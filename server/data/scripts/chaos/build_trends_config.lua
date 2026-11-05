-- Trending builds (O409; build_trends.lua, build_trends_core.lua, tests/build_trends_test.lua; server/README.md
-- "Trending builds (O409)"). Plain table, loaded with
--     ChaosBuildTrendsConfig = dofile("data/scripts/chaos/build_trends_config.lua")
-- Once a day the server groups the passive trees of the active characters per class by the keystones they took and
-- keeps the most played builds of every class in chaos_build_trends: how many characters play each, their share of the
-- class, the average level and one representative code (the tree code CB<n>- and the full build code CC1- around it).
-- No character name or id is ever stored or shown. The website (page?plugin=chaos&p=trends) and the passive tree
-- window (Build Code > Trending) read it. Lua 5.1 / LuaJIT and Lua 5.3 compatible.
return {
	enabled = true,
	table = "chaos_build_trends", -- server/sql/chaos_build_trends.sql; build_trends.lua creates it at startup too

	-- who counts: logged in during the last activeDays days, at least minLevel, below staffGroup, not deleted, not a
	-- tester bot; their active preset (the lowest preset row of chaos_passive_tree)
	activeDays = 7,
	minLevel = 100,
	staffGroup = 4,
	maxCharacters = 50000, -- a safety cap on the rows read in one snapshot

	-- the list: the `top` builds of each class with at least minCount characters (a build of one or two characters is
	-- never listed: no single character can be picked out, and two is no trend)
	top = 5,
	minCount = 3,

	-- when: a snapshot at startup (after startDelaySeconds) when the last one is older than refreshHours, then checked
	-- every checkSeconds. server_config key `configKey` = os.time of the last snapshot. Older snapshots than keepDays are
	-- deleted.
	refreshHours = 24,
	checkSeconds = 3600,
	startDelaySeconds = 120,
	configKey = "chaos_build_trends_at",
	keepDays = 30,
	-- the passive tree window asks at most once per this many ms (ratelimit.lua)
	askMs = 1000,

	-- the keystone names (the client's KEYSTONE_NAMES of game_passivetree/passivetree.lua; the test compares both and
	-- every ks* / ar* flag of passivetree_data.lua): the flag of a keystone node's stats -> its name
	names = {
		ksCleavingArc = "Cleaving Arc", ksBulwark = "Bulwark", ksRicochet = "Ricochet", ksDeadeye = "Deadeye",
		ksArcaneEcho = "Arcane Echo", ksOverload = "Elemental Overload", ksOvergrowth = "Overgrowth", ksThorns = "Thorns",
		ksSharedPhantasm = "Shared Phantasm", ksInspiringIllusion = "Inspiring Illusion", ksImmovable = "Immovable",
		ksUndyingRage = "Undying Rage", ksHuntersFocus = "Hunter's Focus", ksPackAlpha = "Pack Alpha",
		ksLivingShadow = "Living Shadow", ksWayOfTheBlade = "Way of the Blade", ksHoardedSouls = "Hoarded Souls",
		ksBoneColossus = "Bone Colossus", ksHundredHands = "Hundred Hands", ksFlowingMercy = "Flowing Mercy",
		ksDivineVerdict = "Divine Verdict", ksBastion = "Bastion", ksBlackbloodCreed = "Blackblood Creed",
		ksGraveCovenant = "Covenant of the Grave", ksScarredDiscipline = "Scarred Discipline",
		ksPenitentWrath = "Penitent's Wrath", arPyreOath = "Pyre Oath", arSanguine = "Sanguine Covenant",
		arThornbound = "Thornbound Oath", arOpenHand = "Open Hand Creed", arContagion = "Contagion Rite",
		arCascade = "Cascade Edge", arStormstring = "Stormstring", arWinterLattice = "Winter's Lattice",
		arEffigy = "Effigy Covenant", arCinderSigil = "Sigil of Cinders", arAetherEdge = "Aether Edge",
		arReliquary = "Reliquary Vow", arSnarewright = "Snarewright's Creed", arVigils = "Covenant of Vigils",
		arIronTithe = "Iron Tithe", arHollowVessel = "Hollow Vessel", arExecutioner = "Executioner's Verdict",
		arEarthbreaker = "Earthbreaker", arRampage = "Rampage", arLastStand = "Last Stand", arLongshot = "Longshot",
		arBarbed = "Barbed Quiver", arOpeningShot = "Opening Shot", arHobble = "Hobbling Shot",
		ksShadowTwin = "Shadow Twin", ksViperVerdict = "Viper's Verdict", ksCorpseBlast = "Corpse Detonation",
		ksReapersToll = "Reaper's Toll", ksSeventhPalm = "Seventh Palm", ksPiercingPalm = "Piercing Palm",
		ksRadiantRebuke = "Radiant Rebuke", ksDawnchain = "Dawnchain"
	}
}
