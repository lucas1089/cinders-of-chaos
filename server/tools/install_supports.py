#!/usr/bin/env python3
"""Install the spell support runes into a base server: items.otb nodes, items.xml entries and the spell-library hook.

usage: python3 -I install_supports.py DATA_DIR [--dry-run]

Everything is read from server/data/lib/chaos_supports_config.lua (the same file the Lua side uses): firstId,
clientFirstId (optional), levels, levelNames, sprites and supports (key, name, sprite, fits, values, values2, text).

1. data/items/items.otb: one node per support and level, server ids firstId.. (32101..32200), each a copy of the stock
   rune stone `sprites[sprite]` (stackable, use-with: the client treats them so) with the new server id. With
   `clientFirstId` (38658, the own rune looks of pair 46, client/MANIFEST.md "Support rune looks") every node also gets
   its own client id, clientFirstId + (server id - firstId); without it the nodes keep the stock stone's client id (the
   fallback: set it to nil when the client is not on pair 46 yet). A client id that already belongs to another server
   id stops the script. Nodes are appended at the end of the root. A node already there with the same bytes is left
   alone; one with other bytes (an older config, or the stock look before the own one) is replaced; a server id that
   belongs to another client id (neither the stock stone's nor its own) stops the script (nothing is written);
   with clientFirstId unset every rune node goes back to the stock stone's client id (the fallback).
   items.otb.bak keeps the original the first time; the written file is parsed again and every node checked.
   Ranges in use: gems 32001..32035, salvage 32051, dark tiles 30484..30557, art 33000.., pack 36000.., donor 40000...
2. data/items/items.xml: the runes (name, plural, description, weight) between two marker comments before </items>,
   rewritten when the config changed. An id that already has an entry outside the block stops the script.
3. data/spells/lib/spells.lua: one marked line at the end that loads data/spells/scripts/chaos/_supports.lua, so the
   support wrapper is in place before any spell script loads and stock spells get sockets too. Without it only the
   Chaos spells (their _common.lua loads the wrapper) get them.

Idempotent: a second run changes nothing.
"""
import os, re, struct, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from install_gems import scan, escape, attr, xml_escape, START, END, A_SERVERID, A_CLIENTID, FLAG_USEABLE, \
    FLAG_STACKABLE, FLAG_PICKUPABLE, FLAG_MOVEABLE  # noqa: E402

CONFIG = os.path.join(os.path.dirname(HERE), 'data', 'lib', 'chaos_supports_config.lua')
XML_BEGIN = '\t<!-- Chaos spell support runes (server/tools/install_supports.py, do not edit by hand) -->\n'
XML_END = '\t<!-- end of the Chaos spell support runes -->\n'
LIB_LINE = ("pcall(dofile, 'data/spells/scripts/chaos/_supports.lua') "
            "-- Chaos spell supports (server/tools/install_supports.py)\n")
RUNE_WEIGHT = 10
KIND_NAMES = {'single': 'single target', 'area': 'area', 'heal': 'healing', 'buff': 'buff / utility'}


# ------------------------------------------------------------------------------------------------ config
def _strip_comments(text):
    return re.sub(r'--[^\n]*', '', text)


def _numbers(s):
    return [int(x) for x in re.findall(r'-?\d+', s)]


def read_config(path=CONFIG):
    raw = open(path, encoding='utf-8').read()
    text = _strip_comments(raw)
    cf = re.search(r'clientFirstId\s*=\s*(\d+)', text)
    cfg = {'firstId': int(re.search(r'firstId\s*=\s*(\d+)', text).group(1)),
           'clientFirstId': int(cf.group(1)) if cf else None,
           'levels': int(re.search(r'\blevels\s*=\s*(\d+)', text).group(1)),
           'levelNames': re.findall(r'"([^"]+)"', re.search(r'levelNames\s*=\s*\{([^}]*)\}', text).group(1)),
           'sprites': _numbers(re.search(r'sprites\s*=\s*\{([^}]*)\}', text).group(1))}
    block = re.search(r'supports\s*=\s*\{(.*?)\n\t\},', raw, re.S).group(1)
    sups = []
    for m in re.finditer(r'\{key\s*=\s*"(\w+)"(.*?)text\s*=\s*"((?:[^"\\]|\\.)*)"\}', block, re.S):
        body = m.group(2)
        v2 = re.search(r'values2\s*=\s*\{([^}]*)\}', body)
        sups.append({'key': m.group(1),
                     'name': re.search(r'name\s*=\s*"([^"]+)"', body).group(1),
                     'sprite': int(re.search(r'sprite\s*=\s*(\d+)', body).group(1)),
                     'fits': re.findall(r'"(\w+)"', re.search(r'fits\s*=\s*\{([^}]*)\}', body).group(1)),
                     'values': _numbers(re.search(r'\bvalues\s*=\s*\{([^}]*)\}', body).group(1)),
                     'values2': _numbers(v2.group(1)) if v2 else None,
                     'text': m.group(3)})
    cfg['supports'] = sups
    assert sups, 'chaos_supports_config.lua: no supports found'
    assert len(cfg['levelNames']) == cfg['levels'], 'one level name per level'
    for s in sups:
        assert len(s['values']) == cfg['levels'], '%s: one value per level' % s['key']
        assert 1 <= s['sprite'] <= len(cfg['sprites']), '%s: sprite index' % s['key']
    return cfg


def fill(text, v1, v2):
    """the Lua side's fill(): %1 / %2 are the values, %% is a percent sign"""
    text = re.sub(r'%(\d)', lambda m: str(v1 if m.group(1) == '1' else (v2 if v2 is not None else '')), text)
    return text.replace('%%', '%')


def description(cfg, s, level):
    v1 = s['values'][level - 1]
    v2 = s['values2'][level - 1] if s['values2'] else None
    fits = ', '.join(KIND_NAMES.get(k, k) for k in s['fits'])
    effect = fill(s['text'], v1, v2)
    text = 'A support rune for a spell socket: %s. Fits %s spells.' % (effect[:1].lower() + effect[1:], fits)
    if level < cfg['levels']:
        text += ' Three of them combine into one of the next level: use the stack, then left-click the same stack.'
    return text + ' Use it to open the spell supports (!supports).'


def runes(cfg):
    """[(server id, sprite server id, name, plural, description, own client id or None)]"""
    out = []
    n = cfg['levels']
    for ti, s in enumerate(cfg['supports']):
        for level in range(1, n + 1):
            sid = cfg['firstId'] + ti * n + level - 1
            name = ('%s %s rune' % (cfg['levelNames'][level - 1], s['name'])).lower()
            cid = cfg['clientFirstId'] + sid - cfg['firstId'] if cfg['clientFirstId'] else None
            out.append((sid, cfg['sprites'][s['sprite'] - 1], name, name + 's', description(cfg, s, level), cid))
    return out


# ------------------------------------------------------------------------------------------------ items.otb
def rune_node(stock, sid, cid=None):
    """a copy of the stock rune stone node (group, flags, every attribute) with the new server id (and own client id)"""
    _s, _e, _sid, _cid, group, flags, attrs = stock
    flags |= FLAG_PICKUPABLE | FLAG_MOVEABLE
    body = struct.pack('<I', flags)
    for k, v in attrs:
        if k == A_SERVERID:
            v = struct.pack('<H', sid)
        elif k == A_CLIENTID and cid is not None:
            v = struct.pack('<H', cid)
        body += attr(k, v)
    return bytes([START]) + escape(bytes([group])) + escape(body) + bytes([END])


def patch_otb(data, rows):
    kids, root_end = scan(data)
    by_sid = {k[2]: k for k in kids}
    replace, append, wanted = [], [], {}
    owners = {}
    for k in kids:
        owners.setdefault(k[3], []).append(k[2])
    for sid, source, _name, _plural, _desc, own in rows:
        stock = by_sid.get(source)
        if stock is None:
            raise SystemExit('items.otb: no stock node %d (rune stone of rune %d); nothing written' % (source, sid))
        if not (stock[5] & FLAG_STACKABLE and stock[5] & FLAG_USEABLE):
            raise SystemExit('items.otb: node %d is not a stackable use-with item; nothing written' % source)
        cid = own if own is not None else stock[3]
        if own is not None:
            other = [s for s in owners.get(own, []) if s != sid]
            if other:
                raise SystemExit('items.otb: client id %d (the look of rune %d) belongs to server id %s; nothing written'
                                 % (own, sid, other[0]))
        want = rune_node(stock, sid, own)
        wanted[sid] = (want, cid)
        k = by_sid.get(sid)
        if k is None:
            append.append(want)
        elif own is not None and k[3] not in (stock[3], cid):   # without own looks every rune node goes back to the stock stone
            raise SystemExit('items.otb: server id %d already belongs to client id %s, not %d or %d; nothing written'
                             % (sid, k[3], stock[3], cid))
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
        notes.append('items.otb: %d rune nodes updated' % len(replace))
    if append:
        notes.append('items.otb: %d rune nodes added (server ids %d..%d)' % (len(append), rows[0][0], rows[-1][0]))
    if not replace and not append:
        notes.append('items.otb: all %d rune nodes present' % len(rows))
    return bytes(out), notes, wanted


def verify_otb(data, rows, wanted):
    kids, _ = scan(data)
    by_sid = {k[2]: k for k in kids}
    for sid, _src, _n, _p, _d, _own in rows:
        k = by_sid.get(sid)
        want, cid = wanted[sid]
        assert k and k[3] == cid and k[5] & FLAG_STACKABLE, 'rune node %d' % sid
        assert data[k[0]:k[1]] == want, 'rune node %d bytes' % sid
    sids = [k[2] for k in kids]
    assert len(sids) == len(set(sids)), 'duplicate server ids in items.otb'
    own = [by_sid[r[0]][3] for r in rows if r[5] is not None]
    assert len(own) == len(set(own)), 'two support runes share a client id'
    return len(kids)


# ------------------------------------------------------------------------------------------------ items.xml
def xml_block(rows):
    lines = [XML_BEGIN]
    for sid, _src, name, plural, desc, _own in rows:
        lines.append('\t<item id="%d" article="a" name="%s" plural="%s">\n'
                     '\t\t<attribute key="description" value="%s" />\n'
                     '\t\t<attribute key="weight" value="%d" />\n'
                     '\t</item>\n' % (sid, xml_escape(name), xml_escape(plural), xml_escape(desc), RUNE_WEIGHT))
    lines.append(XML_END)
    return ''.join(lines)


def patch_xml(text, rows):
    block = xml_block(rows)
    s = text.find(XML_BEGIN)
    if s >= 0:
        e = text.find(XML_END, s)
        if e < 0:
            raise SystemExit('items.xml: rune start marker without end marker')
        outside = text[:s] + text[e + len(XML_END):]
    else:
        outside = text
    ranges = [(int(a), int(b)) for a, b in re.findall(r'fromid="(\d+)"\s+toid="(\d+)"', outside)]
    for sid in [r[0] for r in rows]:
        if re.search(r'<item\s+id="%d"' % sid, outside) or any(a <= sid <= b for a, b in ranges):
            raise SystemExit('items.xml: id %d already has an entry outside the rune block; nothing written' % sid)
    if s >= 0:
        if text[s:e + len(XML_END)] == block:
            return text, 'items.xml: rune block up to date (%d runes)' % len(rows)
        return text[:s] + block + text[e + len(XML_END):], 'items.xml: rune block rewritten (%d runes)' % len(rows)
    end = text.rfind('</items>')
    if end < 0:
        raise SystemExit('items.xml: no </items>')
    return text[:end] + block + text[end:], 'items.xml: rune block added (%d runes)' % len(rows)


# ------------------------------------------------------------------------------------------------ spells/lib/spells.lua
def patch_lib(text):
    if LIB_LINE in text:
        return text, 'spells/lib/spells.lua: supports line present'
    return text.rstrip('\n') + '\n\n' + LIB_LINE, 'spells/lib/spells.lua: supports line added'


def main():
    args = sys.argv[1:]
    dry = '--dry-run' in args
    args = [a for a in args if not a.startswith('--')]
    if len(args) != 1:
        print(__doc__)
        return 1
    data_dir = args[0]
    cfg = read_config()
    rows = runes(cfg)
    otb = os.path.join(data_dir, 'items', 'items.otb')
    xml = os.path.join(data_dir, 'items', 'items.xml')
    lib = os.path.join(data_dir, 'spells', 'lib', 'spells.lua')
    if not os.path.exists(otb) or not os.path.exists(xml):
        print('items.otb / items.xml not found in', os.path.join(data_dir, 'items'))
        return 1
    raw = open(otb, 'rb').read()
    new, notes, wanted = patch_otb(raw, rows)
    n = verify_otb(new, rows, wanted)
    for line in notes:
        print(line)
    print('items.otb: verified (%d item nodes, every rune node a copy of its rune stone%s)'
          % (n, ', own client ids %d..%d' % (rows[0][5], rows[-1][5]) if rows[0][5] else ''))
    text = open(xml, encoding='utf-8', errors='surrogateescape').read()
    new_text, note = patch_xml(text, rows)
    print(note)
    lib_text = new_lib = None
    if os.path.exists(lib):
        lib_text = open(lib, encoding='utf-8', errors='surrogateescape').read()
        new_lib, note = patch_lib(lib_text)
        print(note)
    else:
        print('spells/lib/spells.lua not found: only the Chaos spells get sockets')
    if dry:
        print('dry run: nothing written')
        return 0
    if new != raw:
        if not os.path.exists(otb + '.bak'):
            open(otb + '.bak', 'wb').write(raw)
        open(otb, 'wb').write(new)
    if new_text != text:
        open(xml, 'w', encoding='utf-8', errors='surrogateescape', newline='').write(new_text)
    if lib_text is not None and new_lib != lib_text:
        open(lib, 'w', encoding='utf-8', errors='surrogateescape', newline='').write(new_lib)
    return 0


if __name__ == '__main__':
    sys.exit(main())
