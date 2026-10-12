-- Bestiary and kill tasks (client game_bestiary, extended opcode ChaosOpcodes.bestiary)
--
-- Bestiary: an entry for every monster the server knows (Game.getMonsterTypes, minus scenery and summons:
-- bestiary_config.lua minExp / excludeNames / excludePatterns), unlocked by kills in four stages (Discovered, Studied,
-- Mastered, Completed) whose kill counts come from the monster's difficulty (its estimated hunting level, the bounty
-- pool's formula) and from how often it spawns on the map (bestiary_spawns.lua, tools/gen_bestiary_spawns.py).
-- Each stage reveals more (picture and numbers, elements and where it lives, the loot) and gives bestiary points; a
-- completed entry gives +damage and +experience against that monster. Bestiary points (stages + kill tasks) raise the
-- bestiary rank, a small experience bonus from every monster.
-- Kill tasks: personal "kill N of a monster" (from its bestiary entry, or the task board) and "kill N of a family"
-- (a category within a level window, the board only) with gold, orbs, experience and bestiary points; daily and weekly
-- limits. The bounty board (bounty.lua) stays the shared daily board with the big rewards; it is not duplicated here:
-- the task tracker HUD lists both (tasks first, then the active bounty contracts, read from ChaosBounty).
-- Pure logic: bestiary_core.lua (tests: server/tests/bestiary_test.lua); settings: bestiary_config.lua.
-- Tables: chaos_bestiary, chaos_bestiary_tasks (server/sql/chaos_bestiary.sql; also created at startup).
--
-- Kills: a CreatureEvent death on every monster without a master (EventCallback onSpawn, as the bounty board); the
-- killers are the last hit and the most damage (summons count for their master) and their party members within
-- partyRange tiles on the same floor (ChaosBounty.credit), each once. Kills are kept in memory and written every
-- flushSeconds, at a new stage and at logout.
-- Bonuses: damage against a completed monster (healthchange on the monster, registered from onTargetCombat), experience
-- (EventCallback onGainExperience; needs the experience dispatch of tools/patch_base_events.py, as every Chaos bonus).
--
-- Protocol (JSON {action, data}):
--   client -> server  open | list | entry {id} | board | take {id} | accept {key} | abandon {key} | query
--   server -> client  summary {open, total, known, completed, percent, points, rank = {name, exp, next, nextName},
--                             cats = [{key, name, known, completed, total}], diffs = [{key, name, th, bonus}], tasks =
--                             {active, maxActive, doneDay, dailyLimit, doneWeek, weeklyLimit}}
--                     list {first, last, rows = [[id, name, cat, diff, level, kills, stage, lookType]]}
--                          (lookType 0 below stage 1)
--                     entry {id, name, cat, diff, level, kills, stage, th, next, ... what the stage reveals}
--                     kill {id, kills, stage, next}
--                     board {offers = [{key, kind, label, target, lo, hi, level, required, monsters, look, reward,
--                            state}], active = [tasks], limits..., nextIn}
--                     tracker {rows = [{k = "task"|"bounty", key, label, p, r, done}]}
-- Lua 5.1 / LuaJIT compatible.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end

-- the type behind a shown name (chaos_constants.lua "Monster names"; a renamed rift monster or invader is still its type)
local function typeNameOf(creature)
	return Chaos.monsterTypeName and Chaos.monsterTypeName(creature) or creature:getName()
end
dofile("data/scripts/chaos/bestiary_core.lua")

Chaos.bestiaryConfig = dofile("data/scripts/chaos/bestiary_config.lua")
local cfg = Chaos.bestiaryConfig
local bountyCfg = Chaos.bountyConfig or dofile("data/scripts/chaos/bounty_config.lua")
local C = ChaosBestiaryCore
local OPCODE = ChaosOpcodes.bestiary or 253
local SPAWNS = dofile("data/scripts/chaos/bestiary_spawns.lua")
local ITEMS = bountyCfg.items -- Orb of Upheaval and Orb of Fate server ids

ChaosBestiary = ChaosBestiary or {}
local X = ChaosBestiary
X.players = X.players or {} -- guid -> state (kept over /reload scripts; written back at logout)
X.catalogue = nil -- built at first use (the scripts load before the monsters)

local RACES = {[1] = "venom", [2] = "blood", [3] = "undead", [4] = "fire", [5] = "energy"}

-- ---------------------------------------------------------------- tables
local tablesReady = false
local function ensureTables()
	if tablesReady then
		return true
	end
	local ok = db.query("CREATE TABLE IF NOT EXISTS `" .. cfg.tableKills .. "` (" ..
		"`player_id` int(11) NOT NULL, `monster` varchar(64) NOT NULL, `kills` int(10) unsigned NOT NULL DEFAULT 0, " ..
		"PRIMARY KEY (`player_id`, `monster`), " ..
		"CONSTRAINT `" .. cfg.tableKills .. "_players_fk` FOREIGN KEY (`player_id`) REFERENCES `players` (`id`) ON DELETE CASCADE" ..
		") ENGINE=InnoDB DEFAULT CHARSET=utf8")
	ok = db.query("CREATE TABLE IF NOT EXISTS `" .. cfg.tableTasks .. "` (" ..
		"`player_id` int(11) NOT NULL, `task` varchar(80) NOT NULL, `accepted_at` int(10) unsigned NOT NULL, " ..
		"`kind` varchar(8) NOT NULL, `target` varchar(64) NOT NULL, `label` varchar(64) NOT NULL, " ..
		"`lo` int(11) NOT NULL DEFAULT 0, `hi` int(11) NOT NULL DEFAULT 0, `level` int(11) NOT NULL DEFAULT 0, " ..
		"`progress` int(11) NOT NULL DEFAULT 0, `required` int(11) NOT NULL DEFAULT 0, " ..
		"`status` tinyint(4) NOT NULL DEFAULT 0, `mc` tinyint(4) NOT NULL DEFAULT 0, " ..
		"`done_day` int(11) NOT NULL DEFAULT 0, `done_week` int(11) NOT NULL DEFAULT 0, " ..
		"PRIMARY KEY (`player_id`, `task`, `accepted_at`), KEY `done` (`player_id`, `status`, `done_week`), " ..
		"CONSTRAINT `" .. cfg.tableTasks .. "_players_fk` FOREIGN KEY (`player_id`) REFERENCES `players` (`id`) ON DELETE CASCADE" ..
		") ENGINE=InnoDB DEFAULT CHARSET=utf8") and ok
	tablesReady = ok and true or false
	return tablesReady
end

-- ---------------------------------------------------------------- catalogue
-- every monster name of monsters.xml (this engine loads a monster type on first use, so Game.getMonsterTypes() only
-- lists the ones loaded so far) and whether it is defined under monster/monsters/chaos/ (the "Chaos" category)
local function xmlMonsters()
	local names, chaos = {}, {}
	local f = io.open("data/monster/monsters.xml", "r")
	if not f then
		return names, chaos
	end
	for line in f:lines() do
		local name = line:match('name%s*=%s*"([^"]+)"')
		local file = line:match('file%s*=%s*"([^"]+)"')
		if name and file then
			names[#names + 1] = name
			if file:lower():find("chaos/", 1, true) then
				chaos[name:lower()] = true
			end
		end
	end
	f:close()
	return names, chaos
end

local function call(mt, method)
	local ok, v = pcall(function() return mt[method](mt) end)
	if ok then
		return v
	end
	return nil
end

function X.build()
	local names, chaos = xmlMonsters()
	-- plus the monsters registered from Lua (data/monster/*.lua, Game.createMonsterType)
	for key in pairs(Game.getMonsterTypes and Game.getMonsterTypes() or {}) do
		names[#names + 1] = key
	end
	-- one entry per shown name; when two registered names show the same name (a quest copy "Demon (Goblin)" whose
	-- definition is called "Demon"), the monster registered under that very name wins
	local byKey, canonical, order, tried = {}, {}, {}, {}
	for _, raw in ipairs(names) do
		local rawKey = raw:lower()
		local mt = (not tried[rawKey]) and MonsterType(raw) or nil
		tried[rawKey] = true
		local name = mt and call(mt, "name")
		local key = name and name:lower()
		if key and (not byKey[key] or (not canonical[key] and rawKey == key)) then
			local exp = tonumber(call(mt, "experience")) or 0
			local outfit = call(mt, "outfit") or {}
			local look = tonumber(outfit.lookType) or 0
			if not C.excluded(name, exp, cfg) and (look > 0 or (tonumber(outfit.lookTypeEx) or 0) > 0) then
				if not byKey[key] then
					order[#order + 1] = key
				end
				canonical[key] = rawKey == key
				byKey[key] = C.buildEntry({
					name = name, exp = exp, health = call(mt, "maxHealth"), minLevel = call(mt, "minLevel"),
					maxLevel = call(mt, "maxLevel"), boss = call(mt, "isBoss") and true or false,
					race = RACES[tonumber(call(mt, "race")) or 0], chaos = chaos[key] or chaos[rawKey], outfit = outfit
				}, SPAWNS[key], cfg)
			end
		end
	end
	local entries = {}
	for _, key in ipairs(order) do
		entries[#entries + 1] = byKey[key]
	end
	X.catalogue = C.index(entries, cfg)
	X.catNames = {}
	for _, cat in ipairs(cfg.categories) do
		X.catNames[cat.key] = cat.name
	end
	print(string.format("[ChaosBestiary] %d bestiary entries", #entries))
	return X.catalogue
end

function X.cat()
	return X.catalogue or X.build()
end

-- ---------------------------------------------------------------- player state
-- st = {guid, kills = {[key] = n}, dirty = {[key] = true}, tasks = {[key] = task}, doneDay, doneWeek, doneKeys,
--       day, week, points = stage points, completed = {[key] = true}, known = n}
local function now()
	return os.time()
end

local function taskDay()
	return C.day(now(), cfg)
end

local function taskWeek()
	return C.week(now(), cfg)
end

local function recount(st)
	local cat = X.cat()
	local s = C.summary(cat, function(key) return st.kills[key] end, cfg)
	st.points, st.known, st.completedCount = s.points, s.known, s.completed
	st.completed = {}
	for key, n in pairs(st.kills) do
		local e = cat.byKey[key]
		if e and C.stageOf(n, e.th) >= 4 then
			st.completed[key] = C.bonusOf(e, cfg)
		end
	end
	return s
end

local function loadTasks(st)
	local day, week = taskDay(), taskWeek()
	st.day, st.week = day, week
	st.tasks, st.doneKeys, st.doneDay, st.doneWeek = {}, {}, 0, 0
	-- finished tasks older than five weeks are history nobody reads
	db.asyncQuery(string.format("DELETE FROM `%s` WHERE `player_id` = %d AND `status` = 1 AND `done_week` < %d",
		cfg.tableTasks, st.guid, Chaos.dayKey(now() - 35 * 86400)))
	for _, r in ipairs(Chaos.select(string.format("SELECT `task`, `accepted_at`, `kind`, `target`, `label`, `lo`, `hi`, " ..
		"`level`, `progress`, `required`, `status`, `mc`, `done_day`, `done_week` FROM `%s` WHERE `player_id` = %d AND " ..
		"(`status` = 0 OR `done_week` >= %d)", cfg.tableTasks, st.guid, week), {{"task", "s"}, {"accepted_at", "n"},
		{"kind", "s"}, {"target", "s"}, {"label", "s"}, {"lo", "n"}, {"hi", "n"}, {"level", "n"}, {"progress", "n"},
		{"required", "n"}, {"status", "n"}, {"mc", "n"}, {"done_day", "n"}, {"done_week", "n"}})) do
		if r.status == 0 then
			st.tasks[r.task] = {key = r.task, at = r.accepted_at, kind = r.kind, target = r.target, label = r.label,
				lo = r.lo, hi = r.hi, level = r.level, progress = r.progress, required = r.required, status = 0, mc = r.mc}
		else
			if r.done_week == week then
				st.doneWeek = st.doneWeek + 1
			end
			if r.done_day == day then
				st.doneDay = st.doneDay + 1
				st.doneKeys[r.task] = true
			end
		end
	end
end

local function loadPlayer(player)
	ensureTables()
	local guid = player:getGuid()
	local st = {guid = guid, kills = {}, dirty = {}}
	for _, r in ipairs(Chaos.select(string.format("SELECT `monster`, `kills` FROM `%s` WHERE `player_id` = %d",
		cfg.tableKills, guid), {{"monster", "s"}, {"kills", "n"}})) do
		st.kills[r.monster] = r.kills
	end
	loadTasks(st)
	recount(st)
	X.players[guid] = st
	return st
end
X.loadPlayer = loadPlayer -- (GM / test use)

local function stateOf(player)
	local st = X.players[player:getGuid()]
	if not st then
		return loadPlayer(player)
	end
	if st.day ~= taskDay() then
		-- a new task day (or week): the counters start again, active tasks stay
		local tasks = st.tasks
		loadTasks(st)
		for key, t in pairs(tasks) do
			if t.status == 0 then
				st.tasks[key] = t
			end
		end
	end
	return st
end
X.stateOf = stateOf

local function flush(st)
	local values = {}
	for key in pairs(st.dirty) do
		values[#values + 1] = string.format("(%d, %s, %d)", st.guid, db.escapeString(key), st.kills[key] or 0)
	end
	st.dirty = {}
	if #values == 0 then
		return
	end
	-- a few hundred monsters at most per character; batches keep the statements short
	for i = 1, #values, 100 do
		local part = {}
		for j = i, math.min(#values, i + 99) do
			part[#part + 1] = values[j]
		end
		db.asyncQuery(string.format("INSERT INTO `%s` (`player_id`, `monster`, `kills`) VALUES %s " ..
			"ON DUPLICATE KEY UPDATE `kills` = VALUES(`kills`)", cfg.tableKills, table.concat(part, ", ")))
	end
end
X.flush = flush

local function taskPoints(player)
	return math.max(0, player:getStorageValue(cfg.taskPointsStorage))
end

function X.pointsOf(player)
	local st = stateOf(player)
	return (st.points or 0) + taskPoints(player)
end

function X.rankOf(player)
	return C.rankOf(X.pointsOf(player), cfg)
end

-- ---------------------------------------------------------------- messages
local function notify(player, message, look)
	player:sendExtendedOpcode(ChaosOpcodes.notifications, json.encode({action = "bestiary", message = message,
		monsterLookType = (look and look > 0) and look or nil}))
end

local function lookOf(e)
	return e.outfit and tonumber(e.outfit.lookType) or 0
end

local function entryOutfit(e)
	local o = e.outfit or {}
	return {type = tonumber(o.lookType) or 0, auxType = tonumber(o.lookTypeEx) or 0, head = o.lookHead,
		body = o.lookBody, legs = o.lookLegs, feet = o.lookFeet, addons = o.lookAddons}
end

local function limits(st)
	return {active = C.activeCount(st), maxActive = cfg.maxActive, doneDay = st.doneDay, dailyLimit = cfg.dailyLimit,
		doneWeek = st.doneWeek, weeklyLimit = cfg.weeklyLimit}
end

local function sendSummary(player, open)
	local st = stateOf(player)
	local cat = X.cat()
	local s = recount(st)
	local points = s.points + taskPoints(player)
	local rank = C.rankOf(points, cfg)
	local cats = {}
	for _, c in ipairs(cfg.categories) do
		local n = s.cats[c.key]
		if n and n.total > 0 then
			cats[#cats + 1] = {key = c.key, name = c.name, known = n.known, completed = n.completed, total = n.total}
		end
	end
	local diffs = {}
	for _, d in ipairs(cfg.difficulties) do
		diffs[#diffs + 1] = {key = d.key, name = d.name, kills = d.kills, bonus = d.bonus}
	end
	diffs[#diffs + 1] = {key = cfg.boss.key, name = cfg.boss.name, kills = cfg.boss.kills, bonus = cfg.boss.bonus}
	Chaos.send(player, OPCODE, "summary", {
		open = open and true or false, total = s.total, known = s.known, completed = s.completed,
		percent = C.percent(s.completed, s.total), points = points, stagePoints = s.points, taskPoints = taskPoints(player),
		rank = rank, cats = cats, diffs = diffs, stages = cfg.stageNames, tasks = limits(st),
		count = #cat.list
	})
end

-- the whole list in packets of about chunkBytes, one per chunkDelay ms (as the spellbook)
local function rowOf(e, st)
	local kills = st.kills[e.key] or 0
	local stage = C.stageOf(kills, e.th)
	return {e.id, e.name, e.cat, e.diff, e.level, kills, stage, stage >= 1 and lookOf(e) or 0}
end

local function sendList(player)
	local st = stateOf(player)
	local rows = {}
	for _, e in ipairs(X.cat().list) do
		rows[#rows + 1] = rowOf(e, st)
	end
	local chunks = C.chunk(rows, cfg.chunkBytes, json.encode)
	local cid = player:getId()
	for i, part in ipairs(chunks) do
		addEvent(function()
			local p = Player(cid)
			if p then
				Chaos.send(p, OPCODE, "list", {first = i == 1, last = i == #chunks, rows = part})
			end
		end, (i - 1) * cfg.chunkDelay)
	end
end

local function towns()
	if X.towns then
		return X.towns
	end
	local list = {}
	for _, t in ipairs(Game.getTowns() or {}) do
		local ok, pos = pcall(function() return t:getTemplePosition() end)
		if ok and pos and pos.x > 0 then
			list[#list + 1] = {name = t:getName(), x = pos.x, y = pos.y}
		end
	end
	X.towns = list
	return list
end

local function itemInfo(id)
	local it = ItemType(id)
	if not it or it:getId() == 0 then
		return nil
	end
	return it:getName(), it:getClientId()
end

local function sendEntry(player, id)
	local e = X.cat().byId[id]
	if not e then
		return
	end
	local st = stateOf(player)
	local kills = st.kills[e.key] or 0
	local stage = C.stageOf(kills, e.th)
	local diff = C.difficultyByKey(e.diff, cfg)
	local data = {id = e.id, name = e.name, cat = e.cat, diff = e.diff, diffName = diff and diff.name, level = e.level,
		kills = kills, stage = stage, th = e.th, next = C.nextOf(kills, e.th), boss = e.boss,
		points = diff and diff.points, bonus = C.bonusOf(e, cfg), spawns = e.spawns > 0}
	local mt = MonsterType(e.name)
	if stage >= 1 then
		data.outfit = entryOutfit(e)
		data.health, data.exp = e.health, e.exp
		if e.minLevel > 0 then
			data.minLevel, data.maxLevel = e.minLevel, e.maxLevel
		end
	end
	if stage >= 2 and mt then
		data.elements = C.elements(call(mt, "getElementList"))
		data.immunities = C.immunities(call(mt, "combatImmunities"))
		data.areas = C.areaTexts(e.areas, towns(), cfg.areasMax)
	end
	if stage >= 2 and mt then
		data.loot = C.loot(call(mt, "getLoot") or {}, itemInfo, stage, cfg)
	end
	if stage >= 3 and ChaosLoot and ChaosLoot.uniqueList then
		local ok, list = pcall(ChaosLoot.uniqueList)
		local uniques = C.uniquesOf(ok and list or {}, e.key)
		for _, u in ipairs(uniques) do
			local it = ItemType(u.id)
			u.cid = it and it:getClientId() or u.id
		end
		data.uniques = uniques
	end
	local can, task = C.canTakeHunt(e, player:getLevel(), kills, cfg)
	if can then
		local ok, why = C.canAccept(task, st, cfg)
		if not ok then
			can, task = false, why
		end
	end
	data.task = {can = can, text = not can and task or nil, required = can and task.required or nil,
		active = st.tasks["h:" .. e.key] and true or false}
	if can then
		data.task.reward = C.taskReward(task, player:getLevel(), cfg, bountyCfg)
	end
	Chaos.send(player, OPCODE, "entry", data)
end

-- ---------------------------------------------------------------- tracker (tasks + bounty contracts)
local function bountyRows(player, rows)
	local B = ChaosBounty
	if B and B.board and not B.current then
		pcall(B.board) -- right after a restart the board is rolled at its first use
	end
	if not B or not B.players or not B.current then
		return
	end
	local bst = B.players[player:getGuid()]
	if not bst then
		return
	end
	local keys = {}
	for key, e in pairs(bst.entries or {}) do
		if e.status == 0 and e.day == B.current.day then
			keys[#keys + 1] = key
		end
	end
	table.sort(keys)
	for _, key in ipairs(keys) do
		local e = bst.entries[key]
		local label = e.monster
		for _, c in ipairs((B.current.byName or {})[tostring(e.monster):lower()] or {}) do
			if c.key == key and c.type == "elite" then
				label = string.format("%s+ %s", c.tier, e.monster)
			elseif c.key == key and c.type == "boss" then
				label = e.monster .. " (boss)"
			end
		end
		rows[#rows + 1] = {k = "bounty", key = key, label = label, p = e.progress, r = e.required}
	end
end

local function taskList(st)
	local list = {}
	for _, t in pairs(st.tasks) do
		if t.status == 0 then
			list[#list + 1] = t
		end
	end
	table.sort(list, function(a, b)
		if a.at ~= b.at then
			return a.at < b.at
		end
		return a.key < b.key
	end)
	return list
end

local function sendTracker(player)
	local st = stateOf(player)
	local rows = {}
	for _, t in ipairs(taskList(st)) do
		local label = t.kind == "family" and string.format("%s (%d-%d)", t.label, t.lo, t.hi) or t.label
		rows[#rows + 1] = {k = "task", key = t.key, label = label, p = t.progress, r = t.required}
	end
	bountyRows(player, rows)
	while #rows > cfg.trackerMax do
		table.remove(rows)
	end
	Chaos.send(player, OPCODE, "tracker", {rows = rows})
end
X.sendTracker = sendTracker

-- one tracker push per player and tick, whatever triggered it (several kills, the bounty board)
local trackerQueued = {}
local function queueTracker(player)
	local cid = player:getId()
	if trackerQueued[cid] then
		return
	end
	trackerQueued[cid] = true
	addEvent(function()
		trackerQueued[cid] = nil
		local p = Player(cid)
		if p then
			sendTracker(p)
		end
	end, 150)
end
X.queueTracker = queueTracker

-- ---------------------------------------------------------------- task board
-- the picture of a family task: its most common monster in the level window
local function familyFace(t)
	local best
	for _, e in ipairs(X.cat().list) do
		if e.cat == t.target and not e.boss and e.level >= (t.lo or 0) and e.level <= (t.hi or 0)
				and (e.spawns or 0) > 0 and (not best or e.spawns > best.spawns) then
			best = e
		end
	end
	return best
end

local function taskView(t, player)
	local e
	if t.kind == "hunt" then
		e = X.cat().byKey[t.target]
	else
		e = familyFace(t)
	end
	return {key = t.key, kind = t.kind, label = t.label, target = t.target, lo = t.lo, hi = t.hi, level = t.level,
		required = t.required, progress = t.progress or 0, monsters = t.monsters,
		look = e and lookOf(e) or 0, outfit = e and entryOutfit(e) or nil,
		reward = C.taskReward(t, player:getLevel(), cfg, bountyCfg)}
end

-- the board is rolled for the character's level at its first look of the task day (storages taskPointsStorage + 1 and
-- + 2), so levelling up during the day does not swap the offers
local function boardLevel(player)
	local day = taskDay()
	if player:getStorageValue(cfg.taskPointsStorage + 1) ~= day then
		player:setStorageValue(cfg.taskPointsStorage + 1, day)
		player:setStorageValue(cfg.taskPointsStorage + 2, player:getLevel())
	end
	return math.max(1, player:getStorageValue(cfg.taskPointsStorage + 2))
end

local function sendBoard(player)
	local st = stateOf(player)
	local offers = C.offers(taskDay(), st.guid, boardLevel(player), X.cat(), cfg)
	local list, active = {}, {}
	for _, o in ipairs(offers) do
		local v = taskView(o, player)
		local cur = st.tasks[o.key]
		v.state = (cur and cur.status == 0) and "active" or (st.doneKeys[o.key] and "done" or "open")
		if v.state == "active" then
			v.progress = cur.progress
		end
		list[#list + 1] = v
	end
	for _, t in ipairs(taskList(st)) do
		active[#active + 1] = taskView(t, player)
	end
	local data = limits(st)
	data.offers, data.tasks = list, active
	data.nextIn = math.max(0, C.nextRoll(now(), cfg) - now())
	Chaos.send(player, OPCODE, "board", data)
end

local function startTask(player, st, task)
	local ok, err = C.canAccept(task, st, cfg)
	if not ok then
		player:sendCancelMessage(err)
		return false
	end
	local at = now()
	-- two tasks of the same key accepted in the same second would share a row: never (the key is active)
	local mc = Chaos.isMultiClient(player) and 1 or 0
	local t = {key = task.key, at = at, kind = task.kind, target = task.target, label = task.label, lo = task.lo or 0,
		hi = task.hi or 0, level = task.level or 0, progress = 0, required = task.required, status = 0, mc = mc}
	st.tasks[t.key] = t
	db.asyncQuery(string.format("INSERT INTO `%s` (`player_id`, `task`, `accepted_at`, `kind`, `target`, `label`, `lo`, " ..
		"`hi`, `level`, `progress`, `required`, `status`, `mc`) VALUES (%d, %s, %d, %s, %s, %s, %d, %d, %d, 0, %d, 0, %d)",
		cfg.tableTasks, st.guid, db.escapeString(t.key), at, db.escapeString(t.kind), db.escapeString(t.target),
		db.escapeString(t.label), t.lo, t.hi, t.level, t.required, mc))
	local what = t.kind == "family" and string.format("%d %s of level %d-%d", t.required, t.label, t.lo, t.hi)
		or string.format("%d x %s", t.required, t.label)
	player:sendTextMessage(MESSAGE_INFO_DESCR, "Kill task accepted: " .. what .. ".")
	if mc == 1 and not cfg.mcReward then
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE,
			"Another character from your connection is online: you may hunt, but this task will pay no reward.")
	end
	queueTracker(player)
	return true
end

local function accept(player, key)
	if type(key) ~= "string" or #key > 80 then
		return
	end
	local st = stateOf(player)
	local task
	for _, o in ipairs(C.offers(taskDay(), st.guid, boardLevel(player), X.cat(), cfg)) do
		if o.key == key then
			task = o
		end
	end
	startTask(player, st, task)
	sendBoard(player)
end

-- a hunt task from a bestiary entry
local function take(player, id)
	local e = X.cat().byId[id]
	local st = stateOf(player)
	local ok, task = C.canTakeHunt(e, player:getLevel(), e and st.kills[e.key] or 0, cfg)
	if not ok then
		player:sendCancelMessage(task)
	else
		startTask(player, st, task)
	end
	if e then
		sendEntry(player, e.id)
	end
	sendBoard(player)
end

local function abandon(player, key)
	local st = stateOf(player)
	local t = type(key) == "string" and st.tasks[key]
	if not t or t.status ~= 0 then
		return
	end
	st.tasks[key] = nil
	db.asyncQuery(string.format("DELETE FROM `%s` WHERE `player_id` = %d AND `task` = %s AND `accepted_at` = %d",
		cfg.tableTasks, st.guid, db.escapeString(key), t.at))
	player:sendTextMessage(MESSAGE_INFO_DESCR, "Kill task abandoned: " .. t.label .. ".")
	sendBoard(player)
	queueTracker(player)
end

-- ---------------------------------------------------------------- rewards
local function giveStack(player, id, count)
	if count <= 0 then
		return false
	end
	local rest = count - Chaos.giveItem(player, id, count)
	if rest <= 0 then
		return false
	end
	local inbox = player:getInbox()
	while inbox and rest > 0 do
		local n = math.min(rest, 100)
		inbox:addItem(id, n, INDEX_WHEREEVER or -1, FLAG_NOLIMIT)
		rest = rest - n
	end
	return true
end

local function plural(n, word)
	return n == 1 and word or word .. "s"
end

local function payTask(player, st, t)
	st.doneDay, st.doneWeek = st.doneDay + 1, st.doneWeek + 1
	st.doneKeys[t.key] = true
	st.tasks[t.key] = nil
	db.asyncQuery(string.format("UPDATE `%s` SET `progress` = %d, `status` = 1, `mc` = %d, `done_day` = %d, " ..
		"`done_week` = %d WHERE `player_id` = %d AND `task` = %s AND `accepted_at` = %d", cfg.tableTasks, t.progress,
		t.mc, st.day, st.week, st.guid, db.escapeString(t.key), t.at))
	local e = t.kind == "hunt" and X.cat().byKey[t.target]
	if t.mc == 1 and not cfg.mcReward then
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, string.format(
			"Kill task completed: %s. Another character from your connection was online during the hunt: no reward.", t.label))
		return
	end
	local r = C.taskReward(t, player:getLevel(), cfg, bountyCfg)
	if r.gold > 0 then
		player:setBankBalance(player:getBankBalance() + r.gold)
	end
	local inbox = giveStack(player, ITEMS.chaos, r.chaos)
	inbox = giveStack(player, ITEMS.divine, r.divine) or inbox
	if r.exp > 0 then
		player:addExperience(r.exp, true)
	end
	player:setStorageValue(cfg.taskPointsStorage, taskPoints(player) + r.points)
	local parts = {}
	if r.gold > 0 then
		parts[#parts + 1] = r.gold .. " gold (bank)"
	end
	if r.chaos > 0 then
		parts[#parts + 1] = r.chaos .. plural(r.chaos, " Orb of Upheaval")
	end
	if r.divine > 0 then
		parts[#parts + 1] = r.divine .. plural(r.divine, " Orb of Fate")
	end
	if r.exp > 0 then
		parts[#parts + 1] = r.exp .. " experience"
	end
	parts[#parts + 1] = r.points .. " bestiary points"
	player:sendTextMessage(MESSAGE_EVENT_ADVANCE, string.format("Kill task completed: %s. Reward: %s.%s", t.label,
		table.concat(parts, ", "), inbox and " Your backpack was full: the orbs are in your inbox." or ""))
	notify(player, string.format("Kill task completed: %d %s.", t.required, t.label), e and lookOf(e) or nil)
	player:getPosition():sendMagicEffect(CONST_ME_FIREWORK_YELLOW)
	if ChaosAchievements then
		pcall(ChaosAchievements.progress, player, "bestiary_tasks", 1)
		pcall(ChaosAchievements.set, player, "bestiary_points", X.pointsOf(player))
	end
end

-- ---------------------------------------------------------------- kills
local function creditKill(player, e)
	local st = stateOf(player)
	local kills, before, after = C.addKill(st.kills[e.key] or 0, e.th)
	st.kills[e.key] = kills
	st.dirty[e.key] = true
	local nextAt = C.nextOf(kills, e.th)
	local changed = false
	if after > before then
		local diff = C.difficultyByKey(e.diff, cfg)
		local gained = C.stagePoints(diff, after) - C.stagePoints(diff, before)
		st.points = (st.points or 0) + gained
		local stageName = cfg.stageNames[after] or ("stage " .. after)
		local text
		if after == 1 then
			st.known = (st.known or 0) + 1
			text = string.format("Bestiary: %s discovered (+%d points).", e.name, gained)
		elseif after >= 4 then
			st.completedCount = (st.completedCount or 0) + 1
			st.completed[e.key] = C.bonusOf(e, cfg)
			local b = st.completed[e.key]
			text = string.format("Bestiary: %s completed (+%d points). You deal %d%% more damage to it and gain %d%% more " ..
				"experience from it.", e.name, gained, b.damage, b.exp)
		else
			text = string.format("Bestiary: %s %s (+%d points).", e.name, stageName:lower(), gained)
		end
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, text)
		if after >= 2 then
			notify(player, text, lookOf(e))
		end
		flush(st)
		if ChaosAchievements then
			pcall(ChaosAchievements.set, player, "bestiary_known", st.known or 0)
			pcall(ChaosAchievements.set, player, "bestiary_completed", st.completedCount or 0)
			pcall(ChaosAchievements.set, player, "bestiary_points", (st.points or 0) + taskPoints(player))
		end
	end
	Chaos.send(player, OPCODE, "kill", {id = e.id, kills = kills, stage = after, next = nextAt})
	-- tasks
	local mc = nil
	for _, t in ipairs(taskList(st)) do
		if C.matches(t, e) then
			if mc == nil then
				mc = Chaos.isMultiClient(player)
			end
			if mc then
				t.mc = 1
			end
			local crossed, done = C.milestones(t, cfg.progressNotices)
			changed = true
			if done then
				payTask(player, st, t)
			else
				for _, pct in ipairs(crossed or {}) do
					player:sendTextMessage(MESSAGE_INFO_DESCR, string.format("Kill task %s: %d%% done (%d/%d).", t.label, pct,
						t.progress, t.required))
				end
				-- progress is written every 10 kills and at the milestones (the row is rewritten at completion)
				if t.progress % 10 == 0 or #(crossed or {}) > 0 then
					db.asyncQuery(string.format("UPDATE `%s` SET `progress` = %d, `mc` = %d WHERE `player_id` = %d AND " ..
						"`task` = %s AND `accepted_at` = %d", cfg.tableTasks, t.progress, t.mc, st.guid, db.escapeString(t.key), t.at))
				end
			end
		end
	end
	if changed then
		queueTracker(player)
	end
end

local function playerOf(creature)
	if not creature then
		return nil
	end
	if creature:isPlayer() then
		return creature
	end
	local master = creature:getMaster()
	if master and master:isPlayer() then
		return master
	end
	return nil
end

function X.onKill(creature, killer, mostDamageKiller)
	local e = X.cat().byKey[typeNameOf(creature):lower()]
	if not e then
		return
	end
	local killers, seen = {}, {}
	for _, k in ipairs({playerOf(killer), playerOf(mostDamageKiller)}) do
		if k and not seen[k:getId()] then
			seen[k:getId()] = true
			killers[#killers + 1] = k
		end
	end
	if #killers == 0 then
		return
	end
	local credited = C.credit(killers, function(p)
		local party = p:getParty()
		if not party then
			return nil
		end
		local members = party:getMembers()
		members[#members + 1] = party:getLeader()
		return members
	end, function(p) return p:getPosition() end, cfg.partyRange, function(p) return p:getId() end)
	for _, p in ipairs(credited) do
		creditKill(p, e)
	end
end

local death = CreatureEvent("ChaosBestiaryDeath")
function death.onDeath(creature, corpse, killer, mostDamageKiller, lastHitUnjustified, mostDamageUnjustified)
	local ok, err = pcall(X.onKill, creature, killer, mostDamageKiller)
	if not ok then
		print("[ChaosBestiary] kill: " .. tostring(err))
	end
	return true
end
death:register()

local spawn = EventCallback
spawn.onSpawn = function(self, position, startup, artificial)
	if not self:getMaster() then
		self:registerEvent("ChaosBestiaryDeath")
	end
	return true
end
spawn:register()

-- ---------------------------------------------------------------- bonuses
local function bonusAgainst(player, name)
	local st = X.players[player:getGuid()]
	return st and st.completed and st.completed[name:lower()] or nil
end

local dealt = CreatureEvent("ChaosBestiaryDealt")
function dealt.onHealthChange(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType, origin)
	if primaryType == COMBAT_HEALING then
		return primaryDamage, primaryType, secondaryDamage, secondaryType
	end
	local p = playerOf(attacker)
	local b = p and bonusAgainst(p, typeNameOf(creature))
	if b and (b.damage or 0) > 0 then
		local function scale(v)
			local a = math.floor(math.abs(v) * (100 + b.damage) / 100 + 1e-6)
			return v < 0 and -a or a
		end
		primaryDamage, secondaryDamage = scale(primaryDamage), scale(secondaryDamage)
	end
	return primaryDamage, primaryType, secondaryDamage, secondaryType
end
dealt:register()

local targetCb = EventCallback
targetCb.onTargetCombat = function(creature, target)
	if creature and target and target:isMonster() then
		local p = playerOf(creature)
		if p and bonusAgainst(p, typeNameOf(target)) then
			target:registerEvent("ChaosBestiaryDealt")
		end
	end
	return RETURNVALUE_NOERROR
end
targetCb:register()

local xpCb = EventCallback
xpCb.onGainExperience = function(self, source, exp, rawExp)
	if not source or not source:isMonster() then
		return exp
	end
	local st = X.players[self:getGuid()]
	if not st then
		return exp
	end
	local b = st.completed and st.completed[source:getName():lower()]
	local pct = (b and b.exp or 0) + C.rankOf((st.points or 0) + taskPoints(self), cfg).exp
	if pct > 0 then
		return math.floor(exp * (100 + pct) / 100 + 1e-9)
	end
	return exp
end
xpCb:register(1)

-- ---------------------------------------------------------------- bounty board -> tracker
-- the bounty board refreshes its window after an accept, an abandon and a completion: the tracker follows. Its kills
-- are caught by the bounty progress push (wrapped below), so no edit of bounty.lua is needed.
local function wrapBounty()
	local B = ChaosBounty
	if not B or B.bestiaryWrapped or not B.sendBoard then
		return
	end
	B.bestiaryWrapped = true
	local sendBoard = B.sendBoard
	B.sendBoard = function(player, ...)
		local r = sendBoard(player, ...)
		if player then
			queueTracker(player)
		end
		return r
	end
	local onKill = B.onKill
	if onKill then
		B.onKill = function(creature, killer, mostDamageKiller, ...)
			local r = onKill(creature, killer, mostDamageKiller, ...)
			-- only characters that hold a contract today get a tracker push
			local function push(p)
				local bst = p and B.players and B.players[p:getGuid()]
				if bst and B.current and B.activeCount(bst.entries or {}, B.current.day) > 0 then
					queueTracker(p)
				end
			end
			for _, k in ipairs({playerOf(killer), playerOf(mostDamageKiller)}) do
				push(k)
				local party = k:getParty()
				if party then
					for _, m in ipairs(party:getMembers()) do
						push(m)
					end
					push(party:getLeader())
				end
			end
			return r
		end
	end
end

-- ---------------------------------------------------------------- events
local startup = GlobalEvent("ChaosBestiaryStartup")
function startup.onStartup()
	ensureTables()
	X.build()
	wrapBounty()
	return true
end
startup:register()

local flusher = GlobalEvent("ChaosBestiaryFlush")
function flusher.onThink(interval)
	for guid, st in pairs(X.players) do
		flush(st)
	end
	return true
end
flusher:interval(cfg.flushSeconds * 1000)
flusher:register()

local login = CreatureEvent("ChaosBestiaryLogin")
function login.onLogin(player)
	player:registerEvent("ChaosBestiaryExtended")
	player:registerEvent("ChaosBestiaryLogout")
	wrapBounty() -- after /reload scripts the startup event does not run again
	loadPlayer(player)
	local cid = player:getId()
	addEvent(function()
		local p = Player(cid)
		if p then
			sendTracker(p)
			-- achievements: the counters are retroactive (they only go up)
			local st = X.players[p:getGuid()]
			if ChaosAchievements and st then
				pcall(ChaosAchievements.set, p, "bestiary_known", st.known or 0)
				pcall(ChaosAchievements.set, p, "bestiary_completed", st.completedCount or 0)
				pcall(ChaosAchievements.set, p, "bestiary_points", (st.points or 0) + taskPoints(p))
			end
		end
	end, 2000)
	return true
end
login:type("login")
login:register()

local logout = CreatureEvent("ChaosBestiaryLogout")
function logout.onLogout(player)
	local st = X.players[player:getGuid()]
	if st then
		flush(st)
		for _, t in pairs(st.tasks) do
			if t.status == 0 then
				db.asyncQuery(string.format("UPDATE `%s` SET `progress` = %d, `mc` = %d WHERE `player_id` = %d AND " ..
					"`task` = %s AND `accepted_at` = %d", cfg.tableTasks, t.progress, t.mc, st.guid, db.escapeString(t.key), t.at))
			end
		end
	end
	X.players[player:getGuid()] = nil
	return true
end
logout:type("logout")
logout:register()

local ext = CreatureEvent("ChaosBestiaryExtended")
function ext.onExtendedOpcode(player, opcode, buffer)
	if opcode ~= OPCODE then
		return
	end
	local msg = Chaos.decode(buffer)
	if not msg then
		return
	end
	-- per action (ratelimit.lua): requests that hit the database cannot be flooded
	if Chaos.limited and Chaos.limited(player, "bestiary." .. tostring(msg.action), 300) then
		return
	end
	local data = type(msg.data) == "table" and msg.data or {}
	local a = msg.action
	if a == "open" then
		sendSummary(player, true)
	elseif a == "list" then
		sendList(player)
	elseif a == "summary" then
		sendSummary(player, false)
	elseif a == "entry" then
		local id = Chaos.toInt(data.id, 1, 100000)
		if id then
			sendEntry(player, id)
		end
	elseif a == "board" then
		sendBoard(player)
	elseif a == "take" then
		local id = Chaos.toInt(data.id, 1, 100000)
		if id then
			take(player, id)
		end
	elseif a == "accept" then
		accept(player, data.key)
	elseif a == "abandon" then
		abandon(player, data.key)
	elseif a == "query" then
		sendTracker(player)
	end
end
ext:type("extendedopcode")
ext:register()

