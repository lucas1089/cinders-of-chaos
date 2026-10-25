#!/usr/bin/env python3
"""Install the store pouches (the Loot Pouch, the Orbs Pouch and the Rift Key Pouch) into a base server: three
items.otb nodes, three items.xml entries and the move hook in data/events/scripts/player.lua.

usage: python3 -I install_pouches.py DATA_DIR [--dry-run] [--stock-looks]

Everything is read from server/data/scripts/chaos/pouches_config.lua (`kinds`: id, sourceId, clientId, capacity,
weight, article, name, plural, description), the same file the Lua side uses.

1. data/items/items.otb: per pouch a copy of the stock container node `sourceId` (loot 32081: the expedition bag,
   orbs 32082: the brocade bag, keys 32083: the fur bag; group, flags, every attribute; containers, not stackable)
   with the server id `id` and the client id `clientId`: our own pouch looks (loot 38608, orbs 38609, keys 38610 of
   pair 34), appended to the client pair by client/tools/sprites/import_art_things.py with art_import/store_items.csv
   (client MANIFEST.md "Store item looks"). --stock-looks keeps the stock bags' client ids instead (for clients whose
   pair does not have the pouch looks yet). The nodes are appended at the end of the root; a node already there with
   the same bytes is left alone, one with other bytes (a changed config, or the stock look or the `oldClientId` look
   33651-33653 of an earlier install: only its client id changes, so existing pouches show the new look at once) is
   replaced, and a server id that belongs to any other client id stops the script (nothing is written).
   items.otb.bak keeps the original the first time; the written file is parsed again and the nodes checked.
   Ranges in use: gems 32001..32035, salvage 32051, omens 32071..32072, pouches 32081..32083, supports 32101..32200,
   orbs v2 32251..32256, Everfull tiers 32261..32267, dark tiles 30484..30557, art 33000.., pack items 36000.., donor items 40000...
2. data/items/items.xml: the entries (name, plural, description, weight, containerSize = capacity) between two marker
   comments before </items>, rewritten when the config changed. An id that already has an entry outside the block
   stops the script.
3. data/events/scripts/player.lua: Player:onMoveItem asks ChaosPouches.onMoveItem first (a pouch, or a container
   holding one, stays in the character's inventory or depot). A script callback cannot refuse a move reliably: the
   base EventCallback dispatcher keeps only the last onMoveItem callback's value. The hook returns early only when the
   pouch rules refuse the move; otherwise the base function runs exactly as before.

Idempotent: a second run changes nothing.
"""
import os, re, struct, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from install_gems import (scan, escape, attr, xml_escape, START, END, A_SERVERID, A_CLIENTID, FLAG_STACKABLE,  # noqa: E402
                          FLAG_PICKUPABLE, FLAG_MOVEABLE)

CONFIG = os.path.join(os.path.dirname(HERE), 'data', 'scripts', 'chaos', 'pouches_config.lua')
XML_BEGIN = '\t<!-- Chaos store pouches (server/tools/install_pouches.py, do not edit by hand) -->\n'
XML_END = '\t<!-- end of the Chaos store pouches -->\n'
NAMES = ('loot', 'orbs', 'keys')
GROUP_CONTAINER = 2

HOOK_MARKER = '-- Chaos: store pouches stay with their owner (install_pouches.py)'
HOOK = (
    '\t' + HOOK_MARKER + '\n'
    '\tif ChaosPouches and ChaosPouches.onMoveItem then\n'
    '\t\tlocal chaosPouchRet = ChaosPouches.onMoveItem(self, item, count, fromPosition, toPosition, fromCylinder, toCylinder)\n'
    '\t\tif chaosPouchRet and chaosPouchRet ~= RETURNVALUE_NOERROR then\n'
    '\t\t\treturn chaosPouchRet\n'
    '\t\tend\n'
    '\tend\n'
)


def read_config(path=CONFIG):
    text = open(path, encoding='utf-8').read()
    kinds = re.search(r'\n\tkinds = \{(.*?)\n\t\},?\n', text, re.S).group(1)
    out = {}
    for name in NAMES:
        block = re.search(r'\n\t\t%s = \{(.*?)\}' % name, kinds, re.S).group(1)

        def num(key):
            return int(re.search(r'\b%s\s*=\s*(\d+)' % key, block).group(1))

        def string(key):
            m = re.search(r'\b%s\s*=\s*((?:"[^"]*"\s*(?:\.\.\s*)?)+)' % key, block, re.S)
            return ''.join(re.findall(r'"([^"]*)"', m.group(1)))

        old = re.search(r'\boldClientId\s*=\s*(\d+)', block)
        cfg = {'id': num('id'), 'sourceId': num('sourceId'), 'clientId': num('clientId'), 'capacity': num('capacity'), 'weight': num('weight'),
               'oldClientId': int(old.group(1)) if old else None,
               'name': string('name'), 'plural': string('plural'), 'article': string('article'),
               'description': string('description')}
        assert cfg['id'] > 0 and cfg['sourceId'] > 0 and cfg['name'], 'pouches_config.lua: kinds.%s incomplete' % name
        assert 1 <= cfg['capacity'] <= 255, 'pouches_config.lua: kinds.%s capacity 1..255 (one byte in the protocol)' % name
        out[name] = cfg
    ids = [out[n]['id'] for n in NAMES]
    assert len(set(ids)) == len(ids), 'pouches_config.lua: the pouches need three ids'
    return out


def look_of(stock, cfg, stock_looks=False):
    """the client id the pouch node gets: its own look, or the stock bag's with --stock-looks"""
    return stock[3] if stock_looks else cfg['clientId']


def node(stock, cfg, client_id):
    """a copy of the stock container node (group, flags, every attribute) with the new server id and client id"""
    _s, _e, _sid, _cid, group, flags, attrs = stock
    flags = (flags | FLAG_PICKUPABLE | FLAG_MOVEABLE) & ~FLAG_STACKABLE
    body = struct.pack('<I', flags)
    seen = False
    for k, v in attrs:
        if k == A_SERVERID:
            v = struct.pack('<H', cfg['id'])
        elif k == A_CLIENTID:
            v = struct.pack('<H', client_id)
            seen = True
        body += attr(k, v)
    assert seen, 'stock node %d has no client id attribute' % cfg['sourceId']
    return bytes([START]) + escape(bytes([group])) + escape(body) + bytes([END])


def patch_otb(data, items, stock_looks=False):
    notes, wanted = [], {}
    out = bytes(data)
    for name in NAMES:
        cfg = items[name]
        kids, root_end = scan(out)
        by_sid = {k[2]: k for k in kids}
        stock = by_sid.get(cfg['sourceId'])
        if stock is None:
            raise SystemExit('items.otb: no stock node %d (%s pouch source); nothing written' % (cfg['sourceId'], name))
        if stock[4] != GROUP_CONTAINER:
            raise SystemExit('items.otb: stock node %d is not a container (group %d); nothing written'
                             % (cfg['sourceId'], stock[4]))
        cid = look_of(stock, cfg, stock_looks)
        if cid != stock[3] and cid in {k[3] for k in kids if k[2] != cfg['id']}:
            raise SystemExit('items.otb: client id %d (%s pouch look) is already used by another node; nothing written'
                             % (cid, name))
        want = node(stock, cfg, cid)
        k = by_sid.get(cfg['id'])
        buf = bytearray(out)
        if k is None:
            buf[root_end:root_end] = want
            notes.append('items.otb: %s pouch node added (server id %d, client id %d)' % (name, cfg['id'], cid))
        elif k[3] not in (stock[3], cfg['clientId'], cfg.get('oldClientId')):
            raise SystemExit('items.otb: server id %d already belongs to client id %s, not %d, %d or %s; nothing written'
                             % (cfg['id'], k[3], stock[3], cfg['clientId'], cfg.get('oldClientId')))
        elif out[k[0]:k[1]] != want:
            buf[k[0]:k[1]] = want
            notes.append('items.otb: %s pouch node updated (client id %s -> %d)' % (name, k[3], cid))
        else:
            notes.append('items.otb: %s pouch node present' % name)
        out = bytes(buf)
        wanted[name] = (want, cid)
    return out, notes, wanted


def verify_otb(data, items, wanted):
    kids, _ = scan(data)
    by_sid = {k[2]: k for k in kids}
    for name in NAMES:
        cfg = items[name]
        want, cid = wanted[name]
        k = by_sid.get(cfg['id'])
        assert k and k[3] == cid, '%s pouch node %d' % (name, cfg['id'])
        assert k[4] == GROUP_CONTAINER, '%s pouch node is a container' % name
        assert not (k[5] & FLAG_STACKABLE), '%s pouch not stackable' % name
        assert data[k[0]:k[1]] == want, '%s pouch node bytes' % name
    sids = [k[2] for k in kids]
    assert len(sids) == len(set(sids)), 'duplicate server ids in items.otb'
    return len(kids)


def xml_block(items):
    body = ''
    for name in NAMES:
        cfg = items[name]
        body += ('\t<item id="%d" article="%s" name="%s" plural="%s">\n'
                 '\t\t<attribute key="description" value="%s" />\n'
                 '\t\t<attribute key="weight" value="%d" />\n'
                 '\t\t<attribute key="containerSize" value="%d" />\n'
                 '\t</item>\n' % (cfg['id'], xml_escape(cfg['article']), xml_escape(cfg['name']),
                                  xml_escape(cfg['plural']), xml_escape(cfg['description']), cfg['weight'],
                                  cfg['capacity']))
    return XML_BEGIN + body + XML_END


def patch_xml(text, items):
    block = xml_block(items)
    s = text.find(XML_BEGIN)
    if s >= 0:
        e = text.find(XML_END, s)
        if e < 0:
            raise SystemExit('items.xml: pouch start marker without end marker')
        outside = text[:s] + text[e + len(XML_END):]
    else:
        outside = text
    ranges = [(int(a), int(b)) for a, b in re.findall(r'fromid="(\d+)"\s+toid="(\d+)"', outside)]
    for name in NAMES:
        sid = items[name]['id']
        if re.search(r'<item\s+id="%d"' % sid, outside) or any(a <= sid <= b for a, b in ranges):
            raise SystemExit('items.xml: id %d already has an entry outside the pouch block; nothing written' % sid)
    if s >= 0:
        if text[s:e + len(XML_END)] == block:
            return text, 'items.xml: pouch block up to date'
        return text[:s] + block + text[e + len(XML_END):], 'items.xml: pouch block rewritten'
    end = text.rfind('</items>')
    if end < 0:
        raise SystemExit('items.xml: no </items>')
    return text[:end] + block + text[end:], 'items.xml: pouch block added (Loot, Orbs and Rift Key Pouch)'


def patch_player(text):
    """returns (new text, status): the hook at the top of Player:onMoveItem"""
    if HOOK_MARKER in text:
        return text, 'player.lua: move hook present'
    m = re.search(r'function Player:onMoveItem\(item, count, fromPosition, toPosition, fromCylinder, toCylinder\)[ \t]*\n',
                  text)
    if not m:
        raise SystemExit('player.lua: Player:onMoveItem(item, count, fromPosition, toPosition, fromCylinder, toCylinder) '
                         'not found; nothing written')
    return text[:m.end()] + HOOK + text[m.end():], 'player.lua: move hook added to Player:onMoveItem'


def main():
    args = sys.argv[1:]
    dry = '--dry-run' in args
    stock_looks = '--stock-looks' in args
    args = [a for a in args if not a.startswith('--')]
    if len(args) != 1:
        print(__doc__)
        return 1
    data_dir = args[0]
    items = read_config()
    otb = os.path.join(data_dir, 'items', 'items.otb')
    xml = os.path.join(data_dir, 'items', 'items.xml')
    player = os.path.join(data_dir, 'events', 'scripts', 'player.lua')
    for path in (otb, xml, player):
        if not os.path.exists(path):
            print('not found:', path)
            return 1
    raw = open(otb, 'rb').read()
    new, notes, wanted = patch_otb(raw, items, stock_looks)
    n = verify_otb(new, items, wanted)
    for note in notes:
        print(note)
    print('items.otb: verified (%d item nodes; pouches %s)' % (n, ', '.join('%d (client %d)' % (items[k]['id'], wanted[k][1])
                                                                           for k in NAMES)))
    text = open(xml, encoding='utf-8', errors='surrogateescape').read()
    new_text, xnote = patch_xml(text, items)
    print(xnote)
    ptext = open(player, encoding='utf-8', errors='surrogateescape', newline='').read()
    new_ptext, pnote = patch_player(ptext)
    print(pnote)
    if dry:
        print('dry run: nothing written')
        return 0
    if new != raw:
        if not os.path.exists(otb + '.bak'):
            open(otb + '.bak', 'wb').write(raw)
        open(otb, 'wb').write(new)
    if new_text != text:
        open(xml, 'w', encoding='utf-8', errors='surrogateescape', newline='').write(new_text)
    if new_ptext != ptext:
        open(player, 'w', encoding='utf-8', errors='surrogateescape', newline='').write(new_ptext)
    return 0


if __name__ == '__main__':
    sys.exit(main())
