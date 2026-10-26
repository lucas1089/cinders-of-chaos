#!/usr/bin/env python3
"""Install the Reward Chest's own look into a base server (server/README.md "Reward chests").

usage: python3 -I install_reward_chest.py DATA_DIR [--dry-run]

Every chest a player takes a reward from (the rift's, the Descent's treasure room, the quest chests of the planned areas
and of the base server's quests) used the stock reward chest (server 21584, client 19250: a gold chest on a stone plinth).
Pair 45 appends a look of its own (client id 38657, client/MANIFEST.md "Reward Chest look"); this step makes the server
item that wears it: server id 32310, "reward chest".

1. data/items/items.otb: a copy of the node of server 21584 (group container, flags, every attribute) with server id 32310
   and client id 38657. Appended at the end of the root; a node already there with the same bytes is left alone, one with
   other bytes is replaced, a server id that belongs to another client id stops the script (nothing is written).
   items.otb.bak keeps the original the first time; the written file is parsed again and the node checked.
2. data/items/items.xml: its entry (article "a", name "reward chest", the attributes of 21584's entry: description,
   container size 32, not pickupable, not moveable) between two marker comments before </items>, rewritten when it
   changed. An id with an entry outside the block stops the script.

The id comes from the free block 32310-32319 (32301-32309 are the charms, 32351-32399 the professions). The configs
(rift_config.lua chest, descent_config.lua objects) fall back to 21584 while the id is not installed; the map step
`rewardchests` (patch_reward_chests.py) refuses to run until the id is in items.otb. A client on a pair before 45 draws
nothing for the new client id: ship pair 45 before this step.

Idempotent: a second run changes nothing.
"""
import os
import re
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from install_gems import scan, escape, attr, xml_escape, START, END, A_SERVERID, A_CLIENTID  # noqa: E402

STOCK_SID = 21584                # the stock reward chest: container, blocks, not moveable, 2x2
RANGE = (32310, 32319)           # reserved for this item
LOOK = (32310, 38657)            # (server id, client id): pair 45, art_import/reward_chest.csv
NAME = 'reward chest'
DEFAULT_ATTRS = (('description', 'This chest contains your rewards earned in battles.'), ('containersize', '32'),
                 ('pickupable', '0'), ('moveable', '0'))
XML_BEGIN = '\t<!-- Chaos Reward Chest look (server/tools/install_reward_chest.py, do not edit by hand) -->\n'
XML_END = '\t<!-- end of the Chaos Reward Chest look -->\n'


def node(stock, sid, cid):
    """a copy of the stock node (group, flags, every attribute) with the new server and client id"""
    _s, _e, _sid, _cid, group, flags, attrs = stock
    body = struct.pack('<I', flags)
    for k, v in attrs:
        if k == A_SERVERID:
            v = struct.pack('<H', sid)
        elif k == A_CLIENTID:
            v = struct.pack('<H', cid)
        body += attr(k, v)
    return bytes([START]) + escape(bytes([group])) + escape(body) + bytes([END])


def patch_otb(data):
    sid, cid = LOOK
    assert RANGE[0] <= sid <= RANGE[1], sid
    kids, root_end = scan(data)
    by_sid = {k[2]: k for k in kids}
    stock = by_sid.get(STOCK_SID)
    if stock is None:
        raise SystemExit('items.otb: no stock node %d (the reward chest); nothing written' % STOCK_SID)
    want = node(stock, sid, cid)
    k = by_sid.get(sid)
    buf = bytearray(data)
    if k is None:
        buf[root_end:root_end] = want
        note = 'items.otb: %s added (server id %d, client id %d)' % (NAME, sid, cid)
    elif k[3] != cid:
        raise SystemExit('items.otb: server id %d already belongs to client id %s, not %d; nothing written'
                         % (sid, k[3], cid))
    elif data[k[0]:k[1]] != want:
        buf[k[0]:k[1]] = want
        note = 'items.otb: %s %d updated' % (NAME, sid)
    else:
        note = 'items.otb: %s %d present' % (NAME, sid)
    return bytes(buf), [note], want


def verify_otb(data, want):
    sid, cid = LOOK
    kids, _ = scan(data)
    by_sid = {k[2]: k for k in kids}
    k = by_sid.get(sid)
    stock = by_sid[STOCK_SID]
    assert k and k[3] == cid and data[k[0]:k[1]] == want, 'reward chest node %d' % sid
    assert k[4] == stock[4] and k[5] == stock[5], 'reward chest %d keeps the stock group and flags' % sid
    sids = [x[2] for x in kids]
    assert len(sids) == len(set(sids)), 'duplicate server ids in items.otb'
    return len(kids)


def stock_attrs(text):
    """[(key, value)] of the stock entry's attributes (id= or fromid= / toid= form), else the defaults"""
    for m in re.finditer(r'<item\s+(?:id="(\d+)"|fromid="(\d+)"\s+toid="(\d+)")[^>]*?(?:/>|>(.*?)</item>)', text, re.S):
        if m.group(1) and int(m.group(1)) == STOCK_SID or m.group(2) and int(m.group(2)) <= STOCK_SID <= int(m.group(3)):
            found = re.findall(r'<attribute\s+key="([^"]*)"\s+value="([^"]*)"', m.group(4) or '')
            if found:
                return found
    return list(DEFAULT_ATTRS)


def xml_block(attrs):
    sid = LOOK[0]
    body = '\t<item id="%d" article="a" name="%s">\n' % (sid, xml_escape(NAME))
    for k, v in attrs:
        body += '\t\t<attribute key="%s" value="%s" />\n' % (k, v)
    body += '\t</item>\n'
    return XML_BEGIN + body + XML_END


def patch_xml(text):
    s = text.find(XML_BEGIN)
    if s >= 0:
        e = text.find(XML_END, s)
        if e < 0:
            raise SystemExit('items.xml: Reward Chest start marker without end marker')
        outside = text[:s] + text[e + len(XML_END):]
    else:
        outside = text
    block = xml_block(stock_attrs(outside))
    sid = LOOK[0]
    ranges = [(int(a), int(b)) for a, b in re.findall(r'fromid="(\d+)"\s+toid="(\d+)"', outside)]
    if re.search(r'<item\s+id="%d"' % sid, outside) or any(a <= sid <= b for a, b in ranges):
        raise SystemExit('items.xml: id %d already has an entry outside the Reward Chest block; nothing written' % sid)
    if s >= 0:
        if text[s:e + len(XML_END)] == block:
            return text, 'items.xml: Reward Chest block up to date'
        return text[:s] + block + text[e + len(XML_END):], 'items.xml: Reward Chest block rewritten'
    end = text.rfind('</items>')
    if end < 0:
        raise SystemExit('items.xml: no </items>')
    return text[:end] + block + text[end:], 'items.xml: Reward Chest block added'


def main(argv):
    dry = '--dry-run' in argv
    args = [a for a in argv if not a.startswith('--')]
    if len(args) != 1:
        print(__doc__)
        return 1
    otb = os.path.join(args[0], 'items', 'items.otb')
    xml = os.path.join(args[0], 'items', 'items.xml')
    if not os.path.exists(otb) or not os.path.exists(xml):
        print('items.otb / items.xml not found in', args[0])
        return 1
    raw = open(otb, 'rb').read()
    new, notes, want = patch_otb(raw)
    n = verify_otb(new, want)
    for note in notes:
        print(note)
    print('items.otb: verified (%d item nodes)' % n)
    text = open(xml, encoding='utf-8', errors='surrogateescape').read()
    new_text, xnote = patch_xml(text)
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
    sys.exit(main(sys.argv[1:]))
