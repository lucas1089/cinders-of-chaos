-- Season pass (seasonpass.lua, seasonpass_core.lua, client game_battlepass). Every number, reward and pack of the
-- season pass, per season. Returned as a table, loaded as Chaos.seasonPassConfig (and by server/tests/seasonpass_test.lua).
-- Data only, no engine calls. Server local time. See server/README.md "Season pass".
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.
--
-- The pass belongs to a season of season_config.lua (same id): it runs while that season runs, for every character of
-- the account (season and standard characters alike), and starts from zero with the next season.
-- Progress (pass XP) comes from play only: experience, bosses, bounty contracts, rifts, treasure goblins, invasions and
-- the daily / weekly challenges. Nothing bought adds pass XP, except the tier skips of the top season pack (asked for
-- by the owner; they only move the cosmetic track).
--
-- Reward kinds (rewardKinds below; seasonpass_core.lua S.validate refuses anything else):
--   {kind = "item", id = <server id>, count = n}          only ids of `allowedItems` (gold and potions: no power)
--   {kind = "coins", amount = n}                           Chaos Coins to the account (chaos_shop_coins)
--   {kind = "title", title = "...", color = "#RRGGBB"}     name plate title of every character of the account
--   {kind = "outfit", male = look, female = look, addons = 0..3, name = "..."}   both looks, every character
--   {kind = "mount", id = <mounts.xml id>, clientid = look, name = "..."}       every character
--   {kind = "shader", id = <shaders.xml id>, name = "..."}                       every character
--   {kind = "portal", key = "<townportal_config.lua style key>", name = "..."}   Town Portal style (route "season")
--   {kind = "frame", frame = "<name plate frame id>", name = "..."}              name plate frame, can be switched off
--   {kind = "transmog", key = "<transmog_config.lua set key>", icon = <item id>, name = "..."}  a transmog appearance
--                                                          set of source "season" (ChaosSeasonPass.ownsTransmog)
--   {kind = "tierskips", count = n}                        packs only: n tiers of pass XP at once
--   {kind = "premium"}                                     packs only: the premium track of the pass
-- Cosmetics are account-wide and kept forever (also after the season); items go to the character that claims.

-- stock item ids (data/items/items.xml)
local PLATINUM, CRYSTAL = 2152, 2160
local GMP, GSP, UHP, SHP = 7590, 8472, 8473, 26031 -- great mana, great spirit, ultimate health, supreme health potions

local function gold(n)
	return {kind = "item", id = PLATINUM, count = n, name = n .. " platinum coins"}
end
local function crystal(n)
	return {kind = "item", id = CRYSTAL, count = n, name = n == 1 and "a crystal coin" or (n .. " crystal coins")}
end
local POTION = {[GMP] = "Great Mana Potions", [GSP] = "Great Spirit Potions", [UHP] = "Ultimate Health Potions",
	[SHP] = "Supreme Health Potions"}
local function potions(id, n)
	return {kind = "item", id = id, count = n, name = n .. " " .. POTION[id]}
end
local function coins(n)
	return {kind = "coins", amount = n, name = n .. " Chaos Coins"}
end

-- Season of Ash (season 1) cosmetics: every look below is existing art of the base server, not sold in the store and
-- not given by any other system (checked by server/tests/seasonpass_test.lua against shop_config.lua,
-- achievements_data.lua, season_config.lua and townportal_config.lua). `cosmetics` is the one list of what the season
-- pass claims, so other systems can check it.
local function everblight(addons, name)
	return {kind = "outfit", male = 974, female = 973, addons = addons, name = name}
end
local function title(text, color)
	return {kind = "title", title = text, color = color, name = "Title: " .. text}
end
-- the season's own outfit shaders (shaders.xml ids 25 and 26: server/tools/install_outfits.py reads them from here;
-- client game_chaosshaders draws them) and name plate frame (client game_nameplate plate_cinderwrought.png,
-- nameplate_core.lua N.FRAMES): sold nowhere, given only by the premium track
local ASH_DRIFT = {kind = "shader", id = 25, shader = "chaos_ash_drift",
	name = "Ash Drift"}
local CINDER_CROWN = {kind = "shader", id = 26, shader = "chaos_cinder_crown",
	name = "Cinder Crown"}
local CINDERWROUGHT = {kind = "frame", frame = "cinderwrought", name = "Cinderwrought plate frame"}

return {
	-- DB tables (server/sql/chaos_seasonpass.sql; seasonpass.lua also creates them at startup)
	tables = {
		accounts = "chaos_seasonpass", -- pass XP and premium per account and season
		claims = "chaos_seasonpass_claims", -- one row per claimed reward (the primary key stops a second claim)
		periods = "chaos_seasonpass_periods", -- daily caps and challenge progress per account, day / week
		packs = "chaos_seasonpass_packs", -- season packs bought (one row per account, season and pack)
		log = "chaos_seasonpass_log" -- claim / buy / tier / admin events
	},
	opcode = 227, -- ChaosOpcodes.seasonPass (client game_battlepass)
	-- player storages (Chaos.storage reserves 7100980 - 7100984 for the season pass)
	storage = {
		frameOff = 7100980 -- 1 = this character hides the season name plate frame
	},
	staffGroup = 4, -- characters of this group and up earn no pass XP (as the leaderboards leave them out)
	flushSeconds = 10, -- pending pass XP and counters are written at least this often (and at tier up, claim, logout)
	claimGraceDays = 14, -- rewards reached can still be claimed this many days after the season ended
	maxTier = 50,

	-- XP of one tier: base + step x (tier - 1). 50 tiers = 80 625 XP. Model (README "Season pass"): a player who
	-- does most dailies and the weeklies and plays about 45 minutes a day reaches tier 50 in about 9 weeks of the
	-- 13-week season; a player who plays every day for hours caps the sources in about 3 weeks.
	tierXp = {base = 1000, step = 25},

	-- Pass XP from play. dailyCap = most pass XP from that source per account and day (server midnight).
	-- bankDays: the caps bank over this many days (a rolling window: the last bankDays days together give at most
	-- bankDays x dailyCap), so a player who misses a day or two catches up on the next; days before the season bank
	-- nothing (2026-10-15, respect the players' time).
	bankDays = 3,
	--   exp       pass XP per 1% of the character's current level gained from monsters, counted on the monster's base
	--             experience times the experience stage of the level only: store potions, world buffs, stamina, the
	--             season modifier and other bonuses add nothing
	--   boss      every credited kill of a boss of bosspoints_config.lua (world bosses, the Trial Warden, endgame)
	--   bounty    a completed bounty contract
	--   rift      a completed rift: xp + perTier x key tier
	--   goblin    a treasure goblin slain
	--   invasion  a defended invasion with a contribution (the Defender board record)
	sources = {
		exp = {name = "Experience", xp = 1, dailyCap = 300},
		boss = {name = "Bosses", xp = 150, dailyCap = 600},
		bounty = {name = "Bounty contracts", xp = 60, dailyCap = 600},
		rift = {name = "Rifts", xp = 40, perTier = 8, dailyCap = 1200},
		goblin = {name = "Treasure goblins", xp = 150, dailyCap = 450},
		invasion = {name = "Invasions", xp = 120, dailyCap = 240}
	},

	-- Challenges: account-wide; each day one challenge of every daily slot is picked (the same for every account, from
	-- the season id and the day), each week (Monday, server midnight) one of every weekly slot. Progress counts from
	-- any character of the account. stat: kill (a monster slain), exp (1% of a level, as above), bounty, rift, rift8
	-- (a rift of tier 8 or higher), boss, goblin, invasion.
	challenges = {
		dailyXp = 250,
		weeklyXp = 1200,
		daily = {
			{ -- slot 1
				{key = "d_kill300", stat = "kill", target = 300, text = "Slay 300 monsters"},
				{key = "d_kill500", stat = "kill", target = 500, text = "Slay 500 monsters"},
				{key = "d_exp30", stat = "exp", target = 30, text = "Gain 30% of a level"}
			},
			{ -- slot 2
				{key = "d_bounty2", stat = "bounty", target = 2, text = "Complete 2 bounty contracts"},
				{key = "d_rift1", stat = "rift", target = 1, text = "Clear a rift"},
				{key = "d_bounty3", stat = "bounty", target = 3, text = "Complete 3 bounty contracts"}
			},
			{ -- slot 3
				{key = "d_kill200", stat = "kill", target = 200, text = "Slay 200 monsters"},
				{key = "d_exp20", stat = "exp", target = 20, text = "Gain 20% of a level"},
				{key = "d_rift2", stat = "rift", target = 2, text = "Clear 2 rifts"}
			}
		},
		weekly = {
			{ -- slot 1
				{key = "w_kill3000", stat = "kill", target = 3000, text = "Slay 3000 monsters"},
				{key = "w_exp200", stat = "exp", target = 200, text = "Gain two levels' worth of experience"}
			},
			{ -- slot 2
				{key = "w_bounty10", stat = "bounty", target = 10, text = "Complete 10 bounty contracts"},
				{key = "w_rift5", stat = "rift", target = 5, text = "Clear 5 rifts"},
				{key = "w_rift8", stat = "rift8", target = 2, text = "Clear 2 rifts of tier 8 or higher"}
			},
			{ -- slot 3
				{key = "w_boss3", stat = "boss", target = 3, text = "Defeat 3 bosses"},
				{key = "w_invasion1", stat = "invasion", target = 1, text = "Defend against an invasion"},
				{key = "w_goblin1", stat = "goblin", target = 1, text = "Slay a treasure goblin"}
			}
		}
	},

	-- item ids a reward may give (gold and potions); anything else is refused by the validator (no orbs, gems, keys,
	-- experience potions, stamina or gear)
	allowedItems = {[PLATINUM] = true, [CRYSTAL] = true, [GMP] = true, [GSP] = true, [UHP] = true, [SHP] = true},

	-- the store category (seasonpass_store.lua, included by the season pass hunk of shop_config.lua) sells the pass and
	-- the packs of this season
	storeSeason = 1,

	-- ------------------------------------------------------------------ passes, per season id
	passes = {
		[1] = {
			name = "Ashen Pass",
			-- price: decided 2026-10-14 (owner delegated; docs/PRICES.md): 600, 320 of it back on the track
			premium = {price = 600, unlock = "seasonPassPremium", icon = 26031,
				description = "Premium track of the Ashen Pass for your whole account: cosmetics only (titles, shaders, a frame, Everblight), 320 coins back."},
			-- tier = {free reward, premium reward}. The free track (gold and potions) is earned by play; the premium track
			-- is cosmetics and Chaos Coins back only (validated: seasonpass_core.lua P.PREMIUM_KINDS): no gold, no potions,
			-- no experience, no gear. 8 titles, 2 outfit shaders, a name plate frame, the Everblight outfit and its addons, a
			-- portal style, a mount and 10 coins on each of the other 32 tiers (320 back).
			tiers = {
				{gold(20), title("Kindled", "#ff9a3c")},
				{potions(GMP, 25), coins(10)},
				{gold(20), coins(10)},
				{potions(GSP, 25), coins(10)},
				{crystal(1), title("Ash-Touched", "#b8a898")},
				{potions(UHP, 25), coins(10)},
				{gold(30), coins(10)},
				{potions(GMP, 25), coins(10)},
				{potions(GSP, 25), coins(10)},
				{crystal(1), ASH_DRIFT}, -- 10
				{gold(30), coins(10)},
				{potions(UHP, 25), coins(10)},
				{potions(GMP, 25), coins(10)},
				{gold(30), coins(10)},
				{title("Ashwalker", "#c9b8a0"), everblight(0, "Everblight outfit")},
				{potions(GSP, 25), coins(10)},
				{potions(UHP, 25), coins(10)},
				{gold(40), title("Emberwake", "#ff8a4a")},
				{potions(GMP, 25), coins(10)},
				{crystal(2), title("Smoulderkin", "#d9783a")}, -- 20
				{potions(GSP, 25), coins(10)},
				{potions(UHP, 25), title("Pyrewarden", "#ff7a30")},
				{gold(40), coins(10)},
				{potions(GMP, 25), coins(10)},
				{crystal(2), {kind = "portal", key = "cinderfall", name = "Portal style: Cinderfall Gate"}},
				{potions(GSP, 25), coins(10)},
				{potions(UHP, 25), coins(10)},
				{gold(50), title("Ashen Herald", "#cdbb9a")},
				{potions(GMP, 50), coins(10)},
				{crystal(2), CINDER_CROWN}, -- 30
				{potions(GSP, 50), coins(10)},
				{potions(UHP, 50), everblight(1, "Everblight first addon")},
				{gold(50), coins(10)},
				{potions(GMP, 50), coins(10)},
				{crystal(3), title("Cinderborn", "#ff6a2c")},
				{potions(GSP, 50), coins(10)},
				{potions(UHP, 50), coins(10)},
				{gold(60), title("Flamebound", "#ff5a24")},
				{potions(GMP, 50), coins(10)},
				{crystal(3), CINDERWROUGHT}, -- 40
				{potions(GSP, 50), coins(10)},
				{potions(UHP, 50), title("Cinderlord", "#e8642a")},
				{gold(60), coins(10)},
				{potions(GMP, 50), coins(10)},
				{crystal(3), everblight(2, "Everblight second addon")},
				{potions(GSP, 50), coins(10)},
				{potions(UHP, 50), coins(10)},
				{gold(80), title("Ashen Sovereign", "#f0d8a8")},
				{potions(GMP, 50), coins(10)},
				{title("Ashbound", "#d8c8a8"), {kind = "mount", id = 106, clientid = 930, name = "Magma Skull mount"}} -- 50
			},
			-- Season packs: bought once per account (store or the pass window), only while the season runs. A pack holds
			-- the cosmetics of every lower pack too; buying a higher pack after a lower one costs the difference (and the
			-- premium pass price already paid counts for a pack that includes the pass).
			packs = {
				{id = 1, key = "ember", name = "Ember Pack", price = 500, unlock = "seasonPack1", look = 278,
					description = "Brotherhood outfit and addons, Cinderhoof mount, title Emberkin, Arboreal transmog. Account-wide.",
					rewards = {
						{kind = "outfit", male = 278, female = 279, addons = 3, name = "Brotherhood outfit (full)"},
						{kind = "mount", id = 90, clientid = 851, name = "Cinderhoof mount"},
						{kind = "title", title = "Emberkin", color = "#ffb05a", name = "Title: Emberkin"},
						{kind = "transmog", key = "arboreal", icon = 27679, name = "Arboreal transmog looks"}
					}},
				{id = 2, key = "blaze", name = "Blaze Pack", price = 1500, unlock = "seasonPack2", look = 1016,
					description = "Ember Pack, premium Ashen Pass, Doom Knight outfit and addons, Flamesteed, Pyre Gate portal.",
					rewards = {
						{kind = "premium", name = "Premium Ashen Pass"},
						{kind = "outfit", male = 1016, female = 1017, addons = 3, name = "Doom Knight outfit (full)"},
						{kind = "mount", id = 47, clientid = 626, name = "Flamesteed mount"},
						{kind = "portal", key = "pyre", name = "Portal style: Pyre Gate"}
					}},
				{id = 3, key = "inferno", name = "Inferno Pack", price = 2500, unlock = "seasonPack3", look = 665,
					description = "Blaze Pack, Chaos Acolyte outfit, Wrathfire Pegasus, title Inferno-Crowned, 500 coins, 10 tier skips.",
					rewards = {
						{kind = "outfit", male = 665, female = 664, addons = 3, name = "Chaos Acolyte outfit (full)"},
						{kind = "mount", id = 116, clientid = 1192, name = "Wrathfire Pegasus mount"},
						{kind = "title", title = "Inferno-Crowned", color = "#ff4a1c", name = "Title: Inferno-Crowned"},
						coins(500),
						{kind = "tierskips", count = 10, name = "10 tier skips"}
					}}
			}
		}
	},

	-- Every cosmetic the season pass and its packs give, by season: the one list of looks the season pass claims. Each
	-- entry carries the reward as `reward` (the shape achievements_data.lua and season_config.lua use), so the store's
	-- exclusion walk (shop_core.lua ChaosShopCore.exclusions) can read this file as it reads those.
	-- seasonpass_test.lua checks that each reward above is listed here and that no other system gives one of them.
	-- Not used: wings and auras (every one in wings.xml / auras.xml is sold in the store). The outfit shaders and the
	-- name plate frame are new art of this season (sold nowhere).
	cosmetics = {
		{season = 1, source = "pass premium 15 / 32 / 45", reward = {kind = "outfit", male = 974, female = 973, name = "Everblight"}},
		{season = 1, source = "Ember Pack", reward = {kind = "outfit", male = 278, female = 279, name = "Brotherhood"}},
		{season = 1, source = "Blaze Pack", reward = {kind = "outfit", male = 1016, female = 1017, name = "Doom Knight"}},
		{season = 1, source = "Inferno Pack", reward = {kind = "outfit", male = 665, female = 664, name = "Chaos Acolyte"}},
		{season = 1, source = "pass premium 50", reward = {kind = "mount", id = 106, name = "Magma Skull"}},
		{season = 1, source = "Ember Pack", reward = {kind = "mount", id = 90, name = "Cinderhoof"}},
		{season = 1, source = "Blaze Pack", reward = {kind = "mount", id = 47, name = "Flamesteed"}},
		{season = 1, source = "Inferno Pack", reward = {kind = "mount", id = 116, name = "Wrathfire Pegasus"}},
		{season = 1, source = "pass premium 25", reward = {kind = "portal", key = "cinderfall", name = "Cinderfall Gate"}},
		{season = 1, source = "Blaze Pack", reward = {kind = "portal", key = "pyre", name = "Pyre Gate"}},
		{season = 1, source = "pass premium 1", reward = {kind = "title", title = "Kindled"}},
		{season = 1, source = "pass premium 5", reward = {kind = "title", title = "Ash-Touched"}},
		{season = 1, source = "pass premium 18", reward = {kind = "title", title = "Emberwake"}},
		{season = 1, source = "pass premium 20", reward = {kind = "title", title = "Smoulderkin"}},
		{season = 1, source = "pass premium 22", reward = {kind = "title", title = "Pyrewarden"}},
		{season = 1, source = "pass premium 28", reward = {kind = "title", title = "Ashen Herald"}},
		{season = 1, source = "pass premium 38", reward = {kind = "title", title = "Flamebound"}},
		{season = 1, source = "pass premium 42", reward = {kind = "title", title = "Cinderlord"}},
		{season = 1, source = "pass premium 48", reward = {kind = "title", title = "Ashen Sovereign"}},
		{season = 1, source = "pass premium 10", reward = {kind = "shader", id = 25, name = "Ash Drift"}},
		{season = 1, source = "pass premium 30", reward = {kind = "shader", id = 26, name = "Cinder Crown"}},
		{season = 1, source = "pass premium 40", reward = {kind = "frame", frame = "cinderwrought", name = "Cinderwrought"}},
		{season = 1, source = "pass free 15", reward = {kind = "title", title = "Ashwalker"}},
		{season = 1, source = "pass premium 35", reward = {kind = "title", title = "Cinderborn"}},
		{season = 1, source = "pass free 50", reward = {kind = "title", title = "Ashbound"}},
		{season = 1, source = "Ember Pack", reward = {kind = "title", title = "Emberkin"}},
		{season = 1, source = "Inferno Pack", reward = {kind = "title", title = "Inferno-Crowned"}},
		{season = 1, source = "Ember Pack", reward = {kind = "transmog", key = "arboreal", name = "Arboreal"}}
	}
}
