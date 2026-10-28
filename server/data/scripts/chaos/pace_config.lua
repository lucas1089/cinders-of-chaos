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
-- bounty pool's "fair hunt" estimate; README "Level bands and capacity": the hunting level of a base monster is its pool
-- level since O285, it was twice it).
-- Curves are linear between the points and flat beyond the ends. A monster with a level of its own (level-scaled, or a
-- generated area's point) uses the "scaled" curves: those monsters carry the engine's x(1 + 0.0074 L) health and
-- x0.03 L experience.
--
-- What it touches: natural map spawns, generated areas and dungeons, base dungeon monsters (dungeons.lua) and the ambush
-- copies of those. Never: bosses (isboss / rewardboss / the tier list's bosses / a generated area's boss), summons,
-- and the instanced modes with their own clear model (rifts, the Ember Descent, the tower, invasions, arena,
-- battleground, the raid, world and guild bosses, Ascended Omens): those create their monsters from scripts and are
-- not marked. PvP is never touched: every factor is on monsters or on monster kills.
return {
	-- false: the whole layer is off (health, experience, loot, damage, ambush and goblin chances, kill goals, multikill)
	enabled = true,

	-- hunting level of a monster without a level of its own = this x ChaosLoot.monsterLevel. 1 since 2026-10-28 (owner:
	-- "retire essa regra como um todo"): it was 2 from 2026-10-14, and from 2026-10-27 every shown level was doubled
	-- too, but the planned hunts (tools/areaplan/plans) pick monsters whose pool level is the hunt's band, so a level 474
	-- Waterglow Conjurer of a 450-506 hunt was shown and paced as 948 (O285)
	baseLevelMult = 1,

	-- O285 (2026-10-28, baseLevelMult 1): a base pack at hunting level L is made of pool level L monsters now, they had
	-- pool level L/2. The health, xp, loot, coins and junkKeep points below were re-fitted to what the models measure
	-- (tools/pack_model.py: the median class's pack dies in as long as before; tools/progression_model.lua: the same minutes
	-- per level; tools/loot_model.lua: the same gold per hour, `lootLevel.goldPerHour`): at level 250 health 0.21 -> 0.095,
	-- xp 0.17 -> 0.075, loot 0.20 -> 0.067. The goal points did not change (the kills per hour did not). Under level 10
	-- (health, loot) and 6 (xp) a monster is untouched, as the pool levels under 10 / 5 were. The pool ends at level 657.
	-- base monsters, by hunting level. health: max health x; xp: experience per kill x (the multikill bonus below comes
	-- on top; the curve is already divided by 1.30, the median pack's bonus); loot: loot per kill x (stock loot thinned,
	-- Chaos rolls, currency, gems, supports, uniques, ambush and goblin chances); goal: kill-count goals x (bounties,
	-- bestiary, the season pass, achievements and journey kill counts)
	base = {
		health = {{10, 1.00}, {20, 0.280}, {35, 0.200}, {60, 0.136}, {100, 0.105}, {150, 0.092}, {200, 0.089}, {250, 0.095},
			{300, 0.082}, {350, 0.072}, {400, 0.085}, {450, 0.098}, {500, 0.102}, {550, 0.100}, {600, 0.105}, {650, 0.110}},
		xp = {{6, 1.00}, {10, 0.20}, {20, 0.20}, {35, 0.14}, {50, 0.098}, {60, 0.108}, {100, 0.082}, {175, 0.072},
			{250, 0.075}, {350, 0.068}, {450, 0.060}, {600, 0.066}},
		loot = {{10, 1}, {50, 0.04722}, {100, 0.09142}, {150, 0.1162}, {200, 0.1589}, {250, 0.2125}, {300, 0.2898},
			{350, 0.06753}, {400, 0.03169}, {450, 0.07779}, {500, 0.08933}, {550, 0.03608}, {600, 0.0907},
			{650, 0.2482}},
		cheapPrice = {{50, 21.13}, {100, 25.22}, {150, 51.42}, {200, 535.2}, {250, 62.23}, {300, 8.202}, {350, 164.9},
			{400, 654.1}, {450, 637.5}, {500, 602.7}, {550, 433.3}, {600, 315.2}, {650, 228}},
		goal = {{20, 1.0}, {35, 1.7}, {60, 1.8}, {100, 2.7}, {175, 3.8}, {250, 5.0}},
		-- Loot by monster level (owner 2026-10-21; `lootLevel` below, pace_core.lua P.levelPlan, server/README.md "Loot
		-- by monster level"). Smooth curves (monotone cubic through the points, flat beyond the ends) by the monster's
		-- level only. coins: the share of the value of coins and NPC-sellable non-gear items, on top of `loot` (it
		-- replaces the linear `gold` of 2026-10-20: 1.0 to 250, 0.30 from 450; gold per hour at 450-600 had been 16M
		-- against the income model's 5.5-6.3M); the coins come back as coins. junkKeep: the share (on top of `loot`) of
		-- those items that stay in kind; the rest of their value is paid as coins. notable: the share of the notable
		-- drops kept (Rare+ gear, rare drops), never below `loot`. From 700 every notable drop stays, and coins and junk
		-- pay for it; below 650 nothing changes but the coins. The points from 650 on are tools/loot_model.lua --derive:
		-- the same gold and items per hour as the 2026-10-20 rule at the pack model's kills per hour.
		-- O141 (2026-10-23): the points 400-600 are fitted to the smooth gold curve of `lootLevel.goldPerHour` (they were
		-- 0.291 at 450 and 0.280 at 550, which put the gold per hour at 400-600 under the level 300 band's: 469k at 300,
		-- 325-537k at 400-600, 1.8M at 650); junkKeep holds the items per hour of the 2026-10-20 rule there
		coins = {{35, 1}, {50, 0.275}, {100, 0.5725}, {150, 0.1451}, {200, 0.1281}, {250, 0.07365}, {300, 0.1208},
			{350, 0.0361}, {400, 0.00866}, {450, 0.2031}, {500, 0.117}, {550, 0.006373}, {575, 0.03}, {600, 0.06},
			{625, 0.2}, {650, 0.2}},
		junkKeep = {{50, 2}, {650, 2}},
		notable = {{50, 0.56}, {100, 0.37}, {150, 0.303}, {200, 0.247}, {250, 0.2}, {300, 0.2}, {350, 0.2}, {400, 0.2},
			{450, 0.2}, {500, 0.197}, {550, 0.193}, {600, 0.19}, {650, 0.19}}
	},

	-- level-scaled Chaos monsters and generated area / dungeon monsters, by level. The engine gives a level-scaled monster
	-- x(1 + 0.0074 L) health and its kill x0.03 L experience (base player.lua, checked on the test server, server/README.md
	-- "Late game"); both are on top of these curves. health: re-measured 2026-10-20 (it was 0.095 at 650 to 0.056 at 2000).
	-- xp: re-fitted 2026-10-22 (O108) with the x0.03 L counted, so a scaled hunt's experience per hour is the leveling
	-- model's again (the 2026-10-14 pack model: median class about 130 h from 1 to 1000). The 2026-10-20 points (0.70 at
	-- 650, 0.58 at 800, 0.52 at 1000) were fitted on the file experience without that factor and paid 5-10x the model per
	-- hour (a kill 81k at 650, 157k at 800, 296k at 1000 before the stage; base monsters there 4.8k-7.6k). The new point at
	-- L is the old 0.042 / 0.036 / 0.030 / 0.026 / 0.024 / 0.023 x the median class's kills per hour with the old health
	-- curve / with this one (tools/pack_model.py): about 0.086 at every level. A kill now pays about 10k at 670, 24k at 810
	-- and 47k at 980 before the stage, for 28k-73k health (pace_scan.lua prints both with the engine factors).
	-- goal: kill goals x, sized on the kill rate like the base set's. The 2026-10-14 points (20 at 650 to 37 at 2000) were
	-- for 990-800 kills an hour; with the 2026-10-20 health a hunter kills about 485 (650) to 211 (2000) an hour
	-- (tools/spawn_tuning.json model.paceKillsPerHour, from tools/pack_model.py), so the goals are the old ones x that
	-- ratio (O108): an 800+ contract or kill task takes the model's time again, and its reward (a share of its kills'
	-- experience) is the model's too.
	-- O138 (2026-10-23, owner: faster, fluid combat): the late sets were a slog, a pack of 8 took 28-74 s for the median class
	-- (5-17x a base hunt's pack, 4-5 s). Health is now x0.40 / 0.31 / 0.20 / 0.16 / 0.15 / 0.14 of the O108 curve above
	-- (0.35 .. 0.42) at 650 / 800 / 1000 / 1300 / 1600 / 2000: a pack of 8 dies in 10-11 s, 2.1-2.4x a base hunt's pack
	-- (tools/pack_model.py --check bounds it at 3x). The median class kills x1.72 / 2.05 / 2.69 / 3.22 / 3.50 / 3.74 as many
	-- an hour (pack_model.py), so xp and loot per kill are the O108 points divided by that and goal is multiplied by it (a
	-- goal counts kills: the contract takes the same hours and pays the same experience; spawn_tuning.json
	-- paceKillsPerHour scaled has the new kills per hour, 790-870, under the base hunts' 1200). Experience, gold and goal
	-- pace per hour are unchanged (tools/progression_model.lua and tools/loot_model.lua --check).
	-- Check with: luajit tools/pace_scan.lua
	scaled = {
		health = {{100, 0.10}, {650, 0.140}, {800, 0.110}, {1000, 0.080}, {1300, 0.068}, {1600, 0.062}, {2000, 0.058}},
		xp = {{100, 0.044}, {650, 0.0499}, {800, 0.0414}, {1000, 0.0323}, {1300, 0.0270}, {1600, 0.0245}, {2000, 0.0233}},
		loot = {{100, 0.137}, {650, 0.482}, {800, 0.336}, {1000, 0.230}, {1300, 0.185}, {1600, 0.163}, {2000, 0.147}},
		goal = {{650, 16.9}, {800, 20.9}, {1000, 25.8}, {1300, 30.9}, {1600, 34.3}, {2000, 36.6}},
		-- loot by monster level: the base points from 450 on (the old `gold` reached 0.30 at 450 in both sets); below,
		-- the old ramp from 100 x the 0.963 the base curve carries there (the empty-corpse floor)
		coins = {{100, 0.963}, {275, 0.626}, {400, 0.730}, {450, 0.740}, {500, 0.880}, {550, 0.900}, {600, 0.900},
			{650, 0.176}, {700, 0.179}, {800, 0.133}, {900, 0.252}, {1000, 0.271}, {1250, 0.290}},
		junkKeep = {{300, 3.67}, {400, 0.700}, {450, 0.500}, {500, 0.720}, {550, 0.800}, {600, 0.880}, {650, 3.67},
			{700, 0.312}, {800, 0.114}, {900, 0.613}, {1000, 3.45}},
		notable = {{650, 0}, {700, 1}}
	},

	-- generated area / dungeon points (areagen: the point's level): the points the run-time model of the queue dungeons
	-- (dungeons_difficulty.lua, tests/areagen_test.lua: about 10 minutes at difficulty 1) was calibrated on. Their
	-- monsters are the level-scaled late sets, so the engine's x0.03 L applies (areagen.lua scales it to the point's
	-- level). The xp points are the 2026-10-14 ones again (O108): the raise of 2026-10-20 (0.19 at 650, 0.15 at 800, 0.075
	-- at 1000) was measured without the x0.03 L and the x(1 + 0.0074 L) health and paid 2.5-4.5x the model; the health
	-- never changed.
	generated = {
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

	-- loot by monster level (owner 2026-10-21, "Ajuste o loot de acordo com o lvl só monstro"): a paced corpse is thinned
	-- by pace_core.lua P.levelPlan with the curves of its monster's set (`coins`, `junkKeep`, `notable` above) at the
	-- monster's level; never by the killer's level, party or place. Notable drops: gear with a stock rarity of at least
	-- notableRarity (4 = Rare; Legendary and Divine too) and items of the loot table with a chance per 100000 of at most
	-- notableChance (1%). false: the 2026-10-20 method (loot.lua L.thinCorpse: each item at random with loot, coins and
	-- sellables x coins on top).
	lootLevel = {
		enabled = true,
		notableRarity = 4,
		notableChance = 1000,
		-- O141: the gold per hour (tools/loot_model.lua) the bands 350-600 are held to by `--check` (the other bands keep
		-- the 2026-10-20 rule's within 5%); `base.coins` / `base.junkKeep` points 400-600 are fitted to it
		goldPerHour = {[100] = 138000, [300] = 469000, [350] = 600000, [400] = 625000, [450] = 785000, [500] = 860000,
			[550] = 1005000, [600] = 1055000, [650] = 1340000},
		-- O285: the items per hour the bands are held to (--check): 100 / 300 / 500 / 650 are the figures from before the
		-- monsters stood at their pool level; the bands between are what the curves give (the pool cannot do more at the
		-- gold above)
		itemsPerHour = {[100] = 539, [300] = 692, [350] = 503, [400] = 436, [450] = 436, [500] = 380, [550] = 368, [600] = 444,
			[650] = 540},
		-- these monsters pay their coins as crystal coins only, a random whole number with the same expected value
		-- (pace_core.lua P.crystalStacks; beta report 2026-10-22: their pay filled the bag with three coin kinds)
		crystalOnly = {} -- empty since O285: the widows paid 3,170 a kill at level 1018, 730-860 at their pool level (509 / 480), a 7% chance of one whole crystal coin
	},

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

	-- pack cleave (PvE only): a direct hit (melee, ranged, spell; not damage over time) of a character, or of its summon
	-- (by its master's class), on a paced monster also deals a share of it to up to `targets` other monsters within
	-- `radius` sqm of that monster (nearest first; never a boss, a player's summon or a player). The share is `percent`
	-- up to level fromLevel, linear to `high` at toLevel and `high` above (pace_core.lua P.cleavePercent). Bosses are
	-- never paced, so boss damage and PvP do not change. By vocation id (chaos_constants.lua Chaos.classes.ids).
	-- Owner decision 2026-10-15: the strongest pack class (the Elementalist) is not touched and every other class is
	-- raised to about 0.92 of it or more in packs at levels 300 / 800 / 1000; each share is what its class needs
	-- (server/tools/pack_model.py; data/spells/README.md "Pack farming for every class"). The classes that needed more
	-- than about 25% got pack spells of their own instead (_blades.lua, _packtools.lua) and keep at most 20% here.
	cleave = {
		enabled = true,
		radius = 1,
		fromLevel = 300,
		toLevel = 1000,
		byVocation = {
			[4] = {percent = 6, high = 11, targets = 4}, -- Warrior
			[8] = {percent = 15, high = 26, targets = 4}, -- Juggernaut
			[14] = {percent = 0, high = 3, targets = 4}, -- Berserker
			[3] = {percent = 23, high = 20, targets = 4}, -- Ranger
			[7] = {percent = 28, high = 21, targets = 4}, -- Deadeye
			[15] = {percent = 9, high = 0, targets = 4}, -- Beastmaster (the companion's hits too)
			[1] = {percent = 0, high = 2, targets = 4}, -- Mystic
			[10] = {percent = 12, high = 17, targets = 4}, -- Illusionist
			[11] = {percent = 10, high = 11, targets = 4}, -- Thief
			[12] = {percent = 12, high = 6, targets = 4}, -- Ninja
			[13] = {percent = 17, high = 19, targets = 4}, -- Samurai
			[20] = {percent = 2, high = 14, targets = 4}, -- Necromancer (the minions' hits too)
			[21] = {percent = 10, high = 7, targets = 4}, -- Lich
			[22] = {percent = 6, high = 6, targets = 4}, -- Bone Lord (the minions' hits too)
			[17] = {percent = 6, high = 12, targets = 4}, -- Monk
			[18] = {percent = 16, high = 16, targets = 4}, -- Shadowfist
			[19] = {percent = 11, high = 15, targets = 4}, -- Iron Sage
			[23] = {percent = 3, high = 16, targets = 4}, -- Templar
			[24] = {percent = 8, high = 13, targets = 4}, -- Inquisitor
			[25] = {percent = 6, high = 16, targets = 4} -- Sentinel
		}
	},

	-- lowercase type names that are never paced (in addition to bosses and summons)
	skip = {},

	-- empty corpses decay after this many seconds (0: the stock decay). More kills leave more corpses.
	emptyCorpseSeconds = 30,
	-- corpses with loot left in them decay after this many seconds, all monsters (0: the stock decay; never lengthens)
	corpseSeconds = 120
}
