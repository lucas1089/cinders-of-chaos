-- loot_config.lua: every number of the Chaos loot layer (loot.lua). Plain table, loaded with
--     ChaosLootConfig = dofile("data/scripts/chaos/loot_config.lua")
-- Tiers: "normal", "magic", "rare", "legendary", "boss" (as produced by monster_tiers.lua).
-- Lua 5.1 / LuaJIT compatible. Edit here, then /reload scripts (or restart).

return {
	-- EventCallback priority (index). Stock default_onDropLoot = 0 (register() without index),
	-- creaturescripts/autoloot.lua = 3. Must be > 0 (after the stock pass) and < 3 (before autoloot,
	-- otherwise autolooters never receive the extra items). Do not change unless you know why.
	priority = 1,
	-- pack combat (pace.lua): the empty corpse check runs at this index, after every step that takes items out of the
	-- corpse (pouches 2.7, base autoloot 3, Rarity Autoloot 3.5, professions 4, loot filter finish 4.5), so a corpse
	-- that the autoloot emptied gets the short decay too
	emptyCorpseIndex = 99,

	-- global hook. A number, or function(ctx) returning a number; ctx = {tier=, monster=, player=}.
	-- Multiplies the chance of the EXTRA rolls (not their stack counts) and the currency chances.
	-- (Unique items are only scaled by tierMult and item find.)
	-- the Loot Frenzy event (events_schedule.lua) raises it on its days, the World Loot buff from the store
	-- (shop_services.lua) while it runs
	rateMult = function(ctx)
		local event = ChaosEvents and ChaosEvents.bonus("loot") or 1
		-- the World Loot buff skips season characters (ctx.player, the corpse owner)
		local buff = ChaosShopServices and ChaosShopServices.buffMult and ChaosShopServices.buffMult("loot", ctx and ctx.player) or 1
		local rift = ChaosRift and ChaosRift.lootMult and ChaosRift.lootMult(ctx) or 1 -- the rift's Quantity bonus
		local world = ChaosWorldEvents and ChaosWorldEvents.lootMult and ChaosWorldEvents.lootMult(ctx) or 1 -- Golden Hour (worldevents.lua)
		-- community goal loot stage and the week's family modifier (community.lua); 1 when neither is active
		local community = ChaosCommunity and ChaosCommunity.lootMult and ChaosCommunity.lootMult(ctx) or 1
		-- the Scorched Marches (pvpzone.lua): its monsters drop more; the Cinder Shrine holder's faction-wide loot buff
		local marches = ChaosPvpZone and ChaosPvpZone.lootMult and ChaosPvpZone.lootMult(ctx) or 1
		-- the Ember of Plenty blessing of the corpse owner (blessings.lua); 1 when none
		local blessing = ChaosBlessings and ChaosBlessings.mult and ChaosBlessings.mult(ctx and ctx.player, "loot") or 1
		return event * buff * rift * world * community * marches * blessing
	end,
	-- cap on the final rate (rateMult, guild perk wrapper included; loot.lua clamps it). The bonuses multiply: all at
	-- once came to ~8-10x. The rift's own Quantity rules still apply, under this cap.
	maxRate = 3.0,

	-- player storage key; value v means +v % to all chances of this layer (extra rolls, currency,
	-- uniques, gear upgrade chance). 0 / unset = no bonus. Read from the corpse owner only.
	-- 7100040 lies inside the range reserved for Chaos (7100000-7100999), see chaos_constants.lua.
	itemFindStorage = 7100040,
	itemFindMaxPercent = 300, -- clamp

	-- same threshold as the stock callback. With catchup.lua loaded (always, in this repo) low stamina CUTS the loot
	-- (catchup_config.lua stamina.lootMult, x0.5) and the stock callback is patched the same way (patch_base_events.py
	-- step 16); only without it does the old rule hold: at or below this, no loot at all
	minStamina = 840,

	-- 1. extra rolls from the monster's own loot table
	-- owner 2026-10-17 ("monstros raros e magicos dropam loot demais"): the expected loot per kill is
	-- 1 + extraRolls x extraChanceMult (stack counts apart): normal 1.0, magic 1.5, rare 2.0, legendary 3.0, boss 3.0.
	-- It was magic 2.0, rare 3.0, legendary 4.0 (and the stack counts below x1.25 / x1.5 on top)
	extraRolls = {normal = 0, magic = 1, rare = 1, legendary = 2, boss = 2},
	-- multiplier on the dropped stack count of an extra roll (on top of levelCountMult below)
	extraCountMult = {normal = 1.0, magic = 1.0, rare = 1.1, legendary = 1.25, boss = 1.5},
	-- same table as the stock callback: {minLevel, maxLevel, multiplier} of Monster:getMonsterLevel()
	levelCountMult = {
		{5, 50, 1.15}, {51, 100, 1.35}, {101, 200, 1.65}, {201, 300, 1.95}, {301, 500, 2.25}, {501, 10000, 2.70}
	},
	-- chance of a single extra roll per entry is lootData.chance (stock units, 0..MAX_LOOTCHANCE) times:
	extraChanceMult = {normal = 1.0, magic = 0.5, rare = 1.0, legendary = 1.0, boss = 1.0},
	-- extra rolls never add these (ids), e.g. quest items
	extraSkipItems = {},

	-- 2. gear quality
	gear = {
		-- floor rarity per tier (a stored id of data/lib/chaos_rarity.lua: 3 Magic, 4 Rare, 5 Legendary; 0 = no floor).
		-- Before the seven rarities (2026-10-18): rare 3, legendary 5, boss 6 of the 15
		minRarity = {normal = 0, magic = 0, rare = 3, legendary = 4, boss = 5},
		-- chance (percent) that a gear item of this tier gets the floor applied at all
		ensureChance = {normal = 0, magic = 0, rare = 100, legendary = 100, boss = 100},
		-- chance (percent) for a bonus after the floor, then +1..+3 steps with the weights below
		bonusChance = {normal = 0, magic = 10, rare = 20, legendary = 35, boss = 50},
		bonusSteps = {{1, 60}, {2, 30}, {3, 10}}, -- {steps, weight}: places up the order Common, Uncommon, Magic, Rare, Legendary
		maxRarity = 5, -- the bonus steps stop at Legendary; Divine only comes from divineChance (and the stock roll)
		-- percent per gear drop of a Divine item, on top of the steps (x item find; the stock roll gives 0.38% more)
		divineChance = {normal = 0, magic = 0, rare = 0.05, legendary = 0.3, boss = 1.5},
		-- the hunting level's own rarity roll (beta 2026-10-20: two days at level 500+ and 30 kills a minute gave no Rare
		-- or Legendary item). Normal and magic monsters are 98% of the kills, and for them every Rare / Legendary came
		-- from the base server's stock roll alone: this layer gave those tiers at most Magic, whatever the level. Now a
		-- gear drop of a monster of hunting level (pace.lua: its own level, else 2 x the bounty pool estimate) at or above
		-- the first point gets at least Rare with `chance` percent (linear between the points, flat beyond, x item find),
		-- and `legendaryShare` percent of those at least Legendary. Below the first point nothing changes.
		-- Measured with the core (server/README.md "Level 500+ rarity"), rare+ gear per hour at 30 kills a minute: level
		-- 540 7.0 -> 8.9, level 1180 6.1 -> 11.7 with the stock roll; without it (the beta's zero) 1.4 -> 3.1 and 1.1 -> 6.0.
		levelRarity = {points = {{450, 0}, {500, 4}, {1000, 6}, {2000, 8}}, legendaryShare = 30},
		-- ids that are never touched (boats etc., same as customs/rarity/reroll_rarity_stats.lua)
		excludedItems = {
			[27797] = true, [27798] = true, [27799] = true, [27800] = true, [27801] = true, [27802] = true
		},
		-- stock rarity roll, copied from default_onDropLoot.lua; used only by ChaosLootRoll to
		-- simulate what the stock pass would have produced
		stockRollChance = 70, -- math.random(100) > 70 -> no rarity
		-- the chances in the order Common, Uncommon, Magic, Rare, Legendary, Divine (ChaosRarity.stockRolls, which
		-- tools/patch_base_events.py step 17 puts into the base roll; 15 rows 15, 14, 12, 10, 8.5, 7, 6, ... 0.5 before)
		stockChances = {15, 14, 12, 10, 7, 1}
	},

	-- 3. currency / crafting drops
	currency = {
		-- cap on the chance scale of the entries: rate x item find x orb find (charms) x Ember of the Forge
		maxScale = 3.0,
		-- orbs only drop from monsters of this level or higher (Monster:getMonsterLevel, see loot.lua monsterLevel);
		-- bosses (levelGateSkip) are exempt. Owner 2026-10-17: "orbs drop too often". 0 = no gate
		minMonsterLevel = 100,
		levelGateSkip = {boss = true},
		-- chance per kill in 1/10000 for EACH entry whose chance table has the tier. The normal column adds up to 183
		-- (about 1 orb per 50 kills of a monster of level 100+, counting the Awakening / Whetstone stacks of 2);
		-- magic is x3 of normal (about 1 per 18 kills) and rare x6 (about 1 per 9). Was magic ~x8 and rare ~x30 of normal.
		-- legendary and boss are unchanged (they also get the guaranteed draw below)
		entries = {
			{id = 29857, name = "Orb of Fate", weight = 30, count = {1, 1},
				chance = {normal = 20, magic = 60, rare = 120, legendary = 2500, boss = 4000}},
			{id = 29856, name = "Orb of Upheaval", weight = 70, count = {1, 1},
				chance = {normal = 40, magic = 120, rare = 240, legendary = 4000, boss = 5000}},
			-- crafting orbs (data/lib/chaos_crafting.lua): Awakening common, Gilding / Unmaking / Erasure
			-- uncommon, Grafting rare
			{id = 29851, name = "Orb of Awakening", weight = 20, count = {1, 2},
				chance = {normal = 30, magic = 90, rare = 180, legendary = 2500, boss = 3500}},
			{id = 24691, name = "Orb of Gilding", weight = 10, count = {1, 1},
				chance = {normal = 10, magic = 30, rare = 60, legendary = 1200, boss = 2000}},
			{id = 24697, name = "Orb of Unmaking", weight = 10, count = {1, 1},
				chance = {normal = 10, magic = 30, rare = 60, legendary = 1200, boss = 2000}},
			{id = 24688, name = "Orb of Erasure", weight = 10, count = {1, 1},
				chance = {normal = 15, magic = 45, rare = 90, legendary = 1500, boss = 2500}},
			{id = 29855, name = "Orb of Grafting", weight = 5, count = {1, 1},
				chance = {normal = 4, magic = 12, rare = 24, legendary = 600, boss = 1000}},
			-- orbs v2 (data/lib/chaos_orbs.lua): the Whetstone and the Orb of Tempering often, Reforging, Excision and Binding
			-- rare, the Orb of Ruin very rare (and mostly from legendary monsters and bosses)
			{id = 32256, name = "Whetstone", weight = 18, count = {1, 2},
				chance = {normal = 25, magic = 75, rare = 150, legendary = 2000, boss = 3000}},
			{id = 32251, name = "Orb of Tempering", weight = 14, count = {1, 1},
				chance = {normal = 12, magic = 36, rare = 72, legendary = 1400, boss = 2200}},
			{id = 32254, name = "Orb of Reforging", weight = 6, count = {1, 1},
				chance = {normal = 4, magic = 12, rare = 24, legendary = 600, boss = 1000}},
			{id = 32253, name = "Orb of Excision", weight = 5, count = {1, 1},
				chance = {normal = 3, magic = 9, rare = 18, legendary = 450, boss = 800}},
			{id = 32252, name = "Orb of Binding", weight = 3, count = {1, 1},
				chance = {normal = 2, magic = 6, rare = 12, legendary = 250, boss = 500}},
			-- Ember Orb (a tier up on a chosen modifier) like Reforging, Crown Orb (a rarity up) like Excision
			{id = 32258, name = "Ember Orb", weight = 6, count = {1, 1},
				chance = {normal = 4, magic = 12, rare = 24, legendary = 600, boss = 1000}},
			{id = 32259, name = "Crown Orb", weight = 3, count = {1, 1},
				chance = {normal = 2, magic = 6, rare = 12, legendary = 300, boss = 600}},
			{id = 32255, name = "Orb of Ruin", weight = 1, count = {1, 1},
				chance = {normal = 0, magic = 1, rare = 4, legendary = 80, boss = 160}},
			-- gems and sockets (data/lib/chaos_gems_config.lua socketOrb; the gems drop through chaos_gems_config.lua)
			{id = 24692, name = "Orb of Sockets", weight = 8, count = {1, 1},
				chance = {normal = 8, magic = 24, rare = 48, legendary = 1000, boss = 1500}}
			-- add more: {id = 12345, name = "Soul Shard", weight = 50, count = {1, 3}, chance = {...}}
		},
		-- guaranteed number of entries drawn by weight (in addition to the chances above)
		guaranteed = {legendary = 1, boss = 1},
		-- bonus count for guaranteed/rolled stackables: floor(count * mult)
		countMult = {normal = 1.0, magic = 1.0, rare = 1.0, legendary = 1.5, boss = 2.0}
	},

	-- 3d. waystones (the base server's Waystone Tier I-VI items, dropped by the stock pass): a monster below this level
	-- (L.monsterLevel) drops none; loot.lua takes them out of the corpse again (L.gateWaystones). Items are found by
	-- name (lowercase Lua pattern), so the base item ids need not be known. 0 = no gate. Owner 2026-10-17.
	waystone = {
		minMonsterLevel = 150,
		namePattern = "^waystone tier",
		skipTiers = {boss = true}
	},

	-- 4. unique items (global ChaosUniqueItems, see LOOT.md)
	unique = {
		-- multiplier on the entry's chance (per 10000 per kill)
		tierMult = {normal = 0, magic = 1, rare = 2, legendary = 4, boss = 6},
		tierRank = {normal = 0, magic = 1, rare = 2, legendary = 3, boss = 4},
		maxPerKill = 1,
		maxChance = 10000, -- clamp after multipliers
		effect = "CONST_ME_FIREWORK_YELLOW", -- magic effect name looked up in _G at runtime (fallback 49)
		fallbackEffect = 49,
		message = "A unique item drops from %s: %s!",
		messageType = "MESSAGE_EVENT_ADVANCE", -- looked up in _G
		-- who gets the text + effect: players within these squares around the corpse
		viewRangeX = 8, viewRangeY = 6,
		-- broadcast legendary finds / uniques to players within this square (multifloor)
		broadcastRangeX = 30, broadcastRangeY = 30,
		broadcastText = "%s found %s!"
	},

	-- announce a legendary/boss kill with rarity >= this on a gear drop (0 disables)
	announceRarityFrom = 10, -- Divine (a stored id)

	-- 6. diagnostic (ChaosLootRoll): hard cap of simulated kills per call, and a fake loot table
	-- used when MonsterType(name):getLoot() is unavailable or empty
	sim = {
		maxKills = 200000,
		fallbackLoot = {
			{itemId = 2160, chance = 10000, maxCount = 3},
			{itemId = 2392, chance = 8000},
			{itemId = 2463, chance = 8000},
			{itemId = 2457, chance = 8000}
		},
		-- item ids the simulation treats as gear when ItemType() is unavailable
		fallbackGear = {[2392] = true, [2463] = true, [2457] = true}
	}
}
