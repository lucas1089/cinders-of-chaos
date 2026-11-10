-- Critical hit caps (O471, owner 2026-11-10): a character's critical chance is at most 45 points and the extra damage of its
-- critical hits at most 150 percent, every source together (gear, gems, passive tree, Paragon, blessings, buffs). The numbers and
-- the maths are in data/lib/chaos_item_mods.lua (config.crit, M.critTotals, M.critKeep, M.critFactor, M.critHit); this file only
-- reads the engine's totals and puts the maths on the hit. Overview: server/README.md "Critical, rune and penetration ceilings (O471)".
--
-- Why on the hit: the engine adds the critical chance and amount of ALL conditions and item attributes in its own
-- Player::getSpecialSkill and rolls the crit in combat.cpp (engine patch 0004), before any Lua event; a script has no say in the
-- sum. onHealthChange gets the damage the crit already raised and the `critical` flag (engine patch 0001), so a critical hit of
-- a player whose totals are over a cap is cut to what the cap allows:
--   chance above 45: the hit stays critical with probability 45 / chance, else the crit is taken off (its whole extra goes)
--   amount above 150: the extra of a crit that stays is 150, not the amount
-- A scripted crit (Keen Edge in supports.lua, Critical Strike with Bows in weapon_styles.lua) is no engine crit; those two ask
-- ChaosItemMods.critRoom how much chance the cap leaves them.
-- The event goes on a target from the onTargetCombat callback below, only while the attacker is over a cap (a monster that was
-- hit before the totals rose gets it at the next hit); a player target (PvP) gets it the same way. Hits of conditions are never
-- critical (patch 0004), summons have no critical totals of their own.
-- Lua 5.1 / LuaJIT and 5.3.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end

ChaosCritCap = ChaosCritCap or {}
local K = ChaosCritCap

-- the engine's totals of a player: chance, amount (nil, nil without the binding)
function K.engineTotals(player)
	if not player or not player.getSpecialSkill or not SPECIALSKILL_CRITICALHITCHANCE then
		return nil, nil
	end
	local ok, chance, amount = pcall(function()
		return player:getSpecialSkill(SPECIALSKILL_CRITICALHITCHANCE), player:getSpecialSkill(SPECIALSKILL_CRITICALHITAMOUNT)
	end)
	if not ok then
		return nil, nil
	end
	return tonumber(chance), tonumber(amount)
end

-- true when a player is over a cap (the event is worth putting on a target)
function K.over(player)
	local M = ChaosItemMods
	if not M then
		return false
	end
	local chance, amount = K.engineTotals(player)
	if not chance then
		return false
	end
	local t = M.critTotals(chance, amount)
	return t.chanceCapped or t.amountCapped
end

-- the hit of a player, the damages in, the damages out
function K.onHit(attacker, primaryDamage, secondaryDamage, critical, rand)
	local M = ChaosItemMods
	if critical ~= true or not M or not attacker or not attacker:isPlayer() then
		return primaryDamage, secondaryDamage
	end
	local chance, amount = K.engineTotals(attacker)
	if not chance then
		return primaryDamage, secondaryDamage
	end
	local p, s, state = M.critHit(primaryDamage, secondaryDamage, chance, amount, rand)
	K.last = state
	return p, s
end

local hit = CreatureEvent("ChaosCritCap")
function hit.onHealthChange(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType, origin, critical)
	if critical == true and primaryType ~= COMBAT_HEALING then
		local ok, p, s = pcall(K.onHit, attacker, primaryDamage, secondaryDamage, critical)
		if ok then
			primaryDamage, secondaryDamage = p, s
		end
	end
	return primaryDamage, primaryType, secondaryDamage, secondaryType
end
hit:register()

local targetCb = EventCallback
targetCb.onTargetCombat = function(creature, target)
	if creature and target and creature:isPlayer() and not (Chaos.eventKnown and Chaos.eventKnown(target, "ChaosCritCap"))
			and K.over(creature) then
		Chaos.registerOnce(target, "ChaosCritCap")
	end
	return RETURNVALUE_NOERROR
end
targetCb:register()
