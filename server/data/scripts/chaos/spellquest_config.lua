-- Settings of the line spell quests (spellquest.lua, rules in spellquest_core.lua, spellquest_tracker_core.lua;
-- server/README.md "Line spell quests"). Returned as a table; spellquest_core.lua puts it in Chaos.spellQuest.
-- Three quests per class line: level 500 an attack, 800 a buff or utility, 1200 an ultimate attack. The base class and
-- both ascended classes of a line share each spell. The spells themselves are not here: only their names (the spell
-- ids and rows belong to the spell registration, not to this file).
-- Storage keys: Chaos.storage.spellQuest (chaos_constants.lua), 10 per quest, 7101040 - 7101069.
return {
	enabled = true,

	-- the NPC (server/data/npc/Archivist Ysolde.xml + scripts/archivist_ysolde.lua), in its stall in the hub
	-- (npc_booths_config.lua) for the main city, as the Keeper of Trials and the Ascendant Oracle
	npc = {
		name = "Archivist Ysolde",
		spawn = true,
		townIds = {2},
		positions = {},
		offsets = {{3, -2}, {-3, -2}, {3, 2}, {-3, 2}, {4, 0}, {-4, 0}, {0, -4}, {0, 4}},
		-- the confirmations (modal windows) only work this close to Ysolde
		range = 6
	},
	modal = {trial = 7160}, -- modal window of the trial question (answered in spellquest.lua)

	-- quest n = index. level: the gate, checked at every step again. kills: counted hunting kills. fragments: needed.
	-- trial: the key in trials_config.lua spellTiers. Quest n needs quest n-1 done on the same line.
	quests = {
		{level = 500, kills = 400, fragments = 20, trial = "s1"},
		{level = 800, kills = 700, fragments = 30, trial = "s2"},
		{level = 1200, kills = 1000, fragments = 40, trial = "s3"}
	},

	-- the hunt. A kill counts when the monster's hunting level (the level the player sees: Chaos.monsterHuntingLevel,
	-- which covers the level-scaled monsters of the late areas, pace.lua) is at least the quest's level, the killer's
	-- level is at least the quest's level, and the monster is a hunt monster. Not counted: summons, monsters of rifts,
	-- trials, dungeons and event spawns (anything ChaosPace does not know and no boss list names), kills within
	-- protectionRadius tiles of a protection zone. A boss kill counts bossKills kills and drops a fragment for sure.
	hunt = {
		bossKills = 25,
		protectionRadius = 4,
		-- a party member who dealt damage counts too, within this many tiles of a killer (as the bounty board)
		partyRange = 30
	},

	-- fragments: a counter in storage and a loot message, never an item. Per counted kill the chance is `chance`
	-- x the multiplier of the monster's tier (capped at 1); a boss kill is a sure fragment; after `pity` counted kills
	-- without a fragment the next one is sure.
	fragments = {
		chance = 0.06,
		tierMultiplier = {normal = 1, magic = 1, rare = 2, legendary = 5},
		pity = 40
	},

	-- the trial (Trials engine, trials_config.lua spellTiers, hook ChaosTrials.spellHook): after a failed run the door
	-- stays closed this long
	trial = {failCooldownSeconds = 60},

	-- the reward: the spell, a message, an effect, gold to the bank (goldPerLevel x the character's level) once per quest
	-- (never again for another line or a repeat)
	reward = {goldPerLevel = 2000},

	-- the third quest's spell is exempt from the 5-spell rotation cap (phase 3 reads this flag; nothing here uses it)
	rotationCapExempt = {false, false, true},

	-- the lines in order (their bit in storage +7 is 2 ^ (index - 1)), base class key of Chaos.classes.ids and the
	-- names of the three spells (quest 1, 2, 3)
	lines = {
		{key = "warrior", class = "warrior", spells = {"Keepfall", "Ironbound Oath", "Judgment of Iron"}},
		{key = "ranger", class = "ranger", spells = {"Moonshard Rain", "Unblinking Gaze", "Dawnbreaker Shot"}},
		{key = "mystic", class = "mystic", spells = {"Prismatic Rupture", "Veil of Whispers", "Eclipse of Ruin"}},
		{key = "thief", class = "thief", spells = {"Eclipse Edge", "Shroud of Knives", "Death Between Heartbeats"}},
		{key = "necromancer", class = "necromancer", spells = {"Soulflay Wave", "Dirge of the Legion", "Funeral of Kings"}},
		{key = "monk", class = "monk", spells = {"Thousand-Echo Palm", "Lotus Stance", "Heaven's Ninth Gate"}},
		{key = "templar", class = "templar", spells = {"Pyre of Absolution", "Mantle of Dawn", "Hammer of Ember Dawn"}}
	}
}
