-- New player survey (survey.lua, survey_core.lua, sql/chaos_survey.sql; client game_chaossurvey; server/README.md "New
-- player funnel and survey (O374)"). Every number of the system. Plain data, Lua 5.1 / LuaJIT and Lua 5.3.
return {
	enabled = true,

	-- the survey is offered once per ACCOUNT and stage (an account with many characters answers each stage once): when a
	-- character reaches the level, or at a later login while its level is below stage + window (a character far past the
	-- stage, a veteran's alt or one from before the install, is not asked about its first steps)
	stages = {20, 50},
	window = 15,

	-- the window opens this many seconds after the level up or the login, and only out of combat (Chaos.inCombat); the
	-- think that sends it runs every checkSeconds
	delaySeconds = 4,
	checkSeconds = 5,

	-- "What confused you so far?": at most this many characters (UTF-8 letters, not bytes); control characters, invalid
	-- UTF-8 and 4-byte characters (the table is utf8) are dropped, spaces are folded
	textMax = 200,

	-- rate limits: one answer or skip per requestMs per character (ChaosRateLimit), and at most perMinute rows written a
	-- minute by the whole server (a flood of clients is dropped, not queued)
	requestMs = 2000,
	perMinute = 60,

	-- who is left out: a staff character (group id above this) and a tester bot (Chaos.isTester)
	maxGroupId = 1,

	-- player storage: bit i set = stage i handled for this character's account (a cache: the table is the truth, so the
	-- login only asks the database while the bit is clear and the level is in a stage's window). 7103060 - 7103069
	-- reserved (+1..9 free)
	storage = 7103060
}
