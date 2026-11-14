#!/usr/bin/env python3
"""Vael Ashmourn, the solo boss of the main quest (O551; computed, not measured): can all 21 classes solo it at level 500?

usage: python3 -I server/tools/mainquest_boss_model.py [--check]

The boss is the spell trial "mq" of the Vocation Trials (trials_config.lua spellTiers). Its health is hp of the Merciless tier x hpShare at
the tier's minimum level (x (level / minLevel) ^ hpExponent above it). The damage a class deals to a boss is class_dps_model.py's one
target number times what a boss lets through (boss_length_model.kept('boss')), the same rule that gives the dungeon bosses their 150 s.
--check holds:
  typical     the median class kills it in 150 s +-10% (the dungeon boss length) at level 500
  weakest     the weakest of the 21 classes (and the median at 700, the top of the tier's window) needs at most 70% of the time limit
  spread      the weakest class deals at least 60% of the median (so the plan does not rest on the spread the class model holds, +-25%)
  hit         a hit of the boss is at most the Cruel Trial's share of the maximum health before the resistance (0.09), lives 3, the time
              limit between 300 and 420 s (the three spell trials: 300 / 360 / 420)
  attacks     (O554) Vael's own attacks (data/scripts/chaos/mainquest_boss_config.lua, the source of their numbers): 4 to 6 of them, every
              phase has some, the last phase has one of two shapes; a windup of at least 1.8 s (the telegraph the player reacts to), the
              biggest single hit (enraged) at most the tier's zone / pyre share (0.24 of the maximum health, before the resistance);
              the load they add, share of the maximum health per second at the dodge share the model assumes (typical 75%, poor 50%
              of the attacks stepped out of), at most a quarter of Vael's melee load (the tier's hit every 2 s) at the typical dodge and
              40% at the poor one, in every phase and enraged; each attack is at least a windup + 2 s after the one before
The boss's four phases, the resistance of their element and the door are tested in tests/mainquest_boss_test.lua (lua, mocked engine); the
attack shapes (tile sets, fairness, timing, only the tiles hit take damage) in tests/mainquest_boss_attacks_test.lua.
"""
import json
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)
import boss_length_model as BL  # noqa: E402
import class_dps_model as CD  # noqa: E402

CHAOS = os.path.join(HERE, '..', 'data', 'scripts', 'chaos')
LEVEL = 500
TYPICAL_SECONDS, TYPICAL_TOL = BL.BOSS_SECONDS, 0.10
MAX_TIME_SHARE = 0.70
MIN_SPREAD = 0.60
MAX_HIT = 0.09
# O554: the attacks
MIN_WIND_MS = 1800
MAX_ATTACKS, MIN_ATTACKS = 6, 4
MELEE_EVERY_S = 2.0  # Vael's melee: the tier's hit every 2 s (the Trial Warden's attack interval)
MAX_LOAD_TYPICAL, MAX_LOAD_POOR = 0.25, 0.40  # of the melee load


def read(name):
    with open(os.path.join(CHAOS, name), encoding='utf-8') as f:
        return f.read()


def tier():
    text = read('trials_config.lua')
    merc = re.search(r'key = "merciless", name = "Merciless", minLevel = \d+, maxLevel = \d+, hp = (\d+)', text)
    exp = float(re.search(r'hpExponent = ([0-9.]+)', text).group(1))
    row = re.search(r'\{key = "mq", name = "[^"]+", minLevel = (\d+), maxLevel = (\d+), hpShare = ([0-9.]+), hit = ([0-9.]+), addHit = ([0-9.]+),\s*'
                    r'time = (\d+), lives = (\d+)', text)
    pyre = re.search(r'\{key = "mq".*?pyreShare = ([0-9.]+), zoneShare = ([0-9.]+)', text, re.S)
    if not merc or not row:
        raise SystemExit('trials_config.lua: the mq spell tier or the Merciless hp was not found')
    return {'merc_hp': int(merc.group(1)), 'exp': exp, 'min': int(row.group(1)), 'max': int(row.group(2)), 'share': float(row.group(3)),
            'hit': float(row.group(4)), 'time': int(row.group(6)), 'lives': int(row.group(7)),
            'floor_share': max(float(pyre.group(1)), float(pyre.group(2))) if pyre else 0.0}


def attacks():
    """Vael's attack table from the Lua config (tools/mainquest_boss_numbers.lua)"""
    lua = os.environ.get('LUAJIT', 'luajit')
    out = subprocess.run([lua, 'tools/mainquest_boss_numbers.lua'], cwd=os.path.join(HERE, '..'), check=True, capture_output=True, text=True).stdout
    return json.loads(out)


def hit_share(a, enraged_mult=1.0):
    """the most one use takes (a character on every shape of it), share of the maximum health before the resistance"""
    return sum(p['share'] for p in a['parts']) * enraged_mult


def period_s(c, phase, a, enraged):
    """seconds from the start of one attack to the start of the next in a phase (mirrors ChaosVaelAttacks.delayAfter)"""
    every = c['every'][min(max(1, phase), len(c['every'])) - 1]
    if enraged:
        every = int(every * c['enrage']['cadenceMult'] + 0.5)
    return max(every, a['windMs'] + c['gapMs']) / 1000.0


def phase_load(c, phase, dodge, enraged):
    """share of the maximum health per second the attacks of a phase take at a dodge share: the mean use of the phase's attacks"""
    mine = [a for a in c['attacks'] if phase in a['phases']]
    if not mine:
        return 0.0
    mult = c['enrage']['damageMult'] if enraged else 1.0
    return sum(hit_share(a, mult) * (1 - dodge) / period_s(c, phase, a, enraged) for a in mine) / len(mine)


def attack_problems(t, c):
    bad = []
    atk = c['attacks']
    if not c['enabled']:
        bad.append('attacks: the switch is off')
    if not MIN_ATTACKS <= len(atk) <= MAX_ATTACKS:
        bad.append('attacks: %d of them (4 to 6)' % len(atk))
    if c['minWindMs'] < MIN_WIND_MS:
        bad.append('attacks: minWindMs %d is below %d' % (c['minWindMs'], MIN_WIND_MS))
    if c['gapMs'] < 1000:
        bad.append('attacks: a quiet gap of %d ms is under a second' % c['gapMs'])
    for a in atk:
        if a['windMs'] < MIN_WIND_MS:
            bad.append('attacks: %s winds up %d ms (at least %d)' % (a['key'], a['windMs'], MIN_WIND_MS))
        if a['windMs'] > 3500:
            bad.append('attacks: %s winds up %d ms (over 3.5 s: it stops being a threat)' % (a['key'], a['windMs']))
        if len(a['parts']) > 2:
            bad.append('attacks: %s has %d shapes (at most 2)' % (a['key'], len(a['parts'])))
        top = hit_share(a, c['enrage']['damageMult'])
        if top > t['floor_share'] + 1e-9:
            bad.append('attacks: %s takes %.3f of the maximum health at most (enraged), the tier allows %.2f' % (a['key'], top, t['floor_share']))
    for phase in range(1, 5):
        mine = [a for a in atk if phase in a['phases']]
        if not mine:
            bad.append('attacks: phase %d has none' % phase)
    if not any(len(a['parts']) == 2 and a['parts'][0]['kind'] != a['parts'][1]['kind'] and 4 in a['phases'] for a in atk):
        bad.append('attacks: the last phase has no attack of two different shapes')
    melee = t['hit'] / MELEE_EVERY_S
    for phase in range(1, 5):
        for enraged in (False, True):
            if enraged and phase != 4 and phase != 3:
                continue
            typical = phase_load(c, phase, c['dodge']['typical'], enraged)
            poor = phase_load(c, phase, c['dodge']['poor'], enraged)
            tag = 'phase %d%s' % (phase, ' enraged' if enraged else '')
            if typical > melee * MAX_LOAD_TYPICAL:
                bad.append('attacks: %s adds %.4f of the maximum health a second at the typical dodge (%.0f%%), over %.0f%% of the melee %.4f' % (
                    tag, typical, c['dodge']['typical'] * 100, MAX_LOAD_TYPICAL * 100, melee))
            if poor > melee * MAX_LOAD_POOR:
                bad.append('attacks: %s adds %.4f a second at the poor dodge (%.0f%%), over %.0f%% of the melee %.4f' % (
                    tag, poor, c['dodge']['poor'] * 100, MAX_LOAD_POOR * 100, melee))
    if not 0 < c['dodge']['poor'] < c['dodge']['typical'] < 1:
        bad.append('attacks: the dodge shares must satisfy 0 < poor < typical < 1')
    return bad


def attack_table(t, c):
    out = ['', '| Attack | phases | shapes | windup | most one use takes | enraged | uses in the median kill | takes at typical / poor dodge |',
           '|---|---|---|---:|---:|---:|---:|---:|']
    seconds_median = seconds(t, LEVEL, CD.median_dps(LEVEL)[0])
    for a in c['attacks']:
        uses = sum(seconds_median / 4 / period_s(c, ph, a, False) / len([x for x in c['attacks'] if ph in x['phases']]) for ph in a['phases'])
        top = hit_share(a)
        out.append('| %s | %s | %s | %.1f s | %.0f%% | %.0f%% | %.1f | %.0f%% / %.0f%% of the maximum health |' % (
            a['key'], ','.join(str(p) for p in a['phases']), ' + '.join(p['kind'] for p in a['parts']), a['windMs'] / 1000.0, top * 100,
            hit_share(a, c['enrage']['damageMult']) * 100, uses, uses * top * (1 - c['dodge']['typical']) * 100,
            uses * top * (1 - c['dodge']['poor']) * 100))
    out.append('')
    out.append('| Phase | load at typical dodge | at poor dodge | enraged (typical / poor) | share of Vael\'s melee load (typical) |')
    out.append('|---|---:|---:|---:|---:|')
    melee = t['hit'] / MELEE_EVERY_S
    for phase in range(1, 5):
        ty, po = phase_load(c, phase, c['dodge']['typical'], False), phase_load(c, phase, c['dodge']['poor'], False)
        et, ep = phase_load(c, phase, c['dodge']['typical'], True), phase_load(c, phase, c['dodge']['poor'], True)
        out.append('| %d | %.4f / s | %.4f / s | %.4f / %.4f | %.0f%% |' % (phase, ty, po, et, ep, ty / melee * 100))
    return out


def health(t, level):
    lvl = max(t['min'], min(t['max'], level))
    return t['merc_hp'] * t['share'] * (lvl / float(t['min'])) ** t['exp']


def seconds(t, level, dps1):
    return health(t, level) / (dps1 * BL.kept('boss'))


def table():
    t = tier()
    out = ['| Class | 1 target at %d | seconds to kill | share of the time limit |' % LEVEL, '|---|---:|---:|---:|']
    rows = []
    for name in CD.KEY:
        d = CD.dps(name, LEVEL)[0]
        rows.append((seconds(t, LEVEL, d), name, d))
    for s, name, d in sorted(rows):
        out.append('| %s | %.0f | %.0f | %.0f%% |' % (name, d, s, s / t['time'] * 100))
    med = CD.median_dps(LEVEL)[0]
    out.append('| median | %.0f | %.0f | %.0f%% |' % (med, seconds(t, LEVEL, med), seconds(t, LEVEL, med) / t['time'] * 100))
    return out, rows, t


def problems():
    out, rows, t = table()
    bad = []
    med = CD.median_dps(LEVEL)[0]
    typical = seconds(t, LEVEL, med)
    if abs(typical - TYPICAL_SECONDS) > TYPICAL_SECONDS * TYPICAL_TOL:
        bad.append('the median class needs %.0f s at level %d (plan %d s +-%d%%): hpShare is %.2f' % (typical, LEVEL, TYPICAL_SECONDS,
                                                                                                   TYPICAL_TOL * 100, t['share']))
    worst_s, worst_name, worst_d = max(rows)
    if worst_s > t['time'] * MAX_TIME_SHARE:
        bad.append('%s needs %.0f s of the %d s limit (more than %d%%)' % (worst_name, worst_s, t['time'], MAX_TIME_SHARE * 100))
    if min(d for _, _, d in rows) < med * MIN_SPREAD:
        bad.append('a class deals less than %d%% of the median' % (MIN_SPREAD * 100))
    top = seconds(t, t['max'], CD.median_dps(t['max'])[0])
    if top > t['time'] * MAX_TIME_SHARE:
        bad.append('the median class needs %.0f s at level %d, the top of the window' % (top, t['max']))
    if t['hit'] > MAX_HIT + 1e-9:
        bad.append('a hit of %.3f of the maximum health is above the Cruel Trial\'s %.2f' % (t['hit'], MAX_HIT))
    if t['lives'] != 3 or not 300 <= t['time'] <= 420:
        bad.append('3 lives and 300-420 s are the spell trials\' rule (got %d lives, %d s)' % (t['lives'], t['time']))
    if t['min'] != 500:
        bad.append('the tier starts at level 500, the second resistance mark')
    bad += attack_problems(t, attacks())
    return bad


def main(argv):
    out, _, t = table()
    if '--check' not in argv:
        print('health at level %d: %.0f (hpShare %.2f)' % (LEVEL, health(t, LEVEL), t['share']))
        print('\n'.join(out + attack_table(t, attacks())))
    bad = problems()
    for b in bad:
        sys.stderr.write('mainquest_boss_model: %s\n' % b)
    if bad:
        return 1
    if '--check' in argv:
        print('mainquest_boss_model: ok')
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
