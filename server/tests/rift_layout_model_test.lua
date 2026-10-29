-- Run from the server/ folder: luajit tests/rift_layout_model_test.lua (CI runs it with LuaJIT and Lua 5.3)
-- The rift layout model (tools/rift_layout_model.lua, rift_layout_balance_config.lua, O309): the density floor of
-- rift_core.lua (a monster for at most density.area.tilesPerMonster walkable tiles), the kind scale of the layout plan,
-- and the check: it passes on the shipped config and fails on the layouts of before the fix (big maps, 50-85 tiles a
-- monster, 7-10 minutes of sweeping).
local checks, fails = 0, 0
local function ok(cond, what)
	checks = checks + 1
	if not cond then
		fails = fails + 1
		print("FAIL " .. tostring(what))
	end
end
local function eq(a, b, what)
	ok(a == b, (what or "check") .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end

dofile("data/scripts/chaos/rift_layout_core.lua")
dofile("data/scripts/chaos/rift_core.lua")
local RL, R = ChaosRiftLayout, ChaosRiftCore
local cfg = dofile("data/scripts/chaos/rift_config.lua")
local ag = dofile("data/scripts/chaos/areagen_config.lua")
ChaosRiftLayoutModelLib = true
local M = dofile("tools/rift_layout_model.lua")
local B = M.B

-- ---------------------------------------------------------------- the density floor
local a = cfg.density.area
local function tpm(tier)
	return a.tilesPerMonster[1] + (a.tilesPerMonster[2] - a.tilesPerMonster[1]) * (tier - 1) / (cfg.maxTier - 1)
end
ok(a.tilesPerMonster[1] <= B.limits.tilesPerMonster, "the floor is inside the model's limit")
ok(a.tilesPerMonster[2] < a.tilesPerMonster[1], "denser at the top tiers")
for _, area in ipairs({3000, 6000, 12000, 20000, 30000}) do
	for _, tier in ipairs({1, 6, 11, 15}) do
		local n = R.densityCount(cfg, tier, 1, area)
		ok(n >= area / tpm(tier) - 1e-6, string.format("tier %d on %d tiles: %.0f monsters, a monster per at most %.1f tiles",
			tier, area, n, tpm(tier)))
		local d = R.density(cfg, tier, 1, nil, area)
		ok(area / d.count <= tpm(tier) + 1.5, string.format("tier %d on %d tiles: plan of %d monsters", tier, area, d.count))
	end
end
-- a band's monsters still grow with the tier on the same map
for tier = 2, cfg.maxTier do
	ok(R.densityCount(cfg, tier, 1, 9000) > R.densityCount(cfg, tier - 1, 1, 9000), "more monsters on tier " .. tier)
end
-- a small map keeps the tier's own count (the floor does not apply)
eq(R.densityCount(cfg, 1, 1, 1081), 80, "a map of the reference size: the base count")
-- a party's growth comes on top of the floor
ok(R.densityCount(cfg, 6, 5, 9000) >= 9000 / tpm(6) * 2 - 1e-6, "a party of five: twice the floor")
-- no area: the band's typical layout
for tier = 1, 15 do
	local t = R.typicalLayout(cfg, tier)
	ok(R.densityCount(cfg, tier, 1) >= t.walkable / tpm(tier) - 1e-6, "tier " .. tier .. ": the typical layout meets the floor")
end
-- the live cap follows the map
ok(R.liveCap(cfg, 1, 14000, 15) > R.liveCap(cfg, 1, 6000, 1), "a bigger map keeps more monsters alive")

-- ---------------------------------------------------------------- the plan of a kind
do
	local req = {theme = "Abyssal Rift", band = 2, seed = 5, origin = {x = 20480, y = 20480, z = 7}}
	local sides = {}
	for _, kind in ipairs({"waste", "cave"}) do
		req.kind, req.floors = kind, 1
		sides[kind] = RL.plan(cfg, req).size[1]
	end
	eq(sides.cave, cfg.layout.sizes[2][2], "a cave has the band's side")
	eq(sides.waste, math.floor(cfg.layout.sizes[2][2] * cfg.layout.kindScale.waste + 0.5), "an open waste is scaled down")
	local nokind = {}
	for k, v in pairs(cfg.layout) do
		nokind[k] = v
	end
	nokind.kindScale = nil
	local c2 = {}
	for k, v in pairs(cfg) do
		c2[k] = v
	end
	c2.layout = nokind
	req.kind = "waste"
	eq(RL.plan(c2, req).size[1], cfg.layout.sizes[2][2], "no kindScale: the band's side")
end

-- ---------------------------------------------------------------- the model on the shipped config
ok(#cfg.layout.sizes == #B.limits.walkableMax and #cfg.layout.sizes == #B.limits.walkableMin, "limits for every band")
eq(select(1, M.tiersOf(cfg, 1)), 1, "band 1 starts at tier 1")
eq(select(2, M.tiersOf(cfg, 1)), 5, "band 1 ends at tier 5")
eq(select(1, M.tiersOf(cfg, 2)), 6, "band 2 starts at tier 6")
eq(select(2, M.tiersOf(cfg, 3)), cfg.maxTier, "the last band ends at the last tier")
local all = M.measureAll(cfg, ag)
eq(#all, #cfg.themes * #cfg.layout.sizes * B.samples, "every theme, band and sample")
local problems = M.problems(cfg, all)
eq(#problems, 0, "the shipped layouts are inside the limits: " .. table.concat(problems, " | "))

-- ---------------------------------------------------------------- the model catches the layouts of before
-- sizes 160 / 200 / 240, no kind scale, two floors 0.8, no density floor, a monster per 50-85 tiles
do
	local old = {}
	for k, v in pairs(cfg) do
		old[k] = v
	end
	local lay = {}
	for k, v in pairs(cfg.layout) do
		lay[k] = v
	end
	lay.sizes = {{5, 160, 1000}, {10, 200, 1100}, {15, 240, 1260}}
	lay.kindScale, lay.twoFloorScale = nil, 0.8
	lay.typical = {{walkable = 8500, route = 200}, {walkable = 14800, route = 265}, {walkable = 21200, route = 340}}
	old.layout = lay
	local dens = {}
	for k, v in pairs(cfg.density) do
		dens[k] = v
	end
	dens.area = {ref = a.ref, exp = a.exp, maxMult = a.maxMult}
	dens.live = {base = 60, perExtraPlayer = 10, per100 = 0.5, max = 260}
	old.density = dens
	-- two themes, one sample each, band 3 (the biggest) and band 2 (the report): enough to see it
	local sample = {}
	for _, spec in ipairs({{"Forsaken Sanctum", 2, 537}, {"Abyssal Rift", 3, 611}, {"Obsidian Hall", 3, 574}}) do
		sample[#sample + 1] = M.measure(old, ag, spec[1], spec[2], spec[3])
	end
	local p = M.problems(old, sample)
	ok(#p >= 6, "the old layouts fail the check (" .. #p .. " problems)")
	local seen = {}
	for _, line in ipairs(p) do
		for _, key in ipairs({"tiles per monster", "tiles per live", "full sweep", "walkable tiles, at most"}) do
			if line:find(key, 1, true) then
				seen[key] = true
			end
		end
	end
	ok(seen["tiles per monster"] and seen["tiles per live"], "too few monsters for the floor is reported")
	ok(seen["walkable tiles, at most"], "a map above the band's walkable limit is reported")
	-- the report's layout: tier 6 Forsaken Sanctum, 168 of 214 slain
	local worst = sample[1].rows[1]
	ok(worst.tpm > 45, "the reported Sanctum had over 45 tiles a monster (" .. string.format("%.0f", worst.tpm) .. ")")
end

print(string.format("rift_layout_model_test: %d checks, %d failed", checks, fails))
os.exit(fails == 0 and 0 or 1)
