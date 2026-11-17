-- Death and spawn effects of monsters, the engine glue (O456; rules deathfx_core.lua, numbers deathfx_config.lua,
-- tests/deathfx_test.lua; server/README.md "Death and spawn effects"). Visual only.
--
-- This file registers no hook of its own. The two hooks already there call it:
--   death  the CreatureEvent "ChaosCosmeticsDeath" of cosmetics.lua (registered once per monster by its onSpawn
--          callback, the kill cosmetics ride on it): ChaosDeathFx.onDeath(creature)
--   spawn  the EventCallback onSpawn of cosmetics.lua (before the placement): ChaosDeathFx.onSpawn(...)
-- Cost: one Lua call and one effect packet (Position:sendMagicEffect, sent to the spectators of the tile only) per
-- death and per respawn that passes the rules; no timer, no storage, no database. A token bucket per kind caps a pack
-- that dies or respawns in one instant (deathfx_config.lua budget).
-- Lua 5.1 / LuaJIT compatible.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not ChaosDeathFx or not ChaosDeathFx.decideDeath then
	dofile("data/scripts/chaos/deathfx_core.lua")
end
ChaosDeathFxConfig = dofile("data/scripts/chaos/deathfx_config.lua")

local K = ChaosDeathFx
K.state = K.state or {death = K.newBudget(ChaosDeathFxConfig.death.budget.capacity),
	spawn = K.newBudget(ChaosDeathFxConfig.spawn.budget.capacity)}

do
	local problems = K.validate(ChaosDeathFxConfig)
	for _, p in ipairs(problems) do
		print("[Chaos deathfx] config: " .. p)
	end
	K.ready = #problems == 0
end

local function nowMs()
	if os.mtime then
		return os.mtime()
	end
	return os.time() * 1000
end

local function raceOf(monster)
	local ok, race = pcall(function() return monster:getType():race() end)
	return ok and tonumber(race) or 0
end

local function isBoss(monster)
	local ok, res = pcall(function() return monster:getType():isBoss() end)
	return ok and res == true
end

local function send(pos, e)
	if not (pos and e) then
		return false
	end
	local ok = pcall(function()
		Position(pos.x + e.dx, pos.y + e.dy, pos.z):sendMagicEffect(e.id)
	end)
	return ok
end

-- a monster died (called by the death event of cosmetics.lua); returns true when an effect was sent
function K.onDeath(monster)
	if not K.ready or not monster or not monster.isMonster or not monster:isMonster() then
		return false
	end
	local hasMaster = monster:getMaster() ~= nil
	local e = K.decideDeath(ChaosDeathFxConfig, raceOf(monster), not hasMaster and isBoss(monster), hasMaster, K.state.death, nowMs())
	return send(e and monster:getPosition(), e)
end

-- a monster is about to be placed (called by the onSpawn callback of cosmetics.lua)
function K.onSpawn(monster, position, startup, artificial)
	if not K.ready or not monster or not position or (startup and ChaosDeathFxConfig.spawn.skipStartup) then
		return false
	end
	local boss = isBoss(monster)
	local e = K.decideSpawn(ChaosDeathFxConfig, raceOf(monster), boss, startup, artificial, K.state.spawn, nowMs())
	return send(position, e)
end
