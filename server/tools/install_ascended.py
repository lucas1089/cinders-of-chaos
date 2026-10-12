#!/usr/bin/env python3
"""Install the items of the Ascended Omens and the Cinderheart (uber.lua) into a base server: five items.otb nodes and
five items.xml entries.

usage: python3 -I install_ascended.py DATA_DIR [--dry-run]

Everything is read from server/data/scripts/chaos/uber_config.lua (`items`: shards.bloodmoon / hollow / storm, sigil,
relic: id, sourceId, name, plural, article, weight, description), the same file the Lua side uses.

1. data/items/items.otb: per item a copy of the stock node `sourceId` with the server id `id` (the three Ascended
   Shards 32073..32075: magma clump, violet and blue crystal shard, stackable; the sigil 32076: soul stone and the relic
   32077: burning heart, not stackable: they carry the custom attribute ascended_kind). Their client ids stay the
   stock ones, so the client needs no change. The nodes are appended at the end of the root; a node already there with
   the same bytes is left alone, one with other bytes (a changed config) is replaced, and a server id that belongs to
   another client id stops the script (nothing is written). items.otb.bak keeps the original the first time; the
   written file is parsed again and the nodes checked. (Ranges in use: see install_omens.py; omens 32071..32072,
   Ascended 32073..32077, pouches 32081..32083.)
2. data/items/items.xml: the entries (name, plural, description, weight) between two marker comments before </items>,
   rewritten when the config changed. An id that already has an entry outside the block stops the script.

Idempotent: a second run changes nothing.
"""
import os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from install_gems import scan, xml_escape, FLAG_STACKABLE  # noqa: E402
from install_omens import node  # noqa: E402

CONFIG = os.path.join(os.path.dirname(HERE), 'data', 'scripts', 'chaos', 'uber_config.lua')
XML_BEGIN = '\t<!-- Chaos Ascended Omens: shards, sigil, relic (server/tools/install_ascended.py, do not edit by hand) -->\n'
XML_END = '\t<!-- end of the Chaos Ascended items -->\n'


def _entry(body):
    def num(key):
        return int(re.search(r'\b%s\s*=\s*(\d+)' % key, body).group(1))

    def string(key):
        return re.search(r'\b%s\s*=\s*"([^"]*)"' % key, body).group(1)
    return {'id': num('id'), 'sourceId': num('sourceId'), 'weight': num('weight'), 'name': string('name'),
            'plural': string('plural'), 'article': string('article'), 'description': string('description')}


def read_config(path=CONFIG):
    """the five items in a fixed order: [(key, cfg), ...]"""
    text = open(path, encoding='utf-8').read()
    block = re.search(r'\n\titems = \{(.*?)\n\t\},\n', text, re.S).group(1)
    out = []
    shards = re.search(r'shards = \{(.*?)\n\t\t\},', block, re.S).group(1)
    for kind in ('bloodmoon', 'hollow', 'storm'):
        body = re.search(r'\b%s = \{(.*?)\}' % kind, shards, re.S).group(1)
        cfg = _entry(body)
        cfg['stackable'] = True
        out.append(('shard_' + kind, cfg))
    for key in ('sigil', 'relic'):
        body = re.search(r'\n\t\t%s = \{(.*?)\}' % key, block, re.S).group(1)
        cfg = _entry(body)
        cfg['stackable'] = False
        out.append((key, cfg))
    ids = [c['id'] for _, c in out]
    assert len(set(ids)) == len(ids), 'uber_config.lua: the Ascended items need five ids'
    return out


def patch_otb(data, items):
    notes, wanted = [], {}
    out = bytes(data)
    for name, cfg in items:
        kids, root_end = scan(out)
        by_sid = {k[2]: k for k in kids}
        stock = by_sid.get(cfg['sourceId'])
        if stock is None:
            raise SystemExit('items.otb: no stock node %d (%s source); nothing written' % (cfg['sourceId'], name))
        want = node(stock, cfg)
        k = by_sid.get(cfg['id'])
        buf = bytearray(out)
        if k is None:
            buf[root_end:root_end] = want
            notes.append('items.otb: %s node added (server id %d, client id %d)' % (name, cfg['id'], stock[3]))
        elif k[3] != stock[3]:
            raise SystemExit('items.otb: server id %d already belongs to client id %s, not %d; nothing written'
                             % (cfg['id'], k[3], stock[3]))
        elif out[k[0]:k[1]] != want:
            buf[k[0]:k[1]] = want
            notes.append('items.otb: %s node updated' % name)
        else:
            notes.append('items.otb: %s node present' % name)
        out = bytes(buf)
        wanted[name] = (want, stock[3])
    return out, notes, wanted


def verify_otb(data, items, wanted):
    kids, _ = scan(data)
    by_sid = {k[2]: k for k in kids}
    for name, cfg in items:
        want, cid = wanted[name]
        k = by_sid.get(cfg['id'])
        assert k and k[3] == cid, '%s node %d' % (name, cfg['id'])
        assert bool(k[5] & FLAG_STACKABLE) == cfg['stackable'], '%s stackable flag' % name
        assert data[k[0]:k[1]] == want, '%s node bytes' % name
    sids = [k[2] for k in kids]
    assert len(sids) == len(set(sids)), 'duplicate server ids in items.otb'
    return len(kids)


def xml_block(items):
    body = ''
    for _name, cfg in items:
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
            raise SystemExit('items.xml: Ascended start marker without end marker')
        outside = text[:s] + text[e + len(XML_END):]
    else:
        outside = text
    ranges = [(int(a), int(b)) for a, b in re.findall(r'fromid="(\d+)"\s+toid="(\d+)"', outside)]
    for name, cfg in items:
        sid = cfg['id']
        if re.search(r'<item\s+id="%d"' % sid, outside) or any(a <= sid <= b for a, b in ranges):
            raise SystemExit('items.xml: id %d already has an entry outside the Ascended block; nothing written' % sid)
    if s >= 0:
        if text[s:e + len(XML_END)] == block:
            return text, 'items.xml: Ascended block up to date'
        return text[:s] + block + text[e + len(XML_END):], 'items.xml: Ascended block rewritten'
    end = text.rfind('</items>')
    if end < 0:
        raise SystemExit('items.xml: no </items>')
    return text[:end] + block + text[end:], 'items.xml: Ascended block added (3 shards, the sigil, the relic)'


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
    print('items.otb: verified (%d item nodes; Ascended items %s)' % (n, ', '.join(str(c['id']) for _, c in items)))
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
