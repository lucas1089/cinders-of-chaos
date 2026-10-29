-- Chaos Pact (monthly subscription) and account storage extras: every limit, price and text in one place.
-- Read by pact.lua (Chaos.pactConfig), pact_core.lua (pure rules), stash.lua / market.lua / autoloot.lua /
-- lootfilter.lua (through ChaosPact.limit), shop_config.lua (the `store` categories below), the website
-- (website/overlay/plugins/chaos/lib.php reads `characters`) and server/tests/pact_test.lua.
-- The engine also loads this file as a script because it lives under data/scripts; it only returns a table.
-- See server/README.md "Chaos Pact and account storage". Lua 5.1 / LuaJIT and Lua 5.3 compatible.
--
-- Every perk is comfort only: room, slots, a title, a Marks drip for cosmetics and a little experience. Nothing here
-- changes combat.
-- A limit is  free + (pact while the Pact is active) + bought extras (at most maxExtra), per account.

-- the Chaos Pact for 30 days costs this many Chaos Coins (O317: 300 -> 299; the Pacto Completo lists it as a part)
local PACT_PRICE = 299
-- what the Pacto Completo gives, both lists (the store shows about three lines of an offer's text)
local COMPLETE_TEXT = "Chaos Pact: +10% XP, stamina x1.5, remote stash, +25 slots, Auto Seller, 5 Marks a day. " ..
	"Premium: x1.5 XP on green stamina, premium outfits, mounts, houses, offline training."

return {
	-- DB tables (server/sql/chaos_pact.sql; pact.lua creates them at startup too)
	tables = {
		pact = "chaos_pact", -- one row per account: Pact end time, run start, last daily claim
		extras = "chaos_account_extras", -- one-time purchases per account: (account_id, extra_key) -> amount
		builds = "chaos_build_slots", -- saved passive tree builds per account: (account_id, slot) -> name, code
		log = "chaos_pact_log", -- purchases, claims, staff grants
		marks = "chaos_pact_marks", -- Pact Marks per account: balance, earned, spent (O317)
		xp = "chaos_pact_xp" -- experience the Pact's +10% added, per character and server month (O317)
	},

	-- ------------------------------------------------------------------ the Pact
	pact = {
		name = "Chaos Pact",
		days = 30, -- one purchase; purchases stack on the time left
		maxStackDays = 365, -- a purchase that would end later than this many days from now is refused
		premiumDays = 0, -- premium days added (0 by the owner's decision: premium gives x1.5 experience on green stamina,
		--                   which is power, not comfort) with each purchase (stock premium content: premium outfits and
		--                   mounts, houses, boats, premium areas, offline training, VIP list 100, premium autoloot).
		--                   0 = the Pact does not touch premium. Premium itself stays on sale in the store.
		-- Pact Marks (O317, owner 2026-10-29): claimable once per server day while the Pact is active (no back pay), in
		-- the game_pact window. They replace the 5 Chaos Coins a day of before. Marks buy the cosmetics of `marks.shelf`
		-- below and nothing else: never coins, services, boosts or supplies.
		dailyMarks = 5,
		-- expiry warning: at login (a chat line and a toast) from this many days before the end, then again from the
		-- last day; once more while the character is online when the level changes (pact.lua)
		warnDays = {3, 1},
		-- name plate frame while the Pact is active (nameplate_core.lua frames, client plate_pactbound.png): below a
		-- frame the player bought or wears as staff, above the default one
		frame = "pactbound",
		title = {key = "pact", text = "Pactbound", color = "#c4553a"} -- name plate title while active (titles.lua)
	},

	-- ------------------------------------------------------------------ VIP perks (pact_perks.lua, pact_perks_core.lua)
	-- The Pact is the server's VIP. Owner approval 2026-10-13 ("Pode fazer todas as mudanças recomendadas"): comfort
	-- and cosmetics; owner 2026-10-13: "Vip ganha +10% de exp e restaura stamina mais rápido. Retire o loot bag e
	-- autoloot." While the Pact is active:
	--   expBonus      +10% experience from monsters (an onGainExperience callback in pact_perks.lua, index `expIndex`,
	--                 multiplied like every Chaos bonus and counted against the experience cap at index 85, xpcap.lua);
	--                 not for season characters (no account-wide boost reaches them, as World Experience)
	--   staminaRegen  stamina comes back this many times faster: offline (the base login script regeneratestamina.lua)
	--                 and on the stamina trainer tile (trainer_tile_stamina.lua); both patched by
	--                 tools/patch_base_events.py to ask ChaosPactPerks
	--   loadoutSlots  +N loadout slots (loadouts_config.lua pactSlots; per character, read through ChaosPact.active;
	--                 owner 2026-10-13: "Pode manter")
	--   (stash slot expansions: limits.stashSlots.pact below; listings, builds and loot rules likewise)
	--   unlocks       the store unlocks that work for the character while it lasts (shop_services.lua S.unlocks keys):
	--                 the storage is set to 2 (a bought unlock is 1 and stays); back to unset when the Pact ends
	--   retired       unlocks the Pact lent before and no longer does: a lent one (2) is taken back at the next apply,
	--                 a bought one (1) stays. Rarity Autoloot left the Pact on 2026-10-13 (still sold in the store)
	--   chatColor     a cosmetic (cosmetics_config.lua, source "pact") granted while active, taken back when it ends
	--   monthly       one exclusive cosmetic per month (YYYYMM -> cosmetic key, source "pact"), granted to the accounts
	--                 with an active Pact during that month and kept for good
	-- The Loot Bag is a store item of its own (pouches_config.lua), never a Pact perk.
	-- No login queue exists on this server (the engine has none), so there is no priority login perk.
	perks = {
		expBonus = 0.10,
		expIndex = 7, -- after the store's World Experience (5) and the blessing (6), before the cap (85)
		staminaRegen = 1.5,
		loadoutSlots = 1,
		unlocks = {"autoSeller"},
		retired = {"rarityAutoloot"},
		pactStorageValue = 2,
		chatColor = "chat_pactbound",
		monthly = {
			[202611] = "kill_pact_ember", [202612] = "loot_pact_frost", [202701] = "kill_pact_venom",
			[202702] = "loot_pact_rose", [202703] = "kill_pact_frost", [202704] = "loot_pact_gold"
		}
	},

	-- ------------------------------------------------------------------ Pact Marks (O317)
	-- A second currency, per account, for cosmetics only. The shelf is a small list in the game_pact window: a Mark is
	-- worth about a coin of the same cosmetic in the store (marks >= price in coins, pact_test.lua checks it against
	-- cosmetics_config.lua), so five Marks a day is about a loot label every month. Only these keys can be bought:
	-- pact.lua refuses anything else, and no store offer, service, boost or supply takes Marks.
	marks = {
		shelf = {
			{key = "loot_ember", marks = 150}, {key = "loot_verdant", marks = 150}, {key = "loot_azure", marks = 150},
			{key = "chat_cinder", marks = 200}, {key = "chat_frost", marks = 200}, {key = "kill_soulspark", marks = 200}
		},
		-- One more slot on the shelf, chosen by the server month from this list (pact_core.lua monthlyItem): the entry at
		-- ((year * 12 + month - 1) mod #list) + 1, so with 12 entries it is the month number and every month of the year has its
		-- own, then the year starts again. Server time, deterministic, nothing stored. Same rules as the fixed shelf: store
		-- cosmetics (no spell effects), a Mark is 1 to 1.5 coins (store_model.lua, pact_test.lua), none of them on the fixed shelf.
		-- They are sold for coins in the store as well; the Marks are a second way to get one, for the month it is on the shelf.
		monthly = {
			{key = "foot_ember", marks = 200},    -- January
			{key = "emote_roar", marks = 200},    -- February
			{key = "lvl_grove", marks = 150},     -- March
			{key = "rare_seal", marks = 150},     -- April
			{key = "kill_shatter", marks = 200},  -- May
			{key = "chat_verdant", marks = 200},  -- June
			{key = "loot_royal", marks = 150},    -- July
			{key = "foot_shadow", marks = 200},   -- August
			{key = "lvl_dawn", marks = 200},      -- September
			{key = "rare_crimson", marks = 200},  -- October
			{key = "emote_salute", marks = 200},  -- November
			{key = "kill_bloodbloom", marks = 200} -- December
		},
		maxBalance = 100000 -- a sanity cap for the column, far above what a Pact earns in years
	},

	-- ------------------------------------------------------------------ limits
	-- key = {label, free, pact (bonus while active), maxExtra (one-time extras that can be bought), unit}
	limits = {
		-- O316 (owner 2026-10-29): the stash has ONE general tab of stash_config.lua slots.free (30) entries for everybody.
		-- Each unit here is one Stash Slot Expansion of slots.perPack (25) entries: bought in the store (free 0, at most
		-- maxExtra 20 = 500 more entries) and one lent while the Chaos Pact runs (the Pact's modest bonus, +25). The old
		-- extras stashTabs / depotTabs (retired, no longer sold) are read by stash.lua and count at slots.legacyPacksPerTab
		-- expansions each, outside this cap.
		stashSlots = {label = "Stash slot expansions (+25 entries)", free = 0, pact = 1, maxExtra = 20},
		marketListings = {label = "Market listings (character)", free = 20, pact = 10, maxExtra = 0},
		marketAccount = {label = "Market listings (account)", free = 40, pact = 20, maxExtra = 0},
		buildSlots = {label = "Saved builds", free = 2, pact = 3, maxExtra = 6},
		-- the autoloot list (Hunt > Auto Loot). premiumCounts: premium alone also gives the bonus, as the base
		-- server's own autoloot callback (data/scripts/creaturescripts/autoloot.lua, 10 free / 20 premium) does.
		-- Keep free + pact at most 20, or raise that callback's premium limit too.
		lootRules = {label = "Loot rules (autoloot list)", free = 10, pact = 10, maxExtra = 0, premiumCounts = true},
		charSlots = {label = "Character slots", free = 5, pact = 0, maxExtra = 10},
		-- remote stash deposit (owner 2026-10-15; stash_config.lua remoteDeposit): deposit from anywhere while > 0;
		-- the Pact lends it, the store sells it once (withdraw stays in town for everybody)
		stashRemote = {label = "Remote stash deposit", free = 0, pact = 1, maxExtra = 1}
	},
	order = {"stashSlots", "stashRemote", "marketListings", "marketAccount", "buildSlots", "lootRules", "charSlots"},

	-- stash tabs: stash_config.lua (tab size, the affinity tabs and which extra, Pact or achievement owns each)

	-- one-time extras: extra key -> what a purchase adds and the most an account can own (maxExtra of the limit
	-- above, or 1 for an affinity tab; stash_config.lua affinities name the extra of each tab)
	extras = {
		stashSlots = {limit = "stashSlots", name = "Stash Slot Expansion"},
		-- retired by O316, never sold again: they stay here so that an account's rows keep a name. stash.lua turns each
		-- one into slots.legacyPacksPerTab expansions (stash_config.lua slots.legacyExtras says how many count)
		stashTabs = {retired = true, max = 0, name = "Extra Stash Tab (retired)"},
		depotTabs = {retired = true, max = 0, name = "Extra Depot Tab (retired)"},
		stashSupplies = {max = 1, name = "Supplies Stash Tab"},
		stashOrbs = {max = 1, name = "Orbs Stash Tab"},
		stashGems = {max = 1, name = "Gems Stash Tab"},
		stashKeys = {max = 1, name = "Keys Stash Tab"},
		stashWeapons = {max = 1, name = "Weapons Stash Tab"},
		stashArmor = {max = 1, name = "Armor Stash Tab"},
		stashJewels = {max = 1, name = "Jewellery Stash Tab"},
		stashMaterials = {max = 1, name = "Materials Stash Tab"},
		stashProducts = {max = 1, name = "Creature Products Stash Tab"},
		stashCosmetics = {max = 1, name = "Collectibles Stash Tab"},
		stashRemote = {limit = "stashRemote", name = "Remote Stash Deposit"}, -- stash_config.lua remoteDeposit
		charSlots = {limit = "charSlots", name = "Character Slot"},
		buildSlots = {limit = "buildSlots", name = "Build Slot"}
	},
	-- extras a staff grant may also set (not sold): the character slots given to accounts that already had more
	-- characters than the free count when this feature was installed (pact.lua grants them once at startup)
	legacyCharSlots = "charSlotsLegacy",
	legacyVersion = 1, -- server_config row chaos_pact_legacy: raise to run the grant again

	-- staff never meet the character slot limit (accounts.type, as class_unlocks_core.lua bypass.minAccountType)
	staffAccountType = 5,

	-- the website (lib.php reads this block): characters per account = free + charSlots + charSlotsLegacy
	characters = {free = 5, maxExtra = 10},

	-- ------------------------------------------------------------------ store (shop_config.lua inserts these)
	-- offers of kind "service": service "pact" (the subscription) and "pactExtra" (extra = an `extras` key), with
	-- stable keys (shop_core.lua offerKey). pact.lua registers both handlers in ChaosShopServices.services. Bundle parts
	-- {kind = "pact", days = n} of shop_config.lua go through ChaosPact.grantDays (premium days in proportion when premiumDays > 0).
	store = {
		pact = {
			name = "Chaos Pact", icon = {item = 16101},
			offers = {
				{kind = "service", service = "pact", key = "service:pact:30", icon = 16101, cost = PACT_PRICE, name = "Chaos Pact (30 days)",
					description = "30 days: +10% XP, stamina x1.5, remote stash, +25 slots, Auto Seller, cosmetics."}
			}
		},
		-- Pacto Completo (O317, owner 2026-10-29): the Pact and Premium together, the best way to buy both. A bundle of a
		-- {kind = "pact"} part (ChaosPact.grantDays) and the premium offer of the same days (the string key resolves to
		-- shop_config.lua's own offer, so its price follows). The Pact's own price per day is the part's list price; the
		-- discount shown is against buying both apart. Giftable (follow-up 2026-10-29): the Pact days and the premium days go to
		-- the receiver's account, `giftable = true` on the pact part; the cap is checked for the receiver first. Prices: docs/PRICES.md "Pacto Completo (O317)".
		complete = {
			name = "Pacto Completo", icon = {item = 16101},
			offers = {
				{kind = "bundle", key = "complete:30", icon = 16101, cost = 499, pactNote = false,
					name = "Pacto Completo (30 days)", description = COMPLETE_TEXT,
					parts = {{kind = "pact", days = 30, cost = PACT_PRICE, source = "complete", required = true, giftable = true}, "premium:30"}},
				{kind = "bundle", key = "complete:90", icon = 16101, cost = 1350, pactNote = false,
					name = "Pacto Completo (90 days)", description = COMPLETE_TEXT,
					parts = {{kind = "pact", days = 90, cost = PACT_PRICE * 3, source = "complete", required = true, giftable = true}, "premium:90"}},
				{kind = "bundle", key = "complete:180", icon = 16101, cost = 2500, pactNote = false,
					name = "Pacto Completo (180 days)", description = COMPLETE_TEXT,
					parts = {{kind = "pact", days = 180, cost = PACT_PRICE * 6, source = "complete", required = true, giftable = true}, "premium:180"}}
			}
		},
		storage = {
			name = "Storage & Slots", icon = {item = 2365},
			offers = {
				{kind = "service", service = "pactExtra", extra = "stashSlots", key = "service:pactExtra:stashSlots", icon = 2365, cost = 50, name = "Stash Slot Expansion",
					description = "Permanent, account-wide: +25 slots on your stash tab. Up to 20 (500 more slots)."},
				{kind = "service", service = "pactExtra", extra = "stashSlots", amount = 4, key = "service:pactExtra:stashSlots:4", icon = 2365, cost = 180, name = "4 Stash Slot Expansions",
					description = "Permanent, account-wide: +100 slots on your stash tab, 10% off."},
				{kind = "service", service = "pactExtra", extra = "stashSupplies", key = "service:pactExtra:stashSupplies", icon = 7618, cost = 150, name = "Supplies Stash Tab",
					description = "Permanent, account-wide: a stash tab for potions, runes, ammo and food."},
				{kind = "service", service = "pactExtra", extra = "stashOrbs", key = "service:pactExtra:stashOrbs", icon = 29856, cost = 200, name = "Orbs Stash Tab",
					description = "Permanent, account-wide: an affinity stash tab for orbs, whetstones, rune shards."},
				{kind = "service", service = "pactExtra", extra = "stashGems", key = "service:pactExtra:stashGems", icon = 32005, cost = 200, name = "Gems Stash Tab",
					description = "Permanent, account-wide: an affinity stash tab for every gem you deposit."},
				{kind = "service", service = "pactExtra", extra = "stashKeys", key = "service:pactExtra:stashKeys", icon = 32072, cost = 150, name = "Keys Stash Tab",
					description = "Permanent, account-wide: an affinity stash tab for Rift Keys, omens, keys, maps."},
				-- the affinity tabs of 2026-10-15: PLACEHOLDER prices (payments are off in the beta; docs/OWNER_TODO.md)
				{kind = "service", service = "pactExtra", extra = "stashWeapons", key = "service:pactExtra:stashWeapons", icon = 2400, cost = 150, name = "Weapons Stash Tab",
					description = "Permanent, account-wide: an affinity stash tab for weapons and quivers."},
				{kind = "service", service = "pactExtra", extra = "stashArmor", key = "service:pactExtra:stashArmor", icon = 2472, cost = 150, name = "Armor Stash Tab",
					description = "Permanent, account-wide: an affinity stash tab for armour pieces and shields."},
				{kind = "service", service = "pactExtra", extra = "stashJewels", key = "service:pactExtra:stashJewels", icon = 2171, cost = 150, name = "Jewellery Stash Tab",
					description = "Permanent, account-wide: an affinity stash tab for rings and amulets."},
				{kind = "service", service = "pactExtra", extra = "stashMaterials", key = "service:pactExtra:stashMaterials", icon = 5880, cost = 150, name = "Materials Stash Tab",
					description = "Permanent, account-wide: an affinity stash tab for ores, herbs and shards."},
				{kind = "service", service = "pactExtra", extra = "stashProducts", key = "service:pactExtra:stashProducts", icon = 36010, cost = 150, name = "Creature Products Stash Tab",
					description = "Permanent, account-wide: a stash tab for creature products."},
				{kind = "service", service = "pactExtra", extra = "stashCosmetics", key = "service:pactExtra:stashCosmetics", icon = 5929, cost = 100, name = "Collectibles Stash Tab",
					description = "Permanent, account-wide: a stash tab for collectibles."},
				-- remote stash deposit (owner 2026-10-15; stash_config.lua remoteDeposit): 400 coins since O317 (docs/PRICES.md "Pacto Completo (O317)")
				{kind = "service", service = "pactExtra", extra = "stashRemote", key = "service:pactExtra:stashRemote", icon = 2365, cost = 400, name = "Remote Stash Deposit",
					description = "Permanent, account-wide: deposit into the stash from anywhere. Pact: included."},
				{kind = "service", service = "pactExtra", extra = "charSlots", key = "service:pactExtra:charSlots", icon = 1949, cost = 250, name = "Character Slot",
					description = "Permanent: one more character on your account, created on the website. Up to 10."},
				{kind = "service", service = "pactExtra", extra = "buildSlots", key = "service:pactExtra:buildSlots", icon = 18559, cost = 100, name = "Build Slot",
					description = "Permanent, account-wide: one more saved passive tree build. Up to 6."}
			}
		}
	},

	-- ------------------------------------------------------------------ misc
	buildNameMax = 24, -- characters of a saved build's name
	rate = {open = 400, claim = 1000, build = 600}, -- ms between two requests of the kind (ChaosRateLimit)

	messages = {
		pactCap = "Your Chaos Pact already runs for more than %d days. Buy more later.",
		extraMax = "Your account already has the most of %s it can have (%d).",
		extraOver = "Your account has %d of at most %d %s; this offer adds %d. Buy fewer at once.",
		claimed = "You claimed today's %d Pact Marks of your Chaos Pact.",
		alreadyClaimed = "You already claimed today's Pact Marks. Come back tomorrow.",
		marksNoItem = "That cosmetic is not on the Marks shelf.",
		marksOwned = "Your account owns that cosmetic already.",
		marksShort = "You need %d Pact Marks for that and have %d.",
		marksBought = "You bought %s with %d Pact Marks. See Character > Cosmetics.",
		noPact = "You have no active Chaos Pact.",
		buildFull = "All your build slots are used (%d). Delete one, or get another slot.",
		buildLocked = "That build slot is read-only now (your account has %d build slots). Load or delete it.",
		charBlocked = "This account has %d character slots and this is character number %d. Buy a Character Slot " ..
			"in the store with another character, or ask the staff."
	}
}
