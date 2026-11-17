-- Effects for roles that had none, the engine glue (O606; data/lib/chaos_gapfx.lua, server/README.md "Effects for roles
-- that had none (O606)"). The lib is loaded once here; the senders ask the global ChaosGapFx when their event happens,
-- so the load order of the scripts does not matter. Gate: config.lua chaosClientPair >= 73.
-- Lua 5.1 / LuaJIT / 5.3.

if not ChaosGapFx then
	dofile("data/lib/chaos_gapfx.lua")
end

local startup = GlobalEvent("ChaosGapFxStartup")
function startup.onStartup()
	local ok, live = pcall(ChaosGapFx.live)
	if ok and live then
		print("[ChaosGapFx] client pair " .. ChaosGapFx.PAIR .. ": " .. tostring(ChaosGapFxIds and ChaosGapFxIds.count or 0) .. " effects on")
	end
	return true
end
startup:register()
