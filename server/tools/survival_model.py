#!/usr/bin/env python3
"""The hunt survival model (O367): how long every class lives in a pack of its hunt, against the median class (computed,
not measured; server/README.md "Hunt survival by class (O367)").

usage: python3 -I server/tools/survival_model.py [--levels 670,750] [--detail] [--monsters] [--legacy] [--check]

Owner report 2026-11-02: a level 757 Ninja cannot hunt level 750 monsters, it takes too much damage. The model answers
"is the class out of line, or is the hunt too hard for everyone".

Without a flag: one table per hunting level (the player `gap` levels above it): health, damage taken per second in the
pack, seconds to die with no healing (burst), healing per second, healing against damage (sustain), each against the
median class. --detail adds the layers (armour, absorb, dodge, toughness, mana pool); --monsters lists the hunt's monsters
and their damage per second at each layer; --legacy prints the state before O367 next to today (`legacy` below).

--check (CI): at every level of `levels` every class lives at least `burstShare` x the median class's burst seconds, and
the median class heals at least `sustainMin` x the pack's damage per second (survival_balance_config.lua).

Inputs (everything in the repo; tools/survival_numbers.lua dumps the Lua side as JSON, luajit or $LUAJIT):
  start_stats.lua             level 1 health and mana and the gains per level of every class
  passive_builds_data.lua     the three role builds of every class (the Auto builds), cut to the tree points of the level:
                              vitality (% health), spirit (% mana), physical and elemental absorb (at most maxAbsorb), the
                              flags Fleet Shadow, Blackblood Creed, Scarred Discipline, Immovable
  chaos_constants.lua         the Thief line's evasion (+ Fleet Shadow), monk_chi_core.lua the Monk line's
  pace_config.lua             `damage`: a level-scaled monster's damage to players by its level
  monster_damage_config.lua   the late-game physical boost (melee and ranged origin only)
  potions_config.lua          the Everfull potions (roll + a percent of the maximum health or mana)
  templar_aura_core.lua       the Templar's and the Inquisitor's own aura
  chaos_vocations*.xml        the vocation's armour factor (<formula armor>)
  install_gear_sets.py        CURVES and FIT_SHARE: the armour of the level's set gear by weight, shield and weapon defence
  bounty_pool.lua, data/monster/monsters/chaos/**   the hunt's monsters (level-scaled, within `band`) and their attacks

The model, per class and level (one build: the role build with the median burst; the engine's order):
  monster hit: melee (origin melee; armour, block, dodge) and "physical" spells (origin ranged; armour, dodge) every
  interval with their chance, the mean of min and max; elemental spells (origin spell) take only the absorbs. Each hit is
  x (1 + engineBonus x level) x pace damage(level) x tierMean, the physical ones x (1 + boost(level) / 100).
  armour = (helmet + body + legs) x fit + boots + amulet + ring + rarityPerPiece x armourPieces, x the vocation's factor;
  reduction armour / (armour + K), at most armorCap. Block: one a second at most, 0.75 d off a melee hit.
  health = (start + gain x (level - 1)) x (1 + vitality value / 100); mana the same with spirit (Ward of the Mind lines:
  the mana adds to the health pool, and the potion is the better of health and mana)
  damage per second = pack x the mean monster's, after armour, block, absorb, dodge and toughness
  healing per second = potionsPerSecond x (roll + percent x max) + the self heal of the line at the level
  burst = pool / damage; sustain = healing / damage; seconds to die = pool / (damage - healing) (never when healing wins)
Not in it: gear modifiers and gems (life leech, dodge, block, "damage taken from monsters"), blessings, the Paragon track,
party heals, kiting, Shadow Veil, mana spent on spells. They are the same kind of thing for every class or move with play.
"""
import json, math, os, re, statistics, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
SERVER = os.path.normpath(os.path.join(HERE, '..'))
CHAOS = os.path.join(SERVER, 'data', 'scripts', 'chaos')
POOL = os.path.join(CHAOS, 'bounty_pool.lua')
MONSTERS = os.path.join(SERVER, 'data', 'monster', 'monsters', 'chaos')
VOC_DIR = os.path.join(SERVER, 'data', 'XML')
GEAR = os.path.join(HERE, 'install_gear_sets.py')

ORDER = ['warrior', 'juggernaut', 'berserker', 'ranger', 'deadeye', 'beastmaster', 'mystic', 'elementalist',
         'illusionist', 'thief', 'ninja', 'samurai', 'necromancer', 'lich', 'bonelord', 'monk', 'shadowfist', 'ironsage',
         'templar', 'inquisitor', 'sentinel']
NAMES = {'bonelord': 'Bone Lord', 'ironsage': 'Iron Sage'}


def name(key):
    return NAMES.get(key, key.capitalize())


def lua_bin():
    return os.environ.get('LUAJIT', 'luajit')


_dump = {}


def dump(levels):
    """the Lua side for these player levels (tools/survival_numbers.lua)"""
    key = tuple(sorted(set(int(x) for x in levels)))
    if key not in _dump:
        args = [lua_bin(), 'tools/survival_numbers.lua'] + [str(x) for x in key]
        out = subprocess.run(args, cwd=SERVER, check=True, capture_output=True, text=True).stdout
        _dump[key] = json.loads(out)
    return _dump[key]


def lin(points, x):
    """linear between {level, value} points, flat outside"""
    pts = sorted((float(a), float(b)) for a, b in points)
    if x <= pts[0][0]:
        return pts[0][1]
    for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
        if x <= x1:
            return y0 + (y1 - y0) * (x - x0) / (x1 - x0)
    return pts[-1][1]


def read(path):
    with open(path, encoding='utf-8', errors='replace') as f:
        return f.read()


# ------------------------------------------------------------------------------------------------ game formulas
def soft_cap(raw, cap, h):
    """ChaosSoftCap: raw up to the cap, then cap + H ln(1 + (raw - cap) / H)"""
    return raw if raw <= cap else cap + h * math.log(1 + (raw - cap) / h)


def char_stat(eff, points, stat):
    """ChaosPassiveCharStat (passivetree_effects.lua): the stat's value (vitality: % health) from its tree points"""
    knee, cap, mx = eff['charStatKnee'][stat], eff['charStatCap'][stat], eff['charStatMax'][stat]
    share = eff['charStatKneeShare']
    raw = max(0.0, points or 0)
    p = min(raw, cap)
    v = mx * share * p / knee if p <= knee else mx * share + mx * (1 - share) * (p - knee) / (cap - knee)
    if raw > cap:
        slope = mx * (1 - share) / (cap - knee) if cap > knee else 0
        v += slope * (soft_cap(raw, cap, eff['softCap']['charStatH'][stat]) - cap)
    return math.floor(v * 1e6 + 0.5) / 1e6


def absorb(eff, value):
    """ChaosPassiveAbsorbPercent: whole percent, at most maxAbsorb"""
    return math.floor(max(0, min(eff['maxAbsorb'], value)) + 1e-6)


def armour_reduction(armour, k, cap):
    return min(cap / 100.0, armour / float(armour + k)) if armour > 0 else 0.0


def boost_percent(points, level):
    """ChaosMonsterDamageCore.percentFor: linear between the points, flat beyond the ends"""
    return lin([(p['level'], p['percent']) for p in points], level) if points else 0.0


# ------------------------------------------------------------------------------------------------ data files
def gear_curves(text=None):
    """{curve: [(level, value), ...]} and FIT_SHARE of install_gear_sets.py"""
    text = text if text is not None else read(GEAR)
    anchors = [int(x) for x in re.search(r'ANCHORS = \(([^)]*)\)', text).group(1).split(',')]
    curves = {}
    for k, vals in re.findall(r"'(\w+)': \(([0-9., ]+)\),", text.split('CURVES = {', 1)[1].split('\n}', 1)[0]):
        curves[k] = list(zip(anchors, [float(v) for v in vals.split(',')]))
    fit = {k: float(v) for k, v in re.findall(r"'(\w)': ([0-9.]+)", re.search(r'FIT_SHARE = \{([^}]*)\}', text).group(1))}
    return curves, fit


def vocation_armour():
    """{vocation id: <formula armor>} of chaos_vocations*.xml"""
    out = {}
    for f in sorted(os.listdir(VOC_DIR)):
        if f.startswith('chaos_vocations') and f.endswith('.xml'):
            for m in re.finditer(r'<vocation id="(\d+)"[^>]*>\s*<formula[^>]*\barmor="([0-9.]+)"', read(os.path.join(VOC_DIR, f))):
                out[int(m.group(1))] = float(m.group(2))
    return out


def attr(tag, key, default=None):
    m = re.search(r'\b' + key + r'="([^"]*)"', tag)
    return m.group(1) if m else default


def parse_monster(text):
    """(level, [attack]) of a monster XML: level = the middle of <level> (engine patch 0082); attack = {kind, mean,
    interval, chance}, kind melee / physical / element"""
    lv = re.search(r'<level\s+min="(\d+)"\s+max="(\d+)"', text)
    level = (int(lv.group(1)) + int(lv.group(2))) / 2.0 if lv else 0
    attacks = []
    block = re.search(r'<attacks>(.*?)</attacks>', text, re.S)
    for tag in re.findall(r'<attack\s[^>]*>', block.group(1) if block else ''):
        nm = (attr(tag, 'name') or '').lower()
        lo, hi = abs(int(attr(tag, 'min', '0'))), abs(int(attr(tag, 'max', '0')))
        if hi <= 0 and lo <= 0:
            continue
        kind = 'melee' if nm == 'melee' else 'physical' if nm in ('physical', 'bleed') else 'element'
        attacks.append({'kind': kind, 'mean': (lo + hi) / 2.0, 'interval': int(attr(tag, 'interval', '2000')),
                        'chance': 100 if kind == 'melee' else int(attr(tag, 'chance', '100'))})
    return level, attacks


def scaled_monsters():
    """{lower name: (level, attacks)} of the level-scaled Chaos monsters (every XML under monsters/chaos with <level>)"""
    out = {}
    for root, _, files in os.walk(MONSTERS):
        for f in sorted(files):
            if f.endswith('.xml'):
                t = read(os.path.join(root, f))
                n = re.search(r'<monster\s[^>]*name="([^"]+)"', t)
                if n and re.search(r'<level\s+min="\d+"', t):
                    out[n.group(1).lower()] = parse_monster(t)
    return out


def hunt(level, band, pool_text=None, monsters=None):
    """the hunt's monsters: [(name, spawns, level, attacks)] of the bounty pool within band of the hunting level"""
    txt = (pool_text if pool_text is not None else read(POOL)).split('\tbosses = ')[0]
    monsters = monsters if monsters is not None else scaled_monsters()
    out = []
    for m in re.finditer(r'\{name = "([^"]+)", level = (\d+), exp = \d+, health = \d+, spawns = (\d+)', txt):
        nm, lv, sp = m.group(1), int(m.group(2)), int(m.group(3))
        if abs(lv - level) <= band and nm.lower() in monsters and monsters[nm.lower()][1]:
            mlv, attacks = monsters[nm.lower()]
            out.append((nm, sp, mlv, attacks))
    return out


# ------------------------------------------------------------------------------------------------ the model
def monster_dps(d, bal, level, attacks):
    """damage per second of one monster before the player's layers: {melee, physical, element}"""
    pace = lin(d['pace']['damage'], level) if d['pace'].get('enabled', True) else 1.0
    boost = boost_percent(d['boost']['points'], level) if d['boost'].get('enabled', True) else 0.0
    base = (1 + bal['engineBonus'] * level) * pace * bal['tierMean']
    out = {'melee': 0.0, 'physical': 0.0, 'element': 0.0}
    for a in attacks:
        v = a['mean'] * a['chance'] / 100.0 / (a['interval'] / 1000.0) * base
        if a['kind'] != 'element' or d['boost'].get('elemental'):
            v *= 1 + boost / 100.0
        out[a['kind']] += v
    return out


def pack_dps(d, bal, level, mons):
    """the mean monster of the hunt (weighted by spawns) x pack: {melee, physical, element, meleeHits}"""
    total = sum(sp for _, sp, _, _ in mons)
    out = {'melee': 0.0, 'physical': 0.0, 'element': 0.0, 'meleeHits': 0.0}
    for _, sp, mlv, attacks in mons:
        one = monster_dps(d, bal, mlv, attacks)
        for k in ('melee', 'physical', 'element'):
            out[k] += one[k] * sp / total * bal['pack']
        out['meleeHits'] += sum(1000.0 / a['interval'] for a in attacks if a['kind'] == 'melee') * sp / total * bal['pack']
    return out


def in_list(bal, key, cls):
    return cls in (bal.get(key) or [])


def self_heal(bal, cls, line, level):
    row = bal['selfHeal'].get(cls) or bal['selfHeal'].get(line) or [0, 0]
    return lin([(300, row[0]), (1000, row[1])], level)


def potion(d, bal, line, pool):
    """the potion of tier potionTier of a line ('health' / 'mana'): roll mean + percent of the pool"""
    tier = bal['potionTier']
    pct = d['potions']['amount']['everfullPct'][tier - 1]
    row = next(p for p in d['potions']['everfull'] if p['line'] == line and p['tier'] == tier)
    rng = row[line]
    return (rng[0] + rng[1]) / 2.0 + pool * pct / 100.0


def evasion(d, cls_id, flags):
    e = d['evasion'].get(str(cls_id))
    if e is not None:
        e += d['fx']['fleetShadow'] if 'ctFleetShadow' in flags else 0
        return e * (d['fx']['creedScale'] if 'ksBlackbloodCreed' in flags else 1)
    e = d['monkEvasion'].get(str(cls_id), 0.0)
    return 0.0 if 'ksScarredDiscipline' in flags else e


def survive(d, bal, cls, level, build, pack, gear, varm, overrides=None):
    """one class at one player level with one build: a dict of every layer and the results"""
    o = overrides or {}
    c = dict(d['classes'][cls])
    c.update(o.get('classes', {}).get(cls, {}))
    eff = d['effects']
    flags = build['flags']
    curves, fit = gear
    weight = next(w for w, lst in bal['weight'].items() if cls in lst)
    f = fit[{'heavy': 'H', 'medium': 'M', 'cloth': 'C'}[weight]]
    jewel = lin(curves['jewel'], level)
    armour = ((lin(curves['helmet'], level) + lin(curves['armor'], level) + lin(curves['legs'], level)) * f
              + lin(curves['boots'], level) + jewel + max(0, jewel - 1) + bal['rarityPerPiece'] * bal['armourPieces'])
    armour *= varm.get(c['id'], 1.0)
    red = armour_reduction(armour, bal['armorK'], bal['armorCap'])
    vit = char_stat(eff, build['vitality'], 'vitality')
    spi = char_stat(eff, build['spirit'], 'spirit')
    health = (c['health'] + c['gainhp'] * (level - 1)) * (1 + vit / 100.0)
    mana = (c['mana'] + c['gainmana'] * (level - 1)) * (1 + spi / 100.0)
    shield = in_list(bal, 'manaShield', c['line'])
    absp = absorb(eff, build['absorbPhysical']) / 100.0
    abse = absorb(eff, build['absorbAllElements']) / 100.0
    dodge = evasion(d, c['id'], flags) + o.get('dodge', {}).get(cls, 0.0)
    tough = bal['toughness'].get(cls, 1.0)
    if in_list(bal, 'ownAura', cls):
        tough *= 1 - d['auras'][str(c['id'])]['reduction']
    if 'ksScarredDiscipline' in flags:
        tough *= 1 - d['fx']['scarred']
    if 'ksImmovable' in flags:
        tough *= 1 - d['fx']['immovable']
    tough *= 1 - o.get('reduction', {}).get(cls, 0.0)
    # block: one a second at most, 0.75 d off a melee hit
    if in_list(bal, 'blockShield', cls):
        dval = lin(curves['shield'], level)
    elif in_list(bal, 'blockWeapon', cls):
        dval = lin(curves['defense'], level)
    else:
        dval = 0.0
    dblock = (bal['blockSkill'] / 4.0 + 2.23) * dval * 0.15
    melee_hit = pack['melee'] / pack['meleeHits'] if pack['meleeHits'] else 0.0
    blocked = min(1.0, pack['meleeHits']) * min(0.75 * dblock, melee_hit * (1 - red))
    melee = max(0.0, pack['melee'] * (1 - red) - blocked)
    phys = (melee + pack['physical'] * (1 - red)) * (1 - absp) * (1 - dodge)
    elem = pack['element'] * (1 - abse)
    guard = 0.0 if o.get('noGuard') else d['guardAt'][str(c['id'])][str(int(level))]
    dmg = (phys + elem) * tough * (1 - guard)
    pool = health + (mana if shield else 0.0)
    pot = potion(d, bal, 'health', health)
    if shield:
        pot = max(pot, potion(d, bal, 'mana', mana))
    heal = bal['potionsPerSecond'] * pot + self_heal(bal, cls, c['line'], level)
    return {'class': cls, 'build': build['id'], 'flags': flags, 'health': health, 'mana': mana, 'pool': pool,
            'armour': armour, 'armourRed': red, 'absorbPhys': absp, 'absorbElem': abse, 'dodge': dodge, 'toughness': tough, 'guard': guard,
            'blocked': blocked, 'damage': dmg, 'heal': heal, 'burst': pool / dmg if dmg > 0 else float('inf'),
            'sustain': heal / dmg if dmg > 0 else float('inf'),
            'ttd': pool / (dmg - heal) if dmg > heal else float('inf'), 'vitality': vit}


def table(levels=None, overrides=None, bal_override=None):
    """{hunting level: {'pack': pack dps, 'monsters': [...], 'rows': {class: row}, 'median': {...}}}"""
    d0 = dump([1000])
    bal = dict(d0['balance'])
    bal.update(bal_override or {})
    levels = levels or [int(x) for x in bal['levels']]
    d = dump([lv + bal['gap'] for lv in levels])
    gear, varm, mons_all = gear_curves(), vocation_armour(), scaled_monsters()
    pool_text = read(POOL)
    out = {}
    for hl in levels:
        pl = hl + bal['gap']
        mons = hunt(hl, bal['band'], pool_text, mons_all)
        pack = pack_dps(d, bal, hl, mons)
        rows = {}
        for cls in ORDER:
            cands = [survive(d, bal, cls, pl, b, pack, gear, varm, overrides) for b in d['builds'][cls][str(pl)]]
            cands.sort(key=lambda r: r['burst'])
            rows[cls] = cands[len(cands) // 2]
        med = {k: statistics.median(r[k] for r in rows.values()) for k in ('health', 'pool', 'damage', 'heal', 'burst',
                                                                             'sustain')}
        out[hl] = {'player': pl, 'pack': pack, 'monsters': mons, 'rows': rows, 'median': med, 'balance': bal}
    return out


def check(res, bal):
    errors = []
    for hl, t in sorted(res.items()):
        med = t['median']
        for cls, r in t['rows'].items():
            if r['burst'] < bal['burstShare'] * med['burst']:
                errors.append('hunt %d: %s lives %.1f s with no healing, %.2f x the median class (%.1f s), under %.2f' % (
                    hl, name(cls), r['burst'], r['burst'] / med['burst'], med['burst'], bal['burstShare']))
        if med['sustain'] < bal['sustainMin']:
            errors.append('hunt %d: the median class heals %.2f x the pack damage, under %.2f' % (hl, med['sustain'],
                                                                                                  bal['sustainMin']))
    return errors


# the state before O367 (overrides of survive): no Ninja guard (chaos_constants.lua Chaos.classes.guard)
LEGACY = {'noGuard': True}


def fmt_s(x):
    return 'never' if x == float('inf') else '%.1f' % x


def report(res, detail=False):
    for hl, t in sorted(res.items()):
        p, med = t['pack'], t['median']
        print('\n== hunt level %d, player level %d: %d monsters (%s), pack of %d: %.0f damage/s before the player '
              '(melee %.0f, physical spells %.0f, elemental %.0f)' % (
                  hl, t['player'], len(t['monsters']), ', '.join(m[0] for m in t['monsters']), t['balance']['pack'],
                  p['melee'] + p['physical'] + p['element'], p['melee'], p['physical'], p['element']))
        head = '%-12s %7s %7s %7s %7s %6s %6s %6s %7s' % ('class', 'health', 'pool', 'dmg/s', 'heal/s', 'burst', 'x med',
                                                         'sust', 'die s')
        if detail:
            head += '  %6s %5s %5s %5s %5s %5s %5s %5s  %s' % ('armour', 'arm%', 'abs%', 'dodge', 'tough', 'guard', 'vit%',
                                                               'block', 'build')
        print(head)
        for cls in ORDER:
            r = t['rows'][cls]
            line = '%-12s %7.0f %7.0f %7.0f %7.0f %6.1f %6.2f %6.2f %7s' % (
                name(cls), r['health'], r['pool'], r['damage'], r['heal'], r['burst'], r['burst'] / med['burst'],
                r['sustain'], fmt_s(r['ttd']))
            if detail:
                line += '  %6.0f %5.1f %5.0f %5.1f %5.2f %5.2f %5.1f %5.0f  %s' % (
                    r['armour'], 100 * r['armourRed'], 100 * r['absorbPhys'], 100 * r['dodge'], r['toughness'],
                    r['guard'], r['vitality'], r['blocked'], r['build'])
            print(line)
        print('%-12s %7.0f %7.0f %7.0f %7.0f %6.1f %6s %6.2f' % ('median', med['health'], med['pool'], med['damage'],
                                                                med['heal'], med['burst'], '1.00', med['sustain']))


def monsters_report(res):
    for hl, t in sorted(res.items()):
        bal = t['balance']
        d = dump([t['player']])
        print('\n== hunt level %d' % hl)
        for nm, sp, mlv, attacks in t['monsters']:
            raw = sum(a['mean'] * a['chance'] / 100.0 / (a['interval'] / 1000.0) for a in attacks)
            one = monster_dps(d, bal, mlv, attacks)
            print('  %-20s level %4.0f spawns %4d: XML %5.0f/s, at the player before armour %5.0f/s (engine x%.3f, pace '
                  'x%.3f, boost +%.0f%% physical)' % (nm, mlv, sp, raw, sum(one.values()), 1 + bal['engineBonus'] * mlv,
                                                       lin(d['pace']['damage'], mlv), boost_percent(d['boost']['points'], mlv)))


def main(argv):
    levels = None
    if '--levels' in argv:
        levels = [int(x) for x in argv[argv.index('--levels') + 1].split(',')]
    res = table(levels)
    bal = next(iter(res.values()))['balance']
    if '--legacy' in argv:
        print('# before O367')
        report(table(levels, overrides=LEGACY), '--detail' in argv)
        print('\n# now')
    report(res, '--detail' in argv)
    if '--monsters' in argv:
        monsters_report(res)
    if '--check' in argv:
        errors = check(res, bal)
        for e in errors:
            print('FAIL ' + e)
        print('survival check: %s' % ('%d failure(s)' % len(errors) if errors else 'ok'))
        return 1 if errors else 0
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
