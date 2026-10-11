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
eq(#index.list >= 60 and #index.list <= 200, true, "60-200 achievements (" .. #index.list .. ")")
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

-- ------------------------------------------------------------------ reward track: category completion
-- (the point milestones and the cosmetics are cosmetics_config.lua; cosmetics_test.lua checks them against this list)
local catKeys = {}
for _, c in ipairs(data.categories) do
	catKeys[#catKeys + 1] = c.key
	local r = index.categoryRewards[c.key]
	eq(r ~= nil, true, "category " .. c.key .. " has a completion reward")
	eq(#r.title <= 24, true, c.key .. " title fits a name plate")
end
dofile("data/scripts/chaos/nameplate_core.lua")
local seenTitles = {}
for _, def in ipairs(index.list) do
	if def.title then seenTitles[def.title] = true end
end
for key, r in pairs(index.categoryRewards) do
	eq(r.frame == nil or ChaosNameplate.FRAMES[r.frame] == true, true, key .. ": frame " .. tostring(r.frame) .. " exists")
	eq(r.frame ~= "gold" and r.frame ~= "crimson", true, key .. ": not the staff or siege frame")
	eq(seenTitles[r.title], nil, key .. ": title " .. r.title .. " is not an achievement title already")
	seenTitles[r.title] = true
end
local badRewards = K.build({categories = {{key = "a", name = "A"}}, list = {{id = "x", cat = "a", name = "X", points = 5, stat = "x"}},
	categoryRewards = {a = {title = string.rep("y", 30)}, zz = {title = "Nope"}}})
eq(#badRewards.problems, 2, "a long title and an unknown category"); eq(next(badRewards.categoryRewards), nil, "both left out")
-- completion is account-wide (any character), hidden achievements count, nothing short of all of them
local allIds, ridsAll = {}, {}
for _, def in ipairs(index.list) do
	allIds[def.id] = true
	if def.cat == "rifts" then ridsAll[def.id] = true end
end
eq(next(K.completedCategories(index, {})), nil, "nothing done: no category")
eq(K.completedCategories(index, ridsAll).rifts, true, "every rift achievement: Rifts complete")
local allBut = {}
for id in pairs(ridsAll) do allBut[id] = true end
allBut.cinder_solo = nil -- a hidden one
eq(K.completedCategories(index, allBut).rifts, nil, "a hidden one missing: not complete")
local done = K.completedCategories(index, allIds)
for _, key in ipairs(catKeys) do eq(done[key], true, "everything: " .. key .. " complete") end
local twoChars = {"cinder_solo"} -- the hidden one on a second character, the rest on the first
for id in pairs(allBut) do twoChars[#twoChars + 1] = id end
local acct = K.accountFromIds(index, twoChars)
eq(K.completedCategories(index, acct.ids).rifts, true, "two characters' achievements together complete it")
-- titles: the completed categories, frame of the reward, key achievement_cat:<key>
local ct = K.categoryTitles(index, ridsAll)
eq(#ct, 1, "one category title"); eq(ct[1].text, "Riftwarden"); eq(ct[1].key, "achievement_cat:rifts"); eq(ct[1].frame, "violet")
eq(#K.categoryTitles(index, allIds), #data.categories, "every category title")
eq(#K.categoryTitles(index, {}), 0, "no title without completion")
local tr = K.categoryTrack(index, {rift_t1 = true, level_50 = true})
eq(#tr, #data.categories, "the track lists every category")
eq(tr[1].key, "combat"); eq(tr[1].done, 1); eq(tr[1].complete, false); eq(tr[1].title, "Warmaster")
eq(K.categoryTrack(index, ridsAll)[4].complete, true, "Rifts complete in the track")
-- the point milestones need account points: an alt's achievements count once
eq(K.accountFromIds(index, {"level_1000", "level_1000"}).points, 50, "an achievement on two characters counts once")

-- ------------------------------------------------------------------ achievements.lua on a mocked engine (reward track)
do
	local sentMsgs, synced, registeredT, titleSources = {}, {}, {}, {}
	CONST_ME_FIREWORK_YELLOW, MESSAGE_EVENT_ADVANCE, MESSAGE_INFO_DESCR = 29, 19, 22
	json = {encode = function(t) return t end}
	dofile("data/scripts/chaos/chaos_constants.lua")
	local dbUnlocks = {} -- {player, id}
	local dbDown = false
	db = {query = function(q)
		if dbDown then return false end
		local guid, id = q:match("VALUES %((%d+), '([%w_]+)'")
		if guid and q:find("chaos_achievements", 1, true) then dbUnlocks[#dbUnlocks + 1] = {tonumber(guid), id} end
		return true
	end, asyncQuery = function() return true end}
	Chaos.select = function(q)
		local out = {}
		local accountId = tonumber(q:match("`account_id` = (%d+)"))
		if accountId then
			for _, u in ipairs(dbUnlocks) do
				if u[1] == 1 or u[1] == 2 then out[#out + 1] = {achievement = u[2]} end -- guids 1 and 2: account 7
			end
		end
		return out
	end
	local function event()
		return function(name)
			local e = {name = name}
			function e:register() registeredT[name] = self end
			function e:interval() end
			function e:separator() end
			return e
		end
	end
	CreatureEvent, GlobalEvent, TalkAction = event(), event(), event()
	EventCallback = {register = function() end}
	addEvent = function() end
	ChaosTitles = {register = function(source, fn) titleSources[source] = fn end}
	ChaosCosmetics = {sync = function(p) synced[#synced + 1] = p:getName() end,
		ownedOf = function() return {chat_ashen = true} end,
		config = dofile("data/scripts/chaos/cosmetics_config.lua")}
	dofile("data/scripts/chaos/cosmetics_core.lua")
	local function mkPlayer(guid, name)
		local p = {}
		function p:getGuid() return guid end
		function p:getName() return name end
		function p:getId() return guid + 100 end
		function p:getAccountId() return 7 end
		function p:sendTextMessage() end
		function p:sendExtendedOpcode(op, msg) sentMsgs[#sentMsgs + 1] = {to = name, op = op, msg = msg} end
		function p:getPosition() return {sendMagicEffect = function() end} end
		return p
	end
	dofile("data/scripts/chaos/achievements.lua")
	local A = ChaosAchievements
	local ann = mkPlayer(1, "Ann")
	A.stats[1], A.unlocked[1], A.dirty[1] = {}, {}, {}
	A.stats[1].level = 300 -- level 50..300: 5 + 10 + 10 + 15 = 40 points (A.set wants an engine Player)
	A.evaluate(ann)
	eq(#synced, 1, "new unlocks: the reward track is synced once"); eq(synced[1], "Ann")
	-- one ACHIEVEMENT UNLOCKED toast per unlock, with the name and the points
	local toasts = {}
	for _, m in ipairs(sentMsgs) do if m.op == 79 and m.msg.action == "achievement" then toasts[#toasts + 1] = m.msg.message end end
	eq(#toasts, 4, "four unlocks, four toasts")
	eq(toasts[1], "Blooded: +5 points.", "the toast: name and points")
	eq(#dbUnlocks, 4, "four unlock rows")
	-- a relog: the unlocks come back from the database, nothing is unlocked or shown again
	local before = #sentMsgs
	A.unlocked[1] = {}
	for _, u in ipairs(dbUnlocks) do if u[1] == 1 then A.unlocked[1][u[2]] = 1 end end
	eq(#A.evaluate(ann, true), 0, "relog: nothing unlocked twice")
	eq(#sentMsgs, before, "relog: no toast twice")
	-- the unlock row cannot be written: no toast, no reward, still locked (the next check tries again)
	A.stats[1].level = 500
	dbDown = true
	eq(#A.evaluate(ann), 0, "database down: nothing unlocked")
	eq(A.unlocked[1].level_500, nil, "still locked")
	eq(#sentMsgs, before, "and nothing shown")
	dbDown = false
	-- the login summary: the quiet check, then one toast with the reward (giveReward needs the engine: stubbed by a pcall
	-- failure, so the summary is checked from the list it gets)
	local list = {index.byId.level_500, index.byId.level_700, rewards = {level_500 = "5 Orb of Fate"}}
	A.summaryToast(ann, list)
	local last = sentMsgs[#sentMsgs].msg
	eq(last.action, "achievement", "the summary toast")
	eq(last.message, "2 achievements unlocked: +50 points: Shatterborn, Into the Abyss. Rewards: 5 Orb of Fate.", "summary with rewards")
	A.stats[1].level = 300
	eq(A.accountOf(ann).points, 40, "account points after the unlocks")
	eq(A.accountOf(7).points, 40, "by account id")
	A.evaluate(ann)
	eq(#synced, 1, "nothing new: no sync")
	A.grant(ann, "tutorial")
	eq(#synced >= 2, true, "a staff grant syncs too")
	-- the window's track message
	sentMsgs = {}
	A.sendTrack(ann)
	local track
	for _, m in ipairs(sentMsgs) do if m.msg.action == "track" then track = m.msg.data end end
	eq(track ~= nil, true, "track sent"); eq(track.ap, 45, "with the account points")
	eq(track.steps[1].o, 1, "owned milestone flagged"); eq(#track.cats, #data.categories, "and the categories")
	-- the category titles join the achievement titles (account-wide: a second character's unlocks count)
	for id in pairs(ridsAll) do dbUnlocks[#dbUnlocks + 1] = {2, id} end -- Bob (guid 2, offline) of the same account
	A.accounts[7] = nil -- reloaded from the database (as at a login)
	local titles = titleSources.achievement(ann)
	local hasCat = false
	for _, t in ipairs(titles) do if t.key == "achievement_cat:rifts" then hasCat = true end end
	eq(hasCat, true, "Ann holds Riftwarden: Bob completed Rifts on the same account")
	ChaosCosmetics, ChaosTitles, json = nil, nil, nil
end

-- ------------------------------------------------------------------ toasts
do
	local t, x = K.toast(index.byId.level_1000, "mount Doombringer")
	eq(t, "The Thousandth Step", "toast title: the name")
	eq(x, "+50 points. Title: the Unbroken. Reward: mount Doombringer.", "toast text: points, title, reward")
	local t1, x1 = K.toast({id = "x", name = "One", points = 1}, "")
	eq(t1 .. "|" .. x1, "One|+1 point.", "one point, no reward")
	eq(K.summaryToast({}), nil, "no unlocks: no toast")
	local s1, sx = K.summaryToast({index.byId.level_50}, {})
	eq(s1 .. "|" .. sx, "Blooded|+5 points.", "one unlock: its own toast")
	local defs = {}
	for _, id in ipairs({"level_50", "level_100", "level_200", "level_300", "level_500"}) do defs[#defs + 1] = index.byId[id] end
	local st, stext = K.summaryToast(defs, {level_300 = "a", level_500 = "b", level_200 = "c"})
	eq(st, "5 achievements unlocked", "summary title")
	eq(stext, "+65 points: Blooded, Ascendant's Threshold, Hardened and 2 more. Rewards: c, a and 1 more.", "summary text, rewards capped")
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
