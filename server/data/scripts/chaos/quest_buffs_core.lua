-- quest_buffs_core.lua: the rules of the seven level 800 buffs of the line spell quests that no engine condition parameter can
-- express (numbers: quest_buffs_config.lua; tests: server/tests/quest_buffs_test.lua). The skill and critical parts of Ironbound
-- Oath, Unblinking Gaze, Veil of Whispers and Shroud of Knives are plain condition parameters set by the spell. What lives here:
--   * evasion        Shroud of Knives and Lotus Stance add evasion to the Thief and the Monk line's dodge chance
--   * chi            Lotus Stance: one more chi on a weapon or fist hit
--   * minions, death Dirge of the Legion: the minions' hit and the death spells (ChaosPassiveDealt in passivetree_effects.lua)
--   * mantle         Mantle of Dawn: less damage taken, a stronger Radiant Strike (templar_combat.lua)
-- A buff is on when the caster carries the condition with its sub id. `has` is the only function that asks the engine.
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.
if not ChaosQuestBuffsConfig then
	dofile("data/scripts/chaos/quest_buffs_config.lua")
end

ChaosQuestBuffs = ChaosQuestBuffs or {}
local Q = ChaosQuestBuffs

function Q.cfg()
	return ChaosQuestBuffsConfig
end

-- is the buff `key` (oath, gaze, veil, knives, dirge, lotus, mantle) up on the creature
function Q.has(creature, key)
	local sub = Q.cfg().subId[key]
	if not sub or not creature or not creature.getCondition then
		return false
	end
	return creature:getCondition(CONDITION_ATTRIBUTES, CONDITIONID_COMBAT, sub) ~= nil
end

-- evasion added to a dodge chance (a chance, 0.10 = 10 points) by the buffs that are up
function Q.evadeBonus(player)
	local c = Q.cfg()
	local extra = 0
	if Q.has(player, "knives") then
		extra = extra + c.knives.evade
	end
	if Q.has(player, "lotus") then
		extra = extra + c.lotus.evade
	end
	return extra
end

-- the chi a weapon or fist hit gives: the base plus Lotus Stance's
function Q.chiPerHit(base, lotus)
	return (base or 0) + (lotus and Q.cfg().lotus.chi or 0)
end

-- the bonus (0.25 = +25%) on the Necromancer's minion hits while Dirge of the Legion lasts
function Q.minionBonus(dirge)
	return dirge and Q.cfg().dirge.minion or 0
end

-- the factor on one damage value of a player under Dirge of the Legion: death damage of a spell (origin = the engine's
-- ORIGIN_SPELL) that is the character's own spell, not a minion hit or a proc (`guarded`: inside ChaosSpellFactor.guard or a
-- keystone proc). Everything else 1.
function Q.deathFactor(dirge, combatType, deathType, origin, spellOrigin, guarded)
	if not dirge or guarded or combatType ~= deathType or origin ~= spellOrigin then
		return 1
	end
	return 1 + Q.cfg().dirge.death
end

-- the factor on damage a player takes under Mantle of Dawn
function Q.takenFactor(mantle)
	return mantle and (1 - Q.cfg().mantle.taken) or 1
end

-- the factor on the Radiant Strike (the holy strike after a melee hit) under Mantle of Dawn
function Q.holyFactor(mantle)
	return mantle and (1 + Q.cfg().mantle.holy) or 1
end

-- Veil of Whispers: the mana every regeneration tick gives
function Q.manaTick(maxMana)
	local v = Q.cfg().veil
	return math.max(v.minMana, math.floor((maxMana or 0) * v.manaPct + 0.5))
end

return Q
