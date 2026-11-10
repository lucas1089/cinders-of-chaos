#!/usr/bin/env python3
"""Tests of pvp_model.py (O444): the config parsers, the PvP rules read from the configs, the formulas on synthetic numbers, the
limits and their exceptions, and the shipped state.

usage: python3 -I server/tools/pvp_model_test.py   (luajit for the survival numbers, as survival_model_test.py)
"""
import os
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import pvp_model as P  # noqa: E402

fails = 0


def ok(cond, msg):
    global fails
    if not cond:
        fails += 1
        print('FAIL ' + msg)


text = P.read(P.CONFIG)
cfg = P.config()

# ---- the config file
ok(cfg['levels'] == [100, 500, 1000], 'levels 100, 500, 1000')
for k in ('burstSeconds', 'drawBand', 'physicalShare', 'burstMax', 'killMin', 'killMax', 'dieMin', 'sustainMax', 'duelShareMax'):
    ok(k in cfg, 'config: %s is read' % k)
ok(0 < cfg['drawBand'] < 0.5 and 0 < cfg['physicalShare'] < 1 and cfg['killMin'] < cfg['killMax'], 'config: sane parameters')
ok(cfg['exceptions']['Deadeye@1000']['burst'] > cfg['burstMax'], 'config: an exception row is read and is above the limit')
ok(all(k.split('@')[0] in P.NAMES for k in cfg['exceptions']), 'config: every exception names a class')
ok(all(int(k.split('@')[1]) in cfg['levels'] for k in cfg['exceptions'] if '@' in k), 'config: every exception level is a level of the table')
ok(text.count('-- O444:') >= 4 and 'COMPUTED, NOT MEASURED' in text, 'config: the exceptions carry O444 notes and it says computed')
for lua in ('luajit', 'lua5.3'):
    if shutil.which(lua):
        r = subprocess.run([lua, '-e', 'local c = dofile("%s"); assert(c.killMin and c.exceptions and c.levels[1] == 100)' % P.CONFIG],
                           capture_output=True, text=True)
        ok(r.returncode == 0, 'config: parses in %s: %s' % (lua, r.stderr.strip()))

# ---- the rules of the configs
rule = P.rules()
ok(rule['fightSeconds'] == 300 and rule['levelRatio'] == 0.8, 'arena: a fight of 300 s, level ratio 0.8')
ok(rule['healingTaken'] == 0.70 and rule['windowMs'] == 10000, 'healing_rules_core.lua: PvP healing x0.70')
ok(rule['normalise'] == (0.8, 0.6, 1.6), 'battleground: normalise exponent 0.8, factors 0.6 .. 1.6')
ok(rule['paceSkipsPvp'], 'pace_config.lua still says PvP is never touched (the model adds no pace factor)')
ok(P.ENGINE_PVP_DAMAGE == 0.5, 'the engine halves damage between players')
for lo, hi, ref in ((100, 299, 200), (300, 599, 450), (600, 899, 750), (900, 2000, 1000)):
    for lv in (lo, (lo + hi) // 2, hi):
        ok(0.95 <= P.normalise(lv, lv, ref, rule['normalise']) <= 1.05,
           'normalise: two players of level %d in bracket %d are within 5%% of x1' % (lv, lo))
ok(P.normalise(500, 1000, 1000, rule['normalise']) == 1.6 and P.normalise(1000, 500, 1000, rule['normalise']) == 0.6,
   'normalise: a weaker source is scaled up and a stronger target takes more, both clamped (1.6 and 0.6)')

# ---- the formulas, on synthetic layers
flat = {'pool': 1000.0, 'health': 1000.0, 'armourRed': 0.0, 'absorbPhys': 0.0, 'absorbElem': 0.0, 'dodge': 0.0, 'toughness': 1.0,
        'guard': 0.0, 'heal': 0.0}
ok(P.mitigation(flat, 0.5) == 1.0, 'mitigation: no layers lets everything through')
armoured = dict(flat, armourRed=0.5, absorbPhys=0.5)
ok(abs(P.mitigation(armoured, 1.0) - 0.25) < 1e-9 and P.mitigation(armoured, 0.0) == 1.0,
   'mitigation: armour and physical absorb stop only the physical share')
ok(abs(P.mitigation(dict(flat, absorbElem=0.4, toughness=0.5, guard=0.2), 0.0) - 0.6 * 0.5 * 0.8) < 1e-9,
   'mitigation: elemental absorb, toughness and guard')
ok(abs(P.mitigation(dict(flat, dodge=0.2), 1.0) - 0.8) < 1e-9, 'mitigation: dodge is physical only')
ok(P.incoming(100, flat, 0.5) == 50, 'incoming: the engine halves the damage between players')
ok(P.kill_time(1000, 100, 0) == 10 and P.kill_time(1000, 100, 50) == 20 and P.kill_time(1000, 100, 100) == P.INF
   and P.kill_time(1000, 100, 150) == P.INF, 'kill_time: pool over the net damage, never when the healing wins')
ok(P.share_left(1000, 100, 0, 5) == 0.5 and P.share_left(1000, 100, 200, 5) == 1.0 and P.share_left(1000, 100, 0, 50) == 0.0,
   'share_left: the health share after some seconds, 1 when the healing wins')
band, fight = 0.10, 300
# duel(pool_a, in_a, heal_a, pool_b, in_b, heal_b): in_x is what X takes a second
ok(P.duel(1000, 50, 0, 1000, 100, 0, fight, band) == 'win', 'duel: A takes 50 a second and B 100: A lives twice as long and wins')
ok(P.duel(1000, 100, 0, 1000, 50, 0, fight, band) == 'loss', 'duel: the same the other way round is a loss')
ok(P.duel(1000, 100, 0, 1000, 105, 0, fight, band) == 'draw', 'duel: kill times within the draw band are a draw')
ok(P.duel(1000, 100, 0, 1000, 120, 0, fight, band) == 'win', 'duel: 20% faster is a win')
ok(P.duel(1000, 100, 100, 1000, 100, 100, fight, band) == 'draw', 'duel: two classes that out-heal each other draw')
ok(P.duel(1000, 100, 50, 1000, 100, 200, fight, band) == 'loss', 'duel: A is killed, B out-heals it: a loss')
ok(P.duel(100000, 100, 50, 100000, 200, 50, fight, band) == 'win', 'duel: nobody dies inside the fight time, the higher health share wins')
ok(P.duel(100000, 100, 50, 100000, 105, 50, fight, band) == 'draw', 'duel: ... and a small difference is a draw')
mid = P.median_layers([dict(flat, pool=1.0), dict(flat, pool=5.0), dict(flat, pool=100.0)])
ok(mid['pool'] == 5.0 and mid['toughness'] == 1.0, 'median_layers: the median of every layer')

# ---- a table on synthetic numbers: 21 identical classes draw; one stronger class wins every duel
lay = dict(flat, pool=10000.0, heal=0.0)
level = 500
base = {'dps': {(c, level): 2000.0 for c in P.NAMES}, 'burst': {(c, level): 1.5 for c in P.NAMES},
        'layers': {(c, level): dict(lay) for c in P.NAMES}}
syn = dict(cfg, levels=[level], exceptions={})
res = P.solve(base, syn, rule)
r = res[level]['rows']['Warrior']
ok(r['wins'] == 0 and r['losses'] == 0 and r['draws'] == 20, 'identical classes: every duel is a draw')
ok(abs(r['kill0'] - 10000 / (2000 * 0.5)) < 1e-9, 'kill: pool over the damage after the PvP half (10 s)')
ok(abs(r['burst'] - 3 * 2000 * 1.5 * 0.5 / 10000) < 1e-9, 'burst: 3 s x damage x burst factor x PvP half over the median pool')
ok(r['kill1'] == r['kill0'] and r['sustain'] == 0.0, 'no healing: the same time and no sustain')
strong = {k: dict(v) for k, v in base.items()}
strong['dps'][('Deadeye', level)] = 6000.0
res2 = P.solve(strong, syn, rule)
r2 = res2[level]['rows']
ok(r2['Deadeye']['wins'] == 20 and r2['Warrior']['losses'] == 1, 'one stronger class wins its 20 duels, the others lose one')
ok(r2['Deadeye']['burst'] > 1.0, 'a class with 3x the damage (a burst of 1.35) one-shots the median class in the burst window (burst above 1)')
healed = {k: dict(v) for k, v in base.items()}
for c in P.NAMES:
    healed['layers'][(c, level)] = dict(lay, heal=3000.0)  # x0.7 = 2100 a second against 1000 taken
r3 = P.solve(healed, syn, rule)[level]['rows']['Warrior']
ok(r3['kill1'] == P.INF and r3['die1'] == P.INF and abs(r3['sustain'] - 2100.0 / 1000.0) < 1e-9 and r3['kill0'] < P.INF,
   'healing above the damage: never with healing, finite without; sustain is healing over damage')
ok(r3['wins'] == 0 and r3['draws'] == 20 and r3['drawsHeal'] == 20, 'healing above the damage: every duel a draw')

# ---- the limits
ok(P.limit(cfg, 'Warrior', 'burst', 500) == cfg['burstMax'] and P.limit(cfg, 'Warrior', 'wins', 500) == cfg['duelShareMax'] * 20,
   'limit: the general one, the duel share of the 20 duels')
ok(P.limit(cfg, 'Deadeye', 'burst', 1000) == cfg['exceptions']['Deadeye@1000']['burst'] and P.limit(cfg, 'Deadeye', 'burst', 100) == cfg['burstMax'],
   'limit: an exception with a level is for that level only')
own = P.config(text.replace('exceptions = {', 'exceptions = {\n\t\t["Warrior"] = {killMin = 1},', 1))
ok(P.limit(own, 'Warrior', 'killMin', 100) == 1 and P.limit(own, 'Warrior', 'killMin', 1000) == 1,
   'limit: an exception without a level is for every level')
ok(P.passes('killMin', 5, 4) and not P.passes('killMin', 3, 4) and P.passes('burst', 0.5, 0.9) and not P.passes('burst', 0.95, 0.9)
   and not P.passes('killMax', P.INF, 15), 'passes: minimum or maximum, never is over every maximum')
ok(P.problems(res, syn) == [], 'problems: identical classes break no limit')
ok(any('Deadeye level 500, burst' in b for b in P.problems(res2, syn)), 'problems: a one shot class is named')
tight = dict(syn, duelShareMax=0.5)
ok(any('wins' in b for b in P.problems(P.solve(strong, tight, rule), tight)), 'problems: a class that wins more than the share of its duels fails')
nr = P.near(res, dict(syn, killMin=9.5))
ok(any(m == 'killMin' for _, _, m, _, _ in nr), 'near: a class within 10% of a minimum is listed')
ok(P.near(res, syn) == [], 'near: nothing within 10% of the limits of identical classes')

# ---- the shipped state
data = P.inputs(cfg['levels'])
real = P.solve(data, cfg, rule)
ok(sorted(real) == [100, 500, 1000] and all(len(t['rows']) == 21 for t in real.values()), 'the shipped table: 21 classes at 3 levels')
ok(P.problems(real, cfg) == [], 'the shipped state passes its limits: %s' % P.problems(real, cfg)[:3])
for lv, t in real.items():
    ok(all(t['rows'][c]['kill0'] > 0 and t['rows'][c]['burstFactor'] > 0 for c in P.NAMES), 'level %d: positive times and burst factors' % lv)
    ok(4 < t['median']['pool'] / (t['median']['dps'] * 0.5) < 15,
       'level %d: the median class takes seconds, not minutes, to kill the median class' % lv)
    ok(all(t['matrix'][(a, b)] == {'win': 'loss', 'loss': 'win', 'draw': 'draw'}[t['matrix'][(b, a)]] for (a, b) in t['matrix']),
       'level %d: the matrix is symmetric (A beats B when B loses to A)' % lv)
    d, dr, pairs = P.summary(real)[lv]
    ok(d + dr == pairs == 210, 'level %d: 210 pairs, decisive or drawn' % lv)
# every exception is still needed: the class is outside the general limit without it (else delete the row), and holds today's value
for key, row in cfg['exceptions'].items():
    cls, _, lv = key.partition('@')
    for m, lim in row.items():
        general = {'burst': cfg['burstMax'], 'wins': cfg['duelShareMax'] * 20, 'losses': cfg['duelShareMax'] * 20}.get(m)
        v = P.value(real[int(lv)]['rows'][cls], m)
        ok(general is not None and not P.passes(m, v, general),
           'exception %s %s is needed: %s against the general %s' % (key, m, P.fmt(v), P.fmt(general or 0)))
        ok(P.passes(m, v, lim) and v >= 0.9 * lim, 'exception %s %s is today\'s value, not a loose one: %s against %s' % (key, m, P.fmt(v), P.fmt(lim)))
# the finding of O444: every class out-heals the median class with its potions at every level, so no duel is decided by damage once
# anyone drinks. When this fails the healing was fixed: tighten sustainMax in pvp_balance_config.lua to 1.0 and delete this line
ok(all(t['rows'][c]['sustain'] > 1.0 for t in real.values() for c in P.NAMES),
   'O444 finding: sustain is above 1 for all 63 class rows (delete this when it is not)')
ok(P.main(['--check']) == 0, 'the CLI check passes')

if fails:
    print('pvp_model_test: %d failed' % fails)
    sys.exit(1)
print('pvp_model_test: ok')
