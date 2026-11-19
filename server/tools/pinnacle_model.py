#!/usr/bin/env python3
"""The pinnacle boss model (O667; computed, not measured in game; server/README.md "Pinnacle bosses (O667)").

usage: python3 -I server/tools/pinnacle_model.py [--derive] [--check]

Four Ascended versions of existing key bosses (Malgrath, Vhoss the Hexmaw, Talath, Varkhul the Ashen Sovereign), shown at level 2000 /
2500 / 3000 / 3500, a private fight alone or with five, opened by a set of four fragments the top content drops. The model answers
what the owner asked: how long the fight is for the median class alone and in a party, how hard the boss hits against the median
class's healing, and how many fragments an hour of top content gives (hours for a set, for the exclusive unique).

Without a flag: the tables for the committed numbers. --derive: the numbers to commit (health and party curve of each boss, the
profile `ref` of boss_mechanics_config.lua, the XML heal). --check (CI): the committed numbers against the derivation and the limits
of data/scripts/chaos/pinnacle_balance_config.lua (the reason of each is there).

Inputs (everything in the repo): class_dps_model.py through boss_length_model.py (the typical damage on one boss at a level), the
survival model through guardian_model.py (the median class's pool, armour, absorbs and healing at a level, with the damage of the boss
through its layers), the XML of each boss (data/monster/monsters/chaos/pinnacle: its attacks, its health, its healing defense),
boss_mechanics_config.lua (the marked attacks: the share of max health of a telegraph x the share a player still takes, the timed
ones too), pinnacle_config.lua (the committed health, curves, fragments, unique) and pinnacle_balance_config.lua (the planned fight
and the limits). The Lua side is dumped by tools/pinnacle_numbers.lua.

The model, per boss:
  length    the fight's health = seconds x (players x typical damage x uptime - the boss's heal a second): solo 420 s, five 300 s. The
            median class finishes in `seconds`; the weakest class (0.75 of the median) alone inside `weakestShare` of the limit.
  damage    the boss's XML hits through the engine's level bonus (1 + 0.0015 x its level) and the level pace (survival_model.monster_dps),
            plus the marks of its telegraphs (guardian_model.median_class): seconds to die with no healing and the pressure (damage /
            healing) of the median class at the planned level; with five the damage curve on top.
  fragments three kinds from one content each (a waystone map of tier 12+, a rift of tier 15, an Omen guardian), the keystone from any:
            the hours of top content for a set, and for the unique (a roll of its chance, then the bad-luck count: expected kills x sets).
"""
import json
import math
import os
import re
import statistics
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import boss_length_model as BL  # noqa: E402
import guardian_model as GM  # noqa: E402
import survival_model as S  # noqa: E402

SERVER = os.path.normpath(os.path.join(HERE, '..'))
PINNACLE = os.path.join(SERVER, 'data', 'monster', 'monsters', 'chaos', 'pinnacle')
UNIQUES = os.path.join(SERVER, 'data', 'lib', 'chaos_unique_items.lua')
ENGINE_BONUS = 0.0015   # config.lua monsterBonusDamage (guardian_balance_config.lua hit.engineBonus)


def lua_bin():
    return os.environ.get('LUAJIT', 'luajit')


_nums = []


def numbers():
    if not _nums:
        out = subprocess.run([lua_bin(), os.path.join('tools', 'pinnacle_numbers.lua')], cwd=SERVER, check=True, capture_output=True,
                             text=True).stdout
        _nums.append(json.loads(out))
    return _nums[0]


def xml_path(boss):
    return os.path.join(PINNACLE, boss['name'].lower().replace(' ', '_').replace("'", '') + '.xml')


def xml_text(boss):
    return S.read(xml_path(boss))


def xml_health(text):
    m = re.search(r'<health now="(\d+)" max="(\d+)"', text)
    return (int(m.group(1)), int(m.group(2))) if m else (0, 0)


def xml_heal(text):
    """the healing a second of the XML's healing defense: chance x the middle of min and max / the interval"""
    return BL.xml_heal(text)


def xml_hits(text):
    return S.parse_monster(text)[1]


# ------------------------------------------------------------------------------------------------ length
def typical(level):
    """damage a second of the median class on one boss at a level (boss_length_model: armour and resistance of a boss kept)"""
    return BL.one_target(level)


def derive_health(boss, bal, heal):
    d = typical(boss['refLevel'])
    up = bal['uptime']
    solo = bal['seconds']['solo'] * (d * up - heal)
    party = bal['seconds']['party'] * (bal['players'] * d * up - heal)
    return solo, (party / solo - 1) / (bal['players'] - 1)


def kill_seconds(boss, bal, players, heal, dmg_factor=1.0):
    """seconds for `players` of the median class (or `dmg_factor` of it) to kill the committed fight"""
    d = typical(boss['refLevel']) * dmg_factor
    health = boss['health'] * (1 + boss['perExtra'] * (players - 1))
    return health / (players * d * bal['uptime'] - heal)


# ------------------------------------------------------------------------------------------------ damage
def warn_seconds(difficulty):
    """boss_mechanics_core G.warnMs: 3.0 s at difficulty 0 down to 1.5 s at 1 (2.5-3 s up to 0.33)"""
    return max(1.5, 3.0 - 1.5 * min(1.0, difficulty))


def marks_share(profile, players):
    """the marked attacks as a share of the victim's max health a second: the mean telegraph share x marksTaken / the cadence, and
    the timed ones (a soak only for a group) the same way"""
    bal = numbers()['bal']
    taken = bal['marksTaken']
    diff = profile.get('difficulty', 0.2)
    every = max(warn_seconds(diff) + profile.get('gapMs', 1500) / 1000.0, profile.get('every', 9000) * (1 - 0.25 * diff) / 1000.0)
    tel = profile.get('telegraphs') or []
    out = 0.0
    if tel:
        out += statistics.mean(t['share'] for t in tel) * taken / every
    for m in profile.get('timed') or []:
        if m.get('groupOnly') and players == 1:
            continue
        share = m.get('missShare') if m['kind'] == 'soak' else m.get('share', 0)
        out += (share or 0) * taken / (m.get('every', 40000) / 1000.0)
    return out


def split_of(hits):
    tot = sum(a['mean'] * a['chance'] / 100.0 / (a['interval'] / 1000.0) for a in hits)
    out = {'melee': 0.0, 'physical': 0.0, 'element': 0.0}
    for a in hits:
        out[a['kind']] += a['mean'] * a['chance'] / 100.0 / (a['interval'] / 1000.0) / tot
    return out


def boss_damage(boss, text):
    """(raw damage a second after the level bonus, the split) of the XML's attacks at the boss's level and the planned player level"""
    pl = boss['refLevel']
    d = S.dump([pl])
    bal = dict(d['balance'])
    hits = xml_hits(text)
    dps = S.monster_dps(d, bal, boss['level'], hits)
    return sum(dps.values()), split_of(hits)


def median(boss, text, profile, players=1, scale=1.0):
    raw, split = boss_damage(boss, text)
    return GM.median_class(boss['refLevel'], split, raw * scale, marks_share(profile, players))


# ------------------------------------------------------------------------------------------------ fragments
def set_hours(cfg, bal):
    """hours of top content for a whole set: the three specific kinds in turn, the keystone along the way (a roll on every clear)
    and, when that falls short of one, the fastest source until it comes"""
    src, mins = cfg['fragments']['sources'], bal['minutes']
    specific, keys, rates = 0.0, 0.0, []
    for s in ('waystone', 'rift', 'omen'):
        rate = 60.0 / mins[s]
        p, q = src[s]['chance'] / 100.0, src[s]['anyChance'] / 100.0
        specific += 1.0 / (rate * p)
        keys += q / p
        rates.append(rate * q)
    extra = max(0.0, 1.0 - keys) / max(rates) if max(rates) > 0 else float('inf')
    return specific + extra, specific, keys


def keystone_per_hour(cfg, bal):
    src, mins = cfg['fragments']['sources'], bal['minutes']
    return statistics.mean(60.0 / mins[s] * src[s]['anyChance'] / 100.0 for s in ('waystone', 'rift', 'omen'))


def fragments_per_hour(cfg, bal):
    src, mins = cfg['fragments']['sources'], bal['minutes']
    return statistics.mean(60.0 / mins[s] * (src[s]['chance'] + src[s]['anyChance']) / 100.0 for s in ('waystone', 'rift', 'omen'))


def expected_kills(cfg):
    """kills until the unique: a roll of `chance` percent, and the kill `pity` is certain"""
    u = cfg['unique']
    p, n = u['chance'] / 100.0, u['pity']
    return (1 - (1 - p) ** n) / p


# ------------------------------------------------------------------------------------------------ the tables
def rows():
    n = numbers()
    cfg, bal = n['cfg'], n['bal']
    out = []
    for boss in cfg['bosses']:
        text = xml_text(boss)
        profile = n['profiles'].get(boss['name'].lower(), {})
        heal = xml_heal(text)
        health, extra = derive_health(boss, bal, heal)
        m1 = median(boss, text, profile, 1)
        m5 = median(boss, text, profile, bal['players'])
        dmg5 = 1 + cfg['damage']['perExtra'] * (bal['players'] - 1)
        dmg5 = min(dmg5, cfg['damage']['max'])
        press5 = m5['pressure'] * dmg5
        out.append({'boss': boss, 'heal': heal, 'health': health, 'perExtra': extra, 'm1': m1, 'm5': m5, 'press5': press5,
                    'dps': typical(boss['refLevel']), 'profile': profile, 'text': text})
    return out


def committed_ref(profile):
    r = profile.get('ref') or {}
    return r


def check():
    n = numbers()
    cfg, bal = n['cfg'], n['bal']
    lim, tol = bal['limits'], bal['tolerance']
    errors = []
    rs = rows()
    if [r['boss']['level'] for r in rs] != [2000, 2500, 3000, 3500]:
        errors.append('the bosses are shown at 2000 / 2500 / 3000 / 3500: %s' % [r['boss']['level'] for r in rs])
    uniques = S.read(UNIQUES)
    prev = None
    for r in rs:
        b, k = r['boss'], r['boss']['key']
        tag = '%s (level %d, planned for %d)' % (b['name'], b['level'], b['refLevel'])
        if len(b['fragments']) != 4:
            errors.append('%s: %d fragment kinds, four are asked' % (tag, len(b['fragments'])))
        if b['minLevel'] > b['refLevel']:
            errors.append('%s: minLevel %d is above the planned level %d' % (tag, b['minLevel'], b['refLevel']))
        if not re.search(r'name = "%s", id = %d,' % (re.escape(b['unique']['name']), b['unique']['id']), uniques):
            errors.append('%s: the unique %s (id %d) is not in chaos_unique_items.lua' % (tag, b['unique']['name'], b['unique']['id']))
        elif not re.search(r'name = "%s", id = %d,[^\n]*\n[^\n]*monsters = \{[^}]*"%s"' % (
                re.escape(b['unique']['name']), b['unique']['id'], re.escape(b['name'])), uniques):
            errors.append('%s: the unique %s does not list the boss as its monster' % (tag, b['unique']['name']))
        # health and the party curve
        if abs(b['health'] - r['health']) > tol['health'] * r['health']:
            errors.append('%s: health %d, derived %d (%.1f%% off, over %.1f%%)' % (
                tag, b['health'], r['health'], 100 * abs(b['health'] - r['health']) / r['health'], 100 * tol['health']))
        if abs(b['perExtra'] - r['perExtra']) > tol['perExtra'] * r['perExtra']:
            errors.append('%s: perExtra %.4f, derived %.4f' % (tag, b['perExtra'], r['perExtra']))
        now, mx = xml_health(r['text'])
        if now != b['health'] or mx != b['health']:
            errors.append('%s: the XML health is %d / %d, pinnacle_config.lua says %d' % (tag, now, mx, b['health']))
        ref = committed_ref(r['profile'])
        if not ref:
            errors.append('%s: no profile (boss_mechanics_config.lua "%s") or no ref' % (tag, b['name'].lower()))
        else:
            want = {'health': b['health'], 'players': 1, 'uptime': bal['uptime'], 'limit': bal['limitSeconds']}
            for key, val in want.items():
                if abs(ref.get(key, -1) - val) > 1e-9:
                    errors.append('%s: profile ref %s is %s, the model says %s' % (tag, key, ref.get(key), val))
            if abs(ref.get('dps', 0) - r['dps']) > 0.015 * r['dps']:
                errors.append('%s: profile ref dps %s, derived %d' % (tag, ref.get('dps'), r['dps']))
            if abs(ref.get('heal', 0) - r['heal']) > 0.03 * max(1, r['heal']):
                errors.append('%s: profile ref heal %s, the XML heals %.0f a second' % (tag, ref.get('heal'), r['heal']))
        # lengths
        solo = kill_seconds(b, bal, 1, r['heal'])
        party = kill_seconds(b, bal, bal['players'], r['heal'])
        weak = kill_seconds(b, bal, 1, r['heal'], bal['weakest'])
        if abs(solo - bal['seconds']['solo']) > 0.03 * bal['seconds']['solo']:
            errors.append('%s: the median class kills it alone in %.0f s, planned %d' % (tag, solo, bal['seconds']['solo']))
        if abs(party - bal['seconds']['party']) > 0.03 * bal['seconds']['party']:
            errors.append('%s: five of the median class kill it in %.0f s, planned %d' % (tag, party, bal['seconds']['party']))
        if weak > bal['weakestShare'] * bal['limitSeconds']:
            errors.append('%s: the weakest class needs %.0f s alone, over %.0f%% of the %d s limit' % (
                tag, weak, 100 * bal['weakestShare'], bal['limitSeconds']))
        # damage against healing
        m1, m5 = r['m1'], r['m5']
        if not lim['burst']['min'] <= m1['burst'] <= lim['burst']['max']:
            errors.append('%s: the median class lives %.1f s with no healing, outside %s-%s' % (tag, m1['burst'], lim['burst']['min'],
                                                                                                lim['burst']['max']))
        if not lim['pressure']['min'] <= m1['pressure'] <= lim['pressure']['max']:
            errors.append('%s: damage against healing %.2f, outside %s-%s' % (tag, m1['pressure'], lim['pressure']['min'],
                                                                              lim['pressure']['max']))
        if r['press5'] > lim['partyPressure']:
            errors.append('%s: a party of five: damage against healing %.2f, over %s' % (tag, r['press5'], lim['partyPressure']))
        if prev is not None and m1['pressure'] < prev * (1 + lim['rise']) - 1e-9:
            errors.append('%s: the pressure %.2f is under the boss before it (%.2f): a higher level is a harder fight' % (
                tag, m1['pressure'], prev))
        prev = m1['pressure']
        # titles
        for text in (cfg['titles']['first'] % (b['short'], '[S29]'), cfg['titles']['deathless'] % b['short']):
            if len(text) > 24:
                errors.append('%s: the title "%s" is %d characters, 24 at most' % (tag, text, len(text)))
    first, last = rs[0]['m1']['pressure'], rs[-1]['m1']['pressure']
    if last > first * lim['riseMax']:
        errors.append('the last boss presses %.2f, over %.2f x the first (%.2f)' % (last, lim['riseMax'], first))
    # fragments
    hours, _, keys = set_hours(cfg, bal)
    if not bal['hours']['set']['min'] <= hours <= bal['hours']['set']['max']:
        errors.append('a whole set takes %.2f hours of top content, outside %s-%s' % (hours, bal['hours']['set']['min'],
                                                                                    bal['hours']['set']['max']))
    if keystone_per_hour(cfg, bal) > bal['hours']['keystonePerHour']:
        errors.append('the keystone comes %.2f an hour, over %s' % (keystone_per_hour(cfg, bal), bal['hours']['keystonePerHour']))
    uh = hours * expected_kills(cfg)
    if not bal['hours']['unique']['min'] <= uh <= bal['hours']['unique']['max']:
        errors.append('a unique takes %.1f hours of top content (%.2f kills x %.2f hours), outside %s-%s' % (
            uh, expected_kills(cfg), hours, bal['hours']['unique']['min'], bal['hours']['unique']['max']))
    src = cfg['fragments']['sources']
    if bal['minutes'].keys() != {'waystone', 'rift', 'omen'} or set(src) != {'waystone', 'rift', 'omen'}:
        errors.append('the sources are waystone, rift and omen in both files')
    if src['rift']['minTier'] != 15:
        errors.append('the rift fragment is of tier 15 (pinnacle_config.lua)')
    for e in errors:
        print('FAIL ' + e)
    print('pinnacle check: %s (%d bosses, a set in %.2f hours of top content, a unique in %.1f)' % (
        'FAIL' if errors else 'ok', len(rs), hours, uh))
    return 1 if errors else 0


def derive():
    n = numbers()
    cfg, bal = n['cfg'], n['bal']
    print('boss            planned  health    perExtra  heal  dps(median, one boss)')
    for r in rows():
        b = r['boss']
        print('%-15s %5d  %9d  %.4f  %5.0f  %6.0f   (committed %d / %.3f)' % (b['name'], b['refLevel'], round(r['health'], -3), r['perExtra'],
                                                                                  r['heal'], r['dps'], b['health'], b['perExtra']))
    hours, specific, keys = set_hours(cfg, bal)
    print('a set: %.2f hours (the three specific kinds %.2f, the keystone %.2f along the way)' % (hours, specific, keys))


def report():
    n = numbers()
    cfg, bal = n['cfg'], n['bal']
    print('| Boss | level (planned) | health | kill solo / five (median class) | weakest alone | die s (no heal) | pressure solo / five |')
    print('|---|---|---|---|---|---|---|')
    for r in rows():
        b = r['boss']
        solo = kill_seconds(b, bal, 1, r['heal'])
        party = kill_seconds(b, bal, bal['players'], r['heal'])
        weak = kill_seconds(b, bal, 1, r['heal'], bal['weakest'])
        print('| %s | %d (%d) | %d | %.0f s / %.0f s | %.0f s | %.1f | %.2f / %.2f |' % (
            b['name'], b['level'], b['refLevel'], b['health'], solo, party, weak, r['m1']['burst'], r['m1']['pressure'], r['press5']))
    print()
    print('| Source | minutes a clear | clears an hour | fragments an hour (own + keystone) |')
    print('|---|---|---|---|')
    for s in ('waystone', 'rift', 'omen'):
        rate = 60.0 / bal['minutes'][s]
        row = cfg['fragments']['sources'][s]
        print('| %s | %d | %.1f | %.2f (%.2f + %.2f) |' % (s, bal['minutes'][s], rate, rate * (row['chance'] + row['anyChance']) / 100.0,
                                                          rate * row['chance'] / 100.0, rate * row['anyChance'] / 100.0))
    hours, specific, keys = set_hours(cfg, bal)
    print()
    print('A whole set: %.2f hours of top content; the unique: %.2f kills on average (%d%% a kill, sure on the kill %d) = %.1f hours; '
          'fragments an hour, mixed: %.2f.' % (hours, expected_kills(cfg), cfg['unique']['chance'], cfg['unique']['pity'],
                                               hours * expected_kills(cfg), fragments_per_hour(cfg, bal)))


def main(argv):
    os.chdir(SERVER)
    if '--check' in argv:
        return check()
    if '--derive' in argv:
        derive()
        return 0
    report()
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
