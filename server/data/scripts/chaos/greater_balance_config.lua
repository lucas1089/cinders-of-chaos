-- greater_balance_config.lua (O668): the inputs and the limits of the Greater Rift model, tools/greater_rift_model.py --check
-- (CI). Plain table, loaded with dofile. Lua 5.1 / LuaJIT and Lua 5.3 compatible. No engine calls. The rule itself (health,
-- damage and level a tier, the clock, the climb) is rift_config.lua `greater`; server/README.md "Greater Rift (O668)" has the
-- method and the tables.
--
-- The model (computed, not measured in game): the median class of a level (tools/class_dps_model.py median_dps, the same line
-- the other models read, its growth past level 1000 included) clears the tier 15 rift in the seconds the rift model gives a
-- typical player at the tier's level (R.clearParts: packs, guardian, walking), scaled by its damage against that typical player
-- (area damage for the packs, single target for the guardian, the walk by its speed) and by the rule's health factor of the
-- Greater tier. The clock (the layout band's limit) is the wall: the tier the median class reaches is the highest one it clears
-- inside it. Against the guardian: its damage (tools/guardian_model.py, tier 15 at the entry level) x the rule's damage factor
-- x the engine's level bonus for the shown level, against the median class's pool and healing at the player's level.
return {
	-- the levels of the report and the check: the entry level of tier 15 and the three levels of the design
	levels = {1025, 1500, 2000, 2500},
	-- the party of 5's total damage in typical players (rift_config.lua party, the rift model's 4.98 for five)
	partyDps = 4.98,
	-- a run counts as inside the clock when its seconds are at most this share of it (1 = the whole clock)
	clockUse = 1.0,
	-- the scan: tiers above the reach to print / check the curve over
	scan = 12,
	limits = {
		-- the tier the median class reaches at each level, solo: wide enough that the level matters (a tier is a +6% health
		-- step and the tier-15 clear is 44% of the clock at the entry level), narrow enough that the ladder has a top
		reach = {[1500] = {33, 40}, [2000] = {39, 46}, [2500] = {43, 50}},
		-- a party of 5 reaches within this many tiers of the solo median (the rift's party scaling keeps the clear time)
		partyDelta = 3,
		-- reach(2500) - reach(1500) at least this: a level 2500 character is clearly ahead of a level 1500 one
		levelSpread = 6,
		-- seconds of a tier against the one under it for the median class of 1500, over every tier up to the reach + scan:
		-- no wall (a tier that jumps) and no free tier (a tier that costs nothing more than the one before)
		stepRatio = {min = 1.03, max = 1.10},
		-- the same for the guardian's damage against healing (pressure), the largest step between two tiers
		pressureStep = 1.06,
		-- seconds of tier 16 at the entry level, as a share of the clock: not free (the rule starts at once), not a wall
		entry = {min = 0.25, max = 0.60},
		-- the guardian's damage against the median class's healing at the reach tier of each level: the guardian is a real
		-- threat there (not only a wall of health) and a healer still lives (the rift guardians of guardian_balance_config.lua
		-- run 0.55-1.15 at their own tier; the Greater tiers go above it on purpose, bounded)
		pressure = {min = 1.0, max = 2.2},
		-- seconds to die with no healing at the reach tier: the hit cap of the rift (rift_config.lua guardian.hitCap, 60% of the
		-- pool a hit) is not counted, so a player still has several seconds
		burst = {min = 2.5, max = 20},
		-- a party of 5 takes the guardian's damage x 1.4 on its target: at most this x the solo pressure of the same tier
		partyPressure = 1.6,
		-- the climb: runs a median character needs from the first Greater key to the tier it reaches, +1 / +2 / +3 by the
		-- clock (a ladder of a few evenings, not one run and not a month)
		runs = {min = 5, max = 40},
		-- the personal best reward of a tier: gold at most this share of the tier 15 chest's gold, at the top of the windows
		pbGoldShare = 0.75
	}
}
