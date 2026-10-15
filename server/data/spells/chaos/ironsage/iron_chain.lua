-- Iron Chain: hurl a chain of iron at your target; it links on to up to 4 more monsters close by.
--
-- The Iron Sage's pack strike (level 150, range 4): the target, then each link to the nearest monster within 2 sqm of
-- the last one hit, none twice, a Monk strike each. Players are only hit when they are the target. Numbers and rules:
-- _packtools.lua.
dofile('data/spells/scripts/chaos/_monk.lua')
dofile('data/spells/scripts/chaos/_packtools.lua')

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
	ChaosPackTools.jumpStrike(player, target, "chain", "lightning_orb", CONST_ANI_ENERGY, "stone_rise", CONST_ME_BLOCKHIT)
	return true
end
