-- healing_rules.lua: the healing rules on every player (numbers and pure rules: healing_rules_core.lua, ChaosHealing).
--   * Weaver's Grace (Illusionist passive): a heal the Illusionist casts on another player is x(1 + othersBonus).
--   * PvP healing reduction: a heal received while in PvP combat is x healingTaken (any healer, potions included).
-- One onHealthChange event on every player (registered one tick after login, after the other login events, so it sees
-- the heal as the other events leave it). Heals of regeneration conditions and of Chaos.heal / addHealth (auras,
-- the Sentinel's regeneration) do not pass onHealthChange and are not changed.
-- The same event notes PvP combat: a player damaged by a player (or a player's summon), and the player who dealt it.

if not (ChaosHealing and ChaosHealing.healMultiplier) then
	dofile("data/scripts/chaos/healing_rules_core.lua")
end
local M = ChaosHealing

local function now()
	return os.mtime and os.mtime() or os.time() * 1000
end

-- the player behind an attacker (itself, or the master of a summon)
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

local function inSiegeArena(player)
	local S = ChaosSiege
	if not (S and S.locate and S.state and S.state.phase == "match") then
		return false
	end
	return S.locate(player:getPosition()) == "arena"
end

-- PvP combat: recent player damage either way, a fight lock from attacking a player, an arena match, the siege arena
function M.inPvp(player)
	if M.recentPvp(M.pvpState, player:getId(), now()) then
		return true
	end
	if player.isPzLocked and player:isPzLocked() then
		return true
	end
	if ChaosArena and ChaosArena.isInside and ChaosArena.isInside(player) then
		return true
	end
	return inSiegeArena(player)
end

local event = CreatureEvent("ChaosHealing")
function event.onHealthChange(creature, attacker, pd, pt, sd, st, origin)
	if not creature or not creature:isPlayer() then
		return pd, pt, sd, st
	end
	if pt == COMBAT_HEALING then
		local healer = attacker and attacker:isPlayer() and attacker or nil
		local m = M.healMultiplier({healerVoc = healer and healer:getVocation():getId() or nil,
			selfHeal = not healer or healer:getId() == creature:getId(), pvp = M.inPvp(creature)})
		if m ~= 1 then
			pd = M.scale(pd, m)
			if st == COMBAT_HEALING then
				sd = M.scale(sd, m)
			end
		end
		return pd, pt, sd, st
	end
	local from = playerOf(attacker)
	if from and from:getId() ~= creature:getId() and (pd ~= 0 or sd ~= 0) then
		local t = now()
		M.markPvp(M.pvpState, creature:getId(), t)
		M.markPvp(M.pvpState, from:getId(), t)
	end
	return pd, pt, sd, st
end
event:register()

local login = CreatureEvent("ChaosHealingLogin")
function login.onLogin(player)
	local pid = player:getId()
	addEvent(function()
		local p = Player(pid)
		if p then
			p:registerEvent("ChaosHealing")
		end
	end, 0)
	return true
end
login:register()

local logout = CreatureEvent("ChaosHealingLogout")
function logout.onLogout(player)
	M.pvpState[player:getId()] = nil
	return true
end
logout:register()
