-- Run from the server/ folder: luajit tests/milestones_test.lua (or lua5.3; CI runs both)
-- Level milestones (O378; milestones_core.lua, milestones_config.lua, milestones.lua; server/README.md "Level milestones
-- (O378)"). Checks: the config against achievements_data.lua (15 milestones 800-2200, a titled level achievement in
-- category "milestones" each), the cosmetics, the storage block, the caches (small against hunting), the plan (login
-- baseline, live advance, a jump, staff, a death and the way back), the toast and the Next Goals lines; then
-- milestones.lua on a mocked engine: login, advance, cache, toast, broadcast, inbox. All data is synthetic.
local n = 0
setmetatable(_G, {__index = function(t, k)
	if type(k) == "string" and k:match("^[A-Z_0-9]+$") then n = n + 1; rawset(t, k, n); return n end
end})
SKILL_LEVEL = 8

local failures, count = 0, 0
local function check(cond, label)
	count = count + 1
	if not cond then
		failures = failures + 1
		print("FAIL " .. label)
	end
end
local function eq(a, b, label)
	check(a == b, label .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end
local function readFile(path)
	local f = io.open(path, "r")
	if not f then return nil end
	local s = f:read("*a")
	f:close()
	return s
end

dofile("data/scripts/chaos/milestones_core.lua")
local K = ChaosMilestonesCore
local cfg = dofile("data/scripts/chaos/milestones_config.lua")
local ach = dofile("data/scripts/chaos/achievements_data.lua")

-- ---------------------------------------------------------------- config
local problems = K.validate(cfg, ach)
eq(#problems, 0, "config validates: " .. table.concat(problems, "; "))
eq(#cfg.list, 15, "15 milestones")
eq(cfg.list[1].level, 800, "first 800") eq(cfg.list[#cfg.list].level, 2200, "last 2200")
do
	local titles = {}
	for _, m in ipairs(cfg.list) do
		local t = K.titleOf(ach, m.level)
		check(t ~= nil and #t <= 24, "level " .. m.level .. " title fits a name plate")
		check(t and not titles[t], "level " .. m.level .. " title unique")
		titles[t or ""] = true
	end
	-- no other achievement has one of these titles
	for _, a in ipairs(ach.list) do
		if a.title and a.cat ~= "milestones" then
			check(not titles[a.title], "title " .. a.title .. " only once")
		end
	end
	eq(ach.categoryRewards.milestones.title, "Hundredfold", "category title")
	check(not titles.Hundredfold, "category title is not a milestone title")
	-- every level achievement from 800 is a milestone; the ones below stay in Combat & Leveling
	for _, a in ipairs(ach.list) do
		if a.stat == "level" then
			eq(a.cat, a.target >= 800 and "milestones" or "combat", a.id .. " category")
		end
	end
end
-- bad configs are reported
check(#K.validate({list = {{level = 800, cache = {1}, challenge = {stat = "tower_floor", target = 5}},
	{level = 950, cache = {0}, challenge = {stat = "tower_floor", target = 4}}}, first = 800, last = 950, step = 100,
	orbs = {{id = 1, name = "x"}}}) >= 3, "gap, shrinking cache, falling challenge")
check(#K.validate({list = {{level = 800, cache = {1}, challenge = {stat = "x", target = 1}}}, first = 800, last = 800,
	step = 100, orbs = {{id = 1, name = "x"}}}) >= 1, "unknown challenge stat")
check(#K.validate(cfg, {list = {}}) >= 15, "missing achievements")

-- the cosmetics: a level-up effect at 1000 / 1500 / 2000 and a cosmetic for the whole category, never sold
do
	local cos = dofile("data/scripts/chaos/cosmetics_config.lua")
	local byAch, cat = {}, nil
	for _, c in ipairs(cos.cosmetics) do
		if c.source == "achievement" and c.achievement then byAch[c.achievement] = c end
		if c.category == "milestones" then cat = c end
	end
	for _, l in ipairs({1000, 1500, 2000}) do
		local c = byAch["level_" .. l]
		check(c and c.kind == "levelfx" and c.price == nil, "level " .. l .. ": a level-up effect, not sold")
	end
	check(cat and cat.price == nil, "the category gives a cosmetic")
end

-- storage block and the README
eq(cfg.storage, 7101080, "storage 7101080")
do
	local readme = readFile("README.md") or ""
	check(readme:find("| 7101080 - 7101089 |", 1, true) ~= nil, "README storage table names the block")
	check(readme:find("Level milestones (O378)", 1, true) ~= nil, "README section")
	-- no other script uses the key
	local p = io.popen("grep -l 7101080 data/scripts/chaos/*.lua data/lib/*.lua 2>/dev/null")
	for file in p:lines() do
		check(file:find("milestones_config", 1, true) ~= nil or file:find("chaos_constants", 1, true) ~= nil, "7101080 only in milestones_config.lua (and the block comment of chaos_constants.lua): " .. file)
	end
	p:close()
end

-- the caches stay small: under a tenth of the orbs hunted from 800 to 2200 (about 290 hours; per hour about 4 Upheaval,
-- 2 Fate, 0.4 Grafting at the normal tier)
do
	local sum = {0, 0, 0}
	for _, m in ipairs(cfg.list) do
		for i = 1, 3 do sum[i] = sum[i] + m.cache[i] end
		check(m.cache[1] >= 5, m.level .. ": at least the level 700 reward")
	end
	local hunted = {4 * 290, 2 * 290, 0.4 * 290}
	for i = 1, 3 do
		check(sum[i] <= hunted[i] / 10, "cache orbs " .. i .. " at most a tenth of hunting: " .. sum[i])
	end
	eq(sum[1], 116, "116 Upheaval in all") eq(sum[2], 48, "48 Fate") eq(sum[3], 5, "5 Grafting")
end
eq(K.cacheText(cfg, K.byLevel(cfg, 1000)), "6 Orb of Upheaval, 2 Orb of Fate, 1 Orb of Grafting", "cache text")
eq(#K.cacheItems(cfg, K.byLevel(cfg, 800)), 2, "no zero stacks")

-- ---------------------------------------------------------------- lookups
eq(K.next(cfg, 799).level, 800, "next of 799") eq(K.next(cfg, 800).level, 900, "next of 800")
eq(K.next(cfg, 2200), nil, "none past 2200")
eq(K.baseline(cfg, 799), 0, "baseline below 800") eq(K.baseline(cfg, 1550), 1500, "baseline 1550")
eq(K.baseline(cfg, 9999), 2200, "baseline at the top")

-- ---------------------------------------------------------------- plan
local function levels(list)
	local out = {}
	for _, m in ipairs(list) do out[#out + 1] = m.level end
	return table.concat(out, ",")
end
-- first login: the baseline, no cache (existing characters past a milestone)
local p = K.plan(cfg, {paid = -1, level = 1234, login = true})
eq(p.paid, 1200, "login baseline 1200") eq(#p.pay, 0, "no cache at the baseline") eq(p.top, nil, "no toast")
p = K.plan(cfg, {paid = -1, level = 50, login = true})
eq(p.paid, 0, "a low character: mark 0")
p = K.plan(cfg, {paid = 1200, level = 1234, login = true})
eq(p.paid, 1200, "a later login keeps the mark")
-- live advance
p = K.plan(cfg, {paid = 0, level = 800, oldLevel = 799})
eq(levels(p.pay), "800", "800 reached") eq(p.paid, 800, "mark 800") eq(p.top.level, 800, "toast 800")
p = K.plan(cfg, {paid = 800, level = 899, oldLevel = 898})
eq(#p.pay, 0, "nothing between") eq(p.paid, 800, "mark kept")
-- a jump (several levels in one gain, or a staff set level)
p = K.plan(cfg, {paid = 800, level = 1210, oldLevel = 850})
eq(levels(p.pay), "900,1000,1100,1200", "every milestone of a jump") eq(p.top.level, 1200, "one toast: the highest")
-- a death and the way back: no second cache
p = K.plan(cfg, {paid = 1000, level = 1000, oldLevel = 999})
eq(#p.pay, 0, "back to 1000 after a death: nothing") eq(p.top, nil, "no toast again")
-- never seen at an advance (logged in before the install): baseline from the old level, then what it reaches now
p = K.plan(cfg, {paid = -1, level = 1100, oldLevel = 1099})
eq(levels(p.pay), "1100", "unseen: only the milestone reached now") eq(p.paid, 1100, "mark")
-- staff: the mark moves, nothing is given
p = K.plan(cfg, {paid = 0, level = 900, oldLevel = 799, staff = true})
eq(#p.pay, 0, "staff: no cache") eq(p.top, nil, "staff: no toast") eq(p.paid, 900, "staff: the mark moves")
-- off
local off = {}
for k, v in pairs(cfg) do off[k] = v end
off.enabled = false
p = K.plan(off, {paid = 0, level = 900, oldLevel = 799})
eq(#p.pay, 0, "off: nothing")

-- ---------------------------------------------------------------- toast
local function tr(key, ...) return string.format(key, ...) end
local h, t = K.toast(cfg, K.byLevel(cfg, 900), "Emberborn", "5 Orb of Upheaval", 1000, tr)
eq(h, "Level 900", "toast header")
eq(t, "Milestone reached. Title: Emberborn. Milestone Cache: 5 Orb of Upheaval. Next milestone: level 1000.", "toast text")
h, t = K.toast(cfg, K.byLevel(cfg, 2200), "Apex of Chaos", "x", nil, tr)
check(not t:find("Next", 1, true), "no next milestone after 2200")
-- the pt-BR texts of the engine keys exist
do
	local pt = dofile("data/scripts/chaos/i18n_strings.lua")["pt-BR"]
	for _, k in ipairs({"toastTitle", "toast", "toastNext", "inbox", "broadcast"}) do
		check(pt[cfg.texts[k]] ~= nil, "pt-BR for " .. k)
	end
end

-- ---------------------------------------------------------------- Next Goals
local G = K.goals(cfg, ach)
eq(G.why[900].en, "Milestone: the title Emberborn and a Milestone Cache (5 Orb of Upheaval, 2 Orb of Fate).", "why en")
check(G.why[900].pt:find("Marco: o título Emberborn", 1, true) == 1, "why pt")
eq(#G.challenges, 15, "a challenge per milestone")
eq(G.challenges[1].key, "ms800", "challenge key") eq(G.challenges[1].stat, "tower_floor", "tower")
eq(G.challenges[3].stat, "pocket_kills", "1000: pocket bosses") eq(G.challenges[3].requires, "ChaosPocketBoss", "requires")
do
	local goals = dofile("data/scripts/chaos/goals_config.lua")
	local byKey = {}
	for _, g in ipairs(goals.goals) do byKey[g.key] = g end
	for _, m in ipairs(cfg.list) do
		local g = byKey["lvl" .. m.level]
		check(g ~= nil and g.target == m.level and g.level <= m.level - 100, "Next Goals: Reach level " .. m.level)
		check(g and g.why.en:find(K.titleOf(ach, m.level), 1, true) ~= nil, "Reach level " .. m.level .. " names the title")
		check(byKey["ms" .. m.level] ~= nil and byKey["ms" .. m.level].level == m.level, "challenge goal at " .. m.level)
	end
	-- the tower floors are within reach of the median class (tools/tower_model.py: L800 34, L1000 44, L1500 64, L2000 93;
	-- L2200 from floor 100's hunt pack at L1950)
	local reach = {[800] = 34, [1000] = 44, [1500] = 64, [2000] = 93, [2200] = 104}
	local function reachAt(l)
		local lo, hi
		for lv in pairs(reach) do
			if lv <= l and (not lo or lv > lo) then lo = lv end
			if lv >= l and (not hi or lv < hi) then hi = lv end
		end
		if lo == hi then return reach[lo] end
		return reach[lo] + (reach[hi] - reach[lo]) * (l - lo) / (hi - lo)
	end
	for _, m in ipairs(cfg.list) do
		if m.challenge.stat == "tower_floor" then
			check(m.challenge.target <= reachAt(m.level), m.level .. ": floor " .. m.challenge.target .. " within reach")
			check(m.challenge.target >= reachAt(m.level) - 10, m.level .. ": floor " .. m.challenge.target .. " still a step")
		end
	end
end

-- ================================================================ milestones.lua on a mocked engine
local registry, storages, bag, inboxes, texts, toasts, broadcasts = {}, {}, {}, {}, {}, {}, {}
local function event()
	return function(name)
		local e = {name = name}
		function e:type() end
		function e:register() registry[name] = self end
		return e
	end
end
CreatureEvent = event()
ItemType = function(id) return {getId = function() return id end, getName = function() return "item" .. id end} end
dofile("data/scripts/chaos/chaos_constants.lua")
dofile("data/scripts/chaos/i18n_core.lua")
function Chaos.isTester(player) return player.tester == true end
function Chaos.broadcast(kind, key, ...)
	local s = string.format(key, ...)
	broadcasts[#broadcasts + 1] = s
	return s
end
ChaosNotify = {send = function(player, title, text, kind)
	toasts[#toasts + 1] = {who = player:getName(), title = title, text = text, kind = kind}
	return true
end}
local function newPlayer(id, name, level, opts)
	opts = opts or {}
	storages[id] = storages[id] or {}
	bag[id], inboxes[id] = {}, {}
	local p = {tester = opts.tester}
	function p:getId() return id end
	function p:getName() return name end
	function p:getLevel() return level end
	function p:getGroup() return {getId = function() return opts.group or 1 end} end
	function p:getStorageValue(k) return storages[id][k] or -1 end
	function p:setStorageValue(k, v) storages[id][k] = v end
	function p:registerEvent() end
	function p:sendTextMessage(kind, text) texts[#texts + 1] = text end
	function p:getItemCount(item) return bag[id][item] or 0 end
	function p:addItem(item, n)
		local room = opts.room or 99
		local put = math.min(n, room)
		bag[id][item] = (bag[id][item] or 0) + put
	end
	function p:getInbox()
		return {addItem = function(_, item, n) inboxes[id][item] = (inboxes[id][item] or 0) + n end}
	end
	function p:getLanguage() return "en" end
	return p
end
dofile("data/scripts/chaos/milestones.lua")
local M = ChaosMilestones
check(registry.ChaosMilestonesLogin ~= nil and registry.ChaosMilestonesAdvance ~= nil, "events registered")

-- an old character at 1234: the baseline, no cache, no toast
local old = newPlayer(1, "Oldie", 1234)
registry.ChaosMilestonesLogin.onLogin(old)
eq(storages[1][cfg.storage], 1200, "old: baseline stored") eq(#toasts, 0, "old: no toast") eq(next(bag[1]), nil, "old: no orbs")
registry.ChaosMilestonesAdvance.onAdvance(old, SKILL_LEVEL, 1234, 1235)
eq(#toasts, 0, "old: 1235 is no milestone")
-- the next milestone is paid
registry.ChaosMilestonesAdvance.onAdvance(old, SKILL_LEVEL, 1299, 1300)
eq(storages[1][cfg.storage], 1300, "old: 1300 stored")
eq(bag[1][29856], 7, "old: 7 Upheaval") eq(bag[1][29857], 3, "old: 3 Fate")
eq(#toasts, 1, "one toast") eq(toasts[1].kind, "milestone", "toast kind") eq(toasts[1].title, "Level 1300", "toast title")
check(toasts[1].text:find("the Knelled", 1, true) ~= nil, "toast names the title")
check(toasts[1].text:find("level 1400", 1, true) ~= nil, "toast names the next milestone")
eq(#broadcasts, 1, "one broadcast") eq(broadcasts[1], "Oldie reached level 1300 and earned the title the Knelled.", "broadcast")
-- again (a death and back): nothing
registry.ChaosMilestonesAdvance.onAdvance(old, SKILL_LEVEL, 1299, 1300)
eq(#toasts, 1, "no second toast") eq(bag[1][29856], 7, "no second cache")
-- skill advances are not levels
registry.ChaosMilestonesAdvance.onAdvance(old, 1, 1399, 1400)
eq(#toasts, 1, "a skill is no level")

-- a full backpack: the rest goes to the inbox and the toast says so
local full = newPlayer(2, "Full", 799, {room = 1})
registry.ChaosMilestonesLogin.onLogin(full)
eq(storages[2][cfg.storage], 0, "full: mark 0")
registry.ChaosMilestonesAdvance.onAdvance(full, SKILL_LEVEL, 799, 800)
eq(bag[2][29856], 1, "full: one in the bag") eq(inboxes[2][29856], 4, "full: four in the inbox")
check(toasts[#toasts].text:find("inbox", 1, true) ~= nil, "full: the toast names the inbox")

-- staff and testers
local gm = newPlayer(3, "Gm", 799, {group = 5})
registry.ChaosMilestonesLogin.onLogin(gm)
local before = #toasts
registry.ChaosMilestonesAdvance.onAdvance(gm, SKILL_LEVEL, 799, 800)
eq(#toasts, before, "staff: no toast") eq(next(bag[3]), nil, "staff: no orbs") eq(storages[3][cfg.storage], 800, "staff: mark")
local bot = newPlayer(4, "Bot", 799, {tester = true})
registry.ChaosMilestonesLogin.onLogin(bot)
local nb = #broadcasts
registry.ChaosMilestonesAdvance.onAdvance(bot, SKILL_LEVEL, 799, 800)
eq(#broadcasts, nb, "tester: no broadcast") eq(bag[4][29856], 5, "tester: the cache")

-- the broadcast switch
M.cfg.broadcast.enabled = false
local quiet = newPlayer(5, "Quiet", 899)
registry.ChaosMilestonesLogin.onLogin(quiet)
nb = #broadcasts
registry.ChaosMilestonesAdvance.onAdvance(quiet, SKILL_LEVEL, 899, 900)
eq(#broadcasts, nb, "broadcast off") eq(bag[5][29856], 5, "the cache still")
M.cfg.broadcast.enabled = true

print(string.format("milestones_test: %d checks, %d failures", count, failures))
if failures > 0 then
	os.exit(1)
end
