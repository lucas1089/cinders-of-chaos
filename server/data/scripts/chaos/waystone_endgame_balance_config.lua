-- waystone_endgame_balance_config.lua (O666): the inputs and the limits of tools/waystone_endgame_model.py --check (CI). Plain table,
-- Lua 5.1 / LuaJIT and 5.3. Computed, not measured in game; server/README.md "Waystone endgame (O666)".
--
-- The model, per tier t (level L = 1100 + 100 (t - 1); the player is at L + the survival model's gap):
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
		-- the deep tiers (XVI-XXV) have no hunt above them (the hunt pool ends at level 2000): a run IS the level's content. Targets of
		-- --derive: a plain run of `deepClearSeconds` (a deep run is not under 80% of it), the median class's sustain `deepSustain` (range
		-- below: harder than the hunt's 1.2 floor, never a wall), experience an hour `deepExpRatio` x the hunt's (12 minutes a level)
		deepClearSeconds = 600,
		deepSustain = 1.8,
		deepSustainRange = {1.2, 2.6},
		deepExpRatio = 1.0,
		-- the median class heals at least this x the pack's damage per second (the hunt model's sustainMin is 1.2)
		sustainMin = 1.2,
		-- every class lives at least this x the median class's seconds with no healing (survival_model.py burstShare)
		burstShare = 0.45,
		-- deep tiers: a plain run pays this x the hunt's experience an hour at most and at least (tiers I-XV are not held: a hunt of
		-- their level exists and the waystone pays in gear and orbs, README "Content rewards")
		expRatio = {0.85, 1.2},
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
