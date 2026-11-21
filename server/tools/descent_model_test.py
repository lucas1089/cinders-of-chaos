"""Tests for descent_model.py (O664): the formulas it copies, the candidate list against the real pickTypes, the Lua dump under both
interpreters, the pace factors a Descent monster gets, one room worked by hand, the shipped config inside its limits, and the state
before O664 outside them.

Run: python3 -I server/tools/descent_model_test.py
"""
import os
import shutil
import statistics
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import spell_upgrade_model as _SU  # noqa: E402
_SU.set_mode(False)  # O709: the spell upgrades ship on and a model's default is the upgrades mode; this test holds the switch-off numbers (the model's --check runs both modes in CI)
import descent_model as M
import class_dps_model as CD
import survival_model as S

fails = 0


def ok(cond, what):
    global fails
    if not cond:
        fails += 1
        print('FAIL ' + what)


LEVELS = [100, 500, 1000, 1500]
bal = M.BAL()
ok(bal['levels'] == LEVELS and bal['parties'] == [1, 4], 'the report covers the four bands, solo and the full party')
num = M.numbers(LEVELS)
cfg = num['cfg']
ok(cfg['maxPlayers'] == 4, 'the Descent takes up to 4 players, so the party of the model is 4')
ok(cfg['pace']['enabled'] and cfg['pace']['health'] > 0 and cfg['pace']['damage'] > 0, 'the pace rule is on in the shipped config')

# ---- formulas
ranks = M.rank_factors()
ok(ranks['magic'][0] < ranks['rare'][0] < ranks['legendary'][0], 'rank health grows magic < rare < legendary (monster_tiers.lua)')
h, d = M.tier_mean({'magic': 10, 'rare': 0, 'legendary': 0}, ranks)
ok(abs(h - (1 + 0.1 * (ranks['magic'][0] - 1))) < 1e-9 and abs(d - (1 + 0.1 * (ranks['magic'][1] - 1))) < 1e-9, 'tier mean: 10% magic')
ok(M.tier_mean({}, ranks) == (1.0, 1.0), 'no rank, no factor')
eh, ed = M.elite_mean(cfg, 1, ranks)
ok(abs(eh - (0.7 * ranks['rare'][0] + 0.3 * ranks['legendary'][0])) < 1e-9, 'elite at depth 1: 30% legendary (25 + 5 x 1), the rest rare')
eh12, _ = M.elite_mean(cfg, 12, ranks)
ok(abs(eh12 - (0.15 * ranks['rare'][0] + 0.85 * ranks['legendary'][0])) < 1e-9, 'elite at depth 12: 85% legendary (25 + 5 x 12)')
eh16, _ = M.elite_mean(cfg, 16, ranks)
ok(abs(eh16 - ranks['legendary'][0]) < 1e-9, 'elite from depth 15: every one legendary (the chance stops at 100)')
ok(M.picks_before(bal, 1) == 0 and M.picks_before(bal, 2) == 0 and M.picks_before(bal, 3) == 1 and M.picks_before(bal, 40) == 12,
   'picks before a room: 0.85 a room, none before room 2, at most 12')
vals = M.boon_values(cfg, bal)
ok(abs(vals['ember_edge'][0] - 0.12) < 1e-9 and abs(vals['stoneskin'][1] - 0.10) < 1e-9 and abs(vals['blood_drinker'][2] - 0.05) < 1e-9,
   'boon values read the real table: Ember Edge +12% damage, Stoneskin -10% taken, Blood Drinker 5% leech')
ok(abs(vals['searing_brand'][0] - 0.5 * 0.15 * bal['boons']['physicalShare']) < 1e-9,
   'a brand: the converted half hits 15% harder, x the physical share')
curve = M.boon_curve(cfg, bal)
ok(curve[0] == (1.0, 1.0, 0.0), 'no pick, no boon')
ok(all(curve[i][0] <= curve[i + 1][0] and curve[i][1] >= curve[i + 1][1] for i in range(12)), 'every pick adds damage and takes less damage on average')
ok(1.5 < curve[12][0] < 3.0 and 0.6 < curve[12][1] < 0.95, 'twelve picks: damage x%.2f, taken x%.2f' % (curve[12][0], curve[12][1]))
ok(M.boon_curve(cfg, bal) == curve, 'the boon curve is seeded: the same twice')

# ---- candidates against the real pickTypes
mons = M.Monsters(num, bal, S.dump(LEVELS))
for lv in LEVELS:
    for depth in range(1, 13):
        esc = num['levels'][str(lv)][str(depth)]['esc']
        cand = {m['name'] for m in M.candidates(mons.mons, cfg, esc['window'])}
        drawn = set(num['pick'][str(lv)][str(depth)])
        # a type of the real pool that the model cannot read (no hits at all) is not a candidate; the draw never holds a type outside
        ok(drawn <= cand | {m['name'] for m in mons.mons if m['src'] == 'none'}, 'level %d depth %d: every drawn type is a candidate (%s)' % (
            lv, depth, sorted(drawn - cand)[:3]))
syn = [{'name': 'A', 'level': 100, 'poolHealth': 500, 'src': 'xml'}, {'name': 'B', 'level': 110, 'poolHealth': 500, 'src': 'xml'},
       {'name': 'C', 'level': 300, 'poolHealth': 500, 'src': 'xml'}, {'name': 'D', 'level': 105, 'poolHealth': 50, 'src': 'xml'}]
cc = M.candidates(syn, {'types': 3, 'escalation': {'minPoolHealth': 100, 'widen': 100}}, [95, 120])
ok([m['name'] for m in cc] == ['A', 'B', 'C'] or {m['name'] for m in cc} == {'A', 'B', 'C'},
   'a window with too few types widens by `widen` and skips a pool entry under minPoolHealth: %s' % [m['name'] for m in cc])
cc = M.candidates(syn, {'types': 3, 'escalation': {'minPoolHealth': 100, 'widen': 1}}, [95, 120])
ok({m['name'] for m in cc} == {'A', 'B', 'C'}, 'still too few after five widenings: the nearest levels of the pool fill up')

# ---- the Lua dump under both interpreters
outs = []
for exe in ('luajit', 'lua5.3'):
    if shutil.which(exe):
        outs.append(subprocess.run([exe, 'tools/descent_numbers.lua', '500', '1500'], cwd=M.SERVER, check=True, capture_output=True, text=True).stdout)
ok(len(outs) < 2 or outs[0] == outs[1], 'descent_numbers.lua prints the same under luajit and lua5.3')

# ---- the pace factors of a Descent monster
rows = {r['name']: r for r in num['pool']}
ok(all(abs(r['ph'] - r['hh'] * cfg['pace']['health']) < 1e-9 and abs(r['pd'] - r['hd'] * cfg['pace']['damage']) < 1e-9 for r in rows.values()),
   'a Descent monster gets the hunt factors of its pool entry times the config numbers')
ok(all(r['hh'] <= 1.0 and 0 < r['hd'] <= 1.0 for r in rows.values()), 'the hunt factors are shares (health, damage)')
bag = rows['Mystic Baguemage']
ok(0.07 < bag['hh'] < 0.12 and 0.4 < bag['hd'] < 0.6, 'a level 416 Mystic Baguemage in a hunt: %.3f of its health, %.2f of its damage' % (bag['hh'], bag['hd']))
old = M.numbers(LEVELS, True)
ok(all(r['ph'] == 1 and r['pd'] == 1 for r in old['pool']), 'legacy: no factor, the state before O664')
ok(old['cfg']['pace'] == {'enabled': False}, 'legacy: the pace rule is off')

# ---- calibration of the stock hit rate (no XML for the stock monsters: guardian_hits.csv)
hits = M.read_hits()
ratios = []
for name, (mlv, attacks) in mons.xml.items():
    if name in hits and attacks:
        raw = sum(a['mean'] * a['chance'] / 100.0 / (a['interval'] / 1000.0) for a in attacks)
        base = hits[name]['melee'] + hits[name]['elem']
        if base > 0:
            ratios.append(raw / base)
fit = statistics.median(ratios)
ok(len(ratios) >= 100 and abs(bal['hitRate'] / fit - 1) < 0.15, 'hitRate %.2f against the median of %d level-scaled monsters with both: %.2f' % (bal['hitRate'], len(ratios), fit))
bag_m = next(m for m in mons.mons if m['name'] == 'Mystic Baguemage')
ok(bag_m['src'] == 'csv' and 480 < bag_m['element'] < 600, 'the Mystic Baguemage hits %.0f a second before the layers (the guardian model has 544 for a level 416 stock monster)' % bag_m['element'])
ok(abs(bag_m['health'] - 27500) < 1, 'a stock monster has its pool health')
scaled = next(m for m in mons.mons if m['name'] == 'Geode Seer')
ok(180000 < scaled['health'] < 195000, 'a level-scaled one carries the engine level health: Geode Seer %.0f' % scaled['health'])

# ---- one room worked by hand: a monster with no damage, then one with a lot
ctx = M.context([500])
P = ctx['players']
none = {'health': 10000.0, 'melee': 0.0, 'physical': 0.0, 'element': 0.0, 'hits': 0.0, 'level': 400, 'name': 'dummy', 'pace_health': 10000.0,
        'pace_damage': {'melee': 0.0, 'physical': 0.0, 'element': 0.0}, 'pace_hits': 0.0}
r = M.room(ctx, 'warrior', 500, 1, 1, 'combat', none)
esc = ctx['num']['levels']['500']['1']
plan = esc['plan']['combat']['1']['plain']
th, td = M.tier_mean(esc['esc']['tiers'], ranks)
d1, d5 = CD.dps('Warrior', 500)
s5 = (d5 - d1) / 4.0
m4 = min(plan['size'], 5)
want = plan['waves'] * (plan['size'] * 10000.0 * esc['esc']['health'] * th / (d1 + (m4 - 1) * s5) + bal['waveGap'])
ok(abs(r['clear'] - want) < 1e-6, 'clear time by hand: %.3f against %.3f' % (r['clear'], want))
ok(r['left'] == 1.0 and r['dmg'] == 0 and r['pressure'] == 0, 'a monster with no damage costs nothing')
big = dict(none, pace_damage={'melee': 0.0, 'physical': 0.0, 'element': 50000.0})
rb = M.room(ctx, 'warrior', 500, 1, 1, 'combat', big)
ok(rb['left'] == 0.0 and rb['die'] < 5 and rb['burst'] < 2, 'a monster with 50,000 damage a second: the warrior is dead in seconds (%.1f s)' % rb['die'])
fatter = dict(none, pace_health=20000.0)
rf = M.room(ctx, 'warrior', 500, 1, 1, 'combat', fatter)
ok(rf['clear'] > 1.9 * (r['clear'] - plan['waves'] * bal['waveGap']), 'twice the health, twice the clear time')
ok(M.room(ctx, 'warrior', 500, 4, 1, 'combat', none)['size'] == plan['size'] + 2 * 3, 'a party of 4 meets 2 more monsters a wave per extra player')
elite = M.room(ctx, 'warrior', 500, 1, 3, 'elite', none)
ok(elite['waves'] == 1, 'an elite room is one wave')
boss = M.room(ctx, 'warrior', 500, 1, 8, 'boss', none)
ok(boss['waves'] == 1 and boss['size'] == 1, 'the boss room is one monster')
boss4 = M.room(ctx, 'warrior', 500, 4, 8, 'boss', none)
ok(abs(boss4['health'] / boss['health'] - (cfg['boss']['healthMult'] + 3 * cfg['boss']['perExtraPlayer']) / cfg['boss']['healthMult']) < 1e-9,
   'the boss has more health for a party (healthMult + perExtraPlayer x 3)')

# ---- the potion tier and the self heal of a level below 300 (survival_model.py has the 670-1000 levels)
ok(P.sbal(100)['potionTier'] < P.sbal(500)['potionTier'], 'a level 100 character drinks a lower potion than level 500')
ok(P.sbal(100)['selfHeal']['warrior'][0] < P.sbal(500)['selfHeal']['warrior'][0], 'below level 300 the self heal is scaled by level')

# ---- the shipped config passes --check, and the state before O664 does not
res = M.compute(LEVELS, bal['parties'])
errs = M.check(res)
ok(errs == [], 'the shipped config passes --check: %s' % errs[:3])
before = M.compute(LEVELS, bal['parties'], True)
errs0 = M.check(before)
ok(len(errs0) >= 8, 'before O664 the check fails (%d failures)' % len(errs0))
for lv in LEVELS:
    b = before['levels'][lv]['rooms'][(1, 1, 'combat')]['median']
    a = res['levels'][lv]['rooms'][(1, 1, 'combat')]['median']
    ok(a['clear'] < 0.6 * b['clear'], 'level %d: room 1 clears in %.0f s now, %.0f s before' % (lv, a['clear'], b['clear']))
    ok(a['pressure'] < b['pressure'] and a['pressure'] <= bal['limits']['room1']['pressure'][1], 'level %d: room 1 presses at %.2f x healing now, %.2f before' % (
        lv, a['pressure'], b['pressure']))
    hb = M.hard_pick(before, lv, 1, 1, 'combat', 0.9)
    ha = M.hard_pick(res, lv, 1, 1, 'combat', 0.9)
    ok(hb[0]['left'] < 0.30 <= ha[0]['left'], 'level %d: the hardest tenth of the picks (%s) leaves the median class %.0f%% now, %.0f%% before' % (
        lv, hb[1]['name'], 100 * ha[0]['left'], 100 * hb[0]['left']))
    bd = before['levels'][lv]['rooms'][(1, 8, 'boss')]['median']
    ok(bd['clear'] > bal['limits']['boss']['clear'][1], 'level %d: before, the boss took %.0f s' % (lv, bd['clear']))
    rooms = res['levels'][lv]['rooms']
    ps = [rooms[(1, d, 'combat')]['median']['pressure'] for d in bal['depths']]
    ok(ps[-1] > 2.0 * ps[0], 'level %d: the rooms grow, pressure %.2f at depth 1 to %.2f at depth %d' % (lv, ps[0], ps[-1], bal['depths'][-1]))

# ---- the reports print (--hunt, --curses, the table)
import contextlib
import io
buf = io.StringIO()
with contextlib.redirect_stdout(buf):
    M.report(res)
    M.hunt_report(res)
    M.curses_report(res, {'swarm': True, 'frailty': True, 'withering': True})
out = buf.getvalue()
ok('hunt pack of party level 1500' in out and 'with frailty and swarm and withering taken' in out and out.count('Warrior') >= 4,
   'the reports print the hunt pack, the rooms and the curses')

print('descent_model_test: %s' % ('%d failure(s)' % fails if fails else 'OK'))
sys.exit(1 if fails else 0)
