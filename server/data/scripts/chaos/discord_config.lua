-- Discord announcements (discord.lua, discord_core.lua; the sender is the website's
-- plugins/chaos/discord_worker.php). The game only writes rows to the queue table; the worker posts them to Discord
-- channel webhooks from the environment (CHAOS_DISCORD_WEBHOOK_<CHANNEL>). No HTTP on the game loop, no token in the
-- repository. See server/README.md "Discord announcements". Lua 5.1 / LuaJIT and Lua 5.3 compatible.
ChaosDiscordConfig = {
	enabled = true,
	table = "chaos_discord_queue", -- server/sql/chaos_discord.sql; discord.lua creates it at startup when missing

	-- every event type on / off. The Character Bazaar events (bazaar_list, bazaar_sale) are the worker's (it reads the
	-- bazaar log): switch them off with CHAOS_DISCORD_OFF=bazaar_list,bazaar_sale (website/README.md "Discord").
	events = {
		record = true, -- a beaten all-time record (records.lua announceRecord)
		first = true, -- a realm first of the season (records.lua announceFirst)
		worldboss_spawn = true, -- a world boss event starts (portals open)
		worldboss_kill = true, -- a world boss falls (the records' kill time and the fighters)
		ascended_kill = true, -- an Ascended Omen falls
		cinderheart_kill = true, -- the Cinderheart falls
		level = true, -- a character reaches a level of levelMilestones
		season_start = true,
		season_end = true,
		chronicle = true, -- the Ashen Chronicle: its start, each written chapter, its end (chronicle.lua)
		status_up = true, -- the server started
		status_down = true, -- a clean shutdown outside the daily restart (a crash posts nothing: chaos_health.py)
		status_restart = true -- the daily server save restart
	},

	-- the channel of each event: the worker posts to CHAOS_DISCORD_WEBHOOK_<CHANNEL> (upper case), else to
	-- CHAOS_DISCORD_WEBHOOK_DEFAULT, else the row waits as "nohook"
	channels = {
		record = "records", first = "records",
		worldboss_spawn = "bosses", worldboss_kill = "bosses", ascended_kill = "bosses", cinderheart_kill = "bosses",
		level = "players",
		season_start = "announce", season_end = "announce", chronicle = "announce",
		status_up = "status", status_down = "status", status_restart = "status"
	},

	levelMilestones = {500, 1000},
	staffGroup = 4, -- staff characters never post (levels)

	-- game side rate limit: at most this many rows per event type per minute (more are dropped and counted); the worker
	-- also spaces its posts per webhook and honours Discord's 429 retry_after
	perMinute = {default = 6, level = 10, record = 10, first = 10},

	-- the daily restart: a shutdown within this many minutes after the server save time of
	-- data/globalevents/globalevents.xml ("serversave.lua", time="HH:MM:SS") posts status_restart, else status_down
	restartWindowMinutes = 20,

	-- server_config key of the season id last announced (season start / end once, also over restarts)
	seasonKey = "chaos_discord_season",
	checkSeconds = 60
}

return ChaosDiscordConfig
