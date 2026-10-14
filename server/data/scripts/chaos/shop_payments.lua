-- Donations from the client store (game_shop "Donate" window): Pix (BRL) and PayPal (USD).
-- Rules in shop_payments_core.lua, numbers in shop_coins_config.lua (`payments`, the packs' usdCents).
--
-- The game server has no HTTPS client, so it never talks to a payment provider. It writes the order; the website's
-- payment worker (website/overlay/plugins/chaos/pay/worker.php, a systemd service) creates the charge and stores the
-- Pix code / PayPal approval link on the row; the provider's webhook (chaos_pay_webhook.php) marks the order 'paid' after
-- re-fetching the payment; shop.lua's crediting step credits it and calls ChaosShopPay.onCredited, which tells the
-- player at once (toast + balance). Refunds and chargebacks after crediting are flagged on the row by the website and
-- handled here (coins still unspent are taken back when payments.removeCoinsOnReversal is on), listed in the admin
-- panel (Store > Donations: refunds).
--
-- client -> server, extended opcode ChaosOpcodes.shop (218, shared with shop.lua; each script ignores the other's actions)
--   pay_packs                      -> "pay_packs" {notice, noticePt, thanks, terms, termsPt, methods, packs, firstBonusPct,
--                                     firstBonusMax, open?}
--   pay_create {pack, method}      -> "pay_order" (the order view) or "pay_error" {msg, order?}
--   pay_status {id}                -> "pay_order"
--   pay_cancel {id}                -> "pay_order"
-- server -> client "pay_paid" {id, coins, name, text, textPt, terms, termsPt} (+ status) when an order of the account is credited;
--   "pay_reversal" {id, coins, text} (+ status) when coins of a refunded / charged back donation were taken back.
-- Tables: chaos_coin_orders (shop.lua) and chaos_coin_payments (one row per order of this flow, server/sql/chaos.sql).

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
dofile("data/scripts/chaos/shop_core.lua")
dofile("data/scripts/chaos/shop_payments_core.lua")

local coinsCfg = ChaosShopCoinsConfig or dofile("data/scripts/chaos/shop_coins_config.lua")
local P, K = ChaosPayCore, ChaosShopCore
local OPCODE = ChaosOpcodes.shop
local T_ORDERS, T_PAY, T_COINS = Chaos.tables.coinOrders, Chaos.tables.coinPayments, Chaos.tables.shopCoins
local T_COIN_GIFTS = Chaos.tables.coinGifts or "chaos_coin_gifts"
local PC = coinsCfg.payments or {}

ChaosShopPay = ChaosShopPay or {}
local Pay = ChaosShopPay

local function log(text)
	print("[Chaos donations] " .. text)
end

db.query([[CREATE TABLE IF NOT EXISTS `chaos_coin_payments` (
  `order_id` int(11) NOT NULL, `method` varchar(16) NOT NULL, `token` varchar(64) NOT NULL,
  `amount_cents` int(11) NOT NULL, `currency` char(3) NOT NULL, `source` varchar(8) NOT NULL DEFAULT 'client',
  `psp` varchar(16) NOT NULL DEFAULT '', `psp_id` varchar(128) NOT NULL DEFAULT '', `psp_ref` varchar(128) NOT NULL DEFAULT '',
  `psp_status` varchar(32) NOT NULL DEFAULT '', `qr_code` varchar(1024) NOT NULL DEFAULT '',
  `pay_url` varchar(1024) NOT NULL DEFAULT '', `qr_image` mediumtext NULL, `expires` int(10) unsigned NOT NULL DEFAULT 0,
  `attempts` int(11) NOT NULL DEFAULT 0, `claimed` int(10) unsigned NOT NULL DEFAULT 0,
  `checked` int(10) unsigned NOT NULL DEFAULT 0, `cancel_sent` tinyint(1) NOT NULL DEFAULT 0,
  `paid_at` int(10) unsigned NOT NULL DEFAULT 0, `reversal` varchar(16) NOT NULL DEFAULT '',
  `reversal_cents` int(11) NOT NULL DEFAULT 0, `reversal_done` tinyint(1) NOT NULL DEFAULT 0,
  `reversal_coins` int(11) NOT NULL DEFAULT 0, `reversal_at` int(10) unsigned NOT NULL DEFAULT 0,
  `note` varchar(255) NOT NULL DEFAULT '', `updated` int(10) unsigned NOT NULL DEFAULT 0,
  PRIMARY KEY (`order_id`), UNIQUE KEY `chaos_coin_payments_token` (`token`),
  KEY `chaos_coin_payments_psp` (`psp`, `psp_id`), KEY `chaos_coin_payments_ref` (`psp`, `psp_ref`),
  KEY `chaos_coin_payments_reversal` (`reversal_done`, `reversal`)) ENGINE=InnoDB DEFAULT CHARSET=utf8]])

local PACKS, STARTERS = {}, {}
for _, pack in ipairs(coinsCfg.packs or {}) do
	PACKS[pack.key] = pack
	if pack.starter then
		STARTERS[#STARTERS + 1] = db.escapeString(pack.key)
	end
end
local METHOD_SQL = {}
for _, m in ipairs(P.ORDER) do
	METHOD_SQL[#METHOD_SQL + 1] = db.escapeString(m)
end
METHOD_SQL = table.concat(METHOD_SQL, ",")

local function now()
	return os.time()
end

local function status(accountId)
	local shopCfg = ChaosShopConfig or {}
	return {points = ChaosShop and ChaosShop.getCoins(accountId) or 0, buyUrl = shopCfg.buyUrl or "", ad = {}}
end

local function send(player, action, data, withStatus)
	local payload = {action = action, data = data}
	if withStatus then
		payload.status = status(player:getAccountId())
	end
	player:sendExtendedOpcode(OPCODE, json.encode(payload))
end

-- ------------------------------------------------------------------ account state
local function countOrders(accountId, where)
	local rows = Chaos.select("SELECT COUNT(*) AS `n` FROM `" .. T_ORDERS .. "` WHERE `account_id` = " .. accountId ..
		" AND `status` IN ('paid', 'credited') AND " .. where, {{"n", "n"}})
	return rows[1] and rows[1].n or 0
end

local function starterCredited(accountId)
	return #STARTERS > 0 and countOrders(accountId, "`pack_key` IN (" .. table.concat(STARTERS, ",") .. ")") > 0
end

local function firstOpen(accountId)
	return countOrders(accountId, #STARTERS > 0 and ("`pack_key` NOT IN (" .. table.concat(STARTERS, ",") .. ")") or "1") == 0
end

local ORDER_COLS = {{"id", "n"}, {"status", "s"}, {"pack_key", "s"}, {"created", "n"}, {"coins", "n"}, {"bonus", "n"},
	{"first_bonus", "n"}, {"method", "s"}, {"amount_cents", "n"}, {"currency", "s"}, {"qr_code", "s"}, {"pay_url", "s"},
	{"expires", "n"}}
local ORDER_SELECT = "SELECT o.`id`, o.`status`, o.`pack_key`, o.`created`, o.`coins`, o.`bonus`, o.`first_bonus`, p.`method`, " ..
	"p.`amount_cents`, p.`currency`, p.`qr_code`, p.`pay_url`, p.`expires` FROM `" .. T_ORDERS .. "` o JOIN `" .. T_PAY ..
	"` p ON p.`order_id` = o.`id` WHERE o.`account_id` = "

local function recentOrders(accountId)
	return Chaos.select(ORDER_SELECT .. accountId .. " AND o.`created` > " .. (now() - 86400) .. " ORDER BY o.`id` DESC LIMIT 50", ORDER_COLS)
end

local function orderOf(accountId, id)
	return Chaos.select(ORDER_SELECT .. accountId .. " AND o.`id` = " .. id, ORDER_COLS)[1]
end

local function viewOf(o)
	return P.view(o, PACKS[o.pack_key], now(), coinsCfg)
end

-- ------------------------------------------------------------------ actions
local function packsView(player)
	local acc = player:getAccountId()
	local starterDone, first = starterCredited(acc), firstOpen(acc)
	local packs = {}
	for _, pack in ipairs(coinsCfg.packs or {}) do
		local credit = K.packCredit(pack, first, coinsCfg)
		local prices = {}
		for _, m in ipairs(P.methods(coinsCfg)) do
			local cents = P.priceCents(pack, m.key, coinsCfg)
			if cents then
				prices[m.key] = {cents = cents, text = P.money(cents, m.currency)}
			end
		end
		packs[#packs + 1] = {key = pack.key, name = pack.name or pack.key, coins = credit.coins, bonus = credit.bonus,
			firstBonus = credit.firstBonus, total = credit.total, once = pack.once or false,
			available = not (pack.once and starterDone), prices = prices}
	end
	local open
	for _, o in ipairs(recentOrders(acc)) do
		if P.isOpen(o, now()) then
			open = viewOf(o)
			break
		end
	end
	local terms, termsPt = P.terms()
	return {notice = P.NOTICE_EN, noticePt = P.NOTICE_PT, thanks = P.THANKS, terms = terms, termsPt = termsPt, methods = P.methods(coinsCfg), packs = packs,
		firstBonusPct = (coinsCfg.firstPurchase or {}).bonusPct or 0, firstBonusMax = (coinsCfg.firstPurchase or {}).maxBonus,
		firstOpen = first, open = open}
end

-- a creator code sent with the donation (the client's donate tab): the same pick as the website's Donate page
-- (creator_lib.php chaos_creator_set_support): chaos_creator_support for supportDays. Returns an error text or nil.
local function pickCreator(player, text)
	local cc = Chaos.creatorCodesConfig
	if not cc then
		local ok, c = pcall(dofile, "data/scripts/chaos/creator_codes_config.lua")
		cc = ok and type(c) == "table" and c or nil
	end
	if not cc or cc.enabled == false then
		return "Creator codes are not available right now."
	end
	local code = P.creatorCode(text)
	local T = cc.tables
	local row = code and Chaos.select(string.format("SELECT `id`, `account_id`, `active`, `code`, `display_name` FROM `%s` WHERE `code` = %s",
		T.codes, db.escapeString(code)), {{"id", "n"}, {"account_id", "n"}, {"active", "n"}, {"code", "s"}, {"display_name", "s"}})[1]
	local acc = player:getAccountId()
	local why = P.creatorRefusal(row, acc)
	if why then
		return why
	end
	db.query(string.format("DELETE FROM `%s` WHERE `account_id` = %d", T.support, acc))
	db.query(string.format("INSERT INTO `%s` (`account_id`, `code_id`, `set_at`, `expires_at`, `ip`) VALUES (%d, %d, %d, %d, %s)",
		T.support, acc, row.id, now(), now() + (cc.supportDays or 30) * 86400, db.escapeString(Game.convertIpToString and
		Game.convertIpToString(player:getIp()) or "")))
	db.query(string.format("INSERT INTO `%s` (`at`, `code_id`, `account_id`, `order_id`, `action`, `detail`) VALUES (%d, %d, %d, 0, 'pick', %s)",
		T.log, now(), row.id, acc, db.escapeString(row.code .. " (client)")))
	return nil
end

local function create(player, data)
	local acc = player:getAccountId()
	if type(data.creator) == "string" and data.creator ~= "" then
		local why = pickCreator(player, data.creator:sub(1, 32))
		if why then
			send(player, "pay_error", {msg = why})
			return
		end
	end
	local pack = PACKS[tostring(data.pack or "")]
	local method = tostring(data.method or "")
	local d = P.decide({coinsCfg = coinsCfg, pack = pack, method = method, now = now(), orders = recentOrders(acc),
		starterCredited = starterCredited(acc)})
	if d.action == "refuse" then
		send(player, "pay_error", {msg = d.reason, order = d.order and viewOf(d.order) or nil})
		return
	elseif d.action == "reuse" then
		send(player, "pay_order", viewOf(d.order))
		return
	end
	local credit = K.packCredit(pack, firstOpen(acc), coinsCfg)
	local token = P.token(acc, now())
	local m = (PC.methods or {})[method]
	local ok = db.query("INSERT INTO `" .. T_ORDERS .. "` (`account_id`, `pack_key`, `provider`, `provider_ref`, `status`, `coins`, " ..
		"`bonus`, `first_bonus`, `note`, `created`) VALUES (" .. acc .. ", " .. db.escapeString(pack.key) .. ", " ..
		db.escapeString(method) .. ", " .. db.escapeString(token) .. ", 'pending', " .. credit.coins .. ", " .. credit.bonus .. ", " ..
		credit.firstBonus .. ", 'donation', " .. now() .. ")")
	local row = ok and Chaos.select("SELECT `id` FROM `" .. T_ORDERS .. "` WHERE `provider` = " .. db.escapeString(method) ..
		" AND `provider_ref` = " .. db.escapeString(token), {{"id", "n"}})[1]
	if not row then
		send(player, "pay_error", {msg = "Could not start the donation. Please try again."})
		return
	end
	db.query("INSERT INTO `" .. T_PAY .. "` (`order_id`, `method`, `token`, `amount_cents`, `currency`, `source`, `updated`) VALUES (" ..
		row.id .. ", " .. db.escapeString(method) .. ", " .. db.escapeString(token) .. ", " .. d.cents .. ", " ..
		db.escapeString(m.currency) .. ", 'client', " .. now() .. ")")
	log(string.format("order %d: account %d, %s, %s %d cents", row.id, acc, pack.key, method, d.cents))
	local o = orderOf(acc, row.id)
	send(player, "pay_order", o and viewOf(o) or {id = row.id, status = "pending"})
end

local function statusOf(player, data)
	local id = Chaos.toInt(data.id, 1)
	local o = id and orderOf(player:getAccountId(), id)
	if o then
		send(player, "pay_order", viewOf(o), o.status == "credited")
	end
end

local function cancel(player, data)
	local acc, id = player:getAccountId(), Chaos.toInt(data.id, 1)
	if not id then
		return
	end
	db.query("UPDATE `" .. T_ORDERS .. "` SET `status` = 'cancelled', `note` = 'cancelled by the player' WHERE `id` = " .. id ..
		" AND `account_id` = " .. acc .. " AND `status` IN ('pending', 'open')")
	statusOf(player, {id = id})
end

local ext = CreatureEvent("ChaosShopPayExtended")
function ext.onExtendedOpcode(player, opcode, buffer)
	if opcode ~= OPCODE then
		return
	end
	local msg = Chaos.decode(buffer)
	if not msg or type(msg.action) ~= "string" or msg.action:sub(1, 4) ~= "pay_" then
		return
	end
	local data = type(msg.data) == "table" and msg.data or {}
	local RL = ChaosRateLimit
	if msg.action == "pay_packs" then
		if not RL or RL.allow(player, "shop.pay.packs", 1000) then
			send(player, "pay_packs", packsView(player), true)
		end
	elseif msg.action == "pay_create" then
		if not RL or RL.allow(player, "shop.pay.create", 3000) then
			create(player, data)
		end
	elseif msg.action == "pay_status" then
		if not RL or RL.allow(player, "shop.pay.status", 1000) then
			statusOf(player, data)
		end
	elseif msg.action == "pay_cancel" then
		if not RL or RL.allow(player, "shop.pay.cancel", 1000) then
			cancel(player, data)
		end
	end
end
ext:type("extendedopcode")
ext:register()

local login = CreatureEvent("ChaosShopPayLogin")
function login.onLogin(player)
	player:registerEvent("ChaosShopPayExtended")
	return true
end
login:register()

-- ------------------------------------------------------------------ after crediting (called by shop.lua)
function Pay.onCredited(orderId, accountId, credit, pack)
	for _, p in ipairs(Game.getPlayers()) do
		if p:getAccountId() == accountId then
			local en, pt = P.thanks(credit.total)
			local terms, termsPt = P.terms("credited")
			send(p, "pay_paid", {id = orderId, coins = credit.total, name = pack and (pack.name or pack.key) or "", text = en, textPt = pt,
				terms = terms, termsPt = termsPt}, true)
		end
	end
end

-- ------------------------------------------------------------------ refunds and chargebacks after crediting
-- the reversal of an order, locked for this round (inside the transaction): a larger refund the website records meanwhile
-- waits for the COMMIT and is handled by the next round. Nil when the row was handled already.
function Pay.lockReversal(orderId)
	return Chaos.select("SELECT `reversal_cents`, `reversal_coins` FROM `" .. T_PAY .. "` WHERE `order_id` = " .. orderId ..
		" AND `reversal_done` = 0 FOR UPDATE", {{"reversal_cents", "n"}, {"reversal_coins", "n"}})[1]
end

function Pay.processReversals()
	local rows = Chaos.select("SELECT p.`order_id`, p.`reversal`, p.`reversal_cents`, p.`amount_cents`, p.`currency`, p.`method`, " ..
		"o.`account_id`, o.`pack_key`, o.`coins`, o.`bonus`, o.`first_bonus` FROM `" .. T_PAY .. "` p JOIN `" .. T_ORDERS ..
		"` o ON o.`id` = p.`order_id` WHERE p.`reversal_done` = 0 AND p.`reversal` <> '' AND o.`status` = 'credited' LIMIT 20",
		{{"order_id", "n"}, {"reversal", "s"}, {"reversal_cents", "n"}, {"amount_cents", "n"}, {"currency", "s"}, {"method", "s"},
		{"account_id", "n"}, {"pack_key", "s"}, {"coins", "n"}, {"bonus", "n"}, {"first_bonus", "n"}})
	for _, r in ipairs(rows) do
		local credited = r.coins + r.bonus + r.first_bonus
		db.query("START TRANSACTION")
		local cur = Pay.lockReversal(r.order_id)
		if not cur then
			db.query("COMMIT") -- handled meanwhile
		else
			r.reversal_cents = cur.reversal_cents
			local bal = Chaos.select("SELECT `coins` FROM `" .. T_COINS .. "` WHERE `account_id` = " .. r.account_id .. " FOR UPDATE", {{"coins", "n"}})[1]
			-- a second, larger refund: only what the earlier round did not take back (reversal_coins)
			local share = P.reversalRemaining(credited, r.amount_cents, r.reversal_cents, cur.reversal_coins, PC.removeCoinsOnReversal)
			local take = math.min(share, math.max(0, bal and bal.coins or 0))
			if take > 0 then
				db.query("UPDATE `" .. T_COINS .. "` SET `coins` = `coins` - " .. take .. " WHERE `account_id` = " .. r.account_id ..
					" AND `coins` >= " .. take)
			end
			-- what the donor's balance could not cover was gifted on: taken back from the receivers (newest gift first)
			local clawed, unpaid, receivers = 0, 0, {}
			if share > take then
				local gifts = Chaos.select("SELECT g.`id`, g.`to_account`, g.`amount`, g.`clawed`, COALESCE(c.`coins`, 0) AS `balance` FROM `" ..
					T_COIN_GIFTS .. "` g LEFT JOIN `" .. T_COINS .. "` c ON c.`account_id` = g.`to_account` WHERE g.`from_account` = " ..
					r.account_id .. " AND g.`order_id` >= " .. r.order_id .. " AND g.`clawed` < g.`amount` ORDER BY g.`id` DESC FOR UPDATE",
					{{"id", "n"}, {"to_account", "n"}, {"amount", "n"}, {"clawed", "n"}, {"balance", "n"}})
				local plan
				plan, unpaid = K.clawbackPlan(share - take, gifts)
				for _, c in ipairs(plan) do
					db.query("UPDATE `" .. T_COINS .. "` SET `coins` = `coins` - " .. c.take .. " WHERE `account_id` = " .. c.account ..
						" AND `coins` >= " .. c.take)
					db.query("UPDATE `" .. T_COIN_GIFTS .. "` SET `clawed` = `clawed` + " .. c.take .. " WHERE `id` = " .. c.id)
					clawed = clawed + c.take
					receivers[c.account] = (receivers[c.account] or 0) + c.take
				end
			end
			db.query("UPDATE `" .. T_PAY .. "` SET `reversal_done` = 1, `reversal_coins` = " .. (cur.reversal_coins + take + clawed) .. ", `updated` = " .. now() ..
				" WHERE `order_id` = " .. r.order_id .. " AND `reversal_done` = 0")
			db.query("COMMIT")
			log(string.format("order %d (%s, %s): %s of %s, %d of %d coins taken back (account %d)", r.order_id, r.pack_key, r.method,
				r.reversal, P.money(r.reversal_cents > 0 and r.reversal_cents or r.amount_cents, r.currency), take, credited, r.account_id))
			if clawed > 0 or unpaid > 0 then
				log(string.format("order %d: %d coins taken back from gift receivers, %d gifted coins could not be recovered (staff: see %s)",
					r.order_id, clawed, unpaid, T_COIN_GIFTS))
			end
			for _, p in ipairs(Game.getPlayers()) do
				local got = receivers[p:getAccountId()]
				if got then
					p:sendTextMessage(MESSAGE_EVENT_ADVANCE, string.format("%d gifted Chaos Coins were taken back: the donation that paid for them was refunded or charged back.", got))
				end
			end
			for _, p in ipairs(Game.getPlayers()) do
				if p:getAccountId() == r.account_id then
					send(p, "pay_reversal", {id = r.order_id, coins = take,
						text = string.format("Donation #%d was refunded or charged back: %d Chaos Coins were taken back.", r.order_id, take)}, true)
				end
			end
		end
	end
end

-- ------------------------------------------------------------------ poll: fast crediting, reversals, stale orders
function Pay.poll()
	if #Chaos.select("SELECT `id` FROM `" .. T_ORDERS .. "` WHERE `status` = 'paid' LIMIT 1", {{"id", "n"}}) > 0 and ChaosShop then
		ChaosShop.processOrders()
	end
	Pay.processReversals()
	-- no charge after 10 minutes: the payment worker is not running (it cancels a charge it makes for such an order)
	db.query("UPDATE `" .. T_ORDERS .. "` SET `status` = 'failed', `note` = 'no charge was made (payment worker not running?)' " ..
		"WHERE `status` = 'pending' AND `provider` IN (" .. METHOD_SQL .. ") AND `created` < " .. (now() - 600))
end

local poll = GlobalEvent("ChaosShopPayPoll")
function poll.onThink(interval)
	Pay.poll()
	return true
end
poll:interval((PC.pollSeconds or 3) * 1000)
poll:register()
