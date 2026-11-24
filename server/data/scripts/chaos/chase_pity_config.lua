-- chase_pity_config.lua: the visible pity of the long chases (O753). Rules: chase_pity_core.lua (tests/chase_pity_test.lua);
-- engine glue: chase_pity.lua; the hooks sit in content_rewards.lua (waystone boss, rift guardian), rift.lua (the chest's
-- set chase), pocketboss.lua (a world boss in a pocket) and pinnacle.lua (the fragments). The sizing of n:
-- tools/chase_pity_model.lua (--check). Plain table. server/README.md "Chase pity (O753)".
--
-- Per character and source: k misses in a row raise the chance of the chase drop to p x (1 + ramp x k / n); the n-th
-- eligible event drops it for sure; a drop sets k to 0. An eligible event is one where the source rolls its chase drop
-- (a set of the rift's theme at the chest's tier, a unique roll of the boss, a fragment roll of the clear). n is the
-- smallest that keeps the mean chase (events to the drop) within maxShift of 1 / p, with p the lowest base chance of the
-- source (the model says how p is found; a character with a higher p sees a smaller shift).
-- The pinnacle uniques keep their own count (pinnacle_config.lua unique.pity, storage +32 .. +35 of its block): the
-- Collection log shows it next to these.
return {
	enabled = true,

	-- player storages, block 7106600 - 7106619 (server/README.md "Storage keys"): base + slot = the misses of that source;
	-- +10 .. +19 free
	storage = {base = 7106600, last = 7106619},

	maxShift = 0.10,

	-- key, slot (storage offset), p (the base chance per eligible event, held to the model), n (the guarantee), ramp (the
	-- chance x (1 + ramp) on the last miss), label (the Collection log's line; pt-BR in the client)
	sources = {
		{key = "rift", slot = 0, p = 0.025, n = 114, ramp = 0.25, label = "Rift chest: set piece"},
		{key = "waystone", slot = 1, p = 0.2034, n = 13, ramp = 0.25, label = "Waystone boss: unique"},
		{key = "guardian", slot = 2, p = 0.1719, n = 15, ramp = 0.25, refTier = 15, refLevel = 1000, label = "Rift guardian: unique"},
		{key = "pocket", slot = 3, p = 0.003, n = 961, ramp = 0.25, label = "Pocket boss: unique"},
		{key = "fragment", slot = 4, p = 0.25, n = 10, ramp = 0.25, label = "Pinnacle fragment"}
	},
	order = {"rift", "waystone", "guardian", "pocket", "fragment"},

	-- the forced drop of a unique source: one unique roll with this item find (every eligible entry certain, loot_config.lua
	-- unique.maxChance; maxPerKill keeps one)
	forceFind = 1000000,

	-- a drop that comes from the guarantee says so (English; pt-BR in i18n_strings.lua)
	message = "Your persistence pays off: %s.",
	staffGroup = 4 -- /chasepity Name [, reset]
}
