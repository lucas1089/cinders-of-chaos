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
	-- with a message; Chaos.storage.passiveRework keeps the last version seen. Build codes made before the change (format
	-- versions 1 and 2) leave them out on import (buildshare_core.lua REWORKED).
	-- Version 1 (2026-10): the mythic leaves 369 (spirit), 376 (healing), 383 (wisdom), 390 (life leech) became the
	-- keystones of the Necromancer, Templar, Thief and Monk lines.
	reworked = {
		{version = 1, ids = {369, 376, 383, 390}}
	}
}

return ChaosPassiveTreeConfig
