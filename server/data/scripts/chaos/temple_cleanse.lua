-- Temple cleanse (server/README.md "Temple cleanse"): every 2 seconds a player standing in a protection zone, not locked
-- for PvP and without a skull, loses the harmful conditions of monsters and bosses and the battle lock that held them
-- (beta report 2026-10-20: a 10-minute boss fire kept characters from the town portal and the NPCs). Rules:
-- temple_cleanse_core.lua. Assumed engine API (TFS 1.4): Game.getPlayers, Player:getTile/hasCondition/removeCondition/
-- isPzLocked/getSkull, Tile:hasFlag(TILESTATE_PROTECTIONZONE). Lua 5.1 / LuaJIT compatible.

dofile("data/scripts/chaos/temple_cleanse_core.lua")
local K = ChaosTempleCleanseCore

local ids
local function conditionIds()
	if not ids then
		ids = {}
		for _, name in ipairs(K.conditions) do
			local v = rawget(_G, name)
			if v then
				ids[#ids + 1] = v
			end
		end
	end
	return ids
end

local function skulled(player)
	local s = player:getSkull()
	return s == SKULL_WHITE or s == SKULL_RED or s == SKULL_BLACK
end

local cleanse = GlobalEvent("ChaosTempleCleanse")
function cleanse.onThink(interval)
	local list = conditionIds()
	for _, player in ipairs(Game.getPlayers()) do
		local tile = player:getTile()
		if tile and tile:hasFlag(TILESTATE_PROTECTIONZONE) then
			local has = false
			for _, c in ipairs(list) do
				if player:hasCondition(c) then
					has = true
					break
				end
			end
			if K.shouldClear({inProtectionZone = true, pzLocked = player:isPzLocked(), skulled = skulled(player), hasDebuff = has}) then
				for _, c in ipairs(list) do
					player:removeCondition(c)
				end
			end
		end
	end
	return true
end
cleanse:interval(2000)
cleanse:register()
