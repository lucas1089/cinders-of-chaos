#!/usr/bin/env python3
"""Rings and necklaces become permanent equipment (idempotent). install_all.py step `jewelry`.

usage: python3 -I patch_base_jewelry.py DATA_DIR [--dry-run] [--check] [--stock-looks]

server/README.md "Rings and necklaces as gear". Owner request 2026-10-22: "faça rings e necklaces iguais a equips
normais. pra equipar, com affixo e suffixo". In the base, most rings change id when worn (transformEquipTo) and the worn
id runs out (duration, decayTo 0); most amulets have charges and vanish at 0. A copy with a rarity, prefixes and
suffixes vanished with them, and the unworn id had no stats, so the loot layer never rolled it. In
data/items/items.xml, for every item with slotType ring or necklace that is not a consumable
(data/lib/chaos_jewelry.lua `consumable`: stealth, energy, time, dwarven and might rings, the amulet of loss, the stone
skin amulet and the four 5-charge elemental amulets keep the base rules):

1. an unworn ring or necklace whose worn id (transformEquipTo) has stats gets those stats on itself (the worn values
   win over its own), loses transformEquipTo, stopduration and showduration, and shows its attributes; it is worn as
   it is from now on;
2. a worn id (duration, decayTo 0, transformDeEquipTo) loses duration, decayTo and showduration: a copy worn before the
   install keeps working and turns back into the unworn id when taken off, as before;
3. charges and showcharges go.

data/movements/movements.xml: every unworn id of step 1 gets a DeEquip entry next to its Equip entry (the base had
none: the worn id took the stats off), so taking it off removes its stats. Both entries are added when it had neither.

data/items/items.otb: every loot base of chaos_jewelry.lua `J.bases` shows its own look, the client id `look` of pair
35 (client/tools/sprites/gen_jewelry_art.py, client/MANIFEST.md "Jewelry looks (pair 35)"). Owner request 2026-10-22:
"use sprites de rings e necklaces dos nossos assets". The node keeps its server id, group, flags and every other
attribute; only the client id changes, and FLAG_ANIMATION goes (each own look has one phase; the stock lightning
pendant is animated, and an animated node whose look has one phase breaks the protocol). --stock-looks puts the stock
client id (`stock`) back instead, for a client on pair 34 or older, which has no thing 38612+. A node with another
client id than `look` or `stock`, a base missing from items.otb, or a `look` another node already uses stops the step
before anything is written. items.otb.bak keeps the original the first time; the written file is parsed again and
checked. Without items.otb (a test folder) this part is skipped.

Uniques on consumable bases (chaos_jewelry.lua `J.uniqueBases`: Ring of the Last Ember, Heart of Cinders, Heartbleed
Pendant) get bases of their own, server ids 41640-41642: items.otb copies of the stock nodes (same client id and
flags) with the new ids, one marked items.xml block with weight, slotType and the unique's stats no item attribute holds
(the `skipped` of gen_unique_specs.py, read from chaos_items.xml), and Equip / DeEquip entries in movements.xml. An id
already used elsewhere stops the step before anything is written.

Nothing else of the files is rewritten. A second run changes nothing. --check changes nothing and exits 1 when
something is still to do.
"""
import os
import re
import struct
import sys

sys.dont_write_bytecode = True

HERE = os.path.dirname(os.path.abspath(__file__))
LIB = os.path.join(os.path.dirname(HERE), 'data', 'lib', 'chaos_jewelry.lua')
sys.path.insert(0, HERE)
from install_gems import scan, escape, attr, START, END, A_SERVERID, A_CLIENTID, FLAG_ANIMATION  # noqa: E402
from gen_unique_specs import ITEM_ATTR, CUSTOM, STRUCTURAL  # noqa: E402

CHAOS_ITEMS = os.path.join(os.path.dirname(HERE), 'data', 'items', 'chaos_items.xml')
XML_BEGIN = '\t<!-- Chaos unique bases (server/tools/patch_base_jewelry.py, do not edit by hand) -->\n'
XML_END = '\t<!-- end of the Chaos unique bases -->\n'

# loot bases whose stock look is animated in the base (items.otb flag): --stock-looks sets the flag again
STOCK_ANIMATED = {7889}

JEWEL_SLOTS = {'ring', 'necklace'}
# keys that are no stat of a ring or necklace: the patch never copies them from a worn id
MECHANICS = {'weight', 'slottype', 'charges', 'showcharges', 'duration', 'showduration', 'decayto', 'transformequipto',
             'transformdeequipto', 'stopduration', 'description', 'showattributes', 'article', 'plural', 'name',
             'writeable', 'maxtextlen', 'pickupable', 'movable', 'containersize', 'primarytype'}
DROP_ON_MERGE = {'transformequipto', 'stopduration', 'showduration'}
DROP_ON_WORN = {'duration', 'decayto', 'showduration'}
DROP_CHARGES = {'charges', 'showcharges'}

ITEM = re.compile(r'<item\b([^>]*?)(/?)>', re.S)
ATTR = re.compile(r'^([ \t]*)<attribute\s+key="([^"]+)"\s+value="([^"]*)"\s*/>[ \t]*\r?\n', re.M)


def consumables(path=LIB):
    """the ids of chaos_jewelry.lua `J.consumable`"""
    text = open(path, encoding='utf-8').read()
    block = text.partition('J.consumable = {')[2].partition('\n}')[0]
    return {int(x) for x in re.findall(r'\[(\d+)\]\s*=', block)}


def bases(path=LIB):
    """[(server id, own client id, stock client id)] of chaos_jewelry.lua `J.bases`"""
    text = open(path, encoding='utf-8').read()
    block = text.partition('J.bases = {')[2].partition('\n}\n')[0]
    return [(int(a), int(b), int(c)) for a, b, c in
            re.findall(r'\{id = (\d+), level = \d+, name = "[^"]+", look = (\d+), stock = (\d+)\}', block)]


class OtbError(Exception):
    pass


def otb_node(k, client_id, flags):
    """the node k of scan() with another client id and flags (group and every other attribute as they are)"""
    _s, _e, sid, _cid, group, _flags, attrs = k
    body = struct.pack('<I', flags)
    seen = False
    for kind, v in attrs:
        if kind == A_CLIENTID:
            v = struct.pack('<H', client_id)
            seen = True
        body += attr(kind, v)
    if not seen:
        raise OtbError('items.otb: node %d has no client id' % sid)
    return bytes([START]) + escape(bytes([group])) + escape(body) + bytes([END])


def patch_otb(data, rows, stock_looks=False):
    """(new data, changed [(server id, old client id, new client id)], wanted {server id: (client id, flags)})"""
    kids, _ = scan(data)
    by_sid = {k[2]: k for k in kids}
    edits, changed, wanted = [], [], {}
    for sid, look, stock in rows:
        k = by_sid.get(sid)
        if k is None:
            raise OtbError('items.otb: no node %d (a jewelry base); nothing written' % sid)
        if k[3] not in (look, stock):
            raise OtbError('items.otb: node %d has client id %s, not %d (own look) or %d (stock); nothing written'
                           % (sid, k[3], look, stock))
        want = stock if stock_looks else look
        if want == look:
            if any(o[3] == look and o[2] != sid for o in kids):
                raise OtbError('items.otb: client id %d (look of %d) is already used by another node; nothing written'
                               % (look, sid))
            flags = k[5] & ~FLAG_ANIMATION
        elif k[3] == look:
            flags = k[5] | (FLAG_ANIMATION if sid in STOCK_ANIMATED else 0)
        else:
            flags = k[5]
        wanted[sid] = (want, flags)
        if k[3] != want or k[5] != flags:
            edits.append((k[0], k[1], otb_node(k, want, flags)))
            changed.append((sid, k[3], want))
    out = bytearray(data)
    for s, e, new in sorted(edits, reverse=True):
        out[s:e] = new
    return bytes(out), changed, wanted


def verify_otb(data, wanted):
    kids, _ = scan(data)
    by_sid = {k[2]: k for k in kids}
    for sid, (cid, flags) in wanted.items():
        k = by_sid.get(sid)
        if not k or k[3] != cid or k[5] != flags:
            raise OtbError('items.otb: node %d not as written' % sid)
    sids = [k[2] for k in kids]
    if len(sids) != len(set(sids)):
        raise OtbError('items.otb: duplicate server ids')
    return len(kids)


# ------------------------------------------------------------------ own bases of the uniques (J.uniqueBases)
def unique_bases(path=LIB):
    """[{id, copy, from, slot, name, unique}] of chaos_jewelry.lua `J.uniqueBases`"""
    text = open(path, encoding='utf-8').read()
    block = text.partition('J.uniqueBases = {')[2].partition('\n}\n')[0]
    out = []
    for m in re.finditer(r'\{id = (\d+), copy = (\d+), from = \{([\d, ]+)\}, slot = "(\w+)", name = "([^"]+)",\s*'
                         r'unique = "([^"]+)"\}', block):
        out.append({'id': int(m.group(1)), 'copy': int(m.group(2)),
                    'from': [int(x) for x in m.group(3).split(',')], 'slot': m.group(4), 'name': m.group(5),
                    'unique': m.group(6)})
    return out


def unique_type_stats(rows, path=CHAOS_ITEMS):
    """id -> [(key, value)] of the items.xml entry: weight, slotType, the unique's stats no item attribute holds (the
    `skipped` of gen_unique_specs.py), showattributes"""
    xml = open(path, encoding='utf-8').read()
    out = {}
    for r in rows:
        m = re.search(r'<item id="%d"[^>]*name="([^"]+)"[^>]*>(.*?)</item>' % r['id'], xml, re.S)
        if not m or m.group(1) != r['unique']:
            raise OtbError('chaos_items.xml: no unique "%s" with id %d' % (r['unique'], r['id']))
        attrs = re.findall(r'<attribute key="(\w+)" value="([^"]*)"', m.group(2))
        keys = dict(attrs)
        if keys.get('slotType') != r['slot']:
            raise OtbError('chaos_items.xml: %d is no %s' % (r['id'], r['slot']))
        rows_ = [('weight', keys.get('weight', '100')), ('slotType', r['slot'])]
        rows_ += [(k, v) for k, v in attrs if k not in ITEM_ATTR and k not in CUSTOM and k not in STRUCTURAL]
        out[r['id']] = rows_ + [('showattributes', '1')]
    return out


def unique_xml_block(rows, stats):
    body = ''
    for r in rows:
        body += '\t<item id="%d" article="a" name="%s">\n' % (r['id'], r['name'])
        body += ''.join('\t\t<attribute key="%s" value="%s" />\n' % kv for kv in stats[r['id']])
        body += '\t</item>\n'
    return XML_BEGIN + body + XML_END


def patch_unique_xml(text, rows, block):
    """items.xml with the block of the unique bases (replaced in place, or before </items>)"""
    if XML_BEGIN in text:
        start = text.index(XML_BEGIN)
        end = text.index(XML_END, start) + len(XML_END)
        outside = text[:start] + text[end:]
    else:
        start = end = text.rfind('</items>')
        if start < 0:
            raise OtbError('items.xml: no </items>')
        outside = text
    ranges = [(int(a), int(b)) for a, b in re.findall(r'<item\b[^>]*\bfromid="(\d+)"[^>]*\btoid="(\d+)"', outside)]
    for r in rows:
        if re.search(r'<item\b[^>]*\bid="%d"' % r['id'], outside) or any(a <= r['id'] <= b for a, b in ranges):
            raise OtbError('items.xml: server id %d is already used; nothing written' % r['id'])
    return text[:start] + block + text[end:]


def copy_node(source, sid):
    """the stock node `source` of scan() with another server id (group, flags, client id and the rest as they are)"""
    _s, _e, _sid, _cid, group, flags, attrs = source
    body = struct.pack('<I', flags)
    for kind, v in attrs:
        if kind == A_SERVERID:
            v = struct.pack('<H', sid)
        body += attr(kind, v)
    return bytes([START]) + escape(bytes([group])) + escape(body) + bytes([END])


def add_unique_nodes(data, rows):
    """(new data, added or updated ids, wanted {id: node bytes})"""
    out, notes, wanted = bytes(data), [], {}
    for r in rows:
        kids, root_end = scan(out)
        by_sid = {k[2]: k for k in kids}
        source = by_sid.get(r['copy'])
        if source is None:
            raise OtbError('items.otb: no stock node %d (the base of %s); nothing written' % (r['copy'], r['unique']))
        want = copy_node(source, r['id'])
        k = by_sid.get(r['id'])
        buf = bytearray(out)
        if k is None:
            buf[root_end:root_end] = want
            notes.append(r['id'])
        elif k[3] != source[3]:
            raise OtbError('items.otb: server id %d already belongs to client id %s, not %d; nothing written'
                           % (r['id'], k[3], source[3]))
        elif out[k[0]:k[1]] != want:
            buf[k[0]:k[1]] = want
            notes.append(r['id'])
        out = bytes(buf)
        wanted[r['id']] = want
    return out, notes, wanted


def verify_unique_nodes(data, wanted):
    kids, _ = scan(data)
    for k in kids:
        if k[2] in wanted and data[k[0]:k[1]] != wanted[k[2]]:
            raise OtbError('items.otb: node %d not as written' % k[2])
    if not set(wanted) <= {k[2] for k in kids}:
        raise OtbError('items.otb: a unique base node is missing after the write')


def parse_items(text):
    """id -> {start, end (of the body), attrs: [(key lower, value, line start, line end, indent, key)]}"""
    out = {}
    for m in ITEM.finditer(text):
        head, closed = m.group(1), m.group(2)
        idm = re.search(r'\bid="(\d+)"', head)
        if not idm or closed:
            continue
        end = text.find('</item>', m.end())
        nxt = text.find('<item', m.end())
        if end < 0 or (0 <= nxt < end):
            continue  # an item with nested items (none for jewelry): left alone
        attrs = []
        for a in ATTR.finditer(text, m.end(), end):
            attrs.append((a.group(2).lower(), a.group(3), a.start(), a.end(), a.group(1), a.group(2)))
        out[int(idm.group(1))] = {'start': m.end(), 'end': end, 'attrs': attrs}
    return out


def attr_map(entry):
    return {a[0]: a[1] for a in entry['attrs']}


def is_jewel(entry):
    return attr_map(entry).get('slottype', '').lower() in JEWEL_SLOTS


def stats(entry):
    """[(key as written, value)] of the attributes that are stats"""
    return [(a[5], a[1]) for a in entry['attrs'] if a[0] not in MECHANICS]


def plan(text, skip):
    """(edits [(start, end, new text)], merged unworn ids {id: slot}, counts)"""
    items = parse_items(text)
    edits, merged = [], {}
    counts = {'merged': 0, 'worn': 0, 'charges': 0}
    for iid in sorted(items):
        entry = items[iid]
        if iid in skip or not is_jewel(entry):
            continue
        amap = attr_map(entry)
        drop = set()
        add = []
        worn = int(amap['transformequipto']) if amap.get('transformequipto', '').isdigit() else 0
        wentry = items.get(worn)
        if worn and worn not in skip and wentry and is_jewel(wentry) and stats(wentry):
            drop |= DROP_ON_MERGE
            own = {a[0]: a for a in entry['attrs']}
            for key, value in stats(wentry):
                a = own.get(key.lower())
                if a is None:
                    add.append((key, value))
                elif a[1] != value:
                    edits.append((a[2], a[3], '%s<attribute key="%s" value="%s" />\n' % (a[4], a[5], value)))
            if amap.get('showattributes') != '1' and 'showattributes' not in own:
                add.append(('showattributes', '1'))
            merged[iid] = amap.get('slottype', '').lower()
            counts['merged'] += 1
        if amap.get('duration') and amap.get('decayto') == '0' and amap.get('transformdeequipto'):
            drop |= DROP_ON_WORN
            counts['worn'] += 1
        if 'charges' in amap:
            drop |= DROP_CHARGES
            counts['charges'] += 1
        for a in entry['attrs']:
            if a[0] in drop:
                edits.append((a[2], a[3], ''))
        if add:
            indent = entry['attrs'][0][4] if entry['attrs'] else '\t\t'
            # before the line that holds </item>
            line_start = text.rfind('\n', 0, entry['end']) + 1
            body = ''.join('%s<attribute key="%s" value="%s" />\n' % (indent, k, v) for k, v in add)
            edits.append((line_start, line_start, body))
    return edits, merged, counts


def apply(text, edits):
    for start, end, new in sorted(edits, key=lambda e: (e[0], e[1]), reverse=True):
        text = text[:start] + new + text[end:]
    return text


def unworn_ids(text, skip):
    """the jewelry ids step 1 merged already or will merge (an earlier run left no transformEquipTo): the ids that a
    worn id with stats turns back into"""
    items = parse_items(text)
    out = {}
    for iid, entry in items.items():
        if iid in skip or not is_jewel(entry):
            continue
        back = attr_map(entry).get('transformdeequipto', '')
        if back.isdigit() and stats(entry) and int(back) not in skip and int(back) in items and is_jewel(items[int(back)]):
            out[int(back)] = attr_map(items[int(back)]).get('slottype', '').lower()
    return out


def covers(text, event, iid):
    """True when movements.xml has an `event` entry for iid (by itemid or a fromid/toid range)"""
    for m in re.finditer(r'<movevent\b[^>]*\bevent="%s"[^>]*>' % event, text, re.I):
        tag = m.group(0)
        one = re.search(r'\bitemid="(\d+)"', tag)
        if one and int(one.group(1)) == iid:
            return True
        lo, hi = re.search(r'\bfromid="(\d+)"', tag), re.search(r'\btoid="(\d+)"', tag)
        if lo and hi and int(lo.group(1)) <= iid <= int(hi.group(1)):
            return True
    return False


def patch_movements(text, ids):
    """adds the missing DeEquip (and Equip) entries; returns text, added"""
    added = 0
    for iid in sorted(ids):
        if covers(text, 'DeEquip', iid):
            continue
        slot = ids[iid] or 'ring'
        line = '\t<movevent event="DeEquip" itemid="%d" slot="%s" function="onDeEquipItem" />\n' % (iid, slot)
        eq = re.search(r'^[ \t]*<movevent\b[^>]*\bevent="Equip"[^>]*\bitemid="%d"[^>]*?(/>|>.*?</movevent>)[^\n]*\n'
                       % iid, text, re.M | re.S)
        if eq:
            text = text[:eq.end()] + line + text[eq.end():]
        else:
            close = text.rfind('</movements>')
            if close < 0:
                continue
            line = ('\t<movevent event="Equip" itemid="%d" slot="%s" function="onEquipItem" />\n' % (iid, slot)) + line
            text = text[:close] + line + text[close:]
        added += 1
    return text, added


def run(data, dry=False, check=False, out=print, stock_looks=False):
    items_path = os.path.join(data, 'items', 'items.xml')
    moves_path = os.path.join(data, 'movements', 'movements.xml')
    otb_path = os.path.join(data, 'items', 'items.otb')
    if not os.path.isfile(items_path):
        out('no items.xml: %s' % items_path)
        return 1
    try:
        ubases = unique_bases()
        ublock = unique_xml_block(ubases, unique_type_stats(ubases))
    except OtbError as e:
        out(str(e))
        return 1
    otb_raw = otb_new = None
    if os.path.isfile(otb_path):
        otb_raw = open(otb_path, 'rb').read()
        try:
            otb_new, changed, wanted = patch_otb(otb_raw, bases(), stock_looks)
            n = verify_otb(otb_new, wanted)
            otb_new, unotes, uwanted = add_unique_nodes(otb_new, ubases)
            verify_unique_nodes(otb_new, uwanted)
            verify_otb(otb_new, wanted)
        except (OtbError, AssertionError, IndexError, struct.error) as e:
            out(str(e))
            return 1
        out('jewelry looks: %d of %d base node(s) %s %s (%d item nodes)%s'
            % (len(changed), len(wanted), 'set to the' if changed else 'already on the',
               'stock client ids' if stock_looks else 'own looks 38612+ (pair 35)', n,
               ''.join('; %d: %s -> %d' % c for c in changed[:3]) + ('; ...' if len(changed) > 3 else '')))
        out('unique bases: %s' % (', '.join('%d (copy of %d)' % (r['id'], r['copy']) for r in ubases)
                                  + (' added or updated' if unotes else ' present')))
    else:
        out('no items.otb: %s (jewelry looks not checked)' % otb_path)
    skip = consumables()
    text = open(items_path, encoding='latin-1').read()
    edits, merged, counts = plan(text, skip)
    new = apply(text, edits)
    try:
        new = patch_unique_xml(new, ubases, ublock)
    except OtbError as e:
        out(str(e))
        return 1
    ids = unworn_ids(new, skip)
    ids.update(merged)
    ids.update({r['id']: r['slot'] for r in ubases})
    todo = new != text
    added = 0
    if os.path.isfile(moves_path):
        mtext = open(moves_path, encoding='latin-1').read()
        mnew, added = patch_movements(mtext, ids)
        todo = todo or added > 0
        if added and not dry and not check:
            open(moves_path, 'w', encoding='latin-1', newline='').write(mnew)
    else:
        out('no movements.xml: %s (DeEquip entries not checked)' % moves_path)
    if new != text and not dry and not check:
        open(items_path, 'w', encoding='latin-1', newline='').write(new)
    if otb_new is not None and otb_new != otb_raw:
        todo = True
        if not dry and not check:
            if not os.path.exists(otb_path + '.bak'):
                open(otb_path + '.bak', 'wb').write(otb_raw)
            open(otb_path, 'wb').write(otb_new)
    out('jewelry: %d unworn id(s) given their worn stats, %d worn id(s) without duration, %d without charges, '
        '%d DeEquip entr%s added%s' % (counts['merged'], counts['worn'], counts['charges'], added,
                                       'y' if added == 1 else 'ies',
                                       ' (check)' if check else (' (dry run)' if dry else '')))
    if check and todo:
        return 1
    return 0


def main(argv):
    args = [a for a in argv if not a.startswith('--')]
    if len(args) != 1:
        print(__doc__)
        return 2
    return run(args[0], dry='--dry-run' in argv, check='--check' in argv, stock_looks='--stock-looks' in argv)


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
