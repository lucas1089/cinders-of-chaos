-- service_npcs_run.lua: the engine side of the service NPCs' talk, loaded by data/npc/scripts/chaos_service_npc.lua in
-- the NPC's own Lua state (it is not a revscript: nothing is registered). The rules are in service_npcs_core.lua; the
-- windows, the money and the base server's commands are the modules' own: this file only opens a window (the module's
-- opcode, "npc" action), reads the houses, and runs the base server's talkactions in a sandbox like commands_ui.lua
-- (the Info & Services window), through the shared loader of commands_ui_core.lua.
--   ChaosServiceNpcsRun.open(player, key)                 opens the NPC's window on the client
--   ChaosServiceNpcsRun.houses()                          {{id, name, town, townName, owner, tiles}}
--   ChaosServiceNpcsRun.perSqm()                          the price of a tile, nil when houses are not for sale
--   ChaosServiceNpcsRun.buyHouse(player, house)           true | false, reason | false, "money", price
--   ChaosServiceNpcsRun.runBase(player, id, param)        the text of a base command (K.BASE id), or nil when it is
--                                                         not on this server
-- Assumed engine API (TFS 1.4): Game.getHouses, House:getId/getName/getTown/getOwnerGuid/setOwnerGuid/getTileCount,
-- Town:getId/getName, Player:isPremium/getHouse/getTotalMoney/removeTotalMoney (the base lib; else getMoney + getBankBalance/removeMoney)/sendExtendedOpcode,
-- configManager.getNumber(configKeys.HOUSE_PRICE). Lua 5.1 / LuaJIT and 5.3.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not ChaosServiceNpcsCore then
	dofile("data/scripts/chaos/service_npcs_core.lua")
end
if not ChaosCommandsCore or not ChaosCommandsCore.baseHandler then
	dofile("data/scripts/chaos/commands_ui_core.lua")
end

ChaosServiceNpcsRun = ChaosServiceNpcsRun or {}
local R = ChaosServiceNpcsRun
local K = ChaosServiceNpcsCore
local CC = ChaosCommandsCore

R.cfg = R.cfg or dofile("data/scripts/chaos/service_npcs_config.lua")

function R.open(player, key)
	local opcodeKey, json = K.openJson(key, R.cfg)
	local opcode = opcodeKey and ChaosOpcodes and ChaosOpcodes[opcodeKey]
	if not opcode or not json then
		return false
	end
	return pcall(function()
		player:sendExtendedOpcode(opcode, json)
	end)
end

function R.perSqm()
	local value
	if configManager and configKeys and configKeys.HOUSE_PRICE then
		local ok, v = pcall(configManager.getNumber, configKeys.HOUSE_PRICE)
		value = ok and tonumber(v) or nil
	end
	if value == nil then
		value = R.cfg.broker.perSqm
	end
	if value < 0 then
		return nil -- the base config switches house sales off with -1
	end
	return value
end

function R.houses()
	local out = {}
	local ok, list = pcall(Game.getHouses)
	for _, h in ipairs(ok and list or {}) do
		local okH, row = pcall(function()
			local town = h:getTown()
			return {id = h:getId(), name = h:getName(), town = town and town:getId() or 0,
				townName = town and town:getName() or "", owner = h:getOwnerGuid(), tiles = h:getTileCount()}
		end)
		if okH and row then
			out[#out + 1] = row
		end
	end
	return out
end

function R.ownsHouse(player)
	local ok, house = pcall(function() return player:getHouse() end)
	return ok and house ~= nil and house ~= false
end

-- buys `house` (a row of R.houses) for the player; the live house is read again, so a sale between the list and the
-- purchase is caught. true | false, reason (a key of K.TEXT) [, price]
function R.buyHouse(player, row)
	local perSqm = R.perSqm()
	local live = House(row.id)
	if not live then
		return false, "taken"
	end
	local price = K.price(live:getTileCount(), perSqm or 0)
	local ok, reason = K.buyCheck({
		priceOn = perSqm ~= nil,
		premium = player:isPremium(),
		owner = live:getOwnerGuid(),
		owns = R.ownsHouse(player),
		price = price,
		money = player.getTotalMoney and player:getTotalMoney() or (player:getMoney() + player:getBankBalance())
	})
	if not ok then
		return false, reason, price
	end
	local paid = price == 0
	if not paid then
		if player.removeTotalMoney then
			paid = player:removeTotalMoney(price)
		else
			paid = player:removeMoney(price)
		end
	end
	if not paid then
		return false, "money", price
	end
	live:setOwnerGuid(player:getGuid())
	return true, nil, price
end

-- one base command (commands_ui_core.lua K.BASE), its text caught as commands_ui.lua does
local loaded = {}
local xmlMap
function R.runBase(player, id, param)
	if loaded[id] == nil then
		if not xmlMap then
			xmlMap = CC.parseXml(CC.readFile(CC.XML_PATH) or "")
		end
		loaded[id] = CC.baseHandler(id, xmlMap) or false
	end
	local fn = loaded[id]
	if not fn then
		return nil
	end
	local def = CC.BASE[id]
	local lines, restore = CC.capture(Player, player:getId(), function(p) return p.getId and p:getId() end,
		Game and Game.getReturnMessage)
	local ok, err = pcall(fn, player, def.words or "", param or "")
	restore()
	if not ok then
		print("[chaos service npcs] " .. id .. ": " .. tostring(err))
		return nil
	end
	return CC.joinLines(CC.rewrite(lines), "Done.")
end

return R
