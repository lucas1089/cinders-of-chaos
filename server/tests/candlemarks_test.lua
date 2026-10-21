-- Run from the server/ folder: luajit tests/candlemarks_test.lua (and lua5.3; CI runs both)
-- Candlemarks (server/README.md "Candlemarks"): the pure rules of candlemarks_core.lua (blocks, the daily cap, who
-- earns with the IP limit, the offers and their guards, the purchase checks, gems, the login recovery, the config
-- checks), the texts in pt-BR, and candlemarks.lua against a mocked engine and a small in-memory database: earning
-- per character into the account balance, the IP limit as characters log in and out, progress kept across a relog,
-- purchases (balance, level, weekly limits, items, the inbox), the write order and the crash recovery, the guarded
-- pocket boss and call offers, refunds, the opcode handler and the staff command.

local checks, failures = 0, 0
local function check(cond, label)
	checks = checks + 1
	if not cond then
		failures = failures + 1
		print("FAIL " .. label)
	end
end
local function eq(a, b, label)
	check(a == b, label .. " (" .. tostring(a) .. " ~= " .. tostring(b) .. ")")
end

local cfg = dofile("data/scripts/chaos/candlemarks_config.lua")
dofile("data/scripts/chaos/candlemarks_core.lua")
local K = ChaosCandlemarksCore

-- ---------------------------------------------------------------- config
local problems = K.validate(cfg)
eq(#problems, 0, "the shipped config is valid: " .. tostring(problems[1]))
eq(cfg.blockMinutes, 30, "one coin per 30 minutes (owner)")
eq(cfg.earn.maxPerIp, 2, "two characters per IP earn (owner)")
eq(cfg.opcode, 176, "opcode")
do
	local function copy(t)
		if type(t) ~= "table" then
			return t
		end
		local o = {}
		for k, v in pairs(t) do
			o[k] = copy(v)
		end
		return o
	end
	local bad = copy(cfg)
	bad.offers[#bad.offers + 1] = {key = "mirror", kind = "item", items = {{29859, 1}}, price = 999, weekly = 1, minLevel = 1,
		name = "x", desc = "x"}
	check(#K.validate(bad) > 0, "a chase orb is refused")
	bad = copy(cfg)
	bad.offers[2].weekly = nil
	check(#K.validate(bad) > 0, "an offer without a weekly limit is refused")
	bad = copy(cfg)
	bad.offers[2].key = bad.offers[1].key
	check(#K.validate(bad) > 0, "a key used twice is refused")
	bad = copy(cfg)
	bad.maxTickSeconds = 4000
	check(#K.validate(bad) > 0, "a tick longer than a block is refused")
end
-- the chase orbs are never sold
local forbidden = {}
for _, id in ipairs(cfg.forbiddenIds) do
	forbidden[id] = true
end
for _, id in ipairs({29859, 29857, 29858}) do
	check(forbidden[id], "chase orb " .. id .. " forbidden")
end
for _, o in ipairs(cfg.offers) do
	for _, it in ipairs(o.items or {}) do
		check(not forbidden[it[1]], o.key .. " sells no forbidden item")
	end
	check(o.weekly >= 1, o.key .. " has a weekly limit")
end

-- every message, offer name and text has a pt-BR entry
local pt = dofile("data/scripts/chaos/i18n_strings.lua")["pt-BR"]
for k, v in pairs(cfg.messages) do
	check(pt[v] ~= nil, "pt-BR for message " .. k)
end
local named = {["3 Orbs of Awakening"] = true, ["Ember Orb"] = true, ["Crown Orb"] = true, ["Orb of Tempering"] = true,
	["Orb of Unmaking"] = true, ["Orb of Grafting"] = true, ["2 Whetstones"] = true, ["10 Rune Shards"] = true}
for _, o in ipairs(cfg.offers) do
	check(pt[o.desc] ~= nil, "pt-BR for the text of " .. o.key)
	check(named[o.name] or pt[o.name] ~= nil, "pt-BR for the name of " .. o.key .. " (item names stay English)")
end

-- ---------------------------------------------------------------- time keys
local wed = os.time({year = 2026, month = 10, day = 14, hour = 12})
eq(K.weekKey(wed, 6), 20261012, "a Wednesday belongs to Monday's week")
eq(K.weekKey(os.time({year = 2026, month = 10, day = 12, hour = 5}), 6), 20261005, "Monday before 06:00: the week before")
eq(K.weekKey(os.time({year = 2026, month = 10, day = 12, hour = 7}), 6), 20261012, "Monday after 06:00: the new week")
eq(K.weekKey(os.time({year = 2026, month = 10, day = 18, hour = 23}), 6), 20261012, "Sunday night: still the week")
eq(K.dayKey(os.time({year = 2026, month = 10, day = 14, hour = 5}), 6), 20261013, "before 06:00: yesterday")
eq(K.dayKey(os.time({year = 2026, month = 10, day = 14, hour = 6}), 6), 20261014, "from 06:00: today")

-- ---------------------------------------------------------------- earning
do
	local acc = K.newAccount()
	local p, coins = 0, 0
	for i = 1, 29 do
		local g
		g, p = K.advance(p, acc, cfg, 60, 1)
		coins = coins + g
	end
	eq(coins, 0, "29 minutes: no coin")
	eq(p, 29 * 60, "29 minutes of progress")
	eq(K.secondsToNext(p, cfg), 60, "a minute to go")
	local g
	g, p = K.advance(p, acc, cfg, 60, 1)
	eq(g, 1, "30 minutes: a coin")
	eq(p, 0, "progress starts again")
	eq(acc.balance, 1, "the account has it")
	eq(acc.earned, 1, "earned counted")
	eq(acc.today, 1, "today counted")
	g, p = K.advance(0, acc, cfg, 3600, 1)
	eq(p, cfg.maxTickSeconds, "a stall credits at most maxTickSeconds")
	g, p = K.advance(100, acc, cfg, -50, 1)
	eq(p, 100, "time going back credits nothing")
	g, p = K.advance(100, acc, cfg, 0 / 0, 1)
	eq(p, 100, "NaN credits nothing")
	-- two characters of one account each add their own coins
	local a2 = K.newAccount()
	local p1, p2 = 0, 600
	for _ = 1, 30 do
		local _
		_, p1 = K.advance(p1, a2, cfg, 60, 1)
		_, p2 = K.advance(p2, a2, cfg, 60, 1)
	end
	eq(a2.balance, 2, "two characters, 30 minutes: two coins for the account")
	eq(p2, 600, "each keeps its own progress")
	-- the daily cap
	local capped = {}
	for k, v in pairs(cfg) do
		capped[k] = v
	end
	capped.earn = {maxPerIp = 2, minLevel = 1, dailyCap = 2}
	local a3 = K.newAccount()
	local p3, total, info = 0, 0, nil
	for _ = 1, 200 do
		local gg
		gg, p3, info = K.advance(p3, a3, capped, 60, 5)
		total = total + gg
	end
	eq(total, 2, "the cap stops at 2 a day")
	check(info.capped, "capped reported")
	local frozen = p3
	_, p3 = K.advance(p3, a3, capped, 60, 5)
	eq(p3, frozen, "progress frozen while capped")
	local gg
	gg, p3 = K.advance(p3, a3, capped, 60, 6)
	eq(a3.today, 0, "a new day resets the day's count")
	check(p3 > frozen or gg > 0, "and the progress moves again")
end

-- ---------------------------------------------------------------- who earns
do
	local function c(guid, ip, loginAt, extra)
		local t = {guid = guid, ip = ip, level = 50, staff = false, loginAt = loginAt}
		for k, v in pairs(extra or {}) do
			t[k] = v
		end
		return t
	end
	local e, why = K.pickEarners({c(1, 77, 10), c(2, 77, 20), c(3, 77, 30)}, cfg)
	check(e[1] and e[2], "the first two logins of an IP earn")
	check(not e[3], "the third does not")
	eq(why[3], "ip", "because of the IP limit")
	e = K.pickEarners({c(2, 77, 20), c(3, 77, 30)}, cfg)
	check(e[2] and e[3], "when the first logs out, the next in order earns")
	e = K.pickEarners({c(3, 77, 30), c(1, 77, 10), c(2, 77, 20)}, cfg)
	check(e[1] and e[2] and not e[3], "order of the list does not matter")
	e = K.pickEarners({c(9, 77, 10), c(4, 77, 10), c(5, 77, 10)}, cfg)
	check(e[4] and e[5] and not e[9], "same login time: the lower character ids")
	e = K.pickEarners({c(1, 77, 10), c(2, 77, 20), c(3, 88, 30), c(4, 99, 40)}, cfg)
	check(e[1] and e[2] and e[3] and e[4], "other IPs are independent")
	e = K.pickEarners({c(1, 0, 10), c(2, 0, 20), c(3, 0, 30)}, cfg)
	check(e[1] and e[2] and e[3], "no connection (IP 0): not limited")
	e, why = K.pickEarners({c(1, 77, 10, {staff = true}), c(2, 77, 20), c(3, 77, 30)}, cfg)
	check(not e[1] and e[2] and e[3], "staff do not earn and take no IP place")
	eq(why[1], "staff", "staff reason")
	local low = {}
	for k, v in pairs(cfg) do
		low[k] = v
	end
	low.earn = {maxPerIp = 2, minLevel = 20, dailyCap = 0}
	e, why = K.pickEarners({c(1, 77, 10, {level = 5}), c(2, 77, 20)}, low)
	check(not e[1] and e[2], "minLevel")
	eq(why[1], "level", "level reason")
	-- one account, several characters (several machines): all earn (owner: no one-per-account rule)
	e = K.pickEarners({c(1, 11, 10, {account = 5}), c(2, 12, 10, {account = 5})}, cfg)
	check(e[1] and e[2], "two characters of one account on two IPs both earn")
end

-- ---------------------------------------------------------------- the shop
do
	local list, byKey = K.offers(cfg, {})
	check(byKey.orb_tempering ~= nil, "item offers are always on sale")
	check(byKey.gem_chipped ~= nil, "gem offers too")
	check(byKey.rested_vial == nil, "a call offer is hidden while its API is missing")
	for _, o in ipairs(list) do
		check(o.kind ~= "pocketboss", "no pocket boss offer without the API")
		check(o.kind ~= "cosmetic", "cosmetic offers are hidden without the cosmetics API")
	end
	local bosses = K.bosses({{key = "rotking", name = "The Rot King"}, {key = "ashwyrm", name = "Ashwyrm"}, {key = "bad key!"}, 5})
	eq(#bosses, 3, "bosses: bad keys skipped, numbers become keys")
	eq(bosses[1].key, "5", "sorted by key")
	eq(K.bosses({ashwyrm = "Ashwyrm", rotking = {name = "The Rot King"}})[2].name, "The Rot King", "bosses from a map")
	eq(#K.bosses("garbage"), 0, "bosses: garbage")
	list, byKey = K.offers(cfg, {bosses = K.bosses({{key = "rotking", name = "The Rot King"}, {key = "ashwyrm"}}),
		has = function(call) return call[1] == "ChaosRested" end})
	local pb = byKey["pocket_charge.rotking"]
	check(pb ~= nil, "one pocket boss offer per boss")
	eq(pb.boss, "rotking", "its boss")
	eq(K.limitKey(pb), "pocket_charge", "every boss shares the weekly limit")
	eq(K.limitKey(byKey["pocket_charge.ashwyrm"]), "pocket_charge", "shared")
	check(byKey.rested_vial ~= nil, "a call offer lights up when its API exists")
	check(byKey.bounty_reroll == nil, "others stay hidden")
	eq(K.limitKey(byKey.supplies_2), "supplies", "the supply bundles share one limit")

	local o = byKey.orb_tempering
	local base = {enabled = true, balance = 100, level = 100, used = 0, near = true}
	local function ctx(over)
		local t = {}
		for k, v in pairs(base) do
			t[k] = v
		end
		for k, v in pairs(over or {}) do
			t[k] = v
		end
		return t
	end
	check(K.checkBuy(o, ctx(), cfg), "a valid purchase")
	eq(select(2, K.checkBuy(o, ctx({enabled = false}), cfg)), "disabled", "disabled")
	eq(select(2, K.checkBuy(nil, ctx(), cfg)), "unknown", "unknown offer")
	eq(select(2, K.checkBuy(o, ctx({busy = true}), cfg)), "busy", "busy")
	local r, a
	_, r, a = K.checkBuy(o, ctx({level = 10}), cfg)
	eq(r, "level", "level")
	eq(a, o.minLevel, "level argument")
	eq(select(2, K.checkBuy(o, ctx({used = o.weekly}), cfg)), "weekly", "weekly limit")
	_, r, a = K.checkBuy(o, ctx({balance = o.price - 1}), cfg)
	eq(r, "balance", "balance")
	eq(a, o.price, "balance argument")
	eq(select(2, K.checkBuy(o, ctx({owned = true}), cfg)), "owned", "owned")
	local near = {}
	for k, v in pairs(cfg) do
		near[k] = v
	end
	near.npc = {buyNearNpc = true}
	eq(select(2, K.checkBuy(o, ctx({near = false}), near)), "npc", "buyNearNpc without the NPC")
	check(cfg.npc.buyNearNpc == true, "owner: purchases only at Osric")
	eq(cfg.messages.npc, "Visit Osric the Chandler to buy (at the temple).", "the message")
	check(K.checkBuy(o, ctx({near = true}), near), "buyNearNpc with the NPC")

	local items = K.itemsOf(byKey.supplies_1)
	eq(#items, 2, "a bundle gives two stacks")
	eq(items[1].id, 7618, "health potions")
	eq(items[1].count, 50, "50 of them")
	local g = K.itemsOf(byKey.gem_flawed, function(n) return 3 end, 7, 32001)
	eq(g[1].id, 32000 + 2 * 5 + 2, "a Flawed gem of type 3 (32000 + (type - 1) * 5 + tier)")
	g = K.itemsOf(byKey.gem_chipped, function(n) return 99 end, 7, 32001)
	eq(g[1].id, 32000 + 6 * 5 + 1, "a random type out of range is clamped")

	local plan = K.recover({{id = 5}, {id = 9}, {id = 7}, {id = 12}}, 7)
	eq(#plan.done, 2, "rows at or under the mark were delivered")
	eq(#plan.deliver, 2, "rows over the mark were not")
	eq(plan.deliver[1].id, 9, "in id order")
	eq(#K.recover({{id = 1}}, -1).deliver, 1, "no mark yet: deliver")

	local view = K.view({balance = 7, today = 2}, 300, list, {pocket_charge = 1}, {earning = true, level = 60,
		icon = function() return 42 end, weekEnds = 100, tr = function(t) return "<" .. t .. ">" end}, cfg)
	eq(view.balance, 7, "view balance")
	eq(view.progress, 300, "view progress")
	eq(view.block, 1800, "view block")
	check(view.earning, "view earning")
	local first = view.offers[1]
	eq(first.u, 1, "view: the shared weekly use")
	eq(first.b, "ashwyrm", "view: the boss name (not translated; no name: the key)")
	eq(first.n, "<Pocket Boss Charge>", "view: names through tr")
	eq(first.c, 42, "view icon")
end

-- ---------------------------------------------------------------- the engine, against a mocked engine and database
MESSAGE_STATUS_SMALL, MESSAGE_EVENT_ADVANCE, MESSAGE_INFO_DESCR, MESSAGE_STATUS_DEFAULT = 1, 2, 3, 4
RETURNVALUE_NOERROR, INDEX_WHEREEVER, FLAG_NOLIMIT = 0, -1, 1

-- the database: the tables of candlemarks.lua, kept in Lua, read from its own queries
local DB = {accounts = {}, progress = {}, purchases = {}, nextId = 0, rowCount = 0, tx = nil, log = {}, failInsert = false}
local function snapshot()
	local function cp(t)
		local o = {}
		for k, v in pairs(t) do
			o[k] = type(v) == "table" and cp(v) or v
		end
		return o
	end
	return {accounts = cp(DB.accounts), progress = cp(DB.progress), purchases = cp(DB.purchases), nextId = DB.nextId}
end
local results, nextResult = {}, 0
local function store(rows)
	if #rows == 0 then
		return false
	end
	nextResult = nextResult + 1
	results[nextResult] = {rows = rows, i = 1}
	return nextResult
end
local function unq(s)
	return (s:gsub("^'", ""):gsub("'$", ""):gsub("\\'", "'"))
end
db = {
	escapeString = function(s) return "'" .. tostring(s):gsub("\\", "\\\\"):gsub("'", "\\'") .. "'" end,
	lastInsertId = function() return DB.nextId end,
	query = function(q)
		DB.log[#DB.log + 1] = q
		if q == "START TRANSACTION" then
			DB.tx = snapshot()
			return true
		elseif q == "COMMIT" then
			DB.tx = nil
			return true
		elseif q == "ROLLBACK" then
			if DB.tx then
				DB.accounts, DB.progress, DB.purchases, DB.nextId = DB.tx.accounts, DB.tx.progress, DB.tx.purchases, DB.tx.nextId
			end
			DB.tx = nil
			return true
		elseif q:find("^CREATE TABLE") then
			return true
		end
		local acc = tonumber(q:match("^INSERT IGNORE INTO `chaos_candlemarks` %(`account_id`, `updated`%) VALUES %((%d+),"))
		if acc then
			DB.accounts[acc] = DB.accounts[acc] or {balance = 0, earned = 0, spent = 0, day = 0, today = 0}
			return true
		end
		local pid, aid, prog = q:match("^INSERT INTO `chaos_candlemark_progress` .- VALUES %((%d+), (%d+), (%d+),")
		if pid then
			DB.progress[tonumber(pid)] = tonumber(prog)
			return true
		end
		local n1, n2, day, today, a = q:match("^UPDATE `chaos_candlemarks` SET `balance` = `balance` %+ (%d+), `earned` = `earned` %+ (%d+), `day` = (%d+), `today` = (%d+), .-WHERE `account_id` = (%d+)")
		if n1 then
			local r = DB.accounts[tonumber(a)]
			r.balance, r.earned, r.day, r.today = r.balance + tonumber(n1), r.earned + tonumber(n2), tonumber(day), tonumber(today)
			return true
		end
		local p1, p2, a2, p3 = q:match("^UPDATE `chaos_candlemarks` SET `balance` = `balance` %- (%d+), `spent` = `spent` %+ (%d+), .-WHERE `account_id` = (%d+) AND `balance` >= (%d+)")
		if p1 then
			local r = DB.accounts[tonumber(a2)]
			if r and r.balance >= tonumber(p3) then
				r.balance, r.spent = r.balance - tonumber(p1), r.spent + tonumber(p2)
				DB.rowCount = 1
			else
				DB.rowCount = 0
			end
			return true
		end
		local r1, r2, a3 = q:match("^UPDATE `chaos_candlemarks` SET `balance` = `balance` %+ (%d+), `spent` = `spent` %- (%d+) WHERE `account_id` = (%d+)")
		if r1 then
			local r = DB.accounts[tonumber(a3)]
			r.balance, r.spent = r.balance + tonumber(r1), r.spent - tonumber(r2)
			return true
		end
		local g1, a4 = q:match("^UPDATE `chaos_candlemarks` SET `balance` = `balance` %+ (%d+) WHERE `account_id` = (%d+)")
		if g1 then
			DB.accounts[tonumber(a4)].balance = DB.accounts[tonumber(a4)].balance + tonumber(g1)
			return true
		end
		local t1, a6 = q:match("^UPDATE `chaos_candlemarks` SET `balance` = GREATEST%(0, `balance` %- (%d+)%) WHERE `account_id` = (%d+)")
		if t1 then
			local r = DB.accounts[tonumber(a6)]
			r.balance = math.max(0, r.balance - tonumber(t1))
			return true
		end
		local vals = q:match("^INSERT INTO `chaos_candlemark_purchases` .- VALUES %((.*)%)$")
		if vals then
			if DB.failInsert then
				return false
			end
			local a5, g, offer, limit, week, price, state, detail, created =
				vals:match("^(%d+), (%d+), ('.-'), ('.-'), (%d+), (%d+), (%d+), ('.-'), (%d+)$")
			DB.nextId = DB.nextId + 1
			DB.purchases[DB.nextId] = {id = DB.nextId, account_id = tonumber(a5), player_id = tonumber(g), offer = unq(offer),
				limit_key = unq(limit), week = tonumber(week), price = tonumber(price), state = tonumber(state), detail = unq(detail)}
			return true
		end
		local st, id, only0 = q:match("^UPDATE `chaos_candlemark_purchases` SET `state` = (%d+), `done_at` = %d+ WHERE `id` = (%d+)( ?A?N?D?.*)$")
		if st then
			local r = DB.purchases[tonumber(id)]
			if r and (only0 == "" or r.state == 0) then
				r.state = tonumber(st)
			end
			return true
		end
		error("unexpected query: " .. q)
	end,
	storeQuery = function(q)
		DB.log[#DB.log + 1] = q
		if q == "SELECT ROW_COUNT() AS `n`" then
			return store({{n = DB.rowCount}})
		end
		local a = tonumber(q:match("FROM `chaos_candlemarks` WHERE `account_id` = (%d+)"))
		if a then
			local r = DB.accounts[a]
			return store(r and {{balance = r.balance, earned = r.earned, spent = r.spent, day = r.day, today = r.today}} or {})
		end
		local pid = tonumber(q:match("FROM `chaos_candlemark_progress` WHERE `player_id` = (%d+)"))
		if pid then
			return store(DB.progress[pid] and {{progress = DB.progress[pid]}} or {})
		end
		local a2, week = q:match("FROM `chaos_candlemark_purchases` WHERE `account_id` = (%d+) AND `week` = (%d+)")
		if a2 then
			local counts = {}
			for _, r in pairs(DB.purchases) do
				if r.account_id == tonumber(a2) and r.week == tonumber(week) and r.state ~= 2 then
					counts[r.limit_key] = (counts[r.limit_key] or 0) + 1
				end
			end
			local rows = {}
			for k, n in pairs(counts) do
				rows[#rows + 1] = {limit_key = k, n = n}
			end
			return store(rows)
		end
		local g = tonumber(q:match("FROM `chaos_candlemark_purchases` WHERE `player_id` = (%d+) AND `state` = 0"))
		if g then
			local rows = {}
			for _, r in pairs(DB.purchases) do
				if r.player_id == g and r.state == 0 then
					rows[#rows + 1] = {id = r.id, price = r.price, detail = r.detail}
				end
			end
			table.sort(rows, function(x, y) return x.id < y.id end)
			return store(rows)
		end
		local id = tonumber(q:match("FROM `chaos_candlemark_purchases` WHERE `id` = (%d+) AND `state` <> 2"))
		if id then
			local r = DB.purchases[id]
			return store(r and r.state ~= 2 and {{id = r.id, price = r.price, account_id = r.account_id}} or {})
		end
		error("unexpected select: " .. q)
	end
}
result = {
	getNumber = function(id, col) local r = results[id]; return tonumber(r.rows[r.i][col]) or 0 end,
	getString = function(id, col) local r = results[id]; return tostring(r.rows[r.i][col] or "") end,
	next = function(id) local r = results[id]; r.i = r.i + 1; return r.i <= #r.rows end,
	free = function(id) results[id] = nil end
}

local registry = {}
local function deep(t)
	if type(t) ~= "table" then
		return t
	end
	local o = {}
	for k, v in pairs(t) do
		o[k] = deep(v)
	end
	return o
end
json = {
	encode = function(t) registry[#registry + 1] = deep(t); return "J" .. #registry end,
	decode = function(s) return deep(registry[tonumber(tostring(s):match("^J(%d+)$") or -1)]) end
}
local events, globalEvents, talks = {}, {}, {}
CreatureEvent = function(name)
	local e = {register = function() end, type = function() end}
	events[name] = e
	return e
end
GlobalEvent = function(name)
	local e = {register = function() end, interval = function(self, ms) self.ms = ms end}
	globalEvents[name] = e
	return e
end
TalkAction = function(words)
	local t = {separator = function() end, register = function() end}
	talks[words] = t
	return t
end
addEvent = function() end
ItemType = function(id) return {getClientId = function() return id - 20000 end} end
Town = function() return nil end

npcsAround = {}
local function osricAt(x, y, z)
	local n = {pos = {x = x, y = y, z = z}}
	function n:isNpc() return true end
	function n:getName() return "Osric the Chandler" end
	function n:getPosition() return self.pos end
	npcsAround = {n}
end
local online = {}
Game = {
	getPlayers = function()
		local out = {}
		for _, p in ipairs(online) do
			out[#out + 1] = p
		end
		return out
	end,
	getSpectators = function(pos, multi, onlyPlayers, a, b, c, d)
		local out = {}
		for _, n in ipairs(npcsAround) do
			if n.pos.z == pos.z and math.abs(n.pos.x - pos.x) <= a and math.abs(n.pos.y - pos.y) <= c then
				out[#out + 1] = n
			end
		end
		return out
	end
}
local byId = {}
Player = function(x)
	if type(x) == "table" then
		return x
	end
	if type(x) == "number" then
		return byId[x]
	end
	for _, p in ipairs(online) do
		if p.name == x then
			return p
		end
	end
	return nil
end

local saveOk = true
local function newPlayer(guid, account, ip, level, group)
	local p = {guid = guid, id = 0x10000000 + guid, account = account, ip = ip, level = level or 100, group = group or 1,
		storage = {}, items = {}, inbox = {}, messages = {}, name = "Char" .. guid, room = 1000, saved = {}}
	function p:getId() return self.id end
	function p:getGuid() return self.guid end
	function p:getName() return self.name end
	function p:getAccountId() return self.account end
	function p:getIp() return self.ip end
	function p:getLevel() return self.level end
	function p:getPosition() return {x = 100, y = 100, z = 7} end
	function p:getGroup()
		local me = self
		return {getId = function() return me.group end, getAccess = function() return me.group >= 4 end}
	end
	function p:getStorageValue(k) return self.storage[k] or -1 end
	function p:setStorageValue(k, v) self.storage[k] = v end
	function p:getItemCount(id) return self.items[id] or 0 end
	function p:addItem(id, count)
		local n = math.min(count, self.room)
		self.room = self.room - n
		self.items[id] = (self.items[id] or 0) + n
	end
	function p:getInbox()
		local me = self
		return {addItem = function(_, id, n) me.inbox[id] = (me.inbox[id] or 0) + n end}
	end
	function p:save()
		if saveOk then
			-- what a save writes: the storages (the mark) and the items
			self.saved = {mark = self.storage[7102460], items = deep(self.items)}
		end
		return saveOk
	end
	function p:sendTextMessage(t, text) self.messages[#self.messages + 1] = text end
	function p:registerEvent() end
	return p
end

dofile("data/scripts/chaos/chaos_constants.lua")
local sent = {}
Chaos.send = function(player, op, action, data)
	sent[#sent + 1] = {to = player, op = op, action = action, data = deep(data)}
	return true
end
Chaos.sendChunked = function(player, op, text)
	local m = json.decode(text)
	sent[#sent + 1] = {to = player, op = op, action = m.action, data = m.data}
	return true
end
local limited = false
ChaosRateLimit = {allow = function() return not limited end}
Chaos.t = function(player, key, ...)
	if select("#", ...) > 0 then
		return string.format(key, ...)
	end
	return key
end

dofile("data/scripts/chaos/candlemarks.lua")
local M = ChaosCandlemarks
eq(ChaosOpcodes.candlemarks, 176, "opcode constant")
for _, taken in ipairs({1, 67, 73, 89, 91, 92, 99, 106, 107, 136, 181, 201, 202, 140, 144, 145, 146, 210, 212, 213, 230, 246}) do
	check(taken ~= ChaosOpcodes.candlemarks, "opcode free of " .. taken)
end
for name, v in pairs(ChaosOpcodes) do
	check(name == "candlemarks" or v ~= ChaosOpcodes.candlemarks, "opcode not shared with " .. name)
end
for name, v in pairs(Chaos.storage) do
	if type(v) == "number" then
		check(v < 7102460 or v > 7102469, "storage block free of " .. name)
	end
end
eq(globalEvents.ChaosCandlemarksTick.ms, 60000, "the tick runs every minute")

local function lastSent(player, action)
	for i = #sent, 1, -1 do
		if sent[i].to == player and sent[i].action == action then
			return sent[i].data
		end
	end
	return nil
end
local function login(p)
	online[#online + 1] = p
	byId[p.id] = p
	events.ChaosCandlemarksLogin.onLogin(p)
end
local function logout(p)
	events.ChaosCandlemarksLogout.onLogout(p)
	for i, q in ipairs(online) do
		if q == p then
			table.remove(online, i)
			break
		end
	end
	byId[p.id] = nil
end
local function minutes(n)
	for _ = 1, n do
		M.clockShift = M.clockShift + 60
		M.tick()
	end
end
local function op(p, action, data)
	events.ChaosCandlemarksExtended.onExtendedOpcode(p, 176, json.encode({action = action, data = data}))
end

-- earning: three characters on one IP, one on another
local a = newPlayer(1, 100, 77)
local b = newPlayer(2, 100, 77) -- same account, same IP
local c = newPlayer(3, 200, 77) -- third on the IP
local d = newPlayer(4, 300, 88)
login(a)
M.clockShift = M.clockShift + 1
login(b)
M.clockShift = M.clockShift + 1
login(c)
login(d)
check(DB.accounts[100] ~= nil, "login makes the account row")
check(lastSent(a, "hud") ~= nil, "login sends the counter")
minutes(30)
eq(DB.accounts[100].balance, 2, "two characters of one account: two coins in 30 minutes")
eq(DB.accounts[200] and DB.accounts[200].balance or 0, 0, "the third character on the IP earns nothing")
eq(DB.accounts[300].balance, 1, "another IP earns")
check(DB.progress[1] ~= nil and DB.progress[1] < 60, "the progress is written with the coin (a few seconds past the block)")
check(a.messages[#a.messages]:find("You earned a Candlemark", 1, true) ~= nil, "a message at the coin")
local hud = lastSent(c, "hud")
eq(hud.e, false, "the counter shows: not earning")
eq(hud.w, "ip", "because of the IP limit")
-- the first logs out: the third starts at the next tick
logout(a)
minutes(1)
eq(lastSent(c, "hud").e, true, "the next login of the IP earns once one logs out")
minutes(29)
eq(DB.accounts[200].balance, 1, "and gets its coin after 30 minutes")
-- the progress survives a relog
minutes(10)
logout(c)
eq(DB.progress[3], 600, "logout writes the progress")
login(c)
eq(M.players[c.id].progress, 600, "relog keeps the progress")
minutes(20)
eq(DB.accounts[200].balance, 2, "the coin comes 20 minutes after the relog")

-- staff never earn
local gm = newPlayer(9, 900, 99, 100, 5)
login(gm)
minutes(30)
eq(DB.accounts[900].balance, 0, "staff earn nothing")
logout(gm)

-- ---------------------------------------------------------------- buying
login(a)
-- far from Osric: the window works, buying does not
DB.accounts[100].balance = DB.accounts[100].balance + 50
M.accounts[100] = nil
op(a, "open", {})
eq(lastSent(a, "state").near, false, "the state says Osric is not here")
op(a, "buy", {k = "gem_chipped"})
eq(lastSent(a, "result").text, "Visit Osric the Chandler to buy (at the temple).", "buying away from Osric is refused")
osricAt(103, 100, 6)
op(a, "buy", {k = "gem_chipped"})
eq(lastSent(a, "result").ok, false, "Osric on another floor does not count")
osricAt(104, 100, 7)
op(a, "buy", {k = "gem_chipped"})
eq(lastSent(a, "result").ok, false, "Osric 4 tiles away is too far (range 3)")
eq(DB.nextId, 0, "nothing written while refused")
DB.accounts[100].balance = DB.accounts[100].balance - 50
M.accounts[100] = nil
osricAt(103, 97, 7)
local before = DB.accounts[100].balance
op(a, "open", {})
local st = lastSent(a, "state")
eq(st.near, true, "near Osric (3 tiles, diagonal)")
check(st ~= nil and #st.offers > 0, "open sends the shop")
eq(st.balance, before, "with the account's balance")
-- not enough
DB.accounts[100].balance, M.accounts[100].balance = 1, 1
op(a, "buy", {k = "orb_tempering"})
eq(lastSent(a, "result").ok, false, "not enough Candlemarks")
eq(DB.accounts[100].balance, 1, "nothing taken")
-- staff give (group 5)
talks["/candlemarks"].onSay(gm, "/candlemarks", "Char1, give 100")
eq(DB.accounts[100].balance, 101, "staff give")
eq(M.accounts[100].balance, 101, "and in memory")
-- a purchase
op(a, "buy", {k = "orb_tempering"})
local res = lastSent(a, "result")
check(res.ok, "bought: " .. tostring(res.text))
eq(a.items[32251], 1, "the orb is in the backpack")
eq(DB.accounts[100].balance, 101 - 8, "the price is taken")
eq(DB.accounts[100].spent, 8, "spent counted")
local id = DB.nextId
eq(DB.purchases[id].state, 1, "the row is done")
eq(a.storage[7102460], id, "the delivery mark")
eq(a.saved.mark, id, "saved with the items")
eq(a.saved.items[32251], 1, "the items in the same save")
-- the write order: the debit and the row in one transaction before anything is given
do
	local iStart, iUpdate, iInsert, iCommit
	for i, q in ipairs(DB.log) do
		if q == "START TRANSACTION" then iStart = i end
		if q:find("`balance` = `balance` %- 8") then iUpdate = i end
		if q:find("^INSERT INTO `chaos_candlemark_purchases`") then iInsert = i end
		if q == "COMMIT" and iInsert and not iCommit and i > iInsert then iCommit = i end
	end
	check(iStart and iUpdate and iInsert and iCommit and iStart < iUpdate and iUpdate < iInsert and iInsert < iCommit,
		"debit and purchase row in one transaction")
end
-- level
a.level = 10
op(a, "buy", {k = "orb_tempering"})
eq(lastSent(a, "result").ok, false, "level refused")
a.level = 100
-- weekly limit (5 a week for Tempering)
for _ = 1, 6 do
	op(a, "buy", {k = "orb_tempering"})
end
eq(a.items[32251], 5, "five a week")
eq(lastSent(a, "result").text, "Weekly limit reached for that offer.", "the sixth is refused")
-- the supply bundles share their limit
op(a, "buy", {k = "supplies_1"})
eq(a.items[7618], 50, "bundle: health potions")
eq(a.items[7620], 50, "bundle: mana potions")
-- the backpack is full: the rest to the inbox
a.room = 10
op(a, "buy", {k = "supplies_1"})
eq(a.inbox[7618], 40, "the rest went to the inbox")
check(lastSent(a, "result").text:find("inbox", 1, true) ~= nil, "and the message says so")
a.room = 1000
-- garbage requests
op(a, "buy", {k = string.rep("x", 500)})
eq(lastSent(a, "result").ok, false, "a long key")
op(a, "buy", {k = 5})
eq(lastSent(a, "result").ok, false, "a number key")
op(a, "buy", "x")
eq(lastSent(a, "result").ok, false, "data not a table")
-- rate limit: nothing happens
local n0 = #DB.log
limited = true
op(a, "buy", {k = "gem_chipped"})
op(a, "open", {})
limited = false
eq(#DB.log, n0, "a limited request touches no database")
-- a gem
op(a, "buy", {k = "gem_chipped"})
local gem
for gid = 32001, 32035 do
	if a.items[gid] then
		gem = gid
	end
end
check(gem ~= nil and (gem - 32001) % 5 == 0, "a Chipped gem of some type")

-- a failed insert rolls the debit back
DB.failInsert = true
local bal = DB.accounts[100].balance
op(a, "buy", {k = "gem_chipped"})
DB.failInsert = false
eq(lastSent(a, "result").ok, false, "a failed write refuses")
eq(DB.accounts[100].balance, bal, "and the debit is rolled back")

-- ---------------------------------------------------------------- crash recovery
-- 1. the save after the delivery fails, the server crashes: the items and the mark are lost together
saveOk = false
op(a, "buy", {k = "whetstone"})
saveOk = true
local crashId = DB.nextId
eq(DB.purchases[crashId].state, 0, "a failed save leaves the row pending")
-- the crash: memory gone, the character as it was saved
a.items, a.storage[7102460] = deep(a.saved.items), a.saved.mark
M.players, M.accounts, M.used = {}, {}, {}
online, byId = {}, {}
login(a)
eq(a.items[32256], 2, "the login delivers the lost purchase once")
eq(DB.purchases[crashId].state, 1, "and settles the row")
eq(a.storage[7102460], crashId, "with the mark")
-- 2. saved but the row update was lost: no second delivery
op(a, "buy", {k = "whetstone"})
local id2 = DB.nextId
DB.purchases[id2].state = 0
M.players, M.accounts, M.used = {}, {}, {}
online, byId = {}, {}
local whet = a.items[32256]
login(a)
eq(a.items[32256], whet, "a saved delivery is not given again")
eq(DB.purchases[id2].state, 1, "its row is settled")

-- ---------------------------------------------------------------- guarded offers
op(a, "open", {})
for _, o in ipairs(lastSent(a, "state").offers) do
	check(o.kind ~= "pocketboss" and o.k ~= "rested_vial", "no API: no pocket boss or vial offer")
end
local charges = {}
ChaosPocketBoss = {
	bosses = function() return {{key = "rotking", name = "The Rot King"}} end,
	addCharges = function(player, key, n) charges[#charges + 1] = {player = player, key = key, n = n}; return true end
}
local vialOk = true
ChaosRested = {addVials = function(player, n) return vialOk end}
op(a, "open", {})
local found = {}
for _, o in ipairs(lastSent(a, "state").offers) do
	found[o.k] = o
end
check(found["pocket_charge.rotking"] ~= nil, "the pocket boss offer lights up with the API")
eq(found["pocket_charge.rotking"].b, "The Rot King", "with its boss name")
check(found.rested_vial ~= nil, "the vial lights up with its API")
bal = DB.accounts[100].balance
op(a, "buy", {k = "pocket_charge.rotking"})
check(lastSent(a, "result").ok, "pocket boss charge bought")
eq(#charges, 1, "addCharges called once")
eq(charges[1].key, "rotking", "for the boss")
eq(charges[1].n, 1, "one charge")
eq(DB.accounts[100].balance, bal - 15, "the price")
eq(a.saved.mark, DB.nextId, "the mark was saved before the call")
-- the real API returns the charges added: 0 and a reason is a refusal, refunded with the reason shown
local realAdd = ChaosPocketBoss.addCharges
ChaosPocketBoss.addCharges = function() return 0, "No more bonus charges today." end
bal = DB.accounts[100].balance
op(a, "buy", {k = "pocket_charge.rotking"})
eq(lastSent(a, "result").ok, false, "0 charges added: refused")
check(lastSent(a, "result").text:find("No more bonus charges today.", 1, true) ~= nil, "with the API's reason")
eq(DB.accounts[100].balance, bal, "and refunded")
ChaosPocketBoss.addCharges = function(player, key, n) charges[#charges + 1] = {player = player, key = key, n = n}; return n end
-- a boss of a higher level than the offer
ChaosPocketBoss.bosses = function() return {{key = "rotking", name = "The Rot King", minLevel = 300}} end
op(a, "buy", {k = "pocket_charge.rotking"})
eq(lastSent(a, "result").text, "You need level 300 for that.", "the boss's own level counts")
ChaosPocketBoss.bosses = function() return {{key = "rotking", name = "The Rot King"}} end
-- an API that says no: refunded
vialOk = false
bal = DB.accounts[100].balance
op(a, "buy", {k = "rested_vial"})
eq(lastSent(a, "result").ok, false, "a refused delivery")
eq(DB.accounts[100].balance, bal, "is refunded")
eq(DB.purchases[DB.nextId].state, 2, "row refunded")
-- an API that errors: refunded too
ChaosRested.addVials = function() error("boom") end
op(a, "buy", {k = "rested_vial"})
eq(DB.accounts[100].balance, bal, "an error is refunded")
-- a pending call row over the mark at login (never saved): refunded, never called
vialOk = true
ChaosRested.addVials = function() vialOk = "called"; return true end
DB.nextId = DB.nextId + 1
DB.purchases[DB.nextId] = {id = DB.nextId, account_id = 100, player_id = 1, offer = "rested_vial", limit_key = "rested_vial",
	week = 0, price = 10, state = 0, detail = "call"}
bal = DB.accounts[100].balance
M.players, M.accounts, M.used = {}, {}, {}
online, byId = {}, {}
login(a)
eq(DB.purchases[DB.nextId].state, 2, "an unsaved call purchase is refunded at login")
eq(DB.accounts[100].balance, bal + 10, "with its price")
check(vialOk ~= "called", "and the API is not called")
-- the weekly limit of the pocket boss charges is shared by every boss
ChaosPocketBoss.bosses = function() return {{key = "rotking"}, {key = "ashwyrm"}} end
op(a, "buy", {k = "pocket_charge.ashwyrm"})
op(a, "buy", {k = "pocket_charge.rotking"})
op(a, "buy", {k = "pocket_charge.ashwyrm"})
eq(#charges, 3, "three charges a week in all bosses (the refused one does not count)")
eq(lastSent(a, "result").text, "Weekly limit reached for that offer.", "the fourth is refused")
ChaosPocketBoss, ChaosRested = nil, nil

-- cosmetics: once per account
local grants, ownedC = {}, {}
ChaosCosmetics = {
	grant = function(acc, key, source) grants[#grants + 1] = {acc, key, source}; ownedC[acc .. key] = true; return true end,
	owns = function(acc, key) return ownedC[acc .. key] == true end
}
talks["/candlemarks"].onSay(gm, "/candlemarks", "Char1, give 500")
op(a, "open", {})
local cos = {}
for _, o in ipairs(lastSent(a, "state").offers) do
	cos[o.k] = o
end
check(cos.cos_tallow and cos.cos_candleseal and cos.cos_candlelight, "the three cosmetics are on sale with the API")
op(a, "buy", {k = "cos_tallow"})
check(lastSent(a, "result").ok, "a cosmetic bought")
eq(grants[1][2], "loot_tallow", "granted to the account")
eq(grants[1][1], 100, "the account")
eq(grants[1][3], "candlemarks", "source candlemarks")
op(a, "open", {})
for _, o in ipairs(lastSent(a, "state").offers) do
	if o.k == "cos_tallow" then
		eq(o.own, true, "the window shows it owned")
	end
end
op(a, "buy", {k = "cos_tallow"})
eq(lastSent(a, "result").text, "Your account already has that.", "owned once")
eq(#grants, 1, "not granted twice")
ChaosCosmetics = nil
-- the shop's cosmetics exist in cosmetics_config.lua, never for coins
local ccfg = dofile("data/scripts/chaos/cosmetics_config.lua")
local cbk = {}
for _, c in ipairs(ccfg.cosmetics) do
	cbk[c.key] = c
end
for _, o in ipairs(cfg.offers) do
	if o.kind == "cosmetic" then
		check(cbk[o.cosmetic] ~= nil, o.key .. ": a real cosmetic")
		eq(cbk[o.cosmetic] and cbk[o.cosmetic].source, "candlemarks", o.key .. ": source candlemarks (not the store, not an exclusive)")
		check(o.price >= 80 and o.price <= 200, o.key .. ": priced 80-200")
	end
end

-- staff: take and refund
talks["/candlemarks"].onSay(gm, "/candlemarks", "Char1, give 50")
local before2 = DB.accounts[100].balance
talks["/candlemarks"].onSay(gm, "/candlemarks", "Char1, take 5")
eq(DB.accounts[100].balance, before2 - 5, "staff take")
local player1 = newPlayer(50, 500, 55, 100, 1)
login(player1)
talks["/candlemarks"].onSay(player1, "/candlemarks", "Char1, give 100")
eq(DB.accounts[100].balance, before2 - 5, "a player cannot give")
talks["/candlemarks"].onSay(gm, "/candlemarks", "Char1, refund " .. id)
eq(DB.purchases[id].state, 2, "staff refund marks the row")
eq(DB.accounts[100].balance, before2 - 5 + 8, "and gives the price back")

print(string.format("candlemarks_test: %d checks, %d failures", checks, failures))
if failures > 0 then
	os.exit(1)
end
