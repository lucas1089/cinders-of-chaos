-- firsthour.lua: the first-hour hints and hunt reveals (firsthour_config.lua, firsthour_core.lua; docs/CONTENT.md
-- "First hour"). At the first login after the starter kit (newplayer.lua) and at the levels of the config, a character
-- gets a hint (a message and a toast) in its language, and the hunting grounds of its level nearest its temple are put
-- on its map: the hidden hunting marks of the map markers (poi.lua) are added to its discoveries, as if it had walked
-- there. Characters that played before this module get every hint marked as given, silently (cfg.quietAbove).
-- Without the map markers (no data/chaos_poi.lua) the hints still come, without hunt names.
-- Assumed engine API (TFS 1.4): CreatureEvent login/advance, Player storage, Town. Lua 5.1 / LuaJIT and 5.3.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not ChaosFirstHourCore or not ChaosFirstHourCore.pickHunts then
	dofile("data/scripts/chaos/firsthour_core.lua")
end

local M = ChaosFirstHourCore
ChaosFirstHour = ChaosFirstHour or {}
local F = ChaosFirstHour

local function C()
	return M.cfg()
end

local function key(name)
	local s = C().storage
	return s.base + s[name]
end

local function kitGiven(player)
	local base = Chaos.storage and Chaos.storage.newPlayer
	return base and player:getStorageValue(base) > 0
end

function F.langOf(player)
	local hooked
	if Chaos.lang then
		local ok, l = pcall(Chaos.lang, player)
		hooked = ok and l or nil
	end
	if ChaosTalesCore and ChaosTalesCore.lang and ChaosTalesCore.langKey then
		return ChaosTalesCore.lang(player:getStorageValue(ChaosTalesCore.langKey()), hooked)
	end
	return (hooked == "pt" or hooked == "pt-BR") and "pt" or "en"
end

-- the hunting marks of the player's level nearest its temple, added to its map discoveries -> their short names
function F.revealHunts(player)
	local P = ChaosPoi
	if not P or not P.all or not P.key or not P.seen then
		return {}
	end
	local town = player:getTown()
	local center = town and town:getTemplePosition() or player:getPosition()
	local guid = player:getGuid()
	local set = P.seen[guid]
	if not set then
		return {}
	end
	local found = M.pickHunts(P.all, set, P.key, center, player:getLevel())
	local names, list = {}, {}
	for _, m in ipairs(found) do
		set[P.key(m)] = true
		names[#names + 1] = M.shortName(m)
		list[#list + 1] = {k = m.k, x = m.x, y = m.y, z = m.z, n = m.n}
	end
	if #found > 0 then
		if P.dirty then
			P.dirty[guid] = true
		end
		if P.watch and P.watch[player:getId()] and Chaos.send then
			Chaos.send(player, ChaosOpcodes.mapMarkers or 153, "reveal", {marks = list})
		end
	end
	return names
end

local function tell(player, text)
	player:sendTextMessage(MESSAGE_EVENT_ADVANCE or MESSAGE_INFO_DESCR, text)
	if ChaosOpcodes and ChaosOpcodes.notifications and json then
		player:sendExtendedOpcode(ChaosOpcodes.notifications, json.encode({action = "newplayer", message = text}))
	end
end

-- give what is due at the character's level (once each)
function F.run(player)
	local level = player:getLevel()
	local names = {}
	local rmask = player:getStorageValue(key("reveals"))
	local due = M.dueReveals(rmask, level)
	if #due > 0 then
		names = F.revealHunts(player)
		for _, i in ipairs(due) do
			rmask = M.set(rmask, i)
		end
		player:setStorageValue(key("reveals"), rmask)
	end
	local hmask = player:getStorageValue(key("hints"))
	local lang = F.langOf(player)
	for _, i in ipairs(M.dueHints(hmask, level)) do
		tell(player, M.text(i, lang, names))
		hmask = M.set(hmask, i)
	end
	player:setStorageValue(key("hints"), hmask)
end

local login = CreatureEvent("ChaosFirstHourLogin")
function login.onLogin(player)
	if not C() or not C().enabled then
		return true
	end
	player:registerEvent("ChaosFirstHourAdvance")
	if player:getStorageValue(key("hints")) < 0 then
		if player:getLevel() > C().quietAbove then
			player:setStorageValue(key("hints"), M.all(#C().hints))
			player:setStorageValue(key("reveals"), M.all(#C().revealAt))
			return true
		end
		player:setStorageValue(key("hints"), 0)
	end
	-- the first hint waits for the kit (the tutorial island gives it when the character leaves)
	local pid = player:getId()
	addEvent(function()
		local p = Player(pid)
		if p and kitGiven(p) then
			F.run(p)
		end
	end, C().delayMs)
	return true
end
login:register()

local advance = CreatureEvent("ChaosFirstHourAdvance")
function advance.onAdvance(player, skill, oldLevel, newLevel)
	if skill == SKILL_LEVEL and newLevel > oldLevel and C() and C().enabled and kitGiven(player) then
		pcall(F.run, player)
	end
	return true
end
advance:register()

-- the welcome (newplayer.lua) comes when the kit is given, also when the character leaves the tutorial island: the
-- first hint follows it
local startup = GlobalEvent("ChaosFirstHourStartup")
function startup.onStartup()
	local NP = ChaosNewPlayer
	if NP and NP.showWelcome and not NP.firstHourWrapped then
		NP.firstHourWrapped = true
		local show = NP.showWelcome
		NP.showWelcome = function(player, ...)
			local shown = show(player, ...)
			if shown and C() and C().enabled and player then
				local pid = player:getId()
				addEvent(function()
					local p = Player(pid)
					if p and kitGiven(p) and p:getStorageValue(key("hints")) >= 0 then
						F.run(p)
					end
				end, C().delayMs)
			end
			return shown
		end
	end
	return true
end
startup:register()
