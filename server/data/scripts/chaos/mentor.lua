-- Mentor system (mentor_config.lua, mentor_core.lua; client game_mentor; website page Mentors).
--
-- A veteran account registers one of its characters as a mentor (the mentor card: language / region, play hours, a
-- note, accepting new apprentices, shown on the website). A new character (level <= apprentice.maxLevel, account at
-- most apprentice.maxAccountDays old) picks a mentor from the list (filters: class, language, online) or accepts an
-- invitation; a referred account's first character gets the referrer's mentor character at login (referral.autoPick).
-- Checks (ChaosMentorCore.linkCheck): not the own account, no staff, nobody banned, no shared IP and no shared private
-- e-mail domain (the referral program's household rules, ChaosReferral.accountFacts), a free place (maxApprentices),
-- monthlyLinks per mentor, at most maxMentors per apprentice, a cooldown after a dismiss, never the same pair twice.
-- While both hunt together (same party, in range, no shared IP now, the mentor not over the content: mentor level <=
-- max(apprentice level, monster level) x ratio + flat) the apprentice gets +exp and takes less damage from monsters,
-- and each such minute counts as shared hunting time: one Mentor Mark per marks.huntMinutes, dailyHuntMarks a day.
-- Milestones of the apprentice (levels, first rift / dungeon / bounty / world boss) give the mentor marks once per
-- apprentice character, only after milestoneMinShared minutes together; graduation at graduationLevel ends the link
-- and rewards both (after graduationMinShared minutes). Every mark respects marks.monthlyCap. Marks buy titles,
-- cosmetics and supplies (cfg.shop; ChaosMentorCore.validate refuses anything else).
--
-- Protocol (extended opcode ChaosOpcodes.mentor = 194, JSON {action, data}, server -> client through Chaos.sendChunked):
--   client -> server  open | sync | list {line, lang, online} | register {lang, hours, note, accepting, public} |
--                     retire | choose {guid} | invite {name} | accept {guid} | decline {guid} | dismiss |
--                     release {guid} | seek {on} | buy {key}
--   server -> client  status {...ChaosMentorCore.view...} (open = true: show the window) | mentors {rows} |
--                     message {text, error}
-- API: ChaosMentor.tagOf(player) -> "mentor" | "seeking" | nil (Party Finder). Staff: /mentor <player>[, unlink].
-- See server/README.md "Mentors". Lua 5.1 / LuaJIT compatible.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not ChaosReferralCore then
	dofile("data/scripts/chaos/referral_core.lua")
end
dofile("data/scripts/chaos/mentor_core.lua")
Chaos.mentorConfig = dofile("data/scripts/chaos/mentor_config.lua")

ChaosMentor = ChaosMentor or {}
local M = ChaosMentor
local K = ChaosMentorCore
local cfg = Chaos.mentorConfig
local T = cfg.tables
local OPCODE = ChaosOpcodes.mentor or 194
local refCfg = Chaos.referralConfig
if not refCfg then
	local ok, r = pcall(dofile, "data/scripts/chaos/referral_config.lua")
	refCfg = ok and r or {}
end

M.online = M.online or {} -- guid -> creature id
M.mentors = M.mentors or {} -- guid of an online mentor -> its row (+ apprentices = {guid...})
M.links = M.links or {} -- guid of an online apprentice -> its active link row (+ lastBonusAt)
M.titles = M.titles or {} -- guid -> {[offer key] = at} shop titles
M.invites = M.invites or {} -- apprentice guid -> {[mentor guid] = {at, name, level, voc, lang}}

local function q(text)
	return db.escapeString(tostring(text or ""))
end

local function log(playerId, otherId, action, detail)
	db.asyncQuery(string.format("INSERT INTO `%s` (`at`, `player_id`, `other_id`, `action`, `detail`) VALUES (%d, %d, %d, %s, %s)",
		T.log, os.time(), playerId or 0, otherId or 0, q(action), q(tostring(detail or ""):sub(1, 128))))
end

local function say(key, ...)
	local text = cfg.messages[key] or key
	if select("#", ...) > 0 then
		return string.format(text, ...)
	end
	return text
end

-- ------------------------------------------------------------------ tables
local SCHEMA = {
	[[CREATE TABLE IF NOT EXISTS `chaos_mentors` (`player_id` int(11) NOT NULL, `account_id` int(11) NOT NULL,
	`active` tinyint(1) NOT NULL DEFAULT 1, `accepting` tinyint(1) NOT NULL DEFAULT 1, `public` tinyint(1) NOT NULL DEFAULT 1,
	`lang` varchar(32) NOT NULL DEFAULT '', `hours` varchar(32) NOT NULL DEFAULT '', `note` varchar(96) NOT NULL DEFAULT '',
	`marks` int(11) NOT NULL DEFAULT 0, `earned` int(11) NOT NULL DEFAULT 0, `graduates` int(11) NOT NULL DEFAULT 0,
	`day_key` int(11) NOT NULL DEFAULT 0, `day_minutes` int(11) NOT NULL DEFAULT 0, `day_marks` int(11) NOT NULL DEFAULT 0,
	`month_key` int(11) NOT NULL DEFAULT 0, `month_marks` int(11) NOT NULL DEFAULT 0, `registered_at` bigint(20) NOT NULL DEFAULT 0,
	PRIMARY KEY (`player_id`), KEY `account_id` (`account_id`)) ENGINE=InnoDB DEFAULT CHARSET=utf8]],
	[[CREATE TABLE IF NOT EXISTS `chaos_mentor_links` (`id` int(11) NOT NULL AUTO_INCREMENT, `mentor_id` int(11) NOT NULL,
	`mentor_account` int(11) NOT NULL, `apprentice_id` int(11) NOT NULL, `apprentice_account` int(11) NOT NULL,
	`status` varchar(10) NOT NULL DEFAULT 'active', `source` varchar(8) NOT NULL DEFAULT 'list', `start_level` int(11) NOT NULL DEFAULT 0,
	`shared_minutes` int(11) NOT NULL DEFAULT 0, `linked_at` bigint(20) NOT NULL DEFAULT 0, `ended_at` bigint(20) NOT NULL DEFAULT 0,
	PRIMARY KEY (`id`), KEY `mentor_id` (`mentor_id`, `status`), KEY `apprentice_id` (`apprentice_id`, `status`))
	ENGINE=InnoDB DEFAULT CHARSET=utf8]],
	[[CREATE TABLE IF NOT EXISTS `chaos_mentor_milestones` (`apprentice_id` int(11) NOT NULL, `milestone` varchar(16) NOT NULL,
	`link_id` int(11) NOT NULL DEFAULT 0, `mentor_id` int(11) NOT NULL DEFAULT 0, `state` varchar(10) NOT NULL DEFAULT 'paid',
	`marks` int(11) NOT NULL DEFAULT 0, `reached_at` bigint(20) NOT NULL DEFAULT 0, `notified` tinyint(1) NOT NULL DEFAULT 0,
	PRIMARY KEY (`apprentice_id`, `milestone`), KEY `mentor_id` (`mentor_id`)) ENGINE=InnoDB DEFAULT CHARSET=utf8]],
	[[CREATE TABLE IF NOT EXISTS `chaos_mentor_purchases` (`id` int(11) NOT NULL AUTO_INCREMENT, `player_id` int(11) NOT NULL,
	`account_id` int(11) NOT NULL, `offer` varchar(32) NOT NULL, `cost` int(11) NOT NULL DEFAULT 0, `at` bigint(20) NOT NULL DEFAULT 0,
	PRIMARY KEY (`id`), KEY `player_id` (`player_id`, `offer`)) ENGINE=InnoDB DEFAULT CHARSET=utf8]],
	[[CREATE TABLE IF NOT EXISTS `chaos_mentor_log` (`id` int(11) NOT NULL AUTO_INCREMENT, `at` bigint(20) NOT NULL,
	`player_id` int(11) NOT NULL DEFAULT 0, `other_id` int(11) NOT NULL DEFAULT 0, `action` varchar(16) NOT NULL,
	`detail` varchar(128) NOT NULL DEFAULT '', PRIMARY KEY (`id`), KEY `player_id` (`player_id`)) ENGINE=InnoDB DEFAULT CHARSET=utf8]]
}

-- a write, then the rows it changed (ROW_COUNT() of the same connection, as guild.lua does)
local function exec(query)
	if not db.query(query) then
		return 0
	end
	local rows = Chaos.select("SELECT ROW_COUNT() AS `n`", {{"n", "n"}})
	return rows[1] and rows[1].n or 0
end

-- ------------------------------------------------------------------ players and accounts
local function playerOf(guid)
	local cid = guid and M.online[guid]
	local p = cid and Player(cid)
	if p and p:getGuid() == guid then
		return p
	end
	return nil
end
M.playerOf = playerOf

local function character(guid)
	return Chaos.select(string.format("SELECT `name`, `level`, `vocation`, `account_id`, `lastlogin` FROM `players` WHERE `id` = %d", guid),
		{{"name", "s"}, {"level", "n"}, {"vocation", "n"}, {"account_id", "n"}, {"lastlogin", "n"}})[1]
end

local function vocName(id)
	local ok, name = pcall(function()
		local v = Vocation(id)
		return v and v:getName() or ""
	end)
	return ok and name or ""
end

-- the referral program's facts (IPs, e-mail, creation, staff, banned); a minimal set when referral.lua is not loaded
local function facts(accountId)
	if ChaosReferral and ChaosReferral.accountFacts then
		local ok, f = pcall(ChaosReferral.accountFacts, accountId)
		if ok and f then
			return f
		end
	end
	local r = Chaos.select(string.format("SELECT `type`, `creation`, `email` FROM `accounts` WHERE `id` = %d", accountId),
		{{"type", "n"}, {"creation", "n"}, {"email", "s"}})[1] or {}
	local ips = {}
	for _, row in ipairs(Chaos.select(string.format("SELECT DISTINCT `lastip` FROM `players` WHERE `account_id` = %d AND `lastip` <> 0", accountId),
			{{"lastip", "n"}})) do
		ips[#ips + 1] = ChaosReferralCore.ipString(row.lastip)
	end
	return {created = r.creation, email = r.email, ips = ips, staff = (r.type or 0) >= cfg.staffAccountType, banned = false}
end

local function staffCharacter(accountId)
	return #Chaos.select(string.format("SELECT `id` FROM `players` WHERE `account_id` = %d AND `group_id` >= %d LIMIT 1",
		accountId, cfg.staffGroup), {{"id", "n"}}) > 0
end

local function accountDays(created, now)
	created = tonumber(created) or 0
	if created <= 0 then
		return nil
	end
	return math.floor((now - created) / 86400)
end

local function monthStart(t)
	local d = os.date("*t", t)
	return os.time({year = d.year, month = d.month, day = 1, hour = 0, min = 0, sec = 0})
end

-- the shop's weekly limits: the shared Monday 06:00 week (mentor_core.lua K.shopWeekStart)
local function weekStart(t)
	return K.shopWeekStart(t, cfg)
end

-- ------------------------------------------------------------------ rows
local MENTOR_COLS = {{"player_id", "n"}, {"account_id", "n"}, {"active", "n"}, {"accepting", "n"}, {"public", "n"}, {"lang", "s"},
	{"hours", "s"}, {"note", "s"}, {"marks", "n"}, {"earned", "n"}, {"graduates", "n"}, {"day_key", "n"}, {"day_minutes", "n"},
	{"day_marks", "n"}, {"month_key", "n"}, {"month_marks", "n"}, {"registered_at", "n"}}
local MENTOR_SELECT = "SELECT `player_id`, `account_id`, `active`, `accepting`, `public`, `lang`, `hours`, `note`, `marks`, `earned`, " ..
	"`graduates`, `day_key`, `day_minutes`, `day_marks`, `month_key`, `month_marks`, `registered_at` FROM `" .. T.mentors .. "`"
local LINK_COLS = {{"id", "n"}, {"mentor_id", "n"}, {"mentor_account", "n"}, {"apprentice_id", "n"}, {"apprentice_account", "n"},
	{"status", "s"}, {"source", "s"}, {"start_level", "n"}, {"shared_minutes", "n"}, {"linked_at", "n"}, {"ended_at", "n"}}
local LINK_SELECT = "SELECT `id`, `mentor_id`, `mentor_account`, `apprentice_id`, `apprentice_account`, `status`, `source`, `start_level`, " ..
	"`shared_minutes`, `linked_at`, `ended_at` FROM `" .. T.links .. "`"

local function mentorRow(guid)
	local r = Chaos.select(MENTOR_SELECT .. string.format(" WHERE `player_id` = %d", guid), MENTOR_COLS)[1]
	if r and r.active == 1 then
		return r
	end
	return nil
end

local function activeLinkOf(apprenticeGuid)
	return Chaos.select(LINK_SELECT .. string.format(" WHERE `apprentice_id` = %d AND `status` = 'active' LIMIT 1", apprenticeGuid), LINK_COLS)[1]
end

local function linksOfMentor(mentorGuid)
	return Chaos.select(LINK_SELECT .. string.format(" WHERE `mentor_id` = %d AND `status` = 'active' ORDER BY `linked_at`", mentorGuid), LINK_COLS)
end

local function linksThisMonth(mentorGuid, now)
	local r = Chaos.select(string.format("SELECT COUNT(*) AS `n` FROM `%s` WHERE `mentor_id` = %d AND `linked_at` >= %d", T.links, mentorGuid,
		monthStart(now)), {{"n", "n"}})[1]
	return r and r.n or 0
end

local function monthMarks(row, now)
	if not row or row.month_key ~= K.monthKey(now) then
		return 0
	end
	return row.month_marks
end

local function statesOf(apprenticeGuid)
	local out = {}
	for _, r in ipairs(Chaos.select(string.format("SELECT `milestone`, `state`, `marks` FROM `%s` WHERE `apprentice_id` = %d", T.milestones,
			apprenticeGuid), {{"milestone", "s"}, {"state", "s"}, {"marks", "n"}})) do
		out[r.milestone] = {state = r.state, marks = r.marks}
	end
	return out
end

-- (re)load what an online character needs in memory: its mentor row and apprentices, its link as an apprentice
function M.load(guid)
	local row = mentorRow(guid)
	if row then
		row.apprentices = {}
		for _, l in ipairs(linksOfMentor(guid)) do
			row.apprentices[#row.apprentices + 1] = l.apprentice_id
		end
	end
	M.mentors[guid] = row
	local link = activeLinkOf(guid)
	if link then
		local old = M.links[guid]
		link.lastBonusAt = old and old.id == link.id and old.lastBonusAt or 0
	end
	M.links[guid] = link
	local titles = {}
	for _, r in ipairs(Chaos.select(string.format("SELECT `offer`, MIN(`at`) AS `at` FROM `%s` WHERE `player_id` = %d GROUP BY `offer`",
			T.purchases, guid), {{"offer", "s"}, {"at", "n"}})) do
		local o = K.offer(cfg, r.offer)
		if o and o.kind == "title" then
			titles[r.offer] = r.at
		end
	end
	M.titles[guid] = titles
end

-- the marks of a mentor (online or not): monthly cap, then one UPDATE; returns what was paid and the state
local function addMarks(mentorGuid, marks, why)
	local now = os.time()
	local row = Chaos.select(MENTOR_SELECT .. string.format(" WHERE `player_id` = %d", mentorGuid), MENTOR_COLS)[1]
	if not row then
		return 0, "capped"
	end
	local paid, state = K.pay(marks, monthMarks(row, now), cfg)
	if paid > 0 then
		local mk = K.monthKey(now)
		db.query(string.format("UPDATE `%s` SET `marks` = `marks` + %d, `earned` = `earned` + %d, `month_marks` = IF(`month_key` = %d, " ..
			"`month_marks` + %d, %d), `month_key` = %d WHERE `player_id` = %d", T.mentors, paid, paid, mk, paid, paid, mk, mentorGuid))
		log(mentorGuid, 0, "marks", "+" .. paid .. " " .. tostring(why))
		if M.mentors[mentorGuid] then
			M.load(mentorGuid)
		end
	end
	return paid, state
end

-- ------------------------------------------------------------------ eligibility
local function mentorInfo(player)
	local accountId, guid = player:getAccountId(), player:getGuid()
	local f = facts(accountId)
	local agg = Chaos.select(string.format("SELECT MAX(`level`) AS `l`, SUM(`onlinetime`) AS `t` FROM `players` WHERE `account_id` = %d", accountId),
		{{"l", "n"}, {"t", "n"}})[1] or {}
	return {staff = f.staff or staffCharacter(accountId), banned = f.banned, accountLevel = agg.l or 0,
		onlineHours = math.floor((agg.t or 0) / 3600), accountDays = accountDays(f.created, os.time()) or 0, level = player:getLevel(),
		isApprentice = activeLinkOf(guid) ~= nil, registered = mentorRow(guid) ~= nil}
end

local function apprenticeInfo(player, f)
	local accountId, guid, now = player:getAccountId(), player:getGuid(), os.time()
	f = f or facts(accountId)
	local hist = Chaos.select(string.format("SELECT COUNT(*) AS `n`, SUM(`status` = 'graduated') AS `g`, MAX(IF(`status` IN ('dismissed', 'released'), " ..
		"`ended_at`, 0)) AS `e` FROM `%s` WHERE `apprentice_id` = %d", T.links, guid), {{"n", "n"}, {"g", "n"}, {"e", "n"}})[1] or {}
	local cooldown = (hist.e or 0) > 0 and (hist.e + cfg.apprentice.dismissCooldownHours * 3600 - now) or 0
	return {accountId = accountId, ips = f.ips, email = f.email, staff = f.staff or staffCharacter(accountId), banned = f.banned,
		level = player:getLevel(), accountDays = accountDays(f.created, now), hasMentor = activeLinkOf(guid) ~= nil,
		isMentor = mentorRow(guid) ~= nil, graduated = (hist.g or 0) > 0, mentors = hist.n or 0, cooldownLeft = math.max(0, cooldown)}
end

local function mentorSide(mentorGuid)
	local row = mentorRow(mentorGuid)
	if not row then
		return {exists = false}
	end
	local f = facts(row.account_id)
	return {exists = true, registered = true, accepting = row.accepting == 1, accountId = row.account_id, ips = f.ips, email = f.email,
		staff = f.staff or staffCharacter(row.account_id), banned = f.banned, active = #linksOfMentor(mentorGuid),
		linksThisMonth = linksThisMonth(mentorGuid, os.time())}
end

local function pairBefore(apprenticeGuid, mentorGuid)
	return #Chaos.select(string.format("SELECT `id` FROM `%s` WHERE `apprentice_id` = %d AND `mentor_id` = %d LIMIT 1", T.links,
		apprenticeGuid, mentorGuid), {{"id", "n"}}) > 0
end

-- ------------------------------------------------------------------ the client
local function send(player, action, data)
	if not player then
		return false
	end
	return Chaos.sendChunked(player, OPCODE, json.encode({action = action, data = data or {}}))
end

local function message(player, text, isError)
	send(player, "message", {text = text, error = isError == true})
	if isError then
		player:sendCancelMessage(text)
	else
		player:sendTextMessage(MESSAGE_INFO_DESCR, text)
	end
end

local function refuse(player, reason, extra)
	message(player, K.say(cfg, reason, extra), true)
end

local function tell(guid, text, kind)
	local p = playerOf(guid)
	if p then
		p:sendTextMessage(kind or MESSAGE_EVENT_ADVANCE, text)
	end
	return p
end

local function linkRowFor(link, otherGuid)
	local ch = character(otherGuid) or {}
	return {guid = otherGuid, name = ch.name or "?", level = ch.level or 0, voc = vocName(ch.vocation or 0),
		online = playerOf(otherGuid) ~= nil, linkedAt = link.linked_at, shared = link.shared_minutes, source = link.source,
		states = statesOf(link.apprentice_id)}
end

-- the over-level check and the rest of the bonus, for an apprentice and (optionally) a monster
local poolLevels
local function monsterLevel(monster)
	if not monster then
		return nil
	end
	if not poolLevels then
		poolLevels = {}
		local ok, pool = pcall(dofile, "data/scripts/chaos/bounty_pool.lua")
		if ok and type(pool) == "table" then
			for _, list in pairs(pool) do
				for _, e in ipairs(type(list) == "table" and list or {}) do
					if type(e) == "table" and e.name and e.level then
						poolLevels[e.name:lower()] = e.level
					end
				end
			end
		end
	end
	local lvl = poolLevels[monster:getName():lower()]
	if lvl then
		return lvl
	end
	local mt = monster:getType()
	return mt and K.estimateLevel(mt:experience(), mt:maxHealth()) or 0
end

local function partyLeaderId(player)
	local party = player:getParty()
	local leader = party and party:getLeader()
	return leader and leader:getId() or nil
end

local function bonusCtx(apprentice, link, monster)
	local mentor = playerOf(link.mentor_id)
	local ctx = {mentorOnline = mentor ~= nil, apprenticeLevel = apprentice:getLevel()}
	if mentor then
		local a, b = apprentice:getPosition(), mentor:getPosition()
		local lid = partyLeaderId(apprentice)
		ctx.sameParty = lid ~= nil and lid == partyLeaderId(mentor)
		ctx.distance = a.z == b.z and math.max(math.abs(a.x - b.x), math.abs(a.y - b.y)) or nil
		ctx.sameIpNow = apprentice:getIp() ~= 0 and apprentice:getIp() == mentor:getIp()
		ctx.mentorLevel = mentor:getLevel()
		ctx.monsterLevel = monsterLevel(monster)
	end
	return ctx
end

function M.bonusFor(apprentice, monster)
	local link = apprentice and M.links[apprentice:getGuid()]
	if not link then
		return false, "none"
	end
	return K.bonusActive(bonusCtx(apprentice, link, monster), cfg)
end

local function referrerMentor(player, f)
	if not f.referrerId or f.trackedPlayer ~= player:getGuid() then
		return nil
	end
	local r = Chaos.select(string.format("SELECT m.`player_id` AS `g`, p.`name` AS `n` FROM `%s` m JOIN `players` p ON p.`id` = m.`player_id` " ..
		"WHERE m.`account_id` = %d AND m.`active` = 1 ORDER BY m.`graduates` DESC, m.`registered_at` LIMIT 1", T.mentors, f.referrerId),
		{{"g", "n"}, {"n", "s"}})[1]
	return r and {guid = r.g, name = r.n} or nil
end

local function topMentors()
	local out = {}
	for _, r in ipairs(Chaos.select(string.format("SELECT p.`name` AS `name`, p.`level` AS `level`, p.`vocation` AS `voc`, m.`graduates` AS `g` " ..
			"FROM `%s` m JOIN `players` p ON p.`id` = m.`player_id` WHERE m.`graduates` > 0 ORDER BY m.`graduates` DESC, m.`player_id` LIMIT %d",
			T.mentors, cfg.topMax), {{"name", "s"}, {"level", "n"}, {"voc", "n"}, {"g", "n"}})) do
		out[#out + 1] = {name = r.name, level = r.level, voc = vocName(r.voc), graduates = r.g}
	end
	return out
end

local function sendStatus(player, open)
	local guid, now = player:getGuid(), os.time()
	local f = facts(player:getAccountId())
	local state = {me = {name = player:getName(), level = player:getLevel(), voc = vocName(player:getVocation():getId())}}
	local okM, rM = K.mentorCheck(mentorInfo(player), cfg)
	state.mentorOk, state.mentorReason = okM, rM
	local ai = apprenticeInfo(player, f)
	local okA, rA = K.apprenticeCheck(ai, cfg)
	state.apprenticeOk, state.apprenticeReason, state.cooldownLeft = okA, rA, ai.cooldownLeft
	state.graduated = ai.graduated
	local row = mentorRow(guid)
	if row then
		local m = {lang = row.lang, hours = row.hours, note = row.note, accepting = row.accepting == 1, public = row.public == 1,
			marks = row.marks, earned = row.earned, graduates = row.graduates, dayKey = row.day_key, dayMinutes = row.day_minutes,
			dayMarks = row.day_marks, monthMarks = monthMarks(row, now), linksThisMonth = linksThisMonth(guid, now), apprentices = {}}
		for _, l in ipairs(linksOfMentor(guid)) do
			m.apprentices[#m.apprentices + 1] = linkRowFor(l, l.apprentice_id)
		end
		state.mentor = m
	end
	local link = activeLinkOf(guid)
	if link then
		local a = linkRowFor(link, link.mentor_id)
		a.states = statesOf(guid)
		local ok, reason = K.bonusActive(bonusCtx(player, link, nil), cfg)
		a.bonus, a.bonusReason = ok, reason
		state.apprentice = a
	end
	state.invites = {}
	for mg, i in pairs(M.invites[guid] or {}) do
		if now - i.at <= cfg.inviteMinutes * 60 then
			state.invites[#state.invites + 1] = {guid = mg, name = i.name, level = i.level, voc = i.voc, lang = i.lang, at = i.at}
		end
	end
	state.seeking = player:getStorageValue(cfg.storage.seeking) == 1
	if not link and okA then
		state.referrer = referrerMentor(player, f)
	end
	state.owned, state.weekly = {}, {}
	for _, r in ipairs(Chaos.select(string.format("SELECT `offer`, SUM(`at` >= %d) AS `w` FROM `%s` WHERE `player_id` = %d GROUP BY `offer`",
			weekStart(now), T.purchases, guid), {{"offer", "s"}, {"w", "n"}})) do
		local o = K.offer(cfg, r.offer)
		if o and o.kind == "title" then
			state.owned[r.offer] = true
		end
		state.weekly[r.offer] = r.w or 0
	end
	for _, o in ipairs(cfg.shop) do
		if o.kind == "cosmetic" and ChaosCosmetics and ChaosCosmetics.owns and ChaosCosmetics.owns(player:getAccountId(), o.cosmetic) then
			state.owned[o.key] = true
		end
	end
	state.top = topMentors()
	local v = K.view(state, cfg, now)
	v.open = open == true
	send(player, "status", v)
end
M.sendStatus = sendStatus

local function sendList(player, data)
	local rows = {}
	local baseOf = Chaos.classes and Chaos.classes.baseOf or {}
	for _, r in ipairs(Chaos.select(string.format("SELECT m.`player_id` AS `g`, m.`account_id` AS `a`, m.`accepting` AS `acc`, m.`lang` AS `lang`, " ..
			"m.`hours` AS `hours`, m.`note` AS `note`, m.`graduates` AS `grad`, p.`name` AS `name`, p.`level` AS `level`, p.`vocation` AS `voc`, " ..
			"p.`lastlogin` AS `last`, (SELECT COUNT(*) FROM `%s` l WHERE l.`mentor_id` = m.`player_id` AND l.`status` = 'active') AS `act` " ..
			"FROM `%s` m JOIN `players` p ON p.`id` = m.`player_id` WHERE m.`active` = 1 AND m.`accepting` = 1 ORDER BY m.`graduates` DESC LIMIT 300",
			T.links, T.mentors), {{"g", "n"}, {"a", "n"}, {"acc", "n"}, {"lang", "s"}, {"hours", "s"}, {"note", "s"}, {"grad", "n"},
			{"name", "s"}, {"level", "n"}, {"voc", "n"}, {"last", "n"}, {"act", "n"}})) do
		rows[#rows + 1] = {guid = r.g, accountId = r.a, accepting = r.acc == 1, lang = r.lang, hours = r.hours, note = r.note,
			graduates = r.grad, name = r.name, level = r.level, voc = vocName(r.voc), line = K.lineOf(cfg, r.voc, baseOf),
			lastLogin = r.last, active = r.act, online = playerOf(r.g) ~= nil}
	end
	local f = {line = type(data.line) == "string" and data.line or "", lang = type(data.lang) == "string" and data.lang or "",
		online = (data.online == "now" or data.online == "week") and data.online or "any"}
	local out = {}
	for _, r in ipairs(K.filterMentors(rows, f, cfg, {accountId = player:getAccountId(), now = os.time()})) do
		out[#out + 1] = {guid = r.guid, name = r.name, level = r.level, voc = r.voc, line = r.line, lang = r.lang, hours = r.hours,
			note = r.note, graduates = r.graduates, active = r.active, max = cfg.mentor.maxApprentices, online = r.online}
	end
	send(player, "mentors", {rows = out, filter = f})
end

-- ------------------------------------------------------------------ milestones and graduation
local function eventFacts(player)
	local f = {level = player:getLevel()}
	local guid = player:getGuid()
	local runs = Chaos.tables and Chaos.tables.dungeonRunPlayers
	if runs then
		local ok, rows = pcall(Chaos.select, string.format("SELECT `run_id` FROM `%s` WHERE `player_id` = %d LIMIT 1", runs, guid), {{"run_id", "n"}})
		f.dungeon = ok and #rows > 0
	end
	local stats = ChaosAchievements and ChaosAchievements.stats and ChaosAchievements.stats[guid]
	if stats then
		f.rift = (tonumber(stats.rift_runs) or 0) > 0 or nil
		f.bounty = (tonumber(stats.bounty_done) or 0) > 0 or nil
		f.worldboss = (tonumber(stats.wb_kills) or 0) > 0 or nil
	end
	return f
end

local function giveItems(player, items)
	local inbox = player.getInbox and player:getInbox()
	for _, it in ipairs(items or {}) do
		local rest = it.count - Chaos.giveItem(player, it.id, it.count)
		while rest > 0 and inbox do
			local n = math.min(rest, 100)
			inbox:addItem(it.id, n, INDEX_WHEREEVER or -1, FLAG_NOLIMIT)
			rest = rest - n
		end
	end
end

local function endLink(link, status)
	db.query(string.format("UPDATE `%s` SET `status` = %s, `ended_at` = %d WHERE `id` = %d AND `status` = 'active'", T.links, q(status), os.time(), link.id))
	log(link.apprentice_id, link.mentor_id, status, "link " .. link.id)
	M.invites[link.apprentice_id] = nil
	for _, g in ipairs({link.apprentice_id, link.mentor_id}) do
		if playerOf(g) then
			M.load(g)
		end
	end
end

function M.graduate(player, link)
	local now = os.time()
	local row = Chaos.select(MENTOR_SELECT .. string.format(" WHERE `player_id` = %d", link.mentor_id), MENTOR_COLS)[1]
	local earned, marks = K.decideGraduation({shared = link.shared_minutes, monthMarks = monthMarks(row, now)}, cfg)
	local mentorName = (character(link.mentor_id) or {}).name or "?"
	db.query(string.format("INSERT IGNORE INTO `%s` (`apprentice_id`, `milestone`, `link_id`, `mentor_id`, `state`, `marks`, `reached_at`, `notified`) " ..
		"VALUES (%d, 'graduation', %d, %d, %s, %d, %d, %d)", T.milestones, player:getGuid(), link.id, link.mentor_id,
		q(earned and "paid" or "unearned"), marks, now, playerOf(link.mentor_id) and 1 or 0))
	endLink(link, "graduated")
	if earned then
		if marks > 0 then
			addMarks(link.mentor_id, marks, "graduation " .. player:getName())
		end
		db.query(string.format("UPDATE `%s` SET `graduates` = `graduates` + 1 WHERE `player_id` = %d", T.mentors, link.mentor_id))
		local g = Chaos.select(string.format("SELECT `graduates` FROM `%s` WHERE `player_id` = %d", T.mentors, link.mentor_id), {{"graduates", "n"}})[1]
		if ChaosAchievements and ChaosAchievements.set then
			pcall(ChaosAchievements.set, link.mentor_id, "mentor_graduates", g and g.graduates or 1)
			pcall(ChaosAchievements.set, player, "mentor_fledged", 1)
		end
		giveItems(player, cfg.graduation.items)
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, say("graduatedApprentice", mentorName, K.graduationText(cfg)))
		player:getPosition():sendMagicEffect(CONST_ME_FIREWORK_YELLOW or CONST_ME_MAGIC_GREEN or 13)
		tell(link.mentor_id, say("graduatedMentor", player:getName(), marks))
	else
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, say("graduatedUnearned", player:getName(), cfg.graduationLevel))
		tell(link.mentor_id, say("graduatedUnearned", player:getName(), cfg.graduationLevel))
	end
	log(player:getGuid(), link.mentor_id, "graduated", (earned and "earned " or "unearned ") .. marks)
end

-- record the milestones the apprentice reached (extra = {rift = true, ...} from a leaderboard record), pay the mentor
function M.checkApprentice(player, extra)
	local link = M.links[player:getGuid()]
	if not link then
		return
	end
	local f = eventFacts(player)
	for k, v in pairs(extra or {}) do
		f[k] = v
	end
	local now = os.time()
	local due = K.due(f, statesOf(player:getGuid()), cfg)
	for _, m in ipairs(due) do
		local row = Chaos.select(MENTOR_SELECT .. string.format(" WHERE `player_id` = %d", link.mentor_id), MENTOR_COLS)[1]
		local state, marks = K.decideMilestone(m, {shared = link.shared_minutes, monthMarks = monthMarks(row, now)}, cfg)
		local online = playerOf(link.mentor_id) ~= nil
		if exec(string.format("INSERT IGNORE INTO `%s` (`apprentice_id`, `milestone`, `link_id`, `mentor_id`, `state`, `marks`, `reached_at`, `notified`) " ..
				"VALUES (%d, %s, %d, %d, %s, %d, %d, %d)", T.milestones, player:getGuid(), q(m.key), link.id, link.mentor_id, q(state), marks, now,
				online and 1 or 0)) > 0 then
			if marks > 0 then
				addMarks(link.mentor_id, marks, m.key .. " " .. player:getName())
			end
			log(player:getGuid(), link.mentor_id, "milestone", m.key .. " " .. state .. " " .. marks)
			if state == "paid" then
				tell(link.mentor_id, say("milestone", player:getName(), m.name, marks))
			elseif state == "unearned" then
				tell(link.mentor_id, say("milestoneUnearned", player:getName(), m.name), MESSAGE_STATUS_CONSOLE_BLUE)
			else
				tell(link.mentor_id, say("milestoneCapped", player:getName(), m.name), MESSAGE_STATUS_CONSOLE_BLUE)
			end
		end
	end
	if player:getLevel() >= cfg.graduationLevel then
		M.graduate(player, link)
	end
end

-- milestones of the mentor's apprentices that happened while it was offline
local function notifyOffline(mentorGuid, player)
	local rows = Chaos.select(string.format("SELECT ms.`apprentice_id` AS `a`, ms.`milestone` AS `m`, ms.`state` AS `s`, ms.`marks` AS `k`, " ..
		"p.`name` AS `n` FROM `%s` ms JOIN `players` p ON p.`id` = ms.`apprentice_id` WHERE ms.`mentor_id` = %d AND ms.`notified` = 0",
		T.milestones, mentorGuid), {{"a", "n"}, {"m", "s"}, {"s", "s"}, {"k", "n"}, {"n", "s"}})
	for _, r in ipairs(rows) do
		local m = K.milestone(cfg, r.m)
		local name = m and m.name or ("Level " .. cfg.graduationLevel .. ": graduation")
		if r.m == "graduation" then
			player:sendTextMessage(MESSAGE_EVENT_ADVANCE, r.s == "paid" and say("graduatedMentor", r.n, r.k) or
				say("graduatedUnearned", r.n, cfg.graduationLevel))
		elseif r.s == "paid" then
			player:sendTextMessage(MESSAGE_EVENT_ADVANCE, say("milestone", r.n, name, r.k))
		end
	end
	if #rows > 0 then
		db.query(string.format("UPDATE `%s` SET `notified` = 1 WHERE `mentor_id` = %d AND `notified` = 0", T.milestones, mentorGuid))
	end
end

-- ------------------------------------------------------------------ linking
local function registerEvents(player)
	player:registerEvent("ChaosMentorHealth")
	player:registerEvent("ChaosMentorMana")
	player:registerEvent("ChaosMentorAdvance")
end

-- link `player` (the apprentice) to `mentorGuid`; source "list" | "invite" | "referral". Returns true or nil, reason.
function M.link(player, mentorGuid, source)
	if not cfg.enabled then
		return nil, "disabled"
	end
	local guid = player:getGuid()
	local f = facts(player:getAccountId())
	local info = {apprentice = apprenticeInfo(player, f), mentor = mentorSide(mentorGuid), source = source,
		pairBefore = pairBefore(guid, mentorGuid)}
	local ok, reason = K.linkCheck(info, cfg, refCfg)
	if not ok then
		log(guid, mentorGuid, "refused", source .. " " .. reason)
		return nil, reason, info.apprentice.cooldownLeft
	end
	local now = os.time()
	db.query(string.format("INSERT INTO `%s` (`mentor_id`, `mentor_account`, `apprentice_id`, `apprentice_account`, `status`, `source`, " ..
		"`start_level`, `shared_minutes`, `linked_at`) VALUES (%d, %d, %d, %d, 'active', %s, %d, 0, %d)", T.links, mentorGuid, info.mentor.accountId,
		guid, player:getAccountId(), q(source), player:getLevel(), now))
	local link = activeLinkOf(guid)
	if not link then
		return nil, "noMentor"
	end
	-- what was reached before the link never pays
	local before = K.reachedNow(eventFacts(player), cfg)
	local states = statesOf(guid)
	for key in pairs(before) do
		if not states[key] then
			db.query(string.format("INSERT IGNORE INTO `%s` (`apprentice_id`, `milestone`, `link_id`, `mentor_id`, `state`, `marks`, `reached_at`, " ..
				"`notified`) VALUES (%d, %s, %d, %d, 'before', 0, %d, 1)", T.milestones, guid, q(key), link.id, mentorGuid, now))
		end
	end
	player:setStorageValue(cfg.storage.seeking, 0)
	M.invites[guid] = nil
	log(guid, mentorGuid, "link", source)
	M.load(guid)
	if playerOf(mentorGuid) then
		M.load(mentorGuid)
	end
	registerEvents(player)
	local mentorName = (character(mentorGuid) or {}).name or "?"
	if source == "referral" then
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, say("autoLinked", mentorName))
	else
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, say("linked", mentorName, math.floor(cfg.bonus.exp * 100 + 0.5),
			math.floor(cfg.bonus.damageTaken * 100 + 0.5)))
	end
	local mp = tell(mentorGuid, say("linkedMentor", player:getName()))
	if mp then
		sendStatus(mp, false)
	end
	return true
end

-- the referral: a referred account's tracked character with no mentor gets the referrer's mentor character
function M.autoPick(player)
	if not (cfg.enabled and cfg.referral and cfg.referral.autoPick) or M.links[player:getGuid()] then
		return false
	end
	local f = facts(player:getAccountId())
	local target = referrerMentor(player, f)
	if not target or pairBefore(player:getGuid(), target.guid) then
		return false
	end
	local ok, reason = K.apprenticeCheck(apprenticeInfo(player, f), cfg)
	if not ok then
		return false, reason
	end
	return M.link(player, target.guid, "referral")
end

-- ------------------------------------------------------------------ actions
local function register(player, data)
	local guid = player:getGuid()
	local lang = K.cleanText(data.lang, cfg.mentor.langMax)
	local hours = K.cleanText(data.hours, cfg.mentor.hoursMax)
	local note = K.cleanText(data.note, cfg.mentor.noteMax)
	local accepting = data.accepting == false and 0 or 1
	local public = data.public == false and 0 or 1
	if mentorRow(guid) then
		db.query(string.format("UPDATE `%s` SET `lang` = %s, `hours` = %s, `note` = %s, `accepting` = %d, `public` = %d WHERE `player_id` = %d",
			T.mentors, q(lang), q(hours), q(note), accepting, public, guid))
		M.load(guid)
		message(player, say("saved"))
		return sendStatus(player, false)
	end
	local ok, reason = K.mentorCheck(mentorInfo(player), cfg)
	if not ok then
		return refuse(player, reason)
	end
	db.query(string.format("INSERT INTO `%s` (`player_id`, `account_id`, `active`, `accepting`, `public`, `lang`, `hours`, `note`, `registered_at`) " ..
		"VALUES (%d, %d, 1, %d, %d, %s, %s, %s, %d) ON DUPLICATE KEY UPDATE `active` = 1, `accepting` = VALUES(`accepting`), `public` = VALUES(`public`), " ..
		"`lang` = VALUES(`lang`), `hours` = VALUES(`hours`), `note` = VALUES(`note`)", T.mentors, guid, player:getAccountId(), accepting, public,
		q(lang), q(hours), q(note), os.time()))
	player:setStorageValue(cfg.storage.seeking, 0)
	log(guid, 0, "register", lang)
	M.load(guid)
	message(player, say("registeredOk"))
	sendStatus(player, false)
end

local function retire(player)
	local guid = player:getGuid()
	if not mentorRow(guid) then
		return refuse(player, "notMentor")
	end
	if #linksOfMentor(guid) > 0 then
		return refuse(player, "hasApprentices")
	end
	db.query(string.format("UPDATE `%s` SET `active` = 0 WHERE `player_id` = %d", T.mentors, guid)) -- marks and graduates stay
	log(guid, 0, "retire", "")
	M.load(guid)
	message(player, say("retired"))
	sendStatus(player, false)
end

local function choose(player, data)
	local mentorGuid = Chaos.toInt(data.guid, 1)
	if not mentorGuid then
		return refuse(player, "noMentor")
	end
	local ok, reason, extra = M.link(player, mentorGuid, "list")
	if not ok then
		refuse(player, reason, extra)
	end
	sendStatus(player, false)
end

local function invite(player, data)
	local guid = player:getGuid()
	local row = mentorRow(guid)
	if not row then
		return refuse(player, "notMentor")
	end
	local name = type(data.name) == "string" and data.name:gsub("^%s+", ""):gsub("%s+$", "") or ""
	local target = name ~= "" and #name <= 29 and Player(name) or nil
	if not target or target:getGuid() == guid then
		return refuse(player, "offline")
	end
	local f = facts(target:getAccountId())
	local info = {apprentice = apprenticeInfo(target, f), mentor = mentorSide(guid), source = "invite",
		pairBefore = pairBefore(target:getGuid(), guid)}
	local ok, reason = K.linkCheck(info, cfg, refCfg)
	if not ok then
		log(guid, target:getGuid(), "refused", "invite " .. reason)
		return refuse(player, reason, info.apprentice.cooldownLeft)
	end
	M.invites[target:getGuid()] = M.invites[target:getGuid()] or {}
	M.invites[target:getGuid()][guid] = {at = os.time(), name = player:getName(), level = player:getLevel(),
		voc = vocName(player:getVocation():getId()), lang = row.lang}
	target:sendTextMessage(MESSAGE_EVENT_ADVANCE, say("invited", player:getName()))
	sendStatus(target, false)
	message(player, say("inviteSent", target:getName()))
end

local function accept(player, data)
	local mentorGuid = Chaos.toInt(data.guid, 1)
	local i = mentorGuid and (M.invites[player:getGuid()] or {})[mentorGuid]
	if not i or os.time() - i.at > cfg.inviteMinutes * 60 then
		refuse(player, "noInvite")
		return sendStatus(player, false)
	end
	local ok, reason, extra = M.link(player, mentorGuid, "invite")
	if not ok then
		refuse(player, reason, extra)
	end
	sendStatus(player, false)
end

local function decline(player, data)
	local mentorGuid = Chaos.toInt(data.guid, 1)
	if mentorGuid and M.invites[player:getGuid()] then
		M.invites[player:getGuid()][mentorGuid] = nil
	end
	sendStatus(player, false)
end

local function dismiss(player)
	local link = activeLinkOf(player:getGuid())
	if not link then
		return refuse(player, "noMentor")
	end
	local mentorName = (character(link.mentor_id) or {}).name or "?"
	endLink(link, "dismissed")
	message(player, say("dismissed", mentorName))
	local mp = tell(link.mentor_id, say("dismissedMentor", player:getName()), MESSAGE_STATUS_CONSOLE_BLUE)
	if mp then
		sendStatus(mp, false)
	end
	sendStatus(player, false)
end

local function release(player, data)
	local apprenticeGuid = Chaos.toInt(data.guid, 1)
	local link = apprenticeGuid and activeLinkOf(apprenticeGuid)
	if not link or link.mentor_id ~= player:getGuid() then
		return refuse(player, "noApprentice")
	end
	local name = (character(apprenticeGuid) or {}).name or "?"
	endLink(link, "released")
	message(player, say("released", name))
	local ap = tell(apprenticeGuid, say("releasedApprentice", player:getName()), MESSAGE_STATUS_CONSOLE_BLUE)
	if ap then
		sendStatus(ap, false)
	end
	sendStatus(player, false)
end

local function seek(player, data)
	local on = data.on == true
	if on then
		local ok, reason = K.apprenticeCheck(apprenticeInfo(player), cfg)
		if not ok then
			return refuse(player, reason)
		end
	end
	player:setStorageValue(cfg.storage.seeking, on and 1 or 0)
	sendStatus(player, false)
end

local function buy(player, data)
	local guid, accountId = player:getGuid(), player:getAccountId()
	local o = type(data.key) == "string" and K.offer(cfg, data.key) or nil
	local row = mentorRow(guid)
	if not row then
		return refuse(player, "notMentor")
	end
	local now = os.time()
	local ctx = {marks = row.marks, cosmetics = ChaosCosmetics and ChaosCosmetics.grant and true or false}
	if o then
		local used = Chaos.select(string.format("SELECT COUNT(*) AS `n`, SUM(`at` >= %d) AS `w` FROM `%s` WHERE `player_id` = %d AND `offer` = %s",
			weekStart(now), T.purchases, guid, q(o.key)), {{"n", "n"}, {"w", "n"}})[1] or {}
		ctx.weeklyUsed = used.w or 0
		if o.kind == "title" then
			ctx.owned = (used.n or 0) > 0
		elseif o.kind == "cosmetic" and ctx.cosmetics then
			ctx.owned = ChaosCosmetics.owns(accountId, o.cosmetic)
		end
	end
	local ok, reason = K.shopCheck(o, ctx, cfg)
	if not ok then
		return refuse(player, reason)
	end
	if o.kind == "item" and player:getFreeCapacity() < 100 and not (player.getInbox and player:getInbox()) then
		return refuse(player, "noRoom")
	end
	-- pay first, with one conditional UPDATE
	if exec(string.format("UPDATE `%s` SET `marks` = `marks` - %d WHERE `player_id` = %d AND `marks` >= %d", T.mentors, o.cost, guid, o.cost)) < 1 then
		return refuse(player, "notEnough")
	end
	local delivered = true
	if o.kind == "cosmetic" then
		delivered = ChaosCosmetics.grant(accountId, o.cosmetic, "mentor") and true or false
	elseif o.kind == "item" then
		giveItems(player, {{id = o.item, count = o.count}})
	end
	if not delivered then
		db.query(string.format("UPDATE `%s` SET `marks` = `marks` + %d WHERE `player_id` = %d", T.mentors, o.cost, guid))
		return refuse(player, "owned")
	end
	db.query(string.format("INSERT INTO `%s` (`player_id`, `account_id`, `offer`, `cost`, `at`) VALUES (%d, %d, %s, %d, %d)", T.purchases, guid,
		accountId, q(o.key), o.cost, now))
	log(guid, 0, "buy", o.key .. " " .. o.cost)
	M.load(guid)
	if o.kind == "title" and ChaosNameplate and ChaosNameplate.refresh then
		pcall(ChaosNameplate.refresh, player)
	end
	message(player, say("bought", o.name))
	sendStatus(player, false)
end

-- ------------------------------------------------------------------ protocol
local ACTIONS = {
	open = {500, function(player) sendStatus(player, true) end},
	sync = {500, function(player) sendStatus(player, false) end},
	list = {800, sendList},
	register = {2000, register},
	retire = {2000, retire},
	choose = {2000, choose},
	invite = {2000, invite},
	accept = {1000, accept},
	decline = {500, decline},
	dismiss = {2000, dismiss},
	release = {2000, release},
	seek = {1000, seek},
	buy = {1000, buy}
}

local ext = CreatureEvent("ChaosMentorExtended")
function ext.onExtendedOpcode(player, opcode, buffer)
	if opcode ~= OPCODE then
		return
	end
	local msg = Chaos.decode(buffer)
	local a = msg and ACTIONS[msg.action]
	if not a then
		return
	end
	if ChaosRateLimit and not ChaosRateLimit.allow(player, "mentor." .. msg.action, a[1]) then
		return
	end
	if not cfg.enabled and msg.action ~= "open" and msg.action ~= "sync" then
		return refuse(player, "disabled")
	end
	local ok, err = pcall(a[2], player, type(msg.data) == "table" and msg.data or {})
	if not ok then
		print("[Chaos mentor] " .. tostring(msg.action) .. " failed: " .. tostring(err))
	end
end
ext:type("extendedopcode")
ext:register()

-- ------------------------------------------------------------------ the bonus
local xp = EventCallback
xp.onGainExperience = function(player, source, exp, rawExp)
	if not cfg.enabled or (exp or 0) <= 0 or not source or not source.isMonster or not source:isMonster() then
		return exp
	end
	local link = M.links[player:getGuid()]
	if not link then
		return exp
	end
	local ok, active = pcall(M.bonusFor, player, source)
	if ok and active then
		link.lastBonusAt = os.time()
		return math.floor(exp * (1 + cfg.bonus.exp))
	end
	return exp
end
xp:register()

local function lessDamage(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType)
	if cfg.enabled and attacker and attacker:isMonster() and primaryType ~= COMBAT_HEALING then
		local player = creature:getPlayer()
		local ok, active = pcall(M.bonusFor, player, attacker)
		if ok and active then
			local keep = 1 - cfg.bonus.damageTaken
			primaryDamage = math.floor(primaryDamage * keep)
			if secondaryType ~= COMBAT_HEALING then
				secondaryDamage = math.floor(secondaryDamage * keep)
			end
		end
	end
	return primaryDamage, primaryType, secondaryDamage, secondaryType
end

local health = CreatureEvent("ChaosMentorHealth")
function health.onHealthChange(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType, origin)
	return lessDamage(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType)
end
health:register()

local mana = CreatureEvent("ChaosMentorMana")
function mana.onManaChange(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType, origin)
	return lessDamage(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType)
end
mana:register()

local advance = CreatureEvent("ChaosMentorAdvance")
function advance.onAdvance(player, skill, oldLevel, newLevel)
	if skill == SKILL_LEVEL and cfg.enabled and M.links[player:getGuid()] then
		local ok, err = pcall(M.checkApprentice, player)
		if not ok then
			print("[Chaos mentor] advance: " .. tostring(err))
		end
	end
	return true
end
advance:register()

-- shared hunting time, once a minute: a link whose apprentice got the bonus in the last minute counts a minute; the
-- mentor earns a mark per marks.huntMinutes of such minutes (any apprentice), dailyHuntMarks a day
function M.tick(now)
	now = now or os.time()
	local counted = {}
	for guid, link in pairs(M.links) do
		if playerOf(guid) and now - (link.lastBonusAt or 0) <= 60 then
			link.shared_minutes = (link.shared_minutes or 0) + 1
			db.query(string.format("UPDATE `%s` SET `shared_minutes` = `shared_minutes` + 1 WHERE `id` = %d AND `status` = 'active'", T.links, link.id))
			counted[link.mentor_id] = true
		end
	end
	for mentorGuid in pairs(counted) do
		local row = Chaos.select(MENTOR_SELECT .. string.format(" WHERE `player_id` = %d", mentorGuid), MENTOR_COLS)[1]
		if row then
			local m = {dayKey = row.day_key, dayMinutes = row.day_minutes, dayMarks = row.day_marks}
			local got = K.huntMinute(m, now, cfg, monthMarks(row, now))
			db.query(string.format("UPDATE `%s` SET `day_key` = %d, `day_minutes` = %d, `day_marks` = %d WHERE `player_id` = %d", T.mentors,
				m.dayKey, m.dayMinutes, m.dayMarks, mentorGuid))
			if got > 0 then
				addMarks(mentorGuid, got, "hunt")
				tell(mentorGuid, say("huntMark", m.dayMarks, cfg.marks.dailyHuntMarks), MESSAGE_STATUS_CONSOLE_BLUE)
			end
		end
	end
	-- a first dungeon is only in the database: look for it once a minute for the online apprentices
	for guid, link in pairs(M.links) do
		local p = playerOf(guid)
		if p then
			local st = statesOf(guid)
			if not st.dungeon then
				M.checkApprentice(p)
			end
		end
	end
	for g, list in pairs(M.invites) do
		for mg, i in pairs(list) do
			if now - i.at > cfg.inviteMinutes * 60 then
				list[mg] = nil
			end
		end
		if next(list) == nil then
			M.invites[g] = nil
		end
	end
end

local think = GlobalEvent("ChaosMentorTick")
function think.onThink(interval)
	if cfg.enabled then
		local ok, err = pcall(M.tick)
		if not ok then
			print("[Chaos mentor] tick: " .. tostring(err))
		end
	end
	return true
end
think:interval(60000)
think:register()

-- ------------------------------------------------------------------ hooks into other systems
-- the Party Finder's tag of a character
function M.tagOf(player)
	if not cfg.enabled or not player then
		return nil
	end
	local guid = player:getGuid()
	local row = M.mentors[guid]
	return K.tagOf({mentor = row and row.accepting == 1 and #(row.apprentices or {}) < cfg.mentor.maxApprentices,
		seeking = not M.links[guid] and player:getLevel() <= cfg.apprentice.maxLevel and player:getStorageValue(cfg.storage.seeking) == 1})
end

local BOARD_EVENT = {rift = "rift", bounty = "bounty", worldboss = "worldboss"}
function M.onRecord(board, who)
	local event = BOARD_EVENT[board]
	if not event then
		return
	end
	local guid = type(who) == "userdata" and who:getGuid() or (type(who) == "table" and tonumber(who.guid)) or tonumber(who)
	local p = guid and M.links[guid] and playerOf(guid)
	if p then
		M.checkApprentice(p, {[event] = true})
	end
end

-- wrap ChaosLeaderboard.record (again after a /reload of leaderboard.lua), as guild.lua and season.lua do
if not (ChaosWrapChain and ChaosWrapChain.wrap) then
	dofile("data/scripts/chaos/wrapchain_core.lua")
end
function M.wrapLeaderboard()
	ChaosWrapChain.wrap(ChaosLeaderboard, "record", "mentor", function(res, board, who)
		M.onRecord(board, who)
	end, function(e) print("[Chaos mentor] record: " .. e) end)
end

function M.ensureHooks()
	if ChaosTitles and ChaosTitles.register then
		ChaosTitles.register("mentor", function(player)
			return player and K.titles(M.titles[player:getGuid()], cfg) or nil
		end)
	end
	M.wrapLeaderboard()
end

-- ------------------------------------------------------------------ login / logout / startup
local login = CreatureEvent("ChaosMentorLogin")
function login.onLogin(player)
	player:registerEvent("ChaosMentorExtended")
	player:registerEvent("ChaosMentorLogout")
	local guid = player:getGuid()
	M.online[guid] = player:getId()
	local ok, err = pcall(function()
		M.ensureHooks()
		M.load(guid)
		if cfg.enabled then
			M.autoPick(player)
		end
		if M.links[guid] then
			registerEvents(player)
			M.checkApprentice(player)
		end
		if M.mentors[guid] then
			notifyOffline(guid, player)
		end
	end)
	if not ok then
		print("[Chaos mentor] login: " .. tostring(err))
	end
	return true
end
login:register()

local logout = CreatureEvent("ChaosMentorLogout")
function logout.onLogout(player)
	local guid = player:getGuid()
	M.online[guid], M.mentors[guid], M.links[guid], M.titles[guid] = nil, nil, nil, nil
	return true
end
logout:register()

local startup = GlobalEvent("ChaosMentorStartup")
function startup.onStartup()
	for _, sql in ipairs(SCHEMA) do
		db.query(sql)
	end
	local problems = K.validate(cfg, {cosmetics = ChaosCosmeticsConfig})
	for _, p in ipairs(problems) do
		print("[Chaos mentor] config: " .. p)
	end
	M.ensureHooks()
	return true
end
startup:register()

-- ------------------------------------------------------------------ staff
local talk = TalkAction("/mentor")
function talk.onSay(player, words, param)
	if not player:getGroup():getAccess() then
		return true
	end
	local name, action = param:match("^%s*([^,]+)%s*,?%s*(%a*)")
	local guid = name and Chaos.findPlayer(name:gsub("%s+$", ""))
	if not guid then
		player:sendCancelMessage("Usage: /mentor <player>[, unlink]")
		return false
	end
	local link = activeLinkOf(guid)
	if action == "unlink" then
		if link then
			endLink(link, "released")
			log(guid, link.mentor_id, "unlink", "by " .. player:getName())
		end
		player:sendTextMessage(MESSAGE_INFO_DESCR, link and "Mentor link removed." or "No active mentor link.")
		return false
	end
	local lines = {}
	local row = mentorRow(guid)
	if row then
		lines[#lines + 1] = string.format("Mentor: %d marks (%d earned, %d this month), %d graduates, %d apprentices, accepting %s.", row.marks,
			row.earned, monthMarks(row, os.time()), row.graduates, #linksOfMentor(guid), row.accepting == 1 and "yes" or "no")
	end
	if link then
		lines[#lines + 1] = string.format("Apprentice of %s since %s (%s), %d minutes together.", (character(link.mentor_id) or {}).name or "?",
			os.date("%Y-%m-%d", link.linked_at), link.source, link.shared_minutes)
	end
	player:showTextDialog(2160, #lines > 0 and table.concat(lines, "\n") or "No mentor data.")
	return false
end
talk:separator(" ")
talk:register()

-- a /reload rebuilds titles.lua's table after this file: put the hooks back once all are loaded
addEvent(function()
	M.ensureHooks()
end, 0)
