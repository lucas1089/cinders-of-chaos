-- descent_balance_config.lua (O664): the inputs and the limits of the Ember Descent model, tools/descent_model.py --check (CI).
-- Plain table, loaded with dofile. Lua 5.1 / LuaJIT and Lua 5.3 compatible. No engine calls. server/README.md "Ember Descent model
-- (O664)" has the method and the before / after tables.
--
-- The model (computed, not measured in game): a character of the band's level, every class, in the rooms of the Descent (the
-- real level window, waves, sizes, tiers, depth growth of descent_config.lua): seconds to clear against seconds to die, solo and in
-- a full party (`maxPlayers` of descent_config.lua, 4), next to the hunt pack of the same level (tools/survival_model.py).
-- O663 measured room 1 live: a level 592 Warrior took 2,611 damage a second, 29% of its health, and 7 of 10 bots fled at 20%.
return {
	-- the party levels of the report and of the check: the bands of the balance models (class_dps_model.py measured 100 / 500 / 1000)
	-- and the end of the planned game
	levels = {100, 500, 1000, 1500},
	-- party sizes: solo and the full party (descent_config.lua maxPlayers = 4; the Descent takes no party of 5)
	parties = {1, 4},
	-- the depths of the report (the room number); eliteFrom is descent_config.lua's. The boss is the last room of a run of 8 to 12 rooms
	depths = {1, 2, 3, 4, 5, 6, 8, 9, 10, 12},
	bossDepths = {8, 12},
	-- the hunt the Descent is held against (survival_balance_config.lua): the player is `gap` levels above the hunting level, the
	-- hunt's monsters are the pool's within `band` levels of it
	gap = 7,
	band = 30,

	-- a level-scaled monster carries the engine's health x (1 + engineHealth x level) (pace_config.lua; pack_model.py SCALED_HEALTH:
	-- 22,500 x (1 + 0.0074 x 980) = 186k against the 200k there)
	engineHealth = 0.0074,
	-- the stock monsters have no XML in the repo, only their biggest hits (data/spells/guardian_hits.csv): one hit of that size
	-- `hitRate` times a second per kind. Fitted on the 130 level-scaled monsters that have both (the median of XML damage a
	-- second over melee mean plus spell mean is 0.45), and it matches the stock line of the guardian model: necro_balance_config.lua
	-- monsterDps at level 416 x guardian_balance_config.lua stockFit 1.6 = 544 a second, the Mystic Baguemage here 540
	hitRate = 0.45,
	-- the share of survival_model.py's healing (one Everfull potion a second and the line's self heal, every second of the fight) a
	-- player lands in a room with its waves: a drink needs the free moment between casts and dodges. O663 measured 1,053 a second for
	-- the level 592 Warrior bots against the model's 2,940 (0.36); a player does better than a bot, 0.4 keeps the bots in the limits
	healUse = 0.4,
	-- seconds from the last kill of a wave to the next wave's first hit: the wave spawns at the far side of the 21 x 21 hall and walks in
	waveGap = 4,
	-- the boss is the strongest of the room's three types (spawnBoss: the last of the types sorted by level): the model takes the mean of the
	-- upper half of the window's candidates (from this share of the window by level)
	bossFrom = 0.5,

	-- the boons of a run (descent_config.lua boons): picks per room cleared or visited (combat .50, elite .18, treasure .10 give a
	-- pick, the shrine .12 a pick for health, the merchant one for embers: about 0.85), the share of the physical damage a brand
	-- converts that a player really deals as physical (casters deal none: 0.5), the seeded Monte Carlo (runs, seed) of the best of three
	-- offers by damage plus damage reduction plus leech
	boons = {picksPerRoom = 0.85, physicalShare = 0.5, runs = 400, seed = 664},

	-- limits of --check, at every level of `levels`; "median class" = the class in the middle of the 21 by pressure (the damage a room
	-- deals it over its healing); left = the health it keeps at the worst moment of the room, potions and self heal counted at healUse;
	-- pressure = damage over healing: under 1 the room heals itself away, over 1 it wears the class down
	limits = {
		-- room 1 (no boon yet), solo and in a party: the median class clears it and keeps most of its health; the worst class does not
		-- fall under 30% (the bots flee at 20%: the line under which a player would not stay); the median class lives `burstVsHunt` x its
		-- seconds to die with no healing in the hunt pack of its level (survival_model.py; a Descent wave is 4 monsters of 0.60-0.85 of
		-- the level, a pack 6-7 of the level); a clear in 8 to 60 seconds (two waves; before O664: 42-113 s; a hunt pack takes the
		-- median class 10-25 s); the median class's damage over its healing 0.15 to 1.0 (a fight that heals itself away, not a walkover); the hardest tenth of the monster picks alone (Mystic Baguemage and its kind) leaves the median class 30%
		room1 = {medianLeft = 0.60, worstLeft = 0.30, burstVsHunt = 1.0, clear = {8, 60}, pressure = {0.15, 1.0}, hardQuantile = 0.9, hardLeft = 0.30},
		-- growth, the solo player's climb: a deeper room never presses the median class less than the one before (slack: the pool
		-- changes with the window, the model takes the mean of it), `lateRoom` presses at least `lateOverFirst` x room 1, the Ashwalker
		-- depth (descent_config.lua titles: 5) is within the median class (it keeps `titleLeft`), the Emberdelver depth (9) is not
		-- free: it presses at least `hardPressure` (the boons, a party and play make up for it)
		growth = {slack = 0.3, lateRoom = 10, lateOverFirst = 1.6, titleDepth = 5, titleLeft = 0.50, hardDepth = 9, hardPressure = 1.3},
		-- the final boss: killed in 60 to 240 seconds by the median class (rift guardian 55 s, dungeon bosses 150 s, Omen 318 s) and a
		-- fight, not a walkover or a wall: it presses the median class at 0.7 to 1.4 x its healing (descent_config.lua boss.damage 1.25: a hunt
		-- monster of its level hits for 0.45 of the pool entry, the boss is one monster of the window's upper half where a pack is 6-7)
		boss = {clear = {60, 240}, pressure = {0.7, 1.4}},
		-- a full party takes 0.4 to 1.5 x the solo player's time to clear room 1 (the room grows by 2 monsters a player, the damage
		-- of the party grows by a player)
		party = {clearRatio = {0.4, 1.5}},
		-- a curse is a gamble for 15-25% more rewards, not a sentence: with Swarm and Frailty both taken at `depth` the median class
		-- keeps `medianLeft`. Named exception (O707, owner decision of 2026-11-21: weapon style power share 0.20 and skill factor
		-- max 1.0): the bow and melee classes lost damage, the class at the middle of the 21 by pressure at level 1000 is now the
		-- Monk (0% left, it was the Beastmaster, 50%), a knife edge of the class order, not a change of the room; `exceptions` lists
		-- the level and the floor held instead (the curse stays a gamble: depth 3 leaves the median class 92%, see --curses)
		curse = {depth = 4, medianLeft = 0.25, exceptions = {[1000] = 0.0}}
	}
}
