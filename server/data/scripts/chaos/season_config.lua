-- Seasons (season.lua, season_core.lua, client game_season). Every number and rule of the season system.
-- Returned as a table, loaded as Chaos.seasonConfig (and by server/tests/season_test.lua). Data only, no engine calls.
-- Server local time. See server/README.md "Seasons".
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.
return {
	-- DB tables (server/sql/chaos_season.sql)
	tables = {
		players = "chaos_season_players", -- one row per character that joined a season (the season flag)
		progress = "chaos_season_progress", -- season-long stats per character (bounty contracts, best rift tier, ...)
		rewards = "chaos_season_rewards", -- reward track milestones reached, per account (kept forever)
		log = "chaos_season_log", -- join / migrate / milestone / admin events
		requests = "chaos_season_requests" -- a join chosen at character creation (website), done at the first login
	},
	-- server_config rows written by /season start|end: chaos_season_<id>_start, chaos_season_<id>_end (unix time).
	-- They win over the dates below, so a season can be started or ended early without editing this file.
	configPrefix = "chaos_season_",

	-- ------------------------------------------------------------------ seasons
	-- start / finish: YYYYMMDD (at `hour`, server local time) or a unix time. A season runs from start to finish.
	-- Only one season can run at a time; ids never change once a season has started (the DB rows use them).
	-- tag: shown in the look text ("[S1]") and in the client. modifier (optional): shown in the window;
	-- expMult (optional) multiplies the monster experience of that season's characters (needs patch_base_events.py,
	-- like every Chaos experience bonus). nil = no modifier.
	seasons = {
		{
			id = 1,
			name = "Season of Ash",
			tag = "[S1]",
			start = 20261120, -- the launch, Fri 20 Nov 2026 15:00 (owner 2026-10-29)
			finish = 20270219, -- 13 weeks; Season 2 starts the next day, 20 Feb 2027 15:00 (planned)
			hour = 15,
			modifier = {
				name = "Ashfall",
				description = "Season characters gain 10% more experience from monsters.",
				expMult = 1.10
			}
		}
	},

	-- ------------------------------------------------------------------ joining
	-- A character joins with "!season join" (or the window's Join button) and then confirms within confirmSeconds.
	-- Characters are created on the website (the base server has no account manager and no in-game creation),
	-- so the opt-in is a command on a fresh character.
	join = {
		maxLevel = 7, -- only characters of this level or lower (a fresh character reaches level 8 within minutes)
		confirmSeconds = 60,
		-- what joining does to the character (it must start from nothing, so nothing a standard character handed
		-- over before the join comes along):
		wipeInventory = true, -- every carried item is destroyed (equipment and backpack)
		wipeBank = true, -- the bank balance becomes 0
		requireEmptyDepot = true, -- refused while any depot, the inbox or the store inbox holds an item
		regiveKit = true -- the new-player kit (newplayer.lua) is given again when the character had received it
	},

	-- ------------------------------------------------------------------ isolation
	-- Season characters and standard characters do not exchange anything while the season runs:
	-- trade window (and house trade), mail (parcels and letters), items on the ground and in corpses, house
	-- tiles, the Chaos bank transfer, the NPC bank transfer, the market, parties; the store: `store` below.
	-- See README "Seasons".
	isolation = {
		-- custom item attribute that marks an item on the ground / a corpse with the realm (0 = standard, else the
		-- season id) of the player who dropped it / killed the monster / died
		tagKey = "chaos_realm",
		mailboxIds = {2593, 3981, 26055, 26056, 26057, 26058, 29830, 29831}, -- items.xml type="mailbox"
		parcelId = 2595, letterId = 2597, labelId = 2599, -- ITEM_PARCEL / ITEM_LETTER / ITEM_LABEL of the engine
		-- party rule: season characters can only be in a party with characters of the same season
		party = "same-realm",
		exemptGroup = 4, -- gamemasters and up are never blocked (they can hand out test items)
		messages = {
			trade = "Season characters can only trade with characters of the same season.",
			move = "You cannot take or hand over items between season and standard characters.",
			mail = "Season characters can only send mail to characters of the same season.",
			house = "This house belongs to a character of another realm (season / standard).",
			party = "Season characters can only be in a party with characters of the same season.",
			bank = "Season characters can only transfer gold to characters of the same season."
		}
	},

	-- ------------------------------------------------------------------ store coins (account-wide)
	-- Chaos Coins belong to the account, so a season character could spend coins its account bought or earned with
	-- standard characters. The rule: cosmetics and account-wide entitlements are fine on both sides; nothing that
	-- gives a season character items, gold, experience, power or a head start comes through the store. Refused
	-- offers go to nobody: the account buys them with a standard character. ChaosSeason.storeRefusal
	-- (season_core.lua) decides from these lists (anything not listed is refused, so a new offer kind needs a
	-- decision here); shop.lua asks ChaosSeason.storeProblem for the buyer and for the receiver of a gift.
	store = {
		-- offer kinds a season character may get (shop_config.lua kinds; "pact" = the Chaos Pact days of a bundle)
		-- "exclusive" = a Founder Pack piece (exclusives_config.lua source founder): a look for the account
		kinds = {wings = true, aura = true, shader = true, outfit = true, addons = true, mount = true, frame = true,
			premium = true, pact = true, exclusive = true},
		-- kind "service": by service. The Chaos Pact and its extras are account comfort (room, slots, coins);
		-- stamina, blessings, the skull remover, resets, the vocation token, world buffs and pouches are refused
		services = {nameToken = true, sexChange = true, pact = true, pactExtra = true},
		-- kind "unlock": by unlock key, or by key prefix. Classes are account-wide anyway; portal styles and
		-- transmog sets are looks; the season pass and its packs are account-wide (their item rewards: passItems).
		-- Pets, the Auto Seller and Rarity Autoloot are refused (gameplay unlocks of the character)
		unlocks = {unlockNecromancer = true, unlockMonk = true, unlockTemplar = true},
		unlockPrefixes = {"portal_", "transmog_", "seasonPass", "seasonPack", "cosmetic_", -- cosmetic_: cosmetics.lua
			"hideout_"}, -- hideout_: hideout decorations (hideout_store.lua), looks only
		message = "%s is not for season characters: they get only cosmetics and account services from the store. " ..
			"Buy it with a standard character.",
		giftMessage = "%s is a season character: only cosmetics and account services can be given to it."
	},
	-- season pass item rewards (gold and potions) come from the account's shared pass (pass XP of every character,
	-- the premium pass, tier skips): while the season runs only standard characters claim them. They stay claimable
	-- (also by the season character after the season ends, within the pass's grace days).
	passItems = {
		seasonCharacters = false,
		message = "Season characters cannot claim the pass's items while the season runs: claim them with a standard " ..
			"character, or after the season."
	},
	-- the season markets (market.lua) trade for gold only: Chaos Coins are account-wide
	market = {
		coins = false,
		message = "Season markets trade for gold only: Chaos Coins belong to the whole account."
	},

	-- ------------------------------------------------------------------ reward track
	-- Milestones reached by any season character of an account unlock the reward for the whole account, forever:
	-- every character of the account (season or standard, existing or created later) gets it at login.
	-- stat: "level" (the character's level), or a leaderboard board key counted for the season by season.lua
	-- through ChaosLeaderboard.record: "bounty" (contracts completed, sum), "rift" (highest rift tier completed),
	-- "worldboss" (world bosses defeated with a reward share), "goblin" (treasure goblins slain).
	-- requires: a global that must exist for the milestone to be listed (rifts are optional).
	-- reward kinds (nothing new is drawn; every look type and mount exists in the base server's XML):
	--   {kind = "title", title = "..."}                          look text + leaderboards (account-wide)
	--   {kind = "outfit", male = lookType, female = lookType, name = "..."}   the outfit without addons
	--   {kind = "addon", male = lookType, female = lookType, addons = 1|2|3, name = "..."}  outfit + addons
	--   {kind = "mount", id = mountId, name = "..."}             data/XML/mounts.xml id
	-- how a leaderboard record (ChaosLeaderboard.record(board, who, value)) adds to a season stat:
	-- "add" sums the value, "max" keeps the best value, "count" counts the calls (one per kill / run)
	stats = {bounty = "add", rift = "max", worldboss = "count", goblin = "add"},
	track = {
		{key = "level100", stat = "level", value = 100, name = "Reach level 100",
			reward = {kind = "title", title = "Ashborn"}},
		{key = "level300", stat = "level", value = 300, name = "Reach level 300",
			reward = {kind = "outfit", male = 667, female = 666, name = "Death Herald outfit"}},
		{key = "level600", stat = "level", value = 600, name = "Reach level 600",
			reward = {kind = "addon", male = 667, female = 666, addons = 3, name = "Death Herald addons"}},
		{key = "level1000", stat = "level", value = 1000, name = "Reach level 1000",
			reward = {kind = "mount", id = 105, name = "Doom Skull mount"}},
		{key = "bounty25", stat = "bounty", value = 25, name = "Complete 25 bounty contracts",
			reward = {kind = "outfit", male = 1066, female = 1067, name = "Revenant outfit"}},
		{key = "worldboss5", stat = "worldboss", value = 5, name = "Defeat 5 world bosses",
			reward = {kind = "mount", id = 103, name = "Nightglass Devourer mount"}},
		{key = "rift10", stat = "rift", value = 10, name = "Complete a tier 10 rift", requires = "ChaosRift",
			reward = {kind = "title", title = "Ashen Riftwalker"}}
	},

	-- ------------------------------------------------------------------ ladder
	-- The leaderboard window gets a "Season" toggle while a season runs: the class ladder and the weekly boards
	-- then show only that season's characters (leaderboard.lua asks ChaosSeason.sendBoard).
	ladder = {
		rows = 20,
		cacheSeconds = 120,
		staffGroup = 4 -- left out of the season ladder (as on the leaderboards)
	},

	-- ------------------------------------------------------------------ modes (Self-Found, Hardcore)
	-- season_modes.lua (engine glue), season_modes_core.lua (rules). A character picks its mode in the join
	-- confirmation; it cannot be changed until the season ends. The end-of-season migration resets it (the character
	-- keeps its items). Table chaos_season_modes (sql/chaos_season.sql). See README "Season modes".
	modes = {
		table = "chaos_season_modes",
		ownerKey = "chaos_owner", -- custom item attribute: guid of the character an item on the ground / a corpse is from
		list = {
			{key = "standard", name = "Standard", short = "Standard", ssf = false, hc = false,
				warning = "Trade, party and loot with every character of the season."},
			{key = "ssf", name = "Self-Found", short = "Self-Found", ssf = true, hc = false,
				warning = "Self-Found: no trading of any kind (trade window, market, Orb Exchange, mail, bank transfers, " ..
					"items of other players on the ground), parties only with Self-Found characters, loot stays your own. " ..
					"Reward: +25% Item Find and +25% Rarity Find, and the Self-Found ladder."},
			{key = "hc", name = "Hardcore", short = "Hardcore", ssf = false, hc = true,
				warning = "Hardcore: one life. If this character dies it falls: it leaves the Hardcore ladder for good, " ..
					"becomes a standard character at once and its grave stays on the ladder."},
			{key = "hcssf", name = "Hardcore Self-Found", short = "HC Self-Found", ssf = true, hc = true,
				warning = "Hardcore Self-Found: one life AND no trading. Both sets of rules at once."}
		},
		ssf = {
			itemFind = 25, -- percent added to the character's Item Find (loot.lua itemFindMult)
			rarityFind = 25 -- percent added to its Rarity Find (loot.lua, the bonus rarity chance)
		},
		hc = {
			loginSeconds = 10, -- no damage for this long after every login
			heartbeatSeconds = 2, -- the client (game_season) sends a heartbeat this often while playing Hardcore
			pingLossSeconds = 6, -- no heartbeat for this long = the connection is lost (the client still attached)
			pingLossPerHour = 3, -- ping-loss protections per hour; a real disconnect is always protected
			pullSeconds = 8, -- without a client (or silent) this long: pulled to the temple
			restartGuardSeconds = 120, -- before the daily restart (the base server save) no Hardcore character can die
			announce = true -- broadcast a fall
		},
		messages = {
			trade = "Self-Found characters cannot trade.",
			party = "Self-Found characters can only be in a party with other Self-Found characters.",
			bank = "Self-Found characters cannot send or receive gold.",
			market = "Self-Found characters cannot buy or sell on the market.",
			orbs = "Self-Found characters cannot use the Orb Exchange.",
			mail = "Self-Found characters cannot send mail.",
			mailTo = "That character is Self-Found: it cannot receive mail.",
			loot = "Self-Found: you can only take your own items and your own loot.",
			give = "Self-Found: you cannot hand items to other players.",
			item = "That item belongs to a Self-Found character.",
			house = "Self-Found characters keep their items to themselves (house)."
		}
	},

	checkSeconds = 60, -- the season start / end check (migration) and the member cache refresh
	staffGroup = 4
}
