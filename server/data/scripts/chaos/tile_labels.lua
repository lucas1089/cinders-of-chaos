-- Orange name labels over tiles: the engine side (tile_labels_core.lua collects them, tile_labels_config.lua the
-- settings; server/README.md "Tile labels"). Every intervalMs each label is sent as animated text (combat_fx.lua
-- ChaosCombatFx.label, opcode 0x84) to the players who see its tile; nothing is sent for a tile nobody sees.
-- Assumed engine API (TFS 1.4): GlobalEvent, Game.getSpectators (through ChaosCombatFx.label).
if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
dofile("data/scripts/chaos/tile_labels_core.lua")

ChaosTileLabels = ChaosTileLabels or {}
local X = ChaosTileLabels
X.config = dofile("data/scripts/chaos/tile_labels_config.lua")

function X.list()
	if not ChaosNpcBoothsCore or not ChaosNpcBoothsCore.booths then
		dofile("data/scripts/chaos/npc_booths_core.lua")
	end
	local B = ChaosNpcBoothsCore
	if not ChaosNpcPlaceCore or not ChaosNpcPlaceCore.templeStands then
		dofile("data/scripts/chaos/npc_place_core.lua")
	end
	local P = ChaosNpcPlaceCore
	return ChaosTileLabelsCore.collect(X.config, B.cfg(), B, P.templeStands(P.templeConfig()))
end

function X.pulse()
	if not X.config.enabled or not ChaosCombatFx or not ChaosCombatFx.label then
		return 0
	end
	X.cache = X.cache or X.list()
	local n = 0
	for _, l in ipairs(X.cache) do
		if ChaosCombatFx.label({x = l.x, y = l.y, z = l.z}, l.text, X.config.color) then
			n = n + 1
		end
	end
	return n
end

local think = GlobalEvent("ChaosTileLabels")
function think.onThink(interval)
	local ok, err = pcall(X.pulse)
	if not ok then
		print("[tile_labels] " .. tostring(err))
	end
	return true
end
think:interval(X.config.intervalMs or 3000)
think:register()
