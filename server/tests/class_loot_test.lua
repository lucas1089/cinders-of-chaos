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
local isBook = {}
for _, id in ipairs(gearCfg.books) do
	isBook[id] = true
end
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
		else
			local w = weapons[b[1]]
			eq(w ~= nil, true, kind .. " " .. b[1] .. " is in base_weapons.csv")
			eq(tonumber(w.level), b[2], kind .. " " .. b[1] .. " level")
			eq(tonumber(w.charges), 0, kind .. " " .. b[1] .. " has no charges")
			eq(w.kind == "wand" and "wand" or w.kind, kind, kind .. " " .. b[1] .. " kind")
		end
	end
end
-- the Ranger starts with a bow and a crossbow at level 0, the casters with wands at level 1
eq(L.bases.bow[1][2], 0, "a bow from level 0")
eq(L.bases.crossbow[1][2], 0, "a crossbow from level 0")
eq(L.bases.wand[1][2] <= 1, true, "a wand from level 1")
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
eq(ids(L.eligible("wand", 8)), "23719,23721,2182,2190,2186,2191,2185,2188,8911,8921,2181,2189", "wands at level 8")
-- the window is 150 below: a bow of level 0 is gone at 200
for _, b in ipairs(L.eligible("bow", 200)) do
	eq(b[2] >= 50 and b[2] <= 220, true, "bow window at 200: " .. b[1])
end
-- above every base the highest three, but only those within fallbackSpan of the highest (2026-10-24: a hunt of level
-- 2000 no longer drops the level 400 bows a hunt of 800 does; the sets' level gear carries the levels above 1000)
eq(#L.eligible("bow", 800), 3, "the three highest bows at 800: 400, 400, 600")
eq(ids(L.eligible("bow", 800)), "27383,28052,27471", "the bows at 800")
eq(#L.eligible("bow", 5000), 1, "the best bow only at 5000")
eq(L.eligible("bow", 5000)[1][1], 29874, "the highest bow")
eq(ids(L.eligible("bow", 1100)), "29874", "the bows at 1100")
eq(L.config.fallbackSpan, 200, "the span of the fallback")
for _, kind in ipairs(L.KINDS) do
	for _, level in ipairs({1200, 2000, 5000}) do
		eq(ids(L.eligible(kind, level)), tostring(L.bases[kind][#L.bases[kind]][1]), kind .. " at " .. level .. ": the best base only")
	end
end
eq(#L.eligible("nothing", 100), 0, "unknown kind")

-- ---------------------------------------------------------------- rows
local pool = {
	hunt = {{name = "Rat", level = 4}, {name = "Dragon", level = 350}},
	bosses = {{name = "Boss", level = 500}}
}
local rows = L.lootRows(pool)
eq(#rows > 0, true, "rows")
local per = {}
for _, r in ipairs(rows) do
	eq(r[3] >= L.config.minChance, true, "row floor " .. r[2])
	per[r[1]] = (per[r[1]] or 0) + r[3]
end
-- the sum per monster stays near the family totals times the boost (the floor and the rounding add a little)
local cfg = L.config
local total = 0
for _, kind in ipairs(L.KINDS) do
	total = total + cfg.monsterChance[kind]
end
eq(per["Rat"] >= total * 0.95 and per["Rat"] <= total * 1.05, true, "a rat carries " .. per["Rat"] .. " of about " .. total)
eq(per["Dragon"] > per["Rat"], true, "the boost grows with the level")
eq(per["Dragon"] <= total * cfg.boost.cap * 1.05, true, "the boost is capped")
-- a boss gets the boss totals, no boost
local bossTotal = 0
for _, kind in ipairs(L.KINDS) do
	bossTotal = bossTotal + cfg.bossChance[kind]
end
eq(per["Boss"] >= bossTotal * 0.95 and per["Boss"] <= bossTotal * 1.05, true, "a boss carries " .. per["Boss"])
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

print("class_loot_test: " .. n .. " checks ok")
