-- The Apothecary of the hub (apothecary_config.lua; the shop is the NPC's own XML and script, data/npc/Veyra the
-- Apothecary.xml and data/npc/scripts/veyra_the_apothecary.lua; server/README.md "The Apothecary"). This file only places
-- her at startup: in her stall of the hub (npc_booths_config.lua names it; ChaosNpcPlace.place asks the stall first),
-- else next to the temple. No opcode, no storage key, no table of its own.
-- Lua 5.1 / LuaJIT. Assumed engine API (TFS 1.4): GlobalEvent, addEvent, Town, Town:getTemplePosition.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not ChaosNpcPlace then
	dofile("data/scripts/chaos/npc_place.lua")
end

ChaosApothecary = ChaosApothecary or {}
local M = ChaosApothecary
local cfg = dofile("data/scripts/chaos/apothecary_config.lua")
M.cfg = cfg

local function log(text)
	print("[Chaos apothecary] " .. text)
end

-- her NPC in every town of cfg.towns; the number placed
function M.place()
	local placed, missed = 0, {}
	for _, id in ipairs(cfg.towns) do
		local town = Town(id)
		local temple = town and town:getTemplePosition()
		local ok, res = false, nil
		if temple then
			ok, res = pcall(ChaosNpcPlace.place, cfg.npc, temple, cfg.offsets)
		end
		if ok and res then
			placed = placed + 1
		else
			missed[#missed + 1] = tostring(id)
		end
	end
	if #missed > 0 then
		log("no " .. cfg.npc .. " in town " .. table.concat(missed, ", ") .. " (no free tile, or data/npc/" .. cfg.npc ..
			".xml is missing: tools/install_apothecary.py)")
	end
	return placed
end

local startup = GlobalEvent("ChaosApothecaryStartup")
function startup.onStartup()
	if cfg.enabled then
		addEvent(function()
			log(M.place() .. " apothecary placed")
		end, cfg.delayMs or 4300)
	end
	return true
end
startup:register()
