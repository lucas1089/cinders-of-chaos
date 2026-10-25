-- pickups_config.lua: the shared ground-pickup framework (pickups.lua, pickups_core.lua): the items, where they land,
-- how they glow and fade. Used by the health and mana globes (globes.lua, globes_config.lua) and the Ember Blessings'
-- ember (blessings.lua, blessings_config.lua `pickup`). Plain table, loaded as
-- ChaosPickupsConfig = dofile("data/scripts/chaos/pickups_config.lua"). Lua 5.1 / LuaJIT and Lua 5.3 compatible.
-- server/tools/install_pickups.py reads `items` from this file (items.otb nodes and items.xml entries).
-- See server/README.md "Ground pickups and globes".
return {
	enabled = true,

	-- The items. id: the new server id (32087 is left to the potions); sourceId: copy the look of that stock node, or
	-- clientId: the look of the stock node with that client id; stackable = true forces the flag (a stackable client
	-- look needs it), nil copies the stock flags. The nodes are never pickupable or moveable (install_pickups.py).
	-- glow: the magic effect that pulses on the tile while the pickup lies there.
	items = {
		{key = "health_globe", id = 32088, sourceId = 7618, article = "a", name = "health globe", plural = "health globes",
			weight = 0, glow = "CONST_ME_MAGIC_RED", take = "CONST_ME_HEARTS",
			description = "A red glowing orb. Step on it to restore health. It fades quickly."},
		{key = "mana_globe", id = 32089, sourceId = 7620, article = "a", name = "mana globe", plural = "mana globes",
			weight = 0, glow = "CONST_ME_MAGIC_BLUE", take = "CONST_ME_STUN",
			description = "A blue glowing orb. Step on it to restore mana. It fades quickly."},
		{key = "ember", id = 32090, clientId = 25045, stackable = true, article = "an", name = "ember",
			plural = "embers", weight = 0, glow = "CONST_ME_FIREAREA", take = "CONST_ME_HITBYFIRE",
			description = "A dying ember. Step on it to be blessed. It goes out quickly."}
	},

	-- failsafe: the items.xml entries decay after this many seconds (item:decay() at creation), so an item left by a
	-- crash cannot stay. The real lifetime is the pickup's own (globes_config.lua, blessings_config.lua `pickup`).
	failsafeSeconds = 90,

	-- the glow effect repeats this often; the fade effect plays where a pickup runs out
	pulseMs = 1500,
	fadeEffect = "CONST_ME_POFF",
	-- the look-out for lifetimes, every this many ms
	tickMs = 500,

	-- tiles to try around the corpse, in order (the corpse tile first); a tile needs ground, no solid block and no
	-- pickup of ours on it. No tile: no pickup.
	placeOffsets = {
		{0, 0}, {1, 0}, {-1, 0}, {0, 1}, {0, -1}, {1, 1}, {-1, -1}, {1, -1}, {-1, 1},
		{2, 0}, {-2, 0}, {0, 2}, {0, -2}
	},

	-- Where nothing drops (read by the globes; the blessings keep their own PvP rule). instances: keys of
	-- Chaos.registerInstance (arena, battleground, siege, the Infinity Tower ...) in which the player gets no globe;
	-- boxes: {x1, y1, x2, y2, z} for places that are no registered instance (the Tower Defense of the base script: add
	-- its room here, the server has no box for it). ChaosBlessings.pvpPlace (PvP-zone tiles too) is checked as well.
	blocked = {
		instances = {arena = true, battleground = true, siege = true, tower = true, trials = true, tutorial = true},
		boxes = {}
	},

	-- messages (Chaos.t keys, pt-BR in i18n_strings.lua)
	notYours = "This is not meant for you."
}
