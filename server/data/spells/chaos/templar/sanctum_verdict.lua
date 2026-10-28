-- Sanctum Verdict: the sanctum passes sentence: one very heavy holy hit on one target within 2 sqm.
--
-- One of the attack kit's spells (data/scripts/chaos/attack_kit_config.lua, key sanctumverdict): the numbers, the shape and
-- the effects are there, the cast is data/spells/chaos/_attackkit.lua.
dofile('data/spells/scripts/chaos/_attackkit.lua')

function onCastSpell(creature, variant, isHotkey)
	return AttackKit.cast('sanctumverdict', creature, variant)
end
