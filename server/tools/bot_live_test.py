#!/usr/bin/env python3
"""python3 -I server/tools/bot_live_test.py: the live state of the tester bots for the staff map (bot_live.py, O727; server/README.md "Bot live map (O727)").

The pure parts (names, text cleaning, staleness, the experience curve), the writer (one JSON line a bot, atomic, at most one write every
WRITE_EVERY seconds, a heartbeat, the log of 50 lines, files gone at the end), the folder reader with the grey / drop rule, the views a
journey and a behaviour give, and the hooks in testers.py (Results.log feeds the bot's log, a helper answer sets the position, the
scheduler's pick sets the goal, a journey look and a check set the rest). A mocked clock, a temp folder, no network, no game."""
import asyncio
import json
import os
import shutil
import stat
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import bot_live as BL  # noqa: E402
import tester_checks as TX  # noqa: E402
import tester_core as TC  # noqa: E402
import tester_journey as TJ  # noqa: E402
import testers as T  # noqa: E402


def read(path):
    with open(path, encoding='utf-8') as f:
        return f.read()


def touch(path, text=''):
    with open(path, 'w', encoding='utf-8') as f:
        f.write(text)


class Clock:
    def __init__(self, t=1000.0):
        self.t = t

    def __call__(self):
        return self.t


class Pure(unittest.TestCase):
    def test_slug_and_name_rule(self):
        self.assertEqual(BL.slug('Tester Abc'), 'tester-abc')
        for bad in ('', 'Tester', 'tester Abc', 'Tester ABC', 'Tester Abcd', 'Grimtooth', '../etc', None):
            self.assertEqual(BL.slug(bad), '', bad)

    def test_clean(self):
        self.assertEqual(BL.clean('a\n\tb\x00  c'), 'a b c')
        self.assertEqual(len(BL.clean('x' * 1000)), BL.FIELD_MAX)
        self.assertEqual(len(BL.clean('x' * 1000, BL.TEXT_MAX)), BL.TEXT_MAX)
        self.assertEqual(BL.clean(None), '')

    def test_staleness(self):
        self.assertEqual(BL.age_state(1000, 1000 + BL.GREY_AFTER), 'live')
        self.assertEqual(BL.age_state(1000, 1000 + BL.GREY_AFTER + 1), 'stale')
        self.assertEqual(BL.age_state(1000, 1000 + BL.DROP_AFTER + 1), 'gone')
        self.assertEqual(BL.age_state(None, 5), 'gone')
        self.assertEqual(BL.age_state('x', 5), 'gone')
        self.assertEqual(BL.GREY_AFTER, 120.0)   # the owner's rule: no update for 2 minutes shows greyed

    def test_exp_curve(self):
        self.assertEqual(BL.exp_for_level(20), 98800)    # the number the site's tests hold to the server
        self.assertEqual(BL.exp_for_level(21), 116000)
        self.assertEqual(BL.exp_for_level(1), 0)
        self.assertEqual(BL.exp_per_hour(20, {20: 60.0}), 116000 - 98800)
        self.assertEqual(BL.exp_per_hour(20, {20: 30.0}), 2 * (116000 - 98800))
        self.assertIsNone(BL.exp_per_hour(20, None))
        self.assertIsNone(BL.exp_per_hour(20, {19: 5}))
        self.assertIsNone(BL.exp_per_hour(20, {20: 0}))

    def test_pos(self):
        self.assertEqual(BL.pos_list({'x': 1, 'y': 2, 'z': 7}), [1, 2, 7])
        self.assertEqual(BL.pos_list((1, 2, 7)), [1, 2, 7])
        for bad in (None, {'x': 1}, [1, 2], [1, 2, 'a'], [True, 1, 1], 'abc'):
            self.assertIsNone(BL.pos_list(bad))


class Writer(unittest.TestCase):
    def setUp(self):
        self.d = tempfile.mkdtemp()
        self.clock = Clock()
        self.b = BL.BotBoard(os.path.join(self.d, 'live'), self.clock)

    def tearDown(self):
        shutil.rmtree(self.d, ignore_errors=True)

    def files(self):
        return sorted(os.listdir(self.b.folder))

    def test_one_json_line_per_bot(self):
        self.b.set('Tester Abc', cls='Ranger', level=120, pos=[32369, 32241, 7], goal='Hunt', why='because', spot='Rat cave', plan=['a', 'b'])
        self.b.log('Tester Abc', 'hunt ok', 'do')
        self.assertEqual(self.b.flush(), 1)
        self.assertEqual(self.files(), ['tester-abc.json'])
        text = read(os.path.join(self.b.folder, 'tester-abc.json'))
        self.assertEqual(text.count('\n'), 1)
        e = json.loads(text)
        self.assertEqual((e['v'], e['name'], e['class'], e['level'], e['pos'], e['goal'], e['why'], e['spot'], e['plan']),
                         (1, 'Tester Abc', 'Ranger', 120, [32369, 32241, 7], 'Hunt', 'because', 'Rat cave', ['a', 'b']))
        self.assertEqual(e['log'], [[1000, 'do: hunt ok']])
        self.assertEqual(e['now'], 'do: hunt ok')
        self.assertEqual(e['t'], 1000)
        self.assertEqual(e['goal_since'], 1000)
        self.assertEqual(sorted(e), sorted(['v', 'name', 'class', 'level', 'pos', 'goal', 'goal_since', 'why', 'spot', 'now', 'plan', 'log', 't', 'src']))

    def test_no_secret_fields(self):
        self.b.set('Tester Abc', cls='Ranger')
        self.b.flush()
        text = read(os.path.join(self.b.folder, 'tester-abc.json')).lower()
        for word in ('password', 'account', 'tstbot', 'token', 'secret'):
            self.assertNotIn(word, text)

    def test_atomic_and_readable(self):
        self.b.set('Tester Abc', level=5)
        self.b.flush()
        self.assertEqual([f for f in os.listdir(self.b.folder) if f.startswith('.tmp')], [])
        mode = stat.S_IMODE(os.stat(os.path.join(self.b.folder, 'tester-abc.json')).st_mode)
        self.assertEqual(mode, 0o644)   # the site's user reads it

    def test_not_a_tester_is_refused(self):
        self.assertFalse(self.b.set('Grimtooth', level=5))
        self.assertFalse(self.b.log('../x', 'hi'))
        self.assertEqual(self.b.flush(force=True), 0)
        self.assertEqual(self.files(), [])

    def test_rate_limit_and_heartbeat(self):
        self.b.set('Tester Abc', level=5)
        self.assertEqual(self.b.flush(), 1)
        self.b.log('Tester Abc', 'one')
        self.clock.t += 1
        self.assertEqual(self.b.flush(), 0, 'a change within WRITE_EVERY waits')
        self.clock.t += BL.WRITE_EVERY
        self.assertEqual(self.b.flush(), 1, 'then it is written')
        self.clock.t += BL.WRITE_EVERY + 1
        self.assertEqual(self.b.flush(), 0, 'nothing changed: nothing written')
        self.clock.t += BL.HEARTBEAT
        self.assertEqual(self.b.flush(), 1, 'a heartbeat keeps `t` fresh')
        self.assertEqual(json.loads(read(os.path.join(self.b.folder, 'tester-abc.json')))['t'], int(self.clock.t))

    def test_same_value_is_not_a_change(self):
        self.b.set('Tester Abc', level=5, goal='Hunt')
        self.b.flush()
        self.assertFalse(self.b.set('Tester Abc', level=5, goal='Hunt'))
        self.assertEqual(self.b.dirty, set())

    def test_goal_since_follows_the_goal(self):
        self.b.set('Tester Abc', goal='Hunt')
        self.clock.t += 500
        self.b.set('Tester Abc', why='x')
        self.assertEqual(self.b.bots['Tester Abc']['goal_since'], 1000)
        self.b.set('Tester Abc', goal='Town')
        self.assertEqual(self.b.bots['Tester Abc']['goal_since'], 1500)

    def test_log_keeps_the_last_50_newest_last(self):
        for i in range(80):
            self.clock.t += 1
            self.b.log('Tester Abc', 'line %d' % i)
        log = self.b.bots['Tester Abc']['log']
        self.assertEqual(len(log), BL.LOG_MAX)
        self.assertEqual(log[0][1], 'line 30')
        self.assertEqual(log[-1][1], 'line 79')
        self.assertTrue(all(a[0] <= b[0] for a, b in zip(log, log[1:])))

    def test_bad_values_keep_the_old_ones(self):
        self.b.set('Tester Abc', level=7, pos=[1, 2, 3])
        self.b.set('Tester Abc', level=-1, pos='nowhere')
        e = self.b.bots['Tester Abc']
        self.assertEqual((e['level'], e['pos']), (7, [1, 2, 3]))
        self.b.set('Tester Abc', plan=['x' * 999] * 20)
        self.assertEqual(len(e['plan']), BL.PLAN_MAX)
        self.assertTrue(all(len(p) <= BL.FIELD_MAX for p in e['plan']))
        self.assertFalse(self.b.set('Tester Abc', password='x'))   # an unknown field is ignored
        self.assertNotIn('password', e)

    def test_close_removes_the_files(self):
        self.b.set('Tester Abc', level=1)
        self.b.set('Tester Abd', level=1)
        self.b.flush()
        self.assertEqual(len(self.files()), 2)
        self.b.close()
        self.assertEqual(self.files(), [])

    def test_clear_folder_removes_old_bot_files(self):
        touch(os.path.join(self.b.folder, 'tester-old.json'), '{}')
        touch(os.path.join(self.b.folder, '.tmpx'), '')
        touch(os.path.join(self.b.folder, 'readme.txt'), 'keep')
        self.assertEqual(BL.clear_folder(self.b.folder), 2)
        self.assertEqual(self.files(), ['readme.txt'])

    def test_unwritable_folder_is_not_an_error(self):
        self.b.set('Tester Abc', level=1)
        shutil.rmtree(self.b.folder)
        self.assertEqual(self.b.flush(), 0)


class Reader(unittest.TestCase):
    def test_fresh_stale_gone_and_broken(self):
        d = tempfile.mkdtemp()
        try:
            clock = Clock(5000.0)
            b = BL.BotBoard(d, clock)
            for name, age in (('Tester Fre', 10), ('Tester Sta', 300), ('Tester Gon', 5000)):
                b.set(name, level=3)
                b.write(name, 5000.0 - age)
            touch(os.path.join(d, 'tester-bad.json'), '{not json')
            touch(os.path.join(d, 'tester-oth.json'), json.dumps({'name': 'Grimtooth', 't': 5000}))
            got = [(e['name'], st) for e, st in BL.read_folder(d, 5000.0)]
            self.assertEqual(got, [('Tester Fre', 'live'), ('Tester Sta', 'stale')])
        finally:
            shutil.rmtree(d, ignore_errors=True)

    def test_missing_folder(self):
        self.assertEqual(BL.read_folder('/nonexistent/folder'), [])


class Views(unittest.TestCase):
    def test_journey_hunt_view_gives_the_reason_and_the_model(self):
        j = TJ.Journey('Tester Jny', 'Knight', 120)
        j.stage = 'hunt'
        j.hunt = {'id': 'cave', 'n': 'Cave Rats', 'lo': 90, 'hi': 160, 'at': 0}
        v = BL.journey_view(j, 120, {120: 60.0})
        self.assertEqual(v['goal'], 'Hunt')
        self.assertIn('level 120 is inside levels 90-160 of Cave Rats', v['why'])
        self.assertIn('exp/h', v['why'])
        self.assertIn(BL.spaced(BL.exp_per_hour(120, {120: 60.0})), v['why'])
        self.assertEqual(v['spot'], 'Cave Rats (levels 90-160)')
        self.assertEqual(len(v['plan']), 4)
        self.assertTrue(v['plan'][0].startswith('Keep hunting Cave Rats'))
        self.assertNotIn('exp/h', BL.journey_view(j, 120, None)['why'])

    def test_journey_trip_and_walk(self):
        j = TJ.Journey('Tester Jny', 'Knight', 30)
        j.stage = 'trip'
        j.todo = ['depot', 'gate', 'npc:Loot Buyer', 'npc:Veyra the Apothecary']
        v = BL.journey_view(j)
        self.assertEqual(v['goal'], 'Town trip')
        self.assertEqual(v['plan'][:4], ['Depot locker', 'Temple teleport to the hall', 'Loot Buyer', 'Veyra the Apothecary'])
        self.assertIn('trip to town', v['why'])
        j.stage, j.todo, j.target = 'hall', [], {'n': 'Bog', 'lo': 20, 'hi': 60}
        v = BL.journey_view(j, 30)
        self.assertEqual(v['goal'], 'Walk to a hunt')
        self.assertEqual(v['plan'], ['Walk to the hunt Bog'])
        self.assertEqual(v['spot'], 'Bog (levels 20-60)')

    def test_journey_leave_and_fallback(self):
        j = TJ.Journey('Tester Jny', 'Knight', 30)
        j.stage = 'leave'
        self.assertEqual(BL.journey_view(j)['goal'], 'Back to town')
        j.stage = 'start'
        j.fall('hall', 'no gate')
        self.assertIn('fallback: hall (no gate)', BL.journey_view(j)['why'])

    def test_behaviour_view(self):
        v = BL.behaviour_view('depot')
        self.assertEqual(v['goal'], 'Depot')
        self.assertIn('scheduler', v['why'])
        v = BL.behaviour_view('checks', ['pets', 'rift'])
        self.assertEqual(v['goal'], 'System checks')
        self.assertEqual(v['plan'], ['Check: pets', 'Check: rift'])
        self.assertEqual(BL.behaviour_view('newthing')['goal'], 'Newthing')

    def test_every_scheduler_behaviour_has_a_label(self):
        for k in TC.BEHAVIOURS:
            self.assertIn(k, BL.GOALS, k)


class Hooks(unittest.TestCase):
    """testers.py: the activity log feeds the live log; helper answers, the scheduler and the journey set the rest"""

    def setUp(self):
        self.d = tempfile.mkdtemp()
        self.clock = Clock()
        self.board = BL.BotBoard(os.path.join(self.d, 'live'), self.clock)

        class A:
            host = '10.0.0.1'
            ops = {}
            after_login = ''
            on_answer = None
        self.res = T.Results(1)
        self.res.live = self.board
        bot = {'account': 'tstbot0123456789', 'password': 'x', 'name': 'Tester Hok', 'level': 40, 'class': 'Knight', 'vocation': 4, 'player_id': 1}
        self.bot = T.TesterBot(0, bot, A(), 1, self.res, {'rotation': [], 'heal': None})
        self.bot.cid = 77

    def tearDown(self):
        shutil.rmtree(self.d, ignore_errors=True)

    def test_results_log_feeds_the_live_log(self):
        self.res.log(self.bot, 'do', 'hunt ok')
        self.res.log(None, 'online', '3 testers in game')   # no bot: not a bot's line
        e = self.board.bots['Tester Hok']
        self.assertEqual([x[1] for x in e['log']], ['do: hunt ok'])

    def test_results_without_a_board_is_unchanged(self):
        res = T.Results(1)
        res.log(self.bot, 'do', 'x')   # no live board, no activity file: nothing happens
        self.assertIsNone(res.live)

    def test_helper_answer_sets_position_and_level(self):
        self.bot.live_seen({'pos': {'x': 32369, 'y': 32241, 'z': 7}, 'level': 41})
        e = self.board.bots['Tester Hok']
        self.assertEqual((e['pos'], e['level']), ([32369, 32241, 7], 41))
        self.bot.live_seen({'err': 'x'})
        self.bot.live_seen(None)
        self.assertEqual(e['pos'], [32369, 32241, 7])

    def test_poll_asks_info_only_when_the_position_is_old(self):
        sent = []
        self.bot.say = lambda text, kind=1: sent.append(text)
        self.bot.live_poll(100.0)
        self.assertEqual(sent, ['!tester info'])
        self.bot.live_poll(100.0 + 5)
        self.assertEqual(len(sent), 1)
        self.bot.live_poll(100.0 + T.LIVE_POLL + 1)
        self.assertEqual(len(sent), 2)
        self.bot.live_pos_at = 500.0
        self.bot.live_poll(500.0 + 5)
        self.assertEqual(len(sent), 2)
        self.res.live = None
        self.bot.live_poll(9999.0)
        self.assertEqual(len(sent), 2)

    def test_scheduler_pick_is_the_goal(self):
        self.bot.live_goal('shop')
        e = self.board.bots['Tester Hok']
        self.assertEqual((e['goal'], e['class'], e['level']), ('Shop', 'Knight', 40))
        self.assertIn('scheduler', e['why'])
        self.assertEqual(len(e['plan']), 2)

    def test_check_is_the_goal_and_the_rest_the_plan(self):
        self.bot.live_check('rift', ['rift', 'pets', 'party'])
        e = self.board.bots['Tester Hok']
        self.assertEqual(e['goal'], 'Check: rift')
        self.assertEqual(e['plan'], ['Check: pets', 'Check: party'])

    def test_checkrun_has_its_hook(self):
        self.assertIsNone(TX.CheckRun('Tester Hok', 'Knight', 40).live)

    def test_journey_pos_is_kept_by_a_look(self):
        j = TJ.Journey('Tester Hok', 'Knight', 40)

        class IO:
            def now(self):
                return 5.0

            async def helper(self, command, kind, wait=4.0):
                return {'level': 40, 'pos': {'x': 10, 'y': 20, 'z': 7}, 'zone': 'temple'}

            async def sleep(self, s):
                pass
        loop = asyncio.new_event_loop()
        try:
            s = loop.run_until_complete(j.look(IO()))
        finally:
            loop.close()
        self.assertEqual(j.pos, [10, 20, 7])
        self.assertEqual(s['zone'], 'temple')

    def test_open_board_respects_the_switches(self):
        class A:
            live_dir = ''
            no_live = False
        self.assertIsNone(T.open_board(A()))
        A.live_dir = os.path.join(self.d, 'x')
        A.no_live = True
        self.assertIsNone(T.open_board(A()))
        A.no_live = False
        b = T.open_board(A())
        self.assertIsNotNone(b)
        self.assertTrue(os.path.isdir(A.live_dir))

    def test_parse_defaults_the_live_dir_to_the_server_data(self):
        a = T.parse(['run', '--server-dir', '/srv/s', '--key-file', '/k'])
        self.assertEqual(a.live_dir, '/srv/s/data/chaos_botlive')
        a = T.parse(['run', '--server-dir', '/srv/s', '--key-file', '/k', '--live-dir', '/x/y', '--no-live'])
        self.assertEqual((a.live_dir, a.no_live), ('/x/y', True))


if __name__ == '__main__':
    unittest.main()
