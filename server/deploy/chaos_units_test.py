#!/usr/bin/env python3
"""Tests for the systemd units of server/deploy/ (O196: server hardening; docs/LAUNCH.md "Running it").

Reads the unit files as text. The two game server units run as User=chaos, never root (chaos-ctl.sh server-user). Checks that no unit keeps core dumps, that chaos-server.service has the sandbox lines and
none of the two that would break it (MemoryDenyWriteExecute, SystemCallFilter), that it keeps ProtectSystem=full (the
reason is in the unit), and that the root ExecStopPost on a file of the repository checkout is guarded: the guard is
run here on a throwaway tree (clean tree runs the script; a file or directory writable by group or others, owned by the
service user or group, or a missing user is refused). Runs systemd-analyze verify when it is installed.

usage: python3 -I server/deploy/chaos_units_test.py
"""
import glob
import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
fails = []


def check(cond, msg):
    if not cond:
        fails.append(msg)
        print('FAIL', msg)


def lines(path):
    """Directive lines of a unit (comments dropped), as a list of 'Key=value' strings."""
    out = []
    for raw in open(path, encoding='utf-8'):
        raw = raw.rstrip('\n')
        if raw.strip() and not raw.lstrip().startswith('#'):
            out.append(raw.strip())
    return out


units = sorted(glob.glob(os.path.join(HERE, '*.service')))
check(len(units) >= 9, 'units found: %d' % len(units))

for path in units:
    name = os.path.basename(path)
    body = lines(path)
    check(not any(re.match(r'LimitCORE=(infinity|-1)', l) for l in body), name + ': keeps core dumps (LimitCORE)')
    check('MemoryDenyWriteExecute=true' not in body and not any(l.startswith('SystemCallFilter=') for l in body),
          name + ': MemoryDenyWriteExecute / SystemCallFilter would break LuaJIT or the tools')
    for l in body:
        if re.match(r'Exec(Start|Stop)(Pre|Post)?=\+', l) and '/opt/chaos/repo/' in l and name != 'chaos-server.service':
            check(False, name + ': root command from the repository checkout without a guard: ' + l)

srv = lines(os.path.join(HERE, 'chaos-server.service'))
need = ['LimitCORE=0', 'NoNewPrivileges=true', 'PrivateTmp=true', 'PrivateDevices=true', 'ProtectSystem=full',
        'ProtectHome=true', 'ProtectProc=invisible', 'ProtectKernelTunables=true', 'ProtectKernelModules=true',
        'ProtectKernelLogs=true', 'ProtectControlGroups=true', 'ProtectClock=true', 'ProtectHostname=true',
        'RestrictNamespaces=true', 'RestrictRealtime=true', 'RestrictSUIDSGID=true', 'LockPersonality=true',
        'SystemCallArchitectures=native', 'CapabilityBoundingSet=', 'AmbientCapabilities=', 'User=chaos']
for n in need:
    check(n in srv, 'chaos-server.service lacks ' + n)
# the game server never runs as root (the engine warns about it; chaos-ctl.sh server-user fix installs these with User=chaos)
kit = lines(os.path.join(HERE, 'chaos-trial-server.service'))
for n in ('User=chaos', 'Group=chaos'):
    check(n in kit, 'chaos-trial-server.service lacks ' + n)
check(not any(l in ('User=root', 'Group=root') for l in srv + kit), 'a game server unit runs as root')
check(any('start-server.sh' in l for l in kit if l.startswith('ExecStart=')), 'the kit unit starts start-server.sh '
      '(chaos-ctl.sh server-user tells the two layouts apart by it)')
fam = [l for l in srv if l.startswith('RestrictAddressFamilies=')]
check(len(fam) == 1 and set(fam[0].split('=', 1)[1].split()) == {'AF_INET', 'AF_INET6', 'AF_UNIX', 'AF_NETLINK'},
      'chaos-server.service address families: %r' % fam)
check(not any(l.startswith('UMask=') for l in srv), 'UMask would hide files the website and chaos-ctl read')
check(not any(l.startswith('ReadWritePaths=') for l in srv), 'ReadWritePaths without ProtectSystem=strict')

# the guard of the root ExecStopPost
stop = [l for l in srv if l.startswith('ExecStopPost=')]
check(len(stop) == 1 and stop[0].startswith("ExecStopPost=+/bin/sh -c '"), 'ExecStopPost is one guarded root command')
if len(stop) == 1:
    cmd = stop[0][len("ExecStopPost=+/bin/sh -c '"):-1].replace('$$', '$')
    check('chaos_crashlog.sh' in cmd and '-perm /022' in cmd and '-user chaos' in cmd and '-group chaos' in cmd,
          'the guard tests owner, group and write bits')
    tmp = tempfile.mkdtemp()
    try:
        repo = os.path.join(tmp, 'repo')
        tools = os.path.join(repo, 'server', 'tools')
        os.makedirs(tools)
        script = os.path.join(tools, 'chaos_crashlog.sh')
        with open(script, 'w') as f:
            f.write('#!/bin/sh\necho RAN\n')
        os.chmod(script, 0o755)
        for d in (repo, os.path.join(repo, 'server'), tools):
            os.chmod(d, 0o755)
        me_u = subprocess.run(['id', '-un'], capture_output=True, text=True).stdout.strip()
        me_g = subprocess.run(['id', '-gn'], capture_output=True, text=True).stdout.strip()

        def run(user, group):
            c = cmd.replace('/opt/chaos/repo', repo).replace('-user chaos', '-user ' + user).replace('-group chaos', '-group ' + group)
            r = subprocess.run(['/bin/sh', '-c', c], capture_output=True, text=True)
            return r.returncode, r.stdout.strip(), r.stderr.strip()

        # a user and group that own nothing here: the clean tree runs the script
        other_u = next((u for u in ('nobody', 'daemon', 'bin') if u != me_u), None)
        other_g = next((g for g in ('nogroup', 'daemon', 'bin') if g != me_g
                        and subprocess.run(['getent', 'group', g], capture_output=True).returncode == 0), None)
        if other_u and other_g and subprocess.run(['getent', 'passwd', other_u], capture_output=True).returncode == 0:
            check(run(other_u, other_g) == (0, 'RAN', ''), 'clean tree runs the script: %r' % (run(other_u, other_g),))
            rc, out, err = run(me_u, other_g)
            check(rc == 0 and out == '' and 'crash record skipped' in err, 'owned by the service user: refused: %r' % err)
            rc, out, err = run(other_u, me_g)
            check(rc == 0 and out == '' and 'crash record skipped' in err, 'group of the service user: refused: %r' % err)
            os.chmod(os.path.join(repo, 'server'), 0o775)
            rc, out, err = run(other_u, other_g)
            check(out == '' and 'crash record skipped' in err, 'group writable directory: refused')
            os.chmod(os.path.join(repo, 'server'), 0o755)
            os.chmod(script, 0o757)
            rc, out, err = run(other_u, other_g)
            check(out == '' and 'crash record skipped' in err, 'world writable script: refused')
            os.chmod(script, 0o755)
        rc, out, err = run('no-such-user-xyz', 'no-such-group-xyz')
        check(rc == 0 and out == '' and 'crash record skipped' in err, 'unknown user or group: refused (fails closed)')
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

# systemd's own parser, when available (unknown directives, bad values; missing binaries are not our business here)
if shutil.which('systemd-analyze'):
    for path in units:
        r = subprocess.run(['systemd-analyze', 'verify', path], capture_output=True, text=True)
        bad = [l for l in (r.stdout + r.stderr).splitlines()
               if l.strip() and not re.search(r'not executable|No such file|not found|Failed to create|Access denied|Unit .* not found', l)]
        check(not bad, os.path.basename(path) + ': systemd-analyze verify: ' + '; '.join(bad[:3]))

if fails:
    print('%d failed' % len(fails))
    sys.exit(1)
print('chaos_units_test: ok (%d units)' % len(units))
