-- In-game guild wars (guildwar.lua, guildwar_core.lua; client game_guildwar, extended opcode ChaosOpcodes.guildWar
-- = 197): every number of the war declarations, the kill rules, the gold stakes and the war board. Loaded with
--     Chaos.guildWarConfig = dofile("data/scripts/chaos/guildwar_config.lua")
-- Plain data, no engine calls (tests/guildwar_test.lua reads it). Lua 5.1 / LuaJIT and Lua 5.3.
-- Overview: server/README.md "Guild wars in game".
return {
	enabled = true,

	-- ------------------------------------------------------------------ who may do what (guild rank levels of the
	-- base server: 3 leader, 2 vice-leader, 1 member)
	rank = 2, -- declare, accept, decline, cancel an offer, surrender: the leader and the vice-leaders
	stakeRank = 3, -- a gold stake (from the guild bank) only by the leader, who alone may withdraw from the guild bank

	-- ------------------------------------------------------------------ the terms of a declaration
	fragLimits = {10, 25, 50, 100, 200}, -- counted kills that win the war (the window offers these)
	durations = {6, 24, 72, 168}, -- hours; the side with more counted kills wins when the time is up (a tie: a draw)
	stake = {
		min = 100000, -- a stake is 0 (none) or at least this much, per side
		max = 500000000,
		feePercent = 10, -- the sink: the winner gets both stakes minus this share (surrender too); a draw refunds both
		-- stakes in full and pays no fee
	},
	offerHours = 24, -- an offer not answered in this time expires (the stake goes back to the declarer's guild bank)
	maxWars = 3, -- wars a guild may have at once (pending offers it made or received + active wars)
	pairCooldownHours = 24, -- after a war between two guilds ended, a new one between them only after this
	minMembers = 3, -- each guild needs this many members
	declareCooldown = 60, -- seconds between two declarations of a guild

	-- ------------------------------------------------------------------ the kills that count (anti-farming)
	-- A player killed by a player of the other side of an active war is a war kill. It counts for the killer's guild
	-- unless one of these rules says no (the kill is still listed in the war log with the reason):
	kills = {
		minVictimLevel = 100, -- a victim below this level never counts
		minLevelRatio = 0.5, -- nor a victim below half of the killer's level
		sameVictimMinutes = 30, -- the same victim counts again only this many minutes after its last counted death
		sameIp = true, -- killer and victim connected from the same IP: never counts
		sameAccount = true, -- killer and victim of the same account (never online at once, but a kill by a summon or
		-- a field can land after a switch): never counts
		realm = true -- season realms: killer and victim must both be of the war's realm
	},
	-- guilds whose owners share an account or whose leaders log in from the same IP cannot fight each other (a war
	-- between them could move a stake from one guild bank to the other)
	sameOwnerBlocked = true,

	-- ------------------------------------------------------------------ rewards
	-- the winner of a war that ended by the frag limit or the time (not a surrender) gets guild XP when the war had at
	-- least minKills counted kills in total; trophy counters warWins / wars (guild_hall trophy room)
	gxp = {win = 150, minKills = 10},
	broadcast = true, -- war started / war ended to the whole server

	-- ------------------------------------------------------------------ the board
	board = {history = 15, active = 20, log = 20, keepDays = 180},
	thinkSeconds = 30, -- how often expired offers and wars past their time are ended

	tables = {wars = "chaos_guildwar", kills = "chaos_guildwar_kills"}
}
