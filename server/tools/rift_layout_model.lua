-- The rift layout model (server/README.md "Rifts", Layout size and density, O309): how big the generated rift maps are
-- against the monsters they hold, and how long it takes to walk them.
--
--     cd server && luajit tools/rift_layout_model.lua            the table (also lua5.3)
--     cd server && luajit tools/rift_layout_model.lua --check    exit 1 when a layout leaves the limits
--     cd server && luajit tools/rift_layout_model.lua --typical  the mean walkable / route per band (layout.typical)
--
-- Inputs, all in the repository: rift_config.lua (layout, density, tiers), rift_layout_core.lua and areagen_core.lua (the
-- generator), rift_core.lua (the plan: R.density, R.tilesPerSecond), rift_layout_balance_config.lua (samples, limits).
-- Computed from the generator, not measured on a server. A test can load it as a library:
-- ChaosRiftLayoutModelLib = true; local M = dofile("tools/rift_layout_model.lua").

dofile("data/scripts/chaos/rift_layout_core.lua")
dofile("data/scripts/chaos/rift_core.lua")
local RL, R = ChaosRiftLayout, ChaosRiftCore
local B = dofile("data/scripts/chaos/rift_layout_balance_config.lua")

local M = {B = B}

-- the tiers of a size band: from the first above the band before, to the band's own last (the last band: maxTier)
function M.tiersOf(cfg, band)
	local sizes = cfg.layout.sizes
	local first = band == 1 and 1 or sizes[band - 1][1] + 1
	local last = band == #sizes and cfg.maxTier or sizes[band][1]
	return first, last
end

-- one measured layout: {theme, band, seed, kind, floors, side, walkable, route, rows = {{tier, count, live, ...}}}
function M.measure(cfg, ag, theme, band, seed)
	local L = RL.generate(cfg, ag, {theme = theme, band = band, seed = seed, origin = {x = 20480, y = 20480, z = 7}}, {})
	local _, _, limit = RL.band(cfg, M.tiersOf(cfg, band))
	local m = {theme = theme, band = band, seed = seed, kind = L.kind, floors = #L.floors, side = L.side,
		walkable = L.walkable, route = L.route, limit = limit, rows = {}}
	local first, last = M.tiersOf(cfg, band)
	for _, tier in ipairs({first, last}) do
		local d = R.density(cfg, tier, 1, nil, L.walkable)
		local tps = R.tilesPerSecond(R.tierInfo(cfg, tier).minLevel)
		m.rows[#m.rows + 1] = {tier = tier, count = d.count, live = d.live, tpm = L.walkable / d.count,
			tpl = L.walkable / d.live, sweep = L.walkable / B.sweepWidth / tps, routeSeconds = R.walkSeconds(cfg, tier, L.route)}
	end
	return m
end

function M.measureAll(cfg, ag)
	local all = {}
	for _, th in ipairs(cfg.themes) do
		for band = 1, #cfg.layout.sizes do
			for i = 1, B.samples do
				all[#all + 1] = M.measure(cfg, ag, th.name, band, B.seedBase + i * B.seedStep)
			end
		end
	end
	return all
end

-- the problems of a list of measured layouts against B.limits (strings)
function M.problems(cfg, all)
	local lim, out = B.limits, {}
	local function bad(m, fmt, ...)
		out[#out + 1] = string.format("%s band %d seed %d (%s, %d floor, side %d): " .. fmt, m.theme, m.band, m.seed, m.kind,
			m.floors, m.side, ...)
	end
	local byBand = {}
	for _, m in ipairs(all) do
		local b = byBand[m.band] or {n = 0, walkable = 0, route = 0, min = math.huge, max = 0}
		byBand[m.band] = b
		b.n, b.walkable, b.route = b.n + 1, b.walkable + m.walkable, b.route + m.route
		b.min, b.max = math.min(b.min, m.walkable), math.max(b.max, m.walkable)
		if m.walkable > lim.walkableMax[m.band] then
			bad(m, "%d walkable tiles, at most %d", m.walkable, lim.walkableMax[m.band])
		elseif m.walkable < lim.walkableMin[m.band] then
			bad(m, "%d walkable tiles, at least %d", m.walkable, lim.walkableMin[m.band])
		end
		for _, r in ipairs(m.rows) do
			if r.tpm > lim.tilesPerMonster then
				bad(m, "tier %d: %.0f tiles per monster (%d monsters on %d tiles), at most %d", r.tier, r.tpm, r.count,
					m.walkable, lim.tilesPerMonster)
			end
			if r.tpl > lim.tilesPerLive then
				bad(m, "tier %d: %.0f tiles per live monster (%d alive), at most %d", r.tier, r.tpl, r.live, lim.tilesPerLive)
			end
			local sweepMax = math.min(lim.sweepSecondsMax, lim.sweepShare * m.limit)
			if r.sweep > sweepMax then
				bad(m, "tier %d: the full sweep takes %.0f s, at most %.0f", r.tier, r.sweep, sweepMax)
			end
			if r.routeSeconds > lim.routeSecondsMax then
				bad(m, "tier %d: the way to the arena takes %.0f s, at most %d", r.tier, r.routeSeconds, lim.routeSecondsMax)
			end
		end
	end
	for band, b in pairs(byBand) do
		if b.max > b.min * lim.spreadMax then
			out[#out + 1] = string.format("band %d: walkable %d to %d, the largest is %.2fx the smallest, at most %.2f", band, b.min,
				b.max, b.max / b.min, lim.spreadMax)
		end
		local typ = cfg.layout.typical[band]
		local w, r = b.walkable / b.n, b.route / b.n
		if math.abs(w / typ.walkable - 1) > lim.typicalTolerance or math.abs(r / typ.route - 1) > lim.typicalTolerance then
			out[#out + 1] = string.format("band %d: measured mean walkable %.0f route %.0f, layout.typical says %d / %d (--typical)",
				band, w, r, typ.walkable, typ.route)
		end
	end
	return out
end

function M.report(cfg, all)
	print(string.format("%-17s %4s %-7s %2s %4s %8s %5s | %4s %6s %5s %6s %6s %6s %6s", "theme", "band", "kind", "fl", "side",
		"walkable", "route", "tier", "monst", "live", "t/mon", "t/live", "sweep", "route"))
	for _, m in ipairs(all) do
		for i, r in ipairs(m.rows) do
			print(string.format("%-17s %4d %-7s %2d %4d %8d %5d | %4d %6d %5d %6.0f %6.0f %5.0fs %5.0fs",
				i == 1 and m.theme or "", m.band, m.kind, m.floors, m.side, m.walkable, m.route, r.tier, r.count, r.live,
				r.tpm, r.tpl, r.sweep, r.routeSeconds))
		end
	end
end

if ChaosRiftLayoutModelLib then
	return M
end

local cfg = dofile("data/scripts/chaos/rift_config.lua")
local ag = dofile("data/scripts/chaos/areagen_config.lua")
local all = M.measureAll(cfg, ag)
if arg and arg[1] == "--typical" then
	for band = 1, #cfg.layout.sizes do
		local n, w, r = 0, 0, 0
		for _, m in ipairs(all) do
			if m.band == band then
				n, w, r = n + 1, w + m.walkable, r + m.route
			end
		end
		print(string.format("band %d: {walkable = %d, route = %d}", band, math.floor(w / n + 0.5), math.floor(r / n + 0.5)))
	end
	return
end
if not (arg and arg[1] == "--check") then
	M.report(cfg, all)
	return
end
local problems = M.problems(cfg, all)
for _, p in ipairs(problems) do
	print("FAIL " .. p)
end
print(string.format("rift_layout_model: %d layouts, %d problem(s)", #all, #problems))
os.exit(#problems == 0 and 0 or 1)
