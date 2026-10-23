#!/usr/bin/env python3
"""Give the uniques with an equip rule of their own that rule in a base server (idempotent).

usage: python3 -I install_unique_equip.py DATA_DIR [--dry-run]

A unique is a copy of a stock base item (data/items/README.md), and the engine's equip check (movements.xml: level and
vocations) belongs to the base item id. A unique of data/items/chaos_items.xml with equipLevel / equipLines (the
build archetype uniques of the second round) is meant for other classes or another level than its base item (the
Stillheart Robe's soulmantle needs level 400, the Hollowglass Diadem's eldritch hood refuses the Elementalist), so:

1. data/movements/movements.xml: the stock Equip entry of each such base id is taken out and recorded, and a new
   Equip entry goes between two marker comments before </movements>: the lower of the two levels, both vocation lists
   (no list when either side lets everyone wear it), the stock `function` (onEquipItem: the item's abilities) and
   script="chaos_unique_equip.lua". The unique's classes show in the look text (the base class of each line), the
   stock-only ones are hidden (showInDescription="0"). A base id with no DeEquip entry of its own gets one in the
   block. The recorded stock rule stays in the block as a comment, so a re-run rebuilds the same block. A stock entry
   with a script of its own, two Equip entries or a range entry over the id stop the tool, nothing written.
2. data/movements/scripts/chaos_unique_equip.lua: written from the recorded stock rules. Its onEquip calls
   ChaosUniqueEquip.onEquip (data/lib/chaos_unique_equip.lua): a copy carrying chaos_unique with an `equip` rule in
   its spec (chaos_unique_specs.lua, tools/gen_unique_specs.py) is held to that rule, every other copy to the stock
   rule. The engine refuses with "You cannot dress this object there."

Run after the vocations step (the class names; add_vocations.py leaves this block alone) and after archery (which
also edits movements.xml). server/README.md "Unique equip rules"; tests/unique_equip_test.lua.
"""
import os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from gen_unique_specs import LINES, equip_rule, items  # noqa: E402

REPO_XML = os.path.join(os.path.dirname(HERE), 'data', 'items', 'chaos_items.xml')
BEGIN = '\t<!-- Chaos unique equip rules (server/tools/install_unique_equip.py, do not edit by hand) -->\n'
END = '\t<!-- end of the Chaos unique equip rules -->\n'
SCRIPT = 'chaos_unique_equip.lua'
# items.xml slotType / weaponType -> movements.xml slot, for a base id without a stock Equip entry
SLOT = {'head': 'head', 'body': 'armor', 'legs': 'legs', 'feet': 'feet', 'necklace': 'necklace', 'ring': 'ring',
        'shield': 'shield', 'sword': 'hand', 'axe': 'hand', 'club': 'hand', 'distance': 'hand', 'wand': 'hand'}
STOCK_RE = re.compile(r'\t<!-- stock (\d+): (.*?) -->\n')


def read(path):
    return open(path, encoding='utf-8', errors='surrogateescape', newline='').read()


def write(path, text):
    open(path, 'w', encoding='utf-8', errors='surrogateescape', newline='').write(text)


def unique_rules(xml_text):
    """[{id, name, slot, level, lines, vocations}] of the uniques with an equip rule, in file order"""
    out = []
    for iid, head, attrs in items(xml_text):
        rule = equip_rule(attrs)
        if not rule:
            continue
        kind = attrs.get('slotType') or attrs.get('weaponType') or ''
        out.append({'id': int(iid), 'name': re.search(r'name="([^"]+)"', head).group(1), 'slot': SLOT.get(kind.lower()),
                    'level': rule[0], 'lines': rule[1], 'vocations': rule[2]})
    return out


def equip_entries(text, iid):
    pat = (r'[ \t]*<movevent\s+event="Equip"\s[^>]*?\bitemid="%d"[^>]*?(?:/>|[^/]>.*?</movevent>)[ \t]*\r?\n?' % iid)
    return list(re.finditer(pat, text, re.S))


def parse_stock(entry):
    """the rule of a stock Equip entry: {slot, level, vocations (None = everyone)}"""
    head = re.match(r'\s*<movevent\b[^>]*', entry, re.S).group(0)
    if re.search(r'\bscript\s*=', head):
        raise SystemExit('movements.xml: the Equip entry of %s has a script of its own; nothing written'
                         % re.search(r'itemid="(\d+)"', head).group(1))
    slot = re.search(r'\bslot\s*=\s*"([^"]+)"', head)
    level = re.search(r'\blevel\s*=\s*"(\d+)"', head)
    voc = re.findall(r'<vocation\s+name="([^"]+)"', entry)
    return {'slot': slot.group(1) if slot else None, 'level': int(level.group(1)) if level else 0,
            'vocations': voc or None}


def stock_comment(iid, st):
    if st is None:
        return '\t<!-- stock %d: none -->\n' % iid
    return '\t<!-- stock %d: slot="%s" level="%d" vocations="%s" -->\n' % (
        iid, st['slot'] or '', st['level'], '|'.join(st['vocations']) if st['vocations'] else '*')


def parse_comment(body):
    if body == 'none':
        return None
    d = dict(re.findall(r'(\w+)="([^"]*)"', body))
    return {'slot': d.get('slot') or None, 'level': int(d.get('level', '0')),
            'vocations': None if d.get('vocations', '*') == '*' else d['vocations'].split('|')}


def block_entry(u, st, deequip):
    slot = (st and st['slot']) or u['slot']
    if not slot:
        raise SystemExit('movements.xml: no slot known for %s (%d)' % (u['name'], u['id']))
    level = min(st['level'], u['level']) if st else 0
    head = '\t<movevent event="Equip" itemid="%d" slot="%s"%s function="onEquipItem" script="%s"' % (
        u['id'], slot, ' level="%d"' % level if level > 0 else '', SCRIPT)
    out = ''
    if st is not None and st['vocations'] is not None and u['vocations']:
        shown = {line for line in u['lines']}
        names = list(u['vocations']) + [v for v in st['vocations'] if v not in u['vocations']]
        body = ''.join('\t\t<vocation name="%s"%s />\n' % (v, '' if v in shown else ' showInDescription="0"')
                       for v in names)
        out += head + '>\n' + body + '\t</movevent>\n'
    else:
        out += head + ' />\n'
    if deequip:
        out += '\t<movevent event="DeEquip" itemid="%d" slot="%s" function="onDeEquipItem" />\n' % (u['id'], slot)
    return out


def patch_moves(text, rules):
    """returns (new text, stock rules {id: rule or None}, notes)"""
    mark = '\x00chaos unique equip block\x00'
    s = text.find(BEGIN)
    recorded = {}
    if s >= 0:
        e = text.find(END, s)
        if e < 0:
            raise SystemExit('movements.xml: start marker without end marker')
        for iid, body in STOCK_RE.findall(text[s:e]):
            recorded[int(iid)] = parse_comment(body)
        outside = text[:s] + mark + text[e + len(END):]
    else:
        at = text.rfind('</movements>')
        if at < 0:
            raise SystemExit('movements.xml: no </movements>')
        outside = text[:at] + mark + text[at:]
    stock, notes, parts = {}, [], []
    for u in rules:
        iid = u['id']
        for a, b in re.findall(r'fromid="(\d+)"\s+toid="(\d+)"', outside):
            if int(a) <= iid <= int(b):
                raise SystemExit('movements.xml: %d is inside a range entry; nothing written' % iid)
        found = equip_entries(outside, iid)
        if len(found) > 1:
            raise SystemExit('movements.xml: %d has %d Equip entries; nothing written' % (iid, len(found)))
        if found:
            st = parse_stock(found[0].group(0))
            outside = outside[:found[0].start()] + outside[found[0].end():]
            notes.append('movements.xml: %s (%d): stock Equip entry taken in (level %d, %s)' % (
                u['name'], iid, st['level'], ', '.join(st['vocations']) if st['vocations'] else 'everyone'))
        elif iid in recorded:
            st = recorded[iid]
        else:
            st = None
        stock[iid] = st
        deequip = re.search(r'<movevent\s+event="DeEquip"\s[^>]*?\bitemid="%d"' % iid, outside) is None
        parts.append(stock_comment(iid, st) + block_entry(u, st, deequip))
    new = outside.replace(mark, BEGIN + ''.join(parts) + END)
    if new == text:
        return text, stock, notes + ['movements.xml: unique equip block up to date']
    return new, stock, notes + ['movements.xml: unique equip block %s' % ('rewritten' if s >= 0 else 'added')]


def lua_value(st):
    if st is None:
        return '{}'
    voc = ('{%s}' % ', '.join('"%s"' % v for v in st['vocations'])) if st['vocations'] else 'nil'
    return '{level = %d, vocations = %s}' % (st['level'], voc)


def script_text(rules, stock):
    L = ['-- GENERATED by server/tools/install_unique_equip.py; a re-run rewrites it, do not edit by hand.',
         '-- The stock equip rules of base items that are also uniques with an equip rule of their own (server/README.md',
         '-- "Unique equip rules"). movements.xml checks the looser rule; ChaosUniqueEquip.onEquip holds a unique copy to',
         '-- its spec\'s rule (data/lib/chaos_unique_specs.lua `equip`) and every other copy to the rule below',
         '-- ({} = anyone; vocations nil = every class).',
         'if not ChaosUniqueEquip then',
         '\tdofile("data/lib/chaos_unique_equip.lua")',
         'end',
         '',
         'local STOCK = {']
    for u in rules:
        L.append('\t[%d] = %s, -- %s' % (u['id'], lua_value(stock[u['id']]), u['name']))
    L += ['}', '',
          'function onEquip(player, item, slot, isCheck)',
          '\treturn ChaosUniqueEquip.onEquip(player, item, slot, isCheck, STOCK)',
          'end', '']
    return '\n'.join(L)


def main():
    args = sys.argv[1:]
    dry = '--dry-run' in args
    args = [a for a in args if not a.startswith('--')]
    if len(args) != 1:
        print(__doc__)
        return 1
    data_dir = args[0]
    moves = os.path.join(data_dir, 'movements', 'movements.xml')
    if not os.path.exists(moves):
        print('not found:', moves)
        return 1
    rules = unique_rules(read(REPO_XML))
    text = read(moves)
    new, stock, notes = patch_moves(text, rules)
    for n in notes:
        print(n)
    script_path = os.path.join(data_dir, 'movements', 'scripts', SCRIPT)
    script = script_text(rules, stock)
    old_script = read(script_path) if os.path.exists(script_path) else None
    print('movements/scripts/%s: %s' % (SCRIPT, 'up to date' if old_script == script else 'written'))
    if dry:
        print('dry run: nothing written')
        return 0
    if new != text:
        write(moves, new)
    if old_script != script:
        os.makedirs(os.path.dirname(script_path), exist_ok=True)
        write(script_path, script)
    return 0


if __name__ == '__main__':
    sys.exit(main())
