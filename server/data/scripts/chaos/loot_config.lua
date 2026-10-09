-- loot_config.lua: every number of the Chaos loot layer (loot.lua). Plain table, loaded with
--     ChaosLootConfig = dofile("data/scripts/chaos/loot_config.lua")
-- Tiers: "normal", "magic", "rare", "legendary", "boss" (as produced by monster_tiers.lua).
-- Lua 5.1 / LuaJIT compatible. Edit here, then /reload scripts (or restart).

return {
	-- EventCallback priority (index). Stock default_onDropLoot = 0 (register() without index),
	-- creaturescripts/autoloot.lua = 3. Must be > 0 (after the stock pass) and < 3 (before autoloot,
	-- otherwise autolooters never receive the extra items). Do not change unless you know why.
	priority = 1,

	-- global hook. A number, or function(ctx) returning a number; ctx = {tier=, monster=, player=}.
	-- Multiplies the chance and the count of the EXTRA rolls and the currency chances.
	-- (Unique items are only scaled by tierMult and item find.)
	-- the Loot Frenzy event (events_schedule.lua) raises it on its days, the World Loot buff from the store
	-- (shop_services.lua) while it runs
	rateMult = function(ctx)
		local event = ChaosEvents and ChaosEvents.bonus("loot") or 1
		local buff = ChaosShopServices and ChaosShopServices.buffMult and ChaosShopServices.buffMult("loot") or 1
		local rift = ChaosRift and ChaosRift.lootMult and ChaosRift.lootMult(ctx) or 1 -- the rift's Quantity bonus
		local world = ChaosWorldEvents and ChaosWorldEvents.lootMult and ChaosWorldEvents.lootMult(ctx) or 1 -- Golden Hour (worldevents.lua)
		return event * buff * rift * world
	end,

	-- player storage key; value v means +v % to all chances of this layer (extra rolls, currency,
	-- uniques, gear upgrade chance). 0 / unset = no bonus. Read from the corpse owner only.
	-- 7100040 lies inside the range reserved for Chaos (7100000-7100999), see chaos_constants.lua.
	itemFindStorage = 7100040,
	itemFindMaxPercent = 300, -- clamp

	-- same threshold as the stock callback: at or below it the stock callback drops nothing, so do we
	minStamina = 840,

	-- 1. extra rolls from the monster's own loot table
	extraRolls = {normal = 0, magic = 1, rare = 2, legendary = 3, boss = 2},
	-- multiplier on the dropped stack count of an extra roll (on top of levelCountMult below)
	extraCountMult = {normal = 1.0, magic = 1.0, rare = 1.25, legendary = 1.5, boss = 1.5},
	-- same table as the stock callback: {minLevel, maxLevel, multiplier} of Monster:getMonsterLevel()
	levelCountMult = {
		{5, 50, 1.15}, {51, 100, 1.35}, {101, 200, 1.65}, {201, 300, 1.95}, {301, 500, 2.25}, {501, 10000, 2.70}
	},
	-- chance of a single extra roll per entry is lootData.chance (stock units, 0..MAX_LOOTCHANCE) times:
	extraChanceMult = {normal = 1.0, magic = 1.0, rare = 1.0, legendary = 1.0, boss = 1.0},
	-- extra rolls never add these (ids), e.g. quest items
	extraSkipItems = {},

	-- 2. gear quality
	gear = {
		-- floor rarity per tier (0 = no floor)
		minRarity = {normal = 0, magic = 0, rare = 3, legendary = 5, boss = 6},
		-- chance (percent) that a gear item of this tier gets the floor applied at all
		ensureChance = {normal = 0, magic = 0, rare = 100, legendary = 100, boss = 100},
		-- chance (percent) for a bonus after the floor, then +1..+3 steps with the weights below
		bonusChance = {normal = 0, magic = 10, rare = 20, legendary = 35, boss = 50},
		bonusSteps = {{1, 60}, {2, 30}, {3, 10}}, -- {steps, weight}
		maxRarity = 15,
		-- ids that are never touched (boats etc., same as customs/rarity/reroll_rarity_stats.lua)
		excludedItems = {
			[27797] = true, [27798] = true, [27799] = true, [27800] = true, [27801] = true, [27802] = true
		},
		-- stock rarity roll, copied from default_onDropLoot.lua; used only by ChaosLootRoll to
		-- simulate what the stock pass would have produced
		stockRollChance = 70, -- math.random(100) > 70 -> no rarity
		stockChances = {
			15.0, 14.0, 12.0, 10.0, 8.5, 7.0, 6.0, 4.5, 3.8, 3.0, 2.3, 1.7, 1.2, 0.8, 0.5
		},
		names = {
			"Common", "Uncommon", "Rare", "Epic", "Legendary", "Exotic", "Mythic", "Chaos", "Eternal",
			"Divine", "Phantasmal", "Celestial", "Cosmic", "Abyssal", "Transcendent"
		}
	},

	-- 3. currency / crafting drops
	currency = {
		-- chance per kill in 1/10000 for EACH entry whose chance table has the tier
		entries = {
			{id = 29857, name = "Orb of Fate", weight = 30, count = {1, 1},
				chance = {normal = 20, magic = 150, rare = 600, legendary = 2500, boss = 4000}},
			{id = 29856, name = "Orb of Upheaval", weight = 70, count = {1, 1},
				chance = {normal = 40, magic = 300, rare = 1200, legendary = 4000, boss = 5000}},
			-- crafting orbs (data/lib/chaos_crafting.lua): Awakening common, Gilding / Unmaking / Erasure
			-- uncommon, Grafting rare
			{id = 29851, name = "Orb of Awakening", weight = 20, count = {1, 2},
				chance = {normal = 30, magic = 200, rare = 700, legendary = 2500, boss = 3500}},
			{id = 24691, name = "Orb of Gilding", weight = 10, count = {1, 1},
				chance = {normal = 10, magic = 80, rare = 300, legendary = 1200, boss = 2000}},
			{id = 24697, name = "Orb of Unmaking", weight = 10, count = {1, 1},
				chance = {normal = 10, magic = 80, rare = 300, legendary = 1200, boss = 2000}},
			{id = 24688, name = "Orb of Erasure", weight = 10, count = {1, 1},
				chance = {normal = 15, magic = 100, rare = 400, legendary = 1500, boss = 2500}},
			{id = 29855, name = "Orb of Grafting", weight = 5, count = {1, 1},
				chance = {normal = 4, magic = 30, rare = 120, legendary = 600, boss = 1000}},
			-- orbs v2 (data/lib/chaos_orbs.lua): the Whetstone and the Orb of Tempering often, Reforging, Excision and Binding
			-- rare, the Orb of Ruin very rare (and mostly from legendary monsters and bosses)
			{id = 32256, name = "Whetstone", weight = 18, count = {1, 2},
				chance = {normal = 25, magic = 180, rare = 600, legendary = 2000, boss = 3000}},
			{id = 32251, name = "Orb of Tempering", weight = 14, count = {1, 1},
				chance = {normal = 12, magic = 90, rare = 350, legendary = 1400, boss = 2200}},
			{id = 32254, name = "Orb of Reforging", weight = 6, count = {1, 1},
				chance = {normal = 4, magic = 35, rare = 140, legendary = 600, boss = 1000}},
			{id = 32253, name = "Orb of Excision", weight = 5, count = {1, 1},
				chance = {normal = 3, magic = 25, rare = 100, legendary = 450, boss = 800}},
			{id = 32252, name = "Orb of Binding", weight = 3, count = {1, 1},
				chance = {normal = 2, magic = 15, rare = 60, legendary = 250, boss = 500}},
			{id = 32255, name = "Orb of Ruin", weight = 1, count = {1, 1},
				chance = {normal = 0, magic = 4, rare = 18, legendary = 80, boss = 160}},
			-- gems and sockets (data/lib/chaos_gems_config.lua socketOrb; the gems drop through chaos_gems_config.lua)
			{id = 24692, name = "Orb of Sockets", weight = 8, count = {1, 1},
				chance = {normal = 8, magic = 60, rare = 250, legendary = 1000, boss = 1500}}
			-- add more: {id = 12345, name = "Soul Shard", weight = 50, count = {1, 3}, chance = {...}}
		},
		-- guaranteed number of entries drawn by weight (in addition to the chances above)
		guaranteed = {legendary = 1, boss = 1},
		-- bonus count for guaranteed/rolled stackables: floor(count * mult)
		countMult = {normal = 1.0, magic = 1.0, rare = 1.0, legendary = 1.5, boss = 2.0}
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
	announceRarityFrom = 10,

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
