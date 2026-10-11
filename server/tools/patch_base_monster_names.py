#!/usr/bin/env python3
"""Give the base monsters Cinders of Chaos names (server/README.md "Base monster names").

usage: python3 -I patch_base_monster_names.py DATA_DIR [--names CSV] [--dry-run]

The new names come from server/data/monster/base_monster_names.csv (columns sha256, name, kind). The sha256 column is
the SHA-256 (hex) of the old name in lower case, so the repository never holds the old names: the tool collects the
names it finds in the base data, hashes each one and renames the ones the CSV knows. kind is "monster" (a monster
type, renamed wherever the base data names it) or "look" (an outfit or mount of data/XML/outfits.xml or mounts.xml,
renamed only there). The same CSV is the hashed mapping for later renames of the base world (NPC dialogue, quests).

Names are collected from data/monster/monsters.xml, the monster XML files, every Game.createMonsterType("...") of the
Lua monsters, the spawn files in data/world, the raid files and the outfit and mount lists. A monster name is then
replaced, case-insensitively and as whole words, in:
1. data/monster/monsters.xml: the registered names. A registration whose new name is already registered by another
   line (a leftover of an older install) is dropped, so a monster type is never registered twice.
2. XML files (monster files, the spawn files, raids, creaturescripts.xml and the other base XML lists): attribute values
   (name, nameDescription, summons, voices, event names, raid spawns, ...). Values that are paths (a "/" or a file
   extension) are left alone, and so are NPC entries of the spawn files (<npc name="..."/>), effect names (<attribute key="areaEffect" value="..."/>) and the house files (house names are a later rename), and so are the name, article and plural of items.xml entries (patch_base_item_names.py
   renames items).
3. Lua files (Lua monsters, scripts, actions, creature scripts, libs, ...): inside string literals only, never in
   identifiers or comments (storage keys such as Storage.X.YTeleport keep working); a name joined to other words by "_"
   (a key such as "name_kills") or to a word before it by an apostrophe is not a whole word and stays. Strings that are paths are left
   alone. "a"/"an" right before a renamed name is corrected.
A whole-word match that is part of a longer name (an item of items.xml, such as a corpse "dead <name>", or another
monster that keeps its name) is left to that name. Not touched: data/npc (dialogue, a later rename), data/XML/quests.xml
(quest log prose), data/scripts/chaos, data/lib/chaos_*.lua and the Chaos monster folders (they come from this
repository with the new names). Monster file names stay: the engine registers monsters by the name in monsters.xml, not
by file name.

Run it before the steps that read monster names from the repository (late_game.py, the spawn tuning): install_all.py
runs it as step `monsternames`, right after `lib`.

Idempotent: a second run finds no old names and changes nothing. --dry-run writes nothing.
"""
import csv
import hashlib
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
CSV_PATH = os.path.join(os.path.dirname(HERE), 'data', 'monster', 'base_monster_names.csv')
KINDS = ('monster', 'look')
REF_DIRS = ('monster', 'world', 'raids', 'scripts', 'actions', 'creaturescripts', 'globalevents', 'movements', 'lib',
            'events', 'talkactions', 'weapons', 'spells', 'XML', 'items')
SKIP_DIRS = (os.path.join('scripts', 'chaos'), os.path.join('monster', 'monsters', 'chaos'),
             os.path.join('monster', 'lua', 'chaos'), 'npc')
SKIP_FILES = (os.path.join('XML', 'quests.xml'),)
ROOT_FILES = ('global.lua',)
LOOK_FILES = (os.path.join('XML', 'outfits.xml'), os.path.join('XML', 'mounts.xml'))
PATHLIKE = re.compile(r'[/\\]|\.(lua|xml|otbm|ogg|wav|png|txt|json|sql)$', re.I)
ITEM_OWN_ATTRS = ('name', 'article', 'plural')


def digest(name):
    return hashlib.sha256(name.strip().lower().encode('utf-8')).hexdigest()


def read_names(path=CSV_PATH):
    """-> {sha256: (new name, kind)}"""
    rows = {}
    with open(path, encoding='utf-8', newline='') as f:
        for row in csv.DictReader(f):
            key = (row.get('sha256') or '').strip().lower()
            if not key or key.startswith('#'):
                continue
            name = (row.get('name') or '').strip()
            kind = (row.get('kind') or 'monster').strip() or 'monster'
            if not re.match(r'^[0-9a-f]{64}$', key) or not name or kind not in KINDS or re.search(r'["<>&]', name):
                raise SystemExit('%s: bad row %r' % (path, row))
            if key in rows:
                raise SystemExit('%s: hash %s twice' % (path, key))
            rows[key] = (name, kind)
    lowered = [(n.lower(), k) for n, k in rows.values()]
    if len(set(lowered)) != len(lowered):
        raise SystemExit('%s: two rows with the same new name' % path)
    return rows


# ------------------------------------------------------------------------------------------------ files
def read(path):
    with open(path, encoding='utf-8', errors='surrogateescape', newline='') as f:
        return f.read()


def write(path, text):
    with open(path, 'w', encoding='utf-8', errors='surrogateescape', newline='') as f:
        f.write(text)


def ref_files(data):
    for f in ROOT_FILES:
        p = os.path.join(data, f)
        if os.path.isfile(p):
            yield p
    for sub in REF_DIRS:
        root = os.path.join(data, sub)
        for dirpath, dirs, files in os.walk(root):
            dirs.sort()
            rel = os.path.relpath(dirpath, data)
            if any(rel == d or rel.startswith(d + os.sep) for d in SKIP_DIRS):
                dirs[:] = []
                continue
            for f in sorted(files):
                if not f.endswith(('.lua', '.xml')):
                    continue
                if sub == 'lib' and f.startswith('chaos_'):
                    continue
                p = os.path.join(dirpath, f)
                if os.path.relpath(p, data) in SKIP_FILES or f.endswith('-house.xml'):
                    continue
                yield p


# ------------------------------------------------------------------------------------------------ names in the data
def found_names(data):
    """-> (monster names, look names, item names): every name the base data uses, lower case"""
    monsters, looks, items = set(), set(), set()
    mxml = os.path.join(data, 'monster', 'monsters.xml')
    if os.path.isfile(mxml):
        for m in re.finditer(r'<monster\s+name="([^"]*)"\s+file="([^"]*)"', read(mxml)):
            monsters.add(m.group(1).lower())
    for dirpath, dirs, files in os.walk(os.path.join(data, 'monster')):
        dirs.sort()
        for f in files:
            p = os.path.join(dirpath, f)
            if f.endswith('.xml') and f != 'monsters.xml':
                m = re.search(r'<monster\s[^>]*?\bname="([^"]*)"', read(p))
                if m:
                    monsters.add(m.group(1).lower())
            elif f.endswith('.lua'):
                for m in re.finditer(r'createMonsterType\(\s*(?:"([^"]*)"|\'([^\']*)\')', read(p)):
                    monsters.add((m.group(1) if m.group(1) is not None else m.group(2)).lower())
    for sub in ('world', 'raids'):
        for dirpath, dirs, files in os.walk(os.path.join(data, sub)):
            for f in files:
                if f.endswith('.xml'):
                    for m in re.finditer(r'<(?:monster|singlespawn)\s[^>]*?\bname="([^"]*)"', read(os.path.join(dirpath, f))):
                        monsters.add(m.group(1).lower())
    for rel in LOOK_FILES:
        p = os.path.join(data, rel)
        if os.path.isfile(p):
            for m in re.finditer(r'<(?:outfit|mount)\s[^>]*?\bname="([^"]*)"', read(p)):
                looks.add(m.group(1).lower())
    ixml = os.path.join(data, 'items', 'items.xml')
    if os.path.isfile(ixml):
        items = {m.lower() for m in re.findall(r'<item\s[^>]*?\bname="([^"]*)"', read(ixml))}
    return monsters, looks, items


def mapping(rows, monsters, looks):
    """-> ({old lower: new} monsters, {old lower: new} looks) for the names of the data that the CSV knows"""
    mon, lk = {}, {}
    for n in monsters:
        r = rows.get(digest(n))
        if r and r[1] == 'monster' and r[0].lower() != n:
            mon[n] = r[0]
    for n in looks:
        r = rows.get(digest(n))
        if r and r[0].lower() != n:
            lk[n] = r[0]
    return mon, lk


# ------------------------------------------------------------------------------------------------ replacing
def _alternation(names):
    return '|'.join(re.escape(n) for n in sorted(names, key=len, reverse=True))


class Renamer:
    """whole-word, case-insensitive replacement of the old names inside one string value"""

    def __init__(self, renamed, keep=()):
        self.renamed = renamed
        self.rx = re.compile(r"(?<![A-Za-z0-9_])(?<![A-Za-z]')(%s)(?![A-Za-z0-9_])" % _alternation(renamed), re.I) if renamed else None
        rx = self.rx
        longer = sorted({k for k in keep if k not in renamed and rx and rx.search(k)}, key=len, reverse=True)
        self.keep = re.compile(r"(?<![A-Za-z0-9_])(%s)(?![A-Za-z0-9_])" % _alternation(longer), re.I) if longer else None
        self.count = 0

    def new_for(self, matched):
        new = self.renamed[matched.lower()]
        if matched == matched.lower():
            return new.lower()
        if matched == matched.upper() and len(matched) > 1:
            return new.upper()
        return new

    def __call__(self, value):
        if not self.rx or not self.rx.search(value):
            return value
        kept = []
        if self.keep:
            def hide(m):
                kept.append(m.group(0))
                return '\x00%d\x00' % (len(kept) - 1)
            value = self.keep.sub(hide, value)
        out, last = [], 0
        for m in self.rx.finditer(value):
            new = self.new_for(m.group(1))
            head = value[last:m.start()]
            art = re.search(r'(?<![A-Za-z])(an?)(\s+)$', head, re.I)
            if art:
                want = 'an' if new[:1].lower() in 'aeiou' else 'a'
                had = art.group(1)
                if had == had.upper() and (len(had) > 1 or new == new.upper()):
                    want = want.upper()
                elif had[0].isupper():
                    want = want.capitalize()
                head = head[:art.start(1)] + want + art.group(2)
            out.append(head)
            out.append(new)
            last = m.end()
            self.count += 1
        out.append(value[last:])
        value = ''.join(out)
        if kept:
            value = re.sub('\x00(\\d+)\x00', lambda m: kept[int(m.group(1))], value)
        return value


ATTR = re.compile(r'(\s)([A-Za-z_:][\w:.-]*)(\s*=\s*)(")([^"]*)(")')
TAG = re.compile(r'<[A-Za-z][^<>]*>')
# <attribute key="areaEffect" value="..."/>: engine effect names, some of them spelled like a monster
# <npc name="..."/> in the spawn files: an NPC that shares a monster's name keeps it (NPCs are a later rename)
NPC_TAG = re.compile(r'<npc\b', re.I)
EFFECT_KEY = re.compile(r'\bkey="[^"]*effect[^"]*"', re.I)


def patch_xml(text, ren, item_file=False):
    """attribute values of every tag"""
    def attr(m):
        key, value = m.group(2), m.group(5)
        if PATHLIKE.search(value) or key.lower() in ('file', 'script', 'path'):
            return m.group(0)
        if item_file and key.lower() in ITEM_OWN_ATTRS:
            return m.group(0)
        new = ren(value)
        return m.group(0) if new == value else '%s%s%s"%s"' % (m.group(1), key, m.group(3), new)

    def tag(m):
        t = m.group(0)
        if '=' not in t or EFFECT_KEY.search(t) or NPC_TAG.match(t):
            return t
        return ATTR.sub(attr, t)
    return TAG.sub(tag, text)


def lua_string_spans(text):
    """[(start, end)] of the contents of every string literal, comments skipped"""
    spans, i, n = [], 0, len(text)
    while i < n:
        c = text[i]
        if c == '-' and text.startswith('--', i):
            m = re.match(r'--\[(=*)\[', text[i:i + 64])
            if m:
                close = ']' + m.group(1) + ']'
                j = text.find(close, i + m.end())
                i = n if j < 0 else j + len(close)
            else:
                j = text.find('\n', i)
                i = n if j < 0 else j + 1
            continue
        if c in '"\'':
            j = i + 1
            while j < n and text[j] != c and text[j] != '\n':
                j += 2 if text[j] == '\\' else 1
            spans.append((i + 1, min(j, n)))
            i = j + 1
            continue
        if c == '[':
            m = re.match(r'\[(=*)\[', text[i:i + 64])
            if m:
                close = ']' + m.group(1) + ']'
                j = text.find(close, i + m.end())
                j = n if j < 0 else j
                spans.append((i + m.end(), j))
                i = j + len(close)
                continue
        i += 1
    return spans


def patch_lua(text, ren):
    out, last = [], 0
    for a, b in lua_string_spans(text):
        value = text[a:b]
        if PATHLIKE.search(value):
            continue
        new = ren(value)
        if new != value:
            out.append(text[last:a])
            out.append(new)
            last = b
    if not out:
        return text
    out.append(text[last:])
    return ''.join(out)


def patch_registrations(text, mon):
    """monsters.xml: rename registrations, drop a line whose new name another line already registers
    -> (text, renamed lines, dropped lines)"""
    lines = text.splitlines(True)
    names = []
    for line in lines:
        m = re.search(r'<monster\s+name="([^"]*)"', line)
        names.append(m.group(1).lower() if m else None)
    final = [mon[n].lower() if n in mon else n for n in names]
    # lines that end up with one name but had different names before: the line that already had the new name wins
    # (else the first one); lines that already shared one name (the base registers some monsters twice) stay as they are
    groups = {}
    for i, n in enumerate(final):
        if n is not None:
            groups.setdefault(n, []).append(i)
    drop = set()
    for n, idx in groups.items():
        if len({names[i] for i in idx}) < 2:
            continue
        had = [i for i in idx if names[i] not in mon]
        win = names[had[0]] if had else names[idx[0]]
        drop.update(i for i in idx if names[i] != win)
    out, renamed, dropped = [], 0, 0
    for i, line in enumerate(lines):
        n = names[i]
        if i in drop:
            dropped += 1
            continue
        if n in mon:
            line = re.sub(r'(<monster\s+name=")[^"]*(")', lambda m: m.group(1) + mon[n] + m.group(2), line, count=1)
            renamed += 1
        out.append(line)
    return ''.join(out), renamed, dropped


def patch_looks(text, lk):
    n = [0]

    def sub(m):
        new = lk.get(m.group(3).lower())
        if not new:
            return m.group(0)
        n[0] += 1
        return m.group(1) + m.group(2) + new + m.group(4)
    out = re.sub(r'(<(?:outfit|mount)\s[^>]*?)(\bname=")([^"]*)(")', sub, text)
    return out, n[0]


def count_tags(text, tag_rx, names):
    return sum(1 for m in re.finditer(tag_rx, text) if m.group(1).lower() in names)


def patch_data(data, mon, lk, items, monsters):
    """-> ({path: new text}, stats)"""
    writes, stats = {}, {'registrations': 0, 'dropped': 0, 'spawns': 0, 'raids': 0, 'looks': 0, 'mentions': 0}
    ren = Renamer(mon, keep=set(items) | set(monsters))
    mxml = os.path.join(data, 'monster', 'monsters.xml')
    for p in ref_files(data):
        t = read(p)
        rel = os.path.relpath(p, data)
        new = t
        if p == mxml:
            new, stats['registrations'], stats['dropped'] = patch_registrations(t, mon)
        elif p.endswith('.xml'):
            if rel.split(os.sep)[0] == 'world':
                stats['spawns'] += count_tags(t, r'<monster\s[^>]*?\bname="([^"]*)"', mon)
            elif rel.split(os.sep)[0] == 'raids':
                stats['raids'] += count_tags(t, r'<(?:monster|singlespawn)\s[^>]*?\bname="([^"]*)"', mon)
            if rel in LOOK_FILES and lk:
                new, k = patch_looks(new, lk)
                stats['looks'] += k
            new = patch_xml(new, ren, item_file=(rel == os.path.join('items', 'items.xml')))
        else:
            new = patch_lua(t, ren)
        if new != t:
            writes[p] = new
    stats['mentions'] = ren.count
    return writes, stats


def main(argv):
    dry = '--dry-run' in argv
    names = CSV_PATH
    if '--names' in argv:
        k = argv.index('--names')
        if k + 1 >= len(argv):
            print(__doc__)
            return 2
        names = argv[k + 1]
        argv = argv[:k] + argv[k + 2:]
    args = [a for a in argv if not a.startswith('--')]
    if len(args) != 1:
        print(__doc__)
        return 2
    data = args[0]
    if not os.path.isfile(os.path.join(data, 'monster', 'monsters.xml')):
        print('not found:', os.path.join(data, 'monster', 'monsters.xml'))
        return 1
    rows = read_names(names)
    monsters, looks, items = found_names(data)
    mon, lk = mapping(rows, monsters, looks)
    writes, st = patch_data(data, mon, lk, items, monsters)
    for p in sorted(writes)[:40]:
        print('  %s' % os.path.relpath(p, data))
    if len(writes) > 40:
        print('  ... and %d more' % (len(writes) - 40))
    known = sum(1 for n, k in rows.values() if k == 'monster')
    print('monsters: %d names renamed now (%d in the CSV); registrations %d (%d duplicate lines dropped), spawn entries %d, '
          'raid spawns %d, mentions %d; outfits and mounts: %d'
          % (len(mon), known, st['registrations'], st['dropped'], st['spawns'], st['raids'], st['mentions'], st['looks']))
    if dry:
        print('dry run: nothing written (%d file(s) would change)' % len(writes))
        return 0
    for p, t in writes.items():
        write(p, t)
    print('%d file(s) written' % len(writes))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
