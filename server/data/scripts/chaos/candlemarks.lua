-- Candlemarks (client game_candlemarks, extended opcode ChaosOpcodes.candlemarks = 176): a currency for time online.
-- Every online character earns one Candlemark per 30 minutes online for its ACCOUNT (at most 2 characters per IP at
-- once); the shop sells pocket boss charges, common orbs, gems, supplies and other help with weekly limits. Numbers:
-- candlemarks_config.lua; pure logic: candlemarks_core.lua (tests: server/tests/candlemarks_test.lua); overview and
-- the write order: server/README.md "Candlemarks". Tables (sql/chaos_candlemarks.sql, also created at startup):
--   chaos_candlemarks           one row per account: balance, earned, spent, the daily cap's day and count
--   chaos_candlemark_progress   one row per character: seconds toward its next coin (written with every coin, every
--                               flushEvery ticks and at logout: a crash loses a few minutes of progress, never adds)
--   chaos_candlemark_purchases  one row per purchase: the weekly limits, the audit, the crash recovery
--
-- Earning: a GlobalEvent every tickSeconds adds the time since the last tick to every earning character
-- (ChaosCandlemarksCore.pickEarners: not staff, at least minLevel, the first maxPerIp logins of an IP). A full block
-- is a coin: the account's balance and the character's progress are written in one transaction.
--
-- Buying (no duplicate on a crash; storage 7102460 = the character's delivery mark, the last purchase id delivered):
--   1. checks (Osric the Chandler within npc.range tiles on the same floor, offer, level, weekly limit of the
--      account, balance in memory), one purchase at a time per character
--   2. one transaction: the balance taken with a conditional UPDATE (balance >= price, ROW_COUNT), the purchase row
--      written as pending (state 0) with what it delivers (`detail`)
--   3a. items and gems: given (backpack, then inbox), the mark set to the row id, the character saved (items and mark
--       in one save), the row marked done (state 1)
--   3b. pocket boss charges, calls, cosmetics: the mark set and the character saved FIRST, then the API is called;
--       a failure (an error or false) refunds the price (state 2)
--   Login recovery of rows still pending: id <= mark = delivered and saved (only the row update was lost): done;
--   id > mark = never saved: items are given now, other kinds are refunded. So a crash never duplicates; a crash
--   between 3b's save and its call loses that one purchase (the row stays done; staff can refund with /candlemarks).
--
-- Protocol (JSON {action, data}):
--   client -> server  open | close | buy {k}
--   server -> client  hud {b, p, n, e, w} (every tick: balance, progress, block, earning, why not)
--                     | state (K.view) | result {ok, text} | npc {} (Osric the Chandler opens the window)
-- Staff: /candlemarks <name> (look, group 4) | /candlemarks <name>, give <n> | take <n> | refund <purchase id>
-- (group 5, logged). Lua 5.1 / LuaJIT.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not Chaos.t then
	dofile("data/scripts/chaos/i18n_core.lua")
end
dofile("data/scripts/chaos/candlemarks_core.lua")
if not ChaosNpcPlace then
	dofile("data/scripts/chaos/npc_place.lua")
end

Chaos.candlemarksConfig = dofile("data/scripts/chaos/candlemarks_config.lua")
local cfg = Chaos.candlemarksConfig
local K = ChaosCandlemarksCore
local OPCODE = ChaosOpcodes.candlemarks or cfg.opcode
local ST = cfg.storage
local T = Chaos.candlemarksTables or {accounts = "chaos_candlemarks", progress = "chaos_candlemark_progress",
	purchases = "chaos_candlemark_purchases"}
local FLUSH_EVERY = 5 -- ticks between progress writes of a character

ChaosCandlemarks = ChaosCandlemarks or {}
local M = ChaosCandlemarks
M.cfg, M.core = cfg, K
M.accounts = M.accounts or {} -- account id -> K.newAccount() state
M.players = M.players or {} -- creature id -> {guid, account, loginAt, lastTick, progress, ticks}
M.earners = M.earners or {} -- guid -> true (last tick)
M.why = M.why or {} -- guid -> why it does not earn (last tick)
M.used = M.used or {} -- account id -> {week, map = {[limit key] = n}}
M.busy = M.busy or {} -- guid -> true while a purchase runs
M.capNoted = M.capNoted or {} -- account id -> day the cap message was sent
M.clockShift = M.clockShift or 0

local function log(text)
	print("[Chaos candlemarks] " .. text)
end

local function try(name, fn, ...)
	local ok, a, b = pcall(fn, ...)
	if not ok then
		log(name .. ": " .. tostring(a))
		return nil
	end
	return a, b
end

local function now()
	return os.time() + (M.clockShift or 0)
end

local function msg(player, key, ...)
	return Chaos.t(player, cfg.messages[key] or key, ...)
end

local function isStaff(player)
	local ok, g = pcall(function() return player:getGroup():getId() end)
	return ok and (tonumber(g) or 0) >= cfg.staffGroup
end

local function exec(query)
	if not db.query(query) then
		return 0
	end
	local rows = Chaos.select("SELECT ROW_COUNT() AS `n`", {{"n", "n"}})
	return rows[1] and tonumber(rows[1].n) or 0
end

-- ---------------------------------------------------------------- tables
function M.ensureTables()
	db.query("CREATE TABLE IF NOT EXISTS `" .. T.accounts .. "` (`account_id` int(11) NOT NULL, `balance` int(11) NOT NULL " ..
		"DEFAULT 0, `earned` int(11) NOT NULL DEFAULT 0, `spent` int(11) NOT NULL DEFAULT 0, `day` int(11) NOT NULL DEFAULT 0, " ..
		"`today` int(11) NOT NULL DEFAULT 0, `updated` int(10) unsigned NOT NULL DEFAULT 0, PRIMARY KEY (`account_id`)) " ..
		"ENGINE=InnoDB DEFAULT CHARSET=utf8")
	db.query("CREATE TABLE IF NOT EXISTS `" .. T.progress .. "` (`player_id` int(11) NOT NULL, `account_id` int(11) NOT NULL, " ..
		"`progress` int(11) NOT NULL DEFAULT 0, `updated` int(10) unsigned NOT NULL DEFAULT 0, PRIMARY KEY (`player_id`)) " ..
		"ENGINE=InnoDB DEFAULT CHARSET=utf8")
	db.query("CREATE TABLE IF NOT EXISTS `" .. T.purchases .. "` (`id` int(11) NOT NULL AUTO_INCREMENT, `account_id` int(11) " ..
		"NOT NULL, `player_id` int(11) NOT NULL, `offer` varchar(64) NOT NULL, `limit_key` varchar(64) NOT NULL, `week` int(11) " ..
		"NOT NULL, `price` int(11) NOT NULL, `state` tinyint(3) unsigned NOT NULL DEFAULT 0, `detail` varchar(255) NOT NULL " ..
		"DEFAULT '', `created` int(10) unsigned NOT NULL, `done_at` int(10) unsigned NOT NULL DEFAULT 0, PRIMARY KEY (`id`), " ..
		"KEY `chaos_cm_week` (`account_id`, `week`, `limit_key`), KEY `chaos_cm_player` (`player_id`, `state`)) " ..
		"ENGINE=InnoDB DEFAULT CHARSET=utf8")
end

-- ---------------------------------------------------------------- accounts and characters
function M.account(accountId)
	accountId = tonumber(accountId) or 0
	if accountId <= 0 then
		return nil
	end
	local acc = M.accounts[accountId]
	if acc then
		return acc
	end
	acc = K.newAccount()
	local row = Chaos.select(string.format("SELECT `balance`, `earned`, `spent`, `day`, `today` FROM `%s` WHERE `account_id` = %d",
		T.accounts, accountId), {{"balance", "n"}, {"earned", "n"}, {"spent", "n"}, {"day", "n"}, {"today", "n"}})[1]
	if row then
		acc.balance, acc.earned, acc.spent = K.int(row.balance), K.int(row.earned), K.int(row.spent)
		acc.day, acc.today = K.int(row.day), K.int(row.today)
	else
		db.query(string.format("INSERT IGNORE INTO `%s` (`account_id`, `updated`) VALUES (%d, %d)", T.accounts, accountId, now()))
	end
	M.accounts[accountId] = acc
	return acc
end

local function loadProgress(guid)
	local row = Chaos.select(string.format("SELECT `progress` FROM `%s` WHERE `player_id` = %d", T.progress, guid),
		{{"progress", "n"}})[1]
	return math.max(0, math.min(K.int(row and row.progress), K.blockSec(cfg) - 1))
end

local function progressQuery(pl)
	return string.format("INSERT INTO `%s` (`player_id`, `account_id`, `progress`, `updated`) VALUES (%d, %d, %d, %d) " ..
		"ON DUPLICATE KEY UPDATE `progress` = %d, `updated` = %d", T.progress, pl.guid, pl.account, pl.progress, now(),
		pl.progress, now())
end

local function flushProgress(pl)
	pl.ticks = 0
	db.query(progressQuery(pl))
end

function M.track(player)
	local cid = player:getId()
	local pl = M.players[cid]
	if pl and pl.guid == player:getGuid() then
		return pl
	end
	pl = {guid = player:getGuid(), account = player:getAccountId(), loginAt = now(), lastTick = now(), ticks = 0}
	pl.progress = loadProgress(pl.guid)
	M.players[cid] = pl
	M.account(pl.account)
	return pl
end

local function accountOnline(accountId, exceptCid)
	for cid, pl in pairs(M.players) do
		if cid ~= exceptCid and pl.account == accountId then
			return true
		end
	end
	return false
end

-- ---------------------------------------------------------------- the weekly limits
local function weekNow()
	return K.weekKey(now(), cfg.weekResetHour)
end

function M.usedOf(accountId)
	local week = weekNow()
	local u = M.used[accountId]
	if u and u.week == week then
		return u.map
	end
	local map = {}
	for _, r in ipairs(Chaos.select(string.format("SELECT `limit_key`, COUNT(*) AS `n` FROM `%s` WHERE `account_id` = %d AND " ..
			"`week` = %d AND `state` <> 2 GROUP BY `limit_key`", T.purchases, accountId, week), {{"limit_key", "s"}, {"n", "n"}})) do
		if type(r.limit_key) == "string" then
			map[r.limit_key] = K.int(r.n)
		end
	end
	M.used[accountId] = {week = week, map = map}
	return map
end

local function weekEnds()
	local w = weekNow()
	local at = os.time({year = math.floor(w / 10000), month = math.floor(w / 100) % 100, day = w % 100 + 7,
		hour = cfg.weekResetHour})
	return math.max(0, at - now())
end

-- ---------------------------------------------------------------- the offers
local function apiFn(call)
	local t = type(call) == "table" and type(call[1]) == "string" and rawget(_G, call[1])
	local f = type(t) == "table" and type(call[2]) == "string" and t[call[2]]
	return type(f) == "function" and f or nil
end

local function pocketApi()
	local P = rawget(_G, "ChaosPocketBoss")
	if type(P) == "table" and type(P.addCharges) == "function" and type(P.bosses) == "function" then
		return P
	end
	return nil
end

function M.offers()
	local P = pocketApi()
	local bosses
	if P then
		local ok, raw = pcall(P.bosses)
		bosses = ok and K.bosses(raw) or nil
	end
	local C = rawget(_G, "ChaosCosmetics")
	return K.offers(cfg, {has = function(call) return apiFn(call) ~= nil end, bosses = bosses,
		cosmetics = type(C) == "table" and type(C.grant) == "function" and type(C.owns) == "function"})
end

local cidCache = {}
local function clientId(id)
	id = K.int(id)
	if id <= 0 then
		return 0
	end
	if cidCache[id] == nil then
		local ok, c = pcall(function() return ItemType(id):getClientId() end)
		c = ok and tonumber(c) or 0
		cidCache[id] = (c and c >= 1 and c <= 65535) and math.floor(c) or 0
	end
	return cidCache[id]
end

local function gemConfig()
	if not ChaosGemsConfig then
		local ok, g = pcall(dofile, "data/lib/chaos_gems_config.lua")
		ChaosGemsConfig = ok and type(g) == "table" and g or nil
	end
	local g = ChaosGemsConfig or {}
	return #(g.types or {}) > 0 and #g.types or 7, g.firstId or 32001
end

local function iconOf(o)
	if o.kind == "item" then
		return clientId(o.items and o.items[1] and o.items[1][1])
	elseif o.kind == "gem" then
		local _, first = gemConfig()
		return clientId(first - 1 + K.int(o.tier))
	end
	return clientId(o.icon)
end

-- ---------------------------------------------------------------- the client
-- Osric the Chandler within npc.range tiles of the player, on the same floor (purchases need him: npc.buyNearNpc)
function M.near(player)
	local ok, found = pcall(function()
		local r = cfg.npc.range
		local name = cfg.npc.name:lower()
		local pos = player:getPosition()
		for _, c in ipairs(Game.getSpectators(pos, false, false, r, r, r, r) or {}) do
			if c:isNpc() and c:getName():lower() == name then
				local cp = c:getPosition()
				if cp.z == pos.z and math.abs(cp.x - pos.x) <= r and math.abs(cp.y - pos.y) <= r then
					return true
				end
			end
		end
		return false
	end)
	return ok and found == true
end

function M.sendHud(player, pl)
	pl = pl or M.players[player:getId()]
	local acc = pl and M.accounts[pl.account]
	if not acc then
		return
	end
	Chaos.send(player, OPCODE, "hud", {b = acc.balance, p = pl.progress, n = K.blockSec(cfg),
		e = M.earners[pl.guid] and true or false, w = M.why[pl.guid]})
end

function M.send(player)
	local pl = M.track(player)
	local acc = M.account(pl.account)
	if not acc then
		return
	end
	local list = M.offers()
	local view = K.view(acc, pl.progress, list, M.usedOf(pl.account), {earning = M.earners[pl.guid], why = M.why[pl.guid],
		level = player:getLevel(), icon = iconOf, weekEnds = weekEnds(),
		tr = function(text) return Chaos.t(player, text) end, near = M.near(player), owned = function(o)
			return o.kind == "cosmetic" and ChaosCosmetics and ChaosCosmetics.owns
				and select(2, pcall(ChaosCosmetics.owns, pl.account, o.cosmetic)) == true
		end}, cfg)
	Chaos.sendChunked(player, OPCODE, json.encode({action = "state", data = view}))
end

local function result(player, ok, text)
	Chaos.send(player, OPCODE, "result", {ok = ok and true or false, text = text})
	if text and text ~= "" then
		player:sendTextMessage(ok and (MESSAGE_INFO_DESCR or MESSAGE_STATUS_DEFAULT) or (MESSAGE_STATUS_SMALL or MESSAGE_STATUS_DEFAULT), text)
	end
	return ok
end

-- ---------------------------------------------------------------- earning
local function credit(pl, acc, gained)
	db.query("START TRANSACTION")
	db.query(string.format("UPDATE `%s` SET `balance` = `balance` + %d, `earned` = `earned` + %d, `day` = %d, `today` = %d, " ..
		"`updated` = %d WHERE `account_id` = %d", T.accounts, gained, gained, acc.day, acc.today, now(), pl.account))
	db.query(progressQuery(pl))
	db.query("COMMIT")
	pl.ticks = 0
end

function M.tick()
	if not cfg.enabled then
		return
	end
	local t = now()
	local day = K.dayKey(t, cfg.dayResetHour)
	local cands, list = {}, {}
	for _, p in ipairs(Game.getPlayers() or {}) do
		local pl = M.track(p)
		local ok, ip = pcall(function() return p:getIp() end)
		cands[#cands + 1] = {guid = pl.guid, ip = ok and tonumber(ip) or 0, level = p:getLevel(), staff = isStaff(p),
			loginAt = pl.loginAt}
		list[#list + 1] = {p, pl}
	end
	local earners, why = K.pickEarners(cands, cfg)
	M.earners, M.why = earners, why
	for _, e in ipairs(list) do
		local p, pl = e[1], e[2]
		local elapsed = t - pl.lastTick
		pl.lastTick = t
		local acc = earners[pl.guid] and M.account(pl.account)
		if acc then
			local gained, progress, info = K.advance(pl.progress, acc, cfg, elapsed, day)
			pl.progress = progress
			pl.ticks = pl.ticks + 1
			if gained > 0 then
				credit(pl, acc, gained)
				p:sendTextMessage(MESSAGE_EVENT_ADVANCE or MESSAGE_INFO_DESCR, msg(p, "earned", acc.balance))
				if not ChaosPack27Fx then
					pcall(dofile, "data/lib/chaos_pack27_fx.lua")
				end
				if ChaosPack27Fx and ChaosPack27Fx.PAIR27_FX and ChaosPack27Fx.send then -- pair 27 trial (switch off)
					pcall(function() ChaosPack27Fx.send(p:getPosition(), "candlemarks") end)
				end
				-- the account's other characters see the new balance
				for cid, other in pairs(M.players) do
					if other.account == pl.account and other ~= pl then
						local op = Player(cid)
						if op then
							M.sendHud(op, other)
						end
					end
				end
			elseif pl.ticks >= FLUSH_EVERY then
				flushProgress(pl)
			end
			if info.capped and M.capNoted[pl.account] ~= day then
				M.capNoted[pl.account] = day
				p:sendTextMessage(MESSAGE_INFO_DESCR, msg(p, "earnedCap"))
			end
		end
		M.sendHud(p, pl)
	end
end

-- ---------------------------------------------------------------- buying
local function giveItems(player, items)
	local inbox = false
	local box = player.getInbox and player:getInbox()
	for _, it in ipairs(items) do
		local rest = it.count - Chaos.giveItem(player, it.id, it.count)
		while rest > 0 and box do
			local n = math.min(rest, 100)
			box:addItem(it.id, n, INDEX_WHEREEVER or -1, FLAG_NOLIMIT)
			rest = rest - n
			inbox = true
		end
	end
	return inbox
end

local function detailOf(items)
	local parts = {}
	for _, it in ipairs(items) do
		parts[#parts + 1] = it.id .. ":" .. it.count
	end
	return "items:" .. table.concat(parts, ",")
end

local function itemsFromDetail(detail)
	local out = {}
	local body = type(detail) == "string" and detail:match("^items:(.*)$")
	for id, n in (body or ""):gmatch("(%d+):(%d+)") do
		out[#out + 1] = {id = tonumber(id), count = tonumber(n)}
	end
	return body and out or nil
end

local function setState(id, state)
	db.query(string.format("UPDATE `%s` SET `state` = %d, `done_at` = %d WHERE `id` = %d AND `state` = 0", T.purchases, state, now(), id))
end

local function refund(pl, id, price)
	db.query("START TRANSACTION")
	db.query(string.format("UPDATE `%s` SET `balance` = `balance` + %d, `spent` = `spent` - %d WHERE `account_id` = %d",
		T.accounts, price, price, pl.account))
	db.query(string.format("UPDATE `%s` SET `state` = 2, `done_at` = %d WHERE `id` = %d", T.purchases, now(), id))
	db.query("COMMIT")
	local acc = M.accounts[pl.account]
	if acc then
		acc.balance, acc.spent = acc.balance + price, acc.spent - price
	end
	M.used[pl.account] = nil
end

-- the non-item deliveries: true when delivered (a call or a cosmetic: no error and not false; a pocket boss charge:
-- at least one added), and the API's reason when it refused
local function deliverApi(player, pl, o)
	local ok, res
	if o.kind == "pocketboss" then
		local P = pocketApi()
		if not P then
			return false
		end
		local why
		ok, res, why = pcall(P.addCharges, player, o.boss, K.int(o.charges))
		-- ChaosPocketBoss.addCharges returns the charges added (0 and a reason when it adds none)
		if ok then
			return (res == true or K.int(res) > 0), type(why) == "string" and why or nil
		end
	elseif o.kind == "call" then
		local f = apiFn(o.call)
		if not f then
			return false
		end
		local args = {}
		for i = 3, #o.call do
			args[#args + 1] = o.call[i]
		end
		ok, res = pcall(f, player, (unpack or table.unpack)(args))
	elseif o.kind == "cosmetic" then
		local C = rawget(_G, "ChaosCosmetics")
		ok, res = pcall(C.grant, pl.account, o.cosmetic, "candlemarks")
	end
	if not ok then
		log("delivery of " .. tostring(o.key) .. " failed: " .. tostring(res))
		return false
	end
	return res ~= false
end

local function buyNow(player, d)
	local pl = M.track(player)
	local acc = M.account(pl.account)
	local _, byKey = M.offers()
	local o = type(d.k) == "string" and #d.k <= 80 and byKey[d.k] or nil
	local used = M.usedOf(pl.account)
	local owned = false
	if o and o.kind == "cosmetic" then
		local okO, has = pcall(ChaosCosmetics.owns, pl.account, o.cosmetic)
		owned = okO and has and true or false
	end
	local ok, reason, arg = K.checkBuy(o, {enabled = cfg.enabled and acc ~= nil, balance = acc and acc.balance or 0,
		level = player:getLevel(), used = o and used[K.limitKey(o)] or 0, owned = owned,
		near = not cfg.npc.buyNearNpc or M.near(player)}, cfg)
	if not ok then
		return result(player, false, msg(player, reason, arg))
	end
	local items
	if o.kind == "item" or o.kind == "gem" then
		local types, first = gemConfig()
		items = K.itemsOf(o, function(n) return math.random(1, n) end, types, first)
	end
	local detail = items and detailOf(items) or (o.kind == "pocketboss" and ("boss:" .. o.boss) or o.kind)
	local week = weekNow()
	-- 2. pay and write the purchase in one transaction
	db.query("START TRANSACTION")
	local paid = exec(string.format("UPDATE `%s` SET `balance` = `balance` - %d, `spent` = `spent` + %d, `updated` = %d " ..
		"WHERE `account_id` = %d AND `balance` >= %d", T.accounts, o.price, o.price, now(), pl.account, o.price))
	local id = 0
	if paid == 1 then
		if db.query(string.format("INSERT INTO `%s` (`account_id`, `player_id`, `offer`, `limit_key`, `week`, `price`, `state`, " ..
				"`detail`, `created`) VALUES (%d, %d, %s, %s, %d, %d, 0, %s, %d)", T.purchases, pl.account, pl.guid,
				db.escapeString(o.key), db.escapeString(K.limitKey(o)), week, o.price, db.escapeString(detail), now())) then
			id = db.lastInsertId and tonumber(db.lastInsertId()) or 0
		end
	end
	if paid ~= 1 or id <= 0 then
		db.query("ROLLBACK")
		M.accounts[pl.account] = nil -- read the balance again
		return result(player, false, msg(player, paid ~= 1 and "balance" or "failed", o.price))
	end
	db.query("COMMIT")
	acc.balance, acc.spent = acc.balance - o.price, acc.spent + o.price
	used[K.limitKey(o)] = (used[K.limitKey(o)] or 0) + 1
	local extra = ""
	if items then
		-- 3a. items and the mark in one save
		if giveItems(player, items) then
			extra = " " .. msg(player, "inbox")
		end
		player:setStorageValue(ST, id)
		if Chaos.saveCharacter(player) then
			setState(id, 1)
		end -- else: pending; the next save (or the login recovery) settles it
	else
		-- 3b. the mark saved first, then the call
		player:setStorageValue(ST, id)
		local delivered, why = false, nil
		if Chaos.saveCharacter(player) then
			delivered, why = deliverApi(player, pl, o)
		end
		if not delivered then
			refund(pl, id, o.price)
			return result(player, false, msg(player, "unavailable") .. (why and (" " .. Chaos.t(player, why)) or ""))
		end
		setState(id, 1)
	end
	local name = Chaos.t(player, o.name)
	name = o.bossName and (name .. ": " .. o.bossName) or name
	log(string.format("%s (account %d) bought %s for %d (purchase %d)", player:getName(), pl.account, o.key, o.price, id))
	return result(player, true, msg(player, "bought", name, o.price) .. extra)
end

function M.buy(player, d)
	local guid = player:getGuid()
	if M.busy[guid] then
		return result(player, false, msg(player, "busy"))
	end
	M.busy[guid] = true
	local ok, res = pcall(buyNow, player, type(d) == "table" and d or {})
	M.busy[guid] = nil
	if not ok then
		log("buy: " .. tostring(res))
		return result(player, false, msg(player, "failed"))
	end
	return res
end

-- ---------------------------------------------------------------- login recovery
function M.recover(player)
	local pl = M.track(player)
	local rows = Chaos.select(string.format("SELECT `id`, `price`, `detail` FROM `%s` WHERE `player_id` = %d AND `state` = 0 " ..
		"ORDER BY `id`", T.purchases, pl.guid), {{"id", "n"}, {"price", "n"}, {"detail", "s"}})
	if #rows == 0 then
		return
	end
	local plan = K.recover(rows, player:getStorageValue(ST))
	for _, r in ipairs(plan.done) do
		setState(r.id, 1)
	end
	for _, r in ipairs(plan.deliver) do
		local items = itemsFromDetail(r.detail)
		if items then
			giveItems(player, items)
			player:setStorageValue(ST, r.id)
			if Chaos.saveCharacter(player) then
				setState(r.id, 1)
			end
			log(string.format("purchase %d delivered to %s at login (after a crash)", r.id, player:getName()))
		else
			refund(pl, r.id, K.int(r.price))
			log(string.format("purchase %d of %s refunded at login (after a crash)", r.id, player:getName()))
		end
	end
end

-- ---------------------------------------------------------------- the NPC
function M.placeNpcs()
	local placed, missed = 0, {}
	for _, id in ipairs(cfg.npc.towns) do
		local town = Town(id)
		local temple = town and town:getTemplePosition()
		if temple and try("place npc", ChaosNpcPlace.place, cfg.npc.name, temple, cfg.npc.offsets) then
			placed = placed + 1
		else
			missed[#missed + 1] = tostring(id)
		end
	end
	if #missed > 0 then
		log("no " .. cfg.npc.name .. " in town " .. table.concat(missed, ", ") .. " (no free tile near the temple, or " ..
			"data/npc/" .. cfg.npc.name .. ".xml is missing: tools/install_candlemarks.py)")
	end
	return placed
end

-- ---------------------------------------------------------------- events
local startup = GlobalEvent("ChaosCandlemarksStartup")
function startup.onStartup()
	for _, p in ipairs(K.validate(cfg)) do
		log("config: " .. p)
	end
	try("tables", M.ensureTables)
	if cfg.enabled then
		addEvent(function()
			log(M.placeNpcs() .. " " .. cfg.npc.name .. "(s) placed")
		end, cfg.npc.delayMs or 3000)
	end
	return true
end
startup:register()

local tick = GlobalEvent("ChaosCandlemarksTick")
function tick.onThink(interval)
	try("tick", M.tick)
	return true
end
tick:interval(cfg.tickSeconds * 1000)
tick:register()

local login = CreatureEvent("ChaosCandlemarksLogin")
function login.onLogin(player)
	player:registerEvent("ChaosCandlemarksExtended")
	player:registerEvent("ChaosCandlemarksLogout")
	if cfg.enabled then
		try("track", M.track, player)
		try("recover", M.recover, player)
		try("hud", M.sendHud, player)
	end
	return true
end
login:type("login")
login:register()

local logout = CreatureEvent("ChaosCandlemarksLogout")
function logout.onLogout(player)
	local cid = player:getId()
	local pl = M.players[cid]
	if pl then
		try("flush", flushProgress, pl)
		M.players[cid] = nil
		if not accountOnline(pl.account, cid) then
			M.accounts[pl.account], M.used[pl.account] = nil, nil
		end
		M.busy[pl.guid], M.earners[pl.guid], M.why[pl.guid] = nil, nil, nil
	end
	return true
end
logout:type("logout")
logout:register()

local ext = CreatureEvent("ChaosCandlemarksExtended")
function ext.onExtendedOpcode(player, opcode, buffer)
	if opcode ~= OPCODE or not cfg.enabled then
		return
	end
	local m = Chaos.decode(buffer)
	if not m or type(m.action) ~= "string" then
		return
	end
	local d = type(m.data) == "table" and m.data or {}
	if m.action == "open" then
		if Chaos.limited(player, "candlemarks", cfg.requestMs) then
			return
		end
		try("send", M.send, player)
	elseif m.action == "buy" then
		if Chaos.limited(player, "candlemarks.buy", cfg.buyMs) then
			return
		end
		try("buy", M.buy, player, d)
		try("send", M.send, player)
		try("hud", M.sendHud, player)
	end
end
ext:type("extendedopcode")
ext:register()

-- staff: /candlemarks Name | /candlemarks Name, give N | take N | refund <purchase id>
local talk = TalkAction("/candlemarks")
function talk.onSay(player, words, param)
	local name, what, n = param:match("^%s*([^,]+),%s*(%a+)%s+(%d+)%s*$")
	local economy = what ~= nil
	local allowed, staff = Chaos.staffCommand(player, words, param, economy)
	if not allowed then
		return not staff
	end
	if economy and player:getGroup():getId() < Chaos.economyMinGroup then
		return false
	end
	if not economy and player:getGroup():getId() < cfg.staffGroup then
		return false
	end
	local target = Player(name or param:match("^%s*(.-)%s*$"))
	if not target then
		player:sendTextMessage(MESSAGE_INFO_DESCR, "/candlemarks <online character>[, give <n> | take <n> | refund <purchase id>]")
		return false
	end
	local pl = M.track(target)
	local acc = M.account(pl.account)
	n = tonumber(n) or 0
	if what == "give" and n > 0 and n <= 100000 then
		db.query(string.format("UPDATE `%s` SET `balance` = `balance` + %d WHERE `account_id` = %d", T.accounts, n, pl.account))
		acc.balance = acc.balance + n
	elseif what == "take" and n > 0 and n <= 100000 then
		local taken = math.min(n, acc.balance)
		db.query(string.format("UPDATE `%s` SET `balance` = GREATEST(0, `balance` - %d) WHERE `account_id` = %d", T.accounts,
			taken, pl.account))
		acc.balance = acc.balance - taken
	elseif what == "refund" and n > 0 then
		local row = Chaos.select(string.format("SELECT `id`, `price`, `account_id` FROM `%s` WHERE `id` = %d AND `state` <> 2",
			T.purchases, n), {{"id", "n"}, {"price", "n"}, {"account_id", "n"}})[1]
		if row and row.account_id == pl.account then
			refund(pl, n, K.int(row.price))
		else
			player:sendTextMessage(MESSAGE_INFO_DESCR, "No such purchase of that account (or already refunded).")
			return false
		end
	end
	player:sendTextMessage(MESSAGE_INFO_DESCR, string.format("%s (account %d): %d Candlemarks (earned %d, spent %d), progress %d/%d s, %s.",
		target:getName(), pl.account, acc.balance, acc.earned, acc.spent, pl.progress, K.blockSec(cfg),
		M.earners[pl.guid] and "earning" or ("not earning: " .. tostring(M.why[pl.guid] or "no tick yet"))))
	M.sendHud(target, pl)
	return false
end
talk:separator(" ")
talk:register()
