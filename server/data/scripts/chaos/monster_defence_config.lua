-- monster_defence_config.lua: how a monster defends against a player (monster_defence.lua, monster_defence_core.lua).
-- Plain table, loaded as Chaos.monsterDefence = dofile("data/scripts/chaos/monster_defence_config.lua").
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible. Edit here, then /reload scripts (or restart). server/README.md "Monster defence (O462)".
-- The numbers that the player stage shares (armour factor, the three caps) are in defence_config.lua, not here.
return {
	enabled = true,

	-- The median class hit by monster level: the size of the hit that armour is measured against (percent of it removed
	-- by the armour of a monster, see armourTarget). Rows {level, hit}, a straight line in the logarithm of both
	-- between two rows, the slope of the last two rows beyond the ends. DERIVED, do not edit by hand:
	-- python3 -I server/tools/defence_curve.py --lua prints the rows, --check compares them (CI). The method: the median
	-- over the 21 classes of the damage weighted mean hit (weapon hit = dps x auto share x attack interval, spell hit =
	-- dps x (1 - auto share) x 2 s) from class_dps_model.py.
	-- O475 (2026-11-10): regenerated for the damage of the balance round (class_dps_model.py after O472 to O474: median hit 7169 -> 9993
	-- at 1000, 576 -> 464 at 100, 3645 -> 3658 at 500; the pool takes back what the weapon growth gives at low levels).
	hitCurve = {
		{level = 1, hit = 4},
		{level = 10, hit = 41},
		{level = 30, hit = 133},
		{level = 60, hit = 279},
		{level = 100, hit = 464},
		{level = 200, hit = 1138},
		{level = 300, hit = 1816},
		{level = 500, hit = 3658},
		{level = 750, hit = 5971},
		{level = 1000, hit = 9993},
		{level = 1500, hit = 14449},
		{level = 2000, hit = 20053},
		{level = 2500, hit = 24884}
	},

	-- percent of the median class hit of the monster's level that the monster's armour removes. A boss is every kind of
	-- monster the code treats as one (monster_defence.lua isBossLike); the elite ranks are listed below, every other
	-- monster (normal and magic) is "normal".
	armourTarget = {normal = 25, elite = 40, boss = 50},
	eliteRanks = {rare = true, legendary = true, nemesis = true},

	-- armour value A of one monster type, by lower case type name, instead of the one computed from level and rank
	armourOverride = {},

	-- percent added to the element resistance of the elite ranks (before the resistCap of defence_config.lua)
	rankResistBonus = 15,

	-- monster modifiers (monster_tiers.lua ChaosMods; keys and kinds in monster_defence_core.lua C.MOD)
	mods = {
		addedAs = 50,          -- Emberforged, Frostforged, Stormforged: percent of a physical hit added as fire, ice or energy
		physReduction = 50,    -- Plated: percent less physical damage taken
		resist = 75,           -- Resistant: the element resistance of the one element drawn when it is rolled
		crit = {chance = 20, mult = 1.5},  -- Ruthless: chance (percent) and size of a critical hit
		block = {chance = 50}  -- Bulwark: chance (percent) that a weapon hit deals nothing (never a tick, never a spell)
	},
	-- the elements a Resistant monster draws from
	resistElements = {"fire", "ice", "energy", "earth", "death", "holy"},

	-- monster ids kept in memory (level, boss flag, armour); two generations of this many
	cacheSize = 32768
}
