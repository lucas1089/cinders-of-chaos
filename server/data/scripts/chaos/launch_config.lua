-- The launch moment (O463): THE one value every launch date of the game is worked out from. Data only.
-- Read by launch_core.lua (ChaosLaunch), which founder_config.lua, creator_codes_config.lua, season_config.lua,
-- battleground_config.lua and chaos_constants.lua call; and by the owner tools and generators (server/deploy/launch_check.py,
-- tools/ci/launch_rehearsal_core.py, website/tools/gen_calendar_data.py, gen_promo_kit.py, gen_streamer_kit.py). Overview:
-- docs/LAUNCH.md "Launch date: on hold", server/README.md "Launch date (O463)". Lua 5.1 / LuaJIT and Lua 5.3 compatible.
--
-- launch = "open"                 no launch date yet (owner, 2026-11-10: "leave the launch of the game open for now").
--                                 Nothing starts by itself on a launch date, nothing prints one: the Founder Pack is not on sale,
--                                 the creator launch bonus is off, Season 1 and PvP season 1 wait, and the texts say "Coming
--                                 soon" ("Em breve"). Everything the beta server does today keeps working.
-- launch = "YYYY-MM-DD HH:MM"     the launch, server local time (America/Sao_Paulo, UTC-3; timezone_config.lua). Setting it is
--                                 the one change that sets every date again; then run the commands of docs/LAUNCH.md.
-- Keep the value on ONE line, in double quotes: the Python tools read it with a one-line reader.
return {
	launch = "open",

	-- Days from the launch day to the moments worked out from it (negative = before). They are documented in docs/LAUNCH.md and
	-- docs/BETA.md; the rehearsal and the calendar read them from here, not from a copy. Season 1 ends `lengthDays` (91, 13
	-- weeks) after the launch (season_config.lua); PvP season 1 and the Tower season have their lengths in their own configs.
	offsets = {
		freeze = -5,       -- content freeze: Sun, five days before the launch
		wipe = -2,         -- beta wipe and launch install: Wed
		rehearsal = -1,    -- launch rehearsal: Thu
		founderEnd = 28    -- the Founder Pack sale ends four weeks after the launch, at the launch hour
	}
}
