-- Display scale (display_scale.lua, display_scale_core.lua, engine src-patch 0037, client game_chaosscale). Returned as a
-- table, loaded as Chaos.displayScaleConfig. See server/README.md "Display scale".
--
-- Every combat number a player SEES (damage and heal numbers, own health, monster and boss health, the DPS meter, the
-- combat log, the death recap, damage boards, the flat damage / heal values of spell and item tooltips) is the internal
-- number x factor(level), the factor of the VIEWER's own level (item tooltips: of the item's level requirement). The
-- internal numbers (health, damage, balance, the database) are never changed. Mana is never scaled (owner 2026-10-21:
-- a spell's mana cost is one fixed number at every level; engine src-patch 0052, server/README.md "Fixed spell
-- costs"): the own mana, spell costs, party members' mana and the mana rows of item tooltips stay as they are.
-- Lua 5.1 / LuaJIT compatible.
return {
	-- the curve: {level, factor} points; the factor is 1 up to the first point's level, between two points it grows
	-- exponentially (a straight line of log(factor)), past the last point it stays at the last factor (the cap). The
	-- factor is rounded to a whole number, so every shown number is the internal one x an integer: a sum of shown hits
	-- is exactly the shown total and a boss bar minus the shown hits is exactly its new value (no rounding drift).
	curve = {
		{100, 1}, -- levels 1-100 see the internal numbers (today's numbers)
		{1000, 1000}, -- level 1000: x1000 (the median single-target DPS of about 2600 is shown as about 2.6M)
		{1500, 10000} -- past 1000 slower (x10 over 500 levels), capped at x10000 from level 1500 on
	},

	-- the largest number sent: a JSON number stays exact up to 2^53; the engine's text message fields are uint32 and
	-- it clamps those itself (src-patch 0037)
	jsonMax = 9007199254740992,

	-- extended opcode of the client module game_chaosscale (server -> client only): the viewer's level and factor at
	-- login and at every level change. 157 is free in the base server, the base client and every Chaos module
	-- (server/README.md "Opcode collision check").
	opcode = 157,

	-- the engine's per-level factor table (Game.setDisplayScale of src-patch 0037) covers levels 1..tableLevels; a
	-- higher level uses the last entry (the cap)
	tableLevels = 1500,

	-- leaderboard boards whose value is damage or healing (leaderboard_config.lua keys); the others (kills, ratings,
	-- times, points, reputation) are never scaled
	leaderboardBoards = {worldboss = true, bosshealer = true, bosstank = true},

	-- item tooltip rows with a flat health / damage / heal value (item_tooltip_core.lua keys; a modifier's key is its
	-- attribute "chaos_mod_<key>"): scaled by the factor of the item's level requirement (req.level), never by the
	-- viewer's level. Attack, defence, armour, skills, speeds, every percent and every mana row (max mana, mana on hit /
	-- kill, mana gems: mana is never scaled) stay as they are.
	itemFlatKeys = {
		maxhealth = true, -- the item type's own stat
		thorns = true, lifeonkill = true, lifeonhit = true, regen = true, -- modifiers
		smolderaura = true, -- legendary power (chaos_powers.lua): fire damage per second
		gem_maxhealth = true -- gem effects in sockets
	}
}
