-- Spell ranks (O686 phase 2): every number. Plain table, loaded with
--     ChaosSpellRanksConfig = dofile("data/scripts/chaos/spell_ranks_config.lua")
-- Design: docs/SPELL_UPGRADES.md (sections 1, 5.2, 5.3, 7); logic: spell_ranks_core.lua; engine: spell_ranks.lua;
-- server/README.md "Spell ranks (O686 phase 2)". Lua 5.1 / LuaJIT and Lua 5.3 compatible.
return {
	-- The switch. false: the rank state is tracked and stored, the opcode answers, but no rank changes a hit, a cooldown, a
	-- mana cost or a monster's health. It turns true with phase 3 (the monster health curve and the models), never alone:
	-- the health factor and the rank gain go live in the same release.
	enabled = false,
	-- SP are earned and stored whether or not `enabled` is true (a dark release lets the ranks accrue, nothing is felt). false: no SP at all.
	track = false,

	-- player storage block 7107000 - 7108099 (README "Storage keys"); the keys of the design, section 7.1
	storage = {
		base = 7107000,
		rankBase = 7107000, -- +spell id (0..499): packed state, see the core P.pack
		version = 7107500, -- version of the block
		awakened = 7107501, -- awakened spells held (phase 7)
		formChanges = 7107502, -- Form changes made (phase 4)
		grantVersion = 7107503, -- reserved: the launch grant was removed (owner 2026-11-20), never written
		lastPickAt = 7107504, -- phase 4: os.time of the last Form pick of the character (the free change window)
		lastPickWhat = 7107505, -- phase 4: spell id * 10 + tier of that pick (only the last pick has the free window)
		sealWaystone = 7107510, -- phase 7
		sealRift = 7107511,
		sealPinnacle = 7107512,
		awakenedSlots = 7107520, -- +0..9 (phase 7)
		spBase = 7107600, -- +spell id (0..499): SP in hundredths of an SP
		last = 7108099,
		maxSpellId = 499,
	},
	version = 1,
	opcode = 168, -- ChaosOpcodes.spellRanks
	table = "chaos_spell_ranks",

	maxRank = 20,
	-- SP are stored in whole units of 1 / spUnit SP (the design said hundredths: a kill gives about 0.0001 SP, so the glue also
	-- keeps the fraction in memory and a finer unit loses nothing at a logout; 42 SP x 10000 fits a 32 bit storage)
	spUnit = 10000,
	-- a character below this level earns no SP (the tutorial, design 1.1)
	minLevel = 8,

	-- cost of rank r in SP is c x r^exp, c set so that ranks 1 to maxRank cost `totalSp` in all (the design: 42)
	cost = {exp = 1.5, totalSp = 42},

	-- the kill value K = E / refXpPerHour(player level), in hours of on-level hunting (design 1.2). E is the base experience
	-- of the kill (see ChaosSpellRanks.baseExp: A1). Points {level, experience an hour with stage, no boosts}, from
	-- progression_model.lua --curve-json (experience to the next level x 60 / minutes a level); linear between points, flat
	-- outside. Phase 3's spell_upgrade_model.py --check holds them to the model.
	refXpPerHour = {
		{1, 45627}, {8, 889488}, {20, 1796032}, {50, 10193418}, {100, 27757437}, {150, 39130589}, {200, 49508732},
		{300, 76760855}, {400, 106379957}, {500, 110822197}, {600, 110372835}, {700, 123368002}, {800, 170182032},
		{1000, 236368895}, {1300, 438252643}, {1600, 719532552}, {2000, 1087899109}, {2200, 1154319240}, {2500, 1154319240},
	},
	-- one kill gives at most this many hours of K (3 minutes): a boss cannot skip ranks
	clampHours = 0.05,

	-- credit rules (design 1.3)
	credit = {
		-- a character who dealt less than this share of the monster's maximum health gets no SP (no leeching)
		minHealthShare = 0.02,
		-- a heal that restored at least this share of an ally's maximum health inside `healWindowMs` before the kill feeds
		-- the heal pool; the pool is `healPool` of K, split by effective healing. No such heal: damage spells keep 100%.
		healMinShare = 0.01,
		healWindowMs = 10000,
		healPool = 0.20,
		-- per monster, per character: at most this many spell ids are tracked (the rest fall into the auto bucket)
		maxSpellsPerMonster = 16,
		-- a monster's table is dropped this long after the last hit it took (a despawn never reads it)
		staleMs = 600000,
		-- after the kill the table stays for the experience callbacks of the party members
		afterDeathMs = 10000,
		-- a summon's hit is credited to the spell in its cast context (a command), else to the spell named here by the
		-- summon's lowercase name; a summon with no row (the wolves with no command) gives no credit, like an auto attack.
		-- The raising spells are support spells today, so their ranks wait for the phase that ranks supports.
		summonSpells = {
			["risen skeleton"] = 192, -- Raise Bone Warrior
			["bone golem"] = 186, -- Bone Golem
		},
	},

	-- which spells have ranks (design 1.1): the groups of spells.xml, minus the ids listed
	eligible = {
		groups = {attack = true, healing = true},
		excluded = {}, -- spell ids that never rank
		heal = {healing = true}, -- the groups whose spells count as heals
	},

	-- the weight of a spell (design 1.4): its cost in SP is x needScale. Order: heal, ultimate, then the cooldown bands.
	needScale = {
		heal = 0.7,
		ultimate = {minCooldownMs = 35000, scale = 0.35},
		bands = { -- {max cooldown ms, scale}; a cooldown above the last band takes `default`
			{8000, 1.0},
			{13000, 0.8},
		},
		default = 0.8,
	},

	-- catch-up (design 1.4): a spell more than `ranksBelow` ranks under the character's best spell of the same weight earns x`mult`
	catchUp = {ranksBelow = 4, mult = 2},

	-- the account echo (design 1.7, owner default): a character's floor on a spell is min(maxFloor, floor(share x the best rank
	-- of the account on it))
	echo = {share = 0.5, maxFloor = 10},

	-- what a rank gives (design 1.5): per rank percent; the cooldown cut comes in steps at `cdRanks`
	effects = {
		damage = {power = 0.9, cooldownPerStep = 2, mana = 1.0}, -- +0.9% hit a rank (+18% at 20), -2% cooldown a step, -1% mana a rank
		heal = {power = 0.6, cooldownPerStep = 3, mana = 1.25},
		cdRanks = {4, 8, 12, 16, 20},
		-- the shortest cooldown a rank may leave (a cooldown shorter to begin with is kept)
		minCooldownMs = 1000,
	},

	-- PvP (owner 2026-11-20: half, no awakening): the rank's power counts at this share against another player; awakening
	-- signature effects and combos are off (phases 6 and 7 read `awakening` and `combos`)
	pvp = {rank = 0.5, forms = 0.5, awakening = false, combos = false},

	-- Forms (phase 4, design 2.4): Form I at rank `rank1`, Form II at `rank2`; the first pick of a tier is free; a change costs
	-- max(minPrice, perLevel x level) gold, bank first; a change of the LAST pick within `freeSeconds` is free (a misclick). The numbers of
	-- the kinds are spell_forms_core.lua `numbers`, the rows data/spells/forms.csv.
	forms = {rank1 = 10, rank2 = 20, minPrice = 10000, perLevel = 150, freeSeconds = 1800, extraCap = 12, groundCap = 6},

	-- tester characters (storage Chaos.storage.tester, README "tester bots") earn no SP: the bots must not bend the curve
	testersEarn = false,

	-- spell ids whose ranks a later reassign clears (design 1.6): [spell id] = version; a character whose stored block version
	-- is below it loses the rank, SP and picks of that id (Form gold is refunded in phase 4)
	reassigned = {},

	-- the monster health factor H by level (design 5.3, owner 2026-11-20: from level 100). 1 below the first point, linear between
	-- points, flat above the last. Read through ChaosSpellRanks.healthFactor(level), which gives 1 while `enabled` is false.
	-- Phase 3 (O686): spell_upgrade_model.py --derive writes these and --check holds them to the derivation; the combos of 10-20% a hit
	-- (owner 2026-11-20) raised them by 0.01 from level 700 up against the first design table, 0.02 at 1600, and the awakening is a line between
	-- its points (0.5 spells at 2000): 2000 and 2200 are 0.02 and 0.01 above it.
	health = {
		{100, 1.02}, {200, 1.03}, {300, 1.06}, {400, 1.08}, {500, 1.10}, {600, 1.13}, {700, 1.16}, {800, 1.18},
		{1000, 1.22}, {1300, 1.25}, {1600, 1.29}, {2000, 1.32}, {2200, 1.35}, {2500, 1.39},
	},

	-- the client state message (opcode 168 `state`, read only in this phase)
	push = {minIntervalMs = 2000, maxSpells = 300},
}
