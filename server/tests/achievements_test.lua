-- Run from the server/ folder: luajit tests/achievements_test.lua (CI: luajit and lua5.3)
-- Covers achievements_core.lua with the real list (achievements_data.lua): the list itself, progress and thresholds,
-- unlocking only once, hidden achievements, points (character and account), the retroactive check, titles, rewards text,
-- the class unlock method and the SQL helpers.

local function eq(a, b, m) if a ~= b then error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2) end end

dofile("data/scripts/chaos/achievements_core.lua")
local K = ChaosAchievementsCore
local data = dofile("data/scripts/chaos/achievements_data.lua")
local index = K.build(data)

-- ------------------------------------------------------------------ the list
eq(#index.problems, 0, "no problems in achievements_data.lua: " .. table.concat(index.problems, "; "))
eq(#index.list >= 60 and #index.list <= 140, true, "60-140 achievements (" .. #index.list .. ")")
local perCat, titles, rewards, hidden = {}, 0, 0, 0
for _, def in ipairs(index.list) do
	perCat[def.cat] = (perCat[def.cat] or 0) + 1
	if def.title then titles = titles + 1 end
	if def.reward then rewards = rewards + 1 end
	if def.hidden then hidden = hidden + 1 end
	eq(def.target >= 1, true, def.id .. " target")
end
for _, c in ipairs(data.categories) do
	eq((perCat[c.key] or 0) > 0, true, "category " .. c.key .. " has achievements")
end
eq(titles >= 10, true, "titles"); eq(rewards >= 10, true, "rewards"); eq(hidden >= 4, true, "hidden ones")
eq(index.byId.goblin_escaped.hidden, true, "the goblin escape is hidden")
eq(index.byId.wb_all.target, 5, "all five bosses")
for _, def in ipairs(index.list) do
	local r = def.reward
	if r and r.outfit then eq(type(r.outfit.female) == "number" and type(r.outfit.male) == "number", true, def.id .. " outfit looks") end
	if r and r.mount then eq(type(r.mount.id), "number", def.id .. " mount id") end
end

-- validation catches bad entries, which are left out
local bad = K.build({categories = {{key = "a", name = "A"}}, list = {
	{id = "ok", cat = "a", name = "Fine", points = 5, stat = "x"},
	{id = "ok", cat = "a", name = "Again", points = 5, stat = "x"},
	{id = "bad id", cat = "a", name = "Space", points = 5, stat = "x"},
	{id = "nocat", cat = "zz", name = "No cat", points = 5, stat = "x"},
	{id = "nostat", cat = "a", name = "No stat", points = 5},
	{id = "longtitle", cat = "a", name = "T", points = 5, stat = "x", title = string.rep("x", 30)}
}})
eq(#bad.problems, 5, "five problems"); eq(#bad.list, 1, "only the good entry"); eq(bad.list[1].name, "Fine", "the first ok wins")

-- ------------------------------------------------------------------ stats
local s = {}
eq(K.add(s, "kills_rare", 1), true); eq(K.add(s, "kills_rare", 2), true); eq(s.kills_rare, 3, "add")
eq(K.add(s, "kills_rare", 0), false, "nothing to add"); eq(K.add(s, "bad key!", 1), false, "bad key")
eq(K.setMax(s, "level", 120), true); eq(K.setMax(s, "level", 90), false, "never goes down"); eq(s.level, 120)
eq(K.setMax(s, "level", 120), false, "same value is no change")

-- ------------------------------------------------------------------ progress and thresholds
local d = index.byId.level_100
eq(select(1, K.progressOf(d, {level = 99})), 99, "progress 99"); eq(select(2, K.progressOf(d, {level = 99})), 100, "target 100")
eq(select(1, K.progressOf(d, {level = 5000})), 100, "capped at the target")
local stats = {level = 99}
local unlocked = {}
local got = K.evaluate(index, stats, unlocked)
local ids = {}
for _, def in ipairs(got) do ids[#ids + 1] = def.id end
eq(table.concat(ids, ","), "level_50", "99: only level 50")
for _, def in ipairs(got) do unlocked[def.id] = 1000 end
stats.level = 100
got = K.evaluate(index, stats, unlocked)
eq(#got, 1, "100: one more"); eq(got[1].id, "level_100", "level 100 at exactly the threshold")
unlocked.level_100 = 1001
eq(#K.evaluate(index, stats, unlocked), 0, "unlocks only once")
-- a jump unlocks every threshold passed, in list order
local jump = K.evaluate(index, {level = 1001}, {})
ids = {}
for _, def in ipairs(jump) do ids[#ids + 1] = def.id end
eq(table.concat(ids, ","), "level_50,level_100,level_200,level_300,level_500,level_700,level_1000", "jump to 1001")
-- "all": every listed stat at least once
local wb = index.byId.wb_all
eq(select(1, K.progressOf(wb, {wb_kaelgor = 3, wb_vharok = 1})), 2, "two of five bosses")
local five = {wb_kaelgor = 1, wb_skaldra = 1, wb_rotmother = 1, wb_nyxareth = 1, wb_vharok = 2}
local found = false
for _, def in ipairs(K.evaluate(index, five, {})) do if def.id == "wb_all" then found = true end end
eq(found, true, "all five bosses unlock Colossus Hunter")

-- ------------------------------------------------------------------ points
eq(K.points(index, {level_50 = 1, level_100 = 1}), 15, "5 + 10")
eq(K.points(index, {level_50 = 1, gone_from_the_list = 1}), 5, "unknown ids count 0")
local maxPoints = K.maxPoints(index)
eq(maxPoints > 1000, true, "max points " .. maxPoints)
-- points achievements see the points earned in the same evaluation
local many = {}
for _, def in ipairs(index.list) do if def.stat ~= "points" then many[def.id] = 1 end end
local before = K.points(index, many)
local pointsGot = K.evaluate(index, {}, many)
ids = {}
for _, def in ipairs(pointsGot) do ids[#ids + 1] = def.id end
eq(table.concat(ids, ","), (before >= 750 and "points_250,points_750") or (before >= 250 and "points_250") or "", "points metas")
local near = {level = 1000, paragon = 282} -- 5+10+10+15+25+25+50 + 10+25+50+50 = 275 points
local chain = K.evaluate(index, near, {})
local chainIds = {}
for _, def in ipairs(chain) do chainIds[def.id] = true end
eq(chainIds.points_250, true, "the points of this evaluation count for Chronicler")
-- categories
local cats = K.categorySummary(index, {level_50 = 1, rift_t1 = 1})
eq(cats[1].key, "combat"); eq(cats[1].done, 1); eq(cats[1].points, 5)
local totalCount = 0
for _, c in ipairs(cats) do totalCount = totalCount + c.total end
eq(totalCount, #index.list, "every achievement in a category")

-- account: distinct achievements of all characters
local acc = K.accountFromIds(index, {"level_50", "level_50", "rift_t1"})
eq(acc.points, 15, "an achievement on two characters counts once"); eq(acc.ids.rift_t1, true)
eq(K.has(acc, "rift_t1"), true); eq(K.has(acc, "rift_t5"), false)
eq(K.has(acc, "points:15"), true); eq(K.has(acc, "points:16"), false); eq(K.has(nil, "rift_t1"), false)

-- ------------------------------------------------------------------ hidden handling
local rows = K.view(index, {goblin_escaped = 0, kills_rare = 7}, {level_50 = 1234}, function(id) return "Orb " .. id end)
local byId = {}
for _, r in ipairs(rows) do byId[r.i] = r end
eq(#rows, #index.list, "every row")
eq(byId.goblin_escaped.n, "???", "hidden name"); eq(byId.goblin_escaped.h, 1); eq(byId.goblin_escaped.t, 0, "no progress shown")
eq(byId.goblin_escaped.ti, nil, "no title leaked"); eq(byId.goblin_escaped.r, nil, "no reward leaked")
eq(byId.rare_100.v, 7); eq(byId.rare_100.t, 100); eq(byId.rare_100.u, 0, "locked")
eq(byId.level_50.u, 1234, "unlock time"); eq(byId.level_50.n, "Blooded")
eq(byId.level_500.r, "5 Orb 29856, 1 Orb 29857", "reward text with item names")
local shown = K.view(index, {}, {goblin_escaped = 99})
for _, r in ipairs(shown) do if r.i == "goblin_escaped" then eq(r.n, "Ha Ha!", "unlocked hidden one is shown"); eq(r.h, 1) end end

-- recent and titles
local rec = K.recent(index, {level_50 = 10, level_100 = 30, rift_t1 = 20, nope = 40}, 2)
eq(#rec, 2); eq(rec[1].id, "level_100", "newest first"); eq(rec[2].id, "rift_t1")
local t = K.titlesOf(index, {level_300 = 50, level_50 = 60, wb_all = 70})
eq(#t, 2, "only achievements with a title"); eq(t[1].text, "Veteran"); eq(t[1].key, "achievement:level_300"); eq(t[1].at, 50)
eq(t[2].text, "Colossus Hunter")
eq(K.rewardText({gold = 1000, mount = {name = "Doombringer", id = 53}, outfit = {name = "Rift Warrior", addons = 3}}),
	"1000 gold, outfit Rift Warrior with addons, mount Doombringer", "reward text")

-- ------------------------------------------------------------------ retroactive
eq(K.paragonLevel(1000, 1000), 0); eq(K.paragonLevel(1050, 1000), 50); eq(K.paragonLevel(400, 1000), 0)
local retro = K.retroStats({level = 1101, paragonStart = 1000, ascended = true, tutorialDone = false, guild = true,
	bountyDone = 30, bountyWeek = 20260105, arena = {["1v1"] = {wins = 3, best = 1250}}})
eq(retro.level, 1101); eq(retro.paragon, 101); eq(retro.ascended, 1); eq(retro.tutorial, 0); eq(retro.guild, 1)
eq(retro.bounty_done, 30); eq(retro.bounty_weeks, 1); eq(retro.arena1v1_wins, 3); eq(retro.arena1v1_rating, 1250)
local old = {level = 50, bounty_done = 40}
eq(K.applyRetro(old, retro), true, "retro raises"); eq(old.level, 1101); eq(old.bounty_done, 40, "retro never lowers a live counter")
eq(K.applyRetro(old, retro), false, "second time: nothing new")
local retroIds = {}
for _, def in ipairs(K.evaluate(index, old, {})) do retroIds[def.id] = true end
for _, id in ipairs({"level_1000", "paragon_100", "ascended", "guild", "bounty_25", "bounty_week", "arena1_win", "arena1_1200"}) do
	eq(retroIds[id], true, "retroactive " .. id)
end
eq(retroIds.paragon_282, nil, "not yet Paragon 282"); eq(retroIds.tutorial, nil, "tutorial not done"); eq(retroIds.bounty_100, nil)

-- ------------------------------------------------------------------ class unlock method
local m = K.unlockMethod(index)
local accounts = {ids = {rift_t10 = true}, points = 480}
local facts = {achievement = function(q) return K.has(accounts, q) end}
eq(m.check({points = 500}, facts), false, "480 < 500")
accounts.points = 500
eq(m.check({points = 500}, facts), true, "500 points")
eq(m.check({name = "rift_t10"}, facts), true, "by achievement id (name)")
eq(m.check({id = "rift_t15"}, facts), false, "missing achievement")
eq(m.check({name = "rift_t15", points = 400}, facts), true, "either is enough")
eq(m.check({points = 500}, {}), false, "no callback (achievements not loaded)")
eq(m.check(nil, facts), false)
eq(m.describe({points = 500}), "earn 500 achievement points on your account")
eq(m.describe({name = "rift_t10"}), "earn the achievement Edge of Ruin")
eq(m.describe({points = 300, name = "wb_all"}), "earn 300 achievement points on your account, or earn the achievement Colossus Hunter")
eq(m.describe({text = "custom"}), "custom")
-- plugged into the class lock's core: the store stays the configured method of every class
-- (skipped where the class lock is not installed yet)
local lockFile = io.open("data/scripts/chaos/class_unlocks_core.lua", "r")
if lockFile then
lockFile:close()
dofile("data/scripts/chaos/class_unlocks_core.lua")
local CK = ChaosClassUnlocksCore
CK.registerMethod("achievement", m)
for key, class in pairs(CK.config.classes) do
	eq(class.unlock.store ~= nil, true, key .. " keeps the store")
	eq(class.unlock.achievement, nil, key .. " has no achievement method configured")
	eq(CK.autoUnlock(key, {level = 1, achievement = function() return true end}), nil, key .. ": not configured, no auto unlock")
end
local cfg = {table = "t", bypass = {minGroup = 4, minAccountType = 5}, classes = {
	monk = {name = "Monk", vocations = {17}, locked = true, unlock = {store = {offer = "unlockMonk", cost = 750},
		achievement = {points = 500}}}}}
eq(CK.autoUnlock("monk", {achievement = function(q) return K.has({ids = {}, points = 499}, q) end}, cfg), nil, "499 points")
eq(CK.autoUnlock("monk", {achievement = function(q) return K.has({ids = {}, points = 500}, q) end}, cfg), "achievement")
eq(CK.lockMessage("monk", cfg):find("earn 500 achievement points on your account", 1, true) ~= nil, true, "lock message")
end

-- ------------------------------------------------------------------ SQL
eq(#K.sqlCreate(), 2)
eq(K.sqlSaveStat(7, "kills_rare", 12):find("GREATEST", 1, true) ~= nil, true, "a save never lowers")
eq(K.sqlOffline(7, "wb_kills", 1, "add"):find("`value` + VALUES(`value`)", 1, true) ~= nil, true, "offline add")
eq(K.sqlOffline(7, "rift_tier", 5, "max"):find("GREATEST", 1, true) ~= nil, true, "offline max")
eq(K.sqlOffline(7, "x", 0, "add"), nil, "nothing to write"); eq(K.sqlOffline(7, "x'; DROP", 1), nil, "no injection")
eq(K.sqlUnlock(7, "level_50", 99), "INSERT IGNORE INTO `chaos_achievements` (`player_id`, `achievement`, `unlocked_at`) VALUES (7, 'level_50', 99)")
eq(K.sqlUnlock(7, "bad'id", 1), nil)

print("achievements_test: OK (" .. #index.list .. " achievements, " .. maxPoints .. " points)")
