-- The clock zone the game needs (O439): data only. Read by timezone.lua (the startup line) and tests/timezone_test.lua.
-- The launch is Fri 2026-11-20 15:00 Brasilia time (UTC-3). weekend_config.lua, founder_config.lua, season_config.lua,
-- creator_codes_config.lua and the 06:00 save all read the machine's LOCAL time, so a VPS left in UTC starts them 3 hours off.
-- The deploy side keeps its own copy: server/tools/chaos_timezone.py (DEFAULT_ZONE, DEFAULT_OFFSET_MIN, and an optional
-- CHAOS_TIMEZONE in /etc/chaos/chaos.env). The two must agree: server/tools/chaos_health_test.py compares them.
-- Check and fix: `chaos-ctl.sh timezone` / `timezone set`, admin app Comandos > Acoes rapidas > Saude e espaco.
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.
return {
	zone = "America/Sao_Paulo",
	offsetMinutes = -180 -- minutes east of UTC; Brazil has had no daylight saving time since 2019
}
