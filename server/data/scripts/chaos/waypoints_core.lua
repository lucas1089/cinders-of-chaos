-- waypoints_core.lua: is a base waypoint open for a character (waypoints_config.lua; server/README.md "Waypoints for
-- everyone (O386)"). The base script data/scripts/customs/waypoints/waypoint.lua calls ChaosWaypointsCore.unlocked
-- once tools/patch_base_waypoints.py has patched it. Pure Lua, no engine calls; tests/waypoints_test.lua.
-- Lua 5.1 / LuaJIT and 5.3.

ChaosWaypointsCore = ChaosWaypointsCore or {}
local W = ChaosWaypointsCore

-- the config, read once (a missing or broken file counts as the base rule)
function W.cfg()
	if W.loaded == nil then
		local ok, cfg = pcall(dofile, "data/scripts/chaos/waypoints_config.lua")
		W.loaded = (ok and type(cfg) == "table") and cfg or false
	end
	return W.loaded or {}
end

-- open: every waypoint while cfg.unlockAll is on, else the base rule (the storage value is 1 once stepped on)
function W.unlocked(cfg, storageValue)
	if type(cfg) == "table" and cfg.unlockAll == true then
		return true
	end
	return tonumber(storageValue) == 1
end

-- the base script's call: the player's storage is read only when the switch is off
function W.isUnlocked(player, aid)
	local cfg = W.cfg()
	if cfg.unlockAll == true then
		return true
	end
	return W.unlocked(cfg, player:getStorageValue(aid))
end

return W
