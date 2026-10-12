-- Dynamic respawn (server/README.md "Spawn density and respawn"): where several players hunt close together the map
-- spawns around them respawn faster. Every tickSeconds the hunters online are counted (respawn_core.lua) and the
-- spawn intervals are set with Game.setSpawnIntervalPercent, which engine patch src-patches/0022-dynamic-respawn.patch
-- adds, or in one call with Game.setSpawnIntervalZones (src-patches/0027-game-loop-stalls.patch); without patch 0022
-- this file only logs once that the function is missing. Numbers: respawn_config.lua.
-- Lua 5.1 / LuaJIT compatible.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not ChaosRespawn or not ChaosRespawn.plan then
	dofile("data/scripts/chaos/respawn_core.lua")
end
ChaosRespawnConfig = dofile("data/scripts/chaos/respawn_config.lua")

local R = ChaosRespawn
R.state = R.state or {}

local function inProtectionZone(player)
	local tile = Tile(player:getPosition())
	return tile ~= nil and tile:hasFlag(TILESTATE_PROTECTIONZONE)
end

-- the players that count as hunting: {x, y, z, ip}
function R.collect(cfg)
	local out = {}
	for _, player in ipairs(Game.getPlayers() or {}) do
		if not Chaos.isStaff(player) and not inProtectionZone(player)
				and (not cfg.requireInFight or player:hasCondition(CONDITION_INFIGHT)) then
			local pos = player:getPosition()
			out[#out + 1] = {x = pos.x, y = pos.y, z = pos.z, ip = player:getIp()}
		end
	end
	return out
end

-- one tick; returns the number of engine calls made (nil when the engine has no setSpawnIntervalPercent)
function R.tick()
	local cfg = ChaosRespawnConfig
	if not Game.setSpawnIntervalPercent then
		if not R.warned then
			R.warned = true
			print("[ChaosRespawn] Game.setSpawnIntervalPercent is missing (engine patch 0022 not built): dynamic respawn off")
		end
		return nil
	end
	local zones = cfg.enabled and R.zones(R.collect(cfg), cfg) or {}
	local plan = R.plan(R.state, zones, cfg.enabled and cfg or {globalPercent = 100})
	-- engine patch 0027: the whole plan in one call through the engine's spawn index (the calls below make one pass
	-- over every map spawn per zone)
	if Game.setSpawnIntervalZones then
		local global, list = R.zoneList(plan)
		if global then
			Game.setSpawnIntervalZones(global, list)
		end
		return #plan
	end
	for _, call in ipairs(plan) do
		if call.from then
			Game.setSpawnIntervalPercent(call.percent, Position(call.from.x, call.from.y, call.from.z),
				Position(call.to.x, call.to.y, call.to.z))
		else
			Game.setSpawnIntervalPercent(call.percent)
		end
	end
	return #plan
end

local think = GlobalEvent("ChaosRespawnTick")
function think.onThink(interval)
	local ok, err = pcall(R.tick)
	if not ok then
		print("[ChaosRespawn] " .. tostring(err))
	end
	return true
end
think:interval((ChaosRespawnConfig.tickSeconds or 20) * 1000)
think:register()
