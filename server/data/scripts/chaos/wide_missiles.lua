-- Missile ids above 255, the engine glue (O737; data/lib/chaos_wide_missiles.lua, server/README.md "Missile ids above 255 (O737)").
-- At startup every fallback row goes to the engine (Game.setMissileFallback of src-patch 0094): a client without 16-bit missiles then
-- sees the one-byte stand-in of a missile above 255. Without the engine patch nothing is set.

if not ChaosWideMissiles then
	dofile("data/lib/chaos_wide_missiles.lua")
end
local W = ChaosWideMissiles

local startup = GlobalEvent("ChaosWideMissilesStartup")
function startup.onStartup()
	local problems = W.check()
	for _, p in ipairs(problems) do
		print("[ChaosWideMissiles] " .. p)
	end
	local ok, n = pcall(W.apply)
	if not ok then
		print("[ChaosWideMissiles] " .. tostring(n))
	elseif n > 0 then
		print("[ChaosWideMissiles] " .. n .. " missile fallbacks set")
	end
	return true
end
startup:register()
