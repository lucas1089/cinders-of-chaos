-- transmog_config.lua: the transmog (appearance) system (transmog.lua, transmog_core.lua).
-- Plain table, loaded with  ChaosTransmogConfig = dofile("data/scripts/chaos/transmog_config.lua")
-- No engine calls here (server/tests/transmog_test.lua reads it with plain Lua).
--
-- A transmog makes an equipped item LOOK like another item of the same kind: only the drawing changes (stats, name,
-- tooltip, weight, everything else stay the item's own). The look is the item's custom attribute "chaos_tmog" (the
-- server id of the look); the engine (server/src-patches/0019-transmog-appearance.patch) sends its client id as item
-- custom attribute 8 and the client (client/base-patches/0030-transmog-appearance.patch) draws it everywhere. It is an
-- item attribute, so it stays through moves, trades, the market escrow, depots and logout.
--
-- Looks are unlocked into an account-wide wardrobe (table chaos_transmog) by carrying or equipping an item once, or,
-- for the appearance sets below, by the set's own source.

return {
	opcode = 212, -- ChaosOpcodes.transmog (client game_transmog)
	tables = {
		looks = "chaos_transmog", -- one row per account and unlocked look (server item id)
		sets = "chaos_transmog_sets" -- one row per account and owned appearance set
	},

	-- gold, taken from the backpack first, then the bank (Player.removeTotalMoney when the server has it)
	fee = {
		apply = 2000, -- base fee to put a look on an item
		perItemLevel = 10, -- + this much per item level (custom attribute "combatPowerLevel"), so endgame gear costs more
		maxApply = 20000, -- the apply fee never goes above this
		remove = 0 -- taking a look off (back to the item's own look)
	},

	-- the equipment slots the window offers (CONST_SLOT_*: 1 head, 4 armor, 5 right hand, 6 left hand, 7 legs, 8 feet)
	slots = {
		{slot = 1, name = "Helmet"},
		{slot = 4, name = "Armor"},
		{slot = 7, name = "Legs"},
		{slot = 8, name = "Boots"},
		{slot = 6, name = "Left hand"},
		{slot = 5, name = "Right hand"}
	},

	-- kinds: an item takes only a look of its own kind. Weapons by weapon type (ItemType:getWeaponType(): 1 sword,
	-- 2 club, 3 axe, 4 shield, 5 distance, 6 wand / rod), armour by slot position bit (ItemType:getSlotPosition():
	-- 1 head, 8 armor, 64 legs, 128 feet). Order = the window's order.
	kinds = {
		{key = "helmet", name = "Helmets", slotBit = 1},
		{key = "armor", name = "Armors", slotBit = 8},
		{key = "legs", name = "Legs", slotBit = 64},
		{key = "boots", name = "Boots", slotBit = 128},
		{key = "sword", name = "Swords", weaponType = 1},
		{key = "axe", name = "Axes", weaponType = 3},
		{key = "club", name = "Clubs", weaponType = 2},
		{key = "distance", name = "Bows and Crossbows", weaponType = 5},
		{key = "wand", name = "Wands and Rods", weaponType = 6},
		{key = "shield", name = "Shields and Spellbooks", weaponType = 4}
	},

	-- the catalogue of looks is every item type up to scanMaxId that has a kind (pickupable, not stackable, not a
	-- container, no fluid, a client id), minus these. Collection progress counts this catalogue.
	scanMaxId = 45000,
	exclude = {
		-- training weapons of the store (shop_config.lua) and test items: no look of value
	},
	excludeRanges = {
		-- {from, to}
	},

	-- when a look is unlocked from an item (sets' looks never are: only their source unlocks them)
	unlock = {
		onCarry = true, -- an item moved into the character's inventory (equipment or carried containers)
		onLogin = true, -- the equipped items at login
		scanOnOpen = true, -- the Transmog window scans the equipment and the carried containers when it opens
		scanDepth = 3 -- container depth of that scan
	},

	-- Appearance sets: looks an account gets only from the set's source (owning an item of a set's look unlocks
	-- nothing). Every look here is existing art of the base server that no monster drops and no NPC sells (checked by
	-- server/tests/transmog_test.lua against data/monster and data/npc when those folders are there).
	--   source "store"        sold in the Chaos store: shop_config.lua offer {kind = "unlock", unlock = "transmog_<key>"}
	--                         (cosmetic only; ChaosTransmog.storeUnlock); account-wide
	--   source "achievement"  owned while the account has the achievement `achievement` (achievements_data.lua)
	--   source "season"       owned when the season pass reports it (ChaosSeasonPass.ownsTransmog(player, key), when
	--                         the season pass has that hook)
	--   source "exclusive"    granted only by staff or a script: ChaosTransmog.grantSet(accountId, key, source)
	--   source "boss"         a rare personal boss drop (exclusives.lua, exclusives_config.lua `bosses`; boss = the
	--                         window's name); granted through ChaosTransmog.grantSet, never sold
	-- how = the window's line of an achievement set (default "Achievement reward")
	sets = {
		{key = "falconer", name = "Falconer's Regalia", source = "store", price = 300,
			desc = "A crested circlet, plate and greaves of the old falconers.",
			looks = {27195, 27200, 27201}},
		{key = "lionguard", name = "Lionguard", source = "store", price = 350,
			desc = "The gilded lion of a sworn guard: helmet, plate, shield and spellbook.",
			looks = {27401, 27402, 27399, 27398}},
		{key = "spiritthorn", name = "Spiritthorn", source = "achievement", achievement = "level_500",
			desc = "Bark and thorn grown into armour. Reach level 500.",
			looks = {27674, 27673}},
		{key = "rimebound", name = "Rimebound", source = "achievement", achievement = "rift_t10",
			desc = "A bow and a shield of runic ice. Close a tier 10 rift.",
			looks = {21696, 21697}},
		{key = "arboreal", name = "Arboreal", source = "season",
			desc = "A living crown and tome. A season reward.",
			looks = {27679, 27680}},
		{key = "arcanomancer", name = "Arcanomancer", source = "exclusive",
			desc = "Regalia and folio of the arcanomancers. Event reward.",
			looks = {27677, 27678}},

		-- the second store set list (shop_config.lua "Appearances"), base looks no monster drops and no NPC sells
		{key = "gravecloak", name = "Gravecloak", source = "store", price = 350,
			desc = "A hooded skull, bone-ribbed plate, legs and boots of a crypt warden.",
			looks = {26708, 26709, 26710, 26711}},
		{key = "soulforged", name = "Soulforged", source = "store", price = 400,
			desc = "Soulshell plate, soulshanks, soulwalkers and the soulbastion shield.",
			looks = {27389, 27387, 27392, 27394}},
		{key = "soulstalker", name = "Soulstalker", source = "store", price = 350,
			desc = "The soulshroud, soulstrider legs and soulstalker boots of a shadow hunter.",
			looks = {27391, 27388, 27393}},
		{key = "mothwing", name = "Mothwing", source = "store", price = 350,
			desc = "A green mothwing helmet, plate, legs and boots.",
			looks = {28382, 28383, 28384, 28385}},
		{key = "cobra", name = "Cobra Regalia", source = "store", price = 300,
			desc = "The cobra hood, a cobra sword, wand and rod.",
			looks = {27213, 27214, 27208, 27209}},
		{key = "lionarms", name = "Lionguard Arms", source = "store", price = 300,
			desc = "The gilded lion's longsword, axe, hammer, longbow, rod and wand (the Lionguard set has the armour).",
			looks = {27400, 27404, 27405, 27395, 27396, 27397}},
		{key = "sanguine", name = "Grand Sanguine", source = "store", price = 350,
			desc = "Blood-red grand sanguine blade, cudgel, hatchet, bow and coil.",
			looks = {27459, 27461, 27463, 27472, 27477}},

		-- achievements (exclusive, never sold)
		{key = "thornmoth", name = "Thornmoth Vestments", source = "achievement", achievement = "prof_wortcunning_100",
			how = "Achievement: Keeper of the Wort (reach Wortcunning level 100)",
			desc = "A moth-winged coif, vestment, breeches and greaves of the herb gatherers.",
			looks = {28390, 28391, 28392, 28393}},
		{key = "haloed", name = "Haloed Arms", source = "achievement", achievement = "wb_heal_top_1",
			how = "Achievement: Lifeline (heal the most of everyone at a world boss kill)",
			desc = "A haloed bolter and bow for those who keep the raid alive.",
			looks = {29564, 29565}},

		-- boss drops (exclusives_config.lua bosses; never sold)
		{key = "hellforged", name = "Hellforged Visage", source = "boss", boss = "Kaelgor the Infernal Warlord",
			desc = "A maliceforged helmet, a demonfang mask and molten plate.",
			looks = {29469, 29472, 8886}},
		{key = "pyrarch", name = "Pyrarch Arms", source = "boss", boss = "Nyxareth the Void Archon",
			desc = "The void-touched pyrarch blade, battleaxe, mace, bow and wand.",
			looks = {29486, 29482, 29484, 29478, 29488}},
		{key = "deathlord", name = "Deathlord Arms", source = "boss", boss = "Varkhul the Ashen Sovereign",
			desc = "The Deathlord's cleaver, mace and blade.",
			looks = {29556, 29557, 29558}},
		{key = "eldritch", name = "Gilded Eldritch Arms", source = "boss", boss = "Ysgrath the Cinderheart",
			desc = "A gilded eldritch claymore, warmace, greataxe, bow and rod.",
			looks = {27655, 27657, 27659, 27662, 27672}}
	},

	staffGroup = 4, -- characters of this group and up may use /transmog (grant / revoke / unlock-all on a character)
	maxLooksSent = 4000 -- the window's wardrobe list is cut at this many looks (it is sent in chunks)
}
