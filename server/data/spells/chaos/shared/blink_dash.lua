-- Flickerdash: dash up to 4 sqm in the facing direction (stops at the first blocked tile) plus 2.5s of speed.
dofile('data/spells/scripts/chaos/_common.lua')

local MAX_STEPS = 4

function onCastSpell(creature, variant, isHotkey)
	local player = creature:getPlayer()
	if not player then
		return false
	end
	local from = player:getPosition()
	local dir = player:getDirection()
	local dest
	for i = 1, MAX_STEPS do
		local p = ChaosSpell.stepPos(from, dir, i)
		if not ChaosSpell.isFreeTile(p) then
			break
		end
		dest = p
	end
	if not dest then
		return ChaosSpell.cancel(player)
	end

	ChaosSpell.fx(from, "shadow_smoke", CONST_ME_POFF)
	player:teleportTo(dest)
	ChaosSpell.fx(dest, "shadow_smoke", CONST_ME_TELEPORT)

	local haste = Condition(CONDITION_HASTE)
	haste:setParameter(CONDITION_PARAM_SUBID, ChaosSpell.SUBID.dash)
	haste:setParameter(CONDITION_PARAM_TICKS, 2500)
	haste:setFormula(0.3, -24, 0.3, -24)
	player:addCondition(haste)
	return true
end
