-- Crimson Covenant: sacrifice 15% of max health for mana and +15% magic level for 12 s.
dofile('data/spells/scripts/chaos/_common.lua')
if not ChaosMysticFx then
	pcall(dofile, 'data/lib/chaos_mystic_fx.lua')
end

function onCastSpell(creature, variant, isHotkey)
	local player = creature:getPlayer()
	if not player then
		return false
	end
	local cost = math.floor(player:getMaxHealth() * 0.15)
	if player:getHealth() <= cost + math.floor(player:getMaxHealth() * 0.20) then
		return ChaosSpell.cancel(player, "Your life force is too low for the pact.")
	end

	player:addHealth("undefined", -cost) -- this engine: (damage type, amount); undefined skips the mana shield
	player:addMana(math.floor(cost * 1.5))

	local buff = Condition(CONDITION_ATTRIBUTES)
	buff:setParameter(CONDITION_PARAM_SUBID, ChaosSpell.SUBID.blood_pact)
	buff:setParameter(CONDITION_PARAM_TICKS, 12000)
	buff:setParameter(CONDITION_PARAM_STAT_MAGICPOINTSPERCENT, 115)
	buff:setParameter(CONDITION_PARAM_BUFF_SPELL, true)
	player:addCondition(buff)

	local pos = player:getPosition()
	-- a crimson burst, then the pact circle alone (it was three effects stacked on the caster)
	local M = ChaosMysticFx
	if M and M.send(pos, "px197_crimson") then
		M.later(300, pos, "blood_pact")
		return true
	end
	ChaosSpell.fx(pos, "blood_rune", CONST_ME_DRAWBLOOD)
	ChaosSpell.vfx(pos, "blood_pact")
	pos:sendMagicEffect(CONST_ME_MAGIC_RED)
	return true
end
