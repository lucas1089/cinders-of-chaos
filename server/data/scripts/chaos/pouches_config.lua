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
		lock = "chaos_locked" -- 1: the item lock (engine patch 0009): NPCs do not buy it, trash refuses it, stock market too
	},

	-- the items: new items.otb nodes (install_pouches.py), copies of stock bags; client ids stay the stock ones.
	-- capacity = containerSize in items.xml (slots); weight in 1/100 oz (the contents weigh as usual)
	kinds = {
		loot = {id = 32081, sourceId = 11242, capacity = 60, weight = 100, title = "Loot Pouch", article = "a",
			name = "loot pouch", plural = "loot pouches",
			collects = "the loot its rules pick (Loot Filter > Loot Pouch)",
			description = "Store item: cannot be traded, sold or dropped. Collects the loot your Loot Pouch rules pick " ..
				"while you carry it (Loot Filter > Loot Pouch)."},
		orbs = {id = 32082, sourceId = 9775, capacity = 40, weight = 100, title = "Orbs Pouch", article = "an",
			name = "orbs pouch", plural = "orbs pouches",
			collects = "orbs, whetstones, rune shards and gems",
			description = "Store item: cannot be traded, sold or dropped. Collects orbs, whetstones, rune shards and " ..
				"gems from your kills while you carry it."},
		keys = {id = 32083, sourceId = 7343, capacity = 30, weight = 100, title = "Rift Key Pouch", article = "a",
			name = "rift key pouch", plural = "rift key pouches",
			collects = "Rift Keys, Omen Keys and omen fragments",
			description = "Store item: cannot be traded, sold or dropped. Collects Rift Keys, Omen Keys and omen " ..
				"fragments from your kills while you carry it."}
	},
	order = {"orbs", "keys", "loot"}, -- a corpse item goes to the first kind that wants it (then the next, then the backpack)

	-- Orbs Pouch: these ids, plus every currency entry of loot_config.lua and the loot filter's orbIds
	orbIds = {29851, 29852, 29853, 29854, 29855, 29856, 29857, 29858, 29859, -- the currency orbs
		24688, 24691, 24692, 24697, -- Erasure, Gilding, Sockets, Unmaking
		32251, 32252, 32253, 32254, 32255, 32256, -- orbs v2 and the Whetstone
		32051}, -- the rune shard (salvage)
	orbGems = true, -- gems (data/lib/chaos_gems.lua, 32001..32035) go to the Orbs Pouch too

	-- Rift Key Pouch: the Rift Key (item + action id, rift_config.lua key) and the omen items (rift_config.lua omen)
	riftKey = {itemId = 10155, actionId = 47401},
	omenIds = {32071, 32072},

	-- Loot Pouch rule defaults (a character that never opened the settings)
	lootDefaults = {list = true, gold = true, uniques = true, gear = false, minRarity = 5, supplies = false, gems = false,
		other = false},
	coinIds = {2148, 2152, 2160, 28872, 28873},

	-- where a pouch (or a container holding one) may be moved: the character's own inventory, or these containers
	-- (depot lockers, depot chest, depot boxes, inbox, store inbox) anywhere up its parents
	depotIds = {2589, 2590, 2591, 2592, 2594, 14404, 26052, 25453, 25454, 25455, 25456, 25457, 25458, 25459, 25460,
		25461, 25462, 25463, 25464, 25465, 25466, 25467, 25468, 25469},

	scanLimit = 60, -- containers looked through to find the carried pouches (inventory, breadth first)
	fullNoticeSeconds = 60 -- "your X Pouch is full" at most this often per pouch
}
return ChaosPouchesConfig
