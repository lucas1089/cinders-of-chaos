#!/usr/bin/env python3
"""Install the base server parts of the Haunted Harvest (server/data/scripts/chaos/harvest_event*.lua; server/README.md
"Haunted Harvest"): its four items and its NPC.

usage: python3 -I install_harvest_event.py DATA_DIR [--dry-run]

1. data/items/items.otb: per row of server/data/items/harvest_items.csv a copy of the stock node `source_id` with the
   server id `id` (41620 hollow candy: the stock candy, stackable; 41621 sexton's key: the bone key; 41622 ritual candle:
   the candlestick; 41623 hollow charm: the ghost charm). The client ids stay the stock ones and so do the flags
   (stackable as the client's dat says), so the client needs no change and no pair. Appended at the end of the root; a
   node already there with the same bytes is left alone, one with other bytes (a changed csv) is replaced, a server id
   that belongs to another client id stops the script (nothing is written). items.otb.bak keeps the original the
   first time; the written file is parsed again and the nodes checked.
2. data/items/items.xml: the entries (article, name, plural, weight, description) between two marker comments before
   </items>, rewritten when the csv changed. An id with an entry outside the block stops the script.
3. data/npc: Widow Hessa's XML (server/data/npc/Widow Hessa.xml) and her script (only new or different files). She
   stands in the event area's camp (the plan's `npcs`, placed with the area by install step contentareas).

The items work without the pair 33 switch (they are stock looks); nothing gives them while the event is shut.
Idempotent: a second run changes nothing.
"""
import csv, os, re, struct, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from install_gems import scan, escape, attr, xml_escape, START, END, A_SERVERID  # noqa: E402
import install_gamble  # noqa: E402

SERVER = os.path.dirname(HERE)
CSV = os.path.join(SERVER, 'data', 'items', 'harvest_items.csv')
NPC = 'Widow Hessa'
XML_BEGIN = '\t<!-- Chaos Haunted Harvest items (server/tools/install_harvest_event.py, do not edit by hand) -->\n'
XML_END = '\t<!-- end of the Chaos Haunted Harvest items -->\n'
RANGE = (41620, 41639)


def read_items(path=CSV):
    rows = list(csv.DictReader(open(path, newline='', encoding='utf-8')))
    for r in rows:
        r['id'], r['source_id'], r['weight'] = int(r['id']), int(r['source_id']), int(r['weight'])
        assert RANGE[0] <= r['id'] <= RANGE[1], '%s: id %d outside %s' % (r['key'], r['id'], RANGE)
        assert r['name'] and r['description'], '%s: name and description' % r['key']
    ids = [r['id'] for r in rows]
    assert len(ids) == len(set(ids)), 'harvest_items.csv: an id twice'
    return rows


def node(stock, sid):
    """a copy of the stock node (group, flags, every attribute) with the new server id"""
    _s, _e, _sid, _cid, group, flags, attrs = stock
    body = struct.pack('<I', flags)
    for k, v in attrs:
        if k == A_SERVERID:
            v = struct.pack('<H', sid)
        body += attr(k, v)
    return bytes([START]) + escape(bytes([group])) + escape(body) + bytes([END])


def patch_otb(data, rows):
    notes, wanted = [], {}
    out = bytes(data)
    for r in rows:
        kids, root_end = scan(out)
        by_sid = {k[2]: k for k in kids}
        stock = by_sid.get(r['source_id'])
        if stock is None:
            raise SystemExit('items.otb: no stock node %d (source of %s); nothing written' % (r['source_id'], r['name']))
        want = node(stock, r['id'])
        k = by_sid.get(r['id'])
        buf = bytearray(out)
        if k is None:
            buf[root_end:root_end] = want
            notes.append('items.otb: %s added (server id %d, client id %d)' % (r['name'], r['id'], stock[3]))
        elif k[3] != stock[3]:
            raise SystemExit('items.otb: server id %d already belongs to client id %s, not %d; nothing written'
                             % (r['id'], k[3], stock[3]))
        elif out[k[0]:k[1]] != want:
            buf[k[0]:k[1]] = want
            notes.append('items.otb: %s updated' % r['name'])
        else:
            notes.append('items.otb: %s present' % r['name'])
        out = bytes(buf)
        wanted[r['id']] = (want, stock[3])
    return out, notes, wanted


def verify_otb(data, wanted):
    kids, _ = scan(data)
    by_sid = {k[2]: k for k in kids}
    for sid, (want, cid) in wanted.items():
        k = by_sid.get(sid)
        assert k and k[3] == cid and data[k[0]:k[1]] == want, 'harvest item node %d' % sid
    sids = [k[2] for k in kids]
    assert len(sids) == len(set(sids)), 'duplicate server ids in items.otb'
    return len(kids)


def xml_block(rows):
    body = ''
    for r in rows:
        plural = ' plural="%s"' % xml_escape(r['plural']) if r['plural'] else ''
        body += ('\t<item id="%d" article="%s" name="%s"%s>\n'
                 '\t\t<attribute key="description" value="%s" />\n'
                 '\t\t<attribute key="weight" value="%d" />\n'
                 '\t</item>\n' % (r['id'], xml_escape(r['article']), xml_escape(r['name']), plural,
                                  xml_escape(r['description']), r['weight']))
    return XML_BEGIN + body + XML_END


def patch_xml(text, rows):
    block = xml_block(rows)
    s = text.find(XML_BEGIN)
    if s >= 0:
        e = text.find(XML_END, s)
        if e < 0:
            raise SystemExit('items.xml: Haunted Harvest start marker without end marker')
        outside = text[:s] + text[e + len(XML_END):]
    else:
        outside = text
    ranges = [(int(a), int(b)) for a, b in re.findall(r'fromid="(\d+)"\s+toid="(\d+)"', outside)]
    for r in rows:
        sid = r['id']
        if re.search(r'<item\s+id="%d"' % sid, outside) or any(a <= sid <= b for a, b in ranges):
            raise SystemExit('items.xml: id %d already has an entry outside the Haunted Harvest block; nothing written' % sid)
    if s >= 0:
        if text[s:e + len(XML_END)] == block:
            return text, 'items.xml: Haunted Harvest block up to date (%d items)' % len(rows)
        return text[:s] + block + text[e + len(XML_END):], 'items.xml: Haunted Harvest block rewritten (%d items)' % len(rows)
    end = text.rfind('</items>')
    if end < 0:
        raise SystemExit('items.xml: no </items>')
    return text[:end] + block + text[end:], 'items.xml: Haunted Harvest block added (%d items)' % len(rows)


def main():
    args = sys.argv[1:]
    dry = '--dry-run' in args
    args = [a for a in args if not a.startswith('--')]
    if len(args) != 1:
        print(__doc__)
        return 1
    data_dir = args[0]
    otb = os.path.join(data_dir, 'items', 'items.otb')
    xml = os.path.join(data_dir, 'items', 'items.xml')
    if not os.path.exists(otb) or not os.path.exists(xml) or not os.path.isdir(os.path.join(data_dir, 'npc')):
        print('items.otb / items.xml / npc not found in', data_dir)
        return 1
    rows = read_items()
    raw = open(otb, 'rb').read()
    new, notes, wanted = patch_otb(raw, rows)
    n = verify_otb(new, wanted)
    for note in notes:
        print(note)
    print('items.otb: verified (%d item nodes)' % n)
    text = open(xml, encoding='utf-8', errors='surrogateescape').read()
    new_text, xnote = patch_xml(text, rows)
    print(xnote)
    for note in install_gamble.copy_npc(data_dir, NPC, dry):
        print(note)
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
