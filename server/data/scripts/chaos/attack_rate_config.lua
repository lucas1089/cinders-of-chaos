-- attack_rate_config.lua: numbers of the 3 attacks per second rules (owner 2026-11-06: "raise the attack limit to 3 per
-- second. Make it reachable too, but balanced"; server/README.md "Attack speed cap"). Read by attack_rate_core.lua.
return {
	-- the interval (ms) up to which a hit is full: one attack per second, the old hard floor. Slower swings are unchanged.
	refIntervalMs = 1000,
	-- a swing faster than refIntervalMs deals hit x (interval / refIntervalMs) ^ curveExponent. 0.63: at the floor of 333 ms
	-- (3 attacks per second) a hit is 50.0% and the damage per second 3 x 0.50 = +50% over one attack per second
	-- (owner design: +40-60%); at 2 attacks per second +29%. Raw auto attack damage is no longer linear in the rate.
	curveExponent = 0.63,
	-- on-hit extras (off-hand strikes, cleaves, ricochets, radiant strikes): at most this many triggers per second and
	-- player, whatever the swing rate. At the old floor (1 swing per second) they could trigger once per second.
	procPerSecond = 1.5,
	limits = {offhand = 1.5, fistOffhand = 1.5, bloodrage = 1.5, cleavingArc = 1.5, ricochet = 1.5, radiant = 1.5},
}
