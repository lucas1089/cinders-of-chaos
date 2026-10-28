-- Rift settings (rift.lua, rift_core.lua). Loaded with
--     ChaosRiftConfig = dofile("data/scripts/chaos/rift_config.lua")
-- Every number of the rifts lives here. Lua 5.1 / LuaJIT compatible. Item ids are SERVER ids.
-- Overview: server/README.md "Rifts".

return {
	-- ------------------------------------------------------------------ the key item
	-- An existing non-stackable item no other script uses ("shadow orb"; one quest NPC lists it, Black Osric) with this
	-- action id. Tier and modifiers
	-- are custom attributes ("rift_tier", "rift_mods" = "key:value,key:value"); the name becomes "Rift Key (Tier N)" and
	-- the description lists the modifiers and the reward bonuses, so looking at a key shows them.
	-- maxMods: the most modifiers a key can carry (drops roll 1-3; the Orb of Grafting adds up to this). alchemyCount: how
	-- many modifiers an Orb of Gilding gives a key without any, {count, weight} (data/lib/chaos_crafting.lua)
	key = {itemId = 10155, actionId = 47401, nameFormat = "Rift Key (Tier %d)", maxMods = 3,
		alchemyCount = {{2, 60}, {3, 40}}},
	-- the reward chest that appears where the rift boss died: 32311 "reward chest", the one-tile look (client 38758, redrawn in
	-- pair 53 as a front-facing chest with coins; tools/install_reward_chest.py: a copy of the stock reward chest 21584, a
	-- container, not moveable). It also is the quest chest of the planned areas (tools/areaplan_build.lua), the Descent's
	-- (descent_config.lua objects.chest) and of the base map's quest chests and boxes; tools/patch_reward_chests.py swaps the
	-- placed ones on the map. fallbackId is the stock chest (gold on a stone plinth; the plain chest 1740 before 2026-10-20)
	-- used while 32311 is not installed. legacyItemIds: the 2 x 2 look of pair 45 (32310, client 38657) that earlier installs
	-- put on the map; it stays an item type, and the map step moves every chest of it to 32311 (read by
	-- tools/patch_reward_chests.py only). server/README.md "Reward chests"
	chest = {itemId = 32311, fallbackId = 21584, legacyItemIds = {32310}, actionId = 47402},
	maxTier = 15,

	-- ------------------------------------------------------------------ opening
	partyRange = 8, -- party members within this many sqm (same floor) of the player using the key come along
	maxPlayers = 5,
	needProtectionZone = true,
	useCooldown = 3, -- seconds between two key uses of one player (exhaust)

	-- ------------------------------------------------------------------ the run
	-- seconds; when it runs out the rift fails: everyone is sent out, the key is lost. With the generated layouts a run
	-- takes the limit of its size band (layout.sizes: 12 / 13 / 15 minutes); this one is the limit of a run without
	-- layouts and then the base of the atlas's Swift cells (atlas_config.lua swiftShare; with layouts the Swift time
	-- comes from the clear-time model, atlas_core.lua A.swiftSeconds)
	timeLimit = 600,
	bossAt = 75, -- percent of the rift's monsters that must die before the boss appears
	exitDelay = 60, -- seconds after the boss died: time to open the chest and loot; then everyone is sent out
	hudEvery = 5, -- seconds between HUD refreshes (the client counts down by itself in between)
	-- instance limits (instance_limits.lua, server/README.md "Instance limits"): warnings at these seconds left; a
	-- running rift whose players are all gone (fallen players who may come back keep it open) closes after idleSeconds
	-- as a failed rift (the key is spent, as when the time runs out); at most maxRuns rifts and Omen arenas at once (the
	-- grid has 16 slots of 256 x 256 on two floors, up to about 50,000 runtime tiles a layout, see "Instance limits" for
	-- the load); a player who finds them all busy (or none ready yet) waits in line and is told when one frees up
	limits = {warnAt = {300, 60, 10}, idleSeconds = 180, maxRuns = 16, waitlist = true},

	-- packs: count = packs.base + floor(tier / packs.perTiers) + packs.perExtraPlayer x (players - 1);
	-- size = a random number in packs.size, + the Swarm modifier. One monster type per pack.
	packs = {base = 6, perTiers = 3, perExtraPlayer = 2, size = {3, 4}, types = 3, spread = 2},
	-- the boss: the strongest of the rift's monster types, made legendary (monster_tiers.lua), its base health x this
	-- x (1 + perExtraPlayer x (players - 1))
	boss = {healthMult = 3, perExtraPlayer = 1.0, tier = "legendary"},

	-- ------------------------------------------------------------------ density (server/README.md "Rifts", Density)
	-- enabled = false brings back the packs above exactly (packs.*, the type's own health, every monster drops loot).
	-- Enabled, a run plans many more, weaker monsters and feeds them in as the party advances:
	--   count     planned monsters solo at tier t: base + perTier x (t - 1), x (1 + perExtraPlayer x (players - 1)),
	--             in packs of `size` (+ Swarm), x Teeming / atlas density. Tier 1 80, tier 10 152, tier 15 192 solo;
	--             a party of 5 twice that.
	--   live      monsters alive at once: base + perExtraPlayer x (players - 1), at most max. The rest wait in a queue;
	--             reinforce.perTick packs a second come in when there is room, in the open room farthest from the
	--             players (at least reinforce.minDistance sqm from each), until the guardian appears.
	--   model     the health budget. Every pack monster has the health a typical player needs: level L = the tier's
	--             level, area damage dps5 x (L / 1000)^dps5Exp (data/spells/README.md, the level 1000 median of the
	--             classes, 5 targets), x gear (the Ascended model's geared player) x uptime (walking, looting). The
	--             packs up to the guardian (bossAt %) take packSeconds of that, the guardian guardianSeconds of the
	--             single-target damage (dps1 x (L / 1000)^dps1Exp x gear x guardianUptime). tierHp: the health
	--             multipliers of monster_tiers.lua (magic, rare, legendary), for the average. Tiers 11-15 add their +15%
	--             health on top (`beyond`), so they run longer.
	--   damage    pack monsters (not the guardians) hit x this: a pack is about twice the size of before.
	-- Spoils stay per run as before (orbs, gold, uniques, keys, fragments, bounty and bestiary credit): elite chances x
	-- the share (old monsters / new monsters), and only that share of the normal monsters carries loot (the others are
	-- husks: experience only, no corpse loot, no kill credit).
	-- Big generated layouts (2026-10-12, `layout` below): the plan and the live cap grow with the layout's walkable
	-- tiles, the run's walking is part of the clear time:
	--   area      count x (walkable / ref) ^ exp, 1 to maxMult (ref = the open floor of the old three-room slot);
	--             typical layouts (layout.typical): band 1 x1.67, band 2 x1.92, band 3 x2.10. Tier 1 solo 134, tier
	--             10 292, tier 15 403 (a party of 5 twice that).
	--   live      + per100 per 100 walkable tiles: about 100 / 130 / 165 alive solo in the three bands, max 260
	--   reinforce packs come in the section farthest from the players among the unvisited ones up to `window`
	--             walking steps past the party's progress, at least minDistance sqm from each player (out of
	--             sight); `visit` = a section counts as reached when a player comes this close to its centre
	--   populate  the first packs are placed `perStep` monsters every stepMs (not all in the task that uses the key)
	--   model.walk the clear time adds the layout's walking distance arrival -> arena x sweep at the tier's level
	density = {
		enabled = true,
		count = {base = 80, perTier = 8, perExtraPlayer = 0.25},
		area = {ref = 1081, exp = 0.25, maxMult = 2.5},
		size = {5, 7},
		spread = 3,
		live = {base = 60, perExtraPlayer = 10, per100 = 0.5, max = 260},
		reinforce = {perTick = 2, minDistance = 16, window = 90, visit = 10},
		populate = {perStep = 20, stepMs = 100},
		model = {dps5 = 5240, dps5Exp = 1.35, dps1 = 2600, dps1Exp = 1.1, gear = 1.15, uptime = 0.6, guardianUptime = 0.75,
			packSeconds = 225, guardianSeconds = 55, tierHp = {magic = 2.0, rare = 3.5, legendary = 6.0},
			walk = {sweep = 1.8}},
		damage = 0.6,
		-- extra monsters (Veilbreach, the Wrathful Guardian's thralls) stop when this many more than `live` are up
		extraSlack = 12
	},

	-- ------------------------------------------------------------------ party scaling (rifts and Omen arenas)
	-- n = the players who entered. Bigger parties face harder content and get more per head, bounded
	-- (rift_core.lua R.party, server/README.md "Rifts", Party scaling):
	--   healthPerExtraPlayer  the rift's TOTAL monster health (packs x health) x (1 + this x (n - 1)). The packs already
	--                         grow (packs.perExtraPlayer), so each monster gets the rest: x total / pack growth, at least 1.
	--                         The guardians have their own: boss.perExtraPlayer, omen.healthPerExtraPlayer.
	--   damagePerExtraPlayer  every rift monster and guardian (Omens too) hits x (1 + this x (n - 1))
	--   rewardPerExtraPlayer  percent on every finisher's chest (gold, orbs, item rolls, Omen Fragments), at most rewardCap
	--   lootPerExtraPlayer    percent on the Chaos loot rate of the rift's kills and on the Sealed Coffer, at most lootCap
	party = {healthPerExtraPlayer = 1.0, damagePerExtraPlayer = 0.10, rewardPerExtraPlayer = 12.5, rewardCap = 50,
		lootPerExtraPlayer = 5, lootCap = 20},
	-- monster tiers inside a rift (percent per monster, before the Elites modifier; x (1 + perTier x tier))
	elite = {magic = 10, rare = 3, legendary = 0.6, perTier = 0.05},

	-- rift tier -> monster level window of the bounty pool (bounty_pool.lua "level") and the level needed to enter.
	-- Tiers above #tiers reuse the last window and add `beyond` per tier (health, damage, rewards).
	tiers = {
		{minLevel = 100, pick = {80, 180}},
		{minLevel = 150, pick = {140, 240}},
		{minLevel = 200, pick = {200, 320}},
		{minLevel = 300, pick = {280, 420}},
		{minLevel = 400, pick = {380, 520}},
		{minLevel = 500, pick = {480, 640}},
		{minLevel = 600, pick = {580, 740}},
		{minLevel = 700, pick = {680, 840}},
		{minLevel = 800, pick = {780, 940}},
		{minLevel = 900, pick = {880, 1100}}
	},
	beyond = {minLevelStep = 25, health = 0.15, damage = 0.15, reward = 0.10},
	minPoolHealth = 100, -- pool entries with less health are left out (odd custom entries)
	widenStep = 60, -- a window with fewer than packs.types monsters is widened by this much per side, up to 5 times

	-- ------------------------------------------------------------------ modifiers
	-- Rolled when the key drops: 1-3 different ones (modCount weights), each with a value in `range` (multiple of
	-- `step`). They make the rift harder and add reward bonuses: `reward` = percent bonus per point of value
	-- (fixed = flat percent). quantity: Chaos loot rate of kills and chest items; rarity: chest gear rarity;
	-- experience: kill experience in the rift (on top of the cap, see `exp`).
	modCount = {{1, 50}, {2, 35}, {3, 15}}, -- {count, weight}
	modCountBetter = {{1, 25}, {2, 45}, {3, 30}}, -- weights for a next-tier key from a completed rift
	-- Modifier tiers I-V: `tiers` = the highest value of each tier (tier 1 starts at range[1], tier t at tiers[t - 1] +
	-- step). Tiers I-III are the value ranges the modifiers had before the tiers (old keys decode unchanged), IV and V
	-- extend them; `range` covers all of them. The tier of a modifier follows from its value (nothing new is stored on
	-- the key). A modifier without `tiers` has no tier (Withering, Fragile). See `modTiers` below for who rolls which.
	mods = {
		{key = "vitality", side = "prefix", name = "Vitality", text = "Monsters have +%d%% health", range = {20, 90}, step = 5,
			tiers = {30, 45, 60, 75, 90}, reward = {quantity = 0.5, experience = 0.25}},
		{key = "brutality", side = "prefix", name = "Brutality", text = "Monsters deal +%d%% damage", range = {15, 60}, step = 5,
			tiers = {20, 30, 40, 50, 60}, reward = {rarity = 0.75, experience = 0.25}},
		{key = "haste", side = "prefix", name = "Haste", text = "Monsters move +%d faster", range = {40, 180}, step = 10,
			tiers = {60, 90, 120, 150, 180}, reward = {quantity = 0.15}},
		{key = "elites", side = "prefix", name = "Elites", text = "+%d%% magic, rare and legendary monsters", range = {50, 300}, step = 25,
			tiers = {75, 125, 200, 250, 300}, reward = {rarity = 0.15, quantity = 0.1}},
		{key = "reflection", side = "prefix", group = "reflect", name = "Reflection", text = "Monsters reflect %d%% of the damage they take", range = {5, 22},
			step = 1, tiers = {8, 11, 15, 18, 22}, reward = {experience = 1.5, quantity = 1.0}},
		{key = "warding", side = "prefix", name = "Warding", text = "Monsters resist %d%% elemental damage", range = {10, 40}, step = 5,
			tiers = {15, 20, 30, 35, 40}, reward = {quantity = 0.75, rarity = 0.5}},
		{key = "withering", side = "suffix", group = "regen", name = "Withering", text = "Players do not regenerate health", range = {1, 1}, step = 1,
			reward = {fixed = {experience = 15, quantity = 15}}},
		{key = "swarm", side = "prefix", name = "Swarm", text = "+%d monsters in every pack", range = {1, 5}, step = 1,
			tiers = {1, 2, 3, 4, 5}, reward = {quantity = 8, experience = 5}},
		-- map modifiers (second set). weight: relative roll weight (the first eight have the default 100); minTier: the
		-- lowest key tier that rolls it (a key of a lower tier never gets it from a drop or an orb); boon = true: a pure
		-- reward without a bonus of its own (shown in gold on the HUD). Effects in rift.lua, numbers in the blocks below.
		{key = "teeming", side = "prefix", name = "Teeming", text = "+%d%% monster packs", range = {20, 70}, step = 10,
			tiers = {20, 30, 50, 60, 70}, weight = 80, reward = {quantity = 0.5, experience = 0.3}},
		{key = "gilded", name = "Gilded Trail", text = "%d%% chance of a fleeing Treasure Goblin",
			range = {30, 100}, step = 10, tiers = {40, 50, 70, 80, 100}, weight = 40, boon = true},
		{key = "warband", side = "prefix", name = "Warbands", text = "%d%% of packs are rare warbands",
			range = {10, 40}, step = 5, tiers = {15, 20, 30, 35, 40}, weight = 60, minTier = 2,
			reward = {rarity = 1.0, quantity = 0.3}},
		-- a chance cannot pass 100%: the coffer has three tiers
		{key = "coffer", name = "Sealed Coffer", text = "%d%% chance of a guarded coffer",
			range = {40, 100}, step = 20, tiers = {40, 60, 100}, weight = 50, boon = true},
		{key = "twin", side = "prefix", name = "Twin Guardians", text = "Twin guardians, %d%% health each", range = {55, 85},
			step = 5, tiers = {60, 65, 75, 80, 85}, weight = 50, minTier = 3, reward = {rarity = 0.25, quantity = 0.2}},
		{key = "echo", name = "Echoing Spoils", text = "%d%% chance of double loot",
			range = {5, 25}, step = 5, tiers = {5, 10, 15, 20, 25}, weight = 35, minTier = 2, boon = true},
		{key = "cinder", side = "prefix", name = "Cinderdeath", text = "Slain monsters burst for %d%% health",
			range = {5, 25}, step = 5, tiers = {5, 10, 15, 20, 25}, weight = 70, minTier = 3,
			reward = {quantity = 1.2, rarity = 0.8}},
		{key = "blight", side = "suffix", name = "Blighted Mending", text = "Players receive %d%% less healing", range = {20, 70}, step = 10,
			tiers = {20, 30, 50, 60, 70}, weight = 70, minTier = 2, reward = {rarity = 0.5, experience = 0.3, quantity = 0.2}},
		{key = "waning", side = "suffix", name = "Waning Veil", text = "The rift closes %d%% sooner", range = {15, 40}, step = 5,
			tiers = {15, 20, 30, 35, 40}, weight = 70, reward = {quantity = 1.0, experience = 0.5}},
		{key = "dread", side = "prefix", name = "Dread Guardian", text = "Guardian +%d%% health and damage", range = {50, 250},
			step = 25, tiers = {75, 100, 150, 200, 250}, weight = 60, minTier = 4, reward = {rarity = 0.2, quantity = 0.1}},
		-- lives (see `lives`): the run starts with fewer shared lives (never fewer than lives.min)
		{key = "fragile", side = "suffix", name = "Fragile", text = "%d fewer shared lives", range = {1, 2}, step = 1,
			weight = 50, minTier = 4, reward = {quantity = 7, rarity = 7, experience = 5}},
		-- third set (2026-10-12). Appended only: the crash refund marker stores a modifier by its index here.
		-- side: "prefix" = the monsters (or the guardian) get stronger, "suffix" = the players or the area get worse; a boon
		-- has no side. group: a key carries one modifier of a group at most (two reflections, two "no regeneration", two
		-- hexes, two kinds of ground, two brands never meet); excludes: modifiers this one never shares a key with. note:
		-- who feels it most (the Codex shows it). Numbers of the effects in the blocks below the list.
		{key = "emberbrand", side = "prefix", group = "brand", name = "Emberbrand",
			text = "Monsters deal +%d%% of their damage as extra fire", range = {10, 50}, step = 5,
			tiers = {15, 20, 30, 40, 50}, weight = 40, minTier = 2, reward = {quantity = 0.5, rarity = 0.3}},
		{key = "frostbrand", side = "prefix", group = "brand", name = "Frostbrand",
			text = "Monsters deal +%d%% of their damage as extra ice", range = {10, 50}, step = 5,
			tiers = {15, 20, 30, 40, 50}, weight = 40, minTier = 2, reward = {quantity = 0.5, rarity = 0.3}},
		{key = "stormbrand", side = "prefix", group = "brand", name = "Stormbrand",
			text = "Monsters deal +%d%% of their damage as extra energy", range = {10, 50}, step = 5,
			tiers = {15, 20, 30, 40, 50}, weight = 40, minTier = 2, reward = {quantity = 0.5, rarity = 0.3}},
		{key = "keen", side = "prefix", name = "Keen Fangs", text = "Monster hits have a %d%% chance to deal 50%% more",
			range = {5, 30}, step = 5, tiers = {5, 10, 15, 20, 30}, weight = 60, reward = {rarity = 0.8, quantity = 0.4}},
		{key = "ironhide", side = "prefix", name = "Ironhide", text = "Monsters take %d%% less physical damage",
			range = {10, 40}, step = 5, tiers = {15, 20, 30, 35, 40}, weight = 60, minTier = 2,
			reward = {quantity = 0.75, rarity = 0.5}, note = "Hardest on physical builds (melee, arrows and bolts)."},
		{key = "festering", side = "prefix", name = "Festering Wounds",
			text = "Monster hits have a %d%% chance to fester for 40%% more as earth over 6 s", range = {10, 50}, step = 10,
			tiers = {10, 20, 30, 40, 50}, weight = 50, minTier = 3, reward = {quantity = 0.4, rarity = 0.25}},
		{key = "spiteglass", side = "prefix", group = "reflect", name = "Spiteglass",
			text = "Monsters reflect %d%% of the elemental damage they take", range = {5, 22}, step = 1,
			tiers = {8, 11, 15, 18, 22}, weight = 50, minTier = 3, reward = {experience = 1.0, quantity = 0.7},
			note = "Hardest on casters and elemental builds. Never with Reflection."},
		{key = "brood", side = "prefix", name = "Single Brood", text = "Every pack is of the rift's strongest kind",
			range = {1, 1}, step = 1, weight = 40, minTier = 2, reward = {fixed = {quantity = 12, rarity = 8}}},
		{key = "wrath", side = "prefix", name = "Wrathful Guardian",
			text = "The guardian's nova hits for %d%% of max health every 8 s; it calls thralls", range = {10, 30}, step = 5,
			tiers = {10, 15, 20, 25, 30}, weight = 50, minTier = 4, excludes = {"twin"},
			reward = {rarity = 0.6, quantity = 0.4}, note = "The nova is marked first: step out of it."},
		{key = "breach", side = "prefix", name = "Veilbreach", text = "%d%% of slain monsters tear open a breach of two more",
			range = {5, 25}, step = 5, tiers = {5, 10, 15, 20, 25}, weight = 50, minTier = 3,
			reward = {quantity = 0.8, experience = 0.5}},
		{key = "searing", side = "suffix", group = "hex", name = "Searing Hex", text = "Players take %d%% more elemental damage",
			range = {10, 40}, step = 5, tiers = {15, 20, 30, 35, 40}, weight = 50, minTier = 2,
			reward = {quantity = 0.4, rarity = 0.4}},
		{key = "flaying", side = "suffix", group = "hex", name = "Flaying Hex", text = "Players take %d%% more physical damage",
			range = {10, 40}, step = 5, tiers = {15, 20, 30, 35, 40}, weight = 50, minTier = 2,
			reward = {quantity = 0.4, rarity = 0.4}},
		{key = "sapping", side = "suffix", group = "hex", name = "Sapping Hex", text = "Players deal %d%% less damage",
			range = {10, 30}, step = 5, tiers = {10, 15, 20, 25, 30}, weight = 50, minTier = 3,
			reward = {quantity = 0.7, rarity = 0.4, experience = 0.3}},
		{key = "parched", side = "suffix", group = "regen", name = "Parched Veins", text = "Players do not regenerate mana",
			range = {1, 1}, step = 1, weight = 50, minTier = 2, reward = {fixed = {experience = 10, quantity = 15, rarity = 5}},
			note = "Hardest on casters. Never with Withering."},
		{key = "scorched", side = "suffix", group = "ground", name = "Scorched Earth",
			text = "Burning ground under the players: %d%% of max health a second", range = {2, 6}, step = 1,
			tiers = {2, 3, 4, 5, 6}, weight = 50, minTier = 2, reward = {quantity = 4, rarity = 3}},
		{key = "rimefloor", side = "suffix", group = "ground", name = "Rimefloor",
			text = "Freezing ground under the players: %d%% of max health a second and slowed", range = {2, 6}, step = 1,
			tiers = {2, 3, 4, 5, 6}, weight = 50, minTier = 2, reward = {quantity = 4.5, rarity = 3}},
		{key = "veilstorm", side = "suffix", name = "Veilstorm", text = "Marked storm strikes near the players: %d%% of max health",
			range = {10, 30}, step = 5, tiers = {10, 15, 20, 25, 30}, weight = 50, minTier = 3,
			reward = {quantity = 0.8, rarity = 0.4}}
	},
	-- which modifier tiers a key rolls: {up to key tier, lowest, highest}. A value is drawn evenly from the bottom of the
	-- lowest to the top of the highest tier (a modifier with fewer tiers stops at its last). Keys of tier 1-5 (and orbs
	-- without a key tier) roll exactly the ranges of before the tiers.
	modTiers = {
		names = {"I", "II", "III", "IV", "V"},
		window = {{5, 1, 3}, {10, 1, 4}, {15, 2, 5}},
		-- every modifier of tier IV / V raises the caps of the summed bonuses (bonusCap) by this much
		capRaise = {[4] = {quantity = 8, rarity = 8, experience = 6}, [5] = {quantity = 16, rarity = 16, experience = 12}}
	},
	-- caps of the summed reward bonuses of a key (percent). The highest three-modifier sums of the first eight
	-- modifiers at tier III (quantity 77, rarity 75, experience 53) stay under them, so they only bound the new
	-- combinations; tier IV / V modifiers raise them (modTiers.capRaise).
	bonusCap = {quantity = 80, rarity = 75, experience = 60},
	-- Gilded Trail: the goblin (treasure_goblin.lua, ChaosTreasureGoblin.spawn) appears in a random open room once
	-- this percent range of the rift's kills is done (rolled per run), at the level of the rift's strongest type
	gilded = {atKills = {25, 60}},
	-- Sealed Coffer: a big treasure chest (12664: blue and silver, a container of 20, not moveable; was 1746, which could
	-- be picked up) in a random open side room. Using it wakes a wave of rift monsters around it
	-- (wave.base + wave.perExtraPlayer x (players - 1), at least `waveTier`); once they are dead it opens with: gold
	-- coins goldPerTier2 x tier^2, Orbs of Upheaval and Fate and item rolls (as the reward chest, base + perTier x tier), all x
	-- (1 + quantity bonus). Wave kills do not count towards the guardian. A coffer nobody woke crumbles when the rift is
	-- sealed; a woken one opens then.
	coffer = {itemId = 12664, actionId = 47403, wave = {base = 5, perExtraPlayer = 1, spread = 2}, waveTier = "magic",
		goldPerTier2 = 2000, chaos = {base = 0.25, perTier = 0.05}, divine = {base = 0, perTier = 0.03},
		rolls = {base = 2, perTier = 0.25}},
	-- Cinderdeath: delayMs after a (non-guardian) monster dies, every player within `radius` sqm of it takes fire damage:
	-- value % of the monster's max health, at most capBase + capPerTier x tier
	cinder = {delayMs = 1500, radius = 1, capBase = 300, capPerTier = 150},
	-- Twin Guardians: the second guardian appears this many sqm east of the first
	twin = {offset = 2},
	-- Withering keeps mana regeneration: the food regeneration condition is replaced by one without health gain.
	-- Parched Veins the other way round (health kept, no mana).
	-- brands: the element of the extra damage (rift.lua maps it to the combat type)
	brands = {emberbrand = "fire", frostbrand = "ice", stormbrand = "energy"},
	-- Keen Fangs: a critical hit deals x critMult
	keen = {critMult = 1.5},
	-- Festering Wounds: share of the hit dealt again as earth damage over `rounds` ticks of intervalMs
	festering = {share = 0.4, rounds = 6, intervalMs = 1000},
	-- Veilbreach: `count` monsters of the run's kinds appear delayMs after the kill, within `spread` sqm; they count
	-- as extra monsters (not towards the guardian) and cannot open a breach themselves
	breach = {count = 2, delayMs = 800, spread = 2},
	-- Wrathful Guardian: every novaEvery s a ring of radius `radius` is marked; warnMs later every player inside takes
	-- value % of max health (death damage). Every thrallEvery s it calls `thralls` husks of the weakest kind, at most
	-- maxThralls alive.
	wrath = {novaEvery = 8, radius = 3, warnMs = 1200, thrallEvery = 20, thralls = 2, maxThralls = 6},
	-- Scorched Earth / Rimefloor: every `every` s a patch (a plus of 5 tiles) burns within `near` sqm of each player for
	-- lastSeconds; standing in one costs value % of max health a second; Rimefloor also slows by slowPercent for slowMs
	ground = {every = 3, near = 2, lastSeconds = 6, slowPercent = 40, slowMs = 1500,
		element = {scorched = "fire", rimefloor = "ice"}},
	-- Veilstorm: every `every` s a mark within `near` sqm of each player; warnMs later the strike hits radius sqm around it
	veilstorm = {every = 6, near = 2, warnMs = 1200, radius = 1},

	-- ------------------------------------------------------------------ lives
	-- A run has shared lives: base + perExtraPlayer x (players who entered - 1), minus the Fragile modifier, at least
	-- min. A death inside costs one: the normal death of the engine (experience / skill / item loss, blessings and the
	-- amulet as anywhere else, the death window), and the next login of that character puts it back at the rift's
	-- entrance (the layout's arrival) with shieldSeconds in which rift monsters cannot hurt it. The death that takes
	-- the last life collapses the rift: everyone out, no chest, the key is spent (as when the time runs out).
	lives = {base = 3, perExtraPlayer = 1, min = 1, shieldSeconds = 5},

	-- ------------------------------------------------------------------ omens (the boss-key chain)
	-- Sealed rifts of tier minTier or more give every finisher Omen Fragments (chest.base + chest.perTier x (tier -
	-- minTier), x (1 + quantity bonus), fractions a chance of one more); rare / legendary rift monsters of those tiers
	-- carry one in the corpse eliteChance % of the time. Using keyCost fragments (anywhere in the backpack) binds an
	-- Omen Key of a random kind; the key opens that kind's guardian arena: the arena of a ready rift layout (the party
	-- arrives at its mouth), the guardian appears startDelay seconds after the party arrives, timeLimit seconds, the
	-- rift's lives.
	-- The guardian has the health of its XML (data/monster/monsters/chaos/omens/) x (1 + healthPerExtraPlayer x
	-- (players - 1)). Killed in time: a chest for every finisher (`reward`) x the party bonus (`party`). The two items
	-- are new items.otb nodes
	-- (tools/install_omens.py): copies of the stock nodes sourceId (red crystal fragment, stackable; eye of the storm)
	-- with new server ids, so the client needs no change.
	omen = {
		minTier = 6,
		chest = {base = 2, perTier = 1},
		eliteChance = {rare = 8, legendary = 25},
		keyCost = 60,
		fragment = {id = 32071, sourceId = 18420, article = "an", name = "omen fragment", plural = "omen fragments",
			weight = 10, description = "A splinter of a rift's dying breath. Use 60 of them to bind an Omen Key."},
		key = {id = 32072, sourceId = 21703, article = "an", name = "omen key", plural = "omen keys", weight = 50,
			description = "It hums with a guardian's name. Use it in a protection zone to open its arena."},
		minLevel = 800,
		timeLimit = 720, -- 12 minutes, was 10 (server/README.md "Solo kill times")
		startDelay = 5,
		healthPerExtraPlayer = 1.0,
		-- theme: index of `themes` for the arena floor
		kinds = {
			{key = "bloodmoon", name = "Bloodmoon", boss = "Sangrith the Bloodmoon Herald", theme = 3},
			{key = "hollow", name = "Hollow", boss = "Morvane the Hollow Crown", theme = 2},
			{key = "storm", name = "Stormcall", boss = "Thalcyra the Stormbound Seer", theme = 1}
		},
		-- the guardian's chest, per finisher: gold to the bank goldPerLevel x the finisher's level (at least minLevel), orbs,
		-- item rolls from the guardian's loot table (gear at the "boss" loot tier, x rarityMult), the Chaos currency roll,
		-- gems and supports of a tier `asTier` rift, and uniqueRolls unique rolls at the boss tier over every unique (no
		-- monster list), x uniqueFind. Level 1000: 3M gold (hunting earns ~9.5M an hour there, server/README.md "Respec").
		reward = {goldPerLevel = 3000, chaos = 4, divine = 2, rolls = 8, rarityMult = 1.5, uniqueRolls = 2, uniqueFind = 2,
			asTier = 15}
	},

	-- ------------------------------------------------------------------ rewards (the chest, per player)
	-- gold (bank) = goldPerTier2 x tier^2; orbs = base + perTier x tier (fractions are a chance of one more);
	-- item rolls: each draws one entry of a random rift monster's loot table weighted by its chance (stack size x the
	-- quantity bonus); gear gets a rarity from the Chaos loot layer (ChaosLoot.upgradeRarity at the `lootTier` of the
	-- rift tier, x the rarity bonus); then one currency roll (ChaosLoot.rollCurrency) and one unique roll at that tier.
	-- Gold, orbs and the number of rolls are x (1 + quantity bonus). Tiers above 10: x (1 + beyond.reward x (t - 10)).
	-- Then the finisher's atlas (atlas_config.lua) and the party bonus (`party`).
	-- Sized against hunting at level 1000 (9.5M gold, 2.5 Upheaval, 1.3 Fate an hour; server/README.md "Rifts", Income):
	-- four tier 15 chests an hour at +128% quantity pay ~15M gold, ~24 Upheaval, ~12 Fate solo.
	reward = {
		goldPerTier2 = 5000,
		chaos = {base = 0.5, perTier = 0.085},
		divine = {base = 0, perTier = 0.06},
		rolls = {base = 2, perTier = 0.5},
		lootTier = {{3, "magic"}, {6, "rare"}, {10, "legendary"}, {999, "boss"}}, -- {up to tier, loot layer tier}
		items = {chaos = 29856, divine = 29857}
	},

	-- next key from a completed rift (one per run, to the player who used the key, else a random finisher):
	-- chance = base + perMod x modifiers (capped at max), and of those `nextTier` + perMod x modifiers are tier + 1
	-- pity (R.keyGuarantee): `runs` sealed rifts in a row that left no stronger key (counter on the receiver, storage
	-- riftRun + 5) make the next one leave tier + 1; a finisher at `outlevel` x the tier's entry level or more always
	-- gets a key of the tier his level fits, at least +1, at most +maxJump (so tier 1 for level 1000 is a fast step)
	keyDrop = {base = 45, perMod = 10, max = 75, nextTier = 60, nextPerMod = 10,
		pity = {runs = 2, outlevel = 1.5, maxJump = 3}},
	-- rare / legendary monsters killed inside a rift: percent chance of a key of the rift's tier in the corpse
	eliteKeyChance = {rare = 4, legendary = 10},

	-- tier-1 keys from normal monsters (any map hunt, not inside a rift): per 100000 per kill, x tierMult of the
	-- monster's tier, when the monster (one of the bounty pool) has a hunting level of at least max(minMonsterLevel,
	-- killer level x levelShare) and the killer is at least minKillerLevel (tier 1 minLevel). Hunting levels since
	-- 2026-10-28 (O284, O285: baseLevelMult 1, so hunting level = pool level).
	monsterKey = {chance = 250, minMonsterLevel = 60, levelShare = 0.4,
		tierMult = {normal = 1, magic = 3, rare = 8, legendary = 20, boss = 40}},
	-- completed bounty contracts give a tier-1 key with this percent chance (players at tier 1 minLevel or more)
	bountyKey = {hunt = 25, elite = 50, boss = 100},

	-- ------------------------------------------------------------------ experience cap
	-- Experience comes from the kills only. So that a dense rift cannot beat open hunting, the BASE experience of rift
	-- kills (monster experience x the monster-level bonus x the stage x the magic/rare/legendary multiplier, before
	-- stamina, potions and the Chaos bonuses) is capped per player at capFactor x the leveling model's rate at the
	-- player's level, per minute spent in the run (at least capMinMinutes). Above the cap a kill gives overCapMult of its
	-- experience. The modifiers' Experience bonus applies on top (to what the cap lets through).
	-- model: the sorcerer's base hours per level band from server/README.md "The leveling model and the hours"
	-- (the fastest vocation, so the cap never cuts below open hunting for anyone). Levels past the last band use the
	-- last band's rate (the hours per level grow with the experience per level).
	exp = {
		capFactor = 1.1,
		overCapMult = 0.02,
		capMinMinutes = 1,
		model = {{1, 100, 0.3}, {100, 300, 2.6}, {300, 500, 7.3}, {500, 700, 21.8}, {700, 800, 17.2}, {800, 900, 21.1},
			{900, 1000, 25.5}}
	},

	-- ------------------------------------------------------------------ the instance (built at runtime)
	-- A grid of slots far from the map: slot i is at origin + (i % cols, i // cols) x spacing, floors z and z + 1.
	-- The real map has no tiles there (checked in the OTBM of the full map, 18,185,071 tiles: x/y 15360-30719 hold
	-- only 26 tiles, at 16735,16438,15 and near 18944,18944,7; the main continent starts at 30720; other runtime
	-- areas use x/y 2000-15359). The grid covers x/y 20480-21503. Before 2026-10-12 it was 16 slots of 64 sqm at 8192.
	grid = {origin = {x = 20480, y = 20480, z = 7}, cols = 4, rows = 4, spacing = 256, floors = 2},
	-- Every run gets a generated map (rift_layout_core.lua, the area generator's rift themes in areagen_config.lua).
	-- Each slot holds one built layout at a time; a run that ends hands its slot to the builder, which clears it and
	-- builds the next layout in short steps (`build`), so a key normally finds a slot ready (server/README.md "Rifts",
	-- Layouts and the slot pool).
	layout = {
		enabled = true,
		-- side of the square layout by key tier and the run's time limit (seconds): {up to tier, side, limit}. A two
		-- floor layout has twoFloorScale x the side on each floor (about 1.3x the area of one floor).
		sizes = {{5, 160, 1000}, {10, 200, 1100}, {15, 240, 1260}},
		-- walkable tiles and walking distance arrival -> arena of a typical layout per band (the mean of 16 layouts
		-- per band over the four themes, tests/rift_layout_test.lua keeps them honest): the density's model
		typical = {{walkable = 8500, route = 200}, {walkable = 14800, route = 265}, {walkable = 21200, route = 340}},
		twoFloorScale = 0.8,
		links = 2, -- holes (with a ladder below) per floor change
		arrivalInset = 10, -- the arrival this many cells from its corner
		-- the guardian's arena in the opposite corner: a chamber of `radius` (nothing in it within `clear`), in a
		-- dungeon a room of `room` x `room`
		arena = {radius = 9, clear = 6, room = 21, inset = 15},
		safeRadius = 12, -- no pack within this many sqm of the arrival
		section = 16, -- packs and reinforcements come by sections of section x section cells ...
		minCells = 24, -- ... with at least this many walkable cells
		attempts = 4, -- a layout the validator rejects is made again with another seed
		-- areagen layout parameters per kind; *Per10k counts scale with the area (per 10,000 cells)
		kinds = {
			cave = {fill = 0.53, steps = 5, spread = 2, minRegion = 60, tunnelRadius = 1, scale = 2, smooth = 2},
			waste = {fill = 0.47, steps = 4, spread = 1, minRegion = 80, tunnelRadius = 2, scale = 3, smooth = 2},
			mixed = {fill = 0.54, steps = 5, spread = 2, minRegion = 60, tunnelRadius = 1, scale = 2, smooth = 2,
				roomsPer10k = {3, 4}, room = {9, 15}, gap = 4},
			dungeon = {roomsPer10k = {11, 14}, room = {10, 19}, gap = 3, corridor = 3, loopsPer10k = {2, 3}}
		},
		-- per rift theme: the areagen theme, the layout kinds {kind, weight} and the floors {count, weight}
		themes = {
			["Abyssal Rift"] = {areagen = "rift_abyss", kinds = {{"waste", 55}, {"cave", 45}}, floors = {{1, 100}}},
			["Obsidian Hall"] = {areagen = "rift_hall", kinds = {{"dungeon", 65}, {"mixed", 35}}, floors = {{1, 60}, {2, 40}}},
			["Ashen Crypt"] = {areagen = "rift_crypt", kinds = {{"mixed", 50}, {"dungeon", 50}}, floors = {{2, 100}}},
			["Forsaken Sanctum"] = {areagen = "rift_sanctum", kinds = {{"cave", 65}, {"mixed", 35}}, floors = {{1, 70}, {2, 30}}}
		}
	},
	-- the slot builder: one layout at a time, in steps of at most sliceMs of game loop every everyMs (the generator
	-- runs in a coroutine and yields; the clean-up and the tiles go in batches); poolReady = the idle slots kept built
	-- and ready (more are built only when the keys ask for them)
	build = {sliceMs = 10, everyMs = 40, poolReady = 6, startDelayMs = 10000},
	-- the Ember Descent (descent.lua) still builds its halls with these: wall, light, dark set and theme floors
	wallId = 5648, -- stone wall
	basinId = 1481, -- coal basin (light)
	-- dark tile set (server/README.md "Dark tile set"): the Descent's walls and lights use these when installed, its
	-- floors the theme's darkStyle (data/lib/chaos_dark_paint.lua); the rifts take the dark palettes of their
	-- areagen themes instead
	dark = {enabled = true, wall = "obsidian_wall", basin = "brazier"},
	-- themes (names: the atlas, the looks, the Descent): grounds and darkStyle are the Descent's floors
	themes = {
		{name = "Abyssal Rift", grounds = {25549, 25704, 25705, 25706, 25707, 25708, 25709}, darkStyle = "abyss"}, -- "rift floor"
		{name = "Obsidian Hall", grounds = {407}, darkStyle = "hall"}, -- black marble floor
		{name = "Ashen Crypt", grounds = {13189, 12237}, darkStyle = "crypt"}, -- dark sandy floor, rutted stone floor
		{name = "Forsaken Sanctum", grounds = {415}, darkStyle = "sanctum"} -- gilded stone floor
	},

	-- ------------------------------------------------------------------ rift-exclusive looks
	-- Inside a rift every monster wears a look nothing outside the rifts uses (client outfits 2100-2115, donor creature
	-- art: client/tools/sprites/monster_looks/picks.csv; server/README.md "Rifts"). The theme picks the family; the run's
	-- monster types (sorted by level) get minion / brute / elite (one type: elite; two: brute and elite), the guardian
	-- (and both twins) the family's guardian look, and each look its name (`names`). Stats, spells, loot, corpse and
	-- credit stay the type's.
	-- Coffer waves and ambush copies wear the look too. Omen arenas keep their guardian's own look (its XML).
	-- enabled = false: every rift monster shows its world look and name again (a client pair without 2100+ shows nothing).
	looks = {
		enabled = true,
		families = {
			["Abyssal Rift"] = {minion = 2100, brute = 2101, elite = 2102, guardian = 2103}, -- eldritch
			["Obsidian Hall"] = {minion = 2104, brute = 2105, elite = 2106, guardian = 2107}, -- obsidian and magma
			["Ashen Crypt"] = {minion = 2108, brute = 2109, elite = 2110, guardian = 2111}, -- undead, ember-lit
			["Forsaken Sanctum"] = {minion = 2112, brute = 2113, elite = 2114, guardian = 2115} -- fungus blight
		},
		-- the name each look shows (creature packet, look text, damage, kill and loot lines, monster bar), per theme and
		-- rank. The family word comes first. Credit and drops stay with the pool type (bestiary, bounty, uniques, keys).
		-- A rank without a name keeps the type's name. Names must not be the name of a monster type (rift_test.lua).
		names = {
			["Abyssal Rift"] = {minion = "Abyssal Spawn", brute = "Abyssal Gazer", elite = "Abyssal Shade",
				guardian = "Abyssal Sovereign"},
			["Obsidian Hall"] = {minion = "Obsidian Hound", brute = "Obsidian Brute", elite = "Obsidian Ravager",
				guardian = "Obsidian Colossus"},
			["Ashen Crypt"] = {minion = "Crypt Thrall", brute = "Crypt Bonehulk", elite = "Crypt Reaper",
				guardian = "Crypt Dreadknight"},
			["Forsaken Sanctum"] = {minion = "Sanctum Sporeling", brute = "Sanctum Creeper", elite = "Sanctum Blightstone",
				guardian = "Sanctum Warden"}
		},
		-- rank variants: our own looks painted over the rank's look (same size, frames and timing; client looks 2200-2207,
		-- client/tools/sprites/rift_variants.py, art_import/rift_variants.csv, monster_looks/rift_variant_picks.csv). A
		-- pack monster of a rank listed here wears one of its variants (evenly) with chance variantShare, else the rank's
		-- look; each variant shows its own name (family word first, never a monster type's name). Guardians have none.
		-- variantsOn: on since 2026-10-13 (pair 24 at 407ad9b6 has looks 2200-2207; an older pair draws nothing).
		variantsOn = true,
		variantShare = 0.4,
		variants = {
			["Abyssal Rift"] = {
				minion = {{look = 2202, name = "Abyssal Bloodeel"}}, -- crimson eel, bone fins, amber eye (base 2100)
				brute = {{look = 2200, name = "Abyssal Pallid Gazer"}}, -- bone-white, teal tentacles, cyan eyes (base 2101)
				elite = {{look = 2203, name = "Abyssal Runeshade"}} -- indigo shade, bone mask, cyan runes (base 2102)
			},
			["Obsidian Hall"] = {
				elite = {{look = 2204, name = "Obsidian Ashmane"}} -- ash-dusted obsidian, blue-white spirit-fire mane (base 2106)
			},
			["Ashen Crypt"] = {
				minion = {{look = 2205, name = "Crypt Ashwalker"}} -- pale ash skeleton, ember cracks, red hood (base 2108)
			},
			["Forsaken Sanctum"] = {
				minion = {{look = 2201, name = "Sanctum Gloomcap"}}, -- violet toadstool, pale green spots (base 2112)
				brute = {{look = 2206, name = "Sanctum Thornrot"}}, -- crimson-brown thorn vines, orange pustules (base 2113)
				elite = {{look = 2207, name = "Sanctum Mosstomb"}} -- grave-stone boulder, ash fungus, shelf mushrooms (base 2114)
			}
		},
		-- bigger guardians: 4x4 looks of our own painted over a guardian's frames with an 8-frame walk and a 4-frame idle
		-- (client/tools/sprites/big_bosses.py, spec monster_looks/big_bosses.json, art_import/big_bosses*; client looks
		-- 2208-2212). With bigGuardiansOn a rift guardian (and both Twin Guardians) and an Omen guardian whose own look is
		-- listed here wear the big look; name, stats, spells and loot stay. bigGuardiansOn: on since 2026-10-13 (pair
		-- 24 at 407ad9b6 has looks 2208-2212; an older pair draws nothing).
		bigGuardiansOn = true,
		bigGuardians = {
			[2103] = 2208, -- Abyssal Sovereign: void spectre, 8-frame walk (was 3 phases)
			[2107] = 2209, -- Obsidian Colossus: magma golem, 8-frame walk (was 2 phases)
			[2111] = 2210, -- Crypt Dreadknight: black plate knight, 3x3 -> 4x4 repaint, 8-frame walk (was 2 phases)
			[2115] = 2211, -- Sanctum Warden: moss golem, 8-frame walk (was 3 phases)
			[2118] = 2212 -- Thalcyra the Stormbound Seer (Omen): storm seer, 3x3 -> 4x4 repaint, 8-frame walk (was 4)
		}
	}
}
