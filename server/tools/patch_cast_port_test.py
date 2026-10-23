#!/usr/bin/env python3
"""Test of patch_cast_port.py: castPort set on a stock-like config.lua (appended when missing, a comment kept, CRLF kept,
the rest unchanged), idempotent, --port, --dry-run, bad arguments.
Run: python3 -I server/tools/patch_cast_port_test.py"""
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.join(HERE, 'patch_cast_port.py')
sys.path.insert(0, HERE)
import patch_cast_port as P  # noqa: E402

STOCK = '''-- Connection Config
ip = "127.0.0.1"
bindOnlyGlobalAddress = false
loginProtocolPort = 7171
gameProtocolPort = 7172
statusProtocolPort = 7171
maxPlayers = 0
broadcastPort = 5
'''

fails = 0


def check(cond, what):
    global fails
    if not cond:
        fails += 1
        print('FAIL', what)


def run(*args):
    return subprocess.run([sys.executable, '-I', TOOL] + list(args), capture_output=True, text=True)


new, old = P.patch(STOCK, 7179)
check(old is None and new.startswith(STOCK) and '\ncastPort = 7179 -- ' in new, 'appended when missing')
check(P.patch(new, 7179)[0] == new, 'idempotent')
again, old = P.patch(new, 7200)
check(old == '7179' and 'castPort = 7200 -- Cinders' in again and again.count('\ncastPort') == 1, 'changed in place')
crlf = 'a = 1\r\ncastPort = 0 -- off\r\nb = 2\r\n'
check(P.patch(crlf, 7179)[0] == 'a = 1\r\ncastPort = 7179 -- off\r\nb = 2\r\n', 'CRLF and the comment kept')
check(P.patch('broadcastPort = 1\n', 7179)[0].count('castPort = 7179') == 1, 'another key ending in Port is not it')

with tempfile.TemporaryDirectory() as tmp:
    cfg = os.path.join(tmp, 'config.lua')
    with open(cfg, 'w') as f:
        f.write(STOCK)
    r = run(tmp, '--dry-run')
    check(r.returncode == 0 and 'dry run' in r.stdout and open(cfg).read() == STOCK, 'dry run changes nothing')
    r = run(tmp)
    check(r.returncode == 0 and 'castPort = 7179' in open(cfg).read(), 'written')
    r = run(tmp)
    check(r.returncode == 0 and 'already' in r.stdout, 'second run: already')
    r = run(tmp, '--port', '7300')
    check(r.returncode == 0 and 'castPort = 7300' in open(cfg).read(), '--port')
    for bad in (['--port', '0'], ['--port', '70000'], ['--port', 'x'], [], [tmp, tmp]):
        check(run(*([tmp] + bad if bad and bad[0] == '--port' else bad)).returncode != 0, 'refused: %r' % bad)
    check(run(os.path.join(tmp, 'none')).returncode != 0, 'no config.lua')

print('patch_cast_port_test: %d failures' % fails)
sys.exit(1 if fails else 0)
