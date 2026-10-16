#!/usr/bin/env python3
"""The game server's own RSA login key (engine patch 0046, server/README.md "Login encryption (RSA, XTEA)").

  python3 -I server/tools/rsa_key.py gen --out /etc/chaos/rsa/login-YYYYMMDD.pem [--owner chaos]
  python3 -I server/tools/rsa_key.py public --key FILE        # the decimal modulus for CHAOS_RSA_PUBLIC, and its fingerprint
  python3 -I server/tools/rsa_key.py check --key FILE [--owner chaos]
  python3 -I server/tools/rsa_key.py fingerprint MODULUS      # the fingerprint of a decimal modulus (compare with the build log)

The 10.98 login sends the account, the password and the session's XTEA key in one 128-byte RSA block. The key.pem of
the base download is the public default open-server key: its private key is public, so anyone on the path can read
every login with it. Make our own key on the game server, keep the private key there, and build the client with the
public modulus:

  gen     makes a 1024-bit key (the protocol's block size, exponent 65537) with `openssl genrsa` as a PKCS#1 PEM
          ("BEGIN RSA PRIVATE KEY", what the engine reads), mode 600, in a folder of mode 700. With --owner (as root)
          the file belongs to that user (the engine runs as `chaos`). Refuses a path inside a git work tree and an
          existing file (a rotation takes a new file name). Prints only the public modulus and the fingerprint.
  public  prints the decimal modulus (the value of the GitHub secret CHAOS_RSA_PUBLIC; it is public, not secret) and
          the fingerprint.
  check   the file is a PKCS#1 key of 1024 bits with exponent 65537, not the public default key, mode 600 (no group or
          other bits), outside a git work tree, owned by --owner when given. Exit status 1 on a problem.
  fingerprint  the first 16 hex digits of SHA-256 of the decimal modulus: the engine prints it at start for each key
          (`>> RSA key 1: ... (fingerprint ...)`), client/tools/set_rsa_key.py prints it in the build log.

Then: CHAOS_RSA_KEY_FILE=<path> in /etc/chaos/chaos.env (config.lua: rsaKeyFile = os.getenv("CHAOS_RSA_KEY_FILE") or
"key.pem", written by prod_config.py). Several files separated by commas are all accepted (a rotation: the new key
first). This tool never prints, copies or uploads the private key.
"""
import argparse
import base64
import hashlib
import os
import re
import shutil
import subprocess
import sys
import tempfile

# the public default open-server modulus (stock key.pem and every stock client): its private key is public knowledge
PUBLIC_DEFAULT_N = int(
    '1091201329673994292788609605089955415282375029027981291234687579'
    '3726629149257644633073969600111060390723088861007265581882535850'
    '3429057592827629436413108566029093628212635953836686562675849720'
    '6207862794310902180176810615217550567108238764764442605581471797'
    '07119674283982419152118103759076030616683978566631413')
BITS = 1024
EXPONENT = 65537


def fingerprint(n):
    """the first 16 hex digits of SHA-256 of the decimal modulus (engine patch 0046, set_rsa_key.py)"""
    return hashlib.sha256(str(int(n)).encode('ascii')).hexdigest()[:16]


def _der_item(data, pos):
    """(tag, value bytes, next position) of the DER item at pos"""
    if pos + 2 > len(data):
        raise ValueError('truncated DER')
    tag, length = data[pos], data[pos + 1]
    pos += 2
    if length & 0x80:
        count = length & 0x7f
        if count == 0 or count > 4 or pos + count > len(data):
            raise ValueError('bad DER length')
        length = int.from_bytes(data[pos:pos + count], 'big')
        pos += count
    if pos + length > len(data):
        raise ValueError('truncated DER')
    return tag, data[pos:pos + length], pos + length


def read_key(path):
    """(n, e, pkcs1) of a PEM private key file: PKCS#1 'RSA PRIVATE KEY' (what the engine reads) or PKCS#8"""
    with open(path, 'rb') as f:
        text = f.read().decode('ascii', 'replace')
    m = re.search(r'-----BEGIN (RSA )?PRIVATE KEY-----(.*?)-----END (RSA )?PRIVATE KEY-----', text, re.S)
    if not m:
        raise ValueError('%s: no PEM private key' % path)
    der = base64.b64decode(''.join(m.group(2).split()))
    pkcs1 = bool(m.group(1))
    tag, body, _ = _der_item(der, 0)
    if tag != 0x30:
        raise ValueError('%s: not a DER sequence' % path)
    if not pkcs1:
        # PrivateKeyInfo: version, algorithm, OCTET STRING with the PKCS#1 key
        _, _, pos = _der_item(body, 0)
        _, _, pos = _der_item(body, pos)
        tag, inner, _ = _der_item(body, pos)
        if tag != 0x04:
            raise ValueError('%s: not an RSA PKCS#8 key' % path)
        tag, body, _ = _der_item(inner, 0)
    _, _, pos = _der_item(body, 0)          # version
    tag, n, pos = _der_item(body, pos)
    tag2, e, _ = _der_item(body, pos)
    if tag != 0x02 or tag2 != 0x02:
        raise ValueError('%s: not an RSA key' % path)
    return int.from_bytes(n, 'big'), int.from_bytes(e, 'big'), pkcs1


def in_git_tree(path):
    d = os.path.dirname(os.path.abspath(path))
    while True:
        if os.path.exists(os.path.join(d, '.git')):
            return True
        parent = os.path.dirname(d)
        if parent == d:
            return False
        d = parent


def problems(path, owner=None):
    """what is wrong with a key file for the engine (empty list: good)"""
    out = []
    try:
        n, e, pkcs1 = read_key(path)
    except (OSError, ValueError) as err:
        return [str(err)]
    if not pkcs1:
        out.append('not a PKCS#1 "BEGIN RSA PRIVATE KEY" file (the engine reads only that): '
                   'openssl rsa -traditional -in FILE -out NEW')
    if n.bit_length() != BITS:
        out.append('the key has %d bits; the 10.98 login needs exactly %d' % (n.bit_length(), BITS))
    if e != EXPONENT:
        out.append('the public exponent is %d; the client uses %d' % (e, EXPONENT))
    if n == PUBLIC_DEFAULT_N:
        out.append('this is the PUBLIC DEFAULT open-server key: its private key is public, anyone can read logins')
    st = os.stat(path)
    if os.name == 'posix' and st.st_mode & 0o077:
        out.append('mode %o: group or others can read it (chmod 600)' % (st.st_mode & 0o777))
    if in_git_tree(path):
        out.append('the file is inside a git work tree: move it out (e.g. /etc/chaos/rsa/)')
    if owner and os.name == 'posix':
        import pwd
        try:
            uid = pwd.getpwnam(owner).pw_uid
        except KeyError:
            out.append('no user %s' % owner)
        else:
            if st.st_uid != uid:
                out.append('owned by uid %d, not %s (chown %s %s)' % (st.st_uid, owner, owner, path))
    return out


def generate(out, owner=None, openssl='openssl'):
    out = os.path.abspath(out)
    if in_git_tree(out):
        raise SystemExit('refused: %s is inside a git work tree; keep the private key out of every repository' % out)
    if os.path.exists(out):
        raise SystemExit('refused: %s exists (a new key takes a new file name; see "Rotation" in server/README.md)' % out)
    if not shutil.which(openssl):
        raise SystemExit('openssl not found (apt install openssl)')
    folder = os.path.dirname(out)
    made = not os.path.isdir(folder)
    os.makedirs(folder, mode=0o700, exist_ok=True)
    old = os.umask(0o077)
    try:
        fd, tmp = tempfile.mkstemp(prefix='.rsa-', dir=folder)
        os.close(fd)
        try:
            ok = False
            for extra in (['-traditional'], []):   # OpenSSL 3 writes PKCS#8 unless -traditional; 1.1 has no flag
                r = subprocess.run([openssl, 'genrsa'] + extra + ['-out', tmp, str(BITS)],
                                   stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
                if r.returncode == 0 and read_key(tmp)[2]:
                    ok = True
                    break
            if not ok:
                raise SystemExit('openssl genrsa failed: %s' % r.stderr.decode('utf-8', 'replace').strip())
            os.chmod(tmp, 0o600)
            if owner:
                shutil.chown(tmp, owner, owner)
            os.link(tmp, out)              # never replaces an existing file
        finally:
            os.unlink(tmp)
    finally:
        os.umask(old)
    if owner and made:
        shutil.chown(folder, owner, owner)   # only a folder this run made (never /etc/chaos itself)
    n, _, _ = read_key(out)
    left = problems(out, owner)
    if left:
        raise SystemExit('the new key has problems: ' + '; '.join(left))
    return n


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    sub = ap.add_subparsers(dest='cmd', required=True)
    g = sub.add_parser('gen', help='make a new 1024-bit key file (mode 600)')
    g.add_argument('--out', required=True)
    g.add_argument('--owner', help='user that owns the file (the engine runs as chaos); needs root')
    p = sub.add_parser('public', help='print the public modulus (decimal) and its fingerprint')
    p.add_argument('--key', required=True)
    c = sub.add_parser('check', help='check a key file for the engine')
    c.add_argument('--key', required=True)
    c.add_argument('--owner')
    f = sub.add_parser('fingerprint', help='fingerprint of a decimal modulus')
    f.add_argument('modulus')
    a = ap.parse_args(argv)

    if a.cmd == 'gen':
        n = generate(a.out, a.owner)
        print('wrote %s (1024 bits, mode 600%s)' % (os.path.abspath(a.out), ', owner ' + a.owner if a.owner else ''))
        print('fingerprint: %s' % fingerprint(n))
        print('public modulus (GitHub secret CHAOS_RSA_PUBLIC; public, not secret):')
        print(n)
        if not a.owner and os.name == 'posix' and os.geteuid() == 0:
            print('note: the file belongs to root; the engine runs as chaos: chown chaos:chaos %s' % a.out)
        print('next: CHAOS_RSA_KEY_FILE=%s in /etc/chaos/chaos.env, a client built with CHAOS_RSA_PUBLIC, then a '
              'restart (docs/SECURITY_CHECKLIST.md)' % os.path.abspath(a.out))
        return 0
    if a.cmd == 'public':
        n, _, _ = read_key(a.key)
        if n == PUBLIC_DEFAULT_N:
            print('WARNING: this is the public default open-server key', file=sys.stderr)
        print('fingerprint: %s' % fingerprint(n))
        print(n)
        return 0
    if a.cmd == 'check':
        left = problems(a.key, a.owner)
        for line in left:
            print('PROBLEM: %s' % line)
        if left:
            return 1
        print('ok: %s (fingerprint %s)' % (a.key, fingerprint(read_key(a.key)[0])))
        return 0
    if not re.fullmatch(r'\d{300,320}', a.modulus.strip()):
        raise SystemExit('MODULUS must be the decimal modulus (about 309 digits)')
    print(fingerprint(int(a.modulus.strip())))
    return 0


if __name__ == '__main__':
    sys.exit(main())
