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
Encrypted blobs (build 13): the client guard key comes from the environment or the CHAOS_CLIENT_KEY= line of
CHAOS_ENV; without it nothing is published; every published blob is ciphertext that decrypts to the signed content; a
packed package (the exe and chaos.pack) is opened with the key of a rotation pair that fits; a development pack, a
pack of another key and a min_package below 13 are refused; the old plain blobs are removed.
Sprite shards (pair 37): a single Tibia.spr in a package is published as its shard set (split and verified), a pack
that holds the shards publishes them as they are, one with both leaves the single file out, a broken spr is refused.

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
sys.path.insert(0, os.path.join(HERE, '..', '..', 'client', 'tools'))
sys.path.insert(0, os.path.join(HERE, '..', '..', 'client', 'tools', 'sprites'))
import pack_client  # noqa: E402
import spr_shards  # noqa: E402
import update_crypt  # noqa: E402

CLIENT_KEY = '7e' * 32   # throwaway client guard keys (never real ones)
OLD_KEY = '19' * 32

failures = 0
# what the shard set of spr_bytes() looks like in a manifest (3000 sprites in shards of 1024 or the default 16384)
SHARDED = {'data/things/1098/Tibia.sprshards', 'data/things/1098/Tibia.000.spr'}


def check(cond, label):
    global failures
    if not cond:
        failures += 1
        print('FAIL', label)


def spr_bytes(count=3000):
    """a small valid 10.98 .spr (u32 count): every fifth id empty, the rest a short random record"""
    table, body = [], bytearray()
    for i in range(count):
        if i % 5 == 4:
            table.append(0)
            continue
        table.append(8 + 4 * count + len(body))
        body += b'\xff\x00\xff' + (16).to_bytes(2, 'little') + os.urandom(16)
    return (bytes.fromhex('03d6bb57') + count.to_bytes(4, 'little') + b''.join(a.to_bytes(4, 'little') for a in table)
            + bytes(body))


INIT = '''Services = {
  update = {
    manifest = "%s",
    publicKey = "%s",
    package = %d,
%s    required = false,
    download = ""
  }
}
'''


def make_zip(path, public, url, package=13, build=13, extra=None, links=False, baseline=None, spr=None):
    with zipfile.ZipFile(path, 'w') as z:
        root = 'CindersOfChaos-Client/'
        line = '' if baseline is None else '    baseline = %d,\n' % baseline
        z.writestr(root + 'init.lua', INIT % (url, public, package, line))
        z.writestr(root + 'BUILD_INFO.txt', 'chaos commit: abc\r\nserver host: 127.0.0.1\r\nclient build: %d\r\n' % build)
        z.writestr(root + 'Chaos.exe', b'MZ' + b'\0' * 100)
        z.writestr(root + 'modules/client_x/x.lua', 'print(1)\n')
        z.writestr(root + 'mods/readme.txt', 'mods\n')
        z.writestr(root + 'data/things/1098/Tibia.dat', os.urandom(4000))
        z.writestr(root + 'data/things/1098/Tibia.spr', spr if spr is not None else spr_bytes())
        for name, data in (extra or {}).items():
            z.writestr(name, data)
        if links:
            info = zipfile.ZipInfo(root + 'modules/evil')
            info.external_attr = (stat.S_IFLNK | 0o777) << 16
            z.writestr(info, '/etc/passwd')


def make_packed_zip(path, tmp, public, url, key_hex=CLIENT_KEY, dev=False, package=13, baseline=None, shards=None):
    """the layout of a build-13 package: CindersOfChaos-Client/ with Chaos.exe and chaos.pack only. shards: None, a
    single Tibia.spr (builds 13, 14); 'only', the spr as a shard set (build 15, pair 37); 'both', the two"""
    tree = tempfile.mkdtemp(dir=tmp)
    line = '' if baseline is None else '    baseline = %d,\n' % baseline
    files = {'init.lua': (INIT % (url, public, package, line)).encode(), 'modules/client_x/x.lua': b'print(1)\n',
             'mods/readme.txt': b'mods\n', 'data/things/1098/Tibia.dat': os.urandom(4000),
             'data/things/1098/Tibia.spr': spr_bytes()}
    for rel, data in files.items():
        full = os.path.join(tree, rel)
        os.makedirs(os.path.dirname(full), exist_ok=True)
        open(full, 'wb').write(data)
    things = os.path.join(tree, 'data', 'things', '1098')
    if shards:
        spr_shards.split(os.path.join(things, 'Tibia.spr'), things, per_shard=1024, quiet=True)
        if shards == 'only':
            os.remove(os.path.join(things, 'Tibia.spr'))
    index = (open(os.path.join(things, 'Tibia.sprshards')).read() if shards else None)
    pack = pack_client.encrypt_pack(pack_client.build_zip(tree), bytes.fromhex(key_hex), is_dev=dev)
    with zipfile.ZipFile(path, 'w') as z:
        z.writestr('CindersOfChaos-Client/Chaos.exe', b'MZ' + b'\0' * 100)
        z.writestr('CindersOfChaos-Client/chaos.pack', pack)
    shutil.rmtree(tree)
    return index


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

        def run(*args, extra=None, drop=()):
            e = dict(os.environ, CHAOS_SITE_DIR=site, CHAOS_UPDATE_KEY=key, CHAOS_UPDATE_MIN_MB='0',
                     CHAOS_WORK_DIR=work, CHAOS_UPDATE_PUBLIC_FILE=os.path.join(keys, 'none.pub'),
                     CHAOS_CLIENT_KEY=CLIENT_KEY, CHAOS_ENV=os.path.join(keys, 'none.env'),
                     STUB_DIR=stub, PATH=stub + os.pathsep + os.environ.get('PATH', ''))
            e.pop('CHAOS_UPDATE_PUBLIC', None)
            e.pop('CHAOS_UPDATE_URL', None)
            e.update(extra or {})
            for k in drop:
                e.pop(k, None)
            r = subprocess.run(['bash', SCRIPT] + list(args), env=e, capture_output=True, text=True)
            check(CLIENT_KEY not in r.stdout + r.stderr and OLD_KEY not in r.stdout + r.stderr,
                  'the client key is never printed')
            return r

        def blobs_ok(key_hex=CLIENT_KEY):
            """every file of files/ is a blob of the manifest, ciphertext that decrypts to its signed content"""
            names = {f for _, _, fs in os.walk(os.path.join(live, 'files')) for f in fs}
            m = payload()
            if names != {f['blob'] for f in m['files']}:
                return False
            for f in m['files']:
                blob = os.path.join(live, 'files', f['blob'][:2], f['blob'])
                if open(blob, 'rb').read(4) != b'CHUB':
                    return False
                if update_crypt.decrypt_file(blob, bytes.fromhex(key_hex))[1] != f['sha256']:
                    return False
            return True

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
        check(m['version'] == 3 and m['min_package'] == 13, 'version 3, min_package = client build 13')
        check(m['encryption'] == 'chaos-blob-1' and blobs_ok(), 'encrypted blobs only, they decrypt to the content')
        paths = {f['path'] for f in m['files']}
        check('modules/client_x/x.lua' in paths and 'data/things/1098/Tibia.dat' in paths, 'modules and the dat')
        check(SHARDED <= paths and 'data/things/1098/Tibia.spr' not in paths,
              'the single spr is published as its shard set: ' + ' '.join(sorted(paths)))
        check('sprites: data/things/1098/Tibia.spr -> shard set' in r.stdout, 'the split is printed')
        check(not any(p.endswith('.exe') or p in ('init.lua', 'BUILD_INFO.txt') for p in paths), 'no exe, no init.lua')
        check('zip: ' in r.stdout and 'sha256 ' in r.stdout, 'size and checksum printed')
        check('check: ok' in r.stdout, 'web server check ok with the right headers: ' + r.stdout)
        check(os.listdir(work) == [], 'the work folder is removed')

        # a single spr that is no valid .spr: refused, nothing published
        before = open(os.path.join(live, 'manifest.json')).read()
        badspr = os.path.join(zips, 'badspr.zip')
        make_zip(badspr, public, url, spr=os.urandom(70000))
        r = run('--version', '4', badspr)
        check(r.returncode != 0 and 'cannot split' in r.stderr, 'a broken spr refused: ' + r.stderr)
        check(open(os.path.join(live, 'manifest.json')).read() == before, 'a broken spr publishes nothing')

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
        make_zip(mismatch, public, url, package=14, build=13)
        r = run('--version', '60', mismatch)
        check(r.returncode != 0 and '--min-package' in r.stderr, 'build and package disagree: refused')
        r = run('--version', '60', '--min-package', '14', good)
        check(r.returncode != 0, 'min_package above the package refused')
        old12 = os.path.join(zips, 'old12.zip')
        make_zip(old12, public, url, package=12, build=12)
        r = run('--version', '60', old12)
        check(r.returncode != 0 and 'only client build 13 or newer' in r.stderr, 'a build-12 package refused')
        r = run('--version', '60', '--min-package', '0', good)
        check(r.returncode != 0 and 'only client build 13 or newer' in r.stderr, 'min_package 0 refused')
        # no client guard key anywhere: nothing published (never a plain fallback)
        r = run('--version', '60', good, drop=('CHAOS_CLIENT_KEY',))
        check(r.returncode != 0 and 'no CHAOS_CLIENT_KEY' in r.stderr, 'no client key: refused')
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

        # build 13: the packed package (exe + chaos.pack), the key read from CHAOS_ENV like the game server's
        envfile = os.path.join(keys, 'chaos.env')
        with open(envfile, 'w') as f:
            f.write('CHAOS_DB_PASS=x\n# the client guard\nCHAOS_CLIENT_KEY="%s,%s"\nOTHER=1\n' % (OLD_KEY, CLIENT_KEY))
        packed = os.path.join(zips, 'packed.zip')
        make_packed_zip(packed, tmp, public, url)
        # a plain blob left by a publish before build 13
        old_plain = os.path.join(live, 'files', 'ab', 'ab' * 32)
        os.makedirs(os.path.dirname(old_plain), exist_ok=True)
        open(old_plain, 'w').write('print("plain module")')
        r = run('--version', '62', packed, extra={'CHAOS_UPDATE_URL': purl, 'CHAOS_ENV': envfile},
                drop=('CHAOS_CLIENT_KEY',))
        check(r.returncode == 0, 'a packed package publishes: ' + r.stdout + r.stderr)
        check('opened with key 2 of CHAOS_CLIENT_KEY' in r.stdout, 'the rotation key that opens the pack is used')
        m = payload()
        check(m['version'] == 62 and m['min_package'] == 13, 'packed: version 62, min_package 13 from init.lua')
        paths = {f['path'] for f in m['files']}
        check('modules/client_x/x.lua' in paths and SHARDED <= paths and 'data/things/1098/Tibia.spr' not in paths
              and not any(p.endswith(('.exe', '.pack')) for p in paths), 'packed: the tree inside the pack, sharded')
        check(blobs_ok() and not os.path.exists(old_plain), 'packed: ciphertext only, the plain blob removed')
        check(os.listdir(work) == [], 'the decrypted tree is removed with the work folder')
        before = open(os.path.join(live, 'manifest.json')).read()
        other_key = os.path.join(zips, 'otherkey.zip')
        make_packed_zip(other_key, tmp, public, url, key_hex='44' * 32)
        r = run('--version', '63', other_key)
        check(r.returncode != 0 and 'no key of CHAOS_CLIENT_KEY opens it' in r.stderr, 'a pack of another key refused')
        devzip = os.path.join(zips, 'dev.zip')
        make_packed_zip(devzip, tmp, public, url, key_hex=update_crypt.DEV_KEY_HEX, dev=True)
        r = run('--version', '63', devzip)
        check(r.returncode != 0 and 'DEVELOPMENT pack' in r.stderr, 'a development pack refused')
        r = run('--version', '63', '--key-index', '1', packed, extra={'CHAOS_ENV': envfile}, drop=('CHAOS_CLIENT_KEY',))
        check(r.returncode != 0 and 'is the one that opens this package' in r.stderr, 'a wrong --key-index refused')
        check(unchanged(), 'refused packed runs publish nothing')
        check(os.listdir(work) == [], 'refused packed runs leave no work folder')

        # build 15 (pair 37): the pack already holds the shard set, no single spr; published as it is
        sharded = os.path.join(zips, 'sharded.zip')
        index = make_packed_zip(sharded, tmp, public, url, package=15, shards='only')
        r = run('--version', '64', sharded, extra={'CHAOS_UPDATE_URL': purl})
        check(r.returncode == 0 and verify() and blobs_ok(), 'a sharded package publishes: ' + r.stdout + r.stderr)
        m = payload()
        paths = {f['path']: f['sha256'] for f in m['files']}
        check(m['min_package'] == 15 and SHARDED <= set(paths) and 'data/things/1098/Tibia.spr' not in paths,
              'sharded: the shard set, min_package 15')
        idx = spr_shards.parse_index(index)
        check(all(paths.get('data/things/1098/' + fn) == sha for _, _, fn, _, sha in idx['shards']),
              'sharded: the shards as the pack holds them')
        check('sprites:' not in r.stdout, 'sharded: nothing to split')
        # a pack with both: the shards are published, the single file is left out
        both = os.path.join(zips, 'both.zip')
        make_packed_zip(both, tmp, public, url, package=15, shards='both')
        r = run('--version', '65', both, extra={'CHAOS_UPDATE_URL': purl})
        paths = {f['path'] for f in payload()['files']}
        check(r.returncode == 0 and SHARDED <= paths and 'data/things/1098/Tibia.spr' not in paths
              and 'next to its shard set' in r.stdout, 'both: shards only: ' + r.stdout + r.stderr)

        # base patch 0101: a package's baseline (its release number) is the version of its update, nothing else
        pkg70 = os.path.join(zips, 'pkg70.zip')
        make_zip(pkg70, public, url, baseline=70)
        r = run('winpkg-71', extra={'STUB_ZIP': pkg70, 'CHAOS_UPDATE_URL': purl})
        check(r.returncode != 0 and 'baseline 70' in r.stderr, 'a tag of another number than the baseline refused')
        r = run('--version', '69', pkg70, extra={'CHAOS_UPDATE_URL': purl})
        check(r.returncode != 0 and 'baseline 70' in r.stderr, '--version below the baseline refused')
        r = run('winpkg-70', extra={'STUB_ZIP': pkg70, 'CHAOS_UPDATE_URL': purl})
        check(r.returncode == 0 and payload()['version'] == 70 and verify(), 'tag winpkg-70 of baseline 70 -> version 70')
        check('baseline 70' in r.stdout, 'the baseline is printed')
        pkg72 = os.path.join(zips, 'pkg72.zip')
        make_zip(pkg72, public, url, baseline=72)
        r = run(pkg72, extra={'CHAOS_UPDATE_URL': purl})
        check(r.returncode == 0 and payload()['version'] == 72, 'a local zip takes its baseline as the version')
        # the incident the other way round: an older package (baseline 71) after 72 is live
        pkg71 = os.path.join(zips, 'pkg71.zip')
        make_zip(pkg71, public, url, baseline=71)
        r = run('winpkg-71', extra={'STUB_ZIP': pkg71, 'CHAOS_UPDATE_URL': purl})
        check(r.returncode != 0 and 'older than the live update' in r.stderr and payload()['version'] == 72,
              'an older package than the live update refused')
        plain.shutdown()

    print('publish_client_update_test: %d failures' % failures)
    return 1 if failures else 0


if __name__ == '__main__':
    sys.exit(main())
