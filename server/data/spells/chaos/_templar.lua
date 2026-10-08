-- Shared helpers of the Templar line's spells (templar/ inquisitor/ sentinel/; docs/CLASSES.md).
-- Loaded by every Templar spell with: dofile('data/spells/scripts/chaos/_templar.lua')
-- Ids, numbers and rules: data/scripts/chaos/templar_aura_core.lua (ChaosTemplar), loaded here into the spell Lua
-- state. The buffs and marks are timer conditions (ChaosTemplar.cfg.ids.subId), the state data/scripts/chaos/
-- templar_combat.lua sees.
dofile('data/spells/scripts/chaos/_common.lua')
if not ChaosTemplar then
	dofile('data/scripts/chaos/templar_aura_core.lua')
end
if TemplarSpell then
	return
end

TemplarSpell = {}
local T = ChaosTemplar

-- skill x attack of a Templar strike: the best of sword, club and axe skill x the main-hand melee weapon's attack
-- (never below 20, an empty hand)
function TemplarSpell.power(player)
	return player:getEffectiveSkillLevel(ChaosSpell.bestMeleeSkill(player)) * ChaosSpell.meleeAttack(player)
end

-- positive min, max of a holy strike (ChaosTemplar.strikeValues, level factor included)
function TemplarSpell.values(player, pMin, pMax, mMin, mMax, baseMin, baseMax)
	return T.strikeValues(player:getLevel(), TemplarSpell.power(player), player:getMagicLevel(), pMin, pMax, mMin,
		mMax, baseMin, baseMax)
end

-- a holy strike on one target, with the PvP rules of ChaosSpell.canAttack
function TemplarSpell.holyStrike(player, target, min, max, effect)
	if not ChaosSpell.canAttack(player, target) then
		return false
	end
	-- the target gets the class event, so Judgement and Zealotry see the hit
	target:registerEvent("ChaosTemplarCombat")
	return doTargetCombat(player, target, COMBAT_HOLYDAMAGE, -math.floor(min), -math.floor(max), effect or
		CONST_ME_HOLYDAMAGE, ORIGIN_SPELL)
end

-- a timer condition (CONDITION_ATTRIBUTES without attributes) with a sub id
function TemplarSpell.addTimer(creature, subId, ticks)
	local c = Condition(CONDITION_ATTRIBUTES, CONDITIONID_COMBAT)
	c:setParameter(CONDITION_PARAM_SUBID, subId)
	c:setParameter(CONDITION_PARAM_TICKS, ticks)
	creature:addCondition(c)
end

function TemplarSpell.hasTimer(creature, subId)
	return creature:getCondition(CONDITION_ATTRIBUTES, CONDITIONID_COMBAT, subId) ~= nil
end

-- a shield in either hand
function TemplarSpell.hasShield(player)
	for _, slot in ipairs({CONST_SLOT_LEFT, CONST_SLOT_RIGHT}) do
		local item = player:getSlotItem(slot)
		if item and ItemType(item:getId()):getWeaponType() == WEAPON_SHIELD then
			return true
		end
	end
	return false
end

-- the string parameter of a spell with params="1" ("" without one)
function TemplarSpell.param(variant)
	local s = variant and (variant.string or (variant.getString and variant:getString())) or ""
	return (tostring(s):gsub('^%s*"?', ''):gsub('"?%s*$', ''))
end
