-- Run from the server/ folder: luajit tests/class_loot_test.lua (and lua5.3; CI runs both)
-- Class loot (server/README.md "Gear coverage"): data/lib/chaos_class_loot.lua. The bases are the stock items of the
-- CSV snapshots, the window picks bases by level, the rows are shared per family with a floor and a level boost.

local n = 0
local function eq(a, b, m)
	n = n + 1
	if a ~= b then
		error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2)
	end
end

local L = dofile("data/lib/chaos_class_loot.lua")

-- ---------------------------------------------------------------- the bases are the CSV's
WEAPON_COVERAGE_NO_MAIN = true
local W = dofile("tools/weapon_coverage.lua")
local weapons = {}
for _, r in ipairs(W.csv("data/items/base_weapons.csv")) do
	weapons[tonumber(r.id)] = r
end
local archery = dofile("data/lib/chaos_archery_config.lua")
local gearCfg = dofile("tools/gear_coverage_config.lua")
dofile("data/lib/chaos_fist_weapons.lua")
local W800 = dofile("data/lib/chaos_weapons800.lua")
local isBook = {}
for _, id in ipairs(gearCfg.books) do
	isBook[id] = true
end
local function wields(w, class)
	if w.classes == "*" then
		return true
	end
	for c in w.classes:gmatch("[^|]+") do
		if c == class then
			return true
		end
	end
	return false
end
local MELEE = {sword = true, axe = true, club = true}
-- every melee class wields a one-handed base (all but the Berserker) and a two-handed base (all twelve)
local MELEE1 = {"Warrior", "Juggernaut", "Thief", "Ninja", "Samurai", "Monk", "Shadowfist", "Iron Sage", "Templar",
	"Inquisitor", "Sentinel"}
for _, kind in ipairs(L.KINDS) do
	local list = L.bases[kind]
	eq(#list > 0, true, kind .. " has bases")
	local last, seen = 0, {}
	for _, b in ipairs(list) do
		eq(b[2] >= last, true, kind .. " sorted by level at " .. b[1])
		last = b[2]
		eq(seen[b[1]], nil, kind .. " base " .. b[1] .. " listed once")
		seen[b[1]] = true
		if kind == "quiver" then
			eq(archery.quivers[b[1]] ~= nil, true, "quiver " .. b[1] .. " is an archery quiver")
			eq(archery.quivers[b[1]][1], b[2], "quiver " .. b[1] .. " level")
		elseif kind == "book" then
			eq(isBook[b[1]], true, "book " .. b[1] .. " is a stock spellbook")
		elseif kind == "fist" then
			local it = ChaosFistWeapons.items[b[1]]
			eq(it ~= nil, true, "fist " .. b[1] .. " is a fist weapon")
			eq(it.level, b[2], "fist " .. b[1] .. " level")
			eq(it.unique, nil, "fist " .. b[1] .. " is no unique")
		elseif W800.items[b[1]] then
			-- the weapons above level 800 (data/lib/chaos_weapons800.lua): same family, same level, wielded by the classes of the kind
			local it = W800.items[b[1]]
			eq(it.family, kind, "weapons800 " .. b[1] .. " family")
			eq(it.level, b[2], "weapons800 " .. b[1] .. " level")
			eq(#it.classes > 0, true, "weapons800 " .. b[1] .. " has a class list")
		else
			local w = weapons[b[1]]
			eq(w ~= nil, true, kind .. " " .. b[1] .. " is in base_weapons.csv")
			eq(tonumber(w.level), b[2], kind .. " " .. b[1] .. " level")
			eq(tonumber(w.charges), 0, kind .. " " .. b[1] .. " has no charges")
			if kind == "melee1h" or kind == "melee2h" then
				eq(MELEE[w.kind], true, kind .. " " .. b[1] .. " is a sword, axe or club")
				eq(tonumber(w.hands), kind == "melee1h" and 1 or 2, kind .. " " .. b[1] .. " hands")
				for _, class in ipairs(MELEE1) do
					eq(wields(w, class), true, kind .. " " .. b[1] .. " is wielded by the " .. class)
				end
				-- the Berserker fights two-handed (its class rule): the one-handed bases are not its list's concern
				if kind == "melee2h" then
					eq(wields(w, "Berserker"), true, kind .. " " .. b[1] .. " is wielded by the Berserker")
				end
			elseif kind == "wand" or kind == "rod" then
				eq(w.kind, "wand", kind .. " " .. b[1] .. " kind")
				-- the sets' split: a wand is wielded by the Elementalist, a rod is the Illusionist's
				eq(wields(w, "Elementalist"), kind == "wand" or w.classes == "*", kind .. " " .. b[1] .. " and the Elementalist")
				eq(wields(w, "Illusionist") or kind == "wand", true, kind .. " " .. b[1] .. " and the Illusionist")
			else
				eq(w.kind, kind, kind .. " " .. b[1] .. " kind")
			end
		end
	end
end
-- the Ranger starts with a bow and a crossbow at level 0, the casters with wands at level 1
-- every weapon above level 800 is a base of its family, and only those families carry them
local inBases = {}
for _, kind in ipairs(L.KINDS) do
	for _, b in ipairs(L.bases[kind]) do
		inBases[b[1]] = kind
	end
end
for _, id in ipairs(W800.ids) do
	eq(inBases[id], W800.items[id].family, "weapons800 " .. id .. " is in its class loot family")
end
eq(L.bases.bow[1][2], 0, "a bow from level 0")
eq(L.bases.crossbow[1][2], 0, "a crossbow from level 0")
eq(L.bases.wand[1][2] <= 1, true, "a wand from level 1")
eq(L.bases.rod[1][2] <= 1, true, "a rod from level 1")
eq(L.bases.fist[1][2], 1, "a fist weapon from level 1")
eq(L.bases.book[1][2], 0, "a spellbook from level 0")

-- ---------------------------------------------------------------- eligible
local function ids(list)
	local out = {}
	for _, b in ipairs(list) do
		out[#out + 1] = b[1]
	end
	return table.concat(out, ",")
end
-- a rat (hunting level 8) drops the first bow and the first wands, nothing above level 28
eq(ids(L.eligible("bow", 8)), "2456", "bow at level 8")
eq(ids(L.eligible("wand", 8)), "23719,23721,2190,2191,2188,8921,2189", "wands at level 8")
eq(ids(L.eligible("rod", 8)), "23719,23721,2182,2186,2185,8911,2181", "rods at level 8")
-- the window is 150 below: a bow of level 0 is gone at 200
for _, b in ipairs(L.eligible("bow", 200)) do
	eq(b[2] >= 50 and b[2] <= 220, true, "bow window at 200: " .. b[1])
end
-- above every base the highest three, but only those within fallbackSpan of the highest (2026-10-24: a hunt of level
-- 2000 no longer drops the level 400 bows a hunt of 800 does; the sets' level gear carries the levels above 1000). Since the
-- weapons above level 800 (2026-10-28) every window up to 2150 holds a bow; the fallback only works above the last one
eq(ids(L.eligible("bow", 800)), "48412", "the bows at 800: the level 820 bow")
eq(#L.eligible("bow", 5000), 1, "the best bow only at 5000")
eq(L.eligible("bow", 5000)[1][1], 48420, "the highest bow")
eq(ids(L.eligible("bow", 1100)), "48414,29874,48415", "the bows at 1100")
eq(L.config.fallbackSpan, 200, "the span of the fallback")
-- above the last base only the three highest bases within fallbackSpan of the top are left
for _, kind in ipairs(L.KINDS) do
	local list = L.bases[kind]
	local top = list[#list][2]
	local want = {}
	for i = math.max(1, #list - 2), #list do
		if list[i][2] >= top - L.config.fallbackSpan then
			want[#want + 1] = list[i][1]
		end
	end
	for _, level in ipairs({top + 250, top + 1000, top + 4000}) do -- beyond window.above and the span
		eq(ids(L.eligible(kind, level)), table.concat(want, ","), kind .. " at " .. level .. ": the best base(s) only")
	end
end
eq(#L.eligible("nothing", 100), 0, "unknown kind")

-- ---------------------------------------------------------------- rows
local pool = {
	hunt = {{name = "Rat", level = 4}, {name = "Dragon", level = 350}, {name = "Titan", level = 650}},
	bosses = {{name = "Boss", level = 500}}
}
local rows = L.lootRows(pool)
eq(#rows > 0, true, "rows")
local per = {}
for _, r in ipairs(rows) do
	eq(r[3] >= L.config.minChance, true, "row floor " .. r[2])
	per[r[1]] = (per[r[1]] or 0) + r[3]
end
local cfg = L.config
-- the chance of a family follows its anchors: linear between them, flat outside
for _, kind in ipairs(L.KINDS) do
	local pts = cfg.chance[kind]
	eq(#pts >= 1, true, kind .. " has anchors")
	for i = 2, #pts do
		eq(pts[i][1] > pts[i - 1][1], true, kind .. " anchors rise")
	end
	eq(L.chanceAt(kind, pts[1][1] - 50), pts[1][2], kind .. " flat below the first anchor")
	eq(L.chanceAt(kind, pts[#pts][1] + 500), pts[#pts][2], kind .. " flat above the last anchor")
	if #pts >= 2 then
		local mid = (pts[1][1] + pts[2][1]) / 2
		eq(math.abs(L.chanceAt(kind, mid) - (pts[1][2] + pts[2][2]) / 2) < 1e-6, true, kind .. " linear between anchors")
	end
	eq(cfg.bossChance[kind] ~= nil, true, kind .. " has a boss chance")
end
eq(L.chanceAt("nothing", 100), 0, "unknown family: no chance")
-- the weapon families get a chance in the fitted bands (--derive); quivers and spellbooks grow with the level
for _, kind in ipairs({"melee1h", "melee2h", "fist", "bow", "crossbow", "wand", "rod"}) do
	for _, level in ipairs({100, 300, 500}) do
		eq(L.chanceAt(kind, level) > 0, true, kind .. " drops at " .. level)
	end
end
eq(L.chanceAt("book", 800) > L.chanceAt("book", 8), true, "the spellbook chance grows with the level")
eq(per["Dragon"] > 0 and per["Rat"] > 0, true, "every monster carries rows")
-- a boss gets the boss totals, no curve
local bossTotal = 0
for _, kind in ipairs(L.KINDS) do
	bossTotal = bossTotal + cfg.bossChance[kind]
end
eq(per["Boss"] >= bossTotal * 0.95 and per["Boss"] <= bossTotal * 1.05, true, "a boss carries " .. per["Boss"])
-- every kind of a hunt level 300 monster has rows: melee both hands, the Monk's fists, bows, crossbows, wands, rods
local seenKind = {}
local kindOf = {}
for _, kind in ipairs(L.KINDS) do
	for _, b in ipairs(L.bases[kind]) do
		kindOf[b[1]] = kindOf[b[1]] or {}
		kindOf[b[1]][kind] = true
	end
end
for _, r in ipairs(L.lootRows({hunt = {{name = "Dragon", level = 300}}})) do
	for kind in pairs(kindOf[r[2]] or {}) do
		seenKind[kind] = true
	end
end
for _, kind in ipairs(L.KINDS) do
	eq(seenKind[kind], true, "a level 300 monster drops the family " .. kind)
end
-- levelOf replaces the pool level
local hi = L.lootRows({hunt = {{name = "Rat", level = 4}}}, function() return 500 end)
local lowest = 1e9
for _, r in ipairs(hi) do
	for _, kind in ipairs(L.KINDS) do
		for _, b in ipairs(L.bases[kind]) do
			if b[1] == r[2] then
				lowest = math.min(lowest, b[2])
			end
		end
	end
end
eq(lowest >= 500 - 150, true, "a hunting level of 500 drops no base below 350")
eq(#L.lootRows(nil), 0, "no pool, no rows")

-- ---------------------------------------------------------------- scaled hunts (rollScaled, loot.lua step 1e)
local sc = L.config.scaled
local always = function(a, b) return a end
local never = function(a, b) return b end
eq(#L.rollScaled(657, "Monk", "normal", 1, always), 0, "a base hunt rolls nothing here (its type carries the rows)")
eq(#L.rollScaled(sc.minLevel, "Monk", "normal", 1, always), 3, "a Monk rolls fist, one-handed and two-handed melee")
eq(#L.rollScaled(1000, "Berserker", "normal", 1, always), 1, "a Berserker rolls two-handed melee only")
eq(#L.rollScaled(1000, "Ranger", "normal", 1, always), 2, "a Ranger rolls a bow and a crossbow")
eq(#L.rollScaled(1000, "Beastmaster", "normal", 1, always), 1, "a Beastmaster rolls a bow")
eq(#L.rollScaled(1000, "Elementalist", "normal", 1, always), 1, "an Elementalist rolls a wand")
eq(#L.rollScaled(1000, "Illusionist", "normal", 1, always), 1, "an Illusionist rolls a rod")
eq(#L.rollScaled(1000, "Nobody", "normal", 1, always), 0, "an unknown class rolls nothing")
eq(#L.rollScaled(1000, "Monk", "normal", 1, never), 0, "a miss rolls nothing")
for _, id in ipairs(L.rollScaled(2000, "Monk", "boss", 9, always)) do
	local found = false
	for _, kind in ipairs({"melee1h", "melee2h", "fist"}) do
		for _, b in ipairs(L.bases[kind]) do
			found = found or b[1] == id
		end
	end
	eq(found, true, "a rolled base " .. id .. " is a Monk base")
end
-- the scale is capped at maxScale: a draw just above 3x the chance misses
local c = L.scaledChanceAt("fist", 1000)
local edge = function(a, b) return math.floor(c * sc.maxScale) + 1 end
eq(#L.rollScaled(1000, "Berserker", "normal", 99, edge), 0, "no family hits above the cap")
-- every class has its families (the audit's loadouts, tools/gear_coverage_config.lua)
for _, g in ipairs(gearCfg.loadouts) do
	for _, name in ipairs(g.classes) do
		local want = {}
		for _, key in ipairs(g.keys) do
			want[#want + 1] = key
		end
		table.sort(want)
		local have = {}
		for _, key in ipairs(L.classKinds[name] or {}) do
			have[#have + 1] = key
		end
		table.sort(have)
		eq(table.concat(have, ","), table.concat(want, ","), name .. " wields the audit's loadouts")
	end
end

print("class_loot_test: " .. n .. " checks ok")
