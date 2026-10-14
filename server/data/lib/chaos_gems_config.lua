-- Gems and sockets: every number (data/lib/chaos_gems.lua reads it; server/README.md "Gems and sockets").
-- Plain table, loaded with  ChaosGemsConfig = dofile("data/lib/chaos_gems_config.lua"). Lua 5.1 / LuaJIT and 5.3.
--
-- Item ids: one server id per gem type and tier, 32001..32035 = 32000 + (type - 1) * 5 + tier. They are new items.otb
-- nodes (server/tools/install_gems.py) that reuse the client sprites of the stock small gems (clientId; clientIdHigh
-- from Flawless up: the small enchanted gems), so the client needs no new sprite; only the small diamond (client 3028)
-- needs the multi-use flag (client/tools/sprites/set_multiuse.py). Being their own server ids, gems stack per tier,
-- NPCs never buy them as stock gems, and nothing in the stock data knows them.
-- The dark tile set takes server ids 30484..30557 (client id + 3000); 32001..32035 stays clear of it.

return {
	firstId = 32001,
	highFrom = 4, -- tiers from here on use clientIdHigh when the type has one
	-- our own gem looks (client/tools/sprites/gen_gem_art.py, art_import/gems.csv): client ids lookFirst.. =
	-- lookFirst + (type - 1) * 5 + tier - 1 (33905..33939, after the Everfull Ration 33904), one animated look per gem
	-- and tier. Not in a published pair yet: ownLook = false keeps the stock sprites above. Once a pair with them is on
	-- windows-assets: ownLook = true, then install_gems.py again (server/README.md "Gems and sockets").
	ownLook = false,
	lookFirst = 33905,

	-- the Orb of Sockets: an unused stackable use-with rune stone (no items.xml entry; install_gems.py names it)
	socketOrb = {id = 24692, name = "Orb of Sockets",
		text = "Rolls a new number of sockets for a piece of gear (gems already socketed stay).",
		price = 25}, -- Chaos store, Chaos Currency

	-- the qualities, lowest first: three of one combine into one of the next
	tiers = {"Chipped", "Flawed", "Polished", "Flawless", "Perfect"},

	-- slot groups: weapon (weapons), armour (helmets, armours, legs, boots, shields, gloves, belts...), jewel (amulets
	-- and rings). Each gem type gives one effect per group, value per tier (index = tier).
	-- Rule: an offensive theme (critical, life leech, attack speed) goes to weapons and the gem's element damage to
	-- jewellery; otherwise the element damage goes to weapons and the theme to armour; the rest is a resistance.
	types = {
		{key = "ruby", name = "ruby", plural = "rubies", clientId = 3030, clientIdHigh = 676, color = "#ff5a4a",
			weapon = {effect = "dmg_fire", values = {2, 4, 6, 9, 12}},
			armour = {effect = "maxhealth", values = {20, 45, 80, 130, 200}},
			jewel = {effect = "res_fire", values = {2, 3, 4, 6, 8}}},
		{key = "sapphire", name = "sapphire", plural = "sapphires", clientId = 3029, clientIdHigh = 675, color = "#5a8cff",
			weapon = {effect = "dmg_ice", values = {2, 4, 6, 9, 12}},
			armour = {effect = "maxmana", values = {15, 35, 60, 100, 150}},
			jewel = {effect = "res_ice", values = {2, 3, 4, 6, 8}}},
		{key = "emerald", name = "emerald", plural = "emeralds", clientId = 3032, clientIdHigh = 677, color = "#4fd06a",
			weapon = {effect = "dmg_earth", values = {2, 4, 6, 9, 12}},
			armour = {effect = "movespeed", values = {1, 1, 2, 2, 3}},
			jewel = {effect = "res_earth", values = {2, 3, 4, 6, 8}}},
		{key = "amethyst", name = "amethyst", plural = "amethysts", clientId = 3033, clientIdHigh = 678, color = "#b070ff",
			weapon = {effect = "crit", values = {1, 1, 2, 3, 3}, values2 = {5, 10, 15, 20, 25}},
			armour = {effect = "res_death", values = {2, 3, 4, 6, 8}},
			jewel = {effect = "dmg_death", values = {2, 4, 6, 9, 12}}},
		{key = "topaz", name = "topaz", plural = "topazes", clientId = 9057, color = "#f6cf4a",
			weapon = {effect = "attackspeed", values = {1, 2, 3, 4, 5}},
			armour = {effect = "res_energy", values = {2, 3, 4, 6, 8}},
			jewel = {effect = "dmg_energy", values = {2, 4, 6, 9, 12}}},
		{key = "diamond", name = "diamond", plural = "diamonds", clientId = 3028, color = "#e8f4ff",
			weapon = {effect = "dmg_holy", values = {2, 4, 6, 9, 12}},
			armour = {effect = "res_all", values = {1, 1, 2, 3, 4}},
			jewel = {effect = "res_holy", values = {2, 3, 4, 6, 8}}},
		{key = "onyx", name = "onyx", plural = "onyxes", clientId = 22193, color = "#9a8c8c",
			weapon = {effect = "leech", values = {1, 3, 4, 5, 7}, values2 = {1, 2, 3, 4, 5}},
			armour = {effect = "res_physical", values = {1, 1, 2, 3, 4}},
			jewel = {effect = "dmg_physical", values = {1, 2, 3, 4, 6}}}
	},

	-- effects: label, format (pct "+N%", flat "+N", pair "+N% / +M%"), the most a character gets from all gems (and,
	-- for movespeed, from the Chaos item modifier of the same name too: chaos_item_mods.lua caps it at 12)
	effects = {
		dmg_fire = {label = "Fire Damage", fmt = "pct", cap = 40},
		dmg_ice = {label = "Ice Damage", fmt = "pct", cap = 40},
		dmg_earth = {label = "Earth Damage", fmt = "pct", cap = 40},
		dmg_death = {label = "Death Damage", fmt = "pct", cap = 40},
		dmg_energy = {label = "Energy Damage", fmt = "pct", cap = 40},
		dmg_holy = {label = "Holy Damage", fmt = "pct", cap = 40},
		dmg_physical = {label = "Physical Damage", fmt = "pct", cap = 12},
		res_fire = {label = "Fire Resistance", fmt = "pct", cap = 30},
		res_ice = {label = "Ice Resistance", fmt = "pct", cap = 30},
		res_earth = {label = "Earth Resistance", fmt = "pct", cap = 30},
		res_death = {label = "Death Resistance", fmt = "pct", cap = 30},
		res_energy = {label = "Energy Resistance", fmt = "pct", cap = 30},
		res_holy = {label = "Holy Resistance", fmt = "pct", cap = 30},
		res_physical = {label = "Physical Resistance", fmt = "pct", cap = 10},
		-- every elemental resistance above (not physical), under their caps
		res_all = {label = "Elemental Resistances", fmt = "pct", spread = {"res_fire", "res_ice", "res_earth", "res_death",
			"res_energy", "res_holy"}},
		maxhealth = {label = "Max Health", fmt = "flat", cap = 2000},
		maxmana = {label = "Max Mana", fmt = "flat", cap = 1500},
		movespeed = {label = "Movement Speed", fmt = "pct", cap = 12},
		-- engine critical hit: chance (%) and extra damage (%) as a pair
		crit = {label = "Critical Chance", label2 = "Critical Hit", fmt = "pair", cap = 10, cap2 = 75},
		-- engine life leech: chance (%) to leech amount (%) of the damage
		leech = {label = "Life Leech Chance", label2 = "Life Leech Amount", fmt = "pair", cap = 20, cap2 = 15},
		-- local to the weapon, like the Attack Speed modifier: the weapon's attack interval (mod + gems, at most this)
		attackspeed = {label = "Attack Speed", fmt = "pct", cap = 20}
	},

	-- ------------------------------------------------------------------ sockets
	-- the most sockets per kind of item (chaos_item_mods.lua kinds) and per rarity tier (tier = ceil(rarity / 3):
	-- index 1 = no rarity, 2 = Common-Rare, 3 = Epic-Exotic, 4 = Mythic-Eternal, 5 = Divine-Celestial,
	-- 6 = Cosmic-Transcendent); an item gets the lower of the two. Two-handed weapons: weapon2h.
	kindMax = {weapon = 2, weapon2h = 3, armor = 3, shield = 2, helmet = 2, legs = 2, boots = 1, jewel = 1, other = 1},
	rarityMax = {1, 1, 2, 2, 3, 3},
	-- drops (the Chaos loot layer, on gear with a rarity): weights of 0, 1, 2, 3 sockets per rarity tier (index 1 =
	-- Common-Rare ... 5 = Cosmic-Transcendent), then capped by the item's maximum
	dropWeights = {
		{80, 18, 2, 0},
		{60, 30, 9, 1},
		{45, 35, 16, 4},
		{35, 38, 20, 7},
		{25, 40, 25, 10}
	},
	-- the Orb of Sockets: a new number of sockets, 1 .. the item's maximum, with these weights (index = sockets)
	orbWeights = {50, 35, 15},
	-- uniques: a fixed number of sockets (no orb changes it; gems may be socketed and removed)
	uniqueSockets = 1,

	-- ------------------------------------------------------------------ removing a gem (crafting bench)
	-- "Remove": the gem comes back for this much gold (bank first, then the backpack), by tier; "Shatter": free, the
	-- gem is destroyed. Both are gem / gold sinks, like the 3-to-1 combining.
	removeCost = {2000, 6000, 20000, 60000, 200000},

	-- ------------------------------------------------------------------ drops (the Chaos loot layer, loot.lua)
	-- chance per kill in 1/10000 by monster tier, x the loot layer's rate (events, buffs, rift quantity) x item find
	drop = {
		chance = {normal = 25, magic = 150, rare = 500, legendary = 1500, boss = 3000},
		-- gem tier weights by monster level: {up to level, {tier 1, 2, 3, 4, 5}}; a monster without a level uses the
		-- killer's level
		levelWeights = {
			{49, {85, 15, 0, 0, 0}},
			{149, {60, 32, 8, 0, 0}},
			{299, {35, 40, 20, 5, 0}},
			{599, {15, 35, 35, 13, 2}},
			{999999, {5, 25, 40, 24, 6}}
		},
		-- legendary monsters and bosses: percent chance that the gem is one tier better (Perfect stays Perfect)
		tierUp = {legendary = 25, boss = 40}
	},

	-- ------------------------------------------------------------------ rewards (bounty.lua, rift.lua, worldboss.lua)
	-- count = gems per reward (a fraction is the chance of one more), chance = percent that there is any, weights =
	-- tier weights (1 .. 5); the gem type is random
	rewards = {
		-- a finished contract, by contract type; tier weights by the band's index (bounty_config.lua bands 1..6)
		bounty = {chance = {hunt = 30, elite = 50, boss = 100}, count = 1,
			bandWeights = {{80, 20, 0, 0, 0}, {50, 40, 10, 0, 0}, {25, 45, 25, 5, 0}, {10, 35, 40, 13, 2},
				{0, 20, 45, 28, 7}, {0, 10, 40, 38, 12}}},
		-- the weekly bounty chest: this many gems of the band's weights
		bountyWeekly = {count = 2},
		-- the rift chest: base + perTier x tier gems, tier weights by rift tier {up to tier, weights}
		rift = {base = 1, perTier = 0.2,
			tierWeights = {{3, {50, 40, 10, 0, 0}}, {6, {20, 45, 30, 5, 0}}, {10, {5, 30, 45, 17, 3}},
				{999, {0, 15, 45, 30, 10}}}},
		-- every eligible world boss participant: count gems (+ share x countShare), these tier weights
		worldboss = {count = 2, countShare = 4, weights = {0, 10, 45, 35, 10}}
	}
}
