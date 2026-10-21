-- Crafting orbs, second set (data/lib/chaos_orbs.lua reads it; server/tools/install_orbs.py reads it too; server/README.md
-- "Crafting orbs v2"). Plain table, loaded with  ChaosOrbsConfig = dofile("data/lib/chaos_orbs_config.lua").
-- Lua 5.1 / LuaJIT and 5.3. Keep one entry per line: the installer reads this file with regular expressions.
--
-- Item ids 32251..32260 are new items.otb nodes (install_orbs.py): copies of the stock node of a client sprite that already
-- has the multi-use flag in Tibia.dat (the inlay stones and essence crystals, the moonlight crystals, the small enchanted
-- amethyst of the Void Orb: a stock gem sprite, which all have the flag), so the client needs no new sprite and Tibia.dat
-- no change. Ranges in use: gems 32001..32035, salvage 32051, omens 32071..32072, supports
-- 32101..32200; 32251..32260 are these.

return {
	-- the new orbs and the Whetstone: id, key (ChaosCrafting orb key), client sprite, name, plural, article, weight,
	-- description (items.xml)
	items = {
		{id = 32251, key = "tempering", clientId = 24483, name = "Orb of Tempering", plural = "Orbs of Tempering", article = "an", weight = 50, description = "Rerolls the values of every unbound modifier inside their tiers. Rift Key: new values."},
		{id = 32252, key = "binding", clientId = 25047, name = "Orb of Binding", plural = "Orbs of Binding", article = "an", weight = 50, description = "Binds one modifier (chosen on the bench) against orbs. Only an Orb of Erasure frees it."},
		{id = 32253, key = "excision", clientId = 25049, name = "Orb of Excision", plural = "Orbs of Excision", article = "an", weight = 50, description = "Removes the modifier you choose on the bench (a random unbound one if used directly)."},
		{id = 32254, key = "reforging", clientId = 25048, name = "Orb of Reforging", plural = "Orbs of Reforging", article = "an", weight = 50, description = "Rerolls the tier and value of one modifier you choose on the crafting bench."},
		{id = 32255, key = "ruin", clientId = 24477, name = "Orb of Ruin", plural = "Orbs of Ruin", article = "an", weight = 50, description = "A gamble on an item with a rarity: its modifiers improve or nothing happens."},
		{id = 32256, key = "whetstone", clientId = 22083, name = "Whetstone", plural = "Whetstones", article = "a", weight = 10, description = "+1% quality on an item with a rarity, up to 20% (30% from Divine rarity)."},
		{id = 32257, key = "unveiling", clientId = 25046, name = "Orb of Unveiling", plural = "Orbs of Unveiling", article = "an", weight = 50, description = "Reveals a veiled modifier: pick one of three. The choice is final."},
		{id = 32258, key = "ember", clientId = 25045, name = "Ember Orb", plural = "Ember Orbs", article = "an", weight = 50, description = "Raises one modifier you choose on the bench by exactly one tier, with a new value in the new tier."},
		{id = 32259, key = "crown", clientId = 25044, name = "Crown Orb", plural = "Crown Orbs", article = "a", weight = 50, description = "Lifts an item one rarity (Common to Legendary), keeping every modifier and adding one."},
		{id = 32260, key = "void", clientId = 678, name = "Void Orb", plural = "Void Orbs", article = "a", weight = 50, description = "Corrupts a Rare or better item for good: a gamble that often improves it, sometimes harms it. No orb changes a corrupted item."}
	},

	-- the names of the base server's currency items, changed by install_orbs.py (items.xml names and every name the base
	-- data refers to them by: monster loot lists). old = the name written by the base server.
	renames = {
		-- 29852 and 29853 were the Ember and Crown Orb of the waystone upgrade shop (no client window, no use-with): they stay
		-- shop currency as shards; the Ember Orb and Crown Orb of today are 32258 and 32259. Two rows each: a server installed
		-- before the rework knows them by the old name. 29854 the same (2026-10-21): the Void Orb of today is 32260.
		{id = 29851, name = "Orb of Awakening", plural = "Orbs of Awakening", old = "Orb of Transmutation"},
		{id = 29852, name = "Ember Shard", plural = "Ember Shards", old = "Orb of Augmentation"},
		{id = 29852, name = "Ember Shard", plural = "Ember Shards", old = "Ember Orb"},
		{id = 29853, name = "Crown Shard", plural = "Crown Shards", old = "Regal Orb"},
		{id = 29853, name = "Crown Shard", plural = "Crown Shards", old = "Crown Orb"},
		{id = 29854, name = "Void Shard", plural = "Void Shards", old = "Vaal Orb"},
		{id = 29854, name = "Void Shard", plural = "Void Shards", old = "Void Orb"},
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
	-- the side limit (once per item). ruin = 0 since the Conquest rework (2026-10-15): the worst case is that nothing
	-- happens; a ruin above 0 would bring the old "ruined for good" outcome back (items ruined before stay ruined).
	ruin = {improve = 40, nothing = 60, ruin = 0, tiers = 60},

	-- the Crown Orb: the highest rarity it lifts an item to (a stored rank: 5 = Legendary; Divine only comes from the Orb
	-- of Fate and the drops), and how many modifiers the lift adds
	crown = {maxRank = 5, add = 1},

	-- the Void Orb (2026-10-21): corrupts an item of rank minRank (4 = Rare) or better for good, then rolls one outcome by
	-- weight (they add up to 100). An outcome that cannot happen on the item falls back along `fallback` (to "sealed" at
	-- the end). Per outcome:
	--   sealed    nothing else: the item is only corrupted (locked against every orb)
	--   tier      one random unbound modifier one tier up (never past T8)
	--   implicit  a corrupted implicit modifier from the pool of the item's kind (not on the item yet), tier implicitTier
	--             or better; it takes no prefix or suffix slot
	--   quality   the item quality becomes quality (30%), above the 20% cap of Rare and Legendary
	--   socket    one socket more, up to sockets (3), past the limit of the item's kind and rarity
	--   reroll    every unbound modifier rolls a new tier (by the item level) and value
	--   rarity    one rarity up (Rare -> Legendary -> Divine, the only orb that makes Divine) and `add` modifiers more
	--   decay     the downside: one random unbound modifier `decay` tiers down (not below T1)
	-- Expected value (rough, in Crown Orb steps): on a good item the five gains (tier, implicit, quality, socket, rarity)
	-- are 59%, nothing 28%, a coin flip (reroll) 8%, a loss (decay) 5%.
	void = {
		minRank = 4,
		outcomes = {{"sealed", 28}, {"tier", 20}, {"implicit", 20}, {"quality", 8}, {"socket", 7}, {"reroll", 8},
			{"rarity", 4}, {"decay", 5}},
		fallback = {tier = "implicit", implicit = "tier", quality = "implicit", socket = "implicit", rarity = "implicit",
			reroll = "sealed", decay = "sealed"},
		implicitTier = 7,
		quality = 30,
		sockets = 3,
		add = 1,
		decay = 2,
		-- the corrupted implicit pool per item kind (ChaosItemMods.config.mods keys; a key the kind may not roll or the item
		-- has already is skipped; an empty pool falls back)
		implicits = {
			weapon = {"bossdamage", "attackspeed", "execute", "physpen", "elepen"},
			shield = {"block", "reflect", "monsterreduction"},
			armor = {"monsterreduction", "reflect", "regen", "thorns"},
			helmet = {"monsterreduction", "cdr", "manacost"},
			legs = {"monsterreduction", "thorns", "dodge"},
			boots = {"movespeed", "dodge"},
			jewel = {"bossdamage", "cdr", "manacost", "experience"},
			other = {"dot", "dodge", "cdr"},
			quiver = {"bossdamage", "physpen", "elepen"}
		}
	}

}
