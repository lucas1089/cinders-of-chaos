#!/usr/bin/env python3
"""python3 -I server/tools/tester_checks_test.py: the system checks of the tester bots (tester_checks.py) against a mocked
server. Every check has a passing run, a failing run that prints a BUG line, and a skip; the Auto setup rows are checked
against the real client data (every class, every preset)."""
import asyncio
import os
import re
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import tester_checks as TX  # noqa: E402

ROOT = os.path.normpath(os.path.join(HERE, '..', '..'))
MODULES = os.path.join(ROOT, 'client', 'overlay', 'modules')


class FakeIO:
    """a mocked game: scripted helper answers per command; time does not pass"""

    def __init__(self, answers=None, replies=None, partner='Tester Bbb', table=None, spells=None):
        self.answers = answers or {}      # helper command -> dict | callable(io) -> dict | None
        self.replies = replies or {}      # (opname, action) -> dict | None
        self.said, self.asked, self.moves, self.partied = [], [], [], []
        self.up = True
        self.partner_name = partner
        self.table, self.spell_table = table, spells or {}
        self.t = 0.0

    def alive(self):
        return self.up

    async def sleep(self, seconds):
        self.t += seconds

    async def say(self, text):
        self.said.append(text)

    async def go(self, place):
        self.moves.append(place)
        return True

    async def helper(self, command, kind, wait=4.0):
        a = self.answers.get(command)
        return a(self) if callable(a) else a

    async def request(self, opname, action, data, expect, timeout):
        self.asked.append((opname, action, data))
        return self.replies.get((opname, action))

    async def party(self, action, other):
        self.partied.append((action, other))
        return True

    async def partner(self):
        return self.partner_name

    def autosetup(self):
        return self.table

    def spells(self):
        return self.spell_table


def run(coro):
    loop = asyncio.new_event_loop()
    try:
        return loop.run_until_complete(coro)
    finally:
        loop.close()


def summons(*rows, owner='none', count=None):
    return {'who': 'Tester Aaa', 'ownerTarget': owner, 'count': len(rows) if count is None else count,
            'summons': [dict({'name': 'war wolf', 'id': 100 + i, 'target': 'none', 'listed': 1, 'listedAllies': 0}, **r)
                        for i, r in enumerate(rows)]}


class Pure(unittest.TestCase):
    def test_snapshot_rules(self):
        self.assertEqual(TX.snapshot_problems(summons({'target': 'monster'}, {'target': 'none'})), [])
        self.assertIn('targets its owner', TX.snapshot_problems(summons({'target': 'owner'}))[0])
        self.assertIn('an ally (ally)', TX.snapshot_problems(summons({'target': 'ally'}))[0])
        self.assertIn('an ally (summon)', TX.snapshot_problems(summons({'target': 'summon'}))[0])
        self.assertIn('engine target list', TX.snapshot_problems(summons({'listedAllies': 2}))[0])
        self.assertIn('holds', TX.snapshot_problems(summons({}, owner='summon'))[0])
        self.assertEqual(TX.snapshot_problems(None), [])

    def test_bug_line_only_on_fail(self):
        self.assertEqual(TX.Result('x', 'Tester Aaa', 'Beastmaster', TX.PASS).bug_line(), None)
        self.assertEqual(TX.Result('x', 'Tester Aaa', 'Beastmaster', TX.FAIL, 'wolf at owner').bug_line(),
                         'BUG x: wolf at owner (Tester Aaa, Beastmaster)')

    def test_checks_apply_by_class(self):
        keys = lambda cls: TX.CheckRun('t', cls, 100).todo()  # noqa: E731
        self.assertIn('beastmaster_wolf', keys('Beastmaster'))
        self.assertNotIn('necro_minions', keys('Beastmaster'))
        self.assertIn('necro_minions', keys('Lich'))
        self.assertNotIn('beastmaster_wolf', keys('Ninja'))
        for k in ('pets', 'party', 'rift', 'waystone', 'reward_chest', 'cursed_chest', 'auto_setup'):
            self.assertIn(k, keys('Ninja'))


class Summons(unittest.TestCase):
    def wolf(self, **kw):
        return summons(dict({'target': 'monster'}, **kw))

    def test_healthy_wolf_passes_with_a_teleport_leg(self):
        io = FakeIO({'summons': self.wolf()})
        r = run(TX.check_summons(io, 'Tester Aaa', 'Beastmaster', 100))
        self.assertEqual(r.status, TX.PASS, r.detail)
        self.assertEqual(io.said, ['vael ferh'])
        self.assertEqual(io.moves, ['hunt', 'town', 'hunt'])

    def test_wolf_at_its_owner_is_a_bug(self):
        io = FakeIO({'summons': summons({'target': 'owner'})})
        r = run(TX.check_summons(io, 'Tester Aaa', 'Beastmaster', 100))
        self.assertEqual(r.status, TX.FAIL)
        self.assertTrue(r.bug_line().startswith('BUG beastmaster_wolf: war wolf #100 targets its owner'))

    def test_allies_left_in_the_target_list_are_a_bug(self):
        io = FakeIO({'summons': self.wolf(listedAllies=2)})
        r = run(TX.check_summons(io, 'Tester Aaa', 'Beastmaster', 100))
        self.assertEqual(r.status, TX.FAIL)
        self.assertIn('2 allies in its engine target list', r.detail)

    def test_bug_only_after_a_teleport(self):
        calls = {'n': 0}

        def answer(io):
            calls['n'] += 1
            # the first watch (11 looks) is clean; the leg after the teleport is wrong
            return summons({'target': 'owner' if 'town' in io.moves else 'monster'})

        r = run(TX.check_summons(FakeIO({'summons': answer}), 'Tester Aaa', 'Beastmaster', 100))
        self.assertEqual(r.status, TX.FAIL)
        self.assertTrue(r.detail.startswith('after a teleport'))

    def test_no_summon_is_a_skip_not_a_pass(self):
        r = run(TX.check_summons(FakeIO({'summons': summons()}), 'Tester Aaa', 'Necromancer', 20))
        self.assertEqual(r.status, TX.SKIP)
        self.assertIn('no summon after "vael oss"', r.detail)

    def test_no_helper_answer_is_a_skip(self):
        self.assertEqual(run(TX.check_summons(FakeIO({}), 'Tester Aaa', 'Lich', 100)).status, TX.SKIP)

    def test_too_many_minions(self):
        r = run(TX.check_summons(FakeIO({'summons': summons(*[{'target': 'monster'}] * 7)}), 'Tester Aaa', 'Necromancer', 100))
        self.assertEqual(r.status, TX.FAIL)
        self.assertIn('cap is 5', r.detail)


class Pets(unittest.TestCase):
    def test_no_window_no_pet(self):
        self.assertEqual(run(TX.check_pets(FakeIO(), 'Tester Aaa', 'Ninja', 100)).status, TX.SKIP)
        io = FakeIO(replies={('pets', 'get'): {'action': 'state', 'data': {'pets': []}}})
        self.assertIn('owns no pet', run(TX.check_pets(io, 'Tester Aaa', 'Ninja', 100)).detail)

    def test_pet_out_and_dismissed(self):
        state = {'action': 'state', 'data': {'pets': [{'species': 'fox'}]}}
        out = summons({'name': 'fox', 'target': 'monster'})

        def answer(io):
            return out if not any(a[1] == 'dismiss' for a in io.asked) else summons()

        io = FakeIO({'summons': answer}, {('pets', 'get'): state})
        r = run(TX.check_pets(io, 'Tester Aaa', 'Ninja', 100))
        self.assertEqual(r.status, TX.PASS, r.detail)
        self.assertEqual([a[1] for a in io.asked], ['get', 'summon', 'dismiss'])
        self.assertEqual(io.asked[1][2], {'species': 'fox'})

    def test_pet_that_attacks_the_owner_or_stays_out(self):
        state = {'action': 'state', 'data': {'pets': [{'key': 'fox'}]}}
        io = FakeIO({'summons': summons({'name': 'fox', 'target': 'owner'})}, {('pets', 'get'): state})
        self.assertEqual(run(TX.check_pets(io, 'Tester Aaa', 'Ninja', 100)).status, TX.FAIL)
        io = FakeIO({'summons': summons({'name': 'fox', 'target': 'monster'})}, {('pets', 'get'): state})
        r = run(TX.check_pets(io, 'Tester Aaa', 'Ninja', 100))
        self.assertEqual((r.status, r.detail), (TX.FAIL, 'the pet is still out after dismiss'))


class Party(unittest.TestCase):
    def test_form_and_leave(self):
        def size(io):
            return {'size': 2 if ('form', 'Tester Bbb') in io.partied and ('leave', 'Tester Bbb') not in io.partied else 1}

        io = FakeIO({'party': size})
        r = run(TX.check_party(io, 'Tester Aaa', 'Ninja', 100))
        self.assertEqual(r.status, TX.PASS, r.detail)
        self.assertEqual(io.partied, [('form', 'Tester Bbb'), ('leave', 'Tester Bbb')])

    def test_no_partner_or_never_joined(self):
        self.assertEqual(run(TX.check_party(FakeIO(partner=None), 'Tester Aaa', 'Ninja', 100)).status, TX.SKIP)
        r = run(TX.check_party(FakeIO({'party': {'size': 1}}), 'Tester Aaa', 'Ninja', 100))
        self.assertEqual(r.status, TX.FAIL)

    def test_still_in_the_party_after_leaving(self):
        r = run(TX.check_party(FakeIO({'party': {'size': 2}}), 'Tester Aaa', 'Ninja', 100))
        self.assertEqual(r.status, TX.FAIL)
        self.assertIn('still sees 2', r.detail)

    def test_wolf_in_a_party_keeps_its_sides(self):
        io = FakeIO({'party': {'size': 2}, 'summons': summons({'target': 'ally'})})
        # the size never drops, but the wolf failure comes first
        r = run(TX.check_party(io, 'Tester Aaa', 'Beastmaster', 100))
        self.assertEqual(r.status, TX.FAIL)
        self.assertTrue(r.detail.startswith('in a party:'))
        self.assertEqual(io.said, ['vael ferh'])


class Others(unittest.TestCase):
    def test_rift(self):
        io = FakeIO({'enter rift 1': {'pos': {}}}, {('rift', 'query'): {'action': 'state', 'data': {}}})
        self.assertEqual(run(TX.check_rift(io, 'Tester Aaa', 'Ninja', 100)).status, TX.PASS)
        self.assertEqual(run(TX.check_rift(FakeIO({'enter rift 1': {'err': 'no temple'}}), 'a', 'Ninja', 100)).status, TX.FAIL)
        self.assertEqual(run(TX.check_rift(FakeIO(), 'a', 'Ninja', 100)).status, TX.SKIP)

    def test_opcode_checks(self):
        ok = {('waystoneAtlas', 'open'): {'action': 'state', 'data': {}}}
        self.assertEqual(run(TX.check_waystone(FakeIO(replies=ok), 'a', 'Ninja', 100)).status, TX.PASS)
        self.assertEqual(run(TX.check_waystone(FakeIO(), 'a', 'Ninja', 100)).status, TX.SKIP)
        bad = {('weeklyChest', 'open'): {'action': 'state', 'data': {'err': 'boom'}}}
        io = FakeIO(replies=bad)
        self.assertEqual(run(TX.check_reward_chest(io, 'a', 'Ninja', 100)).status, TX.FAIL)
        self.assertEqual(io.asked[-1][1], 'close')

    def test_cursed_chest(self):
        state = {'v': 'none'}

        def chest(io):
            return {'state': state['v'], 'left': 0 if state['v'] == 'none' else 1, 'monsters': 5 if state['v'] == 'running' else 0}

        # a tiny state machine on the command
        class ChestIO(FakeIO):
            async def helper(self, command, kind, wait=4.0):
                if command == 'chest spawn':
                    state['v'] = 'idle'
                elif command == 'chest use':
                    state['v'] = 'running'
                elif command == 'chest abort':
                    state['v'] = 'none'
                return chest(self)

        r = run(TX.check_cursed_chest(ChestIO(), 'Tester Aaa', 'Ninja', 100))
        self.assertEqual(r.status, TX.PASS, r.detail)

        class StuckIO(ChestIO):
            async def helper(self, command, kind, wait=4.0):
                a = await ChestIO.helper(self, command, kind, wait)
                if command == 'chest abort':
                    state['v'] = 'running'
                    return chest(self)
                return a

        r = run(TX.check_cursed_chest(StuckIO(), 'Tester Aaa', 'Ninja', 100))
        self.assertEqual(r.status, TX.FAIL)
        self.assertIn('after abort', r.detail)
        self.assertEqual(run(TX.check_cursed_chest(FakeIO(), 'a', 'Ninja', 100)).status, TX.SKIP)
        io = FakeIO({'chest spawn': {'err': 'no cursed chest system'}})
        self.assertEqual(run(TX.check_cursed_chest(io, 'a', 'Ninja', 100)).status, TX.SKIP)


def client_spells():
    """{id: {name, level, vocations}} of the client's spelldata.lua (the Chaos spells)"""
    with open(os.path.join(MODULES, 'game_chaosspells', 'spelldata.lua'), encoding='utf-8') as f:
        text = f.read()
    out = {}
    for m in re.finditer(r'\{ id = (\d+), name = "([^"]+)".*?level = (\d+),.*?vocations = \{ ([\d, ]*) \}', text):
        out[int(m.group(1))] = {'name': m.group(2), 'level': int(m.group(3)),
                                'vocations': [int(x) for x in m.group(4).split(',') if x.strip()]}
    return out


class AutoSetup(unittest.TestCase):
    def test_every_class_preset_is_castable_at_its_level(self):
        table = TX.load_table(os.path.join(MODULES, 'game_helperrotation', 'autorotation_data.lua'))
        spells = client_spells()
        self.assertEqual(len(table), 21)
        for cls, row in table.items():
            self.assertTrue(row['presets'], cls)
            for p in row['presets']:
                # only the Chaos spells are here (spelldata.lua); the stock ones are checked by autosetup_classes_test.lua
                bad = [x for x in TX.auto_setup_problems(table, cls, p['level'], spells) if 'not on the server' not in x]
                self.assertEqual(bad, [], '%s level %d' % (cls, p['level']))

    def test_problems_are_reported(self):
        table = {'Ninja': {'voc': 12, 'presets': [{'level': 8, 'spells': [236]}, {'level': 100, 'spells': [240, 999, 50]}]}}
        spells = {236: {'name': 'Shuriken Toss', 'level': 8, 'vocations': [12]},
                  240: {'name': 'Shadow Step', 'level': 120, 'vocations': [12]},
                  50: {'name': 'Fire Wave', 'level': 8, 'vocations': [5]}}
        self.assertEqual(TX.auto_setup_problems(table, 'Ninja', 50, spells), [])
        bad = TX.auto_setup_problems(table, 'Ninja', 100, spells)
        self.assertEqual(len(bad), 3)
        self.assertTrue(any('needs level 120' in b for b in bad))
        self.assertTrue(any('spell 999 is not on the server' in b for b in bad))
        self.assertTrue(any('not open to Ninja' in b for b in bad))
        self.assertIsNone(TX.auto_setup_problems(table, 'Nobody', 50, spells))
        self.assertEqual(TX.auto_setup_problems(table, 'Ninja', 3, spells), [])

    def test_check_uses_the_table(self):
        table = {'Ninja': {'voc': 12, 'presets': [{'level': 8, 'spells': [236]}]}}
        spells = {236: {'name': 'Shuriken Toss', 'level': 8, 'vocations': [12]}}
        self.assertEqual(run(TX.check_auto_setup(FakeIO(table=table, spells=spells), 'a', 'Ninja', 50)).status, TX.PASS)
        self.assertEqual(run(TX.check_auto_setup(FakeIO(table=table, spells={}), 'a', 'Ninja', 50)).status, TX.FAIL)
        self.assertEqual(run(TX.check_auto_setup(FakeIO(table=None), 'a', 'Ninja', 50)).status, TX.SKIP)
        self.assertEqual(run(TX.check_auto_setup(FakeIO(table=table), 'a', 'Samurai', 50)).status, TX.SKIP)


class Runner(unittest.TestCase):
    def test_run_collects_results_and_report(self):
        table = {'Ninja': {'voc': 12, 'presets': [{'level': 8, 'spells': [236]}]}}
        spells = {236: {'name': 'Shuriken Toss', 'level': 8, 'vocations': [12]}}
        io = FakeIO({'summons': summons()}, table=table, spells=spells)
        cr = TX.CheckRun('Tester Aaa', 'Ninja', 50)
        self.assertTrue(run(cr.run(io)))
        self.assertTrue(cr.finished)
        got = {r.check: r.status for r in cr.results}
        self.assertEqual(got['auto_setup'], TX.PASS)
        self.assertEqual(got['pets'], TX.SKIP)
        text = '\n'.join(TX.report_lines([r.as_dict() for r in cr.results]))
        self.assertIn('== System checks', text)
        self.assertIn('skip pets', text)

    def test_only_and_a_bug_fail_the_run(self):
        io = FakeIO({'summons': summons({'target': 'owner'})})
        cr = TX.CheckRun('Tester Aaa', 'Beastmaster', 100, only=['beastmaster_wolf'])
        self.assertEqual(cr.todo(), ['beastmaster_wolf'])
        self.assertFalse(run(cr.run(io)))
        text = '\n'.join(TX.report_lines([r.as_dict() for r in cr.results]))
        self.assertIn('BUG beastmaster_wolf', text)

    def test_a_dead_bot_is_not_a_result(self):
        class Dying(FakeIO):
            async def helper(self, command, kind, wait=4.0):
                self.up = False
                return None

        io = Dying()
        cr = TX.CheckRun('Tester Aaa', 'Beastmaster', 100)
        self.assertFalse(run(cr.run(io)))
        self.assertEqual(cr.results, [])
        self.assertFalse(cr.finished)

    def test_a_check_that_breaks_is_a_skip(self):
        class Broken(FakeIO):
            async def request(self, *a):
                raise ValueError('boom')

        cr = TX.CheckRun('Tester Aaa', 'Ninja', 100, only=['waystone'])
        run(cr.run(Broken()))
        self.assertEqual((cr.results[0].status, cr.results[0].detail), (TX.SKIP, 'the check broke: boom'))


if __name__ == '__main__':
    unittest.main()
