-- Trainer DPS meter (trainer_meter.lua, trainer_meter_core.lua; client game_trainerdps; extended opcode
-- ChaosOpcodes.trainerMeter = 147). Returned as a table, loaded as Chaos.trainerMeterConfig. See server/README.md
-- "Trainers as DPS meters (O573)". Plain data, Lua 5.1 / LuaJIT and Lua 5.3.
return {
	enabled = true,

	-- Which monsters are trainers. A name (lower case) is a trainer when it is in `names`, or contains one of `words`
	-- (the rule of monster_tiers.lua: a name with "train" or "dummy" never gets a tier), unless it is in `exclude`.
	names = {},
	words = {"train", "dummy"},
	exclude = {},

	-- The numbers of a session. A session is one player's hits on one trainer: it begins with the first hit, ends when
	-- the player has not hit the trainer for endAfterMs (the result stays until the next session or a reset), and starts
	-- over when the player hits another trainer.
	windowMs = 5000, -- the "DPS now" window
	bucketMs = 250, -- the window is summed in buckets of this size (at most windowMs / bucketMs of them are kept)
	minSpanMs = 1000, -- a window or an average is never divided by less than this (one lone hit is not "infinite" DPS)
	endAfterMs = 10000, -- no hit for this long ends the session

	-- bounded tables: sources kept per session (a source beyond this counts under "Other"), rows and elements sent
	maxRows = 40,
	maxRowsSent = 10,
	maxElementsSent = 10,
	-- members of the viewer's party that hit the same trainer, shown next to the own numbers
	party = true,
	maxPartySent = 8,

	-- A summary every sendMs while a session is active (the think event runs at this interval); a finished or reset
	-- session is sent once. No packet per hit. A client that never sent `watch` gets nothing.
	sendMs = 1000,
	-- rate limit of the client's requests (ChaosRateLimit, ms between two)
	requestMs = 250,

	-- The target profile: the armour and the resistance rank the trainer defends with, so a number measured here means
	-- what it would against a monster (monster_defence.lua, monster_defence_core.lua; the numbers are theirs: the armour
	-- of a monster of level L removes 25% of the median class hit of L for a normal monster, 40% for an elite, 50% for a
	-- boss, and an elite also gets rankResistBonus on its element resistance; see monster_defence_config.lua).
	--   class  "normal", "elite" or "boss"
	--   level  "player": the level of the player that hits (the trainer defends like a normal monster of YOUR level, so the
	--          same character reads the same DPS at any level and two players are comparable by how far they are above or
	--          below the median class), or a number 1 .. maxLevel (one level for every player)
	-- enabled = false: the trainer keeps its monster file's own armour and resistances (how it behaved before O573).
	-- byName: another profile for one trainer (lower case name), same fields, a missing field keeps the default.
	profile = {enabled = true, class = "normal", level = "player"},
	byName = {},
	minLevel = 1,
	maxLevel = 2500
}
