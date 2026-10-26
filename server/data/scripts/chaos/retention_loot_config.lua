-- retention_loot_config.lua: the numbers of O260 (an early power spike, pity, a server drop feed, personal records).
-- Rules: retention_loot_core.lua (tests/retention_loot_test.lua); engine side: retention_loot.lua; hooks in loot.lua.
-- Plain table, loaded with  ChaosRetentionLootConfig = dofile("data/scripts/chaos/retention_loot_config.lua").
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible. server/README.md "Early spike, pity, drop feed and personal records (O260)".

return {
	enabled = true,

	-- 1. the first unique. The character's `kills`-th kill (every kill the character gets the corpse of) adds a leveling
	-- unique of its class to that corpse, once per character: the loot beam, the unique sound and the autoloot of the
	-- loot filter treat it like any unique drop. Not for characters above `maxLevel` and never for tester bots.
	firstUnique = {
		enabled = true,
		kills = 150, -- about 10-15 minutes of hunting
		maxLevel = 60,
		-- player storage 7103010: -1 / 0 unset, 1 .. kills - 1 the kills counted so far, doneValue once the unique was given
		storage = 7103010,
		doneValue = 1000000,
		-- the candidates of each class, names of data/lib/chaos_unique_items.lua (leveling uniques, level 10-40). The one
		-- with the highest level requirement the character already meets is given, else the lowest. A class that is not
		-- listed (a new class, an ascended class of a line below) uses its line's list (`lineOf`), else `default`.
		byClass = {
			Warrior = {"Ashen Pilgrim's Blade", "Hatchet of the First Winter", "Tallow-Bell Mace"},
			Ranger = {"Fenwatch Longbow", "Hoarfen Bow"},
			Mystic = {"Cinder-Wick Wand"},
			Thief = {"Cutpurse's Sliver", "Moonlit Shiv"},
			Necromancer = {"Cinder-Wick Wand"},
			Monk = {"Vigil-Knot Wraps", "Chapel-Iron Knuckles"},
			Templar = {"Tallow-Bell Mace", "Ashen Pilgrim's Blade", "Hatchet of the First Winter"}
		},
		lineOf = {
			Juggernaut = "Warrior", Berserker = "Warrior",
			Deadeye = "Ranger", Beastmaster = "Ranger",
			Elementalist = "Mystic", Illusionist = "Mystic",
			Ninja = "Thief", Samurai = "Thief",
			Lich = "Necromancer", ["Bone Lord"] = "Necromancer",
			Shadowfist = "Monk", ["Iron Sage"] = "Monk",
			Inquisitor = "Templar", Sentinel = "Templar"
		},
		default = {"Ashen Pilgrim's Blade"},
		effect = "CONST_ME_FIREWORK_YELLOW", -- shown over the corpse (a CONST_ME_* name; unknown: 49)
		fallbackEffect = 49,
		message = "Something heavy and old lies in the corpse: %s. It is yours.",
	},

	-- 2. pity. A hidden counter of the kills without a drop of at least `resetRank` (the rank of data/lib/chaos_rarity.lua:
	-- 4 Rare, 5 Legendary, 6 Divine, 7 Unique; Common 1, Uncommon 2, Magic 3). At `threshold` the next gear drop of at
	-- least `minRank` (Magic) is raised one rarity (not above `maxRank`, Legendary) and the counter starts again. Only
	-- normal hunting kills count and are raised: the loot tables of rifts, waystone maps, bosses and pocket bosses stay as
	-- they are. Player storage 7103011 holds the counter.
	pity = {
		enabled = true,
		threshold = 400,
		minRank = 3,
		maxRank = 5,
		resetRank = 4,
		storage = 7103011,
		skipTiers = {boss = true}
	},

	-- 3. the server drop feed. A legendary, divine or unique drop posts one line "<name> (Lv N) found <item>!" in the
	-- channel "Drops" and in the Default tab of everyone online. The item is an item link (itemlink.lua): hovering it
	-- shows the tooltip. The existing local broadcast of loot.lua stays. The same line goes to Discord (discord.lua).
	feed = {
		enabled = true,
		-- the kinds, from the lowest: a legendary gear drop, then divine gear and uniques. The client option "Drop feed"
		-- (off / unique / legendary) keeps the lines of a kind at or above its own rank.
		kinds = {legendary = 1, divine = 2, unique = 2},
		minRankLegendary = 5, -- rarity rank (data/lib/chaos_rarity.lua) of the lowest gear drop that posts
		perCharSeconds = 60, -- at most one line per character in this many seconds
		maxPerMinute = 12, -- and this many lines server-wide per minute; more lines are dropped silently
		maxLevelShown = 99999,
		channelId = 21, -- data/chatchannels/chatchannels.xml (tools/patch_drops_channel.py); must not collide with a stock id
		channelName = "Drops",
		channelScript = "drops.lua",
		-- the Default line: a text message of this type (a MESSAGE_* name looked up in _G)
		defaultType = "MESSAGE_EVENT_ADVANCE",
		fallbackType = 19,
		-- the text of the line; %s name, %d level, %s item link (English; pt-BR in i18n_strings.lua)
		text = "%s (Lv %d) found %s!",
		-- the client option "Drop Feed" (game_dropfeed) before the client has sent one: every kind
		defaultOption = "legendary",
		discord = true
	},

	-- 4. personal records: records_config.lua (`personal`, the boards "drop_rarity" and "drop_value") and records.lua. This
	-- layer submits the best drop of a kill; the message "New record: <what>: <value> (was <old>)" is records.lua's.
	records = {
		enabled = true
	}
}
