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
	everfull = {
		{key = "health", id = 32085, sourceId = 7618, article = "an", name = "everfull health potion",
			plural = "everfull health potions", weight = 180, health = {125, 175}, price = 100,
			description = "Never runs out. Heals like a health potion, as often as the potion exhaust allows. " ..
				"Cannot be traded or sold."},
		{key = "mana", id = 32086, sourceId = 7620, article = "an", name = "everfull mana potion",
			plural = "everfull mana potions", weight = 180, mana = {75, 125}, price = 100,
			description = "Never runs out. Restores mana like a mana potion, as often as the potion exhaust allows. " ..
				"Cannot be traded or sold."}
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
	amount = {base = 3, perLevel = 0.01, cap = 10},
	sound = "Aaaah...",

	-- the old empty flasks (strong, great and small/"empty potion flask"): no potion makes them any more and no NPC
	-- sells them; players who still hold some sell them to NPCs at the old price (sell_prices.lua: 5 gold)
	flasks = {7634, 7635, 7636},
	-- the text that replaces a flask deposit line of the base data (install_potions.py)
	flaskText = "Potions no longer leave an empty flask. A potion store still buys old flasks.",

	-- player storage (free block 7102480 - 7102489, README "Storage keys"): +0 is 1 once the character got its
	-- Everfull potions (the starter kit, or the one-time grant at login of a character made before them)
	-- +1 the tree's Healing percent (passivetree_effects.lua writes it; the potion scripts run in another Lua state)
	storage = {granted = 7102480, healingPct = 7102481},

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
