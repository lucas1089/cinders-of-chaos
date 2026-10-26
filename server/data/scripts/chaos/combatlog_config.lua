-- DPS meter and combat log (combatlog.lua, combatlog_core.lua, client game_dpsmeter). Returned as a table, loaded as
-- Chaos.combatLogConfig. See server/README.md "DPS meter and combat log". Plain data, Lua 5.1 / LuaJIT and Lua 5.3.
return {
	enabled = true,

	-- a fight starts with the first damage dealt or taken and ends this long after the last one (healing alone neither
	-- starts nor extends a fight)
	idleMs = 6000,
	-- the shortest duration a fight is counted with (one lone hit is not "infinite" damage per second)
	minFightMs = 1000,
	-- finished fights kept per character (newest first), besides the current one and the session total
	keepFights = 10,

	-- bounded tables: rows per tab and segment (damage / healing / taken); a source beyond this goes to "Other"
	maxRows = 40,
	-- rows per tab sent to the client (the totals always count everything)
	maxRowsSent = 25,
	-- keystone note rows (kind k, keystone_labels_config.lua) sent besides those, per tab
	maxNotesSent = 10,
	-- targets remembered per fight for its label (the most damaged one names a fight without a boss)
	maxTargets = 16,
	-- distinct source names cached server-wide (spells, summons, monsters); the cache starts over beyond this
	maxSourceCache = 4000,

	-- hits are summed per character in a small buffer and folded into the fight and the session once per tick
	tickMs = 1000,
	-- an open meter gets a fresh state at most this often, and only when something changed
	pushMs = 1000,

	-- the session follows the Hunt Tracker session: reset with it, and it does not count while the hunt is paused
	followHunt = true,
	-- after a logout the numbers are kept this long (a relog goes on with the same fights and session)
	keepOfflineMinutes = 30,

	-- party view: members' totals only (no breakdown), members of the same party, the same season realm, and only those
	-- that share (the meter's "Share with party" option; this is the value for characters that never set it)
	shareByDefault = true,

	-- EventCallback onTargetCombat index: registers the damage hook on what a player attacks (after hunt at 60)
	targetIndex = 70,

	-- Proc attribution: doTargetCombat / doAreaCombat are wrapped once; a call is labelled by the script file that made
	-- it (the first Lua frame that is not data/global.lua). Damage and healing dealt inside such a call get the label.
	-- kind: p proc, x reflect / thorns, m summon / minion, i item use. helper = true: a library the spells call too
	-- (the spell wins inside a cast). A file not listed here and not a spell is "Other". Calls from data/spells/** are
	-- never labelled: the cast context names the spell.
	wrapCombat = true,
	procLabels = {
		["supports.lua"] = {name = "Spell supports", kind = "p", icon = "supports"},
		["passivetree_keystones.lua"] = {name = "Keystones", kind = "p", icon = "keystone"},
		["trials_effects.lua"] = {name = "Trial nodes", kind = "p", icon = "keystone"},
		["item_mods.lua"] = {name = "Thorns", kind = "x", icon = "thorns"},
		["item_powers.lua"] = {name = "Legendary powers", kind = "p", icon = "power"},
		["rarity_elements.lua"] = {name = "Item elements", kind = "p", icon = "elements"},
		["weapon_styles.lua"] = {name = "Arrow splash", kind = "p", icon = "distance"},
		["berserker_combat.lua"] = {name = "Bloodrage cleave", kind = "p", icon = "axe"},
		["thief_combat.lua"] = {name = "Thief strikes", kind = "p", icon = "sword"},
		["templar_combat.lua"] = {name = "Templar smite", kind = "p", icon = "power"},
		["descent.lua"] = {name = "Descent boons", kind = "p", icon = "power"},
		["beastmaster.lua"] = {name = "Companion", kind = "m", icon = "summon"},
		["pets.lua"] = {name = "Pet", kind = "m", icon = "summon"},
		["necro_lib.lua"] = {name = "Minions", kind = "m", icon = "summon", helper = true},
		["necro_minions.lua"] = {name = "Minions", kind = "m", icon = "summon"},
		["potions.lua"] = {name = "Potions", kind = "i", icon = "potion"},
	},

	-- boss names (lower case) on top of MonsterType:isBoss(), the boss points list and the world bosses
	extraBosses = {},
}
