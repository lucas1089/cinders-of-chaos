#!/usr/bin/env python3
"""Give every stock player spell (and its rune item) the Chaos name from server/data/spells/spell_names.csv.

usage: python3 -I rename_spells.py DATA_DIR [--sql OUT.sql] [--dry-run]

DATA_DIR is the base server's data folder. Rewrites, in place and idempotently (a second run changes nothing):
  spells/spells.xml       name="" of <instant>/<rune>/<conjure>, and words="" translated part by part with
                          spell_words.csv (monster and house spells and the chaos block are left alone)
  items/items.xml         name="" (lower case) and article of the rune items listed in the csv
  monster/**/*.xml        <attack>/<defense> spells that use a player spell, <item> loot of renamed runes
  monster/**/*.lua        {name = "..."} / {id = "..."} entries naming a renamed spell or rune
  npc/scripts/**/*.lua    spellName = '...' of the spell teachers
  npc/**/*.xml            shop lists ("Old Name,itemid,price")
--sql writes the UPDATEs for player_spells (spells players already learned); run it once against the game database.
It also deletes the player_spells rows of the retired spells kept for monsters only (words "###chaos ...",
monster_spells.py): learned, such a spell would stay castable.
Anything else in DATA_DIR still quoting an old name is listed at the end, so it can be checked.
"""
import csv, glob, os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
CSV = os.path.join(HERE, '..', 'data', 'spells', 'spell_names.csv')
CHAOS_BEGIN = '<!-- BEGIN chaos spells'
CHAOS_END = '<!-- END chaos spells -->'


WORDS_CSV = os.path.join(HERE, '..', 'data', 'spells', 'spell_words.csv')


def load():
    rows = list(csv.DictReader(open(CSV, encoding='utf-8')))
    names = {r['old_name']: r['new_name'] for r in rows}
    runes = {int(r['rune_item']): r['new_name'] for r in rows if r['rune_item']}
    return rows, names, runes


def load_words():
    """word part -> Chaos word part (spell_words.csv)"""
    return {r['old']: r['new'] for r in csv.DictReader(open(WORDS_CSV, encoding='utf-8'))}


def translate_words(words, parts):
    """the Chaos incantation, or None when a part is unknown (monster, house and already translated words)"""
    tokens = words.split()
    if not tokens or not all(t in parts for t in tokens):
        return None
    return ' '.join(parts[t] for t in tokens)


def keep_case(old_text, new_name):
    return new_name.lower() if old_text == old_text.lower() else new_name


def sub_attr(tag_text, attr, value):
    return re.sub(r'(\b%s=")[^"]*(")' % attr, lambda m: m.group(1) + value + m.group(2), tag_text, count=1)


def rename_spells_xml(path, names, parts):
    s = open(path, encoding='utf-8', errors='surrogateescape').read()
    head, sep, rest = s.partition(CHAOS_BEGIN)
    count = 0

    def tag(m):
        nonlocal count
        t = m.group(0)
        name = re.search(r'\bname="([^"]*)"', t)
        if name and name.group(1) in names:
            count += 1
            t = sub_attr(t, 'name', names[name.group(1)])
        words = re.search(r'\bwords="([^"]*)"', t)
        script = re.search(r'\bscript="([^"]*)"', t)
        if words and not (script and script.group(1).startswith(('house/', 'monster/'))):
            new = translate_words(words.group(1), parts)
            if new:
                count += 1
                t = sub_attr(t, 'words', new)
        return t
    head = re.sub(r'<(?:instant|rune|conjure)\b[^>]*>', tag, head)
    tail = ''
    if sep:
        block, sep2, tail_rest = rest.partition(CHAOS_END)
        rest_after = re.sub(r'<(?:instant|rune|conjure)\b[^>]*>', tag, tail_rest)
        tail = sep + block + sep2 + rest_after
    return head + tail, count


def rename_items_xml(path, runes, rune_names):
    """rune items by id (from the <rune> spells) and every other item carrying an old rune name (blank rune, variants)"""
    s = open(path, encoding='utf-8', errors='surrogateescape').read()
    by_name = {k.lower(): v for k, v in rune_names.items()}
    count = 0

    def tag(m):
        nonlocal count
        iid = int(m.group(1))
        name = re.search(r'\bname="([^"]*)"', m.group(0))
        new = runes.get(iid) or (name and by_name.get(name.group(1).lower()))
        if not new:
            return m.group(0)
        new = new.lower()
        t = sub_attr(m.group(0), 'name', new)
        if 'article="' in t:
            t = sub_attr(t, 'article', 'an' if new[0] in 'aeiou' else 'a')
        if t != m.group(0):
            count += 1
        return t
    return re.sub(r'<item\s+id="(\d+)"[^>]*>', tag, s), count


def rename_quoted(s, mapping, pattern):
    """pattern: regex with groups (prefix)(name)(suffix); name matched case-insensitively against mapping."""
    lower = {k.lower(): v for k, v in mapping.items()}
    count = 0

    def rep(m):
        nonlocal count
        old = m.group(2)
        new = lower.get(old.lower())
        if new is None:
            return m.group(0)
        count += 1
        return m.group(1) + keep_case(old, new) + m.group(3)
    return re.sub(pattern, rep, s), count


SPELLNAME_RX = re.compile(r'''(\bspellName\s*=\s*)(['"])((?:\\.|(?!\2)[^\\\n])*)\2''')


def rename_npc_lua(s, names):
    """spellName = '...' / "..." of the spell teachers. Lua escapes count (a stock 'Apprentice\\'s Strike' is found)
    and a new name is written with its quote escaped ('Warlord\\'s Resolve'). Older versions of this tool wrote it
    unescaped, which broke the whole script (Ormuhn, Puffels, Thorwulf, Tristan, Uso, Zarak did not load): such a
    line is repaired first. Returns (text, number of changes)."""
    count = 0
    for new in sorted(set(names.values())):
        if "'" not in new:
            continue
        bad = re.compile(r"(\bspellName\s*=\s*)'(%s)'" % re.escape(new), re.I)
        s, n = bad.subn(lambda m: m.group(1) + "'" + m.group(2).replace("'", "\\'") + "'", s)
        count += n
    lower = {k.lower(): v for k, v in names.items()}

    def rep(m):
        nonlocal count
        q, raw = m.group(2), m.group(3)
        old = re.sub(r'\\(.)', r'\1', raw)
        new = lower.get(old.lower())
        if new is None:
            return m.group(0)
        count += 1
        return m.group(1) + q + keep_case(old, new).replace('\\', '\\\\').replace(q, '\\' + q) + q
    return SPELLNAME_RX.sub(rep, s), count


def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    dry = '--dry-run' in sys.argv
    sql_out = None
    if '--sql' in sys.argv:
        sql_out = sys.argv[sys.argv.index('--sql') + 1]
        args = [a for a in args if a != sql_out]
    if len(args) != 1:
        print(__doc__)
        return 1
    data = args[0]
    rows, names, runes = load()
    rune_names = {r['old_name']: r['new_name'] for r in rows if r['old_name'].endswith(' Rune')}
    changes = {}

    def write(path, text, n):
        if n:
            changes[os.path.relpath(path, data)] = n
            if not dry:
                open(path, 'w', encoding='utf-8', errors='surrogateescape').write(text)

    p = os.path.join(data, 'spells', 'spells.xml')
    write(p, *rename_spells_xml(p, names, load_words()))
    p = os.path.join(data, 'items', 'items.xml')
    if os.path.exists(p):
        write(p, *rename_items_xml(p, runes, rune_names))

    for path in glob.glob(os.path.join(data, 'monster', '**', '*.xml'), recursive=True):
        s = open(path, encoding='utf-8', errors='surrogateescape').read()
        s2, n1 = rename_quoted(s, names, r'(<(?:attack|defense)\b[^>]*?\bname=")([^"]+)(")')
        s2, n2 = rename_quoted(s2, rune_names, r'(<item\b[^>]*?\bname=")([^"]+)(")')
        write(path, s2, n1 + n2)
    for path in glob.glob(os.path.join(data, 'monster', '**', '*.lua'), recursive=True):
        s = open(path, encoding='utf-8', errors='surrogateescape').read()
        write(path, *rename_quoted(s, names, r'(\b(?:name|id)\s*=\s*")([^"]+)(")'))
    for path in glob.glob(os.path.join(data, 'npc', '**', '*.lua'), recursive=True):
        s = open(path, encoding='utf-8', errors='surrogateescape').read()
        write(path, *rename_npc_lua(s, names))
    for path in glob.glob(os.path.join(data, 'npc', '**', '*.xml'), recursive=True):
        s = open(path, encoding='utf-8', errors='surrogateescape').read()
        write(path, *rename_quoted(s, rune_names, r'((?:^|[;"\s]))([A-Za-z\' ]+?)(,\d+,)'))

    if sql_out:
        with open(sql_out, 'w', encoding='utf-8') as f:
            f.write('-- learned spells keep working after tools/rename_spells.py\n')
            for old, new in names.items():
                f.write("UPDATE player_spells SET name = '%s' WHERE name = '%s';\n"
                        % (new.replace("'", "''"), old.replace("'", "''")))
            # retired spells kept for the monsters only (monster_spells.py): needlearn="1" without vocations, so a
            # learned row would be the one way a player could still cast one; nobody keeps it learned
            sp = os.path.join(data, 'spells', 'spells.xml')
            body = re.sub(r'<!--.*?-->', '', open(sp, encoding='utf-8', errors='surrogateescape').read(), flags=re.S) \
                if os.path.isfile(sp) else ''
            for m in re.finditer(r'<instant\b[^>]*>', body):
                name = re.search(r'\bname="([^"]*)"', m.group(0))
                if name and re.search(r'\bwords="###chaos ', m.group(0)):
                    f.write("DELETE FROM player_spells WHERE name = '%s';\n" % name.group(1).replace("'", "''"))

    total = sum(changes.values())
    for path, n in sorted(changes.items()):
        print(f'{n:5d}  {path}')
    print(f'{total} names and words {"would be " if dry else ""}changed in {len(changes)} files')

    # leftovers: an old name quoted anywhere else in data (scripts, quests, raids...)
    olds = sorted(names, key=len, reverse=True)
    rx = re.compile(r'''["'](%s)["']''' % '|'.join(re.escape(o) for o in olds), re.I)
    seen = 0
    for path in [] if dry else glob.glob(os.path.join(data, '**', '*.*'), recursive=True):
        if not path.endswith(('.lua', '.xml')) or os.sep + 'monster' + os.sep in path:
            continue
        try:
            s = open(path, encoding='utf-8', errors='surrogateescape').read()
        except (IsADirectoryError, PermissionError):
            continue
        for m in rx.finditer(s):
            if seen < 40:
                line = s.count('\n', 0, m.start()) + 1
                print(f'  check: {os.path.relpath(path, data)}:{line}: {m.group(0)}')
            seen += 1
    if seen:
        print(f'{seen} other quoted old names (first 40 listed); they may be item names or plain text')
    return 0


if __name__ == '__main__':
    sys.exit(main())
