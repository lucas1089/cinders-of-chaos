#!/usr/bin/env python3
"""Tests for server/deploy/chaos_kit_update.sh and server/deploy/chaos_config_rates.py (docs/ADMIN_APP.md
"Atualizar servidor").

A throwaway "upstream" git repository (branch main) and its clone as the server's checkout; a kit folder with a server
folder (config.lua with a x10 XP table and rateExp = 10, data/, the engine tfs); stand-ins for curl (the GitHub API
and release downloads served from local files, https only), systemctl (unit state in files; an engine containing
BROKEN never comes online), the database client, ldd, and in the throwaway repository for backup.sh, install_all.py
(its lategame step is the real late_game.py: it puts back the release's x1 stages), publish_client_update.sh and
install_site.sh. Checks: check's key=value lines; the players' changelog written from the checkout;
apply's order (backup, stop, engine, install_all --no-sql, start,
--only sql, restart, Server Online); the XP rates kept; the old engine kept as tfs.antes-N; the client update
published; the download files replaced with NAME.prev, NAME.sha256 and downloads.json; the site installed when
website/ changed; the lock; the refusals (missing library, size, an unsafe tar entry, a dirty checkout); the automatic
rollback when the new engine does not come up; the manual rollback (engine, commit, downloads). The map master (a
windows-assets branch with world/ packed by the real tools/map_master.py from a tiny synthetic map): check's map lines,
the map replaced while the server is stopped and before install_all, the old map kept with a timestamp, the same
version skipped without a restart, a damaged part refused before anything stops, --no-map, the map put back by the
automatic and the manual rollback.

usage: python3 -I server/deploy/chaos_kit_update_test.py
"""
import fcntl
import hashlib
import io
import json
import os
import shutil
import subprocess
import sys
import tarfile
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.dirname(os.path.dirname(HERE))
SCRIPT = os.path.join(HERE, 'chaos_kit_update.sh')
CTL = os.path.join(HERE, 'chaos-ctl.sh')
RATES = os.path.join(HERE, 'chaos_config_rates.py')
LATE_GAME = os.path.join(REPO_ROOT, 'server', 'tools', 'late_game.py')
MAP_MASTER = os.path.join(REPO_ROOT, 'server', 'tools', 'map_master.py')
CHANGELOG = os.path.join(REPO_ROOT, 'server', 'tools', 'gen_changelog.py')
NAMES = os.path.join(REPO_ROOT, 'tools', 'ci', 'check_names.py')
sys.path.insert(0, os.path.join(REPO_ROOT, 'server', 'tools'))
import late_game  # noqa: E402
import map_master_test  # noqa: E402  (fake_map: a tiny synthetic OTBM)

CURL = r'''#!/usr/bin/env bash
# test stand-in: https only; the API answers $STUB/releases.json, downloads come from $STUB/assets/NAME
echo "curl $*" >> "$STUB/calls"
out="" url=""
proto=0
while [ $# -gt 0 ]; do
	case "$1" in
		-o) out=$2; shift 2 ;;
		-H|--max-time|--retry|--retry-delay|--max-filesize) shift 2 ;;
		--proto) [ "$2" = '=https' ] && proto=1; shift 2 ;;
		--proto-redir) shift 2 ;;
		-*) shift ;;
		*) url=$1; shift ;;
	esac
done
[ "$proto" = 1 ] || { echo "curl stub: no --proto =https" >&2; exit 2; }
case "$url" in
	https://api.github.com/repos/owner/game/releases*) cp "$STUB/releases.json" "$out" ;;
	https://github.com/owner/game/releases/download/*) cp "$STUB/assets/${url##*/}" "$out" || exit 22 ;;
	*) echo "curl stub: unexpected $url" >&2; exit 22 ;;
esac
'''

SYSTEMCTL = r'''#!/usr/bin/env bash
echo "systemctl $*" >> "$STUB/calls"
args=()
for a in "$@"; do case "$a" in --quiet|--value) ;; *) args+=("$a") ;; esac; done
set -- "${args[@]}"
online() {
	if grep -q BROKEN "$KIT/server/tfs"; then
		rm -f "$STUB/active/$1"; echo "engine crashed" >> "$KIT/logs/server.log"
	else
		touch "$STUB/active/$1"; echo ">> Cinders of Chaos Server Online!" >> "$KIT/logs/server.log"
	fi
}
case "$1" in
	is-active) if [ -e "$STUB/active/$2" ]; then echo active; else echo inactive; exit 3; fi ;;
	stop) rm -f "$STUB/active/$2" ;;
	start|restart) online "$2" ;;
	show) echo "" ;;
esac
'''
MYSQL = '#!/usr/bin/env bash\necho "mysql $*" >> "$STUB/calls"\necho 1\n'
LDD = '#!/usr/bin/env bash\nif [ -n "${STUB_LDD_MISSING:-}" ]; then echo "\tlibfoo.so.1 => not found"; else echo "\tstatically linked"; fi\n'
BACKUP = r'''#!/usr/bin/env bash
echo "backup $*" >> "$STUB/calls"
server=""
while [ $# -gt 0 ]; do case "$1" in --server-dir) server=$2; shift 2 ;; *) shift ;; esac; done
n=$(date +%s%N)
mkdir -p "$CHAOS_BACKUP_DIR/db" "$CHAOS_BACKUP_DIR/data"
echo dump | gzip > "$CHAOS_BACKUP_DIR/db/chaos-db-chaos-$n.sql.gz"
tar -C "$server" --exclude='*.otbm' -czf "$CHAOS_BACKUP_DIR/data/chaos-data-$n.tar.gz" config.lua data
'''
INSTALL = r'''import os, re, sys
here = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, here)
import late_game
stub = os.environ['STUB']
with open(os.path.join(stub, 'calls'), 'a') as f:
    f.write('install %s\n' % ' '.join(sys.argv[2:]))
server = sys.argv[1]
if '--only' in sys.argv:
    sys.exit(0)
cfg = os.path.join(server, 'config.lua')
text = open(cfg).read()
text, _ = late_game.patch_config(text, False)
text = re.sub(r'(?m)^rateExp = .*$', 'rateExp = 1', text)
open(cfg, 'w').write(text)
open(os.path.join(server, 'data', 'installed.txt'), 'w').write(open(os.path.join(here, 'version.txt')).read())
print('[ok] files')
'''
PUBLISH = '#!/usr/bin/env bash\necho "publish $* site=${CHAOS_SITE_DIR:-}" >> "$STUB/calls"\n'
SITE = '#!/usr/bin/env bash\necho "site $*" >> "$STUB/calls"\n'

FAILS = []


def check(cond, what, out=''):
    if not cond:
        FAILS.append(what)
        print('FAIL: ' + what)
        if out:
            print(out[-3000:])


def write(path, data, mode=None):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'wb' if isinstance(data, bytes) else 'w') as f:
        f.write(data)
    if mode:
        os.chmod(path, mode)


def read(path):
    with open(path) as f:
        return f.read()


def sha(path):
    with open(path, 'rb') as f:
        return hashlib.sha256(f.read()).hexdigest()


class World:
    def __init__(self):
        self.root = tempfile.mkdtemp(prefix='chaos_kit_update_test_')
        r = self.root
        self.stub = os.path.join(r, 'stub')
        os.makedirs(os.path.join(self.stub, 'active'))
        os.makedirs(os.path.join(self.stub, 'assets'))
        for name, body in (('curl', CURL), ('systemctl', SYSTEMCTL), ('mariadb', MYSQL), ('ldd', LDD)):
            write(os.path.join(self.stub, 'bin', name), body, 0o755)
        self.kit = os.path.join(r, 'kit')
        self.server = os.path.join(self.kit, 'server')
        self.env = dict(os.environ, STUB=self.stub, KIT=self.kit,
                        PATH=os.path.join(self.stub, 'bin') + os.pathsep + os.environ['PATH'],
                        GIT_AUTHOR_NAME='t', GIT_AUTHOR_EMAIL='t@example.org', GIT_COMMITTER_NAME='t',
                        GIT_COMMITTER_EMAIL='t@example.org', GIT_CONFIG_NOSYSTEM='1', HOME=r)
        for k in list(self.env):
            if k.startswith('CHAOS_') or k == 'SUDO_USER':
                del self.env[k]
        # upstream, branch main
        self.origin = os.path.join(r, 'origin')
        o = self.origin
        self.git('init', '-q', '-b', 'main', o)
        write(os.path.join(o, '.gitignore'), '__pycache__/\n')
        write(os.path.join(o, 'server/tools/backup.sh'), BACKUP, 0o755)
        write(os.path.join(o, 'server/tools/install_all.py'), INSTALL)
        shutil.copy(LATE_GAME, os.path.join(o, 'server/tools/late_game.py'))
        shutil.copy(MAP_MASTER, os.path.join(o, 'server/tools/map_master.py'))
        shutil.copy(CHANGELOG, os.path.join(o, 'server/tools/gen_changelog.py'))
        os.makedirs(os.path.join(o, 'tools/ci'))
        shutil.copy(NAMES, os.path.join(o, 'tools/ci/check_names.py'))
        os.makedirs(os.path.join(o, 'server/deploy'))
        shutil.copy(RATES, os.path.join(o, 'server/deploy/chaos_config_rates.py'))
        shutil.copy(SCRIPT, os.path.join(o, 'server/deploy/chaos_kit_update.sh'))
        write(os.path.join(o, 'server/deploy/publish_client_update.sh'), PUBLISH, 0o755)
        write(os.path.join(o, 'website/install_site.sh'), SITE, 0o755)
        write(os.path.join(o, 'website/page.txt'), 'v1\n')
        write(os.path.join(o, 'server/tools/version.txt'), 'v1\n')
        self.commit('v1')
        self.git('-C', o, 'config', 'uploadpack.allowFilter', 'true')
        self.repo = os.path.join(r, 'repo')
        self.git('clone', '-q', o, self.repo)
        # the kit
        stages = late_game.stages_lua([(lo, hi, m * 10) for lo, hi, m in late_game.STAGES],
                                      '-- Chaos XP rate x10 (chaos-ctl.sh xp-rate)\n' + late_game.STAGES_MARK)
        write(os.path.join(self.server, 'config.lua'),
              'serverName = "test"\nrateExp = 10\nrateLoot = 2\n' + stages + '\nmapName = "map"\n')
        write(os.path.join(self.server, 'data/world/map.otbm'), 'map\n')
        write(os.path.join(self.server, 'tfs'), 'engine 46\n', 0o755)
        os.makedirs(os.path.join(self.kit, 'logs'))
        write(os.path.join(self.kit, 'logs/server.log'), 'Server Online (an old start)\n')
        self.envfile = os.path.join(self.kit, 'chaos.env')
        write(self.envfile, 'CHAOS_DB_USER=chaos\nCHAOS_DB_PASS=secret\nCHAOS_DB_PORT=3307\nCHAOS_BACKUP_DIR=%s\n'
              % os.path.join(r, 'backups'))
        write(os.path.join(self.stub, 'active', 'chaos-server'), '')
        # the site: live client update 46, downloads of 46
        self.site = os.path.join(r, 'site')
        write(os.path.join(self.site, 'updates/live/manifest.json'), json.dumps({'payload': json.dumps({'version': 46})}))
        self.dl = os.path.join(self.site, 'dl')
        write(os.path.join(self.dl, 'CindersOfChaos-Client-Windows.zip'), 'old windows\n')
        write(os.path.join(self.dl, 'CindersOfChaos-Client-Linux.tar.gz'), 'old linux\n')
        self.siteenv = os.path.join(r, 'site.env')
        write(self.siteenv, 'CHAOS_SITE_URL=https://example.org\n')
        self.state = os.path.join(r, 'state')
        self.releases = []

    def git(self, *args, cwd=None):
        r = subprocess.run(['git'] + list(args), cwd=cwd, env=self.env, capture_output=True, text=True)
        if r.returncode != 0:
            raise AssertionError('git %s: %s' % (args, r.stderr))
        return r.stdout.strip()

    def commit(self, msg):
        self.git('-C', self.origin, 'add', '-A')
        self.git('-C', self.origin, 'commit', '-q', '-m', msg)

    def push(self, msg, files):
        for path, text in files.items():
            write(os.path.join(self.origin, path), text)
        self.commit(msg)

    def map_master(self, otbm, damage=False):
        """packs OTBM (bytes) with tools/map_master.py into world/ of the branch windows-assets of the upstream (a
        branch of its own, as the real one); damage: one part changed after its checksum was written"""
        a = os.path.join(self.root, 'assets')
        if not os.path.isdir(a):
            self.git('init', '-q', '-b', 'windows-assets', a)
            write(os.path.join(a, 'things/big.bin'), os.urandom(200000))  # never fetched by the kit
        src = os.path.join(self.root, 'sent.otbm')
        write(src, otbm)
        r = subprocess.run([sys.executable, '-I', MAP_MASTER, 'pack', src, os.path.join(a, 'world'), '--part-size',
                            '3000'], capture_output=True, text=True)
        if r.returncode != 0:
            raise AssertionError('map_master.py pack: ' + r.stdout + r.stderr)
        if damage:
            p = os.path.join(a, 'world', 'map-master.otbm.xz.part00')
            b = bytearray(open(p, 'rb').read())
            b[50] ^= 0x77
            write(p, bytes(b))
        self.git('-C', a, 'add', '-A')
        self.git('-C', a, 'commit', '-q', '-m', 'map master')
        self.git('-C', a, 'push', '-q', '--force', self.origin, 'HEAD:refs/heads/windows-assets')

    def release(self, n, engine, entries=None, size_lie=False):
        """a winpkg-N release with the server package (engine text) and both client packages"""
        a = os.path.join(self.stub, 'assets')
        buf = io.BytesIO()
        with tarfile.open(fileobj=buf, mode='w:gz') as t:
            for name, data in (entries or [('CindersOfChaos-Server-Linux/server/tfs', engine.encode()),
                                           ('CindersOfChaos-Server-Linux/server/lib/libfmt.so.8.1.1',
                                            ('fmt of %s\n' % engine.strip()).encode()),
                                           ('CindersOfChaos-Server-Linux/server/lib/libfmt.so.8', '->libfmt.so.8.1.1'),
                                           ('CindersOfChaos-Server-Linux/server/pad.bin', os.urandom(1100000))]):
                info = tarfile.TarInfo(name)
                if isinstance(data, str) and data.startswith('->'):
                    info.type = tarfile.SYMTYPE
                    info.linkname = data[2:]
                    t.addfile(info)
                    continue
                info.size = len(data)
                info.mode = 0o755
                t.addfile(info, io.BytesIO(data))
        assets = {'CindersOfChaos-Server-Linux.tar.gz': buf.getvalue(),
                  'CindersOfChaos-Client-Windows.zip': os.urandom(1100000),
                  'CindersOfChaos-Client-Linux.tar.gz': os.urandom(1100000)}
        meta = []
        for name, data in assets.items():
            write(os.path.join(a, name), data)
            meta.append({'name': name, 'size': len(data) + (7 if size_lie else 0),
                         'digest': 'sha256:' + hashlib.sha256(data).hexdigest()})
        self.releases.insert(0, {'tag_name': 'winpkg-%d' % n, 'draft': False, 'assets': meta})
        self.releases.insert(0, {'tag_name': 'nightly', 'draft': False, 'assets': meta})
        write(os.path.join(self.stub, 'releases.json'), json.dumps(self.releases))

    def run(self, *args, extra=None, ctl=False):
        env = dict(self.env, CHAOS_REPO=self.repo, CHAOS_KIT_DIR=self.kit, CHAOS_RELEASE_REPO='owner/game',
                   CHAOS_KIT_STATE=self.state, CHAOS_WORK_DIR=self.root, CHAOS_BOOT_TIMEOUT='10',
                   CHAOS_SITE_DIR=self.site, CHAOS_SITE_ENV=self.siteenv, CHAOS_MYSQL='mariadb',
                   CHAOS_ENV=self.envfile, CHAOS_LOG=os.path.join(self.kit, 'logs/server.log'), **(extra or {}))
        write(os.path.join(self.stub, 'calls'), '')
        if ctl:
            env.update(CHAOS_CTL_NO_SUDO='1', CHAOS_CTL_CONF=os.path.join(self.root, 'none.conf'),
                       CHAOS_UPDATE_LOG=os.path.join(self.root, 'update.log'))
            cmd = ['bash', CTL] + list(args)
        else:
            cmd = ['bash', SCRIPT] + list(args)
        r = subprocess.run(cmd, env=env, capture_output=True, text=True, timeout=180)
        self.out = r.stdout + r.stderr
        self.calls = read(os.path.join(self.stub, 'calls')).splitlines()
        return r.returncode

    def kv(self):
        d = {}
        for line in self.out.splitlines():
            if '=' in line:
                k, v = line.split('=', 1)
                d.setdefault(k, v)
        return d

    def pos(self, prefix):
        for i, c in enumerate(self.calls):
            if c.startswith(prefix.split(' ')[0] + ' ') and all(part in c for part in prefix.split(' ')[1:]):
                return i
        return -1

    def state_value(self, key):
        for line in read(os.path.join(self.state, 'state')).splitlines():
            if line.startswith(key + '='):
                return line[len(key) + 1:]
        return None


def test_rates_tool():
    tmp = tempfile.mkdtemp(prefix='chaos_rates_test_')
    try:
        cfg = os.path.join(tmp, 'config.lua')
        write(cfg, '-- stock comment\nrateExp = 5\n' + late_game.stages_lua(late_game.STAGES, late_game.STAGES_MARK) + '\n')

        def rates(*a):
            r = subprocess.run([sys.executable, '-I', RATES] + list(a), capture_output=True, text=True)
            return r.returncode, r.stdout + r.stderr
        rc, out = rates('show', cfg)
        check(rc == 0 and 'xp=x1' in out and 'rateExp=5' in out, 'rates: show x1', out)
        rc, out = rates('set', cfg, '10')
        check(rc == 0 and 'xp=x10 set' in out, 'rates: set 10', out)
        rc, out = rates('show', cfg)
        check('xp=x10' in out and 'stage_first=%d' % (late_game.STAGES[0][2] * 10) in out, 'rates: show x10', out)
        check('-- stock comment' in read(cfg), 'rates: other comments stay')
        check(any(n.startswith('config.lua.before-xp-') for n in os.listdir(tmp)), 'rates: a backup of config.lua')
        for bad in ('0', '101', 'x', '1;2'):
            rc, out = rates('set', cfg, bad)
            check(rc != 0, 'rates: set %r refused' % bad)
        saved = os.path.join(tmp, 's.json')
        rates('save', cfg, saved)
        text, _ = late_game.patch_config(read(cfg), False)  # what install_all's lategame step does
        write(cfg, text.replace('rateExp = 5', 'rateExp = 1'))
        rc, out = rates('show', cfg)
        rc, out = rates('restore', cfg, saved)
        check('rateExp=5' in out and 'x10' in out, 'rates: restore says what came back', out)
        rc, out = rates('show', cfg)
        check('xp=x10' in out and 'rateExp=5' in out, 'rates: restored x10 and rateExp', out)
        rc, out = rates('reset', cfg)
        rc, out = rates('show', cfg)
        check('xp=x1' in out, 'rates: reset to x1', out)
        write(cfg, read(cfg).replace('multiplier = %d' % late_game.STAGES[0][2], 'multiplier = %d' % (late_game.STAGES[0][2] + 1), 1))
        check('xp=custom' in rates('show', cfg)[1], 'rates: a hand-made table is custom')
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def test_flow():
    w = World()
    try:
        w.release(47, 'engine 47\n')
        w.push('Fix the bank NPC\n\nlonger text', {'server/tools/version.txt': 'v2\n', 'website/page.txt': 'v2\n',
                                                    'server/tools/clientservices.py': '# services v2\n',
                                                    'tools/linux/server/start-server.sh': '#!/bin/sh\n# start v2\n'})
        rc = w.run('check')
        d = w.kv()
        check(rc == 0, 'check runs', w.out)
        check(d.get('branch') == 'main' and d.get('behind') == '1' and d.get('ahead') == '0', 'check: one commit behind', w.out)
        check(any(l.startswith('commit=') and l.endswith('Fix the bank NPC') for l in w.out.splitlines()),
              'check: the commit subject', w.out)
        check(d.get('installed_release') == 'unknown' and d.get('latest_release') == '47', 'check: releases', w.out)
        check(d.get('needs_engine') == 'yes' and d.get('needs_client') == 'yes' and d.get('published_client') == '46',
              'check: engine and client needed', w.out)
        check(d.get('needs_downloads') == 'yes' and d.get('website_changed') == 'yes', 'check: downloads, site', w.out)
        check(d.get('update_available') == 'yes' and d.get('running') == 'no', 'check: update available', w.out)
        check(d.get('map_master') == 'none' and d.get('installed_map') == '0' and d.get('needs_map') == 'no',
              'check: no map master branch', w.out)
        check(w.git('-C', w.repo, 'rev-parse', 'HEAD') != w.git('-C', w.origin, 'rev-parse', 'HEAD'),
              'check changes no checkout')

        # the lock: a second run is refused while one holds it
        os.makedirs(w.state, exist_ok=True)
        with open(os.path.join(w.state, '.lock'), 'w') as lk:
            fcntl.flock(lk, fcntl.LOCK_EX)
            rc = w.run('apply')
            check(rc != 0 and 'another update' in w.out, 'apply: refused while locked', w.out)
            rc = w.run('update-apply', ctl=True)
            check(rc != 0 and 'update-running' in w.out, 'chaos-ctl update-apply: refused while running', w.out)
            rc = w.run('check')
            check(w.kv().get('running') == 'yes', 'check: running=yes while locked', w.out)
        check('systemctl stop chaos-server' not in w.calls, 'locked: nothing stopped')

        # a missing library: refused before anything stops
        rc = w.run('apply', extra={'STUB_LDD_MISSING': '1'})
        check(rc == 1 and 'RESULT failed' in w.out and 'libraries' in w.out, 'apply: missing library refused', w.out)
        check(not any(c.startswith('systemctl stop') for c in w.calls), 'missing library: the server keeps running')

        old_engine = read(os.path.join(w.server, 'tfs'))
        rc = w.run('apply')
        out = w.out
        check(rc == 0 and 'RESULT ok' in out, 'apply: ok', out)
        steps = [l.split()[1] for l in out.splitlines() if l.startswith('STEP ')]
        check(steps == ['%d/10' % i for i in range(1, 11)], 'apply: ten steps %r' % steps, out)
        check('no map master' in out, 'apply: no map master, the map stays', out)
        order = [w.pos('backup'), w.pos('systemctl stop chaos-server'), w.pos('install --no-sql'),
                 w.pos('systemctl start chaos-server'), w.pos('install --only sql'), w.pos('systemctl restart chaos-server'),
                 w.pos('publish'), w.pos('site')]
        check(all(i >= 0 for i in order) and order == sorted(order), 'apply: order backup, stop, install, start, sql, '
              'restart, publish, site %r' % order, '\n'.join(w.calls))
        check(any('--mysql mariadb' in c for c in w.calls if c.startswith('install')), 'install_all gets --mysql')
        check(all('--proto =https' in c for c in w.calls if c.startswith('curl')), 'curl: https only')
        check(read(os.path.join(w.server, 'tfs')) == 'engine 47\n', 'apply: new engine installed')
        check(read(os.path.join(w.server, 'tfs.antes-47')) == old_engine, 'apply: old engine kept as tfs.antes-47')
        check(os.path.islink(os.path.join(w.server, 'lib', 'libfmt.so.8'))
              and os.readlink(os.path.join(w.server, 'lib', 'libfmt.so.8')) == 'libfmt.so.8.1.1',
              'apply: the engine libraries (server/lib, links kept) installed with the engine')
        check(read(os.path.join(w.server, 'lib', 'libfmt.so.8.1.1')).startswith('fmt of'),
              'apply: the library files come from the package')
        cfg = read(os.path.join(w.server, 'config.lua'))
        check('rateExp = 10' in cfg and 'multiplier = %d' % (late_game.STAGES[0][2] * 10) in cfg
              and 'Chaos XP rate x10' in cfg, 'apply: the x10 rates survive install_all', cfg)
        check('restored: rateExp=10' in out, 'apply: says the rates were restored', out)
        check(read(os.path.join(w.server, 'data/installed.txt')) == 'v2\n', 'apply: install_all of the new commit')
        cl = json.loads(read(os.path.join(w.server, 'data/changelog/changelog.json')))
        check([(e['text'], e['tags']) for e in cl['entries']] == [('Fix the bank NPC', ['website'])]
              and cl['published'] == 46, 'apply: the changelog written from the checkout (subject only)', cl)
        check('changelog: 1 entries' in out, 'apply: the changelog line', out)
        check(w.git('-C', w.repo, 'rev-parse', 'HEAD') == w.git('-C', w.origin, 'rev-parse', 'HEAD'),
              'apply: checkout at origin/main')
        check(w.git('-C', w.repo, 'rev-parse', '--abbrev-ref', 'HEAD') == 'main', 'apply: on branch main')
        check(any(c.startswith('publish -- winpkg-47') and 'site=' + w.site in c for c in w.calls),
              'apply: client update published with the site setting', '\n'.join(w.calls))
        win = os.path.join(w.dl, 'CindersOfChaos-Client-Windows.zip')
        check(read(win + '.prev') == 'old windows\n', 'downloads: old file kept as .prev')
        check(sha(win) == sha(os.path.join(w.stub, 'assets', 'CindersOfChaos-Client-Windows.zip')), 'downloads: new file')
        check(read(win + '.sha256').split()[0] == sha(win), 'downloads: .sha256 next to it')
        dj = json.load(open(os.path.join(w.dl, 'downloads.json')))
        check(dj.get('release') == 47 and dj['files']['CindersOfChaos-Client-Linux.tar.gz']['size'] == 1100000,
              'downloads.json: release and sizes %r' % dj)
        check(not [n for n in os.listdir(w.dl) if n.startswith('.')], 'downloads: no temporary files left')
        check(any(c.startswith('site ') for c in w.calls), 'apply: the site installed (website/ changed)')
        check(w.state_value('installed_release') == '47' and w.state_value('status') == 'ok', 'state: release 47, ok')
        check(read(os.path.join(w.server, 'tools', 'clientservices.py')) == '# services v2\n',
              'apply: the kit gets clientservices.py it lacked (an older kit)')
        check(read(os.path.join(w.kit, 'start-server.sh')) == '#!/bin/sh\n# start v2\n'
              and os.access(os.path.join(w.kit, 'start-server.sh'), os.X_OK), 'apply: start-server.sh brought up to date')
        check('kit helper files: 2 updated' in w.out, 'apply: says how many helper files changed', w.out)
        check(not [n for n in os.listdir(w.root) if n.startswith('chaos-kit-update.')], 'apply: work folder removed')

        rc = w.run('check')
        d = w.kv()
        check(d.get('behind') == '0' and d.get('needs_engine') == 'no' and d.get('update_available') == 'no'
              and d.get('downloads_release') == '47' and d.get('last_status') == 'ok', 'check after apply: current', w.out)

        # nothing new: no restart
        rc = w.run('apply', '--no-client', '--no-downloads', '--no-site')
        check(rc == 0 and not any(c.startswith('systemctl stop') or c.startswith('systemctl restart') for c in w.calls),
              'apply with nothing new: no restart', w.out)
        check(w.run('apply', '--bogus') != 0, 'apply: unknown option refused')
        check(w.state_value('site_commit') == w.git('-C', w.repo, 'rev-parse', 'HEAD'), 'state: the site commit')

        # the checkout moved by hand (git reset): the site still counts from its own commit
        w.push('Site text', {'website/page.txt': 'v3\n'})
        w.git('-C', w.repo, 'fetch', '--quiet', 'origin', '+refs/heads/main:refs/remotes/origin/main')
        w.git('-C', w.repo, 'reset', '--quiet', '--hard', 'origin/main')
        w.run('check')
        check(w.kv().get('website_changed') == 'yes', 'check: a site change behind a hand reset', w.out)
        rc = w.run('apply', '--no-client', '--no-downloads')
        check(rc == 0 and any(c.startswith('site ') for c in w.calls), 'apply: the site installed after a hand reset', w.out)
        check(w.state_value('site_commit') == w.git('-C', w.repo, 'rev-parse', 'HEAD'), 'state: the site commit moves')
        w.run('check')
        check(w.kv().get('website_changed') == 'no', 'check: the site current', w.out)

        # a broken engine: rolled back automatically
        good_commit = w.git('-C', w.repo, 'rev-parse', 'HEAD')
        w.release(48, 'BROKEN engine 48\n')
        w.push('Break it', {'server/tools/version.txt': 'v3\n'})
        rc = w.run('apply', '--no-client', '--no-downloads')
        check(rc == 2 and 'RESULT rolled-back' in w.out, 'broken engine: rolled back (exit 2)', w.out)
        check(read(os.path.join(w.server, 'tfs')) == 'engine 47\n', 'rollback: engine 47 back')
        check(w.git('-C', w.repo, 'rev-parse', 'HEAD') == good_commit, 'rollback: previous commit')
        check(read(os.path.join(w.server, 'data/installed.txt')) == 'v2\n', 'rollback: data/ from the backup')
        check('rateExp = 10' in read(os.path.join(w.server, 'config.lua')), 'rollback: config.lua of before')
        check(os.path.exists(os.path.join(w.server, 'data/world/map.otbm')), 'rollback: the map carried over')
        check(w.state_value('installed_release') == '47' and w.state_value('status') == 'rolled-back',
              'state after the rollback')
        check(os.path.exists(os.path.join(w.stub, 'active', 'chaos-server')), 'rollback: the server runs')

        # a good release again, then the manual rollback (engine, commit, downloads)
        w.release(49, 'engine 49\n')
        w.push('Fix it', {'server/tools/version.txt': 'v4\n'})
        rc = w.run('apply', '--no-client')
        check(rc == 0 and read(os.path.join(w.server, 'tfs')) == 'engine 49\n', 'apply 49', w.out)
        rc = w.run('update-rollback', ctl=True)
        check(rc == 0 and 'started' in w.out, 'chaos-ctl update-rollback starts', w.out)
        for _ in range(200):
            if 'RESULT' in read(os.path.join(w.root, 'update.log')):
                break
            subprocess.run(['sleep', '0.1'])
        log = read(os.path.join(w.root, 'update.log'))
        check('RESULT ok' in log, 'manual rollback: ok', log)
        check(read(os.path.join(w.server, 'tfs')) == 'engine 47\n', 'manual rollback: engine 47', log)
        check(w.git('-C', w.repo, 'rev-parse', 'HEAD') == good_commit, 'manual rollback: commit')
        dj = json.load(open(os.path.join(w.dl, 'downloads.json')))
        check(dj.get('release') == 47, 'manual rollback: downloads of 47 back')
        # downloads on their own: the site serves 47 while 49 is out (the signed client update was published by hand)
        rc = w.run('downloads', '--bogus')
        check(rc != 0, 'downloads refuses an unknown option', w.out)
        installed_before = w.state_value('installed_release')
        rc = w.run('downloads')
        check(rc == 0 and 'RESULT ok: the site' in w.out and 'release 49 now' in w.out, 'downloads: replaced by 49', w.out)
        dj = json.load(open(os.path.join(w.dl, 'downloads.json')))
        check(dj.get('release') == 49, 'downloads: downloads.json says 49', dj)
        check(sha(win) == sha(os.path.join(w.stub, 'assets', 'CindersOfChaos-Client-Windows.zip')),
              'downloads: the newest zip is in place')
        check(not any(c.startswith(('systemctl', 'publish', 'site')) for c in w.calls) ,
              'downloads: no restart, no client update, no site install', '\n'.join(w.calls))
        check(w.state_value('installed_release') == installed_before, 'downloads: the installed server release is untouched')
        rc = w.run('downloads')
        check(rc == 0 and 'already' in w.out and 'RESULT ok' in w.out, 'downloads: nothing to do when current', w.out)
        before = sha(win)
        rc = w.run('downloads', '--force')
        check(rc == 0 and 'release 49 now' in w.out and sha(win) == before, 'downloads --force replaces the same release', w.out)
        rc = w.run('update-downloads', ctl=True)
        check(rc == 0 and 'started' in w.out, 'chaos-ctl update-downloads starts', w.out)
        for _ in range(200):
            if 'RESULT' in read(os.path.join(w.root, 'update.log')):
                break
            subprocess.run(['sleep', '0.1'])
        check('RESULT ok' in read(os.path.join(w.root, 'update.log')), 'chaos-ctl update-downloads: ok')
        rc = w.run('update-downloads', ';reboot', ctl=True)
        check(rc != 0, 'chaos-ctl update-downloads refuses other arguments', w.out)
        rc = w.run('rollback')
        check(rc != 0 and 'nothing recorded' in w.out, 'a second rollback has nothing to go back to', w.out)
        rc = w.run('update-status', ctl=True)
        check('status=ok' in w.out and 'running=no' in w.out, 'chaos-ctl update-status', w.out)

        # refusals of the download
        w.release(50, 'engine 50\n', size_lie=True)
        rc = w.run('apply')
        check(rc == 1 and 'refused' in w.out and not any(c.startswith('systemctl stop') for c in w.calls),
              'a size that differs from GitHub is refused', w.out)
        w.release(51, '', entries=[('../evil', b'x'), ('CindersOfChaos-Server-Linux/server/tfs', b'engine 51\n'),
                                   ('pad', os.urandom(1100000))])
        rc = w.run('apply')
        check(rc == 1 and 'unsafe path' in w.out, 'an unsafe tar entry is refused', w.out)
        check(not os.path.exists(os.path.join(w.root, 'evil')), 'nothing written outside')
        write(os.path.join(w.repo, 'server/tools/version.txt'), 'local change\n')
        rc = w.run('apply')
        check(rc == 1 and 'changed files' in w.out, 'a dirty checkout is refused', w.out)
    finally:
        shutil.rmtree(w.root, ignore_errors=True)


def test_map():
    w = World()
    try:
        target = os.path.join(w.server, 'data/world/map.otbm')
        old_map = read(target)
        w.release(47, 'engine 47\n')
        rc = w.run('apply', '--no-client', '--no-downloads', '--no-site')
        check(rc == 0, 'map: a first apply without a map master', w.out)

        m1 = map_master_test.fake_map('edited', 11, size=7000)
        w.map_master(m1)
        rc = w.run('check')
        d = w.kv()
        check(rc == 0 and d.get('map_master') == '1' and d.get('installed_map') == '0' and d.get('needs_map') == 'yes'
              and d.get('update_available') == 'yes', 'map: check sees version 1', w.out)
        big = w.git('-C', w.origin, 'rev-parse', 'windows-assets:things/big.bin')
        missing = w.git('-C', w.repo, 'rev-list', '--objects', '--missing=print', 'origin/windows-assets')
        check('?' + big in missing.split(), 'map: the other files of the branch are not fetched', missing)

        rc = w.run('apply', '--no-client', '--no-downloads', '--no-site')
        out = w.out
        check(rc == 0 and 'RESULT ok' in out and 'map master 1' in out, 'map: apply installs version 1', out)
        missing = w.git('-C', w.repo, 'rev-list', '--objects', '--missing=print', 'origin/windows-assets')
        check('?' + big in missing.split(), 'map: apply fetches only world/', missing)
        new = open(target, 'rb').read()
        check(new.endswith(m1[-2000:]), 'map: the map is the master', out)
        hdr = map_master_test.M.read_header(new)
        check(map_master_test.M.file_names(hdr).get('spawn') == 'map-spawn.xml', 'map: the header names map-spawn.xml')
        backups = os.listdir(os.path.join(w.kit, 'map-backups'))
        check(len(backups) == 1 and backups[0].startswith('map.otbm.')
              and read(os.path.join(w.kit, 'map-backups', backups[0])) == old_map, 'map: the old map kept %r' % backups)
        order = [w.pos('backup'), w.pos('systemctl stop chaos-server'), w.pos('install --no-sql'),
                 w.pos('systemctl restart chaos-server')]
        check(all(i >= 0 for i in order) and order == sorted(order), 'map: backup, stop, install, restart %r' % order)
        i_map = out.find('map master version 1 in place')
        check(0 <= out.find('stopping chaos-server') < i_map < out.find('install_all.py (every step'),
              'map: replaced after the stop and before install_all', out)
        check(w.state_value('map_version') == '1', 'map: state map_version')
        rc = w.run('check')
        check(w.kv().get('needs_map') == 'no' and w.kv().get('installed_map') == '1', 'map: check after apply', w.out)

        # the same version: nothing restarted
        rc = w.run('apply', '--no-client', '--no-downloads', '--no-site')
        check(rc == 0 and 'version 1 already' in w.out and not any(c.startswith('systemctl stop') for c in w.calls),
              'map: the same version is skipped, no restart', w.out)

        # a damaged part: refused before anything stops
        w.map_master(map_master_test.fake_map('edited', 12, size=7000), damage=True)
        rc = w.run('apply', '--no-client', '--no-downloads', '--no-site')
        check(rc == 1 and 'map master was refused' in w.out and not any(c.startswith('systemctl stop') for c in w.calls),
              'map: a damaged master refused, the server keeps running', w.out)
        check(open(target, 'rb').read() == new, 'map: the map stays after a refusal')
        rc = w.run('apply', '--no-client', '--no-downloads', '--no-site', '--no-map')
        check(rc == 0 and 'skipped (--no-map)' in w.out, 'map: --no-map', w.out)

        # version 3 with a broken engine: the automatic rollback puts version 1 back
        m3 = map_master_test.fake_map('edited', 13, size=7000)
        w.map_master(m3)
        w.release(48, 'BROKEN engine 48\n')
        rc = w.run('apply', '--no-client', '--no-downloads', '--no-site')
        check(rc == 2 and 'map put back' in w.out, 'map: rolled back with the engine', w.out)
        check(open(target, 'rb').read() == new, 'map: version 1 back after the rollback')
        check(json.load(open(target + '.master.json'))['version'] == 1, 'map: the marker of version 1 back')

        # a good engine: version 3 in; the manual rollback puts version 1 back
        w.release(49, 'engine 49\n')
        rc = w.run('apply', '--no-client', '--no-downloads', '--no-site')
        check(rc == 0 and open(target, 'rb').read().endswith(m3[-2000:]), 'map: version 3 installed', w.out)
        rc = w.run('rollback')
        check(rc == 0 and open(target, 'rb').read() == new, 'map: the manual rollback puts version 1 back', w.out)
        rc = w.run('check')
        check(w.kv().get('installed_map') == '1' and w.kv().get('needs_map') == 'yes', 'map: check after the rollback',
              w.out)
    finally:
        shutil.rmtree(w.root, ignore_errors=True)


def main():
    test_rates_tool()
    test_flow()
    test_map()
    print('chaos_kit_update_test: %d failures' % len(FAILS))
    return 1 if FAILS else 0


if __name__ == '__main__':
    sys.exit(main())
