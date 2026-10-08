#!/usr/bin/env python3
"""Add the Chaos vocations (the Thief line: Thief, Ninja, Samurai) to a base server data folder (idempotent).

usage: python3 -I add_vocations.py DATA_DIR [--dry-run]

1. data/XML/vocations.xml: inserts the entries of server/data/XML/chaos_vocations.xml (the reviewable table: ids,
   gains, attack speed, skills) between "BEGIN chaos vocations" / "END chaos vocations" markers before </vocations>.
   Re-running replaces that block. Stops with an error, changing nothing, when an id or a name of the table is
   already used by an entry outside the block.
2. data/weapons/weapons.xml: the Thief line may wield what it is built for. Weapon entries that list vocations get
   Thief, Ninja and Samurai when the item is a one-handed sword (daggers and light swords; items.xml weaponType
   "sword", not two-handed) or a throwing weapon (weaponType "distance" without ammoType: throwing stars, assassin
   stars, knives, spears). Entries without a vocation list are open to every vocation already and are left alone.
3. data/movements/movements.xml: Equip events that list vocations get the three as well when
   - the slot is not a hand and the Paladin may wear it (light armour, the Thief wears what the Paladin wears), or
   - the slot is a hand and the item is a one-handed sword or a throwing weapon (as in 2).

The engine adds a promoted vocation to a list by itself only for the first vocation that names the base one as its
fromvoc, so all three names are written out. Ninja and Samurai lines carry showInDescription="0", like the base
server writes its promoted vocations. Every added line carries no marker; a list that names "Thief" already is left
as it is, so the tool can run any number of times.
"""
import os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
TABLE = os.path.join(HERE, '..', 'data', 'XML', 'chaos_vocations.xml')
BEGIN = '<!-- BEGIN chaos vocations (server/tools/add_vocations.py) -->'
END = '<!-- END chaos vocations -->'
LINE = ['Thief', 'Ninja', 'Samurai']


def read(path):
    return open(path, encoding='utf-8', errors='surrogateescape').read()


def write(path, text):
    open(path, 'w', encoding='utf-8', errors='surrogateescape').write(text)


def table_entries():
    """the <vocation> elements of the table, as text, and their (id, name) pairs"""
    t = read(TABLE)
    t = re.sub(r'<!--.*?-->', '', t, flags=re.S)
    entries = re.findall(r'[ \t]*<vocation\s.*?</vocation>', t, re.S)
    ids = [(re.search(r'\bid="(\d+)"', e).group(1), re.search(r'\bname="([^"]+)"', e).group(1)) for e in entries]
    return entries, ids


def patch_vocations(text, entries, ids):
    """returns (new text, status)"""
    outside = re.sub(r'[ \t]*' + re.escape(BEGIN) + r'.*?' + re.escape(END) + r'\n?', '', text, flags=re.S)
    for vid, name in ids:
        for m in re.finditer(r'<vocation\s[^>]*>', outside):
            tag = m.group(0)
            if re.search(r'\bid="%s"' % vid, tag) or re.search(r'\bname="%s"' % re.escape(name), tag, re.I):
                return text, 'vocation id %s or name %s is already used: %s' % (vid, name, tag[:80])
    if '</vocations>' not in outside:
        return text, '</vocations> not found'
    block = '\t' + BEGIN + '\n' + '\n'.join(e.rstrip() for e in entries) + '\n\t' + END + '\n'
    new = outside.replace('</vocations>', block + '</vocations>', 1)
    return new, ('already' if new == text else 'patched')


def item_kinds(items_xml):
    """item id -> 'sword1h' | 'throwing' for the items the Thief line may wield"""
    kinds = {}
    for m in re.finditer(r'<item\s([^>]*?)(?:/>|>(.*?)</item>)', items_xml, re.S):
        head, body = m.group(1), m.group(2) or ''
        wt = re.search(r'key="weaponType"\s+value="([^"]+)"', body, re.I)
        if not wt:
            continue
        wt = wt.group(1).lower()
        two = re.search(r'key="slotType"\s+value="two-handed"', body, re.I)
        kind = None
        if wt == 'sword' and not two:
            kind = 'sword1h'
        elif wt == 'distance' and not re.search(r'key="ammoType"', body, re.I):
            kind = 'throwing'
        if not kind:
            continue
        ids = []
        one = re.search(r'\bid="(\d+)"', head)
        if one:
            ids = [int(one.group(1))]
        else:
            fr, to = re.search(r'\bfromid="(\d+)"', head), re.search(r'\btoid="(\d+)"', head)
            if fr and to:
                ids = list(range(int(fr.group(1)), int(to.group(1)) + 1))
        for i in ids:
            kinds[i] = kind
    return kinds


def add_lines(element):
    """append the Thief line to the <vocation> list of one XML element (text), keeping its indentation"""
    if re.search(r'<vocation\s+name="Thief"', element):
        return element
    last = list(re.finditer(r'\n([ \t]*)<vocation\s[^>]*/>', element))
    if not last:
        return element
    indent = last[-1].group(1)
    at = last[-1].end()
    lines = ''.join('\n%s<vocation name="%s"%s />' % (indent, v, '' if v == 'Thief' else ' showInDescription="0"')
                    for v in LINE)
    return element[:at] + lines + element[at:]


def ids_of(tag):
    """item ids an XML tag covers: id / itemid, or fromid..toid"""
    one = re.search(r'\b(?:id|itemid)="(\d+)"', tag)
    if one:
        return [int(one.group(1))]
    fr, to = re.search(r'\bfromid="(\d+)"', tag), re.search(r'\btoid="(\d+)"', tag)
    if fr and to:
        return list(range(int(fr.group(1)), int(to.group(1)) + 1))
    return []


def patch_weapons(text, kinds):
    count = [0]

    def repl(m):
        el = m.group(0)
        if '<vocation' not in el or not any(kinds.get(i) for i in ids_of(m.group(2))):
            return el
        new = add_lines(el)
        if new != el:
            count[0] += 1
        return new
    new = re.sub(r'<(melee|distance)\s([^>]*[^/])>.*?</\1>', repl, text, flags=re.S)
    return new, count[0]


def patch_movements(text, kinds):
    count = [0]

    def repl(m):
        el, tag = m.group(0), m.group(1)
        if '<vocation' not in el:
            return el
        slot = re.search(r'\bslot="([^"]+)"', tag)
        slot = slot.group(1).lower() if slot else ''
        if slot == 'hand':
            ok = any(kinds.get(i) for i in ids_of(tag))
        else:
            ok = re.search(r'<vocation\s+name="Paladin"', el) is not None
        if not ok:
            return el
        new = add_lines(el)
        if new != el:
            count[0] += 1
        return new
    new = re.sub(r'<movevent\s+event="Equip"([^>]*[^/])>.*?</movevent>', repl, text, flags=re.S)
    return new, count[0]


def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    dry = '--dry-run' in sys.argv
    if len(args) != 1:
        print(__doc__)
        sys.exit(2)
    data = args[0]
    paths = {k: os.path.join(data, *p) for k, p in {
        'voc': ('XML', 'vocations.xml'), 'items': ('items', 'items.xml'),
        'weapons': ('weapons', 'weapons.xml'), 'moves': ('movements', 'movements.xml')}.items()}
    for k, p in paths.items():
        if not os.path.exists(p):
            print('missing', p)
            sys.exit(1)
    entries, ids = table_entries()
    voc, status = patch_vocations(read(paths['voc']), entries, ids)
    if status not in ('patched', 'already'):
        print('vocations.xml:', status, '- nothing changed')
        sys.exit(1)
    kinds = item_kinds(read(paths['items']))
    weapons, nw = patch_weapons(read(paths['weapons']), kinds)
    moves, nm = patch_movements(read(paths['moves']), kinds)
    print('vocations.xml: %s (%s)' % (status, ', '.join('%s %s' % i for i in ids)))
    print('weapons.xml: %d weapon entries get the Thief line' % nw)
    print('movements.xml: %d equip entries get the Thief line' % nm)
    if dry:
        print('dry run: nothing written')
        return
    if status == 'patched':
        write(paths['voc'], voc)
    if nw:
        write(paths['weapons'], weapons)
    if nm:
        write(paths['moves'], moves)


if __name__ == '__main__':
    main()
