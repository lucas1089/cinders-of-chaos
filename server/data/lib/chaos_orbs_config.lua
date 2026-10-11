-- Crafting orbs, second set (data/lib/chaos_orbs.lua reads it; server/tools/install_orbs.py reads it too; server/README.md
-- "Crafting orbs v2"). Plain table, loaded with  ChaosOrbsConfig = dofile("data/lib/chaos_orbs_config.lua").
-- Lua 5.1 / LuaJIT and 5.3. Keep one entry per line: the installer reads this file with regular expressions.
--
-- Item ids 32251..32257 are new items.otb nodes (install_orbs.py): copies of the stock node of a client sprite that already
-- has the multi-use flag in Tibia.dat (the inlay stones and essence crystals, the moonlight crystals), so the client needs
-- no new sprite and Tibia.dat no change. Ranges in use: gems 32001..32035, salvage 32051, omens 32071..32072, supports
-- 32101..32200; 32251..32260 are these.

return {
	-- the new orbs and the Whetstone: id, key (ChaosCrafting orb key), client sprite, name, plural, article, weight,
	-- description (items.xml)
	items = {
		{id = 32251, key = "tempering", clientId = 24483, name = "Orb of Tempering", plural = "Orbs of Tempering", article = "an", weight = 50, description = "Use it with an item with a rarity: the values of every modifier that is not bound are rolled again inside their tiers. On a Rift Key: new values."},
		{id = 32252, key = "binding", clientId = 25047, name = "Orb of Binding", plural = "Orbs of Binding", article = "an", weight = 50, description = "Binds one modifier of an item with a rarity: the Orbs of Tempering, Unmaking, Excision, Reforging and Upheaval leave it alone. Choose the modifier on the crafting bench. Only an Orb of Erasure frees it."},
		{id = 32253, key = "excision", clientId = 25049, name = "Orb of Excision", plural = "Orbs of Excision", article = "an", weight = 50, description = "Removes the modifier you choose on the crafting bench (a random one that is not bound when used directly). On a Rift Key: one modifier."},
		{id = 32254, key = "reforging", clientId = 25048, name = "Orb of Reforging", plural = "Orbs of Reforging", article = "an", weight = 50, description = "Rolls the tier (by the item level) and the value of the one modifier you choose on the crafting bench again."},
		{id = 32255, key = "ruin", clientId = 24477, name = "Orb of Ruin", plural = "Orbs of Ruin", article = "an", weight = 50, description = "A gamble for an item with a rarity: it improves (one tier more on every modifier that is not bound, or an extra modifier), nothing happens, or the item is ruined for good: no orb changes it any more."},
		{id = 32256, key = "whetstone", clientId = 22083, name = "Whetstone", plural = "Whetstones", article = "a", weight = 10, description = "Use it with an item with a rarity: +1% quality (every modifier value is multiplied), up to 20% (30% from Divine rarity)."},
		{id = 32257, key = "unveiling", clientId = 25046, name = "Orb of Unveiling", plural = "Orbs of Unveiling", article = "an", weight = 50, description = "Use it with an item that has a veiled modifier: choose one of three modifiers of the veiled pool. The choice is final."}
	},

	-- the names of the base server's currency items, changed by install_orbs.py (items.xml names and every name the base
	-- data refers to them by: monster loot lists). old = the name written by the base server.
	renames = {
		{id = 29851, name = "Orb of Awakening", plural = "Orbs of Awakening", old = "Orb of Transmutation"},
		{id = 29852, name = "Ember Orb", plural = "Ember Orbs", old = "Orb of Augmentation"},
		{id = 29853, name = "Crown Orb", plural = "Crown Orbs", old = "Regal Orb"},
		{id = 29854, name = "Void Orb", plural = "Void Orbs", old = "Vaal Orb"},
		{id = 29855, name = "Orb of Grafting", plural = "Orbs of Grafting", old = "Exalted Orb"},
		{id = 29856, name = "Orb of Upheaval", plural = "Orbs of Upheaval", old = "Chaos Orb"},
		{id = 29857, name = "Orb of Fate", plural = "Orbs of Fate", old = "Divine Orb"},
		{id = 29858, name = "Dawn Orb", plural = "Dawn Orbs", old = "Angel Orb"},
		{id = 29859, name = "Orb of Echoes", plural = "Orbs of Echoes", old = "Mirror of Kalandra"},
		{id = 24691, name = "Orb of Gilding", plural = "Orbs of Gilding", old = "Orb of Alchemy"},
		{id = 24697, name = "Orb of Unmaking", plural = "Orbs of Unmaking", old = "Orb of Annulment"},
		{id = 24688, name = "Orb of Erasure", plural = "Orbs of Erasure", old = "Orb of Scouring"}
	},

	-- the Orb of Ruin: odds in percent of its outcomes (they add up to 100), and how an improvement goes: `tiers` % one
	-- more tier on every modifier that is not bound, else (or when every modifier is at T8) one extra modifier above
	-- the side limit (once per item)
	ruin = {improve = 40, nothing = 45, ruin = 15, tiers = 60}

}
