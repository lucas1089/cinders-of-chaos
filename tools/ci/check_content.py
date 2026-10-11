#!/usr/bin/env python3
"""Server content consistency (no game data needed):
 - XML files parse (fragments such as spells_chaos.xml are checked wrapped in a root element)
 - spells: unique spellid, words and name; every script file exists under data/spells/chaos
 - items: unique ids in chaos_items.xml
 - monsters (monsters/chaos and its subfolders, e.g. world_bosses/): unique names; a lookType above MAX_OUTFIT must be
   listed in needs_sprites.txt; no loot id lists ("a;b"), monster spells, flags and element keys must be known to the
   base (server/tools/fix_monster_xml.py holds the lists and fixes most problems); experience > 0 needs a loot item
   unless the name is in LOOTLESS_OK
Usage: python3 tools/ci/check_content.py"""
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
MAX_OUTFIT = _max_outfit()  # 2125 with things_custom11 / things_custom12 (see server/data/monster/CUSTOM_MONSTERS.md)
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
KNOWN_SPELLS, KNOWN_FLAGS, KNOWN_ELEMENTS = fmx.known_spells(), fmx.known_flags(), set(fmx.ELEMENTS)

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
print('content check:', 'OK' if not bad else f'{bad} problem(s)')
sys.exit(1 if bad else 0)
