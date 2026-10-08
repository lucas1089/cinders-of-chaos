-- multiclient.lua: up to Chaos.multiClient.maxPerIp characters per IP (2), and the multi-client blocks.
-- Helpers and settings: Chaos.multiClient / Chaos.mcSiblings / Chaos.isMultiClient in chaos_constants.lua.
--   * login refused when the IP already has maxPerIp characters online, or when one of them is inside a dungeon
--     run or the Infinity Tower (dungeons.lua / infinitytower_run.lua refuse multi-clienting characters too)
--   * a multi-clienting character cannot attack players (melee, distance, runes, spells; the Chaos spells that
--     deal damage from their script check the same in ChaosSpell.canAttack)
-- The base server's own anti-mc login script (4 per IP) can stay; the lower limit wins.
-- Game.setStorageValue(Chaos.multiClient.offStorage, 1) switches the blocks off (not the login limit).
if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end

-- every character from the IP, blocks or not (the login limit always applies)
local function sameIp(player)
	local list = {}
	local ip = player:getIp()
	if ip == 0 or player:getGroup():getId() >= Chaos.multiClient.exemptGroup then
		return list
	end
	for _, other in ipairs(Game.getPlayers()) do
		if other ~= player and other:getIp() == ip then
			list[#list + 1] = other
		end
	end
	return list
end

local function insideInstance(player)
	return (ChaosDungeonIsInside and ChaosDungeonIsInside(player))
		or (ChaosTowerRun and ChaosTowerRun.isInside and ChaosTowerRun.isInside(player))
end

local login = CreatureEvent("ChaosMultiClientLogin")
function login.onLogin(player)
	local online = #sameIp(player)
	if online + 1 > Chaos.multiClient.maxPerIp then
		print(string.format("[ChaosMC] %s refused: %d characters online from the same IP", player:getName(), online))
		player:popupFYI(string.format("Only %d characters from the same connection can be online at once.", Chaos.multiClient.maxPerIp))
		return false
	end
	local siblings = Chaos.mcSiblings(player) -- empty while the blocks are switched off
	for _, other in ipairs(siblings) do
		if insideInstance(other) then
			print(string.format("[ChaosMC] %s refused: %s (same IP) is in a dungeon or the tower", player:getName(), other:getName()))
			player:popupFYI(other:getName() .. " (same connection) is in a dungeon or the Infinity Tower. Log in again when they are out.")
			return false
		end
	end
	if #siblings > 0 then
		player:sendTextMessage(MESSAGE_INFO_DESCR, string.format(
			"Another character from your connection is online: dungeons, the Infinity Tower and PvP are blocked for both (max %d characters).",
			Chaos.multiClient.maxPerIp))
	end
	return true
end
login:register()

local function playerOf(creature)
	if not creature then
		return nil
	end
	if creature:isPlayer() then
		return creature
	end
	local master = creature:getMaster()
	return master and master:isPlayer() and master or nil
end

local lastNotice = {} -- player id -> os.time() of the last explanation (area spells check every tile)

local pvp = EventCallback
pvp.onTargetCombat = function(creature, target)
	local attacker = playerOf(creature)
	if attacker and target and target:isPlayer() and target ~= attacker and Chaos.isMultiClient(attacker) then
		local id = attacker:getId()
		if (lastNotice[id] or 0) + 2 <= os.time() then
			lastNotice[id] = os.time()
			attacker:sendTextMessage(MESSAGE_STATUS_SMALL, Chaos.multiClient.msgPvp)
		end
		return RETURNVALUE_YOUMAYNOTATTACKTHISPLAYER
	end
	return RETURNVALUE_NOERROR
end
pvp:register()
