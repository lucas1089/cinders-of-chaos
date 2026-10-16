#!/usr/bin/env python3
"""Write the game server's public RSA login key into an assembled client's init.lua (base patch 0072; idempotent).

  python3 -I client/tools/set_rsa_key.py GAME_DIR --modulus DECIMAL
  python3 -I client/tools/set_rsa_key.py GAME_DIR --from-env CHAOS_RSA_PUBLIC [--allow-default]
  python3 -I client/tools/set_rsa_key.py GAME_DIR --clear          # back to the public default key (local tests)

The modulus is what `server/tools/rsa_key.py public --key FILE` prints on the game server (decimal, about 309 digits;
public, not secret). It goes into `Services.rsa` of init.lua; gamelib then encrypts both logins with it instead of the
public default open-server key (server/README.md "Login encryption (RSA, XTEA)"). init.lua is never changed by the
signed updater, so updates keep the key. Checks: decimal, exactly 1024 bits, odd, not the public default key. Prints
the key's fingerprint (the same the engine prints at start for each of its keys) so the build log can be compared.

--from-env NAME reads the value from that environment variable (windows-package.yml: the secret or variable
CHAOS_RSA_PUBLIC). An empty variable is an error unless --allow-default, which then leaves the default key in place
and prints a warning (the full Windows package for local play, or a run with the input allow_dev_key).
"""
import argparse
import hashlib
import os
import re
import sys

PUBLIC_DEFAULT_N = int(
    '1091201329673994292788609605089955415282375029027981291234687579'
    '3726629149257644633073969600111060390723088861007265581882535850'
    '3429057592827629436413108566029093628212635953836686562675849720'
    '6207862794310902180176810615217550567108238764764442605581471797'
    '07119674283982419152118103759076030616683978566631413')
FIELD_RE = re.compile(r'(\n  rsa = )"[^"\n]*"(\n\})')


def fingerprint(n):
    """the first 16 hex digits of SHA-256 of the decimal modulus (engine patch 0046, server/tools/rsa_key.py)"""
    return hashlib.sha256(str(int(n)).encode('ascii')).hexdigest()[:16]


def parse_modulus(value):
    v = (value or '').strip()
    if not re.fullmatch(r'\d{300,320}', v):
        raise ValueError('the modulus must be decimal digits only (about 309; server/tools/rsa_key.py public)')
    n = int(v)
    if n.bit_length() != 1024:
        raise ValueError('the modulus has %d bits; the 10.98 login needs a 1024-bit key' % n.bit_length())
    if n % 2 == 0:
        raise ValueError('the modulus is even: not an RSA modulus')
    if n == PUBLIC_DEFAULT_N:
        raise ValueError('this is the public default open-server key; use the game server\'s own key')
    return n


def apply(text, n):
    """init.lua text with Services.rsa set to n (None: empty, the default key)"""
    value = '' if n is None else str(n)
    new, count = FIELD_RE.subn(lambda m: m.group(1) + '"' + value + '"' + m.group(2), text, count=1)
    if count != 1:
        raise ValueError('init.lua: no Services.rsa field (is base patch 0072 applied?)')
    return new


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('game_dir')
    src = ap.add_mutually_exclusive_group(required=True)
    src.add_argument('--modulus')
    src.add_argument('--from-env', metavar='NAME')
    src.add_argument('--clear', action='store_true')
    ap.add_argument('--allow-default', action='store_true',
                    help='with --from-env: an empty variable keeps the public default key (a warning)')
    a = ap.parse_args(argv)
    path = os.path.join(a.game_dir, 'init.lua')
    with open(path, encoding='utf-8', newline='') as f:
        text = f.read()
    crlf = '\r\n' in text
    text = text.replace('\r\n', '\n')
    n = None
    if a.clear:
        print('init.lua: Services.rsa cleared: the public default key (local test servers only)')
    else:
        value = a.modulus if a.modulus is not None else os.environ.get(a.from_env, '')
        if not value.strip():
            if not a.allow_default:
                print('error: %s is empty: set the secret CHAOS_RSA_PUBLIC (server/tools/rsa_key.py public), or run '
                      'with allow_dev_key for a test build' % a.from_env, file=sys.stderr)
                return 1
            print('WARNING: no %s: this client uses the PUBLIC DEFAULT login key. Anyone on the path can read its '
                  'logins. Never ship it to players.' % a.from_env)
        else:
            try:
                n = parse_modulus(value)
            except ValueError as err:
                print('error: %s' % err, file=sys.stderr)
                return 1
            print('init.lua: Services.rsa set, fingerprint %s (the engine prints the same for its key)' % fingerprint(n))
    try:
        text = apply(text, n)
    except ValueError as err:
        print('error: %s' % err, file=sys.stderr)
        return 1
    if crlf:
        text = text.replace('\n', '\r\n')
    with open(path, 'w', encoding='utf-8', newline='') as f:
        f.write(text)
    return 0


if __name__ == '__main__':
    sys.exit(main())
