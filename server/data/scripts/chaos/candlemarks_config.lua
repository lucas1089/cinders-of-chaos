-- Candlemarks: a currency for time online. Every online character earns one Candlemark for every 30 minutes online
-- (at most 2 characters per IP address at the same time); spent in the Candlemark shop on pocket boss charges, common
-- crafting orbs, gems, supplies and other help to progress. Every number of the system is here. Engine part:
-- candlemarks.lua; pure logic: candlemarks_core.lua (tests: server/tests/candlemarks_test.lua); NPC: data/npc/Osric the
-- Chandler.xml (server/tools/install_candlemarks.py); tables: server/sql/chaos_candlemarks.sql; client
-- game_candlemarks (menu Economy > Candlemarks); overview: server/README.md "Candlemarks".
-- Prices, limits and the IP rule: decided 2026-10-15 (docs/OWNER_TODO.md "Decided").
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible. Edit here, then /reload scripts (or restart).

local C = {}

C.enabled = true
C.opcode = 176 -- ChaosOpcodes.candlemarks (chaos_constants.lua); client game_candlemarks
C.requestMs = 300 -- one window request per player per 300 ms (Chaos.limited)
C.buyMs = 1000 -- one purchase per player per second
C.staffGroup = 4 -- /candlemarks <name> (look) needs this group; give / take need Chaos.economyMinGroup (5)

-- player storages 7102460 - 7102469 (server/README.md "Storage keys"):
--   +0 the id of the last purchase delivered to this character (saved together with the items: the crash-safe
--      delivery mark, candlemarks.lua "Buying")
--   +1 .. +9 free
-- (the progress to the next coin is a row per character in chaos_candlemark_progress, kept across relogs)
C.storage = 7102460

-- ------------------------------------------------------------------ earning (owner decision 2026-10-15)
-- Every online character counts: no activity or AFK rule, no one-character-per-account rule; training online counts
-- too (offline training is logged out, so it does not). Each character has its own progress (a database row, kept
-- across relogs); a full block of blockMinutes gives one coin to the ACCOUNT balance, which every character of the
-- account shares and spends. Several characters of one account online at once each add coins to it.
C.blockMinutes = 30
C.tickSeconds = 60 -- online time is added once a minute
C.maxTickSeconds = 120 -- one tick never credits more than this (a server stall)
C.weekResetHour = 6 -- the weekly limits reset on Monday at this hour (the bounty board's week)
C.dayResetHour = 6 -- the day of earn.dailyCap turns at this hour (server time)

-- Who earns, checked every tick. maxPerIp: at most this many characters per IP address earn at the same time: the
-- earliest logins of that IP (then the lower character id); when one logs out, the next one in that order starts
-- earning at the next tick. The others keep their progress, frozen. A character without a connection (IP 0: lost
-- connection, still in the world) is not limited. Staff (group >= staffGroup) never earn. minLevel: the lowest level
-- that earns. dailyCap: coins per account and day (0 = no cap).
C.earn = {
	maxPerIp = 2,
	minLevel = 1,
	dailyCap = 0
}

-- ------------------------------------------------------------------ the NPC
-- Osric the Chandler next to these towns' temples (startup, npc_place.lua). The window opens anywhere (the game menu,
-- Economy > Candlemarks, the counter, or Osric's trade), but buyNearNpc (owner 2026-10-15): a purchase needs Osric
-- within `range` tiles on the same floor (the server checks).
C.npc = {
	name = "Osric the Chandler", range = 3, towns = {1, 2, 3, 4, 5}, delayMs = 3500, buyNearNpc = true,
	offsets = {{-4, -3}, {4, -3}, {-4, 3}, {4, 3}, {-3, -5}, {3, 5}, {-6, -2}, {6, -2}, {-6, 2}, {6, 2}}
}

-- ------------------------------------------------------------------ the shop
-- Item ids the shop may never sell: the chase orbs (Orb of Echoes, Orb of Fate, Dawn Orb), the Orb of Ruin and the Void Orb.
-- candlemarks_core.lua K.validate refuses them; tests/candlemarks_test.lua checks the list.
C.forbiddenIds = {29859, 29857, 29858, 32255, 32260}

-- Offers, in window order. Every offer has a weekly limit per account (purchases of the offer, or of every offer
-- sharing its `limit` key) and a minimum character level. price = Candlemarks. Kinds:
--   item        items = {{id, count}, ...}: into the backpack, the rest to the inbox
--   gem         a gem of `tier` (1 Chipped .. 5 Perfect) of a random type (data/lib/chaos_gems_config.lua ids)
--   pocketboss  `charges` pocket boss charges: one offer per boss ChaosPocketBoss.bosses() lists, sharing the limit;
--               shown only while ChaosPocketBoss.addCharges and .bosses exist
--   call        call = {"GlobalTable", "function", args...}: GlobalTable.function(player, args...) must return true;
--               shown only while that function exists (the rested XP vial, the bounty and task rerolls are
--               written against the APIs other systems are adding; they light up when those exist)
--   cosmetic    cosmetic = key of cosmetics_config.lua: ChaosCosmetics.grant(account, key, "candlemarks"), once per account
-- icon = a server item id shown in the window (item kinds show their first item, gems the gem of their tier).
-- enabled = false hides an offer.
-- Prices: about 2.5x an active-time-only design, because every online character earns, idle or not, up to 2 per IP:
-- one character online 4 hours a day earns 56 a week, two characters 112 (docs/OWNER_TODO.md "Candlemarks").
C.offers = {
	-- progress: pocket bosses
	{key = "pocket_charge", kind = "pocketboss", charges = 1, price = 15, weekly = 3, minLevel = 50, icon = 2229,
		name = "Pocket Boss Charge", desc = "One extra charge for the pocket boss you choose."},
	-- crafting: the common orbs, never the chase ones
	{key = "orb_awakening", kind = "item", items = {{29851, 3}}, price = 5, weekly = 10, minLevel = 20,
		name = "3 Orbs of Awakening", desc = "Common crafting orbs."},
	{key = "orb_ember", kind = "item", items = {{32258, 1}}, price = 10, weekly = 5, minLevel = 40,
		name = "Ember Orb", desc = "Raises a modifier you choose by one tier."},
	{key = "orb_crown", kind = "item", items = {{32259, 1}}, price = 25, weekly = 2, minLevel = 80,
		name = "Crown Orb", desc = "Lifts an item one rarity, up to Legendary."},
	{key = "orb_tempering", kind = "item", items = {{32251, 1}}, price = 8, weekly = 5, minLevel = 40,
		name = "Orb of Tempering", desc = "Rolls the values of an item's modifiers again."},
	{key = "orb_unmaking", kind = "item", items = {{24697, 1}}, price = 12, weekly = 3, minLevel = 60,
		name = "Orb of Unmaking", desc = "A crafting orb for the patient."},
	{key = "orb_grafting", kind = "item", items = {{29855, 1}}, price = 30, weekly = 1, minLevel = 100,
		name = "Orb of Grafting", desc = "A rare crafting orb, once a week."},
	{key = "whetstone", kind = "item", items = {{32256, 2}}, price = 8, weekly = 5, minLevel = 40,
		name = "2 Whetstones", desc = "Raise the quality of an item."},
	-- gems and shards
	{key = "gem_chipped", kind = "gem", tier = 1, price = 3, weekly = 10, minLevel = 20,
		name = "Chipped Gem", desc = "A random gem of the lowest quality."},
	{key = "gem_flawed", kind = "gem", tier = 2, price = 8, weekly = 5, minLevel = 50,
		name = "Flawed Gem", desc = "A random gem of the second quality."},
	{key = "rune_shards", kind = "item", items = {{32051, 10}}, price = 5, weekly = 5, minLevel = 20,
		name = "10 Rune Shards", desc = "Salvage material."},
	-- supplies at modest value (NPC gold worth about 4,750 / 7,750 / 10,750), 5 bundles a week in all
	{key = "supplies_1", kind = "item", items = {{7618, 50}, {7620, 50}}, price = 3, weekly = 5, minLevel = 8,
		limit = "supplies", name = "Hunting Supplies I", desc = "50 health and 50 mana potions."},
	{key = "supplies_2", kind = "item", items = {{7591, 25}, {7590, 25}}, price = 5, weekly = 5, minLevel = 80,
		limit = "supplies", name = "Hunting Supplies II", desc = "25 great health and 25 great mana potions."},
	{key = "supplies_3", kind = "item", items = {{8473, 25}, {8472, 25}}, price = 8, weekly = 5, minLevel = 130,
		limit = "supplies", name = "Hunting Supplies III", desc = "25 ultimate health and 25 great spirit potions."},
	-- better potions and bigger bundles (owner 2026-10-23: "coloque pots melhores a venda ... e packs maiores
	-- também"): tier IV for level 200 (supreme health 500 and ultimate mana 350 gold at the NPC: 21,250, about 1,770 a
	-- mark like tier I); a crate is four bundles of its tier for three bundles' price. Same weekly limit of 5.
	{key = "supplies_4", kind = "item", items = {{26031, 25}, {26029, 25}}, price = 12, weekly = 5, minLevel = 200,
		limit = "supplies", name = "Hunting Supplies IV", desc = "25 supreme health and 25 ultimate mana potions."},
	{key = "supplies_crate_1", kind = "item", items = {{7618, 100}, {7618, 100}, {7620, 100}, {7620, 100}}, price = 9, weekly = 5, minLevel = 8,
		limit = "supplies", name = "Supply Crate I", desc = "200 health and 200 mana potions."},
	{key = "supplies_crate_2", kind = "item", items = {{7591, 100}, {7590, 100}}, price = 15, weekly = 5, minLevel = 80,
		limit = "supplies", name = "Supply Crate II", desc = "100 great health and 100 great mana potions."},
	{key = "supplies_crate_3", kind = "item", items = {{8473, 100}, {8472, 100}}, price = 24, weekly = 5, minLevel = 130,
		limit = "supplies", name = "Supply Crate III", desc = "100 ultimate health and 100 great spirit potions."},
	{key = "supplies_crate_4", kind = "item", items = {{26031, 100}, {26029, 100}}, price = 36, weekly = 5,
		minLevel = 200, limit = "supplies", name = "Supply Crate IV",
		desc = "100 supreme health and 100 ultimate mana potions."},
	-- other systems' help, shown once their API exists
	{key = "rested_vial", kind = "call", call = {"ChaosRested", "addVials", 1}, price = 10, weekly = 3, minLevel = 20,
		icon = 7440, name = "Rested Vial", desc = "Stored rested experience for your next hunt."},
	{key = "bounty_reroll", kind = "call", call = {"ChaosBounty", "addRerolls", 1}, price = 5, weekly = 3, minLevel = 30,
		icon = 1949, name = "Bounty Reroll", desc = "Draw one bounty contract again."},
	{key = "task_reroll", kind = "call", call = {"ChaosBestiary", "addRerolls", 1}, price = 5, weekly = 3, minLevel = 30,
		icon = 1950, name = "Kill Task Reroll", desc = "Draw one kill task again."},
	-- cosmetics (owner 2026-10-15): our own, never sold for Chaos Coins (cosmetics_config.lua source "candlemarks"),
	-- once per account (the weekly limit of 1 never matters: owned is owned)
	{key = "cos_candleseal", kind = "cosmetic", cosmetic = "kill_candleseal", price = 150, weekly = 1, minLevel = 1,
		icon = 2050, name = "Candle Seal", desc = "A kill effect: a seal of candlelight. For the account."},
	{key = "cos_candlelight", kind = "cosmetic", cosmetic = "chat_candlelight", price = 120, weekly = 1, minLevel = 1,
		icon = 2047, name = "Candlelight Name", desc = "Your name in chat in candlelight. For the account."},
	{key = "cos_tallow", kind = "cosmetic", cosmetic = "loot_tallow", price = 100, weekly = 1, minLevel = 1,
		icon = 2048, name = "Tallow Labels", desc = "Loot labels on warm tallow. For the account."}
}

-- every refusal and message, in English; the pt-BR texts are in i18n_strings.lua (tests/candlemarks_test.lua checks)
C.messages = {
	disabled = "Candlemarks are switched off.",
	unknown = "That offer is not in the shop.",
	level = "You need level %d for that.",
	balance = "You need %d Candlemarks for that.",
	weekly = "Weekly limit reached for that offer.",
	owned = "Your account already has that.",
	unavailable = "That offer is not available right now.",
	busy = "One purchase at a time.",
	npc = "Visit Osric the Chandler to buy (in the teleport room's market).",
	failed = "The purchase could not be written down. Nothing was taken; try again.",
	bought = "Bought %s for %d Candlemarks.",
	inbox = "Your backpack is full: the rest went to your inbox.",
	earned = "You earned a Candlemark. Your account has %d.",
	earnedCap = "Your account reached today's Candlemark limit."
}

return C
