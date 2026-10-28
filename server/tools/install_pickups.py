#!/usr/bin/env python3
"""Ground pickups (server/README.md "Ground pickups and globes"): the health globe, the mana globe and the ember.

usage: python3 -I install_pickups.py DATA_DIR [--dry-run]

Everything is read from server/data/scripts/chaos/pickups_config.lua (`items`, `failsafeSeconds`), the file the Lua side
(pickups.lua) uses too.

1. data/items/items.otb: per item a copy of a stock node (`sourceId`: that server id; `clientId`: the lowest stock
   server id of that client id; with `stockClientId` too: a look of ours that has no stock node, e.g. the ember's
   portal, client item 44396 of pair 55, and the globes, 44397 / 44398: the lowest stock node of `stockClientId` is
   copied and `clientId` written, and a client id that belongs to another server id stops the script), with the new
   server id and the flags NOT pickupable and NOT moveable (a pickup can never go into a bag, be pushed or traded; an
   older node of the ember on 25045 or of a globe on the potion look 7618 / 7620 is rewritten). The stackable flag is copied from the stock node, or forced when the
   row says `stackable = true` (the 10.98 client reads a count for a stackable look). A node already there with the
   same bytes is left alone, one with other bytes is replaced; a server id that belongs to another client id stops
   the script (nothing is written). items.otb.bak keeps the original the first time; the written file is parsed again
   and every node checked.
2. data/items/items.xml: the entries (article, name, plural, description, weight, and `decayTo 0` after
   `failsafeSeconds`, so an item left by a crash goes away by itself) between two marker comments before </items>,
   rewritten when the config changed. An id with an entry outside the block stops the script.

Client pair guard (README "Client pair guard"): the three looks are pair 55 client ids, so the step does nothing (and says
so) while config.lua's chaosClientPair is lower than 55 or missing; an install that already has the nodes keeps them.

The rules (who takes it, how long it lasts) are Lua (pickups.lua); a pickup with no record grants nothing.
Idempotent: a second run changes nothing. --dry-run changes nothing at all.
"""
import os, re, struct, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import client_pair  # noqa: E402
from install_gems import (scan, escape, attr, xml_escape, START, END, A_SERVERID, A_CLIENTID, FLAG_STACKABLE,  # noqa: E402
                          FLAG_PICKUPABLE, FLAG_MOVEABLE)

CONFIG = os.path.join(os.path.dirname(HERE), 'data', 'scripts', 'chaos', 'pickups_config.lua')
XML_BEGIN = '\t<!-- Chaos ground pickups (server/tools/install_pickups.py, do not edit by hand) -->\n'
XML_END = '\t<!-- end of the Chaos ground pickups -->\n'


def lua_string(block, key):
    m = re.search(r'\b%s\s*=\s*((?:"[^"]*"\s*(?:\.\.\s*)?)+)' % key, block, re.S)
    return ''.join(re.findall(r'"([^"]*)"', m.group(1))) if m else ''


def read_config(path=CONFIG):
    text = open(path, encoding='utf-8').read()
    body = re.search(r'\n\titems = \{(.*?)\n\t\},\n', text, re.S).group(1)
    rows = []
    for chunk in re.split(r'\n\t\t\{(?=key =)', '\n' + body)[1:]:
        def num(key, required=True):
            m = re.search(r'\b%s\s*=\s*(\d+)' % key, chunk)
            assert m or not required, 'pickups_config.lua: %s missing' % key
            return int(m.group(1)) if m else None
        stackable = re.search(r'\bstackable\s*=\s*(true|false)', chunk)
        rows.append({'key': lua_string(chunk, 'key'), 'id': num('id'), 'sourceId': num('sourceId', False),
                     'clientId': num('clientId', False), 'stockClientId': num('stockClientId', False),
                     'weight': num('weight'),
                     'stackable': None if not stackable else stackable.group(1) == 'true',
                     'article': lua_string(chunk, 'article'), 'name': lua_string(chunk, 'name'),
                     'plural': lua_string(chunk, 'plural'), 'description': lua_string(chunk, 'description')})
    fs = re.search(r'\bfailsafeSeconds\s*=\s*(\d+)', text)
    cfg = {'items': rows, 'failsafe': int(fs.group(1)) if fs else 0}
    assert len(rows) >= 3 and all(r['key'] and r['id'] and r['name'] and (r['sourceId'] or r['clientId'] or r['stockClientId']) for r in rows), \
        'pickups_config.lua: items incomplete'
    ids = [r['id'] for r in rows]
    assert len(ids) == len(set(ids)), 'pickups_config.lua: duplicate item ids'
    return cfg


# ------------------------------------------------------------------------------------------------ 1. items.otb
def pickup_node(stock, row):
    """a copy of the stock node with the new server id, not pickupable, not moveable"""
    _s, _e, _sid, _cid, group, flags, attrs = stock
    flags &= ~(FLAG_PICKUPABLE | FLAG_MOVEABLE)
    if row['stackable'] is True:
        flags |= FLAG_STACKABLE
    elif row['stackable'] is False:
        flags &= ~FLAG_STACKABLE
    body = struct.pack('<I', flags)
    for k, v in attrs:
        if k == A_SERVERID:
            v = struct.pack('<H', row['id'])
        elif k == A_CLIENTID and row.get('stockClientId'):
            v = struct.pack('<H', row['clientId'])
        body += attr(k, v)
    return bytes([START]) + escape(bytes([group])) + escape(body) + bytes([END])


def stock_of(kids, row, ours):
    if row['sourceId']:
        return next((k for k in kids if k[2] == row['sourceId']), None)
    best = None
    for k in kids:
        if k[3] == (row.get('stockClientId') or row['clientId']) and k[2] not in ours and (best is None or k[2] < best[2]):
            best = k
    return best


def patch_otb(data, cfg):
    kids, root_end = scan(data)
    ours = {r['id'] for r in cfg['items']}
    by_sid = {k[2]: k for k in kids}
    buf = bytearray(data)
    notes, wanted, replace, append = [], [], [], b''
    for row in cfg['items']:
        stock = stock_of(kids, row, ours)
        if stock is None:
            raise SystemExit('items.otb: no stock node for %s (source %s / client %s); nothing written'
                             % (row['name'], row['sourceId'], row['clientId']))
        want = pickup_node(stock, row)
        cid = row['clientId'] if row.get('stockClientId') else stock[3]
        if row.get('stockClientId'):
            other = [x[2] for x in kids if x[3] == cid and x[2] != row['id']]
            if other:
                raise SystemExit('items.otb: client id %d (the look of %s) belongs to server id %d; nothing written'
                                 % (cid, row['name'], other[0]))
        wanted.append((row, want, cid))
        k = by_sid.get(row['id'])
        if k is None:
            append += want
            notes.append('items.otb: %s added (server id %d, client id %d)' % (row['name'], row['id'], cid))
        elif k[3] not in (stock[3], cid):
            raise SystemExit('items.otb: server id %d already belongs to client id %s, not %d; nothing written'
                             % (row['id'], k[3], cid))
        elif data[k[0]:k[1]] != want:
            replace.append((k[0], k[1], want))
            notes.append('items.otb: %s updated' % row['name'])
        else:
            notes.append('items.otb: %s present' % row['name'])
    for s, e, want in sorted(replace, reverse=True):
        buf[s:e] = want
    if append:
        _kids, end = scan(bytes(buf))
        buf[end:end] = append
    return bytes(buf), notes, wanted


def verify_otb(data, wanted):
    kids, _ = scan(data)
    by_sid = {k[2]: k for k in kids}
    for row, want, cid in wanted:
        k = by_sid.get(row['id'])
        assert k and k[3] == cid and data[k[0]:k[1]] == want, 'pickup node %d' % row['id']
        assert not (k[5] & (FLAG_PICKUPABLE | FLAG_MOVEABLE)), 'pickup %d is neither pickupable nor moveable' % row['id']
    sids = [x[2] for x in kids]
    assert len(sids) == len(set(sids)), 'duplicate server ids in items.otb'
    return len(kids)


# ------------------------------------------------------------------------------------------------ 2. items.xml
def xml_block(cfg):
    out = XML_BEGIN
    for r in cfg['items']:
        out += ('\t<item id="%d" article="%s" name="%s" plural="%s">\n'
                '\t\t<attribute key="description" value="%s" />\n'
                '\t\t<attribute key="weight" value="%d" />\n' % (r['id'], xml_escape(r['article']), xml_escape(r['name']),
                                                                 xml_escape(r['plural']), xml_escape(r['description']), r['weight']))
        if cfg['failsafe']:
            out += ('\t\t<attribute key="decayTo" value="0" />\n'
                    '\t\t<attribute key="duration" value="%d" />\n' % cfg['failsafe'])
        out += '\t</item>\n'
    return out + XML_END


def patch_xml(text, cfg):
    block = xml_block(cfg)
    s = text.find(XML_BEGIN)
    if s >= 0:
        e = text.find(XML_END, s)
        if e < 0:
            raise SystemExit('items.xml: pickups start marker without end marker')
        outside = text[:s] + text[e + len(XML_END):]
    else:
        outside = text
    ranges = [(int(a), int(b)) for a, b in re.findall(r'fromid="(\d+)"\s+toid="(\d+)"', outside)]
    for r in cfg['items']:
        if re.search(r'<item\s+id="%d"' % r['id'], outside) or any(a <= r['id'] <= b for a, b in ranges):
            raise SystemExit('items.xml: id %d already has an entry outside the pickups block; nothing written' % r['id'])
    if s >= 0:
        if text[s:e + len(XML_END)] == block:
            return text, 'items.xml: pickups block up to date'
        return text[:s] + block + text[e + len(XML_END):], 'items.xml: pickups block rewritten'
    end = text.rfind('</items>')
    if end < 0:
        raise SystemExit('items.xml: no </items>')
    return text[:end] + block + text[end:], 'items.xml: pickups block added'


def main(argv=None):
    args = list(sys.argv[1:] if argv is None else argv)
    dry = '--dry-run' in args
    args = [a for a in args if not a.startswith('--')]
    if len(args) != 1:
        print(__doc__)
        return 1
    data_dir = args[0]
    ok, why = client_pair.allows(data_dir, client_pair.PAIR_PICKUPS, 'pickups')
    print(why)
    if not ok:
        return 0
    cfg = read_config()
    otb = os.path.join(data_dir, 'items', 'items.otb')
    xml = os.path.join(data_dir, 'items', 'items.xml')
    for path in (otb, xml):
        if not os.path.exists(path):
            print('not found:', path)
            return 1
    raw = open(otb, 'rb').read()
    new, notes, wanted = patch_otb(raw, cfg)
    n = verify_otb(new, wanted)
    for note in notes:
        print(note)
    print('items.otb: verified (%d item nodes)' % n)
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
