-- chaos_constants.lua
-- Single source of truth for every opcode, storage key, DB table name and tunable value
-- used by the Chaos client-module scripts in this folder.
--
-- Every other file in this folder starts with:
--     if not Chaos then dofile("data/scripts/chaos/chaos_constants.lua") end
-- so load order inside data/scripts does not matter. This file is idempotent.
--
-- Lua dialect: TFS 1.4.2 / LuaJIT (Lua 5.1 semantics). Do not use 5.3-only syntax here.

-- the seven item rarities (names, order, the mapping of the 15 old ids): every script that has Chaos has ChaosRarity
if not ChaosRarity then
	-- the server folder is the working directory; the client tests run from the repository root
	if not pcall(dofile, "data/lib/chaos_rarity.lua") then
		pcall(dofile, "server/data/lib/chaos_rarity.lua")
	end
	if not ChaosRarity then
		dofile("data/lib/chaos_rarity.lua") -- fails with the real error
	end
end

-- gold payments from carried coins, then the bank (data/lib/chaos_pay.lua; Chaos.pay below)
if not ChaosPay then
	if not pcall(dofile, "data/lib/chaos_pay.lua") then
		pcall(dofile, "server/data/lib/chaos_pay.lua")
	end
	if not ChaosPay then
		dofile("data/lib/chaos_pay.lua") -- fails with the real error
	end
end

if Chaos then
	-- the first load can come from a spell (classes.lua), outside the Scripts interface: the opcode dispatch's engine
	-- events are made on the load that can make them (Chaos.opcodeDispatch.install)
	if Chaos.opcodeDispatch and Chaos.opcodeDispatch.install then
		Chaos.opcodeDispatch.install()
	end
	if ChaosPzGuard then
		ChaosPzGuard.install()
	end
	-- a reload hands the effect send offsets to the engine again, read anew (src-patch 0060; see the guard below)
	if ChaosFxSendOffsetCore and ChaosFxSendOffsetCore.applyEngine then
		ChaosFxSendOffsetCore.applyEngine(Game, true)
	end
	return
end

Chaos = {}

-- ---------------------------------------------------------------------------
-- Extended opcodes
-- ---------------------------------------------------------------------------
-- Opcodes already used by the base server reference server (checked by grep):
--   1 (language), 67 (item fusion), 73 (highscores), 89 (ancestral points push),
--   91 (crafting), 92 (tasks), 99 (reputation), 106 (char stats), 107 (inspect),
--   136 (party icons), 181 (character upgrades), 201 (game store), 202 (waystone/tier maps)
-- None of the values below collide with those.
ChaosOpcodes = {
	bank = 60,
	monsterbar = 125,
	passivetree = 65,
	notifications = 79,
	dungeons = 109,
	stash = 110, -- chosen here: the client stash.lua has no fixed number (see README)
	notificationsAction = 151, -- client -> server only (party invite / catacomb start)
	notificationsQueue = 152, -- client -> server only (leave queue)
	daily = 207,
	infinitytower = 214,
	autoloot = 216,
	shop = 218, -- Chaos store (client game_shop); the base server's own store uses 201
	bounty = 223, -- bounty board (client game_bounty; bounty.lua, bounty_config.lua)
	rift = 228, -- rift run HUD, server -> client (client game_rift; rift.lua, rift_config.lua)
	leaderboard = 229, -- leaderboards (client game_leaderboard; leaderboard.lua, leaderboard_config.lua)
	crafting = 232, -- crafting bench (client game_crafting; crafting.lua, data/lib/chaos_crafting.lua)
	siege = 233, -- guild siege HUD and sign-up window (client game_siege; siege.lua, siege_config.lua)
	arena = 236, -- ranked PvP arena window and match HUD (client game_arena; arena.lua, arena_config.lua)
	monkChi = 247, -- Monk chi HUD, server -> client, plain text "chi:<chi>:<max>:<decaySec>" (client game_monkchi; monk_chi_core.lua)
	lootfilter = 238, -- loot filter window, corpse highlight data, loot channel rows (client game_lootfilter; lootfilter.lua)
	nameplate = 248, -- name plates over players: title, guild, frame (client game_nameplate; nameplate.lua, titles.lua)
	season = 246, -- seasons window (client game_season; season.lua, season_config.lua)
	seasonPass = 227, -- season pass window: tiers, claims, challenges, packs (client game_battlepass; seasonpass*.lua)
	patchnotes = 244,
	hunt = 241, -- hunt tracker window, exp/h and profit/h (client game_hunt; hunt.lua, hunt_core.lua, hunt_config.lua)
	itemTooltip = 242, -- rich item tooltips with the equipped-item compare (client game_itemtooltip; item_tooltip*.lua)
	achievements = 250, -- achievements window and unlocks (client game_achievements; achievements*.lua)
	invasion = 251, -- invasion HUD and upcoming events window, server -> client (client game_invasion; invasion*.lua, worldevents.lua)
	guild = 252, -- Guild window: level, perks, members, guild bank, guild hall, depot, top guilds (client game_guild; guild*.lua)
	bestiary = 253, -- bestiary, kill tasks and the task tracker HUD (client game_bestiary; bestiary*.lua)
	pets = 254, -- pets window: owned pets, summon / dismiss / rename, levels and abilities (client game_pets; pets*.lua)
	supports = 243, -- spell supports window and action bar sockets (client game_spellsupports; supports.lua)
	spellbook = 219, -- spell list window (client game_spellbook)
	townPortal = 239, -- Town Portal cast bar and Portal Style window (client game_townportal; townportal.lua)
	mapmarks = 245, -- map overlay points of interest and the rift square (client game_mapoverlay; map_marks.lua)
	info = 237, -- Info & Services window: the player commands reached from the menu (client game_chaosinfo; commands_ui*.lua)
	itemLink = 249, -- items linked into chat: register / get a snapshot (client game_chatlinks; itemlink.lua, itemlink_core.lua)
	inspect = 240, -- Inspect Player window: equipment and public stats of another player (client game_playerinspect; inspect.lua, inspect_core.lua)
	market = 221, -- player market for gold and Chaos Coins (client game_market; market.lua, market_core.lua, market_config.lua)
	orbExchange = 209, -- Orb Exchange: order book for the crafting orbs, orb for orb and orb for gold (client game_orbexchange; orbexchange*.lua)
	buffs = 234, -- buff / debuff bar, server -> client diffs (client game_buffbar; buffbar.lua, data/lib/chaos_buffs.lua)
	energyShield = 224, -- energy shield bar, server -> client, sent by the engine (patch 0015, config energyShieldOpcode), plain text "es:<current>:<max>" (client game_energyshield)
	groundLoot = 230, -- ground loot labels: names, rarity and decay of the items on the tiles in view (client game_groundlabels; groundloot.lua)
	castbar = 231, -- cast bar of the cast-time spells, both ways (client game_castbar; casting.lua, data/lib/chaos_casting.lua)
	referral = 220, -- Referral window: own code, enter a code, referred friends (client game_referral; referral*.lua)
	pact = 222, -- Chaos Pact window: status, limits, daily coins, saved builds (client game_pact; pact.lua, pact_config.lua)
	transmog = 212, -- Transmog window: wardrobe, apply / remove a look (client game_transmog; transmog.lua, transmog_core.lua, transmog_config.lua)
	pouches = 226, -- store pouches: the Loot Pouch rules window (client game_pouches; pouches.lua, pouches_core.lua, pouches_config.lua)
	partyFrames = 235, -- party frames: members' health, mana, level, floor, buffs; client -> server actions (client game_partyframes; partyframes.lua)
	cosmetics = 225, -- Cosmetics window, chat name colours, loot label accent (client game_cosmetics; cosmetics*.lua)
	bossSpawns = 217 -- Boss Spawns window: every boss by category, place and respawn (client game_bossspawns; bossspawns*.lua)
}
-- Rift Atlas window: completion grid, node map, allocate / refund (client game_riftatlas; atlas.lua, atlas_core.lua, atlas_config.lua)
ChaosOpcodes.riftAtlas = 210
-- Waystone Atlas: the same window in waystone mode (client game_riftatlas; waystone_atlas*.lua)
ChaosOpcodes.waystoneAtlas = 159
-- DPS meter and combat log: per-skill damage / healing / taken, fights, party totals (client game_dpsmeter; combatlog*.lua)
ChaosOpcodes.combatLog = 204
-- Display scale: the viewer's level and factor, server -> client (client game_chaosscale; display_scale*.lua)
ChaosOpcodes.displayScale = 157
-- Client guard (engine src-patch 0021, client base patch 0035, clientguard*.lua; server/README.md "Client guard"): 189 is
-- the engine's HMAC handshake, both ways, handled in C++ on both sides (it never reaches Lua; listed so that no module
-- takes it); 190 is the module hello of client game_chaosguard, client -> server
ChaosOpcodes.clientGuard = 189
ChaosOpcodes.clientGuardHello = 190
-- The Ashen Chronicle and the Capital Memorial: chapters, record, Memorial choice (client game_chronicle; chronicle.lua,
-- memorial.lua; server/README.md "The Ashen Chronicle")
ChaosOpcodes.chronicle = 171
-- Candlemarks: the currency for time online, its counter and shop window (client game_candlemarks; candlemarks.lua,
-- candlemarks_core.lua, candlemarks_config.lua; server/README.md "Candlemarks"). Storages 7102460 - 7102469.
ChaosOpcodes.candlemarks = 176
-- NPCs that trade for something other than gold: the currency's name, icon and the player's balance in the NPC trade
-- window (client game_npctradewindow; data/lib/chaos_npc_currency.lua, tools/patch_npc_currency.py; README "NPC currencies")
ChaosOpcodes.npcCurrency = 113
Chaos.candlemarksTables = {accounts = "chaos_candlemarks", progress = "chaos_candlemark_progress",
	purchases = "chaos_candlemark_purchases"}

-- ---------------------------------------------------------------------------
-- Item custom attributes in item packets (engine patch server/src-patches/0003-item-custom-attributes.patch, client
-- feature GameItemCustomAttributes = 126): after every item the client gets u16 count, then u16 key + u64 value per
-- entry. The keys are the same numbers as ChaosItemAttrKey in the engine's const.h and ChaosItemAttr in the client
-- (modules/game_itemrarity); tests/item_tooltip_test.lua checks the three. item:getClientAttributes() returns them.
-- ---------------------------------------------------------------------------
Chaos.itemAttr = {
	rarity = 1, -- custom attribute "rarity" (1 Common, 2 Uncommon, 3 Magic, 4 Rare, 5 Legendary, 10 Divine; an old item 1..15)
	level = 2, -- custom attribute "combatPowerLevel" (item level)
	locked = 3, -- custom attribute "chaos_locked" (the item lock)
	unique = 4, -- custom attribute "chaos_unique" present
	sockets = 5, -- custom attribute "chaos_sockets" (socket count; a unique's fixed socket is not stored)
	id = 6, -- custom attribute "chaos_iid": per-item id, given by the engine the first time the item is sent
	version = 7, -- hash of the item's attributes: changes when the item changes (orbs, gems, upgrades)
	appearance = 8 -- custom attribute "chaos_tmog" (transmog look, server id) sent as the look's client id (engine patch 0019)
}

-- ---------------------------------------------------------------------------
-- Typed impact numbers (engine patch server/src-patches/0051-typed-impact-numbers.patch, client base patch 0100,
-- feature GameChaosImpactText = 155): every damage, heal, mana and experience text message carries u16 percent (x100),
-- u8 type and u32 creature id. The types are the same numbers as ChaosImpactType in the engine's const.h and
-- DamageScatterLogic.TYPE in the client (game_damagescatter); tests/impact_text_test.lua checks the three. Scripts:
-- player:sendTextMessage(type, text, pos, value, color, secondaryValue, secondaryColor, percent, typeId, creature).
-- 6 and up are free for scripts (the client keeps the stock font for them).
-- ---------------------------------------------------------------------------
Chaos.impactType = {
	normal = 0,
	critical = 1, -- CombatDamage.critical (combat.cpp rolls it)
	condition = 2, -- damage over time: a condition tick
	manaDrain = 3, -- mana lost: the mana shield or a mana drain
	manaGain = 4, -- mana restored
	energyShield = 5 -- taken by the energy shield (engine patch 0015)
}

-- ---------------------------------------------------------------------------
-- Player storage keys (7100000 - 7100999 is reserved for Chaos; unused by the reference server). The other Chaos
-- blocks up to 7127999 are listed in server/README.md "Storage keys".
-- ---------------------------------------------------------------------------
Chaos.storage = {
	-- autoloot: SAME base as the reference server's own scripts/creaturescripts/autoloot.lua
	-- (it stores item id in base+1 .. base+limit). Keeping it identical means the existing
	-- onDropLoot callback keeps working and uses the list edited from the client window.
	autolootBase = 80000,

	dailyStreakDay = 7100001, -- 1..7, the day slot that is claimable / was last claimed
	dailyLastClaim = 7100002, -- YYYYMMDD of the last claim (int32 safe)

	stashRemote = 7100010, -- >0 : player may keep the stash window open while walking
	-- the stash (stash_config.lua storage): 7100011 - 7100019 reserved; 7100011 journal serial, 7100012 depot -> stash migration (retired), 7100013 stash -> depot migration
	passiveExtraPoints = 7100020, -- bonus passive points granted by quests/GM
	passiveStatsFixed = 7100021, -- 1 once the stats older passive tree versions wrote into the character are clamped
	passiveClassFx = 7100022, -- the class nodes of the passive tree the character holds, a bit each (class_tree.lua)
	passiveRework = 7100023, -- the last reworked-nodes version refunded (passivetree_config.lua reworked)
	-- Paragon points kept from the track before O135 (1 point per level above 1000): set once at the first login after
	-- the fix (paragon.lua P.grantLegacy), -1 = not yet; the O135 cut wiped allocations through the login refund
	paragonLegacy = 7102501,
	paragonConverted = 7102500, -- free passive tree points the character exchanged for Paragon points (paragon.lua, O146); 7102500 - 7102509 reserved
	archetypeFlags = 7100024, -- the build archetype keystones held, a bit each (archetypes_config.lua storage)
	vigils = 7100025, -- the vigils switched on, a bit each (vigils_config.lua storage)
	snareElement = 7100026, -- the element the snares carry, chosen last (snares_config.lua storage.element)
	snareHit = 7100027, -- 1 while a snare's hits are dealt (snares_config.lua storage.hit; read by archetypes.lua)
	weaponStrike = 7100028, -- 1 while a spell's scripted weapon strike is dealt (ChaosSpell.weaponStrike; weapon_styles.lua leaves it out of the melee skill rule)
	dungeonQueueLock = 7100030, -- (os.time of the last queue join; anti spam)
	bountyWeekBonus = 7100300, -- bounty board (bounty.lua): 7100300 - 7100309 reserved; week key of the last weekly bonus
	riftRun = 7100400, -- rifts (rift.lua): 7100400 - 7100409 reserved; +0 tier of the key of a run in progress, +1..+3 its modifiers, +4 start, +5 sealed rifts in a row without a stronger key (pity)
	lootFilter = 7100500, -- loot filter settings of the character, packed in one value (lootfilter_core.lua F.pack); 7100500 - 7100509 reserved
	newPlayer = 7100250, -- new-player kit, welcome, milestones and tutorial island (newplayer*.lua): 7100250 - 7100269 reserved
	bestiary = 7100870, -- bestiary (bestiary_config.lua taskPointsStorage): 7100870 - 7100879 reserved; bestiary points from kill tasks
	-- spell supports (data/lib/chaos_supports_config.lua): 7109990 - 7109992 cast context / Reprisal, 7110000 - 7111999
	-- the support sockets keyed by spell id (base + spell id * 4 + 0..3)
	-- Town Portal (townportal_config.lua storage): 7101600 - 7101639 reserved; selected style, cooldown, store styles owned
	monk = 7100800, -- the Monk line (ChaosMonk.ids.storage in monk_chi_core.lua): 7100800 - 7100809 reserved; chi, its time, focus, Chi Ward
	inspectOff = 7100960, -- 1 = this character does not allow others to inspect it (inspect.lua; default on, so unset)
	-- market (market_config.lua storage): 7100970 - 7100979 reserved; listSeq, deliverSeq (crash-safe escrow markers)
	-- orb exchange (orbexchange_config.lua storage): 7100950 - 7100954 reserved; placeSeq, deliverSeq (crash-safe escrow markers)
	-- season pass (seasonpass_config.lua storage): 7100980 - 7100984 reserved; 7100980 = the season name frame is hidden
	-- cosmetics (cosmetics_config.lua storage): 7100940 - 7100949 reserved; the chosen kill effect, loot label accent,
	-- chat name colour, then one spell skin per class line (7100943 + slot)

	-- store: one-time cosmetics owned (base + id of the wings / aura / shader)
	shopWingsBase = 7100600,
	shopAuraBase = 7100650,
	shopShaderBase = 7100700,
	-- store name plate frames (shop.lua, kind "frame"): base + 1 violet, + 2 frost; 7100760 - 7100769 reserved
	shopFrameBase = 7100760,
	shopFrameActive = 7100769, -- index of the frame shown (0 / unset = the title's own frame)
	-- frame slots 9 and up (shop_core.lua C.FRAMES / frameStorage): base + slot - 9; 7102010 - 7102039 reserved
	shopFrameBase2 = 7102010,

	-- store services (shop_services.lua, autosell.lua): 7100100 - 7100159
	shopLootPouch = 7100100, -- RESERVED: the retired Bottomless Loot Pouch unlock (1 = owned; pouches.lua gives those owners a
	-- free Loot Pouch once). Never reuse the key.
	shopAutoSeller = 7100101, -- 1 = Auto Seller unlocked (per character)
	autosellPaused = 7100102, -- 1 = the auto seller's corpse selling switched off (Auto Seller window)
	autosellRarity = 7100103, -- the rarities the auto seller sells, packed (autosell_core.lua packTiers; 1 = old opt-in: all)
	nameChangeTokens = 7100104, -- unused name changes bought in the store
	vocationChangeTokens = 7100105, -- unused vocation changes bought in the store
	shopRarityAutoloot = 7100106, -- 1 = Rarity Autoloot unlocked (lootfilter.lua: autoloot by rarity)
	-- store pouches (pouches_config.lua storage): 7100107 Loot Pouch rules, 7100108 free Loot Pouch given, 7100109 pouches to give back
	autosellInterval = 7100152, -- the Auto Seller sells the Loot Bag by itself every N minutes (5/10/15/30/60); unset/0 = off
	autosellBase = 7100110 -- + 1 .. + Chaos.shopServices.autosellSlots: item ids on the auto-sell list
}

-- Anti-bot and player reports (client game_antibot; antibot*.lua, reports*.lua, sql/chaos_reports.sql): presence check
-- modal and the report dialog on one opcode; storages 7100890 - 7100899 reserved (antibot.lua: +0 last presence check,
-- +1 day key, +2 checks that day, +3 grace until, +4 suspicion score x 10)
ChaosOpcodes.antibot = 211
Chaos.storage.antibot = 7100890
Chaos.antibotTables = {reports = "chaos_reports", log = "chaos_antibot_log", holds = "chaos_antibot_holds"}
Chaos.botReviewTables = {daily = "chaos_bot_daily", actions = "chaos_bot_actions"} -- botreview.lua, sql/chaos_bot.sql

-- Wardrobe: footprints and outlines (cosmetics.lua kinds footprint / outline, client game_cosmeticfx) and the visual
-- exclusives (exclusives.lua, exclusives_core.lua, exclusives_config.lua, sql/chaos_exclusives.sql; the Collection tab
-- of client game_cosmetics, cosmetics opcode 225, no new opcode). Storages 7102000 - 7102049 reserved: +0 the chosen
-- footprint, +1 the chosen outline (cosmetics_config.lua storage), +10 .. +39 name plate frame slots 9 and up
-- (shopFrameBase2 above)
Chaos.storage.wardrobe = 7102000

-- Tester bots (server/README.md "Tester bots"; testers.lua, testers_core.lua, server/tools/testers.py): storages
-- 7102900 - 7102909 reserved: +0 is 1 on a tester character (written only by testers.py setup; the engine reads the
-- same key, src-patch 0059 CHAOS_TESTER_STORAGE: a tester is never counted online), +1 its supplies were given (the
-- TEST ONLY helper), +2/+3/+4 its hunt position x/y/z, +5 the day (days since 1970) of the
-- respec waiver (respec.lua R.testerWaived), +6 the waivers used that day; +7..9 free
Chaos.storage.tester = 7102900
Chaos.testerGuids = Chaos.testerGuids or {} -- guid -> name of every tester character (testers.lua fills it)

-- a tester bot: the storage, as the engine reads it
function Chaos.isTester(player)
	local ok, v = pcall(function()
		return player:getStorageValue(Chaos.storage.tester)
	end)
	return ok and v == 1
end

-- a tester bot by guid (offline too, once testers.lua loaded the list)
function Chaos.isTesterGuid(guid)
	return Chaos.testerGuids[tonumber(guid) or -1] ~= nil
end

-- SQL: the row of players alias `a` is not a tester (rankings, lists)
function Chaos.notTesterSql(alias)
	return string.format("NOT EXISTS (SELECT 1 FROM `player_storage` `ts` WHERE `ts`.`player_id` = %s.`id` " ..
		"AND `ts`.`key` = %d AND `ts`.`value` = 1)", alias or "`players`", Chaos.storage.tester)
end

-- the players online without the tester bots (every count a player sees)
function Chaos.countedPlayers()
	local n = 0
	for _, p in ipairs(Game.getPlayers()) do
		if not Chaos.isTester(p) then
			n = n + 1
		end
	end
	return n
end

-- ---------------------------------------------------------------------------
-- Database tables (created by server/sql/chaos.sql)
-- ---------------------------------------------------------------------------
Chaos.tables = {
	bank = "chaos_bank",
	stash = "chaos_stash",
	stashBlock = "chaos_stash_block",
	passiveTree = "chaos_passive_tree",
	paragon = "chaos_paragon", -- Paragon track allocations (paragon.lua)
	dungeonProgress = "chaos_dungeon_progress",
	dungeonRuns = "chaos_dungeon_runs",
	dungeonRunPlayers = "chaos_dungeon_run_players",
	towerPlayers = "chaos_tower_players",
	towerSeasonRewards = "chaos_tower_season_rewards", -- season-end top 3 chests, one row per season and character
	shopCoins = "chaos_shop_coins",
	shopHistory = "chaos_shop_history",
	-- store purchase log (also the weekly limits), gifts to offline characters, paid Chaos Coin orders (shop.lua, sql/chaos.sql)
	shopPurchases = "chaos_shop_purchases",
	shopGifts = "chaos_shop_gifts",
	coinOrders = "chaos_coin_orders",
	-- the Pix / PayPal donation of an order (shop_payments.lua, the website's pay/ worker and webhook)
	coinPayments = "chaos_coin_payments",
	coinGifts = "chaos_coin_gifts",
	-- beta starter coins, one row per account (beta.lua, beta_core.lua ChaosBetaCore.TABLE, sql/chaos_beta.sql)
	betaGrants = "chaos_beta_grants"
}
-- Rift Atlas: one row per character, completed grid cells and allocated nodes (atlas.lua, sql/chaos_rift_atlas.sql)
Chaos.tables.riftAtlas = "chaos_rift_atlas"
-- Waystone Atlas: one row per character, completed map cells and allocated nodes (waystone_atlas.lua, sql/chaos_waystone_atlas.sql)
Chaos.tables.waystoneAtlas = "chaos_waystone_atlas"
-- the visual exclusives, one row per account and unlock (exclusives.lua, sql/chaos_exclusives.sql; "Wardrobe" above)
Chaos.tables.exclusives = "chaos_exclusives"
-- Seasonal Journey (season_journey.lua, season_journey_config.lua, sql/chaos_season_journey.sql): on the season opcode
-- (246, actions journey*), no player storages
Chaos.tables.seasonJourneyStats = "chaos_season_journey_stats"
Chaos.tables.seasonJourney = "chaos_season_journey"
-- Ascended Omens and the Cinderheart (uber.lua): player storages 7100460 - 7100469 reserved; +0 the sigil kind of a run
-- in progress (the crash refund marker), +1 its start, +2 the sigil use exhaust
Chaos.storage.ascendedRun = 7100460

-- The Ember Descent (client game_descent; descent.lua, descent_core.lua, descent_config.lua, sql/chaos_descent.sql):
-- the roguelike trial window, run HUD and boon choice on one opcode; storages 7100410 - 7100419 reserved (+0 a run in
-- progress, +1 when the next free run is ready)
ChaosOpcodes.descent = 205
Chaos.storage.descent = 7100410
Chaos.tables.descentPlayers = "chaos_descent_players"
Chaos.tables.descentRuns = "chaos_descent_runs"
-- Factions with reputation (client game_factions; factions.lua, factions_core.lua, factions_config.lua,
-- sql/chaos_factions.sql): SQL only, no player storages
ChaosOpcodes.factions = 215
Chaos.tables.factions = "chaos_factions"
-- Community goals and the weekly world modifier (client game_community; community.lua, community_core.lua,
-- community_config.lua, sql/chaos_community.sql): SQL only, no player storages
ChaosOpcodes.community = 203
Chaos.tables.communityGoal = "chaos_community_goal"
-- The Ashen Sepulchre, the weekly raid (client game_raid; raid.lua, raid_core.lua, raid_config.lua, sql/chaos_raid.sql):
-- the raid window, journal, vendor and in-raid HUD on one opcode; storages 7100440 - 7100449 reserved (+0 inside a raid
-- instance, +1 .. +5 the end of this week's lockout of boss 1 .. 5: the Boss Spawns cooldown)
ChaosOpcodes.raid = 213
Chaos.storage.raid = 7100440
Chaos.tables.raidLockouts = "chaos_raid_lockouts"
Chaos.tables.raidInstances = "chaos_raid_instances"
-- Pocket bosses (pocketboss.lua, pocketboss_core.lua, pocketboss_config.lua, sql/chaos_pocketboss.sql): on the Boss
-- Spawns opcode (217, actions pocket*), no player storages; action ids 47620 - 47629 reserved (47620 the way out)
Chaos.tables.pocketBoss = "chaos_pocketboss"
-- Loadouts / Armory (client game_loadouts; loadouts.lua, loadouts_core.lua, loadouts_config.lua, sql/chaos_loadouts.sql):
-- save and switch whole builds; storages 7100570 - 7100579 reserved (+0 active slot, +1 switch serial, +2 last switch),
-- and 7112000 - 7127999 for the support runes each loadout holds (loadouts_config.lua runeMirrorBase)
ChaosOpcodes.loadouts = 206
Chaos.storage.loadouts = 7100570
Chaos.tables.loadouts = "chaos_loadouts"
-- Depot tabs (client game_depottabs; depot.lua, depot_core.lua, depot_config.lua, tools/patch_base_depot.py): the depot
-- window (tab counts, tab switch requests, tab names and colours); no storages (tabs bought are pact.lua extras)
ChaosOpcodes.depotTabs = 111
Chaos.tables.depotTabs = "chaos_depot_tabs" -- depot tab names and colours per account (depot.lua, sql/chaos_depot_tabs.sql)
-- Hideouts (client game_hideout; hideout.lua, hideout_core.lua, hideout_config.lua, hideout_store.lua,
-- sql/chaos_hideout.sql): decoration window, placement, permissions, visits and likes on one opcode; storages
-- 7100180 - 7100189 reserved (hideout_config.lua storage: the spot a character entered from); map grid x/y 12288 - 12799
ChaosOpcodes.hideout = 192
Chaos.storage.hideout = 7100180
Chaos.tables.hideouts = "chaos_hideouts"
-- PvP battleground "Ember Wells" and the PvP seasons (client game_battleground; battleground*.lua, arena_season.lua,
-- sql/chaos_battleground.sql): queue, vendor, season window, match HUD and scoreboard on one opcode; storages
-- 7100380 - 7100389 reserved (battleground_config.lua storage); map grid x/y 11264 - 11455
ChaosOpcodes.battleground = 200
-- Guild wars in game and the weekly guild boss (client game_guildwar; guildwar*.lua, guildboss*.lua,
-- sql/chaos_guildwar.sql): one opcode for both; storage 7101302 (in the guild block 7101300 - 7101309) holds the end of
-- the guild boss lockout of the character's guild (the Boss Spawns cooldown)
ChaosOpcodes.guildWar = 197
Chaos.storage.guildBossLockout = 7101302
Chaos.tables.guildWars = "chaos_guildwar"
Chaos.tables.guildBoss = "chaos_guildboss_week"
-- Mentors (client game_mentor; mentor.lua, mentor_core.lua, mentor_config.lua, sql/chaos_mentor.sql): mentor list,
-- apprentice view, marks shop on one opcode; storages 7100360 - 7100369 reserved (+0 "looking for a mentor")
ChaosOpcodes.mentor = 194
Chaos.storage.mentor = 7100360
Chaos.tables.mentors = "chaos_mentors"
Chaos.tables.mentorLinks = "chaos_mentor_links"
-- Veiled modifiers: the Unveil window of the Orb of Unveiling (client game_unveil; veiled.lua, data/lib/chaos_veiled*.lua);
-- no storages, no tables (item attributes only)
ChaosOpcodes.veiled = 196
-- Charms: the charm grid window (client game_charms; charms.lua, charms_core.lua, charms_config.lua, sql/chaos_charms.sql);
-- storages 7100470 - 7100479 reserved (+0 the place / take serial, the crash marker; +1 the Last Ember cooldown)
ChaosOpcodes.charms = 198
Chaos.storage.charms = 7100470
Chaos.tables.charms = "chaos_charms"
-- The Scorched Marches, the open-world PvP zone (client game_pvpzone; pvpzone.lua, pvpzone_core.lua, pvpzone_config.lua,
-- sql/chaos_pvpzone.sql): window, entry confirmation, vendor and HUD on one opcode; storages 7100520 - 7100529 reserved
-- (pvpzone_config.lua storage: +0 inside, +1 protected until, +2 carried embers, +3..5 return spot, +6 entered at);
-- map grid x/y 13312 - 13823
ChaosOpcodes.pvpZone = 193
Chaos.storage.pvpZone = 7100520
Chaos.tables.pvpZone = "chaos_pvpzone_players"
-- Professions: gathering for the Material Broker and the experience bonus (client game_professions; professions.lua,
-- professions_core.lua, professions_config.lua, sql/chaos_professions.sql); no storages (node cooldowns in memory)
ChaosOpcodes.professions = 195
Chaos.tables.professions = "chaos_professions"
Chaos.tables.professionSales = "chaos_professions_sales"
-- The Gambler: sealed equipment for gold, a stock per character every 4 hours (client game_gamble; gamble.lua,
-- gamble_core.lua, gamble_config.lua, NPC data/npc/Mordecai Ashwager.xml); storages 7101900 - 7101909 reserved
-- (+0 window, +1 level, +2 vocation, +3 sold slots, +4 early refreshes); no tables
ChaosOpcodes.gamble = 199
Chaos.storage.gamble = 7101900
-- Conquest Tokens: the token vendor and bad-luck protection (client game_conquest; conquest.lua, conquest_core.lua,
-- conquest_config.lua, sql/chaos_conquest.sql, NPC data/npc/Iselde Varrow.xml); storages 7102640 - 7102689 reserved
-- (+0 day, +1..+29 tokens today per source, +30..+39 misses in a row per pity group)
ChaosOpcodes.conquest = 167
Chaos.storage.conquest = 7102640
Chaos.tables.conquest = "chaos_conquest"
-- Map markers (client game_mapmarkers; server/README.md "Map markers"). One opcode for two scripts, JSON {action, data}:
-- partymarkers.lua (+ _core, _config): where the other party members are; poi.lua (+ _core, _config, the generated
-- data/chaos_poi.lua of tools/gen_poi.py): points of interest, the discovered ones in chaos_poi_seen
-- (sql/chaos_poi.sql). No player storages.
ChaosOpcodes.mapMarkers = 153
Chaos.tables.poiSeen = "chaos_poi_seen"
-- Right-click equips (engine src-patch 0024, server/README.md "Right-click equips"; rightclick_equip.lua,
-- rightclick_equip_core.lua; client game_rightclickequip): the client option "Right-click equips items", client ->
-- server {on = true | false}. Storages 7101810 - 7101819 reserved: +0 is 1 while the player turned it off (the engine
-- reads it, CHAOS_EQUIP_ON_USE_OFF in game.cpp). No tables.
ChaosOpcodes.rightClickEquip = 188
Chaos.storage.rightClickEquipOff = 7101810
-- Keep attacking while moving (engine src-patch 0028, server/README.md "Keep attacking while moving"; kitewalk.lua,
-- kitewalk_core.lua; client game_kitewalk): the client option "Keep attacking while moving", client -> server
-- {on = true | false}. Storages 7101820 - 7101829 reserved: +0 is 1 while the player turned it off (the engine reads it,
-- CHAOS_KITE_WALK_OFF in game.cpp). No tables.
ChaosOpcodes.kiteWalk = 186
Chaos.storage.kiteWalkOff = 7101820
-- Item finder: where an item drops, who sells and buys it, the recipes that make or use it (client game_itemfinder;
-- itemfinder.lua, itemfinder_core.lua, itemfinder_sources.lua, itemfinder_config.lua; server/README.md "Item finder").
-- One index in memory, built at startup. No storages, no tables.
ChaosOpcodes.itemFinder = 155
-- Progress bars over tiles (client game_tileoverlays; tilebars.lua, tilebars_core.lua, tilebars_config.lua;
-- server/README.md "Progress bars over tiles"): server -> client bars over map positions for the players near them
-- (battleground braziers, profession nodes, the invasion breach), client -> server hello. No storages, no tables.
ChaosOpcodes.tileBars = 156

-- ---------------------------------------------------------------------------
-- Module settings
-- ---------------------------------------------------------------------------
Chaos.bank = {
	-- Gold uses the native player bank balance (players.balance), the same as the NPC banks.
	-- "star" is a second currency: carried as an item, banked in chaos_bank.stars.
	-- 0: off. The star tab came with the imported client (its item 35572 exists in no item list of this game), so the
	-- client hides it; set a real server item id here (and show the tab) to bring stars back.
	starItemId = 0,
	starWithdrawMax = 1000, -- the client UI caps a withdraw at 1000 per action; enforced here too
	maxAmount = 2000000000, -- sanity cap on a single operation
	transferMinLevel = 1,
	rateLimitMs = 300 -- one money request (deposit, withdraw, all, transfer) per this many ms; opening has its own key
}

Chaos.autoloot = {
	freeLimit = 10, -- mirrors the reference autoloot.lua
	premiumLimit = 20
}

Chaos.daily = {
	-- Reward for streak day 1..7 (SERVER item ids that exist in our items.otb; client ids are looked up at send time).
	-- The window shows one item per day; the bonus below is added to day 7 on top of it.
	rewards = {
		{itemId = 2152, count = 20},  -- platinum coin
		{itemId = 29856, count = 1},  -- Orb of Upheaval
		{itemId = 2152, count = 50},  -- platinum coin
		{itemId = 29857, count = 1},  -- Orb of Fate
		{itemId = 2160, count = 1},   -- crystal coin
		{itemId = 29856, count = 3},  -- Orb of Upheaval
		{itemId = 29857, count = 3}   -- Orb of Fate
	},
	-- given together with day 7 (all or nothing with it): a full week of claims
	weekBonus = {
		{itemId = 2160, count = 2}    -- crystal coin
	},
	openOnLogin = true, -- send OpenDailyWindow at login when today's reward is unclaimed
	openDelayMs = 3000
}

Chaos.passive = {
	rootNode = 1,
	startLevel = 8, -- level 8 has no points; points are counted from here
	levelsPerPoint = 4, -- 1 point every 4 levels: ~248 at level 1000 for 618 nodes, so a build has to choose
	-- past the tree budget: the Paragon track (Chaos.paragon below, paragon.lua)
	maxPresets = 6,
	resetCostPerLevel = 250 -- gold per level; the client text promises "level x 250"
}

-- Paragon track (paragon.lua): 1 point per level above startLevel, spent on small capped stats. A stat's cap is
-- perPoint x maxPoints. Paragon bonuses are added on top of the passive tree's by passivetree_effects.lua.
-- The reset costs level x Chaos.passive.resetCostPerLevel gold, like the tree's.
Chaos.paragon = {
	startLevel = 1000, -- the level where the tree budget (about 248 points) ends; points from level 1001 on
	pointsPerLevel = 1,
	-- O135 (smooth progression): the track used to be maxed at level 1282 (282 points), leaving 900 levels of nothing.
	-- 1 point per level up to slowFrom, then 1 point every levelsPerPointSlow levels: maxed at level 2192
	slowFrom = 1100,
	levelsPerPointSlow = 6,
	categories = {
		{key = "offense", name = "Offense", stats = {
			{key = "damage", name = "Damage", perPoint = 0.5, maxPoints = 40, desc = "Damage dealt (every damage type, not healing)"},
			{key = "critDamage", name = "Critical Damage", perPoint = 0.3, maxPoints = 50, desc = "Extra damage of critical hits"}}},
		{key = "defense", name = "Defense", stats = {
			{key = "health", name = "Max Health", perPoint = 0.5, maxPoints = 40, desc = "Maximum health"},
			{key = "reduction", name = "Damage Reduction", perPoint = 0.25, maxPoints = 32, desc = "Less damage taken from every type"}}},
		{key = "utility", name = "Utility", stats = {
			{key = "speed", name = "Movement Speed", perPoint = 0.5, maxPoints = 20, desc = "Of your base speed"},
			{key = "mana", name = "Max Mana", perPoint = 0.5, maxPoints = 40, desc = "Maximum mana"}}},
		{key = "fortune", name = "Fortune", stats = {
			{key = "goldFind", name = "Gold Find", perPoint = 1.0, maxPoints = 20, desc = "More gold coins in your kills' corpses"},
			{key = "itemFind", name = "Item Find", perPoint = 0.5, maxPoints = 40, desc = "Chaos loot: extra rolls, currency, uniques, rarity"}}}
	},
	-- O146 (beta feedback: "I filled all Paragon at level 1100-1200, at 1500 I have 300 points with nothing to spend them on"):
	-- Paragon Mastery, an endless sink. A rank costs 1 point (so every point earned after the categories above are full
	-- still counts). A mastery of `ranks` ranks gives  scale x ln(1 + ranks / h)  percent: the first ranks are worth
	-- scale / h each, the gain per rank keeps falling (scale / (h + ranks)) but never reaches zero, and there is no
	-- maximum. `bonus` is the Paragon bonus key it adds to (the same keys the categories above use, so one condition /
	-- storage per effect); `category` is the group of the window. 300 ranks of damage (scale 6, h 50) are +11.7%, 1000
	-- ranks +18.2%; the categories above give +20% at their 40 points. Critical chance and speed have no mastery on
	-- purpose (a flat crit chance or movement speed is a PvP lever); the reductions apply in whole percent (the absorb
	-- storage), like every Paragon reduction. maxRanks: the table column is a smallint.
	mastery = {
		maxRanks = 60000,
		stats = {
			{key = "mDamage", category = "offense", name = "Damage Mastery", bonus = "damage", scale = 6, h = 50,
				desc = "Damage dealt (every damage type, not healing)"},
			{key = "mCritDamage", category = "offense", name = "Critical Damage Mastery", bonus = "critDamage", scale = 8, h = 50,
				desc = "Extra damage of critical hits"},
			{key = "mHealth", category = "defense", name = "Health Mastery", bonus = "health", scale = 8, h = 50,
				desc = "Maximum health"},
			{key = "mReduction", category = "defense", name = "Reduction Mastery", bonus = "reduction", scale = 3, h = 60,
				desc = "Less damage taken from every type (whole percent, under the 75% ceiling)"},
			{key = "mMana", category = "utility", name = "Mana Mastery", bonus = "mana", scale = 8, h = 50,
				desc = "Maximum mana"},
			{key = "mGoldFind", category = "fortune", name = "Gold Mastery", bonus = "goldFind", scale = 10, h = 50,
				desc = "More gold coins in your kills' corpses"},
			{key = "mItemFind", category = "fortune", name = "Item Mastery", bonus = "itemFind", scale = 8, h = 50,
				desc = "Chaos loot: extra rolls, currency, uniques, rarity"}
		}
	},
	-- O146: free passive tree points have nothing to buy once the nodes the class cares about are taken, and they keep
	-- coming (1 per 4 levels). The Paragon window exchanges them: `ratio` Paragon points for each tree point, for good
	-- (paragonConverted storage; the tree's point total drops by the same count). From the Paragon unlock level.
	exchange = {ratio = 1}
}

Chaos.stash = {
	-- true: tell the client the stash is remote (window stays open while walking, no depot needed).
	remoteForEveryone = true,
	chunkSize = 40, -- items per addItems packet (keeps packets well under the 24 KB limit)
	maxDistance = 1, -- max Chebyshev distance to a floor item that is stashed from the map
	maxStackPerEntry = 2000000000
}

Chaos.dungeons = {
	-- how the base server DUNGEON_SYSTEM (lib/core/dungeon.lua) is reused:
	--   * list / levels / party size / DungeonPos / FromPos / ToPos / DungeonTime / cooldown storage
	-- Everything the base server table does not have is declared here, per base server dungeon id.
	exitDelayMs = 10000, -- delay between finishing and teleporting the group out
	-- instance limits (instance_limits.lua, server/README.md "Instance limits"): a queue run lasts the base server's
	-- DungeonTime (60 / 30 minutes) but at most maxTimeSeconds; warnings at warnAt seconds left. One run per dungeon at
	-- a time (the base dungeon is one map area): the queue is the waiting line and shows the wait of the run inside.
	-- Pack combat (pace.lua, 2026-10-14; owner: dungeons of at most 10-15 minutes, at least 100 monsters each): 15
	-- minutes (was 45). The base dungeons keep 100-119 of their monsters (tools/spawn_tuning.json "dungeons") and their
	-- own health curves below: the run model gives 9.5 minutes at difficulty 1 and 13.7 at 6 (server/README.md
	-- "Pack combat (pace)").
	maxTimeSeconds = 900,
	limits = {warnAt = {300, 60, 10}},
	-- the cooldown (2026-10-15, respect the players' time): a cleared run 15 minutes (cooldownSeconds, about one more
	-- run's length; runs take 10-15), it replaces the base server's DUNGEON_SYSTEM.CooldownTime (3600, after every run).
	-- A failed run, a time-out, leaving or dying inside: a short failCooldownSeconds, 5 minutes, so farming 85% of the
	-- monsters and leaving does not pay (owner rule "follow your recommendations", 2026-10-15).
	-- Owner 2026-10-24: no cooldown after a cleared run any more (cooldownOnSuccess false); the short fail cooldown stays.
	cooldownOnSuccess = false,
	cooldownOnFail = true,
	cooldownSeconds = 0,
	failCooldownSeconds = 300,
	queueTickMs = 3000,
	-- party size (beta feedback 2026-10-22: dungeons must be doable solo). A base dungeon's NeedParty / AmountParty is now
	-- only the MAXIMUM group; one player may enter alone. The monster numbers (curves, trashHealth, bossHealth) are the
	-- measured solo ones, so 1 player = x1.0 and every further player adds: health x (1 + healthPerExtra (n-1)), damage
	-- to the run's players x (1 + damagePerExtra (n-1)) (dungeons_difficulty.lua D.partyHealth / D.partyDamage). Health
	-- grows slower than the group's damage, so a group clears faster than a solo player. A queue entry waits
	-- soloWaitSeconds for a partner of the same difficulty, then the run starts with whoever is queued.
	party = {healthPerExtra = 0.6, damagePerExtra = 0.1, soloWaitSeconds = 5},
	maxDifficulty = 6, -- client has 6 difficulty buttons
	-- percentage of the run's monsters that must die to unlock the boss (owner, 2026-10-14: 85, was 100): the members
	-- get "Boss unlocked!", a generated dungeon (areagen.lua) opens its boss room gate and spawns its boss; a run is won
	-- when the boss dies after that (dungeons.lua unlockBoss)
	progressNeeded = 85,
	-- stuck safety (O180, owner 2026-10-24: "stuck at 83% with 20 monsters alive, can't find them"): when the kill percent
	-- has not moved for `seconds`, the members are told where the nearest remaining monsters stand (a text line and an
	-- effect on their tiles, every `hintEveryMs`, at most `hintMax`); once the percent is at least `minPercent` the boss is
	-- unlocked anyway (the rest may stand where nobody can reach them), so a map flaw never blocks a run
	stall = {seconds = 150, minPercent = 60, hintEveryMs = 30000, hintMax = 5},
	-- O183: a monster of a run is placed on its tile or the nearest free walkable tile of the same floor within radius tiles
	placement = {radius = 4},
	-- area = {{from, to}, ...}: boxes that belong to the dungeon next to the base FromPos/ToPos box (dungeons.lua areaOf),
	-- for the parts that box misses: measured on the base map and its boss scripts (server/README.md "dungeons")
	extra = {
		[1] = {
			title = "Bones Dungeon",
			bossName = "prince skeletal",
			-- the lever boss room east of the box (the boss script's bossArea; boss, entrance and exit teleport in it)
			area = {{{x = 31856, y = 32197, z = 8}, {x = 31908, y = 32236, z = 8}}},
			loot = {{id = 2160, count = 3}},
			-- pack combat: the boss Prince Skeletal 200,000 at level 175 (533/s): 6:15 alone, x40% = 2:30
			-- (bossHealth x 100-225% like the generated dungeons); the trash its own curve in place of the difficulty
			-- table's 100-1300% (the run model's fit with at least 100 monsters, server/README.md "Pack combat (pace)")
			bossHealth = {40, 50, 60, 70, 80, 90},
			trashHealth = {75, 86, 97, 108, 119, 129},
			challenges = {
				{key = "speed", title = "Speed Runner", points = 5, desc = "Finish in under 6 minutes.", maxMs = 6 * 60 * 1000},
				{key = "flawless", title = "Flawless", points = 10, desc = "Finish without anyone dying."}
			}
		},
		[2] = {
			title = "Master of the Elements",
			bossName = "master of the elements",
			loot = {{id = 2160, count = 5}},
			-- pack combat: the boss 300,000 at level 225 (685/s): 7:18 alone, x34% = 2:30
			-- (bossHealth x 100-225% like the generated dungeons); the trash its own curve in place of the difficulty
			-- table's 100-1300% (the run model's fit with at least 100 monsters, server/README.md "Pack combat (pace)")
			bossHealth = {34, 43, 51, 60, 68, 77},
			trashHealth = {74, 83, 92, 101, 109, 118},
			challenges = {
				{key = "speed", title = "Speed Runner", points = 5, desc = "Finish in under 6 minutes.", maxMs = 6 * 60 * 1000},
				{key = "flawless", title = "Flawless", points = 10, desc = "Finish without anyone dying."}
			}
		},
		[3] = {
			title = "Forbidden Chevalier",
			bossName = "forbidden chevalier",
			-- the base box is floor 7 only (widened to the entry on floor 0): the tower's floors 0-10 with every spawn,
			-- the lever and the boss room on floor 10 (the map's tiles of the dungeon)
			area = {{{x = 31950, y = 33098, z = 0}, {x = 32078, y = 33245, z = 10}}},
			loot = {{id = 2160, count = 8}},
			-- pack combat: the boss 550,000 at level 525 (1,455/s): 6:18 alone, x40% = 2:30
			-- (bossHealth x 100-225% like the generated dungeons); the trash its own curve in place of the difficulty
			-- table's 100-1300% (the run model's fit with at least 100 monsters, server/README.md "Pack combat (pace)")
			bossHealth = {40, 50, 60, 70, 80, 90},
			trashHealth = {34, 37, 41, 44, 47, 51},
			challenges = {
				{key = "speed", title = "Speed Runner", points = 5, desc = "Finish in under 6 minutes.", maxMs = 6 * 60 * 1000},
				{key = "flawless", title = "Flawless", points = 10, desc = "Finish without anyone dying."}
			}
		},
		[4] = {
			title = "Rootmaw",
			bossName = "the rootmaw",
			-- the base box is only the entry hall (and DungeonPos is 3 tiles south of it): floors 8-12 with every spawn,
			-- the lever on floor 11 and the boss room on floor 12 (the map's tiles of the dungeon)
			area = {{{x = 31452, y = 31495, z = 8}, {x = 31736, y = 31644, z = 12}}},
			loot = {{id = 2160, count = 10}},
			-- pack combat: the boss 685,000 at level 625 (1,696/s): 6:44 alone, x37% = 2:30
			-- (bossHealth x 100-225% like the generated dungeons); the trash its own curve in place of the difficulty
			-- table's 100-1300% (the run model's fit with at least 100 monsters, server/README.md "Pack combat (pace)")
			bossHealth = {37, 46, 56, 65, 74, 83},
			trashHealth = {61, 67, 73, 79, 85, 91},
			challenges = {
				{key = "speed", title = "Speed Runner", points = 5, desc = "Finish in under 6 minutes.", maxMs = 6 * 60 * 1000},
				{key = "flawless", title = "Flawless", points = 10, desc = "Finish without dying."}
			}
		}
	}
}

Chaos.tower = {
	-- Season = fixed-length window counted from seasonEpoch (infinitytower_core.lua K.seasonOf): a unix time or
	-- {year, month, day, hour} in server local time. Before the epoch it is season 1. The tower keeps its own 30-day
	-- seasons (points, milestones and the ranking reset each one); the server Seasons (season_config.lua) are 13-week
	-- realms with gaps that staff can start and end by hand, so they are not used here. The epoch is the launch
	-- (docs/BETA.md: Fri 20 Nov 2026 15:00), so Tower Season 1 starts with the server (it was 2025-01-01, which made the
	-- launch season 22). Changing it renumbers the seasons of chaos_tower_players: only on a wiped database.
	seasonEpoch = {year = 2026, month = 11, day = 20, hour = 15},
	seasonLengthDays = 30,
	-- Season end (infinitytower.lua ChaosTower.checkSeasons; server/README.md "Infinity Tower season rewards"): the top
	-- 3 of the ended season's ranking (best floor, then best time; equal floor and time share the place; staff and
	-- characters held by the anti-bot left out) get the chest of their place once: a row in chaos_tower_season_rewards,
	-- delivered into the inbox at once when online, else at the next login. server_config `configKey` = the last season
	-- paid out. chestId: an existing pickupable container of the base items (its look on the podium), renamed by the
	-- item name attribute; items: existing orbs (install_orbs.py).
	seasonEnd = {
		checkSeconds = 60,
		configKey = "chaos_tower_season_done",
		staffGroup = 4,
		chests = {
			{name = "Gold Tower Chest", chestId = 1746, items = { -- treasure chest, 10 slots
				{id = 29857, count = 20, name = "Orb of Fate"}, {id = 29856, count = 40, name = "Orb of Upheaval"}}},
			{name = "Silver Tower Chest", chestId = 1740, items = { -- chest, 15 slots
				{id = 29857, count = 12, name = "Orb of Fate"}, {id = 29856, count = 25, name = "Orb of Upheaval"}}},
			{name = "Copper Tower Chest", chestId = 1738, items = { -- box, 10 slots
				{id = 29857, count = 6, name = "Orb of Fate"}, {id = 29856, count = 12, name = "Orb of Upheaval"}}}
		}
	},
	tryCooldownSeconds = 0, -- "Next Try Available"; 0 = always ready
	pointsPerFloor = 1000,
	rankingSize = 10,
	-- Milestones: SERVER item ids that exist in our items.otb (the client window reads the real ones from the
	-- server; its built-in fallback list is only shown before the first update).
	milestones = {
		{points = 60000, items = {{id = 2148, count = 300, name = "Gold Coin"}}},
		{points = 120000, items = {{id = 29856, count = 3, name = "Orb of Upheaval"}}},
		{points = 180000, items = {{id = 29857, count = 3, name = "Orb of Fate"}}},
		{points = 240000, items = {{id = 29857, count = 10, name = "Orb of Fate"}}},
		{points = 300000, items = {{id = 8209, count = 1, name = "Soulreaper"}}}
	}
}

-- Event schedule (events_schedule.lua). Recurring events; every event is active for whole server days.
--   weekdays = {1..7} (1 = Sunday, os.date("%w") + 1), or monthdays = {1, 2, ...}
--   bonus: xp (multiplier), loot (multiplier on the Chaos loot layer + one extra roll on normal
--          monsters), tierChance (multiplier on magic/rare/legendary spawn chance), ambush (multiplier
--          on the ambush chance after a kill), towerPoints (multiplier on Infinity Tower points)
-- colorlight / colordark are the colours of the event in the client calendar.
Chaos.events = {
	list = {
		{id = "bloodmoon", name = "Blood Moon", weekdays = {7, 1}, colorlight = "#d23a2a", colordark = "#7a1a12",
			description = "The blood moon rises over the world: +50% experience from every kill.",
			bonus = {xp = 1.5}},
		{id = "chaosrift", name = "Chaos Rift", weekdays = {4}, colorlight = "#9b59d6", colordark = "#4d2470",
			description = "Reality tears open: magic, rare and legendary monsters appear twice as often and ambushes are more likely.",
			bonus = {tierChance = 2.0, ambush = 1.5}},
		{id = "lootfrenzy", name = "Loot Frenzy", weekdays = {6}, colorlight = "#e0a526", colordark = "#7a5410",
			description = "Monsters carry more treasure: +50% Chaos loot and an extra loot roll on every monster.",
			bonus = {loot = 1.5}},
		{id = "towerascension", name = "Tower Ascension", monthdays = {1, 2, 3, 15, 16, 17}, colorlight = "#2f9fd0", colordark = "#145470",
			description = "The Infinity Tower calls: double tower points for every floor cleared.",
			bonus = {towerPoints = 2.0}}
	},
	-- how many days of the calendar are sent to the client (from the first day of the current month)
	calendarDays = 62,
	announceOnLogin = true
}

-- World boss event (worldboss.lua). Monster XMLs: data/monster/monsters/chaos/world_bosses/ (register them with
-- tools/register_monsters.py). Times are server local time. See server/README.md "World bosses".
Chaos.worldBoss = {
	enabled = true, -- automatic schedule (the GM command works either way)
	-- starts at every hour h with (h - offsetHours) % intervalHours == 0, minute 0: 03:00, 09:00, 15:00, 21:00
	intervalHours = 6,
	offsetHours = 3,
	warnMinutes = {10, 5, 1}, -- broadcasts before a scheduled start
	mode = "rotation", -- "rotation" (next boss each time) or "random" (never the same twice in a row)
	gatherSeconds = 120, -- portals open, boss appears after this
	portalMinutes = 30, -- town portals stay this long (or until the boss dies)
	fightMinutes = 45, -- the boss leaves this long after it appeared (event failed)
	exitDelaySeconds = 90, -- after the end: time to loot before everyone is sent to their temple
	minLevel = 300,
	maxPlayers = 40, -- players inside lobby + arena at once (0 = no limit)
	-- instance limits (instance_limits.lua, server/README.md "Instance limits"): warnings to everyone inside at warnAt
	-- seconds before the boss withdraws (fightMinutes); one arena, one event at a time
	limits = {warnAt = {300, 60, 10}},
	allowPvp = false, -- no player-vs-player damage in the lobby and the arena
	-- multi-client characters (Chaos.isMultiClient) may enter and fight, but get no participation reward
	mcReward = false,

	-- arena: built at runtime with Game.createTile. Footprint x 5000..5032 (arena) and the lobby south of it,
	-- y 5000..5048, z 7. That part of the map has no tiles (checked in the map file; the script checks again
	-- before building and refuses to build over existing tiles).
	arena = {
		origin = {x = 5000, y = 5000, z = 7}, -- top-left wall corner of the arena
		inner = 31, -- inner width/height of the arena (odd, so there is a centre tile)
		lobbyGap = 7, -- empty (tile-less) rows between the arena's south wall and the lobby's north wall
		lobbyInnerW = 13, lobbyInnerH = 7,
		groundId = 407, -- black marble floor (arena)
		lobbyGroundId = 413, -- stone floor (lobby)
		wallId = 5648, -- stone wall
		pillarId = 1514, -- stone pillar (line-of-sight cover inside the arena)
		basinId = 1481, -- coal basin (light, lobby corners and arena corners)
		portalId = 1387, -- magic forcefield (type teleport in items.xml); used without destination + action id
		-- dark tile set (server/README.md "Dark tile set"): with the set installed, walls, pillars and lights use
		-- these and both rooms are painted (data/lib/chaos_dark_paint.lua styles); else the ids above are used
		dark = {enabled = true, wall = "dark_wall", pillar = "ruined_pillar", basin = "brazier",
			arenaStyle = "arena", lobbyStyle = "lobby"}
	},
	-- action ids of the forcefields (handled by MoveEvent onStepIn, never by the teleport destination, so monsters
	-- that step on them are not moved and the entry rules are checked)
	aid = {enter = 47201, arena = 47202, lobby = 47203, exit = 47204},
	-- town portals: next to every temple of Game.getTowns() (first free spot of portalOffsets), or exactly at
	-- portalPositions when that list is not empty. towns = {id, ...} limits the towns (nil = all).
	towns = nil,
	portalPositions = {},
	portalOffsets = {{2, 0}, {-2, 0}, {0, 2}, {0, -2}, {2, 2}, {-2, 2}, {2, -2}, {-2, -2}, {3, 0}, {-3, 0}},
	rotationStorage = 7100910, -- global storage (Game.setStorageValue, in memory): last boss index; resets on restart

	-- roles (worldboss.lua "role tracking"): what a player did in the fight, besides damage on the boss.
	--   healing: healing on OTHER players inside the arena while the boss is alive, effective only (capped at the
	--            target's missing health) and at most the boss damage the target took and was not healed for yet
	--   tanking: damage from the boss and its adds the player survived (a killing hit counts nothing), capped per hit,
	--            only while the player is active (attacked the boss or an add, or healed someone, within activeSeconds)
	-- contribution score = damage + healing x healWeight + tanking x tankWeight
	roles = {
		healWeight = 1.0, -- 1 health healed on someone else = 1 damage
		selfHealWeight = 0, -- healing yourself does not count (survival is already the tanking credit)
		tankWeight = 0.5, -- tanking overlaps with the healing that undoes it, so it counts half
		tankHitCap = 8000, -- per hit: the biggest designed boss hit (Nyxareth's rift beam)
		offTargetWeight = 0.5, -- hits from a boss or add that is not targeting you (area splash) count half
		activeSeconds = 30,
		titleDays = 7, -- role titles (reward.podium) are held this long after the fight
		titleStorage = 7100930, -- player storages 7100930-7100932: until when the damage/healing/tanking title is held
		boards = {healing = "bosshealer", tanking = "bosstank"} -- weekly boards (leaderboard_config.lua); nil = none
	},

	-- participation reward (everybody with a contribution score of at least minScorePercent % of the boss max health).
	-- share = own score / score of all eligible players. Delivered to the backpack, the rest to the inbox;
	-- players offline at the kill get it at their next login (kept in memory until a restart).
	reward = {
		minScorePercent = 0.25,
		bankGold = 500000, -- deposited into the bank for every eligible player
		bankGoldPool = 10000000, -- split by share, deposited into the bank
		base = {{id = 29856, count = 3}, {id = 29857, count = 1}}, -- Orbs of Upheaval, Orb of Fate for everyone
		pool = {{id = 29856, count = 60}, {id = 29857, count = 25}}, -- split by share (floor)
		gearChance = 1500, -- per 10000: one item of the boss gear list (rolled with rarity gearRarity)
		gearShareBonus = 3000, -- + share x this (a player with 20% of the score: +600)
		gearRarity = {5, 5}, -- min, max rarity of that item (stored ids; Legendary. It was {6, 9} of the 15: Exotic .. Eternal)
		uniqueChance = 50, -- per 10000: one of the boss-only uniques that list this boss (chaos_unique_items.lua)
		uniqueShareBonus = 300, -- + share x this
		-- the top `top` of each category (eligible players only; one player can place in several): rewards[place],
		-- an extra unique roll uniqueChance[place] per 10000 (one unique at most per player) and the role title.
		-- Ties: who reached the value first places higher. A value under placeMinPercent % of the boss max health
		-- does not place.
		podium = {
			top = 3,
			placeMinPercent = 0.1,
			categories = {
				{key = "damage", name = "Damage", title = "Bossbreaker", color = "#f08a4b",
					rewards = {
						{{id = 29857, count = 5}, {id = 2160, count = 50}},
						{{id = 29857, count = 3}, {id = 2160, count = 30}},
						{{id = 29857, count = 2}, {id = 2160, count = 20}}
					},
					uniqueChance = {300, 200, 100}},
				{key = "healing", name = "Healing", title = "Lifewarden", color = "#6fd8a8",
					rewards = {
						{{id = 29857, count = 5}, {id = 2160, count = 50}},
						{{id = 29857, count = 3}, {id = 2160, count = 30}},
						{{id = 29857, count = 2}, {id = 2160, count = 20}}
					},
					uniqueChance = {300, 200, 100}},
				{key = "tanking", name = "Tanking", title = "Bulwark", color = "#9fb4cc",
					rewards = {
						{{id = 29857, count = 5}, {id = 2160, count = 50}},
						{{id = 29857, count = 3}, {id = 2160, count = 30}},
						{{id = 29857, count = 2}, {id = 2160, count = 20}}
					},
					uniqueChance = {300, 200, 100}}
			}
		}
	},

	-- the five bosses. adds: {name, count, health}; phases trigger once when health falls to `at` (fraction).
	-- enrage: from that phase on, `pulse` hits every player within radius every `every` seconds.
	bosses = {
		{name = "Kaelgor the Infernal Warlord", element = "fire",
			intro = "Kaelgor the Infernal Warlord marches out of the burning rift!",
			phases = {
				{at = 0.70, adds = {name = "Hellfire Fighter", count = 4, health = 150000}, yell = "LEGION, TO ME!"},
				{at = 0.40, enrage = true, yell = "I WILL BURN THIS WORLD TO THE GROUND!"},
				{at = 0.15, adds = {name = "Hellspawn", count = 4, health = 150000}, yell = "My guard dies before I do!"}
			},
			pulse = {type = "fire", min = 2500, max = 4000, radius = 6, every = 8, effect = "explosionarea"},
			gear = {29878, 29879, 29880, 29881, 29882, 29883, 29884, 29885, 29890}},
		{name = "Skaldra the Rime Queen", element = "ice",
			intro = "The sky freezes over: Skaldra the Rime Queen descends!",
			phases = {
				{at = 0.70, adds = {name = "Frost Dragon", count = 3, health = 200000}, yell = "My brood, wake!"},
				{at = 0.40, enrage = true, yell = "THE LONG WINTER BEGINS!"},
				{at = 0.15, adds = {name = "Ice Golem", count = 4, health = 120000}, yell = "Shards, protect your queen!"}
			},
			pulse = {type = "ice", min = 2000, max = 3500, radius = 7, every = 7, effect = "giantice"},
			gear = {29869, 29870, 29871, 29872, 29873, 29874, 29875, 29876, 29877}},
		{name = "The Rotmother", element = "earth",
			intro = "The ground splits and the Rotmother crawls out of the plague pits!",
			phases = {
				{at = 0.75, adds = {name = "Defiler", count = 5, health = 120000}, yell = "Children, feed!"},
				{at = 0.50, adds = {name = "Plaguesmith", count = 4, health = 150000}, yell = "More! I need MORE!"},
				{at = 0.25, enrage = true, yell = "BREATHE ME IN!"}
			},
			pulse = {type = "earth", min = 1500, max = 2500, radius = 8, every = 6, effect = "greensmoke"},
			gear = {29863, 29867, 29871, 29872, 29880, 29881}},
		{name = "Nyxareth the Void Archon", element = "death",
			intro = "Reality tears: Nyxareth the Void Archon steps out of the void!",
			phases = {
				{at = 0.70, adds = {name = "Phantasm", count = 4, health = 100000}, yell = "Echoes, consume them."},
				{at = 0.40, enrage = true, yell = "THE VOID OPENS!"},
				{at = 0.15, adds = {name = "Lost Soul", count = 4, health = 100000}, yell = "Your dead serve me now."}
			},
			pulse = {type = "death", min = 2500, max = 4000, radius = 7, every = 7, effect = "mortarea"},
			gear = {29861, 29862, 29863, 29864, 29865, 29866, 29867, 29868}},
		{name = "Vharok the Blood Colossus", element = "physical",
			intro = "The earth trembles: Vharok the Blood Colossus awakens!",
			phases = {
				{at = 0.75, adds = {name = "Blood Beast", count = 4, health = 150000}, yell = "FEED ME!"},
				{at = 0.45, enrage = true, yell = "BLOOD FOR THE COLOSSUS!"},
				{at = 0.20, adds = {name = "Juggernaut", count = 3, health = 200000}, yell = "CRUSH THEM!"}
			},
			-- every player hit by the pulse heals Vharok by healPerHit
			pulse = {type = "physical", min = 2500, max = 4500, radius = 6, every = 7, effect = "groundshaker", healPerHit = 5000},
			gear = {29878, 29879, 29880, 29886, 29887, 29888, 29889, 29869}}
	}
}

-- Boosted creature / boss of the day (clientservices.lua). The reference server already picks both at
-- startup (global storages + boostedMonsterList / boostedBossesList); these lists are only the fallback
-- when that pick is missing or names a monster that does not exist.
Chaos.boosted = {
	creatures = {"Dragon", "Dragon Lord", "Giant Spider", "Hydra", "Behemoth", "Serpent Spawn", "Warlock", "Hero",
		"Nightmare", "Grim Reaper", "Frost Dragon", "Medusa", "Sea Serpent", "Wyrm", "Lost Soul"},
	bosses = {"Vhalkareth", "Morgashal", "Moloveth", "Vharagoth", "Ssylvath the Corruptor", "The Spawnmother"},
	storageCreature = 7100900, -- global storages for the fallback pick: index into the list above
	storageBoss = 7100901,
	storageDay = 7100902 -- YYYYMMDD of the fallback pick
}

-- Store services (shop_services.lua, autosell.lua). Prices and the offers themselves are in shop_config.lua.
Chaos.shopServices = {
	maxStamina = 2520, -- minutes (42 h), what the stamina service restores to (the Stamina Refill offer was removed 2026-10-15)

	-- Temple Teleport Scroll: an ordinary "scroll" item (6119, no other script uses it) with this action id and a
	-- custom name/description; the uses left are kept in the item's custom attribute "chaos_uses".
	templeScroll = {itemId = 6119, actionId = 47301, name = "temple teleport scroll", cooldown = 2},

	-- World buffs: one purchase adds `minutes`; buying while active extends it, never beyond `capMinutes` left
	-- (a purchase that would pass the cap is refused, no coins taken). Expiry times are global storages
	-- (globalStorage + index) and are also written to the server_config table, so they survive /reload and a
	-- restart.
	worldBuffs = {
		{id = "xp", name = "World Experience", bonus = 0.25, minutes = 60, capMinutes = 180,
			text = "+25% experience from monsters for every standard character"},
		{id = "loot", name = "World Loot", bonus = 0.25, minutes = 60, capMinutes = 180,
			text = "+25% Chaos loot (extra loot rolls and currency drops) for every standard character"},
		{id = "skill", name = "World Training", bonus = 0.25, minutes = 60, capMinutes = 180,
			text = "+25% skill and magic level training for every standard character"},
		-- monster_tiers.lua: the spawn chance of magic and rare monsters x (1 + bonus), everywhere (beta 2026-10-22)
		{id = "hunt", name = "World Hunt", bonus = 0.5, minutes = 60, capMinutes = 180,
			text = "Magic and rare monsters appear 50% more often, everywhere"}
	},
	worldBuffStorage = 7100920, -- global storages 7100921.. (expiry unix time per buff, in list order)
	worldBuffConfigKey = "chaos_worldbuff_", -- server_config rows chaos_worldbuff_<id>

	-- Name change rules (ChaosShopServices.validateName)
	name = {
		minLength = 3, maxLength = 20, maxWords = 3, minWordLength = 2,
		-- a first word (or any word) that is one of these is refused: staff look-alikes
		staffWords = {"gm", "cm", "god", "admin", "adm", "tutor", "gamemaster", "staff", "support", "owner", "sr", "senior", "server",
			"tester"}, -- tester: the staff's tester bots are "Tester Xxx" (server/README.md "Tester bots")
		-- refused anywhere in the name (lower case, substring match); extend as needed
		forbidden = {"admin", "gamemaster", "moderator", "fuck", "shit", "bitch", "whore", "nazi", "hitler", "cunt", "rape"},
		-- refused as the whole name: the website's top-level addresses (website/README.md "Web server": /highscores is
		-- a page, so a character named Highscores could not be reached there). The same list as the website's
		-- chaos_reserved_character_names() (website/overlay/engine/function/chaos_character.php; a test compares them)
		reserved = {
			"achievements", "auctionchar", "bans", "blank", "buypoints", "changelog", "changepassword", "characterprofile",
			"config", "contact", "createcharacter", "creatures", "credits", "deaths", "downloads", "failed", "faq", "forum",
			"gallery", "guilds", "guildwar", "helpdesk", "highscores", "house", "houses", "index", "ipn", "items", "killers",
			"login", "logout", "mailtest", "market", "myaccount", "onlinelist", "page", "payment", "powergamers", "protected",
			"queststatus", "recovery", "register", "serverinfo", "settings", "shop", "spells", "sub", "success", "support",
			"team", "topguilds", "toponline", "twofa", "twtrnews", "voting",
			"admin", "api", "assets", "cache", "docker", "engine", "install", "landing", "layouts", "locale", "lua", "plugins",
			"special", "sql", "tests", "tools", "updates", "vendor", "clientservices"
		}
	},

	-- Vocation change: command word -> {base id, ascended id} (data/XML/vocations.xml, docs/CLASSES.md). An ascended
	-- character gets the ascended id of the new class, an unascended one the base id.
	-- Every base class has two ascended classes (Chaos.classes.ascension): the ascended words name the base too, and the
	-- base word carries `choose`: an ascended character must name the ascended class it wants
	-- (!changevocation berserker), an unascended one becomes the base class with any word of the line.
	vocations = {
		warrior = {4, 8, choose = {"juggernaut", "berserker"}},
		juggernaut = {4, 8},
		berserker = {4, 14},
		ranger = {3, 7, choose = {"deadeye", "beastmaster"}},
		deadeye = {3, 7},
		beastmaster = {3, 15},
		mystic = {1, 5, choose = {"elementalist", "illusionist"}},
		elementalist = {1, 5},
		illusionist = {1, 10},
		thief = {11, 12, choose = {"ninja", "samurai"}},
		ninja = {11, 12},
		samurai = {11, 13},
		monk = {17, 18, choose = {"shadowfist", "ironsage"}},
		shadowfist = {17, 18},
		ironsage = {17, 19},
		necromancer = {20, 21, choose = {"lich", "bonelord"}},
		lich = {20, 21},
		bonelord = {20, 22},
		templar = {23, 24, choose = {"inquisitor", "sentinel"}},
		inquisitor = {23, 24},
		sentinel = {23, 25}
	},
	-- the word list players see (!changevocation, the store's notices)
	vocationWords = "warrior|juggernaut|berserker|ranger|deadeye|beastmaster|mystic|elementalist|illusionist|thief|ninja|samurai"
		.. "|monk|shadowfist|ironsage|necromancer|lich|bonelord|templar|inquisitor|sentinel",
	vocationBaseLevel = 8, -- health/mana/capacity gains are counted from this level (as the engine does)

	-- Auto Seller
	autosellSlots = 40,
	-- blessings of the "All Blessings" offer (base server: 1-5, see creaturescripts login.lua)
	blessings = {1, 2, 3, 4, 5}
}

-- Client services: the login screen asks an HTTP endpoint (client/tools or server/tools/clientservices.py)
-- for the boosted creature/boss, the event calendar and the players online. The game server writes what
-- that endpoint serves into this JSON file (path relative to the server folder).
Chaos.clientServices = {
	file = "data/chaos_clientservices.json",
	refreshSeconds = 300
}

-- Party Finder (LFG) window (client game_partyfinder; party_finder.lua, party_finder_core.lua, party_finder_config.lua)
ChaosOpcodes.partyFinder = 208

-- Level-up wings: golden wings open behind a character that gains a level, server -> client to every player who sees
-- it (client game_levelwings; levelwings.lua, levelwings_core.lua, levelwings_config.lua); no storages, no tables
ChaosOpcodes.levelWings = 191

-- Death recap: who killed the character, with what and how fast; the last 5 deaths per character (client
-- game_deathrecap; deathrecap.lua, deathrecap_core.lua, deathrecap_config.lua, sql/chaos_death_recaps.sql; fed by the
-- combat log's damage-taken hook in combatlog.lua). No player storages.
ChaosOpcodes.deathRecap = 154
Chaos.tables.deathRecaps = "chaos_death_recaps"

-- Progress metrics: anonymous aggregate counters for balancing (metrics.lua, metrics_core.lua, metrics_config.lua,
-- sql/chaos_progress_metrics.sql; read by chaos-ctl.sh metrics). No opcode. Storage 7102830 - 7102839 reserved (metrics_config.lua)
Chaos.tables.progressMetrics = "chaos_progress_metrics"

-- Nemesis: a monster that kills a character may become its personal nemesis (client game_nemesis; nemesis.lua,
-- nemesis_core.lua, nemesis_config.lua, sql/chaos_nemesis.sql). 163 is free in the reference server, the base client
-- and every Chaos module. Storages 7102300 - 7102309 reserved (nemesis_config.lua storage)
ChaosOpcodes.nemesis = 163
Chaos.tables.nemesis = "chaos_nemesis"
Chaos.storage.nemesis = 7102300

-- Next Goals: the goals of every character's level band, the gear path, the hunts and the on-screen tracker (client
-- game_goals; goals.lua, goals_core.lua, goals_config.lua, sql/chaos_goals.sql). 178 is free in the reference server,
-- the base client and every Chaos module. No player storages.
ChaosOpcodes.goals = 178
Chaos.tables.goals = "chaos_goals"

-- Card borders: the cards that are ON, server -> client (client game_cardborder; cards.lua, cards_core.lua K.state; server/README.md
-- "Cards and decks"). 172 is free in the reference server, the base client and every Chaos module. No storage, no table.
ChaosOpcodes.cardState = 172

-- Ember Cache, Daily Spark and the day book: points from every activity, a daily Spark, three weekly milestones, what
-- the character did today (client game_embercache; embercache.lua, embercache_core.lua, daybook_core.lua,
-- embercache_config.lua). 174 is free in the reference server, the base client and every Chaos module. Storages
-- 7102700 - 7102719 (the cache) and 7102720 - 7102739 (the day book), embercache_config.lua; no tables.
ChaosOpcodes.emberCache = 174
Chaos.storage.emberCache = 7102700
Chaos.storage.daybook = 7102720
-- Gentle deaths (gentledeath.lua, gentledeath_config.lua): storages 7102740 - 7102744
Chaos.storage.gentleDeath = 7102740
-- Tutorial reset (newplayer_core.lua NP.takeSnapshot / NP.tutorialReset): the character as it was when the tutorial
-- island began, put back when it leaves. Storages 7102750 - 7102779 (NP.SNAP)
Chaos.storage.tutorialSnapshot = 7102750

-- Classes (docs/CLASSES.md). Logic in classes.lua (ChaosClasses), the ascension in ascension.lua, the migration of the
-- old vocations in class_migration.lua, the combat mechanics in thief_combat.lua (Thief line), berserker_combat.lua (Rage,
-- Bloodrage) and beastmaster.lua (the companion), the spells in data/spells/chaos/<class>/.
Chaos.classes = {
	-- vocation ids (server/data/XML/chaos_vocations.xml, installed by server/tools/add_vocations.py). Ids that map 1:1
	-- keep the old number (4 Knight -> Warrior, 8 Elite Knight -> Juggernaut, 3 Paladin -> Ranger, 7 Royal Paladin ->
	-- Deadeye, 1 Sorcerer -> Mystic, 5 Master Sorcerer -> Elementalist, 10 Arch Illusionist -> Illusionist), so items,
	-- spells, NPCs and the database keep working; 2, 6 and 9 are retired (class_migration.lua moves them).
	ids = {
		mystic = 1, ranger = 3, warrior = 4, elementalist = 5, deadeye = 7, juggernaut = 8, illusionist = 10,
		thief = 11, ninja = 12, samurai = 13, berserker = 14, beastmaster = 15,
		-- classes five to seven, behind the store's class unlock (class_unlocks.lua); each line's own ids are in
		-- ChaosMonk.ids (monk_chi_core.lua), necro_config.lua and ChaosTemplar.cfg.ids (templar_aura_core.lua)
		monk = 17, shadowfist = 18, ironsage = 19,
		necromancer = 20, lich = 21, bonelord = 22,
		templar = 23, inquisitor = 24, sentinel = 25
	},
	-- base class of every class (the line)
	baseOf = {[1] = 1, [5] = 1, [10] = 1, [3] = 3, [7] = 3, [15] = 3, [4] = 4, [8] = 4, [14] = 4, [11] = 11, [12] = 11, [13] = 11,
		[17] = 17, [18] = 17, [19] = 17, [20] = 20, [21] = 20, [22] = 20, [23] = 23, [24] = 23, [25] = 23},
	-- the engine knows one promotion per vocation; the choice between two ascended classes is this script's
	ascension = {
		minLevel = 100,
		needProtectionZone = true,
		-- base vocation id -> {command word -> ascended vocation id}
		choices = {
			[4] = {juggernaut = 8, berserker = 14},
			[3] = {deadeye = 7, beastmaster = 15},
			[1] = {elementalist = 5, illusionist = 10},
			[11] = {ninja = 12, samurai = 13},
			[17] = {shadowfist = 18, ironsage = 19},
			[20] = {lich = 21, bonelord = 22},
			[23] = {inquisitor = 24, sentinel = 25}
		}
	},
	-- one-time migration of the old vocations (class_migration.lua). Runs once at startup (version in server_config),
	-- then tells each character at its next login what happened.
	migration = {
		version = 1,
		configKey = "chaos_class_migration",
		-- old vocation id -> new vocation id (ids not listed keep their number)
		map = {[2] = 1, [6] = 10, [9] = 1},
		-- the passive trees of these old vocations are emptied once, for free
		resetTree = {1, 2, 3, 4, 5, 6, 7, 8, 9, 10},
		-- old ascended vocation -> the other ascended class it may switch to once, for free (!ascend <word>)
		freeSwitch = {[8] = 14, [7] = 15},
		-- health / mana / capacity gains per level of the retired vocations (their vocations.xml entries are gone)
		oldGains = {[2] = {hp = 5, mana = 30, cap = 1000}, [6] = {hp = 5, mana = 30, cap = 1000}, [9] = {hp = 6, mana = 22, cap = 1200}},
		-- names for the login message
		oldNames = {[1] = "Sorcerer", [2] = "Druid", [3] = "Paladin", [4] = "Knight", [5] = "Master Sorcerer",
			[6] = "Elder Druid", [7] = "Royal Paladin", [8] = "Elite Knight", [9] = "Illusionist", [10] = "Arch Illusionist"}
	},
	-- class outfits, by vocation id (client pair outfits 1505-1510: client/tools/sprites/import_outfits.py; 1551-1560: the
	-- donor B first set, import_donor_things.py; added to data/XML/outfits.xml for both sexes by
	-- server/tools/install_outfits.py). The class's list is given at a class change (ascension.lua puts on the first one
	-- when the character had none of them) and at login; outfits stay after a later class change. Names must be unique
	-- and match outfits.xml.
	-- Retired donor art class outfits: no longer given (at a login or a class change). install_outfits.py keeps their
	-- outfits.xml line under this name, so the characters that own one can still wear it; the store never sells them
	-- (gen_shop_cosmetics.py, shop.lua). 1559 "Archmage" (donor B 3099, the Mystic line's), retired 2026-10-16: a
	-- front-view 3x3 figure without colours, addons or riding frames that does not match the player looks.
	retiredOutfits = {
		{lookType = 1559, name = "Archmage (old)"}
	},
	-- The Mystic line's replacement Archmage: client pair 29 (outfits 2235 male / 2236 female, our own rig art,
	-- client/tools/outfit_art/class_art_line.py `archmage`, owner-approved 2026-10-16). `enabled` is the pair 29 switch:
	-- off until the clients have pair 29, nothing names the look then. On, it joins the class outfits of `vocations`
	-- with both addons (ChaosClasses.classOutfitsFor: the look of the character's sex), and a character of those
	-- vocations wearing `replaces` (or the other sex's Archmage) is moved to it at its next login
	-- (ChaosClasses.outfitSwap). Keep `enabled` one plain line: install_outfits.py and gen_shop_cosmetics.py read it.
	outfitReplacement = {
		enabled = true,
		vocations = {1, 5, 10},
		replaces = 1559,
		outfit = {lookType = 2235, female = 2236, name = "Archmage", addons = 3}
	},
	outfits = (function()
		local O = {
			warrior = {lookType = 1551, name = "Warborn"},
			thief = {lookType = 1556, name = "Hooded Thief"},
			ninja = {{lookType = 1505, name = "Shadow Ninja"}, {lookType = 1506, name = "Crimson Ninja"},
				{lookType = 1507, name = "Masked Ninja"}, {lookType = 1555, name = "Nightblade"}},
			samurai = {{lookType = 1508, name = "Oni Samurai"}, {lookType = 1509, name = "Ronin"},
				{lookType = 1510, name = "Dark Samurai"}, {lookType = 1554, name = "Wandering Blade"}},
			ranger = {lookType = 1558, name = "Wildwood Ranger"},
			monk = {lookType = 1557, name = "Brawler"},
			necromancer = {lookType = 1560, name = "Plague Doctor"},
			templar = {lookType = 1552, name = "Golden Templar"},
			seraph = {lookType = 1553, name = "Seraph"}
		}
		local function list(...)
			local out = {}
			for _, part in ipairs({...}) do
				if part.lookType then
					out[#out + 1] = part
				else
					for _, o in ipairs(part) do
						out[#out + 1] = o
					end
				end
			end
			return out
		end
		return {
			[4] = list(O.warrior), [8] = list(O.warrior), [14] = list(O.warrior),
			[11] = list(O.thief), [12] = list(O.ninja, O.thief), [13] = list(O.samurai, O.thief),
			[3] = list(O.ranger), [7] = list(O.ranger), [15] = list(O.ranger),
			-- the Mystic line (1, 5, 10) has no donor art outfit since 1559 was retired (retiredOutfits, outfitReplacement)
			[17] = list(O.monk), [18] = list(O.monk), [19] = list(O.monk),
			[20] = list(O.necromancer), [21] = list(O.necromancer), [22] = list(O.necromancer),
			[23] = list(O.templar), [24] = list(O.seraph, O.templar), [25] = list(O.seraph, O.templar)
		}
	end)(),
	storage = {
		dualWield = 7100200, -- 1 while the character may hold an off-hand sword (read by server/src-patches/0002)
		ascended = 7100201, -- os.time of the ascension (information only)
		migratedFrom = 7100202, -- the old vocation id until the login message of the migration was shown, then 0
		freeSwitch = 7100203, -- the ascended vocation id a migrated character may still switch to for free (!ascend)
		offhandGranted = 7100204 -- os.time of the one-time off-hand dagger of a Thief made before dual wield (classes.lua offhandGrant)
	},
	-- condition sub ids of the class buffs (CONDITIONID_COMBAT). The spells and the combat scripts run in different
	-- Lua states; the conditions are the state both see. Stealth is CONDITION_INVISIBLE, the others
	-- CONDITION_ATTRIBUTES without attributes (a timer). Next to ChaosSpell.SUBID (71001-71009).
	subId = {stealth = 71010, poisonBlades = 71011, counter = 71012, bushido = 71013, bloodrage = 71014},
	-- the new lines keep their sub ids in their own config: Necromancer 71020-71023 (necro_config.lua), Monk
	-- 71030-71044 (monk_chi_core.lua), Templar 71050-71052 (templar_aura_core.lua)
	-- Shadow Veil: monsters drop the player as a target and cannot pick it; attacking or being hit ends it
	stealth = {
		durationMs = 4000,
		pulseMs = 200, -- how often monsters around are made to drop the player
		radius = 8,
		ambushMultiplier = 2.0 -- the first weapon hit out of stealth is a critical hit
	},
	-- Evasion: chance to dodge a melee or ranged hit (monster or player weapon attacks), per vocation id
	evasion = {[11] = 0.08, [12] = 0.12, [13] = 0.05},
	-- Poison Blades: weapon hits poison the target, `share` of the hit as earth damage over `ticks` seconds. A hit
	-- refreshes the poison (the condition is replaced, the tick clock runs on), so a class that hits every 1-2 s takes one
	-- tick of the last hit per second: the poison deals about share / ticks of a hit per second. 2026-10-17 (owner:
	-- "O poison do thief é muito fraco"): share 0.6 -> 1.2 (a tick of 15% of the hit became 30%); classScale
	-- multiplies it per vocation, the Ninja only x0.6 (0.72, +20%) so that the Deadeye keeps its lead on one target
	-- (server/data/spells/README.md "Thief poison")
	poisonBlades = {durationMs = 20000, share = 1.2, ticks = 4, tickMs = 1000, classScale = {[12] = 0.6}},
	-- Ninja dual wield: each main-hand weapon hit adds an off-hand strike of `share` of the hit, scaled by the
	-- off-hand weapon's attack against the main hand's (clamped to minRatio..maxRatio)
	-- Thief and Ninja (`vocations`) dual wield. `neutral`: the Thief's main hit is cut by 1 / (1 + share x ratio) so that
	-- a swing of two daggers deals what one dagger swing did before the Thief dual wielded (2026-10-23, server/data/spells/
	-- README.md "Thief dual wield and attack speed"); the Ninja, who always dual wielded, is not cut
	dualWield = {share = 0.5, minRatio = 0.5, maxRatio = 1.25, delayMs = 150, vocations = {[11] = true, [12] = true},
		neutral = {[11] = true}},
	-- Attack interval in ms (the `attackspeed` of chaos_vocations.xml), `was` -> `now` (2026-10-23, owner: the Thief
	-- attacks as fast as the Monk, 1500; the ascended classes tie with the Monk line's: Ninja = Shadowfist 1300,
	-- Samurai = Iron Sage 1700). The weapon hits of these vocations are scaled by was / now so that the damage per
	-- second of the auto attack stays where it was measured (classes.lua speedComp; every other vocation 2000, unchanged)
	attackSpeed = {[11] = {was = 1600, now = 1500}, [12] = {was = 1400, now = 1300}, [13] = {was = 1800, now = 1700}},
	-- a Thief made before dual wield gets the missing second dagger once (storage `offhandGranted`)
	offhandGrant = {itemId = 2379},
	-- Samurai Counter Stance (the duelist off-tank, docs/CLASSES.md): the next melee hit taken within windowMs is parried
	-- (no damage) and answered with a strike of `multiplier` x the parried hit; while the stance lasts every other hit
	-- taken is `guard` smaller; the cast taunts the monsters within tauntRadius sqm
	counter = {windowMs = 3000, multiplier = 1.5, guard = 0.30, tauntRadius = 3},
	-- Samurai Bushido Focus: while the buff lasts, every second without taking damage adds a stack;
	-- each stack is +perStack critical chance on weapon hits and Iaijutsu, a critical hit does critMultiplier
	bushido = {durationMs = 30000, stackMs = 1000, perStack = 0.03, maxStacks = 10, startStacks = 3, critMultiplier = 1.5},
	-- Shadow Mend (spell 98, `saen umh`): the line's self heal. Restores level x perLevel + magic level x perMagicLevel +
	-- maxHealthShare of the maximum health (+-spread); x veiledMultiplier while Shadow Veil is up (healing does not end
	-- the veil). Below the Illusionist and near the Ranger line: server/data/spells/README.md "Healing"
	shadowMend = {perLevel = 0.5, perMagicLevel = 20, maxHealthShare = 0.05, veiledMultiplier = 1.3, spread = 0.1},
	-- shurikens: the attack a shuriken spell uses (stackable throwing weapons left the game, owner 2026-10-20: no star is
	-- needed or carried; a one-handed distance weapon in hand still raises it, ChaosSpell.shurikenPower)
	shuriken = {defaultAttack = 50},
	-- (spellLevelScale, the level factor of the line's spell strikes, stood in for the passive tree until the class trees
	-- of phase 2b; dropped: the tree and class_tree.lua classDamage scale the line now)
	-- Berserker Rage (passive): every damage the Berserker deals gets up to +maxBonus, growing linearly from 0 at full
	-- health to maxBonus at `fullBelow` of the maximum health and below
	rage = {maxBonus = 0.30, fullBelow = 0.30},
	-- Bloodrage (spell): costs `healthCost` of the current health; for durationMs weapon hits also strike up to
	-- maxTargets other enemies next to the Berserker for `cleave` of the hit, and Rage gets +bonus on top
	bloodrage = {durationMs = 12000, healthCost = 0.10, cleave = 0.4, maxTargets = 4, bonus = 0.10, delayMs = 100},
	-- Beastmaster companion: a real monster type (the first of `monsters` that exists), summoned by Wild Bond.
	-- Health base + perLevel x level; a bite every biteMs on the owner's target when next to it, physical damage
	-- dealt as the owner: avg = level x biteLevel + distance skill x biteSkill, min/max = avg x (1 -/+ spread).
	-- Feral Command: every companion leaps to the target and mauls it for mauls x a bite.
	companion = {
		monsters = {"War Wolf", "Wolf"},
		caps = {{level = 0, count = 1}, {level = 400, count = 2}},
		health = {base = 500, perLevel = 15},
		biteMs = 2000, biteLevel = 0.12, biteSkill = 0.6, spread = 0.2,
		mauls = 1.5,
		leashRange = 7, -- a companion farther than this from its owner (or on another floor) is brought back
		thinkMs = 500
	}
}

-- ---------------------------------------------------------------------------
-- Shared helpers
-- ---------------------------------------------------------------------------

-- Decode a JSON buffer; returns a table or nil (never throws).
-- Multi-client: how many characters one IP may have online, and who is exempt (group id, 1 = player).
-- A character with another character online from the same IP is "multi-clienting": it cannot enter dungeons or
-- the Infinity Tower and cannot attack players (multiclient.lua, dungeons.lua, infinitytower_run.lua and
-- data/spells/chaos/_common.lua ChaosSpell.canAttack, which repeats the check in the spells' Lua state).
Chaos.multiClient = {
	maxPerIp = 2,
	exemptGroup = 4, -- group id from which on (gamemasters, gods) the limit and the blocks do not apply
	msgDungeon = "You cannot enter while another character from your connection is online.",
	msgPvp = "You cannot attack players while another character from your connection is online.",
	-- global storage: 1 turns the multi-client blocks off (events, tests); the login limit stays
	offStorage = 7100990,
}

-- other online characters sharing this player's IP (IP 0 = no connection, never matches)
function Chaos.mcSiblings(player)
	local list = {}
	local ip = player:getIp()
	if ip == 0 or player:getGroup():getId() >= Chaos.multiClient.exemptGroup
			or Game.getStorageValue(Chaos.multiClient.offStorage) == 1 then
		return list
	end
	for _, other in ipairs(Game.getPlayers()) do
		if other ~= player and other:getIp() == ip then
			list[#list + 1] = other
		end
	end
	return list
end

function Chaos.isMultiClient(player)
	return #Chaos.mcSiblings(player) > 0
end

-- Nesting limit for every json.decode (O220). The base decoder (data/lib/core/json.lua) recurses once per `[` or `{`
-- with no limit: a 16 KB request of nothing but `[` is 16,000 levels deep, which costs a stack overflow error per
-- packet (and in an unprotected base handler a Lua error in the server log). Real messages nest 2-6 levels.
-- Chaos.jsonDepthOk is a scan (strings skipped, nothing allocated), Chaos.guardJson wraps json.decode with it once.
Chaos.jsonMaxDepth = 32

function Chaos.jsonDepthOk(text, limit)
	if type(text) ~= "string" then
		return true
	end
	limit = limit or Chaos.jsonMaxDepth
	local find, byte = string.find, string.byte
	local depth, pos = 0, 1
	while true do
		local i = find(text, '[%[%]{}"]', pos)
		if not i then
			return true
		end
		local c = byte(text, i)
		if c == 34 then -- a string: to its closing quote, skipping escaped characters
			local j = i + 1
			while true do
				local k = find(text, '["\\]', j)
				if not k then
					return true -- unterminated: the decoder refuses it
				end
				if byte(text, k) == 92 then
					j = k + 2
				else
					pos = k + 1
					break
				end
			end
		elseif c == 91 or c == 123 then
			depth = depth + 1
			if depth > limit then
				return false
			end
			pos = i + 1
		else
			if depth > 0 then
				depth = depth - 1
			end
			pos = i + 1
		end
	end
end

-- json.decode refuses text nested over Chaos.jsonMaxDepth with the error "json nested too deeply" (a pcall'd decode
-- sees it as any other bad JSON). Wraps once; a reload of this file does not wrap the wrapper again.
function Chaos.guardJson()
	if type(json) ~= "table" or type(json.decode) ~= "function" or Chaos.jsonGuarded == json.decode then
		return false
	end
	local raw = json.decode
	local function guarded(text, ...)
		if not Chaos.jsonDepthOk(text) then
			error("json nested too deeply", 2)
		end
		return raw(text, ...)
	end
	json.decode = guarded
	Chaos.jsonGuarded = guarded
	return true
end
Chaos.guardJson()

function Chaos.decode(buffer)
	if type(buffer) ~= "string" or buffer == "" then
		return nil
	end
	local ok, decoded = pcall(json.decode, buffer)
	if ok and type(decoded) == "table" then
		return decoded
	end
	return nil
end

-- Send {"action": action, "data": data} on an extended opcode.
function Chaos.send(player, opcode, action, data)
	if not player then
		return false
	end
	local payload = {action = action}
	if data ~= nil then
		payload.data = data
	end
	local buffer = json.encode(payload)
	if #buffer > Chaos.extendedOpcodeMax and Chaos.sendChunked then
		-- over the engine's 8192-byte string limit: sent in parts (the client side must listen with
		-- ProtocolGame.registerExtendedJSONOpcode, which joins them; a plain listener gets nothing, as before)
		-- named once per opcode and action, so a payload that is too big for what it carries can be found and trimmed
		Chaos.bigSendNamed = Chaos.bigSendNamed or {}
		local key = tostring(opcode) .. ":" .. tostring(action)
		if not Chaos.bigSendNamed[key] then
			Chaos.bigSendNamed[key] = true
			print("[Chaos] extended opcode " .. tostring(opcode) .. " action '" .. tostring(action) .. "' is " .. #buffer ..
				" bytes: sent in parts (reduce what it carries if it is sent often)")
		end
		return Chaos.sendChunked(player, opcode, buffer)
	end
	player:sendExtendedOpcode(opcode, buffer)
	return true
end

-- Creature events that an onTargetCombat callback puts on a monster stay on it until it dies, but the callbacks run for
-- every target of every hit (area spells: every monster in the area), and Creature:registerEvent looks the event up by
-- name each time. Chaos.registerOnce(creature, name) calls it once per monster and event: monster ids are never reused
-- while the server runs. A player is registered at every call (a player keeps its id across logins, its events do not).
-- Chaos.eventKnown(creature, name): true when registerOnce already put that event on this monster (callbacks check it
-- before a costly condition). The memo starts over past Chaos.registerMemoMax monsters (they get registered once more).
Chaos.registerMemoMax = 50000
local registerMemo, registerMemoSize = {}, 0

function Chaos.eventKnown(creature, name)
	local set = registerMemo[name]
	return set ~= nil and set[creature:getId()] == true
end

function Chaos.registerOnce(creature, name)
	local id = creature:getId()
	local set = registerMemo[name]
	if set and set[id] then
		return true
	end
	creature:registerEvent(name)
	if creature:isMonster() then
		if registerMemoSize >= Chaos.registerMemoMax then
			registerMemo, registerMemoSize, set = {}, 0, nil
		end
		if not set then
			set = {}
			registerMemo[name] = set
		end
		set[id] = true
		registerMemoSize = registerMemoSize + 1
	end
	return true
end

-- Chaos.containerBatch(player, fn, ...): runs fn(...) with the player's container updates held (engine patch 0054,
-- player:beginContainerBatch / endContainerBatch): every open window that changed gets one full container packet at the
-- end, and the stats one packet, instead of one packet and one client window refresh per item moved or removed (a Loot
-- Bag sale of 255 items: 510 packets before). The end runs even when fn fails; the error is raised again after it.
-- Without the patch (no such methods) fn just runs. Returns what fn returns.
local function batchDone(player, ok, ...)
	pcall(player.endContainerBatch, player)
	if not ok then
		error((...), 0)
	end
	return ...
end

function Chaos.containerBatch(player, fn, ...)
	if not player or type(player.beginContainerBatch) ~= "function" or type(player.endContainerBatch) ~= "function" then
		return fn(...)
	end
	player:beginContainerBatch()
	return batchDone(player, pcall(fn, ...))
end

-- Chaos.containerBurst(player, fn, ...): Chaos.containerBatch, and the player's container updates stay held for
-- Chaos.burstWindowMs after it (one outer batch, ended by a timer), so the kills of one burst (an area spell, a pack
-- dying in one tick, each with its own auto loot) end in ONE full container packet per open window instead of one per
-- corpse. The client answers every full packet for the open Loot Bag with a window refresh of up to 255 slots (owner
-- 2026-10-23: "o client dá uma travada rápida quando a janela do loot bag está aberta e o auto loot pega muita coisa
-- de uma vez"). Cost: a window shows the loot up to the window later (150 ms). The timer looks the player up again, so
-- a player gone by then is skipped; without the engine patch (no batch methods) fn just runs.
Chaos.burstWindowMs = 150
local burstHeld = {} -- [creature id] = true while the outer batch of that player is held

function Chaos.containerBurst(player, fn, ...)
	if not player or type(player.beginContainerBatch) ~= "function" or type(player.endContainerBatch) ~= "function"
		or type(addEvent) ~= "function" or type(Player) ~= "function" then
		return Chaos.containerBatch(player, fn, ...)
	end
	local id = player:getId()
	if not burstHeld[id] then
		player:beginContainerBatch()
		burstHeld[id] = true
		local okTimer = pcall(addEvent, function()
			burstHeld[id] = nil
			local p = Player(id)
			if p then
				pcall(p.endContainerBatch, p)
			end
		end, Chaos.burstWindowMs)
		if not okTimer then
			burstHeld[id] = nil
			pcall(player.endContainerBatch, player)
		end
	end
	return Chaos.containerBatch(player, fn, ...)
end

-- An extended opcode message (0x32, u8 opcode, u16 length, bytes) carries its payload as one string, and the engine's
-- NetworkMessage::addString silently refuses strings over 8192 bytes. The base Player.sendExtendedOpcode writes 0x32 and
-- the opcode before the string, so a longer payload left those two bytes alone in the packet: the client read the next
-- two bytes as the string length and dropped the rest of that network message ("parse message exception ... last opcode
-- is 0x32" at every admin login: the 20 KB admin catalog). extended_opcode.lua refuses such payloads (with a warning);
-- Chaos.sendChunked splits one into the parts "S..." (start), "P..." (part), "E..." (end) that the client's
-- ProtocolGame.registerExtendedJSONOpcode joins back together. A payload that fits goes out unchanged.
Chaos.extendedOpcodeMax = 8192
Chaos.extendedOpcodeChunk = 8000

function Chaos.splitExtended(buffer, size)
	buffer = tostring(buffer or "")
	if #buffer <= Chaos.extendedOpcodeMax then
		return {buffer}
	end
	size = math.min(size or Chaos.extendedOpcodeChunk, Chaos.extendedOpcodeMax - 1)
	local parts = {}
	for i = 1, #buffer, size do
		parts[#parts + 1] = buffer:sub(i, i + size - 1)
	end
	for i = 1, #parts do
		parts[i] = (i == 1 and "S" or (i == #parts and "E" or "P")) .. parts[i]
	end
	return parts
end

-- for client modules that listen with ProtocolGame.registerExtendedJSONOpcode (JSON payloads only)
function Chaos.sendChunked(player, opcode, buffer)
	if not player then
		return false
	end
	for _, part in ipairs(Chaos.splitExtended(buffer)) do
		if player:sendExtendedOpcode(opcode, part) == false then
			return false
		end
	end
	return true
end

-- Positive integer from client input, or nil. Beyond +-2^53 a number is no exact integer (1e308 stays a float, which
-- string.format("%d") refuses in Lua 5.3 and LuaJIT turns into -2^63): nil too (tests/opcode_fuzz_test.lua).
function Chaos.toInt(value, minimum, maximum)
	local n = tonumber(value)
	if not n or n ~= n or n > 9007199254740992 or n < -9007199254740992 then
		return nil
	end
	n = math.floor(n)
	if minimum and n < minimum then
		return nil
	end
	if maximum and n > maximum then
		return nil
	end
	return n
end

-- YYYYMMDD integer for a unix time (server local time).
function Chaos.dayKey(t)
	return tonumber(os.date("%Y%m%d", t or os.time()))
end

-- dayKey of the calendar day before `t`.
function Chaos.yesterdayKey(t)
	t = t or os.time()
	local d = os.date("*t", t)
	return Chaos.dayKey(os.time({year = d.year, month = d.month, day = d.day - 1, hour = 12}))
end

-- Run a SELECT and return an array of rows (each row is a table of column -> value).
-- `columns` is a list of {name, "n"|"s"} pairs.
function Chaos.select(query, columns)
	local rows = {}
	local resultId = db.storeQuery(query)
	if not resultId then
		return rows
	end
	repeat
		local row = {}
		for _, col in ipairs(columns) do
			if col[2] == "s" then
				row[col[1]] = result.getString(resultId, col[1])
			else
				row[col[1]] = result.getNumber(resultId, col[1])
			end
		end
		rows[#rows + 1] = row
	until not result.next(resultId)
	result.free(resultId)
	return rows
end

-- Give items to a player; returns how many were really added (handles partial / no room).
function Chaos.giveItem(player, itemId, count)
	local before = player:getItemCount(itemId)
	player:addItem(itemId, count, false)
	return player:getItemCount(itemId) - before
end

-- Resolve a player name to guid (online or offline). Returns guid, canonicalName or nil.
function Chaos.findPlayer(name)
	if type(name) ~= "string" or name == "" or #name > 29 then
		return nil
	end
	local online = Player(name)
	if online then
		return online:getGuid(), online:getName(), online
	end
	local resultId = db.storeQuery("SELECT `id`, `name` FROM `players` WHERE `name` = " .. db.escapeString(name) .. " LIMIT 1")
	if not resultId then
		return nil
	end
	local guid = result.getNumber(resultId, "id")
	local canonical = result.getString(resultId, "name")
	result.free(resultId)
	return guid, canonical, nil
end

-- Lazily load a data file that sits next to the scripts (guarded by the file itself).
function Chaos.load(fileName)
	return dofile("data/scripts/chaos/" .. fileName)
end

-- Heal a creature by `amount` (rounded down, at most what it is missing); returns the health it really gained.
-- This engine's Creature:addHealth takes (damage type, amount): a one-argument addHealth(amount) does nothing.
-- The second call covers the stock TFS signature (amount), where the first one does nothing; as in arena.lua.
function Chaos.heal(creature, amount)
	if not creature or type(amount) ~= "number" then
		return 0
	end
	local before = creature:getHealth()
	amount = math.min(math.floor(amount), creature:getMaxHealth() - before)
	if amount <= 0 then
		return 0
	end
	creature:addHealth("healing", amount)
	if creature:getHealth() == before then
		creature:addHealth(amount)
	end
	return creature:getHealth() - before
end

-- The base of a "share of the maximum health" hit on a player (rift ground and storms, raid and Ascended / guild boss
-- telegraphs): the maximum health, or for a Hollow Vessel health + maximum energy shield (archetypes.lua percentBase),
-- so its fixed 100 health is no way around them. Without the archetypes module: the maximum health.
function Chaos.percentBase(player)
	local A = ChaosArchetypes
	if A and A.percentBase then
		local ok, base = pcall(A.percentBase, player)
		if ok and type(base) == "number" then
			return base
		end
	end
	return player:getMaxHealth()
end

-- ---------------------------------------------------------------------------
-- Monster names
-- ---------------------------------------------------------------------------
-- Monster:rename (base engine) changes the name the clients see: the creature packet (look text, the monster bar,
-- battle list), the damage lines (its nameDescription) and our kill and loot lines. Rift monsters (rift_config.lua
-- looks.names) and invaders wear such names. What a monster IS stays its type: everything keyed on it (bestiary,
-- bounty, unique drops, pool levels, resistances, achievements, pets) uses Chaos.monsterTypeName.
function Chaos.monsterTypeName(creature)
	if not creature then
		return nil
	end
	local ok, name = pcall(function()
		local mt = creature:isMonster() and creature:getType()
		return mt and mt:name()
	end)
	if ok and type(name) == "string" and name ~= "" then
		return name
	end
	return creature:getName()
end

-- "an abyssal spawn" for a shown name; the monster files write their nameDescription the same way
function Chaos.nameDescriptionOf(name)
	local lower = tostring(name):lower()
	return (lower:find("^[aeiou]") and "an " or "a ") .. lower
end

-- what loot lines call a monster: its type's nameDescription, or the description of the name it was renamed to
function Chaos.monsterNameDescription(creature)
	local name = creature:getName()
	local ok, desc = pcall(function()
		local mt = creature:isMonster() and creature:getType()
		return mt and mt:name() == name and mt:getNameDescription() or nil
	end)
	if ok and desc then
		return desc
	end
	return Chaos.nameDescriptionOf(name)
end

-- Game.createMonster under a shown name. The name is set in onSpawn, before the placement (callback in
-- monster_tiers.lua, index -100, so it runs first), so the first creature packet already carries it: a rename after the
-- placement does not reach clients that know the creature (the engine resends a known creature by id only, without
-- its name). shownLevel (optional): the level a system scaled the monster to (a rift tier, an invasion area, a
-- generated area point); monster_levels.lua shows it after the name ("[level]", engine patches 0040 / 0044) in the
-- same onSpawn, so the first creature packet carries it too.
Chaos.spawnName = nil
Chaos.spawnLevel = nil
function Chaos.createMonsterNamed(typeName, position, extended, force, shownName, shownLevel)
	if shownName == typeName then
		shownName = nil
	end
	if not shownName and not shownLevel then
		return Game.createMonster(typeName, position, extended, force)
	end
	Chaos.spawnName = shownName
	Chaos.spawnLevel = shownLevel
	local ok, monster = pcall(Game.createMonster, typeName, position, extended, force)
	Chaos.spawnName = nil
	Chaos.spawnLevel = nil
	if not ok then
		error(monster, 0)
	end
	return monster
end

-- ---------------------------------------------------------------------------
-- Instances: every place with its own way in and out (rift, dungeon, raid, arena, ...) registers here. The Town
-- Portal and the hideout ask Chaos.inAnyInstance before they move a player, the hideout asks Chaos.instanceAt before
-- it sends a player back to a stored spot, and the instances sweep strangers out of their slots.
--   Chaos.registerInstance(key, {label = "a raid", inside = function(player) end, at = function(pos) end})
--       inside: the player takes part in a run (membership); at: the position lies in the instance's area
--   Chaos.inAnyInstance(player[, except]) -> key, label   (taking part in one, or standing in one's area)
--   Chaos.instanceAt(pos[, except]) -> key, label         (area only)
--   Chaos.sweepIntruders(inArea, isMember[, text]) -> n   non-staff players in the area who are not members go home
--   optional runs = function() -> {{id, what, left, players, idle}}, close = function(id) -> ok, text: the staff view
--       /instances of instance_limits.lua (server/README.md "Instance limits")
-- A check that errors counts as "no" (one broken module must not lock everybody in place).
-- ---------------------------------------------------------------------------
Chaos.instances = {}
Chaos.instanceOrder = {}

function Chaos.registerInstance(key, def)
	if type(key) ~= "string" or type(def) ~= "table" then
		return false
	end
	if not Chaos.instances[key] then
		Chaos.instanceOrder[#Chaos.instanceOrder + 1] = key
	end
	Chaos.instances[key] = def
	return true
end

local function instanceCheck(fn, arg)
	if type(fn) ~= "function" or arg == nil then
		return false
	end
	local ok, v = pcall(fn, arg)
	return ok and v ~= nil and v ~= false
end

function Chaos.instanceAt(pos, except)
	for _, key in ipairs(Chaos.instanceOrder) do
		local def = Chaos.instances[key]
		if key ~= except and def and instanceCheck(def.at, pos) then
			return key, def.label or key
		end
	end
	return nil
end

function Chaos.inAnyInstance(player, except)
	if not player then
		return nil
	end
	local okPos, pos = pcall(function() return player:getPosition() end)
	for _, key in ipairs(Chaos.instanceOrder) do
		local def = Chaos.instances[key]
		if key ~= except and def and (instanceCheck(def.inside, player) or (okPos and instanceCheck(def.at, pos))) then
			return key, def.label or key
		end
	end
	return nil
end

function Chaos.isStaff(player)
	local ok, v = pcall(function()
		local g = player:getGroup()
		return g and g:getAccess()
	end)
	return ok and v == true
end

-- how often an instance's tick sweeps its slot for strangers (Chaos.sweepDue keeps the time per run table)
Chaos.instanceSweepMs = 3000
function Chaos.sweepDue(run, nowMs)
	if not run or (run.sweptAt and nowMs - run.sweptAt < Chaos.instanceSweepMs and nowMs >= run.sweptAt) then
		return false
	end
	run.sweptAt = nowMs
	return true
end

function Chaos.sweepIntruders(inArea, isMember, text)
	if not Game or type(Game.getPlayers) ~= "function" then
		return 0
	end
	local n = 0
	for _, p in ipairs(Game.getPlayers() or {}) do
		if instanceCheck(inArea, p:getPosition()) and not instanceCheck(isMember, p) and not Chaos.isStaff(p) then
			local town = p:getTown()
			local to = town and town:getTemplePosition()
			if to then
				p:teleportTo(to)
				if to.sendMagicEffect then
					to:sendMagicEffect(CONST_ME_TELEPORT)
				end
				p:sendTextMessage(MESSAGE_EVENT_ADVANCE, text or (Chaos.t and Chaos.t(p, "You do not belong to the group in there: you were sent to your temple.")) or "You do not belong to the group in there: you were sent to your temple.")
				n = n + 1
			end
		end
	end
	return n
end

-- ---------------------------------------------------------------------------
-- Gold payments (server/README.md "Gold payments: carried coins, then the bank")
-- ---------------------------------------------------------------------------
-- Every price in gold is paid with Chaos.pay: carried coins first, then the bank, all or nothing (data/lib/chaos_pay.lua).
--   Chaos.totalMoney(player)          carried + bank
--   Chaos.canPay(player, amount)      true when carried + bank >= amount
--   Chaos.pay(player, amount[, quiet]) true, fromCoins, fromBank; false and nothing taken when short
function Chaos.totalMoney(player)
	return (ChaosPay.total(player))
end

function Chaos.canPay(player, amount)
	return ChaosPay.canPay(player, amount)
end

function Chaos.pay(player, amount, quiet)
	return ChaosPay.pay(player, amount, quiet)
end

-- ---------------------------------------------------------------------------
-- Save before a database credit. Moving value from the character (memory, written at logout and server saves) into
-- a database row (stash, bank, guild bank, ...) at once leaves a window: a crash before the next save brings the
-- character back with the value while the row keeps it too. Remove in memory, Chaos.saveCharacter(player), and only
-- then credit the row; when the save fails, give back what was taken and stop (as market.lua and orbexchange.lua do).
-- ---------------------------------------------------------------------------
function Chaos.saveCharacter(player)
	local ok, saved = pcall(function() return player:save() end)
	return ok and saved == true
end

-- ---------------------------------------------------------------------------
-- Staff talkactions. Commands that create or move economy value (/coins, /charm give, /pact days|extra|claimreset)
-- need group >= Chaos.economyMinGroup (the admin panel's economy.* actions ask the same); the rest only staff access.
-- Every use by staff is written to the admin audit log (admin/core.lua ChaosAdmin.log; the console when it is absent).
-- Returns allowed, isStaff: callers return `not isStaff` when not allowed (a player's words are said as chat, staff's
-- are swallowed).
-- ---------------------------------------------------------------------------
Chaos.economyMinGroup = 5
function Chaos.staffCommand(player, words, param, economy)
	local ok, access, gid = pcall(function()
		local g = player:getGroup()
		return g:getAccess(), g:getId()
	end)
	if not ok or not access then
		return false, false
	end
	local allowed = not economy or (tonumber(gid) or 0) >= Chaos.economyMinGroup
	local status = allowed and "ok" or "denied"
	local text = tostring(words) .. " " .. tostring(param or "")
	if ChaosAdmin and ChaosAdmin.log then
		pcall(ChaosAdmin.log, player, "talk" .. tostring(words), "", {param = tostring(param or "")}, status, text)
	else
		print(string.format("[Chaos staff] %s (group %s) %s -> %s", player:getName(), tostring(gid), text, status))
	end
	if not allowed then
		player:sendCancelMessage("Only an administrator may use " .. tostring(words) .. " this way.")
	end
	return allowed, true
end

-- true when a client request must be dropped (ratelimit.lua; per player and key, e.g. "bounty.accept"): for the opcode
-- handlers whose actions read or write the database or walk large tables
function Chaos.limited(player, key, ms)
	return ChaosRateLimit ~= nil and ChaosRateLimit.allow ~= nil and not ChaosRateLimit.allow(player, key, ms or 300)
end

-- ---------------------------------------------------------------------------
-- Extended opcode dispatch (server/README.md "Stress test", "Extended opcode dispatch"). The engine runs every
-- extendedopcode creature event a player registered for every extended opcode the client sends: about 80 Chaos handlers,
-- each returning at once unless the opcode is its own (about 0.2 ms of game loop per request). Here each handler a
-- module defines (`function ev.onExtendedOpcode`) is kept in Chaos.opcodeDispatch instead of the engine, under the
-- opcode of its guard (its upvalue OPCODE: every Chaos handler starts with `if opcode ~= OPCODE then return end`;
-- tests/opcode_dispatch_test.lua checks the sources) or, without one, for every opcode (notifications, admin). A
-- player's registerEvent of such a name registers the one engine event ChaosOpcodeDispatch, which calls the handlers of
-- the opcode the player registered, in the order they were defined. A request over Chaos.opcodeRequestMax bytes is
-- dropped before any handler decodes it (one console line per player a minute). Handlers defined with the table
-- constructor and the base server's own events stay with the engine. Without the engine API (the unit tests' mocks)
-- nothing changes.
-- ---------------------------------------------------------------------------
Chaos.opcodeRequestMax = 16384 -- bytes; the client's requests are far under 8 KB (the largest, a passive tree plan, ~3 KB)

-- A player's budget of extended opcode requests (O220): a bucket of `burst` that refills `perSecond` a second. The engine
-- already closes a connection above maxPacketsPerSecond (50, all packet types) on average; this bounds a burst inside
-- that average and a client that stays just under it, since each request costs a handler call. Looser than the engine
-- on purpose (a login sends a few dozen at once), so a real client never reaches it. Over the budget: dropped, one
-- console line per player a minute.
Chaos.opcodeBudget = {burst = 250, perSecond = 60}

local D = {byName = {}, byOpcode = {}, any = {}, players = {}, seq = 0, warned = {}, bucket = {}, warnedRate = {}}
Chaos.opcodeDispatch = D

-- the opcode of a handler's guard (an upvalue named OPCODE holding a number), else nil
function D.opcodeOf(fn)
	if type(fn) ~= "function" or not debug or not debug.getupvalue then
		return nil
	end
	for i = 1, 255 do
		local name, value = debug.getupvalue(fn, i)
		if name == nil then
			return nil
		end
		if name == "OPCODE" and type(value) == "number" then
			return value
		end
	end
	return nil
end

function D.add(name, fn)
	D.seq = D.seq + 1
	local entry = {name = name, fn = fn, order = D.seq, opcode = D.opcodeOf(fn)}
	D.byName[name] = entry
	if entry.opcode then
		local list = D.byOpcode[entry.opcode] or {}
		D.byOpcode[entry.opcode] = list
		list[#list + 1] = entry
	else
		D.any[#D.any + 1] = entry
	end
	return entry
end

-- the handlers for an opcode, in the order they were defined (own opcode and the ones for every opcode)
function D.handlersFor(opcode)
	local own, any = D.byOpcode[opcode] or {}, D.any
	if #any == 0 then
		return own
	end
	local out, i, j = {}, 1, 1
	while i <= #own or j <= #any do
		if j > #any or (i <= #own and own[i].order < any[j].order) then
			out[#out + 1] = own[i]
			i = i + 1
		else
			out[#out + 1] = any[j]
			j = j + 1
		end
	end
	return out
end

local function nowMs()
	return os.mtime and os.mtime() or os.time() * 1000
end

-- true when player id `pid` may send one more request now (a token is taken)
function D.take(pid, now)
	now = now or nowMs()
	local cfg = Chaos.opcodeBudget
	local b = D.bucket[pid]
	if not b then
		D.bucket[pid] = {tokens = cfg.burst - 1, at = now}
		return true
	end
	if now > b.at then
		b.tokens = math.min(cfg.burst, b.tokens + (now - b.at) * cfg.perSecond / 1000)
	end
	b.at = now
	if b.tokens < 1 then
		return false
	end
	b.tokens = b.tokens - 1
	return true
end

function D.dispatch(player, opcode, buffer)
	local pid = player:getId()
	if type(buffer) == "string" and #buffer > Chaos.opcodeRequestMax then
		local t = nowMs()
		if not D.warned[pid] or t - D.warned[pid] >= 60000 then
			D.warned[pid] = t
			print(string.format("[Warning - Chaos] extended opcode %d from %s: %d bytes is over %d, dropped", opcode,
				player:getName(), #buffer, Chaos.opcodeRequestMax))
		end
		return
	end
	if not D.take(pid) then
		local t = nowMs()
		if not D.warnedRate[pid] or t - D.warnedRate[pid] >= 60000 then
			D.warnedRate[pid] = t
			print(string.format("[Warning - Chaos] extended opcode %d from %s: over %d requests a second, dropped", opcode,
				player:getName(), Chaos.opcodeBudget.perSecond))
		end
		return
	end
	-- no record of the player's registrations (a reload of the scripts while online): every handler, as all register
	local mine = D.players[pid]
	for _, e in ipairs(D.handlersFor(opcode)) do
		if not mine or mine[e.name] then
			-- an error in one handler is reported and the next ones still run, as with one engine event each
			local ok, err = xpcall(function() return e.fn(player, opcode, buffer) end, debug and debug.traceback or tostring)
			if not ok then
				print(string.format("[Error - Chaos opcode dispatch] %s (opcode %d): %s", e.name, opcode, tostring(err)))
			end
		end
	end
end

function D.forget(pid)
	D.players[pid] = nil
	D.warned[pid] = nil
	D.bucket[pid] = nil
	D.warnedRate[pid] = nil
end

if type(rawgetmetatable) == "function" and type(CreatureEvent) == "table" and getmetatable(CreatureEvent)
		and type(rawget(CreatureEvent, "onExtendedOpcode")) == "function" and type(Player) == "table"
		and type(Player.registerEvent) == "function" then
	local names = setmetatable({}, {__mode = "k"}) -- event object -> its name
	local MT = getmetatable(CreatureEvent)
	local construct = MT.__call
	MT.__call = function(self, def, ...)
		local obj = construct(self, def, ...)
		if obj and type(def) == "string" then
			names[obj] = def
		end
		return obj
	end
	local engineOn = CreatureEvent.onExtendedOpcode
	CreatureEvent.onExtendedOpcode = function(self, fn)
		local name = names[self]
		if not name or type(fn) ~= "function" or D.byName[name] then
			return engineOn(self, fn)
		end
		D.add(name, fn) -- not given to the engine: ev:register() then registers nothing
		return true
	end

	-- a load from another interface: a spell (thief/shadow_veil.lua: _common.lua loadClasses -> classes.lua -> this
	-- file), an NPC script, a lib, an XML event script. They share the engine's Lua state, but CreatureEvent() there
	-- reports "CreatureEvents can only be registered in the Scripts interface." with a traceback (start log
	-- 2026-10-16) and gives nil. A chunk of such a folder on the call stack means: not the Scripts interface.
	D.OTHER_INTERFACES = {"spells", "npc", "lib", "monster", "actions", "creaturescripts", "globalevents", "movements",
		"talkactions", "weapons"}
	function D.outsideScripts()
		if type(debug) ~= "table" or type(debug.getinfo) ~= "function" then
			return false
		end
		for level = 2, 60 do
			local info = debug.getinfo(level, "S")
			if not info then
				break
			end
			local src = info.source or ""
			if src:sub(1, 1) == "@" then
				src = src:gsub("\\", "/")
				for _, dir in ipairs(D.OTHER_INTERFACES) do
					if src:find("data/" .. dir .. "/", 1, true) then
						return true
					end
				end
			end
		end
		return false
	end

	-- the engine events and the registerEvent hook, once. Outside the Scripts interface nothing is installed here (no
	-- CreatureEvent() call at all) and the Scripts interface's own load of this file installs it (the guard at the
	-- top). Without that every Chaos handler stayed in D and no client request reached one (found in a live client,
	-- 2026-10-13).
	function D.install()
		if D.installed then
			return true
		end
		if D.outsideScripts() then
			return false
		end
		local dispatcher = CreatureEvent("ChaosOpcodeDispatch")
		if not dispatcher then
			return false
		end
		dispatcher:type("extendedopcode")
		engineOn(dispatcher, D.dispatch)
		dispatcher:register()
		local logout = CreatureEvent("ChaosOpcodeDispatchLogout")
		if logout then
			function logout.onLogout(player)
				D.forget(player:getId())
				return true
			end
			logout:register()
		end
		D.installed = true
		D.hookRegister()
		return true
	end

	-- Player:registerEvent of a dispatched name registers the one engine event (D.install, once)
	function D.hookRegister()
		local engineRegister, engineUnregister = Player.registerEvent, Player.unregisterEvent
		function Player.registerEvent(self, name)
			if not D.byName[name] then
				return engineRegister(self, name)
			end
			local pid = self:getId()
			local mine = D.players[pid]
			if not mine then
				mine = {}
				D.players[pid] = mine
				engineRegister(self, "ChaosOpcodeDispatch")
				engineRegister(self, "ChaosOpcodeDispatchLogout")
			end
			mine[name] = true
			return true
		end
		function Player.unregisterEvent(self, name)
			if not D.byName[name] then
				return engineUnregister(self, name)
			end
			local mine = D.players[self:getId()]
			if mine then
				mine[name] = nil
			end
			return true
		end
	end
	D.install()
end

-- PZ guard (pz_guard_core.lua): doTargetCombat / doTargetCombatHealth drop damage to a player in a protection zone, as
-- the engine's own combat does. Installed here, before any system keeps a local copy of those globals.
if not ChaosPzGuard then
	pcall(dofile, "data/scripts/chaos/pz_guard_core.lua")
end
if ChaosPzGuard then
	ChaosPzGuard.install()
end

-- A magic effect id of 0 (or none) reaches the client as "invalid effect id 0" and the effect is dropped there. Position:
-- sendMagicEffect refuses it here and names the caller once (a script that computed an effect and got nothing), so the
-- source can be found and fixed; nothing is sent. Installed once (a reload keeps the first wrapper).
-- An effect redrawn in place with art bigger than a tile (pair 36) is sent at its offset tile, so it is centred on
-- the target (fx_send_offset_core.lua, data/lib/chaos_fx_send_offsets.lua). An engine with src-patch 0060 takes the
-- table (Game.setFxSendOffsets, handed over on every load of this file) and shifts every effect packet itself,
-- engine sends included; the guard then sends at the target tile. Without the patch it shifts the Lua sends only.
if not ChaosFxSendOffsetCore then
	pcall(dofile, "data/scripts/chaos/fx_send_offset_core.lua")
end
if ChaosFxSendOffsetCore and ChaosFxSendOffsetCore.applyEngine then
	ChaosFxSendOffsetCore.applyEngine(Game)
end
if type(Position) == "table" and Position.sendMagicEffect and not Chaos.magicEffectGuard then
	local rawSendMagicEffect = Position.sendMagicEffect
	local warned = {}
	local offsets = ChaosFxSendOffsetCore and ChaosFxSendOffsetCore.load()
	Chaos.magicEffectGuard = true
	Position.sendMagicEffect = function(self, effect, ...)
		if effect == nil or effect == 0 then
			local where = debug.traceback("", 2):sub(1, 300)
			if not warned[where] then
				warned[where] = true
				print("[Warning - Chaos] Position:sendMagicEffect with effect " .. tostring(effect) .. " refused" .. where)
			end
			return false
		end
		if offsets and ChaosFxSendOffsetCore.luaShifts(effect, offsets) and type(self) ~= "number"
			and tonumber(self.x) and tonumber(self.y) then
			local x, y = ChaosFxSendOffsetCore.shift(self.x, self.y, effect, offsets)
			return rawSendMagicEffect(Position(x, y, self.z), effect, ...)
		end
		return rawSendMagicEffect(self, effect, ...)
	end
end

-- Beta test mode (beta_mode_core.lua, beta_mode_config.lua; server/README.md "Beta test mode"): read at the start of the
-- scripts, so a /reload or a restart picks up `chaos-ctl.sh beta-mode on|off`. Off unless the file says otherwise.
if Chaos then
	-- (a failed load, e.g. a client test that runs this file from the repo root, leaves the mode off)
	pcall(dofile, "data/scripts/chaos/beta_mode_core.lua")
	local okCfg, cfgBeta = pcall(dofile, "data/scripts/chaos/beta_mode_config.lua")
	Chaos.betaMode = okCfg and type(cfgBeta) == "table" and cfgBeta or {enabled = false}
end
-- Everfull potions told to the client's helper (potions_helper.lua, potions_core.lua heldView; client game_helperrotation
-- everfullheld.lua; O246): the carried Everfull per slot by its stock look, server -> client; client -> server only `sync`
ChaosOpcodes.everfull = 116
-- Weather: the server decides it (which areas, rain or clear, how strong) and sends one small message when it changes;
-- the client draws the rain (client game_chaosweather; weather.lua, weather_core.lua, weather_config.lua; O208)
ChaosOpcodes.weather = 114
