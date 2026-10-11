-- Market price history: every completed market sale (a bought offer, a buy order fill) is kept per item key (realm,
-- currency, item type, rarity, item level band) with its price per unit; the market window asks for the stats of a key
-- (last sale, 7-day median, range, volume, a 30-day chart of daily medians, the typical price), the Sell form suggests a
-- price from it and Browse marks offers priced well under / over the typical price. Numbers: market_history_config.lua;
-- pure logic: market_history_core.lua (tests/market_history_test.lua); tables: sql/chaos_market_history.sql. Overview:
-- server/README.md "Market", Price history.
--
-- Hooks in market.lua (each guarded by `if ChaosMarketHistory`): MK.buy and MK.completeFill call MH.record after their
-- transaction committed (a failure here never touches the sale), MK.browse calls MH.markRows, the opcode handler hands
-- the action "prices" to MH.actions.
-- Protocol (opcode 221, JSON {action, data}):
--   client -> server  prices {id (an offer) | sid, rarity, ilvl; seq}
--   server -> client  prices {seq, id, sid, rarity, band, bandText, gold = stats, coins = stats, marks, warn}
--                     stats = market_history_core.lua H.stats without lastAt (lastAgo = seconds since the last sale)
-- Retention: single sales for rawDays full days, then one daily row per key and day (median, low, high, trimmed mean,
-- sales, units), dropped after keepDays; a globalevent does it every compactSeconds, one key-day per transaction.
-- Lua 5.1 / LuaJIT compatible.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not ChaosMarketCore then
	dofile("data/scripts/chaos/market_core.lua")
end
if not ChaosMarketHistoryCore then
	dofile("data/scripts/chaos/market_history_core.lua")
end

Chaos.marketHistoryConfig = dofile("data/scripts/chaos/market_history_config.lua")
local cfg = Chaos.marketHistoryConfig
local H = ChaosMarketHistoryCore
local MC = ChaosMarketCore
ChaosMarketHistory = ChaosMarketHistory or {}
local MH = ChaosMarketHistory
local OPCODE = ChaosOpcodes.market or 221
local TS, TD = cfg.tables.sales, cfg.tables.daily
local function offersTable()
	return Chaos.marketConfig and Chaos.marketConfig.tables.offers or "chaos_market_offers"
end

local function log(text)
	print("[Chaos market history] " .. text)
end

local function sql(query, columns)
	return Chaos.select(query, columns)
end

local function exec(query)
	if not db.query(query) then
		return -1
	end
	local r = sql("SELECT ROW_COUNT() AS `n`", {{"n", "n"}})[1]
	return r and r.n or 0
end

local function transaction(fn)
	if not db.query("START TRANSACTION") then
		return false
	end
	local ok, res = pcall(fn)
	if ok and res then
		if db.query("COMMIT") then
			return true
		end
	elseif not ok then
		log("transaction error: " .. tostring(res))
	end
	db.query("ROLLBACK")
	return false
end

local function esc(s)
	return db.escapeString(tostring(s))
end

local SCHEMA = {
	[[CREATE TABLE IF NOT EXISTS `chaos_market_history` (`id` int(11) NOT NULL AUTO_INCREMENT,
	`realm` int(11) NOT NULL DEFAULT 0, `item_id` int(11) NOT NULL, `rarity` tinyint(3) unsigned NOT NULL DEFAULT 0,
	`band` int(11) NOT NULL DEFAULT 0, `currency` varchar(8) NOT NULL DEFAULT 'gold', `price` bigint(20) unsigned NOT NULL,
	`count` int(11) NOT NULL DEFAULT 1, `at` int(10) unsigned NOT NULL, `day` int(11) NOT NULL, `offer_id` int(11) NOT NULL,
	PRIMARY KEY (`id`), UNIQUE KEY `chaos_market_history_offer` (`offer_id`),
	KEY `chaos_market_history_key` (`realm`, `item_id`, `rarity`, `band`, `currency`, `at`), KEY `chaos_market_history_day` (`day`))
	ENGINE=InnoDB DEFAULT CHARSET=utf8]],
	[[CREATE TABLE IF NOT EXISTS `chaos_market_history_daily` (`realm` int(11) NOT NULL DEFAULT 0, `item_id` int(11) NOT NULL,
	`rarity` tinyint(3) unsigned NOT NULL DEFAULT 0, `band` int(11) NOT NULL DEFAULT 0, `currency` varchar(8) NOT NULL DEFAULT 'gold',
	`day` int(11) NOT NULL, `sales` int(11) NOT NULL DEFAULT 0, `units` int(11) NOT NULL DEFAULT 0,
	`median` bigint(20) unsigned NOT NULL DEFAULT 0, `low` bigint(20) unsigned NOT NULL DEFAULT 0,
	`high` bigint(20) unsigned NOT NULL DEFAULT 0, `mean` bigint(20) unsigned NOT NULL DEFAULT 0,
	PRIMARY KEY (`realm`, `item_id`, `rarity`, `band`, `currency`, `day`), KEY `chaos_market_history_daily_day` (`day`))
	ENGINE=InnoDB DEFAULT CHARSET=utf8]]
}

local function realmOf(player)
	local S = ChaosSeason
	if S and S.realmOfGuid then
		local ok, r = pcall(S.realmOfGuid, player:getGuid())
		if ok then
			return tonumber(r) or 0
		end
	end
	return 0
end

-- ------------------------------------------------------------------ recording
local cache = {} -- H.key -> {at, s}

-- a sale that just completed (the offer row is sold): one row, once per offer (the unique key makes it idempotent)
function MH.record(offerId, realm)
	local o = sql(string.format("SELECT `item_id`, `count`, `rarity`, `ilvl`, `paid_currency`, `paid_amount`, `closed_at` FROM `%s` "
		.. "WHERE `id` = %d AND `state` = 1", offersTable(), offerId), {{"item_id", "n"}, {"count", "n"}, {"rarity", "n"}, {"ilvl", "n"},
		{"paid_currency", "s"}, {"paid_amount", "n"}, {"closed_at", "n"}})[1]
	if not o or o.paid_amount <= 0 then
		return false
	end
	local cur = o.paid_currency == "coins" and "coins" or "gold"
	local band = H.band(o.ilvl, cfg.bandSize)
	local count = math.max(1, o.count)
	local at = o.closed_at > 0 and o.closed_at or os.time()
	local done = exec(string.format("INSERT IGNORE INTO `%s` (`realm`, `item_id`, `rarity`, `band`, `currency`, `price`, `count`, `at`, `day`, "
		.. "`offer_id`) VALUES (%d, %d, %d, %d, %s, %d, %d, %d, %d, %d)", TS, realm or 0, o.item_id, o.rarity, band, esc(cur),
		H.unitPrice(o.paid_amount, count), count, at, H.day(at), offerId)) >= 0
	cache[H.key(realm, cur, o.item_id, o.rarity, band)] = nil
	return done
end

-- the sold offers of the last keepDays, once (server_config chaos_market_history = cfg.backfillVersion). Their realm is
-- the one stored on the offer (a season offer sold after its season ended counts for that season).
local BACKFILL = "chaos_market_history"
function MH.backfill()
	local r = sql(string.format("SELECT `value` FROM `server_config` WHERE `config` = %s", esc(BACKFILL)), {{"value", "s"}})[1]
	if (r and tonumber(r.value) or 0) >= cfg.backfillVersion then
		return 0
	end
	local b = math.max(2, cfg.bandSize)
	local n = exec(string.format("INSERT IGNORE INTO `%s` (`realm`, `item_id`, `rarity`, `band`, `currency`, `price`, `count`, `at`, `day`, `offer_id`) "
		.. "SELECT `realm`, `item_id`, `rarity`, IF(`ilvl` > 0, FLOOR(`ilvl` / %d) * %d, 0), IF(`paid_currency` = 'coins', 'coins', 'gold'), "
		.. "FLOOR(`paid_amount` / GREATEST(`count`, 1)), GREATEST(`count`, 1), `closed_at`, FLOOR(`closed_at` / 86400), `id` FROM `%s` "
		.. "WHERE `state` = 1 AND `paid_amount` > 0 AND `closed_at` >= %d", TS, b, b, offersTable(), os.time() - cfg.keepDays * H.DAY))
	if n < 0 then
		log("backfill failed (tried again at the next startup)")
		return n
	end
	db.query(string.format("INSERT INTO `server_config` (`config`, `value`) VALUES (%s, %s) ON DUPLICATE KEY UPDATE `value` = %s", esc(BACKFILL),
		esc(tostring(cfg.backfillVersion)), esc(tostring(cfg.backfillVersion))))
	log(string.format("%d past sales imported", n))
	return n
end

-- ------------------------------------------------------------------ retention
local KEY_COLS = {{"realm", "n"}, {"item_id", "n"}, {"rarity", "n"}, {"band", "n"}, {"currency", "s"}, {"day", "n"}}

local function keyWhere(g)
	return string.format("`realm` = %d AND `item_id` = %d AND `rarity` = %d AND `band` = %d AND `currency` = %s AND `day` = %d", g.realm,
		g.item_id, g.rarity, g.band, esc(g.currency), g.day)
end

-- finished days -> daily rows (one key-day per transaction: its row written, its sales deleted), then old rows dropped;
-- returns key-days aggregated, rows dropped
function MH.compact(now)
	now = now or os.time()
	local cut = H.cutoffs(now, cfg)
	local groups = sql(string.format("SELECT `realm`, `item_id`, `rarity`, `band`, `currency`, `day` FROM `%s` WHERE `day` < %d "
		.. "GROUP BY `realm`, `item_id`, `rarity`, `band`, `currency`, `day` LIMIT %d", TS, cut.rawBefore, cfg.compactGroups), KEY_COLS)
	local done = 0
	for _, g in ipairs(groups) do
		local rows = sql(string.format("SELECT `id`, `at`, `price`, `count` FROM `%s` WHERE %s", TS, keyWhere(g)),
			{{"id", "n"}, {"at", "n"}, {"price", "n"}, {"count", "n"}})
		local list = {}
		for _, r in ipairs(rows) do
			list[#list + 1] = {id = r.id, realm = g.realm, item = g.item_id, rarity = g.rarity, band = g.band, cur = g.currency, at = r.at,
				p = r.price, q = r.count}
		end
		local built = H.compactGroups(list, cut.rawBefore, cfg.trimPct)[1]
		if built and built.agg then
			local a = built.agg
			local ok = transaction(function()
				if exec(string.format("INSERT INTO `%s` (`realm`, `item_id`, `rarity`, `band`, `currency`, `day`, `sales`, `units`, `median`, `low`, "
						.. "`high`, `mean`) VALUES (%d, %d, %d, %d, %s, %d, %d, %d, %d, %d, %d, %d) ON DUPLICATE KEY UPDATE "
						.. "`median` = FLOOR((`median` * `sales` + VALUES(`median`) * VALUES(`sales`)) / (`sales` + VALUES(`sales`))), "
						.. "`mean` = FLOOR((`mean` * `sales` + VALUES(`mean`) * VALUES(`sales`)) / (`sales` + VALUES(`sales`))), "
						.. "`low` = LEAST(`low`, VALUES(`low`)), `high` = GREATEST(`high`, VALUES(`high`)), `units` = `units` + VALUES(`units`), "
						.. "`sales` = `sales` + VALUES(`sales`)", TD, g.realm, g.item_id, g.rarity, g.band, esc(g.currency), g.day, a.sales, a.units,
						a.median, a.low, a.high, a.mean or a.median)) < 1 then
					return false
				end
				return exec(string.format("DELETE FROM `%s` WHERE `id` IN (%s)", TS, table.concat(built.ids, ","))) == #built.ids
			end)
			if ok then
				done = done + 1
			else
				log(string.format("could not aggregate item %d day %d (tried again next run)", g.item_id, g.day))
			end
		end
	end
	local dropped = math.max(0, exec(string.format("DELETE FROM `%s` WHERE `day` < %d LIMIT %d", TD, cut.dailyBefore, cfg.dropBatch)))
		+ math.max(0, exec(string.format("DELETE FROM `%s` WHERE `day` < %d LIMIT %d", TS, cut.dailyBefore, cfg.dropBatch)))
	if done > 0 or dropped > 0 then
		cache = {}
	end
	return done, dropped
end

-- ------------------------------------------------------------------ stats
-- the stats of many keys of one realm with two queries; keys = {{cur, item, rarity, band}}; returns H.key -> stats
function MH.statsMany(realm, keys, now)
	now = now or os.time()
	local out, missing, items = {}, {}, {}
	for _, k in ipairs(keys) do
		local key = H.key(realm, k.cur, k.item, k.rarity, k.band)
		local c = cache[key]
		if c and now - c.at < cfg.cacheSeconds then
			out[key] = c.s
		elseif not missing[key] then
			missing[key] = true
			items[#items + 1] = string.format("%d", k.item)
		end
	end
	if #items == 0 then
		return out
	end
	local cut = H.cutoffs(now, cfg)
	local inList = table.concat(items, ",")
	local sales, daily = {}, {}
	for _, r in ipairs(sql(string.format("SELECT `item_id`, `rarity`, `band`, `currency`, `at`, `price`, `count` FROM `%s` WHERE `realm` = %d "
			.. "AND `item_id` IN (%s) AND `at` >= %d ORDER BY `at` DESC LIMIT %d", TS, realm, inList, (cut.today - cfg.chartDays + 1) * H.DAY,
			cfg.rawLimit * #items), {{"item_id", "n"}, {"rarity", "n"}, {"band", "n"}, {"currency", "s"}, {"at", "n"}, {"price", "n"}, {"count", "n"}})) do
		local key = H.key(realm, r.currency, r.item_id, r.rarity, r.band)
		if missing[key] then
			sales[key] = sales[key] or {}
			sales[key][#sales[key] + 1] = {at = r.at, p = r.price, q = r.count}
		end
	end
	for _, r in ipairs(sql(string.format("SELECT `item_id`, `rarity`, `band`, `currency`, `day`, `sales`, `units`, `median`, `low`, `high` FROM `%s` "
			.. "WHERE `realm` = %d AND `item_id` IN (%s) AND `day` > %d", TD, realm, inList, cut.today - cfg.chartDays),
			{{"item_id", "n"}, {"rarity", "n"}, {"band", "n"}, {"currency", "s"}, {"day", "n"}, {"sales", "n"}, {"units", "n"}, {"median", "n"},
			{"low", "n"}, {"high", "n"}})) do
		local key = H.key(realm, r.currency, r.item_id, r.rarity, r.band)
		if missing[key] then
			daily[key] = daily[key] or {}
			daily[key][#daily[key] + 1] = r
		end
	end
	for key in pairs(missing) do
		local s = H.stats(sales[key], daily[key], now, cfg)
		cache[key] = {at = now, s = s}
		out[key] = s
	end
	return out
end

function MH.stats(realm, cur, item, rarity, band, now)
	return MH.statsMany(realm, {{cur = cur, item = item, rarity = rarity, band = band}}, now)[H.key(realm, cur, item, rarity, band)]
end

-- what the client gets of a stats table
local function view(s, now)
	if not s then
		return nil
	end
	local v = {}
	for k, x in pairs(s) do
		v[k] = x
	end
	v.lastAgo = s.lastAt and math.max(0, now - s.lastAt) or nil
	v.lastAt = nil
	return v
end

-- the Browse page (market.lua MK.browse): rows = the offer rows read (item_id, rarity, ilvl, count, prices), list = their
-- views in the same order; each view gets typ (typical price per unit of the offer's first currency), tcur and pm
-- ("low" / "high" when priced well under / over it)
function MH.markRows(rows, list, realm)
	local keys = {}
	for _, r in ipairs(rows) do
		local cur = (r.price_gold or 0) > 0 and "gold" or "coins"
		keys[#keys + 1] = {cur = cur, item = r.item_id, rarity = r.rarity, band = H.band(r.ilvl, cfg.bandSize)}
	end
	local stats = MH.statsMany(realm, keys)
	for i, r in ipairs(rows) do
		local k, v = keys[i], list[i]
		local s = v and stats[H.key(realm, k.cur, k.item, k.rarity, k.band)]
		if s and s.typical then
			local price = k.cur == "gold" and r.price_gold or r.price_coins
			v.typ, v.tcur = s.typical, k.cur
			v.pm = H.mark(H.unitPrice(price, r.count), s.typical, cfg.marks)
		end
	end
end

local function send(player, data)
	Chaos.sendChunked(player, OPCODE, json.encode({action = "prices", data = data}))
end

function MH.prices(player, d)
	if ChaosRateLimit and not ChaosRateLimit.allow(player, "market.prices", cfg.rateMs) then
		return false
	end
	local sid, rarity, ilvl
	local id = MC.int(d.id)
	if id then
		local o = sql(string.format("SELECT `item_id`, `rarity`, `ilvl` FROM `%s` WHERE `id` = %d", offersTable(), id),
			{{"item_id", "n"}, {"rarity", "n"}, {"ilvl", "n"}})[1]
		if not o then
			send(player, {seq = d.seq, id = id, gone = true})
			return false
		end
		sid, rarity, ilvl = o.item_id, o.rarity, o.ilvl
	else
		sid, rarity, ilvl = MC.int(d.sid), MC.clampInt(d.rarity, 0, 255) or 0, MC.clampInt(d.ilvl, 0, 100000) or 0
	end
	if not sid or sid <= 0 then
		return false
	end
	local realm, now = realmOf(player), os.time()
	local band = H.band(ilvl, cfg.bandSize)
	local all = MH.statsMany(realm, {{cur = "gold", item = sid, rarity = rarity, band = band}, {cur = "coins", item = sid, rarity = rarity, band = band}}, now)
	send(player, {seq = d.seq, id = id, sid = sid, rarity = rarity, band = band, bandText = H.bandText(band, cfg.bandSize),
		gold = view(all[H.key(realm, "gold", sid, rarity, band)], now), coins = view(all[H.key(realm, "coins", sid, rarity, band)], now),
		marks = cfg.marks, warn = cfg.warn})
	return true
end

MH.actions = {prices = MH.prices}

-- ------------------------------------------------------------------ events
local startup = GlobalEvent("ChaosMarketHistoryStartup")
function startup.onStartup()
	for _, q in ipairs(SCHEMA) do
		db.query(q)
	end
	MH.backfill()
	MH.compact()
	return true
end
startup:register()

local job = GlobalEvent("ChaosMarketHistoryCompact")
function job.onThink(interval)
	local ok, err = pcall(MH.compact)
	if not ok then
		log("compaction error: " .. tostring(err))
	end
	return true
end
job:interval(cfg.compactSeconds * 1000)
job:register()

return MH
