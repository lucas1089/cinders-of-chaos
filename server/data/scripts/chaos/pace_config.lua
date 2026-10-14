-- Pack combat ("pace", pace.lua, pace_core.lua; server/README.md "Pack combat (pace)"): every number. Plain table, loaded
-- with
--     ChaosPaceConfig = dofile("data/scripts/chaos/pace_config.lua")
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible. Edit here, then restart (or /reload scripts).
--
-- Owner request 2026-10-14: players feel strong and kill packs, not one monster at a time. Monsters have less health
-- and come in bigger packs (the spawn side: tools/spawn_tuning.json, tools/spawn_density.json, areagen_config.lua);
-- experience and loot per kill drop by the kill ratio, so experience and gold per hour stay on the leveling model.
--
-- Pace level of a monster = its hunting level: Monster:getMonsterLevel() for a level-scaled monster, the spawn point's
-- level for a generated area or dungeon monster (areagen.lua), else baseLevelMult x ChaosLoot.monsterLevel (the
-- bounty pool's "fair hunt" estimate; README "Level bands and capacity": the hunting level is twice it).
-- Curves are linear between the points and flat beyond the ends. A monster with a level of its own (level-scaled, or a
-- generated area's point) uses the "scaled" curves: those monsters carry the engine's x(1 + 0.0074 L) health.
--
-- What it touches: natural map spawns, generated areas and dungeons, base dungeon monsters (dungeons.lua) and the ambush
-- copies of those. Never: bosses (isboss / rewardboss / the tier list's bosses / a generated area's boss), summons,
-- and the instanced modes with their own clear model (rifts, the Ember Descent, the tower, invasions, arena,
-- battleground, the raid, world and guild bosses, Ascended Omens): those create their monsters from scripts and are
-- not marked. PvP is never touched: every factor is on monsters or on monster kills.
return {
	-- false: the whole layer is off (health, experience, loot, damage, ambush and goblin chances, kill goals, multikill)
	enabled = true,

	-- hunting level of a monster without a level of its own = this x ChaosLoot.monsterLevel
	baseLevelMult = 2,

	-- base monsters, by hunting level. health: max health x; xp: experience per kill x (the multikill bonus below comes
	-- on top; the curve is already divided by 1.30, the median pack's bonus); loot: loot per kill x (stock loot thinned,
	-- Chaos rolls, currency, gems, supports, uniques, ambush and goblin chances); goal: kill-count goals x (bounties,
	-- bestiary, the season pass, achievements and journey kill counts)
	base = {
		health = {{20, 1.00}, {35, 0.60}, {60, 0.50}, {100, 0.36}, {175, 0.26}, {250, 0.21}},
		xp = {{20, 1.00}, {35, 0.50}, {60, 0.46}, {100, 0.32}, {175, 0.22}, {250, 0.17}, {450, 0.17}, {600, 0.16},
			{800, 0.16}, {1000, 0.17}},
		loot = {{20, 1.00}, {35, 0.59}, {60, 0.54}, {100, 0.37}, {175, 0.27}, {250, 0.20}, {450, 0.20}, {600, 0.19},
			{800, 0.19}, {1000, 0.20}},
		goal = {{20, 1.0}, {35, 1.7}, {60, 1.8}, {100, 2.7}, {175, 3.8}, {250, 5.0}}
	},

	-- level-scaled Chaos monsters and generated area / dungeon monsters, by level (about 1.8x bulkier than a base monster
	-- of the same hunting level after the curve, as before it)
	scaled = {
		health = {{650, 0.095}, {800, 0.080}, {1000, 0.066}, {1300, 0.062}, {1600, 0.059}, {2000, 0.056}},
		xp = {{650, 0.042}, {800, 0.036}, {1000, 0.030}, {1300, 0.026}, {1600, 0.024}, {2000, 0.023}},
		loot = {{650, 0.050}, {800, 0.042}, {1000, 0.035}, {1300, 0.031}, {1600, 0.029}, {2000, 0.027}},
		goal = {{650, 20}, {800, 24}, {1000, 28}, {1300, 32}, {1600, 35}, {2000, 37}}
	},

	-- calibration: every point of the experience and loot curves x this (at most 1 per kill). The curves come from the
	-- pack model; the live check of 2026-10-14 (a scripted hunter, server/README.md "Pack combat (pace)") measured
	-- experience per hour at 0.61-0.85 of the unpaced hunt. Set from the hunt tracker in the beta (1.3 brings the
	-- measured Elementalist to about 0.8-0.85, the Thief to 1.1).
	scale = {xp = 1.3, loot = 1.2}, -- calibrated on the live check of 2026-10-14 (XP/h 0.61-0.85, gold/h 0.49-1.22 of unpaced at 1.0); recheck with the beta hunt tracker

	-- damage to players by a paced monster (all elements, conditions and mana shield hits included), by its hunting
	-- level; the late-game physical boost (monster_damage_config.lua) stays on top. Bosses and player summons: never.
	damage = {{20, 1.00}, {50, 0.85}, {150, 0.75}, {300, 0.65}, {600, 0.55}, {800, 0.45}, {1000, 0.40}},

	-- multikill: kills of one player, each within windowMs of the one before, form a chain. The experience of the whole
	-- chain gets the bonus of its length (percent): the kill that reaches a step also pays the step's difference on the
	-- chain's earlier kills. Monster kills only; it counts against the experience cap (xpcap_config.lua) like any bonus.
	multikill = {
		enabled = true,
		windowMs = 3000,
		steps = {{kills = 4, percent = 10}, {kills = 6, percent = 20}, {kills = 8, percent = 30}, {kills = 9, percent = 40}},
		-- a text message to the player from this many kills in a chain (0: never)
		announceFrom = 6
	},

	-- pack cleave (PvE only): the classes with little area damage (data/spells/README.md C4, area share under ~30%) hit
	-- packs too. A direct hit of such a character (melee, ranged, spell; not damage over time) on a paced monster also
	-- deals `percent` of it to up to `targets` other monsters within `radius` sqm of that monster (nearest first; never a
	-- boss, a player's summon or a player). By vocation id (chaos_constants.lua Chaos.classes.ids). Model and numbers:
	-- server/README.md "Pack combat (pace)", class spread.
	cleave = {
		enabled = true,
		radius = 1,
		byVocation = {
			[7] = {percent = 20, targets = 2}, -- Deadeye (area share 15%)
			[18] = {percent = 20, targets = 2}, -- Shadowfist (7%)
			[11] = {percent = 25, targets = 3}, -- Thief (0%)
			[13] = {percent = 25, targets = 3}, -- Samurai (0%)
			[20] = {percent = 25, targets = 3}, -- Necromancer (1%)
			[17] = {percent = 20, targets = 3}, -- Monk (17%)
			[19] = {percent = 20, targets = 3}, -- Iron Sage (17%)
			[12] = {percent = 15, targets = 2} -- Ninja (30%)
		}
	},

	-- lowercase type names that are never paced (in addition to bosses and summons)
	skip = {},

	-- empty corpses decay after this many seconds (0: the stock decay). More kills leave more corpses.
	emptyCorpseSeconds = 30
}
