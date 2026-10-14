#!/usr/bin/env python3
"""Tests of make_update_manifest.py and ed25519_ref.py: python3 -I client/tools/make_update_manifest_test.py
Needs no extra package (the `cryptography` cross-check runs only when it is installed)."""
import io, json, os, shutil, subprocess, sys, tempfile, unittest
from contextlib import redirect_stdout, redirect_stderr

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import ed25519_ref  # noqa: E402
import make_update_manifest as mum  # noqa: E402

# RFC 8032 section 7.1, tests 1-3: secret key, public key, message, signature
RFC8032 = [
    ('9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60',
     'd75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a', '',
     'e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e065224901555fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b'),
    ('4ccd089b28ff96da9db6c346ec114e0f5b8a319f35aba624da8cf6ed4fb8a6fb',
     '3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c', '72',
     '92a009a9f0d4cab8720e820b5f642540a2b27b5416503f8fb3762223ebdb69da085ac1e43e15996e458f3613d0f11d8c387b2eaeb4302aeeb00d291612bb0c00'),
    ('c5aa8df43f9f837bedb7442f31dcb7b166d38535076f094b85ce3a2e0b4458f7',
     'fc51cd8e6218a1a38da47ed00230f0580816ed13ba3303ac5deb911548908025', 'af82',
     '6291d657deec24024827e69c3abe01a30ce548a284743a445e3680d7db5ac3ac18ff9b538d16f290ae67f760984dc6594a7c15e9716ed28dc027beceea1ec40a'),
]


def run(argv):
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


class Ed25519(unittest.TestCase):
    def test_rfc8032_reference(self):
        for sk, pk, msg, sig in RFC8032:
            sk, pk, msg, sig = bytes.fromhex(sk), bytes.fromhex(pk), bytes.fromhex(msg), bytes.fromhex(sig)
            self.assertEqual(ed25519_ref.secret_to_public(sk), pk)
            self.assertEqual(ed25519_ref.sign(sk, msg), sig)
            self.assertTrue(ed25519_ref.verify(pk, msg, sig))
            self.assertFalse(ed25519_ref.verify(pk, msg + b'x', sig))
            bad = bytearray(sig); bad[5] ^= 1
            self.assertFalse(ed25519_ref.verify(pk, msg, bytes(bad)))

    def test_tool_backend_matches(self):
        for sk, pk, msg, sig in RFC8032:
            sk, pk, msg, sig = bytes.fromhex(sk), bytes.fromhex(pk), bytes.fromhex(msg), bytes.fromhex(sig)
            self.assertEqual(mum.public_from_seed(sk), pk)
            self.assertEqual(mum.sign(sk, msg), sig)
            self.assertTrue(mum.verify_sig(pk, msg, sig))
            self.assertFalse(mum.verify_sig(pk, msg + b'!', sig))


    def test_fallback_backend(self):
        saved = mum._backend
        mum._backend = lambda: 'ref'
        try:
            self.test_tool_backend_matches()
        finally:
            mum._backend = saved


class Paths(unittest.TestCase):
    def test_accepted(self):
        for p in ('modules/game_x/x.lua', 'data/things/1098/Tibia.spr', 'data/fonts/Verdana Bold-11px.png',
                  'data/minimap/regions/63-(33253-31491-7)subarea.png', 'layouts/mobile/a.otui', 'mods/m/a+b,c.png'):
            self.assertIsNone(mum.check_path(p), p)

    def test_refused(self):
        cases = {
            '../init.lua': 'dot segment', 'modules/../init.lua': 'dot segment', '/etc/passwd': 'absolute path',
            'C:/x/y.lua': 'drive or stream name', 'modules\\x.lua': 'backslash', 'init.lua': 'not in a folder',
            'bin/x.lua': 'root not allowed', 'modules/x/client.dll': 'native code is never updated',
            'data/x/run.EXE': 'native code is never updated', 'modules/x/a.sh': 'native code is never updated',
            'modules//x.lua': 'empty segment', 'modules/./x.lua': 'dot segment', 'modules/x/con.lua': 'device name',
            'modules/x/ a.lua': 'space at an end', 'modules/x/a.': 'trailing dot', 'modules/x/a$b.lua': 'bad character',
            'modules/x/': 'trailing slash', 'modules/x/\u00e9.lua': 'bad character', '': 'empty path',
        }
        for p, why in cases.items():
            self.assertEqual(mum.check_path(p), why, p)


class Build(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix='chaos-update-test-')
        self.client = os.path.join(self.tmp, 'client')
        for rel, data in {
            'init.lua': b'-- init',
            'modules/game_a/a.lua': b'print(1)\n',
            'modules/game_a/a.otmod': b'Module\n  name: game_a\n',
            'modules/game_a/copy.lua': b'print(1)\n',  # same content as a.lua: one blob
            'data/images/x y.png': b'\x89PNG' + bytes(range(256)) * 10,
            'data/things/1098/Tibia.dat': os.urandom(4096),
            'data/things/1098/Tibia.spr': os.urandom(70000),
            'data/things/860.rar': b'skipped archive',
            'modules/game_a/a.lua.orig': b'skipped leftover',
            'mods/m/m.lua': b'x',
        }.items():
            path = os.path.join(self.client, rel)
            os.makedirs(os.path.dirname(path), exist_ok=True)
            open(path, 'wb').write(data)
        self.keys = os.path.join(self.tmp, 'keys')
        os.makedirs(self.keys)
        self.key = os.path.join(self.keys, 'update.key')
        self.out = os.path.join(self.tmp, 'site', 'updates', 'live')

    def tearDown(self):
        shutil.rmtree(self.tmp)

    def keygen(self):
        code, out, err = run(['keygen', '--private', self.key, '--public', self.key + '.pub'])
        self.assertEqual(code, 0, err)
        self.assertEqual(oct(os.stat(self.key).st_mode & 0o777), '0o600')
        return open(self.key + '.pub').read().strip()

    def test_dry_run_needs_no_key(self):
        code, out, err = run(['build', self.client, '--dry-run'])
        self.assertEqual(code, 0, err)
        self.assertIn('7 files, 6 distinct', out)
        self.assertFalse(os.path.exists(self.out))

    def test_build_sign_verify(self):
        pub = self.keygen()
        code, out, err = run(['build', self.client, '--out', self.out, '--key', self.key, '--min-package', '2'])
        self.assertEqual(code, 0, err)
        env = json.load(open(os.path.join(self.out, 'manifest.json')))
        self.assertEqual(env['format'], 'chaos-update-1')
        self.assertEqual(env['key'], pub)
        m = json.loads(env['payload'])
        self.assertEqual(m['version'], 1)
        self.assertEqual(m['min_package'], 2)
        paths = [f['path'] for f in m['files']]
        self.assertEqual(paths, sorted(paths))
        self.assertIn('data/things/1098/Tibia.spr', paths)
        self.assertNotIn('init.lua', paths)
        self.assertFalse(any(p.endswith(('.rar', '.orig')) for p in paths))
        # signature over the exact payload bytes
        self.assertTrue(mum.verify_sig(bytes.fromhex(pub), env['payload'].encode(), bytes.fromhex(env['signature'])))
        # one blob per distinct content, content-addressed
        blobs = [f for _, _, fs in os.walk(os.path.join(self.out, 'files')) for f in fs]
        self.assertEqual(len(blobs), 6)
        self.assertEqual(run(['verify', self.out, '--public', pub])[0], 0)

        # second build: version goes up; an older version is refused
        self.assertEqual(run(['build', self.client, '--out', self.out, '--key', self.key])[0], 0)
        self.assertEqual(json.loads(json.load(open(os.path.join(self.out, 'manifest.json')))['payload'])['version'], 2)
        code, out, err = run(['build', self.client, '--out', self.out, '--key', self.key, '--version', '2'])
        self.assertNotEqual(code, 0)
        self.assertIn('not newer', err)

    def test_verify_refuses_tampering(self):
        pub = self.keygen()
        self.assertEqual(run(['build', self.client, '--out', self.out, '--key', self.key])[0], 0)
        mpath = os.path.join(self.out, 'manifest.json')
        good = open(mpath).read()
        # a changed blob
        env = json.loads(good)
        f = json.loads(env['payload'])['files'][0]
        blob = os.path.join(self.out, 'files', f['sha256'][:2], f['sha256'])
        data = open(blob, 'rb').read()
        open(blob, 'wb').write(data[:-1] + bytes([data[-1] ^ 1]))
        code, out, err = run(['verify', self.out, '--public', pub])
        self.assertNotEqual(code, 0)
        self.assertIn('bad blob', err)
        open(blob, 'wb').write(data)
        # a changed payload (signature no longer matches)
        env['payload'] = env['payload'].replace('"version":1', '"version":9')
        open(mpath, 'w').write(json.dumps(env))
        code, out, err = run(['verify', self.out, '--public', pub])
        self.assertIn('bad signature', err)
        # another key
        open(mpath, 'w').write(good)
        code, out, err = run(['verify', self.out, '--public', '11' * 32])
        self.assertIn('bad signature', err)
        # unsigned
        env = json.loads(good); env['signature'] = ''
        open(mpath, 'w').write(json.dumps(env))
        code, out, err = run(['verify', self.out, '--public', pub])
        self.assertIn('not signed', err)

    def test_sprite_shards(self):
        sys.path.insert(0, os.path.join(HERE, 'sprites'))
        import spr_shards
        things = os.path.join(self.client, 'data', 'things', '1098')
        # a small valid .spr (20 sprites, every third one empty) split into shards of 8
        count, table, body = 20, [], b''
        for i in range(count):
            if i % 3 == 2:
                table.append(0)
                continue
            rec = b'\xff\x00\xff' + bytes([4, 0]) + bytes([i, 1, 2, 3])
            table.append(8 + 4 * count + len(body))
            body += rec
        spr = os.path.join(things, 'Tibia.spr')
        with open(spr, 'wb') as f:
            f.write(bytes.fromhex('03d6bb57') + count.to_bytes(4, 'little'))
            f.write(b''.join(a.to_bytes(4, 'little') for a in table) + body)
        spr_shards.split(spr, things, per_shard=8, quiet=True)
        code, out, err = run(['build', self.client, '--dry-run', '--min-package', '3'])
        self.assertNotEqual(code, 0)
        self.assertIn('both here', err)
        code, out, err = run(['build', self.client, '--dry-run', '--with-single-spr'])
        self.assertEqual(code, 0, err)
        self.assertIn('11 files', out)  # 7 + the index + 3 shards
        os.remove(spr)
        code, out, err = run(['build', self.client, '--dry-run'])
        self.assertNotEqual(code, 0)
        self.assertIn('needs --min-package', err)
        code, out, err = run(['build', self.client, '--dry-run', '--min-package', '3'])
        self.assertEqual(code, 0, err)
        self.assertIn('10 files', out)
        self.assertNotIn('without a shard set', err)
        # a shard changed after the split (same size): its hash no longer matches the index
        with open(os.path.join(things, 'Tibia.001.spr'), 'r+b') as f:
            f.seek(-1, 2)
            f.write(b'\x00')
        code, out, err = run(['build', self.client, '--dry-run', '--min-package', '3'])
        self.assertNotEqual(code, 0)
        self.assertIn('Tibia.001.spr: SHA-256 differs', err)
        # a missing shard
        os.remove(os.path.join(things, 'Tibia.002.spr'))
        code, out, err = run(['build', self.client, '--dry-run', '--min-package', '3'])
        self.assertNotEqual(code, 0)
        self.assertIn('missing shard', err)

    def test_single_spr_warning(self):
        code, out, err = run(['build', self.client, '--dry-run'])
        self.assertEqual(code, 0, err)
        self.assertIn('Tibia.spr without a shard set', err)

    def test_refuses_bad_files(self):
        for rel in ('modules/game_a/evil.dll', 'data/a\\b.png', 'modules/game_a/A.LUA'):
            path = os.path.join(self.client, rel)
            open(path, 'wb').write(b'x')
            code, out, err = run(['build', self.client, '--dry-run'])
            self.assertNotEqual(code, 0, rel)
            self.assertIn('refused', err)
            os.remove(path)
        self.assertEqual(run(['build', self.client, '--dry-run'])[0], 0)

    def test_keys_never_in_the_repo(self):
        inside = os.path.join(HERE, 'update-test.key')
        code, out, err = run(['keygen', '--private', inside])
        self.assertNotEqual(code, 0)
        self.assertIn('refused', err)
        self.assertFalse(os.path.exists(inside))
        code, out, err = run(['build', self.client, '--out', os.path.join(HERE, 'pub'), '--key', inside])
        self.assertNotEqual(code, 0)
        self.assertFalse(os.path.exists(os.path.join(HERE, 'pub')))

    def test_no_key_no_publish(self):
        os.environ.pop('CHAOS_UPDATE_KEY', None)
        code, out, err = run(['build', self.client, '--out', self.out])
        self.assertNotEqual(code, 0)
        self.assertIn('no private key', err)

    def test_payload_checks(self):
        m = json.loads(mum.make_payload([('modules/a/a.lua', 'a' * 64, 1)], 3, 0, 0, 4, 'live', 'now'))
        self.assertIsNone(mum.check_payload(m))
        self.assertEqual(mum.check_payload(m, last_version=4), 'older manifest')
        m['files'].append({'path': 'MODULES/a/A.lua', 'sha256': 'b' * 64, 'size': 1})
        self.assertIn('root not allowed', mum.check_payload(m))
        m['files'][-1]['path'] = 'modules/a/A.lua'
        self.assertIn('duplicate', mum.check_payload(m))


if __name__ == '__main__':
    unittest.main(verbosity=1)
