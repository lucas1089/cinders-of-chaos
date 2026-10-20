-- Conquest Tokens: every number of the deterministic progression path (conquest.lua, pure rules in conquest_core.lua,
-- tests: server/tests/conquest_test.lua; overview: server/README.md "Conquest Tokens, the Conquest vendor and bad-luck
-- protection"). Plain table, loaded with  ChaosConquestConfig = dofile("data/scripts/chaos/conquest_config.lua")
-- Lua 5.1 / LuaJIT and Lua 5.3. Edit here, then /reload scripts (or restart).
--
-- The rule behind it: everything a player NEEDS has a deterministic path; luck only decides the maximum. Tokens come
-- from every boss kill and every clear; the vendor sells any unique or set piece the character has seen (or that sits
-- in its level band) at a fixed price, with the normal rolls of a drop. Bad-luck protection raises the drop chance of
-- boss uniques, set pieces, raid uniques and monster uniques after every miss and resets on a drop.

local C = {}

C.enabled = true
C.opcode = 167 -- ChaosOpcodes.conquest (chaos_constants.lua); client game_conquest
C.requestMs = 400 -- one window request per player per 400 ms (Chaos.limited, before any database read)
C.staffGroup = 4 -- /conquest needs this group or higher (giving tokens: an administrator, Chaos.staffCommand economy)
C.name = "Conquest Tokens"

-- player storages 7102640 - 7102689 (server/README.md "Storage keys", Chaos.storage.conquest):
--   +0 the day (YYYYMMDD) the daily counters below belong to; +1 .. +29 tokens earned today per source slot;
--   +30 .. +39 bad-luck protection: misses in a row per pity group slot; +40 .. +49 free
C.storage = 7102640
C.daySlot = 0
C.pitySlot = 30

-- database (server/sql/chaos_conquest.sql; conquest.lua also creates the tables): the balance per character, every
-- grant and purchase (the log), the uniques a character has seen drop (the vendor shows them)
C.tables = {balance = "chaos_conquest", log = "chaos_conquest_log", seen = "chaos_conquest_seen"}
C.logKeepDays = 60 -- log rows older than this are deleted at startup

-- ------------------------------------------------------------------ sources (ChaosConquest.grant(player, key, amount))
-- slot: the daily counter (storage + slot, 1..29; never reuse a slot for another source). cap: tokens per character
-- and day from this source (the day turns at midnight, server time). amount: the default when the caller passes none;
-- a clear scales with its content: base + perTier x rift tier / perDifficulty x dungeon step / perDepth x Descent
-- room / perShare x invasion share (0..1), + clear on a full Descent clear, at most max.
C.sources = {
	boss_world = {slot = 1, amount = 12, cap = 72, label = "world boss"},
	boss_island = {slot = 2, amount = 10, cap = 60, label = "island boss"},
	boss_raid = {slot = 3, amount = 4, cap = 40, label = "raid boss"},
	boss_lair = {slot = 4, amount = 3, cap = 45, label = "lair boss"},
	boss_invasion = {slot = 5, amount = 8, cap = 48, label = "invasion boss"},
	boss_omen = {slot = 6, amount = 15, cap = 90, label = "Omen guardian"},
	boss_ascended = {slot = 7, amount = 25, cap = 150, label = "Ascended Omen"},
	boss_dungeon = {slot = 8, amount = 5, cap = 60, label = "dungeon boss"},
	boss_tower = {slot = 9, amount = 4, cap = 48, label = "tower boss"},
	boss_trial = {slot = 10, amount = 6, cap = 36, label = "trial boss"},
	boss_descent = {slot = 11, amount = 8, cap = 64, label = "Descent boss"},
	boss_guild = {slot = 12, amount = 12, cap = 48, label = "guild boss"},
	boss_sepulchre = {slot = 13, amount = 15, cap = 120, label = "Sepulchre boss"},
	boss_other = {slot = 14, amount = 2, cap = 30, label = "boss"},
	rift_clear = {slot = 15, base = 4, perTier = 0.5, max = 12, cap = 300, label = "sealed rift"},
	dungeon_clear = {slot = 16, base = 5, perDifficulty = 2, max = 15, cap = 90, label = "dungeon clear"},
	descent_clear = {slot = 17, base = 4, perDepth = 0.5, clear = 6, max = 18, cap = 90, label = "Ember Descent"},
	invasion = {slot = 18, base = 5, perShare = 10, max = 15, cap = 60, label = "invasion"},
	-- pocket bosses (H2's system calls ChaosConquest.grant(player, "pocket_boss", n))
	pocket_boss = {slot = 19, amount = 4, cap = 60, label = "pocket boss"},
	-- Next Goals (H5's goals system): ChaosConquest.reward(player, "goals", {tier = band}); band 1 = the first level band
	-- (3 + 2 = 5 tokens), each band above +2, at most 15
	goals = {slot = 21, base = 3, perTier = 2, max = 15, cap = 60, label = "goal"},
	-- salvaged uniques (salvage.lua): a share of the vendor price, see `salvage`
	salvage = {slot = 20, amount = 25, cap = 400, label = "salvage"}
}

-- boss kills: every player in the damage map (summons for their master), the last hit and the most damage, and their
-- party members within partyRange sqm on the same floor (as the boss points). The source is "boss_" .. the category of
-- the Boss Spawns window (bossspawns_config.lua, the monster's type name); a monster that is no listed boss but a boss
-- by its type (MonsterType:isBoss) gives boss_other. byName: monsters with their own source and amount.
C.boss = {
	partyRange = 30,
	categories = {world = "boss_world", island = "boss_island", raid = "boss_raid", lair = "boss_lair",
		invasion = "boss_invasion", omen = "boss_omen", ascended = "boss_ascended", dungeon = "boss_dungeon",
		tower = "boss_tower", trial = "boss_trial", descent = "boss_descent", guild = "boss_guild",
		sepulchre = "boss_sepulchre", rare = "boss_other"},
	fallback = "boss_other",
	byName = {
		["varkhul the ashen sovereign"] = {source = "boss_sepulchre", amount = 35},
		["ysgrath the cinderheart"] = {source = "boss_ascended", amount = 50},
		["sangrith the bloodmoon herald"] = {source = "boss_omen", amount = 15},
		["morvane the hollow crown"] = {source = "boss_omen", amount = 15},
		["thalcyra the stormbound seer"] = {source = "boss_omen", amount = 15},
		["ascended sangrith"] = {source = "boss_ascended", amount = 25},
		["ascended morvane"] = {source = "boss_ascended", amount = 25},
		["ascended thalcyra"] = {source = "boss_ascended", amount = 25}
	}
}

-- ------------------------------------------------------------------ bad-luck protection (pity)
-- Per character and group: every roll that misses raises the next chance to base x (1 + step x misses), at most base x
-- cap; a drop of the group sets the misses back to 0. Groups (where the roll is):
--   monster   monster uniques of magic / rare / legendary monsters (loot.lua, the corpse owner)
--   boss      boss uniques (loot.lua boss corpses, the Ascended spoils' unique rolls)
--   set       set pieces: their unique entries (loot.lua) and every chase roll (rift, raid, Descent, dungeon)
--   raid      the Ashen Sepulchre's raid uniques (raid.lua, per boss loot)
C.pity = {
	monster = {slot = 1, step = 0.01, cap = 3, label = "Monster uniques"},
	boss = {slot = 2, step = 0.10, cap = 4, label = "Boss uniques"},
	set = {slot = 3, step = 0.05, cap = 4, label = "Set pieces"},
	raid = {slot = 4, step = 0.25, cap = 5, label = "Raid uniques"}
}
C.pityOrder = {"monster", "boss", "set", "raid"}

-- ------------------------------------------------------------------ the vendor
-- Every unique of ChaosUniqueItems, every set piece (data/lib/chaos_item_sets.lua) and every raid unique
-- (raid_config.lua uniques). Price = base + perLevel x the item's required level, rounded to `round`; prices = fixed
-- prices by item id. An offer can be bought when the character has seen it drop for itself (chaos_conquest_seen), has
-- killed a monster that drops it (its bestiary), or the item's level is at most its level + levelBand; `always` are
-- always on sale (the Monk's fist weapon path). The item is made like a drop (ChaosMakeUnique): the same stats, the same
-- rolls. Buying needs a protection zone (or the vendor in sight).
C.vendor = {
	levelBand = 50,
	round = 10,
	needProtectionZone = true,
	groups = {
		monster = {base = 600, perLevel = 1.5, label = "Monster unique"},
		boss = {base = 1000, perLevel = 3, label = "Boss unique"},
		set = {base = 900, perLevel = 1.2, label = "Set piece"},
		raid = {base = 2400, perLevel = 0, label = "Raid unique"},
		ascended = {base = 4200, perLevel = 0, label = "Ascended unique"}
	},
	groupOrder = {"monster", "boss", "set", "raid", "ascended"},
	prices = {
		[2498] = 3600, -- Crown of the Last Sovereign (the raid's final boss only)
		[2123] = 5400 -- Cinderheart Signet (the Cinderheart only)
	},
	always = {36659}, -- Grasp of the Pyre Saint: the Monk's top fist weapon has a path for every Monk
	defaultLevel = 100 -- an item whose level is nowhere written
}

-- ------------------------------------------------------------------ the Cinderheart chain
-- omenKey: an Omen Key of the kind you choose (rift_config.lua omen.kinds); attune: an Omen Key you carry takes the
-- kind you choose. shard: one Ascended Shard of the kind you choose. convert: `count` shards (or relics) of one kind
-- become one of another kind, plus `fee` tokens.
C.cinder = {
	omenKey = 150,
	attune = 40,
	shard = 300,
	convert = {shards = 2, relics = 2, fee = 0}
}

-- ------------------------------------------------------------------ refinement (a deterministic rarity step)
-- A worn item with a rarity (not a unique, not ruined) goes one rarity up, keeps every modifier and gains one random
-- modifier that fits the new rarity (none when it is full). Price = base + perRarity x the new rarity; never above
-- maxRarity (a stored id of data/lib/chaos_rarity.lua; Divine stays a matter of luck). The price counts the new place in the
-- order Common 1 .. Divine 6; it was base 60 + 40 x the new id of 15 (140 .. 540), up to Celestial
C.refine = {base = 60, perRarity = 60, maxRarity = 5}

-- ------------------------------------------------------------------ salvage of uniques (salvage.lua)
-- a unique (or set piece) on the bench gives share x its vendor price in tokens, at least min (on top of the set
-- piece's rune shards); far below the price, so buying to salvage never pays
C.salvage = {share = 0.10, min = 25}

-- the vendor NPC (data/npc/Iselde Varrow.xml, installed by server/tools/install_conquest.py): next to the main temple
C.npc = {
	name = "Iselde Varrow", range = 4, towns = {2, 1}, delayMs = 3500, -- the main city first (README "Main city")
	offsets = {{-6, -1}, {6, -1}, {-6, 1}, {6, 1}, {-2, -6}, {2, 6}, {-7, -2}, {7, -2}, {-7, 2}, {7, 2}}
}

return C
