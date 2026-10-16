-- Chaos: Currencies. Candlemarks, Conquest Tokens, Ember Cache points and the beta starter coins, through each system's
-- own API (candlemarks.lua ChaosCandlemarks, conquest.lua ChaosConquest, embercache.lua ChaosEmberCache, beta.lua
-- ChaosBeta). Where a system has no write API (Candlemarks and Conquest give / take: their staff commands write the
-- balance themselves), the same single statements as those commands are used, on the system's own table names, and the
-- system's cache is updated with it. Value needs group 5 (docs/GM_HANDBOOK.md section 2); every run is in the admin log.
ChaosAdminPending = ChaosAdminPending or {}
local function reg(def) def.category = "chaos_currency"; def.id = "chaos_currency." .. def.id; ChaosAdminPending[def.id] = def end

local PLAYER = {name = "player", label = "Player", type = "player"}
local ONLINE = {name = "player", label = "Player (online)", type = "player"}
local AMOUNT = {name = "amount", label = "Amount", type = "int", min = 1, max = 100000}

local function sys(name, fn) return ChaosAdmin.system(name, fn) end

-- ------------------------------------------------------------------ Candlemarks (server/README.md "Candlemarks")
local function cmTable()
	return (Chaos.candlemarksTables and Chaos.candlemarksTables.accounts) or "chaos_candlemarks"
end

local function cmLine(M, name, accountId, pl)
	local acc = M.account(accountId)
	if not acc then return name .. ": no account." end
	local text = string.format("%s (account %d): %d Candlemarks (earned %d, spent %d)", name, accountId, acc.balance, acc.earned, acc.spent)
	if pl then
		text = text .. string.format(", progress %d/%d s, %s", pl.progress or 0, M.core.blockSec(M.cfg),
			M.earners[pl.guid] and "earning" or ("not earning: " .. tostring(M.why[pl.guid] or "no tick yet")))
	end
	return text .. "."
end

reg{id = "candlemarks_view", name = "Candlemarks: view", description = "Account balance (earned, spent) and, online, the progress to the next coin and why the character does or does not earn.",
	params = {PLAYER},
	handler = function(actor, p)
		local M, why = sys("ChaosCandlemarks", "account")
		if not M then return false, why end
		local t, err = ChaosAdmin.targetAny(actor, p.player)
		if not t then return false, err end
		return true, cmLine(M, t.name, t.account, t.player and M.track(t.player))
	end}

local function cmChange(actor, p, sign)
	local M, why = sys("ChaosCandlemarks", "account")
	if not M then return false, why end
	local t, err = ChaosAdmin.targetAny(actor, p.player)
	if not t then return false, err end
	local acc = M.account(t.account)
	if not acc then return false, "No account." end
	local n = p.amount
	if sign > 0 then
		db.query(string.format("UPDATE `%s` SET `balance` = `balance` + %d WHERE `account_id` = %d", cmTable(), n, t.account))
		acc.balance = acc.balance + n
	else
		n = math.min(n, acc.balance)
		db.query(string.format("UPDATE `%s` SET `balance` = GREATEST(0, `balance` - %d) WHERE `account_id` = %d", cmTable(), n, t.account))
		acc.balance = acc.balance - n
	end
	if t.player and M.sendHud then M.sendHud(t.player, M.track(t.player)) end
	return true, (sign > 0 and "+" or "-") .. n .. ". " .. cmLine(M, t.name, t.account)
end

reg{id = "candlemarks_give", name = "Candlemarks: give", description = "Add Candlemarks to the account of a character (as /candlemarks name, give n).",
	minGroup = 5, params = {PLAYER, AMOUNT},
	handler = function(actor, p) return cmChange(actor, p, 1) end}

reg{id = "candlemarks_take", name = "Candlemarks: take", description = "Take Candlemarks from the account of a character (never below 0).",
	minGroup = 5, confirm = true, params = {PLAYER, AMOUNT},
	handler = function(actor, p) return cmChange(actor, p, -1) end}

reg{id = "candlemarks_ip_reset", name = "Candlemarks: reset IP limit", description = "Puts an online character first in its IP address's earning order (at most 2 earn per IP): it earns from the next tick, the last one of that IP stops.",
	params = {ONLINE},
	handler = function(actor, p)
		local M, why = sys("ChaosCandlemarks", "track")
		if not M then return false, why end
		local t, err = ChaosAdmin.targetOnline(actor, p.player)
		if not t then return false, err end
		local pl = M.track(t)
		pl.loginAt = 0
		M.why[pl.guid] = nil
		return true, t:getName() .. " now goes first in its IP's order. " .. cmLine(M, t:getName(), pl.account, pl)
	end}

-- ------------------------------------------------------------------ Conquest Tokens (server/README.md "Conquest Tokens")
local function cqOf(guid)
	return {getGuid = function() return guid end}
end

local function cqLine(X, t)
	local text = string.format("%s: %d Conquest Tokens", t.name, X.balance(t.player or cqOf(t.guid)))
	if t.player then
		local parts = {}
		for _, g in ipairs(X.cfg.pityOrder or {}) do
			parts[#parts + 1] = string.format("%s %d (x%.2f)", g, X.pityMisses(t.player, g), X.pityMult(t.player, g))
		end
		text = text .. "; bad-luck misses " .. table.concat(parts, ", ")
	end
	return text .. "."
end

local function cqLog(X, guid, amount, actor)
	db.query(string.format("INSERT INTO `%s` (`player_id`, `source`, `amount`, `balance`, `detail`, `at`) VALUES (%d, 'staff', %d, %d, %s, %d)",
		X.cfg.tables.log, guid, amount, math.max(0, X.balance(cqOf(guid))), db.escapeString(actor:getName():sub(1, 80)), os.time()))
end

reg{id = "conquest_view", name = "Conquest Tokens: view", description = "Token balance; online also the bad-luck protection misses per group.",
	params = {PLAYER},
	handler = function(actor, p)
		local X, why = sys("ChaosConquest", "balance")
		if not X then return false, why end
		local t, err = ChaosAdmin.targetAny(actor, p.player)
		if not t then return false, err end
		return true, cqLine(X, t)
	end}

reg{id = "conquest_give", name = "Conquest Tokens: give", description = "Add tokens (as /conquest name, give, n; logged in the token log as source staff).",
	minGroup = 5, params = {PLAYER, AMOUNT},
	handler = function(actor, p)
		local X, why = sys("ChaosConquest", "balance")
		if not X then return false, why end
		local t, err = ChaosAdmin.targetAny(actor, p.player)
		if not t then return false, err end
		db.query(string.format("INSERT INTO `%s` (`player_id`, `balance`, `earned`, `updated_at`) VALUES (%d, %d, %d, %d) " ..
			"ON DUPLICATE KEY UPDATE `balance` = `balance` + VALUES(`balance`), `earned` = `earned` + VALUES(`earned`), " ..
			"`updated_at` = VALUES(`updated_at`)", X.cfg.tables.balance, t.guid, p.amount, p.amount, os.time()))
		X.bal[t.guid] = nil
		cqLog(X, t.guid, p.amount, actor)
		return true, "+" .. p.amount .. ". " .. cqLine(X, t)
	end}

reg{id = "conquest_take", name = "Conquest Tokens: take", description = "Take tokens (one conditional update: refused when the balance is lower).",
	minGroup = 5, confirm = true, params = {PLAYER, AMOUNT},
	handler = function(actor, p)
		local X, why = sys("ChaosConquest", "balance")
		if not X then return false, why end
		local t, err = ChaosAdmin.targetAny(actor, p.player)
		if not t then return false, err end
		db.query(string.format("UPDATE `%s` SET `balance` = `balance` - %d, `updated_at` = %d WHERE `player_id` = %d AND `balance` >= %d",
			X.cfg.tables.balance, p.amount, os.time(), t.guid, p.amount))
		local r = Chaos.select("SELECT ROW_COUNT() AS `n`", {{"n", "n"}})[1]
		X.bal[t.guid] = nil
		if not r or r.n ~= 1 then return false, "Balance too low. " .. cqLine(X, t) end
		cqLog(X, t.guid, -p.amount, actor)
		return true, "-" .. p.amount .. ". " .. cqLine(X, t)
	end}

reg{id = "conquest_pity_reset", name = "Conquest: reset bad-luck counters", description = "Sets every bad-luck protection miss counter of an online character to 0 (as /conquest name, pity).",
	confirm = true, params = {ONLINE},
	handler = function(actor, p)
		local X, why = sys("ChaosConquest", "pityMisses")
		if not X then return false, why end
		local t, err = ChaosAdmin.targetOnline(actor, p.player)
		if not t then return false, err end
		local base = Chaos.storage.conquest or X.cfg.storage
		for _, g in pairs(X.cfg.pity or {}) do
			t:setStorageValue(base + X.cfg.pitySlot + g.slot, 0)
		end
		return true, cqLine(X, {name = t:getName(), guid = t:getGuid(), player = t})
	end}

-- ------------------------------------------------------------------ Ember Cache (server/README.md "Ember Cache")
local okEC, ecCfg = pcall(dofile, "data/scripts/chaos/embercache_config.lua")
local EC_SOURCES = {}
for _, key in ipairs(okEC and type(ecCfg) == "table" and ecCfg.order or {}) do
	EC_SOURCES[#EC_SOURCES + 1] = {value = key, label = key}
end
if #EC_SOURCES == 0 then EC_SOURCES[1] = {value = "dungeon", label = "dungeon"} end

local function ecLine(E, t)
	local v = E.view(t)
	return string.format("%s: week %d points (%d milestone(s) given, %d spark(s)), today %d points, Daily Spark %s.", t:getName(),
		v.week.pts or 0, v.week.got or 0, v.week.sparks or 0, v.day.pts or 0, (v.day.spark or 0) > 0 and "lit" or "not lit")
end

reg{id = "embers_view", name = "Ember Cache: view", description = "The week's points and milestones and today's points of an online character.",
	params = {ONLINE},
	handler = function(actor, p)
		local E, why = sys("ChaosEmberCache", "view")
		if not E then return false, why end
		local t, err = ChaosAdmin.targetOnline(actor, p.player)
		if not t then return false, err end
		return true, ecLine(E, t)
	end}

reg{id = "embers_give", name = "Ember Cache: give units", description = "Credits units of a source (ChaosEmberCache.credit: the source's points and caps, the Spark and the milestone rewards as in play).",
	minGroup = 5,
	params = {ONLINE, {name = "source", label = "Source", type = "select", default = EC_SOURCES[1].value, options = EC_SOURCES},
		{name = "units", label = "Units", type = "int", min = 1, max = 1000, default = 1}},
	handler = function(actor, p)
		local E, why = sys("ChaosEmberCache", "credit")
		if not E then return false, why end
		local t, err = ChaosAdmin.targetOnline(actor, p.player)
		if not t then return false, err end
		local n = E.credit(t, p.source, p.units)
		return true, "+" .. tostring(n) .. " point(s). " .. ecLine(E, t)
	end}

reg{id = "embers_take", name = "Ember Cache: take points", description = "Lowers the week's and today's points (milestones already given stay given).",
	minGroup = 5, confirm = true, params = {ONLINE, {name = "points", label = "Points", type = "int", min = 1, max = 100000}},
	handler = function(actor, p)
		local E, why = sys("ChaosEmberCache", "view")
		if not E then return false, why end
		local K, c = ChaosEmberCacheCore, ChaosEmberCacheConfig
		if not K or not c then return false, "The Ember Cache core is not loaded." end
		local t, err = ChaosAdmin.targetOnline(actor, p.player)
		if not t then return false, err end
		E.view(t) -- loads and rolls the state
		local st = E.st[t:getId()] or K.load(c, function(off) return t:getStorageValue(c.storage.base + off) end)
		K.roll(st, os.time(), c)
		st.weekPoints = math.max(0, st.weekPoints - p.points)
		st.dayPoints = math.max(0, st.dayPoints - p.points)
		E.st[t:getId()] = st
		K.save(c, st, function(off, v) t:setStorageValue(c.storage.base + off, v) end)
		if E.send then pcall(E.send, t, false) end
		return true, "-" .. p.points .. ". " .. ecLine(E, t)
	end}

-- ------------------------------------------------------------------ beta starter coins (server/README.md "Beta starter coins")
reg{id = "beta_view", name = "Beta coins: view", description = "Whether the account had its beta starter coins, and its Chaos Coin balance.",
	params = {PLAYER},
	handler = function(actor, p)
		local B = ChaosBetaCore
		if not B or not Chaos.beta then return false, "beta.lua is not loaded on this server." end
		local t, err = ChaosAdmin.targetAny(actor, p.player)
		if not t then return false, err end
		local row = Chaos.select(B.grantedSql(t.account) or "SELECT 0 AS `coins` FROM DUAL WHERE 1 = 0", {{"coins", "n"}})[1]
		local coins = ChaosShop and ChaosShop.getCoins and ChaosShop.getCoins(t.account)
		return true, string.format("%s (account %d): beta %s (%d starter coins), %s; balance %s Chaos Coins.", t.name, t.account,
			B.enabled(Chaos.beta) and "on" or "off", B.starterCoins(Chaos.beta), row and ("granted " .. row.coins) or "not granted",
			tostring(coins or "?"))
	end}

reg{id = "beta_give", name = "Beta coins: give starter coins", description = "Gives the account its beta starter coins now (ChaosBeta.grantStarter: once per account, only while the beta is on).",
	minGroup = 5, params = {ONLINE},
	handler = function(actor, p)
		local Beta, why = sys("ChaosBeta", "grantStarter")
		if not Beta then return false, why end
		local t, err = ChaosAdmin.targetOnline(actor, p.player)
		if not t then return false, err end
		if not Beta.grantStarter(t) then return false, "Not given: the beta is off, the store is not loaded or the account had its coins." end
		if Beta.tell then pcall(Beta.tell, t:getId(), ChaosBetaCore.starterCoins(Chaos.beta)) end
		return true, t:getName() .. ": beta starter coins given to the account."
	end}
