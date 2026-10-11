#!/usr/bin/env python3
"""Tests for chaos_health.py: state changes (alert on FAIL and on recovery only), the error-line scan and its rate
limit, backup ages, disk thresholds, the daily summary and the outbox, against fake services, a temporary log and fake
backup files. Run: python3 -I server/tools/chaos_health_test.py"""
import contextlib
import io
import os
import shutil
import sys
import tempfile
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import chaos_health as H  # noqa: E402

checks = 0


def ok(cond, what):
    global checks
    checks += 1
    if not cond:
        print('FAIL: ' + what)
        sys.exit(1)


GB = H.GB
REPLY = b'<?xml version="1.0"?><tsqp version="1.0"><players online="17" max="500" peak="20"/></tsqp>'


class FakeSystem:
    """Every service up, both ports open, the status answering with 17 online, the database up, 100 of 200 GB free."""
    def __init__(self):
        self.units = {'chaos-server': 'active', 'mariadb': 'active', 'chaos-clientservices': 'active',
                      'chaos-payworker': 'active', 'nginx': 'active', 'php8.3-fpm': 'active'}
        self.up = 3600
        self.ports = {7171: True, 7172: True}
        self.reply = REPLY
        self.db = (True, 'answers')
        self.free = {}           # path -> free bytes (default 100 GB)
        self.posts = []
        self.post_ok = True

    def unit_state(self, unit):
        return self.units.get(unit, 'inactive')

    def installed_units(self, pattern):
        if pattern == 'php*-fpm':
            return [u for u in self.units if u.startswith('php')]
        return [pattern] if pattern in self.units else []

    def uptime(self, unit):
        return self.up if self.units.get(unit) == 'active' else None

    def port_open(self, host, port, timeout=5):
        return self.ports.get(port, False)

    def status(self, host, port, timeout=10):
        return self.reply

    def db_ping(self):
        return self.db

    def disk(self, path):
        return self.free.get(path, 100 * GB), 200 * GB, hash(path)

    def post(self, url, text):
        if self.post_ok:
            self.posts.append(text)
        return self.post_ok

    def hostname(self):
        return 'test'


tmp = tempfile.mkdtemp(prefix='chaos-health-test-')
try:
    backup = os.path.join(tmp, 'backups')
    crash = os.path.join(tmp, 'crashes')
    os.makedirs(os.path.join(backup, 'db'))
    os.makedirs(crash)
    log = os.path.join(tmp, 'server.log')
    state_file = os.path.join(tmp, 'health.json')
    open(log, 'w').close()
    T0 = time.mktime((2026, 10, 31, 8, 0, 0, 0, 0, -1))   # 08:00 local, before the summary hour

    def dump(age_h, name='chaos-db-chaos-20261031-000000.sql.gz', now=T0):
        p = os.path.join(backup, 'db', name)
        open(p, 'w').close()
        os.utime(p, (now - age_h * 3600, now - age_h * 3600))
        return p

    dump(2)
    ENV = {'CHAOS_ALERT_WEBHOOK': 'http://hook.invalid/x', 'CHAOS_BACKUP_DIR': backup}
    ARGS = ['--state', state_file, '--log', log, '--crash-dir', crash, '--backup-dir', backup]
    fake = FakeSystem()

    def go(now, extra=(), env=None, summaries=False):
        """One run; the posts it made (the daily summary only with summaries=True)."""
        before = len(fake.posts)
        with contextlib.redirect_stdout(io.StringIO()):     # the per-check table goes to the journal, not here
            H.main(ARGS + list(extra), env=dict(ENV if env is None else env), sysm=fake, now=now)
        return [p for p in fake.posts[before:] if summaries or 'Daily summary' not in p]

    def state():
        return H.load_state(state_file)

    # --- pure: step()
    s, ev = H.step(None, ('ok', 'fine'), 100)
    ok(ev is None and s['ok'], 'a new check that passes is recorded silently')
    s, ev = H.step(s, ('fail', 'down'), 200)
    ok(ev == 'FAIL' and not s['ok'] and s['since'] == 200, 'ok -> fail alerts')
    s, ev = H.step(s, ('fail', 'still down'), 300)
    ok(ev is None and s['detail'] == 'still down', 'a failure that holds does not alert again')
    s, ev = H.step(s, ('skip', 'grace'), 400)
    ok(ev is None and not s['ok'], 'a skipped run keeps the state')
    s, ev = H.step(s, ('ok', 'back'), 500)
    ok(ev == 'OK' and s['ok'], 'fail -> ok alerts the recovery')
    s, ev = H.step(None, ('fail', 'down'), 100)
    ok(ev == 'FAIL', 'a check that fails on its first run alerts')
    s, ev = H.step(None, ('fail', 'x'), 100, confirm=2)
    ok(ev is None and s['fails'] == 1, 'confirm 2: the first miss waits')
    s, ev = H.step(s, ('fail', 'x'), 200, confirm=2)
    ok(ev == 'FAIL', 'confirm 2: the second miss in a row alerts')
    s, ev = H.step(None, ('fail', 'x'), 100, confirm=2)
    s, ev = H.step(s, ('ok', 'y'), 200, confirm=2)
    s, ev = H.step(s, ('fail', 'x'), 300, confirm=2)
    ok(ev is None, 'confirm 2: a pass in between resets the count')

    # --- pure: helpers
    ok(H.parse_online(REPLY) == 17 and H.parse_online(b'<tsqp></tsqp>') is None, 'player count from the status reply')
    ok(H.disk_result(20 * GB, 100 * GB, 10, 5)[0] == 'ok', '20 % and 20 GB free is fine')
    ok(H.disk_result(4 * GB, 10 * GB, 10, 5)[0] == 'fail', 'under 5 GB fails even at 40 %')
    ok(H.disk_result(9 * GB, 100 * GB, 10, 5)[0] == 'fail', 'under 10 % fails even at 9 GB')
    ok(H.age_result(None, 0, 26, 'x')[0] == 'fail', 'no backup at all fails')
    ok(H.age_result(T0 - 25 * 3600, T0, 26, 'x')[0] == 'ok' and H.age_result(T0 - 27 * 3600, T0, 26, 'x')[0] == 'fail',
       'the backup age limit is 26 h')
    e, m = H.errors_step({}, 3, ['a', 'b', 'c'], 1000, 1800)
    ok(m and m.startswith('3 error line(s)') and e['pending'] == 0, 'the first errors post at once')
    e, m = H.errors_step(e, 2, ['d', 'e'], 1500, 1800)
    ok(m is None and e['pending'] == 2, 'more errors inside 30 min wait')
    e, m = H.errors_step(e, 0, [], 2000, 1800)
    ok(m is None, 'still inside the window')
    e, m = H.errors_step(e, 0, [], 2800, 1800)
    ok(m and m.startswith('2 error line(s)') and 'd\ne' in m, 'the waiting errors post when the window ends')

    # --- run 1: all up, first run: nothing is posted
    out = go(T0)
    ok(out == [], 'all up on the first run: no post')
    st = state()
    ok(all(c['ok'] for c in st['checks'].values()), 'every check passes')
    for name in ('unit:chaos-server', 'unit:mariadb', 'unit:chaos-clientservices', 'unit:chaos-payworker', 'unit:nginx',
                 'unit:php8.3-fpm', 'port:login', 'port:game', 'status', 'database', 'disk:/', 'disk:' + backup,
                 'backup'):
        ok(name in st['checks'], 'checked: ' + name)
    ok('offsite' not in st['checks'], 'no off-site check without a remote')
    ok(st['online'][-1][1] == 17, 'the player count is sampled')

    # --- the database goes down: one FAIL, then silence, then one OK
    fake.db = (False, 'Access denied')
    out = go(T0 + 300)
    ok(len(out) == 1 and 'FAIL database: Access denied' in out[0], 'the database failure alerts once')
    ok(go(T0 + 600) == [], 'no repeat while it stays down')
    fake.db = (True, 'answers')
    out = go(T0 + 900)
    ok(len(out) == 1 and 'OK database' in out[0], 'the recovery alerts once')
    ok(go(T0 + 1200) == [], 'quiet again')

    # --- the game port: confirm 2 (one miss is not an alert)
    fake.ports[7172] = False
    ok(go(T0 + 1500) == [], 'first game port miss: no alert')
    out = go(T0 + 1800)
    ok(len(out) == 1 and 'FAIL game port' in out[0], 'second miss in a row alerts')
    fake.ports[7172] = True
    ok('OK game port' in go(T0 + 2100)[0], 'the game port recovers')

    # --- the daily restart: chaos-server just started, the ports and status are skipped (no alert)
    fake.up = 30
    fake.ports[7171] = fake.ports[7172] = False
    fake.reply = b''
    ok(go(T0 + 2400) == [] and go(T0 + 2700) == [], 'the grace period skips the game checks')
    fake.up = 3600
    fake.ports[7171] = fake.ports[7172] = True
    fake.reply = REPLY

    # --- a service stops (website php-fpm): alert, recovery
    fake.units['php8.3-fpm'] = 'failed'
    out = go(T0 + 3000)
    ok(len(out) == 1 and 'FAIL service php8.3-fpm' in out[0], 'a stopped service alerts')
    fake.units['php8.3-fpm'] = 'active'
    ok('OK service php8.3-fpm' in go(T0 + 3300)[0], 'and recovers')

    # --- error lines in the log, rate limited to one alert per 30 min
    with open(log, 'a') as f:
        f.write('normal line\nLua Script Error: [Action Interface]\ndata/x.lua:1: attempt to index a nil value\n'
                'stack traceback:\n')
    out = go(T0 + 3600)
    ok(len(out) == 1 and out[0].count('\n') >= 3 and '3 error line(s)' in out[0], 'new errors alert with the lines')
    with open(log, 'a') as f:
        f.write('[Error - mysql_real_query] Query: SELECT\n')
    ok(go(T0 + 3900) == [], 'a new error inside 30 min waits')
    with open(log, 'a') as f:
        f.write('half a li')                       # no newline yet: not read
    ok(go(T0 + 5400) and '1 error line(s)' in fake.posts[-1], 'after 30 min the waiting error is posted')
    ok(go(T0 + 5700) == [], 'nothing new: no post')
    with open(log, 'w') as f:                       # logrotate copytruncate: the file starts again
        f.write('Segmentation fault\n')
    out = go(T0 + 9000)
    ok(len(out) == 1 and 'Segmentation fault' in out[0], 'a truncated log is read again from the top')

    # --- the backup gets old, then a new one comes
    for f in os.listdir(os.path.join(backup, 'db')):
        os.remove(os.path.join(backup, 'db', f))
    dump(30, now=T0 + 9300)
    out = go(T0 + 9300)
    ok(len(out) == 1 and 'FAIL local backup' in out[0], 'a dump older than 26 h alerts')
    dump(0, 'chaos-db-chaos-new.sql.gz', now=T0 + 9600)
    ok('OK local backup' in go(T0 + 9600)[0], 'a fresh dump recovers')

    # --- off-site: only checked when a remote is configured
    env = dict(ENV, CHAOS_BACKUP_REMOTE='b2:chaos-backups')
    out = go(T0 + 9900, env=env)
    ok(len(out) == 1 and 'FAIL off-site backup: no off-site copy found' in out[0], 'remote set, no copy: alert')
    stamp = os.path.join(backup, '.offsite_last')
    open(stamp, 'w').close()
    os.utime(stamp, (T0 + 10200, T0 + 10200))
    ok('OK off-site backup' in go(T0 + 10200, env=env)[0], 'a fresh off-site copy recovers')

    # --- disk: the backup dir runs low
    fake.free[backup] = 2 * GB
    out = go(T0 + 10500, env=env)
    ok(len(out) == 1 and 'FAIL disk ' + backup in out[0], 'low disk on the backup dir alerts')
    fake.free[backup] = 100 * GB
    go(T0 + 10800, env=env)

    # --- the webhook is down: the alert waits in the outbox and goes out on the next run
    fake.post_ok = False
    fake.db = (False, 'gone')
    go(T0 + 11100, env=env)
    ok(len(state()['outbox']) == 1, 'a failed post is kept')
    fake.post_ok = True
    out = go(T0 + 11400, env=env)
    ok(len(out) == 1 and 'FAIL database' in out[0] and state()['outbox'] == [], 'and sent on the next run, once')
    fake.db = (True, 'answers')
    go(T0 + 11700, env=env)

    # --- daily summary: once, after 09:00 (T0 is 08:00; T0 + 3600 s was 09:00, so it already went out)
    ok(any(p.startswith('Cinders of Chaos health (test): Daily summary') for p in fake.posts),
       'the summary went out after 09:00')
    ok(sum('Daily summary' in p for p in fake.posts) == 1, 'only once that day')
    T1 = T0 + 86400 + 3600                           # next day 09:00
    crash_file = os.path.join(crash, 'crash-20261101-030000.log')
    with open(crash_file, 'w') as f:
        f.write('x')
    os.utime(crash_file, (T1 - 6 * 3600, T1 - 6 * 3600))
    with open(os.path.join(crash, 'watchdog.log'), 'w') as f:
        f.write(time.strftime('%Y-%m-%d %H:%M:%S', time.localtime(T1 - 3600)) +
                ' no status answer 3 times in a row: restarting chaos-server\n')
    fake.reply = REPLY.replace(b'"17"', b'"42"')
    out = go(T1, env=env, summaries=True)
    summ = [p for p in out if 'Daily summary' in p]
    ok(len(summ) == 1, 'the next day has its own summary')
    ok('online peak 42' in summ[0] and 'crashes: 1, watchdog restarts: 1' in summ[0] and 'off-site' in summ[0] and 'disk:' in summ[0],
       'the summary has the peak, crashes, backups and disk: ' + summ[0])
    ok(go(T1 + 300, env=env, summaries=True) == [], 'no second summary the same day')
    out = go(T1 + 600, ['--summary-now'], env=env, summaries=True)
    ok(len(out) == 1 and 'Daily summary' in out[0], '--summary-now forces one')

    # --- the first run after 09:00 on a fresh state only marks the day (no summary at install time)
    os.remove(state_file)
    ok(go(T1 + 900, env=env, summaries=True) == [], 'a fresh install posts nothing')

    # --- --dry-run posts nothing and saves nothing
    os.remove(state_file)
    fake.db = (False, 'down')
    ok(go(T1 + 1200, ['--dry-run'], env=env) == [] and not os.path.exists(state_file), 'dry run is read only')

    # --- no webhook: the alert is printed, nothing kept
    go(T1 + 1500, env={'CHAOS_BACKUP_DIR': backup})
    ok(state()['outbox'] == [], 'without a webhook nothing piles up')
finally:
    shutil.rmtree(tmp)

print('chaos_health: %d checks passed' % checks)
