-- The clock zone guard (O439): pure logic. Engine file: timezone.lua; numbers: timezone_config.lua; tests: tests/timezone_test.lua;
-- overview: server/README.md "Timezone guard (O439)".
--
-- The game reads the machine's LOCAL time (weekend, Founder Pack, Season 1, the creator launch bonus, the 06:00 save). The
-- launch is Fri 2026-11-20 15:00 Brasilia time (UTC-3), so a VPS left in UTC starts all of it 3 hours late. At the start the
-- server prints one line with the local time and the UTC offset, and a loud warning line when the offset is not the
-- expected one. It never stops the server: a wrong zone is the owner's to fix (chaos-ctl.sh timezone set, then a restart).
-- The offset comes from os.time and os.date("!*t"); a clock can be injected ({time = fn, date = fn}) so the tests need no
-- real zone. Lua 5.1 / LuaJIT and Lua 5.3 compatible.

ChaosTimezone = ChaosTimezone or {}
local T = ChaosTimezone

local function realClock()
	return {time = os.time, date = os.date}
end

-- minutes east of UTC at `now` (default: the clock's time), or nil when the clock cannot tell. The local fields read back
-- as local time give `now`; the UTC fields read back as local time give `now - offset`; the difference is the offset. The
-- UTC fields take the local daylight saving flag so that both reads use the same rule.
function T.offsetMinutes(now, clock)
	clock = clock or realClock()
	local ok, minutes = pcall(function()
		local t = now or clock.time()
		local l = clock.date("*t", t)
		local u = clock.date("!*t", t)
		if type(l) ~= "table" or type(u) ~= "table" then
			return nil
		end
		u.isdst = l.isdst
		local diff = clock.time(l) - clock.time(u)
		return math.floor(diff / 60 + 0.5)
	end)
	if ok and type(minutes) == "number" then
		return minutes
	end
	return nil
end

-- "UTC-03:00", "UTC+00:00", "UTC+05:30"; "UTC?" for nil
function T.label(minutes)
	if type(minutes) ~= "number" then
		return "UTC?"
	end
	local sign = minutes < 0 and "-" or "+"
	local m = math.abs(minutes)
	return string.format("UTC%s%02d:%02d", sign, math.floor(m / 60), m % 60)
end

-- true when the offset is the expected one (a missing config or offset: false)
function T.isExpected(cfg, minutes)
	return type(cfg) == "table" and type(minutes) == "number" and minutes == cfg.offsetMinutes
end

-- what the server prints at the start: {ok = bool, lines = {text, ...}}. Never raises.
function T.startup(cfg, now, clock)
	clock = clock or realClock()
	local okCfg = type(cfg) == "table" and type(cfg.offsetMinutes) == "number"
	local zone = okCfg and cfg.zone or "?"
	local minutes = T.offsetMinutes(now, clock)
	local okTime, stamp = pcall(clock.date, "%Y-%m-%d %H:%M:%S", now or clock.time())
	if not okTime then
		stamp = "?"
	end
	local expected = okCfg and T.label(cfg.offsetMinutes) or "UTC?"
	local lines = {
		string.format(">> Timezone: local time %s, %s (expected %s, %s)", stamp, T.label(minutes), zone, expected)
	}
	local ok = T.isExpected(cfg, minutes)
	if not ok then
		lines[#lines + 1] = string.format(
			">> TIMEZONE WARNING: this machine is at %s, the game needs %s (%s). The Founder Pack, Season 1, the creator launch bonus, " ..
			"the weekend ritual and the 06:00 save all use local time and will run at the wrong hour. " ..
			"Fix: chaos-ctl.sh timezone set (admin app: Comandos > Acoes rapidas > Saude e espaco), then restart the game server.",
			T.label(minutes), expected, zone)
	end
	return {ok = ok, lines = lines}
end
