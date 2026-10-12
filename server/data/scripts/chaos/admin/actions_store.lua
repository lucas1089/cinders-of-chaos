-- Store category (the Chaos store, shop.lua): sales dashboard from chaos_shop_purchases, recent purchases, Chaos Coin
-- donations (chaos_coin_orders, the Pix / PayPal ones with chaos_coin_payments: list, refunds and chargebacks),
-- recording a donation by hand and giving coins.
ChaosAdminPending = ChaosAdminPending or {}
local function reg(def) def.category = "store"; def.id = "store." .. def.id; ChaosAdminPending[def.id] = def end

local function sel(q, cols)
	return Chaos.select(q, cols)
end

local function T(name)
	return Chaos.tables[name]
end

reg{id = "dashboard", name = "Sales dashboard", description = "Coins spent, purchases and gifts per day, per category and the top offers.",
	params = {{name = "days", label = "Days", type = "int", min = 1, max = 365, default = 7}},
	handler = function(actor, p)
		local days = p.days or 7
		local since = os.time() - days * 86400
		local from = " FROM `" .. T("shopPurchases") .. "` WHERE `created` >= " .. since
		local lines = {}
		local tot = sel("SELECT COUNT(*) AS `n`, COALESCE(SUM(`price`), 0) AS `c`, COALESCE(SUM(`list_price` - `price`), 0) AS `d`, " ..
			"COALESCE(SUM(`gift_player` > 0), 0) AS `g`, COUNT(DISTINCT `account_id`) AS `a`" .. from,
			{{"n", "n"}, {"c", "n"}, {"d", "n"}, {"g", "n"}, {"a", "n"}})[1] or {}
		lines[#lines + 1] = string.format("Last %d days: %d purchases, %d coins, %d gifts, %d buyers, %d coins of discounts.",
			days, tot.n or 0, tot.c or 0, tot.g or 0, tot.a or 0, tot.d or 0)
		lines[#lines + 1] = "-- per day"
		for _, r in ipairs(sel("SELECT FROM_UNIXTIME(`created`, '%Y-%m-%d') AS `day`, COUNT(*) AS `n`, SUM(`price`) AS `c`" .. from ..
			" GROUP BY `day` ORDER BY `day` DESC", {{"day", "s"}, {"n", "n"}, {"c", "n"}})) do
			lines[#lines + 1] = string.format("%s  %4d purchases  %7d coins", r.day, r.n, r.c)
		end
		lines[#lines + 1] = "-- per category"
		for _, r in ipairs(sel("SELECT `category`, COUNT(*) AS `n`, SUM(`price`) AS `c`" .. from ..
			" GROUP BY `category` ORDER BY `c` DESC", {{"category", "s"}, {"n", "n"}, {"c", "n"}})) do
			lines[#lines + 1] = string.format("%-16s %4d  %7d coins", r.category ~= "" and r.category or "-", r.n, r.c)
		end
		lines[#lines + 1] = "-- top offers"
		for _, r in ipairs(sel("SELECT `offer_key`, MAX(`title`) AS `t`, COUNT(*) AS `n`, SUM(`price`) AS `c`" .. from ..
			" GROUP BY `offer_key` ORDER BY `c` DESC LIMIT 10", {{"offer_key", "s"}, {"t", "s"}, {"n", "n"}, {"c", "n"}})) do
			lines[#lines + 1] = string.format("%-26s %4d  %7d coins  (%s)", r.t, r.n, r.c, r.offer_key)
		end
		return true, "Store sales", lines
	end}

reg{id = "recent", name = "Recent purchases", description = "The last purchases: time, character, level, offer, price, gift target.",
	params = {{name = "count", label = "Rows", type = "int", min = 1, max = 100, default = 25}},
	handler = function(actor, p)
		local lines = {}
		for _, r in ipairs(sel("SELECT `created`, `player_name`, `level`, `title`, `price`, `list_price`, `gift_player` FROM `" ..
			T("shopPurchases") .. "` ORDER BY `id` DESC LIMIT " .. (p.count or 25), {{"created", "n"}, {"player_name", "s"},
			{"level", "n"}, {"title", "s"}, {"price", "n"}, {"list_price", "n"}, {"gift_player", "n"}})) do
			lines[#lines + 1] = string.format("%s  %s (%d)  %s  %d%s%s", os.date("%m-%d %H:%M", r.created), r.player_name, r.level,
				r.title, r.price, r.list_price > r.price and (" (list " .. r.list_price .. ")") or "",
				r.gift_player > 0 and (" gift to #" .. r.gift_player) or "")
		end
		return true, #lines .. " purchases", lines
	end}

reg{id = "coin_orders", name = "Donations (coin orders)", description = "Chaos Coin donations (chaos_coin_orders): the last ones and the totals per status.",
	params = {{name = "count", label = "Rows", type = "int", min = 1, max = 100, default = 20}},
	handler = function(actor, p)
		local lines = {}
		for _, r in ipairs(sel("SELECT `status`, COUNT(*) AS `n`, SUM(`coins` + `bonus` + `first_bonus`) AS `c` FROM `" ..
			T("coinOrders") .. "` GROUP BY `status`", {{"status", "s"}, {"n", "n"}, {"c", "n"}})) do
			lines[#lines + 1] = string.format("%-9s %5d donations  %8d coins", r.status, r.n, r.c)
		end
		for _, r in ipairs(sel("SELECT `id`, `account_id`, `pack_key`, `provider`, `status`, `coins`, `bonus`, `first_bonus`, `note`, `created` FROM `" ..
			T("coinOrders") .. "` ORDER BY `id` DESC LIMIT " .. (p.count or 20), {{"id", "n"}, {"account_id", "n"}, {"pack_key", "s"},
			{"provider", "s"}, {"status", "s"}, {"coins", "n"}, {"bonus", "n"}, {"first_bonus", "n"}, {"note", "s"}, {"created", "n"}})) do
			lines[#lines + 1] = string.format("Donation #%d %s acc %d %s %s %s %d+%d+%d %s", r.id, os.date("%m-%d %H:%M", r.created), r.account_id,
				r.pack_key, r.provider, r.status, r.coins, r.bonus, r.first_bonus, r.note)
		end
		return true, "Donations", lines
	end}

-- Pix / PayPal donations (shop_payments.lua; the website's pay/ worker and webhook)
local function money(cents, currency)
	return ChaosPayCore and ChaosPayCore.money(cents, currency) or string.format("%.2f %s", cents / 100, currency)
end

reg{id = "pay_donations", name = "Donations: Pix / PayPal", description = "Donations made in the client or on the website: totals per method and currency, the last ones with their provider status.",
	params = {{name = "days", label = "Days", type = "int", min = 1, max = 365, default = 30}, {name = "count", label = "Rows", type = "int", min = 1, max = 100, default = 20}},
	handler = function(actor, p)
		local since = os.time() - (p.days or 30) * 86400
		local lines = {}
		for _, r in ipairs(sel("SELECT p.`method`, p.`currency`, o.`status`, COUNT(*) AS `n`, SUM(p.`amount_cents`) AS `c` FROM `" .. T("coinPayments") ..
			"` p JOIN `" .. T("coinOrders") .. "` o ON o.`id` = p.`order_id` WHERE o.`created` >= " .. since .. " GROUP BY p.`method`, p.`currency`, o.`status`",
			{{"method", "s"}, {"currency", "s"}, {"status", "s"}, {"n", "n"}, {"c", "n"}})) do
			lines[#lines + 1] = string.format("%-7s %-9s %4d donations  %s", r.method, r.status, r.n, money(r.c, r.currency))
		end
		lines[#lines + 1] = "-- last donations"
		for _, r in ipairs(sel("SELECT o.`id`, o.`created`, o.`account_id`, o.`pack_key`, o.`status`, p.`method`, p.`amount_cents`, p.`currency`, p.`psp`, " ..
			"p.`psp_status`, p.`source`, p.`note` FROM `" .. T("coinPayments") .. "` p JOIN `" .. T("coinOrders") .. "` o ON o.`id` = p.`order_id` ORDER BY o.`id` DESC LIMIT " ..
			(p.count or 20), {{"id", "n"}, {"created", "n"}, {"account_id", "n"}, {"pack_key", "s"}, {"status", "s"}, {"method", "s"}, {"amount_cents", "n"},
			{"currency", "s"}, {"psp", "s"}, {"psp_status", "s"}, {"source", "s"}, {"note", "s"}})) do
			lines[#lines + 1] = string.format("Donation #%d %s acc %d %s %s %s via %s (%s, %s) %s %s", r.id, os.date("%m-%d %H:%M", r.created), r.account_id,
				r.pack_key, money(r.amount_cents, r.currency), r.status, r.method, r.psp ~= "" and r.psp or "no charge yet", r.source, r.psp_status, r.note)
		end
		return true, "Donations: Pix / PayPal", lines
	end}

reg{id = "pay_reversals", name = "Donations: refunds and chargebacks", description = "Donations refunded, charged back or disputed after the coins were credited, and the coins taken back (shop_coins_config.lua payments.removeCoinsOnReversal).",
	params = {{name = "count", label = "Rows", type = "int", min = 1, max = 100, default = 30}},
	handler = function(actor, p)
		local lines = {}
		for _, r in ipairs(sel("SELECT o.`id`, o.`account_id`, o.`pack_key`, o.`coins`, o.`bonus`, o.`first_bonus`, p.`method`, p.`amount_cents`, p.`currency`, " ..
			"p.`reversal`, p.`reversal_cents`, p.`reversal_done`, p.`reversal_coins`, p.`reversal_at` FROM `" .. T("coinPayments") .. "` p JOIN `" .. T("coinOrders") ..
			"` o ON o.`id` = p.`order_id` WHERE p.`reversal` <> '' ORDER BY p.`reversal_at` DESC LIMIT " .. (p.count or 30),
			{{"id", "n"}, {"account_id", "n"}, {"pack_key", "s"}, {"coins", "n"}, {"bonus", "n"}, {"first_bonus", "n"}, {"method", "s"}, {"amount_cents", "n"},
			{"currency", "s"}, {"reversal", "s"}, {"reversal_cents", "n"}, {"reversal_done", "n"}, {"reversal_coins", "n"}, {"reversal_at", "n"}})) do
			local credited = r.coins + r.bonus + r.first_bonus
			lines[#lines + 1] = string.format("Donation #%d %s acc %d %s %s: %s of %s, %s", r.id, os.date("%m-%d %H:%M", r.reversal_at), r.account_id, r.method,
				r.pack_key, r.reversal, money(r.reversal_cents > 0 and r.reversal_cents or r.amount_cents, r.currency),
				r.reversal_done == 1 and string.format("%d of %d coins taken back", r.reversal_coins, credited) or "waiting for the game server")
		end
		-- refunded before the coins were credited (nothing to take back)
		for _, r in ipairs(sel("SELECT o.`id`, o.`account_id`, o.`note`, p.`method`, p.`amount_cents`, p.`currency` FROM `" .. T("coinOrders") .. "` o JOIN `" ..
			T("coinPayments") .. "` p ON p.`order_id` = o.`id` WHERE o.`status` = 'refunded' ORDER BY o.`id` DESC LIMIT 20",
			{{"id", "n"}, {"account_id", "n"}, {"note", "s"}, {"method", "s"}, {"amount_cents", "n"}, {"currency", "s"}})) do
			lines[#lines + 1] = string.format("Donation #%d acc %d %s %s before crediting (%s)", r.id, r.account_id, r.method, money(r.amount_cents, r.currency), r.note)
		end
		return true, #lines .. " refunds / chargebacks", #lines > 0 and lines or {"None."}
	end}

local function packOptions()
	local out = {}
	-- the admin folder may load before shop.lua
	local coins = ChaosShopCoinsConfig or dofile("data/scripts/chaos/shop_coins_config.lua")
	for _, pack in ipairs(coins.packs or {}) do
		out[#out + 1] = {value = pack.key, label = (pack.name or pack.key) .. " (" .. pack.coins .. ")"}
	end
	return out
end

reg{id = "record_order", name = "Record a donation", description = "For a donation confirmed outside the website (bank transfer): writes a paid coin order; the store credits it with its bonuses within a minute.",
	confirm = true, minGroup = 6,
	params = {{name = "player", label = "Character of the account", type = "player"},
		{name = "pack", label = "Pack", type = "select", options = packOptions()},
		{name = "ref", label = "Payment reference", type = "string", max = 100}},
	handler = function(actor, p)
		local t = ChaosAdmin.dbPlayer(p.player)
		if not t then return false, "No such character." end
		if not p.ref or p.ref == "" then return false, "A payment reference is needed (it makes the order unique)." end
		local ok = db.query("INSERT IGNORE INTO `" .. T("coinOrders") .. "` (`account_id`, `pack_key`, `provider`, `provider_ref`, `status`, `created`) VALUES (" ..
			t.account_id .. ", " .. db.escapeString(p.pack) .. ", 'manual', " .. db.escapeString(p.ref) .. ", 'paid', " .. os.time() .. ")")
		if not ok then return false, "Could not write the order." end
		if ChaosShop and ChaosShop.processOrders then ChaosShop.processOrders() end
		return true, string.format("Order %s for account %d (%s) recorded.", p.pack, t.account_id, t.name)
	end}

reg{id = "give_coins", name = "Give Chaos Coins", description = "Add (or take with a negative number) Chaos Coins to the account of a character.",
	params = {{name = "player", label = "Character", type = "player"}, {name = "amount", label = "Coins (+/-)", type = "int", min = -1000000, max = 1000000}},
	handler = function(actor, p)
		local t = ChaosAdmin.dbPlayer(p.player)
		if not t then return false, "No such character." end
		if not ChaosShop then return false, "The store is not loaded." end
		ChaosShop.addCoins(t.account_id, p.amount)
		return true, string.format("%s's account now has %d Chaos Coins.", t.name, ChaosShop.getCoins(t.account_id))
	end}
