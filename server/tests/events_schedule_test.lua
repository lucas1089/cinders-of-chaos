-- Run from the server/ folder: luajit tests/events_schedule_test.lua (mock engine API; CI runs it)
local n = 0
setmetatable(_G, {__index = function(t, k)
  if type(k) == "string" and k:match("^[A-Z_0-9]+$") then n = n + 1; rawset(t, k, n); return n end
end})
local registry = {}
function CreatureEvent(name) local o = {}; function o:register() registry[name] = o end; return o end
function TalkAction() local o = {}; function o:register() end; function o:separator() end; return o end
local callbacks = {}
EventCallback = setmetatable({register = function() end}, {__newindex = function(_, k, v) callbacks[k] = v end})
dofile("data/scripts/chaos/chaos_constants.lua")
dofile("data/scripts/chaos/events_schedule.lua")

local assertEq = function(a, b, m) if a ~= b then error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2) end end
local E = ChaosEvents
local function at(y, m, d, h) return os.time({year = y, month = m, day = d, hour = h or 12}) end

-- fixed test schedule
Chaos.events.list = {
  {id = "weekend", name = "Weekend", weekdays = {7, 1}, description = "d", colorlight = "#1", colordark = "#2", bonus = {xp = 1.5}},
  {id = "wed", name = "Wednesday", weekdays = {4}, description = "d", colorlight = "#1", colordark = "#2", bonus = {xp = 2, tierChance = 2}},
  {id = "first", name = "First days", monthdays = {1, 2}, description = "d", colorlight = "#1", colordark = "#2", bonus = {loot = 1.5}}
}
Chaos.events.calendarDays = 31

-- 2026-10-03 is a Saturday, 2026-10-07 a Wednesday, 2026-10-08 a Thursday
assertEq(#E.active(at(2026, 10, 3)), 1, "saturday: weekend only")
assertEq(E.bonus("xp", at(2026, 10, 3)), 1.5, "weekend xp")
assertEq(E.bonus("xp", at(2026, 10, 7)), 2, "wednesday xp")
assertEq(E.bonus("tierChance", at(2026, 10, 7)), 2, "wednesday tier chance")
assertEq(E.bonus("xp", at(2026, 10, 8)), 1, "thursday: no event")
assertEq(E.bonus("loot", at(2026, 10, 1)), 1.5, "first day of month")
-- 2026-11-01 is a Sunday: weekend and first-days overlap, bonuses of different kinds stay separate
assertEq(E.bonus("xp", at(2026, 11, 1)), 1.5, "sunday the 1st xp")
assertEq(E.bonus("loot", at(2026, 11, 1)), 1.5, "sunday the 1st loot")

-- calendar: consecutive days merge into one range, ranges sorted by start
local cal = E.calendar(at(2026, 10, 15)).eventlist
local first = cal[1]
assertEq(first.name, "First days", "first range of October")
assertEq(first.startdate.date, "2026-10-01 00:00:00", "first range start")
assertEq(first.enddate.date, "2026-10-02 23:59:59", "first range end")
local weekendRanges = 0
for _, e in ipairs(cal) do
  if e.name == "Weekend" then
    weekendRanges = weekendRanges + 1
    if e.startdate.date == "2026-10-03 00:00:00" then
      assertEq(e.enddate.date, "2026-10-04 23:59:59", "saturday+sunday merged")
    end
  end
  assert(e.colorlight and e.colordark and e.description, "client fields present")
end
assertEq(weekendRanges, 5, "five weekends from Oct 1 over 31 days")
for i = 2, #cal do
  assert(cal[i - 1].startdate.date <= cal[i].startdate.date, "sorted by start")
end

-- experience callback multiplies only monster experience
local monster = {isMonster = function() return true end}
local player = {isMonster = function() return false end}
local realTime = os.time
os.time = function(t) if t then return realTime(t) end return at(2026, 10, 7) end
assertEq(callbacks.onGainExperience(nil, monster, 100, 100), 200, "wednesday doubles monster xp")
assertEq(callbacks.onGainExperience(nil, player, 100, 100), 100, "non-monster xp untouched")
os.time = realTime

print("events_schedule_test: ok")
