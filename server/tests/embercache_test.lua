-- Run from the server/ folder: luajit tests/embercache_test.lua (CI runs it with luajit and lua5.3)
-- The Ember Cache, the Daily Spark and the day book (embercache_core.lua, daybook_core.lua, embercache_config.lua,
-- embercache.lua; server/README.md "Ember Cache, Daily Spark and the day book"): the config checks, days and weeks,
-- kills per point and the daily caps, the double first points, the Spark, the milestones, rewards by level, storages
-- round trip, the day book's big numbers; then the engine on a mocked server: party kill credit (each kill once),
-- achievement and journey counters, the tower, hunt tracker loot and supplies, rewards to the bank and the inbox,
-- a new day at login with the recap, the window state and the pt-BR keys.

local checks, failures = 0, 0
local function check(cond, label)
	checks = checks + 1
	if not cond then
		failures = failures + 1
		print("FAIL " .. label)
	end
end
local function eq(a, b, label)
	check(a == b, tostring(label or "check") .. " (" .. tostring(a) .. " ~= " .. tostring(b) .. ")")
end

local realTime = os.time
local clock = realTime({year = 2026, month = 10, day = 14, hour = 12}) -- a Wednesday
os.time = function(t)
	if t then return realTime(t) end
	return clock
end
local mclock = 1000000
os.mtime = function() return mclock end

dofile("data/scripts/chaos/embercache_core.lua")
dofile("data/scripts/chaos/daybook_core.lua")
local K = ChaosEmberCacheCore
local D = ChaosDayBookCore
local cfg = dofile("data/scripts/chaos/embercache_config.lua")

-- ---------------------------------------------------------------- config
eq(#K.validate(cfg), 0, "config valid: " .. table.concat(K.validate(cfg), "; "))
check(cfg.storage.base == 7102700 and cfg.storage.last == 7102719, "cache block")
check(cfg.daybook.base == 7102720 and cfg.daybook.last == 7102739, "day book block")
for k, off in pairs(cfg.daybook) do
	if k ~= "base" and k ~= "last" then
		check(cfg.daybook.base + off <= cfg.daybook.last, "day book offset in block: " .. k)
	end
end
for _, key in ipairs(cfg.order) do
	check(cfg.sources[key] ~= nil, "ordered source exists: " .. key)
end
local bad = {storage = {base = 1, last = 2, a = 0, b = 0, capBase = 5}, capped = {"x"}, sources = {y = {cap = 1}},
	stats = {s = {"zz", 1}}, tiers = {{points = 5}, {points = 5}}}
check(#K.validate(bad) >= 5, "bad config found")

-- ---------------------------------------------------------------- days and weeks
local wed = realTime({year = 2026, month = 10, day = 14, hour = 12})
eq(K.day(wed, 6), 20261014, "day"); eq(K.week(wed, 6), 20261012, "week of Monday 12")
eq(K.week(realTime({year = 2026, month = 10, day = 12, hour = 5}), 6), 20261005, "Monday before 6: last week")
eq(K.dayEndsIn(realTime({year = 2026, month = 10, day = 14, hour = 5}), 6), 3600, "an hour to the day's end")
eq(K.weekEndsIn(realTime({year = 2026, month = 10, day = 19, hour = 5}), 6), 3600, "an hour to the week's end")

-- ---------------------------------------------------------------- points
local st = K.new()
local nd, nw = K.roll(st, wed, cfg)
check(nd and nw, "first roll: new day and week")
eq(K.addUnits(st, cfg, "kill", 19), 0, "19 kills: no point yet"); eq(st.killRest, 19, "kept")
eq(K.addUnits(st, cfg, "kill", 1), 1, "the 20th kill"); eq(st.killRest, 0)
eq(K.addUnits(st, cfg, "kill", 5000), 59, "kill cap 60 a day"); eq(K.addUnits(st, cfg, "kill", 100), 0, "capped")
eq(K.addUnits(st, cfg, "dungeon", 1), 12, "a dungeon"); eq(K.addUnits(st, cfg, "nope", 1), 0, "unknown source")
eq(K.addUnits(st, cfg, "craft", 20), 15, "craft cap"); eq(K.addUnits(st, cfg, "elite", 3), 3, "elite")
eq(K.addUnits(st, cfg, "rift", -1), 0, "negative")

st = K.new(); K.roll(st, wed, cfg)
local r = K.addPoints(st, cfg, 10)
eq(r.counted, 20, "first points double"); check(not r.spark, "no spark at 20")
r = K.addPoints(st, cfg, 10)
eq(r.counted, 20, "still double"); check(r.spark, "spark at 40 >= 30"); eq(st.weekSparks, 1)
r = K.addPoints(st, cfg, 30)
eq(r.counted, 50, "20 left of the bonus: 30 + 20"); check(not r.spark, "one spark a day")
r = K.addPoints(st, cfg, 40)
eq(r.counted, 40, "bonus spent"); eq(st.weekPoints, 130); eq(#r.tiers, 1, "first milestone"); eq(r.tiers[1], 1)
r = K.addPoints(st, cfg, 500)
eq(#r.tiers, 2, "two milestones at once"); eq(st.tiersGiven, 3)
r = K.addPoints(st, cfg, 500)
eq(#r.tiers, 0, "no more milestones")
eq(K.addPoints(st, cfg, 0).counted, 0, "nothing")
-- next day keeps the week, next week empties it
nd, nw = K.roll(st, wed + 86400, cfg)
check(nd and not nw, "a new day"); eq(st.dayRaw, 0); eq(st.spark, 0); check(st.weekPoints > 0, "week kept")
nd, nw = K.roll(st, wed + 6 * 86400, cfg)
check(nw, "a new week"); eq(st.weekPoints, 0); eq(st.tiersGiven, 0)

-- income and rewards (hours of hunting gold)
eq(K.income(cfg.income, 100), 402000, "income at 100"); eq(K.income(cfg.income, 1), 21000, "flat before")
eq(K.income(cfg.income, 200), 695000, "between 100 and 300"); eq(K.income(cfg.income, 5000), 10662000, "flat after")
eq(K.income({}, 5), 0, "no table")
eq(K.gold(cfg.daily.reward, 100, cfg.income), 60300, "Spark at 100: 0.15 h")
eq(K.gold(cfg.tiers[3], 1000, cfg.income), 36250800, "milestone 3 at 1000: 3.4 h")
eq(K.gold({goldPerLevel = 5}, 0), 5, "the old per-level form, level at least 1")
eq(K.gold({hours = 1, goldMax = 10}, 100, cfg.income), 10, "cap")
-- the Spark is 10-15 minutes, the milestones about 1 / 2 / 4 hours: the gold share plus the orbs (orbs found per hour
-- of a median hunt, as in the config's comment)
local ORBS_PER_HOUR = {[29856] = 1.5, [29851] = 1.5, [32256] = 1.5, [32251] = 0.6, [29857] = 0.5, [24692] = 0.3}
local function hoursOf(r)
	local h = r.hours
	for _, it in ipairs(r.items) do
		check(ORBS_PER_HOUR[it.id] ~= nil, "a known orb " .. it.id)
		h = h + it.count * 0.05 / (ORBS_PER_HOUR[it.id] or 1)
	end
	return h
end
local sparkH = hoursOf(cfg.daily.reward)
check(sparkH >= 10 / 60 and sparkH <= 15 / 60, "Spark 10-15 min: " .. sparkH)
for i, want in ipairs({1, 2, 4}) do
	local h = hoursOf(cfg.tiers[i])
	check(h >= want * 0.9 and h <= want * 1.1, "milestone " .. i .. " about " .. want .. " h: " .. h)
end

-- storages
local store = {}
st = K.new(); K.roll(st, wed, cfg); K.addUnits(st, cfg, "kill", 45); K.addUnits(st, cfg, "craft", 3)
K.addPoints(st, cfg, 5)
K.save(cfg, st, function(off, v) store[off] = v end)
local back = K.load(cfg, function(off) return store[off] or -1 end)
for _, f in ipairs({"week", "weekPoints", "tiersGiven", "weekSparks", "day", "dayPoints", "dayRaw", "spark", "killRest"}) do
	eq(back[f], st[f], "round trip " .. f)
end
eq(back.caps.kill, 2, "cap kill kept"); eq(back.caps.craft, 3, "cap craft kept")
eq(K.load(cfg, function() return -1 end).weekPoints, 0, "unset storages: zero")

local v = K.view(st, cfg, wed, 100, function(id) return id + 1, "n" .. id end)
eq(#v.week.tiers, 3); eq(v.week.tiers[1].it[1][1], 29857, "client id (Upheaval + 1)"); eq(v.day.goal, cfg.daily.goal)
eq(#v.src, #cfg.order, "every source listed"); eq(v.src[1][1], "kill")

-- ---------------------------------------------------------------- day book core
local hi, lo = D.split(4500000000123)
eq(hi, 4500); eq(lo, 123); eq(D.join(hi, lo), 4500000000123, "big round trip"); eq(D.join(-1, -1), 0, "unset")
eq(D.short(999), "999"); eq(D.short(1234), "1.2k"); eq(D.short(1000000), "1M"); eq(D.short(2500000000), "2.5B")
eq(D.short(123456789), "123M"); eq(D.date(20261014), "2026-10-14")
local b = D.new(20261014, 10)
check(not D.used(b), "empty"); D.add(b, "xp", 3000000000); D.add(b, "kills", 2); D.add(b, "nope", 1); D.add(b, "kills", -5)
check(D.used(b), "used"); eq(b.kills, 2)
store = {}
D.save(cfg, b, function(off, val) store[off] = val; check(val >= 0 and val < 2 ^ 31, "int32 storage") end)
local b2 = D.load(cfg, function(off) return store[off] or -1 end)
eq(b2.xp, 3000000000, "xp round trip"); eq(b2.levelStart, 10)
local old, new = D.roll(b2, 20261015, 12)
eq(old, b2, "old book handed back"); eq(new.levelStart, 12); eq(new.xp, 0)
old = D.roll(new, 20261015, 12)
eq(old, nil, "same day")
local bv = D.view(b2, 15, 60)
eq(bv.lv, 5, "levels gained"); eq(bv.secs, 60, "live seconds")

-- ================================================================ embercache.lua on a mocked engine
MESSAGE_EVENT_ADVANCE, MESSAGE_INFO_DESCR = 19, 20
local registry, globals, callbacks = {}, {}, {}
function CreatureEvent(name)
	local o = {name = name}
	function o:type(t) self.t = t end
	function o:register() registry[name] = self end
	return o
end
function GlobalEvent(name)
	local o = {name = name}
	function o:interval() end
	function o:register() globals[name] = self end
	return o
end
EventCallback = setmetatable({}, {__newindex = function(t, k, fn) rawset(t, k, fn) end})
function EventCallback:register(index) callbacks[#callbacks + 1] = {index = index, fn = rawget(EventCallback, "onGainExperience")} end
local sent = {}
json = {encode = function(t) sent[#sent + 1] = t return "#" .. #sent end,
	decode = function(s) return {action = s} end}
function ItemType(id)
	return {getName = function() return "orb " .. id end, getClientId = function() return id + 1 end}
end

local online = {}
Game = {getPlayers = function() return online end}
local nextId = 0
local function mkPlayer(guid, level, pos)
	nextId = nextId + 1
	local p = {id = nextId, guid = guid, level = level, pos = pos or {x = 100, y = 100, z = 7}, st = {}, said = {},
		bank = 0, items = {}, inbox = {}, full = false, events = {}, ops = {}}
	function p:getId() return self.id end
	function p:getGuid() return self.guid end
	function p:getName() return "P" .. self.guid end
	function p:getLevel() return self.level end
	function p:getPosition() return self.pos end
	function p:isPlayer() return true end
	function p:getParty() return self.party end
	function p:getStorageValue(k) return self.st[k] or -1 end
	function p:setStorageValue(k, val) self.st[k] = val end
	function p:sendTextMessage(t, m) self.said[#self.said + 1] = m end
	function p:getBankBalance() return self.bank end
	function p:setBankBalance(val) self.bank = val end
	function p:addItem(id, n) if self.full then return nil end self.items[id] = (self.items[id] or 0) + n return {} end
	function p:getInbox() local me = self return {addItem = function(_, id, n) me.inbox[id] = (me.inbox[id] or 0) + n return true end} end
	function p:registerEvent(n) self.events[n] = true end
	function p:sendExtendedOpcode(op, s) self.ops[#self.ops + 1] = {op = op, msg = s} end
	online[#online + 1] = p
	return p
end
local function monster(id, pos)
	return {getId = function() return id end, isMonster = function() return true end, getMaster = function() return nil end,
		getPosition = function() return pos or {x = 100, y = 100, z = 7} end}
end

ChaosAchievements = {progress = function() return true end}
ChaosSeasonJourney = {emit = function() return true end}
ChaosTower = {recordRun = function() return true end}
ChaosHunt = {sessions = {}, addLoot = function() return 500 end, addSupply = function() return 70 end}
local toasts = {}
ChaosNotify = {send = function(p, title, text) toasts[#toasts + 1] = {p = p, title = title, text = text} end}

dofile("data/scripts/chaos/chaos_constants.lua")
dofile("data/scripts/chaos/i18n_core.lua")
dofile("data/scripts/chaos/embercache.lua")
local E = ChaosEmberCache
check(registry.ChaosEmberCacheKill and registry.ChaosEmberCacheLogin and registry.ChaosEmberCacheExtended, "events")
eq(callbacks[1].index, cfg.expIndex, "experience callback index")
globals.ChaosEmberCacheStartup.onStartup()
eq(ChaosOpcodes.emberCache, 174, "opcode in ChaosOpcodes")

local a = mkPlayer(1, 100)
local bp = mkPlayer(2, 50, {x = 105, y = 100, z = 7})
local far = mkPlayer(3, 50, {x = 900, y = 100, z = 7})
local party = {getMembers = function() return {bp, far} end, getLeader = function() return a end}
a.party, bp.party, far.party = party, party, party
for _, p in ipairs({a, bp, far}) do registry.ChaosEmberCacheLogin.onLogin(p) end
check(a.events.ChaosEmberCacheKill and a.events.ChaosEmberCacheExtended, "events registered at login")

-- 20 kills: a point for the killer and the near member, none for the far one; a kill seen twice counts once
for i = 1, 20 do
	registry.ChaosEmberCacheKill.onKill(a, monster(1000 + i))
	registry.ChaosEmberCacheKill.onKill(bp, monster(1000 + i)) -- the engine runs kill for the most damage too
end
eq(E.st[a:getId()].dayPoints, 2, "20 kills: 1 point, doubled"); eq(E.st[bp:getId()].dayPoints, 2, "party member near")
eq(E.st[far:getId()].dayPoints, 0, "far member"); eq(E.book[a:getId()].kills, 20, "kills in the day book")
eq(a.st[cfg.storage.base + cfg.storage.dayPoints], 2, "written to the storage")

-- counters: a rift run (12 -> 24) lights the Spark for the online player by guid
ChaosAchievements.progress({guid = 1, name = "P1"}, "rift_runs", 1)
eq(E.st[a:getId()].dayPoints, 26, "rift run"); eq(E.st[a:getId()].spark, 0, "no spark under the goal")
ChaosAchievements.progress(a, "unknown_stat", 5)
eq(E.st[a:getId()].dayPoints, 26, "unknown counter ignored")
ChaosAchievements.progress(99, "rift_runs", 1) -- offline guid: nothing, no error
ChaosSeasonJourney.emit(a, "dungeon_clears", 1)
eq(E.st[a:getId()].dayPoints, 50, "dungeon via the journey emit (12 doubled)")
eq(E.st[a:getId()].spark, 1, "spark lit"); eq(a.bank, K.gold(cfg.daily.reward, 100, cfg.income), "spark gold to the bank")
eq(a.items[29851], 1, "spark orb"); check(#toasts == 1 and toasts[1].title == "Daily Spark", "spark toast")
ChaosSeasonJourney.emit(a, "descent_depth", 9, "max")
eq(E.st[a:getId()].dayPoints, 50, "a max counter is not an activity")
ChaosTower.recordRun(a, 0, 10)
eq(E.st[a:getId()].dayPoints, 50, "a tower run without a floor")
ChaosTower.recordRun(a, 5, 100)
eq(E.st[a:getId()].dayPoints, 66, "tower run (8, doubled)")
-- the first milestone: the backpack is full, the items go to the inbox
a.full = true
local bankBefore = a.bank
E.credit(a, "worldboss", 5) -- 75 raw, 7 left of the bonus: 82 -> 148
eq(E.st[a:getId()].tiersGiven, 1, "milestone 1")
eq(a.bank - bankBefore, K.gold(cfg.tiers[1], 100, cfg.income), "milestone gold"); eq(a.inbox[29856], 1, "milestone items in the inbox")
check(a.said[#a.said]:find("inbox", 1, true) ~= nil, "told about the inbox")
a.full = false

-- the hunt tracker feeds the day book
local sess = {}
ChaosHunt.sessions[1] = sess
ChaosHunt.addLoot(sess, {x = {n = 2, o = true}, y = {n = 1, u = true}, z = {n = 3, r = 4}, w = {n = 5}})
eq(E.book[a:getId()].loot, 500, "loot gold"); eq(E.book[a:getId()].orbs, 2); eq(E.book[a:getId()].uniques, 1)
eq(E.book[a:getId()].rares, 3, "items with a rarity")
ChaosHunt.addSupply(sess, 2268, 5, 10)
eq(E.book[a:getId()].sup, 70, "supplies")
callbacks[1].fn(a, nil, 12345, 12345)
eq(E.book[a:getId()].xp, 12345, "experience")
registry.ChaosEmberCacheDeath.onDeath(a)
eq(E.book[a:getId()].deaths, 1, "death")

-- the window
registry.ChaosEmberCacheExtended.onExtendedOpcode(a, 174, "open")
local last = sent[#sent]
eq(last.action, "state"); eq(last.data.open, 1, "opened"); eq(last.data.week.got, 1); eq(last.data.book.kills, 20)
eq(a.ops[#a.ops].op, 174, "sent on 174")
local n = #sent
registry.ChaosEmberCacheExtended.onExtendedOpcode(a, 175, "open")
eq(#sent, n, "other opcode ignored")

-- logout, a day later login: the recap, a fresh book, the week kept
clock = clock + 600
registry.ChaosEmberCacheLogout.onLogout(a)
eq(E.st[a:getId()], nil, "memory freed")
local secs = a.st[cfg.daybook.base + cfg.daybook.seconds]
eq(secs, 600, "time played saved")
clock = clock + 86400
toasts = {}
registry.ChaosEmberCacheLogin.onLogin(a)
check(#toasts == 1 and toasts[1].title == "Day book", "recap toast")
check(toasts[1].text:find("20 kills", 1, true) ~= nil, "recap text: " .. tostring(toasts[1] and toasts[1].text))
eq(E.book[a:getId()].kills, 0, "fresh day book"); eq(E.st[a:getId()].weekPoints, 148, "week kept")
eq(E.st[a:getId()].dayPoints, 0, "day emptied")
-- pt-BR
Chaos.setLang(a, "pt-BR")
E.credit(a, "rift", 1)
E.credit(a, "rift", 1) -- 48 counted: spark in pt-BR
check(a.said[#a.said]:find("aceso", 1, true) ~= nil, "pt-BR spark text: " .. tostring(a.said[#a.said]))

-- ---------------------------------------------------------------- the junk orb offering (beta 2026-10-20)
do
	local o = cfg.offering
	eq(#K.validate(cfg), 0, "config valid with the offering source")
	-- the plan: whole points, the day's room, the configured order
	local plan = K.offerPlan(cfg, {[29856] = 1500, [29851] = 400, [32256] = 7, [99] = 50}, 0)
	eq(plan.carried, 1907, "only the junk orbs count")
	eq(plan.points, cfg.sources.offering.cap, "capped at the day's room")
	eq(plan.orbs, cfg.sources.offering.cap * o.perPoint, "orbs taken = points x perPoint")
	eq(#plan.take, 1, "Upheaval first, enough of them")
	eq(plan.take[1].id, 29856); eq(plan.take[1].n, plan.orbs)
	plan = K.offerPlan(cfg, {[29856] = 5, [29851] = 4, [32256] = 7}, 0)
	eq(plan.points, 1, "16 orbs: one point"); eq(plan.orbs, 10)
	eq(plan.take[1].n, 5); eq(plan.take[2].n, 4); eq(plan.take[3].n, 1)
	plan = K.offerPlan(cfg, {[29856] = 9}, 0)
	eq(plan.points, 0, "under a point: nothing"); eq(#plan.take, 0)
	plan = K.offerPlan(cfg, {[29856] = 1000}, cfg.sources.offering.cap - 3)
	eq(plan.points, 3, "the rest of the day's room"); eq(plan.room, 3)
	plan = K.offerPlan(cfg, {[29856] = 1000}, cfg.sources.offering.cap)
	eq(plan.points, 0, "room used up")
	plan = K.offerPlan(cfg, {[29856] = -5, [29851] = 0 / 0}, 0)
	eq(plan.points, 0, "bad counts are nothing")

	-- the engine: a backpack with junk orbs (one stack locked, one in a bag), the quote, the offer
	local function stack(id, count, extra)
		local it = {id = id, count = count, attrs = extra or {}}
		function it:getId() return self.id end
		function it:getCount() return self.count end
		function it:getCustomAttribute(k) return self.attrs[k] end
		function it:isContainer() return false end
		function it:isStoreItem() return false end
		function it:remove(k)
			k = k or self.count
			if k > self.count then return false end
			self.count = self.count - k
			return true
		end
		return it
	end
	local function bag(items)
		local b = {items = items}
		function b:getSize() return #self.items end
		function b:getItem(i) return self.items[i + 1] end
		function b:isContainer() return true end
		function b:getId() return 1988 end
		function b:getCount() return 1 end
		function b:getCustomAttribute() return nil end
		function b:isStoreItem() return false end
		return b
	end
	local u1, u2, aw, locked = stack(29856, 100), stack(29856, 45), stack(29851, 30), stack(29856, 100, {chaos_locked = 1})
	local other = stack(29857, 100)
	local inner = bag({aw})
	local o2 = mkPlayer(9, 600)
	function o2:getSlotItem(slot) return slot == (CONST_SLOT_BACKPACK or 3) and bag({u1, locked, other, inner, u2}) or nil end
	registry.ChaosEmberCacheLogin.onLogin(o2)
	sent = {}
	registry.ChaosEmberCacheExtended.onExtendedOpcode(o2, 174, "offerQuote")
	local q = sent[#sent]
	eq(q and q.action, "offer", "the quote answers")
	eq(q.data.carried, 175, "locked orbs and other orbs do not count")
	eq(q.data.points, 17, "175 orbs: 17 points"); eq(q.data.orbs, 170)
	eq(u1.count, 100, "a quote takes nothing")
	local before = E.st[o2:getId()].weekPoints
	registry.ChaosEmberCacheExtended.onExtendedOpcode(o2, 174, "offer")
	eq(u1.count + u2.count + aw.count, 5, "170 orbs left the backpack")
	eq(locked.count, 100, "the locked stack stays"); eq(other.count, 100, "other orbs stay")
	eq(E.st[o2:getId()].dayRaw, 17, "17 raw points")
	eq(E.st[o2:getId()].weekPoints - before, 34, "doubled by the day's bonus like any point")
	eq(E.st[o2:getId()].caps.offering, 17, "the day's offering cap counts")
	eq(o2.st[cfg.storage.base + cfg.storage.capBase + 3], 17, "the cap is saved in its storage")
	check(o2.said[#o2.said]:find("170 junk orbs", 1, true) ~= nil, "told: " .. tostring(o2.said[#o2.said]))
	-- again: 5 left, not a point; nothing taken, told why
	registry.ChaosEmberCacheExtended.onExtendedOpcode(o2, 174, "offer")
	eq(u1.count + u2.count + aw.count, 5, "under a point: nothing taken")
	check(o2.said[#o2.said]:find("at least 10", 1, true) ~= nil, "told why")
	-- the day's cap: a full room refuses
	u1.count = 2000
	registry.ChaosEmberCacheExtended.onExtendedOpcode(o2, 174, "offer")
	eq(E.st[o2:getId()].caps.offering, cfg.sources.offering.cap, "filled up to the cap")
	eq(u1.count, 2000 - (cfg.sources.offering.cap - 17) * o.perPoint, "only the room's orbs taken")
	local left = u1.count
	registry.ChaosEmberCacheExtended.onExtendedOpcode(o2, 174, "offer")
	eq(u1.count, left, "cap reached: nothing taken")
	check(o2.said[#o2.said]:find("today", 1, true) ~= nil, "told the day is full")
	-- a new day: room again
	clock = clock + 86400
	registry.ChaosEmberCacheExtended.onExtendedOpcode(o2, 174, "offer")
	eq(u1.count, left - cfg.sources.offering.cap * o.perPoint, "the next day takes again")
end

-- ---------------------------------------------------------------- pt-BR keys of embercache.lua
local strings = dofile("data/scripts/chaos/i18n_strings.lua")["pt-BR"]
local fh = io.open("data/scripts/chaos/embercache.lua", "r")
local src = fh:read("*a")
fh:close()
local keys = 0
for key in src:gmatch('Chaos%.t%(player,%s*"([^"]+)"') do
	keys = keys + 1
	check(strings[key] ~= nil, "pt-BR for: " .. key)
end
for key in src:gmatch('toast%(player, "([^"]+)"') do
	keys = keys + 1
	check(strings[key] ~= nil, "pt-BR for title: " .. key)
end
check(keys >= 8, "keys found: " .. keys)

print(string.format("embercache_test: %d checks, %d failures", checks, failures))
if failures > 0 then
	os.exit(1)
end
