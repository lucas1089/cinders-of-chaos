-- Client services export: what the login screen shows before the player enters the game.
--
-- The client asks an HTTP endpoint (server/tools/clientservices.py) with POST {"type": ...}:
--   "boostedcreature" -> {"creature": {name, outfit}, "boss": {name, outfit}}
--   "eventschedule"   -> {"eventlist": [...]}          (ChaosEvents.calendar, events_schedule.lua)
--   "cacheinfo"       -> {"playersonline": n, "online": "n players online"}
-- The game server has no HTTP listener, so this script writes all three answers into one JSON file
-- (Chaos.clientServices.file) at startup and every refreshSeconds; the endpoint only serves that file.
--
-- Boosted creature / boss: the reference server picks them at startup (global storages + its lists,
-- see data/lib/custom/update_daily_*.lua). When that pick is missing or names a monster that does not
-- exist, a pick from Chaos.boosted is used instead (stored in global storages, renewed daily).

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end

ChaosClientServices = ChaosClientServices or {}
local S = ChaosClientServices

local function monsterInfo(name)
	if type(name) ~= "string" or name == "" then
		return nil
	end
	local mt = MonsterType(name)
	if not mt then
		return nil
	end
	local ok, outfit = pcall(function() return mt:outfit() end)
	if not ok or type(outfit) ~= "table" or (outfit.lookType or 0) == 0 then
		return nil
	end
	local okName, realName = pcall(function() return mt:getName() end)
	return {
		name = okName and realName or name,
		outfit = {
			type = outfit.lookType or 0,
			auxType = outfit.lookTypeEx or 0,
			head = outfit.lookHead or 0,
			body = outfit.lookBody or 0,
			legs = outfit.lookLegs or 0,
			feet = outfit.lookFeet or 0,
			addons = outfit.lookAddons or 0
		}
	}
end

-- the reference server's own pick, if any
local function referencePick(listName, storageName)
	local list = rawget(_G, listName)
	local keys = rawget(_G, "PlayerStorageKeys")
	if type(list) ~= "table" or type(keys) ~= "table" or not keys[storageName] then
		return nil
	end
	local index = Game.getStorageValue(keys[storageName]) or -1
	return list[index]
end

-- our fallback pick: random existing monster from the list, kept for the whole day
local function fallbackPick(list, storageKey)
	local cfg = Chaos.boosted
	local today = Chaos.dayKey()
	local index = Game.getStorageValue(storageKey) or -1
	if Game.getStorageValue(cfg.storageDay) == today and list[index] and monsterInfo(list[index]) then
		return list[index]
	end
	local candidates = {}
	for i, name in ipairs(list) do
		if monsterInfo(name) then
			candidates[#candidates + 1] = i
		end
	end
	if #candidates == 0 then
		return nil
	end
	index = candidates[math.random(#candidates)]
	Game.setStorageValue(storageKey, index)
	Game.setStorageValue(cfg.storageDay, today)
	return list[index]
end

function S.boostedCreature()
	local info = monsterInfo(referencePick("boostedMonsterList", "boostedCreature"))
	return info or monsterInfo(fallbackPick(Chaos.boosted.creatures, Chaos.boosted.storageCreature))
end

function S.boostedBoss()
	local info = monsterInfo(referencePick("boostedBossesList", "boostedBoss"))
	return info or monsterInfo(fallbackPick(Chaos.boosted.bosses, Chaos.boosted.storageBoss))
end

function S.build()
	-- tester bots are never counted (testers.lua, src-patch 0059)
	local online = Chaos.countedPlayers and Chaos.countedPlayers() or (Game.getPlayerCount and Game.getPlayerCount() or #Game.getPlayers())
	local schedule = ChaosEvents and ChaosEvents.calendar() or {eventlist = {}}
	return {
		updated = os.time(),
		boostedcreature = {creature = S.boostedCreature(), boss = S.boostedBoss()},
		eventschedule = schedule,
		cacheinfo = {playersonline = online, online = online .. " players online"}
	}
end

function S.export()
	local ok, data = pcall(S.build)
	if not ok then
		print("[ChaosClientServices] build failed: " .. tostring(data))
		return false
	end
	local okEncode, text = pcall(json.encode, data)
	if not okEncode then
		print("[ChaosClientServices] encode failed: " .. tostring(text))
		return false
	end
	local path = Chaos.clientServices.file
	local tmp = path .. ".tmp"
	local f = io.open(tmp, "w")
	if not f then
		print("[ChaosClientServices] cannot write " .. tmp)
		return false
	end
	f:write(text)
	f:close()
	os.rename(tmp, path) -- readers never see a half-written file
	return true
end

-- the reference startup events pick the boosted monsters; export a moment later
local startup = GlobalEvent("ChaosClientServicesStartup")
function startup.onStartup()
	addEvent(S.export, 3000)
	return true
end
startup:register()

local refresh = GlobalEvent("ChaosClientServicesRefresh")
function refresh.onThink(interval)
	S.export()
	return true
end
refresh:interval((Chaos.clientServices.refreshSeconds or 300) * 1000)
refresh:register()
