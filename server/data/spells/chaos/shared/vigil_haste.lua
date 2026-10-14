-- Vigil of Haste: switches the vigil on or off. While on it reserves 20% of your maximum mana, and you and your party
-- members within 5 sqm move 15% faster.
-- Rules: data/scripts/chaos/vigils_core.lua; the reservation and the party: vigils.lua.
dofile('data/spells/scripts/chaos/_common.lua')
dofile('data/spells/scripts/chaos/_vigils.lua')

function onCastSpell(creature, variant, isHotkey)
	return ChaosVigilSpell.toggle(creature, "haste")
end
