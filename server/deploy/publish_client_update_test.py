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
Unity channel (O433 phase 16): --unity publishes the player zip of the workflow (a tag or a local zip) as updates/unity with
plain blobs and no client key, leaves the main manifest alone, refuses a changed file, a main client zip, a lower version
and the main client's options.
Unity sprite pair (O433 phase 17): a package built with the client key (unity_build.json embed_client_key) gets the main
client's encrypted pair blobs copied byte for byte as things_enc/*.chub (decrypted and checked when the key is at hand, ciphertext
only otherwise); a dev package says "dev": true and gets none; --no-pair, no published main client, a key that does not open the
blobs and a live manifest of another update key.
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


def make_packed_zip(path, tmp, public, url, key_hex=CLIENT_KEY, dev=False, package=13, baseline=None, shards=None,
                    launcher=False):
    """the layout of a build-13 package: CindersOfChaos-Client/ with Chaos.exe and chaos.pack only. shards: None, a
    single Tibia.spr (builds 13, 14); 'only', the spr as a shard set (build 15, pair 37); 'both', the two"""
    tree = tempfile.mkdtemp(dir=tmp)
    line = '' if baseline is None else '    baseline = %d,\n' % baseline
    files = {'init.lua': (INIT % (url, public, package, line)).encode(), 'modules/client_x/x.lua': b'print(1)\n',
             'mods/readme.txt': b'mods\n', 'data/things/1098/Tibia.dat': os.urandom(4000),
             'data/things/1098/Tibia.spr': spr_bytes(),
             'layouts/mobile/styles/10-panels.otui': b'MobilePanel < UIWidget\n'}
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
        if launcher:
            z.writestr('CindersOfChaos-Client/CindersLauncher.exe', b'MZ launcher')
            z.writestr('CindersOfChaos-Client/libssl-3-x64.dll', b'MZ dll')
            z.writestr('CindersOfChaos-Client/launcher.json', '{}')
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

        # curl stub (O530: the repository is private): the releases API of the tag lists the assets, an asset address
        # answers 302 with a signed address, the signed address hands out $STUB_ZIP / $STUB_APK / $STUB_APK_INFO.
        # Every call with -K (the config on stdin) is logged: the lines of the config, the arguments; any other call
        # goes to the real curl
        real_curl = shutil.which('curl')
        with open(os.path.join(stub, 'curl'), 'w') as f:
            f.write('''#!/usr/bin/env python3
import os, re, shutil, sys
args = sys.argv[1:]
if '-K' not in args:
    os.execv(%r, ['curl'] + args)
stub = os.environ['STUB_DIR']
cfg = sys.stdin.read()
with open(os.path.join(stub, 'cfg.log'), 'a') as f:
    f.write(cfg + '--\\n')
with open(os.path.join(stub, 'args.log'), 'a') as f:
    f.write(' '.join(args) + '\\n')
url = re.search(r'url = "([^"]+)"', cfg).group(1)
out = args[args.index('-o') + 1] if '-o' in args else None
names = {'1': 'CindersOfChaos-Client-Windows.zip', '2': 'CindersOfChaos-Android.apk', '3': 'CindersOfChaos-Android.json',
         '4': 'CindersOfChaos-Unity-Windows.zip'}
def log(line):
    with open(os.path.join(stub, 'urls'), 'a') as f:
        f.write(line + '\\n')
def answer(text):
    sys.stdout.write(text)
    sys.exit(0)
api = os.environ.get('STUB_API_CODE')
m = re.fullmatch(r'https://api\\.github\\.com/repos/([^/]+/[^/]+)/releases/tags/(.+)', url)
if m:
    log('tag ' + m.group(2))
    if api:
        if out:
            open(out, 'w').write('{}')
        answer(api)
    open(os.path.join(stub, 'lasttag'), 'w').write(m.group(2))
    body = '{"assets": [%%s]}' %% ','.join('{"id": %%s, "name": "%%s"}' %% (i, n) for i, n in names.items())
    open(out, 'w').write(body)
    answer('200')
m = re.fullmatch(r'https://api\\.github\\.com/repos/([^/]+/[^/]+)/releases/assets/(\\d+)', url)
if m:
    log('asset ' + names[m.group(2)] + ' of ' + m.group(1))
    answer('302 https://objects.example.org/signed/' + m.group(2) + '?sig=SIGNED')
m = re.fullmatch(r'https://objects\\.example\\.org/signed/(\\d+)\\?sig=SIGNED', url)
if m:
    n = names[m.group(1)]
    src = {'1': 'STUB_ZIP', '2': 'STUB_APK', '3': 'STUB_APK_INFO', '4': 'STUB_ZIP'}[m.group(1)]
    if not os.environ.get(src):
        sys.exit(22)
    shutil.copy(os.environ[src], out)
    sys.exit(0)
sys.stderr.write('curl stub: unexpected ' + url + '\\n')
sys.exit(22)
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
        check('tag winpkg-46\n' in urls and 'asset CindersOfChaos-Client-Windows.zip of lucas1089/cinders-of-chaos' in urls,
              'the release asset through the API: ' + urls)
        check(payload()['version'] == 46 and verify(), 'tag winpkg-46 -> version 46, verifies')
        # O530: no token saved, a private repository (GitHub answers 404): refused with the word the apps translate
        r = run('winpkg-47', extra={'STUB_ZIP': good, 'STUB_API_CODE': '404'})
        check(r.returncode != 0 and 'private-repo' in r.stderr and 'github-token-set' in r.stderr, 'no token, 404: ' + r.stderr)
        check(payload()['version'] == 46, 'a refused download publishes nothing')
        # with the token: the API calls carry it (on stdin), the signed address and the command lines never do
        token = 'github_pat_11ABCDEFG0aBcDeFgHiJkL_mNoPqRsTuVwXyZ0123456789aBcDeFgHiJkLmNoPqRsTuVwXyZ01234'
        tfile = os.path.join(keys, 'github.token')
        with open(tfile, 'w') as f:
            f.write(token + '\n')
        os.chmod(tfile, 0o600)
        for n in ('cfg.log', 'args.log'):
            if os.path.exists(os.path.join(stub, n)):
                os.remove(os.path.join(stub, n))
        r = run('winpkg-48', extra={'STUB_ZIP': good, 'CHAOS_GITHUB_TOKEN_FILE': tfile})
        check(r.returncode == 0, 'tag publishes with a token: ' + r.stdout + r.stderr)
        cfgs = [c for c in open(os.path.join(stub, 'cfg.log')).read().split('--\n') if c.strip()]
        api_cfgs = [c for c in cfgs if 'api.github.com' in c]
        cdn_cfgs = [c for c in cfgs if 'objects.example.org' in c]
        check(len(api_cfgs) == 2 and all('Authorization: Bearer ' + token in c for c in api_cfgs),
              'the tag and asset questions carry the token')
        check(len(cdn_cfgs) == 1 and 'Authorization' not in cdn_cfgs[0], 'the signed address gets no token')
        check('asset' in [c for c in api_cfgs if '/assets/' in c][0].replace('assets', 'asset')
              and 'Accept: application/octet-stream' in [c for c in api_cfgs if '/assets/' in c][0],
              'the asset question asks for the octet-stream')
        check(token not in open(os.path.join(stub, 'args.log')).read(), 'the token is on no command line')
        check(token not in r.stdout + r.stderr and 'SIGNED' not in r.stdout + r.stderr, 'no token or signed address in the output')
        check(payload()['version'] == 48 and verify(), 'tag winpkg-48 -> version 48')

        before = open(os.path.join(live, 'manifest.json')).read()

        def unchanged():
            return open(os.path.join(live, 'manifest.json')).read() == before

        r = run('winpkg-48', extra={'STUB_ZIP': good})
        check(r.returncode != 0 and 'not above the published 48' in r.stderr, 'same version again refused')
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
        # phone data (O313): the "android" section lists what a phone downloads; layouts/mobile stays out, the shards are in
        a = m.get('android') or {}
        by = {f['path']: f for f in m['files']}
        check(a.get('version') == 1 and a.get('files') == sorted(a.get('files') or []), 'android: section, sorted list')
        check('layouts/mobile/styles/10-panels.otui' in by and 'layouts/mobile/styles/10-panels.otui' not in a.get('files', []),
              'android: layouts/mobile is published but not on the phone list')
        check(SHARDED <= set(a.get('files', [])) and 'data/things/1098/Tibia.dat' in a.get('files', []),
              'android: the dat and the shard set are on the phone list')
        check(set(a.get('files', [])) == set(by) - {'layouts/mobile/styles/10-panels.otui'}, 'android: every other file')
        check(a.get('count') == len(a.get('files', [])) and
              a.get('bytes') == sum({by[p]['blob']: by[p]['blob_size'] for p in a.get('files', [])}.values()),
              'android: count and download bytes')
        check('phone files' in subprocess.run([sys.executable, '-I', TOOL, 'verify', live, '--public', public],
                                              capture_output=True, text=True).stdout, 'android: verify reports the section')
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

        # the launcher (O314): a package with CindersLauncher.exe publishes its program files as the native section
        lz = os.path.join(zips, 'launcher.zip')
        make_packed_zip(lz, tmp, public, url, package=15, shards='only', launcher=True)
        # the chunk size is passed on (O552): a size the manifest tool refuses stops the publish, nothing goes live
        r = run('--version', '80', lz, extra={'CHAOS_UPDATE_URL': purl, 'CHAOS_NATIVE_CHUNK': '1000'})
        check(r.returncode != 0 and 'native-chunk' in r.stderr and payload()['version'] == 72, 'a bad chunk size is refused')
        r = run('--version', '80', lz, extra={'CHAOS_UPDATE_URL': purl})
        m = payload()
        nat = m.get('native') or {}
        names = sorted(f['path'] for f in nat.get('files', []))
        check(r.returncode == 0 and verify(), 'launcher package publishes: ' + r.stdout + r.stderr)
        check(names == ['Chaos.exe', 'CindersLauncher.exe', 'chaos.pack', 'libssl-3-x64.dll'], 'native files: %s' % names)
        check(nat.get('package') == 15 and nat.get('game') == 'Chaos.exe' and nat.get('launcher') == 'CindersLauncher.exe',
              'native package, game and launcher')
        check(not any(p.endswith(('.exe', '.dll', '.pack')) for p in (f['path'] for f in m['files'])),
              'native files are not in the Lua updater list')
        for f in nat.get('files', []):
            b = os.path.join(live, 'native', f['sha256'][:2], f['sha256'])
            check(os.path.isfile(b) and os.path.getsize(b) == f['size'], 'native blob of ' + f['path'])
        # a package without the launcher publishes no native section (and the old native blobs go)
        r = run('--version', '81', packed, extra={'CHAOS_UPDATE_URL': purl, 'CHAOS_ENV': envfile},
                drop=('CHAOS_CLIENT_KEY',))
        check(r.returncode == 0 and 'native' not in payload(), 'no launcher, no native section')
        check(not os.path.isdir(os.path.join(live, 'native')) or not os.listdir(os.path.join(live, 'native')),
              'old native blobs removed')
        r = run('--version', '85', lz, extra={'CHAOS_UPDATE_URL': purl, 'CHAOS_NATIVE_CHUNK': '0'})
        check(r.returncode == 0 and not any('chunks' in f for f in payload()['native']['files']), 'chunk size 0 turns them off')

        # the app update (O313 step 8): the Android client's own APK, plain under apk/, the entry in the signed manifest
        def make_apk_files(name, code, version, signer='ab' * 32, body=None):
            apk = os.path.join(zips, name + '.apk')
            open(apk, 'wb').write(b'PK\x03\x04' + (body if body is not None else os.urandom(2000)))
            info = os.path.join(zips, name + '.json')
            json.dump({'version_code': code, 'version_name': version, 'signer_sha256': signer}, open(info, 'w'))
            return apk, info

        def apk_files():
            return sorted(f for _, _, fs in os.walk(os.path.join(live, 'apk')) for f in fs)

        env_apk = {'CHAOS_UPDATE_URL': purl, 'CHAOS_UPDATE_APK_MIN_MB': '0'}
        base_version = payload()['version']
        apk1, info1 = make_apk_files('app31', 31, '1.31')
        # alone: only the entry changes, same version and game files, signed again
        before_m = payload()
        r = run('--apk', apk1, '--apk-info', info1, extra=env_apk)
        a = payload().get('android_apk') or {}
        check(r.returncode == 0 and verify(), 'apk alone publishes: ' + r.stdout + r.stderr)
        check(a.get('version_code') == 31 and a.get('signer_sha256') == 'ab' * 32 and a.get('min_version_code') == 0,
              'apk alone: the entry')
        check(payload()['version'] == base_version and payload()['files'] == before_m['files'],
              'apk alone: same version and files')
        check(apk_files() == [a.get('sha256', '') + '.apk'], 'apk alone: one plain file under apk/')
        check('Range GET of the app update' in r.stdout, 'apk alone: the web check asks the APK URL with a Range: ' + r.stdout)
        check(blobs_ok(), 'apk alone: the game blobs are untouched')
        # a release tag: the APK and its JSON come from the release assets
        apk2, info2 = make_apk_files('app32', 32, '1.32')
        r = run('--apk', 'android-32', '--apk-min-version-code', '31',
                extra=dict(env_apk, STUB_APK=apk2, STUB_APK_INFO=info2))
        a = payload().get('android_apk') or {}
        urls = open(os.path.join(stub, 'urls')).read()
        check(r.returncode == 0 and a.get('version_code') == 32 and a.get('min_version_code') == 31,
              'apk tag publishes: ' + r.stdout + r.stderr)
        check('tag android-32\n' in urls and 'asset CindersOfChaos-Android.apk of ' in urls
              and 'asset CindersOfChaos-Android.json of ' in urls, 'apk tag: both assets downloaded through the API')
        check(len(apk_files()) == 1 and verify(), 'apk tag: the old APK is removed')
        # a publish of new game files keeps the app update
        r = run('--version', '90', good, extra=env_apk)
        a = payload().get('android_apk') or {}
        check(r.returncode == 0 and payload()['version'] == 90 and a.get('version_code') == 32 and len(apk_files()) == 1
              and verify(), 'game files keep the app update: ' + r.stdout + r.stderr)
        # a publish with the APK of the same run
        apk3, info3 = make_apk_files('app33', 33, '1.33')
        r = run('--version', '91', good, '--apk', apk3, '--apk-info', info3, extra=env_apk)
        a = payload().get('android_apk') or {}
        check(r.returncode == 0 and a.get('version_code') == 33 and 'app update: 1.33 code 33' in r.stdout and verify(),
              'game files and APK in one publish: ' + r.stdout + r.stderr)
        # refusals change nothing
        before = open(os.path.join(live, 'manifest.json')).read()
        low, lowi = make_apk_files('app30', 30, '1.30')
        r = run('--apk', low, '--apk-info', lowi, extra=env_apk)
        check(r.returncode != 0 and 'below the published 33' in r.stderr, 'a lower version code refused: ' + r.stderr)
        same, samei = make_apk_files('app33b', 33, '1.33')
        r = run('--apk', same, '--apk-info', samei, extra=env_apk)
        check(r.returncode != 0 and 'another file' in r.stderr, 'the same code with another file refused')
        r = run('--apk', apk3, extra=env_apk)
        check(r.returncode != 0 and '--apk-info' in r.stderr, 'a local APK without its JSON refused')
        r = run('--apk', 'android-34', extra=dict(env_apk, STUB_APK=apk3))
        check(r.returncode != 0 and 'download failed' in r.stderr, 'a missing info asset refused')
        r = run('--apk', 'android-34', extra=dict(env_apk, STUB_APK_INFO=info3))
        check(r.returncode != 0 and 'download failed' in r.stderr, 'a missing APK asset refused')
        tiny = os.path.join(zips, 'tiny.apk')
        open(tiny, 'wb').write(b'PK\x03\x04')
        r = run('--apk', tiny, '--apk-info', info3, extra={'CHAOS_UPDATE_APK_MIN_MB': '1'})
        check(r.returncode != 0 and 'below 1 MB' in r.stderr, 'a tiny APK refused')
        r = run('--apk', apk3, '--apk-info', info3, '--no-apk', extra=env_apk)
        check(r.returncode != 0 and 'together' in r.stderr, '--apk with --no-apk refused')
        r = run('--apk', 'bad tag!', extra=env_apk)
        check(r.returncode != 0 and 'not a local file and not a release tag' in r.stderr, 'an odd tag refused')
        check(open(os.path.join(live, 'manifest.json')).read() == before and os.listdir(work) == [],
              'refused APK runs change nothing')
        # the minimum alone, and removing it
        r = run('--apk-min-version-code', '33', extra=env_apk)
        check(r.returncode == 0 and payload()['android_apk']['min_version_code'] == 33 and verify(),
              'the minimum alone: ' + r.stdout + r.stderr)
        r = run('--no-apk', extra=env_apk)
        check(r.returncode == 0 and 'android_apk' not in payload() and apk_files() == [] and verify(),
              'no-apk alone removes the entry and the file: ' + r.stdout + r.stderr)
        # another private key cannot sign over the published manifest
        keys2 = os.path.join(tmp, 'keys2')
        os.makedirs(keys2)
        key2 = os.path.join(keys2, 'update-key.hex')
        subprocess.run([sys.executable, '-I', TOOL, 'keygen', '--private', key2], capture_output=True, text=True)
        r = run('--apk', apk3, '--apk-info', info3, extra=dict(env_apk, CHAOS_UPDATE_KEY=key2))
        check(r.returncode != 0 and 'not signed by this key' in r.stderr, 'a manifest of another key is not changed')
        r = run()
        check(r.returncode != 0 and 'TAG or ZIP' in r.stderr, 'nothing to do: refused')

        # ---- the Unity client channel (O433 phase 16): --unity, its own manifest in updates/unity, no client key needed
        import make_unity_manifest as mun
        unity_live = os.path.join(site, 'updates', 'unity')
        player = os.path.join(tmp, 'uplayer')
        for rel, data in (('ChaosUnity.exe', b'MZ unity'), ('UnityPlayer.dll', b'MZ player' * 50),
                          ('ChaosUnity_Data/globalgamemanagers', os.urandom(3000)),
                          ('ChaosUnity_Data/Managed/Assembly-CSharp.dll', b'MZ asm' * 40),
                          ('ChaosUnity_Data/Resources/unity default resources', b'res' * 30)):
            full = os.path.join(player, *rel.split('/'))
            os.makedirs(os.path.dirname(full), exist_ok=True)
            open(full, 'wb').write(data)
        uzip = os.path.join(zips, 'unity.zip')
        with open(os.devnull, 'w') as sink:
            real, sys.stdout = sys.stdout, sink
            try:
                mun.main(['pack', player, '--out', uzip, '--package', '31'])
            finally:
                sys.stdout = real
        env_u = {'CHAOS_UPDATE_UNITY_MIN_MB': '0'}
        usrv = serve(site, True)   # a server of its own for the check of updates/unity
        uurl = 'http://127.0.0.1:%d/updates/live/manifest.json' % usrv.server_address[1]

        def upayload():
            return json.loads(json.load(open(os.path.join(unity_live, 'manifest.json')))['payload'])

        def uverify():
            return subprocess.run([sys.executable, '-I', os.path.join(HERE, '..', '..', 'client', 'tools',
                                                                      'make_unity_manifest.py'),
                                   'verify', unity_live, '--public', public], capture_output=True, text=True).returncode == 0

        main_before = open(os.path.join(live, 'manifest.json')).read()
        r = run('--unity', '--version', '2', uzip, extra=env_u, drop=('CHAOS_CLIENT_KEY',))
        check(r.returncode == 0, 'unity zip publishes without a client key: ' + r.stdout + r.stderr)
        check('published: the Unity client, manifest version 2' in r.stdout, 'unity: the summary line')
        um = upayload() if r.returncode == 0 else {}
        check(um.get('channel') == 'unity' and um.get('version') == 2 and um.get('files') == [] and uverify(),
              'unity: its own manifest, no in-game updater files, it verifies')
        check(um.get('native', {}).get('layout') == 'tree' and um['native']['game'] == 'ChaosUnity.exe'
              and um['native']['package'] == 31
              and {f['path'] for f in um['native']['files']} == {'ChaosUnity.exe', 'UnityPlayer.dll',
                                                                  'ChaosUnity_Data/globalgamemanagers',
                                                                  'ChaosUnity_Data/Managed/Assembly-CSharp.dll',
                                                                  'ChaosUnity_Data/Resources/unity default resources'},
              'unity: the tree of the player folder, game and package from the build manifest')
        check(open(os.path.join(live, 'manifest.json')).read() == main_before,
              'unity: the main client manifest is not touched')
        check(os.listdir(work) == [], 'unity: the work folder is removed')
        # a release tag: the asset URL and the version from the tag; the web check against the local server
        open(os.path.join(stub, 'urls'), 'w').close()
        r = run('--unity', 'unity-3', extra=dict(env_u, STUB_ZIP=uzip, CHAOS_UPDATE_URL=uurl))
        check(r.returncode == 0, 'unity tag publishes: ' + r.stdout + r.stderr)
        uurls = open(os.path.join(stub, 'urls')).read()
        check('tag unity-3\n' in uurls and 'asset CindersOfChaos-Unity-Windows.zip of ' in uurls,
              'unity: the release asset through the API')
        check(upayload()['version'] == 3 and uverify(), 'unity: tag unity-3 -> version 3')
        check('/updates/unity/manifest.json -> HTTP 200' in r.stdout and 'check: ok' in r.stdout,
              'unity: the web server check of updates/unity: ' + r.stdout)
        ubefore = open(os.path.join(unity_live, 'manifest.json')).read()
        # refusals publish nothing
        r = run('--unity', 'unity-3', extra=dict(env_u, STUB_ZIP=uzip))
        check(r.returncode != 0 and 'not newer' in r.stderr, 'unity: the same version again refused: ' + r.stderr)
        r = run('--unity', good, extra=env_u)
        check(r.returncode != 0 and 'unity_build.json' in r.stderr, 'unity: a main client zip refused')
        r = run('--version', '99', uzip)
        check(r.returncode != 0 and 'no client folder' not in r.stdout and not os.path.exists(os.path.join(live, 'x')),
              'a unity zip without --unity is not taken for a client')
        check(open(os.path.join(live, 'manifest.json')).read() == main_before, 'the main manifest is still untouched')
        r = run('--unity', uzip, '--apk', 'android-9', extra=env_u)
        check(r.returncode != 0 and 'does not go with' in r.stderr, 'unity with --apk refused')
        r = run('--unity', '--min-package', '13', uzip, extra=env_u)
        check(r.returncode != 0 and 'does not go with' in r.stderr, 'unity with --min-package refused')
        r = run('--unity', '--check-only', uzip, extra=env_u)
        check(r.returncode != 0 and 'does not go with' in r.stderr, 'unity with --check-only refused')
        r = run('--unity', extra=env_u)
        check(r.returncode != 0 and 'needs a TAG or ZIP' in r.stderr, 'unity without a zip refused')
        r = run('--unity', '--version', '9', uzip)
        check(r.returncode != 0 and 'below 20 MB' in r.stderr, 'unity: a small download refused by default')
        # a zip whose file differs from its build manifest
        tampered = os.path.join(zips, 'unity_bad.zip')
        with zipfile.ZipFile(uzip) as zin, zipfile.ZipFile(tampered, 'w') as zout:
            for item in zin.infolist():
                data = zin.read(item.filename)
                zout.writestr(item.filename, b'MZ evil' if item.filename == 'UnityPlayer.dll' else data)
        r = run('--unity', '--version', '9', tampered, extra=env_u)
        check(r.returncode != 0 and 'do not match' in r.stderr, 'unity: a changed file refused: ' + r.stderr)
        # a zip with a script in it
        scripted = os.path.join(zips, 'unity_script.zip')
        with zipfile.ZipFile(uzip) as zin, zipfile.ZipFile(scripted, 'w') as zout:
            for item in zin.infolist():
                zout.writestr(item.filename, zin.read(item.filename))
            zout.writestr('run.bat', 'echo x')
        r = run('--unity', '--version', '9', scripted, extra=env_u)
        check(r.returncode != 0, 'unity: a zip with an extra file refused')
        check(open(os.path.join(unity_live, 'manifest.json')).read() == ubefore and os.listdir(work) == [],
              'unity: refused runs change nothing')
        # ---- the sprite pair (O433 phase 17): a package that carries the client key gets the main client's encrypted blobs
        ukeyed = os.path.join(zips, 'unity_keyed.zip')
        with open(os.devnull, 'w') as sink:
            real, sys.stdout = sys.stdout, sink
            try:
                mun.main(['pack', player, '--out', ukeyed, '--package', '31', '--embed-client-key'])
            finally:
                sys.stdout = real
        live_files = {f['path']: f for f in payload()['files']}
        live_pair = {p: f for p, f in live_files.items() if p.startswith('data/things/1098/Tibia.')}
        check('data/things/1098/Tibia.dat' in live_pair and 'data/things/1098/Tibia.sprshards' in live_pair,
              'unity pair: the published main client holds a pair to copy: ' + ' '.join(sorted(live_pair)))
        main_before = open(os.path.join(live, 'manifest.json')).read()
        r = run('--unity', '--version', '10', ukeyed, extra=env_u)
        check(r.returncode == 0 and 'sprite pair: from ' in r.stdout and 'KEYED' in r.stdout,
              'unity pair: a keyed package publishes with the pair: ' + r.stdout + r.stderr)
        check('decrypted and checked against the signed hashes and the shard index' in r.stdout,
              'unity pair: with the key at hand the blobs are decrypted and checked')
        um = upayload() if r.returncode == 0 else {'native': {'files': []}}
        got = {f['path']: f for f in um['native']['files'] if f['path'].startswith('things_enc/')}
        want = {'things_enc/' + p.rsplit('/', 1)[1] + '.chub': f for p, f in live_pair.items()}
        check(set(got) == set(want) and len(got) >= 3, 'unity pair: the pair files of the main client, as things_enc/*.chub')
        same = all(got[n]['sha256'] == want[n]['blob'] and got[n]['size'] == want[n]['blob_size'] and
                   open(os.path.join(unity_live, 'native', got[n]['sha256'][:2], got[n]['sha256']), 'rb').read() ==
                   open(os.path.join(live, 'files', want[n]['blob'][:2], want[n]['blob']), 'rb').read() for n in got)
        check(same and um['native'].get('dev') is False and uverify(),
              'unity pair: the same bytes as the live blobs, not a dev package, it verifies')
        blob_path = os.path.join(unity_live, 'native', got['things_enc/Tibia.dat.chub']['sha256'][:2],
                                 got['things_enc/Tibia.dat.chub']['sha256']) if got else ''
        check(got and update_crypt.decrypt_file(blob_path, bytes.fromhex(CLIENT_KEY))[1] == live_pair['data/things/1098/Tibia.dat']['sha256'],
              'unity pair: the published Tibia.dat blob opens with the client key')
        check(open(os.path.join(live, 'manifest.json')).read() == main_before, 'unity pair: the main client is not touched')
        # no key at hand: ciphertext checks only
        r = run('--unity', '--version', '11', ukeyed, extra=env_u, drop=('CHAOS_CLIENT_KEY',))
        check(r.returncode == 0 and 'ciphertext checked only' in r.stdout, 'unity pair: without the key only the ciphertext is checked: ' + r.stdout + r.stderr)
        # --no-pair, and --no-pair without --unity
        r = run('--unity', '--version', '12', '--no-pair', ukeyed, extra=env_u)
        um = upayload() if r.returncode == 0 else {'native': {'files': []}}
        check(r.returncode == 0 and 'left out (--no-pair)' in r.stdout and um['native'].get('dev') is False
              and not any(f['path'].startswith('things_enc/') for f in um['native']['files']),
              'unity pair: --no-pair leaves it out: ' + r.stdout + r.stderr)
        r = run('--no-pair', uzip)
        check(r.returncode != 0 and '--no-pair goes with --unity' in r.stderr, '--no-pair without --unity refused')
        # a DEV package (no key inside): marked dev, no pair
        r = run('--unity', '--version', '13', uzip, extra=env_u)
        um = upayload() if r.returncode == 0 else {'native': {'files': []}}
        check(r.returncode == 0 and um['native'].get('dev') is True
              and not any(f['path'].startswith('things_enc/') for f in um['native']['files']) and 'no sprite pair is added' in r.stdout,
              'unity pair: a dev package says dev and gets no pair: ' + r.stdout + r.stderr)
        # no published main client: a warning, no pair
        r = run('--unity', '--version', '14', ukeyed, extra=dict(env_u, CHAOS_UPDATE_UNITY_PAIR_FROM=os.path.join(tmp, 'nowhere')))
        um = upayload() if r.returncode == 0 else {'native': {'files': []}}
        check(r.returncode == 0 and 'WARN: no published main client' in r.stdout
              and not any(f['path'].startswith('things_enc/') for f in um['native']['files']),
              'unity pair: no main client published: a warning and no pair: ' + r.stdout + r.stderr)
        # a main client published with another key than the one at hand: refused, nothing published
        ubefore = open(os.path.join(unity_live, 'manifest.json')).read()
        r = run('--unity', '--version', '15', ukeyed, extra=dict(env_u, CHAOS_CLIENT_KEY=OLD_KEY))
        check(r.returncode != 0 and 'no key of CHAOS_CLIENT_KEY opens' in r.stderr and
              open(os.path.join(unity_live, 'manifest.json')).read() == ubefore, 'unity pair: a key that does not open the live blobs refused: ' + r.stderr)
        # a live manifest of another update key is refused
        other = os.path.join(tmp, 'keys3')
        os.makedirs(other)
        key3 = os.path.join(other, 'update-key.hex')
        subprocess.run([sys.executable, '-I', TOOL, 'keygen', '--private', key3], capture_output=True, text=True)
        r = run('--unity', '--version', '16', ukeyed, extra=dict(env_u, CHAOS_UPDATE_KEY=key3))
        check(r.returncode != 0 and 'not signed by this update key' in r.stderr and
              open(os.path.join(unity_live, 'manifest.json')).read() == ubefore, 'unity pair: a live manifest of another key refused: ' + r.stderr)
        check(os.listdir(work) == [], 'unity pair: the work folder is removed')
        usrv.shutdown()
        plain.shutdown()

    print('publish_client_update_test: %d failures' % failures)
    return 1 if failures else 0


if __name__ == '__main__':
    sys.exit(main())
