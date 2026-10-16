#!/usr/bin/env python3
"""Point an assembled client's init.lua at a game server host and, optionally, the website (idempotent).

  python3 -I client/tools/set_server_host.py GAME_DIR HOST [--site-url URL]

init.lua (base patch 0001) has the login server entry `Servers.LocalTestServ.host` (port 7171) and the login-screen
services URL `http://<host>:8090/clientservices` twice (Services.status and the server entry's clientServicesLink);
all three point at 127.0.0.1 after client/tools/assemble_client.sh. This writes HOST into the three places and keeps the
ports. HOST is a DNS name or an IPv4 address.

--site-url URL (the website, e.g. https://example.org; "" = none, the default):
  * Services.account = "URL/chaos_client_api.php" (base patch 0050: the character select's looks and "Create
    character"; empty keeps both off);
  * the two login-screen services URLs = "URL/clientservices": the site's web server forwards that path to
    server/tools/clientservices.py on the game server (tools/linux/server/README.txt "Login screen services"), so the
    client asks over HTTPS and port 8090 stays closed.
  URL must be https:// (http:// only for 127.0.0.1 or localhost, a local test site), with no query, fragment, quotes or
  spaces; a trailing slash is dropped.
Used by .github/workflows/windows-package.yml (inputs server_host and site_url) for the client downloads of a release;
the full Windows package keeps 127.0.0.1 and no site.
"""
import argparse
import os
import re
import sys

HOST_RE = r'[A-Za-z0-9](?:[A-Za-z0-9.-]{0,251}[A-Za-z0-9])?'
SERVICES_RE = r'"[A-Za-z][A-Za-z0-9+.-]*://[^"\s]*/clientservices"'


def site_url(value):
    """the validated site URL without a trailing slash, or '' for none"""
    url = (value or '').strip()
    if url == '':
        return ''
    url = url.rstrip('/')
    m = re.fullmatch(r'(https?)://(' + HOST_RE + r')(:\d{1,5})?(/[A-Za-z0-9._~%!$&()*+,;=:@/-]*)?', url)
    if not m:
        raise ValueError('--site-url must look like https://example.org (no query, fragment, quotes or spaces)')
    scheme, host = m.group(1), m.group(2).lower()
    if scheme == 'http' and host not in ('127.0.0.1', 'localhost'):
        raise ValueError('--site-url must be https:// (http:// only for 127.0.0.1 or localhost)')
    return url


def apply(text, host, site=''):
    if not re.fullmatch(HOST_RE, host):
        raise ValueError('HOST must be a DNS name or an IPv4 address (letters, digits, dots, hyphens)')
    servers = re.search(r'\nServers = \{\n.*?\n\}\n', text, re.S)
    if not servers:
        raise ValueError('init.lua: no Servers = { ... } block (is base patch 0001 applied?)')
    block, n = re.subn(r'(\n    host = ")[^"]*(")', lambda m: m.group(1) + host + m.group(2), servers.group(0), count=1)
    if n != 1:
        raise ValueError('init.lua: no host = "..." line in Servers')
    text = text[:servers.start()] + block + text[servers.end():]
    services = '"%s/clientservices"' % site if site else '"http://%s:8090/clientservices"' % host
    text, n = re.subn(SERVICES_RE, lambda m: services, text)
    if n != 2:
        raise ValueError('init.lua: expected 2 clientservices URLs (Services.status, clientServicesLink), found %d' % n)
    account = '%s/chaos_client_api.php' % site if site else ''
    text, n = re.subn(r'(\n  account = ")[^"]*(")', lambda m: m.group(1) + account + m.group(2), text, count=1)
    if n != 1:
        raise ValueError('init.lua: no account = "..." line in Services (is base patch 0050 applied?)')
    return text


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('game')
    parser.add_argument('host')
    parser.add_argument('--site-url', default='')
    args = parser.parse_args(argv)
    try:
        site = site_url(args.site_url)
        path = os.path.join(args.game, 'init.lua')
        text = apply(open(path, encoding='utf-8').read(), args.host, site)
    except ValueError as e:
        sys.exit(str(e))
    open(path, 'w', encoding='utf-8', newline='').write(text)
    print('%s: server host %s (ports unchanged)%s' % (path, args.host,
          ', site %s (account API, login-screen services)' % site if site else ', no site'))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
