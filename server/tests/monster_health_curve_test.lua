-- Run from the server/ folder: luajit tests/monster_health_curve_test.lua (no engine; CI runs it with luajit and lua5.3)
-- O470 (2026-11-10): the health of a typical hunt monster by hunting level is one curve, no step where the base monster pool
-- ends (hunting level 657). Server/README.md "Monster health curve (O470)".
--
-- The typical monster, as tools/pack_model.py has it (median_health and SCALED_HEALTH): up to the end of the base pool
-- (657) the median health of the pool's base hunt monsters at that level (bounty_pool.lua, the monsters whose hunting level
-- is the estimate of their experience and health, not a level-scaled Chaos monster; spawns as weights; x1.11 for the tiers)
-- x pace_config.lua base.health; above it SCALED_HEALTH (the model median of the level-scaled monsters before the
-- multiplier, read from tools/pack_model.py) x pace_config.lua scaled.health. The monster files of the base server are not
-- in git: the pool's health column is what the model uses, so the test uses it too.
--
-- Asserts: (1) from hunting level 110 no rise above x1.35 over any 20 levels, and from 600 up none above x1.15 (the step
-- was x2.3); (2) no fall of more than the pool medians' lumps; (3) up to 600 within 10% of the values of before O470 (a table
-- in this file), 1000 and up unchanged; (4) the base and the level-scaled set meet at the seam within 10%; (5) the planned
-- kills per hour of the two sets meet at the seam too, and the scaled plan only falls from there to 1000.
dofile("data/scripts/chaos/pace_core.lua")
local P = ChaosPaceCore
local cfg = dofile("data/scripts/chaos/pace_config.lua")

local fails, checks = 0, 0
local function ok(cond, what)
	checks = checks + 1
	if not cond then
		fails = fails + 1
		print("FAIL " .. what)
	end
end

local function readFile(path)
	local f = assert(io.open(path, "r"))
	local s = f:read("*a")
	f:close()
	return s
end

-- ------------------------------------------------------------------------------------------------ the typical monster
local TIER_HEALTH = 1.11 -- pack_model.py TIER_HEALTH
local SEAM = 657 -- the pool's highest base hunting level (pace_config.lua comment O285)

-- SCALED_HEALTH of tools/pack_model.py: {{level, health}, ...}
local scaledHealth = {}
do
	local text = readFile("tools/pack_model.py")
	local body = text:match("SCALED_HEALTH = %[(.-)%]")
	ok(body ~= nil, "pack_model.py has SCALED_HEALTH")
	for a, b in (body or ""):gmatch("%((%d+), (%d+)%)") do
		scaledHealth[#scaledHealth + 1] = {tonumber(a), tonumber(b)}
	end
	ok(#scaledHealth == 5, "five SCALED_HEALTH points")
end

-- the names of the level-scaled Chaos monsters (a <level min=..> in their file): pack_model.py monsters()
local scaledNames = {}
do
	local p = io.popen("ls data/monster/monsters/chaos/*.xml")
	for path in p:lines() do
		local t = readFile(path)
		local name = t:match('<monster%s[^>]-name="([^"]+)"')
		if name and t:find('<level%s+min="%d+"') then
			scaledNames[name:lower()] = true
		end
	end
	p:close()
end

-- the base hunt monsters of the pool: {level, health, spawns}
local base = {}
do
	local pool = dofile("data/scripts/chaos/bounty_pool.lua")
	for _, e in ipairs(pool.hunt) do
		local lvl = e.level
		local est = P.estimateLevel(e.exp, e.health)
		if not scaledNames[e.name:lower()] and est == lvl and e.health > 0 and e.exp > 0 then
			base[#base + 1] = {lvl, e.health, e.spawns}
		end
	end
end
ok(#base > 500, "the pool lists more than 500 base hunt monsters: " .. #base)
local top = 0
for _, m in ipairs(base) do
	top = math.max(top, m[1])
end

-- pack_model.py median_health
local function median(L)
	local Lh = math.min(L, top)
	local hs = {}
	for _, m in ipairs(base) do
		if m[1] >= Lh * 0.75 and m[1] < Lh * 1.33 then
			for _ = 1, m[3] do
				hs[#hs + 1] = m[2]
			end
		end
	end
	table.sort(hs)
	return hs[math.floor(#hs / 2) + 1] * TIER_HEALTH * math.max(1, L / top)
end

-- the typical hunt monster's health at a hunting level
local function typical(c, L)
	if L <= SEAM then
		return median(L) * P.lin(c.base.health, L, 1)
	end
	return P.lin(scaledHealth, L, 1) * P.lin(c.scaled.health, L, 1)
end

-- ------------------------------------------------------------------------------------------------ the curve
local y = {}
for L = 10, 2200 do
	y[L] = typical(cfg, L)
end
-- levels 1-9: the health curve starts at 10, a monster there is untouched
ok(cfg.base.health[1][1] == 10 and cfg.base.health[1][2] == 1, "levels 1-9 are untouched (factor 1 from level 10)")

-- (1) the rise over 20 levels. The early game rises faster than x1.35 in relative terms (small numbers and the pool's lumps:
-- x1.6 at 100-103 before and after O470), so the rule is checked from level 110, where it holds for the whole curve now
local worst, worstAt = 0, 0
local worst600, worst600At = 0, 0
for L = 110, 2180 do
	local r = y[L + 20] / y[L]
	if r > worst then
		worst, worstAt = r, L
	end
	if L >= 600 and r > worst600 then
		worst600, worst600At = r, L
	end
end
ok(worst <= 1.35, string.format("no rise above x1.35 over 20 levels from 110: x%.3f at %d", worst, worstAt))
ok(worst600 <= 1.15, string.format("from 600 no rise above x1.15 over 20 levels (it was x2.3): x%.3f at %d", worst600, worst600At))
print(string.format("  largest rise over 20 levels: x%.3f at %d from level 110, x%.3f at %d from 600", worst, worstAt, worst600,
	worst600At))

-- (2) a monotone curve up to the pool's lumps: the median of the pool's monsters falls a little at a few levels (4540 at 520
-- against 4359 at 500 is a rise, but 4751 at 620 against 4837 at 600 is a fall of 1.8%, and 349 holds 5.4% below 345), so a
-- level may sit at most 6% under the highest before it; from 600 on at most 4% (the median drops 3.5% from 606 to 607: a
-- spawn count of the base pool, the base set is as before)
local runmax, deepest, deepestAt = 0, 0, 0
local runmax600, deepest600 = 0, 0
for L = 110, 2200 do
	runmax = math.max(runmax, y[L])
	if 1 - y[L] / runmax > deepest then
		deepest, deepestAt = 1 - y[L] / runmax, L
	end
	if L >= 600 then
		runmax600 = math.max(runmax600, y[L])
		deepest600 = math.max(deepest600, 1 - y[L] / runmax600)
	end
end
ok(deepest <= 0.06, string.format("no level more than 6%% under the highest one before it: %.1f%% at %d", deepest * 100, deepestAt))
ok(deepest600 <= 0.04, string.format("from 600 no level more than 4%% under the highest before it: %.1f%%", deepest600 * 100))
-- the scaled set alone (above the seam) never falls
for L = SEAM + 2, 2200 do
	ok(y[L] >= y[L - 1] - 1e-9, "the level-scaled curve rises at " .. L)
end

-- (3) up to 600 within 10% of before O470; 1000 and up unchanged (the values of the model before the change)
local before = {[10] = 77.7, [20] = 77.7, [35] = 155.4, [50] = 224.2, [75] = 358.9, [100] = 477.9, [150] = 837.4, [200] = 1106.4,
	[250] = 1771.6, [300] = 1774.9, [350] = 2117.9, [400] = 3019.2, [450] = 3807.3, [500] = 4359.0, [550] = 4440.0, [600] = 4836.8}
for L, v in pairs(before) do
	ok(math.abs(y[L] / v - 1) <= 0.10, string.format("level %d within 10%% of before O470: %.1f against %.1f", L, y[L], v))
end
local unchanged = {[1000] = 16620.0, [1300] = 22032.0, [1600] = 27235.7, [2000] = 34394.0, [2200] = 34394.0}
for L, v in pairs(unchanged) do
	ok(math.abs(y[L] / v - 1) <= 0.001, string.format("level %d unchanged: %.1f against %.1f", L, y[L], v))
end
-- and the points themselves: 1000 and up as before
local was = {{1000, 0.080}, {1300, 0.068}, {1600, 0.062}, {2000, 0.058}}
for _, p in ipairs(was) do
	ok(math.abs(P.lin(cfg.scaled.health, p[1], 0) - p[2]) < 1e-9, "scaled.health point " .. p[1] .. " is as before")
end
-- the base curve is not touched at all (O470 solved it on the level-scaled side)
local baseWas = {{10, 1.00}, {20, 0.280}, {35, 0.200}, {60, 0.136}, {100, 0.105}, {150, 0.092}, {200, 0.089}, {250, 0.095},
	{300, 0.082}, {350, 0.072}, {400, 0.085}, {450, 0.098}, {500, 0.102}, {550, 0.100}, {600, 0.105}, {650, 0.110}}
for _, p in ipairs(baseWas) do
	ok(math.abs(P.lin(cfg.base.health, p[1], 0) - p[2]) < 1e-9, "base.health point " .. p[1] .. " is as before")
end
-- the level-scaled monsters of levels below 600 (about fifteen in the pool, levels 430-590) keep their curve as it was
for _, L in ipairs({100, 300, 430, 500, 550, 590, 600}) do
	local was = 0.10 + (0.1364 - 0.10) * (L - 100) / 500
	ok(math.abs(P.lin(cfg.scaled.health, L, 0) / was - 1) <= 0.01, "scaled health at " .. L .. " is as before")
end

-- (4) the seam: the base set at its last level and the level-scaled set one level above
local a, b = y[SEAM], y[SEAM + 1]
ok(math.abs(b / a - 1) <= 0.10, string.format("the sets meet at the seam within 10%%: %.0f at %d, %.0f at %d", a, SEAM, b, SEAM + 1))
print(string.format("  seam: %.0f at %d, %.0f at %d (x%.3f)", a, SEAM, b, SEAM + 1, b / a))
-- the numbers of before: a step of x2.28 there
ok(b / a < 1.10, "no step at the seam (it was x2.28)")

-- (5) planned kills per hour (tools/spawn_tuning.json): the two sets meet at the seam, the scaled plan only falls from there
ChaosLootModelLib = true
local LM = dofile("tools/loot_model.lua")
ChaosLootModelLib = nil
local kph = LM.killsTable()
local kb, ks = P.lin(kph.base, SEAM, 1), P.lin(kph.scaled, SEAM, 1)
ok(math.abs(ks / kb - 1) <= 0.10, string.format("planned kills per hour meet at the seam within 10%%: %.0f base, %.0f scaled", kb, ks))
local prev = ks
for L = SEAM + 1, 2200 do
	local k = P.lin(kph.scaled, L, 1)
	ok(k <= prev + 1e-9, "the scaled plan does not rise at " .. L)
	prev = k
end
-- the scaled plan is under the base plan, as the late monsters need more kills' worth of time
for L = SEAM + 1, 2200 do
	ok(P.lin(kph.scaled, L, 1) <= P.lin(kph.base, L, 1) + 1e-9, "the scaled plan is not above the base plan at " .. L)
end

print(string.format("monster_health_curve_test: %d of %d failed", fails, checks))
os.exit(fails == 0 and 0 or 1)
