#!/usr/bin/env python3
"""Balance and naming pass over the Chaos monster XML files (idempotent).

usage: python3 -I tune_monsters.py [--check] [--table]      (run from anywhere)

Every change of the monster lint follow-up (server/README.md "Monster lint", owner approval 2026-10-13) is a row of
TUNING below, keyed by the file under data/monster/monsters/chaos. A row sets values; scaling rows scale to a target
(the strongest hit becomes exactly the target, the other values follow by the same factor, rounded to 10), so a second
run changes nothing.

Row keys:
  name, desc        <monster name>, nameDescription
  experience, speed <monster> attributes
  health            <health now max> (both)
  level             (min, max) of <level>
  flags             {flag: value} (existing <flag> lines)
  elements          [(key, value)]: the whole <elements> block (added after </defenses> when missing)
  attack            {n: {attr: value}}: attributes of the n-th <attack> (0-based)
  drop_melee        attributes removed from the melee <attack>
  attacks_xml       the whole <attacks> block (role templates of the pirates)
  summons_xml       the whole <summons> block (added before <voices> / <loot> when missing)
  hit               the strongest damage value of <attacks> (min/max) becomes this; the others scale with it
  heal              the same for the healing <defense> spells
  heal_spell        {attr: value} on every healing <defense> (interval, chance, min, max)
  armor             armor and defense of <defenses>
  coins             platinum countmax: the coin lines become COIN_BLOCK with it (the late-game set's gold, ~899 at 25)
  loot              the whole <loot> block (LOOT_*)

The 32 dormant donor imports (DORMANT) are clamped to levels 650-1300 by their old rank and get the late-game curves
(late_targets): health, experience per health and speed at the level as the 18 spawned late-game monsters have them,
the strongest hit 800 + 0.8 per level above 650 and heals at 10% of the base health. Computed, not measured.
--check changes nothing and exits 1 when a file is not up to date. --table prints the before/after of the scaled rows.
"""
import os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(os.path.dirname(HERE), 'data', 'monster', 'monsters', 'chaos')
sys.path.insert(0, HERE)
sys.dont_write_bytecode = True
from fix_monster_xml import DAMAGE_SPELLS, _set_attr, _num

LATE_ELEMENTS = [('physicalPercent', -15), ('holyPercent', -15), ('firePercent', 20), ('energyPercent', 20),
                 ('icePercent', 20), ('earthPercent', 20), ('deathPercent', 10)]
COIN_IDS = ('2148', '2152', '2160')
WORLD_BOSS_HEAL = {'interval': '2000', 'chance': '8', 'min': '20000', 'max': '40000'}


def coin_block(platinum, indent):
    rows = [('2148', 90, 43750, 'gold coin'), ('2148', 80, 43750, 'gold coin'), ('2148', 75, 43750, 'gold coin'),
            ('2152', platinum, 65000, 'platinum coin')]
    return ''.join('%s<item id="%s" countmax="%d" chance="%d"/><!-- %s -->\n' % (indent, i, c, ch, n) for i, c, ch, n in rows)


# the equipment pool of the tier 1 late-game monsters (Orclops Ravager, Shaper Matriarch)
LOOT_LATE_TIER1 = '''	<loot>
''' + coin_block(25, '\t\t') + '''		<item id="11302" chance="375"/><!-- equipment pool of the tier 1 late-game monsters -->
		<item id="11301" chance="375"/>
		<item id="11304" chance="375"/>
		<item id="11303" chance="375"/>
		<item id="8891" chance="375"/>
		<item id="9931" chance="375"/>
		<item id="11356" chance="375"/>
		<item id="2645" chance="375"/>
		<item id="8889" chance="562"/>
		<item id="8887" chance="562"/>
		<item id="12607" chance="562"/>
		<item id="8880" chance="562"/>
		<item id="2522" chance="562"/>
		<item id="2520" chance="562"/>
		<item id="11117" chance="562"/>
		<item id="5741" chance="562"/>
	</loot>'''

# the four pirates were one file under four names; each gets a role of about the same expected damage per second
# (chance x average / interval; ~2,000-2,500 before the level scaling) before `hit` scales them alike
PIRATE_BRUISER = '''	<attacks>
		<attack name="melee" interval="2000" min="0" max="-7000"/>
		<attack name="physical" interval="2000" chance="30" length="4" spread="2" min="-3500" max="-6500">
			<attribute key="areaEffect" value="blackspark"/>
		</attack>
		<attack name="bleedcondition" interval="2000" chance="15" range="1" target="1" min="-2000" max="-3000" tick="2000">
			<attribute key="areaEffect" value="redspark"/>
		</attack>
	</attacks>'''
PIRATE_RANGED = '''	<attacks>
		<attack name="physical" interval="2000" chance="100" range="7" min="-2500" max="-5000">
			<attribute key="shootEffect" value="spear"/>
		</attack>
		<attack name="physical" interval="2000" chance="20" range="7" radius="1" target="1" min="-3500" max="-7000">
			<attribute key="shootEffect" value="explosion"/>
			<attribute key="areaEffect" value="explosionarea"/>
		</attack>
	</attacks>'''
PIRATE_CASTER = '''	<attacks>
		<attack name="melee" interval="2000" min="0" max="-3000"/>
		<attack name="energy" interval="2000" chance="30" length="6" spread="0" min="-3000" max="-7000">
			<attribute key="areaEffect" value="energyarea"/>
		</attack>
		<attack name="ice" interval="2000" chance="35" range="7" radius="3" target="1" min="-3000" max="-6000">
			<attribute key="shootEffect" value="smallice"/>
			<attribute key="areaEffect" value="icearea"/>
		</attack>
		<attack name="speed" interval="2000" chance="12" range="7" target="1" speedchange="-600" duration="4000">
			<attribute key="shootEffect" value="snowball"/>
			<attribute key="areaEffect" value="iceattack"/>
		</attack>
	</attacks>'''
PIRATE_SUMMONER = '''	<attacks>
		<attack name="melee" interval="2000" min="0" max="-5000"/>
		<attack name="physical" interval="2000" chance="35" range="4" min="-3000" max="-6000">
			<attribute key="shootEffect" value="throwingknife"/>
		</attack>
	</attacks>'''
PIRATE_SUMMONS = '''	<summons maxSummons="3">
		<summon name="Pirate Skeleton" interval="2000" chance="15"/>
	</summons>'''

# dormant donor imports (they spawn nowhere): old rank -> level 650-1300
DORMANT = ['cunning_hyaena', 'mercenary', 'mercenary_ranger', 'elite_spider', 'cursed_ape', 'webbound_crawler',
           'black_stag', 'captain_bloodbeard', 'dark_sorcerer', 'ironhook_corsair', 'scourgejaw', 'stormy_seadevil',
           'nexweaver', 'acid_hydra', 'mutated_visco', 'elite_tidecrest_serpent', 'elite_twisted_shaper', 'ice_lich',
           'scaleborn', 'spirit_of_purity', 'twisted_shaper', 'celestial_wyrm', 'vorkhaz', 'jungle_warrior',
           'black_vixen', 'golden_dragon', 'spiky_carnivor', 'vyrm', 'winterstride', 'silicron', 'thal', 'facetis']


def late_targets(L):
    """the 18 spawned late-game monsters at level L (fit over levels 670-980, extended to 1300)"""
    hp_at = 75000 + 345 * (L - 670)                  # health at the level
    ratio = 1.15 + 0.0039 * (L - 670)                # experience per health point at the level
    health = round(hp_at / (1 + 0.0074 * L) / 100) * 100
    exp = round(ratio * health * (1 + 0.0074 * L) / (0.03 * L) / 50) * 50
    speed = round((380 + (L - 650) * 100 / 650) / (1 + 0.0085 * L))
    hit = round((800 + 0.8 * (L - 650)) / 10) * 10
    heal = round(health * 0.10 / 10) * 10
    return {'health': health, 'experience': exp, 'speed': speed, 'hit': hit, 'heal': heal}


TUNING = {
    # 1. names the base Lua monsters of the same name no longer overwrite
    'wildwood/gloomtusk_boar.xml': {'name': 'Gloomtusk Boar', 'desc': 'a gloomtusk boar'},
    'wildwood/blightwing_hornet.xml': {'name': 'Blightwing Hornet', 'desc': 'a blightwing hornet'},
    # 2. donor bosses: experience in the world boss band (16-22M for 15-24M health), by health and difficulty
    #    and since the solo kill times pass (README "Solo kill times") their health, heals, armor and hits too: health
    #    one per experience point like the world bosses, the world bosses' heal (20-40k at chance 8 every 2 s, ~1.2k/s),
    #    armor 80-150 and the strongest hit 8-10k. They stay dormant (no spawn).
    'ormathulak.xml': {'experience': 22000000, 'health': 22000000, 'armor': 150, 'heal_spell': WORLD_BOSS_HEAL, 'hit': 10000},
    'talath.xml': {'experience': 21000000, 'health': 21000000, 'armor': 140, 'heal_spell': WORLD_BOSS_HEAL, 'hit': 10000},
    # (Gloomfire's 2,005,500 earth hit became 36-42k on 2026-10-13; `hit` now scales it with the rest)
    'gloomfire.xml': {'experience': 20000000, 'health': 20000000, 'armor': 90, 'heal_spell': WORLD_BOSS_HEAL, 'hit': 9000},
    'saga.xml': {'experience': 18000000, 'health': 18000000, 'armor': 80, 'heal_spell': WORLD_BOSS_HEAL, 'hit': 9000},
    # a solo boss: ~1M health (7.7 min at the level 1000 median 2,600 per second, less its 450 heal per second)
    'legendary_warrior.xml': {'experience': 1000000, 'health': 1000000, 'hit': 2500},
    'vorathrax.xml': {'attack': {3: {'min': '-26000', 'max': '-32000'}}},
    'world_bosses/vharok_the_blood_colossus.xml': {'drop_melee': ['bleed']},
    # 3. the late-game gold for its level (~1.25 gold per level: ~250)
    'orcaruz.xml': {'coins': 5},
    # 4. the late-game set
    # (Lady bug has no earthPercent on purpose: it is immune to earth, which beats the +20)
    'azure_dragon.xml': {'elements': LATE_ELEMENTS, 'coins': 25},
    'blazebringer.xml': {'coins': 25},
    'frost_maiden.xml': {'coins': 25},
    'tundra_troll.xml': {'coins': 25},
    'garack.xml': {'loot': LOOT_LATE_TIER1},
    # 5. experience per health like the levels around them (1.0 at 225, 1.05 at 350); Fenmaw's speed at level 250
    'fenmaw.xml': {'experience': 4750, 'speed': 190},
    'plagueroot.xml': {'experience': 9700},
    # 6. strongest hit 15% of the health, like the other wildwood bosses
    'wildwood/mushroom_king.xml': {'hit': 900},
    # 7. pirate roles (levels and numbers from DORMANT below)
    'scourgejaw.xml': {'attacks_xml': PIRATE_BRUISER},
    'ironhook_corsair.xml': {'attacks_xml': PIRATE_RANGED, 'flags': {'targetdistance': '4'}},
    'stormy_seadevil.xml': {'attacks_xml': PIRATE_CASTER, 'flags': {'targetdistance': '3'}},
    'captain_bloodbeard.xml': {'attacks_xml': PIRATE_SUMMONER, 'summons_xml': PIRATE_SUMMONS},
}
for _i, _f in enumerate(DORMANT):
    _L = round((670 + _i * (1280 - 670) / (len(DORMANT) - 1)) / 10) * 10
    _row = TUNING.setdefault(_f + '.xml', {})
    _row.update(late_targets(_L))
    _row['level'] = (_L - 20, _L + 20)


# ------------------------------------------------------------------------------------------------ text operations
def _root(t, key, value):
    m = re.search(r'<monster\s[^>]*>', t)
    return t[:m.start()] + _set_attr(m.group(0), key, str(value)) + t[m.end():]


def _tag(t, rx, attrs):
    m = re.search(rx, t)
    if not m:
        raise SystemExit('no %s' % rx)
    tag = m.group(0)
    for k, v in attrs.items():
        tag = _set_attr(tag, k, str(v))
    return t[:m.start()] + tag + t[m.end():]


def _block(t, name):
    m = re.search(r'([ \t]*)<%s\b[^>]*>.*?</%s>' % (name, name), t, re.S)
    return m


def _replace_block(t, name, text, before=()):
    m = _block(t, name)
    if m:
        return t[:m.start()] + text + t[m.end():]
    for b in before:
        n = re.search(r'\n([ \t]*)<%s\b' % b, t)
        if n:
            return t[:n.start() + 1] + text + '\n' + t[n.start() + 1:]
    raise SystemExit('no place for <%s>' % name)


def _scale(t, block, pick, target):
    m = _block(t, block)
    if not m:
        return t
    body = m.group(0)
    tags = [x for x in re.finditer(r'<(?:attack|defense)\s[^>]*>', body) if pick(x.group(0))]
    vals = [abs(_num(x.group(0), k)) for x in tags for k in ('min', 'max') if _num(x.group(0), k)]
    if not vals:
        return t
    top = max(vals)
    out, last = [], 0
    for x in tags:
        tag = x.group(0)
        for k in ('min', 'max'):
            v = _num(tag, k)
            if not v:
                continue
            nv = target if abs(v) == top else round(abs(v) * target / top / 10) * 10
            tag = _set_attr(tag, k, str(nv if v > 0 else -nv))
        out.append(body[last:x.start()] + tag)
        last = x.end()
    out.append(body[last:])
    return t[:m.start()] + ''.join(out) + t[m.end():]


def _is_damage(tag):
    n = re.search(r'\sname="([^"]+)"', tag)
    n = n.group(1).lower() if n else ''
    return (n in DAMAGE_SPELLS or n.endswith('condition')) and not re.search(r'\s(?:skill|attack)="', tag)


def _is_heal(tag):
    return bool(re.search(r'\sname="healing"', tag, re.I))


def _heal_attrs(tag, attrs):
    if not _is_heal(tag):
        return tag
    for k, v in attrs.items():
        if k == 'interval' and re.search(r'\sspeed="', tag) and not re.search(r'\sinterval="', tag):
            k = 'speed'
        tag = _set_attr(tag, k, v)
    return tag


def apply(t, row):
    for k in ('name', 'experience', 'speed'):
        if k in row:
            t = _root(t, k, row[k])
    if 'desc' in row:
        t = _root(t, 'nameDescription', row['desc'])
    if 'health' in row:
        t = _tag(t, r'<health\s[^>]*>', {'now': row['health'], 'max': row['health']})
    if 'level' in row:
        t = _tag(t, r'<level\s[^>]*>', {'min': row['level'][0], 'max': row['level'][1]})
    for flag, v in row.get('flags', {}).items():
        t = re.sub(r'(<flag\s+%s\s*=\s*")[^"]*(")' % flag, r'\g<1>%s\2' % v, t, flags=re.I)
    if 'elements' in row:
        body = '\t<elements>\n' + ''.join('\t\t<element %s="%d"/>\n' % kv for kv in row['elements']) + '\t</elements>'
        t = _replace_block(t, 'elements', body, before=('immunities', 'summons', 'voices', 'loot'))
    if 'attacks_xml' in row:
        t = _replace_block(t, 'attacks', row['attacks_xml'])
    if 'summons_xml' in row:
        t = _replace_block(t, 'summons', row['summons_xml'], before=('voices', 'loot'))
    for n, attrs in row.get('attack', {}).items():
        m = _block(t, 'attacks')
        tags = list(re.finditer(r'<attack\s[^>]*>', m.group(0)))
        x = tags[n]
        tag = x.group(0)
        for k, v in attrs.items():
            tag = _set_attr(tag, k, v)
        s = m.start() + x.start()
        t = t[:s] + tag + t[s + len(x.group(0)):]
    for k in row.get('drop_melee', ()):
        t = re.sub(r'(<attack\s+name="melee"[^>]*?)\s+%s="[^"]*"' % k, r'\1', t)
    if 'hit' in row:
        t = _scale(t, 'attacks', _is_damage, row['hit'])
    if 'armor' in row:
        t = _tag(t, r'<defenses\s[^>]*>', {'armor': row['armor'], 'defense': row['armor']})
    if 'heal_spell' in row:
        t = re.sub(r'<defense\s[^>]*>', lambda m: _heal_attrs(m.group(0), row['heal_spell']), t)
    if 'heal' in row:
        t = _scale(t, 'defenses', _is_heal, row['heal'])
    if 'coins' in row:
        m = _block(t, 'loot')
        body = m.group(0)
        indent = re.search(r'\n([ \t]*)<item', body).group(1)
        body = re.sub(r'\n[ \t]*<item\s+id="(?:%s)"[^>]*/>[ \t]*(?:<!--.*?-->)?[ \t]*(?=\n)' % '|'.join(COIN_IDS), '', body)
        head = re.match(r'[ \t]*<loot>[ \t]*\n', body)
        body = body[:head.end()] + coin_block(row['coins'], indent) + body[head.end():]
        t = t[:m.start()] + body + t[m.end():]
    if 'loot' in row:
        t = _replace_block(t, 'loot', row['loot'])
    return t


def stats(t):
    def a(k):
        m = re.search(r'<monster\s[^>]*\s%s="([^"]*)"' % k, t)
        return m.group(1) if m else ''
    lv = re.search(r'<level\s+min="(\d+)"\s+max="(\d+)"', t)
    hp = re.search(r'<health\s[^>]*max="(\d+)"', t)
    dm = _block(t, 'attacks')
    hits = [abs(_num(x.group(0), k) or 0) for x in re.finditer(r'<attack\s[^>]*>', dm.group(0) if dm else '')
            if _is_damage(x.group(0)) for k in ('min', 'max')]
    return {'level': '%s-%s' % lv.groups() if lv else '', 'health': hp.group(1) if hp else '',
            'exp': a('experience'), 'speed': a('speed'), 'hit': max(hits) if hits else 0}


def main(argv):
    check, table = '--check' in argv, '--table' in argv
    bad = 0
    for rel, row in sorted(TUNING.items()):
        p = os.path.join(ROOT, rel)
        t = open(p, encoding='utf-8').read()
        new = apply(t, row)
        if apply(new, row) != new:
            raise SystemExit('%s: not idempotent' % rel)
        if table:
            b, a = stats(t), stats(new)
            print('| %s | %s | %s |' % (rel, ' / '.join(str(b[k]) for k in ('level', 'health', 'exp', 'speed', 'hit')),
                                       ' / '.join(str(a[k]) for k in ('level', 'health', 'exp', 'speed', 'hit'))))
        if new != t:
            bad += 1
            if check:
                print('not up to date:', rel)
            elif not table:
                open(p, 'w', encoding='utf-8', newline='').write(new)
                print('tuned', rel)
    if check:
        print('monster tuning:', 'up to date' if not bad else '%d file(s) to tune' % bad)
        return 1 if bad else 0
    if not table:
        print('%d file(s) changed' % bad)
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
