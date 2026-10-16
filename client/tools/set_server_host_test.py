#!/usr/bin/env python3
"""Tests of set_server_host.py: the host, the site URL (account API, login-screen services), idempotence, validation.

  python3 -I client/tools/set_server_host_test.py
"""
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import set_server_host as S  # noqa: E402

# the parts of init.lua (base patches 0001 and 0050) the tool edits, as assemble_client.sh leaves them
INIT = '''Services = {
  website = "",
  status = { "http://127.0.0.1:8090/clientservices" },
  minimap = "",
  account = "",
  update = {
    manifest = "",
  }
}

Servers = {
  LocalTestServ = {
    name = "Cinders of Chaos",
    host = "127.0.0.1",
    port = 7171,
    clientServicesLink = "http://127.0.0.1:8090/clientservices"
  }
}
'''
fails = 0


def check(cond, what):
    global fails
    if not cond:
        print('FAIL ' + what)
        fails += 1


# host only: as before
t = S.apply(INIT, 'play.example.org')
check('host = "play.example.org"' in t, 'the login host')
check(t.count('"http://play.example.org:8090/clientservices"') == 2, 'both services URLs on the host')
check('account = ""' in t, 'no site: the account API stays off')
check(S.apply(t, 'play.example.org') == t, 'idempotent')

# with the site: account API and services through the site over HTTPS
site = S.site_url('https://example.org/')
check(site == 'https://example.org', 'trailing slash dropped')
t2 = S.apply(INIT, 'play.example.org', site)
check('account = "https://example.org/chaos_client_api.php"' in t2, 'Services.account written')
check(t2.count('"https://example.org/clientservices"') == 2, 'services through the site')
check('host = "play.example.org"' in t2, 'the game host stays the game host')
check(S.apply(t2, 'play.example.org', site) == t2, 'idempotent with the site')
check(S.apply(t2, 'play.example.org') == t, 'run again without a site: back to the host')
check(S.apply(t2, 'play.example.org', S.site_url('https://other.example.org/game')).count(
    '"https://other.example.org/game/clientservices"') == 2, 'a site under a path, rewritten again')
check('account = "http://127.0.0.1/chaos_client_api.php"' in S.apply(INIT, '127.0.0.1', S.site_url('http://127.0.0.1')),
      'http only for a local test site')
check(S.site_url('') == '' and S.site_url('  ') == '', 'empty: no site (the default)')

# validation
for bad in ('http://example.org', 'ftp://example.org', 'example.org', 'https://example.org/?x=1', 'https://ex ample.org',
            'https://example.org/"x', 'https://example.org#top', 'javascript:alert(1)'):
    try:
        S.site_url(bad)
        check(False, 'refused: ' + bad)
    except ValueError:
        pass
for bad in ('', 'a b', 'x"y'):
    try:
        S.apply(INIT, bad)
        check(False, 'host refused: %r' % bad)
    except ValueError:
        pass
try:
    S.apply(INIT.replace('  account = "",\n', ''), 'h', site)
    check(False, 'a client without patch 0050 is refused')
except ValueError:
    pass

# the command line, as the workflow calls it
with tempfile.TemporaryDirectory() as d:
    with open(os.path.join(d, 'init.lua'), 'w', encoding='utf-8') as f:
        f.write(INIT)
    tool = os.path.join(HERE, 'set_server_host.py')
    r = subprocess.run([sys.executable, '-I', tool, d, 'play.example.org', '--site-url', 'https://example.org'],
                       capture_output=True, text=True)
    check(r.returncode == 0, 'command line with a site: ' + r.stderr)
    r = subprocess.run([sys.executable, '-I', tool, d, 'play.example.org', '--site-url', ''], capture_output=True, text=True)
    check(r.returncode == 0, 'command line with an empty site (the workflow default)')
    check('account = ""' in open(os.path.join(d, 'init.lua'), encoding='utf-8').read(), 'empty site: account off again')
    r = subprocess.run([sys.executable, '-I', tool, d, 'play.example.org', '--site-url', 'http://example.org'],
                       capture_output=True, text=True)
    check(r.returncode != 0, 'command line refuses plain http')

if fails:
    sys.exit('%d failure(s)' % fails)
print('set_server_host_test: OK')
