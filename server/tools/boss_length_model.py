#!/usr/bin/env python3
"""The boss lengths of the balance round (O475, owner 2026-11-10: "You can do everything"; computed, not measured).

usage: python3 -I server/tools/boss_length_model.py [--derive] [--pockets] [--check] [--party] [--upgrades]

--upgrades (O686 phase 3): the typical damage is the median class's with the spell upgrades (class_dps_model.py), and every committed health
is multiplied by H of the level it is planned for before it is held to the derivation (the committed numbers are today's: the game
multiplies them by H, ChaosSpellRanks.healthFactor), every committed damage number by the median class's gain; the planned seconds
(150, 55, 318, 360) stay. The tolerance grows by the distance of the typical kill time from today's at that level (spell_upgrade_model.py
slack): H is one curve, the median class's gain is not.

After the round (O470 to O474) the typical character deals more than the numbers the boss models were set with (the C4 median:
913 at level 300, 2,600 at 1000). This tool derives, from class_dps_model.py (the one source of class damage, after the round), the
numbers that give the bosses their planned length again, and --check holds the committed configs to them:

  dungeon bosses   150 s for the typical character of the level (the five generated dungeons): D.dps of dungeons_difficulty.lua is the
                   table below, healthMult of each boss is 150 s x D.dps(level + 25) / (file health x (1 + 0.0074 x boss level))
  rift guardian    55 s: rift_config.lua density.model dps1 / dps5 and their exponents, fitted to the same damage over the tiers'
                   minimum levels (the guardian's health follows: guardianSeconds x dps1 x guardianUptime; the packs keep their 225 s:
                   packSeconds, the same model on dps5)
  arena bosses     360 s for a party at its level (O637, Malgrath, the Drowned Crown: five typical characters of level 800, 85% uptime, 400
                   healed a second): ARENA_BOSSES, the XML health is seconds x (players x typical damage x uptime - heal), and the `ref` of its
                   row of boss_mechanics_config.lua (health, dps, heal, uptime, players) is the same numbers
  Omen guardian    5:18 solo at level 1000 (318 s with 380 healed a second at 75% uptime): the XML health of the three Omen guardians;
                   the Ascended Omens and the Cinderheart (XML health) and the models that fight them (uber_config.lua and
                   raid_config.lua refDps) and the five raid bosses (XML health) move by the same factor, so their documented times hold

  pocket bosses    (O704, owner decision 2026-11-21 on O702) the five world bosses fought in a pocket, alone or in a party of up to five, at the
                   world pocket's level (300): 300 s alone and 200 s for five of the median class (POCKET_SECONDS), the boss heals POCKET_HEAL_SHARE
                   of the median class's damage (the monster files heal 1,200-3,200 a second, above the 994 the median class deals), adds and totems
                   at the pocket's health: the `pocket` block and the "pocket <boss>" profiles of boss_mechanics_config.lua, the health curve of
                   pocketboss_config.lua (overrides world_1 .. world_5) and the kill times of the real boss_mechanics_core.lua (tools/pocket_numbers.lua,
                   luajit). --pockets prints the table before / after
O703 (party health curves, owner 2026-11-21): the mechanics' health factor (boss_mechanics_core.lua G.balance) is worked out for the fight's own
size and health curve, not the profile's own party (the solo one, or the party of five for Gorvath). --party prints the table (tools/
party_factor_numbers.lua, the real core), --check holds it: the five generated dungeon bosses keep their plan (150 s alone, about 102 s with
five) within PARTY_TOL at every size; Gorvath 495 s alone / 421 s with five (guildboss_config.lua targets, clear of the enrage by PARTY_ENRAGE_GAP);
Sangrith and Thalcyra do not move (the same factor at every size: their party health curve is 1.0 a player); Morvane's profile sits on its floor
(minHpMult 0.60), so its health is raised until the solo kill is the other guardians' (O710: ref health 533,800 and the file 1,198,500, x1.0676,
313.5 s alone within 1 s, about 268 s with five against 266) and its party time keeps the plan's ratio to it; and dungeons.lua, guildboss.lua and rift.lua hand attach the size and the curve.

The typical damage on one target is the median class at the level (class_dps_model.median_dps, 1 target) x the share a boss lets
through (BOSS_KEPT: the boss armour takes armourTarget.boss percent of the physical half, the resistance BOSS_RES of the elemental
half); on a pack it is the 5 target median x NORMAL_KEPT (armourTarget.normal, NORMAL_RES). BOSS_RES and NORMAL_RES are assumptions
(mean resistance of the monsters; the design's 30 and 15). Not in it: boss mechanics and the uptime, which the configs hold.

--derive   print the numbers (the table of D.dps, the five healthMult, the rift model, the Omen factor, the pocket bosses)
--pockets  print the pocket bosses' kill times before and after O704 (the table of server/README.md "Pocket boss profile (O704)")
--check    exit 1 when a committed number is more than 1.5% (the Omen XML 0.5%) off its derivation
"""
import json
import math
import json
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)
import class_dps_model as CD  # noqa: E402
import spell_upgrade_model as SU  # noqa: E402  the spell upgrades switch (O686 phase 3)

SERVER = os.path.normpath(os.path.join(HERE, '..'))
CHAOS = os.path.join(SERVER, 'data', 'scripts', 'chaos')
DUNGEONS = os.path.join(CHAOS, 'dungeons_difficulty.lua')
AREAGEN = os.path.join(CHAOS, 'areagen_config.lua')
RIFT = os.path.join(CHAOS, 'rift_config.lua')
UBER = os.path.join(CHAOS, 'uber_config.lua')
RAID = os.path.join(CHAOS, 'raid_config.lua')
DEFENCE = os.path.join(CHAOS, 'monster_defence_config.lua')
PVP = os.path.join(CHAOS, 'pvp_balance_config.lua')
OMENS = os.path.join(SERVER, 'data', 'monster', 'monsters', 'chaos', 'omens')
ASCENDED = os.path.join(SERVER, 'data', 'monster', 'monsters', 'chaos', 'ascended')
RAIDS = os.path.join(SERVER, 'data', 'monster', 'monsters', 'chaos', 'raid')
CHAOS_MONSTERS = os.path.join(SERVER, 'data', 'monster', 'monsters', 'chaos')
MECHANICS = os.path.join(CHAOS, 'boss_mechanics_config.lua')
RAID_OLD = {'gravewarden_ulthar.xml': 4000000, 'morwen_the_ash_sister.xml': 4400000, 'the_marrow_colossus.xml': 4800000,
            'vhoss_the_hexmaw.xml': 5000000, 'varkhul_the_ashen_sovereign.xml': 7200000}   # the XML health before O475

BOSS_RES, NORMAL_RES = 0.30, 0.15
DPS_LEVELS = (100, 200, 300, 500, 700, 850, 1000, 1500, 2000)
BOSS_SECONDS = 150          # a dungeon boss, solo, the typical character
GUARDIAN_SECONDS = 55       # a rift guardian (rift_config.lua density.model guardianSeconds)
OMEN_SECONDS = 318          # the Omen guardian solo at level 1000
OMEN_UPTIME, OMEN_HEAL = 0.75, 380   # uptime of the model and the guardian's heal a second (README "Solo kill times": 330-380)
OMEN_OLD = 500000           # the XML health before O475
ASCENDED_OLD, CINDER_OLD = 1200000, 1650000
REFDPS_OLD = 3000           # uber_config.lua / raid_config.lua model.refDps before O475
GEAR = 1.15                 # rift_config.lua density.model gear
# the arena bosses (O637): file under monsters/chaos, the key of its profile in boss_mechanics_config.lua, level, players, seconds to kill, uptime,
# heal a second (the XML's healing defense): a party of five typical characters, 360 s
ARENA_BOSSES = (('malgrath_the_drowned_crown.xml', 'malgrath, the drowned crown', 800, 5, 360, 0.85, 400),)
# the pocket bosses (O704): the planned fight of the five world bosses in a pocket for the median class at the pocket's level
POCKET_SECONDS = (300, 200)   # alone, five characters (boss_mechanics_config.lua pocket.seconds)
POCKET_PLAYERS = 5            # the pocket's party (pocketboss_config.lua party.max)
POCKET_UPTIME = 0.85          # the damage lands this share of the time, as the arena and pinnacle bosses (the mechanics' downtime comes on top)
POCKET_HEAL_SHARE = 0.10      # the boss heals this share of the median class's damage alone (Omen guardian 0.07, pinnacle 0.025)
POCKET_HEAL_MAX = 0.12        # no pocket boss heals more than this share of it, the file's own or scaled
POCKET_TOL = 0.03             # the kill time of every size, with the mechanics' factor, within 3% of the plan (the factor's floor and rounding)
POCKET_WEAK = 0.75            # the weakest class deals this share of the median (class_dps_model.py keeps every class within 25%)
POCKET_WEAK_SHARE = 0.6       # and finishes alone within this share of the pocket's limit (pocketboss_config.lua minutes x 60)
# the five generated dungeons: id, player level (dungeon level + 25), boss level, file health (the monster file's, README "Solo kill times")
DUNGEON_BOSSES = (('vault', 825, 900, 14800), ('marrow', 1025, 1100, 15000), ('crucible', 1325, 1400, 15500),
                  ('sanctum', 1625, 1700, 16000), ('throne', 2025, 2100, 16000))


def read(path):
    with open(path, encoding='utf-8') as f:
        return f.read()


def kept(kind):
    """the share of a typical hit that gets through: armour on the physical half, resistance on the elemental half"""
    armour = int(re.search(r'armourTarget = \{[^}]*\b%s = (\d+)' % kind, read(DEFENCE)).group(1)) / 100.0
    share = float(re.search(r'physicalShare = ([0-9.]+)', read(PVP)).group(1))
    res = BOSS_RES if kind == 'boss' else NORMAL_RES
    return share * (1 - armour) + (1 - share) * (1 - res)


def one_target(level):
    """damage per second of the typical character on one boss"""
    return CD.median_dps(level)[0] * kept('boss')


def area(level):
    """damage per second of the typical character on 5 targets (a pack)"""
    return CD.median_dps(level)[1] * kept('normal')


def dps_table():
    return [(lv, one_target(lv)) for lv in DPS_LEVELS]


def table_dps(rows, level):
    """the log-linear rule of D.dps: straight in log level and log damage between rows, flat above the last, scaled by the level below the first"""
    if level <= rows[0][0]:
        return rows[0][1] * max(level, 1) / float(rows[0][0])
    for (x0, y0), (x1, y1) in zip(rows, rows[1:]):
        if level <= x1:
            return y0 * (y1 / y0) ** (math.log(level / float(x0)) / math.log(x1 / float(x0)))
    return rows[-1][1]


def health_mult(rows, level, boss_level, file_health, seconds=BOSS_SECONDS):
    return seconds * table_dps(rows, level) / (file_health * (1 + 0.0074 * boss_level))


def fit(values, levels, gear=GEAR):
    """value at level 1000 and the exponent of a power law v = a x (L / 1000) ^ e x gear through the points (least squares in the logs)"""
    xs = [math.log(l / 1000.0) for l in levels]
    ys = [math.log(v / gear) for v in values]
    n = len(xs)
    mx, my = sum(xs) / n, sum(ys) / n
    e = sum((x - mx) * (y - my) for x, y in zip(xs, ys)) / sum((x - mx) ** 2 for x in xs)
    return math.exp(my - e * mx), e


def rift_levels():
    return [int(v) for v in re.findall(r'\{minLevel = (\d+), pick', read(RIFT))]


def rift_fit():
    lv = rift_levels()
    return fit([one_target(l) for l in lv], lv), fit([area(l) for l in lv], lv)


def arena_health(level, players, seconds, uptime, heal):
    """the XML health of an arena boss: seconds x (players x typical damage on one boss x uptime - heal a second)"""
    return seconds * (players * one_target(level) * uptime - heal)


def omen_factor():
    health = (one_target(1000) * OMEN_UPTIME - OMEN_HEAL) * OMEN_SECONDS
    return health, health / OMEN_OLD


# ------------------------------------------------------------------------------------------------ committed numbers
def committed_dps():
    text = read(DUNGEONS)
    m = re.search(r'\n\tdps = (\{\{[^\n]*\}\})\}', text)
    return [(int(a), float(b)) for a, b in re.findall(r'\{(\d+),\s*([0-9.]+)\}', m.group(1))]


def committed_mults():
    text = read(AREAGEN)
    out = {}
    for m in re.finditer(r'id = "(\w+)", name = "[^"]*", kind = "dungeon".*?healthMult = ([0-9.]+)', text, re.S):
        out[m.group(1)] = float(m.group(2))
    return out


def committed_rift():
    text = read(RIFT)
    g = lambda k: float(re.search(r'\b%s = ([0-9.]+)' % k, text).group(1))
    return (g('dps1'), g('dps1Exp')), (g('dps5'), g('dps5Exp'))


def committed_health(folder):
    out = {}
    for f in sorted(os.listdir(folder)):
        if f.endswith('.xml'):
            m = re.search(r'<health now="(\d+)"', read(os.path.join(folder, f)))
            if m:
                out[f] = int(m.group(1))
    return out


def committed_refdps():
    return float(re.search(r'refDps = (\d+)', read(UBER)).group(1)), float(re.search(r'refDps = (\d+)', read(RAID)).group(1))


def committed_arena(profile):
    """(health, heal, dps, uptime, players) of the `ref` of a profile of boss_mechanics_config.lua"""
    text = read(MECHANICS)
    m = re.search(r'\["%s"\] = \{.*?ref = \{health = (\d+), heal = (\d+), dps = (\d+), uptime = ([0-9.]+), players = (\d+)' % re.escape(profile),
                  text, re.S)
    return (int(m.group(1)), int(m.group(2)), int(m.group(3)), float(m.group(4)), int(m.group(5))) if m else None


def xml_heal(text):
    """the healing a second of the XML's healing defense: chance x the middle of min and max / the interval"""
    m = re.search(r'<defense name="healing" interval="(\d+)" chance="(\d+)" min="(\d+)" max="(\d+)"', text)
    return int(m.group(2)) / 100.0 * (int(m.group(3)) + int(m.group(4))) / 2.0 / (int(m.group(1)) / 1000.0) if m else 0.0


# ------------------------------------------------------------------------------------------------ pocket bosses (O704)
_pocket = []


def lua_bin():
    return os.environ.get('LUAJIT', 'luajit')


def pocket_numbers():
    """tools/pocket_numbers.lua: the pocket config, the world pocket bosses' files, curves and profiles, the kill times of the real core"""
    if not _pocket:
        out = subprocess.run([lua_bin(), os.path.join('tools', 'pocket_numbers.lua')], cwd=SERVER, check=True, capture_output=True, text=True).stdout
        _pocket.append(json.loads(out))
    return _pocket[0]


def pocket_plan(level, heal, uptime=POCKET_UPTIME, seconds=POCKET_SECONDS, players=POCKET_PLAYERS):
    """(health alone, perExtra of the party curve): seconds x (players x typical damage x uptime - heal), the same rule as the arena bosses"""
    d = one_target(level)
    solo = seconds[0] * (d * uptime - heal)
    party = seconds[1] * (players * d * uptime - heal)
    return solo, (party / solo - 1) / (players - 1)


def print_pockets():
    n = pocket_numbers()
    print('pocket bosses at level %d (the median class kills alone in %d s, five in %d s; limit %d s); before = the event profile, the file\'s heal,\n'
          'the world curve of 3%% (+2.5%% a player); after = the pocket profile (O704)' % (n['worldLevel'], POCKET_SECONDS[0], POCKET_SECONDS[1], n['limit']))
    print('%-30s %9s %10s %10s %10s %10s %10s' % ('boss', 'file heal', 'alone b', 'alone a', 'five b', 'five a', 'weak a'))
    for b in n['bosses']:
        def sec(v):
            return '%10s' % ('never' if v is None else '%.0f' % v)
        print('%-30s %9.0f %s %s %s %s %s' % (b['name'], b['xmlHeal'], sec(b['before'].get('1', {}).get('seconds')), sec(b['after']['1']['seconds']),
                                              sec(b['before'].get('5', {}).get('seconds')), sec(b['after']['5']['seconds']), sec(b['weak']['1'])))
    return 0


def pocket_problems():
    """the committed pocket numbers against the plan: the median class's damage at the pocket's level, the heal, the health and the curve (in
    boss_mechanics_config.lua and as fractions of the files in pocketboss_config.lua), the files' heal and the scale to the pocket's, the adds and
    totems at the pocket's size, and the kill time of every size with the mechanics' factor (the real core)"""
    bad = []
    n = pocket_numbers()
    P = n['pocket']
    level = n['worldLevel']
    if P['level'] != level:
        bad.append('pocket level %s, the world pocket is tuned for level %s (Chaos.worldBoss.minLevel)' % (P['level'], level))
    if [P['seconds']['solo'], P['seconds']['party']] != list(POCKET_SECONDS) or P['players'] != POCKET_PLAYERS or P['uptime'] != POCKET_UPTIME:
        bad.append('pocket plan %s s, %s players, uptime %s: the model asks %s s, %d, %s' % (P['seconds'], P['players'], P['uptime'], POCKET_SECONDS, POCKET_PLAYERS, POCKET_UPTIME))
    if n['partyMax'] != POCKET_PLAYERS:
        bad.append('the pocket party is %s, the model plans five (pocketboss_config.lua party.max)' % n['partyMax'])
    with SU.forced(False):  # the ref and the heal are the fight's numbers of today: the model's damage (the game multiplies the monster by H, the players grow by the gain)
        today = one_target(level)
    if abs(P['dps'] / today - 1) > 0.015:
        bad.append('pocket dps is %s, the median class on one boss at level %d deals %.0f' % (P['dps'], level, today))
    if abs(P['heal'] / (today * POCKET_HEAL_SHARE) - 1) > 0.05 or abs(P['healShare'] - POCKET_HEAL_SHARE) > 1e-9:
        bad.append('pocket heal is %s a second (share %s), %.0f%% of %.0f is %.0f' % (P['heal'], P['healShare'], POCKET_HEAL_SHARE * 100, today, today * POCKET_HEAL_SHARE))
    heal_tol = HEAL_UP_TOL if SU.active() else 0.0
    want_solo, want_extra = pocket_plan(level, P['heal'])
    if abs(P['health'] * _h(level) / want_solo - 1) > _tol(0.015, level) + heal_tol:
        bad.append('pocket health alone is %s x H %.3f, %d s of the median class (heal %s) is %.0f' % (P['health'], _h(level), POCKET_SECONDS[0], P['heal'], want_solo))
    have5 = P['health'] * (1 + P['perExtra'] * (POCKET_PLAYERS - 1))
    want5 = want_solo * (1 + want_extra * (POCKET_PLAYERS - 1))
    if abs(have5 * _h(level) / want5 - 1) > _tol(0.015, level) + heal_tol:
        bad.append('pocket health for five is %.0f x H %.3f (perExtra %s), %d s of five characters is %.0f' % (have5, _h(level), P['perExtra'], POCKET_SECONDS[1], want5))
    limit = n['limit']
    for b in n['bosses']:
        name = b['name']
        prof = b['profile']
        if not prof:
            bad.append('%s: no pocket profile "%s%s" in boss_mechanics_config.lua' % (name, P['prefix'], name.lower()))
            continue
        # the file: its health and heal are what the profile and the curve are written against
        if b['xmlHealth'] <= 0:
            bad.append('%s: no monster file health read' % name)
            continue
        px = prof['pocket']
        if abs(px['xmlHeal'] / b['xmlHeal'] - 1) > 0.01:
            bad.append('%s: pocket.xmlHeal %s, the monster file heals %.0f a second' % (name, px['xmlHeal'], b['xmlHeal']))
        scaled = b['xmlHeal'] * px['healScale']
        if abs(scaled / P['heal'] - 1) > 0.01:
            bad.append('%s: the file heals %.0f a second x healScale %.4f is %.0f, the pocket heal is %s' % (name, b['xmlHeal'], px['healScale'], scaled, P['heal']))
        if scaled > POCKET_HEAL_MAX * today:
            bad.append('%s: heals %.0f a second against the median class\'s %.0f (%.0f%%, over %.0f%%)' % (name, scaled, today, scaled / today * 100, POCKET_HEAL_MAX * 100))
        # the curve of pocketboss_config.lua (fractions of the file) is the profile's health and party curve
        st = b['settings']
        for size in range(1, POCKET_PLAYERS + 1):
            frac = min(st['solo'] + st['perExtra'] * (size - 1), st.get('max', 9e9))
            want = P['health'] * (1 + P['perExtra'] * (size - 1))
            if abs(frac * b['xmlHealth'] / want - 1) > 0.003:
                bad.append('%s x%d: pocketboss_config.lua health curve gives %.0f, the pocket health is %.0f' % (name, size, frac * b['xmlHealth'], want))
        ref = prof['ref']
        if ref['health'] != P['health'] or ref['heal'] != P['heal'] or ref['dps'] != P['dps'] or ref['uptime'] != P['uptime'] or ref['players'] != 1:
            bad.append('%s: the profile ref %s is not the pocket fight (health %s, heal %s, dps %s, uptime %s, alone)' % (name, ref, P['health'], P['heal'], P['dps'], P['uptime']))
        if ref.get('limit') != limit:
            bad.append('%s: the profile ref limit %s, the pocket lasts %s s' % (name, ref.get('limit'), limit))
        # the adds and totems are the event's x the pocket's health over the event's, and grow with the boss
        raid = b['event']
        if raid['health'] <= P['health'] * 10:
            bad.append('%s: the event ref health %s is not an event fight' % (name, raid['health']))
        for ph in prof.get('adds', []):
            if ph.get('healthPerExtra') != P['perExtra']:
                bad.append('%s: adds %s grow by %s a player, the boss by %s' % (name, ph.get('name'), ph.get('healthPerExtra'), P['perExtra']))
            if ph['health'] * ph.get('count', 1) > 0.15 * P['health']:
                bad.append('%s: adds %s of the pocket have %s health in all, over 15%% of the pocket boss' % (name, ph.get('name'), ph['health'] * ph.get('count', 1)))
        for m in prof.get('timed', []):
            if 'totemHealth' in m:
                if m.get('totemPerExtra') != P['perExtra']:
                    bad.append('%s: totem %s grows by %s a player, the boss by %s' % (name, m.get('totemName'), m.get('totemPerExtra'), P['perExtra']))
                if m['totemHealth'] > 0.05 * P['health']:
                    bad.append('%s: the totem %s has %s health, over 5%% of the pocket boss' % (name, m.get('totemName'), m['totemHealth']))
        # the kill time of every size with the mechanics' factor (the real core), the weakest class alone, no factor on the floor
        floor_ = prof.get('minHpMult', 0.6)
        times = []
        for size in range(1, POCKET_PLAYERS + 1):
            a = b['after'][str(size)]
            times.append(a['seconds'])
            plan = POCKET_SECONDS[0] if size == 1 else (POCKET_SECONDS[1] if size == POCKET_PLAYERS else None)
            if a['hpMult'] <= floor_ + 1e-9 or a['hpMult'] > 1 + 1e-9:
                bad.append('%s x%d: the mechanics\' factor %.4f is on the floor %.2f or above 1: the kill time is not kept' % (name, size, a['hpMult'], floor_))
            if plan and abs(a['seconds'] / plan - 1) > POCKET_TOL:
                bad.append('%s x%d: the median class kills it in %.0f s, planned %d (%.1f%% off, over %.0f%%)' % (name, size, a['seconds'], plan, abs(a['seconds'] / plan - 1) * 100, POCKET_TOL * 100))
            if a['seconds'] > limit:
                bad.append('%s x%d: %.0f s, over the %d s limit' % (name, size, a['seconds'], limit))
        if any(later > earlier * 1.001 for earlier, later in zip(times, times[1:])):
            bad.append('%s: a bigger party takes longer: %s' % (name, ['%.0f' % t for t in times]))
        weak = b['weak']['1']
        if weak is None or weak > POCKET_WEAK_SHARE * limit:
            bad.append('%s: the weakest class (x%.2f) alone takes %s s, over %.0f%% of the %d s limit' % (name, POCKET_WEAK, weak, POCKET_WEAK_SHARE * 100, limit))
    if len(n['bosses']) != 5:
        bad.append('%d world bosses, the model holds five' % len(n['bosses']))
    return bad


def lua_rows(rows):
    return '{' + ', '.join('{%d, %d}' % (lv, round(v)) for lv, v in rows) + '}'


def derive():
    rows = dps_table()
    print('D.dps rows (typical damage on one boss; median class x %.3f):' % kept('boss'))
    print('  ' + lua_rows(rows))
    print('\nhealthMult for %d s:' % BOSS_SECONDS)
    for name, lv, bl, hp in DUNGEON_BOSSES:
        print('  %-9s level %d: %.2f (health %.0f)' % (name, lv, health_mult([(l, round(v)) for l, v in rows], lv, bl, hp),
                                                      BOSS_SECONDS * table_dps(rows, lv)))
    (d1, e1), (d5, e5) = rift_fit()
    print('\nrift model: dps1 = %.0f, dps1Exp = %.2f, dps5 = %.0f, dps5Exp = %.2f (gear %.2f, tier levels %s)' % (
        d1, e1, d5, e5, GEAR, rift_levels()))
    print('\narena bosses (a party of typical characters):')
    for fname, profile, level, players, seconds, uptime, heal in ARENA_BOSSES:
        print('  %-34s level %d, %d players, %d s: health %.0f, party damage %.0f a second' % (
            fname, level, players, seconds, arena_health(level, players, seconds, uptime, heal), players * one_target(level)))
    pn = pocket_numbers()
    solo, extra = pocket_plan(pn['worldLevel'], pn['pocket']['heal'])
    print('\npocket bosses (level %d, %d s alone / %d s for five, heal %d a second): health %.0f, perExtra %.3f (committed %s / %s)' % (
        pn['worldLevel'], POCKET_SECONDS[0], POCKET_SECONDS[1], pn['pocket']['heal'], solo, extra, pn['pocket']['health'], pn['pocket']['perExtra']))
    h, f = omen_factor()
    print('\nOmen guardian health %.0f (x%.3f of %d): Ascended %.0f, Cinderheart %.0f, refDps %.0f' % (
        h, f, OMEN_OLD, ASCENDED_OLD * f, CINDER_OLD * f, REFDPS_OLD * f))
    return 0


RIFT_UP_TOL = 0.05   # the upgrades mode: a rift guardian or pack at any tier level dies within 5% of today's time (the spread of the spell share
#                      on one target against five is the same as in spell_upgrade_balance_config.lua limits killTimeFiveTargets)
HEAL_UP_TOL = 0.03   # the upgrades mode: a boss that heals (its heal is not multiplied by H) takes this much more of the tolerance


def _h(level):
    """what the game multiplies a committed health by at a level (H with the upgrades on, else 1)"""
    return SU.health(level)


def _g(level, targets=1):
    """what the median class's damage grows by at a level (the upgrades on, else 1)"""
    return SU.median_gain(level, targets)


def _tol(base, level, targets=1):
    return base + SU.slack(level, targets)


# ------------------------------------------------------------------------------------------------ O703: the factor of the fight's own size
PARTY_TOL = 0.015            # the kill time with the factor against the plain time of the size (the curve's own plan)
PARTY_ENRAGE_GAP = 60        # seconds the guild boss's solo kill must stay under its enrage
MORVANE_SOLO_TOL = 1.0       # seconds: Morvane alone against Sangrith alone (O710)
MORVANE_FIVE_TOL = 0.02      # Morvane with five against Sangrith with five
PARTY_FIVE = {'dungeon': 102.0}   # the dungeon curve 1 + 0.6 (n - 1): a group of five against 150 s alone (150 x 3.4 / 5)
_party = []


def lua_bin():
    return os.environ.get('LUAJIT', 'luajit')


def party_numbers():
    """tools/party_factor_numbers.lua: G.refForCurve / G.balance of the real core for each fight and size"""
    if not _party:
        out = subprocess.run([lua_bin(), os.path.join('tools', 'party_factor_numbers.lua')], cwd=SERVER, check=True, capture_output=True,
                             text=True).stdout
        _party.append(json.loads(out))
    return _party[0]


def party_problems(nums=None):
    nums = nums or party_numbers()
    bad = []
    guild = nums['guild']
    for f in nums['fights']:
        key, kind, rows = f['key'], f['kind'], f['rows']
        solo, five = rows['1'], rows['5']
        if kind != 'guild' and abs(solo['hpMult'] - solo['soloMult']) > 1e-9:
            bad.append('%s: alone the factor %.4f is not the solo one %.4f' % (key, solo['hpMult'], solo['soloMult']))
        if kind == 'dungeon':
            if abs(solo['final'] / BOSS_SECONDS - 1) > PARTY_TOL:
                bad.append('%s: alone %.0f s, planned %d' % (key, solo['final'], BOSS_SECONDS))
            if abs(five['final'] / PARTY_FIVE['dungeon'] - 1) > 0.02:
                bad.append('%s: five kill it in %.0f s, the curve plans %.0f' % (key, five['final'], PARTY_FIVE['dungeon']))
            for n, r in rows.items():
                if abs(r['final'] / r['base'] - 1) > PARTY_TOL:
                    bad.append('%s x%s: %.1f s with the factor, the plain time of the size is %.1f' % (key, n, r['final'], r['base']))
        elif kind == 'guild':
            t = guild['targets']
            for n, want in (('1', t['party1']), ('2', t['party2']), ('5', t['party5']), ('10', t['party10'])):
                got = rows[n]['final']
                if abs(got / want - 1) > 0.01:
                    bad.append('Gorvath x%s: %.0f s with the factor, the plan is %d' % (n, got, want))
            for n, r in rows.items():
                if abs(r['final'] / r['base'] - 1) > PARTY_TOL:
                    bad.append('Gorvath x%s: %.1f s with the factor, the plain time of the size is %.1f' % (n, r['final'], r['base']))
            if guild['enrageAt'] - solo['final'] < PARTY_ENRAGE_GAP:
                bad.append('Gorvath alone %.0f s is within %d s of the %d s enrage' % (solo['final'], PARTY_ENRAGE_GAP, guild['enrageAt']))
        elif key.startswith('morvane'):
            # the floor of the profile binds (the weakest class's rule): O710 raised its health until alone it takes the other Omen guardians'
            # time, and the party keeps the plan's ratio to it
            ref_s = [x for x in nums['fights'] if x['key'].startswith('sangrith')][0]['rows']
            if abs(solo['final'] - ref_s['1']['final']) > MORVANE_SOLO_TOL:
                bad.append('Morvane alone: %.1f s, Sangrith alone %.1f s (within %.0f s)' % (solo['final'], ref_s['1']['final'], MORVANE_SOLO_TOL))
            if abs(five['final'] / ref_s['5']['final'] - 1) > MORVANE_FIVE_TOL:
                bad.append('Morvane with five: %.1f s, Sangrith with five %.1f s (within %.0f%%)' % (
                    five['final'], ref_s['5']['final'], MORVANE_FIVE_TOL * 100))
            if abs(five['final'] / solo['final'] / (five['base'] / solo['base']) - 1) > PARTY_TOL:
                bad.append('Morvane: five take %.0f s against %.0f alone, the plain ratio is %.3f (the factor %.4f)' % (
                    five['final'], solo['final'], five['base'] / solo['base'], five['hpMult']))
        else:   # Sangrith, Thalcyra: no effect, the same factor at every size
            for n, r in rows.items():
                if abs(r['hpMult'] - r['soloMult']) > 1e-9:
                    bad.append('%s x%s: the factor moved to %.4f from %.4f (it must not)' % (key, n, r['hpMult'], r['soloMult']))
    return bad


def callsite_problems():
    """the engine files hand attach the size and the curve (they run only inside the engine)"""
    bad = []
    want = (('dungeons.lua', ('ChaosBossMech.hint(monster, run.size or 1', 'DIFF.partyHealth(n, cfg.party)')),
            ('guildboss.lua', ('partySize = run.size', 'B.healthMult(cfg, n)')),
            ('rift.lua', ('partySize = run.omen', 'R.omenHealthMult(C(), n)')),
            ('boss_mechanics.lua', ('G.refForCurve(profile.ref, opts.partySize or players, opts.healthCurve)', 'M.hints[id]')))
    for fname, needles in want:
        text = read(os.path.join(CHAOS, fname))
        for n in needles:
            if n not in text:
                bad.append("%s does not hand the mechanics the fight's size and health curve (missing: %s)" % (fname, n))
    return bad


def print_party():
    nums = party_numbers()
    print('mechanics health factor by size (with = kill time with it, today = with the factor the fights had; seconds of the ref):')
    for f in nums['fights']:
        print('  %-32s %s' % (f['key'], f['kind']))
        for n in sorted(f['rows'], key=int):
            r = f['rows'][n]
            print('    x%-2s factor %.4f (was %.4f)  plain %6.1f s  with factor %6.1f s  today %6.1f s' % (
                n, r['hpMult'], r['soloMult'], r['base'], r['final'], r['oldFinal']))
    return 0


def problems():
    bad = []
    rows = dps_table()
    have = committed_dps()
    if [lv for lv, _ in have] != list(DPS_LEVELS):
        bad.append('D.dps levels are %s, not %s' % ([lv for lv, _ in have], list(DPS_LEVELS)))
    else:
        for (lv, v), (_, c) in zip(rows, have):
            # a damage table of today's model: with the upgrades on the derivation has the gain in it and the table stays as it is (the
            # game multiplies the monster by H, the players grow by the gain), so it is held in the run of today only
            if not SU.active() and abs(c / v - 1) > 0.015:
                bad.append('D.dps at %d is %.0f, the derivation %.0f' % (lv, c, v))
    mults = committed_mults()
    for name, lv, bl, hp in DUNGEON_BOSSES:
        want = health_mult(have, lv, bl, hp) * _g(lv)
        if name not in mults or abs(mults[name] * _h(lv) / want - 1) > _tol(0.015, lv):
            bad.append('%s healthMult is %s, 150 s on the committed D.dps is %.2f' % (name, mults.get(name), want / _h(lv)))
    (c1, ce1), (c5, ce5) = committed_rift()
    (d1, e1), (d5, e5) = rift_fit()
    if not SU.active():
        for name, have_v, want_v in (('dps1', c1, d1), ('dps5', c5, d5)):
            if abs(have_v / want_v - 1) > 0.015:
                bad.append('rift %s is %.0f, the derivation %.0f' % (name, have_v, want_v))
        for name, have_v, want_v in (('dps1Exp', ce1, e1), ('dps5Exp', ce5, e5)):
            if abs(have_v - want_v) > 0.015:
                bad.append('rift %s is %.2f, the derivation %.2f' % (name, have_v, want_v))
    else:
        # the model's damage is today's, the guardian's health is seconds x it x H (rift.lua): the guardian (one target) and the pack (five)
        # of every tier level die in today's time when H is the typical damage's gain
        for l in rift_levels():
            for name, targets in (('guardian', 1), ('pack', 5)):
                if abs(_h(l) / SU.median_gain(l, targets) - 1) > RIFT_UP_TOL:
                    bad.append('rift %s at tier level %d: H %.3f against the typical damage gain %.3f, the kill time moves %+.1f%% (limit %.0f%%)' % (
                        name, l, _h(l), SU.median_gain(l, targets), (_h(l) / SU.median_gain(l, targets) - 1) * 100, RIFT_UP_TOL * 100))
    health, factor = omen_factor()
    h_omen = _h(1000)
    heal_tol = HEAL_UP_TOL if SU.active() else 0.0
    morvane = committed_arena('morvane the hollow crown')[0] / float(OMEN_OLD)   # O710: the one guardian on its floor has more health
    for f, v in committed_health(OMENS).items():
        want_h = health * (morvane if f.startswith('morvane') else 1.0)
        if abs(v * h_omen / want_h - 1) > _tol(0.005, 1000) + heal_tol:
            bad.append('Omen %s health %d x H %.3f, the derivation %.0f' % (f, v, h_omen, want_h))
    for f, v in committed_health(ASCENDED).items():
        old = {'ysgrath_the_cinderheart.xml': CINDER_OLD}.get(f, ASCENDED_OLD if f.startswith('ascended_') else None)
        if old and abs(v * h_omen / (old * factor) - 1) > _tol(0.005, 1000) + heal_tol:
            bad.append('%s health %d x H %.3f, the derivation %.0f' % (f, v, h_omen, old * factor))
    for f, v in committed_health(RAIDS).items():
        if f in RAID_OLD and abs(v * h_omen / (RAID_OLD[f] * factor) - 1) > _tol(0.005, 1000) + heal_tol:
            bad.append('raid boss %s health %d x H %.3f, the derivation %.0f' % (f, v, h_omen, RAID_OLD[f] * factor))
    for fname, profile, level, players, seconds, uptime, heal in ARENA_BOSSES:
        want = arena_health(level, players, seconds, uptime, heal)
        have = committed_health(CHAOS_MONSTERS).get(fname)
        if have is None or abs(have * _h(level) / want - 1) > _tol(0.015, level) + heal_tol:
            bad.append('arena boss %s health %s x H %.3f, the derivation %.0f (%d s for %d characters of level %d)' % (
                fname, have, _h(level), want, seconds, players, level))
        ref = committed_arena(profile)
        if ref is None:
            bad.append('arena boss %s: no profile %s with a ref in boss_mechanics_config.lua' % (fname, profile))
            continue
        with SU.forced(False):  # the ref is the fight's numbers of today: the XML, the model's damage (the game multiplies by H, the players by the gain)
            today_dps = players * one_target(level)
        for what, got, exp in (('health', ref[0], have or 0), ('heal', ref[1], heal), ('dps', ref[2], today_dps), ('uptime', ref[3], uptime),
                               ('players', ref[4], players)):
            if exp and abs(got / float(exp) - 1) > (0.001 if what in ('health', 'heal', 'uptime', 'players') else 0.015):
                bad.append('arena boss %s: ref %s is %s, it must be %s' % (profile, what, got, exp))
        got_heal = xml_heal(read(os.path.join(CHAOS_MONSTERS, fname)))
        if abs(got_heal / heal - 1) > 0.01:
            bad.append('arena boss %s: its healing defense heals %.0f a second, the model has %d' % (fname, got_heal, heal))
    bad.extend(pocket_problems())
    for name, v in zip(('uber', 'raid'), committed_refdps()):
        # a damage number of today's model: held in the run of today only (see D.dps above)
        if not SU.active() and abs(v / (REFDPS_OLD * factor) - 1) > 0.015:
            bad.append('%s refDps is %.0f, the derivation %.0f' % (name, v, REFDPS_OLD * factor))
    bad.extend(party_problems())
    bad.extend(callsite_problems())
    return bad


def main(argv):
    argv = SU.from_argv(argv)
    if SU.active():
        print(SU.banner())
    if '--derive' in argv:
        return derive()
    if '--pockets' in argv:
        return print_pockets()
    if '--party' in argv:
        return print_party()
    bad = problems()
    if '--check' in argv:
        for b in bad:
            print('FAIL ' + b)
        if not bad:
            print('boss length check: ok (dungeon bosses %d s, rift guardian %d s, Omen guardian %d s, arena bosses %s s, pocket bosses %d / %d s, from the typical damage after the round; the party factor of each size, O703)' % (
                BOSS_SECONDS, GUARDIAN_SECONDS, OMEN_SECONDS, '/'.join(str(a[4]) for a in ARENA_BOSSES), POCKET_SECONDS[0], POCKET_SECONDS[1]))
        return 1 if bad else 0
    return derive()


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
