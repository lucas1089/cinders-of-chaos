#!/usr/bin/env python3
"""Tests of make_unity_manifest.py: python3 -I client/tools/make_unity_manifest_test.py
Pack a fake Unity player folder, publish it signed, verify it, and refuse the bad cases. The key is a throwaway one."""
import hashlib, io, json, os, shutil, sys, tempfile, unittest, zipfile
from contextlib import redirect_stdout, redirect_stderr

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import make_unity_manifest as mun  # noqa: E402
import make_update_manifest as mum  # noqa: E402


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


if __name__ == '__main__':
    unittest.main()
