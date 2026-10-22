-- Tester bots on the live server (server/README.md "Tester bots"; rules in testers_core.lua).
--
-- A tester is a character with the storage Chaos.storage.tester = 1 (written only by server/tools/testers.py setup).
-- The engine never counts it online (src-patch 0059). This script keeps it apart from the players:
--   * login: a tester in a staff group or on a staff account is refused (testers never get rights); its guid joins
--     Chaos.testerGuids, so rankings, records, the chronicle and Discord leave it out
--   * the name plate shows the title TESTER (top priority); every look at it says it is a test character
--   * no combat, trade or party between a tester and a player (summons count as their master)
--   * Game.broadcastMessage drops a broadcast that names a tester (level, achievement, record, prize broadcasts)
-- Assumed engine API (TFS 1.4.2): CreatureEvent login/logout, EventCallback onLook / onTargetCombat / onTradeRequest /
-- onTradeAccept / Party onJoin, GlobalEvent onStartup, db.storeQuery, Player:getGroup / getAccountType.
-- Lua 5.1 / LuaJIT compatible.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not ChaosTestersCore or not ChaosTestersCore.safetyProblem then
	dofile("data/scripts/chaos/testers_core.lua")
end

local K = ChaosTestersCore

ChaosTesters = ChaosTesters or {}
local X = ChaosTesters

local function log(text)
	print("[Chaos testers] " .. text)
end

local function testerOf(creature)
	if not creature then
		return nil
	end
	local p = creature
	if not creature:isPlayer() then
		local master = creature:getMaster()
		if not master or not master:isPlayer() then
			return nil
		end
		p = master
	end
	return p
end

local function isTester(creature)
	local p = testerOf(creature)
	return p ~= nil and Chaos.isTester(p)
end

local function isPlayerSide(creature)
	return testerOf(creature) ~= nil
end

-- every tester guid and name, from the database (startup and /reload)
function X.load()
	local id = db.storeQuery(string.format(
		"SELECT `p`.`id`, `p`.`name` FROM `players` `p` JOIN `player_storage` `s` ON `s`.`player_id` = `p`.`id` " ..
		"WHERE `s`.`key` = %d AND `s`.`value` = 1", Chaos.storage.tester))
	local n = 0
	if id then
		repeat
			Chaos.testerGuids[result.getNumber(id, "id")] = result.getString(id, "name")
			n = n + 1
		until not result.next(id)
		result.free(id)
	end
	return n
end

-- ---------------------------------------------------------------- login safety
local login = CreatureEvent("ChaosTestersLogin")
function login.onLogin(player)
	if not Chaos.isTester(player) then
		return true
	end
	local group = player:getGroup()
	local problem = K.safetyProblem(group and group:getId() or 0, player:getAccountType())
	if not problem and not K.isTesterName(player:getName()) then
		problem = "name is not \"Tester Xxx\""
	end
	if problem then
		log(string.format("refused tester %s (guid %d): %s", player:getName(), player:getGuid(), problem))
		return false
	end
	Chaos.testerGuids[player:getGuid()] = player:getName()
	return true
end
login:type("login")
login:register()

local startup = GlobalEvent("ChaosTestersStartup")
function startup.onStartup()
	local n = X.load()
	if n > 0 then
		log(string.format("%d tester character(s) known", n))
	end
	return true
end
startup:register()

-- ---------------------------------------------------------------- the TESTER tag
if ChaosTitles and ChaosTitles.register then
	ChaosTitles.register("tester", function(player)
		if not Chaos.isTester(player) then
			return nil
		end
		return {text = K.TITLE, key = "tester:tester", color = K.TITLE_COLOR, priority = K.TITLE_PRIORITY, at = 0}
	end)
end

local look = EventCallback
look.onLook = function(self, thing, position, distance, description)
	if thing and thing:isPlayer() and Chaos.isTester(thing) then
		description = (description or "") .. "\n" .. K.lookLine(thing:getId() == self:getId())
	end
	return description
end
look:register(103)

-- ---------------------------------------------------------------- apart from the players
local guard = EventCallback
guard.onTargetCombat = function(creature, target)
	if not creature or not target or not isPlayerSide(creature) or not isPlayerSide(target) then
		return RETURNVALUE_NOERROR
	end
	if K.mixed(isTester(creature), isTester(target)) then
		return RETURNVALUE_YOUMAYNOTATTACKTHISPLAYER
	end
	return RETURNVALUE_NOERROR
end
guard:register()

local trade = EventCallback
trade.onTradeRequest = function(player, target, item)
	if target and K.mixed(Chaos.isTester(player), Chaos.isTester(target)) then
		player:sendCancelMessage(RETURNVALUE_NOTPOSSIBLE)
		return false
	end
	return true
end
trade:register()

local accept = EventCallback
accept.onTradeAccept = function(player, target, item, targetItem)
	return not (target and K.mixed(Chaos.isTester(player), Chaos.isTester(target)))
end
accept:register()

local partyJoin = EventCallback
partyJoin.onJoin = function(party, player)
	local leader = party:getLeader()
	if leader and K.mixed(Chaos.isTester(leader), Chaos.isTester(player)) then
		player:sendCancelMessage(RETURNVALUE_NOTPOSSIBLE)
		return false
	end
	return true
end
partyJoin:register()

-- ---------------------------------------------------------------- broadcasts
if Game and Game.broadcastMessage and not X.rawBroadcast then
	X.rawBroadcast = Game.broadcastMessage
	Game.broadcastMessage = function(text, kind)
		if next(Chaos.testerGuids) ~= nil and K.mentions(text, Chaos.testerGuids) then
			return true
		end
		return X.rawBroadcast(text, kind)
	end
end
