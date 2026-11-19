#!/usr/bin/env python3
"""The waystone endgame model (O666; computed, not measured in game; server/README.md "Waystone endgame (O666)").

usage: python3 -I server/tools/waystone_endgame_model.py [--derive] [--check] [--write-bosses] [--tiers 1,10,25]

Owner 2026-11-19: the waystones go on past tier XV (tiers XVI-XXV); O672 (owner 2026-11-19: the player cap stays 2500): all at monster level 2500, ten steps of difficulty by factors, never a level above the cap. For every tier the model gives, for the median
class of the tier's level and a plain run (no modifiers): the clear time (sweep of the map + its boss + the walk), the seconds the median
class lives in the pack with no healing and how much it heals against the pack's damage, the experience a run pays against the hunt of
the level (minutes a level in waystones against the 12 of a hunt), and then the four band bosses, the corrupted waystone and the atlas.

Inputs (all in the repo): data/scripts/chaos/waystone_tiers_config.lua (tiers, bands, the engine's level factors),
waystone_endgame_config.lua (deep factors, band bosses, corruption, atlas), waystone_endgame_balance_config.lua (assumptions, limits),
class_dps_model.py (the median class damage at any level, flat steps of the round above 2000: the damage keeps its line, see
the README), survival_model.py (health, armour, healing, the monsters' damage layers), pace_config.lua `scaled` (health and experience of a
monster by its level, flat above 2000), tools/late_game.py (the experience stage), data/monster/monsters/chaos/waystone_bosses (the band
bosses' files).

--derive   the deep factors (health, damage) the limits ask for, and the band bosses' XML health and attack numbers
--write-bosses  write the four band bosses' files (health and attacks from the model)
--check    exit 1 when a limit of waystone_endgame_balance_config.lua fails, or a committed number is off its derivation
"""
import json
import math
import os
import re
import statistics
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)
import class_dps_model as CD  # noqa: E402
import survival_model as S  # noqa: E402
import boss_length_model as BL  # noqa: E402

SERVER = os.path.normpath(os.path.join(HERE, '..'))
CHAOS = os.path.join(SERVER, 'data', 'scripts', 'chaos')
BOSSES = os.path.join(SERVER, 'data', 'monster', 'monsters', 'chaos', 'waystone_bosses')
PACE = os.path.join(CHAOS, 'pace_config.lua')


def lua_bin():
    return os.environ.get('LUAJIT', 'luajit')


def numbers():
    out = subprocess.run([lua_bin(), os.path.join(SERVER, 'tools', 'waystone_endgame_numbers.lua')], cwd=SERVER, check=True,
                         capture_output=True, text=True).stdout
    return json.loads(out)


def lin(points, x):
    """linear between points [(x, y)], flat beyond the ends"""
    if x <= points[0][0]:
        return points[0][1]
    for (x0, y0), (x1, y1) in zip(points, points[1:]):
        if x <= x1:
            return y0 + (y1 - y0) * (x - x0) / float(x1 - x0)
    return points[-1][1]


def pace_scaled(key):
    """the points of pace_config.lua `scaled` <key> (health / xp / damage)"""
    text = S.read(PACE)
    block = text[text.index('\tscaled = {'):]
    m = re.search(r'\b%s = \{(\{.*?\})\}' % key, block, re.S)
    pts = re.findall(r'\{\s*(\d+)\s*,\s*([0-9.]+)\s*\}', m.group(1))
    return [(float(a), float(b)) for a, b in pts]


def exp_for_level(level):
    """the engine's experience formula (Player::getExpForLevel): the total experience at `level`"""
    lv = level - 1
    return (50 * lv ** 3 - 150 * lv ** 2 + 400 * lv) / 3.0


def native_pool(assume):
    """(median health, median experience, rows) of the pool monsters of the native window"""
    lo, hi = assume['native']['window']
    txt = S.read(S.POOL).split('\tbosses = ')[0]
    rows = [(int(m.group(1)), int(m.group(2)), int(m.group(3))) for m in re.finditer(
        r'\{name = "[^"]+", level = (\d+), exp = (\d+), health = (\d+)', txt) if lo <= int(m.group(1)) <= hi]
    return statistics.median(r[2] for r in rows), statistics.median(r[1] for r in rows), rows


def player_level(num, L):
    """the median character of a run at monster level L: the survival model's gap above it, never above the level cap (O672, owner
    2026-11-19: the player cap stays 2500, balance config `playerCap`)"""
    gap = cached('gap', lambda: S.dump([1000])['balance']['gap'])
    return min(L + gap, num['bal']['assume']['playerCap'])


def deep_target(num, t, key):
    """the target of the balance config for deep tier t (16-25): its {first, last} pair, straight between the two"""
    pair = num['bal']['limits'][key]
    d = num['tiers']['deep']
    last = len(num['tiers']['tiers'])
    return pair[0] + (pair[1] - pair[0]) * (t - d['from']) / float(last - d['from'])


def deep_factor(cfg, t, key):
    d = cfg['tiers']['deep']
    if t < d['from']:
        return 1.0
    return d[key]['base'] + d[key]['perTier'] * (t - d['from'])


def scale(tcfg, native, target):
    h, d = tcfg['healthPerLevel'], tcfg['damagePerLevel']
    return {'health': (1 + h * target) / (1 + h * native), 'damage': (1 + d * target) / (1 + d * native), 'experience': target / native}


_cache = {}


def cached(key, fn):
    if key not in _cache:
        _cache[key] = fn()
    return _cache[key]


def run_row(num, t, deep=None):
    """the numbers of a plain run of tier t; deep = (health, damage, experience) factors, else the config's"""
    tc, eg, bal = num['tiers'], num['endgame'], num['bal']
    a = bal['assume']
    L = tc['tiers'][t - 1]['level']
    P = player_level(num, L)
    hf, df, xf = deep or (deep_factor(num, t, 'health'), deep_factor(num, t, 'damage'), deep_factor(num, t, 'experience'))
    h0, e0, _ = cached('native', lambda: native_pool(a))
    n0 = a['native']['level']
    f = scale(tc, n0, L)
    pace_h = lin(cached('ph', lambda: pace_scaled('health')), L) if a['paceApplies'] else 1.0
    pace_x = lin(cached('px', lambda: pace_scaled('xp')), L) if a['paceApplies'] else 1.0
    kept_n, kept_b = BL.kept('normal'), BL.kept('boss')
    dps1, dps5 = CD.median_dps(P)
    mon_hp = h0 * f['health'] * hf * pace_h * a['tierHp']
    sweep = a['mapMonsters'] * mon_hp / (dps5 * kept_n * a['uptime'])
    # the base tier of the map: the deep band uses the strongest three, the others by their band; the boss base by the mean of the maps
    maps = [b for b in tc['bands'] if b['first'] <= t <= b['last']][0]['maps']
    boss_base = statistics.mean(a['bossBase'][m - 1] for m in maps)
    first = [b for b in tc['bands'] if b['first'] <= t <= b['last']][0]['first']
    bf = scale(tc, tc['tiers'][first - 1]['level'], L)
    boss_hp = boss_base * bf['health'] * hf
    boss_s = boss_hp / (dps1 * kept_b * a['bossUptime'])
    clear = sweep + boss_s + a['walkSeconds'] + a['bossMapSeconds']
    # survival: the native window's pool monsters' attacks at the run's level
    d = cached(('dump', P), lambda: S.dump([P]))
    bl = d['balance']
    mons = cached('mons', lambda: S.hunt(n0, (a['native']['window'][1] - a['native']['window'][0]) // 2, None, S.scaled_monsters()))
    pack = S.pack_dps(d, bl, L, [(nm, sp, L, att) for nm, sp, _, att in mons])
    for k in ('melee', 'physical', 'element'):
        pack[k] *= df
    gear, varm = cached('gear', S.gear_curves), cached('varm', S.vocation_armour)
    rows = []
    for cls in S.ORDER:
        cands = [S.survive(d, bl, cls, P, b, pack, gear, varm) for b in d['builds'][cls][str(P)]]
        cands.sort(key=lambda r: r['burst'])
        rows.append(cands[len(cands) // 2])
    med = {k: statistics.median(r[k] for r in rows) for k in ('pool', 'damage', 'heal', 'burst', 'sustain')}
    worst = min(r['burst'] for r in rows) / med['burst']
    # the reward: experience of the run, the engine stage, x T / native (K.scale) x the deep factor
    run_exp = (a['mapMonsters'] * e0 * pace_x * f['experience'] * xf + 0) * a['stage']
    per_hour = run_exp * 3600.0 / (clear + a['overheadSeconds'])
    hunt = (exp_for_level(L + 1) - exp_for_level(L)) * 60.0 / a['huntMinutesPerLevel']
    return {'tier': t, 'level': L, 'player': P, 'monsterHp': mon_hp, 'sweep': sweep, 'bossHp': boss_hp, 'bossSeconds': boss_s, 'clear': clear,
            'burst': med['burst'], 'sustain': med['sustain'], 'worst': worst, 'runExp': run_exp, 'perHour': per_hour, 'hunt': hunt,
            'ratio': per_hour / hunt, 'minPerLevel': (exp_for_level(L + 1) - exp_for_level(L)) / per_hour * 60.0}


def derive_deep(num, t):
    """the deep factors (health, damage, experience) of tier t that put a plain run on the targets of the balance config for that tier: clear
    time `deepClearSeconds`, the median class's sustain `deepSustain`, experience an hour `deepExpRatio` x the hunt of the level (each a
    {tier XVI, tier XXV} pair, straight between). Closed forms: the sweep and the boss are linear in the health factor, the pack's damage
    in the damage factor, the experience in the experience factor"""
    a = num['bal']['assume']
    base = run_row(num, t, (1.0, 1.0, 1.0))
    work = base['clear'] - a['walkSeconds'] - a['bossMapSeconds']
    hf = max(1.0, (deep_target(num, t, 'deepClearSeconds') - a['walkSeconds'] - a['bossMapSeconds']) / work)
    df = base['sustain'] / deep_target(num, t, 'deepSustain')
    at = run_row(num, t, (hf, df, 1.0))
    xf = deep_target(num, t, 'deepExpRatio') / at['ratio']
    return hf, df, xf


# ------------------------------------------------------------------------------------------------ band bosses
def read_boss(file):
    path = os.path.join(BOSSES, file + '.xml')
    if not os.path.exists(path):
        return None
    text = S.read(path)
    hp = int(re.search(r'<health now="\d+" max="(\d+)"', text).group(1))
    return {'health': hp, 'attacks': S.parse_monster(text)[1], 'text': text}


def band_row(num, b):
    a = num['bal']['assume']
    t = b['tier']
    tc = num['tiers']
    L = tc['tiers'][t - 1]['level']
    P = player_level(num, L)
    dps1 = CD.median_dps(P)[0] * BL.kept('boss')
    want_hp = b['seconds'] * dps1 * a['bossUptime']
    out = {'tier': t, 'level': L, 'monster': b['monster'], 'wantHealth': want_hp}
    xml = read_boss(b['file'])
    out['xml'] = xml
    d = cached(('dump', P), lambda: S.dump([P]))
    bl = d['balance']
    gear, varm = cached('gear', S.gear_curves), cached('varm', S.vocation_armour)
    # the boss's hits per second at the run's level through the same layers as a pack monster's (one monster, pack factor 1)
    if xml:
        one = S.monster_dps(d, dict(bl, tierMean=1.0), L, xml['attacks'])
        pack = {'melee': one['melee'], 'physical': one['physical'], 'element': one['element'], 'meleeHits': 0.5}
        rows = []
        for cls in S.ORDER:
            cands = [S.survive(d, bl, cls, P, bb, pack, gear, varm) for bb in d['builds'][cls][str(P)]]
            cands.sort(key=lambda r: r['burst'])
            rows.append(cands[len(cands) // 2])
        out['die'] = statistics.median(r['burst'] for r in rows)
        out['kill'] = xml['health'] / (dps1 * a['bossUptime'])
        out['dps'] = sum(one.values())
    # the pool of the median class and the damage per second that kills it in dieSeconds: the XML attack numbers to write
    d_rows = [S.survive(d, bl, c, P, sorted(d['builds'][c][str(P)], key=lambda x: x['id'])[0],
                        {'melee': 1.0, 'physical': 0.0, 'element': 0.0, 'meleeHits': 1.0}, gear, varm) for c in S.ORDER]
    pool = statistics.median(r['pool'] for r in d_rows)
    out['wantDps'] = pool / b['dieSeconds']
    return out


# the band bosses' files: outfit of an existing boss (no new art), numbers from the model (--write-bosses)
LOOKS = {5: (2234, 'undead', 'groundshaker', 'death'), 10: (229, 'undead', 'firearea', 'fire'),
         15: (204, 'undead', 'groundshaker', 'physical'), 25: (591, 'undead', 'mortarea', 'death')}
TEMPLATE = """<?xml version="1.0" encoding="UTF-8"?>
<!-- Band boss of the waystone maps (O666, ChaosWaystoneEndgame, README "Waystone endgame (O666)"): it appears when the map's boss dies in
     the last tier of band %(band)s (tier %(tier)d, monster level %(level)d). Its outfit is an existing boss's (%(look)d). Health and attacks
     are written by tools/waystone_endgame_model.py (write-bosses: the median class kills it in %(seconds)d s and lives %(die)d s under its
     hits at the tier's level); the loot of its drop table is in content_rewards.lua (branch band), so this file lists a coin only. -->
<monster name="%(name)s" nameDescription="%(name)s" race="%(race)s" experience="%(exp)d" speed="260" manacost="0">
	<health now="%(hp)d" max="%(hp)d" />
	<look type="%(look)d" corpse="6068" />
	<targetchange interval="8000" chance="5" />
	<flags>
		<flag isboss="1" />
		<flag summonable="0" />
		<flag attackable="1" />
		<flag hostile="1" />
		<flag illusionable="0" />
		<flag convinceable="0" />
		<flag pushable="0" />
		<flag canpushitems="1" />
		<flag canpushcreatures="1" />
		<flag targetdistance="1" />
		<flag staticattack="90" />
		<flag runonhealth="0" />
		<flag canwalkonfire="1" />
		<flag canwalkonenergy="1" />
		<flag canwalkonpoison="1" />
	</flags>
	<attacks>
		<attack name="melee" interval="2000" min="-%(mmin)d" max="-%(mmax)d" />
		<attack name="%(elem)s" interval="2000" chance="14" length="5" spread="2" min="-%(amin)d" max="-%(amax)d">
			<attribute key="areaEffect" value="%(area)s" />
		</attack>
	</attacks>
	<defenses armor="90" defense="90" />
	<elements>
		<element physicalPercent="15" />
		<element firePercent="5" />
		<element energyPercent="0" />
		<element earthPercent="0" />
		<element icePercent="5" />
		<element holyPercent="-15" />
		<element deathPercent="30" />
	</elements>
	<immunities>
		<immunity paralyze="1" />
		<immunity invisible="1" />
		<immunity outfit="1" />
		<immunity drunk="1" />
		<immunity lifedrain="1" />
	</immunities>
	<loot>
		<item id="2160" countmax="5" chance="100000" /><!-- crystal coin -->
	</loot>
</monster>
"""


def boss_xml(num, b, hp, scale_):
    look, race, area, elem = LOOKS[b['tier']]
    mmax = int(round(scale_ / 100.0) * 100)
    amax = int(round(scale_ * 0.8 / 100.0) * 100)
    band = [x['name'] for x in num['tiers']['bands'] if x['first'] <= b['tier'] <= x['last']][0]
    row = run_row(num, b['tier'])
    exp = int(round(0.08 * row['runExp'] / num['bal']['assume']['stage'] / 1000.0) * 1000)
    return TEMPLATE % {'band': band, 'tier': b['tier'], 'level': row['level'], 'look': look, 'seconds': b['seconds'], 'die': b['dieSeconds'],
                       'name': b['monster'], 'race': race, 'exp': exp, 'hp': hp, 'mmin': mmax // 2, 'mmax': mmax, 'amin': amax // 2,
                       'amax': amax, 'elem': elem, 'area': area}


def die_seconds(num, b, text):
    a = S.parse_monster(text)[1]
    L = num['tiers']['tiers'][b['tier'] - 1]['level']
    P = player_level(num, L)
    d = cached(('dump', P), lambda: S.dump([P]))
    one = S.monster_dps(d, dict(d['balance'], tierMean=1.0), L, a)
    pack = {'melee': one['melee'], 'physical': one['physical'], 'element': one['element'], 'meleeHits': 0.5}
    gear, varm = cached('gear', S.gear_curves), cached('varm', S.vocation_armour)
    rows = []
    for cls in S.ORDER:
        cands = [S.survive(d, d['balance'], cls, P, bb, pack, gear, varm) for bb in d['builds'][cls][str(P)]]
        cands.sort(key=lambda r: r['burst'])
        rows.append(cands[len(cands) // 2])
    return statistics.median(r['burst'] for r in rows)


def fit_boss(num, b):
    """(health, melee max) so that the median class kills it in `seconds` and lives `dieSeconds` under its hits (bisection on the hit)"""
    want = band_row(num, dict(b, file='__none__'))['wantHealth']
    hp = int(round(want / 1000.0) * 1000)
    lo, hi = 100.0, 400000.0
    for _ in range(30):
        mid = (lo + hi) / 2
        if die_seconds(num, b, boss_xml(num, b, hp, mid)) > b['dieSeconds']:
            lo = mid
        else:
            hi = mid
    return hp, (lo + hi) / 2


def write_bosses(num):
    os.makedirs(BOSSES, exist_ok=True)
    for b in num['endgame']['bandBosses']:
        hp, m = fit_boss(num, b)
        text = boss_xml(num, b, hp, m)
        # the repository's monster rules (tools/ci/check_content.py): flat armour and defence capped by level, resistance caps
        import tune_monsters as tune
        text = tune.flat.xml(text, tune.flat.Pool(tune.flat.POOL), tune.flat.read_config())[0]
        text = tune.resists.xml(text)[0]
        with open(os.path.join(BOSSES, b['file'] + '.xml'), 'w', encoding='utf-8', newline='\n') as f:
            f.write(text)
        print('wrote %s: health %d, melee max %d' % (b['file'], hp, int(round(m / 100.0) * 100)))


# ------------------------------------------------------------------------------------------------ corruption and atlas
def corrupt_check(num):
    eg, lim = num['endgame'], num['bal']['limits']
    cr = eg['corrupt']
    errs = []
    if cr['breakChance'] > lim['corruptBreakMax']:
        errs.append('corruption: break chance %d%% over %d%%' % (cr['breakChance'], lim['corruptBreakMax']))
    cap = {'quantity': 120, 'rarity': 110, 'experience': 80}   # waystone_mods_config.lua bonusCap
    return errs, cap


def atlas_check(num):
    eg, lim = num['endgame'], num['bal']['limits']
    st = eg['atlas']['stats']
    full = sum(s['maxRank'] * eg['atlas']['cost'] for s in st)
    pts = len(num['tiers']['tiers'])
    errs = []
    if pts < full * 0.5:
        errs.append('atlas: %d points buy under half of the %d ranks' % (pts, full))
    if pts > full * lim['atlasFullShare']:
        errs.append('atlas: %d points would fill every stat (%d ranks, share %.2f)' % (pts, full, lim['atlasFullShare']))
    return errs, full, pts


def check(num, rows, bands):
    lim = num['bal']['limits']
    errs = []
    for r in rows:
        t = r['tier']
        lo_c = deep_target(num, t, 'deepClearSeconds') * (1 - lim['deepClearTol']) if t >= 16 else lim['clearSeconds'][0]
        if not lo_c <= r['clear'] <= lim['clearSeconds'][1]:
            errs.append('tier %d: a plain run takes %.0f s, outside %d-%d' % (t, r['clear'], lo_c, lim['clearSeconds'][1]))
        if t >= 16:
            want = deep_target(num, t, 'deepClearSeconds')
            if abs(r['clear'] - want) > lim['deepClearTol'] * want:
                errs.append('tier %d: a plain run takes %.0f s, the target is %.0f s (tolerance %.0f%%)' % (t, r['clear'], want, lim['deepClearTol'] * 100))
            if r['level'] > num['bal']['assume']['playerCap'] or r['player'] > num['bal']['assume']['playerCap']:
                errs.append('tier %d: level %d (player %d) is above the cap %d' % (t, r['level'], r['player'], num['bal']['assume']['playerCap']))
        if r['sustain'] < lim['sustainMin']:
            errs.append('tier %d: the median class heals %.2f x the pack damage, under %.2f' % (t, r['sustain'], lim['sustainMin']))
        if r['worst'] < lim['burstShare']:
            errs.append('tier %d: the weakest class lives %.2f x the median, under %.2f' % (t, r['worst'], lim['burstShare']))
        if t >= 16 and not lim['expRatio'][0] <= r['ratio'] <= lim['expRatio'][1]:
            errs.append('tier %d: a plain run pays %.2f x the hunt experience, outside %.2f-%.2f' % (t, r['ratio'], lim['expRatio'][0], lim['expRatio'][1]))
    # O672: every tier is at most at the cap, and the ten deep tiers are a curve at the cap: each harder than the one before (a longer run,
    # a lower sustain), no step a wall, tier XVI harder than XV (no free first step), none harder than the last tier's target
    cap = num['bal']['assume']['playerCap']
    for t, e in enumerate(num['tiers']['tiers'], 1):
        if e['level'] > cap:
            errs.append('tier %d: monster level %d is above the player cap %d' % (t, e['level'], cap))
    for t in range(16, len(num['tiers']['tiers']) + 1):
        a0, a1 = rows[t - 2], rows[t - 1]
        if not a1['clear'] > a0['clear']:
            errs.append('tier %d: a plain run (%.0f s) is not longer than tier %d (%.0f s)' % (t, a1['clear'], t - 1, a0['clear']))
        if not a1['sustain'] < a0['sustain']:
            errs.append('tier %d: sustain %.2f is not under tier %d (%.2f)' % (t, a1['sustain'], t - 1, a0['sustain']))
        if t > 16 and a1['clear'] > a0['clear'] * lim['deepStepClear']:
            errs.append('tier %d: a plain run grows %.2f x from tier %d, over %.2f x (a wall)' % (t, a1['clear'] / a0['clear'], t - 1, lim['deepStepClear']))
        if t > 16 and a0['sustain'] - a1['sustain'] > lim['deepStepSustain'] * a0['sustain']:
            errs.append('tier %d: sustain falls %.0f%% from tier %d (%.2f to %.2f), over %.0f%% (a wall)' % (
                t, 100 * (1 - a1['sustain'] / a0['sustain']), t - 1, a0['sustain'], a1['sustain'], 100 * lim['deepStepSustain']))
    for b in bands:
        if not b['xml']:
            errs.append('band boss %s (tier %d): no file in waystone_bosses' % (b['monster'], b['tier']))
            continue
        if abs(b['xml']['health'] - b['wantHealth']) > lim['bandKillTol'] * b['wantHealth']:
            errs.append('band boss %s: XML health %d, derived %d (tolerance %.0f%%)' % (b['monster'], b['xml']['health'], b['wantHealth'], lim['bandKillTol'] * 100))
        if b.get('die', 0) < lim['bandDieMin']:
            errs.append('band boss %s: the median class lives %.1f s under its hits, under %d s' % (b['monster'], b.get('die', 0), lim['bandDieMin']))
    errs += limits(num)[1]
    e1, _ = corrupt_check(num)
    e2, _, _ = atlas_check(num)
    errs += e1 + e2
    # the committed deep factors against the derivation, every deep tier
    for t in range(16, len(num['tiers']['tiers']) + 1):
        for name, have, want in zip(('health', 'damage', 'experience'), (deep_factor(num, t, 'health'), deep_factor(num, t, 'damage'),
                                    deep_factor(num, t, 'experience')), derive_deep(num, t)):
            if abs(have - want) > lim['derivedTol'] * want:
                errs.append('tier %d: deep %s factor %.3f, derived %.3f (tolerance %.0f%%)' % (t, name, have, want, lim['derivedTol'] * 100))
        r = rows[t - 1]
        if not lim['deepSustainRange'][0] <= r['sustain'] <= lim['deepSustainRange'][1]:
            errs.append('tier %d: sustain %.2f outside %.1f-%.1f' % (t, r['sustain'], lim['deepSustainRange'][0], lim['deepSustainRange'][1]))
    return errs


def limits(num):
    """what the engine and our formulas do at the top level (the cap 2500, the median class at the cap): returns (lines, errors). The numbers that could overflow:
    the experience of the level (Lua doubles and the engine's uint64), a monster's health after the level factor (int32, K.health clamps),
    a class's health and mana (int32), the display level (src-patch 0044: int32), the experience stage (open ended)"""
    tc = num['tiers']
    top = tc['tiers'][-1]['level']
    P = player_level(num, top)
    lines, errs = [], []
    exp = exp_for_level(P + 1)
    lines.append('experience to level %d: %.3e (a double holds 9e15, the engine uint64 1.8e19)' % (P + 1, exp))
    if exp >= 2 ** 53:
        errs.append('limits: the experience of level %d is over 2^53' % (P + 1))
    d = cached(('dump', P), lambda: S.dump([P]))
    big = 0
    for cls, c in d['classes'].items():
        big = max(big, c['health'] + c['gainhp'] * (P - 1), c['mana'] + c['gainmana'] * (P - 1))
    lines.append('the biggest class health or mana at level %d: %s (int32 max 2,147,483,647)' % (P, '{:,.0f}'.format(big)))
    if big >= 2 ** 31:
        errs.append('limits: a class health or mana at level %d reaches int32' % P)
    row = run_row(num, len(tc['tiers']))
    lines.append('a monster of tier %d: %s health, a boss %s (K.health clamps at 2,147,483,647)' % (
        len(tc['tiers']), '{:,.0f}'.format(row['monsterHp']), '{:,.0f}'.format(row['bossHp'])))
    if row['bossHp'] >= 2 ** 31:
        errs.append('limits: the boss health of the top tier reaches int32')
    lines.append('display level %d: int32 since src-patch 0044 (monster_levels.lua); the experience stage x%d is open ended from level 951 (late_game.py)'
                 % (top, num['bal']['assume']['stage']))
    lines.append('above level 2000 the models extrapolate flat or along their line: the pace curves (pace_config.lua scaled) are flat, '
                 'class_dps_model.py keeps its line (median 1 target %.0f at %d), the hunt pool, the weapon bands (2200) and the leveling '
                 'model (2200) end below: no hunt of the level exists' % (CD.median_dps(P)[0], P))
    return lines, errs


def report(rows, bands):
    print('| Tier | Level | Monster hp | Sweep s | Boss s | Clear s | Burst s | Sustain | Worst | Exp/h vs hunt | Min / level |')
    print('|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|')
    for r in rows:
        print('| %d | %d | %s | %.0f | %.0f | %.0f | %.1f | %.2f | %.2f | %.2f | %.1f |' % (
            r['tier'], r['level'], '{:,.0f}'.format(r['monsterHp']), r['sweep'], r['bossSeconds'], r['clear'], r['burst'], r['sustain'],
            r['worst'], r['ratio'], r['minPerLevel']))
    print('\nband bosses')
    print('| Tier | Level | Boss | Planned hp | XML hp | Kill s | Die s | Wanted dps | Its dps |')
    print('|---:|---:|---|---:|---:|---:|---:|---:|---:|')
    for b in bands:
        x = b['xml']
        print('| %d | %d | %s | %s | %s | %s | %s | %.0f | %s |' % (
            b['tier'], b['level'], b['monster'], '{:,.0f}'.format(b['wantHealth']), '{:,.0f}'.format(x['health']) if x else '-',
            '%.0f' % b['kill'] if 'kill' in b else '-', '%.1f' % b['die'] if 'die' in b else '-', b['wantDps'], '%.0f' % b['dps'] if 'dps' in b else '-'))


def main(argv):
    num = numbers()
    tiers = [int(x) for x in argv[argv.index('--tiers') + 1].split(',')] if '--tiers' in argv else list(range(1, len(num['tiers']['tiers']) + 1))
    if '--write-bosses' in argv:
        write_bosses(num)
        return 0
    if '--derive' in argv:
        print('derived deep factors per tier (health, damage, experience):')
        pts = {}
        for t in range(16, 26):
            f = derive_deep(num, t)
            pts[t] = f
            print('  tier %d: health x%.3f damage x%.3f experience x%.2f' % (t, f[0], f[1], f[2]))
        for i, name in enumerate(('health', 'damage', 'experience')):
            a0, a1 = pts[16][i], pts[25][i]
            print('  %s: base %.3f perTier %.4f (the line through tiers 16 and 25)' % (name, a0, (a1 - a0) / 9.0))
        for b in num['endgame']['bandBosses']:
            r = band_row(num, b)
            print('  band boss %s: health %d, attacks to total %.0f damage a second (before the engine factor)' % (b['monster'], r['wantHealth'], r['wantDps']))
        return 0
    rows = [run_row(num, t) for t in tiers]
    bands = [band_row(num, b) for b in num['endgame']['bandBosses']]
    report(rows, bands)
    errs, full, pts = atlas_check(num)
    print('\natlas: %d points (one a tier), %d ranks of the four stats' % (pts, full))
    print('\nlimits at the top level')
    for line in limits(num)[0]:
        print('  ' + line)
    if '--check' in argv:
        errs = check(num, rows if len(tiers) == len(num['tiers']['tiers']) else [run_row(num, t) for t in range(1, 26)], bands)
        for e in errs:
            print('FAIL', e)
        print('waystone_endgame_model: %s' % ('FAIL (%d)' % len(errs) if errs else 'OK'))
        return 1 if errs else 0
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
