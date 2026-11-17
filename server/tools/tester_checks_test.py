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
        self.supports = [{'id': 7, 'name': 'Fire Bolt', 'count': 0, 'max': 2}]
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
                'sockets': {'count': it['sockets'], 'max': it['max'], 'list': [{}] * it['socketed']}}}}
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
            return {'action': 'state', 'data': {'spells': [dict(s) for s in self.supports]}}
        if opname == 'supports' and action == 'socket':
            if self.refuse:
                return {'action': 'result', 'data': {'ok': False, 'text': self.refuse}}
            if self.bug != 'supports':
                self.supports[0]['count'] += 1
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
        if command == 'rift key':
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
        self.assertLess(cmds.index('path temple'), cmds.index('rift key'))
        self.assertLess(cmds.index('rift key'), cmds.index('rift path'))

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

if __name__ == '__main__':
    unittest.main()
