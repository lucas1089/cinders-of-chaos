-- Shadow Veil: vanish for 4 seconds; monsters lose you and your first weapon hit out of it is a critical hit.
--
-- Stealth (Chaos.classes.stealth): an invisibility condition with the class sub id. Every pulse, monsters around drop
-- the player as a target and take it off their target lists, so they cannot pick it again; a monster that still targets
-- it cannot attack it (data/scripts/chaos/thief_combat.lua). Dealing damage or taking a hit ends it. Not aggressive:
-- casting it does not end it. When it ends the monsters get the player back on their target lists.
dofile('data/spells/scripts/chaos/_common.lua')
ChaosSpell.loadClasses()

-- monsters made to drop the player; when the veil ends they get it back on their target lists (the engine only adds a
-- player again when it moves or appears, so a player standing still would stay forgotten)
local function restore(player, dropped)
	for id in pairs(dropped) do
		local m = Monster(id)
		if m and m:getHealth() > 0 and m:isOpponent(player) then
			m:addTarget(player)
			if m:isIdle() then
				m:setIdle(false)
			end
			if not m:getTarget() then
				m:searchTarget()
			end
		end
	end
end

local function pulse(playerId, left, dropped)
	local player = Player(playerId)
	if not player then
		return
	end
	local cfg = Chaos.classes
	if not player:getCondition(CONDITION_INVISIBLE, CONDITIONID_COMBAT, cfg.subId.stealth) then
		restore(player, dropped)
		return
	end
	for _, c in ipairs(ChaosSpell.spectators(player:getPosition(), cfg.stealth.radius)) do
		if c:isMonster() and ChaosSpell.isEnemy(player, c) then
			ChaosSpell.dropTarget(c, player)
			dropped[c:getId()] = true
		end
	end
	if left > 0 then
		addEvent(pulse, cfg.stealth.pulseMs, playerId, left - cfg.stealth.pulseMs, dropped)
	else
		addEvent(pulse, cfg.stealth.pulseMs, playerId, 0, dropped) -- one more pulse sees the veil gone
	end
end

function onCastSpell(creature, variant, isHotkey)
	local player = creature:getPlayer()
	if not player then
		return false
	end
	local cfg = Chaos.classes
	local c = Condition(CONDITION_INVISIBLE, CONDITIONID_COMBAT)
	c:setParameter(CONDITION_PARAM_SUBID, cfg.subId.stealth)
	c:setParameter(CONDITION_PARAM_TICKS, cfg.stealth.durationMs)
	player:addCondition(c)
	ChaosSpell.vfxOr(player:getPosition(), "shade_vanish", "shadow_smoke", CONST_ME_POFF)
	pulse(player:getId(), cfg.stealth.durationMs, {})
	return true
end
