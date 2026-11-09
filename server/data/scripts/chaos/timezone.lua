-- The clock zone guard (O439): at the start, one console line with the local time and the UTC offset, and a loud warning
-- line when the offset is not the expected one (timezone_config.lua). It never stops the server and never changes
-- anything. Pure logic: timezone_core.lua (tests/timezone_test.lua); overview: server/README.md "Timezone guard (O439)".
-- Check and fix from outside: chaos-ctl.sh timezone / timezone set. Assumed engine API (TFS 1.4): GlobalEvent onStartup, print.
-- Lua 5.1 / LuaJIT compatible.

if not ChaosTimezone then
	dofile("data/scripts/chaos/timezone_core.lua")
end

local cfg = dofile("data/scripts/chaos/timezone_config.lua")

local startup = GlobalEvent("ChaosTimezoneStartup")
function startup.onStartup()
	local ok, err = pcall(function()
		local r = ChaosTimezone.startup(cfg)
		for _, line in ipairs(r.lines) do
			print(line)
		end
	end)
	if not ok then
		print("[Chaos timezone] the zone check failed to run: " .. tostring(err))
	end
	return true
end
startup:register()
