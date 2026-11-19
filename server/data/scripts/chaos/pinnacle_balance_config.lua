-- pinnacle_balance_config.lua (O667): the inputs and the limits of the pinnacle boss model, tools/pinnacle_model.py --check (CI).
-- Plain table, loaded with dofile. Lua 5.1 / LuaJIT and Lua 5.3 compatible. No engine calls. server/README.md "Pinnacle bosses
-- (O667)" has the method and the tables.
--
-- The model (computed, not measured in game): four bosses, each planned for a character level (pinnacle_config.lua `refLevel`).
--   length    the median class (class_dps_model.py, through boss_length_model.py: the armour and resistance a boss keeps) kills the boss
--             alone in `seconds.solo` and five of them in `seconds.party`: the fight's health (pinnacle_config.lua `health`, the XML's)
--             is seconds x (players x damage x uptime - the boss's heal a second), and `perExtra` the party curve to five.
--   damage    the boss's hits (its XML attacks x the engine's level bonus 1 + 0.0015 x its level x the level pace, as the hunt model does)
--             and its marked attacks (boss_mechanics_config.lua: the share of max health of a telegraph x the share a player still
--             takes, the timed ones too) against the median class of the planned level (survival_model.py through guardian_model.py):
--             seconds to die with no healing, and the pressure (damage against healing).
--   fragments a whole set is four kinds, three from one content each and the keystone from any: the hours of top content for a set
--             and, with the unique's roll and its bad-luck count, for a unique.
return {
	-- O672 (owner 2026-11-19): the player's level cap is 2500, so no boss is shown, planned or opened at a level above it. The first
	-- version (O667) had 2000 / 2500 / 3000 / 3500 with planned levels 2000-2500; the ladder is now 1900 / 2100 / 2300 / 2500: even steps
	-- of 200 under the cap, so a capped character meets the last boss at its own level and the first is one the 1800-1900 characters of
	-- the waystone tier XII+ fragments can reach. Each fight is planned for the level it is shown at (`refLevel` = `level`) and opens
	-- 100 levels below it (`minLevel`, `openBelow`), as the first version did.
	levelCap = 2500,
	-- the planned fight
	seconds = {solo = 420, party = 300},
	players = 5,
	-- the damage lands this share of the time (the mechanics' own downtime is held by boss_mechanics_core.lua G.balance: the profile's
	-- `ref` is this fight, the health of the run is x its hpMult)
	uptime = 0.85,
	limitSeconds = 1200, -- pinnacle_config.lua minutes x 60
	-- the weakest class deals this share of the median (class_dps_model.py keeps every class within 25%): it finishes alone within
	-- `weakestShare` of the limit
	weakest = 0.75,
	weakestShare = 0.6,

	-- how the boss's hits split over the player's layers: melee (armour, block) / physical spell / elemental (absorbs)
	split = {melee = 0.5, physical = 0.1, element = 0.4},
	-- the share of the marked attacks a player still takes after moving (the telegraphs are dodgeable)
	marksTaken = 0.35,
	-- a Hex Effigy (the immobile ward of the adds) and the boss's heal a second: from the XML (healing defense)

	-- tolerance of the committed numbers (health, party curve) against the derivation
	tolerance = {health = 0.015, perExtra = 0.02},

	-- limits of --check (the boss at its planned level, the median class)
	limits = {
		ladder = {1900, 2100, 2300, 2500},
		openBelow = 100,
		-- seconds to die with no healing, solo (the Omen guardian: 3-10, the rift guardians 1.2-16)
		burst = {min = 4.0, max = 13.0},
		-- the boss's damage against the median class's healing, solo: above it the healer loses without dodging, far below it the boss is
		-- only a wall of health (guardian_balance_config.lua pressure 0.55-1.15, Omen 0.7-1.35; a pinnacle is the harder fight)
		pressure = {min = 0.80, max = 1.40},
		-- a party of 5: the boss's damage x the damage curve on its target, against that player's healing (the party heals each other too)
		partyPressure = 1.75,
		-- the rise of the pressure from the first boss to the last: each one at least this much above the one before it (a higher
		-- level is a harder fight), at most `riseMax` x the first
		rise = 0.0, riseMax = 1.5
	},

	-- the fragments: what the top content takes (minutes a clear, solo or a party) and the limits of --check. A waystone map of the
	-- top tiers and a rift of tier 15 are the size band of the biggest rift (12-15 minutes, rift_config.lua layout.sizes); the Omen
	-- guardian is its rift (the run, the climb to the guardian and its 5:18 kill, boss_length_model.py OMEN_SECONDS).
	minutes = {waystone = 15, rift = 13, omen = 12},
	hours = {
		-- hours of top content for a whole set (the three specific kinds in turn, the keystone along the way): a set is an evening or
		-- two of the top content, not a week; and not less than the 2.5 hours of a hunt of the band
		set = {min = 2.5, max = 7.0},
		-- the keystone's own rate: one an hour of mixed top content at most (it is a roll on every clear)
		keystonePerHour = 1.5,
		-- hours of top content for the exclusive unique of one boss (sets x kills to the unique), with the bad-luck count
		unique = {min = 8, max = 45}
	}
}
