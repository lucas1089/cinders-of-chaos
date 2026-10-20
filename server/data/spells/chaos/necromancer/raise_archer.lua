-- Raise Bone Archer: A risen archer joins you: a fragile ranged minion (range 5, physical arrows) that hits harder than a skeleton. One minion per cast. You can have only a few minions of all kinds at once (3 for the Necromancer); at the limit the oldest one crumbles first (no corpse, no loot). Health and hits scale with your level and magic level (necro_config.lua minions.archer); the minion hits the creature you target (data/scripts/chaos/necro_minions.lua).
dofile('data/spells/scripts/chaos/_necro.lua')

function onCastSpell(creature, variant, isHotkey)
	local player = creature:getPlayer()
	if not player then
		return false
	end
	return NecroSpell.summon(player, "archer")
end
