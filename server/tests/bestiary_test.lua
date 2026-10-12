-- Run from the server/ folder: luajit tests/bestiary_test.lua (and lua5.3; CI runs both)
-- Pure logic of the bestiary and kill tasks (bestiary_core.lua): difficulty, stages, points, ranks, categories, the
-- catalogue, task windows, the board, kill matching, the accept limits, rewards, the window views and packets.
-- Uses the real bestiary_config.lua, bestiary_spawns.lua and bounty_config.lua.
dofile("data/scripts/chaos/bestiary_core.lua")
local C = ChaosBestiaryCore
local cfg = dofile("data/scripts/chaos/bestiary_config.lua")
local spawns = dofile("data/scripts/chaos/bestiary_spawns.lua")
local bountyCfg = dofile("data/scripts/chaos/bounty_config.lua")

local function eq(a, b, m)
	if a ~= b then
		error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2)
	end
end

-- ---------------------------------------------------------------- config sanity
local prevMax = 0
for i, d in ipairs(cfg.difficulties) do
	assert(d.maxLevel > prevMax, "difficulty bands go up: " .. d.key)
	prevMax = d.maxLevel
	eq(#d.kills, 4, d.key .. " four stages")
	eq(#d.points, 4, d.key .. " four point steps")
	for s = 2, 4 do
		assert(d.kills[s] > d.kills[s - 1], d.key .. " kills go up")
	end
	assert(d.bonus.damage >= 1 and d.bonus.damage <= 3 and d.bonus.exp >= 1 and d.bonus.exp <= 3, "bonus 1-3%")
	if i > 1 then
		assert(C.stagePoints(d, 4) >= C.stagePoints(cfg.difficulties[i - 1], 4), "harder pays more points")
	end
end
eq(#cfg.stageNames, 4)
for i = 2, #cfg.ranks do
	assert(cfg.ranks[i].points > cfg.ranks[i - 1].points and cfg.ranks[i].exp > cfg.ranks[i - 1].exp, "ranks go up")
end
local catKeys = {}
for _, c in ipairs(cfg.categories) do
	assert(not catKeys[c.key], "category key once: " .. c.key)
	catKeys[c.key] = true
end
assert(catKeys.bosses and catKeys.chaos and catKeys.other, "fixed categories")
for _, v in pairs(cfg.raceFallback) do
	assert(catKeys[v], "race fallback is a category: " .. v)
end

-- ---------------------------------------------------------------- level and difficulty
eq(C.estimateLevel({minLevel = 600, maxLevel = 800}, cfg), 700, "level range: the middle")
eq(C.estimateLevel({exp = 100, health = 0}, cfg), 16, "1.6 x sqrt(100)")
eq(C.estimateLevel({exp = 100, health = 6000}, cfg), 24, "health raises it, at most x1.5")
eq(C.estimateLevel({exp = 0}, cfg), 2, "no experience: 1.6 rounded")
eq(C.estimateLevel({exp = 1e9}, cfg), cfg.maxLevel, "capped")
eq(C.difficultyOf(5, false, cfg).key, "harmless")
eq(C.difficultyOf(14, false, cfg).key, "harmless")
eq(C.difficultyOf(15, false, cfg).key, "easy")
eq(C.difficultyOf(100, false, cfg).key, "medium")
eq(C.difficultyOf(300, false, cfg).key, "hard")
eq(C.difficultyOf(700, false, cfg).key, "challenging")
eq(C.difficultyOf(1500, false, cfg).key, "deadly")
eq(C.difficultyOf(5, true, cfg).key, "boss", "the boss flag wins")
eq(C.difficultyByKey("hard", cfg).name, "Hard")
eq(C.difficultyByKey("boss", cfg), cfg.boss)
eq(C.difficultyByKey("nope", cfg), nil)

-- ---------------------------------------------------------------- stages
local medium = C.difficultyByKey("medium", cfg)
local th = C.thresholds(medium, 200, cfg)
eq(table.concat(th, ","), "1,25,250,1000", "normal thresholds")
local few = C.thresholds(medium, 3, cfg)
eq(table.concat(few, ","), "1,5,50,200", "few spawns: x0.2")
local none = C.thresholds(medium, 0, cfg)
eq(table.concat(none, ","), "1,25,250,1000", "no spawns at all keeps the normal numbers")
local tiny = C.thresholds({kills = {1, 2, 3, 5}, points = {1, 1, 1, 1}}, 1, cfg)
eq(table.concat(tiny, ","), "1,2,3,4", "at least the stage number and strictly increasing")
eq(table.concat(C.thresholds(cfg.boss, 1, cfg), ","), "1,2,3,5", "bosses keep their numbers")
eq(C.stageOf(0, th), 0)
eq(C.stageOf(1, th), 1)
eq(C.stageOf(24, th), 1)
eq(C.stageOf(25, th), 2)
eq(C.stageOf(999, th), 3)
eq(C.stageOf(5000, th), 4)
eq(C.nextOf(0, th), 1)
eq(C.nextOf(30, th), 250)
eq(C.nextOf(1000, th), nil, "complete: no next")
local k, before, after = C.addKill(24, th)
eq(k, 25); eq(before, 1); eq(after, 2)
k, before, after = C.addKill(3, th)
eq(before, after, "no new stage")
eq(C.stagePoints(medium, 0), 0)
eq(C.stagePoints(medium, 2), 5)
eq(C.stagePoints(medium, 4), 20)
eq(C.stagePoints(medium, 9), 20, "capped at four")

-- ---------------------------------------------------------------- ranks
local r = C.rankOf(0, cfg)
eq(r.name, "Novice"); eq(r.exp, 0); eq(r.next, 100); eq(r.nextName, "Tracker")
r = C.rankOf(299, cfg)
eq(r.name, "Tracker"); eq(r.exp, 0.5)
r = C.rankOf(1000000, cfg)
eq(r.name, "Monster Sage"); eq(r.next, nil)

-- ---------------------------------------------------------------- categories
eq(C.categoryOf("Dragon Lord", "blood", false, false, cfg), "dragons")
eq(C.categoryOf("Demon", "fire", false, false, cfg), "demons")
eq(C.categoryOf("Ghoul", "undead", false, false, cfg), "undead")
eq(C.categoryOf("Orc Berserker", "blood", false, false, cfg), "humanoids")
eq(C.categoryOf("Bandit", "blood", false, false, cfg), "humans")
eq(C.categoryOf("Wolf", "blood", false, false, cfg), "beasts")
eq(C.categoryOf("Giant Spider", "venom", false, false, cfg), "vermin", "the last word first")
eq(C.categoryOf("Frost Dragon", "undead", false, false, cfg), "dragons", "not 'frost' (humanoids)")
eq(C.categoryOf("Demon Skeleton", "undead", false, false, cfg), "undead")
eq(C.categoryOf("Orc Berserker", "blood", false, false, cfg), "humanoids", "an earlier word when the last matches nothing")
eq(C.categoryOf("Tarantula", "venom", false, false, cfg), "vermin")
eq(C.categoryOf("Fire Elemental", "fire", false, false, cfg), "elementals")
eq(C.categoryOf("Vhalkareth", "blood", true, false, cfg), "bosses", "bosses first")
eq(C.categoryOf("Dragon Thing", "blood", false, true, cfg), "chaos", "Chaos monsters next")
eq(C.categoryOf("Xyzzy", "undead", false, false, cfg), "undead", "race fallback")
eq(C.categoryOf("Xyzzy", "venom", false, false, cfg), "vermin")
eq(C.categoryOf("Xyzzy", "blood", false, false, cfg), "other")
eq(C.categoryOf("Xyzzy", nil, false, false, cfg), "other")
eq(C.categoryOf("Dragonling", "blood", false, false, cfg), "dragons", "prefix words")
eq(C.categoryOf("Gutworm", "blood", false, false, cfg), "vermin", "suffix words (*worm)")
eq(C.categoryOf("Lost Soul", "undead", false, false, cfg), "undead", "the head noun before 'lost'")

-- ---------------------------------------------------------------- exclusions
assert(C.excluded("Treasure Chest", 100, cfg), "excluded name")
assert(C.excluded("Training Dummy", 100, cfg), "excluded pattern")
assert(C.excluded("Rat", 0, cfg), "no experience")
assert(not C.excluded("Rat", 5, cfg), "a rat is in")

-- ---------------------------------------------------------------- catalogue
local raw = {
	{name = "Rat", exp = 5, health = 20, race = "blood"},
	{name = "Cave Rat", exp = 10, health = 30, race = "blood"},
	{name = "Dragon", exp = 700, health = 1000, race = "blood"},
	{name = "Dragon Lord", exp = 2100, health = 1900, race = "blood"},
	{name = "Frost Dragon", exp = 2100, health = 1800, race = "undead"},
	{name = "Demon", exp = 6000, health = 8200, race = "fire"},
	{name = "Vhalkareth", exp = 12000, health = 90000, race = "venom", boss = true},
	{name = "Wolf", exp = 18, health = 25, race = "blood"},
	{name = "War Wolf", exp = 55, health = 140, race = "blood"},
	{name = "Winter Wolf", exp = 20, health = 30, race = "blood"},
	{name = "Lonely Ghost", exp = 50, health = 100, race = "undead"}
}
local entries = {}
for _, m in ipairs(raw) do
	entries[#entries + 1] = C.buildEntry(m, spawns[m.name:lower()], cfg)
end
local cat = C.index(entries, cfg)
eq(#cat.list, #raw)
local dragon = cat.byKey["dragon"]
assert(dragon and dragon.cat == "dragons" and dragon.spawns > 0, "dragon spawns on the map")
eq(dragon.level, 42, "1.6 x sqrt(700) rounded")
eq(dragon.diff, "easy")
eq(cat.byId[dragon.id], dragon)
eq(cat.byKey["vhalkareth"].cat, "bosses")
eq(cat.list[1].cat, "bosses", "categories in config order")
for i = 2, #cat.list do
	local a, b = cat.list[i - 1], cat.list[i]
	local idx = C.categoryIndex(cfg)
	assert(idx[a.cat] < idx[b.cat] or (a.cat == b.cat and a.level <= b.level), "sorted by category, then level")
end
local lonely = cat.byKey["lonely ghost"]
eq(lonely.spawns, 0, "a name not on the map")
eq(lonely.areas, nil)

local kills = {rat = 300, dragon = 1, ["dragon lord"] = 30}
local s = C.summary(cat, function(key) return kills[key] end, cfg)
eq(s.total, #raw)
eq(s.known, 3)
eq(s.completed, 1, "300 rats complete the entry (harmless: 250)")
eq(s.cats.dragons.known, 2)
eq(s.cats.dragons.total, 3)
local expect = C.stagePoints(C.difficultyByKey("harmless", cfg), 4) + C.stagePoints(C.difficultyByKey("easy", cfg), 1)
	+ C.stagePoints(C.difficultyByKey(cat.byKey["dragon lord"].diff, cfg), C.stageOf(30, cat.byKey["dragon lord"].th))
eq(s.points, expect, "points from the stages")
eq(C.percent(1, 3), 33.3)
eq(C.percent(0, 0), 0)
eq(C.bonusOf(cat.byKey["rat"], cfg).damage, 1)
eq(C.bonusOf(cat.byKey["vhalkareth"], cfg).exp, 3)

-- ---------------------------------------------------------------- task windows and hunts
local w = C.window(100, cfg.takeWindow)
eq(w.lo, 40); eq(w.hi, 170)
w = C.window(10, cfg.takeWindow)
eq(w.lo, 1, "low characters may hunt anything up to the top")
local ok, task = C.canTakeHunt(dragon, 50, 1, cfg)
assert(ok, tostring(task))
eq(task.key, "h:dragon"); eq(task.kind, "hunt"); eq(task.target, "dragon")
eq(task.required, C.huntCount(dragon, cfg))
assert(task.required >= 10 and task.required % 10 == 0, "rounded kills")
ok, task = C.canTakeHunt(dragon, 50, 0, cfg)
assert(not ok and task:find("discovered"), "must be discovered first")
ok, task = C.canTakeHunt(dragon, 500, 5, cfg)
assert(not ok and task:find("not for your level"), "too low for a level 500")
ok, task = C.canTakeHunt(cat.byKey["vhalkareth"], 1000, 5, cfg)
assert(not ok and task:find("Bosses"), "no boss tasks")
ok, task = C.canTakeHunt(lonely, 30, 5, cfg)
assert(not ok and task:find("does not live"), "must spawn")
ok = C.canTakeHunt(nil, 30, 5, cfg)
assert(not ok)
local fewEntry = {key = "x", diff = "medium", spawns = 3}
eq(C.huntCount(fewEntry, cfg), 75, "few spawns: half, rounded to 5")

-- ---------------------------------------------------------------- the board (real-size catalogue from the spawn data)
local big = {}
for key, sp in pairs(spawns) do
	-- a fake level from the key (the board only needs levels, categories and spawns)
	local level = 5 + (#key * 37) % 400
	big[#big + 1] = {key = key, name = key, level = level, cat = C.categoryOf(key, nil, false, false, cfg),
		diff = C.difficultyOf(level, false, cfg).key, spawns = sp.spawns, boss = false}
end
local bigCat = C.index(big, cfg)
local offers, win = C.offers(20261008, 42, 120, bigCat, cfg)
local again = C.offers(20261008, 42, 120, bigCat, cfg)
eq(#offers, #again)
for i = 1, #offers do
	eq(offers[i].key, again[i].key, "same day and character: same board")
end
local hunts, fams, keys = 0, 0, {}
for _, o in ipairs(offers) do
	assert(not keys[o.key], "distinct offers")
	keys[o.key] = true
	assert(o.required and o.required > 0, "a kill count")
	if o.kind == "hunt" then
		hunts = hunts + 1
		local e = bigCat.byKey[o.target]
		assert(e.level >= win.lo and e.level <= win.hi, "hunt in the board window")
	else
		fams = fams + 1
		assert(o.target ~= "other", "no 'other' family")
		eq(o.lo, win.lo); eq(o.hi, win.hi)
	end
end
eq(hunts, cfg.boardHunts)
eq(fams, cfg.boardFamilies)
local other = C.offers(20261009, 42, 120, bigCat, cfg)
local same = 0
for i = 1, math.min(#offers, #other) do
	if offers[i].key == other[i].key then
		same = same + 1
	end
end
assert(same < #offers, "another day, another board")
local empty = C.offers(20261008, 42, 120, C.index({}, cfg), cfg)
eq(#empty, 0, "nothing to offer")

-- ---------------------------------------------------------------- kill matching
local hunt = {key = "h:dragon", kind = "hunt", target = "dragon", status = 0}
assert(C.matches(hunt, dragon))
assert(not C.matches(hunt, cat.byKey["dragon lord"]))
hunt.status = 1
assert(not C.matches(hunt, dragon), "finished tasks do not count")
local fam = {kind = "family", target = "dragons", lo = 30, hi = 200, status = 0}
assert(C.matches(fam, dragon))
local dl = cat.byKey["dragon lord"]
eq(C.matches(fam, dl), dl.level >= 30 and dl.level <= 200, "family: level window")
assert(not C.matches(fam, cat.byKey["wolf"]), "family: category")
assert(not C.matches({kind = "family", target = "bosses", lo = 1, hi = 9999, status = 0}, cat.byKey["vhalkareth"]),
	"bosses never count for a family")

-- progress and milestones (the bounty board's)
local t = {progress = 0, required = 8, status = 0}
local crossedAll = {}
local done
for _ = 1, 8 do
	local crossed
	crossed, done = C.milestones(t, cfg.progressNotices)
	for _, p in ipairs(crossed or {}) do
		crossedAll[#crossedAll + 1] = p
	end
end
assert(done, "done at 8")
eq(table.concat(crossedAll, ","), "25,50,75")
eq(t.status, 1)
local again2 = C.milestones(t, cfg.progressNotices)
eq(again2, nil, "no progress after completion")

-- party credit (the bounty board's)
local function P(id, x, party)
	return {id = id, pos = {x = x, y = 100, z = 7}, party = party}
end
local partyList = {}
local a, b, c2 = P(1, 100, partyList), P(2, 110, partyList), P(3, 200, partyList)
partyList[1], partyList[2], partyList[3] = a, b, c2
local credited = C.credit({a, a}, function(p) return p.party end, function(p) return p.pos end, cfg.partyRange,
	function(p) return p.id end)
eq(#credited, 2, "the killer once and the member in range; the far one gets nothing")

-- ---------------------------------------------------------------- accept limits
local st = {tasks = {}, doneDay = 0, doneWeek = 0, doneKeys = {}}
local function T(key)
	return {key = key, kind = "hunt", target = key, required = 10}
end
ok = C.canAccept(T("h:a"), st, cfg)
assert(ok)
for i = 1, cfg.maxActive do
	st.tasks["h:" .. i] = {status = 0}
end
local msg
ok, msg = C.canAccept(T("h:b"), st, cfg)
assert(not ok and msg:find("at most"), "active cap")
st.tasks = {["h:1"] = {status = 0}}
ok, msg = C.canAccept(T("h:1"), st, cfg)
assert(not ok and msg:find("already hold"), "the same task twice")
st.doneKeys["h:z"] = true
ok, msg = C.canAccept(T("h:z"), st, cfg)
assert(not ok and msg:find("today"), "a task done today")
st.doneDay = cfg.dailyLimit - 1
ok, msg = C.canAccept(T("h:y"), st, cfg)
assert(not ok and msg:find("a day"), "done + active reaches the daily limit")
st.tasks, st.doneDay = {}, cfg.dailyLimit - 1
ok = C.canAccept(T("h:y"), st, cfg)
assert(ok, "one more is fine")
st.doneDay, st.doneWeek = 0, cfg.weeklyLimit
ok, msg = C.canAccept(T("h:y"), st, cfg)
assert(not ok and msg:find("a week"), "weekly limit")
ok, msg = C.canAccept(nil, st, cfg)
assert(not ok and msg:find("not on your board"))
eq(C.activeCount({tasks = {a = {status = 0}, b = {status = 1}}}), 1)

-- ---------------------------------------------------------------- rewards
local low = C.taskReward({kind = "hunt", level = 20}, 20, cfg, bountyCfg)
eq(low.gold, 4000, "band 1 hunt: 40% of 10k")
eq(low.chaos, 0)
eq(low.exp, math.floor(C.expForLevel(20) * 1.5 / 100))
eq(low.points, cfg.reward.hunt.points * C.difficultyOf(20, false, cfg).points[1])
local top = C.taskReward({kind = "family", level = 900}, 1000, cfg, bountyCfg)
eq(top.gold, 1200000, "band 6 family: 60% of 2M")
eq(top.chaos, 4)
eq(top.divine, 1)
eq(top.exp, math.floor(C.expForLevel(1000) * 2 / 100))
local capped = C.taskReward({kind = "hunt", level = 20}, 1000, cfg, bountyCfg)
eq(capped.gold, 4000, "a low task pays the low band even for a high character")
eq(capped.exp, math.floor(C.expForLevel(49) * 1.5 / 100), "experience capped at the band top")
-- the most a day of tasks pays stays well below a day of bounty contracts at the same band
local dayTasks = cfg.dailyLimit * top.gold
local dayBounty = 12 * bountyCfg.bands[6].reward.gold
assert(dayTasks < dayBounty / 3, "modest next to the bounty board")

-- ---------------------------------------------------------------- views
local els = C.elements({[8] = 20, [2] = -10, [4] = 0})
eq(#els, 2, "zero is left out")
eq(els[1].name, "energy"); eq(els[1].pct, -10)
eq(els[2].name, "fire"); eq(els[2].pct, 20)
eq(#C.elements(nil), 0)
local imm = C.immunities(4 + 8 + 2048)
eq(table.concat(imm, ","), "earth,fire,death")
eq(#C.immunities(0), 0)
eq(C.depthText(7), "surface")
eq(C.depthText(5), "above ground")
eq(C.depthText(9), "underground, floor -2")
local towns = {{name = "Northport", x = 1000, y = 1000}, {name = "Southmere", x = 1000, y = 2000}}
local town, d = C.nearestTown({x = 1030, y = 1100}, towns)
eq(town.name, "Northport"); eq(d, 100)
local areas = C.areaTexts({{1010, 1010, 7, 30}, {1000, 1900, 9, 10}, {5, 5, 7, 1}, {6, 6, 7, 1}}, towns, 3)
eq(#areas, 3, "at most areasMax")
eq(areas[1].text, "in Northport (surface)")
eq(areas[2].text, "near Southmere (underground, floor -2)")
eq(areas[1].count, 30)
eq(C.areaTexts({{5, 6, 7, 1}}, {}, 3)[1].text, "around 5, 6 (surface)", "no towns")

local loot = {{itemId = 1, chance = 50000, maxCount = 10}, {itemId = 2, chance = 100}, {itemId = 3, chance = 5000},
	{itemId = 4, chance = 1000}, {itemId = 5, chance = 20000}, {itemId = 6, chance = 300}, {itemId = 99, chance = 1}}
local names = {"gold coin", "magic sword", "steel shield", "ring", "meat", "rare gem"}
local function info(id)
	if names[id] then
		return names[id], id + 100
	end
	return nil
end
eq(#C.loot(loot, info, 1, cfg), 0, "stage 1: no loot")
local l2 = C.loot(loot, info, 2, cfg)
eq(#l2, cfg.lootHighlights)
eq(l2[1].name, "magic sword", "stage 2: the rarest first")
eq(l2[1].chance, 0.1)
eq(l2[1].cid, 102)
local l3 = C.loot(loot, info, 3, cfg)
eq(#l3, 6, "stage 3: all known items")
eq(l3[1].name, "gold coin", "most common first")
eq(l3[1].max, 10)

local uniques = {{name = "Wyrmfang", id = 500, monsters = {"Dragon", "Dragon Lord"}},
	{name = "Anything", id = 501, monsters = {}}, {name = "Lordly", id = 502, monsters = {"dragon lord"}, bossOnly = true},
	{name = "Broken", id = 503}}
local u = C.uniquesOf(uniques, "dragon lord")
eq(#u, 2)
eq(u[1].name, "Wyrmfang")
eq(u[2].bossOnly, true)
eq(#C.uniquesOf(uniques, "rat"), 0)

-- ---------------------------------------------------------------- packets
local rows = {}
for i = 1, 500 do
	rows[i] = string.rep("x", 40) .. i
end
local function enc(v)
	return '"' .. v .. '"'
end
local chunks = C.chunk(rows, 1000, enc)
local total = 0
for _, part in ipairs(chunks) do
	local size = 2
	for _, v in ipairs(part) do
		size = size + #enc(v) + 1
	end
	assert(size <= 1000, "under the budget")
	total = total + #part
end
eq(total, 500, "nothing lost")
eq(#C.chunk({}, 1000, enc), 1, "an empty list is one empty packet")
eq(#C.chunk({}, 1000, enc)[1], 0)

-- ---------------------------------------------------------------- days
local function at(y, mo, dd, hh)
	return os.time({year = y, month = mo, day = dd, hour = hh, min = 0, sec = 0})
end
eq(C.day(at(2026, 10, 8, 5), cfg), 20261007, "before rollHour: the previous task day")
eq(C.week(at(2026, 10, 8, 12), cfg), 20261005)
eq(C.nextRoll(at(2026, 10, 8, 7), cfg), at(2026, 10, 9, 6))

-- ---------------------------------------------------------------- spawn data
local n = 0
for key, e in pairs(spawns) do
	n = n + 1
	eq(key, key:lower(), "keys are lower case")
	assert(e.spawns > 0, "spawn count")
	assert(#e.areas >= 1 and #e.areas <= 3, "1-3 areas")
end
assert(n > 500, "the full map's monsters")

print("bestiary_test: ok")
