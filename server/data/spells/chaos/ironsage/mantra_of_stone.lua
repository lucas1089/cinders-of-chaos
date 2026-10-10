-- Mantra of Stone: chant for 12 s; you and party members within 6 sqm take 8% less damage while they stay near, and
-- every pulse (2 s) heals them for level x 1 + fist x 24 (the Iron Sage's party heal, ChaosMonk.cfg.mantra.heal).
--
-- The aura pulses every 2 s: everyone in reach gets a 3 s timer condition (ChaosMonk.ids.subId.mantra) that
-- data/scripts/chaos/monk_combat.lua reads on damage taken. Uses no chi. Stops when the Sage dies or logs out.
dofile('data/spells/scripts/chaos/_monk.lua')

local function pulse(caster, step)
	local M = ChaosMonk
	local pos = caster:getPosition()
	-- Deep Mantra (the passive tree, class_tree.lua): its own, stronger timer
	local sub = ChaosClassTree.has(caster, "ctDeepMantra") and M.ids.subId.mantraDeep or M.ids.subId.mantra
	local heal = M.mantraHeal(caster:getLevel(), caster:getEffectiveSkillLevel(SKILL_FIST))
	for _, c in ipairs(ChaosSpell.alliesAround(caster, pos, M.cfg.mantra.radius, false)) do
		if c:isPlayer() then
			MonkSpell.timer(c, sub, M.cfg.mantra.pulseMs + 1000)
			if heal > 0 and c:getHealth() > 0 and c:getHealth() < c:getMaxHealth() then
				ChaosSpell.healTarget(caster, c, heal, heal, CONST_ME_NONE)
			end
		end
	end
	ChaosSpell.vfxOr(pos, "stone_rise", "arcane_aura", CONST_ME_YELLOW_RINGS)
	return true
end

function onCastSpell(creature, variant, isHotkey)
	local player = creature:getPlayer()
	if not player then
		return false
	end
	local m = ChaosMonk.cfg.mantra
	ChaosSpell.pulse(player:getId(), math.floor(m.durationMs / m.pulseMs), m.pulseMs, pulse)
	return true
end
