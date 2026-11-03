-- Death recap (deathrecap.lua, deathrecap_core.lua, client game_deathrecap, extended opcode ChaosOpcodes.deathRecap =
-- 154). Every number of the system. Returned as a table, loaded as Chaos.deathRecapConfig. See server/README.md
-- "Death recap". Plain data, Lua 5.1 / LuaJIT and Lua 5.3.
return {
	enabled = true,

	-- the rolling log of damage taken per character: hits older than windowMs before the death are not shown, and at
	-- most maxHits hits are kept (the oldest goes first)
	windowMs = 20000,
	maxHits = 60,

	-- attackers listed in one recap (the rest is summed into one "Others" row); elements per attacker are bounded by
	-- the engine's damage types (10)
	maxAttackers = 8,
	-- the last hits before the death shown as a timeline (the killing blow is the last one)
	lastHits = 6,
	-- the killing blow is the last health hit of the log; when the engine's killer is another attacker, or that hit is
	-- longer than this before the death (the lethal hit had no health event: a script's damage with ORIGIN_NONE), the
	-- killer is named without an amount
	killerGapMs = 1500,
	-- names are cut to this many characters
	nameMax = 40,
	-- one recap is cut (attackers dropped from the bottom, then the timeline) until its JSON fits in this many bytes;
	-- the history (5 summaries and the full newest recap) then fits in one extended opcode message (8192)
	maxRecapBytes = 5000,

	-- recaps stored per character (table chaos_death_recaps, the oldest deleted beyond this)
	keep = 5,

	-- a death shown at the next login is sent this long after the login (the client modules are loaded by then)
	loginDelayMs = 1500,
	-- an unseen recap older than this is not opened by itself at login (it stays in the history)
	autoOpenMaxAgeSeconds = 7 * 24 * 3600,

	-- a hit that would kill but is cancelled by a mode (onPrepareDeath returns false: arena, battleground, the Marches,
	-- raid, descent, guild boss, Ascended Omens, trials, the Trial of Ascension) counts as a death there when the
	-- character stood in one of Chaos.registerInstance's instances. The mode is checked this long after the hit.
	defeatCheckMs = 100,
	-- instance keys (Chaos.registerInstance) whose deaths and defeats get no recap on purpose; none by default
	hideModes = {},

	-- what a hidden attacker (a staff character in ghost mode the victim could not see) is called
	hiddenName = "Unseen attacker",
	-- the opcode handler's rate limit
	rateLimitMs = 300,

	-- Death advice (O371; deathadvice_core.lua): 1-3 short tips in the recap, why the character died and what to do.
	-- Rules in this order, at most `max` tips; the client words them (game_deathrecap deathrecaplogic.lua L.tips).
	advice = {
		enabled = true,
		max = 3,
		-- lvl: monsters this many levels above the character dealt at least levelShare % of the damage
		levelGap = 30,
		levelShare = 30,
		-- res: one element dealt at least resShare % of the damage and the character resists it under resLow %.
		-- Elements with a tip, and the gem that resists it (data/lib/chaos_gems_config.lua; the test checks them)
		resShare = 40,
		resLow = 10,
		resElements = {
			fire = {gem = "ruby", group = "jewel"}, ice = {gem = "sapphire", group = "jewel"},
			earth = {gem = "emerald", group = "jewel"}, holy = {gem = "diamond", group = "jewel"},
			death = {gem = "amethyst", group = "armour"}, energy = {gem = "topaz", group = "armour"},
			physical = {gem = "onyx", group = "armour"},
		},
		-- pot: no potion drunk in a fight of at least potMinMs, and the healing received covered under potHealShare % of
		-- the health damage (a stock potion the log cannot see still heals)
		potMinMs = 4000,
		potHealShare = 30,
		-- heal: potions drunk, but in a fight of at least healMinMs the healing covered under healShare % of the damage
		healMinMs = 8000,
		healShare = 25,
		-- pack: this many monsters or more hit the character
		packSize = 5,
		-- the rolling logs of healing received and potions drunk (count bound per character, the window is windowMs)
		maxHeals = 60,
		maxPotions = 30,
	},
}
