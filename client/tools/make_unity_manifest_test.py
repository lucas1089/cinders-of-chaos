#!/usr/bin/env python3
"""Tests of make_unity_manifest.py: python3 -I client/tools/make_unity_manifest_test.py
Pack a fake Unity player folder, publish it signed, verify it, and refuse the bad cases. The key is a throwaway one."""
import hashlib, io, json, os, shutil, sys, tempfile, unittest, zipfile
from contextlib import redirect_stdout, redirect_stderr

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import make_unity_manifest as mun  # noqa: E402
import make_update_manifest as mum  # noqa: E402
import update_crypt as uc  # noqa: E402


def run(argv):
    out, err = io.StringIO(), io.StringIO()
    code = 0
    with redirect_stdout(out), redirect_stderr(err):
        try:
            code = mun.main(argv) or 0
        except SystemExit as e:
            code = e.code if isinstance(e.code, int) else 1
            if not isinstance(e.code, int):
                err.write(str(e.code))
    return code, out.getvalue(), err.getvalue()


def write(root, rel, data=b'x'):
    p = os.path.join(root, *rel.split('/'))
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, 'wb') as f:
        f.write(data)


PLAYER = {
    'ChaosUnity.exe': b'exe',
    'UnityPlayer.dll': b'player',
    'UnityCrashHandler64.exe': b'crash',
    'ChaosUnity_Data/globalgamemanagers': b'ggm',
    'ChaosUnity_Data/Managed/Assembly-CSharp.dll': b'asm',
    'ChaosUnity_Data/Resources/unity default resources': b'res',
    'ChaosUnity_Data/StreamingAssets/overlay/modules/game_chaossound/sounds/a.ogg': b'ogg',
    'MonoBleedingEdge/EmbedRuntime/mono-2.0-bdwgc.dll': b'mono',
}


class Base(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix='unity-manifest-test-')
        self.player = os.path.join(self.tmp, 'player')
        for rel, data in PLAYER.items():
            write(self.player, rel, data)
        # left out on purpose
        write(self.player, 'ChaosUnity_BurstDebugInformation_DoNotShip/x.dll', b'burst')
        write(self.player, 'ChaosUnity_BackUpThisFolder_ButDontShipItWithYourGame/y.dll', b'backup')
        write(self.player, 'ChaosUnity_Data/Managed/Assembly-CSharp.pdb', b'pdb')
        self.zip = os.path.join(self.tmp, 'out', 'unity.zip')
        self.key = os.path.join(self.tmp, 'update.key')
        code, _, err = run_mum(['keygen', '--private', self.key, '--public', self.key + '.pub'])
        self.assertEqual(code, 0, err)
        self.public = open(self.key + '.pub').read().strip()
        self.site = os.path.join(self.tmp, 'site', 'updates', 'unity')

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def extract(self, name='x'):
        dest = os.path.join(self.tmp, name)
        with zipfile.ZipFile(self.zip) as z:
            z.extractall(dest)
        return dest

    def pack(self):
        code, out, err = run(['pack', self.player, '--out', self.zip, '--package', '31'])
        self.assertEqual(code, 0, err)
        return out


def run_mum(argv):
    out, err = io.StringIO(), io.StringIO()
    code = 0
    with redirect_stdout(out), redirect_stderr(err):
        try:
            code = mum.main(argv) or 0
        except SystemExit as e:
            code = e.code if isinstance(e.code, int) else 1
            if not isinstance(e.code, int):
                err.write(str(e.code))
    return code, out.getvalue(), err.getvalue()


class Rules(unittest.TestCase):
    def test_paths(self):
        ok = ['ChaosUnity.exe', 'a/b.dll', 'ChaosUnity_Data/Resources/unity default resources', 'a/b/c/d.assets.resS']
        for p in ok:
            self.assertIsNone(mun.check_tree_path(p), p)
        bad = ['', '/a', 'a//b', 'a/../b', '.hidden', 'a/.git', 'a\\b', 'c:x', 'a b.', 'a/b ', 'con.dll', 'a/aux.txt',
               'a/nul', 'run.bat', 'a/b.ps1', 'sub/x.exe', 'a/' * 13 + 'f', 'é.dll', 'x' * 97, 'a/b/' + 'y' * 100,
               'a/lnk.lnk']
        for p in bad:
            self.assertIsNotNone(mun.check_tree_path(p), p)

    def native(self, files, **extra):
        n = mun.make_native([(p, 'ab' * 32, 3) for p in files], 31, 'ChaosUnity.exe')
        n.update(extra)
        return n

    def test_native_rules(self):
        self.assertIsNone(mun.check_tree_native(self.native(['ChaosUnity.exe', 'd/x.dll'])))
        cases = [
            self.native(['ChaosUnity.exe', 'D/x.dll', 'd/X.dll']),          # same name on Windows
            self.native(['ChaosUnity.exe', 'd', 'd/x.dll']),                # a file that is also a folder
            self.native(['x.dll']),                                          # no game
            self.native(['ChaosUnity.exe'], layout='flat'),
            self.native(['ChaosUnity.exe'], launcher='ChaosUnity.exe'),
            self.native(['ChaosUnity.exe'], files_url='files/'),
            self.native([]),
            self.native(['ChaosUnity.exe', 'run.cmd']),
        ]
        for c in cases:
            self.assertIsNotNone(mun.check_tree_native(c), c)
        n = self.native(['ChaosUnity.exe'])
        n['files'][0]['size'] = 3 * 1024 ** 3
        self.assertIsNotNone(mun.check_tree_native(n))
        n['files'][0]['size'] = 3
        n['files'][0]['sha256'] = 'AB' * 32
        self.assertIsNotNone(mun.check_tree_native(n))
        n = self.native(['ChaosUnity.exe'])
        n['game'] = 'sub/ChaosUnity.exe'
        self.assertIsNotNone(mun.check_tree_native(n))

    def test_payload_rules(self):
        good = {'format': 1, 'product': mum.PRODUCT, 'channel': 'unity', 'version': 3, 'files': [],
                'native': self.native(['ChaosUnity.exe'])}
        self.assertIsNone(mun.check_payload(good))
        for key, val in (('format', 2), ('product', 'x'), ('channel', 'live'), ('version', 0), ('files', [{'path': 'a'}])):
            self.assertIsNotNone(mun.check_payload({**good, key: val}), key)


class LauncherVector(unittest.TestCase):
    VECTOR = os.path.join(os.path.dirname(HERE), '..', 'launcher', 'tests', 'data', 'python_unity_manifest.json')

    def test_launcher_vector(self):
        """launcher/tests/data/python_unity_manifest.json: a unity manifest this tool's rules accept, signed with a fixed
        key and a fixed time, read by launcher/tests/vector.rs. UPDATE_LAUNCHER_VECTOR=1 rewrites it."""
        seed = bytes([0x43]) * 32
        files = [('ChaosUnity.exe', b'exe'), ('UnityPlayer.dll', b'player'),
                 ('ChaosUnity_Data/Managed/Assembly-CSharp.dll', b'asm'),
                 ('ChaosUnity_Data/Resources/unity default resources', b'res')]
        entries = [(p, hashlib.sha256(d).hexdigest(), len(d)) for p, d in files]
        payload = json.dumps({'format': 1, 'product': mum.PRODUCT, 'channel': 'unity', 'version': 4,
                              'created': '2026-11-08T00:00:00Z', 'min_package': 0, 'files': [],
                              'native': mun.make_native(entries, 31, 'ChaosUnity.exe')},
                             sort_keys=True, separators=(',', ':'), ensure_ascii=True)
        self.assertIsNone(mun.check_payload(json.loads(payload)))
        public = mum.public_from_seed(seed)
        env = mum.make_envelope(payload, public.hex(), mum.sign(seed, payload.encode('ascii')).hex())
        doc = json.dumps({'public_key': public.hex(), 'envelope': json.loads(env)}, indent=1, sort_keys=True) + '\n'
        if os.environ.get('UPDATE_LAUNCHER_VECTOR') == '1':
            with open(self.VECTOR, 'w', encoding='ascii') as f:
                f.write(doc)
        with open(self.VECTOR, encoding='ascii') as f:
            self.assertEqual(f.read(), doc, 'regenerate with UPDATE_LAUNCHER_VECTOR=1')


class PackAndPublish(Base):
    def test_pack_lists_the_right_files(self):
        out = self.pack()
        self.assertIn('packed 8 files', out)
        with zipfile.ZipFile(self.zip) as z:
            names = set(z.namelist())
        self.assertEqual(names, set(PLAYER) | {'unity_build.json'})
        info = json.load(open(os.path.join(self.extract(), 'unity_build.json')))
        self.assertEqual((info['native']['package'], info['native']['game'], info['native']['layout']),
                         (31, 'ChaosUnity.exe', 'tree'))
        self.assertEqual({f['path'] for f in info['native']['files']}, set(PLAYER))
        self.assertIsNone(mun.check_tree_native(info['native']))

    def test_pack_refuses_odd_files(self):
        write(self.player, 'ChaosUnity_Data/run.bat')
        code, _, err = run(['pack', self.player, '--out', self.zip, '--package', '31'])
        self.assertNotEqual(code, 0)
        self.assertIn('run.bat', err)
        self.assertFalse(os.path.exists(self.zip))

    def test_pack_refuses_a_link(self):
        try:
            os.symlink(os.path.join(self.player, 'UnityPlayer.dll'), os.path.join(self.player, 'link.dll'))
        except OSError:
            self.skipTest('no symlinks here')
        code, _, err = run(['pack', self.player, '--out', self.zip, '--package', '31'])
        self.assertNotEqual(code, 0)
        self.assertIn('link.dll', err)

    def test_publish_verify_and_versions(self):
        self.pack()
        x = self.extract()
        code, out, err = run(['build', x, '--out', self.site, '--key', self.key])
        self.assertEqual(code, 0, err)
        self.assertIn('published unity version 1', out)
        code, out, err = run(['verify', self.site, '--public', self.public])
        self.assertEqual(code, 0, err)
        self.assertIn('8 files', out)
        env = json.load(open(os.path.join(self.site, 'manifest.json')))
        m = json.loads(env['payload'])
        self.assertEqual((m['channel'], m['version'], m['files'], m['native']['layout']), ('unity', 1, [], 'tree'))
        # the blobs are plain, named by hash
        h = next(f['sha256'] for f in m['native']['files'] if f['path'] == 'UnityPlayer.dll')
        self.assertEqual(open(mum.native_blob_path(self.site, h), 'rb').read(), b'player')
        # a version that is not newer is refused, the next one is fine
        code, _, err = run(['build', x, '--out', self.site, '--key', self.key, '--version', '1'])
        self.assertNotEqual(code, 0)
        self.assertIn('not newer', err)
        code, out, _ = run(['build', x, '--out', self.site, '--key', self.key])
        self.assertEqual(code, 0)
        self.assertIn('published unity version 2 (was 1)', out)
        # the main client's checker refuses this manifest, and ours refuses a main client's
        self.assertIsNotNone(mum.check_payload(m))

    def test_verify_catches_a_changed_blob_and_a_wrong_key(self):
        self.pack()
        run(['build', self.extract(), '--out', self.site, '--key', self.key])
        env = json.load(open(os.path.join(self.site, 'manifest.json')))
        m = json.loads(env['payload'])
        h = next(f['sha256'] for f in m['native']['files'] if f['path'] == 'ChaosUnity.exe')
        with open(mum.native_blob_path(self.site, h), 'wb') as f:
            f.write(b'EXE')
        code, _, err = run(['verify', self.site, '--public', self.public])
        self.assertNotEqual(code, 0)
        self.assertIn('ChaosUnity.exe', err)
        code, _, err = run(['verify', self.site, '--public', '00' * 32])
        self.assertNotEqual(code, 0)
        self.assertIn('bad signature', err)

    def test_build_refuses_a_changed_download(self):
        self.pack()
        x = self.extract()
        write(x, 'UnityPlayer.dll', b'tampered')
        code, _, err = run(['build', x, '--out', self.site, '--key', self.key])
        self.assertNotEqual(code, 0)
        self.assertIn('do not match', err)
        self.assertFalse(os.path.exists(os.path.join(self.site, 'manifest.json')))
        # an extra file
        x2 = self.extract('x2')
        write(x2, 'extra.dll')
        code, _, err = run(['build', x2, '--out', self.site, '--key', self.key])
        self.assertNotEqual(code, 0)
        # no build manifest
        os.remove(os.path.join(x2, 'unity_build.json'))
        code, _, err = run(['build', x2, '--out', self.site, '--key', self.key])
        self.assertNotEqual(code, 0)
        self.assertIn('unity_build.json', err)

    def test_old_blobs_are_pruned(self):
        self.pack()
        run(['build', self.extract(), '--out', self.site, '--key', self.key])
        old = [os.path.join(d, n) for d, _, ns in os.walk(os.path.join(self.site, 'native')) for n in ns]
        self.assertEqual(len(old), 8)
        write(self.player, 'UnityPlayer.dll', b'player v2')
        os.remove(self.zip)
        self.pack()
        code, out, err = run(['build', self.extract('y'), '--out', self.site, '--key', self.key])
        self.assertEqual(code, 0, err)
        left = [os.path.join(d, n) for d, _, ns in os.walk(os.path.join(self.site, 'native')) for n in ns]
        self.assertEqual(len(left), 8)
        self.assertIn('1 old file(s) removed', out)

    def test_a_site_inside_the_repository_is_refused(self):
        self.pack()
        inside = os.path.join(os.path.dirname(HERE), 'unity_test_site')
        code, _, err = run(['build', self.extract(), '--out', inside, '--key', self.key])
        self.assertNotEqual(code, 0)
        self.assertIn('inside the repository', err)
        self.assertFalse(os.path.exists(inside))


# a made-up client key (never a real one): the update blobs of the fake live folder are encrypted with it
FAKE_CLIENT_KEY = hashlib.sha256(b'made-up unity pair test key, not a real key').digest()
OTHER_CLIENT_KEY = hashlib.sha256(b'another made-up key').digest()


class PairTests(Base):
    """Phase 17: a keyed package adds the main client's sprite pair, the encrypted update blobs of its live folder, byte for byte."""

    def make_live(self, shards=3, enc_key=FAKE_CLIENT_KEY, dev_flag=False, drop=None, tamper=None, index_sha_wrong=False,
                  sign_key=None, name_gap=False):
        live = os.path.join(self.tmp, 'site', 'updates', 'live')
        shutil.rmtree(live, ignore_errors=True)
        os.makedirs(os.path.join(live, 'files'))
        dat = b'\x01\x02dat bytes'
        files = {'data/things/1098/Tibia.dat': dat, 'modules/game_x/x.lua': b'print(1)\n'}
        lines = ['chaos-spr-shards 1', 'signature 4660', 'sprites %d' % (shards * 4), 'per-shard 4']
        first = 1
        for i in range(shards):
            n = i + 2 if (name_gap and i == shards - 1) else i
            body = bytes((j * (i + 3)) & 255 for j in range(200 + i))
            name = 'Tibia.%03d.spr' % n
            files['data/things/1098/' + name] = body
            sha = hashlib.sha256(body).hexdigest()
            if index_sha_wrong and i == 1:
                sha = '0' * 64
            lines.append('shard %d 4 %s %d %s' % (first, name, len(body), sha))
            first += 4
        files['data/things/1098/Tibia.sprshards'] = ('\n'.join(lines) + '\n').encode()
        entries = []
        for path, body in sorted(files.items()):
            if drop and path.endswith(drop):
                continue
            blob = uc.encrypt(body, enc_key, dev=dev_flag)
            if tamper and path.endswith(tamper):
                blob = blob[:40] + bytes([blob[40] ^ 1]) + blob[41:]
            bsha = hashlib.sha256(blob).hexdigest()
            dst = os.path.join(live, 'files', bsha[:2], bsha)
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            with open(dst, 'wb') as f:
                f.write(blob)
            entries.append((path, hashlib.sha256(body).hexdigest(), len(body), bsha, len(blob)))
        payload = mum.make_payload(entries, 5, 0, 13, 4, 'live', '2026-11-08T00:00:00Z')
        seed = mum.read_seed(sign_key or self.key)
        public = mum.public_from_seed(seed)
        sig = mum.sign(seed, payload.encode('ascii'))
        with open(os.path.join(live, 'manifest.json'), 'w') as f:
            f.write(mum.make_envelope(payload, public.hex(), sig.hex()))
        return live, entries

    def pack_keyed(self, embed=True):
        argv = ['pack', self.player, '--out', self.zip, '--package', '31']
        if embed:
            argv.append('--embed-client-key')
        code, out, err = run(argv)
        self.assertEqual(code, 0, err)
        return out

    def build(self, live=None, x=None, out=None, env_key=None):
        argv = ['build', x or self.extract(), '--out', out or self.site, '--key', self.key]
        if live:
            argv += ['--pair-from', live]
        if env_key is not None:
            os.environ['CHAOS_CLIENT_KEY'] = env_key.hex()
        try:
            return run(argv)
        finally:
            os.environ.pop('CHAOS_CLIENT_KEY', None)

    def test_pack_marks_keyed_and_dev(self):
        out = self.pack_keyed(True)
        self.assertIn('KEYED', out)
        info = json.load(open(os.path.join(self.extract('k'), 'unity_build.json')))
        self.assertIs(info['embed_client_key'], True)
        self.assertNotIn('dev', info['native'])
        os.remove(self.zip)
        out = self.pack_keyed(False)
        self.assertIn('DEV package', out)
        info = json.load(open(os.path.join(self.extract('d'), 'unity_build.json')))
        self.assertIs(info['embed_client_key'], False)
        # only a boolean: no key text anywhere in the file
        text = open(os.path.join(self.tmp, 'd', 'unity_build.json')).read()
        self.assertNotIn(FAKE_CLIENT_KEY.hex(), text)

    def test_keyed_package_gets_the_pair_byte_for_byte(self):
        self.pack_keyed()
        live, entries = self.make_live()
        code, out, err = self.build(live)
        self.assertEqual(code, 0, err)
        self.assertIn('sprite pair: data/things/1098/ (5 blobs', out)
        self.assertIn('ciphertext checked only', out)
        self.assertIn('KEYED', out)
        code, out, err = run(['verify', self.site, '--public', self.public])
        self.assertEqual(code, 0, err)
        self.assertIn('13 files', out)
        self.assertIn('keyed, 5 sprite pair blobs', out)
        m = json.loads(json.load(open(os.path.join(self.site, 'manifest.json')))['payload'])
        self.assertIs(m['native']['dev'], False)
        pair = {f['path']: f for f in m['native']['files'] if f['path'].startswith('things_enc/')}
        self.assertEqual(sorted(pair), ['things_enc/Tibia.000.spr.chub', 'things_enc/Tibia.001.spr.chub', 'things_enc/Tibia.002.spr.chub',
                                        'things_enc/Tibia.dat.chub', 'things_enc/Tibia.sprshards.chub'])
        by_path = {e[0]: e for e in entries}
        for path, f in pair.items():
            plain_name = 'data/things/1098/' + path.split('/')[1][:-len('.chub')]
            blob = by_path[plain_name][3]
            self.assertEqual((f['sha256'], f['size']), (blob, by_path[plain_name][4]))
            # the same bytes the live folder holds, under the native name
            live_bytes = open(os.path.join(live, 'files', blob[:2], blob), 'rb').read()
            self.assertEqual(open(mum.native_blob_path(self.site, f['sha256']), 'rb').read(), live_bytes)
            self.assertEqual(live_bytes[:4], b'CHUB')
        self.assertIsNone(mun.check_payload(m))
        # the live modules are not part of the pair
        self.assertFalse(any('x.lua' in p for p in pair))
        # the key never reaches the manifest
        self.assertNotIn(FAKE_CLIENT_KEY.hex(), json.dumps(m))

    def test_blobs_decrypt_with_the_key_and_the_index_is_checked(self):
        self.pack_keyed()
        live, _ = self.make_live()
        code, out, err = self.build(live, env_key=FAKE_CLIENT_KEY)
        self.assertEqual(code, 0, err)
        self.assertIn('decrypted and checked against the signed hashes and the shard index', out)
        self.assertNotIn(FAKE_CLIENT_KEY.hex(), out + err)

    def test_wrong_key_or_a_wrong_index_is_refused_with_the_key_set(self):
        self.pack_keyed()
        live, _ = self.make_live()
        code, _, err = self.build(live, env_key=OTHER_CLIENT_KEY)
        self.assertNotEqual(code, 0)
        self.assertIn('no key of CHAOS_CLIENT_KEY opens', err)
        self.assertNotIn(OTHER_CLIENT_KEY.hex(), err)
        live, _ = self.make_live(index_sha_wrong=True)
        code, _, err = self.build(live, env_key=FAKE_CLIENT_KEY)
        self.assertNotEqual(code, 0)
        self.assertIn('does not describe the shard blobs', err)
        self.assertFalse(os.path.exists(os.path.join(self.site, 'manifest.json')))

    def test_dev_package_gets_no_pair_and_says_dev(self):
        self.pack_keyed(embed=False)
        live, _ = self.make_live()
        code, out, err = self.build(live)
        self.assertEqual(code, 0, err)
        self.assertIn('no sprite pair is added', out)
        m = json.loads(json.load(open(os.path.join(self.site, 'manifest.json')))['payload'])
        self.assertIs(m['native']['dev'], True)
        self.assertFalse(any(f['path'].startswith('things_enc/') for f in m['native']['files']))
        code, out, _ = run(['verify', self.site, '--public', self.public])
        self.assertIn('DEV, 0 sprite pair blobs', out)

    def test_a_zip_without_the_flag_is_a_dev_package(self):
        self.pack_keyed()
        x = self.extract()
        path = os.path.join(x, 'unity_build.json')
        info = json.load(open(path))
        del info['embed_client_key']
        json.dump(info, open(path, 'w'))
        code, out, err = self.build(x=x)
        self.assertEqual(code, 0, err)
        m = json.loads(json.load(open(os.path.join(self.site, 'manifest.json')))['payload'])
        self.assertIs(m['native']['dev'], True)
        info['embed_client_key'] = 'yes'
        json.dump(info, open(path, 'w'))
        code, _, err = self.build(x=x, out=os.path.join(self.tmp, 'site2'))
        self.assertNotEqual(code, 0)
        self.assertIn('embed_client_key is not a boolean', err)

    def test_keyed_without_a_pair_source_is_still_fine(self):
        self.pack_keyed()
        code, out, err = self.build()
        self.assertEqual(code, 0, err)
        m = json.loads(json.load(open(os.path.join(self.site, 'manifest.json')))['payload'])
        self.assertIs(m['native']['dev'], False)
        self.assertEqual(len(m['native']['files']), 8)

    def refused(self, live, needle, env_key=None):
        code, _, err = self.build(live, env_key=env_key)
        self.assertNotEqual(code, 0)
        self.assertIn(needle, err)
        self.assertFalse(os.path.exists(os.path.join(self.site, 'manifest.json')), 'nothing may be published')

    def test_bad_live_folders_are_refused(self):
        self.pack_keyed()
        other = os.path.join(self.tmp, 'other.key')
        run_mum(['keygen', '--private', other, '--public', other + '.pub'])
        live, _ = self.make_live(sign_key=other)
        self.refused(live, 'not signed by this update key')
        live, _ = self.make_live(drop='Tibia.sprshards')
        self.refused(live, 'holds no data/things')
        live, _ = self.make_live(drop='Tibia.dat')
        self.refused(live, 'holds no data/things')
        live, _ = self.make_live(name_gap=True)
        self.refused(live, 'missing or have a gap')
        live, _ = self.make_live(dev_flag=True)
        self.refused(live, 'DEVELOPMENT key')
        # a changed blob whose hash was recomputed is only seen by a publisher that holds the key
        live, _ = self.make_live(tamper='Tibia.001.spr')
        self.refused(live, 'opens the blob', env_key=FAKE_CLIENT_KEY)
        live, _ = self.make_live()
        os.remove(os.path.join(live, 'manifest.json'))
        self.refused(live, 'manifest.json')
        live, entries = self.make_live()
        blob = next(e[3] for e in entries if e[0].endswith('Tibia.000.spr'))
        os.remove(os.path.join(live, 'files', blob[:2], blob))
        self.refused(live, 'missing or changed')
        # a plain file where a blob should be
        live, entries = self.make_live()
        e = next(e for e in entries if e[0].endswith('Tibia.dat'))
        with open(os.path.join(live, 'files', e[3][:2], e[3]), 'wb') as f:
            f.write(b'x' * e[4])
        self.refused(live, 'missing or changed')

    def test_a_player_folder_with_the_pair_folder_clashes(self):
        write(self.player, 'things_enc/Tibia.dat.chub', b'junk')
        self.pack_keyed()
        live, _ = self.make_live()
        code, _, err = self.build(live)
        self.assertNotEqual(code, 0)
        self.assertIn('things_enc/', err)

    def test_the_pair_blobs_are_pruned_when_the_pair_goes(self):
        self.pack_keyed()
        live, _ = self.make_live()
        self.build(live)
        count = lambda: sum(len(ns) for _, _, ns in os.walk(os.path.join(self.site, 'native')))
        self.assertEqual(count(), 13)
        code, out, err = self.build(x=self.extract('again'))
        self.assertEqual(code, 0, err)
        self.assertEqual(count(), 8)


if __name__ == '__main__':
    unittest.main()
