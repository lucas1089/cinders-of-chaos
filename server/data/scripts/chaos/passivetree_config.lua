-- Passive tree numbers of the planner and the mastery nodes (passivetree.lua, passivetree_core.lua).
-- The points themselves are Chaos.passive (chaos_constants.lua); the respec prices are respec_config.lua.
ChaosPassiveTreeConfig = {
	-- planApply: the most node ids one request may carry. A plan never needs more than the points owned (about 260 at
	-- level 1000 with the boss points); this only bounds the work a forged request can cause.
	maxPlanNodes = 300,
	-- planApply and masteryChoose: at most one request per this many ms (the same as a plain save)
	rateMs = 1000,
	-- a mastery node offers 2 to this many effects (the generator and the tests check the data against it)
	maxMasteryChoices = 4,
	-- changing the effect of a saved mastery costs the single-node refund price of respec.lua (free below its
	-- freeBelowLevel); a choice made while the node is planned is free
	masteryChangeUsesNodePrice = true,
	-- Nodes whose meaning changed a lot (append only; never edit a handed-out entry). At the first login after a version,
	-- every preset and loadout of the character loses these nodes (and the ones only connected through them), for free,
	-- with a message; Chaos.storage.passiveRework keeps the last version seen. Build codes made before the change (an
	-- older format version) leave them out on import (buildshare_core.lua REWORKED).
	-- Version 1 (2026-10): the mythic leaves 369 (spirit), 376 (healing), 383 (wisdom), 390 (life leech) became the
	-- keystones of the Necromancer, Templar, Thief and Monk lines.
	-- Version 2 (2026-10, the build archetypes, docs/BUILDS.md): twelve small leaves became the archetype keystones
	-- (archetypes_config.lua nodes): 77, 78, 81, 82 (leech / crit leaves), 106-109 (elemental cluster ends), 253, 262,
	-- 355, 362 (mythic leaves).
	-- Version 3 (2026-10-12, the second round: snares, vigils, Hollow Vessel): the four other elemental cluster ends 96,
	-- 99, 102, 105 became Hollow Vessel, Covenant of Vigils, Iron Tithe and Snarewright's Creed (build codes format 5).
	-- Version 4 (2026-10, owner: no drown nodes): 23 drown nodes left the tree (hidden in the client's nodes.lua, bridged
	-- so the rest stays connected); node 504 keeps its vitality, spirit and experience. The presets lose them at login
	-- anyway (refundForeignNodes); this entry takes them out of the saved loadouts too. buildshare_core.lua REMOVED.
	-- Version 5 (2026-10, owner: the routes to every keystone and notable must be relevant to the class): the class lanes,
	-- tools/gen_class_lanes.lua. About 170 to 300 plain nodes per class give that class other stats (same place, same
	-- cost), so the character loses the plain nodes that have a lane for its class (and what hung on them), for free,
	-- once, with the message. `lanes = true` lets the core read the nodes from the tree data instead of listing them.
	reworked = {
		{version = 1, ids = {369, 376, 383, 390}},
		{version = 2, ids = {77, 78, 81, 82, 106, 107, 108, 109, 253, 262, 355, 362}},
		{version = 3, ids = {96, 99, 102, 105}},
		{version = 4, ids = {8, 10, 167, 212, 213, 237, 322, 325, 486, 487, 488, 489, 490, 491, 493, 494, 497, 498, 499, 500,
			501, 502, 503}},
		{version = 5, ids = {}, lanes = true}
	}
}

return ChaosPassiveTreeConfig
