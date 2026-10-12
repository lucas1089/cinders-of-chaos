#!/usr/bin/env python3
"""Install the charm items into a base server (server/data/scripts/chaos/charms*.lua; README "Charms").

usage: python3 -I install_charms.py DATA_DIR [--dry-run]

Everything is read from server/data/scripts/chaos/charms_config.lua (`C.items`: id, key, sourceId, article, name,
plural, weight, description; `stackable = true` for the charm shard), the same file the Lua side uses.

1. data/items/items.otb: per item a copy of the stock node `sourceId` with the server id `id` (32301..32304 the small,
   tall, wide and grand charm, 32305..32308 the four unique charms, 32309 the charm shard). Their client ids stay the
   stock ones (small trinkets: insignia, brooch, medals, figurines, a frost charm; the shard an onyx chip), so the
   client needs no change. A charm is never stackable (every charm has its own modifiers); the shard is, and its stock
   node must be too (the client reads the count byte by the stock look's flags). The nodes are appended at the end of
   the root; a node already there with the same bytes is left alone, one with other bytes (a changed config) is
   replaced, and a server id that belongs to another client id stops the script (nothing is written). items.otb.bak
   keeps the original the first time; the written file is parsed again and the nodes checked.
   (Ranges in use: see install_omens.py; omens 32071..32072, Ascended 32073..32077, pouches 32081..32083, faction
   tokens 32091..32094, supports 32101..32200, orbs v2 32251..32260, charms 32301..32309.)
2. data/items/items.xml: the entries (name, plural, description, weight) between two marker comments before </items>,
   rewritten when the config changed. An id that already has an entry outside the block stops the script.

Idempotent: a second run changes nothing.
"""
import os, re, struct, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from install_gems import scan, escape, attr, xml_escape, START, END, A_SERVERID, FLAG_STACKABLE, FLAG_PICKUPABLE, FLAG_MOVEABLE  # noqa: E402

SERVER = os.path.dirname(HERE)
CONFIG = os.path.join(SERVER, 'data', 'scripts', 'chaos', 'charms_config.lua')
XML_BEGIN = '\t<!-- Chaos charms (server/tools/install_charms.py, do not edit by hand) -->\n'
XML_END = '\t<!-- end of the Chaos charms -->\n'


def read_config(path=CONFIG):
    text = open(path, encoding='utf-8').read()
    block = re.search(r'\nC\.items = \{(.*?)\n\}', text, re.S).group(1)
    out = []
    for m in re.finditer(r'\{(id = \d+.*?)\},?\s*(?=\n\t\{|$)', block, re.S):
        body = m.group(1)

        def num(k):
            return int(re.search(r'\b%s\s*=\s*(\d+)' % k, body).group(1))

        def string(k):
            mm = re.search(r'\b%s\s*=\s*((?:"[^"]*"\s*(?:\.\.\s*)?)+)' % k, body, re.S)
            return ''.join(re.findall(r'"([^"]*)"', mm.group(1)))

        cfg = {'key': string('key'), 'id': num('id'), 'sourceId': num('sourceId'), 'weight': num('weight'),
               'name': string('name'), 'plural': string('plural'), 'article': string('article'),
               'description': string('description'), 'stackable': bool(re.search(r'\bstackable\s*=\s*true', body))}
        assert cfg['id'] > 0 and cfg['sourceId'] > 0 and cfg['name'], 'charms_config.lua: item %s incomplete' % cfg['key']
        out.append(cfg)
    assert len(out) >= 1, 'charms_config.lua: no items'
    assert len({t['id'] for t in out}) == len(out), 'charms_config.lua: item ids must differ'
    return out


def node(stock, cfg):
    """a copy of the stock node (group, flags, every attribute) with the new server id"""
    _s, _e, _sid, _cid, group, flags, attrs = stock
    flags |= FLAG_PICKUPABLE | FLAG_MOVEABLE
    if cfg['stackable']:
        flags |= FLAG_STACKABLE
    else:
        flags &= ~FLAG_STACKABLE
    body = struct.pack('<I', flags)
    for k, v in attrs:
        if k == A_SERVERID:
            v = struct.pack('<H', cfg['id'])
        body += attr(k, v)
    return bytes([START]) + escape(bytes([group])) + escape(body) + bytes([END])


def patch_otb(data, items):
    notes, wanted = [], {}
    out = bytes(data)
    for cfg in items:
        kids, root_end = scan(out)
        by_sid = {k[2]: k for k in kids}
        stock = by_sid.get(cfg['sourceId'])
        if stock is None:
            raise SystemExit('items.otb: no stock node %d (charm item %s source); nothing written' % (cfg['sourceId'], cfg['key']))
        if bool(stock[5] & FLAG_STACKABLE) != cfg['stackable']:
            raise SystemExit('items.otb: stock node %d (charm item %s source) is %sstackable, the item must %sbe; the client '
                             'would misread the count. Pick another source; nothing written'
                             % (cfg['sourceId'], cfg['key'], '' if stock[5] & FLAG_STACKABLE else 'not ',
                                '' if cfg['stackable'] else 'not '))
        want = node(stock, cfg)
        k = by_sid.get(cfg['id'])
        buf = bytearray(out)
        if k is None:
            buf[root_end:root_end] = want
            notes.append('items.otb: %s node added (server id %d, client id %d)' % (cfg['key'], cfg['id'], stock[3]))
        elif k[3] != stock[3]:
            raise SystemExit('items.otb: server id %d already belongs to client id %s, not %d; nothing written'
                             % (cfg['id'], k[3], stock[3]))
        elif out[k[0]:k[1]] != want:
            buf[k[0]:k[1]] = want
            notes.append('items.otb: %s node updated' % cfg['key'])
        else:
            notes.append('items.otb: %s node present' % cfg['key'])
        out = bytes(buf)
        wanted[cfg['key']] = (want, stock[3])
    return out, notes, wanted


def verify_otb(data, items, wanted):
    kids, _ = scan(data)
    by_sid = {k[2]: k for k in kids}
    for cfg in items:
        want, cid = wanted[cfg['key']]
        k = by_sid.get(cfg['id'])
        assert k and k[3] == cid, 'charm item %s node %d' % (cfg['key'], cfg['id'])
        assert bool(k[5] & FLAG_STACKABLE) == cfg['stackable'], 'charm item %s stackable flag' % cfg['key']
        assert data[k[0]:k[1]] == want, 'charm item %s node bytes' % cfg['key']
    sids = [k[2] for k in kids]
    assert len(sids) == len(set(sids)), 'duplicate server ids in items.otb'
    return len(kids)


def xml_block(items):
    body = ''
    for cfg in items:
        body += ('\t<item id="%d" article="%s" name="%s" plural="%s">\n'
                 '\t\t<attribute key="description" value="%s" />\n'
                 '\t\t<attribute key="weight" value="%d" />\n'
                 '\t</item>\n' % (cfg['id'], xml_escape(cfg['article']), xml_escape(cfg['name']),
                                  xml_escape(cfg['plural']), xml_escape(cfg['description']), cfg['weight']))
    return XML_BEGIN + body + XML_END


def patch_xml(text, items):
    block = xml_block(items)
    s = text.find(XML_BEGIN)
    if s >= 0:
        e = text.find(XML_END, s)
        if e < 0:
            raise SystemExit('items.xml: charm start marker without end marker')
        outside = text[:s] + text[e + len(XML_END):]
    else:
        outside = text
    ranges = [(int(a), int(b)) for a, b in re.findall(r'fromid="(\d+)"\s+toid="(\d+)"', outside)]
    for cfg in items:
        sid = cfg['id']
        if re.search(r'<item\s+id="%d"' % sid, outside) or any(a <= sid <= b for a, b in ranges):
            raise SystemExit('items.xml: id %d already has an entry outside the charm block; nothing written' % sid)
    if s >= 0:
        if text[s:e + len(XML_END)] == block:
            return text, 'items.xml: charm block up to date'
        return text[:s] + block + text[e + len(XML_END):], 'items.xml: charm block rewritten'
    end = text.rfind('</items>')
    if end < 0:
        raise SystemExit('items.xml: no </items>')
    return text[:end] + block + text[end:], 'items.xml: charm block added (%d items)' % len(items)


def main():
    args = sys.argv[1:]
    dry = '--dry-run' in args
    args = [a for a in args if not a.startswith('--')]
    if len(args) != 1:
        print(__doc__)
        return 1
    data_dir = args[0]
    items = read_config()
    otb = os.path.join(data_dir, 'items', 'items.otb')
    xml = os.path.join(data_dir, 'items', 'items.xml')
    if not os.path.exists(otb) or not os.path.exists(xml):
        print('items.otb / items.xml not found in', os.path.join(data_dir, 'items'))
        return 1
    raw = open(otb, 'rb').read()
    new, notes, wanted = patch_otb(raw, items)
    n = verify_otb(new, items, wanted)
    for note in notes:
        print(note)
    print('items.otb: verified (%d item nodes; charms %s)' % (n, ', '.join(str(t['id']) for t in items)))
    text = open(xml, encoding='utf-8', errors='surrogateescape').read()
    new_text, xnote = patch_xml(text, items)
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
