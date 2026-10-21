#!/usr/bin/env python3
"""Install the gems and the Orb of Sockets into a base server: items.otb nodes and items.xml entries.

usage: python3 -I install_gems.py DATA_DIR [--dry-run]

Everything is read from server/data/lib/chaos_gems_config.lua (the same file the Lua side uses): firstId, tiers,
types (name, plural, clientId, clientIdHigh, the three effects and their values), effects (labels) and socketOrb.

1. data/items/items.otb: one node per gem type and tier, server ids firstId.. (32001..32035), each a copy of the stock
   node of its client sprite (the small ruby, the small enchanted ruby, ...) with the new server id and the "useable"
   flag (FLAG_USEABLE, needed for "use with"). With `ownLook = true` the node's client id is our own animated look
   instead, lookFirst + (type - 1) * tiers + tier - 1 (33905..33939: client/tools/sprites/gen_gem_art.py,
   art_import/gems.csv; the client pair must have them), the rest of the node still the stock gem's (its look copies
   the stock gem's dat flags: stackable, multi-use). Flipping ownLook either way rewrites the 35 nodes; a look id that
   another node uses stops the script. Nodes are appended at the end of the root. A node already there with the
   same bytes is left alone; one with other bytes (an older config) is replaced; a server id that belongs to another
   client id (neither the stock sprite nor our look) stops the script (nothing is written). A copy of the original
   file is kept as items.otb.bak the first time. After writing, the file is parsed again and every gem node is
   checked.
   The dark tile set (install_dark_tiles.py) uses 30484..30557; these ids stay clear of it.
2. data/items/items.xml: the gems (name, plural, a description with their three effects, weight) inside a block
   between two marker comments before </items>, rewritten when the config changed; and the Orb of Sockets (the unused
   stackable use-with rune stone socketOrb.id) inside the same block. An id that already has an entry outside the block
   stops the script.

Client side: every gem sprite but the small diamond (client 3028) is already "use with" in Tibia.dat; that one gets
the flag from client/tools/sprites/set_multiuse.py (its default list).

Idempotent: a second run changes nothing.
"""
import os, re, struct, sys

HERE = os.path.dirname(os.path.abspath(__file__))
CONFIG = os.path.join(os.path.dirname(HERE), 'data', 'lib', 'chaos_gems_config.lua')
ESC, START, END = 0xFD, 0xFE, 0xFF
A_SERVERID, A_CLIENTID = 0x10, 0x11
FLAG_USEABLE, FLAG_PICKUPABLE, FLAG_MOVEABLE, FLAG_STACKABLE = 1 << 4, 1 << 5, 1 << 6, 1 << 7
# the client sends no random-phase byte unless the server node says the look is animated: a node whose client thing
# has more than one phase needs this flag, or every item packet of it is one byte short for the client (2026-10-16:
# "ProtocolGame parse message exception ... last opcode is 0x6e ... eof reached" opening a Loot Bag holding gems)
FLAG_ANIMATION = 1 << 24
XML_BEGIN = '\t<!-- Chaos gems and the Orb of Sockets (server/tools/install_gems.py, do not edit by hand) -->\n'
XML_END = '\t<!-- end of the Chaos gems -->\n'
GEM_WEIGHT = 10
ORB_WEIGHT = 50
ORB_ITEM_TEXT = 'Rolls a new number of sockets on a piece of gear. Gems stay; uniques keep one.'


# ------------------------------------------------------------------------------------------------ config
def _strip_comments(text):
    return re.sub(r'--[^\n]*', '', text)


def _numbers(s):
    return [int(x) for x in re.findall(r'-?\d+', s)]


def read_config(path=CONFIG):
    text = _strip_comments(open(path, encoding='utf-8').read())
    cfg = {}
    cfg['firstId'] = int(re.search(r'firstId\s*=\s*(\d+)', text).group(1))
    cfg['highFrom'] = int(re.search(r'highFrom\s*=\s*(\d+)', text).group(1))
    own = re.search(r'\bownLook\s*=\s*(true|false)', text)
    cfg['ownLook'] = bool(own and own.group(1) == 'true')
    look = re.search(r'\blookFirst\s*=\s*(\d+)', text)
    cfg['lookFirst'] = int(look.group(1)) if look else None
    assert not cfg['ownLook'] or cfg['lookFirst'], 'chaos_gems_config.lua: ownLook needs lookFirst'
    cfg['tiers'] = re.findall(r'"([^"]+)"', re.search(r'tiers\s*=\s*\{([^}]*)\}', text).group(1))
    orb = re.search(r'socketOrb\s*=\s*\{(.*?)\}', text, re.S).group(1)
    cfg['socketOrb'] = {'id': int(re.search(r'id\s*=\s*(\d+)', orb).group(1)),
                        'name': re.search(r'name\s*=\s*"([^"]+)"', orb).group(1),
                        'text': re.search(r'text\s*=\s*"([^"]+)"', orb).group(1)}
    effects = {}
    eblock = re.search(r'effects\s*=\s*\{(.*?)\n\t\},', text, re.S).group(1)
    for m in re.finditer(r'(\w+)\s*=\s*\{label\s*=\s*"([^"]+)"(?:,\s*label2\s*=\s*"([^"]+)")?,\s*fmt\s*=\s*"(\w+)"', eblock):
        effects[m.group(1)] = {'label': m.group(2), 'label2': m.group(3), 'fmt': m.group(4)}
    cfg['effects'] = effects
    types = []
    tblock = re.search(r'types\s*=\s*\{(.*?)\n\t\},', text, re.S).group(1)
    for m in re.finditer(r'\{key\s*=\s*"(\w+)"(.*?)jewel\s*=\s*\{(.*?)\}\}', tblock, re.S):
        head, body = m.group(2), m.group(0)
        t = {'key': m.group(1),
             'name': re.search(r'name\s*=\s*"([^"]+)"', head).group(1),
             'plural': re.search(r'plural\s*=\s*"([^"]+)"', head).group(1),
             'clientId': int(re.search(r'clientId\s*=\s*(\d+)', head).group(1))}
        high = re.search(r'clientIdHigh\s*=\s*(\d+)', head)
        t['clientIdHigh'] = int(high.group(1)) if high else None
        for group in ('weapon', 'armour', 'jewel'):
            g = re.search(group + r'\s*=\s*\{effect\s*=\s*"(\w+)",\s*values\s*=\s*\{([^}]*)\}(?:,\s*values2\s*=\s*\{([^}]*)\})?', body)
            t[group] = {'effect': g.group(1), 'values': _numbers(g.group(2)),
                        'values2': _numbers(g.group(3)) if g.group(3) else None}
        types.append(t)
    cfg['types'] = types
    assert len(types) >= 1 and len(cfg['tiers']) >= 1, 'chaos_gems_config.lua: no types or tiers found'
    for t in types:
        for group in ('weapon', 'armour', 'jewel'):
            assert t[group]['effect'] in effects, 'unknown effect %s' % t[group]['effect']
            assert len(t[group]['values']) == len(cfg['tiers']), '%s %s: one value per tier' % (t['key'], group)
    return cfg


def stock_client_id(cfg, sid):
    """the client id of the stock gem sprite of a gem server id (its otb node is copied)"""
    n = len(cfg['tiers'])
    t = cfg['types'][(sid - cfg['firstId']) // n]
    tier = (sid - cfg['firstId']) % n + 1
    return t['clientIdHigh'] if (t['clientIdHigh'] and tier >= cfg['highFrom']) else t['clientId']


def own_client_id(cfg, sid):
    """our own look of a gem server id (lookFirst..), None without lookFirst"""
    return cfg['lookFirst'] + sid - cfg['firstId'] if cfg.get('lookFirst') else None


def gems(cfg):
    """[(server id, client id, items.xml name, plural, description)]; the client id is our look with ownLook"""
    out = []
    n = len(cfg['tiers'])
    for ti, t in enumerate(cfg['types']):
        for tier in range(1, n + 1):
            sid = cfg['firstId'] + ti * n + tier - 1
            cid = stock_client_id(cfg, sid)
            if cfg.get('ownLook'):
                cid = own_client_id(cfg, sid)
            q = cfg['tiers'][tier - 1].lower()
            parts = []
            for group, label in (('weapon', 'in a weapon'), ('armour', 'in armour'), ('jewel', 'in jewellery')):
                g = t[group]
                e = cfg['effects'][g['effect']]
                v = g['values'][tier - 1]
                if e['fmt'] == 'flat':
                    txt = '%s +%d' % (e['label'], v)
                elif e['fmt'] == 'pair':
                    txt = '%s +%d%%, %s +%d%%' % (e['label'], v, e['label2'], g['values2'][tier - 1])
                else:
                    txt = '%s +%d%%' % (e['label'], v)
                parts.append('%s: %s' % (label, txt))
            desc = 'A gem for a socket: %s. Use it with gear that has a free socket.' % '; '.join(parts)
            if tier < n:  # the same words as G.COMBINE_HOW (chaos_gems.lua)
                desc += (' To combine three into one of the next quality: use the stack, then left-click the same '
                         'stack.')
            out.append((sid, cid, '%s %s' % (q, t['name']), '%s %s' % (q, t['plural']), desc))
    return out


# ------------------------------------------------------------------------------------------------ items.otb
def escape(data):
    out = bytearray()
    for b in data:
        if b in (ESC, START, END):
            out.append(ESC)
        out.append(b)
    return bytes(out)


def attr(kind, payload):
    return bytes([kind]) + struct.pack('<H', len(payload)) + payload


def scan(data):
    """root children: list of (start, end, server id, client id, group, flags, attributes [(kind, payload)])"""
    assert data[4] == START, 'not an items.otb (no root node)'
    i = 6
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
        j, sid, cid, attrs = 5, None, None, []
        while j + 3 <= len(props):
            k = props[j]; ln = struct.unpack_from('<H', props, j + 1)[0]
            v = bytes(props[j + 3:j + 3 + ln])
            attrs.append((k, v))
            if k == A_SERVERID:
                sid = struct.unpack('<H', v)[0]
            elif k == A_CLIENTID:
                cid = struct.unpack('<H', v)[0]
            j += 3 + ln
        kids.append((s, i, sid, cid, group, flags, attrs))
    assert data[i] == END, 'unexpected byte after the item nodes'
    return kids, i


def gem_node(stock, sid, cid=None):
    """a copy of the stock node (group, flags + useable, every attribute) with the new server id (and client id).
    With our own look (cid) the node is animated (FLAG_ANIMATION): every own gem look has 9 phases
    (client/tools/sprites/art_import/gems.csv), so the server must send the phase byte the client reads for it."""
    _s, _e, _sid, _cid, group, flags, attrs = stock
    flags |= FLAG_USEABLE | FLAG_PICKUPABLE | FLAG_MOVEABLE | FLAG_STACKABLE
    if cid is not None:
        flags |= FLAG_ANIMATION
    body = struct.pack('<I', flags)
    for k, v in attrs:
        if k == A_SERVERID:
            v = struct.pack('<H', sid)
        elif k == A_CLIENTID and cid is not None:
            v = struct.pack('<H', cid)
        body += attr(k, v)
    return bytes([START]) + escape(bytes([group])) + escape(body) + bytes([END])


def stock_nodes(kids, first, last):
    """client id -> the stock node with that client id (lowest server id outside our range)"""
    out = {}
    for k in kids:
        sid, cid = k[2], k[3]
        if sid is None or cid is None or first <= sid <= last:
            continue
        if cid not in out or sid < out[cid][2]:
            out[cid] = k
    return out


def patch_otb(data, rows, cfg=None):
    """cfg (read_config) names the stock sprite of each gem when the rows carry our own looks (ownLook)"""
    kids, root_end = scan(data)
    first, last = rows[0][0], rows[-1][0]
    stock = stock_nodes(kids, first, last)
    by_sid = {k[2]: k for k in kids}
    replace, append, wanted = [], [], {}
    others = {k[3] for k in kids if k[2] is not None and not first <= k[2] <= last}
    for sid, cid, _name, _plural, _desc in rows:
        scid = stock_client_id(cfg, sid) if cfg else cid
        if cid != scid and cid in others:
            raise SystemExit('items.otb: client id %d (the look of gem %d) is already used by another node; nothing '
                             'written' % (cid, sid))
        if scid not in stock:
            raise SystemExit('items.otb: no stock node with client id %d (gem %d); nothing written' % (scid, sid))
        want = gem_node(stock[scid], sid, cid if cid != scid else None)
        wanted[sid] = want
        k = by_sid.get(sid)
        if k is None:
            append.append(want)
        elif k[3] not in (cid, scid, own_client_id(cfg, sid) if cfg else cid):
            raise SystemExit('items.otb: server id %d already belongs to client id %s, not %d; nothing written'
                             % (sid, k[3], cid))
        elif data[k[0]:k[1]] != want:
            replace.append((k[0], k[1], want))
    out = bytearray(data)
    for s, e, b in sorted(replace, reverse=True):
        out[s:e] = b
    shift = sum(len(b) - (e - s) for s, e, b in replace)
    at = root_end + shift
    out[at:at] = b''.join(append)
    notes = []
    if replace:
        notes.append('items.otb: %d gem nodes updated' % len(replace))
    if append:
        notes.append('items.otb: %d gem nodes added (server ids %d..%d)' % (len(append), first, last))
    if not replace and not append:
        notes.append('items.otb: all %d gem nodes present' % len(rows))
    return bytes(out), notes, wanted


def verify_otb(data, rows, wanted):
    kids, _ = scan(data)
    by_sid = {k[2]: k for k in kids}
    for sid, cid, _n, _p, _d in rows:
        k = by_sid.get(sid)
        assert k and k[3] == cid and k[5] & FLAG_USEABLE and k[5] & FLAG_STACKABLE, 'gem node %d' % sid
        assert data[k[0]:k[1]] == wanted[sid], 'gem node %d bytes' % sid
    sids = [k[2] for k in kids]
    assert len(sids) == len(set(sids)), 'duplicate server ids in items.otb'
    return len(kids)


# ------------------------------------------------------------------------------------------------ items.xml
def xml_escape(s):
    return s.replace('&', '&amp;').replace('"', '&quot;').replace('<', '&lt;').replace('>', '&gt;')


def xml_block(rows, orb):
    lines = [XML_BEGIN]
    for sid, _cid, name, plural, desc in rows:
        lines.append('\t<item id="%d" article="a" name="%s" plural="%s">\n'
                     '\t\t<attribute key="description" value="%s" />\n'
                     '\t\t<attribute key="weight" value="%d" />\n'
                     '\t</item>\n' % (sid, xml_escape(name), xml_escape(plural), xml_escape(desc), GEM_WEIGHT))
    lines.append('\t<item id="%d" article="an" name="%s" plural="%s">\n'
                 '\t\t<attribute key="description" value="%s" />\n'
                 '\t\t<attribute key="weight" value="%d" />\n'
                 '\t</item>\n' % (orb['id'], xml_escape(orb['name']), xml_escape(orb['name'].replace('Orb of', 'Orbs of')),
                                  xml_escape(ORB_ITEM_TEXT), ORB_WEIGHT))
    lines.append(XML_END)
    return ''.join(lines)


def patch_xml(text, rows, orb):
    block = xml_block(rows, orb)
    s = text.find(XML_BEGIN)
    if s >= 0:
        e = text.find(XML_END, s)
        if e < 0:
            raise SystemExit('items.xml: gem start marker without end marker')
        outside = text[:s] + text[e + len(XML_END):]
    else:
        outside = text
    ranges = [(int(a), int(b)) for a, b in re.findall(r'fromid="(\d+)"\s+toid="(\d+)"', outside)]
    for sid in [r[0] for r in rows] + [orb['id']]:
        if re.search(r'<item\s+id="%d"' % sid, outside) or any(a <= sid <= b for a, b in ranges):
            raise SystemExit('items.xml: id %d already has an entry outside the gem block; nothing written' % sid)
    if s >= 0:
        if text[s:e + len(XML_END)] == block:
            return text, 'items.xml: gem block up to date (%d gems + the Orb of Sockets)' % len(rows)
        return text[:s] + block + text[e + len(XML_END):], 'items.xml: gem block rewritten (%d gems)' % len(rows)
    end = text.rfind('</items>')
    if end < 0:
        raise SystemExit('items.xml: no </items>')
    return text[:end] + block + text[end:], 'items.xml: gem block added (%d gems + the Orb of Sockets)' % len(rows)


def main():
    args = sys.argv[1:]
    dry = '--dry-run' in args
    args = [a for a in args if not a.startswith('--')]
    if len(args) != 1:
        print(__doc__)
        return 1
    data_dir = args[0]
    cfg = read_config()
    rows = gems(cfg)
    otb = os.path.join(data_dir, 'items', 'items.otb')
    xml = os.path.join(data_dir, 'items', 'items.xml')
    if not os.path.exists(otb) or not os.path.exists(xml):
        print('items.otb / items.xml not found in', os.path.join(data_dir, 'items'))
        return 1
    raw = open(otb, 'rb').read()
    new, notes, wanted = patch_otb(raw, rows, cfg)
    n = verify_otb(new, rows, wanted)
    for line in notes:
        print(line)
    print('items.otb: verified (%d item nodes, every gem node a useable copy of its stock sprite%s)'
          % (n, ', with our own looks %d..%d' % (rows[0][1], rows[-1][1]) if cfg['ownLook'] else ''))
    text = open(xml, encoding='utf-8', errors='surrogateescape').read()
    new_text, note = patch_xml(text, rows, cfg['socketOrb'])
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
