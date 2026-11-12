#!/usr/bin/env python3
"""Dead references in the map editor palette and brushes of our own grounds (O514).

    python3 -I tools/ci/check_editor_palette.py

Reads the committed mapeditor/data/1098/cinders/cinders_brushes.json and cinders_tilesets.json (written by
server/tools/gen_editor_brushes.py) and the item table server/data/items/art_items.csv, and fails when:
  - an id of a border set, a ground or a palette is not a server id of that table (a dead reference), or has the
    wrong kind (a border slot that is not a border piece, a ground brush on a non-ground)
  - a ground family of the table (kind ground) has no brush, no border set, or a border set that lacks one of its
    12 pieces
  - a ground, water, shore, lake, dock, tree or stump of the table is in no palette
  - a ground names a border set that is not defined, or a palette lists an id twice
Exit 0 and one line when all is well."""
import csv
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CINDERS = os.path.join(ROOT, 'mapeditor', 'data', '1098', 'cinders')
ART_ITEMS = os.path.join(ROOT, 'server', 'data', 'items', 'art_items.csv')
PIECES = ('n', 'e', 's', 'w', 'nw', 'ne', 'sw', 'se', 'in_nw', 'in_ne', 'in_sw', 'in_se')
IN_PALETTE = ('ground', 'water', 'shore', 'lake', 'dock', 'tree', 'stump', 'border')


def load_json(path, problems):
    try:
        with open(path, encoding='utf-8') as f:
            return json.load(f)
    except (OSError, ValueError) as e:
        problems.append('%s: %s' % (os.path.relpath(path, ROOT), e))
        return None


def check(cinders=CINDERS, art_items=ART_ITEMS):
    problems = []
    items = {}
    with open(art_items, encoding='utf-8', newline='') as f:
        for r in csv.DictReader(f):
            items[int(r['server_id'])] = r
    brushes = load_json(os.path.join(cinders, 'cinders_brushes.json'), problems)
    tilesets = load_json(os.path.join(cinders, 'cinders_tilesets.json'), problems)
    if problems:
        return problems

    def kind(i):
        r = items.get(i)
        return r['kind'] if r else None

    borders = brushes.get('borders', {})
    grounds = brushes.get('grounds', {})
    for key, arr in borders.items():
        if len(arr) != 13 or arr[0] != 0:
            problems.append('border set %s: want 13 slots with slot 0 = 0' % key)
            continue
        for slot, i in enumerate(arr[1:], 1):
            if kind(i) is None:
                problems.append('border set %s slot %d: id %s is not in art_items.csv' % (key, slot, i))
            elif kind(i) != 'border':
                problems.append('border set %s slot %d: id %s is a %s, not a border piece' % (key, slot, i, kind(i)))
    ground_ids = set()
    for name, g in grounds.items():
        ids = [int(x[0]) for x in g.get('items', [])] + [int(g.get('lookid', 0))]
        for i in ids:
            ground_ids.add(i)
            if kind(i) != 'ground':
                problems.append('ground %s: id %s is %s' % (name, i, kind(i) or 'not in art_items.csv'))
        for b in g.get('borders', []):
            if b.get('border') not in borders:
                problems.append('ground %s: border set %s is not defined' % (name, b.get('border')))
    for i, r in sorted(items.items()):
        if r['kind'] != 'ground':
            continue
        short = r['key'][len('ground_'):]
        if i not in ground_ids:
            problems.append('ground family %s (id %d) has no ground brush' % (short, i))
        owners = [n for n, g in grounds.items() if g.get('lookid') == i]
        sets = {b['border'] for n in owners for b in grounds[n].get('borders', [])}
        if not sets:
            problems.append('ground family %s has no border set' % short)
        want = {p: items[j]['server_id'] for j, p in
                ((j, items[j]['key'][len('border_%s_' % short):]) for j in items
                 if items[j]['kind'] == 'border' and items[j]['key'].startswith('border_%s_' % short))}
        if sorted(want) != sorted(PIECES):
            problems.append('ground family %s: the table has pieces %s, want %s' % (short, sorted(want), sorted(PIECES)))
        for s in sets:
            have = {int(x) for x in borders.get(s, [])[1:]}
            lacking = [p for p in want if int(want[p]) not in have]
            if lacking:
                problems.append('border set %s lacks the pieces %s of %s' % (s, lacking, short))
    seen = {}
    for cat, palettes in tilesets.items():
        for name, ids in palettes.items():
            if len(ids) != len(set(ids)):
                problems.append('palette %s lists an id twice' % name)
            for i in ids:
                seen.setdefault(i, []).append(name)
                if i not in items:
                    problems.append('palette %s: id %s is not in art_items.csv' % (name, i))
    for i, r in sorted(items.items()):
        if r['kind'] in IN_PALETTE and i not in seen:
            problems.append('%s %s (id %d) is in no palette' % (r['kind'], r['key'], i))
    return problems


def main():
    problems = check()
    if problems:
        for p in problems:
            print('FAIL', p)
        print('%d problem(s) in the map editor palette' % len(problems))
        return 1
    print('map editor palette ok: every id is a pack item, every ground family has a brush and its 12 pieces')
    return 0


if __name__ == '__main__':
    sys.exit(main())
