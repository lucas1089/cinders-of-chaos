-- Run from the server/ folder: luajit tests/mana_flow_test.lua (and lua5.3; CI runs both)
-- The mana flow (server/README.md "Mana flow"): regeneration by level; fixed spell costs (no cap, no percent of the
-- maximum mana; owner 2026-10-21, server/README.md "Fixed spell costs"). Beta report:
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

-- fixed spell costs (owner 2026-10-21, server/README.md "Fixed spell costs"): no cap, no rule of the level or the pool
eq(F.capCost, nil, "no cost cap (a cost never depends on the maximum mana)")
eq(C.cap, nil, "no cap numbers")
local function readAll(path)
	local f = assert(io.open(path, "r"))
	local s = f:read("*a")
	f:close()
	return s
end
-- every Chaos spell has one flat mana number; none costs a percentage of the maximum mana
local xml = readAll("data/spells/chaos/spells_chaos.xml"):gsub("<!%-%-.-%-%->", "")
local spells = 0
for tag in xml:gmatch("<instant%s[^>]*>") do
	spells = spells + 1
	local name = tag:match('name="([^"]*)"') or "?"
	eq(tag:find("manapercent", 1, true), nil, name .. ": no manapercent")
	eq(tag:match(' mana="(%d+)"') ~= nil, true, name .. ": a fixed mana number")
end
eq(spells > 100, true, "the Chaos spells were read")
eq(readAll("data/spells/chaos/spells_chaos.xml"):match('name="Shadow Mend"[^>]* mana="(%d+)"'), "25",
	"Shadow Mend: 25 mana at every level (40 until 2026-10-22, 2% of the maximum mana before)")
-- the stock spells the classes keep: a number in the mana column (stock_spells.csv, spell_timings.csv)
for _, csv in ipairs({"data/spells/stock_spells.csv", "data/spells/spell_timings.csv"}) do
	local header, col
	for line in readAll(csv):gmatch("[^\n]+") do
		if not header then
			header = true
			local i = 0
			for field in line:gmatch("[^,]+") do
				i = i + 1
				if field == "mana" then col = i end
			end
			eq(col ~= nil, true, csv .. ": a mana column")
		else
			local i, value = 0, nil
			for field in (line .. ","):gmatch("([^,]*),") do
				i = i + 1
				if i == col then value = field end
			end
			eq(value == "" or value:match("^%d+$") ~= nil, true, csv .. ": a flat mana number in " .. line:sub(1, 40))
		end
	end
end

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
local costFn, removed = nil, nil
ChaosSpellEvents = {set = function(kind, key, fn) if kind == "cost" then costFn = fn end end,
	remove = function(kind, key) removed = kind .. ":" .. key end}
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
eq(costFn, nil, "no spell cost handler: a cost is the spell's fixed number")
eq(removed, "cost:manaflow", "the old cap handler is dropped (it survives a /reload otherwise)")

-- thinkPlayer (O199): the same amount as regenAmount for every level, mana, dead and Parched Veins case, cached per level
do
	local function fake(level, mana, maxMana, hp)
		return {getLevel = function() return level end, getMana = function() return mana end,
			getMaxMana = function() return maxMana end, getHealth = function() return hp end, getId = function() return 7 end}
	end
	for _, lv in ipairs({1, 99, 100, 150, 200, 799, 800, 1000, 1500}) do
		for _, st in ipairs({{0, 4000}, {3990, 4000}, {4000, 4000}, {10, 5}}) do
			for _, hp in ipairs({100, 0}) do
				for _, nm in ipairs({false, true}) do
					for pass = 1, 2 do -- the second pass answers from the cache
						eq(F.thinkPlayer(fake(lv, st[1], st[2], hp), function() return nm end),
							F.regenAmount(lv, st[1], st[2], nm, hp <= 0), "thinkPlayer " .. lv .. "/" .. st[1] .. "/" .. hp .. "/" .. tostring(nm))
					end
				end
			end
		end
	end
	eq(F.thinkPlayer(fake(800, 0, 4000, 100)), 53, "no Parched lookup given")
	local looked = false
	eq(F.thinkPlayer(fake(800, 4000, 4000, 100), function() looked = true end), 0, "full pool")
	eq(looked, false, "a full pool reads nothing else")
	F.clearCache()
	eq(F.thinkPlayer(fake(800, 0, 4000, 100)), 53, "after clearCache")
end

print(string.format("mana_flow_test: %d checks, %d failures", count, failures))
if failures > 0 then os.exit(1) end
