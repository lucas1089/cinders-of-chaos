#!/usr/bin/env python3
"""The Infinity Tower model (server/tools/tower_model.py; server/README.md "Infinity Tower balance and floor rewards").

usage: python3 -I server/tools/tower_model_test.py

- the config is read: pools, bosses with their heals, the curves, the sawtooth, the limits;
- the tier factor: no tiers is 1.0, the modifiers' health effect is read from monster_tiers.lua (Juggernaut, Stoneskin);
- the planner of 2026-10-22 reproduces the beta report: the median class at level 800 gets stuck at floor 29, because the
  floor 30 boss (Zeburoth, 1,750 health a second) out-heals its one-target damage;
- the committed config passes --check, and its `health` / `bossHealth` / `damage` / `lootShare` / `killGold` lines are what
  --derive prints;
- O328: a monster shown at level L hits like a hunt monster of level L (pace damage x hit(L) over hit(band level)), the hit of
  a level 1200 monster is above the level 100 one's, the tower's items and gold an hour stay at a hunt of the same level;
- a floor with the health doubled, a boss that heals more than the class deals, a missing breather and a wrong damage
  curve each fail --check;
- O172: floors 1-1000 rise strictly (health trend, boss health, damage from floor 52, level), floor 100000 sits on the caps,
  the caps stay under int32, and a flat tower, a repeating boss, a boss dip or a cap past int32 fails --check;
- a group adds damage, a boss floor takes the boss time on top of its helpers, a stronger class clears faster.
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import tower_model as T  # noqa: E402

fails = []


def check(cond, what):
    if not cond:
        fails.append(what)
        print('FAIL ' + what)


def run_check(cfg, info):
    lines = []
    code = T.check(cfg, info, out=lines.append)
    return code, '\n'.join(lines)


cfg = T.balance()
info = T.tier_info(cfg)
text = T.read(T.BALANCE)

# ---- the config
check(len(cfg['pools']) == 7 and all(len(p) == 5 for p in cfg['pools']), 'seven pools of five species')
check([b[0] for b in cfg['bosses']][:2] == ['the ashen count', 'the grey widow'], 'bosses in config order')
check(dict(cfg['bosses'])['zeburoth'] == 1750, 'Zeburoth heals 1,750 a second')
check(len(cfg['sawtooth']) == int(cfg['milestoneEvery']), 'the sawtooth is one climb')
check(sorted(cfg['bossHealth']) == list(range(10, 121, 10)), 'a boss health for every boss floor')
check(cfg['limits']['reachMin'] == 30 and cfg['limits']['reachMax'] == 40, 'a level 800 player gets 30-40 floors deep')

# ---- the tiers
hp, cnt, mod = T.tier_info()
check(hp == {'magic': 2.0, 'rare': 3.5, 'legendary': 6.0}, 'the stock tier health is read from monster_tiers.lua: %s' % hp)
check(cnt == {'magic': 1.5, 'rare': 2.5, 'legendary': 3.5}, 'modifier counts: %s' % cnt)
check(1.0 < mod < 1.4, 'the average modifier adds health: %.3f' % mod)
check(abs(T.tier_factor((0, 0, 0), (hp, cnt, mod)) - 1.0) < 1e-9, 'no tiers: factor 1')
check(T.tier_factor((1, 0, 0), (hp, cnt, 1.0)) == 2.0, 'all magic without modifiers: x2')
check(T.tier_info(cfg)[0] == cfg['tierHealth'] and cfg['tierHealth']['legendary'] < 6.0, 'the tower tier health replaces the stock one')

# ---- the planner of 2026-10-22: the beta report
old = T.legacy_scheme()
oi = T.tier_info()
check(T.reach(old, cfg, 800, oi) == 29, 'before: level 800 stops at floor 29 (reach %d)' % T.reach(old, cfg, 800, oi))
t30 = T.floor_time(old, cfg, 30, [(None, 800)], oi)
# the median class (the middle five) deals 1,865 a second to one boss after the class identity pass, so the 1,750 heal leaves it
# 15 minutes instead of for ever (it was out-healed before the pass)
check(t30[2] > 600, 'before: the floor 30 boss out-heals (all but) a level 800 median class: %.0f s' % t30[2])
check(T.floor_time(old, cfg, 30, [(None, 1500)], oi)[2] < float('inf'), 'before: it dies for a level 1500 player')
check(old['count'](35) == 15 and old['count'](100) == 16, 'before: 15 monsters on floor 35, 16 from floor 36')
check(old['mix'](40)[0] == 0.45 and old['mix'](40)[2] == 0.04, 'before: the tier chances rose with every floor')

# ---- the committed config
new = T.new_scheme(cfg)
code, out = run_check(cfg, info)
check(code == 0, 'the committed config passes --check: ' + out[-400:])
check('tower check: ok' in out, 'it says ok')
check(T.reach(new, cfg, 800, info) in range(30, 41), 'after: level 800 gets to floor %d' % T.reach(new, cfg, 800, info))
for f in range(1, 121):
    t, pack, boss = T.floor_time(new, cfg, f, [(None, T.lin(cfg['level'], f))], info)
    check(t < float('inf'), 'floor %d can be cleared at its level' % f)
    check(t < 300 + 1e-9, 'floor %d is far inside the floor limit (%.0f s of 300 / 600)' % (f, t))
health, boss_health, damage, share, gold = T.derive(cfg, info)
for line in (health, boss_health, damage, share, gold):
    check(line in text, '--derive prints the committed line: ' + line[:60])

# ---- what --check refuses
bad = T.balance(re.sub(r'(?m)^(\thealth = \{\{.*)$', lambda m: re.sub(r'\{(\d+), (\d+)\}',
                                                                      lambda x: '{%s, %d}' % (x.group(1), int(x.group(2)) * 2),
                                                                      m.group(1)), text))
code, out = run_check(bad, T.tier_info(bad))
check(code == 1 and 'FAIL' in out, 'doubled health fails')
nobreath = T.balance(text.replace('sawtooth = {0.75, 0.88, 1.00, 1.10, 1.22}', 'sawtooth = {1.00, 1.00, 1.00, 1.00, 1.00}'))
code, out = run_check(nobreath, T.tier_info(nobreath))
check(code == 1 and 'not a breather' in out, 'a flat sawtooth has no breather')
swapped = T.balance(text.replace('{name = "zeburoth", heal = 1750}', '{name = "zeburoth", heal = 9000}'))
code, out = run_check(swapped, T.tier_info(swapped))
check(code == 1 and 'heals' in out, 'a boss that heals more than the class deals fails')
dmg = T.balance(re.sub(r'(?m)^\tdamage = \{\{.*$', '\tdamage = {{1, 1.0}, {400, 1.0}},', text))
code, out = run_check(dmg, T.tier_info(dmg))
check(code == 1 and 'pace curve' in out, 'monsters that hit like no hunt monster fail')

# ---- O328: damage follows the shown level, loot stays at a hunt of that level
def hit_at(f):
    return T.lin(cfg['hit'], T.band_level(cfg, f)) * T.dmg_at(cfg, f)


f100 = next(f for f in range(1, 121) if T.lin(cfg['level'], f) >= 100)
f1200 = next(f for f in range(1, 121) if T.lin(cfg['level'], f) >= 1200)
f2000 = next(f for f in range(1, 121) if T.lin(cfg['level'], f) >= 2000)
check(hit_at(f1200) > 1.5 * hit_at(f100), 'a monster shown at level 1200 hits %.0f, the level 100 one %.0f' % (hit_at(f1200), hit_at(f100)))
check(hit_at(f2000) > hit_at(f1200), 'level 2000 hits more than level 1200: %.0f against %.0f' % (hit_at(f2000), hit_at(f1200)))
for f in (1, 8, 20, 40, 60, 120):
    want = T.lin(T._PACE_DAMAGE(), T.lin(cfg['level'], f)) * T.lin(cfg['hit'], T.lin(cfg['level'], f)) * T.climb_at(cfg, f)  # the hunt match x the climb (owner 2026-10-29)
    check(abs(hit_at(f) - want) <= cfg['limits']['damageTol'] * want, 'floor %d hits like a hunt monster of its level x the climb: %.0f against %.0f' % (f, hit_at(f), want))
check(T.band_level(cfg, 1) == 11 and T.band_level(cfg, 60) == 100, 'the band levels are the bounty pool medians: %d, %d' % (T.band_level(cfg, 1), T.band_level(cfg, 60)))
check(T.loot_level(cfg, 500) == T.lin(cfg['level'], 120) and T.loot_level(cfg, 10) == 300, 'the loot level is capped at the level of maxFloor')
check(all(0 < s <= 1 for _, s in cfg['lootShare']) and all(g > 0 for _, g in cfg['killGold']), 'lootShare is a share, killGold is positive')
nothin = T.balance(re.sub(r'(?m)^\tlootShare = \{\{.*$', '\tlootShare = {{1, 1.0}},', text))
code, out = run_check(nothin, T.tier_info(nothin))
check(code == 1 and 'items an hour' in out, 'an unthinned tower corpse fails: it gives more items an hour than a hunt')
rich = T.balance(re.sub(r'(?m)^(\tkillGold = \{\{.*)$', lambda m: re.sub(r'\{(\d+), (\d+)\}', lambda x: '{%s, %d}' % (x.group(1), int(x.group(2)) * 3), m.group(1)), text))
code, out = run_check(rich, T.tier_info(rich))
check(code == 1 and 'gold an hour' in out, 'three times the gold per kill fails')
weak = T.balance(re.sub(r'(?m)^\thit = \{\{.*$', '\thit = {{7, 25}, {2200, 25}},', text))
code, out = run_check(weak, T.tier_info(weak))
check(code == 1 and 'pace curve' in out, 'a hit reference that does not follow the levels fails the damage check')

# ---- O172: the tower never stops getting stronger
b = cfg['beyond']
check(b['healthMax'] * cfg['tierHealth']['legendary'] <= b['engineMaxHealth'] <= 2 ** 31 - 1, 'the health cap leaves room for the legendary tier under int32')
check(b['bossHealthMax'] <= b['engineMaxHealth'] and b['levelMax'] <= 2 ** 31 - 1, 'the boss health and level caps are under int32')
check(T.endless(cfg, info) == [], 'the committed config grows strictly to floor %d: %s' % (cfg['limits']['endless'], T.endless(cfg, info)[:3]))
check(T.growth(cfg, 0.007, 0.000002, 120) == 1.0 and T.growth(cfg, 0.007, 0.000002, 1) == 1.0, 'no growth up to maxFloor')
check(T.growth(cfg, 0.007, 0.000002, 10 ** 9) < float('inf'), 'the growth never overflows')
for f in range(1, 1001):
    check(T.hp_at(cfg, f) == T.hp_at(cfg, f) and T.boss_hp_at(cfg, f) <= b['bossHealthMax'], 'floor %d: a finite health under its cap' % f)
check(T.hp_at(cfg, 10 ** 5) == b['healthMax'] and T.boss_hp_at(cfg, 10 ** 5) == b['bossHealthMax'], 'floor 100000: both at their caps')
check(T.dmg_at(cfg, 10 ** 5) == b['damageMax'] and T.boss_dmg_at(cfg, 10 ** 5) == b['damageMax'], 'floor 100000: the damage factor at its cap')
check(T.level_at(cfg, 10 ** 5) == 2200 + b['levelPerFloor'] * (10 ** 5 - 120), 'floor 100000: the level is still linear')
for f in range(121, 1001):
    check(T.trend_hp(cfg, f) > T.trend_hp(cfg, f - 1), 'floor %d: stronger than the floor before' % f)
starts = [T.growth_floor(cfg, b['healthRate'], b['healthAccel'], b['healthMax'] / (T.lin(cfg['health'], 120) * max(cfg['sawtooth'])))]
check(T.hp_at(cfg, starts[0] - 1) < b["healthMax"] == T.hp_at(cfg, (starts[0] + 4) // 5 * 5), 'the health cap starts at floor %d' % starts[0])
flat = T.balance(text.replace('healthRate = 0.007', 'healthRate = 0.0').replace('healthAccel = 0.000002', 'healthAccel = 0.0'))
code, out = run_check(flat, T.tier_info(flat))
check(code == 1 and 'does not rise' in out, 'a tower that stops growing above maxFloor fails')
nodmg = T.balance(text.replace('damageRate = 0.002', 'damageRate = 0.0').replace('damageAccel = 0.000004', 'damageAccel = 0.0'))
code, out = run_check(nodmg, T.tier_info(nodmg))
check(code == 1 and 'damage factor does not rise' in out, 'a damage factor that stops growing fails')
big = T.balance(text.replace('healthMax = 580000000', 'healthMax = 900000000'))
code, out = run_check(big, T.tier_info(big))
check(code == 1 and 'engine limit' in out, 'a health cap that the legendary tier pushes past int32 fails')
early = T.balance(text.replace('healthRate = 0.007', 'healthRate = 0.03'))
code, out = run_check(early, T.tier_info(early))
check(code == 1 and ('cap starts' in out or 'cliff' in out or 'jumps' in out), 'a climb that hits the cap before floor 1000 fails')
repeat = T.balance(text.replace('bossHealthRate = 0.007', 'bossHealthRate = 0.0').replace('bossHealthAccel = 0.000002', 'bossHealthAccel = 0.0'))
code, out = run_check(repeat, T.tier_info(repeat))
check(code == 1 and 'boss floor' in out, 'bosses that repeat their health above maxFloor fail')
dip = T.balance(re.sub(r'\[110\] = \d+', '[110] = 187000', text, count=1))
code, out = run_check(dip, T.tier_info(dip))
check(code == 1 and 'boss floor 110' in out, 'a boss with less health than the one 10 floors before fails (the old 110 dip)')

# ---- the model
solo = T.floor_time(new, cfg, 20, [(None, 540)], info)
pair = T.floor_time(new, cfg, 20, [(None, 540), (None, 540)], info)
check(pair[1] > 0 and solo[1] > 0, 'a floor takes time')
check(T.floor_time(new, cfg, 12, [(None, 540), (None, 540)], info)[1] < T.floor_time(new, cfg, 12, [(None, 540)], info)[1] * 1.6,
      'a second player brings more monsters but also more damage')
check(T.floor_time(new, cfg, 10, [(None, 300)], info)[0] > T.floor_time(new, cfg, 10, [(None, 300)], info)[1],
      'a boss floor takes its helpers and the boss')
strong = max(T.PM.C4, key=lambda c: T.class_dps(c, 800, 7)[0])
weak = min(T.PM.C4, key=lambda c: T.class_dps(c, 800, 7)[0])
check(T.floor_time(new, cfg, 30, [(strong, 800)], info)[1] < T.floor_time(new, cfg, 30, [(weak, 800)], info)[1],
      'the stronger class clears faster')
check(T.sig(123456) == 123000 and T.sig(0.01234) == 0.0123, 'sig keeps three digits')

if fails:
    print('%d FAILED' % len(fails))
    sys.exit(1)
print('tower_model_test: ok')
