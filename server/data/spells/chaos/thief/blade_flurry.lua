-- Blade Flurry: spin with your blades and cut every monster next to you.
--
-- The Thief line's area strike (all three classes, level 50): a melee weapon strike on each monster in the 3x3 square
-- around you (other players are never hit). On one target it hits like a Shuriken Toss; its worth is the pack. Each hit
-- crits out of Shadow Veil, carries Poison Blades, rolls the Bushido crit and is followed by the Ninja's off-hand.
-- Numbers and rules: _blades.lua.
dofile('data/spells/scripts/chaos/_common.lua')
dofile('data/spells/scripts/chaos/_blades.lua')

function onCastSpell(creature, variant, isHotkey)
	local player = creature:getPlayer()
	if not player then
		return false
	end
	ChaosBlades.flurry(player, "whirlwind")
	return true
end
