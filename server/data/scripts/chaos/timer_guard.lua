-- Timer guard, the engine glue (O579; the logic is data/lib/chaos_timer_guard.lua, server/README.md "Timer guard"): installs the
-- guarded addEvent, so a timer callback that errors is printed with the script and line it was written in ("[Chaos timer error]
-- ...") instead of throwing into the engine as "Lua Script Error: [Main Interface] in a timer event called from: (Unknown
-- scriptfile)". Scripts that keep the engine's addEvent in a local load the lib first (_supports.lua, combatlog.lua,
-- chaos_fx_owner.lua). Lua 5.1 / LuaJIT and Lua 5.3 compatible.
if not ChaosTimerGuard or not ChaosTimerGuard.install then
	dofile("data/lib/chaos_timer_guard.lua")
end
ChaosTimerGuard.install()
