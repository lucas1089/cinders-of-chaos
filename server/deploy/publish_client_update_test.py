#!/usr/bin/env python3
"""Tests for server/deploy/publish_client_update.sh (docs/LAUNCH.md "Publishing a client update").

Runs the real script against a small synthetic client package (the layout of CindersOfChaos-Client-Windows.zip:
CindersOfChaos-Client/ with init.lua, BUILD_INFO.txt, modules/, mods/, data/things/1098/, the exe), a temporary site
folder and a throwaway key pair made in a temporary folder outside the repository. Checks: a local zip and a release
tag (curl is a stub that hands out the zip for the GitHub URL) publish a manifest that make_update_manifest.py verify
accepts, with the tag's number as version and the package's client build as min_package; the exe is not in it; the
same version again, a package of another key, a wrong public key setting, a zip with "..", an absolute path or a link,
a too small download and a zip with no client folder are refused and publish nothing; the web server check against a
local HTTP server (right headers and Range: ok; a plain static server: warnings, exit still 0).

usage: python3 -I server/deploy/publish_client_update_test.py
"""
import http.server
import json
import os
import shutil
import stat
import subprocess
import sys
import tempfile
import threading
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(HERE, 'publish_client_update.sh')
TOOL = os.path.join(HERE, '..', '..', 'client', 'tools', 'make_update_manifest.py')

failures = 0


def check(cond, label):
    global failures
    if not cond:
        failures += 1
        print('FAIL', label)


INIT = '''Services = {
  update = {
    manifest = "%s",
    publicKey = "%s",
    package = %d,
    required = false,
    download = ""
  }
}
'''


def make_zip(path, public, url, package=11, build=11, extra=None, links=False):
    with zipfile.ZipFile(path, 'w') as z:
        root = 'CindersOfChaos-Client/'
        z.writestr(root + 'init.lua', INIT % (url, public, package))
        z.writestr(root + 'BUILD_INFO.txt', 'chaos commit: abc\r\nserver host: 127.0.0.1\r\nclient build: %d\r\n' % build)
        z.writestr(root + 'Chaos.exe', b'MZ' + b'\0' * 100)
        z.writestr(root + 'modules/client_x/x.lua', 'print(1)\n')
        z.writestr(root + 'mods/readme.txt', 'mods\n')
        z.writestr(root + 'data/things/1098/Tibia.dat', os.urandom(4000))
        z.writestr(root + 'data/things/1098/Tibia.spr', os.urandom(70000))
        for name, data in (extra or {}).items():
            z.writestr(name, data)
        if links:
            info = zipfile.ZipInfo(root + 'modules/evil')
            info.external_attr = (stat.S_IFLNK | 0o777) << 16
            z.writestr(info, '/etc/passwd')


class Handler(http.server.SimpleHTTPRequestHandler):
    """static files with the headers of website/overlay/updates/.htaccess and single Range requests"""
    proper = True

    def log_message(self, *a):
        pass

    def end_headers(self):
        if self.proper:
            p = self.path.split('?')[0]
            if p.endswith('manifest.json'):
                self.send_header('Cache-Control', 'no-cache')
            else:
                self.send_header('Cache-Control', 'public, max-age=31536000, immutable')
        super().end_headers()

    def guess_type(self, path):
        return 'application/json' if str(path).endswith('.json') else 'application/octet-stream'

    def do_GET(self):
        rng = self.headers.get('Range')
        if not (self.proper and rng and rng.startswith('bytes=')):
            return super().do_GET()
        path = self.translate_path(self.path.split('?')[0])
        if not os.path.isfile(path):
            return self.send_error(404)
        a, b = rng[6:].split('-')
        data = open(path, 'rb').read()
        part = data[int(a):int(b) + 1]
        self.send_response(206)
        self.send_header('Content-Range', 'bytes %s-%d/%d' % (a, int(a) + len(part) - 1, len(data)))
        self.send_header('Content-Length', str(len(part)))
        self.send_header('Content-Type', 'application/octet-stream')
        self.end_headers()
        self.wfile.write(part)


def serve(root, proper):
    handler = type('H', (Handler,), {'proper': proper})
    srv = http.server.ThreadingHTTPServer(('127.0.0.1', 0),
                                          lambda *a, **k: handler(*a, directory=root, **k))
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    return srv


def main():
    with tempfile.TemporaryDirectory() as tmp:
        keys = os.path.join(tmp, 'keys')
        os.makedirs(keys)
        key = os.path.join(keys, 'update-key.hex')
        r = subprocess.run([sys.executable, '-I', TOOL, 'keygen', '--private', key], capture_output=True, text=True)
        check(r.returncode == 0, 'keygen: ' + r.stderr)
        public = subprocess.run([sys.executable, '-I', TOOL, 'pubkey', '--private', key], capture_output=True,
                                text=True).stdout.strip()
        check(len(public) == 64, 'pubkey prints the public key')
        site = os.path.join(tmp, 'site')
        os.makedirs(site)
        live = os.path.join(site, 'updates', 'live')
        work = os.path.join(tmp, 'work')
        os.makedirs(work)
        stub = os.path.join(tmp, 'stub')
        os.makedirs(stub)
        srv = serve(site, True)
        url = 'http://127.0.0.1:%d/updates/live/manifest.json' % srv.server_address[1]
        zips = os.path.join(tmp, 'zips')
        os.makedirs(zips)
        good = os.path.join(zips, 'client.zip')
        make_zip(good, public, url)

        # curl stub: the GitHub release URL hands out $STUB_ZIP, everything else goes to the real curl
        real_curl = shutil.which('curl')
        with open(os.path.join(stub, 'curl'), 'w') as f:
            f.write('''#!/usr/bin/env bash
out="" url=""
for a in "$@"; do
  [ "$prev" = -o ] && out=$a
  case $a in https://github.com/*) url=$a ;; esac
  prev=$a
done
if [ -n "$url" ]; then
  echo "$url" >> "$STUB_DIR/urls"
  [ -n "${STUB_ZIP:-}" ] || exit 22
  cp "$STUB_ZIP" "$out"
  exit 0
fi
exec %s "$@"
''' % real_curl)
        os.chmod(os.path.join(stub, 'curl'), 0o755)

        def run(*args, extra=None):
            e = dict(os.environ, CHAOS_SITE_DIR=site, CHAOS_UPDATE_KEY=key, CHAOS_UPDATE_MIN_MB='0',
                     CHAOS_WORK_DIR=work, CHAOS_UPDATE_PUBLIC_FILE=os.path.join(keys, 'none.pub'),
                     STUB_DIR=stub, PATH=stub + os.pathsep + os.environ.get('PATH', ''))
            e.pop('CHAOS_UPDATE_PUBLIC', None)
            e.pop('CHAOS_UPDATE_URL', None)
            e.update(extra or {})
            return subprocess.run(['bash', SCRIPT] + list(args), env=e, capture_output=True, text=True)

        def payload():
            return json.loads(json.load(open(os.path.join(live, 'manifest.json')))['payload'])

        def verify():
            return subprocess.run([sys.executable, '-I', TOOL, 'verify', live, '--public', public],
                                  capture_output=True, text=True).returncode == 0

        # a local zip, version given
        r = run('--version', '3', good)
        check(r.returncode == 0, 'local zip publishes: ' + r.stdout + r.stderr)
        check(verify(), 'the published manifest verifies')
        m = payload()
        check(m['version'] == 3 and m['min_package'] == 11, 'version 3, min_package = client build 11')
        paths = {f['path'] for f in m['files']}
        check('modules/client_x/x.lua' in paths and 'data/things/1098/Tibia.spr' in paths, 'modules and the pair')
        check(not any(p.endswith('.exe') or p in ('init.lua', 'BUILD_INFO.txt') for p in paths), 'no exe, no init.lua')
        check('zip: ' in r.stdout and 'sha256 ' in r.stdout, 'size and checksum printed')
        check('check: ok' in r.stdout, 'web server check ok with the right headers: ' + r.stdout)
        check(os.listdir(work) == [], 'the work folder is removed')

        # a release tag: the version is the tag's number
        r = run('winpkg-46', extra={'STUB_ZIP': good})
        check(r.returncode == 0, 'tag publishes: ' + r.stdout + r.stderr)
        urls = open(os.path.join(stub, 'urls')).read()
        check('https://github.com/lucas1089/cinders-of-chaos/releases/download/winpkg-46/'
              'CindersOfChaos-Client-Windows.zip' in urls, 'the release asset URL')
        check(payload()['version'] == 46 and verify(), 'tag winpkg-46 -> version 46, verifies')

        before = open(os.path.join(live, 'manifest.json')).read()

        def unchanged():
            return open(os.path.join(live, 'manifest.json')).read() == before

        r = run('winpkg-46', extra={'STUB_ZIP': good})
        check(r.returncode != 0 and 'not above the published 46' in r.stderr, 'same version again refused')
        r = run('winpkg-45', extra={'STUB_ZIP': good})
        check(r.returncode != 0, 'an older tag refused')
        r = run('winpkg-47')
        check(r.returncode != 0 and 'download failed' in r.stderr, 'a failed download refused')
        r = run('--version', '50', good, extra={'CHAOS_UPDATE_PUBLIC': '0' * 64})
        check(r.returncode != 0 and 'is not the one of' in r.stderr, 'a wrong public key setting refused')
        r = run('--version', '50', good, extra={'CHAOS_UPDATE_PUBLIC': public})
        check(r.returncode == 0 and payload()['version'] == 50, 'the right public key setting accepted')
        before = open(os.path.join(live, 'manifest.json')).read()

        other = os.path.join(zips, 'other.zip')
        make_zip(other, 'ab' * 32, url)
        r = run('--version', '60', other)
        check(r.returncode != 0 and 'would refuse' in r.stderr, 'a package of another key refused')
        mismatch = os.path.join(zips, 'mismatch.zip')
        make_zip(mismatch, public, url, package=12, build=11)
        r = run('--version', '60', mismatch)
        check(r.returncode != 0 and '--min-package' in r.stderr, 'build and package disagree: refused')
        r = run('--version', '60', '--min-package', '13', good)
        check(r.returncode != 0, 'min_package above the package refused')
        for name, data in (('../evil.txt', 'x'), ('/abs.txt', 'x'), ('CindersOfChaos-Client/../../e.txt', 'x')):
            bad = os.path.join(zips, 'bad.zip')
            make_zip(bad, public, url, extra={name: data})
            r = run('--version', '60', bad)
            check(r.returncode != 0 and 'refused' in r.stderr, 'unsafe entry %r refused' % name)
        check(not os.path.exists(os.path.join(tmp, 'evil.txt')), 'nothing written outside')
        bad = os.path.join(zips, 'link.zip')
        make_zip(bad, public, url, links=True)
        r = run('--version', '60', bad)
        check(r.returncode != 0 and 'link' in r.stderr, 'a link entry refused')
        empty = os.path.join(zips, 'empty.zip')
        with zipfile.ZipFile(empty, 'w') as z:
            z.writestr('readme.txt', 'nothing')
        r = run('--version', '60', empty)
        check(r.returncode != 0 and 'client folder' in r.stderr, 'no client folder refused')
        r = run('--version', '60', good, extra={'CHAOS_UPDATE_MIN_MB': '50'})
        check(r.returncode != 0 and 'below 50 MB' in r.stderr, 'a too small download refused')
        check(unchanged(), 'refused runs publish nothing')
        check(os.listdir(work) == [], 'refused runs leave no work folder')

        # a static server without the headers and without Range: warnings only, the publish stands
        srv.shutdown()
        plain = serve(site, False)
        purl = 'http://127.0.0.1:%d/updates/live/manifest.json' % plain.server_address[1]
        r = run('--version', '61', good, extra={'CHAOS_UPDATE_URL': purl})
        check(r.returncode == 0 and verify(), 'publish with a plain server: exit 0')
        check('WARN Cache-Control' in r.stdout and 'WARN a blob Range' in r.stdout, 'plain server warnings')
        r = run('--check-only', extra={'CHAOS_UPDATE_URL': purl})
        check(r.returncode == 1, '--check-only fails on warnings')
        plain.shutdown()

    print('publish_client_update_test: %d failures' % failures)
    return 1 if failures else 0


if __name__ == '__main__':
    sys.exit(main())
