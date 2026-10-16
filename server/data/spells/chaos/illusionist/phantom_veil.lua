-- Wraithshroud: 8s of invisibility plus a speed boost.
dofile('data/spells/scripts/chaos/_common.lua')

function onCastSpell(creature, variant, isHotkey)
	local player = creature:getPlayer()
	if not player then
		return false
	end
	local invis = Condition(CONDITION_INVISIBLE)
	invis:setParameter(CONDITION_PARAM_SUBID, ChaosSpell.SUBID.phantom_veil)
	invis:setParameter(CONDITION_PARAM_TICKS, 8000)
	player:addCondition(invis)

	local haste = Condition(CONDITION_HASTE)
	haste:setParameter(CONDITION_PARAM_SUBID, ChaosSpell.SUBID.phantom_veil + 1000)
	haste:setParameter(CONDITION_PARAM_TICKS, 8000)
	haste:setFormula(0.4, -30, 0.4, -30)
	player:addCondition(haste)

	local pos = player:getPosition()
	-- the shroud alone (the stock blue sparkle on top of it went; server/data/spells/README_FX.md "Mystic line effects")
	if not ChaosSpell.vfx(pos, "shadow_shroud") then
		ChaosSpell.fx(pos, "shadow_smoke", CONST_ME_MORTAREA)
		pos:sendMagicEffect(CONST_ME_MAGIC_BLUE)
	end
	return true
end
