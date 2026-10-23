#!/usr/bin/env python3
"""The Infinity Tower model (server/tools/tower_model.py; server/README.md "Infinity Tower balance and floor rewards").

usage: python3 -I server/tools/tower_model_test.py

- the config is read: pools, bosses with their heals, the curves, the sawtooth, the limits;
- the tier factor: no tiers is 1.0, the modifiers' health effect is read from monster_tiers.lua (Juggernaut, Stoneskin);
- the planner of 2026-10-22 reproduces the beta report: the median class at level 800 gets stuck at floor 29, because the
  floor 30 boss (Zeburoth, 1,750 health a second) out-heals its one-target damage;
- the committed config passes --check, and its `health` / `bossHealth` / `damage` lines are what --derive prints;
- a floor with the health doubled, a boss that heals more than the class deals, a missing breather and a wrong damage
  curve each fail --check;
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
check(t30[2] == float('inf'), 'before: the floor 30 boss out-heals a level 800 median class')
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
health, boss_health, damage = T.derive(cfg, info)
for line in (health, boss_health, damage):
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
