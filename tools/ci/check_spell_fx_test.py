#!/usr/bin/env python3
"""Tests of tools/ci/check_spell_fx.py: the rule on synthetic data, the committed tables, and two real probe runs
(the effects pass of O457: Dawnpiercer shows the gold comet and no longer the blue arcane blast).

    python3 -I tools/ci/check_spell_fx_test.py
"""
import os
import shutil
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import check_spell_fx as c  # noqa: E402


class Rule(unittest.TestCase):
    TAGS = {1: ('fire_thing', 'fire'), 2: ('ice_thing', 'ice'), 3: ('smoke', 'any'), 4: ('holy_thing', 'holy')}
    SPELLS = {10: ('Test Fire', 'fire'), 11: ('Test Holy', 'holy')}

    def test_same_element_and_any_pass(self):
        errors, used = c.violations({10: {1, 3}}, self.SPELLS, self.TAGS, {})
        self.assertEqual(errors, [])
        self.assertEqual(used, set())

    def test_another_element_fails(self):
        errors, _ = c.violations({10: {2}}, self.SPELLS, self.TAGS, {})
        self.assertEqual(len(errors), 1)
        self.assertIn('Test Fire', errors[0])
        self.assertIn('ice', errors[0])

    def test_old_holy_blast_would_fail(self):
        # the blue arcane blast 810 on a holy spell was the first row of the review
        tags = dict(self.TAGS)
        tags[810] = ('blast_magical', 'arcane')
        errors, _ = c.violations({11: {810}}, self.SPELLS, tags, {})
        self.assertEqual(len(errors), 1)

    def test_allow_row_passes_and_is_used(self):
        errors, used = c.violations({11: {1}}, self.SPELLS, self.TAGS, {(11, 1): 'a holy fire'})
        self.assertEqual(errors, [])
        self.assertEqual(used, {(11, 1)})

    def test_untagged_effect_fails(self):
        errors, _ = c.violations({10: {99}}, self.SPELLS, self.TAGS, {})
        self.assertEqual(len(errors), 1)
        self.assertIn('no element tag', errors[0])

    def test_spell_without_element_is_skipped(self):
        errors, _ = c.violations({77: {2}}, self.SPELLS, self.TAGS, {})
        self.assertEqual(errors, [])

    def test_cancel_puff_is_not_a_cast_effect(self):
        lines = ['ME\t3\t0\t0\t0\t0\t0\t', 'CANCEL\tno chi', 'ME\t3\t0\t0\t0\t0\t0\t', 'ME\t12\t0\t0\t0\t0\t0\t']
        self.assertEqual(c.parse_probe(lines), [3, 12])


class Tables(unittest.TestCase):
    def test_tags(self):
        tags = c.load_tags()
        self.assertGreater(len(tags), 80)
        for eid, (name, el) in tags.items():
            self.assertTrue(el == c.ANY or el in c.ELEMENTS, 'effect %d: element %s' % (eid, el))
            self.assertTrue(name, 'effect %d has a name' % eid)

    def test_allow_rows_are_sound(self):
        tags = c.load_tags()
        elements = c.spell_elements()
        for (sid, eid), reason in c.load_allow().items():
            self.assertIn(sid, elements)
            self.assertIn(eid, tags)
            self.assertGreater(len(reason.strip()), 10)
            self.assertFalse(c.element_ok(elements[sid][1], tags[eid][1]), 'row %d / %d allows what the rule allows' % (sid, eid))

    def test_spelldata_has_elements(self):
        elements = c.spell_elements()
        self.assertGreater(len(elements), 80)
        self.assertEqual(elements[214][0], 'Dawnpiercer')
        self.assertEqual(elements[214][1], 'holy')

    def test_chaos_spells_read(self):
        spells = c.chaos_spells()
        self.assertGreater(len(spells), 150)
        by = {s['id']: s for s in spells}
        self.assertEqual(by[214]['name'], 'Dawnpiercer')
        self.assertIn('Ranger', by[214]['vocs'])


@unittest.skipIf(shutil.which('lua5.3') is None, 'lua5.3 not installed')
class Probe(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.root = c.make_root()

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.root, ignore_errors=True)

    def spell(self, sid):
        return next(s for s in c.chaos_spells() if s['id'] == sid)

    def test_dawnpiercer_shows_the_gold_comet(self):
        ids = c.probe_spell(self.root, self.spell(214))
        self.assertIn(4293, ids)
        self.assertNotIn(810, ids)

    def test_crypt_collapse_has_no_fire_blast(self):
        ids = c.probe_spell(self.root, self.spell(119))
        self.assertNotIn(809, ids)
        self.assertIn(4328, ids)

    def test_whirling_heel_is_not_holy(self):
        ids = c.probe_spell(self.root, self.spell(65))
        self.assertNotIn(641, ids)


if __name__ == '__main__':
    unittest.main()
