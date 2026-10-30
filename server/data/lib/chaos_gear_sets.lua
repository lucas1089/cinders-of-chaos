-- chaos_gear_sets.lua: the seven equipment sets of client pair 28 on the server side, behind one switch. Loaded with
--     ChaosGearSets = dofile("data/lib/chaos_gear_sets.lua")
-- (data/scripts/chaos/gear_sets.lua, transmog_config.lua; server/tools/install_gear_sets.py reads the switch line).
-- Plain Lua, no engine calls at load (server/tests/gear_sets_test.lua). Lua 5.1 / LuaJIT and 5.3.
-- Overview: server/README.md "Equipment sets (pair 28)".
--
-- Pair switch (M.PAIR28, ON since 2026-10-15: pair 28 is live, windows-assets b37b983c). A client on pair
-- 27 or older has no items 33995..34442 and draws nothing for them. Off: the items exist once installed
-- (install_gear_sets.py, install step `gearsets`) but no monster drops them and the transmog catalogue skips their ids.
-- On: data/scripts/chaos/gear_sets.lua adds M.lootRows() to the monster types at startup and the pieces become
-- ordinary transmog looks.
--
-- What it holds (art: client/tools/sprites/gen_gear_sets_art.py, the owner's own sheets of 2026-10-15): 448 pieces,
-- 64 per set (server ids 36995..37442, data/lib/chaos_gear_sets_items.lua, generated with their levels and stats).
-- Each set covers every class (heavy, medium and cloth armour, the weapons of every line) over a level band:
--   Blightfang 8-150 (venom), Wyrmscale 40-220 (green dragon), Cinderwrought 120-450 (fire), Bloodmoon 300-650
--   (blood), Rimewraith 450-1000 (frost and spectral), Azure Vigil 800-1350 (holy), Gildcrown 1250-2000 (gold).
--
-- Three later-tier sets (2026-10-24, server/README.md "Gear beyond level 1000"): Wintermourn 1000-1350, Lumenhallow
-- 1300-1750 and Sunderthrone 1700-2050 are copies of the pieces of Rimewraith, Azure Vigil and Gildcrown (same client
-- ids, so the same looks; server ids 52000..52191, items.tier2First / tier2Last) with a name, a level band and set
-- bonuses of their own. The stock gear stops at level 1000 and the art sets at 2000, and a monster type has one loot
-- table whatever level it is spawned at, so the hunts of 1000 to 2000 dropped the same bases as a hunt of 800.
--
-- How players get them: loot of the monsters of the set's theme (sources below), every piece whose level is near the
-- monster's (window), a small total chance per kill shared by those pieces; the themed bosses more. On top, level
-- gear (M.rollLevelGear, called by the chaos loot layer, loot.lua step 1d): a kill of a monster hunted at level
-- `open.minLevel` or more, whatever its type, may drop one piece of ANY set near the level it is hunted at (a spawned
-- monster's own level, else its hunting level), so a hunt of level 2000 drops other bases than a hunt of 800. The chaos loot
-- layer then rolls rarity, item level and modifiers as for any gear drop, and smart loot favours the killer's class
-- (the equip rules of movements.xml name it). The base stats are fixed by level: the roll decides only how far above
-- them a copy goes. No talkaction, no shop. Set bonuses at 2, 4 and 6 pieces (M.bonuses) through the item set system.

local M = {}

M.PAIR28 = true

-- Pair switch of the five relic sets (2026-10-30, O338, server/README.md "Relic sets (pair 58)"): OFF as shipped. They are 65 pieces
-- of client pair 58 (ids 48446..48510, data/lib/chaos_relic_sets_items.lua, install_relic_sets.py): Venomcoil 640, Hoarglass 860,
-- Kilnforged 1400, Halogild 1700, Deepdirge 2050, 13 pieces each (helmet, chest, legs, boots, shield, spellbook, sword, axe, hammer,
-- bow, wand or rod, ring, amulet). A client on pair 57 or older has no looks for them. Off: the items exist once installed (the
-- `relicsets` step waits for config.lua chaosClientPair >= 58) but no monster drops them, the transmog catalogue skips their ids and
-- the item sets leave the five sets out. On: gear_sets.lua adds their loot rows, the sets and their bonuses are live and the pieces are
-- ordinary transmog looks. The audits (tools/weapon_coverage.lua, tools/gear_coverage.lua) count them either way, as they count the
-- weapons above level 800. They are NOT part of the level gear pool (levelPieces): more pieces there would thin every set weapon's chance.
M.PAIR58 = false

local ok, items = pcall(dofile, "data/lib/chaos_gear_sets_items.lua")
M.items = ok and items or {first = 36995, last = 37442, sets = {}, pieces = {}}
local okRelic, relic = pcall(dofile, "data/lib/chaos_relic_sets_items.lua")
if okRelic and type(relic) == "table" then
	M.items.relicFirst, M.items.relicLast = relic.first, relic.last
	for key, set in pairs(relic.sets or {}) do
		M.items.sets[key] = set
	end
	for _, p in ipairs(relic.pieces or {}) do
		M.items.pieces[#M.items.pieces + 1] = p
	end
end

M.config = {
	-- total chance per kill (per 100000, the loot unit) that one of the eligible pieces drops, shared by them
	monsterChance = 600,
	bossChance = 15000,
	-- no single entry below this (a monster with many eligible pieces)
	minChance = 10,
	-- a piece is eligible when its level is at most the monster's level + above and at least its level - below
	window = {below = 300, above = 50},
	-- level gear (M.rollLevelGear): a kill at a hunting level of `minLevel` or more, of any monster type, rolls one
	-- piece of any set whose level is in [level - below, level + above]: the chance per kill (per 100000, by monster
	-- tier; a boss `boss`), a piece that the killer's class wears weighs `classWeight` times as much
	open = {minLevel = 700, below = 200, above = 50, classWeight = 3, maxScale = 3,
		chance = {normal = 1600, magic = 2400, rare = 3200, legendary = 4800, boss = 15000}}
}

-- set key -> the monsters of its theme as {name, hunting level} (the installed names; levels of
-- data/scripts/chaos/bounty_pool.lua or the monster file's <level>), and its bosses the same way
M.sources = {
	blightfang = {
		monsters = {{"Poison Spider", 8}, {"Swamp Troll", 8}, {"Cobra", 9}, {"Scorpion", 11}, {"Wailing Widow", 34},
			{"Rot Elemental", 44}, {"Bog Raider", 45}, {"Giant Spider", 48}, {"Plaguesmith", 138}, {"Cobra Assassin", 146},
			{"Blightwalker", 148}, {"Venom Spider", 177}},
		bosses = {{"Fennra", 36}, {"Snake God Essence", 88}}
	},
	wyrmscale = {
		monsters = {{"Wyvern", 36}, {"Dragon Lord Hatchling", 41}, {"Dragon", 42}, {"Wyrm", 63}, {"Dragon Lord", 73},
			{"Wyrmblood Warmaster", 78}, {"Elder Wyrm", 80}, {"Wyrmblood Spellweaver", 89}, {"Wyrmblood Elite", 104},
			{"Wyrmblood Abomination", 104}, {"Black Dragon", 163}, {"Mega Dragon", 167}, {"Netheria Dragon", 175},
			{"Wardragon", 180}},
		bosses = {{"Shimmerscale", 42}}
	},
	cinderwrought = {
		monsters = {{"Hellhound", 132}, {"Lava Golem", 150}, {"Burning Gladiator", 167}, {"Hellflayer", 233},
			{"Burning Book", 262}, {"Cinderclaw", 308}, {"Infernal Demon", 387}, {"Hellhunter Pyrarch", 436},
			{"Blazefang", 474}},
		bosses = {{"Pyrevorn", 124}, {"Morgashal", 240}}
	},
	bloodmoon = {
		monsters = {{"Elder Bloodjaw", 326}, {"Bloodfang Reaver", 409}, {"Bloodthirst Bulgeye", 416},
			{"Bloodspark Adept", 474}, {"Bloodshade Reaper", 501}},
		bosses = {}
	},
	rimewraith = {
		monsters = {{"Distorted Phantom", 406}, {"Capricious Phantom", 415}, {"Frost Hydra", 436},
			{"Hazardous Phantom", 449}, {"Glacial Hellcharger", 612}, {"Frost Maiden", 820}, {"Ice Lich", 1000}},
		bosses = {}
	},
	azurevigil = {
		monsters = {{"Dawn Strayer", 980}, {"Spirit of Purity", 1040}, {"Celestial Wyrm", 1080}},
		bosses = {{"Ossivane the Gravecage", 1100}}
	},
	gildcrown = {
		monsters = {{"Winterstride", 1220}, {"Bloodantler Fiend", 1600},
			{"Mirecoil Wyrm", 1900}, {"Pyrewing Tyrant", 2000}, {"Pyre Stork", 2000}},
		bosses = {{"Vaelith the Fallen Seraph", 1700}, {"Azhkarrath the Chained Wyrm", 2100}}
	},
	-- the relic sets (pair 58): monsters of the theme inside the window [level - 50, level + 300] of the set's one level
	venomcoil = {
		monsters = {{"Grove Keeper", 700}, {"Elite Spider", 730}, {"Gallows Oak", 750}, {"Webbound Crawler", 770},
			{"Blight Hound", 790}, {"Rootbound Pilgrim", 830}, {"Acid Hydra", 930}, {"Blight Bloom", 930}},
		bosses = {{"Vharzul the Verdant Eye", 700}}
	},
	hoarglass = {
		monsters = {{"Frost Maiden", 820}, {"Tundra Troll", 830}, {"Azure Dragon", 880}, {"Ice Lich", 1000}, {"Rimecairn", 1020},
			{"Quicksilver Wraith", 1040}},
		bosses = {{"Ossivane the Gravecage", 1100}}
	},
	kilnforged = {
		monsters = {{"Cinderskull Reaver", 1500}, {"Ashveil Hierarch", 1500}, {"Redmane Anvilbreaker", 1550},
			{"Cinderhorn Juggernaut", 1700}},
		bosses = {{"Forgewarden Kharzun", 1400}}
	},
	halogild = {
		monsters = {{"Oathbroken Colossus", 1700}, {"Siege Behemoth", 1700}, {"Ironmask Warbreaker", 1800},
			{"Gravecrown Oathbreaker", 1850}},
		bosses = {{"Vaelith the Fallen Seraph", 1700}}
	},
	deepdirge = {
		monsters = {{"Pyre Stork", 2000}, {"Pyrewing Tyrant", 2000}},
		bosses = {{"Azhkarrath the Chained Wyrm", 2100}}
	}
}

-- id -> piece
M.byId = {}
for _, p in ipairs(M.items.pieces or {}) do
	M.byId[p.id] = p
end

function M.piece(id)
	return M.byId[tonumber(id) or 0]
end

-- the pieces of a set a monster of `level` may drop (in id order); none when no piece is near enough
function M.eligible(setKey, level, cfg)
	local w = (cfg or M.config).window
	local out = {}
	for _, p in ipairs(M.items.pieces or {}) do
		if p.set == setKey and p.level <= level + w.above and p.level >= level - w.below then
			out[#out + 1] = p
		end
	end
	return out
end

-- the pieces a kill at hunting level `level` may drop as level gear (all sets), in id order
function M.levelPieces(level, cfg)
	local o = (cfg or M.config).open
	local out = {}
	level = tonumber(level) or 0
	if not o or level < o.minLevel then
		return out
	end
	-- above the highest piece the window stays at the top: a monster of 2400 drops what a monster of 2050 does
	local top = 0
	for _, p in ipairs(M.items.pieces or {}) do
		if not p.relic then
			top = math.max(top, p.level)
		end
	end
	local from = math.min(level, top) - o.below
	for _, p in ipairs(M.items.pieces or {}) do
		if not p.relic and p.level <= level + o.above and p.level >= from then
			out[#out + 1] = p
		end
	end
	return out
end

-- chance per 100000 that a kill of this monster tier drops a piece of level gear (before the scale of the caller)
function M.levelChance(tier, cfg)
	local o = (cfg or M.config).open
	return o and (o.chance[tier or "normal"] or o.chance.normal) or 0
end

local function wears(p, class)
	if #p.classes == 0 then
		return true
	end
	for _, c in ipairs(p.classes) do
		if c == class then
			return true
		end
	end
	return false
end

-- one kill: the piece of level gear it drops or nil. scale multiplies the chance (rate, item find, pack factor; at most
-- open.maxScale), rnd(a, b) -> integer in [a, b], className = the killer's class (a piece that class wears weighs
-- open.classWeight times as much)
function M.rollLevelGear(level, tier, scale, rnd, className, cfg)
	cfg = cfg or M.config
	if not M.PAIR28 then
		return nil
	end
	local list = M.levelPieces(level, cfg)
	if #list == 0 then
		return nil
	end
	scale = math.min(cfg.open.maxScale, math.max(0, tonumber(scale) or 1))
	if rnd(1, 100000) > M.levelChance(tier, cfg) * scale then
		return nil
	end
	local weights, total = {}, 0
	for i, p in ipairs(list) do
		local w = (className and wears(p, className)) and cfg.open.classWeight or 1
		weights[i] = w
		total = total + w
	end
	local pick = rnd(1, total)
	for i, p in ipairs(list) do
		pick = pick - weights[i]
		if pick <= 0 then
			return p
		end
	end
	return list[#list]
end

-- what the audits (tools/weapon_coverage.lua, tools/gear_coverage.lua) count as the level-gear source of a piece: the
-- lowest hunting level it drops at and the chance per kill of a normal monster there, shared by the pieces of the window
function M.levelDrop(p, cfg)
	cfg = cfg or M.config
	local o = cfg.open
	if not o or not M.PAIR28 or p.relic then
		return nil
	end
	local access = math.max(o.minLevel, p.level - o.above)
	local n = #M.levelPieces(access, cfg)
	if n == 0 then
		return nil
	end
	return {level = access, chance = math.floor(M.levelChance("normal", cfg) / n)}
end

-- the loot rows {monster, item id, chance per 100000} of every source (the switch is the caller's business)
function M.lootRows(cfg)
	cfg = cfg or M.config
	local rows = {}
	local keys = {}
	for key in pairs(M.sources) do
		keys[#keys + 1] = key
	end
	table.sort(keys)
	for _, key in ipairs(keys) do
		local src = M.sources[key]
		for _, group in ipairs({{src.monsters or {}, cfg.monsterChance}, {src.bosses or {}, cfg.bossChance}}) do
			for _, m in ipairs(group[1]) do
				local list = M.eligible(key, m[2], cfg)
				if #list > 0 then
					local each = math.max(cfg.minChance, math.floor(group[2] / #list))
					for _, p in ipairs(list) do
						rows[#rows + 1] = {m[1], p.id, each}
					end
				end
			end
		end
	end
	return rows
end

-- ---------------------------------------------------------------- set bonuses (only while PAIR28 is on)
-- The sets join the item set system (data/lib/chaos_item_sets.lua S.load reads M.itemSets()) as open sets: any piece
-- of the set counts (by its base id; the same item twice, e.g. in both hands, once; a two-handed weapon or launcher
-- twice), and 2, 4 and 6 pieces worn at their level give the bonuses below. Keys are those of the item sets: modifier
-- keys (added to the equipped items' totals before their caps), res_<element> (less damage of that element taken;
-- against players and their summons only pvpShare % of it) and maxhealthpct (the set condition). Every tier is about
-- one modifier roll of the tier a piece of the set's band rolls (blightfang T2-T3 ... gildcrown T7), below the
-- matching uniques and keystones (server/README.md "Equipment sets (pair 28)").
M.pvpShare = 50
M.cap = 6
M.bonuses = {
	blightfang = { -- poison (8-150)
		{n = 2, stats = {poisonchance = 4, res_earth = 4}},
		{n = 4, stats = {dot = 6}},
		{n = 6, stats = {poisonchance = 4, dot = 4}}
	},
	wyrmscale = { -- dragon hide: fire resistance (40-220)
		{n = 2, stats = {res_fire = 5}},
		{n = 4, stats = {maxhealthpct = 3}},
		{n = 6, stats = {res_fire = 5, monsterreduction = 2}}
	},
	cinderwrought = { -- fire damage (120-450)
		{n = 2, stats = {ignitechance = 6}},
		{n = 4, stats = {elepen = 4}},
		{n = 6, stats = {ignitechance = 4, dot = 10}}
	},
	bloodmoon = { -- life leech (300-650)
		{n = 2, stats = {lifeonhit = 8}},
		{n = 4, stats = {lifeonkill = 40}},
		{n = 6, stats = {lifeonhit = 8, regen = 10}}
	},
	rimewraith = { -- ice and the spectral step (450-1000)
		{n = 2, stats = {chillchance = 8}},
		{n = 4, stats = {dodge = 2}},
		{n = 6, stats = {res_ice = 8, dodge = 1}}
	},
	azurevigil = { -- holy protection (800-1350)
		{n = 2, stats = {res_death = 8}},
		{n = 4, stats = {monsterreduction = 3, healing = 4}},
		{n = 6, stats = {monsterreduction = 2, maxhealthpct = 4}}
	},
	gildcrown = { -- gold and loot (1250-2000)
		{n = 2, stats = {goldfind = 10}},
		{n = 4, stats = {rarityfind = 8, itemfind = 5}},
		{n = 6, stats = {bossdamage = 6}}
	},
	-- the later tiers (2026-10-24): one step above the art set whose looks they wear, in the same line of play
	wintermourn = { -- ice and the spectral step, the second rank (1000-1350)
		{n = 2, stats = {chillchance = 10}},
		{n = 4, stats = {dodge = 3}},
		{n = 6, stats = {res_ice = 10, dodge = 2}}
	},
	lumenhallow = { -- holy protection, the second rank (1300-1750)
		{n = 2, stats = {res_death = 10}},
		{n = 4, stats = {monsterreduction = 4, healing = 5}},
		{n = 6, stats = {monsterreduction = 3, maxhealthpct = 5}}
	},
	sunderthrone = { -- gold and loot, the second rank (1700-2050)
		{n = 2, stats = {goldfind = 14}},
		{n = 4, stats = {rarityfind = 10, itemfind = 7}},
		{n = 6, stats = {bossdamage = 8}}
	},
	-- the relic sets (2026-10-30, pair 58): one level each, about one modifier roll of the tier of that level per step
	venomcoil = { -- poison and the rot (640)
		{n = 2, stats = {poisonchance = 7, res_earth = 6}},
		{n = 4, stats = {dot = 10}},
		{n = 6, stats = {poisonchance = 5, dot = 8}}
	},
	hoarglass = { -- frost and piercing cold (860)
		{n = 2, stats = {chillchance = 9}},
		{n = 4, stats = {res_ice = 8}},
		{n = 6, stats = {elepen = 5, chillchance = 5}}
	},
	kilnforged = { -- the forge fire (1400)
		{n = 2, stats = {ignitechance = 10}},
		{n = 4, stats = {elepen = 7}},
		{n = 6, stats = {ignitechance = 6, dot = 14}}
	},
	halogild = { -- gilded holy light (1700)
		{n = 2, stats = {res_holy = 10}},
		{n = 4, stats = {healing = 7}},
		{n = 6, stats = {maxhealthpct = 5, monsterreduction = 3}}
	},
	deepdirge = { -- the abyss: life from the dead (2050)
		{n = 2, stats = {lifeonhit = 14, res_death = 8}},
		{n = 4, stats = {execute = 5}},
		{n = 6, stats = {bossdamage = 6, lifeonkill = 80}}
	}
}

local SLOT = {helmet = "head", armor = "body", legs = "legs", boots = "feet", amulet = "necklace", ring = "ring",
	shield = "shield", spellbook = "shield"}

-- the sets in the item sets' format (fresh tables on every call: S.load fills them in)
function M.itemSets()
	local out = {}
	local keys = {}
	for key, s in pairs(M.items.sets or {}) do
		if not s.relic or M.PAIR58 then -- the relic sets are live with their own switch
			keys[#keys + 1] = key
		end
	end
	table.sort(keys)
	for _, key in ipairs(keys) do
		local s = M.items.sets[key]
		local set = {key = key, name = s.name, family = "gear", classes = "every class", level = s.band[1],
			open = true, cap = M.cap, pvpShare = M.pvpShare, pieces = {}, bonuses = {}, sources = {}}
		for _, p in ipairs(M.items.pieces or {}) do
			if p.set == key then
				local two = p.fit == "2" or p.kind == "bow" or p.kind == "crossbow"
				set.pieces[#set.pieces + 1] = {id = p.id, name = p.name, slot = SLOT[p.kind] or "weapon",
					hands = two and 2 or 1, level = p.level}
			end
		end
		for _, b in ipairs(M.bonuses[key] or {}) do
			local stats = {}
			for k, v in pairs(b.stats) do
				stats[k] = v
			end
			set.bonuses[#set.bonuses + 1] = {n = b.n, stats = stats}
		end
		out[#out + 1] = set
	end
	return out
end

-- transmog_config.lua calls this on its table: off, the ids leave the catalogue (an installed piece unlocks nothing)
function M.addTransmog(cfg)
	if not M.PAIR28 then
		cfg.excludeRanges = cfg.excludeRanges or {}
		cfg.excludeRanges[#cfg.excludeRanges + 1] = {M.items.first, M.items.last}
	end
	-- the later-tier sets wear the looks of the art sets: their ids are not looks of their own, on or off
	if M.items.tier2First then
		cfg.excludeRanges = cfg.excludeRanges or {}
		cfg.excludeRanges[#cfg.excludeRanges + 1] = {M.items.tier2First, M.items.tier2Last}
	end
	-- the relic sets (pair 58) are looks of their own once their switch is on
	if M.items.relicFirst and not M.PAIR58 then
		cfg.excludeRanges = cfg.excludeRanges or {}
		cfg.excludeRanges[#cfg.excludeRanges + 1] = {M.items.relicFirst, M.items.relicLast}
	end
	return cfg
end

return M
