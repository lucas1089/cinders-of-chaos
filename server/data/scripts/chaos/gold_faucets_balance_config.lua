-- Gold faucets against the one gold curve (O754, owner 2026-11-24 "Acertar o ouro"; server/README.md "Gold faucets against
-- the curve (O754)"). The inputs and limits of tools/gold_faucets_model.lua. Plain table, loaded with dofile. Lua 5.1 /
-- LuaJIT and Lua 5.3 compatible. No engine calls.
--
-- The rule: content pays gold an hour against hunt_gold_config.lua `hunting` at the level it is played. Harder or riskier
-- content may pay more, at most `limit` x the curve (party content per character). Content under `low` x the curve is
-- fine only when it pays something else (the model prints what). The gold of a faucet is its own gold (chest, bank,
-- bonus coins) plus the corpse gold of its kills: `kills` x the curve, the share of a hunt's kill loot an hour of the
-- content gives. Every number below is a model input, computed or read elsewhere, not measured in game.
return {
	limit = 1.5,
	low = 0.8,
	-- the levels a faucet is checked at (inside its own range); a faucet with flat gold is worst at the bottom of its range,
	-- one with gold x level at the top
	levels = {100, 200, 300, 400, 500, 650, 800, 1000, 1300, 1600, 2000, 2500},
	party = 5, -- party content is checked per character with this many players

	-- the hunt kills an hour and the share of coins and junk in the sale gold (luajit tools/loot_model.lua --income,
	-- columns Kills/h and Coins and junk/h over Sale gold/h). Linear between the points, flat beyond.
	huntKills = {{40, 1596}, {100, 1574}, {300, 1285}, {500, 1211}, {650, 1163}, {800, 1086}, {1000, 938}, {1300, 835},
		{1600, 814}, {2000, 802}, {2500, 789}},
	coinShare = {{40, 0.49}, {100, 0.46}, {300, 0.43}, {500, 0.47}, {650, 0.32}, {800, 0.23}, {1000, 0.24}, {1300, 0.27},
		{1600, 0.25}, {2000, 0.27}, {2500, 0.25}},

	rift = {
		-- the share of a hunt's kill loot an hour of rifting gives (tools/content_reward_model.lua EFFICIENCY.rift: the pack
		-- model's kills x 0.80 for the key, walking and the chest)
		kills = 0.80,
		around = 180, -- seconds around a run: key, travel, the chest, town (tests/rift_test.lua, the income model)
		quantity = 128, -- the key's quantity bonus checked: the highest sum with tier V modifiers (the income model)
		-- the atlas checked: own goldMult at its cap and the Lone Ember keystone (rewardMult 60), the most a finisher stacks
		atlas = {own = {goldMult = 25}, run = {rewardMult = 60}},
		partyDps = 4.98, -- a party of 5 deals 4.98x the damage of one (the Ascended model, rift_config.lua density)
		-- the Omen guardian: boss_length_model.py plans 318 s at level 1000; 120 s to bind the key, travel and loot
		omenSeconds = 318 + 120,
		-- the Ascended Omens kill before the enrage (600 s, uber_config.lua) and the Cinderheart before its 900 s: 80% of
		-- it, as the raid's planning; 120 s around each
		ascendedSeconds = 480 + 120,
		cinderSeconds = 720 + 120,
		-- the Greater Rift (greater_rift_model.py): the shown tier the median class reaches solo and in a party of 5, and
		-- the seconds of a run at that tier (the clock nearly spent); 180 s around it as a rift
		greaterReach = {{1025, 29, 1251}, {1500, 36, 1220}, {2000, 42, 1203}, {2500, 47, 1222}}
	},

	waystone = {kills = 0.85, from = 1100}, -- content_reward_model.lua EFFICIENCY.waystone; no gold of its own

	descent = {
		-- a full clear (depth 12, the boss slain) with every curse (+105% gold), solo. descent_model.py: about 700-810 s of
		-- room fights at levels 100-1500, plus about 30 s a room between them (walk, shrine, merchant, treasure): 20 min
		depth = 12, minutes = 20, cursePercent = 105,
		kills = 0.7, -- about 240 monsters a run (waves x size of descent_config.lua at depth 1-12) against a hunt's kills
		from = 100
	},

	tower = {
		-- infinitytower_balance_config.lua holds the items an hour of the tower at most 1.2x and its coin gold at most
		-- goldRatio x goldShare (0.73) of a hunt of the floor's level: about one hunt. floorGold x floor per floor on top:
		-- the median class at level 800 gets 30-46 floors deep (reachLevel), about 90 floors an hour (24 s a floor and the
		-- pause)
		kills = 1.0, level = 800, floor = 40, floorsPerHour = 90
	},

	dungeons = {
		-- the generated dungeons (areagen_config.lua kind "dungeon"): 9.5 minutes at difficulty 1 and 13.7 at 6
		-- (chaos_constants.lua Chaos.dungeons, the run model), 110 monsters of which 85% die before the boss
		minutes = {9.5, 10.3, 11.1, 12.0, 12.8, 13.7},
		monsters = 94,
		itemShare = 0.76 -- the gear and extra rolls share of the sale gold at level 1000 (the loot bonus of a difficulty)
	},

	raid = {
		-- The Ashen Sepulchre, once a week: four bosses and the final one at 80% of their enrage (540 / 600 / 660 / 660 /
		-- 960 s) is 46 minutes, the trash and walking 30 more
		minutes = 75, kills = 0.2
	},

	worldboss = {
		-- four a day; the fight about 15 minutes, the gathering 2 and the exit 1.5, so 20 minutes of a player's time
		minutes = 20, kills = 0
	},

	invasion = {
		-- 20 minutes (invasion_config.lua timeLimitMinutes); the invaders drop their loot, about half a hunt's kills
		minutes = 20, kills = 0.5, defenders = {1, 5}
	},

	bounty = {
		-- a hunt contract: half of the kills of a hunt are of the contract's type (a hunt has 2-4 kinds); an elite
		-- contract: count x eliteSearch kills of the type; a boss contract: about 6 minutes to find and kill the boss
		targetShare = 0.5, bossMinutes = 6
	},

	trials = {
		-- a trial fight of 480-600 s (trials_config.lua tiers time) and a minute around it; boss and adds, no corpse loot
		minutes = 10, kills = 0
	},

	siege = {
		-- one a week: a 25 minute match (siege_config.lua matchMinutes) and 5 minutes around it; PvP, no corpse loot
		minutes = 30, kills = 0
	},

	goblin = {
		-- treasure_goblin_config.lua spawn.oneIn: one natural respawn in 3000 a goblin; a hunter kills the hunt kills an
		-- hour; the gold of the variants is 70% x 1 + 30% x 0.5 of the Hoarder's, x 1.05 (80-130%)
		variantGold = 0.85, rollMean = 1.05
	}
}
