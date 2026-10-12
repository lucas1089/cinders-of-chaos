-- chaos_constants.lua
-- Single source of truth for every opcode, storage key, DB table name and tunable value
-- used by the Chaos client-module scripts in this folder.
--
-- Every other file in this folder starts with:
--     if not Chaos then dofile("data/scripts/chaos/chaos_constants.lua") end
-- so load order inside data/scripts does not matter. This file is idempotent.
--
-- Lua dialect: TFS 1.4.2 / LuaJIT (Lua 5.1 semantics). Do not use 5.3-only syntax here.

if Chaos then
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
-- DPS meter and combat log: per-skill damage / healing / taken, fights, party totals (client game_dpsmeter; combatlog*.lua)
ChaosOpcodes.combatLog = 204
-- Client guard (engine src-patch 0021, client base patch 0035, clientguard*.lua; server/README.md "Client guard"): 189 is
-- the engine's HMAC handshake, both ways, handled in C++ on both sides (it never reaches Lua; listed so that no module
-- takes it); 190 is the module hello of client game_chaosguard, client -> server
ChaosOpcodes.clientGuard = 189
ChaosOpcodes.clientGuardHello = 190

-- ---------------------------------------------------------------------------
-- Item custom attributes in item packets (engine patch server/src-patches/0003-item-custom-attributes.patch, client
-- feature GameItemCustomAttributes = 126): after every item the client gets u16 count, then u16 key + u64 value per
-- entry. The keys are the same numbers as ChaosItemAttrKey in the engine's const.h and ChaosItemAttr in the client
-- (modules/game_itemrarity); tests/item_tooltip_test.lua checks the three. item:getClientAttributes() returns them.
-- ---------------------------------------------------------------------------
Chaos.itemAttr = {
	rarity = 1, -- custom attribute "rarity" (1..15)
	level = 2, -- custom attribute "combatPowerLevel" (item level)
	locked = 3, -- custom attribute "chaos_locked" (the item lock)
	unique = 4, -- custom attribute "chaos_unique" present
	sockets = 5, -- custom attribute "chaos_sockets" (socket count; a unique's fixed socket is not stored)
	id = 6, -- custom attribute "chaos_iid": per-item id, given by the engine the first time the item is sent
	version = 7, -- hash of the item's attributes: changes when the item changes (orbs, gems, upgrades)
	appearance = 8 -- custom attribute "chaos_tmog" (transmog look, server id) sent as the look's client id (engine patch 0019)
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
	passiveExtraPoints = 7100020, -- bonus passive points granted by quests/GM
	passiveStatsFixed = 7100021, -- 1 once the stats older passive tree versions wrote into the character are clamped
	passiveClassFx = 7100022, -- the class nodes of the passive tree the character holds, a bit each (class_tree.lua)
	passiveRework = 7100023, -- the last reworked-nodes version refunded (passivetree_config.lua reworked)
	dungeonQueueLock = 7100030, -- (os.time of the last queue join; anti spam)
	bountyWeekBonus = 7100300, -- bounty board (bounty.lua): 7100300 - 7100309 reserved; week key of the last weekly bonus
	riftRun = 7100400, -- rifts (rift.lua): 7100400 - 7100409 reserved; +0 tier of the key of a run in progress, +1..+3 its modifiers, +4 start
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
	autosellPaused = 7100102, -- 1 = auto seller switched off with !autosell off
	autosellRarity = 7100103, -- 1 = opt-in: the auto seller may sell items with a rarity / modifiers
	nameChangeTokens = 7100104, -- unused name changes bought in the store
	vocationChangeTokens = 7100105, -- unused vocation changes bought in the store
	shopRarityAutoloot = 7100106, -- 1 = Rarity Autoloot unlocked (lootfilter.lua: autoloot by rarity)
	-- store pouches (pouches_config.lua storage): 7100107 Loot Pouch rules, 7100108 free Loot Pouch given, 7100109 pouches to give back
	autosellBase = 7100110 -- + 1 .. + Chaos.shopServices.autosellSlots: item ids on the auto-sell list
}

-- Anti-bot and player reports (client game_antibot; antibot*.lua, reports*.lua, sql/chaos_reports.sql): presence check
-- modal and the report dialog on one opcode; storages 7100890 - 7100899 reserved (antibot.lua: +0 last presence check,
-- +1 day key, +2 checks that day, +3 grace until, +4 suspicion score x 10)
ChaosOpcodes.antibot = 211
Chaos.storage.antibot = 7100890
Chaos.antibotTables = {reports = "chaos_reports", log = "chaos_antibot_log", holds = "chaos_antibot_holds"}

-- Wardrobe: footprints and outlines (cosmetics.lua kinds footprint / outline, client game_cosmeticfx) and the visual
-- exclusives (exclusives.lua, exclusives_core.lua, exclusives_config.lua, sql/chaos_exclusives.sql; the Collection tab
-- of client game_cosmetics, cosmetics opcode 225, no new opcode). Storages 7102000 - 7102049 reserved: +0 the chosen
-- footprint, +1 the chosen outline (cosmetics_config.lua storage), +10 .. +39 name plate frame slots 9 and up
-- (shopFrameBase2 above)
Chaos.storage.wardrobe = 7102000

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
	coinGifts = "chaos_coin_gifts"
}
-- Rift Atlas: one row per character, completed grid cells and allocated nodes (atlas.lua, sql/chaos_rift_atlas.sql)
Chaos.tables.riftAtlas = "chaos_rift_atlas"
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
	-- ASSUMPTION: 35572 is the SERVER item id of the star item and equals the client id the
	-- client hard-codes (setItemId(35572)). Set to 0 to disable the star tab server-side.
	starItemId = 35572,
	starWithdrawMax = 1000, -- the client UI caps a withdraw at 1000 per action; enforced here too
	maxAmount = 2000000000, -- sanity cap on a single operation
	transferMinLevel = 1
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
	}
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
	-- DungeonTime (60 / 30 minutes) but at most maxTimeSeconds (45 minutes: two to three times the speed challenge of
	-- 15-20 minutes); warnings at warnAt seconds left. One run per dungeon at a time (the base dungeon is one map area):
	-- the queue is the waiting line and shows the wait of the run inside.
	maxTimeSeconds = 2700,
	limits = {warnAt = {300, 60, 10}},
	cooldownOnSuccess = true, -- apply DUNGEON_SYSTEM.CooldownTime also after a win (the base server modal only did on failure)
	queueTickMs = 3000,
	maxDifficulty = 6, -- client has 6 difficulty buttons
	-- percentage of area monsters that must die before the "boss can be killed" notice
	progressNeeded = 100,
	extra = {
		[1] = {
			title = "Bones Dungeon",
			bossName = "prince skeletal",
			loot = {{id = 2160, count = 3}},
			challenges = {
				{key = "speed", title = "Speed Runner", points = 5, desc = "Finish in under 15 minutes.", maxMs = 15 * 60 * 1000},
				{key = "flawless", title = "Flawless", points = 10, desc = "Finish without anyone dying."}
			}
		},
		[2] = {
			title = "Master of the Elements",
			bossName = "master of the elements",
			loot = {{id = 2160, count = 5}},
			challenges = {
				{key = "speed", title = "Speed Runner", points = 5, desc = "Finish in under 20 minutes.", maxMs = 20 * 60 * 1000},
				{key = "flawless", title = "Flawless", points = 10, desc = "Finish without anyone dying."}
			}
		},
		[3] = {
			title = "Forbidden Chevalier",
			bossName = "forbidden chevalier",
			loot = {{id = 2160, count = 8}},
			challenges = {
				{key = "speed", title = "Speed Runner", points = 5, desc = "Finish in under 20 minutes.", maxMs = 20 * 60 * 1000},
				{key = "flawless", title = "Flawless", points = 10, desc = "Finish without anyone dying."}
			}
		},
		[4] = {
			title = "Rootmaw",
			bossName = "the rootmaw",
			loot = {{id = 2160, count = 10}},
			challenges = {
				{key = "speed", title = "Speed Runner", points = 5, desc = "Finish in under 10 minutes.", maxMs = 10 * 60 * 1000},
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
		gearRarity = {6, 9}, -- min, max rarity of that item (Game.createItemWithRarity)
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
	maxStamina = 2520, -- minutes (42 h), what the Stamina Refill restores to

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
			text = "+25% skill and magic level training for every standard character"}
	},
	worldBuffStorage = 7100920, -- global storages 7100921.. (expiry unix time per buff, in list order)
	worldBuffConfigKey = "chaos_worldbuff_", -- server_config rows chaos_worldbuff_<id>

	-- Name change rules (ChaosShopServices.validateName)
	name = {
		minLength = 3, maxLength = 20, maxWords = 3, minWordLength = 2,
		-- a first word (or any word) that is one of these is refused: staff look-alikes
		staffWords = {"gm", "cm", "god", "admin", "adm", "tutor", "gamemaster", "staff", "support", "owner", "sr", "senior", "server"},
		-- refused anywhere in the name (lower case, substring match); extend as needed
		forbidden = {"admin", "gamemaster", "moderator", "fuck", "shit", "bitch", "whore", "nazi", "hitler", "cunt", "rape"}
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
	outfits = (function()
		local O = {
			warrior = {lookType = 1551, name = "Warborn"},
			thief = {lookType = 1556, name = "Hooded Thief"},
			ninja = {{lookType = 1505, name = "Shadow Ninja"}, {lookType = 1506, name = "Crimson Ninja"},
				{lookType = 1507, name = "Masked Ninja"}, {lookType = 1555, name = "Nightblade"}},
			samurai = {{lookType = 1508, name = "Oni Samurai"}, {lookType = 1509, name = "Ronin"},
				{lookType = 1510, name = "Dark Samurai"}, {lookType = 1554, name = "Wandering Blade"}},
			ranger = {lookType = 1558, name = "Wildwood Ranger"},
			mystic = {lookType = 1559, name = "Archmage"},
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
			[1] = list(O.mystic), [5] = list(O.mystic), [10] = list(O.mystic),
			[17] = list(O.monk), [18] = list(O.monk), [19] = list(O.monk),
			[20] = list(O.necromancer), [21] = list(O.necromancer), [22] = list(O.necromancer),
			[23] = list(O.templar), [24] = list(O.seraph, O.templar), [25] = list(O.seraph, O.templar)
		}
	end)(),
	storage = {
		dualWield = 7100200, -- 1 while the character may hold an off-hand sword (read by server/src-patches/0002)
		ascended = 7100201, -- os.time of the ascension (information only)
		migratedFrom = 7100202, -- the old vocation id until the login message of the migration was shown, then 0
		freeSwitch = 7100203 -- the ascended vocation id a migrated character may still switch to for free (!ascend)
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
	-- Poison Blades: weapon hits poison the target, `share` of the hit as earth damage over `ticks` seconds
	poisonBlades = {durationMs = 20000, share = 0.6, ticks = 4, tickMs = 1000},
	-- Ninja dual wield: each main-hand weapon hit adds an off-hand strike of `share` of the hit, scaled by the
	-- off-hand weapon's attack against the main hand's (clamped to minRatio..maxRatio)
	dualWield = {share = 0.5, minRatio = 0.5, maxRatio = 1.25, delayMs = 150},
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
	shadowMend = {perLevel = 1.0, perMagicLevel = 10, maxHealthShare = 0.04, veiledMultiplier = 1.3, spread = 0.1},
	-- shurikens: the throwing stars of the base server; the attack a shuriken spell uses without one in hand
	shuriken = {items = {2399, 7368}, defaultAttack = 50},
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
	player:sendExtendedOpcode(opcode, json.encode(payload))
	return true
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

-- Positive integer from client input, or nil.
function Chaos.toInt(value, minimum, maximum)
	local n = tonumber(value)
	if not n or n ~= n or n == math.huge or n == -math.huge then
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
-- its name).
Chaos.spawnName = nil
function Chaos.createMonsterNamed(typeName, position, extended, force, shownName)
	if not shownName or shownName == typeName then
		return Game.createMonster(typeName, position, extended, force)
	end
	Chaos.spawnName = shownName
	local ok, monster = pcall(Game.createMonster, typeName, position, extended, force)
	Chaos.spawnName = nil
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
				p:sendTextMessage(MESSAGE_EVENT_ADVANCE, text or "You do not belong to the group in there: you were sent to your temple.")
				n = n + 1
			end
		end
	end
	return n
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
