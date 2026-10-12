#!/usr/bin/env python3
"""Write the signed updater's settings into an assembled client's init.lua (Services.update, base patch 0031).

  python3 -I client/tools/set_update_config.py GAME_DIR --manifest https://site/updates/live/manifest.json \
      --public-key <64 hex> [--package N] [--download URL] [--required]

Only the public key goes into the client; the private key never leaves the operator's machine
(docs/LAUNCH.md "Client updates"). An http:// manifest URL is refused unless --allow-http (local tests only).
"""
import argparse, os, re, sys


def set_field(text, name, value):
    pat = re.compile(r'(\n    %s = )[^\n]*?(,?\n)' % re.escape(name))
    block = re.search(r'\n  update = \{\n(.*?)\n  \}', text, re.S)
    if not block:
        sys.exit('init.lua has no Services.update block (is base patch 0031 applied?)')
    inner = block.group(0)
    new_inner, n = pat.subn(lambda m: m.group(1) + value + m.group(2), inner, count=1)
    if n != 1:
        sys.exit(f'init.lua: Services.update.{name} not found')
    return text.replace(inner, new_inner, 1)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('game_dir')
    ap.add_argument('--manifest', required=True)
    ap.add_argument('--public-key', required=True)
    ap.add_argument('--package', type=int)
    ap.add_argument('--download', default=None)
    ap.add_argument('--required', action='store_true')
    ap.add_argument('--allow-http', action='store_true', help='local tests only')
    a = ap.parse_args()
    if not re.fullmatch(r'https://[A-Za-z0-9.-]+(:\d+)?/[A-Za-z0-9._~/-]*manifest\.json', a.manifest):
        if not (a.allow_http and re.fullmatch(r'http://[A-Za-z0-9.-]+(:\d+)?/[A-Za-z0-9._~/-]*manifest\.json', a.manifest)):
            sys.exit('--manifest: an https:// URL ending in manifest.json')
    if not re.fullmatch(r'[0-9a-f]{64}', a.public_key):
        sys.exit('--public-key: 64 lowercase hex digits (make_update_manifest.py keygen prints it)')
    if a.download is not None and a.download and not re.fullmatch(r'https?://[^\s"\\]+', a.download):
        sys.exit('--download: a URL')
    path = os.path.join(a.game_dir, 'init.lua')
    text = open(path, encoding='utf-8').read()
    text = set_field(text, 'manifest', '"%s"' % a.manifest)
    text = set_field(text, 'publicKey', '"%s"' % a.public_key)
    if a.package is not None:
        text = set_field(text, 'package', str(a.package))
    if a.download is not None:
        text = set_field(text, 'download', '"%s"' % a.download)
    text = set_field(text, 'required', 'true' if a.required else 'false')
    open(path, 'w', encoding='utf-8').write(text)
    print(f'{path}: updater on, manifest {a.manifest}, key {a.public_key[:16]}...')


if __name__ == '__main__':
    main()
