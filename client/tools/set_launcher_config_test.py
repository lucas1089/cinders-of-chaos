#!/usr/bin/env python3
"""Tests of set_launcher_config.py: python3 -I client/tools/set_launcher_config_test.py
The result must parse in the launcher (launcher/src/config.rs); the same keys are in launcher/README.md."""
import io, json, os, shutil, sys, tempfile, unittest
from contextlib import redirect_stderr, redirect_stdout

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import set_launcher_config as slc  # noqa: E402

KEY = '42' * 32
INIT = '''Services = {
  update = {
    manifest = "%s",
    publicKey = "%s",
    package = 14,
%s    required = false,
    download = ""
  }
}
'''


class SetLauncherConfig(unittest.TestCase):
    def setUp(self):
        self.d = tempfile.mkdtemp(prefix='chaos-launcher-cfg-')

    def tearDown(self):
        shutil.rmtree(self.d)

    def init(self, manifest='https://site.test/updates/live/manifest.json', key=KEY, baseline='    baseline = 47,\n'):
        with open(os.path.join(self.d, 'init.lua'), 'w') as f:
            f.write(INIT % (manifest, key, baseline))

    def run_tool(self, *extra):
        out, err = io.StringIO(), io.StringIO()
        with redirect_stdout(out), redirect_stderr(err):
            try:
                code = slc.main([self.d, *extra])
            except SystemExit as e:
                code = e.code if isinstance(e.code, int) else 1
                err.write(str(e.code))
        return code, out.getvalue(), err.getvalue()

    def test_writes_the_same_facts_as_the_updater(self):
        self.init()
        code, out, err = self.run_tool()
        self.assertEqual(code, 0, err)
        cfg = json.load(open(os.path.join(self.d, 'launcher.json')))
        self.assertEqual(cfg, {'manifest': 'https://site.test/updates/live/manifest.json', 'public_key': KEY,
                               'game': 'Chaos.exe', 'baseline': 47,
                               'feed': 'https://site.test/chaos_launcher_feed.php'})

    def test_no_baseline_is_left_out(self):
        self.init(baseline='')
        self.assertEqual(self.run_tool()[0], 0)
        self.assertNotIn('baseline', json.load(open(os.path.join(self.d, 'launcher.json'))))

    def test_updater_off_writes_nothing(self):
        self.init(manifest='', key='')
        code, out, err = self.run_tool()
        self.assertEqual(code, 2)
        self.assertFalse(os.path.exists(os.path.join(self.d, 'launcher.json')))

    def test_refuses_odd_values(self):
        self.init(manifest='http://site.test/manifest.json')
        self.assertNotEqual(self.run_tool()[0], 0)
        self.init(key='zz' * 32)
        self.assertNotEqual(self.run_tool()[0], 0)
        self.init()
        self.assertNotEqual(self.run_tool('--game', '..\\x.exe')[0], 0)
        self.assertFalse(os.path.exists(os.path.join(self.d, 'launcher.json')))

    def test_feed_default_override_and_off(self):
        self.init(manifest='https://site.test:8443/updates/live/manifest.json')
        self.assertEqual(self.run_tool()[0], 0)
        cfg = json.load(open(os.path.join(self.d, 'launcher.json')))
        self.assertEqual(cfg['feed'], 'https://site.test:8443/chaos_launcher_feed.php')
        self.assertEqual(self.run_tool('--feed', 'https://other.test/f.php')[0], 0)
        self.assertEqual(json.load(open(os.path.join(self.d, 'launcher.json')))['feed'], 'https://other.test/f.php')
        self.assertEqual(self.run_tool('--no-feed')[0], 0)
        self.assertEqual(json.load(open(os.path.join(self.d, 'launcher.json')))['feed'], '')

    def test_refuses_odd_feeds(self):
        self.init()
        os.path.exists(os.path.join(self.d, 'launcher.json')) and os.remove(os.path.join(self.d, 'launcher.json'))
        for bad in ('http://site.test/f.php', 'https://site.test/a b', 'javascript:alert(1)', 'https://u@site.test/f'):
            self.assertNotEqual(self.run_tool('--feed', bad)[0], 0, bad)
        self.assertFalse(os.path.exists(os.path.join(self.d, 'launcher.json')))

    def test_game_name(self):
        self.init()
        self.assertEqual(self.run_tool('--game', 'Game.exe')[0], 0)
        self.assertEqual(json.load(open(os.path.join(self.d, 'launcher.json')))['game'], 'Game.exe')


if __name__ == '__main__':
    unittest.main(verbosity=1)
