#!/usr/bin/env python3
"""Install the Everfull Ration (the store's infinite food) into a base server: one items.otb node and one items.xml
entry.

usage: python3 -I install_store_food.py DATA_DIR [--dry-run]

Everything is read from server/data/scripts/chaos/store_food_config.lua (`item`: id, sourceId, clientId, ownLook,
weight, article, name, plural, description), the file the Lua side (store_food.lua) uses too.

1. data/items/items.otb: a copy of the stock food node `sourceId` (2672, the dragon ham: group, flags, every attribute)
   with the server id `id`, stackable like that node (its look is a stackable client thing: the 10.98 protocol
   writes a count byte for an item whose client thing is stackable, so a server item that is not would leave the
   client reading past the message, "ProtocolGame parse message exception ... opcode 0x6e" at every container that
   showed the ration, found in a live test 2026-10-14; one ration a character, count 1, never used up). Its client
   id: the dragon ham's while
   `ownLook = false`, `clientId` (our art, client id 33904: client/tools/sprites/gen_store_food_art.py, appended by
   import_art_things.py with art_import/store_food.csv; in things_custom25) while ownLook = true (on since 2026-10-14). A node already there with the same bytes is left alone, one
   with other bytes (a changed config or look) is replaced; a server id that belongs to any other client id stops the
   script (nothing is written). items.otb.bak keeps the original the first time; the written file is parsed again and
   the node checked. Range: 32084 (after the store pouches 32081..32083).
2. data/items/items.xml: the entry (article, name, plural, description, weight) between two marker comments before
   </items>, rewritten when the config changed. An id that already has an entry outside the block stops the script.

The use (eating) and the store-bound rules are Lua (store_food.lua); the move / trade refusals are the store pouches'
hook (install_pouches.py) for any item with chaos_storebound. Idempotent: a second run changes nothing.
"""
import os, re, struct, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from install_gems import (scan, escape, attr, xml_escape, START, END, A_SERVERID, A_CLIENTID, FLAG_STACKABLE,  # noqa: E402
                          FLAG_PICKUPABLE, FLAG_MOVEABLE)

CONFIG = os.path.join(os.path.dirname(HERE), 'data', 'scripts', 'chaos', 'store_food_config.lua')
XML_BEGIN = '\t<!-- Chaos Everfull Ration (server/tools/install_store_food.py, do not edit by hand) -->\n'
XML_END = '\t<!-- end of the Chaos Everfull Ration -->\n'


def read_config(path=CONFIG):
    text = open(path, encoding='utf-8').read()
    block = re.search(r'\n\titem = \{(.*?)\},\n', text, re.S).group(1)

    def num(key):
        return int(re.search(r'\b%s\s*=\s*(\d+)' % key, block).group(1))

    def string(key):
        m = re.search(r'\b%s\s*=\s*((?:"[^"]*"\s*(?:\.\.\s*)?)+)' % key, block, re.S)
        return ''.join(re.findall(r'"([^"]*)"', m.group(1)))

    own = re.search(r'\bownLook\s*=\s*(true|false)', block)
    cfg = {'id': num('id'), 'sourceId': num('sourceId'), 'clientId': num('clientId'), 'weight': num('weight'),
           'ownLook': bool(own and own.group(1) == 'true'), 'name': string('name'), 'plural': string('plural'),
           'article': string('article'), 'description': string('description')}
    assert cfg['id'] > 0 and cfg['sourceId'] > 0 and cfg['name'], 'store_food_config.lua: item incomplete'
    return cfg


def node(stock, cfg, client_id):
    """a copy of the stock food node with the new server id and client id, stackable as the stock node is (the client
    reads a count for a stackable look; the ration's look is the stock food's or our art made with its flags)"""
    _s, _e, _sid, _cid, group, flags, attrs = stock
    flags = flags | FLAG_PICKUPABLE | FLAG_MOVEABLE
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


def patch_otb(data, cfg):
    kids, root_end = scan(data)
    by_sid = {k[2]: k for k in kids}
    stock = by_sid.get(cfg['sourceId'])
    if stock is None:
        raise SystemExit('items.otb: no stock node %d (the ration source); nothing written' % cfg['sourceId'])
    cid = cfg['clientId'] if cfg['ownLook'] else stock[3]
    if cfg['ownLook'] and cid in {k[3] for k in kids if k[2] != cfg['id']}:
        raise SystemExit('items.otb: client id %d (the ration look) is already used by another node; nothing written' % cid)
    want = node(stock, cfg, cid)
    k = by_sid.get(cfg['id'])
    buf = bytearray(data)
    if k is None:
        buf[root_end:root_end] = want
        note = 'items.otb: Everfull Ration node added (server id %d, client id %d)' % (cfg['id'], cid)
    elif k[3] not in (stock[3], cfg['clientId']):
        raise SystemExit('items.otb: server id %d already belongs to client id %s, not %d or %d; nothing written'
                         % (cfg['id'], k[3], stock[3], cfg['clientId']))
    elif data[k[0]:k[1]] != want:
        buf[k[0]:k[1]] = want
        note = 'items.otb: Everfull Ration node updated (client id %s -> %d)' % (k[3], cid)
    else:
        note = 'items.otb: Everfull Ration node present'
    return bytes(buf), note, want, cid


def verify_otb(data, cfg, want, cid):
    kids, _ = scan(data)
    by_sid = {k[2]: k for k in kids}
    k = by_sid.get(cfg['id'])
    assert k and k[3] == cid, 'ration node %d' % cfg['id']
    stock = by_sid.get(cfg['sourceId'])
    assert stock and bool(k[5] & FLAG_STACKABLE) == bool(stock[5] & FLAG_STACKABLE), \
        'ration stackable as its source (the client reads a count for a stackable look)'
    assert data[k[0]:k[1]] == want, 'ration node bytes'
    sids = [x[2] for x in kids]
    assert len(sids) == len(set(sids)), 'duplicate server ids in items.otb'
    return len(kids)


def xml_block(cfg):
    return XML_BEGIN + ('\t<item id="%d" article="%s" name="%s" plural="%s">\n'
                        '\t\t<attribute key="description" value="%s" />\n'
                        '\t\t<attribute key="weight" value="%d" />\n'
                        '\t</item>\n' % (cfg['id'], xml_escape(cfg['article']), xml_escape(cfg['name']),
                                         xml_escape(cfg['plural']), xml_escape(cfg['description']), cfg['weight'])) + XML_END


def patch_xml(text, cfg):
    block = xml_block(cfg)
    s = text.find(XML_BEGIN)
    if s >= 0:
        e = text.find(XML_END, s)
        if e < 0:
            raise SystemExit('items.xml: ration start marker without end marker')
        outside = text[:s] + text[e + len(XML_END):]
    else:
        outside = text
    ranges = [(int(a), int(b)) for a, b in re.findall(r'fromid="(\d+)"\s+toid="(\d+)"', outside)]
    sid = cfg['id']
    if re.search(r'<item\s+id="%d"' % sid, outside) or any(a <= sid <= b for a, b in ranges):
        raise SystemExit('items.xml: id %d already has an entry outside the ration block; nothing written' % sid)
    if s >= 0:
        if text[s:e + len(XML_END)] == block:
            return text, 'items.xml: ration block up to date'
        return text[:s] + block + text[e + len(XML_END):], 'items.xml: ration block rewritten'
    end = text.rfind('</items>')
    if end < 0:
        raise SystemExit('items.xml: no </items>')
    return text[:end] + block + text[end:], 'items.xml: ration block added'


def main(argv=None):
    args = list(sys.argv[1:] if argv is None else argv)
    dry = '--dry-run' in args
    args = [a for a in args if not a.startswith('--')]
    if len(args) != 1:
        print(__doc__)
        return 1
    data_dir = args[0]
    cfg = read_config()
    otb = os.path.join(data_dir, 'items', 'items.otb')
    xml = os.path.join(data_dir, 'items', 'items.xml')
    for path in (otb, xml):
        if not os.path.exists(path):
            print('not found:', path)
            return 1
    raw = open(otb, 'rb').read()
    new, note, want, cid = patch_otb(raw, cfg)
    n = verify_otb(new, cfg, want, cid)
    print(note)
    print('items.otb: verified (%d item nodes; ration %d, client %d)' % (n, cfg['id'], cid))
    text = open(xml, encoding='utf-8', errors='surrogateescape').read()
    new_text, xnote = patch_xml(text, cfg)
    print(xnote)
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
