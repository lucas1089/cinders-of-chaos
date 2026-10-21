-- Twin Verdict: two heavy holy strikes at the target 0.6 s apart, each 1.3 times Final Verdict's; +50% against a
-- target below 25% health, checked for each strike. 16 s cooldown (the cooldown ladder, 2026-10-20; was 24 s).
dofile('data/spells/scripts/chaos/_common.lua')

local SCALE = 1.3
local GAP_MS = 600

local function strike(casterId, targetId)
	local player, target = Player(casterId), Creature(targetId)
	if not player or not target or target:getHealth() <= 0 or not ChaosSpell.canAttack(player, target) then
		return
	end
	local dist = player:getEffectiveSkillLevel(SKILL_DISTANCE)
	local power = dist * ChaosSpell.distanceAttack(player)
	local level, ml = player:getLevel() / 5, player:getMagicLevel()
	local min = (level + power * 0.143 + ml * 3 + 60) * SCALE
	local max = (level + power * 0.234 + ml * 5 + 110) * SCALE
	if target:getHealth() < target:getMaxHealth() * 0.25 then
		min, max = min * 1.5, max * 1.5
	end
	ChaosSpell.vshoot(player:getPosition(), target:getPosition(), "holy_spear", "holy_arrow", CONST_ANI_HOLY)
	ChaosSpell.vfx(target:getPosition(), "holy_smite")
	ChaosSpell.damageTarget(player, target, COMBAT_HOLYDAMAGE, min, max, Fx("holy_smite", CONST_ME_HOLYDAMAGE))
end

function onCastSpell(creature, variant, isHotkey)
	local player = creature:getPlayer()
	if not player then
		return false
	end
	local target = ChaosSpell.targetOf(variant)
	if not target or target == player then
		return ChaosSpell.cancel(player, RETURNVALUE_YOUCANONLYUSEITONCREATURES)
	end
	if not ChaosSpell.canAttack(player, target) then
		return ChaosSpell.cancel(player, RETURNVALUE_YOUMAYNOTATTACKTHISPLAYER)
	end
	strike(player:getId(), target:getId())
	addEvent(strike, GAP_MS, player:getId(), target:getId())
	return true
end
