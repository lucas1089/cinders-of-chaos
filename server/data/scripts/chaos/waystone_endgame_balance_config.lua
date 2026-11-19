-- waystone_endgame_balance_config.lua (O666): the inputs and the limits of tools/waystone_endgame_model.py --check (CI). Plain table,
-- Lua 5.1 / LuaJIT and 5.3. Computed, not measured in game; server/README.md "Waystone endgame (O666)".
--
-- The model, per tier t (level L of waystone_tiers_config.lua: 1100 + 100 (t - 1) up to 2500, then 2500 for tiers XVI-XXV (O672, the
-- player cap); the player is at L + the survival model's gap, never above `playerCap`):
--   monster   a native waystone monster (hunting level `native.level`, the pool's median health / experience of `native.window`) at the
--             run's level: health x the engine's level factor (waystone_tiers_core.lua K.scale) x the deep factor x the pace layer (pace
--             config `scaled`, flat above its last point) when `paceApplies`; damage by survival_model.py (the engine bonus at L, the
--             pace curve, the late boost) from the pool's monsters of the native window, x the deep damage factor.
--   sweep     `mapMonsters` monsters x health x `tierHp` / (the median class's 5 target damage x the armour share x `uptime`).
--   boss      the base boss health of the base tier of the map (`bossBase`) scaled like the monsters', killed by the 1 target damage x
--             `bossUptime`; the band boss: the `seconds` of waystone_endgame_config.lua at the same damage (the XML health follows).
--   survive   the median class (survival_model.py) against a pack of the monsters: seconds to die with no healing (burst) and healing
--             against damage (sustain), as the hunt model; every class at least burstShare x the median's burst.
--   reward    experience a run x the stage x `xpMult`, against the hunt of the level (12 minutes a level, the progression model), and
--             the minutes a level in waystones.
return {
	-- the assumptions
	assume = {
		playerCap = 2500, -- O672 (owner 2026-11-19): the player's level cap; the median class of a run is at most this level
		mapMonsters = 240, -- monsters standing on one of the base maps (audit_waystone_maps.py counts them on an installed server)
		native = {level = 540, window = {468, 612}}, -- the base waystone monsters' hunting levels
		paceApplies = true, -- the pace layer (pace_config.lua `scaled`) acts on a waystone monster by its (run) level
		tierHp = 1.18, -- the average health of the map's magic / rare monsters (12% of them, x2 / x3.5)
		uptime = 0.6, -- the share of a run the damage is on the monsters (walking, looting; the rift model's)
		bossUptime = 0.75,
		overheadSeconds = 75, -- opening the next waystone, the pads and the walk in
		bossBase = {300000, 400000, 500000, 650000, 800000, 1000000}, -- the base bosses' health by base tier (README "Waystone tiers": 300k to 1M)
		huntMinutesPerLevel = 12, -- the leveling model at the top (progression_model.lua: 10-14.5 minutes from level 1000 to 2200)
		stage = 13, -- the experience stage from level 951 (late_game.py LATE_STAGES, open ended)
		bossMapSeconds = 0, -- extra seconds the map boss's lever and walk take
		walkSeconds = 120
	},
	-- the limits of --check, at every tier
	limits = {
		-- a plain run: clear time (sweep + boss + walk, seconds) inside these (the base timer is 30 minutes)
		clearSeconds = {240, 1200},
		-- the deep tiers (XVI-XXV, all at the level cap 2500, O672): no hunt of the level exists (the hunt pool ends at level 2000) and the
		-- cap is the top, so a deep run IS the endgame content and the ten tiers are ten steps of difficulty at one level. Targets of
		-- --derive, {tier XVI, tier XXV} and linear between (a step is a tenth of the distance):
		--   clear time of a plain run: 420 s (7 minutes, well over the 5.5 minutes of tier XV, no free first step) to 780 s (13 minutes,
		--   inside the 12-15 minutes of the biggest rift and the Omen guardian: a tier is never longer than the top content already is)
		--   sustain (the median class's healing against the pack's damage): 2.4 to 1.4 (the hunt model's floor is 1.2: the last tier is
		--   hard, never a wall; tier XV is 3.4 at the cap)
		--   experience an hour against the hunt of the level (12 minutes a level): 0.9 to 1.2 x (a harder tier pays more an hour; most
		--   of the experience is useless at the cap, so it is for the characters on their way up: a hard tier is worth it, no tier more
		--   than a hunt of the level would pay)
		deepClearSeconds = {420, 780},
		deepSustain = {2.4, 1.4},
		deepSustainRange = {1.2, 2.6},
		deepExpRatio = {0.9, 1.2},
		-- the curve of the ten deep tiers: each is harder than the one before (a plain run longer, the pack heavier on the healer) and no
		-- step is a wall: the clear time grows at most this x and the sustain falls at most this share between two tiers
		deepStepClear = 1.12,
		deepStepSustain = 0.15,
		-- the committed clear time of a deep tier is within this share of its target (the factors are two straight lines)
		deepClearTol = 0.12,
		-- the median class heals at least this x the pack's damage per second (the hunt model's sustainMin is 1.2)
		sustainMin = 1.2,
		-- every class lives at least this x the median class's seconds with no healing (survival_model.py burstShare)
		burstShare = 0.45,
		-- deep tiers: a plain run pays this x the hunt's experience an hour at most and at least (tiers I-XV are not held: a hunt of
		-- their level exists and the waystone pays in gear and orbs, README "Content rewards")
		expRatio = {0.8, 1.3},
		-- the deep factors of waystone_endgame_config.lua are within this share of the derivation
		derivedTol = 0.12,
		-- a band boss: the median class kills it within this share of its planned seconds, and lives at least this long under its hits
		bandKillTol = 0.10,
		bandDieMin = 25,
		-- a corrupted waystone: the expected quantity bonus of a run is at most this x the best Rare waystone's (the cap), the break
		-- chance at most this percent
		corruptQuantityVsRare = 1.35,
		corruptBreakMax = 25,
		-- the first clear atlas: the 25 points are at most this share of the 4 stats' full ranks (a choice is forced)
		atlasFullShare = 1.25
	}
}
