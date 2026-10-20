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

usage: python3 -I server/deploy/chaos_ctl_test.py
"""
import os
import re
import stat
import subprocess
import sys
import tempfile

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
case "$*" in
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


        # catalog and panel: a thread plays the engine and answers what the script queued
        import threading, time

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
    print('chaos_ctl_test: %d failures' % failures)
    return 1 if failures else 0


if __name__ == '__main__':
    sys.exit(main())
