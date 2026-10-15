-- Competitive records (client game_leaderboard "Records" view; extended opcode ChaosOpcodes.leaderboard, actions r*)
--
-- Fastest kills and best results of every competitive system, in three views: this week, the season and all time, with
-- filters by class, party size and variant (boss, difficulty, tier band, floor, bracket). The boards: records_config.lua
-- `boards`, filled in by ChaosRecordsCore.catalogue from the content configs. Overview and the anti-abuse rules:
-- server/README.md "Competitive records".
--
-- Sources. No content script was edited for this: the hooks wrap public functions those scripts already call (as
-- achievements.lua, guild.lua and season.lua do), installed at load, at startup and again every minute (a /reload of the
-- wrapped script replaces the function):
--   ChaosWorldBoss.computeRewards(shares, ...)  world boss kill: fight time (W.state.fightStart), damage shares
--   ChaosRiftCore.atlasSealed(info)              sealed rift / Omen guardian: tier, omen, seconds, deaths, finishers
--   ChaosExclusives.bossKill(player, key)        Ascended and Cinderheart ("ascended_<k>" / "cinder": ChaosAscended run),
--                                                guild boss ("guild_<k>": ChaosGuildBoss run)
--   ChaosLeaderboard.record(board, ...)          raid_clear, descent, arena1v1/2v2/3v3, battleground
--   ChaosTower.recordRun(player, floors, secs)   highest floor
--   ChaosAchievements.set(player, "trial_tier_<n>")   a cleared Vocation Trial (ChaosTrials.runs: class family, time)
-- Two hooks are calls into this file: ChaosRecords.towerFloor(players, floor, seconds) (one guarded line in
-- infinitytower_run.lua floorCleared) and ChaosRecords.dungeonClear(info) (dungeons.lua endRun: not added yet,
-- server/README.md "Competitive records" has the line).
--
-- Public API:
--   ChaosRecords.submit(run)   run = {board, variant, value, members = {Player | guid | {guid, name}}, size, debug,
--                              difficulty, difficultyStart, first = {key, short}} -> true | false, reason
--   ChaosRecords.titlesOf(player), ChaosRecords.badgeOf(player)
-- Protocol (JSON {action, data}) on the leaderboard opcode; leaderboard.lua ignores these actions:
--   client -> server  rmeta | rget {board, variant, size, period, group} | rfirsts
--   server -> client  rmeta {categories, periods, groups, ownGroup, season, parts}   rcat {cat, boards, part}
--                     rboard {board, variant, size, period, group, rows, own, total, record, resetIn, seasonName}
--                     rfirsts {season, seasonName, rows = [{target, board, name, members, at, value, format}]}
-- Lua 5.1 / LuaJIT compatible.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not Chaos.t then
	dofile("data/scripts/chaos/i18n_core.lua")
end
dofile("data/scripts/chaos/records_core.lua")

Chaos.recordsConfig = dofile("data/scripts/chaos/records_config.lua")
local cfg = Chaos.recordsConfig
local K = ChaosRecordsCore
ChaosRecords = ChaosRecords or {}
local R = ChaosRecords
local OPCODE = ChaosOpcodes.leaderboard or 229
local T = cfg.tables

R.boards, R.byKey = R.boards or {}, R.byKey or {}
R.firsts = R.firsts or {season = nil, byTarget = {}, byGuid = {}}
R.held = R.held or {week = 0, byGuid = {}}
R.best = {} -- slot -> all-time best value (announcements), loaded lazily
R.offset = R.offset or 0 -- staff clock shift (/records shift); a shifted clock marks every run as a debug run

local function log(text)
	print("[Chaos records] " .. text)
end

local function now()
	return os.time() + R.offset
end

local function mnow()
	return os.mtime and os.mtime() or os.time() * 1000
end

local function season()
	return ChaosSeason and ChaosSeason.current and ChaosSeason.current() or nil
end

local function keys(t)
	return K.periodKeys(t or now(), cfg.resetHour, season())
end

-- ---------------------------------------------------------------- database
local ready = false
local function ensureTables()
	if ready then
		return
	end
	db.query("CREATE TABLE IF NOT EXISTS `" .. T.best .. "` (`slot` varchar(64) NOT NULL, `period` varchar(16) NOT NULL, " ..
		"`player_id` int(11) NOT NULL, `value` bigint(20) NOT NULL DEFAULT 0, `at` int(10) unsigned NOT NULL DEFAULT 0, " ..
		"`voc` smallint(5) NOT NULL DEFAULT 0, `party` tinyint(3) unsigned NOT NULL DEFAULT 1, `members` varchar(160) NOT NULL " ..
		"DEFAULT '', `count` int(10) unsigned NOT NULL DEFAULT 0, PRIMARY KEY (`slot`, `period`, `player_id`), " ..
		"KEY `chaos_records_view` (`period`, `slot`, `value`)) ENGINE=InnoDB DEFAULT CHARSET=utf8")
	db.query("CREATE TABLE IF NOT EXISTS `" .. T.firsts .. "` (`season` varchar(16) NOT NULL, `target` varchar(64) NOT NULL, " ..
		"`board` varchar(48) NOT NULL DEFAULT '', `name` varchar(48) NOT NULL DEFAULT '', `members` varchar(160) NOT NULL " ..
		"DEFAULT '', `guids` varchar(120) NOT NULL DEFAULT '', `value` bigint(20) NOT NULL DEFAULT 0, `at` int(10) unsigned " ..
		"NOT NULL DEFAULT 0, PRIMARY KEY (`season`, `target`)) ENGINE=InnoDB DEFAULT CHARSET=utf8")
	db.query("CREATE TABLE IF NOT EXISTS `" .. T.awards .. "` (`week` int(10) unsigned NOT NULL, `slot` varchar(64) NOT NULL, " ..
		"`rank` tinyint(3) unsigned NOT NULL, `player_id` int(11) NOT NULL, `cat` varchar(16) NOT NULL DEFAULT '', " ..
		"`value` bigint(20) NOT NULL DEFAULT 0, PRIMARY KEY (`week`, `slot`, `rank`), KEY `chaos_records_awards_player` " ..
		"(`player_id`, `week`)) ENGINE=InnoDB DEFAULT CHARSET=utf8")
	db.query("CREATE TABLE IF NOT EXISTS `" .. T.boards .. "` (`key` varchar(48) NOT NULL, `cat` varchar(16) NOT NULL, " ..
		"`name` varchar(64) NOT NULL, `mode` varchar(4) NOT NULL, `format` varchar(8) NOT NULL DEFAULT '', `label` varchar(32) " ..
		"NOT NULL DEFAULT '', `variants` text NOT NULL, `sizes` varchar(64) NOT NULL DEFAULT '', `ord` smallint(5) unsigned " ..
		"NOT NULL DEFAULT 0, PRIMARY KEY (`key`)) ENGINE=InnoDB DEFAULT CHARSET=utf8")
	ready = true
end

local function esc(s)
	return db.escapeString(tostring(s or ""))
end

local function getConfig(key)
	local id = db.storeQuery("SELECT `value` FROM `server_config` WHERE `config` = " .. esc(key))
	if not id then
		return nil
	end
	local v = result.getString(id, "value")
	result.free(id)
	return tonumber(v)
end

local function setConfig(key, value)
	db.query(string.format("INSERT INTO `server_config` (`config`, `value`) VALUES (%s, %s) ON DUPLICATE KEY UPDATE " ..
		"`value` = VALUES(`value`)", esc(key), esc(value)))
end

-- ---------------------------------------------------------------- catalogue
local function sources()
	local src = {worldBosses = {}, omens = {}, ascended = {}, trials = {}, dungeons = {}}
	for _, b in ipairs(Chaos.worldBoss and Chaos.worldBoss.bosses or {}) do
		src.worldBosses[#src.worldBosses + 1] = b.name
	end
	local rc = ChaosRiftConfig
	for _, o in ipairs(rc and rc.omen and rc.omen.kinds or {}) do
		src.omens[#src.omens + 1] = {key = o.key, name = o.name, boss = o.boss}
	end
	for _, a in ipairs(ChaosUberConfig and ChaosUberConfig.kinds or {}) do
		src.ascended[#src.ascended + 1] = {key = a.key, name = a.name, boss = a.boss, final = a.final}
	end
	local gb = Chaos.guildBossConfig
	src.guildBoss = gb and gb.boss and gb.boss.boss or nil
	for _, t in ipairs(Chaos.trials and Chaos.trials.tiers or {}) do
		src.trials[#src.trials + 1] = {key = t.key, name = t.name}
	end
	local extra = Chaos.dungeons and Chaos.dungeons.extra or {}
	local ids = {}
	for id in pairs(DUNGEON_SYSTEM and DUNGEON_SYSTEM.Dungeons or {}) do
		ids[#ids + 1] = id
	end
	table.sort(ids, function(a, b) return tostring(a) < tostring(b) end)
	for _, id in ipairs(ids) do
		local d = DUNGEON_SYSTEM.Dungeons[id]
		local name = (extra[id] and extra[id].title) or (type(d) == "table" and d.Name) or ("Dungeon " .. tostring(id))
		src.dungeons[#src.dungeons + 1] = {id = id, name = name}
	end
	return src
end

-- the boards table for the website (names, labels, variants; the site has no Lua)
local function publishBoards()
	ensureTables()
	db.query("DELETE FROM `" .. T.boards .. "`")
	for i, b in ipairs(R.boards) do
		local v, s = {}, {}
		for _, x in ipairs(b.variants) do
			v[#v + 1] = x.key .. "=" .. x.name:gsub("[;=]", " ")
		end
		for _, x in ipairs(b.sizes) do
			s[#s + 1] = x.key .. "=" .. x.name
		end
		db.query(string.format("INSERT INTO `%s` (`key`, `cat`, `name`, `mode`, `format`, `label`, `variants`, `sizes`, `ord`) " ..
			"VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %d)", T.boards, esc(b.key), esc(b.cat), esc(b.name), esc(b.mode),
			esc(b.format or ""), esc(b.value or ""), esc(table.concat(v, ";")), esc(table.concat(s, ";")), i))
	end
end

function R.build()
	R.boards, R.byKey = K.catalogue(cfg, sources())
	return R.boards
end

local function catOfSlot(slot)
	local b = K.parseSlot(slot)
	local board = b and R.byKey[b]
	return board and board.cat or nil
end

-- ---------------------------------------------------------------- members
-- a Player object (userdata in the engine; any object with getGuid in the tests)
local function isPlayer(x)
	return type(x) == "userdata" or (type(x) == "table" and type(x.getGuid) == "function")
end

local function memberOf(who)
	if isPlayer(who) then
		return {guid = who:getGuid(), name = who:getName(), group = who:getGroup():getId(), voc = who:getVocation():getId(),
			mc = Chaos.isMultiClient and Chaos.isMultiClient(who) or false}
	end
	local guid = tonumber(type(who) == "table" and who.guid or who)
	if not guid then
		return nil
	end
	for _, p in ipairs(Game.getPlayers()) do
		if p:getGuid() == guid then
			return memberOf(p)
		end
	end
	local rows = Chaos.select("SELECT `name`, `group_id`, `vocation` FROM `players` WHERE `id` = " .. guid,
		{{"name", "s"}, {"group_id", "n"}, {"vocation", "n"}})
	local r = rows[1]
	if not r then
		return nil
	end
	return {guid = guid, name = r.name, group = r.group_id, voc = r.vocation}
end

-- ---------------------------------------------------------------- submit
local function bestOf(slot, mode)
	if R.best[slot] == nil then
		local rows = Chaos.select(string.format("SELECT `value` FROM `%s` WHERE `slot` = %s AND `period` = 'all' AND `value` > 0 " ..
			"ORDER BY `value` %s LIMIT 1", T.best, esc(slot), mode == "min" and "ASC" or "DESC"), {{"value", "n"}})
		R.best[slot] = rows[1] and rows[1].value or false
	end
	return R.best[slot] or nil
end

-- build(lang) -> the text: each player reads it in their language (Chaos.broadcast); the log and the notification
-- are English
local function broadcast(build)
	local text = Chaos.broadcast(MESSAGE_EVENT_ADVANCE, build)
	if ChaosNotify and ChaosNotify.gmBroadcast then
		pcall(ChaosNotify.gmBroadcast, nil, text)
	end
	log(text)
end

local function upsert(slot, period, m, value, mode, at, party, names)
	local better = mode == "min" and "VALUES(`value`) < `value`" or "VALUES(`value`) > `value`"
	local valueSet = mode == "add" and "`value` = `value` + VALUES(`value`)" or ("`value` = IF(" .. better .. ", VALUES(`value`), `value`)")
	local cond = mode == "add" and "1" or better
	-- assignments run left to right: everything that compares with the old value comes before `value` itself
	db.asyncQuery(string.format("INSERT INTO `%s` (`slot`, `period`, `player_id`, `value`, `at`, `voc`, `party`, `members`, " ..
		"`count`) VALUES (%s, %s, %d, %d, %d, %d, %d, %s, 1) ON DUPLICATE KEY UPDATE `count` = `count` + 1, " ..
		"`at` = IF(%s, VALUES(`at`), `at`), `voc` = IF(%s, VALUES(`voc`), `voc`), `party` = IF(%s, VALUES(`party`), `party`), " ..
		"`members` = IF(%s, VALUES(`members`), `members`), %s", T.best, esc(slot), esc(period), m.guid, value, at, m.voc or 0,
		party, esc(names:sub(1, 160)), cond, cond, cond, cond, valueSet))
end

local function realmFirst(board, run, members, value)
	local target, short, display = K.firstTarget(board, run.variant, run)
	if not target then
		return
	end
	local k = keys()
	if R.firsts.season ~= k.season then
		R.loadFirsts()
	end
	if R.firsts.byTarget[target] then
		return
	end
	local guids = {}
	for _, m in ipairs(members) do
		guids[#guids + 1] = tostring(m.guid)
	end
	local entry = {target = target, board = board.key, short = short, members = K.names(members), at = now(), value = value}
	R.firsts.byTarget[target] = entry
	for _, m in ipairs(members) do
		R.firsts.byGuid[m.guid] = R.firsts.byGuid[m.guid] or {}
		table.insert(R.firsts.byGuid[m.guid], entry)
	end
	db.query(string.format("INSERT IGNORE INTO `%s` (`season`, `target`, `board`, `name`, `members`, `guids`, `value`, `at`) " ..
		"VALUES (%s, %s, %s, %s, %s, %s, %d, %d)", T.firsts, esc(k.season), esc(target), esc(board.key), esc(short),
		esc(entry.members:sub(1, 160)), esc(table.concat(guids, ","):sub(1, 120)), value, entry.at))
	if cfg.announceFirst then
		local seasonName = K.seasonName(k.season, season())
		broadcast(function(lang) return K.firstText(display, members, seasonName, lang) end)
	end
	for _, m in ipairs(members) do
		local p = Player(m.name)
		if p and ChaosNameplate and ChaosNameplate.refresh then
			pcall(ChaosNameplate.refresh, p)
		end
	end
end

function R.submit(run)
	if type(run) ~= "table" then
		return false, "no run"
	end
	local board = R.byKey[run.board]
	local members = {}
	for _, who in ipairs(run.members or {}) do
		local m = memberOf(who)
		if m then
			members[#members + 1] = m
		end
	end
	local r = {}
	for k, v in pairs(run) do
		r[k] = v
	end
	r.members = members
	r.debug = run.debug or R.offset ~= 0
	local ok, size = K.validate(r, board, cfg)
	if not ok then
		if size ~= "nobody" then
			log(string.format("run not counted on %s: %s", tostring(run.board), tostring(size)))
		end
		return false, size
	end
	local value = math.floor(tonumber(run.value))
	local slot = K.slot(board.key, run.variant, size)
	local prev = bestOf(slot, board.mode)
	local at, k = now(), keys()
	local names = K.names(members)
	ensureTables()
	for _, m in ipairs(members) do
		for _, period in ipairs({k.week, k.season, k.all}) do
			upsert(slot, period, m, value, board.mode, at, #members, names)
		end
	end
	if board.mode ~= "add" and K.better(board.mode, value, prev or 0) then
		R.best[slot] = value
		if cfg.announceRecord and K.isRecord(prev, value, board.mode) then
			broadcast(function(lang) return K.recordText(board, run.variant, size, value, members, prev, lang) end)
		end
	end
	realmFirst(board, run, members, value)
	return true, slot
end

-- ---------------------------------------------------------------- firsts, awards, titles
function R.loadFirsts()
	ensureTables()
	local k = keys()
	R.firsts = {season = k.season, byTarget = {}, byGuid = {}}
	local rows = Chaos.select(string.format("SELECT `target`, `board`, `name`, `members`, `guids`, `value`, `at` FROM `%s` " ..
		"WHERE `season` = %s", T.firsts, esc(k.season)), {{"target", "s"}, {"board", "s"}, {"name", "s"}, {"members", "s"},
		{"guids", "s"}, {"value", "n"}, {"at", "n"}})
	for _, r in ipairs(rows) do
		local e = {target = r.target, board = r.board, short = r.name, members = r.members, at = r.at, value = r.value}
		R.firsts.byTarget[r.target] = e
		for g in r.guids:gmatch("%d+") do
			g = tonumber(g)
			R.firsts.byGuid[g] = R.firsts.byGuid[g] or {}
			table.insert(R.firsts.byGuid[g], e)
		end
	end
end

local function loadHeld(week)
	local rows = Chaos.select(string.format("SELECT `slot`, `rank`, `player_id`, `cat`, `value` FROM `%s` WHERE `week` = %d",
		T.awards, week), {{"slot", "s"}, {"rank", "n"}, {"player_id", "n"}, {"cat", "s"}, {"value", "n"}})
	local awards = {}
	for _, r in ipairs(rows) do
		awards[#awards + 1] = {slot = r.slot, rank = r.rank, guid = r.player_id, cat = r.cat, value = r.value}
	end
	R.held = {week = week, byGuid = K.held(awards), count = #awards}
end

-- the weekly awards: the top 3 of every slot of the week that ended -> chaos_records_awards (titles, badge)
function R.checkReset(force)
	ensureTables()
	local cur = K.week(now(), cfg.resetHour)
	local last = getConfig(cfg.resetConfigKey)
	if not force and not ChaosLeaderboard.resetDue(last, cur) then
		return false
	end
	local prev = K.prevWeek(cur, cfg.resetHour)
	local rows = Chaos.select(string.format("SELECT r.`slot`, r.`player_id`, r.`value`, r.`at`, p.`name` FROM `%s` r JOIN " ..
		"`players` p ON p.`id` = r.`player_id` WHERE r.`period` = %s AND p.`group_id` < %d%s", T.best, esc("w" .. prev),
		cfg.staffGroup, ChaosAntibot and ChaosAntibot.heldClause and ChaosAntibot.heldClause("p.") or ""),
		{{"slot", "s"}, {"player_id", "n"}, {"value", "n"}, {"at", "n"}, {"name", "s"}})
	local bySlot = {}
	for _, r in ipairs(rows) do
		bySlot[r.slot] = bySlot[r.slot] or {}
		table.insert(bySlot[r.slot], {guid = r.player_id, value = r.value, at = r.at, name = r.name})
	end
	local ranked = {}
	for slot, list in pairs(bySlot) do
		local b = R.byKey[K.parseSlot(slot) or ""]
		if b then
			ranked[slot] = K.rank(list, b.mode)
		end
	end
	local awards = K.awards(ranked, cfg.top, catOfSlot)
	for _, a in ipairs(awards) do
		db.query(string.format("INSERT IGNORE INTO `%s` (`week`, `slot`, `rank`, `player_id`, `cat`, `value`) VALUES " ..
			"(%d, %s, %d, %d, %s, %d)", T.awards, prev, esc(a.slot), a.rank, a.guid, esc(a.cat or ""), a.value))
	end
	setConfig(cfg.resetConfigKey, cur)
	local oldest = K.week(ChaosLeaderboard.weekStart(cur, cfg.resetHour) - cfg.keepWeeks * 7 * 86400, cfg.resetHour)
	db.asyncQuery(string.format("DELETE FROM `%s` WHERE `period` LIKE 'w%%' AND `period` < %s", T.best, esc("w" .. oldest)))
	loadHeld(prev)
	log(string.format("weekly awards: week %d, %d placings", prev, #awards))
	if #awards > 0 then
		broadcast(function(lang)
			return ChaosI18n.text(lang, "Records: %d weekly top 3 placings of last week hold their titles and the %s badge this week.",
				#awards, cfg.badgeFrame)
		end)
	end
	for _, p in ipairs(Game.getPlayers()) do
		if ChaosNameplate and ChaosNameplate.refresh then
			pcall(ChaosNameplate.refresh, p)
		end
	end
	return true, prev, awards
end

function R.titlesOf(player)
	local guid = player:getGuid()
	local weekAt = ChaosLeaderboard.weekStart(R.held.week, cfg.resetHour) + 7 * 86400
	return K.titlesOf(cfg, R.held.byGuid[guid], R.firsts.byGuid[guid], weekAt)
end

function R.badgeOf(player)
	return R.held.byGuid[player:getGuid()] and cfg.badgeFrame or nil
end

-- ---------------------------------------------------------------- sources (hooks)
local unpack = unpack or table.unpack
local function pack(...)
	return {n = select("#", ...), ...}
end

-- tbl[name] runs as before; after(results, ...) runs behind it, guarded. Hooked once through ChaosWrapChain
-- (wrapchain_core.lua): season, guild, mentor and others hook the same functions, and a flag that only compared
-- with tbl[name] wrapped again every minute under them, so the hooks ran several times per call.
if not (ChaosWrapChain and ChaosWrapChain.wrap) then
	dofile("data/scripts/chaos/wrapchain_core.lua")
end
function R.wrap(tbl, name, flag, after)
	return ChaosWrapChain.wrap(tbl, name, flag, after, log)
end
local wrap = R.wrap

-- world boss kill (worldboss.lua calls computeRewards when the boss dies)
local function onWorldBoss(res, shares, r, boss)
	local W = ChaosWorldBoss
	local st = W and W.state
	if not boss or not st then
		return
	end
	local variant
	for _, b in ipairs(R.byKey.wb_time and R.byKey.wb_time.variants or {}) do
		if b.name == boss.name then
			variant = b.key
		end
	end
	if not variant then
		return
	end
	local members, total = {}, 0
	for _, s in ipairs(shares or {}) do
		total = total + (tonumber(s.damage) or 0)
		members[#members + 1] = {guid = s.guid, name = s.name}
	end
	local secs = os.time() - (st.fightStart or os.time())
	R.submit({board = "wb_time", variant = variant, value = secs, members = members, debug = st.forced})
	if total > 0 then
		for _, s in ipairs(shares or {}) do
			local share = math.floor((tonumber(s.damage) or 0) * 10000 / total + 0.5)
			if share > 0 then
				R.submit({board = "wb_share", variant = variant, value = share, members = {{guid = s.guid, name = s.name}},
					size = 1, debug = st.forced})
			end
		end
	end
end

-- sealed rift or Omen guardian (rift.lua -> ChaosRiftCore.atlasSealed): every finisher
local function onSealed(res, info)
	if type(info) ~= "table" then
		return
	end
	local members = {}
	for _, g in ipairs(info.guids or {}) do
		members[#members + 1] = {guid = g}
	end
	local secs = tonumber(info.secs) or 0
	if info.omen then
		R.submit({board = "omen", variant = info.omen, value = secs, members = members})
		return
	end
	local tier = tonumber(info.tier) or 0
	R.submit({board = "rift_tier", value = tier, members = members, size = 1})
	local band = K.bandOf(cfg, tier)
	if band then
		R.submit({board = "rift_band", variant = band, value = secs, members = members})
	end
	-- the Rift Atlas completion of every finisher (atlas.lua credited the cells in the original call)
	local A, AC = ChaosAtlas, ChaosAtlasCore
	if A and A.get and AC and AC.cells and ChaosAtlasConfig and ChaosRiftConfig then
		local max = #AC.cells(ChaosAtlasConfig, ChaosRiftConfig)
		for _, g in ipairs(info.guids or {}) do
			local ok, st = pcall(A.get, g)
			if ok and st and max > 0 then
				local n = 0
				for _ in pairs(st.done or {}) do
					n = n + 1
				end
				R.submit({board = "atlas", value = math.floor(n * 10000 / max), members = {{guid = g}}, size = 1})
			end
		end
	end
end

-- the run of an instance table (slot -> run) that holds this player
local function runOfPlayer(runs, player)
	for _, run in pairs(runs or {}) do
		if run.players and run.players[player:getId()] then
			return run
		end
	end
	return nil
end

local function runMembers(run)
	local members = {}
	for id, e in pairs(run.players or {}) do
		members[#members + 1] = Player(id) or {guid = e.guid, name = e.name}
	end
	return members
end

-- Ascended / Cinderheart and the guild boss (exclusives.lua bossKill: once per rewarded player online at the kill;
-- the run is submitted once, at its first call)
R.seenRuns = setmetatable({}, {__mode = "k"})
local function onBossKill(res, player, killKey)
	if not isPlayer(player) or type(killKey) ~= "string" then
		return
	end
	if killKey == "cinder" or killKey:sub(1, 9) == "ascended_" then
		local A = ChaosAscended
		local run = A and runOfPlayer(A.runs, player)
		if not run or R.seenRuns[run] then
			return
		end
		R.seenRuns[run] = true
		local members = runMembers(run)
		local count = #members
		R.submit({board = "ascended", variant = killKey == "cinder" and "cinder" or killKey:sub(10),
			value = run.secs or 0, members = members, size = math.max(run.size or 1, count), debug = run.staff or run.test})
	elseif killKey:sub(1, 6) == "guild_" then
		local GB = ChaosGuildBoss
		local run = GB and runOfPlayer(GB.runs, player)
		if not run or R.seenRuns[run] then
			return
		end
		R.seenRuns[run] = true
		local secs = math.max(1, math.floor((mnow() - (run.bossAt or mnow())) / 1000))
		R.submit({board = "guildboss", value = secs, members = runMembers(run), debug = run.staff or run.test})
	end
end

-- leaderboard records: the raid clear, the Descent, the arena and the battleground
local ARENA = {arena1v1 = "1v1", arena2v2 = "2v2", arena3v3 = "3v3"}
local function onRecord(res, board, who, value)
	if not res[1] then
		return -- the leaderboard did not take it (unknown board or player)
	end
	if board == "raid_clear" then
		-- ChaosRaid.runOf is a table (player id -> run), not a function
		local runs = ChaosRaid and ChaosRaid.runOf
		local run = isPlayer(who) and type(runs) == "table" and runs[who:getId()] or nil
		R.submit({board = "raid", value = value, members = {who}, size = 1, debug = run and run.staff or nil})
	elseif board == "descent" then
		R.submit({board = "descent", value = value, members = {who}, size = 1})
	elseif ARENA[board] then
		R.submit({board = "arena", variant = ARENA[board], value = value, members = {who}, size = 1})
	elseif board == "battleground" then
		R.submit({board = "battleground", value = 1, members = {who}, size = 1})
	end
end

-- Infinity Tower: the floors cleared at the end of a run (highest floor)
local function onTowerRun(res, player, floors, secs)
	if (tonumber(floors) or 0) > 0 then
		R.submit({board = "tower_floor", value = floors, members = {player}, size = 1})
	end
end

-- the fastest climb: infinitytower_run.lua floorCleared calls this (players = run.players: id -> {id, guid, ...})
function R.towerFloor(players, floorNo, secs)
	local variant = K.towerVariant(cfg, tonumber(floorNo) or 0)
	if not variant then
		return
	end
	local members = {}
	for id, e in pairs(players or {}) do
		members[#members + 1] = Player(type(e) == "table" and e.id or id) or {guid = type(e) == "table" and e.guid or nil}
	end
	R.submit({board = "tower_time", variant = variant, value = secs, members = members})
end

-- a cleared Vocation Trial (trials.lua reward: ChaosAchievements.set(player, "trial_tier_<n>", 1))
local function onAchievementSet(res, player, key)
	if not isPlayer(player) or type(key) ~= "string" then
		return
	end
	local tier = tonumber(key:match("^trial_tier_(%d+)$"))
	local tr = tier and ChaosTrials and ChaosTrials.runs and ChaosTrials.runs[player:getId()]
	if not tr or not tr.tierDef then
		return
	end
	local secs = math.floor((tr.tierDef.time * 1000 - math.max(0, (tr.deadline or 0) - mnow())) / 1000)
	local tiers = Chaos.trials and Chaos.trials.tiers or {}
	local variant = tiers[tier] and tiers[tier].key
	R.submit({board = "trials", variant = variant, value = secs, members = {player}, size = 1,
		first = {key = tostring(tr.famKey) .. "." .. tostring(variant), short = tr.fam and tr.fam.boss and tr.fam.boss.name}})
end

-- dungeons.lua endRun (success): info = {dungeonId, title, difficulty, difficultyStart, ms, members = {{guid, name}}}
function R.dungeonClear(info)
	if type(info) ~= "table" then
		return false, "no info"
	end
	local board = ChaosRecordsCore.isHollowVault(cfg, info.title) and "hollowvault" or ("dungeon_" .. tostring(info.dungeonId))
	return R.submit({board = board, variant = "d" .. tostring(info.difficulty), value = math.floor((info.ms or 0) / 1000),
		members = info.members, difficulty = info.difficulty, difficultyStart = info.difficultyStart})
end

function R.installHooks()
	wrap(ChaosWorldBoss, "computeRewards", "recordsWrapped", onWorldBoss)
	wrap(ChaosRiftCore, "atlasSealed", "recordsWrapped", onSealed)
	wrap(ChaosExclusives, "bossKill", "recordsWrapped", onBossKill)
	wrap(ChaosLeaderboard, "record", "recordsWrapped", onRecord)
	wrap(ChaosTower, "recordRun", "recordsWrapped", onTowerRun)
	wrap(ChaosAchievements, "set", "recordsWrapped", onAchievementSet)
end
R.installHooks()

if ChaosTitles and ChaosTitles.register then
	ChaosTitles.register("records", function(player) return R.titlesOf(player) end)
	ChaosTitles.registerFrame("records", function(player) return R.badgeOf(player) end)
end

-- ---------------------------------------------------------------- views
local function classIds(groupKey)
	local LB = ChaosLeaderboard
	if not groupKey or not LB.classGroups then
		return nil
	end
	for _, g in ipairs(LB.classGroups()) do
		if tostring(g.key) == tostring(groupKey) then
			return g.ids
		end
	end
	return nil
end

local function periodKey(p)
	local k = keys()
	return k[p] or k.week
end

function R.view(player, data)
	local board = R.byKey[data.board] or R.boards[1]
	if not board then
		return nil
	end
	local variant = board.variantByKey[data.variant or ""] and data.variant or (board.variants[1] and board.variants[1].key)
	local size = "-"
	if #board.sizes > 0 then
		size = board.sizes[1].key
		for _, s in ipairs(board.sizes) do
			if s.key == data.size then
				size = s.key
			end
		end
	end
	local period = (data.period == "season" or data.period == "all") and data.period or "week"
	local slot = K.slot(board.key, variant, size ~= "-" and size or nil)
	local ids = board.byClass and classIds(data.group) or nil
	local where = string.format("r.`slot` = %s AND r.`period` = %s AND r.`value` > 0 AND p.`group_id` < %d%s%s", esc(slot),
		esc(periodKey(period)), cfg.staffGroup, ids and string.format(" AND r.`voc` IN (%s)", table.concat(ids, ",")) or "",
		ChaosAntibot and ChaosAntibot.heldClause and ChaosAntibot.heldClause("p.") or "")
	local order = board.mode == "min" and "ASC" or "DESC"
	local rows = Chaos.select(string.format("SELECT r.`player_id`, r.`value`, r.`at`, r.`voc`, r.`party`, r.`members`, " ..
		"p.`name` FROM `%s` r JOIN `players` p ON p.`id` = r.`player_id` WHERE %s ORDER BY r.`value` %s, r.`at` ASC, " ..
		"r.`player_id` ASC LIMIT %d", T.best, where, order, cfg.rows), {{"player_id", "n"}, {"value", "n"}, {"at", "n"},
		{"voc", "n"}, {"party", "n"}, {"members", "s"}, {"name", "s"}})
	local out = {}
	for i, r in ipairs(rows) do
		local v = Vocation(r.voc)
		out[i] = {rank = i, name = r.name, value = r.value, at = r.at, party = r.party, members = r.party > 1 and r.members or nil,
			vocation = v and v:getName() or nil}
	end
	local function count(extra)
		local q = Chaos.select(string.format("SELECT COUNT(*) AS `n` FROM `%s` r JOIN `players` p ON p.`id` = r.`player_id` " ..
			"WHERE %s%s", T.best, where, extra or ""), {{"n", "n"}})
		return q[1] and q[1].n or 0
	end
	local own
	local mine = Chaos.select(string.format("SELECT r.`value`, r.`at` FROM `%s` r JOIN `players` p ON p.`id` = r.`player_id` " ..
		"WHERE %s AND r.`player_id` = %d", T.best, where, player:getGuid()), {{"value", "n"}, {"at", "n"}})[1]
	if mine then
		local cmp = board.mode == "min" and "<" or ">"
		local ahead = count(string.format(" AND (r.`value` %s %d OR (r.`value` = %d AND (r.`at` < %d OR (r.`at` = %d AND " ..
			"r.`player_id` < %d))))", cmp, mine.value, mine.value, mine.at, mine.at, player:getGuid()))
		own = {rank = ahead + 1, value = mine.value, at = mine.at}
	end
	local s = season()
	return {board = board.key, variant = variant, size = size ~= "-" and size or nil, period = period, group = ids and data.group or nil,
		rows = out, own = own, total = count(), record = bestOf(slot, board.mode), resetIn = math.max(0, K.nextReset(now(),
		cfg.resetHour) - now()), seasonName = K.seasonName(keys().season, s)}
end

local function boardMeta(b)
	local v, s = {}, {}
	for _, x in ipairs(b.variants) do
		v[#v + 1] = {key = x.key, name = x.name}
	end
	for _, x in ipairs(b.sizes) do
		s[#s + 1] = {key = x.key, name = x.name}
	end
	return {key = b.key, name = b.name, mode = b.mode, format = b.format, value = b.value, byClass = b.byClass,
		first = b.first, variants = v, sizes = s}
end

-- meta in parts that each stay under the extended opcode limit (the leaderboard window has no chunk joiner)
function R.sendMeta(player)
	local cats, parts = {}, 0
	for _, c in ipairs(cfg.categories) do
		local list = {}
		for _, b in ipairs(R.boards) do
			if b.cat == c.key then
				list[#list + 1] = boardMeta(b)
			end
		end
		if #list > 0 then
			cats[#cats + 1] = {key = c.key, name = c.name, title = c.title, info = c.info}
			local part = {}
			for i, b in ipairs(list) do
				part[#part + 1] = b
				if #part == 6 or i == #list then
					parts = parts + 1
					Chaos.send(player, OPCODE, "rcat", {cat = c.key, boards = part})
					part = {}
				end
			end
		end
	end
	local groups = {}
	if ChaosLeaderboard.classGroups then
		for _, g in ipairs(ChaosLeaderboard.classGroups()) do
			groups[#groups + 1] = {key = g.key, name = g.name}
		end
	end
	local k = keys()
	Chaos.send(player, OPCODE, "rmeta", {categories = cats, periods = cfg.periods, groups = groups, parts = parts,
		season = {key = k.season, name = K.seasonName(k.season, season())}, badge = cfg.badgeFrame,
		titles = R.titlesOf(player)})
end

function R.sendFirsts(player)
	local k = keys()
	if R.firsts.season ~= k.season then
		R.loadFirsts()
	end
	local rows = {}
	for _, e in pairs(R.firsts.byTarget) do
		local b = R.byKey[e.board]
		-- the boss's full name (K.firstDisplay); e.short is the title's short name
		rows[#rows + 1] = {target = e.target, board = b and b.name or e.board,
			name = K.firstDisplay(R.byKey, e.target, e.short) or e.short, members = e.members, at = e.at,
			value = e.value, format = b and b.format or nil}
	end
	table.sort(rows, function(a, b) return a.at < b.at end)
	while #rows > 60 do
		table.remove(rows)
	end
	Chaos.send(player, OPCODE, "rfirsts", {season = k.season, seasonName = K.seasonName(k.season, season()), rows = rows})
end

-- ---------------------------------------------------------------- events
local ext = CreatureEvent("ChaosRecordsExtended")
function ext.onExtendedOpcode(player, opcode, buffer)
	if opcode ~= OPCODE then
		return
	end
	local msg = Chaos.decode(buffer)
	-- only the Records actions: every other action on this opcode is leaderboard.lua's
	if not msg or (msg.action ~= "rmeta" and msg.action ~= "rget" and msg.action ~= "rfirsts") then
		return
	end
	if ChaosRateLimit and not ChaosRateLimit.allow(player, "records." .. msg.action, 150) then
		return
	end
	local data = type(msg.data) == "table" and msg.data or {}
	if msg.action == "rmeta" then
		R.sendMeta(player)
	elseif msg.action == "rget" then
		local req = {board = type(data.board) == "string" and data.board:sub(1, 48) or nil,
			variant = type(data.variant) == "string" and data.variant:sub(1, 24) or nil,
			size = type(data.size) == "string" and data.size:sub(1, 12) or nil,
			period = type(data.period) == "string" and data.period:sub(1, 8) or nil,
			group = Chaos.toInt(data.group, 0, 100000)}
		local view = R.view(player, req)
		if view then
			Chaos.send(player, OPCODE, "rboard", view)
		end
	elseif msg.action == "rfirsts" then
		R.sendFirsts(player)
	end
end
ext:type("extendedopcode")
ext:register()

local login = CreatureEvent("ChaosRecordsLogin")
function login.onLogin(player)
	player:registerEvent("ChaosRecordsExtended")
	return true
end
login:type("login")
login:register()

local think = GlobalEvent("ChaosRecordsReset")
function think.onThink(interval)
	R.installHooks() -- again after a /reload of a wrapped script
	R.checkReset()
	if R.firsts.season ~= keys().season then
		R.loadFirsts() -- a new season: new realm firsts
	end
	return true
end
think:interval(cfg.checkSeconds * 1000)
think:register()

local startup = GlobalEvent("ChaosRecordsStartup")
function startup.onStartup()
	ensureTables()
	R.build()
	publishBoards()
	R.installHooks()
	R.loadFirsts()
	if not R.checkReset() then
		loadHeld(K.prevWeek(K.week(now(), cfg.resetHour), cfg.resetHour))
	end
	log(string.format("%d boards, %d realm firsts this season (%s)", #R.boards, (function()
		local n = 0
		for _ in pairs(R.firsts.byTarget) do
			n = n + 1
		end
		return n
	end)(), tostring(R.firsts.season)))
	return true
end
startup:register()

-- staff: /records (status) | reset (award last week again; INSERT IGNORE keeps it once) | shift <days> (test clock;
-- every run is a debug run while shifted) | rebuild (the catalogue and the website table)
local talk = TalkAction("/records")
function talk.onSay(player, words, param)
	if not player:getGroup():getAccess() then
		return false
	end
	if Chaos.staffCommand and not Chaos.staffCommand(player, words, param, false) then
		return false
	end
	local cmd, arg = tostring(param or ""):lower():match("^%s*(%S*)%s*(.-)%s*$")
	if cmd == "reset" then
		local _, prev, awards = R.checkReset(true)
		player:sendTextMessage(MESSAGE_INFO_DESCR, string.format("Records: week %s awarded, %d placings.", tostring(prev),
			awards and #awards or 0))
	elseif cmd == "shift" then
		R.offset = math.floor((tonumber(arg) or 0) * 86400)
		player:sendTextMessage(MESSAGE_INFO_DESCR, string.format("Records clock shifted %s day(s); runs do not count while shifted.", arg))
	elseif cmd == "rebuild" then
		R.build()
		publishBoards()
		player:sendTextMessage(MESSAGE_INFO_DESCR, string.format("Records: %d boards rebuilt.", #R.boards))
	else
		player:sendTextMessage(MESSAGE_INFO_DESCR, string.format("Records: %d boards, season %s, %d award(s) held (week %d), " ..
			"clock offset %d s.", #R.boards, keys().season, R.held.count or 0, R.held.week, R.offset))
	end
	return false
end
talk:separator(" ")
talk:register()

-- a first catalogue at load (the content configs loaded before this file); startup builds it again with every script
R.build()
