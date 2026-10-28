-- Run from the server/ folder: luajit tests/hunt_display_levels_test.lua (or lua5.3; CI runs both)
-- Owner 2026-10-27 (bug B): no monster standing in a hunt shows a nameplate level far below the hunt's band. Crosses the
-- bounty pool, the bestiary spawn data and the map marks (hunting levels): every monster that spawns within the
-- area radius of a hunt mark with a lower end of 100 or more is shown (monster_levels.lua rules: the pool level x
-- baseLevelMult (1 since 2026-10-28, O285), a monster outside the pool raised to its hunt's lower end) at no less than K.farBelow x that lower end.
local failures, count = 0, 0
local function check(cond, label)
	count = count + 1
	if not cond then
		failures = failures + 1
		print("FAIL " .. label)
	end
end

dofile("data/scripts/chaos/monster_levels_core.lua")
dofile("data/scripts/chaos/pace_core.lua")
local K, P = ChaosMonsterLevelsCore, ChaosPaceCore
local pace = dofile("data/scripts/chaos/pace_config.lua")
local pool = dofile("data/scripts/chaos/bounty_pool.lua")
local spawns = dofile("data/scripts/chaos/bestiary_spawns.lua")
local poi = dofile("data/chaos_poi.lua")

local byName = {}
for _, list in ipairs({pool.hunt or {}, pool.bosses or {}}) do
	for _, e in ipairs(list) do
		byName[e.name:lower()] = e
	end
end
local idx = K.indexHunts(poi.marks)
local hunts = {}
for _, m in ipairs(poi.marks) do
	if m.k == "hunt" then
		local lo = K.bandOf(m.n)
		if lo and lo >= 100 then
			hunts[#hunts + 1] = {m = m, lo = lo}
		end
	end
end
check(#hunts > 20, "the map has hunts of 100+ (" .. #hunts .. ")")

local unlisted, low = {}, {}
for name, sp in pairs(spawns) do
	for _, a in ipairs(sp.areas or {}) do
		local x, y, z = a[1], a[2], a[3]
		for _, h in ipairs(hunts) do
			local hm = h.m
			if hm.z == z and math.max(math.abs(hm.x - x), math.abs(hm.y - y)) <= K.areaRadius then
				local e = byName[name]
				local shown
				if e then
					shown = P.entryLevel(pace, e)
				else
					unlisted[name] = true
					shown = K.raise(1 * pace.baseLevelMult, K.areaFloor(idx, x, y, z))
				end
				if e and shown < h.lo * K.farBelow then
					-- a listed monster this far below its hunt is raised by monster_levels.lua (K.areaFloor)
					shown = K.raise(shown, K.areaFloor(idx, x, y, z))
				end
				if shown < h.lo * K.farBelow then
					low[#low + 1] = name .. " " .. shown .. " in " .. hm.n
				end
			end
		end
	end
end
check(#low == 0, "monsters far below their hunt: " .. table.concat(low, "; "))
local n = 0
for _ in pairs(unlisted) do
	n = n + 1
end
check(n > 0, "the data still has monsters outside the pool in hunts (the rule is exercised): " .. n)

if failures > 0 then
	print(string.format("hunt_display_levels_test: %d checks, %d FAILED", count, failures))
	os.exit(1)
end
print(string.format("hunt_display_levels_test: %d checks, 0 failures", count))
