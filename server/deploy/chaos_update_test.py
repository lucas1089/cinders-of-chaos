#!/usr/bin/env python3
"""Tests for server/deploy/chaos_update.sh (docs/LAUNCH.md "Updating the live server").

Runs the real script against a throwaway git repository with release tags, a small server folder and stubs: systemctl
(a fake unit state in files), and the repo's backup.sh, install_all.py, chaos_watchdog.py and chaos_health.py replaced
by small stand-ins in the throwaway repository. Checks the order (backup before the dry run, stop before the install, a
dump of the stopped server, start last), the refusals (dirty checkout, a branch instead of a tag, engine patches without
--engine, a failed backup, an unfinished update), --check-only, --at-save with the restart held off, the Lua error
check and the rollback (checkout, data archive with the map and logs carried over, the old engine).

usage: python3 -I server/deploy/chaos_update_test.py
"""
import os
import shutil
import stat
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(HERE, 'chaos_update.sh')

SYSTEMCTL = r'''#!/usr/bin/env bash
# test stand-in: unit state is a file per active unit in $STUB/active
echo "systemctl $*" >> "$STUB/calls"
args=()
for a in "$@"; do case "$a" in --quiet|--value|--kill-whom=*) ;; *) args+=("$a") ;; esac; done
set -- "${args[@]}"
case "$1" in
	is-active) [ -e "$STUB/active/$2" ] ;;
	stop) rm -f "$STUB/active/$2" ;;
	start)
		touch "$STUB/active/$2"
		if [ "$2" = chaos-server ] && [ -n "${STUB_LUA_ERROR:-}" ]; then echo "Lua Script Error: [Test] boom" >> "$STUB/server.log"; fi
		if [ "$2" = chaos-server ]; then echo "map loaded" >> "$STUB/server.log"; fi ;;
	daemon-reload)
		# the "daily save": the engine stops by itself once the update's drop-in is there
		if [ -n "${STUB_SAVE_ON_RELOAD:-}" ] && ls "$STUB"/run/*/50-chaos-update.conf >/dev/null 2>&1; then
			rm -f "$STUB/active/chaos-server"
		fi ;;
	show)
		# show -p PROP UNIT
		case "$3" in
			Result) echo "${STUB_RESULT:-success}" ;;
			*) echo "" ;;
		esac ;;
	kill) ;;
esac
'''

BACKUP = r'''#!/usr/bin/env bash
# test stand-in for server/tools/backup.sh
echo "backup $*" >> "$STUB/calls"
[ -z "${STUB_BACKUP_FAIL:-}" ] || exit 1
server=""; data=1
while [ $# -gt 0 ]; do case "$1" in --server-dir) server=$2; shift 2 ;; --no-data) data=0; shift ;; *) shift ;; esac; done
n=$(date +%s%N)
mkdir -p "$CHAOS_BACKUP_DIR/db" "$CHAOS_BACKUP_DIR/data"
echo dump | gzip > "$CHAOS_BACKUP_DIR/db/chaos-db-chaos-$n.sql.gz"
if [ "$data" = 1 ] && [ -n "$server" ]; then
	tar -C "$server" --exclude='*.otbm' --exclude='data/logs' --exclude='data/reports' -czf "$CHAOS_BACKUP_DIR/data/chaos-data-$n.tar.gz" config.lua data
fi
sleep 0.05
'''

INSTALL = r'''import os, shutil, sys
stub = os.environ['STUB']
here = os.path.dirname(os.path.abspath(__file__))
server = sys.argv[1]
dry = '--dry-run' in sys.argv
with open(os.path.join(stub, 'calls'), 'a') as f:
    f.write('install %s\n' % ('dry' if dry else 'real'))
if os.environ.get('STUB_INSTALL_FAIL') and not dry:
    sys.exit(1)
if not dry:
    shutil.copytree(os.path.join(here, '..', 'data', 'scripts'), os.path.join(server, 'data', 'scripts'), dirs_exist_ok=True)
print('[ok] files - 1 file(s) %s' % ('would change' if dry else 'changed'))
'''

WATCHDOG = 'def ask_status(host, port, timeout):\n    return True\n'
HEALTH = 'print("ok   service chaos-server")\n'


def run(cmd, cwd=None, env=None, check=True):
    r = subprocess.run(cmd, cwd=cwd, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, universal_newlines=True)
    if check and r.returncode != 0:
        raise AssertionError('%s failed:\n%s' % (cmd, r.stdout))
    return r


def write(path, text, mode=None):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w') as f:
        f.write(text)
    if mode:
        os.chmod(path, mode)


def read(path):
    with open(path) as f:
        return f.read()


class World:
    def __init__(self):
        self.root = tempfile.mkdtemp(prefix='chaos_update_test_')
        r = self.root
        self.stub = os.path.join(r, 'stub')
        os.makedirs(os.path.join(self.stub, 'active'))
        os.makedirs(os.path.join(self.stub, 'run'))
        write(os.path.join(self.stub, 'bin', 'systemctl'), SYSTEMCTL, 0o755)
        write(os.path.join(self.stub, 'calls'), '')
        for unit in ('chaos-server', 'chaos-health.timer', 'chaos-watchdog.timer', 'chaos-backup.timer'):
            write(os.path.join(self.stub, 'active', unit), '')
        self.env = dict(os.environ, STUB=self.stub, PATH=os.path.join(self.stub, 'bin') + os.pathsep + os.environ['PATH'],
                        GIT_AUTHOR_NAME='t', GIT_AUTHOR_EMAIL='t@example.org', GIT_COMMITTER_NAME='t',
                        GIT_COMMITTER_EMAIL='t@example.org', GIT_CONFIG_NOSYSTEM='1', HOME=r)
        # the "upstream" repository with release v1
        self.origin = os.path.join(r, 'origin')
        o = self.origin
        run(['git', 'init', '-q', o], env=self.env)
        write(os.path.join(o, '.gitignore'), '__pycache__/\n*.pyc\n')
        write(os.path.join(o, 'server/tools/backup.sh'), BACKUP, 0o755)
        write(os.path.join(o, 'server/tools/install_all.py'), INSTALL)
        write(os.path.join(o, 'server/tools/chaos_watchdog.py'), WATCHDOG)
        write(os.path.join(o, 'server/tools/chaos_health.py'), HEALTH)
        write(os.path.join(o, 'server/data/scripts/chaos/a.lua'), '-- v1\n')
        self.commit('v1')
        # the checkout on the game server, and the server folder installed from v1
        self.repo = os.path.join(r, 'repo')
        run(['git', 'clone', '-q', o, self.repo], env=self.env)
        run(['git', '-C', self.repo, 'checkout', '-q', '--detach', 'v1'], env=self.env)
        self.server = os.path.join(r, 'server')
        write(os.path.join(self.server, 'config.lua'), 'serverName = "test"\n')
        write(os.path.join(self.server, 'data/scripts/chaos/a.lua'), '-- v1\n')
        write(os.path.join(self.server, 'data/world/map.otbm'), 'map v1\n')
        write(os.path.join(self.server, 'data/logs/old.log'), 'log\n')
        write(os.path.join(self.server, 'tfs'), 'engine v1\n', 0o755)
        self.envfile = os.path.join(r, 'chaos.env')
        write(self.envfile, 'CHAOS_DB_NAME=chaos\nCHAOS_BACKUP_DIR=%s\n' % os.path.join(r, 'backups'))
        self.state = os.path.join(r, 'state')

    def commit(self, tag):
        run(['git', '-C', self.origin, 'add', '-A'], env=self.env)
        run(['git', '-C', self.origin, 'commit', '-q', '-m', tag], env=self.env)
        run(['git', '-C', self.origin, 'tag', tag], env=self.env)

    def release(self, tag, files):
        for path, text in files.items():
            write(os.path.join(self.origin, path), text)
        self.commit(tag)

    def update(self, *args, extra_env=None, input_text=None):
        env = dict(self.env, **(extra_env or {}))
        cmd = ['bash', SCRIPT, '--repo', self.repo, '--server', self.server, '--env', self.envfile, '--state-dir',
               self.state, '--log', os.path.join(self.stub, 'server.log'), '--dropin-dir', os.path.join(self.stub, 'run'),
               '--boot-timeout', '20'] + list(args)
        write(os.path.join(self.stub, 'calls'), '')
        r = subprocess.run(cmd, env=env, input=input_text if input_text is not None else '', stdout=subprocess.PIPE,
                           stderr=subprocess.STDOUT, universal_newlines=True, timeout=120)
        self.out = r.stdout
        self.calls = read(os.path.join(self.stub, 'calls')).splitlines()
        return r.returncode

    def head(self):
        return run(['git', '-C', self.repo, 'rev-parse', 'HEAD'], env=self.env).stdout.strip()

    def tag(self, tag):
        return run(['git', '-C', self.origin, 'rev-parse', tag + '^{commit}'], env=self.env).stdout.strip()

    def state_value(self, key):
        for line in read(os.path.join(self.state, 'state')).splitlines():
            if line.startswith(key + '='):
                return line[len(key) + 1:]
        return None

    def index(self, prefix):
        for i, c in enumerate(self.calls):
            if c.startswith(prefix):
                return i
        raise AssertionError('no call %r in %r\n%s' % (prefix, self.calls, self.out))

    def close(self):
        shutil.rmtree(self.root, ignore_errors=True)


FAILS = []


def check(cond, what, w=None):
    if not cond:
        FAILS.append(what)
        print('FAIL: ' + what)
        if w is not None:
            print(w.out)


def test_update_and_rollback():
    w = World()
    try:
        w.release('v2', {'server/data/scripts/chaos/a.lua': '-- v2\n', 'server/data/scripts/chaos/b.lua': '-- new in v2\n',
                         'server/data/patchnotes/2026-11-01.md': '# Week\n'})
        rc = w.update('--ref', 'v2', '--now', '--yes')
        check(rc == 0, 'update v2 exits 0 (got %d)' % rc, w)
        check(w.head() == w.tag('v2'), 'checkout at v2 after the update', w)
        check(read(os.path.join(w.server, 'data/scripts/chaos/a.lua')) == '-- v2\n', 'v2 installed')
        order = [w.index('backup --save-service chaos-server'), w.index('install dry'),
                 w.index('systemctl stop chaos-server'), w.index('backup --no-data'), w.index('install real'),
                 w.index('systemctl start chaos-server')]
        check(order == sorted(order), 'order: backup, dry run, stop, dump, install, start %r' % order, w)
        check(w.index('systemctl stop chaos-health.timer') > w.index('systemctl stop chaos-server'),
              'timers held only once the server is down', w)
        check(any(c == 'systemctl start chaos-backup.timer' for c in w.calls), 'timers started again', w)
        check(w.state_value('deployed') == w.tag('v2') and w.state_value('previous') == w.tag('v1'),
              'state: deployed v2, previous v1', w)
        check('a patch note for players is included' in w.out, 'patch note noticed', w)
        check(os.path.isfile(w.state_value('data_archive') or '/nonexistent'), 'pre-update data archive recorded', w)

        rc = w.update('--ref', 'v2', '--now', '--yes')
        check(rc == 0 and 'nothing to do' in w.out and not any(c.startswith('backup') for c in w.calls),
              'second run of the same tag does nothing', w)

        write(os.path.join(w.server, 'data/logs/new.log'), 'after update\n')
        rc = w.update('--rollback', '--now', '--yes')
        check(rc == 0, 'rollback exits 0 (got %d)' % rc, w)
        check(w.head() == w.tag('v1'), 'checkout back at v1', w)
        check(read(os.path.join(w.server, 'data/scripts/chaos/a.lua')) == '-- v1\n', 'v1 data back')
        check(not os.path.exists(os.path.join(w.server, 'data/scripts/chaos/b.lua')), 'the file v2 added is gone')
        check(read(os.path.join(w.server, 'data/world/map.otbm')) == 'map v1\n', 'map carried over')
        check(os.path.isfile(os.path.join(w.server, 'data/logs/new.log')), 'logs carried over')
        check(any(n.startswith('data.before-rollback-') for n in os.listdir(w.server)), 'replaced data kept aside')
        check(w.index('backup --save-service') < w.index('systemctl stop chaos-server'), 'rollback backs up first', w)
        check('Rollback to the last backup' in w.out, 'rollback points to the database restore', w)
        check(w.state_value('deployed') == w.tag('v1') and w.state_value('previous') == '', 'state after rollback', w)

        rc = w.update('--rollback', '--now', '--yes')
        check(rc == 1 and 'nothing recorded' in w.out, 'a second rollback refuses', w)
    finally:
        w.close()


def test_refusals():
    w = World()
    try:
        w.release('v2', {'server/data/scripts/chaos/a.lua': '-- v2\n'})
        write(os.path.join(w.repo, 'stray.txt'), 'x')
        rc = w.update('--ref', 'v2', '--now', '--yes')
        check(rc == 1 and 'untracked' in w.out and not w.calls, 'dirty checkout refused', w)
        os.remove(os.path.join(w.repo, 'stray.txt'))

        rc = w.update('--ref', 'v2', '--yes')
        check(rc == 1 and '--at-save' in w.out, 'no timing refused', w)

        branch = run(['git', '-C', w.origin, 'branch', '--show-current'], env=w.env).stdout.strip()
        rc = w.update('--ref', 'origin/' + branch, '--now', '--yes')
        check(rc == 1 and 'not a tag' in w.out, 'a branch is refused without --untagged', w)

        rc = w.update('--ref', 'v2', '--now', '--yes', extra_env={'STUB_BACKUP_FAIL': '1'})
        check(rc == 1 and 'backup failed' in w.out, 'failed backup stops', w)
        check(w.head() == w.tag('v1') and not any(c.startswith('install') for c in w.calls)
              and not any('stop chaos-server' in c for c in w.calls), 'nothing changed after a failed backup', w)

        rc = w.update('--ref', 'v2', '--now', input_text='no\n')
        check(rc == 1 and w.head() == w.tag('v1') and not any('stop chaos-server' in c for c in w.calls),
              'a "no" at the question puts the checkout back', w)

        rc = w.update('--ref', 'v2', '--check-only')
        check(rc == 0 and w.head() == w.tag('v1') and 'install dry' in w.calls
              and not any(c.startswith('backup') or 'stop' in c for c in w.calls), 'check only changes nothing', w)

        rc = w.update('--ref', 'v2', '--now', '--yes', extra_env={'STUB_INSTALL_FAIL': '1'})
        check(rc == 1 and 'stays down' in w.out and w.state_value('status') == 'installing', 'failed install', w)
        rc = w.update('--ref', 'v2', '--now', '--yes')
        check(rc == 1 and 'stopped during the install' in w.out, 'unfinished update refused until rollback', w)
        rc = w.update('--rollback', '--now', '--yes')
        check(rc == 0 and w.head() == w.tag('v1'), 'rollback after a failed install', w)
    finally:
        w.close()


def test_engine_and_at_save():
    w = World()
    try:
        w.release('v2', {'server/src-patches/0099-test.patch': 'patch\n', 'server/data/scripts/chaos/a.lua': '-- v2\n'})
        rc = w.update('--ref', 'v2', '--now', '--yes')
        check(rc == 1 and '--engine' in w.out and w.head() == w.tag('v1'), 'engine patches need --engine', w)

        engine = os.path.join(w.root, 'tfs-v2')
        write(engine, 'engine v2\n', 0o755)
        rc = w.update('--ref', 'v2', '--at-save', '--yes', '--engine', engine,
                      extra_env={'STUB_SAVE_ON_RELOAD': '1', 'STUB_LUA_ERROR': '1'})
        check(rc == 2, 'Lua errors after the start give exit 2 (got %d)' % rc, w)
        check('Lua Script Error' in w.out, 'the error lines are shown', w)
        check(read(os.path.join(w.server, 'tfs')) == 'engine v2\n', 'new engine installed')
        check(os.stat(os.path.join(w.server, 'tfs')).st_mode & stat.S_IXUSR, 'engine executable')
        check(not os.path.exists(os.path.join(w.stub, 'run', 'chaos-server.service.d', '50-chaos-update.conf')),
              'drop-in removed after the stop', w)
        check(not any('systemctl stop chaos-server' == c for c in w.calls), '--at-save never stops the server itself', w)

        rc = w.update('--rollback', '--now', '--yes')
        check(rc == 0 and read(os.path.join(w.server, 'tfs')) == 'engine v1\n', 'rollback puts the old engine back', w)

        w.release('v3', {'server/data/scripts/chaos/a.lua': '-- v3\n'})
        rc = w.update('--ref', 'v3', '--at-save', '--yes', '--engine', engine, extra_env={'STUB_SAVE_ON_RELOAD': '1', 'STUB_RESULT': 'signal'})
        check(rc == 1 and 'a crash' in w.out and w.head() == w.tag('v1') and 'install real' not in w.calls,
              'a crash while waiting installs nothing and starts the old release', w)
        check(os.path.exists(os.path.join(w.stub, 'active', 'chaos-server')), 'server started again after the crash', w)
    finally:
        w.close()


def main():
    for t in (test_update_and_rollback, test_refusals, test_engine_and_at_save):
        t()
    if FAILS:
        print('%d check(s) failed' % len(FAILS))
        return 1
    print('chaos_update.sh: all checks passed')
    return 0


if __name__ == '__main__':
    sys.exit(main())
