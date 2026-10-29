-- Right-click equips (engine src-patch 0024, client game_rightclickequip, extended opcode ChaosOpcodes.rightClickEquip
-- = 188; server/README.md "Right-click equips"). The engine equips on use; this glue keeps the client option
-- "Right-click equips items" in the storage the engine reads (Chaos.storage.rightClickEquipOff; the client sends
-- {on = true | false} at every login and when the option changes), and sends the client at login the multi-use
-- weapons a right-click equips (the list is worked out once, from the item types and data/actions/actions.xml).
-- Rules: rightclick_equip_core.lua; numbers: rightclick_equip_config.lua (tests/rightclick_equip_test.lua).
-- Lua 5.1 / LuaJIT compatible.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not ChaosRightClickEquip or not ChaosRightClickEquip.update then
	dofile("data/scripts/chaos/rightclick_equip_core.lua")
end

local R = ChaosRightClickEquip
local cfg = dofile("data/scripts/chaos/rightclick_equip_config.lua")
local OPCODE = ChaosOpcodes.rightClickEquip or 188
local KEY = Chaos.storage.rightClickEquipOff or 7101810

-- the client ids of the multi-use weapons a right-click equips (worked out at the first login, then kept)
local listJson
local function list()
	if listJson then
		return listJson
	end
	local xml = ""
	local f = io.open(cfg.actionsFile, "r")
	if f then
		xml = f:read("*a") or ""
		f:close()
	else
		print("[Chaos right-click equip] " .. cfg.actionsFile .. " not found: every multi-use weapon counts as equipment")
	end
	local keep = {}
	for _, id in ipairs(cfg.keepUseWith or {}) do
		keep[id] = true
	end
	local items = {}
	for id = cfg.firstItemId, cfg.lastItemId do
		local it = ItemType(id)
		if it and it:getId() == id and it:isUseable() then
			items[#items + 1] = {id = id, clientId = it:getClientId(), useable = true, pickupable = it:isPickupable(),
				container = it:isContainer(), slotPosition = it:getSlotPosition(), weaponType = it:getWeaponType()}
		end
	end
	local ids = R.multiUseIds(items, cfg.toolWeaponsKeepUseWith and R.toolIds(xml, cfg.destroyScripts) or {}, keep, _G)
	listJson = json.encode(R.listMessage(ids))
	print(string.format("[Chaos right-click equip] %d multi-use weapon look(s) equip on a right-click", #ids))
	return listJson
end

local login = CreatureEvent("ChaosRightClickEquipLogin")
function login.onLogin(player)
	player:registerEvent("ChaosRightClickEquipOpcode")
	local ok, err = pcall(function()
		Chaos.sendChunked(player, OPCODE, list())
	end)
	if not ok then
		print("[Chaos right-click equip] login: " .. tostring(err))
	end
	return true
end
login:type("login")
login:register()

local opcode = CreatureEvent("ChaosRightClickEquipOpcode")
function opcode.onExtendedOpcode(player, code, buffer)
	if code ~= OPCODE then
		return
	end
	local want = R.update(player:getStorageValue(KEY), Chaos.decode(buffer))
	if want ~= nil then
		player:setStorageValue(KEY, want)
	end
end
opcode:type("extendedopcode")
opcode:register()
