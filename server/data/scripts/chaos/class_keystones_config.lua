-- class_keystones_config.lua: the numbers of the signature keystones of the Thief, Necromancer, Monk and Templar lines
-- on the passive tree's nodes 621 (Wrath) and 624 (Resolve) (owner, 2026-10-20: "excellent nodes like Ricochet and
-- Deadeye for all classes"). Pure data; rules in class_keystones_core.lua, engine glue in passivetree_keystones.lua.
--
-- Each one is a per-class variant of 621 / 624 (client treedata/nodes.lua, the variant key is the class key:
-- ChaosClasses.keystoneKey), like Ricochet and Deadeye are the Ranger's. Every one changes how the class fights in
-- every fight (a second strike, a chain, an explosion, a finisher) and has a price. The client tooltips repeat these
-- numbers; server/tests/class_keystones_test.lua checks that they match.
-- Computed balance against Ricochet and Deadeye (not measured in game): server/data/spells/README.md "Signature
-- keystones of the Thief, Necromancer, Monk and Templar lines" (ChaosClassKeystones.model).

ChaosClassKeystonesConfig = {
	-- which class gets which keystone on which node (the variant keys of 621 / 624; the generator writes them to `v`)
	variants = {
		[621] = {thief = "ksShadowTwin", ninja = "ksShadowTwin", samurai = "ksShadowTwin",
			necromancer = "ksCorpseBlast", lich = "ksCorpseBlast", bonelord = "ksCorpseBlast",
			monk = "ksSeventhPalm", shadowfist = "ksSeventhPalm",
			templar = "ksRadiantRebuke", inquisitor = "ksRadiantRebuke", sentinel = "ksRadiantRebuke"},
		[624] = {thief = "ksViperVerdict", ninja = "ksViperVerdict", samurai = "ksViperVerdict",
			necromancer = "ksReapersToll", lich = "ksReapersToll", bonelord = "ksReapersToll",
			monk = "ksPiercingPalm", shadowfist = "ksPiercingPalm", ironsage = "ksPiercingPalm",
			templar = "ksDawnchain", inquisitor = "ksDawnchain"},
	},

	-- Shadow Twin (Thief line, 621): a melee or ranged weapon hit has `chance` percent to be struck again by your shadow
	-- delayMs later on the same target for `percent` of the hit (its damage type). Price: damage you take x (1 + taken).
	ksShadowTwin = {chance = 30, percent = 0.60, delayMs = 300, taken = 0.06},

	-- Viper's Verdict (Thief line, 624): a melee or ranged weapon hit on a poisoned target has `chance` percent to strike a
	-- vital: x multiplier. Price: weapon hits on a target that is not poisoned x price.
	ksViperVerdict = {chance = 20, multiplier = 2.0, price = 0.85},

	-- Corpse Detonation (Necromancer line, 621): a monster killed by you or your minions explodes: `percent` of its
	-- maximum health (at most perLevel x your level) as death damage to up to maxTargets other enemies within `radius`.
	-- An explosion's kills do not explode. Price: the hits of you and your minions x price.
	ksCorpseBlast = {percent = 0.12, perLevel = 15, radius = 2, maxTargets = 6, price = 0.92},

	-- Reaper's Toll (Necromancer line, 624): the hits of you and your minions on a monster at or below `below` of its
	-- maximum health x (1 + bonus) (a scythe on the first one); on a monster above it x price. Not damage over time.
	ksReapersToll = {below = 0.40, bonus = 1.0, price = 0.92},

	-- Seventh Palm (Monk line, 621): every `every`th melee hit (fist or weapon; the count starts over after windowMs
	-- without one) is a finisher: x finisher, and a shockwave hits up to maxTargets other enemies within 1 sqm of the
	-- target for shockShare of the finisher. Price: the other melee hits x price.
	ksSeventhPalm = {every = 5, windowMs = 4000, finisher = 2.2, shockShare = 0.50, maxTargets = 4, price = 0.90},

	-- Piercing Palm (Monk line, 624): a melee hit (fist or weapon) passes through: the nearest other enemy next to the
	-- target and farther from you takes `first` of the hit, the next one behind that `second`. Price: the hit x price.
	ksPiercingPalm = {first = 0.70, second = 0.40, price = 0.95, delayMs = 100},

	-- Radiant Rebuke (Templar line, 621): with a shield, a melee or ranged hit taken has blockChance percent to be blocked
	-- completely; a block releases a holy nova (at most one every icdMs): up to maxTargets enemies within `radius` take
	-- `share` of the blocked hit + perMagicLevel x your magic level. Price: your weapon hits x price.
	ksRadiantRebuke = {blockChance = 20, share = 1.0, perMagicLevel = 4, radius = 2, maxTargets = 8, icdMs = 1000,
		price = 0.90},

	-- Dawnchain (Templar line, 624): a melee weapon hit sends a chain of light: holy damage to the nearest other enemy
	-- within `range` sqm (in sight) for `percent` of the hit, then from there once more for `percent` of that; never the
	-- same target twice. Price: your spells x spellPrice.
	ksDawnchain = {percent = 0.55, falloff = 0.55, bounces = 2, range = 3, delay = 120, spellPrice = 0.90},
}

return ChaosClassKeystonesConfig
