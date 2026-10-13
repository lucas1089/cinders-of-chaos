#!/usr/bin/env python3
"""Rewrite imported monster XML so the TFS 1.4.2 base loads every entry (idempotent).

usage: python3 -I fix_monster_xml.py [FILE_OR_DIR ...]   (default: data/monster/monsters/chaos, run from server/)

  * a loot list <item id="a;b;c" chance="C" .../> becomes one <item> per id with chance C/N (other attributes kept);
    the base reads only the first number of such an id and drops the entry ("Unknown loot item id", "Cant load loot")
  * monster spells the base does not know are replaced by built-in attacks of the same role (SPELL_FIX below);
    interval, chance, range, min and max are kept
  * flags the base does not know (and no src-patch adds) are removed
  * element attributes get the case the base expects (PhysicalPercent -> physicalPercent)
  * stray text inside <attacks>/<defenses> such as "</defense>>" is removed (the base fails to load a spell there)
  * unknown area effects in AREA_FIX are renamed
Load warnings and leftovers of the donor servers (same behaviour, no console line):
  * <event name> of the donor servers (DONOR_EVENTS, registered nowhere here: one warning per spawn) is removed,
    and so is a <script> block left empty
  * <monster> attributes the base never reads (DEAD_ROOT_ATTRS) and the <strategy> and <levelconfig> lines (no
    reader; the level scaling is global, config.lua monsterBonus*) are removed
  * a non-melee spell without chance gets chance="100" (the base default; it warns on every load)
  * |min| > |max| on a spell is swapped (the base swaps it at load)
  * a damage spell with min above 0 and max below 0 gets a negative min (a lost minus sign: rolls between the two
    healed the target)
  * targetdistance below 1 becomes 1, targetchange and voices chance above 100 become 100, a speedchange below -1000
    becomes -1000 (the base clamps each with a warning)
  * pushable="1" next to canpushcreatures="1" becomes pushable="0" (the base forces it)
  * the article of nameDescription follows the first letter ("an saga" -> "a saga"; words on u are left alone)
Behaviour changes (bugs):
  * summonable and convinceable become 0: a Chaos monster is never a player summon (the summon spell and the convince
    rune read these flags and the monster's manacost, which is 0 or low on the donor imports)
  * a monster with loot and no corpse gets FALLBACK_CORPSE (with corpse 0 the loot has no container and is lost)
Prints one line per changed file. tools/ci/check_content.py rejects anything this script would change.
"""
import os, re, sys

# flags the base reads (monsters.cpp loadMonster); src-patches may add more, see known_flags()
BASE_FLAGS = {'summonable', 'attackable', 'hostile', 'ignorespawnblock', 'illusionable', 'challengeable',
              'convinceable', 'pushable', 'isboss', 'canpushitems', 'canpushcreatures', 'staticattack', 'lightlevel',
              'lightcolor', 'targetdistance', 'runonhealth', 'hidehealth', 'canwalkonenergy', 'canwalkonfire',
              'canwalkonpoison'}
ELEMENTS = ['physicalPercent', 'icePercent', 'poisonPercent', 'earthPercent', 'firePercent', 'energyPercent',
            'holyPercent', 'deathPercent', 'waterPercent', 'arcanePercent', 'drownPercent', 'lifedrainPercent',
            'manadrainPercent']
AREA_FIX = {'purplesd': 'purpleenergy', 'hitarea': 'blackspark'}  # blackspark is the hit-area effect
# effect names the base resolves for areaEffect / shootEffect (tools.cpp magicEffectNames / shootTypeNames, lower case);
# an unknown one silently becomes "no effect". Names of the other world are kept as SHA-256 (like base_monster_names.csv).
MAGIC_EFFECTS = set("""assassin bats bigclouds bigplants blacksmoke blackspark bloodysteps bluebubble bluefirework bluenote
    blueshimmer bubbles cake confettihorizontal confettivertical dice dragonhead energy energyarea explosion explosionarea
    fire firearea fireattack giantice giftwraps greenbubble greennote greenshimmer greensmoke greenspark groundshaker
    hearts holyarea holydamage icearea iceattack icetornado insects mirrorhorizontal mirrorvertical mortarea orcshaman
    orcshamanfire plantattack poff poison purpleenergy purplenote purplesmoke redfirework rednote redshimmer redsmoke
    redspark skullhorizontal skullvertical sleep smallclouds smallplants smoke stepshorizontal stepsvertical stones stun
    teleport thunder tutorialarrow tutorialsquare watercreature watersplash whitenote yellowbubble yellowenergy
    yellowfirework yellownote yellowsmoke yellowspark""".split())
MAGIC_EFFECT_HASHES = {'48915e6df408d9540fdadc3430f99b3852efc60884fa785e07e197c570a9cd0b',
                       'a87791fd15b7f113a15b1db8debaa1215b4b4961389e048e74feb8dea4cb3e04',
                       'b820f77a2539cc87cf8d42d8751785e46d0ba2dbe68d092026d30384f0ac034d'}
SHOOT_EFFECTS = set("""arcane arcanearrow arcanebolt arrow bolt burstarrow cake crystallinearrow death diamondarrow drillbolt
    earth eartharrow enchantedspear energy energyball envenomedarrow etherealspear explosion fire flammingarrow flasharrow
    greenstar holy huntingspear ice infernalbolt largerock leafstar onyxarrow piercingbolt poison poisonarrow powerbolt
    prismaticbolt redstar royalspear royalstar shiverarrow simplearrow smallearth smallholy smallice smallstone sniperarrow
    snowball spear spectralbolt suddendeath throwingknife throwingstar vortexbolt water waterarrow waterbolt whirlwindaxe
    whirlwindclub whirlwindsword""".split())
SHOOT_EFFECT_HASHES = {'99c30f68e1580e9c5adce9afbe6836387c384546397e5401fe50300d477f07c1',
                       'ce41be1020c44e60373f047252784d411df1614ca1853968f553c7fed7970012'}

def known_effect(kind, value):
    """kind 'area' or 'shoot'; value as written in the monster file (the base lower-cases it)"""
    import hashlib
    v = value.strip().lower()
    names, hashes = (MAGIC_EFFECTS, MAGIC_EFFECT_HASHES) if kind == 'area' else (SHOOT_EFFECTS, SHOOT_EFFECT_HASHES)
    return v in names or hashlib.sha256(v.encode('utf-8')).hexdigest() in hashes

# monster spell names the base resolves without a spells.xml entry (monsters.cpp deserializeSpell)
BUILTIN_SPELLS = {'melee', 'physical', 'bleed', 'poison', 'earth', 'fire', 'energy', 'drown', 'ice', 'holy', 'death',
                  'water', 'arcane', 'lifedrain', 'manadrain', 'healing', 'speed', 'outfit', 'invisible', 'drunk',
                  'firefield', 'poisonfield', 'energyfield', 'firecondition', 'energycondition', 'earthcondition',
                  'poisoncondition', 'icecondition', 'freezecondition', 'deathcondition', 'cursecondition',
                  'holycondition', 'dazzlecondition', 'drowncondition', 'bleedcondition', 'physicalcondition',
                  'strength', 'effect'}
# monster-only instants in the base spells.xml (words "###N"); a monster spell may name any of them
BASE_MONSTER_SPELLS = {
    'ghastly dragon curse', 'djinn electrify', 'energy elemental electrify', 'massive energy elemental electrify',
    'massive fire elemental soulfire', 'hellfire fighter soulfire', 'hellspawn soulfire', 'spectre drown',
    'phantasm drown', 'undead dragon curse', 'wyrmblood abomination curse', 'lancer beetle curse',
    'lizard magistrate curse', 'death blob curse', 'choking fear drown', 'blightwalker curse', 'sea serpent drown',
    'young sea serpent drown', 'saltkin constrictor freeze', 'saltkin constrictor electrify', 'cliff strider electrify',
    'war golem electrify', 'souleater drown', 'mutated bat curse', 'ashkarn soulfire', 'lava golem soulfire',
    'magma crawler soulfire', 'war golem skill reducer', 'silencer skill reducer', 'warlock skill reducer',
    'cliff strider skill reducer', 'thundertusk skill reducer', 'diabolic imp skill reducer',
    'dark torturer skill reducer', 'forest fury skill reducer', 'demon outcast skill reducer', 'fury skill reducer',
    'barbarian brutetamer skill reducer', 'drownkin spellsinger skill reducer', 'werewolf skill reducer',
    'ice golem skill reducer', 'feverdream skill reducer', 'shock head skill reducer 1', 'shock head skill reducer 2',
    'enslaved dwarf skill reducer 1', 'enslaved dwarf skill reducer 2', 'djinn cancel invisibility',
    'betrayed wraith skill reducer', 'pirate corsair skill reducer', 'monster soulfire', 'neferash skill reducer',
    'woodling paralyze', 'pixie skill reducer', 'physical explosion', 'sludgebrass fairy skill reducer'}

def known_spells():
    """lower-case monster spell names the installed server knows: built-ins, base monster instants, the stock
    player spells under their Chaos names (spell_names.csv) and our own spells (spells_chaos.xml)."""
    import csv
    names = BUILTIN_SPELLS | BASE_MONSTER_SPELLS
    sp = os.path.join(HERE, '..', 'data', 'spells')
    p = os.path.join(sp, 'spell_names.csv')
    if os.path.exists(p):
        names |= {r['new_name'].lower() for r in csv.DictReader(open(p, newline='', encoding='utf-8'))}
    p = os.path.join(sp, 'chaos', 'spells_chaos.xml')
    if os.path.exists(p):
        names |= {n.lower() for n in re.findall(r'<(?:instant|rune)\b[^>]*\bname="([^"]+)"',
                                                 open(p, encoding='utf-8').read())}
    return names

# unknown spell name (lower case) -> (extra attributes, [(effect key, value)]); same damage numbers, nearest shape
SPELL_FIX = {
    "ul'thazmor iceball": ('name="ice" range="7" target="1" radius="3"',
                             [('shootEffect', 'ice'), ('areaEffect', 'icearea')]),
    'ranged_stun_stone': ('name="speed" target="1" speedchange="-700" duration="3000"',
                          [('shootEffect', 'largerock'), ('areaEffect', 'stun')]),
    'ultra berserk': ('name="physical" radius="3" target="0"', [('areaEffect', 'blackspark')]),
    'advanced thunder shuriken': ('name="energy" range="7" target="1"',
                                  [('shootEffect', 'throwingstar'), ('areaEffect', 'energy')]),
    'arctic_plant': ('name="speed" target="1" speedchange="-400" duration="3000"',
                     [('shootEffect', 'smallice'), ('areaEffect', 'iceattack')]),
    'serpent_attack': ('name="speed" range="7" target="1" speedchange="-850" duration="12000"',
                       [('shootEffect', 'poison'), ('areaEffect', 'redshimmer')]),
}
KEEP_ATTRS = ('interval', 'speed', 'chance', 'range', 'min', 'max')

# built-in spells whose min/max are damage (negative); healing and the conditions are not in it
DAMAGE_SPELLS = {'melee', 'physical', 'bleed', 'poison', 'earth', 'fire', 'energy', 'drown', 'ice', 'holy', 'death',
                 'water', 'arcane', 'lifedrain', 'manadrain', 'firefield', 'poisonfield', 'energyfield'}
# creature events the donor monsters register; no script here or in the base defines them
DONOR_EVENTS = {'auto_loot', 'orb_bonus', 'crusd_chest_bonus', 'RewardChestDeath', 'first_boss_kill_talent',
                'spawn_for_time', 'boss_tp_death', 'boss_summoner', 'boss_draken_legs', 'saga_outfit_boss'}
# <monster> attributes of the donor servers; the base reads name, nameDescription, race, experience, speed, manacost,
# skull and script only
DEAD_ROOT_ATTRS = ('looting', 'skulled', 'evented', 'bosses', 'damagereduction', 'damagepenetration', 'power')
FALLBACK_CORPSE = 6068   # the corpse adapt_monsters.py gives imports whose own corpse does not exist here

HERE = os.path.dirname(os.path.abspath(__file__))

def known_flags():
    flags = set(BASE_FLAGS)
    pdir = os.path.join(HERE, '..', 'src-patches')
    for f in sorted(os.listdir(pdir)) if os.path.isdir(pdir) else []:
        for ln in open(os.path.join(pdir, f), encoding='utf-8', errors='ignore'):
            m = re.match(r'\+.*strcasecmp\(attrName, "(\w+)"\)', ln)
            if m: flags.add(m.group(1).lower())
    return flags

LOOT_LIST = re.compile(r'^([ \t]*)<item\b([^>]*?)\bid="(\d+(?:\s*;\s*\d+)+)"([^>]*?)/>([ \t]*<!--.*?-->)?',
                       re.M)

def split_loot(m):
    indent, pre, ids, post, comment = m.group(1), m.group(2), m.group(3), m.group(4), m.group(5) or ''
    ids = [i.strip() for i in ids.split(';') if i.strip()]
    attrs = pre + post
    cm = re.search(r'\bchance="(\d+)"', attrs)
    total = int(cm.group(1)) if cm else 100000
    each = max(1, round(total / len(ids)))
    attrs = re.sub(r'\s*\bchance="\d+"', '', attrs).strip()
    attrs = re.sub(r'\s+', ' ', attrs)
    out = []
    for k, i in enumerate(ids):
        extra = (' ' + attrs) if attrs else ''
        out.append(f'{indent}<item id="{i}"{extra} chance="{each}"/>' + (comment if k == 0 else ''))
    return '\n'.join(out)

def fix_spell(m):
    indent, tag, attrs = m.group(1), m.group(2), m.group(3)
    nm = re.search(r'\bname="([^"]*)"', attrs)
    fix = SPELL_FIX.get(nm.group(1).lower()) if nm else None
    if not fix:
        return m.group(0)
    kept = [a.group(0) for a in re.finditer(r'\b(\w+)="[^"]*"', attrs) if a.group(1) in KEEP_ATTRS]
    head = f'{indent}<{tag} {fix[0]} ' + ' '.join(kept)
    body = ''.join(f'\n{indent}\t<attribute key="{k}" value="{v}"/>' for k, v in fix[1])
    return f'{head.rstrip()}>{body}\n{indent}</{tag}>'

def _set_attr(tag, key, value):
    """tag text with key="value" (replaced in place, or added before the closing bracket)"""
    rx = re.compile(r'(\s%s\s*=\s*")[^"]*(")' % re.escape(key))
    if rx.search(tag):
        return rx.sub(lambda m: m.group(1) + value + m.group(2), tag, count=1)
    end = re.search(r'\s*/?>$', tag)
    return tag[:end.start()] + ' %s="%s"' % (key, value) + tag[end.start():]

def _num(tag, key):
    m = re.search(r'\s%s\s*=\s*"(-?\d+)"' % re.escape(key), tag)
    return int(m.group(1)) if m else None

def fix_spell_tag(m):
    tag = m.group(0)
    name = re.search(r'\sname\s*=\s*"([^"]*)"', tag)
    if name and name.group(1).lower() != 'melee' and _num(tag, 'chance') is None \
            and not re.search(r'\sscript\s*=', tag):
        tag = re.sub(r'(\s(?:interval|speed)\s*=\s*"[^"]*")', r'\1 chance="100"', tag, count=1) \
            if re.search(r'\s(?:interval|speed)\s*=', tag) else _set_attr(tag, 'chance', '100')
    mn, mx = _num(tag, 'min'), _num(tag, 'max')
    if name and name.group(1).lower() in DAMAGE_SPELLS and mn is not None and mx is not None and mn > 0 > mx:
        tag = _set_attr(tag, 'min', str(-mn)); mn = -mn
    if mn is not None and mx is not None and abs(mn) > abs(mx):
        tag = _set_attr(_set_attr(tag, 'min', str(mx)), 'max', str(mn))
    for k in ('speedchange', 'minspeedchange', 'maxspeedchange'):
        v = _num(tag, k)
        if v is not None and v < -1000:
            tag = _set_attr(tag, k, '-1000')
    return tag

def _article(m):
    first = m.group(3).lower()
    if first == 'u':
        return m.group(0)
    want = 'an' if first in 'aeio' else 'a'
    return m.group(1) + (want if m.group(2).islower() else want.capitalize()) + ' '

def fix_text(t, flags):
    t = LOOT_LIST.sub(split_loot, t)
    t = re.sub(r'^([ \t]*)<(attack|defense)\b([^>]*?)\s*/>', fix_spell, t, flags=re.M)
    def flag_line(m):
        return m.group(0) if m.group(2).lower() in flags else ''
    t = re.sub(r'(\n[ \t]*<flag\s+(\w+)\s*=\s*"[^"]*"\s*/>[ \t]*)', lambda m: flag_line(m), t)
    canon = {e.lower(): e for e in ELEMENTS}
    t = re.sub(r'(<element\s+)(\w+)(\s*=)', lambda m: m.group(1) + canon.get(m.group(2).lower(), m.group(2)) + m.group(3), t)
    t = re.sub(r'(</(?:attack|defense)>)>+', r'\1', t)
    for old, new in AREA_FIX.items():
        t = re.sub(r'(key="areaEffect"\s+value=")%s"' % re.escape(old), r'\g<1>%s"' % new, t, flags=re.I)
    # donor events and the <script> block they leave empty
    t = re.sub(r'\n[ \t]*<event\s+name="(%s)"\s*/>[ \t]*(?=\n)' % '|'.join(map(re.escape, sorted(DONOR_EVENTS))), '', t)
    t = re.sub(r'\n[ \t]*<script>\s*</script>[ \t]*(?=\n)', '', t)
    # attributes and tags the base never reads
    t = re.sub(r'<monster\s[^>]*>', lambda m: re.sub(r'\s+(?:%s)\s*=\s*"[^"]*"' % '|'.join(DEAD_ROOT_ATTRS), '', m.group(0)), t,
               count=1)
    t = re.sub(r'\n[ \t]*<(?:strategy|levelconfig)\b[^>]*/>[ \t]*(?=\n)', '', t)
    # what the base clamps, swaps or defaults with a warning
    t = re.sub(r'<(?:attack|defense)\s[^>]*>', fix_spell_tag, t)
    t = re.sub(r'(<flag\s+targetdistance\s*=\s*")(-?\d+)(")', lambda m: m.group(1) + str(max(1, int(m.group(2)))) + m.group(3), t, flags=re.I)
    for node in ('targetchange', 'voices'):
        t = re.sub(r'<%s\s[^>]*>' % node, lambda m: _set_attr(m.group(0), 'chance', '100')
                   if (_num(m.group(0), 'chance') or 0) > 100 else m.group(0), t)
    if re.search(r'<flag\s+canpushcreatures\s*=\s*"1"', t, re.I):
        t = re.sub(r'(<flag\s+pushable\s*=\s*")1(")', r'\g<1>0\2', t, flags=re.I)
    t = re.sub(r'(\snameDescription\s*=\s*")(an?) (?=([A-Za-z]))', _article, t, count=1)
    # never a player summon
    t = re.sub(r'(<flag\s+(?:summonable|convinceable)\s*=\s*")1(")', r'\g<1>0\2', t, flags=re.I)
    # loot needs a corpse to land in
    loot = re.search(r'<loot>(.*?)</loot>', re.sub(r'<!--.*?-->', '', t, flags=re.S), re.S)
    look = re.search(r'<look\s[^>]*>', t)
    if loot and '<item' in loot.group(1) and look and not _num(look.group(0), 'corpse'):
        t = t.replace(look.group(0), _set_attr(look.group(0), 'corpse', str(FALLBACK_CORPSE)), 1)
    return t

def files(args):
    for a in args:
        if os.path.isdir(a):
            for root, _d, fs in os.walk(a):
                for f in sorted(fs):
                    if f.endswith('.xml'): yield os.path.join(root, f)
        else:
            yield a

def main():
    args = sys.argv[1:] or [os.path.join(HERE, '..', 'data', 'monster', 'monsters', 'chaos')]
    flags = known_flags()
    n = 0
    for f in files(args):
        t = open(f, encoding='utf-8').read()
        new = fix_text(t, flags)
        if new != t:
            open(f, 'w', encoding='utf-8', newline='').write(new)
            print('fixed', f); n += 1
    print(f'{n} file(s) changed')

if __name__ == '__main__':
    main()
