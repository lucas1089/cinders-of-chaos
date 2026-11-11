#!/usr/bin/env python3
"""Tests of the weapon growth of O472 (tools/weapon_growth.py): W and a(level), the weapon curves of the install tools against the old
curves, the four install tools and the generated lists moving an install made with the OLD numbers to the new ones (and a second run
changing nothing), the growth table, the uniques, the caster config and the Lua side holding the same table.

usage: python3 -I server/tools/weapon_growth_test.py
"""
import os
import re
import subprocess
import shutil
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SERVER = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import weapon_growth as WG  # noqa: E402
import install_gear_sets as GS  # noqa: E402
import install_weapons800 as W8  # noqa: E402
import install_relic_sets as RS  # noqa: E402
import install_fist_weapons as FW  # noqa: E402
import gen_weapon_growth as GG  # noqa: E402

fails = 0


def check(cond, msg):
    global fails
    if not cond:
        fails += 1
        print('FAIL: ' + msg)


# ---- W and a
rows = {100: 1.00, 200: 1.14, 300: 1.26, 500: 1.42, 700: 1.55, 850: 1.85, 1000: 2.20, 1500: 2.35, 2000: 2.60}
for lv, w in rows.items():
    check(abs(WG.weapon_w(lv) - w) < 1e-9, 'W(%d) = %.2f' % (lv, w))
check(WG.weapon_w(1) == 1.0 and WG.weapon_w(100) == 1.0 and WG.weapon_w(9000) == 2.6, 'W is 1 up to 100 and flat above 2000')
check(abs(WG.weapon_a(500) - (1 + 0.42 / 0.85)) < 1e-9 and abs(WG.weapon_a(1000) - 2.4117647) < 1e-6, 'a = 1 + (W - 1) / 0.85')
prev, worst = 1.0, 1.0
for lv in range(100, 2101):
    w = WG.weapon_w(lv)
    if w < prev - 1e-12:
        check(False, 'W falls at %d' % lv)
    prev = w
    if lv - 50 >= 100:
        worst = max(worst, w / WG.weapon_w(lv - 50))
check(worst <= 1.12, 'no step above x1.12 per 50 levels (%.4f)' % worst)
check(WG.grown(55, 300) == int(55 * WG.weapon_a(300) + 0.5) and WG.grown(55, 100) == 55 and WG.grown(55, 50) == 55, 'grown() rounds half up, 1 up to 100')

# ---- the curves are the old ones times a at every anchor
for name in ('attack', 'bow', 'wand'):
    for lv, new in zip(GS.WEAPON_ANCHORS, GS.WEAPON_CURVES[name]):
        want = GS.old_weapon_curve(name, lv) * WG.weapon_a(lv)
        check(abs(new - want) <= 0.51, '%s at %d: %s is old x a = %.2f' % (name, lv, new, want))
    check(len(GS.WEAPON_CURVES[name]) == len(GS.WEAPON_ANCHORS), name + ': a value per anchor')
check(GS.curve('attack', 1000) == 147 and GS.curve('bow', 1000) == 191 and GS.curve('wand', 1000) == 285, 'the curves at 1000: 147 / 191 / 285')
check(GS.curve('attack', 100) == 46 and GS.curve('attack', 50) == 40, 'no growth up to 100')
with GS.old_weapon_curves():
    check(GS.curve('attack', 1000) == 61 and GS.curve('wand', 1000) == 118, 'old_weapon_curves() gives the numbers of before')
check(GS.curve('attack', 1000) == 147, 'and puts the new ones back')

# ---- the Lua config holds the same table and the same mean wand curve
cfg = open(os.path.join(SERVER, 'data', 'scripts', 'chaos', 'spell_scaling_config.lua')).read()
growth = re.search(r'weaponGrowth = \{(.*?)\},\n\tcaster', cfg, re.S).group(1)
pairs = [(int(a), float(b)) for a, b in re.findall(r'\{(\d+), ([\d.]+)\}', growth)]
check(tuple(pairs) == WG.WEAPON_GROWTH, 'spell_scaling_config.lua weaponGrowth is weapon_growth.py WEAPON_GROWTH')
mean = [(int(a), int(b)) for a, b in re.findall(r'\{(\d+), (\d+)\}', re.search(r'wandMean = \{(.*?)\},\n\t\},', cfg, re.S).group(1))]
check(mean == list(zip(GS.WEAPON_ANCHORS, GS.WEAPON_CURVES['wand'])), 'caster.wandMean is the wand curve of the install tool')

bow = [(int(a), int(b)) for a, b in re.findall(r'\{(\d+), (\d+)\}', re.search(r'bowMean = \{(.*?)\},\n\t\twandMean', cfg, re.S).group(1))]
check(bow == list(zip(GS.WEAPON_ANCHORS, GS.WEAPON_CURVES['bow'])), 'caster.bowMean is the bow curve of the install tool')

# ---- an install made with the OLD numbers moves to the new ones, a second run changes nothing
MANIFESTS = {
    'gear sets': (GS, lambda: GS.rows_of(GS.DEFAULT_MANIFEST), '<items>\n</items>\n', '<weapons>\n</weapons>\n'),
    'weapons800': (W8, lambda: W8.rows_of(), '<items>\n</items>\n', '<weapons>\n</weapons>\n'),
    'relic sets': (RS, lambda: RS.rows_of(), '<items>\n</items>\n', '<weapons>\n</weapons>\n'),
}
for label, (mod, rows_fn, items0, weapons0) in MANIFESTS.items():
    with GS.old_weapon_curves():
        old_rows = rows_fn()
        old_items, _ = mod.patch_xml(items0, old_rows)[:2]
        old_weapons, _ = mod.patch_weapons(weapons0, old_rows)[:2]
    new_rows = rows_fn()
    new_items, note_i = mod.patch_xml(old_items, new_rows)[:2]
    new_weapons, note_w = mod.patch_weapons(old_weapons, new_rows)[:2]
    fresh_items = mod.patch_xml(items0, new_rows)[0]
    fresh_weapons = mod.patch_weapons(weapons0, new_rows)[0]
    check(old_items != new_items and old_weapons != new_weapons, label + ': the old install differs from the new numbers')
    check(new_items == fresh_items and new_weapons == fresh_weapons, label + ': the run over the old install gives what a fresh install gives')
    check(mod.patch_xml(new_items, new_rows)[0] == new_items and mod.patch_weapons(new_weapons, new_rows)[0] == new_weapons,
          label + ': a second run changes nothing')
    check('rewritten' in note_i or 'rewritten' in note_w, label + ': the block is rewritten (%s)' % note_i)

# the fist weapons
fist_rows = FW.rows_of(FW.DEFAULT_MANIFESTS)
check(all(int(r['ex']['attack']) == WG.grown(int(r['ex']['attack_before']), int(r['ex']['level'])) for r in fist_rows), 'fist weapons: attack = the CSV x a(level)')
check(any(int(r['ex']['attack']) > int(r['ex']['attack_before']) for r in fist_rows), 'some fist weapons grew')
x0 = '<items>\n</items>\n'
old_text = None
saved = WG.WEAPON_GROWTH
WG.WEAPON_GROWTH = tuple((lv, 1.0) for lv, _ in saved)   # the attack of before: a = 1 everywhere
old_text = FW.patch_xml(x0, FW.rows_of(FW.DEFAULT_MANIFESTS))[0]
WG.WEAPON_GROWTH = saved
new_text, note = FW.patch_xml(old_text, FW.rows_of(FW.DEFAULT_MANIFESTS))
check(new_text != old_text and 'rewritten' in note and FW.patch_xml(new_text, FW.rows_of(FW.DEFAULT_MANIFESTS))[0] == new_text,
      'fist weapons: the old install is rewritten, a second run changes nothing')

# ---- the growth table (the upgrade on touch)
types, uniques = GG.type_rows(), GG.unique_rows()
check(len(types) > 150 and len(uniques) == len(WG.OLD_UNIQUE_ATTACK), 'the growth table lists %d types and %d uniques' % (len(types), len(uniques)))
check(all(o != n for o, n in list(types.values()) + list(uniques.values())), 'only changed rows are listed')
check(types[36657] == (50, 65) and types[36659] == (62, 100), 'fist weapons: 50 -> 65, 62 -> 100')
check(subprocess.run([sys.executable, '-I', os.path.join(HERE, 'gen_weapon_growth.py'), '--check']).returncode == 0, 'chaos_weapon_growth.lua is up to date')
# every set weapon of a level above 100 is in the table (its physical attack changed), none of level 100 or less
by_level = {r['server_id']: r['level'] for r in GS.rows_of(GS.DEFAULT_MANIFEST)}
for sid, (o, n) in types.items():
    if sid in by_level:
        check(by_level[sid] > 100, 'set weapon %d: level %d above 100' % (sid, by_level[sid]))
# the uniques: new = old x a(level) (the equip level or the "Requires level" of the description)
text = open(os.path.join(SERVER, 'data', 'items', 'chaos_items.xml'), encoding='utf-8').read()
for m in re.finditer(r'<item id="(\d+)"[^>]*>(.*?)</item>', text, re.S):
    uid, body = int(m.group(1)), m.group(2)
    a = re.search(r'key="attack" value="(\d+)"', body)
    if not a:
        continue
    el = re.search(r'key="equipLevel" value="(\d+)"', body)
    rq = re.search(r'Requires level (\d+)', body)
    lvl = int(el.group(1)) if el else int(rq.group(1))
    old = WG.OLD_UNIQUE_ATTACK.get(uid)
    if old is not None:
        check(int(a.group(1)) == WG.grown(old, lvl), 'unique %d: %s = %d x a(%d)' % (uid, a.group(1), old, lvl))
    else:
        check(WG.grown(int(a.group(1)), lvl) == int(a.group(1)), 'unique %d (level %d) was not changed by the growth, so it stays' % (uid, lvl))

# ---- the generated base wands are grown from the CSV's numbers before
r = subprocess.run([sys.executable, '-I', os.path.join(HERE, 'gen_base_wands.py'), '--check'], stdout=subprocess.PIPE, universal_newlines=True)
check(r.returncode == 0, 'chaos_base_wands.lua is up to date: ' + r.stdout.strip())

print('weapon_growth_test: ' + ('%d failed' % fails if fails else 'ok'))
sys.exit(1 if fails else 0)
