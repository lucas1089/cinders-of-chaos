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

Donations (pay-status / -set / -test / -enable / -disable, O413): a value only on stdin, one line, checked per NAME
(providers from a fixed list, never mock; https site URL; tokens by charset and length), never echoed; payments.env made
from the example (mode 640), the line replaced in place, the payer salt made once; status shows yes/no and the webhook
URLs, masks e-mails and tokens in log lines; test sends the secrets to curl on its stdin, calls the env's PayPal host
and the webhook pages (401 = ok); enable installs the unit with the real paths.

Engine rebuild (engine-build status | start | log, engine-build-token-set, O436): a fake curl plays the GitHub API. The token
only on stdin, one line, a real shape, checked at GitHub before it is kept (401 and 404 save nothing), mode 600, never in any
output and never on a command line (curl gets it as a config line on its stdin); start dispatches windows-package.yml on the
branch with the live client build and allow_dev_key false, finds the run, refuses while one is queued or in progress;
status parses state, jobs, failed step, release and newer-than-installed; the client build rule (never backwards, the same
number only while the client program is unchanged since the live client's commit, a new number with a note, the pending
number becoming the baseline once live); API errors.

Timezone guard (timezone, timezone set, O439): a fake timedatectl and TZ as the process zone; UTC is WRONG with exit 1 and the
zone, offset, expected zone and fix; the right name with the wrong offset (and the reverse) is WRONG; set calls timedatectl
set-timezone with the expected zone (CHAOS_TIMEZONE of the env file, a bad value ignored), prints the result and the restart
note, never restarts; refusals set nothing.

Launch check (launch-check, O440): the wiring of server/deploy/launch_check.py with a stub mysql and a stub for the checkout
tool: five count queries (only SELECT COUNT), the payments facts of pay-status, the flags --json / --max-players / --launch,
exit 1 on a FAIL, a table or the database missing fails its own line and nothing crashes, no key, password or token in any
output, nothing changed on disk, arguments refused before anything runs.

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

        # publish-unity (O433 phase 16): the Unity client channel, release tags only, same background log
        for bad in (('publish-unity',), ('publish-unity', '/tmp/x.zip'), ('publish-unity', 'a;b'), ('publish-unity', 'v1..2'),
                    ('publish-unity', 'unity-3', 'unity-4'), ('publish-unity', 'unity-3', '--version', 'x'),
                    ('publish-unity', 'unity-3', '--min-package', '13'), ('publish-unity', 'unity-3', '--key', '/tmp/k')):
            check(run(*bad, extra=pe).returncode != 0, 'publish-unity refuses %r' % (bad,))
        for argv, want in ((('unity-3',), 'args --unity -- unity-3'),
                           (('unity-3', '--version', '7'), 'args --unity --version 7 -- unity-3')):
            r = run('publish-unity', *argv, extra=pe)
            check(r.returncode == 0 and 'publish-log' in r.stdout, 'publish-unity %r starts: %s' % (argv, r.stdout + r.stderr))
            for _ in range(50):
                if os.path.exists(plog) and 'site=' in open(plog).read():
                    break
                time.sleep(0.1)
            out = run('publish-log', extra=pe).stdout
            check(want in out and 'site=/srv/site' in out, 'publish-unity %r passes %r: %s' % (argv, want, out))

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
    test_newplayer()
    test_health_balance()
    test_feedback()
    test_discord()
    test_discord_bot()
    test_pay()
    test_engine_build()
    test_github_private()
    test_server_user()
    test_timezone()
    test_launch_check()
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
        # a running kit update: the pair is not written (the update would refuse its swap ten minutes later, O486)
        import fcntl
        pair_kstate = os.path.join(tmp, 'pair-kstate')
        os.makedirs(pair_kstate)
        with open(os.path.join(pair_kstate, '.lock'), 'w') as lockf:
            fcntl.flock(lockf, fcntl.LOCK_EX)
            r = run('client-pair', 'set', '57', extra={'CHAOS_KIT_STATE': pair_kstate})
            check(r.returncode != 0 and 'update-running' in r.stderr
                  and 'chaosClientPair=56' in run('client-pair', 'show').stdout,
                  'client-pair set waits for a running kit update: ' + r.stdout + r.stderr)
            check(run('client-pair', 'show', extra={'CHAOS_KIT_STATE': pair_kstate}).returncode == 0,
                  'client-pair show works while an update runs')
            fcntl.flock(lockf, fcntl.LOCK_UN)
        r = run('client-pair', 'set', '57', extra={'CHAOS_KIT_STATE': pair_kstate})
        check(r.returncode == 0 and 'chaosClientPair=57' in run('client-pair', 'show').stdout,
              'client-pair set once the update ended: ' + r.stdout + r.stderr)

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
        r = run('site-log', extra={'CHAOS_SITE_LOG': os.path.join(tmp, 'no-site.log')})
        check(r.returncode == 0 and 'no site install log yet' in r.stdout, 'site-log without a log: ' + r.stdout + r.stderr)
        r = run('publish-log', extra={'CHAOS_PUBLISH_LOG': os.path.join(tmp, 'no-publish.log')})
        check(r.returncode == 0 and 'no publish log yet' in r.stdout, 'publish-log without a log: ' + r.stdout + r.stderr)

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
    # O437 retention: one old cohort day (20089 = 2025-01-01, the day the counters began) so every window is over
    ('meta', 'retain_since', '', 20089), ('cohort', '20250101', '', 20), ('retain', 'd1', '20250101', 8),
    ('retain', 'd2_7', '20250101', 5), ('retain', 'd8_30', '20250101', 6), ('retain', 'in7', '20250101', 10),
    ('retain', 'in30', '20250101', 12),
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


NEWPLAYER_MYSQL = r'''#!/usr/bin/env bash
echo "$(basename "$0") $*" >> "$STUB/calls"
case "$*" in
  *"FROM \`chaos_survey\`"*)
    case "${STUB_NP_FAIL:-}" in
      table) echo "ERROR 1146 (42S02) at line 1: Table 'chaos.chaos_survey' doesn't exist" >&2; exit 1 ;;
      db) echo "ERROR 2002 (HY000): Can't connect to local MySQL server" >&2; exit 1 ;;
    esac
    cat "$STUB/survey.tsv" ;;
  *"FROM \`players\`"*)
    [ -z "${STUB_NP_FAIL:-}" ] || { echo "ERROR 2002 (HY000): Can't connect" >&2; exit 1; }
    cat "$STUB/funnel.tsv" ;;
esac
'''


def test_newplayer():
    """chaos-ctl.sh newplayer-funnel / survey (O374, server/tools/newplayer_report.py); synthetic rows only"""
    repo_root = os.path.dirname(os.path.dirname(HERE))
    with tempfile.TemporaryDirectory() as tmp:
        stub = os.path.join(tmp, 'stub')
        repo = os.path.join(tmp, 'repo')
        os.makedirs(stub)
        os.makedirs(os.path.join(repo, 'server', 'tools'))
        shutil.copy(os.path.join(repo_root, 'server', 'tools', 'newplayer_report.py'), os.path.join(repo, 'server', 'tools'))
        for name, body in (('systemctl', SYSTEMCTL), ('mysql', NEWPLAYER_MYSQL)):
            p = os.path.join(stub, name)
            with open(p, 'w') as f:
                f.write(body)
            os.chmod(p, 0o755)
        with open(os.path.join(stub, 'funnel.tsv'), 'w') as f:
            f.write('0\t0\t1\t1\t1\t1\t0\t40\n2\t1\t1\t1\t5\t4\t2\t8\n3\t2\t0\t1\t0\t0\t0\t12\n')
        with open(os.path.join(stub, 'survey.tsv'), 'w') as f:
            f.write('20\tanswered\t4\t1\t21\t95\t1790000000\tWhere is the bank?\n20\tskipped\t0\t-1\t20\t60\t1790000000\t\n')
        env_file = os.path.join(tmp, 'chaos.env')
        with open(env_file, 'w') as f:
            f.write('CHAOS_DB_USER=chaos\nCHAOS_DB_PASS=secret\n')
        env = dict(os.environ, PATH=stub + ':' + os.environ['PATH'], STUB=stub, CHAOS_CTL_NO_SUDO='1',
                   CHAOS_SERVER_DIR=os.path.join(tmp, 'server'), CHAOS_ENV=env_file, CHAOS_REPO=repo,
                   CHAOS_MYSQL='mysql', CHAOS_CTL_CONF=os.path.join(tmp, 'none.conf'),
                   CHAOS_PID_FILE=os.path.join(tmp, 'no.pid'), CHAOS_LOG=os.path.join(tmp, 'no.log'))
        for k in ('SUDO_USER', 'CHAOS_UNIT', 'CHAOS_ROOT', 'CHAOS_KIT_DIR', 'CHAOS_DB_SOCKET', 'STUB_NP_FAIL'):
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

        r = run('newplayer-funnel')
        check(r.returncode == 0 and 'Characters: 60' in r.stdout and 'last 30 days' in r.stdout,
              'newplayer-funnel: text, 30 days by default: ' + r.stdout + r.stderr)
        q = calls()
        check('GROUP BY `reach`' in q and '`rs`.`key` = 7102831' in q, 'newplayer-funnel: the grouped query: ' + q)
        for column in ('`name`', 'account', 'lastip', 'email'):
            check(column not in q, 'newplayer-funnel never reads ' + column)
        check('secret' not in q, 'newplayer-funnel: the password is not on a command line')
        reset()
        r = run('newplayer-funnel', '--days', '90', '--json')
        d = json.loads(r.stdout or '{}')
        check(r.returncode == 0 and d.get('ok') and d.get('days') == 90 and d.get('characters') == 60,
              'newplayer-funnel --json --days 90: ' + r.stdout)
        r = run('newplayer-funnel', '--pt')
        check(r.returncode == 0 and 'Personagens: 60' in r.stdout, 'newplayer-funnel --pt')
        reset()
        r = run('survey', '--pt')
        check(r.returncode == 0 and 'Pesquisa do nível 20: 1 responderam, 1 pularam' in r.stdout
              and 'Where is the bank?' in r.stdout, 'survey --pt: ' + r.stdout + r.stderr)
        q = calls()
        check('FROM `chaos_survey`' in q and 'account_id' not in q, 'survey: the query reads no account: ' + q)
        r = run('survey', '--json', '--texts', '5', '--days', '7')
        d = json.loads(r.stdout or '{}')
        check(r.returncode == 0 and d.get('answers') == 2 and d.get('days') == 7, 'survey --json: ' + r.stdout)
        r = run('survey', '--json', extra={'STUB_NP_FAIL': 'table'})
        check(r.returncode == 1 and json.loads(r.stdout or '{}') == {'ok': False, 'error': 'no-table'},
              'survey: no table: ' + r.stdout)
        r = run('newplayer-funnel', '--json', extra={'STUB_NP_FAIL': 'db'})
        check(r.returncode == 1 and json.loads(r.stdout or '{}') == {'ok': False, 'error': 'database'},
              'newplayer-funnel: database down: ' + r.stdout)
        reset()
        for args in (('newplayer-funnel', '--days'), ('newplayer-funnel', '--days', '0'), ('newplayer-funnel', '--days', '3651'),
                     ('newplayer-funnel', '--days', '1;id'), ('newplayer-funnel', '--days', '$(id)'),
                     ('newplayer-funnel', '--texts', '5'), ('newplayer-funnel', 'x'), ('survey', '--texts', '501'),
                     ('survey', '--texts', 'x'), ('survey', '--bogus'), ('survey', '--days', '99999')):
            r = run(*args)
            check(r.returncode != 0, 'refuses %r' % (args,))
        check(calls() == '', 'a refused call never reaches the database')


HEALTH_MYSQL = r'''#!/usr/bin/env bash
echo "$(basename "$0") $*" >> "$STUB/calls"
case " $* " in *" -e "*) q="$*" ;; *) q=$(cat); echo "STDIN: $q" >> "$STUB/calls" ;; esac
case "$q" in
  *chaos_telemetry_online*)
    case "${STUB_GH_FAIL:-}" in
      table) echo "ERROR 1146 (42S02) at line 1: Table 'chaos.chaos_telemetry_area' doesn't exist" >&2; exit 1 ;;
      db) echo "ERROR 2002 (HY000): Can't connect to local MySQL server" >&2; exit 1 ;;
    esac
    cat "$STUB/gh.tsv" ;;
  *"'sw'"*) [ -z "${STUB_BR_FAIL:-}" ] || exit 1; cat "$STUB/sw.tsv" ;;
  *chaos_telemetry_class*)
    [ "${STUB_BR_FAIL:-}" != table ] || { echo "ERROR 1146 (42S02): Table 'chaos.chaos_telemetry_class' doesn't exist" >&2; exit 1; }
    cat "$STUB/br.tsv" ;;
esac
'''


def test_health_balance():
    """chaos-ctl.sh game-health (O397) and balance-report (O398); synthetic rows only"""
    import getpass
    repo_root = os.path.dirname(os.path.dirname(HERE))
    with tempfile.TemporaryDirectory() as tmp:
        stub = os.path.join(tmp, 'stub')
        repo = os.path.join(tmp, 'repo')
        server = os.path.join(tmp, 'server')
        sysd = os.path.join(tmp, 'systemd')
        baldir = os.path.join(tmp, 'balance')
        botdata = os.path.join(tmp, 'botdata')
        for d in (stub, os.path.join(repo, 'server', 'tools'), os.path.join(repo, 'server', 'deploy'),
                  os.path.join(server, 'data', 'scripts', 'chaos'), sysd, botdata):
            os.makedirs(d)
        for f in ('game_health.py', 'newplayer_report.py', 'balance_report.py', 'balance_report_config.json'):
            shutil.copy(os.path.join(repo_root, 'server', 'tools', f), os.path.join(repo, 'server', 'tools'))
        for f in ('chaos-balance.service', 'chaos-balance.timer'):
            shutil.copy(os.path.join(HERE, f), os.path.join(repo, 'server', 'deploy'))
        for name, body in (('systemctl', SYSTEMCTL), ('mysql', HEALTH_MYSQL)):
            p = os.path.join(stub, name)
            with open(p, 'w') as f:
                f.write(body)
            os.chmod(p, 0o755)
        now = int(time.time())
        h = now - now % 3600
        with open(os.path.join(stub, 'gh.tsv'), 'w') as f:
            f.write('on\t%d\t12\t120\t14\non\t%d\t12\t240\t25\nde\t%d\t4\n' % (h - 7200, h - 3600, h - 3600))
            f.write('hu\tAshen Caves\t40\t36000\t900\nhu\tRift\t3\t1200\t50\nda\tAshen Caves\t7\n')
            f.write('ec\tfaucet\tloot\t500000\t300\nec\tsink\tsupplies\t120000\t280\n')
            f.write('fn\t2\t1\t1\t1\t5\t4\t2\t8\nfn\t3\t2\t0\t1\t0\t0\t0\t12\n')
        with open(os.path.join(server, 'data', 'chaos_poi.lua'), 'w') as f:
            f.write('return {marks = {\n\t\t{k = "hunt", x = 1, y = 1, z = 7, n = "Bone Pits", r = 1},\n}}\n')
        with open(os.path.join(server, 'data', 'scripts', 'chaos', 'season_config.lua'), 'w') as f:
            f.write('return {seasons = {\n\t{\n\t\tid = 1,\n\t\tname = "Season of Ash",\n\t\ttag = "[S1]",\n'
                    '\t\tstart = 20261120,\n\t\tfinish = 20270219,\n\t\thour = 15\n\t}\n}}\n')
        # season 1 ended 3 days ago (the /season end override of the database wins over the file's dates)
        with open(os.path.join(stub, 'sw.tsv'), 'w') as f:
            f.write('sw\t1\t%d\t%d\n' % (now - 40 * 86400, now - 3 * 86400))
        rows = []
        need = 50 * 400 * 400 - 150 * 400 + 200
        for voc, mins in ((1, 30), (3, 45), (4, 20), (5, 31), (7, 29)):
            rows.append('hu\t300-499\t%d\t40\t36000\t%d\t100' % (voc, int(need / float(mins) * 600)))
            rows.append('cl\t300-499\t%d\t5\t1000000' % voc)
        rows.append('ca\t3\tArrow Rain\t900')
        with open(os.path.join(stub, 'br.tsv'), 'w') as f:
            f.write('\n'.join(rows) + '\n')
        env_file = os.path.join(tmp, 'chaos.env')
        with open(env_file, 'w') as f:
            f.write('CHAOS_DB_USER=chaos\nCHAOS_DB_PASS=secret\n')
        env = dict(os.environ, PATH=stub + ':' + os.environ['PATH'], STUB=stub, CHAOS_CTL_NO_SUDO='1',
                   CHAOS_SERVER_DIR=server, CHAOS_ENV=env_file, CHAOS_REPO=repo, CHAOS_MYSQL='mysql',
                   CHAOS_CTL_CONF=os.path.join(tmp, 'none.conf'), CHAOS_PID_FILE=os.path.join(tmp, 'no.pid'),
                   CHAOS_LOG=os.path.join(tmp, 'no.log'), CHAOS_SYSTEMD_DIR=sysd, CHAOS_BALANCE_DIR=baldir,
                   CHAOS_BOT_DATA=botdata, CHAOS_BOT_USER=getpass.getuser())
        for k in ('SUDO_USER', 'CHAOS_UNIT', 'CHAOS_ROOT', 'CHAOS_KIT_DIR', 'CHAOS_DB_SOCKET', 'STUB_GH_FAIL',
                  'STUB_BR_FAIL'):
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

        # ---- game-health (O397)
        r = run('game-health', '--kv', '--pt')
        kv = r.stdout.splitlines()
        check(r.returncode == 0 and 'ok=1' in kv and 'days=7' in kv, 'game-health --kv: ' + r.stdout[:300] + r.stderr)
        check(sum(1 for x in kv if x.startswith('hour=')) == 7 * 24, 'game-health: one line per hour of 7 days')
        check('hunt_top=40 10.0 900 7 Ashen Caves' in kv and 'hunt_low=0 0.0 0 0 Bone Pits' in kv,
              'game-health: hunts, the installed markers included: %r' % [x for x in kv if x.startswith('hunt')])
        check('hunt_top=<5 0.3 50 0 Rift' in kv, 'game-health: small groups "<5"')
        q = calls()
        check('chaos_telemetry_online' in q and 'GROUP BY `reach`' in q, 'game-health: one script, telemetry and funnel')
        for column in ('`name`', 'account', 'lastip', 'email'):
            check(column not in q, 'game-health never reads ' + column)
        check('secret' not in q, 'game-health: the password is not on a command line')
        reset()
        r = run('game-health', '--days', '30')
        check(r.returncode == 0 and 'Game health: the last 30 days' in r.stdout, 'game-health text: ' + r.stdout[:200])
        r = run('game-health', '--json')
        d = json.loads(r.stdout or '{}')
        check(r.returncode == 0 and d.get('ok') and d['hunts']['top'][0]['name'] == 'Ashen Caves', 'game-health --json')
        r = run('game-health', '--kv', extra={'STUB_GH_FAIL': 'table'})
        check(r.returncode == 1 and r.stdout.strip() == 'ok=0\nerror=no-table', 'game-health: no table: ' + r.stdout)
        r = run('game-health', '--json', extra={'STUB_GH_FAIL': 'db'})
        check(r.returncode == 1 and json.loads(r.stdout or '{}') == {'ok': False, 'error': 'database'},
              'game-health: database down')
        reset()
        for args in (('game-health', '--days'), ('game-health', '--days', '0'), ('game-health', '--days', '91'),
                     ('game-health', '--days', '1;id'), ('game-health', '--days', '$(id)'), ('game-health', 'x')):
            r = run(*args)
            check(r.returncode != 0, 'refuses %r' % (args,))
        check(calls() == '', 'a refused game-health never reaches the database')

        # ---- balance-report (O398)
        r = run('balance-report', '--pt', '--days', '30')
        check(r.returncode == 0 and r.stdout.startswith('# Relatório de equilíbrio: últimos 30 dias')
              and 'Ranger, nível 300-499: sobe de nível 50% mais devagar' in r.stdout,
              'balance-report --pt: ' + r.stdout[:600] + r.stderr)
        q = calls()
        check('chaos_telemetry_hunt' in q and 'player_id' not in q and '`name`' not in q, 'balance-report: aggregates only')
        check(not os.path.exists(baldir), 'nothing saved without --save')
        reset()
        r = run('balance-report', '--season', 'current', '--json')
        d = json.loads(r.stdout or '{}')
        check(r.returncode == 0 and d.get('title') == 'Season of Ash [S1]'
              and abs(d.get('until', 0) - (now - 3 * 86400)) < 5, 'balance-report --season current: '
              + r.stdout[:300] + r.stderr)
        check("'chaos_season_1_end'" in calls(), 'the season window reads the /season overrides')
        r = run('balance-report', '--season', '1', '--pt', '--dm')
        check(r.returncode == 0 and 'saved=%s/season-1.md' % baldir in r.stdout and 'dm=queued' in r.stdout,
              'balance-report --dm: ' + r.stdout[-300:] + r.stderr)
        check(os.path.exists(os.path.join(botdata, 'outbox', 'season-1.md')), 'the report waits in the bot outbox')
        r = run('balance-report', 'last')
        check(r.returncode == 0 and r.stdout.startswith('# Relatório de equilíbrio: Season of Ash'), 'balance-report last')
        r = run('balance-report', 'auto')
        check(r.returncode == 0 and 'nothing due' in r.stdout, 'auto: a saved season is not due again: ' + r.stdout + r.stderr)
        os.unlink(os.path.join(baldir, 'season-1.md'))
        shutil.rmtree(os.path.join(botdata, 'outbox'))
        r = run('balance-report', 'auto')
        check(r.returncode == 0 and 'season 1 report saved' in r.stdout and 'dm=queued' in r.stdout,
              'auto: the ended season gets its report: ' + r.stdout + r.stderr)
        check(os.path.exists(os.path.join(baldir, 'season-1.md')) and
              os.path.exists(os.path.join(botdata, 'outbox', 'season-1.md')), 'auto: saved and queued')
        nobot = {'CHAOS_BOT_DATA': os.path.join(tmp, 'nobot')}
        r = run('balance-report', '--days', '7', '--save', extra=nobot)
        check(r.returncode == 0 and 'saved=%s/balance-' % baldir in r.stdout, 'balance-report --save')
        r = run('balance-report', '--days', '7', '--dm', extra=nobot)
        check(r.returncode == 0 and 'dm=no-bot' in r.stdout, 'no bot installed: said, not failed')
        r = run('balance-report', '--json', extra={'STUB_BR_FAIL': 'table'})
        check(r.returncode == 1 and json.loads(r.stdout or '{}') == {'ok': False, 'error': 'no-table'},
              'balance-report: no table: ' + r.stdout)
        r = run('balance-report', '--season', '9')
        check(r.returncode != 0 and 'no-season' in r.stderr, 'an unknown season')
        reset()
        r = run('balance-report', 'timer', 'on')
        check(r.returncode == 0 and os.path.exists(os.path.join(sysd, 'chaos-balance.timer')), 'timer on: ' + r.stderr)
        unit = open(os.path.join(sysd, 'chaos-balance.service')).read()
        check(repo + '/server/deploy/chaos-ctl.sh balance-report auto' in unit, 'timer on: the real repository path')
        check('enable --now chaos-balance.timer' in calls(), 'timer on: enabled')
        r = run('balance-report', 'timer', 'status')
        check('timer_installed=yes' in r.stdout and 'season-1.md' in r.stdout, 'timer status: ' + r.stdout)
        r = run('balance-report', 'timer', 'off')
        check(r.returncode == 0 and 'disable --now chaos-balance.timer' in calls(), 'timer off')
        reset()
        for args in (('balance-report', '--days', '0'), ('balance-report', '--days', '731'),
                     ('balance-report', '--days', '1;id'), ('balance-report', '--season', 'x'),
                     ('balance-report', '--season', '$(id)'), ('balance-report', '--days', '7', '--season', '1'),
                     ('balance-report', '--bogus'), ('balance-report', 'timer', 'maybe'), ('balance-report', 'last', 'x')):
            r = run(*args)
            check(r.returncode != 0, 'refuses %r' % (args,))
        check(calls() == '', 'a refused balance-report never reaches the database')


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
        rt = d.get('retention', [{}])
        check(len(rt) == 1 and rt[0].get('day') == '2025-01-01' and rt[0].get('cohort') == 20 and rt[0].get('d1Pct') == 40.0
              and rt[0].get('in7Pct') == 50.0 and rt[0].get('in30Pct') == 60.0 and rt[0].get('d8_30Pct') == 30.0,
              'metrics: retention by creation day: ' + str(rt))
        check(d.get('retentionSince') == '2025-01-01' and [e['window'] for e in d.get('retentionAll', [])]
              == ['d1', 'd2_7', 'd8_30', 'in7', 'in30'] and d['retentionAll'][0]['pct'] == 40.0,
              'metrics: retention totals: ' + str(d.get('retentionAll')))
        r = run('metrics')
        check(r.returncode == 0 and 'Churn (gone = no login for 14 days; 36 gone, 28 active)' in r.stdout
              and 'Ember Caves' in r.stdout and 'level 10: 10 min' in r.stdout, 'metrics: text: ' + r.stdout + r.stderr)
        check('Retention by creation day' in r.stdout and '2025-01-01: 20 new, day 1 8 (40.0%)' in r.stdout,
              'metrics: text has the retention section: ' + r.stdout)
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
        r = run('discord-set', 'records', stdin='1567178340434059494\n')
        check(r.returncode != 0 and 'channel ID' in r.stderr and 'Guardar ajuste' in r.stderr and not os.path.exists(denv),
              'discord-set: a channel ID points to the bot setting: ' + r.stderr)
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


def test_pay():
    """pay-status | pay-set | pay-test | pay-enable | pay-disable (donations, O413; docs/PAYMENTS.md)"""
    repo_root = os.path.dirname(os.path.dirname(HERE))
    mp_token = 'APP_USR-1234567890123456-110512-0a1b2c3d4e5f60718293a4b5c6d7e8f9-123456789'
    mp_secret = 'f00dfeedc0ffee1234567890abcdef0123456789abcdef0123456789abcdef01'
    pp_id = 'AaBbCcDdEeFfGgHhIiJjKkLlMmNnOoPpQqRrSsTtUuVvWwXxYyZz0123456789_-AaBbCcDdEeFfGgHh'
    pp_secret = 'EeSsCcRrEeTt0123456789_-EeSsCcRrEeTt0123456789_-EeSsCcRrEeTt0123456789_-EeSsCcRr'
    secrets = (mp_token, mp_secret, pp_id, pp_secret)
    # curl: records its arguments and stdin; the code by URL (on stdin for the providers, on the line for the webhooks)
    curl = '''#!/usr/bin/env bash
echo "curl $*" >> "$STUB/calls"
in=""
case " $* " in *" -K - "*) in=$(cat) ;; esac
printf '%s\\n--\\n' "$in" >> "$STUB/curl.stdin"
out=""
while [ $# -gt 0 ]; do [ "$1" = -o ] && out=$2; shift; done
case "$in" in
  *mercadopago*) [ -n "$out" ] && [ "$out" != /dev/null ] && printf '{"id":1,"site_id":"MLB","email":"x@y.z"}' > "$out"
                 printf '%s' "${STUB_MP_CODE:-200}" ;;
  *paypal*) printf '%s' "${STUB_PP_CODE:-200}" ;;
  *) printf '%s' "${STUB_HOOK_CODE:-401}" ;;
esac
'''
    sysctl = '''#!/usr/bin/env bash
echo "systemctl $*" >> "$STUB/calls"
case "$*" in
  is-active*) [ -e "$STUB/active" ] && echo active || { echo inactive; exit 3; } ;;
  is-enabled*) [ -e "$STUB/enabled" ] && echo enabled || echo disabled ;;
  "enable --now"*) touch "$STUB/enabled" "$STUB/active" ;;
  "disable --now"*) rm -f "$STUB/enabled" "$STUB/active" ;;
esac
exit 0
'''
    with tempfile.TemporaryDirectory() as tmp:
        stub = os.path.join(tmp, 'stub')
        repo = os.path.join(tmp, 'repo')
        site = os.path.join(tmp, 'site')
        sysd = os.path.join(tmp, 'systemd')
        for d in (stub, os.path.join(repo, 'server', 'deploy'), os.path.join(repo, 'website'),
                  os.path.join(site, 'plugins', 'chaos', 'pay'), sysd):
            os.makedirs(d)
        for f in ('chaos-payworker.service', 'chaos.logrotate'):
            shutil.copy(os.path.join(HERE, f), os.path.join(repo, 'server', 'deploy', f))
        shutil.copy(os.path.join(repo_root, 'website', 'payments.env.example'), os.path.join(repo, 'website'))
        open(os.path.join(site, 'plugins', 'chaos', 'pay', 'worker.php'), 'w').close()
        for name, body in (('curl', curl), ('systemctl', sysctl)):
            p = os.path.join(stub, name)
            with open(p, 'w') as f:
                f.write(body)
            os.chmod(p, 0o755)
        site_env = os.path.join(tmp, 'site.env')
        with open(site_env, 'w') as f:
            f.write('CHAOS_SITE_URL=https://example.org/\n')
        penv = os.path.join(tmp, 'etc', 'payments.env')
        wlog = os.path.join(tmp, 'logs', 'payworker.log')
        os.makedirs(os.path.dirname(wlog))
        with open(wlog, 'w') as f:
            f.write('order 7: mercadopago charge 99, expires 12:00\nerror for donor@example.com token APP_USR-123-abc\n')
        user = subprocess.run(['id', '-un'], capture_output=True, text=True).stdout.strip()
        group = subprocess.run(['id', '-gn'], capture_output=True, text=True).stdout.strip()
        env = dict(os.environ, PATH=stub + ':' + os.environ['PATH'], STUB=stub, CHAOS_CTL_NO_SUDO='1',
                   CHAOS_SERVER_DIR=os.path.join(tmp, 'server'), CHAOS_ENV=os.path.join(tmp, 'chaos.env'),
                   CHAOS_REPO=repo, CHAOS_CTL_CONF=os.path.join(tmp, 'none.conf'),
                   CHAOS_PID_FILE=os.path.join(tmp, 'no.pid'), CHAOS_LOG=os.path.join(tmp, 'no.log'),
                   CHAOS_PAY_ENV=penv, CHAOS_PAY_USER=user, CHAOS_PAY_GROUP=group, CHAOS_PAYWORKER_LOG=wlog,
                   CHAOS_SITE_ENV=site_env, CHAOS_SITE_DIR=site, CHAOS_SYSTEMD_DIR=sysd,
                   CHAOS_LOGROTATE_FILE=os.path.join(tmp, 'logrotate-chaos'))
        for k in ('SUDO_USER', 'CHAOS_UNIT', 'CHAOS_ROOT', 'CHAOS_KIT_DIR', 'CHAOS_DB_SOCKET', 'CHAOS_BACKUP_DIR'):
            env.pop(k, None)
        seen = []

        def run(*args, stdin=None, extra=None):
            r = subprocess.run(['bash', SCRIPT] + list(args), env=dict(env, **(extra or {})), input=stdin,
                               capture_output=True, text=True)
            seen.append(r.stdout + r.stderr)
            return r

        def calls():
            p = os.path.join(stub, 'calls')
            return open(p).read() if os.path.exists(p) else ''

        def text():
            return open(penv).read()

        def kv(out):
            d = {}
            for line in out.splitlines():
                if line.startswith('@'):
                    break
                if '=' in line:
                    k, v = line.split('=', 1)
                    d.setdefault(k, v)
            return d

        # refusals: nothing is written, not even the file
        for name, bad in (('CHAOS_PAY_PIX_PROVIDER', 'mock'), ('CHAOS_PAY_PIX_PROVIDER', 'paypal'),
                          ('CHAOS_PAY_PAYPAL_PROVIDER', 'mock'), ('CHAOS_PAYPAL_ENV', 'production'),
                          ('CHAOS_PAY_SITE_URL', 'http://example.org'), ('CHAOS_PAY_SITE_URL', 'https://example.org/?a=1'),
                          ('CHAOS_PAY_SITE_URL', 'https://user@example.org'), ('CHAOS_MP_ACCESS_TOKEN', 'abc'),
                          ('CHAOS_MP_ACCESS_TOKEN', mp_token + '$(id)'), ('CHAOS_MP_ACCESS_TOKEN', 'XX-' + mp_token[8:]),
                          ('CHAOS_PAYPAL_CLIENT_SECRET', 'short'), ('CHAOS_PAYPAL_WEBHOOK_ID', 'ab cd'),
                          ('CHAOS_PAY_PAYER_EMAIL', 'not an email'), ('CHAOS_PAYPAL_CATEGORY', 'GOODS'),
                          ('CHAOS_MP_WEBHOOK_SECRET', mp_secret + '\nCHAOS_PAY_ALLOW_MOCK=1')):
            r = run('pay-set', name, stdin=bad + '\n')
            check(r.returncode != 0, 'pay-set refuses %s=%r' % (name, bad))
            check(not os.path.exists(penv), 'pay-set: a refused value writes nothing: %r' % bad)
            check(bad not in r.stdout + r.stderr or len(bad) < 8, 'pay-set: a refused value is not echoed')
        for bad in ('CHAOS_PAY_ALLOW_MOCK', 'CHAOS_PAY_PAYER_SALT', 'CHAOS_PAY_LOG', 'x;id', ''):
            r = run('pay-set', bad, stdin='1\n')
            check(r.returncode != 0 and not os.path.exists(penv), 'pay-set refuses the name %r' % bad)
        check(run('pay-set', 'CHAOS_PAYPAL_ENV', 'live').returncode != 0 and not os.path.exists(penv),
              'pay-set: a value on the command line is no input')

        # the first save creates the file from the example, mode 640, with a random payer salt
        r = run('pay-set', 'CHAOS_MP_ACCESS_TOKEN', stdin=mp_token + '\n')
        check(r.returncode == 0 and 'CHAOS_MP_ACCESS_TOKEN saved' in r.stdout and 'created' in r.stdout
              and 'payer salt' in r.stdout, 'pay-set first save: ' + r.stdout + r.stderr)
        check(stat.S_IMODE(os.stat(penv).st_mode) == 0o640, 'payments.env is mode 640: %o' % os.stat(penv).st_mode)
        t = text()
        check('# Settings of the donation flow' in t and t.count('CHAOS_MP_ACCESS_TOKEN=') == 1
              and 'CHAOS_MP_ACCESS_TOKEN=' + mp_token + '\n' in t, 'pay-set: the example kept, the line replaced in place')
        salt = re.search(r'^CHAOS_PAY_PAYER_SALT=(\S+)$', t, re.M)
        check(salt is not None and len(salt.group(1)) >= 40, 'pay-set: payer salt made')
        r = run('pay-set', 'CHAOS_MP_WEBHOOK_SECRET', stdin=mp_secret + '\r\n')
        check(r.returncode == 0 and 'payer salt' not in r.stdout and re.search(r'^CHAOS_PAY_PAYER_SALT=(\S+)$', text(), re.M).group(1) == salt.group(1),
              'pay-set: the salt is made once and kept')
        for name, val in (('CHAOS_PAY_PIX_PROVIDER', 'mercadopago'), ('CHAOS_PAY_PAYPAL_PROVIDER', 'paypal'),
                          ('CHAOS_PAYPAL_CLIENT_ID', pp_id), ('CHAOS_PAYPAL_CLIENT_SECRET', pp_secret),
                          ('CHAOS_PAYPAL_WEBHOOK_ID', '1JE4291016473214C'), ('CHAOS_PAYPAL_ENV', 'live'),
                          ('CHAOS_PAY_PAYER_EMAIL', 'donor+{account}@example.org'), ('CHAOS_PAYPAL_CATEGORY', 'DIGITAL_GOODS')):
            r = run('pay-set', name, stdin='  ' + val + '  \n')
            check(r.returncode == 0 and name + ' saved' in r.stdout and name + '=' + val + '\n' in text(), 'pay-set %s: %s' % (name, r.stdout + r.stderr))
            check(val not in r.stdout + r.stderr, 'pay-set %s: the value is never echoed' % name)
        check(text().count('CHAOS_PAYPAL_ENV=') == 1 and 'CHAOS_PAYPAL_ENV=sandbox' not in text(), 'pay-set: PAYPAL_ENV replaced')
        check(not [n for n in os.listdir(os.path.dirname(penv)) if n != 'payments.env'], 'pay-set: no temp file left')
        check(stat.S_IMODE(os.stat(penv).st_mode) == 0o640, 'payments.env still mode 640 after rewrites')
        r = run('pay-set', 'CHAOS_PAYPAL_CATEGORY', stdin='\n')
        check(r.returncode == 0 and 'emptied' in r.stdout and 'CHAOS_PAYPAL_CATEGORY=\n' in text(), 'pay-set: empty input empties the value')
        before = text()
        r = run('pay-set', 'CHAOS_PAYPAL_ENV', stdin='live\nCHAOS_PAY_ALLOW_MOCK=1\n')
        check(r.returncode != 0 and text() == before, 'pay-set: a second line is refused, nothing changed')
        # a hand-made duplicate line: the first is replaced, later ones go
        with open(penv, 'a') as f:
            f.write('CHAOS_PAYPAL_ENV=sandbox\n')
        run('pay-set', 'CHAOS_PAYPAL_ENV', stdin='sandbox\n')
        check(text().count('CHAOS_PAYPAL_ENV=') == 1, 'pay-set: duplicate lines collapse to one')
        run('pay-set', 'CHAOS_PAYPAL_ENV', stdin='live\n')
        # a running worker restarts after a save
        open(os.path.join(stub, 'active'), 'w').close()
        open(os.path.join(stub, 'calls'), 'w').close()
        r = run('pay-set', 'CHAOS_PAY_SITE_URL', stdin='https://donate.example.org/\n')
        check(r.returncode == 0 and 'systemctl restart chaos-payworker' in calls() and 'restarted' in r.stdout, 'pay-set restarts a running worker')
        os.remove(os.path.join(stub, 'active'))
        # a mode or owner gone wrong is put back
        os.chmod(penv, 0o666)
        run('pay-set', 'CHAOS_PAY_SITE_URL', stdin='\n')
        check(stat.S_IMODE(os.stat(penv).st_mode) == 0o640, 'pay-set puts mode 640 back')

        # status: yes / no, never a value; the webhook URLs from the site URL
        r = run('pay-status')
        out = kv(r.stdout)
        check(r.returncode == 0 and out.get('pix_provider') == 'mercadopago' and out.get('paypal_provider') == 'paypal'
              and out.get('paypal_env') == 'live' and out.get('mp_token') == 'live', 'pay-status: providers: ' + r.stdout + r.stderr)
        check(out.get('set_CHAOS_MP_ACCESS_TOKEN') == 'yes' and out.get('set_CHAOS_PAYPAL_CATEGORY') == 'no'
              and out.get('set_CHAOS_PAY_PAYER_SALT') == 'yes' and out.get('set_CHAOS_PAY_SITE_URL') == 'no', 'pay-status: set flags')
        check(out.get('paypal_category') == 'DONATION', 'pay-status: an empty category reads as the default')
        check(out.get('site_url') == 'https://example.org'
              and out.get('webhook_mercadopago') == 'https://example.org/chaos_pay_webhook.php?psp=mercadopago'
              and out.get('webhook_paypal') == 'https://example.org/chaos_pay_webhook.php?psp=paypal', 'pay-status: webhook URLs from site.env')
        check(out.get('env_file') == '640 %s:%s' % (user, group) and out.get('env_ok') == 'yes', 'pay-status: env file')
        check(out.get('site_installed') == 'yes' and out.get('worker_installed') == 'no' and out.get('worker_active') == 'inactive'
              and out.get('mock') == 'no', 'pay-status: worker and mock: ' + r.stdout)
        check('@log' in r.stdout and '@worker' in r.stdout and 'order 7: mercadopago charge 99' in r.stdout, 'pay-status: logs')
        check('donor@example.com' not in r.stdout and 'APP_USR-123' not in r.stdout, 'pay-status: e-mail and token masked in the log')
        check(run('pay-status', 'x').returncode != 0, 'pay-status takes no argument')
        run('pay-set', 'CHAOS_PAY_SITE_URL', stdin='https://donate.example.org/\n')
        out = kv(run('pay-status').stdout)
        check(out.get('webhook_paypal') == 'https://donate.example.org/chaos_pay_webhook.php?psp=paypal', 'pay-status: CHAOS_PAY_SITE_URL wins')

        # test: the providers with the secrets on curl's stdin, the webhooks unsigned
        open(os.path.join(stub, 'calls'), 'w').close()
        r = run('pay-test')
        check(r.returncode == 0 and 'pix=200 ok site=MLB token=live' in r.stdout and 'paypal=200 ok env=live' in r.stdout
              and 'webhook_pix=401 ok' in r.stdout and 'webhook_paypal=401 ok' in r.stdout, 'pay-test: ' + r.stdout + r.stderr)
        c = calls()
        check(not any(s in c for s in secrets), 'pay-test: no secret on a curl command line')
        cin = open(os.path.join(stub, 'curl.stdin')).read()
        check('url = "https://api.mercadopago.com/users/me"' in cin and 'Authorization: Bearer ' + mp_token in cin, 'pay-test: Mercado Pago on stdin')
        check('url = "https://api-m.paypal.com/v1/oauth2/token"' in cin and 'user = "%s:%s"' % (pp_id, pp_secret) in cin, 'pay-test: PayPal live host on stdin')
        check('https://donate.example.org/chaos_pay_webhook.php?psp=mercadopago' in c, 'pay-test: webhook URL called')
        r = run('pay-test', extra={'STUB_MP_CODE': '401', 'STUB_HOOK_CODE': '503'})
        check(r.returncode == 1 and 'pix=401 fail' in r.stdout and 'webhook_pix=503 fail' in r.stdout, 'pay-test: failures: ' + r.stdout)
        run('pay-set', 'CHAOS_PAYPAL_ENV', stdin='sandbox\n')
        run('pay-set', 'CHAOS_PAY_PAYPAL_PROVIDER', stdin='off\n')
        open(os.path.join(stub, 'curl.stdin'), 'w').close()
        r = run('pay-test')
        check(r.returncode == 0 and 'paypal=200 ok env=sandbox' in r.stdout and 'webhook_paypal=skipped' in r.stdout, 'pay-test: sandbox, provider off')
        check(re.search(r'^url = "https://api-m\.sandbox\.paypal\.com/v1/oauth2/token"$',
                        open(os.path.join(stub, 'curl.stdin')).read(), re.M) is not None, 'pay-test: sandbox host')
        check(run('pay-test', 'x').returncode != 0, 'pay-test takes no argument')

        # enable / disable
        open(os.path.join(stub, 'calls'), 'w').close()
        r = run('pay-enable')
        unit = os.path.join(sysd, 'chaos-payworker.service')
        check(r.returncode == 0 and 'chaos-payworker is on' in r.stdout and 'methods on: pix' in r.stdout, 'pay-enable: ' + r.stdout + r.stderr)
        ut = open(unit).read() if os.path.exists(unit) else ''
        check('--site ' + site + ' ' in ut and 'EnvironmentFile=-' + penv in ut and 'append:' + wlog in ut
              and 'ReadWritePaths=' + os.path.dirname(wlog) + '\n' in ut, 'pay-enable: unit with the real paths')
        check(os.path.isfile(os.path.join(tmp, 'logrotate-chaos')), 'pay-enable: logrotate installed')
        c = calls()
        check(c.index('systemctl daemon-reload') < c.index('systemctl enable --now chaos-payworker'), 'pay-enable: daemon-reload, then enable --now')
        open(os.path.join(stub, 'calls'), 'w').close()
        r = run('pay-enable')
        check(r.returncode == 0 and 'already' in r.stdout and 'daemon-reload' not in calls(), 'pay-enable twice: no reload')
        out = kv(run('pay-status').stdout)
        check(out.get('worker_installed') == 'yes' and out.get('worker_active') == 'active', 'pay-status after enable')
        r = run('pay-disable')
        check(r.returncode == 0 and 'systemctl disable --now chaos-payworker' in calls(), 'pay-disable: ' + r.stderr)
        r = run('pay-enable', extra={'CHAOS_SITE_DIR': os.path.join(tmp, 'nosite')})
        check(r.returncode != 0 and 'site-not-installed' in r.stderr, 'pay-enable: no site, no worker')
        check(run('pay-enable', 'x').returncode != 0 and run('pay-disable', 'x').returncode != 0, 'enable / disable take no argument')

        # a mock provider left in the file shows
        with open(penv, 'a') as f:
            f.write('CHAOS_PAY_PIX_PROVIDER=mock\n')
        out = kv(run('pay-status').stdout)
        check(out.get('mock') == 'yes' and out.get('pix_provider') == 'mock', 'pay-status: mock shows')

        check(not any(s in t for t in seen for s in secrets + (salt.group(1),)), 'no output of any pay command holds a secret')

def test_engine_build():
    """engine-build status | start | log and engine-build-token-set (O436): a fake curl plays the GitHub API"""
    token = 'github_pat_11ABCDEFG0aBcDeFgHiJkL_mNoPqRsTuVwXyZ0123456789aBcDeFgHiJkLmNoPqRsTuVwXyZ01234'
    # curl: records its arguments and its stdin (the config line), answers like the GitHub API from files of $STUB
    curl = '''#!/usr/bin/env python3
import json, os, re, sys
stub = os.environ['STUB']
args = sys.argv[1:]
cfg = sys.stdin.read() if '-K' in args else ''
open(os.path.join(stub, 'calls'), 'a').write('curl ' + ' '.join(args) + '\\n')
open(os.path.join(stub, 'curl.stdin'), 'a').write(cfg + '\\n--\\n')
out = args[args.index('-o') + 1] if '-o' in args else None
data = args[args.index('-d') + 1] if '-d' in args else None
url = re.search(r'url = "([^"]+)"', cfg).group(1)
def read(name, default=''):
    p = os.path.join(stub, name)
    return open(p).read() if os.path.exists(p) else default
def answer(code, body=''):
    if out:
        open(out, 'w').write(body)
    sys.stdout.write(str(code))
    sys.exit(0)
if re.search(r'/actions/workflows/windows-package\\.yml/dispatches$', url) and data is not None:
    open(os.path.join(stub, 'dispatch.json'), 'a').write(data + '\\n')
    code = read('dispatch.code', '204').strip()
    if code == '204':
        runs = json.loads(read('runs.json', '{"workflow_runs": []}'))['workflow_runs']
        n = max([r['id'] for r in runs] + [100]) + 1
        runs.append({'id': n, 'run_number': n - 900, 'status': 'queued', 'conclusion': None, 'created_at': '2026-11-08T10:00:00Z',
                     'updated_at': '2026-11-08T10:00:00Z', 'head_sha': 'a1b2c3d4e5f6', 'html_url': 'https://github.com/o/r/actions/runs/%d' % n})
        open(os.path.join(stub, 'runs.json'), 'w').write(json.dumps({'workflow_runs': runs}))
    answer(code)
if re.search(r'/actions/workflows/windows-package\\.yml$', url):
    answer(read('token.code', '200').strip(), '{}')
if '/actions/workflows/windows-package.yml/runs?' in url:
    answer(read('runs.code', '200').strip(), read('runs.json', '{"workflow_runs": []}'))
if re.search(r'/actions/runs/\\d+/jobs', url):
    answer(200, read('jobs.json', '{"jobs": []}'))
if '/releases/tags/' in url:
    p = os.path.join(stub, 'release.json')
    answer(200 if os.path.exists(p) else 404, read('release.json', '{}'))
answer(404)
'''
    git_env = dict(os.environ, GIT_AUTHOR_NAME='t', GIT_AUTHOR_EMAIL='t@example.org', GIT_COMMITTER_NAME='t',
                   GIT_COMMITTER_EMAIL='t@example.org', GIT_CONFIG_GLOBAL='/dev/null', GIT_CONFIG_SYSTEM='/dev/null')

    def git(cwd, *a):
        r = subprocess.run(['git', '-C', cwd] + list(a), env=git_env, capture_output=True, text=True)
        assert r.returncode == 0, (a, r.stderr)
        return r.stdout.strip()

    with tempfile.TemporaryDirectory() as tmp:
        stub = os.path.join(tmp, 'stub')
        os.makedirs(stub)
        p = os.path.join(stub, 'curl')
        with open(p, 'w') as f:
            f.write(curl)
        os.chmod(p, 0o755)
        # the checkout and its origin: the client program under client/base-patches, the server under server/src-patches
        origin = os.path.join(tmp, 'origin.git')
        work = os.path.join(tmp, 'work')
        repo = os.path.join(tmp, 'repo')
        subprocess.run(['git', 'init', '-q', '--bare', '-b', 'main', origin], env=git_env, check=True)
        os.makedirs(os.path.join(work, 'client', 'base-patches'))
        os.makedirs(os.path.join(work, 'server', 'src-patches'))
        subprocess.run(['git', 'init', '-q', '-b', 'main', work], env=git_env, check=True)
        open(os.path.join(work, 'client', 'base-patches', '0001-a.patch'), 'w').write('a\n')
        open(os.path.join(work, 'server', 'src-patches', '0089-loot.patch'), 'w').write('a\n')
        git(work, 'add', '-A')
        git(work, 'commit', '-q', '-m', 'one')
        git(work, 'remote', 'add', 'origin', origin)
        git(work, 'push', '-q', 'origin', 'main')
        base = git(work, 'rev-parse', 'HEAD')
        subprocess.run(['git', 'clone', '-q', origin, repo], env=git_env, check=True)
        kstate = os.path.join(tmp, 'kit-state')
        site = os.path.join(tmp, 'site')
        os.makedirs(kstate)
        os.makedirs(os.path.join(site, 'updates', 'live'))
        tfile = os.path.join(tmp, 'etc', 'engine-build.token')

        def write_state(release=100, commit=base):
            with open(os.path.join(kstate, 'state'), 'w') as f:
                f.write('installed_release=%d\ndeployed_commit=%s\n' % (release, commit))

        def write_manifest(min_package):
            with open(os.path.join(site, 'updates', 'live', 'manifest.json'), 'w') as f:
                json.dump({'payload': json.dumps({'version': 90, 'min_package': min_package})}, f)

        def put(name, text):
            with open(os.path.join(stub, name), 'w') as f:
                f.write(text)

        def drop(name):
            if os.path.exists(os.path.join(stub, name)):
                os.remove(os.path.join(stub, name))

        def set_run(status, conclusion=None, run_id=101, number=101, created='2026-11-08T10:00:00Z', updated='2026-11-08T10:40:00Z'):
            put('runs.json', json.dumps({'workflow_runs': [{
                'id': run_id, 'run_number': number, 'status': status, 'conclusion': conclusion, 'created_at': created,
                'updated_at': updated, 'head_sha': 'a1b2c3d4e5f6', 'html_url': 'https://github.com/o/r/actions/runs/%d' % run_id}]}))

        write_state()
        write_manifest(30)
        env = dict(os.environ, PATH=stub + ':' + os.environ['PATH'], STUB=stub, CHAOS_CTL_NO_SUDO='1',
                   CHAOS_SERVER_DIR=os.path.join(tmp, 'server'), CHAOS_ENV=os.path.join(tmp, 'chaos.env'),
                   CHAOS_REPO=repo, CHAOS_CTL_CONF=os.path.join(tmp, 'none.conf'), CHAOS_KIT_STATE=kstate,
                   CHAOS_PID_FILE=os.path.join(tmp, 'no.pid'), CHAOS_LOG=os.path.join(tmp, 'no.log'),
                   CHAOS_SITE_DIR=site, CHAOS_ENGINE_TOKEN_FILE=tfile, CHAOS_EB_WAIT='0',
                   GIT_CONFIG_GLOBAL='/dev/null', GIT_CONFIG_SYSTEM='/dev/null')
        for k in ('SUDO_USER', 'CHAOS_UNIT', 'CHAOS_ROOT', 'CHAOS_KIT_DIR', 'CHAOS_DB_SOCKET', 'CHAOS_BACKUP_DIR',
                  'CHAOS_UPDATE_BRANCH', 'CHAOS_RELEASE_REPO'):
            env.pop(k, None)
        seen = []

        def run(*args, stdin=None):
            r = subprocess.run(['bash', SCRIPT] + list(args), env=env, input=stdin, capture_output=True, text=True)
            seen.append(r.stdout + r.stderr)
            return r

        def calls():
            p = os.path.join(stub, 'calls')
            return open(p).read() if os.path.exists(p) else ''

        def dispatches():
            p = os.path.join(stub, 'dispatch.json')
            return [json.loads(x) for x in open(p).read().splitlines()] if os.path.exists(p) else []

        def kv(out):
            d = {}
            for line in out.splitlines():
                if line.startswith('@'):
                    break
                if '=' in line:
                    k, v = line.split('=', 1)
                    d.setdefault(k, v)
            return d

        # no token yet: start is refused before GitHub is asked anything, status reads the public runs
        r = run('engine-build', 'start')
        check(r.returncode != 0 and 'token-missing' in r.stderr and not dispatches(), 'start without a token: ' + r.stderr)
        st = kv(run('engine-build').stdout)
        check(st.get('token') == 'no' and st.get('state') == 'none' and st.get('client_build') == '30'
              and st.get('installed_release') == '100' and st.get('release_newer') == 'no', 'status without runs: %s' % st)

        # engine-build-token-set: one line on stdin, a real shape, checked at GitHub, kept mode 600, never echoed
        for bad in ('ghp_short', 'not a token', token + '$(id)', 'github_pat_' + 'x' * 5):
            r = run('engine-build-token-set', stdin=bad + '\n')
            check(r.returncode != 0 and not os.path.exists(tfile), 'token-set refuses %r' % bad)
            check(bad not in r.stdout + r.stderr or len(bad) < 12, 'token-set: a refused value is not echoed')
        r = run('engine-build-token-set', stdin=token + '\nsecond\n')
        check(r.returncode != 0 and not os.path.exists(tfile), 'token-set: a second line is refused')
        check(run('engine-build-token-set', token).returncode != 0 and not os.path.exists(tfile),
              'token-set: a value on the command line is no input')
        put('token.code', '401')
        r = run('engine-build-token-set', stdin=token + '\n')
        check(r.returncode != 0 and 'token-refused' in r.stderr and not os.path.exists(tfile), 'token-set: GitHub 401 saves nothing: ' + r.stderr)
        put('token.code', '404')
        r = run('engine-build-token-set', stdin=token + '\n')
        check(r.returncode != 0 and 'no-access' in r.stderr and not os.path.exists(tfile), 'token-set: GitHub 404 saves nothing')
        drop('token.code')
        r = run('engine-build-token-set', stdin='  ' + token + '  \r\n')
        check(r.returncode == 0 and 'saved' in r.stdout and open(tfile).read() == token + '\n', 'token-set saves: ' + r.stdout + r.stderr)
        check(stat.S_IMODE(os.stat(tfile).st_mode) == 0o600, 'token file is mode 600: %o' % os.stat(tfile).st_mode)
        check(not [n for n in os.listdir(os.path.dirname(tfile)) if n != 'engine-build.token'], 'token-set: no temp file left')
        check('Authorization: Bearer ' + token in open(os.path.join(stub, 'curl.stdin')).read(), 'the token reaches curl on its stdin')
        check(kv(run('engine-build').stdout).get('token') == 'yes', 'status: token=yes')

        # start: the dispatch body, the client build rule, the run found
        r = run('engine-build', 'start')
        kvs = kv(r.stdout)
        check(r.returncode == 0 and kvs.get('started') == 'yes' and kvs.get('client_build') == '30'
              and kvs.get('run_id') == '101' and kvs.get('commit') == base[:7], 'start: ' + r.stdout + r.stderr)
        check(dispatches() == [{'ref': 'main', 'inputs': {'client_build': '30', 'allow_dev_key': 'false'}}],
              'start: ref main, client_build the live 30, allow_dev_key false: %s' % dispatches())
        check('start branch=main commit=%s client_build=30 run=101' % base[:7] in open(os.path.join(kstate, 'engine-build', 'log')).read(), 'start: logged')
        # a second start while the run is queued or running: refused, nothing dispatched again
        for state in ('queued', 'in_progress'):
            set_run(state, run_id=101)
            r = run('engine-build', 'start')
            check(r.returncode != 0 and 'build-running' in r.stderr and len(dispatches()) == 1, 'second start refused (%s): %s' % (state, r.stderr))

        # status of a running build, with its jobs
        put('jobs.json', json.dumps({'jobs': [
            {'name': 'server', 'status': 'completed', 'conclusion': 'success', 'steps': []},
            {'name': 'engine-linux', 'status': 'in_progress', 'conclusion': None,
             'steps': [{'name': 'Build the engine', 'status': 'in_progress', 'conclusion': None}]},
            {'name': 'publish', 'status': 'queued', 'conclusion': None, 'steps': []}]}))
        set_run('in_progress', created='2026-11-08T10:00:00Z')
        st = kv(run('engine-build').stdout)
        check(st.get('state') == 'in_progress' and st.get('run_id') == '101' and st.get('run_number') == '101'
              and st.get('job') == 'engine-linux' and st.get('step') == 'Build the engine' and st.get('jobs_done') == '1/3'
              and st.get('release_newer') == 'no' and int(st.get('elapsed_s', '0')) > 0 and st.get('url', '').startswith('https://github.com/'),
              'status in progress: %s' % st)

        # success: the release exists with the engine and is newer than the installed one
        put('release.json', json.dumps({'assets': [{'name': 'CindersOfChaos-Server-Linux.tar.gz'}]}))
        set_run('completed', 'success')
        st = kv(run('engine-build').stdout)
        check(st.get('state') == 'success' and st.get('release_tag') == 'winpkg-101' and st.get('release_ready') == 'yes'
              and st.get('release_newer') == 'yes' and st.get('finished') == '2026-11-08T10:40:00Z' and st.get('elapsed_s') == '2400',
              'status success: %s' % st)
        check(st.get('client_next') == '31' and st.get('client_changed') == 'no', 'status: client_next 31, the client program unchanged: %s' % st)
        write_state(release=101)
        check(kv(run('engine-build').stdout).get('release_newer') == 'no', 'status: the installed release is this one: not newer')
        write_state(release=100)
        put('release.json', json.dumps({'assets': [{'name': 'other.zip'}]}))
        st = kv(run('engine-build').stdout)
        check(st.get('release_ready') == 'no' and st.get('release_newer') == 'no', 'status: a release without the engine is not ready')
        drop('release.json')
        st = kv(run('engine-build').stdout)
        check(st.get('release_ready') == 'no' and st.get('release_newer') == 'no', 'status: no release yet')

        # failure and cancelled: the failed job and step
        put('jobs.json', json.dumps({'jobs': [
            {'name': 'engine-linux', 'status': 'completed', 'conclusion': 'failure',
             'steps': [{'name': 'Checkout', 'status': 'completed', 'conclusion': 'success'},
                       {'name': 'Compile the engine', 'status': 'completed', 'conclusion': 'failure'}]}]}))
        set_run('completed', 'failure')
        out = run('engine-build', 'log').stdout
        st = kv(out)
        check(st.get('state') == 'failure' and st.get('failed_job') == 'engine-linux' and st.get('failed_step') == 'Compile the engine'
              and st.get('release_newer') == 'no', 'status failure: %s' % st)
        check('@jobs' in out and 'engine-linux: failure' in out and 'step Compile the engine: failure' in out and '@history' in out
              and 'client_build=30' in out, 'log: jobs, failed step, history: ' + out)
        set_run('completed', 'cancelled')
        check(kv(run('engine-build').stdout).get('state') == 'failure', 'status: cancelled counts as failure (conclusion shows it)')
        check(kv(run('engine-build').stdout).get('conclusion') == 'cancelled', 'status: conclusion cancelled')

        # API trouble: state unknown, an error line, exit 1; refused start
        put('runs.code', '401')
        r = run('engine-build')
        check(r.returncode == 1 and kv(r.stdout).get('state') == 'unknown' and 'token-refused' in r.stdout, 'status 401: ' + r.stdout)
        put('runs.code', '500')
        r = run('engine-build', 'start')
        check(r.returncode != 0 and 'github-unreachable' in r.stderr and len(dispatches()) == 1, 'start with GitHub down: ' + r.stderr)
        drop('runs.code')

        # the client build rule
        n0 = len(dispatches())
        r = run('engine-build', 'start', '--client-build', '29')
        check(r.returncode != 0 and 'client-build-backwards' in r.stderr and len(dispatches()) == n0, 'a build number never goes backwards: ' + r.stderr)
        check(run('engine-build', 'start', '--client-build', '0').returncode != 0 and run('engine-build', 'start', '--client-build', '70000').returncode != 0
              and len(dispatches()) == n0, 'client build out of range refused')
        check(run('engine-build', 'start', '--client-build', 'x').returncode != 0 and run('engine-build', 'start', 'now').returncode != 0
              and len(dispatches()) == n0, 'bad start arguments refused')
        # a server-only change since the live client: the same number is fine
        open(os.path.join(work, 'server', 'src-patches', '0090-more.patch'), 'w').write('b\n')
        git(work, 'add', '-A')
        git(work, 'commit', '-q', '-m', 'server patch')
        git(work, 'push', '-q', 'origin', 'main')
        set_run('completed', 'success')
        r = run('engine-build', 'start')
        check(r.returncode == 0 and dispatches()[-1]['inputs']['client_build'] == '30', 'a server-only change keeps the live number: ' + r.stdout + r.stderr)
        # a client program change since the live client: the same number is refused, nothing dispatched
        open(os.path.join(work, 'client', 'base-patches', '0002-b.patch'), 'w').write('c\n')
        git(work, 'add', '-A')
        git(work, 'commit', '-q', '-m', 'client patch')
        git(work, 'push', '-q', 'origin', 'main')
        client_head = git(work, 'rev-parse', 'HEAD')
        set_run('completed', 'success', run_id=102, number=102)
        n0 = len(dispatches())
        r = run('engine-build', 'start')
        check(r.returncode != 0 and 'client-changed' in r.stderr and '--new-client' in r.stderr and len(dispatches()) == n0,
              'a changed client program refuses the live number: ' + r.stderr)
        st = kv(run('engine-build').stdout)
        check(st.get('client_changed') == 'yes' and st.get('client_next') == '31', 'status says the client program changed and the next number: %s' % st)
        # a running build is not asked about the client (no fetch while the app polls)
        set_run('in_progress', run_id=102, number=102)
        st = kv(run('engine-build').stdout)
        check('client_changed' not in st and st.get('client_next') == '31', 'status while running: client_next only: %s' % st)
        set_run('completed', 'success', run_id=102, number=102)
        # the new number with --new-client: live + 1, built, and put into clientGuardBuilds (old builds stay)
        os.makedirs(os.path.join(tmp, 'server'))
        cfg = os.path.join(tmp, 'server', 'config.lua')
        with open(cfg, 'w') as f:
            f.write('ip = "x"\nclientGuardMode = "enforce"\nclientGuardBuilds = "29, 30"\nclientGuardManifest = ""\n')
        # the kit update running: refused, nothing dispatched, nothing edited
        os.makedirs(kstate, exist_ok=True)
        import fcntl
        lockf = open(os.path.join(kstate, '.lock'), 'w')
        fcntl.flock(lockf, fcntl.LOCK_EX)
        r = run('engine-build', 'start', '--new-client')
        check(r.returncode != 0 and 'update-running' in r.stderr and len(dispatches()) == n0 and '31' not in open(cfg).read(),
              'a new number waits for a running kit update: ' + r.stderr)
        fcntl.flock(lockf, fcntl.LOCK_UN)
        lockf.close()
        check(run('engine-build', 'start', '--new-client', '--client-build', '31').returncode != 0 and len(dispatches()) == n0,
              '--new-client and --client-build together are refused')
        r = run('engine-build', 'start', '--new-client')
        check(r.returncode == 0 and dispatches()[-1]['inputs']['client_build'] == '31' and 'new_client=yes' in r.stdout
              and 'guard=added' in r.stdout and 'APK' in r.stdout, 'new client: ' + r.stdout + r.stderr)
        check('clientGuardBuilds = "29, 30, 31"' in open(cfg).read() and 'clientGuardMode = "enforce"' in open(cfg).read()
              and [n for n in os.listdir(os.path.dirname(cfg)) if n.startswith('config.lua.before-guard-')],
              'the guard list got 31, old builds stay, a backup was kept: ' + open(cfg).read())
        set_run('completed', 'success', run_id=103, number=103)
        n0 = len(dispatches())
        r = run('engine-build', 'start', '--client-build', '31')
        check(r.returncode == 0 and 'guard=present' in r.stdout and open(cfg).read().count('31') == 1,
              'a second start of 31 changes nothing in the list: ' + r.stdout + r.stderr)
        # an empty list accepts every build; a missing line is told
        with open(cfg, 'w') as f:
            f.write('clientGuardBuilds = ""\n')
        set_run('completed', 'success', run_id=104, number=104)
        check('guard=any' in run('engine-build', 'start', '--client-build', '31').stdout, 'an empty guard list is left alone')
        with open(cfg, 'w') as f:
            f.write('ip = "x"\n')
        set_run('completed', 'success', run_id=105, number=105)
        r = run('engine-build', 'start', '--client-build', '31')
        check('guard=missing' in r.stdout and 'by hand' in r.stdout and r.returncode == 0, 'no guard line: told to add it by hand: ' + r.stdout)
        os.remove(cfg)
        set_run('completed', 'success', run_id=106, number=106)
        check('guard=missing' in run('engine-build', 'start', '--client-build', '31').stdout, 'no config.lua: told')
        n0 = len(dispatches())
        set_run('completed', 'success', run_id=103, number=103)
        pend = os.path.join(kstate, 'engine-build', 'pending_client')
        check(open(pend).read().split() == ['31', client_head], 'the new number waits as pending until it is live')
        set_run('completed', 'success', run_id=103, number=103)
        r = run('engine-build', 'start')
        check(r.returncode != 0 and 'client-changed' in r.stderr, 'while 31 is not live the baseline stays: ' + r.stderr)
        check(open(pend).read().split()[0] == '31', 'the pending number is still 31')
        write_manifest(31)
        r = run('engine-build', 'start')
        check(r.returncode == 0 and dispatches()[-1]['inputs']['client_build'] == '31' and not os.path.exists(pend)
              and open(os.path.join(kstate, 'engine-build', 'client_exe_commit')).read().strip() == client_head,
              '31 live: the pending commit is the new baseline, the same number is fine again: ' + r.stdout + r.stderr)
        # no live client update: the number must be given
        os.remove(os.path.join(site, 'updates', 'live', 'manifest.json'))
        set_run('completed', 'success', run_id=104, number=104)
        n0 = len(dispatches())
        r = run('engine-build', 'start')
        check(r.returncode != 0 and 'client-build-unknown' in r.stderr and len(dispatches()) == n0, 'no live client: the number is required: ' + r.stderr)
        # no commit to compare with
        write_manifest(31)
        os.remove(os.path.join(kstate, 'state'))
        os.remove(os.path.join(kstate, 'engine-build', 'client_exe_commit'))
        r = run('engine-build', 'start')
        check(r.returncode != 0 and 'client-check-failed' in r.stderr and len(dispatches()) == n0, 'no baseline commit refuses: ' + r.stderr)
        write_state(commit=client_head)
        # GitHub refuses the dispatch
        for code, word in (('403', 'no-access'), ('422', 'workflow-refused'), ('401', 'token-refused'), ('500', 'dispatch-failed')):
            put('dispatch.code', code)
            r = run('engine-build', 'start')
            check(r.returncode != 0 and word in r.stderr and len(dispatches()) == n0 + (['403', '422', '401', '500'].index(code) + 1),
                  'dispatch %s -> %s: %s' % (code, word, r.stderr))
        drop('dispatch.code')
        # a hand-edited token file that is no token is never sent
        with open(tfile, 'w') as f:
            f.write('x"\nheader = "Evil: 1\n')
        r = run('engine-build', 'start')
        check(r.returncode != 0 and 'token-missing' in r.stderr, 'a file that is no token counts as no token: ' + r.stderr)
        check('Evil' not in open(os.path.join(stub, 'curl.stdin')).read(), 'its text never reached curl')
        # removing the token
        r = run('engine-build-token-set', stdin='\n')
        check(r.returncode == 0 and not os.path.exists(tfile) and 'removed' in r.stdout, 'token-set with nothing removes the file')

        # the token is in no output and in no process argument, ever
        check(not any(token in t or token[11:] in t for t in seen), 'no output of any engine-build command holds the token')
        check(token[11:] not in calls() and 'Bearer' not in calls() and 'github_pat' not in calls(), 'the token is never on a command line')
        check(run('engine-build', 'frobnicate').returncode != 0, 'engine-build: an unknown subcommand is refused')


def test_github_private():
    """github-token-set | github-token-status, admin-desktop-releases | admin-desktop-asset-url (O530, a private repository)"""
    token = 'github_pat_11ABCDEFG0aBcDeFgHiJkL_mNoPqRsTuVwXyZ0123456789aBcDeFgHiJkLmNoPqRsTuVwXyZ01234'
    # curl: a fake api.github.com. A private repository answers 404 to a call without the Authorization line.
    curl = '''#!/usr/bin/env python3
import json, os, re, sys
stub = os.environ['STUB']
args = sys.argv[1:]
cfg = sys.stdin.read() if '-K' in args else ''
open(os.path.join(stub, 'calls'), 'a').write('curl ' + ' '.join(args) + '\\n')
open(os.path.join(stub, 'curl.stdin'), 'a').write(cfg + '\\n--\\n')
out = args[args.index('-o') + 1] if '-o' in args else None
url = re.search(r'url = "([^"]+)"', cfg).group(1)
def read(name, default=''):
    p = os.path.join(stub, name)
    return open(p).read() if os.path.exists(p) else default
def answer(code, body=''):
    if out and out != '/dev/null':
        open(out, 'w').write(body)
    sys.stdout.write(str(code))
    sys.exit(0)
private = os.path.exists(os.path.join(stub, 'private'))
authed = 'Authorization: Bearer ' in cfg
if private and not authed:
    answer(404, '{}')
if re.search(r'/repos/o/r$', url):
    answer(read('repo.code', '200').strip(), '{}')
if re.search(r'/repos/o/r/branches/main$', url):
    answer(read('contents.code', '200').strip(), '{}')
if re.search(r'/actions/workflows/windows-package\\.yml$', url):
    answer(read('actions.code', '200').strip(), '{}')
if re.search(r'/repos/o/r/releases\\?per_page=\\d+$', url):
    answer(read('rel.code', '200').strip(), read('releases.json', '[]'))
m = re.search(r'/repos/o/r/releases/tags/(.+)$', url)
if m:
    for r in json.loads(read('releases.json', '[]')):
        if r['tag_name'] == m.group(1):
            answer(200, json.dumps(r))
    answer(404, '{}')
m = re.search(r'/repos/o/r/releases/assets/(\\d+)$', url)
if m:
    sys.stdout.write('302 https://objects.example.org/signed/' + m.group(1) + '?sig=SIGNED')
    sys.exit(0)
answer(404)
'''
    with tempfile.TemporaryDirectory() as tmp:
        stub = os.path.join(tmp, 'stub')
        os.makedirs(stub)
        p = os.path.join(stub, 'curl')
        with open(p, 'w') as f:
            f.write(curl)
        os.chmod(p, 0o755)
        tfile = os.path.join(tmp, 'etc', 'github.token')
        env = dict(os.environ, PATH=stub + ':' + os.environ['PATH'], STUB=stub, CHAOS_CTL_NO_SUDO='1',
                   CHAOS_SERVER_DIR=os.path.join(tmp, 'server'), CHAOS_ENV=os.path.join(tmp, 'chaos.env'),
                   CHAOS_REPO=os.path.join(tmp, 'repo'), CHAOS_CTL_CONF=os.path.join(tmp, 'none.conf'),
                   CHAOS_KIT_STATE=os.path.join(tmp, 'kit-state'), CHAOS_PID_FILE=os.path.join(tmp, 'no.pid'),
                   CHAOS_LOG=os.path.join(tmp, 'no.log'), CHAOS_SITE_DIR=os.path.join(tmp, 'site'),
                   CHAOS_GITHUB_TOKEN_FILE=tfile, CHAOS_RELEASE_REPO='o/r', GIT_CONFIG_GLOBAL='/dev/null',
                   GIT_CONFIG_SYSTEM='/dev/null')
        for k in ('SUDO_USER', 'CHAOS_UNIT', 'CHAOS_ROOT', 'CHAOS_KIT_DIR', 'CHAOS_DB_SOCKET', 'CHAOS_BACKUP_DIR',
                  'CHAOS_UPDATE_BRANCH', 'CHAOS_ENGINE_TOKEN_FILE'):
            env.pop(k, None)
        seen = []

        def run(*args, stdin=None, extra=None):
            r = subprocess.run(['bash', SCRIPT] + list(args), env=dict(env, **(extra or {})), input=stdin,
                               capture_output=True, text=True)
            seen.append(r.stdout + r.stderr)
            return r

        def put(name, text):
            with open(os.path.join(stub, name), 'w') as f:
                f.write(text)

        def drop(name):
            if os.path.exists(os.path.join(stub, name)):
                os.remove(os.path.join(stub, name))

        def kv(out):
            d = {}
            for line in out.splitlines():
                if '=' in line:
                    k, v = line.split('=', 1)
                    d.setdefault(k, v)
            return d

        def calls():
            p = os.path.join(stub, 'calls')
            return open(p).read() if os.path.exists(p) else ''

        # a public repository: nothing is needed
        st = kv(run('github-token-status').stdout)
        check(st.get('token') == 'no' and st.get('private') == 'no' and st.get('ready') == 'yes' and st.get('contents') == 'none',
              'status, public repository, no token: %s' % st)
        # the repository turns private
        put('private', '')
        r = run('github-token-status')
        st = kv(r.stdout)
        check(r.returncode == 0 and st.get('private') == 'yes' and st.get('ready') == 'no' and st.get('error', '').startswith('private-repo:')
              and 'github-token-set' in st.get('error', ''), 'status, private repository, no token: ' + r.stdout)
        # the admin app's questions get the word the app translates
        r = run('admin-desktop-releases')
        check(r.returncode != 0 and 'chaos-ctl: private-repo:' in r.stderr, 'admin-desktop-releases without a token: ' + r.stderr)
        r = run('admin-desktop-asset-url', 'admin-desktop-v0.4.2', 'cinders-admin.exe')
        check(r.returncode != 0 and 'private-repo' in r.stderr, 'admin-desktop-asset-url without a token: ' + r.stderr)
        r = run('engine-build')
        check(r.returncode == 1 and 'error=private-repo:' in r.stdout, 'engine-build status without a token on a private repository: ' + r.stdout)

        # github-token-set: one line on stdin, a real shape, Contents checked before it is kept
        for bad in ('ghp_short', 'not a token', token + '$(id)', 'github_pat_xx'):
            r = run('github-token-set', stdin=bad + '\n')
            check(r.returncode != 0 and not os.path.exists(tfile), 'github-token-set refuses %r' % bad)
        r = run('github-token-set', stdin=token + '\nsecond\n')
        check(r.returncode != 0 and not os.path.exists(tfile), 'a second line is refused')
        check(run('github-token-set', token).returncode != 0 and not os.path.exists(tfile), 'a value on the command line is no input')
        put('contents.code', '401')
        r = run('github-token-set', stdin=token + '\n')
        check(r.returncode != 0 and 'token-refused' in r.stderr and not os.path.exists(tfile), 'Contents 401 saves nothing: ' + r.stderr)
        put('contents.code', '404')
        r = run('github-token-set', stdin=token + '\n')
        check(r.returncode != 0 and 'no-access' in r.stderr and 'Contents read' in r.stderr and not os.path.exists(tfile),
              'Contents 404 saves nothing: ' + r.stderr)
        drop('contents.code')
        put('actions.code', '403')
        r = run('github-token-set', stdin='  ' + token + '  \r\n')
        check(r.returncode == 0 and open(tfile).read() == token + '\n' and 'Contents: ok' in r.stdout
              and 'Actions: no access' in r.stdout, 'a token without Actions is kept for the updates: ' + r.stdout + r.stderr)
        drop('actions.code')
        check(stat.S_IMODE(os.stat(tfile).st_mode) == 0o600, 'the token file is mode 600')
        r = run('github-token-set', stdin=token + '\n')
        check(r.returncode == 0 and 'Contents: ok. Actions: ok' in r.stdout, 'saved with both: ' + r.stdout)
        check('Authorization: Bearer ' + token in open(os.path.join(stub, 'curl.stdin')).read(), 'the token reaches curl on its stdin')
        st = kv(run('github-token-status').stdout)
        check(st.get('token') == 'yes' and st.get('private') == 'yes' and st.get('contents') == 'ok' and st.get('actions') == 'ok'
              and st.get('ready') == 'yes' and 'error' not in st, 'status with the token: %s' % st)
        put('contents.code', '404')
        st = kv(run('github-token-status').stdout)
        check(st.get('contents') == 'no-access' and st.get('ready') == 'no' and st.get('error', '').startswith('no-access:'),
              'status: a token that lost the repository: %s' % st)
        drop('contents.code')

        # the releases for the desktop app, through the token
        rels = [
            {'tag_name': 'winpkg-900', 'draft': False, 'assets': [{'id': 1, 'name': 'CindersOfChaos-Server-Linux.tar.gz', 'size': 5}]},
            {'tag_name': 'admin-desktop-v0.4.2', 'draft': False, 'assets': [
                {'id': 11, 'name': 'cinders-admin.exe', 'size': 100, 'browser_download_url': 'https://github.com/x/y'},
                {'id': 12, 'name': 'cinders-admin.exe.sig', 'size': 90}, {'id': 13, 'name': 'other.bin', 'size': 1}]},
            {'tag_name': 'admin-desktop-v0.5.0', 'draft': True, 'assets': []},
            {'tag_name': 'admin-desktop-v$(id)', 'draft': False, 'assets': []}]
        put('releases.json', json.dumps(rels))
        r = run('admin-desktop-releases')
        got = json.loads(r.stdout) if r.returncode == 0 else None
        check(got == [{'tag_name': 'admin-desktop-v0.4.2', 'draft': False, 'assets': [
            {'name': 'cinders-admin.exe', 'size': 100}, {'name': 'cinders-admin.exe.sig', 'size': 90}]},
            {'tag_name': 'admin-desktop-v0.5.0', 'draft': True, 'assets': []}],
              'admin-desktop-releases: only the admin-desktop releases, names and sizes, no addresses: ' + r.stdout + r.stderr)
        put('rel.code', '500')
        r = run('admin-desktop-releases')
        check(r.returncode != 0 and 'github-unreachable' in r.stderr, 'GitHub down: ' + r.stderr)
        drop('rel.code')
        check(run('admin-desktop-releases', 'x').returncode != 0, 'admin-desktop-releases takes no argument')

        # the signed address of one asset
        r = run('admin-desktop-asset-url', 'admin-desktop-v0.4.2', 'cinders-admin.exe.sig')
        check(r.returncode == 0 and r.stdout == 'https://objects.example.org/signed/12?sig=SIGNED\n', 'admin-desktop-asset-url: ' + r.stdout + r.stderr)
        cfgs = [c for c in open(os.path.join(stub, 'curl.stdin')).read().split('\n--\n') if 'releases/assets/12' in c]
        check(cfgs and 'Accept: application/octet-stream' in cfgs[0] and 'Authorization: Bearer ' + token in cfgs[0],
              'the asset question asks for the octet-stream with the token')
        r = run('admin-desktop-asset-url', 'admin-desktop-v0.4.2', 'other.bin')
        check(r.returncode != 0, 'a file that is not a cinders-admin file is refused')
        r = run('admin-desktop-asset-url', 'admin-desktop-v0.4.2', 'cinders-admin.zip')
        check(r.returncode != 0 and 'no-asset' in r.stderr, 'an asset the release lacks: ' + r.stderr)
        r = run('admin-desktop-asset-url', 'winpkg-900', 'cinders-admin.exe')
        check(r.returncode != 0 and 'admin-desktop-v' in r.stderr, 'only an admin-desktop tag')
        r = run('admin-desktop-asset-url', 'admin-desktop-v9.9.9', 'cinders-admin.exe')
        check(r.returncode != 0 and 'no-release' in r.stderr, 'a release that does not exist: ' + r.stderr)
        check(run('admin-desktop-asset-url', 'admin-desktop-v0.4.2').returncode != 0, 'two arguments are needed')

        # the old name writes the same file; the legacy setting still names the file
        os.remove(tfile)
        put('actions.code', '200')
        r = run('engine-build-token-set', stdin=token + '\n')
        check(r.returncode == 0 and open(tfile).read() == token + '\n', 'engine-build-token-set keeps the same token file: ' + r.stdout + r.stderr)
        legacy = os.path.join(tmp, 'etc', 'engine-build.token')
        r = run('github-token-set', stdin=token + '\n', extra={'CHAOS_GITHUB_TOKEN_FILE': '', 'CHAOS_ENGINE_TOKEN_FILE': legacy})
        check(r.returncode == 0 and os.path.exists(legacy), 'CHAOS_ENGINE_TOKEN_FILE still names the file: ' + r.stdout + r.stderr)

        # removing the token
        r = run('github-token-set', stdin='\n')
        check(r.returncode == 0 and not os.path.exists(tfile) and 'removed' in r.stdout, 'an empty line removes the file')
        st = kv(run('github-token-status').stdout)
        check(st.get('token') == 'no' and st.get('ready') == 'no', 'status after removing: %s' % st)

        # never in an output, never on a command line
        check(not any(token in t or token[11:] in t for t in seen), 'no output holds the token')
        check(token[11:] not in calls() and 'Bearer' not in calls(), 'the token is never on a command line')


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
        for f in ('bot.py', 'bot_core.py', 'claude_client.py', 'changes_export.py', 'requirements.txt', '.env.example'):
            shutil.copy(os.path.join(HERE, 'discord_bot', f), bsrc)
        for f in ('chaos-discordbot.service', 'chaos-discordbot-sync.service', 'chaos-discordbot-sync.timer',
                  'chaos.logrotate'):
            shutil.copy(os.path.join(HERE, f), os.path.join(repo, 'server', 'deploy', f))
        # a git checkout (O385): the game's changes come from its history; a docs commit and merges are left out
        top = os.path.dirname(os.path.dirname(HERE))
        os.makedirs(os.path.join(repo, 'server', 'tools'))
        os.makedirs(os.path.join(repo, 'tools', 'ci'))
        shutil.copy(os.path.join(top, 'server', 'tools', 'gen_changelog.py'), os.path.join(repo, 'server', 'tools'))
        shutil.copy(os.path.join(top, 'tools', 'ci', 'check_names.py'), os.path.join(repo, 'tools', 'ci'))
        genv = dict(os.environ, GIT_AUTHOR_NAME='t', GIT_AUTHOR_EMAIL='t@example.org', GIT_COMMITTER_NAME='t',
                    GIT_COMMITTER_EMAIL='t@example.org', GIT_CONFIG_NOSYSTEM='1', HOME=tmp)

        def git(*a):
            return subprocess.run(['git', '-C', repo] + list(a), env=genv, capture_output=True, text=True,
                                  check=True).stdout.strip()

        def gcommit(path, msg):
            full = os.path.join(repo, path)
            os.makedirs(os.path.dirname(full), exist_ok=True)
            with open(full, 'a') as f:
                f.write(msg + '\n')
            git('add', '-A')
            git('commit', '-q', '-m', msg)

        git('init', '-q', '-b', 'main')
        gcommit('README.md', 'Start')
        gcommit('server/data/monster/dragon.xml', 'Dragons in the north (O999)\n\nThey guard the pass in '
                'server/data/monster/dragon.xml and drop scales.\n\nCo-Authored-By: someone')
        gcommit('docs/NOTES.md', 'Docs: a note')
        git('checkout', '-q', '-b', 'side')
        gcommit('client/overlay/modules/game_x/x.lua', 'Bigger bag window')
        git('checkout', '-q', 'main')
        gcommit('server/data/items/items.xml', 'Health potions heal more')
        git('merge', '-q', '--no-ff', '-m', 'Merge pull request #1 from side', 'side')
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

        # O385: the sync unit and timer with the real paths, enabled; changes.json written at once
        sunit = open(os.path.join(sysd, 'chaos-discordbot-sync.service')).read()
        check(botdir + '/app/changes_export.py sync --repo ' + repo + ' --data ' + data + ' --server-data '
              + server + '/data' in sunit and 'ReadWritePaths=%s -%s/data/patchnotes %s' % (data, server, os.path.dirname(blog))
              in sunit and 'append:%s/discord-bot-sync.log' % os.path.dirname(blog) in sunit
              and '/opt/chaos' not in sunit and '/var/lib/chaos' not in sunit, 'the sync unit gets the paths: ' + sunit)
        check(os.path.exists(os.path.join(sysd, 'chaos-discordbot-sync.timer'))
              and 'systemctl enable --now chaos-discordbot-sync.timer' in c, 'the sync timer is installed and started')
        check(os.path.exists(os.path.join(botdir, 'app', 'changes_export.py')), 'install copies changes_export.py')
        check(os.path.isdir(os.path.join(server, 'data', 'patchnotes')), 'install makes SERVER/data/patchnotes')
        cpath = os.path.join(data, 'changes.json')
        check('changes: 3 game changes' in r.stdout, 'install runs the first sync: ' + r.stdout + r.stderr)
        ch = json.load(open(cpath, encoding='utf-8'))
        subjects = [x['subject'] for x in ch['commits']]
        check(sorted(subjects) == ['Bigger bag window', 'Dragons in the north', 'Health potions heal more'],
              'changes: game commits only, no docs, no merge, roadmap id cut: %s' % subjects)
        dragon = [x for x in ch['commits'] if x['subject'] == 'Dragons in the north'][0]
        check(dragon['body'] == 'They guard the pass in and drop scales.' and dragon['tags'] == ['content']
              and ch['head'] == git('rev-parse', 'HEAD'), 'changes: body without paths or trailers, head: %s' % dragon)
        st = os.stat(cpath)
        check(stat.S_IMODE(st.st_mode) == 0o640 and (st.st_uid, st.st_gid) == (os.stat(data).st_uid, os.stat(data).st_gid),
              'changes.json: mode 640, owner of the data dir')
        mtime = os.stat(cpath).st_mtime_ns

        # idempotent: nothing is redone, a changed file is copied
        open(os.path.join(stub, 'calls'), 'w').close()
        r = run('install')
        c = calls()
        check(r.returncode == 0 and 'requirements: already installed' in r.stdout and 'unit: already installed' in r.stdout
              and 'pip install' not in c and '-m venv' not in c and 'restart' not in c, 'install twice changes nothing: ' + r.stdout + c)
        check('sync timer: already installed' in r.stdout and 'daemon-reload' not in c
              and 'changes: 3 game changes (unchanged)' in r.stdout and os.stat(cpath).st_mtime_ns == mtime,
              'install twice: the sync unit and changes.json stay as they are: ' + r.stdout)
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
        check('not running' in r.stdout and 'restarted' not in r.stdout, 'set: a stopped bot is not started: ' + r.stdout)
        open(os.path.join(stub, 'active'), 'w').close()
        open(os.path.join(stub, 'calls'), 'w').close()
        r = run('set', 'DISCORD_BUGS_CHANNEL_ID', stdin='1567178340434059494\n')
        check(r.returncode == 0 and 'systemctl restart chaos-discordbot' in calls() and 'restarted' in r.stdout,
              'set: a running bot restarts with the new setting: ' + r.stdout + r.stderr)
        os.remove(os.path.join(stub, 'active'))
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
        check(kvs(run('status')).get('patch_auto') == 'publish', 'patch_auto defaults to publish in status')
        for v in ('publish', 'off', 'preview'):
            check(run('set', 'DISCORD_BOT_PATCH_AUTO', stdin=v + '\n').returncode == 0
                  and kvs(run('status')).get('patch_auto') == v, 'DISCORD_BOT_PATCH_AUTO ' + v)
        for bad in ('auto', 'Publish', 'publish now', 'on'):
            check(run('set', 'DISCORD_BOT_PATCH_AUTO', stdin=bad + '\n').returncode != 0, 'DISCORD_BOT_PATCH_AUTO refuses ' + bad)
        k = kvs(run('status'))
        check(k.get('changes_file', 'missing') != 'missing' and 'sync_timer' in k, 'status: changes file and sync timer')
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
        gcommit('server/data/spells/spells.xml', 'Fireball hits harder')
        r = run('patchnotes')
        check('changes: 4 game changes' in r.stdout and json.load(open(cpath))['commits'][0]['subject'] == 'Fireball hits harder',
              'patchnotes refreshes changes.json after a new commit: ' + r.stdout + r.stderr)
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



TZ_TIMEDATECTL = '''#!/usr/bin/env bash
echo "timedatectl $*" >> "$STUB/calls"
case "$*" in
  "show -p Timezone --value") cat "$STUB/tz" 2>/dev/null ;;
  "set-timezone "*) printf '%s\\n' "$2" > "$STUB/tz" ;;
  status) echo "                Time zone: $(cat "$STUB/tz" 2>/dev/null) (XXX, +0000)" ;;
esac
'''


def test_timezone():
    """chaos-ctl.sh timezone [set] (O439): the decision of server/tools/chaos_timezone.py with a fake timedatectl; TZ is
    the process zone the offset comes from (BRT3 = UTC-3, UTC0 = UTC); nothing here touches the real zone."""
    repo_root = os.path.dirname(os.path.dirname(HERE))
    with tempfile.TemporaryDirectory() as tmp:
        stub = os.path.join(tmp, 'stub')
        repo = os.path.join(tmp, 'repo')
        os.makedirs(stub)
        os.makedirs(os.path.join(repo, 'server', 'tools'))
        shutil.copy(os.path.join(repo_root, 'server', 'tools', 'chaos_timezone.py'), os.path.join(repo, 'server', 'tools'))
        for name, body in (('systemctl', SYSTEMCTL), ('timedatectl', TZ_TIMEDATECTL)):
            p = os.path.join(stub, name)
            with open(p, 'w') as f:
                f.write(body)
            os.chmod(p, 0o755)
        env_file = os.path.join(tmp, 'chaos.env')
        with open(env_file, 'w') as f:
            f.write('CHAOS_DB_USER=chaos\n')
        none = os.path.join(tmp, 'none')
        env = dict(os.environ, PATH=stub + ':' + os.environ['PATH'], STUB=stub, CHAOS_CTL_NO_SUDO='1',
                   CHAOS_SERVER_DIR=os.path.join(tmp, 'server'), CHAOS_ENV=env_file, CHAOS_REPO=repo,
                   CHAOS_CTL_CONF=os.path.join(tmp, 'none.conf'), CHAOS_PID_FILE=os.path.join(tmp, 'no.pid'),
                   CHAOS_LOG=os.path.join(tmp, 'no.log'), CHAOS_TZ_ETC_TIMEZONE=none, CHAOS_TZ_LOCALTIME=none, TZ='UTC0')
        for k in ('SUDO_USER', 'CHAOS_UNIT', 'CHAOS_ROOT', 'CHAOS_KIT_DIR', 'CHAOS_TIMEZONE'):
            env.pop(k, None)

        def run(*args, extra=None):
            return subprocess.run(['bash', SCRIPT] + list(args), env=dict(env, **(extra or {})), capture_output=True,
                                  text=True, timeout=60)

        def calls():
            p = os.path.join(stub, 'calls')
            return open(p).read() if os.path.exists(p) else ''

        def setzone(name):
            with open(os.path.join(stub, 'tz'), 'w') as f:
                f.write(name + '\n')

        def kv(r):
            return dict(l.split('=', 1) for l in r.stdout.splitlines() if '=' in l)

        # a machine left in UTC: WRONG, exit 1, the zone, the offset, the expected zone and the fix
        setzone('Etc/UTC')
        r = run('timezone')
        d = kv(r)
        check(r.returncode == 1 and d.get('result') == 'WRONG', 'timezone: UTC is WRONG with exit 1: ' + r.stdout + r.stderr)
        check(d.get('zone') == 'Etc/UTC' and d.get('utc_offset') == '+00:00' and d.get('expected_zone') == 'America/Sao_Paulo'
              and d.get('expected_offset') == '-03:00', 'timezone: zone, offset and expected zone: ' + r.stdout)
        check(re.fullmatch(r'\d{4}-\d\d-\d\d \d\d:\d\d:\d\d', d.get('local_time', '')) is not None,
              'timezone: the local time: ' + r.stdout)
        check('chaos-ctl.sh timezone set' in d.get('detail', '') and 'restart' in d.get('detail', ''),
              'timezone: the detail names the fix')
        check('set-timezone' not in calls(), 'timezone: reading never sets anything')
        # the right zone and offset
        setzone('America/Sao_Paulo')
        r = run('timezone', extra={'TZ': 'BRT3'})
        d = kv(r)
        check(r.returncode == 0 and d.get('result') == 'OK' and d.get('utc_offset') == '-03:00'
              and d.get('zone') == 'America/Sao_Paulo', 'timezone: Sao Paulo is OK: ' + r.stdout + r.stderr)
        # a stale name with the wrong offset, and the right offset under another name: both WRONG
        check(run('timezone', extra={'TZ': 'UTC0'}).returncode == 1, 'timezone: the right name with the wrong offset is WRONG')
        setzone('Etc/UTC')
        check(run('timezone', extra={'TZ': 'BRT3'}).returncode == 1, 'timezone: the right offset under the wrong name is WRONG')
        # /etc/timezone and the /etc/localtime link are read too
        with open(os.path.join(tmp, 'etc-timezone'), 'w') as f:
            f.write('America/Sao_Paulo\n')
        setzone('')
        r = run('timezone', extra={'TZ': 'BRT3', 'CHAOS_TZ_ETC_TIMEZONE': os.path.join(tmp, 'etc-timezone')})
        check(r.returncode == 0 and kv(r).get('zone') == 'America/Sao_Paulo', 'timezone: /etc/timezone is read: ' + r.stdout)
        link = os.path.join(tmp, 'localtime')
        os.symlink('../usr/share/zoneinfo/America/Sao_Paulo', link)
        r = run('timezone', extra={'TZ': 'BRT3', 'CHAOS_TZ_LOCALTIME': link})
        check(r.returncode == 0 and kv(r).get('zone') == 'America/Sao_Paulo',
              'timezone: the /etc/localtime link is read: ' + r.stdout)

        # set: timedatectl set-timezone, the result, the restart note, never a restart
        open(os.path.join(stub, 'calls'), 'w').close()
        setzone('Etc/UTC')
        r = run('timezone', 'set', extra={'TZ': 'BRT3'})
        d = kv(r)
        check(r.returncode == 0 and 'timedatectl set-timezone America/Sao_Paulo' in calls(),
              'timezone set: sets the expected zone: ' + r.stdout + r.stderr + calls())
        check(d.get('timezone_set') == 'America/Sao_Paulo' and d.get('result') == 'OK' and d.get('zone') == 'America/Sao_Paulo',
              'timezone set: prints the result: ' + r.stdout)
        check(d.get('restart_needed') == 'yes' and 'restart' in d.get('note', '') and 'Painel > Servidor' in d.get('note', '')
              and 'Nothing was restarted' in d.get('note', ''), 'timezone set: says the game server must be restarted: ' + r.stdout)
        check('restart' not in calls().replace('set-timezone', '') and 'kill' not in calls(),
              'timezone set: never restarts by itself: ' + calls())
        # still wrong after the set (here: the process zone is UTC): exit 1, but the set was done and the note is there
        setzone('Etc/UTC')
        r = run('timezone', 'set', extra={'TZ': 'UTC0'})
        check(r.returncode == 1 and kv(r).get('result') == 'WRONG' and kv(r).get('restart_needed') == 'yes',
              'timezone set: exit 1 when the zone is still wrong: ' + r.stdout)
        # CHAOS_TIMEZONE of the env file is the expected zone
        with open(env_file, 'a') as f:
            f.write('CHAOS_TIMEZONE=Europe/Lisbon\n')
        open(os.path.join(stub, 'calls'), 'w').close()
        r = run('timezone', 'set', extra={'TZ': 'UTC0'})
        check('timedatectl set-timezone Europe/Lisbon' in calls() and kv(r).get('expected_zone') == 'Europe/Lisbon',
              'timezone set: CHAOS_TIMEZONE of the env file: ' + r.stdout + calls())
        with open(env_file, 'w') as f:
            f.write('CHAOS_DB_USER=chaos\nCHAOS_TIMEZONE="a b;id"\n')
        open(os.path.join(stub, 'calls'), 'w').close()
        r = run('timezone', 'set', extra={'TZ': 'UTC0'})
        check('timedatectl set-timezone America/Sao_Paulo' in calls(),
              'timezone set: a bad CHAOS_TIMEZONE is ignored: ' + calls())
        # refusals set nothing
        open(os.path.join(stub, 'calls'), 'w').close()
        for bad in (('timezone', 'bogus'), ('timezone', 'set', 'x'), ('timezone', 'status'), ('timezone', '$(id)')):
            check(run(*bad).returncode != 0, 'timezone refuses %r' % (bad,))
        check('set-timezone' not in calls(), 'timezone: a refused call sets nothing')
        os.unlink(os.path.join(repo, 'server', 'tools', 'chaos_timezone.py'))
        r = run('timezone')
        check(r.returncode != 0 and 'chaos_timezone.py' in r.stderr, 'timezone: a missing tool is named: ' + r.stderr)
        h = run('help').stdout
        check('timezone set' in h and 'launch-check' in h, 'help lists timezone and launch-check')


LAUNCH_MYSQL = '''#!/usr/bin/env bash
echo "$(basename "$0") $*" >> "$STUB/calls"
[ -z "${STUB_DB_FAIL:-}" ] || { echo "ERROR 2002 (HY000): Can't connect to local MySQL server" >&2; exit 1; }
case "$*" in
  *chaos_beta_testers*)
    [ -z "${STUB_NO_BETA_TABLE:-}" ] || { echo "ERROR 1146 (42S02): Table 'chaos.chaos_beta_testers' doesn't exist" >&2; exit 1; }
    echo "${STUB_BETA_TESTERS:-0}" ;;
  *chaos_shop_coins*) echo "${STUB_COINS:-0}" ;;
  *players_online*) echo "${STUB_ONLINE:-0}" ;;
  *"FROM accounts"*) echo "${STUB_ACCOUNTS:-0}" ;;
  *"FROM players"*) echo "${STUB_PLAYERS:-0}" ;;
esac
'''
LAUNCH_GIT = '''#!/usr/bin/env bash
echo "git $*" >> "$STUB/calls"
shift 4
case "$1 $2" in
  "rev-parse --short") echo abc1234 ;;
  "symbolic-ref --short") echo main ;;
  "status --porcelain") [ -z "${STUB_GIT_DIRTY:-}" ] || echo " M x.lua" ;;
  "rev-parse HEAD") echo abc1234deadbeef ;;
  "describe --tags") echo winpkg-50 ;;
esac
'''


def test_launch_check():
    """chaos-ctl.sh launch-check [--json] [--max-players N] [--launch ...] (O440): the wiring of launch_check.py with a stub
    mysql and git; the decisions are launch_check_test.py's. Made-up values only."""
    repo_root = os.path.dirname(os.path.dirname(HERE))
    fake_key = '00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff'
    with tempfile.TemporaryDirectory() as tmp:
        stub = os.path.join(tmp, 'stub')
        repo = os.path.join(tmp, 'repo')
        server = os.path.join(tmp, 'server')
        cfg = os.path.join(server, 'data', 'scripts', 'chaos')
        bdir = os.path.join(tmp, 'backups')
        for d in (stub, os.path.join(repo, 'server', 'tools'), os.path.join(repo, 'server', 'deploy'), cfg,
                  os.path.join(server, 'data', 'patchnotes'), os.path.join(bdir, 'db')):
            os.makedirs(d)
        shutil.copy(os.path.join(repo_root, 'server', 'tools', 'chaos_timezone.py'), os.path.join(repo, 'server', 'tools'))
        shutil.copy(os.path.join(HERE, 'launch_check.py'), os.path.join(repo, 'server', 'deploy'))
        for name, body in (('systemctl', SYSTEMCTL), ('mysql', LAUNCH_MYSQL), ('git', LAUNCH_GIT),
                           ('timedatectl', TZ_TIMEDATECTL)):
            p = os.path.join(stub, name)
            with open(p, 'w') as f:
                f.write(body)
            os.chmod(p, 0o755)
        with open(os.path.join(stub, 'tz'), 'w') as f:
            f.write('America/Sao_Paulo\n')

        def put(path, text):
            with open(path, 'w') as f:
                f.write(text)
        put(os.path.join(cfg, 'beta_config.lua'), 'return {enabled = false}\n')
        put(os.path.join(cfg, 'beta_mode_config.lua'), 'return {enabled = false}\n')
        # the configs read the one launch value (O463); an example launch, the owner's date is never pinned here
        put(os.path.join(cfg, 'launch_config.lua'), 'return {\n\tlaunch = "2031-03-14 18:00"\n}\n')
        lc = 'dofile("data/scripts/chaos/launch_core.lua")'
        put(os.path.join(cfg, 'season_config.lua'),
            'return {seasons = {{id = 1, start = %s.ymd(0), finish = %s.ymd(91), lengthDays = 91, hour = 18}}}\n' % (lc, lc))
        put(os.path.join(cfg, 'battleground_config.lua'), 'return {season = {weeks = 8, epoch = %s.parts(0)}}\n' % lc)
        put(os.path.join(cfg, 'founder_config.lua'), 'local START = %s.stamp(0)\nlocal END = %s.stamp(28)\n' % (lc, lc))
        put(os.path.join(cfg, 'creator_codes_config.lua'),
            'return {launchBonusStart = %s.stamp(0), launchBonusDays = 30}\n' % lc)
        put(os.path.join(server, 'config.lua'),
            'maxPlayers = 400\nclientGuardMode = "enforce"\nclientGuardKey = os.getenv("CHAOS_CLIENT_KEY") or ""\n'
            'clientGuardAllowDevKey = false\n')
        for n in ('2031-03-14.md', '2031-03-14.pt-br.md'):
            put(os.path.join(server, 'data', 'patchnotes', n), 'x\n')
        dump = os.path.join(bdir, 'db', 'chaos-db-x-1.sql.gz')
        put(dump, '')
        env_file = os.path.join(tmp, 'chaos.env')
        put(env_file, 'CHAOS_DB_USER=chaos\nCHAOS_DB_PASS=secret\nCHAOS_BACKUP_DIR=%s\nCHAOS_CLIENT_KEY=%s\n' % (bdir, fake_key))
        penv = os.path.join(tmp, 'payments.env')
        put(penv, 'CHAOS_PAY_PIX_PROVIDER=mercadopago\nCHAOS_PAY_PAYPAL_PROVIDER=off\nCHAOS_MP_ACCESS_TOKEN=APP_USR-1234567890\n')
        none = os.path.join(tmp, 'none')
        env = dict(os.environ, PATH=stub + ':' + os.environ['PATH'], STUB=stub, CHAOS_CTL_NO_SUDO='1', CHAOS_SERVER_DIR=server,
                   CHAOS_ENV=env_file, CHAOS_REPO=repo, CHAOS_MYSQL='mysql', CHAOS_CTL_CONF=os.path.join(tmp, 'none.conf'),
                   CHAOS_PID_FILE=os.path.join(tmp, 'no.pid'), CHAOS_LOG=os.path.join(tmp, 'no.log'), CHAOS_PAY_ENV=penv,
                   CHAOS_BETA_CRON=os.path.join(tmp, 'chaos-beta-coins'), CHAOS_TZ_ETC_TIMEZONE=none,
                   CHAOS_TZ_LOCALTIME=none, TZ='BRT3')
        for k in ('SUDO_USER', 'CHAOS_UNIT', 'CHAOS_ROOT', 'CHAOS_KIT_DIR', 'CHAOS_DB_SOCKET', 'CHAOS_BACKUP_DIR',
                  'CHAOS_TIMEZONE', 'STUB_DB_FAIL', 'STUB_NO_BETA_TABLE', 'STUB_GIT_DIRTY'):
            env.pop(k, None)

        def run(*args, extra=None):
            return subprocess.run(['bash', SCRIPT] + list(args), env=dict(env, **(extra or {})), capture_output=True,
                                  text=True, timeout=120)

        def calls():
            p = os.path.join(stub, 'calls')
            return open(p).read() if os.path.exists(p) else ''

        def st(r):
            out = {}
            for line in r.stdout.splitlines()[:-1]:
                p = line.split()
                if len(p) >= 2:
                    out[p[1]] = p[0]
            return out

        def snapshot():
            snap = {}
            for base in (server, bdir, repo):
                for root, _d, files in os.walk(base):
                    for f in files:
                        p = os.path.join(root, f)
                        s = os.stat(p)
                        snap[p] = (s.st_size, s.st_mtime_ns)
            for p in (env_file, penv):
                s = os.stat(p)
                snap[p] = (s.st_size, s.st_mtime_ns)
            return snap

        before = snapshot()
        r = run('launch-check', '--max-players', '400')
        s = st(r)
        check(r.returncode == 0 and len(s) == 17 and set(s.values()) == {'OK'},
              'launch-check: a good installation, 17 OK, exit 0: ' + r.stdout + r.stderr)
        check(r.stdout.splitlines()[-1] == 'launch check: 0 FAIL, 0 WARN, 17 OK', 'launch-check: the summary line: ' + r.stdout)
        check(snapshot() == before, 'launch-check changes nothing on disk')
        c = calls()
        check('SELECT COUNT(*) FROM players' in c and 'FROM chaos_shop_coins WHERE coins > 0' in c
              and 'FROM chaos_beta_testers' in c and 'FROM players_online' in c and 'FROM accounts' in c,
              'launch-check: the five count queries: ' + c)
        check('UPDATE' not in c and 'DELETE' not in c and 'INSERT' not in c,
              'launch-check: only SELECT counts reach the database')
        check(fake_key not in r.stdout + r.stderr + c and 'secret' not in c and 'APP_USR-1234567890' not in r.stdout + r.stderr,
              'launch-check: no client key, database password or token anywhere')
        r = run('launch-check')
        check(r.returncode == 0 and st(r).get('max_players') == 'WARN' and 'owner decision: 300 or 400' in r.stdout,
              'launch-check: maxPlayers is a WARN without the flag, exit 0: ' + r.stdout)
        r = run('launch-check', '--max-players', '300')
        check(r.returncode == 1 and st(r).get('max_players') == 'FAIL', 'launch-check --max-players 300 against 400: FAIL')
        r = run('launch-check', '--json', '--max-players', '400')
        try:
            d = json.loads(r.stdout)
        except ValueError:
            d = {}
            check(False, 'launch-check --json: valid JSON: ' + r.stdout)
        check(r.returncode == 0 and r.stdout.count('\n') == 1 and d.get('ok') is True and d.get('okCount') == 17
              and d.get('fail') == 0 and d.get('launch') == '2031-03-14 18:00', 'launch-check --json: one line: ' + r.stdout)
        r = run('launch-check', '--max-players', '400', '--launch', '2031-04-04 18:00')
        s = st(r)
        check(r.returncode == 1 and s.get('launch_date') == 'FAIL' and s.get('dates_season') == 'FAIL'
              and s.get('dates_founder') == 'FAIL' and s.get('patch_notes') == 'WARN',
              'launch-check --launch moves the expected date: ' + r.stdout)
        # the launch is open (O463): one WARN says so, exit 0, the rest still runs
        put(os.path.join(cfg, 'launch_config.lua'), 'return {\n\tlaunch = "open"\n}\n')
        r = run('launch-check', '--max-players', '400')
        s = st(r)
        check(r.returncode == 0 and len(s) == 17 and s.get('launch_date') == 'WARN' and 'no launch date is set' in r.stdout
              and [k for k, v in s.items() if v == 'WARN'] == ['launch_date']
              and r.stdout.splitlines()[-1] == 'launch check: 0 FAIL, 1 WARN, 16 OK',
              'launch-check: open, one WARN that says no launch date is set, exit 0: ' + r.stdout)
        r = run('launch-check', '--json', '--max-players', '400')
        try:
            d = json.loads(r.stdout)
        except ValueError:
            d = {}
        check(d.get('launch') is None and d.get('launchOpen') is True and d.get('ok') is True and d.get('warn') == 1,
              'launch-check --json: open has launch null: ' + r.stdout)
        put(os.path.join(cfg, 'launch_config.lua'), 'return {\n\tlaunch = "2031-03-14 18:00"\n}\n')

        # one thing wrong at a time
        put(os.path.join(cfg, 'beta_config.lua'), 'return {enabled = true}\n')
        r = run('launch-check', '--max-players', '400')
        check(r.returncode == 1 and st(r).get('beta_config') == 'FAIL', 'launch-check: beta_config true: FAIL, exit 1')
        put(os.path.join(cfg, 'beta_config.lua'), 'return {enabled = false}\n')
        put(os.path.join(tmp, 'chaos-beta-coins'), '* * * * * root true\n')
        r = run('launch-check', '--max-players', '400')
        check(r.returncode == 1 and st(r).get('beta_cron') == 'FAIL', 'launch-check: the beta coins cron: FAIL')
        os.unlink(os.path.join(tmp, 'chaos-beta-coins'))
        put(penv, 'CHAOS_PAY_PIX_PROVIDER=mock\n')
        r = run('launch-check', '--max-players', '400')
        check(r.returncode == 1 and st(r).get('payments') == 'FAIL', 'launch-check: a mock provider: FAIL: ' + r.stdout)
        put(penv, 'CHAOS_PAY_PIX_PROVIDER=off\n')
        r = run('launch-check', '--max-players', '400')
        check(r.returncode == 0 and st(r).get('payments') == 'WARN', 'launch-check: no live provider: WARN, exit 0')
        os.unlink(penv)
        r = run('launch-check', '--max-players', '400')
        check(r.returncode == 0 and st(r).get('payments') == 'WARN', 'launch-check: no payments env: WARN (providers off)')
        put(penv, 'CHAOS_PAY_PIX_PROVIDER=mercadopago\nCHAOS_MP_ACCESS_TOKEN=APP_USR-1234567890\n')
        r = run('launch-check', '--max-players', '400', extra={'STUB_PLAYERS': '12', 'STUB_COINS': '3', 'STUB_ACCOUNTS': '9'})
        check(r.returncode == 0 and st(r).get('database') == 'WARN' and 'players 12' in r.stdout
              and 'accounts with coins 3' in r.stdout, 'launch-check: players before the wipe: WARN, counts only: ' + r.stdout)
        r = run('launch-check', '--max-players', '400', extra={'STUB_NO_BETA_TABLE': '1'})
        check(r.returncode == 1 and st(r).get('database') == 'FAIL' and 'beta_testers (no-table)' in r.stdout,
              'launch-check: a missing table fails only that count: ' + r.stdout)
        r = run('launch-check', '--max-players', '400', extra={'STUB_DB_FAIL': '1'})
        check(r.returncode == 1 and st(r).get('database') == 'FAIL' and 'players (database)' in r.stdout and len(st(r)) == 17,
              'launch-check: the database down: FAIL, no crash, every other check ran: ' + r.stdout)
        r = run('launch-check', '--max-players', '400', extra={'STUB_GIT_DIRTY': '1'})
        check(r.returncode == 0 and st(r).get('checkout') == 'WARN' and 'dirty' in r.stdout,
              'launch-check: a dirty checkout: WARN')
        r = run('launch-check', '--max-players', '400', extra={'TZ': 'UTC0'})
        check(r.returncode == 1 and st(r).get('timezone') == 'FAIL' and 'chaos-ctl.sh timezone set' in r.stdout,
              'launch-check: the timezone check is the Part A one: ' + r.stdout)
        os.unlink(dump)
        r = run('launch-check', '--max-players', '400')
        check(r.returncode == 1 and st(r).get('backup') == 'FAIL', 'launch-check: no backup: FAIL')
        put(dump, '')

        # refusals: nothing reaches the shell or the SQL as text
        n = len(calls())
        for bad in (('launch-check', 'x'), ('launch-check', '--json;id'), ('launch-check', '--max-players', 'x'),
                    ('launch-check', '--max-players', '0'), ('launch-check', '--max-players', '1234567'),
                    ('launch-check', '--max-players'), ('launch-check', '--launch', 'soon'),
                    ('launch-check', '--launch', '2026-11-20'), ('launch-check', '--launch', '2026-11-20 15:00; id'),
                    ('launch-check', '$(id)'), ('launch-check', "' OR 1=1 --")):
            check(run(*bad).returncode != 0, 'launch-check refuses %r' % (bad,))
        check(len(calls()) == n, 'launch-check: a refused call never reaches the database')
        os.unlink(os.path.join(repo, 'server', 'deploy', 'launch_check.py'))
        r = run('launch-check')
        check(r.returncode != 0 and 'launch_check.py' in r.stderr, 'launch-check: a missing tool is named: ' + r.stderr)


if __name__ == '__main__':
    sys.exit(main())
