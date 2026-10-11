-- Run from the server/ folder: luajit tests/rightclick_equip_test.lua (no engine needed; CI runs it with luajit and lua5.3)
-- Covers "Right-click equips" (server/README.md): the client option's message (rightclick_equip_core.lua), the storage
-- the engine reads (src-patch 0024, Game::chaosUseEquip), the engine's equipment rule mirrored in Lua, the actions.xml
-- reading (destroy script vs tools), the multi-use list, and the glue (rightclick_equip.lua) against a mocked engine:
-- the login registers the opcode event and sends the list, {on = false} turns it off, {on = true} back on, a repeated
-- message writes nothing, another opcode and junk are ignored. The engine side (which slot, the move events) is C++
-- and was tested live (server/README.md).
dofile("data/scripts/chaos/chaos_constants.lua")
dofile("data/scripts/chaos/rightclick_equip_core.lua")
local R = ChaosRightClickEquip

local fails, checks = 0, 0
local function ok(cond, what)
	checks = checks + 1
	if not cond then
		fails = fails + 1
		print("FAIL " .. what)
	end
end
local function eq(a, b, what)
	ok(a == b, what .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end

-- ------------------------------------------------------------------ opcode and storage
eq(ChaosOpcodes.rightClickEquip, 188, "opcode")
local seen = {}
for name, v in pairs(ChaosOpcodes) do
	ok(seen[v] == nil, "opcode " .. v .. " used twice (" .. name .. ", " .. tostring(seen[v]) .. ")")
	seen[v] = name
end
for _, v in ipairs({1, 67, 73, 89, 91, 92, 99, 106, 107, 136, 181, 201, 202, 140, 144, 145, 146, 210, 212, 213, 230, 246}) do
	ok(ChaosOpcodes.rightClickEquip ~= v, "not a base opcode " .. v)
end
eq(Chaos.storage.rightClickEquipOff, 7101810, "storage")
for name, v in pairs(Chaos.storage) do
	if type(v) == "number" and name ~= "rightClickEquipOff" then
		ok(v < 7101810 or v > 7101819, "storage block 7101810 - 7101819 is free of " .. name)
	end
end

-- the engine reads the same number (src-patch 0024)
local f = io.open("src-patches/0024-equip-on-use.patch", "r")
ok(f ~= nil, "src-patch 0024 present")
if f then
	local patch = f:read("*a")
	f:close()
	ok(patch:find("CHAOS_EQUIP_ON_USE_OFF = 7101810;", 1, true) ~= nil, "engine storage key matches")
	ok(patch:find("off == 1", 1, true) ~= nil, "engine: only 1 turns it off")
end

-- ------------------------------------------------------------------ the message
eq(R.storageValue({on = false}), R.OFF, "off")
eq(R.storageValue({on = true}), R.ON, "on")
eq(R.storageValue({on = 0}), R.OFF, "0 is off")
eq(R.storageValue({on = "true"}), R.ON, "text true")
eq(R.storageValue({action = "set", data = {on = false}}), R.OFF, "the action / data form")
eq(R.storageValue({on = "maybe"}), nil, "junk value")
eq(R.storageValue({}), nil, "no value")
eq(R.storageValue(nil), nil, "no message")
eq(R.storageValue("on"), nil, "not a table")
eq(R.OFF, 1, "the engine reads 1 as off")
ok(R.ON ~= R.OFF, "on differs")

-- ------------------------------------------------------------------ stored value -> on / off
ok(R.isOn(-1), "unset (-1): on, the default")
ok(R.isOn(nil), "nil: on")
ok(R.isOn(0), "0: on")
ok(not R.isOn(1), "1: off")
ok(R.isOn(2), "anything else: on (as the engine)")

-- ------------------------------------------------------------------ update: write only a change
eq(R.update(-1, {on = true}), nil, "default and on: nothing to write")
eq(R.update(-1, {on = false}), R.OFF, "turned off")
eq(R.update(1, {on = false}), nil, "already off")
eq(R.update(1, {on = true}), R.ON, "back on")
eq(R.update(0, {on = true}), nil, "already on")
eq(R.update(1, {junk = 1}), nil, "junk changes nothing")

-- ------------------------------------------------------------------ the engine's equipment rule (Game::chaosEquipsOnUse)
local C = {SLOTP_HEAD = 1, SLOTP_NECKLACE = 2, SLOTP_BACKPACK = 4, SLOTP_ARMOR = 8, SLOTP_RIGHT = 16, SLOTP_LEFT = 32,
	SLOTP_LEGS = 64, SLOTP_FEET = 128, SLOTP_RING = 256, SLOTP_AMMO = 512, SLOTP_TWO_HAND = 2048, SLOTP_DECK = 4096,
	WEAPON_NONE = 0, WEAPON_SWORD = 1, WEAPON_CLUB = 2, WEAPON_AXE = 3, WEAPON_SHIELD = 4, WEAPON_DISTANCE = 5,
	WEAPON_WAND = 6, WEAPON_AMMO = 7, WEAPON_QUIVER = 8}
local HAND = 48
ok(R.equipsOnUse(1 + HAND, 0, C), "helmet")
ok(R.equipsOnUse(2 + HAND, 0, C), "amulet")
ok(R.equipsOnUse(8 + HAND, 0, C), "armour")
ok(R.equipsOnUse(64 + HAND, 0, C), "legs")
ok(R.equipsOnUse(128 + HAND, 0, C), "boots")
ok(R.equipsOnUse(256 + HAND, 0, C), "ring")
ok(R.equipsOnUse(HAND, 1, C), "sword")
ok(R.equipsOnUse(HAND + 2048, 3, C), "two-handed axe")
ok(R.equipsOnUse(HAND + 2048, 5, C), "bow")
ok(R.equipsOnUse(HAND, 4, C), "shield")
ok(R.equipsOnUse(16, 8, C), "quiver")
ok(R.equipsOnUse(HAND, 6, C), "wand")
ok(not R.equipsOnUse(HAND, 0, C), "anything a hand may hold (a potion, a rope)")
ok(not R.equipsOnUse(512 + HAND, 7, C), "ammunition")
ok(not R.equipsOnUse(4 + HAND, 0, C), "a backpack")
ok(not R.equipsOnUse(4096 + HAND, 0, C), "the base's extra slots")
eq(R.band(304, 256), 256, "band: club ring's slot bits hold the ring bit")
eq(R.band(48, 256), 0, "band: the hands do not")
-- the C++ rule names the same slots and weapon types (src-patch 0024)
if f then
	local fh = io.open("src-patches/0024-equip-on-use.patch", "r")
	local patch = fh:read("*a")
	fh:close()
	ok(patch:find("SLOTP_HEAD | SLOTP_NECKLACE | SLOTP_ARMOR | SLOTP_LEGS | SLOTP_FEET | SLOTP_RING", 1, true) ~= nil,
		"engine: the same slots")
	for _, w in ipairs({"WEAPON_SWORD", "WEAPON_CLUB", "WEAPON_AXE", "WEAPON_SHIELD", "WEAPON_DISTANCE", "WEAPON_WAND",
			"WEAPON_QUIVER"}) do
		ok(patch:find("+\t\tcase " .. w .. ":", 1, true) ~= nil, "engine: weapon type " .. w)
	end
	ok(patch:find("item->isUseable() && !isHotkey && item->getTopParent() == player", 1, true) ~= nil,
		"engine: a plain use of carried multi-use equipment")
end

-- ------------------------------------------------------------------ actions.xml: the destroy script and the tools
local xml = [[
<actions>
	<action fromid="2376" toid="2380" script="other/destroy.lua" />
	<action itemid="2420" script="tools/machete.lua" />
	<action itemid="2416;2550" script="tools/crowbar.lua"/>
	<!-- <action itemid="2400" script="other/commented.lua" /> -->
	<action fromid="2382" toid="2383" function="increaseItemId" />
	<action itemid="1000" script="OTHER/Destroy.lua" />
</actions>
]]
local acts = R.parseActions(xml)
eq(acts[2376], "other/destroy.lua", "range start")
eq(acts[2380], "other/destroy.lua", "range end")
eq(acts[2381], nil, "outside the range")
eq(acts[2420], "tools/machete.lua", "one id")
eq(acts[2550], "tools/crowbar.lua", "an id list")
eq(acts[2400], nil, "a commented entry is no action")
eq(acts[2383], "increaseItemId", "a function action")
local tools = R.toolIds(xml, {"other/destroy.lua"})
ok(not tools[2376] and not tools[2378], "destroy: no tool")
ok(not tools[1000], "destroy, other case: no tool")
ok(tools[2420] and tools[2416] and tools[2550] and tools[2382], "the tools and other actions keep their use with")
eq(next(R.parseActions(nil)), nil, "no file: nothing")

-- ------------------------------------------------------------------ the multi-use list
local items = {
	{id = 2376, clientId = 3264, useable = true, pickupable = true, slotPosition = HAND, weaponType = 1}, -- sword
	{id = 2377, clientId = 3265, useable = true, pickupable = true, slotPosition = HAND + 2048, weaponType = 1},
	{id = 2420, clientId = 3308, useable = true, pickupable = true, slotPosition = HAND, weaponType = 1}, -- machete
	{id = 2120, clientId = 3003, useable = true, pickupable = true, slotPosition = HAND, weaponType = 0}, -- rope
	{id = 7000, clientId = 9000, useable = true, pickupable = true, slotPosition = HAND, weaponType = 3}, -- no action
	{id = 7001, clientId = 9000, useable = true, pickupable = true, slotPosition = HAND, weaponType = 3}, -- same look
	{id = 7002, clientId = 9002, useable = true, pickupable = false, slotPosition = HAND, weaponType = 3},
	{id = 7003, clientId = 9003, useable = true, pickupable = true, container = true, slotPosition = 4, weaponType = 0},
	{id = 7004, clientId = 9004, useable = true, pickupable = true, slotPosition = HAND, weaponType = 2},
}
local ids = R.multiUseIds(items, tools, {[7004] = true}, C)
eq(table.concat(ids, ","), "3264,3265,9000", "weapons yes; a tool, a rope, a fixed item, a container, a kept id no")
eq(R.listMessage(ids).action, "multiuse", "message action")
eq(#R.listMessage(ids).data.ids, 3, "message ids")
eq(#R.listMessage(nil).data.ids, 0, "empty list")
local cfg = dofile("data/scripts/chaos/rightclick_equip_config.lua")
eq(cfg.destroyScripts[1], "other/destroy.lua", "config: the base destroy script")
ok(cfg.firstItemId < 2376 and cfg.lastItemId > 40000, "config: the scan covers the base and the Chaos items")

-- ------------------------------------------------------------------ glue against a mocked engine
local events = {}
function CreatureEvent(name)
	local e = {name = name}
	function e:type(t) self.kind = t end
	function e:register() events[self.name] = self end
	return e
end
json = json or {
	decode = function(s)
		if s == '{"on":false}' then return {on = false} end
		if s == '{"on":true}' then return {on = true} end
		error("bad json")
	end,
}
local encoded
json.encode = function(t) encoded = t return "ENCODED" end
for k, v in pairs(C) do _G[k] = v end
local types = {}
for _, it in ipairs(items) do types[it.id] = it end
function ItemType(id)
	local t = types[id]
	return {
		getId = function() return t and id or 0 end,
		isUseable = function() return t ~= nil end,
		getClientId = function() return t.clientId end,
		isPickupable = function() return t.pickupable end,
		isContainer = function() return t.container or false end,
		getSlotPosition = function() return t.slotPosition end,
		getWeaponType = function() return t.weaponType end,
	}
end
local sent = {}
Chaos.sendChunked = function(player, opcode, buffer) sent[#sent + 1] = {opcode, buffer} return true end
local realOpen = io.open
io.open = function(path, mode)
	if path == "data/actions/actions.xml" then
		return {read = function() return xml end, close = function() end}
	end
	return realOpen(path, mode)
end
local realPrint = print
print = function() end
dofile("data/scripts/chaos/rightclick_equip.lua")
print = realPrint
ok(events.ChaosRightClickEquipLogin and events.ChaosRightClickEquipLogin.kind == "login", "login event")
ok(events.ChaosRightClickEquipOpcode and events.ChaosRightClickEquipOpcode.kind == "extendedopcode", "opcode event")

local store, writes, registered = {}, 0, {}
local pl = {}
function pl:registerEvent(n) registered[#registered + 1] = n end
function pl:getStorageValue(k) return store[k] or -1 end
function pl:setStorageValue(k, v) store[k] = v; writes = writes + 1 end
print = function() end
ok(events.ChaosRightClickEquipLogin.onLogin(pl), "login returns true")
print = realPrint
eq(registered[1], "ChaosRightClickEquipOpcode", "login registers the opcode event")
eq(#sent, 1, "login sends the list")
eq(sent[1] and sent[1][1], 188, "on the opcode")
eq(sent[1] and sent[1][2], "ENCODED", "the encoded message")
eq(encoded and encoded.action, "multiuse", "list message")
eq(encoded and table.concat(encoded.data.ids, ","), "3264,3265,9000,9004", "the list from the item types and actions.xml (no kept ids in the config)")
encoded = nil
print = function() end
events.ChaosRightClickEquipLogin.onLogin(pl)
print = realPrint
eq(#sent, 2, "every login sends it")
eq(encoded, nil, "the list is worked out once")
io.open = realOpen

local on = events.ChaosRightClickEquipOpcode.onExtendedOpcode
on(pl, 188, '{"on":true}')
eq(writes, 0, "on at login with nothing stored: no write")
on(pl, 188, '{"on":false}')
eq(store[7101810], 1, "off stored")
on(pl, 188, '{"on":false}')
eq(writes, 1, "off again: no second write")
on(pl, 187, '{"on":true}')
eq(store[7101810], 1, "another opcode is ignored")
on(pl, 188, 'not json')
eq(store[7101810], 1, "junk is ignored")
on(pl, 188, '{"on":true}')
eq(store[7101810], 0, "back on")

print(string.format("rightclick_equip_test: %d checks, %d failures", checks, fails))
if fails > 0 then
	os.exit(1)
end
