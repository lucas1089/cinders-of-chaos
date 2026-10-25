#!/usr/bin/env python3
"""Install the Cursed Chest's three own looks into a base server (server/README.md "Cursed Chest").

usage: python3 -I install_cursed_chest.py DATA_DIR [--dry-run]

The Cursed Chest used the Sealed Coffer's chest (server 12664, client 4073). Pair 43 appends three looks of its own
(client ids 38642-38644, client/MANIFEST.md "Cursed Chest looks"); each chest that spawns shows one of them at random
(data/scripts/chaos/cursedchest_config.lua `chest.itemIds`).

1. data/items/items.otb: per look a copy of the node of server 12664 (group container, flags, every attribute) with
   server id 32281 / 32282 / 32283 and client id 38642 / 38643 / 38644. Appended at the end of the root; a node already
   there with the same bytes is left alone, one with other bytes is replaced, a server id that belongs to another
   client id stops the script (nothing is written). items.otb.bak keeps the original the first time; the written file
   is parsed again and the nodes checked.
2. data/items/items.xml: their entries (article "a", name "cursed chest", the container size of 12664's entry) between
   two marker comments before </items>, rewritten when they changed. An id with an entry outside the block stops the
   script.

The ids come from the free block 32281-32299 (32251-32267 are the orbs and potions, 32268-32280 stay free). The
config falls back to 12664 while the ids are not installed. A client on a pair before 43 draws nothing for the new
client ids: ship pair 43 before this step.

Idempotent: a second run changes nothing.
"""
import os
import re
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from install_gems import scan, escape, attr, xml_escape, START, END, A_SERVERID, A_CLIENTID  # noqa: E402

STOCK_SID = 12664                # the Sealed Coffer's treasure chest: container, blocks, not moveable, 2x2
RANGE = (32281, 32299)           # reserved for this item set
# (server id, client id, animated): pair 43, art_import/cursed_chest.csv. A (5 phases) and C (8 phases) idle-animate; B is a
# still. An animated node carries FLAG_ANIMATION, so the server sends the phase byte the client reads for the item.
LOOKS = ((32281, 38642, True), (32282, 38643, False), (32283, 38644, True))
FLAG_ANIMATION = 1 << 24
NAME = 'cursed chest'
DEFAULT_SIZE = 20                # containerSize of the stock entry (the base items.xml: 12664-12665 "treasure chest")
XML_BEGIN = '\t<!-- Chaos Cursed Chest looks (server/tools/install_cursed_chest.py, do not edit by hand) -->\n'
XML_END = '\t<!-- end of the Chaos Cursed Chest looks -->\n'


def node(stock, sid, cid, animated=False):
    """a copy of the stock node (group, flags, every attribute) with the new server and client id"""
    _s, _e, _sid, _cid, group, flags, attrs = stock
    if animated:
        flags |= FLAG_ANIMATION
    body = struct.pack('<I', flags)
    for k, v in attrs:
        if k == A_SERVERID:
            v = struct.pack('<H', sid)
        elif k == A_CLIENTID:
            v = struct.pack('<H', cid)
        body += attr(k, v)
    return bytes([START]) + escape(bytes([group])) + escape(body) + bytes([END])


def patch_otb(data):
    notes, wanted = [], {}
    out = bytes(data)
    for sid, cid, anim in LOOKS:
        assert RANGE[0] <= sid <= RANGE[1], sid
        kids, root_end = scan(out)
        by_sid = {k[2]: k for k in kids}
        stock = by_sid.get(STOCK_SID)
        if stock is None:
            raise SystemExit('items.otb: no stock node %d (the Sealed Coffer chest); nothing written' % STOCK_SID)
        want = node(stock, sid, cid, anim)
        k = by_sid.get(sid)
        buf = bytearray(out)
        if k is None:
            buf[root_end:root_end] = want
            notes.append('items.otb: %s added (server id %d, client id %d)' % (NAME, sid, cid))
        elif k[3] != cid:
            raise SystemExit('items.otb: server id %d already belongs to client id %s, not %d; nothing written'
                             % (sid, k[3], cid))
        elif out[k[0]:k[1]] != want:
            buf[k[0]:k[1]] = want
            notes.append('items.otb: %s %d updated' % (NAME, sid))
        else:
            notes.append('items.otb: %s %d present' % (NAME, sid))
        out = bytes(buf)
        wanted[sid] = (want, cid, anim)
    return out, notes, wanted


def verify_otb(data, wanted):
    kids, _ = scan(data)
    by_sid = {k[2]: k for k in kids}
    for sid, (want, cid, anim) in wanted.items():
        k = by_sid.get(sid)
        assert k and k[3] == cid and data[k[0]:k[1]] == want, 'cursed chest node %d' % sid
        assert k[4] == by_sid[STOCK_SID][4] and k[5] == by_sid[STOCK_SID][5] | (FLAG_ANIMATION if anim else 0), \
            'cursed chest %d keeps the stock group and flags (animated: %s)' % (sid, anim)
    sids = [k[2] for k in kids]
    assert len(sids) == len(set(sids)), 'duplicate server ids in items.otb'
    return len(kids)


def container_size(text):
    """containerSize of the stock entry (id= or fromid= / toid= form), else the default"""
    for m in re.finditer(r'<item\s+(?:id="(\d+)"|fromid="(\d+)"\s+toid="(\d+)")[^>]*?(?:/>|>(.*?)</item>)', text, re.S):
        if m.group(1) and int(m.group(1)) == STOCK_SID or m.group(2) and int(m.group(2)) <= STOCK_SID <= int(m.group(3)):
            s = re.search(r'key="containerSize"\s+value="(\d+)"', m.group(4) or '')
            if s:
                return int(s.group(1))
    return DEFAULT_SIZE


def xml_block(size):
    body = ''
    for sid, _cid, _a in LOOKS:
        body += ('\t<item id="%d" article="a" name="%s">\n'
                 '\t\t<attribute key="containerSize" value="%d" />\n'
                 '\t</item>\n' % (sid, xml_escape(NAME), size))
    return XML_BEGIN + body + XML_END


def patch_xml(text):
    s = text.find(XML_BEGIN)
    if s >= 0:
        e = text.find(XML_END, s)
        if e < 0:
            raise SystemExit('items.xml: Cursed Chest start marker without end marker')
        outside = text[:s] + text[e + len(XML_END):]
    else:
        outside = text
    block = xml_block(container_size(outside))
    ranges = [(int(a), int(b)) for a, b in re.findall(r'fromid="(\d+)"\s+toid="(\d+)"', outside)]
    for sid, _cid, _a in LOOKS:
        if re.search(r'<item\s+id="%d"' % sid, outside) or any(a <= sid <= b for a, b in ranges):
            raise SystemExit('items.xml: id %d already has an entry outside the Cursed Chest block; nothing written' % sid)
    if s >= 0:
        if text[s:e + len(XML_END)] == block:
            return text, 'items.xml: Cursed Chest block up to date (%d items)' % len(LOOKS)
        return text[:s] + block + text[e + len(XML_END):], 'items.xml: Cursed Chest block rewritten'
    end = text.rfind('</items>')
    if end < 0:
        raise SystemExit('items.xml: no </items>')
    return text[:end] + block + text[end:], 'items.xml: Cursed Chest block added (%d items)' % len(LOOKS)


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
    new, notes, wanted = patch_otb(raw)
    n = verify_otb(new, wanted)
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
