#!/usr/bin/env python3
"""Install the dark tile set into a base server: one items.otb node and one items.xml entry per tile.

usage: python3 -I install_dark_tiles.py DATA_DIR [--dry-run] [--manifest CSV]

The tiles are drawn by client/tools/sprites/gen_dark_tiles.py, which appends them to the client Tibia.dat / Tibia.spr
at client ids 27484.. and writes the manifest server/data/items/dark_tiles.csv (the default --manifest). Server id =
client id + 3000 (30484..). Without the matching client pair the items show as nothing in the client, so install both.

1. data/items/items.otb: a node per manifest row (group ground or none, flags: blocking, always-on-top for borders /
   walls / pillars, animation; attributes: server id, client id, ground speed, light, top order). Nodes are appended at
   the end of the root. A node already there with the same bytes is left alone; one with other bytes (an older
   manifest) is replaced; a server id that belongs to a different client id stops the script (nothing is written).
   A copy of the original file is kept as items.otb.bak the first time. After writing, the file is parsed again and
   every node is checked.
2. data/items/items.xml: one <item id=.. name=..> per row inside a block between two marker comments, before
   </items>. The block is rewritten when the manifest changed. An id that already has an entry outside the block
   stops the script.

Idempotent: a second run changes nothing. Lua side: data/lib/chaos_dark_tiles.lua (ChaosDarkTiles.id(name, fallback)
returns the fallback while the items are not installed).
"""
import csv, os, re, struct, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from item_wire_table import adjust_rows  # noqa: E402
DEFAULT_MANIFEST = os.path.join(os.path.dirname(HERE), 'data', 'items', 'dark_tiles.csv')
ESC, START, END = 0xFD, 0xFE, 0xFF
A_SERVERID, A_CLIENTID, A_SPEED, A_LIGHT2, A_TOPORDER = 0x10, 0x11, 0x14, 0x2A, 0x2B
XML_BEGIN = '\t<!-- Chaos dark tile set (server/tools/install_dark_tiles.py, do not edit by hand) -->\n'
XML_END = '\t<!-- end of the Chaos dark tile set -->\n'


def read_manifest(path):
    with open(path, newline='') as fh:
        rows = list(csv.DictReader(fh))
    for r in rows:
        for k in ('client_id', 'server_id', 'speed', 'otb_group', 'otb_flags', 'top_order', 'light_level', 'light_color'):
            r[k] = int(r[k])
    return adjust_rows(rows)   # the nodes the client pair needs other wire bytes for (item_wire_table.py)


def escape(data):
    out = bytearray()
    for b in data:
        if b in (ESC, START, END):
            out.append(ESC)
        out.append(b)
    return bytes(out)


def attr(kind, payload):
    return bytes([kind]) + struct.pack('<H', len(payload)) + payload


def node_bytes(r):
    """the full node: START, group, escaped(flags + attributes), END"""
    body = struct.pack('<I', r['otb_flags'])
    body += attr(A_SERVERID, struct.pack('<H', r['server_id']))
    body += attr(A_CLIENTID, struct.pack('<H', r['client_id']))
    if r['otb_group'] == 1:
        body += attr(A_SPEED, struct.pack('<H', r['speed']))
    if r['light_level']:
        body += attr(A_LIGHT2, struct.pack('<HH', r['light_level'], r['light_color']))
    if r['top_order']:
        body += attr(A_TOPORDER, bytes([r['top_order']]))
    return bytes([START]) + escape(bytes([r['otb_group']])) + escape(body) + bytes([END])


def scan(data):
    """root children of an items.otb: list of (start, end, server id, client id, group, flags); root end offset"""
    assert data[4] == START, 'not an items.otb (no root node)'
    i = 6
    # root props: escaped bytes up to the first child START
    while data[i] != START:
        i += 2 if data[i] == ESC else 1
    kids = []
    while data[i] == START:
        s = i
        i += 1
        props = bytearray()
        depth = 0
        while True:
            b = data[i]
            if b == ESC:
                if depth == 0:
                    props.append(data[i + 1])
                i += 2
            elif b == START:
                depth += 1; i += 1
            elif b == END:
                i += 1
                if depth == 0:
                    break
                depth -= 1
            else:
                if depth == 0:
                    props.append(b)
                i += 1
        group = props[0]
        flags = struct.unpack_from('<I', props, 1)[0]
        j, sid, cid = 5, None, None
        while j + 3 <= len(props):
            k = props[j]; ln = struct.unpack_from('<H', props, j + 1)[0]
            v = props[j + 3:j + 3 + ln]
            if k == A_SERVERID:
                sid = struct.unpack('<H', v)[0]
            elif k == A_CLIENTID:
                cid = struct.unpack('<H', v)[0]
            j += 3 + ln
        kids.append((s, i, sid, cid, group, flags))
    assert data[i] == END, 'unexpected byte after the item nodes'
    return kids, i


def patch_otb(data, rows):
    kids, root_end = scan(data)
    by_sid = {k[2]: k for k in kids}
    notes, replace, append = [], [], []
    for r in rows:
        want = node_bytes(r)
        k = by_sid.get(r['server_id'])
        if k is None:
            append.append(want)
        elif k[3] != r['client_id']:
            raise SystemExit('items.otb: server id %d already belongs to client id %s, not %d; nothing written'
                             % (r['server_id'], k[3], r['client_id']))
        elif data[k[0]:k[1]] != want:
            replace.append((k[0], k[1], want))
    out = bytearray(data)
    for s, e, b in sorted(replace, reverse=True):
        out[s:e] = b
    shift = sum(len(b) - (e - s) for s, e, b in replace)
    at = root_end + shift
    out[at:at] = b''.join(append)
    if replace:
        notes.append('items.otb: %d dark tile nodes updated' % len(replace))
    if append:
        notes.append('items.otb: %d dark tile nodes added (server ids %d..%d)'
                     % (len(append), rows[0]['server_id'], rows[-1]['server_id']))
    if not replace and not append:
        notes.append('items.otb: all %d dark tile nodes present' % len(rows))
    return bytes(out), notes


def verify_otb(data, rows):
    kids, _ = scan(data)
    by_sid = {k[2]: k for k in kids}
    for r in rows:
        k = by_sid.get(r['server_id'])
        assert k and k[3] == r['client_id'] and k[4] == r['otb_group'] and k[5] == r['otb_flags'], r['key']
        assert data[k[0]:k[1]] == node_bytes(r), r['key']
    sids = [k[2] for k in kids]
    assert len(sids) == len(set(sids)), 'duplicate server ids in items.otb'
    return len(kids)


def xml_escape(s):
    return s.replace('&', '&amp;').replace('"', '&quot;').replace('<', '&lt;').replace('>', '&gt;')


def xml_block(rows):
    lines = [XML_BEGIN]
    for r in rows:
        lines.append('\t<item id="%d" name="%s" />\n' % (r['server_id'], xml_escape(r['name'])))
    lines.append(XML_END)
    return ''.join(lines)


def patch_xml(text, rows):
    block = xml_block(rows)
    s = text.find(XML_BEGIN)
    if s >= 0:
        e = text.find(XML_END, s)
        if e < 0:
            raise SystemExit('items.xml: dark tile start marker without end marker')
        outside = text[:s] + text[e + len(XML_END):]
    else:
        outside = text
    ranges = [(int(a), int(b)) for a, b in re.findall(r'fromid="(\d+)"\s+toid="(\d+)"', outside)]
    for r in rows:
        sid = r['server_id']
        if re.search(r'<item\s+id="%d"' % sid, outside) or any(a <= sid <= b for a, b in ranges):
            raise SystemExit('items.xml: id %d already has an entry outside the dark tile block; nothing written' % sid)
    if s >= 0:
        if text[s:e + len(XML_END)] == block:
            return text, 'items.xml: dark tile block up to date (%d items)' % len(rows)
        return text[:s] + block + text[e + len(XML_END):], 'items.xml: dark tile block rewritten (%d items)' % len(rows)
    end = text.rfind('</items>')
    if end < 0:
        raise SystemExit('items.xml: no </items>')
    return text[:end] + block + text[end:], 'items.xml: dark tile block added (%d items)' % len(rows)


def main():
    args = sys.argv[1:]
    dry = '--dry-run' in args
    manifest = DEFAULT_MANIFEST
    if '--manifest' in args:
        i = args.index('--manifest'); manifest = args[i + 1]; del args[i:i + 2]
    args = [a for a in args if not a.startswith('--')]
    if len(args) != 1:
        print(__doc__)
        return 1
    data_dir = args[0]
    rows = read_manifest(manifest)
    for r in rows:
        assert r['server_id'] == r['client_id'] + 3000, 'server id must be client id + 3000 (%s)' % r['key']
    otb = os.path.join(data_dir, 'items', 'items.otb')
    xml = os.path.join(data_dir, 'items', 'items.xml')
    if not os.path.exists(otb) or not os.path.exists(xml):
        print('items.otb / items.xml not found in', os.path.join(data_dir, 'items'))
        return 1
    raw = open(otb, 'rb').read()
    new, notes = patch_otb(raw, rows)
    n = verify_otb(new, rows)
    for line in notes:
        print(line)
    print('items.otb: verified (%d item nodes, every dark tile node as in the manifest)' % n)
    text = open(xml, encoding='utf-8', errors='surrogateescape').read()
    new_text, note = patch_xml(text, rows)
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
