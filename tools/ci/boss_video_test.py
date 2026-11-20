#!/usr/bin/env python3
"""Tests of the boss fight video (O689): tools/ci/boss_video_report.py, tools/ci/boss_video.sh, .github/workflows/boss-video.yml, the
UL_PINNACLE_PARTY part of tools/ci/unity_live_check.sh and the numbers the test-only client module test_bosstour copies from the server.

  python3 -I tools/ci/boss_video_test.py

The script run (`BossVideoRun`) uses a fake client (a shell script that writes the module's log lines), a fake testers.py (writes an activity log
with the verdict line the real one writes) and the real Xvfb and ffmpeg; it is skipped when either is missing. No server, no client build, no sprite.
"""
import json
import os
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import time
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, 'tools', 'ci'))
import boss_video_report as R  # noqa: E402


def read(*parts):
    with open(os.path.join(ROOT, *parts), encoding='utf-8') as f:
        return f.read()


ACTIVITY = """\
10:00:00 Tester Aka (L1900 Mystic) login    in game
10:41:02 Tester Aka (L1900 Illusionist) CHECK    PASS pinnacle_party: Ascended Malgrath down in 301 s, 2 fall(s), 5 player(s), level 1900, 4 dodge(s), marks taken 3 of 20 (15%); gear x; 3 teleport/grant fallback(s) named in the result; carried out: Tester Bel at 86 s, Tester Cor at 172 s; party: Illusionist, Juggernaut, Deadeye, Elementalist, Samurai
10:41:03 Tester Bel (L1900 Juggernaut) CHECK    SKIP pinnacle_party: played as a member of the party of Tester Aka (its result is the party's)
10:41:04 Tester Cor (L1900 Deadeye) DEATH    died while hunting
10:41:05 Tester Dun (L1900 Samurai) login    in game
"""
HURT = ("10:41:02 Tester Aka (L1900 Illusionist) CHECK    PASS pinnacle_party: Ascended Malgrath hurt to 12% in 412 s, not down (5 fall(s), level 1900, x); "
        "carried out: Tester Aka at 20 s, Tester Bel at 33 s; party: Illusionist, Juggernaut\n")
CLIENT = """\
[info] bosstour: armed: account lcs1abc123, boss Malgrath, party of 5, 480 s of fight, 7200 s of waiting at most
[info] bosstour: ready
[info] bosstour: boss 80% at 12 s in the fight, party member 2 tiles away
[info] bosstour: boss 41% at 42 s in the fight, party member 3 tiles away
[info] bosstour: fight state success
[info] bosstour: done ok boss dead
"""


class Report(unittest.TestCase):
    def test_levels_match_the_config(self):
        cfg = read('server', 'data', 'scripts', 'chaos', 'pinnacle_config.lua')
        rows = re.findall(r'\{key = "(\w+)", name = "[^"]*", short = "[^"]*", level = (\d+), minLevel = (\d+), refLevel = (\d+)', cfg)
        self.assertEqual(len(rows), 4)
        for key, level, minlevel, ref in rows:
            self.assertEqual(R.BOSS_LEVELS[key], int(ref), key)
            # the party is at the level the boss is shown at, which is also the level the checks open the boss for (the highest boss its level opens)
            self.assertEqual(int(level), int(ref), key)
            self.assertGreaterEqual(R.BOSS_LEVELS[key], int(minlevel), key)
        self.assertEqual(set(R.BOSS_LEVELS), {r[0] for r in rows})
        # the highest boss a level opens is the boss of the video: a party at the level of boss N opens N and nothing above it
        by_min = sorted((int(r[2]), r[0]) for r in rows)
        for _, key in by_min:
            above = [k for m, k in by_min if m <= R.BOSS_LEVELS[key]]
            self.assertEqual(above[-1], key, 'the party of %s would open %s' % (key, above[-1]))

    def test_shell_table_matches(self):
        sh = read('tools', 'ci', 'unity_live_check.sh')
        m = re.search(r'pinnacle_level\(\) \{\n  case "\$1" in\n(.*?)\n    \*\)', sh, re.S)
        self.assertTrue(m)
        got = dict((k, int(v)) for k, v in re.findall(r'(\w+)\) echo (\d+) ;;', m.group(1)))
        self.assertEqual(got, R.BOSS_LEVELS)

    def test_level_command(self):
        out = subprocess.run([sys.executable, '-I', os.path.join(ROOT, 'tools', 'ci', 'boss_video_report.py'), 'level', 'malgrath'],
                             capture_output=True, text=True)
        self.assertEqual(out.stdout.strip(), '1900')
        bad = subprocess.run([sys.executable, '-I', os.path.join(ROOT, 'tools', 'ci', 'boss_video_report.py'), 'level', 'nobody'], capture_output=True, text=True)
        self.assertEqual(bad.returncode, 2)

    def test_fight_lines(self):
        lines = R.fight_lines(ACTIVITY)
        self.assertEqual(len(lines), 3)
        self.assertTrue(all(' CHECK ' in l or ' DEATH ' in l for l in lines))

    def test_killed(self):
        v = R.verdict_of(R.fight_lines(ACTIVITY))
        self.assertEqual(v['result'], 'killed')
        self.assertEqual((v['seconds'], v['falls'], v['boss_left']), (301, 2, 0))
        self.assertEqual(v['out'], [('Tester Bel', 86), ('Tester Cor', 172)])
        self.assertEqual(v['status'], 'PASS')

    def test_not_killed(self):
        v = R.verdict_of(R.fight_lines(HURT))
        self.assertEqual(v['result'], 'not killed')
        self.assertEqual((v['seconds'], v['falls'], v['boss_left']), (412, 5, 12))
        self.assertEqual(v['out'], [('Tester Aka', 20), ('Tester Bel', 33)])

    def test_skip_and_nothing(self):
        line = "10:00:00 Tester Aka (L1900 Mystic) CHECK    SKIP pinnacle_party: the party could not be formed (a bot left the game)\n"
        v = R.verdict_of(R.fight_lines(line))
        self.assertEqual(v['result'], 'not killed')
        self.assertEqual(v['status'], 'SKIP')
        self.assertEqual(R.verdict_of([])['result'], 'unknown')
        member = "10:00:00 Tester Bel (L1900 Mystic) CHECK    SKIP pinnacle_party: played as a member of the party of Tester Aka (its result is the party's)\n"
        self.assertEqual(R.verdict_of(R.fight_lines(member))['result'], 'unknown', 'a member line is not the leader\'s verdict')

    def test_client_facts(self):
        c = R.client_facts(CLIENT)
        self.assertTrue(c['ready'])
        self.assertEqual(c['boss'], [(80, 12), (41, 42)])
        self.assertEqual(c['states'], ['success'])
        self.assertEqual(c['done'], ('ok', 'boss dead'))

    def test_report_text(self):
        text = R.build_report('malgrath', 1900, ['Tester Aka', 'Tester Bel'], ACTIVITY, CLIENT, 321)
        self.assertIn('the boss was killed in 301 s after it came (2 fall(s))', text)
        self.assertIn('Tester Bel at 86 s', text)
        self.assertIn('80% at 12 s', text)
        self.assertIn('recorded: 321 s', text)
        wipe = R.build_report('malgrath', 1900, ['Tester Aka'], HURT, '[info] bosstour: ready\n[info] bosstour: done ok fight over, no kill\n')
        self.assertIn('NOT killed after 412 s, 88% of its health taken (12% left)', wipe)
        self.assertIn('carried out (a fall, healed and sent back): Tester Aka at 20 s, Tester Bel at 33 s', wipe)
        none = R.build_report('malgrath', 1900, [], '', '')
        self.assertIn('result: unknown', none)
        self.assertIn('never saw the fight open', none)

    def test_redaction(self):
        secrets = ['hunter2hunter2', 'lcs1abc123']
        text = 'login lcs1abc123 hunter2hunter2 tstbot0123456789ab key ' + 'a1' * 32 + ' acct lcp3deadbe done'
        out = R.redact(text, secrets)
        for gone in ('hunter2hunter2', 'lcs1abc123', 'tstbot0123456789', 'a1' * 32, 'lcp3deadbe'):
            self.assertNotIn(gone, out)
        self.assertIn('done', out)

    def test_secrets_file_and_state(self):
        with tempfile.TemporaryDirectory() as d:
            sf = os.path.join(d, 's.txt')
            with open(sf, 'w') as f:
                f.write('secretvalue1\nab\n\n')
            sj = os.path.join(d, 'state.json')
            with open(sj, 'w') as f:
                json.dump({'bots': [{'account': 'tstbotAAAAAAAAAA', 'password': 'pw-with_dash-12345'}]}, f)
            got = R.secrets_of(sf, sj)
            self.assertIn('secretvalue1', got)
            self.assertIn('pw-with_dash-12345', got)
            self.assertNotIn('ab', got, 'a value under six characters would cut ordinary words')

    def test_report_reaches_no_secret(self):
        act = ACTIVITY + '10:41:06 Tester Aka (L1900 Mystic) CHECK    PASS other: dbpass=Sup3rDBpass here\n'
        text = R.build_report('malgrath', 1900, ['Tester Aka'], act, CLIENT, 5, ['Sup3rDBpass'])
        self.assertNotIn('Sup3rDBpass', text)


    def test_the_kind_column_is_padded_like_testers_py(self):
        """the second run: testers.py writes '%s %s %-8s %s', so the verdict line reads `CHECK    SKIP pinnacle_party:`; the report and the grep of the script
        did not match it (the fixtures here had one space). The line below is made with the same format string"""
        who = 'Tester Aaa (L1900 Illusionist)'
        line = '%s %s %-8s %s' % ('20:37:50', who, 'CHECK', 'SKIP pinnacle_party: the member Aad did not come to the Keeper: no way to npc Keeper of the Pinnacle: another floor')
        self.assertIn('CHECK    SKIP', line)
        v = R.verdict_of(R.fight_lines(line + '\n'))
        self.assertEqual((v['status'], v['result']), ('SKIP', 'not killed'))
        self.assertIn('the member Aad did not come to the Keeper', v['text'])
        text = R.build_report('malgrath', 1900, ['Tester Aaa'], line + '\n', '')
        self.assertIn('the boss was NOT killed', text)
        self.assertNotIn('result: unknown', text)
        sh = read('tools', 'ci', 'boss_video.sh')
        pattern = re.search(r"grep -qP '([^']*pinnacle_party:[^']*)'", sh).group(1)
        self.assertTrue(re.search(pattern.replace('(?!played as a member)', '(?!played as a member)'), line))
        self.assertFalse(re.search(pattern, '%s %s %-8s %s' % ('20:36:31', who, 'CHECK', "SKIP pinnacle_party: played as a member of the party of Tester Aaa")))

    def test_retry_lines_are_in_the_report(self):
        act = ('20:30:00 Tester Aaa (L1900 Illusionist) RETRY    pinnacle_party try 1 of 8 did not open the fight (the member Aad did not come): the bots wait in the temple\n'
               '20:40:00 Tester Aaa (L1900 Illusionist) CHECK    PASS pinnacle_party: Ascended Malgrath down in 301 s, 2 fall(s)\n')
        text = R.build_report('malgrath', 1900, ['Tester Aaa'], act, '[info] bosstour: ready\n')
        self.assertIn('RETRY    pinnacle_party try 1 of 8', text)
        self.assertIn('killed in 301 s', text)

    def test_deaths_are_summed_with_their_killers(self):
        rows = []
        for i, (who, wh, tail) in enumerate([
                ('Aad', 'town', '; killed by a Dragon 912, a Dragon Hatchling 40 (3 last hit(s)); last helper move hunt 15 s before'),
                ('Aad', 'depot', '; killed by a Dragon 100 (1 last hit(s)); last helper move hunt 9 s before'),
                ('Aaa', 'hunt', '; no damage line seen; last helper move town 400 s before'),
                ('Aaa', 'shop', '; killed by a Wyrm 77 (2 last hit(s))')]):
            rows.append('20:%02d:00 Tester %s (L1900 Elementalist) %-8s died while %s%s' % (i, who, 'DEATH', wh, tail))
        d = R.death_facts(rows)
        self.assertEqual(d['n'], 4)
        self.assertEqual(d['per_bot'], {'Tester Aad': 2, 'Tester Aaa': 2})
        self.assertEqual(d['while'], {'town': 1, 'depot': 1, 'hunt': 1, 'shop': 1})
        self.assertEqual(d['killers'], {'a Dragon': 2, 'a Wyrm': 1})
        self.assertEqual(d['unseen'], 1)
        self.assertEqual(d['move'], {'hunt': 2, 'town': 1})
        text = R.build_report('malgrath', 1900, ['Tester Aad'], '\n'.join(rows) + '\n', '')
        self.assertIn('deaths: 4 (Tester Aaa 2, Tester Aad 2)', text)
        self.assertIn('not the place it died in', text)
        self.assertIn('a Dragon 2', text)
        self.assertIn('deaths with no damage line before them: 1 of 4', text)

    def test_many_deaths_do_not_bury_the_verdict(self):
        rows = ['20:%02d:%02d Tester Aad (L1900 Elementalist) %-8s died while town' % (i // 60, i % 60, 'DEATH') for i in range(100)]
        act = '\n'.join(rows) + '\n20:59:00 Tester Aaa (L1900 Illusionist) CHECK    FAIL pinnacle_party: Ascended Malgrath hurt to 40% in 400 s, not down (3 fall(s))\n'
        text = R.build_report('malgrath', 1900, ['Tester Aaa'], act, '')
        self.assertIn('deaths: 100', text)
        self.assertIn('[88 more deaths left out]', text)
        self.assertIn('NOT killed after 400 s', text)
        self.assertLess(text.count(' DEATH '), 14)

    def test_console_tail_is_scrubbed(self):
        secrets = ['Sup3rDBpass', 'lcs1abc123']
        lines = ['[2026-11-20 20:00:00] boot line %d' % i for i in range(500)]
        lines += ['[x] Tester Aad has logged in from 10.1.2.3',
                  '[x] mysql connect user=chaos password=Sup3rDBpass',
                  '[x] account lcs1abc123 entered', '[x] guard key ' + 'ab' * 32,
                  '[x] tstbot0123456789 was here',
                  '[x] Tester Aad lost 912 hitpoints to a Dragon']
        out = R.scrub_console('\n'.join(lines) + '\n', secrets, 300)
        for gone in ('Sup3rDBpass', 'lcs1abc123', 'ab' * 32, 'tstbot0123456789', '10.1.2.3', 'password'):
            self.assertNotIn(gone, out)
        self.assertIn('<ip>', out)
        self.assertIn('Tester Aad lost 912 hitpoints to a Dragon', out, 'a plain line stays')
        self.assertLessEqual(len(out.splitlines()), 300 + 2)
        self.assertIn('line(s) with a sensitive word dropped', out)
        self.assertNotIn('boot line 0\n', out, 'only the tail')


class Static(unittest.TestCase):
    def test_grid_of_the_client_module_is_the_servers(self):
        cfg = read('server', 'data', 'scripts', 'chaos', 'pinnacle_config.lua')
        g = re.search(r'grid = \{origin = \{x = (\d+), y = (\d+), z = (\d+)\}, cols = (\d+), slots = (\d+), spacing = (\d+)\}', cfg)
        self.assertTrue(g)
        x, y, z, cols, slots, spacing = (int(v) for v in g.groups())
        logic = read('client', 'overlay', 'modules', 'test_bosstour', 'bosstourlogic.lua')
        m = re.search(r'L\.GRID = \{x = (\d+), y = (\d+), z = (\d+), cols = (\d+), slots = (\d+), spacing = (\d+)\}', logic)
        self.assertTrue(m)
        self.assertEqual(tuple(int(v) for v in m.groups()), (x, y, z, cols, slots, spacing))

    def test_module_is_armed_by_its_variable_only(self):
        glue = read('client', 'overlay', 'modules', 'test_bosstour', 'bosstour.lua')
        logic = read('client', 'overlay', 'modules', 'test_bosstour', 'bosstourlogic.lua')
        self.assertIn("L.ENV_ON = 'CHAOS_BOSSTOUR'", logic)
        self.assertIn("get(L.ENV_ON) ~= '1'", logic)
        self.assertRegex(glue, r"if not cfg then\n\s+if err ~= 'off'")
        for word in ('addTab', 'g_ui.loadUI', 'bindKeyPress', 'registerTopBar', 'ChaosTopbar'):
            self.assertNotIn(word, glue, 'the test module must not add a window, hotkey or hub card')
        for l in glue.splitlines():
            if 'log(' in l:
                self.assertNotIn('password', l.lower(), 'the password is never logged: ' + l.strip())

    def test_workflow_is_manual_and_secret_free(self):
        wf = read('.github', 'workflows', 'boss-video.yml')
        self.assertRegex(wf, r'(?m)^on:\n  workflow_dispatch:')
        self.assertNotRegex(wf, r'(?m)^  (push|pull_request|schedule|workflow_run):')
        self.assertNotIn('secrets.', wf, 'no repository secret: the guard key is made in the run')
        self.assertIn('::add-mask::$key', wf)
        self.assertIn('boss:', wf)
        self.assertIn('default: malgrath', wf)
        self.assertRegex(wf, r'(?m)^permissions:\n  contents: read')
        self.assertNotIn('git push', wf)
        for line in wf.splitlines():
            m = re.match(r'^\s*- name: (.*)$', line)
            if m:
                self.assertNotIn(': ', m.group(1), 'a step name with ": " breaks the YAML: ' + m.group(1))
        up = wf[wf.index('actions/upload-artifact'):]
        paths = re.findall(r'\$\{\{ runner\.temp \}\}/boss-video/(\S+)', up)
        self.assertEqual(sorted(paths), ['*_fight.mp4', 'client-log.txt', 'fight-report.txt', 'server-console-tail.txt'],
                         'only the mp4, the report, the client log and the tail of the server console are uploaded')
        self.assertIn('name: boss-video', up)
        self.assertIn('UL_PINNACLE_PARTY: "1"', wf)
        self.assertIn('tools/ci/boss_video.sh', wf)
        try:
            import yaml
        except ImportError:
            return
        d = yaml.safe_load(wf)
        self.assertEqual(list(d[True]), ['workflow_dispatch'])
        inputs = d[True]['workflow_dispatch']['inputs']
        self.assertEqual(inputs['boss']['default'], 'malgrath')
        self.assertEqual(inputs['seconds']['default'], '480')

    def test_script_limits(self):
        sh = read('tools', 'ci', 'boss_video.sh')
        self.assertIn('BV_SECONDS:-480', sh)
        self.assertIn('-gt 900', sh)
        self.assertIn('-pix_fmt yuv420p', sh)
        self.assertIn('-c:v libx264', sh)
        self.assertIn('-crf 23', sh)
        self.assertIn('-movflags +faststart', sh)
        self.assertIn('--checks --closed --only pinnacle_party --video --prep-minutes', sh)
        # O689: the bots' kind column is padded (testers.py '%-8s'): every grep of the activity log allows the spaces
        self.assertNotIn(' CHECK [A-Z]+ pinnacle_party', sh)
        self.assertEqual(sh.count(' CHECK +[A-Z]+ +pinnacle_party'), 3)
        # the database login goes to the bots only, the client gets the spectator's account only
        client = sh[sh.index('export CHAOS_BOSSTOUR=1'):]
        self.assertNotIn('PARTYF', client[:client.index('exec ./chaos-client')])

    def test_live_check_switch(self):
        sh = read('tools', 'ci', 'unity_live_check.sh')
        self.assertIn('UL_PINNACLE_PARTY', sh)
        self.assertIn('group_id', sh)
        m = re.search(r"new_spectator\(\) \{.*?^\}", sh, re.S | re.M)
        self.assertTrue(m)
        self.assertIn("'$PN', 6,", m.group(0), 'the spectator is a group 6 staff character')
        self.assertNotIn('7102900', m.group(0), 'the spectator is not a tester')
        self.assertNotIn('Tester', m.group(0))
        party = re.search(r"setup_pinnacle_party\(\) \{.*?^\}", sh, re.S | re.M).group(0)
        self.assertIn('--classes Mystic:1,Ranger:1,Warrior:1,Mystic:1,Thief:1', party)
        self.assertIn('--count 5', party)
        self.assertIn('chaos_testers_closed', party)
        self.assertNotIn('git ', party)
        # the plan's base classes become the five classes of the party
        checks = read('server', 'tools', 'tester_checks.py')
        plan = re.search(r"PINNACLE_PLAN = \(([^)]*)\)", checks).group(1)
        self.assertEqual([p.strip(" '") for p in plan.split(',')], ['Illusionist', 'Juggernaut', 'Deadeye', 'Elementalist', 'Samurai'])


FAKE_CLIENT = """#!/usr/bin/env bash
# a client that writes the log lines of test_bosstour, no window
echo "env: account $CHAOS_LIVE_ACCOUNT password $CHAOS_LIVE_PASSWORD follow $CHAOS_BOSSTOUR_FOLLOW boss $CHAOS_BOSSTOUR_BOSS seconds $CHAOS_BOSSTOUR_SECONDS"
if [ -n "${CHAOS_DB_PASS:-}" ]; then echo "LEAK: the client got the database login"; fi
if [ "${FAKE_NO_FIGHT:-0}" = 1 ]; then exec sleep 600; fi
sleep 2
echo "bosstour: ready"
sleep 2
echo "bosstour: boss 80% at 12 s in the fight, party member 2 tiles away"
sleep 7
echo "bosstour: fight state success"
echo "bosstour: done ok boss dead"
"""

FAKE_TESTERS = '''\
import os, signal, sys, time
state = sys.argv[sys.argv.index('--state') + 1]
if os.environ.get('CHAOS_BOSSTOUR'):
    print('LEAK: the bots got the client switch')
os.makedirs(os.path.join(state, 'runs'), exist_ok=True)
with open(os.path.join(state, 'runs', 'run-20261120-100000.log'), 'a', buffering=1) as f:
    f.write('10:00:00 Tester Aka (L1900 Mystic) login    in game\\n')
    time.sleep(%(delay)s)
    f.write(%(line)r + '\\n')
    signal.signal(signal.SIGTERM, lambda *a: sys.exit(0))
    print('args: ' + ' '.join(sys.argv[2:]))
    while True:
        time.sleep(0.5)
'''

VERDICT = ("10:01:00 Tester Aka (L1900 Illusionist) CHECK    PASS pinnacle_party: Ascended Malgrath down in 301 s, 2 fall(s), 5 player(s), level 1900; "
           "carried out: Tester Bel at 86 s; party: Illusionist, Juggernaut, Deadeye, Elementalist, Samurai")
SKIPPED = "10:01:00 Tester Aka (L1900 Mystic) CHECK    SKIP pinnacle_party: the party could not be formed (a bot left the game)"


@unittest.skipUnless(shutil.which('Xvfb') and shutil.which('ffmpeg') and shutil.which('ffprobe'), 'needs Xvfb, ffmpeg and ffprobe')
class BossVideoRun(unittest.TestCase):
    def setUp(self):
        self.d = tempfile.mkdtemp(prefix='bossvideo_')
        self.addCleanup(shutil.rmtree, self.d, True)
        self.game = os.path.join(self.d, 'game')
        os.makedirs(self.game)
        client = os.path.join(self.game, 'chaos-client')
        with open(client, 'w') as f:
            f.write(FAKE_CLIENT)
        os.chmod(client, 0o755)
        self.key = 'ab' * 32
        self.envf = os.path.join(self.d, 'client-chaos.env')
        with open(self.envf, 'w') as f:
            f.write("export CHAOS_LIVE_HOST=127.0.0.1\nexport CHAOS_LIVE_ACCOUNT=lcs1abc123\nexport CHAOS_LIVE_PASSWORD=Pw0rdSecret99\n"
                    "export CHAOS_LIVE_CHARACTER='Live Aldric A'\nexport CHAOS_CLIENT_KEY=%s\n" % self.key)
        self.state = os.path.join(self.d, 'testers')
        os.makedirs(self.state)
        with open(os.path.join(self.state, 'state.json'), 'w') as f:
            json.dump({'bots': [{'name': 'Tester Aka', 'account': 'tstbot0123456789', 'password': 'BotPw-secret_12345'}]}, f)
        self.tfs = os.path.join(self.d, 'tfs.log')
        with open(self.tfs, 'w') as f:
            f.write('>> Loading map\n>> Tester Aka has logged in from 10.0.0.9\n>> db login DbPassSecret77 for tstbot0123456789\n'
                    '>> Tester Cor died: killed by a Dragon\n>> rsa key file loaded\n')
        self.partyf = os.path.join(self.d, 'party.env')
        with open(self.partyf, 'w') as f:
            f.write("export PARTY_NAMES='Tester Aka,Tester Bel,Tester Cor,Tester Dun,Tester Eld'\nexport PARTY_BOSS=malgrath\nexport PARTY_LEVEL=1900\n"
                    "export TESTERS_STATE=%s\nexport TESTERS_KEY_FILE=/nonexistent\nexport TESTERS_SERVER_DIR=/nonexistent\n"
                    "export TESTERS_TFS_LOG=%s\nexport TESTERS_HOST=127.0.0.1\nexport TESTERS_PORT=7171\n"
                    "export CHAOS_DB_PASS=DbPassSecret77\n" % (self.state, self.tfs))
        self.out = os.path.join(self.d, 'out')

    def run_script(self, line, delay=3, extra=None, timeout=180):
        fake = os.path.join(self.d, 'fake_testers.py')
        with open(fake, 'w') as f:
            f.write(FAKE_TESTERS % {'delay': delay, 'line': line})
        env = dict(os.environ, BV_TESTERS=fake, BV_DISPLAY='96', BV_WIDTH='320', BV_HEIGHT='240', BV_SECONDS='30', BV_PREP_WAIT='120')
        env.update(extra or {})
        t0 = time.time()
        p = subprocess.run(['bash', os.path.join(ROOT, 'tools', 'ci', 'boss_video.sh'), self.game, self.envf, self.partyf, self.out],
                           capture_output=True, text=True, env=env, timeout=timeout)
        return p, time.time() - t0

    def test_a_fight_is_filmed_and_reported(self):
        p, secs = self.run_script(VERDICT)
        self.assertEqual(p.returncode, 0, p.stdout + p.stderr)
        self.assertEqual(sorted(os.listdir(self.out)), ['client-log.txt', 'fight-report.txt', 'malgrath_fight.mp4', 'server-console-tail.txt'], 'nothing but the four files is left')
        tail = read_path(os.path.join(self.out, 'server-console-tail.txt'))
        self.assertIn('Tester Cor died: killed by a Dragon', tail)
        for gone in ('DbPassSecret77', 'tstbot0123456789', '10.0.0.9', 'rsa key'):
            self.assertNotIn(gone, tail)
        video = os.path.join(self.out, 'malgrath_fight.mp4')
        probe = subprocess.run(['ffprobe', '-v', 'error', '-select_streams', 'v:0', '-show_entries', 'stream=codec_name,pix_fmt,width,height',
                                '-of', 'csv=p=0', video], capture_output=True, text=True).stdout.strip()
        self.assertEqual(sorted(probe.split(',')), sorted(['h264', 'yuv420p', '320', '240']))
        dur = float(subprocess.run(['ffprobe', '-v', 'error', '-show_entries', 'format=duration', '-of', 'csv=p=0', video], capture_output=True, text=True).stdout)
        self.assertGreater(dur, 3.0)
        self.assertLess(dur, 40.0, 'the recording stops with the tour, not at the time limit')
        report = read_path(os.path.join(self.out, 'fight-report.txt'))
        self.assertIn('the boss was killed in 301 s after it came (2 fall(s))', report)
        self.assertIn('Tester Bel at 86 s', report)
        clog = read_path(os.path.join(self.out, 'client-log.txt'))
        self.assertIn('bosstour: done ok boss dead', clog)
        self.assertIn('follow Tester Aka,Tester Bel,Tester Cor,Tester Dun,Tester Eld boss Malgrath seconds 30', clog)
        for secret in ('lcs1abc123', 'Pw0rdSecret99', self.key, 'DbPassSecret77', 'tstbot0123456789', 'BotPw-secret_12345'):
            for name, text in (('client log', clog), ('report', report), ('stdout', p.stdout), ('stderr', p.stderr), ('console tail', tail)):
                self.assertNotIn(secret, text, '%s shows %s' % (name, secret[:4]))
        self.assertNotIn('LEAK', clog + p.stdout)

    def test_a_check_that_ends_with_no_fight_fails(self):
        p, secs = self.run_script(SKIPPED, delay=1, extra={'FAKE_NO_FIGHT': '1', 'BV_CHECK_GRACE': '4'})
        self.assertEqual(p.returncode, 1, p.stdout + p.stderr)
        self.assertIn('no fight opened', p.stderr)
        self.assertFalse(os.path.exists(os.path.join(self.out, 'malgrath_fight.mp4')))
        report = read_path(os.path.join(self.out, 'fight-report.txt'))
        self.assertIn('never saw the fight open', report)
        self.assertIn('the party could not be formed', report)
        self.assertLess(secs, 60)

    def test_refused_limits(self):
        for key, value in (('BV_SECONDS', '901'), ('BV_SECONDS', '29'), ('BV_SECONDS', 'x'), ('BV_PREP_WAIT', '10'), ('BV_WIDTH', '321')):
            p, _ = self.run_script(VERDICT, extra={key: value})
            self.assertEqual(p.returncode, 2, '%s=%s: %s' % (key, value, p.stderr))


def read_path(path):
    with open(path, encoding='utf-8', errors='replace') as f:
        return f.read()


if __name__ == '__main__':
    unittest.main(verbosity=1)
