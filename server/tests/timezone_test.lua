-- Run from the server/ folder: luajit tests/timezone_test.lua (CI runs it with LuaJIT and Lua 5.3).
-- The clock zone guard (data/scripts/chaos/timezone_core.lua, timezone_config.lua, timezone.lua; O439): the UTC offset
-- from os.time and os.date("!*t") on injected clocks (no real zone needed), the startup line, the loud warning for a
-- wrong offset, and that nothing here can stop the server (a broken clock gives a warning, a failing check is caught).
local realPrint = print
local checks, fails = 0, 0
local function ok(cond, what)
	checks = checks + 1
	if not cond then
		fails = fails + 1
		realPrint("FAIL " .. tostring(what))
	end
end
local function eq(a, b, what)
	ok(a == b, (what or "check") .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end

-- a fake clock for a machine `off` minutes east of UTC, with an optional daylight saving window [dstFrom, dstTo) in
-- unix time that adds `dstMin` minutes. time(t) is os.time: fields read as local time; date is os.date.
local function daysFromCivil(y, m, d)
	if m <= 2 then
		y = y - 1
	end
	local era = math.floor(y / 400)
	local yoe = y - era * 400
	local mp = (m + 9) % 12
	local doy = math.floor((153 * mp + 2) / 5) + d - 1
	local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
	return era * 146097 + doe - 719468
end
local function fakeClock(off, dstFrom, dstTo, dstMin)
	local function localOffset(t)
		if dstFrom and t >= dstFrom and t < dstTo then
			return (off + dstMin) * 60, true
		end
		return off * 60, false
	end
	local clock = {}
	function clock.date(fmt, t)
		if fmt == "!*t" then
			local d = os.date("!*t", t)
			d.isdst = false
			return d
		elseif fmt == "*t" then
			local o, dst = localOffset(t)
			local d = os.date("!*t", t + o)
			d.isdst = dst
			return d
		end
		local o = localOffset(t)
		return os.date("!" .. fmt, t + o)
	end
	function clock.time(f)
		if f == nil then
			return 1700000000
		end
		local utcAsIf = daysFromCivil(f.year, f.month, f.day) * 86400 + f.hour * 3600 + f.min * 60 + f.sec
		local o = (off + ((f.isdst and dstMin) or 0)) * 60
		return utcAsIf - o
	end
	return clock
end

dofile("data/scripts/chaos/timezone_core.lua")
local T = ChaosTimezone
ok(T ~= nil, "timezone_core.lua defines ChaosTimezone")
local cfg = dofile("data/scripts/chaos/timezone_config.lua")
eq(cfg.zone, "America/Sao_Paulo", "the expected zone")
eq(cfg.offsetMinutes, -180, "the expected offset is UTC-3")

-- the launch: Fri 2026-11-20 15:00 Brasilia = 18:00 UTC
local LAUNCH_UTC = daysFromCivil(2026, 11, 20) * 86400 + 18 * 3600

-- ---------------------------------------------------------------- the offset
eq(T.offsetMinutes(LAUNCH_UTC, fakeClock(-180)), -180, "a Brasilia machine: -180")
eq(T.offsetMinutes(LAUNCH_UTC, fakeClock(0)), 0, "a UTC machine: 0")
eq(T.offsetMinutes(LAUNCH_UTC, fakeClock(330)), 330, "a +05:30 machine: 330")
eq(T.offsetMinutes(LAUNCH_UTC, fakeClock(-480)), -480, "a -08:00 machine: -480")
-- daylight saving: the local flag is used for both reads
local jul = daysFromCivil(2026, 7, 1) * 86400 + 12 * 3600
eq(T.offsetMinutes(jul, fakeClock(60, jul - 86400, jul + 86400, 60)), 120, "summer time counts: +01:00 plus one hour is 120")
eq(T.offsetMinutes(jul + 365 * 86400, fakeClock(60, jul - 86400, jul + 86400, 60)), 60, "outside the window: 60")
-- no `now`: the clock's own time is used
eq(T.offsetMinutes(nil, fakeClock(-180)), -180, "now defaults to the clock's time")
-- the real clock works and gives a whole number of minutes
local real = T.offsetMinutes()
ok(type(real) == "number" and real == math.floor(real) and math.abs(real) <= 14 * 60 + 59, "the real clock: " .. tostring(real))
-- a broken clock gives nil, never an error
eq(T.offsetMinutes(1, {time = function() error("boom") end, date = function() error("boom") end}), nil, "a clock that raises: nil")
eq(T.offsetMinutes(1, {time = os.time, date = function() return nil end}), nil, "a clock with no date table: nil")

-- ---------------------------------------------------------------- labels and the decision
eq(T.label(-180), "UTC-03:00", "label -180")
eq(T.label(0), "UTC+00:00", "label 0")
eq(T.label(330), "UTC+05:30", "label 330")
eq(T.label(-570), "UTC-09:30", "label -570")
eq(T.label(nil), "UTC?", "label nil")
ok(T.isExpected(cfg, -180), "-180 is expected")
ok(not T.isExpected(cfg, 0), "0 is not expected")
ok(not T.isExpected(cfg, nil), "an unknown offset is not expected")
ok(not T.isExpected(nil, -180), "no config is not expected")

-- ---------------------------------------------------------------- the startup lines
local r = T.startup(cfg, LAUNCH_UTC, fakeClock(-180))
ok(r.ok, "Brasilia machine: ok")
eq(#r.lines, 1, "ok: one line")
ok(r.lines[1]:find("local time 2026-11-20 15:00:00", 1, true) ~= nil, "the line has the local time: " .. r.lines[1])
ok(r.lines[1]:find("UTC-03:00", 1, true) ~= nil and r.lines[1]:find("America/Sao_Paulo", 1, true) ~= nil,
	"the line has the offset and the expected zone: " .. r.lines[1])
ok(r.lines[1]:find("WARNING", 1, true) == nil, "no warning when the zone is right")

r = T.startup(cfg, LAUNCH_UTC, fakeClock(0))
ok(not r.ok, "UTC machine: not ok")
eq(#r.lines, 2, "wrong: the info line and the warning")
ok(r.lines[1]:find("local time 2026-11-20 18:00:00", 1, true) ~= nil and r.lines[1]:find("UTC+00:00", 1, true) ~= nil,
	"the info line still tells the real local time: " .. r.lines[1])
ok(r.lines[2]:find("TIMEZONE WARNING", 1, true) ~= nil, "loud warning: " .. r.lines[2])
ok(r.lines[2]:find("UTC+00:00", 1, true) ~= nil and r.lines[2]:find("UTC-03:00", 1, true) ~= nil, "the warning names both offsets")
ok(r.lines[2]:find("chaos-ctl.sh timezone set", 1, true) ~= nil and r.lines[2]:find("restart", 1, true) ~= nil,
	"the warning names the fix and the restart")
ok(not r.lines[1]:find("\n", 1, true) and not r.lines[2]:find("\n", 1, true), "one line each")

-- a clock that cannot tell: a warning, no raise
r = T.startup(cfg, 1, {time = function() error("boom") end, date = function() error("boom") end})
ok(not r.ok and #r.lines == 2 and r.lines[2]:find("TIMEZONE WARNING", 1, true) ~= nil, "a broken clock warns")
ok(r.lines[1]:find("local time ?", 1, true) ~= nil, "a broken clock prints ? for the time")
-- a broken config: a warning, no raise
r = T.startup(nil, LAUNCH_UTC, fakeClock(-180))
ok(not r.ok and #r.lines == 2, "no config warns")
r = T.startup({zone = "X"}, LAUNCH_UTC, fakeClock(-180))
ok(not r.ok, "a config without an offset warns")
-- the real clock path runs
r = T.startup(cfg)
ok(type(r.ok) == "boolean" and #r.lines >= 1, "the real clock path runs")

-- ---------------------------------------------------------------- the engine file: never stops the server
local printed = {}
local registered = 0
_G.print = function(s)
	printed[#printed + 1] = tostring(s)
end
local handler
_G.GlobalEvent = function(name)
	local ev = {name = name}
	function ev:register()
		registered = registered + 1
	end
	setmetatable(ev, {__newindex = function(t, k, v)
		rawset(t, k, v)
		if k == "onStartup" then
			handler = v
		end
	end})
	return ev
end
dofile("data/scripts/chaos/timezone.lua")
eq(registered, 1, "timezone.lua registers one startup event")
ok(type(handler) == "function", "it has an onStartup handler")
local res = handler()
eq(res, true, "onStartup returns true")
ok(#printed >= 1 and printed[1]:find(">> Timezone:", 1, true) == 1, "onStartup prints the zone line: " .. tostring(printed[1]))
-- a core that raises is caught and the start goes on
local saved = ChaosTimezone.startup
ChaosTimezone.startup = function() error("boom") end
printed = {}
eq(handler(), true, "a failing check still returns true")
ok(#printed == 1 and printed[1]:find("failed to run", 1, true) ~= nil, "and says so: " .. tostring(printed[1]))
ChaosTimezone.startup = saved

_G.print = realPrint
print(string.format("timezone_test: %d checks, %d failures", checks, fails))
if fails > 0 then
	os.exit(1)
end
