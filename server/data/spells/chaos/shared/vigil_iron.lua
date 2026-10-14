-- Vigil of Iron: switches the vigil on or off. While on it reserves 35% of your maximum mana, and you and your party
-- members within 5 sqm take 6% less damage (not on top of the Templar line's defence aura: the stronger counts).
-- Rules: data/scripts/chaos/vigils_core.lua; the reservation and the party: vigils.lua.
dofile('data/spells/scripts/chaos/_common.lua')
dofile('data/spells/scripts/chaos/_vigils.lua')

function onCastSpell(creature, variant, isHotkey)
	return ChaosVigilSpell.toggle(creature, "iron")
end
