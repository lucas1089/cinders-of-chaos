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

The live spectator (2026-10-23): spectate NAME refuses bad names and queues nothing for them, queues "spectate NAME" once
per 5 s, waits for a fresh snapshot of that name, runs the renderer (a stub) with the name as one argument, keeps one
view at a time (busy, exit 75) and one every 0.8 s, answers no-answer for an old snapshot; spectate-pair status and its
refusals (no git checkout, a bad branch).
The live cast (phase 2): cast NAME refuses bad names, is off without castPort (or with a port out of range), queues
"cast NAME", runs the relay (a stub reading stdin to its end) with the port and the name as one argument, queues
"caststop" when it ends, and keeps one cast at a time (busy, exit 75).

Progress metrics (O253): metrics [--json] runs one fixed read-only query against chaos_progress_metrics (stub mysql),
pipes the rows to server/tools/progress_metrics.py, prints text or one JSON line, answers {"ok": false, "error": ...} with
exit 1 when the table or the database is missing, and refuses any argument (nothing reaches the shell or the SQL).

Discord (discord-set / -enable / -disable / -test / -status): the webhook URL only on stdin and only if it matches the
strict pattern (hosts, id and token lengths, no extra path or query, no second line), never on a command line (curl gets
it as a config line on its stdin), never in any output; /etc/chaos/discord.env created mode 600, rewritten in place of the
old line only, CHAOS_SITE_URL filled from the site env, empty input removes a line, a channel name outside the list (or
with shell characters) refused; enable installs the units and the logrotate file, disable stops the timer; test reports
the HTTP code per channel; status shows yes/no and the last 4 id digits, masks a token in log and queue lines.

usage: python3 -I server/deploy/chaos_ctl_test.py
"""
import json
import os
import shutil
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
  *StandardOutput*) [ -n "${STUB_SVCLOG:-}" ] && echo "append:$STUB_SVCLOG" || echo journal ;;
  list-unit-files*) printf 'chaos-backup.timer enabled\nchaos-helpai.service enabled\nchaos-server.service enabled\napache2.service enabled\nssh.service enabled\n' ;;
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
  *"SELECT id FROM players WHERE"*) echo "${STUB_PID:-}" ;;
  *"FROM players_online WHERE player_id"*) echo "${STUB_ONLINE:-0}" ;;
  *"DISTINCT player_name"*) echo Gma; echo "Bad;Name" ;;
  *chaos_admin_log*) printf '2026-10-21 10:00\\tGma\\tplayers.kick\\tBob\\tok\\tdone\\n' ;;
  *COUNT*) echo 7 ;;
  *players_online*) printf 'Bob\\t120\\t3\\n' ;;
esac
'''
RECORD = '''#!/usr/bin/env bash
echo "$(basename "$0") $*" >> "$STUB/calls"
case "$(basename "$0") $*" in
  "apt-get -s"*) printf 'Inst libfoo [1] (2 Debian)\nInst php8.3-fpm [3] (4 Ubuntu)\nConf libfoo\n' ;;
  dpkg-query*) printf 'libapache2-mod-php 2:8.3+93ubuntu2\nlibapache2-mod-php8.3 8.3.6-0ubuntu0.24.04.13\nphp8.2-fpm \n' ;;
  apt-get*) echo "stub apt-get $*" ;;
  journalctl*) echo "journal line" ;;
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
                           ('visudo', NOOP), ('install', NOOP), ('apt-get', RECORD), ('shutdown', RECORD), ('dpkg-query', RECORD),
                           ('journalctl', RECORD)):
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

        # publish-apk (O313 step 8): the Android app update, release tags only, same background log
        for bad in (('publish-apk',), ('publish-apk', '/tmp/x.apk'), ('publish-apk', 'a;b'), ('publish-apk', 'v1..2'),
                    ('publish-apk', 'android-31', 'android-32'), ('publish-apk', '--min-version-code', 'x'),
                    ('publish-apk', 'android-31', '--key', '/tmp/k')):
            check(run(*bad, extra=pe).returncode != 0, 'publish-apk refuses %r' % (bad,))
        for argv, want in ((('android-31',), 'args --apk android-31'),
                           (('android-31', '--min-version-code', '30'), 'args --apk android-31 --apk-min-version-code 30'),
                           (('--remove',), 'args --no-apk'),
                           (('--min-version-code', '31'), 'args --apk-min-version-code 31')):
            r = run('publish-apk', *argv, extra=pe)
            check(r.returncode == 0 and 'publish-log' in r.stdout, 'publish-apk %r starts: %s' % (argv, r.stdout + r.stderr))
            for _ in range(50):
                if os.path.exists(plog) and 'site=' in open(plog).read():
                    break
                time.sleep(0.1)
            out = run('publish-log', extra=pe).stdout
            check(want in out and 'site=/srv/site' in out, 'publish-apk %r passes %r: %s' % (argv, want, out))


        # catalog and panel: a thread plays the engine and answers what the script queued
        import threading

        def engine(kind):
            seen = len(spool())  # only a line queued after this call counts

            def go():
                for _ in range(40):
                    time.sleep(0.1)
                    m = re.findall(r'^(catalog .*|panel (\d+) .*)$', spool()[seen:], re.M)
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

        # reload-files / reload-file (O312): the config names on disk, the panel action server.reload_file with one bare name
        cdir = os.path.join(server, 'data', 'scripts', 'chaos')
        os.makedirs(cdir, exist_ok=True)
        for fname in ('pace_config.lua', 'arena_config.lua', 'arena_core.lua', 'Bad_config.lua', 'x-y_config.lua', 'notes.txt'):
            open(os.path.join(cdir, fname), 'w').write('return {}\n')
        r = run('reload-files')
        check(r.returncode == 0 and r.stdout.split() == ['arena_config', 'pace_config'], 'reload-files lists only config names: ' + r.stdout + r.stderr)
        check(run('reload-files', 'x').returncode != 0, 'reload-files takes no argument')
        before = spool()
        t = engine('panel')
        r = run('reload-file', 'Gma', 'pace_config')
        t.join()
        check(r.returncode == 0 and '"message":"done"' in r.stdout, 'reload-file prints the panel answer: ' + r.stdout + r.stderr)
        check(re.search(r'panel \d{9} server\.reload_file\|Gma\|\{"file":"pace_config"\}\n$', spool()) is not None,
              'reload-file queues the panel action with the bare name')
        t = engine('panel')
        r = run('reload-file', 'Gma')
        t.join()
        check(re.search(r'panel \d{9} server\.reload_file\|Gma\|\{"file":""\}\n$', spool()) is not None, 'reload-file without a name lists')
        before = spool()
        for bad in (('reload-file',), ('reload-file', 'Gma', '../pace_config'), ('reload-file', 'Gma', 'pace_config.lua'),
                    ('reload-file', 'Gma', 'Pace_config'), ('reload-file', 'Gma', 'a;b'), ('reload-file', 'Gma', 'a b'),
                    ('reload-file', 'Gma', 'a"b'), ('reload-file', 'Gma', '$(id)'), ('reload-file', 'Gma', 'a\nb'),
                    ('reload-file', 'Gma', '/etc/passwd'), ('reload-file', 'Gma', 'a', 'b'), ('reload-file', 'x', 'a_config'),
                    ('reload-file', 'Gma;x', 'a_config'), ('reload-file', 'Gma', 'a' * 70)):
            check(run(*bad).returncode != 0, 'reload-file refuses %r' % (bad,))
        check(spool() == before, 'refused reload-file queues nothing')

        # spectate: the name checked, "spectate NAME" queued (again only after 5 s), a fresh snapshot of that name
        # awaited, the renderer (a stub) run with the name as one argument; busy, no answer; spectate-pair
        spstate = os.path.join(tmp, 'spstate')
        tools = os.path.join(tmp, 'repo', 'server', 'tools')
        os.makedirs(tools, exist_ok=True)
        with open(os.path.join(tools, 'spectate_render.py'), 'w') as f:
            f.write('import json, sys\nprint(json.dumps({"ok": True, "args": sys.argv[1:]}))\n')
        spe = {'CHAOS_SPECTATE_STATE': spstate, 'CHAOS_SPECTATE_PAIR': os.path.join(tmp, 'pair')}
        before = spool()
        for bad in (('spectate',), ('spectate', 'ab'), ('spectate', 'Bob;ls'), ('spectate', '$(id)'), ('spectate', 'Bob '),
                    ('spectate', 'Bo  b'), ('spectate', '1Bob'), ('spectate', 'Bob', 'Ann'), ('spectate', 'Bob\nsave')):
            check(run(*bad, extra=spe).returncode != 0, 'spectate refuses %r' % (bad[1:],))
        check(spool() == before, 'a refused spectate queues nothing')

        def spect_engine(name):
            def go():
                for _ in range(60):
                    time.sleep(0.1)
                    if ('spectate %s\n' % name) in spool():
                        with open(os.path.join(server, 'remote.spectate'), 'w') as f:
                            f.write('{"v":1,"online":true,"watch":"%s","t":%d}' % (name, int(time.time())))
                        return
            t = threading.Thread(target=go)
            t.start()
            return t

        t = spect_engine("Sir O'Neil")
        r = run('spectate', "Sir O'Neil", extra=spe)
        t.join()
        check(r.returncode == 0 and r.stdout.startswith('{"ok": true'), 'spectate prints the answer: ' + r.stdout + r.stderr)
        args = json.loads(r.stdout)['args'] if r.returncode == 0 else []
        check(args[:1] == ['render'] and "Sir O'Neil" in args and '--watch' in args, 'the name is one argument: %r' % args)
        check(os.path.join(server, 'remote.spectate') in args and os.path.join(tmp, 'pair', 'Tibia.spr') in args,
              'the snapshot and the pair: %r' % args)
        check(spool() == before + "spectate Sir O'Neil\n", 'spectate queues its line')
        check(oct(os.stat(spstate).st_mode & 0o777) == oct(0o700), 'the state folder is private')
        t0 = time.time()
        r = run('spectate', "Sir O'Neil", extra=spe)
        check(r.returncode == 0, 'a second view at once: ' + r.stderr)
        check(spool() == before + "spectate Sir O'Neil\n", 'within 5 s the watch is not queued again')
        check(time.time() - t0 >= 0.5, 'at most one view every 0.8 s')
        import fcntl
        with open(os.path.join(spstate, 'lock'), 'w') as lk:
            fcntl.flock(lk, fcntl.LOCK_EX)
            r = run('spectate', "Sir O'Neil", extra=spe)
        check(r.returncode == 75 and '"busy"' in r.stdout, 'one view at a time: busy, exit 75: ' + r.stdout)
        with open(os.path.join(server, 'remote.spectate'), 'w') as f:
            f.write('{"v":1,"online":true,"watch":"Ann Other","t":1}')
        os.utime(os.path.join(server, 'remote.spectate'), (1, 1))
        r = run('spectate', 'Ann Other', extra=spe)
        check(r.returncode == 1 and '"no-answer"' in r.stdout, 'an old snapshot is no answer: ' + r.stdout)
        check(spool().endswith('spectate Ann Other\n'), 'another name is queued at once')
        r = run('spectate-pair', 'status', extra=spe)
        check(r.returncode == 0 and 'branch=windows-assets' in r.stdout and 'fetching=no' in r.stdout
              and '"info"' in r.stdout, 'spectate-pair status: ' + r.stdout + r.stderr)
        for bad in (('spectate-pair', 'nope'), ('spectate-pair', 'fetch', 'x'), ('spectate-pair', 'log', 'x')):
            check(run(*bad, extra=spe).returncode != 0, 'spectate-pair refuses %r' % (bad[1:],))
        r = run('spectate-pair', 'fetch-now', extra=spe)
        check(r.returncode != 0 and 'no git checkout' in r.stderr, 'fetch-now needs the git checkout: ' + r.stderr)
        r = run('spectate-pair', 'fetch-now', extra=dict(spe, CHAOS_PAIR_BRANCH='a..b'))
        check(r.returncode != 0 and 'bad CHAOS_PAIR_BRANCH' in r.stderr, 'a bad branch is refused')

        # cast: the name checked, the port from config.lua, "cast NAME" queued, the relay (a stub that reads stdin to
        # its end) run in the foreground with the name as one argument, "caststop" queued after; busy; port off
        with open(os.path.join(tools, 'cast_relay.py'), 'w') as f:
            f.write('import json, sys\nsys.stdin.read()\nprint(json.dumps({"t": "end", "args": sys.argv[1:]}))\n')
        os.makedirs(os.path.join(tmp, 'pair'), exist_ok=True)
        for fn in ('Tibia.dat', 'Tibia.spr'):
            open(os.path.join(tmp, 'pair', fn), 'wb').close()
        cfg_lua = os.path.join(server, 'config.lua')
        had_cfg = open(cfg_lua).read() if os.path.exists(cfg_lua) else None
        before = spool()
        for bad in (('cast',), ('cast', 'ab'), ('cast', 'Bob;ls'), ('cast', '$(id)'), ('cast', 'Bob '), ('cast', 'Bo  b'),
                    ('cast', '1Bob'), ('cast', 'Bob', 'Ann'), ('cast', 'Bob\ncaststop')):
            check(run(*bad, extra=spe).returncode != 0, 'cast refuses %r' % (bad[1:],))
        r = run('cast', 'Bob', extra=spe)
        check(r.returncode != 0 and '"cast-off"' in r.stdout, 'no castPort: the cast is off: ' + r.stdout)
        check(spool() == before, 'a refused cast queues nothing')
        with open(cfg_lua, 'a') as f:
            f.write('\ncastPort = 7179 -- the live cast\n')
        r = run('cast', "Sir O'Neil", extra=spe, stdin='')
        args = json.loads(r.stdout)['args'] if r.returncode == 0 and r.stdout.startswith('{') else []
        check(r.returncode == 0 and "Sir O'Neil" in args and args[args.index('--port') + 1] == '7179',
              'cast runs the relay with the port and the name as one argument: %r %s' % (args, r.stderr))
        check(os.path.join(tmp, 'pair', 'Tibia.dat') in args and '--max-seconds' in args, 'the pair and the limit')
        check(spool() == before + "cast Sir O'Neil\ncaststop\n", 'cast queues its line, then caststop: %r'
              % spool()[len(before):])
        r = run('cast', 'Bob', extra=dict(spe, CHAOS_CAST_PORT='70000'))
        check(r.returncode != 0 and '"cast-off"' in r.stdout, 'a port out of range is off')
        with open(os.path.join(spstate, 'cast.lock'), 'w') as lk:
            fcntl.flock(lk, fcntl.LOCK_EX)
            r = run('cast', 'Bob', extra=spe)
        check(r.returncode == 75 and '"busy"' in r.stdout, 'one cast at a time: busy, exit 75: ' + r.stdout)
        if had_cfg is None:
            os.remove(cfg_lua)
        else:
            with open(cfg_lua, 'w') as f:
                f.write(had_cfg)

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

        # ---- errors clear: a marker line, the list counts only what comes after it; the log keeps every line
        cleared_log = os.path.join(tmp, 'cleared.log')
        shutil.copy(runs_log, cleared_log)
        r = run('errors', 'clear', extra={'CHAOS_LOG': cleared_log})
        check(r.returncode == 0 and 'cleared' in r.stdout, 'errors clear: ' + r.stdout + r.stderr)
        with open(cleared_log) as f:
            kept = f.read()
        check('56x' not in kept and kept.count('MySQL error') == 56 and 'list cleared by the owner' in kept,
              'errors clear: the log keeps every line, a marker appended')
        with open(cleared_log, 'a') as f:
            f.write('[2026-10-20 10:00:00] Exception: after the clear\n')
        for name, d in awks:
            extra = {'CHAOS_LOG': cleared_log, 'PATH': d + ':' + env['PATH']}
            lines = run('errors', extra=extra).stdout.splitlines()
            check(lines == ['@run 2026-10-20 08:00:01 current', '1x Exception: after the clear [2026-10-20 10:00:00]',
                            '@older 0'], '%s errors after a clear: only the new error: %r' % (name, lines))
            r = run('errors', 'all', extra=extra)
            check('MySQL' not in r.stdout and 'bad thing' not in r.stdout and 'after the clear' in r.stdout,
                  '%s errors all after a clear: nothing older: %r' % (name, r.stdout))
            out = dict(l.split('=', 1) for l in run('status', extra=extra).stdout.splitlines() if '=' in l)
            check(out.get('errors') == '1', '%s status after a clear: %r' % (name, out.get('errors')))
        check(run('errors', 'clear', 'x').returncode != 0, 'errors clear takes nothing more')

        # ---- vps, services, service, service-log (2026-10-22)
        out = dict(l.split('=', 1) for l in run('vps').stdout.splitlines() if '=' in l)
        for k in ('host', 'kernel', 'load', 'cpus', 'mem_total_mb', 'disk_free_gb', 'upgrades', 'reboot_required',
                  'reboot_at'):
            check(k in out, 'vps info: %s' % k)
        check(out.get('upgrades') == '2', 'vps info: the pending packages: %r' % out.get('upgrades'))
        check(out.get('php_upgrades') == '1', 'vps info: the pending PHP packages: %r' % out.get('php_upgrades'))
        check(out.get('php') == 'libapache2-mod-php8.3 8.3.6-0ubuntu0.24.04.13', 'vps info: the PHP package: %r' % out.get('php'))
        vlog = os.path.join(tmp, 'vps-upgrade.log')
        r = run('vps', 'upgrade', extra={'CHAOS_VPS_LOG': vlog})
        check(r.returncode == 0 and 'started' in r.stdout, 'vps upgrade: ' + r.stdout + r.stderr)
        for _ in range(50):
            if os.path.exists(vlog) and 'done (exit 0)' in open(vlog).read():
                break
            time.sleep(0.1)
        text = open(vlog).read()
        check('stub apt-get update' in text and 'stub apt-get -y' in text and 'force-confold' in text
              and 'done (exit 0)' in text, 'vps upgrade: update, then upgrade keeping config files: ' + text)
        check(not os.path.exists(vlog + '.pid'), 'vps upgrade: the pid file is gone when it ends')
        r = run('vps', 'upgrade-log', '5', extra={'CHAOS_VPS_LOG': vlog})
        check('done (exit 0)' in r.stdout, 'vps upgrade-log: ' + r.stdout)
        before = spool()
        r = run('vps', 'reboot', '5')
        check(r.returncode == 0 and 'shutdown -r +5' in calls(), 'vps reboot 5: ' + r.stdout + r.stderr)
        check(spool()[len(before):].startswith('broadcast The server machine restarts in 5 minute(s)'),
              'vps reboot: players are warned: %r' % spool()[len(before):])
        for bad in (('vps', 'reboot'), ('vps', 'reboot', '0'), ('vps', 'reboot', '61'), ('vps', 'reboot', '5;x'),
                    ('vps', 'nope')):
            check(run(*bad).returncode != 0, 'refused: %r' % (bad,))
        r = run('vps', 'reboot-cancel')
        check(r.returncode == 0 and 'shutdown -c' in calls(), 'vps reboot-cancel: ' + r.stdout + r.stderr)
        r = run('services')
        check(r.stdout.splitlines() == ['apache2.service active enabled', 'chaos-backup.timer active enabled',
                                        'chaos-helpai.service active enabled', 'chaos-server.service active enabled'], 'services: ' + r.stdout + r.stderr)
        r = run('service', 'chaos-helpai', 'restart')
        check(r.returncode == 0 and 'systemctl restart chaos-helpai' in calls(), 'service restart: ' + r.stdout + r.stderr)
        r = run('service', 'apache2', 'restart')
        check(r.returncode == 0 and 'systemctl restart apache2' in calls(), 'service restart apache2: ' + r.stdout + r.stderr)
        for bad in (('service', 'sshd', 'stop'), ('service', 'chaos-helpai', 'enable'), ('service', 'chaos-x;rm', 'stop'),
                    ('service', '../chaos-x', 'stop'), ('service', 'chaos-helpai'), ('service-log', 'ssh'),
                    ('service', 'apache2x', 'restart'), ('service', 'php8.3-fpm;x', 'restart')):
            check(run(*bad).returncode != 0, 'refused: %r' % (bad,))
        check('systemctl stop sshd' not in calls() and 'enable chaos' not in calls(), 'a refused service runs nothing')
        svclog = os.path.join(tmp, 'helpai.log')
        with open(svclog, 'w') as f:
            f.write('\n'.join('helpai %d' % i for i in range(30)) + '\n')
        r = run('service-log', 'chaos-helpai', '3', extra={'STUB_SVCLOG': svclog})
        check(r.stdout.splitlines()[1:] == ['helpai 27', 'helpai 28', 'helpai 29'], 'service-log: its file: ' + r.stdout)
        r = run('service-log', 'chaos-backup.timer')
        check('journal line' in r.stdout and 'journalctl -u chaos-backup.timer -n 60' in calls(),
              'service-log: the journal without a file: ' + r.stdout)

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
    test_metrics()
    test_feedback()
    test_discord()
    test_discord_bot()
    test_server_user()
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
        shutil.copy(os.path.join(repo_root, 'server', 'tools', 'client_pair.py'), os.path.join(repo, 'server', 'tools'))
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

        # client-pair: the record of the shipped client's sprite pair in config.lua (server/README.md "Client pair guard")
        r = run('client-pair')
        check(r.returncode == 0 and 'chaosClientPair=missing' in r.stdout, 'client-pair: missing by default: ' + r.stdout + r.stderr)
        r = run('client-pair', 'set', '55')
        check(r.returncode == 0 and 'chaosClientPair=55' in run('client-pair', 'show').stdout, 'client-pair set 55: ' + r.stdout + r.stderr)
        check(run('client-pair', 'set', '54').returncode != 0 and 'chaosClientPair=55' in run('client-pair', 'show').stdout,
              'client-pair: lowering refused')
        check(run('client-pair', 'set', '56').returncode == 0 and 'chaosClientPair=56' in run('client-pair', 'show').stdout,
              'client-pair set 56')
        check('rateExp = 5' in open(cfg).read(), 'client-pair leaves the rest of config.lua alone')
        for bad in (('client-pair', 'set'), ('client-pair', 'set', 'x'), ('client-pair', 'set', '5;x'), ('client-pair', 'set', '1000'),
                    ('client-pair', 'set', '5', '6'), ('client-pair', 'bogus')):
            check(run(*bad).returncode != 0, 'client-pair refuses %r' % (bad,))

        # beta-mode: the `enabled` line of beta_mode_config.lua (sed --follow-symlinks, backup, checked), restart on request
        sdir = os.path.join(server, 'data', 'scripts', 'chaos')
        os.makedirs(sdir)
        real = os.path.join(tmp, 'real_beta_mode_config.lua')
        shutil.copy(os.path.join(repo_root, 'server', 'data', 'scripts', 'chaos', 'beta_mode_config.lua'), real)
        bfile = os.path.join(sdir, 'beta_mode_config.lua')
        os.symlink(real, bfile)  # a symlinked file keeps its link (sed --follow-symlinks)
        open(os.path.join(stub, 'calls'), 'w').close()  # the restarts of the xp-rate checks are history
        r = run('beta-mode')
        check(r.returncode == 0 and 'beta_mode=off' in r.stdout, 'beta-mode: off by default: ' + r.stdout + r.stderr)
        before = open(real).read()
        r = run('beta-mode', 'on')
        check(r.returncode == 0 and 'beta_mode=on' in r.stdout and 'next restart' in r.stdout, 'beta-mode on: ' + r.stdout + r.stderr)
        check(os.path.islink(bfile), 'beta-mode on: the symlink is kept')
        check('beta_mode=on' in run('beta-mode', 'status').stdout, 'beta-mode: on after on')
        after = open(real).read()
        check(after == before.replace('enabled = false,', 'enabled = true,', 1), 'beta-mode on: only the enabled line changed')
        check(open(bfile + '.before-beta').read() == before, 'beta-mode on: a backup of the file before')
        check('systemctl restart' not in calls(), 'beta-mode on without restart does not restart')
        r = run('beta-mode', 'on')
        check(r.returncode == 0 and 'unchanged' in r.stdout, 'beta-mode on twice is a no-op: ' + r.stdout)
        r = run('beta-mode', 'off', 'restart')
        check(r.returncode == 0 and 'systemctl restart chaos-server' in calls(), 'beta-mode off restart: ' + r.stderr)
        check(open(real).read() == before, 'beta-mode off: back to the original text')
        for bad in (('beta-mode', 'maybe'), ('beta-mode', 'on', 'now'), ('beta-mode', 'status', 'x'), ('beta-mode', 'off', 'restart', 'x')):
            check(run(*bad).returncode != 0, 'beta-mode refuses %r' % (bad,))

        # clientservices-impl: python by default; rust builds first (a failed build changes nothing), adds the systemd
        # drop-in and restarts; python removes it; rebuild only while on
        csroot = os.path.join(tmp, 'csroot')
        sysd = os.path.join(tmp, 'sysd')
        cbuild_dir = os.path.join(repo, 'server', 'services', 'clientservices-rs')
        os.makedirs(cbuild_dir, exist_ok=True)
        with open(os.path.join(cbuild_dir, 'build.sh'), 'w') as f:
            f.write('#!/bin/sh\n[ ! -f "$0.fail" ] || { echo cargo failed >&2; exit 3; }\nmkdir -p "$(dirname "$1")"\n'
                    'echo "$(cat "$1" 2>/dev/null)x" > "$1"; chmod 755 "$1"\n')
        csx = {'CHAOS_ROOT': csroot, 'CHAOS_SYSTEMD_DIR': sysd, 'CHAOS_CS_SETTLE': '0'}
        drop = os.path.join(sysd, 'chaos-clientservices.service.d', '10-rust.conf')
        r = run('clientservices-impl', extra=csx)
        check(r.returncode == 0 and 'clientservices_impl=python' in r.stdout and 'binary=missing' in r.stdout,
              'clientservices-impl: python by default: ' + r.stdout + r.stderr)
        open(os.path.join(stub, 'calls'), 'w').close()
        r = run('clientservices-impl', 'rust', extra=csx)
        check(r.returncode == 0 and 'clientservices_impl=rust' in r.stdout, 'clientservices-impl rust: ' + r.stdout + r.stderr)
        dtext = open(drop).read() if os.path.exists(drop) else ''
        check('ExecStart=\n' in dtext and 'ExecStart=%s/bin/clientservices-rs %s/data/chaos_clientservices.json --host 0.0.0.0 --port 8090\n'
              % (csroot, server) in dtext, 'clientservices-impl rust: the drop-in resets and sets ExecStart: ' + dtext)
        check(os.access(os.path.join(csroot, 'bin', 'clientservices-rs'), os.X_OK), 'clientservices-impl rust: the binary is installed')
        check('systemctl daemon-reload' in calls() and 'systemctl restart chaos-clientservices' in calls(),
              'clientservices-impl rust: reload and restart')
        check('clientservices_impl=rust' in run('clientservices-impl', 'status', extra=csx).stdout and
              'binary=present' in run('clientservices-impl', extra=csx).stdout, 'clientservices-impl: status says rust')
        r = run('clientservices-impl', 'rebuild', extra=csx)
        check(r.returncode == 0 and open(os.path.join(csroot, 'bin', 'clientservices-rs')).read().count('x') == 2,
              'clientservices-impl rebuild: builds again while on: ' + r.stderr)
        open(os.path.join(cbuild_dir, 'build.sh.fail'), 'w').close()
        r = run('clientservices-impl', 'rebuild', extra=csx)
        check(r.returncode != 0 and os.path.exists(drop), 'clientservices-impl: a failed build leaves the switch as it was')
        r = run('clientservices-impl', 'python', extra=csx)
        check(r.returncode == 0 and 'clientservices_impl=python' in r.stdout and not os.path.exists(drop),
              'clientservices-impl python: the drop-in is removed: ' + r.stdout + r.stderr)
        r = run('clientservices-impl', 'rust', extra=csx)
        check(r.returncode != 0 and not os.path.exists(drop), 'clientservices-impl rust: a failed build writes no drop-in')
        os.remove(os.path.join(cbuild_dir, 'build.sh.fail'))
        r = run('clientservices-impl', 'rebuild', extra=csx)
        check(r.returncode == 0 and 'nothing to rebuild' in r.stdout, 'clientservices-impl rebuild: nothing while python')
        r = run('clientservices-impl', 'rust', extra=dict(csx, STUB_NOUNIT='1'))
        check(r.returncode != 0 and 'unit-not-found' in r.stderr and not os.path.exists(drop),
              'clientservices-impl rust: no unit installed is refused')
        for bad in (('clientservices-impl', 'go'), ('clientservices-impl', 'rust', 'x'), ('clientservices-impl', 'status', 'x')):
            check(run(*bad, extra=csx).returncode != 0, 'clientservices-impl refuses %r' % (bad,))

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

        # gm-set: staff group and account type, only for an offline character; the name is quoted for SQL
        r = run('gm-set', "Sir O'Neil", '6', extra={'STUB_PID': '42'})
        check(r.returncode == 0 and 'group 6' in r.stdout, 'gm-set: ' + r.stdout + r.stderr)
        c = calls()
        check("name = 'Sir O''Neil'" in c and 'SET group_id = 6 WHERE id = 42' in c and 'a.type = 6 WHERE p.id = 42' in c,
              'gm-set: quoted name, group and account type: ' + c)
        r = run('gm-set', 'Bob', '4', extra={'STUB_PID': '42', 'STUB_ONLINE': '1'})
        check(r.returncode != 0 and 'online' in r.stderr, 'gm-set: an online character is refused')
        r = run('gm-set', 'Ghost', '4')
        check(r.returncode != 0 and 'character-not-found' in r.stderr, 'gm-set: no such character')
        for bad in (('gm-set', 'Bob', '7'), ('gm-set', 'Bob', '0'), ('gm-set', 'Bob'), ('gm-set', 'Bob;x', '4'),
                    ('gm-set', 'Bob', '4', 'x'), ('gm-set', 'ab', '4')):
            check(run(*bad, extra={'STUB_PID': '42'}).returncode != 0, 'gm-set refuses %r' % (bad,))

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
                    ('update-rollback', 'x'), ('update-downloads', '--yes'), ('update-downloads', ';reboot')):
            check(run(*bad, extra=kit).returncode != 0, 'refused: %r' % (bad,))
        r = run('update-downloads', '--force', extra=kit)
        check(r.returncode == 0 and 'started' in r.stdout, 'update-downloads --force starts: ' + r.stdout + r.stderr)
        r = run('update', 'v1', 'now', extra=kit)
        check(r.returncode != 0 and 'kit-layout' in r.stderr, 'update TAG on the kit points to update-apply')
        r = run('rollback', 'at-save', extra=kit)
        check(r.returncode != 0 and 'kit-layout' in r.stderr, 'rollback at-save on the kit is refused')
        r = run('update-status', extra=dict(kit, CHAOS_KIT_STATE=os.path.join(tmp, 'kstate')))
        check(r.returncode == 0 and 'running=no' in r.stdout and 'status=' in r.stdout,
              'update-status: ' + r.stdout + r.stderr)
        r = run('site-install', extra={'CHAOS_SITE_ENV': os.path.join(tmp, 'nope.env')})
        check(r.returncode != 0, 'site-install without a site settings file is refused')

        # areas-publish: the map inbox into CHAOS_DL_DIR/areas-TOKEN (a stub area_inbox.py), a token kept in a 600 file
        atool = os.path.join(repo, 'server', 'tools')
        os.makedirs(atool, exist_ok=True)
        dl = os.path.join(tmp, 'dl')
        os.makedirs(dl)
        asite = os.path.join(tmp, 'site.env')
        with open(asite, 'w') as f:
            f.write('CHAOS_SITE_URL=https://www.example.org   # the site\n')
        astate = os.path.join(tmp, 'astate')
        aextra = {'CHAOS_DL_DIR': dl, 'CHAOS_SITE_ENV': asite, 'CHAOS_AREAS_STATE': astate}
        r = run('areas-publish', extra=aextra)
        check(r.returncode != 0 and 'area_inbox.py' in r.stderr, 'areas-publish without the tool is refused: ' + r.stderr)
        with open(os.path.join(atool, 'area_inbox.py'), 'w') as f:
            f.write('import os, sys\n'
                    'with open(os.environ["STUB"] + "/acalls", "a") as c: c.write(" ".join(sys.argv[1:]) + "\\n")\n'
                    'if os.environ.get("STUB_AFAIL"): print("boom"); sys.exit(1)\n'
                    'out = sys.argv[2]\nos.makedirs(out + "/mire")\n'
                    'open(out + "/list.txt", "w").write("mire|pending|50-140|Mire\\n")\n'
                    'open(out + "/mire/mire.otbm", "w").write("x")\n')
        for bad in (('areas-publish', '--yes'), ('areas-publish', ';reboot'), ('areas-publish', '../x')):
            check(run(*bad, extra=aextra).returncode != 0, 'areas-publish refuses %r' % (bad,))
        r = run('areas-publish', extra=aextra)
        check(r.returncode == 0 and 'areas-published: 1 area(s)' in r.stdout, 'areas-publish runs: ' + r.stdout + r.stderr)
        tok = open(os.path.join(astate, 'token')).read().strip()
        check(re.fullmatch(r'[0-9a-f]{32}', tok) is not None, 'the token is 32 hex digits: ' + tok)
        check(stat.S_IMODE(os.stat(os.path.join(astate, 'token')).st_mode) == 0o600, 'the token file is mode 600')
        check('url=https://www.example.org/dl/areas-%s/' % tok in r.stdout, 'the url is printed: ' + r.stdout)
        check(os.path.isfile(os.path.join(dl, 'areas-' + tok, 'mire', 'mire.otbm')) and
              os.path.isfile(os.path.join(dl, 'areas-' + tok, 'list.txt')), 'the files are in dl/areas-TOKEN')
        check(stat.S_IMODE(os.stat(os.path.join(dl, 'areas-' + tok)).st_mode) == 0o755, 'the folder is readable by the web server')
        check([n for n in os.listdir(dl) if n.startswith('.areas')] == [], 'no temporary folder is left')
        acalls = open(os.path.join(stub, 'acalls')).read()
        check('--assets' not in acalls, 'no pictures unless asked')
        r = run('areas-publish', extra=aextra)
        check(open(os.path.join(astate, 'token')).read().strip() == tok, 'a second run keeps the token')
        r = run('areas-publish', '--pictures', extra=aextra)
        check('--assets' in open(os.path.join(stub, 'acalls')).read(), '--pictures passes the render inputs')
        r = run('areas-publish', extra=dict(aextra, STUB_AFAIL='1'))
        check(r.returncode != 0 and os.path.isfile(os.path.join(dl, 'areas-' + tok, 'list.txt')) and
              [n for n in os.listdir(dl) if n.startswith('.areas')] == [], 'a failed build leaves the published folder as it was')
        r = run('areas-publish', '--rotate', extra=aextra)
        tok2 = open(os.path.join(astate, 'token')).read().strip()
        check(r.returncode == 0 and tok2 != tok and os.path.isdir(os.path.join(dl, 'areas-' + tok2)) and
              not os.path.exists(os.path.join(dl, 'areas-' + tok)), '--rotate: a new token, the old folder is gone')


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
                f.write('-- ' + name + '\nHELPER_VERSION = 7\n')
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
        check(r.returncode != 0 and 'helper-not-loaded' in r.stderr, 'testers: an older helper copy without a version counts as not loaded')
        hv = '7'
        with open(log, 'a') as f:
            f.write('[tester-helper] running v%s (TEST ONLY)\n' % hv)
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
            check('--keystones' not in calls, 'a plain start has no --keystones: ' + calls)
            check('ab' * 32 not in calls and 'secret' not in calls, 'no key and no password on a command line')
            check('db=yes' in calls, 'the database settings reach testers.py by the environment')
            check(os.getpgid(pid) == pid, 'the run has its own process group')
            with open(log, 'a') as f:
                f.write('[tester-helper] testers online: 3\n[tester-helper] testers online: 4\n')
            r = run('testers', 'status', extra={'STUB_BOTS': '5'})
            out = dict(l.split('=', 1) for l in r.stdout.splitlines() if '=' in l)
            check(out.get('running') == 'yes' and out.get('pid') == str(pid) and out.get('bots') == '5'
                  and out.get('helper') == 'copied' and out.get('helper_loaded') == 'yes', 'testers status: ' + r.stdout)
            check(out.get('online_server') == '4', 'testers status: the helper\'s last console count: ' + r.stdout)
            r = run('testers', 'start', '5', '2')
            check(r.returncode != 0 and 'already running' in r.stderr, 'a second start is refused')
            r = run('testers', 'cleanup', '--yes', extra={'CHAOS_TESTERS_STOP_WAIT': '1'})
            check(r.returncode == 0 and 'waiting' in r.stdout, 'cleanup right after a stop waits, then deletes: '
                  + r.stdout + r.stderr)
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
        r = run('testers', 'log')
        check(r.returncode != 0 and 'no activity log yet' in r.stderr, 'log: none yet, refused')
        os.makedirs(os.path.join(state, 'runs'), exist_ok=True)
        for stamp, body in (('20261022-100000', 'old\n'), ('20261022-110000', ''.join('line %d\n' % i for i in range(300)))):
            with open(os.path.join(state, 'runs', 'run-%s.log' % stamp), 'w') as f:
                f.write(body)
        r = run('testers', 'log', '5')
        check(r.returncode == 0 and 'run-20261022-110000.log (300 lines)' in r.stdout and 'line 299' in r.stdout
              and 'line 294' not in r.stdout and 'old' not in r.stdout, 'log: the newest run, its last N lines:\n' + r.stdout)
        r = run('testers', 'log', '0')
        check(r.returncode != 0, 'log: N 0 refused')
        r = run('testers', 'log', 'x;id')
        check(r.returncode != 0, 'log: N not a number refused')

        # --keystones (O249): the run gets the flag; without it none; a wrong order of options is refused
        before = tcalls()
        r = run('testers', 'start', '2', '1', '--keystones', extra={'STUB_BOTS': '5'})
        check(r.returncode == 0 and 'keystones and masteries first' in r.stdout, 'start --keystones: ' + r.stdout + r.stderr)
        pid = int(open(os.path.join(state, 'run.pid')).read())
        for _ in range(50):
            if 'run --key-file' in tcalls()[len(before):]:
                break
            time.sleep(0.1)
        new = tcalls()[len(before):]
        check('--scenarios' in new and new.split('--scenarios', 1)[1].split()[1:2] == ['--keystones'],
              'the run gets --keystones after the table: ' + new)
        r = run('testers', 'stop')
        try:
            os.killpg(pid, signal.SIGKILL)
        except OSError:
            pass
        check(run('testers', 'start', '--keystones', 'x').returncode != 0, 'start: a word that is not a number is refused')

        # --checks (O110): the run gets the flag after the table; both flags together give both
        before = tcalls()
        r = run('testers', 'start', '2', '1', '--checks', extra={'STUB_BOTS': '5'})
        check(r.returncode == 0 and 'system checks' in r.stdout, 'start --checks: ' + r.stdout + r.stderr)
        pid = int(open(os.path.join(state, 'run.pid')).read())
        for _ in range(50):
            if 'run --key-file' in tcalls()[len(before):]:
                break
            time.sleep(0.1)
        new = tcalls()[len(before):]
        check('--scenarios' in new and new.split('--scenarios', 1)[1].split()[1:2] == ['--checks'],
              'the run gets --checks after the table: ' + new)
        run('testers', 'stop')
        try:
            os.killpg(pid, signal.SIGKILL)
        except OSError:
            pass

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


METRICS_MYSQL = '''#!/usr/bin/env bash
echo "$(basename "$0") $*" >> "$STUB/calls"
case "$*" in
  *chaos_progress_metrics*)
    case "${STUB_METRICS_FAIL:-}" in
      table) echo "ERROR 1146 (42S02) at line 1: Table 'chaos.chaos_progress_metrics' doesn't exist" >&2; exit 1 ;;
      db) echo "ERROR 2002 (HY000): Can't connect to local MySQL server" >&2; exit 1 ;;
    esac
    cat "$STUB/metrics.tsv" ;;
esac
'''

# synthetic counters: no real player, name or account
METRICS_ROWS = [
    ('churn', '1-5', 'gone', 30), ('churn', '1-5', 'active', 10), ('churn', '6-10', 'gone', 5),
    ('churn', '6-10', 'active', 15), ('churn', '11-15', 'gone', 0), ('churn', '11-15', 'active', 0),
    ('churn', '101-150', 'gone', 1), ('churn', '101-150', 'active', 3),
    ('meta', 'churn_at', '', 1760000000), ('meta', 'churn_days', '', 14),
    ('death_area', 'Ember Caves', '6-10', 12), ('death_area', 'Ember Caves', '11-15', 3),
    ('death_area', 'Frost Hold', '6-10', 20),
    ('death_monster', 'Dragon', '11-15', 9), ('death_monster', 'Rat', '1-5', 40),
    ('session1', '5', '', 6), ('session1', '10', '', 2), ('session1', '30', '', 2), ('session1', 'inf', '', 1),
    ('ttl', '10', '10', 10), ('ttl', '10', '20', 10), ('ttl', '25', '60', 4),
]


FEEDBACK_MYSQL = '''#!/usr/bin/env bash
echo "$(basename "$0") $*" >> "$STUB/calls"
case " $* " in *" -e "*) ;; *) cat > "$STUB/stdin"; echo "STDIN: $(cat "$STUB/stdin")" >> "$STUB/calls" ;; esac
case "$*" in
  *"FROM chaos_reports"*) [ -z "${STUB_FB_FAIL:-}" ] || { echo "ERROR 2002 can't connect" >&2; exit 1; }
    cat "$STUB/feedback.tsv" ;;
esac
if grep -q "UPDATE chaos_reports" "$STUB/stdin" 2>/dev/null; then echo "${STUB_FB_ROWS:-1}"; fi
'''


def test_feedback():
    """chaos-ctl.sh feedback / feedback-close (and server/tools/feedback_format.py)"""
    repo_root = os.path.dirname(os.path.dirname(HERE))
    with tempfile.TemporaryDirectory() as tmp:
        stub = os.path.join(tmp, 'stub')
        repo = os.path.join(tmp, 'repo')
        os.makedirs(stub)
        os.makedirs(os.path.join(repo, 'server', 'tools'))
        shutil.copy(os.path.join(repo_root, 'server', 'tools', 'feedback_format.py'), os.path.join(repo, 'server', 'tools'))
        for name, body in (('systemctl', SYSTEMCTL), ('mysql', FEEDBACK_MYSQL)):
            p = os.path.join(stub, name)
            with open(p, 'w') as f:
                f.write(body)
            os.chmod(p, 0o755)
        chat = 'Category: map\\nCharacter position: 1, 2, 3\\nLevel 120, Mystic\\nSent 2026-10-27 14:03:00'
        rows = [['12', '1793109780', '[map] Wall \\\\x missing\\nnear the gate', '1010', '990', '7', chat, 'open', '', 'Bobby'],
                ['11', '1793000000', '[suggestion] more depots\x07 \u202eplease', '5', '6', '7', '', 'closed', 'done; thanks', 'Al']]
        with open(os.path.join(stub, 'feedback.tsv'), 'w') as f:
            f.write(''.join('\t'.join(r) + '\n' for r in rows))
        env_file = os.path.join(tmp, 'chaos.env')
        with open(env_file, 'w') as f:
            f.write('CHAOS_DB_USER=chaos\nCHAOS_DB_PASS=secret\n')
        env = dict(os.environ, PATH=stub + ':' + os.environ['PATH'], STUB=stub, CHAOS_CTL_NO_SUDO='1',
                   CHAOS_SERVER_DIR=os.path.join(tmp, 'server'), CHAOS_ENV=env_file, CHAOS_REPO=repo,
                   CHAOS_MYSQL='mysql', CHAOS_CTL_CONF=os.path.join(tmp, 'none.conf'),
                   CHAOS_PID_FILE=os.path.join(tmp, 'no.pid'), CHAOS_LOG=os.path.join(tmp, 'no.log'))
        for k in ('SUDO_USER', 'CHAOS_UNIT', 'CHAOS_ROOT', 'CHAOS_KIT_DIR', 'CHAOS_DB_SOCKET', 'STUB_FB_FAIL', 'STUB_FB_ROWS'):
            env.pop(k, None)

        def run(*args, extra=None):
            return subprocess.run(['bash', SCRIPT] + list(args), env=dict(env, **(extra or {})), capture_output=True,
                                  text=True, timeout=60)

        def calls():
            p = os.path.join(stub, 'calls')
            return open(p).read() if os.path.exists(p) else ''

        def reset():
            if os.path.exists(os.path.join(stub, 'calls')):
                os.unlink(os.path.join(stub, 'calls'))

        r = run('feedback')
        check(r.returncode == 0, 'feedback runs: ' + r.stderr)
        q = calls()
        check("reason = 'bug'" in q and "status = 'open'" in q and '* 86400' in q and 'UNIX_TIMESTAMP() - 30 *' in q,
              'feedback: default query is open, 30 days: ' + q)
        for column in ('reporter_account', 'account', 'ip', 'email', 'reporter_id', 'target_id'):
            check(not re.search(r'\b%s\b' % column, q.split('mysql', 1)[-1].replace('chaos_reports', '')), 'feedback never selects ' + column)
        check('reporter_name' not in q, 'feedback: the name is not even selected without --names')
        check(r.stdout.splitlines()[0] == '#12 | 2026-10-27 14:03 UTC | map | open | pos 1010,990,7 | lvl 120 Mystic',
              'feedback: header line: ' + r.stdout)
        check('  Wall \\x missing near the gate' in r.stdout, 'feedback: text unescaped on one line: ' + r.stdout)
        check('Bobby' not in r.stdout and 'Al\n' not in r.stdout and 'from:' not in r.stdout, 'feedback: no names by default')
        check('#11 | ' in r.stdout and 'closed: done; thanks' in r.stdout, 'feedback: closed rows with the staff note')
        check('\x07' not in r.stdout and '\u202e' not in r.stdout and 'more depots please' in r.stdout,
              'feedback: control and bidi characters stripped')
        check(r.stdout.rstrip().endswith('-- 2 reports'), 'feedback: footer')
        check('secret' not in calls().replace('STDIN', ''), 'feedback: the database password is not on a command line')
        reset()
        r = run('feedback', '--names', '--all', '--days', '7', '--category', 'suggestion')
        q = calls()
        check(r.returncode == 0 and 'from: Bobby' in r.stdout and 'from: Al' in r.stdout, 'feedback --names prints names: ' + r.stdout)
        check('reporter_name FROM' in q and "status = 'open'" not in q and '- 7 * 86400' in q
              and "note LIKE '[suggestion] %'" in q, 'feedback options reach the query: ' + q)
        reset()
        check(run('feedback', '--category', 'all').returncode == 0 and 'note LIKE' not in calls(), 'feedback --category all')
        before = calls()
        for bad in (('--days',), ('--days', '0'), ('--days', 'x'), ('--days', '99999'), ('--days', '1;id'),
                    ('--category', "x' OR 1=1 --"), ('--category',), ('--category', 'map;id'), ('--bogus',), ('x',),
                    ('--days', '$(id)'), ('--names=1',)):
            r = run('feedback', *bad)
            check(r.returncode != 0, 'feedback refuses %r' % (bad,))
        check(calls() == before, 'feedback: a refused call never reaches the database')
        with open(os.path.join(stub, 'feedback.tsv'), 'w') as f:
            f.write('')
        check('No bug reports or suggestions.' in run('feedback').stdout, 'feedback: nothing to show')
        r = run('feedback', extra={'STUB_FB_FAIL': '1'})
        check(r.returncode != 0 and 'database-down' in r.stderr and 'No bug' not in r.stdout, 'feedback: database down is an error')

        # feedback-close
        reset()
        r = run('feedback-close', '12', 'fixed in the next update')
        check(r.returncode == 0 and r.stdout.strip() == 'closed #12', 'feedback-close: ' + r.stdout + r.stderr)
        sql = open(os.path.join(stub, 'stdin')).read()
        check("status = 'closed'" in sql and 'WHERE id = 12 AND reason = \'bug\' AND status = \'open\'' in sql,
              'feedback-close: the update: ' + sql)
        check('CONVERT(0x%s USING utf8mb4)' % 'fixed in the next update'.encode().hex() in sql, 'feedback-close: note as hex: ' + sql)
        reset()
        hostile = "x'; DROP TABLE chaos_reports; -- \\\\ \"\n\x07 \u202e ok"
        r = run('feedback-close', '7', hostile)
        sql = open(os.path.join(stub, 'stdin')).read()
        check(r.returncode == 0 and 'DROP' not in sql and "x'" not in sql and '\\' not in sql and '\x07' not in sql,
              'feedback-close: a hostile note never reaches the SQL as text: ' + sql)
        check(re.search(r"staff_note = CONVERT\(0x[0-9a-f]+ USING utf8mb4\) WHERE id = 7 ", sql), 'feedback-close: hex literal only: ' + sql)
        r = run('feedback-close', '007')
        sql = open(os.path.join(stub, 'stdin')).read()
        check(r.returncode == 0 and "staff_note = ''" in sql and 'WHERE id = 7 ' in sql, 'feedback-close: no note, 007 is 7: ' + sql)
        r = run('feedback-close', '12', extra={'STUB_FB_ROWS': '0'})
        check(r.returncode != 0 and 'feedback-not-found' in r.stderr, 'feedback-close: not open -> error: ' + r.stderr)
        reset()
        for bad in ((), ('x',), ('1;id',), ('-1',), ('1 OR 1=1',), ('1234567890',), ("1' OR '1",), ('$(id)',)):
            r = run('feedback-close', *bad)
            check(r.returncode != 0, 'feedback-close refuses %r' % (bad,))
        check(calls() == '', 'feedback-close: a refused call never reaches the database')


def test_metrics():
    """chaos-ctl.sh metrics [--json]"""
    repo_root = os.path.dirname(os.path.dirname(HERE))
    with tempfile.TemporaryDirectory() as tmp:
        stub = os.path.join(tmp, 'stub')
        repo = os.path.join(tmp, 'repo')
        os.makedirs(stub)
        os.makedirs(os.path.join(repo, 'server', 'tools'))
        shutil.copy(os.path.join(repo_root, 'server', 'tools', 'progress_metrics.py'),
                    os.path.join(repo, 'server', 'tools'))
        for name, body in (('systemctl', SYSTEMCTL), ('mysql', METRICS_MYSQL)):
            p = os.path.join(stub, name)
            with open(p, 'w') as f:
                f.write(body)
            os.chmod(p, 0o755)
        with open(os.path.join(stub, 'metrics.tsv'), 'w') as f:
            f.write(''.join('\t'.join(str(c) for c in row) + '\n' for row in METRICS_ROWS))
        env_file = os.path.join(tmp, 'chaos.env')
        with open(env_file, 'w') as f:
            f.write('CHAOS_DB_USER=chaos\nCHAOS_DB_PASS=secret\n')
        env = dict(os.environ, PATH=stub + ':' + os.environ['PATH'], STUB=stub, CHAOS_CTL_NO_SUDO='1',
                   CHAOS_SERVER_DIR=os.path.join(tmp, 'server'), CHAOS_ENV=env_file, CHAOS_REPO=repo,
                   CHAOS_MYSQL='mysql', CHAOS_CTL_CONF=os.path.join(tmp, 'none.conf'),
                   CHAOS_PID_FILE=os.path.join(tmp, 'no.pid'), CHAOS_LOG=os.path.join(tmp, 'no.log'))
        for k in ('SUDO_USER', 'CHAOS_UNIT', 'CHAOS_ROOT', 'CHAOS_KIT_DIR', 'CHAOS_DB_SOCKET', 'STUB_METRICS_FAIL'):
            env.pop(k, None)

        def run(*args, extra=None):
            return subprocess.run(['bash', SCRIPT] + list(args), env=dict(env, **(extra or {})), capture_output=True,
                                  text=True, timeout=60)

        def calls():
            p = os.path.join(stub, 'calls')
            return open(p).read() if os.path.exists(p) else ''

        r = run('metrics', '--json')
        check(r.returncode == 0 and r.stdout.count('\n') == 1, 'metrics --json: one line: ' + r.stdout + r.stderr)
        try:
            d = json.loads(r.stdout)
        except ValueError:
            d = {}
            check(False, 'metrics --json: valid JSON: ' + r.stdout)
        check(d.get('ok') is True, 'metrics --json: ok')
        check('SELECT kind, k1, k2, n FROM chaos_progress_metrics' in calls(), 'metrics: the fixed query: ' + calls())
        check(d.get('churn', {}).get('days') == 14 and d['churn']['gone'] == 36 and d['churn']['active'] == 28,
              'metrics: churn totals: ' + str(d.get('churn')))
        bands = [b['band'] for b in d.get('churn', {}).get('bands', [])]
        check(bands == ['1-5', '6-10', '11-15', '101-150'], 'metrics: bands in level order: %r' % (bands,))
        check(d['churn']['bands'][0]['gonePct'] == 75.0, 'metrics: gone share of band 1')
        check([e['name'] for e in d.get('deathAreas', [])] == ['Frost Hold', 'Ember Caves']
              and d['deathAreas'][1]['deaths'] == 15 and d['deathAreas'][1]['topBand'] == '6-10', 'metrics: death areas')
        check([e['name'] for e in d.get('deathMonsters', [])] == ['Rat', 'Dragon'], 'metrics: death monsters')
        check(d.get('milestones', [{}])[0].get('medianMinutes') == 10.0 and d['milestones'][0]['characters'] == 20,
              'metrics: median time to level 10: ' + str(d.get('milestones')))
        check(d.get('firstSessionCharacters') == 11, 'metrics: first sessions')
        r = run('metrics')
        check(r.returncode == 0 and 'Churn (gone = no login for 14 days; 36 gone, 28 active)' in r.stdout
              and 'Ember Caves' in r.stdout and 'level 10: 10 min' in r.stdout, 'metrics: text: ' + r.stdout + r.stderr)
        r = run('metrics', '--json', extra={'STUB_METRICS_FAIL': 'table'})
        check(r.returncode == 1 and json.loads(r.stdout) == {'ok': False, 'error': 'no-table'},
              'metrics: no table: ' + r.stdout + r.stderr)
        r = run('metrics', '--json', extra={'STUB_METRICS_FAIL': 'db'})
        check(r.returncode == 1 and json.loads(r.stdout) == {'ok': False, 'error': 'database'},
              'metrics: no database: ' + r.stdout + r.stderr)
        with open(os.path.join(stub, 'metrics.tsv'), 'w') as f:
            f.write('')
        r = run('metrics', '--json')
        check(r.returncode == 0 and json.loads(r.stdout).get('empty') is True, 'metrics: an empty table: ' + r.stdout)
        before = calls()
        for bad in (('metrics', 'x'), ('metrics', '--json', 'x'), ('metrics', '--json;id'), ('metrics', '$(id)'),
                    ('metrics', '--top', '3'), ('metrics', "' OR 1=1 --")):
            r = run(*bad)
            check(r.returncode != 0, 'metrics refuses %r' % (bad,))
        check(calls() == before, 'metrics: a refused call never reaches the database')
        # a missing tool is told, not a traceback
        os.unlink(os.path.join(repo, 'server', 'tools', 'progress_metrics.py'))
        r = run('metrics', '--json')
        check(r.returncode != 0 and 'progress_metrics.py' in r.stderr, 'metrics: a missing tool is named: ' + r.stderr)


def test_discord():
    repo_root = os.path.dirname(os.path.dirname(HERE))
    token = 'AbCdEfGhIjKlMnOpQrStUvWxYz0123456789_-aBcD'
    hook = 'https://discord.com/api/webhooks/123456789012345678/' + token
    hook2 = 'https://canary.discord.com/api/webhooks/987654321098765432/' + token[::-1]
    curl = '''#!/usr/bin/env bash
echo "curl $*" >> "$STUB/calls"
cat > "$STUB/curl.stdin"
printf '%s' "${STUB_CURL_CODE:-204}"
[ "${STUB_CURL_CODE:-204}" != 000 ] || exit 6
'''
    mysql = '''#!/usr/bin/env bash
echo "mysql $*" >> "$STUB/calls"
case "$*" in *chaos_discord_queue*)
  printf '5\tchronicle\tfailed\t3\thttp 404 https://discord.com/api/webhooks/111111/SECRETTOKENSECRETTOKEN12\n' ;; esac
'''
    sysctl = '''#!/usr/bin/env bash
echo "systemctl $*" >> "$STUB/calls"
case "$*" in is-enabled*) echo enabled ;; is-active*) echo active ;; esac
exit 0
'''
    with tempfile.TemporaryDirectory() as tmp:
        stub = os.path.join(tmp, 'stub')
        repo = os.path.join(tmp, 'repo')
        site = os.path.join(tmp, 'site')
        sysd = os.path.join(tmp, 'systemd')
        os.makedirs(stub)
        os.makedirs(os.path.join(repo, 'server', 'deploy'))
        os.makedirs(os.path.join(site, 'plugins', 'chaos'))
        os.makedirs(sysd)
        for f in ('chaos-discord.service', 'chaos-discord.timer', 'chaos.logrotate'):
            shutil.copy(os.path.join(HERE, f), os.path.join(repo, 'server', 'deploy', f))
        open(os.path.join(site, 'plugins', 'chaos', 'discord_worker.php'), 'w').close()
        for name, body in (('curl', curl), ('mysql', mysql), ('systemctl', sysctl)):
            p = os.path.join(stub, name)
            with open(p, 'w') as f:
                f.write(body)
            os.chmod(p, 0o755)
        env_file = os.path.join(tmp, 'chaos.env')
        with open(env_file, 'w') as f:
            f.write('CHAOS_DB_USER=chaos\nCHAOS_DB_PASS=dbsecret\n')
        site_env = os.path.join(tmp, 'site.env')
        with open(site_env, 'w') as f:
            f.write('CHAOS_SITE_URL=https://example.org/\n')
        denv = os.path.join(tmp, 'etc', 'discord.env')
        dlog = os.path.join(tmp, 'discord.log')
        with open(dlog, 'w') as f:
            f.write('12:00:00 discord: failed https://discord.com/api/webhooks/111111/SECRETTOKENSECRETTOKEN12\nline two\n')
        rotate = os.path.join(tmp, 'logrotate-chaos')
        env = dict(os.environ, PATH=stub + ':' + os.environ['PATH'], STUB=stub, CHAOS_CTL_NO_SUDO='1',
                   CHAOS_SERVER_DIR=os.path.join(tmp, 'server'), CHAOS_ENV=env_file, CHAOS_REPO=repo, CHAOS_MYSQL='mysql',
                   CHAOS_CTL_CONF=os.path.join(tmp, 'none.conf'), CHAOS_PID_FILE=os.path.join(tmp, 'no.pid'),
                   CHAOS_LOG=os.path.join(tmp, 'no.log'), CHAOS_DISCORD_ENV=denv, CHAOS_DISCORD_LOG=dlog,
                   CHAOS_DISCORD_USER=subprocess.run(['id', '-un'], capture_output=True, text=True).stdout.strip(),
                   CHAOS_DISCORD_GROUP=subprocess.run(['id', '-gn'], capture_output=True, text=True).stdout.strip(),
                   CHAOS_SITE_ENV=site_env, CHAOS_SITE_DIR=site, CHAOS_SYSTEMD_DIR=sysd, CHAOS_LOGROTATE_FILE=rotate)
        for k in ('SUDO_USER', 'CHAOS_UNIT', 'CHAOS_ROOT', 'CHAOS_KIT_DIR', 'CHAOS_DB_SOCKET', 'CHAOS_BACKUP_DIR'):
            env.pop(k, None)
        seen = []  # every stdout / stderr of every run: the token must be in none of them

        def run(*args, stdin=None, extra=None):
            r = subprocess.run(['bash', SCRIPT] + list(args), env=dict(env, **(extra or {})), input=stdin,
                               capture_output=True, text=True)
            seen.append(r.stdout + r.stderr)
            return r

        def calls():
            p = os.path.join(stub, 'calls')
            return open(p).read() if os.path.exists(p) else ''

        def text():
            return open(denv).read()

        # refusals: nothing is written, not even the file
        for bad in ('http://discord.com/api/webhooks/123456/' + token, 'https://evil.com/api/webhooks/123456/' + token,
                    'https://discord.com.evil.com/api/webhooks/123456/' + token,
                    'https://discord.com/api/webhooks/1234/' + token, 'https://discord.com/api/webhooks/123456/short',
                    hook + '?wait=true', hook + '/x', hook + ' extra', 'https://discord.com/api/webhooks/12a456/' + token,
                    'https://user@discord.com/api/webhooks/123456/' + token, 'https://discord.com/api/webhooks/123456/' + token + '\nFOO=1',
                    'javascript:alert(1)', '$(id)'):
            r = run('discord-set', 'records', stdin=bad + '\n')
            check(r.returncode != 0, 'discord-set refuses %r' % bad)
            check(not os.path.exists(denv), 'discord-set: a refused URL writes nothing: %r' % bad)
        for bad in ('records;id', 'Records', 'all', '', '../x', 'records bosses', '$(id)', 'RECORDS'):
            r = run('discord-set', bad, stdin=hook + '\n')
            check(r.returncode != 0 and not os.path.exists(denv), 'discord-set refuses the channel %r' % bad)
        check(run('discord-set', stdin=hook).returncode != 0, 'discord-set needs a channel')
        check(run('discord-set', 'records', 'extra', stdin=hook).returncode != 0, 'discord-set takes one argument')
        check(run('discord-set', 'records', hook).returncode != 0, 'discord-set: a URL on the command line is no input')
        check(run('discord-test', 'records;id').returncode != 0 and run('discord-test', 'a', 'b').returncode != 0,
              'discord-test refuses a bad channel')

        # set: created mode 600, the site url filled, only the one line replaced
        r = run('discord-set', 'records', stdin=hook + '\n')
        check(r.returncode == 0 and 'records saved' in r.stdout and token not in r.stdout + r.stderr, 'discord-set: ' + r.stdout + r.stderr)
        check('5678' in r.stdout and '123456789012345678' not in r.stdout, 'discord-set: only the last 4 digits of the id')
        check(stat.S_IMODE(os.stat(denv).st_mode) == 0o600, 'discord.env is mode 600: %o' % os.stat(denv).st_mode)
        check('CHAOS_DISCORD_WEBHOOK_RECORDS=' + hook + '\n' in text() and 'CHAOS_SITE_URL=https://example.org\n' in text(),
              'discord.env: the line and the site url: ' + repr(text()))
        r = run('discord-set', 'bosses', stdin=hook2 + '\r\n')
        check(r.returncode == 0 and 'WEBHOOK_BOSSES=' + hook2 + '\n' in text(), 'discord-set: a second channel (CRLF input): ' + r.stderr)
        with open(denv, 'a') as f:
            f.write('CHAOS_DISCORD_OFF=level,bazaar_list\n')
        before = text()
        r = run('discord-set', 'records', stdin='  ' + hook2 + '  \n')
        check(r.returncode == 0 and 'WEBHOOK_RECORDS=' + hook2 + '\n' in text() and hook + '\n' not in text(), 'discord-set: replaces the line')
        check(text().count('WEBHOOK_RECORDS') == 1 and 'WEBHOOK_BOSSES=' + hook2 in text() and 'CHAOS_DISCORD_OFF=level,bazaar_list' in text()
              and text().count('CHAOS_SITE_URL') == 1, 'discord-set: the other lines stay: ' + repr(text()))
        check(stat.S_IMODE(os.stat(denv).st_mode) == 0o600, 'discord.env still mode 600 after a rewrite')
        check(not [n for n in os.listdir(os.path.dirname(denv)) if n != 'discord.env'], 'discord-set: no temp file left')
        # a symlinked env file stays a symlink
        real = os.path.join(tmp, 'real.env')
        shutil.move(denv, real)
        os.symlink(real, denv)
        r = run('discord-set', 'players', stdin=hook + '\n')
        check(r.returncode == 0 and os.path.islink(denv) and 'WEBHOOK_PLAYERS=' + hook in open(real).read(), 'discord-set: a symlink is followed')
        os.unlink(denv)
        shutil.move(real, denv)
        # remove
        r = run('discord-set', 'players', stdin='\n')
        check(r.returncode == 0 and 'removed' in r.stdout and 'WEBHOOK_PLAYERS' not in text() and 'WEBHOOK_BOSSES' in text(), 'discord-set: empty input removes: ' + r.stderr)
        r = run('discord-set', 'bosses', stdin='')
        check(r.returncode == 0 and 'WEBHOOK_BOSSES' not in text(), 'discord-set: closed stdin removes')
        run('discord-set', 'bosses', stdin=hook2 + '\n')
        # a hand-edited file without a trailing newline and without the site url: the url gets its own line
        saved = text()
        with open(denv, 'w') as f:
            f.write('CHAOS_DISCORD_WEBHOOK_DEFAULT=' + hook)
        r = run('discord-set', 'status', stdin=hook2 + '\n')
        check(r.returncode == 0 and 'CHAOS_DISCORD_WEBHOOK_DEFAULT=' + hook + '\n' in text() and 'CHAOS_SITE_URL=https://example.org\n' in text(),
              'discord-set: no line glued onto an unterminated last line: ' + repr(text()))
        with open(denv, 'w') as f:
            f.write(saved)
        # a rejected URL leaves the file as it was
        before = text()
        check(run('discord-set', 'bosses', stdin='nonsense\n').returncode != 0 and text() == before, 'discord-set: a bad URL leaves the file')

        # status: yes / no, never the URL, masked log and queue
        r = run('discord-status')
        out = dict(l.split('=', 1) for l in r.stdout.splitlines() if '=' in l and not l.startswith('12:'))
        check(r.returncode == 0 and out.get('channel_records') == 'yes id_end=5432' and out.get('channel_bosses') == 'yes id_end=5432'
              and out.get('channel_status') == 'no' and out.get('channel_default') == 'no', 'discord-status: channels: ' + r.stdout)
        check(out.get('off_kinds') == 'level,bazaar_list' and out.get('site_url') == 'https://example.org', 'discord-status: off kinds, site url')
        check(out.get('timer_installed') == 'no' and out.get('timer_enabled') == 'enabled' and out.get('timer_active') == 'active', 'discord-status: timer')
        check(re.search(r'env_file=600 ', r.stdout) is not None, 'discord-status: env file mode')
        check('@log' in r.stdout and 'line two' in r.stdout and '@queue' in r.stdout and 'chronicle\tfailed\t3' in r.stdout, 'discord-status: log and queue: ' + r.stdout)
        check('SECRETTOKEN' not in r.stdout and '/webhooks/111111/***' in r.stdout, 'discord-status: tokens in log and queue lines are masked')
        check('/api/webhooks/12345' not in r.stdout, 'discord-status: no saved URL')
        check(run('discord-status', 'x').returncode != 0, 'discord-status takes no argument')

        # test: one post per saved channel, the URL only on curl's stdin
        open(os.path.join(stub, 'calls'), 'w').close()
        r = run('discord-test')
        check(r.returncode == 0 and 'records=204 ok' in r.stdout and 'bosses=204 ok' in r.stdout and 'status' not in r.stdout, 'discord-test all: ' + r.stdout + r.stderr)
        check(calls().count('curl ') == 2 and 'teste do webhook records' in calls() and 'teste do webhook bosses' in calls(), 'discord-test: two posts: ' + calls())
        check('discord' not in calls().replace('chaos-discord', '').replace('teste do webhook', '') and token not in calls() and token[::-1] not in calls(),
              'discord-test: the URL is never in curl arguments')
        check('url = "' + hook2 + '"' in open(os.path.join(stub, 'curl.stdin')).read() or 'url = "' + hook + '"' in open(os.path.join(stub, 'curl.stdin')).read(),
              'discord-test: curl gets the URL as a config line on stdin')
        r = run('discord-test', 'records')
        check(r.returncode == 0 and r.stdout.strip() == 'records=204 ok', 'discord-test records: ' + r.stdout)
        r = run('discord-test', 'status')
        check(r.returncode != 0 and 'status=not-configured' in r.stdout, 'discord-test: a channel without a webhook')
        r = run('discord-test', 'bosses', extra={'STUB_CURL_CODE': '404'})
        check(r.returncode == 1 and 'bosses=404 fail' in r.stdout, 'discord-test: HTTP 404 fails: ' + r.stdout)
        r = run('discord-test', 'bosses', extra={'STUB_CURL_CODE': '000'})
        check(r.returncode == 1 and 'bosses=000 fail' in r.stdout, 'discord-test: no connection fails: ' + r.stdout)

        # enable / disable
        r = run('discord-enable')
        check(r.returncode == 0 and 'channels with a webhook: 2' in r.stdout, 'discord-enable: ' + r.stdout + r.stderr)
        check(os.path.isfile(os.path.join(sysd, 'chaos-discord.timer')) and os.path.isfile(os.path.join(sysd, 'chaos-discord.service'))
              and os.path.isfile(rotate), 'discord-enable: units and logrotate installed')
        c = calls()
        check(c.index('systemctl daemon-reload') < c.index('systemctl enable --now chaos-discord.timer'), 'discord-enable: daemon-reload, then enable --now')
        open(os.path.join(stub, 'calls'), 'w').close()
        r = run('discord-enable')
        check(r.returncode == 0 and 'already' in r.stdout and 'daemon-reload' not in calls() and 'enable --now chaos-discord.timer' in calls(), 'discord-enable twice: no reload')
        r = run('discord-disable')
        check(r.returncode == 0 and 'systemctl disable --now chaos-discord.timer' in calls(), 'discord-disable: ' + r.stderr)
        check(run('discord-enable', 'x').returncode != 0 and run('discord-disable', 'x').returncode != 0, 'enable / disable take no argument')
        r = run('discord-enable', extra={'CHAOS_SITE_DIR': os.path.join(tmp, 'nosite')})
        check(r.returncode != 0 and 'site-not-installed' in r.stderr, 'discord-enable: no site, no timer')

        check(not any(token in t or token[::-1] in t for t in seen), 'no output of any discord command holds a webhook token')
        check('webhooks' not in calls(), 'no command line (stubs) saw a webhook URL')


def test_discord_bot():
    """discord-bot install | set | start | stop | restart | status | logs | patchnotes (server/deploy/discord_bot/)"""
    token = 'MTA1NzAxMjM0NTY3ODkwMTIz.GaBcDe.' + 'x' * 30
    key = 'sk-ant-api03-' + 'Z' * 40
    sysctl = '''#!/usr/bin/env bash
echo "systemctl $*" >> "$STUB/calls"
case "$*" in
  is-active*) [ -e "$STUB/active" ] && echo active || { echo inactive; exit 3; } ;;
  is-enabled*) [ -e "$STUB/enabled" ] && echo enabled || echo disabled ;;
  enable*) touch "$STUB/enabled" ;;
  start*|restart*) touch "$STUB/active" ;;
  stop*) rm -f "$STUB/active" ;;
  show*) echo "Tue 2026-10-20 06:00:01 UTC" ;;
esac
exit 0
'''
    # CHAOS_BOT_PYTHON: -c checks pass, -m venv DIR makes DIR/bin/pip and DIR/bin/python3 stubs (no network, no pip)
    py = '''#!/usr/bin/env bash
echo "python $*" >> "$STUB/calls"
# STUB_NOVENV: no venv module until the apt-get stub put the package in
if [ "$1" = "-c" ] && [ -n "${STUB_NOVENV:-}" ] && [ ! -e "$STUB/venv_ok" ]; then exit 1; fi
if [ "$1" = "-m" ] && [ "$2" = "venv" ]; then
  mkdir -p "$3/bin"
  printf '#!/usr/bin/env bash\\necho "pip $*" >> "$STUB/calls"\\n[ -z "${STUB_PIP_FAIL:-}" ]\\n' > "$3/bin/pip"
  printf '#!/usr/bin/env bash\\nexit 0\\n' > "$3/bin/python3"
  chmod +x "$3/bin/pip" "$3/bin/python3"
fi
exit 0
'''
    with tempfile.TemporaryDirectory() as tmp:
        stub = os.path.join(tmp, 'stub')
        repo = os.path.join(tmp, 'repo')
        bsrc = os.path.join(repo, 'server', 'deploy', 'discord_bot')
        sysd = os.path.join(tmp, 'systemd')
        server = os.path.join(tmp, 'server')
        for d in (stub, bsrc, sysd, os.path.join(server, 'data')):
            os.makedirs(d)
        for f in ('bot.py', 'bot_core.py', 'claude_client.py', 'requirements.txt', '.env.example'):
            shutil.copy(os.path.join(HERE, 'discord_bot', f), bsrc)
        for f in ('chaos-discordbot.service', 'chaos.logrotate'):
            shutil.copy(os.path.join(HERE, f), os.path.join(repo, 'server', 'deploy', f))
        aptget = '#!/usr/bin/env bash\necho "apt-get $*" >> "$STUB/calls"\n[ -n "${STUB_APT_FAIL:-}" ] && exit 100\ntouch "$STUB/venv_ok"\n'
        for name, body in (('systemctl', sysctl), ('fakepython', py), ('apt-get', aptget)):
            p = os.path.join(stub, name)
            with open(p, 'w') as f:
                f.write(body)
            os.chmod(p, 0o755)
        me = subprocess.run(['id', '-un'], capture_output=True, text=True).stdout.strip()
        envf = os.path.join(tmp, 'etc', 'discord-bot.env')
        botdir, data, blog = os.path.join(tmp, 'opt', 'bot'), os.path.join(tmp, 'var', 'bot'), os.path.join(tmp, 'bot.log')
        env = dict(os.environ, PATH=stub + ':' + os.environ['PATH'], STUB=stub, CHAOS_CTL_NO_SUDO='1',
                   CHAOS_SERVER_DIR=server, CHAOS_REPO=repo, CHAOS_CTL_CONF=os.path.join(tmp, 'none.conf'),
                   CHAOS_PID_FILE=os.path.join(tmp, 'no.pid'), CHAOS_LOG=os.path.join(tmp, 'no.log'),
                   CHAOS_BOT_USER=me, CHAOS_BOT_ENV=envf, CHAOS_BOT_DIR=botdir, CHAOS_BOT_DATA=data, CHAOS_BOT_LOG=blog,
                   CHAOS_BOT_PYTHON=os.path.join(stub, 'fakepython'), CHAOS_BOT_WAIT='0', CHAOS_SYSTEMD_DIR=sysd,
                   CHAOS_LOGROTATE_FILE=os.path.join(tmp, 'logrotate-chaos'))
        for k in ('SUDO_USER', 'CHAOS_UNIT', 'CHAOS_ROOT', 'CHAOS_KIT_DIR'):
            env.pop(k, None)
        seen = []

        def run(*args, stdin=None, extra=None):
            r = subprocess.run(['bash', SCRIPT, 'discord-bot'] + list(args), env=dict(env, **(extra or {})), input=stdin,
                               capture_output=True, text=True)
            seen.append(r.stdout + r.stderr)
            return r

        def calls():
            p = os.path.join(stub, 'calls')
            return open(p).read() if os.path.exists(p) else ''

        def kvs(r):
            return dict(l.split('=', 1) for l in r.stdout.splitlines() if '=' in l and not l.startswith(('(', '@')))

        # before the install: status works, start refuses, set refuses
        k = kvs(run('status'))
        check(k.get('installed') == 'no' and k.get('unit_installed') == 'no' and k.get('env_file') == 'missing'
              and k.get('set_DISCORD_TOKEN') == 'no', 'status before install: %s' % k)
        r = run('start')
        check(r.returncode != 0 and 'not-installed' in r.stderr, 'start before install is refused: ' + r.stderr)
        r = run('set', 'DISCORD_TOKEN', stdin=token + '\n')
        check(r.returncode != 0 and 'not-installed' in r.stderr and not os.path.exists(envf), 'set before install is refused')

        # no python3-venv: the install puts it in with apt-get; when apt-get fails, it stops with the hint
        r = run('install', extra={'STUB_NOVENV': '1', 'STUB_APT_FAIL': '1'})
        check(r.returncode != 0 and 'python3-venv-missing' in r.stderr and 'apt-get install -y -q python3-venv' in calls(),
              'no venv and apt-get fails: refused with the hint: ' + r.stderr)
        # install
        r = run('install', extra={'STUB_NOVENV': '1'})
        check(r.returncode == 0 and 'discord-bot install: ok' in r.stdout and 'missing settings: DISCORD_TOKEN' in r.stdout,
              'install: ' + r.stdout + r.stderr)
        check('installing python3-venv' in r.stdout, 'the install put python3-venv in first')
        for f in ('bot.py', 'bot_core.py', 'claude_client.py'):
            check(os.path.exists(os.path.join(botdir, 'app', f)), 'install copies ' + f)
        check(stat.S_IMODE(os.stat(envf).st_mode) == 0o600, 'the settings file is mode 600')
        check('DISCORD_TOKEN=' in open(envf).read(), 'the settings file starts from .env.example')
        unit = open(os.path.join(sysd, 'chaos-discordbot.service')).read()
        check('User=%s' % me in unit and 'EnvironmentFile=' + envf in unit and botdir + '/venv/bin/python3 -I ' + botdir + '/app/bot.py' in unit
              and 'ReadWritePaths=' + data in unit and 'append:' + blog in unit and 'User=chaosbot' not in unit and 'Group=chaosbot' not in unit,
              'the unit gets the configured user and paths: ' + unit)
        c = calls()
        check('python -m venv ' + botdir + '/venv' in c and 'pip install' in c and '-r ' + bsrc + '/requirements.txt' in c,
              'install makes the venv and installs the pinned requirements: ' + c)
        check('systemctl enable chaos-discordbot' in c and 'systemctl daemon-reload' in c and 'systemctl start' not in c,
              'install enables, does not start')
        check(os.path.exists(os.path.join(tmp, 'logrotate-chaos')), 'install adds the logrotate file')
        check(stat.S_IMODE(os.stat(data).st_mode) == 0o750, 'the data dir is mode 750')

        # idempotent: nothing is redone, a changed file is copied
        open(os.path.join(stub, 'calls'), 'w').close()
        r = run('install')
        c = calls()
        check(r.returncode == 0 and 'requirements: already installed' in r.stdout and 'unit: already installed' in r.stdout
              and 'pip install' not in c and '-m venv' not in c and 'restart' not in c, 'install twice changes nothing: ' + r.stdout + c)
        with open(os.path.join(bsrc, 'bot.py'), 'a') as f:
            f.write('# changed\n')
        touch_active = open(os.path.join(stub, 'active'), 'w')
        touch_active.close()
        open(os.path.join(stub, 'calls'), 'w').close()
        r = run('install')
        check('systemctl restart chaos-discordbot' in calls() and 'pip install' not in calls()
              and open(os.path.join(botdir, 'app', 'bot.py')).read().endswith('# changed\n'),
              'new code is copied and the running bot restarted: ' + r.stdout)
        os.remove(os.path.join(stub, 'active'))
        r = run('install', extra={'STUB_PIP_FAIL': '1'})
        check(r.returncode == 0, 'pip is not run again for the same requirements')
        shutil.rmtree(os.path.join(botdir, 'venv'))
        r = run('install', extra={'STUB_PIP_FAIL': '1'})
        check(r.returncode != 0 and 'pip install failed' in r.stderr, 'a failed pip install fails the command')
        r = run('install')
        check(r.returncode == 0 and 'requirements: installed' in r.stdout, 'a missing venv is made again')
        r = run('install', 'x')
        check(r.returncode != 0, 'install takes no argument')

        # set: validated per name, mode 600, only that line replaced, never printed
        r = run('set', 'DISCORD_TOKEN', stdin=token + '\n')
        check(r.returncode == 0 and 'saved' in r.stdout and token not in r.stdout + r.stderr, 'set token: ' + r.stdout + r.stderr)
        r = run('set', 'ANTHROPIC_API_KEY', stdin=key + '\n')
        check(r.returncode == 0 and key not in r.stdout + r.stderr, 'set key')
        body = open(envf).read()
        check(body.count('DISCORD_TOKEN=') == 1 and 'DISCORD_TOKEN=' + token in body and 'ANTHROPIC_API_KEY=' + key in body
              and stat.S_IMODE(os.stat(envf).st_mode) == 0o600, 'values in the file, mode 600, one line each')
        for name, bad in (('DISCORD_TOKEN', 'short'), ('DISCORD_TOKEN', token + '\nFOO=1'), ('ANTHROPIC_API_KEY', 'sk-xyz'),
                          ('DISCORD_OWNER_ID', 'abc'), ('DISCORD_OWNER_ID', '12'), ('DISCORD_BOT_MODEL', 'a b'),
                          ('DISCORD_OWNER_ID', '123456; id'), ('DISCORD_OWNER_ID', '$(id)')):
            before = open(envf).read()
            r = run('set', name, stdin=bad + '\n')
            check(r.returncode != 0 and open(envf).read() == before, 'set refuses %s=%r' % (name, bad))
        for bad in ('PATH', 'discord_token', 'DISCORD_TOKEN;id', '', 'A B'):
            r = run('set', bad, stdin='123456\n')
            check(r.returncode != 0, 'set refuses the name %r' % bad)
        check(run('set', 'DISCORD_OWNER_ID', '123456').returncode != 0, 'a value on the command line is no input')
        for name in ('DISCORD_OWNER_ID', 'DISCORD_BUGS_CHANNEL_ID'):
            check(run('set', name, stdin='111111111111111111\n').returncode == 0, 'set ' + name)

        # start needs all five settings
        r = run('start')
        check(r.returncode != 0 and 'config-missing: DISCORD_PATCH_CHANNEL_ID' in r.stderr and 'DISCORD_TOKEN' not in r.stderr
              and 'systemctl start' not in calls(), 'start names only the missing settings: ' + r.stderr)
        check(run('set', 'DISCORD_PATCH_CHANNEL_ID', stdin='222222222222222222\n').returncode == 0, 'set the last one')
        r = run('start')
        check(r.returncode == 0 and 'is active' in r.stdout and 'systemctl start chaos-discordbot' in calls(), 'start: ' + r.stdout + r.stderr)
        r = run('restart')
        check(r.returncode == 0 and 'systemctl restart chaos-discordbot' in calls(), 'restart')
        k = kvs(run('status'))
        check(k.get('installed') == 'yes' and k.get('unit_active') == 'active' and k.get('unit_enabled') == 'enabled'
              and k.get('set_DISCORD_TOKEN') == 'yes' and k.get('set_DISCORD_GUILD_ID') == 'no'
              and k.get('env_file', '').startswith('600') and k.get('model') == 'claude-sonnet-5-5', 'status after install: %s' % k)
        check(run('set', 'DISCORD_BOT_MODEL', stdin='claude-opus-5-5\n').returncode == 0
              and kvs(run('status')).get('model') == 'claude-opus-5-5', 'the model setting shows in status')
        check(run('set', 'DISCORD_BOT_MODEL', stdin='\n').returncode == 0 and '\nDISCORD_BOT_MODEL=' not in open(envf).read(),
              'an empty value removes the line')
        r = run('stop')
        check(r.returncode == 0 and not os.path.exists(os.path.join(stub, 'active')), 'stop')
        r = run('start', extra={'STUB_NOPE': '1'})
        check(r.returncode == 0, 'start again')

        # logs: tokens and keys masked
        with open(blog, 'w') as f:
            f.write('line one\nlogin with %s\nkey %s\nlast\n' % (token, key))
        r = run('logs', '3')
        check(r.returncode == 0 and token not in r.stdout and key not in r.stdout and '***' in r.stdout and 'last' in r.stdout
              and 'line one' not in r.stdout, 'logs mask tokens and keys: ' + r.stdout)
        check('sk-ant-***' in run('logs').stdout, 'key masked as sk-ant-***')
        check(run('logs', 'x').returncode != 0 and run('logs', '1', '2').returncode != 0, 'logs refuses bad arguments')
        r = run('status')
        check(token not in r.stdout and key not in r.stdout and 'last' in r.stdout, 'status log tail is masked')
        check(run('nope').returncode != 0 and run('status', 'x').returncode != 0, 'unknown subcommand and arguments refused')

        # patchnotes: new files copied into SERVER/data/patchnotes, existing ones kept
        os.makedirs(os.path.join(data, 'patchnotes'))
        for n, t in (('2026-10-29.md', 'en'), ('2026-10-29.pt-br.md', 'pt')):
            open(os.path.join(data, 'patchnotes', n), 'w').write(t)
        r = run('patchnotes')
        check(r.returncode == 0 and '2 files copied' in r.stdout and open(os.path.join(server, 'data', 'patchnotes', '2026-10-29.md')).read() == 'en',
              'patchnotes copies new notes: ' + r.stdout + r.stderr)
        open(os.path.join(server, 'data', 'patchnotes', '2026-10-29.md'), 'w').write('edited')
        r = run('patchnotes')
        check('0 files copied' in r.stdout and open(os.path.join(server, 'data', 'patchnotes', '2026-10-29.md')).read() == 'edited',
              'patchnotes never overwrites')

        joined = '\n'.join(seen)
        check(token not in joined and key not in joined, 'no output of any discord-bot command holds a token or a key')
        check(token not in calls() and key not in calls(), 'no command line (stubs) saw a token or a key')


SU_SYSTEMCTL = """#!/usr/bin/env bash
echo "systemctl $*" >> "$STUB/calls"
case "$*" in
  *LoadState*) echo loaded ;;
  *"-p User"*) cat "$STUB/unit_user" 2>/dev/null || echo root ;;
  *"-p Group"*) echo root ;;
  *"-p MainPID"*) echo 0 ;;
  daemon-reload) [ -n "${STUB_NORELOAD:-}" ] || sed -n 's/^User=//p' "$STUB_UNITFILE" | head -n 1 > "$STUB/unit_user" ;;
  is-active*) exit 0 ;;
  show*) echo "Tue 2026-10-20 06:00:01 UTC" ;;
esac
exit 0
"""
SU_STUBS = {
    'systemctl': SU_SYSTEMCTL,
    'ps': '#!/usr/bin/env bash\n# STUB_PROC_AFTER: the user of the process once the unit was started (a restart happened)\n'
          'if [ -n "${STUB_PROC_AFTER:-}" ] && grep -q "^systemctl start" "$STUB/calls" 2>/dev/null; then echo "  $STUB_PROC_AFTER"; '
          'else echo "  ${STUB_PROC_USER:-root}"; fi\n',
    'getent': '#!/usr/bin/env bash\necho "getent $*" >> "$STUB/calls"\n'
              'case "$1" in passwd) [ -e "$STUB/have_user" ] ;; group) [ -e "$STUB/have_group" ] ;; *) false ;; esac\n',
    'useradd': '#!/usr/bin/env bash\necho "useradd $*" >> "$STUB/calls"\ntouch "$STUB/have_user"\n',
    'chown': '#!/usr/bin/env bash\necho "chown $*" >> "$STUB/calls"\n[ -z "${STUB_CHOWN_FAIL:-}" ]\n',
    'runuser': '#!/usr/bin/env bash\necho "runuser $1 $2" >> "$STUB/calls"\nshift 3\nexec "$@"\n',
    'sleep': '#!/usr/bin/env bash\nexit 0\n',
    'systemd-analyze': '#!/usr/bin/env bash\necho "systemd-analyze $*" >> "$STUB/calls"\n'
                       '[ -z "${STUB_VERIFY_RC:-}" ] || { echo "unit.service: Unknown key name Bogus"; exit 1; }\n',
    'dbclient': '#!/usr/bin/env bash\necho "dbclient $*" >> "$STUB/calls"\n'
                '[ -z "${STUB_DBDOWN:-}" ] || exit 1\n'
                'case "$*" in *"SELECT COUNT(*) FROM mysql.user"*) echo "${STUB_DBADMIN:-0}" ;; '
                '*"SELECT 1"*) echo 1 ;; esac\n',
}


def test_server_user():
    """server-user status | fix | rollback | log (the engine ran as root: the unit gets User=chaos)"""
    unit_src = os.path.join(HERE, 'chaos-trial-server.service')
    repo_unit_src = os.path.join(HERE, 'chaos-server.service')
    with tempfile.TemporaryDirectory() as tmp:
        stub = os.path.join(tmp, 'stub')
        os.makedirs(stub)
        for name, body in SU_STUBS.items():
            p = os.path.join(stub, name)
            with open(p, 'w') as f:
                f.write(body)
            os.chmod(p, 0o755)
        kit = os.path.join(tmp, 'kit')
        repo = os.path.join(tmp, 'repo')
        sysd = os.path.join(tmp, 'sysd')
        state = os.path.join(tmp, 'state')
        sulog = os.path.join(tmp, 'server-user.log')
        for d in ('server', 'database', 'run', 'logs', 'crashes', 'mariadb/bin'):
            os.makedirs(os.path.join(kit, d))
        os.makedirs(sysd)
        os.makedirs(os.path.join(repo, 'server', 'deploy'))
        os.makedirs(os.path.join(repo, 'server', 'tools'))
        for d in (kit, repo, os.path.join(repo, 'server'), os.path.join(repo, 'server', 'deploy'), os.path.join(repo, 'server', 'tools')):
            os.chmod(d, 0o755)
        shutil.copy(unit_src, os.path.join(repo, 'server', 'deploy'))
        shutil.copy(repo_unit_src, os.path.join(repo, 'server', 'deploy'))
        with open(os.path.join(repo, 'server', 'deploy', 'chaos_kit_update.sh'), 'w') as f:
            f.write('#!/usr/bin/env bash\nexit 0\n')
        os.chmod(os.path.join(repo, 'server', 'deploy', 'chaos_kit_update.sh'), 0o755)
        with open(os.path.join(kit, 'start-server.sh'), 'w') as f:
            f.write('#!/bin/sh\n')
        os.chmod(os.path.join(kit, 'start-server.sh'), 0o755)
        with open(os.path.join(kit, 'chaos.env'), 'w') as f:
            f.write('CHAOS_DB_USER=chaos\nCHAOS_DB_PASS=secret\nCHAOS_RSA_KEY_FILE="%s, key.pem,%s"\n'
                    % (os.path.join(kit, 'rsa', 'login-1.pem'), os.path.join(kit, 'etc', 'login-2.pem')))
        # the login keys: one in a folder of keys only (rsa_key.py gen), one beside another file, key.pem in the server folder
        os.makedirs(os.path.join(kit, 'rsa'))
        os.makedirs(os.path.join(kit, 'etc'))
        for k in ('rsa/login-1.pem', 'etc/login-2.pem', 'etc/other.txt', 'server/key.pem'):
            open(os.path.join(kit, k), 'w').close()
        os.chmod(os.path.join(kit, 'chaos.env'), 0o600)
        ufile = os.path.join(sysd, 'chaos-server.service')

        # the installed unit as the README's old step left it: the kit's unit with User=root (the owner of /opt/chaos-trial)
        def install_old():
            with open(unit_src) as f:
                body = f.read().replace('/opt/chaos-trial', kit).replace('User=chaos', 'User=root').replace('Group=chaos', 'Group=root')
            with open(ufile, 'w') as f:
                f.write(body)
            with open(os.path.join(stub, 'unit_user'), 'w') as f:
                f.write('root\n')
            return body

        old_body = install_old()
        env = dict(os.environ, PATH=stub + ':' + os.environ['PATH'], STUB=stub, CHAOS_CTL_NO_SUDO='1',
                   CHAOS_CTL_CONF=os.path.join(tmp, 'none.conf'), CHAOS_KIT_DIR=kit, CHAOS_ROOT=kit,
                   CHAOS_SERVER_DIR=os.path.join(kit, 'server'), CHAOS_REPO=repo, CHAOS_ENV=os.path.join(kit, 'chaos.env'),
                   CHAOS_LOG=os.path.join(kit, 'logs', 'server.log'), CHAOS_SYSTEMD_DIR=sysd, CHAOS_SERVER_USER_STATE=state,
                   CHAOS_SERVER_USER_LOG=sulog, CHAOS_MYSQL='dbclient', CHAOS_PID_FILE=os.path.join(kit, 'run', 'server.pid'),
                   CHAOS_UPDATE_LOG=os.path.join(tmp, 'u.log'), CHAOS_KIT_STATE=os.path.join(tmp, 'kstate'),
                   CHAOS_SERVER_USER='chaostest', STUB_UNITFILE=ufile)
        for k in ('SUDO_USER', 'CHAOS_UNIT', 'CHAOS_DB_SOCKET', 'CHAOS_BACKUP_DIR'):
            env.pop(k, None)

        def run(*args, extra=None, e=None):
            return subprocess.run(['bash', SCRIPT] + list(args), env=dict(e or env, **(extra or {})), capture_output=True, text=True)

        def calls():
            p = os.path.join(stub, 'calls')
            return open(p).read() if os.path.exists(p) else ''

        def reset_calls():
            open(os.path.join(stub, 'calls'), 'w').close()

        def kv(r):
            return dict(l.split('=', 1) for l in r.stdout.splitlines() if '=' in l)

        def unit_text():
            return open(ufile).read()

        # status before: a root unit, no chaos user
        r = run('server-user')
        st = kv(r)
        check(r.returncode == 0 and st.get('unit_user') == 'root' and st.get('layout') == 'kit' and st.get('runs_as_root') == 'yes'
              and st.get('user_exists') == 'no' and st.get('needs_fix') == 'yes' and st.get('target_user') == 'chaostest'
              and st.get('repo_root_owned') == 'yes' and st.get('db_admin') == 'no' and st.get('unit_backup') == 'no'
              and st.get('restart_needed') == 'no', 'server-user status before: ' + r.stdout + r.stderr)
        check(not any(c in calls() for c in ('useradd', 'chown ', 'daemon-reload')), 'server-user status changes nothing')
        check(run('server-user', 'status', 'x').returncode != 0 and run('server-user', 'nope').returncode != 0, 'server-user: bad arguments refused')
        check(run('server-user', 'fix', '--restart', '5').returncode != 0 and run('server-user', 'fix', '--restart', '9999').returncode != 0
              and run('server-user', 'fix', '--restart', 'x').returncode != 0 and run('server-user', 'fix', 'now').returncode != 0
              and 'useradd' not in calls(), 'server-user fix: the restart delay is 30 to 900 seconds')

        # refusals change nothing
        def untouched(label):
            check('useradd' not in calls() and 'chown ' not in calls() and 'daemon-reload' not in calls() and 'CREATE USER' not in calls()
                  and unit_text() == old_body and not os.path.exists(state + '/pending-backup'), label + ': nothing changed: ' + calls())

        reset_calls()
        os.chmod(os.path.join(repo, 'server'), 0o775)
        r = run('server-user', 'fix')
        check(r.returncode != 0 and 'repo-not-root-owned' in r.stderr, 'fix: a group-writable checkout is refused: ' + r.stderr)
        untouched('writable checkout')
        os.chmod(os.path.join(repo, 'server'), 0o755)
        os.chmod(kit, 0o750)
        r = run('server-user', 'fix')
        check(r.returncode != 0 and 'kit-not-traversable' in r.stderr, 'fix: a kit folder the user cannot enter is refused: ' + r.stderr)
        untouched('kit mode')
        os.chmod(kit, 0o755)
        os.rename(os.path.join(kit, 'run'), os.path.join(kit, 'run.real'))
        os.symlink(os.path.join(kit, 'run.real'), os.path.join(kit, 'run'))
        r = run('server-user', 'fix')
        check(r.returncode != 0 and 'symbolic link' in r.stderr, 'fix: a symbolic link in the way is refused: ' + r.stderr)
        untouched('symlink')
        os.unlink(os.path.join(kit, 'run'))
        os.rename(os.path.join(kit, 'run.real'), os.path.join(kit, 'run'))
        r = run('server-user', 'fix', extra={'CHAOS_REPO': kit})
        check(r.returncode != 0 and ('contain each other' in r.stderr or 'no-unit-template' in r.stderr), 'fix: the checkout inside the kit folders is refused: ' + r.stderr)
        untouched('overlap')
        r = run('server-user', 'fix', extra={'STUB_VERIFY_RC': '1'})
        check(r.returncode != 0 and 'unit-verify-failed' in r.stderr and 'Unknown key name' in r.stderr, 'fix: systemd-analyze verify failure stops it: ' + r.stderr)
        untouched('verify')
        r = run('server-user', 'fix', extra={'STUB_DBDOWN': '1'})
        check(r.returncode != 0 and 'database-down' in r.stderr, 'fix: a database that does not answer stops it: ' + r.stderr)
        check('chown ' not in calls() and unit_text() == old_body, 'fix: database down: no chown, unit untouched')
        # a repo unit installed while the settings say kit would stop the server
        with open(os.path.join(repo, 'server', 'deploy', 'chaos-server.service')) as f:
            repo_body = f.read()
        with open(ufile, 'w') as f:
            f.write(repo_body)
        reset_calls()
        r = run('server-user', 'fix')
        check(r.returncode != 0 and 'layout-mismatch' in r.stderr and unit_text() == repo_body and 'useradd' not in calls(),
              'fix: the layout of the installed unit must match the settings: ' + r.stderr)
        install_old()
        r = run('server-user', 'fix', extra={'CHAOS_SERVER_USER': 'root'})
        check(r.returncode != 0 and 'bad CHAOS_SERVER_USER' in r.stderr, 'the target user is never root')
        r = run('server-user', 'fix', extra={'CHAOS_SYSTEMD_DIR': os.path.join(tmp, 'no-such')})
        check(r.returncode != 0 and 'unit-file-not-found' in r.stderr, 'fix: no unit file, no change')

        # a drop-in that keeps User=root: the new unit is not applied, the old one is put back
        reset_calls()
        r = run('server-user', 'fix', extra={'STUB_NORELOAD': '1'})
        check(r.returncode != 0 and 'unit-user-not-applied' in r.stderr and unit_text() == old_body, 'fix: User= not applied: the old unit is back: ' + r.stderr + unit_text()[:200])
        check(calls().count('daemon-reload') == 2, 'fix: reloaded after the install and after the way back')
        for f in os.listdir(state):
            if f.startswith('chaos-server.service.before-'):
                os.unlink(os.path.join(state, f))
        os.unlink(os.path.join(stub, 'have_user'))

        # the engine runs as root (a process called tfs)
        tfs = os.path.join(tmp, 'tfs')
        shutil.copy('/bin/sleep', tfs)
        proc = subprocess.Popen([tfs, '600'])
        try:
            with open(os.path.join(kit, 'run', 'server.pid'), 'w') as f:
                f.write('%d\n' % proc.pid)
            r = run('server-user')
            st = kv(r)
            check(st.get('login_keys') == '3', 'status: the login keys named in chaos.env: %r' % st)
            check(st.get('engine_pid') == str(proc.pid) and st.get('engine_user') == 'root' and st.get('runs_as_root') == 'yes'
                  and st.get('restart_needed') == 'yes', 'status: the live engine process runs as root: ' + r.stdout)
            check(kv(run('status')).get('engine_user') == 'root', 'status: engine_user line')

            # the fix
            reset_calls()
            r = run('server-user', 'fix')
            c = calls()
            check(r.returncode == 0 and 'RESULT ok: prepared' in r.stdout, 'fix: ok: ' + r.stdout + r.stderr)
            check('systemd-analyze verify' in c and c.index('systemd-analyze verify') < c.index('useradd'), 'fix: the unit is verified before anything changes')
            check('useradd --system --user-group --home-dir /var/lib/chaos --no-create-home --shell /usr/sbin/nologin chaostest' in c,
                  'fix: the system user is created without a login: ' + c)
            for d in ('server', 'database', 'run', 'logs', 'crashes'):
                check('chown -R -h chaostest:chaostest -- %s' % os.path.join(kit, d) in c, 'fix: chown of %s' % d)
            check('chown -h chaostest -- %s' % os.path.join(kit, 'chaos.env') in c, 'fix: chaos.env owned by the service user')
            for k in ('rsa/login-1.pem', 'etc/login-2.pem', 'server/key.pem', 'rsa'):
                check('chown -h chaostest:chaostest -- %s\n' % os.path.join(kit, k) in c, 'fix: the login key %s owned by the service user: %s' % (k, c))
            check('chown -h chaostest:chaostest -- %s\n' % os.path.join(kit, 'etc') not in c and 'other.txt' not in c,
                  'fix: a folder with other files in it is not given away')
            check('login keys owned by chaostest' in r.stdout, 'fix: says which keys: ' + r.stdout)
            check(repo not in ''.join(l for l in c.splitlines() if l.startswith('chown')) and 'chown -R -h chaostest:chaostest -- %s\n' % kit not in c,
                  'fix: never the checkout or the whole kit folder')
            check(('runuser -u' in c or os.stat(os.path.join(kit, 'database')).st_uid == 0) and "CREATE USER IF NOT EXISTS 'chaostest'@'localhost' IDENTIFIED VIA unix_socket" in c
                  and "GRANT ALL PRIVILEGES ON *.* TO 'chaostest'@'localhost'" in c, "fix: the kit's database gets the socket admin: " + c)
            new_body = unit_text()
            check('User=chaostest' in new_body and 'Group=chaostest' in new_body and 'User=root' not in new_body
                  and 'ExecStart=%s/start-server.sh' % kit in new_body and '/opt/chaos-trial' not in new_body,
                  'fix: the kit unit with the user and the kit folder: ' + new_body[-900:])
            baks = [f for f in os.listdir(state) if f.startswith('chaos-server.service.before-')]
            check(len(baks) == 1 and open(os.path.join(state, baks[0])).read() == old_body, 'fix: the old unit is kept: %r' % baks)
            check('systemctl daemon-reload' in c, 'fix: daemon-reload')
            check('restart: needed' in r.stdout and 'restart 300' in r.stdout and 'systemctl restart' not in c and 'systemctl stop' not in c,
                  'fix: without --restart the server is not restarted: ' + r.stdout)
            check(os.stat(state).st_mode & 0o777 == 0o700, 'fix: the state folder is private')

            # again: idempotent (the database admin is there now, the unit already has the user)
            reset_calls()
            r = run('server-user', 'fix', extra={'STUB_DBADMIN': '1'})
            c = calls()
            check(r.returncode == 0 and 'left as it is' in r.stdout and 'useradd' not in c and 'CREATE USER' not in c
                  and 'daemon-reload' not in c and unit_text() == new_body, 'fix twice: no new user, no new unit: ' + r.stdout + c)
            check(len([f for f in os.listdir(state) if f.startswith('chaos-server.service.before-')]) == 1, 'fix twice: no second backup')
            check(os.path.exists(os.path.join(stub, 'have_user')), 'fix twice: the user stays')
            st = kv(run('server-user', extra={'STUB_DBADMIN': '1'}))
            check(st.get('unit_user') == 'chaostest' and st.get('unit_current') == 'yes' and st.get('user_exists') == 'yes'
                  and st.get('db_admin') == 'yes' and st.get('unit_backup') == 'yes' and st.get('restart_needed') == 'yes'
                  and st.get('runs_as_root') == 'yes', 'status after: unit ready, engine still root until the restart: %r' % st)

            # update-apply tells that the unit still runs as root; not when it does not
            install_old()
            r = run('update-apply')
            check(r.returncode == 0 and 'warning' in r.stderr and 'server-user fix' in r.stderr, 'update-apply: warns when the unit runs as root: ' + r.stderr)
            with open(os.path.join(stub, 'unit_user'), 'w') as f:
                f.write('chaostest\n')
            r = run('update-apply')
            check(r.returncode == 0 and 'warning' not in r.stderr, 'update-apply: silent when the unit has a user: ' + r.stderr)

            # rollback (no restart)
            reset_calls()
            with open(ufile, 'w') as f:
                f.write(new_body)
            r = run('server-user', 'rollback')
            check(r.returncode == 0 and unit_text() == old_body and 'daemon-reload' in calls() and 'systemctl restart' not in calls(),
                  'rollback: the old unit is back, no restart: ' + r.stdout + r.stderr)

            # the restart part: success when the engine comes back as the service user
            with open(ufile, 'w') as f:
                f.write(new_body)
            with open(os.path.join(stub, 'unit_user'), 'w') as f:
                f.write('chaostest\n')
            with open(os.path.join(state, 'pending-backup'), 'w') as f:
                f.write(os.path.join(state, baks[0]) + '\n')
            reset_calls()
            r = run('server-user-impl', '30', extra={'STUB_PROC_USER': 'chaostest'})
            c = calls()
            check(r.returncode == 0 and 'RESULT ok' in r.stdout, 'impl: ok: ' + r.stdout + r.stderr)
            check(c.index('systemctl stop chaos-server') < c.index('chown -R -h chaostest:chaostest') < c.index('systemctl start chaos-server'),
                  'impl: stop, chown again, start: ' + c)
            check('The server restarts in 30 seconds' in open(os.path.join(kit, 'server', 'remote.cmd')).read(), 'impl: players are warned')
            check(unit_text() == new_body, 'impl: the new unit stays')
            # failure: the engine comes back as root: the old unit is put back and started
            reset_calls()
            r = run('server-user-impl', '30', extra={'STUB_PROC_USER': 'root'})
            c = calls()
            check(r.returncode == 1 and 'RESULT rolled-back' in r.stdout and unit_text() == old_body, 'impl: wrong user: rolled back: ' + r.stdout + r.stderr)
            check(c.rindex('daemon-reload') < c.rindex('systemctl restart chaos-server'), 'impl: reload, then start the old unit')
            # chown failure after the stop
            with open(ufile, 'w') as f:
                f.write(new_body)
            reset_calls()
            r = run('server-user-impl', '30', extra={'STUB_PROC_USER': 'chaostest', 'STUB_CHOWN_FAIL': '1'})
            check(r.returncode == 1 and 'RESULT rolled-back: chown failed' in r.stdout and unit_text() == old_body
                  and 'systemctl start chaos-server' in calls(), 'impl: chown failure: old unit back and started: ' + r.stdout)
            check(run('server-user-impl', '5').returncode != 0 and run('server-user-impl').returncode != 0, 'impl: the delay is checked')

            # fix --restart: detached, the log gets the result
            install_old()
            reset_calls()
            with open(os.path.join(stub, 'have_user'), 'w'):
                pass
            r = run('server-user', 'fix', '--restart', '60', extra={'STUB_PROC_USER': 'root', 'STUB_PROC_AFTER': 'chaostest', 'STUB_DBADMIN': '1'})
            check(r.returncode == 0 and 'restart: in 60 seconds' in r.stdout, 'fix --restart: scheduled: ' + r.stdout + r.stderr)
            for _ in range(100):
                if os.path.exists(sulog) and 'RESULT' in open(sulog).read():
                    break
                time.sleep(0.1)
            check(os.path.exists(sulog) and 'RESULT ok' in open(sulog).read(), 'fix --restart: the detached restart finished ok: ' + (open(sulog).read() if os.path.exists(sulog) else 'no log'))
            r = run('server-user', 'log', '5')
            check(r.returncode == 0 and 'RESULT ok' in r.stdout, 'server-user log: ' + r.stdout)
        finally:
            proc.kill()
            proc.wait()

        # the repo layout (/opt/chaos): only the server folder, no database step, the repo unit
        rserver = os.path.join(tmp, 'rserver')
        os.makedirs(rserver)
        renv = dict(env, CHAOS_SERVER_DIR=rserver, CHAOS_ROOT='/opt/chaos', CHAOS_PID_FILE=os.path.join(tmp, 'none.pid'),
                    CHAOS_ENV=os.path.join(tmp, 'none.env'))
        renv.pop('CHAOS_KIT_DIR')
        with open(ufile, 'w') as f:
            f.write(repo_body.replace('User=chaos', 'User=root'))
        with open(os.path.join(stub, 'unit_user'), 'w') as f:
            f.write('root\n')
        reset_calls()
        r = run('server-user', 'fix', e=renv)
        c = calls()
        check(r.returncode == 0 and 'User=chaostest' in unit_text() and 'ExecStart=/opt/chaos/server/tfs' in unit_text(), 'repo layout: the repo unit: ' + r.stdout + r.stderr)
        check('chown -R -h chaostest:chaostest -- %s' % rserver in c and c.count('chown ') == 1 and 'dbclient' not in c and 'runuser' not in c,
              'repo layout: only the server folder, no database step: ' + c)
        check(kv(run('server-user', e=renv)).get('layout') == 'repo', 'repo layout: status')
        r = run('server-user', 'fix', e=dict(renv, CHAOS_ROOT='/srv/other'))
        check(r.returncode != 0 and 'layout-unsupported' in r.stderr, 'repo layout: another root folder is refused: ' + r.stderr)



if __name__ == '__main__':
    sys.exit(main())
