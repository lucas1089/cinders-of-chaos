-- Run from the server/ folder: luajit tests/launch_test.lua (CI runs it with LuaJIT and Lua 5.3).
-- The launch moment (O463): data/scripts/chaos/launch_core.lua and launch_config.lua. The open state, a set date (an example
-- date, never the owner's), every derived moment, text in both languages, bad values failing closed, and that the five configs
-- that start something at the launch follow the one value (open: nothing starts, set: the old dates come back).
local checks, fails = 0, 0
local function ok(cond, what)
	checks = checks + 1
	if not cond then
		fails = fails + 1
		print("FAIL " .. tostring(what))
	end
end
local function eq(a, b, what)
	ok(a == b, (what or "check") .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end

local L = dofile("data/scripts/chaos/launch_core.lua")
local EXAMPLE = {launch = "2031-03-14 18:00", offsets = {freeze = -5, wipe = -2, rehearsal = -1, founderEnd = 28}}
local OPEN = {launch = "open"}

-- ---------------------------------------------------------------- the shipped config
L.override = nil
local shipped = L.config()
eq(#L.validate(shipped), 0, "the shipped launch_config.lua is valid")
eq(shipped.launch, "open", "the owner put the launch on hold (2026-11-10): launch = open")
ok(L.isOpen(shipped), "shipped: open")
eq(L.stamp(0, shipped), nil, "shipped: no stamp")
eq(L.ymd(0, shipped), nil, "shipped: no ymd")
eq(L.parts(28, shipped), nil, "shipped: no parts")
eq(L.hour(shipped), 15, "shipped: a date will get the launch hour 15 by default")

-- ---------------------------------------------------------------- the open state
ok(L.isOpen(OPEN), "open is open")
eq(L.stamp(0, OPEN), nil, "open: stamp nil")
eq(L.text(0, "en", OPEN), "Coming soon", "open: en text")
eq(L.text(0, "pt-BR", OPEN), "Em breve", "open: pt-BR text")
eq(L.text(28, "en", OPEN, false), "Coming soon", "open: the offset does not matter")

-- ---------------------------------------------------------------- a set date and what follows it
ok(not L.isOpen(EXAMPLE), "a date is not open")
eq(L.stamp(0, EXAMPLE), "2031-03-14 18:00", "launch stamp")
eq(L.stamp(L.offset("wipe", EXAMPLE), EXAMPLE), "2031-03-12 18:00", "wipe = launch - 2 days")
eq(L.stamp(L.offset("rehearsal", EXAMPLE), EXAMPLE), "2031-03-13 18:00", "rehearsal = launch - 1 day")
eq(L.stamp(L.offset("freeze", EXAMPLE), EXAMPLE), "2031-03-09 18:00", "freeze = launch - 5 days")
eq(L.stamp(L.offset("founderEnd", EXAMPLE), EXAMPLE), "2031-04-11 18:00", "Founder Pack end = launch + 28 days")
eq(L.stamp(91, EXAMPLE), "2031-06-13 18:00", "Season 1 end = launch + 91 days (season_config.lua lengthDays)")
eq(L.ymd(0, EXAMPLE), 20310314, "ymd")
eq(L.hour(EXAMPLE), 18, "the launch hour is the hour of the value")
local p = L.parts(0, EXAMPLE)
ok(p and p.year == 2031 and p.month == 3 and p.day == 14 and p.hour == 18, "parts")
eq(L.text(0, "en", EXAMPLE), "2031-03-14 18:00", "en text")
eq(L.text(0, "pt-BR", EXAMPLE), "14/03/2031 18:00", "pt-BR text")
eq(L.text(28, "pt-BR", EXAMPLE, false), "11/04/2031", "pt-BR date without the time")
-- month and year borders, a leap day
local border = {launch = "2027-12-30 09:05"}
eq(L.stamp(3, border), "2028-01-02 09:05", "over the new year")
eq(L.stamp(60, border), "2028-02-28 09:05", "february of a leap year")
eq(L.stamp(61, border), "2028-02-29 09:05", "the leap day exists")
eq(L.stamp(-364, border), "2026-12-31 09:05", "back a year")
-- offsets default when the config leaves them out; a config may move them
eq(L.offset("wipe", OPEN), -2, "default offset")
eq(L.offset("wipe", {launch = "2031-03-14 18:00", offsets = {wipe = -3}}), -3, "an offset moves")

-- ---------------------------------------------------------------- bad values fail closed
for _, bad in ipairs({"soon", "", "2031-13-01 10:00", "2031-02-30 10:00", "2031-03-14", "2031-03-14 25:00", "2031-3-14 10:00"}) do
	ok(L.isOpen({launch = bad}), "a bad value is open: " .. bad)
	eq(L.stamp(0, {launch = bad}), nil, "a bad value has no date: " .. bad)
	ok(#L.validate({launch = bad, offsets = EXAMPLE.offsets}) > 0, "validate names it: " .. bad)
end
ok(L.isOpen({}), "no value is open")
ok(#L.validate({launch = "2031-03-14 18:30", offsets = EXAMPLE.offsets}) > 0, "validate: a launch off the hour is refused")
ok(not L.isOpen({launch = "2031-03-14 18:30"}), "but it is still a date (the check is validate's)")
ok(#L.validate({offsets = EXAMPLE.offsets}) > 0, "validate: no value")
ok(#L.validate({launch = "open", offsets = {wipe = 1.5}}) > 0, "validate: offsets must be whole days")
eq(#L.validate({launch = "open", offsets = EXAMPLE.offsets}), 0, "validate: open is fine")
eq(#L.validate(EXAMPLE), 0, "validate: a date is fine")

-- ---------------------------------------------------------------- the override of the tests
L.override = EXAMPLE
eq(L.stamp(0), "2031-03-14 18:00", "the override is the config")
L.override = OPEN
ok(L.isOpen(), "the override can be open")
L.override = nil

-- ---------------------------------------------------------------- the configs that follow the one value
local function loadWith(override, file)
	L.override = override
	local cfg = dofile("data/scripts/chaos/" .. file)
	L.override = nil
	return cfg
end

-- Founder Pack
local f = loadWith(OPEN, "founder_config.lua")
eq(f.start, nil, "open: founder start nil")
eq(f["end"], nil, "open: founder end nil")
eq(f.open, true, "open: founder is marked open")
for _, o in ipairs(f.store.pack.offers) do
	eq(o.availableSoon, true, "open: the offer is not on sale: " .. o.key)
	eq(o.availableFrom, nil, "open: the offer has no sale window: " .. o.key)
	eq(o.availableUntil, nil, "open: the offer shows no end date: " .. o.key)
end
f = loadWith(EXAMPLE, "founder_config.lua")
eq(f.start, "2031-03-14 18:00", "set: founder start is the launch")
eq(f["end"], "2031-04-11 18:00", "set: founder end is launch + 28 days")
eq(f.open, nil, "set: founder is not open")
for _, o in ipairs(f.store.pack.offers) do
	eq(o.availableFrom, "2031-03-14 18:00", "set: offer from: " .. o.key)
	eq(o.availableUntil, "2031-04-11 18:00", "set: offer until: " .. o.key)
	eq(o.availableSoon, nil, "set: offer not soon: " .. o.key)
end

-- creator launch bonus
local c = loadWith(OPEN, "creator_codes_config.lua")
eq(c.launchBonusStart, nil, "open: no creator bonus start")
c = loadWith(EXAMPLE, "creator_codes_config.lua")
eq(c.launchBonusStart, "2031-03-14 18:00", "set: creator bonus starts with the launch")
eq(c.launchBonusPct, 15, "the bonus % is not touched")
eq(c.launchBonusDays, 30, "the bonus days are not touched")

-- Season 1
local s = loadWith(OPEN, "season_config.lua").seasons[1]
eq(s.open, true, "open: Season 1 is open")
eq(s.start, nil, "open: Season 1 has no start")
eq(s.finish, nil, "open: Season 1 has no finish")
eq(s.lengthDays, 91, "open: Season 1 keeps its length")
s = loadWith(EXAMPLE, "season_config.lua").seasons[1]
eq(s.open, nil, "set: Season 1 is not open")
eq(s.start, 20310314, "set: Season 1 starts with the launch")
eq(s.finish, 20310613, "set: Season 1 ends 91 days later")
eq(L.ymd(s.lengthDays, EXAMPLE), s.finish, "set: finish = start + lengthDays (the two literals of season_config.lua agree)")
eq(s.hour, 18, "set: Season 1 starts at the launch hour")

-- PvP season 1
local b = loadWith(OPEN, "battleground_config.lua")
eq(b.season.epoch, nil, "open: no PvP epoch")
b = loadWith(EXAMPLE, "battleground_config.lua")
ok(b.season.epoch and b.season.epoch.year == 2031 and b.season.epoch.month == 3 and b.season.epoch.day == 14 and
	b.season.epoch.hour == 18, "set: the PvP epoch is the launch")

-- the Tower epoch lives in chaos_constants.lua, which needs the engine's globals: its line is read as text
local f2 = io.open("data/scripts/chaos/chaos_constants.lua", "r")
local src = f2:read("*a")
f2:close()
ok(src:find("ChaosLaunch", 1, true) ~= nil or src:find("launch_core", 1, true) ~= nil, "chaos_constants.lua reads the launch value")
ok(not src:find("seasonEpoch%s*=%s*{year%s*=%s*2026"), "chaos_constants.lua has no literal Tower epoch")

print(string.format("launch_test: %d checks, %d failures", checks, fails))
os.exit(fails == 0 and 0 or 1)
