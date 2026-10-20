#!/usr/bin/env python3
"""Tests for server/deploy/chaos-ctl.sh (docs/ADMIN_APP.md).

Runs the real script as the current user (CHAOS_CTL_NO_SUDO=1) against a throwaway server folder and stubs for
systemctl and mysql: the status lines, the remote.cmd lines each command queues, the refusals (a bad number, a bad tag, a
second line in a broadcast, a key that is not one ssh public key line, an unknown command) and that a refused command
queues nothing. Only refused install-admin inputs are run, and adduser / visudo / install are stubs too, so the test
never creates a user or touches sudoers.

usage: python3 -I server/deploy/chaos_ctl_test.py
"""
import os
import stat
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(HERE, 'chaos-ctl.sh')

SYSTEMCTL = '''#!/usr/bin/env bash
echo "systemctl $*" >> "$STUB/calls"
case $1 in
  is-active) echo active ;;
  show) echo "Tue 2026-10-20 06:00:01 UTC" ;;
esac
exit 0
'''
MYSQL = '''#!/usr/bin/env bash
echo "mysql $*" >> "$STUB/calls"
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
        for name, body in (('systemctl', SYSTEMCTL), ('mysql', MYSQL), ('adduser', NOOP), ('visudo', NOOP),
                           ('install', NOOP)):
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
        env = dict(os.environ, PATH=stub + ':' + os.environ['PATH'], STUB=stub, CHAOS_CTL_NO_SUDO='1',
                   CHAOS_SERVER_DIR=server, CHAOS_ENV=env_file, CHAOS_LOG=log,
                   CHAOS_UPDATE_LOG=os.path.join(tmp, 'u.log'), CHAOS_REPO=os.path.join(tmp, 'repo'))

        def run(*args, stdin=None):
            return subprocess.run(['bash', SCRIPT] + list(args), env=env, input=stdin, capture_output=True, text=True)

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
        check('secret' not in calls(), 'the database password is never on a command line')

        r = run('logs', '5')
        check(r.stdout.count('\n') == 5, 'logs 5: five lines')
        check(run('logs', 'x').returncode != 0, 'logs: N must be a number')
        check(run('logs', '9999').stdout.count('\n') <= 102, 'logs: capped')
        r = run('errors')
        check('Lua Script Error' in r.stdout and 'line 3' not in r.stdout, 'errors: only the error lines')
        check('Bob' in run('players').stdout, 'players: from players_online')

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
        import re, threading, time

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
    print('chaos_ctl_test: %d failures' % failures)
    return 1 if failures else 0


if __name__ == '__main__':
    sys.exit(main())
