-- Player reports (client game_antibot: the Report Player dialog; extended opcode 211, dispatched by antibot.lua).
-- Pure logic: reports_core.lua; numbers: antibot_config.lua `reports`; table chaos_reports (sql/chaos_reports.sql);
-- overview and staff guide: server/README.md "Anti-bot and player reports".
--
-- A report stores reporter, target, reason, note, the target's position when online (else the reporter's;
-- target_online says which), the time, the target's anti-bot score and its last lines in PUBLIC chat channels
-- (ChaosReports.onChannelSpeak, called from the public channel scripts by tools/patch_report_chat.py; never private
-- messages, never the default local chat). Cooldowns and limits per reporter account (reports_core.lua R.allow).
-- Opened from: right-click a player > Report Player, or System > Report a Player (players type no commands: README
-- "Player commands: the menu"; tests/commands_ui_test.lua refuses a spoken "!" command).
-- The base client's rule violation report (Player:onReportRuleViolation) lands in the same table (reason "other").
-- Bug reports (System > Report a Bug, Player:onReportBug via tools/patch_base_events.py step 12) too: reason "bug",
-- RP.onReportBug below; `/reports list bugs` lists the open ones.
-- Staff: `/reports` (list, show, close, log, score, check, clear) and the admin panel (Accounts & Security).
-- Lua 5.1 / LuaJIT compatible.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not Chaos.t then
	dofile("data/scripts/chaos/i18n_core.lua")
end
dofile("data/scripts/chaos/reports_core.lua")

Chaos.antibotConfig = Chaos.antibotConfig or dofile("data/scripts/chaos/antibot_config.lua")
local cfg = Chaos.antibotConfig
local rcfg = cfg.reports
local R = ChaosReportsCore
local OPCODE = ChaosOpcodes.antibot or 211
local T = Chaos.antibotTables or {reports = "chaos_reports", log = "chaos_antibot_log", holds = "chaos_antibot_holds"}

ChaosReports = ChaosReports or {}
local RP = ChaosReports
RP.state = RP.state or R.newState()

local function log(text)
	print("[Chaos reports] " .. text)
end

local function isStaff(player)
	local ok, group = pcall(function()
		return player:getGroup():getId()
	end)
	return ok and (tonumber(group) or 0) >= cfg.staffGroup
end

local function send(player, action, data)
	return Chaos.send(player, OPCODE, action, data or {})
end

local function hhmm(t)
	return os.date("%H:%M", t)
end

local function stamp(t)
	return os.date("%Y-%m-%d %H:%M", t)
end

function RP.ensureTable()
	db.query("CREATE TABLE IF NOT EXISTS `" .. T.reports .. "` (`id` int unsigned NOT NULL AUTO_INCREMENT, `created_at` int " ..
		"unsigned NOT NULL, `reporter_id` int unsigned NOT NULL, `reporter_account` int unsigned NOT NULL DEFAULT 0, " ..
		"`reporter_name` varchar(64) NOT NULL DEFAULT '', `target_id` int unsigned NOT NULL, `target_name` varchar(64) NOT " ..
		"NULL DEFAULT '', `reason` varchar(16) NOT NULL, `note` varchar(255) NOT NULL DEFAULT '', `pos_x` int unsigned NOT " ..
		"NULL DEFAULT 0, `pos_y` int unsigned NOT NULL DEFAULT 0, `pos_z` tinyint unsigned NOT NULL DEFAULT 0, " ..
		"`target_online` tinyint unsigned NOT NULL DEFAULT 0, `suspicion` int unsigned NOT NULL DEFAULT 0, `chat` text, " ..
		"`status` varchar(8) NOT NULL DEFAULT 'open', `closed_at` int unsigned NOT NULL DEFAULT 0, `closed_by` varchar(64) " ..
		"NOT NULL DEFAULT '', `staff_note` varchar(255) NOT NULL DEFAULT '', PRIMARY KEY (`id`), KEY `idx_status` " ..
		"(`status`, `created_at`), KEY `idx_target` (`target_id`), KEY `idx_reporter` (`reporter_account`, `created_at`)) " ..
		"ENGINE=InnoDB DEFAULT CHARSET=utf8mb4")
end

-- ---------------------------------------------------------------- public chat (tools/patch_report_chat.py)
-- called first in onSpeak of every public channel script; channel = the channel's name from chatchannels.xml
function RP.onChannelSpeak(player, channel, talkType, message)
	if rcfg.enabled == false or not player or type(message) ~= "string" then
		return
	end
	pcall(R.chatPush, RP.state, rcfg, player:getGuid(), tostring(channel or "?"), message, os.time())
end

-- ---------------------------------------------------------------- the webhook
local function webhookUrl()
	local env = os.getenv and os.getenv("CHAOS_REPORTS_WEBHOOK")
	local url = (env and env ~= "") and env or rcfg.discordWebhook
	return R.validWebhook(url) and url or nil
end

local function postWebhook(row)
	local url = webhookUrl()
	if not url or not os.execute or not io.open then
		return
	end
	local path = os.tmpname and os.tmpname() or nil
	local f = path and io.open(path, "w")
	if not f then
		return
	end
	f:write(json.encode(R.discordPayload(row)))
	f:close()
	-- the URL passed R.validWebhook (letters, digits, - and _ only after the fixed prefix), the body is a file: nothing
	-- from players reaches the shell. Runs in the background; the file is removed after the post.
	os.execute(string.format("(curl -s -m 10 -H 'Content-Type: application/json' --data @%s '%s' >/dev/null 2>&1; rm -f %s) &",
		path, url, path))
end

-- ---------------------------------------------------------------- submit
local function targetOf(name)
	local guid, canonical, online = Chaos.findPlayer(name)
	if not guid then
		return nil
	end
	local group = 1
	if online then
		group = online:getGroup():getId()
	else
		local rows = Chaos.select("SELECT `group_id` FROM `players` WHERE `id` = " .. guid, {{"group_id", "n"}})
		group = rows[1] and rows[1].group_id or 1
	end
	return {guid = guid, name = canonical, online = online, group = group}
end

local function insertRow(row)
	db.query(string.format("INSERT INTO `%s` (`created_at`, `reporter_id`, `reporter_account`, `reporter_name`, `target_id`, " ..
		"`target_name`, `reason`, `note`, `pos_x`, `pos_y`, `pos_z`, `target_online`, `suspicion`, `chat`) VALUES (%d, %d, %d, " ..
		"%s, %d, %s, %s, %s, %d, %d, %d, %d, %d, %s)", T.reports, row.created_at, row.reporter_id, row.reporter_account,
		db.escapeString(row.reporter_name), row.target_id, db.escapeString(row.target_name), db.escapeString(row.reason),
		db.escapeString(row.note), row.pos_x, row.pos_y, row.pos_z, row.target_online, row.suspicion, db.escapeString(row.chat)))
	row.id = db.lastInsertId and db.lastInsertId() or 0
end

local function tellStaff(text)
	for _, p in ipairs(Game.getPlayers()) do
		if isStaff(p) then
			p:sendTextMessage(MESSAGE_STATUS_CONSOLE_BLUE, text)
		end
	end
end

-- the row is written and returned (with its id) or nil, error key
function RP.submit(player, input)
	local reporter = {guid = player:getGuid(), name = player:getName(), level = player:getLevel(),
		account = player:getAccountId()}
	local clean, err = R.validate(rcfg, input, reporter)
	if not clean then
		return nil, err
	end
	local target = targetOf(clean.name)
	if not target then
		return nil, "unknown"
	end
	if target.guid == reporter.guid then
		return nil, "self"
	end
	if target.group >= cfg.staffGroup then
		return nil, "staff"
	end
	local now = os.time()
	local ok, why = R.allow(RP.state, rcfg, reporter, target.guid, now)
	if not ok then
		return nil, why
	end
	local pos = (target.online or player):getPosition()
	local row = {created_at = now, reporter_id = reporter.guid, reporter_account = reporter.account,
		reporter_name = reporter.name, target_id = target.guid, target_name = target.name, reason = clean.reason,
		note = clean.note, pos_x = pos.x, pos_y = pos.y, pos_z = pos.z, target_online = target.online and 1 or 0,
		suspicion = ChaosAntibot and ChaosAntibot.scoreOf and ChaosAntibot.scoreOf(target.guid) or 0,
		chat = table.concat(R.chatLines(RP.state, target.guid, hhmm), "\n")}
	insertRow(row)
	R.record(RP.state, rcfg, reporter, target.guid, now)
	log(string.format("#%d %s reported %s (%s)", row.id, row.reporter_name, row.target_name, row.reason))
	tellStaff(string.format("[Report #%d] %s reported %s: %s. /reports show %d", row.id, row.reporter_name,
		row.target_name, row.reason, row.id))
	pcall(postWebhook, row)
	return row
end

-- ---------------------------------------------------------------- bug reports (System > Report a Bug)
-- Player:onReportBug(message, position, category) of the base data/events/scripts/player.lua calls this first
-- (tools/patch_base_events.py step 12), so the stock callback that refused normal accounts and wrote text files under
-- data/reports/bugs/ no longer runs. Every account may report; limits: Chaos.limited per character (bugs.rapidMs) and
-- R.allowBug per account (cooldown, per day). The row is a chaos_reports row with reason "bug" (/reports, the admin
-- panel, the website staff page and the reports webhook show it). Returns the row or nil, error key.
function RP.submitBug(player, message, position, category)
	local bcfg = rcfg.bugs
	local clean, err = R.validateBug(bcfg, message, category)
	if not clean then
		return nil, err
	end
	if Chaos.limited(player, "reports.bug", bcfg.rapidMs or 5000) then
		return nil, "bugrapid"
	end
	local account = player:getAccountId()
	local now = os.time()
	local ok, why = R.allowBug(RP.state, bcfg, account, now)
	if not ok then
		return nil, why
	end
	local own = player:getPosition()
	local pos, posKind = R.bugPosition(category, position, own)
	local vocation = "?"
	pcall(function()
		vocation = player:getVocation():getName()
	end)
	local row = {created_at = now, reporter_id = player:getGuid(), reporter_account = account,
		reporter_name = player:getName(), target_id = player:getGuid(), target_name = player:getName(), reason = "bug",
		note = clean.note, pos_x = pos.x, pos_y = pos.y, pos_z = pos.z, target_online = 1, suspicion = 0,
		category = clean.category, shortened = clean.shortened,
		chat = R.bugDetails({category = clean.category, pos = pos, posKind = posKind, own = own,
			level = player:getLevel(), vocation = vocation, at = now, shortened = clean.shortened}, stamp)}
	insertRow(row)
	R.recordBug(RP.state, account, now)
	log(string.format("#%d bug (%s) from %s at %d, %d, %d", row.id, row.category, row.reporter_name, pos.x, pos.y, pos.z))
	tellStaff(string.format("[Bug #%d] %s (%s) at %d, %d, %d. /reports show %d", row.id, row.reporter_name,
		row.category, pos.x, pos.y, pos.z, row.id))
	pcall(postWebhook, row)
	return row
end

-- the engine event: the player always gets an answer in the server log window and on screen
function RP.onReportBug(player, message, position, category)
	local ok, row, err = pcall(RP.submitBug, player, message, position, category)
	if not ok then
		log("bug report: " .. tostring(row))
		row, err = nil, nil
	end
	if row then
		player:sendTextMessage(MESSAGE_INFO_DESCR, Chaos.t(player, "Thank you. Your bug report #%d was sent to the staff%s.",
			row.id, row.shortened and Chaos.t(player, " (shortened to %d characters)", rcfg.bugs.textMax) or ""))
	else
		player:sendTextMessage(MESSAGE_STATUS_SMALL, Chaos.t(player, R.errors[err] or
			"Your bug report could not be stored. Please report the bug on our Discord."))
	end
	return true
end

local function reasonsPayload()
	local out = {}
	for _, r in ipairs(rcfg.reasons) do
		out[#out + 1] = {k = r.key, n = r.label}
	end
	return out
end

function RP.open(player, name)
	send(player, "reportOpen", {name = R.clean(name, 29), reasons = reasonsPayload(), noteMax = rcfg.noteMax})
end

-- the opcode actions antibot.lua does not handle itself
function RP.handle(player, action, d)
	if action == "reportOpen" then
		return RP.open(player, d.name)
	elseif action == "report" then
		local row, err = RP.submit(player, d)
		if row then
			send(player, "reportResult", {ok = true, text = Chaos.t(player, "Thank you. Your report about %s was sent to the staff (#%d).",
				row.target_name, row.id)})
		else
			send(player, "reportResult", {ok = false, text = Chaos.tx(player, R.errors[err] or tostring(err))})
		end
	end
end

-- ---------------------------------------------------------------- the base client's rule violation report
local violation = EventCallback
violation.onReportRuleViolation = function(player, targetName, reportType, reportReason, comment, translation)
	local row = RP.submit(player, {name = targetName, reason = "other",
		note = string.format("(client report %s/%s) %s", tostring(reportType), tostring(reportReason), tostring(comment or ""))})
	if row then
		player:sendTextMessage(MESSAGE_INFO_DESCR, Chaos.t(player, "Your report about %s was sent to the staff.", row.target_name))
	end
end
violation:register()

-- ---------------------------------------------------------------- staff
local function rowsWhere(where, limit)
	return Chaos.select(string.format("SELECT `id`, `created_at`, `reporter_name`, `target_id`, `target_name`, `reason`, " ..
		"`note`, `pos_x`, `pos_y`, `pos_z`, `target_online`, `suspicion`, `chat`, `status`, `closed_at`, `closed_by`, " ..
		"`staff_note` FROM `%s` WHERE %s ORDER BY `id` DESC LIMIT %d", T.reports, where, limit),
		{{"id", "n"}, {"created_at", "n"}, {"reporter_name", "s"}, {"target_id", "n"}, {"target_name", "s"}, {"reason", "s"},
			{"note", "s"}, {"pos_x", "n"}, {"pos_y", "n"}, {"pos_z", "n"}, {"target_online", "n"}, {"suspicion", "n"},
			{"chat", "s"}, {"status", "s"}, {"closed_at", "n"}, {"closed_by", "s"}, {"staff_note", "s"}})
end

function RP.listLines(status, limit)
	local where = status == "all" and "1 = 1" or string.format("`status` = %s", db.escapeString(status or "open"))
	if status == "bugs" then
		where = "`status` = 'open' AND `reason` = 'bug'"
	end
	local lines = {}
	for _, r in ipairs(rowsWhere(where, limit or rcfg.listMax)) do
		lines[#lines + 1] = R.listLine(r, stamp)
	end
	return lines
end

function RP.detail(id)
	local r = rowsWhere("`id` = " .. math.floor(tonumber(id) or 0), 1)[1]
	if not r then
		return nil
	end
	local bug = r.reason == "bug"
	local lines = {R.listLine(r, stamp),
		string.format("Position %d, %d, %d (%s)", r.pos_x, r.pos_y, r.pos_z, bug and "bug report" or
			(r.target_online == 1 and "target" or "reporter; target offline")),
		(bug and "Text: " or "Note: ") .. (r.note ~= "" and r.note or "-")}
	if r.status == "closed" then
		lines[#lines + 1] = string.format("Closed %s by %s: %s", stamp(r.closed_at), r.closed_by, r.staff_note)
	end
	lines[#lines + 1] = bug and "Details:" or "Public chat of the target:"
	if r.chat == "" then
		lines[#lines + 1] = "  (none)"
	end
	for l in r.chat:gmatch("[^\n]+") do
		lines[#lines + 1] = "  " .. l
	end
	return lines
end

function RP.close(id, by, note)
	id = math.floor(tonumber(id) or 0)
	local r = rowsWhere("`id` = " .. id, 1)[1]
	if not r then
		return false, "No report #" .. id .. "."
	end
	if r.status == "closed" then
		return false, "Report #" .. id .. " is already closed."
	end
	db.query(string.format("UPDATE `%s` SET `status` = 'closed', `closed_at` = %d, `closed_by` = %s, `staff_note` = %s " ..
		"WHERE `id` = %d", T.reports, os.time(), db.escapeString(by), db.escapeString(R.clean(note, 255)), id))
	return true, "Report #" .. id .. " closed."
end

function RP.logLines(name, limit)
	local where = "1 = 1"
	if name and name ~= "" then
		local guid = Chaos.findPlayer(name)
		if not guid then
			return {"No character " .. name .. "."}
		end
		where = "`player_id` = " .. guid
	end
	local lines = {}
	for _, r in ipairs(Chaos.select(string.format("SELECT `created_at`, `player_name`, `kind`, `score`, `detail` FROM `%s` " ..
			"WHERE %s ORDER BY `id` DESC LIMIT %d", T.log, where, limit or 20), {{"created_at", "n"}, {"player_name", "s"},
			{"kind", "s"}, {"score", "n"}, {"detail", "s"}})) do
		lines[#lines + 1] = string.format("%s %s %s (%d): %s", stamp(r.created_at), r.player_name, r.kind, r.score, r.detail)
	end
	if #lines == 0 then
		lines[1] = "No anti-bot log entries."
	end
	return lines
end

function RP.scoreLines(name)
	local AB, K = ChaosAntibot, ChaosAntibotCore
	local st = AB and AB.stateByName(name)
	if not st then
		return {"No anti-bot state for " .. tostring(name) .. " (offline too long, staff, or never seen since the restart)."}
	end
	local lines = {name .. ": " .. K.summary(st)}
	local c = st.check
	lines[#lines + 1] = string.format("Checks: last %s, %d today, grace until %s%s", c.lastAt > 0 and stamp(c.lastAt) or "never",
		c.dayCount or 0, (c.graceUntil or 0) > 0 and stamp(c.graceUntil) or "-", c.active and ", one running now" or "")
	return lines
end

local function reply(player, lines)
	local text = table.concat(lines, "\n")
	if #lines > 3 and player.popupFYI then
		player:popupFYI(text)
	else
		for _, l in ipairs(lines) do
			player:sendTextMessage(MESSAGE_INFO_DESCR, l)
		end
	end
end

local USAGE = "/reports [list [open|closed|all|bugs]] | show <id> | close <id>, <note> | log [name] | score <name> | " ..
	"check <name> | clear <name>"

local staffTalk = TalkAction("/reports")
function staffTalk.onSay(player, words, param)
	if not isStaff(player) or not player:getGroup():getAccess() then
		return true -- plain chat for players
	end
	param = (param or ""):gsub("^%s+", ""):gsub("%s+$", "")
	local cmd, arg = param:match("^(%S*)%s*(.*)$")
	cmd = (cmd or ""):lower()
	if cmd == "" or cmd == "list" then
		local status = arg ~= "" and arg:lower() or "open"
		local lines = RP.listLines(status)
		table.insert(lines, 1, string.format("Reports (%s), newest first:", status))
		if #lines == 1 then
			lines[2] = "none"
		end
		reply(player, lines)
	elseif cmd == "show" then
		reply(player, RP.detail(arg) or {"No report #" .. arg .. "."})
	elseif cmd == "close" then
		local id, note = arg:match("^(%d+)%s*,?%s*(.*)$")
		local _, text = RP.close(id, player:getName(), note or "")
		player:sendTextMessage(MESSAGE_INFO_DESCR, text)
	elseif cmd == "log" then
		reply(player, RP.logLines(arg))
	elseif cmd == "score" then
		reply(player, RP.scoreLines(arg))
	elseif cmd == "check" then
		local target = Player(arg)
		local ok, why = false, "Character not online."
		if target and ChaosAntibot then
			ok, why = ChaosAntibot.forceCheck(target)
		end
		player:sendTextMessage(MESSAGE_INFO_DESCR, ok and ("Presence check sent to " .. target:getName() .. ".") or why)
	elseif cmd == "clear" then
		local guid, canonical = Chaos.findPlayer(arg)
		if not guid or not ChaosAntibot then
			player:sendTextMessage(MESSAGE_INFO_DESCR, Chaos.t(player, "No character %s.", arg))
		else
			local acc = Chaos.select("SELECT `account_id` FROM `players` WHERE `id` = " .. guid, {{"account_id", "n"}})[1]
			local cleared = acc and ChaosAntibot.clearHold(acc.account_id, player:getName())
			local st = ChaosAntibot.states[guid]
			if st then
				st.score = 0
			end
			ChaosAntibot.writeLog(guid, acc and acc.account_id or 0, canonical, "hold_cleared", 0, "by " .. player:getName())
			player:sendTextMessage(MESSAGE_INFO_DESCR, Chaos.t(player, "%s: score reset%s.", canonical,
				cleared and ", leaderboard hold cleared" or ""))
		end
	else
		player:sendTextMessage(MESSAGE_INFO_DESCR, USAGE)
	end
	return false
end
staffTalk:separator(" ")
staffTalk:register()

-- ---------------------------------------------------------------- admin panel (Accounts & Security)
ChaosAdminPending = ChaosAdminPending or {}
local function reg(def)
	def.category = "security"
	def.id = "security." .. def.id
	ChaosAdminPending[def.id] = def
end

reg{id = "reports_list", name = "Player reports", description = "Player and bug reports, newest first (max 30).",
	params = {{name = "status", label = "Status", type = "select", default = "open",
		options = {{value = "open", label = "Open"}, {value = "bugs", label = "Bug reports (open)"},
			{value = "closed", label = "Closed"}, {value = "all", label = "All"}}}},
	handler = function(actor, p)
		local lines = RP.listLines(p.status or "open")
		return true, #lines .. " report(s).", lines
	end}

reg{id = "reports_show", name = "Show report", description = "One report with its public chat lines.",
	params = {{name = "id", label = "Report id", type = "int", min = 1, required = true}},
	handler = function(actor, p)
		local lines = RP.detail(p.id)
		if not lines then
			return false, "No report #" .. tostring(p.id) .. "."
		end
		return true, "Report #" .. p.id, lines
	end}

reg{id = "reports_close", name = "Close report", description = "Close a report with a staff note.",
	params = {{name = "id", label = "Report id", type = "int", min = 1, required = true},
		{name = "note", label = "Staff note", type = "string", max = 200}},
	handler = function(actor, p)
		return RP.close(p.id, actor:getName(), p.note or "")
	end}

reg{id = "antibot_log", name = "Anti-bot log", description = "Anti-bot staff log (scores, presence checks), newest first.",
	params = {{name = "player", label = "Player (empty = all)", type = "string", max = 29}},
	handler = function(actor, p)
		return true, "Anti-bot log", RP.logLines(p.player, 30)
	end}

reg{id = "antibot_score", name = "Anti-bot score", description = "Suspicion score and signals of a character.",
	params = {{name = "player", label = "Player", type = "player", required = true}},
	handler = function(actor, p)
		return true, "Anti-bot score", RP.scoreLines(p.player)
	end}

-- ---------------------------------------------------------------- events
local logout = CreatureEvent("ChaosReportsLogout")
function logout.onLogout(player)
	R.chatGone(RP.state, player:getGuid(), os.time())
	return true
end
logout:type("logout")
logout:register()

local login = CreatureEvent("ChaosReportsLogin")
function login.onLogin(player)
	player:registerEvent("ChaosReportsLogout")
	return true
end
login:type("login")
login:register()

local sweep = GlobalEvent("ChaosReportsSweep")
function sweep.onThink(interval)
	R.chatSweep(RP.state, rcfg, os.time())
	return true
end
sweep:interval(300000)
sweep:register()

local startup = GlobalEvent("ChaosReportsStartup")
function startup.onStartup()
	local ok, err = pcall(RP.ensureTable)
	if not ok then
		log("table: " .. tostring(err))
	end
	return true
end
startup:type("startup")
startup:register()
