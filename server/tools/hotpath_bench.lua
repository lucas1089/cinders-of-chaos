-- hotpath_bench.lua: micro benchmark of the combat hot path changes of O199 (server/README.md "Combat hot paths (O199)").
-- Run from the server/ folder: luajit tools/hotpath_bench.lua   and   lua5.3 tools/hotpath_bench.lua
-- Each case times the old code (a copy kept here) against the new code on a mocked engine. Numbers are nanoseconds
-- per call, best of 5 runs. Nothing is asserted: the tests in tests/ check the behavior.
local clock = os.clock
local function bench(name, n, fn)
	local best = math.huge
	for _ = 1, 5 do
		local t = clock()
		fn(n)
		best = math.min(best, clock() - t)
	end
	return best / n * 1e9
end
local function report(title, n, old, new)
	local a, b = bench("old", n, old), bench("new", n, new)
	print(string.format("%-46s old %8.1f ns   new %8.1f ns   x%.2f", title, a, b, a / b))
end
print(_VERSION, jit and jit.version or "")

-- 1. mana flow think (mana_flow_core.lua)
dofile("data/scripts/chaos/mana_flow_config.lua")
dofile("data/scripts/chaos/mana_flow_core.lua")
local F = ChaosManaFlow
local function mkPlayer(level, mana, maxMana)
	return {getId = function() return level end, getLevel = function() return level end,
		getMana = function() return mana end, getMaxMana = function() return maxMana end,
		getHealth = function() return 100 end}
end
local runOf = {}
local function parched(pid)
	local run = runOf[pid]
	return run ~= nil and run.fx ~= nil and run.fx.noMana == true
end
for _, case in ipairs({{"full pool", 4000}, {"missing mana", 100}}) do
	local players = {}
	for i = 1, 200 do players[i] = mkPlayer(100 + i * 4, case[2], 4000) end
	local sink = 0
	report("mana think, 200 players, " .. case[1], 2000, function(n)
		for _ = 1, n / 200 + 1 do
			for _, p in ipairs(players) do
				local pid = p:getId()
				sink = sink + F.regenAmount(p:getLevel(), p:getMana(), p:getMaxMana(), parched(pid), p:getHealth() <= 0)
			end
		end
	end, function(n)
		for _ = 1, n / 200 + 1 do
			for _, p in ipairs(players) do
				sink = sink + F.thinkPlayer(p, parched)
			end
		end
	end)
end

-- 2. pack29 aura scan (pack29_vfx.lua): per player per scan, three rows
CONDITION_PARALYZE, CONDITION_DRUNK, CONDITION_REGENERATION, CONDITIONID_COMBAT = 1, 2, 3, 9
local scanRows = {
	{"CONDITION_PARALYZE", nil, "slowed"},
	{"CONDITION_DRUNK", nil, "confused"},
	{"CONDITION_REGENERATION", "CONDITIONID_COMBAT", "regeneration"},
}
local shown = 0
local V = {show = function() shown = shown + 1 end}
local player = {hasCondition = function() return false end, getCondition = function() return nil end}
local function scanOld(p)
	for _, row in ipairs(scanRows) do
		local ctype = _G[row[1]]
		if ctype then
			local cond
			if row[2] then
				cond = _G[row[2]] and p:getCondition(ctype, _G[row[2]])
			else
				cond = p:hasCondition(ctype)
			end
			if cond then V.show(p, row[3]) end
		end
	end
end
local resolved = {}
for _, row in ipairs(scanRows) do
	resolved[#resolved + 1] = {_G[row[1]], row[2] and _G[row[2]], row[2] ~= nil, row[3]}
end
local function scanNew(p, rows)
	for i = 1, #rows do
		local row = rows[i]
		local cond
		if row[3] then
			cond = row[2] and p:getCondition(row[1], row[2])
		else
			cond = p:hasCondition(row[1])
		end
		if cond then V.show(p, row[4]) end
	end
end
report("pack29 scan of one player", 2e6, function(n) for _ = 1, n do pcall(scanOld, player) end end,
	function(n) for _ = 1, n do pcall(scanNew, player, resolved) end end)

-- 3. gems hit callback (gems.lua): the totals key per damage type
local DAMAGE = {[1] = "physical", [2] = "fire", [4] = "ice", [8] = "earth", [16] = "energy", [32] = "death", [64] = "holy"}
local DMGKEY = {}
for k, v in pairs(DAMAGE) do DMGKEY[k] = "dmg_" .. v end
local totals = {dmg_physical = 5, dmg_fire = 0}
local acc = 0
report("gems hit: two totals lookups", 2e6, function(n)
	for _ = 1, n do
		local a = DAMAGE[1] and totals["dmg_" .. DAMAGE[1]] or 0
		local b = DAMAGE[2] and totals["dmg_" .. DAMAGE[2]] or 0
		acc = acc + a + b
	end
end, function(n)
	for _ = 1, n do
		local a = DMGKEY[1] and totals[DMGKEY[1]] or 0
		local b = DMGKEY[2] and totals[DMGKEY[2]] or 0
		acc = acc + a + b
	end
end)
