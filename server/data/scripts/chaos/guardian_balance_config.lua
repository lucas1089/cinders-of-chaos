-- guardian_balance_config.lua (O427): the inputs and the limits of the guardian and rift pack model,
-- tools/guardian_model.py --check (CI). Plain table, loaded with dofile. Lua 5.1 / LuaJIT and Lua 5.3 compatible. No
-- engine calls. server/README.md "Rifts", Guardian damage has the method and the before / after tables.
--
-- The model (computed, not measured in game): per rift tier a geared player of the tier's level (every class, the median
-- build, tools/survival_model.py survive()) meets the guardian and a lured pack of its monsters. The guardian's damage
-- before the player's layers = the base monster's hits (the median of the tier's window by the XML of the repo, a fitted
-- table for the stock monsters of tiers 1-4) x the legendary tier x the tier's damage x guardian.damage x the party's;
-- its marked attacks add a share of the victim's max health. Against the median class: seconds to die with no healing,
-- damage against healing. A Necromancer's trio: seconds the front minion lives under the guardian's hits.
return {
	-- tiers of the report and of the check
	tiers = {1, 5, 10, 15},
	-- base damage of one monster before the layers by hunting level: the stock monsters of the low tiers have no XML in the
	-- repo, so necro_balance_config.lua monsterDps (armor_sim.py stock column, a caster with no percent armour) x stockFit.
	-- The fit: the XML median of tier 5 is 1.46 x that line, of tier 6 1.77 x.
	stockFit = 1.6,
	-- the guardian is the strongest of the window: this far up it (0 the bottom, 1 the top) for the stock line
	windowAt = 0.8,
	-- tiers whose window has XML for most of its monsters (the median of those is the base damage), from this tier on
	xmlFromTier = 6,
	-- the legendary tier's damage factor (monster_tiers.lua tiers.legendary.damage) and the mean tier of a pack monster
	legendaryDamage = 2.0,
	packTierMean = 1.025,
	-- how the guardian's hits split over the player's layers: melee (armour, block) / physical spell / elemental (absorbs)
	split = {melee = 0.5, physical = 0.1, element = 0.4},
	-- monsters of a rift pack (size 5-7) that hit the player at once and the share of the
	-- marked attacks a player still takes after moving (the telegraphs are dodgeable)
	pack = 5,
	marksTaken = 0.35,
	-- the Necromancer's trio against a guardian: the share of its hits that go to the minions (necro_balance_config.lua
	-- focus), seconds a minion is away after it dies (the cast and the walk back), the guardian fight in seconds
	reraise = 4,
	fight = 55,

	-- O476 (2026-11-10): the guardian's single hit and the level warning (tools/guardian_model.py --hits / --warn, the stored
	-- levels in rift_config.lua `warn`, server/README.md "Rifts", Level warning). The hit chain reads the config as it is
	-- (guardian.damage, tiers, party) and the legendary rank of monster_tiers.lua; the base hits are the committed snapshot
	-- data/spells/guardian_hits.csv (tools/survey_guardian_hits.py on an installed server).
	hit = {
		-- the engine's monster level bonus (config.lua monsterBonusDamage 0.0015 a level): x (1 + this x its level) on a monster's
		-- hit. The live engine of 2026-11-10 runs it TWICE (Game::combatChangeHealth runs again after the health events, measured:
		-- a fixed 40 hit of a level 950 monster cost 235); another change fixes the engine, so the rule counts it once, like the
		-- other models. With `enginePasses = 2` (or --passes 2) the levels are the ones of the engine before the fix.
		engineBonus = 0.0015, enginePasses = 1,
		-- the rule reads the guardian that this share of the draws does not exceed (by hit size, weighted by the odds that the
		-- type is the strongest of the run's three: the two stock types of tier 3 with 8M health and hits of 8-11k are 1.7%)
		quantile = 0.9,
		-- the rule: the biggest roll of that guardian, after the median class's armour and absorbs, at most this share of its
		-- pool (health, plus mana for a mana shield class); the shareCap of the marked attacks (rift_config.lua guardian.kit)
		oneHit = 0.6,
		-- the levels the rule looks at (the stored levels are multiples of it)
		step = 5
	},

	-- limits of --check (a guardian at the tier's level, the median class)
	limits = {
		-- seconds to die with no healing, a rift guardian by tier, the Omen guardian (tighter)
		burst = {min = 1.2, max = 16},
		omenBurst = {min = 3, max = 10},
		omenPressure = {min = 0.7, max = 1.35},
		-- the guardian's damage against the median class's healing: above it the healer loses without dodging, far
		-- below it the guardian is only a wall of health (the owner's report)
		pressure = {min = 0.55, max = 1.15},
		-- O478 (2026-11-10), a NAMED EXCEPTION, owner decision pending: with the hit cap (rift_config.lua guardian.hitCap) the
		-- guardian of tier 1 deals 0.41 x the median healing, under `pressure.min`. No guardian.damage brings it back: the
		-- model's typical tier 1 guardian rolls over the cap even at its lowest, so its sustained damage is the cap times its
		-- hit rate and a bigger multiplier only cuts more (base 3.6 and base 50 both give 0.41; tier 2 sits at 0.55). The cap
		-- is the owner's decision, so it stays. The row lowers the floor of that tier to what the model gives, no further;
		-- --check fails when the tier reaches `pressure.min` again (a stale row). The ways back are more hits a second at
		-- tiers 1-2 (an engine knob, a scripted extra hit) or a lower band, both the owner's call.
		-- server/README.md "Rifts", Guardian hit cap (O478).
		pressureCapped = {{tier = 1, min = 0.40}},
		-- a lured pack of the tier: seconds to die with no healing and healing against its damage (hunts: 1.2 and more)
		-- (the burst of a pack is not limited: a median class heals about its whole pool a second at tier 1)
		packSustain = {min = 0.75, max = 1.8},
		-- a party of 5: the guardian's damage x (1 + damagePerExtraPlayer x 4) on its target, against that player's healing
		-- (the party heals each other too); at most this
		partyPressure = 1.6,
		-- (a median class heals about its whole pool a second at the low tiers, so the seconds to die with no healing are
		-- 1 / pressure there: only a lower bound is kept for them)
		-- a Necromancer's front minion lives at least minionMin and at most minionMax seconds under the guardian, and the
		-- owner takes at least ownerShare of the damage a lone player would take while the minions stand
		minionMin = 4, minionMax = 16, ownerShare = 0.6,
		-- monsters of a tier 15 rift against tier 1 (a rift is denser, not only longer) and the most alive at once (the
		-- server load)
		denseMin = 1.2, liveMax = 265
	},

	-- the state before O427 for the before / after tables (patched over rift_config.lua by tools/guardian_numbers.lua)
	legacy = {
		cfg = {
			guardian = {damage = {base = 1, perTier = 0, min = 0, omen = 1}, minion = {factor = 0.25, splash = 0},
				kit = {base = 0, perTiers = 5, omenCount = 0}},
			density = {damage = 0.6, count = {base = 80, perTier = 8}, live = {base = 60, per100 = 1.0, max = 260},
				area = {tilesPerMonster = {33, 27}}}
		},
		necroIncoming = {pace = true, factor = 0.25}
	}
}
