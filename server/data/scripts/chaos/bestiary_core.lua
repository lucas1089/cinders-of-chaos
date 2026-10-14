-- Bestiary and kill tasks: pure logic (no engine calls), shared by bestiary.lua and server/tests/bestiary_test.lua.
--   ChaosBestiaryCore.estimateLevel(m, cfg)          hunting level of {exp, health, minLevel, maxLevel} (bounty pool formula)
--   .difficultyOf(level, boss, cfg)                  a row of cfg.difficulties (or cfg.boss)
--   .thresholds(diff, spawns, cfg)                   kills for stages 1..4 (fewer for monsters with few spawns)
--   .stageOf(kills, th) / .nextOf(kills, th)         stage reached (0..4) / kills needed for the next one (nil at 4)
--   .stagePoints(diff, stage)                        bestiary points of reaching `stage` (cumulative)
--   .rankOf(points, cfg)                             {index, name, exp, next, nextName}
--   .categoryOf(name, race, boss, chaos, cfg)        category key
--   .buildEntry(info, spawnInfo, cfg)                a catalogue entry from monster data (see bestiary.lua)
--   .summary(catalogue, killsOf, cfg)                totals, per category counts and points
--   .addKill(kills, th)                              new kills, old stage, new stage
--   .window(level, w)                                level window {lo, hi} for tasks
--   .huntTask(entry, level, cfg) / .canTakeHunt      a hunt task for an entry and whether a character may take it
--   .offers(day, guid, level, catalogue, cfg)        the board of a character for a task day (seeded)
--   .matches(task, entry)                            whether a kill of `entry` counts for `task`
--   .canAccept(task, st, cfg, lang?)                 the accept rules (active, daily and weekly limits, repeats); the
--                                                    reasons (also canTakeHunt's, lang last) in `lang`, English without
--   .taskReward(task, playerLevel, cfg, bountyCfg)   {gold, chaos, divine, exp, points}
--   .elements(list) / .immunities(mask) / .depthText(z) / .nearestTown(pos, towns) / .loot(...)  views for the window
--   .chunk(list, budget, encode)                     splits a list into packets under `budget` bytes
--   .day(t, cfg) / .week(t, cfg) / .nextRoll(t, cfg) the task day, week and the next day start (bounty board's)
-- Party credit, kill milestones, days and weeks and the seeded generator are the bounty board's (bounty_core.lua).
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.

if not ChaosBounty or not ChaosBounty.credit then
	dofile("data/scripts/chaos/bounty_core.lua")
end

ChaosBestiaryCore = ChaosBestiaryCore or {}
local C = ChaosBestiaryCore

-- a text in `lang` (Chaos.t keys, i18n_strings.lua); English without ChaosI18n
local function T(lang, key, ...)
	if ChaosI18n and ChaosI18n.text then
		return ChaosI18n.text(lang, key, ...)
	end
	if select("#", ...) == 0 then
		return key
	end
	return string.format(key, ...)
end
local B = ChaosBounty

C.credit = B.credit -- (killers, membersOf, posOf, range, idOf): killers and their party members in range, each once
C.milestones = B.addKill -- ({progress, required, status}, notices): crossed percents and completion
C.rng = B.rng
C.expForLevel = B.expForLevel

function C.day(t, cfg)
	return B.day(t, cfg)
end

function C.week(t, cfg)
	return B.week(t, cfg)
end

function C.nextRoll(t, cfg)
	return B.nextRoll(t, cfg)
end

-- ---------------------------------------------------------------- level and difficulty
-- the bounty pool's estimate (tools/gen_bounty_pool.py estimate_level), capped at cfg.maxLevel
function C.estimateLevel(m, cfg)
	local minL, maxL = tonumber(m.minLevel) or 0, tonumber(m.maxLevel) or 0
	local level
	if minL > 0 and maxL >= minL then
		level = math.floor((minL + maxL) / 2)
	else
		local byExp = 1.6 * math.sqrt(math.max(tonumber(m.exp) or 0, 1))
		local byHp = (tonumber(m.health) or 0) / 60
		level = math.floor(math.max(byExp, math.min(byHp, byExp * 1.5)) + 0.5)
	end
	return math.max(1, math.min(level, cfg and cfg.maxLevel or 1500))
end

function C.difficultyOf(level, boss, cfg)
	if boss then
		return cfg.boss
	end
	for _, d in ipairs(cfg.difficulties) do
		if level <= d.maxLevel then
			return d
		end
	end
	return cfg.difficulties[#cfg.difficulties]
end

function C.difficultyByKey(key, cfg)
	if key == cfg.boss.key then
		return cfg.boss
	end
	for _, d in ipairs(cfg.difficulties) do
		if d.key == key then
			return d
		end
	end
	return nil
end

-- ---------------------------------------------------------------- stages
-- goal: the monster's kill-goal factor (pack combat, pace_config.lua; 1 or nil = none): every stage after the first
-- (Discovered stays at its kill) needs that many times the kills
function C.thresholds(diff, spawns, cfg, goal)
	local th = {}
	spawns = tonumber(spawns) or 0
	goal = tonumber(goal) or 1
	local few = diff ~= cfg.boss and spawns > 0 and spawns < cfg.fewSpawns
	for i, k in ipairs(diff.kills) do
		if goal > 1 and i > 1 and diff ~= cfg.boss then
			k = math.floor(k * goal + 0.5)
		end
		if few then
			k = math.max(i, math.floor(k * cfg.fewSpawnsMult + 0.5))
		end
		if i > 1 and k <= th[i - 1] then
			k = th[i - 1] + 1
		end
		th[i] = k
	end
	return th
end

function C.stageOf(kills, th)
	local stage = 0
	for i, k in ipairs(th) do
		if kills >= k then
			stage = i
		end
	end
	return stage
end

function C.nextOf(kills, th)
	for _, k in ipairs(th) do
		if kills < k then
			return k
		end
	end
	return nil
end

function C.stagePoints(diff, stage)
	local n = 0
	for i = 1, math.min(stage, #diff.points) do
		n = n + diff.points[i]
	end
	return n
end

-- kills + 1: returns the new count, the stage before and the stage after
function C.addKill(kills, th)
	local before = C.stageOf(kills, th)
	kills = kills + 1
	return kills, before, C.stageOf(kills, th)
end

function C.rankOf(points, cfg)
	local index = 1
	for i, r in ipairs(cfg.ranks) do
		if points >= r.points then
			index = i
		end
	end
	local r, nx = cfg.ranks[index], cfg.ranks[index + 1]
	return {index = index, name = r.name, exp = r.exp, next = nx and nx.points or nil, nextName = nx and nx.name or nil}
end

-- ---------------------------------------------------------------- categories
local function wordsOf(name)
	local list = {}
	for w in tostring(name):lower():gmatch("%a+") do
		list[#list + 1] = w
	end
	return list
end

local function wordMatches(word, pattern)
	if pattern:sub(1, 1) == "*" then
		local tail = pattern:sub(2)
		return #word >= #tail and word:sub(-#tail) == tail
	end
	if pattern:sub(-1) == "*" then
		local stem = pattern:sub(1, -2)
		return word:sub(1, #stem) == stem
	end
	return word == pattern
end

function C.categoryOf(name, race, boss, chaos, cfg)
	if boss then
		return "bosses"
	end
	if chaos then
		return "chaos"
	end
	-- the last word first (the head noun: "Giant Spider" is a spider, "Frost Dragon" a dragon), then the ones before it
	local words = wordsOf(name)
	for i = #words, 1, -1 do
		for _, cat in ipairs(cfg.categories) do
			for _, pattern in ipairs(cat.words or {}) do
				if wordMatches(words[i], pattern) then
					return cat.key
				end
			end
		end
	end
	return cfg.raceFallback[tostring(race or "")] or "other"
end

function C.categoryIndex(cfg)
	local index = {}
	for i, cat in ipairs(cfg.categories) do
		index[cat.key] = i
	end
	return index
end

-- ---------------------------------------------------------------- catalogue
function C.excluded(name, exp, cfg)
	local lower = tostring(name):lower()
	if (tonumber(exp) or 0) < cfg.minExp or cfg.excludeNames[lower] then
		return true
	end
	for _, p in ipairs(cfg.excludePatterns) do
		if lower:find(p) then
			return true
		end
	end
	return false
end

-- info = {name, exp, health, minLevel, maxLevel, boss, race, chaos, outfit}; spawnInfo = bestiary_spawns.lua row or nil
function C.buildEntry(info, spawnInfo, cfg)
	local spawns = spawnInfo and spawnInfo.spawns or 0
	local level = C.estimateLevel(info, cfg)
	local diff = C.difficultyOf(level, info.boss, cfg)
	-- pack combat (pace): cfg.goalOf(info, level) is set by bestiary.lua (pace_core.lua goalOfEntry); bosses keep theirs
	local goal = (not info.boss and cfg.goalOf) and cfg.goalOf(info, level) or 1
	return {
		goal = goal,
		name = info.name,
		key = info.name:lower(),
		level = level,
		minLevel = tonumber(info.minLevel) or 0,
		maxLevel = tonumber(info.maxLevel) or 0,
		exp = tonumber(info.exp) or 0,
		health = tonumber(info.health) or 0,
		boss = info.boss and true or false,
		race = info.race,
		cat = C.categoryOf(info.name, info.race, info.boss, info.chaos, cfg),
		diff = diff.key,
		spawns = spawns,
		areas = spawnInfo and spawnInfo.areas or nil,
		th = C.thresholds(diff, spawns, cfg, goal),
		outfit = info.outfit
	}
end

-- sorts entries by category order, level and name and numbers them (entry.id = position)
function C.index(entries, cfg)
	local order = C.categoryIndex(cfg)
	table.sort(entries, function(a, b)
		local ca, cb = order[a.cat] or 99, order[b.cat] or 99
		if ca ~= cb then
			return ca < cb
		end
		if a.level ~= b.level then
			return a.level < b.level
		end
		return a.key < b.key
	end)
	local catalogue = {list = entries, byKey = {}, byId = {}}
	for i, e in ipairs(entries) do
		e.id = i
		catalogue.byKey[e.key] = e
		catalogue.byId[i] = e
	end
	return catalogue
end

-- killsOf(key) -> kills of the character; returns {known, completed, total, points (from stages), cats = {[key] = {known,
-- completed, total}}}
function C.summary(catalogue, killsOf, cfg)
	local s = {known = 0, completed = 0, total = 0, points = 0, cats = {}}
	for _, cat in ipairs(cfg.categories) do
		s.cats[cat.key] = {known = 0, completed = 0, total = 0}
	end
	for _, e in ipairs(catalogue.list) do
		local c = s.cats[e.cat]
		local stage = C.stageOf(killsOf(e.key) or 0, e.th)
		s.total = s.total + 1
		c.total = c.total + 1
		if stage >= 1 then
			s.known = s.known + 1
			c.known = c.known + 1
		end
		if stage >= 4 then
			s.completed = s.completed + 1
			c.completed = c.completed + 1
		end
		s.points = s.points + C.stagePoints(C.difficultyByKey(e.diff, cfg), stage)
	end
	return s
end

function C.percent(part, total)
	if (total or 0) <= 0 then
		return 0
	end
	return math.floor(part * 1000 / total + 0.5) / 10
end

-- ---------------------------------------------------------------- task windows
function C.window(level, w)
	level = math.max(1, tonumber(level) or 1)
	local lo = math.floor(level * w.lowFrac)
	if level <= (w.anyBelow or 0) then
		lo = 1
	end
	return {lo = math.max(1, lo), hi = math.ceil(level * w.highFrac) + (w.highAdd or 0)}
end

local function inWindow(e, win)
	return e.level >= win.lo and e.level <= win.hi
end

local function roundTo(n, step)
	return math.max(step, math.floor(n / step + 0.5) * step)
end

function C.huntCount(entry, cfg)
	local n = (cfg.huntKills[entry.diff] or 100) * (tonumber(entry.goal) or 1)
	if (entry.spawns or 0) < cfg.fewSpawnsTask then
		return roundTo(n * cfg.fewSpawnsTaskMult, 5)
	end
	return roundTo(n, 10)
end

function C.huntTask(entry)
	return {key = "h:" .. entry.key, kind = "hunt", target = entry.key, label = entry.name, lo = entry.level,
		hi = entry.level, level = entry.level, required = nil}
end

-- whether a character of `level` with `kills` of the entry may take a hunt task for it (not the limits: canAccept)
function C.canTakeHunt(entry, level, kills, cfg, lang)
	if not entry then
		return false, T(lang, "That monster is not in the bestiary.")
	end
	if entry.boss then
		return false, T(lang, "Bosses cannot be taken as kill tasks.")
	end
	if (entry.spawns or 0) <= 0 then
		return false, T(lang, "That monster does not live anywhere you can hunt it.")
	end
	if (kills or 0) < 1 then
		return false, T(lang, "Kill one first: its bestiary entry must be discovered.")
	end
	local win = C.window(level, cfg.takeWindow)
	if not inWindow(entry, win) then
		return false, T(lang, "That monster is not for your level (hunting level %d, yours: %d-%d).", entry.level,
			win.lo, win.hi)
	end
	local task = C.huntTask(entry)
	task.required = C.huntCount(entry, cfg)
	return true, task
end

-- the board of a character for a task day: hunts from spawning monsters in the board window, families from categories
-- with at least familyMinMonsters of them. Seeded by day and character: the same all day, other characters differ.
function C.offers(day, guid, level, catalogue, cfg)
	local win = C.window(level, cfg.boardWindow)
	local rand = C.rng((day % 100000) * 7919 + (guid % 1000003) * 31 + 17)
	local pool, byCat, cats = {}, {}, {}
	for _, e in ipairs(catalogue.list) do
		if not e.boss and (e.spawns or 0) > 0 and inWindow(e, win) then
			pool[#pool + 1] = e
			if not byCat[e.cat] then
				byCat[e.cat] = {}
				cats[#cats + 1] = e.cat
			end
			table.insert(byCat[e.cat], e)
		end
	end
	local offers = {}
	-- hunts: distinct monsters
	local used = {}
	for _ = 1, math.min(cfg.boardHunts, #pool) do
		local e
		for _ = 1, 20 do
			e = pool[rand(1, #pool)]
			if not used[e.key] then
				break
			end
		end
		if not used[e.key] then
			used[e.key] = true
			local task = C.huntTask(e)
			task.required = C.huntCount(e, cfg)
			offers[#offers + 1] = task
		end
	end
	-- families: distinct categories with enough monsters ("other" is no family)
	local famCats = {}
	for _, key in ipairs(cats) do
		if key ~= "other" and #byCat[key] >= cfg.familyMinMonsters then
			famCats[#famCats + 1] = key
		end
	end
	table.sort(famCats)
	local names = {}
	for _, cat in ipairs(cfg.categories) do
		names[cat.key] = cat.name
	end
	for _ = 1, math.min(cfg.boardFamilies, #famCats) do
		local i = rand(1, #famCats)
		local key = table.remove(famCats, i)
		local mid = math.floor((win.lo + win.hi) / 2)
		local diff = C.difficultyOf(mid, false, cfg)
		offers[#offers + 1] = {
			key = string.format("f:%s:%d-%d", key, win.lo, win.hi),
			kind = "family", target = key, label = names[key] or key, lo = win.lo, hi = win.hi, level = mid,
			required = roundTo((cfg.huntKills[diff.key] or 100) * cfg.familyKillsMult
				* (cfg.familyGoalOf and cfg.familyGoalOf(mid) or 1), 10),
			monsters = #byCat[key]
		}
	end
	return offers, win
end

-- a kill of catalogue entry `e` counts for the task
function C.matches(task, e)
	if not task or not e or task.status ~= 0 then
		return false
	end
	if task.kind == "hunt" then
		return task.target == e.key
	end
	return task.target == e.cat and not e.boss and e.level >= task.lo and e.level <= task.hi
end

-- st = {tasks = {[key] = task}, doneDay = n, doneWeek = n, doneKeys = {[key] = true} (completed this task day)}
function C.activeCount(st)
	local n = 0
	for _, t in pairs(st.tasks) do
		if t.status == 0 then
			n = n + 1
		end
	end
	return n
end

function C.canAccept(task, st, cfg, lang)
	if not task then
		return false, T(lang, "That task is not on your board.")
	end
	local cur = st.tasks[task.key]
	if cur and cur.status == 0 then
		return false, T(lang, "You already hold that task.")
	end
	if st.doneKeys[task.key] then
		return false, T(lang, "You already completed that task today.")
	end
	local active = C.activeCount(st)
	if active >= cfg.maxActive then
		return false, T(lang, "You can hold at most %d kill tasks at once.", cfg.maxActive)
	end
	if st.doneDay + active >= cfg.dailyLimit then
		return false, T(lang, "You can complete at most %d kill tasks a day.", cfg.dailyLimit)
	end
	if st.doneWeek + active >= cfg.weeklyLimit then
		return false, T(lang, "You can complete at most %d kill tasks a week.", cfg.weeklyLimit)
	end
	return true
end

-- ---------------------------------------------------------------- rewards
function C.taskReward(task, playerLevel, cfg, bountyCfg)
	local r = cfg.reward[task.kind] or cfg.reward.hunt
	local bandIndex = math.min(B.bandOf(task.level or 1, bountyCfg), B.bandOf(playerLevel or 1, bountyCfg))
	local band = bountyCfg.bands[bandIndex]
	local base = band.reward
	local level = math.max(1, math.min(playerLevel or band.min, band.max))
	local diff = C.difficultyOf(task.level or 1, false, cfg)
	local divine = (base.divine or 0) * (r.divineMult or 0)
	return {
		gold = math.floor((base.gold or 0) * r.goldMult),
		chaos = math.floor((base.chaos or 0) * r.chaosMult),
		divine = math.floor(divine),
		exp = math.floor(C.expForLevel(level) * r.expPercent / 100),
		points = r.points * diff.points[1]
	}
end

-- ---------------------------------------------------------------- views
-- combat type flags of the engine (CombatType_t) -> names, in display order
C.ELEMENTS = {
	{1, "physical"}, {2, "energy"}, {4, "earth"}, {8, "fire"}, {32, "life drain"}, {64, "mana drain"},
	{256, "drown"}, {512, "ice"}, {1024, "holy"}, {2048, "death"}
}

-- list = MonsterType:getElementList() ({[combat type] = percent}; positive = takes less, negative = takes more)
function C.elements(list)
	local out = {}
	for _, el in ipairs(C.ELEMENTS) do
		local v = list and tonumber(list[el[1]])
		if v and v ~= 0 then
			out[#out + 1] = {name = el[2], pct = v}
		end
	end
	return out
end

local function hasBit(mask, bit)
	return math.floor(mask / bit) % 2 == 1
end

function C.immunities(mask)
	local out = {}
	mask = tonumber(mask) or 0
	for _, el in ipairs(C.ELEMENTS) do
		if hasBit(mask, el[1]) then
			out[#out + 1] = el[2]
		end
	end
	return out
end

function C.depthText(z)
	if z < 7 then
		return "above ground"
	elseif z == 7 then
		return "surface"
	end
	return string.format("underground, floor -%d", z - 7)
end

-- towns = {{name, x, y}}; nearest temple by distance on the map (floors ignored)
function C.nearestTown(pos, towns)
	local best, bestD
	for _, t in ipairs(towns or {}) do
		local d = math.max(math.abs(t.x - pos.x), math.abs(t.y - pos.y))
		if not bestD or d < bestD then
			best, bestD = t, d
		end
	end
	return best, bestD
end

-- areas = {{x, y, z, n}} (bestiary_spawns.lua) -> {{text, count}}
function C.areaTexts(areas, towns, max)
	local out = {}
	for i, a in ipairs(areas or {}) do
		if i > max then
			break
		end
		local pos = {x = a[1], y = a[2], z = a[3]}
		local town, d = C.nearestTown(pos, towns)
		local where
		if not town then
			where = string.format("around %d, %d", pos.x, pos.y)
		elseif d <= 60 then
			where = "in " .. town.name
		else
			where = "near " .. town.name
		end
		out[#out + 1] = {text = string.format("%s (%s)", where, C.depthText(pos.z)), count = a[4]}
	end
	return out
end

-- loot = MonsterType:getLoot() rows {itemId, chance (of 100000), maxCount}; itemInfo(id) -> name, clientId or nil;
-- stage 2: the `highlights` rarest; stage 3: all (up to max), most common first
function C.loot(loot, itemInfo, stage, cfg)
	local list = {}
	for _, l in ipairs(loot or {}) do
		local id = tonumber(l.itemId)
		if id and id > 0 then
			local name, cid = itemInfo(id)
			if name and name ~= "" then
				list[#list + 1] = {id = id, cid = cid or id, name = name, chance = (tonumber(l.chance) or 0) / 1000,
					max = tonumber(l.maxCount) or 1}
			end
		end
	end
	if stage < 2 then
		return {}
	end
	if stage == 2 then
		table.sort(list, function(a, b)
			if a.chance ~= b.chance then
				return a.chance < b.chance
			end
			return a.name < b.name
		end)
		local out = {}
		for i = 1, math.min(cfg.lootHighlights, #list) do
			out[i] = list[i]
		end
		return out
	end
	table.sort(list, function(a, b)
		if a.chance ~= b.chance then
			return a.chance > b.chance
		end
		return a.name < b.name
	end)
	local out = {}
	for i = 1, math.min(cfg.lootMax, #list) do
		out[i] = list[i]
	end
	return out
end

-- uniques = ChaosLoot.uniqueList() rows; the ones that name this monster (an empty list = any monster, not shown)
function C.uniquesOf(uniques, key)
	local out = {}
	for _, u in ipairs(uniques or {}) do
		if type(u.monsters) == "table" then
			for _, m in pairs(u.monsters) do
				if tostring(m):lower() == key then
					out[#out + 1] = {name = u.name, id = u.id, bossOnly = u.bossOnly or nil}
					break
				end
			end
		end
	end
	return out
end

-- bonus of a completed entry
function C.bonusOf(entry, cfg)
	local diff = C.difficultyByKey(entry.diff, cfg)
	return diff and diff.bonus or {damage = 0, exp = 0}
end

-- ---------------------------------------------------------------- packets
function C.chunk(list, budget, encode)
	local chunks, current, size = {}, {}, 2
	for _, item in ipairs(list) do
		local n = #encode(item) + 1
		if #current > 0 and size + n > budget then
			chunks[#chunks + 1] = current
			current, size = {}, 2
		end
		current[#current + 1] = item
		size = size + n
	end
	if #current > 0 or #chunks == 0 then
		chunks[#chunks + 1] = current
	end
	return chunks
end

return C
