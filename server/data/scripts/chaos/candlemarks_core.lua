-- Candlemarks: pure logic (no engine calls), shared by candlemarks.lua and server/tests/candlemarks_test.lua.
--   time       blockSec(cfg), dayKey(t, hour), weekKey(t, hour)
--   earning    newAccount(), rollDay(acc, day), advance(progress, acc, cfg, elapsed, day) -> coins, progress, info;
--              secondsToNext(progress, cfg)
--   who earns  pickEarners(cands, cfg) -> earners {[guid] = true}, why {[guid] = reason}
--   shop       bosses(raw) -> {{key, name}}; offers(cfg, ext) -> list, byKey; limitKey(o); checkBuy(o, ctx, cfg) ->
--              true | false, reason, arg; itemsOf(o, rnd, gemTypes, gemFirst) -> {{id, count}}; recover(rows, seq)
--   view       view(acc, progress, list, used, ctx, cfg) -> the client's state
--   checks     validate(cfg) -> problems
-- The state of an account: {balance, earned, spent, day (dayKey of `today`), today (coins earned that day)}; the
-- progress to the next coin belongs to each character (a player storage).
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.

ChaosCandlemarksCore = ChaosCandlemarksCore or {}
local K = ChaosCandlemarksCore

local floor, max, min = math.floor, math.max, math.min

local function int(v)
	v = tonumber(v)
	if not v or v ~= v or v == math.huge or v == -math.huge then
		return 0
	end
	return floor(v)
end
K.int = int

-- ---------------------------------------------------------------- time
function K.blockSec(cfg)
	return int(cfg.blockMinutes) * 60
end

-- YYYYMMDD of the day `t` belongs to, the day turning at `hour` (server time)
function K.dayKey(t, hour)
	local d = os.date("*t", int(t) - int(hour) * 3600)
	return d.year * 10000 + d.month * 100 + d.day
end

-- YYYYMMDD of the Monday the week of `t` started, the week turning on Monday at `hour` (the bounty board's week)
function K.weekKey(t, hour)
	local d = os.date("*t", int(t) - int(hour) * 3600)
	local back = (d.wday + 5) % 7 -- days since Monday
	local m = os.date("*t", os.time({year = d.year, month = d.month, day = d.day - back, hour = 12}))
	return m.year * 10000 + m.month * 100 + m.day
end

-- ---------------------------------------------------------------- earning
function K.newAccount()
	return {balance = 0, earned = 0, spent = 0, day = 0, today = 0}
end

-- a new day for the daily cap: the day's count starts over. true when it turned.
function K.rollDay(acc, day)
	if acc.day ~= day then
		acc.day, acc.today = day, 0
		return true
	end
	return false
end

-- One tick of online time for a character that earns now. progress = the character's seconds toward its next coin;
-- acc = its account's state (shared by every character of the account); elapsed = seconds since its last tick
-- (clamped to cfg.maxTickSeconds); day = dayKey of now (the daily cap's day). Every full block of progress is one coin
-- to the account. With the daily cap reached the progress stays where it is. Returns coins, the new progress, and
-- info {capped = the account's daily cap is reached}.
function K.advance(progress, acc, cfg, elapsed, day)
	local info = {}
	K.rollDay(acc, day)
	local B = K.blockSec(cfg)
	local cap = int(cfg.earn and cfg.earn.dailyCap)
	progress = max(0, int(progress))
	if cap > 0 and acc.today >= cap then
		info.capped = true
		return 0, progress, info
	end
	progress = progress + min(max(0, int(elapsed)), int(cfg.maxTickSeconds))
	local gained = 0
	while progress >= B do
		progress = progress - B
		gained = gained + 1
		acc.today = acc.today + 1
		acc.balance = acc.balance + 1
		acc.earned = acc.earned + 1
		if cap > 0 and acc.today >= cap then
			info.capped = true
			break
		end
	end
	return gained, progress, info
end

-- seconds of online time left to the next coin
function K.secondsToNext(progress, cfg)
	return max(0, K.blockSec(cfg) - int(progress))
end

-- ---------------------------------------------------------------- who earns
-- cands = {{guid, ip, level, staff, loginAt}}: every online character. Every character earns except staff, those
-- under cfg.earn.minLevel, and those over cfg.earn.maxPerIp on one IP address: per IP the earliest logins earn (then
-- the lower guid), so when one of them logs out the next in that order earns from the next tick. IP 0 (no
-- connection) is not limited. Returns earners {[guid] = true}, why {[guid] = "staff" | "level" | "ip"}.
function K.pickEarners(cands, cfg)
	local e = cfg.earn or {}
	local earners, why, ok = {}, {}, {}
	for _, c in ipairs(cands or {}) do
		if c.staff then
			why[c.guid] = "staff"
		elseif int(c.level) < int(e.minLevel) then
			why[c.guid] = "level"
		else
			ok[#ok + 1] = c
		end
	end
	table.sort(ok, function(a, b)
		if int(a.loginAt) ~= int(b.loginAt) then
			return int(a.loginAt) < int(b.loginAt)
		end
		return int(a.guid) < int(b.guid)
	end)
	local perIp = {}
	local maxIp = max(1, int(e.maxPerIp))
	for _, c in ipairs(ok) do
		local ip = int(c.ip)
		if ip ~= 0 and (perIp[ip] or 0) >= maxIp then
			why[c.guid] = "ip"
		else
			if ip ~= 0 then
				perIp[ip] = (perIp[ip] or 0) + 1
			end
			earners[c.guid] = true
		end
	end
	return earners, why
end

-- ---------------------------------------------------------------- shop
local KEY = "^[%w_%-]+$"

-- the pocket bosses from ChaosPocketBoss.bosses(), whatever its shape: an array of {key, name, minLevel} (or id / label), an
-- array of keys, or a map key -> def | name. Sorted by key; bad entries skipped; at most 40.
function K.bosses(raw)
	local out, seen = {}, {}
	if type(raw) ~= "table" then
		return out
	end
	local function add(key, name, minLevel)
		key = type(key) == "number" and tostring(int(key)) or key
		if type(key) ~= "string" or #key > 32 or not key:match(KEY) or seen[key] then
			return
		end
		if type(name) ~= "string" or name == "" then
			name = key
		end
		seen[key] = true
		out[#out + 1] = {key = key, name = name:sub(1, 48), minLevel = max(0, int(minLevel))}
	end
	local isArray = #raw > 0
	if isArray then
		for _, b in ipairs(raw) do
			if type(b) == "table" then
				add(b.key or b.id, b.name or b.label, b.minLevel)
			else
				add(b, nil)
			end
		end
	else
		for k, v in pairs(raw) do
			if type(v) == "table" then
				add(v.key or k, v.name or v.label, v.minLevel)
			else
				add(k, v)
			end
		end
	end
	table.sort(out, function(a, b) return a.key < b.key end)
	while #out > 40 do
		out[#out] = nil
	end
	return out
end

function K.limitKey(o)
	return o.limitKey or o.limit or o.key
end

-- The offers on sale now. ext = {has = function(call) -> bool (that API exists), bosses = K.bosses(...) or nil (no
-- pocket boss API), cosmetics = bool (ChaosCosmetics.grant exists)}. A pocket boss offer becomes one offer per boss:
-- key "<offer key>.<boss key>", sharing the offer's weekly limit, its level the higher of the offer's and the boss's.
-- Returns list, byKey.
function K.offers(cfg, ext)
	ext = ext or {}
	local list, byKey = {}, {}
	local function put(o)
		list[#list + 1] = o
		byKey[o.key] = o
	end
	for _, o in ipairs(cfg.offers or {}) do
		if o.enabled ~= false then
			if o.kind == "item" or o.kind == "gem" then
				put(o)
			elseif o.kind == "pocketboss" then
				for _, b in ipairs(ext.bosses or {}) do
					local r = {}
					for k, v in pairs(o) do
						r[k] = v
					end
					r.key, r.boss, r.limitKey = o.key .. "." .. b.key, b.key, o.limit or o.key
					r.name, r.bossName = o.name, b.name
					r.minLevel = max(int(o.minLevel), int(b.minLevel))
					put(r)
				end
			elseif o.kind == "call" then
				if ext.has and ext.has(o.call) then
					put(o)
				end
			elseif o.kind == "cosmetic" then
				if o.cosmetic and ext.cosmetics then
					put(o)
				end
			end
		end
	end
	return list, byKey
end

-- ctx = {enabled, balance, level, used (purchases of the offer's limit key this week), owned, near (an NPC in range,
-- when cfg.npc.buyNearNpc), busy}. The first refusal: disabled, unknown, busy, npc, level, owned, weekly, balance.
function K.checkBuy(o, ctx, cfg)
	if not ctx.enabled then
		return false, "disabled"
	end
	if type(o) ~= "table" then
		return false, "unknown"
	end
	if ctx.busy then
		return false, "busy"
	end
	if cfg.npc and cfg.npc.buyNearNpc and not ctx.near then
		return false, "npc"
	end
	if int(ctx.level) < int(o.minLevel) then
		return false, "level", int(o.minLevel)
	end
	if ctx.owned then
		return false, "owned"
	end
	if int(o.weekly) > 0 and int(ctx.used) >= int(o.weekly) then
		return false, "weekly"
	end
	if int(ctx.balance) < int(o.price) then
		return false, "balance", int(o.price)
	end
	return true
end

-- the items an item or gem offer gives: {{id, count}}; rnd(n) -> 1..n picks a gem type (gemTypes of them, ids from
-- gemFirst: data/lib/chaos_gems_config.lua, id = firstId - 1 + (type - 1) * 5 + tier)
function K.itemsOf(o, rnd, gemTypes, gemFirst)
	local out = {}
	if o.kind == "item" then
		for _, it in ipairs(o.items or {}) do
			out[#out + 1] = {id = int(it[1]), count = max(1, int(it[2]))}
		end
	elseif o.kind == "gem" then
		local n = max(1, int(gemTypes))
		local t = min(n, max(1, int(rnd and rnd(n) or 1)))
		out[1] = {id = int(gemFirst) - 1 + (t - 1) * 5 + min(5, max(1, int(o.tier))), count = 1}
	end
	return out
end

-- what to do with the pending purchases of a character at login. rows = {{id, ...}} (state pending), seq = the
-- character's delivery mark (the last purchase id saved with its items). Returns {done = {...}, deliver = {...}}:
-- a row at or under the mark was delivered and saved (only its row update was lost), a row over it was not.
function K.recover(rows, seq)
	local out = {done = {}, deliver = {}}
	seq = int(seq)
	for _, r in ipairs(rows or {}) do
		if int(r.id) <= seq then
			out.done[#out.done + 1] = r
		else
			out.deliver[#out.deliver + 1] = r
		end
	end
	table.sort(out.deliver, function(a, b) return int(a.id) < int(b.id) end)
	return out
end

-- ---------------------------------------------------------------- view
-- the client's state. acc = the account's state, progress = this character's; used = {[limit key] = purchases this
-- week}; ctx = {earning (bool), why (the reason it does not), level, icon = function(o) -> client id, weekEnds
-- (seconds to the weekly reset), tr = function(text) -> the text in the player's language (offer names and texts),
-- near (Osric in range: buying works), owned = function(o) -> the account owns that cosmetic}
function K.view(acc, progress, list, used, ctx, cfg)
	used = used or {}
	local tr = ctx.tr or function(text) return text end
	local out = {
		balance = int(acc.balance), progress = int(progress), block = K.blockSec(cfg),
		earning = ctx.earning and true or false, why = ctx.why, today = int(acc.today),
		cap = int(cfg.earn and cfg.earn.dailyCap), level = int(ctx.level), weekEnds = int(ctx.weekEnds), offers = {},
		near = (not (cfg.npc and cfg.npc.buyNearNpc)) or ctx.near == true
	}
	for _, o in ipairs(list or {}) do
		out.offers[#out.offers + 1] = {
			k = o.key, n = tr(o.name), b = o.bossName, d = tr(o.desc), p = int(o.price), w = int(o.weekly),
			u = int(used[K.limitKey(o)]), l = int(o.minLevel), c = ctx.icon and int(ctx.icon(o)) or 0, kind = o.kind,
			own = (ctx.owned and ctx.owned(o)) and true or nil
		}
	end
	return out
end

-- ---------------------------------------------------------------- checks
local KINDS = {item = true, gem = true, pocketboss = true, call = true, cosmetic = true}

function K.validate(cfg)
	local out = {}
	local function bad(fmt, ...)
		out[#out + 1] = string.format(fmt, ...)
	end
	local B = K.blockSec(cfg)
	if B < 60 then
		bad("blockMinutes must be at least 1")
	end
	if int(cfg.tickSeconds) < 1 or int(cfg.maxTickSeconds) < int(cfg.tickSeconds) or int(cfg.maxTickSeconds) >= B then
		bad("maxTickSeconds must be at least tickSeconds and under one block")
	end
	if int(cfg.earn and cfg.earn.maxPerIp) < 1 then
		bad("earn.maxPerIp must be at least 1")
	end
	if int(cfg.storage) < 7100000 or int(cfg.storage) > 7127999 then
		bad("storage outside the Chaos blocks")
	end
	local forbidden = {}
	for _, id in ipairs(cfg.forbiddenIds or {}) do
		forbidden[id] = true
	end
	local keys = {}
	for i, o in ipairs(cfg.offers or {}) do
		local w = tostring(o.key or ("#" .. i))
		if type(o.key) ~= "string" or not o.key:match("^[%w_]+$") or keys[o.key] then
			bad("%s: key missing, not plain or used twice", w)
		end
		keys[o.key or "?"] = true
		if not KINDS[o.kind] then
			bad("%s: unknown kind %s", w, tostring(o.kind))
		end
		if type(o.price) ~= "number" or o.price < 1 or o.price ~= floor(o.price) then
			bad("%s: price must be a positive whole number", w)
		end
		if type(o.weekly) ~= "number" or o.weekly < 1 or o.weekly ~= floor(o.weekly) then
			bad("%s: every offer needs a weekly limit", w)
		end
		if type(o.minLevel) ~= "number" or o.minLevel < 1 then
			bad("%s: minLevel needed", w)
		end
		if type(o.name) ~= "string" or o.name == "" or #o.name > 40 or type(o.desc) ~= "string" or #o.desc > 80 then
			bad("%s: name (up to 40) and desc (up to 80) needed", w)
		end
		if o.kind == "item" then
			if type(o.items) ~= "table" or #o.items < 1 then
				bad("%s: items needed", w)
			end
			for _, it in ipairs(o.items or {}) do
				if type(it[1]) ~= "number" or type(it[2]) ~= "number" or it[2] < 1 or it[2] > 100 then
					bad("%s: item {id, count 1-100}", w)
				elseif forbidden[it[1]] then
					bad("%s: item %d is never sold for Candlemarks", w, it[1])
				end
			end
		elseif o.kind == "gem" and (type(o.tier) ~= "number" or o.tier < 1 or o.tier > 5) then
			bad("%s: gem tier 1-5", w)
		elseif o.kind == "pocketboss" and (type(o.charges) ~= "number" or o.charges < 1) then
			bad("%s: charges needed", w)
		elseif o.kind == "call" and (type(o.call) ~= "table" or type(o.call[1]) ~= "string" or type(o.call[2]) ~= "string") then
			bad("%s: call = {table, function, args...}", w)
		end
	end
	for _, k in ipairs({"disabled", "unknown", "level", "balance", "weekly", "owned", "unavailable", "busy", "npc", "failed",
			"bought", "inbox", "earned", "earnedCap"}) do
		if type(cfg.messages and cfg.messages[k]) ~= "string" then
			bad("messages.%s missing", k)
		end
	end
	return out
end

return K
