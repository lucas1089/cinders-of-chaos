-- rightclick_equip_core.lua: the rules of "Right-click equips items" (engine src-patch 0024, client
-- game_rightclickequip, extended opcode ChaosOpcodes.rightClickEquip = 188; the glue is rightclick_equip.lua; server/
-- README.md "Right-click equips"). Pure Lua, no engine calls; tests/rightclick_equip_test.lua.
--
-- The engine puts on a piece of equipment the player carries when it is used and has no action of its own, and takes
-- a worn one off (Game::chaosUseEquip). The client option turns that off for the character:
--   client -> server  {on = true | false}
-- and the storage Chaos.storage.rightClickEquipOff holds 1 while it is off (unset or anything else: on, the default).
-- Multi-use weapons (the stock "break furniture" use with) would start a use with on a right-click; the server tells
-- the client which of them to use plainly instead (the engine then equips them), at every login:
--   server -> client  {action = "multiuse", data = {ids = {client ids}}}
-- All carried equipment that is multi-use, minus the tools: an item with an action in actions.xml other than the
-- destroy script keeps its use with (machete, crowbar, scythe) only when the config toolWeaponsKeepUseWith is on; by
-- default they equip like every weapon (owner report: the crowbar still offered "Use with"). Lua 5.1 / LuaJIT and 5.3.

ChaosRightClickEquip = ChaosRightClickEquip or {}
local R = ChaosRightClickEquip

R.OFF = 1 -- the storage value the engine reads as "turned off"
R.ON = 0

-- the storage value a decoded client message asks for, or nil when the message is not one
function R.storageValue(msg)
	if type(msg) ~= "table" then
		return nil
	end
	local on = msg.on
	if on == nil and type(msg.data) == "table" then
		on = msg.data.on -- {action = ..., data = {on = ...}} as the other modules send
	end
	if on == true or on == 1 or on == "1" or on == "true" then
		return R.ON
	elseif on == false or on == 0 or on == "0" or on == "false" then
		return R.OFF
	end
	return nil
end

-- true when the stored value means "on" (the engine's reading: only R.OFF turns it off)
function R.isOn(stored)
	return tonumber(stored) ~= R.OFF
end

-- the value to write, or nil when nothing changes (the client sends the option at every login)
function R.update(stored, msg)
	local want = R.storageValue(msg)
	if want == nil or R.isOn(stored) == (want == R.ON) then
		return nil
	end
	return want
end

-- ------------------------------------------------------------------ which items equip on use
-- a AND b for non-negative integers (no bit library needed: Lua 5.1 / LuaJIT and 5.3)
local function band(a, b)
	a, b = math.floor(tonumber(a) or 0), math.floor(tonumber(b) or 0)
	local r, p = 0, 1
	while a > 0 and b > 0 do
		if a % 2 == 1 and b % 2 == 1 then
			r = r + p
		end
		a, b, p = math.floor(a / 2), math.floor(b / 2), p * 2
	end
	return r
end
R.band = band

-- the engine's rule (Game::chaosEquipsOnUse, src-patch 0024): a head, necklace, armour, legs, feet or ring item, or a
-- sword, club, axe, distance weapon, wand, shield or quiver. C holds the engine's constants (SLOTP_*, WEAPON_*).
function R.equipsOnUse(slotPosition, weaponType, C)
	local slots = 0
	for _, k in ipairs({"SLOTP_HEAD", "SLOTP_NECKLACE", "SLOTP_ARMOR", "SLOTP_LEGS", "SLOTP_FEET", "SLOTP_RING"}) do
		slots = slots + (tonumber(C[k]) or 0)
	end
	if band(slotPosition, slots) ~= 0 then
		return true
	end
	for _, k in ipairs({"WEAPON_SWORD", "WEAPON_CLUB", "WEAPON_AXE", "WEAPON_SHIELD", "WEAPON_DISTANCE", "WEAPON_WAND",
			"WEAPON_QUIVER"}) do
		if C[k] ~= nil and weaponType == C[k] then
			return true
		end
	end
	return false
end

-- the item ids with an action in an actions.xml text: {[id] = script} (a function action counts as its name)
function R.parseActions(xml)
	local out = {}
	if type(xml) ~= "string" then
		return out
	end
	xml = xml:gsub("<!%-%-.-%-%->", "")
	for tag in xml:gmatch("<action%s(.-)/?>") do
		local function attr(name)
			return tag:match("%f[%w]" .. name .. '%s*=%s*"([^"]*)"')
		end
		local script = attr("script") or attr("function") or "?"
		local ids = attr("itemid")
		if ids then
			for id in ids:gmatch("%d+") do
				out[tonumber(id)] = script
			end
		end
		local from, to = tonumber(attr("fromid") or ""), tonumber(attr("toid") or "")
		if from and to and to >= from and to - from <= 100000 then
			for id = from, to do
				out[id] = script
			end
		end
	end
	return out
end

-- {[id] = true} of the ids whose action is not one of the destroy scripts (a tool's use with)
function R.toolIds(xml, destroyScripts)
	local destroy = {}
	for _, s in ipairs(destroyScripts or {}) do
		destroy[s:gsub("\\", "/"):lower()] = true
	end
	local out = {}
	for id, script in pairs(R.parseActions(xml)) do
		if not destroy[script:gsub("\\", "/"):lower()] then
			out[id] = true
		end
	end
	return out
end

-- the sorted client ids of the multi-use equipment that a right-click equips. items: a list of
-- {id, clientId, useable, pickupable, container, slotPosition, weaponType}; tools and keep: sets of server ids
function R.multiUseIds(items, tools, keep, C)
	local seen, ids = {}, {}
	for _, it in ipairs(items or {}) do
		local cid = tonumber(it.clientId) or 0
		if it.useable and it.pickupable and not it.container and cid > 0 and not (tools or {})[it.id]
				and not (keep or {})[it.id] and R.equipsOnUse(it.slotPosition, it.weaponType, C) and not seen[cid] then
			seen[cid] = true
			ids[#ids + 1] = cid
		end
	end
	table.sort(ids)
	return ids
end

-- the login message with the list
function R.listMessage(ids)
	return {action = "multiuse", data = {ids = ids or {}}}
end

return R
