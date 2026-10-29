-- The Weekend Ritual: pure logic (no engine calls), shared by weekend.lua and server/tests/weekend_test.lua.
-- Config: weekend_config.lua. Overview: server/README.md "Weekend Ritual (O321)".
--   clock     K.offset(cfg, t), K.parts(t, off), K.stamp(t, off)           civil time by arithmetic, no os.date
--   window    K.window(cfg, t, off) -> {active, startsAt, endsAt, key, theme, themeKey, nextStart, nextKey, ...}
--   theme     K.themeAt(cfg, startsAt, off), K.mults(cfg, w, seasonal)
--   highlight K.highlightAt(cfg, w, off)
--   due       K.due(cfg, t, off, done) -> the announcements and the highlight start that are due now
--   preview   K.preview(cfg, t, off) -> the login line before the start, or nil
--   calendar  K.calendar(cfg, t, off, days), K.upcoming(cfg, t, off, n)
--   skill     K.scaleTries(tries, mult, rand)
--   check     K.validate(cfg) -> list of problems (empty: fine)
-- Weekday numbers follow os.date("*t").wday: 1 = Sunday ... 7 = Saturday. `off` is seconds east of UTC.
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.

ChaosWeekendCore = ChaosWeekendCore or {}
local K = ChaosWeekendCore

local floor = math.floor

local DAY, WEEK = 86400, 604800

local function num(v, default)
	v = tonumber(v)
	if not v or v ~= v then
		return default
	end
	return v
end

-- ---------------------------------------------------------------- the clock
-- days since 1970-01-01 of a civil date (proleptic Gregorian) and back
function K.daysFromCivil(y, m, d)
	if m <= 2 then
		y = y - 1
	end
	local era = floor(y / 400)
	local yoe = y - era * 400
	local mp = (m + 9) % 12
	local doy = floor((153 * mp + 2) / 5) + d - 1
	local doe = yoe * 365 + floor(yoe / 4) - floor(yoe / 100) + doy
	return era * 146097 + doe - 719468
end

function K.civilFromDays(z)
	z = z + 719468
	local era = floor(z / 146097)
	local doe = z - era * 146097
	local yoe = floor((doe - floor(doe / 1460) + floor(doe / 36524) - floor(doe / 146096)) / 365)
	local y = yoe + era * 400
	local doy = doe - (365 * yoe + floor(yoe / 4) - floor(yoe / 100))
	local mp = floor((5 * doy + 2) / 153)
	local d = doy - floor((153 * mp + 2) / 5) + 1
	local m = mp < 10 and mp + 3 or mp - 9
	if m <= 2 then
		y = y + 1
	end
	return y, m, d
end

-- seconds east of UTC of the clock the schedule follows: the fixed offset of the config, else the server's own zone at t
function K.offset(cfg, t)
	local h = cfg.utcOffsetHours
	if type(h) == "number" then
		return floor(h * 3600)
	end
	t = t or os.time()
	local u = os.date("!*t", t)
	u.isdst = false
	local l = os.date("*t", t)
	l.isdst = false
	return os.time(l) - os.time(u)
end

-- the local civil time of t
function K.parts(t, off)
	local L = floor(t) + (off or 0)
	local days = floor(L / DAY)
	local sod = L - days * DAY
	local y, m, d = K.civilFromDays(days)
	return {year = y, month = m, day = d, hour = floor(sod / 3600), min = floor(sod % 3600 / 60), sec = sod % 60,
		wday = (days + 4) % 7 + 1, days = days}
end

function K.stamp(t, off)
	local p = K.parts(t, off)
	return string.format("%04d-%02d-%02d %02d:%02d:%02d", p.year, p.month, p.day, p.hour, p.min, p.sec)
end

-- "Friday 18:00" parts: the weekday name key and the clock text
K.WEEKDAYS = {"Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"}

function K.clockText(hour, minute)
	return string.format("%02d:%02d", hour, minute)
end

-- "2h 05m", "45m", "30s": a duration for the login line
function K.span(seconds)
	seconds = floor(num(seconds, 0))
	if seconds < 0 then
		seconds = 0
	end
	local d, h, m = floor(seconds / DAY), floor(seconds % DAY / 3600), floor(seconds % 3600 / 60)
	if d > 0 then
		return string.format("%dd %dh", d, h)
	end
	if h > 0 then
		return string.format("%dh %02dm", h, m)
	end
	if m > 0 then
		return string.format("%dm", m)
	end
	return string.format("%ds", seconds)
end

-- ---------------------------------------------------------------- the window
local function secondOfWeek(spot)
	return (num(spot.weekday, 1) - 1) * DAY + num(spot.hour, 0) * 3600 + num(spot.minute, 0) * 60
end

-- start second of the week, length of the window in seconds (finish is the last minute, so the window ends at its end)
local function windowSpan(cfg)
	local s = secondOfWeek(cfg.schedule.start)
	local len = (secondOfWeek(cfg.schedule.finish) + 60 - s) % WEEK
	if len == 0 then
		len = WEEK
	end
	return s, len
end

local function keyOf(startsAt, off)
	local p = K.parts(startsAt, off)
	return p.year * 10000 + p.month * 100 + p.day
end
K.keyOf = keyOf

-- 1-based index into the rotation of the weekend that starts at startsAt (the epoch's weekend is 1)
function K.themeIndex(cfg, startsAt, off)
	local n = #(cfg.rotation or {})
	if n == 0 then
		return 1
	end
	local e = num(cfg.epoch, 20260102)
	local epochDays = K.daysFromCivil(floor(e / 10000), floor(e / 100) % 100, e % 100)
	local startDays = K.parts(startsAt, off).days
	return floor((startDays - epochDays) / 7) % n + 1
end

-- the theme of the weekend that starts at startsAt: key, table
function K.themeAt(cfg, startsAt, off)
	local key = cfg.forceTheme
	if not (key and (cfg.themes or {})[key]) then
		key = (cfg.rotation or {})[K.themeIndex(cfg, startsAt, off)]
	end
	return key, (cfg.themes or {})[key]
end

local function describe(cfg, s, off)
	local key, theme = K.themeAt(cfg, s, off)
	return {startsAt = s - off, endsAt = nil, key = keyOf(s - off, off), themeKey = key, theme = theme}
end

-- The window at time t. Always: nextStart, nextKey, nextThemeKey (the first start after t). When active: active = true,
-- startsAt, endsAt, key (YYYYMMDD of the first day), themeKey, theme, remaining.
function K.window(cfg, t, off)
	off = off or 0
	t = floor(t)
	local L = t + off
	local startS, len = windowSpan(cfg)
	local days = floor(L / DAY)
	local weekday0 = (days + 4) % 7
	local base = (days - weekday0) * DAY -- local Sunday 00:00 of this week
	local out = {active = false}
	for k = -1, 0 do
		local s = base + startS + k * WEEK
		if L >= s and L < s + len then
			out = describe(cfg, s, off)
			out.active = true
			out.endsAt = s + len - off
			out.remaining = out.endsAt - t
			break
		end
	end
	for k = 0, 1 do
		local s = base + startS + k * WEEK
		if s > L then
			local n = describe(cfg, s, off)
			out.nextStart, out.nextKey, out.nextThemeKey, out.nextTheme = n.startsAt, n.key, n.themeKey, n.theme
			break
		end
	end
	if out.active and not out.nextStart then
		local n = describe(cfg, base + startS + WEEK, off)
		out.nextStart, out.nextKey, out.nextThemeKey, out.nextTheme = n.startsAt, n.key, n.themeKey, n.theme
	end
	return out
end

-- the next n weekends that have not ended at t (the running one first): {startsAt, endsAt, key, themeKey, theme}
function K.upcoming(cfg, t, off, n)
	local out = {}
	local startS, len = windowSpan(cfg)
	local L = floor(t) + (off or 0)
	local days = floor(L / DAY)
	local base = (days - (days + 4) % 7) * DAY
	for k = -1, n + 1 do
		local s = base + startS + k * WEEK
		if s + len > L and #out < n then
			local w = describe(cfg, s, off or 0)
			w.endsAt = s + len - (off or 0)
			out[#out + 1] = w
		end
	end
	return out
end

-- ---------------------------------------------------------------- what the theme gives
-- {xp, loot, skill, riftReward} for a player; nothing outside the window, nothing for a season character unless the
-- config lets them (seasonal = true when the character is one)
function K.mults(cfg, w, seasonal)
	local m = {xp = 1, loot = 1, skill = 1, riftReward = 0}
	if not (w and w.active and w.theme) then
		return m
	end
	if seasonal and not cfg.seasonCharacters then
		return m
	end
	m.xp = math.max(1, num(w.theme.xp, 1))
	m.loot = math.max(1, num(w.theme.loot, 1))
	m.skill = math.max(1, num(w.theme.skill, 1))
	m.riftReward = math.max(0, num(w.theme.riftReward, 0))
	return m
end

-- training tries x mult, whole: the fraction is a chance (one try per hit would round the bonus away). rand() in [0, 1)
function K.scaleTries(tries, mult, rand)
	tries = num(tries, 0)
	if tries <= 0 or mult <= 1 then
		return tries
	end
	local scaled = tries * mult
	local whole = floor(scaled)
	if (rand or math.random)() < scaled - whole then
		whole = whole + 1
	end
	return whole
end

-- ---------------------------------------------------------------- the highlight
-- unix time of the highlight of the window w (nil when it is off)
function K.highlightAt(cfg, w, off)
	local h = cfg.highlight
	if not (h and h.enabled ~= false and w and w.startsAt) then
		return nil
	end
	off = off or 0
	local sL = w.startsAt + off
	local mid = floor(sL / DAY) * DAY
	local startWeekday = K.parts(w.startsAt, off).wday
	local delta = (num(h.weekday, 7) - startWeekday) % 7
	return mid + delta * DAY + num(h.hour, 0) * 3600 + num(h.minute, 0) * 60 - off
end

-- ---------------------------------------------------------------- what is due now
-- done: a table with true at "start:<key>", "end:<key>", "warn<m>:<key>" and "hl:<key>" for what was done already.
-- Returns a list of {kind = "start" | "endwarn" | "warnhl" | "highlight", key, minutes (endwarn, warnhl), mark = {...}}.
-- A warning is for the closest one only: a server that sees it late says the latest one and marks the earlier ones done.
function K.due(cfg, t, off, done)
	done = done or {}
	local w = K.window(cfg, t, off)
	local out = {}
	if not w.active then
		return out, w
	end
	local key = w.key
	if not done["start:" .. key] and t < w.startsAt + num(cfg.startGraceMinutes, 30) * 60 then
		out[#out + 1] = {kind = "start", key = key, mark = {"start:" .. key}}
	end
	local endWarn = num(cfg.endWarnMinutes, 60)
	if endWarn > 0 and not done["end:" .. key] and t >= w.endsAt - endWarn * 60 then
		out[#out + 1] = {kind = "endwarn", key = key, minutes = floor((w.endsAt - t) / 60 + 0.5), mark = {"end:" .. key}}
	end
	local h = cfg.highlight
	local at = K.highlightAt(cfg, w, off)
	if at then
		local warns = {}
		for _, m in ipairs(h.warnMinutes or {}) do
			warns[#warns + 1] = m
		end
		table.sort(warns, function(a, b) return a > b end) -- 30, 10: the earliest warning first
		local pick, marks = nil, {}
		for _, m in ipairs(warns) do
			local k = "warn" .. m .. ":" .. key
			if t >= at - m * 60 and t < at then
				marks[#marks + 1] = k
				if not done[k] then
					pick = m -- the latest warning not done whose time has come
				end
			end
		end
		if pick then
			out[#out + 1] = {kind = "warnhl", key = key, minutes = pick, at = at, mark = marks}
		end
		if t >= at and t < at + num(h.graceMinutes, 20) * 60 and not done["hl:" .. key] then
			out[#out + 1] = {kind = "highlight", key = key, at = at, mark = {"hl:" .. key}}
		end
	end
	return out, w
end

-- the login line before the start: {startsAt, in (seconds), themeKey, theme} within loginPreviewHours, else nil
function K.preview(cfg, t, off)
	local w = K.window(cfg, t, off)
	if w.active or not w.nextStart then
		return nil
	end
	local wait = w.nextStart - t
	if wait > num(cfg.loginPreviewHours, 48) * 3600 then
		return nil
	end
	return {startsAt = w.nextStart, wait = wait, themeKey = w.nextThemeKey, theme = w.nextTheme}
end

-- ---------------------------------------------------------------- the events calendar
-- entries as ChaosEvents.calendar sends them, for the weekends from the first day of the month of t over `days` days
function K.calendar(cfg, t, off, days)
	off = off or 0
	local p = K.parts(t, off)
	local firstDays = K.daysFromCivil(p.year, p.month, 1)
	local from = firstDays * DAY - off
	local to = from + (days or 62) * DAY
	local out = {}
	local c = cfg.calendar or {}
	for _, w in ipairs(K.upcoming(cfg, from - 4 * DAY, off, 14)) do
		if w.endsAt > from and w.startsAt < to then
			out[#out + 1] = {
				name = c.name or "Weekend Ritual",
				description = c.description or "",
				colorlight = c.colorlight,
				colordark = c.colordark,
				startdate = {date = K.stamp(w.startsAt, off)},
				enddate = {date = K.stamp(w.endsAt - 1, off)}
			}
		end
	end
	return out
end

-- ---------------------------------------------------------------- the config check
local function inRange(v, lo, hi)
	return type(v) == "number" and v >= lo and v <= hi
end

-- the problems of a config, as text (empty list: fine). Tests run it on the shipped config.
function K.validate(cfg)
	local bad = {}
	local function add(s) bad[#bad + 1] = s end
	local sc = cfg.schedule or {}
	for _, which in ipairs({"start", "finish"}) do
		local s = sc[which]
		if type(s) ~= "table" or not inRange(s.weekday, 1, 7) or not inRange(s.hour, 0, 23) or not inRange(s.minute, 0, 59) then
			add("schedule." .. which .. " needs weekday 1-7, hour 0-23, minute 0-59")
		end
	end
	if #bad > 0 then
		return bad
	end
	if type(cfg.rotation) ~= "table" or #cfg.rotation == 0 then
		add("rotation is empty")
	else
		for _, key in ipairs(cfg.rotation) do
			if type(cfg.themes) ~= "table" or type(cfg.themes[key]) ~= "table" then
				add("rotation: unknown theme " .. tostring(key))
			end
		end
	end
	local epoch = num(cfg.epoch, 0)
	local ep = K.parts(K.daysFromCivil(floor(epoch / 10000), floor(epoch / 100) % 100, epoch % 100) * DAY, 0)
	if ep.wday ~= sc.start.weekday then
		add("epoch must be a day of the start weekday (" .. tostring(cfg.epoch) .. ")")
	end
	for key, th in pairs(cfg.themes or {}) do
		local gives = 0
		if type(th.name) ~= "string" or type(th.text) ~= "string" then
			add("theme " .. key .. " needs a name and a text")
		end
		if th.xp then gives = gives + 1; if not inRange(th.xp, 1, 1.5) then add("theme " .. key .. ": xp from 1 to 1.5") end end
		if th.loot then gives = gives + 1; if not inRange(th.loot, 1, 1.5) then add("theme " .. key .. ": loot from 1 to 1.5") end end
		if th.skill then gives = gives + 1; if not inRange(th.skill, 1, 2) then add("theme " .. key .. ": skill from 1 to 2") end end
		if th.riftReward then gives = gives + 1; if not inRange(th.riftReward, 0, 50) then add("theme " .. key .. ": riftReward from 0 to 50") end end
		if gives == 0 then
			add("theme " .. key .. " gives nothing")
		end
	end
	local h = cfg.highlight
	if type(h) == "table" and h.enabled ~= false then
		if h.kind ~= "worldboss" and h.kind ~= "invasion" then
			add("highlight.kind is worldboss or invasion")
		end
		if not (inRange(h.weekday, 1, 7) and inRange(h.hour, 0, 23) and inRange(h.minute, 0, 59)) then
			add("highlight needs weekday 1-7, hour 0-23, minute 0-59")
		else
			-- the highlight and its grace must lie inside the window (checked on a window of the epoch's week)
			local e = num(cfg.epoch, 20260102)
			local startsAt = K.daysFromCivil(floor(e / 10000), floor(e / 100) % 100, e % 100) * DAY +
				sc.start.hour * 3600 + sc.start.minute * 60
			local w = K.window(cfg, startsAt, 0)
			local at = K.highlightAt(cfg, w, 0)
			if not (w.active and at and at >= w.startsAt and at + num(h.graceMinutes, 20) * 60 < w.endsAt) then
				add("the highlight must start inside the window and finish its grace there")
			end
			for _, m in ipairs(h.warnMinutes or {}) do
				if not inRange(m, 1, 600) then
					add("highlight.warnMinutes: 1 to 600")
				end
			end
		end
	end
	if num(cfg.tickSeconds, 0) < 5 then
		add("tickSeconds is at least 5")
	end
	return bad
end

return K
