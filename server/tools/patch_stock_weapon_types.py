#!/usr/bin/env python3
"""A stock weapon is the kind its name says (O500, owner 2026-11-11: "The item counts as an axe, but it is not."; server/README.md "Stock weapon types (O500)").

usage: python3 -I patch_stock_weapon_types.py DATA_DIR [--dry-run] [--table FILE]

The base server types a few weapons against what they are: the Twin Hooks (a pair of hooked blades) is an axe, the Dawnforged Great Axe
is a sword. The weaponType (sword, axe, club) is the weapon's kind for everything we build on it: the family trait (sword tempo, axe
cleave, club daze), the modifiers it may roll, the coverage tables and the tooltip's type line ("Two-handed axe"). So the step sets
weaponType in items.xml for exactly the ids of data/items/stock_weapon_types.csv (id, name, old, new, reason; the rule and every
decision are in server/README.md "Stock weapon types (O500)"; tools/audit_weapon_types.py finds the candidates):

  the item has the old type    set to the new one
  the item has the new type    already done
  the item has a third type    reported, left alone (someone changed it: the table is not applied over it)
  the item is not in items.xml reported
  a row whose new type = old   a decision to keep (polearms and a few odd names); nothing is written

An item keeps its id, so a copy a player owns has the new kind at once. Idempotent; `--dry-run` writes nothing. Run before every step that
reads a weapon type (vocations, weapons, the survey of tools/survey_base_weapons.py, the equip rules and the weapon growth). The name
column is for readers; the id decides."""
import csv
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SERVER = os.path.dirname(HERE)
TABLE = os.path.join(SERVER, 'data', 'items', 'stock_weapon_types.csv')
KINDS = ('sword', 'axe', 'club')

# an item with a body ends at </item>; a self-closing item (`<item id=".." name=".." />`) has none and must not swallow the next item
ITEM_RE = re.compile(r'(<item\s+([^>]*?)(/?)>)(.*?)(</item>|(?=<item\s))', re.S)
TYPE_RE = re.compile(r'(<attribute\s+key\s*=\s*"weaponType"\s+value\s*=\s*")([^"]*)(")', re.I)


def read_table(path=TABLE):
    """list of rows {id, name, old, new, reason}; refuses a row that is not three melee kinds or an id twice"""
    rows, seen = [], set()
    with open(path, encoding='utf-8', newline='') as f:
        for r in csv.DictReader(f):
            row = {'id': int(r['id']), 'name': r['name'], 'old': r['old'].strip().lower(), 'new': r['new'].strip().lower(),
                   'reason': r['reason']}
            if row['old'] not in KINDS or row['new'] not in KINDS:
                raise SystemExit('%s: id %d: old and new must be sword, axe or club' % (path, row['id']))
            if row['id'] in seen:
                raise SystemExit('%s: id %d twice' % (path, row['id']))
            seen.add(row['id'])
            rows.append(row)
    return rows


def patch_text(text, rows):
    """(new text, result) with result = {'moved': [row], 'done': [row], 'kept': [row], 'other': [(row, type)], 'missing': [row]}"""
    want = {r['id']: r for r in rows}
    res = {'moved': [], 'done': [], 'kept': [], 'other': [], 'missing': []}
    seen = set()

    def fix(m):
        idm = re.search(r'\bid\s*=\s*"(\d+)"', m.group(2))
        if m.group(3) == '/' or not idm:
            return m.group(0)
        row = want.get(int(idm.group(1)))
        if not row:
            return m.group(0)
        seen.add(row['id'])
        body = m.group(4)
        tm = TYPE_RE.search(body)
        have = tm.group(2).lower() if tm else None
        if row['old'] == row['new']:
            res['kept'].append(row)
            return m.group(0)
        if have == row['new']:
            res['done'].append(row)
            return m.group(0)
        if have != row['old']:
            res['other'].append((row, have))
            return m.group(0)
        res['moved'].append(row)
        body = TYPE_RE.sub(lambda t: t.group(1) + row['new'] + t.group(3), body, count=1)
        return m.group(1) + body + m.group(5)

    out = ITEM_RE.sub(fix, text)
    res['missing'] = [r for r in rows if r['id'] not in seen]
    return out, res


def lines_of(res, total):
    lines = []
    for r in res['moved']:
        lines.append('  %d %s: %s -> %s' % (r['id'], r['name'], r['old'], r['new']))
    for r, have in res['other']:
        lines.append('  WARNING: %d %s has the type %s (the table says %s -> %s): left alone' % (r['id'], r['name'], have, r['old'], r['new']))
    for r in res['missing']:
        lines.append('  WARNING: %d %s is not in items.xml' % (r['id'], r['name']))
    if res['moved']:
        head = 'items.xml: %d stock weapon(s) set to the kind their name says' % len(res['moved'])
    else:
        head = 'items.xml: the stock weapon types are right'
    head += ' (%d already done, %d kept on purpose, %d rows)' % (len(res['done']), len(res['kept']), total)
    return [head] + lines


def main(argv):
    args = [a for a in argv if not a.startswith('--')]
    table = TABLE
    if '--table' in argv:
        i = argv.index('--table')
        table = argv[i + 1]
        args = [a for a in args if a != table]
    if len(args) != 1:
        print(__doc__)
        return 2
    path = os.path.join(args[0], 'items', 'items.xml')
    if not os.path.isfile(path):
        print('not found:', path)
        return 1
    rows = read_table(table)
    with open(path, encoding='utf-8', errors='surrogateescape', newline='') as f:
        text = f.read()
    new, res = patch_text(text, rows)
    print('\n'.join(lines_of(res, len(rows))))
    if '--dry-run' in argv:
        print('dry run: nothing written')
        return 0
    if new != text:
        with open(path, 'w', encoding='utf-8', errors='surrogateescape', newline='') as f:
            f.write(new)
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
