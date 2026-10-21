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
		coins = {{35, 1.00}, {100, 0.963}, {300, 0.828}, {450, 0.291}, {550, 0.280}, {650, 0.176}, {700, 0.179},
			{800, 0.133}, {900, 0.252}, {1000, 0.271}, {1250, 0.290}},
		junkKeep = {{650, 3.67}, {700, 0.312}, {800, 0.114}, {900, 0.613}, {1000, 3.45}},
		notable = {{650, 0}, {700, 1}}
	},

	-- level-scaled Chaos monsters and generated area / dungeon monsters, by level. Re-measured 2026-10-20 against the base
	-- curves (tester: spiders at level 500 gave more experience than monsters at level 800): the old points left a
	-- level-scaled monster with 1/15 of the experience and 1/4.6 of the health of a base monster of the same hunting
	-- level. Now the experience per kill follows the base monsters' (about 4000 at 650, 6300 at 800, 10000 at 1000,
	-- 16500 at 1300, then +13.5 a level) and the health the same ratio as there (experience about 1 x health).
	-- Check with: luajit tools/pace_scan.lua
	scaled = {
		health = {{100, 0.10}, {650, 0.35}, {800, 0.36}, {1000, 0.40}, {1300, 0.42}, {1600, 0.42}, {2000, 0.42}},
		xp = {{100, 0.115}, {650, 0.70}, {800, 0.58}, {1000, 0.52}, {1300, 0.50}, {1600, 0.48}, {2000, 0.46}},
		loot = {{100, 0.137}, {650, 0.83}, {800, 0.69}, {1000, 0.62}, {1300, 0.595}, {1600, 0.57}, {2000, 0.55}},
		goal = {{650, 20}, {800, 24}, {1000, 28}, {1300, 32}, {1600, 35}, {2000, 37}},
		-- loot by monster level: the base points from 450 on (the old `gold` reached 0.30 at 450 in both sets); below,
		-- the old ramp from 100 x the 0.963 the base curve carries there (the empty-corpse floor)
		coins = {{100, 0.963}, {275, 0.626}, {450, 0.291}, {550, 0.280}, {650, 0.176}, {700, 0.179}, {800, 0.133},
			{900, 0.252}, {1000, 0.271}, {1250, 0.290}},
		junkKeep = {{650, 3.67}, {700, 0.312}, {800, 0.114}, {900, 0.613}, {1000, 3.45}},
		notable = {{650, 0}, {700, 1}}
	},

	-- generated area / dungeon points (areagen: the point's level): the points the run-time model of the queue dungeons
	-- (dungeons_difficulty.lua, tests/areagen_test.lua: about 10 minutes at difficulty 1) was calibrated on. Kept as they
	-- were; their health stays; the experience points were raised 2026-10-20 so that experience per health point matches the base monsters (about 0.8-1.2, it was 0.2-0.8: a generated area paid 4-6% of a base monster's experience per kill). The generator's own levelScale experience applies first.
	generated = {
		health = {{650, 0.095}, {800, 0.080}, {1000, 0.066}, {1300, 0.062}, {1600, 0.059}, {2000, 0.056}},
		xp = {{650, 0.19}, {800, 0.15}, {1000, 0.075}, {1300, 0.045}, {1600, 0.032}, {2000, 0.026}},
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
		-- these monsters pay their coins as crystal coins only, a random whole number with the same expected value
		-- (pace_core.lua P.crystalStacks; beta report 2026-10-22: their pay filled the bag with three coin kinds)
		crystalOnly = {"Nightfang Widow", "Shadowcrystal Widow"}
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
