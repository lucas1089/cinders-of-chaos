-- Run from the server/ folder: luajit tests/respawn_test.lua (no engine needed; CI runs it with luajit and lua5.3)
-- Covers the dynamic respawn (data/scripts/chaos/respawn_core.lua, respawn.lua): the percent per hunter count, the
-- hunter counts (radius, floors, one per IP), the busy zones (grid cells, margin, busiest applied last), the plan
-- (nothing when nothing changed, reset then zones, back to 100 when the hunters leave, the global percent) and the
-- glue against a mocked engine: who counts as a hunter, the engine calls, a missing engine function, errors.
dofile("data/scripts/chaos/chaos_constants.lua")
dofile("data/scripts/chaos/respawn_core.lua")
local R = ChaosRespawn
local cfg = dofile("data/scripts/chaos/respawn_config.lua")

local fails, checks = 0, 0
local function ok(cond, what)
	checks = checks + 1
	if not cond then
		fails = fails + 1
		print("FAIL " .. what)
	end
end
local function eq(a, b, what)
	ok(a == b, what .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end
local function copy(t, over)
	local o = {}
	for k, v in pairs(t) do
		o[k] = v
	end
	for k, v in pairs(over or {}) do
		o[k] = v
	end
	return o
end

-- ------------------------------------------------------------------ config
ok(cfg.enabled, "on by default")
ok(cfg.minPercent >= 10 and cfg.minPercent <= 100, "minPercent within the engine's 10-1000")
eq(cfg.globalPercent, 100, "the stock spawntimes when nobody hunts")
ok(cfg.tickSeconds >= 5, "not every second")
ok(cfg.margin >= 0 and cfg.cellSize >= 8, "zone size")

-- ------------------------------------------------------------------ percent
eq(R.percentFor(0, cfg), 100, "nobody")
eq(R.percentFor(1, cfg), 100, "one hunter: stock")
eq(R.percentFor(2, cfg), 85, "two")
eq(R.percentFor(3, cfg), 70, "three")
eq(R.percentFor(4, cfg), 55, "four")
eq(R.percentFor(5, cfg), 50, "five: the floor")
eq(R.percentFor(40, cfg), 50, "many: the floor")
local half = copy(cfg, {globalPercent = 80})
eq(R.percentFor(0, half), 80, "global percent everywhere")
eq(R.percentFor(5, half), 40, "global percent times the busy percent")
eq(R.percentFor(5, copy(cfg, {globalPercent = 10})), 10, "never under 10 (the engine clamps there too)")
local last = 101
for n = 0, 12 do
	local p = R.percentFor(n, cfg)
	ok(p <= last, "never slower with more hunters (" .. n .. ")")
	last = p
end

-- ------------------------------------------------------------------ counts
local function h(x, y, z, ip)
	return {x = x, y = y, z = z or 7, ip = ip}
end
local c = R.counts({h(100, 100, 7, 1), h(110, 100, 7, 2), h(111, 100, 7, 3), h(100, 100, 8, 4)}, cfg)
eq(c[1], 2, "radius 10 includes 10 sqm away, not 11")
eq(c[2], 3, "the middle one sees both")
eq(c[3], 2, "11 sqm from the first")
eq(c[4], 1, "another floor is alone")
c = R.counts({h(100, 100, 7, 5), h(101, 100, 7, 5), h(102, 100, 7, 6)}, cfg)
eq(c[1], 2, "two characters on one IP count once")
c = R.counts({h(100, 100, 7, 5), h(101, 100, 7, 5)}, copy(cfg, {onePerIp = false}))
eq(c[1], 2, "onePerIp off: both count")
c = R.counts({h(100, 100, 7, 0), h(101, 100, 7, 0)}, cfg)
eq(c[1], 2, "unknown IP (0): every character counts")
c = R.counts({h(100, 100), h(100, 110), h(110, 110)}, cfg)
eq(c[1], 3, "diagonal 10/10 is within the radius")

-- ------------------------------------------------------------------ zones
local zs = R.zones({h(100, 100, 7, 1)}, cfg)
eq(#zs, 0, "one hunter: no zone")
zs = R.zones({h(100, 100, 7, 1), h(103, 102, 7, 2)}, cfg)
eq(#zs, 1, "two together: one zone")
eq(zs[1].percent, 85, "zone percent")
eq(zs[1].x0, 96 - 8, "cell 6 (96-111) minus the margin")
eq(zs[1].x1, 111 + 8, "cell end plus the margin")
eq(zs[1].y0, 96 - 8, "y start")
eq(zs[1].z, 7, "floor")
-- a party of four across two cells and a pair elsewhere: the busiest zones come last
zs = R.zones({h(110, 100, 7, 1), h(112, 100, 7, 2), h(114, 101, 7, 3), h(116, 101, 7, 4),
	h(300, 300, 7, 5), h(302, 300, 7, 6)}, cfg)
eq(#zs, 3, "two cells of the party, one of the pair")
eq(zs[1].percent, 85, "the pair first")
eq(zs[#zs].percent, 55, "the party of four last")
for i = 2, #zs do
	ok(zs[i - 1].percent >= zs[i].percent, "sorted busiest last")
end
local again = R.zones({h(116, 101, 7, 4), h(114, 101, 7, 3), h(112, 100, 7, 2), h(110, 100, 7, 1),
	h(302, 300, 7, 6), h(300, 300, 7, 5)}, cfg)
eq(R.signature(again, cfg), R.signature(zs, cfg), "the order of the players does not matter")

-- ------------------------------------------------------------------ plan
local state = {}
eq(#R.plan(state, {}, cfg), 0, "start, nobody: nothing to do (the engine starts at 100)")
local calls = R.plan(state, zs, cfg)
eq(#calls, 1 + #zs, "reset plus one per zone")
eq(calls[1].percent, 100, "reset to the global percent")
eq(calls[1].from, nil, "reset covers every spawn")
eq(calls[#calls].percent, 55, "busiest last")
eq(calls[2].from.x, zs[1].x0, "zone box from")
eq(calls[2].to.y, zs[1].y1, "zone box to")
eq(#R.plan(state, again, cfg), 0, "same zones next tick: nothing")
calls = R.plan(state, {}, cfg)
eq(#calls, 1, "hunters left: one reset")
eq(calls[1].percent, 100, "back to the spawntime")
eq(#R.plan(state, {}, cfg), 0, "and then nothing")
calls = R.plan(state, {}, half)
eq(#calls, 1, "global percent changed: one call")
eq(calls[1].percent, 80, "global percent")

-- ------------------------------------------------------------------ glue (respawn.lua) against a mocked engine
TILESTATE_PROTECTIONZONE, CONDITION_INFIGHT = 1, 2
local globals = {}
function GlobalEvent(name)
	local o = {name = name}
	function o:interval(ms) self.ms = ms end
	function o:register() globals[name] = self end
	return o
end
function Position(x, y, z)
	return {x = x, y = y, z = z}
end
local pz = {}
function Tile(pos)
	return {hasFlag = function(_, flag) return flag == TILESTATE_PROTECTIONZONE and pz[pos.x .. ":" .. pos.y] == true end}
end
local function newPlayer(x, y, ip, opts)
	opts = opts or {}
	local pl = {}
	function pl:getPosition() return {x = x, y = y, z = 7} end
	function pl:getIp() return ip end
	function pl:hasCondition(cond) return cond == CONDITION_INFIGHT and opts.fight ~= false end
	function pl:getGroup() return {getAccess = function() return opts.staff == true end} end
	return pl
end
local players = {}
local engine = {}
Game = {getPlayers = function() return players end}
local printed = {}
local realPrint = print
print = function(s) printed[#printed + 1] = s end
ChaosRespawn.state = nil
dofile("data/scripts/chaos/respawn.lua")
print = realPrint
eq(#printed, 0, "loads quietly")
local tick = globals.ChaosRespawnTick
ok(tick ~= nil, "the tick is registered")
eq(tick.ms, cfg.tickSeconds * 1000, "tick interval")

-- without engine patch 0022: one log line, nothing else
print = function(s) printed[#printed + 1] = s end
eq(tick.onThink(20000), true, "think returns true")
tick.onThink(20000)
print = realPrint
eq(#printed, 1, "missing engine function logged once")
ok(printed[1] and printed[1]:find("0022", 1, true) ~= nil, "the log names the patch")

-- with the engine function
Game.setSpawnIntervalPercent = function(percent, from, to)
	engine[#engine + 1] = {percent = percent, from = from, to = to}
	return 1
end
players = {newPlayer(100, 100, 1), newPlayer(102, 100, 2), newPlayer(104, 101, 3, {fight = false}),
	newPlayer(101, 101, 4, {staff = true}), newPlayer(103, 103, 5)}
pz["103:103"] = true
eq(#ChaosRespawn.collect(ChaosRespawnConfig), 2, "idle, staff and protection zone players do not count")
tick.onThink(20000)
eq(#engine, 2, "reset and one zone")
eq(engine[1].percent, 100, "reset first")
eq(engine[1].from, nil, "reset is map wide")
eq(engine[2].percent, 85, "two hunters: 85%")
eq(engine[2].from.z, 7, "zone floor")
engine = {}
tick.onThink(20000)
eq(#engine, 0, "nothing changed: no engine call")
players = {}
tick.onThink(20000)
eq(#engine, 1, "they left: one reset")
eq(engine[1].percent, 100, "back to 100")
-- switched off in the config: back to 100 once, then nothing
engine = {}
players = {newPlayer(100, 100, 1), newPlayer(102, 100, 2)}
tick.onThink(20000)
eq(#engine, 2, "busy again")
ChaosRespawnConfig.enabled = false
engine = {}
tick.onThink(20000)
eq(#engine, 1, "off: one reset")
eq(engine[1].percent, 100, "off: stock spawntimes")
engine = {}
tick.onThink(20000)
eq(#engine, 0, "off: then nothing")
ChaosRespawnConfig.enabled = true
-- an engine error is caught and logged, the event still returns true
Game.getPlayers = function() error("boom") end
printed = {}
print = function(s) printed[#printed + 1] = s end
local okRet = tick.onThink(20000)
print = realPrint
eq(okRet, true, "error: still true")
ok(printed[1] and printed[1]:find("boom", 1, true) ~= nil, "error logged")

if fails > 0 then
	print(string.format("respawn: %d of %d checks failed", fails, checks))
	os.exit(1)
end
print(string.format("respawn: all %d checks passed", checks))
