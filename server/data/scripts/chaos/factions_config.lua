-- factions_config.lua: every number of the factions (factions.lua, factions_core.lua; server/README.md "Factions").
-- Plain table, loaded with  Chaos.factionsConfig = dofile("data/scripts/chaos/factions_config.lua")
-- No engine calls here (server/tests/factions_test.lua reads it with plain Lua). Lua 5.1 / LuaJIT and Lua 5.3.
-- server/tools/install_factions.py reads `tokens` (the four token items) from this file.
--
-- Reputation is per character (season characters are characters of their own: they start at Neutral everywhere).
-- Every gain goes through ChaosFactionsCore.gain: activity sources (kills, bounties, tokens, rifts, invasions, world
-- bosses) lose value after `daily.bands` reputation per faction and day, contracts do not; nothing passes the weekly cap
-- of a faction; a gain lowers the rival faction by `rivalry.share` of it (never below `rivalry.floor`, never once the
-- rival is Exalted). Nothing locks content: a Hostile faction still talks, offers contracts and takes tokens.

local UPHEAVAL, FATE, GRAFTING, AWAKENING, GILDING = 29856, 29857, 29855, 29851, 24691
local WHETSTONE, TEMPERING, BINDING, REFORGING = 32256, 32251, 32252, 32254
local SHARD = 32051 -- salvage Rune Shard (salvage_config.lua)

return {
	enabled = true,
	opcode = 215, -- ChaosOpcodes.factions (client game_factions)
	tables = {
		rep = "chaos_factions", -- one row per character and faction (sql/chaos_factions.sql)
		contracts = "chaos_faction_contracts", -- contract progress per character, period and slot
		purchases = "chaos_faction_purchases" -- quartermaster unlocks (week 0) and weekly limited offers
	},
	staffGroup = 4, -- /faction <character>, <faction>, <amount>
	dayHour = 6, -- the faction day runs from this hour to this hour; the week starts on Monday at this hour (bounty board rule)
	requestMs = 400, -- per player, between two window requests
	npcRange = 6, -- quartermaster purchases, token turn-ins, deliveries and recipes need the faction's NPC this close
	multiClientRep = false, -- kills of a multi-client character give no faction reputation (contracts still count)

	-- the bar: reputation goes from rep.min to rep.max (the Exalted threshold; more is not kept)
	rep = {min = -6000, max = 36000, start = 0},
	ranks = {
		{key = "hostile", name = "Hostile", min = -6000, color = "#c9301f"},
		{key = "wary", name = "Wary", min = -2000, color = "#d07a3a"},
		{key = "neutral", name = "Neutral", min = 0, color = "#b8b0a0"},
		{key = "trusted", name = "Trusted", min = 2500, color = "#7fc86a"},
		{key = "honored", name = "Honored", min = 8000, color = "#5fb0e8"},
		{key = "revered", name = "Revered", min = 18000, color = "#b98ae8"},
		{key = "exalted", name = "Exalted", min = 36000, color = "#f6cf72"}
	},

	-- diminishing returns per faction and faction day on activity reputation (contracts are exempt): the first 600 at
	-- full value, the next 600 at half, everything after at a fifth
	daily = {bands = {{upTo = 600, mult = 1.0}, {upTo = 1200, mult = 0.5}, {mult = 0.2}}},
	weeklyCap = 7500, -- per faction and week, every source together (rivalry losses do not count)
	-- the unused cap of a week (and of every week skipped) carries over: a week's cap is weeklyCap + the carried part,
	-- at most rolloverWeeks weeks' worth (3: 22,500). A player who misses two weeks catches up in the third.
	-- (2026-10-15, respect the players' time; docs/OWNER_TODO.md "Time-friendly progression")
	rolloverWeeks = 3,
	rivalry = {share = 0.25, floor = -2000, swornAtExalted = true},

	-- activity sources
	sources = {
		-- a kill of a monster of one of the faction's bestiary categories (bestiary_config.lua) at or above
		-- minLevelShare x the character's level: points by monster tier, every `pointsPerRep` points = 1 reputation
		kill = {points = {normal = 1, magic = 3, rare = 8, legendary = 25}, pointsPerRep = 10, minLevelShare = 0.4},
		bounty = 60, -- a completed bounty contract whose monster belongs to the faction (bounty.lua)
		token = 40, -- per faction token turned in at the faction's NPC
		rift = {base = 30, perTier = 6}, -- a sealed rift of the faction's theme (not an Omen guardian)
		invasion = 100, -- a rewarded share of an invasion of an invader the faction fights (invasion.lua)
		worldBoss = 150 -- a rewarded share of the faction's world boss (worldboss.lua)
	},

	-- faction tokens drop from the faction's content into the killer's backpack (inbox when full): monsters of its
	-- categories (per 10000, by tier; only at or above the kill's level rule), its world boss and rift seals
	-- (count), invasion rewards of its invaders (count). install_factions.py adds them to items.otb / items.xml
	-- (stackable copies of the stock node sourceId; the client keeps the stock sprite).
	tokenDrop = {chance = {normal = 4, magic = 25, rare = 120, legendary = 600}, minMonsterLevel = 60,
		worldBoss = 5, riftSeal = 1, riftSealPerTiers = 5, invasion = 2},

	-- contracts: per faction `daily` contracts each faction day and `weekly` each week, generated from a seed (character,
	-- period, faction, slot), so the same character sees the same contracts all period. The character's level at the
	-- first look is stored with the progress and used again for every later look.
	contracts = {
		daily = 2,
		weekly = 1,
		rep = {daily = 300, weekly = 1200},
		gold = {daily = 0, weekly = 0}, -- no gold reward: reputation only
		-- kinds a slot is drawn from (weights); a kind that cannot be made (no family in the level window) is skipped
		dailyKinds = {{"kill", 50}, {"rift", 25}, {"deliver", 25}},
		weeklyKinds = {{"worldboss", 30}, {"invasion", 30}, {"riftmany", 20}, {"delivermany", 20}},
		kill = {count = {120, 200}, step = 10, minLevelShare = 0.4}, -- monsters of one family of the faction
		rift = {count = 1, tierBelow = 1}, -- one rift of the theme, tier = the highest the character may open minus this
		riftmany = {count = 3, tierBelow = 2},
		worldboss = {count = 1},
		invasion = {count = 1}, -- any invasion counts (they come a few times a day)
		-- material sink: rune shards and gold handed to the NPC
		deliver = {items = {{id = SHARD, count = {15, 25}}}, gold = {perLevel = 150, min = 20000, max = 150000}},
		delivermany = {items = {{id = SHARD, count = {60, 90}}}, gold = {perLevel = 500, min = 60000, max = 500000}}
	},

	-- the four token items (install_factions.py): server ids 32091..32094 (free range between the pouches 32081..32083
	-- and the support runes 32101..; ranges listed in tools/install_omens.py)
	tokens = {
		vigil = {id = 32091, sourceId = 20130, article = "a", name = "pyre ash sigil", plural = "pyre ash sigils", weight = 10,
			description = "Ash from a Vigil pyre, pressed into a seal. The Ashen Vigil takes it as proof of the dead put back to rest."},
		compact = {id = 32092, sourceId = 25378, article = "a", name = "cinderforge seal", plural = "cinderforge seals", weight = 20,
			description = "A copper seal struck at the obsidian forges. The Cinderforge Compact pays its debts in these."},
		choir = {id = 32093, sourceId = 12627, article = "a", name = "veiled eye", plural = "veiled eyes", weight = 10,
			description = "It still blinks. The Veiled Choir collects what looked back from the rifts."},
		circle = {id = 32094, sourceId = 15546, article = "a", name = "thornbound leaf", plural = "thornbound leaves", weight = 5,
			description = "A leaf grown through a blight scar. The Thornbound Circle counts every one it is brought."}
	},

	-- ======================================================================= the factions
	-- categories: bestiary categories (bestiary_config.lua) whose kills count; theme: rift theme (rift_config.lua);
	-- invaders: invasion factions (invasion_config.lua) it fights; bosses: world boss names (parts, lower case);
	-- rival: the faction a gain lowers. npc: the home NPC (data/npc/<name>.xml), placed at startup next to the temple of
	-- `town` (a name or an id; `townId` when the name is not on the map) on the first free offset.
	factions = {
		{key = "vigil", name = "The Ashen Vigil", short = "Vigil", color = "#e0a050", rival = "choir",
			lore = "Pyre-wardens who burn what will not stay dead. Since the Cinders fell, their bells ring at every grave that stirs, and they ring for the rifts too.",
			categories = {"undead", "humans"}, theme = "Ashen Crypt", invaders = {"undead"}, bosses = {"vharok"},
			npc = {name = "Warden Ysolde", town = "Cinderhold", townId = 2},
			titles = {honored = "Pyrewarden", revered = "Bellkeeper of the Vigil", exalted = "Ashen Saint"},
			frame = "bone"},
		{key = "compact", name = "The Cinderforge Compact", short = "Compact", color = "#e0603a", rival = "circle",
			lore = "Smiths and sellswords sworn to the obsidian forges. They pay in steel for whatever others fear to dig up, and they fear nothing that burns.",
			categories = {"demons", "constructs", "humanoids"}, theme = "Obsidian Hall", invaders = {"orcs", "minotaurs"},
			bosses = {"kaelgor"}, npc = {name = "Forgemaster Brannoc", town = 1, townId = 1},
			titles = {honored = "Forgesworn", revered = "Anvilguard", exalted = "Cinderlord"},
			frame = "ember"},
		{key = "choir", name = "The Veiled Choir", short = "Choir", color = "#b07ae8", rival = "vigil",
			lore = "Seers who listen at the rifts and sing back. What answers, they bargain with. The Vigil calls it heresy; the Choir calls it knowledge.",
			categories = {"magic", "dragons", "aquatic", "elementals"}, theme = "Abyssal Rift", invaders = {"demons"},
			bosses = {"nyxareth", "skaldra"}, npc = {name = "Cantor Velith", town = "Bellwatch", townId = 11},
			titles = {honored = "Veilsinger", revered = "Voice of the Rift", exalted = "Abyss-Tongued"},
			frame = "violet"},
		{key = "circle", name = "The Thornbound Circle", short = "Circle", color = "#6fb85a", rival = "compact",
			lore = "Wardens of root and rot. They cut the blight out of the Forsaken Sanctum before it reaches the fields, and they hate the furnaces that eat their forests.",
			categories = {"plants", "beasts", "vermin", "reptiles", "birds", "slimes"}, theme = "Forsaken Sanctum",
			invaders = {"goblins", "wildwood"}, bosses = {"rotmother"}, npc = {name = "Elder Bramwyn", town = "Thornmere", townId = 4},
			titles = {honored = "Thornwarden", revered = "Rootkeeper", exalted = "Heart of the Thorn"},
			frame = "verdant"}
	},
	-- where the NPCs may stand around the temple (first free tile; the Ascendant Oracle and the Keeper of Trials use
	-- the closer ring)
	npcOffsets = {{4, -3}, {-4, -3}, {4, 3}, {-4, 3}, {5, 0}, {-5, 0}, {0, 5}, {0, -5}, {5, -2}, {-5, 2}},

	-- ======================================================================= the quartermasters
	-- One list per faction. rank = the rank key needed. price = gold (carried or bank), tokens = that faction's tokens.
	-- kinds:
	--   gear     a fixed item: base `id` of item kind `kind` (chaos_item_mods.lua M.kindOf), `rarity` (1..15), item
	--            `level`, `mods` = {{key, tier}} (Chaos modifier keys of chaos_item_mods.lua; each value is the middle of
	--            its tier's range). Checked against chaos_item_mods.lua (tests): the tier is allowed at the level, the
	--            kind may carry it, no more than the rarity's count and side limits. A catch-up and target-farm path:
	--            never above item level 125, rarity Epic, T7 (top drops: 145-150, up to 6 modifiers, T8).
	--   orbs     items = {{id, count}}; weekly = purchases per week
	--   recipe   bought once; then `craft` = {inputs = {{id, count}}, tokens = n, gold = n, output = {{id, count}}} at the NPC
	--   aura     the faction tabard aura: an aura of data/XML/auras.xml, exclusive (ids 25..28, data/XML/chaos_auras_donor.csv,
	--            looks 2136..2139 of things_custom14; the former placeholders 14, 15, 24, 23 are store auras only again)
	--   mount    the faction mount: a mount of data/XML/mounts.xml, exclusive (ids 142..145, tools/install_outfits.py,
	--            looks 2132..2135; the former placeholders 46, 30, 50, 54 stay store mounts only)
	-- Titles (by rank, with the faction frame at Exalted) are earned, not bought: `titles` above.
	offers = {
		vigil = {
			{key = "vigil_ash5", kind = "orbs", rank = "trusted", name = "Ash-Blessed Orbs", price = 150000, weekly = 3,
				items = {{id = UPHEAVAL, count = 5}}},
			{key = "vigil_recipe", kind = "recipe", rank = "honored", name = "Recipe: Pyre Distillation", price = 100000,
				craft = {inputs = {{id = SHARD, count = 40}}, tokens = 3, gold = 10000, output = {{id = FATE, count = 1}}}},
			{key = "vigil_helm", kind = "gear", rank = "honored", name = "Vigil Warden's Helm", price = 250000, tokens = 10,
				id = 2491, itemKind = "helmet", rarity = 4, level = 100, mods = {{"monsterreduction", 5}, {"regen", 5}, {"lifeonkill", 5}}},
			{key = "vigil_fate2", kind = "orbs", rank = "revered", name = "Pyre-Sealed Fate", price = 300000, weekly = 2,
				items = {{id = FATE, count = 2}}},
			{key = "vigil_plate", kind = "gear", rank = "revered", name = "Vigil Pyreplate", price = 600000, tokens = 20,
				id = 2487, itemKind = "armor", rarity = 4, level = 115, mods = {{"monsterreduction", 6}, {"thorns", 6}, {"regen", 6}}},
			{key = "vigil_aura", kind = "aura", rank = "revered", name = "Vigil Tabard: Pyrelight Mantle (aura)", price = 300000, tokens = 15, aura = 25},
			{key = "vigil_shield", kind = "gear", rank = "exalted", name = "Bulwark of the Last Pyre", price = 1500000, tokens = 40,
				id = 2514, itemKind = "shield", rarity = 4, level = 125, mods = {{"block", 7}, {"reflect", 7}, {"regen", 7}}},
			{key = "vigil_mount", kind = "mount", rank = "exalted", name = "Pyrewarden Charger (mount)", price = 2000000, tokens = 60, mount = 142}
		},
		compact = {
			{key = "compact_whet", kind = "orbs", rank = "trusted", name = "Forge Whetstones", price = 120000, weekly = 3,
				items = {{id = WHETSTONE, count = 10}}},
			{key = "compact_recipe", kind = "recipe", rank = "honored", name = "Recipe: Cinder Tempering", price = 100000,
				craft = {inputs = {{id = SHARD, count = 15}}, tokens = 2, gold = 5000, output = {{id = TEMPERING, count = 2}}}},
			{key = "compact_sword", kind = "gear", rank = "honored", name = "Compact Warblade", price = 250000, tokens = 10,
				id = 2408, itemKind = "weapon", rarity = 4, level = 100, mods = {{"bossdamage", 5}, {"physpen", 5}, {"attackspeed", 5}}},
			{key = "compact_graft", kind = "orbs", rank = "revered", name = "Forgemaster's Graft", price = 900000, weekly = 1,
				items = {{id = GRAFTING, count = 1}}},
			{key = "compact_legs", kind = "gear", rank = "revered", name = "Anvilguard Greaves", price = 600000, tokens = 20,
				id = 2495, itemKind = "legs", rarity = 4, level = 115, mods = {{"dodge", 6}, {"thorns", 6}, {"regen", 6}}},
			{key = "compact_aura", kind = "aura", rank = "revered", name = "Compact Tabard: Forgeflame Ring (aura)", price = 300000, tokens = 15, aura = 26},
			{key = "compact_axe", kind = "gear", rank = "exalted", name = "Cinderlord's Cleaver", price = 1500000, tokens = 40,
				id = 7434, itemKind = "weapon", rarity = 4, level = 125, mods = {{"bossdamage", 7}, {"physpen", 7}, {"attackspeed", 7}}},
			{key = "compact_mount", kind = "mount", rank = "exalted", name = "Forgeborn Emberwolf (mount)", price = 2000000, tokens = 60, mount = 143}
		},
		choir = {
			{key = "choir_gild", kind = "orbs", rank = "trusted", name = "Choir Gilding", price = 140000, weekly = 3,
				items = {{id = GILDING, count = 3}}},
			{key = "choir_recipe", kind = "recipe", rank = "honored", name = "Recipe: Veiled Binding", price = 100000,
				craft = {inputs = {{id = SHARD, count = 50}}, tokens = 3, gold = 10000, output = {{id = BINDING, count = 1}}}},
			{key = "choir_tiara", kind = "gear", rank = "honored", name = "Veilsinger's Circlet", price = 250000, tokens = 10,
				id = 3971, itemKind = "helmet", rarity = 4, level = 100, mods = {{"monsterreduction", 5}, {"cdr", 5}, {"manacost", 5}}},
			{key = "choir_fate2", kind = "orbs", rank = "revered", name = "Rift-Heard Fate", price = 300000, weekly = 2,
				items = {{id = FATE, count = 2}}},
			{key = "choir_amulet", kind = "gear", rank = "revered", name = "Voice of the Rift", price = 600000, tokens = 20,
				id = 2131, itemKind = "jewel", rarity = 4, level = 115, mods = {{"elepen", 6}, {"cdr", 6}, {"manaonkill", 6}}},
			{key = "choir_aura", kind = "aura", rank = "revered", name = "Choir Tabard: Veiled Eyes (aura)", price = 300000, tokens = 15, aura = 27},
			{key = "choir_wand", kind = "gear", rank = "exalted", name = "Abyss-Tongue Wand", price = 1500000, tokens = 40,
				id = 8920, itemKind = "weapon", rarity = 4, level = 125, mods = {{"elepen", 7}, {"dot", 7}, {"manaonhit", 7}}},
			{key = "choir_mount", kind = "mount", rank = "exalted", name = "Veilrunner (mount)", price = 2000000, tokens = 60, mount = 144}
		},
		circle = {
			{key = "circle_wake", kind = "orbs", rank = "trusted", name = "Seed Orbs", price = 80000, weekly = 3,
				items = {{id = AWAKENING, count = 5}}},
			{key = "circle_recipe", kind = "recipe", rank = "honored", name = "Recipe: Thorn Reforging", price = 100000,
				craft = {inputs = {{id = SHARD, count = 35}}, tokens = 3, gold = 10000, output = {{id = REFORGING, count = 1}}}},
			{key = "circle_boots", kind = "gear", rank = "honored", name = "Thornwarden's Treads", price = 250000, tokens = 10,
				id = 7886, itemKind = "boots", rarity = 4, level = 100, mods = {{"dodge", 5}, {"movespeed", 5}}},
			{key = "circle_up10", kind = "orbs", rank = "revered", name = "Root-Bound Upheaval", price = 280000, weekly = 2,
				items = {{id = UPHEAVAL, count = 10}}},
			{key = "circle_legs", kind = "gear", rank = "revered", name = "Rootkeeper's Leggings", price = 600000, tokens = 20,
				id = 2470, itemKind = "legs", rarity = 4, level = 115, mods = {{"dodge", 6}, {"regen", 6}, {"goldfind", 6}}},
			{key = "circle_aura", kind = "aura", rank = "revered", name = "Circle Tabard: Thornfire Wreath (aura)", price = 300000, tokens = 15, aura = 28},
			{key = "circle_amulet", kind = "gear", rank = "exalted", name = "Heart of the Thorn", price = 1500000, tokens = 40,
				id = 2171, itemKind = "jewel", rarity = 4, level = 125, mods = {{"bossdamage", 7}, {"lifeonkill", 7}, {"healing", 7}}},
			{key = "circle_mount", kind = "mount", rank = "exalted", name = "Thornbound Stag (mount)", price = 2000000, tokens = 60, mount = 145}
		}
	},
	-- the gear rules the tests hold every gear offer to (see `offers`)
	gearLimits = {maxLevel = 125, maxRarity = 4, maxTier = 7},

	-- the weekly Reputation board (leaderboard_config.lua "factions"): reputation gained this week, every faction
	leaderboard = {board = "factions", mode = "add"},
	-- achievements_data.lua stats: faction_exalted_<key> (1 once Exalted) and faction_exalted (how many are)
	achievementStats = true
}
