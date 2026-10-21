#!/usr/bin/env python3
"""Install the second set of crafting orbs and the new names of the currency items into a base server.

usage: python3 -I install_orbs.py DATA_DIR [--dry-run]

Everything is read from server/data/lib/chaos_orbs_config.lua (`items`, `renames`), the same file the Lua side uses.

1. data/items/items.otb: one node per new item (the Orbs of Tempering, Binding, Excision, Reforging and Ruin, the
   Whetstone, the Orb of Unveiling of the veiled modifiers, the Ember, Crown and Void Orbs, server ids 32251..32260), each a
   copy of the stock node of its client sprite (the inlay stones, the essence crystals, the moonlight crystals, the
   crowned gems, the small enchanted amethyst) with the new server id and the "useable" flag (needed for "use with"). Those sprites
   have the multi-use flag in Tibia.dat already, so the client needs nothing (client/tools/sprites/set_multiuse.py is NOT
   needed for these). Nodes are appended at the end of the root; a node already there with the same bytes is left alone,
   one with other bytes is replaced, a server id that belongs to another client id stops the script (nothing is
   written). items.otb.bak keeps the original the first time; the written file is parsed again and every node checked.
2. data/items/items.xml: the new items inside a block between two marker comments before </items> (rewritten when the
   config changed), and the new names of the currency items of `renames` (the base server's character-upgrade currencies
   29851..29859 and the three rune-stone orbs install_crafting.py names): the `name` and `plural` attributes of their
   entries. An id that already has an entry outside the block (for the new items) stops the script.
3. The names the base data refers to those items by: the loot lists of data/monster (`id = "chaos orb"` in the waystone
   monsters, `<item name="chaos orb" .../>` in monster XML), NPC shop lists and any other script or XML of the base server
   (not data/scripts/chaos and not data/lib/chaos_*.lua, which come from this repository) have the old names replaced,
   case-insensitively and whole words only ("Vaal Orb" -> "Void Orb", "Chaos Orb" -> "Orb of Upheaval", ...). Without
   this step the monsters' loot entries would name items that no longer exist.

Idempotent: a second run changes nothing. --dry-run changes nothing at all.
"""
import os, re, struct, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from install_gems import (scan, escape, attr, xml_escape, START, END, A_SERVERID, FLAG_USEABLE, FLAG_STACKABLE,  # noqa: E402
                          FLAG_PICKUPABLE, FLAG_MOVEABLE)

CONFIG = os.path.join(os.path.dirname(HERE), 'data', 'lib', 'chaos_orbs_config.lua')
XML_BEGIN = '\t<!-- Chaos crafting orbs v2 (server/tools/install_orbs.py, do not edit by hand) -->\n'
XML_END = '\t<!-- end of the Chaos crafting orbs v2 -->\n'


def read_config(path=CONFIG):
    text = open(path, encoding='utf-8').read()
    text = re.sub(r'--[^\n]*', '', text)

    def table(name):
        m = re.search(r'\b%s\s*=\s*\{\n(.*?)\n\t\}' % name, text, re.S)
        assert m, 'chaos_orbs_config.lua: no %s table' % name
        return m.group(1)

    def field(row, key, num=False):
        m = re.search(r'\b%s\s*=\s*%s' % (key, r'(\d+)' if num else r'"([^"]*)"'), row)
        assert m, 'chaos_orbs_config.lua: %s missing in %s' % (key, row[:60])
        return int(m.group(1)) if num else m.group(1)

    items = []
    for row in table('items').split('\n'):
        if '{' not in row:
            continue
        items.append({'id': field(row, 'id', True), 'key': field(row, 'key'), 'clientId': field(row, 'clientId', True),
                      'name': field(row, 'name'), 'plural': field(row, 'plural'), 'article': field(row, 'article'),
                      'weight': field(row, 'weight', True), 'description': field(row, 'description')})
    renames = []
    for row in table('renames').split('\n'):
        if '{' not in row:
            continue
        renames.append({'id': field(row, 'id', True), 'name': field(row, 'name'), 'plural': field(row, 'plural'),
                        'old': field(row, 'old')})
    assert items and renames, 'chaos_orbs_config.lua: no items or renames'
    ids = [i['id'] for i in items]
    assert len(ids) == len(set(ids)), 'duplicate item ids'
    return {'items': items, 'renames': renames}


# ------------------------------------------------------------------------------------------------ items.otb
def orb_node(stock, sid):
    """a copy of the stock node (group, flags + useable, every attribute) with the new server id"""
    _s, _e, _sid, _cid, group, flags, attrs = stock
    flags |= FLAG_USEABLE | FLAG_PICKUPABLE | FLAG_MOVEABLE | FLAG_STACKABLE
    body = struct.pack('<I', flags)
    for k, v in attrs:
        if k == A_SERVERID:
            v = struct.pack('<H', sid)
        body += attr(k, v)
    return bytes([START]) + escape(bytes([group])) + escape(body) + bytes([END])


def stock_for(kids, cid, ours):
    """the stock node of a client id: the lowest server id that is not one of ours"""
    best = None
    for k in kids:
        sid, c = k[2], k[3]
        if sid is None or c != cid or sid in ours:
            continue
        if best is None or sid < best[2]:
            best = k
    return best


def patch_otb(data, items):
    kids, _ = scan(data)
    ours = {i['id'] for i in items}
    notes, out = [], bytearray(data)
    wanted = {}
    for it in items:
        stock = stock_for(kids, it['clientId'], ours)
        if stock is None:
            raise SystemExit('items.otb: no stock node with client id %d (%s); nothing written' % (it['clientId'], it['name']))
        wanted[it['id']] = (orb_node(stock, it['id']), stock[3])
    # replace in place, from the back (the offsets of the earlier ones stay valid), then append the missing ones
    by_sid = {k[2]: k for k in kids}
    append = b''
    for it in items:
        node, cid = wanted[it['id']]
        k = by_sid.get(it['id'])
        if k is None:
            append += node
            notes.append('items.otb: %s node added (server id %d, client id %d)' % (it['name'], it['id'], cid))
        elif k[3] != cid:
            raise SystemExit('items.otb: server id %d already belongs to client id %s, not %d; nothing written'
                             % (it['id'], k[3], cid))
        elif data[k[0]:k[1]] != node:
            notes.append('items.otb: %s node rewritten (the flags or the sprite changed)' % it['name'])
    for it in sorted(items, key=lambda i: -(by_sid[i['id']][0] if i['id'] in by_sid else -1)):
        k = by_sid.get(it['id'])
        if k is not None and data[k[0]:k[1]] != wanted[it['id']][0]:
            out[k[0]:k[1]] = wanted[it['id']][0]
    if append:
        _kids, root_end = scan(bytes(out))
        out[root_end:root_end] = append
    if not notes:
        notes.append('items.otb: the %d orb nodes are present' % len(items))
    return bytes(out), notes, wanted


def verify_otb(data, items, wanted):
    kids, _ = scan(data)
    by_sid = {k[2]: k for k in kids}
    for it in items:
        k = by_sid.get(it['id'])
        node, cid = wanted[it['id']]
        assert k and k[3] == cid and k[5] & FLAG_STACKABLE and k[5] & FLAG_USEABLE, 'orb node %d' % it['id']
        assert data[k[0]:k[1]] == node, 'orb node bytes %d' % it['id']
    sids = [k[2] for k in kids]
    assert len(sids) == len(set(sids)), 'duplicate server ids in items.otb'
    return len(kids)


# ------------------------------------------------------------------------------------------------ items.xml
def xml_block(items):
    lines = [XML_BEGIN]
    for it in items:
        lines.append('\t<item id="%d" article="%s" name="%s" plural="%s">\n'
                     '\t\t<attribute key="description" value="%s" />\n'
                     '\t\t<attribute key="weight" value="%d" />\n'
                     '\t</item>\n' % (it['id'], xml_escape(it['article']), xml_escape(it['name']), xml_escape(it['plural']),
                                      xml_escape(it['description']), it['weight']))
    lines.append(XML_END)
    return ''.join(lines)


def rename_entries(text, renames):
    """set name / plural of the entries of `renames`; returns (text, notes)"""
    notes = []
    for r in renames:
        m = re.search(r'<item\s+id="%d"([^>]*?)(/?)>' % r['id'], text)
        if not m:
            notes.append('items.xml: %d (%s) has no entry yet: left to install_crafting.py' % (r['id'], r['name']))
            continue
        attrs = m.group(1)
        new = attrs
        nm = re.search(r'\sname="([^"]*)"', new)
        if nm:
            if nm.group(1) == r['name']:
                pass
            else:
                new = new[:nm.start()] + ' name="%s"' % xml_escape(r['name']) + new[nm.end():]
        else:
            new += ' name="%s"' % xml_escape(r['name'])
        pl = re.search(r'\splural="([^"]*)"', new)
        if pl:
            if pl.group(1) != r['plural']:
                new = new[:pl.start()] + ' plural="%s"' % xml_escape(r['plural']) + new[pl.end():]
        else:
            new += ' plural="%s"' % xml_escape(r['plural'])
        if new != attrs:
            text = text[:m.start(1)] + new + text[m.end(1):]
            notes.append('items.xml: %d is now "%s"' % (r['id'], r['name']))
    return text, notes


def patch_xml(text, items, renames):
    block = xml_block(items)
    s = text.find(XML_BEGIN)
    if s >= 0:
        e = text.find(XML_END, s)
        if e < 0:
            raise SystemExit('items.xml: orbs start marker without end marker')
        outside = text[:s] + text[e + len(XML_END):]
    else:
        outside = text
    ranges = [(int(a), int(b)) for a, b in re.findall(r'fromid="(\d+)"\s+toid="(\d+)"', outside)]
    for it in items:
        sid = it['id']
        if re.search(r'<item\s+id="%d"' % sid, outside) or any(a <= sid <= b for a, b in ranges):
            raise SystemExit('items.xml: id %d already has an entry outside the orbs block; nothing written' % sid)
    notes = []
    if s >= 0:
        if text[s:e + len(XML_END)] == block:
            notes.append('items.xml: orbs block up to date (%d items)' % len(items))
        else:
            text = text[:s] + block + text[e + len(XML_END):]
            notes.append('items.xml: orbs block rewritten (%d items)' % len(items))
    else:
        end = text.rfind('</items>')
        if end < 0:
            raise SystemExit('items.xml: no </items>')
        text = text[:end] + block + text[end:]
        notes.append('items.xml: orbs block added (%d items)' % len(items))
    text, more = rename_entries(text, renames)
    return text, notes + more


# ------------------------------------------------------------------------------------------------ name references
SKIP_DIRS = (os.path.join('scripts', 'chaos'), os.path.join('items'), os.path.join('patchnotes'))


def name_patterns(renames):
    """[(compiled regex, function(match) -> new text)] for every old name, longest first"""
    out = []
    for r in sorted(renames, key=lambda r: -len(r['old'])):
        old, new = r['old'], r['name']
        # plural forms of the old name ("Chaos Orbs") are not written by the base data; the singular is enough
        out.append((re.compile(r'(?<![A-Za-z])%s(?![A-Za-z])' % re.escape(old), re.I),
                    (lambda new: lambda m: new.lower() if m.group(0) == m.group(0).lower() else new)(new)))
    return out


def patch_references(data_dir, renames, dry):
    pats = name_patterns(renames)
    changed, total = [], 0
    for sub in ('monster', 'npc', 'scripts', 'talkactions', 'actions', 'creaturescripts', 'globalevents', 'movements', 'lib',
                'events', 'raids', 'weapons', 'XML'):
        root = os.path.join(data_dir, sub)
        for dirpath, dirs, files in os.walk(root):
            rel = os.path.relpath(dirpath, data_dir)
            if any(rel == d or rel.startswith(d + os.sep) for d in SKIP_DIRS):
                dirs[:] = []
                continue
            for f in files:
                if not f.endswith(('.lua', '.xml', '.txt', '.off')):
                    continue
                if sub == 'lib' and f.startswith('chaos_'):
                    continue
                path = os.path.join(dirpath, f)
                try:
                    text = open(path, encoding='utf-8', errors='surrogateescape').read()
                except OSError:
                    continue
                new = text
                for rx, fn in pats:
                    new = rx.sub(fn, new)
                if new != text:
                    n = sum(1 for _ in re.finditer('|'.join(rx.pattern for rx, _f in pats), text, re.I))
                    changed.append((os.path.relpath(path, data_dir), n))
                    total += n
                    if not dry:
                        open(path, 'w', encoding='utf-8', errors='surrogateescape', newline='').write(new)
    return changed, total


def main():
    args = sys.argv[1:]
    dry = '--dry-run' in args
    args = [a for a in args if not a.startswith('--')]
    if len(args) != 1:
        print(__doc__)
        return 1
    data_dir = args[0]
    cfg = read_config()
    otb = os.path.join(data_dir, 'items', 'items.otb')
    xml = os.path.join(data_dir, 'items', 'items.xml')
    if not os.path.exists(otb) or not os.path.exists(xml):
        print('items.otb / items.xml not found in', os.path.join(data_dir, 'items'))
        return 1
    raw = open(otb, 'rb').read()
    new, notes, wanted = patch_otb(raw, cfg['items'])
    n = verify_otb(new, cfg['items'], wanted)
    for note in notes:
        print(note)
    print('items.otb: verified (%d item nodes, %d orb nodes)' % (n, len(cfg['items'])))
    text = open(xml, encoding='utf-8', errors='surrogateescape').read()
    new_text, xnotes = patch_xml(text, cfg['items'], cfg['renames'])
    for note in xnotes:
        print(note)
    changed, total = patch_references(data_dir, cfg['renames'], dry)
    for rel, count in changed[:20]:
        print('names: %s (%d)' % (rel, count))
    if len(changed) > 20:
        print('names: ... and %d more files' % (len(changed) - 20))
    print('names: %d reference%s in %d file%s %s' % (total, '' if total == 1 else 's', len(changed),
                                                    '' if len(changed) == 1 else 's', 'would change' if dry else 'changed'))
    if dry:
        print('dry run: nothing written')
        return 0
    if new != raw:
        if not os.path.exists(otb + '.bak'):
            open(otb + '.bak', 'wb').write(raw)
        open(otb, 'wb').write(new)
    if new_text != text:
        open(xml, 'w', encoding='utf-8', errors='surrogateescape', newline='').write(new_text)
    return 0


if __name__ == '__main__':
    sys.exit(main())
