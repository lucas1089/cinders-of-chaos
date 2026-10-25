-- Run from the server/ folder: luajit tests/weather_test.lua (no engine needed; CI runs it with luajit and lua5.3)
-- Covers the weather (data/scripts/chaos/weather_core.lua, weather_config.lua, weather.lua; O208): the opcode (free:
-- not in the reference server, the reference client, ChaosOpcodes, the client modules), the base's numbers, the dice
-- (startup, the five-minute roll, a late tick), the strength picks, the areas (floors, boxes), the per-player "send only
-- on change" rule, and the glue against a mocked engine: login, hello, crossing into a cave and out, a weather change,
-- logout, the tick count of messages (what the base's 100 ms loop sent per minute against this), staff command.
dofile("data/scripts/chaos/chaos_constants.lua")
dofile("data/scripts/chaos/weather_core.lua")
local W = ChaosWeather
local cfg = dofile("data/scripts/chaos/weather_config.lua")

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

-- ------------------------------------------------------------------ opcode
eq(ChaosOpcodes.weather, 114, "opcode 114")
local seen = {}
for name, v in pairs(ChaosOpcodes) do
	ok(seen[v] == nil, "opcode " .. v .. " used twice (" .. name .. ", " .. tostring(seen[v]) .. ")")
	seen[v] = name
end
for _, v in ipairs({1, 67, 73, 89, 91, 92, 99, 106, 107, 136, 181, 201, 202, -- the reference server
		126, 127, -- its NPC scripts' currency opcodes
		140, 144, 145, 146, 210, 212, 213, 230, 246}) do -- the reference client's own ExtendedIds
	ok(ChaosOpcodes.weather ~= v, "not an opcode of the reference server or client: " .. v)
end
-- the other Chaos files: no other script or module names 114 as an opcode
local function readFile(path)
	local f = io.open(path, "r")
	if not f then return nil end
	local s = f:read("*a")
	f:close()
	return s
end
local ls = io.popen("ls ../client/overlay/modules 2>/dev/null")
local others = 0
for dir in ls:lines() do
	if dir ~= "game_chaosweather" then
		local ph = io.popen("ls ../client/overlay/modules/" .. dir .. "/*.lua 2>/dev/null")
		for file in ph:lines() do
			local s = readFile(file)
			if s and not file:find("_test.lua", 1, true) and (s:find("[Oo]pcode[%w_]*%s*=%s*114%f[%D]") or s:find("xtended[%w]*Opcode%(%s*114%f[%D]")) then
				others = others + 1
				print("opcode 114 in " .. file)
			end
		end
		ph:close()
	end
end
ls:close()
eq(others, 0, "no other client module on 114")
local clientMod = readFile("../client/overlay/modules/game_chaosweather/chaosweather.lua")
ok(clientMod ~= nil and clientMod:find("114", 1, true) ~= nil, "the client module listens on 114")

-- ------------------------------------------------------------------ config: the base's numbers
eq(cfg.startChance, 15, "base: 15% to start")
eq(cfg.stopChance, 10, "base: 10% to stop")
eq(cfg.rollMs, 300000, "base: every 5 minutes")
ok(cfg.tickMs >= 2000, "the glue ticks at most every 2 s (the base: every 100 ms)")
ok(cfg.fadeMs >= 500 and cfg.fadeMs <= 10000, "fade in a sane range")
local totalWeight, hasNormal = 0, false
for _, e in ipairs(cfg.intensities) do
	totalWeight = totalWeight + e.weight
	ok(e.level >= 1 and e.level <= 3, "level 1..3")
	if e.level == 2 then hasNormal = true end
end
eq(totalWeight, 100, "weights are percent")
ok(hasNormal, "level 2 (the base's look) exists")

-- ------------------------------------------------------------------ dice
local function seq(...)
	local list, i = {...}, 0
	return function(n)
		i = i + 1
		local v = list[i]
		if v == nil then error("rng ran out") end
		return math.min(v, n)
	end
end
local st = W.newState()
W.startup(st, cfg, seq(15, 50), 1000)
eq(st.raining, true, "startup roll 15 rains (<= 15)")
eq(st.intensity, 2, "weight roll 50 -> level 2 (20 for level 1, then 60)")
eq(st.nextRollAt, 1000 + 300000, "next roll in 5 min")
st = W.newState()
W.startup(st, cfg, seq(16), 1000)
eq(st.raining, false, "startup roll 16 stays dry")
eq(st.intensity, 0, "no strength when dry")
-- strength picks
eq(W.pickIntensity(cfg, seq(1)), 1, "roll 1 -> light")
eq(W.pickIntensity(cfg, seq(20)), 1, "roll 20 -> light")
eq(W.pickIntensity(cfg, seq(21)), 2, "roll 21 -> normal")
eq(W.pickIntensity(cfg, seq(80)), 2, "roll 80 -> normal")
eq(W.pickIntensity(cfg, seq(81)), 3, "roll 81 -> heavy")
eq(W.pickIntensity(cfg, seq(100)), 3, "roll 100 -> heavy")
eq(W.pickIntensity({intensities = {}}, seq(1)), 2, "no table: normal")
-- the roll: not before its time, one roll per interval
st = W.newState()
eq(W.roll(st, cfg, seq(1), 5000), false, "the first call only sets the timer")
eq(st.nextRollAt, 5000 + cfg.rollMs, "timer set")
eq(W.roll(st, cfg, seq(1), 5000 + cfg.rollMs - 1), false, "before the time: no dice")
eq(W.roll(st, cfg, seq(15, 50), 5000 + cfg.rollMs), true, "dry world, 15: starts to rain")
eq(st.raining, true, "raining"); eq(st.intensity, 2, "strength rolled")
eq(st.nextRollAt, 5000 + 2 * cfg.rollMs, "timer moves")
eq(W.roll(st, cfg, seq(11), st.nextRollAt), false, "rainy world, 11: keeps raining")
eq(st.raining, true, "still raining")
eq(W.roll(st, cfg, seq(10), st.nextRollAt), true, "rainy world, 10: stops")
eq(st.raining, false, "dry"); eq(st.intensity, 0, "strength cleared")
-- a late tick (the server stalled for an hour) rolls once
local late = st.nextRollAt + 3600000
eq(W.roll(st, cfg, seq(16), late), false, "late tick: one roll, nothing")
eq(st.nextRollAt, late + cfg.rollMs, "timer counts from now")
-- statistics of the base's chain: long run share of rainy rolls = 15 / (15 + 10) = 60%
local n, rainy = 20000, 0
math.randomseed(12345)
local sim = W.newState()
W.startup(sim, cfg, math.random, 0)
for i = 1, n do
	W.roll(sim, cfg, math.random, i * cfg.rollMs)
	if sim.raining then rainy = rainy + 1 end
end
ok(math.abs(rainy / n - 0.6) < 0.03, "rain share about 60% like the base chain: " .. rainy / n)
-- staff set
st = W.newState()
W.set(st, cfg, true, seq(), 9, 1000)
eq(st.raining, true, "set rain"); eq(st.intensity, 3, "level clamped to 3")
W.set(st, cfg, true, seq(), 0, 1000)
eq(st.intensity, 1, "level clamped to 1")
eq(st.nextRollAt, 1000 + cfg.rollMs, "dice go on from the set time")
W.set(st, cfg, false, seq(), nil, 2000)
eq(st.raining, false, "set clear")

-- ------------------------------------------------------------------ areas
eq(W.areaAt(cfg, {x = 100, y = 100, z = 7}).name, "surface", "floor 7 is the surface")
eq(W.areaAt(cfg, {x = 100, y = 100, z = 0}).name, "surface", "floor 0")
eq(W.areaAt(cfg, {x = 100, y = 100, z = 8}), nil, "floor 8 is underground")
eq(W.areaAt(cfg, {x = 100, y = 100, z = 15}), nil, "floor 15")
eq(W.areaAt(cfg, nil), nil, "no position")
local boxed = {areas = {
	{name = "marsh", kind = "rain", minZ = 7, maxZ = 7, box = {10, 10, 20, 20}},
	{name = "rest", kind = "rain", minZ = 0, maxZ = 7}}}
eq(W.areaAt(boxed, {x = 10, y = 20, z = 7}).name, "marsh", "box edge counts")
eq(W.areaAt(boxed, {x = 21, y = 20, z = 7}).name, "rest", "outside the box falls to the next area")
eq(W.areaAt(boxed, {x = 15, y = 15, z = 6}).name, "rest", "box is for floor 7 only")

-- ------------------------------------------------------------------ messages and the per-player rule
st = W.newState()
W.set(st, cfg, true, seq(), 2, 0)
local surface, cave = {x = 5, y = 5, z = 7}, {x = 5, y = 5, z = 9}
local m = W.message(st, cfg, surface)
eq(m.k, "rain", "rain on the surface"); eq(m.i, 2, "strength"); eq(m.f, cfg.fadeMs, "fade")
m = W.message(st, cfg, cave)
eq(m.k, "none", "none in a cave"); eq(m.i, nil, "no strength with none")
local sent = {}
ok(W.decide(sent, 1, st, cfg, surface) ~= nil, "first rain goes out")
eq(W.decide(sent, 1, st, cfg, surface), nil, "again: unchanged, nothing")
eq(W.decide(sent, 1, st, cfg, {x = 9, y = 9, z = 3}), nil, "walking about the surface: nothing")
m = W.decide(sent, 1, st, cfg, cave)
ok(m and m.k == "none", "into a cave: none")
eq(W.decide(sent, 1, st, cfg, cave), nil, "in the cave: nothing")
m = W.decide(sent, 1, st, cfg, surface)
ok(m and m.k == "rain", "out of the cave: rain again")
W.set(st, cfg, true, seq(), 3, 0)
m = W.decide(sent, 1, st, cfg, surface)
ok(m and m.i == 3, "a stronger rain is a change")
W.set(st, cfg, false, seq(), nil, 0)
m = W.decide(sent, 1, st, cfg, surface)
ok(m and m.k == "none", "the rain stops")
-- a dry world sends nothing to a fresh player, a forced one (hello) answers
sent = {}
eq(W.decide(sent, 2, st, cfg, surface), nil, "dry world: nothing to a new player")
ok(W.decide(sent, 2, st, cfg, surface, true) ~= nil, "force answers")
W.forget(sent, 2)
eq(sent[2], nil, "forget")
-- the message is tiny
W.set(st, cfg, true, seq(), 3, 0)
local keys = 0
for _ in pairs(W.message(st, cfg, surface)) do keys = keys + 1 end
eq(keys, 3, "three fields")

-- ------------------------------------------------------------------ the glue on a mocked engine
local events, sentOps, clock, scheduled = {}, {}, 1000000, {}
function CreatureEvent(name)
	local e = {name = name}
	function e:type() return self end
	function e:register() events[name] = self end
	return e
end
function GlobalEvent(name)
	local e = {name = name}
	function e:interval(ms) self.ms = ms end
	function e:type(t) self.kind = t end
	function e:register() events[name] = self end
	return e
end
local talkAction
function TalkAction(words)
	local e = {words = words}
	function e:separator() end
	function e:register() talkAction = self end
	return e
end
MESSAGE_INFO_DESCR = 1
os.mtime = function() return clock end
function addEvent(fn, ms) scheduled[#scheduled + 1] = {fn = fn, ms = ms} end
-- a tiny deterministic JSON (sorted keys) in place of the engine's
json = {
	encode = function(v)
		local function enc(x)
			if type(x) == "table" then
				local keys = {}
				for k in pairs(x) do keys[#keys + 1] = k end
				table.sort(keys)
				local parts = {}
				for _, k in ipairs(keys) do parts[#parts + 1] = '"' .. k .. '":' .. enc(x[k]) end
				return "{" .. table.concat(parts, ",") .. "}"
			elseif type(x) == "string" then
				return '"' .. x .. '"'
			end
			return tostring(x)
		end
		return enc(v)
	end,
	decode = function(str)
		local action = str:match('^{"action":"(%w+)"}$')
		if not action then error("bad json") end
		return {action = action}
	end
}
local byId = {}
local function newPlayer(id, z)
	local pl = {id = id, z = z, texts = {}, registered = {}}
	function pl:getId() return self.id end
	function pl:getPosition() return {x = 100, y = 100, z = self.z} end
	function pl:registerEvent(name) self.registered[#self.registered + 1] = name end
	function pl:sendExtendedOpcode(op, buffer) sentOps[#sentOps + 1] = {to = self.id, op = op, buffer = buffer} return true end
	function pl:getGroup() return {getAccess = function() return true end, getId = function() return 6 end} end
	function pl:sendTextMessage(_, text) self.texts[#self.texts + 1] = text end
	byId[id] = pl
	return pl
end
local a, b, c = newPlayer(1, 7), newPlayer(2, 7), newPlayer(3, 10)
local online = {a, b, c}
Game = {getPlayers = function() return online end}
function Player(id) return byId[id] end
local printed, realPrint = {}, print
print = function(s) printed[#printed + 1] = s end
ChaosWeather.state, ChaosWeather.sent = nil, nil
dofile("data/scripts/chaos/weather.lua")
print = realPrint
eq(#printed, 0, "loads quietly")
ok(events.ChaosWeatherThink and events.ChaosWeatherStartup and events.ChaosWeatherLogin and events.ChaosWeatherExtended
	and events.ChaosWeatherLogout and talkAction, "events and the staff command")
eq(events.ChaosWeatherThink.ms, cfg.tickMs, "tick interval from the config")
ok(events.ChaosWeatherThink.ms >= 2000, "not a per-100 ms event")
eq(events.ChaosWeatherStartup.kind, "startup", "startup event")

-- a rainy start; the tick tells the two surface players, not the one in the cave
math.randomseed(1)
local real = math.random
math.random = seq(15, 50) -- rains, level 2
events.ChaosWeatherStartup.onStartup()
math.random = real
eq(ChaosWeather.state.raining, true, "startup rains")
sentOps = {}
events.ChaosWeatherThink.onThink(cfg.tickMs)
eq(#sentOps, 2, "two players on the surface told")
for _, o in ipairs(sentOps) do
	eq(o.op, 114, "opcode 114")
	eq(o.buffer, '{"action":"set","data":{"f":' .. cfg.fadeMs .. ',"i":2,"k":"rain"}}', "payload")
end
sentOps = {}
for i = 1, 20 do events.ChaosWeatherThink.onThink(cfg.tickMs) end
eq(#sentOps, 0, "20 more ticks with nothing changed: no message")
-- the cave player walks out; the surface player walks in
c.z = 7
a.z = 12
events.ChaosWeatherThink.onThink(cfg.tickMs)
eq(#sentOps, 2, "two crossings, two messages")
local by = {}
for _, o in ipairs(sentOps) do by[o.to] = o.buffer end
ok(by[3] and by[3]:find('"rain"', 1, true), "the one who came out gets rain")
ok(by[1] and by[1]:find('"none"', 1, true), "the one who went in gets none")
-- login: registers events, a try after 1.5 s that forces the state
sentOps = {}
local d = newPlayer(4, 6)
online[#online + 1] = d
events.ChaosWeatherLogin.onLogin(d)
eq(table.concat(d.registered, ","), "ChaosWeatherExtended,ChaosWeatherLogout", "login registers")
eq(#scheduled, 1, "one delayed send"); eq(scheduled[1].ms, 1500, "1.5 s")
scheduled[1].fn()
eq(#sentOps, 1, "login send"); ok(sentOps[1].buffer:find('"rain"', 1, true), "rain on login")
-- hello answers even when nothing changed
sentOps = {}
events.ChaosWeatherExtended.onExtendedOpcode(d, 114, '{"action":"hello"}')
eq(#sentOps, 1, "hello answered")
events.ChaosWeatherExtended.onExtendedOpcode(d, 115, '{"action":"hello"}')
events.ChaosWeatherExtended.onExtendedOpcode(d, 114, '{"action":"other"}')
events.ChaosWeatherExtended.onExtendedOpcode(d, 114, 'not json')
eq(#sentOps, 1, "other opcode, action or junk: ignored")
-- the weather changes at the roll time: everyone on the surface hears once
sentOps = {}
clock = clock + 400000
math.random = seq(10) -- the stop roll
events.ChaosWeatherThink.onThink(cfg.tickMs)
math.random = real
eq(ChaosWeather.state.raining, false, "the roll stopped the rain")
eq(#sentOps, 3, "b, c, d were in rain: told it stopped; a is in a cave and already has none")
for _, o in ipairs(sentOps) do ok(o.buffer:find('"none"', 1, true) ~= nil, "none") end
-- logout forgets
events.ChaosWeatherLogout.onLogout(b)
eq(ChaosWeather.sent[b:getId()], nil, "logout forgets")
-- disabled: no sends
ChaosWeatherConfig.enabled = false
sentOps = {}
ChaosWeather.state.raining, ChaosWeather.state.intensity = true, 1
events.ChaosWeatherThink.onThink(cfg.tickMs)
events.ChaosWeatherExtended.onExtendedOpcode(d, 114, '{"action":"hello"}')
eq(#sentOps, 0, "switched off: nothing")
ChaosWeatherConfig.enabled = true
-- an error inside a tick is caught and logged
Game.getPlayers = function() error("boom") end
printed = {}
print = function(s) printed[#printed + 1] = s end
eq(events.ChaosWeatherThink.onThink(cfg.tickMs), true, "error: still true")
print = realPrint
ok(printed[1] and printed[1]:find("boom", 1, true) ~= nil, "error logged")
Game.getPlayers = function() return online end
-- staff command
sentOps = {}
talkAction.onSay(a, "/weather", "rain 3")
eq(ChaosWeather.state.intensity, 3, "/weather rain 3")
ok(a.texts[#a.texts]:find("rain 3", 1, true) ~= nil, "staff gets the state")
ok(#sentOps >= 1, "players told at once")
talkAction.onSay(a, "/weather", "clear")
eq(ChaosWeather.state.raining, false, "/weather clear")
talkAction.onSay(a, "/weather", "info")
ok(a.texts[#a.texts]:find("clear", 1, true) ~= nil, "/weather info")

-- a player below the staff group changes nothing and sees nothing
local plain = newPlayer(9, 7)
plain.getGroup = function() return {getAccess = function() return false end, getId = function() return 1 end} end
local before = ChaosWeather.state.raining
eq(talkAction.onSay(plain, "/weather", "rain 3"), false, "a player: refused")
eq(ChaosWeather.state.raining, before, "a player changed nothing")
eq(#plain.texts, 0, "a player gets no text")

-- ------------------------------------------------------------------ load: what the base's loop cost against this
-- 200 players in a rain of one hour: the base sent an effect per player per 100 ms (two effects, a distance effect and
-- a magic effect, each their own packet) = 200 * 36000 * 2 packets; here one message per player when it changes.
local players = {}
for i = 1, 200 do players[i] = {id = i, z = 7} end
local state, sentTab, msgs = W.newState(), {}, 0
W.set(state, cfg, true, seq(), 2, 0)
for tick = 1, 3600000 / cfg.tickMs do
	for _, p in ipairs(players) do
		if W.decide(sentTab, p.id, state, cfg, {x = 1, y = 1, z = p.z}) then msgs = msgs + 1 end
	end
end
eq(msgs, 200, "an hour of steady rain for 200 players: 200 messages in all")

if fails > 0 then
	print(string.format("weather: %d of %d checks failed", fails, checks))
	os.exit(1)
end
print(string.format("weather: all %d checks passed", checks))
