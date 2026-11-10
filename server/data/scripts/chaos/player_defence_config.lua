-- player_defence_config.lua: the numbers of the player's defence layer (O464, server/README.md "Player defence (O464)").
-- Plain table, loaded as Chaos.playerDefence = dofile("data/scripts/chaos/player_defence_config.lua").
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.
-- The numbers a monster and a player share (armour by hit size, the physical cap, the resistance cap, the block cap) are in
-- defence_config.lua and are not repeated here.
return {
	-- false: the layer is off and the older events (engine armour is still off in config.lua) run as before O464
	enabled = true,

	-- the four resistances: each engine damage type a player meets belongs to one group. Physical is not one of them (it has
	-- armour and the physical reduction)
	groups = {
		fire = {"fire"},
		cold = {"ice", "water", "drown"},
		lightning = {"energy", "holy", "arcane"},
		chaos = {"earth", "death", "lifedrain", "manadrain"}
	},
	groupOrder = {"fire", "cold", "lightning", "chaos"},
	-- "all elements" sources (the allres modifier, a gem's all resistances, the tree's all elements) count toward these three
	allGroups = {"fire", "cold", "lightning"},

	-- the penalty on all four resistances by level. `points` is the whole penalty from `level` on (not on top of the one
	-- before). `warnFrom`: the level the player is told from. enabled = false turns the whole penalty off.
	penalty = {
		enabled = true,
		marks = {
			{level = 250, points = 30, warnFrom = 240},
			{level = 500, points = 60, warnFrom = 490}
		}
	},

	-- avoidance: the highest chance (percent) of each, for attack hits (dodge, block) and spell hits (suppression)
	dodgeCap = 75,
	suppressCap = 100,
	-- a suppressed spell hit deals this percent less
	suppressLess = 50,

	-- the engine's own item absorb (Player::blockHit, patch 0049) cannot be switched off from Lua: it has taken its share of
	-- the hit before any event runs. true: the layer divides that share out again and counts the same absorb as one of the
	-- sources of its groups. false: the engine's share is left as it is and not counted (fail-safe, not used)
	undoEngineAbsorb = true,
	-- the equipment slots the engine reads (Player::blockHit, CONST_SLOT_FIRST .. CONST_SLOT_BADGE)
	wornSlots = {1, 2, 4, 5, 6, 7, 8, 9, 10, 13},
	-- player storage (server/README.md "Storage keys", 7103080 - 7103089): +0 the last level the character was warned about
	-- the penalty for (once per level)
	storage = {lastWarned = 7103080},
	-- the monster hit the sheet shows the armour against ("armour against a typical hit"): the mean melee hit of the hunt
	-- monsters at a hunting level (server/README.md "Monster defence (O462)": 143, 481 and 807 at 100, 500 and 1,000, computed
	-- from the monster files). A straight line in log level and log hit between two rows, the last slope beyond. Display only:
	-- no hit is ever worked out from it
	typicalHit = {{level = 100, hit = 143}, {level = 500, hit = 481}, {level = 1000, hit = 807}},
	-- how long (ms) the sums of one player are kept before they are read again (the equip and level callbacks clear them)
	cacheMs = 1000
}
