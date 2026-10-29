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
		migrated = 7100012, -- the depot migration version done for this character (depot -> stash)
		toDepot = 7100013, -- the stash -> depot migration version done for this character (off, kept for the log)
		legacy = 7100014 -- the grandfather version done for this character (O316: affinity tabs the old rules gave)
	},

	-- ------------------------------------------------------------------ room
	-- O316 (owner 2026-10-29, pt-BR: "No stash, coloque de graca apenas 1 aba de 30 slots e coloque na loja expansao de
	-- slot e aquelas abas proprias para cada tipo de item"): the stash is the only storage and the free room is ONE
	-- general tab of `slots.free` (30) entries. Everything else is sold in the store (Storage & Slots):
	--   * Stash Slot Expansion: +slots.perPack (25) slots on the general tab, up to pact_config.lua limits.stashSlots
	--     (maxExtra 20 packs = 500 slots, 530 in all). The Chaos Pact lends one pack while it runs.
	--   * the affinity tabs below, one per item type, 100 entries each, all bought (no free, Pact or achievement grant).
	-- Extra general tabs are not sold any more: a second general tab only splits the same room, so the expansion simply
	-- grows the one tab (cleaner than two ways to buy the same thing).
	-- Grandfathered (nothing deleted, nothing lost): an old tab bought in the store (Extra Stash Tab, Extra Depot Tab,
	-- 4 Depot Tabs) or earned by an achievement is worth `slots.legacyPacksPerTab` expansions (3 x 25 = 75 slots, the
	-- 150 coins the tab cost at 50 coins an expansion). Characters that hold more than their slots keep every item:
	-- the old general tabs 2..30 and the entries above the size of tab 1 are withdraw-only.
	slots = {
		free = 30, -- entries of the one general tab, everybody
		perPack = 25, -- entries one expansion adds
		legacyPacksPerTab = 3, -- one old tab (bought or earned) = this many expansions, outside the cap of the store
		-- old extras that counted as a general tab each: extra key -> the most the old rules let an account own
		legacyExtras = {stashTabs = 6, depotTabs = 12}
	},
	generalTabs = 1, -- writable general tabs, for everybody
	tabSize = 100, -- entries of an OLD general tab (2..30) as the window shows it; they are withdraw-only now
	maxGeneralTabs = 30, -- the highest old general tab id that may still hold entries (ids stay below the affinity ids)
	maxStackPerEntry = 2000000000, -- the most of one plain stack type
	-- achievements that opened a general tab before O316: each is worth one old tab (slots.legacyPacksPerTab), kept for
	-- accounts that have them (the ids are stored data; achievements_data.lua renames the texts)
	generalAchievements = {"depot_tab_relics", "depot_tab_trophies", "depot_tab_vault"},
	depotTabsCount = true, -- bought depot tabs (pact_config.lua extra depotTabs) count as one old tab each

	-- affinity tabs, in routing order (the first owned one with room that matches takes the item). Ids are fixed (stored
	-- in chaos_stash.tab / chaos_stash_items.tab). Ownership since O316: only an extra bought once (pact_config.lua
	-- extras, store "Storage & Slots"). The old free / Pact / achievement grants are gone; `legacyGrants` below honours
	-- them once for the accounts that used them.
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
		{key = "supplies", tab = 104, name = "Supplies", icon = 7618, size = 100, extra = "stashSupplies",
			match = {flags = {"rune", "fluid", "ammo", "food"}, words = {"potion", "potions", "flask", "flasks", "elixir", "elixirs"}}},
		{key = "weapons", tab = 105, name = "Weapons", icon = 2400, size = 100, extra = "stashWeapons",
			match = {gear = {"weapon", "quiver"}}},
		{key = "armor", tab = 106, name = "Armor", icon = 2472, size = 100, extra = "stashArmor",
			match = {gear = {"helmet", "armor", "legs", "boots", "shield", "other"}}},
		{key = "jewels", tab = 107, name = "Jewellery", icon = 2171, size = 100, extra = "stashJewels",
			match = {gear = {"jewel"}}},
		{key = "materials", tab = 108, name = "Materials", icon = 5880, size = 100, extra = "stashMaterials",
			match = {flags = {"material"}, words = {"shard", "shards", "ore", "ores", "ingot", "ingots", "dust"}}},
		{key = "products", tab = 109, name = "Creature Products", icon = 36010, size = 100,
			extra = "stashProducts", match = {flags = {"product"}}},
		{key = "cosmetics", tab = 110, name = "Collectibles", icon = 5929, size = 100, extra = "stashCosmetics",
			match = {flags = {"cosmetic"}, words = {"doll", "figurine", "statuette", "trophy", "plush", "souvenir"}}}
	},

	-- O316 grandfathering (stash.lua S.grandfather, once per character, storage `legacy`, raise `version` to run it again):
	-- the tabs the old rules gave for free are not given any more, but an account that used one keeps it.
	--   used:   an old free or Pact tab where THIS character holds entries -> the account gets the extra (bought once)
	--   earned: an achievement the account has -> the extra
	legacyGrants = {
		version = 1,
		used = {{tab = "supplies", extra = "stashSupplies"}, {tab = "products", extra = "stashProducts"}},
		earned = {{achievement = "unique_50", extra = "stashCosmetics"}}
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
	-- O316 (owner 2026-10-29: "Retire o depot do jogo"): the depot is retired. The stash is the one storage; the depot
	-- chest of every town is withdraw-only and its contents move into the stash at the first locker opening. A locker no
	-- longer shows a depot window: the engine still opens it (the migration needs the chest in its locker), one event
	-- later the stash window opens and the client closes the locker window (depot.lua Depot.onOpenLocker). The inbox and
	-- the market item stay inside the locker for the engine (mail, house transfers, the market); players reach them
	-- through the stash window (Collect inbox, S.collectInbox) and the top bar Market entry.
	depot = {
		migrate = true, -- at a locker opening, once per character: every item of the depot boxes and chests moves into the stash
		-- raised to 2 by O316: the 2026-10-17 stash -> depot move (toDepot) put items into depot boxes of characters that
		-- had already run version 1, and they come back the same way (only what is still in a depot moves)
		version = 2,
		withdrawOnly = true, -- the depot boxes and chests take no new items; the inbox and the market work as before
		-- O316: a locker opens the stash window. false: the locker only tells the player where the stash is.
		openStash = true
	},
	-- the stash -> depot migration (stash.lua S.migrateToDepot, run by depot.lua when a locker is opened: the engine
	-- saves the depot only then). Every stash entry (a merged stack becomes stacks of `stackSize`, a stored item is made
	-- again with all its attributes) goes into an open depot tab with room, through the stash journal (the same crash
	-- safety as a withdrawal). What does not fit stays in the stash, withdraw-only: nothing is ever lost or deleted.
	-- enabled: also closes the stash to new items (window drop, Stow Everything, scripts): it only gives items back.
	toDepot = {
		enabled = false,
		version = 1, -- raise to run it again (only what is still in the stash moves)
		batch = 40, -- entries moved per locker opening at most (each is one journalled, saved withdrawal)
		stackSize = 100 -- items per depot stack
	},
	migrationBatch = 400, -- items moved per login at most (the rest at the next login)

	storeCategory = "Storage & Slots", -- the store category the window's Buy button opens (pact_config.lua store.storage)

	-- ------------------------------------------------------------------ inbox
	-- The base inbox (mail, house transfers, market and store fallbacks) is reached through the stash window since the
	-- depot lockers no longer open: "Collect inbox" moves what is in the inbox into the stash (into the matching
	-- affinity tab when owned, else the general tab) and what cannot be stashed into the backpack, in a protection
	-- zone or a hideout, at most `batch` items per press.
	inbox = {batch = 60, rateMs = 1500},

	-- ------------------------------------------------------------------ protocol
	chunkSize = 40, -- entries per addItems packet at most
	chunkBytes = 6000, -- and its entries' JSON at most this long: a packet over 8192 bytes is lost to this window (stash.lua sendItems)
	maxDistance = 1, -- Chebyshev distance to a floor item deposited from the map
	rate = {list = 300, withdraw = 250, stow = 1500, block = 100, open = 300, deposit = 100}, -- ms between requests
	-- a second deposit of the same position within this many ms is the same drop sent twice (an old client): ignored
	-- (stash_core.lua K.repeatDeposit)
	repeatDepositMs = 400,

	messages = {
		cannot = "You cannot put that item into the stash.",
		blocked = "That item is on your never-stash list.",
		tooMany = "Your stash cannot hold that many of this item.",
		full = "Your stash is full (%d entries). Withdraw something, or get a Stash Slot Expansion in the Store (Storage & Slots).",
		locked = "Your stash is full: the entries above your %d slots and the tabs you do not own are withdraw-only. Get a Stash Slot Expansion in the Store (Storage & Slots).",
		busy = "The stash is busy. Try again in a moment.",
		moved = "That item moved before it reached the stash. Drag it again.",
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
		toDepot = "Your stash moved into your depot: %d entr(ies). %d stay in the stash because the open depot tabs are full " ..
			"(take them out in a protection zone and put them into your depot).",
		toDepotMore = "More of your stash moves into your depot when you open a depot locker again.",
		depositClosed = "The stash is closed to new items: put them into your depot. It only gives items back.",
		depotClosed = "The depot boxes are withdraw-only now: everything goes into the stash (Economy > Supply Stash). " ..
			"You can still take items out.",
		-- O316: the depot is retired
		inboxEmpty = "Your inbox is empty.",
		inboxPz = "You can collect your inbox only in a protection zone.",
		inboxDone = "Inbox: %d item(s) into your stash, %d into your backpack, %d stay in the inbox (%s).",
		inboxNone = "Nothing from the inbox could be moved.",
		inboxMore = "More inbox items wait: collect again.",
		-- delivery of market purchases (market.lua MK.deliver -> ChaosStash.deliverItem)
		deliveredStash = "in your stash",
		deliveredStashTab = "in your stash (%s tab)",
		grandfathered = "The stash changed: your old tabs are worth extra slots, and the affinity tabs you used are yours to keep."
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
