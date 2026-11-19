#!/usr/bin/env python3
"""python3 -I server/tools/tester_checks_test.py: the system checks of the tester bots (tester_checks.py) against a mocked
server. Every check has a passing run, a failing run that prints a BUG line, and a skip; the Auto setup rows are checked
against the real client data (every class, every preset)."""
import asyncio
import copy
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

    async def partner(self, min_level=0):
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


LIVE = {'live': 'fox', 'cid': 100}  # !tester pet: the live pet's creature id (the first row of summons() has id 100)


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
                  'rift_layout', 'waystone_run', 'content_rewards', 'party_xp', 'unique_passive', 'dual_fists', 'dual_blades'):
            self.assertIn(k, keys('Ninja'))


class UniquePassive(unittest.TestCase):
    def answer(self, **over):
        d = {'id': 26185, 'family': 'critrule', 'line': 'monk', 'slot': 9, 'active': ['critrule'], 'm': 0.92,
             'crit': False, 'lostBefore': 1000, 'lostAfter': 920, 'hit': 820}
        d.update(over)
        return d

    def check(self, **over):
        return run(TX.check_unique_passive(FakeIO({'unique': self.answer(**over)}), 'Tester Aaa', 'Monk', 600))

    def test_the_hit_follows_the_rule(self):
        r = self.check()
        self.assertEqual(r.status, TX.PASS, r.detail)
        self.assertIn('critrule (item 26185, monk line): hit 1000 -> 920, rule x0.920', r.detail)
        self.assertEqual(self.check(lostAfter=935).status, TX.PASS, 'within 3%')

    def test_a_hit_off_the_rule_is_a_bug(self):
        r = self.check(lostAfter=1000)
        self.assertEqual(r.status, TX.FAIL)
        self.assertIn('took x1.000 of the health, its rule says x0.920', r.detail)

    def test_a_sleeping_passive_is_a_bug(self):
        r = self.check(active=[])
        self.assertEqual(r.status, TX.FAIL)
        self.assertIn('leaves its passive asleep (active: none)', r.detail)
        r = self.check(m=None)
        self.assertIn('never reached', r.detail)

    def test_skips(self):
        self.assertEqual(run(TX.check_unique_passive(FakeIO(), 'a', 'Monk', 600)).status, TX.SKIP)
        r = self.check(err='no free slot for a unique of the monk line')
        self.assertEqual(r.status, TX.SKIP)
        self.assertEqual(self.check(lostBefore=0).status, TX.SKIP)


class DualFists(unittest.TestCase):
    def check(self, cls='Monk', **f):
        return run(TX.check_dual_fists(FakeIO({'fists': f}), 'Tester Aaa', cls, 600))

    def test_a_monk_strikes_with_the_off_hand(self):
        r = self.check(able=True, left=0, right=0, melee=3, off=3, meleeSum=3000, offSum=1400)
        self.assertEqual(r.status, TX.PASS, r.detail)
        self.assertIn('3 melee hits, 3 off-hand strikes (1400 damage)', r.detail)
        self.assertEqual(self.check(able=True, left=0, right=0, melee=3, off=2).status,
                         TX.PASS, 'the last strike may land after the watch')

    def test_bugs(self):
        r = self.check(able=True, left=0, right=6, melee=0, off=0)
        self.assertEqual(r.status, TX.FAIL)
        self.assertIn('shield hand code 6', r.detail)
        self.assertIn('no off-hand strike', self.check(able=True, left=0, right=0, melee=4, off=0).detail)
        self.assertIn('one each', self.check(able=True, left=0, right=0, melee=4, off=8).detail)
        r = self.check(cls='Warrior', able=False, left=0)
        self.assertEqual(r.status, TX.FAIL)
        self.assertIn('outside the Monk line could wear', r.detail)

    def test_other_class_refused_and_skips(self):
        self.assertEqual(self.check(cls='Warrior', able=False, left=6).status, TX.PASS)
        self.assertEqual(run(TX.check_dual_fists(FakeIO(), 'a', 'Monk', 600)).status, TX.SKIP)
        self.assertEqual(self.check(able=False, err='could not empty the hands').status, TX.SKIP)
        self.assertEqual(self.check(able=True, left=0, right=0, melee=0, off=0).status, TX.SKIP)


class DualBlades(unittest.TestCase):
    def check(self, cls='Thief', **f):
        return run(TX.check_dual_blades(FakeIO({'blades': f}), 'Tester Aaa', cls, 600))

    def test_strikes_the_rules_hold_back_are_no_bug(self):
        # live run 2026-11-15 (O580): 14 melee hits, 11 strikes, Tester Aah. The strike follows after 150 ms, the attack rate
        # gate (1.5 a second) refuses some and a hit under a few points rounds its strike to 0: the helper counts both
        self.assertEqual(self.check(able=True, left=0, right=0, melee=14, off=11, gated=2, small=0).status, TX.PASS)
        self.assertEqual(self.check(able=True, left=0, right=0, melee=14, off=11, gated=0, small=2).status, TX.PASS)
        self.assertEqual(self.check(able=True, left=0, right=0, melee=14, off=11, gated=1, small=1).status, TX.PASS)
        # not explained by what the helper counted: still a bug, with the numbers in the text
        r = self.check(able=True, left=0, right=0, melee=14, off=11, gated=1, small=0)
        self.assertEqual(r.status, TX.FAIL)
        self.assertIn('14 melee hits but 11 off-hand strikes (one each; 1 refused by the attack rate gate, 0 hits too small)',
                      r.detail)
        self.assertEqual(self.check(able=True, left=0, right=0, melee=14, off=11).status, TX.FAIL, 'old helper: strict')
        self.assertEqual(self.check(able=True, left=0, right=0, melee=4, off=0, gated=1, small=1).status, TX.FAIL,
                         'no strike at all with only two excused hits')
        self.assertEqual(self.check(able=True, left=0, right=0, melee=4, off=5, gated=3).status, TX.FAIL,
                         'more strikes than hits is never excused')

    def test_a_thief_strikes_with_the_off_hand(self):
        r = self.check(able=True, left=0, right=0, melee=4, off=4, offSum=900)
        self.assertEqual(r.status, TX.PASS, r.detail)
        self.assertIn('4 melee hits, 4 off-hand strikes (900 damage)', r.detail)

    def test_bugs(self):
        self.assertIn('could not wear a dagger in each hand',
                      self.check(able=True, left=0, right=14).detail)
        self.assertIn('no off-hand strike', self.check(cls='Ninja', able=True, left=0, right=0, melee=3, off=0).detail)
        r = self.check(cls='Samurai', able=False, left=0, right=0)
        self.assertEqual(r.status, TX.FAIL)
        self.assertIn('does not dual wield could hold a dagger in the shield hand', r.detail)

    def test_others_refused(self):
        r = self.check(cls='Samurai', able=False, left=0, right=14)
        self.assertEqual(r.status, TX.PASS, r.detail)
        self.assertIn('refused in the shield hand (code 14)', r.detail)
        self.assertEqual(self.check(cls='Mystic', able=False, left=14, right=14).status, TX.PASS)


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

    def test_a_pet_of_the_helper_when_none_is_owned(self):
        io = FakeIO({'pet': {'key': 'ember_whelp', 'owns': True}, 'summons': summons()},
                    replies={('pets', 'get'): {'action': 'state', 'data': {'pets': []}}})
        r = run(TX.check_pets(io, 'Tester Aaa', 'Ninja', 100))
        self.assertNotIn('owns no pet', r.detail)
        self.assertIn(('pets', 'summon', {'species': 'ember_whelp'}), io.asked)

    def test_pet_out_and_dismissed(self):
        state = {'action': 'state', 'data': {'pets': [{'species': 'fox'}]}}
        out = summons({'name': 'fox', 'target': 'monster'})

        def answer(io):
            return out if not any(a[1] == 'dismiss' for a in io.asked) else summons()

        io = FakeIO({'summons': answer, 'pet': LIVE}, {('pets', 'get'): state})
        r = run(TX.check_pets(io, 'Tester Aaa', 'Ninja', 100))
        self.assertEqual(r.status, TX.PASS, r.detail)
        self.assertEqual([a[1] for a in io.asked], ['get', 'summon', 'dismiss'])
        self.assertEqual(io.asked[1][2], {'species': 'fox'})

    def test_pet_that_attacks_the_owner_or_stays_out(self):
        state = {'action': 'state', 'data': {'pets': [{'key': 'fox'}]}}
        io = FakeIO({'summons': summons({'name': 'fox', 'target': 'owner'}), 'pet': LIVE}, {('pets', 'get'): state})
        self.assertEqual(run(TX.check_pets(io, 'Tester Aaa', 'Ninja', 100)).status, TX.FAIL)
        io = FakeIO({'summons': summons({'name': 'fox', 'target': 'monster'}), 'pet': LIVE}, {('pets', 'get'): state})
        r = run(TX.check_pets(io, 'Tester Aaa', 'Ninja', 100))
        self.assertEqual((r.status, r.detail), (TX.FAIL, 'the pet is still out after dismiss'))

    def test_minions_that_stay_are_not_the_pet(self):
        # live run 2026-11-01: a Lich's minions stayed after the pet's dismiss and read as the pet (the first summon)
        state = {'action': 'state', 'data': {'pets': [{'key': 'fox'}]}}
        minion = {'name': 'skeleton', 'id': 900, 'target': 'monster'}

        def answer(io):
            pet = {'name': 'fox', 'id': 100, 'target': 'monster'}
            return summons(minion, pet) if not any(a[1] == 'dismiss' for a in io.asked) else summons(minion)

        io = FakeIO({'summons': answer, 'pet': LIVE}, {('pets', 'get'): state})
        r = run(TX.check_pets(io, 'Tester Aaa', 'Lich', 300))
        self.assertEqual(r.status, TX.PASS, r.detail)

    def test_a_pet_that_rests_or_waits_is_a_skip_with_the_rule(self):
        state = {'action': 'state', 'data': {'pets': [{'key': 'fox'}]}}
        for live, text in (({'live': 'fox', 'rest': 'summons'}, 'the bot has other summons'),
                           ({'live': 'fox', 'rest': 'pz'}, 'a protection zone'),
                           ({'deathLeft': 40}, 'death cooldown 40 s'),
                           ({'summonLeft': 9}, 'call cooldown 9 s'),
                           ({'live': 'fox'}, 'no rule of the game says why'),
                           (None, 'no answer to !tester pet')):
            io = FakeIO({'summons': summons(), 'pet': live}, {('pets', 'get'): state})
            r = run(TX.check_pets(io, 'Tester Aaa', 'Ninja', 100))
            self.assertEqual(r.status, TX.SKIP)
            self.assertIn(text, r.detail)

    def test_a_pet_that_is_out_but_no_summon_fails(self):
        state = {'action': 'state', 'data': {'pets': [{'key': 'fox'}]}}
        io = FakeIO({'summons': summons(), 'pet': LIVE}, {('pets', 'get'): state})
        r = run(TX.check_pets(io, 'Tester Aaa', 'Ninja', 100))
        self.assertEqual(r.status, TX.FAIL)
        self.assertIn('not a summon of the bot', r.detail)


class Party(unittest.TestCase):
    def test_a_partner_that_died_is_a_skip_not_a_bug(self):
        # live run 2026-11-01 at level 1600: bots died every few seconds, "joined, the party has 0 member(s)"
        io = FakeIO({'party': {'size': 0}})
        io.partner_kept = lambda other: False
        r = run(TX.check_party(io, 'Tester Aaa', 'Ninja', 100))
        self.assertEqual(r.status, TX.SKIP, r.detail)
        self.assertIn('died or logged in again', r.detail)
        io = FakeIO({'party': {'size': 0}})
        io.partner_kept = lambda other: True
        self.assertEqual(run(TX.check_party(io, 'Tester Aaa', 'Ninja', 100)).status, TX.FAIL)

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
        io = FakeIO({'enter rift 1': {'pos': {}, 'tier': 1, 'held': True}})
        self.assertEqual(run(TX.check_rift(io, 'Tester Aaa', 'Ninja', 100)).status, TX.PASS)
        io = FakeIO({'enter rift 1': {'pos': {}, 'tier': 1, 'held': False}})
        self.assertEqual(run(TX.check_rift(io, 'Tester Aaa', 'Ninja', 100)).status, TX.FAIL)
        # live run 2026-11-01: a full bag put the key on the ground; the helper finds it there, no bug
        io = FakeIO({'enter rift 1': {'pos': {}, 'tier': 1, 'held': False, 'bagFull': True}})
        r = run(TX.check_rift(io, 'Tester Aaa', 'Ninja', 100))
        self.assertEqual(r.status, TX.SKIP)
        self.assertIn('bag is full', r.detail)
        io = FakeIO({'enter rift 1': {'pos': {}}})
        self.assertEqual(run(TX.check_rift(io, 'Tester Aaa', 'Ninja', 100)).status, TX.SKIP)
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
        # no tile for the chest near the bot: the helper says why, the check is a skip (it read state "none" and failed before)
        io = FakeIO({'chest spawn': {'err': 'no tile for a chest near the tester (the game\'s own rule)'}})
        r = run(TX.check_cursed_chest(io, 'a', 'Ninja', 100))
        self.assertEqual(r.status, TX.SKIP)
        self.assertIn('no tile for a chest', r.detail)

    def test_cursed_chest_no_answer_to_use_is_a_skip(self):
        # live run 2026-11-15: "after use the chest is None": the answer to `chest use` never came (a busy server)
        seen = []

        class NoUse(FakeIO):
            async def helper(self, command, kind, wait=4.0):
                seen.append(command)
                if command == 'chest use':
                    return None
                return {'state': 'idle', 'left': 1, 'monsters': 0}

        r = run(TX.check_cursed_chest(NoUse(), 'Tester Aaa', 'Mystic', 100))
        self.assertEqual(r.status, TX.SKIP, r.detail)
        self.assertIn('no answer to !tester chest use', r.detail)
        self.assertEqual(seen[-1], 'chest abort', 'the chest is taken away again')

    def test_cursed_chest_horde_counts(self):
        def io_with(running):
            class HordeIO(FakeIO):
                async def helper(self, command, kind, wait=4.0):
                    if command == 'chest spawn':
                        return {'state': 'idle', 'left': 1}
                    if command in ('chest use', 'chest state') and not getattr(self, 'aborted', False):
                        return dict({'state': 'running', 'left': 1}, **running)
                    self.aborted = True
                    return {'state': 'none', 'left': 0}
            return HordeIO()
        # a horde the bots killed at once: no monster left, but some were made
        r = run(TX.check_cursed_chest(io_with({'monsters': 0, 'horde': 1, 'made': 6}), 'a', 'Ninja', 100))
        self.assertEqual(r.status, TX.PASS, r.detail)
        r = run(TX.check_cursed_chest(io_with({'monsters': 0, 'horde': 1, 'made': 0}), 'a', 'Ninja', 100))
        self.assertEqual(r.status, TX.FAIL)
        self.assertIn('horde 1 came with no monster', r.detail)
        # before the first horde (2.5 s after the use) nothing is due yet
        r = run(TX.check_cursed_chest(io_with({'monsters': 0, 'horde': 0}), 'a', 'Ninja', 100))
        self.assertEqual(r.status, TX.PASS, r.detail)


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

    def test_another_band_only_fails_when_one_of_the_tier_was_ready(self):
        self.assertEqual(self.check(band=2, readyOfBand=1).status, TX.FAIL)
        self.assertEqual(self.check(band=2).status, TX.FAIL)   # an old helper: no count, the strict rule
        self.assertEqual(self.check(band=2, readyOfBand=0).status, TX.PASS)   # a full pool hands out another band

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
        # the switch in the temple (the engine refuses it in a fight outside a protection zone), back to the hunt after
        self.assertEqual(io.moves, ['town', 'hunt', 'hunt'])
        self.assertIn('no answer to !tester party kill', r.detail)

    def test_a_switch_the_engine_refuses_in_a_fight_is_a_skip(self):
        _, r = self.run_check(shareActive=False, leaderBlocked=True, leaderPz=False)
        self.assertEqual(r.status, TX.SKIP, r.detail)
        self.assertIn('in a fight outside a protection zone', r.detail)
        io, r = self.run_check(shareActive=False, leaderBlocked=False, leaderPz=True)
        self.assertEqual(r.status, TX.FAIL, r.detail)
        self.assertEqual([a for a in io.partied if a[0] == 'share'], [('share', 'Tester Bbb')] * 2, 'one more switch, then a bug')

    def test_a_party_that_broke_up_before_the_switch_is_a_skip(self):
        # O580 (live run 2026-11-15, Tester Acu, Lich): the party had two members when the check began and none when the
        # switch was read (a join or a leave of a bot): the engine drops the switch of a leader with no party
        calls = []

        def answer(io):
            calls.append(1)
            if len(calls) == 1:
                return self.party(io)
            return {'size': 0, 'members': []}
        r = run(TX.check_party_xp(FakeIO({'party': answer}), 'Tester Aaa', 'Lich', 100))
        self.assertEqual(r.status, TX.SKIP, r.detail)
        self.assertIn('the party broke up before the switch could be read (party of 0, leader None', r.detail)
        # the leader changed: also no verdict on this bot's switch
        calls.clear()

        def other_leader(io):
            calls.append(1)
            return self.party(io) if len(calls) == 1 else self.party(io, leader='Tester Bbb', shareActive=False)
        r = run(TX.check_party_xp(FakeIO({'party': other_leader}), 'Tester Aaa', 'Lich', 100))
        self.assertEqual(r.status, TX.SKIP, r.detail)

    def test_a_refused_switch_names_the_party_in_the_failure(self):
        _, r = self.run_check(shareActive=False, leaderBlocked=False, leaderPz=True)
        self.assertEqual(r.status, TX.FAIL)
        self.assertIn('(party of 2, leader Tester Aaa, leader in a fight outside a protection zone: False, '
                      'in a protection zone: True)', r.detail)

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
        # off with every rule the helper sees passing: the engine's own activity ticks decide, no failure
        _, r = self.run_check(shareEnabled=False)
        self.assertEqual(r.status, TX.PASS, r.detail)

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

    def kill(self, shared=None, solo=None, **over):
        k = {'monster': 'Demon', 'shared': {'leader': 6500, 'partner': 6400, 'active': True, 'enabled': True, 'dead': True},
             'solo': {'leader': 10000, 'partner': 0, 'dead': True}}
        k['shared'].update(shared or {})
        k['solo'].update(solo or {})
        k.update(over)
        return k

    def test_a_real_shared_kill_pays_what_the_share_rule_says(self):
        self.assertEqual(TX.shared_kill_problems(self.kill(), 650), (None, []))
        self.assertEqual(TX.shared_kill_problems(self.kill(shared={'leader': 6700}), 650)[1], [], 'within 5%')
        skip, bad = TX.shared_kill_problems(self.kill(shared={'leader': 10000}), 650)
        self.assertIn('the leader got 100% of a solo kill', bad[0])
        _, bad = TX.shared_kill_problems(self.kill(shared={'partner': 0}), 650)
        self.assertIn('paid the partner nothing', bad[0])
        _, bad = TX.shared_kill_problems(self.kill(solo={'partner': 40}), 650)
        self.assertIn('solo kill of the leader paid the partner 40', bad[0])

    def test_a_kill_with_the_share_off_pays_the_leader_alone(self):
        self.assertEqual(TX.shared_kill_problems(self.kill(shared={'enabled': False, 'leader': 10000, 'partner': 0}), 650),
                         (None, []))
        _, bad = TX.shared_kill_problems(self.kill(shared={'enabled': False, 'partner': 26, 'partnerHit': True}), 650)
        self.assertEqual(bad, [])
        _, bad = TX.shared_kill_problems(self.kill(shared={'enabled': False, 'partner': 5}), 650)
        self.assertIn('kill with the share not working', bad[0])

    def test_a_kill_that_did_not_run_is_a_skip_not_a_bug(self):
        for k, text in ((None, 'no answer'), ({'err': 'not the leader of a party of 2'}, 'not the leader'),
                        (self.kill(solo={'dead': False}), 'did not die'), (self.kill(solo={'leader': 0}), 'paid the leader nothing'),
                        (self.kill(shared={'err': 'no free tile next to the leader'}), 'no free tile')):
            skip, bad = TX.shared_kill_problems(k, 650)
            self.assertIn(text, skip)
            self.assertEqual(bad, [])

    def test_the_check_runs_the_kill_at_the_hunt(self):
        io = FakeIO({'party': lambda io: self.party(io), 'party kill': self.kill()})
        r = run(TX.check_party_xp(io, 'Tester Aaa', 'Ninja', 100))
        self.assertEqual(r.status, TX.PASS, r.detail)
        self.assertIn('kill shared: leader 6500 / partner 6400 xp (share working), solo 10000', r.detail)
        io = FakeIO({'party': lambda io: self.party(io), 'party kill': self.kill(shared={'partner': 0})})
        r = run(TX.check_party_xp(io, 'Tester Aaa', 'Ninja', 100))
        self.assertEqual(r.status, TX.FAIL, r.detail)
        self.assertIn('paid the partner nothing', r.detail)

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
        self.n = 1   # the open quest: the next one after a completion (500, 800, 1200)
        self.spells_of = [spell, spell + ' II', spell + ' III']

    def state(self, **extra):
        code = 'ok' if self.level >= TX.QUEST_LEVELS[self.n - 1] else 'level'
        d = {'level': self.level, 'quest': self.n, 'step': self.q['step'], 'code': code, 'kills': self.q['kills'],
             'fragments': self.q['fragments'], 'pity': self.q['pity'], 'need': dict(self.NEED),
             'spell': self.spells_of[self.n - 1], 'learned': self.known}
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
        if command == 'path npc Archivist Odrenna':   # O589: a person walks to her first
            if self.odrenna and getattr(self, 'walkable', False):
                self.near = True
                return {'here': True, 'name': 'Archivist Odrenna', 'pos': {'x': 5, 'y': 5, 'z': 7}, 'dest': {'x': 6, 'y': 5, 'z': 7}}
            return {'err': 'no path', 'name': 'Archivist Odrenna'}
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
            self.n = 1
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
            done, spell = self.n, self.spells_of[self.n - 1]
            if self.n < 3:
                self.n, self.q = self.n + 1, {'step': 0, 'kills': 0, 'fragments': 0, 'pity': 0}
            return self.state(completed=done, taught=spell, taughtKnown=self.known, gold=0 if 'nogold' in self.faults else 2000 * self.level)
        return {'err': 'unknown spellquest command'}


def quest_table(voc=4):
    return {'Warrior': {'voc': voc, 'presets': [{'level': 500, 'spells': [142, 225]}], 'extras': [], 'ultimate': 148}}


KEEPFALL = {142: {'name': 'Keepfall', 'level': 500, 'vocations': [4, 8, 14]}}


class SpellQuest(unittest.TestCase):
    def test_every_quest_the_level_opens(self):
        # O302: the quests at 800 and 1200 ran in no live check before; a level 1300 bot does all three in order
        io = QuestIO(level=1300)
        r = run(TX.check_spell_quest(io, 'Tester Aaa', 'Warrior', 1300))
        self.assertEqual(r.status, TX.PASS, r.detail)
        for text in ('Keepfall learned', 'quest 2 (level 800): Keepfall II learned', 'quest 3 (level 1200): Keepfall III learned'):
            self.assertIn(text, r.detail)
        self.assertNotIn('not reached', r.detail)
        r = run(TX.check_spell_quest(QuestIO(level=900), 'Tester Aaa', 'Warrior', 900))
        self.assertEqual(r.status, TX.PASS, r.detail)
        self.assertIn('quest 2 (level 800)', r.detail)
        self.assertIn('quests at level 1200 not reached (level 900)', r.detail)
        r = run(TX.check_spell_quest(QuestIO(level=900, faults={'nogold'}), 'Tester Aaa', 'Warrior', 900))
        self.assertEqual(r.status, TX.FAIL)
        self.assertIn('quest 1: the reward', r.detail)

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

    def test_the_bot_walks_to_odrenna_and_the_teleport_is_only_the_counted_fallback(self):
        io = QuestIO(table=quest_table(), spells=KEEPFALL)
        io.walkable = True
        r = self.go(io)
        self.assertEqual(r.status, TX.PASS, r.detail)
        self.assertIn('path npc Archivist Odrenna', io.cmds)
        self.assertNotIn('enter npc Archivist Odrenna', io.cmds, 'on foot: no teleport')
        self.assertEqual(r.fallbacks, [])
        io = QuestIO(table=quest_table(), spells=KEEPFALL)      # no path to her: the helper's teleport, named and counted
        r = self.go(io)
        self.assertEqual(r.status, TX.PASS, r.detail)
        self.assertLess(io.cmds.index('path npc Archivist Odrenna'), io.cmds.index('enter npc Archivist Odrenna'))
        self.assertEqual(r.fallbacks, ['enter npc Archivist Odrenna (no path)'])
        self.assertEqual(r.as_dict()['fallbacks'], ['enter npc Archivist Odrenna (no path)'])
        r = run(TX.check_spell_quest(QuestIO(level=1300), 'Tester Aaa', 'Warrior', 1300))
        self.assertEqual(r.status, TX.PASS, r.detail)
        self.assertEqual(len(r.fallbacks), 3, 'one teleport per quest of a level 1300 bot')
        io = QuestIO(faults=['nokill'])
        io.walkable = True
        self.assertEqual(self.go(io).fallbacks, [], 'a failed quest keeps the fallbacks it had (none)')

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
        self.assertTrue(r.bug_line().startswith('BUG spell_quest: quest 1: kills do not count'))

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

    def test_a_missing_answer_is_a_skip_not_a_bug(self):
        # live run 2026-11-15: 33 of 60 spell quest checks failed "no answer to !tester spellquest ..." (a busy server answered
        # about 4 % of the commands late or not at all; 25 commands a check): not a fault of the quest
        for dropped in ('state', 'set 1 1 0 0', 'kill 3', 'kill 45', 'kill boss', 'set 1 2', 'trial', 'leave', 'complete'):
            class Dropping(QuestIO):
                async def helper(self, command, kind, wait=4.0):
                    if command == 'spellquest ' + dropped:
                        self.cmds.append(command)
                        return None
                    return await QuestIO.helper(self, command, kind, wait)

            io = Dropping(table=quest_table(), spells=KEEPFALL)
            r = self.go(io)
            self.assertEqual(r.status, TX.SKIP, '%s: %s' % (dropped, r.detail))
            self.assertIn('no answer to !tester spellquest %s' % dropped, r.detail)
            self.assertIn('no fault of the quest', r.detail)
            self.assertEqual(io.cmds[-1], 'spellquest reset', 'the quest is reset after it')

    def test_the_helper_error_is_a_bug_not_a_skip(self):
        class Erring(QuestIO):
            async def helper(self, command, kind, wait=4.0):
                if command == 'spellquest kill 3':
                    return {'err': 'data/scripts/chaos/spellquest.lua:1: boom', 'cmd': 'spellquest'}
                return await QuestIO.helper(self, command, kind, wait)

        r = self.go(Erring(table=quest_table(), spells=KEEPFALL))
        self.assertEqual(r.status, TX.FAIL)
        self.assertIn('boom', r.detail)

    def test_the_quest_waits_longer_for_each_answer(self):
        waits = []

        class Waits(QuestIO):
            async def helper(self, command, kind, wait=4.0):
                if command.startswith('spellquest'):
                    waits.append(wait)
                return await QuestIO.helper(self, command, kind, wait)

        self.go(Waits(table=quest_table(), spells=KEEPFALL))
        self.assertTrue(waits and min(waits) >= TX.QUEST_WAIT > TX.ANSWER, waits)

    def test_a_crowd_round_odrenna_is_asked_again_then_a_skip(self):
        # live run 2026-11-15: "Archivist Odrenna is not in the game (no free tile)": she stood there, the testers stood round her
        class Crowd(QuestIO):
            def __init__(self, full, **kw):
                QuestIO.__init__(self, **kw)
                self.full = full

            async def helper(self, command, kind, wait=4.0):
                if command == 'enter npc Archivist Odrenna':
                    self.cmds.append(command)
                    self.full -= 1
                    if self.full >= 0:
                        return {'kind': 'npc', 'err': 'no free tile', 'name': 'Archivist Odrenna', 'crowd': True}
                    self.near = True
                    return {'kind': 'npc', 'npc': 'Archivist Odrenna'}
                return await QuestIO.helper(self, command, kind, wait)

        io = Crowd(2, table=quest_table(), spells=KEEPFALL)
        r = self.go(io)
        self.assertEqual(r.status, TX.PASS, r.detail)
        self.assertEqual(io.cmds.count('enter npc Archivist Odrenna'), 3, 'asked again after each crowded answer')
        self.assertGreaterEqual(io.t, 2 * TX.CROWD_WAIT, 'with a pause between the asks')
        io = Crowd(99, table=quest_table(), spells=KEEPFALL)
        r = self.go(io)
        self.assertEqual(r.status, TX.SKIP, r.detail)
        self.assertIn('crowd her stall', r.detail)
        self.assertEqual(io.cmds.count('enter npc Archivist Odrenna'), TX.CROWD_TRIES)
        # no such NPC stays a bug
        self.assertEqual(self.go(QuestIO(odrenna=False)).status, TX.FAIL)

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

    def test_the_real_level_800_buffs_are_auto_setup_timers(self):
        # live run 2026-11-01: Lotus Stance and Ironbound Oath read "in no preset"; a buff is a timer of Auto setup
        table = TX.load_table(os.path.join(MODULES, 'game_helperrotation', 'autorotation_data.lua'))
        timers = TX.load_timer_ids(os.path.join(MODULES, 'game_helpersupport', 'supportspells.lua'))
        with open(os.path.join(MODULES, 'game_chaosspells', 'spelldata.lua'), encoding='utf-8') as f:
            text = f.read()
        quest2 = [(m.group(2), int(m.group(1))) for m in re.finditer(r'\{ id = (\d+), name = "([^"]+)"[^\n]*? quest = 2 \}', text)]
        self.assertEqual(len(quest2), 7, 'one level 800 quest buff per line')
        spells = client_spells()
        for cls, row in table.items():
            mine = [n for n, sid in quest2 if row['voc'] in spells[sid]['vocations']]
            self.assertEqual(len(mine), 1, '%s: exactly one quest 2 spell, got %s' % (cls, mine))
            self.assertEqual(TX.quest_spell_problems(mine[0], cls, 900, spells, table, timers), [], cls)
            self.assertTrue(TX.quest_spell_problems(mine[0], cls, 900, spells, table), 'without the timers it reads missing')

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


# ---------------------------------------------------------------- crafting and upgrades (O584 item 3)
class CraftIO(FakeIO):
    """a mocked backpack, crafting window and tooltip: new stacks go in front, an orb changes the item as its text says;
    `bug` names an orb that does nothing (or the wrong thing)"""

    def __init__(self, bug=None, give_error=None, max_sockets=3, refuse=None):
        FakeIO.__init__(self)
        self.bug, self.give_error, self.refuse = bug, give_error, refuse
        self.slots = []   # front first: {'what', 'id', 'clientId'}
        self.item = {'rarity': 0, 'mods': [], 'quality': 0, 'sockets': 0, 'max': max_sockets, 'socketed': 0}
        self.orbs = {}
        self.opened = False
        self.use_withs = []
        self.supports = [{'id': 7, 'name': 'Fire Bolt', 'count': 2, 'max': 3, 'runes': []}]
        self.charm_bag, self.charm_placed = [], []
        self.rnd = 0

    def index_of(self, what):
        return next(i for i, s in enumerate(self.slots) if s['what'] == what)

    async def go(self, place):
        return True

    async def open_bag(self, client_id):
        self.opened = True

    async def use_with(self, a, ac, b, bc):
        self.use_withs.append((a, b))
        if self.slots[a]['what'] == 'gem' and self.slots[b]['what'] == 'item' and self.item['socketed'] < self.item['sockets']:
            self.item['socketed'] += 1
            del self.slots[a]

    async def helper(self, command, kind, wait=4.0):
        if kind != 'give':
            return None
        if self.give_error:
            return {'err': self.give_error}
        _, what, *rest = command.split()
        ids = {'item': 2400, 'orb': 30000, 'gem': 32006, 'rune': 33001, 'charm': 32301, 'card': 27482}
        key = rest[0] if what == 'orb' else what
        if what == 'orb':
            self.orbs[key] = self.orbs.get(key, 0) + int(rest[1])
            what_ = 'orb:' + key
        else:
            what_ = what
        existing = next((i for i, s in enumerate(self.slots) if s['what'] == what_), None)
        if existing is None or what in ('item', 'charm'):
            self.slots.insert(0, {'what': what_, 'id': ids[what] + (hash(key) % 7 if what == 'orb' else 0), 'clientId': 100 + len(self.slots)})
            existing = 0
        if what == 'charm':
            self.charm_bag.append({'ref': 's3.0', 'sid': 32301, 'iid': '5'})
        s = self.slots[existing]
        return {'what': what, 'key': key, 'id': s['id'], 'clientId': s['clientId'], 'index': existing, 'path': str(existing),
                'count': 1, 'bagClientId': 1988, 'level': 700}

    def mods_state(self):
        return [{'key': m, 'group': m} for m in self.item['mods']]

    async def request(self, opname, action, data, expect, timeout):
        self.asked.append((opname, action, data))
        it = self.item
        if opname == 'crafting' and action == 'select':
            return {'action': 'state', 'data': {'counts': dict(self.orbs), 'item': {
                'path': data['path'], 'rarity': it['rarity'], 'mods': self.mods_state(), 'quality': it['quality'], 'sig': 'sig',
                'sockets': {'count': it['sockets'], 'max': it['max'], 'list': [{'id': 32006, 'index': i + 1} for i in range(it['socketed'])] + [{'id': 0, 'index': it['socketed'] + 1 + j} for j in range(it['sockets'] - it['socketed'])]}}}}
        if opname == 'itemTooltip':
            pos = data['items'][0]['pos']
            slot = self.slots[pos['z']]
            tip = {'name': 'thing', 'rarity': it['rarity'], 'mods': [{'k': m} for m in it['mods']], 'q': it['quality'],
                   'sk': it['socketed']}
            if slot['what'] == 'card':
                tip = {'name': 'Minor Card', 'desc': self.card_desc}
            return {'action': 'tips', 'data': {'items': [{'pos': pos, 'tip': tip}]}}
        if opname == 'crafting' and action == 'apply':
            return self.apply(data['orb'])
        if opname == 'supports' and action == 'open':
            return {'action': 'state', 'data': {'spells': [copy.deepcopy(s) for s in self.supports]}}
        if opname == 'supports' and action == 'socket':
            if self.refuse:
                return {'action': 'result', 'data': {'ok': False, 'text': self.refuse}}
            if self.bug != 'supports':
                self.supports[0]['runes'].append({'slot': len(self.supports[0]['runes']) + 1})
            return {'action': 'result', 'data': {'ok': True, 'text': 'ok'}}
        if opname == 'charms' and action == 'open':
            return {'action': 'state', 'data': {'bag': list(self.charm_bag), 'placed': list(self.charm_placed),
                                                'cells': [{'x': 1, 'y': 1, 'open': True}, {'x': 2, 'y': 1}]}}
        if opname == 'charms' and action == 'place':
            if self.bug != 'charms':
                self.charm_placed.append({'id': 41})
                self.charm_bag.pop(0)
            return {'action': 'result', 'data': {'ok': True}}
        if opname == 'charms' and action == 'take':
            self.charm_placed.pop()
            self.charm_bag.append({'ref': 's3.0', 'sid': 32301, 'iid': '5'})
            return {'action': 'result', 'data': {'ok': True}}
        return None

    card_desc = 'Gives 2% fire damage. Use it to add it to your deck.'

    def apply(self, orb):
        it = self.item
        if self.orbs.get(orb, 0) < 1:
            return {'action': 'result', 'data': {'ok': False, 'text': 'You do not have it'}}
        if self.refuse == orb:
            return {'action': 'result', 'data': {'ok': False, 'text': 'item level too low for this orb'}}
        self.orbs[orb] -= 1
        if self.bug == orb:
            return {'action': 'result', 'data': {'ok': True, 'text': 'done'}}   # an orb that did nothing
        self.rnd += 1
        if orb == 'transmutation':
            it['rarity'], it['mods'] = 1, ['a%d' % self.rnd]
        elif orb == 'alchemy':
            it['rarity'], it['mods'] = 3, ['a%d' % self.rnd, 'b%d' % self.rnd]
        elif orb == 'exalted':
            it['mods'] = it['mods'] + ['c%d' % self.rnd]
        elif orb == 'annulment':
            it['mods'] = it['mods'][:-1]
        elif orb == 'scouring':
            it['rarity'], it['mods'] = 0, []
        elif orb == 'chaos':
            it['mods'] = ['r%d' % self.rnd for _ in it['mods']]
        elif orb == 'divine':
            it['rarity'] = {1: 2, 2: 3, 3: 4, 4: 5, 5: 10}.get(it['rarity'], it['rarity'])
            it['mods'] = it['mods'] + ['d%d' % self.rnd]
        elif orb == 'whetstone':
            it['quality'] += 1
        elif orb == 'sockets':
            it['sockets'] = min(it['max'], self.rnd)
        return {'action': 'result', 'data': {'ok': True, 'text': 'done'}}


class Crafting(unittest.TestCase):
    def go(self, fn, io, cls='Ninja'):
        return run(fn(io, 'Tester Cra', cls, 600))

    def test_the_orbs_change_the_item_as_promised(self):
        io = CraftIO()
        r = self.go(TX.check_craft_orbs, io)
        self.assertEqual(r.status, TX.PASS, r.detail)
        self.assertTrue(r.detail.startswith('Orb of Awakening, Orb of Grafting, Orb of Upheaval, Orb of Unmaking, Orb of Fate, '
                                            'Orb of Erasure, Orb of Gilding changed'), r.detail)
        self.assertTrue(io.opened, 'the backpack is opened as container 0 for the tooltip')
        self.assertEqual(io.item['rarity'], 3, 'the chain ends on the Gilding')
        tip_asks = [a for a in io.asked if a[0] == 'itemTooltip']
        self.assertEqual(tip_asks[0][2]['items'][0]['pos'], {'x': 0xFFFF, 'y': 0x40, 'z': 0}, 'the item sits in slot 0 of the backpack')

    def test_an_orb_that_does_nothing_is_a_bug(self):
        for orb, label in (('exalted', 'Orb of Grafting'), ('transmutation', 'Orb of Awakening'), ('divine', 'Orb of Fate')):
            r = self.go(TX.check_craft_orbs, CraftIO(bug=orb))
            self.assertEqual(r.status, TX.FAIL, orb)
            self.assertIn(label, r.detail)
            self.assertIsNotNone(r.bug_line())

    def test_the_tooltip_and_the_bench_must_agree(self):
        class Lying(CraftIO):
            async def request(self, opname, action, data, expect, timeout):
                r = await CraftIO.request(self, opname, action, data, expect, timeout)
                if opname == 'itemTooltip' and self.item['mods']:
                    r['data']['items'][0]['tip']['mods'] = r['data']['items'][0]['tip']['mods'][:1] + [{'k': 'x'}, {'k': 'y'}, {'k': 'z'}]
                return r
        r = self.go(TX.check_craft_orbs, Lying())
        self.assertEqual(r.status, TX.FAIL)
        self.assertIn('the tooltip lists', r.detail)

    def test_refused_orbs_are_notes_not_bugs(self):
        r = self.go(TX.check_craft_orbs, CraftIO(refuse='divine'))
        self.assertEqual(r.status, TX.PASS)
        self.assertIn('Orb of Fate refused', r.detail)

    def test_skips_say_why(self):
        r = self.go(TX.check_craft_orbs, CraftIO(give_error='the charm system is not loaded'))
        self.assertEqual(r.status, TX.SKIP)
        self.assertIn('not loaded', r.detail)
        old = self.go(TX.check_craft_orbs, CraftIO(give_error='unknown command'))
        self.assertEqual(old.status, TX.SKIP)

    def test_whetstone_adds_quality(self):
        io = CraftIO()
        r = self.go(TX.check_craft_whetstone, io)
        self.assertEqual(r.status, TX.PASS, r.detail)
        self.assertEqual(io.item['quality'], 1)
        r = self.go(TX.check_craft_whetstone, CraftIO(bug='whetstone'))
        self.assertEqual((r.status, 'quality' in r.detail), (TX.FAIL, True))

    def test_sockets(self):
        r = self.go(TX.check_craft_sockets, CraftIO())
        self.assertEqual(r.status, TX.PASS, r.detail)
        r = self.go(TX.check_craft_sockets, CraftIO(max_sockets=0))
        self.assertEqual(r.status, TX.SKIP)
        r = self.go(TX.check_craft_sockets, CraftIO(bug='sockets'))
        self.assertEqual(r.status, TX.FAIL)
        self.assertIn('five Orbs of Sockets', r.detail)

    def test_gems_go_in_by_use_with(self):
        io = CraftIO()
        r = self.go(TX.check_craft_gems, io)
        self.assertEqual(r.status, TX.PASS, r.detail)
        gem_slot, item_slot = io.use_withs[0]
        self.assertEqual((gem_slot, item_slot), (0, 1), 'the gem (given last, in front) is used on the item one slot back')
        self.assertEqual(io.item['socketed'], 1)

    def test_a_gem_that_does_not_stick_is_a_bug(self):
        class NoStick(CraftIO):
            async def use_with(self, a, ac, b, bc):
                self.use_withs.append((a, b))
        r = self.go(TX.check_craft_gems, NoStick())
        self.assertEqual(r.status, TX.FAIL)
        self.assertIn('expected one more', r.detail)

    def test_the_slots_follow_new_stacks(self):
        h = TX.Held()
        h.add('a', {'id': 1, 'index': 0})
        h.add('b', {'id': 2, 'index': 0})
        self.assertEqual((h['a']['index'], h['b']['index']), (1, 0), 'a new stack moves the older ones back')
        h.add('c', {'id': 1, 'index': 1})
        self.assertEqual((h['a']['index'], h['b']['index']), (1, 0), 'a stack that merged moves nothing')

    def test_supports(self):
        r = self.go(TX.check_craft_supports, CraftIO())
        self.assertEqual(r.status, TX.PASS, r.detail)
        r = self.go(TX.check_craft_supports, CraftIO(bug='supports'))
        self.assertEqual(r.status, TX.FAIL)
        r = self.go(TX.check_craft_supports, CraftIO(refuse='The spell has no free socket'))
        self.assertEqual(r.status, TX.SKIP)

    def test_charms(self):
        io = CraftIO()
        r = self.go(TX.check_craft_charms, io)
        self.assertEqual(r.status, TX.PASS, r.detail)
        self.assertEqual((len(io.charm_bag), len(io.charm_placed)), (1, 0), 'the charm is back in the bag')
        r = self.go(TX.check_craft_charms, CraftIO(bug='charms'))
        self.assertEqual(r.status, TX.FAIL)

    def test_cards_tooltip(self):
        r = self.go(TX.check_craft_cards, CraftIO())
        self.assertEqual(r.status, TX.PASS, r.detail)
        io = CraftIO()
        io.card_desc = ''
        r = self.go(TX.check_craft_cards, io)
        self.assertEqual(r.status, TX.FAIL)
        self.assertIn('no description', r.detail)

    def test_orb_rules(self):
        v = lambda rarity=0, mods=(), quality=0, sockets=0: {'rarity': rarity, 'mods': list(mods), 'bench_mods': list(mods),  # noqa: E731
                                                              'quality': quality, 'sockets': sockets, 'sockets_max': 3,
                                                              'socketed': 0, 'tip': ''}
        self.assertEqual(TX.orb_problems('chaos', v(3, 'ab'), v(3, 'cd')), [])
        self.assertTrue(TX.orb_problems('chaos', v(3, 'ab'), v(3, 'c')))
        self.assertTrue(TX.orb_problems('scouring', v(3, 'ab'), v(3, 'ab')))
        self.assertTrue(TX.orb_problems('annulment', v(3, 'ab'), v(3, 'ab')))
        self.assertEqual(TX.orb_problems('divine', v(4, 'ab'), v(5, 'abc')), [])
        self.assertTrue(TX.orb_problems('divine', v(10, 'ab'), v(5, 'abc')), 'a step down is no step up')
        self.assertTrue(TX.orb_problems('sockets', v(), v(sockets=4)))

    def test_the_checks_are_in_the_run_and_the_report(self):
        keys = TX.CheckRun('t', 'Ninja', 100).todo()
        for k in ('craft_orbs', 'craft_whetstone', 'craft_sockets', 'craft_gems', 'craft_supports', 'craft_charms', 'craft_cards'):
            self.assertIn(k, keys)

class ClosedIO(FakeIO):
    """FakeIO plus the closed-mode calls: a second bot (`other`) with its own helper answers and replies"""

    def __init__(self, other_answers=None, other_replies=None, plan=None, sql_ok=True, bot_up=True, **kw):
        super().__init__(**kw)
        self.other_answers, self.other_replies = other_answers or {}, other_replies or {}
        self.plan, self.sql_ok, self.bot_up, self.sqls, self.other_asked = plan, sql_ok, bot_up, [], []

    async def go_of(self, other, place):
        return True

    async def helper_of(self, other, command, kind, wait=4.0):
        a = self.other_answers.get(command)
        return a(self) if callable(a) else a

    async def request_of(self, other, opname, action, data, expect, timeout):
        self.other_asked.append((opname, action, data))
        r = self.other_replies.get((opname, action))
        return r(self) if callable(r) else r

    def closed_plan(self):
        return self.plan

    def online(self, name):
        return name if self.bot_up else None

    def sql(self, statements):
        self.sqls.append(list(statements))
        return self.sql_ok


GUARDS = {s: {'mixed': True, 'off': True, 'together': True} for s in TX.CLOSED_SYSTEMS}


def closed_answer(**over):
    d = {'loaded': True, 'on': True, 'guards': GUARDS, 'realm': 900000001}
    d.update(over)
    return d


class ClosedMode(unittest.TestCase):
    def one(self, fn, io):
        return run(fn(io, 'Tester Aaa', 'Warrior', 500))

    def test_closed_checks_only_in_a_closed_run(self):
        self.assertEqual(TX.CheckRun('Tester Aaa', 'Warrior', 1).todo().count('closed_arena'), 0)
        todo = TX.CheckRun('Tester Aaa', 'Warrior', 1, closed=True).todo()
        for key in TX.CLOSED_KEYS:
            self.assertIn(key, todo)
        self.assertEqual(TX.CheckRun('Tester Aaa', 'Warrior', 1, closed=True, only=TX.CLOSED_KEYS).todo(), list(TX.CLOSED_KEYS))

    def test_problems(self):
        self.assertEqual(TX.closed_problems(closed_answer()), [])
        self.assertTrue(TX.closed_problems(closed_answer(on=False)))
        self.assertTrue(TX.closed_problems({'loaded': False}))
        weak = dict(GUARDS, arena={'mixed': False, 'off': True, 'together': True})
        self.assertIn('arena: the rules let a tester meet a player', TX.closed_problems(closed_answer(guards=weak)))
        weak = dict(GUARDS, market={'mixed': True, 'off': False, 'together': True})
        self.assertIn('market: testers are matched with the mode off', TX.closed_problems(closed_answer(guards=weak)))
        gone = {k: v for k, v in GUARDS.items() if k != 'guild'}
        self.assertTrue(any(p.startswith('guild: no guard') for p in TX.closed_problems(closed_answer(guards=gone))))
        self.assertTrue(TX.closed_problems(closed_answer(guild={'name': 'Iron Crows', 'side': 'player'})))

    def test_guards(self):
        r = self.one(TX.check_closed_guards, ClosedIO(answers={'closed': closed_answer()}))
        self.assertEqual(r.status, TX.PASS)
        r = self.one(TX.check_closed_guards, ClosedIO(answers={'closed': closed_answer(on=False)}))
        self.assertEqual(r.status, TX.FAIL)
        self.assertIn('BUG closed_guards', r.bug_line())
        self.assertEqual(self.one(TX.check_closed_guards, ClosedIO()).status, TX.SKIP)

    def arena_io(self, answer):
        both = {'closed': closed_answer(arena=answer)}
        q = {('arena', 'queue'): {'action': 'state'}}
        return ClosedIO(answers=both, other_answers=both, replies=dict(q), other_replies=dict(q))

    def test_arena(self):
        self.assertEqual(self.one(TX.check_closed_arena, self.arena_io({'queued': False, 'inMatch': True})).status, TX.PASS)
        self.assertEqual(self.one(TX.check_closed_arena, ClosedIO(partner=None)).status, TX.SKIP)
        self.assertEqual(self.one(TX.check_closed_arena, ClosedIO()).status, TX.SKIP)  # no answer from the window
        io = self.arena_io({'queued': True, 'inMatch': False})
        self.assertEqual(self.one(TX.check_closed_arena, io).status, TX.FAIL)
        self.assertIn(('arena', 'leave', {}), io.asked)
        self.assertEqual(self.one(TX.check_closed_arena, self.arena_io({'queued': False, 'inMatch': False})).status, TX.SKIP)

    def test_battleground_and_pvp(self):
        io = ClosedIO(answers={'closed': closed_answer(battleground={'queued': True})},
                      replies={('battleground', 'queue'): {'action': 'state'}})
        self.assertEqual(self.one(TX.check_closed_battleground, io).status, TX.PASS)
        self.assertIn(('battleground', 'leave', {}), io.asked)
        io = ClosedIO(answers={'closed': closed_answer(battleground={'queued': False})},
                      replies={('battleground', 'queue'): {'action': 'state'}})
        self.assertEqual(self.one(TX.check_closed_battleground, io).status, TX.SKIP)
        io = ClosedIO(answers={'closed': closed_answer(pvp={'inside': True})}, replies={('pvpZone', 'enter'): {'action': 'enter'}})
        self.assertEqual(self.one(TX.check_closed_pvp, io).status, TX.PASS)
        io = ClosedIO(answers={'closed': closed_answer(pvp={'inside': False})},
                      replies={('pvpZone', 'enter'): {'action': 'msg', 'data': {'text': 'no'}}})
        self.assertEqual(self.one(TX.check_closed_pvp, io).status, TX.SKIP)

    def war_io(self, accept_ok=True, active=True, declare_ok=True, plan=None, offers=True):
        plan = plan or {'guild': 'Tester Guild Alfa', 'leader': True, 'rival': 'Tester Guild Bravo', 'rival_leader': 'Tester Bbb'}
        me = closed_answer(guild={'name': 'Tester Guild Alfa', 'side': 'tester', 'level': 3})
        state = {'action': 'state', 'data': {'wars': {'pending': [{'id': 7}] if offers else [], 'active': [{'id': 7}] if active else []}}}
        return ClosedIO(answers={'closed': me}, plan=plan, replies={
            ('guildWar', 'declare'): {'action': 'message', 'data': {'ok': declare_ok, 'text': 'x'}},
            ('guildWar', 'refresh'): state, ('guildWar', 'surrender'): {'action': 'message', 'data': {'ok': True}}},
            other_replies={('guildWar', 'refresh'): state,
                           ('guildWar', 'accept'): {'action': 'message', 'data': {'ok': accept_ok, 'text': 'no'}}})

    def test_guild_war(self):
        self.assertEqual(self.one(TX.check_closed_guild, self.war_io()).status, TX.PASS)
        self.assertEqual(self.one(TX.check_closed_guild, self.war_io(active=False)).status, TX.FAIL)
        self.assertEqual(self.one(TX.check_closed_guild, self.war_io(accept_ok=False)).status, TX.FAIL)
        self.assertEqual(self.one(TX.check_closed_guild, self.war_io(offers=False)).status, TX.FAIL)
        self.assertEqual(self.one(TX.check_closed_guild, self.war_io(declare_ok=False)).status, TX.SKIP)
        self.assertEqual(self.one(TX.check_closed_guild, ClosedIO()).status, TX.SKIP)
        member = {'guild': 'Tester Guild Alfa', 'leader': False, 'rival': 'Tester Guild Bravo', 'rival_leader': 'Tester Bbb'}
        self.assertEqual(self.one(TX.check_closed_guild, self.war_io(plan=member)).status, TX.SKIP)
        io = self.war_io()
        io.bot_up = False
        self.assertEqual(self.one(TX.check_closed_guild, io).status, TX.SKIP)
        io = self.war_io()
        io.answers['closed'] = closed_answer(guild={'name': 'Iron Crows', 'side': 'player'})
        self.assertEqual(self.one(TX.check_closed_guild, io).status, TX.FAIL)

    def market_io(self, buy=True, listed=True, items=True):
        sellable = {'action': 'sellable', 'data': {'items': [{'ref': '0', 'sid': 7618}] if items else []}}
        done = {'action': 'done', 'data': {'what': 'list', 'id': 41}} if listed else {'action': 'error', 'data': {'text': 'busy'}}
        bought = {'action': 'done', 'data': {'what': 'buy'}} if buy else {'action': 'error', 'data': {'text': 'no'}}
        return ClosedIO(replies={('market', 'sellable'): sellable, ('market', 'list'): done, ('market', 'cancel'): {'action': 'done'}},
                        other_replies={('market', 'browse'): {'action': 'page', 'data': {'rows': [{'id': 41}]}},
                                       ('market', 'buy'): bought})

    def test_market(self):
        io = self.market_io()
        self.assertEqual(self.one(TX.check_closed_market, io).status, TX.PASS)
        self.assertEqual(io.asked[1][2]['coins'], 0)  # gold only
        self.assertEqual(self.one(TX.check_closed_market, self.market_io(buy=False)).status, TX.FAIL)
        self.assertEqual(self.one(TX.check_closed_market, self.market_io(listed=False)).status, TX.SKIP)
        self.assertEqual(self.one(TX.check_closed_market, self.market_io(items=False)).status, TX.SKIP)
        self.assertEqual(self.one(TX.check_closed_market, ClosedIO()).status, TX.SKIP)
        self.assertEqual(self.one(TX.check_closed_market, ClosedIO(partner=None)).status, TX.SKIP)

    def test_bazaar(self):
        self.assertIsNone(TX.bazaar_problem(False, True, False))
        self.assertTrue(TX.bazaar_problem(True, True, False))
        self.assertTrue(TX.bazaar_problem(False, False, False))
        self.assertTrue(TX.bazaar_problem(False, True, True))
        seq = [closed_answer(bazaar={'locked': v}) for v in (False, True, False)]

        def nxt(io):
            return seq.pop(0)
        io = ClosedIO(answers={'closed': nxt})
        self.assertEqual(self.one(TX.check_closed_bazaar, io).status, TX.PASS)
        self.assertEqual(len(io.sqls), 2)  # listed, then released
        self.assertIn('cancelled', io.sqls[1][0])
        seq[:] = [closed_answer(bazaar={'locked': v}) for v in (False, False, False)]
        io = ClosedIO(answers={'closed': nxt})
        self.assertEqual(self.one(TX.check_closed_bazaar, io).status, TX.FAIL)
        self.assertEqual(len(io.sqls), 2)  # released even when the check fails
        self.assertEqual(self.one(TX.check_closed_bazaar, ClosedIO(answers={'closed': closed_answer()})).status, TX.SKIP)
        io = ClosedIO(answers={'closed': closed_answer(bazaar={'locked': False})}, sql_ok=False)
        self.assertEqual(self.one(TX.check_closed_bazaar, io).status, TX.SKIP)


# ---------------------------------------------------------------------------------------------------- the raid in closed mode (O588)
class RaidWorld:
    """a tiny raid on one lane (y = 5): the entrance portal at x 100, the hall from x 0, a pack at x 25, the boss at x 50, the exit
    portal at x 55 once every boss is slain. It answers `!tester raid` as the helper does (the guide's rules in miniature), moves
    the bots by their steps and is the raid window. Time does not pass."""
    PORTAL, PACK, BOSS, EXIT, TEMPLE = (100, 5), (25, 5), (50, 5), (55, 5), (92, 3)

    def __init__(self, need=1, bosses=1, level=900, on=True, refuse=None, side='tester', slot=3, blocked=(), kill_after=3,
                 never_kill=False, leave_ok=True, levels=None, players=1, no_path=False, no_portal=False, town_ok=True):
        self.no_path, self.no_portal, self.town_ok = no_path, no_portal, town_ok
        self.need, self.bosses, self.level, self.on, self.refuse = need, bosses, level, on, refuse
        self.side, self.slot, self.blocked, self.kill_after = side, slot, set(blocked), kill_after
        self.never_kill, self.leave_ok, self.levels, self.players = never_kill, leave_ok, levels or {}, players
        self.units, self.party = {}, set()
        self.killed = self.trash = 0
        self.packhp, self.hp = kill_after, 100.0
        self.closed = 0
        self.steps = {}
        self.log = []

    def unit(self, name):
        return self.units.setdefault(name, {'pos': (60, 60), 'inside': False})

    def pos(self, name):
        x, y = self.unit(name)['pos']
        return {'x': x, 'y': y, 'z': 7}

    def facts(self, name):
        u = self.unit(name)
        out = {'inside': u['inside'], 'level': self.levels.get(name, self.level), 'minLevel': 800, 'minPlayers': self.need,
               'maxPlayers': 15, 'pos': self.pos(name), 'pz': not u['inside'], 'on': self.on, 'enabled': True, 'bosses': self.bosses,
               'portal': {'x': self.PORTAL[0], 'y': self.PORTAL[1], 'z': 7}, 'slot': 3}
        if not u['inside']:
            return out
        guide = self.guide(u['pos'])
        out['run'] = {'id': 1, 'slot': self.slot, 'side': self.side, 'players': self.players, 'killed': self.killed,
                      'trash': self.trash, 'cleared': self.killed >= self.bosses, 'kills': self.killed, 'fallen': False,
                      'monsters': (self.packhp if not self.trash else 0) + (0 if self.killed else 1),
                      'trashLeft': self.packhp if not self.trash else None, 'bossHp': None if self.killed else int(self.hp)}
        out['guide'] = guide
        return out

    def guide(self, pos):
        def near(a, b, d):
            return abs(a[0] - b[0]) <= d and abs(a[1] - b[1]) <= d

        def g(mode, goal, area, where):
            return {'mode': mode, 'goal': {'x': goal[0], 'y': goal[1], 'z': 7}, 'area': area, 'where': where, 'idx': 1}
        where = 'hall' if pos[0] < 15 else 'corridor' if pos[0] < 35 else 'room'
        if self.killed >= self.bosses:
            return g('exit', self.EXIT, None, where)
        if not self.trash:
            return g('fight' if near(pos, self.PACK, 3) else 'walk', self.PACK, 'trash', where)
        return g('fight' if near(pos, self.BOSS, 4) else 'walk', self.BOSS, 'boss', where)

    def tick(self, name):
        """one look of the leader at its fight: the pack or the boss loses health"""
        u = self.unit(name)
        if not u['inside'] or self.never_kill:
            return
        g = self.guide(u['pos'])
        if g['mode'] == 'fight' and g['area'] == 'trash':
            self.packhp -= 1
            if self.packhp <= 0:
                self.trash = 1
        elif g['mode'] == 'fight' and g['area'] == 'boss':
            self.hp -= 100.0 / self.kill_after
            if self.hp <= 0:
                self.killed = 1

    def answer(self, name, command):
        if command == 'raid path':
            if self.no_path:
                return {'err': 'no path to the raid portal'}
            x, y = self.unit(name)['pos']
            tx, ty = self.PORTAL[0] - 1, self.PORTAL[1]
            dirs = []
            while y != ty and x != tx:
                dirs.append(5 if ty > y else 7)    # a diagonal, southeast or northeast
                x, y = x + 1, y + (1 if ty > y else -1)
            dirs += [1] * max(0, tx - x) + [3] * max(0, x - tx) + [2] * max(0, ty - y) + [0] * max(0, y - ty)
            return dict(self.facts(name), path=dirs)
        if command == 'raid portal':
            if self.no_portal:
                return {'err': 'no free tile next to the raid portal'}
            self.unit(name)['pos'] = (self.PORTAL[0] - 1, self.PORTAL[1])
            return self.facts(name)
        if command == 'raid close':
            was = any(u['inside'] for u in self.units.values())
            for u in self.units.values():
                u['inside'] = False
            self.closed += 1
            return dict(self.facts(name), closed=was)
        if command == 'raid state':
            self.tick(name)
            return self.facts(name)
        if command == 'bag':
            return {'potions': 100}
        return None

    def request(self, name, opname, action):
        if opname != 'raid':
            return None
        u = self.unit(name)
        if action == 'open':
            return {'action': 'info', 'data': {}}
        if action == 'start':
            if self.refuse:
                return {'action': 'msg', 'data': {'text': self.refuse}}
            for n in [name] + sorted(self.party):
                self.unit(n)['inside'], self.unit(n)['pos'] = True, (0, 5)
            return {'action': 'closeInfo', 'data': {}}
        if action == 'leave':
            fighting = self.guide(u['pos'])['mode'] == 'fight' and u['inside']
            if fighting and not self.leave_ok:
                return {'action': 'msg', 'data': {'text': 'Not in the middle of a boss fight.'}}
            u['inside'] = False
            return {'action': 'end', 'data': {}}
        return None

    def step(self, name, dx, dy):
        u = self.unit(name)
        nx, ny = u['pos'][0] + dx, u['pos'][1] + dy
        self.steps[name] = self.steps.get(name, 0) + 1
        if (nx, ny) in self.blocked or not (-1 <= nx <= 200):
            return
        if not u['inside'] and (nx, ny) == self.PORTAL:
            return   # the portal opens the window and puts the bot back
        if u['inside'] and (nx, ny) == self.EXIT and self.killed >= self.bosses:
            u['inside'], u['pos'] = False, (self.PORTAL[0] - 1, self.PORTAL[1])
            return
        u['pos'] = (nx, ny)


class RaidIO(ClosedIO):
    def __init__(self, world, partner='Tester Bbb', **kw):
        super().__init__(partner=partner, **kw)
        self.w, self.me, self.looted, self.modes, self.partner_levels, self.left_party = world, 'Tester Aaa', 0, [], [], []
        self.cmds = []

    async def helper(self, command, kind, wait=4.0):
        self.cmds.append((self.me, command))
        return self.w.answer(self.me, command)

    async def helper_of(self, other, command, kind, wait=4.0):
        self.cmds.append((other, command))
        return self.w.answer(other, command)

    async def request(self, opname, action, data, expect, timeout):
        self.asked.append((opname, action, data))
        return self.w.request(self.me, opname, action)

    async def request_of(self, other, opname, action, data, expect, timeout):
        self.other_asked.append((opname, action, data))
        return self.w.request(other, opname, action)

    async def partner(self, min_level=0):
        self.partner_levels.append(min_level)
        return self.partner_name if self.partner_name and self.w.levels.get(self.partner_name, self.w.level) >= min_level else None

    async def party(self, action, other):
        self.partied.append((action, other))
        if action == 'form':
            self.w.party.add(other)
        else:
            self.left_party.append(other)
        return True

    async def go(self, place):
        self.moves.append(place)
        if self.w.town_ok:
            self.w.unit(self.me)['pos'] = self.w.TEMPLE
        return self.w.town_ok

    async def go_of(self, other, place):
        if self.w.town_ok:
            self.w.unit(other)['pos'] = self.w.TEMPLE
        return self.w.town_ok

    async def step(self, dx, dy):
        self.w.step(self.me, dx, dy)

    async def step_of(self, other, dx, dy):
        self.w.step(other, dx, dy)

    async def loot(self):
        self.looted += 1

    def raid_mode(self, names, on):
        self.modes.append((list(names), on))


class RaidClosed(unittest.TestCase):
    def setUp(self):
        self.keep = (TX.RAID_BUDGET, TX.RAID_FIGHT_MIN, TX.RAID_LEAVE_WAIT, TX.RAID_STUCK)
        TX.reset_raid_turn()

    def tearDown(self):
        TX.RAID_BUDGET, TX.RAID_FIGHT_MIN, TX.RAID_LEAVE_WAIT, TX.RAID_STUCK = self.keep
        TX.reset_raid_turn()

    def play(self, world, **kw):
        io = RaidIO(world, **kw)
        return run(TX.check_closed_raid(io, 'Tester Aaa', 'Warrior', 900)), io

    # -------------------------------------------------------------------------------- the pure parts
    def test_plan_and_walker(self):
        here = {'x': 0, 'y': 5, 'z': 7}
        self.assertEqual(TX.raid_plan(here, {'x': 3, 'y': 5, 'z': 7}, 2), [(1, 0), (1, 0)])
        self.assertEqual(TX.raid_plan(here, {'x': 1, 'y': 9, 'z': 7}, 9), [(0, 1)] * 3 + [(1, 0), (0, 1)])   # the longer axis first
        self.assertEqual(TX.raid_plan(here, {'x': -2, 'y': 5, 'z': 7}, 5), [(-1, 0), (-1, 0)])
        self.assertEqual(TX.raid_plan(here, here, 3), [])
        self.assertEqual(TX.raid_plan(here, {'x': 3, 'y': 5, 'z': 6}, 3), [])      # another floor: no step
        self.assertEqual(TX.raid_plan(None, here, 3), [])
        self.assertTrue(TX.raid_near(here, {'x': 2, 'y': 4, 'z': 7}, 2))
        self.assertFalse(TX.raid_near(here, {'x': 3, 'y': 5, 'z': 7}, 2))
        self.assertFalse(TX.raid_near(here, {'x': 1, 'y': 5, 'z': 6}, 2))
        w = TX.RaidWalker()
        goal = {'x': 9, 'y': 5, 'z': 7}
        self.assertEqual(w.steps(here, goal, 2, 0.0), [(1, 0), (1, 0)])
        moved = {'x': 2, 'y': 5, 'z': 7}
        self.assertEqual(w.steps(moved, goal, 2, 1.0), [(1, 0), (1, 0)])                # it moved: no detour
        self.assertEqual(w.stuck(1.0), 0.0)
        first = w.steps(moved, goal, 2, 2.0)                                           # same tile: blocked
        self.assertEqual(first, [(0, 1)])                                              # one tile to the side
        second = w.steps(moved, goal, 2, 3.0)
        self.assertEqual(second, [(0, -1)] * 2)                                        # the other side, further
        self.assertGreaterEqual(w.stuck(3.0), 2.0)
        self.assertEqual(w.steps({'x': 2, 'y': 6, 'z': 7}, goal, 2, 4.0), [(1, 0), (1, 0)])   # round it: on
        self.assertEqual(w.stuck(4.0), 0.0)
        v = TX.RaidWalker()
        self.assertEqual(v.steps(here, {'x': 0, 'y': 9, 'z': 7}, 1, 0.0), [(0, 1)])
        self.assertEqual(v.steps(here, {'x': 0, 'y': 9, 'z': 7}, 1, 1.0), [(1, 0)])    # blocked going south: across is east / west

    def test_refusal(self):
        ok = {'on': True, 'level': 900, 'minLevel': 800, 'portal': {'x': 1, 'y': 1, 'z': 7}}
        self.assertIsNone(TX.raid_refusal(ok))
        self.assertEqual(TX.raid_refusal(None)[0], TX.SKIP)
        self.assertEqual(TX.raid_refusal({'err': 'no raid system'}), (TX.SKIP, 'no raid system'))
        self.assertIn('switch', TX.raid_refusal(dict(ok, on=False))[1])
        self.assertIn('sealed', TX.raid_refusal(dict(ok, enabled=False))[1])
        self.assertIn('level 700', TX.raid_refusal(dict(ok, level=700))[1])
        self.assertIn('inside', TX.raid_refusal(dict(ok, inside=True))[1])
        self.assertIn('portal', TX.raid_refusal({k: v for k, v in ok.items() if k != 'portal'})[1])
        self.assertIn('level 500', TX.raid_refusal({'on': True, 'minLevel': 800, 'portal': ok['portal']}, 500)[1])

    def test_problems_and_verdict(self):
        mine = {'run': {'side': 'tester', 'slot': 3, 'players': 2}}
        self.assertEqual(TX.raid_problems(mine, 3), [])
        self.assertEqual(TX.raid_problems({}, 3), [])
        self.assertTrue(TX.raid_problems({'run': {'side': 'player', 'slot': 3, 'players': 1}}, 3))
        self.assertTrue(TX.raid_problems({'run': {'side': 'tester', 'slot': 0, 'players': 1}}, 3))
        self.assertTrue(TX.raid_problems({'run': {'side': 'tester', 'slot': 3, 'players': 3}}, 3))
        self.assertEqual(TX.raid_problems({'run': {'side': 'tester', 'slot': 0, 'players': 1}}), [])   # no slot known: not judged
        base = {'faults': [], 'killed': 0, 'trash': 0, 'kills': 0, 'reached': {'hall'}, 'fought': 0, 'stuck': None, 'secs': 50, 'bosses': 5}
        self.assertEqual(TX.raid_verdict(dict(base, faults=['x']))[0], TX.FAIL)
        self.assertEqual(TX.raid_verdict(dict(base, trash=1))[0], TX.PASS)
        self.assertEqual(TX.raid_verdict(dict(base, killed=2, left='the exit'))[0], TX.PASS)
        self.assertEqual(TX.raid_verdict(dict(base, kills=1))[0], TX.PASS)
        self.assertEqual(TX.raid_verdict(dict(base, fought=TX.RAID_FIGHT_MIN))[0], TX.FAIL)
        self.assertEqual(TX.raid_verdict(dict(base, stuck=(5, 6)))[0], TX.SKIP)
        self.assertEqual(TX.raid_verdict(base)[0], TX.SKIP)
        self.assertEqual(TX.raid_start_refusal('Closed test mode is off: the testers do not play this.')[0], TX.FAIL)
        self.assertEqual(TX.raid_start_refusal('Testers and players are never mixed.')[0], TX.FAIL)
        self.assertEqual(TX.raid_start_refusal('Every wing of the Sepulchre is taken right now.')[0], TX.SKIP)
        self.assertEqual(TX.raid_start_refusal(None)[0], TX.SKIP)

    def test_registered_in_the_closed_run_only(self):
        self.assertIn('closed_raid', TX.CLOSED_KEYS)
        self.assertNotIn('closed_raid', TX.KEYS)
        self.assertEqual(TX.CLOSED_KEYS[-1], 'closed_raid')     # the longest check goes last
        self.assertIn('raid', TX.CLOSED_SYSTEMS)
        self.assertEqual(TX.CheckRun('Tester Aaa', 'Warrior', 1).todo().count('closed_raid'), 0)

    # -------------------------------------------------------------------------------- the check
    def test_played_to_the_exit_by_a_party(self):
        world = RaidWorld()
        r, io = self.play(world)
        self.assertEqual(r.status, TX.PASS, r.detail)
        self.assertIn('2 bot(s)', r.detail)
        self.assertIn('bosses slain 1 of 1', r.detail)
        self.assertIn('left by the exit', r.detail)
        self.assertIn('came on foot from the temple', r.detail)
        self.assertEqual(io.partied[0], ('form', 'Tester Bbb'))
        self.assertIn(('leave', 'Tester Bbb'), io.partied)                       # the party is dissolved at the end
        self.assertEqual(io.partner_levels, [800])                                # a member of the raid's level only
        self.assertIn(('raid', 'open', {}), io.asked)
        self.assertEqual([a for a in io.asked if a[1] == 'start'], [('raid', 'start', {})])
        self.assertGreaterEqual(io.looted, 1)                                     # the loot of the kill
        self.assertGreater(world.steps['Tester Aaa'], 40)                         # walked it: hall, corridor, room, to the exit
        self.assertGreater(world.steps['Tester Bbb'], 40)                         # the member walked too
        self.assertEqual(world.closed, 1)                                         # the empty run was closed
        self.assertEqual(io.modes[0], (['Tester Aaa', 'Tester Bbb'], True))
        self.assertEqual(io.modes[-1][1], False)                                  # and the flight rule is back
        self.assertIn('Tester Aaa', TX.RAID_TURN['done'])
        self.assertIsNone(TX.RAID_TURN['by'])
        self.assertEqual(TX.RAID_MEMBERS, {})
        self.assertLess(io.cmds.index(('Tester Aaa', 'bag')), io.cmds.index(('Tester Aaa', 'raid path')))   # the potions first, then the way
        self.assertIn(('Tester Bbb', 'raid path'), io.cmds)                       # the member walks to the entrance too
        self.assertNotIn(('Tester Aaa', 'raid portal'), io.cmds)                  # nobody is put next to the portal: they walked
        self.assertEqual(io.moves.count('town'), 1)                               # to the temple first
        self.assertEqual(io.cmds[-2:], [('Tester Aaa', 'raid close'), ('Tester Aaa', 'raid state')])   # the run is closed, then looked at

    def test_the_way_to_the_entrance(self):
        r, io = self.play(RaidWorld(no_path=True), partner=None)
        self.assertEqual(r.status, TX.PASS, r.detail)
        self.assertIn('next to the portal by the helper', r.detail)               # no path: the helper's step next to it
        self.assertIn(('Tester Aaa', 'raid portal'), io.cmds)
        self.assertEqual(r.fallbacks, ['raid portal (no path, or the walk did not arrive)'])   # O589: counted and named
        TX.reset_raid_turn()
        r, io = self.play(RaidWorld(), partner=None)
        self.assertEqual(r.fallbacks, [], 'on foot: no teleport to count')
        TX.reset_raid_turn()
        r, io = self.play(RaidWorld(blocked={(97, 5), (96, 5), (95, 5), (94, 5), (93, 4), (93, 5), (93, 3), (94, 3)}), partner=None)
        self.assertEqual(r.status, TX.PASS, r.detail)                             # a path that does not arrive: the helper's step
        self.assertIn('by the helper', r.detail)
        TX.reset_raid_turn()
        r, io = self.play(RaidWorld(no_path=True, no_portal=True), partner=None)
        self.assertEqual(r.status, TX.SKIP)
        self.assertIn('no free tile next to the raid portal', r.detail)
        self.assertEqual([a for a in io.asked if a[1] == 'start'], [])            # it never started
        self.assertEqual(TX.RAID_MEMBERS, {})
        TX.reset_raid_turn()
        r, io = self.play(RaidWorld(town_ok=False), partner=None)
        self.assertEqual(r.status, TX.SKIP)
        self.assertIn('did not bring the bot to the temple', r.detail)
        self.assertEqual(TX.raid_path_steps([1, 5, 7, 99, True, 'x', 0]), [(1, 0), (1, 0), (0, 1), (1, 0), (0, -1), (0, -1)])
        self.assertEqual(TX.raid_path_steps(None), [])
        self.assertEqual(TX.raid_path_steps([2] * 300).count((0, 1)), 120)         # at most 120 steps

    def test_solo_when_nobody_is_free(self):
        r, io = self.play(RaidWorld(), partner=None)
        self.assertEqual(r.status, TX.PASS, r.detail)
        self.assertIn('1 bot(s)', r.detail)
        self.assertEqual(io.partied, [])

    def test_a_member_below_the_level_stays_out(self):
        world = RaidWorld(levels={'Tester Bbb': 500})
        r, io = self.play(world)
        self.assertEqual(r.status, TX.PASS, r.detail)
        self.assertIn('1 bot(s)', r.detail)
        self.assertEqual(world.steps.get('Tester Bbb', 0), 0)

    def test_a_blocked_way_is_walked_round(self):
        r, io = self.play(RaidWorld(blocked={(10, 5), (11, 5), (11, 4), (11, 6)}), partner=None)
        self.assertEqual(r.status, TX.PASS, r.detail)

    def test_the_party_minimum(self):
        r, _ = self.play(RaidWorld(need=2), partner=None)
        self.assertEqual(r.status, TX.SKIP)
        self.assertIn('needs 2 players', r.detail)
        r, _ = self.play(RaidWorld(need=2))
        self.assertEqual(r.status, TX.PASS, r.detail)
        TX.reset_raid_turn()
        r, _ = self.play(RaidWorld(need=3))
        self.assertEqual(r.status, TX.SKIP)
        self.assertIn('needs 3 players', r.detail)

    def test_no_check_for_a_bot_that_cannot(self):
        for over, word in ((dict(on=False), 'switch'), (dict(level=700), 'level 700')):
            r, io = self.play(RaidWorld(**over))
            self.assertEqual(r.status, TX.SKIP)
            self.assertIn(word, r.detail)
            self.assertEqual(io.partied, [])
            self.assertIsNone(TX.RAID_TURN['by'])
        io = RaidIO(RaidWorld())
        io.w.answer = lambda name, command: None
        r = run(TX.check_closed_raid(io, 'Tester Aaa', 'Warrior', 900))
        self.assertEqual((r.status, 'old helper file' in r.detail), (TX.SKIP, True))

    def test_the_start_refused(self):
        r, io = self.play(RaidWorld(refuse='Closed test mode is off: the testers do not play this.'))
        self.assertEqual(r.status, TX.FAIL)
        self.assertIn('BUG closed_raid', r.bug_line())
        self.assertIsNone(TX.RAID_TURN['done'])
        self.assertEqual(TX.RAID_MEMBERS, {})
        r, io = self.play(RaidWorld(refuse='Every wing of the Sepulchre is taken right now. Try again in a moment.'))
        self.assertEqual(r.status, TX.SKIP)
        self.assertIn('did not open', r.detail)
        self.assertIsNone(TX.RAID_TURN['done'])

    def test_a_tester_in_a_players_raid_fails(self):
        for over, word in ((dict(side='player'), 'player raid'), (dict(slot=0), 'slot 0'), (dict(players=3), 'players in the testers')):
            TX.reset_raid_turn()
            world = RaidWorld(**over)
            world.slot_expected = 3
            r, io = self.play(world, partner=None)
            self.assertEqual(r.status, TX.FAIL, r.detail)
            self.assertIn(word.split()[0], r.detail)
            self.assertEqual(world.closed, 1)   # the bot is taken out and the run closed even then

    def test_one_raid_at_a_time(self):
        TX.RAID_TURN['by'] = 'Tester Ccc'
        r, io = self.play(RaidWorld())
        self.assertEqual(r.status, TX.SKIP)
        self.assertIn('Tester Ccc is in it', r.detail)
        TX.RAID_TURN.update(by=None, done='Tester Ccc')
        r, io = self.play(RaidWorld())
        self.assertEqual(r.status, TX.SKIP)
        self.assertIn('Tester Ccc played it', r.detail)
        TX.reset_raid_turn()
        TX.RAID_MEMBERS['Tester Aaa'] = 'Tester Zzz'
        r, io = self.play(RaidWorld())
        self.assertEqual(r.status, TX.SKIP)
        self.assertIn('member of the party of Tester Zzz', r.detail)

    def test_walk_blocked_for_good_is_a_skip(self):
        TX.RAID_BUDGET, TX.RAID_STUCK = 70.0, 15.0
        wall = {(x, y) for x in range(0, 40) for y in range(0, 12)} - {(0, 5)}
        r, io = self.play(RaidWorld(blocked=wall), partner=None)
        self.assertEqual(r.status, TX.SKIP, r.detail)
        self.assertIn('blocked at', r.detail)

    def test_a_fight_without_a_kill_fails(self):
        TX.RAID_BUDGET, TX.RAID_FIGHT_MIN = 400.0, 60.0
        r, io = self.play(RaidWorld(never_kill=True), partner=None)
        self.assertEqual(r.status, TX.FAIL, r.detail)
        self.assertIn('killed nothing', r.detail)

    def test_time_is_up_in_a_fight(self):
        TX.RAID_BUDGET, TX.RAID_FIGHT_MIN, TX.RAID_LEAVE_WAIT = 60.0, 9999.0, 20.0
        world = RaidWorld(never_kill=True, leave_ok=False)
        r, io = self.play(world, partner=None)
        self.assertEqual(r.status, TX.SKIP, r.detail)
        self.assertEqual(world.closed, 1)                                         # closed by the helper after the wait
        # and with a clear leave, the Leave button does it
        TX.reset_raid_turn()
        world = RaidWorld(kill_after=60)
        r, io = self.play(world, partner=None)
        self.assertEqual(r.status, TX.SKIP)

    def test_the_budget_ends_a_slow_raid_at_the_leave_button(self):
        TX.RAID_BUDGET = 40.0
        world = RaidWorld(kill_after=999)     # the pack falls late: not within the budget
        world.PACK = (25, 5)
        r, io = self.play(world, partner=None)
        self.assertEqual(r.status, TX.SKIP, r.detail)
        self.assertIn(('raid', 'leave', {}), io.asked)
        self.assertEqual(world.closed, 1)

    def test_no_answer_from_the_helper_inside(self):
        world = RaidWorld()
        io = RaidIO(world, partner=None)
        real = world.answer
        calls = {'n': 0, 'inside': 0}

        def flaky(name, command):
            if command == 'raid state' and world.unit(name)['inside']:
                calls['inside'] += 1
                if calls['inside'] > 2:      # the first looks answer (the bot is seen inside), the helper goes silent after
                    calls['n'] += 1
                    return None
            return real(name, command)
        world.answer = flaky
        r = run(TX.check_closed_raid(io, 'Tester Aaa', 'Warrior', 900))
        self.assertEqual(r.status, TX.SKIP, r.detail)
        self.assertIn('no pack was killed', r.detail)
        self.assertGreaterEqual(calls['n'], TX.RAID_MISSES)


# ---------------------------------------------------------------------------------------------------- the dungeons in closed mode (O589)
class DungeonWorld:
    """a tiny dungeon world on one lane (y = 5): the entrance mark at x 100 (the temple at x 92), dungeon 4 (level 600, one player) and
    dungeon 1 (level 150, two players), monsters at x 10, 20, 30 and the boss at x 60 of the run. It answers `!tester path`, `enter`
    and `dungeon` as the helper does (the guide's rules in miniature), moves the bots by their steps and is the dungeons window.
    Time does not pass."""
    ENTRY, TEMPLE = (100, 5), (92, 3)
    MONSTERS = (10, 20, 30)
    BOSS = 60

    def __init__(self, level=900, on=True, side='tester', no_path=False, refuse=False, kill_after=2, never_kill=False, blocked=(),
                 levels=None, no_enter=False, town_ok=True, size4=1, members=None, dungeons=(4, 1), queued_forever=False):
        self.level, self.on, self.side, self.no_path, self.refuse = level, on, side, no_path, refuse
        self.kill_after, self.never_kill, self.blocked, self.levels = kill_after, never_kill, set(blocked), levels or {}
        self.no_enter, self.town_ok, self.size4, self.members_override = no_enter, town_ok, size4, members
        self.dungeons, self.queued_forever = dungeons, queued_forever
        self.units, self.queue = {}, []
        self.run = None
        self.hp = {}
        self.steps, self.teleports, self.closed = {}, 0, 0

    def unit(self, name):
        return self.units.setdefault(name, {'pos': (60, 60), 'inside': False, 'queued': None})

    def pos(self, name):
        x, y = self.unit(name)['pos']
        return {'x': x, 'y': y, 'z': 8}

    def listing(self):
        table = {4: {'id': 4, 'title': 'Rootmaw', 'level': 600, 'size': self.size4, 'max': 1},
                 1: {'id': 1, 'title': 'Bones Dungeon', 'level': 150, 'size': 2, 'max': 1}}
        return [table[i] for i in self.dungeons]

    def monsters_alive(self):
        return [x for x in self.MONSTERS if self.hp.get(x, 1) > 0]

    def percent(self):
        return int(100 * (len(self.MONSTERS) - len(self.monsters_alive())) / len(self.MONSTERS))

    def guide(self, pos):
        def near(a, b, d):
            return abs(a - b) <= d

        def g(mode, goal, area):
            return {'mode': mode, 'goal': {'x': goal, 'y': 5, 'z': 8}, 'area': area, 'why': 'test'}
        alive = self.monsters_alive()
        if alive:
            goal = min(alive, key=lambda m: abs(m - pos[0]))
            return g('fight' if near(pos[0], goal, 3) else 'walk', goal, 'monsters')
        if self.hp.get(self.BOSS, 1) > 0:
            return g('fight' if near(pos[0], self.BOSS, 4) else 'walk', self.BOSS, 'boss')
        return {'mode': 'wait', 'area': 'boss', 'why': 'the run is over'}

    def facts(self, name):
        u = self.unit(name)
        out = {'inside': u['inside'], 'level': self.levels.get(name, self.level), 'pos': self.pos(name), 'on': self.on,
               'queued': u['queued'], 'maxDifficulty': 6, 'soloWait': 5}
        if not u['inside']:
            if not u['queued']:
                out['list'] = self.listing()
            return out
        members = self.members_override if self.members_override is not None else len(self.run['names'])
        out['run'] = {'id': 1, 'dungeon': self.run['id'], 'title': 'x', 'side': self.side, 'size': 1, 'members': members,
                      'difficulty': 1, 'percent': self.percent(), 'total': 3, 'left': len(self.monsters_alive()),
                      'unlocked': not self.monsters_alive(), 'ended': self.run.get('exit_in') is not None, 'deaths': 0,
                      'bossHp': int(100 * self.hp.get(self.BOSS, 1.0)) if self.hp.get(self.BOSS, 1) > 0 else None}
        out['guide'] = self.guide(u['pos'])
        return out

    def tick(self, name):
        u = self.unit(name)
        if not u['inside'] or name != self.run['names'][0]:
            return
        if self.run.get('exit_in') is not None:   # the exit teleport comes a few looks after the clear (exitDelayMs)
            self.run['exit_in'] -= 1
            if self.run['exit_in'] <= 0:
                for n in self.run['names']:
                    self.units[n]['inside'] = False
                    self.units[n]['pos'] = (self.ENTRY[0] - 5, 5)
            return
        if self.never_kill:
            return
        g = self.guide(u['pos'])
        if g['mode'] != 'fight':
            return
        target = g['goal']['x']
        self.hp[target] = self.hp.get(target, 1.0) - 1.0 / self.kill_after
        if target == self.BOSS and self.hp[target] <= 0:
            self.run['exit_in'] = 3

    def path_to(self, name, goal, reach):
        x, y = self.unit(name)['pos']
        dirs = [2] * max(0, 5 - y) + [0] * max(0, y - 5)
        if x < goal - reach:
            dirs += [1] * (goal - reach - x)
        elif x > goal + reach:
            dirs += [3] * (x - goal - reach)
        return dirs

    def answer(self, name, command):
        u = self.unit(name)
        if command == 'bag':
            return {'potions': 100}
        if command == 'path dungeon':
            if self.no_path:
                return {'err': 'no path', 'name': 'Bones Dungeon', 'dest': {'x': self.ENTRY[0], 'y': 5, 'z': 8}}
            dist = max(abs(u['pos'][0] - self.ENTRY[0]), abs(u['pos'][1] - self.ENTRY[1]))
            base = {'pos': self.pos(name), 'dest': {'x': self.ENTRY[0], 'y': 5, 'z': 8}, 'dist': dist, 'name': 'Bones Dungeon'}
            if dist <= 1:
                return dict(base, here=True, path=[])
            return dict(base, path=self.path_to(name, self.ENTRY[0], 1))
        if command == 'enter dungeon':
            if self.no_enter:
                return {'err': 'no free tile'}
            self.teleports += 1
            u['pos'] = (self.ENTRY[0] - 1, 5)
            return {'kind': 'dungeon', 'pos': self.pos(name)}
        if command == 'dungeon state':
            if u['queued'] and not self.queued_forever:    # the solo wait: a queue short of its group starts after a few looks
                self.waits = getattr(self, 'waits', 0) + 1
                if self.waits >= 2:
                    size = 2 if u['queued'] == 1 else self.size4
                    self.run = {'id': u['queued'], 'names': list(self.queue[:size])}
                    self.hp = {}
                    for n in self.run['names']:
                        self.units[n].update(inside=True, queued=None, pos=(0, 5))
                    self.queue = self.queue[size:]
            self.tick(name)
            return self.facts(name)
        if command == 'dungeon path':
            if not u['inside']:
                return dict(self.facts(name), err='not inside a dungeon run')
            g = self.guide(u['pos'])
            if g['mode'] != 'walk':
                return dict(self.facts(name), err='no goal')
            return dict(self.facts(name), path=self.path_to(name, g['goal']['x'], 3), dist=abs(u['pos'][0] - g['goal']['x']))
        if command == 'dungeon close':
            was = any(v['inside'] for v in self.units.values())
            for v in self.units.values():
                v['inside'] = False
            self.closed += 1
            return dict(self.facts(name), closed=was)
        return None

    def request(self, name, opname, action, data=None):
        if opname != 'dungeons':
            return None
        u = self.unit(name)
        if action == 'fetch':
            return {'action': 'list', 'data': {}}
        if action == 'queue':
            if u['queued']:                       # the window's one button: again leaves
                u['queued'] = None
                self.queue = [n for n in self.queue if n != name]
                return {'action': 'queue', 'data': {'id': data['id'], 'joined': False}}
            if self.refuse:
                return {'action': 'queue', 'data': {'id': data['id'], 'joined': False}}
            u['queued'] = data['id']
            self.queue.append(name)
            size = 2 if data['id'] == 1 else self.size4
            if not self.queued_forever and len(self.queue) >= size:
                self.run = {'id': data['id'], 'names': list(self.queue[:size])}
                self.hp = {}
                for n in self.run['names']:
                    self.units[n].update(inside=True, queued=None, pos=(0, 5))
                self.queue = self.queue[size:]
            return {'action': 'queue', 'data': {'id': data['id'], 'joined': True}}
        return None

    def step(self, name, dx, dy):
        u = self.unit(name)
        nx, ny = u['pos'][0] + dx, u['pos'][1] + dy
        self.steps[name] = self.steps.get(name, 0) + 1
        if (nx, ny) in self.blocked or not (-1 <= nx <= 200):
            return
        if not u['inside'] and (nx, ny) == self.ENTRY:
            return   # the entrance tile opens the window
        u['pos'] = (nx, ny)


class DungeonIO(ClosedIO):
    def __init__(self, world, me='Tester Aaa', partner='Tester Bbb', **kw):
        super().__init__(partner=partner, **kw)
        self.w, self.me, self.looted, self.modes, self.partner_levels, self.cmds = world, me, 0, [], [], []

    async def helper(self, command, kind, wait=4.0):
        self.cmds.append((self.me, command))
        return self.w.answer(self.me, command)

    async def helper_of(self, other, command, kind, wait=4.0):
        self.cmds.append((other, command))
        return self.w.answer(other, command)

    async def request(self, opname, action, data, expect, timeout):
        self.asked.append((opname, action, data))
        return self.w.request(self.me, opname, action, data)

    async def request_of(self, other, opname, action, data, expect, timeout):
        self.other_asked.append((opname, action, data))
        return self.w.request(other, opname, action, data)

    async def partner(self, min_level=0):
        self.partner_levels.append(min_level)
        return self.partner_name if self.partner_name and self.w.levels.get(self.partner_name, self.w.level) >= min_level else None

    async def go(self, place):
        self.moves.append(place)
        if self.w.town_ok:
            self.w.unit(self.me)['pos'] = self.w.TEMPLE
        return self.w.town_ok

    async def go_of(self, other, place):
        if self.w.town_ok:
            self.w.unit(other)['pos'] = self.w.TEMPLE
        return self.w.town_ok

    async def step(self, dx, dy):
        self.w.step(self.me, dx, dy)

    async def step_of(self, other, dx, dy):
        self.w.step(other, dx, dy)

    async def loot(self):
        self.looted += 1

    def raid_mode(self, names, on, keep_flee=False):
        self.modes.append((list(names), on, keep_flee))


class DungeonClosed(unittest.TestCase):
    def setUp(self):
        self.keep = (TX.DUNGEON_BUDGET, TX.DUNGEON_FIGHT_MIN, TX.DUNGEON_STUCK, TX.DUNGEON_QUEUE_WAIT)
        TX.reset_dungeon_turn()

    def tearDown(self):
        TX.DUNGEON_BUDGET, TX.DUNGEON_FIGHT_MIN, TX.DUNGEON_STUCK, TX.DUNGEON_QUEUE_WAIT = self.keep
        TX.reset_dungeon_turn()

    def play(self, world, name='Tester Aaa', level=900, **kw):
        io = DungeonIO(world, me=name, **kw)
        return run(TX.check_closed_dungeon(io, name, 'Warrior', level)), io

    # -------------------------------------------------------------------------------- the pure parts
    def test_pick_refusal_problems_verdict(self):
        listing = [{'id': 1, 'level': 150, 'size': 2}, {'id': 4, 'level': 600, 'size': 1}, {'id': 9, 'level': 2000, 'size': 1}]
        a = {'level': 900, 'list': listing, 'on': True}
        self.assertIsNone(TX.dungeon_refusal(a))
        self.assertEqual(TX.dungeon_pick(a)[0]['id'], 4)                                # the highest of its level
        self.assertEqual(TX.dungeon_pick(dict(a, level=2500))[0]['id'], 9)
        d, why = TX.dungeon_pick(dict(a, level=100))
        self.assertIsNone(d)
        self.assertIn('level 100: the lowest dungeon needs level 150', why)
        TX.DUNGEON_BUSY[4] = 'Tester Ccc'
        self.assertEqual(TX.dungeon_pick(a)[0]['id'], 1)                                # 4 is played: the next one
        TX.DUNGEON_DONE[1] = 'Tester Ddd'
        d, why = TX.dungeon_pick(a)
        self.assertIsNone(d)
        self.assertIn('Tester Ccc', why)
        self.assertIn('Tester Ddd', why)
        for bad, word in ((None, 'old helper'), ({'err': 'no dungeon system'}, 'no dungeon system'), (dict(a, on=False), 'switch'),
                          (dict(a, inside=True), 'inside'), (dict(a, queued=4), 'queued'), (dict(a, list=[]), 'no dungeon list')):
            r = TX.dungeon_refusal(bad)
            self.assertEqual(r[0], TX.SKIP)
            self.assertIn(word, r[1])
        mine = {'run': {'side': 'tester', 'members': 2}}
        self.assertEqual(TX.dungeon_problems(mine, 2), [])
        self.assertEqual(TX.dungeon_problems({}, 2), [])
        self.assertTrue(TX.dungeon_problems({'run': {'side': 'player', 'members': 1}}, 2))
        self.assertTrue(TX.dungeon_problems({'run': {'side': 'tester', 'members': 3}}, 2))
        self.assertEqual(TX.dungeon_problems({'run': {'side': 'tester', 'members': 3}}), [])
        base = {'secs': 100, 'members': 1, 'steps': 5, 'came': 'foot'}
        self.assertEqual(TX.dungeon_verdict(dict(base, faults=['x']))[0], TX.FAIL)
        self.assertEqual(TX.dungeon_verdict(dict(base, percent=10))[0], TX.PASS)
        self.assertEqual(TX.dungeon_verdict(dict(base, won=True))[0], TX.PASS)
        self.assertEqual(TX.dungeon_verdict(dict(base, fought=TX.DUNGEON_FIGHT_MIN))[0], TX.FAIL)
        self.assertEqual(TX.dungeon_verdict(dict(base, stuck=(1, 2)))[0], TX.SKIP)
        self.assertEqual(TX.dungeon_verdict(dict(base, died=True))[0], TX.SKIP)
        self.assertEqual(TX.dungeon_verdict(base)[0], TX.SKIP)
        self.assertIn('enter dungeon (no path)', TX.dungeon_verdict(dict(base, won=True, fallbacks=['enter dungeon (no path)']))[1])
        self.assertIn('closed_dungeon', TX.CLOSED_KEYS)
        self.assertNotIn('closed_dungeon', TX.KEYS)
        self.assertLess(TX.CLOSED_KEYS.index('closed_dungeon'), TX.CLOSED_KEYS.index('closed_raid'))
        self.assertEqual(TX.CLOSED_KEYS[-1], 'closed_raid')

    def test_the_closed_systems_are_the_servers(self):
        with open(os.path.join(ROOT, 'server', 'data', 'scripts', 'chaos', 'testers_core.lua'), encoding='utf-8') as f:
            text = f.read()
        block = re.search(r'K\.CLOSED_SYSTEMS = \{(.*?)\}', text, re.S).group(1)
        keys = sorted(re.findall(r'(\w+) = true', block))
        self.assertEqual(keys, sorted(TX.CLOSED_SYSTEMS), 'testers_core.lua K.CLOSED_SYSTEMS and tester_checks.py CLOSED_SYSTEMS agree')

    # -------------------------------------------------------------------------------- walking like a person
    def test_walk_by_path(self):
        class W:
            def __init__(self, answers):
                self.answers, self.stepped = list(answers), 0

        class IO(FakeIO):
            def __init__(self, answers):
                super().__init__()
                self.queue_ = list(answers)
                self.steps = []

            async def helper(self, command, kind, wait=4.0):
                return self.queue_.pop(0) if self.queue_ else None

            async def step(self, dx, dy):
                self.steps.append((dx, dy))
        lead = {'name': 'Tester Aaa', 'lead': True}
        io = IO([{'path': [1, 1], 'dist': 5}, {'path': [], 'dist': 1, 'pos': {}}])
        how, got = run(TX.walk_by_path(io, lead, 'path x', 'path'))
        self.assertEqual(how, 'foot')
        self.assertEqual(io.steps, [(1, 0), (1, 0)])
        io = IO([{'here': True}])
        self.assertEqual(run(TX.walk_by_path(io, lead, 'path x', 'path'))[0], 'foot')
        self.assertEqual(io.steps, [])
        how, got = run(TX.walk_by_path(IO([{'err': 'no path'}]), lead, 'path x', 'path'))
        self.assertEqual((how, got['err']), ('err', 'no path'))
        how, got = run(TX.walk_by_path(IO([None]), lead, 'path x', 'path'))
        self.assertEqual(how, 'err')
        self.assertIn('no answer', got['err'])
        how, got = run(TX.walk_by_path(IO([{'path': [], 'dist': 9}]), lead, 'path x', 'path'))
        self.assertEqual((how, got['err']), ('err', 'an empty path'))
        io = IO([{'path': [1], 'dist': 9}, {'path': [1], 'dist': 9}, {'path': [1], 'dist': 9}, {'path': [1], 'dist': 9}])
        self.assertEqual(run(TX.walk_by_path(io, lead, 'path x', 'path'))[0], 'far')     # the steps do not bring it nearer
        io = IO([{'path': [1], 'dist': 50 - i} for i in range(20)])
        self.assertEqual(run(TX.walk_by_path(io, lead, 'path x', 'path', rounds=3))[0], 'far')   # still on the way after 3 asks
        self.assertEqual(len(io.steps), 3)
        self.assertIn('enter x (no path)', TX.fallback_note('enter x', 'no path'))

    # -------------------------------------------------------------------------------- the check
    def test_played_to_the_end(self):
        world = DungeonWorld()
        r, io = self.play(world, partner=None)
        self.assertEqual(r.status, TX.PASS, r.detail)
        self.assertTrue(r.detail.startswith('Rootmaw: came'), r.detail)
        self.assertIn('100% of the monsters dead', r.detail)
        self.assertIn('boss slain', r.detail)
        self.assertIn('came on foot from the temple', r.detail)
        self.assertEqual(r.fallbacks, [])
        self.assertEqual(world.teleports, 0)
        self.assertNotIn(('Tester Aaa', 'enter dungeon'), io.cmds)                # it walked
        self.assertLess(io.cmds.index(('Tester Aaa', 'bag')), io.cmds.index(('Tester Aaa', 'path dungeon')))
        self.assertIn(('dungeons', 'fetch', {}), io.asked)
        self.assertEqual([a for a in io.asked if a[1] == 'queue'], [('dungeons', 'queue', {'id': 4, 'difficulty': 1})])
        self.assertGreaterEqual(io.looted, 2)                                     # a loot after the kills and one after the boss
        self.assertGreater(world.steps['Tester Aaa'], 50)
        self.assertEqual(io.modes[0], (['Tester Aaa'], True, True))                # no walk back to the hunt, but the bot may still flee
        self.assertEqual(io.modes[-1][1], False)
        self.assertEqual(io.cmds[-2:], [('Tester Aaa', 'dungeon close'), ('Tester Aaa', 'dungeon state')])
        self.assertEqual(TX.DUNGEON_DONE, {4: 'Tester Aaa'})
        self.assertEqual(TX.DUNGEON_BUSY, {})
        self.assertEqual(TX.DUNGEON_MEMBERS, {})
        self.assertEqual(io.moves.count('town'), 1)
        self.assertIn(('Tester Aaa', 'dungeon path'), io.cmds)                    # inside: the engine path to the goal

    def test_a_party_of_two_in_a_dungeon_of_two(self):
        world = DungeonWorld(level=300, dungeons=(1,))
        r, io = self.play(world, level=300)
        self.assertEqual(r.status, TX.PASS, r.detail)
        self.assertIn('2 bot(s)', r.detail)
        self.assertEqual(io.partner_levels, [150])
        self.assertEqual(io.partied[0], ('form', 'Tester Bbb'))
        self.assertIn(('leave', 'Tester Bbb'), io.partied)
        self.assertEqual([a for a in io.other_asked if a[1] == 'queue'], [('dungeons', 'queue', {'id': 1, 'difficulty': 1})])
        self.assertGreater(world.steps['Tester Bbb'], 20)                         # the member walked to the entrance and in
        self.assertIn(('Tester Bbb', 'path dungeon'), io.cmds)
        self.assertEqual(TX.DUNGEON_MEMBERS, {})
        self.assertEqual(io.modes[0][0], ['Tester Aaa', 'Tester Bbb'])

    def test_a_member_of_another_party_does_no_second_run(self):
        TX.DUNGEON_MEMBERS['Tester Aaa'] = 'Tester Zzz'
        r, io = self.play(DungeonWorld())
        self.assertEqual(r.status, TX.SKIP)
        self.assertIn('member of the party of Tester Zzz', r.detail)
        self.assertEqual(io.asked, [])

    def test_each_dungeon_once_per_run(self):
        world = DungeonWorld()
        r, io = self.play(world, partner=None)
        self.assertEqual(r.status, TX.PASS, r.detail)
        r2, io2 = self.play(DungeonWorld(), name='Tester Ccc', partner=None)       # the second bot gets the other dungeon, played alone
        self.assertEqual(r2.status, TX.PASS, r2.detail)
        self.assertEqual(TX.DUNGEON_DONE, {4: 'Tester Aaa', 1: 'Tester Ccc'})
        self.assertEqual([a for a in io2.asked if a[1] == 'queue'], [('dungeons', 'queue', {'id': 1, 'difficulty': 1})])
        TX.DUNGEON_DONE.update({4: 'a', 1: 'b'})
        r3, io3 = self.play(DungeonWorld(), name='Tester Ddd', partner=None)
        self.assertEqual(r3.status, TX.SKIP)
        self.assertIn('was played in this run', r3.detail)
        self.assertEqual(io3.asked, [])

    def test_no_path_the_teleport_is_the_fallback_and_counted(self):
        world = DungeonWorld(no_path=True)
        r, io = self.play(world, partner=None)
        self.assertEqual(r.status, TX.PASS, r.detail)
        self.assertEqual(world.teleports, 1)
        self.assertIn(('Tester Aaa', 'enter dungeon'), io.cmds)
        self.assertEqual(r.fallbacks, ['enter dungeon (no path)'])
        self.assertIn('teleport in place of walking: enter dungeon (no path)', r.detail)
        self.assertIn('by a helper teleport next to the entrance', r.detail)
        self.assertEqual(r.as_dict()['fallbacks'], ['enter dungeon (no path)'])
        lines = TX.report_lines([r.as_dict()])
        self.assertTrue(any('helper teleports in place of walking: 1' in ln for ln in lines), lines)
        self.assertTrue(any('closed_dungeon' in ln and 'enter dungeon (no path)' in ln and '1x' in ln for ln in lines), lines)
        self.assertEqual([ln for ln in TX.report_lines([TX.Result('x', 'b', 'c', TX.PASS).as_dict()]) if 'teleports' in ln], [])
        TX.reset_dungeon_turn()
        r, io = self.play(DungeonWorld(no_path=True, no_enter=True), partner=None)
        self.assertEqual(r.status, TX.SKIP)
        self.assertIn('no way to dungeon', r.detail)
        self.assertEqual([a for a in io.asked if a[1] == 'queue'], [])
        self.assertEqual(TX.DUNGEON_BUSY, {})

    def test_a_blocked_way_to_the_entrance_falls_back(self):
        world = DungeonWorld(blocked={(97, 5), (96, 5), (95, 5), (94, 5), (93, 5), (93, 4), (93, 6), (94, 3), (94, 4), (94, 6), (93, 3)})
        r, io = self.play(world, partner=None)
        self.assertEqual(r.status, TX.PASS, r.detail)
        self.assertEqual(r.fallbacks and r.fallbacks[0].startswith('enter dungeon'), True)

    def test_refusals_before_the_walk(self):
        for over, word in ((dict(on=False), 'switch'), (dict(level=100), 'level 100')):
            r, io = self.play(DungeonWorld(**over), level=over.get('level', 900))
            self.assertEqual(r.status, TX.SKIP)
            self.assertIn(word, r.detail)
            self.assertEqual(io.asked, [])
            self.assertEqual(TX.DUNGEON_BUSY, {})
        r, io = self.play(DungeonWorld(town_ok=False), partner=None)
        self.assertEqual(r.status, TX.SKIP)
        self.assertIn('did not bring the bot to the temple', r.detail)
        io = DungeonIO(DungeonWorld())
        io.w.answer = lambda name, command: None
        r = run(TX.check_closed_dungeon(io, 'Tester Aaa', 'Warrior', 900))
        self.assertEqual((r.status, 'old helper file' in r.detail), (TX.SKIP, True))

    def test_the_queue_refuses_or_waits(self):
        r, io = self.play(DungeonWorld(refuse=True), partner=None)
        self.assertEqual(r.status, TX.SKIP)
        self.assertIn('queue refused the bot', r.detail)
        self.assertEqual(TX.DUNGEON_DONE, {})
        TX.reset_dungeon_turn()
        TX.DUNGEON_QUEUE_WAIT = 6.0
        world = DungeonWorld(queued_forever=True)
        r, io = self.play(world, partner=None)
        self.assertEqual(r.status, TX.SKIP)
        self.assertIn('did not start in 6 s', r.detail)
        self.assertEqual([a for a in io.asked if a[1] == 'queue'].__len__(), 2)       # the entry is left by asking again
        self.assertIsNone(world.unit('Tester Aaa')['queued'])

    def test_a_tester_in_a_players_run_fails(self):
        for over, word in ((dict(side='player'), 'player dungeon run'), (dict(members=3), 'players in the testers')):
            TX.reset_dungeon_turn()
            r, io = self.play(DungeonWorld(**over), partner=None)
            self.assertEqual(r.status, TX.FAIL, r.detail)
            self.assertIn(word, r.detail)
            self.assertIn('BUG closed_dungeon', r.bug_line())
            self.assertEqual(TX.DUNGEON_DONE, {})

    def test_no_kill_in_a_fight_is_a_failure(self):
        TX.DUNGEON_BUDGET, TX.DUNGEON_FIGHT_MIN = 60.0, 20.0
        r, io = self.play(DungeonWorld(never_kill=True), partner=None)
        self.assertEqual(r.status, TX.FAIL, r.detail)
        self.assertIn('killed none', r.detail)
        self.assertEqual(TX.DUNGEON_DONE, {})

    def test_a_walk_that_never_moves_is_a_skip(self):
        TX.DUNGEON_BUDGET, TX.DUNGEON_STUCK = 60.0, 10.0
        world = DungeonWorld(blocked={(x, y) for x in range(0, 40) for y in range(0, 12)} - {(0, 5)})
        world.blocked.discard((0, 5))
        r, io = self.play(world, partner=None)
        self.assertEqual(r.status, TX.SKIP, r.detail)
        self.assertIn('blocked', r.detail)

    def test_the_budget_closes_a_slow_run(self):
        TX.DUNGEON_BUDGET = 8.0
        world = DungeonWorld(kill_after=50)
        r, io = self.play(world, partner=None)
        self.assertIn(r.status, (TX.PASS, TX.SKIP), r.detail)
        self.assertEqual(world.closed, 1)
        self.assertIn(('Tester Aaa', 'dungeon close'), io.cmds)
        self.assertFalse(world.unit('Tester Aaa')['inside'])
        self.assertEqual(TX.DUNGEON_BUSY, {})

    def test_a_bot_still_inside_after_the_close_fails(self):
        world = DungeonWorld()
        io = DungeonIO(world, partner=None)
        real = world.answer

        def stubborn(name, command):
            if command == 'dungeon close':
                return dict(world.facts(name), closed=False)
            return real(name, command)
        world.answer = stubborn
        TX.DUNGEON_BUDGET = 8.0
        world2 = world
        world2.kill_after = 50
        r = run(TX.check_closed_dungeon(io, 'Tester Aaa', 'Warrior', 900))
        self.assertEqual(r.status, TX.FAIL, r.detail)
        self.assertIn('still inside the dungeon after the close', r.detail)


# ---------------------------------------------------------------------------------------------------- the group queue and the party finder (O589)
class QueueWorld:
    """two windows on one tiny world: the Group Queue (join of a party of two, a ready check, a run of the testers) and the Party Finder
    (a listing, the other bot's list, an application, the leader's accept). It answers `!tester dungeon` / `party` as the helper does."""
    LIST = [{'id': 1, 'title': 'Bones Dungeon', 'level': 150, 'size': 2, 'max': 1},
            {'id': 4, 'title': 'Rootmaw', 'level': 600, 'size': 1, 'max': 1},
            {'id': 3, 'title': 'Forbidden Chevalier', 'level': 500, 'size': 2, 'max': 1}]

    def __init__(self, level=900, on=True, refuse=None, no_check=False, never_runs=False, side='tester', members=2, levels=None,
                 pf_refuse=None, hidden=False, no_apply=False, no_join=False, roles=('tank', 'healer')):
        self.level, self.on, self.refuse, self.no_check, self.never_runs = level, on, refuse, no_check, never_runs
        self.side, self.members, self.levels = side, members, levels or {}
        self.pf_refuse, self.hidden, self.no_apply, self.no_join, self.roles = pf_refuse, hidden, no_apply, no_join, roles
        self.joined, self.accepted, self.inside, self.checks_seen = None, set(), set(), 0
        self.listing, self.apps, self.party_size, self.closed, self.unlisted = None, [], 1, 0, 0
        self.asked = []

    def lvl(self, name):
        return self.levels.get(name, self.level)

    def dungeon_state(self, name):
        out = {'inside': name in self.inside, 'level': self.lvl(name), 'on': self.on, 'queued': 1 if self.joined and name not in self.inside else None,
               'pos': {'x': 5, 'y': 5, 'z': 8}}
        if name in self.inside:
            out['run'] = {'side': self.side, 'members': self.members, 'percent': 0, 'left': 10, 'dungeon': self.joined}
        elif not out['queued']:
            out['list'] = self.LIST
        return out

    def answer(self, name, command):
        if command == 'dungeon state':
            if self.joined and not self.never_runs and len(self.accepted) >= 2 and name not in self.inside:
                self.inside = {'Tester Aaa', 'Tester Bbb'}      # both accepted: the dungeon's next tick starts the run
            return self.dungeon_state(name)
        if command == 'dungeon close':
            self.closed += 1
            self.inside.clear()
            self.joined = None
            return dict(self.dungeon_state(name), closed=True)
        if command == 'party':
            return {'size': self.party_size}
        return None

    def request(self, name, opname, action, data=None):
        self.asked.append((name, opname, action, data))
        if opname == 'groupQueue':
            if action == 'open':
                return {'action': 'state', 'data': {}}
            if action == 'join':
                if self.refuse:
                    return {'action': 'msg', 'data': {'text': self.refuse}}
                self.joined = data['dungeon']['id']
                return {'action': 'state', 'data': {'group': {'picks': [data['dungeon']]}}}
            if action == 'query':
                if self.joined and not self.no_check and len(self.accepted) < 2:
                    self.checks_seen += 1
                    return {'action': 'state', 'data': {'group': {'check': {'key': 'dungeon', 'accepted': len(self.accepted), 'total': 2}}}}
                return {'action': 'state', 'data': {'group': {} if not self.joined else {'picks': []}}}
            if action == 'accept':
                self.accepted.add(name)
                return {'action': 'state', 'data': {}}
            if action == 'leave':
                self.joined = None
                return {'action': 'state', 'data': {}}
        if opname == 'partyFinder':
            if action == 'open':
                return {'action': 'init', 'data': {'acts': [{'k': 'dungeon', 'n': 'Dungeon', 'targets': ['Bones'], 'max': 5},
                                                          {'k': 'rift', 'n': 'Rift', 'range': {'min': 2, 'max': 9}}],
                                                   'my': list(self.roles) if name == 'Tester Aaa' else ['healer', 'dps'], 'defExp': 30}}
            if action == 'post':
                if self.pf_refuse:
                    return {'action': 'notice', 'data': {'text': self.pf_refuse, 'kind': 'error'}}
                self.listing = {'id': 7, 'data': data}
                return {'action': 'list', 'data': {'rows': [], 'mine': {'id': 7, 'apps': []}}}
            if action == 'refresh':
                if name == 'Tester Bbb':
                    rows = [] if self.hidden or not self.listing else [{'id': 7, 'ld': 'Tester Aaa'}]
                    return {'action': 'list', 'data': {'rows': rows}}
                apps = [{'n': 'Tester Bbb', 'g': 43}] if self.apps else []
                return {'action': 'list', 'data': {'rows': [], 'mine': {'id': 7, 'apps': apps}}}
            if action == 'apply':
                if not self.no_apply:
                    self.apps.append(name)
                return {'action': 'notice', 'data': {'text': 'You applied', 'kind': 'info'}}
            if action == 'accept':
                self.accepted_g = data['g']
                return {'action': 'list', 'data': {'rows': []}}
            if action == 'unlist':
                self.unlisted += 1
                return {'action': 'list', 'data': {'rows': []}}
        return None


class QueueIO(ClosedIO):
    def __init__(self, world, me='Tester Aaa', **kw):
        super().__init__(**kw)
        self.w, self.me, self.partner_levels, self.cmds = world, me, [], []

    async def helper(self, command, kind, wait=4.0):
        self.cmds.append((self.me, command))
        return self.w.answer(self.me, command)

    async def helper_of(self, other, command, kind, wait=4.0):
        self.cmds.append((other, command))
        return self.w.answer(other, command)

    async def request(self, opname, action, data, expect, timeout):
        self.asked.append((opname, action, data))
        return self.w.request(self.me, opname, action, data)

    async def request_of(self, other, opname, action, data, expect, timeout):
        self.other_asked.append((opname, action, data))
        return self.w.request(other, opname, action, data)

    async def partner(self, min_level=0):
        self.partner_levels.append(min_level)
        return self.partner_name if self.partner_name and self.w.lvl(self.partner_name) >= min_level else None

    async def party(self, action, other):
        self.partied.append((action, other))
        if action in ('form', 'join') and not self.w.no_join:
            self.w.party_size = 2
        elif action == 'leave':
            self.w.party_size = 1
        return not (action == 'join' and self.w.no_join)


class GroupQueueClosed(unittest.TestCase):
    def setUp(self):
        TX.reset_dungeon_turn()

    def tearDown(self):
        TX.reset_dungeon_turn()

    def play(self, world, **kw):
        io = QueueIO(world, **kw)
        return run(TX.check_closed_groupqueue(io, 'Tester Aaa', 'Warrior', world.level)), io

    def test_pick_and_refusal(self):
        lst = QueueWorld.LIST
        self.assertEqual(TX.groupqueue_pick(lst, 900, set())['id'], 3)          # the highest of two that both may enter (size 2)
        self.assertEqual(TX.groupqueue_pick(lst, 300, set())['id'], 1)
        self.assertEqual(TX.groupqueue_pick(lst, 900, {3})['id'], 1)
        self.assertIsNone(TX.groupqueue_pick(lst, 100, set()))
        self.assertIsNone(TX.groupqueue_pick(lst, 900, {1, 3}))
        self.assertIsNone(TX.groupqueue_pick(None, 900, set()))
        self.assertEqual(TX.groupqueue_refusal('Closed test mode is off: the testers do not play this.')[0], TX.FAIL)
        self.assertEqual(TX.groupqueue_refusal('Testers and players are never mixed.')[0], TX.FAIL)
        self.assertEqual(TX.groupqueue_refusal('You are in cooldown for dungeons.')[0], TX.SKIP)
        self.assertEqual(TX.groupqueue_refusal('')[0], TX.SKIP)
        self.assertIn('closed_groupqueue', TX.CLOSED_KEYS)
        self.assertIn('closed_party_finder', TX.CLOSED_KEYS)
        self.assertNotIn('closed_groupqueue', TX.KEYS)
        self.assertLess(TX.CLOSED_KEYS.index('closed_groupqueue'), TX.CLOSED_KEYS.index('closed_dungeon'))

    def test_a_party_of_two_is_started_after_the_ready_check(self):
        world = QueueWorld()
        r, io = self.play(world)
        self.assertEqual(r.status, TX.PASS, r.detail)
        self.assertIn('ready check accepted by both', r.detail)
        self.assertIn('Forbidden Chevalier', r.detail)                           # the highest dungeon for two of level 900
        self.assertEqual(world.joined, None)                                     # the run was closed
        self.assertEqual(world.closed, 1)
        self.assertEqual(world.accepted, {'Tester Aaa', 'Tester Bbb'})
        self.assertGreaterEqual(world.checks_seen, 1)
        self.assertEqual(io.partied[0], ('form', 'Tester Bbb'))
        self.assertIn(('leave', 'Tester Bbb'), io.partied)
        self.assertEqual(io.partner_levels, [150])
        self.assertIn(('groupQueue', 'join', {'dungeon': {'id': 3, 'difficulty': 1}}), io.asked)
        self.assertEqual(TX.DUNGEON_BUSY, {})
        self.assertLess(io.moves.index('town'), 1)

    def test_skips(self):
        for over, word in ((dict(on=False), 'switch'), (dict(level=100), 'level 100')):
            r, io = self.play(QueueWorld(**over))
            self.assertEqual(r.status, TX.SKIP)
            self.assertIn(word, r.detail)
        r, io = self.play(QueueWorld(), partner=None)
        self.assertEqual(r.status, TX.SKIP)
        self.assertIn('no free bot of level 150', r.detail)
        r, io = self.play(QueueWorld(levels={'Tester Bbb': 400}))                # the partner is below dungeon 3: dungeon 1 for two
        self.assertEqual(r.status, TX.PASS, r.detail)
        self.assertIn('Bones Dungeon', r.detail)
        TX.DUNGEON_BUSY.update({1: 'x', 3: 'y'})
        r, io = self.play(QueueWorld())
        self.assertEqual(r.status, TX.SKIP)
        self.assertIn('no dungeon for two', r.detail)
        TX.reset_dungeon_turn()
        r, io = self.play(QueueWorld(never_runs=True))
        self.assertEqual(r.status, TX.SKIP)
        self.assertIn('no run in', r.detail)

    def test_the_join_refused(self):
        r, io = self.play(QueueWorld(refuse='Closed test mode is off: the testers do not play this.'))
        self.assertEqual(r.status, TX.FAIL)
        self.assertIn('BUG closed_groupqueue', r.bug_line())
        self.assertEqual(TX.DUNGEON_BUSY, {})
        r, io = self.play(QueueWorld(refuse='You are in cooldown for dungeons.'))
        self.assertEqual(r.status, TX.SKIP)

    def test_a_party_started_without_a_ready_check_or_in_a_players_run_fails(self):
        r, io = self.play(QueueWorld(no_check=True))
        self.assertEqual(r.status, TX.SKIP, r.detail)                            # nobody accepted: no run
        w = QueueWorld(side='player')
        r, io = self.play(w)
        self.assertEqual(r.status, TX.FAIL, r.detail)
        self.assertIn('player dungeon run', r.detail)
        w = QueueWorld(members=1)
        r, io = self.play(w)
        self.assertEqual(r.status, TX.FAIL, r.detail)
        self.assertIn('1 member(s) inside', r.detail)


class PartyFinderClosed(unittest.TestCase):
    def play(self, world, **kw):
        io = QueueIO(world, **kw)
        return run(TX.check_closed_party_finder(io, 'Tester Aaa', 'Warrior', 900)), io

    def test_the_helpers(self):
        init = {'acts': [{'k': 'rift', 'range': {'min': 2}, 'title': True}, {'k': 'dungeon', 'targets': ['A']}], 'defExp': 45, 'my': ['dps', 'x', 'tank']}
        act, why = TX.pf_pick_activity(init)
        self.assertEqual(act['k'], 'dungeon')                                     # the first one that needs no title
        self.assertIsNone(TX.pf_pick_activity({'acts': []})[0])
        self.assertIsNone(TX.pf_pick_activity(None)[0])
        d = TX.pf_listing(act, 'tank', 'healer', init)
        self.assertEqual((d['a'], d['want'], d['role'], d['exp'], d['t']), ('dungeon', {'healer': 1}, 'tank', 45, 1))
        d = TX.pf_listing({'k': 'rift', 'range': {'min': 2}, 'title': True}, 'tank', 'dps', init)
        self.assertEqual((d['lo'], d['hi'], d['title']), (2, 2, 'Tester group'))
        self.assertEqual(TX.pf_roles(init), ['dps', 'tank'])
        self.assertEqual(TX.pf_roles(None), [])

    def test_listed_found_applied_accepted_joined(self):
        world = QueueWorld()
        r, io = self.play(world)
        self.assertEqual(r.status, TX.PASS, r.detail)
        self.assertIn('Tester Bbb', r.detail)
        self.assertIn('party of 2', r.detail)
        self.assertEqual(world.accepted_g, 43)                                    # the leader accepted the applicant by its guid
        self.assertEqual(world.listing['data']['want'], {'healer': 1})            # the first role the partner fills
        self.assertEqual(world.listing['data']['role'], 'tank')
        self.assertEqual(world.unlisted, 1)                                       # the listing is taken down again
        self.assertIn(('join', 'Tester Bbb'), io.partied)
        self.assertIn(('leave', 'Tester Bbb'), io.partied)
        self.assertEqual(world.party_size, 1)

    def test_refusals_and_failures(self):
        r, _ = self.play(QueueWorld(), partner=None)
        self.assertEqual(r.status, TX.SKIP)
        r, io = self.play(QueueWorld(pf_refuse='Closed test mode is off: the testers do not play this.'))
        self.assertEqual(r.status, TX.FAIL)
        self.assertIn('BUG closed_party_finder', r.bug_line())
        self.assertEqual(io.partied[-1], ('leave', 'Tester Bbb'))
        r, _ = self.play(QueueWorld(pf_refuse='Wait a moment before posting again.'))
        self.assertEqual(r.status, TX.SKIP)
        r, _ = self.play(QueueWorld(hidden=True))
        self.assertEqual(r.status, TX.FAIL)
        self.assertIn('not in another tester', r.detail)
        r, io = self.play(QueueWorld(no_apply=True))
        self.assertEqual(r.status, TX.FAIL)
        self.assertIn('leader sees 0 application', r.detail)
        r, _ = self.play(QueueWorld(no_join=True))
        self.assertEqual(r.status, TX.SKIP)
        self.assertIn('could not join', r.detail)
        r, _ = self.play(QueueWorld(roles=()))
        self.assertEqual(r.status, TX.SKIP)
        self.assertIn('no role', r.detail)

    def test_no_answer_from_the_window(self):
        io = QueueIO(QueueWorld())
        io.w.request = lambda *a, **k: None
        r = run(TX.check_closed_party_finder(io, 'Tester Aaa', 'Warrior', 900))
        self.assertEqual(r.status, TX.SKIP)
        self.assertIn('not installed', r.detail)



# ------------------------------------------------------------------------------------------------ the siege, the guild boss and the rift (O592)
class SiegeWorld:
    """a tiny siege world on one lane (y = 5): the portal at x 100 (the temple at x 92), the base of each guild at x 10, its gate at x 20, the
    obelisk at x 60 (radius 2). It answers `!tester siege ...` as the helper does (the guide's rules in miniature), moves the bots by their
    steps, takes a bot through the portal and the gate when it steps on them, scores the hold and calls a tie contested. Time does not pass."""
    PORTAL, TEMPLE, GATE, CENTER, RADIUS = 100, (92, 3), 20, 60, 2

    def __init__(self, on=True, started=True, why='players are signed up for the next siege', refuse_portal=False, no_path=False, level=900,
                 side='tester', no_contest=False, no_score=False, blocked=(), running=False, guilds=('Tester Guild Alfa', 'Tester Guild Bravo'),
                 no_portal_step=False):
        self.on, self.started, self.why, self.refuse_portal, self.no_path, self.level = on, started, why, refuse_portal, no_path, level
        self.side, self.no_contest, self.no_score, self.blocked, self.running = side, no_contest, no_score, set(blocked), running
        self.guilds, self.units, self.up, self.closed, self.teleports = guilds, {}, False, 0, 0
        self.score = 0
        self.no_portal_step = no_portal_step

    def unit(self, name):
        return self.units.setdefault(name, {'pos': (60, 60), 'inside': False, 'where': None})

    def pos(self, name):
        x, y = self.unit(name)['pos']
        return {'x': x, 'y': y, 'z': 7}

    def on_point(self, name):
        u = self.unit(name)
        return u['inside'] and u['where'] == 'arena' and abs(u['pos'][0] - self.CENTER) <= self.RADIUS

    def guide(self, name):
        u = self.unit(name)
        if not u['inside']:
            return None
        if u['where'] == 'base':
            return {'mode': 'walk', 'goal': {'x': self.GATE, 'y': 5, 'z': 7}, 'reach': [0, 0], 'area': 'gate', 'why': 'test'}
        if self.on_point(name):
            return {'mode': 'hold', 'goal': {'x': self.CENTER, 'y': 5, 'z': 7}, 'area': 'obelisk', 'why': 'test'}
        return {'mode': 'walk', 'goal': {'x': self.CENTER, 'y': 5, 'z': 7}, 'reach': [0, self.RADIUS], 'area': 'obelisk', 'why': 'test'}

    def facts(self, name):
        u = self.unit(name)
        guild = self.guilds[0] if name == 'Tester Aaa' else self.guilds[1]
        out = {'inside': u['inside'], 'level': self.level, 'minLevel': 100, 'pos': self.pos(name), 'on': self.on, 'running': self.up or self.running,
               'phase': 'match' if self.up else 'idle', 'side': self.side if self.up else None, 'guild': guild, 'signed': self.up,
               'portal': {'x': self.PORTAL, 'y': 5, 'z': 7} if self.up else None}
        if u['inside']:
            both = [n for n, v in self.units.items() if self.on_point(n)]
            contested = len(both) == 2 and not self.no_contest
            holder = '' if len(both) != 1 else ('Tester Guild Alfa' if both[0] == 'Tester Aaa' else 'Tester Guild Bravo')
            out.update({'where': u['where'], 'bracket': 1, 'center': {'x': self.CENTER, 'y': 5, 'z': 7}, 'gate': {'x': self.GATE, 'y': 5, 'z': 7},
                        'onPoint': self.on_point(name), 'downed': False, 'members': 1, 'holder': holder, 'contested': contested,
                        'team': {'name': guild, 'score': self.score if name == 'Tester Aaa' else 0, 'kills': 0},
                        'rivals': [{'name': 'x', 'score': 0, 'kills': 0}], 'you': {'points': self.score, 'kills': 0, 'deaths': 0},
                        'guide': self.guide(name)})
        return out

    def tick(self):
        """one second of the siege: the hold scores for the guild that stands on the obelisk alone"""
        on = [n for n in self.units if self.on_point(n)]
        if on == ['Tester Aaa'] and not self.no_score:
            self.score += 1

    def path_to(self, name, goal, reach):
        x, y = self.unit(name)['pos']
        dirs = [2] * max(0, 5 - y) + [0] * max(0, y - 5)
        if x < goal - reach:
            dirs += [1] * (goal - reach - x)
        elif x > goal + reach:
            dirs += [3] * (x - goal - reach)
        return dirs

    def answer(self, name, command):
        u = self.unit(name)
        if command == 'siege state':
            self.tick() if name == 'Tester Aaa' else None
            return self.facts(name)
        if command == 'siege start':
            if not self.started:
                return {'started': False, 'why': self.why}
            self.up = True
            return {'started': True}
        if command == 'siege path':
            if u['inside']:
                g = self.guide(name)
                if g['mode'] != 'walk':
                    return dict(self.facts(name), err='no goal')
                return dict(self.facts(name), path=self.path_to(name, g['goal']['x'], g['reach'][1]), dist=abs(u['pos'][0] - g['goal']['x']))
            dist = max(abs(u['pos'][0] - self.PORTAL), abs(u['pos'][1] - 5))
            base = {'pos': self.pos(name), 'dest': {'x': self.PORTAL, 'y': 5, 'z': 7}, 'dist': dist}
            if dist <= 1:
                return dict(base, here=True, path=[])
            if self.no_path:
                return dict(self.facts(name), err='no path')
            return dict(base, path=self.path_to(name, self.PORTAL, 1))
        if command == 'siege portal':
            self.teleports += 1
            u['pos'] = (self.PORTAL - 1, 5)
            return self.facts(name)
        if command == 'siege close':
            for v in self.units.values():
                v['inside'] = False
            was, self.up = self.up, False
            self.closed += 1
            return dict(self.facts(name), closed=was)
        return None

    def step(self, name, dx, dy):
        u = self.unit(name)
        nx, ny = u['pos'][0] + dx, u['pos'][1] + dy
        if (nx, ny) in self.blocked or not (-1 <= nx <= 200):
            return
        u['pos'] = (nx, ny)
        if not u['inside'] and (nx, ny) == (self.PORTAL, 5) and self.up and not self.refuse_portal and not self.no_portal_step:
            u.update(inside=True, where='base', pos=(10, 5))
        elif u['inside'] and u['where'] == 'base' and (nx, ny) == (self.GATE, 5):
            u.update(where='arena', pos=(self.GATE + 2, 5))


class SiegeIO(ClosedIO):
    def __init__(self, world, me='Tester Aaa', **kw):
        super().__init__(**kw)
        self.w, self.me, self.modes, self.cmds = world, me, [], []

    async def helper(self, command, kind, wait=4.0):
        self.cmds.append((self.me, command))
        return self.w.answer(self.me, command)

    async def helper_of(self, other, command, kind, wait=4.0):
        self.cmds.append((other, command))
        return self.w.answer(other, command)

    async def go(self, place):
        self.moves.append(place)
        self.w.unit(self.me)['pos'] = self.w.TEMPLE
        return True

    async def go_of(self, other, place):
        self.w.unit(other)['pos'] = self.w.TEMPLE
        return True

    async def step(self, dx, dy):
        self.w.step(self.me, dx, dy)

    async def step_of(self, other, dx, dy):
        self.w.step(other, dx, dy)

    def raid_mode(self, names, on, keep_flee=False):
        self.modes.append((list(names), on, keep_flee))


ALFA = {'guild': 'Tester Guild Alfa', 'leader': True, 'rival': 'Tester Guild Bravo', 'rival_leader': 'Tester Bbb'}


class SiegeClosed(unittest.TestCase):
    def setUp(self):
        TX.reset_siege_turn()

    def tearDown(self):
        TX.reset_siege_turn()

    def play(self, world, name='Tester Aaa', plan=ALFA, **kw):
        io = SiegeIO(world, me=name, plan=plan, **kw)
        return run(TX.check_closed_siege(io, name, 'Warrior', 900)), io

    def test_pure_parts(self):
        a = {'on': True, 'guild': 'Tester Guild Alfa', 'level': 900, 'minLevel': 100}
        self.assertIsNone(TX.siege_refusal(a))
        for bad, word in ((None, 'old helper'), ({'err': 'no siege system'}, 'no siege system'), (dict(a, on=False), 'switch'),
                          (dict(a, running=True), 'running already'), (dict(a, inside=True), 'inside'), (dict(a, guild=None), 'no tester guild'),
                          (dict(a, level=50), 'level 50')):
            r = TX.siege_refusal(bad)
            self.assertEqual(r[0], TX.SKIP)
            self.assertIn(word, r[1])
        self.assertEqual(TX.siege_problems({'inside': True, 'side': 'tester'}), [])
        self.assertEqual(TX.siege_problems({'inside': False, 'side': 'player'}), [])
        self.assertTrue(TX.siege_problems({'inside': True, 'side': 'player'}))
        base = {'both': True, 'secs': 100, 'steps': 40, 'came': 'foot', 'guild': 'A', 'rival': 'B', 'score': 5, 'contested': True}
        self.assertEqual(TX.siege_verdict(dict(base, faults=['x']))[0], TX.FAIL)
        self.assertEqual(TX.siege_verdict(base)[0], TX.PASS)
        self.assertEqual(TX.siege_verdict(dict(base, both=False))[0], TX.SKIP)
        self.assertEqual(TX.siege_verdict(dict(base, stuck=(1, 2)))[0], TX.SKIP)
        self.assertEqual(TX.siege_verdict(dict(base, contested=False))[0], TX.SKIP)
        self.assertEqual(TX.siege_verdict(dict(base, score=0, contested=False, held=9))[0], TX.FAIL)
        self.assertEqual(TX.siege_verdict(dict(base, score=0, contested=False))[0], TX.SKIP)
        self.assertIn('siege portal (no path)', TX.siege_verdict(dict(base, fallbacks=['siege portal (no path)']))[1])
        self.assertIn('closed_siege', TX.CLOSED_KEYS)
        self.assertNotIn('closed_siege', TX.KEYS)
        self.assertLess(TX.CLOSED_KEYS.index('closed_dungeon'), TX.CLOSED_KEYS.index('closed_siege'))
        self.assertLess(TX.CLOSED_KEYS.index('closed_siege'), TX.CLOSED_KEYS.index('closed_raid'))
        self.assertEqual(TX.CLOSED_KEYS[-1], 'closed_raid')

    def test_a_siege_played_on_foot_is_a_pass(self):
        r, io = self.play(SiegeWorld())
        self.assertEqual(r.status, TX.PASS, r.detail)
        self.assertIn('contested', r.detail)
        self.assertEqual(r.fallbacks, [])
        self.assertEqual(io.w.teleports, 0)
        self.assertEqual(io.w.closed, 1)
        self.assertEqual(io.w.up, False)
        self.assertGreater(io.w.score, 0)
        self.assertEqual(io.modes[0], (['Tester Aaa', 'Tester Bbb'], True, False))
        self.assertEqual(io.modes[-1], (['Tester Aaa', 'Tester Bbb'], False, False))
        cmds = [c for _, c in io.cmds]
        self.assertLess(cmds.index('siege start'), cmds.index('siege path'))
        self.assertTrue(all(c != 'siege portal' for c in cmds), 'no helper step next to the portal when the path works')

    def test_the_rival_waits_for_the_first_guild_to_score(self):
        w = SiegeWorld()
        r, io = self.play(w)
        self.assertEqual(r.status, TX.PASS)
        # the rival (Bbb) never stood on the point before the runner (Aaa) held it alone
        self.assertGreaterEqual(w.score, TX.SIEGE_HOLD_FIRST)

    def test_no_path_to_the_portal_is_a_counted_fallback(self):
        r, io = self.play(SiegeWorld(no_path=True))
        self.assertEqual(r.status, TX.PASS, r.detail)
        self.assertEqual(io.w.teleports, 2)
        self.assertEqual(len(r.fallbacks), 2)
        self.assertIn('siege portal (no path)', r.fallbacks[0])
        self.assertIn('teleport in place of walking', r.detail)

    def test_skips(self):
        for world, word in ((SiegeWorld(on=False), 'switch'), (SiegeWorld(running=True), 'running already'),
                            (SiegeWorld(level=50), 'level 50'), (SiegeWorld(started=False), 'did not start: players are signed up')):
            r, io = self.play(world)
            self.assertEqual(r.status, TX.SKIP)
            self.assertIn(word, r.detail)
        r, _ = self.play(SiegeWorld(), plan=None)
        self.assertEqual((r.status, 'no tester guild' in r.detail), (TX.SKIP, True))
        r, _ = self.play(SiegeWorld(), plan=dict(ALFA, leader=False))
        self.assertEqual((r.status, 'not the leader' in r.detail), (TX.SKIP, True))
        r, _ = self.play(SiegeWorld(), bot_up=False)
        self.assertEqual((r.status, 'not in game' in r.detail), (TX.SKIP, True))
        TX.SIEGE_STUCK = 4.0
        r, _ = self.play(SiegeWorld(blocked={(x, y) for x in range(0, 40) for y in range(0, 12)} - {(10, 5)}))
        self.assertEqual(r.status, TX.SKIP)
        self.assertIn('blocked', r.detail)
        TX.SIEGE_STUCK = 30.0

    def test_one_siege_check_at_a_time(self):
        r, _ = self.play(SiegeWorld())
        self.assertEqual(r.status, TX.PASS)
        # the other leader's own check is the rival of the first: its result is the siege's
        r2, _ = self.play(SiegeWorld(), name='Tester Bbb', plan=dict(ALFA, guild='Tester Guild Bravo', rival='Tester Guild Alfa', rival_leader='Tester Aaa'))
        self.assertEqual(r2.status, TX.SKIP)
        self.assertIn('played as the rival leader of Tester Aaa', r2.detail)
        TX.reset_siege_turn()
        TX.SIEGE_TURN['by'] = 'Tester Ccc'
        r3, _ = self.play(SiegeWorld())
        self.assertEqual(r3.status, TX.SKIP)
        self.assertIn('played by Tester Ccc', r3.detail)

    def test_bugs(self):
        r, io = self.play(SiegeWorld(refuse_portal=True))
        self.assertEqual(r.status, TX.FAIL)
        self.assertIn('did not take', r.detail)
        self.assertEqual(io.w.closed, 1)
        r, _ = self.play(SiegeWorld(no_contest=True))
        self.assertEqual(r.status, TX.FAIL)
        self.assertIn('never called it contested', r.detail)
        self.assertIn('BUG closed_siege', r.bug_line())
        r, _ = self.play(SiegeWorld(no_score=True))
        self.assertEqual(r.status, TX.FAIL)
        self.assertIn('scored 0', r.detail)
        r, _ = self.play(SiegeWorld(side='player'))
        self.assertEqual(r.status, TX.FAIL)
        self.assertIn('must be the testers', r.detail)

    def test_the_siege_is_closed_when_the_bot_is_gone(self):
        io = SiegeIO(SiegeWorld(), plan=ALFA)
        real = io.alive
        n = {'k': 0}

        def alive():
            n['k'] += 1
            return n['k'] < 40
        io.alive = alive
        r = run(TX.check_closed_siege(io, 'Tester Aaa', 'Warrior', 900))
        self.assertEqual(io.w.closed, 1, 'the siege is closed even when the check is cut off')
        del real


class GuildBossWorld:
    """a tiny guild boss world on one lane (y = 5): the Guild Hall Portal at x 100 (the temple at x 92), the stone at x 80 in the hall, the
    arena entry at x 0 and the boss at x 40. It answers `!tester guildboss ...`, the guild window's buyHall and the stone's requests as the
    server does (a free hall, a stone of 5 embers, a boss that comes a few looks after the summon) and moves the bot by its steps."""
    PORTAL, TEMPLE, STONE, BOSS = 100, (92, 3), 80, 40

    def __init__(self, has_hall=False, buy_refused=False, level=900, rank=3, on=True, board=('Tester Guild Alfa',), side='tester', no_fuel=False,
                 summon_refused='', never_boss=False, never_hurt=False, no_path=False, killed=False, hall_stuck=False, tester_flag=True,
                 boss_after=3, kill_after=5, blocked=(), no_orb=False):
        self.has_hall, self.buy_refused, self.level, self.rank, self.on, self.board, self.side = has_hall, buy_refused, level, rank, on, board, side
        self.no_fuel, self.summon_refused, self.never_boss, self.never_hurt, self.no_path = no_fuel, summon_refused, never_boss, never_hurt, no_path
        self.killed, self.hall_stuck, self.tester_flag, self.boss_after, self.kill_after = killed, hall_stuck, tester_flag, boss_after, kill_after
        self.blocked, self.no_orb = set(blocked), no_orb
        self.pos, self.in_hall, self.inside, self.fuel, self.orbs, self.looks, self.hp = (60, 60), False, False, 0, 0, 0, 100
        self.closed, self.teleports, self.asked, self.boss_up, self.summoned_at = 0, 0, [], False, None

    def guide(self):
        if not self.inside:
            return None
        if not self.boss_up:
            return {'mode': 'wait', 'why': 'the boss is coming'}
        if abs(self.pos[0] - self.BOSS) <= 5:
            return {'mode': 'fight', 'goal': {'x': self.BOSS, 'y': 5, 'z': 7}, 'area': 'boss', 'why': 'test'}
        return {'mode': 'walk', 'goal': {'x': self.BOSS, 'y': 5, 'z': 7}, 'reach': [1, 5], 'area': 'boss', 'why': 'test'}

    def facts(self):
        out = {'inside': self.inside, 'level': self.level, 'minLevel': 150, 'pos': {'x': self.pos[0], 'y': self.pos[1], 'z': 7}, 'on': self.on,
               'guild': 'Tester Guild Alfa', 'rank': self.rank, 'side': self.side, 'hasHall': self.has_hall, 'inHall': self.in_hall,
               'fuel': self.fuel, 'need': 5, 'attempts': 0, 'maxAttempts': 3, 'killed': self.killed, 'running': self.inside,
               'canSummon': self.has_hall and self.in_hall and self.fuel >= 5 and not self.inside,
               'reason': 'The stone holds %d of 5 embers.' % self.fuel, 'stone': {'x': self.STONE, 'y': 5, 'z': 7} if self.has_hall else None,
               'board': list(self.board)}
        if self.inside:
            out['run'] = {'state': 'running', 'boss': 'alive' if self.boss_up else 'waiting', 'tester': self.tester_flag, 'lives': 3,
                          'bossPos': {'x': self.BOSS, 'y': 5, 'z': 7} if self.boss_up else None, 'bossHp': self.hp if self.boss_up else None,
                          'gate': {'x': 2, 'y': 5, 'z': 7}}
            out['guide'] = self.guide()
        return out

    def tick(self):
        if not self.inside:
            return
        self.looks += 1
        if not self.boss_up and self.looks >= self.boss_after and not self.never_boss:
            self.boss_up = True
        g = self.guide()
        if g and g['mode'] == 'fight' and not self.never_hurt:
            self.hp = max(0, self.hp - 100 // self.kill_after)
            if self.hp <= 0:
                self.boss_up = False
                self.won = True

    def path_to(self, goal, reach):
        x, y = self.pos
        dirs = [2] * max(0, 5 - y) + [0] * max(0, y - 5)
        if x < goal - reach:
            dirs += [1] * (goal - reach - x)
        elif x > goal + reach:
            dirs += [3] * (x - goal - reach)
        return dirs

    def answer(self, command):
        if command == 'guildboss state':
            self.tick()
            return self.facts()
        if command == 'guildboss path':
            if self.no_path and not self.inside:
                return dict(self.facts(), err='no path')
            if self.inside:
                g = self.guide()
                if g['mode'] != 'walk':
                    return dict(self.facts(), err='no goal')
                return dict(self.facts(), path=self.path_to(g['goal']['x'], 5), dist=abs(self.pos[0] - self.BOSS))
            dest = self.STONE if self.in_hall else self.PORTAL
            dist = max(abs(self.pos[0] - dest), abs(self.pos[1] - 5))
            base = {'pos': {'x': self.pos[0], 'y': self.pos[1], 'z': 7}, 'dest': {'x': dest, 'y': 5, 'z': 7}, 'dist': dist,
                    'target': 'stone' if self.in_hall else 'hall'}
            if dist <= 1:
                return dict(self.facts(), **dict(base, here=True, path=[]))
            return dict(self.facts(), **dict(base, path=self.path_to(dest, 1)))
        if command == 'guildboss hall':
            self.teleports += 1
            self.in_hall = True
            self.pos = (self.STONE - 3, 5)
            return self.facts()
        if command == 'guildboss close':
            was = self.inside
            self.inside = False
            self.closed += 1
            return dict(self.facts(), closed=was)
        if command == 'give orb chaos 1':
            if self.no_orb:
                return {'err': 'no orb chaos'}
            self.orbs += 1
            return {'what': 'orb', 'id': 29856, 'count': 1}
        if command == 'bag':
            return {'potions': 100}
        return None

    def request(self, opname, action, data=None):
        self.asked.append((opname, action, data))
        if (opname, action) == ('guild', 'buyHall'):
            if self.buy_refused:
                return {'action': 'message', 'data': {'ok': False, 'text': 'Your guild needs guild level 5 for a guild hall.'}}
            self.has_hall = True
            return {'action': 'message', 'data': {'ok': True, 'text': 'Your guild owns a guild hall now (free for the test guilds).'}}
        if (opname, action) == ('guildWar', 'bossItem'):
            if self.orbs and not self.no_fuel:
                self.orbs -= 1
                self.fuel += 5
            return {'action': 'message', 'data': {'ok': True, 'text': 'You fed the Summoning Stone 1 x Orb of Upheaval: 5 embers.'}}
        if (opname, action) == ('guildWar', 'bossSummon'):
            if self.summon_refused:
                return {'action': 'message', 'data': {'ok': False, 'text': self.summon_refused}}
            if self.fuel >= 5 and self.in_hall:
                self.fuel -= 5
                self.inside, self.pos, self.looks, self.boss_up, self.hp = True, (0, 5), 0, False, 100
            return {'action': 'message', 'data': {'ok': True, 'text': 'Gorvath is coming.'}}
        if (opname, action) == ('guildWar', 'open'):
            return {'action': 'state', 'data': {}}
        return None

    def step(self, dx, dy):
        nx, ny = self.pos[0] + dx, self.pos[1] + dy
        if (nx, ny) in self.blocked or not (-1 <= nx <= 200):
            return
        self.pos = (nx, ny)
        if not self.in_hall and (nx, ny) == (self.PORTAL, 5) and self.has_hall and not self.hall_stuck:
            self.in_hall, self.pos = True, (self.STONE - 10, 5)


class GuildBossIO(FakeIO):
    def __init__(self, world, **kw):
        super().__init__(**kw)
        self.w, self.modes, self.cmds, self.looted = world, [], [], 0

    async def helper(self, command, kind, wait=4.0):
        self.cmds.append(command)
        return self.w.answer(command)

    async def request(self, opname, action, data, expect, timeout):
        self.asked.append((opname, action, data))
        return self.w.request(opname, action, data)

    async def go(self, place):
        self.moves.append(place)
        self.w.pos = self.w.TEMPLE
        return True

    async def step(self, dx, dy):
        self.w.step(dx, dy)

    async def loot(self):
        self.looted += 1

    def raid_mode(self, names, on, keep_flee=False):
        self.modes.append((list(names), on, keep_flee))


class GuildBossClosed(unittest.TestCase):
    def setUp(self):
        self.keep = (TX.GB_BUDGET, TX.GB_FIGHT_MIN, TX.GB_STUCK, TX.GB_BOSS_WAIT)

    def tearDown(self):
        TX.GB_BUDGET, TX.GB_FIGHT_MIN, TX.GB_STUCK, TX.GB_BOSS_WAIT = self.keep

    def play(self, world, name='Tester Aaa', level=900):
        io = GuildBossIO(world)
        return run(TX.check_closed_guildboss(io, name, 'Warrior', level)), io

    def test_pure_parts(self):
        a = {'on': True, 'guild': 'Tester Guild Alfa', 'rank': 3, 'level': 900, 'minLevel': 150}
        self.assertIsNone(TX.guildboss_refusal(a))
        for bad, word in ((None, 'old helper'), ({'err': 'no guild boss system'}, 'no guild boss system'), (dict(a, on=False), 'switch'),
                          (dict(a, inside=True), 'inside'), (dict(a, guild=None), 'no tester guild'), (dict(a, rank=1), 'leader'),
                          (dict(a, level=100), 'level 100'), (dict(a, killed=True), 'slew'), (dict(a, running=True), 'fighting')):
            r = TX.guildboss_refusal(bad)
            self.assertEqual(r[0], TX.SKIP)
            self.assertIn(word, r[1])
        self.assertEqual(TX.guildboss_problems({'guild': 'Tester Guild Alfa', 'side': 'tester', 'board': ['Tester Guild Alfa'],
                                                'run': {'tester': True}}), [])
        self.assertEqual(TX.guildboss_problems({}), [])
        self.assertTrue(TX.guildboss_problems({'guild': 'x', 'side': 'player'}))
        self.assertTrue(TX.guildboss_problems({'board': ['Ashen Wolves']}))
        self.assertTrue(TX.guildboss_problems({'run': {'tester': False}}))
        base = {'secs': 100, 'steps': 30, 'fuel': 5, 'need': 5, 'came': 'foot', 'boss_seen': True, 'hp': 60}
        self.assertEqual(TX.guildboss_verdict(dict(base, faults=['x']))[0], TX.FAIL)
        self.assertEqual(TX.guildboss_verdict(base)[0], TX.PASS)
        self.assertEqual(TX.guildboss_verdict(dict(base, hp=100, won=True))[0], TX.PASS)
        self.assertEqual(TX.guildboss_verdict(dict(base, hp=100, fought=TX.GB_FIGHT_MIN))[0], TX.FAIL)
        self.assertEqual(TX.guildboss_verdict(dict(base, hp=100, stuck=(1, 2)))[0], TX.SKIP)
        self.assertEqual(TX.guildboss_verdict(dict(base, hp=100, died=True))[0], TX.SKIP)
        self.assertEqual(TX.guildboss_verdict(dict(base, hp=100))[0], TX.SKIP)
        self.assertEqual(TX.guildboss_verdict(dict(base, boss_seen=False))[0], TX.FAIL)
        self.assertEqual(TX.guildboss_verdict(dict(base, boss_seen=False, died=True))[0], TX.SKIP)
        self.assertIn('guildboss hall (no path)', TX.guildboss_verdict(dict(base, fallbacks=['guildboss hall (no path)']))[1])
        self.assertIn('closed_guildboss', TX.CLOSED_KEYS)
        self.assertNotIn('closed_guildboss', TX.KEYS)
        self.assertLess(TX.CLOSED_KEYS.index('closed_guildboss'), TX.CLOSED_KEYS.index('closed_raid'))
        self.assertEqual(TX.window_text({'data': {'text': 'x' * 200}}), 'x' * 90)
        self.assertEqual(TX.window_text(None), '')

    def test_a_guild_boss_played_on_foot_is_a_pass(self):
        r, io = self.play(GuildBossWorld())
        self.assertEqual(r.status, TX.PASS, r.detail)
        self.assertIn('Gorvath', r.detail)
        self.assertEqual(r.fallbacks, [])
        self.assertEqual(io.w.teleports, 0)
        self.assertGreaterEqual(io.w.closed, 1)
        self.assertEqual(io.w.inside, False)
        asked = [(o, a) for o, a, _ in io.asked]
        self.assertEqual([x for x in asked if x[1] in ('buyHall', 'bossItem', 'bossSummon')],
                         [('guild', 'buyHall'), ('guildWar', 'bossItem'), ('guildWar', 'bossSummon')], 'the window, in a person\'s order')
        self.assertIn(('guildWar', 'bossItem', {'key': 'upheaval'}), io.asked)
        self.assertEqual(io.modes[0], (['Tester Aaa'], True, False))
        self.assertEqual(io.modes[-1], (['Tester Aaa'], False, False))
        self.assertGreater(io.looted, -1)

    def test_a_hall_that_is_there_is_not_bought_again(self):
        r, io = self.play(GuildBossWorld(has_hall=True))
        self.assertEqual(r.status, TX.PASS, r.detail)
        self.assertNotIn(('guild', 'buyHall'), [(o, a) for o, a, _ in io.asked])

    def test_the_hall_by_the_portals_entry_is_a_counted_fallback(self):
        r, io = self.play(GuildBossWorld(hall_stuck=True))
        self.assertEqual(r.status, TX.PASS, r.detail)
        self.assertEqual(io.w.teleports, 1)
        self.assertEqual(len(r.fallbacks), 1)
        self.assertIn('guildboss hall', r.fallbacks[0])
        r, io = self.play(GuildBossWorld(no_path=True))
        self.assertEqual(r.status, TX.PASS, r.detail)
        self.assertIn('no path', r.fallbacks[0])

    def test_skips(self):
        for world, word in ((GuildBossWorld(on=False), 'switch'), (GuildBossWorld(level=100), 'level 100'), (GuildBossWorld(rank=1), 'leader'),
                            (GuildBossWorld(killed=True), 'slew'), (GuildBossWorld(no_orb=True), 'Orb of Upheaval'),
                            (GuildBossWorld(summon_refused='The testers\' guild boss waits: the arenas are kept for the players.'), 'kept for the players'),
                            (GuildBossWorld(summon_refused='Closed test mode is off: the testers do not play this.'), 'Closed test mode')):
            r, _ = self.play(world)
            self.assertEqual(r.status, TX.SKIP, (word, r.detail))
            self.assertIn(word, r.detail)

    def test_bugs(self):
        r, _ = self.play(GuildBossWorld(buy_refused=True))
        self.assertEqual(r.status, TX.FAIL)
        self.assertIn('could not buy its free hall', r.detail)
        self.assertIn('BUG closed_guildboss', r.bug_line())
        r, _ = self.play(GuildBossWorld(no_fuel=True))
        self.assertEqual(r.status, TX.FAIL)
        self.assertIn('holds 0 of 5', r.detail)
        r, _ = self.play(GuildBossWorld(board=('Tester Guild Alfa', 'Ashen Wolves')))
        self.assertEqual(r.status, TX.FAIL)
        self.assertIn('Ashen Wolves', r.detail)
        r, _ = self.play(GuildBossWorld(side='player'))
        self.assertEqual(r.status, TX.FAIL)
        r, _ = self.play(GuildBossWorld(tester_flag=False))
        self.assertEqual(r.status, TX.FAIL)
        self.assertIn('run of players', r.detail)
        TX.GB_BOSS_WAIT = 6.0
        r, io = self.play(GuildBossWorld(never_boss=True))
        self.assertEqual(r.status, TX.FAIL)
        self.assertIn('did not appear', r.detail)
        self.assertEqual(io.w.inside, False, 'the run is closed')
        TX.GB_FIGHT_MIN = 8.0
        r, _ = self.play(GuildBossWorld(never_hurt=True))
        self.assertEqual(r.status, TX.FAIL)
        self.assertIn('took none of its health', r.detail)

    def test_walks_blocked_and_the_budget(self):
        TX.GB_STUCK = 5.0
        r, _ = self.play(GuildBossWorld(blocked={(x, y) for x in range(0, 40) for y in range(0, 12)} - {(0, 5)}))
        self.assertEqual(r.status, TX.SKIP)
        self.assertIn('blocked', r.detail)
        TX.GB_STUCK = self.keep[2]
        TX.GB_BUDGET = 12.0
        r, io = self.play(GuildBossWorld(never_hurt=True))
        self.assertIn(r.status, (TX.SKIP, TX.PASS))
        self.assertEqual(io.w.inside, False, 'closed at the end of the time')


class RiftWorld:
    """a tiny rift world on one lane (y = 5): the temple at x 92 (a protection zone within 3 tiles), the bot hunting at x 60, a rift whose
    monsters stand at x 10, 20, 30 and the guardian at x 50. `!tester path temple`, `rift ...` as the helper answers them; using the key
    in the zone opens the rift (the bot arrives at x 0), `rift close` ends it."""
    TEMPLE = 92

    def __init__(self, level=900, in_zone=False, no_path=False, no_key=False, bag_full=False, never_open=False, never_kill=False, floor=False,
                 blocked=(), kill_after=2, tier=3, err=None, key_err=None):
        self.level, self.in_zone, self.no_path, self.no_key, self.bag_full, self.never_open = level, in_zone, no_path, no_key, bag_full, never_open
        self.never_kill, self.floor, self.blocked, self.kill_after, self.tier, self.err, self.key_err = never_kill, floor, set(blocked), kill_after, tier, err, key_err
        self.pos = (self.TEMPLE if in_zone else 60, 5)
        self.key, self.inside, self.killed, self.hp, self.monsters = False, False, 0, {}, [10, 20, 30]
        self.boss_hp, self.closed, self.teleports, self.used = 100, 0, 0, 0

    def pz(self):
        return abs(self.pos[0] - self.TEMPLE) <= 3 and abs(self.pos[1] - 3) <= 3

    def alive(self):
        return [m for m in self.monsters if self.hp.get(m, 1) > 0]

    def guide(self):
        if not self.inside:
            return None
        alive = self.alive()
        if not alive and self.boss_hp > 0 and self.killed >= 1 and True:
            g = ('fight' if abs(self.pos[0] - 50) <= 4 else 'walk')
            return {'mode': g, 'goal': {'x': 50, 'y': 5, 'z': 7}, 'reach': [1, 4], 'area': 'boss', 'why': 'test'}
        if not alive:
            return {'mode': 'wait', 'why': 'nothing to do'}
        goal = min(alive, key=lambda m: abs(m - self.pos[0]))
        z = 6 if self.floor else 7
        return {'mode': 'fight' if abs(self.pos[0] - goal) <= 4 and not self.floor else 'walk', 'goal': {'x': goal, 'y': 5, 'z': z}, 'reach': [1, 4], 'area': 'pack',
                'why': 'test'}

    def facts(self):
        out = {'inside': self.inside, 'level': self.level, 'pos': {'x': self.pos[0], 'y': self.pos[1], 'z': 7}, 'pz': self.pz(), 'held': self.key,
               'tier': self.tier}
        if self.inside:
            out['run'] = {'id': 1, 'tier': self.tier, 'theme': 'ash', 'kind': 'rooms', 'state': 'running',
                          'boss': 'alive' if not self.alive() and self.killed else 'waiting', 'killed': self.killed, 'total': 3, 'bossAt': 3,
                          'floors': 1, 'monsters': len(self.alive()), 'bossHp': self.boss_hp if not self.alive() else None}
            out['guide'] = self.guide()
        return out

    def tick(self):
        if not self.inside or self.never_kill:
            return
        g = self.guide()
        if not g or g['mode'] != 'fight':
            return
        x = g['goal']['x']
        if g['area'] == 'boss':
            self.boss_hp = max(0, self.boss_hp - 100 // self.kill_after)
            return
        self.hp[x] = self.hp.get(x, 1.0) - 1.0 / self.kill_after
        if self.hp[x] <= 0:
            self.killed += 1

    def path_to(self, goal, reach):
        x, y = self.pos
        dirs = [2] * max(0, 5 - y) + [0] * max(0, y - 5)
        if x < goal - reach:
            dirs += [1] * (goal - reach - x)
        elif x > goal + reach:
            dirs += [3] * (x - goal - reach)
        return dirs

    def answer(self, command):
        if command == 'rift state':
            if self.err:
                return {'err': self.err}
            self.tick()
            return self.facts()
        if command == 'path temple':
            if self.no_path:
                return {'err': 'no path', 'dest': {'x': self.TEMPLE, 'y': 5, 'z': 7}}
            dist = max(abs(self.pos[0] - self.TEMPLE), abs(self.pos[1] - 5))
            base = {'pos': {'x': self.pos[0], 'y': self.pos[1], 'z': 7}, 'dest': {'x': self.TEMPLE, 'y': 5, 'z': 7}, 'dist': dist}
            if dist <= 1:
                return dict(base, here=True, path=[])
            return dict(base, path=self.path_to(self.TEMPLE, 1))
        if command == 'enter temple':
            self.teleports += 1
            self.pos = (self.TEMPLE - 1, 5)
            return {'kind': 'temple', 'pos': {'x': self.pos[0], 'y': self.pos[1], 'z': 7}}
        if command.startswith('rift key'):   # O661: `rift key N`, the tier of the level warning
            if self.key_err:
                return dict(self.facts(), err=self.key_err)
            if not self.pz():
                return dict(self.facts(), err='not in a protection zone')
            self.key = not self.no_key and not self.bag_full
            return dict(self.facts(), held=self.key, keyClientId=20155, bagFull=True if self.bag_full else None)
        if command == 'rift path':
            g = self.guide()
            if not self.inside or not g or g['mode'] != 'walk':
                return dict(self.facts(), err='no goal' if self.inside else 'not inside a rift')
            if self.floor:
                return dict(self.facts(), err='another floor')
            return dict(self.facts(), path=self.path_to(g['goal']['x'], g['reach'][1]), dist=abs(self.pos[0] - g['goal']['x']))
        if command == 'rift close':
            was = self.inside
            self.inside, self.key = False, False
            self.closed += 1
            return dict(self.facts(), closed=was)
        return None

    def use(self):
        self.used += 1
        if self.key and self.pz() and not self.never_open:
            self.key, self.inside, self.pos = False, True, (0, 5)

    def step(self, dx, dy):
        nx, ny = self.pos[0] + dx, self.pos[1] + dy
        if (nx, ny) in self.blocked or not (-1 <= nx <= 200):
            return
        self.pos = (nx, ny)


class RiftIO(FakeIO):
    def __init__(self, world, **kw):
        super().__init__(**kw)
        self.w, self.modes, self.cmds, self.looted = world, [], [], 0

    async def helper(self, command, kind, wait=4.0):
        self.cmds.append(command)
        return self.w.answer(command)

    async def go(self, place):
        self.moves.append(place)
        if place == 'hunt':
            self.w.pos = (60, 5)
        return True

    async def step(self, dx, dy):
        self.w.step(dx, dy)

    async def use_item(self, client_id):
        self.w.use()
        return True

    async def loot(self):
        self.looted += 1

    def raid_mode(self, names, on, keep_flee=False):
        self.modes.append((list(names), on, keep_flee))


class RiftWalk(unittest.TestCase):
    def setUp(self):
        self.keep = (TX.RIFT_BUDGET, TX.RIFT_FIGHT_MIN, TX.RIFT_STUCK)

    def tearDown(self):
        TX.RIFT_BUDGET, TX.RIFT_FIGHT_MIN, TX.RIFT_STUCK = self.keep

    def play(self, world, level=900):
        io = RiftIO(world)
        return run(TX.check_rift_walk(io, 'Tester Aaa', 'Warrior', level)), io

    def test_the_verdict(self):
        base = {'tier': 3, 'theme': 'ash', 'came': 'foot', 'steps': 20, 'secs': 60, 'kills': 2}
        self.assertEqual(TX.rift_walk_verdict(dict(base, faults=['x']))[0], TX.FAIL)
        self.assertEqual(TX.rift_walk_verdict(base)[0], TX.PASS)
        self.assertEqual(TX.rift_walk_verdict(dict(base, kills=0, hp=70, boss_seen=True))[0], TX.PASS)
        self.assertEqual(TX.rift_walk_verdict(dict(base, kills=0, fought=TX.RIFT_FIGHT_MIN))[0], TX.FAIL)
        self.assertEqual(TX.rift_walk_verdict(dict(base, kills=0, floor=True))[0], TX.SKIP)
        self.assertEqual(TX.rift_walk_verdict(dict(base, kills=0, stuck=(1, 2)))[0], TX.SKIP)
        self.assertEqual(TX.rift_walk_verdict(dict(base, kills=0, died=True))[0], TX.SKIP)
        self.assertEqual(TX.rift_walk_verdict(dict(base, kills=0))[0], TX.SKIP)
        self.assertIn('enter temple (no path)', TX.rift_walk_verdict(dict(base, fallbacks=['enter temple (no path)']))[1])
        self.assertIn('rift_walk', TX.KEYS)
        self.assertNotIn('rift_walk', TX.CLOSED_KEYS)

    def test_a_rift_walked_from_the_hunt_is_a_pass(self):
        r, io = self.play(RiftWorld())
        self.assertEqual(r.status, TX.PASS, r.detail)
        self.assertEqual(r.fallbacks, [])
        self.assertEqual(io.w.teleports, 0, 'the bot walked to the temple')
        self.assertEqual(io.w.used, 1, 'the key was used once')
        self.assertEqual(io.w.closed, 1)
        self.assertFalse(io.w.inside)
        self.assertIn('walked to the temple', r.detail)
        self.assertEqual(io.moves[-1], 'hunt', 'back to the hunt')
        self.assertEqual(io.modes[0], (['Tester Aaa'], True, True))
        self.assertEqual(io.modes[-1], (['Tester Aaa'], False, False))
        self.assertGreater(io.looted, 0)
        cmds = io.cmds
        key = next(c for c in cmds if c.startswith('rift key'))
        self.assertLess(cmds.index('path temple'), cmds.index(key))
        self.assertLess(cmds.index(key), cmds.index('rift path'))

    def test_a_bot_in_the_zone_walks_nowhere(self):
        r, io = self.play(RiftWorld(in_zone=True))
        self.assertEqual(r.status, TX.PASS, r.detail)
        self.assertNotIn('path temple', io.cmds)

    def test_no_path_to_the_temple_is_a_counted_fallback(self):
        r, io = self.play(RiftWorld(no_path=True))
        self.assertEqual(r.status, TX.PASS, r.detail)
        self.assertEqual(io.w.teleports, 1)
        self.assertEqual(len(r.fallbacks), 1)
        self.assertIn('enter temple', r.fallbacks[0])
        self.assertIn('no path', r.fallbacks[0])
        self.assertIn('teleport in place of walking', r.detail)

    def test_skips(self):
        r, _ = self.play(RiftWorld(err='no rifts on this server'))
        self.assertEqual((r.status, 'no rifts' in r.detail), (TX.SKIP, True))
        r, _ = self.play(RiftWorld(tier=None, level=50))
        self.assertEqual((r.status, 'opens no rift' in r.detail), (TX.SKIP, True))
        r, io = self.play(RiftWorld(never_open=True))
        self.assertEqual(r.status, TX.SKIP)
        self.assertIn('did not open', r.detail)
        self.assertEqual(io.w.used, 3, 'the hotkey is sent again twice')
        self.assertEqual(io.w.closed, 1, 'the unused key is taken out again')
        r, _ = self.play(RiftWorld(bag_full=True))
        self.assertEqual((r.status, 'bag is full' in r.detail), (TX.SKIP, True))
        r, _ = self.play(RiftWorld(key_err='level too low for a rift'))
        self.assertEqual((r.status, 'level too low' in r.detail), (TX.SKIP, True))
        r, _ = self.play(RiftWorld(floor=True))
        self.assertEqual(r.status, TX.SKIP)
        self.assertIn('another floor', r.detail)
        TX.RIFT_STUCK = 5.0
        r, _ = self.play(RiftWorld(blocked={(x, y) for x in range(0, 60) for y in range(0, 12)} - {(0, 5)}))
        self.assertEqual(r.status, TX.SKIP)
        self.assertIn('blocked', r.detail)

    def test_bugs(self):
        r, io = self.play(RiftWorld(no_key=True))
        self.assertEqual(r.status, TX.FAIL)
        self.assertIn('backpack holds none', r.detail)
        self.assertIn('BUG rift_walk', r.bug_line())
        TX.RIFT_FIGHT_MIN = 8.0
        r, io = self.play(RiftWorld(never_kill=True))
        self.assertEqual(r.status, TX.FAIL)
        self.assertIn('killed none', r.detail)
        self.assertEqual(io.w.closed, 1, 'the run is closed')

    def test_the_budget_ends_the_walk(self):
        TX.RIFT_BUDGET = 6.0
        r, io = self.play(RiftWorld(never_kill=True))
        self.assertIn(r.status, (TX.SKIP, TX.PASS))
        self.assertEqual(io.w.closed, 1)
        self.assertEqual(io.moves[-1], 'hunt')

class SoloWorld:
    """a tower or a descent on one lane (y = 5): the temple at x 92, the bot hunting at x 60. `tower | descent state / path / close` and
    `path temple`, `enter temple` as the helper answers them; the window's requests (`enter`, `start`, `pick`, `ready`, `skip`) come through
    SoloIO.request. Looks advance the world: a floor or room starts, monsters die while the bot fights in reach, a cleared floor pays gold."""
    TEMPLE = 92
    FIGHT = 5

    def __init__(self, kind, level=900, pay='free', sigil_ok=True, no_path=False, never_open=False, never_kill=False, mixed=False, bank_stuck=False,
                 free=16, can_enter=True, inside=False, err=None, pz=True, start_text=None, stay_open=False, blocked=(), die_after=None,
                 puzzle=False, family='warrior', problem=None, boss_fall=True):
        self.kind, self.level, self.pay, self.sigil_ok, self.no_path, self.never_open = kind, level, pay, sigil_ok, no_path, never_open
        self.never_kill, self.mixed, self.bank_stuck, self.free, self.can_enter, self.err, self.pz = never_kill, mixed, bank_stuck, free, can_enter, err, pz
        self.start_text, self.stay_open, self.blocked, self.die_after = start_text, stay_open, set(blocked), die_after
        self.pos = (60, 5)
        self.inside, self.floor, self.cleared, self.bank = inside, 0, 0, 1000
        self.monsters, self.wait, self.state, self.offer = [], 0, 'fight', None
        self.closed, self.teleports, self.skips, self.picks, self.readies, self.sigils, self.starts, self.looks = 0, 0, 0, 0, 0, 0, 0, 0
        self.kinds = ['combat', 'shrine', 'combat', 'combat']
        self.ready = False
        self.depth = 0
        self.puzzle, self.family, self.problem, self.boss_fall = puzzle, family, problem, boss_fall
        self.stage, self.boss_hp, self.killed, self.won = 'wave', 100, 0, False

    # ---- the screen
    def facts(self):
        out = {'inside': self.inside, 'level': self.level, 'minLevel': 100, 'pos': {'x': self.pos[0], 'y': self.pos[1], 'z': 7}, 'free': self.free,
               'reserve': 4 if self.kind == 'tower' else 2, 'bank': self.bank}
        if self.kind == 'tower':
            out.update(canEnter=self.can_enter, floorGold=50, inArena=self.inside)
        elif self.kind == 'trial':
            out.update(pz=self.pz, family=self.family, familyName='The Iron Gauntlet', tier=1, cleared=0, maxTier=3, minLevel=100, problem=self.problem,
                       puzzle=True if self.puzzle else None, kinds=['wave', 'wave', 'boss'])
        else:
            out.update(pz=self.pz, pay=self.pay, sigils=self.sigils)
        if self.inside:
            out['run'] = self.run()
            out['guide'] = self.guide()
        return out

    def run(self):
        players = 2 if self.mixed else 1
        if self.kind == 'trial':
            return {'tier': 1, 'phase': 'fight', 'stage': 'seals' if self.puzzle else self.stage, 'stageIdx': 1 if self.stage == 'wave' else 3, 'stages': 3,
                    'killed': self.killed, 'total': 8, 'lives': 3, 'livesMax': 3, 'left': 400, 'monsters': len(self.alive()),
                    'boss': 'alive' if self.stage == 'boss' else 'waiting', 'bossHp': self.boss_hp if self.stage == 'boss' else None}
        if self.kind == 'tower':
            return {'floor': self.floor, 'cleared': self.cleared, 'remaining': len(self.alive()), 'monsters': len(self.alive()), 'waiting': self.wait > 0 or self.floor == 0,
                    'nextIn': self.wait, 'canSkip': self.wait > 0, 'players': players, 'testers': 1}
        return {'room': self.floor, 'rooms': 4, 'kind': self.kinds[max(0, self.floor - 1)], 'state': self.state, 'depth': self.depth, 'monsters': len(self.alive()),
                'players': players, 'testers': 1, 'offer': {'id': 7, 'cards': 3} if self.offer else None, 'ready': self.ready}

    def alive(self):
        return [m for m in self.monsters if m['hp'] > 0]

    def guide(self):
        if self.kind == 'trial':
            if self.puzzle:
                return {'mode': 'wait', 'area': 'puzzle', 'why': 'a seals stage'}
            if not self.alive():
                return {'mode': 'wait', 'why': 'no monster'}
        if self.kind == 'tower':
            if self.wait > 0 or self.floor == 0:
                return {'mode': 'wait', 'skip': True if self.wait > 0 else None, 'why': 'between floors'}
        else:
            if self.offer:
                return {'mode': 'pick', 'offer': 7, 'card': 1}
            if self.state == 'rest':
                return {'mode': 'wait', 'why': 'waiting for the party'} if self.ready else {'mode': 'ready', 'why': 'a room of rest'}
            if self.state != 'fight':
                return {'mode': 'wait', 'why': 'the door'}
        alive = self.alive()
        if not alive:
            return {'mode': 'wait', 'why': 'no monster'}
        goal = min(alive, key=lambda m: abs(m['x'] - self.pos[0]))
        near = abs(goal['x'] - self.pos[0]) <= self.FIGHT
        return {'mode': 'fight' if near else 'walk', 'goal': {'x': goal['x'], 'y': 5, 'z': 7}, 'reach': [1, self.FIGHT],
                'area': 'boss' if goal.get('boss') else 'pack', 'why': 'test'}

    def spawn(self):
        self.monsters = [{'x': self.pos[0] + 8, 'hp': 1.0}, {'x': self.pos[0] + 14, 'hp': 1.0}]

    def tick_trial(self):
        if self.floor == 0:
            self.floor = 1
            self.spawn()
            return
        g = self.guide()
        if g['mode'] != 'fight' or self.never_kill:
            return
        x = g['goal']['x']
        for m in self.monsters:
            if m['x'] == x and m['hp'] > 0:
                m['hp'] -= 0.5
                if m['hp'] <= 0:
                    self.killed += 1
        if not self.alive() and self.stage == 'wave':
            self.stage = 'boss'
            self.monsters = [{'x': self.pos[0] + 6, 'hp': 1.0, 'boss': True}]
        elif self.stage == 'boss' and self.boss_fall:
            self.boss_hp = max(0, int(self.monsters[0]['hp'] * 100))
            if not self.alive():
                self.inside = False

    def tick(self):
        if not self.inside:
            return
        self.looks += 1
        if self.die_after is not None and self.looks > self.die_after:
            self.inside = False
            return
        if self.kind == 'trial':
            self.tick_trial()
            return
        if self.kind == 'tower':
            if self.floor == 0 or self.wait > 0:
                self.wait = max(0, self.wait - 1)
                if self.wait == 0:
                    self.floor += 1
                    self.spawn()
                return
        else:
            if self.state == 'travel':
                self.floor += 1
                self.state = 'rest' if self.kinds[self.floor - 1] == 'shrine' else 'fight'
                self.ready = False
                if self.state == 'fight':
                    self.spawn()
                return
            if self.state != 'fight':
                return
            if self.floor == 0:
                self.floor = 1
                self.spawn()
                return
        g = self.guide()
        if g['mode'] != 'fight' or self.never_kill:
            return
        x = g['goal']['x']
        for m in self.monsters:
            if m['x'] == x and m['hp'] > 0:
                m['hp'] -= 0.5
        if not self.alive():
            self.cleared += 1
            if self.kind == 'tower':
                if not self.bank_stuck:
                    self.bank += 50 * self.cleared
                self.wait = 3
            else:
                self.depth = self.floor
                self.offer = True
                self.state = 'choose'

    def path_to(self, goal, reach):
        x, _ = self.pos
        if x < goal - reach:
            return [1] * (goal - reach - x)
        if x > goal + reach:
            return [3] * (x - goal - reach)
        return []

    def answer(self, command):
        kind = self.kind
        if command == '%s state' % kind:
            if self.err:
                return {'err': self.err}
            self.tick()
            return self.facts()
        if command == '%s path' % kind:
            g = self.guide() if self.inside else None
            if not g or g['mode'] != 'walk':
                return dict(self.facts(), err='no goal' if self.inside else 'not inside')
            return dict(self.facts(), path=self.path_to(g['goal']['x'], g['reach'][1]), dist=abs(self.pos[0] - g['goal']['x']))
        if command == '%s close' % kind:
            was = self.inside
            self.inside = False
            self.closed += 1
            return dict(self.facts(), closed=was)
        if command == 'descent sigil':
            self.sigils += 1
            if self.sigil_ok:
                self.pay = 'sigil'
            return dict(self.facts(), given=self.sigil_ok, err=None if self.sigil_ok else 'the sigil could not be made')
        if command == 'path temple':
            if self.no_path:
                return {'err': 'no path', 'dest': {'x': self.TEMPLE, 'y': 5, 'z': 7}}
            dist = abs(self.pos[0] - self.TEMPLE)
            base = {'pos': {'x': self.pos[0], 'y': 5, 'z': 7}, 'dest': {'x': self.TEMPLE, 'y': 5, 'z': 7}, 'dist': dist}
            return dict(base, here=True, path=[]) if dist <= 1 else dict(base, path=self.path_to(self.TEMPLE, 1))
        if command == 'enter temple':
            self.teleports += 1
            self.pos = (self.TEMPLE - 1, 5)
            return {'kind': 'temple', 'pos': {'x': self.pos[0], 'y': 5, 'z': 7}}
        return None

    def open(self):
        if self.never_open or self.inside:
            return None
        self.starts += 1
        self.inside, self.floor, self.state = True, 0, 'fight'
        self.pos = (30, 5)
        return True

    def step(self, dx, dy):
        nx = self.pos[0] + dx
        if (nx, self.pos[1] + dy) in self.blocked or not (-1 <= nx <= 200):
            return
        self.pos = (nx, self.pos[1] + dy)


class SoloIO(FakeIO):
    def __init__(self, world, **kw):
        super().__init__(**kw)
        self.w, self.modes, self.cmds, self.looted, self.sent = world, [], [], 0, []

    async def helper(self, command, kind, wait=4.0):
        self.cmds.append(command)
        return self.w.answer(command)

    async def go(self, place):
        self.moves.append(place)
        if place == 'hunt':
            self.w.pos = (60, 5)
        return True

    async def request(self, opname, action, data, expect, timeout):
        self.sent.append((opname, action, data))
        w = self.w
        if (opname, action) == ('passivetree', 'trialEnter'):
            if w.start_text:
                return {'action': 'sendMessage', 'data': {'message': w.start_text}}
            w.open()
            return {'action': 'trialState'}
        if (opname, action) in (('infinitytower', 'enter'), ('descent', 'start')):
            if w.start_text:
                return {'action': 'msg', 'data': {'text': w.start_text}}
            w.open()
            return {'action': 'state' if opname == 'infinitytower' else 'closeInfo'}
        if (opname, action) == ('infinitytower', 'skip') and w.wait > 0:
            w.wait, w.skips = 1, w.skips + 1
            return {'action': 'state'}
        if (opname, action) == ('descent', 'pick'):
            w.picks += 1
            if not w.stay_open and data.get('offer') == 7:
                w.offer, w.state = None, 'travel'
            return {'action': 'closeOffer'}
        if (opname, action) == ('descent', 'ready'):
            w.readies += 1
            w.ready, w.state = True, 'travel'
            return {'action': 'hud'}
        return None

    async def step(self, dx, dy):
        self.w.step(dx, dy)

    async def loot(self):
        self.looted += 1

    def raid_mode(self, names, on, keep_flee=False):
        self.modes.append((list(names), on, keep_flee))


class SoloWalk(unittest.TestCase):
    def setUp(self):
        self.keep = (TX.TOWER_BUDGET, TX.DESCENT_BUDGET, TX.SOLO_FIGHT_MIN, TX.SOLO_STUCK, TX.SOLO_ENTER_WAIT)

    def tearDown(self):
        TX.TOWER_BUDGET, TX.DESCENT_BUDGET, TX.SOLO_FIGHT_MIN, TX.SOLO_STUCK, TX.SOLO_ENTER_WAIT = self.keep

    def tower(self, **kw):
        w = SoloWorld('tower', **kw)
        io = SoloIO(w)
        return run(TX.check_tower_walk(io, 'Tester Aaa', 'Warrior', w.level)), io

    def descent(self, **kw):
        w = SoloWorld('descent', **kw)
        io = SoloIO(w)
        return run(TX.check_descent_walk(io, 'Tester Aaa', 'Warrior', w.level)), io

    def test_the_verdicts(self):
        base = {'level': 300, 'came': 'foot', 'steps': 20, 'secs': 60}
        self.assertEqual(TX.tower_walk_verdict(dict(base, faults=['x']))[0], TX.FAIL)
        self.assertEqual(TX.tower_walk_verdict(dict(base, cleared=2, skips=1))[0], TX.PASS)
        self.assertIn('called 1 time', TX.tower_walk_verdict(dict(base, cleared=2, skips=1))[1])
        self.assertEqual(TX.tower_walk_verdict(dict(base, cleared=0, fought=TX.SOLO_FIGHT_MIN))[0], TX.FAIL)
        self.assertEqual(TX.tower_walk_verdict(dict(base, stuck=(1, 2)))[0], TX.SKIP)
        self.assertEqual(TX.tower_walk_verdict(dict(base, died=True))[0], TX.SKIP)
        self.assertEqual(TX.tower_walk_verdict(base)[0], TX.SKIP)
        self.assertIn('enter temple (no path)', TX.tower_walk_verdict(dict(base, cleared=1, fallbacks=['enter temple (no path)']))[1])
        self.assertEqual(TX.descent_walk_verdict(dict(base, faults=['x']))[0], TX.FAIL)
        self.assertEqual(TX.descent_walk_verdict(dict(base, depth=2, picks=2, rests=1))[0], TX.PASS)
        self.assertIn('2 boon choice(s) answered', TX.descent_walk_verdict(dict(base, depth=2, picks=2, rests=1))[1])
        self.assertEqual(TX.descent_walk_verdict(dict(base, fought=TX.SOLO_FIGHT_MIN))[0], TX.FAIL)
        self.assertEqual(TX.descent_walk_verdict(dict(base, stuck=(1, 2)))[0], TX.SKIP)
        self.assertEqual(TX.descent_walk_verdict(dict(base, died=True))[0], TX.SKIP)
        for k in ('tower_walk', 'descent_walk'):
            self.assertIn(k, TX.KEYS)
            self.assertNotIn(k, TX.CLOSED_KEYS)
        self.assertLess(TX.KEYS.index('tower_walk'), TX.KEYS.index('rift_walk'))

    def test_the_tower_is_walked_and_two_floors_are_a_pass(self):
        r, io = self.tower()
        self.assertEqual(r.status, TX.PASS, r.detail)
        self.assertEqual(r.fallbacks, [])
        self.assertEqual(io.w.teleports, 0, 'the bot walked to the temple')
        self.assertEqual(io.w.starts, 1)
        self.assertGreaterEqual(io.w.cleared, 2)
        self.assertGreaterEqual(io.w.skips, 1, 'the next floor was called between the floors')
        self.assertIn(('infinitytower', 'enter', {}), io.sent)
        self.assertFalse(io.w.inside)
        self.assertEqual(io.moves[-1], 'hunt')
        self.assertEqual(io.modes[0], (['Tester Aaa'], True, True))
        self.assertEqual(io.modes[-1], (['Tester Aaa'], False, False))
        self.assertGreater(io.looted, 0)
        self.assertLess(io.cmds.index('path temple'), io.cmds.index('tower path'))
        self.assertIn('2 floor(s) cleared', r.detail)

    def test_no_path_to_the_temple_is_a_counted_fallback(self):
        r, io = self.tower(no_path=True)
        self.assertEqual(r.status, TX.PASS, r.detail)
        self.assertEqual(io.w.teleports, 1)
        self.assertEqual(len(r.fallbacks), 1)
        self.assertIn('enter temple', r.fallbacks[0])
        self.assertIn('teleport in place of walking', r.detail)

    def test_the_tower_skips(self):
        r, _ = self.tower(err='no tower system')
        self.assertEqual((r.status, 'no tower' in r.detail), (TX.SKIP, True))
        r, _ = self.tower(level=50)
        self.assertEqual((r.status, 'needs level 100' in r.detail), (TX.SKIP, True))
        r, _ = self.tower(inside=True)
        self.assertEqual((r.status, 'inside the Infinity Tower already' in r.detail), (TX.SKIP, True))
        r, _ = self.tower(can_enter=False)
        self.assertEqual((r.status, 'try cooldown' in r.detail), (TX.SKIP, True))
        r, io = self.tower(free=4)
        self.assertEqual((r.status, 'kept for the players' in r.detail), (TX.SKIP, True))
        self.assertEqual(io.w.starts, 0, 'the reserve: the bot does not even ask')
        r, io = self.tower(never_open=True)
        self.assertEqual(r.status, TX.SKIP)
        self.assertIn('did not take the bot in', r.detail)
        self.assertEqual(io.moves[-1], 'hunt')
        r, _ = self.tower(die_after=3)
        self.assertEqual((r.status, 'fell before a floor' in r.detail), (TX.SKIP, True))
        TX.SOLO_STUCK = 5.0
        r, _ = self.tower(blocked={(x, y) for x in range(20, 60) for y in range(0, 12)})
        self.assertEqual(r.status, TX.SKIP)
        self.assertIn('blocked', r.detail)

    def test_the_tower_bugs(self):
        r, io = self.tower(bank_stuck=True)
        self.assertEqual(r.status, TX.FAIL)
        self.assertIn('bank rose by 0', r.detail)
        self.assertIn('BUG tower_walk', r.bug_line())
        self.assertGreaterEqual(io.w.closed, 1, 'the run is closed')
        r, _ = self.tower(mixed=True)
        self.assertEqual(r.status, TX.FAIL)
        self.assertIn('a player is in the tower run of the testers', r.detail)
        TX.SOLO_FIGHT_MIN = 8.0
        r, io = self.tower(never_kill=True)
        self.assertEqual(r.status, TX.FAIL)
        self.assertIn('cleared no floor', r.detail)
        self.assertFalse(io.w.inside)

    def test_the_budget_ends_the_tower(self):
        TX.TOWER_BUDGET = 6.0
        r, io = self.tower(never_kill=True)
        self.assertIn(r.status, (TX.SKIP, TX.PASS))
        self.assertFalse(io.w.inside)
        self.assertEqual(io.moves[-1], 'hunt')

    def test_the_descent_is_walked_boons_are_picked_and_rest_is_left(self):
        r, io = self.descent()
        self.assertEqual(r.status, TX.PASS, r.detail)
        self.assertEqual(io.w.teleports, 0)
        self.assertEqual(io.w.sigils, 0, 'the free run pays: no sigil asked')
        self.assertGreaterEqual(io.w.picks, 1)
        self.assertEqual(io.w.readies, 1, 'the shrine room is left with Continue')
        self.assertIn(('descent', 'start', {'weekly': False}), io.sent)
        self.assertGreaterEqual(io.w.depth, 2)
        self.assertFalse(io.w.inside)
        self.assertEqual(io.moves[-1], 'hunt')
        self.assertLess(io.cmds.index('path temple'), io.cmds.index('descent path'))
        self.assertIn('boon choice(s) answered', r.detail)

    def test_a_used_free_run_asks_for_a_sigil(self):
        r, io = self.descent(pay=None)
        self.assertEqual(r.status, TX.PASS, r.detail)
        self.assertEqual(io.w.sigils, 1)
        r, io = self.descent(pay=None, sigil_ok=False)
        self.assertEqual((r.status, 'no free descent today' in r.detail), (TX.SKIP, True))
        self.assertEqual(io.w.starts, 0)

    def test_the_descent_skips(self):
        r, _ = self.descent(err='no descent system')
        self.assertEqual((r.status, 'no descent' in r.detail), (TX.SKIP, True))
        r, _ = self.descent(level=50)
        self.assertEqual((r.status, 'needs level 100' in r.detail), (TX.SKIP, True))
        r, _ = self.descent(inside=True)
        self.assertEqual((r.status, 'inside the Ember Descent already' in r.detail), (TX.SKIP, True))
        r, io = self.descent(free=2)
        self.assertEqual((r.status, 'kept for the players' in r.detail), (TX.SKIP, True))
        r, io = self.descent(pz=False)
        self.assertEqual(r.status, TX.SKIP)
        self.assertIn('not in a protection zone', r.detail)
        self.assertEqual(io.w.starts, 0)
        r, io = self.descent(start_text='You are already in the Descent.')
        self.assertEqual(r.status, TX.SKIP)
        self.assertIn('did not start', r.detail)
        self.assertIn('already in the Descent', r.detail)
        r, _ = self.descent(die_after=3)
        self.assertEqual((r.status, 'fell before a room' in r.detail), (TX.SKIP, True))

    def trial(self, **kw):
        w = SoloWorld('trial', **kw)
        io = SoloIO(w)
        return run(TX.check_trial_walk(io, 'Tester Aaa', 'Warrior', w.level)), io

    def test_the_trial_verdict(self):
        base = {'level': 300, 'came': 'foot', 'steps': 20, 'secs': 60, 'tier': 1, 'family': 'warrior'}
        self.assertEqual(TX.trial_walk_verdict(dict(base, faults=['x']))[0], TX.FAIL)
        self.assertEqual(TX.trial_walk_verdict(dict(base, killed=4, boss_seen=True, hp=60))[0], TX.PASS)
        self.assertIn('the guardian at 60%', TX.trial_walk_verdict(dict(base, killed=4, boss_seen=True, hp=60))[1])
        self.assertEqual(TX.trial_walk_verdict(dict(base, fought=TX.SOLO_FIGHT_MIN))[0], TX.FAIL)
        self.assertEqual(TX.trial_walk_verdict(dict(base, puzzle='seals'))[0], TX.SKIP)
        self.assertEqual(TX.trial_walk_verdict(dict(base, stuck=(1, 2)))[0], TX.SKIP)
        self.assertEqual(TX.trial_walk_verdict(dict(base, died=True, lives=0))[0], TX.SKIP)
        self.assertEqual(TX.trial_walk_verdict(base)[0], TX.SKIP)
        self.assertIn('trial_walk', TX.KEYS)
        self.assertNotIn('trial_walk', TX.CLOSED_KEYS)

    def test_the_trial_is_walked_the_waves_and_the_guardian(self):
        r, io = self.trial()
        self.assertEqual(r.status, TX.PASS, r.detail)
        self.assertEqual(io.w.teleports, 0)
        self.assertIn(('passivetree', 'trialEnter', {'tier': 1}), io.sent)
        self.assertGreaterEqual(io.w.killed, 2)
        self.assertFalse(io.w.inside)
        self.assertEqual(io.moves[-1], 'hunt')
        self.assertLess(io.cmds.index('path temple'), io.cmds.index('trial path'))
        self.assertIn('tier 1 of warrior', r.detail)

    def test_the_trial_skips(self):
        r, io = self.trial(err='no trial system')
        self.assertEqual((r.status, 'no trial' in r.detail), (TX.SKIP, True))
        r, _ = self.trial(level=50)
        self.assertEqual((r.status, 'needs level 100' in r.detail), (TX.SKIP, True))
        r, _ = self.trial(inside=True)
        self.assertEqual((r.status, 'inside the trial already' in r.detail), (TX.SKIP, True))
        r, io = self.trial(puzzle=True, family='mystic')
        self.assertEqual((r.status, 'puzzle' in r.detail), (TX.SKIP, True))
        self.assertEqual(io.w.starts, 0, 'a puzzle trial is not even entered')
        r, _ = self.trial(family=None)
        self.assertEqual((r.status, 'has no trial' in r.detail), (TX.SKIP, True))
        r, _ = self.trial(problem='The trial is still closed to you for 40 seconds.')
        self.assertEqual((r.status, 'still closed' in r.detail), (TX.SKIP, True))
        r, _ = self.trial(free=2)
        self.assertEqual((r.status, 'kept for the players' in r.detail), (TX.SKIP, True))
        r, io = self.trial(pz=False)
        self.assertEqual(r.status, TX.SKIP)
        self.assertEqual(io.w.starts, 0)
        r, io = self.trial(never_open=True)
        self.assertEqual((r.status, 'did not open' in r.detail), (TX.SKIP, True))
        r, _ = self.trial(die_after=3)
        self.assertEqual((r.status, 'ended before a thrall died' in r.detail), (TX.SKIP, True))

    def test_the_trial_bugs(self):
        TX.SOLO_FIGHT_MIN = 8.0
        r, io = self.trial(never_kill=True)
        self.assertEqual(r.status, TX.FAIL)
        self.assertIn('killed none', r.detail)
        self.assertIn('BUG trial_walk', r.bug_line())
        self.assertFalse(io.w.inside)

    def test_the_descent_bugs(self):
        r, io = self.descent(stay_open=True)
        self.assertEqual(r.status, TX.FAIL)
        self.assertIn('stayed open', r.detail)
        self.assertIn('BUG descent_walk', r.bug_line())
        self.assertFalse(io.w.inside)
        r, _ = self.descent(mixed=True)
        self.assertEqual(r.status, TX.FAIL)
        self.assertIn('a player is in the descent run of the testers', r.detail)
        TX.SOLO_FIGHT_MIN = 8.0
        r, io = self.descent(never_kill=True)
        self.assertEqual(r.status, TX.FAIL)
        self.assertIn('cleared no room', r.detail)
        self.assertGreaterEqual(io.w.closed, 1)


class HideoutIO(FakeIO):
    """the hideout window of a mocked server: `open` / `get` answer the state, `enter` builds the room, `place` accepts a free tile that is not
    reserved (and only the first `accept` tiles tried are refused when `refuse` is set), `remove`, `leave`"""

    def __init__(self, level_text=None, refuse=False, lie_list=False, keep_on_remove=False, no_room=False, stuck_inside=False, owned=True,
                 inside=False, silent=False):
        super().__init__()
        self.level_text, self.refuse, self.lie_list, self.keep_on_remove, self.no_room, self.stuck_inside = level_text, refuse, lie_list, keep_on_remove, no_room, stuck_inside
        self.owned, self.silent = owned, silent
        self.inside, self.placed, self.nid, self.tries, self.sent = inside, [], 0, 0, []
        self.modes = []

    def catalogue(self):
        return [{'key': 'banner', 'name': 'Wall banner', 'layer': 'wall', 'owned': True, 'max': 2, 'placed': 0},
                {'key': 'rug', 'name': 'Rug', 'layer': 'floor', 'owned': self.owned, 'max': 3, 'placed': len(self.placed)}]

    def state(self):
        return {'action': 'state', 'data': {'me': 5, 'inside': {'owner': 5, 'isOwner': True} if self.inside else None,
                'layout': {'w': 9, 'h': 7, 'reserved': [[4, 3, 'altar'], [1, 1, 'door']], 'arrival': [4, 5]}, 'catalogue': self.catalogue(),
                'hideout': {'count': len(self.placed) + (1 if self.lie_list else 0), 'max': 20},
                'placed': [] if self.lie_list else [dict(p) for p in self.placed]}}

    async def request(self, opname, action, data, expect, timeout):
        self.sent.append((action, data))
        if self.silent:
            return None
        if self.level_text and action == 'open':
            return {'action': 'result', 'data': {'ok': False, 'text': self.level_text}}
        if action in ('open', 'get'):
            return self.state()
        if action == 'enter':
            if not self.no_room:
                self.inside = True
            return self.state()
        if action == 'place':
            self.tries += 1
            if self.refuse or (data['x'], data['y']) in ((4, 3), (4, 5), (1, 1)):
                return {'action': 'result', 'data': {'ok': False, 'text': 'That tile is taken.'}}
            self.nid += 1
            self.placed.append({'id': self.nid, 'key': data['key'], 'x': data['x'], 'y': data['y'], 'r': 0})
            return {'action': 'result', 'data': {'ok': True, 'text': 'Rug placed.'}}
        if action == 'remove':
            if not self.keep_on_remove:
                self.placed = [p for p in self.placed if p['id'] != data['id']]
            return {'action': 'result', 'data': {'ok': True, 'text': 'Removed.'}}
        if action == 'leave':
            if not self.stuck_inside:
                self.inside = False
            return self.state()
        return None

    async def go(self, place):
        self.moves.append(place)
        return True

    def raid_mode(self, names, on, keep_flee=False):
        self.modes.append((list(names), on, keep_flee))


class HideoutCheck(unittest.TestCase):
    def play(self, **kw):
        io = HideoutIO(**kw)
        return run(TX.check_hideout(io, 'Tester Aaa', 'Warrior', 900)), io

    def test_the_candidates_and_the_pick(self):
        layout = {'w': 9, 'h': 7, 'reserved': [[4, 3, 'altar']], 'arrival': [4, 5]}
        cells = TX.hideout_candidates(layout)
        self.assertEqual(len(cells), TX.HIDEOUT_TRIES)
        self.assertNotIn((4, 3), cells)
        self.assertNotIn((4, 5), cells)
        self.assertEqual(TX.hideout_candidates({}), [])
        self.assertTrue(all(1 <= x < 9 and 1 <= y < 7 for x, y in cells))
        self.assertEqual(TX.hideout_pick([{'key': 'a', 'owned': False, 'max': 1}, {'key': 'w', 'owned': True, 'layer': 'wall', 'max': 1},
                                          {'key': 'full', 'owned': True, 'layer': 'floor', 'max': 2, 'placed': 2},
                                          {'key': 'rug', 'owned': True, 'layer': 'floor', 'max': 2, 'placed': 1}])['key'], 'rug')
        self.assertIsNone(TX.hideout_pick([]))
        self.assertIn('hideout', TX.KEYS)

    def test_a_decoration_is_placed_listed_removed_and_the_room_left(self):
        r, io = self.play()
        self.assertEqual(r.status, TX.PASS, r.detail)
        actions = [a for a, _ in io.sent]
        for want in ('open', 'enter', 'place', 'remove', 'leave'):
            self.assertIn(want, actions)
        self.assertLess(actions.index('enter'), actions.index('place'))
        self.assertLess(actions.index('place'), actions.index('remove'))
        self.assertFalse(io.inside)
        self.assertEqual(io.placed, [])
        self.assertEqual(io.moves[-1], 'hunt')
        self.assertEqual(io.modes[0], (['Tester Aaa'], True, True))
        self.assertEqual(io.modes[-1], (['Tester Aaa'], False, False))
        placed = [d for a, d in io.sent if a == 'place'][0]
        self.assertEqual(placed['key'], 'rug', 'the wall banner is no floor decoration')
        self.assertGreaterEqual(io.tries, 1)

    def test_skips(self):
        r, _ = self.play(silent=True)
        self.assertEqual((r.status, 'not installed' in r.detail), (TX.SKIP, True))
        r, _ = self.play(level_text='The hideout opens at level 50.')
        self.assertEqual((r.status, 'opens at level' in r.detail), (TX.SKIP, True))
        r, _ = self.play(inside=True)
        self.assertEqual((r.status, 'inside a hideout already' in r.detail), (TX.SKIP, True))
        r, _ = self.play(owned=False)
        self.assertEqual((r.status, 'no decoration' in r.detail), (TX.SKIP, True))
        r, io = self.play(no_room=True)
        self.assertEqual((r.status, 'did not open' in r.detail), (TX.SKIP, True))
        self.assertEqual(io.moves[-1], 'hunt')

    def test_bugs(self):
        r, io = self.play(refuse=True)
        self.assertEqual(r.status, TX.FAIL)
        self.assertIn('no tile of the room took', r.detail)
        self.assertIn('BUG hideout', r.bug_line())
        self.assertFalse(io.inside, 'the bot is taken out again')
        r, _ = self.play(lie_list=True)
        self.assertEqual(r.status, TX.FAIL)
        self.assertIn('lists 0 such decoration', r.detail)
        r, _ = self.play(keep_on_remove=True)
        self.assertEqual(r.status, TX.FAIL)
        self.assertIn('was removed', r.detail)
        r, io = self.play(stuck_inside=True)
        self.assertEqual(r.status, TX.FAIL)
        self.assertIn('Leave did not bring the bot out', r.detail)


class BossWorld:
    """an Ascended or omen arena on one lane (y = 5): the temple at x 92, the bot hunting at x 60. `ascended | omen state / path / close`, the grant
    (`ascended sigil`, `omen key`), `path temple`, `enter temple` as the helper answers them; the sigil / key is used through BossIO.use_item. The boss
    comes 3 looks after the arrival and loses health while the bot fights within reach."""
    TEMPLE = 92
    FIGHT = 5

    def __init__(self, system, level=1000, no_path=False, never_open=False, never_hurt=False, mixed=False, untagged=False, free=4, reserve=1,
                 inside=False, err=None, pz=True, grant_err=None, no_item=False, bag_full=False, die_after=None, blocked=(), enabled=True):
        self.system, self.level, self.no_path, self.never_open, self.never_hurt = system, level, no_path, never_open, never_hurt
        self.mixed, self.untagged, self.free, self.reserve, self.inside, self.err, self.pz = mixed, untagged, free, reserve, inside, err, pz
        self.grant_err, self.no_item, self.bag_full, self.die_after, self.blocked, self.enabled = grant_err, no_item, bag_full, die_after, set(blocked), enabled
        self.pos = (60, 5)
        self.held, self.grants, self.uses, self.closed, self.teleports, self.looks, self.hp, self.boss_at = False, 0, 0, 0, 0, 0, 100, None
        self.BOSS_X = 120

    def facts(self):
        out = {'inside': self.inside, 'level': self.level, 'pos': {'x': self.pos[0], 'y': 5, 'z': 7}, 'pz': self.pz, 'free': self.free,
               'reserve': self.reserve, 'held': self.held, 'enabled': self.enabled}
        if self.system == 'ascended':
            out.update(kinds=[{'key': 'bloodmoon', 'minLevel': 900}, {'key': 'storm', 'minLevel': 900}], sigilClientId=5809)
        else:
            out.update(minLevel=800, keyClientId=21703)
        if self.inside:
            out['run'] = self.run()
            out['guide'] = self.guide()
        return out

    def boss_up(self):
        return self.looks >= 3

    def run(self):
        run = {'id': 1, 'kind': 'bloodmoon', 'state': 'running', 'boss': 'alive' if self.boss_up() else 'waiting', 'lives': 3, 'livesMax': 3,
               'players': 2 if self.mixed else 1, 'testers': 1, 'left': 700, 'phase': 1,
               'tester': not self.untagged, 'bossHp': self.hp if self.boss_up() else None}
        if self.system == 'omen':
            run['omen'] = 'storm'
            run.pop('tester')
        return run

    def guide(self):
        if not self.boss_up():
            return {'mode': 'wait', 'why': 'the boss is coming'}
        near = abs(self.BOSS_X - self.pos[0]) <= self.FIGHT
        return {'mode': 'fight' if near else 'walk', 'goal': {'x': self.BOSS_X, 'y': 5, 'z': 7}, 'reach': [1, self.FIGHT], 'area': 'boss', 'why': 'test'}

    def tick(self):
        if not self.inside:
            return
        self.looks += 1
        if self.die_after is not None and self.looks > self.die_after:
            self.inside = False
            return
        if self.guide()['mode'] == 'fight' and not self.never_hurt:
            self.hp = max(1, self.hp - 15)

    def path_to(self, goal, reach):
        x, _ = self.pos
        if x < goal - reach:
            return [1] * (goal - reach - x)
        if x > goal + reach:
            return [3] * (x - goal - reach)
        return []

    def answer(self, command):
        sysn = self.system
        grant = 'ascended sigil' if sysn == 'ascended' else 'omen key'
        if command == '%s state' % sysn:
            if self.err:
                return {'err': self.err}
            self.tick()
            return self.facts()
        if command == grant:
            if self.grant_err:
                return {'err': self.grant_err}
            self.grants += 1
            self.held = not self.no_item and not self.bag_full
            return dict(self.facts(), given=True, kind='bloodmoon', bagFull=True if self.bag_full else None)
        if command == '%s path' % sysn:
            g = self.guide() if self.inside else None
            if not g or g['mode'] != 'walk':
                return dict(self.facts(), err='no goal' if self.inside else 'not inside')
            return dict(self.facts(), path=self.path_to(g['goal']['x'], g['reach'][1]), dist=abs(self.pos[0] - g['goal']['x']))
        if command == '%s close' % sysn:
            was = self.inside
            self.inside = False
            self.closed += 1
            return dict(self.facts(), closed=was)
        if command == 'path temple':
            if self.no_path:
                return {'err': 'no path', 'dest': {'x': self.TEMPLE, 'y': 5, 'z': 7}}
            dist = abs(self.pos[0] - self.TEMPLE)
            base = {'pos': {'x': self.pos[0], 'y': 5, 'z': 7}, 'dest': {'x': self.TEMPLE, 'y': 5, 'z': 7}, 'dist': dist}
            return dict(base, here=True, path=[]) if dist <= 1 else dict(base, path=self.path_to(self.TEMPLE, 1))
        if command == 'enter temple':
            self.teleports += 1
            self.pos = (self.TEMPLE - 1, 5)
            return {'kind': 'temple', 'pos': {'x': self.pos[0], 'y': 5, 'z': 7}}
        return None

    def use(self):
        self.uses += 1
        if self.never_open or self.inside or not self.held:
            return
        self.held = False
        self.inside, self.looks = True, 0
        self.pos = (110, 5)

    def step(self, dx, dy):
        nx = self.pos[0] + dx
        if (nx, self.pos[1] + dy) in self.blocked or not (-1 <= nx <= 200):
            return
        self.pos = (nx, self.pos[1] + dy)


class BossIO(FakeIO):
    def __init__(self, world, **kw):
        super().__init__(**kw)
        self.w, self.modes, self.cmds, self.looted = world, [], [], 0

    async def helper(self, command, kind, wait=4.0):
        self.cmds.append(command)
        return self.w.answer(command)

    async def go(self, place):
        self.moves.append(place)
        if place == 'hunt':
            self.w.pos = (60, 5)
        return True

    async def use_item(self, client_id):
        self.client = client_id
        self.w.use()
        return True

    async def step(self, dx, dy):
        self.w.step(dx, dy)

    async def loot(self):
        self.looted += 1

    def raid_mode(self, names, on, keep_flee=False):
        self.modes.append((list(names), on, keep_flee))


class BossWalk(unittest.TestCase):
    def setUp(self):
        self.keep = (TX.ASC_BUDGET, TX.SOLO_FIGHT_MIN, TX.SOLO_STUCK, TX.ASC_OPEN_WAIT)

    def tearDown(self):
        TX.ASC_BUDGET, TX.SOLO_FIGHT_MIN, TX.SOLO_STUCK, TX.ASC_OPEN_WAIT = self.keep

    def play(self, system, **kw):
        w = BossWorld(system, **kw)
        io = BossIO(w)
        fn = TX.check_ascended_walk if system == 'ascended' else TX.check_omen_walk
        return run(fn(io, 'Tester Aaa', 'Warrior', w.level)), io

    def test_the_verdicts(self):
        base = {'level': 1000, 'came': 'foot', 'steps': 20, 'secs': 60, 'boss_seen': True, 'hp': 70, 'phase': 2, 'boss': 'bloodmoon'}
        for fn in (TX.ascended_walk_verdict, TX.omen_walk_verdict):
            self.assertEqual(fn(dict(base, faults=['x']))[0], TX.FAIL)
            self.assertEqual(fn(base)[0], TX.PASS)
            self.assertIn('hurt to 70%', fn(base)[1])
            self.assertIn('phase 2', fn(base)[1])
            self.assertEqual(fn(dict(base, hp=100, fought=TX.SOLO_FIGHT_MIN))[0], TX.FAIL)
            self.assertEqual(fn(dict(base, hp=100, stuck=(1, 2)))[0], TX.SKIP)
            self.assertEqual(fn(dict(base, hp=100, died=True))[0], TX.SKIP)
            self.assertEqual(fn(dict(base, hp=100))[0], TX.SKIP)
            self.assertIn('did not come', fn(dict(base, hp=None, boss_seen=False))[1])
        self.assertIn('enter temple (no path)', TX.ascended_walk_verdict(dict(base, fallbacks=['enter temple (no path)']))[1])
        for k in ('ascended_walk', 'omen_walk'):
            self.assertIn(k, TX.KEYS)
            self.assertNotIn(k, TX.CLOSED_KEYS)
        self.assertLess(TX.KEYS.index('ascended_walk'), TX.KEYS.index('rift_walk'))
        self.assertLess(TX.KEYS.index('omen_walk'), TX.KEYS.index('rift_walk'))

    def test_the_problems(self):
        t = {}
        self.assertEqual(TX.boss_problems({'run': {'players': 2, 'testers': 1}}, t)[0][:19], 'a player is in the ')
        t = {'system': 'ascended'}
        self.assertIn('not marked', TX.boss_problems({'run': {'tester': False, 'players': 1, 'testers': 1}}, t)[0])
        t = {'system': 'omen'}
        self.assertEqual(TX.boss_problems({'run': {'omen': 'storm', 'bossHp': 55, 'phase': 2, 'lives': 2}}, t), [])
        self.assertEqual((t['hp'], t['phase'], t['lives'], t['boss_seen']), (55, 2, 2, True))
        TX.boss_problems({'run': {'bossHp': 80}}, t)
        self.assertEqual(t['hp'], 55, 'the lowest health is kept')

    def test_the_refusals(self):
        k = [{'key': 'bloodmoon', 'minLevel': 900}]
        self.assertEqual(TX.ascended_refusal(None)[0], TX.SKIP)
        self.assertIn('no system', TX.ascended_refusal({'err': 'no system'})[1])
        self.assertIn('closed', TX.ascended_refusal({'enabled': False, 'kinds': k})[1])
        self.assertIn('need level 900', TX.ascended_refusal({'level': 500, 'kinds': k})[1])
        self.assertIn('inside an Ascended arena already', TX.ascended_refusal({'level': 1000, 'kinds': k, 'inside': True})[1])
        self.assertIn('kept for the players', TX.ascended_refusal({'level': 1000, 'kinds': k, 'free': 1, 'reserve': 1})[1])
        self.assertIsNone(TX.ascended_refusal({'level': 1000, 'kinds': k, 'free': 2, 'reserve': 1}))

    def test_the_ascended_arena_is_walked_and_the_boss_is_hurt(self):
        r, io = self.play('ascended')
        self.assertEqual(r.status, TX.PASS, r.detail)
        self.assertEqual(r.fallbacks, [])
        self.assertEqual(io.w.teleports, 0, 'the bot walked to the temple')
        self.assertEqual((io.w.grants, io.client), (1, 5809))
        self.assertGreaterEqual(io.w.uses, 1)
        self.assertFalse(io.w.inside)
        self.assertEqual(io.moves[-1], 'hunt')
        self.assertEqual(io.modes[0], (['Tester Aaa'], True, True))
        self.assertEqual(io.modes[-1], (['Tester Aaa'], False, False))
        self.assertLess(io.cmds.index('path temple'), io.cmds.index('ascended sigil'))
        self.assertLess(io.cmds.index('ascended sigil'), io.cmds.index('ascended path'))
        self.assertGreaterEqual(io.w.closed, 1)
        self.assertIn('hurt to', r.detail)

    def test_the_omen_arena_is_walked_and_the_guardian_is_hurt(self):
        r, io = self.play('omen')
        self.assertEqual(r.status, TX.PASS, r.detail)
        self.assertEqual((io.w.grants, io.client), (1, 21703))
        self.assertFalse(io.w.inside)
        self.assertEqual(io.moves[-1], 'hunt')
        self.assertLess(io.cmds.index('omen key'), io.cmds.index('omen path'))
        self.assertGreaterEqual(io.w.closed, 1)

    def test_no_path_to_the_temple_is_a_counted_fallback(self):
        r, io = self.play('ascended', no_path=True)
        self.assertEqual(r.status, TX.PASS, r.detail)
        self.assertEqual(io.w.teleports, 1)
        self.assertEqual(r.fallbacks, ['enter temple (no path)'])

    def test_the_skips(self):
        for system, label in (('ascended', 'Ascended'), ('omen', 'omen')):
            r, _ = self.play(system, err='no %s system' % system)
            self.assertEqual((r.status, 'no %s' % system in r.detail), (TX.SKIP, True))
            r, _ = self.play(system, level=300)
            self.assertEqual((r.status, 'need level' in r.detail or 'needs level' in r.detail), (TX.SKIP, True))
            r, _ = self.play(system, inside=True)
            self.assertEqual((r.status, 'inside' in r.detail), (TX.SKIP, True))
            r, io = self.play(system, pz=False)
            self.assertEqual(r.status, TX.SKIP)
            self.assertIn('not in a protection zone', r.detail)
            self.assertEqual(io.w.grants, 0, 'no grant outside a protection zone')
            r, io = self.play(system, grant_err='level 500 opens none')
            self.assertEqual((r.status, 'opens none' in r.detail), (TX.SKIP, True))
            r, io = self.play(system, bag_full=True)
            self.assertEqual((r.status, 'bag is full' in r.detail), (TX.SKIP, True))
            r, io = self.play(system, no_item=True)
            self.assertEqual((r.status, 'holds none' in r.detail), (TX.FAIL, True))
            r, io = self.play(system, never_open=True)
            self.assertEqual((r.status, 'did not open' in r.detail), (TX.SKIP, True))
            r, _ = self.play(system, die_after=2)
            self.assertEqual((r.status, 'fell before the boss was hurt' in r.detail or 'did not come' in r.detail), (TX.SKIP, True))
        r, _ = self.play('ascended', free=1)
        self.assertEqual((r.status, 'kept for the players' in r.detail), (TX.SKIP, True))

    def test_the_bugs(self):
        r, io = self.play('ascended', mixed=True)
        self.assertEqual(r.status, TX.FAIL)
        self.assertIn('a player is in the arena run of the testers', r.detail)
        self.assertIn('BUG ascended_walk', r.bug_line())
        self.assertFalse(io.w.inside)
        r, _ = self.play('ascended', untagged=True)
        self.assertEqual(r.status, TX.FAIL)
        self.assertIn('not marked', r.detail)
        TX.SOLO_FIGHT_MIN = 8.0
        r, io = self.play('ascended', never_hurt=True)
        self.assertEqual(r.status, TX.FAIL)
        self.assertIn('took none of its health', r.detail)
        self.assertGreaterEqual(io.w.closed, 1)
        r, io = self.play('omen', never_hurt=True)
        self.assertEqual(r.status, TX.FAIL)
        self.assertIn('BUG omen_walk', r.bug_line())


class BountyWorld:
    """the bounty board on one lane (y = 5): the bot at x 60, the hunt of the contract at x 140. `bounty state / path`, the window's `accept` and
    `abandon` come through BountyIO.request. A monster of the contract is in sight within 30 tiles of the hunt; the bot kills one per look when it
    fights in reach, and the counter moves with it."""
    HUNT = 140
    FIGHT = 5

    def __init__(self, err=None, candidates=True, held=False, max_active=3, accept_ok=True, never_count=False, no_monster=False, blocked=(), die_after=None,
                 done_status=False, drop_row=False):
        self.err, self.candidates, self.held, self.max_active, self.accept_ok = err, candidates, held, max_active, accept_ok
        self.never_count, self.no_monster, self.blocked, self.die_after, self.drop_row = never_count, no_monster, set(blocked), die_after, drop_row
        self.pos = (60, 5)
        self.active = [{'key': '1-9', 'name': 'Snake', 'progress': 4, 'required': 60, 'status': 0}] if held else []
        self.accepts, self.abandons, self.looks, self.dead = 0, 0, 0, False

    def mine(self):
        return self.active[0] if self.active else None

    def guide(self):
        e = self.mine()
        if not e or e['status'] != 0:
            return {'mode': 'wait', 'why': 'no contract'}
        if abs(self.pos[0] - self.HUNT) <= 30 and not self.no_monster:
            near = abs(self.pos[0] - self.HUNT) <= self.FIGHT
            return {'mode': 'fight' if near else 'walk', 'goal': {'x': self.HUNT, 'y': 5, 'z': 7}, 'reach': [1, self.FIGHT], 'area': 'monster'}
        if abs(self.pos[0] - self.HUNT) <= 12:
            return {'mode': 'wait', 'area': 'spawn', 'why': 'at the hunt'}
        return {'mode': 'walk', 'goal': {'x': self.HUNT, 'y': 5, 'z': 7}, 'reach': [1, 8], 'area': 'mark'}

    def facts(self):
        out = {'level': 100, 'pos': {'x': self.pos[0], 'y': 5, 'z': 7}, 'day': 1, 'maxActive': self.max_active, 'active': [dict(x) for x in self.active],
               'candidates': [{'key': '1-2', 'name': 'Rat', 'count': 60, 'level': 4, 'distance': 80, 'mark': {'x': self.HUNT, 'y': 5, 'z': 7, 'n': 'Hunting: Rat'}}]
               if self.candidates else []}
        if self.mine():
            out['guide'] = self.guide()
        return out

    def tick(self):
        self.looks += 1
        if self.die_after is not None and self.looks > self.die_after:
            self.dead = True
            return
        e = self.mine()
        if e and e['status'] == 0 and self.guide()['mode'] == 'fight' and not self.never_count:
            e['progress'] += 1
        if self.drop_row and self.looks > 2:
            self.active = []

    def path_to(self, goal, reach):
        x, _ = self.pos
        if x < goal - reach:
            return [1] * (goal - reach - x)
        if x > goal + reach:
            return [3] * (x - goal - reach)
        return []

    def answer(self, command):
        if command == 'bounty state':
            if self.err:
                return {'err': self.err}
            if self.mine():
                self.tick()
            return self.facts()
        if command == 'bounty path':
            g = self.guide() if self.mine() else None
            if not g or g['mode'] != 'walk':
                return dict(self.facts(), err='no goal')
            return dict(self.facts(), path=self.path_to(g['goal']['x'], g['reach'][1]))
        return None

    def step(self, dx, dy):
        nx = self.pos[0] + dx
        if (nx, self.pos[1] + dy) in self.blocked or not (-1 <= nx <= 300):
            return
        self.pos = (nx, self.pos[1] + dy)


class BountyIO(FakeIO):
    def __init__(self, world, **kw):
        super().__init__(**kw)
        self.w, self.modes, self.cmds, self.looted, self.sent = world, [], [], 0, []

    def alive(self):
        return not self.w.dead

    async def helper(self, command, kind, wait=4.0):
        self.cmds.append(command)
        return self.w.answer(command)

    async def go(self, place):
        self.moves.append(place)
        return True

    async def request(self, opname, action, data, expect, timeout):
        self.sent.append((opname, action, data))
        w = self.w
        if (opname, action) == ('bounty', 'accept') and w.accept_ok:
            w.accepts += 1
            w.active = [{'key': data['key'], 'name': 'Rat', 'progress': 0, 'required': 60, 'status': 0}]
            return {'action': 'board'}
        if (opname, action) == ('bounty', 'abandon'):
            w.abandons += 1
            w.active = []
            return {'action': 'board'}
        return None

    async def step(self, dx, dy):
        self.w.step(dx, dy)

    async def loot(self):
        self.looted += 1

    def raid_mode(self, names, on, keep_flee=False):
        self.modes.append((list(names), on, keep_flee))


class BountyWalk(unittest.TestCase):
    def setUp(self):
        self.keep = (TX.BOUNTY_BUDGET, TX.SOLO_FIGHT_MIN, TX.SOLO_STUCK, TX.BOUNTY_SPAWN_WAIT)

    def tearDown(self):
        TX.BOUNTY_BUDGET, TX.SOLO_FIGHT_MIN, TX.SOLO_STUCK, TX.BOUNTY_SPAWN_WAIT = self.keep

    def play(self, **kw):
        w = BountyWorld(**kw)
        io = BountyIO(w)
        return run(TX.check_bounty_walk(io, 'Tester Aaa', 'Warrior', 100)), io

    def test_the_verdicts(self):
        base = {'level': 100, 'steps': 10, 'secs': 50, 'name': 'Rat', 'base': 0, 'progress': 3, 'required': 60}
        self.assertEqual(TX.bounty_walk_verdict(dict(base, faults=['x']))[0], TX.FAIL)
        self.assertEqual(TX.bounty_walk_verdict(base)[0], TX.PASS)
        self.assertIn('from 0 to 3 of 60', TX.bounty_walk_verdict(base)[1])
        self.assertEqual(TX.bounty_walk_verdict(dict(base, progress=2, fought=TX.SOLO_FIGHT_MIN))[0], TX.FAIL)
        self.assertEqual(TX.bounty_walk_verdict(dict(base, progress=0, stuck=(1, 2)))[0], TX.SKIP)
        self.assertEqual(TX.bounty_walk_verdict(dict(base, progress=0, died=True))[0], TX.SKIP)
        self.assertEqual(TX.bounty_walk_verdict(dict(base, progress=0, waited=TX.BOUNTY_SPAWN_WAIT))[0], TX.SKIP)
        self.assertEqual(TX.bounty_walk_verdict(dict(base, progress=1))[0], TX.SKIP)
        self.assertIn('bounty_walk', TX.KEYS)
        self.assertNotIn('bounty_walk', TX.CLOSED_KEYS)
        self.assertLess(TX.KEYS.index('bounty_walk'), TX.KEYS.index('rift_walk'))

    def test_the_pick(self):
        self.assertEqual(TX.bounty_pick({'active': [{'key': 'a', 'status': 1, 'required': 5}], 'candidates': [{'key': 'b'}]}), ({'key': 'b'}, False))
        row, held = TX.bounty_pick({'active': [{'key': 'a', 'status': 0, 'required': 5}], 'candidates': [{'key': 'b'}]})
        self.assertEqual((row['key'], held), ('a', True))
        row, why = TX.bounty_pick({'level': 7, 'active': [], 'candidates': []})
        self.assertIsNone(row)
        self.assertIn('level 7', why)
        row, why = TX.bounty_pick({'active': [{'key': i, 'status': 1} for i in range(3)], 'maxActive': 3, 'candidates': [{'key': 'b'}]})
        self.assertIsNone(row)
        self.assertIn('holds 3 contracts', why)

    def test_the_contract_is_accepted_hunted_and_counted(self):
        r, io = self.play()
        self.assertEqual(r.status, TX.PASS, r.detail)
        self.assertIn(('bounty', 'accept', {'key': '1-2'}), io.sent)
        self.assertIn(('bounty', 'abandon', {'key': '1-2'}), io.sent)
        self.assertEqual((io.w.accepts, io.w.abandons), (1, 1))
        self.assertGreater(io.w.pos[0], 60 - 1)
        self.assertEqual(io.moves[-1], 'hunt')
        self.assertEqual(io.modes[0], (['Tester Aaa'], True, True))
        self.assertEqual(io.modes[-1], (['Tester Aaa'], False, False))
        self.assertGreater(io.looted, 0)
        self.assertIn('bounty path', io.cmds)

    def test_a_contract_already_held_is_hunted_and_not_abandoned(self):
        r, io = self.play(held=True)
        self.assertEqual(r.status, TX.PASS, r.detail)
        self.assertEqual((io.w.accepts, io.w.abandons), (0, 0))
        self.assertIn('from 4 to 7', r.detail)

    def test_the_skips(self):
        r, _ = self.play(err='no bounty system')
        self.assertEqual((r.status, 'no bounty' in r.detail), (TX.SKIP, True))
        r, io = self.play(candidates=False)
        self.assertEqual((r.status, 'hunt mark' in r.detail), (TX.SKIP, True))
        self.assertEqual(io.w.accepts, 0)
        r, io = self.play(accept_ok=False)
        self.assertEqual((r.status, 'was not accepted' in r.detail), (TX.SKIP, True))
        self.assertEqual(io.w.abandons, 0, 'nothing accepted, nothing abandoned')
        TX.BOUNTY_SPAWN_WAIT = 6.0
        r, _ = self.play(no_monster=True, blocked=())
        self.assertEqual(r.status, TX.SKIP)
        r, _ = self.play(die_after=3)
        self.assertEqual((r.status, 'died' in r.detail), (TX.SKIP, True))
        TX.SOLO_STUCK = 4.0
        r, _ = self.play(blocked=[(61, 5)])
        self.assertEqual((r.status, 'blocked' in r.detail), (TX.SKIP, True))

    def test_the_bugs(self):
        TX.SOLO_FIGHT_MIN = 8.0
        r, io = self.play(never_count=True)
        self.assertEqual(r.status, TX.FAIL)
        self.assertIn('counter moved 0', r.detail)
        self.assertIn('BUG bounty_walk', r.bug_line())
        self.assertEqual(io.w.abandons, 1, 'the contract goes back after a failure too')
        r, _ = self.play(drop_row=True)
        self.assertEqual(r.status, TX.FAIL)
        self.assertIn('left the list', r.detail)


class MainQuestWorld:
    """the main quest on one lane (y = 5): Ysolde at x 92, a place at x 120, the Trolls at x 150, the bot at x 60. Steps: talk, visit, kill, then
    `last` (a spell step the bots do not play). `mainquest state`, `path npc NAME`, `path pos X Y Z`, `enter npc NAME` as the helper answers them; a
    word said next to Ysolde, a stay at the place and kills at the Trolls move the quest, a look after another."""
    NPC, VISIT, TROLLS = 92, 120, 150

    def __init__(self, err=None, enabled=True, staff=False, state=1, level=100, stuck_talk=False, stuck_visit=False, never_count=False, no_path=False,
                 start=1, kinds=None, blocked=()):
        self.err, self.enabled, self.staff, self.state, self.level = err, enabled, staff, state, level
        self.stuck_talk, self.stuck_visit, self.never_count, self.no_path, self.blocked = stuck_talk, stuck_visit, never_count, no_path, set(blocked)
        self.kinds = kinds or ['talk', 'visit', 'kill', 'spell']
        self.step, self.progress, self.pos = start, 0, (60, 5)
        self.said, self.stayed, self.teleports, self.looks = [], 0, 0, 0
        self.armed = False

    def plan(self):
        kind = self.kinds[self.step - 1]
        if kind == 'talk':
            return {'action': 'talk', 'label': 'Warden Ysolde'}
        if kind == 'visit':
            return {'action': 'visit', 'label': 'the place', 'radius': 6}
        if kind == 'kill':
            return {'action': 'kill', 'label': 'Troll', 'monsters': ['Troll'], 'target': 12}
        return {'action': 'skip', 'reason': "the step asks for 'spell' (the bots do not play it)"}

    def facts(self):
        active = self.state == 1 and self.step <= len(self.kinds)
        out = {'enabled': self.enabled, 'staff': self.staff, 'level': self.level, 'state': self.state, 'active': active, 'done': self.state == 2,
               'step': self.step, 'steps': len(self.kinds), 'pos': {'x': self.pos[0], 'y': 5, 'z': 7}}
        if active:
            kind = self.kinds[self.step - 1]
            out.update(key='step%d' % self.step, stepLevel=8, running=True, progress=self.progress, target=12, plan=self.plan())
            if kind == 'visit':
                out['cond'] = {'kind': 'visit', 'label': 'the place', 'radius': 6, 'pos': {'x': self.VISIT, 'y': 5, 'z': 7}}
            if kind == 'kill':
                out['where'] = {'k': 'pos', 'pos': {'x': self.TROLLS, 'y': 5, 'z': 7}}
        return out

    def tick(self):
        self.looks += 1
        if self.step > len(self.kinds):
            return
        kind = self.kinds[self.step - 1]
        if kind == 'talk' and self.armed and not self.stuck_talk:
            self.step, self.armed = self.step + 1, False
        elif kind == 'visit':
            if abs(self.pos[0] - self.VISIT) <= 6:
                self.stayed += 1
                if self.stayed >= 2 and not self.stuck_visit:
                    self.step, self.stayed = self.step + 1, 0
        elif kind == 'kill' and abs(self.pos[0] - self.TROLLS) <= 6 and not self.never_count:
            self.progress += 1

    def path_to(self, goal, reach):
        x, _ = self.pos
        if x < goal - reach:
            return [1] * (goal - reach - x)
        if x > goal + reach:
            return [3] * (x - goal - reach)
        return []

    def answer(self, command):
        if command == 'mainquest state':
            if self.err:
                return {'err': self.err}
            self.tick()
            return self.facts()
        parts = command.split()
        if parts[0] == 'path' and parts[1] in ('npc', 'pos'):
            if self.no_path:
                return {'err': 'no path'}
            goal = self.NPC if parts[1] == 'npc' else int(parts[2])
            dist = abs(self.pos[0] - goal)
            base = {'pos': {'x': self.pos[0], 'y': 5, 'z': 7}, 'dest': {'x': goal, 'y': 5, 'z': 7}, 'dist': dist}
            return dict(base, here=True, path=[]) if dist <= 1 else dict(base, path=self.path_to(goal, 1))
        if parts[0] == 'enter' and parts[1] == 'npc':
            self.teleports += 1
            self.pos = (self.NPC - 1, 5)
            return {'kind': 'npc', 'pos': {'x': self.pos[0], 'y': 5, 'z': 7}}
        return None

    def step_by(self, dx, dy):
        nx = self.pos[0] + dx
        if (nx, self.pos[1] + dy) in self.blocked or not (-1 <= nx <= 300):
            return
        self.pos = (nx, self.pos[1] + dy)


class MainQuestIO(FakeIO):
    def __init__(self, world, **kw):
        super().__init__(**kw)
        self.w, self.modes, self.looted = world, [], 0

    async def helper(self, command, kind, wait=4.0):
        return self.w.answer(command)

    async def go(self, place):
        self.moves.append(place)
        return True

    async def say(self, text):
        self.w.said.append(text)
        if text == 'oath' and abs(self.w.pos[0] - self.w.NPC) <= 4:
            self.w.armed = True

    async def step(self, dx, dy):
        self.w.step_by(dx, dy)

    async def loot(self):
        self.looted += 1

    def raid_mode(self, names, on, keep_flee=False):
        self.modes.append((list(names), on, keep_flee))


class MainQuestWalk(unittest.TestCase):
    def setUp(self):
        self.keep = (TX.MQ_KILL_BUDGET, TX.MQ_STEP_WAIT)

    def tearDown(self):
        TX.MQ_KILL_BUDGET, TX.MQ_STEP_WAIT = self.keep

    def play(self, **kw):
        w = MainQuestWorld(**kw)
        io = MainQuestIO(w)
        return run(TX.check_mainquest_walk(io, 'Tester Aaa', 'Warrior', 100)), io

    def test_the_verdicts(self):
        base = {'first': 1, 'step': 3, 'level': 100}
        self.assertEqual(TX.mainquest_verdict(dict(base, faults=['x']))[0], TX.FAIL)
        self.assertEqual(TX.mainquest_verdict(base)[0], TX.PASS)
        self.assertIn('steps 1 to 3', TX.mainquest_verdict(base)[1])
        self.assertIn('stopped: a spell', TX.mainquest_verdict(dict(base, why='a spell'))[1])
        self.assertEqual(TX.mainquest_verdict(dict(first=2, step=2, counted=2))[0], TX.PASS)
        self.assertIn('kill counter moved 2', TX.mainquest_verdict(dict(first=2, step=2, counted=2))[1])
        self.assertEqual(TX.mainquest_verdict(dict(first=2, step=2, why='no path'))[0], TX.SKIP)
        self.assertIn('enter npc', TX.mainquest_verdict(dict(base, fallbacks=['enter npc Warden Ysolde (no path)']))[1])
        self.assertIn('mainquest_walk', TX.KEYS)
        self.assertNotIn('mainquest_walk', TX.CLOSED_KEYS)
        self.assertLess(TX.KEYS.index('mainquest_walk'), TX.KEYS.index('rift_walk'))

    def test_the_first_steps_are_played(self):
        r, io = self.play()
        self.assertEqual(r.status, TX.PASS, r.detail)
        self.assertEqual(io.w.said, ['hi', 'oath'])
        self.assertEqual(io.w.teleports, 0, 'the bot walked')
        self.assertGreaterEqual(io.w.step, 3)
        self.assertEqual(io.moves[-1], 'hunt')
        self.assertEqual(io.modes[0], (['Tester Aaa'], True, True))
        self.assertEqual(io.modes[-1], (['Tester Aaa'], False, False))
        self.assertIn('steps 1 to', r.detail)

    def test_a_kill_step_proves_the_counter(self):
        r, io = self.play(start=3)
        self.assertEqual(r.status, TX.PASS, r.detail)
        self.assertIn('kill counter moved 3', r.detail)
        self.assertGreater(io.looted, 0)
        r, _ = self.play(start=4)
        self.assertEqual((r.status, "'spell'" in r.detail), (TX.SKIP, True))

    def test_no_path_is_a_counted_fallback_for_an_npc(self):
        r, io = self.play(no_path=True, kinds=['talk', 'spell'])
        self.assertEqual(r.status, TX.PASS, r.detail)
        self.assertEqual(io.w.teleports, 1)
        self.assertIn('enter npc Warden Ysolde', r.detail)

    def test_the_skips(self):
        r, _ = self.play(err='no main quest system')
        self.assertEqual((r.status, 'no main quest' in r.detail), (TX.SKIP, True))
        r, _ = self.play(enabled=False)
        self.assertEqual((r.status, 'switched off' in r.detail), (TX.SKIP, True))
        r, _ = self.play(staff=True)
        self.assertEqual((r.status, 'staff' in r.detail), (TX.SKIP, True))
        r, _ = self.play(state=0)
        self.assertEqual((r.status, 'not running' in r.detail), (TX.SKIP, True))
        r, _ = self.play(state=2)
        self.assertEqual((r.status, 'finished' in r.detail), (TX.SKIP, True))
        r, _ = self.play(no_path=True, kinds=['visit', 'spell'])
        self.assertEqual((r.status, 'no way on foot' in r.detail), (TX.SKIP, True))
        TX.MQ_KILL_BUDGET = 6.0
        r, _ = self.play(start=3, never_count=True)
        self.assertEqual((r.status, 'died at the place' in r.detail or 'in 6 s' in r.detail), (TX.SKIP, True))

    def test_the_bugs(self):
        TX.MQ_STEP_WAIT = 3.0
        r, io = self.play(stuck_talk=True)
        self.assertEqual(r.status, TX.FAIL)
        self.assertIn('the quest did not move', r.detail)
        self.assertIn('BUG mainquest_walk', r.bug_line())
        r, _ = self.play(start=2, stuck_visit=True)
        self.assertEqual(r.status, TX.FAIL)
        self.assertIn('stands at the place', r.detail)


# ================================================================================================ O650: elite and boss contracts, the daily, the Chronicle,
# the Nemesis, the goblin, Vael, the invasions, the later steps of the main quest
class LaneIO(FakeIO):
    """one lane (y = 5): a world with answer(command), step(dx, dy), reply(opname, action, data) and `dead`"""

    def __init__(self, world, **kw):
        super().__init__(**kw)
        self.w, self.modes, self.cmds, self.looted, self.sent = world, [], [], 0, []

    def alive(self):
        return not getattr(self.w, 'dead', False)

    async def helper(self, command, kind, wait=4.0):
        self.cmds.append(command)
        return self.w.answer(command)

    async def go(self, place):
        self.moves.append(place)
        return True

    async def request(self, opname, action, data, expect, timeout):
        self.sent.append((opname, action, data))
        return self.w.reply(opname, action, data)

    async def step(self, dx, dy):
        self.w.step(dx, dy)

    async def loot(self):
        self.looted += 1

    def raid_mode(self, names, on, keep_flee=False):
        self.modes.append((list(names), on, keep_flee))


class LaneWorld:
    def __init__(self, blocked=(), die_after=None):
        self.pos, self.blocked, self.die_after, self.looks, self.dead = (60, 5), set(blocked), die_after, 0, False

    def look(self):
        self.looks += 1
        if self.die_after is not None and self.looks > self.die_after:
            self.dead = True
            return False
        return True

    def path_to(self, goal, reach):
        x, _ = self.pos
        if x < goal - reach:
            return [1] * (goal - reach - x)
        if x > goal + reach:
            return [3] * (x - goal - reach)
        return []

    def step(self, dx, dy):
        nx = self.pos[0] + dx
        if (nx, self.pos[1] + dy) in self.blocked or not (-1 <= nx <= 300):
            return
        self.pos = (nx, self.pos[1] + dy)

    def at(self):
        return {'x': self.pos[0], 'y': 5, 'z': 7}

    def reply(self, opname, action, data):
        return None


class DailyWorld(LaneWorld):
    def __init__(self, taken=False, err=None, claim_ok=True, reward_ok=True, streak_ok=True, bag_held=3):
        super().__init__()
        self.taken, self.err, self.claim_ok, self.reward_ok, self.streak_ok, self.held = taken, err, claim_ok, reward_ok, streak_ok, bag_held
        self.streak, self.claims = 1, 0

    def facts(self):
        nxt = self.streak + (0 if self.taken else 1)
        return {'taken': self.taken, 'slot': 3, 'value': 1, 'streak': self.streak, 'next': self.streak + 1 if not self.taken else self.streak,
                'reward': {'itemId': 2160, 'count': 2, 'clientId': 3031, 'name': 'crystal coin', 'held': self.held}}

    def answer(self, command):
        if command == 'daily state':
            return {'err': self.err} if self.err else self.facts()
        return None

    def reply(self, opname, action, data):
        if (opname, action) == ('daily', 'calim'):
            self.claims += 1
            if self.claim_ok:
                self.taken = True
                self.streak += 1 if self.streak_ok else 2
                if self.reward_ok:
                    self.held += 2
            return {'action': 'OpenDailyWindow', 'data': {'TakenReward': 1 if self.claim_ok else 0}}
        return {'action': 'OpenDailyWindow', 'data': {'TakenReward': 1 if self.taken else 0}}


class DailyClaim(unittest.TestCase):
    def play(self, **kw):
        w = DailyWorld(**kw)
        io = LaneIO(w)
        return run(TX.check_daily_claim(io, 'Tester Aaa', 'Warrior', 100)), io

    def test_the_claim_pays_and_the_streak_goes_up(self):
        r, io = self.play()
        self.assertEqual(r.status, TX.PASS, r.detail)
        self.assertIn(('daily', 'open', {}), io.sent)
        self.assertIn(('daily', 'calim', 1), io.sent, 'the number the window sends for the slot')
        self.assertIn('2x crystal coin arrived, streak 2', r.detail)
        self.assertIn('daily_claim', TX.KEYS)
        self.assertNotIn('daily_claim', TX.CLOSED_KEYS)

    def test_the_skips(self):
        r, io = self.play(taken=True)
        self.assertEqual((r.status, 'is taken today' in r.detail), (TX.SKIP, True))
        self.assertEqual(io.w.claims, 0, 'a day taken is not claimed again')
        r, _ = self.play(err='no daily system')
        self.assertEqual((r.status, 'no daily' in r.detail), (TX.SKIP, True))

    def test_the_bugs(self):
        r, _ = self.play(claim_ok=False)
        self.assertEqual(r.status, TX.FAIL)
        self.assertIn('left the day open', r.detail)
        self.assertIn('TakenReward 0', r.detail)
        r, _ = self.play(reward_ok=False)
        self.assertEqual(r.status, TX.FAIL)
        self.assertIn('did not arrive', r.detail)
        self.assertIn('BUG daily_claim', r.bug_line())
        r, _ = self.play(streak_ok=False)
        self.assertEqual(r.status, TX.FAIL)
        self.assertIn('the streak is 3, it should be 2', r.detail)


class ChronicleWorld(LaneWorld):
    def __init__(self, **over):
        super().__init__()
        self.facts_ = dict({'enabled': True, 'running': True, 'season': 7, 'chapter': 2, 'chapters': 5, 'counted': False, 'testersListed': 0, 'mine': 0}, **over)
        self.top = ['Ana', 'Bob']

    def answer(self, command):
        return dict(self.facts_) if command == 'chronicle state' else None

    def reply(self, opname, action, data):
        if (opname, action) == ('chronicle', 'open'):
            return {'action': 'state', 'data': {'chapters': [{'top': [{'n': n, 'p': 3} for n in self.top]}], 'record': []}}
        return None


class ChronicleWalk(unittest.TestCase):
    def play(self, top=None, **over):
        w = ChronicleWorld(**over)
        if top is not None:
            w.top = top
        io = LaneIO(w)
        return run(TX.check_chronicle_walk(io, 'Tester Aaa', 'Warrior', 100)), io

    def test_the_window_is_opened_and_no_tester_is_in_the_books(self):
        r, io = self.play()
        self.assertEqual(r.status, TX.PASS, r.detail)
        self.assertEqual([x[:2] for x in io.sent], [('chronicle', 'open'), ('chronicle', 'close')])
        self.assertIn('not counted', r.detail)
        self.assertIn('2 name(s)', r.detail)
        self.assertIn('chronicle_walk', TX.KEYS)

    def test_the_skips(self):
        r, _ = self.play(running=False)
        self.assertEqual((r.status, 'no Chronicle season' in r.detail), (TX.SKIP, True))
        r, _ = self.play(enabled=False)
        self.assertEqual((r.status, 'switched off' in r.detail), (TX.SKIP, True))
        r, _ = self.play(err='no chronicle system')
        self.assertEqual((r.status, 'no chronicle' in r.detail), (TX.SKIP, True))

    def test_the_bugs(self):
        for over, text in ((dict(counted=True), 'would enter the chapter'), (dict(testersListed=2), '2 tester row(s)'), (dict(mine=5), '5 point(s)')):
            r, _ = self.play(**over)
            self.assertEqual(r.status, TX.FAIL, r.detail)
            self.assertIn(text, r.detail)
        r, _ = self.play(top=['Ana', 'Tester Zed'])
        self.assertEqual(r.status, TX.FAIL)
        self.assertIn('the window lists a tester: Tester Zed', r.detail)
        self.assertIn('BUG chronicle_walk', r.bug_line())


class NemesisWorld(LaneWorld):
    """the Nemesis on one lane: a monster in sight, the TEST ONLY birth and call, the Nemesis 4 tiles from the bot; it loses `step` percent for every look
    the bot is within 5 tiles"""
    def __init__(self, sight=True, born_err=None, appear_err=None, never_arrive=False, step=40, never_hurt=False, die_after=None, enabled=True, level=100, has=False,
                 record_stays=False, fade=False, far=False, blocked=(), min_level=50):
        super().__init__(blocked=blocked, die_after=die_after)
        self.sight, self.born_err, self.appear_err, self.never_arrive, self.step_hp = sight, born_err, appear_err, never_arrive, step
        self.never_hurt, self.enabled, self.level, self.has, self.record_stays, self.fade, self.far, self.min_level = never_hurt, enabled, level, has, record_stays, fade, far, min_level
        self.nem, self.hp, self.avenged, self.pending, self.closes, self.born_calls = None, 100, 0, False, 0, 0

    def facts(self):
        out = {'enabled': self.enabled, 'level': self.level, 'minLevel': self.min_level, 'pos': self.at(), 'avenged': self.avenged, 'has': self.has,
               'pending': self.pending}
        if self.has:
            out['nemesis'] = {'name': 'Varkh', 'monster': 'Ghoul', 'level': 120}
        elif self.sight:
            out['sight'] = {'name': 'Ghoul', 'distance': 2}
        if self.nem is not None:
            out['world'] = {'pos': {'x': self.nem, 'y': 5, 'z': 7}, 'hp': self.hp, 'level': 120}
            near = abs(self.nem - self.pos[0]) <= 5
            out['guide'] = {'mode': 'fight' if near else 'walk', 'goal': {'x': self.nem, 'y': 5, 'z': 7}, 'reach': [1, 5], 'area': 'nemesis'}
        else:
            out['guide'] = {'mode': 'wait', 'why': 'no Nemesis'}
        return out

    def tick(self):
        if not self.look():
            return
        if self.pending and not self.never_arrive:
            self.pending, self.nem = False, (self.pos[0] + 4 if not self.far else 100)
            return
        if self.nem is None:
            return
        if self.fade and self.hp == 100 and self.looks > 6:
            self.nem = None
            return
        if abs(self.nem - self.pos[0]) <= 5 and not self.never_hurt:
            self.hp -= self.step_hp
            if self.hp <= 0:
                self.nem, self.avenged = None, self.avenged + 1
                self.has = self.record_stays

    def answer(self, command):
        if command == 'nemesis state':
            self.tick()
            return self.facts()
        if command == 'nemesis born':
            self.born_calls += 1
            if self.born_err:
                return dict(self.facts(), err=self.born_err)
            self.has = True
            return dict(self.facts(), born=True)
        if command == 'nemesis appear':
            if self.appear_err:
                return dict(self.facts(), err=self.appear_err)
            self.pending = True
            return dict(self.facts(), appear=True)
        if command == 'nemesis path':
            g = self.facts()['guide']
            if g['mode'] != 'walk':
                return dict(self.facts(), err='no goal')
            return dict(self.facts(), path=self.path_to(g['goal']['x'], g['reach'][1]))
        if command == 'nemesis close':
            self.closes += 1
            self.nem, self.has, self.pending = None, False, False
            return dict(self.facts(), closed=True)
        return None


class NemesisWalk(unittest.TestCase):
    def setUp(self):
        self.keep = (TX.NEMESIS_BUDGET, TX.SOLO_FIGHT_MIN, TX.SOLO_STUCK, TX.NEMESIS_SIGHT_WAIT, TX.NEMESIS_ARRIVE_WAIT)

    def tearDown(self):
        TX.NEMESIS_BUDGET, TX.SOLO_FIGHT_MIN, TX.SOLO_STUCK, TX.NEMESIS_SIGHT_WAIT, TX.NEMESIS_ARRIVE_WAIT = self.keep

    def play(self, **kw):
        w = NemesisWorld(**kw)
        io = LaneIO(w)
        return run(TX.check_nemesis_walk(io, 'Tester Aaa', 'Warrior', 100)), io

    def test_the_verdicts(self):
        base = {'level': 100, 'steps': 3, 'secs': 20, 'name': 'Varkh', 'avenged': 1}
        self.assertEqual(TX.nemesis_walk_verdict(dict(base, faults=['x']))[0], TX.FAIL)
        self.assertEqual(TX.nemesis_walk_verdict(dict(base, killed=True))[0], TX.PASS)
        self.assertIn('slain, avenged 1', TX.nemesis_walk_verdict(dict(base, killed=True))[1])
        self.assertIn('hurt to 40%', TX.nemesis_walk_verdict(dict(base, hp=40))[1])
        self.assertEqual(TX.nemesis_walk_verdict(dict(base, hp=100, fought=TX.SOLO_FIGHT_MIN))[0], TX.FAIL)
        for key in ('stuck', 'died', 'faded'):
            self.assertEqual(TX.nemesis_walk_verdict(dict(base, **{key: (1, 2) if key == 'stuck' else True}))[0], TX.SKIP)
        self.assertEqual(TX.nemesis_walk_verdict(base)[0], TX.SKIP)
        self.assertIn('nemesis_walk', TX.KEYS)
        self.assertNotIn('nemesis_walk', TX.CLOSED_KEYS)

    def test_it_is_born_called_and_slain(self):
        r, io = self.play()
        self.assertEqual(r.status, TX.PASS, r.detail)
        self.assertIn('slain', r.detail)
        self.assertLess(io.cmds.index('nemesis born'), io.cmds.index('nemesis appear'))
        self.assertEqual(io.cmds[-1], 'nemesis close', 'the record and the monster go after the run')
        self.assertEqual(io.moves[-1], 'hunt')
        self.assertEqual(io.modes[0], (['Tester Aaa'], True, True))
        self.assertEqual(io.modes[-1], (['Tester Aaa'], False, False))
        self.assertFalse(io.w.has)

    def test_a_bot_far_from_it_walks_to_it(self):
        r, io = self.play(far=True, step=100)
        self.assertEqual(r.status, TX.PASS, r.detail)
        self.assertIn('nemesis path', io.cmds)
        self.assertGreater(io.w.pos[0], 80)

    def test_a_record_left_by_an_earlier_run_goes_first(self):
        r, io = self.play(has=True)
        self.assertEqual(r.status, TX.PASS, r.detail)
        self.assertEqual(io.cmds.count('nemesis close'), 2)
        self.assertLess(io.cmds.index('nemesis close'), io.cmds.index('nemesis born'))

    def test_the_skips(self):
        r, _ = self.play(enabled=False)
        self.assertEqual((r.status, 'switched off' in r.detail), (TX.SKIP, True))
        r, io = self.play(level=30)
        self.assertEqual((r.status, 'born from level 50' in r.detail), (TX.SKIP, True))
        self.assertEqual(io.w.born_calls, 0)
        TX.NEMESIS_SIGHT_WAIT = 6.0
        r, io = self.play(sight=False)
        self.assertEqual((r.status, 'no regular monster in sight' in r.detail), (TX.SKIP, True))
        self.assertEqual(io.w.born_calls, 0, 'nothing is born without a monster in sight')
        r, _ = self.play(born_err='the bot has a Nemesis already')
        self.assertEqual((r.status, 'was not born' in r.detail), (TX.SKIP, True))
        r, _ = self.play(appear_err='the bot stands in a protection zone')
        self.assertEqual((r.status, 'not called' in r.detail or 'was not called' in r.detail), (TX.SKIP, True))
        TX.NEMESIS_ARRIVE_WAIT = 4.0
        r, io = self.play(never_arrive=True)
        self.assertEqual((r.status, 'did not arrive' in r.detail), (TX.SKIP, True))
        self.assertGreaterEqual(io.w.closes, 1, 'the record goes even when it never came')
        r, _ = self.play(die_after=2)
        self.assertEqual(r.status, TX.SKIP)
        r, _ = self.play(fade=True, never_hurt=True)
        self.assertEqual((r.status, 'faded' in r.detail), (TX.SKIP, True))
        TX.SOLO_STUCK = 4.0
        r, _ = self.play(far=True, blocked=[(61, 5)])
        self.assertEqual((r.status, 'blocked' in r.detail), (TX.SKIP, True))

    def test_the_bugs(self):
        TX.SOLO_FIGHT_MIN = 8.0
        r, io = self.play(never_hurt=True)
        self.assertEqual(r.status, TX.FAIL)
        self.assertIn('health did not move', r.detail)
        self.assertIn('BUG nemesis_walk', r.bug_line())
        self.assertGreaterEqual(io.w.closes, 1)
        r, _ = self.play(record_stays=True)
        self.assertEqual(r.status, TX.FAIL)
        self.assertIn('record is still there', r.detail)


class GoblinWorld(LaneWorld):
    """a treasure goblin of the bot's own on one lane: 5 tiles away, asleep until hit; after the first hit it moves 1 tile away every look and
    escapes after `escape` looks; `hits` hits kill it"""
    def __init__(self, err=None, spawn_err=None, hits=2, escape=99, never_hit=False, die_after=None, blocked=(), has=False, far=False):
        super().__init__(blocked=blocked, die_after=die_after)
        self.err, self.spawn_err, self.hits, self.escape, self.never_hit, self.has, self.far = err, spawn_err, hits, escape, never_hit, has, far
        self.gob, self.hit, self.taken, self.killed, self.since, self.closes = None, 0, 0, 0, 0, 0

    def facts(self):
        out = {'killed': self.killed, 'world': 0, 'pos': self.at(), 'cancelled': 0}
        if self.gob is not None:
            near = abs(self.gob - self.pos[0]) <= 5
            out['goblin'] = {'pos': {'x': self.gob, 'y': 5, 'z': 7}, 'hp': 100 - 50 * self.taken, 'hit': self.hit > 0}
            out['guide'] = {'mode': 'fight' if near else 'walk', 'goal': {'x': self.gob, 'y': 5, 'z': 7}, 'reach': [1, 5], 'area': 'goblin'}
        else:
            out['guide'] = {'mode': 'wait', 'why': 'no goblin of its own'}
        return out

    def tick(self):
        if not self.look() or self.gob is None:
            return
        near = abs(self.gob - self.pos[0]) <= 5
        if self.hit:
            self.since += 1
            if self.since > self.escape:
                self.gob = None
                return
            self.gob += 1
        if near and not self.never_hit:
            self.hit += 1
            self.taken += 1
            if self.taken >= self.hits:
                self.gob, self.killed = None, self.killed + 1

    def answer(self, command):
        if command == 'goblin state':
            if self.err:
                return {'err': self.err}
            if self.has and self.gob is None and command == 'goblin state' and not self.looks:
                self.gob = self.pos[0] + 5
            self.tick()
            return self.facts()
        if command == 'goblin spawn':
            if self.spawn_err:
                return dict(self.facts(), err=self.spawn_err)
            self.gob = self.pos[0] + (40 if self.far else 5)
            return dict(self.facts(), spawned=True)
        if command == 'goblin path':
            g = self.facts()['guide']
            if g['mode'] != 'walk':
                return dict(self.facts(), err='no goal')
            return dict(self.facts(), path=self.path_to(g['goal']['x'], g['reach'][1]))
        if command == 'goblin close':
            self.closes += 1
            self.gob = None
            return dict(self.facts(), closed=True)
        return None


class GoblinWalk(unittest.TestCase):
    def setUp(self):
        self.keep = (TX.GOBLIN_BUDGET, TX.SOLO_FIGHT_MIN, TX.SOLO_STUCK)

    def tearDown(self):
        TX.GOBLIN_BUDGET, TX.SOLO_FIGHT_MIN, TX.SOLO_STUCK = self.keep

    def play(self, **kw):
        w = GoblinWorld(**kw)
        io = LaneIO(w)
        return run(TX.check_goblin_walk(io, 'Tester Aaa', 'Warrior', 100)), io

    def test_the_verdicts(self):
        base = {'level': 100, 'steps': 3, 'secs': 20}
        self.assertEqual(TX.goblin_walk_verdict(dict(base, faults=['x']))[0], TX.FAIL)
        self.assertEqual(TX.goblin_walk_verdict(dict(base, killed=1))[0], TX.PASS)
        self.assertEqual(TX.goblin_walk_verdict(dict(base, hit=True))[0], TX.PASS)
        self.assertIn('it escaped', TX.goblin_walk_verdict(dict(base, hit=True))[1])
        self.assertEqual(TX.goblin_walk_verdict(dict(base, fought=TX.SOLO_FIGHT_MIN))[0], TX.FAIL)
        self.assertEqual(TX.goblin_walk_verdict(dict(base, stuck=(1, 2)))[0], TX.SKIP)
        self.assertEqual(TX.goblin_walk_verdict(dict(base, died=True))[0], TX.SKIP)
        self.assertEqual(TX.goblin_walk_verdict(base)[0], TX.SKIP)
        self.assertIn('goblin_walk', TX.KEYS)

    def test_the_goblin_is_chased_and_killed(self):
        r, io = self.play(far=True)
        self.assertEqual(r.status, TX.PASS, r.detail)
        self.assertIn('killed the goblin', r.detail)
        self.assertEqual(io.cmds[-1], 'goblin close')
        self.assertEqual(io.moves[-1], 'hunt')
        self.assertIn('goblin path', io.cmds, 'it ran: the bot walked after it')
        self.assertGreater(io.looted, 0)
        self.assertEqual(io.modes[-1], (['Tester Aaa'], False, False))

    def test_a_goblin_that_escapes_after_a_hit_is_a_pass(self):
        r, _ = self.play(hits=9, escape=2)
        self.assertEqual(r.status, TX.PASS, r.detail)
        self.assertIn('it escaped', r.detail)

    def test_the_skips(self):
        r, _ = self.play(err='no treasure goblin system')
        self.assertEqual((r.status, 'no treasure goblin' in r.detail), (TX.SKIP, True))
        r, io = self.play(spawn_err='a player is near: the goblin is not made')
        self.assertEqual((r.status, 'a player is near' in r.detail), (TX.SKIP, True))
        self.assertEqual(io.cmds[-1], 'goblin close')
        r, _ = self.play(die_after=2, hits=99, never_hit=True)
        self.assertEqual(r.status, TX.SKIP)
        TX.SOLO_STUCK = 4.0
        r, _ = self.play(hits=99, never_hit=True, far=True, blocked=[(61, 5)])
        self.assertEqual((r.status, 'blocked' in r.detail), (TX.SKIP, True))

    def test_the_bugs(self):
        TX.SOLO_FIGHT_MIN = 6.0
        r, io = self.play(never_hit=True)
        self.assertEqual(r.status, TX.FAIL)
        self.assertIn('did not hit it', r.detail)
        self.assertIn('BUG goblin_walk', r.bug_line())
        self.assertGreaterEqual(io.w.closes, 1)


class InvasionWorld(LaneWorld):
    def __init__(self, running=True, err=None, credited=False, landed=False, die_after=None, blocked=(), start_cancelled=0):
        super().__init__(blocked=blocked, die_after=die_after)
        self.running, self.err, self.credited, self.landed, self.cancelled = running, err, credited, landed, start_cancelled
        self.inv = 90

    def facts(self):
        out = {'phase': 'running' if self.running else 'idle', 'running': self.running, 'level': 300, 'pos': self.at(), 'credited': self.credited,
               'cancelled': self.cancelled, 'invader': {'x': self.inv, 'y': 5, 'z': 7, 'name': 'Orc Raider', 'hp': 80}}
        near = abs(self.inv - self.pos[0]) <= 5
        out['guide'] = {'mode': 'fight' if near else 'walk', 'goal': {'x': self.inv, 'y': 5, 'z': 7}, 'reach': [1, 5], 'area': 'invader'}
        return out

    def answer(self, command):
        if command == 'invasion state':
            if self.err:
                return {'err': self.err}
            if self.look() and abs(self.inv - self.pos[0]) <= 5 and not self.landed:
                self.cancelled += 1
            return self.facts()
        if command == 'invasion path':
            g = self.facts()['guide']
            return dict(self.facts(), path=self.path_to(g['goal']['x'], g['reach'][1])) if g['mode'] == 'walk' else dict(self.facts(), err='no goal')
        return None


class InvasionWalk(unittest.TestCase):
    def setUp(self):
        self.keep = (TX.INVASION_BUDGET, TX.SOLO_FIGHT_MIN, TX.SOLO_STUCK)

    def tearDown(self):
        TX.INVASION_BUDGET, TX.SOLO_FIGHT_MIN, TX.SOLO_STUCK = self.keep

    def play(self, **kw):
        w = InvasionWorld(**kw)
        io = LaneIO(w)
        return run(TX.check_invasion_walk(io, 'Tester Aaa', 'Warrior', 100)), io

    def test_the_verdicts(self):
        base = {'level': 300, 'steps': 3, 'secs': 20}
        self.assertEqual(TX.invasion_walk_verdict(dict(base, faults=['x']))[0], TX.FAIL)
        self.assertEqual(TX.invasion_walk_verdict(dict(base, cancelled=2))[0], TX.PASS)
        self.assertIn('2 hit(s)', TX.invasion_walk_verdict(dict(base, cancelled=2))[1])
        self.assertEqual(TX.invasion_walk_verdict(dict(base, cancelled=0, fought=TX.SOLO_FIGHT_MIN))[0], TX.FAIL)
        self.assertEqual(TX.invasion_walk_verdict(dict(base, stuck=(1, 2)))[0], TX.SKIP)
        self.assertEqual(TX.invasion_walk_verdict(dict(base, died=True))[0], TX.SKIP)
        self.assertEqual(TX.invasion_walk_verdict(base)[0], TX.SKIP)
        self.assertIn('invasion_walk', TX.KEYS)

    def test_the_bot_walks_to_the_invaders_and_its_hits_are_cancelled(self):
        r, io = self.play()
        self.assertEqual(r.status, TX.PASS, r.detail)
        self.assertIn('invasion path', io.cmds)
        self.assertGreater(io.w.pos[0], 80)
        self.assertEqual(io.moves[-1], 'hunt')

    def test_the_skips(self):
        r, _ = self.play(err='no invasion system')
        self.assertEqual((r.status, 'no invasion system' in r.detail), (TX.SKIP, True))
        r, io = self.play(running=False)
        self.assertEqual((r.status, 'no invasion is running' in r.detail), (TX.SKIP, True))
        self.assertEqual(io.cmds, ['invasion state'], 'nothing runs: the bot does not move')
        r, _ = self.play(die_after=2)
        self.assertEqual(r.status, TX.SKIP)
        TX.SOLO_STUCK = 4.0
        r, _ = self.play(blocked=[(61, 5)])
        self.assertEqual((r.status, 'blocked' in r.detail), (TX.SKIP, True))

    def test_the_bugs(self):
        r, _ = self.play(credited=True)
        self.assertEqual(r.status, TX.FAIL)
        self.assertIn('contribution book', r.detail)
        self.assertIn('BUG invasion_walk', r.bug_line())
        TX.SOLO_FIGHT_MIN = 6.0
        r, _ = self.play(landed=True)
        self.assertEqual(r.status, TX.FAIL)
        self.assertIn('no hit was cancelled', r.detail)


class VaelWorld(SoloWorld):
    """Vael's chamber: the trial world with the commands of `!tester vael` (state, enter = the TEST ONLY door, path, close)"""
    def __init__(self, min_level=500, enter_err=None, level=900, **kw):
        super().__init__('trial', level=level, **kw)
        self.min_level, self.enter_err = min_level, enter_err

    def facts(self):
        out = super().facts()
        out.update(minLevel=self.min_level, won=False, tries=0, door='door_closed')
        return out

    def answer(self, command):
        head, _, rest = command.partition(' ')
        if head != 'vael':
            return super().answer(command)
        if rest == 'enter':
            if self.enter_err:
                return dict(self.facts(), err=self.enter_err)
            self.open()
            return dict(self.facts(), entered=True)
        return super().answer('trial ' + rest)


class VaelWalk(unittest.TestCase):
    def setUp(self):
        self.keep = (TX.VAEL_BUDGET, TX.SOLO_FIGHT_MIN, TX.SOLO_STUCK)

    def tearDown(self):
        TX.VAEL_BUDGET, TX.SOLO_FIGHT_MIN, TX.SOLO_STUCK = self.keep

    def play(self, **kw):
        w = VaelWorld(**kw)
        io = SoloIO(w)
        return run(TX.check_vael_walk(io, 'Tester Aaa', 'Warrior', w.level)), io

    def test_the_verdicts(self):
        base = {'level': 600, 'came': 'foot', 'steps': 20, 'secs': 60}
        self.assertEqual(TX.vael_walk_verdict(dict(base, faults=['x']))[0], TX.FAIL)
        self.assertIn('Vael hurt to 60%', TX.vael_walk_verdict(dict(base, killed=4, boss_seen=True, hp=60))[1])
        self.assertEqual(TX.vael_walk_verdict(dict(base, killed=2))[0], TX.PASS)
        self.assertEqual(TX.vael_walk_verdict(dict(base, fought=TX.SOLO_FIGHT_MIN))[0], TX.FAIL)
        self.assertEqual(TX.vael_walk_verdict(dict(base, puzzle='seals'))[0], TX.SKIP)
        self.assertEqual(TX.vael_walk_verdict(dict(base, stuck=(1, 2)))[0], TX.SKIP)
        self.assertEqual(TX.vael_walk_verdict(dict(base, died=True, lives=0))[0], TX.SKIP)
        self.assertEqual(TX.vael_walk_verdict(base)[0], TX.SKIP)
        self.assertIn('vael_walk', TX.KEYS)
        self.assertNotIn('vael_walk', TX.CLOSED_KEYS)

    def test_vael_is_entered_through_the_test_only_door_and_fought(self):
        r, io = self.play()
        self.assertEqual(r.status, TX.PASS, r.detail)
        self.assertIn('Vael hurt to', r.detail)
        self.assertEqual(io.w.teleports, 0, 'the bot walked to the temple')
        self.assertLess(io.cmds.index('path temple'), io.cmds.index('vael enter'))
        self.assertLess(io.cmds.index('vael enter'), io.cmds.index('vael path'))
        self.assertFalse(io.w.inside)
        self.assertEqual(io.moves[-1], 'hunt')

    def test_the_skips(self):
        r, _ = self.play(err='no main quest boss')
        self.assertEqual((r.status, 'no main quest boss' in r.detail), (TX.SKIP, True))
        r, io = self.play(level=300, min_level=500)
        self.assertEqual((r.status, 'needs level 500' in r.detail), (TX.SKIP, True))
        self.assertEqual(io.w.starts, 0)
        r, _ = self.play(inside=True)
        self.assertEqual((r.status, 'inside' in r.detail), (TX.SKIP, True))
        r, _ = self.play(free=2)
        self.assertEqual((r.status, 'kept for the players' in r.detail), (TX.SKIP, True))
        r, _ = self.play(family=None)
        self.assertEqual((r.status, 'no trial family' in r.detail), (TX.SKIP, True))
        r, io = self.play(puzzle=True, family='mystic')
        self.assertEqual((r.status, 'puzzle' in r.detail), (TX.SKIP, True))
        self.assertEqual(io.w.starts, 0, 'a puzzle stage is not even entered')
        r, io = self.play(pz=False)
        self.assertEqual(r.status, TX.SKIP)
        self.assertEqual(io.w.starts, 0)
        r, io = self.play(enter_err="Vael's door opens from level 500")
        self.assertEqual((r.status, 'door stayed shut' in r.detail, 'opens from level 500' in r.detail), (TX.SKIP, True, True))
        r, _ = self.play(die_after=1)
        self.assertEqual((r.status, 'lives ran out' in r.detail), (TX.SKIP, True))

    def test_the_bugs(self):
        TX.SOLO_FIGHT_MIN = 8.0
        r, io = self.play(never_kill=True)
        self.assertEqual(r.status, TX.FAIL)
        self.assertIn("killed none", r.detail)
        self.assertIn('BUG vael_walk', r.bug_line())
        self.assertGreaterEqual(io.w.closed, 1)


class BountyKinds(unittest.TestCase):
    """the elite and the boss contract through the same loop as the hunt contract (BountyWorld with `type`, `tier`, a crowd)"""

    def play(self, kind, world=None, **kw):
        w = world or BountyWorld(**kw)
        w.kind = kind
        io = BountyIO(w)
        fn = {'elite': TX.check_bounty_elite_walk, 'boss': TX.check_bounty_boss_walk, 'hunt': TX.check_bounty_walk}[kind]
        return run(fn(io, 'Tester Aaa', 'Warrior', 100)), io

    def test_the_pick(self):
        a = {'level': 100, 'active': [{'key': 'h', 'status': 0, 'required': 60}], 'candidates': [{'key': 'c'}], 'elite': [{'key': 'e'}], 'boss': [{'key': 'b'}]}
        self.assertEqual(TX.bounty_pick(a, 'hunt'), (a['active'][0], True))
        self.assertEqual(TX.bounty_pick(a, 'elite'), ({'key': 'e'}, False), 'a hunt contract held is no elite contract')
        self.assertEqual(TX.bounty_pick(a, 'boss'), ({'key': 'b'}, False))
        a['active'].append({'key': 'x', 'status': 0, 'required': 4, 'type': 'elite'})
        self.assertEqual(TX.bounty_pick(a, 'elite')[0]['key'], 'x')
        self.assertTrue(TX.bounty_pick(a, 'elite')[1])
        row, why = TX.bounty_pick({'level': 100, 'active': []}, 'elite')
        self.assertIsNone(row)
        self.assertIn('no elite contract', why)
        row, why = TX.bounty_pick({'level': 100, 'active': []}, 'boss')
        self.assertIn('open boss mark', why)

    def test_the_verdicts(self):
        base = {'level': 100, 'steps': 10, 'secs': 50, 'name': 'Wyrm', 'base': 0, 'progress': 1, 'required': 2, 'kind': 'elite', 'need': 1}
        self.assertEqual(TX.bounty_walk_verdict(base)[0], TX.PASS)
        self.assertEqual(TX.bounty_walk_verdict(dict(base, progress=0, fought=TX.SOLO_FIGHT_MIN))[0], TX.FAIL)
        boss = dict(base, kind='boss', progress=0, fought=TX.SOLO_FIGHT_MIN)
        self.assertEqual(TX.bounty_walk_verdict(boss)[0], TX.SKIP, 'a boss that did not fall in 150 s is no bug')
        self.assertIn('did not fall', TX.bounty_walk_verdict(boss)[1])
        crowd = TX.bounty_walk_verdict(dict(base, kind='boss', progress=0, crowd=TX.BOUNTY_CROWD_WAIT))
        self.assertEqual(crowd[0], TX.SKIP)
        self.assertIn('a player is near', crowd[1])
        self.assertEqual(TX.bounty_walk_verdict(dict(base, kind='boss', progress=0, waited=TX.BOUNTY_BOSS_WAIT))[0], TX.SKIP)
        self.assertIn('lair', TX.bounty_walk_verdict(dict(base, kind='boss', progress=0, waited=TX.BOUNTY_BOSS_WAIT))[1])
        self.assertEqual(TX.bounty_walk_verdict(dict(base, kind='boss', progress=0, waited=TX.BOUNTY_SPAWN_WAIT))[0], TX.SKIP)
        for k in ('bounty_elite_walk', 'bounty_boss_walk'):
            self.assertIn(k, TX.KEYS)
            self.assertNotIn(k, TX.CLOSED_KEYS)
            self.assertLess(TX.KEYS.index(k), TX.KEYS.index('rift_walk'))
        self.assertEqual(TX.BOUNTY_NEED, {'hunt': 3, 'elite': 1, 'boss': 1})

    def test_an_elite_contract_counts_one_kill(self):
        class Elite(BountyWorld):
            def facts(self):
                out = super().facts()
                out['elite'] = [{'key': '1-3', 'name': 'Rat', 'count': 5, 'level': 4, 'tier': 'magic', 'mark': {'x': self.HUNT, 'y': 5, 'z': 7}}]
                out['candidates'] = []
                return out
        w = Elite()
        io = BountyIO(w)
        r = run(TX.check_bounty_elite_walk(io, 'Tester Aaa', 'Warrior', 100))
        self.assertEqual(r.status, TX.PASS, r.detail)
        self.assertEqual((w.accepts, w.abandons), (1, 1))
        self.assertIn(('bounty', 'accept', {'key': '1-3'}), io.sent)
        self.assertLessEqual(w.mine()['progress'] if w.mine() else 1, 1)

    def test_a_boss_contract_leaves_a_boss_the_players_are_at(self):
        class Boss(BountyWorld):
            crowd = False

            def facts(self):
                out = super().facts()
                out['boss'] = [{'key': '1-4', 'name': 'The Collector', 'count': 1, 'level': 16, 'mark': {'x': self.HUNT, 'y': 5, 'z': 7}}]
                out['candidates'] = []
                return out

            def guide(self):
                if self.crowd:
                    return {'mode': 'wait', 'area': 'crowd', 'why': 'a player is near'}
                return super().guide()
        w = Boss()
        w.crowd = True
        io = BountyIO(w)
        r = run(TX.check_bounty_boss_walk(io, 'Tester Aaa', 'Warrior', 100))
        self.assertEqual((r.status, 'a player is near' in r.detail), (TX.SKIP, True))
        self.assertEqual(w.abandons, 1, 'the contract goes back')
        w2 = Boss()
        io2 = BountyIO(w2)
        r2 = run(TX.check_bounty_boss_walk(io2, 'Tester Aaa', 'Warrior', 100))
        self.assertEqual(r2.status, TX.PASS, r2.detail)
        self.assertIn('The Collector', r2.detail)
        r3, _ = self.play('elite', candidates=False)
        self.assertEqual((r3.status, 'no elite contract' in r3.detail), (TX.SKIP, True))


class MainQuestLaterWorld(MainQuestWorld):
    """the later steps: bring, go, daily, cast, hunt, vael on top of the first lane"""
    def __init__(self, kinds, **kw):
        super().__init__(kinds=kinds, **kw)
        self.go_sent, self.daily_taken, self.daily_claims, self.cast_after, self.hunt_after = 0, False, 0, 3, 3
        self.kill_target = 2
        self.go_ok, self.daily_ok, self.bring_ok, self.hunt_ok, self.cast_ok = True, True, True, True, True

    def plan(self):
        kind = self.kinds[self.step - 1]
        if kind == 'bring':
            return {'action': 'bring', 'label': 'Warden Ysolde', 'flag': 'tusks'}
        if kind == 'go':
            return {'action': 'go', 'flag': 'pets'}
        if kind == 'daily':
            return {'action': 'daily', 'flag': 'daily'}
        if kind == 'cast':
            return {'action': 'cast'}
        if kind == 'hunt':
            return {'action': 'hunt', 'stat': 'kills_magic', 'target': 1}
        if kind == 'vael':
            return {'action': 'vael', 'reason': 'the boss'}
        return super().plan()

    def facts(self):
        out = super().facts()
        kind = self.kinds[self.step - 1] if self.step <= len(self.kinds) else ''
        if kind in ('cast', 'hunt'):
            out['where'] = {'k': 'pos', 'pos': {'x': self.TROLLS, 'y': 5, 'z': 7}}
        return out

    def tick(self):
        super().tick()
        if self.step > len(self.kinds):
            return
        kind = self.kinds[self.step - 1]
        if kind == 'kill' and self.progress >= self.kill_target:
            self.step, self.progress = self.step + 1, 0
        elif kind == 'bring' and self.armed and self.bring_ok:
            self.step, self.armed = self.step + 1, False
        elif kind == 'cast' and abs(self.pos[0] - self.TROLLS) <= 6 and self.cast_ok:
            self.cast_after -= 1
            if self.cast_after <= 0:
                self.step += 1
        elif kind == 'hunt' and abs(self.pos[0] - self.TROLLS) <= 6 and self.hunt_ok:
            self.hunt_after -= 1
            if self.hunt_after <= 0:
                self.step += 1

    def answer(self, command):
        if command == 'daily state':
            return {'taken': self.daily_taken, 'slot': 1, 'value': 6, 'streak': 0, 'next': 1, 'reward': {'itemId': 1, 'count': 1, 'held': 0 if not self.daily_taken else 1}} \
                if not self.daily_taken else {'taken': True, 'slot': 1, 'value': 6, 'streak': 1, 'next': 1, 'reward': {'itemId': 1, 'count': 1, 'held': 1}}
        return super().answer(command)


class MainQuestLaterIO(MainQuestIO):
    async def request(self, opname, action, data, expect, timeout):
        w = self.w
        if (opname, action) == ('goals', 'mqGo'):
            w.go_sent += 1
            if w.go_ok and w.kinds[w.step - 1] == 'go':
                w.step += 1
            return {'action': 'welcome'}
        if (opname, action) == ('daily', 'calim'):
            w.daily_claims += 1
            w.daily_taken = True
            if w.daily_ok and w.kinds[w.step - 1] == 'daily':
                w.step += 1
            return {'action': 'OpenDailyWindow', 'data': {'TakenReward': 1}}
        return None


class MainQuestLater(unittest.TestCase):
    def setUp(self):
        self.keep = (TX.MQ_KILL_BUDGET, TX.MQ_STEP_WAIT, TX.MQ_CAST_WAIT, TX.MQ_HUNT_BUDGET)

    def tearDown(self):
        TX.MQ_KILL_BUDGET, TX.MQ_STEP_WAIT, TX.MQ_CAST_WAIT, TX.MQ_HUNT_BUDGET = self.keep

    def play(self, kinds, start=1, **kw):
        w = MainQuestLaterWorld(kinds, start=start)
        for k, v in kw.items():
            setattr(w, k, v)
        io = MainQuestLaterIO(w)
        return run(TX.check_mainquest_walk(io, 'Tester Aaa', 'Warrior', 100)), io

    def test_a_flag_of_the_go_button_is_pressed(self):
        r, io = self.play(['go', 'spell'])
        self.assertEqual(r.status, TX.PASS, r.detail)
        self.assertEqual(io.w.go_sent, 1)
        self.assertIn('steps 1 to 2', r.detail)
        r, io = self.play(['go', 'spell'], go_ok=False)
        self.assertEqual(r.status, TX.FAIL)
        self.assertIn('the Go button was pressed for pets and the quest did not move', r.detail)

    def test_the_daily_flag_is_a_claim(self):
        r, io = self.play(['daily', 'spell'])
        self.assertEqual(r.status, TX.PASS, r.detail)
        self.assertEqual(io.w.daily_claims, 1)
        r, io = self.play(['daily', 'spell'], daily_taken=True)
        self.assertEqual(r.status, TX.SKIP)
        self.assertIn('is taken today', r.detail)
        self.assertEqual(io.w.daily_claims, 0)
        r, _ = self.play(['daily', 'spell'], daily_ok=False)
        self.assertEqual(r.status, TX.FAIL)
        self.assertIn('the daily was claimed and the quest did not move', r.detail)

    def test_a_bring_step_hands_the_drops_over(self):
        r, io = self.play(['kill', 'bring', 'spell'], start=1)
        self.assertEqual(r.status, TX.PASS, r.detail)
        self.assertEqual(io.w.said.count('oath'), 1, 'the kill step has no words')
        self.assertEqual(io.w.step, 3, 'the drops were collected in this run: the bring step moved')
        # the bring step alone: the drops were not collected in this run, so a step that does not move is no bug of the bot
        TX.MQ_STEP_WAIT = 3.0
        r, io = self.play(['bring', 'spell'], bring_ok=False)
        self.assertEqual(r.status, TX.SKIP)
        self.assertIn('the drops of the kill step before it are not in the bag', r.detail)
        self.assertEqual(io.w.said, ['hi', 'oath'])

    def test_a_cast_and_a_tier_kill_are_hunted(self):
        r, io = self.play(['cast', 'spell'])
        self.assertEqual(r.status, TX.PASS, r.detail)
        self.assertGreater(io.looted, 0)
        r, _ = self.play(['hunt', 'spell'])
        self.assertEqual(r.status, TX.PASS, r.detail)
        TX.MQ_CAST_WAIT, TX.MQ_HUNT_BUDGET = 5.0, 5.0
        r, _ = self.play(['cast', 'spell'], cast_ok=False)
        self.assertEqual((r.status, 'no spell was cast' in r.detail), (TX.SKIP, True))
        r, _ = self.play(['hunt', 'spell'], hunt_ok=False)
        self.assertEqual((r.status, 'kills_magic monster died' in r.detail), (TX.SKIP, True))

    def test_vael_has_his_own_check(self):
        r, _ = self.play(['vael'])
        self.assertEqual((r.status, 'vael_walk' in r.detail), (TX.SKIP, True))


# ---------------------------------------------------------------- economy, crafting and progression chores (O653)
class FoundIO(FakeIO):
    """a mocked backpack of a bot that dropped things: one plain piece in slot 0, the bot's orbs, a gem, a rune; the crafting window and the tooltip
    answer from it. `uncounted`: an orb the window forgets to count off; `piece`: the facts of the piece"""

    def __init__(self, orbs=None, gems=0, runes=0, uncounted=None, piece=None, err=None, chase=5):
        FakeIO.__init__(self)
        self.orbs, self.gems, self.runes, self.uncounted, self.err = dict(orbs or {}), gems, runes, uncounted, err
        self.item = dict({'rarity': 0, 'mods': [], 'quality': 0, 'qcap': 2, 'sockets': 0, 'max': 2, 'socketed': 0, 'unique': False, 'maxMods': 4}, **(piece or {}))
        self.chase, self.uses, self.support = chase, [], {'id': 9, 'name': 'Fire Bolt', 'count': 2, 'max': 3, 'runes': []}
        self.worn, self.sets, self.wore = {4: {'s': 4, 'sc': 10}}, {}, None
        self.piece = {'i': 0, 'id': 2400, 'cid': 3300, 's': 4, 'sc': 20, 'chase': chase}

    async def open_bag(self, client_id):
        return None

    async def use_with(self, a, ac, b, bc):
        self.uses.append((a, b))
        if self.gems and self.item['socketed'] < self.item['sockets']:
            self.item['socketed'] += 1
            self.gems -= 1

    async def wear(self, index, client_id, slot):
        self.wore = (index, slot)
        if self.chase > 0 and not self.err:
            self.worn[slot] = {'s': slot, 'sc': self.piece['sc'], 'set': self.piece.get('set')}
            self.piece = None

    def found(self):
        if self.err:
            return {'err': self.err}
        drops = []
        if self.gems:
            drops.append({'i': 1, 'id': 32006, 'cid': 3400, 'n': self.gems, 'k': 'gem'})
        if self.runes:
            drops.append({'i': 2, 'id': 33001, 'cid': 3500, 'n': self.runes, 'k': 'rune'})
        pieces = [dict(self.piece, unique=True if self.item['unique'] else None)] if self.piece else []
        return {'orbs': dict(self.orbs), 'drops': drops, 'pieces': pieces, 'best': self.piece['i'] if self.piece and self.chase > 0 else None,
                'worn': [dict(w) for w in self.worn.values()], 'sets': dict(self.sets), 'bagClientId': 1988}

    async def helper(self, command, kind, wait=4.0):
        return self.found() if command == 'found' else None

    def state_item(self):
        it = self.item
        return {'rarity': it['rarity'], 'mods': [{'key': m, 'group': m} for m in it['mods']], 'quality': it['quality'], 'qualityCap': it['qcap'],
                'maxMods': it['maxMods'], 'unique': it['unique'], 'sig': 'sig',
                'sockets': {'count': it['sockets'], 'max': it['max'], 'list': [{'id': 32006, 'index': i + 1} for i in range(it['socketed'])] + [{'id': 0, 'index': it['socketed'] + 1 + j} for j in range(it['sockets'] - it['socketed'])]}}

    async def request(self, opname, action, data, expect, timeout):
        self.asked.append((opname, action, data))
        it = self.item
        if opname == 'crafting' and action == 'select':
            return {'action': 'state', 'data': {'counts': dict(self.orbs), 'item': self.state_item()}}
        if opname == 'itemTooltip':
            tip = {'name': 'a piece', 'rarity': it['rarity'], 'mods': [{'k': m} for m in it['mods']], 'q': it['quality'], 'sk': it['socketed'], 'sc': it['sockets']}
            return {'action': 'tips', 'data': {'items': [{'pos': data['items'][0]['pos'], 'tip': tip}]}}
        if opname == 'crafting' and action == 'apply':
            orb = data['orb']
            if self.orbs.get(orb, 0) < 1:
                return {'action': 'result', 'data': {'ok': False, 'text': 'none'}}
            if orb != self.uncounted:
                self.orbs[orb] -= 1
            if orb == 'alchemy':
                it['rarity'], it['mods'] = 3, ['a', 'b']
            elif orb == 'whetstone':
                it['quality'] += 1
            elif orb == 'sockets':
                it['sockets'] = it['max']
            return {'action': 'result', 'data': {'ok': True, 'text': 'done'}}
        if opname == 'supports' and action == 'open':
            return {'action': 'state', 'data': {'spells': [copy.deepcopy(self.support)]}}
        if opname == 'supports' and action == 'socket':
            self.support['runes'].append({'slot': len(self.support['runes']) + 1})
            self.runes -= 1
            return {'action': 'result', 'data': {'ok': True}}
        return None


class CraftFound(unittest.TestCase):
    def go(self, io, fn=None):
        return run((fn or TX.check_craft_found)(io, 'Tester Fnd', 'Ninja', 300))

    def test_the_orb_plan_follows_the_piece(self):
        n = {'alchemy': 1, 'transmutation': 1, 'exalted': 1, 'whetstone': 1, 'sockets': 1}
        base = {'rarity': 0, 'mods': [], 'quality': 0, 'qualityCap': 2, 'maxMods': 4, 'sockets': {'count': 0, 'max': 2}}
        self.assertEqual(TX.found_next_orb(base, n)[0], 'alchemy')
        self.assertEqual(TX.found_next_orb(base, {'transmutation': 1})[0], 'transmutation')
        self.assertEqual(TX.found_next_orb(dict(base, rarity=1, mods=['a']), n)[0], 'exalted', 'room for a modifier on a Common piece')
        self.assertEqual(TX.found_next_orb(dict(base, rarity=3, mods=['a', 'b']), n)[0], 'whetstone', 'a Magic piece gets the Whetstone, not Grafting')
        self.assertEqual(TX.found_next_orb(dict(base, rarity=3, quality=2), n)[0], 'sockets', 'the quality cap is reached')
        self.assertIsNone(TX.found_next_orb(dict(base, rarity=3, quality=2, sockets={'count': 2, 'max': 2}), n))
        self.assertIsNone(TX.found_next_orb(dict(base, unique=True), n), 'a unique gets nothing')
        self.assertIsNone(TX.found_next_orb(dict(base, corrupted=True), n))
        self.assertIsNone(TX.found_next_orb(base, {}), 'an empty hand')

    def test_what_the_bot_dropped_is_spent_and_counted_off(self):
        io = FoundIO(orbs={'alchemy': 1, 'whetstone': 2, 'sockets': 1}, gems=1, runes=1)
        r = self.go(io)
        self.assertEqual(r.status, TX.PASS, r.detail)
        self.assertEqual(io.item['rarity'], 3)
        self.assertEqual(io.item['quality'], 2)
        self.assertEqual(io.item['sockets'], 2)
        self.assertEqual((io.item['socketed'], io.gems, len(io.support['runes'])), (1, 0, 1), 'the gem sits in a socket and the rune in the spell')
        self.assertEqual(io.uses[0], (1, 0), 'the gem (slot 1) is used on the piece (slot 0)')
        self.assertEqual(io.orbs, {'alchemy': 0, 'whetstone': 0, 'sockets': 0})
        self.assertIn('Orb of Gilding', r.detail)
        self.assertIn('gem(s) socketed', r.detail)
        self.assertIn('rune(s) into a spell', r.detail)
        self.assertNotIn('give', [a[1] for a in io.asked], 'no helper grant')

    def test_it_is_a_skip_while_nothing_dropped(self):
        r = self.go(FoundIO())
        self.assertEqual((r.status, 'dropped no orbs' in r.detail), (TX.SKIP, True))
        r = self.go(FoundIO(err='no backpack'))
        self.assertEqual((r.status, r.detail), (TX.SKIP, 'no backpack'))
        r = self.go(FoundIO(orbs={'alchemy': 1}, piece={'unique': True}))
        self.assertEqual(r.status, TX.SKIP, 'a unique takes no orb')

    def test_an_orb_the_window_does_not_count_off_is_a_bug(self):
        r = self.go(FoundIO(orbs={'whetstone': 3}, uncounted='whetstone'))
        self.assertEqual(r.status, TX.FAIL)
        self.assertIn('the bench counts', r.detail)
        self.assertIn('BUG craft_found', r.bug_line())

    def test_the_checks_are_in_the_run(self):
        keys = TX.CheckRun('t', 'Ninja', 100).todo()
        for k in ('craft_found', 'gear_chase', 'chore_faction', 'chore_pass', 'chore_chests', 'chore_candlemarks', 'chore_gamble', 'chore_trade', 'chore_salvage'):
            self.assertIn(k, keys)
            self.assertNotIn(k, TX.CLOSED_KEYS)
        self.assertLess(keys.index('gear_chase'), keys.index('rift_walk'), 'the rift stays the longest, last')


class GearChase(unittest.TestCase):
    def go(self, io):
        return run(TX.check_gear_chase(io, 'Tester Gch', 'Ninja', 300))

    def test_the_best_piece_is_worn(self):
        io = FoundIO()
        r = self.go(io)
        self.assertEqual(r.status, TX.PASS, r.detail)
        self.assertEqual(io.wore, (0, 4))
        self.assertIn('a better piece', r.detail)

    def test_a_set_piece_is_named_and_counted(self):
        io = FoundIO()
        io.piece['set'] = 'ashen_vow'
        io.sets = {'ashen_vow': 1}
        r = self.go(io)
        self.assertEqual(r.status, TX.PASS, r.detail)
        self.assertIn('a set piece (ashen_vow)', r.detail)
        io = FoundIO()
        io.piece['jewelry'] = True
        r = self.go(io)
        self.assertIn('a jewel', r.detail)

    def test_nothing_better_and_the_servers_refusal_are_skips(self):
        r = self.go(FoundIO(chase=0))
        self.assertEqual((r.status, 'beats what the bot wears' in r.detail), (TX.SKIP, True))

        class Refuses(FoundIO):
            async def wear(self, index, client_id, slot):
                self.wore = (index, slot)
        r = self.go(Refuses())
        self.assertEqual((r.status, 'level or class rule' in r.detail), (TX.SKIP, True))

    def test_a_worn_slot_that_is_empty_is_a_bug(self):
        class Vanishes(FoundIO):
            async def wear(self, index, client_id, slot):
                self.wore = (index, slot)
                self.piece = None
                self.worn.pop(slot, None)
        r = self.go(Vanishes())
        self.assertEqual(r.status, TX.FAIL)
        self.assertIn('is empty', r.detail)


class ChoreIO(FakeIO):
    """scripted windows: the replies of (opname, action) are dicts, lists (popped in order, the last one stays) or callables of the data"""

    def __init__(self, replies=None, answers=None):
        FakeIO.__init__(self, answers=dict({'path npc Osric the Chandler': {'here': True}, 'path npc Mordecai Ashwager': {'here': True},
                                            'path npc Material Broker': {'here': True}}, **(answers or {})), replies=replies)

    async def open_bag(self, client_id):
        return None

    async def request(self, opname, action, data, expect, timeout):
        self.asked.append((opname, action, data))
        r = self.replies.get((opname, action))
        if isinstance(r, list):
            return r.pop(0) if len(r) > 1 else r[0]
        return r(data) if callable(r) else r


def st(data):
    return {'action': 'state', 'data': data}


class Chores(unittest.TestCase):
    def go(self, fn, io, level=300):
        return run(fn(io, 'Tester Chr', 'Ninja', level))

    def test_the_faction_window_turns_tokens_into_reputation(self):
        def f(rep, tok):
            return {'k': 'ash', 'rep': rep, 'tok': tok, 'rn': 'Friend', 'wk': 0, 'wc': 50}
        io = ChoreIO({('factions', 'open'): [st({'factions': [f(10, 4)], 'contracts': [{'key': 'c1', 'p': 1, 'n': 5}]}), st({'factions': [f(50, 0)], 'contracts': []})]})
        r = self.go(TX.check_chore_faction, io)
        self.assertEqual(r.status, TX.PASS, r.detail)
        self.assertIn(('factions', 'turnin', {'f': 'ash'}), io.asked)
        self.assertIn('reputation 10 -> 50', r.detail)
        self.assertEqual(io.asked[-1][:2], ('factions', 'close'), 'the window is closed again')
        io = ChoreIO({('factions', 'open'): [st({'factions': [f(10, 4)]}), st({'factions': [f(10, 4)]})]})
        r = self.go(TX.check_chore_faction, io)
        self.assertEqual(r.status, TX.FAIL)
        self.assertIn('were not taken', r.detail)
        io = ChoreIO({('factions', 'open'): [st({'factions': [f(10, 4)]}), st({'factions': [f(10, 0)]})]})
        r = self.go(TX.check_chore_faction, io)
        self.assertEqual((r.status, 'gave no reputation' in r.detail), (TX.FAIL, True))
        self.assertEqual(self.go(TX.check_chore_faction, ChoreIO()).status, TX.SKIP)
        io = ChoreIO({('factions', 'open'): st({'factions': [f(10, 0)], 'contracts': [{'key': 'c1', 'p': 9, 'n': 5}]})})
        r = self.go(TX.check_chore_faction, io)
        self.assertEqual((r.status, 'contract c1 shows 9 of 5' in r.detail), (TX.FAIL, True))
        io = ChoreIO({('factions', 'open'): st({'factions': [f(10, 0)], 'contracts': [{'key': 'c1', 'p': 1, 'n': 5}]})})
        self.assertEqual(self.go(TX.check_chore_faction, io).status, TX.PASS)

    def test_the_season_pass_claims_what_the_tier_holds(self):
        base = {'season': {'id': 3}, 'tier': 3}
        io = ChoreIO({('seasonPass', 'open'): [st(dict(base, claimed=['000', ''])), st(dict(base, claimed=['110', '']))]})
        r = self.go(TX.check_chore_pass, io)
        self.assertEqual(r.status, TX.PASS, r.detail)
        self.assertIn(('seasonPass', 'claimAll', {}), io.asked)
        self.assertIn('claimed 2 free tier(s) of 3', r.detail)
        io = ChoreIO({('seasonPass', 'open'): st(dict(base, claimed=['000', '']))})
        r = self.go(TX.check_chore_pass, io)
        self.assertEqual((r.status, 'left 3 of 3' in r.detail), (TX.FAIL, True))
        io = ChoreIO({('seasonPass', 'open'): st(dict(base, claimed=['111', '']))})
        r = self.go(TX.check_chore_pass, io)
        self.assertEqual(r.status, TX.PASS)
        self.assertNotIn('claimAll', [a[1] for a in io.asked])
        io = ChoreIO({('seasonPass', 'open'): st({'season': None})})
        self.assertEqual(self.go(TX.check_chore_pass, io).status, TX.SKIP)
        self.assertEqual(self.go(TX.check_chore_pass, ChoreIO()).status, TX.SKIP)
        self.assertEqual(TX.pass_claimable({'season': {'id': 1}, 'tier': 5, 'claimed': ['101', '']}), [2], 'a tier beyond the string is not claimable')

    def test_a_tester_has_no_weekly_chest(self):
        io = ChoreIO({('weeklyChest', 'open'): st({'got': 0, 'need': 5, 'chest': {'given': 0}, 'chests': 0}), ('emberCache', 'open'): st({'week': 4})})
        r = self.go(TX.check_chore_chests, io)
        self.assertEqual(r.status, TX.PASS, r.detail)
        self.assertEqual({a[0] for a in io.asked if a[1] == 'close'}, {'weeklyChest', 'emberCache'})
        io = ChoreIO({('weeklyChest', 'open'): st({'got': 2, 'need': 5, 'chest': {'given': 0}}), ('emberCache', 'open'): st({'week': 4})})
        self.assertEqual(self.go(TX.check_chore_chests, io).status, TX.FAIL)
        io = ChoreIO({('weeklyChest', 'open'): st({'got': 0, 'chest': {'given': 1}, 'chests': 1}), ('emberCache', 'open'): st({'week': 4})})
        r = self.go(TX.check_chore_chests, io)
        self.assertEqual((r.status, "the reward pool is the players'" in r.detail), (TX.FAIL, True))
        io = ChoreIO({('weeklyChest', 'open'): st({'got': 0, 'chest': {'given': 0}, 'chests': 0})})
        self.assertEqual(self.go(TX.check_chore_chests, io).status, TX.SKIP)
        self.assertEqual(self.go(TX.check_chore_chests, ChoreIO()).status, TX.SKIP)

    def test_candlemarks_buy_the_cheapest_offer_it_can_pay(self):
        offers = [{'k': 'big', 'p': 90, 'l': 1, 'kind': 'item'}, {'k': 'low', 'p': 20, 'l': 1, 'kind': 'item'}, {'k': 'hi', 'p': 5, 'l': 900, 'kind': 'item'},
                  {'k': 'cos', 'p': 1, 'l': 1, 'kind': 'cosmetic'}, {'k': 'ownd', 'p': 2, 'l': 1, 'kind': 'item', 'own': True}]
        ok = {'action': 'result', 'data': {'ok': True}}
        io = ChoreIO({('candlemarks', 'open'): [st({'balance': 50, 'offers': offers}), st({'balance': 30, 'offers': offers})], ('candlemarks', 'buy'): ok})
        r = self.go(TX.check_chore_candlemarks, io)
        self.assertEqual(r.status, TX.PASS, r.detail)
        self.assertIn(('candlemarks', 'buy', {'k': 'low'}), io.asked, 'the cheapest item offer for its level, not a cosmetic, an owned one or a high level one')
        io = ChoreIO({('candlemarks', 'open'): [st({'balance': 50, 'offers': offers}), st({'balance': 50, 'offers': offers})], ('candlemarks', 'buy'): ok})
        r = self.go(TX.check_chore_candlemarks, io)
        self.assertEqual((r.status, 'the balance fell by 0' in r.detail), (TX.FAIL, True))
        io = ChoreIO({('candlemarks', 'open'): st({'balance': 3, 'offers': offers})})
        r = self.go(TX.check_chore_candlemarks, io)
        self.assertEqual((r.status, 'buys none' in r.detail), (TX.PASS, True))
        self.assertNotIn('buy', [a[1] for a in io.asked])
        io = ChoreIO({('candlemarks', 'open'): st({'balance': 50, 'offers': offers}), ('candlemarks', 'buy'): {'action': 'result', 'data': {'ok': False, 'text': 'walk to Osric'}}})
        r = self.go(TX.check_chore_candlemarks, io)
        self.assertEqual((r.status, 'walk to Osric' in r.detail), (TX.SKIP, True))
        io = ChoreIO(answers={'path npc Osric the Chandler': {'err': 'no way'}, 'enter npc Osric the Chandler': {'err': 'no npc'}})
        r = self.go(TX.check_chore_candlemarks, io)
        self.assertEqual((r.status, 'no way to npc Osric' in r.detail), (TX.SKIP, True))

    def test_the_gambler_sells_a_piece_that_reaches_the_bag(self):
        def stock(sold, money):
            return {'w': 7, 'money': money, 'items': [{'i': 1, 'id': 2400, 'n': 'Sealed Sword', 'sn': 'weapon', 'p': 300, 'sold': sold or None},
                                                      {'i': 2, 'id': 2401, 'n': 'Dear', 'p': 99999}]}
        bags = [{'used': 10}, {'used': 11}]
        io = ChoreIO({('gamble', 'open'): [st(stock(False, 1000)), st(stock(True, 700))]})
        io.answers['bag'] = lambda self: bags.pop(0)
        r = self.go(TX.check_chore_gamble, io)
        self.assertEqual(r.status, TX.PASS, r.detail)
        self.assertIn(('gamble', 'buy', {'i': 1, 'w': 7, 'id': 2400}), io.asked)
        bags[:] = [{'used': 10}, {'used': 10}]
        io = ChoreIO({('gamble', 'open'): [st(stock(False, 1000)), st(stock(True, 700))]})
        io.answers['bag'] = lambda self: bags.pop(0)
        r = self.go(TX.check_chore_gamble, io)
        self.assertEqual((r.status, 'no new item' in r.detail), (TX.FAIL, True))
        io = ChoreIO({('gamble', 'open'): [st(stock(False, 1000)), st(stock(False, 700))]})
        r = self.go(TX.check_chore_gamble, io)
        self.assertEqual((r.status, 'not marked sold' in r.detail), (TX.FAIL, True))
        io = ChoreIO({('gamble', 'open'): [st(stock(False, 1000)), st(stock(True, 1000))]})
        r = self.go(TX.check_chore_gamble, io)
        self.assertEqual((r.status, 'the money fell by 0' in r.detail), (TX.FAIL, True))
        io = ChoreIO({('gamble', 'open'): st(stock(False, 10))})
        r = self.go(TX.check_chore_gamble, io)
        self.assertEqual((r.status, 'for none' in r.detail), (TX.SKIP, True))

    def test_the_broker_buys_what_was_gathered(self):
        def dem(*h):
            return {'demand': [{'id': 1, 'h': n} for n in h]}
        ok = {'action': 'result', 'data': {'ok': True}}
        io = ChoreIO({('professions', 'open'): [st(dem(3, 2)), st(dem(0, 0))], ('professions', 'sellAll'): ok})
        r = self.go(TX.check_chore_trade, io)
        self.assertEqual((r.status, 'sold 5 of 5' in r.detail), (TX.PASS, True))
        io = ChoreIO({('professions', 'open'): [st(dem(3)), st(dem(3))], ('professions', 'sellAll'): ok})
        self.assertEqual(self.go(TX.check_chore_trade, io).status, TX.FAIL)
        io = ChoreIO({('professions', 'open'): st(dem(3)), ('professions', 'sellAll'): {'action': 'result', 'data': {'ok': False, 'text': 'no broker near'}}})
        r = self.go(TX.check_chore_trade, io)
        self.assertEqual((r.status, 'no broker near' in r.detail), (TX.FAIL, True))
        io = ChoreIO({('professions', 'open'): st(dem(0, 0))})
        r = self.go(TX.check_chore_trade, io)
        self.assertEqual((r.status, 'no gathered material' in r.detail), (TX.SKIP, True))
        self.assertNotIn('sellAll', [a[1] for a in io.asked])


class ChoreSalvage(unittest.TestCase):
    def go(self, io):
        return run(TX.check_chore_salvage(io, 'Tester Slv', 'Ninja', 300))

    @staticmethod
    def io(items_after, shards=(4, 9), rep=None, ok=True):
        items = [{'path': '0', 'id': 2400, 'name': 'Old Axe', 'rarity': 2, 'rarityName': 'Uncommon'}, {'path': '1', 'id': 2401, 'name': 'Fine Axe', 'rarity': 3},
                 {'path': '2', 'id': 2402, 'name': 'Grey Axe', 'rarity': 0}]
        rep = rep if rep is not None else {'pieces': [{'i': 0, 'id': 2400, 'chase': -5}, {'i': 1, 'id': 2401, 'chase': 30}, {'i': 2, 'id': 2402, 'chase': -9}],
                                           'bagClientId': 1988}
        first = {'items': items, 'salvage': {'installed': True, 'shards': shards[0]}}
        second = {'items': items[:items_after], 'salvage': {'installed': True, 'shards': shards[1]}}
        return ChoreIO({('crafting', 'open'): [st(first), st(second)], ('crafting', 'select'): st({'item': {'sig': 's1'}}),
                        ('crafting', 'salvage'): {'action': 'result', 'data': {'ok': ok, 'text': 'no'}}},
                       answers={'found': rep})

    def test_a_piece_the_bot_will_not_wear_is_salvaged(self):
        io = self.io(2)
        r = self.go(io)
        self.assertEqual(r.status, TX.PASS, r.detail)
        self.assertIn(('crafting', 'salvage', {'path': '0', 'id': 2400, 'sig': 's1'}), io.asked, 'the first useless rolled piece, with its signature')
        self.assertIn('shards 4 -> 9', r.detail)

    def test_the_pick_leaves_what_the_bot_wants(self):
        items = [{'path': '1', 'id': 2401, 'rarity': 3}, {'path': '0', 'id': 2400, 'rarity': 0}, {'path': '2', 'id': 2402, 'rarity': 2, 'locked': True},
                 {'path': '3', 'id': 2403, 'rarity': 2, 'unique': True}]
        rep = {'pieces': [{'i': 0, 'chase': -1}, {'i': 1, 'chase': 20}, {'i': 2, 'chase': -1}, {'i': 3, 'chase': -1, 'unique': True}]}
        self.assertIsNone(TX.salvage_pick(rep, items), 'a better piece, a normal one, a locked one and a unique are kept')
        items.append({'path': '4', 'id': 2404, 'rarity': 1})
        rep['pieces'].append({'i': 4, 'chase': 0})
        self.assertEqual(TX.salvage_pick(rep, items)['path'], '4')

    def test_the_bugs_and_the_skips(self):
        r = self.go(self.io(3))
        self.assertEqual((r.status, 'expected one less' in r.detail), (TX.FAIL, True))
        r = self.go(self.io(2, shards=(9, 4)))
        self.assertEqual((r.status, 'Rune Shards fell' in r.detail), (TX.FAIL, True))
        r = self.go(self.io(2, ok=False))
        self.assertEqual((r.status, 'the bench refused Old Axe' in r.detail), (TX.SKIP, True))
        r = self.go(self.io(2, rep={'pieces': [{'i': 1, 'id': 2401, 'chase': 30}], 'bagClientId': 1}))
        self.assertEqual((r.status, 'would not wear' in r.detail), (TX.SKIP, True))
        r = self.go(ChoreIO(answers={'found': {'err': 'no backpack'}}))
        self.assertEqual((r.status, r.detail), (TX.SKIP, 'no backpack'))

class BossCopyWorld(LaneWorld):
    """the copy of a boss on one lane: it stands at x = 90 once made; the bot hurts it within 6 tiles; a mark falls on the bot's tile every
    `mark_every` looks while it is in reach: the guide says dodge and the bot has to step off before the next look"""

    def __init__(self, err=None, spawn_err=None, level_ok=True, hits=3, kill=True, mark_every=4, listed=0, pz_first=False, die_after=None, blocked=(), far=True):
        super().__init__(blocked=blocked, die_after=die_after)
        if not far:
            self.pos = (86, 5)
        self.err, self.spawn_err, self.level_ok, self.hits, self.kill = err, spawn_err, level_ok, hits, kill
        self.mark_every, self.listed, self.pz_first = mark_every, listed, pz_first
        self.made, self.hp, self.killed, self.points, self.closes, self.spawns = False, 100, 0, 1, 0, 0
        self.marked_at, self.dodged_x, self.marks_sent, self.looks_in_reach = None, None, 0, 0

    def near(self):
        return abs(self.pos[0] - 90) <= 6

    def facts(self):
        out = {'level': 700, 'pos': self.at(), 'killed': self.killed, 'listed': self.listed, 'points': self.points,
               'next': 'Talath' if self.level_ok else None, 'nextLevel': 650}
        if not self.made:
            out['guide'] = {'mode': 'wait', 'why': 'no boss copy of its own'}
            return out
        out['boss'] = {'pos': {'x': 90, 'y': 5, 'z': 7}, 'name': 'Talath', 'hp': self.hp, 'left': 300}
        if self.marked_at is not None and self.pos[0] == self.marked_at:
            out['danger'] = {'left': 1500, 'labels': ['Frost Lance'], 'count': 1, 'here': True, 'tiles': [[self.marked_at, 5]]}
            side = -3 if self.marked_at >= 90 else 3   # toward the boss: the safe tile stays in reach
            out['guide'] = {'mode': 'dodge', 'goal': {'x': self.marked_at + side, 'y': 5, 'z': 7}, 'why': 'a mark of Frost Lance is on the bot\'s tile'}
        elif self.near():
            out['guide'] = {'mode': 'fight', 'goal': {'x': 90, 'y': 5, 'z': 7}, 'area': 'boss'}
        else:
            out['guide'] = {'mode': 'walk', 'goal': {'x': 90, 'y': 5, 'z': 7}, 'reach': [1, 6], 'area': 'boss'}
        return out

    def answer(self, command):
        if command == 'boss state':
            if self.err:
                return {'err': self.err}
            if self.made and self.look() and self.near():
                self.looks_in_reach += 1
                if self.marked_at is not None and self.pos[0] == self.marked_at:
                    self.marked_at = None   # it stayed: the hit landed (nothing here: the world has no damage)
                self.hp = max(0, self.hp - self.hits)
                if self.hp == 0 and self.kill:
                    self.killed += 1
                    self.made = False
                    self.points += 1
                elif self.mark_every and self.looks_in_reach % self.mark_every == 0:
                    self.marked_at = self.pos[0]
                    self.marks_sent += 1
            return self.facts()
        if command == 'boss spawn':
            if self.pz_first and not self.spawns:
                self.spawns += 1
                return dict(self.facts(), err='the bot stands in a protection zone')
            if self.spawn_err:
                return dict(self.facts(), err=self.spawn_err)
            self.spawns += 1
            self.made, self.hp = True, 100
            return dict(self.facts(), spawned=True)
        if command == 'boss path':
            g = self.facts()['guide']
            return dict(self.facts(), path=self.path_to(g['goal']['x'], g['reach'][1])) if g['mode'] == 'walk' else dict(self.facts(), err='no goal')
        if command == 'boss close':
            self.closes += 1
            self.made = False
            return dict(self.facts(), closed=True)
        return None


class BossCopyWalk(unittest.TestCase):
    def setUp(self):
        self.keep = (TX.BOSS_BUDGET, TX.SOLO_FIGHT_MIN, TX.SOLO_STUCK)

    def tearDown(self):
        TX.BOSS_BUDGET, TX.SOLO_FIGHT_MIN, TX.SOLO_STUCK = self.keep

    def play(self, **kw):
        w = BossCopyWorld(**kw)
        io = LaneIO(w)
        return run(TX.check_boss_copy_walk(io, 'Tester Aaa', 'Warrior', 700)), io

    def test_the_verdicts(self):
        base = {'level': 700, 'steps': 5, 'secs': 30, 'name': 'Talath'}
        self.assertEqual(TX.boss_copy_verdict(dict(base, faults=['x']))[0], TX.FAIL)
        r = TX.boss_copy_verdict(dict(base, killed=1, marks=3, dodged=2, points0=1, points=2))
        self.assertEqual(r[0], TX.PASS)
        self.assertIn('3 warning(s) seen, 2 dodge(s)', r[1])
        self.assertIn('boss passive points 1 -> 2', r[1])
        self.assertEqual(TX.boss_copy_verdict(dict(base, hp=40))[0], TX.PASS)
        self.assertIn('hurt the copy of Talath to 40%', TX.boss_copy_verdict(dict(base, hp=40))[1])
        self.assertEqual(TX.boss_copy_verdict(dict(base, hp=100, fought=TX.SOLO_FIGHT_MIN))[0], TX.FAIL)
        self.assertEqual(TX.boss_copy_verdict(dict(base, stuck=(1, 2)))[0], TX.SKIP)
        self.assertEqual(TX.boss_copy_verdict(dict(base, died=True))[0], TX.SKIP)
        self.assertEqual(TX.boss_copy_verdict(base)[0], TX.SKIP)
        self.assertIn('boss_copy_walk', TX.KEYS)
        self.assertNotIn('boss_copy_walk', TX.CLOSED_KEYS)

    def test_the_copy_is_fought_and_the_marks_are_dodged(self):
        r, io = self.play()
        self.assertEqual(r.status, TX.PASS, r.detail)
        self.assertIn('killed the copy of Talath', r.detail)
        self.assertIn('boss passive points 1 -> 2', r.detail)
        self.assertGreaterEqual(io.w.marks_sent, 1, 'a mark fell on the bot')
        self.assertIn('dodge(s)', r.detail)
        self.assertNotIn(' 0 dodge(s)', r.detail, 'it stepped off the marked tile')
        self.assertEqual(io.cmds[-1], 'boss close')
        self.assertEqual(io.moves[-1], 'hunt')
        self.assertIn('boss path', io.cmds, 'it walked to the copy by the engine path')
        self.assertGreater(io.looted, 0)
        self.assertEqual(io.modes[-1], (['Tester Aaa'], False, False))
        self.assertEqual(io.modes[0], (['Tester Aaa'], True, True), 'the bot may flee like a person at low health')

    def test_a_copy_that_is_hurt_but_not_killed_is_a_pass(self):
        TX.BOSS_BUDGET = 40.0
        r, _ = self.play(hits=1, kill=False)
        self.assertEqual(r.status, TX.PASS, r.detail)
        self.assertIn('hurt the copy', r.detail)

    def test_a_protection_zone_sends_the_bot_to_the_hunt_once(self):
        r, io = self.play(pz_first=True)
        self.assertEqual(r.status, TX.PASS, r.detail)
        self.assertEqual(io.moves[0], 'hunt')
        self.assertEqual(io.w.spawns, 2)

    def test_the_skips(self):
        r, _ = self.play(err='no tester boss system')
        self.assertEqual((r.status, 'no tester boss system' in r.detail), (TX.SKIP, True))
        r, _ = self.play(level_ok=False)
        self.assertEqual((r.status, 'under the lowest boss copy' in r.detail), (TX.SKIP, True))
        r, io = self.play(spawn_err='a player is near: the copy is not made')
        self.assertEqual((r.status, 'a player is near' in r.detail), (TX.SKIP, True))
        self.assertEqual(io.cmds[-1], 'boss close')
        r, _ = self.play(die_after=2, hits=0, kill=False)
        self.assertEqual(r.status, TX.SKIP)
        TX.SOLO_STUCK = 4.0
        r, _ = self.play(hits=0, kill=False, blocked=[(61, 5)])
        self.assertEqual((r.status, 'blocked' in r.detail), (TX.SKIP, True))

    def test_the_bugs(self):
        TX.SOLO_FIGHT_MIN = 6.0
        r, io = self.play(hits=0, kill=False, far=False, mark_every=0)
        self.assertEqual(r.status, TX.FAIL)
        self.assertIn('did not hurt it', r.detail)
        self.assertIn('BUG boss_copy_walk', r.bug_line())
        self.assertGreaterEqual(io.w.closes, 1)
        r, _ = self.play(listed=1)
        self.assertEqual(r.status, TX.FAIL)
        self.assertIn('tester name(s) in a boss board', r.detail)


class PvpWorld:
    """two bots in a PvP place (kind arena | zone | bg): `inside_after` looks to stand inside, the foe's health falls to `hp_floor` from look
    `hp_after`, the match ends (the server puts the bots out) after `end_after` looks; `others` players in the roster, `season` tester rows"""

    def __init__(self, kind='arena', inside_after=1, hp_after=None, hp_floor=60, end_after=None, others=0, season=0, closed=True, queue_members=3):
        self.kind, self.inside_after, self.hp_after, self.hp_floor = kind, inside_after, hp_after, hp_floor
        self.end_after, self.others, self.season, self.closed, self.queue_members = end_after, others, season, closed, queue_members
        self.looks = {'a': 0, 'b': 0}

    def state(self, who):
        self.looks[who] += 1
        n = self.looks[who]
        inside = n >= self.inside_after and not (self.end_after is not None and n > self.end_after)
        hp = self.hp_floor if self.hp_after is not None and n >= self.hp_after else 100
        foes = [{'x': 61, 'y': 5, 'z': 7, 'name': 'Tester Bbb', 'hp': hp}]
        if self.kind == 'zone':
            sec = {'inside': inside, 'testers': 1, 'others': self.others, 'foes': foes if inside else []}
        else:
            sec = {'queued': not inside, 'inMatch': inside, 'phase': 'fight' if inside else None, 'testers': 1, 'others': self.others,
                   'foes': foes if inside else [], 'queueMembers': self.queue_members, 'need': 10}
        out = {'closed': self.closed, 'place': {'arena': 'arena', 'zone': 'pvp zone', 'bg': 'battleground'}[self.kind] if inside else None, 'level': 500,
               'pos': {'x': 60, 'y': 5, 'z': 7}, 'seasonListed': self.season, 'cancelledPlayer': 0, TX.PVP_SECTION[self.kind]: sec}
        if inside:
            out['foe'] = {'x': 61, 'y': 5, 'z': 7, 'name': 'Tester Bbb', 'seen': True, 'dist': 1, 'hp': hp}
            out['guide'] = {'mode': 'fight', 'goal': {'x': 61, 'y': 5, 'z': 7}, 'reach': [1, 5], 'area': 'foe'}
        else:
            out['guide'] = {'mode': 'wait', 'why': 'not in a PvP place'}
        return out


class PvpIO(ClosedIO):
    """ClosedIO with the walking calls and a PvpWorld behind `pvp state` of both bots"""

    def __init__(self, world, replies=None, other_replies=None, **kw):
        super().__init__(answers={'pvp state': lambda io: world.state('a'), 'pvp path': lambda io: {'path': []}},
                         other_answers={'pvp state': lambda io: world.state('b'), 'pvp path': lambda io: {'path': []}},
                         replies=replies, other_replies=other_replies, **kw)
        self.w, self.modes, self.looted = world, [], 0

    def raid_mode(self, names, on, keep_flee=False):
        self.modes.append((list(names), on, keep_flee))

    async def step(self, dx, dy):
        pass

    async def step_of(self, other, dx, dy):
        pass

    async def loot(self):
        self.looted += 1


class PvpFights(unittest.TestCase):
    def setUp(self):
        self.keep = (TX.PVP_FIGHT_MIN, TX.ARENA_WAIT, TX.BG_QUEUE_WAIT, TX.PVP_BUDGET.copy())

    def tearDown(self):
        TX.PVP_FIGHT_MIN, TX.ARENA_WAIT, TX.BG_QUEUE_WAIT = self.keep[:3]
        TX.PVP_BUDGET.clear()
        TX.PVP_BUDGET.update(self.keep[3])

    def arena(self, world, **kw):
        q = {('arena', 'queue'): {'action': 'state'}, ('arena', 'leave'): {'action': 'state'}}
        io = PvpIO(world, replies=dict(q), other_replies=dict(q), **kw)
        return run(TX.check_closed_arena_fight(io, 'Tester Aaa', 'Warrior', 500)), io

    def zone(self, world, **kw):
        q = {('pvpZone', 'enter'): {'action': 'enter', 'data': {}}}
        io = PvpIO(world, replies=dict(q), other_replies=dict(q), **kw)
        return run(TX.check_closed_pvp_fight(io, 'Tester Aaa', 'Warrior', 500)), io

    def bg(self, world):
        q = {('battleground', 'queue'): {'action': 'state'}, ('battleground', 'leave'): {'action': 'state'}}
        io = PvpIO(world, replies=dict(q), other_replies=dict(q))
        return run(TX.check_closed_battleground_match(io, 'Tester Aaa', 'Warrior', 500)), io

    def test_the_keys_and_the_order(self):
        for k in ('closed_arena_fight', 'closed_pvp_fight', 'closed_battleground_match'):
            self.assertIn(k, TX.CLOSED_KEYS)
            self.assertNotIn(k, TX.KEYS)
            self.assertLess(TX.CLOSED_KEYS.index(k), TX.CLOSED_KEYS.index('closed_raid'), 'the raid is the longest: last')

    def test_the_verdicts(self):
        base = {'level': 500, 'steps': 4, 'secs': 60, 'was_in': True}
        self.assertEqual(TX.pvp_fight_verdict(dict(base, faults=['x']), 'arena match')[0], TX.FAIL)
        r = TX.pvp_fight_verdict(dict(base, ended=True, foe_hp=40), 'arena match')
        self.assertEqual(r[0], TX.PASS)
        self.assertIn('played to its end between testers only', r[1])
        self.assertEqual(TX.pvp_fight_verdict(dict(base, foe_hp=70), 'Marches')[0], TX.PASS)
        self.assertEqual(TX.pvp_fight_verdict(dict(base, foe_hp=100, fought=TX.PVP_FIGHT_MIN), 'Marches')[0], TX.FAIL)
        self.assertEqual(TX.pvp_fight_verdict({'level': 1}, 'Marches')[0], TX.SKIP)
        self.assertEqual(TX.pvp_fight_verdict(dict(base, stuck=(1, 2)), 'Marches')[0], TX.SKIP)
        self.assertEqual(TX.pvp_fight_verdict(dict(base, died=True), 'Marches')[0], TX.SKIP)
        self.assertIn('hit(s) on a player were cancelled', TX.pvp_fight_verdict(dict(base, foe_hp=50, cancelled_player=2), 'Marches')[1])

    def test_the_problems(self):
        arena = lambda **kw: dict({'closed': True, 'arena': {'inMatch': True, 'others': 0}}, **kw)  # noqa: E731
        self.assertEqual(TX.pvp_problems(arena(), 'arena'), [])
        self.assertIn('1 player(s) are in the testers\' arena', TX.pvp_problems(arena(arena={'inMatch': True, 'others': 1}), 'arena')[0])
        self.assertIn('tester row(s) in the season ratings', TX.pvp_problems(arena(seasonListed=2), 'arena')[0])
        self.assertIn('closed switch off', TX.pvp_problems(arena(place='arena', closed=False), 'arena')[0])
        self.assertEqual(TX.pvp_problems({'zone': {'inside': False, 'others': 5}}, 'zone'), [], 'outside the place nobody is judged')
        self.assertEqual(TX.pvp_hurt({'arena': {'foes': [{'hp': 80}, {'hp': 55}]}}, 'arena'), 55)
        self.assertEqual(TX.pvp_hurt({'foe': {'hp': 30}}, 'zone'), 30)
        self.assertIsNone(TX.pvp_hurt({}, 'zone'))

    def test_an_arena_match_played_to_its_end(self):
        r, io = self.arena(PvpWorld('arena', hp_after=3, end_after=12))
        self.assertEqual(r.status, TX.PASS, r.detail)
        self.assertIn('played to its end between testers only', r.detail)
        self.assertEqual(io.asked[-1], ('arena', 'leave', {}))
        self.assertEqual(io.other_asked[-1], ('arena', 'leave', {}))
        self.assertEqual(io.modes[0], (['Tester Aaa', 'Tester Bbb'], True, False))
        self.assertEqual(io.modes[-1], (['Tester Aaa', 'Tester Bbb'], False, False))

    def test_an_arena_match_still_running_with_a_foe_hurt_is_a_pass(self):
        r, _ = self.arena(PvpWorld('arena', hp_after=2))
        self.assertEqual(r.status, TX.PASS, r.detail)
        self.assertIn('a foe tester hurt to 60%', r.detail)

    def test_the_arena_bugs(self):
        r, _ = self.arena(PvpWorld('arena', hp_after=2, others=1))
        self.assertEqual(r.status, TX.FAIL)
        self.assertIn('player(s) are in the testers\' arena', r.detail)
        self.assertIn('BUG closed_arena_fight', r.bug_line())
        r, _ = self.arena(PvpWorld('arena', hp_after=2, season=1))
        self.assertEqual(r.status, TX.FAIL)
        self.assertIn('season ratings', r.detail)
        TX.PVP_FIGHT_MIN = 5.0
        r, _ = self.arena(PvpWorld('arena'))
        self.assertEqual(r.status, TX.FAIL)
        self.assertIn('hurt none', r.detail)

    def test_the_arena_skips(self):
        r, _ = self.arena(PvpWorld('arena'), partner=None)
        self.assertEqual((r.status, 'no free bot' in r.detail), (TX.SKIP, True))
        io = PvpIO(PvpWorld('arena'))
        self.assertEqual(run(TX.check_closed_arena_fight(io, 'Tester Aaa', 'Warrior', 500)).status, TX.SKIP, 'no answer from the window')
        TX.ARENA_WAIT = 4.0
        r, io = self.arena(PvpWorld('arena', inside_after=999))
        self.assertEqual((r.status, 'not in a match' in r.detail), (TX.SKIP, True))
        self.assertEqual(io.asked[-1], ('arena', 'leave', {}), 'the queue is left')

    def test_the_marches(self):
        r, io = self.zone(PvpWorld('zone', hp_after=3))
        self.assertEqual(r.status, TX.PASS, r.detail)
        self.assertIn('hurt to 60% in the Marches', r.detail)
        self.assertEqual(io.moves[-1], 'town')
        r, _ = self.zone(PvpWorld('zone', hp_after=3, others=2))
        self.assertEqual((r.status, 'testers\' zone' in r.detail), (TX.FAIL, True))
        r, _ = self.zone(PvpWorld('zone', inside_after=999))
        self.assertEqual((r.status, 'not inside the Marches' in r.detail), (TX.SKIP, True))
        io = PvpIO(PvpWorld('zone'))
        self.assertEqual(run(TX.check_closed_pvp_fight(io, 'Tester Aaa', 'Warrior', 500)).status, TX.SKIP, 'no answer from the window')

    def test_the_battleground(self):
        r, io = self.bg(PvpWorld('bg', inside_after=4, hp_after=8))
        self.assertEqual(r.status, TX.PASS, r.detail)
        self.assertIn('hurt to 60% in the battleground match', r.detail)
        self.assertEqual(io.asked[-1], ('battleground', 'leave', {}))
        TX.BG_QUEUE_WAIT = 10.0
        r, _ = self.bg(PvpWorld('bg', inside_after=999, queue_members=4))
        self.assertEqual(r.status, TX.SKIP)
        self.assertIn('4 of the 10 testers a match needs were queued', r.detail)
        TX.BG_QUEUE_WAIT = 150.0
        r, _ = self.bg(PvpWorld('bg', inside_after=4, hp_after=8, others=1))
        self.assertEqual(r.status, TX.FAIL)
        self.assertIn('BUG closed_battleground_match', r.bug_line())
        io = PvpIO(PvpWorld('bg'))
        self.assertEqual(run(TX.check_closed_battleground_match(io, 'Tester Aaa', 'Warrior', 500)).status, TX.SKIP, 'no answer from the window')



# ------------------------------------------------------------------------------------------------ O651: pocket bosses
class PocketWorld(RiftWorld):
    """a pocket boss on the rift lane (y = 5): the temple at x 92, the pocket's boss at x 50. `pocket state | path | close`, the Boss Spawns window's `open` and
    `pocketEnter`; the boss comes after two looks, dies of the bot's hits, the first kill raises the points and entering spends a charge"""

    def __init__(self, enter_error=None, no_point=False, no_charge=False, never_kill=False, mixed=False, free=16, left=3, enabled=True, err=None,
                 has_point=True, level=900, **kw):
        super().__init__(level=level, **kw)
        self.enter_error, self.no_point, self.no_charge, self.mixed, self.free, self.left = enter_error, no_point, no_charge, mixed, free, left
        self.enabled, self.err_p, self.has_point, self.never_kill_p = enabled, err, has_point, never_kill
        self.inside_p, self.looks, self.boss, self.state, self.points, self.closed_p, self.entered = False, 0, 'waiting', 'running', 2, 0, []
        self.bhp = 100

    def row(self):
        r = {'key': 'world_1', 'name': 'Kaelgor', 'category': 'world', 'level': 300, 'left': self.left}
        if self.has_point:
            r['point'] = {'id': 1, 'got': self.points >= 3}
        return r

    def pguide(self):
        if self.state != 'running':
            return {'mode': 'wait', 'why': 'the pocket is over'}
        if self.boss != 'alive':
            return {'mode': 'wait', 'why': 'the boss comes in a moment'}
        return {'mode': 'fight' if abs(self.pos[0] - 50) <= 5 else 'walk', 'goal': {'x': 50, 'y': 5, 'z': 7}, 'reach': [1, 5], 'area': 'boss', 'why': 'test'}

    def pfacts(self):
        out = {'inside': self.inside_p, 'level': self.level, 'pos': {'x': self.pos[0], 'y': self.pos[1], 'z': 7}, 'pz': self.pz(), 'enabled': self.enabled,
               'free': self.free, 'reserve': 4, 'points': {'got': self.points, 'total': 10}}
        if self.inside_p:
            out['run'] = {'key': 'world_1', 'name': 'Kaelgor', 'state': self.state, 'boss': self.boss, 'left': 600, 'players': 1 + (1 if self.mixed else 0), 'testers': 1,
                          'bossHp': self.bhp if self.boss == 'alive' else None, 'inArena': True}
            out['guide'] = self.pguide()
        else:
            out['bosses'] = [self.row()] if self.left > 0 else []
        return out

    def ptick(self):
        if not self.inside_p:
            return
        self.looks += 1
        if self.boss == 'waiting' and self.looks >= 2:
            self.boss = 'alive'
        g = self.pguide()
        if g['mode'] == 'fight' and not self.never_kill_p:
            self.bhp = max(0, self.bhp - 50)
            if self.bhp == 0:
                self.boss, self.state = 'dead', 'success'
                if not self.no_point:
                    self.points += 1

    def answer(self, command):
        if command == 'pocket state':
            if self.err_p:
                return {'err': self.err_p}
            self.ptick()
            return self.pfacts()
        if command == 'pocket path':
            g = self.pguide()
            if not self.inside_p or g['mode'] != 'walk':
                return dict(self.pfacts(), err='no goal' if self.inside_p else 'not inside a pocket')
            return dict(self.pfacts(), path=self.path_to(50, 5), dist=abs(self.pos[0] - 50))
        if command == 'pocket close':
            was = self.inside_p
            self.inside_p = False
            self.closed_p += 1
            return dict(self.pfacts(), closed=was)
        return super().answer(command)

    def request(self, opname, action, data):
        if opname != 'bossSpawns':
            return None
        if action == 'open':
            return {'action': 'list', 'data': {}}
        if action == 'pocketEnter':
            self.entered.append(data.get('k'))
            if self.enter_error:
                return {'action': 'pocketError', 'data': {'text': self.enter_error}}
            if not self.pz():
                return {'action': 'pocketError', 'data': {'text': 'You can only open a pocket in a protection zone.'}}
            self.inside_p = True
            self.pos = (50 - 12, 5)
            if not self.no_charge:
                self.left -= 1
            return {'action': 'pocket', 'data': {}}
        return None


class PocketIO(RiftIO):
    def __init__(self, world, **kw):
        super().__init__(world, **kw)
        self.asked = []

    async def request(self, opname, action, data, expect, timeout):
        self.asked.append((opname, action, data))
        return self.w.request(opname, action, data)


class PocketWalk(unittest.TestCase):
    def setUp(self):
        self.keep = (TX.POCKET_BUDGET, TX.SOLO_FIGHT_MIN, TX.SOLO_ENTER_WAIT)

    def tearDown(self):
        TX.POCKET_BUDGET, TX.SOLO_FIGHT_MIN, TX.SOLO_ENTER_WAIT = self.keep

    def play(self, world, level=900):
        io = PocketIO(world)
        return run(TX.check_pocket_walk(io, 'Tester Aaa', 'Warrior', level)), io

    def test_the_pure_parts(self):
        a = {'level': 900, 'enabled': True, 'free': 16, 'reserve': 4, 'bosses': [{'key': 'world_1', 'name': 'K', 'left': 3, 'point': {'id': 1, 'got': False}},
                                                                                 {'key': 'raid_a', 'name': 'R', 'left': 1}]}
        self.assertIsNone(TX.pocket_refusal(a))
        self.assertEqual(TX.pocket_pick(a)['key'], 'world_1', 'the first row: the helper ordered them')
        self.assertIsNone(TX.pocket_pick({'bosses': []}))
        for bad, word in ((None, 'old helper'), ({'err': 'no pocket boss system'}, 'no pocket boss'), (dict(a, enabled=False), 'closed'),
                          (dict(a, inside=True), 'inside'), (dict(a, free=4), 'kept for the players'), (dict(a, bosses=[]), 'no pocket with a charge')):
            r = TX.pocket_refusal(bad)
            self.assertEqual(r[0], TX.SKIP)
            self.assertIn(word, r[1])
        self.assertIsNone(TX.pocket_refusal(dict(a, free=5)), 'free 5 less one is the reserve: allowed')
        trace = {'faults': []}
        self.assertEqual(TX.pocket_problems({'run': {'players': 1, 'testers': 1, 'boss': 'alive', 'bossHp': 60}}, trace), [])
        self.assertEqual((trace['boss_seen'], trace['hp']), (True, 60))
        self.assertTrue(TX.pocket_problems({'run': {'players': 2, 'testers': 1}}, trace))
        TX.pocket_problems({'run': {'state': 'success', 'boss': 'dead'}}, trace)
        self.assertEqual((trace['won'], trace['hp']), (True, 0))
        self.assertEqual(TX.pocket_error_text({'action': 'pocketError', 'data': {'text': 'No.'}}), 'No.')
        self.assertIsNone(TX.pocket_error_text({'action': 'pocket', 'data': {}}))
        self.assertIsNone(TX.pocket_error_text(None))
        base = {'secs': 90, 'steps': 12, 'came': 'foot', 'boss': 'Kaelgor', 'level': 900}
        self.assertEqual(TX.pocket_walk_verdict(dict(base, faults=['x']))[0], TX.FAIL)
        v = TX.pocket_walk_verdict(dict(base, won=True, point={'id': 1, 'got': False}, point_gain=1))
        self.assertEqual(v[0], TX.PASS)
        self.assertIn('boss point came', v[1])
        self.assertIn('held already', TX.pocket_walk_verdict(dict(base, won=True, point={'id': 1, 'got': True}))[1])
        self.assertEqual(TX.pocket_walk_verdict(dict(base, boss_seen=True, hp=40))[0], TX.SKIP)
        self.assertEqual(TX.pocket_walk_verdict(dict(base, boss_seen=True, hp=100, fought=TX.SOLO_FIGHT_MIN))[0], TX.FAIL)
        self.assertEqual(TX.pocket_walk_verdict(dict(base, stuck=(1, 2)))[0], TX.SKIP)
        self.assertEqual(TX.pocket_walk_verdict(dict(base, died=True))[0], TX.SKIP)
        self.assertEqual(TX.pocket_walk_verdict(base)[0], TX.SKIP)
        self.assertIn('pocket_walk', TX.KEYS)
        self.assertNotIn('pocket_walk', TX.CLOSED_KEYS)
        self.assertLess(TX.KEYS.index('pocket_walk'), TX.KEYS.index('rift_walk'))

    def test_a_pocket_played_is_a_pass_with_the_point(self):
        r, io = self.play(PocketWorld())
        self.assertEqual(r.status, TX.PASS, r.detail)
        self.assertIn('Kaelgor fell', r.detail)
        self.assertIn('boss point came (+1)', r.detail)
        self.assertEqual(r.fallbacks, [])
        self.assertEqual(io.w.teleports, 0, 'the bot walked to the temple')
        ops = [(o, a) for o, a, _ in io.asked]
        self.assertEqual(ops, [('bossSpawns', 'open'), ('bossSpawns', 'pocketEnter')], 'the window opened, then the pocket asked for')
        self.assertEqual(io.w.entered, ['world_1'])
        self.assertEqual(io.w.closed_p >= 1, True)
        self.assertFalse(io.w.inside_p)
        self.assertEqual(io.moves[-1], 'hunt')
        self.assertEqual(io.modes[-1], (['Tester Aaa'], False, False))
        self.assertGreater(io.looted, 0, 'the corpse of the boss is looted')
        cmds = io.cmds
        self.assertLess(cmds.index('path temple'), cmds.index('pocket close'))

    def test_a_boss_with_no_point_is_a_pass_without_the_check(self):
        r, _ = self.play(PocketWorld(has_point=False))
        self.assertEqual(r.status, TX.PASS, r.detail)
        self.assertNotIn('boss point', r.detail)

    def test_skips(self):
        for world, word in ((PocketWorld(err='no pocket boss system'), 'no pocket boss'), (PocketWorld(enabled=False), 'closed'), (PocketWorld(free=4), 'kept for the players'),
                            (PocketWorld(left=0), 'no pocket with a charge'),
                            (PocketWorld(enter_error='The testers wait: the halls are kept for the players.'), 'testers wait')):
            r, io = self.play(world)
            self.assertEqual(r.status, TX.SKIP, r.detail)
            self.assertIn(word, r.detail)
            self.assertFalse(io.w.inside_p)
        TX.SOLO_ENTER_WAIT = 3.0
        r, _ = self.play(PocketWorld(enter_error='You need level 300.'))
        self.assertEqual(r.status, TX.SKIP)
        self.assertIn('did not open', r.detail)

    def test_bugs(self):
        r, io = self.play(PocketWorld(no_point=True))
        self.assertEqual(r.status, TX.FAIL)
        self.assertIn('gave no boss passive point', r.detail)
        r, _ = self.play(PocketWorld(no_charge=True))
        self.assertEqual(r.status, TX.FAIL)
        self.assertIn('a charge is spent when it opens', r.detail)
        r, _ = self.play(PocketWorld(mixed=True))
        self.assertEqual(r.status, TX.FAIL)
        self.assertIn('a player is in the pocket of the testers', r.detail)
        r, _ = self.play(PocketWorld(enter_error='Testers and players are never mixed.'))
        self.assertEqual(r.status, TX.FAIL)
        self.assertIn('refused a lone tester', r.detail)
        TX.SOLO_FIGHT_MIN = 8.0
        r, io = self.play(PocketWorld(never_kill=True))
        self.assertEqual(r.status, TX.FAIL)
        self.assertIn('took none of its health', r.detail)
        self.assertFalse(io.w.inside_p, 'the pocket is left')

    def test_the_budget_ends_the_fight(self):
        TX.POCKET_BUDGET = 6.0
        r, io = self.play(PocketWorld(never_kill=True))
        self.assertEqual(r.status, TX.SKIP, r.detail)
        self.assertFalse(io.w.inside_p)
        self.assertEqual(io.moves[-1], 'hunt')


# ------------------------------------------------------------------------------------------------ O651: the rift stairs
class StairsWorld(RiftWorld):
    """a rift of two floors on one lane: the hole at x 40 on floor 7 drops to the ladder at x 40 on floor 8, the ladder is used to climb. `mons` is
    [(x, floor)], the guardian stands at x 50 on `boss_z`; the guardian comes when the pack is dead"""
    HOLE = 40

    def __init__(self, mons=((10, 7), (20, 7), (70, 8)), boss_z=8, stuck_hole=False, **kw):
        super().__init__(**kw)
        self.z, self.mons, self.boss_z, self.stuck_hole = 7, [list(m) for m in mons], boss_z, stuck_hole
        self.dead, self.uses, self.falls = set(), 0, 0

    def alive_i(self):
        return [i for i in range(len(self.mons)) if i not in self.dead]

    def boss_up(self):
        return not self.alive_i() and self.boss_hp > 0

    def stairs(self, tz):
        goal = {'x': self.HOLE, 'y': 5, 'z': self.z}
        if tz > self.z:
            return {'mode': 'walk', 'goal': goal, 'reach': [0, 1], 'area': 'stairs', 'via': 'hole', 'why': 'to the hole'}
        if abs(self.pos[0] - self.HOLE) <= 1:
            return {'mode': 'use', 'goal': goal, 'area': 'stairs', 'via': 'ladder', 'why': 'up the ladder',
                    'use': {'x': self.HOLE, 'y': 5, 'z': self.z, 'clientId': 1386, 'stack': 1}}
        return {'mode': 'walk', 'goal': goal, 'reach': [0, 1], 'area': 'stairs', 'via': 'ladder', 'why': 'to the ladder'}

    def guide(self):
        if not self.inside:
            return None
        here = [i for i in self.alive_i() if self.mons[i][1] == self.z]
        if self.boss_up():
            if self.boss_z != self.z:
                return self.stairs(self.boss_z)
            return {'mode': 'fight' if abs(self.pos[0] - 50) <= 4 else 'walk', 'goal': {'x': 50, 'y': 5, 'z': self.z}, 'reach': [1, 4], 'area': 'boss', 'why': 't'}
        if here:
            i = min(here, key=lambda j: abs(self.mons[j][0] - self.pos[0]))
            x = self.mons[i][0]
            return {'mode': 'fight' if abs(self.pos[0] - x) <= 4 else 'walk', 'goal': {'x': x, 'y': 5, 'z': self.z}, 'reach': [1, 4], 'area': 'pack', 'why': 't', 'idx': i}
        left = self.alive_i()
        if left:
            return self.stairs(self.mons[left[0]][1])
        return {'mode': 'wait', 'why': 'nothing to do'}

    def facts(self):
        out = {'inside': self.inside, 'level': self.level, 'pos': {'x': self.pos[0], 'y': self.pos[1], 'z': self.z}, 'pz': self.pz(), 'held': self.key,
               'tier': self.tier}
        if self.inside:
            out['run'] = {'id': 1, 'tier': self.tier, 'theme': 'ash', 'kind': 'rooms', 'state': 'running', 'boss': 'alive' if self.boss_up() else 'waiting',
                          'killed': len(self.dead), 'total': len(self.mons), 'bossAt': len(self.mons), 'floors': 2, 'links': 1, 'monsters': len(self.alive_i()),
                          'bossHp': self.boss_hp if self.boss_up() else None}
            g = self.guide()
            out['guide'] = {k: v for k, v in g.items() if k != 'idx'}
        return out

    def tick(self):
        if not self.inside or self.never_kill:
            return
        g = self.guide()
        if not g or g['mode'] != 'fight':
            return
        if g['area'] == 'boss':
            self.boss_hp = max(0, self.boss_hp - 100 // self.kill_after)
        else:
            self.dead.add(g['idx'])

    def step(self, dx, dy):
        super().step(dx, dy)
        if self.inside and self.z == 7 and self.pos[0] == self.HOLE and not self.stuck_hole:
            self.z = 8   # the hole: down to the ladder under it
            self.falls += 1

    def use_at(self, pos, client_id, stack):
        self.uses += 1
        if self.z == 8 and pos[0] == self.HOLE and abs(self.pos[0] - self.HOLE) <= 1 and client_id == 1386:
            self.z = 7
            self.pos = (self.HOLE, 5)

    def answer(self, command):
        if command == 'rift path':
            g = self.guide()
            if not self.inside or not g or g['mode'] != 'walk':
                return dict(self.facts(), err='no goal' if self.inside else 'not inside a rift')
            return dict(self.facts(), path=self.path_to(g['goal']['x'], g['reach'][1]), dist=abs(self.pos[0] - g['goal']['x']))
        return super().answer(command)


class StairsIO(RiftIO):
    async def use_at(self, pos, client_id, stack=1):
        self.w.use_at(pos, client_id, stack)
        return True


class RiftStairs(unittest.TestCase):
    def setUp(self):
        self.keep = (TX.RIFT_BUDGET, TX.RIFT_BUDGET_TWO, TX.RIFT_STAIR_LOOKS)

    def tearDown(self):
        TX.RIFT_BUDGET, TX.RIFT_BUDGET_TWO, TX.RIFT_STAIR_LOOKS = self.keep

    def play(self, world, level=900):
        io = StairsIO(world)
        return run(TX.check_rift_walk(io, 'Tester Aaa', 'Warrior', level)), io

    def test_down_the_hole_to_the_guardian(self):
        r, io = self.play(StairsWorld())
        self.assertEqual(r.status, TX.PASS, r.detail)
        self.assertEqual(io.w.falls, 1, 'the bot stepped onto the hole once')
        self.assertEqual(io.w.uses, 0, 'no ladder was needed')
        self.assertEqual(io.w.z, 8)
        self.assertIn('2 floors, 1 floor change(s) (1 down, 0 up, 0 ladder use(s))', r.detail)
        self.assertIn('the guardian at', r.detail)
        self.assertEqual(io.w.closed, 1)

    def test_up_the_ladder_again(self):
        r, io = self.play(StairsWorld(mons=((10, 8), (20, 8), (30, 8)), boss_z=7))
        self.assertEqual(r.status, TX.PASS, r.detail)
        self.assertEqual((io.w.falls, io.w.z), (1, 7))
        self.assertGreaterEqual(io.w.uses, 1, 'the ladder was used')
        self.assertIn('1 down, 1 up', r.detail)
        self.assertIn('1 ladder use(s)', r.detail)

    def test_a_hole_that_does_not_take_the_bot_is_a_bug(self):
        r, _ = self.play(StairsWorld(stuck_hole=True))
        self.assertEqual(r.status, TX.FAIL, r.detail)
        self.assertIn('stood next to the hole', r.detail)
        self.assertIn('did not change', r.detail)

    def test_killing_on_the_first_floor_only_is_no_walk_of_the_stairs(self):
        base = {'tier': 3, 'theme': 'ash', 'came': 'foot', 'steps': 20, 'secs': 60, 'kills': 2, 'floors': 2, 'links': 1}
        self.assertEqual(TX.rift_walk_verdict(base)[0], TX.SKIP)
        self.assertIn('stairs were not walked', TX.rift_walk_verdict(base)[1])
        self.assertEqual(TX.rift_walk_verdict(dict(base, stairs=1, down=1))[0], TX.PASS)
        self.assertEqual(TX.rift_walk_verdict(dict(base, floors=1, links=0))[0], TX.PASS, 'a rift of one floor needs no stairs')
        self.assertEqual(TX.rift_walk_verdict(dict(base, kills=0, floor=True))[0], TX.SKIP)


# ------------------------------------------------------------------------------------------------ O651: dungeon difficulties and the Weekly Challenge
class DifficultyWorld(DungeonWorld):
    """the dungeon lane of DungeonWorld with the Weekly Challenge (dungeon 7, level 800, one fixed difficulty) in the list, the unlock of the helper and
    the run's difficulty (the queue's request, the fixed one for the weekly dungeon)"""

    def __init__(self, unlock_ok=True, weekly=True, current=True, listed=(0, 0), run_diff=None, scaled=True, level=900, **kw):
        super().__init__(level=level, dungeons=(4,), **kw)
        self.unlock_ok, self.weekly_on, self.current, self.listed, self.run_diff, self.scaled_on = unlock_ok, weekly, current, list(listed), run_diff, scaled
        self.asked, self.unlocked, self.weekly_calls = {}, [], 0

    def listing(self):
        rows = [dict(r) for r in super().listing()]
        if self.weekly_on:
            rows.append({'id': 7, 'title': 'Weekly Challenge', 'level': 800, 'size': 1, 'max': 1, 'fixed': 1, 'weekly': True})
        return rows

    def facts(self, name):
        out = super().facts(name)
        if 'run' in out:
            diff = 1 if self.run['id'] == 7 else self.asked.get(name, 1)
            out['run']['difficulty'] = self.run_diff if self.run_diff is not None else diff
            out['run']['scaled'] = out['run']['left'] if self.scaled_on else 0
        return out

    def answer(self, name, command):
        if command.startswith('dungeon unlock '):
            _, _, did, diff = command.split()
            if not self.unlock_ok:
                return {'err': 'not a tester'}
            self.unlocked.append((int(did), int(diff)))
            return {'unlocked': int(diff)}
        if command == 'dungeon weekly':
            n = self.weekly_calls
            self.weekly_calls += 1
            return {'weekly': {'enabled': True, 'built': '2026-W46', 'theme': 'Marrow Crypts', 'current': self.current, 'testersListed': self.listed[min(n, 1)]}}
        return super().answer(name, command)

    def request(self, name, opname, action, data=None):
        if opname == 'dungeons' and action == 'queue' and not self.unit(name)['queued']:
            self.asked[name] = data['difficulty']
        return super().request(name, opname, action, data)


class DungeonDifficulty(unittest.TestCase):
    def setUp(self):
        TX.reset_dungeon_turn()

    def tearDown(self):
        TX.reset_dungeon_turn()

    def play(self, world, fn=None, name='Tester Aaa', level=900):
        io = DungeonIO(world, me=name)
        return run((fn or TX.check_dungeon_difficulty)(io, name, 'Warrior', level)), io

    def test_the_pick(self):
        a = {'level': 900, 'maxDifficulty': 6, 'list': [{'id': 4, 'level': 600, 'size': 1}, {'id': 1, 'level': 150, 'size': 2}, {'id': 7, 'level': 800, 'size': 1, 'fixed': 1, 'weekly': True}]}
        dg, d, why = TX.dungeon_difficulty_pick(a)
        self.assertEqual((dg['id'], d, why), (1, 6, None), 'level 900 carries difficulty 6 of the level 150 dungeon (x3.0 = 450)')
        dg, d, why = TX.dungeon_difficulty_pick(dict(a, level=700))
        self.assertEqual((dg['id'], d), (1, 6))
        dg, d, why = TX.dungeon_difficulty_pick(dict(a, level=300))
        self.assertEqual((dg['id'], d), (1, 4), 'a bot of level 300: difficulty 4 of the level 150 dungeon (x1.7 = 255)')
        dg, d, why = TX.dungeon_difficulty_pick(dict(a, level=160))
        self.assertEqual((dg['id'], d), (1, 2), 'a bot of level 160: difficulty 2 (x1.0)')
        dg, d, why = TX.dungeon_difficulty_pick(dict(a, level=100))
        self.assertIsNone(dg)
        self.assertIn('no free dungeon carries difficulty 2', why)
        TX.DUNGEON_DIFF_DONE.update({6: 'Tester Bbb', 5: 'Tester Ccc'})
        dg, d, why = TX.dungeon_difficulty_pick(a)
        self.assertEqual(d, 4, 'a difficulty another bot played is left to the next bot')
        TX.DUNGEON_BUSY[1] = 'Tester Ddd'
        dg, d, why = TX.dungeon_difficulty_pick(a)
        self.assertEqual((dg['id'], d), (4, 3), 'a dungeon a bot is in is skipped (level 900 carries 3 of the level 600 dungeon)')
        TX.DUNGEON_DIFF_DONE.update({d: 'x' for d in (2, 3, 4)})
        dg, d, why = TX.dungeon_difficulty_pick(a)
        self.assertIsNone(dg)
        self.assertIn('every difficulty', why)
        self.assertIn('check_dungeon_difficulty', dir(TX))
        self.assertIn('dungeon_difficulty', TX.CLOSED_KEYS)
        self.assertIn('weekly_challenge', TX.CLOSED_KEYS)
        self.assertLess(TX.CLOSED_KEYS.index('closed_dungeon'), TX.CLOSED_KEYS.index('dungeon_difficulty'))
        self.assertEqual(TX.CLOSED_KEYS[-1], 'closed_raid')
        self.assertNotIn('dungeon_difficulty', TX.KEYS)
        # the plain dungeon check leaves the Weekly Challenge to its own check
        picked = TX.dungeon_pick({'level': 900, 'list': [{'id': 7, 'level': 800, 'size': 1, 'weekly': True}, {'id': 4, 'level': 600, 'size': 1}]})[0]
        self.assertEqual(picked['id'], 4)
        self.assertEqual(TX.difficulty_problems({'run': {'difficulty': 3, 'scaled': 2, 'left': 2}}, {'difficulty': 3}), [])
        self.assertTrue(TX.difficulty_problems({'run': {'difficulty': 1}}, {'difficulty': 3, 'asked': 3}))
        self.assertIn('Weekly', TX.weekly_board_problem({'testersListed': 1}, 'after the run') or 'Weekly')
        self.assertIsNone(TX.weekly_board_problem({'testersListed': 0}, 'x'))
        self.assertIsNone(TX.weekly_board_problem(None, 'x'))

    def test_a_difficulty_is_unlocked_asked_for_and_carried(self):
        w = DifficultyWorld()
        r, io = self.play(w)
        self.assertEqual(r.status, TX.PASS, r.detail)
        self.assertIn('Rootmaw at difficulty 3', r.detail)
        self.assertIn('3 of 3 monster(s) scaled', r.detail)
        self.assertEqual(w.unlocked, [(4, 3)], 'the helper unlocked it on the bot\'s own progress')
        self.assertEqual(w.asked['Tester Aaa'], 3, 'the queue asked for it')
        cmds = [c for _, c in io.cmds]
        self.assertIn('dungeon unlock 4 3', cmds)
        self.assertEqual(TX.DUNGEON_DIFF_DONE.get(3), 'Tester Aaa')
        queue_i = [i for i, (o, a, d) in enumerate(io.asked) if a == 'queue'][0]
        self.assertGreater(len(io.asked), queue_i)

    def test_what_goes_wrong(self):
        r, _ = self.play(DifficultyWorld(run_diff=1))
        self.assertEqual(r.status, TX.FAIL, r.detail)
        self.assertIn('the run is at difficulty 1', r.detail)
        r, _ = self.play(DifficultyWorld(unlock_ok=False))
        self.assertEqual(r.status, TX.SKIP, r.detail)
        self.assertIn('could not be unlocked', r.detail)
        r, _ = self.play(DifficultyWorld(level=100), level=100)
        self.assertEqual(r.status, TX.SKIP, r.detail)
        self.assertIn('no free dungeon carries difficulty', r.detail)

    def test_the_weekly_challenge_is_at_its_fixed_difficulty(self):
        w = DifficultyWorld()
        r, io = self.play(w, TX.check_weekly_challenge)
        self.assertEqual(r.status, TX.PASS, r.detail)
        self.assertIn('Weekly Challenge 2026-W46 (Marrow Crypts)', r.detail)
        self.assertEqual(w.asked['Tester Aaa'], TX.WEEKLY_ASK, 'the bot asked for another difficulty')
        self.assertEqual(w.unlocked, [], 'nothing is unlocked for a dungeon with one difficulty')
        self.assertEqual(w.weekly_calls, 2, 'the boards were read before and after')
        self.assertNotIn('difficulty %d' % TX.WEEKLY_ASK, r.detail.split('(')[0])

    def test_the_weekly_challenge_bugs_and_skips(self):
        r, _ = self.play(DifficultyWorld(run_diff=TX.WEEKLY_ASK), TX.check_weekly_challenge)
        self.assertEqual(r.status, TX.FAIL, r.detail)
        self.assertIn('the check expects 1', r.detail)
        r, _ = self.play(DifficultyWorld(listed=(0, 2)), TX.check_weekly_challenge)
        self.assertEqual(r.status, TX.FAIL, r.detail)
        self.assertIn('2 tester(s) after the run', r.detail)
        r, _ = self.play(DifficultyWorld(listed=(1, 1)), TX.check_weekly_challenge)
        self.assertEqual(r.status, TX.FAIL, r.detail)
        self.assertIn('before the run', r.detail)
        r, _ = self.play(DifficultyWorld(weekly=False), TX.check_weekly_challenge)
        self.assertEqual((r.status, 'not built this week' in r.detail), (TX.SKIP, True))
        r, _ = self.play(DifficultyWorld(current=False), TX.check_weekly_challenge)
        self.assertEqual((r.status, 'not this week' in r.detail), (TX.SKIP, True))
        r, _ = self.play(DifficultyWorld(level=500), TX.check_weekly_challenge, level=500)
        self.assertEqual((r.status, 'needs level 800' in r.detail), (TX.SKIP, True))
        TX.DUNGEON_BUSY[7] = 'Tester Zzz'
        r, _ = self.play(DifficultyWorld(), TX.check_weekly_challenge)
        self.assertEqual((r.status, 'Tester Zzz' in r.detail), (TX.SKIP, True))


# ------------------------------------------------------------------------------------------------ O651: a waystone map walked
class WsWorld(RiftWorld):
    """a waystone map on the rift lane: the temple at x 92, four monsters at x 10, 20, 30, 40. `wsmap state | enter | path | close`; the bot arrives at x 0"""

    def __init__(self, level=1500, arrivals=4, free=True, free_why=None, free_tier=1, tier_level=1100, enter_err=None, players=0, level_bad=False,
                 never_kill=False, evict_after=None, err=None, **kw):
        super().__init__(level=level, **kw)
        self.arrivals, self.free, self.free_why, self.free_tier, self.tier_level = arrivals, free, free_why, free_tier, tier_level
        self.enter_err, self.players, self.level_bad, self.evict_after, self.err_w, self.never_kill_w = enter_err, players, level_bad, evict_after, err, never_kill
        self.in_map, self.mons, self.dead, self.looks, self.entered, self.closed_w = False, [10, 20, 30, 40], set(), 0, [], 0

    def alive_m(self):
        return [m for m in self.mons if m not in self.dead]

    def wguide(self):
        alive = self.alive_m()
        if not alive:
            return {'mode': 'wait', 'why': 'no monster in sight'}
        x = min(alive, key=lambda m: abs(m - self.pos[0]))
        return {'mode': 'fight' if abs(self.pos[0] - x) <= 5 else 'walk', 'goal': {'x': x, 'y': 5, 'z': 7}, 'reach': [1, 5], 'area': 'pack', 'why': 'test'}

    def wfacts(self):
        out = {'inside': self.in_map, 'level': self.level, 'pos': {'x': self.pos[0], 'y': self.pos[1], 'z': 7}, 'minLevel': 1000, 'kills': 3, 'arrivals': self.arrivals,
               'enabled': True}
        if self.in_map:
            out['run'] = {'map': 9, 'tier': self.free_tier, 'tierLevel': self.tier_level, 'since': self.looks, 'left': 500, 'players': self.players,
                          'monsters': len(self.alive_m()), 'monsterLevel': self.tier_level + (7 if self.level_bad else 0), 'nearestHp': 100}
            out['guide'] = self.wguide()
        else:
            out.update(free=self.free, freeTier=self.free_tier if self.free else None, freeTierLevel=self.tier_level if self.free else None,
                       why=self.free_why if not self.free else None)
        return out

    def wtick(self):
        if not self.in_map:
            return
        self.looks += 1
        if self.evict_after is not None and self.looks > self.evict_after:
            self.in_map, self.pos = False, (self.TEMPLE - 1, 5)
            return
        g = self.wguide()
        if g['mode'] == 'fight' and not self.never_kill_w:
            self.dead.add(g['goal']['x'])

    def answer(self, command):
        if command == 'wsmap state':
            if self.err_w:
                return {'err': self.err_w}
            self.wtick()
            return self.wfacts()
        if command.startswith('wsmap enter'):
            self.entered.append(command)
            if self.enter_err:
                return dict(self.wfacts(), err=self.enter_err)
            self.in_map, self.pos, self.looks = True, (0, 5), 0
            return dict(self.wfacts(), entered=True, map=9, tier=self.free_tier)
        if command == 'wsmap path':
            g = self.wguide()
            if not self.in_map or g['mode'] != 'walk':
                return dict(self.wfacts(), err='no goal' if self.in_map else 'not inside a waystone map')
            return dict(self.wfacts(), path=self.path_to(g['goal']['x'], 5), dist=abs(self.pos[0] - g['goal']['x']))
        if command == 'wsmap close':
            was = self.in_map
            self.in_map = False
            self.closed_w += 1
            return dict(self.wfacts(), closed=was)
        return super().answer(command)

    def pz(self):
        return super().pz() and not self.in_map


class WsIO(RiftIO):
    pass


class WaystoneMapWalk(unittest.TestCase):
    def setUp(self):
        self.keep = (TX.WSMAP_BUDGET, TX.SOLO_FIGHT_MIN, TX.SOLO_STUCK)

    def tearDown(self):
        TX.WSMAP_BUDGET, TX.SOLO_FIGHT_MIN, TX.SOLO_STUCK = self.keep

    def play(self, world, level=1500):
        io = WsIO(world)
        return run(TX.check_wsmap_walk(io, 'Tester Aaa', 'Warrior', level)), io

    def test_the_pure_parts(self):
        a = {'level': 1500, 'minLevel': 1000, 'arrivals': 4, 'free': True, 'freeTier': 1, 'freeTierLevel': 1100}
        self.assertIsNone(TX.wsmap_refusal(a))
        for bad, word in ((None, 'old helper'), ({'err': 'no waystone system'}, 'no waystone'), (dict(a, enabled=False), 'off'), (dict(a, level=900), 'need level 1000'),
                          (dict(a, inside=True), 'inside'), (dict(a, arrivals=0), 'arrival tile'), (dict(a, free=False, why='somebody is in the map'), 'somebody is in the map'),
                          (dict(a, level=1000, freeTierLevel=1300), 'free waystone map is tier')):
            r = TX.wsmap_refusal(bad)
            self.assertEqual(r[0], TX.SKIP)
            self.assertIn(word, r[1])
        trace = {}
        self.assertEqual(TX.wsmap_problems({'run': {'players': 0, 'monsters': 8, 'tier': 1, 'tierLevel': 1100, 'monsterLevel': 1100, 'map': 3}}, trace), [])
        self.assertEqual(TX.wsmap_problems({'run': {'players': 0, 'monsters': 5, 'tier': 1, 'tierLevel': 1100, 'monsterLevel': 1100, 'map': 3}}, trace), [])
        self.assertEqual(trace['kills'], 3)
        self.assertTrue(TX.wsmap_problems({'run': {'players': 1, 'monsters': 5}}, trace))
        self.assertTrue(TX.wsmap_problems({'run': {'players': 0, 'monsters': 5, 'tierLevel': 1100, 'monsterLevel': 1107}}, trace))
        base = {'secs': 60, 'steps': 10, 'came': 'helper', 'level': 1500, 'tier': 1, 'tier_level': 1100, 'map': 3}
        self.assertEqual(TX.wsmap_walk_verdict(dict(base, faults=['x']))[0], TX.FAIL)
        self.assertEqual(TX.wsmap_walk_verdict(dict(base, kills=3))[0], TX.PASS)
        self.assertEqual(TX.wsmap_walk_verdict(dict(base, kills=1, fought=TX.SOLO_FIGHT_MIN))[0], TX.FAIL, 'a long fight with too few kills is a bug')
        self.assertEqual(TX.wsmap_walk_verdict(dict(base, kills=0, fought=TX.SOLO_FIGHT_MIN))[0], TX.FAIL)
        self.assertEqual(TX.wsmap_walk_verdict(dict(base, kills=0, stuck=(1, 2)))[0], TX.SKIP)
        self.assertEqual(TX.wsmap_walk_verdict(dict(base, kills=0, died=True))[0], TX.SKIP)
        self.assertEqual(TX.wsmap_walk_verdict(dict(base, kills=1))[0], TX.SKIP)
        self.assertIn('wsmap_walk', TX.KEYS)
        self.assertLess(TX.KEYS.index('wsmap_walk'), TX.KEYS.index('rift_walk'))

    def test_a_map_walked_is_a_pass_with_a_counted_teleport(self):
        r, io = self.play(WsWorld())
        self.assertEqual(r.status, TX.PASS, r.detail)
        self.assertIn('tier 1 (level 1100)', r.detail)
        self.assertEqual(io.w.entered, ['wsmap enter 1'])
        self.assertEqual(len(r.fallbacks), 1)
        self.assertIn('waystone device', r.fallbacks[0])
        self.assertIn('teleport in place of walking', r.detail)
        self.assertEqual(io.w.teleports, 0, 'the bot walked to the temple')
        self.assertGreaterEqual(io.w.closed_w, 1)
        self.assertFalse(io.w.in_map)
        self.assertEqual(io.moves[-1], 'hunt')
        self.assertEqual(io.modes[-1], (['Tester Aaa'], False, False))
        self.assertLess(io.cmds.index('path temple'), io.cmds.index('wsmap enter 1'))

    def test_the_band_the_server_offers_is_asked_for(self):
        r, io = self.play(WsWorld(free_tier=6, tier_level=1600))
        self.assertEqual(r.status, TX.PASS, r.detail)
        self.assertEqual(io.w.entered, ['wsmap enter 6'])

    def test_skips(self):
        for world, word in ((WsWorld(err='no waystone system'), 'no waystone'), (WsWorld(arrivals=0), 'arrival tile'),
                            (WsWorld(free=False, free_why='a tester run holds the map'), 'tester run holds the map'), (WsWorld(level=900), 'need level 1000'),
                            (WsWorld(enter_err='somebody is in the map'), 'somebody is in the map')):
            r, io = self.play(world, level=world.level)
            self.assertEqual(r.status, TX.SKIP, r.detail)
            self.assertIn(word, r.detail)
            self.assertFalse(io.w.in_map)

    def test_bugs(self):
        r, _ = self.play(WsWorld(players=1))
        self.assertEqual(r.status, TX.FAIL, r.detail)
        self.assertIn('player(s) are in the waystone map of the testers', r.detail)
        r, _ = self.play(WsWorld(level_bad=True))
        self.assertEqual(r.status, TX.FAIL, r.detail)
        self.assertIn('the run is tier 1', r.detail)
        TX.SOLO_FIGHT_MIN = 8.0
        r, io = self.play(WsWorld(never_kill=True))
        self.assertEqual(r.status, TX.FAIL, r.detail)
        self.assertIn('killed none', r.detail)
        self.assertGreaterEqual(io.w.closed_w, 1)

    def test_the_server_sends_the_bot_out(self):
        r, io = self.play(WsWorld(evict_after=1))
        self.assertEqual(r.status, TX.SKIP, r.detail)
        self.assertIn('out of the map before it killed a monster', r.detail)
        self.assertEqual(io.moves[-1], 'hunt')
        TX.WSMAP_BUDGET = 4.0
        r, _ = self.play(WsWorld(never_kill=True))
        self.assertEqual(r.status, TX.SKIP, r.detail)
        self.assertIn('only 0 of 3', r.detail)


# ------------------------------------------------------------------------------------------------ O655: ascension, spells, tales, tasks, gathering, settings
class AscWorld:
    """the Oracle, the Proof, the Trial and the Choice of one base class tester: words, modal windows and the helper's `ascend` answers"""

    def __init__(self, stage=0, voc=4, locked=(), free=8, reserve=2, wait=0, no_trial_window=False, trial_never_opens=False, grant_locked=False,
                 enter_stays=False, level=100, deadly=False):
        self.stage, self.voc, self.ascended, self.inside, self.looks = stage, voc, False, False, 0
        self.locked, self.free, self.reserve, self.wait = set(locked), free, reserve, wait
        self.no_trial_window, self.trial_never_opens, self.grant_locked = no_trial_window, trial_never_opens, grant_locked
        self.enter_stays, self.level, self.deadly = enter_stays, level, False
        self.choices = [{'i': 1, 'word': 'berserker', 'id': 14, 'name': 'Berserker'}, {'i': 2, 'word': 'paladin', 'id': 15, 'name': 'Paladin Lord'}]
        self.said, self.answers = [], []
        self.cooldown_after_fail = deadly

    def probe(self, **extra):
        out = {'enabled': True, 'level': self.level, 'minLevel': 100, 'voc': self.voc, 'vocName': {4: 'Warrior', 14: 'Berserker', 15: 'Paladin Lord'}[self.voc],
               'eligible': not self.ascended, 'ascended': self.ascended, 'stage': self.stage, 'wait': self.wait, 'needed': 10, 'proof': 10 if self.stage >= 2 else 0,
               'inside': self.inside, 'free': self.free, 'reserve': self.reserve, 'tester': True, 'pos': {'x': 5, 'y': 5, 'z': 7},
               'choices': [dict(c, allowed=c['id'] not in self.locked) for c in self.choices]}
        if self.ascended:
            out['why'] = 'ascended'
        if self.inside:
            hp = max(0, 100 - 40 * self.looks)
            out['run'] = {'state': 'fight', 'boss': 'alive', 'bossHp': hp, 'adds': 0, 'players': 1, 'testers': 1, 'tester': True}
            out['guide'] = {'mode': 'fight', 'goal': {'x': 6, 'y': 5, 'z': 7}, 'area': 'boss'}
        out.update(extra)
        return out

    def answer(self, command):
        if command == 'path npc Ascendant Oracle':
            return {'here': True}
        if command == 'ascend proof':
            if self.stage != 1:
                return {'err': 'the Proof of Strength is not open (stage %d)' % self.stage}
            self.stage = 2
            return self.probe(proofed=True)
        if command == 'ascend close':
            return self.probe(closed=False)
        if command == 'ascend state':
            if self.inside:
                self.looks += 1
                if self.looks >= 3 and not self.trial_never_opens:
                    self.inside, self.stage = False, 3
            return self.probe()
        return None


class AscIO(FakeIO):
    def __init__(self, world, **kw):
        super().__init__(**kw)
        self.w, self.modes, self.cmds, self.looted = world, [], [], 0

    async def helper(self, command, kind, wait=4.0):
        self.cmds.append(command)
        return self.w.answer(command)

    async def go(self, place):
        self.moves.append(place)
        return True

    async def said_and_heard(self, text, wait=1.5, kind=1):
        w = self.w
        w.said.append(text)
        if text == 'ascension' and w.stage == 0:
            w.stage = 1
        return []

    async def say_modal(self, text, ids, wait=5.0, kind=1):
        w = self.w
        if text == 'trial' and w.stage == 2 and not w.no_trial_window:
            return {'id': 7101, 'title': 'The Trial of Ascension', 'message': 'm', 'buttons': [(1, 'Enter'), (2, 'Not yet')], 'choices': [], 'escape': 2, 'enter': 1}, []
        if text == 'choice' and w.stage == 3:
            return {'id': 7102, 'title': 'The Choice', 'message': 'm', 'buttons': [(1, 'Choose'), (2, 'Not yet')],
                    'choices': [(1, 'Berserker'), (2, 'Paladin Lord')], 'escape': 2, 'enter': 1}, []
        return None, ['You are not ready.']

    async def modal_answer(self, window_id, button, choice, wait=1.5, ids=()):
        w = self.w
        w.answers.append((window_id, button, choice))
        if window_id == 7101 and button == 1:
            w.inside, w.looks = True, 0
            return None, []
        if window_id == 7102:
            c = w.choices[choice - 1]
            return {'id': 7110 + c['id'], 'title': 'Ascend?', 'message': 'm', 'buttons': [(1, 'Ascend'), (2, 'Cancel')], 'choices': [], 'escape': 2, 'enter': 1}, []
        if window_id > 7110 and button == 1:
            vid = window_id - 7110
            if vid in w.locked and not w.grant_locked:
                return None, ['That class is locked. Unlock it in the store.']
            w.voc, w.ascended, w.stage = vid, True, 4
            return None, ['You have ascended.']
        return None, []

    async def step(self, dx, dy):
        pass

    async def loot(self):
        self.looted += 1

    def raid_mode(self, names, on, keep_flee=False):
        self.modes.append((list(names), on, keep_flee))


class AscensionWalk(unittest.TestCase):
    def setUp(self):
        self.keep = (TX.ASC_TRIAL_BUDGET, TX.ASC_ENTER_WAIT, TX.ASC_BACK_WAIT)

    def tearDown(self):
        TX.ASC_TRIAL_BUDGET, TX.ASC_ENTER_WAIT, TX.ASC_BACK_WAIT = self.keep

    def play(self, **kw):
        w = AscWorld(**kw)
        io = AscIO(w)
        return run(TX.check_ascension_walk(io, 'Tester Asc', 'Warrior', w.level)), io, w

    def test_the_whole_quest_with_a_locked_class(self):
        r, io, w = self.play(locked=(14,))
        self.assertEqual(r.status, TX.PASS, r.detail)
        self.assertIn('steps: calling, proof, trial, locked, choice', r.detail)
        self.assertIn('the class lock refused Berserker', r.detail)
        self.assertIn('Warrior became Paladin Lord', r.detail)
        self.assertEqual((w.voc, w.stage, w.ascended), (15, 4, True))
        self.assertEqual(w.answers[0], (7101, 1, 0), 'Enter pressed in the trial window')
        self.assertIn((7102, 1, 1), w.answers, 'the locked class was chosen first, in the window\'s own order')
        self.assertIn((7102, 1, 2), w.answers)
        self.assertEqual(w.said.count('ascension'), 1)
        self.assertIn('ascend proof', io.cmds)
        self.assertEqual(io.cmds.count('ascend close') >= 2, True, 'the bot\'s own trial is closed after the play and in the finally')
        self.assertEqual(io.modes[0][1:], (True, True))
        self.assertEqual(io.modes[-1][1], False)
        self.assertEqual(io.moves[-1], 'hunt')

    def test_an_open_line_walks_to_the_first_class(self):
        r, io, w = self.play()
        self.assertEqual(r.status, TX.PASS, r.detail)
        self.assertNotIn('locked', r.detail.split(';')[0])
        self.assertEqual((w.voc, w.ascended), (14, True))

    def test_a_locked_class_that_is_granted_is_a_bug(self):
        r, _, w = self.play(locked=(14,), grant_locked=True)
        self.assertEqual(r.status, TX.FAIL)
        self.assertIn('is locked for the account and the Oracle ascended the bot to it', r.detail)

    def test_every_class_locked_proves_the_refusal_only(self):
        r, _, w = self.play(locked=(14, 15))
        self.assertEqual(r.status, TX.PASS, r.detail)
        self.assertIn('locked', r.detail)
        self.assertIn('every class of the line is locked', r.detail)
        self.assertEqual((w.voc, w.stage), (4, 3))

    def test_the_stages_are_resumed(self):
        r, io, w = self.play(stage=2)
        self.assertEqual(r.status, TX.PASS)
        self.assertIn('steps: trial, choice', r.detail)
        self.assertNotIn('ascend proof', io.cmds)
        r, io, w = self.play(stage=3)
        self.assertIn('steps: choice', r.detail)

    def test_the_stops_and_the_skips(self):
        r, _, _ = self.play(stage=2, wait=300)
        self.assertEqual((r.status, 'closed for 300 s' in r.detail), (TX.SKIP, True))
        r, _, _ = self.play(stage=2, free=2)
        self.assertEqual((r.status, 'kept for the players' in r.detail), (TX.SKIP, True))
        r, _, _ = self.play(stage=2, no_trial_window=True)
        self.assertEqual((r.status, 'opened no trial window' in r.detail), (TX.SKIP, True))
        TX.ASC_TRIAL_BUDGET = 6.0
        r, _, w = self.play(stage=2, trial_never_opens=True)
        self.assertEqual(r.status, TX.SKIP, r.detail)
        self.assertIn('not broken', r.detail)

    def test_the_refusals(self):
        self.assertEqual(TX.ascension_refusal(None)[0], TX.SKIP)
        self.assertEqual(TX.ascension_refusal({'err': 'no ascension quest'})[1], 'no ascension quest')
        self.assertIn('level 50', TX.ascension_refusal({'enabled': True, 'eligible': False, 'why': 'level', 'level': 50, 'minLevel': 100})[1])
        self.assertIn('ascended class already', TX.ascension_refusal({'enabled': True, 'ascended': True, 'vocName': 'Berserker'})[1])
        self.assertIn('no ascension', TX.ascension_refusal({'enabled': True, 'eligible': False, 'why': 'noline'})[1])
        self.assertIn('done already', TX.ascension_refusal({'enabled': True, 'eligible': True, 'stage': 4})[1])
        self.assertIn('inside a trial', TX.ascension_refusal({'enabled': True, 'eligible': True, 'stage': 2, 'inside': True})[1])
        self.assertIsNone(TX.ascension_refusal({'enabled': True, 'eligible': True, 'stage': 0}))
        for a in ({'enabled': False}, ):
            self.assertEqual(TX.ascension_refusal(a)[0], TX.SKIP)
        self.assertEqual(run(TX.check_ascension_walk(FakeIO(), 'a', 'Warrior', 100)).status, TX.SKIP)

    def test_the_choice_plan_and_the_verdicts(self):
        locked, allowed = TX.asc_choice_plan([{'i': 1, 'id': 14, 'allowed': False}, {'i': 2, 'id': 15, 'allowed': True}, {'bad': 1}])
        self.assertEqual(([c['id'] for c in locked], [c['id'] for c in allowed]), ([14], [15]))
        self.assertEqual(TX.asc_choice_plan(None), ([], []))
        self.assertEqual(TX.ascension_verdict({'faults': ['x']})[0], TX.FAIL)
        self.assertEqual(TX.ascension_verdict({'done': [], 'why': 'nothing'})[0], TX.SKIP)
        st, text = TX.ascension_verdict({'done': ['calling'], 'why': 'no proof', 'fallbacks': ['enter npc']})
        self.assertEqual(st, TX.PASS)
        self.assertIn('(stopped: no proof)', text)
        self.assertIn('enter npc', text)

    def test_it_runs_last_and_is_an_open_check(self):
        self.assertIn('ascension_walk', TX.KEYS)
        self.assertNotIn('ascension_walk', TX.CLOSED_KEYS)
        self.assertEqual(TX.KEYS[-1], 'ascension_walk', 'the class changes: after every other check')
        self.assertLess(TX.KEYS.index('rift_walk'), TX.KEYS.index('ascension_walk'))


class SpellIO(FakeIO):
    def __init__(self, spells, replies_by_words=None, **kw):
        super().__init__(**kw)
        self.list, self.by_words, self.cast = spells, replies_by_words or {}, []

    def class_spells(self):
        return self.list

    async def said_and_heard(self, text, wait=1.5, kind=1):
        self.cast.append(text)
        return self.by_words.get(text, [])


def spell(words, group='support', level=8, **kw):
    return dict({'words': words, 'name': words, 'group': group, 'level': level, 'needlearn': False, 'params': False, 'needtarget': False}, **kw)


class SpellSupport(unittest.TestCase):
    LIST = [spell('utani hur'), spell('exura', 'healing', 1), spell('exori', 'attack', 1), spell('utevo res', params=True), spell('exeta', needtarget=True),
            spell('vok aeg', 'attack', 10, needlearn=True, needtarget=True), spell('far', level=900)]

    def go(self, io, level=50):
        return run(TX.check_spell_support(io, 'Tester Spl', 'Ninja', level))

    def test_the_pick(self):
        self.assertEqual([s['words'] for s in TX.spell_support_pick(self.LIST, 50)], ['utani hur', 'exura'], 'no attack, parameter, target, learning or level')
        self.assertEqual(len(TX.spell_support_pick([spell('w%d' % i, level=i) for i in range(1, 20)], 50, 3)), 3)
        self.assertEqual([s['words'] for s in TX.spell_learn_pick(self.LIST, 50)], ['vok aeg'])
        self.assertEqual(TX.spell_learn_pick(self.LIST, 5), [])
        self.assertEqual(TX.spell_support_pick([spell('a'), spell('a')], 50), [spell('a')], 'one row per words')

    def test_the_refusal_kinds(self):
        for text, kind in (('You must learn this spell first.', 'unknown'), ('Your vocation cannot use this spell.', 'vocation'), ('You need a premium account.', 'premium'),
                           ('You do not have enough level.', 'level'), ('You do not have enough mana.', 'mana'), ('You are exhausted.', 'exhausted')):
            self.assertEqual(TX.spell_refusal([text]), kind)
        self.assertIsNone(TX.spell_refusal(['You see a rat.']))
        self.assertIsNone(TX.spell_refusal([]))

    def test_the_support_spells_are_cast_and_the_learned_one_is_refused(self):
        io = SpellIO(self.LIST, {'vok aeg': ['You must learn this spell first.']})
        r = self.go(io)
        self.assertEqual(r.status, TX.PASS, r.detail)
        self.assertEqual(io.cast, ['utani hur', 'exura', 'vok aeg'])
        self.assertIn('2 of 2 support spell(s) cast with no refusal', r.detail)
        self.assertIn('1 of 1 learned-spell(s) refused', r.detail)

    def test_a_listed_spell_that_is_refused_is_a_bug(self):
        for text, kind in (('You must learn this spell first.', 'unknown'), ('Your vocation cannot use this spell.', 'vocation')):
            r = self.go(SpellIO(self.LIST, {'utani hur': [text]}))
            self.assertEqual(r.status, TX.FAIL)
            self.assertIn('utani hur (%s)' % kind, r.detail)

    def test_mana_holds_a_cast_back_and_silence_on_a_learned_spell_is_a_note(self):
        r = self.go(SpellIO(self.LIST, {'exura': ['You do not have enough mana.']}))
        self.assertEqual((r.status, '1 held back by mana' in r.detail, '1 cast without a word' in r.detail), (TX.PASS, True, True))
        r = self.go(SpellIO(self.LIST, {'utani hur': ['You are exhausted.'], 'exura': ['You do not have enough mana.']}))
        self.assertEqual(r.status, TX.SKIP)

    def test_skips(self):
        self.assertEqual(self.go(SpellIO([])).status, TX.SKIP)
        self.assertEqual(self.go(SpellIO([spell('exori', 'attack', 1)])).status, TX.SKIP)
        self.assertIn('spell_support', TX.KEYS)


class TalesIO(FakeIO):
    def __init__(self, listing, tale=None, answers=None):
        super().__init__(answers=dict({'path npc Archivist Maelis': {'here': True}}, **(answers or {})))
        self.listing, self.tale, self.pressed = listing, tale, []

    async def say_modal(self, text, ids, wait=5.0, kind=1):
        self.kind_said = kind   # O656: the words after the greeting go in the NPC channel
        return self.listing, ['She looks up.']

    async def modal_answer(self, window_id, button, choice, wait=1.5, ids=()):
        self.pressed.append((window_id, button, choice))
        return (self.tale if window_id == 7170 and 7171 in ids else None), []


def tales_window(choices=((1, 'The Hollow Road'),), buttons=((1, 'Read'), (2, 'Close')), title='Tales of the Ash'):
    return {'id': 7170, 'title': title, 'message': 'pick', 'buttons': list(buttons), 'choices': list(choices), 'escape': 2, 'enter': 1}


class TalesRead(unittest.TestCase):
    def go(self, io):
        return run(TX.check_tales_read(io, 'Tester Tal', 'Ninja', 300))

    def test_read_opens_a_tale_and_the_windows_close(self):
        tale = {'id': 7171, 'title': 'The Hollow Road', 'message': 'Once...', 'buttons': [(2, 'Close')], 'choices': [], 'escape': 2, 'enter': 2}
        io = TalesIO(tales_window(), tale)
        r = self.go(io)
        self.assertEqual(r.status, TX.PASS, r.detail)
        self.assertIn('Read opened "The Hollow Road"', r.detail)
        self.assertEqual(io.pressed[0], (7170, 1, 1), 'Read with the first tale')
        self.assertEqual(io.kind_said, TX.NPC_CHANNEL, 'O656: "tales" goes in the NPC channel (12), a plain say after the greeting is ignored by the NPC library')
        self.assertEqual(TX.NPC_CHANNEL, 12)
        self.assertEqual(io.pressed[1], (7171, 2, 255), 'the tale closed with its escape button')
        self.assertEqual(io.pressed[2][:2], (7170, 2), 'the list closed')

    def test_the_bugs_and_the_skips(self):
        self.assertEqual((self.go(TalesIO(tales_window(), None)).status), TX.FAIL)
        self.assertIn('no tale window came', self.go(TalesIO(tales_window(), None)).detail)
        r = self.go(TalesIO(tales_window(buttons=((1, 'Go'),)), None))
        self.assertEqual((r.status, 'not Read and Close' in r.detail), (TX.FAIL, True))
        self.assertEqual(self.go(TalesIO(tales_window(title=''), None)).status, TX.FAIL)
        r = self.go(TalesIO(tales_window(choices=()), None))
        self.assertEqual((r.status, 'no tale open' in r.detail), (TX.PASS, True))
        r = self.go(TalesIO(None))
        self.assertEqual((r.status, 'opened no list of tales' in r.detail, 'She looks up' in r.detail), (TX.SKIP, True, True))
        tale = {'id': 7171, 'title': '', 'message': '', 'buttons': [], 'choices': [], 'escape': 0, 'enter': 0}
        self.assertEqual(self.go(TalesIO(tales_window(), tale)).status, TX.FAIL)
        io = TalesIO(None, answers={'path npc Archivist Maelis': {'err': 'no way'}})
        io.answers['enter npc Archivist Maelis'] = {'err': 'no npc'}
        self.assertEqual(run(TX.check_tales_read(io, 'a', 'Ninja', 300)).status, TX.SKIP)


class KillTaskIO(ChoreIO):
    pass


def board(offers=(), tasks=()):
    return {'action': 'board', 'data': {'offers': list(offers), 'tasks': list(tasks)}}


class KillTask(unittest.TestCase):
    def go(self, io, level=300):
        return run(TX.check_kill_task(io, 'Tester Kil', 'Ninja', level))

    OFFERS = [{'key': 'fam:bug:1', 'kind': 'family', 'state': 'done', 'required': 5, 'lo': 1, 'hi': 50},
              {'key': 'fam:rat:2', 'kind': 'family', 'state': 'open', 'required': 40, 'lo': 250, 'hi': 350, 'label': 'rats'},
              {'key': 'hunt:troll', 'kind': 'hunt', 'state': 'open', 'required': 20, 'lo': 10, 'hi': 20, 'label': 'trolls'},
              {'key': 'fam:ant:3', 'kind': 'family', 'state': 'open', 'required': 30, 'lo': 200, 'hi': 400, 'label': 'ants'}]

    def test_accept_listed_active_abandon(self):
        held = {'key': 'fam:ant:3', 'required': 30, 'progress': 0}
        io = KillTaskIO({('bestiary', 'board'): board(self.OFFERS),
                         ('bestiary', 'accept'): board([dict(o, state='active') if o['key'] == 'fam:ant:3' else o for o in self.OFFERS], [held]),
                         ('bestiary', 'abandon'): board(self.OFFERS)})
        r = self.go(io)
        self.assertEqual(r.status, TX.PASS, r.detail)
        self.assertIn(('bestiary', 'accept', {'key': 'fam:ant:3'}), io.asked, 'an open offer whose level window holds the bot, the fewest kills')
        self.assertEqual(io.asked[-1][:2], ('bestiary', 'abandon'))

    def test_the_bugs(self):
        held = {'key': 'fam:ant:3', 'required': 30, 'progress': 0}
        act = [dict(o, state='active') if o['key'] == 'fam:ant:3' else o for o in self.OFFERS]
        active = board(act, [held])
        r = self.go(KillTaskIO({('bestiary', 'board'): board(self.OFFERS), ('bestiary', 'accept'): active, ('bestiary', 'abandon'): active}))
        self.assertEqual((r.status, 'still in the active list' in r.detail), (TX.FAIL, True))
        r = self.go(KillTaskIO({('bestiary', 'board'): board(self.OFFERS), ('bestiary', 'accept'): board(self.OFFERS, [dict(held, progress=4)]),
                                ('bestiary', 'abandon'): board(self.OFFERS)}))
        self.assertEqual((r.status, 'shows 4 of 30' in r.detail), (TX.FAIL, True))
        r = self.go(KillTaskIO({('bestiary', 'board'): board(self.OFFERS), ('bestiary', 'accept'): board(self.OFFERS), ('bestiary', 'abandon'): board(self.OFFERS)}))
        self.assertEqual((r.status, 'did not take' in r.detail), (TX.SKIP, True))
        r = self.go(KillTaskIO({('bestiary', 'board'): board(self.OFFERS), ('bestiary', 'accept'): board(
            [dict(o, state='open') for o in self.OFFERS], [held]), ('bestiary', 'abandon'): board(self.OFFERS)}))
        self.assertEqual((r.status, 'not active' in r.detail), (TX.FAIL, True))

    def test_the_skips(self):
        self.assertEqual(self.go(KillTaskIO()).status, TX.SKIP)
        r = self.go(KillTaskIO({('bestiary', 'board'): board([dict(self.OFFERS[0])])}))
        self.assertEqual((r.status, 'no open kill task' in r.detail), (TX.SKIP, True))
        self.assertIsNone(TX.kill_task_pick(None, 10))


class GatherIO(ChoreIO):
    def __init__(self, probes, shop=None):
        super().__init__()
        self.probes, self.used, self.bought, self.shop_items = list(probes), [], [], shop
        self.answers['path npc Material Broker'] = {'here': True}

    async def helper(self, command, kind, wait=4.0):
        if command == 'gather state':
            return self.probes.pop(0) if len(self.probes) > 1 else self.probes[0]
        if command == 'gather path':
            return {'here': True, 'dist': 0}
        return self.answers.get(command)

    async def shop_window(self, npc, wait=5.0):
        return self.shop_items

    def shop_close(self):
        pass

    async def buy(self, item_id, amount=1):
        self.bought.append(item_id)

    async def use_at(self, pos, client_id, stackpos=0, wait=1.5):
        self.used.append((pos, client_id, stackpos))
        return list(self.texts)

    texts = []

    async def step(self, dx, dy):
        pass

    def raid_mode(self, names, on, keep_flee=False):
        pass


def gprobe(held=0, tools=True, node=True, gathering=False, d=0, **kw):
    out = {'enabled': True, 'levelOk': True, 'level': 100, 'minLevel': 20, 'held': held, 'gathering': gathering, 'bank': 500,
           'tools': {'delving': tools, 'wortcunning': False}, 'buy': [{'id': 2553, 'clientId': 2553, 'price': 50}, {'id': 2405, 'clientId': 2405, 'price': 20}, {'id': 5908, 'clientId': 5908, 'price': 600}]}
    if node:
        out['node'] = {'prof': 'delving', 'tier': 2, 'id': 100, 'clientId': 4000, 'pos': {'x': 9, 'y': 9, 'z': 7}, 'stackpos': 1, 'd': d}
    out.update(kw)
    return out


class GatherWalk(unittest.TestCase):
    def go(self, io, level=100):
        return run(TX.check_gather_walk(io, 'Tester Gat', 'Ninja', level))

    def test_the_node_is_used_and_the_material_comes(self):
        io = GatherIO([gprobe(0), gprobe(0), gprobe(0), gprobe(3, gathering=True)])
        r = self.go(io)
        self.assertEqual(r.status, TX.PASS, r.detail)
        self.assertIn('gathered 3 material(s) from a delving node of tier 2', r.detail)
        self.assertEqual(io.used[0], ({'x': 9, 'y': 9, 'z': 7}, 4000, 1))
        self.assertEqual(io.bought, [], 'the bot has a pick: nothing to buy')

    def test_a_bot_without_a_tool_buys_the_cheapest_at_the_broker(self):
        io = GatherIO([gprobe(0, tools=False, node=False), gprobe(0), gprobe(0), gprobe(0), gprobe(2)], shop=[{'id': 2405, 'name': 'sickle', 'buy': 20}, {'id': 2553, 'name': 'pick', 'buy': 50}])
        r = self.go(io)
        self.assertEqual(r.status, TX.PASS, r.detail)
        self.assertEqual(io.bought, [2405], 'the sickle: the cheapest')
        io = GatherIO([gprobe(0, tools=False, node=False)], shop=[{'id': 2405, 'name': 'sickle', 'buy': 20}])
        r = self.go(io)
        self.assertEqual((r.status, 'holds no pick or sickle' in r.detail), (TX.FAIL, True))
        r = self.go(GatherIO([gprobe(0, tools=False, node=False)], shop=None))
        self.assertEqual((r.status, 'no window' in r.detail), (TX.SKIP, True))
        r = self.go(GatherIO([gprobe(0, tools=False, node=False, bank=5)], shop=[]))
        self.assertEqual((r.status, 'gold in the bank' in r.detail), (TX.SKIP, True))

    def test_the_verdicts(self):
        a, b = gprobe(0), gprobe(0)
        self.assertEqual(TX.gather_verdict(a, gprobe(2), False, [])[0], TX.PASS)
        self.assertEqual(TX.gather_verdict(a, b, True, [])[0], TX.SKIP)
        st, text = TX.gather_verdict(a, b, False, ['Stand next to it.'])
        self.assertEqual((st, 'Stand next to it' in text), (TX.SKIP, True))
        st, text = TX.gather_verdict(a, b, False, [])
        self.assertEqual((st, 'no gather started' in text), (TX.FAIL, True))
        self.assertEqual(TX.gather_verdict(a, None, False, [])[0], TX.SKIP)

    def test_the_skips(self):
        self.assertEqual(self.go(FakeIO()).status, TX.SKIP)
        self.assertEqual(self.go(GatherIO([{'err': 'no professions'}])).status, TX.SKIP)
        r = self.go(GatherIO([gprobe(0, levelOk=False, level=5)]))
        self.assertEqual((r.status, 'open at level 20' in r.detail), (TX.SKIP, True))
        r = self.go(GatherIO([gprobe(0, node=False, guide={'mode': 'wait', 'why': 'no node within 150 tiles'})]))
        self.assertEqual((r.status, 'no node within' in r.detail), (TX.SKIP, True))
        r = self.go(GatherIO([gprobe(0, d=5)]))
        self.assertEqual((r.status, 'tiles from the node' in r.detail), (TX.SKIP, True))


class SettingsIO(ChoreIO):
    pass


def settings(rules):
    return {'action': 'settings', 'data': {'rules': rules}}


class Settings(unittest.TestCase):
    def test_pouch_rules_turn_over_and_back(self):
        a = {'orbs': True, 'runes': False, 'minRarity': 2}
        io = SettingsIO({('pouches', 'open'): settings(a), ('pouches', 'set'): [settings(dict(a, orbs=False)), settings(a)]})
        r = run(TX.check_pouch_rules(io, 'Tester Pou', 'Ninja', 100))
        self.assertEqual(r.status, TX.PASS, r.detail)
        self.assertIn('rule orbs turned True and back', r.detail)
        self.assertEqual(io.asked[1][2]['rules']['orbs'], False)
        self.assertEqual(io.asked[2][2]['rules']['orbs'], True, 'put back')
        io = SettingsIO({('pouches', 'open'): settings(a), ('pouches', 'set'): [settings(a), settings(a)]})
        self.assertEqual((run(TX.check_pouch_rules(io, 'a', 'Ninja', 1)).status), TX.FAIL)
        io = SettingsIO({('pouches', 'open'): settings(a), ('pouches', 'set'): [settings(dict(a, orbs=False, runes=True)), settings(a)]})
        r = run(TX.check_pouch_rules(io, 'a', 'Ninja', 1))
        self.assertEqual((r.status, 'changed runes as well' in r.detail), (TX.FAIL, True))
        io = SettingsIO({('pouches', 'open'): settings(a), ('pouches', 'set'): [settings(dict(a, orbs=False)), settings(dict(a, orbs=False))]})
        r = run(TX.check_pouch_rules(io, 'a', 'Ninja', 1))
        self.assertEqual((r.status, 'put back' in r.detail), (TX.FAIL, True))
        self.assertEqual(run(TX.check_pouch_rules(SettingsIO(), 'a', 'Ninja', 1)).status, TX.SKIP)
        io = SettingsIO({('pouches', 'open'): settings(a)})
        self.assertEqual(run(TX.check_pouch_rules(io, 'a', 'Ninja', 1)).status, TX.SKIP)
        self.assertEqual(io.asked[-1][:2], ('pouches', 'set'), 'the rules are put back even when no answer came')

    def test_the_auto_seller(self):
        def a(paused, unlocked, notice=None):
            return {'action': 'autoseller', 'data': {'paused': paused, 'unlocked': unlocked, 'notice': notice}}
        io = SettingsIO({('pouches', 'as_open'): a(False, False), ('pouches', 'aspause'): a(False, False, 'Needs the Auto Seller (Store).')})
        r = run(TX.check_autosell_rules(io, 'a', 'Ninja', 1))
        self.assertEqual((r.status, 'locked for the bot' in r.detail), (TX.PASS, True))
        self.assertEqual(sum(1 for x in io.asked if x[1] == 'aspause'), 1, 'a locked window is asked once')
        io = SettingsIO({('pouches', 'as_open'): a(False, False), ('pouches', 'aspause'): a(True, False, 'x')})
        self.assertEqual(run(TX.check_autosell_rules(io, 'a', 'Ninja', 1)).status, TX.FAIL)
        io = SettingsIO({('pouches', 'as_open'): a(False, False), ('pouches', 'aspause'): a(False, False)})
        self.assertEqual(run(TX.check_autosell_rules(io, 'a', 'Ninja', 1)).status, TX.FAIL)
        io = SettingsIO({('pouches', 'as_open'): a(True, True), ('pouches', 'aspause'): [a(False, True), a(True, True)]})
        r = run(TX.check_autosell_rules(io, 'a', 'Ninja', 1))
        self.assertEqual((r.status, 'switched on and back' in r.detail), (TX.PASS, True))
        self.assertEqual([x[2] for x in io.asked if x[1] == 'aspause'], [{'on': True}, {'on': False}])
        io = SettingsIO({('pouches', 'as_open'): a(True, True), ('pouches', 'aspause'): a(True, True)})
        self.assertEqual(run(TX.check_autosell_rules(io, 'a', 'Ninja', 1)).status, TX.FAIL)
        io = SettingsIO({('pouches', 'as_open'): a(True, True), ('pouches', 'aspause'): [a(False, True), a(False, True)]})
        self.assertEqual(run(TX.check_autosell_rules(io, 'a', 'Ninja', 1)).status, TX.FAIL)
        self.assertEqual(run(TX.check_autosell_rules(SettingsIO(), 'a', 'Ninja', 1)).status, TX.SKIP)

    def test_the_stash_window(self):
        def m(**d):
            return {'action': 'Stash', 'data': d}
        tabs = m(make='tabs', tabs=[{'name': 'General', 'used': 3, 'size': 30}, {'name': 'Weapons', 'used': 0, 'size': 25}], canWithdraw=True, canDeposit=True)
        r = TX.stash_verdict([m(make='addCategorys'), tabs, m(make='found', total=4)])
        self.assertEqual((r[0], '2 tab(s)' in r[1], 'search found 4' in r[1]), (TX.PASS, True, True))
        self.assertEqual(TX.stash_verdict([tabs])[0], TX.PASS)
        self.assertEqual(TX.stash_verdict([m(make='found', total=1)])[0], TX.SKIP)
        self.assertEqual(TX.stash_verdict([m(make='tabs', tabs=[])])[0], TX.FAIL)
        self.assertEqual(TX.stash_verdict([m(make='tabs', tabs=[{'name': 'G', 'used': 31, 'size': 30}])])[0], TX.FAIL)
        self.assertEqual(TX.stash_verdict([tabs, m(make='found', error='boom')])[0], TX.FAIL)
        self.assertEqual(TX.stash_verdict([tabs, m(make='found', error='short')])[0], TX.PASS)
        self.assertEqual(TX.stash_verdict(None)[0], TX.SKIP)

        class CollectIO(FakeIO):
            async def collect(self, opname, action, datas, wait=3.0):
                self.asked.append((opname, action, datas))
                return [tabs]
        io = CollectIO()
        r = run(TX.check_stash_window(io, 'a', 'Ninja', 1))
        self.assertEqual(r.status, TX.PASS)
        self.assertEqual([d['make'] for d in io.asked[0][2]], ['SendCategories', 'SendItems', 'Find'])

    def test_the_gambler_reroll(self):
        def stock(money, rerolls, ids, price=400):
            return st({'w': 3, 'money': money, 'rerolls': rerolls, 'reroll': price, 'items': [{'i': i, 'id': 2400 + i, 'p': 10} for i in ids]})
        ok = {'action': 'result', 'data': {'ok': True}}
        io = ChoreIO({('gamble', 'open'): [stock(9000, 0, [1, 2]), stock(8600, 1, [5, 6])], ('gamble', 'reroll'): ok})
        r = run(TX.check_gamble_reroll(io, 'Tester Gam', 'Ninja', 300))
        self.assertEqual(r.status, TX.PASS, r.detail)
        self.assertIn('for 400 gold', r.detail)
        self.assertIn(('gamble', 'reroll', {'w': 3}), io.asked)
        self.assertEqual(io.asked[-1][:2], ('gamble', 'close'))
        for after, want in ((stock(9000, 1, [5, 6]), 'the money did not fall'), (stock(8600, 0, [5, 6]), 'the count went'), (stock(8600, 1, [1, 2]), 'the stock is the same')):
            io = ChoreIO({('gamble', 'open'): [stock(9000, 0, [1, 2]), after], ('gamble', 'reroll'): ok})
            r = run(TX.check_gamble_reroll(io, 'a', 'Ninja', 300))
            self.assertEqual((r.status, want in r.detail), (TX.FAIL, True), r.detail)
        io = ChoreIO({('gamble', 'open'): stock(9000, 0, [1], price=None)})
        self.assertIn('no more fresh crates', run(TX.check_gamble_reroll(io, 'a', 'Ninja', 300)).detail)
        io = ChoreIO({('gamble', 'open'): stock(5200, 0, [1])})
        r = run(TX.check_gamble_reroll(io, 'a', 'Ninja', 300))
        self.assertEqual((r.status, 'keeps 5000 for supplies' in r.detail), (TX.SKIP, True))
        self.assertNotIn('reroll', [a[1] for a in io.asked])
        io = ChoreIO({('gamble', 'open'): stock(9000, 0, [1]), ('gamble', 'reroll'): {'action': 'result', 'data': {'ok': False, 'text': 'Fresh crates cost 400 gold.'}}})
        self.assertEqual(run(TX.check_gamble_reroll(io, 'a', 'Ninja', 300)).status, TX.SKIP)
        self.assertEqual(run(TX.check_gamble_reroll(ChoreIO(), 'a', 'Ninja', 300)).status, TX.SKIP)

    def test_the_keys(self):
        for k in ('spell_support', 'tales_read', 'kill_task', 'gather_walk', 'pouch_rules', 'autosell_rules', 'stash_window', 'gamble_reroll', 'ascension_walk'):
            self.assertIn(k, TX.KEYS)
            self.assertNotIn(k, TX.CLOSED_KEYS)
        self.assertEqual(len(TX.KEYS), len(set(TX.KEYS)))


# ------------------------------------------------------------------------------------------------ O657: stash moves, dummy, mount, knife, rod, kill task kills
class ToolIO(ChoreIO):
    """a mocked game for the O657 checks: scripted helper answers (lists are popped in order, the last one stays), the packets the checks send are kept"""

    def __init__(self, helper=None, replies=None, collects=None):
        super().__init__(replies=replies)
        self.script = {k: (list(v) if isinstance(v, list) else v) for k, v in (helper or {}).items()}
        self.collect_fn = collects
        self.used, self.toggled, self.stepped, self.collected, self.bought, self.shop_items = [], [], [], [], [], None
        self.use_texts, self.mount_texts = [], []

    async def helper(self, command, kind, wait=4.0):
        self.cmds = getattr(self, 'cmds', []) + [command]
        v = self.script.get(command, self.answers.get(command))
        if isinstance(v, list):
            return v.pop(0) if len(v) > 1 else v[0]
        return v(self) if callable(v) else v

    async def collect(self, opname, action, datas, wait=3.0):
        self.collected.append((opname, action, datas))
        return self.collect_fn(datas) if self.collect_fn else []

    async def use_item_with(self, client_id, pos, target_client_id, target_stackpos=0, wait=1.5):
        self.used.append((client_id, pos, target_client_id, target_stackpos))
        return list(self.use_texts)

    async def toggle_mount(self, on, wait=2.5):
        self.toggled.append(on)
        return list(self.mount_texts)

    async def step(self, dx, dy):
        self.stepped.append((dx, dy))

    async def shop_window(self, npc, wait=5.0):
        return self.shop_items

    def shop_close(self):
        pass

    async def buy(self, item_id, amount=1):
        self.bought.append(item_id)

    async def loot(self):
        pass

    def raid_mode(self, names, on, keep_flee=False):
        pass


def smsg(**d):
    return {'action': 'Stash', 'data': d}


class StashWorld:
    """the stash of a mocked server: the units of one item type, a deposit adds the dragged unit, a Redeem gives it back"""

    def __init__(self, item=777, stored=True, closed=None, lose=False, keep=False):
        self.item, self.stored, self.closed, self.lose, self.keep = item, stored, closed, lose, keep
        self.units, self.row = 0, None

    def list(self):
        ents = []
        if self.units:
            ents.append({'id': self.item, 'count': self.units, 'row': self.row} if self.row is not None else {'id': self.item, 'count': self.units})
        return [smsg(make='tabs', tabs=[{'name': 'General', 'used': 1, 'size': 30}], canWithdraw=True, canDeposit=not self.closed, depositWhy=self.closed),
                smsg(make='addItems', isFirst=True, isLast=True, items=ents)]

    def __call__(self, datas):
        out = []
        for d in datas:
            if d['make'] == 'SendItems':
                out += self.list()
            elif d['make'] == 'Stash':
                if self.closed:
                    out.append(smsg(make='access', canDeposit=False))
                elif not self.keep:
                    self.units += 1
                    self.row = 41 if self.stored else None
            elif d['make'] == 'Redeem' and not self.lose:
                self.units = max(0, self.units - 1)
                if self.stored:
                    self.row = None
        return out


def stash_io(world, back=True, give=None):
    give = give if give is not None else {'what': 'item', 'id': 777, 'clientId': 3100, 'index': 4, 'bagClientId': 2853, 'count': 1}
    bag = {'used': 3, 'rows': [{'i': 0, 'id': 7618}, {'i': 1, 'id': 777}, {'i': 2, 'id': 7620}] if back else [{'i': 0, 'id': 7618}, {'i': 1, 'id': 7620}, {'i': 2, 'id': 7618}]}
    return ToolIO(helper={'give item': give, 'bag': bag, 'path temple': {'here': True}}, collects=world)


class StashMove(unittest.TestCase):
    def go(self, io):
        return run(TX.check_stash_move(io, 'Tester Sta', 'Ninja', 100))

    def test_a_stored_item_goes_in_and_comes_out(self):
        w = StashWorld()
        io = stash_io(w)
        r = self.go(io)
        self.assertEqual(r.status, TX.PASS, r.detail)
        self.assertIn('a stored item', r.detail)
        self.assertIn('0 -> 1 -> 0', r.detail)
        dep = next(d for c in io.collected for d in c[2] if d['make'] == 'Stash')
        self.assertEqual(dep['Pos'], {'x': 65535, 'y': 64, 'z': 4, 'stackpos': 4}, 'the place in the open backpack (container 0, the slot)')
        self.assertEqual((dep['ItemId'], dep['Count'], dep['UpdateList']), (3100, 1, True))
        red = next(d for c in io.collected for d in c[2] if d['make'] == 'Redeem')
        self.assertEqual(red, {'make': 'Redeem', 'row': 41}, 'a stored item is taken out by its row')
        self.assertEqual(io.moves[-1], 'hunt', 'the bot goes back to its hunt')

    def test_a_plain_stack_is_taken_out_by_its_type(self):
        w = StashWorld(stored=False)
        io = stash_io(w)
        r = self.go(io)
        self.assertEqual(r.status, TX.PASS, r.detail)
        self.assertIn('a stack', r.detail)
        red = next(d for c in io.collected for d in c[2] if d['make'] == 'Redeem')
        self.assertEqual(red, {'make': 'Redeem', 'item': 777, 'count': 1})

    def test_the_faults(self):
        r = self.go(stash_io(StashWorld(keep=True)))
        self.assertEqual((r.status, 'expected one more' in r.detail), (TX.FAIL, True), 'the drag changed nothing and no reason came')
        r = self.go(stash_io(StashWorld(lose=True)))
        self.assertEqual((r.status, 'took item 777 out of the stash' in r.detail), (TX.FAIL, True), 'the withdrawal left the unit in the stash')
        r = self.go(stash_io(StashWorld(), back=False))
        self.assertEqual((r.status, 'the stash lost it' in r.detail), (TX.FAIL, True), 'the stash gave it up and the backpack has none')

    def test_a_closed_stash_is_a_skip(self):
        r = self.go(stash_io(StashWorld(closed='depot')))
        self.assertEqual(r.status, TX.SKIP, r.detail)
        self.assertIn('takes no deposit', r.detail)

    def test_the_skips(self):
        self.assertEqual(self.go(ToolIO()).status, TX.SKIP)
        r = self.go(ToolIO(helper={'give item': {'err': 'no room for the item'}}))
        self.assertEqual((r.status, 'no room' in r.detail), (TX.SKIP, True))
        r = self.go(ToolIO(helper={'give item': {'what': 'item'}}))
        self.assertEqual((r.status, 'no item or slot' in r.detail), (TX.SKIP, True))
        r = self.go(ToolIO(helper={'give item': {'id': 7, 'clientId': 8, 'index': 0, 'bagClientId': 1}, 'path temple': {'err': 'no path'}, 'enter temple': {'err': 'no'}}))
        self.assertEqual(r.status, TX.SKIP, r.detail)
        r = self.go(ToolIO(helper={'give item': {'id': 7, 'clientId': 8, 'index': 0, 'bagClientId': 1}, 'path temple': {'here': True}}, collects=lambda d: []))
        self.assertEqual((r.status, 'no item list' in r.detail), (TX.SKIP, True), 'a stash that sends no list')

    def test_the_readers(self):
        msgs = [smsg(make='addItems', items=[{'id': 7, 'count': 3}, {'id': 7, 'count': 2, 'row': 9}, {'id': 8, 'count': 1}])]
        self.assertEqual(TX.stash_units(msgs, 7), (5, [9]))
        self.assertEqual(TX.stash_units([], 7), (None, []))
        self.assertEqual(TX.stash_units([smsg(make='tabs')], 7), (None, []))
        self.assertIn('closed', TX.stash_closed([smsg(make='tabs', canDeposit=False, depositWhy='depot')]))
        self.assertIsNone(TX.stash_closed([smsg(make='tabs', canDeposit=True)]))


def dstate(charges=500, tries=100, level=30, pz=True, guide='use', weapon=True, dummy=True, **kw):
    out = {'enabled': True, 'pz': pz, 'level': 100, 'training': False, 'locked': False,
           'skill': {'skill': 'fist', 'level': level, 'tries': tries}, 'guide': {'mode': guide, 'why': 'x'}}
    if weapon:
        out['weapon'] = {'id': 27733, 'clientId': 7733, 'index': 2, 'charges': charges, 'kind': 'fist', 'allowed': True}
    if dummy:
        out['dummy'] = {'id': 27751, 'clientId': 7751, 'pos': {'x': 9, 'y': 8, 'z': 7}, 'd': 1, 'stackpos': 2, 'kind': 'bonus'}
    out.update(kw)
    return out


class DummyTrain(unittest.TestCase):
    def go(self, io):
        return run(TX.check_dummy_train(io, 'Tester Dum', 'Monk', 100))

    def test_the_weapon_trains_on_the_dummy(self):
        io = ToolIO(helper={'dummy state': [dstate(), dstate(494, 400)]})
        r = self.go(io)
        self.assertEqual(r.status, TX.PASS, r.detail)
        self.assertIn('6 charge(s) spent', r.detail)
        self.assertEqual(io.used, [(7733, {'x': 9, 'y': 8, 'z': 7}, 7751, 2)], 'the weapon by its client id on the dummy by its place')
        self.assertEqual(io.stepped, [(1, 0)], 'a step off the dummy ends the chain')
        self.assertNotIn('dummy clear', io.cmds, 'a weapon the bot owned is not taken')

    def test_a_granted_weapon_is_taken_back(self):
        io = ToolIO(helper={'dummy state': [dstate(weapon=False, guide='wait'), dstate(494, 400)], 'dummy give': dstate(), 'dummy clear': {'cleared': 1}})
        r = self.go(io)
        self.assertEqual(r.status, TX.PASS, r.detail)
        self.assertEqual(io.cmds.count('dummy give'), 1)
        self.assertEqual(io.cmds[-1], 'dummy clear', 'the TEST ONLY weapon goes at the end')

    def test_a_walk_to_the_dummy(self):
        io = ToolIO(helper={'dummy state': [dstate(guide='walk'), dstate(guide='use'), dstate(494, 400)], 'dummy path': {'here': True, 'dist': 0}})
        r = self.go(io)
        self.assertEqual(r.status, TX.PASS, r.detail)
        self.assertIn('dummy path', io.cmds)

    def test_the_verdicts(self):
        a = dstate()
        self.assertEqual(TX.dummy_verdict(a, dstate(494, 400))[0], TX.PASS)
        self.assertEqual(TX.dummy_verdict(a, dstate(494, 100))[0], TX.FAIL, 'charges spent and the skill did not rise')
        self.assertEqual(TX.dummy_verdict(a, dstate(500, 400))[0], TX.FAIL, 'the skill rose and no charge was spent')
        self.assertEqual(TX.dummy_verdict(a, dstate(500, 100))[0], TX.SKIP, 'nothing happened')
        self.assertEqual(TX.dummy_verdict(a, dstate(500, 5, level=31))[0], TX.FAIL, 'a level up resets the tries: still a rise, but no charge')
        self.assertEqual(TX.dummy_verdict(a, dstate(494, 5, level=31))[0], TX.PASS, 'a level up resets the tries: a rise')
        self.assertEqual(TX.dummy_verdict(a, None)[0], TX.SKIP)
        gone = dstate(weapon=False, tries=400)
        self.assertEqual(TX.dummy_verdict(a, gone)[0], TX.PASS, 'the last charge: the weapon is gone')

    def test_the_skips(self):
        self.assertEqual(self.go(ToolIO()).status, TX.SKIP)
        self.assertEqual(self.go(ToolIO(helper={'dummy state': {'err': 'no exercise weapons'}})).status, TX.SKIP)
        r = self.go(ToolIO(helper={'dummy state': dstate(locked=True)}))
        self.assertEqual((r.status, 'locked' in r.detail), (TX.SKIP, True))
        r = self.go(ToolIO(helper={'dummy state': dstate(weapon=False), 'dummy give': {'err': 'no exercise weapon for this class'}}))
        self.assertEqual((r.status, 'no exercise weapon' in r.detail), (TX.SKIP, True))
        r = self.go(ToolIO(helper={'dummy state': dstate(dummy=False, guide='wait', pz=False)}))
        self.assertEqual(r.status, TX.SKIP, r.detail)
        r = self.go(ToolIO(helper={'dummy state': dstate(pz=False)}))
        self.assertEqual((r.status, 'outside a protection zone' in r.detail), (TX.SKIP, True))
        r = self.go(ToolIO(helper={'dummy state': dstate(guide='walk'), 'dummy path': {'err': 'no path'}}))
        self.assertEqual((r.status, 'no way on foot' in r.detail), (TX.SKIP, True))
        self.assertEqual(ToolIO().stepped, [], 'no weapon use, no step')


def mstate(mounted=False, speed=220, pz=False, **kw):
    out = {'mounted': mounted, 'lookMount': 368 if mounted else 0, 'speed': speed + (20 if mounted else 0), 'baseSpeed': speed, 'pz': pz, 'granted': 7, 'current': 7}
    out.update(kw)
    return out


class MountRide(unittest.TestCase):
    def go(self, io):
        return run(TX.check_mount_ride(io, 'Tester Mnt', 'Ninja', 100))

    def test_on_and_off(self):
        io = ToolIO(helper={'mount state': [mstate(), mstate(), mstate(True), mstate()], 'mount give': mstate(), 'mount clear': mstate()})
        r = self.go(io)
        self.assertEqual(r.status, TX.PASS, r.detail)
        self.assertIn('speed 220 -> 240', r.detail)
        self.assertEqual(io.toggled, [True, False], 'the mount button on, then off')
        self.assertEqual(io.cmds[-1], 'mount clear', 'the TEST ONLY mount goes at the end')

    def test_the_verdicts(self):
        b = mstate()
        self.assertEqual(TX.mount_verdict({'before': b, 'on': mstate(True), 'off': mstate()})[0], TX.PASS)
        st, text = TX.mount_verdict({'before': b, 'on': mstate(), 'texts_on': ['Only premium accounts can use mounts.']})
        self.assertEqual((st, 'premium' in text), (TX.SKIP, True), 'the server said why')
        st, text = TX.mount_verdict({'before': b, 'on': mstate()})
        self.assertEqual((st, 'not mounted' in text), (TX.FAIL, True), 'no mount and no word')
        self.assertEqual(TX.mount_verdict({'before': b, 'on': mstate(pz=True)})[0], TX.SKIP, 'a protection zone refuses a mount')
        self.assertEqual(TX.mount_verdict({'before': b, 'on': dict(mstate(True), speed=200)})[0], TX.FAIL, 'mounted and slower')
        st, text = TX.mount_verdict({'before': b, 'on': mstate(True), 'off': mstate(True)})
        self.assertEqual((st, 'still mounted' in text), (TX.FAIL, True))
        st, text = TX.mount_verdict({'before': b, 'on': mstate(True), 'off': dict(mstate(), speed=240)})
        self.assertEqual((st, 'speed stays' in text), (TX.FAIL, True), 'dismounted and the mount speed stays')
        self.assertEqual(TX.mount_verdict({'before': b, 'on': mstate(True), 'off': None})[0], TX.SKIP)
        self.assertEqual(TX.mount_verdict({'before': b, 'on': None})[0], TX.SKIP)
        mount_without_speed = dict(mstate(True), speed=220)
        self.assertEqual(TX.mount_verdict({'before': b, 'on': mount_without_speed, 'off': mstate()})[0], TX.PASS, 'a mount that adds no speed is fine')

    def test_the_skips(self):
        self.assertEqual(self.go(ToolIO()).status, TX.SKIP)
        r = self.go(ToolIO(helper={'mount state': mstate(), 'mount give': {'err': 'the engine refused the mount: no such call'}}))
        self.assertEqual((r.status, 'refused the mount' in r.detail), (TX.SKIP, True))
        r = self.go(ToolIO(helper={'mount state': [mstate(), mstate(pz=True), mstate(pz=True)], 'mount give': mstate(), 'mount clear': mstate()}))
        self.assertEqual((r.status, 'protection zone' in r.detail), (TX.SKIP, True))
        io = ToolIO(helper={'mount state': mstate(), 'mount give': mstate(), 'mount clear': mstate()})
        io.mount_texts = ['You are exhausted.']
        r = self.go(io)
        self.assertEqual((r.status, 'exhausted' in r.detail), (TX.SKIP, True))
        self.assertEqual(io.toggled, [True], 'a refused mount is not toggled off')


def fstate(xp=0, level=1, held=0, corpse=True, tools=True, gathering=False, water=False, d=1, tries=10, flvl=5, **kw):
    out = {'enabled': True, 'levelOk': True, 'level': 100, 'minLevel': 20, 'held': held, 'gathering': gathering, 'bank': 900,
           'tools': {'delving': False, 'wortcunning': False, 'flaying': tools, 'angling': tools},
           'buy': [{'id': 5908, 'clientId': 5908, 'price': 600}, {'id': 2580, 'clientId': 2580, 'price': 150}],
           'prof': {'flaying': {'level': level, 'xp': xp, 'gathered': 0}, 'angling': {'level': level, 'xp': xp, 'gathered': 0}},
           'fishing': {'level': flvl, 'tries': tries}, 'flayGuide': {'mode': 'wait', 'why': 'no fresh corpse of a beast or reptile within 10 tiles'},
           'angleGuide': {'mode': 'wait', 'why': 'no fishable water within 30 tiles'}}
    if corpse:
        out['corpse'] = {'tag': 32, 'tier': 2, 'pos': {'x': 9, 'y': 9, 'z': 7}, 'd': d, 'clientId': 2300, 'stackpos': 1}
        out['flayGuide'] = {'mode': 'use' if d <= 1 else 'walk', 'why': 'x'}
    if water:
        out['water'] = {'pos': {'x': 4, 'y': 4, 'z': 7}, 'd': d, 'clientId': 4608, 'stackpos': 0}
        out['angleGuide'] = {'mode': 'use' if d <= 2 else 'walk', 'why': 'x'}
    out.update(kw)
    return out


class FlayAndAngle(unittest.TestCase):
    def flay(self, io):
        return run(TX.check_flay_walk(io, 'Tester Fla', 'Ninja', 100))

    def angle(self, io):
        return run(TX.check_angle_walk(io, 'Tester Ang', 'Ninja', 100))

    def test_the_knife_on_a_corpse(self):
        io = ToolIO(helper={'gather state': [fstate(), fstate(), fstate(), fstate(xp=40, held=1, corpse=False)]})
        r = self.flay(io)
        self.assertEqual(r.status, TX.PASS, r.detail)
        self.assertIn('flayed a tier 2 corpse', r.detail)
        self.assertEqual(io.used, [(5908, {'x': 9, 'y': 9, 'z': 7}, 2300, 1)], 'the knife by its client id on the corpse by its place')
        self.assertEqual(io.bought, [], 'the bot has a knife')

    def test_a_walk_and_a_knife_from_the_broker(self):
        io = ToolIO(helper={'gather state': [fstate(tools=False, d=4), fstate(tools=True, d=4), fstate(d=4), fstate(d=1), fstate(d=1), fstate(xp=40, corpse=False)],
                            'gather corpse': {'here': True, 'dist': 0}})
        io.shop_items = [{'id': 5908, 'name': 'obsidian knife', 'buy': 600}]
        r = self.flay(io)
        self.assertEqual(r.status, TX.PASS, r.detail)
        self.assertEqual(io.bought, [5908], 'the knife from the Material Broker')
        self.assertIn('gather corpse', io.cmds)

    def test_the_verdicts(self):
        a = fstate()
        self.assertEqual(TX.flay_verdict(a, fstate(xp=30), False, [])[0], TX.PASS)
        self.assertEqual(TX.flay_verdict(a, fstate(held=2), False, [])[0], TX.PASS, 'the materials rose')
        self.assertEqual(TX.flay_verdict(a, fstate(level=2), False, [])[0], TX.PASS, 'a level up')
        self.assertEqual(TX.flay_verdict(a, fstate(), True, [])[0], TX.SKIP, 'interrupted')
        st, text = TX.flay_verdict(a, fstate(), False, ['This corpse was flayed already.'])
        self.assertEqual((st, 'flayed already' in text), (TX.SKIP, True))
        self.assertEqual(TX.flay_verdict(a, fstate(corpse=False), False, [])[0], TX.SKIP, 'the corpse decayed')
        self.assertEqual(TX.flay_verdict(a, fstate(), False, [])[0], TX.FAIL, 'a fresh corpse, the knife, no word and no channel')
        self.assertEqual(TX.flay_verdict(a, None, False, [])[0], TX.SKIP)

    def test_the_flay_skips(self):
        self.assertEqual(self.flay(ToolIO()).status, TX.SKIP)
        self.assertEqual(self.flay(ToolIO(helper={'gather state': {'err': 'no professions'}})).status, TX.SKIP)
        r = self.flay(ToolIO(helper={'gather state': fstate(levelOk=False, level=5)}))
        self.assertEqual((r.status, 'open at level 20' in r.detail), (TX.SKIP, True))
        io = ToolIO(helper={'gather state': fstate(corpse=False)})
        r = self.flay(io)
        self.assertEqual((r.status, 'no fresh corpse' in r.detail), (TX.SKIP, True))
        self.assertGreaterEqual(io.t, 90, 'the bot waited at its hunt for a corpse')
        r = self.flay(ToolIO(helper={'gather state': fstate(tools=False, bank=5)}))
        self.assertEqual((r.status, 'gold in the bank' in r.detail), (TX.SKIP, True))
        io = ToolIO(helper={'gather state': fstate(tools=False)})
        io.shop_items = []
        self.assertEqual((self.flay(io).status), TX.SKIP, 'no window')
        io = ToolIO(helper={'gather state': fstate(d=3), 'gather corpse': {'err': 'no path'}})
        r = self.flay(io)
        self.assertEqual((r.status, 'no way on foot' in r.detail), (TX.SKIP, True))

    def test_the_rod_at_the_water(self):
        io = ToolIO(helper={'gather state': [fstate(water=True, d=1, corpse=False), fstate(water=True, d=1, corpse=False),
                                             fstate(water=True, d=1, corpse=False, tries=11)]})
        r = self.angle(io)
        self.assertEqual(r.status, TX.PASS, r.detail)
        self.assertIn('after 1 cast(s)', r.detail)
        self.assertEqual(io.used, [(2580, {'x': 4, 'y': 4, 'z': 7}, 4608, 0)], 'the rod by its client id at the water tile (the ground: place 0)')

    def test_casts_until_the_line_works(self):
        seq = [fstate(water=True, corpse=False)] * 4 + [fstate(water=True, corpse=False, xp=5, held=1)]
        io = ToolIO(helper={'gather state': seq})
        r = self.angle(io)
        self.assertEqual(r.status, TX.PASS, r.detail)
        self.assertEqual(len(io.used), 3, 'cast again until a result came')

    def test_the_angle_verdicts(self):
        a = fstate(water=True)
        self.assertEqual(TX.angle_verdict(a, fstate(water=True, tries=11), 1, [])[0], TX.PASS)
        self.assertEqual(TX.angle_verdict(a, fstate(water=True, flvl=6, tries=0), 1, [])[0], TX.PASS, 'a Fishing level up')
        self.assertEqual(TX.angle_verdict(a, fstate(water=True, xp=3), 2, [])[0], TX.PASS)
        self.assertEqual(TX.angle_verdict(a, fstate(water=True, held=1), 2, [])[0], TX.FAIL, 'a material and no Angling experience')
        self.assertEqual(TX.angle_verdict(a, fstate(water=True, held=1, xp=3), 2, [])[0], TX.PASS)
        st, text = TX.angle_verdict(a, fstate(water=True), 6, ['You need worms.'])
        self.assertEqual((st, 'worms' in text), (TX.SKIP, True))
        st, text = TX.angle_verdict(a, fstate(water=True), 6, [])
        self.assertEqual((st, '6 cast(s)' in text), (TX.SKIP, True))
        self.assertEqual(TX.angle_verdict(a, None, 1, [])[0], TX.SKIP)

    def test_the_angle_skips(self):
        self.assertEqual(self.angle(ToolIO()).status, TX.SKIP)
        r = self.angle(ToolIO(helper={'gather state': fstate(corpse=False)}))
        self.assertEqual((r.status, 'no fishable water' in r.detail), (TX.SKIP, True))
        r = self.angle(ToolIO(helper={'gather state': fstate(water=True, d=9, tools=True, corpse=False), 'gather water': {'err': 'no path'}}))
        self.assertEqual((r.status, 'no way on foot' in r.detail), (TX.SKIP, True))
        io = ToolIO(helper={'gather state': fstate(water=True, tools=False, corpse=False)})
        io.shop_items = [{'id': 2580, 'name': 'fishing rod', 'buy': 150}]
        r = self.angle(io)
        self.assertEqual(io.bought, [2580], 'the rod from the broker')
        self.assertEqual((r.status, 'holds none' in r.detail or r.status == TX.FAIL), (TX.FAIL, True), 'bought and the backpack holds none')


def tboard(offers=(), tasks=()):
    return {'action': 'board', 'data': {'offers': list(offers), 'tasks': list(tasks)}}


def toffer(key='h:rat', kind='hunt', required=20, state='open'):
    return {'key': key, 'kind': kind, 'label': 'Rat', 'required': required, 'state': state, 'lo': 0, 'hi': 0}


def tprobe(progress=0, kills=4, mode='fight', why='x', x=1, area=None, key='h:rat', monster='Rat'):
    return {'level': 100, 'pos': {'x': 10, 'y': 10, 'z': 7}, 'active': [{'key': key, 'kind': 'hunt', 'label': monster, 'progress': progress, 'required': 20, 'status': 0,
                                                                          'monster': monster, 'kills': kills}],
            'guide': {'mode': mode, 'goal': {'x': 10 + x, 'y': 10, 'z': 7}, 'reach': [1, 5], 'why': why, 'area': area}}


class KillTaskKills(unittest.TestCase):
    def go(self, io):
        return run(TX.check_kill_task_kills(io, 'Tester Tsk', 'Ninja', 100))

    def io(self, probes, board=None, accept=None, abandon=None):
        accepted = accept if accept is not None else tboard([toffer(state='active')], [{'key': 'h:rat', 'progress': 0, 'required': 20}])
        return ToolIO(helper={'task state': probes, 'task path': {'path': [1, 1], 'dist': 2}},
                      replies={('bestiary', 'board'): board or tboard([toffer()]), ('bestiary', 'accept'): accepted,
                               ('bestiary', 'abandon'): abandon or tboard([toffer()])})

    def test_the_counters_rise(self):
        io = self.io([tprobe(0, 4, 'walk'), tprobe(0, 4, 'walk'), tprobe(1, 5, 'fight'), tprobe(2, 6, 'fight'), tprobe(3, 7, 'fight')])
        r = self.go(io)
        self.assertEqual(r.status, TX.PASS, r.detail)
        self.assertIn('the task counter went from 0 to 3 of 20', r.detail)
        self.assertIn('4 to 7 kills', r.detail)
        self.assertTrue(any(a[1] == 'abandon' for a in io.asked), 'the task goes back')
        self.assertEqual(io.moves[-1], 'hunt')

    def test_the_bestiary_must_count_too(self):
        io = self.io([tprobe(0, 4, 'walk'), tprobe(0, 4, 'walk'), tprobe(3, 4, 'fight')])
        r = self.go(io)
        self.assertEqual((r.status, 'bestiary entry' in r.detail), (TX.FAIL, True), 'the task moved and the entry did not')

    def test_a_fight_with_no_kill_is_a_fault(self):
        io = self.io([tprobe(0, 4, 'walk'), tprobe(0, 4, 'walk')] + [tprobe(0, 4, 'fight')] * 200)
        r = self.go(io)
        self.assertEqual((r.status, 'counter moved 0' in r.detail), (TX.FAIL, True))

    def test_waiting_at_the_hunt_is_a_skip(self):
        io = self.io([tprobe(0, 4, 'walk'), tprobe(0, 4, 'walk')] + [tprobe(0, 4, 'wait', area='spawn')] * 200)
        r = self.go(io)
        self.assertEqual((r.status, 'in sight at its hunt' in r.detail), (TX.SKIP, True))

    def test_a_task_that_leaves_the_list(self):
        io = self.io([tprobe(0, 4, 'walk'), tprobe(0, 4, 'walk'), {'level': 100, 'pos': {'x': 1, 'y': 1, 'z': 7}, 'active': []}])
        r = self.go(io)
        self.assertEqual((r.status, 'left the list' in r.detail), (TX.FAIL, True))

    def test_an_offer_with_no_known_hunt_is_left_for_the_next(self):
        no = tprobe(0, 4, 'wait', why='no hunt lists Rat')
        io = self.io([no, no], board=tboard([toffer('h:rat'), toffer('f:beast', 'family', 30)]))
        r = self.go(io)
        self.assertEqual(r.status, TX.SKIP, r.detail)
        self.assertIn('no open kill task with a monster that a hunt mark lists', r.detail)
        self.assertGreaterEqual(sum(1 for a in io.asked if a[1] == 'abandon'), 1, 'each task the bot took is given back')

    def test_the_pick(self):
        board = tboard([toffer('f:a', 'family', 5), toffer('h:b', 'hunt', 30), toffer('h:c', 'hunt', 10), toffer('h:d', 'hunt', 1, 'done')])['data']
        self.assertEqual(TX.task_hunt_pick(board, 100)['key'], 'h:c', 'a single monster first, the fewest kills first')
        self.assertEqual(TX.task_hunt_pick(board, 100, {'h:c'})['key'], 'h:b')
        self.assertEqual(TX.task_hunt_pick(board, 100, {'h:b', 'h:c'})['key'], 'f:a', 'then a family')
        self.assertIsNone(TX.task_hunt_pick(board, 100, {'h:b', 'h:c', 'f:a'}))
        self.assertIsNone(TX.task_hunt_pick(None, 100))

    def test_the_skips(self):
        self.assertEqual(self.go(ToolIO()).status, TX.SKIP)
        r = self.go(self.io([tprobe()], board=tboard([])))
        self.assertEqual((r.status, 'no open kill task' in r.detail), (TX.SKIP, True))
        r = self.go(self.io([tprobe()], accept=tboard([], [])))
        self.assertEqual(r.status, TX.SKIP, 'the board did not take the task')


class NewKeys(unittest.TestCase):
    def test_the_keys(self):
        for k in ('stash_move', 'dummy_train', 'mount_ride', 'flay_walk', 'angle_walk', 'kill_task_kills'):
            self.assertIn(k, TX.KEYS)
            self.assertNotIn(k, TX.CLOSED_KEYS)
        self.assertEqual(len(TX.KEYS), len(set(TX.KEYS)))
        self.assertLess(TX.KEYS.index('stash_move'), TX.KEYS.index('rift_walk'), 'before the long rift walk')
        self.assertEqual(TX.KEYS[-1], 'ascension_walk', 'the class change stays last')


# ---------------------------------------------------------------- gear up, level gates, retreat (O658)
class GearBot:
    """what CheckRun and gear_up read of the bot: its creature id (one per login), its level, the helper's info"""

    def __init__(self, cid=500, level=300, health=100):
        self.cid, self.level, self.health = cid, level, health
        self.helper = {'info': {'potions': {'health': 2160, 'mana': 2161}}}


class GearIO(FakeIO):
    """a mocked bot with a backpack, a bank, a bag of potions, Veyra's window and the Gambler's stock. `pieces` are backpack pieces
    {i, id, cid, s, sc}, `worn` {slot: score}"""

    def __init__(self, bank=0, pieces=None, worn=None, potions=(20, 20), stock=None, old_helper=False, refuse_wear=False, level=300):
        FakeIO.__init__(self)
        self.bot = GearBot(level=level)
        self.info = {'potions': {'health': 2160, 'mana': 2161}}
        self.bank, self.pieces, self.worn = bank, list(pieces or []), dict(worn or {})
        self.potions = {'health': potions[0], 'mana': potions[1]}
        self.stock = list(stock or [])
        self.old_helper, self.refuse_wear = old_helper, refuse_wear
        self.log, self.grants, self.walked = [], [], []
        self.retreats = 0

    def found(self):
        best, gain = None, 0
        out = []
        for p in self.pieces:
            c = p['sc'] - self.worn.get(p['s'], 0)
            out.append({'i': p['i'], 'id': p['id'], 'cid': p['cid'], 's': p['s'], 'sc': p['sc'], 'chase': c})
            if c > gain:
                best, gain = p['i'], c
        return {'pieces': out, 'best': best, 'worn': [{'s': s, 'sc': v} for s, v in sorted(self.worn.items())], 'sets': {}, 'orbs': {}, 'drops': []}

    async def helper(self, command, kind, wait=4.0):
        self.log.append(command)
        if self.old_helper:
            return None
        if command == 'found':
            return self.found()
        if command == 'bag':
            return {'used': 1, 'potions': dict(self.potions)}
        if command == 'gold':
            return {'bank': self.bank}
        if command.startswith('gold to '):
            want = int(command.split()[-1])
            give = max(0, want - self.bank)
            self.bank += give
            self.grants.append(give)
            return {'bank': self.bank, 'granted': give}
        if command == 'info':
            return self.info
        return None

    async def wear(self, index, client_id, slot):
        if self.refuse_wear:
            return
        piece = next(p for p in self.pieces if p['i'] == index)
        self.worn[slot] = piece['sc']
        self.pieces.remove(piece)

    async def shop_window(self, npc, wait=5.0):
        return [{'id': 2160, 'sub': 0, 'name': 'health potion', 'buy': 45, 'sell': 0},
                {'id': 2161, 'sub': 0, 'name': 'mana potion', 'buy': 50, 'sell': 0},
                {'id': 2162, 'sub': 0, 'name': 'strong health potion', 'buy': 100, 'sell': 0}]

    async def buy(self, item_id, amount=1):
        price = 45 if item_id == 2160 else 50
        if self.bank >= price * amount:
            self.bank -= price * amount
            self.potions['health' if item_id == 2160 else 'mana'] += amount
        return []

    def shop_close(self):
        pass

    async def loot(self):
        pass

    async def request(self, opname, action, data, expect, timeout):
        self.asked.append((opname, action, data))
        if opname != 'gamble':
            return self.replies.get((opname, action))
        if action == 'close':
            return None
        if action == 'buy':
            row = next((e for e in self.stock if e['i'] == data['i']), None)
            if row and self.bank >= row['p'] and not row.get('sold'):
                self.bank -= row['p']
                row['sold'] = True
                slot = {'Helmet': 1, 'Armor': 4, 'Legs': 7, 'Boots': 8}[row['sn']]
                self.pieces.append({'i': 40 + row['i'], 'id': 9000 + row['i'], 'cid': 9000 + row['i'], 's': slot, 'sc': 10})
            return {'action': 'result', 'data': {'ok': True}}
        return {'action': 'state', 'data': {'w': 1, 'money': self.bank, 'items': [dict(e) for e in self.stock]}}


def gstock():
    return [{'i': 1, 'id': 1, 'sn': 'Helmet', 'p': 40000, 'n': 'helm'}, {'i': 2, 'id': 2, 'sn': 'Armor', 'p': 90000, 'n': 'plate'},
            {'i': 3, 'id': 3, 'sn': 'Legs', 'p': 60000, 'n': 'greaves'}, {'i': 4, 'id': 4, 'sn': 'Boots', 'p': 30000, 'n': 'boots'},
            {'i': 5, 'id': 5, 'sn': 'Helmet', 'p': 20000, 'n': 'cheap helm'}, {'i': 6, 'id': 6, 'sn': 'Weapon', 'p': 10, 'n': 'sword'},
            {'i': 7, 'id': 7, 'sn': 'Armor', 'p': 9000000, 'n': 'too dear'}]


async def walked_stub(io, name, npc, near=1):
    """chore_walk on a mock: the walk is recorded, the bot is there"""
    io.walked.append(npc)
    return None, []


class GearUp(unittest.TestCase):
    def setUp(self):
        self._walk = TX.chore_walk
        TX.chore_walk = walked_stub

    def tearDown(self):
        TX.chore_walk = self._walk

    def test_wears_buys_and_pays_with_a_named_grant(self):
        io = GearIO(bank=0, pieces=[{'i': 3, 'id': 7, 'cid': 70, 's': 1, 'sc': 25}], worn={}, stock=gstock())
        r = run(TX.gear_up(io, 'Tester Aaa', 'Warrior', 300))
        self.assertEqual((r.check, r.status), ('gear_up', TX.PASS), r.detail)
        self.assertEqual(sorted(io.worn), [1, 4, 7, 8], 'helmet, armor, legs and boots are worn')
        self.assertEqual(io.worn[1], 25, 'the piece the bot had stays on: no helmet is bought for a slot that is filled')
        self.assertEqual(io.potions, {'health': 100, 'mana': 100})
        self.assertTrue(r.fallbacks and all(f.startswith('grant ') for f in r.fallbacks), 'a short bank is topped up and the grant is named')
        self.assertIn('TEST ONLY gold grant', r.detail)
        self.assertEqual(io.walked, ['Veyra the Apothecary', 'Mordecai Ashwager'], 'on foot to both shops')
        sold = {e['sn'] for e in io.stock if e.get('sold')}
        self.assertEqual(sold, {'Armor', 'Legs', 'Boots'}, 'only for the empty slots, nothing over the cap')
        self.assertFalse(next(e for e in io.stock if e['i'] == 7).get('sold'))
        self.assertGreaterEqual(io.bank, TX.GEAR_RESERVE - 1)

    def test_no_grant_when_the_bank_is_full_enough(self):
        io = GearIO(bank=5000000, pieces=[], worn={1: 5, 4: 5, 7: 5, 8: 5}, potions=(100, 100), stock=gstock())
        r = run(TX.gear_up(io, 'Tester Aaa', 'Warrior', 300))
        self.assertEqual((r.status, r.fallbacks, io.grants), (TX.PASS, [], []), r.detail)
        self.assertEqual(io.walked, [], 'nothing to buy: no walk')
        self.assertIn('potions held (100 health, 100 mana)', r.detail)

    def test_potions_only(self):
        io = GearIO(bank=100000, worn={1: 5, 4: 5, 7: 5, 8: 5}, potions=(10, 95), stock=gstock())
        r = run(TX.gear_up(io, 'Tester Aaa', 'Warrior', 300))
        self.assertEqual(io.potions, {'health': 100, 'mana': 95}, 'mana 95 is over the 90 the bot buys under')
        self.assertEqual(io.walked, ['Veyra the Apothecary'])
        self.assertEqual(r.fallbacks, [])
        self.assertIn('bought 90 health potion(s)', r.detail)

    def test_level_under_the_gambler(self):
        io = GearIO(bank=10 ** 6, worn={}, potions=(100, 100), stock=gstock(), level=30)
        r = run(TX.gear_up(io, 'Tester Aaa', 'Warrior', 30))
        self.assertEqual(r.status, TX.SKIP)
        self.assertIn('the Gambler opens at level 40', r.detail)
        self.assertNotIn('Mordecai Ashwager', io.walked)

    def test_the_grant_limit_and_the_piece_cap(self):
        io = GearIO(bank=0, worn={1: 5, 4: 5, 7: 5}, potions=(100, 100), stock=[{'i': 8, 'id': 8, 'sn': 'Boots', 'p': TX.GEAR_PIECE_CAP + 1}])
        r = run(TX.gear_up(io, 'Tester Aaa', 'Warrior', 300))
        self.assertEqual((r.status, io.grants), (TX.PASS, []), 'a piece over the cap is left, no gold is asked for it')
        io = GearIO(bank=0, worn={1: 5, 4: 5, 7: 5}, potions=(100, 100), stock=[{'i': 9, 'id': 9, 'sn': 'Boots', 'p': TX.GEAR_GRANT_CAP + 10}])
        saved = TX.GEAR_PIECE_CAP
        TX.GEAR_PIECE_CAP = 10 ** 9
        try:
            r = run(TX.gear_up(io, 'Tester Aaa', 'Warrior', 300))
        finally:
            TX.GEAR_PIECE_CAP = saved
        self.assertEqual(io.grants, [], 'a grant over the limit of a gear-up is not asked for')
        self.assertIn('grant limit', r.detail)

    def test_an_old_helper_and_a_refused_wear(self):
        r = run(TX.gear_up(GearIO(old_helper=True), 'Tester Aaa', 'Warrior', 300))
        self.assertEqual(r.status, TX.SKIP)
        self.assertIn('no answer', r.detail)
        io = GearIO(bank=10 ** 6, pieces=[{'i': 3, 'id': 7, 'cid': 70, 's': 1, 'sc': 25}], worn={4: 5, 7: 5, 8: 5}, potions=(100, 100), stock=gstock(),
                    refuse_wear=True)
        run(TX.gear_up(io, 'Tester Aaa', 'Warrior', 300))
        self.assertIsNone(io.worn.get(1), 'the server kept the piece in the bag: it is not forced')
        self.assertLess(sum(1 for c in io.log if c == 'found'), 12, 'no endless loop on a refused piece')

    def test_the_heal_rule_is_checked(self):
        io = GearIO(bank=10 ** 6, worn={1: 5, 4: 5, 7: 5, 8: 5}, potions=(100, 100))
        r = run(TX.gear_up(io, 'Tester Aaa', 'Warrior', 300))
        self.assertIn('health potion 2160 on the heal rule', r.detail)
        io = GearIO(bank=10 ** 6, worn={1: 5, 4: 5, 7: 5, 8: 5}, potions=(100, 100))
        io.bot.helper = {}
        r = run(TX.gear_up(io, 'Tester Aaa', 'Warrior', 300))
        self.assertIn('health potion 2160 on the heal rule', r.detail, 'the helper is asked for `info` when the bot has none')


class Pure658(unittest.TestCase):
    def test_level_gate(self):
        self.assertIsNone(TX.level_gate('wsmap_walk', 1000))
        t = TX.level_gate('wsmap_walk', 999)
        self.assertIn('level 999', t)
        self.assertIn('opens at level 1000', t)
        self.assertIsNone(TX.level_gate('pets', 1), 'a check with no gate')
        self.assertIn('opens at level 100', TX.level_gate('rift_walk', 0))

    def test_the_tables(self):
        every = set(TX.KEYS) | set(TX.CLOSED_KEYS)
        self.assertLessEqual(TX.FIGHT_KEYS, every, 'a fight key that is no check')
        self.assertLessEqual(set(TX.LEVEL_GATES), TX.FIGHT_KEYS, 'a gate on a check that does not gear up')
        for key in ('closed_raid', 'rift_walk', 'pocket_walk', 'vael_walk', 'ascension_walk', 'boss_copy_walk', 'closed_dungeon'):
            self.assertIn(key, TX.FIGHT_KEYS)
        for key in ('pets', 'party', 'auto_setup', 'hideout', 'chore_pass', 'tales_read', 'closed_guards'):
            self.assertNotIn(key, TX.FIGHT_KEYS, 'a window check does not need a gear-up')

    def test_slot_gaps_and_pieces(self):
        self.assertEqual(TX.slot_gaps({'worn': [{'s': 1}, {'s': 8}, {'s': 5}]}), {4: 'Armor', 7: 'Legs'})
        self.assertEqual(TX.slot_gaps({'worn': []}), {1: 'Helmet', 4: 'Armor', 7: 'Legs', 8: 'Boots'})
        rows = gstock()
        got = TX.gear_pieces_for(rows, {'Helmet', 'Boots', 'Weapon'})
        self.assertEqual([e['i'] for e in got], [6, 5, 4], 'the cheapest of each name, by price')
        self.assertEqual(TX.gear_pieces_for(rows, {'Armor'}, 8000), [], 'nothing under the cap')
        self.assertEqual(TX.gear_pieces_for([{'i': 1, 'sn': 'Boots', 'p': 5, 'sold': True}], {'Boots'}), [], 'a sold piece is not for sale')

    def test_potion_plan_and_rows(self):
        self.assertEqual(TX.potion_plan({'potions': {'health': 20, 'mana': 95}}), (80, 0))
        self.assertEqual(TX.potion_plan({'potions': {'health': 100, 'mana': 0}}), (0, 100))
        self.assertEqual(TX.potion_plan({}), (0, 0))
        self.assertEqual(TX.potion_plan(None), (0, 0))
        hp, mp = TX.potion_rows([{'name': 'Health Potion', 'buy': 45, 'id': 1}, {'name': 'strong health potion', 'buy': 100, 'id': 2},
                                 {'name': 'mana potion', 'buy': 0, 'id': 3}])
        self.assertEqual((hp['id'], mp), (1, None), 'the plain potion by name, a row with no price is no offer')

    def test_retreat_step(self):
        pos = {'x': 10, 'y': 10, 'z': 7}
        self.assertEqual(TX.retreat_step([(7, 10), (9, 10), (10, 10)], pos), (-1, 0), 'back along the trail (west)')
        self.assertEqual(TX.retreat_step([(10, 14), (10, 12), (10, 10)], pos), (0, 1), 'south')
        self.assertEqual(TX.retreat_step([(10, 10)], pos, {'x': 14, 'y': 10}), (-1, 0), 'away from the goal when there is no trail')
        self.assertIsNone(TX.retreat_step([(10, 10)], pos))
        self.assertIsNone(TX.retreat_step([], None))

    def test_report_names_the_grants_apart(self):
        rows = [TX.Result('gear_up', 'Tester Aaa', 'Warrior', TX.PASS, 'x', ['grant 40000 gold (potions; the bank held 0)']).as_dict(),
                TX.Result('rift_walk', 'Tester Aaa', 'Warrior', TX.SKIP, 'y', ['enter npc (no path)']).as_dict()]
        text = '\n'.join(TX.report_lines(rows))
        self.assertIn('gold granted by the helper (TEST ONLY fallback of gear_up', text)
        self.assertIn('helper teleports in place of walking: 1', text, 'the grant is not counted as a teleport')

    def test_level_gates_hold_the_configs(self):
        chaos = os.path.join(ROOT, 'server', 'data', 'scripts', 'chaos')

        def first(name, pattern):
            with open(os.path.join(chaos, name), encoding='utf-8') as f:
                m = re.search(pattern, f.read(), re.S | re.M)
            self.assertIsNotNone(m, '%s: %s' % (name, pattern))
            return int(m.group(1))

        want = {
            'closed_siege': first('siege_config.lua', r'^\tminLevel = (\d+)'),
            'closed_guildboss': first('guildboss_config.lua', r'^\tminLevel = (\d+)'),
            'closed_raid': first('raid_config.lua', r'^\tminLevel = (\d+)'),
            'descent_walk': first('descent_config.lua', r'^\tminLevel = (\d+)'),
            'rift_walk': first('rift_config.lua', r'\{minLevel = (\d+), pick'),
            'nemesis_walk': first('nemesis_config.lua', r'birth = \{.*?minLevel = (\d+)'),
            'pocket_walk': first('pocketboss_config.lua', r'raid = \{minLevel = (\d+)'),
            'wsmap_walk': first('waystone_tiers_config.lua', r'tester = \{minLevel = (\d+)'),
            'trial_walk': first('trials_config.lua', r'key = "normal".*?minLevel = (\d+)'),
            'vael_walk': first('trials_config.lua', r'key = "mq".*?minLevel = (\d+)'),
            'tower_walk': first('weeklychest_config.lua', r'key = "tower", level = (\d+)'),
            'closed_dungeon': first('weeklychest_config.lua', r'key = "dungeon", level = (\d+)'),
            'dungeon_difficulty': first('bossspawns_config.lua', r'\[1\] = \{name = "[^"]+", level = (\d+)'),
            'weekly_challenge': first('weekly_challenge_config.lua', r'Hollow Vault \(level (\d+)\)'),
            'ascension_walk': first('chaos_constants.lua', r'ascension = \{\s*minLevel = (\d+)'),
        }
        for key, level in want.items():
            self.assertEqual(TX.LEVEL_GATES[key], level, '%s: the config says level %d' % (key, level))
        self.assertEqual(set(want), set(TX.LEVEL_GATES), 'a gate with no config proof')


class GatedRun(unittest.TestCase):
    def setUp(self):
        self._walk = TX.chore_walk
        TX.chore_walk = walked_stub

    def tearDown(self):
        TX.chore_walk = self._walk

    def test_a_gated_check_skips_before_it_walks_or_gears(self):
        class Quiet(FakeIO):
            async def helper(self, command, kind, wait=4.0):
                raise AssertionError('no helper call for a gated check: ' + command)

        cr = TX.CheckRun('Tester Aaa', 'Warrior', 100, only=['wsmap_walk', 'closed_raid'], closed=True)
        self.assertTrue(run(cr.run(Quiet())))
        got = {r.check: (r.status, r.detail) for r in cr.results}
        self.assertEqual(got['wsmap_walk'][0], TX.SKIP)
        self.assertIn('level 100: wsmap_walk opens at level 1000', got['wsmap_walk'][1])
        self.assertEqual(got['closed_raid'][0], TX.SKIP)
        self.assertNotIn('gear_up', got, 'no gear-up for a check the level shuts')
        self.assertTrue(cr.finished)

    def test_the_level_now_gates_not_the_level_of_the_login(self):
        io = GearIO(bank=10 ** 6, worn={1: 5, 4: 5, 7: 5, 8: 5}, potions=(100, 100), level=90)
        cr = TX.CheckRun('Tester Aaa', 'Warrior', 500, only=['tower_walk'])
        run(cr.run(io))
        self.assertEqual(cr.results[0].status, TX.SKIP)
        self.assertIn('level 90', cr.results[0].detail)

    def test_gear_up_once_per_login_before_the_first_fight_check(self):
        calls = []

        async def check_a(io, name, cls, level):
            calls.append(('a', level))
            return TX.Result('tower_walk', name, cls, TX.PASS, 'ok')

        async def check_b(io, name, cls, level):
            calls.append(('b', level))
            return TX.Result('hideout', name, cls, TX.PASS, 'ok')

        async def check_c(io, name, cls, level):
            calls.append(('c', level))
            return TX.Result('descent_walk', name, cls, TX.SKIP, 'died at the hunt')

        io = GearIO(bank=10 ** 6, worn={1: 5, 4: 5, 7: 5, 8: 5}, potions=(100, 100), level=300)
        cr = TX.CheckRun('Tester Aaa', 'Warrior', 300)
        cr.table = [('hideout', check_b, lambda c: True), ('tower_walk', check_a, lambda c: True), ('descent_walk', check_c, lambda c: True)]
        io.retreats = 2
        run(cr.run(io))
        kinds = [r.check for r in cr.results]
        self.assertEqual(kinds, ['hideout', 'gear_up', 'tower_walk', 'descent_walk'], 'the gear-up comes before the first fight check, once')
        self.assertIn('the bot retreated 2 time(s) to heal', cr.results[-1].detail, 'a SKIP after a retreat says so')
        self.assertEqual([c[1] for c in calls], [300, 300, 300])
        # a new login (a new creature id) is geared up again
        cr2 = TX.CheckRun('Tester Aaa', 'Warrior', 300)
        cr2.table = [('tower_walk', check_a, lambda c: True)]
        self.assertTrue(cr2.gear_due(io))
        run(cr2.run(io))
        self.assertFalse(cr2.gear_due(io))
        io.bot.cid = 501
        self.assertTrue(cr2.gear_due(io), 'the next login')

    def test_no_gear_flag_and_a_gear_up_that_breaks(self):
        async def check_a(io, name, cls, level):
            return TX.Result('tower_walk', name, cls, TX.PASS, 'ok')

        io = GearIO()
        cr = TX.CheckRun('Tester Aaa', 'Warrior', 300, gear=False)
        cr.table = [('tower_walk', check_a, lambda c: True)]
        run(cr.run(io))
        self.assertEqual([r.check for r in cr.results], ['tower_walk'])
        self.assertEqual(io.log, [], 'no gear-up, no helper call')

        class Breaks(GearIO):
            async def helper(self, command, kind, wait=4.0):
                raise ValueError('boom')

        cr = TX.CheckRun('Tester Aaa', 'Warrior', 300)
        cr.table = [('tower_walk', check_a, lambda c: True)]
        run(cr.run(Breaks()))
        self.assertEqual([(r.check, r.status) for r in cr.results], [('gear_up', TX.SKIP), ('tower_walk', TX.PASS)])
        self.assertIn('the gear-up broke: boom', cr.results[0].detail)

    def test_a_death_during_the_gear_up_is_not_a_result(self):
        class Dies(GearIO):
            async def helper(self, command, kind, wait=4.0):
                self.up = False
                return None

        async def check_a(io, name, cls, level):
            raise AssertionError('not reached')

        io = Dies()
        cr = TX.CheckRun('Tester Aaa', 'Warrior', 300)
        cr.table = [('tower_walk', check_a, lambda c: True)]
        self.assertFalse(run(cr.run(io)))
        self.assertEqual(cr.results, [])
        self.assertTrue(cr.gear_due(io), 'done again after the next login')


class RetreatIO(FakeIO):
    """a bot whose health a heal raises: `health` per look, `heal_now` counts"""

    def __init__(self, health=20, heals=None):
        FakeIO.__init__(self)
        self.health = health
        self.heals = heals if heals is not None else []
        self.steps = []
        self.retreats = 0

    async def heal_now(self):
        self.heals.append(self.health)
        self.health = min(100, self.health + 20)
        return 'potion'

    async def step(self, dx, dy):
        self.steps.append((dx, dy))

    async def loot(self):
        pass


class Retreat(unittest.TestCase):
    def go(self, io, pos, trail=None, goal=None, trace=None):
        r = {'name': 'Tester Aaa', 'lead': True, 'trail': list(trail or [])}
        trace = {} if trace is None else trace
        spent = run(TX.retreat_check(io, r, {'pos': pos}, trace, {'goal': goal} if goal else {}))
        return spent, r, trace

    def test_under_30_heals_steps_back_and_waits(self):
        io = RetreatIO(health=20)
        spent, r, trace = self.go(io, {'x': 10, 'y': 10, 'z': 7}, trail=[(7, 10), (9, 10)])
        self.assertGreater(spent, 0)
        self.assertEqual(io.steps, [(-1, 0)], 'one step back the way it came')
        self.assertGreaterEqual(len(io.heals), 2, 'a heal, then the waiting looks heal again until the health is over 50')
        self.assertGreaterEqual(io.health, TX.RETREAT_BACK)
        self.assertEqual((trace['retreats'], io.retreats, trace['retreat_heals'][0]), (1, 1, 'potion'))

    def test_over_30_or_unknown_health_goes_on(self):
        for h in (30, 60, 100, None):
            io = RetreatIO(health=h)
            spent, _, trace = self.go(io, {'x': 1, 'y': 1, 'z': 7})
            self.assertEqual((spent, io.steps, io.heals, trace), (0.0, [], [], {}), 'health %s' % h)

    def test_a_dead_bot_does_not_retreat_and_the_loop_is_bounded(self):
        io = RetreatIO(health=10)
        io.up = False
        self.assertEqual(self.go(io, {'x': 1, 'y': 1, 'z': 7})[0], 0.0)
        io = RetreatIO(health=10)
        trace = {'retreats': TX.RETREAT_MAX}
        self.assertEqual(self.go(io, {'x': 1, 'y': 1, 'z': 7}, trace=trace)[0], 0.0, 'at most RETREAT_MAX a loop')

    def test_a_heal_that_does_not_come_ends_the_wait(self):
        class NoHeal(RetreatIO):
            async def heal_now(self):
                self.heals.append(1)
                return None

        io = NoHeal(health=5)
        spent, _, trace = self.go(io, {'x': 1, 'y': 1, 'z': 7}, goal={'x': 4, 'y': 1})
        self.assertLessEqual(spent, TX.RETREAT_WAIT + TX.RAID_STEP + 1, 'the wait is bounded')
        self.assertEqual((io.steps, trace['retreat_heals']), ([(-1, 0)], ['none']), 'away from the goal; no heal helped')

    def test_the_play_loops_retreat_before_they_go_on(self):
        looks = {'n': 0}

        class LoopIO(RetreatIO):
            async def helper(self, command, kind, wait=4.0):
                looks['n'] += 1
                return {'pos': {'x': 10 + looks['n'], 'y': 10, 'z': 7}, 'guide': {'mode': 'wait'}}

        io = LoopIO(health=15)
        r = {'name': 'Tester Aaa', 'lead': True, 'walker': TX.RaidWalker()}
        trace = {'faults': [], 'steps': 0, 'fought': 0.0, 'stuck': None, 'died': False, 'secs': 0}
        done = {'n': 0}

        def look(s, t):
            done['n'] += 1
            return done['n'] > 3

        run(TX.chase_play(io, r, trace, {'cmd': 'nemesis', 'budget': 120.0, 'look': look}))
        self.assertEqual(trace.get('retreats'), 1, 'one retreat: the heal brought it over the line')
        self.assertTrue(io.heals)

    def test_the_four_play_loops_call_it(self):
        with open(os.path.join(HERE, 'tester_checks.py'), encoding='utf-8') as f:
            src = f.read()
        self.assertEqual(src.count('await retreat_check(io, r, s, trace, g)'), 4, 'solo_play, chase_play, boss_copy_play, bounty_play')



# ---------------------------------------------------------------- retreat in every fight loop, home, empty slots (O659)
class HomeIO(RetreatIO):
    """a bot in a content: `inside` per the state, a portal the Town Portal opens (or not), the raid's Leave button (or a refusal). Health stays
    low unless `heals`; every call is logged"""

    def __init__(self, health=15, portal=True, takes=True, leave=None, heals=False, content='rift'):
        RetreatIO.__init__(self, health=health)
        self.portal, self.takes, self.leave_reply, self.content = portal, takes, leave, content
        self.heals_on = heals
        self.inside = True
        self.cast = False
        self.walked = []
        self.log = []
        self.pos = (10, 10)

    async def heal_now(self):
        self.heals.append(self.health)
        if self.heals_on:
            self.health = min(100, self.health + 20)
            return 'potion'
        return None

    async def say(self, text):
        self.said.append(text)
        self.cast = text == TX.HOME_WORDS and self.portal

    async def step(self, dx, dy):
        self.steps.append((dx, dy))
        self.pos = (self.pos[0] + dx, self.pos[1] + dy)
        if self.cast and self.takes and self.pos == (13, 10):
            self.inside = False   # the step onto the portal took the bot out

    def state(self):
        return {'inside': self.inside, 'pos': {'x': self.pos[0], 'y': self.pos[1], 'z': 7}, 'guide': {'mode': 'wait'},
                'run': {'state': 'running', 'killed': 0, 'players': 1, 'side': 'tester', 'slot': 1}}

    async def helper(self, command, kind, wait=4.0):
        self.log.append(command)
        if command == 'journey':
            return {'portal': {'x': 13, 'y': 10, 'z': 7}, 'pos': {'x': self.pos[0], 'y': self.pos[1], 'z': 7}} if self.cast else {'zone': 'rift'}
        if command in ('rift state', 'dungeon state', 'raid state'):
            return self.state()
        return None

    async def request(self, opname, action, data, expect, timeout):
        self.asked.append((opname, action, data))
        if (opname, action) == ('raid', 'leave') and self.leave_reply is not None:
            if self.leave_reply == 'end':
                self.inside = False
            return {'action': self.leave_reply, 'data': {'text': 'Not in the middle of a boss fight.'}}
        return None


def home_stub(status=None, detail='wore 1 piece(s) (helmet)'):
    """gear_up replaced by a recorder (the restock itself is tested in GearUp)"""
    calls = []

    async def gear(io, name, cls, level):
        calls.append((name, cls, level))
        return TX.Result('gear_up', name, cls, status or TX.PASS, detail, ['grant 40000 gold (potions; the bank held 0)'])

    return gear, calls


class HomeRetreat(unittest.TestCase):
    def setUp(self):
        self._gear = TX.gear_up
        self.gear, self.calls = home_stub()
        TX.gear_up = self.gear

    def tearDown(self):
        TX.gear_up = self._gear

    def call(self, io, key='rift_walk', trace=None, pos=None, home=None):
        r = {'name': 'Tester Aaa', 'lead': True, 'trail': [(7, 10), (9, 10)]}
        trace = {'fallbacks': []} if trace is None else trace
        pos = pos or {'x': io.pos[0], 'y': io.pos[1], 'z': 7}
        h = home if home is not None else TX.home_rule(key, 'Tester Aaa', 'Warrior', 900)
        spent = run(TX.retreat_or_home(io, r, {'pos': pos}, trace, {}, h))
        return spent, trace

    def test_the_first_retreat_is_the_plain_one(self):
        io = HomeIO(heals=True)
        spent, trace = self.call(io)
        self.assertGreater(spent, 0)
        self.assertEqual((io.said, trace.get('home_log'), trace.get('gone')), ([], None, None), 'no cast, no way home')
        self.assertEqual(trace['retreats'], 1)

    def test_the_second_retreat_goes_home_by_the_town_portal_and_restocks(self):
        io = HomeIO()
        spent, trace = self.call(io, trace={'retreats': 1, 'fallbacks': []})
        self.assertEqual(io.said, [TX.HOME_WORDS], 'the Town Portal words of the journey')
        self.assertFalse(io.inside, 'the step onto the portal took the bot out')
        self.assertTrue(trace['gone'])
        self.assertEqual(io.retreats, 1)
        self.assertEqual(trace['retreats'], 2)
        self.assertEqual(self.calls, [('Tester Aaa', 'Warrior', 900)], 'the O658 gear-up ran once')
        row = trace['home_log'][0]
        self.assertEqual(row['how'], 'the Town Portal')
        self.assertIn('wore 1 piece', row['gear'])
        self.assertEqual(trace['fallbacks'], ['grant 40000 gold (potions; the bank held 0)'], 'the grant of the restock is named')
        self.assertGreaterEqual(spent, TX.HOME_CAST)
        self.assertEqual(io.steps, [(1, 0)] * 3, 'walked three tiles into the portal')

    def test_the_verdict_of_a_bot_that_stays_out_is_a_skip_with_the_count(self):
        io = HomeIO()
        _, trace = self.call(io, trace={'retreats': 1, 'fallbacks': []})
        status, text = TX.home_verdict(trace, TX.PASS, 'x')
        self.assertEqual(status, TX.SKIP)
        self.assertIn('retreated home (2 retreat(s) under 30 % health', text)
        self.assertIn('out by the Town Portal', text)
        self.assertIn('restock: pass: wore 1 piece', text)
        self.assertEqual(TX.home_verdict(trace, TX.FAIL, 'bug')[0], TX.FAIL, 'a fault stays a fault')
        self.assertEqual(TX.home_verdict({}, TX.PASS, 'x'), (TX.PASS, 'x'), 'no trip: nothing changes')

    def test_a_content_that_holds_the_bot_is_asked_once_then_the_plain_retreat_goes_on(self):
        io = HomeIO(portal=False)
        spent, trace = self.call(io, trace={'retreats': 1, 'fallbacks': []})
        self.assertEqual(io.said, [TX.HOME_WORDS], 'the cast is the probe')
        self.assertIn('holds the bot', trace['home_refused'])
        self.assertFalse(trace.get('gone'))
        self.assertTrue(io.inside)
        self.assertEqual(trace['retreats'], 2, 'the plain retreat counted')
        self.assertEqual(self.calls, [], 'no restock for a bot that did not get out')
        self.call(io, trace=trace)
        self.assertEqual(io.said, [TX.HOME_WORDS], 'not asked again in the loop')
        status, text = TX.home_verdict(trace, TX.SKIP, 'no kill')
        self.assertEqual(status, TX.SKIP)
        self.assertIn('tried to go home after 3 retreat(s)', text)

    def test_the_raid_leave_button_is_the_way_out_when_the_portal_is_refused(self):
        io = HomeIO(portal=False, leave='end')
        _, trace = self.call(io, key='closed_raid', trace={'retreats': 1, 'fallbacks': []})
        self.assertTrue(trace['gone'])
        self.assertEqual(trace['home_log'][0]['how'], "the raid's Leave button")
        self.assertIn(('raid', 'leave', {}), io.asked)
        self.assertIn('Leave button', TX.home_verdict(trace, TX.PASS, 'x')[1])

    def test_a_boss_fight_keeps_the_bot_in_the_raid(self):
        io = HomeIO(portal=False, leave='msg')
        _, trace = self.call(io, key='closed_raid', trace={'retreats': 1, 'fallbacks': []})
        self.assertFalse(trace.get('gone'))
        self.assertIn('Not in the middle of a boss fight', trace['home_refused'])

    def test_a_content_with_a_way_back_sends_the_bot_back(self):
        io = HomeIO()
        back = []

        async def come_back(io_, r, home, trace):
            back.append(home['key'])
            io_.inside = True
            return True

        home = dict(TX.home_rule('rift_walk', 'Tester Aaa', 'Warrior', 900), back=come_back)
        _, trace = self.call(io, trace={'retreats': 1, 'fallbacks': []}, home=home)
        self.assertEqual(back, ['rift_walk'])
        self.assertFalse(trace['gone'], 'the loop goes on')
        self.assertTrue(trace['home_log'][0]['back'])
        self.assertIn('went home 1 time(s) and came back (2 retreat(s))', TX.home_verdict(trace, TX.PASS, 'x')[1])

    def test_a_broken_restock_is_a_line_not_a_crash(self):
        async def boom(io, name, cls, level):
            raise RuntimeError('boom')

        TX.gear_up = boom
        io = HomeIO()
        _, trace = self.call(io, trace={'retreats': 1, 'fallbacks': []})
        self.assertTrue(trace['gone'])
        self.assertIn('the gear-up broke: boom', trace['home_log'][0]['gear'])

    def test_a_loop_with_no_rule_or_a_member_keeps_the_plain_retreat(self):
        io = HomeIO()
        _, trace = self.call(io, key='tower_walk', trace={'retreats': 1, 'fallbacks': []}, home=None)
        self.assertEqual(io.said, [])
        io = HomeIO()
        r = {'name': 'Tester Bbb', 'lead': False, 'trail': []}
        run(TX.retreat_or_home(io, r, {'pos': {'x': 1, 'y': 1, 'z': 7}}, {'retreats': 1}, {}, TX.home_rule('rift_walk', 'Tester Bbb', 'Warrior', 900)))
        self.assertEqual(io.said, [], 'only the leader (the io of the loop) goes home')

    def test_the_rules_hold_the_server(self):
        chaos = os.path.join(ROOT, 'server', 'data', 'scripts', 'chaos')
        with open(os.path.join(chaos, 'townportal_core.lua'), encoding='utf-8') as f:
            core = f.read()
        for flag in ('rift', 'dungeon', 'instance'):
            self.assertRegex(core, r'if f\.%s then' % flag, 'the Town Portal is refused in %s: the cast is the probe, not the way out' % flag)
        with open(os.path.join(chaos, 'raid.lua'), encoding='utf-8') as f:
            raid = f.read()
        self.assertIn('elseif a == "leave" then', raid, 'the raid has the Leave button')
        self.assertIn('Not in the middle of a boss fight', raid)
        self.assertEqual(set(TX.HOME_RULES), {'rift_walk', 'closed_dungeon', 'dungeon_difficulty', 'weekly_challenge', 'closed_raid'})
        self.assertTrue(set(TX.HOME_RULES) <= TX.FIGHT_KEYS)
        self.assertEqual([k for k, v in TX.HOME_RULES.items() if v['leave'] is not None], ['closed_raid'])
        self.assertEqual([k for k, v in TX.HOME_RULES.items() if v['back'] is not None], [], 'no content of the three has a way back')

    def test_the_words_are_the_journeys(self):
        import tester_journey as TJ
        self.assertEqual((TX.HOME_WORDS, TX.HOME_CAST), (TJ.TOWN_WORDS, TJ.PORTAL_CAST))

    def test_the_three_loops_are_wired(self):
        with open(os.path.join(HERE, 'tester_checks.py'), encoding='utf-8') as f:
            src = f.read()
        self.assertEqual(src.count('await retreat_or_home(io, '), 3, 'rift_walk_play, dungeon_walk_all, raid_walk_all')
        self.assertEqual(src.count('status, text = home_verdict(trace, status, text)'), 3)
        self.assertEqual(src.count('await retreat_check(io, r, s, trace, g)'), 4, 'the four loops of O658 are as they were')


def rift_trace(level=900):
    return {'faults': [], 'steps': 0, 'kills': 0, 'boss_seen': False, 'hp': None, 'fought': 0.0, 'stuck': None, 'floor': False, 'died': False,
            'secs': 0, 'came': 'foot', 'tier': 3, 'theme': None, 'fallbacks': [], 'level': level}


class HomeLoops(unittest.TestCase):
    def setUp(self):
        self._gear = TX.gear_up
        TX.gear_up, self.calls = home_stub()
        self.keep = TX.RIFT_BUDGET
        TX.RIFT_BUDGET = 90.0

    def tearDown(self):
        TX.gear_up = self._gear
        TX.RIFT_BUDGET = self.keep

    def test_the_rift_loop_goes_home_on_the_second_retreat(self):
        io = HomeIO()
        r = {'name': 'Tester Aaa', 'lead': True, 'walker': TX.RaidWalker(), 'inside': True}
        trace = rift_trace()
        res = run(TX.rift_walk_play(io, 'Tester Aaa', 'Warrior', r, trace))
        self.assertEqual(res.status, TX.SKIP, res.detail)
        self.assertIn('retreated home (2 retreat(s)', res.detail)
        self.assertEqual(trace['retreats'], 2)
        self.assertEqual(len(self.calls), 1)
        self.assertIn('grant 40000 gold', ' '.join(res.fallbacks), 'the grant of the restock is in the result')
        self.assertFalse(io.inside)

    def test_the_rift_that_holds_the_bot_says_so_and_ends_by_its_budget(self):
        io = HomeIO(portal=False)
        r = {'name': 'Tester Aaa', 'lead': True, 'walker': TX.RaidWalker(), 'inside': True}
        trace = rift_trace()
        res = run(TX.rift_walk_play(io, 'Tester Aaa', 'Warrior', r, trace))
        self.assertEqual(res.status, TX.SKIP, res.detail)
        self.assertIn('tried to go home', res.detail)
        self.assertIn('holds the bot', res.detail)
        self.assertEqual(io.said.count(TX.HOME_WORDS), 1, 'asked once')
        self.assertLessEqual(trace['retreats'], TX.RETREAT_MAX)
        self.assertEqual(self.calls, [])

    def test_the_dungeon_loop_retreats_and_goes_home(self):
        io = HomeIO(content='dungeon')
        squad = [{'name': 'Tester Aaa', 'lead': True, 'walker': TX.RaidWalker(), 'inside': True}]
        trace = {'faults': [], 'steps': 0, 'percent': 0, 'unlocked': False, 'won': False, 'fought': 0.0, 'stuck': None, 'secs': 0, 'left': '?',
                 'members': 1, 'title': 'The Hollow Vault', 'died': False, 'level': 300, 'came': 'foot', 'size': 1, 'fallbacks': [],
                 'key': 'closed_dungeon', 'difficulty': 1, 'asked': 1, 'scaled': 0, 'monsters': 0}
        res = run(TX.dungeon_walk_all(io, 'Tester Aaa', 'Warrior', squad, trace))
        self.assertEqual(res.status, TX.SKIP, res.detail)
        self.assertIn('retreated home (2 retreat(s)', res.detail)
        self.assertEqual(trace['left'], 'retreated home')
        self.assertEqual(self.calls, [('Tester Aaa', 'Warrior', 300)])

    def test_the_weekly_challenge_and_the_difficulties_use_the_same_rule(self):
        for key in ('dungeon_difficulty', 'weekly_challenge'):
            self.assertIsNotNone(TX.home_rule(key, 'Tester Aaa', 'Warrior', 900))

    def test_the_raid_loop_leaves_by_the_button_and_goes_home(self):
        io = HomeIO(portal=False, leave='end', content='raid')
        squad = [{'name': 'Tester Aaa', 'lead': True, 'walker': TX.RaidWalker(), 'inside': True}]
        trace = {'faults': [], 'reached': set(), 'killed': 0, 'bosses': 3, 'trash': 0, 'kills': 0, 'fought': 0.0, 'stuck': None, 'steps': 0,
                 'secs': 0, 'left': '?', 'members': 1, 'came': 'foot', 'fallbacks': []}
        res = run(TX.raid_walk_all(io, 'Tester Aaa', 'Warrior', {'slot': 1, 'level': 900}, squad, trace))
        self.assertEqual(res.status, TX.SKIP, res.detail)
        self.assertIn("out by the raid's Leave button", res.detail)
        self.assertEqual(self.calls, [('Tester Aaa', 'Warrior', 900)])

    def test_a_bot_with_health_over_the_line_plays_on_untouched(self):
        io = HomeIO(health=80)
        r = {'name': 'Tester Aaa', 'lead': True, 'walker': TX.RaidWalker(), 'inside': True}
        trace = rift_trace()
        run(TX.rift_walk_play(io, 'Tester Aaa', 'Warrior', r, trace))
        self.assertEqual((trace.get('retreats'), io.said, self.calls), (None, [], []))


class GearGap(unittest.TestCase):
    def setUp(self):
        self._walk = TX.chore_walk
        TX.chore_walk = walked_stub

    def tearDown(self):
        TX.chore_walk = self._walk

    def test_a_slot_the_stock_cannot_fill_is_named_with_its_reason_and_nothing_is_granted(self):
        stock = [e for e in gstock() if e['sn'] != 'Boots']   # no boots in the window for this class and level
        io = GearIO(bank=10 ** 7, pieces=[], worn={}, stock=stock, potions=(100, 100))
        r = run(TX.gear_up(io, 'Tester Aaa', 'Mage', 300))
        self.assertEqual(sorted(io.worn), [1, 4, 7], 'helmet, armor and legs bought and worn; the boots slot stays empty')
        self.assertIn('1 basic slot(s) stay empty: Boots (no Boots in the Gambler\'s stock for a level 300 Mage)', r.detail)
        self.assertEqual(io.grants, [], 'no gold grant was needed, and no gear is ever granted')

    def test_sold_and_dear_stock_say_why(self):
        self.assertIn('sold', TX.gear_gap_why([{'sn': 'Boots', 'sold': True, 'p': 5}], 'Boots', 300, 'Mage'))
        self.assertIn('costs 9000000 gold', TX.gear_gap_why([{'sn': 'Armor', 'p': 9000000}], 'Armor', 300, 'Mage'))
        self.assertIsNone(TX.gear_gap_why([{'sn': 'Helmet', 'p': 10}], 'Helmet', 300, 'Mage'))

    def test_a_low_level_names_the_gambler_level(self):
        io = GearIO(bank=10 ** 7, pieces=[], worn={}, stock=gstock(), potions=(100, 100), level=20)
        r = run(TX.gear_up(io, 'Tester Aaa', 'Mage', 20))
        self.assertIn('4 basic slot(s) stay empty', r.detail)
        self.assertIn('the Gambler opens at level 40', r.detail)

    def test_a_full_set_says_nothing_of_gaps(self):
        io = GearIO(bank=10 ** 7, pieces=[], worn={1: 5, 4: 5, 7: 5, 8: 5}, stock=gstock(), potions=(100, 100))
        r = run(TX.gear_up(io, 'Tester Aaa', 'Mage', 300))
        self.assertNotIn('stay empty', r.detail)


# ---------------------------------------------------------------- the live run fixes (O660)
class Live660Io(FakeIO):
    """a bot with a backpack of `size` slots of which `used` are taken; `do_keep` frees `keep_frees` slots a round; time passes in `t`"""

    def __init__(self, size=20, used=20, keep_frees=3):
        super().__init__()
        self.size, self.used, self.keep_frees, self.kept = size, used, keep_frees, 0
        self.clock = 'clock'
        io = self

        class Bot:
            level = 600

            async def do_keep(self, clock):
                io.kept += 1
                io.used = max(0, io.used - io.keep_frees)
                return True

        self.bot = Bot()

    async def helper(self, command, kind, wait=4.0):
        if command == 'bag':
            return {'used': self.used, 'size': self.size}
        return None


class Live660(unittest.TestCase):
    def test_a_refused_purchase_has_the_servers_words(self):
        self.assertTrue(TX.gamble_refused({'data': {'ok': False, 'text': 'You need 5 gold for that crate.'}}))
        self.assertFalse(TX.gamble_refused({'data': {'ok': True}}))
        self.assertFalse(TX.gamble_refused(None))
        self.assertEqual(TX.gamble_refusal({'data': {'ok': False, 'text': 'You need 5 gold for that crate.'}}, None), 'refused: You need 5 gold for that crate.')
        self.assertEqual(TX.gamble_refusal(None, None), 'no answer')
        self.assertIn('not marked sold', TX.gamble_refusal(None, {'items': []}))
        self.assertEqual(TX.gamble_refusal({'data': {'ok': False}}, {}), 'refused')

    def test_the_gambler_check_reads_a_refusal_as_a_skip_not_a_free_purchase(self):
        row = {'i': 14, 'p': 111100, 'id': 7, 'n': 'Cuirass', 'sn': 'Armor'}
        a = {'money': 147630, 'items': [dict(row)]}
        same = {'money': 147630, 'items': [dict(row)]}
        self.assertEqual(TX.gamble_verdict(row, a, same, 3, 3)[0], TX.FAIL, 'the old reading: the money did not fall')

        class GIO(FakeIO):
            def __init__(self):
                super().__init__()
                self.bank = 147630
                self.walked = []

            async def request(self, opname, action, data, expect, timeout):
                if action == 'open':
                    return {'action': 'state', 'data': {'w': 1, 'money': self.bank, 'items': [dict(row, sold=False)]}}
                if action == 'buy':
                    return {'action': 'result', 'data': {'ok': False, 'text': 'You are too far from Mordecai.'}}
                return None

            async def helper(self, command, kind, wait=4.0):
                return {'used': 3, 'size': 20}

        walked, TX.chore_walk = TX.chore_walk, walked_stub
        try:
            r = run(TX.check_chore_gamble(GIO(), 'Tester Aaa', 'Mage', 300))
        finally:
            TX.chore_walk = walked
        self.assertEqual(r.status, TX.SKIP, r.detail)
        self.assertIn('refused the purchase: refused: You are too far from Mordecai.', r.detail)

    def test_free_slots_and_the_keep_rounds(self):
        self.assertEqual(TX.bag_free({'used': 18, 'size': 20}), 2)
        self.assertIsNone(TX.bag_free({}))
        self.assertIsNone(TX.bag_free(None))
        io = Live660Io(size=20, used=20, keep_frees=3)
        free = run(TX.make_room(io, 'craft_orbs'))
        self.assertEqual(io.kept, 2, 'two rounds at most (ROOM_ROUNDS)')
        self.assertEqual(free, 6)
        io = Live660Io(size=20, used=18, keep_frees=3)
        self.assertEqual(run(TX.make_room(io, 'craft_orbs')), 5)
        self.assertEqual(io.kept, 1, 'one round was enough: 4 slots free')
        io = Live660Io(size=20, used=10)
        self.assertEqual(run(TX.make_room(io, 'craft_orbs')), 10)
        self.assertEqual(io.kept, 0, 'a roomy bag is left alone')
        io = Live660Io(size=20, used=20)
        self.assertIsNone(run(TX.make_room(io, 'party')), 'a check that is given nothing does not tidy')
        self.assertEqual(io.kept, 0)
        self.assertIsNone(run(TX.make_room(FakeIO(), 'craft_orbs')), 'no bag report: nothing to do')

    def test_the_keys_that_need_room_are_checks(self):
        for k in TX.ROOM_KEYS - {'gear_up'}:
            self.assertIn(k, TX.KEYS + TX.CLOSED_KEYS, k)
        self.assertIn('daily_claim', TX.ROOM_KEYS)

    def test_the_run_makes_room_before_a_craft_check_and_waits_in_town_between_checks(self):
        io = Live660Io(size=20, used=20)
        seen = []
        cr = TX.CheckRun('Tester Aaa', 'Ninja', 600, only=['craft_orbs', 'party'])

        async def fake_orbs(i, name, cls, level):
            seen.append(('craft_orbs', i.kept, list(i.moves)))
            return TX.Result('craft_orbs', name, cls, TX.PASS, 'ok')

        async def fake_party(i, name, cls, level):
            seen.append(('party', i.kept, list(i.moves)))
            return TX.Result('party', name, cls, TX.PASS, 'ok')

        cr.table = [('craft_orbs', fake_orbs, lambda c: True), ('party', fake_party, lambda c: True)]
        self.assertTrue(run(cr.run(io)))
        self.assertEqual(seen[0][1], 2, 'the bag was cleared before the check asked for items')
        self.assertEqual(seen[0][2], ['town'])
        self.assertEqual(seen[1][2], ['town', 'town'], 'in town before every check that is not a fight')

    def test_a_fight_check_is_not_pulled_back_to_town(self):
        io = Live660Io()
        self.assertFalse(run(TX.settle_in_town(io, 'rift_walk')))
        self.assertEqual(io.moves, [])
        self.assertTrue(run(TX.settle_in_town(io, 'pets')))
        self.assertEqual(io.moves, ['town'])
        self.assertFalse(run(TX.settle_in_town(type('I', (), {'alive': lambda self: True})(), 'pets')), 'an io with no go')

    def test_the_third_death_in_one_check_gives_it_up_with_the_count(self):
        class Dying(FakeIO):
            async def helper(self, command, kind, wait=4.0):
                self.up = False
                return None

        cr = TX.CheckRun('Tester Aaa', 'Beastmaster', 100, only=['beastmaster_wolf'])
        for n in (1, 2):
            io = Dying()
            self.assertFalse(run(cr.run(io)))
            self.assertEqual(cr.results, [], 'death %d: not a result yet' % n)
            self.assertFalse(cr.finished)
        io = Dying()
        self.assertFalse(run(cr.run(io)))
        self.assertEqual([(r.check, r.status) for r in cr.results], [('beastmaster_wolf', TX.SKIP)])
        self.assertIn('the bot died 3 times in this check (level 100, no gear-up)', cr.results[0].detail)
        self.assertTrue(cr.finished, 'the check is done: the next pass goes on to the next one')

    def test_a_death_count_is_per_check(self):
        cr = TX.CheckRun('Tester Aaa', 'Ninja', 100)
        io = FakeIO()
        r = TX.Result('x', 'a', 'b', TX.SKIP, 'why')
        self.assertIsNone(TX.cut_verdict(cr, 'pets', io, r))
        self.assertIsNone(TX.cut_verdict(cr, 'rift', io, r))
        self.assertIsNone(TX.cut_verdict(cr, 'pets', io, r))
        self.assertIsNotNone(TX.cut_verdict(cr, 'pets', io, r))
        self.assertIsNone(TX.cut_verdict(cr, 'rift', io, r))

    def test_the_daily_reward_that_did_not_fit_is_a_skip(self):
        io = LaneIO(DailyWorld(claim_ok=False))
        io.bot = type('B', (), {'recent': ['You do not have enough room or capacity for the reward.']})()
        r = run(TX.check_daily_claim(io, 'Tester Aaa', 'Warrior', 100))
        self.assertEqual(r.status, TX.SKIP, r.detail)
        self.assertIn('did not fit the backpack', r.detail)
        r = run(TX.check_daily_claim(LaneIO(DailyWorld(claim_ok=False)), 'Tester Aaa', 'Warrior', 100))
        self.assertEqual(r.status, TX.FAIL, 'no word of room: still a bug')
        self.assertTrue(TX.no_room_said(type('I', (), {'bot': type('B', (), {'recent': ['Your backpack is full: it went to your inbox.']})()})()))
        self.assertFalse(TX.no_room_said(object()))

    def test_the_hideout_waits_between_edits_and_between_reads(self):
        class Timed(HideoutIO):
            def __init__(self):
                super().__init__()
                self.stamps = {}

            async def request(self, opname, action, data, expect, timeout):
                self.stamps.setdefault(action, []).append(self.t)
                if action == 'place' and len(self.stamps['place']) <= 2:   # the first two tiles are refused: the next try must wait
                    return {'action': 'result', 'data': {'ok': False, 'text': 'That tile is taken.'}}
                return await super().request(opname, action, data, expect, timeout)

        io = Timed()
        r = run(TX.check_hideout(io, 'Tester Aaa', 'Warrior', 900))
        self.assertEqual(r.status, TX.PASS, r.detail)
        place = io.stamps['place']
        self.assertEqual(len(place), 3, 'two tiles refused, the third took it')
        for a, b in zip(place, place[1:]):
            self.assertGreaterEqual(b - a, 0.25, 'the window drops an edit that comes sooner than 250 ms')
        gets = io.stamps['get']
        self.assertGreaterEqual(len(gets), 3)
        for a, b in zip(gets, gets[1:]):
            self.assertGreaterEqual(b - a, 1.0, 'the window answers `get` once a second')

    def test_a_hideout_that_refuses_says_every_distinct_word(self):
        class Words(HideoutIO):
            async def request(self, opname, action, data, expect, timeout):
                if action == 'place':
                    self.tries += 1
                    text = 'At most 2 x Rug per hideout.' if self.tries > 3 else 'That tile is taken.'
                    return {'action': 'result', 'data': {'ok': False, 'text': text}}
                return await super().request(opname, action, data, expect, timeout)

        r = run(TX.check_hideout(Words(), 'Tester Aaa', 'Warrior', 900))
        self.assertEqual(r.status, TX.FAIL)
        self.assertIn('That tile is taken. | At most 2 x Rug per hideout.', r.detail)
        self.assertIn('the catalogue said 0 of 3 placed', r.detail)

    def test_a_new_room_is_read_again_after_the_bot_entered_it(self):
        class Fresh(HideoutIO):
            """a hideout never entered: the catalogue counts no decoration; entering builds the room with its two thrones (placed 2 of 2)"""

            def __init__(self):
                super().__init__()
                self.gets_inside = 0

            def catalogue(self):
                throne = {'key': 'throne', 'name': 'Throne', 'layer': 'object', 'owned': True, 'max': 2, 'placed': 2 if self.gets_inside else 0}
                rug = {'key': 'rug', 'name': 'Rug', 'layer': 'floor', 'owned': True, 'max': 3, 'placed': len([p for p in self.placed if p['key'] == 'rug'])}
                return [throne, rug]

            async def request(self, opname, action, data, expect, timeout):
                if action == 'get' and self.inside:
                    self.gets_inside += 1   # the room is built by the time of the first read inside; the answer to `enter` came before
                if action == 'place' and data['key'] == 'throne':
                    self.sent.append((action, data))
                    return {'action': 'result', 'data': {'ok': False, 'text': 'At most 2 x Throne per hideout.'}}
                return await super().request(opname, action, data, expect, timeout)

        io = Fresh()
        r = run(TX.check_hideout(io, 'Tester Aaa', 'Warrior', 900))
        self.assertEqual(r.status, TX.PASS, r.detail)
        placed = [d for a, d in io.sent if a == 'place']
        self.assertEqual({d['key'] for d in placed}, {'rug'}, 'the throne that the room holds twice is not tried: the pick was made again inside')

    def test_a_socket_without_a_gem_is_not_a_gem_in_the_socket(self):
        st = {'sockets': {'count': 2, 'max': 3, 'list': [{'id': 0, 'index': 1}, {'id': 32006, 'index': 2, 'name': 'Flawed Ruby'}]}}
        v = TX.item_view({}, st)
        self.assertEqual((v['sockets'], v['socketed']), (2, 1), 'the bench lists every socket; only the one with a gem id holds a gem')
        v = TX.item_view({}, {'sockets': {'count': 1, 'max': 1, 'list': [{'id': 0, 'index': 1}]}})
        self.assertEqual(v['socketed'], 0)

    def test_a_gem_used_up_moves_the_item_one_slot_forward(self):
        class Strict(CraftIO):
            """the bench answers only for the slot the item really sits in (the gem leaves its slot when it is used up)"""

            async def request(self, opname, action, data, expect, timeout):
                if opname == 'crafting' and action == 'select' and int(data['path']) != self.index_of('item'):
                    self.asked.append((opname, action, data))
                    return {'action': 'state', 'data': {'counts': dict(self.orbs), 'item': None}}
                if opname == 'itemTooltip' and int(data['items'][0]['pos']['z']) != self.index_of('item'):
                    self.asked.append((opname, action, data))
                    return {'action': 'tips', 'data': {'items': []}}
                return await super().request(opname, action, data, expect, timeout)

        io = Strict()
        r = run(TX.check_craft_gems(io, 'Tester Aaa', 'Mage', 300))
        self.assertEqual(r.status, TX.PASS, r.detail)
        self.assertEqual(TX.slot_after_use({'index': 0}, {'index': 1, 'path': '1'}, 1), {'index': 0, 'path': '0'})
        self.assertEqual(TX.slot_after_use({'index': 0}, {'index': 1}, 3)['index'], 1, 'a stack of three keeps its slot')
        self.assertEqual(TX.slot_after_use({'index': 5}, {'index': 1}, 1)['index'], 1, 'a slot behind the item does not move it')

    def test_a_placement_whose_answer_never_came_is_read_from_the_room(self):
        class Lost(HideoutIO):
            """the window places the decoration and its answer is lost (the live run: two thrones placed, no answer, then 'At most 2')"""

            def __init__(self):
                super().__init__()
                self.dropped = 0

            async def request(self, opname, action, data, expect, timeout):
                reply = await super().request(opname, action, data, expect, timeout)
                if action == 'place' and reply and reply['data'].get('ok') and self.dropped == 0:
                    self.dropped += 1
                    return None
                return reply

        io = Lost()
        r = run(TX.check_hideout(io, 'Tester Aaa', 'Warrior', 900))
        self.assertEqual(r.status, TX.PASS, r.detail)
        self.assertIn('the answer to the place never came: the room listed it', r.detail)
        self.assertEqual(io.placed, [], 'the one decoration is removed again, the room is as it was')
        self.assertEqual(len([1 for a, d in io.sent if a == 'place']), 1, 'the room listed it: no second decoration is placed after the lost answer')

    def test_upheaval_that_rolls_the_rarity_own_count_is_a_note_and_the_chain_goes_on(self):
        b = {'rarity': 1, 'mods': ['a', 'b'], 'bench_mods': ['a', 'b'], 'tip': 'x'}
        a = {'rarity': 1, 'mods': ['c'], 'bench_mods': ['c'], 'tip': 'y'}
        problems = TX.orb_problems('chaos', b, a)
        self.assertTrue(TX.upheaval_count_only('chaos', b, a, problems))
        self.assertIn('2 -> 1', TX.upheaval_note(b, a))
        other = dict(a, rarity=2)
        self.assertFalse(TX.upheaval_count_only('chaos', b, other, TX.orb_problems('chaos', b, other)), 'a changed rarity is a bug')
        none = dict(a, mods=[], bench_mods=[])
        self.assertFalse(TX.upheaval_count_only('chaos', b, none, TX.orb_problems('chaos', b, none)), 'no modifier left is a bug')
        more = dict(a, mods=['c', 'd', 'e'], bench_mods=['c', 'd', 'e'])
        self.assertFalse(TX.upheaval_count_only('chaos', b, more, TX.orb_problems('chaos', b, more)), 'more modifiers than before is a bug')
        self.assertFalse(TX.upheaval_count_only('annulment', b, a, ['modifiers 2 -> 1: expected one less']))

    def test_the_gem_failure_names_what_the_bench_listed(self):
        self.assertEqual(TX.sock_names({'sockets': {'list': [{'name': 'Flawed Ruby'}, {'id': 5}]}}), 'Flawed Ruby, 5')
        self.assertEqual(TX.sock_names({}), 'none')
        self.assertEqual(TX.sock_names(None), 'none')

    def test_a_rune_that_fits_the_second_spell_is_socketed_there(self):
        class Shapes(CraftIO):
            def __init__(self, fits):
                super().__init__()
                self.fits = fits
                self.supports = [{'id': 7, 'name': 'Fire Bolt', 'count': 2, 'max': 3, 'runes': []}, {'id': 8, 'name': 'Ice Wave', 'count': 2, 'max': 3, 'runes': []}]
                self.tried = []

            async def request(self, opname, action, data, expect, timeout):
                if (opname, action) == ('supports', 'socket'):
                    self.tried.append(data['spell'])
                    if data['spell'] not in self.fits:
                        return {'action': 'result', 'data': {'ok': False, 'text': 'That support does not fit this spell (single target, area).'}}
                    for sp in self.supports:
                        if sp['id'] == data['spell']:
                            sp['runes'].append({'slot': len(sp['runes']) + 1})
                    return {'action': 'result', 'data': {'ok': True, 'text': 'ok'}}
                return await super().request(opname, action, data, expect, timeout)

        io = Shapes(fits=[8])
        r = run(TX.check_craft_supports(io, 'Tester Aaa', 'Mage', 300))
        self.assertEqual(r.status, TX.PASS, r.detail)
        self.assertEqual(io.tried, [7, 8], 'the first spell refused the shape, the second took the rune')
        self.assertIn('Ice Wave', r.detail)
        io = Shapes(fits=[])
        r = run(TX.check_craft_supports(io, 'Tester Aaa', 'Mage', 300))
        self.assertEqual(r.status, TX.SKIP)
        self.assertIn('fits none of the 2 spell(s) tried', r.detail)

    def test_a_spell_with_its_open_sockets_full_is_not_free(self):
        full = {'id': 1, 'count': 2, 'max': 3, 'runes': [{'slot': 1}, {'slot': 2}]}
        free = {'id': 2, 'count': 2, 'max': 3, 'runes': [{'slot': 1}]}
        self.assertFalse(TX.spell_has_room(full), 'count is the sockets open, not the runes: 2 runes in 2 sockets is full though 2 < max 3')
        self.assertTrue(TX.spell_has_room(free))
        self.assertTrue(TX.spell_has_room({'id': 3, 'count': 1, 'max': 3}))
        self.assertFalse(TX.spell_has_room({'id': 4, 'count': 0, 'max': 3, 'runes': []}), 'a spell under the level of its first socket')
        self.assertEqual((TX.spell_runes(full), TX.spell_runes(None), TX.spell_runes({})), (2, 0, 0))
        class ById(CraftIO):
            async def request(self, opname, action, data, expect, timeout):
                if (opname, action) == ('supports', 'socket'):
                    self.asked.append((opname, action, data))
                    sp = next(s for s in self.supports if s['id'] == data['spell'])
                    sp['runes'].append({'slot': len(sp['runes']) + 1})
                    return {'action': 'result', 'data': {'ok': True, 'text': 'ok'}}
                return await super().request(opname, action, data, expect, timeout)

        io = ById()
        io.supports = [full, free]
        r = run(TX.check_craft_supports(io, 'Tester Aaa', 'Mage', 300))
        self.assertEqual(r.status, TX.PASS, r.detail)
        socketed = [x[2]['spell'] for x in io.asked if x[:2] == ('supports', 'socket')]
        self.assertEqual(socketed, [2], 'the full spell is not tried')

    def test_the_windows_are_opened_from_town(self):
        class Where(CraftIO):
            async def go(self, place):
                self.moves.append(place)
                return True

        io = Where()
        run(TX.check_craft_supports(io, 'Tester Aaa', 'Mage', 300))
        run(TX.check_craft_charms(io, 'Tester Aaa', 'Mage', 300))
        run(TX.check_craft_orbs(io, 'Tester Aaa', 'Mage', 300))
        self.assertEqual(set(io.moves), {'town'}, 'the crafting windows are opened from the temple, never from a hunt of a bot with no gear')

    def test_the_piece_cap_reaches_the_armor_of_a_level_1700_bot(self):
        self.assertGreaterEqual(TX.GEAR_PIECE_CAP, 1840000, 'the live Gambler asked 1.84M for an Armor at level 1692')
        rows = [{'i': 1, 'sn': 'Armor', 'p': 1840000}, {'i': 2, 'sn': 'Armor', 'p': 2600000}, {'i': 3, 'sn': 'Legs', 'p': 5000000}]
        got = TX.gear_pieces_for(rows, {'Armor', 'Legs'})
        self.assertEqual([r['i'] for r in got], [1], 'the cheapest Armor, and no Legs over the cap')


class Live661Io(FakeIO):
    """a mocked bot for O661: scripted queue replies in order, the helper answers by command"""

    def __init__(self, replies_in_order=None, **kw):
        super().__init__(**kw)
        self.queue_replies = list(replies_in_order or [])

    async def request(self, opname, action, data, expect, timeout):
        self.asked.append((opname, action, data))
        if (opname, action) == ('dungeons', 'queue') and self.queue_replies:
            return self.queue_replies.pop(0)
        return self.replies.get((opname, action))


def queue_answer(text, joined=False):
    return {'action': 'queue', 'data': {'id': 4, 'joined': joined, 'text': text}}


class Live661(unittest.TestCase):
    """O661: the passive tree spent, the rift tier of the warning, a dungeon queue out of a fight, the pocket boss of the bot's level, the way to a
    bounty hunt"""

    # ---- the passive tree
    def test_the_gear_up_spends_the_free_passive_points_on_the_defense_build(self):
        io = Live661Io(replies={('passivetree', 'autobuildApply'): {'action': 'autobuildApplied', 'data': {'message': 'Auto build: 158 nodes added'}}})
        g = {'notes': []}
        self.assertTrue(run(TX.gear_tree(io, g)))
        self.assertEqual(io.asked[0], ('passivetree', 'autobuildApply', {'build': 'focus_defense', 'mode': 'add', 'cost': 0}),
                         'the free "add" mode of the Auto build window: it takes nothing back and costs nothing')
        self.assertIn('158 nodes added', g['tree'])
        self.assertEqual(g['notes'], [])

    def test_no_free_point_is_no_fault_a_refusal_is_a_note(self):
        none = {'action': 'autobuildError', 'data': {'message': 'Nothing would change: you already have this build, or you have no free points.'}}
        g = {'notes': []}
        self.assertFalse(run(TX.gear_tree(Live661Io(replies={('passivetree', 'autobuildApply'): none}), g)))
        self.assertEqual(g['notes'], [], 'a tree that is spent already is not a fault')
        odd = {'action': 'autobuildError', 'data': {'message': 'That build is not for your class.'}}
        g = {'notes': []}
        run(TX.gear_tree(Live661Io(replies={('passivetree', 'autobuildApply'): odd}), g))
        self.assertEqual(len(g['notes']), 1)
        self.assertIn('not for your class', g['notes'][0], "the server's own words")

    def test_the_gear_up_result_names_the_tree(self):
        class Io(FakeIO):
            async def helper(self, command, kind, wait=4.0):
                return {'potions': {'health': 266, 'mana': 100}} if command in ('bag', 'info') else None

        io = Io(replies={('passivetree', 'autobuildApply'): {'action': 'autobuildApplied', 'data': {'message': 'Auto build: 12 nodes added'}}})
        r = run(TX.gear_up(io, 'Tester Aaa', 'Mage', 300))
        self.assertIn('passive tree focus_defense: Auto build: 12 nodes added', r.detail)

    def test_the_defense_focus_build_exists_in_the_server(self):
        with open(os.path.join(ROOT, 'server', 'data', 'scripts', 'chaos', 'passive_builds_config.lua'), encoding='utf-8') as f:
            text = f.read()
        self.assertIn('{key = "defense", name = "Defense"', text, 'the focus theme the build id is made from')
        with open(os.path.join(ROOT, 'server', 'data', 'scripts', 'chaos', 'passive_builds_core.lua'), encoding='utf-8') as f:
            core = f.read()
        self.assertIn('themes["focus_" .. theme.key]', core, 'the id of a focus build is focus_<key>')

    # ---- the rift tier
    def test_the_rift_tier_follows_the_level_warning(self):
        with open(os.path.join(ROOT, 'server', 'data', 'scripts', 'chaos', 'rift_config.lua'), encoding='utf-8') as f:
            m = re.search(r'levels = \{([0-9, ]+)\}', f.read())
        self.assertIsNotNone(m)
        self.assertEqual(TX.RIFT_WARN_LEVELS, tuple(int(v) for v in m.group(1).split(',')), 'the warn levels of rift_config.lua')
        self.assertEqual(TX.rift_tier_for(100), 1)
        self.assertEqual(TX.rift_tier_for(179), 1)
        self.assertEqual(TX.rift_tier_for(180), 1)
        self.assertEqual(TX.rift_tier_for(240), 2)
        self.assertEqual(TX.rift_tier_for(700), 6)
        self.assertEqual(TX.rift_tier_for(800), 8)
        self.assertEqual(TX.rift_tier_for(1000), 14)
        self.assertEqual(TX.rift_tier_for(2000), 15)
        self.assertIsNone(TX.rift_tier_for(None))
        self.assertEqual(TX.rift_key_command(800), 'rift key 8')
        self.assertEqual(TX.rift_key_command('x'), 'rift key')

    def test_the_tier_is_one_the_level_opens(self):
        chaos = os.path.join(ROOT, 'server', 'data', 'scripts', 'chaos', 'rift_config.lua')
        with open(chaos, encoding='utf-8') as f:
            text = f.read()
        mins = [int(v) for v in re.findall(r'\{minLevel = (\d+), pick', text)]
        step = int(re.search(r'minLevelStep = (\d+)', text).group(1))
        for level in range(100, 2100, 5):
            t = TX.rift_tier_for(level)
            need = mins[t - 1] if t <= len(mins) else mins[-1] + (t - len(mins)) * step
            self.assertLessEqual(need, level, 'level %d: the key of tier %d needs level %d' % (level, t, need))

    def test_the_rift_check_asks_for_the_tier_of_the_warning(self):
        class Io(FakeIO):
            def __init__(self):
                super().__init__()
                self.cmds = []

            def raid_mode(self, *a, **k):
                pass

            async def helper(self, command, kind, wait=4.0):
                self.cmds.append(command)
                if command == 'rift state':
                    return {'inside': False, 'tier': 8, 'level': 700, 'pz': True}
                if command == 'rift key 6':
                    return {'err': 'stop here'}
                return {}

        io = Io()
        r = run(TX.check_rift_walk(io, 'Tester Aaa', 'Mage', 700))
        self.assertIn('rift key 6', io.cmds, 'a level 700 bot (opens tier 8, warned at 760) takes the key of tier 6')
        self.assertNotIn('rift key', io.cmds)
        self.assertIn('stop here', r.detail)

    # ---- the dungeon queue
    def test_a_queue_refused_in_a_fight_is_asked_again(self):
        io = Live661Io([queue_answer('You cannot enter a dungeon while you are in a fight.'),
                        queue_answer('You cannot enter a dungeon while you are in a fight.'), queue_answer('', joined=True)])
        reply, waited = run(TX.queue_dungeon_calm(io, {'lead': True, 'name': 'Tester Aaa'}, {'id': 4, 'difficulty': 1}))
        self.assertTrue(reply['data']['joined'])
        self.assertEqual(len([a for a in io.asked if a[1] == 'queue']), 3)
        self.assertEqual(waited, 2 * TX.DUNGEON_CALM_GAP)
        self.assertEqual(io.t, 2 * TX.DUNGEON_CALM_GAP, 'the bot stood still between the asks')

    def test_the_refusal_words_come_as_a_text_line_not_in_the_answer(self):
        """the live answer is {id, joined: false} and the words arrive as the cancel message: the bot reads them from its last text lines"""
        class Bot:
            recent = []

        class Io(Live661Io):
            def __init__(self, replies):
                super().__init__(replies)
                self.bot = Bot()

            async def request(self, opname, action, data, expect, timeout):
                reply = await super().request(opname, action, data, expect, timeout)
                if reply is not None and not reply['data']['joined']:
                    self.bot.recent = ['You cannot enter a dungeon while you are in a fight.']
                else:
                    self.bot.recent = []
                return reply

        no = {'action': 'queue', 'data': {'id': 4, 'joined': False}}
        yes = {'action': 'queue', 'data': {'id': 4, 'joined': True}}
        io = Io([no, no, yes])
        reply, waited = run(TX.queue_dungeon_calm(io, {'lead': True, 'name': 'Tester Aaa'}, {'id': 4}))
        self.assertTrue(reply['data']['joined'])
        self.assertEqual(waited, 2 * TX.DUNGEON_CALM_GAP)

    def test_another_refusal_is_not_asked_again(self):
        io = Live661Io([queue_answer('You need level 150.')])
        reply, waited = run(TX.queue_dungeon_calm(io, {'lead': True, 'name': 'Tester Aaa'}, {'id': 4}))
        self.assertEqual(waited, 0)
        self.assertEqual(TX.queue_refusal(reply), 'You need level 150.')

    def test_a_fight_that_does_not_end_gives_up_after_a_step_back_to_the_temple(self):
        io = Live661Io([queue_answer('You cannot enter a dungeon while you are in a fight.')] * 40)
        walks = []

        async def walked(io_, r, kind, n=None, near=1):
            walks.append((kind, r['name'], io_.t))
            return 'foot', None, None

        old = TX.walk_to_place
        TX.walk_to_place = walked
        try:
            reply, waited = run(TX.queue_dungeon_calm(io, {'lead': True, 'name': 'Tester Aaa'}, {'id': 4}))
        finally:
            TX.walk_to_place = old
        self.assertEqual(walks, [('temple', 'Tester Aaa', TX.DUNGEON_CALM_TEMPLE)], 'one walk back to the temple, after the first refusals')
        self.assertGreaterEqual(waited, TX.DUNGEON_CALM_WAIT)
        self.assertIn(TX.IN_A_FIGHT, TX.queue_refusal(reply))

    def test_the_refusal_text_is_the_servers(self):
        with open(os.path.join(ROOT, 'server', 'data', 'scripts', 'chaos', 'dungeons.lua'), encoding='utf-8') as f:
            self.assertIn('You cannot enter a dungeon ' + TX.IN_A_FIGHT + '.', f.read())
        self.assertEqual(TX.queue_refusal(None), '')
        self.assertEqual(TX.queue_refusal(queue_answer('', joined=True)), '')

    # ---- the pocket boss
    def test_a_pocket_boss_above_the_level_is_not_played(self):
        self.assertIsNone(TX.pocket_unfit({'name': 'Raid A', 'bl': 600}, 700))
        self.assertIsNone(TX.pocket_unfit({'name': 'Old helper'}, 700), 'a row with no boss level (an old probe) is played as before')
        text = TX.pocket_unfit({'name': "Ul'thazmor", 'bl': 2400}, 631)
        self.assertIn('level 631', text)
        self.assertIn("Ul'thazmor", text)

    def test_the_check_skips_a_boss_above_the_bot_before_it_walks(self):
        class Io(FakeIO):
            async def helper(self, command, kind, wait=4.0):
                return {'level': 631, 'enabled': True, 'free': 12, 'reserve': 4, 'bosses': [{'key': 'raid_ul', 'name': "Ul'thazmor", 'bl': 2400, 'level': 150}]}

        io = Io()
        r = run(TX.check_pocket_walk(io, 'Tester Aaa', 'Mage', 631))
        self.assertEqual(r.status, TX.SKIP)
        self.assertEqual(io.moves, [], 'no walk, no charge spent')

    # ---- the way to a bounty hunt
    def test_far_goals_are_not_walked(self):
        pos = {'x': 32957, 'y': 32076, 'z': 7}
        self.assertTrue(TX.bounty_far(pos, {'x': 33007, 'y': 33360, 'z': 7}))
        self.assertFalse(TX.bounty_far(pos, {'x': 32990, 'y': 32100, 'z': 7}))
        self.assertFalse(TX.bounty_far(None, {'x': 1, 'y': 1, 'z': 7}))
        self.assertEqual(TX.travel_command({'x': 33007, 'y': 33360, 'z': 7}), 'journey near 33007 33360 7')

    def test_no_teleport_to_the_hunt_is_a_skip_with_the_reason(self):
        class Io(FakeIO):
            async def helper(self, command, kind, wait=4.0):
                if command.startswith('journey near'):
                    return {'zone': 'temple', 'pos': {'x': 32957, 'y': 32076, 'z': 7},
                            'pick': {'id': 'h1', 'n': 'Wasp Nest', 't': {'x': 1, 'y': 1, 'z': 7}, 'a': {'x': 31000, 'y': 31000, 'z': 7}}}
                return None

        trace, fb = {'level': 600, 'steps': 0}, []
        spent = run(TX.bounty_travel_leg(Io(), {'name': 'Tester Aaa', 'lead': True}, {'x': 33007, 'y': 33360, 'z': 7}, trace, fb))
        self.assertGreaterEqual(spent, 0)
        self.assertEqual(trace['travel'], 'no way')
        self.assertIn('Wasp Nest', trace['no_way'])
        self.assertIn('tiles away', trace['no_way'])
        status, text = TX.bounty_walk_verdict(dict(trace, faults=[], name='Rotworm', need=3, secs=5, fallbacks=fb, progress=0, base=0))
        self.assertEqual(status, TX.SKIP)
        self.assertIn('has no way there', text)

    def test_no_hunt_open_to_the_level_is_a_skip(self):
        class Io(FakeIO):
            async def helper(self, command, kind, wait=4.0):
                return {'zone': 'temple', 'pos': {'x': 32957, 'y': 32076, 'z': 7}, 'pick': None}

        trace, fb = {'level': 600, 'steps': 0}, []
        run(TX.bounty_travel_leg(Io(), {'name': 'Tester Aaa', 'lead': True}, {'x': 33007, 'y': 33360, 'z': 7}, trace, fb))
        self.assertEqual(trace['travel'], 'no way')
        self.assertIn('no hunt of the teleport room is open to level 600', trace['no_way'])

    def test_the_arrival_at_the_hunt_ends_the_travel(self):
        class Io(FakeIO):
            def __init__(self):
                super().__init__()
                self.zone = 'temple'
                self.steps = []

            async def helper(self, command, kind, wait=4.0):
                pick = {'id': 'h1', 'n': 'Wasp Nest', 't': {'x': 5, 'y': 5, 'z': 7}, 'a': {'x': 33000, 'y': 33350, 'z': 7}}
                if command.startswith('journey near'):
                    return {'zone': self.zone, 'pos': {'x': 32957, 'y': 32076, 'z': 7}, 'pick': pick}
                return None

        io = Io()
        calls = []

        class Boom(Exception):
            pass

        orig = TX.bounty_travel_leg

        # the legs themselves are the journey's (tester_journey_test.py); here the arrival flips the zone after the first act
        import tester_journey as TJ
        old_act = TJ.Journey.act

        async def act(self, io_, s):
            calls.append(s['zone'])
            self.target = s['pick']
            io.zone = 'other'

        TJ.Journey.act = act
        try:
            trace, fb = {'level': 600, 'steps': 0}, []
            run(orig(io, {'name': 'Tester Aaa', 'lead': True}, {'x': 33007, 'y': 33360, 'z': 7}, trace, fb))
        finally:
            TJ.Journey.act = old_act
        self.assertEqual(trace['travel'], 'foot')
        self.assertEqual(calls, ['temple'])

    def test_the_contract_whose_hunt_a_teleport_leads_to_is_taken(self):
        arrivals = {(100, 100, 7): {'x': 105, 'y': 98, 'z': 7}, (900, 900, 7): {'x': 100, 'y': 100, 'z': 7}}

        class Io(FakeIO):
            async def helper(self, command, kind, wait=4.0):
                x, y, z = (int(v) for v in command.split()[2:5])
                return {'zone': 'temple', 'pick': {'id': 'h', 'n': 'Hunt %d' % x, 'a': arrivals[(x, y, z)]}}

        a = {'level': 600, 'candidates': [{'key': 'far', 'name': 'Far One', 'mark': {'x': 900, 'y': 900, 'z': 7}},
                                          {'key': 'near', 'name': 'Near One', 'mark': {'x': 100, 'y': 100, 'z': 7}}, {'key': 'nomark', 'name': 'None'}]}
        row, why = run(TX.bounty_near_row(Io(), a))
        self.assertIsNone(why)
        self.assertEqual(row['key'], 'near')
        self.assertEqual(row['arrival'], 5)
        a['candidates'] = a['candidates'][:1]
        row, why = run(TX.bounty_near_row(Io(), a))
        self.assertIsNone(row)
        self.assertIn('none of the 1 hunt contract(s)', why)
        self.assertIn('Far One', why)
        row, why = run(TX.bounty_near_row(FakeIO(), {'level': 9, 'candidates': a['candidates']}))
        self.assertIn('no hunt teleport is open to level 9', why)

    def test_the_helper_part_is_in_the_helper_files(self):
        with open(os.path.join(HERE, 'tester_helper_core.lua'), encoding='utf-8') as f:
            core = f.read()
        self.assertIn('function H.journeyNear', core)
        self.assertIn('[near X Y Z]', core)
        with open(os.path.join(HERE, 'tester_helper.lua'), encoding='utf-8') as f:
            self.assertIn('near = opts.near', f.read())


if __name__ == '__main__':
    unittest.main()
