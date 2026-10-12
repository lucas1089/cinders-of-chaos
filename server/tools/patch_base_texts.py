#!/usr/bin/env python3
"""Rewrite the old world's proper nouns in the base server's texts (server/README.md "Base world texts").

usage: python3 -I patch_base_texts.py DATA_DIR [--names CSV] [--npc-names CSV] [--monster-names CSV]
                                               [--map PATH | --no-map] [--map-only] [--dry-run] [--no-backup]

Players read the base world in NPC dialogue, the quest log, raid messages, achievements, books, signs, item
descriptions and script messages. This tool replaces every name of the old world there with its Cinders of Chaos
name, from three hashed lists (no old name is in the repository; see base_rename_lib.py):
  server/data/npc/base_world_names.csv    towns, places, gods, factions, persons, lore words, outfit and mount words
  server/data/npc/base_npc_names.csv      the NPCs (rows of kind `npc`; patch_base_npc_names.py renames the NPCs)
  server/data/monster/base_monster_names.csv  the monsters (patch_base_monster_names.py leaves data/npc and the quest
                                          log to this tool)
A phrase of the data is looked up by the sha256 of its lower case form. When two lists know one phrase, the world
list wins, then the NPC list, then the monster list.

Where:
1. XML files of the base data (data/npc, data/XML with the quest log, outfits and mounts, data/raids, data/items with
   the item descriptions but not the item names, data/monster and the other lists): attribute values. Paths,
   file / script attributes, spell / talkaction words and engine effect names (key="...Effect") stay.
2. Lua files of the base data: the contents of string literals (dialogue, keywords, travel destinations, messages,
   achievement texts), never identifiers or comments. Paths and spell words (`words("...")`, `words = "..."`) stay.
3. The map (.otbm, as the towns step finds it, or --map): the texts and descriptions of items (signs, books, plaques).
   Item nodes are parsed attribute by attribute; a node with an attribute this tool does not know is left alone. The
   rebuilt file is checked (same item nodes, the new texts read back) before it replaces the map through a temporary
   file; <map>.otbm.bak keeps the original the first time (unless --no-backup).
Not touched: data/world (the spawn and house files: patch_base_npc_names.py and patch_base_houses.py), the repository's
own files (data/scripts/chaos, data/spells/chaos, data/lib/chaos_*.lua, the Chaos monster folders, the NPCs of
server/data/npc), and any name of an
item, monster or NPC the data still uses (a whole item name that contains an old word keeps it, so a lookup by name
still finds the item).

Whole words only; a/an before a new name is corrected; "the" is not doubled; NPC keywords are strings like any other,
so a player says the new name. Rows of match `cap` (old names that are also English words) change only where written
with a capital letter or as a keyword, and not inside the title-case names of outfits and mounts ("Crimson X").

Idempotent: a second run finds no old name and changes nothing. --dry-run writes nothing.
"""
import os
import re
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import base_rename_lib as L  # noqa: E402

WORLD_KINDS = ('town', 'demonym', 'world', 'god', 'place', 'faction', 'person', 'lore', 'look')
SKIP_DIRS = (os.path.join('scripts', 'chaos'), os.path.join('spells', 'chaos'), os.path.join('monster', 'monsters', 'chaos'),
             os.path.join('monster', 'lua', 'chaos'), 'world', 'logs', 'reports', 'migrations', 'patchnotes')
ITEM_OWN_ATTRS = ('name', 'article', 'plural')
# <attribute key="areaEffect" value="..."/>: engine effect names, some spelled like an old monster
EFFECT_KEY = re.compile(r'\bkey="[^"]*effect[^"]*"', re.I)


# ------------------------------------------------------------------------------------------------ the data files
def text_files(data):
    own = L.own_npc_files()
    npc = os.path.join(data, 'npc')
    for dirpath, dirs, files in os.walk(data):
        dirs.sort()
        rel = os.path.relpath(dirpath, data)
        if rel != '.' and any(rel == d or rel.startswith(d + os.sep) for d in SKIP_DIRS):
            dirs[:] = []
            continue
        for f in sorted(files):
            if not f.endswith(('.lua', '.xml')):
                continue
            if rel == 'lib' and f.startswith('chaos_'):
                continue
            p = os.path.join(dirpath, f)
            if p.startswith(npc + os.sep) and os.path.relpath(p, npc).replace(os.sep, '/') in own:
                continue
            yield p


def kept_names(data):
    """names the data uses for lookups: item names, monster names, NPC names (lower case)"""
    return set(item_names(data)) | other_names(data)


def item_names(data):
    ixml = os.path.join(data, 'items', 'items.xml')
    if not os.path.isfile(ixml):
        return set()
    return {m.lower() for m in re.findall(r'<item\s[^>]*?\sname="([^"]*)"', L.read(ixml))}


def other_names(data):
    """monster and NPC names (lower case)"""
    keep = set()
    mxml = os.path.join(data, 'monster', 'monsters.xml')
    if os.path.isfile(mxml):
        keep |= {m.lower() for m in re.findall(r'<monster\s+name="([^"]*)"', L.read(mxml))}
    for dirpath, dirs, files in os.walk(os.path.join(data, 'monster')):
        for f in files:
            if f.endswith('.xml') and f != 'monsters.xml':
                m = re.search(r'<monster\s[^>]*?\bname="([^"]*)"', L.read(os.path.join(dirpath, f)))
                if m:
                    keep.add(m.group(1).lower())
            elif f.endswith('.lua'):
                for m in re.finditer(r'createMonsterType\(\s*["\']([^"\']*)["\']', L.read(os.path.join(dirpath, f))):
                    keep.add(m.group(1).lower())
    npc = os.path.join(data, 'npc')
    if os.path.isdir(npc):
        for f in os.listdir(npc):
            if f.endswith('.xml'):
                m = re.search(r'<npc\b[^>]*?\bname="([^"]*)"', L.read(os.path.join(npc, f)))
                if m:
                    keep.add(m.group(1).lower())
    return keep


def collect_strings(data):
    """every string the tool may change: {path: [values]}"""
    out = {}
    for p in text_files(data):
        t = L.read(p)
        out[p] = list(v for k, v in L.xml_values(t)) if p.endswith('.xml') else list(L.lua_strings(t))
    return out


def merged_rows(world, npc, monster):
    rows = dict(monster)
    rows.update({k: v for k, v in npc.items() if v[1] == 'npc'})
    rows.update(world)
    return rows


LOOK_FILES = (os.path.join('XML', 'outfits.xml'), os.path.join('XML', 'mounts.xml'))


def patch_files(data, ren, titles=None):
    writes = {}
    ixml = os.path.join(data, 'items', 'items.xml')
    looks = {os.path.join(data, f) for f in LOOK_FILES}
    for p in text_files(data):
        t = L.read(p)
        if p.endswith('.xml'):
            new = L.patch_xml(t, titles if (titles and p in looks) else ren, skip_attrs=(ITEM_OWN_ATTRS if p == ixml else ()) + ('words',),
                              skip_tag=EFFECT_KEY.search)
        else:
            new = L.patch_lua(t, ren, skip_words=True)
        if new != t:
            writes[p] = new
    return writes


# ------------------------------------------------------------------------------------------------ the map
class MapError(Exception):
    pass


ESC, START, END = 0xFD, 0xFE, 0xFF
A_TEXT, A_DESC = 6, 7
FIXED = {4: 2, 5: 2, 8: 5, 10: 2, 12: 1, 14: 1, 15: 1, 16: 4, 17: 1, 18: 4, 20: 4, 21: 4, 22: 2, 23: 4}
STRINGS = {1, 6, 7, 19, 30, 31, 32}
ITEM_NODE = re.compile(rb'\xfe\x06((?:\xfd[\x00-\xff]|[^\xfd\xfe\xff])+)')


def _real(data, i):
    j = i
    while j > 0 and data[j - 1] == ESC:
        j -= 1
    return (i - j) % 2 == 0


def unescape(b):
    return re.sub(rb'\xfd([\x00-\xff])', lambda m: m.group(1), b)


def escape(b):
    return re.sub(rb'([\xfd\xfe\xff])', lambda m: b'\xfd' + m.group(1), b)


def parse_item(payload):
    """unescaped item node payload -> (id bytes, [(attr, value bytes or str)]) or None when an attribute is unknown"""
    if len(payload) < 2:
        return None
    attrs, q = [], 2
    while q < len(payload):
        a = payload[q]
        q += 1
        if a in FIXED:
            n = FIXED[a]
            if q + n > len(payload):
                return None
            attrs.append((a, payload[q:q + n]))
            q += n
        elif a in STRINGS:
            if q + 2 > len(payload):
                return None
            ln = struct.unpack_from('<H', payload, q)[0]
            if q + 2 + ln > len(payload):
                return None
            attrs.append((a, payload[q + 2:q + 2 + ln].decode('latin-1')))
            q += 2 + ln
        else:
            return None
    return payload[:2], attrs


def build_item(iid, attrs):
    out = bytearray(iid)
    for a, v in attrs:
        out.append(a)
        if isinstance(v, str):
            b = v.encode('latin-1')
            out += struct.pack('<H', len(b)) + b
        else:
            out += v
    return bytes(out)


def map_texts(data):
    """[(attr, text)] of every item text of a map (for collecting phrases)"""
    out = []
    for m in ITEM_NODE.finditer(data):
        if len(m.group(1)) <= 2 or not _real(data, m.start()):
            continue
        parsed = parse_item(unescape(m.group(1)))
        if parsed:
            out += [(a, v) for a, v in parsed[1] if a in (A_TEXT, A_DESC)]
    return out


def patch_map(data, ren):
    """-> (new bytes or None, changed nodes, unparsed nodes)"""
    chunks, last, changed, unparsed, expect = [], 0, 0, 0, []
    for m in ITEM_NODE.finditer(data):
        raw = m.group(1)
        if len(raw) <= 2 or not _real(data, m.start()):
            continue
        parsed = parse_item(unescape(raw))
        if parsed is None:
            unparsed += 1
            continue
        iid, attrs = parsed
        new_attrs, hit = [], False
        for a, v in attrs:
            if a in (A_TEXT, A_DESC):
                nv = ren(v)
                try:
                    nv.encode('latin-1')
                except UnicodeEncodeError:
                    nv = v
                if nv != v:
                    hit = True
                    v = nv
            new_attrs.append((a, v))
        if not hit:
            continue
        body = escape(build_item(iid, new_attrs))
        chunks.append(data[last:m.start(1)])
        chunks.append(body)
        last = m.end(1)
        changed += 1
        expect.append([v for a, v in new_attrs if a in (A_TEXT, A_DESC)])
    if not changed:
        return None, 0, unparsed
    chunks.append(data[last:])
    out = b''.join(chunks)
    # read it back: the same item nodes, and the changed texts where they were written
    n_old = sum(1 for m in ITEM_NODE.finditer(data) if _real(data, m.start()))
    n_new = sum(1 for m in ITEM_NODE.finditer(out) if _real(out, m.start()))
    if n_old != n_new:
        raise MapError('item node count changed (%d -> %d)' % (n_old, n_new))
    if out.count(b'\xfe') - out.count(b'\xfd\xfe') != data.count(b'\xfe') - data.count(b'\xfd\xfe'):
        raise MapError('node markers changed')
    texts_new = [v for a, v in map_texts(out) if a in (A_TEXT, A_DESC)]
    for want in expect:
        for v in want:
            if v not in texts_new:
                raise MapError('a rewritten text does not read back')
    return out, changed, unparsed


# ------------------------------------------------------------------------------------------------ main
def opt(argv, name):
    if name in argv:
        k = argv.index(name)
        if k + 1 >= len(argv):
            raise SystemExit('%s needs a value' % name)
        return argv[k + 1], argv[:k] + argv[k + 2:]
    return None, argv


def main(argv):
    dry = '--dry-run' in argv
    no_map = '--no-map' in argv
    map_only = '--map-only' in argv
    backup = '--no-backup' not in argv
    world_csv, argv = opt(argv, '--names')
    npc_csv, argv = opt(argv, '--npc-names')
    mon_csv, argv = opt(argv, '--monster-names')
    map_arg, argv = opt(argv, '--map')
    args = [a for a in argv if not a.startswith('--')]
    if len(args) != 1:
        print(__doc__)
        return 2
    data = args[0]
    if not os.path.isdir(data):
        print('not found:', data)
        return 1
    world = L.read_rows(world_csv or L.WORLD_CSV, WORLD_KINDS)
    npc = L.read_rows(npc_csv or L.NPC_CSV, ('npc', 'file')) if (npc_csv or os.path.isfile(L.NPC_CSV)) else {}
    monster = L.read_monster_rows(mon_csv or L.MONSTER_CSV)
    rows = merged_rows(world, npc, monster)
    hard = other_names(data)
    keep = item_names(data) | hard

    texts = []
    strings = {} if map_only else collect_strings(data)
    for vals in strings.values():
        texts += vals
    path = None
    raw = None
    if not no_map:
        path = map_arg or L.map_path(data)
        if path and os.path.isfile(path):
            raw = open(path, 'rb').read()
            if raw[:2] == b'\x1f\x8b':
                print('%s is compressed; map texts skipped' % path)
                raw = None
            else:
                texts += [v for a, v in map_texts(raw)]
        else:
            print('no map found (DATA_DIR/world/<mapName>.otbm); map texts skipped')
    names = L.known(rows, texts)
    ren = L.Renamer(names, keep=keep, soft=keep - hard)
    titles = L.Renamer(names, keep=keep, soft=keep - hard, titles=True)
    writes = {} if map_only else patch_files(data, ren, titles)
    ren.count += titles.count
    for k, v in titles.by_kind.items():
        ren.by_kind[k] = ren.by_kind.get(k, 0) + v
    file_hits = ren.count
    kinds = dict(ren.by_kind)
    for p in sorted(writes)[:30]:
        print('  %s' % os.path.relpath(p, data))
    if len(writes) > 30:
        print('  ... and %d more' % (len(writes) - 30))
    print('texts: %d old names found in the data (%d world, %d NPC, %d monster rows); %d replacement(s) in %d file(s): %s'
          % (len(names), sum(1 for v in names.values() if v[1] not in ('npc', 'monster')),
             sum(1 for v in names.values() if v[1] == 'npc'), sum(1 for v in names.values() if v[1] == 'monster'),
             file_hits, len(writes), ', '.join('%s %d' % kv for kv in sorted(kinds.items())) or 'none'))
    new_map = None
    if raw is not None:
        try:
            new_map, nodes, unparsed = patch_map(raw, ren)
        except MapError as e:
            print('%s: %s; map not written' % (path, e))
            return 1
        print('map: %d item text(s) rewritten (%d replacement(s))%s'
              % (nodes, ren.count - file_hits, ', %d item node(s) with unknown attributes left alone' % unparsed
                 if unparsed else ''))
    if dry:
        print('dry run: nothing written (%d file(s)%s would change)' % (len(writes), ' and the map' if new_map else ''))
        return 0
    for p, t in writes.items():
        L.write(p, t)
    if new_map is not None:
        if backup and not os.path.exists(path + '.bak'):
            with open(path + '.bak', 'wb') as f:
                f.write(raw)
        tmp = path + '.tmp'
        with open(tmp, 'wb') as f:
            f.write(new_map)
        os.replace(tmp, path)
        print('%s written (%d bytes, was %d)' % (os.path.basename(path), len(new_map), len(raw)))
    print('%d file(s) written' % len(writes))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
