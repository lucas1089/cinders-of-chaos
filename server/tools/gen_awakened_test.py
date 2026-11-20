#!/usr/bin/env python3
"""Tests of gen_awakened.py (O686 phase 7): the file is what the tool writes, one row for each spell with Forms, the design's four examples
verbatim, every signature inside the band by the Lua value and by the tool's own mirror of it, the kinds follow the shape of the spell, names
unique in both languages, the refusals (a missing name, a name row of another spell)."""
import csv
import os
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gen_awakened as G  # noqa: E402

ROWS = None
CFG = None
VALUES = None


def setUpModule():
    global ROWS, CFG, VALUES
    ROWS = G.generate()
    CFG, VALUES = G.lua_numbers()


class Written(unittest.TestCase):
    def test_the_committed_file_is_what_the_tool_writes(self):
        with open(G.OUT, encoding='utf-8', newline='') as f:
            self.assertEqual(f.read(), G.render(ROWS))

    def test_one_row_for_each_spell_with_forms(self):
        forms = G.read_forms()
        self.assertEqual([r['id'] for r in ROWS], sorted(forms))
        self.assertEqual(len(ROWS), 149)
        for r in ROWS:
            self.assertEqual(r['spell'], forms[r['id']][0])
            self.assertEqual(r['role'], forms[r['id']][1])

    def test_the_columns(self):
        with open(G.OUT, newline='', encoding='utf-8') as f:
            self.assertEqual(csv.DictReader(f).fieldnames, G.COLUMNS)

    def test_deterministic(self):
        self.assertEqual(G.render(G.generate()), G.render(ROWS))


class Examples(unittest.TestCase):
    """docs/SPELL_UPGRADES.md 3.3, word for word"""

    def row(self, sid):
        return next(r for r in ROWS if r['id'] == sid)

    def test_doomtide(self):
        r = self.row(206)
        self.assertEqual((r['name_en'], r['kind']), ('Cataclysm of Cinders', 'PULSE'))
        o = G.parse_over(r['over'])['PULSE']
        self.assertEqual((o['secs'], o['pulses'], o['pct'], o['minHit'], o['mana']), (6, 3, 0.4, 3, 0.03))

    def test_final_verdict(self):
        r = self.row(218)
        self.assertEqual((r['name_en'], r['kind']), ('Verdict Unbound', 'LINE+MARK'))
        o = G.parse_over(r['over'])
        self.assertEqual((o['LINE']['len'], o['MARK']['secs'], o['MARK']['pct']), (6, 6, 0.5))

    def test_judgment_of_iron(self):
        r = self.row(148)
        self.assertEqual((r['name_en'], r['kind']), ('Iron Reckoning', 'RINGS+CDCUT'))
        o = G.parse_over(r['over'])
        self.assertEqual((o['RINGS']['rings'], o['CDCUT']['window'], o['CDCUT']['cut'], o['CDCUT']['cap']), (3, 8, 1, 5))

    def test_mirror_mend(self):
        r = self.row(96)
        self.assertEqual((r['name_en'], r['kind']), ('Hall of Mends', 'REFLECT+SHIELD'))
        o = G.parse_over(r['over'])
        self.assertEqual((o['REFLECT']['radius'], o['REFLECT']['pct'], o['SHIELD']['pct'], o['SHIELD']['secs']), (4, 0.5, 0.03, 4))


class Values(unittest.TestCase):
    def test_every_row_is_inside_the_band(self):
        lo, hi = float(CFG['bandMin']), float(CFG['bandMax'])
        for sid, (v, out, util, kind) in VALUES.items():
            self.assertTrue(lo <= v <= hi, '%d is worth %s' % (sid, v))

    def test_the_mean_is_the_target(self):
        mean = sum(v[0] for v in VALUES.values()) / len(VALUES)
        self.assertAlmostEqual(mean, float(CFG['target']), delta=0.005)

    def test_the_tools_mirror_is_the_lua_value(self):
        S = G.Solver(CFG)
        for r in ROWS:
            self.assertAlmostEqual(G.py_value(r, S), VALUES[r['id']][0], places=6, msg=str(r['id']))

    def test_every_kind_is_used(self):
        used = set()
        for r in ROWS:
            used.update(r['kind'].split('+'))
        self.assertEqual(used, set(G.KEYS))


class Kinds(unittest.TestCase):
    def test_damage_and_heal_kinds_are_legal(self):
        damage = {'PULSE', 'LINE', 'MARK', 'RINGS', 'ECHO', 'SHIELD', 'CDCUT', 'LEECH'}
        heal = {'PULSE', 'REFLECT', 'SHIELD', 'ECHO', 'CDCUT'}
        for r in ROWS:
            kinds = set(r['kind'].split('+'))
            self.assertTrue(kinds <= (heal if r['role'] == 'heal' else damage), '%d %s' % (r['id'], r['kind']))

    def test_one_output_part_a_row(self):
        out = {'PULSE', 'LINE', 'RINGS', 'ECHO', 'REFLECT'}
        for r in ROWS:
            self.assertEqual(len(out & set(r['kind'].split('+'))), 1, '%d %s' % (r['id'], r['kind']))

    def test_a_cooldown_cut_needs_a_long_cooldown(self):
        for r in ROWS:
            if 'CDCUT' in r['kind']:
                self.assertGreaterEqual(float(r['cooldown']), G.MIN_CDCUT_SECONDS, '%d %s' % (r['id'], r['spell']))

    def test_area_spells_ring_and_lines_follow_the_shape(self):
        for r in ROWS:
            if r['role'] == 'damage' and 'LINE' in r['kind'] and r['id'] != 218:
                self.assertIn(r['shape'], ('single', 'self', 'line', 'wave'), '%d %s' % (r['id'], r['kind']))

    def test_names_are_unique_in_both_languages(self):
        for key in ('name_en', 'name_pt'):
            names = [r[key] for r in ROWS]
            self.assertEqual(len(names), len(set(names)), key)
        for r in ROWS:
            self.assertNotEqual(r['name_en'], r['spell'])

    def test_every_number_is_written(self):
        for r in ROWS:
            over = G.parse_over(r['over'])
            for kind in r['kind'].split('+'):
                self.assertEqual(sorted(over[kind]), sorted(G.KEYS[kind]), '%d %s' % (r['id'], kind))


class Refusals(unittest.TestCase):
    def test_a_spell_without_a_name_is_refused(self):
        saved = G.read_names
        names = saved()
        del names[206]
        G.read_names = lambda: names
        try:
            with self.assertRaises(SystemExit):
                G.generate()
        finally:
            G.read_names = saved

    def test_a_name_row_of_another_spell_is_refused(self):
        saved = G.read_names
        names = saved()
        names[206] = dict(names[206], spell='Something Else')
        G.read_names = lambda: names
        try:
            with self.assertRaises(SystemExit):
                G.generate()
        finally:
            G.read_names = saved

    def test_a_name_of_a_spell_with_no_forms_is_refused(self):
        saved = G.read_names
        names = saved()
        names[9999] = {'id': '9999', 'spell': 'Ghost', 'name_en': 'Boo', 'name_pt': 'Bu'}
        G.read_names = lambda: names
        try:
            with self.assertRaises(SystemExit):
                G.generate()
        finally:
            G.read_names = saved


if __name__ == '__main__':
    unittest.main()
