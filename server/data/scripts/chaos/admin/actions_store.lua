-- Store category (the Chaos store, shop.lua): sales dashboard from chaos_shop_purchases, recent purchases, paid Chaos
-- Coin orders (chaos_coin_orders), recording a paid order by hand and giving coins.
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

reg{id = "coin_orders", name = "Coin orders", description = "Paid Chaos Coin orders (chaos_coin_orders): the last ones and the totals.",
	params = {{name = "count", label = "Rows", type = "int", min = 1, max = 100, default = 20}},
	handler = function(actor, p)
		local lines = {}
		for _, r in ipairs(sel("SELECT `status`, COUNT(*) AS `n`, SUM(`coins` + `bonus` + `first_bonus`) AS `c` FROM `" ..
			T("coinOrders") .. "` GROUP BY `status`", {{"status", "s"}, {"n", "n"}, {"c", "n"}})) do
			lines[#lines + 1] = string.format("%-9s %5d orders  %8d coins", r.status, r.n, r.c)
		end
		for _, r in ipairs(sel("SELECT `id`, `account_id`, `pack_key`, `provider`, `status`, `coins`, `bonus`, `first_bonus`, `note`, `created` FROM `" ..
			T("coinOrders") .. "` ORDER BY `id` DESC LIMIT " .. (p.count or 20), {{"id", "n"}, {"account_id", "n"}, {"pack_key", "s"},
			{"provider", "s"}, {"status", "s"}, {"coins", "n"}, {"bonus", "n"}, {"first_bonus", "n"}, {"note", "s"}, {"created", "n"}})) do
			lines[#lines + 1] = string.format("#%d %s acc %d %s %s %s %d+%d+%d %s", r.id, os.date("%m-%d %H:%M", r.created), r.account_id,
				r.pack_key, r.provider, r.status, r.coins, r.bonus, r.first_bonus, r.note)
		end
		return true, "Coin orders", lines
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

reg{id = "record_order", name = "Record a paid coin order", description = "For a payment confirmed outside the website (bank transfer): writes a paid order; the store credits it with its bonuses within a minute.",
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
