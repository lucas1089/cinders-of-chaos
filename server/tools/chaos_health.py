#!/usr/bin/env python3
"""Health alerts for the live server (server/deploy/chaos-health.service, .timer; docs/LAUNCH.md "Monitoring").

The timer runs it every 5 minutes. Each run checks:
  - units active: chaos-server, mariadb (or mysql), chaos-clientservices, chaos-payworker, and nginx / php*-fpm when
    they are installed (CHAOS_HEALTH_UNITS replaces the required list, space separated);
  - the login port (7171) and the game port (7172) accept a TCP connection;
  - the status protocol answers (chaos_watchdog.fetch_status); the player count comes from its <players online=...>;
  - MariaDB answers SELECT 1 with the CHAOS_DB_* credentials (the mysql / mariadb client, password in a 0600 file);
  - free disk on / and on CHAOS_BACKUP_DIR: at least --min-free-pct (10) % and --min-free-gb (5) GB;
  - the newest dump in CHAOS_BACKUP_DIR/db is younger than --backup-max-age (26) hours;
  - the last off-site copy (server/tools/backup_offsite.sh) is younger than 26 hours, only when CHAOS_BACKUP_REMOTE or
    CHAOS_BACKUP_RSYNC is set;
  - error lines in the console log since the last run (Lua errors, stack tracebacks, [Error ...], segfaults).

It posts {"content": ...} to CHAOS_ALERT_WEBHOOK (the same webhook as chaos_crashlog.sh) only when a check changes
state: FAIL when it starts failing, OK when it recovers. Nothing is posted while a state holds. Error lines are counted
and posted at most once per --error-window (30 min) with the first lines. The game checks (chaos-server, ports, status)
must fail --confirm-game (2) runs in a row, and are skipped during the first --grace (300) s after a start, so the daily
restart never alerts. Once a day after --summary-hour (09, server time) it posts a summary: the online peak over 24 h,
backups, crashes and watchdog restarts, error lines, disk, and what is failing now. A post that fails is kept and sent
again by the next run. State: --state (/var/lib/chaos/health.json).

usage: python3 -I server/tools/chaos_health.py [--dry-run] [--test-alert] [--summary-now] [--state FILE] ...
       (--help lists every option)
"""
import argparse
import glob
import json
import os
import re
import shutil
import socket
import subprocess
import sys
import tempfile
import time
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import chaos_watchdog  # noqa: E402

DEFAULT_UNITS = ['chaos-server', 'mariadb|mysql', 'chaos-clientservices', 'chaos-payworker']
OPTIONAL_UNITS = ['nginx', 'php*-fpm']
GAME_CHECKS = ('unit:chaos-server', 'port:login', 'port:game', 'status')
ERROR_RE = re.compile(r'lua script error|stack traceback|\[error\b|segmentation fault|segfault|'
                      r'attempt to (index|call|compare|perform|concatenate)', re.I)
MAX_SCAN = 32 * 1024 * 1024    # read at most this much new log per run; a larger jump skips ahead
MAX_POST = 1900                # webhook messages are cut here (Discord-style hooks refuse more than 2000)
OUTBOX_MAX = 20
DAY = 86400
GB = 1024 ** 3


# ------------------------------------------------------------------ pure logic (unit tested)
def step(prev, result, now, confirm=1):
    """One check's next state and the event to post (None, 'FAIL' or 'OK').
    prev: {'ok', 'fails', 'since', 'detail'} or None (never seen). result: ('ok' | 'fail' | 'skip', detail).
    A check that was never seen and passes is recorded silently; one that fails alerts like any other."""
    status, detail = result
    st = dict(prev) if prev else {'ok': True, 'fails': 0, 'since': now, 'detail': ''}
    if status == 'skip':
        return st, None
    st['detail'] = detail
    if status == 'ok':
        st['fails'] = 0
        if not st['ok']:
            st['ok'], st['since'] = True, now
            return st, 'OK'
        return st, None
    st['fails'] = st.get('fails', 0) + 1
    if st['ok'] and st['fails'] >= confirm:
        st['ok'], st['since'] = False, now
        return st, 'FAIL'
    return st, None


def scan_log(path, pos, max_bytes=MAX_SCAN, keep=5):
    """New error lines in the log since pos ({'ino', 'off'} or None). Returns (pos, count, first lines).
    The first run starts at the end (old lines are not news). A new inode or a shorter file (logrotate copytruncate)
    starts again from the top. Only whole lines are read; a half-written last line waits for the next run."""
    try:
        st = os.stat(path)
    except OSError:
        return pos, 0, []
    if not pos:
        return {'ino': st.st_ino, 'off': st.st_size}, 0, []
    off = pos.get('off', 0)
    if pos.get('ino') != st.st_ino or st.st_size < off:
        off = 0
    if st.st_size - off > max_bytes:
        off = st.st_size - max_bytes
    count, lines = 0, []
    try:
        with open(path, 'rb') as f:
            f.seek(off)
            data = f.read(st.st_size - off)
    except OSError:
        return pos, 0, []
    end = data.rfind(b'\n')
    if end < 0:
        return {'ino': st.st_ino, 'off': off}, 0, []
    for raw in data[:end].split(b'\n'):
        line = raw.decode('utf-8', 'replace').rstrip('\r')
        if ERROR_RE.search(line):
            count += 1
            if len(lines) < keep:
                lines.append(line.strip()[:200])
    return {'ino': st.st_ino, 'off': off + end + 1}, count, lines


def errors_step(err, count, lines, now, window=1800, keep=5):
    """Rate limit for the error-line alert: errors pile up in err['pending'] and are posted at most once per window.
    Returns (err, message or None)."""
    err = dict(err or {})
    err.setdefault('pending', 0)
    err.setdefault('lines', [])
    err.setdefault('last_alert', 0)
    if count:
        err['pending'] += count
        err['lines'] = (err['lines'] + lines)[:keep]
    if err['pending'] and (not err['last_alert'] or now - err['last_alert'] >= window):
        msg = '%d error line(s) in the server log since %s:\n%s' % (
            err['pending'], 'the last alert' if err['last_alert'] else 'monitoring started',
            '\n'.join(err['lines']))
        err.update(pending=0, lines=[], last_alert=now)
        return err, msg
    return err, None


def parse_online(reply):
    """Players online from a status reply (bytes), or None."""
    m = re.search(rb'<players\b[^>]*\bonline="(\d+)"', reply or b'')
    return int(m.group(1)) if m else None


def disk_result(free, total, min_pct, min_gb):
    pct = 100.0 * free / total if total else 0.0
    detail = '%.1f GB free (%.0f %%)' % (free / GB, pct)
    return ('ok' if pct >= min_pct and free >= min_gb * GB else 'fail', detail)


def age_result(mtime, now, max_hours, what):
    if mtime is None:
        return ('fail', 'no %s found' % what)
    hours = (now - mtime) / 3600.0
    detail = 'newest %s %.1f h old' % (what, hours)
    return ('ok' if hours < max_hours else 'fail', detail)


def summary_due(state, now_local, hour):
    """True once a day, at the first run at or after `hour` (server time). now_local: time.struct_time."""
    today = time.strftime('%Y-%m-%d', now_local)
    return now_local.tm_hour >= hour and state.get('summary_day') != today


def trim(samples, now, span=DAY):
    return [s for s in samples if now - s[0] <= span]


# ------------------------------------------------------------------ the machine (replaced by fakes in the tests)
class System:
    def __init__(self, env):
        self.env = env

    def systemctl(self, *args):
        try:
            return subprocess.run(['systemctl'] + list(args), capture_output=True, text=True, timeout=15).stdout
        except (OSError, subprocess.SubprocessError):
            return ''

    def unit_state(self, unit):
        return self.systemctl('is-active', unit).strip() or 'unknown'

    def installed_units(self, pattern):
        """Service names matching a pattern ('nginx', 'php*-fpm') that are installed."""
        out = self.systemctl('list-unit-files', '--type=service', '--no-legend', '--plain', pattern + '.service')
        names = [line.split()[0] for line in out.splitlines() if line.strip()]
        return [n[:-len('.service')] for n in names if n.endswith('.service')]

    def uptime(self, unit):
        return chaos_watchdog.unit_uptime(unit)

    def port_open(self, host, port, timeout=5):
        try:
            with socket.create_connection((host, port), timeout=timeout):
                return True
        except OSError:
            return False

    def status(self, host, port, timeout=10):
        return chaos_watchdog.fetch_status(host, port, timeout)

    def db_ping(self):
        client = shutil.which('mariadb') or shutil.which('mysql')
        if not client:
            return False, 'no mysql / mariadb client installed'
        env = self.env

        def q(v):
            return '"%s"' % v.replace('\\', '\\\\').replace('"', '\\"')
        fd, path = tempfile.mkstemp(prefix='chaos-health-')
        try:
            with os.fdopen(fd, 'w') as f:
                f.write('[client]\n')
                if env.get('CHAOS_DB_HOST'):
                    f.write('host=%s\n' % q(env['CHAOS_DB_HOST']))
                if env.get('CHAOS_DB_PORT'):
                    f.write('port=%s\n' % env['CHAOS_DB_PORT'])
                if env.get('CHAOS_DB_USER'):
                    f.write('user=%s\n' % q(env['CHAOS_DB_USER']))
                if env.get('CHAOS_DB_PASS'):
                    f.write('password=%s\n' % q(env['CHAOS_DB_PASS']))
            cmd = [client, '--defaults-extra-file=' + path, '--connect-timeout=10', '-N', '-B', '-e', 'SELECT 1']
            if env.get('CHAOS_DB_NAME'):
                cmd.append(env['CHAOS_DB_NAME'])
            r = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
        except (OSError, subprocess.SubprocessError) as e:
            return False, str(e)[:200]
        finally:
            os.unlink(path)
        if r.returncode == 0 and r.stdout.strip() == '1':
            return True, 'answers'
        return False, (r.stderr.strip() or 'exit %d' % r.returncode)[:200]

    def disk(self, path):
        u = shutil.disk_usage(path)
        return u.free, u.total, os.stat(path).st_dev

    def post(self, url, text):
        body = json.dumps({'content': text[:MAX_POST]}).encode()
        req = urllib.request.Request(url, data=body, headers={'Content-Type': 'application/json',
                                                              'User-Agent': 'chaos-health/1'})
        try:
            with urllib.request.urlopen(req, timeout=15) as r:
                return 200 <= r.status < 300
        except OSError:
            return False

    def hostname(self):
        return socket.gethostname()


def newest_mtime(pattern):
    best = None
    for f in glob.glob(pattern):
        try:
            m = os.path.getmtime(f)
        except OSError:
            continue
        if best is None or m > best:
            best = m
    return best


def count_since(pattern, since):
    n = 0
    for f in glob.glob(pattern):
        try:
            if os.path.getmtime(f) >= since:
                n += 1
        except OSError:
            pass
    return n


def watchdog_restarts(path, since):
    n = 0
    try:
        with open(path, errors='replace') as f:
            for line in f:
                if 'restarting' not in line:
                    continue
                try:
                    t = time.mktime(time.strptime(line[:19], '%Y-%m-%d %H:%M:%S'))
                except ValueError:
                    continue
                if t >= since:
                    n += 1
    except OSError:
        pass
    return n


# ------------------------------------------------------------------ one run
def run_checks(sysm, opts, env, state, now):
    """Every check as {name: (status, detail)} plus the player count (or None)."""
    res = {}
    units = env.get('CHAOS_HEALTH_UNITS', '').split() or DEFAULT_UNITS
    for spec in units:
        names = spec.split('|')
        present = [n for n in names if sysm.installed_units(n)]
        unit = present[0] if present else names[0]
        st = sysm.unit_state(unit)
        res['unit:' + names[0]] = ('ok' if st == 'active' else 'fail', '%s is %s' % (unit, st))
    for pattern in OPTIONAL_UNITS:
        for unit in sysm.installed_units(pattern):
            st = sysm.unit_state(unit)
            res['unit:' + unit] = ('ok' if st == 'active' else 'fail', '%s is %s' % (unit, st))

    up = sysm.uptime(opts.unit)
    online = None
    if up is None or up < opts.grace:
        why = '%s is not running' % opts.unit if up is None else '%s started %d s ago' % (opts.unit, up)
        for name in ('port:login', 'port:game', 'status'):
            res[name] = ('skip', why)
    else:
        for name, port in (('port:login', opts.login_port), ('port:game', opts.game_port)):
            ok = sysm.port_open(opts.host, port)
            res[name] = ('ok' if ok else 'fail', 'port %d %s' % (port, 'accepts' if ok else 'refuses or times out'))
        reply = sysm.status(opts.host, opts.login_port)
        if chaos_watchdog.is_status_reply(reply):
            online = parse_online(reply)
            res['status'] = ('ok', 'answers, %s online' % ('?' if online is None else online))
        else:
            res['status'] = ('fail', 'no status answer on %d' % opts.login_port)

    ok, detail = sysm.db_ping()
    res['database'] = ('ok' if ok else 'fail', detail)

    seen = {}
    for path in ['/', opts.backup_dir]:
        if not os.path.isdir(path):
            res['disk:' + path] = ('fail', 'missing directory')
            continue
        free, total, dev = sysm.disk(path)
        if dev in seen:
            continue
        seen[dev] = path
        res['disk:' + path] = disk_result(free, total, opts.min_free_pct, opts.min_free_gb)

    res['backup'] = age_result(newest_mtime(os.path.join(opts.backup_dir, 'db', 'chaos-db-*.sql.gz')), now,
                               opts.backup_max_age, 'database dump')
    if env.get('CHAOS_BACKUP_REMOTE') or env.get('CHAOS_BACKUP_RSYNC'):
        stamp = os.path.join(opts.backup_dir, '.offsite_last')
        res['offsite'] = age_result(newest_mtime(stamp), now, opts.backup_max_age, 'off-site copy')
    return res, online


def summary_text(state, opts, now, results):
    since = now - DAY
    samples = state.get('online', [])
    if samples:
        peak = max(samples, key=lambda s: s[1])
        online = 'online peak %d at %s, now %d' % (peak[1], time.strftime('%H:%M', time.localtime(peak[0])),
                                                   samples[-1][1])
    else:
        online = 'online: no status answers in 24 h'
    db = os.path.join(opts.backup_dir, 'db', 'chaos-db-*.sql.gz')
    newest = newest_mtime(db)
    backups = 'backups: %d dump(s) in 24 h, newest %s' % (
        count_since(db, since), 'none' if newest is None else '%.1f h old' % ((now - newest) / 3600.0))
    off = newest_mtime(os.path.join(opts.backup_dir, '.offsite_last'))
    if off is not None:
        backups += ', off-site %.1f h old' % ((now - off) / 3600.0)
    crashes = 'crashes: %d, watchdog restarts: %d' % (
        count_since(os.path.join(opts.crash_dir, 'crash-*.log'), since),
        watchdog_restarts(os.path.join(opts.crash_dir, 'watchdog.log'), since))
    errs = 'error lines in the log: %d' % sum(n for _, n in state.get('errors_seen', []))
    disks = 'disk: ' + ', '.join('%s %s' % (k[5:], v[1]) for k, v in sorted(results.items()) if k.startswith('disk:'))
    failing = [k for k, v in sorted(state.get('checks', {}).items()) if not v.get('ok', True)]
    bad = 'failing now: ' + (', '.join(failing) if failing else 'nothing')
    return 'Daily summary (24 h)\n- ' + '\n- '.join([online, backups, crashes, errs, disks, bad])


def label(name):
    return {'port:login': 'login port', 'port:game': 'game port', 'status': 'status protocol',
            'database': 'database', 'backup': 'local backup', 'offsite': 'off-site backup'}.get(
        name, name.replace('unit:', 'service ').replace('disk:', 'disk '))


def run(sysm, opts, env, state, now, now_local):
    """One full run: returns (new state, messages to post, this run's results)."""
    state = dict(state)
    checks = dict(state.get('checks', {}))
    results, online = run_checks(sysm, opts, env, state, now)
    events = []
    for name, result in sorted(results.items()):
        confirm = opts.confirm_game if name in GAME_CHECKS else 1
        checks[name], ev = step(checks.get(name), result, now, confirm)
        if ev:
            events.append('%s %s: %s' % (ev, label(name), checks[name]['detail']))
    state['checks'] = checks
    msgs = []
    if events:
        msgs.append('\n'.join(events))

    pos, count, lines = scan_log(opts.log, state.get('log_pos'))
    state['log_pos'] = pos
    state['errors'], err_msg = errors_step(state.get('errors'), count, lines, now, opts.error_window)
    if err_msg:
        msgs.append(err_msg)
    seen = trim(state.get('errors_seen', []), now)
    if count:
        seen.append([now, count])
    state['errors_seen'] = seen

    samples = trim(state.get('online', []), now)
    if online is not None:
        samples.append([now, online])
    state['online'] = samples

    if opts.summary_now or summary_due(state, now_local, opts.summary_hour):
        if state.get('last_run') or opts.summary_now:
            msgs.append(summary_text(state, opts, now, results))
        state['summary_day'] = time.strftime('%Y-%m-%d', now_local)   # the very first run only marks the day
    state['last_run'] = now
    return state, msgs, results


def load_state(path):
    try:
        with open(path) as f:
            s = json.load(f)
        return s if isinstance(s, dict) else {}
    except (OSError, ValueError):
        return {}


def save_state(path, state):
    os.makedirs(os.path.dirname(path) or '.', exist_ok=True)
    tmp = path + '.tmp'
    with open(tmp, 'w') as f:
        json.dump(state, f)
    os.replace(tmp, path)


def deliver(sysm, url, prefix, outbox, msgs):
    """Post the outbox then the new messages; whatever fails stays in the outbox (newest OUTBOX_MAX)."""
    queue = list(outbox) + [prefix + m for m in msgs]
    if not url:
        for m in queue:
            print('alert (no CHAOS_ALERT_WEBHOOK set): ' + m)
        return []
    left = []
    for m in queue:
        if left or not sysm.post(url, m):
            left.append(m)
    return left[-OUTBOX_MAX:]


def parse_args(argv, env):
    p = argparse.ArgumentParser(description='Cinders of Chaos health alerts (docs/LAUNCH.md "Monitoring").')
    p.add_argument('--state', default='/var/lib/chaos/health.json')
    p.add_argument('--log', default=env.get('CHAOS_SERVER_LOG', '/var/log/chaos/server.log'))
    p.add_argument('--crash-dir', default=env.get('CHAOS_CRASH_DIR', '/var/log/chaos/crashes'))
    p.add_argument('--backup-dir', default=env.get('CHAOS_BACKUP_DIR', '/var/backups/chaos'))
    p.add_argument('--unit', default='chaos-server')
    p.add_argument('--host', default='127.0.0.1')
    p.add_argument('--login-port', type=int, default=7171)
    p.add_argument('--game-port', type=int, default=7172)
    p.add_argument('--grace', type=float, default=300)
    p.add_argument('--confirm-game', type=int, default=2)
    p.add_argument('--min-free-pct', type=float, default=float(env.get('CHAOS_HEALTH_MIN_FREE_PCT') or 10))
    p.add_argument('--min-free-gb', type=float, default=float(env.get('CHAOS_HEALTH_MIN_FREE_GB') or 5))
    p.add_argument('--backup-max-age', type=float, default=float(env.get('CHAOS_HEALTH_BACKUP_MAX_AGE_H') or 26),
                   help='hours')
    p.add_argument('--error-window', type=float, default=1800, help='seconds between two error-line alerts')
    p.add_argument('--summary-hour', type=int, default=int(env.get('CHAOS_HEALTH_SUMMARY_HOUR') or 9))
    p.add_argument('--summary-now', action='store_true', help='post the daily summary now')
    p.add_argument('--test-alert', action='store_true', help='post one test message and exit')
    p.add_argument('--dry-run', action='store_true', help='print the messages; post nothing, save no state')
    return p.parse_args(argv)


def main(argv, env=None, sysm=None, now=None):
    env = dict(os.environ if env is None else env)
    opts = parse_args(argv, env)
    sysm = sysm or System(env)
    url = env.get('CHAOS_ALERT_WEBHOOK', '').strip()
    prefix = 'Cinders of Chaos health (%s): ' % sysm.hostname()
    if opts.test_alert:
        if not url:
            print('CHAOS_ALERT_WEBHOOK is empty')
            return 1
        ok = sysm.post(url, prefix + 'test alert, the webhook works')
        print('posted' if ok else 'the post failed')
        return 0 if ok else 1
    now = time.time() if now is None else now
    state = load_state(opts.state)
    state, msgs, results = run(sysm, opts, env, state, now, time.localtime(now))
    for name, (status, detail) in sorted(results.items()):
        alerted = '' if state['checks'][name]['ok'] else ' (alerted)'
        print('%-26s %-4s %s%s' % (name, status, detail, alerted))
    if opts.dry_run:
        for m in msgs:
            print('would post: ' + prefix + m)
        return 0
    state['outbox'] = deliver(sysm, url, prefix, state.get('outbox', []), msgs)
    save_state(opts.state, state)
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
