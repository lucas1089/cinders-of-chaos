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
from install_gems import scan, escape, attr, START, END, A_CLIENTID, FLAG_ANIMATION  # noqa: E402

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
    otb_raw = otb_new = None
    if os.path.isfile(otb_path):
        otb_raw = open(otb_path, 'rb').read()
        try:
            otb_new, changed, wanted = patch_otb(otb_raw, bases(), stock_looks)
            n = verify_otb(otb_new, wanted)
        except (OtbError, AssertionError, IndexError, struct.error) as e:
            out(str(e))
            return 1
        out('jewelry looks: %d of %d base node(s) %s %s (%d item nodes)%s'
            % (len(changed), len(wanted), 'set to the' if changed else 'already on the',
               'stock client ids' if stock_looks else 'own looks 38612+ (pair 35)', n,
               ''.join('; %d: %s -> %d' % c for c in changed[:3]) + ('; ...' if len(changed) > 3 else '')))
    else:
        out('no items.otb: %s (jewelry looks not checked)' % otb_path)
    skip = consumables()
    text = open(items_path, encoding='latin-1').read()
    edits, merged, counts = plan(text, skip)
    new = apply(text, edits)
    ids = unworn_ids(new, skip)
    ids.update(merged)
    todo = bool(edits)
    added = 0
    if os.path.isfile(moves_path):
        mtext = open(moves_path, encoding='latin-1').read()
        mnew, added = patch_movements(mtext, ids)
        todo = todo or added > 0
        if added and not dry and not check:
            open(moves_path, 'w', encoding='latin-1', newline='').write(mnew)
    else:
        out('no movements.xml: %s (DeEquip entries not checked)' % moves_path)
    if edits and not dry and not check:
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
