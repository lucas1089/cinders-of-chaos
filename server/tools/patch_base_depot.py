#!/usr/bin/env python3
"""Depot tabs: make the base server's depot boxes the tabs of the depot chest (server/README.md "Depot tabs").

usage: python3 -I patch_base_depot.py DATA_DIR [--dry-run]

The box ids, their name pattern and their slots are read from server/data/scripts/chaos/depot_config.lua (boxIds,
boxName, boxSlots), the same file the Lua side (depot.lua) uses.

1. data/items/items.otb: the depot boxes (stock "depot box I" .. "XVII", 25453..25469) get the pickupable flag. The
   engine refuses to add an item that is not pickupable to any container, so without it no script can put a box into a
   depot chest (the base only ever loaded boxes from the database). They stay NOT moveable: a player cannot drag a
   box out of the chest (Game::playerMoveItem refuses items that are not moveable). Nothing else in the node changes.
   items.otb.bak keeps the original the first time; the written file is parsed again and the boxes checked.
2. data/items/items.xml: each box entry gets the name "depot tab <n>" and containerSize = boxSlots (100, stock 32), so
   a tab has a slot for every item it may hold. Other attributes of the entry are kept. A box id inside a fromid/toid
   range stops the script (nothing written).
3. data/scripts/customs/actions/sounds/depot.lua (the base locker Action, it plays a sound): its onUse first calls
   ChaosDepot.onOpenLocker(player, item), which makes the boxes, sorts loose items of before tabs into them and updates
   the look texts and the client. The Action's return value is unchanged (the engine then opens the locker). When the
   file does not exist, nothing is written: depot.lua registers its own locker Action then.
4. data/events/scripts/player.lua: Player:onMoveItem asks ChaosDepot.onMoveItem first (a move that adds to a locked or
   full tab, or loose into the depot chest, is refused with a message). Only a refusal returns early; otherwise the base
   function runs exactly as before. A script callback cannot refuse a move reliably (the base EventCallback dispatcher
   keeps only the last onMoveItem callback's value), hence the hook, as for the store pouches.

Idempotent: a second run changes nothing.
"""
import os, re, struct, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from install_gems import scan, escape, attr, START, END, FLAG_PICKUPABLE, FLAG_MOVEABLE  # noqa: E402

CONFIG = os.path.join(os.path.dirname(HERE), 'data', 'scripts', 'chaos', 'depot_config.lua')
XML_MARK = '<!-- Chaos depot tab (server/tools/patch_base_depot.py) -->'
LOCKER_MARK = '-- Chaos: depot tabs (patch_base_depot.py)'
MOVE_MARK = '-- Chaos: depot tab limits (patch_base_depot.py)'
MOVE_HOOK = (
    '\t' + MOVE_MARK + '\n'
    '\tif ChaosDepot and ChaosDepot.onMoveItem then\n'
    '\t\tlocal chaosDepotRet = ChaosDepot.onMoveItem(self, item, count, fromPosition, toPosition, fromCylinder, toCylinder)\n'
    '\t\tif chaosDepotRet and chaosDepotRet ~= RETURNVALUE_NOERROR then\n'
    '\t\t\treturn chaosDepotRet\n'
    '\t\tend\n'
    '\tend\n'
)


def read_config(path=CONFIG):
    text = open(path, encoding='utf-8').read()
    ids = [int(x) for x in re.findall(r'\d+', re.search(r'\bboxIds\s*=\s*\{([^}]*)\}', text).group(1))]
    name = re.search(r'\bboxName\s*=\s*"([^"]*)"', text).group(1)
    slots = int(re.search(r'\bboxSlots\s*=\s*(\d+)', text).group(1))
    assert ids and len(set(ids)) == len(ids), 'depot_config.lua: boxIds empty or repeated'
    assert '%d' in name, 'depot_config.lua: boxName needs %d'
    assert 1 <= slots <= 255, 'depot_config.lua: boxSlots 1..255 (one byte in the protocol)'
    return ids, name, slots


# ------------------------------------------------------------------------------------------------ items.otb
def box_node(k):
    """the node with the pickupable flag (moveable stays as it is: off for the stock boxes)"""
    _s, _e, _sid, _cid, group, flags, attrs = k
    body = struct.pack('<I', flags | FLAG_PICKUPABLE)
    for kind, v in attrs:
        body += attr(kind, v)
    return bytes([START]) + escape(bytes([group])) + escape(body) + bytes([END])


def patch_otb(data, ids):
    kids, _root_end = scan(data)
    by_sid = {k[2]: k for k in kids}
    replace, notes = [], []
    for sid in ids:
        k = by_sid.get(sid)
        if k is None:
            raise SystemExit('items.otb: no node for depot box %d; nothing written' % sid)
        if k[5] & FLAG_PICKUPABLE:
            continue
        replace.append((k[0], k[1], box_node(k)))
    out = bytearray(data)
    for s, e, b in sorted(replace, reverse=True):
        out[s:e] = b
    notes.append('items.otb: %d depot box(es) made pickupable' % len(replace) if replace else
                 'items.otb: the %d depot boxes are pickupable' % len(ids))
    return bytes(out), notes


def verify_otb(data, ids):
    kids, _ = scan(data)
    by_sid = {k[2]: k for k in kids}
    for sid in ids:
        k = by_sid.get(sid)
        assert k and k[5] & FLAG_PICKUPABLE, 'depot box %d not pickupable' % sid
        assert not (k[5] & FLAG_MOVEABLE), 'depot box %d is moveable: a player could take it out of the chest' % sid
    return len(kids)


# ------------------------------------------------------------------------------------------------ items.xml
def patch_xml(text, ids, name, slots):
    nl = '\r\n' if '\r\n' in text else '\n'
    changed = 0
    for n, sid in enumerate(ids, 1):
        for m in re.finditer(r'<item\b[^>]*\bfromid="(\d+)"[^>]*\btoid="(\d+)"', text):
            if int(m.group(1)) <= sid <= int(m.group(2)):
                raise SystemExit('items.xml: depot box %d is inside the range %s..%s; nothing written'
                                 % (sid, m.group(1), m.group(2)))
        m = re.search(r'([ \t]*)<item\b[^>]*\bid="%d"[^>]*?(/>|>.*?</item>)' % sid, text, re.S)
        if not m:
            raise SystemExit('items.xml: no entry for depot box %d; nothing written' % sid)
        indent = m.group(1)
        inner = m.group(2)
        keep = []
        if inner != '/>':
            for line in re.findall(r'<attribute\b[^>]*/>', inner):
                if not re.search(r'key="containerSize"', line, re.I):
                    keep.append(line)
        lines = [indent + '<item id="%d" article="a" name="%s">' % (sid, name % n),
                 indent + '\t' + XML_MARK,
                 indent + '\t<attribute key="containerSize" value="%d" />' % slots]
        lines += [indent + '\t' + line for line in keep]
        lines.append(indent + '</item>')
        want = nl.join(lines)
        if text[m.start():m.end()] != want:
            text = text[:m.start()] + want + text[m.end():]
            changed += 1
    note = ('items.xml: %d depot box entr%s renamed to tabs (%d slots)' % (changed, 'y' if changed == 1 else 'ies', slots)
            if changed else 'items.xml: the %d depot tab entries are present' % len(ids))
    return text, note


# ------------------------------------------------------------------------------------------------ scripts
def patch_locker(text):
    if LOCKER_MARK in text:
        return text, 'depot.lua: locker hook present'
    m = re.search(r'function\s+[\w.:]+\.onUse\((\w+),\s*(\w+)[^)]*\)[ \t]*\r?\n', text)
    if not m:
        raise SystemExit('depot.lua: no onUse(player, item, ...) function found; nothing written')
    nl = '\r\n' if '\r\n' in m.group(0) else '\n'
    player, item = m.group(1), m.group(2)
    hook = ('    ' + LOCKER_MARK + nl +
            '    if ChaosDepot and ChaosDepot.onOpenLocker then' + nl +
            '        ChaosDepot.onOpenLocker(%s, %s)' % (player, item) + nl +
            '    end' + nl)
    return text[:m.end()] + hook + text[m.end():], 'depot.lua: locker hook added to the locker onUse'


def patch_player(text):
    if MOVE_MARK in text:
        return text, 'player.lua: depot move hook present'
    m = re.search(r'function Player:onMoveItem\(item, count, fromPosition, toPosition, fromCylinder, toCylinder\)[ \t]*\r?\n',
                  text)
    if not m:
        raise SystemExit('player.lua: Player:onMoveItem(item, count, fromPosition, toPosition, fromCylinder, toCylinder) '
                         'not found; nothing written')
    hook = MOVE_HOOK.replace('\n', '\r\n') if m.group(0).endswith('\r\n') else MOVE_HOOK
    return text[:m.end()] + hook + text[m.end():], 'player.lua: depot move hook added to Player:onMoveItem'


def main():
    args = sys.argv[1:]
    dry = '--dry-run' in args
    args = [a for a in args if not a.startswith('--')]
    if len(args) != 1:
        print(__doc__)
        return 1
    data_dir = args[0]
    ids, name, slots = read_config()
    otb = os.path.join(data_dir, 'items', 'items.otb')
    xml = os.path.join(data_dir, 'items', 'items.xml')
    player = os.path.join(data_dir, 'events', 'scripts', 'player.lua')
    locker = os.path.join(data_dir, 'scripts', 'customs', 'actions', 'sounds', 'depot.lua')
    for path in (otb, xml, player):
        if not os.path.exists(path):
            print('not found:', path)
            return 1
    raw = open(otb, 'rb').read()
    new, notes = patch_otb(raw, ids)
    n = verify_otb(new, ids)
    for note in notes:
        print(note)
    print('items.otb: verified (%d item nodes; depot boxes %d..%d)' % (n, ids[0], ids[-1]))
    text = open(xml, encoding='utf-8', errors='surrogateescape', newline='').read()
    new_text, xnote = patch_xml(text, ids, name, slots)
    print(xnote)
    ptext = open(player, encoding='utf-8', errors='surrogateescape', newline='').read()
    new_ptext, pnote = patch_player(ptext)
    print(pnote)
    ltext = new_ltext = None
    if os.path.exists(locker):
        ltext = open(locker, encoding='utf-8', errors='surrogateescape', newline='').read()
        new_ltext, lnote = patch_locker(ltext)
        print(lnote)
    else:
        print('depot.lua: %s not found; depot.lua (Chaos) registers its own locker Action' % locker)
    if dry:
        print('dry run: nothing written')
        return 0
    if new != raw:
        if not os.path.exists(otb + '.bak'):
            open(otb + '.bak', 'wb').write(raw)
        open(otb, 'wb').write(new)
    if new_text != text:
        open(xml, 'w', encoding='utf-8', errors='surrogateescape', newline='').write(new_text)
    if new_ptext != ptext:
        open(player, 'w', encoding='utf-8', errors='surrogateescape', newline='').write(new_ptext)
    if ltext is not None and new_ltext != ltext:
        open(locker, 'w', encoding='utf-8', errors='surrogateescape', newline='').write(new_ltext)
    return 0


if __name__ == '__main__':
    sys.exit(main())
