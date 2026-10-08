#!/usr/bin/env python3
"""Server content consistency (no game data needed):
 - XML files parse (fragments such as spells_chaos.xml are checked wrapped in a root element)
 - spells: unique spellid, words and name; every script file exists under data/spells/chaos
 - items: unique ids in chaos_items.xml
 - monsters (monsters/chaos and its subfolders, e.g. world_bosses/): unique names; a lookType above MAX_OUTFIT must be
   listed in needs_sprites.txt
Usage: python3 tools/ci/check_content.py"""
import glob, os, re, subprocess, sys
import xml.dom.minidom as minidom

MAX_OUTFIT = 1501  # outfits of the merged dat (see server/data/monster/CUSTOM_MONSTERS.md)
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

for f in subprocess.check_output(['git', 'ls-files', '*.xml'], text=True).split():
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
print('content check:', 'OK' if not bad else f'{bad} problem(s)')
sys.exit(1 if bad else 0)
