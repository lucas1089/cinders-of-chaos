#!/usr/bin/env python3
"""Tests of merge_brushes.py on a synthetic editor data folder: python3 -I mapeditor/tools/merge_brushes_test.py"""
import json
import os
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import merge_brushes as m  # noqa: E402

STOCK_BRUSHES = {
    'borders': {'1': [0, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16]},
    'grounds': {'grass': {'zorder': 3500, 'lookid': 4526, 'items': [[4526, 100]], 'borders': [], 'friends': []}},
    'walls': {'w': {}}, 'doors': {}, 'doodads': {}, 'carpets': {}, 'tables': {},
}
STOCK_TILESETS = {'terrain': {'Nature': [4526]}, 'raw': {'Others2': [1]}, 'item': {'Tools': [2]}}
OURS_B = {
    'borders': {'cinders_moss': [0] + list(range(100, 112))},
    'grounds': {'cinders moss': {'zorder': 3600, 'lookid': 99, 'items': [[99, 100]],
                                 'borders': [{'align': 'outer', 'border': 'cinders_moss', 'to': '*'}],
                                 'friends': []}},
}
OURS_T = {'terrain': {'Cinders': [99]}, 'raw': {'Cinders objects': [200]}}


def write(d, name, obj):
    with open(os.path.join(d, name), 'w', encoding='utf-8') as f:
        json.dump(obj, f, indent=1)


class T(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.data = os.path.join(self.tmp.name, 'data')
        self.frag = os.path.join(self.tmp.name, 'frag')
        os.makedirs(self.data)
        os.makedirs(self.frag)
        write(self.data, 'brushes.json', STOCK_BRUSHES)
        write(self.data, 'tilesets.json', STOCK_TILESETS)
        write(self.frag, 'cinders_brushes.json', OURS_B)
        write(self.frag, 'cinders_tilesets.json', OURS_T)

    def run_merge(self):
        return m.main([self.data, '--fragments', self.frag])

    def read(self, name):
        with open(os.path.join(self.data, name), encoding='utf-8') as f:
            return json.load(f)

    def test_merge_keeps_stock_and_adds_ours(self):
        self.assertEqual(self.run_merge(), 0)
        b, t = self.read('brushes.json'), self.read('tilesets.json')
        self.assertEqual(b['grounds']['grass'], STOCK_BRUSHES['grounds']['grass'])
        self.assertEqual(b['borders']['1'], STOCK_BRUSHES['borders']['1'])
        self.assertEqual(b['grounds']['cinders moss'], OURS_B['grounds']['cinders moss'])
        self.assertEqual(b['borders']['cinders_moss'], OURS_B['borders']['cinders_moss'])
        for k in ('walls', 'doors', 'doodads', 'carpets', 'tables'):
            self.assertIn(k, b)
        self.assertEqual(t['terrain']['Nature'], [4526])
        self.assertEqual(t['terrain']['Cinders'], [99])
        self.assertEqual(t['raw']['Cinders objects'], [200])
        self.assertEqual(t['item'], {'Tools': [2]})

    def test_idempotent(self):
        self.run_merge()
        with open(os.path.join(self.data, 'brushes.json'), 'rb') as f:
            first = f.read()
        self.run_merge()
        with open(os.path.join(self.data, 'brushes.json'), 'rb') as f:
            self.assertEqual(f.read(), first)

    def test_a_new_run_replaces_our_old_entries(self):
        self.run_merge()
        new = json.loads(json.dumps(OURS_B))
        new['grounds']['cinders moss']['zorder'] = 3700
        write(self.frag, 'cinders_brushes.json', new)
        self.run_merge()
        self.assertEqual(self.read('brushes.json')['grounds']['cinders moss']['zorder'], 3700)

    def test_refuses_a_stock_ground_item(self):
        bad = json.loads(json.dumps(OURS_B))
        bad['grounds']['cinders moss']['items'] = [[4526, 100]]
        write(self.frag, 'cinders_brushes.json', bad)
        with self.assertRaises(SystemExit) as e:
            self.run_merge()
        self.assertIn('stock ground', str(e.exception))
        self.assertNotIn('cinders moss', self.read('brushes.json')['grounds'])

    def test_refuses_a_stock_key(self):
        bad = json.loads(json.dumps(OURS_B))
        bad['borders']['1'] = bad['borders'].pop('cinders_moss')
        bad['grounds']['cinders moss']['borders'][0]['border'] = '1'
        write(self.frag, 'cinders_brushes.json', bad)
        with self.assertRaises(SystemExit):
            self.run_merge()

    def test_missing_file(self):
        os.remove(os.path.join(self.data, 'tilesets.json'))
        with self.assertRaises(SystemExit):
            self.run_merge()

    def test_real_fragments_merge_into_a_stock_like_folder(self):
        self.assertEqual(m.main([self.data]), 0)
        b = self.read('brushes.json')
        self.assertEqual(sum(1 for n in b['grounds'] if n.startswith('cinders ')), 12)


if __name__ == '__main__':
    unittest.main()
