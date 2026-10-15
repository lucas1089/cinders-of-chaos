-- catchup_core.lua: the rules of time-friendly progression (ChaosCatchupCore), no engine needed. The engine part is
-- catchup.lua, the numbers catchup_config.lua, the tests server/tests/catchup_test.lua. Lua 5.1 / LuaJIT and Lua 5.3.
--
--   K.expForLevel(level)                    total experience of a level (the engine's formula)
--   K.hoursPerLevel(cfg, level)             the leveling model's hours for one level at `level`
--   K.xpPerMinute(cfg, level)               experience per minute of model hunting at `level`
--   K.restedAfter(cfg, pool, offlineSec)    the rested pool (minutes) after an absence
--   K.isReturning(cfg, lastSeen, now)       the account was away long enough (lastSeen = 0: a new account, never)
--   K.altPct(cfg, level, best)              the alt catch-up bonus in percent
--   K.staminaLow(cfg, stamina)              at or below the low stamina line
--   K.staminaLootMult(cfg, stamina)         loot factor of the stamina (1 or stamina.lootMult)
--   K.staminaXpFactor(cfg, stamina)         experience factor on top of the base script's own low stamina rule
--   K.xpGain(cfg, exp, f)                   the experience after the bonuses and the rested minutes it spent
--   K.lootMult(cfg, f) / K.tokenMult(cfg, f)
-- f (facts) = {level, stamina, pool = rested minutes, returning = bool, best = account best level, season = bool}

ChaosCatchupCore = ChaosCatchupCore or {}
local K = ChaosCatchupCore

local floor, max, min = math.floor, math.max, math.min

local function num(v, d)
	v = tonumber(v)
	if not v or v ~= v or v == math.huge or v == -math.huge then
		return d
	end
	return v
end

-- ---------------------------------------------------------------- the leveling model
function K.expForLevel(level)
	local lv = max(0, floor(num(level, 1)) - 1)
	return (50 * lv * lv * lv - 150 * lv * lv + 400 * lv) / 3
end

function K.hoursPerLevel(cfg, level)
	local model = cfg.model or {}
	level = max(1, num(level, 1))
	local last
	for _, band in ipairs(model) do
		local from, to, hours = band[1], band[2], band[3]
		if to > from then
			last = hours / (to - from)
			if level >= from and level < to then
				return last
			end
		end
	end
	return last or 0.05
end

function K.xpPerMinute(cfg, level)
	level = max(1, floor(num(level, 1)))
	local span = K.expForLevel(level + 1) - K.expForLevel(level)
	local minutes = K.hoursPerLevel(cfg, level) * 60
	if minutes <= 0 or span <= 0 then
		return 1
	end
	return span / minutes
end

-- ---------------------------------------------------------------- rested
function K.restedAfter(cfg, pool, offlineSec)
	local r = cfg.rested or {}
	pool = max(0, num(pool, 0))
	if r.enabled == false then
		return pool
	end
	local sec = num(offlineSec, 0) - (r.graceSeconds or 0)
	if sec <= 0 then
		return min(pool, r.capMinutes or 0)
	end
	return min(r.capMinutes or 0, pool + sec / 3600 * (r.minutesPerOfflineHour or 0))
end

-- a pool after n Rested Vials: (new pool, minutes added); nothing when the pool is full or n is not 1..10
function K.addVials(cfg, pool, n)
	local r = cfg.rested or {}
	pool = max(0, num(pool, 0))
	n = floor(num(n, 0))
	if r.enabled == false or n < 1 or n > 10 then
		return pool, 0
	end
	local cap = r.capMinutes or 0
	local after = min(cap, pool + n * (r.vialMinutes or 60))
	return max(pool, after), max(0, after - pool)
end

-- ---------------------------------------------------------------- returning and alts
function K.isReturning(cfg, lastSeen, now)
	local r = cfg.returning or {}
	lastSeen, now = num(lastSeen, 0), num(now, 0)
	if r.enabled == false or lastSeen <= 0 then
		return false
	end
	return now - lastSeen >= (r.awayDays or 14) * 86400
end

function K.returningUntil(cfg, now)
	return floor(num(now, 0) + ((cfg.returning or {}).durationDays or 7) * 86400)
end

function K.altPct(cfg, level, best)
	local a = cfg.alt or {}
	level, best = num(level, 0), num(best, 0)
	if a.enabled == false or best < (a.minBest or 0) or level >= best then
		return 0
	end
	local fade = max(a.minFade or 1, best * (a.fadeShare or 0))
	local share = min(1, (best - level) / fade)
	return (a.maxPct or 0) * share
end

-- ---------------------------------------------------------------- stamina
function K.staminaLow(cfg, stamina)
	local s = cfg.stamina or {}
	return num(stamina, 0) <= (s.lowAt or 840)
end

function K.staminaLootMult(cfg, stamina)
	if not K.staminaLow(cfg, stamina) then
		return 1
	end
	return max(0, num((cfg.stamina or {}).lootMult, 0))
end

function K.staminaXpFactor(cfg, stamina)
	if not K.staminaLow(cfg, stamina) then
		return 1
	end
	local s = cfg.stamina or {}
	local base = num(s.baseXpMult, 1)
	if base <= 0 then
		return 1
	end
	return max(0, num(s.xpMult, base)) / base
end

-- ---------------------------------------------------------------- the experience
-- Returns the experience and the rested minutes spent. exp is the kill's experience as it reaches this callback.
function K.xpGain(cfg, exp, f)
	exp = num(exp, 0)
	f = f or {}
	if exp <= 0 or cfg.enabled == false then
		return exp, 0
	end
	exp = exp * K.staminaXpFactor(cfg, f.stamina)
	if f.season and not cfg.seasonCharacters then
		return exp, 0
	end
	local cap = max(1, num(cfg.maxXpMult, 1))
	local other = 1
	if f.returning and (cfg.returning or {}).enabled ~= false then
		other = other * (1 + num(cfg.returning.xpPct, 0) / 100)
	end
	other = other * (1 + K.altPct(cfg, f.level, f.best) / 100)
	other = min(cap, other)
	local out = exp * other
	local spent = 0
	local r = cfg.rested or {}
	local pool = max(0, num(f.pool, 0))
	if r.enabled ~= false and pool > 0 then
		local restedMult = min(cap / other, 1 + num(r.bonusPct, 0) / 100)
		local perMin = max(1e-9, num(f.xpPerMin, K.xpPerMinute(cfg, f.level)))
		local bonus = min(out * (restedMult - 1), pool * perMin)
		if bonus > 0 then
			out = out + bonus
			spent = min(pool, bonus / perMin)
		end
	end
	return out, spent
end

function K.lootMult(cfg, f)
	f = f or {}
	if cfg.enabled == false then
		return K.staminaLow(cfg, f.stamina) and 0 or 1
	end
	local m = K.staminaLootMult(cfg, f.stamina)
	if f.returning and not (f.season and not cfg.seasonCharacters) and (cfg.returning or {}).enabled ~= false then
		m = m * (1 + num(cfg.returning.lootPct, 0) / 100)
	end
	return m
end

function K.tokenMult(cfg, f)
	f = f or {}
	if cfg.enabled == false or not f.returning or (f.season and not cfg.seasonCharacters)
			or (cfg.returning or {}).enabled == false then
		return 1
	end
	return 1 + num(cfg.returning.tokenPct, 0) / 100
end

-- the problems of a config (empty list = fine)
function K.validate(cfg)
	local out = {}
	local function bad(fmt, ...)
		out[#out + 1] = string.format(fmt, ...)
	end
	local s = cfg.stamina or {}
	if num(s.lootMult, -1) <= 0 then
		bad("stamina.lootMult must be above 0 (low stamina never zeroes the loot)")
	end
	if num(s.xpMult, -1) <= 0 then
		bad("stamina.xpMult must be above 0")
	end
	if num(s.offlineMult, 0) < 1 then
		bad("stamina.offlineMult below 1")
	end
	if num(cfg.maxXpMult, 0) < 1 then
		bad("maxXpMult below 1")
	end
	local prev = 0
	for i, b in ipairs(cfg.model or {}) do
		if b[1] < prev or b[2] <= b[1] or b[3] <= 0 then
			bad("model band %d is not increasing", i)
		end
		prev = b[2]
	end
	for k, v in pairs(cfg.storage or {}) do
		if v < 7102400 or v > 7102409 then
			bad("storage %s outside 7102400-7102409", k)
		end
	end
	return out
end

return K
