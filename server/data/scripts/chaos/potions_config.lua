-- Potions (server/README.md "Potions"): no empty flasks, and the first health and mana potions are Everfull.
-- Read by potions.lua, data/lib/chaos_potions.lua (also in the NPC states) and server/tools/install_potions.py.
-- The engine also loads this file as a script because it lives under data/scripts; it only sets a table.
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.
ChaosPotionsConfig = {
	-- the Everfull potions: the lowest tier of health and mana potion (the stock Health Potion 7618 and Mana Potion
	-- 7620, level 1, sold everywhere), made reusable. New items.otb nodes (install_potions.py), copies of the stock
	-- node `sourceId` with the server id `id` and the stock look (stackable like the stock node: the 10.98 client
	-- reads a count for a stackable look; one per character, count 1, never used up). Server ids after the Everfull
	-- Ration (32084). heal / mana: the stock potion's roll. price: what a potion seller asks for a replacement.
	-- The hybrid classes start on these two as well (the first spirit potion is the great one, level 80).
	-- O245: the higher tiers (tier 2+): the stock great / ultimate / supreme potion's roll, level and look, as new
	-- nodes 32261..32267. They are never sold (only tier 1 is): a character earns one from Veyra the Apothecary
	-- (materials) or buys the same swap in the store, see `upgrade` below. A tier REPLACES the item of its slot; the
	-- charges are the slot's pool (`pools`), never the tier's. line: health | mana | spirit; from: the server ids the
	-- tier is made from (the previous tier of the same line); level: the stock potion's level (a drink below it is
	-- refused, as the stock script does); pools: the charge pools a drink spends (default: the entry's `key`); a spirit
	-- potion spends one charge of EACH pool, so it costs what a health and a mana drink cost and nothing is gained
	-- by holding it next to the other two flasks. price: gold, for a tier 1 potion a seller's replacement, for a higher
	-- tier what Veyra asks to give back a lost flask (the materials' worth, upgrade.materials x her stock price).
	-- O247: the looks (clientId: client items 38645-38656 of pair 44, art by PixelLab, one per entry; install_potions.py
	-- writes it into each items.otb node, so a client without pair 44 draws nothing) and three more entries, so every line
	-- has all four tiers: the spirit potion of tier 1 (32268, made from the Everfull health potion, level 0), the supreme
	-- mana potion (32269) and the supreme spirit potion (32270), server ids 32268-32270 of the block 32268-32280. They
	-- have no stock potion: the roll is designed in proportion to the line (spirit is about 60% of the health and mana
	-- roll of its tier; supreme mana sits above ultimate mana as supreme health sits above ultimate health, x1.33).
	-- sourceId is only the node the new item copies (group, flags, attributes); the look is clientId. materialId /
	-- materialCount / materialName: what Veyra's task takes when it is not `upgrade.materials` stock potions of sourceId
	-- (the tier 1 spirit potion costs 40 health potions, the two supreme ones 60 ultimate ones). The three new entries
	-- stand last on purpose: an entry's place among the ones with a `from` is its upgrade flag (storage.upgradeBase +
	-- place), so a new entry never goes in the middle.
	everfull = {
		{key = "health", id = 32085, sourceId = 7618, clientId = 38645, article = "an", name = "everfull health potion",
			plural = "everfull health potions", weight = 180, health = {125, 175}, price = 100,
			line = "health", tier = 1, level = 0,
			description = "A flask: kills and the temple refill its charges, each drink costs one. Heals like a health " ..
				"potion. Cannot be traded or sold."},
		{key = "mana", id = 32086, sourceId = 7620, clientId = 38649, article = "an", name = "everfull mana potion",
			plural = "everfull mana potions", weight = 180, mana = {75, 125}, price = 100,
			line = "mana", tier = 1, level = 0,
			description = "A flask: kills and the temple refill its charges, each drink costs one. Restores mana like a " ..
				"mana potion. Cannot be traded or sold."},
		{key = "health", id = 32261, sourceId = 7591, clientId = 38646, article = "an", name = "everfull great health potion",
			plural = "everfull great health potions", weight = 180, health = {425, 575}, price = 7600,
			line = "health", tier = 2, level = 80, from = {32085},
			description = "A flask: kills and the temple refill its charges, each drink costs one. Heals like a great health potion (level 80). Cannot be traded or sold."},
		{key = "mana", id = 32262, sourceId = 7590, clientId = 38650, article = "an", name = "everfull great mana potion",
			plural = "everfull great mana potions", weight = 180, mana = {150, 250}, price = 4800,
			line = "mana", tier = 2, level = 80, from = {32086},
			description = "A flask: kills and the temple refill its charges, each drink costs one. Restores mana like a great mana potion (level 80). Cannot be traded or sold."},
		{key = "health", id = 32263, sourceId = 8472, clientId = 38654, article = "an", name = "everfull great spirit potion",
			plural = "everfull great spirit potions", weight = 180, health = {250, 350}, mana = {100, 200}, price = 7600,
			line = "spirit", tier = 2, level = 80, from = {32268}, pools = {"health", "mana"},
			description = "A flask: kills and the temple refill its charges. Heals and restores mana like a great spirit potion (level 80); a drink costs one health charge and one mana charge. Cannot be traded or sold."},
		{key = "health", id = 32264, sourceId = 8473, clientId = 38647, article = "an", name = "everfull ultimate health potion",
			plural = "everfull ultimate health potions", weight = 180, health = {650, 850}, price = 12400,
			line = "health", tier = 3, level = 130, from = {32261},
			description = "A flask: kills and the temple refill its charges, each drink costs one. Heals like an ultimate health potion (level 130). Cannot be traded or sold."},
		{key = "mana", id = 32265, sourceId = 26029, clientId = 38651, article = "an", name = "everfull ultimate mana potion",
			plural = "everfull ultimate mana potions", weight = 180, mana = {425, 575}, price = 14000,
			line = "mana", tier = 3, level = 130, from = {32262},
			description = "A flask: kills and the temple refill its charges, each drink costs one. Restores mana like an ultimate mana potion (level 130). Cannot be traded or sold."},
		{key = "health", id = 32266, sourceId = 26030, clientId = 38655, article = "an", name = "everfull ultimate spirit potion",
			plural = "everfull ultimate spirit potions", weight = 180, health = {420, 580}, mana = {200, 350}, price = 14000,
			line = "spirit", tier = 3, level = 130, from = {32263}, pools = {"health", "mana"},
			description = "A flask: kills and the temple refill its charges. Heals and restores mana like an ultimate spirit potion (level 130); a drink costs one health charge and one mana charge. Cannot be traded or sold."},
		{key = "health", id = 32267, sourceId = 26031, clientId = 38648, article = "an", name = "everfull supreme health potion",
			plural = "everfull supreme health potions", weight = 180, health = {875, 1125}, price = 20000,
			line = "health", tier = 4, level = 200, from = {32264},
			description = "A flask: kills and the temple refill its charges, each drink costs one. Heals like a supreme health potion (level 200). Cannot be traded or sold."},
		{key = "health", id = 32268, sourceId = 8472, clientId = 38653, article = "an", name = "everfull spirit potion",
			plural = "everfull spirit potions", weight = 180, health = {75, 105}, mana = {45, 75}, price = 1800,
			line = "spirit", tier = 1, level = 0, from = {32085}, pools = {"health", "mana"},
			materialId = 7618, materialName = "health potions",
			description = "A flask: kills and the temple refill its charges. Heals and restores mana like a small spirit potion; a drink costs one health charge and one mana charge. Cannot be traded or sold."},
		{key = "mana", id = 32269, sourceId = 26029, clientId = 38652, article = "an", name = "everfull supreme mana potion",
			plural = "everfull supreme mana potions", weight = 180, mana = {575, 775}, price = 21000,
			line = "mana", tier = 4, level = 200, from = {32265},
			materialId = 26029, materialCount = 60, materialName = "ultimate mana potions",
			description = "A flask: kills and the temple refill its charges, each drink costs one. Restores mana like a supreme mana potion (level 200). Cannot be traded or sold."},
		{key = "health", id = 32270, sourceId = 26030, clientId = 38656, article = "an", name = "everfull supreme spirit potion",
			plural = "everfull supreme spirit potions", weight = 180, health = {560, 760}, mana = {275, 475}, price = 21000,
			line = "spirit", tier = 4, level = 200, from = {32266}, pools = {"health", "mana"},
			materialId = 26030, materialCount = 60, materialName = "ultimate spirit potions",
			description = "A flask: kills and the temple refill its charges. Heals and restores mana like a supreme spirit potion (level 200); a drink costs one health charge and one mana charge. Cannot be traded or sold."}
	},

	-- the charge pools (one per kind, shared by every tier and line): the flask table below is keyed by them
	pools = {"health", "mana"},

	-- O245 upgrade tiers. A character's slot (health or mana) holds ONE Everfull item. An upgrade swaps it for the next
	-- tier of the line, keeping its bound and lock attributes; the charges are not touched. Two ways, the same swap
	-- (ChaosPotions.upgrade): Veyra the Apothecary asks `materials` stock potions of the tier (`sourceId`) from the
	-- backpack, or the store sells the swap for `coins` by tier (shop_config.lua service "everfullUpgrade").
	-- Both need the level of the stock potion and the previous tier, and each tier is done once per character.
	upgrade = {
		materials = 40,
		coins = {[1] = 20, [2] = 30, [3] = 50, [4] = 70}
	},

	-- the potion exhaust: CONDITION_EXHAUST_HEAL for the action interval - 100 ms; only the Everfull potions add it,
	-- stock potions are paced by the potion cooldown channel (patch 0042); exhaustMs is used when the engine's config
	-- cannot be read
	exhaustMs = 500,

	-- what a health or mana potion gives (owner 2026-10-22: "quanto mais lvl o personagem tem, menos as pots healam.
	-- façam elas healarem uma quantidade fixa + uma porcentagem. e elas também são afetadas por healing da skill
	-- tree"): the potion's own roll (the fixed part) + a percent of the drinker's maximum health or mana. The percent
	-- grows with the potion's level: base + perLevel x the level it needs, at most cap. Health potion (level 0) 3%,
	-- great (80) 3.8%, ultimate (130) 4.3%, level 200 5%, 500 8%, 700 10%. The tree's Healing (incrementHealth) raises
	-- both: health through the heal event like every heal, mana here (storage healingPct, written by the tree).
	-- The Everfull potions (owner 2026-10-25: "faça as everfull recuperar um fixo + uma porcentagem") take their percent
	-- from their tier instead (everfullPct[tier], any character level): a flask has few charges, so each drink is worth
	-- more than a stock potion of its level. A spirit potion gives it on health and on mana. A stock potion drunk by an
	-- empty flask keeps the level curve.
	amount = {base = 3, perLevel = 0.01, cap = 10, everfullPct = {6, 8, 10, 12}},
	sound = "Aaaah...",

	-- the old empty flasks (strong, great and small/"empty potion flask"): no potion makes them any more and no NPC
	-- sells them; players who still hold some sell them to NPCs at the old price (sell_prices.lua: 5 gold)
	flasks = {7634, 7635, 7636},
	-- the text that replaces a flask deposit line of the base data (install_potions.py)
	flaskText = "Potions no longer leave an empty flask. A potion store still buys old flasks.",

	-- player storage (free block 7102480 - 7102489, README "Storage keys"): +0 is 1 once the character got its
	-- Everfull potions (the starter kit, or the one-time grant at login of a character made before them)
	-- +1 the tree's Healing percent (passivetree_effects.lua writes it; the potion scripts run in another Lua state)
	-- +2 / +3 the charges left in the health / mana flask in hundredths of a charge (-1 = never set = full); +4 the
	-- tree's extra charges (whole charges, both flasks), +5 the tree's charge gain percent (passivetree_effects.lua
	-- writes them from the bonus names in flask.tree)
	storage = {granted = 7102480, healingPct = 7102481, healthCharges = 7102482, manaCharges = 7102483,
		treeMaxCharges = 7102484, treeGainPct = 7102485,
		-- O245: +0 .. +6 the upgrade to the tier at that place among the tiers 2+ was done (1), block 7102510 - 7102519
		upgradeBase = 7102510},

	-- Flask charges (owner 2026-10-25, O242: "do what PoE does, where potions refill as players kill monsters").
	-- The Everfull potions are flasks. Each holds `max` charges and a drink costs `cost` charges. Charges are kept in
	-- hundredths in the character's storage (the flask item carries none: a relog, a moved, split or lost item
	-- cannot change them). Never set = full.
	flask = {
		cost = 1,
		-- max charges and the share of each kill's refill the flask gets (mana is spent faster by casters)
		health = {max = 5, gain = 1.0},
		mana = {max = 8, gain = 1.5},
		-- a kill refills, in hundredths of a charge, by the monster's tier (monster_tiers.lua ChaosTierOf) ...
		perKill = {normal = 8, magic = 25, rare = 60, legendary = 150, boss = 300},
		-- ... times a factor from the monster type's base experience: xp / ref, at least min, at most max (a rat
		-- gives a quarter of the tier value, a dragon-sized monster up to three times). Bosses skip it.
		xp = {ref = 200, min = 0.25, max = 3.0},
		-- at most this much from one kill (hundredths of a charge, the tree's gain included)
		killCap = 300,
		-- party members within this many tiles (same floor) of a killer, and everybody in the damage map, get the refill
		partyRange = 30,
		-- town: in a protection zone the flasks refill to full within `safeMs`; not while the character is in a fight
		-- (CONDITION_INFIGHT), so standing in a temple tile and shooting out does not refill
		safeMs = 2000, safeNeedsNoFight = true,
		-- the tree's hooks (bonus names the passive tree may give; no node gives them yet) and their caps
		tree = {maxStat = "flaskMaxCharges", gainStat = "flaskChargeGain", maxExtra = 5, gainPctCap = 100},
		-- an empty flask drinks a carried stock potion of the same kind (the potion the flask copies) instead, so a
		-- hotkey (engine patch 0043 picks the flask first) never dead-ends; the stock potion is used up
		stockFallback = true,
		-- the message after a refill (a whole charge more) is sent at most every `noticeMs` per player
		noticeMs = 4000,
		-- a monster whose name has one of these words never refills (the training dummies; monster_tiers.lua skip)
		skipWords = {"train", "dummy"}
	},

	-- custom attributes (the store pouches' keys: pouches.lua refuses ground, mail, trade, the player market and other
	-- players' containers for chaos_storebound; engine patch 0009: NPCs never buy a chaos_locked item, the trash
	-- refuses it; death_keep.lua keeps chaos_storebound items on death)
	attr = {storebound = "chaos_storebound", lock = "chaos_locked"},
	-- the value of chaos_locked on an Everfull potion. Every lock check of the server and the engine treats any value
	-- but 0 as locked (patch 0009, salvage_core.lua K.isLocked), but the client draws only a player's own lock (1, the
	-- crafting bench's Lock button) grey (game_shaderfx). With 1 the potions showed as dark, empty-looking flasks in
	-- the backpack (live screenshot 2026-10-16); 2 keeps them bound and drawn in their red and purple. Potions given
	-- before are changed at their owner's next login (ChaosPotions.rebind).
	bindLock = 2
}
return ChaosPotionsConfig
