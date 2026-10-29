#!/usr/bin/env python3
"""Tests of make_update_manifest.py, update_crypt.py and ed25519_ref.py:
python3 -I client/tools/make_update_manifest_test.py
Publishing encrypts every blob (update_crypt.py), which needs the `cryptography` package (CI has it)."""
import hashlib, io, json, os, re, shutil, subprocess, sys, tempfile, unittest
from contextlib import redirect_stdout, redirect_stderr

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import ed25519_ref  # noqa: E402
import make_update_manifest as mum  # noqa: E402
import pack_client  # noqa: E402
import update_crypt as uc  # noqa: E402

TEST_KEY = '5a' * 32      # a throwaway client key (never a real one)
OTHER_KEY = 'c3' * 32

# the fixed cross-language vector: client key bytes 00..1f, plaintext "Cinders of Chaos update blob";
# tools/chaosblob_test.cpp decrypts the same bytes with the engine header (base patch 0103)
VECTOR_KEY = bytes(range(32))
VECTOR_PLAIN = b'Cinders of Chaos update blob'
VECTOR_BLOB = ('434855420100000056081a63ae5ba02bfc8785411c00000000000000228f968fdbd0179714570604cf59bf2902453d372f5e93'
               'b3d523a2ffb9be36b66b2d2b9c1412c280daa56a5d')

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
        self.saved_env = os.environ.get(mum.KEY_ENV)
        os.environ[mum.KEY_ENV] = TEST_KEY

    def tearDown(self):
        shutil.rmtree(self.tmp)
        if self.saved_env is None:
            os.environ.pop(mum.KEY_ENV, None)
        else:
            os.environ[mum.KEY_ENV] = self.saved_env

    def payload(self):
        return json.loads(json.load(open(os.path.join(self.out, 'manifest.json')))['payload'])

    def blob_files(self):
        return [os.path.join(d, f) for d, _, fs in os.walk(os.path.join(self.out, 'files')) for f in fs]

    def keygen(self):
        code, out, err = run(['keygen', '--private', self.key, '--public', self.key + '.pub'])
        self.assertEqual(code, 0, err)
        self.assertEqual(oct(os.stat(self.key).st_mode & 0o777), '0o600')
        return open(self.key + '.pub').read().strip()

    def test_pubkey(self):
        pub = self.keygen()
        code, out, err = run(['pubkey', '--private', self.key])
        self.assertEqual(code, 0, err)
        self.assertEqual(out.strip(), pub)

    def test_dry_run_needs_no_key(self):
        code, out, err = run(['build', self.client, '--dry-run'])
        self.assertEqual(code, 0, err)
        self.assertIn('7 files, 6 distinct', out)
        self.assertFalse(os.path.exists(self.out))
        os.environ.pop(mum.KEY_ENV)
        self.assertEqual(run(['build', self.client, '--dry-run'])[0], 0, 'dry run without the blob key')

    def test_build_sign_verify(self):
        pub = self.keygen()
        code, out, err = run(['build', self.client, '--out', self.out, '--key', self.key, '--min-package', '13'])
        self.assertEqual(code, 0, err)
        self.assertNotIn(TEST_KEY, out + err, 'the blob key is never printed')
        env = json.load(open(os.path.join(self.out, 'manifest.json')))
        self.assertEqual(env['format'], 'chaos-update-1')
        self.assertEqual(env['key'], pub)
        m = json.loads(env['payload'])
        self.assertEqual(m['version'], 1)
        self.assertEqual(m['min_package'], 13)
        self.assertEqual(m['encryption'], 'chaos-blob-1')
        paths = [f['path'] for f in m['files']]
        self.assertEqual(paths, sorted(paths))
        self.assertIn('data/things/1098/Tibia.spr', paths)
        self.assertNotIn('init.lua', paths)
        self.assertFalse(any(p.endswith(('.rar', '.orig')) for p in paths))
        # signature over the exact payload bytes
        self.assertTrue(mum.verify_sig(bytes.fromhex(pub), env['payload'].encode(), bytes.fromhex(env['signature'])))
        # one encrypted blob per distinct content, addressed by the blob's own SHA-256; nothing plain on the site
        blobs = self.blob_files()
        self.assertEqual(len(blobs), 6)
        by_path = {f['path']: f for f in m['files']}
        self.assertEqual(by_path['modules/game_a/a.lua']['blob'], by_path['modules/game_a/copy.lua']['blob'])
        key = bytes.fromhex(TEST_KEY)
        for f in m['files']:
            blob = os.path.join(self.out, 'files', f['blob'][:2], f['blob'])
            data = open(blob, 'rb').read()
            self.assertEqual(len(data), f['size'] + 44)
            self.assertEqual(mum.sha256_file(blob), f['blob'])
            self.assertEqual(data[:4], b'CHUB')
            plain = open(os.path.join(self.client, f['path']), 'rb').read()
            self.assertEqual(uc.decrypt(data, key), plain, f['path'])
            if len(plain) > 8:
                self.assertNotIn(plain[:16], data, 'no plaintext on the site: ' + f['path'])
        code, out, err = run(['verify', self.out, '--public', pub])
        self.assertEqual(code, 0, err)
        self.assertIn('decrypts to its signed content', out)
        os.environ.pop(mum.KEY_ENV)
        code, out, err = run(['verify', self.out, '--public', pub])
        self.assertEqual(code, 0, err)
        self.assertIn('ciphertext only', out)
        os.environ[mum.KEY_ENV] = OTHER_KEY
        code, out, err = run(['verify', self.out, '--public', pub])
        self.assertNotEqual(code, 0)
        self.assertIn('does not decrypt to the signed content', err)
        os.environ[mum.KEY_ENV] = TEST_KEY

        # second build: version goes up, the same blobs (deterministic); an older version is refused
        before = sorted(self.blob_files())
        code, out, err = run(['build', self.client, '--out', self.out, '--key', self.key, '--min-package', '13'])
        self.assertEqual(code, 0, err)
        self.assertIn('0 new blob(s)', out)
        self.assertEqual(sorted(self.blob_files()), before)
        self.assertEqual(self.payload()['version'], 2)
        self.assertEqual([f['blob'] for f in self.payload()['files']], [f['blob'] for f in m['files']])
        code, out, err = run(['build', self.client, '--out', self.out, '--key', self.key, '--version', '2',
                              '--min-package', '13'])
        self.assertNotEqual(code, 0)
        self.assertIn('not newer', err)

    def set_baseline(self, n):
        open(os.path.join(self.client, 'init.lua'), 'w').write(
            'Services = {\n  update = {\n    manifest = "",\n    package = 11,\n    baseline = %d,\n'
            '    required = false\n  }\n}\n' % n)

    def test_package_baseline(self):
        # base patch 0101: the package's release number is the version of its files
        self.assertEqual(mum.package_baseline(self.client), 0, 'no update block: no baseline')
        self.set_baseline(47)
        self.assertEqual(mum.package_baseline(self.client), 47)
        self.keygen()
        mp = ['--min-package', '13']
        code, out, err = run(['build', self.client, '--out', self.out, '--key', self.key] + mp)
        self.assertEqual(code, 0, err)
        self.assertEqual(json.loads(json.load(open(os.path.join(self.out, 'manifest.json')))['payload'])['version'], 47)
        # another number for these files is refused (lower: own players skip it; higher: newer packages downgrade)
        for v in ('46', '48'):
            code, out, err = run(['build', self.client, '--out', self.out, '--key', self.key, '--version', v] + mp)
            self.assertNotEqual(code, 0)
            self.assertIn('baseline 47', err)
        # an older package (baseline 46) after 47 is live: refused, nothing changes
        self.set_baseline(46)
        code, out, err = run(['build', self.client, '--out', self.out, '--key', self.key] + mp)
        self.assertNotEqual(code, 0)
        self.assertIn('publish a newer package', err)
        self.assertEqual(json.loads(json.load(open(os.path.join(self.out, 'manifest.json')))['payload'])['version'], 47)
        code, out, err = run(['build', self.client, '--dry-run'])
        self.assertEqual(code, 0, err)
        self.assertIn('version 46 (package baseline 46)', out)

    def test_verify_refuses_tampering(self):
        pub = self.keygen()
        self.assertEqual(run(['build', self.client, '--out', self.out, '--key', self.key, '--min-package', '13'])[0], 0)
        mpath = os.path.join(self.out, 'manifest.json')
        good = open(mpath).read()
        # a changed blob
        env = json.loads(good)
        f = json.loads(env['payload'])['files'][0]
        blob = os.path.join(self.out, 'files', f['blob'][:2], f['blob'])
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

    def test_spr_over_the_limit_ships_as_shards(self):
        """pair 37: a Tibia.spr over the updater's 1 GiB is refused, its shard set publishes (the limit lowered to a
        few hundred bytes stands in for 1 GiB)"""
        sys.path.insert(0, os.path.join(HERE, 'sprites'))
        import spr_shards
        things = os.path.join(self.client, 'data', 'things', '1098')
        count, table, body = 40, [], b''
        for i in range(count):
            rec = b'\xff\x00\xff' + bytes([4, 0]) + bytes([i, 1, 2, 3])
            table.append(8 + 4 * count + len(body))
            body += rec
        spr = os.path.join(things, 'Tibia.spr')
        with open(spr, 'wb') as f:
            f.write(bytes.fromhex('03d6bb57') + count.to_bytes(4, 'little'))
            f.write(b''.join(a.to_bytes(4, 'little') for a in table) + body)
        os.remove(os.path.join(self.client, 'data', 'images', 'x y.png'))
        os.remove(os.path.join(things, 'Tibia.dat'))
        open(os.path.join(things, 'Tibia.dat'), 'wb').write(b'dat')
        limit = os.path.getsize(spr) - 1
        saved = mum.MAX_FILE_SIZE
        mum.MAX_FILE_SIZE = limit
        try:
            code, out, err = run(['build', self.client, '--dry-run', '--min-package', '15'])
            self.assertNotEqual(code, 0)
            self.assertIn('data/things/1098/Tibia.spr: larger than %d bytes' % limit, err)
            self.assertIn('spr_shards.py split', err)
            spr_shards.split(spr, things, per_shard=16, quiet=True)
            spr_shards.verify(spr, things, quiet=True)
            os.remove(spr)
            shards = [f for f in os.listdir(things) if spr_shards.SHARD_NAME.match(f)]
            self.assertEqual(len(shards), 3)
            self.assertTrue(all(os.path.getsize(os.path.join(things, f)) <= limit for f in shards))
            code, out, err = run(['build', self.client, '--dry-run', '--min-package', '15'])
            self.assertEqual(code, 0, err)
            # the real publish: every listed file within the limit, the client's own payload check passes
            self.keygen()
            code, out, err = run(['build', self.client, '--out', self.out, '--key', self.key, '--min-package', '15',
                                  '--version', '37'])
            self.assertEqual(code, 0, err)
            m = self.payload()
            self.assertIsNone(mum.check_payload(m))
            paths = {f['path'] for f in m['files']}
            self.assertNotIn('data/things/1098/Tibia.spr', paths)
            self.assertIn('data/things/1098/Tibia.sprshards', paths)
            self.assertTrue(all(f['size'] <= limit for f in m['files']))
            # a manifest listing a file over the limit is what the clients refuse
            m['files'][0]['size'] = limit + 1
            self.assertIn('bad size', mum.check_payload(m))
        finally:
            mum.MAX_FILE_SIZE = saved

    def test_overlay_limit(self):
        entries = [('data/a.bin', 'x', 100), ('modules/b.lua', 'y', 5)]
        self.assertEqual(mum.overlay_size(entries), 22 + 76 + 20 + 100 + 76 + 26 + 5)
        saved = mum.MAX_OVERLAY_SIZE
        mum.MAX_OVERLAY_SIZE = 1000
        try:
            code, out, err = run(['build', self.client, '--dry-run'])
            self.assertNotEqual(code, 0)
            self.assertIn('update overlay', err)
        finally:
            mum.MAX_OVERLAY_SIZE = saved
        self.assertEqual(run(['build', self.client, '--dry-run'])[0], 0)

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
        code, out, err = run(['build', self.client, '--out', self.out, '--min-package', '13'])
        self.assertNotEqual(code, 0)
        self.assertIn('no private key', err)

    def test_no_blob_key_no_publish(self):
        # no CHAOS_CLIENT_KEY: refused, nothing written (never a plain fallback)
        self.keygen()
        os.environ.pop(mum.KEY_ENV)
        code, out, err = run(['build', self.client, '--out', self.out, '--key', self.key, '--min-package', '13'])
        self.assertNotEqual(code, 0)
        self.assertIn('no blob key', err)
        self.assertFalse(os.path.exists(os.path.join(self.out, 'manifest.json')))
        os.environ[mum.KEY_ENV] = 'not-hex'
        code, out, err = run(['build', self.client, '--out', self.out, '--key', self.key, '--min-package', '13'])
        self.assertNotEqual(code, 0)
        self.assertIn('64 hex digits', err)
        self.assertNotIn('not-hex', err, 'the value is never quoted')

    def test_encrypted_needs_min_package(self):
        self.keygen()
        code, out, err = run(['build', self.client, '--out', self.out, '--key', self.key, '--min-package', '12'])
        self.assertNotEqual(code, 0)
        self.assertIn('--min-package 13', err)
        self.assertFalse(os.path.exists(os.path.join(self.out, 'manifest.json')))

    def test_dev_key(self):
        # --dev: the public development key, flagged in every blob header; any min_package (tests)
        pub = self.keygen()
        os.environ.pop(mum.KEY_ENV)
        code, out, err = run(['build', self.client, '--out', self.out, '--key', self.key, '--dev'])
        self.assertEqual(code, 0, err)
        self.assertIn('DEVELOPMENT key', out)
        dev = bytes.fromhex(uc.DEV_KEY_HEX)
        for path in self.blob_files():
            self.assertEqual(uc.header_flags(path) & uc.FLAG_DEV, uc.FLAG_DEV)
            uc.decrypt_file(path, dev)
        self.assertEqual(run(['verify', self.out, '--public', pub, '--dev'])[0], 0)
        os.environ[mum.KEY_ENV] = TEST_KEY
        code, out, err = run(['verify', self.out, '--public', pub])
        self.assertNotEqual(code, 0, 'dev blobs do not open with the real key')

    def test_key_rotation(self):
        # CHAOS_CLIENT_KEY "old,new": the index picks the key; without it the build refuses
        self.keygen()
        os.environ[mum.KEY_ENV] = OTHER_KEY + ',' + TEST_KEY
        code, out, err = run(['build', self.client, '--out', self.out, '--key', self.key, '--min-package', '13'])
        self.assertNotEqual(code, 0)
        self.assertIn('--key-index', err)
        code, out, err = run(['build', self.client, '--out', self.out, '--key', self.key, '--min-package', '13',
                              '--key-index', '2'])
        self.assertEqual(code, 0, err)
        f = self.payload()['files'][0]
        uc.decrypt_file(os.path.join(self.out, 'files', f['blob'][:2], f['blob']), bytes.fromhex(TEST_KEY))
        code, out, err = run(['build', self.client, '--out', self.out, '--key', self.key, '--min-package', '13',
                              '--key-index', '3'])
        self.assertNotEqual(code, 0)

    def test_old_plain_blobs_removed(self):
        # a publish before build 13 left plain blobs under files/<sha[:2]>/<sha>: the encrypted publish removes them
        self.keygen()
        plain_sha = mum.sha256_file(os.path.join(self.client, 'modules/game_a/a.lua'))
        old = os.path.join(self.out, 'files', plain_sha[:2], plain_sha)
        os.makedirs(os.path.dirname(old))
        shutil.copyfile(os.path.join(self.client, 'modules/game_a/a.lua'), old)
        open(os.path.join(self.out, 'files', 'stray.tmp'), 'w').write('x')
        code, out, err = run(['build', self.client, '--out', self.out, '--key', self.key, '--min-package', '13'])
        self.assertEqual(code, 0, err)
        self.assertIn('2 old file(s) removed', out)
        self.assertFalse(os.path.exists(old))
        listed = {f['blob'] for f in self.payload()['files']}
        self.assertEqual({os.path.basename(p) for p in self.blob_files()}, listed)
        # a changed file: its new blob is added, the old one removed
        open(os.path.join(self.client, 'modules/game_a/a.lua'), 'wb').write(b'print(2)\n')
        code, out, err = run(['build', self.client, '--out', self.out, '--key', self.key, '--min-package', '13'])
        self.assertEqual(code, 0, err)
        self.assertIn('1 new blob(s), 0 old file(s) removed', out)  # copy.lua still holds print(1)
        open(os.path.join(self.client, 'modules/game_a/copy.lua'), 'wb').write(b'print(2)\n')
        code, out, err = run(['build', self.client, '--out', self.out, '--key', self.key, '--min-package', '13'])
        self.assertIn('0 new blob(s), 1 old file(s) removed', out)  # print(1) is gone

    def test_unpack_packed_client(self):
        # a build-13 package ships chaos.pack: unpack opens it with the key of CHAOS_CLIENT_KEY that fits
        pack = os.path.join(self.tmp, 'chaos.pack')
        key = bytes.fromhex(TEST_KEY)
        open(pack, 'wb').write(pack_client.encrypt_pack(pack_client.build_zip(self.client), key))
        os.environ[mum.KEY_ENV] = OTHER_KEY + ',' + TEST_KEY
        dest = os.path.join(self.tmp, 'tree')
        code, out, err = run(['unpack', pack, dest])
        self.assertEqual(code, 0, err)
        self.assertIn('key-index=2', out)
        self.assertEqual(open(os.path.join(dest, 'modules/game_a/a.lua'), 'rb').read(), b'print(1)\n')
        self.assertEqual(open(os.path.join(dest, 'data/things/1098/Tibia.spr'), 'rb').read(),
                         open(os.path.join(self.client, 'data/things/1098/Tibia.spr'), 'rb').read())
        self.assertEqual([n for n in os.listdir(self.tmp) if n.startswith('.pack-')], [], 'temporary zip removed')
        os.environ[mum.KEY_ENV] = OTHER_KEY
        code, out, err = run(['unpack', pack, os.path.join(self.tmp, 'tree2')])
        self.assertNotEqual(code, 0)
        self.assertIn('no key', err)
        os.environ.pop(mum.KEY_ENV)
        code, out, err = run(['unpack', pack, os.path.join(self.tmp, 'tree3')])
        self.assertNotEqual(code, 0)
        self.assertIn('no CHAOS_CLIENT_KEY', err)
        # a development pack needs --dev
        devpack = os.path.join(self.tmp, 'dev.pack')
        open(devpack, 'wb').write(pack_client.encrypt_pack(b'PK\x05\x06' + bytes(18), bytes.fromhex(uc.DEV_KEY_HEX),
                                                           is_dev=True))
        code, out, err = run(['unpack', devpack, os.path.join(self.tmp, 'tree4')])
        self.assertNotEqual(code, 0)
        self.assertIn('DEVELOPMENT pack', err)
        code, out, err = run(['unpack', devpack, os.path.join(self.tmp, 'tree5'), '--dev'])
        self.assertEqual(code, 0, err)

    def test_payload_checks(self):
        m = json.loads(mum.make_payload([('modules/a/a.lua', 'a' * 64, 1, 'c' * 64, 45)], 3, 0, 0, 4, 'live', 'now'))
        self.assertIsNone(mum.check_payload(m))
        self.assertEqual(mum.check_payload(m, last_version=4), 'older manifest')
        m['files'][0]['blob_size'] = 1
        self.assertIn('bad blob_size', mum.check_payload(m))
        m['files'][0]['blob_size'] = 45
        m['files'][0]['blob'] = 'x'
        self.assertIn('bad blob', mum.check_payload(m))
        m['files'][0]['blob'] = 'c' * 64
        m['files'].append({'path': 'MODULES/a/A.lua', 'sha256': 'b' * 64, 'size': 1, 'blob': 'd' * 64, 'blob_size': 45})
        self.assertIn('root not allowed', mum.check_payload(m))
        m['files'][-1]['path'] = 'modules/a/A.lua'
        self.assertIn('duplicate', mum.check_payload(m))
        del m['encryption']
        self.assertEqual(mum.check_payload(m), 'manifest is not encrypted')


class Native(unittest.TestCase):
    """native files for the game launcher (O314): a separate section of the signed payload, plain blobs in native/,
    nothing changed for the Lua updater of the clients already out"""
    tearDown = Build.tearDown
    payload, blob_files, keygen = Build.payload, Build.blob_files, Build.keygen

    def _setup(self):
        Build.setUp(self)
        self.nat = os.path.join(self.tmp, 'native')
        os.makedirs(self.nat)
        self.nat_files = {'Chaos.exe': b'MZ' + os.urandom(3000), 'libssl-3-x64.dll': os.urandom(2000),
                          'chaos.pack': b'CHPK' + os.urandom(9000), 'CindersLauncher.exe': b'MZ' + os.urandom(500)}
        for name, data in self.nat_files.items():
            open(os.path.join(self.nat, name), 'wb').write(data)
        self.pub = self.keygen()

    def setUp(self):  # noqa: F811
        self._setup()

    def publish(self, *extra, native=True):
        argv = ['build', self.client, '--out', self.out, '--key', self.key, '--min-package', '13']
        if native:
            argv += ['--native-dir', self.nat, '--native-package', '14', '--native-launcher', 'CindersLauncher.exe']
        return run(argv + list(extra))

    def native_blobs(self):
        return sorted(f for d, _, fs in os.walk(os.path.join(self.out, 'native')) for f in fs)

    def test_section_and_plain_blobs(self):
        code, out, err = self.publish()
        self.assertEqual(code, 0, err)
        n = self.payload()['native']
        self.assertEqual((n['package'], n['game'], n['launcher'], n['files_url']),
                         (14, 'Chaos.exe', 'CindersLauncher.exe', 'native/'))
        self.assertEqual([f['path'] for f in n['files']], sorted(self.nat_files, key=lambda s: s))
        for f in n['files']:
            data = self.nat_files[f['path']]
            self.assertEqual((f['sha256'], f['size']), (hashlib.sha256(data).hexdigest(), len(data)))
            blob = os.path.join(self.out, 'native', f['sha256'][:2], f['sha256'])
            self.assertEqual(open(blob, 'rb').read(), data, 'native blobs are plain')
        code, out, err = run(['verify', self.out, '--public', self.pub])
        self.assertEqual(code, 0, err)
        self.assertIn('4 native files (package 14)', out)

    def test_old_clients_see_the_same_files(self):
        self.assertEqual(self.publish(native=False)[0], 0)
        plain = self.payload()
        shutil.rmtree(self.out)
        self.assertEqual(self.publish()[0], 0)
        withn = self.payload()
        for k in ('files', 'format', 'product', 'version', 'min_version', 'min_package', 'files_url', 'encryption',
                  'parallel'):
            self.assertEqual(plain[k], withn[k], k)
        self.assertNotIn('native', plain)
        self.assertEqual(set(withn) - set(plain), {'native'})
        # the Lua updater's path rules still hold: no native file leaks into "files"
        self.assertFalse([f for f in withn['files'] if f['path'].lower().endswith(('.exe', '.dll', '.pack'))])
        self.assertEqual(len(self.blob_files()), len({f['blob'] for f in withn['files']}))

    def test_dry_run(self):
        code, out, err = run(['build', self.client, '--dry-run', '--native-dir', self.nat, '--native-package', '14'])
        self.assertEqual(code, 0, err)
        self.assertIn('native package 14 (4 files)', out)

    def test_tampered_native_blob_fails_verify(self):
        self.assertEqual(self.publish()[0], 0)
        f = [f for f in self.payload()['native']['files'] if f['path'] == 'Chaos.exe'][0]
        blob = os.path.join(self.out, 'native', f['sha256'][:2], f['sha256'])
        open(blob, 'ab').write(b'x')
        code, out, err = run(['verify', self.out, '--public', self.pub])
        self.assertNotEqual(code, 0)
        self.assertIn('bad native file Chaos.exe', err)

    def test_native_section_is_signed(self):
        self.assertEqual(self.publish()[0], 0)
        mpath = os.path.join(self.out, 'manifest.json')
        env = json.load(open(mpath))
        env['payload'] = env['payload'].replace('"package":14', '"package":15')
        json.dump(env, open(mpath, 'w'))
        code, out, err = run(['verify', self.out, '--public', self.pub])
        self.assertNotEqual(code, 0)
        self.assertIn('bad signature', err)

    def test_refused_inputs(self):
        def refused(msg, *extra):
            code, out, err = self.publish(*extra)
            self.assertNotEqual(code, 0, msg)
            self.assertFalse(os.path.exists(os.path.join(self.out, 'manifest.json')), 'nothing published: ' + msg)
            return err
        open(os.path.join(self.nat, 'run.bat'), 'w').write('x')
        self.assertIn('only .exe .dll .pack', refused('bat'))
        os.remove(os.path.join(self.nat, 'run.bat'))
        os.makedirs(os.path.join(self.nat, 'sub'))
        self.assertIn('not a plain file', refused('folder'))
        os.rmdir(os.path.join(self.nat, 'sub'))
        open(os.path.join(self.nat, 'bad name.dll'), 'wb').write(b'x')
        self.assertIn('bad file name', refused('space'))
        os.remove(os.path.join(self.nat, 'bad name.dll'))
        open(os.path.join(self.nat, 'nul.dll'), 'wb').write(b'x')
        self.assertIn('device name', refused('device'))
        os.remove(os.path.join(self.nat, 'nul.dll'))
        # package below min-package, no package, missing game or launcher
        code, _, err = run(['build', self.client, '--out', self.out, '--key', self.key, '--min-package', '13',
                            '--native-dir', self.nat, '--native-package', '12'])
        self.assertNotEqual(code, 0)
        self.assertIn('below --min-package', err)
        code, _, err = run(['build', self.client, '--out', self.out, '--key', self.key, '--min-package', '13',
                            '--native-dir', self.nat])
        self.assertNotEqual(code, 0)
        self.assertIn('needs --native-package', err)
        self.assertIn('--native-game Nope.exe', refused('game', '--native-game', 'Nope.exe'))
        self.assertIn('--native-launcher', refused('launcher', '--native-launcher', 'Missing.exe'))

    def test_payload_rules(self):
        good = mum.make_native([('Chaos.exe', 'a' * 64, 5), ('x.dll', 'b' * 64, 0)], 14, 'Chaos.exe', None)
        self.assertIsNone(mum.check_native(good))
        def bad(**kw):
            n = json.loads(json.dumps(good))
            for k, v in kw.items():
                if v is None:
                    n.pop(k, None)
                else:
                    n[k] = v
            self.assertIsNotNone(mum.check_native(n), kw)
        bad(package=-1)
        bad(package='14')
        bad(game='x.dll')
        bad(game='Missing.exe')
        bad(launcher='Chaos.exe')
        bad(files_url='files/')
        bad(files=[])
        bad(files=[{'path': '../Chaos.exe', 'sha256': 'a' * 64, 'size': 1}], game='Chaos.exe')
        bad(files=[{'path': 'Chaos.exe', 'sha256': 'A' * 64, 'size': 1}])
        bad(files=[{'path': 'Chaos.exe', 'sha256': 'a' * 64, 'size': mum.NATIVE_MAX_FILE_SIZE + 1}])
        bad(files=[{'path': 'Chaos.exe', 'sha256': 'a' * 64, 'size': 1}] * 2)
        for name in ('a.lua', 'a/b.exe', 'a\\b.exe', 'C:x.exe', '.hidden.exe', 'con.exe', 'a.exe.', ''):
            self.assertIsNotNone(mum.check_native_name(name), name)
        self.assertIsNone(mum.check_native_name('libGLESv2.dll'))

    VECTOR = os.path.join(HERE, '..', '..', 'launcher', 'tests', 'data', 'python_manifest.json')

    def test_launcher_vector(self):
        """launcher/tests/data/python_manifest.json: a manifest this tool signs (fixed key, fixed time), read by
        launcher/tests/vector.rs. UPDATE_LAUNCHER_VECTOR=1 rewrites it."""
        seed = bytes([0x42]) * 32
        entries = [('x/y.lua', 'a' * 64, 3, 'b' * 64, 3 + mum.BLOB_OVERHEAD)]
        nat = mum.make_native([('Chaos.exe', hashlib.sha256(b'exe').hexdigest(), 3),
                               ('CindersLauncher.exe', hashlib.sha256(b'launcher').hexdigest(), 8),
                               ('libssl-3-x64.dll', hashlib.sha256(b'dll').hexdigest(), 3)],
                              14, 'Chaos.exe', 'CindersLauncher.exe')
        payload = mum.make_payload(entries, 7, 0, 13, 8, 'live', '2026-10-29T00:00:00Z', nat)
        public = mum.public_from_seed(seed)
        env = mum.make_envelope(payload, public.hex(), mum.sign(seed, payload.encode('ascii')).hex())
        doc = json.dumps({'public_key': public.hex(), 'envelope': json.loads(env)}, indent=1, sort_keys=True) + '\n'
        if os.environ.get('UPDATE_LAUNCHER_VECTOR') == '1':
            with open(self.VECTOR, 'w', encoding='ascii') as f:
                f.write(doc)
        with open(self.VECTOR, encoding='ascii') as f:
            self.assertEqual(f.read(), doc, 'regenerate with UPDATE_LAUNCHER_VECTOR=1')

    def test_stale_native_blobs_are_pruned(self):
        self.assertEqual(self.publish()[0], 0)
        self.assertEqual(len(self.native_blobs()), 4)
        open(os.path.join(self.nat, 'Chaos.exe'), 'wb').write(b'MZ new')
        self.assertEqual(self.publish()[0], 0)
        self.assertEqual(len(self.native_blobs()), 4, 'the old exe blob is gone, the new one is there')
        self.assertEqual(self.publish(native=False)[0], 0)
        self.assertEqual(self.native_blobs(), [])


class Android(unittest.TestCase):
    """phone data (O313): the "android" section lists the files a phone downloads on first start; old clients ignore it"""
    tearDown = Build.tearDown
    payload, blob_files, keygen = Build.payload, Build.blob_files, Build.keygen

    def setUp(self):
        Build.setUp(self)
        for rel, data in {'layouts/mobile/styles/10-panels.otui': b'MobilePanel < UIWidget\n',
                          'layouts/classic/a.otui': b'x', 'data/images/streamer/overlay.png': b'\x89PNG' + os.urandom(40)}.items():
            path = os.path.join(self.client, rel)
            os.makedirs(os.path.dirname(path), exist_ok=True)
            open(path, 'wb').write(data)
        self.pub = self.keygen()

    def publish(self, *extra):
        return run(['build', self.client, '--out', self.out, '--key', self.key, '--min-package', '13'] + list(extra))

    def test_section_lists_the_phone_files(self):
        code, out, err = self.publish()
        self.assertEqual(code, 0, err)
        m = self.payload()
        a = m['android']
        paths = {f['path'] for f in m['files']}
        self.assertEqual(a['version'], 1)
        self.assertEqual(a['files'], sorted(a['files']))
        self.assertNotIn('layouts/mobile/styles/10-panels.otui', a['files'], 'the APK leaves layouts/mobile out')
        self.assertIn('layouts/mobile/styles/10-panels.otui', paths, 'desktop clients still get it')
        self.assertEqual(set(a['files']), paths - {'layouts/mobile/styles/10-panels.otui'})
        self.assertIn('data/things/1098/Tibia.dat', a['files'])
        self.assertEqual(a['count'], len(a['files']))
        blobs = {f['blob']: f['blob_size'] for f in m['files'] if f['path'] in set(a['files'])}
        self.assertEqual(a['bytes'], sum(blobs.values()), 'distinct encrypted blobs: the download size')
        self.assertIsNone(mum.check_payload(m))
        self.assertIn('phone data', out)
        code, out, err = run(['verify', self.out, '--public', self.pub])
        self.assertEqual(code, 0, err)
        self.assertIn('%d phone files' % a['count'], out)

    def test_exclude_prefix(self):
        code, out, err = self.publish('--android-exclude', 'data/images/streamer/')
        self.assertEqual(code, 0, err)
        m = self.payload()
        self.assertNotIn('data/images/streamer/overlay.png', m['android']['files'])
        self.assertIn('data/images/streamer/overlay.png', {f['path'] for f in m['files']})
        for bad in ('data/things', '../x/', 'bin/x/', 'data/a b$/'):
            code, out, err = self.publish('--android-exclude', bad)
            self.assertNotEqual(code, 0, bad)
            self.assertIn('--android-exclude', err)

    def test_old_clients_see_the_same_files(self):
        self.assertEqual(self.publish('--no-android')[0], 0)
        plain = self.payload()
        self.assertNotIn('android', plain)
        shutil.rmtree(self.out)
        self.assertEqual(self.publish()[0], 0)
        withp = self.payload()
        for k in ('files', 'format', 'product', 'version', 'min_version', 'min_package', 'files_url', 'encryption',
                  'parallel'):
            self.assertEqual(plain[k], withp[k], k)

    def test_section_is_signed(self):
        self.assertEqual(self.publish()[0], 0)
        path = os.path.join(self.out, 'manifest.json')
        env = json.load(open(path))
        m = json.loads(env['payload'])
        m['android']['files'].pop()
        m['android']['count'] -= 1
        env['payload'] = json.dumps(m, sort_keys=True, separators=(',', ':'))
        json.dump(env, open(path, 'w'))
        code, out, err = run(['verify', self.out, '--public', self.pub])
        self.assertNotEqual(code, 0)
        self.assertIn('bad signature', err)

    def test_dry_run_and_no_pair_warning(self):
        code, out, err = run(['build', self.client, '--dry-run'])
        self.assertEqual(code, 0, err)
        self.assertIn('phone data', out)
        self.assertNotIn('warning: no data/things', err)
        os.remove(os.path.join(self.client, 'data/things/1098/Tibia.dat'))
        code, out, err = run(['build', self.client, '--dry-run'])
        self.assertEqual(code, 0, err)
        self.assertIn('warning: no data/things/*.dat in the phone data list', err)

    def test_payload_rules(self):
        entries = [('modules/a/a.lua', 'a' * 64, 1, 'c' * 64, 45), ('layouts/mobile/x.otui', 'b' * 64, 2, 'd' * 64, 46),
                   ('data/things/1098/Tibia.dat', 'e' * 64, 3, 'f' * 64, 47)]
        m = json.loads(mum.make_payload(entries, 3, 0, 0, 4, 'live', 'now', android=()))
        self.assertIsNone(mum.check_payload(m))
        self.assertEqual(m['android']['files'], ['data/things/1098/Tibia.dat', 'modules/a/a.lua'])
        self.assertEqual(m['android']['bytes'], 45 + 47)
        self.assertNotIn('android', json.loads(mum.make_payload(entries, 3, 0, 0, 4, 'live', 'now')))

        def broken(fn):
            x = json.loads(json.dumps(m))
            fn(x['android'])
            return mum.check_payload(x)
        self.assertIn('not a file of the update', broken(lambda a: a['files'].append('modules/zz/z.lua')))
        self.assertIn('duplicate', broken(lambda a: a.update(files=a['files'] + [a['files'][0]], count=3)))
        self.assertIn('never on a phone', broken(lambda a: a.update(files=['layouts/mobile/x.otui'], count=1, bytes=46)))
        self.assertIn('bad count', broken(lambda a: a.update(count=9)))
        self.assertIn('bad bytes', broken(lambda a: a.update(bytes=1)))
        self.assertIn('bad version', broken(lambda a: a.update(version=2)))
        self.assertIn('bad file list', broken(lambda a: a.update(files=[])))


class Crypt(unittest.TestCase):
    """update_crypt.py: the blob format the engine decrypts (base patch 0103)"""
    key = bytes.fromhex(TEST_KEY)

    def test_fixed_vector(self):
        blob = uc.encrypt(VECTOR_PLAIN, VECTOR_KEY)
        self.assertEqual(blob.hex(), VECTOR_BLOB)
        self.assertEqual(uc.decrypt(bytes.fromhex(VECTOR_BLOB), VECTOR_KEY), VECTOR_PLAIN)

    def test_round_trip_and_determinism(self):
        for plain in (b'', b'x', os.urandom(1000), os.urandom(70000)):
            a = uc.encrypt(plain, self.key)
            self.assertEqual(a, uc.encrypt(plain, self.key), 'same content, same blob')
            self.assertEqual(len(a), len(plain) + uc.OVERHEAD)
            self.assertEqual(uc.decrypt(a, self.key), plain)
        self.assertNotEqual(uc.encrypt(b'a', self.key)[8:20], uc.encrypt(b'b', self.key)[8:20], 'nonce per content')

    def test_wrong_key(self):
        blob = uc.encrypt(b'secret module', self.key)
        with self.assertRaises(uc.BlobError):
            uc.decrypt(blob, bytes.fromhex(OTHER_KEY))

    def test_not_the_pack_key(self):
        # the update key is its own HKDF label: a chaos.pack never opens as a blob and the other way round
        plain = b'same bytes'
        self.assertNotEqual(uc.encrypt(plain, self.key)[28:], uc.encrypt(plain, self.key, fmt=uc.PACK)[28:])
        with self.assertRaises(uc.BlobError):
            uc.decrypt(uc.encrypt(plain, self.key, fmt=uc.PACK), self.key)
        # the PACK format is byte-identical to pack_client.py
        self.assertEqual(uc.encrypt(plain * 200, self.key, fmt=uc.PACK), pack_client.encrypt_pack(plain * 200, self.key))

    def test_tamper(self):
        blob = bytearray(uc.encrypt(b'0123456789' * 50, self.key))
        for at in (5, 9, 21, 28, 100, len(blob) - 1):  # flags, nonce, length, body, tag
            bad = bytearray(blob)
            bad[at] ^= 1
            with self.assertRaises(uc.BlobError, msg='byte %d' % at):
                uc.decrypt(bytes(bad), self.key)
        with self.assertRaises(uc.BlobError):
            uc.decrypt(bytes(blob[:-1]), self.key)
        with self.assertRaises(uc.BlobError):
            uc.decrypt(b'PLAIN' + bytes(blob[5:]), self.key)

    def test_streaming_matches(self):
        tmp = tempfile.mkdtemp(prefix='chaos-crypt-')
        try:
            src = os.path.join(tmp, 'big.bin')
            plain = os.urandom(uc.BLOCK * 2 + 12345)  # more than two blocks
            open(src, 'wb').write(plain)
            dst = os.path.join(tmp, 'big.blob')
            with open(dst, 'wb') as f:
                c, size = uc.encrypt_file(src, f, self.key)
            data = open(dst, 'rb').read()
            self.assertEqual(data, uc.encrypt(plain, self.key))
            self.assertEqual(size, len(data))
            self.assertEqual(c, mum.sha256_file(dst))
            out = os.path.join(tmp, 'back.bin')
            with open(out, 'wb') as f:
                flags, sha = uc.decrypt_file(dst, self.key, f)
            self.assertEqual(open(out, 'rb').read(), plain)
            self.assertEqual(sha, mum.sha256_file(src))
            self.assertEqual(flags, 0)
            with open(dst, 'r+b') as f:
                f.seek(uc.BLOCK + 3)
                b = f.read(1)
                f.seek(uc.BLOCK + 3)
                f.write(bytes([b[0] ^ 0x80]))
            with self.assertRaises(uc.BlobError):
                uc.decrypt_file(dst, self.key)
        finally:
            shutil.rmtree(tmp)

    def test_pack_v2_streaming(self):
        # chaos.pack format 2 (zlib, then GCM) read block by block: what `make_update_manifest.py unpack` does
        tmp = tempfile.mkdtemp(prefix='chaos-pack-')
        try:
            plain = (b'modules/game_x/x.lua print(1)\n' * 400000) + os.urandom(uc.BLOCK + 777)  # > 2 blocks packed
            pack = pack_client.encrypt_pack(plain, self.key, is_dev=True)
            self.assertLess(len(pack), len(plain))
            self.assertEqual(pack, uc.encrypt(plain, self.key, dev=True, fmt=uc.PACK))
            self.assertEqual(uc.decrypt(pack, self.key, fmt=uc.PACK), plain)
            path = os.path.join(tmp, 'chaos.pack')
            open(path, 'wb').write(pack)
            out = io.BytesIO()
            flags, sha = uc.decrypt_file(path, self.key, out, uc.PACK)
            self.assertEqual(flags, uc.FLAG_DEV)
            self.assertEqual(out.getvalue(), plain)
            self.assertEqual(sha, hashlib.sha256(plain).hexdigest())
            for at in (4, 20, 28, len(pack) // 2, len(pack) - 20, len(pack) - 1):  # version, length, body, tag
                bad = bytearray(pack)
                bad[at] ^= 1
                open(path, 'wb').write(bytes(bad))
                with self.assertRaises(uc.BlobError, msg='byte %d' % at):
                    uc.decrypt_file(path, self.key, io.BytesIO(), uc.PACK)
            for cut in (pack[:-1], pack + b'\0', pack[:40]):
                open(path, 'wb').write(cut)
                with self.assertRaises(uc.BlobError):
                    uc.decrypt_file(path, self.key, None, uc.PACK)
            with self.assertRaises(uc.BlobError):
                uc.encrypt_file(path, io.BytesIO(), self.key, fmt=uc.PACK)
        finally:
            shutil.rmtree(tmp)

    def test_parse_client_keys(self):
        self.assertEqual(uc.parse_client_keys(''), [])
        self.assertEqual(uc.parse_client_keys(TEST_KEY.upper()), [self.key])
        self.assertEqual(len(uc.parse_client_keys(OTHER_KEY + ', ' + TEST_KEY)), 2)
        with self.assertRaises(uc.BlobError):
            uc.parse_client_keys('abc')


class SetUpdateConfig(unittest.TestCase):
    """set_update_config.py writes the package's settings; make_update_manifest.py reads the baseline back."""
    INIT = ('Services = {\n  update = {\n    manifest = "",\n    publicKey = "",\n    package = 1,\n%s'
            '    required = false,\n    download = ""\n  },\n  other = 1\n}\n')

    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix='chaos-update-cfg-')

    def tearDown(self):
        shutil.rmtree(self.tmp)

    def run_tool(self, *args):
        return subprocess.run([sys.executable, '-I', os.path.join(HERE, 'set_update_config.py'), self.tmp,
                               '--manifest', 'https://site.example/updates/live/manifest.json',
                               '--public-key', 'ab' * 32] + list(args), capture_output=True, text=True)

    def test_baseline(self):
        path = os.path.join(self.tmp, 'init.lua')
        open(path, 'w').write(self.INIT % '    baseline = 0,\n')
        r = self.run_tool('--package', '12', '--baseline', '47')
        self.assertEqual(r.returncode, 0, r.stderr)
        text = open(path).read()
        self.assertIn('    package = 12,\n', text)
        self.assertIn('    baseline = 47,\n', text)
        self.assertEqual(mum.package_baseline(self.tmp), 47)
        # an init.lua without the field (a base without patch 0101) is refused when a baseline is asked for
        open(path, 'w').write(self.INIT % '')
        r = self.run_tool('--baseline', '47')
        self.assertNotEqual(r.returncode, 0)
        self.assertIn('0101', r.stderr)
        self.assertEqual(self.run_tool().returncode, 0, 'no --baseline: works on an old init.lua')
        self.assertNotEqual(self.run_tool('--baseline', '-1').returncode, 0)


class Workflow(unittest.TestCase):
    """windows-package.yml: the client trees that go through the updater and the pack hold the sprite shards, not a
    single Tibia.spr (pair 37 is over the updater's 1 GiB); the single file goes to the map editor only"""
    PATH = os.path.join(HERE, '..', '..', '.github', 'workflows', 'windows-package.yml')

    def test_shards_in_the_client_trees(self):
        text = open(self.PATH, encoding='utf-8').read()
        builds = [ln for ln in text.splitlines() if 'make_update_manifest.py build' in ln]
        self.assertEqual(len(builds), 3, builds)
        for ln in builds:
            self.assertIn('--min-package "$CLIENT_BUILD"', ln)
            self.assertNotIn('--with-single-spr', ln)
        # the pair is never unpacked straight into a client tree, and each client tree gets a verified split
        self.assertNotIn('-C "$P/client/data/things/1098"', text)
        self.assertNotIn('-C "$P/data/things/1098"', text)
        self.assertEqual(text.count('spr_shards.py split'), 2)
        self.assertEqual(text.count('spr_shards.py verify'), 2)
        # the map editor gets the single file, not the shards
        self.assertNotIn('cp "$P/client/data/things/1098/"Tibia.*', text)
        self.assertIn('"$P/mapeditor/client/"', text)


class AndroidWorkflow(unittest.TestCase):
    """android-client.yml (O313): the APK gets the same manifest URL and public key as the Windows package, with the same
    production defaults, writes them with set_update_config.py, and the emulator smoke test asserts the first-start screen"""
    DIR = os.path.join(HERE, '..', '..', '.github', 'workflows')

    @staticmethod
    def default(text, name):
        m = re.search(r'\n      %s:\n(?:        [^\n]*\n)*?        default: "([^"\n]*)"' % name, text)
        return m.group(1) if m else None

    def test_same_update_inputs_as_the_windows_package(self):
        win = open(os.path.join(self.DIR, 'windows-package.yml'), encoding='utf-8').read()
        apk = open(os.path.join(self.DIR, 'android-client.yml'), encoding='utf-8').read()
        for name in ('update_manifest', 'update_public_key'):
            self.assertIsNotNone(self.default(win, name), name)
            self.assertEqual(self.default(apk, name), self.default(win, name), name + ': same production default')
        self.assertEqual(self.default(apk, 'update_manifest'), 'https://www.cindersofchaos.com/updates/live/manifest.json')
        self.assertEqual(self.default(apk, 'update_public_key'),
                         '7f4ae1b812e3ca86ac4551683b987b8bf68d2256b36b1785c07cb4f3ffb72224')
        self.assertIn('UPDATE_MANIFEST: ${{ inputs.update_manifest }}', apk)
        self.assertIn('UPDATE_PUBLIC_KEY: ${{ inputs.update_public_key }}', apk)
        self.assertIn('set_update_config.py game --manifest "$UPDATE_MANIFEST"', apk)
        self.assertIn('--public-key "$UPDATE_PUBLIC_KEY" --package "$CLIENT_BUILD"', apk)

    def test_smoke_asserts_the_first_start_screen(self):
        apk = open(os.path.join(self.DIR, 'android-client.yml'), encoding='utf-8').read()
        self.assertIn('grep -q "firststart: screen shown" logcat.txt', apk)
        src = open(os.path.join(HERE, '..', 'overlay', 'modules', 'client_chaos_firststart', 'firststart.lua'),
                   encoding='utf-8').read()
        self.assertIn("g_logger.info('firststart: screen shown (' .. tostring(why) .. ')')", src)


if __name__ == '__main__':
    unittest.main(verbosity=1)
