-- rumours_run.lua: the engine side of the tavern rumours (O394) for the rumour NPC, loaded by
-- data/npc/scripts/chaos_service_npc.lua in the NPC's own Lua state (it is not a revscript: nothing is registered).
-- The rules are rumours_core.lua; the spawner of the planned appearances is rumours.lua (main state). Both read the
-- same config and hunt places, so a true rumour names what rumours.lua will spawn.
--   ChaosRumoursRun.sources(now)              {regions, invasions, worldBoss}: what a rumour may be about
--   ChaosRumoursRun.ask(player, now, rng)     "off" | "nothing" | "money", fee | "told", rumour, fee
-- Engine API used: Game.getStorageValue (the world boss rotation, a global storage), Player:getGuid / getLevel and
-- Chaos.pay (carried coins, then the bank). Lua 5.1 / LuaJIT and 5.3.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not ChaosRumoursCore then
	dofile("data/scripts/chaos/rumours_core.lua")
end

ChaosRumoursRun = ChaosRumoursRun or {}
local M = ChaosRumoursRun
local R = ChaosRumoursCore

M.cfg = M.cfg or dofile("data/scripts/chaos/rumours_config.lua")
M.heard = M.heard or {} -- guid -> {rumour key -> until}; memory of this NPC state (a restart forgets it)
M.PLACES = "data/lib/chaos_hunt_places.lua"

-- the hunt places file of the installed server (install_content_areas.py), or nil
function M.places(path)
	local f = io.open(path or M.PLACES, "r")
	if not f then
		return nil
	end
	f:close()
	local ok, places = pcall(dofile, path or M.PLACES)
	return ok and type(places) == "table" and places or nil
end

function M.regions()
	if not M.regionList then
		M.regionList = R.regions(M.cfg, M.places())
	end
	return M.regionList
end

local function invasions(now, horizon)
	local okCore = ChaosInvasionCore and ChaosInvasionCore.upcoming or pcall(dofile, "data/scripts/chaos/invasion_core.lua")
	if not okCore or not ChaosInvasionCore then
		return {}
	end
	local I = ChaosInvasionCore
	if not M.invasionCfg then
		local ok, c = pcall(dofile, "data/scripts/chaos/invasion_config.lua")
		M.invasionCfg = ok and type(c) == "table" and c or {}
	end
	local c = M.invasionCfg
	if not c.enabled then
		return {}
	end
	local out = {}
	local ok, list = pcall(I.upcoming, c, now, horizon)
	for _, s in ipairs(ok and list or {}) do
		local area = s.areaKey and I.areaByKey(c, s.areaKey)
		local faction = s.factionKey and (c.factions or {})[s.factionKey]
		if area and faction then
			out[#out + 1] = {at = s.at, areaName = area.name, factionName = faction.name}
		end
	end
	return out
end

local function worldBoss(now)
	local wb = Chaos.worldBoss
	if not wb or not wb.enabled then
		return nil
	end
	local last = Game and Game.getStorageValue and wb.rotationStorage and Game.getStorageValue(wb.rotationStorage) or -1
	return {at = R.worldBossNext(now, wb), name = R.worldBossName(wb, last, (M.cfg.worldBoss or {}).unknownName)}
end

function M.sources(now)
	local horizon = ((M.cfg.horizonMinutes or 60) + 5) * 60
	return {regions = M.regions(), invasions = invasions(now, horizon), worldBoss = worldBoss(now)}
end

-- one ask: "off" (switched off), "nothing" (nothing new for this player: no fee), "money", fee (could not pay; the
-- rumour stays untold), "told", rumour, fee
function M.ask(player, now, rng)
	if not M.cfg.enabled then
		return "off"
	end
	now = now or os.time()
	rng = rng or math.random
	R.purge(M.heard, now)
	local guid = player:getGuid()
	local cands = R.candidates(M.cfg, now, M.sources(now))
	local mine = M.heard[guid] or {}
	local new = false
	for _, c in ipairs(cands) do
		if not mine[c.key] then
			new = true
			break
		end
	end
	if not new then
		return "nothing"
	end
	local fee = R.fee(M.cfg, player:getLevel())
	if fee > 0 and not Chaos.pay(player, fee) then
		return "money", fee
	end
	local rumour = R.ask(M.cfg, M.heard, guid, now, cands, rng, M.regions())
	return "told", rumour, fee
end

return M
