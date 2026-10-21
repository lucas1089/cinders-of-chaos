-- Gentle deaths (gentledeath.lua, gentledeath_core.lua; server/README.md "Gentle deaths and blessings"): every number. Plain table,
-- loaded with
--     ChaosGentleDeathConfig = dofile("data/scripts/chaos/gentledeath_config.lua")
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible. Edit here, then restart (or /reload scripts).
--
-- Owner goal 2026-10-15: noob friendly. A death of a new character costs little or no experience, and the first death
-- of each day costs half for everyone. Owner decision 2026-10-15 (death and blessings): nobody ever loses items on death
-- (equipment, backpack, containers) except with a red or black skull, where the base rules apply; experience is lost
-- by the base formula (a percentage, reduced by the blessings as in the base rules), softened by the curve below. Skills
-- and magic level follow the engine's own rules. The classic blessings: !bless buys the missing ones for gold, and the
-- store's Eternal Blessing keeps them for good on one character.
return {
	enabled = true,

	-- player storages 7102740 - 7102744 (server/README.md "Storage keys"): +0 the day (YYYYMMDD) of the last death
	-- that used the first-death-of-the-day discount, +1 the Eternal Blessing (1 = owned)
	storage = {base = 7102740, last = 7102744, firstDeathDay = 0, eternal = 1},

	-- the day turns at this hour (server time), like the bounty board and the Ember Cache
	resetHour = 6,

	-- experience loss x this factor by level, linear between the points, flat beyond the ends.
	-- Levels 1-30 lose nothing, 100 loses half, 250 and up the full loss.
	xpLoss = {
		{level = 1, mult = 0},
		{level = 30, mult = 0},
		{level = 100, mult = 0.5},
		{level = 250, mult = 1}
	},

	-- the first death of each day: x this factor on top (1 = off)
	firstDeathOfDay = 0.5,

	-- true: no equipped item, backpack or container drops on death, at any level. Never with a red or black skull (the
	-- base rules then), never for a Hardcore season character (its own rule: season_modes.lua, the fall). The base
	-- droploot.lua returns before the item loss (patch_base_events.py step 19), so an amulet of loss is not used up.
	keepItems = true,

	-- true: the eased loss is told to the player (in the player's language)
	tell = true,

	-- the classic blessings (the five base ones; not the Ember Blessings of blessings.lua). Ids: Chaos.shopServices.blessings in
	-- chaos_constants.lua (1-5).
	bless = {
		-- !bless: buys the missing blessings for gold (carried, then the bank), anywhere but in combat (battle sign or
		-- protection zone lock). Owner exception 2026-10-15 to the no-commands rule.
		words = "!bless",
		-- the price of ONE blessing at a level: the base NPC price (2000 to level 30, +200 a level to 20000 at level 120),
		-- then +100 a level after 120, at most maxEach (100000 from level 920). Numbers to review: docs/OWNER_TODO.md.
		baseCost = 2000, fromLevel = 30, perLevel = 200, midCap = 20000, lateFrom = 120, latePerLevel = 100,
		maxEach = 100000,
		-- one !bless per player per this many ms
		rateMs = 2000
	},

	-- the store's Eternal Blessing (shop_config.lua Blessings, service "eternalBlessing"): one purchase per character keeps
	-- all five blessings for good (given back at every login after a death). Not for season characters (seasonBlocked).
	eternal = {service = "eternalBlessing"}
}
