#!/usr/bin/env python3
"""Server content consistency (no game data needed):
 - XML files parse (fragments such as spells_chaos.xml are checked wrapped in a root element)
 - spells: unique spellid, words and name; every script file exists under data/spells/chaos
 - removed spells (spell_names.csv "removed", the conjure spells of data/lib/chaos_rune_supply.lua: the runes and
   R.otherConjures): one csv row per removed script; no class kit names one (spells_chaos.xml, add_vocations.py LINE_STOCK_SPELLS, the tutorial's class
   spells in newplayer_config.lua)
 - monster spells: a Chaos monster's stock spell that the retire tools retire is kept for monsters (monster_spells.py)
 - throwing weapons (server/data/lib/chaos_throwables.lua): no Chaos monster loot (XML or Lua), new-player kit or
   hunt supply price names a stackable throwing weapon, and the shuriken constants list no star
 - items: unique ids in chaos_items.xml
 - monsters (monsters/chaos and its subfolders, e.g. world_bosses/): unique names; a lookType above MAX_OUTFIT must be
   listed in needs_sprites.txt; no loot id lists ("a;b"), monster spells, flags and element keys must be known to the
   base (server/tools/fix_monster_xml.py holds the lists and fixes most problems); experience > 0 needs a loot item
   unless the name is in LOOTLESS_OK
 - Lua monsters (monster/lua/chaos): every loot entry has a numeric `id =` (the base ignores `name =`), experience > 0
   needs a loot table unless the name is in LOOTLESS_OK
Monster rules (check_monster_rules; codes in brackets, allowlist ALLOW with a reason per entry; an entry that no
longer matches fails too):
 - names: no Chaos monster takes the name of a base type (data/monster/base_monster_hashes.txt, after the renames of
   base_monster_names.csv) [name.base-type]; XML and Lua names unique [name.duplicate]; "a"/"an" fits [name.article]
 - <monster> attributes and tags the base reads; health now/max present, now <= max, max > 0; race and skull known
 - look: a type (or typeex); lookType inside the client pair and not one of its blank outfits (PAIR_*); loot needs a
   corpse [corpse.none]; loot and corpse ids above BASE_MAX_ITEM in our item tables [item.unknown]
 - targetchange and voices: interval and chance present, chance <= 100; voices not empty
 - flags: staticattack <= 100, targetdistance >= 1, runonhealth below the health at the top level, no pushable with
   canpushcreatures, no summonable or convinceable [flag.tameable] (a Chaos monster is never a player summon)
 - elements and immunities: known keys, one attribute per node, one value per damage type (earth/poison), no element
   on an immune type, element percent <= 100
 - spells: name or script, chance present (non-melee) and <= 100, interval >= 1, range <= 20, |min| <= |max|, damage
   negative and healing positive, a speed spell with a change >= -1000, melee skill with attack, no value on a melee
   bleed (the base never reads it), one geometry key, known effect keys and names (fix_monster_xml.MAGIC_EFFECTS),
   a single hit of at most MAX_HIT [spell.big-hit]
 - summons: maxSummons (exact case) 1-100 with entries, chance <= 100, every name a monster type; outfit monster=
 - scripts: every <event name> a CreatureEvent of server/data/scripts (or BASE_EVENTS), script= files present
 - loot: chance 1-100000, countmax >= 1; speed 0-MAX_SPEED at the top level
 - Lua monsters: name, lookType, corpse and loot ids by the same rules
 - the rows of server/tools/tune_monsters.py are applied (names, experience, levels, loot of the lint follow-up)
Options (not used by CI): --base DATA_DIR also checks every loot and corpse id against that items.xml and that a
corpse is a container; --pair Tibia.dat recounts the outfits and blank outfits of a pair and compares PAIR_*.
Usage: python3 tools/ci/check_content.py [--base DATA_DIR] [--pair Tibia.dat]"""
import glob, os, re, subprocess, sys
import xml.dom.minidom as minidom

# the outfit count of the newest client pair: the pairs up to things_custom10b end at 2081; the monster looks
# (client/tools/sprites/monster_looks/picks.csv, imported at fixed ids with import_outfits.py --first-outfit) end the
# list since things_custom11 (things_custom12 only adds effects). Read from picks.csv so new looks need no edit here.
BASE_OUTFIT = 2081
def _max_outfit():
    import csv
    p = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'client', 'tools', 'sprites',
                     'monster_looks', 'picks.csv')
    looks = [int(r['look']) for r in csv.DictReader(open(p, newline=''))] if os.path.exists(p) else []
    return max([BASE_OUTFIT] + looks)
MAX_OUTFIT = _max_outfit()  # 2311 with things_custom30 (the strip looks 2312-2384 are no monster looks; see server/data/monster/CUSTOM_MONSTERS.md)
bad = 0

def fail(msg):
    global bad
    print(msg); bad += 1

def parse(path):
    raw = open(path, encoding='utf-8').read()
    try:
        return minidom.parseString(raw.encode('utf-8'))
    except Exception:
        stripped = re.sub(r'^\s*<\?xml[^>]*\?>', '', raw)
        try:
            return minidom.parseString(('<root>' + stripped + '</root>').encode('utf-8'))
        except Exception as e:
            fail(f'{path}: not well-formed ({e})')
            return None

for f in subprocess.check_output(['git', 'ls-files', '-z', '*.xml'], text=True).split('\0'):
    if not f:
        continue
    parse(f)

# spells
sp = 'server/data/spells/chaos/spells_chaos.xml'
if os.path.exists(sp):
    doc = parse(sp)
    seen = {'spellid': {}, 'words': {}, 'name': {}}
    for el in (doc.getElementsByTagName('instant') if doc else []):
        for k in seen:
            v = el.getAttribute(k)
            if v in seen[k]:
                fail(f'{sp}: duplicate {k} {v!r}')
            seen[k][v] = 1
        script = el.getAttribute('script')
        if not os.path.exists(os.path.join('server/data/spells', script)):
            fail(f'{sp}: script {script} not found')

# rune supply (server/README.md "Rune supply"): the rune conjure spells are gone; no class kit may name one
def check_removed_spells():
    import csv
    names_csv, words_csv = 'server/data/spells/spell_names.csv', 'server/data/spells/spell_words.csv'
    cfg_path = 'server/data/lib/chaos_rune_supply.lua'
    if not (os.path.exists(names_csv) and os.path.exists(cfg_path)):
        return
    parts = {r['old']: r['new'] for r in csv.DictReader(open(words_csv, encoding='utf-8'))}
    rows = [r for r in csv.DictReader(open(names_csv, encoding='utf-8')) if r.get('removed')]
    cfg_text = open(cfg_path, encoding='utf-8').read()
    # script paths under data/spells/scripts: the runes' conjuring/<name>, and R.otherConjures as written
    paths = {'conjuring/' + s for s in re.findall(r'script = "([\w.]+\.lua)"', cfg_text)}
    paths |= set(re.findall(r'\{script = "([\w./]+\.lua)", name = ', cfg_text))
    if len(rows) != len(paths):
        fail(f'{names_csv}: {len(rows)} rows marked removed, {cfg_path} lists {len(paths)} removed conjure scripts')
    words, names = set(), set()
    for r in rows:
        words.add(r['words'])
        words.add(' '.join(parts.get(t, t) for t in r['words'].split()))
        names |= {r['old_name'].lower(), r['new_name'].lower()}
    # the Chaos spells (spells_chaos.xml): no conjure script, no words of a removed spell
    for m in re.finditer(r'<instant\b([^>]*)>', open(sp, encoding='utf-8').read() if os.path.exists(sp) else ''):
        a = dict(re.findall(r'(\w+)="([^"]*)"', m.group(1)))
        if a.get('script', '') in paths or a.get('script', '').startswith('conjuring/'):
            fail(f'{sp}: {a.get("name")} uses the removed conjure script {a.get("script")}')
        if a.get('words') in words:
            fail(f'{sp}: {a.get("name")} has the words of a removed conjure spell ({a.get("words")})')
    # the stock spells each class line gets (add_vocations.py LINE_STOCK_SPELLS)
    import add_vocations
    for script, stock_words, _lines in add_vocations.LINE_STOCK_SPELLS:
        if script in paths or script.startswith('conjuring/') or stock_words in words:
            fail(f'server/tools/add_vocations.py: LINE_STOCK_SPELLS names the removed conjure spell {script}')
    # the new-player kits and the tutorial's class spells (newplayer_config.lua)
    npc_cfg = 'server/data/scripts/chaos/newplayer_config.lua'
    if os.path.exists(npc_cfg):
        t = open(npc_cfg, encoding='utf-8').read()
        for n, w in re.findall(r'\{name = "([^"]+)", words = "([^"]+)"', t):
            if w in words or n.lower() in names:
                fail(f'{npc_cfg}: the class spell {n!r} ({w}) is a removed conjure spell')

# stackable throwing weapons are out of the game (server/README.md "Throwing weapons")
def check_throwables():
    lib = 'server/data/lib/chaos_throwables.lua'
    if not os.path.exists(lib):
        return
    text = re.sub(r'--[^\n]*', '', open(lib, encoding='utf-8').read())
    m = re.search(r'T\.items\s*=\s*\{(.*?)\n\}', text, re.S)
    ids = {int(i) for i in re.findall(r'\[(\d+)\]\s*=\s*"', m.group(1))} if m else set()
    if not ids:
        fail(f'{lib}: no throwables listed')
        return
    for f in glob.glob('server/data/monster/monsters/chaos/**/*.xml', recursive=True):
        for i in re.findall(r'<item\b[^>]*?\bid="(\d+)"', open(f, encoding='utf-8').read()):
            if int(i) in ids:
                fail(f'{f}: loot names the throwing weapon {i} (data/lib/chaos_throwables.lua)')
    for f in glob.glob('server/data/monster/lua/chaos/**/*.lua', recursive=True):
        for i in re.findall(r'\bid\s*=\s*(\d+)', open(f, encoding='utf-8').read()):
            if int(i) in ids:
                fail(f'{f}: loot names the throwing weapon {i}')
    kit = 'server/data/scripts/chaos/newplayer_config.lua'
    if os.path.exists(kit):
        for i in re.findall(r'\{(?:slot = "\w+", )?id = (\d+)', re.sub(r'--[^\n]*', '', open(kit, encoding='utf-8').read())):
            if int(i) in ids:
                fail(f'{kit}: a kit gives the throwing weapon {i}')
    hs = 'server/data/scripts/chaos/hunt_supplies.lua'
    if os.path.exists(hs):
        for i in re.findall(r'\[(\d+)\]\s*=', open(hs, encoding='utf-8').read()):
            if int(i) in ids:
                fail(f'{hs}: a supply price for the throwing weapon {i}')
    if os.path.exists('server/data/scripts/chaos/chaos_constants.lua'):
        c = open('server/data/scripts/chaos/chaos_constants.lua', encoding='utf-8').read()
        if re.search(r'shuriken\s*=\s*\{[^}]*items\s*=', c):
            fail('server/data/scripts/chaos/chaos_constants.lua: shuriken lists items again (no star is needed)')
check_throwables()

# items
ip = 'server/data/items/chaos_items.xml'
if os.path.exists(ip):
    doc = parse(ip)
    ids = {}
    for el in (doc.getElementsByTagName('item') if doc else []):
        i = el.getAttribute('id')
        if i in ids:
            fail(f'{ip}: duplicate item id {i}')
        ids[i] = 1

# monsters
needs = set()
np_ = 'server/data/monster/needs_sprites.txt'
if os.path.exists(np_):
    needs = {l.split('\t')[0].lower() for l in open(np_, encoding='utf-8') if l.strip()}
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'server', 'tools'))
sys.dont_write_bytecode = True
import fix_monster_xml as fmx
import tune_monsters as tune
KNOWN_SPELLS, KNOWN_FLAGS, KNOWN_ELEMENTS = fmx.known_spells(), fmx.known_flags(), set(fmx.ELEMENTS)
check_removed_spells()

# monster spells (server/README.md "Monster spells"): a Chaos monster that attacks with a stock spell the retire tools
# take out (patch_spell_cap.py CAP, retire_cure_spells.py) must get the monster-only form from them, not the comment,
# or the engine reports "Unknown spell name" and the monster loses the attack
def check_monster_spells_kept():
    import monster_spells as ms, patch_spell_cap as cap, retire_cure_spells as cure
    refs = ms.references(os.devnull, extra_dirs=[d for d in ms.REPO_MONSTERS if os.path.isdir(d)])
    needed = ms.needed_names(os.devnull)
    retired = {name.lower(): script for script, (_, name, keep) in cap.CAP.items() if not keep}
    retired.update({name.lower(): script for script, (_, name) in list(cure.CURES.items()) + list(cure.OTHERS.items())})
    for name, files in sorted(refs.items()):
        script = retired.get(name)
        if not script:
            continue
        tag = '\t<instant name="%s" words="x" script="%s">\n\t\t<vocation name="Mystic" />\n\t</instant>\n' % (name, script)
        out = cure.patch(cap.patch('<spells>\n' + tag + '</spells>\n', needed)[0], needed)[0]
        if 'words="###chaos ' not in out or '<vocation' in out:
            fail(f'{files[0]}: monster spell {name!r} is retired and not kept for monsters (server/tools/monster_spells.py)')
check_monster_spells_kept()

def check_monster_body(f, t):
    """what the base server cannot load: loot id lists, unknown spells/flags/element keys, stray text in
    <attacks>/<defenses>. server/tools/fix_monster_xml.py fixes most of these."""
    doc = parse(f)
    if not doc:
        return
    for it in doc.getElementsByTagName('item'):
        if it.parentNode.nodeName in ('loot', 'inside', 'item') and not it.getAttribute('id').isdigit() \
                and not it.getAttribute('name'):
            fail(f'{f}: loot item id {it.getAttribute("id")!r} is not one number (split the list)')
    for block in doc.getElementsByTagName('attacks') + doc.getElementsByTagName('defenses'):
        for c in block.childNodes:
            if c.nodeType == c.TEXT_NODE and c.data.strip():
                fail(f'{f}: stray text {c.data.strip()!r} in <{block.nodeName}>')
            if c.nodeType == c.ELEMENT_NODE and not c.getAttribute('script') \
                    and c.getAttribute('name').lower() not in KNOWN_SPELLS:
                fail(f'{f}: unknown monster spell {c.getAttribute("name")!r}')
    for fl in doc.getElementsByTagName('flag'):
        for k in fl.attributes.keys():
            if k.lower() not in KNOWN_FLAGS:
                fail(f'{f}: unknown monster flag {k!r}')
    for el in doc.getElementsByTagName('element'):
        for k in el.attributes.keys():
            if k not in KNOWN_ELEMENTS:
                fail(f'{f}: unknown element key {k!r}')
    if fmx.fix_text(t, KNOWN_FLAGS) != t:
        fail(f'{f}: run server/tools/fix_monster_xml.py on it')
    # a level-scaled monster (engine x(1 + 0.0015 L) damage on top) with one attack far above its others: an import
    # slip (Elite Twisted Shaper's arc bolt hit 28000 next to a 1060 melee and one-shot level 1000 characters, beta
    # 2026-10-21). Its peers of levels 850-1150 top out about 1000-1400.
    if doc.getElementsByTagName('level'):
        tops = sorted(abs(int(a.getAttribute('max'))) for a in doc.getElementsByTagName('attack')
                      if a.parentNode.nodeName == 'attacks' and re.fullmatch(r'-?\d+', a.getAttribute('max') or ''))
        if len(tops) > 1 and tops[-1] > 3 * max(tops[-2], 1) and tops[-1] > 2000:
            fail(f'{f}: one attack hits {tops[-1]}, over 3x its next ({tops[-2]}): a level-scaled monster one-shots')
    rel = os.path.relpath(f, 'server/data/monster/monsters/chaos').replace(os.sep, '/')
    if rel in tune.TUNING and tune.apply(t, tune.TUNING[rel]) != t:
        fail(f'{f}: run server/tools/tune_monsters.py on it')

# no fire immunity (owner decision C7, server/tools/monster_fire_resist.py): Pyre Oath burns its owner every second
for f, fix in tune.fire_resist_files():
    if fix(open(f, encoding='utf-8', errors='ignore').read())[1]:
        fail(f'{f}: fire immunity; run server/tools/tune_monsters.py (a fire resistance of {tune.fire.FIRE_RESIST_PERCENT}% instead)')

# experience > 0 but no loot on purpose: adds and bosses whose system pays the rewards (uber.lua, guildboss.lua,
# raid.lua). Experience 0 (summons, pets, goblins, wardens) needs no entry. Every other monster needs a loot item.
LOOTLESS_OK = {'bloodmoon thrall', 'cinderspawn', 'hollow wraith', 'storm shard',      # uber.lua adds
               'banner wraith', 'gorvath the banner-eater',                            # guildboss.lua
               'cinder acolyte', 'hex effigy'}                                         # raid.lua adds

names = {}
for f in sorted(glob.glob('server/data/monster/monsters/chaos/**/*.xml', recursive=True)):
    t = open(f, encoding='utf-8', errors='ignore').read()
    m = re.search(r'<monster\s+name="([^"]+)"', t)
    if not m:
        fail(f'{f}: no <monster name>'); continue
    n = m.group(1).lower()
    if n in names:
        fail(f'{f}: duplicate monster name {m.group(1)!r} (also {names[n]})')
    names[n] = f
    look = re.search(r'<look\s+type="(\d+)"', t)
    if look and int(look.group(1)) > MAX_OUTFIT and n not in needs:
        fail(f'{f}: lookType {look.group(1)} above {MAX_OUTFIT} and not listed in needs_sprites.txt')
    check_monster_body(f, t)
    xp = re.search(r'<monster\s[^>]*\bexperience\s*=\s*"(\d+)"', t)
    loot = re.search(r'<loot>(.*?)</loot>', re.sub(r'<!--.*?-->', '', t, flags=re.S), re.S)
    if xp and int(xp.group(1)) > 0 and n not in LOOTLESS_OK and not (loot and '<item' in loot.group(1)):
        fail(f'{f}: experience {xp.group(1)} but no loot item (add a loot table or list it in LOOTLESS_OK)')
# Lua monsters (Game.createMonsterType): the base's registerMonsterType.loot only calls Loot():setId(loot.id), so an entry
# by name (or with no id) loads as nothing. Every entry, children too, needs an `id` that is one item id (1..65535).
def _lua_code(t):
    """the text with comments and string contents blanked (same length), so braces count right"""
    out, i, n = [], 0, len(t)
    while i < n:
        if t.startswith('--', i):
            m = re.match(r'--\[(=*)\[', t[i:i + 64])
            if m:
                e = t.find(']' + m.group(1) + ']', i + m.end())
                j = n if e < 0 else e + len(m.group(1)) + 2
            else:
                e = t.find('\n', i)
                j = n if e < 0 else e
            out.append(' ' * (j - i)); i = j
        elif t[i] in '"\'':
            q, j = t[i], i + 1
            while j < n and t[j] != q and t[j] != '\n':
                j += 2 if t[j] == '\\' else 1
            out.append(q + ' ' * (min(j, n) - i - 1) + (q if j < n else '')); i = j + 1
        else:
            out.append(t[i]); i += 1
    return ''.join(out)[:n]

def _closing(code, at):
    depth = 0
    for k in range(at, len(code)):
        depth += {'{': 1, '}': -1}.get(code[k], 0)
        if depth == 0:
            return k
    return -1

def check_lua_loot(f, t):
    code = _lua_code(t)
    m = re.search(r'\bmonster\.loot\s*=\s*\{', code)
    xp = re.search(r'\bmonster\.experience\s*=\s*(\d+)', code)
    name = re.search(r'createMonsterType\(\s*"([^"]+)"', t)
    if not m:
        if xp and int(xp.group(1)) > 0 and not (name and name.group(1).lower() in LOOTLESS_OK):
            fail(f'{f}: experience {xp.group(1)} but no monster.loot (add a loot table or list it in LOOTLESS_OK)')
        return
    end = _closing(code, m.end() - 1)
    if end < 0:
        fail(f'{f}: monster.loot is not closed'); return
    entries, k = 0, m.end()
    stack = [(m.end(), end)]
    while stack:
        lo, hi = stack.pop()
        k = lo
        while k < hi:
            if code[k] == '{':
                close = _closing(code, k)
                body = code[k + 1:close]
                # the entry's own fields: the body without its nested tables (child = {...})
                own = body
                for _ in range(10):
                    own2 = re.sub(r'\{[^{}]*\}', '', own)
                    if own2 == own:
                        break
                    own = own2
                entries += 1
                line = t.count('\n', 0, k) + 1
                iid = re.search(r'\bid\s*=\s*(\d+)\s*(?:,|$)', own.strip() + ',')
                if re.search(r'\bname\s*=', own):
                    fail(f'{f}:{line}: loot entry by name; the base loads only `id =` (look the id up in items.xml)')
                elif not iid or not 0 < int(iid.group(1)) < 65536:
                    fail(f'{f}:{line}: loot entry without a valid item id')
                child = re.search(r'\bchild\s*=\s*\{', code[k + 1:close])
                if child:
                    cs = k + 1 + child.end() - 1
                    stack.append((cs + 1, _closing(code, cs)))
                k = close + 1
            else:
                k += 1
    if entries == 0 and xp and int(xp.group(1)) > 0 and not (name and name.group(1).lower() in LOOTLESS_OK):
        fail(f'{f}: experience {xp.group(1)} but an empty monster.loot')

for f in sorted(glob.glob('server/data/monster/lua/chaos/**/*.lua', recursive=True)):
    check_lua_loot(f, open(f, encoding='utf-8', errors='ignore').read())

# ------------------------------------------------------------------------------------------------ monster rules
import hashlib, csv
import xml.etree.ElementTree as ET

def _opt(flag):
    return sys.argv[sys.argv.index(flag) + 1] if flag in sys.argv[:-1] else None

# the client pair the monsters are drawn with: pair 33 (client/MANIFEST.md "Pair 33 build"), 2667 outfits (pair 33 adds
# the wings 2385-2476, head accessories 2477-2568, capes 2569-2657 and the harvest kit looks 2658-2667, no blank
# padding; pairs 31 and 32 added none); things_custom30 had 2384 (pair 30 adds the
# 75 sheet looks 2237-2311 and the 73 strip looks 2312-2384, art_import/pack30_looks.csv and pack30_strips.csv, no
# blank padding; pair 29 added the Archmage 2235 / 2236); the blank ones have no sprite at all (stock gaps, 1562-1999 and 2082-2099 reserved, 2143-2160
# and 2194-2199 padding). --pair recounts both.
PAIR_NAME, PAIR_OUTFITS = 'pair 33', 2667
PAIR_BLANK = ('135 161-191 411 415 424 439-440 468-469 474-485 501 518-520 524-525 536 543 549 581-582 597 616 623 '
              '625 638-643 645-646 652-663 678 700-711 713 715 718-719 722-723 737 741-744 748 751-758 764-841 861 '
              '864-867 871-872 880 891-898 1562-1999 2082-2099 2143-2160 2194-2199')
def _ranges(text):
    out = set()
    for part in text.split():
        a, _, b = part.partition('-')
        out.update(range(int(a), int(b or a) + 1))
    return out
BLANK_OUTFITS = _ranges(PAIR_BLANK)
BASE_MAX_ITEM = 29926         # highest server id of the base items.xml; above it every id is ours
MAX_HIT = 100000              # one spell hit; no player has this much health
MAX_SPEED = 2000              # at the top of the level range (speed x(1 + 0.0085 L))
LEVEL_HEALTH, LEVEL_SPEED = 0.0074, 0.0085   # engine level scaling, see areagen_core.lua and server/README.md
BASE_EVENTS = set()           # creature events of the base scripts a Chaos monster may name (none today)
RACES = {'venom', 'blood', 'undead', 'fire', 'energy'}
SKULLS = {'none', 'yellow', 'green', 'white', 'red', 'black', 'orange'}
ROOT_ATTRS = {'name', 'namedescription', 'race', 'experience', 'speed', 'manacost', 'skull', 'script'}
ROOT_TAGS = {'health', 'look', 'targetchange', 'flags', 'attacks', 'defenses', 'elements', 'immunities', 'summons',
             'voices', 'loot', 'script', 'level'}
IMMUNITIES = {'physical', 'energy', 'fire', 'poison', 'earth', 'drown', 'ice', 'holy', 'death', 'lifedrain',
              'manadrain', 'paralyze', 'outfit', 'drunk', 'invisible', 'invisibility', 'bleed', 'water', 'arcane'}
ELEMENT_TYPE = {e: e[:-7].lower() for e in fmx.ELEMENTS}
ELEMENT_TYPE['poisonPercent'] = 'earth'
IMMUNITY_TYPE = {'poison': 'earth'}
DAMAGE_SPELLS = fmx.DAMAGE_SPELLS

# (code, lower-case monster name) -> why it stays
ALLOW = {
    ('flag.runonhealth', 'treasure goblin'): 'flees from the first hit on purpose (runThreshold, treasure_goblin_config.lua)',
    ('flag.runonhealth', 'gem goblin'): 'goblin variant of treasure_goblin.lua, same flee trick',
    ('flag.runonhealth', 'shard goblin'): 'goblin variant of treasure_goblin.lua, same flee trick',
    ('name.base-type', 'blue butterfly'): 'Lua import meant to replace the base type of that name (createMonsterType refills it)',
    ('name.base-type', 'red butterfly'): 'Lua import meant to replace the base type of that name',
    ('name.base-type', 'yellow butterfly'): 'Lua import meant to replace the base type of that name',
    ('name.base-type', 'scar tribe warrior'): 'Lua import meant to replace the base type of that name',
    ('name.base-type', 'overcharged energy elemental'): 'Lua import meant to replace the base type of that name',
}
allow_used = set()

def rule(code, name, f, msg):
    key = (code, name.lower())
    if key in ALLOW:
        allow_used.add(key); return
    fail(f'{f}: [{code}] {msg}')

def _int(v, default=0):
    try:
        return int(str(v).strip())
    except (TypeError, ValueError):
        return default

def _sha(name):
    return hashlib.sha256(name.strip().lower().encode('utf-8')).hexdigest()

def base_type_hashes():
    """hashes of the base monster types once install_all.py renamed them (base_monster_names.csv, kind monster)"""
    p = 'server/data/monster/base_monster_hashes.txt'
    hashes = {l.strip() for l in open(p, encoding='utf-8') if l.strip()} if os.path.exists(p) else set()
    renames = {}
    p = 'server/data/monster/base_monster_names.csv'
    if os.path.exists(p):
        for r in csv.DictReader(open(p, encoding='utf-8', newline='')):
            if (r.get('kind') or 'monster') == 'monster':
                renames[r['sha256'].strip().lower()] = r['name'].strip()
    return {(_sha(renames[h]) if h in renames else h) for h in hashes}
BASE_TYPES = base_type_hashes()

def our_item_ids():
    ids = set()
    for p in glob.glob('server/data/items/*.csv'):
        for r in csv.DictReader(open(p, encoding='utf-8', newline='')):
            for k in ('server_id', 'id'):
                if (r.get(k) or '').isdigit():
                    ids.add(int(r[k]))
    if os.path.exists(ip):
        ids |= {int(x) for x in re.findall(r'<item\s[^>]*?\bid="(\d+)"', open(ip, encoding='utf-8').read())}
    return ids
OUR_ITEMS = our_item_ids()

BASE_ITEMS = None   # --base: {id: (name, is container)}
if _opt('--base'):
    BASE_ITEMS = {}
    for el in ET.parse(os.path.join(_opt('--base'), 'items', 'items.xml')).getroot().iter('item'):
        cont = any((a.get('key') or '').lower() == 'containersize' for a in el.iter('attribute'))
        first = _int(el.get('id') or el.get('fromid')); last = _int(el.get('id') or el.get('toid'))
        for i in range(first, last + 1):
            BASE_ITEMS[i] = (el.get('name', ''), cont)

if _opt('--pair'):
    sys.path.insert(0, os.path.join('client', 'tools', 'sprites'))
    from datspr import Dat
    d = Dat(_opt('--pair'))
    blank = {o.id for o in d.outfits if not any(o.sprites)}
    if d.counts[1] != PAIR_OUTFITS or blank != BLANK_OUTFITS:
        fail(f'{_opt("--pair")}: {d.counts[1]} outfits, {len(blank)} blank; PAIR_OUTFITS / PAIR_BLANK say '
             f'{PAIR_OUTFITS} / {len(BLANK_OUTFITS)} (update them with this pair\'s numbers)')

EVENTS = set(BASE_EVENTS)
for p in glob.glob('server/data/scripts/**/*.lua', recursive=True):
    EVENTS |= set(re.findall(r'CreatureEvent\(\s*"([^"]+)"', open(p, encoding='utf-8', errors='ignore').read()))

def check_item_id(f, name, iid, what):
    if iid <= 0:
        return
    if iid > BASE_MAX_ITEM and iid not in OUR_ITEMS:
        rule('item.unknown', name, f, f'{what} {iid} is above the base ids and in none of server/data/items')
    elif BASE_ITEMS is not None and iid not in BASE_ITEMS and iid not in OUR_ITEMS:
        rule('item.unknown', name, f, f'{what} {iid} is not in {_opt("--base")}/items/items.xml')

def check_look(f, name, look):
    if look > PAIR_OUTFITS:
        rule('look.pair', name, f, f'lookType {look} is above the {PAIR_OUTFITS} outfits of {PAIR_NAME}')
    elif look in BLANK_OUTFITS:
        rule('look.pair', name, f, f'lookType {look} is a blank outfit of {PAIR_NAME} (nothing is drawn)')

def check_loot_items(f, name, parent):
    for it in parent.findall('item'):
        iid = _int(it.get('id'), None) if it.get('id', '').isdigit() else None
        ch = it.get('chance', it.get('chance1'))
        if ch is not None and not 0 < _int(ch) <= 100000:
            rule('loot.chance', name, f, f'loot item {it.get("id")} chance {ch} (1-100000)')
        if it.get('countmax') is not None and _int(it.get('countmax')) < 1:
            rule('loot.countmax', name, f, f'loot item {it.get("id")} countmax {it.get("countmax")} (the base reads 1)')
        if iid is not None:
            check_item_id(f, name, iid, 'loot item')
            if BASE_ITEMS is not None and (it.findall('item') or it.find('inside') is not None) \
                    and iid in BASE_ITEMS and not BASE_ITEMS[iid][1]:
                rule('loot.not-container', name, f, f'loot item {iid} has child items but is no container')
        for child in [it] + ([it.find('inside')] if it.find('inside') is not None else []):
            if child is not it or it.findall('item'):
                check_loot_items(f, name, child)

def check_spell(f, name, s, block, imm):
    sn = (s.get('name') or '').strip().lower()
    tag = f'<{s.tag} name="{s.get("name") or s.get("script")}">'
    if not sn and not s.get('script'):
        rule('spell.name', name, f, f'{block}: a spell with neither name nor script (dropped)'); return
    if s.get('script') and not os.path.exists(os.path.join('server/data/monster/scripts', s.get('script'))):
        rule('spell.script', name, f, f'{tag}: script {s.get("script")} is not in server/data/monster/scripts')
    if sn != 'melee' and s.get('chance') is None and not s.get('script'):
        rule('spell.chance', name, f, f'{tag}: no chance (the base warns and uses 100)')
    if _int(s.get('chance')) > 100:
        rule('spell.chance', name, f, f'{tag}: chance {s.get("chance")} above 100')
    iv = s.get('interval', s.get('speed'))
    if iv is not None and _int(iv) < 1:
        rule('spell.interval', name, f, f'{tag}: interval {iv} below 1')
    if _int(s.get('range')) > 20:
        rule('spell.range', name, f, f'{tag}: range {s.get("range")} above 20 (clamped)')
    mn, mx = _int(s.get('min')), _int(s.get('max'))
    if abs(mn) > abs(mx):
        rule('spell.min-max', name, f, f'{tag}: |min| {mn} above |max| {mx} (the base swaps them)')
    if sn in DAMAGE_SPELLS and (mn > 0 or mx > 0):
        rule('spell.sign', name, f, f'{tag}: positive min/max heals the target')
    if sn == 'healing' and (mn < 0 or mx < 0):
        rule('spell.sign', name, f, f'{tag}: negative healing damages the monster')
    if sn != 'healing' and max(abs(mn), abs(mx)) > MAX_HIT:
        rule('spell.big-hit', name, f, f'{tag}: one hit of {max(abs(mn), abs(mx))} (above {MAX_HIT})')
    if sn == 'speed':
        if s.get('speedchange') is None and not _int(s.get('minspeedchange')) and s.get('maxspeedchange') is None:
            rule('spell.speed', name, f, f'{tag}: no speedchange (the base drops the spell)')
        for k in ('speedchange', 'minspeedchange', 'maxspeedchange'):
            if s.get(k) is not None and _int(s.get(k)) < -1000:
                rule('spell.speed', name, f, f'{tag}: {k} {s.get(k)} below -1000 (clamped)')
    if sn == 'melee':
        if s.get('skill') is not None and s.get('attack') is None:
            rule('spell.melee', name, f, f'{tag}: skill without attack (min/max are used)')
        for k in ('bleed', 'physical'):
            if _int(s.get(k)) != 0:
                rule('spell.melee-bleed', name, f, f'{tag}: {k}="{s.get(k)}" is never read (a 0 damage bleed)')
    geo = [k for k in ('length', 'radius', 'ring') if s.get(k) is not None]
    if len(geo) > 1:
        rule('spell.geometry', name, f, f'{tag}: {", ".join(geo)} together (only the last counts)')
    for a in s.findall('attribute'):
        k, v = (a.get('key') or '').lower(), a.get('value') or ''
        if k not in ('areaeffect', 'shooteffect'):
            rule('spell.effect', name, f, f'{tag}: effect key {a.get("key")!r} does not exist')
        elif not fmx.known_effect('area' if k == 'areaeffect' else 'shoot', v):
            rule('spell.effect', name, f, f'{tag}: {a.get("key")} {v!r} is not a base effect (shows nothing)')
    if s.get('monster') and _sha(s.get('monster')) not in ALL_TYPES:
        rule('outfit.monster', name, f, f'{tag}: outfit monster {s.get("monster")!r} is no monster type')

def check_monster_rules(f, r):
    name = r.get('name', '')
    if not name.strip():
        fail(f'{f}: [name.missing] no name'); return
    nd = r.get('nameDescription', '')
    m = re.match(r'(an?) ([A-Za-z])', nd)
    if m and m.group(2).lower() != 'u' and (m.group(1) == 'an') != (m.group(2).lower() in 'aeio'):
        rule('name.article', name, f, f'nameDescription {nd!r}: wrong article')
    for k in r.attrib:
        if k.lower() not in ROOT_ATTRS:
            rule('root.attr', name, f, f'<monster {k}=...> is never read by the base')
    for c in r:
        if c.tag.lower() not in ROOT_TAGS:
            rule('root.tag', name, f, f'<{c.tag}> is never read by the base')
    if r.get('race') and r.get('race').lower() not in RACES:
        rule('race', name, f, f'race {r.get("race")!r} unknown (the base keeps blood)')
    if r.get('skull') and r.get('skull').lower() not in SKULLS:
        rule('skull', name, f, f'skull {r.get("skull")!r} unknown')
    lv = r.find('level')
    top = _int(lv.get('max')) if lv is not None else 0
    h = r.find('health')
    hmax = 0
    if h is None or h.get('now') is None or h.get('max') is None:
        rule('health', name, f, '<health now max> incomplete (the base uses 100)')
    else:
        hmax = _int(h.get('max'))
        if _int(h.get('now')) > hmax or hmax <= 0:
            rule('health', name, f, f'health now {h.get("now")} max {h.get("max")}')
    spd = _int(r.get('speed'))
    if spd < 0 or spd * (1 + LEVEL_SPEED * top) > MAX_SPEED:
        rule('speed', name, f, f'speed {spd} (at level {top}: {spd * (1 + LEVEL_SPEED * top):.0f}; 0-{MAX_SPEED})')
    look = r.find('look')
    if look is None or (look.get('type') is None and look.get('typeex') is None):
        rule('look.missing', name, f, 'no look type (the monster is invisible)')
    else:
        if look.get('type') is not None:
            check_look(f, name, _int(look.get('type')))
        corpse = _int(look.get('corpse'))
        loot = r.find('loot')
        if not corpse and loot is not None and loot.find('item') is not None:
            rule('corpse.none', name, f, 'loot but no corpse (the loot has nowhere to go)')
        if corpse:
            check_item_id(f, name, corpse, 'corpse')
            if BASE_ITEMS is not None and corpse in BASE_ITEMS and not BASE_ITEMS[corpse][1]:
                rule('corpse.container', name, f, f'corpse {corpse} {BASE_ITEMS[corpse][0]!r} is no container')
    for node in ('targetchange', 'voices'):
        n = r.find(node)
        if n is None:
            continue
        if n.get('interval') is None and n.get('speed') is None:
            rule(node, name, f, f'<{node}> without interval')
        if n.get('chance') is None or _int(n.get('chance')) > 100:
            rule(node, name, f, f'<{node}> chance {n.get("chance")} (needed, at most 100)')
    for v in (r.find('voices') if r.find('voices') is not None else []):
        if v.tag == 'voice' and not (v.get('sentence') or '').strip():
            rule('voices', name, f, 'an empty voice sentence')
    flags = {}
    for n in (r.find('flags') if r.find('flags') is not None else []):
        if len(n.attrib) > 1:
            rule('flag.node', name, f, f'<flag> with {len(n.attrib)} attributes (only the first is read)')
        for k, v in list(n.attrib.items())[:1]:
            flags[k.lower()] = v
    if _int(flags.get('staticattack')) > 100:
        rule('flag.range', name, f, f'staticattack {flags["staticattack"]} above 100')
    if 'targetdistance' in flags and _int(flags['targetdistance']) < 1:
        rule('flag.range', name, f, f'targetdistance {flags["targetdistance"]} below 1')
    if hmax and _int(flags.get('runonhealth')) >= hmax * (1 + LEVEL_HEALTH * top):
        rule('flag.runonhealth', name, f, f'runonhealth {flags["runonhealth"]} at or above the health '
             f'{hmax * (1 + LEVEL_HEALTH * top):.0f} (it always flees)')
    if flags.get('canpushcreatures') == '1' and flags.get('pushable') == '1':
        rule('flag.pushable', name, f, 'pushable="1" with canpushcreatures="1" (the base forces 0)')
    for k in ('summonable', 'convinceable'):
        if flags.get(k) == '1':
            rule('flag.tameable', name, f, f'{k}="1": players could summon or convince it')
    imm = set()
    for n in (r.find('immunities') if r.find('immunities') is not None else []):
        if len(n.attrib) > 1:
            rule('immunity.node', name, f, f'<immunity> with {len(n.attrib)} attributes (only the first is read)')
        for k, v in list(n.attrib.items())[:1]:
            key = (v if k == 'name' else k).lower()
            if key not in IMMUNITIES:
                rule('immunity.unknown', name, f, f'immunity {key!r} unknown')
            elif k == 'name' or v == '1':
                imm.add(IMMUNITY_TYPE.get(key, key))
    seen = {}
    for n in (r.find('elements') if r.find('elements') is not None else []):
        if len(n.attrib) > 1:
            rule('element.node', name, f, f'<element> with {len(n.attrib)} attributes (only the first is read)')
        for k, v in list(n.attrib.items())[:1]:
            typ = ELEMENT_TYPE.get(k)
            if typ in seen:
                rule('element.twice', name, f, f'{k}="{v}" after {seen[typ]} (one damage type; the last wins)')
            seen[typ] = f'{k}="{v}"'
            if typ in imm:
                rule('element.immune', name, f, f'{k}="{v}" on an immune type (the immunity wins)')
            if _int(v) > 100:
                rule('element.range', name, f, f'{k}="{v}" above 100')
    for block in ('attacks', 'defenses'):
        for s in (r.find(block) if r.find(block) is not None else []):
            check_spell(f, name, s, block, imm)
    su = r.find('summons')
    if su is not None:
        entries = su.findall('summon')
        ms = su.get('maxSummons')
        if entries and (ms is None or not 0 < _int(ms) <= 100):
            rule('summons', name, f, f'maxSummons {ms!r} with {len(entries)} summons (exact case, 1-100)')
        for e in entries:
            if not (e.get('name') or '').strip() or _sha(e.get('name')) not in ALL_TYPES:
                rule('summon.monster', name, f, f'summon {e.get("name")!r} is no monster type')
            if _int(e.get('chance')) > 100:
                rule('summons', name, f, f'summon chance {e.get("chance")} above 100')
    sc = r.find('script')
    for e in (sc if sc is not None else []):
        if e.get('name') not in EVENTS:
            rule('event', name, f, f'event {e.get("name")!r} is no CreatureEvent here (one warning per spawn)')
    if r.get('script') and not os.path.exists(os.path.join('server/data/monster/scripts', r.get('script'))):
        rule('script', name, f, f'script {r.get("script")} is not in server/data/monster/scripts')
    loot = r.find('loot')
    if loot is not None:
        check_loot_items(f, name, loot)

def check_lua_rules(f, t):
    code = _lua_code(t)
    m = re.search(r'createMonsterType\(\s*"([^"]+)"', t)
    if not m:
        return
    name = m.group(1)
    look = re.search(r'\blookType\s*=\s*(\d+)', code)
    if look:
        check_look(f, name, int(look.group(1)))
    corpse = re.search(r'\bmonster\.corpse\s*=\s*(\d+)', code)
    if corpse:
        check_item_id(f, name, int(corpse.group(1)), 'corpse')
    lm = re.search(r'\bmonster\.loot\s*=\s*\{', code)
    if lm:
        for iid in re.findall(r'\bid\s*=\s*(\d+)', code[lm.end():_closing(code, lm.end() - 1)]):
            check_item_id(f, name, int(iid), 'loot item')
    hp = re.search(r'\bmonster\.health\s*=\s*(\d+)', code)
    hm = re.search(r'\bmonster\.maxHealth\s*=\s*(\d+)', code)
    if hp and hm and int(hp.group(1)) > int(hm.group(1)):
        rule('health', name, f, f'health {hp.group(1)} above maxHealth {hm.group(1)}')
    sm = re.search(r'\bmonster\.summons\s*=\s*\{', code)
    if sm:
        for s in re.findall(r'\bname\s*=\s*"([^"]+)"', t[sm.end():_closing(code, sm.end() - 1)]):
            if _sha(s) not in ALL_TYPES:
                rule('summon.monster', name, f, f'summon {s!r} is no monster type')

XML_DOCS = []
for f in sorted(glob.glob('server/data/monster/monsters/chaos/**/*.xml', recursive=True)):
    try:
        XML_DOCS.append((f, ET.parse(f).getroot()))
    except ET.ParseError:
        pass   # reported above
LUA_DOCS = []
for f in sorted(glob.glob('server/data/monster/lua/chaos/**/*.lua', recursive=True)):
    t = open(f, encoding='utf-8', errors='ignore').read()
    m = re.search(r'createMonsterType\(\s*"([^"]+)"', t)
    if m:
        LUA_DOCS.append((f, m.group(1), t))
OURS = {}
for f, n in [(f, r.get('name', '')) for f, r in XML_DOCS] + [(f, n) for f, n, _t in LUA_DOCS]:
    if n.lower() in OURS and f.endswith('.lua'):
        rule('name.duplicate', n, f, f'name {n!r} also in {OURS[n.lower()]}')
    OURS.setdefault(n.lower(), f)
    if _sha(n) in BASE_TYPES:
        rule('name.base-type', n, f, f'{n!r} is also a base monster type (ours is skipped or overwritten at load)')
ALL_TYPES = BASE_TYPES | {_sha(n) for n in OURS}
for f, r in XML_DOCS:
    check_monster_rules(f, r)
for f, _n, t in LUA_DOCS:
    check_lua_rules(f, t)
for key in sorted(set(ALLOW) - allow_used):
    fail(f'tools/ci/check_content.py: ALLOW entry {key} matches nothing any more (remove it)')
print('content check:', 'OK' if not bad else f'{bad} problem(s)')
sys.exit(1 if bad else 0)
