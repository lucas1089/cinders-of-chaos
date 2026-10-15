-- catchup_config.lua: every number of "respect the player's time" (catchup.lua, catchup_core.lua; server/README.md
-- "Time-friendly progression (catchup)"). Plain table, loaded with
--     ChaosCatchupConfig = dofile("data/scripts/chaos/catchup_config.lua")
-- No engine calls here (server/tests/catchup_test.lua reads it with plain Lua). Lua 5.1 / LuaJIT and Lua 5.3.
--
-- Owner goal (2026-10-15): an adult with little time progresses fluidly; a heavy player still feels rewarded.
-- Four parts, each switchable: stamina (low stamina reduces, never zeroes), rested experience (offline time builds a
-- pool), the returning player boost (back after a long break) and the alt catch-up (characters below the account's best).
-- The numbers to review are listed in docs/OWNER_TODO.md "Time-friendly progression".

return {
	enabled = true,
	table = "chaos_catchup", -- one row per account (server/sql/chaos_catchup.sql; catchup.lua also creates it)

	-- player storages 7102400 - 7102409 (server/README.md "Storage keys")
	storage = {
		rested = 7102400, -- the rested pool in centi-minutes of model hunting (1 = 0.01 minute)
		lowNotice = 7102401, -- the day key (YYYYMMDD) of the last "low stamina" notice
		returningSeen = 7102402 -- the returning_until this character was already welcomed for
	},

	-- the EventCallback onGainExperience index: after the experience cap (xpcap_config.lua, 85), before the dungeon
	-- difficulty (90), the rift cap (100) and the hunt tracker (1000). These bonuses are the player's own time, so the
	-- cap does not eat them; they have their own ceiling (maxXpMult).
	xpIndex = 87,
	-- the rested, returning and alt bonuses multiply; together never above this (x3 = +200%)
	maxXpMult = 3.0,
	-- season characters race on a fresh start: no rested pool, no returning boost, no alt catch-up for them
	-- (the stamina rules below still apply)
	seasonCharacters = false,

	-- ------------------------------------------------------------------ stamina
	-- The stock rule (base server): at or below 14 hours of stamina a kill dropped NOTHING and gave half experience.
	-- Now the loot is cut, never zero: lootMult for the stock loot (tools/patch_base_events.py step 16) and the Chaos
	-- loot layer (loot.lua). The base experience rule (x0.5, baseXpMult) stays in the base script; xpMult / baseXpMult
	-- is applied on top (1 with the numbers below).
	stamina = {
		lowAt = 840, -- minutes (14 h); the stock threshold
		lootMult = 0.5,
		xpMult = 0.5,
		baseXpMult = 0.5,
		-- offline regeneration x this (tools/patch_base_events.py step 17; the Chaos Pact's x1.5 multiplies on top):
		-- stock 1 minute per 3 minutes offline (1 per 10 above 40 h). x2: a night of 8 h gives 5.3 h back (was 2.7 h);
		-- a player who plays up to about 9.5 h a day never runs dry (was 6 h)
		offlineMult = 2.0
	},

	-- ------------------------------------------------------------------ rested experience
	-- Offline time (past graceSeconds, as the stamina rule) fills a pool counted in minutes of "model hunting": the
	-- experience the leveling model (server/README.md "The leveling model and the hours") gets per minute at the
	-- character's level. While the pool lasts, monster experience gets +bonusPct %; the bonus itself is what the pool
	-- pays. 2.5 minutes per offline hour: a day away (23 h) is about 57 minutes, i.e. the whole hour of a one-hour
	-- player is doubled; the cap of 180 minutes is three days away. A player who logs out for 12 h gets 30 minutes.
	rested = {
		enabled = true,
		bonusPct = 100,
		minutesPerOfflineHour = 2.5,
		capMinutes = 180,
		graceSeconds = 600,
		-- a Rested Vial (the Candlemarks shop, ChaosRested.addVials) adds this many minutes, never past capMinutes
		vialMinutes = 60
	},
	-- the leveling model: {from level, to level, hours} (the sorcerer's base hours per band, the fastest vocation, the
	-- same table as rift_config.lua exp.model). Levels past the last band keep its hours per level.
	model = {{1, 100, 0.3}, {100, 300, 2.6}, {300, 500, 7.3}, {500, 700, 21.8}, {700, 800, 17.2}, {800, 900, 21.1},
		{900, 1000, 25.5}},

	-- ------------------------------------------------------------------ returning player
	-- An account none of whose characters was online for awayDays gets durationDays of: +xpPct % experience from
	-- monsters, +lootPct % Chaos loot (outside the loot cap), +tokenPct % token drop chance (faction tokens; other token
	-- systems ask ChaosCatchup.tokenMult). The welcome message points at the Next Goals panel when it exists.
	returning = {
		enabled = true,
		awayDays = 14,
		durationDays = 7,
		xpPct = 50,
		lootPct = 25,
		tokenPct = 50
	},

	-- ------------------------------------------------------------------ alt catch-up
	-- A character below the best level of its account (season characters do not count) gets +maxPct % monster
	-- experience while it is at least fade levels below; inside that band the bonus shrinks linearly to 0 at the best
	-- level. fade = max(minFade, best x fadeShare): best 500 -> full +100% up to level 400, +50% at 450, 0 at 500.
	alt = {
		enabled = true,
		minBest = 50, -- no catch-up before the account has a character of this level
		maxPct = 100,
		fadeShare = 0.2,
		minFade = 20
	}
}
