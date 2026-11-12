#!/usr/bin/env python3
"""Pack missile names must not point at donor art (O528).

    python3 -I client/tools/sprites/donor_missile_names.py           # drop the donor-drawn pack names from the 4 tables
    python3 -I client/tools/sprites/donor_missile_names.py --check   # CI: the 4 committed tables are already clean

import_pair51_missiles.py refilled the blank missile ids 147-152 and 189-250 (62 ids, pair51_missiles.csv) with missiles of
two other sprite sources. Pair 36 had named ids 189-250 (proj_*, mega_*) and pair 41 redrew 189-203, so those names drew
something else from pair 51 on (189 "proj_bomb" drew dynamite, 192 "proj_comet" a fire comet; 43 of the 62 are one-phase
1x1 stills). The names of those ids are the p51_<name> ones of chaos_pair51_missile_ids.lua. This module holds the rule: a
missile row of a pack table whose id is in the donor set is left out. import_fx_art.py applies it when it writes the Lua
and catalog tables (flag --keep-donor-names for a rebuild of an older pair); this CLI applies it to the committed tables,
which the full import cannot rewrite without the old pairs.  Idempotent.  Stdlib only.

The art specs (art_import/pack36_missiles.csv, pack41_missiles.csv) are NOT edited: they are the build record of pairs
36 and 41, where a missile's id is its position in the spec, so dropping a row would move every later id.
server/tests/missile_art_source_test.lua is the guard on the name tables.
"""
import csv
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', '..', '..'))
DONOR_CSV = os.path.join(HERE, 'pair51_missiles.csv')
LIB = os.path.join(ROOT, 'server', 'data', 'lib')
SPELLS = os.path.join(ROOT, 'server', 'data', 'spells')
TABLES = [os.path.join(LIB, 'chaos_pack36_fx_ids.lua'), os.path.join(LIB, 'chaos_pack41_fx_ids.lua'),
          os.path.join(SPELLS, 'pack36_fx_catalog.csv'), os.path.join(SPELLS, 'pack41_fx_catalog.csv')]
NOTE = ('-- Missile names whose id draws the art of another source are not listed (O528, donor_missile_names.py): pair 51 '
        'refilled the ids\n'
        '-- of pair51_missiles.csv with donor missiles, and those are named p51_<name> in chaos_pair51_missile_ids.lua.')
LUA_ROW = re.compile(r'^ChaosVfxMissile\.([A-Za-z0-9_]+) = \{id = (\d+),')
CAT_ROW = re.compile(r'^missile,(\d+),')


def donor_ids(path=DONOR_CSV):
    with open(path, newline='', encoding='utf-8') as fh:
        return {int(r['missile_id']) for r in csv.DictReader(fh)}


def filter_lua(text, donors):
    """the Lua text without the ChaosVfxMissile rows of donor ids (p51_ names are the donors' own)"""
    out, dropped = [], 0
    for line in text.split('\n'):
        m = LUA_ROW.match(line)
        if m and int(m.group(2)) in donors and not m.group(1).startswith('p51_'):
            dropped += 1
            continue
        out.append(line)
    if dropped and NOTE not in text:
        for i, line in enumerate(out):
            if line.startswith('if not ChaosVfx'):
                out[i:i] = NOTE.split('\n')
                break
    return '\n'.join(out)


def filter_catalog(text, donors):
    """the catalog text without the missile rows of donor ids"""
    return '\n'.join(l for l in text.split('\n') if not (CAT_ROW.match(l) and int(CAT_ROW.match(l).group(1)) in donors))


def apply(path, donors):
    with open(path, newline='', encoding='utf-8') as fh:
        old = fh.read()
    new = (filter_lua if path.endswith('.lua') else filter_catalog)(old, donors)
    return old, new


def main(argv):
    check = '--check' in argv
    donors = donor_ids()
    bad = 0
    for p in TABLES:
        old, new = apply(p, donors)
        name = os.path.relpath(p, ROOT)
        if old == new:
            print('%s: clean' % name)
            continue
        if check:
            print('%s: names a donor id; run donor_missile_names.py' % name)
            bad += 1
        else:
            with open(p, 'w', newline='', encoding='utf-8') as fh:
                fh.write(new)
            print('%s: rewritten' % name)
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
