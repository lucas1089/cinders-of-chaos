-- The stash: the one item storage of a character (the depot boxes retire into it). Every number and text in one place.
-- Read by stash.lua (engine glue), stash_core.lua (the rules, through stash.lua), pact.lua (the window's tab line),
-- depot.lua (the transition flags) and server/tests/stash_test.lua. The engine also loads this file as a script
-- because it lives under data/scripts; it only returns a table. See server/README.md "Stash".
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.
--
-- Scope: per character (player_id), as the stash always was (the depot was per character too); the tab LIMITS are per
-- account (pact_config.lua limits, chaos_account_extras), so every character of an account has the same room.
--
-- Room. An entry is one slot of a tab: a plain stack type (merged: 5,000 gold coins are one entry) or one stored item
-- (a weapon, a rift key, a stack with attributes). General tabs take anything; an affinity tab takes only its class
-- and every deposit of that class goes there first (spilling into the general tabs when it is full or not owned).
return {
	tables = {
		stash = "chaos_stash", -- plain stacks: (player_id, item_id) -> count, tab (sql/chaos.sql)
		items = "chaos_stash_items", -- whole items, one row each, and the journal of every deposit / withdrawal
		block = "chaos_stash_block", -- the "never stash" list (player_id, item_id)
		log = "chaos_stash_log" -- the depot migration and staff actions
	},

	-- player storages (chaos_constants.lua block 7100011 - 7100019)
	storage = {
		seq = 7100011, -- the journal serial: saved with the character, it tells after a crash which side is true
		migrated = 7100012 -- the depot migration version done for this character
	},

	-- ------------------------------------------------------------------ room
	-- Free sizing (2026-10-15, from the repo's loot data; server/README.md "Stash", "Free room"): a character met 20
	-- orb ids, 25 gem types (5 kinds x 5 qualities), 20 profession materials, 27 pack products plus the base monsters'
	-- products (2,945 priced item ids, most of them gear), potions / runes / food, and keeps gear one entry per piece.
	-- The old free room was 2 stash tabs of 48 types + 4 depot tabs of 100 items = 496 slots; the new free room is
	-- 4 general tabs of 100 + the Supplies tab of 100 = 500 entries, and a merged stack is one entry where the depot
	-- counted every stack of 100 as one item.
	tabSize = 100, -- entries per general tab (pact_config.lua limits.stashTabs says how many: 4 free, +2 Pact, +6 bought)
	maxGeneralTabs = 30, -- the most general tabs one account can reach (ids stay below the affinity ids)
	maxStackPerEntry = 2000000000, -- the most of one plain stack type
	generalAchievements = {"depot_tab_relics", "depot_tab_trophies", "depot_tab_vault"}, -- +1 general tab each (account)
	depotTabsCount = true, -- bought depot tabs (pact_config.lua extra depotTabs) count as general stash tabs, one each

	-- affinity tabs, in routing order (the first owned one with room that matches takes the item). Ids are fixed (stored
	-- in chaos_stash.tab / chaos_stash_items.tab). Ownership: free = everybody, pact = while the Chaos Pact runs, extra =
	-- bought once (pact_config.lua extras, store "Storage & Slots"), achievements = any character of the account has one.
	-- A tab that is no longer owned keeps its items, withdraw-only. match: kinds (orbs / gems / keys, the special kinds),
	-- gear (chaos_item_mods.lua kinds: weapon, quiver, shield, helmet, armor, legs, boots, jewel, other), flags (rune,
	-- fluid, ammo, food, key, riftKey, material, product, cosmetic), ids and words (whole words of the item name).
	affinities = {
		{key = "orbs", tab = 101, name = "Orbs", icon = 29856, size = 100, extra = "stashOrbs",
			match = {kinds = {"orbs"}}},
		{key = "gems", tab = 102, name = "Gems", icon = 32005, size = 100, extra = "stashGems",
			match = {kinds = {"gems"}}},
		{key = "keys", tab = 103, name = "Keys", icon = 32072, size = 100, extra = "stashKeys",
			match = {kinds = {"keys"}, flags = {"key", "riftKey"}, words = {"map", "maps"}}},
		{key = "supplies", tab = 104, name = "Supplies", icon = 7618, size = 100, free = true,
			match = {flags = {"rune", "fluid", "ammo", "food"}, words = {"potion", "potions", "flask", "flasks", "elixir", "elixirs"}}},
		{key = "weapons", tab = 105, name = "Weapons", icon = 2400, size = 100, extra = "stashWeapons",
			match = {gear = {"weapon", "quiver"}}},
		{key = "armor", tab = 106, name = "Armor", icon = 2472, size = 100, extra = "stashArmor",
			match = {gear = {"helmet", "armor", "legs", "boots", "shield", "other"}}},
		{key = "jewels", tab = 107, name = "Jewellery", icon = 2171, size = 100, extra = "stashJewels",
			match = {gear = {"jewel"}}},
		{key = "materials", tab = 108, name = "Materials", icon = 5880, size = 100, extra = "stashMaterials",
			match = {flags = {"material"}, words = {"shard", "shards", "ore", "ores", "ingot", "ingots", "dust"}}},
		{key = "products", tab = 109, name = "Creature Products", icon = 36010, size = 100, pact = true,
			extra = "stashProducts", match = {flags = {"product"}}},
		{key = "cosmetics", tab = 110, name = "Collectibles", icon = 5929, size = 100, extra = "stashCosmetics",
			achievements = {"unique_50"},
			match = {flags = {"cosmetic"}, words = {"doll", "figurine", "statuette", "trophy", "plush", "souvenir"}}}
	},

	-- what the flags mean beyond the item type's own (stash.lua reads these when it describes an item)
	foodWords = {"food", "meat", "ham", "fish", "bread", "cheese", "mushroom", "apple", "carrot", "egg", "cookie",
		"pie", "steak", "sausage", "stew", "potato", "roll", "melon", "grapes", "pear", "banana", "cherry"},
	cosmeticIds = {}, -- item ids that always count as collectibles
	materialIds = {}, -- item ids that always count as materials (the profession materials are added at load)

	-- the depot's contents of before the stash took over: withdraw-only, never full
	oldDepot = {tab = 200, name = "Old depot", icon = 2594},

	-- ------------------------------------------------------------------ Stow Everything
	-- every item of the backpack (through its bags) except: equipped items and the backpack itself, containers (their
	-- contents go, the bag stays), items that cannot be moved or picked up, store-bound items, locked items (the item
	-- lock), items on the "never stash" list, and items with an action or unique id (quest items) unless the action id
	-- is listed here
	stowActionIds = {[47401] = true}, -- a Rift Key (rift.lua)
	reportNames = 6, -- item names listed per reason in the report

	-- ------------------------------------------------------------------ access
	-- Owner decision 2026-10-15: free players use the stash in town only, deposit and withdraw alike (a protection zone,
	-- or inside a hideout). Remote deposit (from anywhere, mid-hunt, Stow Everything included) is a paid unlock: bought
	-- once per account (pact_config.lua extra stashRemote, store "Storage & Slots") or lent while the Chaos Pact is
	-- active (it stops when the Pact ends; nothing stored is lost). Withdraw stays protection-zone only for everybody.
	withdrawInHideout = true, -- the hideout counts as town for both
	remoteDeposit = {extra = "stashRemote", pact = true},

	-- ------------------------------------------------------------------ the depot transition (depot.lua, stash.lua)
	depot = {
		migrate = true, -- at login, once per character: every item of the depot boxes and chests moves into the stash
		version = 1, -- raise to run the migration again (only what is still in a depot moves)
		withdrawOnly = true -- the depot boxes and chests take no new items; the inbox and the market work as before
	},
	migrationBatch = 400, -- items moved per login at most (the rest at the next login)

	-- ------------------------------------------------------------------ protocol
	chunkSize = 40, -- entries per addItems packet (well under the 8 KB limit)
	maxDistance = 1, -- Chebyshev distance to a floor item deposited from the map
	rate = {list = 300, withdraw = 250, stow = 1500, block = 100, open = 300, deposit = 100}, -- ms between requests

	messages = {
		cannot = "You cannot put that item into the stash.",
		blocked = "That item is on your never-stash list.",
		tooMany = "Your stash cannot hold that many of this item.",
		full = "Your stash is full (%d entries). Withdraw something, or get another tab.",
		locked = "Your stash is full: the tabs beyond your %d general tabs and the tabs you no longer own are withdraw-only.",
		busy = "The stash is busy. Try again in a moment.",
		taken = "Could not take the item.",
		container = "Empty the container first.",
		stashed = "Stashed %dx %s.",
		stashedTab = "Stashed %dx %s (%s tab).",
		notThere = "You do not have that item in the stash.",
		capacity = "You do not have enough capacity.",
		room = "You do not have enough room.",
		retrieved = "Retrieved %dx %s from your stash.",
		pz = "You can take items out of the stash only in a protection zone.",
		depositPz = "You can put items into the stash only in a protection zone. Remote deposit from anywhere: " ..
			"Store > Storage & Slots, or an active Chaos Pact.",
		corrupt = "That item could not be restored. It stays in the stash; tell the staff.",
		stowNone = "Nothing to stow.",
		stowDone = "Stowed %d item(s) into your stash.",
		stowSkipped = "Kept %d item(s): %s.",
		migrated = "Your depot moved into your stash: %d item(s); %d did not fit and wait in the Old depot tab " ..
			"(withdraw-only). %d stay in the depot.",
		migratedMore = "More depot items move at your next login.",
		depotClosed = "The depot boxes are withdraw-only now: everything goes into the stash (Economy > Supply Stash). " ..
			"You can still take items out."
	},
	-- the skip reasons of Stow Everything, as the report names them
	reasons = {
		container = "containers",
		fixed = "cannot be moved",
		bound = "store-bound",
		locked = "locked",
		quest = "quest items",
		blocked = "never-stash list",
		full = "no room",
		limit = "too many",
		busy = "busy"
	}
}
