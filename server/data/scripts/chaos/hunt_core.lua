-- Hunt tracker, pure logic (no engine calls): the session clock (pause, resume, offline), the counters (experience,
-- kills, loot, supplies, damage, healing), the corpse snapshots merge, the used-supply count from two inventory
-- counts, the rates and the compact state sent to the client. Used by hunt.lua; tested by server/tests/hunt_test.lua.
-- Lua 5.1 / LuaJIT and 5.3 compatible.
--
-- A session:
--   {acc = seconds counted before `since`, since = os.time() the clock (re)started or nil while stopped,
--    paused = true when the player paused it, online = false after logout (offlineAt = when),
--    exp, kills = {[name] = n}, killCount, loot = {[key] = entry}, lootValue, supplies = {[id] = entry},
--    supplyValue, damage, healing, inv = {[id] = units} (last supply count, nil = take a fresh one)}
-- A loot entry: {key, id, cid (client id), name, n (count), value (gold, all of them), r (rarity 0..15),
--                u (unique), o (orb / currency)}

ChaosHunt = ChaosHunt or {}
local H = ChaosHunt

-- ---------------------------------------------------------------- session clock
local function zero(s)
	s.exp, s.kills, s.killCount = 0, {}, 0
	s.loot, s.lootValue = {}, 0
	s.supplies, s.supplyValue = {}, 0
	s.damage, s.healing = 0, 0
	s.inv = nil
	return s
end

function H.new(now)
	return zero({acc = 0, since = now, paused = false, online = true})
end

function H.elapsed(s, now)
	return s.acc + (s.since and math.max(0, now - s.since) or 0)
end

-- true while the counters run (online and not paused)
function H.running(s)
	return s.since ~= nil
end

local function stopClock(s, now)
	if s.since then
		s.acc = s.acc + math.max(0, now - s.since)
		s.since = nil
	end
end

local function startClock(s, now)
	if not s.since and s.online and not s.paused then
		s.since = now
	end
end

function H.pause(s, now)
	s.paused = true
	stopClock(s, now)
end

function H.resume(s, now)
	s.paused = false
	s.inv = nil -- supplies moved while paused are not "used"
	startClock(s, now)
end

function H.setOnline(s, online, now)
	s.online = online and true or false
	if s.online then
		s.offlineAt = nil
		s.inv = nil
		startClock(s, now)
	else
		s.offlineAt = now
		stopClock(s, now)
	end
end

-- back to zero; a paused session stays paused
function H.reset(s, now)
	s.acc = 0
	s.since = nil
	startClock(s, now)
	return zero(s)
end

-- sessions kept after logout for keepSeconds; returns how many were dropped
function H.sweep(sessions, now, keepSeconds)
	local dropped = 0
	for key, s in pairs(sessions) do
		if not s.online and s.offlineAt and now - s.offlineAt > keepSeconds then
			sessions[key] = nil
			dropped = dropped + 1
		end
	end
	return dropped
end

-- ---------------------------------------------------------------- counters
function H.addExp(s, n)
	n = math.floor(tonumber(n) or 0)
	if n > 0 and H.running(s) then
		s.exp = s.exp + n
	end
end

function H.addKill(s, name)
	if not H.running(s) or type(name) ~= "string" or name == "" then
		return
	end
	s.kills[name] = (s.kills[name] or 0) + 1
	s.killCount = s.killCount + 1
end

function H.addDamage(s, n)
	n = math.floor(tonumber(n) or 0)
	if n > 0 and H.running(s) then
		s.damage = s.damage + n
	end
end

function H.addHealing(s, n)
	n = math.floor(tonumber(n) or 0)
	if n > 0 and H.running(s) then
		s.healing = s.healing + n
	end
end

-- ---------------------------------------------------------------- loot
function H.itemKey(id, rarity, unique)
	return id .. ":" .. (rarity or 0) .. ":" .. (unique and 1 or 0)
end

-- gold for one item: coins, then extra values, then the NPC sell price
function H.unitValue(id, prices, coins, extra)
	return (coins and coins[id]) or (extra and extra[id]) or (prices and prices[id]) or 0
end

-- two reads of one corpse ({[key] = entry}): per key the entry with the larger count
function H.mergeMax(a, b)
	local out = {}
	for k, e in pairs(a or {}) do
		out[k] = e
	end
	for k, e in pairs(b or {}) do
		if not out[k] or (e.n or 0) > (out[k].n or 0) then
			out[k] = e
		end
	end
	return out
end

function H.isSpecial(e)
	return (e.o and true) or (e.u and true) or (tonumber(e.r) or 0) > 0
end

-- corpse = {[key] = {id, cid, name, n, r, u, o}}; unit(id) -> gold. Returns the gold added.
function H.addLoot(s, corpse, unit)
	if not H.running(s) then
		return 0
	end
	local gold = 0
	for key, e in pairs(corpse) do
		local n = math.floor(tonumber(e.n) or 0)
		if n > 0 then
			local value = (unit and unit(e.id) or 0) * n
			local row = s.loot[key]
			if not row then
				row = {key = key, id = e.id, cid = e.cid or e.id, name = e.name or "?", n = 0, value = 0,
					r = tonumber(e.r) or 0, u = e.u and true or false, o = e.o and true or false}
				s.loot[key] = row
			end
			row.n = row.n + n
			row.value = row.value + value
			gold = gold + value
		end
	end
	s.lootValue = s.lootValue + gold
	return gold
end

-- ---------------------------------------------------------------- supplies
-- prev / cur: {[id] = units} from two inventory counts -> {[id] = units used} (only decreases count)
function H.supplyUsed(prev, cur)
	local used = {}
	if not prev then
		return used
	end
	for id, before in pairs(prev) do
		local now = cur[id] or 0
		if now < before then
			used[id] = before - now
		end
	end
	return used
end

function H.addSupply(s, id, n, unitPrice, cid, name)
	n = math.floor(tonumber(n) or 0)
	if n <= 0 or not H.running(s) then
		return 0
	end
	local row = s.supplies[id]
	if not row then
		row = {id = id, cid = cid or id, name = name or "?", n = 0, value = 0}
		s.supplies[id] = row
	end
	local value = math.floor((tonumber(unitPrice) or 0) * n + 0.5)
	row.n = row.n + n
	row.value = row.value + value
	s.supplyValue = s.supplyValue + value
	return value
end

-- ---------------------------------------------------------------- rates
-- experience needed to reach `level` (the engine's Player::getExpForLevel)
function H.expForLevel(level)
	level = math.floor(tonumber(level) or 1)
	return math.floor((((level - 6) * level + 17) * level - 12) / 6) * 100
end

function H.perHour(value, seconds, minSeconds)
	if seconds < (minSeconds or 1) or seconds <= 0 then
		return 0
	end
	local v = value * 3600 / seconds
	return v >= 0 and math.floor(v) or -math.floor(-v)
end

-- seconds to gain `left` experience at `perHour`, or -1 (no rate)
function H.timeToLevel(left, perHour)
	if not perHour or perHour <= 0 then
		return -1
	end
	return math.ceil(math.max(0, left) * 3600 / perHour)
end

-- ---------------------------------------------------------------- wire state
local function sortedRows(map, less, limit)
	local rows = {}
	for _, v in pairs(map) do
		rows[#rows + 1] = v
	end
	table.sort(rows, less)
	if limit and #rows > limit then
		for i = #rows, limit + 1, -1 do
			rows[i] = nil
		end
	end
	return rows
end

local function byValue(a, b)
	if a.value ~= b.value then
		return a.value > b.value
	end
	if a.n ~= b.n then
		return a.n > b.n
	end
	return a.key < b.key
end

local function bySpecial(a, b)
	local au, bu = a.u and 1 or 0, b.u and 1 or 0
	if au ~= bu then
		return au > bu
	end
	if a.r ~= b.r then
		return a.r > b.r
	end
	if a.n ~= b.n then
		return a.n > b.n
	end
	return a.key < b.key
end

-- ctx = {exp = player experience, level = player level, minRateSeconds, maxKills, maxLoot, maxSupplies, maxSpecials}
function H.state(s, now, ctx)
	local t = H.elapsed(s, now)
	local minS = ctx.minRateSeconds or 30
	local xph = H.perHour(s.exp, t, minS)
	local left = math.max(0, H.expForLevel((ctx.level or 1) + 1) - (ctx.exp or 0))
	local profit = s.lootValue - s.supplyValue
	local out = {
		t = t, p = s.paused and 1 or 0,
		xp = s.exp, xph = xph, lvl = ctx.level or 1, left = left, ttl = H.timeToLevel(left, xph),
		lv = s.lootValue, lvh = H.perHour(s.lootValue, t, minS),
		sv = s.supplyValue, svh = H.perHour(s.supplyValue, t, minS),
		pf = profit, pfh = H.perHour(profit, t, minS),
		dmg = s.damage, dps = t >= minS and math.floor(s.damage / t) or 0,
		heal = s.healing, hps = t >= minS and math.floor(s.healing / t) or 0,
		kc = s.killCount, k = {}, l = {}, s = {}, x = {}
	}
	local kills = {}
	for name, n in pairs(s.kills) do
		kills[#kills + 1] = {name, n}
	end
	table.sort(kills, function(a, b)
		if a[2] ~= b[2] then
			return a[2] > b[2]
		end
		return a[1] < b[1]
	end)
	for i = 1, math.min(#kills, ctx.maxKills or 40) do
		out.k[i] = kills[i]
	end
	for _, e in ipairs(sortedRows(s.loot, byValue, ctx.maxLoot or 60)) do
		out.l[#out.l + 1] = {e.cid, e.n, e.value, e.name, e.r, e.u and 1 or 0, e.o and 1 or 0}
	end
	for _, e in ipairs(sortedRows(s.supplies, function(a, b)
		if a.value ~= b.value then
			return a.value > b.value
		end
		return a.id < b.id
	end, ctx.maxSupplies or 30)) do
		out.s[#out.s + 1] = {e.cid, e.n, e.value, e.name}
	end
	local specials = {}
	for k, e in pairs(s.loot) do
		if H.isSpecial(e) then
			specials[k] = e
		end
	end
	for _, e in ipairs(sortedRows(specials, bySpecial, ctx.maxSpecials or 40)) do
		out.x[#out.x + 1] = {e.cid, e.n, e.name, e.r, e.u and 1 or 0, e.o and 1 or 0}
	end
	return out
end

return H
