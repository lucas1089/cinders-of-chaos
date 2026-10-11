-- Run from the server/ folder: luajit tests/daily_test.lua (and lua5.3; CI runs both)
-- Part 1: the pure streak logic (daily_core.lua) with the real daily_config.lua: days, the 7-slot cycle, grace,
-- milestones, titles, the migration from the old per-character storages, the login window order.
-- Part 2: daily.lua on a mocked engine API: the client protocol (slot mapping), account-wide claims, all or nothing,
-- milestone rewards, the login window queue.
dofile("data/scripts/chaos/daily_core.lua")
local D = ChaosDailyCore
local SC = dofile("data/scripts/chaos/daily_config.lua")

local function eq(a, b, m)
	if a ~= b then
		error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2)
	end
end

-- ---------------------------------------------------------------- config
local prev = 0
for _, m in ipairs(SC.milestones) do
	assert(m.days > prev, "milestones in order")
	prev = m.days
	assert(#m.items > 0, "milestone " .. m.days .. " has a reward")
end
local days = {}
for _, m in ipairs(SC.milestones) do
	days[#days + 1] = m.days
end
eq(table.concat(days, ","), "7,14,30,60,100,180", "milestone days")
eq(D.milestoneAt(SC, 30).title ~= nil, true, "a title at 30")
eq(D.milestoneAt(SC, 100).title ~= nil, true, "a title at 100")
eq(D.milestoneAt(SC, 180).title ~= nil, true, "a title at 180")
eq(SC.graceEvery, 7, "a grace charge per 7 days")
eq(SC.graceMax, 2, "2 charges at most")

-- ---------------------------------------------------------------- days
eq(D.gap(20261007, 20261008), 1, "next day")
eq(D.gap(20261031, 20261101), 1, "over a month end")
eq(D.gap(20261231, 20270101), 1, "over the year end")
eq(D.gap(20260228, 20260301), 1, "February")
eq(D.gap(20261025, 20261026), 1, "daylight saving change in Europe")
eq(D.gap(20261001, 20261008), 7, "a week")
eq(D.gap(0, 20261008), nil, "never claimed")
eq(D.slotOf(1), 1, "slot 1")
eq(D.slotOf(7), 7, "slot 7")
eq(D.slotOf(8), 1, "day 8 is slot 1")
eq(D.slotOf(30), 2, "day 30 is slot 2")

-- ---------------------------------------------------------------- view and claim
local T = 20261008
local v = D.view(D.blank(), T, SC)
eq(v.taken, false, "fresh: not taken")
eq(v.next, 1, "fresh: day 1")
eq(v.slot, 1, "fresh: slot 1")
eq(v.achieved, 0, "fresh: nothing reached")

local rec, res = D.claim(D.blank(), T, SC)
eq(rec.streak, 1, "first claim")
eq(rec.best, 1, "best")
eq(rec.last, T, "last claim")
eq(res.slot, 1, "slot")
eq(res.milestone, nil, "no milestone on day 1")
local again, why = D.claim(rec, T, SC)
eq(again, nil, "twice a day refused")
eq(why, "taken", "reason")
v = D.view(rec, T, SC)
eq(v.taken, true, "taken today")
eq(v.next, 1, "taken: the streak of today")
eq(v.achieved, 1, "taken: day 1 reached")

-- walk 7 days: the week milestone and a grace charge on day 7
local day = 20261008
rec = D.blank()
for i = 1, 7 do
	rec, res = D.claim(rec, day, SC)
	day = day + 1
end
eq(rec.streak, 7, "7 days")
eq(res.slot, 7, "slot 7")
eq(res.week, true, "week bonus day")
eq(res.milestone.days, 7, "milestone 7")
eq(res.graceGained, 1, "grace charge earned")
eq(rec.grace, 1, "one charge")
rec, res = D.claim(rec, day, SC) -- 20261015, day 8
eq(res.slot, 1, "day 8: slot 1 again")
eq(rec.streak, 8, "streak keeps counting")

-- missing one day with a charge: the streak goes on, the charge is used
v = D.view(rec, 20261017, SC) -- 20261016 missed
eq(v.graceUse, 1, "a charge covers the missed day")
eq(v.next, 9, "streak continues")
eq(v.broken, false, "not broken")
local r2, res2 = D.claim(rec, 20261017, SC)
eq(r2.streak, 9, "claimed through grace")
eq(r2.grace, 0, "charge used")
eq(res2.graceUsed, 1, "result says so")
-- missing a day without a charge: broken
v = D.view(r2, 20261019, SC)
eq(v.broken, true, "no charge: broken")
eq(v.streak, 0, "the streak shown is 0")
eq(v.next, 1, "starts at 1")
eq(v.slot, 1, "slot 1")
local r3 = D.claim(r2, 20261019, SC)
eq(r3.streak, 1, "new streak")
eq(r3.best, 9, "best kept")
-- two missed days with two charges: graceMaxMissed = 1 -> broken
local rich = {streak = 20, best = 20, grace = 2, last = 20261008, claims = 20}
v = D.view(rich, 20261011, SC)
eq(v.broken, true, "two missed days are not covered")
v = D.view(rich, 20261010, SC)
eq(v.graceUse, 1, "one missed day uses one of two charges")
-- charges stop at graceMax
local full = {streak = 13, best = 13, grace = 2, last = 20261008, claims = 13}
local r4, res4 = D.claim(full, 20261009, SC)
eq(r4.grace, 2, "no third charge")
eq(res4.graceGained, 0, "nothing gained at the cap")
eq(res4.milestone.days, 14, "milestone 14")
-- clock back (last claim in the future): start again, never pay twice for one day
v = D.view({streak = 5, best = 5, grace = 0, last = 20261010, claims = 5}, 20261008, SC)
eq(v.taken, false, "future claim date")
eq(v.next, 1, "restart")

-- ---------------------------------------------------------------- milestones and titles
eq(D.nextMilestone(SC, 0).days, 7, "next milestone from 0")
eq(D.nextMilestone(SC, 7).days, 14, "next after 7")
eq(D.nextMilestone(SC, 29).days, 30, "next after 29")
eq(D.nextMilestone(SC, 180), nil, "all reached")
eq(D.titleFor(SC, 29), nil, "no title below 30")
local title, tdays = D.titleFor(SC, 45)
eq(title, D.milestoneAt(SC, 30).title, "title at 45 days")
eq(tdays, 30, "its days")
eq(D.titleFor(SC, 500), D.milestoneAt(SC, 180).title, "highest title")
local names = {[29856] = "Orb of Upheaval", [29857] = "Orb of Fate", [29855] = "Orb of Grafting"}
local function nm(id) return names[id] or ("item " .. id) end
eq(D.milestoneText(D.milestoneAt(SC, 7), nm), "2x Orb of Upheaval, 1x Orb of Fate", "milestone text")
assert(D.milestoneText(D.milestoneAt(SC, 30), nm):find("and the title \"", 1, true), "title in the milestone text")
eq(D.lookText(nil, 0, "He"), nil, "no look text without a title")
eq(D.lookText("the Devoted", 30, "You"), "You hold the login streak title the Devoted (30 days in a row).", "look text")
eq(D.lookText("the Devoted", 30, "She"), "She holds the login streak title the Devoted (30 days in a row).", "look she")

-- ---------------------------------------------------------------- migration
local m = D.migrate({{slot = 3, last = 20261005}, {slot = 6, last = 20261007}, {slot = 7, last = 20261001}})
eq(m.streak, 6, "the most recent claim wins")
eq(m.last, 20261007, "its day")
eq(m.best, 6, "best from it")
m = D.migrate({{slot = 2, last = 20261007}, {slot = 5, last = 20261007}})
eq(m.streak, 5, "same day: the higher slot")
m = D.migrate({{slot = -1, last = -1}, {slot = 9, last = 20261007}})
eq(m.streak, 0, "unset or bad storages: blank")
eq(m.last, 0, "blank last")
eq(D.view(D.migrate({{slot = 4, last = 20261007}}), 20261008, SC).next, 5, "a migrated streak continues")

-- ---------------------------------------------------------------- login order
local order = D.loginOrder({{key = "daily", order = 20}, {key = "notes", order = 10}, {key = "other", order = 30}},
	{daily = true, notes = true})
eq(table.concat(order, ","), "notes,daily", "wanted windows in order")
eq(#D.loginOrder({{key = "daily", order = 20}}, {}), 0, "nothing wanted")

-- ================================================================ part 2: daily.lua on a mocked engine
local n = 0
setmetatable(_G, {__index = function(t, k)
	if type(k) == "string" and k:match("^[A-Z_0-9]+$") then n = n + 1; rawset(t, k, n); return n end
end})
local registry, events, looks = {}, {}, {}
function CreatureEvent(name) local o = {}; function o:register() registry[name] = o end; function o:type() end; return o end
function addEvent(fn, delay, ...) events[#events + 1] = {fn = fn, args = {...}} end
function TalkAction() local o = {}; function o:register() end; function o:separator() end; return o end
function ItemType(id) return {getClientId = function() return id + 1000 end, getName = function() return "item" .. id end} end
EventCallback = setmetatable({register = function(self) looks[#looks + 1] = rawget(self, "_fn") end},
	{__newindex = function(t, k, v) rawset(t, "_fn", v) end})
local broadcasts = {}
Game = {getPlayers = function() return {} end, broadcastMessage = function(t) broadcasts[#broadcasts + 1] = t end}
local queries = {}
db = {query = function(q) queries[#queries + 1] = q; return true end}
local players = {}
function Player(id) return players[id] end
dofile("data/scripts/chaos/chaos_constants.lua")
local TODAY = 20261007
Chaos.dayKey = function() return TODAY end
Chaos.yesterdayKey = function() return TODAY - 1 end
local sent = {}
Chaos.send = function(_, _, action, data) sent[#sent + 1] = {action = action, data = data} end
Chaos.decode = function(b) return b end
local dbRows = {} -- old storages in the DB (player_storage)
Chaos.select = function(q) if q:find("player_storage", 1, true) then return dbRows end return {} end
local room = 1000 -- how many items fit
Chaos.giveItem = function(p, id, count) local g = math.min(count, room); room = room - g; p.items[id] = (p.items[id] or 0) + g; return g end
local nextId = 0
local function mkPlayer(account)
	nextId = nextId + 1
	local p = {st = {}, items = {}, msgs = {}, id = nextId, account = account or 1}
	function p:getStorageValue(k) return self.st[k] or -1 end
	function p:setStorageValue(k, v) self.st[k] = v end
	function p:sendCancelMessage(t) self.cancel = t end
	function p:sendTextMessage(_, t) self.msgs[#self.msgs + 1] = t end
	function p:removeItem(id, c) self.items[id] = self.items[id] - c; room = room + c end
	function p:getPosition() return {sendMagicEffect = function() end} end
	function p:getId() return self.id end
	function p:getGuid() return self.id end
	function p:getAccountId() return self.account end
	function p:getName() return "Char" .. self.id end
	function p:registerEvent() end
	function p:isPlayer() return true end
	function p:getSex() return 0 end
	players[p.id] = p
	return p
end
dofile("data/scripts/chaos/daily.lua")
local cfg = Chaos.daily
eq(#cfg.rewards, 7, "seven rewards")
local ev = registry["ChaosDailyExtended"]
local S = Chaos.storage
local DY = ChaosDaily
local map = {6, 7, 1, 2, 3, 4, 5} -- the client sends v = map[slot]
local function call(p, action, data) ev.onExtendedOpcode(p, ChaosOpcodes.daily, {action = action, data = data}) end
local function lastWindow() for i = #sent, 1, -1 do if sent[i].action == "OpenDailyWindow" then return sent[i].data end end end

-- migration at login: the best of the account's characters
dbRows = {{player_id = 50, key = S.dailyStreakDay, value = 3}, {player_id = 50, key = S.dailyLastClaim, value = TODAY - 1},
	{player_id = 51, key = S.dailyStreakDay, value = 6}, {player_id = 51, key = S.dailyLastClaim, value = TODAY - 3}}
local a = mkPlayer(1)
registry["ChaosDailyLogin"].onLogin(a)
eq(DY.accounts[1].streak, 3, "migrated from the most recent claim")
assert(queries[#queries]:find("chaos_daily_account", 1, true), "row written")
-- the login window queue: the daily window is sent with Login = 1
eq(#events, 1, "login queue scheduled")
events[1].fn(table.unpack and table.unpack(events[1].args) or unpack(events[1].args))
local w = lastWindow()
eq(w.Login, 1, "opened at login")
eq(w.Day + 2, 4, "slot 4 claimable (client adds 2)")
eq(w.Streak, 3, "streak shown")
eq(w.Next.Days, 7, "next milestone")
eq(w.Next.In, 4, "in 4 days")
-- claim day 4 from character a
call(a, "calim", map[4])
eq(a.items[cfg.rewards[4].itemId], cfg.rewards[4].count, "day 4 reward")
eq(DY.accounts[1].streak, 4, "streak 4")
eq(a.st[S.dailyLastClaim], TODAY, "old storage kept in step")
-- another character of the same account cannot claim today
local b = mkPlayer(1)
registry["ChaosDailyLogin"].onLogin(b)
call(b, "calim", map[5])
assert(b.cancel and b.cancel:find("account already"), "account-wide: second character refused")
eq(next(b.items), nil, "nothing given to the alt")
eq(lastWindow().TakenReward, 1, "the alt sees it taken")
-- a character of another account claims day 1
dbRows = {}
local c = mkPlayer(2)
registry["ChaosDailyLogin"].onLogin(c)
call(c, "calim", map[1])
eq(c.items[cfg.rewards[1].itemId], cfg.rewards[1].count, "other account: day 1")
-- stale window (wrong slot): resync, no reward
TODAY = 20261008
local before = a.items[cfg.rewards[5].itemId] or 0
call(a, "calim", map[2])
eq(a.items[cfg.rewards[5].itemId] or 0, before, "wrong slot: nothing paid")
-- walk to day 7: week bonus + milestone 7 + grace charge
for slot = 5, 7 do
	call(a, "calim", map[slot])
	assert(not a.cancel, "claim day " .. slot)
	TODAY = TODAY + 1
end
eq(DY.accounts[1].streak, 7, "streak 7")
eq(DY.accounts[1].grace, 1, "grace charge")
local seven = D.milestoneAt(SC, 7)
local orbs = 0
for _, it in ipairs(seven.items) do if it.itemId == 29856 then orbs = orbs + it.count end end
eq(a.items[29856], (cfg.rewards[2].itemId == 29856 and 0 or 0) + orbs + (cfg.rewards[6].itemId == 29856 and cfg.rewards[6].count or 0),
	"milestone orbs given with day 6's orbs")
local found = false
for _, t in ipairs(a.msgs) do if t:find("Login streak of 7 days", 1, true) then found = true end end
eq(found, true, "milestone message")
-- all or nothing: day 14's milestone does not fit -> nothing given, streak unchanged
DY.accounts[1] = {streak = 13, best = 13, grace = 1, last = TODAY - 1, claims = 13}
room = 2
local before14 = a.items[cfg.rewards[7].itemId]
call(a, "calim", map[7])
assert(a.cancel and a.cancel:find("room"), "refused when the milestone does not fit")
eq(a.items[cfg.rewards[7].itemId], before14, "taken back")
eq(DY.accounts[1].streak, 13, "no streak change on failure")
room = 1000
-- look text: title after a best streak of 30
DY.accounts[1].best = 30
local text = looks[#looks](a, b, nil, 1, "You see Char.")
assert(text:find("login streak title", 1, true), "look text with the title")
-- the login queue moves on when the client reports the window closed
local order = {}
ChaosLoginWindows.register("first", 10, function() return true end, function() order[#order + 1] = "first" end)
events = {}
registry["ChaosDailyLogout"].onLogout(c) -- a new session (the earlier logins' pending starts were dropped above)
registry["ChaosDailyLogin"].onLogin(c)
local e = events[1]
e.fn(table.unpack and table.unpack(e.args) or unpack(e.args))
eq(order[1], "first", "lower order first")
local count = #sent
call(c, "closed")
eq(#sent, count, "a 'closed' for another window does nothing")
ChaosLoginWindows.closed(c, "first")
eq(#sent, count + 1, "then the daily window")
eq(lastWindow().Login, 1, "as a login opening")
-- no login windows while on the tutorial island; its end starts the queue once (one start at a time)
registry["ChaosDailyLogout"].onLogout(c)
local onIsland = true
ChaosNewPlayer = {onTutorial = function() return onIsland end}
order, events = {}, {}
registry["ChaosDailyLogin"].onLogin(c)
eq(#events, 1, "start scheduled")
events[1].fn(table.unpack and table.unpack(events[1].args) or unpack(events[1].args))
eq(#order, 0, "nothing opens on the tutorial island")
eq(ChaosLoginWindows.state[c:getId()], nil, "no queue")
onIsland, events = false, {}
ChaosLoginWindows.start(c)
ChaosLoginWindows.start(c)
eq(#events, 1, "a second start while one is pending is ignored")
events[1].fn(table.unpack and table.unpack(events[1].args) or unpack(events[1].args))
eq(order[1], "first", "after the tutorial the queue opens")
ChaosNewPlayer = nil
print("daily_test: OK")
