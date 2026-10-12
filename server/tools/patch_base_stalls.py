#!/usr/bin/env python3
"""Base server scripts that held or loaded the game loop (server/README.md "Game loop stalls").

usage: python3 -I patch_base_stalls.py DATA_DIR [--dry-run]

1. The expedition announcements (data/scripts/customs/expeditions_system/expeditions/**/*.lua). At each spawn time
   (onTime, about 11 times a day per script) a script announces the new expedition NPC or boss to the players on its
   island: it looks at every tile of a box, and a tile whose top creature is a player gets the sound, the map marks and
   the broadcast. The big box (30726,30879 - 31758,31485, floor 7) has 627,000 tiles: one scan held the game loop for
   0.6-0.9 s, and 24 scripts do it. Each such scan loop
       for x = FROM.x, TO.x do
           for y = FROM.y, TO.y do
               local checkPos = Position(x, y, FROM.z)
               local tile = Tile(checkPos)
               ... tile:getTopCreature() ... creature:isPlayer() ...
   becomes a loop over the same positions that hold a player (from Game.getPlayers(), in the same x-then-y order), with
   the body untouched. A tile without a player never had a player as its top creature, so every player, sound, map
   mark and broadcast stays the same. Loops that look for something else (a boss to remove) are not touched. A local
   helper is added at the top of each changed file.
2. The upgrade slots (data/scripts/customs/upgrade/upgrade_slot_item.lua). Every 100 ms per player online the script
   reads the description of every worn item and parses its "[Name+N]" slots. The parse is now kept per description
   text: the same text gives the same slots, so only a new or changed description is parsed again (the description is
   still read every time). This took most of the script's garbage (a pattern iterator and tables per item, 10 times a
   second per player), which the Lua collector then had to sweep inside other tasks.
3. The same check, less often. Each player had its own 100 ms timer (addEvent at the end of the check, started at
   login): about 13% of the game loop at 200 online even with the cache of 2. The check now runs at login (as before),
   at once when an item is put on or taken off (EventCallback onItemMoved with an inventory slot on either side: drag
   and drop, the equip hotkey and right-click equips since engine patch 0024), and once a second for every player
   online in 12 groups (player id modulo 12, one group every 83 ms, like item_mods.lua) for the other ways a worn item
   changes (decay, a script's moveTo, an upgrade or an orb used on a worn item). A player who left is dropped from the
   script's cache by the group pass, as the stock timer did. The check itself is unchanged. After a reload of the
   scripts the new chain takes over the players online and the old one stops.

Every change carries a marker and is made once (3 has its own marker, so a base patched by an older version of
this tool gets 3 too) (a second run changes nothing). A file without the stock code is left
alone: exit status 0, an install without these base scripts has nothing to do.
"""
import os
import re
import sys

MARK = 'Chaos (patch_base_stalls.py)'
EXPEDITIONS = ('scripts', 'customs', 'expeditions_system', 'expeditions')
UPGRADE = ('scripts', 'customs', 'upgrade', 'upgrade_slot_item.lua')

# ------------------------------------------------------------------------------------------------ 1. expeditions
# the scan of a box for players: two loops, the position, the tile and (a few lines on) a player as the top creature
LOOP_RE = re.compile(
    r'^(?P<i>[ \t]*)for x = (?P<f>[A-Za-z_]\w*)\.x, (?P<t>[A-Za-z_]\w*)\.x do[ \t]*\r?\n'
    r'(?P<i2>[ \t]*)for y = (?P=f)\.y, (?P=t)\.y do[ \t]*\r?\n'
    r'(?P<i3>[ \t]*)local checkPos = Position\(x, y, (?P=f)\.z\)[ \t]*\r?\n'
    r'(?=[ \t]*local tile = Tile\(checkPos\)[ \t]*\r?\n(?:[ \t]*\r?\n)*'
    r'[ \t]*if tile then[ \t]*\r?\n[ \t]*local (?P<c>[A-Za-z_]\w*) = tile:getTopCreature\(\)[ \t]*\r?\n'
    r'[ \t]*if (?P=c) and (?P=c):isPlayer\(\) then)', re.M)

LOOP_NEW = (
    '{i}for _, checkPos in ipairs(chaosPlayerTiles({f}, {t})) do -- %s: no map scan\n'
    '{i2}do\n'
    '{i3}local x, y = checkPos.x, checkPos.y\n') % MARK

PLAYER_TILES = (
    '-- %s: the positions in the box (fromPos.z only) that hold a player, in the order\n'
    '-- of the stock scan (x, then y). A tile without a player cannot have a player as its top creature, so the scans\n'
    '-- below see the same players as the stock loops over every tile of the box, without the 0.6 s scan.\n'
    'local function chaosPlayerTiles(fromPos, toPos)\n'
    '\tlocal list, seen = {}, {}\n'
    '\tfor _, player in ipairs(Game.getPlayers()) do\n'
    '\t\tlocal p = player:getPosition()\n'
    '\t\tif p.z == fromPos.z and p.x >= fromPos.x and p.x <= toPos.x and p.y >= fromPos.y and p.y <= toPos.y then\n'
    '\t\t\tlocal key = p.x * 65536 + p.y\n'
    '\t\t\tif not seen[key] then\n'
    '\t\t\t\tseen[key] = true\n'
    '\t\t\t\tlist[#list + 1] = Position(p.x, p.y, p.z)\n'
    '\t\t\tend\n'
    '\t\tend\n'
    '\tend\n'
    '\ttable.sort(list, function(a, b)\n'
    '\t\tif a.x ~= b.x then\n'
    '\t\t\treturn a.x < b.x\n'
    '\t\tend\n'
    '\t\treturn a.y < b.y\n'
    '\tend)\n'
    '\treturn list\n'
    'end\n'
    '\n') % MARK

# ------------------------------------------------------------------------------------------------ 2. upgrade slots
UPGRADE_DEF_RE = re.compile(r'^slotAttribute\.autoDetection = function\(playerId\)[ \t]*\r?\n', re.M)
UPGRADE_CALL_RE = re.compile(r'^([ \t]*)local slots = slotAttribute\.getItemSlots\(item\)[ \t]*\r?\n'
                             r'(?=[ \t]*slotAttribute\.onSlotEquip\(player, slots, slot\))', re.M)
SLOTS_CACHE = (
    '-- %s: the slots parsed from an item description, kept per description text (the\n'
    '-- same text always gives the same slots). The check below runs often for every player; it now parses only a new\n'
    '-- or changed description. The cached tables are only read (onSlotEquip copies what it keeps).\n'
    'local chaosSlotsByDescription, chaosSlotsCached = {}, 0\n'
    'local function chaosItemSlots(item)\n'
    '\tlocal description = Item.getDescription(item)\n'
    '\tlocal slots = chaosSlotsByDescription[description]\n'
    '\tif not slots then\n'
    '\t\tslots = slotAttribute.getItemSlots(item)\n'
    '\t\tif chaosSlotsCached >= 5000 then\n'
    '\t\t\tchaosSlotsByDescription, chaosSlotsCached = {}, 0\n'
    '\t\tend\n'
    '\t\tchaosSlotsByDescription[description] = slots\n'
    '\t\tchaosSlotsCached = chaosSlotsCached + 1\n'
    '\tend\n'
    '\treturn slots\n'
    'end\n'
    '\n') % MARK


# ------------------------------------------------------------------------------------------------ 3. check interval
MARK_INTERVAL = 'Chaos (patch_base_stalls.py, check interval)'
UPGRADE_TIMER_RE = re.compile(r'^([ \t]*)addEvent\(slotAttribute\.autoDetection, \d+, playerId\)[ \t]*\r?\n', re.M)
UPGRADE_LOGIN_RE = re.compile(r'^local creatureEvent = CreatureEvent\(\)[ \t]*\r?\n'
                              r'(?=(?:[ \t]*\r?\n)*function creatureEvent\.onLogin\(player\)[ \t]*\r?\n'
                              r'[ \t]*slotAttribute\.autoDetection\(player\.uid\))', re.M)
UPGRADE_TIMER_NEW = ('{i}-- %s: no timer per player any more; chaosUpgradeGroup below checks\n'
                     '{i}-- every player once a second, onItemMoved at once\n') % MARK_INTERVAL
UPGRADE_GROUPS = (
    '-- %s: the check above ran every 100 ms for every player online (a timer per\n'
    '-- player), about 13%% of the game loop at 200 online. Now it runs at login (onLogin below, as before), at once when\n'
    '-- an item is put on or taken off (onItemMoved with an inventory slot on either side), and once a second for every\n'
    '-- player in 12 groups (player id modulo 12, one group every 83 ms) for the other ways a worn item changes (decay, a\n'
    '-- script, an upgrade or an orb used on a worn item). The check drops a player who left from the cache, as before.\n'
    'local chaosUpgradeGroups, chaosUpgradeInterval = 12, 1000\n'
    'ChaosUpgradeSlotsChain = (ChaosUpgradeSlotsChain or 0) + 1\n'
    'local chaosUpgradeChain, chaosUpgradeSeeded = ChaosUpgradeSlotsChain, false\n'
    'local function chaosUpgradeGroup(group)\n'
    '\tif ChaosUpgradeSlotsChain ~= chaosUpgradeChain then\n'
    '\t\treturn -- a reload of the scripts started a new chain\n'
    '\tend\n'
    '\tif not chaosUpgradeSeeded then\n'
    '\t\tchaosUpgradeSeeded = true -- after a reload: the players already online\n'
    '\t\tfor _, player in ipairs(Game.getPlayers()) do\n'
    '\t\t\tlocal playerId = player:getId()\n'
    '\t\t\tif not slotAttribute.cache[playerId] then\n'
    '\t\t\t\tslotAttribute.cache[playerId] = {}\n'
    '\t\t\tend\n'
    '\t\tend\n'
    '\tend\n'
    '\tfor playerId in pairs(slotAttribute.cache) do\n'
    '\t\tif playerId %% chaosUpgradeGroups == group then\n'
    '\t\t\tslotAttribute.autoDetection(playerId)\n'
    '\t\tend\n'
    '\tend\n'
    '\taddEvent(chaosUpgradeGroup, math.floor(chaosUpgradeInterval / chaosUpgradeGroups), (group + 1) %% chaosUpgradeGroups)\n'
    'end\n'
    'addEvent(chaosUpgradeGroup, math.floor(chaosUpgradeInterval / chaosUpgradeGroups), 0)\n'
    '\n'
    'local chaosUpgradeMoved = EventCallback\n'
    'chaosUpgradeMoved.onItemMoved = function(player, item, count, fromPosition, toPosition, fromCylinder, toCylinder)\n'
    '\tlocal inventory = CONTAINER_POSITION or 0xFFFF\n'
    '\tif (fromPosition.x == inventory and fromPosition.y < 64) or (toPosition.x == inventory and toPosition.y < 64) then\n'
    '\t\tslotAttribute.autoDetection(player:getId())\n'
    '\tend\n'
    'end\n'
    'chaosUpgradeMoved:register(13) -- after base_rarity.lua (10), item_mods.lua (11), archery.lua (12)\n'
    '\n') % MARK_INTERVAL


def crlf(text, new):
    return new.replace('\n', '\r\n') if '\r\n' in text else new


def patch_expedition(text):
    """(new text, status): 'already', 'patched (N loops)' or 'none'"""
    if MARK in text:
        return text, 'already'
    n = 0
    out, pos = [], 0
    for m in LOOP_RE.finditer(text):
        out.append(text[pos:m.start()])
        out.append(crlf(text, LOOP_NEW.format(i=m.group('i'), i2=m.group('i2'), i3=m.group('i3'), f=m.group('f'),
                                              t=m.group('t'))))
        pos = m.end()
        n += 1
    if n == 0:
        return text, 'none'
    out.append(text[pos:])
    body = ''.join(out)
    bom = '﻿' if body.startswith('﻿') else ''
    return bom + crlf(text, PLAYER_TILES) + body[len(bom):], 'patched (%d loop%s)' % (n, '' if n == 1 else 's')


def patch_upgrade_cache(text):
    """(new text, status): 'already', 'patched' or 'none'"""
    if MARK in text:
        return text, 'already'
    d = UPGRADE_DEF_RE.search(text)
    if not d:
        return text, 'none'
    c = UPGRADE_CALL_RE.search(text, d.end())
    if not c:
        return text, 'none'
    new = (text[:d.start()] + crlf(text, SLOTS_CACHE) + text[d.start():c.start()]
           + crlf(text, '%slocal slots = chaosItemSlots(item)\n' % c.group(1)) + text[c.end():])
    return new, 'patched'


def patch_upgrade_interval(text):
    """(new text, status): 'already', 'patched' or 'none'"""
    if MARK_INTERVAL in text:
        return text, 'already'
    d = UPGRADE_DEF_RE.search(text)
    if not d:
        return text, 'none'
    tm = UPGRADE_TIMER_RE.search(text, d.end())
    if not tm:
        return text, 'none'
    lg = UPGRADE_LOGIN_RE.search(text, tm.end())
    if not lg:
        return text, 'none'
    new = (text[:tm.start()] + crlf(text, UPGRADE_TIMER_NEW.format(i=tm.group(1))) + text[tm.end():lg.start()]
           + crlf(text, UPGRADE_GROUPS) + text[lg.start():])
    return new, 'patched'


def patch_upgrade(text):
    """(new text, status) for 2 and 3: 'already', 'patched (...)' or 'none'"""
    text, cache = patch_upgrade_cache(text)
    text, interval = patch_upgrade_interval(text)
    if cache == 'none' and interval == 'none':
        return text, 'none'
    done = [what for what, st in (('slot cache', cache), ('check every 1 s and on equip', interval)) if st == 'patched']
    if not done:
        return text, 'already'
    rest = [what + ' ' + st for what, st in (('slot cache', cache), ('check interval', interval))
            if st != 'patched']
    rest = [r.replace(' none', ': stock code not found') for r in rest]
    return text, 'patched (%s%s)' % (', '.join(done), '; ' + ', '.join(rest) if rest else '')


def files(data):
    root = os.path.join(data, *EXPEDITIONS)
    if os.path.isdir(root):
        for dirpath, dirnames, filenames in os.walk(root):
            dirnames.sort()
            for name in sorted(filenames):
                if name.endswith('.lua'):
                    yield os.path.join(dirpath, name), patch_expedition
    path = os.path.join(data, *UPGRADE)
    if os.path.isfile(path):
        yield path, patch_upgrade


def main(argv):
    args = [a for a in argv if not a.startswith('--')]
    dry = '--dry-run' in argv
    if len(args) != 1 or not os.path.isdir(args[0]):
        print(__doc__.strip().splitlines()[2])
        return 2
    data = args[0]
    found = 0
    for path, fn in files(data):
        rel = os.path.relpath(path, data).replace(os.sep, '/')
        with open(path, encoding='utf-8', errors='surrogateescape', newline='') as f:
            text = f.read()
        new, st = fn(text)
        if st == 'none':
            continue
        found += 1
        if st.startswith('patched') and not dry:
            with open(path, 'w', encoding='utf-8', errors='surrogateescape', newline='') as f:
                f.write(new)
        print('data/%s: %s%s' % (rel, st, ' (dry run, not written)' if dry and st.startswith('patched') else ''))
    if not found:
        print('no expedition scan loop and no upgrade slot check found (nothing to do)')
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
