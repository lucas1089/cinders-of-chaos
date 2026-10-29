-- Death Between Heartbeats: the shortest wait in the world: a melee blade strike that crits a target above half health.

-- One of the attack kit's spells (data/scripts/chaos/attack_kit_config.lua, key deathbetweenheartbeats): the numbers, the shape and
-- the effects are there, the cast is data/spells/chaos/_attackkit.lua. A line spell quest ultimate (quest 3, level 1200):
-- needlearn, taught by the quest, a long cooldown, and no slot in the helper's rotation of 5.
dofile('data/spells/scripts/chaos/_attackkit.lua')

function onCastSpell(creature, variant, isHotkey)
	return AttackKit.cast('deathbetweenheartbeats', creature, variant)
end
