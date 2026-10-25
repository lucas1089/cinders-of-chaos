-- Weather, the pure part (weather.lua is the engine glue; tests/weather_test.lua; numbers in weather_config.lua;
-- server/README.md "Weather on the client (O208)"). The server only decides: whether it rains, how strong, and where.
-- State: {raining, intensity, nextRollAt}. Each player has a "last sent" signature, so a message goes out only when
-- what that player should see changes. The message (JSON on ChaosOpcodes.weather, action "set"):
--     {k = "rain", i = 1..3, f = fadeMs}      or      {k = "none", f = fadeMs}
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible. Time is in ms, supplied by the caller; luck is a function rng(n) -> 1..n.
ChaosWeather = ChaosWeather or {}
local W = ChaosWeather

function W.newState()
	return {raining = false, intensity = 0, nextRollAt = nil}
end

-- the strength of a new rain by the weights of cfg.intensities; falls back to 2
function W.pickIntensity(cfg, rng)
	local total = 0
	for _, e in ipairs(cfg.intensities or {}) do
		total = total + math.max(0, e.weight or 0)
	end
	if total <= 0 then
		return 2
	end
	local roll = rng(total)
	for _, e in ipairs(cfg.intensities) do
		local w = math.max(0, e.weight or 0)
		if roll <= w then
			return e.level
		end
		roll = roll - w
	end
	return 2
end

local function setRain(state, cfg, on, rng, level)
	if on then
		state.raining = true
		state.intensity = level and math.max(1, math.min(3, math.floor(level))) or W.pickIntensity(cfg, rng)
	else
		state.raining = false
		state.intensity = 0
	end
end

-- at server start (the base: 15% rain)
function W.startup(state, cfg, rng, now)
	setRain(state, cfg, rng(100) <= cfg.startChance, rng)
	state.nextRollAt = now + cfg.rollMs
end

-- the base's five-minute dice; true when the weather changed. A tick that comes late rolls once, not once per missed turn.
function W.roll(state, cfg, rng, now)
	if state.nextRollAt == nil then
		state.nextRollAt = now + cfg.rollMs
		return false
	end
	if now < state.nextRollAt then
		return false
	end
	state.nextRollAt = now + cfg.rollMs
	if state.raining then
		if rng(100) <= cfg.stopChance then
			setRain(state, cfg, false)
			return true
		end
	elseif rng(100) <= cfg.startChance then
		setRain(state, cfg, true, rng)
		return true
	end
	return false
end

-- staff: set it by hand (level nil = a fresh roll of the strength); the dice go on from now
function W.set(state, cfg, on, rng, level, now)
	setRain(state, cfg, on, rng, level)
	if now then
		state.nextRollAt = now + cfg.rollMs
	end
end

-- the area that holds a tile {x, y, z}, or nil
function W.areaAt(cfg, pos)
	if type(pos) ~= "table" or not pos.z then
		return nil
	end
	for _, a in ipairs(cfg.areas or {}) do
		if pos.z >= (a.minZ or 0) and pos.z <= (a.maxZ or 15) then
			local b = a.box
			if not b or (pos.x >= b[1] and pos.x <= b[3] and pos.y >= b[2] and pos.y <= b[4]) then
				return a
			end
		end
	end
	return nil
end

-- what the player at pos should see now
function W.message(state, cfg, pos)
	local a = W.areaAt(cfg, pos)
	if a and state.raining and a.kind == "rain" then
		return {k = "rain", i = state.intensity, f = cfg.fadeMs}
	end
	return {k = "none", f = cfg.fadeMs}
end

local function signature(msg)
	return msg.k .. ":" .. tostring(msg.i or 0)
end

-- The message to send to a player now, or nil when it is what he already has. `sent` is a table id -> signature (a
-- player is taken to see "none" until a first message went out, so a dry world sends nothing to nobody, except with
-- `force`: the client asked, or just logged in).
function W.decide(sent, id, state, cfg, pos, force)
	local msg = W.message(state, cfg, pos)
	local sig = signature(msg)
	if not force and (sent[id] or "none:0") == sig then
		return nil
	end
	sent[id] = sig
	return msg
end

function W.forget(sent, id)
	sent[id] = nil
end
