-- Event schedule: recurring server events with real bonuses (config: Chaos.events in chaos_constants.lua).
--
-- ChaosEvents.active(t)        -> list of events active at time t (default now)
-- ChaosEvents.bonus(kind, t)   -> product of the active multipliers of that kind (1 when none)
-- ChaosEvents.calendar(t)      -> {eventlist = [...]} in the format the client calendar reads
--                                 (name, description, colorlight, colordark, startdate.date, enddate.date)
--
-- Where the bonuses are applied:
--   xp          EventCallback onGainExperience (below)
--   loot        loot_config.lua rateMult + one extra roll on normal monsters (loot.lua)
--   tierChance  monster_tiers.lua spawn roll
--   ambush      monster_tiers.lua ambush roll
--   towerPoints infinitytower.lua ChaosTower.recordRun
-- Lua 5.1 / LuaJIT compatible.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not Chaos.t then
	dofile("data/scripts/chaos/i18n_core.lua")
end
if not ChaosCommands then
	dofile("data/scripts/chaos/commands_ui_core.lua")
end

ChaosEvents = ChaosEvents or {}
local E = ChaosEvents
E.dynamic = E.dynamic or {} -- key -> runtime event (see E.active)

local function cfg()
	return Chaos.events or {list = {}}
end

local function contains(list, value)
	for _, v in ipairs(list or {}) do
		if v == value then
			return true
		end
	end
	return false
end

-- true if the event runs on the calendar day of time t
function E.runsOn(event, t)
	local d = os.date("*t", t)
	if event.weekdays and contains(event.weekdays, d.wday) then
		return true
	end
	if event.monthdays and contains(event.monthdays, d.day) then
		return true
	end
	return false
end

function E.active(t)
	t = t or os.time()
	local list = {}
	for _, event in ipairs(cfg().list) do
		if E.runsOn(event, t) then
			list[#list + 1] = event
		end
	end
	-- runtime events with an end time (invasion.lua: the Victory buff; worldevents.lua): {id, name, description, bonus, untilTime}
	for _, event in pairs(E.dynamic) do
		if (event.untilTime or 0) > t then
			list[#list + 1] = event
		end
	end
	return list
end

function E.bonus(kind, t)
	local mult = 1
	for _, event in ipairs(E.active(t)) do
		local b = event.bonus and event.bonus[kind]
		if type(b) == "number" and b > 0 then
			mult = mult * b
		end
	end
	return mult
end

local function dayStart(t)
	local d = os.date("*t", t)
	return os.time({year = d.year, month = d.month, day = d.day, hour = 0, min = 0, sec = 0})
end

local function addDays(t, n)
	local d = os.date("*t", t)
	-- noon avoids DST edges, dayStart() brings it back to midnight
	return dayStart(os.time({year = d.year, month = d.month, day = d.day + n, hour = 12}))
end

local function stamp(t)
	return os.date("%Y-%m-%d %H:%M:%S", t)
end

-- Occurrences from the first day of the month of t, consecutive days merged into one range.
function E.calendar(t)
	t = t or os.time()
	local d = os.date("*t", t)
	local first = os.time({year = d.year, month = d.month, day = 1, hour = 12})
	first = dayStart(first)
	local days = cfg().calendarDays or 62
	local out = {}
	for _, event in ipairs(cfg().list) do
		local runStart
		for i = 0, days do
			local day = addDays(first, i)
			local on = i < days and E.runsOn(event, day)
			if on and not runStart then
				runStart = day
			elseif not on and runStart then
				out[#out + 1] = {
					name = event.name,
					description = event.description,
					colorlight = event.colorlight,
					colordark = event.colordark,
					startdate = {date = stamp(runStart)},
					enddate = {date = stamp(day - 1)}
				}
				runStart = nil
			end
		end
	end
	-- the Weekend Ritual (weekend.lua): Friday evening to Sunday night, not whole days
	if ChaosWeekend and ChaosWeekend.calendarEntries then
		for _, entry in ipairs(ChaosWeekend.calendarEntries(t)) do
			out[#out + 1] = entry
		end
	end
	table.sort(out, function(a, b)
		return a.startdate.date < b.startdate.date
	end)
	return {eventlist = out}
end

-- one line per active event, used on login and by !events
-- (an event with describe(player) writes its own line in the player's language: the Weekend Ritual)
function E.describeActive(t, player)
	local lines = {}
	for _, event in ipairs(E.active(t)) do
		if type(event.describe) == "function" then
			lines[#lines + 1] = event.describe(player)
		else
			lines[#lines + 1] = event.name .. ": " .. event.description
		end
	end
	return lines
end

-- experience bonus
local xpCb = EventCallback
xpCb.onGainExperience = function(self, source, exp, rawExp)
	local mult = E.bonus("xp")
	if mult ~= 1 and source and source:isMonster() then
		return math.floor(exp * mult)
	end
	return exp
end
xpCb:register()

local login = CreatureEvent("ChaosEventsLogin")
function login.onLogin(player)
	if cfg().announceOnLogin then
		for _, line in ipairs(E.describeActive(nil, player)) do
			player:sendTextMessage(MESSAGE_STATUS_CONSOLE_BLUE, Chaos.t(player, "Event active - %s", line))
		end
	end
	return true
end
login:register()

local talk = {} -- reached from the menu: Info & Services window (commands_ui.lua, id "events")
function talk.onSay(player, words, param)
	local lines = E.describeActive(nil, player)
	if #lines == 0 then
		player:sendTextMessage(MESSAGE_INFO_DESCR, Chaos.t(player, "No event is active today. Check the calendar on the login screen."))
	else
		player:sendTextMessage(MESSAGE_INFO_DESCR, Chaos.t(player, "Active events:\n%s", table.concat(lines, "\n")))
	end
	return false
end
ChaosCommands.register("events", function(player, param) return talk.onSay(player, "", param) end)
