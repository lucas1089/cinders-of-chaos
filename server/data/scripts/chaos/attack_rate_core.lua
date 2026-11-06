-- attack_rate_core.lua: damage per hit and on-hit triggers at high attack rates (the 3 attacks per second cap, engine
-- src-patch 0088; server/README.md "Attack speed cap"). Pure Lua, no engine calls; tests/attack_speed_cap_test.lua.
--   * hitFactor(intervalMs): the multiplier of an auto attack hit. 1 for a swing of refIntervalMs (1000) or slower,
--     (interval / 1000) ^ curveExponent below, so the damage per second grows with rate ^ (1 - exponent) above one
--     attack per second, not linearly. weapon_styles.lua applies it to every weapon hit of a player.
--   * allow(state, key, nowMs): a per-second limit for the extras a hit triggers (off-hand strike, cleave, ricochet...):
--     true at most limits[key] times per second per state (one state per player).
-- Lua 5.1 / LuaJIT and 5.3.
ChaosAttackRate = ChaosAttackRate or {}
local R = ChaosAttackRate

if not R.config then
	R.config = dofile("data/scripts/chaos/attack_rate_config.lua")
end

-- the hit multiplier of a swing interval in ms (1 when slow, unknown or off)
function R.hitFactor(intervalMs, cfg)
	cfg = cfg or R.config
	local ref, k = tonumber(cfg.refIntervalMs) or 1000, tonumber(cfg.curveExponent) or 0
	local i = tonumber(intervalMs) or 0
	if i <= 0 or i >= ref or k <= 0 then
		return 1
	end
	return (i / ref) ^ k
end

-- the damage per second of a swing interval relative to one attack per second
function R.dpsFactor(intervalMs, cfg)
	local i = tonumber(intervalMs) or 0
	if i <= 0 then
		return 1
	end
	return R.hitFactor(i, cfg) * (1000 / i)
end

-- attacks per second of an interval
function R.rate(intervalMs)
	local i = tonumber(intervalMs) or 0
	return i > 0 and 1000 / i or 0
end

function R.limit(key, cfg)
	cfg = cfg or R.config
	local v = cfg.limits and cfg.limits[key]
	return tonumber(v) or tonumber(cfg.procPerSecond) or 0
end

-- state = {} per player; key = "offhand", "bloodrage", ...; nowMs. A limit of 0 or less turns the rule off.
function R.allow(state, key, nowMs, cfg)
	local per = R.limit(key, cfg)
	if per <= 0 then
		return true
	end
	local last = state[key]
	if last and nowMs - last < 950 / per then -- 5% slack: a timer a few ms early still counts
		return false
	end
	state[key] = nowMs
	return true
end

function R.now()
	return os.mtime and os.mtime() or os.time() * 1000
end

-- per player id states for the engine files; R.gate(pid, key) = allow on the player's state at the current time
R.states = R.states or {}
function R.gate(pid, key)
	local st = R.states[pid]
	if not st then
		st = {}
		R.states[pid] = st
	end
	return R.allow(st, key, R.now())
end

function R.clear(pid)
	R.states[pid] = nil
end
