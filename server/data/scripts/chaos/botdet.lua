-- Bot detection events and scores (O722): collects what a character does, writes it in batches, runs six heuristics once an
-- hour and gives staff the numbers (/botcheck, chaos-ctl.sh botcheck-top, the admin app). Pure logic: botdet_core.lua
-- (tests/botdet_test.lua); numbers: botdet_config.lua; tables: sql/chaos_botdet.sql; design, policy and the questions that
-- are the owner's: docs/BOT_DETECTION.md; server/README.md "Bot detection events and scores (O722)".
--
-- NOTHING HERE PUNISHES, KICKS OR MOVES ANYONE. Every signal only adds an event or a number. Testers (tester bots, journey
-- bots) and staff are never collected. This sits next to antibot.lua (the presence check, a decaying score) and
-- botreview.lua (a daily score per character): it keeps the raw events of the last 7 days for staff and scores the six
-- heuristics of the plan by the hour; the three do not read each other's numbers.
--
-- Where the data comes from (in memory per character, written every flushSeconds and at logout):
--   positions   one getPosition per online character every sampleMs (GlobalEvent); only a change of tile is kept
--   steps       player:getBotSignals() (engine src-patch 0093, polled every pollEvery samples): key steps, path commands
--               (autowalk) with their length, and the first attack on a creature after it came into view
--   spells      ChaosSpellEvents "cast" and "cooldown" (engine patch 0008, events enabled): id, hit point and mana %, and
--               whether the cast came the moment the cooldown ended (a held hotkey says nothing about rhythm)
--   heals       a healthchange event of the character as its own attacker: spells, runes and potions, hit point % before
--   sessions    login, logout and pauses of 5 minutes or more without any action
--   the client  extended opcode ChaosOpcodes.botdet (client game_chaosguard): module digests and known-tool codes
-- Without src-patch 0093 the reaction and path heuristics have no data and the others carry the total.
-- Lua 5.1 / LuaJIT compatible.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
dofile("data/scripts/chaos/botdet_core.lua")

Chaos.botdetConfig = Chaos.botdetConfig or dofile("data/scripts/chaos/botdet_config.lua")
local cfg = Chaos.botdetConfig
local K = ChaosBotdetCore
local OPCODE = ChaosOpcodes.botdet or 169
local T = Chaos.botdetTables or cfg.tables

ChaosBotdet = ChaosBotdet or {}
local BD = ChaosBotdet
BD.states = BD.states or {} -- guid -> core state (+ cid, account, nextFlush, nextHour)
BD.byCid = BD.byCid or {} -- creature id -> guid of the characters collected
BD.ticks = BD.ticks or 0
BD.stats = BD.stats or {samples = 0, flushes = 0, rows = 0, hourly = 0}
BD.official = BD.official -- {name = digest} of the official client modules, nil until read
BD.lastPurge, BD.lastTop = BD.lastPurge or "", BD.lastTop or "" -- day keys of the last purge and top list

local function log(text)
	print("[Chaos botdet] " .. text)
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

local function isStaff(player)
	return groupOf(player) >= cfg.staffGroup
end

-- ---------------------------------------------------------------- tables
function BD.ensureTables()
	db.query("CREATE TABLE IF NOT EXISTS `" .. T.events .. "` (`id` bigint unsigned NOT NULL AUTO_INCREMENT, `player_id` int " ..
		"unsigned NOT NULL, `type` varchar(16) NOT NULL, `data` mediumtext NOT NULL, `created_at` int unsigned NOT NULL, " ..
		"PRIMARY KEY (`id`), KEY `idx_player_time` (`player_id`, `created_at`), KEY `idx_time` (`created_at`), " ..
		"KEY `idx_type` (`type`, `created_at`)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4")
	db.query("CREATE TABLE IF NOT EXISTS `" .. T.scores .. "` (`id` bigint unsigned NOT NULL AUTO_INCREMENT, `player_id` int " ..
		"unsigned NOT NULL, `player_name` varchar(64) NOT NULL DEFAULT '', `hour_ts` int unsigned NOT NULL, `total` smallint " ..
		"unsigned NOT NULL DEFAULT 0, `route` smallint unsigned NOT NULL DEFAULT 0, `regularity` smallint unsigned NOT NULL " ..
		"DEFAULT 0, `reaction` smallint unsigned NOT NULL DEFAULT 0, `heal` smallint unsigned NOT NULL DEFAULT 0, `session` " ..
		"smallint unsigned NOT NULL DEFAULT 0, `bonus` smallint unsigned NOT NULL DEFAULT 0, `flagged` tinyint unsigned NOT " ..
		"NULL DEFAULT 0, `notes` varchar(1024) NOT NULL DEFAULT '', `created_at` int unsigned NOT NULL, PRIMARY KEY (`id`), " ..
		"UNIQUE KEY `uniq_player_hour` (`player_id`, `hour_ts`), KEY `idx_hour_total` (`hour_ts`, `total`), KEY " ..
		"`idx_flagged` (`flagged`, `hour_ts`)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4")
end

-- the official module digests of the client (data/lib/chaos_module_hashes.lua, made at release by
-- client/tools/gen_module_hashes.py); an empty or missing list compares nothing
function BD.loadOfficial()
	local ok, list = pcall(dofile, cfg.integrity.listFile)
	if ok and type(list) == "table" and type(list.modules) == "table" then
		BD.official = list.modules
	else
		BD.official = {}
	end
	return BD.official
end

-- ---------------------------------------------------------------- writing
function BD.writeRows(guid, rows)
	if #rows == 0 then
		return 0
	end
	local values = {}
	for _, row in ipairs(rows) do
		local data = json.encode(row.data)
		if #data > 60000 then
			data = data:sub(1, 60000) -- never an oversized row (a bounded ring cannot reach this)
		end
		values[#values + 1] = string.format("(%d, %s, %s, %d)", guid, db.escapeString(row.type), db.escapeString(data), row.created_at)
	end
	db.asyncQuery("INSERT INTO `" .. T.events .. "` (`player_id`, `type`, `data`, `created_at`) VALUES " .. table.concat(values, ", "))
	BD.stats.rows = BD.stats.rows + #rows
	return #rows
end

function BD.flush(st, now)
	local rows = K.takeRows(st, cfg, now)
	BD.stats.flushes = BD.stats.flushes + 1
	return BD.writeRows(st.guid, rows)
end

function BD.writeScore(st, res, now)
	local row = K.scoreRow(res, cfg)
	local hour = math.floor(now / 3600) * 3600
	db.asyncQuery(string.format("INSERT INTO `%s` (`player_id`, `player_name`, `hour_ts`, `total`, `route`, `regularity`, " ..
		"`reaction`, `heal`, `session`, `bonus`, `flagged`, `notes`, `created_at`) VALUES (%d, %s, %d, %d, %d, %d, %d, %d, %d, " ..
		"%d, %d, %s, %d) ON DUPLICATE KEY UPDATE `total` = VALUES(`total`), `route` = VALUES(`route`), `regularity` = " ..
		"VALUES(`regularity`), `reaction` = VALUES(`reaction`), `heal` = VALUES(`heal`), `session` = VALUES(`session`), " ..
		"`bonus` = VALUES(`bonus`), `flagged` = VALUES(`flagged`), `notes` = VALUES(`notes`), `player_name` = VALUES(`player_name`)",
		T.scores, st.guid, db.escapeString(st.name or ""), hour, row.total, row.route, row.regularity, row.reaction, row.heal,
		row.session, row.bonus, row.flagged, db.escapeString(row.notes), now))
	BD.stats.hourly = BD.stats.hourly + 1
end

-- the hourly pass of one character: the six heuristics over the rings, one score row (only when something has data)
function BD.hourly(st, now)
	local res = K.analyze(st, cfg, now)
	st.last = res
	if res.coverage > 0 then
		BD.writeScore(st, res, now)
	end
	return res
end

-- ---------------------------------------------------------------- states
local function stateOfCreature(creature)
	if not creature then
		return nil
	end
	local ok, cid = pcall(function()
		return creature:getId()
	end)
	local guid = ok and BD.byCid[cid]
	return guid and BD.states[guid] or nil
end

function BD.stateOf(player)
	local guid = player:getGuid()
	local st = BD.states[guid]
	if not st then
		st = K.newState(cfg, guid, player:getName(), os.time())
		BD.states[guid] = st
	end
	st.name = player:getName()
	return st
end

-- ---------------------------------------------------------------- events
local login = CreatureEvent("ChaosBotdetLogin")
function login.onLogin(player)
	player:registerEvent("ChaosBotdetLogout")
	-- staff, and the staff's tester bots and journey bots (testers.lua: bots by design) are not collected
	if cfg.enabled == false or isStaff(player) or (Chaos.isTester and Chaos.isTester(player)) then
		return true
	end
	player:registerEvent("ChaosBotdetHealth")
	player:registerEvent("ChaosBotdetExtended")
	local now = os.time()
	local st = BD.stateOf(player)
	if st.offlineAt and now - st.offlineAt >= cfg.session.idleSeconds then
		st.idleEnd = now -- a relog after a pause starts a new stretch; a quick relog keeps it
	end
	st.cid, st.account = player:getId(), player:getAccountId()
	K.onLogin(st, cfg, now)
	st.nextFlush = now + cfg.flushSeconds + (st.guid % cfg.flushSeconds)
	st.nextHour = now + cfg.hourlySeconds + (st.guid % cfg.hourlySeconds)
	BD.byCid[st.cid] = st.guid
	-- the known-tool list goes to the client a little after the login (its modules are up by then)
	local pid = st.cid
	addEvent(function()
		local p = Player(pid)
		if p and BD.byCid[pid] and #K.toolList(cfg) > 0 then
			Chaos.send(p, OPCODE, "tools", {t = K.toolList(cfg)})
		end
	end, 4000)
	return true
end
login:type("login")
login:register()

local logout = CreatureEvent("ChaosBotdetLogout")
function logout.onLogout(player)
	local cid = player:getId()
	local guid = BD.byCid[cid]
	BD.byCid[cid] = nil
	local st = guid and BD.states[guid]
	if st then
		local now = os.time()
		K.onLogout(st, cfg, now)
		try("final signals", BD.poll, player, st, now)
		try("flush", BD.flush, st, now)
		try("hourly", BD.hourly, st, now)
	end
	return true
end
logout:type("logout")
logout:register()

local health = CreatureEvent("ChaosBotdetHealth")
function health.onHealthChange(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType, origin)
	if primaryType == COMBAT_HEALING and attacker and attacker == creature then
		local st = stateOfCreature(creature)
		if st then
			local max = creature:getMaxHealth()
			if max > 0 then
				K.onHeal(st, cfg, nowMs(), os.time(), creature:getHealth() * 100 / max)
			end
		end
	end
	return primaryDamage, primaryType, secondaryDamage, secondaryType
end
health:type("healthchange")
health:register()

-- spell casts (engine patch 0008 with the spell events on): the cooldown events of a cast come before its cast event
if not ChaosSpellEvents or not ChaosSpellEvents.set then
	pcall(dofile, "data/lib/chaos_spell_events.lua")
end
BD.ready = BD.ready or {} -- creature id -> {["s" .. id] = ms ready, ["g" .. group] = ms ready}
BD.pendingCd = BD.pendingCd or {}
if ChaosSpellEvents and ChaosSpellEvents.set then
	ChaosSpellEvents.set("cooldown", "botdet", function(player, name, id, group, aggressive, cooldownType, ms)
		if player and BD.byCid[player:getId()] then
			local p = BD.pendingCd[player:getId()] or {}
			BD.pendingCd[player:getId()] = p
			if cooldownType == "spell" then
				p.spell = ms
			elseif cooldownType == "group" then
				p.group = ms
			end
		end
		return ms
	end)
	ChaosSpellEvents.set("cast", "botdet", function(player, name, id, group, aggressive, mana, health)
		local st = player and stateOfCreature(player)
		if not st then
			return
		end
		local cid, now = player:getId(), nowMs()
		local rd = BD.ready[cid] or {}
		BD.ready[cid] = rd
		local sk, gk = "s" .. tostring(id), "g" .. tostring(group)
		local readyAt = math.max(rd[sk] or 0, rd[gk] or 0)
		local bound = false
		if readyAt > 0 then
			bound = now >= readyAt - 150 and now - readyAt <= 150
		end
		local p = BD.pendingCd[cid]
		BD.pendingCd[cid] = nil
		rd[sk] = now + (p and p.spell or 0)
		rd[gk] = now + (p and p.group or 0)
		local maxHp, maxMp = player:getMaxHealth(), player:getMaxMana()
		K.onCast(st, cfg, now, os.time(), id, bound, maxHp > 0 and player:getHealth() * 100 / maxHp or 100,
			maxMp > 0 and player:getMana() * 100 / maxMp or 100)
	end)
end

-- the client's signals: module digests in chunks, the codes of known tools
local ext = CreatureEvent("ChaosBotdetExtended")
function ext.onExtendedOpcode(player, opcode, buffer)
	if opcode ~= OPCODE then
		return
	end
	local st = stateOfCreature(player)
	if not st or (Chaos.limited and Chaos.limited(player, "botdet.msg", 400)) then
		return
	end
	local msg = Chaos.decode(buffer)
	if not msg or type(msg.data) ~= "table" then
		return
	end
	local now = os.time()
	local ev
	if msg.action == "integrity" then
		if not BD.official then
			BD.loadOfficial()
		end
		local _, e = K.integrityChunk(st, cfg, msg.data, BD.official)
		ev = e
	elseif msg.action == "tools" then
		ev = K.toolCodes(st, cfg, msg.data)
	end
	if ev then
		ev.created_at = now
		BD.writeRows(st.guid, {ev})
	end
end
ext:type("extendedopcode")
ext:register()

-- ---------------------------------------------------------------- the one-second tick
function BD.poll(player, st, now)
	if player.getBotSignals then
		local sig = player:getBotSignals()
		if sig then
			K.onSignals(st, cfg, sig, now)
		end
	end
end

function BD.tick()
	BD.ticks = BD.ticks + 1
	local now = os.time()
	local poll = BD.ticks % cfg.pollEvery == 0
	for cid, guid in pairs(BD.byCid) do
		local st = BD.states[guid]
		local player = st and Player(cid)
		if not player then
			BD.byCid[cid] = nil
		else
			local pos = player:getPosition()
			K.onSample(st, cfg, pos.x, pos.y, pos.z, now)
			BD.stats.samples = BD.stats.samples + 1
			if poll then
				BD.poll(player, st, now)
			end
			if now >= st.nextFlush then
				st.nextFlush = now + cfg.flushSeconds
				try("flush", BD.flush, st, now)
			end
			if now >= st.nextHour then
				st.nextHour = now + cfg.hourlySeconds
				try("hourly", BD.hourly, st, now)
			end
		end
	end
	-- states of characters gone for good
	if BD.ticks % 600 == 0 then
		for guid, st in pairs(BD.states) do
			if K.expired(st, cfg, now) then
				BD.states[guid] = nil
			end
		end
		BD.maintenance(now)
	end
	return true
end

-- the daily purge and the daily top list
function BD.purge(now)
	local chunk = cfg.purgeChunk
	local function stmt(table_, col, days)
		return string.format("DELETE FROM `%s` WHERE `%s` < %d LIMIT %d", table_, col, now - days * 86400, chunk)
	end
	-- a day's rows are deleted in chunks, spaced so the database is never held
	for i = 0, 11 do
		addEvent(function()
			db.asyncQuery(stmt(T.events, "created_at", cfg.retention.eventDays))
			db.asyncQuery(stmt(T.scores, "hour_ts", cfg.retention.scoreDays))
		end, i * 5000)
	end
end

function BD.topRows(limit, since)
	limit = limit or cfg.report.topN
	-- the highest hour of each character: ties and the several hours of one character are cut here, so the query asks for more
	-- rows than the limit and needs no GROUP BY (a strict SQL mode refuses one with columns that are not grouped)
	local rows = Chaos.select(string.format("SELECT `player_name`, `total`, `route`, `regularity`, `reaction`, `heal`, `session`, " ..
		"`bonus`, `flagged` FROM `%s` WHERE `hour_ts` >= %d ORDER BY `total` DESC, `hour_ts` DESC LIMIT %d", T.scores, since, limit * 12),
		{{"player_name", "s"}, {"total", "n"}, {"route", "n"}, {"regularity", "n"}, {"reaction", "n"}, {"heal", "n"},
		{"session", "n"}, {"bonus", "n"}, {"flagged", "n"}})
	local out, seen = {}, {}
	for _, r in ipairs(rows) do
		if not seen[r.player_name] and #out < limit then
			seen[r.player_name] = true
			out[#out + 1] = r
		end
	end
	return out
end

function BD.topLines(limit, since)
	local lines = {}
	for i, r in ipairs(BD.topRows(limit, since or os.time() - 86400)) do
		lines[#lines + 1] = string.format("%2d. %-20s total %3d%s  route %d rhythm %d reaction %d heal %d session %d bonus %d", i, r.player_name,
			r.total, r.flagged == 1 and " FLAG" or "     ", r.route, r.regularity, r.reaction, r.heal, r.session, r.bonus)
	end
	if #lines == 0 then
		lines[1] = "No scores in the last 24 hours."
	end
	return lines
end

-- the daily list, appended to the log file (botcheck-top reads the table, this file is the history)
function BD.writeTop(now)
	local lines = BD.topLines(cfg.report.topN, now - 86400)
	local ok, f = pcall(io.open, cfg.report.logFile, "a")
	if not ok or not f then
		log("cannot write " .. tostring(cfg.report.logFile))
		return false
	end
	f:write(string.format("== %s botdet top %d (last 24 hours)\n", os.date("%Y-%m-%d %H:%M", now), cfg.report.topN))
	for _, l in ipairs(lines) do
		f:write(l .. "\n")
	end
	f:close()
	return true
end

function BD.maintenance(now)
	local hour = tonumber(os.date("%H", now)) or 0
	local day = os.date("%Y%j", now)
	if BD.lastPurge ~= day and hour >= cfg.report.logHour then
		BD.lastPurge = day
		try("purge", BD.purge, now)
	end
	if BD.lastTop ~= day and hour >= cfg.report.logHour then
		BD.lastTop = day
		try("top", BD.writeTop, now)
	end
end

local think = GlobalEvent("ChaosBotdetThink")
function think.onThink(interval)
	if cfg.enabled ~= false then
		try("tick", BD.tick)
	end
	return true
end
think:interval(cfg.sampleMs)
think:register()

local startup = GlobalEvent("ChaosBotdetStartup")
function startup.onStartup()
	try("tables", BD.ensureTables)
	try("official", BD.loadOfficial)
	return true
end
startup:type("startup")
startup:register()

-- ---------------------------------------------------------------- staff: /botcheck
function BD.checkLines(name)
	local guid, canonical = Chaos.findPlayer(name)
	if not guid then
		return {"No such character."}
	end
	local lines = {}
	local st = BD.states[guid]
	if st and BD.byCid[st.cid or -1] == guid then
		local res = BD.hourly(st, os.time())
		lines[#lines + 1] = canonical .. " (online, live numbers over the last hours)"
		for _, l in ipairs(K.lines(res, cfg)) do
			lines[#lines + 1] = l
		end
	else
		local rows = Chaos.select(string.format("SELECT `hour_ts`, `total`, `flagged`, `notes` FROM `%s` WHERE `player_id` = %d " ..
			"AND `hour_ts` >= %d ORDER BY `total` DESC LIMIT 1", T.scores, guid, os.time() - 86400),
			{{"hour_ts", "n"}, {"total", "n"}, {"flagged", "n"}, {"notes", "s"}})
		if #rows == 0 then
			lines[#lines + 1] = canonical .. ": no scores in the last 24 hours."
		else
			local r = rows[1]
			lines[#lines + 1] = string.format("%s (offline), the highest hour of the last 24: %s, total %d%s", canonical,
				os.date("%Y-%m-%d %H:00", r.hour_ts), r.total, r.flagged == 1 and " FLAGGED" or "")
			for part in (r.notes or ""):gmatch("[^|]+") do
				lines[#lines + 1] = (part:gsub("^%s+", ""):gsub("%s+$", ""))
			end
		end
	end
	-- the client's signals of the last 7 days
	for _, e in ipairs(Chaos.select(string.format("SELECT `type`, `data`, `created_at` FROM `%s` WHERE `player_id` = %d AND `type` IN " ..
			"('integrity', 'tool') AND `created_at` >= %d ORDER BY `id` DESC LIMIT 5", T.events, guid, os.time() - 7 * 86400),
			{{"type", "s"}, {"data", "s"}, {"created_at", "n"}})) do
		lines[#lines + 1] = string.format("client signal %s (%s): %s", e.type, os.date("%Y-%m-%d %H:%M", e.created_at), (e.data or ""):sub(1, 200))
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

local USAGE = "/botcheck <name> | /botcheck top [N] | /botcheck ask <name>"

local talk = TalkAction("/botcheck")
function talk.onSay(player, words, param)
	local allowed, staff = Chaos.staffCommand(player, words, param, false)
	if not allowed or groupOf(player) < cfg.staffGroup then
		return not staff
	end
	param = (param or ""):gsub("^%s+", ""):gsub("%s+$", "")
	if param == "" then
		player:sendTextMessage(MESSAGE_INFO_DESCR, USAGE)
		return false
	end
	local n = param:match("^[Tt][Oo][Pp]%s*(%d*)$")
	if n then
		reply(player, BD.topLines(tonumber(n) or cfg.report.topN))
		return false
	end
	local who = param:match("^[Aa][Ss][Kk]%s+(.+)$")
	if who then
		-- the optional question: the presence check of antibot.lua, sent now (never an action by itself)
		local target = Player(who)
		if not target then
			player:sendTextMessage(MESSAGE_INFO_DESCR, "That character is not online.")
		elseif ChaosAntibot and ChaosAntibot.forceCheck then
			local ok, why = ChaosAntibot.forceCheck(target)
			player:sendTextMessage(MESSAGE_INFO_DESCR, ok and ("Presence check sent to " .. target:getName() .. ".") or tostring(why))
		else
			player:sendTextMessage(MESSAGE_INFO_DESCR, "The presence check is not loaded.")
		end
		return false
	end
	reply(player, BD.checkLines(param))
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

reg{id = "botcheck_top", name = "Bot detection: top of the day", description = "The 20 highest scores of the last 24 hours.",
	params = {},
	handler = function(actor, p)
		return true, "Bot detection", BD.topLines(cfg.report.topN)
	end}

reg{id = "botcheck_show", name = "Bot detection: character", description = "The six heuristics with their numbers.",
	params = {{name = "player", label = "Player", type = "player", required = true}},
	handler = function(actor, p)
		return true, "Bot detection", BD.checkLines(p.player)
	end}
