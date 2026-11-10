-- attack_rate_config.lua: numbers of the on-hit limits of the 3 attacks per second cap (owner 2026-11-06: "raise the attack limit to 3 per
-- second. Make it reachable too, but balanced"; server/README.md "Attack speed cap"). Read by attack_rate_core.lua.
return {
	-- on-hit extras (off-hand strikes, cleaves, ricochets, radiant strikes): at most this many triggers per second and
	-- player, whatever the swing rate. At the old floor (1 swing per second) they could trigger once per second.
	procPerSecond = 1.5,
	limits = {offhand = 1.5, fistOffhand = 1.5, bloodrage = 1.5, cleavingArc = 1.5, ricochet = 1.5, radiant = 1.5,
		undyingRage = 1.5, axeCleave = 1.5},

	-- Skill training stays where it was (O429): a weapon swing is one skill try, so lower base intervals would train a
	-- skill faster per hour. The tries of weapon use (fist, melee, distance; not exercise weapons, which are not swings) are
	-- cut by newInterval / oldInterval of the vocation, `trainOld` = the base intervals (ms) before O429, `trainDefault` for
	-- every other vocation. Offline training counts tries from the vocation's attack speed too, so it follows.
	trainDefault = 2000,
	trainOld = {[11] = 1500, [12] = 1300, [13] = 1700, [17] = 1500, [18] = 1300, [19] = 1700},
}
