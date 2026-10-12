-- Vigil of Wrath: switches the vigil on or off. While on it reserves 35% of your maximum mana, and you and your party
-- members within 5 sqm deal 5% more damage (not on top of Inspiring Illusion: the stronger counts).
-- Rules: data/scripts/chaos/vigils_core.lua; the reservation and the party: vigils.lua.
dofile('data/spells/scripts/chaos/_common.lua')
dofile('data/spells/scripts/chaos/_vigils.lua')

function onCastSpell(creature, variant, isHotkey)
	return ChaosVigilSpell.toggle(creature, "wrath")
end
