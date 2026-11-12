#!/usr/bin/env python3
"""Brushes of our own grounds for our map editor, so it borders them by itself (O514).

    python3 -I server/tools/gen_editor_brushes.py [--out DIR] [--check]

Writes two files into mapeditor/data/1098/cinders/ (or DIR):

  cinders_brushes.json   the "borders" and "grounds" objects in the schema of the upstream editor's brushes.json
  cinders_tilesets.json  the palettes, in the schema of its tilesets.json

mapeditor/tools/merge_brushes.py merges them into the editor's own data/1098 files (the build workflow and the
Windows package run it). --check fails when the committed files differ from what this script writes (CI).

The data comes from our tables, never from a hand list:
  server/data/items/art_items.csv   the 12 pack grounds (kind ground), their 12 border pieces each (kind border, extra
                                    piece=...), the water, shores, lake objects, dock props, trees and stumps
  server/data/scripts/chaos/areaplan_build.lua   `local PACK = {...}`: the z order of six grounds in the area
                                    planner; the editor uses the same numbers, so a hand-bordered map and a planned
                                    area agree on which ground draws over which

What the editor reads (schema, facts from the upstream tree at the pin, editor/core/brushstore.cpp):
  border set  "borders": {KEY: [0, n, e, s, w, cnw, cne, csw, cse, dnw, dne, dse, dsw]}: 13 slots, slot 0 unused, a
              slot is an item id or {"variants": [[id, chance], ...]}
  ground      "grounds": {NAME: {"zorder", "lookid", "items": [[id, chance]], "borders": [{"align": "outer"|"inner",
              "border": KEY, "to": NAME | "*" | ""}], "friends": [...], "hate_friends", "optional", "solo_optional"}}
  The ground with the higher zorder owns an "outer" border and the editor puts its pieces on the lower neighbour
  tile, the way our borders work. "to": "*" is every lower ground, stock grounds included.

The 12 slots take our 12 pieces as the area planner already does (server/tools/areaplan_build.lua packPiece): the
editor's n, e, s, w are our n, e, s, w; its outer corners (cnw, cne, csw, cse: only that diagonal neighbour is the
higher ground) are our nw, ne, sw, se; its inner corners (dnw, dne, dse, dsw: two sides) are our in_nw, in_ne, in_se,
in_sw. The proof is in gen_editor_brushes_test.py and server/README.md "Editor brushes (O514)".

Shores are not brushes: a shore set has 19 pieces named after the land sides in 4-neighbour combinations (in_ew,
in_nsw, ...), animated, and drawn on the water tile; the editor's rule has 12 slots chosen from 8 neighbours. They are
in the palette only."""
import argparse
import csv
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
ART_ITEMS = os.path.join(ROOT, 'server', 'data', 'items', 'art_items.csv')
PLANNER = os.path.join(ROOT, 'server', 'tools', 'areaplan_build.lua')
OUT_DIR = os.path.join(ROOT, 'mapeditor', 'data', '1098', 'cinders')

# the editor's 13 border slots (slot 0 unused) and our piece names (see the docstring)
SLOTS = ('n', 'e', 's', 'w', 'cnw', 'cne', 'csw', 'cse', 'dnw', 'dne', 'dse', 'dsw')
PIECE_OF = {'n': 'n', 'e': 'e', 's': 's', 'w': 'w', 'cnw': 'nw', 'cne': 'ne', 'csw': 'sw', 'cse': 'se',
            'dnw': 'in_nw', 'dne': 'in_ne', 'dse': 'in_se', 'dsw': 'in_sw'}

# z order of the grounds the planner does not list (editor only). The stock grounds of the editor: dirt 1000,
# sand 3000, grass 3500, earth 10500. Ours draw their border over stock dirt and sand; grass draws over our floors,
# clay and sand; our grass and loam sit at or above stock grass (the planner's numbers).
EDITOR_Z = {'fine_sand': 3050, 'flagstone_floor': 3300, 'jade_tile_floor': 3310, 'slate_floor': 3320,
            'red_clay': 3480, 'bright_grass': 3640}

NAME_PREFIX = 'cinders '
BORDER_PREFIX = 'cinders_'
PALETTE = 'Cinders'


def read_items(path=ART_ITEMS):
    rows = []
    with open(path, encoding='utf-8', newline='') as f:
        for r in csv.DictReader(f):
            extra = {}
            for part in re.split(r'[|]', r.get('extra') or ''):
                if '=' in part:
                    k, v = part.split('=', 1)
                    extra[k] = v
            rows.append({'key': r['key'], 'id': int(r['server_id']), 'kind': r['kind'], 'name': r['name'],
                         'extra': extra})
    return rows


def planner_z(path=PLANNER):
    """z orders of `local PACK = {name = z, ...}` in the area planner"""
    with open(path, encoding='utf-8') as f:
        text = f.read()
    m = re.search(r'local PACK = \{([^}]*)\}', text)
    if not m:
        raise SystemExit('%s: no "local PACK = {...}" table' % path)
    z = {k: int(v) for k, v in re.findall(r'([a-z_]+)\s*=\s*(\d+)', m.group(1))}
    if not z:
        raise SystemExit('%s: empty PACK table' % path)
    return z


def families(rows):
    """[(short name, ground row, {piece: id})] for every ground, in id order"""
    out = []
    for g in sorted((r for r in rows if r['kind'] == 'ground'), key=lambda r: r['id']):
        short = g['key'][len('ground_'):]
        pieces = {}
        for r in rows:
            if r['kind'] == 'border' and r['key'].startswith('border_' + short + '_'):
                if r['key'][len('border_' + short + '_'):] != r['extra'].get('piece'):
                    raise SystemExit('%s: key and piece= disagree' % r['key'])
                pieces[r['extra']['piece']] = r['id']
        out.append((short, g, pieces))
    return out


def zorder(short, planner):
    if short in planner:
        return planner[short]
    if short in EDITOR_Z:
        return EDITOR_Z[short]
    raise SystemExit('ground %s has no z order: add it to EDITOR_Z (or to PACK of areaplan_build.lua)' % short)


def build_brushes(rows, planner):
    borders, grounds = {}, {}
    for short, g, pieces in families(rows):
        missing = [p for p in PIECE_OF.values() if p not in pieces]
        if missing:
            raise SystemExit('ground %s lacks border pieces %s' % (short, missing))
        key = BORDER_PREFIX + short
        borders[key] = [0] + [pieces[PIECE_OF[s]] for s in SLOTS]
        grounds[NAME_PREFIX + g['name']] = {
            'borders': [{'align': 'outer', 'border': key, 'to': '*'}],
            'friends': [],
            'hate_friends': False,
            'items': [[g['id'], 100]],
            'lookid': g['id'],
            'optional': '',
            'solo_optional': False,
            'zorder': zorder(short, planner),
        }
    return {'borders': borders, 'grounds': grounds}


def build_tilesets(rows):
    def ids(kind):
        return sorted(r['id'] for r in rows if r['kind'] == kind)
    grounds = [g['id'] for _, g, _ in families(rows)]
    return {
        'terrain': {PALETTE: grounds + ids('water') + ids('shore')},
        'raw': {PALETTE + ' objects': ids('lake') + ids('dock') + ids('tree') + ids('stump'),
                PALETTE + ' border pieces': ids('border')},
    }


def render(obj):
    return json.dumps(obj, indent=1, ensure_ascii=True) + '\n'


def outputs(rows=None, planner=None):
    rows = rows if rows is not None else read_items()
    planner = planner if planner is not None else planner_z()
    return {'cinders_brushes.json': render(build_brushes(rows, planner)),
            'cinders_tilesets.json': render(build_tilesets(rows))}


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('--out', default=OUT_DIR)
    ap.add_argument('--check', action='store_true', help='fail when the files in --out are not what this writes')
    a = ap.parse_args(argv)
    want = outputs()
    if a.check:
        bad = []
        for name, text in want.items():
            path = os.path.join(a.out, name)
            have = open(path, encoding='utf-8', newline='').read() if os.path.exists(path) else None
            if have != text:
                bad.append(path)
        if bad:
            print('out of date (run python3 -I server/tools/gen_editor_brushes.py): ' + ', '.join(bad))
            return 1
        print('editor brushes up to date (%d files)' % len(want))
        return 0
    os.makedirs(a.out, exist_ok=True)
    for name, text in want.items():
        with open(os.path.join(a.out, name), 'w', encoding='utf-8', newline='') as f:
            f.write(text)
        print('wrote', os.path.join(a.out, name))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
