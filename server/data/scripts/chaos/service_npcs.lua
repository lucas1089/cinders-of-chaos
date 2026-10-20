-- The service NPCs of the Halls of Services (service_npcs_config.lua, service_npcs_core.lua; the talk: service_npcs_run.lua
-- and data/npc/scripts/chaos_service_npc.lua; server/README.md "Service NPCs"). This file only places them at startup:
-- each stands in its booth of its town's hall (npc_booths_config.lua names it in a slot; ChaosNpcPlace.place asks
-- ChaosNpcBooths first), else next to the temple. No opcode, no storage key, no table of its own.
-- Lua 5.1 / LuaJIT. Assumed engine API (TFS 1.4): GlobalEvent, addEvent, Town, Town:getTemplePosition.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not ChaosServiceNpcsCore then
	dofile("data/scripts/chaos/service_npcs_core.lua")
end
if not ChaosNpcPlace then
	dofile("data/scripts/chaos/npc_place.lua")
end

ChaosServiceNpcs = ChaosServiceNpcs or {}
local M = ChaosServiceNpcs
local cfg = dofile("data/scripts/chaos/service_npcs_config.lua")
M.cfg = cfg

local function log(text)
	print("[Chaos service npcs] " .. text)
end

local function try(name, fn, ...)
	local ok, res = pcall(fn, ...)
	if not ok then
		log(name .. ": " .. tostring(res))
		return nil
	end
	return res
end

-- every NPC of the config in every town of cfg.towns; the number placed, the names that were not
function M.placeNpcs()
	local placed, missed = 0, {}
	for _, key in ipairs(cfg.order) do
		local npc = cfg.npcs[key]
		for _, id in ipairs(cfg.towns) do
			local town = Town(id)
			local temple = town and town:getTemplePosition()
			if temple and try("place " .. npc.name, ChaosNpcPlace.place, npc.name, temple, cfg.offsets) then
				placed = placed + 1
			else
				missed[#missed + 1] = npc.name .. "/" .. tostring(id)
			end
		end
	end
	if #missed > 0 then
		log("not placed: " .. table.concat(missed, ", ") .. " (no free tile, or data/npc/<name>.xml is missing: " ..
			"tools/install_service_npcs.py)")
	end
	return placed
end

local startup = GlobalEvent("ChaosServiceNpcsStartup")
function startup.onStartup()
	for _, p in ipairs(ChaosServiceNpcsCore.validate(cfg)) do
		log("config: " .. p)
	end
	if cfg.enabled then
		addEvent(function()
			log(M.placeNpcs() .. " service NPC(s) placed")
		end, cfg.delayMs or 4000)
	end
	return true
end
startup:register()
