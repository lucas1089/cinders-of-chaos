#!/usr/bin/env python3
"""Point an assembled client's init.lua at a game server host (idempotent).

  python3 -I client/tools/set_server_host.py GAME_DIR HOST

init.lua (base patch 0001) has the login server entry `Servers.LocalTestServ.host` (port 7171) and the login-screen
services URL `http://<host>:8090/clientservices` twice (Services.status and the server entry's clientServicesLink);
all three point at 127.0.0.1 after client/tools/assemble_client.sh. This writes HOST into the three places and keeps the
ports. HOST is a DNS name or an IPv4 address. Used by .github/workflows/windows-package.yml (input server_host) for the
client downloads of a release; the full Windows package keeps 127.0.0.1.
"""
import os
import re
import sys


def main(argv):
    if len(argv) != 2:
        print(__doc__)
        return 2
    game, host = argv
    if not re.fullmatch(r'[A-Za-z0-9](?:[A-Za-z0-9.-]{0,251}[A-Za-z0-9])?', host):
        sys.exit('HOST must be a DNS name or an IPv4 address (letters, digits, dots, hyphens)')
    path = os.path.join(game, 'init.lua')
    text = open(path, encoding='utf-8').read()
    servers = re.search(r'\nServers = \{\n.*?\n\}\n', text, re.S)
    if not servers:
        sys.exit('init.lua: no Servers = { ... } block (is base patch 0001 applied?)')
    block, n = re.subn(r'(\n    host = ")[^"]*(")', lambda m: m.group(1) + host + m.group(2), servers.group(0), count=1)
    if n != 1:
        sys.exit('init.lua: no host = "..." line in Servers')
    text = text[:servers.start()] + block + text[servers.end():]
    text, n = re.subn(r'http://[^/:"]+:8090/clientservices', 'http://%s:8090/clientservices' % host, text)
    if n != 2:
        sys.exit('init.lua: expected 2 clientservices URLs (Services.status, clientServicesLink), found %d' % n)
    open(path, 'w', encoding='utf-8', newline='').write(text)
    print('%s: server host %s (ports unchanged)' % (path, host))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
