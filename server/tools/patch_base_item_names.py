#!/usr/bin/env python3
"""Give some base items Cinders of Chaos names, keyed by item id (server/README.md "Base item names").

usage: python3 -I patch_base_item_names.py DATA_DIR [--names CSV] [--dry-run]

The new names come from server/data/items/base_item_names.csv (columns id, article, name, plural; an empty article or
plural removes that attribute; several ids may share a new name only when items.xml gives them the same old name,
else the tool stops before writing anything). Only ids and new names are in the repository; the old names are read from the server's
own items.xml at install time.

1. data/items/items.xml: the entry of each id (one `<item id="N" ...>` line, or a `<item fromid="N" toid="M" ...>` range
   whose fromid is N; an id that is only inside a range is left alone and listed) gets the new name, article and plural.
2. The loot of the base monsters refers to items by id or by name. Every loot entry that names a renamed item by its old
   name is changed to its id: `id = "old name"` in monster Lua files, `<item name="old name" .../>` in monster XML. Loot
   by id needs nothing.
3. Every other mention of an old name in the base data (NPC shop lists, quest and reward texts, scripts; not
   data/scripts/chaos, not data/lib/chaos_*.lua, not data/items) is replaced, case-insensitively and whole words only;
   an all-lower-case mention gets the new name in lower case. In Lua files only string literals change, and a new
   name with an apostrophe is escaped for the quote style of its string; in XML files only attribute values, and
   paths (script="dir/name.lua") stay.

The engine finds items by name case-insensitively, so without steps 2 and 3 a monster or shop that names a renamed item
would fail to load it. Run it on the same data folder each time: an old name is only known while items.xml still has
it, so steps 2 and 3 work on the run that renames the entry.

Idempotent: a second run changes nothing. --dry-run writes nothing.
"""
import csv
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import base_rename_lib as RL  # noqa: E402
CSV_PATH = os.path.join(os.path.dirname(HERE), 'data', 'items', 'base_item_names.csv')
REF_DIRS = ('monster', 'npc', 'scripts', 'talkactions', 'actions', 'creaturescripts', 'globalevents', 'movements',
            'lib', 'events', 'raids', 'weapons', 'XML', 'spells')
SKIP_DIRS = (os.path.join('scripts', 'chaos'), 'items', 'patchnotes', os.path.join('monster', 'monsters', 'chaos'),
             os.path.join('monster', 'lua', 'chaos'))


def read_names(path=CSV_PATH):
    rows = {}
    with open(path, encoding='utf-8', newline='') as f:
        for row in csv.DictReader(f):
            iid = (row.get('id') or '').strip()
            if not iid or iid.startswith('#'):
                continue
            name = (row.get('name') or '').strip()
            if not iid.isdigit() or not name or '"' in name or '<' in name or '&' in name:
                raise SystemExit('%s: bad row %r' % (path, row))
            if int(iid) in rows:
                raise SystemExit('%s: id %s twice' % (path, iid))
            rows[int(iid)] = {'name': name, 'article': (row.get('article') or '').strip(),
                              'plural': (row.get('plural') or '').strip()}
    return rows


def check_shared_names(text, rows):
    """two CSV rows may share a new name only when items.xml gave both ids the same old name (one item kind with
    several ids, such as a corpse in two looks) or already has the new name; anything else stops the tool"""
    old = {}
    for m in re.finditer(r'<item\s+(?:id="(\d+)"|fromid="(\d+)")[^>]*?\sname="([^"]*)"', text):
        old.setdefault(int(m.group(1) or m.group(2)), m.group(3).lower())
    by_new = {}
    for iid, r in rows.items():
        by_new.setdefault(r['name'].lower(), set()).add(iid)
    bad = []
    for new, ids in sorted(by_new.items()):
        if len(ids) < 2:
            continue
        olds = {old.get(i, new) for i in ids} - {new}
        if len(olds) > 1:
            bad.append('%s (ids %s)' % (new, ', '.join(map(str, sorted(ids)))))
    if bad:
        raise SystemExit('two items of different old names would get the same new name: ' + '; '.join(bad))


# ------------------------------------------------------------------------------------------------ items.xml
def _set(attrs, key, value):
    m = re.search(r'\s%s="[^"]*"' % key, attrs)
    if value:
        part = ' %s="%s"' % (key, value)
        if m:
            return attrs[:m.start()] + part + attrs[m.end():]
        if key == 'article':  # before the name, as the base file writes it
            n = re.search(r'\sname="', attrs)
            if n:
                return attrs[:n.start()] + part + attrs[n.start():]
        return attrs + part
    return attrs[:m.start()] + attrs[m.end():] if m else attrs


def patch_items(text, rows):
    """-> (new text, {old name lower: (id, new name)} of the entries renamed now, notes)"""
    renamed, notes = {}, []
    all_names = {}
    entry = re.compile(r'<item\s+(?:id="(\d+)"|fromid="(\d+)"(\s+toid="\d+")?)([^>]*?)(/?)>')
    for m in entry.finditer(text):
        n = re.search(r'\sname="([^"]*)"', m.group(4))
        if n:
            all_names.setdefault(n.group(1).lower(), set()).add(int(m.group(1) or m.group(2)))
    seen = set()

    def sub(m):
        iid = int(m.group(1) or m.group(2))
        r = rows.get(iid)
        if r is None or iid in seen:
            return m.group(0)
        seen.add(iid)
        attrs = m.group(4)
        old = re.search(r'\sname="([^"]*)"', attrs)
        old = old.group(1) if old else ''
        new = _set(_set(_set(attrs, 'name', r['name']), 'article', r['article']), 'plural', r['plural'])
        if new == attrs:
            return m.group(0)
        if old and old.lower() != r['name'].lower():
            others = sorted(i for i in all_names.get(old.lower(), set()) - {iid}
                            if rows.get(i, {}).get('name', '').lower() != r['name'].lower())
            if others:
                notes.append('items.xml: %d shares its old name with %s; references by that name now mean %d'
                             % (iid, ', '.join(map(str, others)), iid))
            renamed.setdefault(old.lower(), (iid, r['name']))
        notes.append('items.xml: %d is now "%s"' % (iid, r['name']))
        return m.group(0)[:m.start(4) - m.start(0)] + new + m.group(0)[m.end(4) - m.start(0):]
    text = entry.sub(sub, text)
    for iid in sorted(set(rows) - seen):
        notes.append('items.xml: %d has no entry of its own (left alone)' % iid)
    taken = {}
    for m in entry.finditer(text):
        n = re.search(r'\sname="([^"]*)"', m.group(4))
        if n:
            taken.setdefault(n.group(1).lower(), set()).add(int(m.group(1) or m.group(2)))
    for iid, r in rows.items():
        clash = sorted(taken.get(r['name'].lower(), set()) - {iid})
        if clash and any(rows.get(c, {}).get('name', '').lower() != r['name'].lower() for c in clash):
            notes.append('items.xml: the new name of %d is also the name of %s' % (iid, ', '.join(map(str, clash))))
    return text, renamed, notes


# ------------------------------------------------------------------------------------------------ references
_WORDS = {}


def _word(old):
    rx = _WORDS.get(old)
    if rx is None:
        rx = _WORDS[old] = re.compile(r'(?<![A-Za-z0-9])%s(?![A-Za-z0-9])' % re.escape(old), re.I)
    return rx


def patch_monster_lua(text, renamed):
    n = [0]

    def sub(m):
        iid = renamed.get(m.group(3).lower())
        if not iid:
            return m.group(0)
        n[0] += 1
        return '%s%d' % (m.group(1), iid[0])
    out = re.sub(r'(\bid\s*=\s*)(["\'])([^"\'\n]*)\2', sub, text)
    return out, n[0]


def patch_monster_xml(text, renamed):
    n = [0]

    def sub(m):
        iid = renamed.get(m.group(2).lower())
        if not iid:
            return m.group(0)
        n[0] += 1
        return '%sid="%d"' % (m.group(1), iid[0])
    out = re.sub(r'(<item\b[^>]*?\s)name="([^"]*)"', sub, text)
    return out, n[0]


def longer_names(renamed, names):
    """{old name: [other item names that contain it as whole words]}: those mentions are other items and stay"""
    out = {}
    for old in renamed:
        rx = _word(old)
        out[old] = sorted((n for n in names if n != old and old in n and rx.search(n)), key=len, reverse=True)
    return out


def patch_text(text, renamed, longer=None):
    n = 0
    longer = longer or {}
    low = text.lower()
    for old in sorted(renamed, key=len, reverse=True):
        if old not in low:
            continue
        new = renamed[old][1]
        keep = []

        def hide(m):
            keep.append(m.group(0))
            return '\x00%d\x00' % (len(keep) - 1)
        for other in longer.get(old, []):
            text = _word(other).sub(hide, text)

        def sub(m, new=new):
            return new.lower() if m.group(0) == m.group(0).lower() else new
        text, k = _word(old).subn(sub, text)
        n += k
        if keep:
            text = re.sub('\x00(\\d+)\x00', lambda m: keep[int(m.group(1))], text)
        low = text.lower()
    return text, n


def ref_files(data):
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
                yield os.path.join(dirpath, f)


def patch_references(data, renamed, names=()):
    """-> {path: new text}, loot changes, text changes; names: every item name of items.xml (lower case)"""
    writes, loot, words = {}, 0, 0
    if not renamed:
        return writes, 0, 0
    longer = longer_names(renamed, set(names))
    monster = os.path.join(data, 'monster') + os.sep
    for p in ref_files(data):
        t = read(p)
        new, k = t, 0
        if p.startswith(monster):
            new, k = (patch_monster_lua if p.endswith('.lua') else patch_monster_xml)(new, renamed)
        if p.endswith('.lua'):
            # inside string literals only, escaped for their quote style (a new name may have an apostrophe)
            n = [0]

            def fn(value):
                v, c = patch_text(value, renamed, longer)
                n[0] += c
                return v
            new, w = RL.patch_lua(new, fn), 0
            w = n[0]
        else:
            # attribute values only; paths (script="dir/name.lua") stay
            n = [0]

            def fx(value):
                v, c = patch_text(value, renamed, longer)
                n[0] += c
                return v
            new = RL.patch_xml(new, fx)
            w = n[0]
        if new != t:
            writes[p] = new
            loot += k
            words += w
    return writes, loot, words


# ------------------------------------------------------------------------------------------------ files
def read(path):
    with open(path, encoding='utf-8', errors='surrogateescape', newline='') as f:
        return f.read()


def write(path, text):
    with open(path, 'w', encoding='utf-8', errors='surrogateescape', newline='') as f:
        f.write(text)


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
    xml = os.path.join(data, 'items', 'items.xml')
    if not os.path.isfile(xml):
        print('not found:', xml)
        return 1
    rows = read_names(names)
    text = read(xml)
    check_shared_names(text, rows)
    new_xml, renamed, notes = patch_items(text, rows)
    for n in notes:
        print(n)
    names = {m.lower() for m in re.findall(r'<item\s[^>]*?\sname="([^"]*)"', text)}
    writes, loot, words = patch_references(data, renamed, names)
    if new_xml != text:
        writes[xml] = new_xml
    for p in sorted(writes):
        if p != xml:
            print('  %s' % os.path.relpath(p, data))
    done = sum(1 for n in notes if n.endswith('"') and ' is now "' in n)
    print('items: %d renamed now (%d old names), %d of %d already named; loot by old name -> id: %d; other mentions: %d'
          % (done, len(renamed), len(rows) - done, len(rows), loot, words))
    if dry:
        print('dry run: nothing written (%d file(s) would change)' % len(writes))
        return 0
    for p, t in writes.items():
        write(p, t)
    print('%d file(s) written' % len(writes))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
