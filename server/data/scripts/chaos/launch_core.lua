-- The launch moment (O463): pure logic, no engine API. Data: launch_config.lua (the one value `launch`, "open" or a date).
-- Tests: tests/launch_test.lua. Overview: server/README.md "Launch date (O463)", docs/LAUNCH.md.
--
--   ChaosLaunch.config()                 the config table (ChaosLaunch.override first, for tests; a missing file reads as open)
--   L.parse(text)                        -> year, month, day, hour, min of "YYYY-MM-DD HH:MM", or nil (open, or not a date)
--   L.isOpen(cfg)                        true unless `launch` is a valid date: a broken value fails closed (open)
--   L.offset(name, cfg)                  days from the launch to a derived moment (cfg.offsets, default below)
--   L.stamp(days, cfg)                   "YYYY-MM-DD HH:MM" of the launch plus `days` days, at the launch hour; nil while open
--   L.ymd(days, cfg)                     the same day as the number YYYYMMDD; nil while open
--   L.parts(days, cfg)                   {year, month, day, hour}; nil while open
--   L.hour(cfg)                          the launch hour (15 while open: the hour a date will get by default)
--   L.text(days, lang, cfg, withTime)    "20/11/2026 15:00" (pt-BR) / "2026-11-20 15:00" / "Em breve" / "Coming soon" while open
--   L.validate(cfg)                      -> list of problems (empty = fine; a date must be on the hour, HH:00)
-- The derived moments follow the one value: wipe = launch - 2 days, rehearsal = - 1, freeze = - 5, Founder Pack end = + 28,
-- (Season 1 ends season_config.lua lengthDays = 91 days after it). Lua 5.1 / LuaJIT and Lua 5.3 compatible.

ChaosLaunch = ChaosLaunch or {}
local L = ChaosLaunch

local floor = math.floor

L.SOON = {en = "Coming soon", ["pt-BR"] = "Em breve"}
L.DEFAULT_HOUR = 15
L.OFFSETS = {freeze = -5, wipe = -2, rehearsal = -1, founderEnd = 28}

function L.config()
	if type(L.override) == "table" then
		return L.override
	end
	local ok, cfg = pcall(dofile, "data/scripts/chaos/launch_config.lua")
	if ok and type(cfg) == "table" then
		return cfg
	end
	return {launch = "open"}
end

-- days since 1970-01-01 of a civil date (proleptic Gregorian) and back; no os.time, so no zone and no 2038 limit
local function daysFromCivil(y, m, d)
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

local function civilFromDays(z)
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
L.daysFromCivil, L.civilFromDays = daysFromCivil, civilFromDays

function L.parse(text)
	if type(text) ~= "string" then
		return nil
	end
	local y, mo, d, h, mi = text:match("^(%d%d%d%d)%-(%d%d)%-(%d%d) (%d%d):(%d%d)$")
	if not y then
		return nil
	end
	y, mo, d, h, mi = tonumber(y), tonumber(mo), tonumber(d), tonumber(h), tonumber(mi)
	if mo < 1 or mo > 12 or d < 1 or h > 23 or mi > 59 then
		return nil
	end
	local ry, rm, rd = civilFromDays(daysFromCivil(y, mo, d))
	if ry ~= y or rm ~= mo or rd ~= d then
		return nil -- 2026-02-30 and the like
	end
	return y, mo, d, h, mi
end

function L.isOpen(cfg)
	cfg = cfg or L.config()
	return L.parse(cfg.launch) == nil
end

function L.offset(name, cfg)
	cfg = cfg or L.config()
	local o = type(cfg.offsets) == "table" and tonumber(cfg.offsets[name]) or nil
	return o or L.OFFSETS[name]
end

local function shifted(days, cfg)
	cfg = cfg or L.config()
	local y, mo, d, h, mi = L.parse(cfg.launch)
	if not y then
		return nil
	end
	local ny, nm, nd = civilFromDays(daysFromCivil(y, mo, d) + (tonumber(days) or 0))
	return ny, nm, nd, h, mi
end

function L.stamp(days, cfg)
	local y, mo, d, h, mi = shifted(days, cfg)
	return y and string.format("%04d-%02d-%02d %02d:%02d", y, mo, d, h, mi) or nil
end

function L.ymd(days, cfg)
	local y, mo, d = shifted(days, cfg)
	return y and (y * 10000 + mo * 100 + d) or nil
end

function L.parts(days, cfg)
	local y, mo, d, h = shifted(days, cfg)
	return y and {year = y, month = mo, day = d, hour = h} or nil
end

function L.hour(cfg)
	local _, _, _, h = shifted(0, cfg)
	return h or L.DEFAULT_HOUR
end

function L.text(days, lang, cfg, withTime)
	local y, mo, d, h, mi = shifted(days, cfg)
	if not y then
		return lang == "pt-BR" and L.SOON["pt-BR"] or L.SOON.en
	end
	local time = withTime == false and "" or string.format(" %02d:%02d", h, mi)
	if lang == "pt-BR" then
		return string.format("%02d/%02d/%04d%s", d, mo, y, time)
	end
	return string.format("%04d-%02d-%02d%s", y, mo, d, time)
end

function L.validate(cfg)
	cfg = cfg or L.config()
	local problems = {}
	if type(cfg.launch) ~= "string" then
		problems[#problems + 1] = "launch must be \"open\" or \"YYYY-MM-DD HH:MM\""
	elseif cfg.launch ~= "open" and not L.parse(cfg.launch) then
		problems[#problems + 1] = "launch is neither \"open\" nor a real \"YYYY-MM-DD HH:MM\": " .. cfg.launch
	elseif cfg.launch ~= "open" then
		-- Season 1, PvP season 1 and the Tower season start at an hour (their configs have no minute): the Founder Pack and the
		-- creator bonus would otherwise start minutes before them
		local _, _, _, _, mi = L.parse(cfg.launch)
		if mi ~= 0 then
			problems[#problems + 1] = "launch must be on the hour (HH:00): Season 1, PvP season 1 and the Tower season have no minute"
		end
	end
	for name in pairs(L.OFFSETS) do
		local o = type(cfg.offsets) == "table" and cfg.offsets[name]
		if type(o) ~= "number" or o ~= floor(o) then
			problems[#problems + 1] = "offsets." .. name .. " must be a whole number of days"
		end
	end
	return problems
end

return L
