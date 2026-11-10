-- Death and spawn effects of monsters, the pure part (ChaosDeathFx; numbers deathfx_config.lua, engine glue deathfx.lua,
-- tests/deathfx_test.lua). server/README.md "Death and spawn effects". Lua 5.1 / LuaJIT compatible.
--   ChaosDeathFx.raceName(n)                       "venom" | "blood" | "undead" | "fire" | "energy" for the engine race 1..5
--   ChaosDeathFx.validate(cfg)                     list of problems (empty = fine)
--   ChaosDeathFx.newBudget(cap)                    a token bucket state
--   ChaosDeathFx.take(state, nowMs, budgetCfg)     true when an effect may start now (spends a token)
--   ChaosDeathFx.decideDeath(cfg, race, boss, hasMaster, state, nowMs)       the effect {id, dx, dy, ms} or nil
--   ChaosDeathFx.decideSpawn(cfg, race, boss, startup, artificial, state, nowMs)   the effect or nil
-- A death effect: not for a creature with a master (player summons and wolves, minions, a boss's adds: they have no
-- body and come in packs), by race, the large one for a boss (bosses skip the budget, they die one at a time). A spawn
-- effect: only a map respawn, never the start of the server, never a script-made monster, never a boss.

ChaosDeathFx = ChaosDeathFx or {}
local K = ChaosDeathFx

K.RACES = {[1] = "venom", [2] = "blood", [3] = "undead", [4] = "fire", [5] = "energy"}
K.RACE_NAMES = {"blood", "undead", "fire", "energy", "venom"}

function K.raceName(n)
	return K.RACES[tonumber(n) or 0]
end

local function isEffect(e)
	return type(e) == "table" and type(e.id) == "number" and e.id >= 1 and e.id <= 65535 and e.id == math.floor(e.id)
		and type(e.dx) == "number" and type(e.dy) == "number" and math.abs(e.dx) <= 4 and math.abs(e.dy) <= 4
		and type(e.ms) == "number"
end

local function checkSet(out, label, set, minMs, maxMs)
	if type(set) ~= "table" then
		out[#out + 1] = label .. " effects missing"
		return
	end
	for _, race in ipairs(K.RACE_NAMES) do
		local e = set[race]
		if not isEffect(e) then
			out[#out + 1] = label .. "." .. race .. " is no effect {id, dx, dy, ms}"
		elseif e.ms < minMs or e.ms > maxMs then
			out[#out + 1] = label .. "." .. race .. " lasts " .. e.ms .. " ms, expected " .. minMs .. " to " .. maxMs
		end
	end
end

local function checkBudget(out, label, b)
	if type(b) ~= "table" or type(b.capacity) ~= "number" or b.capacity < 1 or b.capacity > 40
			or type(b.perSecond) ~= "number" or b.perSecond <= 0 or b.perSecond > 60 then
		out[#out + 1] = label .. ".budget needs capacity 1 to 40 and perSecond above 0 up to 60"
	end
end

function K.validate(cfg)
	local out = {}
	if type(cfg) ~= "table" then
		return {"no config"}
	end
	if type(cfg.death) ~= "table" or type(cfg.spawn) ~= "table" then
		return {"death and spawn sections needed"}
	end
	checkSet(out, "death", cfg.death.effects, 300, 1000)
	checkSet(out, "death.boss", cfg.death.boss, 300, 1500)
	checkBudget(out, "death", cfg.death.budget)
	checkSet(out, "spawn", cfg.spawn.effects, 300, 1000)
	checkBudget(out, "spawn", cfg.spawn.budget)
	return out
end

-- a token bucket: capacity tokens, perSecond refilled per second, one spent per effect
function K.newBudget(cap)
	return {tokens = cap, at = nil}
end

function K.take(state, nowMs, b)
	if type(state) ~= "table" or type(b) ~= "table" then
		return false
	end
	if state.at == nil then
		state.tokens = b.capacity
	else
		local dt = nowMs - state.at
		if dt > 0 then
			state.tokens = math.min(b.capacity, (state.tokens or 0) + dt * b.perSecond / 1000)
		end
	end
	state.at = nowMs
	if state.tokens >= 1 then
		state.tokens = state.tokens - 1
		return true
	end
	return false
end

function K.decideDeath(cfg, race, boss, hasMaster, state, nowMs)
	if type(cfg) ~= "table" or not cfg.enabled or type(cfg.death) ~= "table" or not cfg.death.enabled or hasMaster then
		return nil
	end
	local name = type(race) == "string" and race or K.raceName(race)
	if not name then
		return nil
	end
	if boss then
		return cfg.death.boss and cfg.death.boss[name] or nil
	end
	local e = cfg.death.effects and cfg.death.effects[name]
	if e and K.take(state, nowMs, cfg.death.budget) then
		return e
	end
	return nil
end

function K.decideSpawn(cfg, race, boss, startup, artificial, state, nowMs)
	if type(cfg) ~= "table" or not cfg.enabled or type(cfg.spawn) ~= "table" or not cfg.spawn.enabled or boss then
		return nil
	end
	if (startup and cfg.spawn.skipStartup) or (artificial and cfg.spawn.skipArtificial) then
		return nil
	end
	local name = type(race) == "string" and race or K.raceName(race)
	local e = name and cfg.spawn.effects and cfg.spawn.effects[name]
	if e and K.take(state, nowMs, cfg.spawn.budget) then
		return e
	end
	return nil
end
