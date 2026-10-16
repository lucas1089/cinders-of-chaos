#!/usr/bin/env python3
"""Tests of rsa_key.py: gen (mode 600, PKCS#1, 1024 bits, refusals), public, check, fingerprint, the default key.

  python3 -I server/tools/rsa_key_test.py      (needs the openssl command, as on the game server)
"""
import base64
import hashlib
import os
import shutil
import stat
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import rsa_key as R  # noqa: E402

fails = 0


def check(cond, what):
    global fails
    if not cond:
        fails += 1
        print('FAIL: ' + what)


def run(args):
    return subprocess.run([sys.executable, '-I', os.path.join(HERE, 'rsa_key.py')] + args,
                          capture_output=True, text=True)


def der_int(v):
    b = v.to_bytes((v.bit_length() + 8) // 8 or 1, 'big')
    return b'\x02' + der_len(len(b)) + b


def der_len(n):
    if n < 128:
        return bytes([n])
    b = n.to_bytes((n.bit_length() + 7) // 8, 'big')
    return bytes([0x80 | len(b)]) + b


def fake_pkcs1(n, e=65537):
    """a PEM with the shape of a PKCS#1 key and modulus n (the other numbers are dummies: only n and e are read)"""
    body = b''.join(der_int(v) for v in (0, n, e, 3, 5, 7, 1, 1, 1))
    der = b'\x30' + der_len(len(body)) + body
    b64 = base64.b64encode(der).decode()
    return '-----BEGIN RSA PRIVATE KEY-----\n%s\n-----END RSA PRIVATE KEY-----\n' % '\n'.join(
        b64[i:i + 64] for i in range(0, len(b64), 64))


if not shutil.which('openssl'):
    print('rsa_key_test: skipped (no openssl command)')
    sys.exit(0)

d = tempfile.mkdtemp()
try:
    key = os.path.join(d, 'rsa', 'login.pem')
    r = run(['gen', '--out', key])
    check(r.returncode == 0, 'gen works: ' + r.stderr)
    st = os.stat(key)
    check(stat.S_IMODE(st.st_mode) == 0o600, 'key mode 600 (%o)' % stat.S_IMODE(st.st_mode))
    check(stat.S_IMODE(os.stat(os.path.dirname(key)).st_mode) == 0o700, 'new folder mode 700')
    text = open(key).read()
    check(text.startswith('-----BEGIN RSA PRIVATE KEY-----'), 'PKCS#1 PEM, the format the engine reads')
    check('PRIVATE KEY' not in r.stdout and text.split('\n')[1] not in r.stdout, 'gen never prints the private key')
    n, e, pkcs1 = R.read_key(key)
    check(n.bit_length() == 1024 and e == 65537 and pkcs1, '1024 bits, e 65537')
    m = int(subprocess.check_output(['openssl', 'rsa', '-in', key, '-noout', '-modulus']).decode().split('=')[1], 16)
    check(m == n, 'the DER reader gives the same modulus as openssl')
    check(str(n) in r.stdout and R.fingerprint(n) in r.stdout, 'gen prints the public modulus and the fingerprint')
    check(R.fingerprint(n) == hashlib.sha256(str(n).encode()).hexdigest()[:16], 'fingerprint definition')
    leftovers = [f for f in os.listdir(os.path.dirname(key)) if f != 'login.pem']
    check(not leftovers, 'no temporary file left: %s' % leftovers)

    r = run(['gen', '--out', key])
    check(r.returncode != 0 and 'exists' in (r.stderr + r.stdout), 'gen refuses to overwrite a key')
    check(open(key).read() == text, 'the old key is untouched')

    r = run(['public', '--key', key])
    check(r.returncode == 0 and r.stdout.strip().split('\n')[-1] == str(n), 'public prints the decimal modulus last')
    r = run(['check', '--key', key])
    check(r.returncode == 0 and 'ok' in r.stdout, 'check passes on a fresh key: ' + r.stdout)
    r = run(['fingerprint', str(n)])
    check(r.stdout.strip() == R.fingerprint(n), 'fingerprint command')

    os.chmod(key, 0o640)
    r = run(['check', '--key', key])
    check(r.returncode == 1 and 'mode 640' in r.stdout, 'check refuses a group-readable key')
    os.chmod(key, 0o600)

    # PKCS#8 (what OpenSSL 3 writes without -traditional) is read but refused for the engine
    p8 = os.path.join(d, 'p8.pem')
    subprocess.run(['openssl', 'pkcs8', '-topk8', '-nocrypt', '-in', key, '-out', p8], check=True,
                   capture_output=True)
    os.chmod(p8, 0o600)
    check(R.read_key(p8)[0] == n, 'PKCS#8 modulus read')
    r = run(['check', '--key', p8])
    check(r.returncode == 1 and 'PKCS#1' in r.stdout, 'check refuses PKCS#8')

    # the public default open-server key
    default = os.path.join(d, 'default.pem')
    with open(default, 'w') as f:
        f.write(fake_pkcs1(R.PUBLIC_DEFAULT_N))
    os.chmod(default, 0o600)
    r = run(['check', '--key', default])
    check(r.returncode == 1 and 'PUBLIC DEFAULT' in r.stdout, 'check refuses the public default key')
    r = run(['public', '--key', default])
    check('WARNING' in r.stderr, 'public warns on the default key')
    check(R.fingerprint(R.PUBLIC_DEFAULT_N) == '69bbc82b7c9073de', 'default key fingerprint (engine log value)')

    # 2048 bits and another exponent
    small = os.path.join(d, 'e3.pem')
    with open(small, 'w') as f:
        f.write(fake_pkcs1(n, 3))
    os.chmod(small, 0o600)
    check(any('exponent' in p for p in R.problems(small)), 'exponent other than 65537 refused')
    big = os.path.join(d, 'big.pem')
    with open(big, 'w') as f:
        f.write(fake_pkcs1((1 << 2047) | 1))
    os.chmod(big, 0o600)
    check(any('2048 bits' in p for p in R.problems(big)), '2048-bit key refused')

    # never inside a git work tree
    repo = os.path.join(d, 'repo')
    os.makedirs(os.path.join(repo, '.git'))
    r = run(['gen', '--out', os.path.join(repo, 'keys', 'k.pem')])
    check(r.returncode != 0 and 'git' in (r.stderr + r.stdout), 'gen refuses a path inside a git work tree')
    check(not os.path.exists(os.path.join(repo, 'keys', 'k.pem')), 'nothing written in the work tree')
    inside = os.path.join(repo, 'k.pem')
    shutil.copy(key, inside)
    os.chmod(inside, 0o600)
    check(any('git work tree' in p for p in R.problems(inside)), 'check flags a key inside a work tree')
finally:
    shutil.rmtree(d)

if fails:
    print('%d failure(s)' % fails)
    sys.exit(1)
print('rsa_key_test: ok')
