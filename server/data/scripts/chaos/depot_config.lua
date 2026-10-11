-- Depot tabs: the depot chest holds numbered tab containers, each with a fixed room; an account opens some of them.
-- Read by depot.lua (engine glue), depot_core.lua (the rules, through depot.lua), shop_config.lua (the `store`
-- category below), tools/patch_base_depot.py (box ids, names, slots) and server/tests/depot_test.lua.
-- The engine also loads this file as a script because it lives under data/scripts; it only returns a table.
-- See server/README.md "Depot tabs". Lua 5.1 / LuaJIT and Lua 5.3 compatible.
--
-- How many tabs an account may fill: pact_config.lua `limits.depotTabs` (free + Chaos Pact while active + bought
-- extras, at most maxExtra) + one per achievement of `achievementTabs` that any character of the account has, at most
-- the number of boxes. Tabs above that are withdraw-only. Nothing is ever deleted.
return {
	-- the tab containers, in tab order: tab n is boxIds[n] (the base server's numbered depot boxes I..XVII, renamed and
	-- made 100 slots by tools/patch_base_depot.py). Their number is the most tabs an account can have.
	boxIds = {25453, 25454, 25455, 25456, 25457, 25458, 25459, 25460, 25461, 25462, 25463, 25464, 25465, 25466, 25467,
		25468, 25469},
	boxName = "depot tab %d", -- items.xml name of box n (patch_base_depot.py)
	boxSlots = 100, -- items.xml containerSize of the boxes (patch_base_depot.py): at least tabSize
	chestIds = {2594}, -- the depot chest (ITEM_DEPOT); its only own content should be the boxes
	lockerIds = {2589, 2590, 2591, 2592}, -- the lockers (type "depot"); opening one makes sure the boxes exist

	tabSize = 100, -- items per tab; an item inside a bag counts, a container counts as 1 plus its contents

	-- the inbox and the market item in every locker (the depot window's Inbox and Market buttons use them)
	inboxId = 14404,
	marketId = 14405,

	-- ------------------------------------------------------------------ the depot window (client game_depottabs)
	-- opcode 111 client -> server: open {tab} asks to switch the window to a tab (the client then opens that box with the
	-- engine's own use packet); style {tab, name, color} renames and colours a tab. Milliseconds between two requests.
	openMs = 250,
	styleMs = 1000,
	nameMax = 16, -- characters of a tab name (printable ASCII and Latin-1; empty = the default name)
	-- tab colours (key, shown name, colour of the tab's accent); "" = default. No free colours.
	palette = {
		{key = "gold", name = "Gold", color = "#e8b84a"},
		{key = "ember", name = "Ember", color = "#e0752a"},
		{key = "crimson", name = "Crimson", color = "#c0241c"},
		{key = "rose", name = "Rose", color = "#d0627a"},
		{key = "violet", name = "Violet", color = "#9a5ad0"},
		{key = "frost", name = "Frost", color = "#7cc4e8"},
		{key = "azure", name = "Azure", color = "#3a74d0"},
		{key = "jade", name = "Jade", color = "#3fae74"},
		{key = "moss", name = "Moss", color = "#8aa63a"},
		{key = "bone", name = "Bone", color = "#e6dcc0"},
		{key = "ash", name = "Ash Grey", color = "#8c8a86"},
		{key = "bronze", name = "Bronze", color = "#a8703a"}
	},
	table = "chaos_depot_tabs", -- per account and tab: name, colour (sql/chaos_depot_tabs.sql; Chaos.tables.depotTabs)

	limitKey = "depotTabs", -- the pact_config.lua limit (free / Pact / bought)

	-- achievements (achievements_data.lua ids) that each open one more tab for the whole account
	achievementTabs = {"depot_tab_relics", "depot_tab_trophies", "depot_tab_vault"},

	-- the base server's locker Action (a sound) that calls ChaosDepot.onOpenLocker (patch_base_depot.py writes the
	-- hook); when this file is missing depot.lua registers its own locker Action instead
	lockerScript = "data/scripts/customs/actions/sounds/depot.lua",

	-- ------------------------------------------------------------------ store (shop_config.lua inserts this category)
	-- service "pactExtra" (pact.lua): `extra` names the pact_config.lua extra, `amount` how many one purchase adds
	store = {
		name = "Depot Tabs", icon = {item = 25453},
		offers = {
			{kind = "service", service = "pactExtra", extra = "depotTabs", key = "service:pactExtra:depotTabs", icon = 25453,
				cost = 150, name = "Extra Depot Tab",
				description = "Permanent, account-wide: one more depot tab of 100 items. Up to 9."},
			{kind = "service", service = "pactExtra", extra = "depotTabs", amount = 4, key = "service:pactExtra:depotTabs:4",
				icon = 25456, cost = 500, name = "4 Depot Tabs",
				description = "Permanent, account-wide: four more depot tabs of 100 items each."}
		}
	},

	-- ------------------------------------------------------------------ texts
	messages = {
		locked = "Depot tab %d is locked: your account has %d depot tabs. You can still take items out. " ..
			"Buy more tabs in the Store (Depot Tabs).",
		full = "Depot tab %d is full: %d of %d items, this needs %d (a container counts with its contents).",
		chest = "Put items into a depot tab, not loose into the depot chest. Your open tabs: 1 to %d.",
		open = "Depot: %d of %d tabs open, %d items each (bags count with their contents). %s",
		hint = "Buy more tabs in the Store (Depot Tabs).",
		allOpen = "Every tab is open.",
		sorted = "Your depot was sorted into tabs: %d item(s) in open tabs, %d in locked tabs (withdraw-only).",
		leftLoose = " %d item(s) did not fit a tab and stay loose in the depot chest (withdraw-only).",
		descOpen = "%d of %d items.",
		descLocked = "Locked: %d item(s) inside, withdraw-only. Your account has %d depot tabs. Buy more in the Store.",
		descLockedEmpty = "Locked. Your account has %d depot tabs. Buy more in the Store (Depot Tabs).",
		descNamed = "%s. %s", -- a named tab's look text: the name, then one of the three texts above
		openFar = "Stand at your depot locker to switch tabs.",
		openNoTab = "That depot tab does not exist.",
		nameLong = "A tab name has at most %d characters.",
		nameChars = "A tab name may only use letters, digits, spaces and punctuation.",
		badColor = "Pick one of the tab colours."
	}
}
