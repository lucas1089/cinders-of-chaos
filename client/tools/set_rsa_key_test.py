#!/usr/bin/env python3
"""Tests of set_rsa_key.py and of base patch 0072's Lua side: the modulus checks, init.lua edits, idempotence, the
environment variable rules, and that gamelib takes Services.rsa (the const.lua hunk run under LuaJIT / Lua 5.3).

  python3 -I client/tools/set_rsa_key_test.py
"""
import os
import random
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import set_rsa_key as K  # noqa: E402

PATCH = os.path.join(HERE, '..', 'base-patches', '0072-login-encryption-keys.patch')
INIT = '''Services = {
  account = "",
  update = {
    manifest = "",
    download = ""
  },
  -- comment
  rsa = ""
}

Servers = {
}
'''
fails = 0


def check(cond, what):
    global fails
    if not cond:
        fails += 1
        print('FAIL: ' + what)


def fake_modulus(seed):
    """a 1024-bit odd number (not a real key: the tool only checks the shape)"""
    rnd = random.Random(seed)
    return (1 << 1023) | rnd.getrandbits(1022) << 1 | 1


def run(args, env=None):
    e = dict(os.environ)
    e.update(env or {})
    return subprocess.run([sys.executable, '-I', os.path.join(HERE, 'set_rsa_key.py')] + args,
                          capture_output=True, text=True, env=e)


n1, n2 = fake_modulus(1), fake_modulus(2)

# modulus checks
check(K.parse_modulus(str(n1)) == n1, 'a 1024-bit odd modulus is accepted')
for bad, why in ((str(K.PUBLIC_DEFAULT_N), 'the public default key'), (str(n1 + 1), 'even'),
                 (str(n1 >> 1), '1023 bits'), ('0x' + format(n1, 'x'), 'hex'), ('', 'empty'),
                 (str(n1) + ' ', None), ('12 34', 'spaces inside')):
    try:
        K.parse_modulus(bad)
        ok = why is None
    except ValueError:
        ok = why is not None
    check(ok, 'parse_modulus: %r (%s)' % (bad[:20], why or 'trailing space is trimmed'))

# init.lua edits
t1 = K.apply(INIT, n1)
check('\n  rsa = "%d"\n}' % n1 in t1, 'Services.rsa written')
check(K.apply(t1, n1) == t1, 'idempotent')
check('\n  rsa = "%d"\n}' % n2 in K.apply(t1, n2), 'a new key replaces the old one')
check(K.apply(t1, None) == INIT, 'cleared again')
try:
    K.apply(INIT.replace('  rsa = ""\n', ''), n1)
    check(False, 'no rsa field: refused')
except ValueError:
    pass
check(K.fingerprint(n1) == __import__('hashlib').sha256(str(n1).encode()).hexdigest()[:16], 'fingerprint')

# command line and environment
d = tempfile.mkdtemp()
try:
    init = os.path.join(d, 'init.lua')
    with open(init, 'w', encoding='utf-8', newline='') as f:
        f.write(INIT.replace('\n', '\r\n'))
    r = run([d, '--from-env', 'CHAOS_RSA_PUBLIC'], {'CHAOS_RSA_PUBLIC': ''})
    check(r.returncode == 1 and 'empty' in r.stderr, 'empty variable fails without --allow-default')
    r = run([d, '--from-env', 'CHAOS_RSA_PUBLIC', '--allow-default'], {'CHAOS_RSA_PUBLIC': ''})
    check(r.returncode == 0 and 'PUBLIC DEFAULT' in r.stdout, 'empty variable with --allow-default warns')
    r = run([d, '--from-env', 'CHAOS_RSA_PUBLIC'], {'CHAOS_RSA_PUBLIC': str(n1) + '\n'})
    text = open(init, encoding='utf-8', newline='').read()
    check(r.returncode == 0 and ('rsa = "%d"\r\n}' % n1) in text, 'set from the environment, CRLF kept')
    check(K.fingerprint(n1) in r.stdout and str(n1) not in r.stdout, 'prints the fingerprint, not the modulus')
    r = run([d, '--modulus', str(K.PUBLIC_DEFAULT_N)])
    check(r.returncode == 1 and 'default' in r.stderr, 'the default key is refused')
    check(('rsa = "%d"' % n1) in open(init, encoding='utf-8').read(), 'a refused value leaves init.lua as it was')
    r = run([d, '--clear'])
    check(r.returncode == 0 and 'rsa = ""' in open(init, encoding='utf-8').read(), '--clear')
finally:
    shutil.rmtree(d)

# base patch 0072: init.lua gets the field the tool edits, const.lua takes it
patch = open(PATCH, encoding='utf-8').read()
check('+  rsa = ""\n' in patch or '+  rsa = ""\r\n' in patch, 'patch 0072 adds Services.rsa to init.lua')
check('RAND_bytes' in patch and 'mt19937 eng(std::time' in patch, 'patch 0072 replaces the time-seeded XTEA key')
m = re.search(r'\n\+(-- Chaos \(base patch 0072\).*?\n\+end)\r?\n', patch, re.S)
check(m is not None, 'patch 0072 const.lua hunk found')
if m:
    snippet = '\n'.join(line[1:] for line in ('+' + m.group(1)).replace('\r', '').split('\n'))
    lua = 'OTSERV_RSA = "default"\nServices = {rsa = VALUE}\n' + snippet + '\nprint(OTSERV_RSA)\n'
    for exe in ('luajit', 'lua5.3'):
        if not shutil.which(exe):
            continue
        for value, want in (('"%d"' % n1, str(n1)), ('""', 'default'), ('"123"', 'default'), ('42', 'default'),
                            ('"%d x"' % n1, 'default')):
            out = subprocess.run([exe, '-'], input=lua.replace('VALUE', value), capture_output=True, text=True)
            check(out.stdout.strip() == want, '%s: Services.rsa = %s -> %s (got %r)' % (exe, value[:12], want[:12],
                                                                                     out.stdout.strip()[:12]))
        out = subprocess.run([exe, '-'], input=snippet + '\nprint(OTSERV_RSA)\n', capture_output=True, text=True)
        check(out.returncode == 0, '%s: no Services table is fine' % exe)

if fails:
    print('%d failure(s)' % fails)
    sys.exit(1)
print('set_rsa_key_test: ok')
