-- Run from the server/ folder: luajit tests/mana_flow_test.lua (and lua5.3; CI runs both)
-- The mana flow (server/README.md "Mana flow"): regeneration by level and the cap of a spell's cost. Beta report:
-- a level 800 Juggernaut sustained nothing without infinite mana potions.
local count, failures = 0, 0
local function eq(a, b, what)
	count = count + 1
	if a ~= b then failures = failures + 1; print("FAIL " .. tostring(what) .. ": " .. tostring(a) .. " ~= " .. tostring(b)) end
end
dofile("data/scripts/chaos/mana_flow_config.lua")
dofile("data/scripts/chaos/mana_flow_core.lua")
local F, C = ChaosManaFlow, ChaosManaFlowConfig

-- regeneration curve
eq(F.regenPerSecond(99), 0, "none below the first level")
eq(F.regenPerSecond(100), 4, "level 100")
eq(F.regenPerSecond(200), 14, "level 200 (linear)")
eq(F.regenPerSecond(300), 24, "level 300")
eq(F.regenPerSecond(800), 52.5, "level 800")
eq(F.regenPerSecond(1000), 60, "level 1000")
eq(F.regenPerSecond(1500), 60, "the last value holds")
local prev = 0
for lv = 1, 1200 do
	local r = F.regenPerSecond(lv)
	eq(r >= prev, true, "never falls at " .. lv)
	prev = r
end

-- the amount of one think
eq(F.regenAmount(800, 100, 4000, false, false), 53, "level 800 gives 53 (52.5 rounded)")
eq(F.regenAmount(800, 3990, 4000, false, false), 10, "never past the maximum")
eq(F.regenAmount(800, 4000, 4000, false, false), 0, "full pool")
eq(F.regenAmount(800, 100, 4000, true, false), 0, "Parched Veins")
eq(F.regenAmount(800, 100, 4000, false, true), 0, "dead")
eq(F.regenAmount(50, 10, 400, false, false), 0, "below level 100")

-- the sustain claim: the Juggernaut's best rotation (rotation_sim.py --mana: 44 mana a second at 300) against the
-- vocation's own 2.5 a second plus the flow; at 600+ the rotation is paid, at 300 the runway is over 60 s
local VOC_REGEN = 2.5
local function pool(level) return 35 + (level - 1) * 5 end
eq(F.regenPerSecond(600) + VOC_REGEN >= 44, true, "level 600 sustains the level 300 rotation")
eq(F.regenPerSecond(800) + VOC_REGEN >= 50, true, "level 800 sustains 50 a second")
eq(pool(300) / (44 - F.regenPerSecond(300) - VOC_REGEN) > 60, true, "level 300 runway over 60 s")
eq(pool(100) / (31.25 - F.regenPerSecond(100) - VOC_REGEN) >= 15, true, "level 100 keeps the 15 s runway rule")

-- the cap
eq(F.capCost(400, 800, 4000, 0), 400, "400 of 4000 is under 25%")
eq(F.capCost(1800, 800, 4000, 0), 1000, "capped at 25% of the maximum")
eq(F.capCost(400, 260, 1330, 0), 332, "Colossus Fall at level 260: 25% of 1330")
eq(F.capCost(400, 99, 100, 0), 400, "below level 100 no cap")
eq(F.capCost(0, 800, 4000, 0), 0, "a free cast stays free")
eq(F.capCost(1800, 800, 1000, 3000), 1000, "reserved mana counts: 25% of 4000, not of 1000")
eq(F.capCost(5, 800, 0, 0), 5, "no pool known: unchanged")
eq(F.capCost(5, 800, 3, 0), 1, "at least 1 when capped")

-- the engine glue against a mock
local added = {}
local players = {}
local function mkPlayer(id, level, mana, maxMana, health)
	return {getId = function() return id end, getLevel = function() return level end, getMana = function() return mana end,
		getMaxMana = function() return maxMana end, getHealth = function() return health or 100 end,
		addMana = function(_, n) added[id] = (added[id] or 0) + n end}
end
Chaos = {}
Game = {getPlayers = function() return players end}
local registered
GlobalEvent = function() local e = {}; e.interval = function() end; e.register = function() registered = true end; return e end
ChaosVigils = {applied = {[2] = {mana = 3000}}}
ChaosRift = {runOf = {[3] = {fx = {noMana = true}}}}
local costFn
ChaosSpellEvents = {set = function(kind, key, fn) if kind == "cost" and key == "manaflow" then costFn = fn end end}
ChaosManaFlow = nil
dofile("data/scripts/chaos/mana_flow.lua")
eq(registered, true, "think registered")
players = {mkPlayer(1, 800, 0, 4000), mkPlayer(2, 800, 0, 1000), mkPlayer(3, 800, 0, 4000), mkPlayer(4, 50, 0, 400),
	mkPlayer(5, 800, 4000, 4000), mkPlayer(6, 800, 0, 4000, 0)}
ChaosManaFlow.think()
eq(added[1], 53, "level 800 gets 53")
eq(added[2], 53, "a vigil holder gets it too")
eq(added[3], nil, "Parched Veins: nothing")
eq(added[4], nil, "level 50: nothing")
eq(added[5], nil, "full: nothing")
eq(added[6], nil, "dead: nothing")
local c, h = costFn(mkPlayer(2, 800, 0, 1000), "x", 1, 1, true, 1800, 7)
eq(c, 1000, "the handler caps with the reserved mana added back")
eq(h, 7, "health cost passes through")
eq((costFn(mkPlayer(1, 800, 0, 4000), "x", 1, 1, true, 400, 0)), 400, "an ordinary cost passes")

print(string.format("mana_flow_test: %d checks, %d failures", count, failures))
if failures > 0 then os.exit(1) end
