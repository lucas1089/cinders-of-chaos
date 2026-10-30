-- Run from the server/ folder: luajit tests/unique_open_level_test.lua (and lua5.3; CI runs both)
-- O342: the leveling uniques drop from any monster near their level (loot_config.lua unique.openLevel, loot.lua
-- L.openLevelMult / L.rollUniques), the pace model (tools/unique_pace_model.lua) and the faster monster pity.
local checks, fails = 0, 0
local function ok(cond, what)
	checks = checks + 1
	if not cond then
		fails = fails + 1
		print("FAIL " .. what)
	end
end

ChaosUniquePaceLib = true
local M = dofile("tools/unique_pace_model.lua")
ChaosUniquePaceLib = nil
local L, C = ChaosLoot, ChaosLootConfig
local u = C.unique
local o = u.openLevel
local V = M.V

-- ---------------------------------------------------------------- the window
local savedO = {}
for k, v in pairs(o) do savedO[k] = v end
o.mult = {{1, 2}} -- flat 2 for the window tests
local e = {id = 9001, name = "Level 100 Blade", level = 100, minTier = "rare", chance = 10, monsters = {"Listed"}}
ok(L.openLevelMult(e, 100) == 2, "the item's own level is inside")
ok(L.openLevelMult(e, 90) == 2, "10% below the item's level is inside (lower edge)")
ok(L.openLevelMult(e, 89) == nil, "below 90% of the item's level is outside")
ok(L.openLevelMult(e, 210) == 2, "level x above + aboveFlat is inside (upper edge)")
ok(L.openLevelMult(e, 211) == nil, "above the window is outside")
ok(L.openLevelMult(e, 0) == nil and L.openLevelMult(e, nil) == nil, "no monster level: the name list holds")
ok(L.openLevelMult({id = 1, minTier = "rare", chance = 5}, 50) == nil, "an entry without a level is never opened")
ok(L.openLevelMult({id = 1, level = 100, bossOnly = true}, 100) == nil, "a boss-only entry stays home")
ok(L.openLevelMult({id = 1, level = 1000, minMonsterLevel = 1000}, 1000) == nil, "an endgame entry keeps the O148 rule")
ok(L.openLevelMult({id = 1, level = 750}, 750) == nil, "an item above maxItemLevel is not opened")
o.enabled = false
ok(L.openLevelMult(e, 100) == nil, "disabled: the lists hold")
o.enabled = true
o.mult = {{1, 0}, {100, 1}, {200, 3}}
ok(L.openLevelMult(e, 150) == 2, "the multiplier is a curve of the monster level (linear)")
ok(L.openLevelMult(e, 5) == nil, "a multiplier of 0 closes the window")
for k, v in pairs(savedO) do o[k] = v end

-- ---------------------------------------------------------------- L.rollUniques
local savedPity = _G.ChaosConquest
_G.ChaosConquest = nil
do
	local list = {
		{id = 9101, name = "Blade", minTier = "rare", chance = 100, level = 100, monsters = {"Listed"}},
		{id = 9102, name = "Magic Cap", minTier = "magic", chance = 100, level = 100, monsters = {"Listed"}},
		{id = 9103, name = "Crown", minTier = "boss", chance = 100, level = 100, bossOnly = true, monsters = {"Listed"}},
		{id = 9104, name = "Far Blade", minTier = "rare", chance = 100, level = 400, monsters = {"Listed"}}
	}
	o.mult = {{1, 1}}
	local function ids(hits)
		local t = {}
		for _, h in ipairs(hits) do t[#t + 1] = h.id end
		table.sort(t)
		return table.concat(t, ",")
	end
	L.setRandom(function(a, b) return a end) -- every roll hits
	local saveMax = u.maxPerKill
	u.maxPerKill = 10
	ok(ids(L.rollUniques("rare", "Wolf", 100, 1, list, nil)) == "9101,9102", "an unlisted level 100 monster: the two level 100 entries")
	ok(ids(L.rollUniques("magic", "Wolf", 100, 1, list, nil)) == "9102", "magic: minTier holds")
	ok(ids(L.rollUniques("normal", "Wolf", 100, 1, list, nil)) == "", "normal monsters drop no unique")
	ok(ids(L.rollUniques("boss", "Wolf", 100, 1, list, nil)) == "9101,9102", "a boss: the boss-only entry stays home")
	ok(ids(L.rollUniques("rare", "Wolf", 50, 1, list, nil)) == "", "a level 50 monster is below the window")
	ok(ids(L.rollUniques("rare", "Wolf", 300, 1, list, nil)) == "", "level 300: between both windows (90 - 210, 360 - 810)")
	ok(ids(L.rollUniques("rare", "Wolf", 400, 1, list, nil)) == "9104", "level 400: only the level 400 entry")
	ok(ids(L.rollUniques("rare", "Listed", 5, 1, list, nil)) == "9101,9102,9104", "a listed monster drops at any level")
	u.maxPerKill = saveMax
	L.setRandom(nil)

	-- the chance of an open drop is the entry's chance x tier x pace x the curve; a listed one keeps the full chance
	o.mult = {{1, 0.25}}
	local n, hitsOpen, hitsListed = 40000, 0, 0
	math.randomseed(42)
	L.setRandom(function(a, b) return math.random(a, b) end)
	local one = {{id = 9201, name = "Probe", minTier = "rare", chance = 20, level = 100, monsters = {"Listed"}}}
	for _ = 1, n do
		hitsOpen = hitsOpen + #L.rollUniques("rare", "Wolf", 100, 1, one, nil)
		hitsListed = hitsListed + #L.rollUniques("rare", "Listed", 100, 1, one, nil)
	end
	L.setRandom(nil)
	local want = 20 * u.tierMult.rare / 10000 -- 0.4%
	ok(math.abs(hitsListed / n - want) < want * 0.25, string.format("listed monster: %.4f vs %.4f", hitsListed / n, want))
	ok(math.abs(hitsOpen / n - want * 0.25) < want * 0.25 * 0.35, string.format("open drop: %.4f vs %.4f", hitsOpen / n, want * 0.25))
end
_G.ChaosConquest = savedPity
for k, v in pairs(savedO) do o[k] = v end

-- ---------------------------------------------------------------- the shipped rule and the pace
ok(o.enabled and o.maxItemLevel >= 650 and o.above >= 2, "shipped: on, covers items up to level 650")
ok(o.below > 0 and o.below <= 0.2, "shipped: the window starts at most 20% below the item level")
local prev = 0
for _, p in ipairs(o.mult) do
	ok(p[1] > prev and p[2] > 0, "shipped: multiplier points ascend and are positive at " .. p[1])
	prev = p[1]
end
ok(#M.leveling() == 97, "97 leveling uniques (no season): " .. #M.leveling())

-- the model against the real function: Rare monster, level 100, an unlisted name, fixed generator
do
	local pace = M.pace(100)
	local q = M.tierChance("rare", "Zzz Unlisted", 100, pace)
	local want = q.monster + q.set - q.monster * q.set
	math.randomseed(7)
	L.setRandom(function(a, b) return math.random(a, b) end)
	local chaos = _G.ChaosConquest
	_G.ChaosConquest = nil
	local n, got = 60000, 0
	for _ = 1, n do
		got = got + math.min(1, #L.rollUniques("rare", "Zzz Unlisted", 100, pace, nil, nil))
	end
	_G.ChaosConquest = chaos
	L.setRandom(nil)
	got = got / n
	ok(want > 0 and math.abs(got - want) < 0.2 * want, string.format("model %.5f vs rollUniques %.5f", want, got))
end

-- tier mix: the cumulative thresholds of monster_tiers.lua (a roll under 600 is magic, under 150 rare, under 25 legendary)
do
	local s = M.tierShares(0)
	ok(math.abs(s.legendary - 0.0025) < 1e-9 and math.abs(s.rare - 0.0125) < 1e-9 and math.abs(s.magic - 0.045) < 1e-9,
		"tier shares without ambush: 0.25% / 1.25% / 4.5%")
	local a = M.tierShares(1)
	ok(a.magic + a.rare + a.legendary > 0.0625, "ambush copies add Magic+ kills")
	ok(math.abs(a.normal + a.magic + a.rare + a.legendary - 1) < 1e-9, "shares sum to 1")
end

-- the bands, the hall hunts and the pity of the shipped numbers (the same limits as --check)
for _, b in ipairs(V.bands) do
	local r = M.band(b.level)
	ok(r ~= nil, "band " .. b.level .. " has monsters")
	if r then
		ok(r.kills >= b.min and r.kills <= b.max, string.format("band %d: %.0f kills per unique (%d - %d)", b.level, r.kills, b.min, b.max))
		local speed = r.kills / r.pity
		ok(speed >= V.pity.minSpeedup and speed <= V.pity.maxSpeedup, string.format("band %d: pity speed-up %.2f", b.level, speed))
	end
end
-- without the rule the same bands are far out (the reason for it)
do
	local r = M.band(100, {legacy = true})
	ok(r.kills > 10000, "before the rule: level 100 needed " .. math.floor(r.kills) .. " kills")
end

-- ---------------------------------------------------------------- the monster pity
do
	local CQ = dofile("data/scripts/chaos/conquest_config.lua")
	ok(CQ.pity.monster.step == 0.02 and CQ.pity.monster.cap == 3, "monster pity: +2% per miss, up to x3")
	dofile("data/scripts/chaos/conquest_core.lua")
	local K = ChaosConquestCore
	if K and K.pityMult then
		ok(math.abs(K.pityMult(CQ, "monster", 50) - 2) < 1e-9, "50 misses: x2")
		ok(K.pityMult(CQ, "monster", 100) == 3 and K.pityMult(CQ, "monster", 5000) == 3, "x3 from 100 misses, never more")
	end
end

print(string.format("unique_open_level_test: %d of %d failed", fails, checks))
os.exit(fails == 0 and 0 or 1)
