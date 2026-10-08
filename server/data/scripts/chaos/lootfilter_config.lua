-- Loot filter, loot channel and loot rays: tunables (lootfilter.lua re-reads this file on /reload scripts).
-- The engine also loads this file as a script because it lives under data/scripts; it only returns a table.
ChaosLootFilterConfig = {
	-- EventCallback.onDropLoot indexes (lower runs first). Existing: 0 stock loot + "Loot of" text, 1 Chaos loot layer,
	-- 2 auto seller, 3 base autoloot, 4 loot pouch. Ours go between them, see README "Loot filter".
	snapshotIndex = 2.5, -- snapshot of the corpse + hold back autoloot-list items below the Rarity Autoloot minimum
	pickupIndex = 3.5,   -- Rarity Autoloot: pick up rarity gear / uniques that are not on the autoloot list
	finishIndex = 4.5,   -- put the held items back, send the loot row, the rare-drop lines, start the rays

	-- loot channel
	historySize = 50,          -- kills remembered per character (older ones are dropped and greyed on the client)
	reach = {x = 7, y = 5},    -- click-to-loot: same floor and within this many squares of the corpse (the visible screen)
	sweepMs = 1000,            -- one timer for rays and decay checks while anything is tracked
	decayCheckEvery = 5,       -- check tracked corpses for decay every N sweeps
	corpseAttribute = "lf_kill", -- custom attribute set on the corpse (kill id), so the corpse can be found again

	-- loot rays: a light beam over the corpse while a qualifying item is still in it
	rayUniques = true,       -- uniques (ChaosUniqueItems, custom attribute chaos_unique) get the gold/orange ray
	rayMinRarity = 5,        -- base rarity id from which items get a ray (5 = Legendary ... 15 = Transcendent)
	rayIntervalMs = 1000,    -- the beam effect is 900 ms long; resent this often while the item is in the corpse
	rayDurationS = 60,       -- stop after this long even if the item is still there
	rayVisibleTo = "looters", -- "looters": the corpse owner and party members (the players allowed to loot it); "all": everyone
	rayUniqueEffect = "loot_ray_unique",
	rayBands = { -- rarity id -> effect name (server/data/lib/chaos_fx.lua); the highest band <= rarity wins
		{from = 5, effect = "loot_ray_legendary"}, -- Legendary, Exotic: gold
		{from = 7, effect = "loot_ray_mythic"},    -- Mythic, Chaos, Eternal: red
		{from = 10, effect = "loot_ray_divine"},   -- Divine, Phantasmal, Celestial: white-blue
		{from = 13, effect = "loot_ray_cosmic"}    -- Cosmic, Abyssal, Transcendent: violet
	},

	-- item categories (equipment = rarity gear or anything worn/wielded; see lootfilter.lua itemInfo)
	coinIds = {2148, 2152, 2160, 28872, 28873},
	orbIds = {29856, 29857},   -- plus every currency entry of ChaosLootConfig and any item named "... Orb" / "Orb of ..."
	supplyWords = {"potion", "rune", "flask", "arrow", "bolt", "spear", "star", "food", "meat", "ham", "fish", "bread", "cheese", "mushroom"}
}
return ChaosLootFilterConfig
