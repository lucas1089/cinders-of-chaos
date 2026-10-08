-- Mantra of Stone: chant for 12 s; you and party members within 6 sqm take 8% less damage while they stay near.
--
-- The aura pulses every 2 s: everyone in reach gets a 3 s timer condition (ChaosMonk.ids.subId.mantra) that
-- data/scripts/chaos/monk_combat.lua reads on damage taken. Uses no chi. Stops when the Sage dies or logs out.
dofile('data/spells/scripts/chaos/_monk.lua')

local function pulse(caster, step)
	local M = ChaosMonk
	local pos = caster:getPosition()
	for _, c in ipairs(ChaosSpell.alliesAround(caster, pos, M.cfg.mantra.radius, false)) do
		if c:isPlayer() then
			MonkSpell.timer(c, M.ids.subId.mantra, M.cfg.mantra.pulseMs + 1000)
		end
	end
	ChaosSpell.fx(pos, "arcane_aura", CONST_ME_YELLOW_RINGS)
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
