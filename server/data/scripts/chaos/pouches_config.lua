-- Store pouches: tunables (pouches.lua re-reads this file on /reload scripts; server/tools/install_pouches.py reads the
-- `kinds` block for items.otb / items.xml). The engine also loads this file as a script because it lives under
-- data/scripts; it only returns a table.
--
-- Three physical containers sold in the store (Convenience): each one collects its own kind of loot from the corpses
-- the character owns, while the character carries it. Rules: pouches_core.lua; engine glue: pouches.lua; README
-- "Store pouches".
ChaosPouchesConfig = {
	-- EventCallback.onDropLoot index: after the auto seller (2), the rift key drop (2) and the loot filter snapshot
	-- (2.5), before the base autoloot (3) and the Rarity Autoloot pickup (3.5)
	dropIndex = 2.7,

	-- player storages (chaos_constants.lua, store services range 7100100 - 7100159)
	storage = {
		lootRules = 7100107, -- the Loot Pouch rules, packed (pouches_core.lua P.packRules); unset = defaults
		legacyGrant = 7100108, -- 1 = the free Loot Pouch for a former Bottomless Loot Pouch owner was given
		regrant = 7100109 -- bits (1 loot, 2 orbs, 4 keys): a pouch lost with a dropped backpack, given back at login
	},
	legacyUnlock = 7100100, -- the retired Bottomless Loot Pouch unlock (Chaos.storage.shopLootPouch), read only

	-- custom attributes on every pouch
	attr = {
		owner = "chaos_pouch_owner", -- guid of the character it belongs to (only the owner's pouch collects)
		kind = "chaos_pouch", -- "loot" | "orbs" | "keys"
		storebound = "chaos_storebound", -- 1: a store item (trade, mail, ground, player market refuse it)
		lock = "chaos_locked" -- not 0: the item lock (engine patch 0009): NPCs do not buy it, trash refuses it, stock market too
	},
	-- the value of chaos_locked on a pouch. Every lock check of the server and the engine treats any value but 0 as
	-- locked, but the client draws only a player's own lock (1, the crafting bench's Lock button) grey (game_shaderfx
	-- shaderfxlogic.lua isLocked). 2 = bound like the Everfull potions: locked, drawn in its colours. Owner report
	-- 2026-10-22: with 1 the pouches showed grey in the backpack and the purse. Older pouches get it at login (PO.rebind).
	bindLock = 2,

	-- the items: new items.otb nodes (install_pouches.py), copies of the stock bag `sourceId` (group, flags) with their
	-- own look `clientId`: our pouch art in its theme palette (client/tools/sprites/gen_store_items_art.py, appended to
	-- pair 34 by import_art_things.py with art_import/store_items.csv; client MANIFEST.md "Store item looks").
	-- `oldClientId`: the earlier look (gen_pouch_art.py, art_import/pouches.csv, 33651-33653), replaced in place by
	-- install_pouches.py. install_pouches.py --stock-looks keeps the stock bag looks.
	-- capacity = containerSize in items.xml (slots, at most 255); weight in 1/100 oz (the contents weigh as usual, except
	-- in a `weightless` one: engine src-patch 0038)
	kinds = {
		-- the Loot Bag (owner, 2026-10-13: "uma bag sem fundo que pode carregar todo o loot que o jogador recebe
		-- automaticamente"): every rule on by default (lootDefaults), the most slots a container can have (255: one byte
		-- in the protocol) and weightless (Game.setWeightlessContainer, pouches.lua at startup), so its contents never
		-- count against the character's capacity. The Auto Seller sells what is in it (autosell.lua, every 30 s).
		loot = {id = 32081, sourceId = 11242, clientId = 38608, oldClientId = 33653,
			capacity = 255, weight = 100, title = "Loot Bag", article = "a",
			name = "loot bag", plural = "loot bags", weightless = true,
			collects = "all the loot of your kills, as its rules pick (Loot Filter > Loot Bag)",
			description = "Store item: cannot be traded, sold or dropped. A bottomless bag: the loot of your kills goes " ..
				"into it while you carry it, its contents weigh nothing, and the Auto Seller sells what is in it."},
		orbs = {id = 32082, sourceId = 9775, clientId = 38609, oldClientId = 33651,
			capacity = 40, weight = 100, title = "Orbs Pouch", article = "an",
			name = "orbs pouch", plural = "orbs pouches",
			collects = "orbs, whetstones, rune shards and gems",
			description = "Store item: cannot be traded, sold or dropped. Collects orbs, whetstones, rune shards and " ..
				"gems from your kills while you carry it."},
		keys = {id = 32083, sourceId = 7343, clientId = 38610, oldClientId = 33652,
			capacity = 30, weight = 100, title = "Rift Key Pouch", article = "a",
			name = "rift key pouch", plural = "rift key pouches",
			collects = "Rift Keys, Omen Keys and omen fragments",
			description = "Store item: cannot be traded, sold or dropped. Collects Rift Keys, Omen Keys and omen " ..
				"fragments from your kills while you carry it."}
	},
	-- the specialist pouches, in priority order: an item of their kind (orbs, rune shards, gems / Rift Keys, omen items)
	-- always goes to them first, before the Loot Pouch, whatever the Loot Pouch rules say. Full: the Loot Pouch takes it
	-- only with its "overflow" rule (default on), else the backpack, else it stays in the corpse (pouches_core.lua plan)
	priority = {"orbs", "keys"},
	order = {"orbs", "keys", "loot"}, -- the order of the per-kill chat line

	-- Orbs Pouch: these ids, plus every currency entry of loot_config.lua and the loot filter's orbIds
	orbIds = {29851, 29852, 29853, 29854, 29855, 29856, 29857, 29858, 29859, -- the currency orbs
		24688, 24691, 24692, 24697, -- Erasure, Gilding, Sockets, Unmaking
		32251, 32252, 32253, 32254, 32255, 32256, 32258, 32259, 32260, -- orbs v2, the Whetstone, Ember, Crown and Void
		32051}, -- the rune shard (salvage)
	orbGems = true, -- gems (data/lib/chaos_gems.lua, 32001..32035) go to the Orbs Pouch too

	-- Rift Key Pouch: the Rift Key (item + action id, rift_config.lua key) and the omen items (rift_config.lua omen)
	riftKey = {itemId = 10155, actionId = 47401},
	omenIds = {32071, 32072},

	-- Loot Bag rule defaults (a character that never opened the settings): everything ("todo o loot", 2026-10-13);
	-- minRarity 1 = gear of any rarity. overflow: take what a full Orbs / Rift Key Pouch passes on
	lootDefaults = {list = true, gold = true, uniques = true, gear = true, minRarity = 1, supplies = true, gems = true,
		other = true, overflow = true},
	coinIds = {2148, 2152, 2160, 28872, 28873},

	-- where a pouch (or a container holding one) may be moved: the character's own inventory, or these containers
	-- (depot lockers, depot chest, depot boxes, inbox, store inbox) anywhere up its parents
	depotIds = {2589, 2590, 2591, 2592, 2594, 14404, 26052, 25453, 25454, 25455, 25456, 25457, 25458, 25459, 25460,
		25461, 25462, 25463, 25464, 25465, 25466, 25467, 25468, 25469},

	-- Loot Bag order (owner 2026-10-17): rarest first, uniques above all. Sorted when loot enters the bag and when it is
	-- opened (no timer). maxMoves: item moves per sort at most (each is a container update for the client)
	sort = {enabled = true, maxMoves = 120},

	-- the purse = the engine's store inbox: the Loot Bag may not leave it (pouches.lua onMoveItem)
	purseIds = {26052},

	scanLimit = 60, -- containers looked through to find the carried pouches (inventory, breadth first)
	fullNoticeSeconds = 60, -- "your X Pouch is full" at most this often per pouch

	-- the per-kill loot line ("Looted: 10 gold coins, 2 dragon scales, [Rare] wyrmscale helmet."): at most `maxEntries`
	-- items, then "and N more"; rarity gear from `flagRarity` (3 = Rare) and uniques are wrapped in {} (the client's
	-- loot highlight, as the Chaos bonus loot line does)
	lootLine = {maxEntries = 5, flagRarity = 3}
}
return ChaosPouchesConfig
