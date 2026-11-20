-- Spell awakening (O686 phase 7): every number. Plain table, loaded with
--     ChaosSpellAwakeningConfig = dofile("data/scripts/chaos/spell_awakening_config.lua")
-- Design: docs/SPELL_UPGRADES.md section 3 (3.1 what it is, 3.2 the Seals and the slot costs, 3.3 examples, 3.4 look), 5.1, 5.2, 7.1; logic:
-- spell_awakening_core.lua; engine: spell_awakening.lua; data: data/spells/awakened.csv; server/README.md "Spell awakening (O686 phase 7)".
-- Nothing acts while spell_ranks_config.lua `enabled` is false (awakening is one part of the spell upgrades; the same switch) or
-- `enabled` below is false. The storage keys are spell_ranks_config.lua `storage` (sealWaystone, sealRift, sealPinnacle, awakened, awakenedSlots).
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.
return {
	enabled = true,

	-- 3.1: an awakened spell hits (or heals) this much more. In PvP it follows the PvP factor of spell_ranks_config.lua (`pvp.rank`, 0.5).
	bonus = 0.10,

	-- 3.1: at most this many awakened spells, one in each slot
	maxSlots = 3,

	-- 3.2: the Seals each slot costs, a counter in storage (never an item). The slot is the lowest free one. Hours of the ideal top content
	-- are waystone / rates.waystonePerHour + rift / rates.riftPerHour; the pinnacle Seals come along at rates.pinnacleSealsPerHour.
	slots = {
		{waystone = 40, rift = 36, pinnacle = 16},
		{waystone = 70, rift = 60, pinnacle = 28},
		{waystone = 100, rift = 90, pinnacle = 40},
	},

	-- 3.2: where the Seals come from. waystone: a cleared waystone map of tier minTier-25 for every player in the map, +firstClear the first
	-- time a tier is cleared by that character (the atlas's first clear, ChaosWaystoneEndgame.creditFirstClear). rift: every Greater Rift run
	-- that ends at tier minTier or higher gives perRun to each player of the run, +climb when the run is sealed and the key climbs.
	-- pinnacle: perKill for each member of the party at the kill of an Ascended boss.
	sources = {
		waystone = {minTier = 16, perClear = 1, firstClear = 1},
		rift = {minTier = 16, perRun = 1, climb = 1},
		pinnacle = {perKill = 2},
	},
	-- a held count stops here (a storage is a 32 bit number; nobody holds more than the three slots cost, 210 + 186 + 84 Seals)
	sealCap = 9999,

	-- the rates the costs were set against, held by server/tools/spell_upgrade_model.py --check to the three models (waystone_endgame_model.py,
	-- greater_rift_model.py, pinnacle_model.py) inside `tol`: a model that moves 20% fails the check and the costs are retuned (design 3.2).
	-- waystonePerHour: a cleared deep map and the walk to the next one is `waystoneMinutes` (pinnacle_balance_config.lua minutes.waystone);
	-- the model's plain clear time of tiers 16-25 times `efficiency` (the design's 1.4x: deaths, restocking, waiting for a party) is that.
	-- riftPerHour: a Greater run is `riftSeconds` at the tier it reaches. pinnacleSealsPerHour: perKill / the hours of a set of fragments.
	rates = {waystonePerHour = 4.0, riftPerHour = 3.0, pinnacleSealsPerHour = 0.72, waystoneMinutes = 15, riftSeconds = 1200, efficiency = 1.4},
	tol = 0.20,
	-- the design table (3.2): hours of ideal top content for each awakening and the same at 1.4x real efficiency
	hours = {22, 37.5, 55},

	-- 5.1: the awakened spell's share of a median class's damage (a top spell: a fifth of a spell share of 80%, in a rotation of about four
	-- spells that matter); (bonus + signature) x this = +3% of the class damage each, +9% with three (spell_upgrade_balance_config.lua awakening.perSpell)
	classShare = 0.20,
	perSpell = 0.03,

	-- 3.3: the signature effect. Its value is the share of the spell's own damage it adds on a typical cast, about +5% (`target`), held inside
	-- `band` for every row of data/spells/awakened.csv by tests/spell_awakening_test.lua, the model and tools/gen_awakened.py:
	--   value = min(raw output, capShare) x use + the utility parts at their worth
	-- raw output: the damage (or heal) the parts deal, as a share of the cast's own damage on the typical enemies of its shape (`targets`,
	-- spell_awakening_core.lua A.raw). The engine never deals more than capShare of the cast's own damage in signature hits (a boss in the ring
	-- is no gold mine); `use` is the share of that which lands on a live target of a hunt pack (the rest is overkill, enemies that left, a pack
	-- dead before the third pulse: measured by the live pass, phase 8, tester bots). Utility (a mark, a shield, a cooldown cut, a leech) is
	-- counted in damage by `worth`.
	signature = {
		target = 0.05,
		band = {min = 0.03, max = 0.07},
		capShare = 0.25,
		use = 0.20,
		-- extra hits of a signature: at most this many targets each, at most this many ground rings a player runs at once
		maxTargets = 12,
		maxRings = 4,
		-- the kind numbers the value model counts: enemies a cast of each shape hits on a typical pack; the enemies a ring reaches at least;
		-- the enemies of a line (per sqm of its length, at most `lineReach`); allies near a healed one; the kills in the window of a cooldown cut
		targets = {single = 1, self = 1, line = 2.5, wave = 3, circle = 3.5, around = 3.5},
		ringReach = 2,
		lineDensity = 0.5,
		lineReach = 4,
		allies = 1.5,
		kills = 3,
		-- damage worth of the utility: a mark's bonus on the next hit (times markShare, the next hit is about this share of the cast), 1% of
		-- max health shielded, one second of cooldown cut per second of cooldown, 1% of the damage leeched
		worth = {mark = 0.05, markShare = 0.6, shield = 0.3, cooldown = 0.3, leech = 0.5},
		-- a signature ring pulses on the enemies within this many sqm of its centre
		ringRadius = 3,
		-- the largest share of its max health a signature shield gives
		shieldMax = 0.10,
		-- a mark lasts at most this long, and a spell marked at most this many enemies (a pack of 12)
		markMaxSecs = 10,
		-- the cooldown a cut may leave (like the rank's cooldown cut)
		minCooldownMs = 1000,
	},

	-- the client: the Seal counts and the awakened spells, pushed on `open` and after an awaken or a Seal
	push = {minIntervalMs = 2000},

	-- tester characters earn no Seals (the bots must not bend the rates); the live pass (phase 8) sets them by the staff command
	testersEarn = false,
}
