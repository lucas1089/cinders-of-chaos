-- Spell supports: every number (data/lib/chaos_supports.lua reads it; overview data/scripts/chaos/SUPPORTS.md).
-- Plain table, loaded with  ChaosSupportsConfig = dofile("data/lib/chaos_supports_config.lua"). It is read in two Lua
-- states: the scripts state (data/scripts/chaos/supports.lua: sockets, window, hit effects, drops) and the spell state
-- (data/spells/chaos/_supports.lua: cast context, mana refund, cooldown). Lua 5.1 / LuaJIT and 5.3.
--
-- Item ids: one server id per support and level, firstId + (type - 1) * 5 + (level - 1) = 32101..32200. They are new
-- items.otb nodes (server/tools/install_supports.py), copies of the stock rune stones named in `sprites` (stackable,
-- use-with), so the client needs no new sprite. Ranges in use: gems 32001..32035, salvage 32051, art 33000..,
-- pack items 36000.., donor items 40000...

return {
	firstId = 32101,
	levels = 5,

	-- the five levels carry the item rarity names and colours (Common .. Mythic of the gear rarities)
	levelNames = {"Common", "Rare", "Epic", "Legendary", "Mythic"},
	levelColors = {"#c4cebc", "#1e963e", "#e32121", "#f6fa07", "#a30ff6"},

	-- stock rune stones (server id -> client sprite) the items copy; index = `sprite` of a support
	sprites = {24685, 24686, 24687, 24689, 24690, 24693, 24694, 24695, 24696, 24698},

	-- what a spell is, for the compatibility rules (supports.lua works it out from data/spells/spells.xml with the
	-- spellbook parser: damage + single target = single, damage otherwise = area, heal = heal, the rest = buff).
	-- override: spell id -> kind, where the parse is wrong. none: spells that never get sockets.
	kinds = {"single", "area", "heal", "buff"},
	kindNames = {single = "single target", area = "area", heal = "healing", buff = "buff / utility"},
	-- (checked against the parse of every Chaos spell on a test server: the strikes that deal damage through a helper,
	-- ChaosSpell.weaponStrike / the Monk and Templar helpers, read as buffs)
	kindOverride = {
		[202] = "single", -- Forked Storm: one bolt that jumps
		[242] = "single", -- Shuriken Barrage: one target plus jumps
		[219] = "single", -- Hail of Dawn: every arrow on the target
		[185] = "area", -- Corpse Explosion: bursts around the target
		[203] = "buff", -- Crimson Covenant: health into mana, not a heal
		[186] = "buff", -- Bone Golem: a summon
		[182] = "single", -- Withering Curse
		[188] = "area", -- Bone Offering: a skeleton bursts
		[63] = "single", [64] = "single", [68] = "single", [69] = "single", [71] = "single", -- Monk strikes
		[189] = "single", [198] = "single", -- Radiant Smite, Judgement
		[236] = "single", [240] = "single", [244] = "single", -- Shuriken Toss, Shadow Step, Iaijutsu
		[73] = "area", [74] = "area", -- Blade Flurry, Iaido Sweep (weapon strikes on every monster hit)
		-- the pack tools (data/spells/chaos/_packtools.lua): Palm Shockwave, Shadow Ricochet, Iron Chain, Bone Shrapnel,
		-- Sanctified Ground, Shield Wave, Fan of Knives
		[194] = "area", [195] = "area", [196] = "area", [197] = "area", [137] = "area", [170] = "area", [136] = "area",
		-- the snares (data/spells/chaos/_snares.lua): a brand rune socketed in them picks their element
		[99] = "area", [100] = "area", [104] = "buff", -- Snare Trap, Seeker Mine, Detonate Mines
		-- the attack kit (owner 2026-10-23, data/spells/chaos/_attackkit.lua; the strikes are dealt by the shared cast, so
		-- the parse sees no damage call): single target and damage over time
		[2] = "single", [19] = "single", [23] = "single", [24] = "single", [43] = "single", [45] = "single",
		[57] = "single", [80] = "single", [82] = "single", [88] = "single", [90] = "single", [106] = "single",
		[113] = "single", [121] = "single", [127] = "single", [131] = "single", [138] = "single", [140] = "single",
		-- the attack kit: circles, bursts around the caster, waves and lines
		[9] = "area", [22] = "area", [38] = "area", [56] = "area", [62] = "area", [84] = "area", [87] = "area",
		[89] = "area", [107] = "area", [112] = "area", [118] = "area", [119] = "area", [120] = "area", [122] = "area",
		[126] = "area", [128] = "area", [129] = "area", [139] = "area", [141] = "area",
	},

	-- ------------------------------------------------------------------ the supports
	-- key, name (item: "<level name> <name> rune"), sprite (index into sprites), weight (drops), fits = spell kinds,
	-- group (one support of a group per spell), values per level (value2 where a support has two numbers),
	-- text = the effect, %1 = value, %2 = value2. icon = client/overlay/data/images/game/supports/<key>.png
	supports = {
		{key = "emberbrand", name = "Emberbrand", sprite = 1, weight = 6, fits = {"single", "area"}, group = "brand",
			element = "fire", values = {20, 30, 40, 50, 60},
			text = "%1%% of the spell's damage becomes fire damage"},
		{key = "rimebrand", name = "Rimebrand", sprite = 2, weight = 6, fits = {"single", "area"}, group = "brand",
			element = "ice", values = {20, 30, 40, 50, 60},
			text = "%1%% of the spell's damage becomes ice damage"},
		{key = "dawnbrand", name = "Dawnbrand", sprite = 3, weight = 6, fits = {"single", "area"}, group = "brand",
			element = "holy", values = {20, 30, 40, 50, 60},
			text = "%1%% of the spell's damage becomes holy damage"},
		{key = "gravebrand", name = "Gravebrand", sprite = 4, weight = 6, fits = {"single", "area"}, group = "brand",
			element = "death", values = {20, 30, 40, 50, 60},
			text = "%1%% of the spell's damage becomes death damage"},
		{key = "stormbrand", name = "Stormbrand", sprite = 5, weight = 6, fits = {"single", "area"}, group = "brand",
			element = "energy", values = {20, 30, 40, 50, 60},
			text = "%1%% of the spell's damage becomes energy damage"},
		{key = "quickening", name = "Quickening", sprite = 6, weight = 10, fits = {"single", "area", "heal", "buff"},
			values = {6, 9, 12, 15, 18},
			text = "Cooldown -%1%%"},
		{key = "thrift", name = "Thrift", sprite = 6, weight = 10, fits = {"single", "area", "heal", "buff"},
			values = {6, 9, 12, 15, 20},
			text = "Mana cost -%1%%, given back right after the cast"},
		{key = "keenedge", name = "Keen Edge", sprite = 7, weight = 9, fits = {"single", "area"},
			values = {2, 3, 5, 6, 8}, values2 = {50, 50, 50, 50, 50}, -- two thirds, like every crit chance (patch 0004)
			text = "+%1%% chance per hit to strike critically for +%2%% damage"},
		{key = "echo", name = "Echo", sprite = 8, weight = 7, fits = {"single", "area"},
			values = {15, 20, 25, 30, 35}, values2 = {50, 50, 50, 50, 50},
			text = "%1%% chance per cast that the spell's hits strike again 0.5 s later for %2%% damage"},
		{key = "fork", name = "Fork", sprite = 8, weight = 7, fits = {"single"},
			values = {1, 1, 2, 2, 3}, values2 = {35, 40, 45, 50, 55},
			text = "The hit forks to %1 more enemies within 3 sqm for %2%% of it"},
		{key = "breadth", name = "Breadth", sprite = 9, weight = 7, fits = {"area"},
			values = {1, 1, 1, 1, 2}, values2 = {35, 40, 45, 50, 55},
			text = "Enemies within %1 sqm of the hit ones that the spell missed take %2%% of the average hit (max 6)"},
		{key = "shatter", name = "Shatter", sprite = 9, weight = 7, fits = {"single"},
			values = {20, 25, 30, 35, 40},
			text = "Enemies next to the target take %1%% of the hit (max 4)"},
		{key = "deathburst", name = "Deathburst", sprite = 10, weight = 6, fits = {"single", "area"},
			values = {25, 30, 35, 40, 50},
			text = "A kill by the spell bursts the corpse: enemies within 2 sqm take %1%% of the killing hit (once per cast)"},
		{key = "surge", name = "Surge", sprite = 7, weight = 6, fits = {"single", "area"},
			values = {30, 35, 40, 50, 60},
			text = "A critical hit of the spell blasts the enemies next to the target for %1%% of it (once per cast)"},
		{key = "reprisal", name = "Reprisal", sprite = 10, weight = 6, fits = {"single", "area", "heal", "buff"},
			values = {40, 55, 70, 85, 100},
			text = "For 8 s after the cast, a monster's hit on you has a 25%% chance to strike it back for %1%% of the hit"},
		{key = "bloodthirst", name = "Bloodthirst", sprite = 4, weight = 8, fits = {"single", "area"},
			values = {2, 3, 4, 5, 6},
			text = "Heals you for %1%% of the spell's damage (at most 8%% of your max health per cast)"},
		{key = "siphon", name = "Siphon", sprite = 2, weight = 8, fits = {"single", "area"},
			values = {10, 15, 20, 25, 30},
			text = "Restores %1 mana per 1000 damage of the spell (at most 5%% of your max mana per cast)"},
		{key = "sunder", name = "Sunder", sprite = 1, weight = 7, fits = {"single", "area"},
			values = {5, 8, 11, 14, 18},
			text = "Ignores %1 points of a monster's resistance to the spell's element (never below 0)"},
		{key = "hex", name = "Hex", sprite = 3, weight = 7, fits = {"single", "area"},
			values = {3, 4, 5, 6, 8},
			text = "Monsters hit take +%1%% damage from everyone for 4 s (the strongest hex counts)"},
		{key = "mercy", name = "Mercy", sprite = 5, weight = 7, fits = {"heal"},
			values = {5, 8, 11, 14, 18},
			text = "The spell heals %1%% more"},
	},

	-- caps on the summed value of one support key on one spell (with option 2, extra sources may add up)
	caps = {quickening = 30, thrift = 30, keenedge = 13, echo = 40, bloodthirst = 8, siphon = 40, sunder = 25,
		hex = 10, mercy = 25},

	-- the fixed numbers of the effects
	effect = {
		cooldownMinMs = 1000, -- Quickening never takes a cooldown below this
		echoDelay = 500, -- ms
		forkRange = 3,
		breadthMax = 6,
		shatterMax = 4,
		burstRadius = 2,
		reprisalWindow = 8, -- seconds after the cast
		reprisalChance = 25, -- percent per monster hit
		reprisalCooldown = 1000, -- ms between two strikes back
		reprisalMaxShare = 25, -- a strike back is at most this % of your max health
		bloodthirstMaxShare = 8, -- % of max health per cast
		siphonMaxShare = 5, -- % of max mana per cast
		hexDuration = 4000 -- ms
	},

	-- ------------------------------------------------------------------ sockets
	-- 1st socket: when the character may cast the spell. 2nd: character level >= spell level + second.add (at least
	-- second.min). 3rd: level >= spell level + third.add (at least third.min) and opened once per spell and character
	-- with third.orbs Orbs of Sockets (chaos_gems_config.lua socketOrb) at the support window.
	maxSockets = 3,
	second = {add = 60, min = 80},
	third = {add = 150, min = 200, orbs = 2},

	-- removing a rune at the window: "Remove" gives it back for this much gold by level (bank first, then the
	-- backpack), "Shatter" destroys it for free. The same numbers as the gems (chaos_gems_config.lua removeCost).
	removeCost = {2000, 6000, 20000, 60000, 200000},

	-- ------------------------------------------------------------------ storages (player)
	-- base + spell id * 4 + 0: 1 = the 3rd socket is opened; + 1..3: the rune (server id) in that socket.
	-- 7110000 - 7111999 reserved (spell ids 0 .. 499). The cast context keys sit just below.
	storageBase = 7110000,
	maxSpellId = 499,
	storageContext = 7109990, -- serial * 1000 + spell id while a spell's own hits run (spell state writes it)
	storageReprisal = 7109991, -- spell id of the last cast with Reprisal
	storageReprisalUntil = 7109992, -- os.time() until Reprisal answers hits

	-- which spells get sockets: instants with a spell id of their own (a spell id used twice gets none), not
	-- conjuring, not house spells. stockSpells = false limits it to the Chaos spells (scripts under chaos/).
	stockSpells = true,
	none = {},

	-- ------------------------------------------------------------------ drops (the Chaos loot layer, loot.lua)
	-- chance per kill in 1/10000 by monster tier x the loot layer's rate x item find (gems: 25/150/500/1500/3000)
	drop = {
		chance = {normal = 10, magic = 60, rare = 200, legendary = 700, boss = 1500},
		-- level weights by monster level: the gems' table (chaos_gems_config.lua drop.levelWeights)
		tierUp = {legendary = 25, boss = 40}
	},
	-- rewards: like the gems' (count = runes per reward, a fraction is the chance of one more; weights = level 1..5)
	rewards = {
		rift = {base = 0.3, perTier = 0.1,
			tierWeights = {{3, {60, 35, 5, 0, 0}}, {6, {30, 45, 20, 5, 0}}, {10, {10, 35, 35, 17, 3}},
				{999, {0, 20, 40, 30, 10}}}},
		bounty = {chance = {hunt = 10, elite = 20, boss = 50}, count = 1}, -- band weights: the gems' bounty table
		worldboss = {count = 1, countShare = 1, weights = {0, 15, 45, 30, 10}}
	}
}
