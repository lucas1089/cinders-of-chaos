-- monster_damage_config.lua: the late-game monster damage boost (monster_damage.lua, monster_damage_core.lua).
-- Plain table, loaded as Chaos.monsterDamage = dofile("data/scripts/chaos/monster_damage_config.lua").
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible. Edit here, then /reload scripts (or restart). tools/armor_sim.py reads the
-- points from this file. See server/README.md "Percent armour" (Late-game damage boost).
--
-- Why: the percent armour (engine patch 0016) cuts a share of every physical hit, where the stock formula took a flat
-- amount that hardly mattered against late-game hits; the late game (tuned for the stock armour) got 7-16% easier.
-- This gives the physical damage of high-level monsters to players back. Elemental damage is unchanged: armour never
-- reduced a monster's elemental spells (the engine sets blockArmor only on melee and physical spells).
return {
	enabled = true,

	-- percent more PHYSICAL damage to players by the attacking monster's level, linear between the points, flat beyond
	-- the ends (below the first point: the first point's percent, 0). The level is Monster:getMonsterLevel() for a
	-- level-scaled monster, else its hunting level (bounty_pool.lua / the experience and health estimate, the same as
	-- ChaosLoot.monsterLevel); an invader counts at least at its invasion area's level.
	points = {
		{level = 150, percent = 0},
		{level = 300, percent = 14},
		{level = 650, percent = 30},
	},

	-- also scale the elemental part of a hit (false: physical only, the share that armour reduces)
	elemental = false,

	-- the hit taken by the mana shield (utamo vita) is scaled as well (onManaChange), so mana shield users are not spared
	manaShield = true,

	-- monster levels kept in memory (per generation; at most twice this many). Above the monsters that fight players at
	-- once: pack combat (pace.lua) keeps ~100k monsters alive
	levelCacheSize = 32768
}
