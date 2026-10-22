#!/usr/bin/env python3
"""Tests for server/deploy/chaos-ctl.sh (docs/ADMIN_APP.md).

Runs the real script as the current user (CHAOS_CTL_NO_SUDO=1) against a throwaway server folder and stubs for
systemctl and mysql: the status lines, the remote.cmd lines each command queues, the refusals (a bad number, a bad tag, a
second line in a broadcast, a key that is not one ssh public key line, an unknown command) and that a refused command
queues nothing. Only refused install-admin inputs are run, and adduser / visudo / install are stubs too, so the test
never creates a user or touches sudoers.

The settings file (/etc/chaos/ctl.conf, here CHAOS_CTL_CONF): its keys are used, the environment wins, unknown keys and
unsafe values are ignored and never run, a file writable by group or others is ignored as a whole. A missing unit stops
start / stop / restart with exit 5 and "unit-not-found". With a live engine pid file, save signals that pid (never the
unit's main process). CHAOS_DB_SOCKET and CHAOS_MYSQL reach the database client;
a missing client exits 127 with "mysql-not-found".

Tester bots (testers start | stop | status | report | cleanup, with a stub testers.py): the refusals (development key
allowed in config.lua, no key file, a key file readable by others, N over 150, a helper not loaded without --restart),
the helper copied into data/scripts and removed by stop, the run in its own process group that stop ends, the key file
path and never a key or the database password on a command line, cleanup waiting after a stop, --yes for deleting.

The admin commands of 2026-10-21: xp-rate (show, set with and without restart, reset, refusals), backups, health,
cleanup (lists, then removes only old work folders, srvNN and engine backups beyond the newest 2), account-create /
account-password (the password from stdin, a PBKDF2 hash to the database client on stdin, never on a command line),
gm-logs (the command log of one staff member newest first, the audit rows, no link out of the folder, a quote
escaped), and the kit's update-check / update-apply / update-status refusals and settings.

usage: python3 -I server/deploy/chaos_ctl_test.py
"""
import os
import re
import stat
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(HERE, 'chaos-ctl.sh')

SYSTEMCTL = '''#!/usr/bin/env bash
echo "systemctl $*" >> "$STUB/calls"
case "$*" in
  *LoadState*) if [ -n "${STUB_NOUNIT:-}" ]; then echo not-found; else echo loaded; fi ;;
  is-active*) if [ -n "${STUB_NOUNIT:-}" ]; then echo inactive; exit 4; else echo active; fi ;;
  show*) echo "Tue 2026-10-20 06:00:01 UTC" ;;
  *) [ -z "${STUB_NOUNIT:-}" ] || { echo "Failed to $1 $2.service: Unit $2.service not found." >&2; exit 5; } ;;
esac
exit 0
'''
MYSQL = '''#!/usr/bin/env bash
echo "$(basename "$0") $*" >> "$STUB/calls"
# where it connects (never the password line)
grep -E '^(socket|host|port)=' "${1#--defaults-extra-file=}" | sed 's/^/  cnf /' >> "$STUB/calls"
case " $* " in *" -e "*) ;; *) cat > "$STUB/stdin" ;; esac
case "$*" in
  *"FROM accounts"*) echo "${STUB_ACCOUNTS:-0}" ;;
  *"DISTINCT player_name"*) echo Gma; echo "Bad;Name" ;;
  *chaos_admin_log*) printf '2026-10-21 10:00\\tGma\\tplayers.kick\\tBob\\tok\\tdone\\n' ;;
  *COUNT*) echo 7 ;;
  *players_online*) printf 'Bob\\t120\\t3\\n' ;;
esac
'''
NOOP = '''#!/usr/bin/env bash
echo "$(basename "$0") $*" >> "$STUB/calls"
echo "stub $(basename "$0") must not run" >&2
exit 1
'''

failures = 0


def check(cond, label):
    global failures
    if not cond:
        failures += 1
        print('FAIL', label)


def main():
    with tempfile.TemporaryDirectory() as tmp:
        stub = os.path.join(tmp, 'stub')
        server = os.path.join(tmp, 'server')
        os.makedirs(stub)
        os.makedirs(server)
        for name, body in (('systemctl', SYSTEMCTL), ('mysql', MYSQL), ('kitmysql', MYSQL), ('adduser', NOOP),
                           ('visudo', NOOP), ('install', NOOP)):
            p = os.path.join(stub, name)
            with open(p, 'w') as f:
                f.write(body)
            os.chmod(p, os.stat(p).st_mode | stat.S_IXUSR)
        env_file = os.path.join(tmp, 'chaos.env')
        with open(env_file, 'w') as f:
            f.write('CHAOS_DB_USER=chaos\nCHAOS_DB_PASS=secret\nCHAOS_DB_NAME=chaos\nCHAOS_BACKUP_DIR=%s\n' % tmp)
        log = os.path.join(tmp, 'server.log')
        with open(log, 'w') as f:
            f.write('\n'.join('line %d' % i for i in range(100)) + '\nLua Script Error: boom\n')
        conf = os.path.join(tmp, 'ctl.conf')
        env = dict(os.environ, PATH=stub + ':' + os.environ['PATH'], STUB=stub, CHAOS_CTL_NO_SUDO='1',
                   CHAOS_SERVER_DIR=server, CHAOS_ENV=env_file, CHAOS_LOG=log,
                   CHAOS_UPDATE_LOG=os.path.join(tmp, 'u.log'), CHAOS_REPO=os.path.join(tmp, 'repo'),
                   CHAOS_CTL_CONF=conf, CHAOS_PID_FILE=os.path.join(tmp, 'no.pid'), CHAOS_MYSQL='mysql')
        for k in ('SUDO_USER', 'CHAOS_UNIT', 'CHAOS_ROOT', 'CHAOS_DB_SOCKET', 'CHAOS_BACKUP_DIR'):
            env.pop(k, None)

        def run(*args, stdin=None, extra=None):
            e = dict(env, **(extra or {}))
            return subprocess.run(['bash', SCRIPT] + list(args), env=e, input=stdin, capture_output=True, text=True)

        def spool():
            p = os.path.join(server, 'remote.cmd')
            return open(p).read() if os.path.exists(p) else ''

        def calls():
            p = os.path.join(stub, 'calls')
            return open(p).read() if os.path.exists(p) else ''

        r = run('status')
        out = dict(l.split('=', 1) for l in r.stdout.splitlines() if '=' in l)
        check(r.returncode == 0, 'status runs')
        check(out.get('service') == 'active', 'status: service')
        check(out.get('players') == '7', 'status: players from the database')
        check(out.get('errors') == '1', 'status: one Lua error in the log')
        check(out.get('backup') == 'none', 'status: no backup yet')
        check(out.get('unit') == 'chaos-server' and out.get('unit_state') == 'loaded', 'status: unit and its state')
        check(out.get('pid') == '', 'status: no engine pid file')
        check('cnf host=127.0.0.1' in calls(), 'mysql: TCP host by default')
        check('secret' not in calls(), 'the database password is never on a command line')

        r = run('logs', '5')
        check(r.stdout.count('\n') == 5, 'logs 5: five lines')
        check(run('logs', 'x').returncode != 0, 'logs: N must be a number')
        check(run('logs', '9999').stdout.count('\n') <= 102, 'logs: capped')
        r = run('errors')
        check('Lua Script Error' in r.stdout and 'line 3' not in r.stdout, 'errors: only the error lines')
        check('Bob' in run('players').stdout, 'players: from players_online')
        check("WHEN 1 THEN 'Mystic'" in calls() and "WHEN 19 THEN 'Iron Sage'" in calls(),
              'players: the class name, not the vocation id')

        # the class names cover every vocation of docs/CLASSES.md and the server's vocation files, with the same names
        r = run('vocations')
        vocs = dict(l.split('=', 1) for l in r.stdout.splitlines())
        repo = os.path.dirname(os.path.dirname(HERE))
        xml_vocs = {}
        for name in os.listdir(os.path.join(repo, 'server', 'data', 'XML')):
            if name.startswith('chaos_vocations') and name.endswith('.xml'):
                text = open(os.path.join(repo, 'server', 'data', 'XML', name)).read()
                for m in re.finditer(r'<vocation\s+id="(\d+)"[^>]*?\sname="([^"]+)"', text):
                    xml_vocs[m.group(1)] = m.group(2)
        check(len(xml_vocs) >= 20, 'vocation files found: %d' % len(xml_vocs))
        for vid, vname in xml_vocs.items():
            check(vocs.get(vid) == vname, 'vocations: id %s is %r, not %r' % (vid, vname, vocs.get(vid)))
        check(vocs.get('0') == 'None', 'vocations: 0 is None')
        classes = open(os.path.join(repo, 'docs', 'CLASSES.md')).read()
        doc_ids = set(re.findall(r'^ *\| (\d+) \| [A-Z][a-z]', classes, re.M))
        doc_ids |= set(re.findall(r'(\d+) (?:Necromancer|Lich|Bone Lord) \(', classes))
        check(len(doc_ids) >= 20, 'docs/CLASSES.md vocation ids found: %d' % len(doc_ids))
        for vid in sorted(doc_ids, key=int):
            check(vid in vocs, 'vocations: docs/CLASSES.md id %s has a name' % vid)
        for vid, vname in vocs.items():
            check(vid == '0' or re.search(r'\b%s\b' % re.escape(vname), classes), 'vocations: %s is in docs/CLASSES.md' % vname)

        check(run('broadcast', 'Back', 'in', '5').returncode == 0, 'broadcast queues')
        check(run('kick', 'Bob').returncode == 0, 'kick queues')
        check(run('close').returncode == 0 and run('open').returncode == 0, 'close and open queue')
        check(spool() == 'broadcast Back in 5\nkick Bob\nclose\nopen\n',
              'remote.cmd holds exactly those lines: ' + repr(spool()))
        before = spool()
        check(run('broadcast', 'a\nsave').returncode != 0, 'a second line inside a broadcast is refused')
        check(run('broadcast').returncode != 0, 'broadcast without text is refused')
        check(spool() == before, 'refused commands queue nothing')

        r = run('restart', '0')
        check(r.returncode == 0 and 'systemctl restart chaos-server' in calls(), 'restart now')
        check(run('restart', 'abc').returncode != 0, 'restart: seconds must be a number')
        check(run('restart', '5000').returncode != 0, 'restart: at most 900 seconds')
        check(run('save').returncode == 0 and 'kill -s SIGUSR1' in calls(), 'save sends SIGUSR1')
        check(run('update', '--bad;x', 'now').returncode != 0, 'update: a bad tag is refused')
        check(run('update', 'v1..2', 'now').returncode != 0, 'update: ".." in a tag is refused')
        check(run('update', 'v1.2', 'later').returncode != 0, 'update: now or at-save')
        check(run('rollback').returncode != 0, 'rollback: now or at-save')
        check(run('bogus').returncode != 0, 'unknown command')
        check('usage: chaos-ctl.sh' in run('help').stdout, 'help prints the usage')

        # publish-update: release tags only, settings of ctl.conf passed on, runs in the background into publish-log
        plog = os.path.join(tmp, 'publish.log')
        pdir = os.path.join(tmp, 'repo', 'server', 'deploy')
        os.makedirs(pdir, exist_ok=True)
        pub = os.path.join(pdir, 'publish_client_update.sh')
        with open(pub, 'w') as f:
            f.write('#!/usr/bin/env bash\necho "args $*"\necho "site=${CHAOS_SITE_DIR:-} key=${CHAOS_UPDATE_KEY:-}"\n')
        os.chmod(pub, 0o755)
        pe = {'CHAOS_PUBLISH_LOG': plog, 'CHAOS_SITE_DIR': '/srv/site'}
        for bad in (('publish-update',), ('publish-update', '/tmp/x.zip'), ('publish-update', 'a;b'),
                    ('publish-update', 'v1..2'), ('publish-update', 'winpkg-46', '--version', 'x'),
                    ('publish-update', 'winpkg-46', '--key', '/tmp/k')):
            check(run(*bad, extra=pe).returncode != 0, 'publish-update refuses %r' % (bad,))
        r = run('publish-update', 'winpkg-46', '--min-package', '11', extra=pe)
        check(r.returncode == 0 and 'publish-log' in r.stdout, 'publish-update starts: ' + r.stdout + r.stderr)
        for _ in range(50):
            if os.path.exists(plog) and 'site=' in open(plog).read():
                break
            time.sleep(0.1)
        out = run('publish-log', extra=pe).stdout
        check('args --min-package 11 -- winpkg-46' in out and 'site=/srv/site key=' in out,
              'publish-update passes the tag, the options and the settings: ' + out)


        # catalog and panel: a thread plays the engine and answers what the script queued
        import threading

        def engine(kind):
            def go():
                for _ in range(40):
                    time.sleep(0.1)
                    m = re.findall(r'^(catalog .*|panel (\d+) .*)$', spool(), re.M)
                    if kind == 'catalog' and any(x[0].startswith('catalog ') for x in m):
                        open(os.path.join(server, 'remote.catalog'), 'w').write('{"categories":[]}')
                        return
                    if kind == 'panel' and any(x[0].startswith('panel ') for x in m):
                        rid = [x[1] for x in m if x[0].startswith('panel ')][-1]
                        with open(os.path.join(server, 'remote.result'), 'w') as f:
                            f.write('{"rid":%s,"ok":true,"message":"done"}\n' % rid)
                        return
            t = threading.Thread(target=go)
            t.start()
            return t

        before = spool()
        t = engine('catalog')
        r = run('catalog', 'Gma')
        t.join()
        check(r.returncode == 0 and r.stdout.strip() == '{"categories":[]}', 'catalog prints the answer: ' + r.stdout)
        check(spool() == before + 'catalog Gma\n', 'catalog queues one line')
        t = engine('panel')
        r = run('panel', 'Gma', 'players.kick', '{"player":"Bob"}')
        t.join()
        check(r.returncode == 0 and '"message":"done"' in r.stdout, 'panel prints its answer: ' + r.stdout)
        check(re.search(r'panel \d{9} players\.kick\|Gma\|\{"player":"Bob"\}\n$', spool()) is not None, 'panel queues its line')
        before = spool()
        for bad in (('catalog', 'x'), ('catalog', 'Gma;x'), ('panel', 'Gma', 'a b', '{}'), ('panel', 'Gma', '../x', '{}'),
                    ('panel', 'Gma', 'a.b', '[]'), ('panel', 'Gma', 'a.b', '{' + 'x' * 950 + '}'), ('panel', 'G', 'a.b', '{}')):
            check(run(*bad).returncode != 0, 'refused: %r' % (bad[:3],))
        check(spool() == before, 'refused panel commands queue nothing')

        for bad in ('not a key', 'ssh-rsa AAAA\nssh-rsa BBBB', 'ssh-rsa AAAA; rm -rf /', ''):
            r = run('install-admin', '-', stdin=bad)
            check(r.returncode != 0, 'install-admin refuses %r' % bad[:20])
        check('adduser' not in calls() and 'visudo' not in calls(), 'a refused key creates no user')

        # ---- errors: per server start, identical lines counted once, older starts only on request
        runs_log = os.path.join(tmp, 'runs.log')
        with open(runs_log, 'w') as f:
            f.write('Starting the game server (2026-10-16 07:00:00). Ctrl+C or ./stop-server.sh stops it.\n'
                    '>> Loading config\n'
                    + 'MySQL error: Lost connection to server during query\n' * 56
                    + 'Starting the game server (2026-10-20 08:00:01). Ctrl+C or ./stop-server.sh stops it.\n'
                    '>> Loading config\nServer Online\n'
                    + ('Lua Script Error: [Event Interface]\ndata/events/scripts/player.lua:Player@onLook\n'
                       'attempt to index a nil value\nnormal line\n') * 3
                    + '[2026-10-20 09:15:02] Exception: bad thing\n[2026-10-20 09:16:40] Exception: bad thing\n')
        awks = []
        for name in ('mawk', 'gawk', 'busybox'):
            path = subprocess.run(['bash', '-c', 'command -v ' + name], capture_output=True, text=True).stdout.strip()
            if path:
                d = os.path.join(tmp, 'awk-' + name)
                os.makedirs(d)
                if name == 'busybox':
                    with open(os.path.join(d, 'awk'), 'w') as f:
                        f.write('#!/bin/sh\nexec %s awk "$@"\n' % path)
                    os.chmod(os.path.join(d, 'awk'), 0o755)
                else:
                    os.symlink(path, os.path.join(d, 'awk'))
                awks.append((name, d))
        check(awks, 'an awk to test with')
        for name, d in awks:
            extra = {'CHAOS_LOG': runs_log, 'PATH': d + ':' + env['PATH']}
            r = run('errors', extra=extra)
            lines = r.stdout.splitlines()
            check(r.returncode == 0, '%s errors runs: %s' % (name, r.stderr))
            check(lines[:1] == ['@run 2026-10-20 08:00:01 current'], '%s errors: the current start first: %r' % (name, lines[:1]))
            check('3x Lua Script Error: [Event Interface] | data/events/scripts/player.lua:Player@onLook | '
                  'attempt to index a nil value' in lines, '%s errors: a Lua error with its two lines, counted: %r' % (name, lines))
            check('2x Exception: bad thing [2026-10-20 09:16:40]' in lines, '%s errors: timestamps kept apart: %r' % (name, lines))
            check(not any('MySQL' in l for l in lines), '%s errors: an older start is hidden by default' % name)
            check(lines[-1:] == ['@older 1'], '%s errors: says one older start had errors: %r' % (name, lines[-1:]))
            r = run('errors', 'all', extra=extra)
            check('@run 2026-10-16 07:00:00' in r.stdout and '56x MySQL error: Lost connection to server during query' in r.stdout,
                  '%s errors all: the older start, counted: %r' % (name, r.stdout))
            check(r.stdout.index('2026-10-16') < r.stdout.index('2026-10-20 08'), '%s errors all: oldest first' % name)
            r = run('errors', '1', extra=extra)
            check(r.stdout.count('x ') == 1 and 'Exception' in r.stdout, '%s errors 1: only the newest entry' % name)
            out = dict(l.split('=', 1) for l in run('status', extra=extra).stdout.splitlines() if '=' in l)
            check(out.get('errors') == '5', '%s status: errors since the last start: %r' % (name, out.get('errors')))
        check(run('errors', 'x').returncode != 0, 'errors: N must be a number')

        # ---- the settings file (/etc/chaos/ctl.conf): sudo drops the environment, so the app only sees this file
        def status(extra=None):
            r = run('status', extra=extra)
            return dict(l.split('=', 1) for l in r.stdout.splitlines() if '=' in l), r

        def write_conf(text, mode=0o644):
            with open(conf, 'w') as f:
                f.write(text)
            os.chmod(conf, mode)

        marker = os.path.join(tmp, 'pwned')
        write_conf('# the Linux kit\nCHAOS_UNIT=chaos-trial\nCHAOS_DB_SOCKET="/opt/chaos-trial/run/mariadb.sock"\n'
                   'CHAOS_MYSQL=kitmysql\nCHAOS_LOG=$(touch %s)\nCHAOS_ROOT=/a b\nPATH=/evil\nnot a line\n' % marker)
        env.pop('CHAOS_MYSQL')
        out, r = status()
        check(out.get('unit') == 'chaos-trial', 'ctl.conf: CHAOS_UNIT is used: %r' % out.get('unit'))
        check(not os.path.exists(marker), 'ctl.conf: a value is never run')
        check(r.stderr.count('ignored') == 4, 'ctl.conf: the unsafe lines are ignored with a warning: ' + r.stderr)
        check(out.get('errors') == '1', 'ctl.conf: an ignored CHAOS_LOG keeps the log of the environment')
        check('kitmysql' in calls() and 'cnf socket=/opt/chaos-trial/run/mariadb.sock' in calls(),
              'ctl.conf: CHAOS_MYSQL and CHAOS_DB_SOCKET reach the database client')
        out, _ = status({'CHAOS_UNIT': 'from-env'})
        check(out.get('unit') == 'from-env', 'the environment wins over ctl.conf')
        r = run('restart', '0')
        check(r.returncode == 0 and 'systemctl restart chaos-trial' in calls(), 'ctl.conf: restart uses its unit')
        out, _ = status({'SUDO_USER': 'someone'})
        check(out.get('unit') == 'chaos-server', 'CHAOS_CTL_CONF is not honoured under sudo')
        write_conf('CHAOS_UNIT=chaos-trial\n', 0o664)
        out, r = status()
        check(out.get('unit') == 'chaos-server' and 'writable' in r.stderr, 'a group-writable ctl.conf is ignored')
        os.remove(conf)
        env['CHAOS_MYSQL'] = 'mysql'

        r = run('players', extra={'CHAOS_MYSQL': os.path.join(tmp, 'no-such-client')})
        check(r.returncode == 127 and 'mysql-not-found' in r.stderr and 'CHAOS_MYSQL' in r.stderr,
              'no database client: exit 127 and mysql-not-found: ' + r.stderr)
        out, _ = status({'CHAOS_MYSQL': os.path.join(tmp, 'no-such-client')})
        check(out.get('players') == '?' and out.get('service') == 'active', 'no database client: status still answers')

        # ---- a unit that does not exist (systemctl exit 5): a clear message, nothing run
        before = calls()
        for args in (('start',), ('stop',), ('restart', '0'), ('restart', '30')):
            r = run(*args, extra={'STUB_NOUNIT': '1'})
            check(r.returncode == 5 and 'unit-not-found' in r.stderr and 'CHAOS_UNIT' in r.stderr,
                  'no unit: %s says unit-not-found (exit %d): %s' % (args[0], r.returncode, r.stderr))
        new = calls()[len(before):]
        check('systemctl start' not in new and 'systemctl restart' not in new and 'systemctl stop' not in new,
              'no unit: nothing started or stopped')
        out, _ = status({'STUB_NOUNIT': '1'})
        check(out.get('unit_state') == 'not-found', 'status: unit_state=not-found')

        # ---- the engine pid file of the Linux kit: save signals the engine itself, never start-server.sh
        tfs = os.path.join(tmp, 'tfs')
        sleep_bin = subprocess.run(['bash', '-c', 'command -v sleep'], capture_output=True, text=True).stdout.strip()
        with open(sleep_bin, 'rb') as src, open(tfs, 'wb') as dst:
            dst.write(src.read())
        os.chmod(tfs, 0o755)
        pidf = os.path.join(tmp, 'server.pid')
        proc = subprocess.Popen([tfs, '30'])
        try:
            with open(pidf, 'w') as f:
                f.write('%d\n' % proc.pid)
            out, _ = status({'CHAOS_PID_FILE': pidf})
            check(out.get('pid') == str(proc.pid), 'status: the engine pid')
            before = calls()
            r = run('save', extra={'CHAOS_PID_FILE': pidf, 'STUB_NOUNIT': '1'})
            check(r.returncode == 0 and 'save requested' in r.stdout, 'save with the pid file: ' + r.stderr)
            check(proc.wait(timeout=5) == -10, 'save sent SIGUSR1 to the engine pid')
            check('SIGUSR1' not in calls()[len(before):], 'save with the pid file does not signal the unit')
        finally:
            if proc.poll() is None:
                proc.kill()
        with open(pidf, 'w') as f:
            f.write('%d\n' % os.getpid())
        out, _ = status({'CHAOS_PID_FILE': pidf})
        check(out.get('pid') == '', 'a pid that is not the engine (tfs) is not used')
    test_admin_commands()
    test_testers()
    print('chaos_ctl_test: %d failures' % failures)
    return 1 if failures else 0


def test_admin_commands():
    """xp-rate, backups, health, cleanup, accounts and the refusals of the kit's update commands"""
    import shutil
    repo_root = os.path.dirname(os.path.dirname(HERE))
    with tempfile.TemporaryDirectory() as tmp:
        stub = os.path.join(tmp, 'stub')
        server = os.path.join(tmp, 'server')
        repo = os.path.join(tmp, 'repo')
        os.makedirs(stub)
        os.makedirs(os.path.join(repo, 'server', 'deploy'))
        os.makedirs(os.path.join(repo, 'server', 'tools'))
        shutil.copy(os.path.join(HERE, 'chaos_config_rates.py'), os.path.join(repo, 'server', 'deploy'))
        shutil.copy(os.path.join(repo_root, 'server', 'tools', 'late_game.py'), os.path.join(repo, 'server', 'tools'))
        for name, body in (('systemctl', SYSTEMCTL), ('mysql', MYSQL)):
            p = os.path.join(stub, name)
            with open(p, 'w') as f:
                f.write(body)
            os.chmod(p, 0o755)
        sys.path.insert(0, os.path.join(repo_root, 'server', 'tools'))
        import late_game
        os.makedirs(os.path.join(server, 'data'))
        cfg = os.path.join(server, 'config.lua')
        with open(cfg, 'w') as f:
            f.write('rateExp = 5\npasswordHashIterations = 2000\n'
                    + late_game.stages_lua(late_game.STAGES, late_game.STAGES_MARK) + '\n')
        env_file = os.path.join(tmp, 'chaos.env')
        bdir = os.path.join(tmp, 'backups')
        with open(env_file, 'w') as f:
            f.write('CHAOS_DB_USER=chaos\nCHAOS_DB_PASS=secret\nCHAOS_BACKUP_DIR=%s\n' % bdir)
        work = os.path.join(tmp, 'work')
        os.makedirs(work)
        env = dict(os.environ, PATH=stub + ':' + os.environ['PATH'], STUB=stub, CHAOS_CTL_NO_SUDO='1',
                   CHAOS_SERVER_DIR=server, CHAOS_ENV=env_file, CHAOS_REPO=repo, CHAOS_MYSQL='mysql',
                   CHAOS_CTL_CONF=os.path.join(tmp, 'none.conf'), CHAOS_WORK_DIR=work,
                   CHAOS_PID_FILE=os.path.join(tmp, 'no.pid'), CHAOS_LOG=os.path.join(tmp, 'no.log'))
        for k in ('SUDO_USER', 'CHAOS_UNIT', 'CHAOS_ROOT', 'CHAOS_KIT_DIR', 'CHAOS_DB_SOCKET', 'CHAOS_BACKUP_DIR'):
            env.pop(k, None)

        def run(*args, stdin=None, extra=None):
            return subprocess.run(['bash', SCRIPT] + list(args), env=dict(env, **(extra or {})), input=stdin,
                                  capture_output=True, text=True)

        def calls():
            p = os.path.join(stub, 'calls')
            return open(p).read() if os.path.exists(p) else ''

        r = run('xp-rate')
        check(r.returncode == 0 and 'xp=x1' in r.stdout and 'rateExp=5' in r.stdout,
              'xp-rate: shows x1: ' + r.stdout + r.stderr)
        r = run('xp-rate', 'set', '10')
        check(r.returncode == 0 and 'next restart' in r.stdout, 'xp-rate set 10: ' + r.stdout + r.stderr)
        check('xp=x10' in run('xp-rate', 'show').stdout, 'xp-rate: x10 after set')
        check('systemctl restart' not in calls(), 'xp-rate set without restart does not restart')
        r = run('xp-rate', 'reset', 'restart')
        check(r.returncode == 0 and 'systemctl restart chaos-server' in calls(), 'xp-rate reset restart: ' + r.stderr)
        check('xp=x1' in run('xp-rate', 'show').stdout, 'xp-rate: x1 after reset')
        for bad in (('xp-rate', 'set', '0'), ('xp-rate', 'set', '101'), ('xp-rate', 'set', '5;x'),
                    ('xp-rate', 'set', '5', 'now'), ('xp-rate', 'bogus'), ('xp-rate', 'reset', 'x')):
            check(run(*bad).returncode != 0, 'xp-rate refuses %r' % (bad,))

        os.makedirs(os.path.join(bdir, 'db'))
        with open(os.path.join(bdir, 'db', 'chaos-db-chaos-1.sql.gz'), 'w') as f:
            f.write('x')
        r = run('backups')
        check(r.returncode == 0 and 'dir=' + bdir in r.stdout and 'chaos-db-chaos-1.sql.gz' in r.stdout,
              'backups lists the dumps: ' + r.stdout + r.stderr)

        # cleanup: old work folders, srvNN, engine backups beyond the newest 2
        old = os.path.join(work, 'chaos-publish.abc')
        os.makedirs(old)
        os.utime(old, (time.time() - 3 * 86400,) * 2)
        fresh = os.path.join(work, 'chaos-kit-update.new')
        os.makedirs(fresh)
        os.makedirs(os.path.join(work, 'srv46'))
        os.makedirs(os.path.join(work, 'keepme'))
        for i, n in enumerate((44, 45, 46, 47)):
            p = os.path.join(server, 'tfs.antes-%d' % n)
            with open(p, 'w') as f:
                f.write('e')
            os.utime(p, (time.time() - (10 - i) * 3600,) * 2)
        r = run('health')
        out = dict(l.split('=', 1) for l in r.stdout.splitlines() if '=' in l)
        check(r.returncode == 0 and out.get('database') == 'ok' and out.get('cleanup', '').startswith('4 item'),
              'health: database and cleanup count: ' + r.stdout + r.stderr)
        check('web' in out and 'disk' in out, 'health: web and disk lines')
        r = run('cleanup')
        check(r.returncode == 0 and r.stdout.count('would remove') == 4 and os.path.exists(old),
              'cleanup lists only: ' + r.stdout)
        r = run('cleanup', '--yes')
        check(r.returncode == 0 and not os.path.exists(old) and not os.path.exists(os.path.join(work, 'srv46')),
              'cleanup --yes removes: ' + r.stdout + r.stderr)
        check(os.path.exists(fresh) and os.path.exists(os.path.join(work, 'keepme')), 'cleanup keeps fresh and other folders')
        left = sorted(n for n in os.listdir(server) if n.startswith('tfs.antes-'))
        check(left == ['tfs.antes-46', 'tfs.antes-47'], 'cleanup keeps the newest two engine backups: %r' % left)
        check(run('cleanup', 'now').returncode != 0, 'cleanup refuses other arguments')

        # accounts: the password from stdin, a PBKDF2 hash to the database on stdin, never on a command line
        r = run('account-create', 'Newbie1', stdin='hunter22secret\n')
        check(r.returncode == 0 and 'created' in r.stdout, 'account-create: ' + r.stdout + r.stderr)
        with open(os.path.join(stub, 'stdin')) as f:
            sql = f.read()
        check(sql.startswith("INSERT INTO accounts (name, password, type, creation) VALUES ('Newbie1', "
                             "'pbkdf2-sha256$2000$"), 'account-create: a PBKDF2 hash with the configured iterations: ' + sql)
        check('hunter22secret' not in calls() + sql, 'the password is never on a command line or in the SQL')
        r = run('account-create', 'Newbie1', stdin='hunter22secret\n', extra={'STUB_ACCOUNTS': '1'})
        check(r.returncode != 0 and 'account-exists' in r.stderr, 'account-create: an existing account is refused')
        r = run('account-password', 'Newbie1', stdin='another-pass\n', extra={'STUB_ACCOUNTS': '1'})
        with open(os.path.join(stub, 'stdin')) as f:
            sql = f.read()
        check(r.returncode == 0 and "UPDATE accounts SET password = 'pbkdf2-sha256$" in sql,
              'account-password: ' + r.stdout + r.stderr)
        check(run('account-password', 'Ghost', stdin='another-pass\n').returncode != 0, 'account-password: no such account')
        for bad, pw in ((('account-create', "a'b"), 'hunter22'), (('account-create', 'ab'), 'hunter22'),
                        (('account-create', 'Okname'), 'short'), (('account-create', 'Okname'), 'x' * 70),
                        (('account-create', 'Okname', 'extra'), 'hunter22'), (('account-create', 'Okname'), '')):
            check(run(*bad, stdin=pw + '\n').returncode != 0, 'account refuses %r / %d characters' % (bad, len(pw)))

        # gm-logs: the base command logs and the admin panel's audit rows, a validated name, no other file
        logs = os.path.join(server, 'data', 'logs')
        os.makedirs(logs)
        with open(os.path.join(logs, 'Gm Ana commands.log'), 'w') as f:
            f.write(''.join('[21/10/2026 10:%02d] Gm Ana: /i %d\n' % (i, i) for i in range(10)))
        with open(os.path.join(tmp, 'secret.txt'), 'w') as f:
            f.write('do not show\n')
        os.symlink(os.path.join(tmp, 'secret.txt'), os.path.join(logs, 'Evil commands.log'))
        r = run('gm-logs', '3', 'Gm Ana')
        out = r.stdout
        check(r.returncode == 0 and '@staff\nGm Ana\nGma\n' in out, 'gm-logs: staff from the files and the table: ' + out + r.stderr)
        check('Bad;Name' not in out, 'gm-logs: odd names from the table are dropped')
        check('@commands Gm Ana\n[21/10/2026 10:09] Gm Ana: /i 9\n[21/10/2026 10:08]' in out and '10:06' not in out,
              'gm-logs: the newest 3 lines, newest first: ' + out)
        check("@panel\n2026-10-21 10:00\tGma\tplayers.kick" in out and "WHERE player_name = 'Gm Ana'" in calls(),
              'gm-logs: the audit rows of that player')
        check('Gm Ana commands.log' in out.split('@files')[1], 'gm-logs: the file list')
        r = run('gm-logs', 'Evil')
        check('do not show' not in r.stdout, 'gm-logs: a link out of the folder is not read')
        r = run('gm-logs', "O'Neil")
        check(r.returncode == 0 and "player_name = 'O''Neil'" in calls(), 'gm-logs: a quote in the name is escaped')
        for bad in (('gm-logs', '../x'), ('gm-logs', 'a/b'), ('gm-logs', 'Gm', 'Two'), ('gm-logs', 'x;y')):
            check(run(*bad).returncode != 0, 'gm-logs refuses %r' % (bad,))
        r = run('gm-logs')
        check(r.returncode == 0 and 'LIMIT 60' in calls() and '@panel' in r.stdout, 'gm-logs: all staff, 60 rows')

        # the kit's update commands: only for the kit, only whitelisted options
        r = run('update-check')
        check(r.returncode != 0 and 'kit-not-found' in r.stderr, 'update-check without a kit says so: ' + r.stderr)
        kit = {'CHAOS_KIT_DIR': tmp}
        kup = os.path.join(repo, 'server', 'deploy', 'chaos_kit_update.sh')
        with open(kup, 'w') as f:
            f.write('#!/usr/bin/env bash\necho "kit $* branch=${CHAOS_UPDATE_BRANCH:-} server=$CHAOS_SERVER_DIR"\n')
        os.chmod(kup, 0o755)
        r = run('update-check', extra=dict(kit, CHAOS_UPDATE_BRANCH='beta'))
        check(r.returncode == 0 and 'kit check branch=beta server=' + server in r.stdout,
              'update-check runs the kit script: ' + r.stdout + r.stderr)
        for bad in (('update-apply', '--yes'), ('update-apply', ';reboot'), ('update-check', 'x'),
                    ('update-rollback', 'x')):
            check(run(*bad, extra=kit).returncode != 0, 'refused: %r' % (bad,))
        r = run('update', 'v1', 'now', extra=kit)
        check(r.returncode != 0 and 'kit-layout' in r.stderr, 'update TAG on the kit points to update-apply')
        r = run('rollback', 'at-save', extra=kit)
        check(r.returncode != 0 and 'kit-layout' in r.stderr, 'rollback at-save on the kit is refused')
        r = run('update-status', extra=dict(kit, CHAOS_KIT_STATE=os.path.join(tmp, 'kstate')))
        check(r.returncode == 0 and 'running=no' in r.stdout and 'status=' in r.stdout,
              'update-status: ' + r.stdout + r.stderr)
        r = run('site-install', extra={'CHAOS_SITE_ENV': os.path.join(tmp, 'nope.env')})
        check(r.returncode != 0, 'site-install without a site settings file is refused')


TESTERS_STUB = """import os, sys, time
with open(os.path.join(os.environ['STUB'], 'testers_calls'), 'a') as f:
    f.write(' '.join(sys.argv[1:]) + ' db=' + ('yes' if os.environ.get('CHAOS_DB_PASS') == 'secret' else 'no') + '\\n')
if sys.argv[1] == 'status':
    print('bots=%s' % os.environ.get('STUB_BOTS', '0'))
    print('minutes=2')
if sys.argv[1] == 'run':
    time.sleep(60)
"""


def test_testers():
    """chaos-ctl.sh testers: refusals, the helper copied and removed, the run started and stopped, cleanup"""
    import signal
    with tempfile.TemporaryDirectory() as tmp:
        stub = os.path.join(tmp, 'stub')
        server = os.path.join(tmp, 'server')
        repo = os.path.join(tmp, 'repo')
        state = os.path.join(tmp, 'tstate')
        os.makedirs(stub)
        os.makedirs(os.path.join(server, 'data', 'scripts'))
        os.makedirs(os.path.join(repo, 'server', 'tools'))
        for name, body in (('systemctl', SYSTEMCTL), ('mysql', MYSQL)):
            p = os.path.join(stub, name)
            with open(p, 'w') as f:
                f.write(body)
            os.chmod(p, 0o755)
        with open(os.path.join(repo, 'server', 'tools', 'testers.py'), 'w') as f:
            f.write(TESTERS_STUB)
        for name in ('tester_helper.lua', 'tester_helper_core.lua'):
            with open(os.path.join(repo, 'server', 'tools', name), 'w') as f:
                f.write('-- ' + name + '\n')
        cfg = os.path.join(server, 'config.lua')
        with open(cfg, 'w') as f:
            f.write('-- clientGuardAllowDevKey = true\nclientGuardAllowDevKey = false\n')
        env_file = os.path.join(tmp, 'chaos.env')
        with open(env_file, 'w') as f:
            f.write('CHAOS_DB_USER=chaos\nCHAOS_DB_PASS=secret\n')
        key = os.path.join(tmp, 'tester-client-key')
        log = os.path.join(tmp, 'server.log')
        with open(log, 'w') as f:
            f.write('Loading config\nserver online\n')
        env = dict(os.environ, PATH=stub + ':' + os.environ['PATH'], STUB=stub, CHAOS_CTL_NO_SUDO='1',
                   CHAOS_SERVER_DIR=server, CHAOS_ENV=env_file, CHAOS_REPO=repo, CHAOS_MYSQL='mysql',
                   CHAOS_CTL_CONF=os.path.join(tmp, 'none.conf'), CHAOS_PID_FILE=os.path.join(tmp, 'no.pid'),
                   CHAOS_LOG=log, CHAOS_TESTER_KEY=key, CHAOS_TESTER_STATE=state,
                   CHAOS_TESTER_LOG=os.path.join(tmp, 'testers.log'))
        for k in ('SUDO_USER', 'CHAOS_UNIT', 'CHAOS_ROOT', 'CHAOS_KIT_DIR', 'CHAOS_DB_SOCKET'):
            env.pop(k, None)

        def run(*args, extra=None):
            return subprocess.run(['bash', SCRIPT] + list(args), env=dict(env, **(extra or {})), capture_output=True,
                                  text=True, timeout=60)

        def tcalls():
            p = os.path.join(stub, 'testers_calls')
            return open(p).read() if os.path.exists(p) else ''

        helper = os.path.join(server, 'data', 'scripts', 'zz_tester_helper.lua')
        r = run('testers', 'start')
        check(r.returncode != 0 and 'read -rsp' in r.stderr and key in r.stderr,
              'testers: no key file, the read -rs command is shown: ' + r.stderr)
        with open(key, 'w') as f:
            f.write('ab' * 32 + '\n')
        os.chmod(key, 0o644)
        r = run('testers', 'start')
        check(r.returncode != 0 and 'readable by group or others' in r.stderr, 'testers: a readable key file is refused')
        os.chmod(key, 0o600)
        with open(cfg, 'a') as f:
            f.write('clientGuardAllowDevKey = true\n')
        r = run('testers', 'start')
        check(r.returncode != 0 and 'clientGuardAllowDevKey' in r.stderr, 'testers: the development key is refused')
        with open(cfg, 'w') as f:
            f.write('clientGuardAllowDevKey = false\n')
        for bad in (('151',), ('0',), ('5', '0'), ('5', '2000'), ('x',), ('5', '5', '5'), ('--restart', 'x'),
                    ('--restart', '5000')):
            check(run('testers', 'start', *bad).returncode != 0, 'testers start refused: %r' % (bad,))
        check(run('testers', 'fly').returncode != 0, 'testers: an unknown subcommand is refused')
        r = run('testers', 'start', '5', '2')
        check(r.returncode != 0 and 'helper-not-loaded' in r.stderr and '--restart' in r.stderr,
              'testers: a helper not loaded since the server start is refused: ' + r.stderr)
        check(not os.path.exists(helper), 'a refused start leaves no helper in data/scripts')
        check(tcalls() == '', 'nothing refused ran testers.py')

        with open(log, 'a') as f:
            f.write('[tester-helper] running (TEST ONLY)\n')
        r = run('testers', 'start', '5', '2')
        check(r.returncode == 0 and 'tester bots: 5 for 2 minutes' in r.stdout, 'testers start: ' + r.stdout + r.stderr)
        check(os.path.exists(helper) and os.path.exists(helper.replace('helper.lua', 'helper_core.lua')),
              'the helper is copied into data/scripts')
        pid = int(open(os.path.join(state, 'run.pid')).read())
        try:
            check(oct(os.stat(state).st_mode & 0o777) == '0o700', 'the state folder is root only')
            for _ in range(50):
                if 'run --key-file' in tcalls():
                    break
                time.sleep(0.1)
            calls = tcalls()
            check('setup --count 5 --server-dir ' + server in calls, 'setup of 5 testers: ' + calls)
            check('run --key-file %s --server-dir %s' % (key, server) in calls and '--minutes 2 --count 5' in calls,
                  'the run: the key file path, minutes, count: ' + calls)
            check('--scenarios ' in calls and 'server/tools/tester_scenarios.json' in calls,
                  'the run gets the coverage table: ' + calls)
            check('ab' * 32 not in calls and 'secret' not in calls, 'no key and no password on a command line')
            check('db=yes' in calls, 'the database settings reach testers.py by the environment')
            check(os.getpgid(pid) == pid, 'the run has its own process group')
            r = run('testers', 'status', extra={'STUB_BOTS': '5'})
            out = dict(l.split('=', 1) for l in r.stdout.splitlines() if '=' in l)
            check(out.get('running') == 'yes' and out.get('pid') == str(pid) and out.get('bots') == '5'
                  and out.get('helper') == 'copied' and out.get('helper_loaded') == 'yes', 'testers status: ' + r.stdout)
            r = run('testers', 'start', '5', '2')
            check(r.returncode != 0 and 'already running' in r.stderr, 'a second start is refused')
            r = run('testers', 'cleanup', '--yes')
            check(r.returncode != 0 and 'wait' in r.stderr, 'cleanup right after a stop waits: ' + r.stderr)
            check(not os.path.exists(helper), 'cleanup stopped the run and removed the helper')
            dead = False
            for _ in range(50):
                try:
                    os.kill(pid, 0)
                except OSError:
                    dead = True
                    break
                time.sleep(0.1)
            check(dead, 'stop ended the run')
        finally:
            try:
                os.killpg(pid, signal.SIGKILL)
            except OSError:
                pass
        r = run('testers', 'stop')
        check(r.returncode == 0 and not os.path.exists(helper), 'stop when nothing runs is fine')
        with open(os.path.join(state, 'stopped'), 'w') as f:
            f.write('%d\n' % (time.time() - 600))
        before = tcalls()
        r = run('testers', 'cleanup')
        check(r.returncode == 0 and 'cleanup --state %s --dry-run' % state in tcalls()[len(before):]
              and 'nothing deleted' in r.stdout, 'cleanup without --yes only lists: ' + r.stdout + r.stderr)
        before = tcalls()
        r = run('testers', 'cleanup', '--yes')
        new = tcalls()[len(before):]
        check(r.returncode == 0 and 'cleanup --state ' + state in new and '--dry-run' not in new,
              'cleanup --yes deletes: ' + new)
        check(run('testers', 'cleanup', '--all').returncode != 0, 'cleanup: an unknown option is refused')
        r = run('testers', 'report')
        check(r.returncode == 0 and 'report --state %s --log %s' % (state, log) in tcalls(), 'report reads the log')

        # not loaded, with --restart: the restart countdown is queued, the bots wait for it
        with open(log, 'a') as f:
            f.write('Loading config\n')
        r = run('testers', 'start', '3', '1', '--restart', '5', extra={'STUB_BOTS': '5'})
        check(r.returncode == 0 and 'starting in 35 s' in r.stdout, 'start --restart: ' + r.stdout + r.stderr)
        check('The server restarts in 5 seconds' in open(os.path.join(server, 'remote.cmd')).read(),
              'the restart countdown is announced')
        pid = int(open(os.path.join(state, 'run.pid')).read())
        r = run('testers', 'stop')
        check(r.returncode == 0 and not os.path.exists(helper), 'stop removes the helper')
        try:
            os.killpg(pid, signal.SIGKILL)
        except OSError:
            pass
        time.sleep(6)  # the stub restart countdown runs out inside the folder


if __name__ == '__main__':
    sys.exit(main())
