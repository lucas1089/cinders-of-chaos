#!/usr/bin/env python3
"""Install the omen items of the rifts (the Omen Fragment and the Omen Key) into a base server: two items.otb nodes and
two items.xml entries.

usage: python3 -I install_omens.py DATA_DIR [--dry-run]

Everything is read from server/data/scripts/chaos/rift_config.lua (`omen.fragment` and `omen.key`: id, sourceId,
article, name, plural, weight, description), the same file the Lua side uses.

1. data/items/items.otb: per item a copy of the stock node `sourceId` with the server id `id` (fragment 32071: the red
   crystal fragment, stackable; key 32072: the eye of the storm, not stackable: it carries the custom attribute
   omen_kind). Their client ids stay the stock ones, so the client needs no change. The nodes are appended at the end
   of the root; a node already there with the same bytes is left alone, one with other bytes (a changed config) is
   replaced, and a server id that belongs to another client id stops the script (nothing is written). items.otb.bak
   keeps the original the first time; the written file is parsed again and the nodes checked.
   Ranges in use: gems 32001..32035, salvage 32051, omens 32071..32072, supports 32101..32200, Everfull
   tiers 32261..32267 (install_potions.py), dark tiles
   30484..30557, art 33000.., pack items 36000.., donor items 40000...
2. data/items/items.xml: the entries (name, plural, description, weight) between two marker comments before </items>,
   rewritten when the config changed. An id that already has an entry outside the block stops the script.

Idempotent: a second run changes nothing.
"""
import os, re, struct, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from install_gems import scan, escape, attr, xml_escape, START, END, A_SERVERID, FLAG_STACKABLE, FLAG_PICKUPABLE, FLAG_MOVEABLE  # noqa: E402

CONFIG = os.path.join(os.path.dirname(HERE), 'data', 'scripts', 'chaos', 'rift_config.lua')
XML_BEGIN = '\t<!-- Chaos rifts: the omen items (server/tools/install_omens.py, do not edit by hand) -->\n'
XML_END = '\t<!-- end of the Chaos omen items -->\n'
NAMES = ('fragment', 'key')


def read_config(path=CONFIG):
    text = open(path, encoding='utf-8').read()
    omen = re.search(r'\n\tomen = \{(.*?)\n\t\}', text, re.S).group(1)
    out = {}
    for name in NAMES:
        block = re.search(r'\b%s\s*=\s*\{(.*?)\}' % name, omen, re.S).group(1)

        def num(key):
            return int(re.search(r'\b%s\s*=\s*(\d+)' % key, block).group(1))

        def string(key):
            m = re.search(r'\b%s\s*=\s*((?:"[^"]*"\s*(?:\.\.\s*)?)+)' % key, block, re.S)
            return ''.join(re.findall(r'"([^"]*)"', m.group(1)))

        cfg = {'id': num('id'), 'sourceId': num('sourceId'), 'weight': num('weight'), 'name': string('name'),
               'plural': string('plural'), 'article': string('article'), 'description': string('description'),
               'stackable': name == 'fragment'}
        assert cfg['id'] > 0 and cfg['sourceId'] > 0 and cfg['name'], 'rift_config.lua: omen.%s incomplete' % name
        out[name] = cfg
    assert out['fragment']['id'] != out['key']['id'], 'rift_config.lua: the omen items need two ids'
    return out


def node(stock, cfg):
    """a copy of the stock node (group, flags, every attribute) with the new server id; stackable or not by cfg"""
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
    for name in NAMES:
        cfg = items[name]
        kids, root_end = scan(out)
        by_sid = {k[2]: k for k in kids}
        stock = by_sid.get(cfg['sourceId'])
        if stock is None:
            raise SystemExit('items.otb: no stock node %d (omen %s source); nothing written' % (cfg['sourceId'], name))
        want = node(stock, cfg)
        k = by_sid.get(cfg['id'])
        buf = bytearray(out)
        if k is None:
            buf[root_end:root_end] = want
            notes.append('items.otb: omen %s node added (server id %d, client id %d)' % (name, cfg['id'], stock[3]))
        elif k[3] != stock[3]:
            raise SystemExit('items.otb: server id %d already belongs to client id %s, not %d; nothing written'
                             % (cfg['id'], k[3], stock[3]))
        elif out[k[0]:k[1]] != want:
            buf[k[0]:k[1]] = want
            notes.append('items.otb: omen %s node updated' % name)
        else:
            notes.append('items.otb: omen %s node present' % name)
        out = bytes(buf)
        wanted[name] = (want, stock[3])
    return out, notes, wanted


def verify_otb(data, items, wanted):
    kids, _ = scan(data)
    by_sid = {k[2]: k for k in kids}
    for name in NAMES:
        cfg = items[name]
        want, cid = wanted[name]
        k = by_sid.get(cfg['id'])
        assert k and k[3] == cid, 'omen %s node %d' % (name, cfg['id'])
        assert bool(k[5] & FLAG_STACKABLE) == cfg['stackable'], 'omen %s stackable flag' % name
        assert data[k[0]:k[1]] == want, 'omen %s node bytes' % name
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
                 '\t</item>\n' % (cfg['id'], xml_escape(cfg['article']), xml_escape(cfg['name']),
                                  xml_escape(cfg['plural']), xml_escape(cfg['description']), cfg['weight']))
    return XML_BEGIN + body + XML_END


def patch_xml(text, items):
    block = xml_block(items)
    s = text.find(XML_BEGIN)
    if s >= 0:
        e = text.find(XML_END, s)
        if e < 0:
            raise SystemExit('items.xml: omen start marker without end marker')
        outside = text[:s] + text[e + len(XML_END):]
    else:
        outside = text
    ranges = [(int(a), int(b)) for a, b in re.findall(r'fromid="(\d+)"\s+toid="(\d+)"', outside)]
    for name in NAMES:
        sid = items[name]['id']
        if re.search(r'<item\s+id="%d"' % sid, outside) or any(a <= sid <= b for a, b in ranges):
            raise SystemExit('items.xml: id %d already has an entry outside the omen block; nothing written' % sid)
    if s >= 0:
        if text[s:e + len(XML_END)] == block:
            return text, 'items.xml: omen block up to date'
        return text[:s] + block + text[e + len(XML_END):], 'items.xml: omen block rewritten'
    end = text.rfind('</items>')
    if end < 0:
        raise SystemExit('items.xml: no </items>')
    return text[:end] + block + text[end:], 'items.xml: omen block added (the Omen Fragment and the Omen Key)'


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
    print('items.otb: verified (%d item nodes; omen fragment %d stackable, omen key %d not)'
          % (n, items['fragment']['id'], items['key']['id']))
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
