-- chaos_gear_sets.lua: the seven equipment sets of client pair 28 on the server side, behind one switch. Loaded with
--     ChaosGearSets = dofile("data/lib/chaos_gear_sets.lua")
-- (data/scripts/chaos/gear_sets.lua, transmog_config.lua; server/tools/install_gear_sets.py reads the switch line).
-- Plain Lua, no engine calls at load (server/tests/gear_sets_test.lua). Lua 5.1 / LuaJIT and 5.3.
-- Overview: server/README.md "Equipment sets (pair 28)".
--
-- Pair switch (M.PAIR28, OFF as shipped: pair 28 is not published yet; the owner approves it first). A client on pair
-- 27 or older has no items 33995..34442 and draws nothing for them. Off: the items exist once installed
-- (install_gear_sets.py, install step `gearsets`) but no monster drops them and the transmog catalogue skips their ids.
-- On: data/scripts/chaos/gear_sets.lua adds M.lootRows() to the monster types at startup and the pieces become
-- ordinary transmog looks.
--
-- What it holds (art: client/tools/sprites/gen_gear_sets_art.py, the owner's own sheets of 2026-10-15): 448 pieces,
-- 64 per set (server ids 36995..37442, data/lib/chaos_gear_sets_items.lua, generated with their levels and stats).
-- Each set covers every class (heavy, medium and cloth armour, the weapons of every line) over a level band:
--   Blightfang 8-150 (venom), Wyrmscale 40-220 (green dragon), Cinderwrought 120-450 (fire), Bloodmoon 300-650
--   (blood), Rimewraith 450-1000 (frost and spectral), Azure Vigil 800-1350 (holy), Gildcrown 1200-2000 (gold).
--
-- How players get them: loot of the monsters of the set's theme (sources below), every piece whose level is near the
-- monster's (window), a small total chance per kill shared by those pieces; the themed bosses more. The chaos loot
-- layer then rolls rarity, item level and modifiers as for any gear drop, and smart loot favours the killer's class
-- (the equip rules of movements.xml name it). The base stats are fixed by level: the roll decides only how far above
-- them a copy goes. No talkaction, no shop.

local M = {}

M.PAIR28 = false

local ok, items = pcall(dofile, "data/lib/chaos_gear_sets_items.lua")
M.items = ok and items or {first = 36995, last = 37442, sets = {}, pieces = {}}

M.config = {
	-- total chance per kill (per 100000, the loot unit) that one of the eligible pieces drops, shared by them
	monsterChance = 600,
	bossChance = 15000,
	-- no single entry below this (a monster with many eligible pieces)
	minChance = 10,
	-- a piece is eligible when its level is at most the monster's level + above and at least its level - below
	window = {below = 300, above = 50}
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
		monsters = {{"Golden Dragon", 1160}, {"Winterstride", 1220}, {"Bloodantler Fiend", 1600},
			{"Mirecoil Wyrm", 1900}},
		bosses = {{"Vaelith the Fallen Seraph", 1700}}
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

-- transmog_config.lua calls this on its table: off, the ids leave the catalogue (an installed piece unlocks nothing)
function M.addTransmog(cfg)
	if not M.PAIR28 then
		cfg.excludeRanges = cfg.excludeRanges or {}
		cfg.excludeRanges[#cfg.excludeRanges + 1] = {M.items.first, M.items.last}
	end
	return cfg
end

return M
