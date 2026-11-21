#!/usr/bin/env python3
"""The pinnacle boss model (O667; computed, not measured in game; server/README.md "Pinnacle bosses (O667)").
O686 phase 3: `--upgrades` puts the spell upgrades on (spell_upgrade_model.py): the four bosses x H at their planned level (pinnacle.lua), the typical damage with the gain: 420 s alone and 300 s with five stay. `--check --upgrades` must pass as `--check` does.

usage: python3 -I server/tools/pinnacle_model.py [--derive] [--check] [--hits] [--nocap] [--factors] [--options] [--upgrades]
O698: --factors prints the mechanics' health factor per party size (boss_mechanics_core.lua, what pinnacle.lua applies) against the solo one;
--options prints the bots of the boss video against the model class by class and three health options per boss (the owner picks)
O690 (owner 2026-11-20): one hit of a pinnacle boss, of its adds or of its marked attacks on a player takes at most pinnacle_config.lua
`hitCap` (40% of the pool, a marked attack 60%; the rule of the rift guardian's O478 cap, hitcap_core.lua). The model's damage is the sustained
damage x the retention of the cap, E[min(roll, cap)] / E[roll] per attack of the XML, per class (its pool, armour, absorbs, toughness; rolls
spread evenly between the XML's min and max as guardian_model.py has them), the median over the classes; the marked attacks the same by
their share of the victim's health. --hits prints the hit table before and after the cap per boss, --nocap the model of before.

Four Ascended versions of existing key bosses (Malgrath, Vhoss the Hexmaw, Talath, Varkhul the Ashen Sovereign), shown at level 1900 /
2100 / 2300 / 2500 (the player cap is 2500, owner 2026-11-19; O672), a private fight alone or with five, opened by a set of four fragments the top content drops. The model answers
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
import spell_upgrade_model as SU  # noqa: E402  the spell upgrades switch (O686 phase 3): boss health x H at the planned level

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
def typical(level, boss=None):
    """damage a second of the median class on one boss at a level (boss_length_model: armour and resistance of a boss kept).
    O699 (owner 2026-11-21): for a pinnacle boss (`boss` given) the kept share of the elemental half is the boss file's own resistance
    (real_kept), not the shared BOSS_RES 0.30 of boss_length_model.py (that constant stays for every other boss)"""
    d = BL.one_target(level)
    if boss is not None:
        kept, _ = real_kept(xml_text(boss))
        d *= kept / BL.kept('boss')
    return d


def derive_health(boss, bal, heal):
    d = typical(boss['refLevel'], boss)
    up = bal['uptime']
    solo = bal['seconds']['solo'] * (d * up - heal)
    party = bal['seconds']['party'] * (bal['players'] * d * up - heal)
    return solo, (party / solo - 1) / (bal['players'] - 1)


def kill_seconds(boss, bal, players, heal, dmg_factor=1.0):
    """seconds for `players` of the median class (or `dmg_factor` of it) to kill the committed fight"""
    d = typical(boss['refLevel'], boss) * dmg_factor
    health = boss['health'] * SU.health(boss['refLevel']) * (1 + boss['perExtra'] * (players - 1))  # x H at the planned level (pinnacle.lua), 1 while off
    return health / (players * d * bal['uptime'] - heal)


# ------------------------------------------------------------------------------------------------ damage
def warn_seconds(difficulty):
    """boss_mechanics_core G.warnMs: 3.0 s at difficulty 0 down to 1.5 s at 1 (2.5-3 s up to 0.33)"""
    return max(1.5, 3.0 - 1.5 * min(1.0, difficulty))


def marks_share(profile, players, kept=None):
    """the marked attacks as a share of the victim's max health a second: the mean telegraph share x marksTaken / the cadence, and
    the timed ones (a soak only for a group) the same way. `kept(share)` (O690) is the part of a marked hit the telegraph cap leaves (1 without it)"""
    kept = kept or (lambda share: 1.0)
    bal = numbers()['bal']
    taken = bal['marksTaken']
    diff = profile.get('difficulty', 0.2)
    every = max(warn_seconds(diff) + profile.get('gapMs', 1500) / 1000.0, profile.get('every', 9000) * (1 - 0.25 * diff) / 1000.0)
    tel = profile.get('telegraphs') or []
    out = 0.0
    if tel:
        out += statistics.mean(t['share'] * kept(t['share']) for t in tel) * taken / every
    for m in profile.get('timed') or []:
        if m.get('groupOnly') and players == 1:
            continue
        share = m.get('missShare') if m['kind'] == 'soak' else m.get('share', 0)
        out += (share or 0) * kept(share or 0) * taken / (m.get('every', 40000) / 1000.0)
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


def cap_settings(nums=None):
    """(on, share, telegraph) of pinnacle_config.lua hitCap as the numbers dump has it; (False, 0, 0) when the model runs --nocap"""
    nums = nums or numbers()
    c = nums['cfg'].get('hitCap') or {}
    if nums.get('_nocap'):
        return False, 0.0, 0.0
    def num(v):
        return float(v) if isinstance(v, (int, float)) and not isinstance(v, bool) else 0.0
    share, tel = num(c.get('share')), num(c.get('telegraph'))
    return bool(c.get('enabled')) and share > 0 and tel > 0, share, tel  # a bad number is no cap here: check_cap names it


def xml_rolls(text):
    """[{kind, lo, hi, weight}] of the XML's attacks: the roll spread (min, max) and the weight (its damage a second before the layers)"""
    block = re.search(r'<attacks>(.*?)</attacks>', text, re.S)
    out = []
    for tag in re.findall(r'<attack\s[^>]*>', block.group(1) if block else ''):
        nm = (S.attr(tag, 'name') or '').lower()
        lo, hi = abs(int(S.attr(tag, 'min', '0'))), abs(int(S.attr(tag, 'max', '0')))
        if hi <= 0 and lo <= 0:
            continue
        lo, hi = min(lo, hi), max(lo, hi)
        kind = 'melee' if nm == 'melee' else 'physical' if nm in ('physical', 'bleed') else 'element'
        chance = 100 if kind == 'melee' else int(S.attr(tag, 'chance', '100'))
        interval = int(S.attr(tag, 'interval', '2000'))
        out.append({'name': nm, 'kind': kind, 'lo': float(lo), 'hi': float(hi), 'weight': (lo + hi) / 2.0 * chance / 100.0 / (interval / 1000.0)})
    return out


def hit_base(boss):
    """(factor from the XML roll to the hit before the player's layers, the late-game boost of melee / physical): the engine's level bonus
    and the level pace of survival_model.monster_dps (the same base the sustained damage uses)"""
    d = S.dump([boss['refLevel']])
    bal = d['balance']
    base = (1 + bal['engineBonus'] * boss['level']) * S.lin(d['pace']['damage'], boss['level']) * bal['tierMean']
    boost = S.boost_percent(d['boost']['points'], boss['level']) if d['boost'].get('enabled', True) else 0.0
    return base, boost, bool(d['boost'].get('elemental'))


def layer_factor(row, kind):
    """what a class's layers leave of a hit of `kind` before the pool: melee and physical armour and absorb, an element its absorb; x toughness"""
    if kind == 'element':
        return (1 - row['absorbElem']) * row['toughness']
    return (1 - row['armourRed']) * (1 - row['absorbPhys']) * row['toughness']


def hit_scale(boss, row, atk, mult):
    """XML roll -> the hit that reaches the class's health: the level base, the boost (melee, physical; an element when the boost is
    elemental), the party's damage curve `mult`, the class's layers"""
    base, boost, elemental = hit_base(boss)
    f = base * layer_factor(row, atk['kind'])
    if atk['kind'] != 'element' or elemental:
        f *= 1 + boost / 100.0
    return f * mult


def kind_retention(boss, row, atks, mult, share):
    """{kind: retention} for a class `row`: the damage-weighted E[min(roll, share x pool)] / E[roll] of the attacks of the kind"""
    out = {}
    for kind in ('melee', 'physical', 'element'):
        items = [a for a in atks if a['kind'] == kind]
        tot = sum(a['weight'] for a in items)
        if tot <= 0:
            out[kind] = 1.0
            continue
        v = 0.0
        for a in items:
            f = hit_scale(boss, row, a, mult)
            v += a['weight'] * GM.uniform_retention(a['lo'] * f, a['hi'] * f, share * row['pool'])
        out[kind] = v / tot
    return out


def marks_kept(profile, players, mult, row, tshare):
    """the share of the marked attacks' damage the telegraph cap leaves for a class: a marked hit is `share` of the victim's health (x the
    party curve) against telegraph x pool; the mean over the telegraphs and timed marks as marks_share() weighs them"""
    def kept(share):
        hit = share * mult * row['health'] / row['pool']
        return min(1.0, tshare / hit) if hit > 0 else 1.0
    return kept


def median(boss, text, profile, players=1, scale=1.0, mult=1.0, capped=True):
    """the median class at the planned level under the boss's hits (and marks); with the cap on the sustained damage is cut by each class's
    retention (the party curve `mult` raises the rolls the cap sees; the caller multiplies the pressure by it as before)"""
    on, share, tshare = cap_settings()
    raw, split = boss_damage(boss, text)
    if not (on and capped):
        return GM.median_class(boss['refLevel'], split, raw * scale, marks_share(profile, players))
    pl = boss['refLevel']
    d = S.dump([pl])
    bal = d['balance']
    gear, varm = S.gear_curves(), S.vocation_armour()
    atks = xml_rolls(text)
    dps = raw * scale

    def pack_of(ret):
        return {'melee': dps * split['melee'] * ret['melee'], 'physical': dps * split['physical'] * ret['physical'],
                'element': dps * split['element'] * ret['element'], 'meleeHits': 0.5}
    rows = []
    for cls in S.ORDER:
        full = pack_of({'melee': 1.0, 'physical': 1.0, 'element': 1.0})
        cands = [(S.survive(d, bal, cls, pl, b, full, gear, varm), b) for b in d['builds'][cls][str(pl)]]
        cands.sort(key=lambda c: c[0]['burst'])
        r0, build = cands[len(cands) // 2]
        ret = kind_retention(boss, r0, atks, mult, share)
        r = dict(S.survive(d, bal, cls, pl, build, pack_of(ret), gear, varm))
        r['ret'] = ret
        kept = marks_kept(profile, players, mult, r, tshare)
        r['damage'] += marks_share(profile, players, kept) * r['health']
        r['burst'] = r['pool'] / r['damage'] if r['damage'] > 0 else float('inf')
        r['sustain'] = r['heal'] / r['damage'] if r['damage'] > 0 else float('inf')
        r['pressure'] = r['damage'] / r['heal'] if r['heal'] > 0 else float('inf')
        rows.append(r)
    med = {k: statistics.median(r[k] for r in rows) for k in ('pool', 'health', 'heal', 'damage', 'burst', 'sustain', 'pressure')}
    med['rows'] = rows
    return med


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
        dmg5 = 1 + cfg['damage']['perExtra'] * (bal['players'] - 1)
        dmg5 = min(dmg5, cfg['damage']['max'])
        m1 = median(boss, text, profile, 1)
        m5 = median(boss, text, profile, bal['players'], mult=dmg5)
        press5 = m5['pressure'] * dmg5
        out.append({'boss': boss, 'heal': heal, 'health': health, 'perExtra': extra, 'm1': m1, 'm5': m5, 'press5': press5, 'dmg5': dmg5,
                    'dps': typical(boss['refLevel'], boss), 'profile': profile, 'text': text})
    return out


def hit_table():
    """O690: per boss and party size (1, 5) at the planned level: the biggest roll of each plain attack and the biggest marked hit as a share
    of the pool, the median over the 21 classes and the class it hits hardest, before and after the cap, with the retention"""
    on, share, tshare = cap_settings()
    n = numbers()
    bal = n['bal']
    out = []
    for r in rows():
        b = r['boss']
        atks = xml_rolls(r['text'])
        prof = r['profile']
        row = {'boss': b, 'cells': {}}
        for players in (1, bal['players']):
            mult = 1.0 if players == 1 else r['dmg5']
            med = r['m1'] if players == 1 else r['m5']
            cls_rows = med['rows']
            biggest = []
            for a in atks:
                shares = [a['hi'] * hit_scale(b, c, a, mult) / c['pool'] for c in cls_rows]
                biggest.append((a['name'], a['kind'], statistics.median(shares), max(shares)))
            tel = [t['share'] for t in (prof.get('telegraphs') or [])] + [
                (m.get('missShare') if m['kind'] == 'soak' else m.get('share', 0)) or 0 for m in (prof.get('timed') or [])
                if not (m.get('groupOnly') and players == 1)]
            tmax = max(tel) if tel else 0.0
            tshares = [tmax * mult * c['health'] / c['pool'] for c in cls_rows]
            top = max(biggest, key=lambda x: x[2])
            split = boss_damage(b, r['text'])[1]
            totals = [sum(split[k] * c['ret'][k] for k in split) if 'ret' in c else 1.0 for c in cls_rows]
            cells = {'attacks': biggest, 'top': top, 'tel': (statistics.median(tshares), max(tshares)),
                     'cut': sum(1 for c in cls_rows if max(a['hi'] * hit_scale(b, c, a, mult) for a in atks) > share * c['pool']) if on else 0,
                     'telCut': sum(1 for v in tshares if v > tshare) if on else 0,
                     'retMean': statistics.mean(totals), 'retWorst': min(totals),
                     'retEl': statistics.mean(c['ret']['element'] if 'ret' in c else 1.0 for c in cls_rows),
                     'retMelee': statistics.mean(c['ret']['melee'] if 'ret' in c else 1.0 for c in cls_rows),
                     'classes': len(cls_rows), 'pressure': med['pressure'] * mult, 'burst': med['burst']}
            row['cells'][players] = cells
        out.append(row)
    return out


def print_hits(rows_):
    on, share, tshare = cap_settings()
    print('hit cap (O690): %s; plain hits at most %.0f%% of the pool, marked attacks %.0f%%' % (
        'on' if on else 'OFF (--nocap)', 100 * share, 100 * tshare))
    print('biggest roll of each attack after the class layers, as a share of the pool: median class (worst class); the party curve x1.24 for five')
    for r in rows_:
        b = r['boss']
        print('\n%s (level %d)' % (b['name'], b['refLevel']))
        for players, c in sorted(r['cells'].items()):
            line = []
            for name, kind, med, worst in c['attacks']:
                cap_med, cap_worst = (min(med, share), min(worst, share)) if on else (med, worst)
                line.append('%s %.0f%% -> %.0f%% (%.0f%% -> %.0f%%)' % (name, 100 * med, 100 * cap_med, 100 * worst, 100 * cap_worst))
            tm, tw = c['tel']
            tcm, tcw = (min(tm, tshare), min(tw, tshare)) if on else (tm, tw)
            print('  %d player%s: %s' % (players, '' if players == 1 else 's', '; '.join(line)))
            print('             marked, the biggest: %.0f%% -> %.0f%% (%.0f%% -> %.0f%%); classes cut by the plain cap %d of %d, by the marked cap %d' % (
                100 * tm, 100 * tcm, 100 * tw, 100 * tcw, c['cut'], c['classes'], c['telCut']))
            print('             damage kept by the cap (mean over the classes; the worst class): melee %.2f, element %.2f, all %.2f (%.2f); '
                  'median class: pressure %.2f, seconds to die %.1f' % (c['retMelee'], c['retEl'], c['retMean'], c['retWorst'], c['pressure'], c['burst']))


def check_cap(n, rs):
    """O690: the committed cap against pinnacle_balance_config.lua hitCap (the reasons are there)"""
    errors = []
    bal = n['bal']['hitCap']
    c = n['cfg'].get('hitCap')
    if not isinstance(c, dict):
        return ['pinnacle_config.lua has no hitCap block']
    for key in ('share', 'telegraph'):
        v = c.get(key)
        if not isinstance(v, (int, float)) or isinstance(v, bool) or not 0 < v <= 1:
            errors.append('hitCap.%s is %r, not a share of the pool in (0, 1]' % (key, v))
    if errors:
        return errors
    if c.get('enabled') is not True:
        errors.append('hitCap.enabled is %r: the model, the README and the bots assume the cap' % (c.get('enabled'),))
    extra = sorted(set(c) - {'enabled', 'share', 'telegraph'})
    if extra:
        errors.append('hitCap has keys the model does not read: %s' % extra)
    share, tel = c['share'], c['telegraph']
    if abs(share - bal['share']) > 1e-9 or abs(tel - bal['telegraph']) > 1e-9:
        errors.append('hitCap %s / %s is not pinnacle_balance_config.lua hitCap %s / %s (the reasoned numbers)' % (
            share, tel, bal['share'], bal['telegraph']))
    # no one-shot: a character of full health survives `survives` plain hits in a row with `left` of its pool still standing (the upper bound
    # of the share; the lower bound is the retention below: a cap that is too low turns the boss into a wall of health)
    if share * bal['survives'] > 1.0 - bal['left'] + 1e-9:
        errors.append('hitCap.share %s: %d plain hits in a row take %.0f%% of a full pool, %.0f%% must be left' % (
            share, bal['survives'], 100 * share * bal['survives'], 100 * bal['left']))
    # a marked attack: never under the biggest share the profiles design (the cap then only trims what the party curve adds), never the pool
    prof = [t['share'] for p in n['profiles'].values() for t in (p.get('telegraphs') or [])]
    prof += [(m.get('missShare') if m['kind'] == 'soak' else m.get('share', 0)) or 0 for p in n['profiles'].values() for m in (p.get('timed') or [])]
    design = max(prof) if prof else 0.0
    if not share < tel <= bal['telegraphMax']:
        errors.append('hitCap.telegraph %s is not above the plain share %s and at most %s (a marked attack hurts more than a plain hit, and never one-shots)' % (
            tel, share, bal['telegraphMax']))
    if tel < design - 1e-9:
        errors.append('hitCap.telegraph %s is under the biggest marked hit the profiles design (%s of the health): a solo fight would be cut' % (tel, design))
    # the cap is no wall: the classes keep most of the boss's damage on average and the hardest hit class most of its own; and it acts
    lim = bal['retention']
    if any('ret' not in x for r in rs for x in r['m1']['rows']):
        return errors + ['the model ran without the cap (--nocap) while hitCap is on']
    cells = {r['boss']['key']: r for r in hit_table()}
    for key, r in cells.items():
        for players, c in sorted(r['cells'].items()):
            if c['retMean'] < lim['mean']:
                errors.append('%s, %d player(s): the cap takes %.0f%% of the boss\'s damage away on average (it keeps %.2f, at least %.2f is asked): a wall of health, '
                              'not a fight: raise the share or the boss\'s uncapped damage' % (key, players, 100 * (1 - c['retMean']), c['retMean'], lim['mean']))
            if c['retWorst'] < lim['worst']:
                errors.append('%s, %d player(s): the hardest hit class keeps %.2f of the boss\'s damage, at least %.2f is asked' % (
                    key, players, c['retWorst'], lim['worst']))
        top = r['cells'][n['bal']['players']]
        if top['cut'] < bal['cuts']['atLeast']:
            errors.append('%s: with five the cap cuts the biggest hit of %d of %d classes, at least %d are asked: a cap that touches nobody is no cap' % (
                key, top['cut'], top['classes'], bal['cuts']['atLeast']))
        if top['cut'] > bal['cuts']['atMost'] * top['classes']:
            errors.append('%s: with five the cap cuts the biggest hit of %d of %d classes, over %.0f%%: it is the hit, not the fight' % (
                key, top['cut'], top['classes'], 100 * bal['cuts']['atMost']))
    return errors


def check_factors(n):
    """O698: the mechanics' health factor of each boss at each size (boss_mechanics_core.lua G.refFor / G.balance, what pinnacle.lua hands
    boss_mechanics.lua) keeps the planned kill time of that size (420 s alone, 300 s with five) inside `factor.tolerance`, no factor sits on the
    floor of the profile (`minHpMult`, a bound that cuts the plan), and the factor of a party is not the solo one (the fight is worked out for its size)"""
    bal = n['bal']
    fc = bal['factor']
    errors = []
    for boss in n['cfg']['bosses']:
        key = boss['name'].lower()
        prof = n['profiles'].get(key, {})
        rows_ = n['factors'].get(key)
        if not rows_:
            errors.append('%s: no factor rows (the profile has no ref)' % boss['name'])
            continue
        floor_ = prof.get('minHpMult', 0.6)
        for size in range(1, bal['players'] + 1):
            f = rows_[str(size)]
            if f['hpMult'] <= floor_ + 1e-9 or f['hpMult'] > 1 + 1e-9:
                errors.append('%s x%d: the health factor %.4f is on the floor %.2f or above 1: the kill time is not kept' % (boss['name'], size, f['hpMult'], floor_))
            if abs(f['final'] - f['base']) > fc['tolerance'] * f['base']:
                errors.append('%s x%d: with the factor %.4f the kill time is %.0f s, planned %.0f (%.1f%% off, over %.1f%%)' % (
                    boss['name'], size, f['hpMult'], f['final'], f['base'], 100 * abs(f['final'] - f['base']) / f['base'], 100 * fc['tolerance']))
        solo_plan, party_plan = bal['seconds']['solo'], bal['seconds']['party']
        if abs(rows_['1']['final'] - solo_plan) > fc['tolerance'] * solo_plan:
            errors.append('%s: alone the median class kills it in %.0f s with the factor, planned %d' % (boss['name'], rows_['1']['final'], solo_plan))
        top = rows_[str(bal['players'])]
        if abs(top['final'] - party_plan) > fc['tolerance'] * party_plan:
            errors.append('%s: five of the median class kill it in %.0f s with the factor, planned %d' % (boss['name'], top['final'], party_plan))
        if abs(top['hpMult'] - top['soloMult']) < fc['partyDiffers'] and abs(top['soloFinal'] - party_plan) > fc['tolerance'] * party_plan:
            errors.append('%s: the party factor is the solo one (%.4f) and misses the plan' % (boss['name'], top['soloMult']))
    return errors


def committed_ref(profile):
    r = profile.get('ref') or {}
    return r


def check():
    n = numbers()
    cfg, bal = n['cfg'], n['bal']
    lim, tol = bal['limits'], bal['tolerance']
    errors = []
    rs = rows()
    # O672 (owner 2026-11-19): the player cap is 2500; the ladder of the bosses lies inside it, every boss planned for the level it is shown at
    if [r['boss']['level'] for r in rs] != lim['ladder']:
        errors.append('the bosses are shown at %s: %s' % (' / '.join(str(x) for x in lim['ladder']), [r['boss']['level'] for r in rs]))
    for r in rs:
        b = r['boss']
        if b['level'] > bal['levelCap'] or b['refLevel'] > bal['levelCap'] or b['minLevel'] > bal['levelCap']:
            errors.append('%s: a level above the player cap %d (level %d, planned %d, from %d)' % (
                b['name'], bal['levelCap'], b['level'], b['refLevel'], b['minLevel']))
        if b['refLevel'] != b['level']:
            errors.append('%s: planned for %d, shown at %d (the ladder plans every fight for the level it is shown at)' % (
                b['name'], b['refLevel'], b['level']))
        if b['refLevel'] - b['minLevel'] != lim['openBelow']:
            errors.append('%s: opens from %d, %d under the planned level %d, asked %d' % (
                b['name'], b['minLevel'], b['refLevel'] - b['minLevel'], b['refLevel'], lim['openBelow']))
    if [r['boss']['refLevel'] for r in rs] != sorted(set(r['boss']['refLevel'] for r in rs)):
        errors.append('the planned levels do not rise from boss to boss')
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
        have_hp = b['health'] * SU.health(b['refLevel'])  # the game multiplies the committed fight by H (pinnacle.lua), 1 while off
        tol_hp = tol['health'] + SU.slack(b['refLevel'])
        if abs(have_hp - r['health']) > tol_hp * r['health']:
            errors.append('%s: health %d x H %.3f, derived %d (%.1f%% off, over %.1f%%)' % (
                tag, b['health'], SU.health(b['refLevel']), r['health'], 100 * abs(have_hp - r['health']) / r['health'], 100 * tol_hp))
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
            with SU.forced(False):  # the ref is the fight's numbers of today (the XML health, the damage of the model), the game adds H and the gain
                today_dps = typical(b['refLevel'], b)
            if abs(ref.get('dps', 0) - today_dps) > 0.015 * today_dps:
                errors.append('%s: profile ref dps %s, derived %d' % (tag, ref.get('dps'), today_dps))
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
    errors.extend(check_cap(n, rs))
    errors.extend(check_factors(n))
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


# ------------------------------------------------------------------------------------------------ O698: the mechanics' factor, the options
def factor_rows():
    """{boss key: {size: row}} of boss_mechanics_core.lua G.balance for the fight of each size (tools/pinnacle_numbers.lua, the real core):
    health, hpMult (what pinnacle.lua applies), base / final seconds, downtime share, fixed seconds, and the solo factor the fights used before O698"""
    return numbers()['factors']


def scaled_rows(wants):
    """the same rows for a health and a damage scale of the committed fight: wants = [(boss key, health scale, damage scale)] -> {want: {size: row}}"""
    args = ['%s,%.8f,%.8f' % w for w in wants]
    out = subprocess.run([lua_bin(), os.path.join('tools', 'pinnacle_numbers.lua')] + args, cwd=SERVER, check=True, capture_output=True,
                         text=True).stdout
    got = json.loads(out)['scaled']
    return {w: got[a] for w, a in zip(wants, args)}


def real_kept(text):
    """boss_length_model.kept('boss') with the boss's own resistances: the elemental half through the mean of the six elements of its XML
    (fire, energy, earth, ice, holy, death) instead of BOSS_RES; the armour on the physical half as the model has it"""
    share = float(re.search(r'physicalShare = ([0-9.]+)', BL.read(BL.PVP)).group(1))
    six = [int(v) for k, v in re.findall(r'<element (\w+)Percent="(-?\d+)"', text) if k != 'physical']
    res = sum(six) / (100.0 * max(1, len(six)))
    return BL.kept('boss') + (1 - share) * (BL.BOSS_RES - res), res


def bot_scale(bal, rows_):
    """[(boss key, options)] the three options of health for each boss (the owner picks; nothing is changed by them), numbers from the real core:
    health scales of the committed fight (a: the median kills it in the planned time with the boss's real resistances, b: the measured bot five
    kill it in `target` seconds, c: in half of it), the fight's health with the factor, the median five's and the bot five's seconds"""
    me = bal['measured']
    plan = float(bal['seconds']['party'])
    facs = factor_rows()
    out = []
    for r in rows_:
        b = r['boss']
        key = b['name'].lower()
        kept, res = real_kept(r['text'])
        ratio = 1.0   # O699: the committed fight already holds the boss file's resistance (typical(level, boss)); option a is the committed state
        row5 = facs[key][str(bal['players'])]
        vid = row5['health'] * row5['soloMult']   # the fight of the video: the party's health x the solo factor (Malgrath: 10,134,615)
        cur = row5['health'] * row5['hpMult']

        def times(hs, ds):
            got = scaled_rows([(key, hs, ds)])[(key, hs, ds)]
            five, solo = got[str(bal['players'])], got['1']
            fight = five['health'] * five['hpMult']
            return {'hs': hs, 'ds': ds, 'five_health': fight, 'solo_health': solo['health'] * solo['hpMult'], 'median5': five['final'],
                    'median1': solo['final'], 'bots5': me['seconds'] * fight / vid, 'hpMult5': five['hpMult']}

        def solve(target):
            hs = 1.0
            for _ in range(4):
                hs *= target / times(hs, 1.0)['bots5']
            return hs
        opts = [('today (O698 factor)', times(1.0, 1.0)), ('a: inputs fixed', times(ratio, ratio)),
                ('b: bots kill in %d s' % plan, times(solve(plan), 1.0)), ('c: bots kill in %d s' % (plan / 2), times(solve(plan / 2), 1.0))]
        out.append({'boss': b, 'res': res, 'kept': kept, 'ratio': ratio, 'cur': cur, 'vid': vid, 'options': opts})
    return out


def print_factors():
    n = numbers()
    bal = n['bal']
    print('health factor of boss_mechanics_core.lua G.balance per party size (what pinnacle.lua applies, O698), against the solo factor the')
    print('fights used at every size before it (final = the kill time of the median class with the factor; plan %d s solo, %d s with %d)' % (
        bal['seconds']['solo'], bal['seconds']['party'], bal['players']))
    print('| Boss | size | health | factor | solo factor (before) | final s | before s | downtime | fixed s |')
    print('|---|---|---|---|---|---|---|---|---|')
    for key, sizes in n['factors'].items():
        for size in sorted(sizes, key=int):
            f = sizes[size]
            print('| %s | %s | %d | %.4f | %.4f | %.0f | %.0f | %.3f | %.1f |' % (key, size, f['health'], f['hpMult'], f['soloMult'], f['final'],
                                                                              f['soloFinal'], f['share'], f['fixed']))


def print_options():
    n = numbers()
    bal = n['bal']
    me = bal['measured']
    rs = rows()
    print('measured (O689 run 6): %s, %d bots of level %d, %d s from %d health; bots %.0f a second (sum), the model plans %.0f (%d x %.0f raw)' % (
        me['boss'], me['players'], me['level'], me['seconds'], me['startHealth'], sum(me['perBot'].values()),
        bal['players'] * typical(rs[0]['boss']['refLevel']), bal['players'], typical(rs[0]['boss']['refLevel'])))
    print('| Boss | boss resist (six elements) | kept (BOSS_RES 0.30 / real) | option | health of the fight (five) | median five s | bot five s | median alone s | health x today |')
    print('|---|---|---|---|---|---|---|---|---|')
    for o in bot_scale(bal, rs):
        today = o['options'][0][1]['five_health']
        for name, t in o['options']:
            print('| %s | %.1f%% | %.3f / %.3f | %s | %d | %.0f | %.0f | %.0f | %.2f |' % (
                o['boss']['name'], 100 * o['res'], BL.kept('boss'), o['kept'], name, t['five_health'], t['median5'], t['bots5'], t['median1'],
                t['five_health'] / today))


def class_table():
    """the bots against the model, per class, at the planned level of the measured boss: the bot's damage a second, the model's raw and kept"""
    n = numbers()
    me = n['bal']['measured']
    rs = rows()
    r = [x for x in rs if x['boss']['name'].lower() == me['boss']][0]
    import class_dps_model as CD
    level = r['boss']['refLevel']
    kept = BL.kept('boss')
    real, res = real_kept(r['text'])
    out = []
    for cls, got in me['perBot'].items():
        raw = CD.dps(cls, level)[0]
        out.append({'cls': cls, 'bot': got, 'early': me['early'][cls], 'raw': raw, 'model': raw * kept, 'real': raw * real,
                    'dots': me['dots'].get(cls, 0) / float(me['botSeconds'])})
    return out, kept, real, res


def print_classes():
    n = numbers()
    me = n['bal']['measured']
    rows_, kept, real, res = class_table()
    print('class by class at level %d on one boss (a second): bot = damage_final of the run, model = class_dps_model.dps x BOSS_RES kept %.3f,' % (
        1900, kept))
    print('real = the same x the kept %.3f of the boss files (%.1f%% resist on the six elements)' % (real, 100 * res))
    print('| Class | bot | early tally | model raw | model kept | bot / model | model real resist | bot / real | dots of the bot |')
    print('|---|---|---|---|---|---|---|---|---|')
    tb = tm = tr = 0.0
    for c in rows_:
        print('| %s | %.0f | %.0f | %.0f | %.0f | %.2f | %.0f | %.2f | %.0f (%.0f%%) |' % (c['cls'], c['bot'], c['early'], c['raw'], c['model'], c['bot'] / c['model'],
                                                                                    c['real'], c['bot'] / c['real'], c['dots'], 100 * c['dots'] / c['bot']))
        tb += c['bot']
        tm += c['model']
        tr += c['real']
    print('| sum of the five | %.0f | | | %.0f | %.2f | %.0f | %.2f | |' % (tb, tm, tb / tm, tr, tb / tr))


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
    argv = SU.from_argv(argv)
    if SU.active():
        print(SU.banner())
    os.chdir(SERVER)
    if '--nocap' in argv:  # the model of before O690: no cap
        numbers()['_nocap'] = True
    if '--check' in argv:
        return check()
    if '--hits' in argv:
        print_hits(hit_table())
        return 0
    if '--factors' in argv:
        print_factors()
        return 0
    if '--options' in argv:
        print_classes()
        print()
        print_options()
        return 0
    if '--derive' in argv:
        derive()
        return 0
    report()
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
