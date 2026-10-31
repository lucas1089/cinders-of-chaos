-- Run from the server/ folder: luajit tests/weeklychest_test.lua (CI runs it with luajit and lua5.3)
-- The Weekly Chest (weeklychest_core.lua, weeklychest_config.lua, weeklychest.lua; server/README.md "The Weekly Chest
-- (O261)"): the config checks (storages, opcode 117 free, activity gates against the systems' own configs, reward limits
-- against the Ember Cache), the week (equal to the bounty board's), marking, the needed count with locked activities, the
-- chest and the bonus roll, rewards by level band, the storage round trip; then the engine on a mocked server: the four
-- hooks, the chest at 4 of 6, the bonus at 6 of 6, a locked-out player, a new week, the window and pt-BR.

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

dofile("data/scripts/chaos/chaos_constants.lua")
dofile("data/scripts/chaos/weeklychest_core.lua")
dofile("data/scripts/chaos/bounty_core.lua")
local K = ChaosWeeklyChestCore
local E = ChaosEmberCacheCore
local cfg = dofile("data/scripts/chaos/weeklychest_config.lua")
local ember = dofile("data/scripts/chaos/embercache_config.lua")

-- ---------------------------------------------------------------- config
eq(#K.validate(cfg), 0, "config valid: " .. table.concat(K.validate(cfg), "; "))
local bad = {storage = {base = 1, last = 2, a = 5}, activities = {{key = "a", level = 0}, {key = "a", level = 1}},
	stats = {x = "zz"}, need = 9, minNeed = 0, bands = {{min = 5, orbs = 0}}, chest = {hours = -1, items = {{id = 1, count = 0}}},
	bonus = {}, orbHours = {}}
check(#K.validate(bad) >= 8, "bad config found")

-- storages: the reserved block, in the README and in the constants
eq(cfg.storage.base, 7103020); eq(cfg.storage.last, 7103029)
eq(Chaos.storage.weeklyChest, cfg.storage.base, "storage in chaos_constants.lua")
local readme = io.open("README.md"):read("*a")
check(readme:find("7103020 - 7103029", 1, true) ~= nil, "storage block in the README")
check(readme:find("`weeklyChest`", 1, true) ~= nil, "opcode in the README table")

-- opcode 117: ours, unique, not one of the reference server's, the base client's or another module's
eq(ChaosOpcodes.weeklyChest, 117, "opcode 117"); eq(cfg.opcode, 117, "opcode in the config")
do
	local seen = {}
	for name, v in pairs(ChaosOpcodes) do
		check(seen[v] == nil, "opcode " .. v .. " used twice (" .. name .. ", " .. tostring(seen[v]) .. ")")
		seen[v] = name
	end
	for _, v in ipairs({1, 67, 73, 89, 91, 92, 99, 106, 107, 136, 181, 201, 202, 125, 126, 144, 145, 146, 210, 212, 213, 230, 246}) do
		check(v ~= 117, "117 is not an opcode of the reference server or client: " .. v)
	end
	local p = io.popen("grep -rlE '[Oo]pcode[A-Za-z_]*[ ]*=[ ]*117([^0-9]|$)|xtended[A-Za-z]*Opcode\\([ ]*117[^0-9]' "
		.. "data ../client/overlay/modules --include=*.lua 2>/dev/null")
	if p then
		for file in p:lines() do
			check(file:find("weeklychest", 1, true) or file:find("chaos_constants", 1, true) or file:find("_test.lua", 1, true),
				"opcode 117 named in " .. file)
		end
		p:close()
	end
end

-- activity gates equal the systems' own levels
do
	local function level(key)
		for _, a in ipairs(cfg.activities) do
			if a.key == key then return a.level end
		end
	end
	local rift = dofile("data/scripts/chaos/rift_config.lua")
	eq(level("rift"), rift.tiers[1].minLevel, "rift gate")
	eq(level("bounty"), dofile("data/scripts/chaos/bounty_config.lua").bands[1].min, "bounty gate")
	eq(level("waystone"), dofile("data/scripts/chaos/waystone_tiers_config.lua").tiers[1].level, "waystone gate")
	local inv = dofile("data/scripts/chaos/invasion_config.lua").minLevel
	check(level("boss") <= inv and level("boss") <= (Chaos.worldBoss and Chaos.worldBoss.minLevel or 300),
		"boss gate: the lowest of invasion and world boss")
	eq(level("boss"), inv, "boss gate is the invasion's")
	eq(Chaos.worldBoss and Chaos.worldBoss.minLevel, 300, "world boss minimum (a change here: check the gate)")
end
-- the bands are the bounty board's
do
	local bb = dofile("data/scripts/chaos/bounty_config.lua").bands
	for i = 2, #bb do
		eq(cfg.bands[i].min, bb[i].min, "band " .. i .. " starts where the bounty band does")
	end
	eq(#cfg.bands, #bb, "as many bands as the bounty board")
end
-- the rewards: limits in hours of hunting at every band, orb values as the Ember Cache's, under its top milestone
for id, h in pairs(cfg.orbHours) do
	local noted = {[29856] = 2, [29851] = 2, [32256] = 2, [32251] = 5, [29857] = 6, [24692] = 10}
	eq(math.floor(h * 60 + 0.5), noted[id], "orb " .. id .. " minutes as the Ember Cache notes")
end
for i, pt in ipairs(ember.income) do
	eq(cfg.income[i][1], pt[1], "income level " .. i); eq(cfg.income[i][2], pt[2], "income gold " .. i)
end
eq(#cfg.income, #ember.income, "income is the Ember Cache's")
for _, lv in ipairs({1, 8, 49, 50, 149, 150, 299, 300, 499, 500, 799, 800, 1500, 2500}) do
	local c = K.hours(cfg, lv, cfg.chest)
	check(c <= cfg.limits.chestHours, "chest hours at " .. lv .. ": " .. c)
	local worst = 0
	for i, def in ipairs(cfg.bonus) do
		local h = K.hours(cfg, lv, def)
		worst = math.max(worst, h)
		check(h <= cfg.limits.bonusHours, "bonus option " .. i .. " hours at " .. lv .. ": " .. h)
		check(h >= 0.25, "bonus option " .. i .. " is worth a roll at " .. lv)
	end
	check(c + worst <= cfg.limits.totalHours, "chest and bonus at " .. lv .. ": " .. (c + worst))
	check(c + worst < ember.tiers[#ember.tiers].hours + 0.6, "under the Ember Cache's top milestone at " .. lv)
end

-- ---------------------------------------------------------------- the week
local wed = realTime({year = 2026, month = 10, day = 14, hour = 12})
eq(K.week(wed, 6), 20261012, "week of Monday 12")
eq(K.week(realTime({year = 2026, month = 10, day = 12, hour = 5}), 6), 20261005, "Monday before 6: last week")
do
	local bcfg = dofile("data/scripts/chaos/bounty_config.lua")
	eq(cfg.resetHour, bcfg.rollHour, "same reset hour as the bounty board")
	for _, t in ipairs({wed, realTime({year = 2026, month = 10, day = 12, hour = 5}), realTime({year = 2026, month = 10, day = 12, hour = 6}),
			realTime({year = 2026, month = 10, day = 18, hour = 23}), realTime({year = 2026, month = 10, day = 19, hour = 5})}) do
		eq(K.week(t, cfg.resetHour), ChaosBounty.week(t, bcfg), "the bounty board's week at " .. os.date("%a %d %H", t))
	end
end

-- ---------------------------------------------------------------- marking and targets
local st = K.new()
check(K.roll(st, wed, cfg), "first roll starts the week"); check(not K.roll(st, wed, cfg), "same week")
eq(st.week, 20261012)
check(K.mark(st, cfg, "rift"), "rift marked"); check(not K.mark(st, cfg, "rift"), "once a week")
check(not K.mark(st, cfg, "nope"), "unknown activity")
check(K.isDone(st, cfg, "rift") and not K.isDone(st, cfg, "dungeon"), "bits")
eq(K.doneCount(st, cfg), 1)

-- needed counts by level: everything unlocked 4 of 6 and a bonus at 6; fewer unlocked, fewer needed, 2 at the least
local function tg(level) local t = K.targets(K.new(), cfg, level) return t.open, t.need, t.bonusNeed end
local o, n, b = tg(1200); eq(o, 6); eq(n, 4); eq(b, 6, "all six at 1200")
o, n, b = tg(300); eq(o, 5, "300: no waystone"); eq(n, 3, "3 of 5"); eq(b, 5, "bonus at 5 of 5")
o, n, b = tg(100); eq(o, 4, "100: rift, tower, boss, bounty"); eq(n, 2, "4 open, 2 locked: need 2")
o, n, b = tg(50); eq(o, 2, "50: boss and bounty (dungeon 150, rift and tower 100)"); eq(n, 2, "minimum 2"); eq(b, nil, "no bonus beyond the chest")
o, n, b = tg(8); eq(o, 1, "8: the bounty only"); eq(n, 1, "never more than there is"); eq(b, nil, "no bonus with one")
o, n, b = tg(30); eq(o, 2); eq(n, 2); eq(b, nil, "two open, two needed: no bonus roll beyond the chest")
-- an activity done below its gate still counts (the gate is a guess about the systems; the player did it)
do
	local s = K.new(); K.mark(s, cfg, "waystone")
	local t = K.targets(s, cfg, 300)
	eq(t.open, 6, "a done activity is open"); eq(t.need, 4)
end

-- due: the chest at the need, the bonus at all open; each once
do
	local s = K.new()
	for _, k in ipairs({"dungeon", "rift", "tower"}) do K.mark(s, cfg, k) end
	local d = K.due(s, cfg, 1200)
	check(not d.chest and not d.bonus, "3 of 6: nothing")
	K.mark(s, cfg, "bounty")
	d = K.due(s, cfg, 1200); check(d.chest and not d.bonus, "4 of 6: the chest")
	s.chest = 1
	d = K.due(s, cfg, 1200); check(not d.chest and not d.bonus, "the chest is given once")
	K.mark(s, cfg, "boss"); K.mark(s, cfg, "waystone")
	d = K.due(s, cfg, 1200); check(d.bonus and not d.chest, "6 of 6: the bonus roll")
	s.bonus = 1
	d = K.due(s, cfg, 1200); check(not d.bonus, "the bonus is given once")
	-- a level 300 player with five open: 3 of 5 chest, 5 of 5 bonus
	local p = K.new()
	for _, k in ipairs({"dungeon", "rift", "tower"}) do K.mark(p, cfg, k) end
	check(K.due(p, cfg, 300).chest, "level 300: 3 of 5 opens it")
	K.mark(p, cfg, "boss"); K.mark(p, cfg, "bounty")
	check(K.due(p, cfg, 300).bonus, "level 300: 5 of 5 adds the bonus roll")
end

-- ---------------------------------------------------------------- rewards
do
	local r1 = K.reward(cfg, 20, cfg.chest)
	eq(r1.gold, math.floor(1.0 * E.income(cfg.income, 20) + 0.5), "gold is hours of income")
	eq(r1.items[1].id, 29856); eq(r1.items[1].count, 2, "band 1 orbs x1")
	local r6 = K.reward(cfg, 1000, cfg.chest)
	eq(r6.items[1].count, 6, "band 6 orbs x3"); check(r6.gold > r1.gold * 100, "gold grows with the level")
	eq(K.bandOf(cfg, 1), 1); eq(K.bandOf(cfg, 49), 1); eq(K.bandOf(cfg, 50), 2); eq(K.bandOf(cfg, 5000), 6)
	eq(K.bonusOption(cfg, 0), 1); eq(K.bonusOption(cfg, 0.5), 2); eq(K.bonusOption(cfg, 0.999), 3); eq(K.bonusOption(cfg, 5), 3, "die clamped")
	eq(K.bonusOption(cfg, 0 / 0), 1, "NaN die")
	local nan = K.reward(cfg, 0 / 0, cfg.chest)
	check(nan.gold >= 0, "a NaN level pays something sane")
end

-- ---------------------------------------------------------------- storages
do
	local store = {}
	local s = {week = 20261012, done = 63, chest = 1, bonus = 1, chests = 7}
	K.save(cfg, s, function(off, v) store[off] = v; check(v >= 0 and v < 2 ^ 31, "int32 storage") end)
	local s2 = K.load(cfg, function(off) return store[off] or -1 end)
	eq(s2.week, 20261012); eq(s2.done, 63); eq(s2.chest, 1); eq(s2.bonus, 1); eq(s2.chests, 7)
	local empty = K.load(cfg, function() return -1 end)
	eq(empty.week, 0); eq(empty.done, 0, "unset storages are a fresh state")
end

-- ---------------------------------------------------------------- the view
do
	local s = K.new(); K.roll(s, wed, cfg); K.mark(s, cfg, "rift")
	local v = K.view(s, cfg, wed, 300, function(id) return id + 1, "orb " .. id end)
	eq(#v.acts, 6); eq(v.got, 1); eq(v.need, 3); eq(v.bonusNeed, 5)
	eq(v.acts[3].k, "waystone"); eq(v.acts[3].open, 0, "waystone locked at 300"); eq(v.acts[3].lv, 1100)
	eq(v.acts[2].done, 1); eq(v.chest.it[1].cid, 29857); eq(v.chest.it[1].name, "orb 29856")
	check(v.bonus.lo < v.bonus.hi, "the bonus gold range"); eq(v.endsIn, E.weekEndsIn(wed, 6))
end

-- ================================================================ weeklychest.lua on a mocked engine
MESSAGE_EVENT_ADVANCE, MESSAGE_INFO_DESCR, MESSAGE_STATUS_DEFAULT = 19, 20, 21
local registry, globals = {}, {}
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
local sent = {}
json = {encode = function(t) sent[#sent + 1] = t return "#" .. #sent end,
	decode = function(s) return {action = s} end}
function ItemType(id)
	return {getName = function() return "orb " .. id end, getClientId = function() return id + 1 end}
end
local online = {}
Game = {getPlayers = function() return online end}
local nextId = 0
local function mkPlayer(guid, level)
	nextId = nextId + 1
	local p = {id = nextId, guid = guid, level = level, st = {}, said = {}, bank = 0, items = {}, inbox = {}, full = false,
		events = {}, ops = {}}
	function p:getId() return self.id end
	function p:getGuid() return self.guid end
	function p:getName() return "P" .. self.guid end
	function p:getLevel() return self.level end
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

ChaosAchievements = {progress = function() return true end}
ChaosSeasonJourney = {emit = function() return true end}
ChaosTower = {recordRun = function() return true end}
ChaosWaystoneTiers = {startRun = function(area, serverId, mods) return 12 end}
local toasts = {}
ChaosNotify = {send = function(p, title, text) toasts[#toasts + 1] = {p = p, title = title, text = text} end}

dofile("data/scripts/chaos/i18n_core.lua")
dofile("data/scripts/chaos/weeklychest.lua")
local W = ChaosWeeklyChest
check(registry.ChaosWeeklyChestLogin and registry.ChaosWeeklyChestLogout and registry.ChaosWeeklyChestExtended, "events")
globals.ChaosWeeklyChestStartup.onStartup()

local a = mkPlayer(1, 1200)
registry.ChaosWeeklyChestLogin.onLogin(a)
check(a.events.ChaosWeeklyChestExtended and a.events.ChaosWeeklyChestLogout, "events registered at login")
eq(a.st[cfg.storage.base + cfg.storage.week], 20261012, "week stored at login")

-- the hooks: a counter by guid, the journey, the tower (a run without a floor does not count), a waystone's opener
ChaosAchievements.progress({guid = 1, name = "P1"}, "rift_runs", 1)
check(K.isDone(W.st[a:getId()], cfg, "rift"), "rift run")
ChaosAchievements.progress(a, "unknown_stat", 5)
ChaosAchievements.progress(99, "bounty_done", 1) -- offline guid: nothing, no error
ChaosSeasonJourney.emit(a, "descent_depth", 9, "max")
check(not K.isDone(W.st[a:getId()], cfg, "dungeon"), "a max counter is not an activity")
ChaosSeasonJourney.emit(a, "dungeon_clears", 1)
check(K.isDone(W.st[a:getId()], cfg, "dungeon"), "dungeon via the journey emit")
eq(a.said[#a.said]:find("Weekly Chest: 2 of 4", 1, true) ~= nil, true, "progress line: " .. tostring(a.said[#a.said]))
ChaosTower.recordRun(a, 0, 10)
check(not K.isDone(W.st[a:getId()], cfg, "tower"), "a tower run without a floor")
eq(ChaosWaystoneTiers.startRun({}, 1, {opener = 1}), 12, "the wrapped function still returns")
check(K.isDone(W.st[a:getId()], cfg, "waystone"), "waystone: the opener")
ChaosWaystoneTiers.startRun({}, 1, {})
ChaosWaystoneTiers.startRun({}, 1, nil)
eq(a.bank, 0, "nothing paid yet (3 of 6)"); eq(a.st[cfg.storage.base + cfg.storage.chest] ~= 1, true)

-- the fourth: the chest, once; the backpack full sends the items to the inbox
a.full = true
ChaosTower.recordRun(a, 5, 100)
local chest = K.reward(cfg, 1200, cfg.chest)
eq(a.bank, chest.gold, "chest gold to the bank")
eq(a.inbox[29856], chest.items[1].count, "chest orbs in the inbox")
check(toasts[#toasts].title == "Weekly Chest" and toasts[#toasts].text:find("opens", 1, true) ~= nil, "chest toast")
check(a.said[#a.said - 0]:find("inbox", 1, true) ~= nil, "told about the inbox")
eq(a.st[cfg.storage.base + cfg.storage.chest], 1, "chest flag stored"); eq(a.st[cfg.storage.base + cfg.storage.chests], 1)
a.full = false
local bank = a.bank
ChaosAchievements.progress(a, "rift_runs", 1)
eq(a.bank, bank, "a done activity counts once")
ChaosAchievements.progress(a, "bounty_done", 1)
eq(a.bank, bank, "the fifth: nothing yet")
ChaosAchievements.progress(a, "invasion_fought", 1) -- the sixth: the bonus roll
check(a.bank > bank, "bonus gold")
eq(a.st[cfg.storage.base + cfg.storage.bonus], 1, "bonus flag stored")
check(toasts[#toasts].text:find("Bonus roll", 1, true) ~= nil, "bonus toast: " .. tostring(toasts[#toasts].text))
local after = a.bank
ChaosAchievements.progress(a, "wb_kills", 1)
eq(a.bank, after, "no second chest or bonus")
-- the window
registry.ChaosWeeklyChestExtended.onExtendedOpcode(a, 117, "open")
local last = sent[#sent]
eq(last.action, "state"); eq(last.data.shown, 1, "opened"); eq(last.data.open, 6, "open stays the activity count"); eq(last.data.got, 6); eq(last.data.chest.given, 1)
eq(a.ops[#a.ops].op, 117, "sent on 117")
local n0 = #sent
registry.ChaosWeeklyChestExtended.onExtendedOpcode(a, 118, "open")
eq(#sent, n0, "other opcode ignored")

-- a low level: two activities open, two needed
local low = mkPlayer(2, 40)
registry.ChaosWeeklyChestLogin.onLogin(low)
ChaosAchievements.progress(low, "bounty_done", 1)
eq(low.bank, 0, "one of two")
ChaosAchievements.progress(low, "invasion_fought", 1)
check(low.bank > 0, "two of the two he can do open the chest")
eq(low.st[cfg.storage.base + cfg.storage.bonus] ~= 1, true, "no bonus beyond the chest at two open activities")

-- tester characters earn nothing
Chaos.isTesterGuid = function(g) return g == 3 end
local tbot = mkPlayer(3, 1200)
registry.ChaosWeeklyChestLogin.onLogin(tbot)
ChaosAchievements.progress(tbot, "rift_runs", 1)
check(not K.isDone(W.st[tbot:getId()], cfg, "rift"), "a tester bot is not counted")
Chaos.isTesterGuid = nil

-- logout and a new week: the state is saved and the week empties
clock = clock + 600
registry.ChaosWeeklyChestLogout.onLogout(a)
eq(W.st[a:getId()], nil, "memory freed")
clock = realTime({year = 2026, month = 10, day = 19, hour = 7}) -- the next Monday after the reset
registry.ChaosWeeklyChestLogin.onLogin(a)
eq(W.st[a:getId()].week, 20261019, "new week"); eq(W.st[a:getId()].done, 0, "week emptied")
eq(W.st[a:getId()].chests, 1, "chests given in all are kept")
local b0 = a.bank
ChaosAchievements.progress(a, "rift_runs", 1)
eq(a.bank, b0, "new week counts again, not paid at 1")
-- pt-BR
Chaos.setLang(a, "pt-BR")
ChaosAchievements.progress(a, "bounty_done", 1)
check(a.said[#a.said]:find("atividades", 1, true), "pt-BR progress: " .. tostring(a.said[#a.said]))
for _, key in ipairs({"Weekly Chest: %d of %d activities done this week.", "The Weekly Chest opens: %s",
		"Bonus roll for every activity of the week: %s"}) do
	check(ChaosI18n and ChaosI18n.strings and ChaosI18n.strings["pt-BR"] and ChaosI18n.strings["pt-BR"][key], "pt-BR entry: " .. key)
end

-- the levels shared with the top menu's unlock table (O259) are the same
do
	local ok, U = pcall(dofile, "data/scripts/chaos/unlocks_config.lua")
	check(ok and type(U) == "table" and U.entries, "unlocks_config.lua loads")
	local menu = {}
	for _, e in ipairs(ok and U.entries or {}) do
		menu[e.key] = e.level
	end
	for _, a in ipairs(cfg.activities) do
		local k = ({dungeon = "dungeons", rift = "rifts", tower = "tower"})[a.key]
		if k then
			eq(a.level, menu[k], "activity " .. a.key .. " level matches unlocks_config " .. k)
		end
	end
end

print(string.format("weeklychest_test: %d checks, %d failures", checks, failures))
os.exit(failures == 0 and 0 or 1)
