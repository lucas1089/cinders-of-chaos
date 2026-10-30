#!/usr/bin/env python3
"""Tests for desktop/tools/sign_release.py (O312 signed self-update).

Signs a fake program with a throwaway key, verifies it, and checks the refusals: another key, a changed byte, a wrong
version or file name, a key that is not the one compiled into the app, a key file inside a git work tree. The vector
(fixed seed, fixed bytes) is the same one desktop/src/sign.rs checks, so the Python signer and the Rust verifier are pinned
to each other: Ed25519 is deterministic, the envelope must be byte for byte this one.

usage: python3 -I desktop/tools/sign_release_test.py
"""
import os
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import sign_release as S  # noqa: E402

fails = 0


def check(cond, what):
    global fails
    if not cond:
        fails += 1
        print('FAIL', what)


# the vector shared with desktop/src/sign.rs (VECTOR_*)
SEED = bytes([0x42]) * 32
EXE = b'cinders-admin test program\n'
VERSION = '0.2.0'
VECTOR_ENVELOPE = (
    '{"format":"cinders-admin-release-1","key":"2152f8d19b791d24453242e15f2eab6cb7cffa7b6a5ed30097960e069881db12","signature":"6efec38f4128de865126aac8db530e1ed8e4d8a5bf22df068132c5a8bb4feb2ca9426202ec1a4f187184a4a0a044cc4408d65cdf37a3e931be69b8bb6d7bc203","payload":"{\\"format\\":1,\\"product\\":\\"cinders-admin\\",\\"version\\":\\"0.2.0\\",\\"asset\\":\\"cinders-admin.exe\\",\\"sha256\\":\\"85bf7cd5d2bc943c74ce227067aab30872d2f2501a1cc81b85ece49b593a259c\\",\\"size\\":27}"}\n'
)

m = S.manifest_tools()
pub = m.public_from_seed(SEED).hex()
check(pub == '2152f8d19b791d24453242e15f2eab6cb7cffa7b6a5ed30097960e069881db12',
      'vector public key (update sign.rs VECTOR_PUBLIC if this changes): ' + pub)
payload = S.payload_for(EXE, VERSION, S.ASSET)
text = S.envelope(m, SEED, payload)
if '--print-vector' in sys.argv:
    print(text, end='')
    sys.exit(0)
check(text == VECTOR_ENVELOPE, 'the vector is what the signer makes (update VECTOR_* in sign.rs if this changes)')
check(S.check_envelope(m, text, EXE, pub, VERSION) is None, 'vector verifies')
check(len(EXE) == 27, 'vector size')

with tempfile.TemporaryDirectory() as tmp:
    key = os.path.join(tmp, 'key.hex')
    with open(key, 'w') as f:
        f.write(SEED.hex() + '\n')
    os.chmod(key, 0o600)
    exe = os.path.join(tmp, 'cinders-admin.exe')
    with open(exe, 'wb') as f:
        f.write(EXE)
    pubfile = os.path.join(tmp, 'update_public_key.hex')
    with open(pubfile, 'w') as f:
        f.write(pub + '\n')
    sig = os.path.join(tmp, 'cinders-admin.exe.sig')

    def sign(*extra, key_path=key, public=pubfile, version=VERSION):
        argv = ['sign', '--key', key_path, '--exe', exe, '--version', version, '--out', sig, '--public-file', public]
        try:
            return S.main(argv + list(extra))
        except SystemExit as e:
            return e.code

    def verify(version=VERSION, exe_path=exe, public=pub):
        try:
            return S.main(['verify', '--exe', exe_path, '--sig', sig, '--public', public, '--version', version])
        except SystemExit as e:
            return e.code

    check(sign() == 0, 'sign works')
    check(open(sig).read() == text, 'the signed file is the vector (deterministic)')
    check(verify() == 0, 'verify ok')
    check(verify(public=pubfile) == 0, 'verify takes the public key file')

    # a changed byte, a wrong version, another key
    bad = os.path.join(tmp, 'bad.exe')
    with open(bad, 'wb') as f:
        f.write(EXE[:-1] + b'!')
    check(verify(exe_path=bad) == 1, 'a changed byte is refused')
    check(verify(version='0.3.0') == 1, 'another version is refused')
    other = m.public_from_seed(bytes([9]) * 32).hex()
    check(verify(public=other) == 1, 'another key is refused')
    with open(sig) as f:
        env = f.read()
    with open(sig, 'w') as f:
        f.write(env.replace('"signature":"', '"signature":"00'))
    check(verify() == 1, 'a damaged signature is refused')
    with open(sig, 'w') as f:
        f.write('hello')
    check(verify() == 1, 'garbage is refused')
    with open(sig, 'w') as f:
        f.write(env.replace('cinders-admin-release-1', 'chaos-update-1'))
    check(verify() == 1, 'another format is refused')

    # the key must be the one compiled in
    wrong = os.path.join(tmp, 'wrong_public.hex')
    with open(wrong, 'w') as f:
        f.write(other + '\n')
    check(sign(public=wrong) not in (0, None), 'sign refuses a key that is not the compiled-in one')
    zeros = os.path.join(tmp, 'zeros.hex')
    with open(zeros, 'w') as f:
        f.write('0' * 64 + '\n')
    check(sign(public=zeros) not in (0, None), 'sign refuses while the public key file holds no key')
    check(sign(version='x') not in (0, None), 'sign refuses a bad version')

    # a private key inside a git work tree is refused (the repository itself)
    inside = os.path.join(S.ROOT, 'desktop', 'tools', '.test-key.hex')
    try:
        with open(inside, 'w') as f:
            f.write(SEED.hex() + '\n')
        check(sign(key_path=inside) not in (0, None), 'sign refuses a key inside the repository')
    finally:
        if os.path.exists(inside):
            os.remove(inside)

# the shipped public key file is a key or all zeros, never half of one
shipped = open(S.PUBLIC_FILE).read().strip()
check(len(shipped) == 64 and all(c in '0123456789abcdef' for c in shipped), 'update_public_key.hex holds 64 hex digits')

print('sign_release_test: %d failures' % fails)
sys.exit(1 if fails else 0)
