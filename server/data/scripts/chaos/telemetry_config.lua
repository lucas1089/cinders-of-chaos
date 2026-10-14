-- Balance telemetry for staff (telemetry.lua, telemetry_core.lua; website page.php?plugin=chaos&p=telemetry).
-- Hourly aggregates only. No character id, name or account ever reaches the database: the per-character numbers live
-- in memory between two samples and are dropped when the hour is written. See server/README.md "Balance telemetry".
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.
ChaosTelemetryConfig = {
	enabled = true,

	-- DB tables (server/sql/chaos_telemetry.sql; telemetry.lua creates them at startup when missing)
	tables = {
		hunt = "chaos_telemetry_hunt", -- exp, loot, supplies, kills and hunting time per level band and class
		boss = "chaos_telemetry_boss", -- kills and kill times per boss and party size
		deaths = "chaos_telemetry_deaths", -- deaths per area and killer per level band
		casts = "chaos_telemetry_casts", -- spell casts per class
		economy = "chaos_telemetry_economy", -- gold sinks and faucets per source and level band
		online = "chaos_telemetry_online" -- online samples per level band and class (and the total)
	},

	-- every sampleSeconds: online counts, the hunt tracker's counters of every online character (deltas)
	sampleSeconds = 300,
	-- a sample counts as hunting time when the character gained experience or killed something since the last one
	-- (at most sampleSeconds per sample: the hunt tracker's paused or offline time never counts)

	-- level bands (as the passive tree statistics): {from, to}, to nil = and above
	bands = {{1, 99}, {100, 299}, {300, 499}, {500, 999}, {1000, nil}},
	-- characters of this group and up are left out (staff test characters would skew the numbers)
	staffGroup = 4,

	-- spell casts: count every Nth cast (1 = all). A cast only adds one to a counter in memory.
	castSampleEvery = 1,

	-- bosses fed by the competitive records (records.lua R.submit; only runs the records accept): board -> label
	-- prefix. Map bosses (bossspawns.lua) are counted at their death with the time since the first player hit.
	recordBosses = {wb_time = "World boss", ascended = "Ascended", guildboss = "Guild boss", omen = "Omen guardian"},
	-- party sizes above this are one bucket ("N+")
	maxParty = 10,

	-- deaths: the area is the instance (Chaos.registerInstance label) the character stood in, else the nearest hunting
	-- place of the map markers (data/chaos_poi.lua, kind "hunt") within poiRange squares and poiFloors floors, else the
	-- nearest temple ("near <town>")
	poiRange = 60,
	poiFloors = 3,

	-- retention (telemetry.lua runs it at startup and once a day): hourly rows older than hourlyDays become one daily
	-- row per day; daily rows older than dailyDays are deleted
	hourlyDays = 90,
	dailyDays = 730,

	-- server_config key of the last day rolled up (one rollup per day, also over restarts)
	rollupKey = "chaos_telemetry_rollup"
}

return ChaosTelemetryConfig
