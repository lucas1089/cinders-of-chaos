#!/usr/bin/env python3
"""Install the items of client/tools/sprites/import_art_things.py into a base server: items.otb, items.xml, a shop list.

usage: python3 -I install_pack_items.py DATA_DIR [--dry-run] [--manifest CSV]
       python3 -I install_pack_items.py --lua [--manifest CSV]     (rewrites server/data/lib/chaos_pack_items.lua)

The manifest (default server/data/items/art_items.csv) is written by import_art_things.py (--manifest-out): client id,
server id, key, kind, mode, name, otb group / flags / top order, ground speed, light and extra data (plural, weight,
description, sell price, food, race). Client ids from 33000 (the importer runs with --first-item 33000), server id =
client id + 3000 (36000..; the base items.otb uses up to 29926, dark tiles 30484.., gems 32001.., donor items 40000..).
Without the matching client pair the items show as nothing in the client, so install both.

1. data/items/items.otb
   - mode=new: one node per row (same node layout as install_dark_tiles.py), appended at the end of the root. A node
     already there with the same bytes is left alone; one of the same group and flags with other bytes (the client ids
     moved after a rebuild of the chain) is replaced; anything else with that server id stops the script.
   - mode=replace (new looks for existing items: the three rune-stone crafting orbs, the Orb of Sockets, the seven
     profession ore pieces): the client id attribute of that existing node is set to the row's client id; everything
     else of the node stays. The client entry copies the old one's dat flags (stackable, multi-use, light).
   items.otb.bak keeps the original the first time; the written file is parsed again and every node checked.
2. data/items/items.xml: the new items (name, article, plural, weight, description; corpses: container size, decay,
   corpse type) in a block between two marker comments before </items>, rewritten when the manifest changed. An id that
   already has an entry outside the block stops the script. Items with mode=replace keep their entries.
3. the base desert trader's NPC file, data/npc/Grimgan.xml (or his file of before the npcnames step; when present): the creature products (kind=product) are added to his shop_sellable list at
   their price, so players can sell them (and tools/gen_sell_prices.py picks them up for the Auto Seller).

Idempotent: a second run changes nothing. Lua side: data/lib/chaos_pack_items.lua (food, products by key), loaded by
data/scripts/chaos/pack_items.lua (eating the new food).
"""
import csv, os, re, struct, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from item_wire_table import adjust_rows  # noqa: E402
from install_dark_tiles import scan, node_bytes, xml_escape, ESC, START, END, A_CLIENTID  # noqa: E402

REPO_DATA = os.path.join(os.path.dirname(HERE), 'data')
DEFAULT_MANIFEST = os.path.join(REPO_DATA, 'items', 'art_items.csv')
LUA_OUT = os.path.join(REPO_DATA, 'lib', 'chaos_pack_items.lua')
XML_BEGIN = '\t<!-- Chaos pack items (server/tools/install_pack_items.py, do not edit by hand) -->\n'
XML_END = '\t<!-- end of the Chaos pack items -->\n'
# the desert trader of the base server (Grimgan since the npcnames step; sha256 of his old file name)
TRADER = ('Grimgan', 'e1611e79c955724155c98b4d79dbc11406cd387773935da008cad6e854b36166')
CORPSE = {'blood': ('blood', 'blood'), 'venom': ('venom', 'slime'), 'undead': ('undead', None)}


def read_manifest(path):
    rows = list(csv.DictReader(open(path, newline='')))
    for r in rows:
        for k in ('client_id', 'server_id', 'speed', 'light_level', 'light_color'):
            r[k] = int(r[k])
        for k in ('otb_group', 'otb_flags', 'top_order'):
            r[k] = int(r[k]) if r[k] != '' else None
        r['ex'] = dict(p.split('=', 1) for p in (r['extra'] or '').split('|') if '=' in p)
    return adjust_rows(rows)   # the nodes the client pair needs other wire bytes for (item_wire_table.py)


def unescape(raw):
    out = bytearray(); j = 0
    while j < len(raw):
        if raw[j] == ESC:
            out.append(raw[j + 1]); j += 2
        else:
            out.append(raw[j]); j += 1
    return bytes(out)


def escape(data):
    out = bytearray()
    for b in data:
        if b in (ESC, START, END):
            out.append(ESC)
        out.append(b)
    return bytes(out)


def set_client_id(node, cid):
    """node bytes (START .. END, no children) with the client id attribute replaced"""
    p = unescape(node[1:-1])
    j = 5
    out = bytearray(p[:5])
    found = False
    while j + 3 <= len(p):
        k = p[j]; ln = struct.unpack_from('<H', p, j + 1)[0]
        v = p[j + 3:j + 3 + ln]
        if k == A_CLIENTID:
            v = struct.pack('<H', cid); found = True
        out += bytes([k]) + struct.pack('<H', len(v)) + v
        j += 3 + ln
    assert found, 'node without client id'
    return bytes([START]) + escape(bytes(out)) + bytes([END])


def otb_row(r):
    return {'server_id': r['server_id'], 'client_id': r['client_id'], 'otb_group': r['otb_group'], 'otb_flags': r['otb_flags'],
            'speed': r['speed'], 'light_level': r['light_level'], 'light_color': r['light_color'], 'top_order': r['top_order']}


def patch_otb(data, rows):
    kids, root_end = scan(data)
    by_sid = {k[2]: k for k in kids}
    replace, append, counts = [], [], {'new': 0, 'updated': 0, 'look': 0}
    for r in rows:
        k = by_sid.get(r['server_id'])
        if r['mode'] == 'replace':
            if k is None:
                raise SystemExit('items.otb: no item %d to give a new look; nothing written' % r['server_id'])
            if k[3] != r['client_id']:
                replace.append((k[0], k[1], set_client_id(data[k[0]:k[1]], r['client_id']))); counts['look'] += 1
            continue
        want = node_bytes(otb_row(r))
        if k is None:
            append.append(want); counts['new'] += 1
        elif data[k[0]:k[1]] != want:
            if (k[4], k[5]) != (r['otb_group'], r['otb_flags']):
                raise SystemExit('items.otb: server id %d belongs to another item (client id %s); nothing written'
                                 % (r['server_id'], k[3]))
            replace.append((k[0], k[1], want)); counts['updated'] += 1
    out = bytearray(data)
    for s, e, b in sorted(replace, reverse=True):
        out[s:e] = b
    shift = sum(len(b) - (e - s) for s, e, b in replace)
    at = root_end + shift
    out[at:at] = b''.join(append)
    return bytes(out), counts


def verify_otb(data, rows):
    kids, _ = scan(data)
    by_sid = {k[2]: k for k in kids}
    for r in rows:
        k = by_sid.get(r['server_id'])
        assert k and k[3] == r['client_id'], r['key']
        if r['mode'] == 'new':
            assert data[k[0]:k[1]] == node_bytes(otb_row(r)), r['key']
    sids = [k[2] for k in kids]
    assert len(sids) == len(set(sids)), 'duplicate server ids in items.otb'
    return len(kids)


def article(name):
    return 'an' if name[0] in 'aeiou' else 'a'


def xml_item(r):
    ex, kind, name = r['ex'], r['kind'], r['name']
    attrs = ['id="%d"' % r['server_id']]
    if kind in ('product', 'food', 'corpse', 'tree', 'stump', 'lake', 'dock'):
        attrs.append('article="%s"' % article(name))
    attrs.append('name="%s"' % xml_escape(name))
    if ex.get('plural'):
        attrs.append('plural="%s"' % xml_escape(ex['plural']))
    inner = []
    if 'weight' in ex:
        inner.append(('weight', ex['weight']))
    if ex.get('description'):
        inner.append(('description', ex['description']))
    if kind == 'corpse':
        ctype, fluid = CORPSE.get(ex.get('race', 'blood'), ('blood', 'blood'))
        inner += [('containerSize', '20'), ('decayTo', '0'), ('duration', '600'), ('corpseType', ctype)]
        if fluid:
            inner.append(('fluidSource', fluid))
    if not inner:
        return '\t<item %s />\n' % ' '.join(attrs)
    body = ''.join('\t\t<attribute key="%s" value="%s" />\n' % (k, xml_escape(v)) for k, v in inner)
    return '\t<item %s>\n%s\t</item>\n' % (' '.join(attrs), body)


def patch_xml(text, rows):
    new = [r for r in rows if r['mode'] == 'new']
    block = XML_BEGIN + ''.join(xml_item(r) for r in new) + XML_END
    s = text.find(XML_BEGIN)
    if s >= 0:
        e = text.find(XML_END, s)
        if e < 0:
            raise SystemExit('items.xml: pack item start marker without end marker')
        outside = text[:s] + text[e + len(XML_END):]
    else:
        outside = text
    ranges = [(int(a), int(b)) for a, b in re.findall(r'fromid="(\d+)"\s+toid="(\d+)"', outside)]
    for r in new:
        sid = r['server_id']
        if re.search(r'<item\s+id="%d"' % sid, outside) or any(a <= sid <= b for a, b in ranges):
            raise SystemExit('items.xml: id %d already has an entry outside the pack item block; nothing written' % sid)
    if s >= 0:
        if text[s:e + len(XML_END)] == block:
            return text, 'items.xml: pack item block up to date (%d items)' % len(new)
        return text[:s] + block + text[e + len(XML_END):], 'items.xml: pack item block rewritten (%d items)' % len(new)
    end = text.rfind('</items>')
    if end < 0:
        raise SystemExit('items.xml: no </items>')
    return text[:end] + block + text[end:], 'items.xml: pack item block added (%d items)' % len(new)


def patch_npc(text, rows):
    """our products in the shop_sellable list: entries of the same name (an older manifest) are replaced."""
    m = re.search(r'(<parameter\s+key="shop_sellable"\s+value=")([^"]*)(")', text)
    if not m:
        return text, 'npc: no shop_sellable list, nothing added'
    prods = [r for r in rows if r['kind'] == 'product']
    ours = {r['name'].title() for r in prods}
    entries = [e.strip() for e in m.group(2).split(';') if e.strip()]
    keep = [e for e in entries if e.split(',')[0].strip() not in ours]
    want = ['%s,%d,%s' % (r['name'].title(), r['server_id'], r['ex']['sell']) for r in prods]
    # in order but not necessarily last: a later step (fistweapons) appends its own entries after ours
    if [e for e in entries if e.split(',')[0].strip() in ours] == want:
        if m.group(2) == m.group(2).rstrip():
            return text, 'npc: all creature products already in the sell list'
        # blanks after the last ';' are one more entry to the NPC library ("Parameter(s) missing for item")
        return text[:m.start(2)] + m.group(2).rstrip() + text[m.end(2):], 'npc: blank entry at the end of the sell list removed'
    val = '\n\t\t\t\t\t' + ';\n\t\t\t\t\t'.join(keep + want) + ';'
    return text[:m.start(2)] + val + text[m.end(2):], 'npc: %d creature products in the sell list (%d replaced)' % (
        len(want), len(entries) - len(keep))


def lua_text(rows):
    food = [r for r in rows if r['kind'] == 'food']
    prod = [r for r in rows if r['kind'] == 'product']
    corpse = [r for r in rows if r['kind'] == 'corpse']
    L = ['-- Server ids of the pack items (server/tools/install_pack_items.py --lua, from server/data/items/art_items.csv).',
         '-- Generated; do not edit by hand. The items exist after the "packitems" install step and need the matching',
         '-- client pair (client/tools/sprites/import_art_things.py).', '', 'ChaosPackItems = {', '\t-- [id] = {seconds of food, sound}', '\tfood = {']
    L += ['\t\t[%d] = {%s, "%s"}, -- %s' % (r['server_id'], r['ex']['food'], r['ex']['sound'], r['name']) for r in food]
    L += ['\t},', '\t-- key = server id (creature products, loot of the pack monsters; sold to Grimgan)', '\tproducts = {']
    L += ['\t\t%s = %d,' % (r['key'], r['server_id']) for r in prod]
    L += ['\t},', '\tcorpses = {']
    L += ['\t\t%s = %d,' % (r['key'][len('corpse_'):], r['server_id']) for r in corpse]
    L += ['\t}', '}', '']
    return '\n'.join(L)


def main():
    args = sys.argv[1:]
    dry = '--dry-run' in args
    manifest = DEFAULT_MANIFEST
    if '--manifest' in args:
        i = args.index('--manifest'); manifest = args[i + 1]; del args[i:i + 2]
    rows = read_manifest(manifest)
    for r in rows:
        if r['mode'] == 'new':
            assert r['server_id'] == r['client_id'] + 3000, 'server id must be client id + 3000 (%s)' % r['key']
    if '--lua' in args:
        open(LUA_OUT, 'w').write(lua_text(rows))
        print('wrote', LUA_OUT)
        return 0
    args = [a for a in args if not a.startswith('--')]
    if len(args) != 1:
        print(__doc__)
        return 1
    data_dir = args[0]
    otb = os.path.join(data_dir, 'items', 'items.otb')
    xml = os.path.join(data_dir, 'items', 'items.xml')
    if not os.path.exists(otb) or not os.path.exists(xml):
        print('items.otb / items.xml not found in', os.path.join(data_dir, 'items'))
        return 1
    raw = open(otb, 'rb').read()
    new, c = patch_otb(raw, rows)
    n = verify_otb(new, rows)
    print('items.otb: %d nodes added, %d updated, %d new looks; verified (%d item nodes)' % (c['new'], c['updated'], c['look'], n))
    text = open(xml, encoding='utf-8', errors='surrogateescape').read()
    new_text, note = patch_xml(text, rows)
    print(note)
    import base_rename_lib
    trader = base_rename_lib.npc_file(os.path.join(data_dir, 'npc'), *TRADER)
    npc = os.path.join(data_dir, 'npc', trader) if trader else None
    ntext = new_ntext = None
    if npc and os.path.exists(npc):
        ntext = open(npc, encoding='utf-8', errors='surrogateescape').read()
        new_ntext, nnote = patch_npc(ntext, rows)
        print(nnote)
    else:
        print('npc: the trader %s not found, products not added to a shop' % TRADER[0])
    if dry:
        print('dry run: nothing written')
        return 0
    if new != raw:
        if not os.path.exists(otb + '.bak'):
            open(otb + '.bak', 'wb').write(raw)
        open(otb, 'wb').write(new)
    if new_text != text:
        open(xml, 'w', encoding='utf-8', errors='surrogateescape', newline='').write(new_text)
    if ntext is not None and new_ntext != ntext:
        open(npc, 'w', encoding='utf-8', errors='surrogateescape', newline='').write(new_ntext)
    return 0


if __name__ == '__main__':
    sys.exit(main())
