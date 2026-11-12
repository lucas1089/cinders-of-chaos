#!/usr/bin/env python3
"""python3 -I client/tools/sprites/donor_missile_names_test.py : the donor-name rule of donor_missile_names.py on synthetic
Lua and catalog text, on the committed tables (clean, idempotent), and the wiring in import_fx_art.py (O528)."""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import donor_missile_names as D  # noqa: E402

failed = 0


def check(ok, what):
    global failed
    if not ok:
        failed += 1
        print('FAIL:', what)


donors = D.donor_ids()
check(len(donors) == 62 and min(donors) == 147 and max(donors) == 250, '62 donor ids, 147..250')
check({200, 205, 208, 228, 229, 249}.isdisjoint(donors), 'ids the donors did not touch stay named')

lua = ('-- GENERATED\nif not ChaosVfx then\nend\nChaosVfx.a = {id = 189, dx = 1, dy = 1, ms = 9}  -- an effect keeps its row\n'
       'ChaosVfxMissile.proj_bomb = {id = 189, dx = 1, dy = 1}  -- Bomb\n'
       'ChaosVfxMissile.proj_spirit_wisp = {id = 200, dx = 0, dy = 0}  -- Spirit Wisp\n'
       'ChaosVfxMissile.p51_dynamite = {id = 189, dx = 0, dy = 0}\n')
out = D.filter_lua(lua, donors)
check('proj_bomb' not in out, 'a pack name on a donor id is dropped')
check('proj_spirit_wisp' in out, 'a pack name on an untouched id stays')
check('ChaosVfx.a = {id = 189' in out, 'an effect with the same number stays')
check('p51_dynamite' in out, 'a p51_ name stays')
check(D.NOTE in out and out.index(D.NOTE) < out.index('if not ChaosVfx'), 'the note sits in the header')
check(D.filter_lua(out, donors) == out, 'idempotent, the note is not added twice')
check(D.filter_lua('ChaosVfxMissile.x = {id = 5, dx = 0, dy = 0}\n', donors) == 'ChaosVfxMissile.x = {id = 5, dx = 0, dy = 0}\n',
      'a text with nothing to drop is unchanged, no note')

cat = ('kind,id,name,size\neffect,189,e189,1x1\nmissile,189,proj_bomb,3x3\nmissile,200,proj_spirit_wisp,2x2\n'
       'missile,5,x,1x1\n')
oc = D.filter_catalog(cat, donors)
check('proj_bomb' not in oc and 'e189' in oc and 'proj_spirit_wisp' in oc and 'missile,5,' in oc, 'catalog rows')
check(D.filter_catalog(oc, donors) == oc, 'catalog idempotent')

for p in D.TABLES:
    old, new = D.apply(p, donors)
    check(old == new, os.path.relpath(p, D.ROOT) + ' has no donor-drawn pack name')

src = open(os.path.join(HERE, 'import_fx_art.py'), encoding='utf-8').read()
check('DN.filter_lua(' in src and 'in DONORS' in src and '--keep-donor-names' in src,
      'import_fx_art.py applies the rule to the Lua and the catalog it writes')
sys.exit(1 if failed else 0)
