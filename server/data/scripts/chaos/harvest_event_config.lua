-- The Haunted Harvest: a seasonal haunted event zone of the pair 33 kit (harvest_event.lua, harvest_event_core.lua;
-- tests/harvest_event_test.lua; overview server/README.md "Haunted Harvest"). Every number of the event is here.
-- Returned as a table, loaded as Chaos.harvestConfig = dofile("data/scripts/chaos/harvest_event_config.lua").
-- No engine calls. Lua 5.1 / LuaJIT and Lua 5.3.
--
-- Nothing runs while ChaosHarvestArt.PAIR33 (data/lib/chaos_harvest_art.lua) is off: the kit's items and looks exist
-- only in the client pair 33. Item ids are SERVER ids: the kit 41093..41607 (data/lib/chaos_pack33_kit.lua) and the
-- event items 41620..41623 (data/items/harvest_items.csv, server/tools/install_harvest_event.py).
local C = {}

C.enabled = true

-- the window (server time, both days included; from after to = a window over the new year). /harvest on | off |
-- auto (gamemasters) and the admin panel's Events > Haunted Harvest (also the admin app's remote commands) force it
-- open or shut until set back to auto (a global storage: it survives restarts).
C.window = {from = {month = 10, day = 25}, to = {month = 11, day = 5}}
C.tickSeconds = 60 -- the open / shut check and the city portals
C.staffGroup = 4 -- /harvest status; on / off / auto need the economy group (5) like the other world switches
C.switchGroup = 5

-- player storages 7102800 - 7102809 (server/README.md "Storage keys"):
--   +0 the day (yyyymmdd) of +1, +1 hollow candy from pumpkins that day, +2 the day of the boss's first kill bonus
-- global storage 7102810: the forced state (0 = the window decides, 1 = open, 2 = shut)
C.storage = {day = 7102800, pumpkinCandy = 7102801, bossDay = 7102802}
C.globalStorage = {force = 7102810}

-- action ids 47720 - 47729: the Harvest Portals next to the temples (cityportals kind "harvest"), the ground under the
-- crypt seal and under the ritual circle (harvest_event.lua sets them at startup)
C.aid = {portal = 47720, seal = 47721, circle = 47722}
C.portal = {item = 1387, towns = {2, 1}} -- Cinderhold and Mirewake, like the Memorial Portal

C.items = {candy = 41620, key = 41621, candle = 41622, charm = 41623}

-- pumpkin patches: a ripe pumpkin (stage 5) harvested gives candy and turns into a fresh mound (it grows again through
-- the items.xml decay of the stages, about 7 minutes); now and then the pumpkin wakes (stage 6) and a monster climbs out
C.pumpkin = {candy = {2, 4}, dailyCap = 250, wakeChance = 12, wake = {"Gourdmaw Brute", "Strawhusk Stalker"},
	charmChance = 0.25} -- percent

-- graves (graveyard; mound -> dug -> buried coffin): dig a fresh grave (use it), then open the coffin: candy, now and
-- then a sexton's key, often the dead climb out
C.grave = {candy = {1, 3}, keyChance = 20, raiseChance = 55, raise = {"Barrowbone Reaver", "Barrowbone Archer",
	"Lamenting Shade"}, raiseCount = {1, 2}}
-- upright coffins (the catacombs' coffin gallery)
C.coffin = {candy = {1, 3}, raiseChance = 60, raise = {"Barrowbone Reaver", "Barrowbone Archer"}, raiseCount = {1, 2}}
-- candy cauldrons (the hamlet): trick or treat, then empty for refillSeconds
C.cauldron = {candy = {3, 6}, trickChance = 30, trick = {"Hexwhisker Cat", "Hexwhisker Cat", "Gallows Raven"},
	refillSeconds = 300}
-- the cursed bell (the gibbet hill): ringing it calls a flock of ravens (cooldown per bell)
C.bell = {cooldownSeconds = 180, ravens = 3, raven = "Gallows Raven"}
-- the crypt seal (the ruined chapel): a sexton's key breaks it; it stays open 4 minutes (items.xml decay)
C.seal = {keys = 1}
-- the ritual circle (the ritual chamber): `candles` ritual candles light it; the portal stays open 2 minutes
C.circle = {candles = 3}

-- the boss: at each threshold of `phases` (percent of health) the King's Crypt's graves burst and raise his court and a
-- ward cuts the damage he takes by `wardPercent` for `wardSeconds` (the ritual phase)
C.boss = {name = "Malvorn the Hollow King", phases = {75, 50, 25}, wardSeconds = 20, wardPercent = 50,
	court = {"Barrowbone Reaver", "Barrowbone Archer", "Lamenting Shade"}, perGrave = 1,
	dailyCandy = 30} -- once a day per character, on top of the loot

-- the hollow charm: unlocks one cosmetic the account does not own yet, from this pool (kind cosmetic =
-- cosmetics_config.lua key, ChaosCosmetics.grant; kind exclusive = exclusives_config.lua key, ChaosExclusives.grant).
-- HOOK for the pair 33 cosmetics (wings, head pieces, capes): add their keys here, e.g. {kind = "exclusive",
-- key = "wings_<name>"}, once they exist; nothing else changes. Owned all: the charm gives fallbackCandy instead.
C.charmPool = {
	{kind = "cosmetic", key = "kill_soulspark"},
	{kind = "cosmetic", key = "kill_bloodbloom"},
	{kind = "cosmetic", key = "chat_amethyst"},
	{kind = "cosmetic", key = "foot_blood"},
	{kind = "cosmetic", key = "loot_royal"}
}
C.charmFallbackCandy = 40

-- Widow Hessa's trades (data/npc/scripts/widow_hessa.lua): price = hollow candy; items = {{id, count}, ...}
C.shop = {
	{key = "charm", price = 60, items = {{41623, 1}}, name = "hollow charm"},
	{key = "candle", price = 20, items = {{41622, 1}}, name = "ritual candle"},
	{key = "key", price = 15, items = {{41621, 1}}, name = "sexton's key"},
	{key = "pumpkinhead", price = 25, items = {{2096, 1}}, name = "pumpkinhead"},
	{key = "supplies", price = 10, items = {{7591, 25}, {7590, 25}}, name = "25 great health and 25 great mana potions"},
	{key = "awakening", price = 8, items = {{29851, 3}}, name = "3 Orbs of Awakening"},
	{key = "tempering", price = 15, items = {{32251, 1}}, name = "Orb of Tempering"},
	{key = "whetstones", price = 12, items = {{32256, 2}}, name = "2 Whetstones"},
	{key = "shards", price = 6, items = {{32051, 10}}, name = "10 Rune Shards"}
}

-- the night: an effect over a few set pieces now and then while players are in the area
C.ambient = {everySeconds = 15, effects = {"CONST_ME_BATS", "CONST_ME_POFF", "CONST_ME_MORTAREA", "CONST_ME_SMALLCLOUDS"}}

-- the client calendar (ChaosEvents.dynamic) while open
C.calendar = {name = "Haunted Harvest", description = "A cursed harvest village opens its gates: Harvest Portals next to the temples."}

-- every message, in English; pt-BR in i18n_strings.lua (tests/i18n_test.lua checks)
C.messages = {
	opened = "The Haunted Harvest has begun! Harvest Portals stand next to the temples.",
	closed = "The Haunted Harvest is over. The village sleeps until next year.",
	shut = "The Haunted Harvest is not open now.",
	notRipe = "The pumpkin is not ripe yet.",
	harvested = "You harvest the pumpkin: %d hollow candy.",
	capped = "You harvested enough pumpkins today; the field gives you nothing more.",
	woke = "The pumpkin wakes up!",
	dig = "You dig into the fresh grave...",
	coffinEmpty = "The coffin is empty but for some candy (%d).",
	coffinKey = "Among the bones lies a sexton's key.",
	risen = "The dead climb out!",
	treat = "Treat! The cauldron gives you %d hollow candy.",
	trick = "Trick!",
	cauldronEmpty = "The cauldron is empty. It fills again soon.",
	bell = "The cursed bell tolls... wings beat in the dark.",
	bellCooldown = "The bell is still ringing in the dark.",
	sealNeedsKey = "The crypt seal is shut. A sexton's key would break it.",
	sealBreaks = "The seal cracks open. The crypt stair lies below.",
	candlePlaced = "You set a ritual candle on the circle (%d of %d).",
	circleLit = "The circle flares: the ritual portal is open!",
	circleBusy = "The circle is already burning.",
	portalShut = "The ritual portal is not open.",
	charmUsed = "The hollow charm crumbles: %s is yours (for the account).",
	charmCandy = "Your account owns every haunted cosmetic: the charm turns into %d hollow candy.",
	bossPhase = "%s calls his court from the graves!",
	bossSlain = "%s has fallen! The harvest is safe... for now.",
	bossBonus = "First Hollow King of the day: %d hollow candy."
}

return C
