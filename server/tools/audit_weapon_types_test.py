#!/usr/bin/env python3
"""Tests of audit_weapon_types.py on synthetic files (O500, server/README.md "Stock weapon types (O500)"):
python3 -I server/tools/audit_weapon_types_test.py

The name rule (head noun, compounds, the part before " of "), the CLEAR / ODD / SPEED lists on a made-up items.xml, weapons.xml and
vocations.xml, the table marks, --check (exit 1 on a stock mismatch not in the table, 0 with it, a Chaos item never fails it) and the
committed table's own rule: every row of it that moves a weapon agrees with the rule of the audit (a move to the kind the name says, or
an odd item with a hint word), so the table and the tool do not drift."""
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import audit_weapon_types as A
import patch_stock_weapon_types as P

fails = 0


def check(cond, label):
    global fails
    if not cond:
        fails += 1
        print('FAIL ' + label)


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w', encoding='utf-8', newline='') as f:
        f.write(text)


# ---- the name rule
for name, want in (('hand axe', 'axe'), ('Dawnforged Great Axe', 'axe'), ('greataxe', 'axe'), ('ogre choppa', 'axe'), ('dreaded cleaver', 'axe'),
                   ('guardian halberd', 'axe'), ('longsword', 'sword'), ('thornmere sword', 'sword'), ('combat knife', 'sword'),
                   ('blade of corruption', 'sword'), ('scytheblade', 'sword'), ("Mad Hobb the Ripper's sabre", 'sword'),
                   ('war hammer', 'club'), ('warhammer', 'club'), ('morning star', 'club'), ('Dawnforged Skull Crusher', 'club'),
                   ('metal bat', 'club'), ("brutetamer's staff", 'club'), ('hammer of wrath', 'club'), ('mace of mayhem', 'club'),
                   ('axe of mayhem', 'axe'), ('scythe of the reaper', None), ('twin hooks', None), ('the avenger', None),
                   ('Serrated Twin Hooks of Devouring', None), ('combat', None)):
    got = A.kind_by_name(name)
    check((got[0] if got else None) == want, 'kind_by_name(%r) = %r, want %r' % (name, got, want))
check(A.kind_by_name('hammer axe')[0] == 'axe', 'the head noun is the last word: a hammer axe is an axe')
check(A.kind_by_name('axe hammer')[0] == 'club', 'an axe hammer is a hammer')
check(A.hint_by_name('twin hooks')[1] == 'sword', 'hooks are a sword')
check(A.hint_by_name('dragon lance')[1] == 'axe', 'a lance is an axe (polearms follow the stock majority)')
check(A.hint_by_name('sludgebrass whip')[1] == 'club', 'a whip is a club')
check(A.hint_by_name('the avenger') is None, 'no hint in a plain name')
check(A.word_kind('combat') is None, 'combat is no bat')

# ---- the lists
ITEMS = '''<?xml version="1.0"?>
<items>
	<item id="10" name="hand axe"><attribute key="weaponType" value="sword" /><attribute key="attack" value="5" /></item>
	<item id="11" name="great axe" plural="great axes"><attribute key="weaponType" value="axe" /><attribute key="slotType" value="two-handed" /><attribute key="attackspeed" value="3000" /></item>
	<item id="12" name="twin hooks"><attribute key="weaponType" value="axe" /><attribute key="slotType" value="two-handed" /><attribute key="attackspeed" value="3000" /></item>
	<item id="13" name="the avenger"><attribute key="weaponType" value="sword" /></item>
	<item id="14" name="skull crusher"><attribute key="weaponType" value="sword" /></item>
	<item id="15" name="dragon lance"><attribute key="weaponType" value="axe" /><attribute key="attackspeed" value="1800" /></item>
	<item id="16" name="a shield"><attribute key="weaponType" value="shield" /></item>
	<item id="17" name="short bow"><attribute key="weaponType" value="distance" /><attribute key="slotType" value="two-handed" /><attribute key="attackspeed" value="3000" /></item>
	<item id="40000" name="cinder maul"><attribute key="weaponType" value="axe" /></item>
	<item id="18" name="steel axe"><attribute key="weaponType" value="axe" /><attribute key="attackspeed" value="2000" /></item>
</items>
'''
WEAPONS = '''<weapons>
	<melee id="12" level="20"><vocation name="Warrior" /><vocation name="Ninja" /></melee>
	<melee id="11" level="30"><vocation name="Warrior" /></melee>
</weapons>
'''
VOCATIONS = '''<vocations>
	<vocation id="1" name="Warrior" description="x" attackspeed="1300"></vocation>
	<vocation id="2" name="Ninja" description="x" attackspeed="900"></vocation>
</vocations>
'''
tmp = tempfile.mkdtemp(prefix='o500audit_')
try:
    write(os.path.join(tmp, 'items', 'items.xml'), ITEMS)
    write(os.path.join(tmp, 'weapons', 'weapons.xml'), WEAPONS)
    write(os.path.join(tmp, 'XML', 'vocations.xml'), VOCATIONS)
    res = A.audit(tmp, {})
    clear = {r['id']: r for r in res['clear']}
    check(sorted(clear) == [10, 14, 40000], 'CLEAR: the hand axe (a sword), the skull crusher (a sword) and the Chaos maul: %r' % sorted(clear))
    check(clear[10]['kind'] == 'axe' and clear[14]['kind'] == 'club', 'CLEAR: the kind the name says')
    check(clear[10]['stock'] and not clear[40000]['stock'], 'CLEAR: a Chaos id is marked')
    odd = {r['id']: r for r in res['odd']}
    check(sorted(odd) == [12, 13, 15], 'ODD: the hooks, the avenger and the lance: %r' % sorted(odd))
    check(odd[12]['kind'] == 'sword' and odd[12]['word'] == 'hooks', 'ODD: hooks are a sword')
    check(odd[15]['kind'] == 'axe' and odd[15]['type'] == 'axe', 'ODD: the lance stays an axe')
    check(odd[13]['word'] == '' and odd[13]['kind'] == odd[13]['type'], 'ODD: the avenger has no clue and keeps its type')
    speed = {r['id']: r for r in res['speed']}
    check(sorted(speed) == [11, 12, 15, 17], 'SPEED: 3000 / 3000 / 1800 / 3000 ms, not the 2000 ms one: %r' % sorted(speed))
    check(speed[12]['swings'] == [1350, 1950], 'SPEED: the swing for the Warrior (1300) and the Ninja (900): %r' % speed[12]['swings'])
    check(speed[11]['swings'] == [1950] and speed[11]['hands'] == 2 and speed[15]['hands'] == 1, 'SPEED: hands and a single class')
    text = '\n'.join(A.render(res))
    check('CLEAR mismatches (the name says one kind, the type another): 3' in text, 'the CLEAR header counts')
    check('ODD items (no kind word in the name): 3, of them 2 with a hint word, 1 with no clue' in text, 'the ODD header counts')
    check('SLOW (over 2500 ms): 3, of them 3 two-handed' in text, 'the SLOW line counts')
    check('NOT in the table' in text, 'a mismatch is marked as missing from the table')
    # the table marks
    table = {10: {}, 12: {}}
    res2 = A.audit(tmp, table)
    check([r['in_table'] for r in res2['clear'] if r['id'] == 10] == [True], 'the table marks a CLEAR row')
    check([r['in_table'] for r in res2['odd'] if r['id'] == 12] == [True], 'the table marks an ODD row')
    # --check
    tpath = os.path.join(tmp, 'table.csv')
    write(tpath, 'id,name,old,new,reason\n10,hand axe,sword,axe,x\n')
    run = lambda *a: subprocess.run([sys.executable, '-I', os.path.join(HERE, 'audit_weapon_types.py'), tmp, '--check', '--quiet'] + list(a),
                                    stdout=subprocess.PIPE, stderr=subprocess.STDOUT, universal_newlines=True)
    p = run('--table', tpath)
    check(p.returncode == 1 and 'FAIL: 1 clear mismatch(es)' in p.stdout, '--check: the skull crusher is not in the table: exit 1: ' + p.stdout[-200:])
    write(tpath, 'id,name,old,new,reason\n10,hand axe,sword,axe,x\n14,skull crusher,sword,club,x\n')
    p = run('--table', tpath)
    check(p.returncode == 0, '--check: both in the table: exit 0 (a Chaos item never fails it): ' + p.stdout[-200:])
    p = subprocess.run([sys.executable, '-I', os.path.join(HERE, 'audit_weapon_types.py')], stdout=subprocess.PIPE, universal_newlines=True)
    check(p.returncode == 2, 'no argument: usage')
finally:
    shutil.rmtree(tmp, ignore_errors=True)

# ---- the committed table against the rule: a move goes to the kind the name says, or is an odd item with a hint word of the same kind
for r in P.read_table():
    if r['old'] == r['new']:
        hint = A.hint_by_name(r['name'])
        found = A.kind_by_name(r['name'])
        check((found and found[0] == r['new']) or (hint and hint[1] == r['new']), 'kept row %d %s agrees with the rule' % (r['id'], r['name']))
        continue
    found = A.kind_by_name(r['name'])
    hint = A.hint_by_name(r['name'])
    if found:
        check(found[0] == r['new'], 'row %d %s: the name says %s' % (r['id'], r['name'], found[0]))
    else:
        check(hint is not None and hint[1] == r['new'], 'row %d %s: the hint word gives %s' % (r['id'], r['name'], r['new']))

if fails:
    print('%d check(s) failed' % fails)
    sys.exit(1)
print('audit_weapon_types_test: ok')
