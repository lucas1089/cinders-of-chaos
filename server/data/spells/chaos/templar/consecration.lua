-- Consecration: hallows the ground under the Templar for 6 seconds. Each second holy damage hits enemies within 2 sqm
-- of the cast tile, and allies standing in it (party, own summons, the Templar) are healed a little.
--
-- Pulse damage: weapon power and magic level like Radiant Smite, much smaller per pulse; allies get
-- ChaosTemplar.cfg.consecration.allyHeal x a pulse. The zone stays where it was cast and ends when the Templar dies or
-- logs out.
dofile('data/spells/scripts/chaos/_templar.lua')

local c = ChaosTemplar.cfg.consecration
local area = createCombatArea(AREA_CIRCLE2X2)

function onCastSpell(creature, variant, isHotkey)
	local player = creature:getPlayer()
	if not player then
		return false
	end
	local p = player:getPosition()
	local center = {x = p.x, y = p.y, z = p.z}
	local min, max = TemplarSpell.values(player, 0.025, 0.04, 0.4, 0.6, 10, 20)
	ChaosSpell.pulse(player:getId(), c.pulses, c.intervalMs, function(caster, step)
		local pos = Position(center)
		ChaosSpell.fx(pos, "holy_cross", CONST_ME_HOLYAREA)
		for _, enemy in ipairs(ChaosSpell.enemiesAround(caster, pos, c.radius)) do
			enemy:registerEvent("ChaosTemplarCombat")
		end
		doAreaCombat(caster, COMBAT_HOLYDAMAGE, pos, area, -math.floor(min), -math.floor(max), Fx("holy_smite", CONST_ME_HOLYDAMAGE))
		for _, ally in ipairs(ChaosSpell.alliesAround(caster, pos, c.radius, true)) do
			ChaosSpell.healTarget(caster, ally, min * c.allyHeal, max * c.allyHeal, Fx("heal_sparkle", CONST_ME_MAGIC_BLUE))
		end
		return true
	end)
	return true
end
