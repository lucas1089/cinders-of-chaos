#!/usr/bin/env python3
"""Signs the desktop admin app release (O312) for its self-update (desktop/src/sign.rs, update.rs).

The scheme is the one of the game updater and the launcher (client/MANIFEST.md "Signed updater"): Ed25519 over the exact
bytes of a payload text, in the envelope {format, key, signature, payload}. The Ed25519 code is the one of
client/tools/make_update_manifest.py (same key file format: 64 hex digits, same keygen). The payload names the product,
the version, the file name, the SHA-256 and the size, so a signature is good for one file of one version.

  sign    --key PATH --exe FILE --version X.Y.Z [--asset cinders-admin.exe] --out FILE.sig
          [--public-file desktop/update_public_key.hex]
          Writes the signed envelope. Refuses a key that is not the one compiled into the app (the public key file), so
          a release the installed apps would reject is never published, and refuses a key file inside a git work tree.
  verify  --exe FILE --sig FILE --public HEX|FILE [--version X.Y.Z]
          Checks a signature file the way the app does (signature, product, asset name, size, SHA-256).
  keygen  is make_update_manifest.py keygen:  python3 -I client/tools/make_update_manifest.py keygen --private PATH
          Put the public key it prints in desktop/update_public_key.hex and the private key's text in the GitHub secret
          ADMIN_DESKTOP_SIGNING_KEY. Keep the private key file outside the repository.

usage: python3 -I desktop/tools/sign_release.py sign|verify ...
"""
import argparse
import hashlib
import importlib.util
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
PUBLIC_FILE = os.path.join(ROOT, 'desktop', 'update_public_key.hex')
FORMAT = 'cinders-admin-release-1'
PRODUCT = 'cinders-admin'
ASSET = 'cinders-admin.exe'
VERSION = re.compile(r'^[0-9]+(\.[0-9]+){1,3}$')
HEX64 = re.compile(r'^[0-9a-f]{64}$')


def manifest_tools():
    path = os.path.join(ROOT, 'client', 'tools', 'make_update_manifest.py')
    spec = importlib.util.spec_from_file_location('make_update_manifest', path)
    mod = importlib.util.module_from_spec(spec)
    sys.modules['make_update_manifest'] = mod
    sys.path.insert(0, os.path.dirname(path))  # ed25519_ref.py sits next to it
    spec.loader.exec_module(mod)
    return mod


def read_public(arg):
    """A 64 digit hex key, or the path of a file that holds one."""
    text = arg.strip()
    if not HEX64.match(text):
        with open(arg, encoding='ascii') as f:
            text = f.read().strip()
    if not HEX64.match(text) or text == '0' * 64:
        sys.exit('no usable public key (64 lowercase hex digits, not all zeros): ' + arg)
    return text


def payload_for(exe_bytes, version, asset):
    return json.dumps({
        'format': 1,
        'product': PRODUCT,
        'version': version,
        'asset': asset,
        'sha256': hashlib.sha256(exe_bytes).hexdigest(),
        'size': len(exe_bytes),
    }, separators=(',', ':'))


def envelope(m, seed, payload):
    public = m.public_from_seed(seed)
    signature = m.sign(seed, payload.encode('ascii'))
    if not m.verify_sig(public, payload.encode('ascii'), signature):
        sys.exit('internal: the new signature does not verify')
    return json.dumps({
        'format': FORMAT,
        'key': public.hex(),
        'signature': signature.hex(),
        'payload': payload,
    }, separators=(',', ':')) + '\n'


def check_envelope(m, text, exe_bytes, public_hex, version=None, asset=ASSET):
    """None when the file is good, else the reason (the checks of desktop/src/sign.rs)."""
    try:
        env = json.loads(text)
        payload = env['payload']
        signature = bytes.fromhex(env['signature'])
    except (ValueError, KeyError, TypeError):
        return 'not a signature file'
    if env.get('format') != FORMAT:
        return 'unknown format'
    public = bytes.fromhex(public_hex)
    if env.get('key') is not None and env['key'] != public_hex:
        return 'signed with another key'
    if not m.verify_sig(public, payload.encode('ascii'), signature):
        return 'bad signature'
    p = json.loads(payload)
    if p.get('format') != 1 or p.get('product') != PRODUCT:
        return 'another product'
    if p.get('asset') != asset:
        return 'another file name'
    if version is not None and p.get('version') != version:
        return 'another version'
    if p.get('size') != len(exe_bytes):
        return 'size differs'
    if p.get('sha256') != hashlib.sha256(exe_bytes).hexdigest():
        return 'checksum differs'
    return None


def cmd_sign(args):
    if not VERSION.match(args.version):
        sys.exit('version like 0.2.0')
    m = manifest_tools()
    seed = m.read_seed(args.key)  # refuses a key inside a git work tree
    want = read_public(args.public_file)
    if m.public_from_seed(seed).hex() != want:
        sys.exit('this key is not the one in %s: the installed apps would refuse the release' % args.public_file)
    with open(args.exe, 'rb') as f:
        data = f.read()
    if not data:
        sys.exit(args.exe + ' is empty')
    text = envelope(m, seed, payload_for(data, args.version, args.asset))
    why = check_envelope(m, text, data, want, args.version, args.asset)
    if why:
        sys.exit('internal: the new file does not check: ' + why)
    with open(args.out, 'w', encoding='ascii', newline='\n') as f:
        f.write(text)
    print('signed %s %s (%d bytes) -> %s' % (args.asset, args.version, len(data), args.out))
    return 0


def cmd_verify(args):
    m = manifest_tools()
    public = read_public(args.public)
    with open(args.exe, 'rb') as f:
        data = f.read()
    with open(args.sig, encoding='ascii') as f:
        text = f.read()
    why = check_envelope(m, text, data, public, args.version, args.asset)
    if why:
        print('refused:', why)
        return 1
    print('signature ok')
    return 0


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    sub = ap.add_subparsers(dest='cmd', required=True)
    s = sub.add_parser('sign')
    s.add_argument('--key', required=True)
    s.add_argument('--exe', required=True)
    s.add_argument('--version', required=True)
    s.add_argument('--asset', default=ASSET)
    s.add_argument('--out', required=True)
    s.add_argument('--public-file', default=PUBLIC_FILE)
    v = sub.add_parser('verify')
    v.add_argument('--exe', required=True)
    v.add_argument('--sig', required=True)
    v.add_argument('--public', required=True)
    v.add_argument('--version')
    v.add_argument('--asset', default=ASSET)
    args = ap.parse_args(argv)
    return {'sign': cmd_sign, 'verify': cmd_verify}[args.cmd](args)


if __name__ == '__main__':
    sys.exit(main())
