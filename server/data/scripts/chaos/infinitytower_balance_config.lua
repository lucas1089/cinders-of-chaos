-- Infinity Tower balance (infinitytower_run.lua, infinitytower_balance_core.lua; server/README.md "Infinity Tower
-- balance and floor rewards", O144): every number of the floors, their health, the rewards and the model limits. Plain
-- table, loaded with
--     ChaosTowerBalance = dofile("data/scripts/chaos/infinitytower_balance_config.lua")
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible. Edit here, then restart (or /reload scripts). The curves are linear between
-- their points up to maxFloor; above it the `beyond` growth takes over (the tower never stops getting stronger, O172).
-- tools/tower_model.py reads this file with regular expressions: keep each curve
-- as `name = {{floor, value}, ...}` and the other numbers as `name = number`.
--
-- Why (beta report 2026-10-22, "Infinity Tower": level 800 stuck at floor 20-29, a level 100 monster takes a minute for a
-- level 500 pair, drops like outside, no reward per floor, four different monsters and deaths from floor 20): the floors
-- used the stock health of their pool (pace.lua never touches the tower), the chance of a magic / rare / legendary
-- monster (x2 / x3.5 / x6 health, 1-4 modifiers) grew with every floor, a floor held up to 16 monsters, and the 5
-- pools changed health by up to 60x between bands. tools/tower_model.py recomputes the time to clear a floor from this
-- file against the damage of the classes (tools/pack_model.py) and --check bounds it, as pack_model.py --check does for
-- the late packs.
--
-- Health: `health` is the maximum health of a normal monster of the floor (its pool species only decide what it looks like
-- and how it hits); the tier (monster_tiers.lua) multiplies on top. It was derived with `tower_model.py --derive` so a
-- floor dies in `clear` seconds for the median class at the level the floor is meant for (`level`), about what a pack of
-- that level takes in a base hunt (pace_config.lua); `sawtooth` then lets the floors of every five climb and the floor
-- after a milestone floor breathe.
return {
	-- floors
	bossEvery = 10, -- every 10th floor holds a boss (and about a third of the floor's count as helpers)
	milestoneEvery = 5, -- the floors with a reward, the end of a climb of the sawtooth
	bandFloors = 8, -- the pool changes every 8 floors; the last pool repeats
	bossHelperDivisor = 3,
	perPlayer = 2, -- monsters added for every player of the group after the first
	maxFloor = 120, -- the last point of the curves; the model times the floors 1 to this, `beyond` grows every value above it

	-- the species of a floor's band (looks and attacks; their stock health is not used)
	pools = {
		{"troll", "orc warrior", "skeleton", "ghoul", "dwarf soldier"},
		{"minotaur", "cyclops", "giant spider", "gargoyle", "stone golem"},
		{"dragon", "warlock", "banshee", "serpent spawn", "crystal spider"},
		{"demon skeleton", "vampire", "werewolf", "lost soul", "hydra"},
		{"behemoth", "dragon lord", "dark torturer", "fury", "phantasm"},
		{"hellhound", "juggernaut", "plaguesmith", "undead dragon", "grim reaper"},
		{"demon", "destroyer", "hellfire fighter", "massive fire elemental", "blightwalker"}
	},

	-- the bosses in the order of the boss floors (10, 20, ...; the list repeats). heal: the boss's own health per second
	-- from its file (server/README.md "Solo kill times"). Ordered by what a player of the floor's level can out-damage:
	-- Zeburoth and Ashvoran heal 1,750 a second and come last (before 2026-10-23 they stood on floors 30 and 90).
	bosses = {
		{name = "the ashen count", heal = 0},
		{name = "the grey widow", heal = 42},
		{name = "massacre", heal = 0},
		{name = "vharagoth", heal = 64},
		{name = "moloveth", heal = 64},
		{name = "vhalkareth", heal = 60},
		{name = "jungle's revenge", heal = 204},
		{name = "ssylvath the corruptor", heal = 250},
		{name = "pestrogh", heal = 300},
		{name = "morgashal", heal = 316},
		{name = "zeburoth", heal = 1750},
		{name = "ashvoran", heal = 1750}
	},

	-- monsters of a floor for one player (rounded)
	count = {{1, 4}, {16, 6}, {32, 7}, {64, 8}, {120, 9}},

	-- health of a magic / rare / legendary monster against a normal one of its floor (monster_tiers.lua has x2 / x3.5 / x6:
	-- one legendary Lost Soul with Juggernaut and Stoneskin took a level 500 pair a minute); damage, speed and the modifiers
	-- stay the tier's. The run sets the health to health x this (ChaosTowerBalance.preTierHealth)
	tierHealth = {magic = 1.5, rare = 2.2, legendary = 3.5},

	-- chance in percent that a monster of the floor is magic / rare / legendary (the rest is normal)
	magic = {{1, 5}, {30, 26}, {60, 36}, {120, 40}},
	rare = {{1, 0}, {30, 7}, {60, 14}, {120, 16}},
	legendary = {{1, 0}, {30, 1}, {60, 3}, {120, 4}},

	-- the level a floor is meant for (the median class kills the floor in `clear` seconds)
	level = {{1, 100}, {10, 300}, {20, 540}, {30, 740}, {40, 900}, {60, 1250}, {80, 1600}, {100, 1950}, {120, 2200}},

	-- the climb of five floors: the health factor of the floor at the position 1..5 of its milestone cycle (the 5th is
	-- the milestone floor, the 1st the breather after the one before)
	sawtooth = {0.75, 0.88, 1.00, 1.10, 1.22},

	-- seconds a boss lives for the median class alone at the level of its floor (one target, bossUptime)
	bossSeconds = {{10, 45}, {120, 90}},

	-- seconds a floor of factor 1.0 takes the median class at the level it is meant for (tower_model.py --derive: the
	-- health below follows from it). A base hunt pack of that level takes 3 s at level 100, 5 s at 640 and 10-11 s from 670 (the
	-- late sets, pace_config.lua); the tower follows that smoothly and stays within huntMin..huntMax of it
	clear = {{1, 2.5}, {12, 3.5}, {24, 5}, {28, 8.5}, {40, 9.5}, {60, 10.5}, {120, 11}},

	-- maximum health of a normal monster by floor (tower_model.py --derive)
	health = {{1, 574}, {4, 718}, {8, 1140}, {12, 1610}, {16, 2180}, {20, 2870}, {24, 3970}, {28, 5940}, {32, 7190}, {36, 7980}, {40, 8860}, {50, 10600}, {60, 11800}, {70, 13100}, {80, 14400}, {90, 15400}, {100, 15500}, {110, 16000}, {120, 16700}},
	-- maximum health of the boss by boss floor (tower_model.py --derive)
	bossHealth = {[10] = 32400, [20] = 59200, [30] = 92100, [40] = 120000, [50] = 155000, [60] = 186000, [70] = 210000, [80] = 242000, [90] = 276000, [100] = 315000, [110] = 317000, [120] = 319000},
	-- damage of a floor's monsters to players (tower_model.py --derive): a monster shown at level L hits like a hunt monster of
	-- level L (O328). The pool species keeps its own attacks (they decide the looks and the kind of hit), so the factor is the
	-- pace_config.lua damage curve at L times `hit` at L over `hit` at the band's hunting level (the median of the species'
	-- bounty pool levels): a level 1200 troll no longer hits like the level 100 one. monster_damage.lua adds the late-game
	-- physical boost of the floor's level on top (ChaosTowerRun.levelOf).
	damage = {{1, 7.27}, {5, 10.4}, {7, 11.1}, {8, 6.17}, {9, 6.33}, {13, 6.47}, {15, 6.45}, {16, 2.67}, {17, 2.66}, {21, 2.63}, {23, 2.61}, {24, 1.8}, {25, 1.78}, {29, 1.76}, {31, 1.74}, {32, 1.16}, {33, 1.16}, {37, 1.16}, {39, 1.17}, {40, 0.909}, {41, 0.911}, {45, 0.917}, {47, 0.929}, {48, 1.28}, {49, 1.29}, {53, 1.34}, {57, 1.39}, {61, 1.45}, {65, 1.49}, {69, 1.53}, {73, 1.57}, {77, 1.6}, {81, 1.64}, {85, 1.68}, {89, 1.72}, {93, 1.76}, {97, 1.79}, {101, 1.83}, {105, 1.86}, {109, 1.88}, {113, 1.91}, {117, 1.94}, {120, 1.96}},
	-- the climb (owner 2026-10-29): on top of the hunt match above, every floor from the first hits `climb` more than the one
	-- below it (factor 1 + climb x (floor - 1), held at maxFloor; above it the `beyond` growth takes over): the tower is a
	-- challenge, harder than a hunt of the same level, and a floor never hits softer than the one before it in the same band
	climb = 0.015,
	-- the stock hit of a monster by hunting level, the reference of the line above (O328): the maximum of one attack of a monster
	-- of that level. Points below 140 are the stock species (troll 25 at level 7, dragon 160 at 42, demon 500 at 137); from 300
	-- the imported level-scaled monsters of data/monster/monsters/chaos (the median of their attack maxima: about 780-900 up to
	-- level 900, 1150 above 1000; the 1300 and 2200 points extend the slope). Only the ratio between two levels is used. Flat
	-- beyond 2200: above maxFloor the `damageRate` growth below takes over.
	hit = {{7, 25}, {42, 160}, {137, 500}, {300, 750}, {650, 880}, {1000, 1150}, {1300, 1350}, {2200, 1800}},

	-- Above maxFloor (O172, owner 2026-10-24: "the higher the floor, the stronger the monsters, without end"): every value
	-- keeps rising with the floor, never flat and never a repeat of an old boss. d = floor - maxFloor. `level` grows linearly
	-- (levelPerFloor a floor); health, bossHealth and damage are the value at maxFloor times exp(rate x d + accel x d^2 / 2),
	-- so a floor is rate + accel x d (as a fraction) harder than the one before and that step itself climbs: a soft wall, no
	-- cliff. rate starts above the level's own growth (12.5 of 2200 is 0.57% a floor), so the time a floor takes the player of its level rises from the first floor above maxFloor (tower_model.py checks it). The bosses' damage factor is 1 up
	-- to maxFloor and the same growth above it. The caps keep the engine's integers whole (TFS health is int32): the
	-- normal monster's cap leaves room for the legendary tier (x3.5 = 2.03e9 < 2^31 - 1 = 2147483647). A value at its cap
	-- stays there; tools/tower_model.py --check prints the floors where each cap starts and requires them past 1000.
	beyond = {
		levelPerFloor = 12.5, -- the slope of the curve's last segment (floor 100 to 120)
		healthRate = 0.007, -- 0.7% a floor at first: above the level (12.5 of 2200 = 0.57%), so a floor at its own level takes longer and longer
		healthAccel = 0.000002,
		bossHealthRate = 0.007,
		bossHealthAccel = 0.000002,
		damageRate = 0.002,
		damageAccel = 0.000004,
		levelMax = 2000000000, -- the shown level (engine patch 0044: int32 display level, drawn as text)
		healthMax = 580000000, -- a normal monster; x3.5 (legendary) stays under 2^31 - 1
		bossHealthMax = 2000000000, -- a boss has no tier
		damageMax = 1000, -- factor on a hit: monster hits are int32 and scaled through floor(hit x factor + 0.5)
		engineMaxHealth = 2147000000 -- whatever the tier makes of it: the last guard before setMaxHealth
	},

	-- Floor rewards (server/README.md "Infinity Tower balance and floor rewards"). Above maxFloor the counts of the rules
	-- (and the count of the drops) are those of maxFloor: the monsters keep growing, the economy does not (O172). Items are existing ones: crystal coins
	-- (2160) and the orbs of install_orbs.py. A rule gives its item on the milestone floors (`every`: floor % every == 0)
	-- a count of max(min, floor(base + perFloor x floor)); rules of one item add up on a floor.
	rewards = {
		-- the first time a character clears the floor in a tower season (30 days; the same season as the points): player
		-- storage `storage` holds season x 1000 + the highest milestone floor paid, so a floor pays once per season
		storage = 7102820,
		firstClear = {
			{every = 5, id = 2160, name = "Crystal Coin", base = 0, perFloor = 1},
			{every = 10, id = 29856, name = "Orb of Upheaval", base = 1, perFloor = 0.1},
			{every = 10, id = 29857, name = "Orb of Fate", base = 0, perFloor = 0.05, min = 1},
			{every = 25, id = 29857, name = "Orb of Fate", base = 2, perFloor = 0.04}
		},
		-- every time the floor is cleared in a run, on top of the gold of every floor (floorGold x floor)
		repeatable = {
			{every = 5, id = 2160, name = "Crystal Coin", base = 0, perFloor = 0.25},
			{every = 10, id = 29856, name = "Orb of Upheaval", base = 0, perFloor = 0.05, min = 1}
		}
	},

	-- Tower drops: added to the corpse of a tower monster on top of its own loot (infinitytower_run.lua onDropLoot).
	-- chance: per 10000 kills of a normal monster from the floor `from` on; tierMult x it for a magic / rare / legendary one.
	-- count: min to max, max + floor(perFloor x floor).
	drops = {
		tierMult = {magic = 1.5, rare = 3, legendary = 6},
		items = {
			{id = 29856, name = "Orb of Upheaval", from = 1, chance = 25, min = 1, max = 1, perFloor = 0},
			{id = 29857, name = "Orb of Fate", from = 20, chance = 12, min = 1, max = 1, perFloor = 0},
			{id = 2160, name = "Crystal Coin", from = 1, chance = 400, min = 1, max = 2, perFloor = 0.05}
		}
	},

	-- Loot follows the floor (O328, tester 2026-10-29: "the drops are those of the original level 100 version"). A tower monster
	-- counts at the level of its floor in loot.lua (ChaosLoot.monsterLevel: item level, gear by level, class weapons, rarity, orb
	-- and unique gates), capped at the level of maxFloor (the economy does not inflate, O172). Its corpse is thinned like a hunt
	-- monster of that level (pace_config.lua, the scaled sets above lootScaledFrom) times `lootShare`, so the items an hour of the
	-- tower are those of a hunt of the same level (the tower kills 3600 x monsters / (clear + engage + pause) an hour, more than a
	-- pack hunt). Gold: `killGold` is the gold of a normal monster's corpse in coins, goldShare x the gold an hour of the hunt at
	-- that level (pace_config.lua lootLevel.goldPerHour, flat above its last band) over the kills an hour of the tower. Both
	-- curves come from `tower_model.py --derive`.
	lootScaledFrom = 650,
	goldShare = 0.5,
	lootShare = {{1, 1}, {4, 1}, {8, 1}, {12, 1}, {16, 1}, {20, 1}, {24, 1}, {28, 1}, {32, 1}, {36, 1}, {40, 1}, {50, 0.94}, {60, 0.95}, {70, 0.96}, {80, 0.96}, {90, 0.94}, {100, 0.86}, {110, 0.86}, {120, 0.88}},
	killGold = {{1, 55}, {4, 55}, {8, 87}, {12, 110}, {16, 220}, {20, 270}, {24, 280}, {28, 370}, {32, 410}, {36, 410}, {40, 420}, {50, 380}, {60, 380}, {70, 390}, {80, 390}, {90, 390}, {100, 350}, {110, 350}, {120, 350}},

	-- the model (tower_model.py): the damage of the classes of tools/pack_model.py with this share of the time in the target
	packUptime = 1.0,
	bossUptime = 0.75,
	engageSeconds = 3, -- monsters reach the group after the spawn

	-- tower_model.py --check
	limits = {
		clearMax = 24, -- seconds: a floor at the level it is meant for (median class), the sawtooth's top included
		clearMin = 1.5,
		huntMax = 1.7, -- ... against the base hunt pack of the same level
		huntMin = 0.6,
		bossMin = 30, -- seconds: a boss at its floor's level, alone
		bossMax = 150,
		bossHeal = 0.5, -- the boss's heal against the median class's one-target damage with its uptime, at most
		weakBoss = 300, -- seconds: the class with the least one-target damage kills any boss in this time (the floor's limit is 600)
		breather = 0.85, -- the floor after a milestone floor against it
		stepMax = 1.35, -- a floor against the one before it (a boss floor and the breather left out)
		underLevel = 0.6, -- a player of this share of the floor's level ...
		underMax = 60, -- ... still clears a normal floor in this many seconds
		reachLevel = 800, -- the median class at this level gets as deep as every floor up to it takes at most reachRatio times ...
		reachRatio = 1.1, -- ... the base hunt pack of its own level (a floor beyond that is a fight it feels), the boss floors with reachBoss
		reachBoss = 100, -- seconds for a boss, helpers excluded
		reachMin = 30, -- the floors it gets to: reachMin to reachMax
		reachMax = 40,
		weakReach = 20, -- the weakest class of the same level gets at least this deep
		pairMax = 25, -- seconds: two players of level 500 and 800 on a normal floor up to floor 30
		singleMax = 30, -- seconds: one legendary monster (the average modifiers) alone, for the median class at the floor's level
		damageTol = 0.12, -- the damage curve against pace(L) x hit(L) / hit(band level) on every floor (relative; O328)
		lootRatio = 1.05, -- the items an hour of the tower against a hunt of the floor's level, at most (O328)
		goldRatio = 1.05, -- the gold an hour of the tower against goldShare x a hunt of the floor's level, at most
		endless = 1000, -- floors whose growth is checked strictly (health trend, boss health, damage, level; O172)
		capMin = 1000 -- the floor where a cap (int32 health, damage factor) may start at the earliest
	}
}
