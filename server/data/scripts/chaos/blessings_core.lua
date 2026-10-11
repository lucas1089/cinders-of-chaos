-- blessings_core.lua: the pure rules of the Ember Blessings (no engine calls; tests/blessings_test.lua).
-- The engine glue is blessings.lua, the numbers blessings_config.lua; overview server/README.md "Ember Blessings".
--
--   K.levelFactor(cfg, playerLevel, monsterLevel)  share of the chance left by the level gap (0 .. 1)
--   K.chance(cfg, tier, playerLevel, monsterLevel)  percent chance of one kill
--   K.ready(cfg, st, now)                          the internal cooldown is over
--   K.pick(cfg, rand)                              a pool entry drawn by weight
--   K.grant(cfg, st, key, now)                     the blessing given: {action = "new" | "refresh" | "replace",
--                                                  key, untilMs, replaced = key or nil}
--   K.roll(cfg, st, info, now, rand)               one kill: the grant, or nil and why
--   K.expire(st, now)                              the keys that ran out (taken out of st)
--   K.left(st, key, now) / K.value(cfg, st, key, now) / K.mult(cfg, st, key, now)
--   K.list(cfg, st, now)                           the active blessings, longest time left first
-- st (one character): {active = {key -> {untilMs, sinceMs}}, lastProcMs = ms or nil}
-- Rules: the same kind never stacks (a proc of an active kind sets its time back to the full duration); different
-- kinds run side by side up to cfg.maxActive; a new kind past the cap takes the place of the one with the least time
-- left. Lua 5.1 / LuaJIT and Lua 5.3.

ChaosBlessingsCore = ChaosBlessingsCore or {}
local K = ChaosBlessingsCore

local function entryOf(cfg, key)
	for _, e in ipairs(cfg.pool or {}) do
		if e.key == key then
			return e
		end
	end
	return nil
end
K.entry = entryOf

function K.newState()
	return {active = {}, lastProcMs = nil}
end

-- ------------------------------------------------------------------ the chance
function K.levelFactor(cfg, playerLevel, monsterLevel)
	local g = cfg.levelGap or {}
	playerLevel, monsterLevel = tonumber(playerLevel) or 1, tonumber(monsterLevel) or 0
	if monsterLevel <= 0 or playerLevel - monsterLevel <= (g.grace or 0) then
		return 1 -- no known level, or close enough
	end
	local share = monsterLevel / math.max(1, playerLevel)
	for _, row in ipairs(g.ratio or {}) do
		if share >= row[1] then
			return row[2]
		end
	end
	return 0
end

function K.chance(cfg, tier, playerLevel, monsterLevel)
	local base = (cfg.chance or {})[tier or "normal"] or (cfg.chance or {}).normal or 0
	local pct = base * K.levelFactor(cfg, playerLevel, monsterLevel)
	return math.max(0, math.min(pct, cfg.maxChance or 100))
end

function K.ready(cfg, st, now)
	return st.lastProcMs == nil or now - st.lastProcMs >= (cfg.cooldownMs or 0)
end

-- ------------------------------------------------------------------ the draw
-- rand(a, b): an integer in [a, b]
function K.pick(cfg, rand)
	local total = 0
	for _, e in ipairs(cfg.pool or {}) do
		total = total + math.max(0, e.weight or 0)
	end
	if total <= 0 then
		return nil
	end
	local r = rand(1, total)
	for _, e in ipairs(cfg.pool) do
		r = r - math.max(0, e.weight or 0)
		if r <= 0 then
			return e
		end
	end
	return cfg.pool[#cfg.pool]
end

local function count(st)
	local n = 0
	for _ in pairs(st.active) do
		n = n + 1
	end
	return n
end
K.count = count

-- the active blessing with the least time left (ties: the key, so the outcome never depends on table order)
local function weakest(st)
	local key, untilMs
	for k, a in pairs(st.active) do
		if not key or a.untilMs < untilMs or (a.untilMs == untilMs and k < key) then
			key, untilMs = k, a.untilMs
		end
	end
	return key
end

function K.grant(cfg, st, key, now)
	local untilMs = now + (cfg.durationMs or 60000)
	local a = st.active[key]
	if a then
		a.untilMs = untilMs -- no stacking: the full time again
		return {action = "refresh", key = key, untilMs = untilMs}
	end
	local out = {action = "new", key = key, untilMs = untilMs}
	if count(st) >= math.max(1, cfg.maxActive or 3) then
		out.replaced = weakest(st)
		out.action = "replace"
		st.active[out.replaced] = nil
	end
	st.active[key] = {untilMs = untilMs, sinceMs = now}
	return out
end

-- info: {tier, playerLevel, monsterLevel, blocked = reason or nil}; returns the grant or nil, reason
function K.roll(cfg, st, info, now, rand)
	if cfg.enabled == false then
		return nil, "disabled"
	end
	if info.blocked then
		return nil, info.blocked
	end
	if not K.ready(cfg, st, now) then
		return nil, "cooldown"
	end
	local pct = K.chance(cfg, info.tier, info.playerLevel, info.monsterLevel)
	if pct <= 0 then
		return nil, "trivial"
	end
	-- resolution 1/10000 %
	if rand(1, 1000000) > pct * 10000 then
		return nil, "miss"
	end
	local e = K.pick(cfg, rand)
	if not e then
		return nil, "empty pool"
	end
	st.lastProcMs = now
	return K.grant(cfg, st, e.key, now)
end

-- ------------------------------------------------------------------ what is active
function K.expire(st, now)
	local gone = {}
	for k, a in pairs(st.active) do
		if a.untilMs <= now then
			gone[#gone + 1] = k
		end
	end
	table.sort(gone)
	for _, k in ipairs(gone) do
		st.active[k] = nil
	end
	return gone
end

function K.left(st, key, now)
	local a = st and st.active[key]
	if not a or a.untilMs <= now then
		return 0
	end
	return a.untilMs - now
end

-- the blessing's value while it runs, else 0
function K.value(cfg, st, key, now)
	if K.left(st, key, now) <= 0 then
		return 0
	end
	local e = entryOf(cfg, key)
	return e and e.value or 0
end

-- 1 + value / 100 while it runs, else 1 (a "ward" gives 1 - value / 100)
function K.mult(cfg, st, key, now)
	local v = K.value(cfg, st, key, now)
	if v == 0 then
		return 1
	end
	if key == "ward" then
		return math.max(0, 1 - v / 100)
	end
	return 1 + v / 100
end

-- a damage value (may be negative) times m, rounded toward zero
function K.scale(v, m)
	local a = math.floor(math.abs(v * m) + 1e-6)
	return v < 0 and -a or a
end

-- the extra speed of the Ember of Haste for a base speed
function K.speedDelta(cfg, baseSpeed)
	local e = entryOf(cfg, "speed")
	return math.floor((tonumber(baseSpeed) or 0) * (e and e.value or 0) / 100)
end

-- health and mana per regeneration tick of the Ember of Renewal (at least 1 each)
function K.regenAmounts(cfg, maxHealth, maxMana)
	local e = entryOf(cfg, "regen")
	local pct = e and e.value or 0
	return math.max(1, math.floor((tonumber(maxHealth) or 0) * pct / 100)),
		math.max(1, math.floor((tonumber(maxMana) or 0) * pct / 100))
end

-- the buff bar items: {key, name, desc, leftMs}, longest time left first, then by key
function K.list(cfg, st, now)
	local out = {}
	for k, a in pairs(st and st.active or {}) do
		local e = entryOf(cfg, k)
		if e and a.untilMs > now then
			out[#out + 1] = {key = k, name = e.name, desc = string.format(e.desc or "", e.value or 0), leftMs = a.untilMs - now}
		end
	end
	table.sort(out, function(x, y)
		if x.leftMs ~= y.leftMs then
			return x.leftMs > y.leftMs
		end
		return x.key < y.key
	end)
	return out
end

return K
