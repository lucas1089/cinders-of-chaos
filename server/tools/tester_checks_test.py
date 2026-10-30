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
        for k in ('pets', 'party', 'rift', 'waystone', 'reward_chest', 'cursed_chest', 'auto_setup', 'spell_quest',
                  'rift_layout', 'waystone_run', 'content_rewards', 'party_xp'):
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


def waystone_answer(tier, **over):
    """what `!tester waystone <tier>` says on a correct server: a Rare waystone of 4 modifiers, a run, 2 monsters"""
    a = {'tier': tier, 'tierLevel': 1000 + 100 * tier, 'map': 1, 'nrolled': 4,
         'held': {'tier': tier, 'mods': 4, 'rarity': 'Rare', 'expectRarity': 'Rare'},
         'take': {'ok': True, 'mods': 4, 'before': 3, 'after': 2}, 'rescaled': 2,
         'run': {'active': tier, 'live': True, 'tier': tier, 'mods': 4, 'seconds': 1850, 'fxHealth': 1.3},
         'monsters': [{'name': 'Armorcoil', 'levelBefore': 1100, 'level': 1000 + 100 * tier,
                       'expectLevel': 1000 + 100 * tier, 'ratio': 1.4, 'expectRatio': 1.41}]}
    a.update(over)
    return a


class WaystoneRun(unittest.TestCase):
    def io(self, **over):
        return FakeIO({'waystone %d' % t: (lambda io, t=t: waystone_answer(t, **over)) for t in TX.WAYSTONE_TIERS})

    def test_a_correct_run_passes_in_every_band(self):
        r = run(TX.check_waystone_run(self.io(), 'Tester Aaa', 'Ninja', 100))
        self.assertEqual(r.status, TX.PASS, r.detail)
        for t in TX.WAYSTONE_TIERS:
            self.assertIn('tier %d' % t, r.detail)

    def test_each_wrong_fact_is_a_bug(self):
        cases = {
            'held': ({'held': {'tier': 3, 'mods': 2, 'rarity': 'Magic', 'expectRarity': 'Rare'}}, 'reads back'),
            'take': ({'take': {'ok': True, 'mods': 4, 'before': 3, 'after': 3}}, 'changed the count'),
            'taken': ({'take': {'ok': False}}, 'could not take'),
            'run': ({'run': {'active': 2, 'live': False}}, 'not registered'),
            'runmods': ({'run': {'active': 2, 'live': True, 'tier': 2, 'mods': 0, 'seconds': 1800}}, 'with 0 modifiers'),
            'active': ({'run': {'active': 1, 'live': True, 'tier': 2, 'mods': 4, 'seconds': 1800}}, 'counts at tier'),
            'level': ({'monsters': [{'name': 'Armorcoil', 'level': 1100, 'expectLevel': 1200, 'ratio': 1, 'expectRatio': 1}]}, 'is level 1100'),
            'health': ({'monsters': [{'name': 'Armorcoil', 'level': 1200, 'expectLevel': 1200, 'ratio': 1.0, 'expectRatio': 1.5}]}, 'health x1.000'),
            'ladder': ({'tierLevel': 1500}, 'runs at level 1500'),
        }
        for label, (over, text) in cases.items():
            r = run(TX.check_waystone_run(self.io(**over), 'Tester Aaa', 'Ninja', 100))
            self.assertEqual(r.status, TX.FAIL, label)
            self.assertIn(text, r.detail, label)
            self.assertTrue(r.bug_line().startswith('BUG waystone_run: tier 2:'), label)

    def test_skips_and_start_run_errors(self):
        self.assertEqual(run(TX.check_waystone_run(FakeIO(), 'a', 'Ninja', 100)).status, TX.SKIP)
        io = FakeIO({'waystone %d' % t: {'err': 'map in use'} for t in TX.WAYSTONE_TIERS})
        r = run(TX.check_waystone_run(io, 'a', 'Ninja', 100))
        self.assertEqual((r.status, 'map in use' in r.detail), (TX.SKIP, True))
        io = FakeIO({'waystone 2': {'err': 'no waystone system'}})
        self.assertEqual(run(TX.check_waystone_run(io, 'a', 'Ninja', 100)).status, TX.SKIP)
        io = FakeIO({'waystone 2': {'err': 'startRun: boom'}})
        r = run(TX.check_waystone_run(io, 'a', 'Ninja', 100))
        self.assertEqual(r.status, TX.FAIL)
        self.assertIn('ChaosWaystoneTiers.startRun: boom', r.detail)

    def test_a_map_in_use_does_not_hide_the_others(self):
        answers = {'waystone 2': {'err': 'map in use'}, 'waystone 8': waystone_answer(8), 'waystone 14': waystone_answer(14)}
        r = run(TX.check_waystone_run(FakeIO(answers), 'a', 'Ninja', 100))
        self.assertEqual(r.status, TX.PASS)
        self.assertIn('tier 2: map in use', r.detail)

    def test_no_monster_in_range_still_checks_the_rest(self):
        r = run(TX.check_waystone_run(self.io(monsters=[]), 'a', 'Ninja', 100))
        self.assertEqual(r.status, TX.PASS)
        self.assertIn('0 monster(s) sampled', r.detail)


def layout_answer(**over):
    a = {'tier': 3, 'theme': 'Obsidian Hall', 'kind': 'dungeon', 'band': 1, 'bandExpected': 1, 'floors': 1, 'side': 144,
         'walkable': 5600, 'route': 160, 'kinds': ['dungeon', 'mixed'], 'floorCounts': [1, 2],
         'limits': {'walkableMin': 4500, 'walkableMax': 7500}, 'startWalk': True, 'bossWalk': True, 'mouthWalk': True,
         'playerWalk': True, 'sample': {'n': 40, 'bare': 0, 'blocked': 0}, 'after': {'inRun': False, 'slotFree': True}}
    a.update(over)
    return a


class RiftLayout(unittest.TestCase):
    def check(self, **over):
        return run(TX.check_rift_layout(FakeIO({'riftrun layout': layout_answer(**over)}), 'Tester Aaa', 'Ninja', 600))

    def test_a_valid_layout_passes(self):
        r = self.check()
        self.assertEqual(r.status, TX.PASS, r.detail)
        self.assertIn('Obsidian Hall', r.detail)

    def test_each_broken_fact_is_a_bug(self):
        cases = {
            'kind': ({'kind': 'cave'}, 'layout kind cave'),
            'floors': ({'floors': 3}, '3 floor(s)'),
            'band': ({'band': 2}, 'band 2 layout'),
            'big': ({'walkable': 20000}, '20000 walkable tiles'),
            'small': ({'walkable': 100}, '100 walkable tiles'),
            'route': ({'route': -1}, 'no walking route'),
            'start': ({'startWalk': False}, 'the arrival is not a walkable'),
            'boss': ({'bossWalk': False}, 'guardian'),
            'mouth': ({'mouthWalk': False}, 'arena'),
            'player': ({'playerWalk': False}, 'the bot after entering'),
            'bare': ({'sample': {'n': 40, 'bare': 3, 'blocked': 0}}, '3 have no ground'),
            'blocked': ({'sample': {'n': 40, 'bare': 0, 'blocked': 2}}, '2 block'),
            'stuck': ({'after': {'inRun': True, 'slotFree': True}}, 'did not close'),
            'slot': ({'after': {'inRun': False, 'slotFree': False}}, 'did not close'),
            'read': ({'err': 'read: boom'}, 'read: boom'),
        }
        for label, (over, text) in cases.items():
            r = self.check(**over)
            self.assertEqual(r.status, TX.FAIL, label)
            self.assertIn(text, r.detail, label)
            self.assertTrue(r.bug_line().startswith('BUG rift_layout:'), label)

    def test_skips(self):
        self.assertEqual(run(TX.check_rift_layout(FakeIO(), 'a', 'Ninja', 600)).status, TX.SKIP)
        for err in ('level too low for a rift', 'the rift did not open (a slot is busy or being built)', 'no rifts on this server'):
            io = FakeIO({'riftrun layout': {'err': err}})
            self.assertEqual(run(TX.check_rift_layout(io, 'a', 'Ninja', 30)).status, TX.SKIP, err)


def loot_answer(**over):
    a = {'paid': True, 'items': 12, 'pieces': 4, 'minPieces': 3, 'badRarity': 0, 'waystones': 1, 'minWaystones': 1,
         'orbs': [{'id': 29851, 'name': 'Orb of Awakening', 'min': 2, 'count': 3},
                  {'id': 24691, 'name': 'Orb of Gilding', 'min': 1, 'count': 1}]}
    a.update(over)
    return a


class ContentRewards(unittest.TestCase):
    def io(self, loot=None, rift=None, waystone_err=None):
        way = {'tier': 8, 'loot': loot if loot is not None else loot_answer()}
        if waystone_err:
            way = {'err': waystone_err}
        return FakeIO({'waystone 8 loot': way, 'riftrun loot': rift if rift is not None else
                       {'tier': 5, 'loot': {'paid': True, 'items': 6, 'orbs': 7, 'minOrbs': 6}}})

    def test_both_pay_what_the_config_guarantees(self):
        r = run(TX.check_content_rewards(self.io(), 'Tester Aaa', 'Ninja', 600))
        self.assertEqual(r.status, TX.PASS, r.detail)
        self.assertIn('waystone boss', r.detail)
        self.assertIn('rift guardian: 7 orbs', r.detail)

    def test_a_short_waystone_boss_is_a_bug(self):
        cases = {'pieces': ({'pieces': 1}, '1 gear piece'), 'rarity': ({'badRarity': 2}, 'below Legendary'),
                 'orb': ({'orbs': [{'name': 'Orb of Awakening', 'min': 2, 'count': 0}]}, 'Orb of Awakening x0'),
                 'waystone': ({'waystones': 0}, '0 waystone(s)'), 'paid': ({'paid': False}, 'paid nothing')}
        for label, (over, text) in cases.items():
            r = run(TX.check_content_rewards(self.io(loot=loot_answer(**over)), 'a', 'Ninja', 600))
            self.assertEqual(r.status, TX.FAIL, label)
            self.assertIn(text, r.detail, label)
            self.assertTrue(r.bug_line().startswith('BUG content_rewards: waystone boss:'), label)

    def test_a_short_rift_guardian_is_a_bug(self):
        r = run(TX.check_content_rewards(self.io(rift={'loot': {'paid': True, 'orbs': 2, 'minOrbs': 6}}), 'a', 'Ninja', 600))
        self.assertEqual(r.status, TX.FAIL)
        self.assertIn('rift guardian: 2 orb(s)', r.detail)
        r = run(TX.check_content_rewards(self.io(rift={'loot': {'paid': False, 'orbs': 9, 'minOrbs': 6}}), 'a', 'Ninja', 600))
        self.assertEqual(r.status, TX.FAIL)

    def test_a_level_30_bot_checks_the_waystone_half_only(self):
        r = run(TX.check_content_rewards(self.io(rift={'err': 'level too low for a rift'}), 'a', 'Ninja', 30))
        self.assertEqual(r.status, TX.PASS)
        self.assertIn('rift guardian not checked: level too low', r.detail)

    def test_nothing_checked_is_a_skip(self):
        r = run(TX.check_content_rewards(self.io(waystone_err='no waystone system', rift={'err': 'no rifts on this server'}),
                                         'a', 'Ninja', 30))
        self.assertEqual(r.status, TX.SKIP)
        self.assertEqual(run(TX.check_content_rewards(FakeIO(), 'a', 'Ninja', 30)).status, TX.SKIP)


class PartyXp(unittest.TestCase):
    def party(self, io, **over):
        """the helper's party answer: a pair of Tester bots, shared experience switched on after the 'share' packet"""
        on = ('share', 'Tester Bbb') in io.partied
        d = {'size': 2, 'leader': 'Tester Aaa', 'members': ['Tester Bbb'], 'shareActive': on, 'shareEnabled': on,
             'levels': [100, 90], 'minLevel': 67, 'lines': 2, 'bonusPct': 30, 'shareOf1000': 650, 'problems': []}
        d.update(over)
        return d

    def run_check(self, **over):
        io = FakeIO({'party': lambda io: self.party(io, **over)})
        return io, run(TX.check_party_xp(io, 'Tester Aaa', 'Ninja', 100))

    def test_the_share_is_what_the_rule_pays(self):
        self.assertEqual(TX.share_expected(2, 2), 650)       # ceil(1000 x 1.3 / 2)
        self.assertEqual(TX.share_expected(1, 3), 400)       # ceil(1000 x 1.2 / 3)
        self.assertEqual(TX.share_expected(5, 5), 500)       # x2.5 / 5
        self.assertEqual(TX.share_expected(7, 7), 358)       # seven lines count as five: ceil(2500 / 7)
        io, r = self.run_check()
        self.assertEqual(r.status, TX.PASS, r.detail)
        self.assertEqual(io.partied, [('form', 'Tester Bbb'), ('share', 'Tester Bbb'), ('unshare', 'Tester Bbb'), ('leave', 'Tester Bbb')])
        self.assertIn('1000 xp pays 650', r.detail)

    def test_a_wrong_share_is_a_bug(self):
        _, r = self.run_check(shareOf1000=500)
        self.assertEqual(r.status, TX.FAIL)
        self.assertIn('1000 experience pays 500', r.detail)
        self.assertTrue(r.bug_line().startswith('BUG party_xp:'))

    def test_the_switch_that_did_not_take(self):
        io = FakeIO({'party': lambda io: self.party(io, shareActive=False, shareEnabled=False,
                                                    problems=[{'name': 'Tester Bbb', 'kind': 'idle'}])})
        r = run(TX.check_party_xp(io, 'Tester Aaa', 'Ninja', 100))
        self.assertEqual(r.status, TX.FAIL)
        self.assertIn('says it is off', r.detail)

    def test_the_engine_verdict_must_follow_the_rules(self):
        # working while a member is far below the highest level
        _, r = self.run_check(problems=[{'name': 'Tester Bbb', 'kind': 'level'}], levels=[1000, 30], minLevel=667)
        self.assertEqual(r.status, TX.FAIL)
        self.assertIn('Tester Bbb is below two thirds', r.detail)
        _, r = self.run_check(problems=[{'name': 'Tester Bbb', 'kind': 'range'}])
        self.assertIn('is out of range', r.detail)
        # off with every rule passing
        _, r = self.run_check(shareEnabled=False)
        self.assertEqual(r.status, TX.FAIL)
        self.assertIn('every member passes', r.detail)

    def test_off_for_a_real_reason_is_a_pass(self):
        io = FakeIO({'party': lambda io: self.party(io, shareEnabled=False, problems=[{'name': 'Tester Bbb', 'kind': 'level'}],
                                                    shareOf1000=650)})
        r = run(TX.check_party_xp(io, 'Tester Aaa', 'Ninja', 100))
        self.assertEqual(r.status, TX.PASS, r.detail)
        self.assertIn('engine off: Tester Bbb level', r.detail)

    def test_a_verdict_seen_once_is_not_a_bug(self):
        calls = {'n': 0}

        def answer(io):
            calls['n'] += 1
            return self.party(io, shareEnabled=(calls['n'] != 3))   # the first look after the switch only
        r = run(TX.check_party_xp(FakeIO({'party': answer}), 'Tester Aaa', 'Ninja', 100))
        self.assertEqual(r.status, TX.PASS, r.detail)

    def test_skips(self):
        self.assertEqual(run(TX.check_party_xp(FakeIO(partner=None), 'Tester Aaa', 'Ninja', 100)).status, TX.SKIP)
        self.assertEqual(run(TX.check_party_xp(FakeIO(), 'Tester Aaa', 'Ninja', 100)).status, TX.SKIP)
        r = run(TX.check_party_xp(FakeIO({'party': {'size': 1}}), 'Tester Aaa', 'Ninja', 100))
        self.assertEqual(r.status, TX.SKIP)
        io = FakeIO({'party': {'size': 2, 'leader': 'Tester Bbb'}})
        self.assertIn('not the leader', run(TX.check_party_xp(io, 'Tester Aaa', 'Ninja', 100)).detail)
        io = FakeIO({'party': {'size': 2, 'leader': 'Tester Aaa'}})
        self.assertIn('old helper file', run(TX.check_party_xp(io, 'Tester Aaa', 'Ninja', 100)).detail)


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


class QuestIO(FakeIO):
    """a mocked helper for `!tester spellquest`: the rules of the game's quest 1 (400 kills, 20 fragments, pity 40, a boss = 25
    kills and a sure fragment, 2000 gold a level) as a small state machine; `faults` switch single rules off"""

    NEED = {'kills': 400, 'fragments': 20, 'level': 500}

    def __init__(self, level=600, spell='Keepfall', faults=(), odrenna=True, **kw):
        FakeIO.__init__(self, **kw)
        self.level, self.spell, self.faults, self.odrenna = level, spell, set(faults), odrenna
        self.q = {'step': 0, 'kills': 0, 'fragments': 0, 'pity': 0}
        self.known, self.near, self.running, self.cmds = False, False, False, []

    def state(self, **extra):
        code = 'ok' if self.level >= 500 else 'level'
        d = {'level': self.level, 'quest': 1, 'step': self.q['step'], 'code': code, 'kills': self.q['kills'],
             'fragments': self.q['fragments'], 'pity': self.q['pity'], 'need': dict(self.NEED), 'spell': self.spell,
             'learned': self.known}
        d.update(extra)
        return d

    def credit(self, boss):
        if self.q['step'] != 1 or self.level < 500 or 'nokill' in self.faults:
            return 0
        w = 25 if boss else 1
        self.q['kills'] = min(400, self.q['kills'] + w)
        if boss:
            self.q['fragments'] += 1
        elif self.q['pity'] + 1 > 40 and 'nopity' not in self.faults:
            self.q['fragments'], self.q['pity'] = self.q['fragments'] + 1, 0
        else:
            self.q['pity'] += 1
        return w

    async def go(self, place):
        self.moves.append(place)
        self.near = False
        return True

    async def helper(self, command, kind, wait=4.0):
        self.cmds.append(command)
        if command == 'enter npc Archivist Odrenna':
            if not self.odrenna:
                return {'kind': 'npc', 'err': 'no such NPC', 'name': 'Archivist Odrenna'}
            self.near = True
            return {'kind': 'npc', 'npc': 'Archivist Odrenna'}
        if not command.startswith('spellquest'):
            return await FakeIO.helper(self, command, kind, wait)
        sub = command.split()[1:]
        if not sub or sub[0] == 'state':
            return self.state()
        if sub[0] == 'reset':
            self.q, self.known, self.running = {'step': 0, 'kills': 0, 'fragments': 0, 'pity': 0}, False, False
            return self.state()
        if sub[0] == 'set':
            step = int(sub[2])
            self.q = {'step': step, 'kills': 400 if step >= 2 else 0, 'fragments': 20 if step >= 2 else 0, 'pity': 0}
            return self.state()
        if sub[0] == 'kill':
            boss = sub[-1] == 'boss'
            n = 1 if len(sub) == 1 or sub[1] == 'boss' else int(sub[1])
            weight = sum(self.credit(boss) for _ in range(n))
            return self.state(counted=n if weight else 0, weight=weight)
        if sub[0] == 'trial':
            ok = self.near and self.q['step'] == 2 and 'notrial' not in self.faults
            self.running = ok
            return self.state(entered=ok, running=ok, near=self.near, text='' if ok else 'The trial is entered at Archivist Odrenna.')
        if sub[0] == 'leave':
            was, self.running = self.running, False
            return self.state(left=was, running=self.running)
        if sub[0] == 'complete':
            if self.q['step'] != 2:
                return self.state(err='the quest is not on its trial step')
            self.q['step'], self.known = 3, 'noteach' not in self.faults
            return self.state(completed=1, taught=self.spell, taughtKnown=self.known, gold=0 if 'nogold' in self.faults else 2000 * self.level)
        return {'err': 'unknown spellquest command'}


def quest_table(voc=4):
    return {'Warrior': {'voc': voc, 'presets': [{'level': 500, 'spells': [142, 225]}], 'extras': [], 'ultimate': 148}}


KEEPFALL = {142: {'name': 'Keepfall', 'level': 500, 'vocations': [4, 8, 14]}}


class SpellQuest(unittest.TestCase):
    def go(self, io, cls='Warrior', level=600):
        return run(TX.check_spell_quest(io, 'Tester Aaa', cls, level))

    def test_the_whole_quest_passes(self):
        io = QuestIO(table=quest_table(), spells=KEEPFALL)
        r = self.go(io)
        self.assertEqual(r.status, TX.PASS, r.detail)
        self.assertIn('Keepfall learned', r.detail)
        self.assertIn('in the Auto setup data', r.detail)
        self.assertEqual(io.cmds[0], 'spellquest reset')
        self.assertEqual(io.cmds[-1], 'spellquest reset', 'the quest is reset at the end')
        self.assertIn('enter npc Archivist Odrenna', io.cmds)
        self.assertEqual(io.moves, ['hunt'], 'back to the hunt spot')
        self.assertFalse(io.known)

    def test_low_level_is_a_skip(self):
        io = QuestIO(level=499)
        self.assertEqual(self.go(io, level=499).status, TX.SKIP)
        self.assertEqual(io.cmds, [])
        # the game says the level is lower now (a death): skip, and the quest is reset
        io = QuestIO(level=480)
        r = self.go(io, level=600)
        self.assertEqual(r.status, TX.SKIP)
        self.assertIn('bot is level 480 now', r.detail)

    def test_no_system_no_answer_no_line(self):
        self.assertEqual(self.go(FakeIO()).status, TX.SKIP)
        self.assertEqual(self.go(FakeIO({'spellquest reset': {'err': 'no spell quest system'}})).status, TX.SKIP)
        self.assertEqual(self.go(FakeIO({'spellquest reset': {'err': 'no class line', 'code': 'noline'}})).status, TX.SKIP)

    def test_kills_that_do_not_count(self):
        r = self.go(QuestIO(faults=['nokill']))
        self.assertEqual(r.status, TX.FAIL)
        self.assertTrue(r.bug_line().startswith('BUG spell_quest: kills do not count'))

    def test_no_fragment_from_the_pity(self):
        r = self.go(QuestIO(faults=['nopity']))
        self.assertEqual(r.status, TX.FAIL)
        self.assertIn('no fragment within 41 counted kills', r.detail)

    def test_odrenna_missing_from_the_world(self):
        io = QuestIO(odrenna=False)
        r = self.go(io)
        self.assertEqual(r.status, TX.FAIL)
        self.assertIn('Archivist Odrenna is not in the game', r.detail)
        self.assertEqual(io.cmds[-1], 'spellquest reset')
        self.assertEqual(self.go(FakeIO({'spellquest reset': {'level': 600, 'quest': 1, 'step': 0, 'code': 'ok', 'spell': 'Keepfall',
                                                              'need': QuestIO.NEED}, 'spellquest state': {
            'level': 600, 'quest': 1, 'step': 0, 'code': 'ok', 'spell': 'Keepfall', 'need': QuestIO.NEED}, 'spellquest set 1 1 0 0': {
            'step': 1, 'kills': 0, 'fragments': 0}, 'spellquest kill 3': {'counted': 3, 'kills': 3}, 'spellquest kill 45': {
            'counted': 45, 'kills': 48, 'fragments': 2}, 'spellquest kill boss': {'weight': 25, 'kills': 73},
            'spellquest set 1 2': {'step': 2, 'kills': 400, 'fragments': 20}})).status, TX.SKIP,
            'no answer to the NPC walk is a skip, not a bug')

    def test_trial_that_does_not_open(self):
        r = self.go(QuestIO(faults=['notrial']))
        self.assertEqual(r.status, TX.FAIL)
        self.assertIn('the trial does not open at Odrenna', r.detail)

    def test_reward_rules(self):
        self.assertIn('the reward', self.go(QuestIO(faults=['noteach'])).detail)
        r = self.go(QuestIO(faults=['nogold']))
        self.assertEqual(r.status, TX.FAIL)
        self.assertIn('gold', r.detail)

    def test_spell_data(self):
        # the spell is not on the server, not open to the class, gated too high, missing from Auto setup
        r = self.go(QuestIO(table=quest_table(), spells={1: {'name': 'Other', 'level': 1, 'vocations': []}}))
        self.assertEqual((r.status, 'not in the server\'s spell list' in r.detail), (TX.FAIL, True))
        r = self.go(QuestIO(table=quest_table(), spells={142: {'name': 'Keepfall', 'level': 500, 'vocations': [5]}}))
        self.assertIn('is not open to Warrior', r.detail)
        r = self.go(QuestIO(table=quest_table(), spells={142: {'name': 'Keepfall', 'level': 900, 'vocations': [4]}}))
        self.assertIn('needs level 900', r.detail)
        table = quest_table()
        table['Warrior']['presets'] = [{'level': 500, 'spells': [225]}]
        table['Warrior']['ultimate'] = None
        r = self.go(QuestIO(table=table, spells=KEEPFALL))
        self.assertIn('no preset or extras of the Auto setup', r.detail)
        table['Warrior']['extras'] = [142]
        self.assertEqual(self.go(QuestIO(table=table, spells=KEEPFALL)).status, TX.PASS, 'extras count')
        # nothing to compare with: the flow still passes
        self.assertEqual(self.go(QuestIO()).status, TX.PASS)

    def test_the_real_first_spell_of_every_class_is_in_the_auto_setup_data(self):
        table = TX.load_table(os.path.join(MODULES, 'game_helperrotation', 'autorotation_data.lua'))
        with open(os.path.join(MODULES, 'game_chaosspells', 'spelldata.lua'), encoding='utf-8') as f:
            text = f.read()
        quest1 = [(m.group(2), int(m.group(1))) for m in re.finditer(r'\{ id = (\d+), name = "([^"]+)"[^\n]*? quest = 1 \}', text)]
        self.assertEqual(len(quest1), 7, 'one level 500 quest spell per line')
        spells = client_spells()
        for cls, row in table.items():
            mine = [n for n, sid in quest1 if row['voc'] in spells[sid]['vocations']]
            self.assertEqual(len(mine), 1, '%s: exactly one quest 1 spell, got %s' % (cls, mine))
            self.assertEqual(TX.quest_spell_problems(mine[0], cls, 500, spells, table), [], cls)

    def test_load_table_reads_extras_and_the_ultimate(self):
        table = TX.load_table(os.path.join(MODULES, 'game_helperrotation', 'autorotation_data.lua'))
        self.assertTrue(all(row.get('ultimate') for row in table.values()), 'every class lists its ultimate')
        self.assertTrue(any(row['extras'] for row in table.values()), 'some class has extras')


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
