#!/usr/bin/env python3
"""python3 -I server/tools/patch_waystone_hideout_test.py: patch_waystone_hideout.py on a synthetic tier_maps.lua and
items.xml (the lines it changes are as in the base server; a copy of the real files is also checked when the
WAYSTONE_BASE_DATA environment variable names a base data folder): the helper and the changes are made once, a second
run changes nothing, a dry run writes nothing, CRLF text is kept, a text that is not the known one is refused without
writing anything, and the patched script still parses in Lua and runs its helper against a mocked engine."""
import os
import shutil
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import patch_waystone_hideout as P

LUA = '''local OPCODE      = 202
local PAD_AID = 46201

print(">> Waystone System Loaded")

local clientToServer = { --- Client ID -> Item ID ( Tier Tablets )
  [27189] = 29845, -- Tier I
  [27190] = 29846,
  [27191] = 29847,
  [27192] = 29848,
  [27193] = 29849,
  [27194] = 29850, -- Tier VI
}

local teleportMapping = {
  [29845] = { { area = { fromPos = Position(33314, 33066, 8) }, destination = Position(33597, 33141, 8) } },
}

local pendingTablet = {}
local pendingCenter = {}
local pendingPortals = {}

local showTabletUI = Action()
function showTabletUI.onUse(player, runeItem, fromPosition, target, toPosition, isHotkey)
  if not fromPosition:getTile():getHouse() then
    player:sendTextMessage(MESSAGE_INFO_DESCR, "You may only use Waystone Portal inside a House.")
    return true
  end
  local guid = player:getGuid()
  pendingCenter[player:getGuid()] = toPosition
  pendingTablet[guid] = runeItem
  player:sendExtendedOpcode(OPCODE, json.encode{ action = "show" })
  return true
end
showTabletUI:aid(42707)
showTabletUI:register()

local function handle(player, data)
  local guid = player:getGuid()
  if data.action == "wrap" then
    local waystoneDevice = pendingTablet[1]
    waystoneDevice:transform(29628)
    waystoneDevice:setActionId(0)
    return true
  end
  if data.action == "teleport" then
    local serverTypeId = clientToServer[data.clientId]
    local options = teleportMapping[serverTypeId]
    local finalArea = options and options[1].area
    local center = pendingCenter[guid]
    pendingCenter[guid] = nil
    for _, d in ipairs({}) do
      local spawnPos = d
        local tile = Tile(spawnPos)
        if tile then
          local tileHouse = tile:getHouse()
          if tileHouse and tileHouse:getOwnerGuid() == player:getGuid() and tile:isWalkable() then
            Game.createItem(1, 1, spawnPos)
          end
        end
    end
    if #pendingPortals == 0 then
      player:sendTextMessage(MESSAGE_INFO_DESCR,
        "There is no space in your house to spawn portals.")
      return true
    end
    player:sendExtendedOpcode(OPCODE, json.encode{ action = "teleport_done" })
  end
end
'''
XML = '<items>\n' + ''.join(
    '\t<item id="%d" name="Waystone Tier %s">\n\t\t<attribute key="description" value="Use This waystone on waystone device '
    'at house to teleport to a random tier %d map." />\n\t</item>\n' % (29845 + i, r, i + 1)
    for i, r in enumerate(['I', 'II', 'III', 'IV', 'V', 'VI'])) + \
    '\t<item id="29628" name="waystone portal kit">\n\t\t<attribute key="description" value="Use it in your house to construct a waystone portal." />\n\t</item>\n</items>\n'
fails = 0


def ok(cond, what):
    global fails
    if not cond:
        fails += 1
        print('FAIL', what)


def tree(lua=LUA, xml=XML):
    d = tempfile.mkdtemp()
    os.makedirs(os.path.join(d, 'scripts', 'customs', 'waystone_system'))
    os.makedirs(os.path.join(d, 'items'))
    if lua is not None:
        with open(os.path.join(d, 'scripts', 'customs', 'waystone_system', 'tier_maps.lua'), 'w', newline='') as f:
            f.write(lua)
    if xml is not None:
        with open(os.path.join(d, 'items', 'items.xml'), 'w', newline='') as f:
            f.write(xml)
    return d


def lua_path(d):
    return os.path.join(d, 'scripts', 'customs', 'waystone_system', 'tier_maps.lua')


def xml_path(d):
    return os.path.join(d, 'items', 'items.xml')


def rd(path):
    with open(path, newline='') as f:
        return f.read()


def check_tree(d, label, lua, xml):
    ok(P.main([d, '--dry-run']) == 0, label + ': dry run')
    ok(rd(lua_path(d)) == lua and rd(xml_path(d)) == xml, label + ': dry run writes nothing')
    ok(P.main([d]) == 0, label + ': first run')
    t = rd(lua_path(d))
    x = rd(xml_path(d))
    ok(t != lua and P.MARK in t, label + ': marker')
    ok('chaosWaystonePlace(player, fromPosition, false)' in t and 'getTile():getHouse()' not in t, label + ': use check')
    ok('chaosWaystonePlace(player, spawnPos, true) and tile:isWalkable()' in t and 'tileHouse' not in t, label + ': pad check')
    ok('in your hideout or inside a house.' in t and 'inside a House.' not in t, label + ': refusal text')
    ok('There is no space in your hideout or house to spawn portals.' in t, label + ': no space text')
    ok('ChaosHideout.isFixture(waystoneDevice)' in t, label + ': wrap refusal')
    ok(t.index('local function chaosWaystonePlace') < t.index('showTabletUI = Action()'), label + ': helper before use')
    ok(x.count('in your hideout or house to teleport to a random tier') == 6 and 'waystone device at house' not in x, label + ': descriptions')
    ok('Use it in your house to construct' in x, label + ': the kit text stays')
    ok(P.main([d]) == 0, label + ': second run')
    ok(rd(lua_path(d)) == t and rd(xml_path(d)) == x, label + ': second run changes nothing')
    ok(t.count(P.MARK) == 1, label + ': block once')
    # part 2: the window data, the item check before the pads, the tier items' action
    ok(t.count(P.MARK2) == 1, label + ': part 2 once')
    ok(P.SHOW_NEW in t and P.SHOW_OLD not in t, label + ': show carries the tiers')
    ok(t.index('local function chaosWaystoneTiers') < t.index('showTabletUI = Action()'), label + ': tiers helper before use')
    ok(t.index('local clientToServer') < t.index('local function chaosWaystoneTiers'), label + ': tiers helper after the table')
    ok(t.index('You have no waystone of that tier.') < t.index('local center = pendingCenter[guid]'), label + ': item check first')
    ok(t.index('chaosTierUse:register()') > t.index('showTabletUI:register()'), label + ': tier action after the device')
    ok('chaosTierUse:id(29845, 29846, 29847, 29848, 29849, 29850, 41951, ' in t and ', 41959)' in t, label + ': the fifteen tiers')
    ok(t.count(P.MARK3) == 1, label + ': part 3 once')
    ok(t.index('local function chaosWaystoneOptions') > t.index('local teleportMapping'), label + ': part 3 helpers after the mapping')
    ok(t.index('chaosWaystoneMerge()') < t.index('local serverTypeId = clientToServer[data.clientId]'), label + ': merged before the lookup')
    ok('local options = chaosWaystoneOptions(serverTypeId)' in t, label + ': the band\'s maps')
    ok(t.index('ChaosWaystoneTiers.startRun') > t.index('action = "teleport_done"'), label + ': the run\'s tier after the pads')
    return t


# synthetic, LF
d = tree()
try:
    t = check_tree(d, 'lf', LUA, XML)
    for lua in ('luajit', 'lua5.3'):
        if shutil.which(lua):
            r = subprocess.run([lua, '-e', 'assert(loadfile("%s"))' % lua_path(d)], stdin=subprocess.DEVNULL,
                               capture_output=True, timeout=30)
            ok(r.returncode == 0, '%s parses the patched script: %s' % (lua, r.stderr[:200]))
            # the helper on a mocked engine: house, own house, own hideout, nothing
            start = t.index(P.MARK)
            end = t.index('\nend\n', start) + 5
            probe = (
                'local me = {getGuid = function() return 7 end}\n'
                'local house = {owner = 7}\n'
                'function house:getOwnerGuid() return self.owner end\n'
                'local tiles = {}\n'
                'function Tile(pos) return tiles[pos] end\n'
                + t[start:end] +
                'local function tile(h) return {getHouse = function() return h end} end\n'
                'tiles.plain = tile(nil)\n'
                'tiles.own = tile(house)\n'
                'tiles.other = tile({getOwnerGuid = function() return 9 end})\n'
                'local function eq(a, b, m) if a ~= b then error(m .. ": " .. tostring(a), 2) end end\n'
                'eq(chaosWaystonePlace(me, "plain", false), false, "no house, no hideout")\n'
                'eq(chaosWaystonePlace(me, "own", false), true, "own house")\n'
                'eq(chaosWaystonePlace(me, "other", false), true, "any house for the device")\n'
                'eq(chaosWaystonePlace(me, "other", true), false, "pads only on an own house")\n'
                'eq(chaosWaystonePlace(me, "own", true), true, "pads on an own house")\n'
                'eq(chaosWaystonePlace(me, "nowhere", false), false, "no tile")\n'
                'ChaosHideout = {isOwnRoomTile = function(p, pos) return pos == "plain" or pos == "nowhere" end}\n'
                'eq(chaosWaystonePlace(me, "plain", false), true, "own hideout (device)")\n'
                'eq(chaosWaystonePlace(me, "plain", true), true, "own hideout (pads)")\n'
                'eq(chaosWaystonePlace(me, "nowhere", true), true, "a hideout tile the map has no house on")\n'
                'ChaosHideout = {isOwnRoomTile = function() return false end}\n'
                'eq(chaosWaystonePlace(me, "plain", false), false, "someone else\'s hideout")\n'
                'print("helper ok")\n')
            r = subprocess.run([lua, '-e', probe], stdin=subprocess.DEVNULL, capture_output=True, timeout=30)
            ok(r.returncode == 0 and b'helper ok' in r.stdout, '%s runs the helper: %s' % (lua, r.stderr[:300]))
            # part 2 on a mocked engine: the tiers and the pick in "show", a tier used on the device / in the
            # hideout / elsewhere
            probe2 = (
                'local actions, sent, texts = {}, {}, {}\n'
                'function Action() local a = {ids = {}} function a:aid(x) self.aidv = x end '
                'function a:id(...) for _, v in ipairs({...}) do self.ids[#self.ids + 1] = v end end '
                'function a:register() actions[#actions + 1] = self end return a end\n'
                'json = {encode = function(t) return t end}\n'
                'MESSAGE_INFO_DESCR = 1\n'
                'function Position(x, y, z) return {x = x, y = y, z = z} end\n'
                'function Tile(pos) return {getHouse = function() return pos.house end} end\n'
                'local held = {[29845] = 2, [29847] = 1}\n'
                'local me = {}\n'
                'function me:getGuid() return 7 end\n'
                'function me:getItemCount(id) return held[id] or 0 end\n'
                'function me:sendExtendedOpcode(op, msg) sent[#sent + 1] = msg end\n'
                'function me:sendTextMessage(_, text) texts[#texts + 1] = text end\n'
                'function me:setStorageValue() end\n'
                'local dpos = {house = true, getTile = function(self) return {getHouse = function() return true end} end}\n'
                'local device = {getActionId = function() return 42707 end, isItem = function() return true end, '
                'getPosition = function() return dpos end}\n'
                'local file = assert(loadfile(%r))\n'
                'pcall(file)\n'
                'local function eq(a, b, m) if a ~= b then error(m .. ": " .. tostring(a), 2) end end\n'
                'eq(#actions, 2, "device action and tier action")\n'
                'local dev, tier = actions[1], actions[2]\n'
                'eq(#tier.ids, 15, "fifteen tier ids")\n'
                'dev.onUse(me, device, dpos, nil, dpos, false)\n'
                'local m = sent[#sent]\n'
                'eq(m.action, "show", "show")\n'
                'eq(#m.tiers, 6, "six tiers")\n'
                'eq(m.tiers[1].tier, 1, "tier I first") eq(m.tiers[1].clientId, 27189, "its client id") '
                'eq(m.tiers[1].count, 2, "two held")\n'
                'eq(m.tiers[3].count, 1, "tier III held") eq(m.tiers[6].count, 0, "tier VI not held")\n'
                'eq(m.pick, nil, "the device alone picks nothing")\n'
                'local tierItem = {getId = function() return 29847 end}\n'
                'setmetatable(device, {__index = function() return nil end})\n'
                'tier.onUse(me, tierItem, {}, nil, {}, false)\n'
                'eq(texts[#texts], "Use this waystone on the waystone device in your hideout or house.", "elsewhere: where to use it")\n'
                'ChaosHideout = {waystoneDevice = function(p) return device end}\n'
                'tier.onUse(me, tierItem, {}, nil, {}, false)\n'
                'eq(sent[#sent].pick, 27191, "used in the hideout: tier III picked")\n'
                'ChaosHideout = nil\n'
                'tier.onUse(me, tierItem, {}, device, dpos, false)\n'
                'eq(sent[#sent].pick, 27191, "used on the device: tier III picked")\n'
                'dev.onUse(me, device, dpos, nil, dpos, false)\n'
                'eq(sent[#sent].pick, nil, "the pick is used once")\n'
                'held[41959] = 3\n'
                'ChaosWaystoneTiers = {tablets = function() local o = {} for i = 41951, 41959 do o[i] = i end return o end, '
                'tierLevel = function(t) return 1000 + 100 * t end}\n'
                'dev.onUse(me, device, dpos, nil, dpos, false)\n'
                'm = sent[#sent]\n'
                'eq(#m.tiers, 15, "part 3: fifteen tiers")\n'
                'eq(m.tiers[1].level, 1100, "tier I level") eq(m.tiers[15].clientId, 41959, "tier XV keyed by its server id")\n'
                'eq(m.tiers[15].count, 3, "tier XV held") eq(m.tiers[15].level, 2500, "tier XV level")\n'
                'print("part 2 ok")\n') % lua_path(d)
            r = subprocess.run([lua, '-e', probe2], stdin=subprocess.DEVNULL, capture_output=True, timeout=30)
            ok(r.returncode == 0 and b'part 2 ok' in r.stdout, '%s runs part 2: %s %s' % (lua, r.stdout[-300:], r.stderr[:300]))
finally:
    shutil.rmtree(d)

# a server patched by part 1 only gets part 2 on the next run
d = tree()
try:
    old_text, _, err = P.patch_lua_part1(LUA)
    ok(err is None and P.MARK2 not in old_text, 'part 1 alone')
    with open(lua_path(d), 'w', newline='') as f:
        f.write(old_text)
    ok(P.main([d]) == 0, 'part 1 install: next run')
    t = rd(lua_path(d))
    ok(t.count(P.MARK) == 1 and t.count(P.MARK2) == 1, 'part 1 install: part 2 added once')
finally:
    shutil.rmtree(d)

# CRLF text is kept
crlf_lua, crlf_xml = LUA.replace('\n', '\r\n'), XML.replace('\n', '\r\n')
d = tree(crlf_lua, crlf_xml)
try:
    t = check_tree(d, 'crlf', crlf_lua, crlf_xml)
    ok(t.count('\n') == t.count('\r\n'), 'crlf: every line break is CRLF')
finally:
    shutil.rmtree(d)

# the original signature mismatch is refused, nothing written
for what, lua, xml in [
        ('a use check that differs', LUA.replace('getTile():getHouse()', 'getTile():getZone()'), XML),
        ('no pad check', LUA.replace('tileHouse:getOwnerGuid()', 'tileHouse:getName()'), XML),
        ('no PAD_AID line', LUA.replace('local PAD_AID = 46201', 'local PAD = 1'), XML),
        ('no wrap line', LUA.replace('waystoneDevice:transform(29628)', 'waystoneDevice:remove()'), XML),
        ('a changed no-space message', LUA.replace('in your house to spawn', 'in the keep to spawn'), XML),
        ('five descriptions only', LUA, XML.replace('Use This waystone on waystone device at house to teleport to a random tier 6 map.', 'x')),
        ('no show message', LUA.replace('json.encode{ action = "show" }', 'json.encode{ action = "open" }'), XML),
        ('no teleport center line', LUA.replace('local center = pendingCenter[guid]', 'local c = nil'), XML),
        ('empty files', '', '')]:
    d = tree(lua, xml)
    try:
        ok(P.main([d]) == 1, 'refused: ' + what)
        ok(rd(lua_path(d)) == lua and rd(xml_path(d)) == xml, 'nothing written: ' + what)
    finally:
        shutil.rmtree(d)
for lua, xml, what in [(LUA, None, 'items.xml missing'), (None, XML, 'tier_maps.lua missing')]:
    d = tree(lua, xml)
    try:
        ok(P.main([d]) == 1, 'refused: ' + what)
    finally:
        shutil.rmtree(d)

# a marker with a piece removed is refused
d = tree()
try:
    P.main([d])
    broken = rd(lua_path(d)).replace('ChaosHideout.isFixture(waystoneDevice)', 'nothing')
    with open(lua_path(d), 'w', newline='') as f:
        f.write(broken)
    ok(P.main([d]) == 1, 'a half-patched script is refused')
finally:
    shutil.rmtree(d)

# a copy of the real base files, when given
base = os.environ.get('WAYSTONE_BASE_DATA')
if base and os.path.isfile(os.path.join(base, 'scripts', 'customs', 'waystone_system', 'tier_maps.lua')):
    d = tempfile.mkdtemp()
    try:
        os.makedirs(os.path.dirname(lua_path(d)))
        os.makedirs(os.path.dirname(xml_path(d)))
        shutil.copy(os.path.join(base, 'scripts', 'customs', 'waystone_system', 'tier_maps.lua'), lua_path(d))
        shutil.copy(os.path.join(base, 'items', 'items.xml'), xml_path(d))
        check_tree(d, 'real', rd(lua_path(d)), rd(xml_path(d)))
    finally:
        shutil.rmtree(d)

print('patch_waystone_hideout_test: %s' % ('FAILED %d' % fails if fails else 'OK'))
sys.exit(1 if fails else 0)
