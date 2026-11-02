"""Tests for survival_model.py (O367): the game formulas it copies, the parsers on synthetic data, the Lua dump under both
interpreters, the shipped config inside its limits, and the before / after of the Ninja guard.

Run: python3 -I server/tools/survival_model_test.py
"""
import json
import os
import shutil
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import survival_model as M

fails = 0


def ok(cond, what):
    global fails
    if not cond:
        fails += 1
        print('FAIL ' + what)


# ---- formulas
d = M.dump([757])
eff = d['effects']
ok(M.char_stat(eff, 0, 'vitality') == 0, 'no vitality points, no health')
ok(abs(M.char_stat(eff, 50, 'vitality') - 40) < 1e-9, 'vitality 50 = +40% (the knee: 80% of 50)')
ok(abs(M.char_stat(eff, 100, 'vitality') - 50) < 1e-9, 'vitality 100 = +50% (the cap)')
ok(50 < M.char_stat(eff, 200, 'vitality') < 70, 'past the cap the soft cap still adds')
ok(M.absorb(eff, 157) == eff['maxAbsorb'] == 75, 'absorb is held at maxAbsorb')
ok(M.absorb(eff, 7.6) == 7, 'absorb is a whole percent')
ok(abs(M.armour_reduction(250, 250, 80) - 0.5) < 1e-9, 'armour K: half at K')
ok(M.armour_reduction(10 ** 6, 250, 80) == 0.8, 'armour cap')
pts = [{'level': 150, 'percent': 0}, {'level': 300, 'percent': 14}, {'level': 650, 'percent': 30}]
ok(M.boost_percent(pts, 100) == 0 and M.boost_percent(pts, 1000) == 30 and M.boost_percent(pts, 225) == 7,
   'the late boost lookup (monster_damage_core.lua percentFor)')

# ---- parsers
curves, fit = M.gear_curves()
ok(M.lin(curves['armor'], 1000) == 25 and M.lin(curves['armor'], 8) == 7, 'body armour curve of install_gear_sets.py')
ok(fit == {'H': 1.0, 'M': 0.9, 'C': 0.8, 'A': 0.9}, 'FIT_SHARE')
varm = M.vocation_armour()
ok(varm.get(13) == 1.1 and varm.get(14) == 0.9 and varm.get(12) == 1.0, 'vocation armour factors')
xml = '''<monster name="Test Brute"><level min="740" max="760"/><attacks>
<attack name="melee" interval="2000" min="-100" max="-300"/>
<attack name="physical" interval="2000" chance="50" range="7" min="-200" max="-400"/>
<attack name="fire" interval="1000" chance="20" range="7" min="-100" max="-100"/>
</attacks></monster>'''
lv, atk = M.parse_monster(xml)
ok(lv == 750, 'the monster level is the middle of <level> (engine patch 0082)')
ok([a['kind'] for a in atk] == ['melee', 'physical', 'element'], 'attack kinds')
ok(atk[0]['chance'] == 100 and atk[0]['mean'] == 200, 'melee always fires, the mean of min and max')
pool = '\t\t{name = "Test Brute", level = 750, exp = 1, health = 1, spawns = 10, look = 1},\n' \
       '\t\t{name = "Far Away", level = 900, exp = 1, health = 1, spawns = 10, look = 1},\n\tbosses = {}'
h = M.hunt(750, 30, pool, {'test brute': (lv, atk), 'far away': (900, atk)})
ok([m[0] for m in h] == ['Test Brute'], 'the hunt takes the pool monsters within the band')
bal = d['balance']
one = M.monster_dps(d, bal, 750, atk)
base = (1 + bal['engineBonus'] * 750) * M.lin(d['pace']['damage'], 750) * bal['tierMean']
ok(abs(one['melee'] - 100 * base * 1.3) < 1e-6, 'melee: engine bonus x pace x tier x boost')
ok(abs(one['physical'] - 75 * base * 1.3) < 1e-6, 'physical spell: chance and boost')
ok(abs(one['element'] - 20 * base) < 1e-6, 'elemental spell: no boost')

# ---- the real hunt at 750: the owner's screenshot (Cursed Ape, Gallows Oak 750, Grove Keeper 700)
res = M.table()
t750 = res[750]
names = [m[0] for m in t750['monsters']]
ok('Cursed Ape' in names and 'Gallows Oak' in names, 'the 750 hunt holds the screenshot monsters')
ape = next(m for m in t750['monsters'] if m[0] == 'Cursed Ape')
ok(700 < sum(M.monster_dps(d, bal, ape[2], ape[3]).values()) < 780, 'a Cursed Ape hits ~737/s before armour')

# ---- the cause: the Ninja's tree lanes
nb = d['builds']['ninja']['757']
ok(max(b['vitality'] for b in nb) < 25 and max(b['absorbPhysical'] for b in nb) < 20,
   'the Ninja builds hold almost no vitality or physical absorb at 757')
peers = [max(b['vitality'] for b in d['builds'][c]['757']) for c in M.ORDER if c != 'ninja' and c != 'thief']
ok(min(peers) >= 20 and sorted(peers)[len(peers) // 2] >= 90, 'the other classes reach 90+ vitality (median build)')

# ---- the Lua dump under both interpreters, and the guard read from classes.lua
outs = []
for exe in ('luajit', 'lua5.3'):
    if shutil.which(exe):
        outs.append(subprocess.run([exe, 'tools/survival_numbers.lua', '100', '757'], cwd=M.SERVER, check=True,
                                   capture_output=True, text=True).stdout)
ok(len(outs) < 2 or outs[0] == outs[1], 'survival_numbers.lua prints the same under luajit and lua5.3')
g = json.loads(outs[0])['guardAt'] if outs else d['guardAt']
gp = d['guard']['points']
ok(abs(g['12']['757'] - M.lin(gp, 757)) < 1e-9 and g['11']['757'] == 0 and g['13']['757'] == 0,
   'the guard: the Ninja only, by its points')

# ---- the check: today passes, the state before the guard fails on the Ninja only
ok(M.check(res, bal) == [], 'the shipped config passes --check: %s' % M.check(res, bal))
before = M.table(overrides=M.LEGACY)
errs = M.check(before, bal)
ok(len(errs) == len(bal['levels']) and all('Ninja' in e for e in errs), 'before the guard: the Ninja fails at every level')
for hl in bal['levels']:
    b, a = before[hl], res[hl]
    rb = b['rows']['ninja']['burst'] / b['median']['burst']
    ra = a['rows']['ninja']['burst'] / a['median']['burst']
    ok(rb < 0.45 <= ra, 'hunt %d: the Ninja %.2f -> %.2f of the median class' % (hl, rb, ra))
    ok(0.55 <= ra <= 0.8, 'hunt %d: the Ninja lands with its no-shield peers, not above them (%.2f)' % (hl, ra))
    others = [c for c in M.ORDER if c != 'ninja']
    ok(all(abs(b['rows'][c]['damage'] - a['rows'][c]['damage']) < 1e-6 for c in others), 'hunt %d: no other class changes' % hl)
    ok(a['median']['sustain'] >= bal['sustainMin'], 'hunt %d: the median class out-heals the pack' % hl)

print('survival_model_test: %s' % ('%d failure(s)' % fails if fails else 'OK'))
sys.exit(1 if fails else 0)
