-- Referral program (referral_config.lua, referral_core.lua; client game_referral; website register form).
--
-- An account gets a referral code (chaos_referral_codes) once one of its characters reached cfg.minReferrerLevel. A new
-- account enters a friend's code at creation on the website (written as a `pending` link, checked here at its first
-- login) or in game in Character > Referral within cfg.entryDays of its creation (checked at once). The checks
-- (ChaosReferralCore.linkCheck): one referrer per account, not the own code, no staff on either side, referrer not
-- banned, no referring back, no shared IP, no shared private e-mail domain, at most monthlyLinks new friends per
-- referrer and month. An accepted link (`active`) fixes the referred account's first character (lowest character id)
-- and gives the friend's gift (supplies and a title) to the character that logs in.
-- When that first character reaches a milestone level (cfg.milestones) the referrer earns its reward: a row in
-- chaos_referral_rewards, paid at once (Chaos Coins to the account, the title on the name plate) unless the referred
-- account is banned (void), the referrer is banned or has had monthlyRewards rewards this month (both: wait, paid at a
-- later login, at server start or by the retry every cfg.retryMinutes). The referrer is told at once or at the next login.
--
-- Protocol (extended opcode ChaosOpcodes.referral = 220, JSON {action, data}):
--   client -> server  open | sync | enter {code}
--   server -> client  status {...ChaosReferralCore.view...} (open = true: show the window) | message {text, error}
-- Staff: /referral <player>[, unlink]. See server/README.md "Referral program". Lua 5.1 / LuaJIT compatible.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
dofile("data/scripts/chaos/referral_core.lua")
Chaos.referralConfig = dofile("data/scripts/chaos/referral_config.lua")

ChaosReferral = ChaosReferral or {}
local Ref = ChaosReferral
local Core = ChaosReferralCore
local cfg = Chaos.referralConfig
local T = cfg.tables
local MSG = cfg.messages
local AB = cfg.antiAbuse or {}
local OPCODE = ChaosOpcodes.referral or 220

Ref.accounts = Ref.accounts or {} -- account id -> {gift, giftAt, paid = {[key] = at}} (titles), loaded at login

local function q(text)
	return db.escapeString(tostring(text or ""))
end

local function say(key, ...)
	local text = MSG[key] or key
	if select("#", ...) > 0 then
		return string.format(text, ...)
	end
	return text
end

-- ------------------------------------------------------------------ tables
local SCHEMA = {
	[[CREATE TABLE IF NOT EXISTS `chaos_referral_codes` (`account_id` int(11) NOT NULL, `code` varchar(16) NOT NULL,
	`created_at` bigint(20) NOT NULL DEFAULT 0, PRIMARY KEY (`account_id`), UNIQUE KEY `code` (`code`)) ENGINE=InnoDB DEFAULT CHARSET=utf8]],
	[[CREATE TABLE IF NOT EXISTS `chaos_referrals` (`referred_account_id` int(11) NOT NULL, `referrer_account_id` int(11) NOT NULL,
	`code` varchar(16) NOT NULL DEFAULT '', `source` varchar(8) NOT NULL DEFAULT 'game', `status` varchar(10) NOT NULL DEFAULT 'pending',
	`reason` varchar(32) NOT NULL DEFAULT '', `reg_ip` varchar(45) NOT NULL DEFAULT '', `created_at` bigint(20) NOT NULL DEFAULT 0,
	`linked_at` bigint(20) NOT NULL DEFAULT 0, `player_id` int(11) NOT NULL DEFAULT 0, `gift_at` bigint(20) NOT NULL DEFAULT 0,
	`gift_player_id` int(11) NOT NULL DEFAULT 0, PRIMARY KEY (`referred_account_id`), KEY `referrer_account_id` (`referrer_account_id`))
	ENGINE=InnoDB DEFAULT CHARSET=utf8]],
	[[CREATE TABLE IF NOT EXISTS `chaos_referral_rewards` (`referred_account_id` int(11) NOT NULL, `milestone` varchar(16) NOT NULL,
	`referrer_account_id` int(11) NOT NULL, `player_id` int(11) NOT NULL DEFAULT 0, `reached_at` bigint(20) NOT NULL DEFAULT 0,
	`state` varchar(8) NOT NULL DEFAULT 'due', `paid_at` bigint(20) NOT NULL DEFAULT 0, `coins` int(11) NOT NULL DEFAULT 0,
	`notified` tinyint(1) NOT NULL DEFAULT 0, PRIMARY KEY (`referred_account_id`, `milestone`), KEY `referrer_account_id` (`referrer_account_id`))
	ENGINE=InnoDB DEFAULT CHARSET=utf8]],
	[[CREATE TABLE IF NOT EXISTS `chaos_referral_log` (`id` int(11) NOT NULL AUTO_INCREMENT, `at` bigint(20) NOT NULL,
	`account_id` int(11) NOT NULL DEFAULT 0, `other_account_id` int(11) NOT NULL DEFAULT 0, `player_id` int(11) NOT NULL DEFAULT 0,
	`action` varchar(16) NOT NULL, `detail` varchar(128) NOT NULL DEFAULT '', PRIMARY KEY (`id`), KEY `account_id` (`account_id`))
	ENGINE=InnoDB DEFAULT CHARSET=utf8]]
}

local function log(accountId, otherId, playerId, action, detail)
	db.asyncQuery(string.format("INSERT INTO `%s` (`at`, `account_id`, `other_account_id`, `player_id`, `action`, `detail`) VALUES (%d, %d, %d, %d, %s, %s)",
		T.log, os.time(), accountId or 0, otherId or 0, playerId or 0, q(action), q(tostring(detail or ""):sub(1, 128))))
	print(string.format("[Chaos referral] %s: account %d, other %d, player %d %s", action, accountId or 0, otherId or 0, playerId or 0, tostring(detail or "")))
end

-- ------------------------------------------------------------------ account facts
local znoteChecked, hasZnote = false, false
local function znote()
	if not znoteChecked then
		znoteChecked = true
		hasZnote = #Chaos.select("SELECT `table_name` AS `t` FROM `information_schema`.`tables` WHERE `table_schema` = DATABASE() " ..
			"AND `table_name` = 'znote_accounts'", {{"t", "s"}}) > 0
	end
	return hasZnote
end

local function accountRow(accountId)
	local r = Chaos.select(string.format("SELECT `type`, `creation`, `email` FROM `accounts` WHERE `id` = %d", accountId),
		{{"type", "n"}, {"creation", "n"}, {"email", "s"}})[1]
	if not r then
		return nil
	end
	r.ips = {}
	if znote() then
		local z = Chaos.select(string.format("SELECT `created`, `ip` FROM `znote_accounts` WHERE `account_id` = %d", accountId),
			{{"created", "n"}, {"ip", "n"}})[1]
		if z then
			if (r.creation or 0) <= 0 then
				r.creation = z.created
			end
			r.ips[#r.ips + 1] = Core.ipFromLong(z.ip)
		end
	end
	return r
end

local function onlineOf(accountId)
	local out = {}
	for _, p in ipairs(Game.getPlayers()) do
		if p:getAccountId() == accountId then
			out[#out + 1] = p
		end
	end
	return out
end

local function isStaff(accountId, row)
	row = row or accountRow(accountId)
	if row and (row.type or 0) >= (AB.staffAccountType or 2) then
		return true
	end
	return #Chaos.select(string.format("SELECT `id` FROM `players` WHERE `account_id` = %d AND `group_id` >= %d LIMIT 1",
		accountId, AB.staffGroup or 2), {{"id", "n"}}) > 0
end

local function isBanned(accountId)
	return #Chaos.select(string.format("SELECT `account_id` FROM `account_bans` WHERE `account_id` = %d AND (`expires_at` <= 0 OR `expires_at` > %d)",
		accountId, os.time()), {{"account_id", "n"}}) > 0
end
Ref.isBanned = isBanned

-- every IP the account is known by: login IPs of its characters (and of those online), its registration IP
local function ipsOf(accountId, row, link)
	local ips = {}
	for _, ip in ipairs(row and row.ips or {}) do
		ips[#ips + 1] = ip
	end
	for _, r in ipairs(Chaos.select(string.format("SELECT DISTINCT `lastip` FROM `players` WHERE `account_id` = %d AND `lastip` <> 0", accountId),
			{{"lastip", "n"}})) do
		ips[#ips + 1] = Core.ipString(r.lastip)
	end
	for _, p in ipairs(onlineOf(accountId)) do
		ips[#ips + 1] = Core.ipString(p:getIp())
	end
	if link and link.reg_ip and link.reg_ip ~= "" then
		ips[#ips + 1] = link.reg_ip
	end
	return ips
end

local function maxLevel(accountId)
	local r = Chaos.select(string.format("SELECT MAX(`level`) AS `m` FROM `players` WHERE `account_id` = %d", accountId), {{"m", "n"}})[1]
	return r and r.m or 0
end

local function firstCharacter(accountId)
	local r = Chaos.select(string.format("SELECT MIN(`id`) AS `m` FROM `players` WHERE `account_id` = %d", accountId), {{"m", "n"}})[1]
	return r and r.m or 0
end

local function characterOf(guid)
	return Chaos.select(string.format("SELECT `name`, `level` FROM `players` WHERE `id` = %d", guid), {{"name", "s"}, {"level", "n"}})[1]
end

-- the name shown for an account: its highest-level character
local function accountName(accountId)
	local r = Chaos.select(string.format("SELECT `name` FROM `players` WHERE `account_id` = %d ORDER BY `level` DESC, `id` LIMIT 1", accountId),
		{{"name", "s"}})[1]
	return r and r.name or ("account " .. accountId)
end

local function monthStart(t)
	local d = os.date("*t", t)
	return os.time({year = d.year, month = d.month, day = 1, hour = 0, min = 0, sec = 0})
end

local LINK_COLS = {{"referred_account_id", "n"}, {"referrer_account_id", "n"}, {"code", "s"}, {"source", "s"}, {"status", "s"},
	{"reason", "s"}, {"reg_ip", "s"}, {"created_at", "n"}, {"linked_at", "n"}, {"player_id", "n"}, {"gift_at", "n"}, {"gift_player_id", "n"}}
local LINK_SELECT = "SELECT `referred_account_id`, `referrer_account_id`, `code`, `source`, `status`, `reason`, `reg_ip`, `created_at`, " ..
	"`linked_at`, `player_id`, `gift_at`, `gift_player_id` FROM `" .. T.links .. "`"

local function linkOf(accountId)
	return Chaos.select(LINK_SELECT .. string.format(" WHERE `referred_account_id` = %d", accountId), LINK_COLS)[1]
end

local function linksThisMonth(referrerId, now)
	local r = Chaos.select(string.format("SELECT COUNT(*) AS `n` FROM `%s` WHERE `referrer_account_id` = %d AND `status` = 'active' AND `linked_at` >= %d",
		T.links, referrerId, monthStart(now)), {{"n", "n"}})[1]
	return r and r.n or 0
end

local function paidThisMonth(referrerId, now)
	local r = Chaos.select(string.format("SELECT COUNT(*) AS `n` FROM `%s` WHERE `referrer_account_id` = %d AND `state` = 'paid' AND `paid_at` >= %d",
		T.rewards, referrerId, monthStart(now)), {{"n", "n"}})[1]
	return r and r.n or 0
end

-- the account facts of the referral's anti-abuse checks, for other systems (mentor.lua reuses them): creation time,
-- e-mail, every known IP, staff, banned, and the active referral link (referrer account, tracked character)
function Ref.accountFacts(accountId)
	local row = accountRow(accountId) or {ips = {}}
	local link = linkOf(accountId)
	local active = link and link.status == "active"
	return {created = row.creation, email = row.email, ips = ipsOf(accountId, row, link), staff = isStaff(accountId, row),
		banned = isBanned(accountId), referrerId = active and link.referrer_account_id or nil,
		trackedPlayer = active and link.player_id or nil}
end

-- ------------------------------------------------------------------ codes
local function codeOfAccount(accountId)
	local r = Chaos.select(string.format("SELECT `code` FROM `%s` WHERE `account_id` = %d", T.codes, accountId), {{"code", "s"}})[1]
	return r and r.code or nil
end

local function accountOfCode(code)
	local r = Chaos.select(string.format("SELECT `account_id` FROM `%s` WHERE `code` = %s", T.codes, q(code)), {{"account_id", "n"}})[1]
	return r and r.account_id or nil
end

-- the account's code, made when it may hold one; nil, reason otherwise
function Ref.codeFor(accountId)
	local code = codeOfAccount(accountId)
	if code then
		return code
	end
	local ok, reason = Core.codeHolder({staff = isStaff(accountId), maxLevel = maxLevel(accountId)}, cfg)
	if not ok then
		return nil, reason
	end
	for _ = 1, 20 do
		local c = Core.make(math.random, cfg)
		if not accountOfCode(c) then
			db.query(string.format("INSERT IGNORE INTO `%s` (`account_id`, `code`, `created_at`) VALUES (%d, %s, %d)", T.codes, accountId, q(c), os.time()))
			code = codeOfAccount(accountId)
			if code then
				log(accountId, 0, 0, "code", code)
				return code
			end
		end
	end
	return nil, "disabled"
end

-- ------------------------------------------------------------------ titles (account-wide)
function Ref.load(accountId)
	local st = {gift = false, giftAt = 0, paid = {}}
	local link = linkOf(accountId)
	if link and link.status == "active" and link.gift_at > 0 then
		st.gift, st.giftAt = true, link.gift_at
	end
	for _, r in ipairs(Chaos.select(string.format("SELECT `milestone`, `paid_at` FROM `%s` WHERE `referrer_account_id` = %d AND `state` = 'paid' ORDER BY `paid_at`",
			T.rewards, accountId), {{"milestone", "s"}, {"paid_at", "n"}})) do
		st.paid[r.milestone] = st.paid[r.milestone] or r.paid_at
	end
	Ref.accounts[accountId] = st
	return st
end

local function titleSource(player)
	if not player then
		return nil
	end
	local st = Ref.accounts[player:getAccountId()]
	if not st then
		return nil
	end
	return Core.titles(st, cfg)
end

local function refreshAccount(accountId)
	Ref.load(accountId)
	for _, p in ipairs(onlineOf(accountId)) do
		if ChaosNameplate and ChaosNameplate.refresh then
			pcall(ChaosNameplate.refresh, p)
		end
	end
end

function Ref.ensureHooks()
	if ChaosTitles and ChaosTitles.register then
		ChaosTitles.register("referral", titleSource)
	end
end

-- ------------------------------------------------------------------ client
local function send(player, action, data)
	Chaos.send(player, OPCODE, action, data)
end

local function message(player, text, isError)
	send(player, "message", {text = text, error = isError == true})
	if isError then
		player:sendCancelMessage(text)
	else
		player:sendTextMessage(MESSAGE_INFO_DESCR, text)
	end
end

local function friendsOf(accountId)
	local list = {}
	local links = Chaos.select(LINK_SELECT .. string.format(" WHERE `referrer_account_id` = %d AND `status` = 'active' ORDER BY `linked_at`", accountId), LINK_COLS)
	for _, l in ipairs(links) do
		local ch = l.player_id > 0 and characterOf(l.player_id) or nil
		local f = {name = ch and ch.name or "(no character yet)", level = ch and ch.level or 0, linkedAt = l.linked_at, status = l.status, rewards = {}}
		for _, r in ipairs(Chaos.select(string.format("SELECT `milestone`, `state`, `paid_at` FROM `%s` WHERE `referred_account_id` = %d",
				T.rewards, l.referred_account_id), {{"milestone", "s"}, {"state", "s"}, {"paid_at", "n"}})) do
			f.rewards[r.milestone] = {state = r.state, at = r.paid_at}
		end
		list[#list + 1] = f
	end
	return list
end

local function sendStatus(player, open)
	local accountId = player:getAccountId()
	local now = os.time()
	local row = accountRow(accountId) or {}
	local code, reason = Ref.codeFor(accountId)
	local link = linkOf(accountId)
	local state = {
		code = code, holderReason = reason, created = row.creation, staff = isStaff(accountId, row),
		friends = friendsOf(accountId), linksThisMonth = linksThisMonth(accountId, now), paidThisMonth = paidThisMonth(accountId, now)
	}
	local coins = Chaos.select(string.format("SELECT SUM(`coins`) AS `c` FROM `%s` WHERE `referrer_account_id` = %d AND `state` = 'paid'",
		T.rewards, accountId), {{"c", "n"}})[1]
	state.coinsEarned = coins and coins.c or 0
	if link then
		state.link = {status = link.status, referrerName = accountName(link.referrer_account_id), gift = link.gift_at > 0,
			reason = link.status == "rejected" and say(link.reason, cfg.entryDays) or ""}
	end
	local v = Core.view(state, cfg, now)
	v.open = open == true
	send(player, "status", v)
end
Ref.sendStatus = sendStatus

-- ------------------------------------------------------------------ the friend's gift
local function giveGift(player, link)
	if link.status ~= "active" or link.gift_at > 0 then
		return false
	end
	local gift = cfg.starterGift
	-- check the depot inbox first: what does not fit in the backpack goes there (as achievements.lua and bounty.lua do)
	local inbox = player.getInbox and player:getInbox()
	if not inbox then
		player:sendTextMessage(MESSAGE_STATUS_CONSOLE_BLUE, say("giftNoRoom"))
		return false
	end
	local toInbox = false
	for _, it in ipairs(gift.items or {}) do
		local rest = it.count - Chaos.giveItem(player, it.id, it.count)
		while rest > 0 do
			local n = math.min(rest, 100)
			inbox:addItem(it.id, n, INDEX_WHEREEVER or -1, FLAG_NOLIMIT)
			rest = rest - n
			toInbox = true
		end
	end
	if toInbox then
		player:sendTextMessage(MESSAGE_STATUS_CONSOLE_BLUE, say("giftInbox"))
	end
	local now = os.time()
	db.query(string.format("UPDATE `%s` SET `gift_at` = %d, `gift_player_id` = %d WHERE `referred_account_id` = %d AND `gift_at` = 0",
		T.links, now, player:getGuid(), link.referred_account_id))
	link.gift_at = now
	log(link.referred_account_id, link.referrer_account_id, player:getGuid(), "gift", Core.giftText(cfg))
	player:sendTextMessage(MESSAGE_EVENT_ADVANCE, say("gift", Core.giftText(cfg), gift.title and gift.title.text or ""))
	player:getPosition():sendMagicEffect(CONST_ME_GIFT_WRAPS or CONST_ME_MAGIC_GREEN or 13)
	refreshAccount(link.referred_account_id)
	return true
end

-- ------------------------------------------------------------------ linking
-- the facts linkCheck needs for `player`'s account taking `referrerId`'s code
local function checkInfo(player, referrerId, link, ignoreWindow)
	local accountId = player:getAccountId()
	local me = accountRow(accountId) or {ips = {}}
	local him = referrerId and accountRow(referrerId) or nil
	local hisLink = referrerId and linkOf(referrerId) or nil
	return {
		now = os.time(), ignoreWindow = ignoreWindow,
		referee = {accountId = accountId, created = me.creation, staff = isStaff(accountId, me), link = link,
			ips = ipsOf(accountId, me, link), email = me.email},
		referrer = him and {accountId = referrerId, staff = isStaff(referrerId, him), banned = isBanned(referrerId),
			ips = ipsOf(referrerId, him, hisLink), email = him.email, linksThisMonth = linksThisMonth(referrerId, os.time()),
			referredBy = hisLink and hisLink.status == "active" and hisLink.referrer_account_id or nil} or nil
	}
end

local function activate(player, link, referrerId, code, source)
	local accountId = player:getAccountId()
	local now = os.time()
	local first = firstCharacter(accountId)
	db.query(string.format("INSERT INTO `%s` (`referred_account_id`, `referrer_account_id`, `code`, `source`, `status`, `reason`, `created_at`, " ..
		"`linked_at`, `player_id`) VALUES (%d, %d, %s, %s, 'active', '', %d, %d, %d) ON DUPLICATE KEY UPDATE `referrer_account_id` = VALUES(`referrer_account_id`), " ..
		"`code` = VALUES(`code`), `source` = VALUES(`source`), `status` = 'active', `reason` = '', `linked_at` = VALUES(`linked_at`), `player_id` = VALUES(`player_id`)",
		T.links, accountId, referrerId, q(code), q(source), link and link.created_at or now, now, first))
	log(accountId, referrerId, player:getGuid(), "link", source .. " " .. code)
	local fresh = linkOf(accountId)
	player:sendTextMessage(MESSAGE_EVENT_ADVANCE, say("linked", accountName(referrerId)))
	if fresh then
		giveGift(player, fresh)
	end
	return fresh
end

-- a code typed in game
function Ref.enter(player, text)
	if not cfg.enabled then
		return message(player, say("disabled"), true)
	end
	local code = Core.normalize(text, cfg)
	if not code then
		return message(player, say("badCode"), true)
	end
	local referrerId = accountOfCode(code)
	local link = linkOf(player:getAccountId())
	local ok, reason = Core.linkCheck(checkInfo(player, referrerId, link, false), cfg)
	if not ok then
		log(player:getAccountId(), referrerId or 0, player:getGuid(), "refused", reason .. " " .. code)
		message(player, say(reason, cfg.entryDays), true)
		return sendStatus(player, false)
	end
	local fresh = activate(player, link, referrerId, code, "game")
	if fresh and fresh.player_id == player:getGuid() then
		player:registerEvent("ChaosReferralAdvance")
		Ref.checkMilestones(player)
	end
	sendStatus(player, false)
	send(player, "message", {text = say("linked", accountName(referrerId)), error = false})
end

-- a code entered on the website: checked at the first login of the account
local function checkPending(player, link)
	local code = Core.normalize(link.code, cfg)
	local referrerId = code and accountOfCode(code) or nil
	if referrerId and referrerId ~= link.referrer_account_id then
		referrerId = nil
	end
	local ok, reason
	if not referrerId then
		ok, reason = nil, "unknownCode"
	else
		local info = checkInfo(player, referrerId, nil, true)
		ok, reason = Core.linkCheck(info, cfg)
	end
	if not ok then
		db.query(string.format("UPDATE `%s` SET `status` = 'rejected', `reason` = %s WHERE `referred_account_id` = %d", T.links, q(reason), link.referred_account_id))
		log(link.referred_account_id, link.referrer_account_id, player:getGuid(), "rejected", reason .. " " .. tostring(link.code))
		player:sendTextMessage(MESSAGE_STATUS_CONSOLE_BLUE, say("rejected", say(reason, cfg.entryDays)))
		return nil
	end
	return activate(player, link, referrerId, code, "web")
end

-- ------------------------------------------------------------------ milestones and rewards
local function notify(referrerId)
	local online = onlineOf(referrerId)
	if #online == 0 then
		return
	end
	local rows = Chaos.select(string.format("SELECT `referred_account_id`, `milestone`, `state`, `coins`, `player_id` FROM `%s` WHERE `referrer_account_id` = %d " ..
		"AND `notified` = 0 AND `state` IN ('paid', 'void') ORDER BY `reached_at`", T.rewards, referrerId),
		{{"referred_account_id", "n"}, {"milestone", "s"}, {"state", "s"}, {"coins", "n"}, {"player_id", "n"}})
	for _, r in ipairs(rows) do
		local m = Core.milestone(cfg, r.milestone)
		local ch = characterOf(r.player_id)
		local name = ch and ch.name or "?"
		if m then
			local text = r.state == "paid" and say("paid", name, m.level, Core.rewardText(m)) or say("void", name, m.level)
			for _, p in ipairs(online) do
				p:sendTextMessage(MESSAGE_EVENT_ADVANCE, text)
			end
		end
		db.query(string.format("UPDATE `%s` SET `notified` = 1 WHERE `referred_account_id` = %d AND `milestone` = %s",
			T.rewards, r.referred_account_id, q(r.milestone)))
	end
end

-- pays (or voids) the due rewards of a referrer; returns how many were paid
function Ref.processRewards(referrerId)
	local now = os.time()
	local due = Chaos.select(string.format("SELECT `referred_account_id`, `milestone`, `player_id` FROM `%s` WHERE `referrer_account_id` = %d AND `state` = 'due' " ..
		"ORDER BY `reached_at`", T.rewards, referrerId), {{"referred_account_id", "n"}, {"milestone", "s"}, {"player_id", "n"}})
	if #due == 0 then
		return 0
	end
	local referrerBanned = isBanned(referrerId)
	local paid, waiting = 0, {}
	for _, r in ipairs(due) do
		local m = Core.milestone(cfg, r.milestone)
		local decision = m and Core.decide({referredBanned = isBanned(r.referred_account_id), referrerBanned = referrerBanned,
			paidThisMonth = paidThisMonth(referrerId, now)}, cfg) or "void"
		if decision == "pay" then
			local coins = tonumber(m.coins) or 0
			db.query(string.format("UPDATE `%s` SET `state` = 'paid', `paid_at` = %d, `coins` = %d WHERE `referred_account_id` = %d AND `milestone` = %s AND `state` = 'due'",
				T.rewards, now, coins, r.referred_account_id, q(r.milestone)))
			if coins > 0 then
				db.query(string.format("INSERT INTO `%s` (`account_id`, `coins`) VALUES (%d, %d) ON DUPLICATE KEY UPDATE `coins` = `coins` + %d",
					Chaos.tables.shopCoins, referrerId, coins, coins))
			end
			log(referrerId, r.referred_account_id, r.player_id, "paid", r.milestone .. " " .. Core.rewardText(m))
			paid = paid + 1
		elseif decision == "void" then
			db.query(string.format("UPDATE `%s` SET `state` = 'void' WHERE `referred_account_id` = %d AND `milestone` = %s AND `state` = 'due'",
				T.rewards, r.referred_account_id, q(r.milestone)))
			log(referrerId, r.referred_account_id, r.player_id, "void", r.milestone)
		else
			waiting[#waiting + 1] = r
		end
	end
	if paid > 0 then
		refreshAccount(referrerId)
	end
	notify(referrerId)
	return paid, waiting
end

-- the tracked character of a referred account reached a level: record the milestones, pay the referrer
function Ref.checkMilestones(player)
	local link = linkOf(player:getAccountId())
	if not link or link.status ~= "active" or link.player_id ~= player:getGuid() then
		return
	end
	local reached = {}
	for _, r in ipairs(Chaos.select(string.format("SELECT `milestone` FROM `%s` WHERE `referred_account_id` = %d", T.rewards, link.referred_account_id),
			{{"milestone", "s"}})) do
		reached[r.milestone] = true
	end
	local due = Core.due(player:getLevel(), reached, cfg)
	if #due == 0 then
		return
	end
	local now = os.time()
	for _, m in ipairs(due) do
		db.query(string.format("INSERT IGNORE INTO `%s` (`referred_account_id`, `milestone`, `referrer_account_id`, `player_id`, `reached_at`, `state`) " ..
			"VALUES (%d, %s, %d, %d, %d, 'due')", T.rewards, link.referred_account_id, q(m.key), link.referrer_account_id, player:getGuid(), now))
		log(link.referrer_account_id, link.referred_account_id, player:getGuid(), "reached", m.key)
	end
	local _, waiting = Ref.processRewards(link.referrer_account_id)
	for _, w in ipairs(waiting or {}) do
		local m = Core.milestone(cfg, w.milestone)
		if m and w.referred_account_id == link.referred_account_id then
			for _, p in ipairs(onlineOf(link.referrer_account_id)) do
				p:sendTextMessage(MESSAGE_STATUS_CONSOLE_BLUE, say("waitingCap", player:getName(), m.level))
			end
		end
	end
end

-- ------------------------------------------------------------------ protocol
local ACTIONS = {
	open = {500, function(player) sendStatus(player, true) end},
	sync = {500, function(player) sendStatus(player, false) end},
	enter = {2000, function(player, data) Ref.enter(player, data.code) end}
}

local ext = CreatureEvent("ChaosReferralExtended")
function ext.onExtendedOpcode(player, opcode, buffer)
	if opcode ~= OPCODE then
		return
	end
	local msg = Chaos.decode(buffer)
	local a = msg and ACTIONS[msg.action]
	if not a then
		return
	end
	if ChaosRateLimit and not ChaosRateLimit.allow(player, "referral." .. msg.action, a[1]) then
		return
	end
	local ok, err = pcall(a[2], player, type(msg.data) == "table" and msg.data or {})
	if not ok then
		print("[Chaos referral] " .. tostring(msg.action) .. " failed: " .. tostring(err))
	end
end
ext:type("extendedopcode")
ext:register()

local advance = CreatureEvent("ChaosReferralAdvance")
function advance.onAdvance(player, skill, oldLevel, newLevel)
	if skill == SKILL_LEVEL and cfg.enabled then
		local ok, err = pcall(Ref.checkMilestones, player)
		if not ok then
			print("[Chaos referral] advance: " .. tostring(err))
		end
	end
	return true
end
advance:type("advance")
advance:register()

-- ------------------------------------------------------------------ login
local login = CreatureEvent("ChaosReferralLogin")
function login.onLogin(player)
	Ref.ensureHooks()
	player:registerEvent("ChaosReferralExtended")
	local accountId = player:getAccountId()
	local ok, err = pcall(function()
		local link = linkOf(accountId)
		if cfg.enabled and link and link.status == "pending" then
			link = checkPending(player, link)
		end
		if link and link.status == "active" then
			if link.gift_at == 0 then
				giveGift(player, link)
			end
			if link.player_id == player:getGuid() then
				player:registerEvent("ChaosReferralAdvance")
				Ref.checkMilestones(player)
			end
		end
		Ref.processRewards(accountId)
		notify(accountId)
		Ref.load(accountId)
	end)
	if not ok then
		print("[Chaos referral] login: " .. tostring(err))
	end
	return true
end
login:register()

-- ------------------------------------------------------------------ startup: tables, rewards that waited
-- every referrer with a waiting reward: pay what may be paid now (a new month, a lifted ban)
function Ref.processAllDue(why)
	local n = 0
	for _, r in ipairs(Chaos.select(string.format("SELECT DISTINCT `referrer_account_id` FROM `%s` WHERE `state` = 'due'", T.rewards),
			{{"referrer_account_id", "n"}})) do
		n = n + (Ref.processRewards(r.referrer_account_id) or 0)
	end
	if n > 0 then
		print(string.format("[Chaos referral] %d waiting reward(s) paid (%s)", n, why))
	end
	return n
end

local startup = GlobalEvent("ChaosReferralStartup")
function startup.onStartup()
	for _, sql in ipairs(SCHEMA) do
		db.query(sql)
	end
	Ref.processAllDue("startup")
	Ref.ensureHooks()
	return true
end
startup:register()

local retry = GlobalEvent("ChaosReferralRetry")
function retry.onThink(interval)
	if cfg.enabled then
		local ok, err = pcall(Ref.processAllDue, "retry")
		if not ok then
			print("[Chaos referral] retry: " .. tostring(err))
		end
	end
	return true
end
retry:interval(math.max(1, cfg.retryMinutes or 30) * 60 * 1000)
retry:register()

-- ------------------------------------------------------------------ staff
local talk = TalkAction("/referral")
function talk.onSay(player, words, param)
	if not player:getGroup():getAccess() then
		return true
	end
	local name, action = param:match("^%s*([^,]+)%s*,?%s*(%a*)")
	local guid = name and Chaos.findPlayer(name:gsub("%s+$", ""))
	if not guid then
		player:sendCancelMessage("Usage: /referral <player>[, unlink]")
		return false
	end
	local accountId = Chaos.select(string.format("SELECT `account_id` FROM `players` WHERE `id` = %d", guid), {{"account_id", "n"}})[1].account_id
	if action == "unlink" then
		db.query(string.format("DELETE FROM `%s` WHERE `referred_account_id` = %d", T.links, accountId))
		db.query(string.format("DELETE FROM `%s` WHERE `referred_account_id` = %d AND `state` <> 'paid'", T.rewards, accountId))
		log(accountId, 0, guid, "unlink", "by " .. player:getName())
		refreshAccount(accountId)
		player:sendTextMessage(MESSAGE_INFO_DESCR, "Referral link of account " .. accountId .. " removed.")
		return false
	end
	local link = linkOf(accountId)
	local lines = {string.format("Account %d: code %s.", accountId, codeOfAccount(accountId) or "-")}
	if link then
		lines[#lines + 1] = string.format("Referred by account %d (%s), %s via %s%s, tracked character %d, gift %s.", link.referrer_account_id,
			link.code, link.status, link.source, link.reason ~= "" and (" (" .. link.reason .. ")") or "", link.player_id,
			link.gift_at > 0 and os.date("%Y-%m-%d %H:%M", link.gift_at) or "not yet")
	end
	local friends = Chaos.select(string.format("SELECT COUNT(*) AS `n` FROM `%s` WHERE `referrer_account_id` = %d AND `status` = 'active'", T.links, accountId), {{"n", "n"}})[1]
	lines[#lines + 1] = string.format("Referred friends: %d; links this month %d, rewards paid this month %d.", friends and friends.n or 0,
		linksThisMonth(accountId, os.time()), paidThisMonth(accountId, os.time()))
	player:showTextDialog(2160, table.concat(lines, "\n"))
	return false
end
talk:separator(" ")
talk:register()

-- a /reload rebuilds titles.lua's table after this file: put the hook back once all are loaded
addEvent(function()
	Ref.ensureHooks()
end, 0)
