-- vigils_config.lua: the numbers of the vigils, auras that reserve a share of the maximum mana while they are on
-- (docs/BUILDS.md "Vigils", server/README.md "Vigils"). Pure data. Rules: vigils_core.lua (tested by
-- server/tests/vigils_test.lua). Engine glue: vigils.lua (the think, the reservation, the party), the hit rules in
-- archetypes.lua, the four toggle spells (data/spells/chaos/shared/vigil_*.lua, spells_chaos.xml).
--
-- A vigil is switched on and off by its spell; it stays on (logout and death included) until switched off. While on,
-- a share of the maximum mana is reserved: the maximum mana is lowered by it (a condition), so reserved mana can never
-- be spent, not by spells, not by the mana shield, not by the Trials' Mana Ward. A vigil covers its holder and the
-- party members on the same floor within `radius` sqm; two holders' vigils of one kind do not add up (the strongest
-- counts). Computed balance (not measured in game): server/data/spells/README.md "Snares and vigils".

ChaosVigilsConfig = {
	-- player storage: the vigils switched on, a bit each in the order of `list` (chaos_constants.lua Chaos.storage.vigils)
	storage = 7100025,
	thinkMs = 1000, -- the reservation, the party and the effects are refreshed every think
	holdMs = 1500, -- a covered member keeps the effects this long after the last think that saw it in range
	radius = 5,
	maxReserve = 1.0, -- at most the whole maximum mana (or health, Iron Tithe) is reserved

	-- the vigils, in bit order (append only). reserve: the share of the maximum mana. Effects on everyone covered:
	--   wrath: damage dealt +damage (not on top of Inspiring Illusion: the stronger of the two counts)
	--   iron: damage taken -taken (not on top of the Templar line's defence aura: the stronger counts)
	--   haste: speed +speed of the base speed (a haste condition)
	--   clarity: mana +manaShare of the member's maximum mana a second (none under the rift's Parched Veins)
	list = {
		{key = "wrath", name = "Vigil of Wrath", spell = 179, reserve = 0.35, damage = 0.05},
		{key = "iron", name = "Vigil of Iron", spell = 255, reserve = 0.35, taken = 0.06},
		{key = "haste", name = "Vigil of Haste", spell = 161, reserve = 0.20, speed = 0.15},
		{key = "clarity", name = "Vigil of Clarity", spell = 162, reserve = 0.20, manaShare = 0.01},
	},

	-- condition sub ids (CONDITIONID_COMBAT): the reserved mana, the reserved health (Iron Tithe), the haste
	subIds = {mana = 71092, health = 71093, haste = 71094},

	-- Covenant of Vigils (keystone, archetypes_config.lua arVigils): reservation x reserve, radius +radius, the party
	-- (not the holder) gets party x more of every effect; your own damage x ownDamage (archetypes_core.lua hitFactor)
	keystone = {reserve = 0.70, radius = 3, party = 0.20, ownDamage = 0.90},
	-- Iron Tithe (keystone, arIronTithe): the vigils reserve maximum health instead of mana, at healthShare of their
	-- share; they cover you alone, x self stronger
	tithe = {healthShare = 0.60, self = 1.5},

	-- the vigil uniques (archetypes_config.lua uniques)
	-- Choirmaster's Circlet: reservation x reserve. Oathkeeper's Standard: reservation x reserve, radius +radius.
	uniques = {choirmaster = {reserve = 0.85}, oathkeeper = {reserve = 0.90, radius = 2}},

	-- the other party auras the vigils meet (their own configs hold the numbers; the tests check they match):
	-- Inspiring Illusion (passivetree_keystones.lua cfg.inspire: +8% within 8 sqm)
	inspire = {bonus = 0.08, range = 8}
}

return ChaosVigilsConfig
