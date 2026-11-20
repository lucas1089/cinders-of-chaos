#!/usr/bin/env python3
"""Tests of the spell showcase video (O692): tools/ci/spells_video.sh, .github/workflows/spells-video.yml, the UL_SPELL_SHOWCASE part of
tools/ci/unity_live_check.sh, the test-only client module test_spelltour and the combo bursts of the server.

  python3 -I tools/ci/spells_video_test.py

The script run (`SpellsVideoRun`) uses a fake client (a shell script that writes the module's log lines) and the real Xvfb and ffmpeg; it is
skipped when either is missing. No server, no client build, no sprite.
"""
import os
import re
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def read(*parts):
    with open(os.path.join(ROOT, *parts), encoding='utf-8') as f:
        return f.read()


def read_path(path):
    with open(path, encoding='utf-8', errors='replace') as f:
        return f.read()


CLASSES = {'elementalist': 5, 'deadeye': 7, 'illusionist': 10}


class Static(unittest.TestCase):
    def test_workflow_is_manual_and_secret_free(self):
        wf = read('.github', 'workflows', 'spells-video.yml')
        self.assertRegex(wf, r'(?m)^on:\n  workflow_dispatch:')
        self.assertNotRegex(wf, r'(?m)^  (push|pull_request|schedule|workflow_run):')
        self.assertNotIn('secrets.', wf, 'no repository secret: the guard key is made in the run')
        self.assertIn('::add-mask::$key', wf)
        self.assertRegex(wf, r'(?m)^permissions:\n  contents: read')
        self.assertNotIn('git push', wf)
        self.assertNotIn('windows-assets\n          path: assets\n          push', wf)
        for line in wf.splitlines():
            m = re.match(r'^\s*- name: (.*)$', line)
            if m:
                self.assertNotIn(': ', m.group(1), 'a step name with ": " breaks the YAML: ' + m.group(1))
        up = wf[wf.index('actions/upload-artifact'):]
        paths = re.findall(r'\$\{\{ runner\.temp \}\}/spells-video/(\S+)', up)
        self.assertEqual(sorted(paths), ['*.mp4', 'client-log-*.txt', 'spells-report.txt'], 'only the mp4s, the report and the client logs are uploaded')
        self.assertIn('name: spells-video', up)
        self.assertIn('UL_SPELL_SHOWCASE: "1"', wf)
        self.assertIn('tools/ci/spells_video.sh', wf)
        self.assertIn('test -f game/modules/test_spelltour/spelltour.lua', wf)
        for c in CLASSES:
            self.assertIn('spell-%s.env' % c, wf)
        try:
            import yaml
        except ImportError:
            return
        d = yaml.safe_load(wf)
        self.assertEqual(list(d[True]), ['workflow_dispatch'])
        inputs = d[True]['workflow_dispatch']['inputs']
        self.assertEqual(inputs['seconds']['default'], '900')

    def test_script_limits(self):
        sh = read('tools', 'ci', 'spells_video.sh')
        self.assertIn('SV_SECONDS:-900', sh)
        self.assertIn('-gt 1800', sh)
        self.assertIn('-pix_fmt yuv420p', sh)
        self.assertIn('-c:v libx264', sh)
        self.assertIn('-crf 20', sh)
        self.assertIn('-movflags +faststart', sh)
        self.assertIn('-video_size "${W}x${H}"', sh)
        self.assertIn('SV_WIDTH:-1280', sh)
        self.assertIn('SV_HEIGHT:-720', sh)

    def test_module_is_armed_by_its_variable_only(self):
        glue = read('client', 'overlay', 'modules', 'test_spelltour', 'spelltour.lua')
        logic = read('client', 'overlay', 'modules', 'test_spelltour', 'spelltourlogic.lua')
        self.assertIn("L.ENV_ON = 'CHAOS_SPELLTOUR'", logic)
        self.assertIn("get(L.ENV_ON) ~= '1'", logic)
        self.assertRegex(glue, r"if not cfg then\n\s+if err ~= 'off'")
        for word in ('addTab', 'g_ui.loadUI', 'bindKeyPress', 'registerTopBar', 'ChaosTopbar'):
            self.assertNotIn(word, glue, 'the test module must not add a window, hotkey or hub card')
        for l in glue.splitlines():
            if 'log(' in l:
                self.assertNotIn('password', l.lower(), 'the password is never logged: ' + l.strip())
        otmod = read('client', 'overlay', 'modules', 'test_spelltour', 'test_spelltour.otmod')
        self.assertIn('autoload: true', otmod)
        self.assertIn('@onLoad: ChaosSpellTour.init()', otmod)

    def test_opcode_is_the_servers(self):
        logic = read('client', 'overlay', 'modules', 'test_spelltour', 'spelltourlogic.lua')
        self.assertIn('L.OPCODE = 168', logic)
        consts = read('server', 'data', 'scripts', 'chaos', 'chaos_constants.lua')
        self.assertRegex(consts, r'spellRanks\s*=\s*168')

    def test_live_check_switch(self):
        sh = read('tools', 'ci', 'unity_live_check.sh')
        self.assertIn('UL_SPELL_SHOWCASE', sh)
        inst = re.search(r"install_spell_showcase\(\) \{.*?^\}", sh, re.S | re.M).group(0)
        self.assertIn('$SERVER/data/scripts/chaos/spell_ranks_config.lua', inst, 'the switch is turned in the run copy only')
        self.assertNotIn('$REPO/server/data', inst, 'the repository file is never the one edited')
        self.assertIn('zz_spell_showcase.lua', inst)
        self.assertIn('zz_spell_showcase_core.lua', inst)
        main = sh[sh.index('install_tester_helper\ninstall_spell_showcase\nstart_tfs'):]
        self.assertTrue(main)
        chars = re.search(r"new_showcase\(\) \{.*?^\}", sh, re.S | re.M).group(0)
        self.assertIn("'$PN', 6,", chars, 'a showcase character is a group 6 staff character')
        self.assertIn('VALUES (\'$PA\', SHA1(\'$PP\'), 6', chars)
        self.assertNotIn('7102900', chars, 'a showcase character is not a tester')
        self.assertIn('Showcase $title', chars)
        setup = re.search(r"setup_spell_showcase\(\) \{.*?^\}", sh, re.S | re.M).group(0)
        got = dict((c, int(v)) for c, v in re.findall(r'"(\w+) (\d+) \d+"', setup))
        self.assertEqual(got, CLASSES)
        self.assertIn('CHAOS_SPELLTOUR_CLASS', setup)
        self.assertNotIn('git ', setup)
        # the vocation ids are the server's
        xml = read('server', 'data', 'XML', 'chaos_vocations.xml')
        for name, vid in (('Elementalist', 5), ('Deadeye', 7), ('Illusionist', 10)):
            self.assertRegex(xml, r'<vocation id="%d" clientid="\d+" name="%s"' % (vid, name))
        # the ranks switch of the repository stays off
        cfg = read('server', 'data', 'scripts', 'chaos', 'spell_ranks_config.lua')
        self.assertRegex(cfg, r'(?m)^\tenabled = false,')
        self.assertIn('^\tenabled = false,', inst)

    def test_classes_of_the_module_match(self):
        logic = read('client', 'overlay', 'modules', 'test_spelltour', 'spelltourlogic.lua')
        got = dict((c, int(v)) for c, v in re.findall(r'(\w+) = \{\n    vocation = (\d+),', logic))
        self.assertEqual(got, CLASSES)

    def test_showcase_helper_is_test_only(self):
        inst = read('server', 'tools', 'install_all.py')
        self.assertNotIn('spell_showcase', inst, 'the pack helper is never an install step')
        for f in ('spell_showcase.lua', 'spell_showcase_core.lua'):
            self.assertTrue(os.path.isfile(os.path.join(ROOT, 'server', 'tools', f)))
            self.assertFalse(os.path.exists(os.path.join(ROOT, 'server', 'data', 'scripts', 'chaos', f)))
        lua = read('server', 'tools', 'spell_showcase.lua')
        for word in ('setMaxHealth', 'addHealth', 'setHealth', 'setTarget'):
            self.assertNotIn(word, lua, 'the pack helper changes no health and no target')


FAKE_CLIENT = """#!/usr/bin/env bash
# a client that writes the log lines of test_spelltour, no window
echo "env: account $CHAOS_LIVE_ACCOUNT password $CHAOS_LIVE_PASSWORD class $CHAOS_SPELLTOUR_CLASS seconds $CHAOS_SPELLTOUR_SECONDS key $CHAOS_CLIENT_KEY"
if [ "${FAKE_NO_READY:-0}" = 1 ]; then exec sleep 600; fi
echo "[info] spelltour: armed: account $CHAOS_LIVE_ACCOUNT, class $CHAOS_SPELLTOUR_CLASS, at most $CHAOS_SPELLTOUR_SECONDS s of film"
sleep 1
echo "[info] spelltour: class $CHAOS_SPELLTOUR_CLASS: 3 actions, 5 s long; Form kinds: AFTERMATH DELAY; combos: steam_burst"
echo "[info] spelltour: ready"
sleep 1
echo "[info] spelltour: phase forms"
echo "[info] spelltour: caption Falling Pyre, no Form"
echo "[info] spelltour: cast 204 Falling Pyre"
sleep 2
echo "[info] spelltour: caption Combo Steam Burst: Rime Bloom, then Witchfire Bolt"
echo "[info] spelltour: cast 200 Rime Bloom (combo steam_burst part 1)"
echo "[info] spelltour: no monster to target for Witchfire Bolt"
sleep 2
echo "[info] spelltour: done ok script played"
"""


@unittest.skipUnless(shutil.which('Xvfb') and shutil.which('ffmpeg') and shutil.which('ffprobe'), 'needs Xvfb, ffmpeg and ffprobe')
class SpellsVideoRun(unittest.TestCase):
    def setUp(self):
        self.d = tempfile.mkdtemp(prefix='spellsvideo_')
        self.addCleanup(shutil.rmtree, self.d, True)
        self.game = os.path.join(self.d, 'game')
        os.makedirs(self.game)
        client = os.path.join(self.game, 'chaos-client')
        with open(client, 'w') as f:
            f.write(FAKE_CLIENT)
        os.chmod(client, 0o755)
        self.key = 'cd' * 32
        self.envs = []
        self.secrets = [self.key]
        for i, c in enumerate(('elementalist', 'deadeye')):
            path = os.path.join(self.d, 'spell-%s.env' % c)
            account, password = 'lcw%d0abc12' % (i + 1), 'Pw0rdSecret%d9' % i
            self.secrets += [account, password]
            with open(path, 'w') as f:
                f.write("export CHAOS_LIVE_HOST=127.0.0.1\nexport CHAOS_LIVE_ACCOUNT=%s\nexport CHAOS_LIVE_PASSWORD=%s\n"
                        "export CHAOS_LIVE_CHARACTER='Showcase %s'\nexport CHAOS_SPELLTOUR_CLASS=%s\nexport CHAOS_CLIENT_KEY=%s\n"
                        % (account, password, c.title(), c, self.key))
            self.envs.append(path)
        self.out = os.path.join(self.d, 'out')

    def run_script(self, extra=None, envs=None, timeout=180):
        env = dict(os.environ, SV_DISPLAY='95', SV_WIDTH='320', SV_HEIGHT='240', SV_SECONDS='30', SV_READY_WAIT='60')
        env.update(extra or {})
        return subprocess.run(['bash', os.path.join(ROOT, 'tools', 'ci', 'spells_video.sh'), self.game, self.out] + (envs or self.envs),
                              capture_output=True, text=True, env=env, timeout=timeout)

    def test_a_class_is_filmed_and_reported(self):
        p = self.run_script()
        self.assertEqual(p.returncode, 0, p.stdout + p.stderr)
        self.assertEqual(sorted(os.listdir(self.out)), ['client-log-deadeye.txt', 'client-log-elementalist.txt', 'deadeye.mp4', 'elementalist.mp4', 'spells-report.txt'],
                         'nothing but the mp4s, the report and the logs is left')
        for c in ('elementalist', 'deadeye'):
            video = os.path.join(self.out, c + '.mp4')
            probe = subprocess.run(['ffprobe', '-v', 'error', '-select_streams', 'v:0', '-show_entries', 'stream=codec_name,pix_fmt,width,height',
                                    '-of', 'csv=p=0', video], capture_output=True, text=True).stdout.strip()
            self.assertEqual(sorted(probe.split(',')), sorted(['h264', 'yuv420p', '320', '240']))
            dur = float(subprocess.run(['ffprobe', '-v', 'error', '-show_entries', 'format=duration', '-of', 'csv=p=0', video], capture_output=True, text=True).stdout)
            self.assertGreater(dur, 3.0)
            self.assertLess(dur, 40.0, 'the recording stops with the tour, not at the time limit')
        report = read_path(os.path.join(self.out, 'spells-report.txt'))
        self.assertIn('elementalist:', report)
        self.assertIn('deadeye:', report)
        self.assertIn('Falling Pyre, no Form', report)
        self.assertIn('Combo Steam Burst: Rime Bloom, then Witchfire Bolt', report)
        self.assertIn('casts: 2', report)
        self.assertIn('warning:', report)
        clog = read_path(os.path.join(self.out, 'client-log-elementalist.txt'))
        self.assertIn('spelltour: done ok script played', clog)
        self.assertIn('class elementalist seconds 30', clog)
        for secret in self.secrets:
            for name, text in (('client log', clog), ('other log', read_path(os.path.join(self.out, 'client-log-deadeye.txt'))), ('report', report),
                               ('stdout', p.stdout), ('stderr', p.stderr)):
                self.assertNotIn(secret, text, '%s shows %s' % (name, secret[:4]))

    def test_a_client_that_never_gets_ready_fails(self):
        p = self.run_script(extra={'FAKE_NO_READY': '1', 'SV_READY_WAIT': '30'}, envs=self.envs[:1])
        self.assertEqual(p.returncode, 1, p.stdout + p.stderr)
        self.assertIn('no ready line', p.stderr)
        self.assertFalse(os.path.exists(os.path.join(self.out, 'elementalist.mp4')))
        self.assertIn('FAILED', read_path(os.path.join(self.out, 'spells-report.txt')))

    def test_refused_limits(self):
        for key, value in (('SV_SECONDS', '1801'), ('SV_SECONDS', '29'), ('SV_SECONDS', 'x'), ('SV_READY_WAIT', '5'), ('SV_WIDTH', '321')):
            p = self.run_script(extra={key: value}, envs=self.envs[:1])
            self.assertEqual(p.returncode, 2, '%s=%s: %s' % (key, value, p.stderr))
        p = self.run_script(envs=[os.path.join(self.d, 'nope.env')])
        self.assertEqual(p.returncode, 2)


if __name__ == '__main__':
    unittest.main(verbosity=1)
