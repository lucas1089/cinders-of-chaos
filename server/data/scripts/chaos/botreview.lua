-- Bot review: a daily suspicion score per character with explanations, for GM review only (server/README.md "Bot
-- detection"; pure logic botreview_core.lua, numbers botreview_config.lua, tests tests/botreview_test.lua and
-- tests/botreview_load_test.lua; tables sql/chaos_bot.sql; staff page website pages/botreview.php).
--
-- NOTHING HERE PUNISHES, KICKS OR MOVES ANYONE. A day whose score reaches flagAt is put on the review list; staff look,
-- then mark it reviewed, false positive or escalated (GM handbook section 3). Every mark is logged in chaos_bot_actions.
--
-- Where the samples come from (no per-step work of its own):
--   antibot.lua's hooks, by wrapping ChaosAntibotCore: onAction (spells, heals), onSelfHeal (+ HP % for the threshold
--   signal), onDamage (HP % before the hit), onPosition (the 2 s position sample it already takes: route keys, turns
--   on the spot), onLootMove (activity)
--   ChaosAntibot.finishCheck wrapped: the result of each presence check and whether the character kept acting
--   ChaosReports.onChannelSpeak wrapped: a line in a public channel (counted, never stored)
--   a kill creature event (one call per kill), EventCallback onTargetCombat (a table lookup and a compare per combat),
--   onLook and onItemMoved (one call per click of the player)
-- Work: one evaluation per character every evalSeconds (300 s), spread by guid; a cluster pass every 300 s over the
-- characters that share an IP or a party (pairs only, rings of 64 numbers, pairsPerTick pairs per 10 s tick); one DB write per flagged-or-stored
-- character and hour (async). tests/botreview_load_test.lua measures it.
-- Lua 5.1 / LuaJIT compatible.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
dofile("data/scripts/chaos/botreview_core.lua")

Chaos.botReviewConfig = Chaos.botReviewConfig or dofile("data/scripts/chaos/botreview_config.lua")
local cfg = Chaos.botReviewConfig
local BR = ChaosBotReviewCore
local T = Chaos.botReviewTables or cfg.tables

ChaosBotReview = ChaosBotReview or {}
local BV = ChaosBotReview
BV.states = BV.states or {} -- guid -> core state (+ cid, name, account, offlineAt, nextEval)
BV.byCid = BV.byCid or {} -- creature id -> guid
BV.wrapped = BV.wrapped or {}
BV.stats = BV.stats or {evals = 0, writes = 0, clusterPairs = 0, randomChecks = 0}
BV.lastCluster, BV.lastPurge, BV.lastPoll = BV.lastCluster or 0, BV.lastPurge or 0, BV.lastPoll or 0

local ADMIN_GROUP = 5 -- may change a case that is already escalated (GM handbook section 7, level 2)

local function log(text)
	print("[Chaos botreview] " .. text)
end

local function try(name, fn, ...)
	local ok, a, b, c = pcall(fn, ...)
	if not ok then
		log(name .. ": " .. tostring(a))
		return nil
	end
	return a, b, c
end

local function nowMs()
	return os.mtime and os.mtime() or os.time() * 1000
end

local function groupOf(player)
	local ok, g = pcall(function()
		return player:getGroup():getId()
	end)
	return ok and (tonumber(g) or 0) or 0
end

local function stateOfCid(cid)
	local guid = BV.byCid[cid]
	return guid and BV.states[guid] or nil
end

local function hpPct(cid)
	local p = Player(cid)
	if not p then
		return nil
	end
	local max = p:getMaxHealth()
	return max > 0 and math.floor(p:getHealth() * 100 / max) or nil
end

-- ---------------------------------------------------------------- wrapping antibot.lua (no hooks of our own)
local function wrap(tbl, name, make)
	if not tbl or type(tbl[name]) ~= "function" then
		return false
	end
	local key = tostring(tbl) .. "." .. name
	if tbl[name] == BV.wrapped[key] then
		return true
	end
	local fn = make(tbl[name])
	BV.wrapped[key] = fn
	tbl[name] = fn
	return true
end

function BV.wrap()
	local K = ChaosAntibotCore
	wrap(K, "onAction", function(orig)
		return function(st, acfg, ms, nowS, kind, bound)
			local r = orig(st, acfg, ms, nowS, kind, bound)
			local b = r and st and BV.states[st.guid]
			if b then
				BR.onAction(b, cfg, ms, nowS)
			end
			return r
		end
	end)
	wrap(K, "onDamage", function(orig)
		return function(st, acfg, ms)
			local b = st and BV.states[st.guid]
			if b then
				local hp = hpPct(b.cid)
				if hp then
					BR.onHit(b, cfg, ms, hp)
				end
			end
			return orig(st, acfg, ms)
		end
	end)
	wrap(K, "onSelfHeal", function(orig)
		return function(st, acfg, ms, nowS)
			local b = st and BV.states[st.guid]
			if b then
				local hp = hpPct(b.cid)
				if hp then
					BR.onHeal(b, cfg, ms, hp)
				end
			end
			return orig(st, acfg, ms, nowS)
		end
	end)
	wrap(K, "onLootMove", function(orig)
		return function(st, acfg, ms, nowS)
			local b = st and BV.states[st.guid]
			if b then
				BR.activity(b, cfg, nowS or math.floor(ms / 1000))
			end
			return orig(st, acfg, ms, nowS)
		end
	end)
	wrap(K, "onPosition", function(orig)
		return function(st, acfg, x, y, z, nowS, ms)
			local r = orig(st, acfg, x, y, z, nowS, ms)
			local b = st and BV.states[st.guid]
			if b then
				local f = acfg.loop and acfg.loop.fightMs or 4000
				local fighting = ms ~= nil and ((st.lastDamage and ms - st.lastDamage < f) or (st.lastAction and ms - st.lastAction < f))
				if b.lx == x and b.ly == y and b.lz == z then
					-- standing: a turn on the spot is a click of a human (bots rarely bother)
					local p = Player(b.cid)
					local dir = p and p:getDirection()
					if dir and b.dir and dir ~= b.dir and not fighting then
						BR.noise(b, cfg, "turn", nowS)
					end
					b.dir = dir
				else
					b.lx, b.ly, b.lz, b.dir = x, y, z, nil
					BR.onPosition(b, cfg, x, y, z, nowS, fighting)
				end
			end
			return r
		end
	end)
	-- the presence check: whether the character kept acting while it was open
	wrap(ChaosAntibot, "finishCheck", function(orig)
		return function(player, st, result, why)
			local b = player and stateOfCid(player:getId())
			local c = st and st.check and st.check.active
			local acted = false
			if b and c then
				acted = (b.lastActive or 0) > (c.started or 0) + 5
			end
			local r1, r2 = orig(player, st, result, why)
			if b then
				BR.onCheck(b, os.time(), result, acted, b.randomPending ~= nil)
				b.randomPending = nil
			end
			return r1, r2
		end
	end)
	-- public chat lines (patch_report_chat.py): counted only
	wrap(ChaosReports, "onChannelSpeak", function(orig)
		return function(player, channel, talkType, message)
			local b = player and stateOfCid(player:getId())
			if b then
				BR.noise(b, cfg, "chat", os.time())
			end
			return orig(player, channel, talkType, message)
		end
	end)
end

-- ---------------------------------------------------------------- tables
function BV.ensureTables()
	db.query("CREATE TABLE IF NOT EXISTS `" .. T.daily .. "` (`id` int unsigned NOT NULL AUTO_INCREMENT, `player_id` int " ..
		"unsigned NOT NULL, `account_id` int unsigned NOT NULL DEFAULT 0, `player_name` varchar(64) NOT NULL DEFAULT '', " ..
		"`day` int unsigned NOT NULL, `score` smallint unsigned NOT NULL DEFAULT 0, `peak` smallint unsigned NOT NULL " ..
		"DEFAULT 0, `flagged` tinyint unsigned NOT NULL DEFAULT 0, `signals` varchar(255) NOT NULL DEFAULT '', `reasons` " ..
		"varchar(1024) NOT NULL DEFAULT '', `timeline` varchar(255) NOT NULL DEFAULT '', `status` varchar(16) NOT NULL " ..
		"DEFAULT 'none', `reviewed_by` varchar(64) NOT NULL DEFAULT '', `reviewed_at` int unsigned NOT NULL DEFAULT 0, " ..
		"`note` varchar(255) NOT NULL DEFAULT '', `created_at` int unsigned NOT NULL, `updated_at` int unsigned NOT NULL, " ..
		"PRIMARY KEY (`id`), UNIQUE KEY `uniq_player_day` (`player_id`, `day`), KEY `idx_day` (`day`, `flagged`), " ..
		"KEY `idx_status` (`status`)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4")
	db.query("CREATE TABLE IF NOT EXISTS `" .. T.actions .. "` (`id` int unsigned NOT NULL AUTO_INCREMENT, `created_at` " ..
		"int unsigned NOT NULL, `player_id` int unsigned NOT NULL, `player_name` varchar(64) NOT NULL DEFAULT '', `day` " ..
		"int unsigned NOT NULL DEFAULT 0, `action` varchar(16) NOT NULL, `staff` varchar(64) NOT NULL DEFAULT '', " ..
		"`staff_group` tinyint unsigned NOT NULL DEFAULT 0, `note` varchar(255) NOT NULL DEFAULT '', `done_at` int " ..
		"unsigned NOT NULL DEFAULT 0, `result` varchar(32) NOT NULL DEFAULT '', PRIMARY KEY (`id`), KEY `idx_pending` " ..
		"(`action`, `done_at`), KEY `idx_player` (`player_id`, `created_at`)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4")
end

-- ---------------------------------------------------------------- states
function BV.stateOf(player)
	local guid = player:getGuid()
	local st = BV.states[guid]
	if not st then
		st = BR.newState(cfg, os.time())
		BV.states[guid] = st
	end
	st.guid, st.cid, st.name, st.account = guid, player:getId(), player:getName(), player:getAccountId()
	return st
end

local function antibotState(guid)
	return ChaosAntibot and ChaosAntibot.states and ChaosAntibot.states[guid] or nil
end

local function writeDay(st, day, nowS)
	local row = BR.rowOf(st, cfg, day, st.guid, st.account, st.name, nowS)
	db.asyncQuery(BR.upsertSql(cfg, row, db.escapeString))
	BV.stats.writes = BV.stats.writes + 1
	return row
end

local function tellStaff(text)
	for _, p in ipairs(Game.getPlayers()) do
		if groupOf(p) >= cfg.staffGroup then
			p:sendTextMessage(MESSAGE_STATUS_CONSOLE_BLUE, text)
		end
	end
end

-- one evaluation of one character
function BV.evaluate(player, st, nowS)
	local ab = antibotState(st.guid)
	BR.evaluate(st, cfg, ab and ab.signals or {}, nowS, ab and ab.info or {})
	BV.stats.evals = BV.stats.evals + 1
	local d = os.date("*t", nowS)
	local finished = BR.addPoint(st, cfg, Chaos.dayKey(nowS), d.hour, st.score)
	if finished and (finished.written or BR.dayScore(finished, cfg) >= cfg.storeAt) then
		writeDay(st, finished, nowS)
	end
	local due, dayScore, newlyFlagged = BR.writeDue(st, cfg, math.floor(nowS / 3600))
	if due then
		writeDay(st, st.day, nowS)
	end
	if newlyFlagged then
		tellStaff(string.format("[Bot review] %s is on the review list (day score %d). /botreview %s", st.name,
			math.floor(dayScore + 0.5), st.name))
		log(string.format("%s flagged (day score %d): %s", st.name, math.floor(dayScore + 0.5),
			table.concat(st.explain or {}, " | ")))
	end
	-- a rare random presence check (antibot.lua sends it when the character is not in PvP, a boss fight or a rift)
	if ab and ab.check then
		local streak = ab.info and ab.info.nonstop and ab.info.nonstop.streak or 0
		if BR.randomCheckDue(st, cfg, nowS, streak, ab.check, ChaosAntibot and Chaos.antibotConfig and
				Chaos.antibotConfig.check, Chaos.dayKey(nowS), math.random()) then
			ab.check.owed = true
			st.randomPending = nowS
			BV.stats.randomChecks = BV.stats.randomChecks + 1
		end
	end
	return st.score
end

-- ---------------------------------------------------------------- the cluster pass
function BV.groups(players)
	local byIp, byParty, groups = {}, {}, {}
	for _, p in ipairs(players) do
		local st = stateOfCid(p:getId())
		if st then
			local entry = {guid = st.guid, name = st.name, acts = nil, st = st}
			local ip = p:getIp()
			if ip and ip ~= 0 then
				local g = byIp[ip]
				if not g then
					g = {kind = "ip"}
					byIp[ip] = g
					groups[#groups + 1] = g
				end
				g[#g + 1] = entry
			end
			local party = p.getParty and p:getParty()
			if party then
				local leader = party:getLeader()
				local key = leader and leader:getId() or 0
				local g = byParty[key]
				if not g then
					g = {kind = "party"}
					byParty[key] = g
					groups[#groups + 1] = g
				end
				g[#g + 1] = entry
			end
		end
	end
	local out = {}
	for _, g in ipairs(groups) do
		if #g >= 2 then
			for _, e in ipairs(g) do
				if not e.acts then
					e.acts = BR.values(e.st.acts)
				end
			end
			out[#out + 1] = g
		end
	end
	return out
end

-- starts a pass: the groups and a copy of each ring now; the pairs then run in slices (BV.clusterStep)
function BV.clusterStart(players)
	BV.cluster = {jobs = BR.clusterJobs(BV.groups(players), cfg), next = 1, results = {}}
	return #BV.cluster.jobs
end

-- runs up to `budget` pairs; at the end of a pass every online character gets its result
function BV.clusterStep(budget)
	local c = BV.cluster
	if not c then
		return true
	end
	BR.clusterRun(c.jobs, c.next, c.next + budget - 1, c.results, cfg)
	c.next = c.next + budget
	if c.next > #c.jobs then
		local online = {}
		for guid, st in pairs(BV.states) do
			if not st.offlineAt then
				online[guid] = st
			end
		end
		BR.clusterApply(c.results, online)
		BV.stats.clusterPairs = BV.stats.clusterPairs + #c.jobs
		BV.cluster = nil
		return true
	end
	return false
end

-- the whole pass at once (staff tools, tests)
function BV.clusterPass(players)
	local n = BV.clusterStart(players)
	BV.clusterStep(n + 1)
	return n
end

-- ---------------------------------------------------------------- staff actions (also the website's, by SQL)
-- action: reviewed | false_positive | escalate | note; returns ok, text
function BV.mark(staffName, staffGroup, guid, day, action, note)
	if action ~= "reviewed" and action ~= "false_positive" and action ~= "escalate" and action ~= "note" then
		return false, "Unknown action."
	end
	local rows = Chaos.select(string.format("SELECT `id`, `status`, `player_name`, `day` FROM `%s` WHERE `player_id` = %d%s " ..
		"ORDER BY `day` DESC LIMIT 1", T.daily, guid, day and day > 0 and (" AND `day` = " .. math.floor(day)) or " AND `flagged` = 1"),
		{{"id", "n"}, {"status", "s"}, {"player_name", "s"}, {"day", "n"}})
	local row = rows[1]
	if not row then
		return false, "No flagged day for that character."
	end
	if row.status == "escalated" and action ~= "note" and (staffGroup or 0) < ADMIN_GROUP then
		return false, "This case is escalated: only an administrator (group 5) may change it."
	end
	note = tostring(note or ""):gsub("[%c]", " "):sub(1, 255)
	local status = ({reviewed = "reviewed", false_positive = "false_positive", escalate = "escalated"})[action]
	if status then
		db.query(string.format("UPDATE `%s` SET `status` = %s, `reviewed_by` = %s, `reviewed_at` = %d, `note` = %s WHERE `id` = %d",
			T.daily, db.escapeString(status), db.escapeString(staffName), os.time(), db.escapeString(note), row.id))
	else
		db.query(string.format("UPDATE `%s` SET `note` = %s WHERE `id` = %d", T.daily, db.escapeString(note), row.id))
	end
	db.asyncQuery(string.format("INSERT INTO `%s` (`created_at`, `player_id`, `player_name`, `day`, `action`, `staff`, " ..
		"`staff_group`, `note`, `done_at`) VALUES (%d, %d, %s, %d, %s, %s, %d, %s, %d)", T.actions, os.time(), guid,
		db.escapeString(row.player_name), row.day, db.escapeString(action), db.escapeString(staffName), staffGroup or 0,
		db.escapeString(note), os.time()))
	return true, string.format("%s, day %d: %s.", row.player_name, row.day, status or "note saved")
end

-- presence checks requested from the website panel (chaos_bot_actions, action "check", done_at 0)
function BV.pollRequests(nowS)
	local rows = Chaos.select(string.format("SELECT `id`, `player_id`, `created_at` FROM `%s` WHERE `action` = 'check' AND " ..
		"`done_at` = 0 ORDER BY `id` LIMIT 20", T.actions), {{"id", "n"}, {"player_id", "n"}, {"created_at", "n"}})
	for _, r in ipairs(rows) do
		local result
		local st = BV.states[r.player_id]
		local ab = antibotState(r.player_id)
		if st and not st.offlineAt and ab and ab.check then
			if ab.check.active then
				result = "already running"
			else
				ab.check.owed = true -- antibot.lua sends it outside PvP, boss fights and rifts
				result = "sent"
			end
		elseif nowS - r.created_at > 86400 then
			result = "expired"
		end
		if result then
			db.asyncQuery(string.format("UPDATE `%s` SET `done_at` = %d, `result` = %s WHERE `id` = %d", T.actions, nowS,
				db.escapeString(result), r.id))
		end
	end
	return #rows
end

function BV.purge(nowS)
	for _, q in ipairs(BR.purgeSql(cfg, nowS, function(days)
		return Chaos.dayKey(nowS - days * 86400)
	end)) do
		db.asyncQuery(q)
	end
end

-- ---------------------------------------------------------------- the tick
function BV.tick()
	local nowS = os.time()
	local players = Game.getPlayers()
	for _, player in ipairs(players) do
		local st = stateOfCid(player:getId())
		if st and nowS >= (st.nextEval or 0) then
			st.nextEval = nowS + cfg.evalSeconds
			try("evaluate", BV.evaluate, player, st, nowS)
		end
	end
	if BV.cluster then
		try("cluster", BV.clusterStep, cfg.cluster.pairsPerTick)
	elseif nowS - BV.lastCluster >= cfg.cluster.everySeconds then
		BV.lastCluster = nowS
		try("cluster", BV.clusterStart, players)
	end
	if nowS - BV.lastPoll >= cfg.requestPollSeconds then
		BV.lastPoll = nowS
		try("requests", BV.pollRequests, nowS)
	end
	if nowS - BV.lastPurge >= cfg.purgeEverySeconds then
		BV.lastPurge = nowS
		try("purge", BV.purge, nowS)
	end
	for guid, st in pairs(BV.states) do
		if st.offlineAt and nowS - st.offlineAt >= cfg.keepOfflineMinutes * 60 then
			if st.day and st.day.written then
				try("write", writeDay, st, st.day, nowS)
			end
			BV.states[guid] = nil
		end
	end
end

-- ---------------------------------------------------------------- events
local login = CreatureEvent("ChaosBotReviewLogin")
function login.onLogin(player)
	-- staff, and the staff's tester bots (testers.lua: they are bots by design)
	if cfg.enabled == false or groupOf(player) >= cfg.staffGroup or (Chaos.isTester and Chaos.isTester(player)) then
		return true
	end
	BV.wrap()
	local st = BV.stateOf(player)
	st.offlineAt = nil
	st.nextEval = os.time() + (player:getGuid() % cfg.evalSeconds) + 30
	BV.byCid[player:getId()] = player:getGuid()
	player:registerEvent("ChaosBotReviewKill")
	player:registerEvent("ChaosBotReviewLogout")
	return true
end
login:type("login")
login:register()

local logout = CreatureEvent("ChaosBotReviewLogout")
function logout.onLogout(player)
	local guid = BV.byCid[player:getId()]
	BV.byCid[player:getId()] = nil
	local st = guid and BV.states[guid]
	if st then
		st.offlineAt = os.time()
	end
	return true
end
logout:type("logout")
logout:register()

local kill = CreatureEvent("ChaosBotReviewKill")
function kill.onKill(creature, target)
	local st = creature and stateOfCid(creature:getId())
	if st and target and target:isMonster() and not target:getMaster() then
		BR.onKill(st, nowMs())
	end
	return true
end
kill:type("kill")
kill:register()

local combat = EventCallback
combat.onTargetCombat = function(creature, target)
	local st = creature and target and stateOfCid(creature:getId())
	if st and target:isMonster() then
		local ms = nowMs()
		if BR.onCombat(st, cfg, ms, target:getId()) then
			BR.onAction(st, cfg, ms, os.time())
		end
	end
	return RETURNVALUE_NOERROR
end
combat:register()

local look = EventCallback
look.onLook = function(self, thing, position, distance, description)
	local st = self and stateOfCid(self:getId())
	if st then
		BR.noise(st, cfg, "look", os.time())
	end
	return description
end
look:register()

-- item moves that are not looting (looting by hand is antibot.lua's loot signal)
local moved = EventCallback
moved.onItemMoved = function(player, item, count, fromPosition, toPosition, fromCylinder, toCylinder)
	local st = player and stateOfCid(player:getId())
	if not st then
		return
	end
	local corpse = false
	pcall(function()
		if fromCylinder and fromCylinder:isItem() and fromCylinder:isContainer() then
			corpse = ItemType(fromCylinder:getId()):isCorpse() or (fromCylinder:getAttribute(ITEM_ATTRIBUTE_CORPSEOWNER) or 0) ~= 0
		end
	end)
	if not corpse then
		BR.noise(st, cfg, "inv", os.time())
	end
end
moved:register()

local think = GlobalEvent("ChaosBotReviewThink")
function think.onThink(interval)
	if cfg.enabled ~= false then
		try("tick", BV.tick)
	end
	return true
end
think:interval(10000)
think:register()

local startup = GlobalEvent("ChaosBotReviewStartup")
function startup.onStartup()
	try("tables", BV.ensureTables)
	try("wrap", BV.wrap)
	return true
end
startup:type("startup")
startup:register()

BV.wrap()

-- ---------------------------------------------------------------- staff: /botreview and the admin panel
local function stamp(day)
	return tostring(day or "?")
end

-- the live state and the stored days of a character
function BV.detailLines(name)
	local guid, canon = Chaos.findPlayer(name)
	if not guid then
		return {"No character named " .. tostring(name) .. "."}
	end
	local lines = {}
	local st = BV.states[guid]
	if st and st.signals then
		lines[#lines + 1] = string.format("%s now: score %d (automation %.2f, unattended %.2f), today %d", canon,
			math.floor((st.score or 0) + 0.5), st.A or 0, st.U or 0, math.floor(BR.dayScore(st.day, cfg) + 0.5))
		lines[#lines + 1] = BR.signalsText(st.signals)
		for _, e in ipairs(st.explain or {}) do
			lines[#lines + 1] = "- " .. e
		end
		lines[#lines + 1] = "today by hour: " .. BR.timeline(st.day)
	else
		lines[#lines + 1] = canon .. ": no live state (offline or not evaluated yet)."
	end
	for _, r in ipairs(Chaos.select(string.format("SELECT `day`, `score`, `flagged`, `status`, `reasons` FROM `%s` WHERE " ..
			"`player_id` = %d ORDER BY `day` DESC LIMIT 7", T.daily, guid),
			{{"day", "n"}, {"score", "n"}, {"flagged", "n"}, {"status", "s"}, {"reasons", "s"}})) do
		lines[#lines + 1] = string.format("%s: %d %s%s", stamp(r.day), r.score or 0, tostring(r.status), r.flagged == 1 and " (flagged)" or "")
	end
	return lines
end

function BV.listLines(limit)
	local since = Chaos.dayKey(os.time() - 7 * 86400)
	local lines = {}
	for _, r in ipairs(Chaos.select(string.format("SELECT `player_name`, `day`, `score`, `status` FROM `%s` WHERE `flagged` = 1 " ..
			"AND `day` >= %d AND `status` IN ('new', 'escalated') ORDER BY `score` DESC LIMIT %d", T.daily, since, limit or 20),
			{{"player_name", "s"}, {"day", "n"}, {"score", "n"}, {"status", "s"}})) do
		lines[#lines + 1] = string.format("%s  day %s  score %d  %s", r.player_name, stamp(r.day), r.score, r.status)
	end
	if #lines == 0 then
		lines[1] = "Nothing to review in the last 7 days."
	end
	return lines
end

local function reply(player, lines)
	if #lines > 3 and player.popupFYI then
		player:popupFYI(table.concat(lines, "\n"))
	else
		for _, l in ipairs(lines) do
			player:sendTextMessage(MESSAGE_INFO_DESCR, l)
		end
	end
end

local USAGE = "/botreview | /botreview <name> | /botreview mark <name>, reviewed|false_positive|escalate|note[, note]"

local talk = TalkAction("/botreview")
function talk.onSay(player, words, param)
	local allowed, staff = Chaos.staffCommand(player, words, param, false)
	if not allowed or groupOf(player) < cfg.staffGroup then
		return not staff
	end
	param = (param or ""):gsub("^%s+", ""):gsub("%s+$", "")
	if param == "" then
		reply(player, BV.listLines(20))
		return false
	end
	local rest = param:match("^[Mm][Aa][Rr][Kk]%s+(.+)$")
	if rest then
		local name, action, note = rest:match("^([^,]+),%s*([%w_]+)%s*,?%s*(.*)$")
		local guid = name and Chaos.findPlayer((name:gsub("%s+$", "")))
		if not guid then
			player:sendTextMessage(MESSAGE_INFO_DESCR, USAGE)
			return false
		end
		local _, text = BV.mark(player:getName(), groupOf(player), guid, nil, action:lower(), note)
		player:sendTextMessage(MESSAGE_INFO_DESCR, text)
		return false
	end
	reply(player, BV.detailLines(param))
	return false
end
talk:separator(" ")
talk:register()

ChaosAdminPending = ChaosAdminPending or {}
local function reg(def)
	def.category = "security"
	def.id = "security." .. def.id
	ChaosAdminPending[def.id] = def
end

reg{id = "botreview_list", name = "Bot review list", description = "Characters on the bot review list (last 7 days).",
	params = {},
	handler = function(actor, p)
		local lines = BV.listLines(30)
		return true, "Bot review", lines
	end}

reg{id = "botreview_show", name = "Bot review: character", description = "Live score, signals, explanations and last days.",
	params = {{name = "player", label = "Player", type = "player", required = true}},
	handler = function(actor, p)
		return true, "Bot review", BV.detailLines(p.player)
	end}

reg{id = "botreview_mark", name = "Bot review: mark", description = "Mark the latest flagged day (logged).",
	params = {{name = "player", label = "Player", type = "player", required = true},
		{name = "action", label = "Mark", type = "select", default = "reviewed",
			options = {{value = "reviewed", label = "Reviewed"}, {value = "false_positive", label = "False positive"},
				{value = "escalate", label = "Escalate"}}},
		{name = "note", label = "Note", type = "string", max = 200, required = false}},
	handler = function(actor, p)
		local guid = Chaos.findPlayer(p.player)
		if not guid then
			return false, "No such character."
		end
		return BV.mark(actor:getName(), groupOf(actor), guid, nil, p.action, p.note)
	end}
