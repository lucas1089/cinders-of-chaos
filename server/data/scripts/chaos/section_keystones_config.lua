-- section_keystones_config.lua: the numbers of the six keystones of the class sections of the Warrior, Ranger and Mystic lines
-- (O449, nodes 679, 682, 689, 692, 699, 702 of the passive tree; docs/CLASSES.md "Class sections", server/README.md "Passive
-- tree: class sections of the Warrior, Ranger and Mystic lines"). Pure data; rules in section_keystones_core.lua, engine glue
-- in passivetree_keystones.lua. The client tooltips (treedata/nodes.lua) repeat these numbers and
-- server/tests/section_keystones_test.lua checks that they match.
--
-- Each one is a thin combination of hooks that exist already: a damage factor on a hit that depends on what stands near the
-- target or the player (Immovable, Hunter's Focus, Viper's Verdict), a bleed (Barbed Quiver), a second strike (Shadow Twin),
-- the wolf factor (Pack Alpha). Every gain has a price, like every other keystone. Sized under the signature keystones
-- (computed, not measured in game: server/data/spells/README.md "Class sections of the Warrior, Ranger and Mystic lines").
-- Wolfbond's numbers are in class_tree.lua (ChaosClassTree.fx.ksWolfbond): the spells' Lua state reads them there.

ChaosSectionKeystonesConfig = {
	-- Unbroken Line (Juggernaut, 679): with a shield, a melee or ranged hit taken deals perEnemy less for each enemy within
	-- radius sqm of you (maxEnemies at most: 8%). Price: your melee and ranged weapon hits x price.
	ksUnbrokenLine = {perEnemy = 0.02, maxEnemies = 4, radius = 1, price = 0.95},

	-- Open Veins (Berserker, 682): a two-handed melee weapon hit makes the target bleed for share x the hit over ticks ticks
	-- of tickMs (a stronger bleed replaces a weaker, the engine's rule: Barbed Quiver's). Price: those hits x price.
	ksOpenVeins = {share = 0.50, ticks = 4, tickMs = 1000, price = 0.92},

	-- Lone Mark (Deadeye, 689): a bow or crossbow hit on a target with no other enemy within radius sqm of it x alone; with
	-- another enemy there x crowd.
	ksLoneMark = {radius = 2, alone = 1.12, crowd = 0.92},

	-- Convergence (Elementalist, 699): an elemental spell hit on a target with `others` or more other enemies within radius
	-- sqm of it x bonus; on a target with none x alone.
	ksConvergence = {radius = 2, others = 2, bonus = 1.12, alone = 0.93},

	-- Phantom Double (Illusionist, 702): a spell hit has chance percent to be struck again delayMs later by your double on
	-- the same target for percent x the hit (at most one every icdMs). Price: your spell hits x price.
	ksPhantomDouble = {chance = 20, percent = 0.60, delayMs = 400, icdMs = 1000, price = 0.95},
}

return ChaosSectionKeystonesConfig
