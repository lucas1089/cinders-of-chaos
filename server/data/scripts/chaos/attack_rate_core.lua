-- attack_rate_core.lua: per-second limits of the extras a hit triggers at high attack rates (the 3 attacks per second cap,
-- engine src-patch 0088; server/README.md "Attack speed cap"). Pure Lua, no engine calls; tests/attack_speed_cap_test.lua.
-- An auto attack hit keeps its full damage at any swing rate (owner 2026-11-06: "keep the auto hit worth the same"), so
-- the damage per second of the auto attack grows with the rate. The per-hit reduction of the first O426 version is gone.
--   * allow(state, key, nowMs): a per-second limit for the extras a hit triggers (off-hand strike, cleave, ricochet...):
--     true at most limits[key] times per second per state (one state per player).
-- Lua 5.1 / LuaJIT and 5.3.
ChaosAttackRate = ChaosAttackRate or {}
local R = ChaosAttackRate

if not R.config then
	R.config = dofile("data/scripts/chaos/attack_rate_config.lua")
end

-- the share of the weapon-use skill tries a vocation keeps: its base interval now / before O429 (1 when not shorter)
function R.trainFactor(vocId, currentMs, cfg)
	cfg = cfg or R.config
	local old = tonumber(cfg.trainOld and cfg.trainOld[vocId]) or tonumber(cfg.trainDefault) or 0
	local now = tonumber(currentMs) or 0
	if old <= 0 or now <= 0 or now >= old then
		return 1
	end
	return now / old
end

-- whole tries out of tries x factor, the fraction carried in state.carry (a try is an integer; never loses a share)
function R.trainTries(state, tries, factor)
	tries = tonumber(tries) or 0
	if tries <= 0 or not factor or factor >= 1 then
		return tries
	end
	local v = tries * factor + (state.carry or 0)
	local whole = math.floor(v)
	state.carry = v - whole
	return whole
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
