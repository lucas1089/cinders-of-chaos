#!/usr/bin/env python3
"""Write the website's account API URL into an assembled client's init.lua (Services.account, base patch 0050).

  python3 -I client/tools/set_account_api.py GAME_DIR https://www.example.org/chaos_client_api.php
  python3 -I client/tools/set_account_api.py GAME_DIR ""            # off: no looks from the site, no creation

The character select (overlay module client_chaos_charselect) reads the wings, aura and shader of each character
there, and its "Create character" window creates characters through it (website/README.md "Client API",
docs/LAUNCH.md). Only an https:// URL ending in chaos_client_api.php is written; --allow-http also takes
http://127.0.0.1[:port]/... (a local test site; the client itself refuses plain http to any other host).
Idempotent: a second run with the same URL changes nothing.
"""
import argparse
import os
import re
import sys


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('game_dir')
    ap.add_argument('url')
    ap.add_argument('--allow-http', action='store_true', help='http://127.0.0.1 (local tests only)')
    a = ap.parse_args()
    if a.url and not re.fullmatch(r'https://[A-Za-z0-9.-]+(:\d+)?/([A-Za-z0-9._~-]+/)*chaos_client_api\.php', a.url):
        if not (a.allow_http and re.fullmatch(r'http://(127\.0\.0\.1|localhost)(:\d+)?/([A-Za-z0-9._~-]+/)*chaos_client_api\.php', a.url)):
            sys.exit('URL: https://<site>/chaos_client_api.php (or "" to turn it off)')
    path = os.path.join(a.game_dir, 'init.lua')
    text = open(path, encoding='utf-8').read()
    new, n = re.subn(r'(\n  account = )"[^"\n]*"(,\n)', lambda m: m.group(1) + '"' + a.url + '"' + m.group(2), text, count=1)
    if n != 1:
        sys.exit('init.lua has no Services.account line (is base patch 0050 applied?)')
    if new != text:
        open(path, 'w', encoding='utf-8', newline='').write(new)
    print('%s: Services.account = "%s"' % (path, a.url))
    return 0


if __name__ == '__main__':
    sys.exit(main())
