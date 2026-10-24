-- Creator codes: the creator's share of a supporter's donation, paid in Chaos Coins in game
-- (creator_codes_config.lua, creator_codes_core.lua; website plugins/chaos/creator_lib.php, pages/creator.php).
--
-- The website keeps the codes (an administrator creates them) and the donor's pick (chaos_creator_support: the code an
-- account chose, until when). This file, every cfg.pollSeconds and at startup:
--   1. matches: every credited donation (chaos_coin_orders status 'credited') of an account whose pick covers the
--      donation's creation time gets one chaos_creator_uses row (the order id is the key: once per donation), with the
--      share C.share(the pack's coins, the code's %). A row the website wrote at order time (the donate page's hook,
--      share 0 until credited) gets its share here.
--   2. settles: each pending / waiting row is decided by ChaosCreatorCore.decide (own account, same IP or /64, same
--      payer, refund / chargeback, code off: void; within holdDays, creator banned, over the month's cap: wait) and a
--      due share is added to the creator's account (chaos_shop_coins, the store's balance table; nothing of the store is
--      edited). The creator is told in game. Every step goes to chaos_creator_log.
-- Gods: /creatorcodes status | run   (inspect, or run a round now). See server/README.md "Creator codes".
-- Lua 5.1 / LuaJIT compatible.

if not (Chaos and Chaos.t) then
	if not Chaos then
		dofile("data/scripts/chaos/chaos_constants.lua")
	end
	dofile("data/scripts/chaos/i18n_core.lua")
end
if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
dofile("data/scripts/chaos/creator_codes_core.lua")
Chaos.creatorCodesConfig = dofile("data/scripts/chaos/creator_codes_config.lua")

ChaosCreatorCodes = ChaosCreatorCodes or {}
local CC = ChaosCreatorCodes
local Core = ChaosCreatorCore
local cfg = Chaos.creatorCodesConfig
local T = cfg.tables
local COINS = (Chaos.tables and Chaos.tables.shopCoins) or "chaos_shop_coins"

local function q(text)
	return db.escapeString(tostring(text or ""))
end

local SCHEMA = {
	[[CREATE TABLE IF NOT EXISTS `chaos_creator_codes` (`id` int(11) NOT NULL AUTO_INCREMENT, `code` varchar(16) NOT NULL,
	`account_id` int(11) NOT NULL, `display_name` varchar(64) NOT NULL DEFAULT '', `pct` tinyint(3) unsigned NOT NULL DEFAULT 0,
	`active` tinyint(1) NOT NULL DEFAULT 1, `note` varchar(255) NOT NULL DEFAULT '', `created_at` int(10) unsigned NOT NULL DEFAULT 0,
	`created_by` varchar(64) NOT NULL DEFAULT '', PRIMARY KEY (`id`), UNIQUE KEY `chaos_creator_codes_code` (`code`),
	KEY `chaos_creator_codes_account` (`account_id`)) ENGINE=InnoDB DEFAULT CHARSET=utf8]],
	[[CREATE TABLE IF NOT EXISTS `chaos_creator_support` (`account_id` int(11) NOT NULL, `code_id` int(11) NOT NULL,
	`set_at` int(10) unsigned NOT NULL, `expires_at` int(10) unsigned NOT NULL, `ip` varchar(64) NOT NULL DEFAULT '',
	PRIMARY KEY (`account_id`), KEY `chaos_creator_support_code` (`code_id`)) ENGINE=InnoDB DEFAULT CHARSET=utf8]],
	[[CREATE TABLE IF NOT EXISTS `chaos_creator_uses` (`order_id` int(11) NOT NULL, `code_id` int(11) NOT NULL,
	`creator_account_id` int(11) NOT NULL, `buyer_account_id` int(11) NOT NULL, `coins_base` int(11) NOT NULL DEFAULT 0,
	`share` int(11) NOT NULL DEFAULT 0, `state` varchar(8) NOT NULL DEFAULT 'pending', `reason` varchar(16) NOT NULL DEFAULT '',
	`created_at` int(10) unsigned NOT NULL DEFAULT 0, `credited_at` int(10) unsigned NOT NULL DEFAULT 0,
	`settled_at` int(10) unsigned NOT NULL DEFAULT 0, PRIMARY KEY (`order_id`), KEY `chaos_creator_uses_code` (`code_id`, `state`),
	KEY `chaos_creator_uses_creator` (`creator_account_id`, `state`, `settled_at`)) ENGINE=InnoDB DEFAULT CHARSET=utf8]],
	[[CREATE TABLE IF NOT EXISTS `chaos_creator_log` (`id` int(11) NOT NULL AUTO_INCREMENT, `at` int(10) unsigned NOT NULL,
	`code_id` int(11) NOT NULL DEFAULT 0, `account_id` int(11) NOT NULL DEFAULT 0, `order_id` int(11) NOT NULL DEFAULT 0,
	`action` varchar(16) NOT NULL, `detail` varchar(255) NOT NULL DEFAULT '', PRIMARY KEY (`id`), KEY `chaos_creator_log_code` (`code_id`))
	ENGINE=InnoDB DEFAULT CHARSET=utf8]],
	[[CREATE TABLE IF NOT EXISTS `chaos_pay_payers` (`order_id` int(11) NOT NULL, `account_id` int(11) NOT NULL,
	`payer_hash` char(64) NOT NULL, `created_at` int(10) unsigned NOT NULL DEFAULT 0, PRIMARY KEY (`order_id`),
	KEY `chaos_pay_payers_account` (`account_id`), KEY `chaos_pay_payers_hash` (`payer_hash`)) ENGINE=InnoDB DEFAULT CHARSET=utf8]]
}

local function log(codeId, accountId, orderId, action, detail)
	db.asyncQuery(string.format("INSERT INTO `%s` (`at`, `code_id`, `account_id`, `order_id`, `action`, `detail`) VALUES (%d, %d, %d, %d, %s, %s)",
		T.log, os.time(), codeId or 0, accountId or 0, orderId or 0, q(action), q(tostring(detail or ""):sub(1, 255))))
end

local function monthStart(t)
	local d = os.date("*t", t)
	return os.time({year = d.year, month = d.month, day = 1, hour = 0, min = 0, sec = 0})
end

-- ---------------------------------------------------------------- facts
local function ipString(n)
	n = tonumber(n)
	if not n or n <= 0 then
		return nil
	end
	n = math.floor(n)
	return string.format("%d.%d.%d.%d", n % 256, math.floor(n / 256) % 256, math.floor(n / 65536) % 256, math.floor(n / 16777216) % 256)
end

-- login IPs of every character of the account, the IPs of its characters online and the IP of its website pick
local function ipsOf(accountId)
	local ips = {}
	for _, r in ipairs(Chaos.select(string.format("SELECT DISTINCT `lastip` FROM `players` WHERE `account_id` = %d AND `lastip` <> 0",
			accountId), {{"lastip", "n"}})) do
		ips[#ips + 1] = ipString(r.lastip)
	end
	for _, p in ipairs(Game.getPlayers()) do
		if p:getAccountId() == accountId then
			ips[#ips + 1] = ipString(p:getIp())
		end
	end
	local s = Chaos.select(string.format("SELECT `ip` FROM `%s` WHERE `account_id` = %d", T.support, accountId), {{"ip", "s"}})[1]
	if s and s.ip ~= "" then
		ips[#ips + 1] = s.ip
	end
	return ips
end

local payersChecked, hasPayers = false, false
local function payersOf(accountId)
	if not payersChecked then
		payersChecked = true
		hasPayers = #Chaos.select("SELECT `table_name` AS `t` FROM `information_schema`.`tables` WHERE `table_schema` = DATABASE() " ..
			"AND `table_name` = " .. q(T.payers), {{"t", "s"}}) > 0
	end
	local out = {}
	if hasPayers then
		for _, r in ipairs(Chaos.select(string.format("SELECT DISTINCT `payer_hash` FROM `%s` WHERE `account_id` = %d", T.payers,
				accountId), {{"payer_hash", "s"}})) do
			out[#out + 1] = r.payer_hash
		end
	end
	return out
end

local function isBanned(accountId)
	return #Chaos.select(string.format("SELECT `account_id` FROM `account_bans` WHERE `account_id` = %d AND (`expires_at` <= 0 OR `expires_at` > %d)",
		accountId, os.time()), {{"account_id", "n"}}) > 0
end

local function paidThisMonth(creatorId, now)
	local r = Chaos.select(string.format("SELECT SUM(`share`) AS `s` FROM `%s` WHERE `creator_account_id` = %d AND `state` = 'paid' AND `settled_at` >= %d",
		T.uses, creatorId, monthStart(now)), {{"s", "n"}})[1]
	return r and r.s or 0
end

local function codeRow(codeId)
	return Chaos.select(string.format("SELECT `id`, `code`, `account_id`, `pct`, `active` FROM `%s` WHERE `id` = %d", T.codes, codeId),
		{{"id", "n"}, {"code", "s"}, {"account_id", "n"}, {"pct", "n"}, {"active", "n"}})[1]
end

-- ---------------------------------------------------------------- 1. match credited donations to picks
function CC.match()
	local rows = Chaos.select(string.format("SELECT o.`id`, o.`account_id`, o.`coins`, o.`created`, o.`credited`, s.`code_id`, s.`set_at`, s.`expires_at` " ..
		"FROM `chaos_coin_orders` o JOIN `%s` s ON s.`account_id` = o.`account_id` LEFT JOIN `%s` u ON u.`order_id` = o.`id` " ..
		"WHERE o.`status` = 'credited' AND u.`order_id` IS NULL AND o.`created` >= s.`set_at` AND o.`created` <= s.`expires_at` LIMIT 200",
		T.support, T.uses), {{"id", "n"}, {"account_id", "n"}, {"coins", "n"}, {"created", "n"}, {"credited", "n"}, {"code_id", "n"},
		{"set_at", "n"}, {"expires_at", "n"}})
	local n = 0
	for _, o in ipairs(rows) do
		local code = codeRow(o.code_id)
		if code then
			local share = Core.share(o.coins, Core.pctOf(code, cfg), cfg)
			db.query(string.format("INSERT IGNORE INTO `%s` (`order_id`, `code_id`, `creator_account_id`, `buyer_account_id`, `coins_base`, `share`, " ..
				"`state`, `created_at`, `credited_at`) VALUES (%d, %d, %d, %d, %d, %d, 'pending', %d, %d)", T.uses, o.id, code.id, code.account_id,
				o.account_id, o.coins, share, os.time(), o.credited))
			log(code.id, o.account_id, o.id, "match", string.format("%s: %d coins -> share %d", code.code, o.coins, share))
			n = n + 1
		end
	end
	return n
end

-- ---------------------------------------------------------------- 2. settle
local function tell(accountId, text)
	for _, p in ipairs(Game.getPlayers()) do
		if p:getAccountId() == accountId then
			p:sendTextMessage(MESSAGE_EVENT_ADVANCE, text)
		end
	end
end

function CC.settle()
	local now = os.time()
	local rows = Chaos.select(string.format("SELECT u.`order_id`, u.`code_id`, u.`creator_account_id`, u.`buyer_account_id`, u.`share`, " ..
		"u.`coins_base`, u.`state`, u.`reason`, o.`status`, o.`coins`, o.`credited`, p.`reversal` FROM `%s` u " ..
		"JOIN `chaos_coin_orders` o ON o.`id` = u.`order_id` LEFT JOIN `chaos_coin_payments` p ON p.`order_id` = u.`order_id` " ..
		"WHERE u.`state` IN ('pending', 'wait') ORDER BY u.`order_id` LIMIT 200", T.uses),
		{{"order_id", "n"}, {"code_id", "n"}, {"creator_account_id", "n"}, {"buyer_account_id", "n"}, {"share", "n"}, {"coins_base", "n"},
		{"state", "s"}, {"reason", "s"}, {"status", "s"}, {"coins", "n"}, {"credited", "n"}, {"reversal", "s"}})
	local paid = 0
	for _, u in ipairs(rows) do
		local open = u.status == "pending" or u.status == "open" or u.status == "paid"
		if not open then -- credited, or ended without coins (expired, cancelled, failed, refunded)
			local code = codeRow(u.code_id)
			local share = u.share
			if share <= 0 and u.coins_base <= 0 and u.status == "credited" and code then -- a row of the donate page's hook
				share = Core.share(u.coins, Core.pctOf(code, cfg), cfg)
				db.query(string.format("UPDATE `%s` SET `share` = %d, `coins_base` = %d, `credited_at` = %d WHERE `order_id` = %d",
					T.uses, share, u.coins, u.credited, u.order_id))
			end
			local facts = {codeExists = code ~= nil, codeActive = code and code.active == 1,
				reversed = u.status ~= "credited" or (u.reversal or "") ~= ""}
			if code and not facts.reversed and u.buyer_account_id ~= u.creator_account_id then
				facts.buyerIps, facts.creatorIps = ipsOf(u.buyer_account_id), ipsOf(u.creator_account_id)
				facts.buyerPayers, facts.creatorPayers = payersOf(u.buyer_account_id), payersOf(u.creator_account_id)
				facts.creatorBanned = isBanned(u.creator_account_id)
				facts.paidThisMonth = paidThisMonth(u.creator_account_id, now)
			end
			local state, reason, amount = Core.decide({buyer = u.buyer_account_id, creator = u.creator_account_id, share = share,
				credited = u.credited}, facts, cfg, now)
			if state == "pay" then
				db.query(string.format("UPDATE `%s` SET `state` = 'paid', `reason` = '', `settled_at` = %d WHERE `order_id` = %d AND `state` IN ('pending', 'wait')",
					T.uses, now, u.order_id))
				db.query(string.format("INSERT INTO `%s` (`account_id`, `coins`) VALUES (%d, %d) ON DUPLICATE KEY UPDATE `coins` = `coins` + %d",
					COINS, u.creator_account_id, amount, amount))
				log(u.code_id, u.creator_account_id, u.order_id, "paid", string.format("%d coins (donor account %d)", amount, u.buyer_account_id))
				tell(u.creator_account_id, string.format(cfg.messages.paid, code.code, amount))
				paid = paid + 1
			elseif state == "void" then
				db.query(string.format("UPDATE `%s` SET `state` = 'void', `reason` = %s, `settled_at` = %d WHERE `order_id` = %d AND `state` IN ('pending', 'wait')",
					T.uses, q(reason), now, u.order_id))
				log(u.code_id, u.buyer_account_id, u.order_id, "void", tostring(cfg.messages[reason] or reason))
			elseif u.state ~= "wait" or u.reason ~= reason then
				db.query(string.format("UPDATE `%s` SET `state` = 'wait', `reason` = %s WHERE `order_id` = %d AND `state` IN ('pending', 'wait')",
					T.uses, q(reason), u.order_id))
			end
		end
	end
	return paid
end

function CC.round(why)
	if not cfg.enabled then
		return 0, 0
	end
	local matched = CC.match()
	local paid = CC.settle()
	if matched > 0 or paid > 0 then
		print(string.format("[Chaos creator codes] %s: %d donation(s) matched, %d share(s) paid", why or "round", matched, paid))
	end
	return matched, paid
end

local startup = GlobalEvent("ChaosCreatorCodesStartup")
function startup.onStartup()
	for _, sql in ipairs(SCHEMA) do
		db.query(sql)
	end
	local ok, err = pcall(CC.round, "startup")
	if not ok then
		print("[Chaos creator codes] startup: " .. tostring(err))
	end
	return true
end
startup:register()

local poll = GlobalEvent("ChaosCreatorCodesPoll")
function poll.onThink(interval)
	local ok, err = pcall(CC.round, "poll")
	if not ok then
		print("[Chaos creator codes] poll: " .. tostring(err))
	end
	return true
end
poll:interval(math.max(30, cfg.pollSeconds or 300) * 1000)
poll:register()

local talk = TalkAction("/creatorcodes")
function talk.onSay(player, words, param)
	if not player:getGroup():getAccess() or player:getGroup():getId() < (cfg.adminGroup or 5) then
		return true
	end
	param = (param or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
	if param == "run" then
		local m, p = CC.round("by " .. player:getName())
		player:sendTextMessage(MESSAGE_INFO_DESCR, Chaos.t(player, "Creator codes: %d matched, %d paid.", m, p))
		return false
	end
	local lines = {string.format("Creator codes: %s, %d%% of the coins, hold %d days, caps %d / donation, %d / month.",
		cfg.enabled and "on" or "off", cfg.sharePct, cfg.holdDays, cfg.orderCap, cfg.monthlyCap)}
	for _, r in ipairs(Chaos.select(string.format("SELECT c.`code`, c.`active`, " ..
			"(SELECT COUNT(*) FROM `%s` u WHERE u.`code_id` = c.`id` AND u.`state` = 'paid') AS `n`, " ..
			"(SELECT COALESCE(SUM(u.`share`), 0) FROM `%s` u WHERE u.`code_id` = c.`id` AND u.`state` = 'paid') AS `s` FROM `%s` c ORDER BY c.`code` LIMIT 40",
			T.uses, T.uses, T.codes), {{"code", "s"}, {"active", "n"}, {"n", "n"}, {"s", "n"}})) do
		lines[#lines + 1] = string.format("%s%s: %d paid share(s), %d coins", r.code, r.active == 1 and "" or " (off)", r.n, r.s)
	end
	player:showTextDialog(2160, table.concat(lines, "\n"))
	return false
end
talk:separator(" ")
talk:register()
