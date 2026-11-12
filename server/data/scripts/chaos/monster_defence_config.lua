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

	-- The median WEAPON hit by monster level (O501): the size of the hit that armour is measured against for a melee or ranged
	-- weapon hit (a spell keeps hitCurve). In the units that ARRIVE at the layer: the engine's roll of the physical part of the
	-- auto attack of the tier weapon of the level, at the typical skill, after the monster's own flat armour and defence took
	-- their part, the median over the 15 classes with an armoured weapon hit (the casters' wand hit is ORIGIN_WAND: no armour).
	-- The class curve above is the hit of a typical character after its own multipliers, which are later events of the monster
	-- than this layer (class damage, damage pool, weapon style and power, the Monk's unarmed scaling); against it an auto attack lost
	-- 50 to 90% (owner 2026-11-11). DERIVED, do not edit by hand: python3 -I server/tools/defence_curve.py --lua prints the rows,
	-- --check compares them (CI). Same levels as hitCurve.
	-- O505 (2026-11-11): regenerated for the flat armour rule (flatRollCurve, flatShare below, install step monsterflat): the typical hunt
	-- monster keeps a flat armour of a few points instead of 15 at level 20 and 30 at level 100, so more of the roll arrives (82 -> 106 at 100,
	-- 239 -> 297 at 500). A launcher is no longer taken for one that meets the defence (the engine gives it to melee hits only).
	weaponHitCurve = {
		{level = 1, hit = 16},
		{level = 10, hit = 18},
		{level = 30, hit = 32},
		{level = 60, hit = 64},
		{level = 100, hit = 106},
		{level = 200, hit = 160},
		{level = 300, hit = 219},
		{level = 500, hit = 297},
		{level = 750, hit = 413},
		{level = 1000, hit = 622},
		{level = 1500, hit = 744},
		{level = 2000, hit = 900},
		{level = 2500, hit = 944}
	},

	-- The monster's own flat armour and defence (O505; the XML `armor` and `defense` of a monster file, which the engine takes off a weapon
	-- hit before any Lua: Creature::blockHit) are capped at install time by tools/patch_monster_flat_defence.py (install step monsterflat):
	-- for a monster of level L the two together take at most flatShare percent of flatRollCurve at L (the mean the engine takes off:
	-- armour 3/4 of its value, defence 3/4 of its value), normal monsters 10, bosses twice that (the layer sizes a boss's armour at twice
	-- the normal share too). The layer itself does not read these rows at run time: they are the data of the install tool and of the checks
	-- (tools/defence_curve.py G5).
	flatShare = {normal = 10, boss = 20},
	-- the median engine ROLL of the physical part of an auto attack by level, before any armour: the mean of the roll (the engine formula
	-- level / 5 + (skill / 4 + 1) x (attack / 3) x 1.03, a bell from 0 to that maximum) of the typical character with the tier weapon of
	-- the level, median over the 12 armoured classes that are not the fist line (the fist line's hit size is its own, see O505 part 3).
	-- DERIVED, do not edit by hand: python3 -I server/tools/defence_curve.py --lua prints the rows, --check compares them (CI). Same levels.
	flatRollCurve = {
		{level = 1, hit = 18},
		{level = 10, hit = 20},
		{level = 30, hit = 35},
		{level = 60, hit = 70},
		{level = 100, hit = 118},
		{level = 200, hit = 178},
		{level = 300, hit = 243},
		{level = 500, hit = 330},
		{level = 750, hit = 458},
		{level = 1000, hit = 690},
		{level = 1500, hit = 825},
		{level = 2000, hit = 1000},
		{level = 2500, hit = 1050}
	},

	-- the vocation ids of the casting classes (Mystic, Elementalist, Illusionist, Necromancer, Lich, Bone Lord; docs/CLASSES.md): their
	-- magic level IS their skill and their spells are sized by the class curve above. Every other class is a weapon class: a spell hit it
	-- deals itself (inside its own cast) is a weapon-size hit and meets the weapon armour of weaponHitCurve like an auto attack (O505,
	-- monster_defence_core.lua C.weaponSpellHit). tools/defence_curve.py --check holds this list to rotation_sim.py CLASS_KIND.
	casterVocations = {1, 5, 10, 20, 21, 22},

	-- percent of the median class hit (a spell) or of the median weapon hit (a weapon hit) of the monster's level that the monster's
	-- armour removes. A boss is every kind of monster the code treats as one (monster_defence.lua isBossLike); the elite ranks are
	-- listed below, every other monster (normal and magic) is "normal".
	armourTarget = {normal = 25, elite = 40, boss = 50},
	-- the same for a weapon hit (O501, percent of the median weapon hit): a little above armourTarget, because the hits of one weapon roll
	-- between 0 and twice their mean, the cap holds the small ones and the big ones lose less, so the armour removes its armourTarget of
	-- the DAMAGE of the median class's auto attack (tools/defence_curve.py G1: within 3 points at every level from 8 to 2500)
	weaponTarget = {normal = 27.5, elite = 44.5, boss = 55},
	-- the most of a WEAPON hit that armour may remove, by rank (O501, percent): a small hit or a low roll of the weapon is not erased.
	-- The ceilings of the auto attack of any class: tools/defence_curve.py CEILING (G2). Not for a spell.
	weaponShareCap = {normal = 40, elite = 55, boss = 65},
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
