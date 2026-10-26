#!/usr/bin/env python3
"""The base server's waystone device works in the owner's hideout, not only in a house (idempotent).

usage: python3 -I patch_waystone_hideout.py DATA_DIR [--dry-run]

The base waystone system (data/scripts/customs/waystone_system/tier_maps.lua) is made for houses: the device (item
29624 / 29626, action id 42707) refuses unless its tile is a house tile ("You may only use Waystone Portal inside a
House."), and the portal pads that open next to it are made only on tiles of a house the player owns ("There is no
space in your house to spawn portals."). The Chaos hideout (server/README.md "Hideouts") is a runtime room with no
engine house, so the device would never work there. Patched in tier_maps.lua:
  * a helper chaosWaystonePlace(player, pos, ownerOnly) after the PAD_AID line: true on a house tile (an owned one when
    ownerOnly), or on a tile of the player's own hideout (ChaosHideout.isOwnRoomTile(player, pos), data/scripts/chaos/
    hideout.lua; read when used, so the load order does not matter);
  * the use check and the pad tile check call the helper (a house keeps working exactly as before);
  * the "wrap" answer refuses the device that is a fixture of a hideout (ChaosHideout.isFixture);
  * the texts: "You may only use the Waystone Portal in your hideout or inside a house." and "There is no space in your
    hideout or house to spawn portals."
Part 2 (player report 2026-10-22: "the device's Use does nothing, clicking a waystone does nothing"; its own marker,
so a server patched by part 1 only gets it on the next run):
  * the "show" message to the client window (client module game_waystone, opcode 202) carries the tiers the player
    holds ({clientId, tier, count}, counted by the server in every backpack) and the tier to pick first;
  * "teleport" refuses a tier the player does not hold before any pad is made (the base made the pads first and
    took the waystone after, so a pick without one still opened the pads);
  * a Waystone Tier item gets its own action (the base had none, so using one did nothing): used on the device, or
    used anywhere in the player's own hideout (ChaosHideout.waystoneDevice), it opens the device's window with that
    tier picked; elsewhere it says where to use it.
Part 3 (owner 2026-10-23: 15 tiers from level 1100 to 2500, 2-3 scenarios for the low, middle and high levels; its own
marker): the device reads data/scripts/chaos/waystone_tiers.lua (ChaosWaystoneTiers; each call guarded, so without it the
base behaviour stays):
  * the tier items VII-XV (tools/install_waystone_items.py) join clientToServer (WT.tablets, keyed by their server id),
    so the window lists them and "teleport" takes them; their action is the tier items' action;
  * a tier opens one of the maps of its band (WT.optionsFor: the base mapping's entries of the band's base tiers);
  * the window rows carry the tier's monster level (WT.tierLevel);
  * when the pads open, WT.startRun(finalArea, serverTypeId) sets the map to the run's tier.
Part 4 (owner 2026-10-23: waystones with modifiers, the maps of an ARPG; its own marker): the device takes the
waystone that was used on it (data/scripts/chaos/waystone_mods.lua ChaosWaystoneMods.choose / take; else the one of that
tier with the fewest modifiers) instead of any one of the id, and passes its modifiers to WT.startRun.
And in data/items/items.xml the descriptions of the six Waystone Tier items ("... on waystone device at house ...")
say "... on the waystone device in your hideout or house ...". The portal kit (29628) stays "in your house": building a
device from a kit needs a house, the hideout has its own device built in. Every change is made once (a second run changes
nothing). Refuses (exit 1), changing nothing, when tier_maps.lua or items.xml is missing or is not the text this patch
knows (a line to change not there). Line endings (LF or CRLF) are kept.
"""
import os
import re
import sys

MARK = '-- Chaos: waystone device in the hideout (patch_waystone_hideout.py)'
USE_OLD = re.compile(r'if not fromPosition:getTile\(\):getHouse\(\) then(\r?\n)(\s*)player:sendTextMessage\(MESSAGE_INFO_DESCR, '
                     r'"You may only use Waystone Portal inside a House\."\)')
USE_NEW = ('if not chaosWaystonePlace(player, fromPosition, false) then', 'You may only use the Waystone Portal in your hideout or inside a house.')
PAD_OLD = re.compile(r'local tileHouse = tile:getHouse\(\)(\r?\n)(\s*)if tileHouse and tileHouse:getOwnerGuid\(\) == player:getGuid\(\) '
                     r'and tile:isWalkable\(\) then')
PAD_NEW = 'if chaosWaystonePlace(player, spawnPos, true) and tile:isWalkable() then'
MSG_OLD = '"There is no space in your house to spawn portals."'
MSG_NEW = '"There is no space in your hideout or house to spawn portals."'
PAD_ANCHOR = re.compile(r'^local PAD_AID = \d+[ \t]*\r?$', re.M)
WRAP_ANCHOR = re.compile(r'^([ \t]*)waystoneDevice:transform\(29628\)[ \t]*\r?$', re.M)

HELPER = [
    MARK,
    '-- true on a house tile (one the player owns when ownerOnly), or on a tile of the player\'s own hideout',
    'local function chaosWaystonePlace(player, pos, ownerOnly)',
    '  local tile = Tile(pos)',
    '  local house = tile and tile:getHouse()',
    '  if house and (not ownerOnly or house:getOwnerGuid() == player:getGuid()) then',
    '    return true',
    '  end',
    '  return ChaosHideout ~= nil and ChaosHideout.isOwnRoomTile ~= nil and ChaosHideout.isOwnRoomTile(player, pos) == true',
    'end',
]

MARK2 = '-- Chaos: waystone window data and the tier items (patch_waystone_hideout.py part 2)'
SHOW_OLD = 'player:sendExtendedOpcode(OPCODE, json.encode{ action = "show" })'
SHOW_NEW = ('player:sendExtendedOpcode(OPCODE, json.encode{ action = "show", tiers = chaosWaystoneTiers(player), '
            'pick = chaosWaystonePick(player) })')
SHOW_ANCHOR = re.compile(r'^local showTabletUI = Action\(\)[ \t]*\r?$', re.M)
REGISTER_ANCHOR = re.compile(r'^showTabletUI:register\(\)[ \t]*\r?$', re.M)
CENTER_ANCHOR = re.compile(r'^([ \t]*)local center = pendingCenter\[guid\][ \t]*\r?$', re.M)
TIER_IDS = (29845, 29846, 29847, 29848, 29849, 29850)
# the tier items VII-XV (install_waystone_items.py NEW_IDS; waystone_tiers_config.lua tiers)
NEW_TIER_IDS = tuple(range(41951, 41960))

MARK3 = '-- Chaos: waystone tiers VII-XV and the level bands (patch_waystone_hideout.py part 3)'
HELPER3 = [
    MARK3,
    'local chaosMerged = false',
    'local function chaosWaystoneMerge()',
    '  if chaosMerged or not (ChaosWaystoneTiers and ChaosWaystoneTiers.tablets) then return end',
    '  local ok, list = pcall(ChaosWaystoneTiers.tablets)',
    '  if not ok or type(list) ~= "table" then return end',
    '  chaosMerged = true',
    '  for key, serverId in pairs(list) do',
    '    clientToServer[key] = serverId',
    '  end',
    'end',
    'local function chaosWaystoneLevel(tier)',
    '  if ChaosWaystoneTiers and ChaosWaystoneTiers.tierLevel then',
    '    local ok, lv = pcall(ChaosWaystoneTiers.tierLevel, tier)',
    '    if ok then return lv end',
    '  end',
    '  return nil',
    'end',
    'local function chaosWaystoneOptions(serverId)',
    '  if ChaosWaystoneTiers and ChaosWaystoneTiers.optionsFor then',
    '    local ok, list = pcall(ChaosWaystoneTiers.optionsFor, serverId, teleportMapping)',
    '    if ok and type(list) == "table" and #list > 0 then return list end',
    '  end',
    '  return teleportMapping[serverId]',
    'end',
]
P3_PICK = 'local chaosPickFor = {}'
P3_LIST_OLD = '  local out = {}%s  for clientId, serverId in pairs(clientToServer) do%s    local itemType'
P3_TIER_OLD = '    t.tier, t.serverId = i, nil'
P3_TIER_NEW = '    t.tier, t.serverId, t.level = i, nil, chaosWaystoneLevel(i)'
P3_SERVER_OLD = 'local serverTypeId = clientToServer[data.clientId]'
P3_OPTIONS_OLD = 'local options = teleportMapping[serverTypeId]'
P3_OPTIONS_NEW = 'local options = chaosWaystoneOptions(serverTypeId)'
P3_DONE = 'player:sendExtendedOpcode(OPCODE, json.encode{ action = "teleport_done" })'
P3_USE_OLD = 'function chaosTierUse.onUse(player, item, fromPosition, target, toPosition, isHotkey)'
P3_IDS_OLD = 'chaosTierUse:id(%s)' % ', '.join(str(i) for i in TIER_IDS)
P3_IDS_NEW = 'chaosTierUse:id(%s)' % ', '.join(str(i) for i in TIER_IDS + NEW_TIER_IDS)

MARK4 = '-- Chaos: waystone modifiers, the used waystone is the one taken (patch_waystone_hideout.py part 4)'
HELPER4 = [
    MARK4,
    'local function chaosWaystoneTake(player, serverId)',
    '  if ChaosWaystoneMods and ChaosWaystoneMods.take then',
    '    local ok, taken, mods = pcall(ChaosWaystoneMods.take, player, serverId)',
    '    if ok then return taken, mods end',
    '  end',
    '  return player:removeItem(serverId, 1), {}',
    'end',
]
P4_TIERUSE = 'local chaosTierUse = Action()'
P4_REMOVE = re.compile(r'^([ \t]*)if not player:removeItem\(serverTypeId, 1\) then', re.M)
P4_START_OLD = 'pcall(ChaosWaystoneTiers.startRun, finalArea, serverTypeId)'
P4_START_NEW = 'pcall(ChaosWaystoneTiers.startRun, finalArea, serverTypeId, chaosMods)'
P4_POS = re.compile(r'^([ \t]*)local pos = device:getPosition\(\)', re.M)
P4_CHOOSE = 'if ChaosWaystoneMods and ChaosWaystoneMods.choose then pcall(ChaosWaystoneMods.choose, player, item) end'

HELPER2 = [
    MARK2,
    '-- the tiers the player holds, for the window: {clientId, look, tier, count} by tier (look: the item\'s client id',
    '-- in this server\'s items.otb, for the icon); and the tier to pick first',
    'local chaosPickFor = {}',
    'local function chaosWaystoneTiers(player)',
    '  local out = {}',
    '  for clientId, serverId in pairs(clientToServer) do',
    '    local itemType = ItemType and ItemType(serverId)',
    '    local look = itemType and itemType:getClientId() or clientId',
    '    out[#out + 1] = { clientId = clientId, look = look, serverId = serverId, count = player:getItemCount(serverId) }',
    '  end',
    '  table.sort(out, function(a, b) return a.serverId < b.serverId end)',
    '  for i, t in ipairs(out) do',
    '    t.tier, t.serverId = i, nil',
    '  end',
    '  return out',
    'end',
    'local function chaosWaystonePick(player)',
    '  local pick = chaosPickFor[player:getGuid()]',
    '  chaosPickFor[player:getGuid()] = nil',
    '  return pick',
    'end',
]

TIER_USE = [
    '-- Chaos (part 2): a Waystone Tier used on the device, or anywhere in the own hideout, opens the device\'s window',
    'local chaosTierUse = Action()',
    'function chaosTierUse.onUse(player, item, fromPosition, target, toPosition, isHotkey)',
    '  local device = nil',
    '  if target and type(target) == "userdata" and target.isItem and target:isItem() and target:getActionId() == 42707 then',
    '    device = target',
    '  elseif ChaosHideout and ChaosHideout.waystoneDevice then',
    '    device = ChaosHideout.waystoneDevice(player)',
    '  end',
    '  if not device then',
    '    player:sendTextMessage(MESSAGE_INFO_DESCR, "Use this waystone on the waystone device in your hideout or house.")',
    '    return true',
    '  end',
    '  for clientId, serverId in pairs(clientToServer) do',
    '    if serverId == item:getId() then',
    '      chaosPickFor[player:getGuid()] = clientId',
    '    end',
    '  end',
    '  local pos = device:getPosition()',
    '  showTabletUI.onUse(player, device, pos, nil, pos, isHotkey)',
    '  chaosPickFor[player:getGuid()] = nil',
    '  return true',
    'end',
    'chaosTierUse:id(%s)' % ', '.join(str(i) for i in TIER_IDS),
    'chaosTierUse:register()',
]

DESC_OLD = re.compile(r'Use This waystone on waystone device at house to teleport to a random tier (\d+) map\.')
DESC_NEW = 'Use this waystone on the waystone device in your hideout or house to teleport to a random tier %s map.'
DESC_DONE = re.compile(r'Use this waystone on the waystone device in your hideout or house to teleport to a random tier (\d+) map\.')


def nl_of(text):
    return '\r\n' if '\r\n' in text else '\n'


def patch_lua(text):
    """-> (new text, changes, error): part 1, then part 2, then part 3"""
    new, changes, err = patch_lua_part1(text)
    if err:
        return text, [], err
    new, changes2, err = patch_lua_part2(new)
    if err:
        return text, [], err
    new, changes3, err = patch_lua_part3(new)
    if err:
        return text, [], err
    new, changes4, err = patch_lua_part4(new)
    if err:
        return text, [], err
    return new, changes + changes2 + changes3 + changes4, None


def patch_lua_part4(text):
    """-> (new text, changes, error): the waystone used is the one taken, its modifiers go to the run"""
    done = ('chaosWaystoneTake(player, serverTypeId)', P4_START_NEW, P4_CHOOSE)
    if MARK4 in text:
        for need in done:
            if need not in text:
                return text, [], 'part 4 marker present but "%s" is missing' % need
        return text, [], None
    nl = nl_of(text)
    if text.count(P4_TIERUSE) != 1 or len(P4_REMOVE.findall(text)) != 1 or text.count(P4_START_OLD) != 1 \
            or len(P4_POS.findall(text)) != 1:
        return text, [], 'the take, the run start or the tier items\' action not as expected (part 3 first)'
    new = text.replace(P4_TIERUSE, nl.join(HELPER4) + nl + P4_TIERUSE, 1)
    new = P4_REMOVE.sub(lambda m: '%slocal chaosTaken, chaosMods = chaosWaystoneTake(player, serverTypeId)%s%sif not chaosTaken then'
                        % (m.group(1), nl, m.group(1)), new, count=1)
    new = new.replace(P4_START_OLD, P4_START_NEW, 1)
    new = P4_POS.sub(lambda m: '%s%s%s%s' % (m.group(1), P4_CHOOSE, nl, m.group(0)), new, count=1)
    return new, ['the used waystone is taken', 'its modifiers go to the run'], None


def patch_lua_part3(text):
    """-> (new text, changes, error): the tier items VII-XV, the band's maps, the level in the window, the run's tier"""
    done = ('chaosWaystoneMerge()', P3_TIER_NEW, P3_OPTIONS_NEW, 'ChaosWaystoneTiers.startRun', P3_IDS_NEW)
    if MARK3 in text:
        for need in done:
            if need not in text:
                return text, [], 'part 3 marker present but "%s" is missing' % need
        return text, [], None
    nl = nl_of(text)
    list_old = P3_LIST_OLD % (nl, nl)
    for old, what in ((P3_PICK, 'the part 2 helpers'), (list_old, 'the window list (chaosWaystoneTiers)'),
                      (P3_TIER_OLD, 'the window rows\' tier'), (P3_SERVER_OLD, 'the teleport\'s item lookup'),
                      (P3_OPTIONS_OLD, 'the teleport\'s maps'), (P3_DONE, 'the teleport answer'),
                      (P3_USE_OLD, 'the tier items\' action'), (P3_IDS_OLD, 'the tier items\' ids')):
        if text.count(old) != 1:
            return text, [], '%s not as expected (part 2 first)' % what
    if text.index('local teleportMapping') > text.index(P3_PICK):
        return text, [], 'teleportMapping is not before the part 2 helpers'
    pick_line = re.search(r'^' + re.escape(P3_PICK) + r'[ \t]*\r?$', text, re.M)
    if not pick_line:
        return text, [], 'the part 2 helpers not as expected'
    cr = '\r' if pick_line.group(0).endswith('\r') else ''
    new = text[:pick_line.end()] + nl + nl.join(HELPER3) + cr + text[pick_line.end():]
    new = new.replace(list_old, '  local out = {}%s  chaosWaystoneMerge()%s  for clientId, serverId in pairs(clientToServer) do%s    local itemType' % (nl, nl, nl), 1)
    new = new.replace(P3_TIER_OLD, P3_TIER_NEW, 1)
    new = re.sub(r'^([ \t]*)' + re.escape(P3_SERVER_OLD), lambda m: '%schaosWaystoneMerge()%s%s%s' % (
        m.group(1), nl, m.group(1), P3_SERVER_OLD), new, count=1, flags=re.M)
    new = new.replace(P3_OPTIONS_OLD, P3_OPTIONS_NEW, 1)
    new = re.sub(r'^([ \t]*)' + re.escape(P3_DONE), lambda m: '%s%s%s%sif ChaosWaystoneTiers and ChaosWaystoneTiers.startRun then%s%s  pcall(ChaosWaystoneTiers.startRun, finalArea, serverTypeId)%s%send' % (
        m.group(1), P3_DONE, nl, m.group(1), nl, m.group(1), nl, m.group(1)), new, count=1, flags=re.M)
    new = new.replace(P3_USE_OLD, P3_USE_OLD + nl + '  chaosWaystoneMerge()', 1)
    new = new.replace(P3_IDS_OLD, P3_IDS_NEW, 1)
    return new, ['tier items VII-XV', 'maps of the band', 'level in the window', 'run tier at the pads'], None


def patch_lua_part2(text):
    """-> (new text, changes, error): the window data, the item check before the pads, the tier items' action"""
    if MARK2 in text:
        for need in (SHOW_NEW, 'chaosTierUse:register()', 'You have no waystone of that tier.'):
            if need not in text:
                return text, [], 'part 2 marker present but "%s" is missing' % need
        return text, [], None
    nl = nl_of(text)
    if text.count(SHOW_OLD) != 1:
        return text, [], 'the "show" message of the device is not as expected'
    if 'local clientToServer = {' not in text or text.index('local clientToServer = {') > text.find('local showTabletUI'):
        return text, [], 'the clientToServer table is not before the device action'
    if len(SHOW_ANCHOR.findall(text)) != 1 or len(REGISTER_ANCHOR.findall(text)) != 1:
        return text, [], 'the device action (showTabletUI) is not as expected'
    if len(CENTER_ANCHOR.findall(text)) != 1:
        return text, [], 'the teleport answer (local center = pendingCenter[guid]) is not as expected'

    def cr(m):
        return '\r' if m.group(0).endswith('\r') else ''
    new = text.replace(SHOW_OLD, SHOW_NEW, 1)
    new = SHOW_ANCHOR.sub(lambda m: nl.join(HELPER2) + nl + nl + m.group(0), new, count=1)
    new = REGISTER_ANCHOR.sub(lambda m: m.group(0).rstrip('\r') + nl + nl + nl.join(TIER_USE) + cr(m), new, count=1)
    new = CENTER_ANCHOR.sub(lambda m: nl.join([
        '%sif player:getItemCount(serverTypeId) < 1 then' % m.group(1),
        '%s  player:sendExtendedOpcode(OPCODE, json.encode{' % m.group(1),
        '%s    action = "teleport_error",' % m.group(1),
        '%s    text   = "You have no waystone of that tier."' % m.group(1),
        '%s  })' % m.group(1),
        '%s  return true' % m.group(1),
        '%send' % m.group(1),
        m.group(0).rstrip('\r')]) + cr(m), new, count=1)
    return new, ['window data (tiers held, tier to pick)', 'item check before the pads', 'tier items\' action'], None


def patch_lua_part1(text):
    """-> (new text, changes, error)"""
    if MARK in text:
        # patched before: all the pieces must be there
        for need in ('chaosWaystonePlace(player, fromPosition, false)', 'chaosWaystonePlace(player, spawnPos, true)',
                     'ChaosHideout.isFixture(waystoneDevice)', MSG_NEW):
            if need not in text:
                return text, [], 'marker present but "%s" is missing' % need
        return text, [], None
    nl = nl_of(text)
    if not USE_OLD.search(text):
        return text, [], 'the use check (fromPosition:getTile():getHouse() with its message) is not as expected'
    if not PAD_OLD.search(text):
        return text, [], 'the pad tile check (tile:getHouse() owned by the player) is not as expected'
    if text.count(MSG_OLD) != 1:
        return text, [], 'the "no space in your house" message is not as expected'
    if len(PAD_ANCHOR.findall(text)) != 1 or len(WRAP_ANCHOR.findall(text)) != 1:
        return text, [], 'the PAD_AID line or the wrap answer is not as expected'
    new = USE_OLD.sub(lambda m: '%s%s%s%splayer:sendTextMessage(MESSAGE_INFO_DESCR, "%s")' % (
        USE_NEW[0], m.group(1), m.group(2), '', USE_NEW[1]), text, count=1)
    new = PAD_OLD.sub(lambda m: PAD_NEW, new, count=1)
    new = new.replace(MSG_OLD, MSG_NEW, 1)
    new = WRAP_ANCHOR.sub(lambda m: nl.join([
        '%sif ChaosHideout and ChaosHideout.isFixture and ChaosHideout.isFixture(waystoneDevice) then' % m.group(1),
        '%s  player:sendExtendedOpcode(OPCODE, json.encode{' % m.group(1),
        '%s    action = "wrap_error",' % m.group(1),
        '%s    text   = "The waystone portal of your hideout cannot be wrapped."' % m.group(1),
        '%s  })' % m.group(1),
        '%s  return true' % m.group(1),
        '%send' % m.group(1),
        m.group(0).rstrip('\r')]) + ('\r' if m.group(0).endswith('\r') else ''), new, count=1)
    new = PAD_ANCHOR.sub(lambda m: m.group(0).rstrip('\r') + nl + nl.join(HELPER) + ('\r' if m.group(0).endswith('\r') else ''),
                         new, count=1)
    return new, ['helper chaosWaystonePlace', 'use check', 'pad tile check', 'wrap refusal', 'two messages'], None


def patch_items(text):
    """-> (new text, changes, error): the six Waystone Tier descriptions"""
    old = DESC_OLD.findall(text)
    done = DESC_DONE.findall(text)
    if len(old) + len(done) != 6:
        return text, [], 'expected 6 Waystone Tier descriptions, found %d' % (len(old) + len(done))
    if not old:
        return text, [], None
    new = DESC_OLD.sub(lambda m: DESC_NEW % m.group(1), text)
    return new, ['%d Waystone Tier description(s)' % len(old)], None


def main(argv):
    args = [a for a in argv if not a.startswith('--')]
    if not args:
        print(__doc__)
        return 2
    dry = '--dry-run' in argv
    jobs = [('scripts/customs/waystone_system/tier_maps.lua', patch_lua), ('items/items.xml', patch_items)]
    out, total = [], 0
    for rel, fn in jobs:
        path = os.path.join(args[0], *rel.split('/'))
        if not os.path.isfile(path):
            print('patch_waystone_hideout: %s is missing' % path)
            return 1
        with open(path, encoding='utf-8', errors='surrogateescape', newline='') as f:
            text = f.read()
        new, changes, err = fn(text)
        if err:
            print('patch_waystone_hideout: %s: %s' % (rel, err))
            return 1
        for c in changes:
            print('  %s: %s' % (rel, c))
        total += len(changes)
        out.append((path, text, new))
    if not dry:
        for path, text, new in out:
            if new != text:
                with open(path, 'w', encoding='utf-8', errors='surrogateescape', newline='') as f:
                    f.write(new)
    print('patch_waystone_hideout: %d change(s)%s' % (total, ' (dry run)' if dry else ''))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
