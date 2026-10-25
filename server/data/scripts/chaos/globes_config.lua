-- globes_config.lua: every number of the health and mana globes (globes.lua, globes_core.lua; shared framework
-- pickups.lua). A kill may drop a red health globe and / or a blue mana globe; the lower the killer or a nearby party
-- member is on health (mana), the likelier. Plain table, loaded as ChaosGlobesConfig =
-- dofile("data/scripts/chaos/globes_config.lua"). Lua 5.1 / LuaJIT and Lua 5.3 compatible.
-- Edit here, then /reload scripts (or restart). See server/README.md "Ground pickups and globes".
return {
	enabled = true,

	-- The chance curve per kind: {share of max, percent chance} points, highest share first. Above the first point
	-- the chance is 0, between two points it is linear, below the last it stays at the last. Shares are of the lowest
	-- health (mana) among the killer and the party members near it.
	curve = {
		health = {{0.60, 0}, {0.30, 35}, {0.10, 50}},
		mana = {{0.60, 0}, {0.30, 35}, {0.10, 50}}
	},
	-- a flat percent chance by the monster's tier (monster_tiers.lua ChaosTierOf), added to both kinds; normal 0
	flat = {magic = 0, rare = 3, legendary = 5, boss = 10},
	-- never more than this for one kind
	maxChance = 60,
	-- mana: a character with at most this much maximum mana gets no mana globe
	minMaxMana = 30,

	-- the heal: percent of the maximum health (mana). The tree's Healing applies as it does to potions: health through
	-- the heal event (Player healing events), mana through the stored percent
	healthPct = 18,
	manaPct = 18,
	-- the storage the tree's Healing percent is read from for mana (potions_config.lua storage.healingPct); the
	-- potions' own config is read first when it is loaded
	healingStorage = 7102481,

	-- The pickup. ownerWindowMs 0: the killer's party takes it at once; nobody outside the party ever does.
	lifetimeMs = 15000,
	ownerWindowMs = 0,

	-- anti-abuse
	-- per killer and kind: no new globe for this long after one dropped
	cooldownMs = {health = 5000, mana = 5000},
	-- per killer: at most this many globes of a kind on the ground at once
	maxAlive = 2,
	-- party members count for the curve when they are this near the killer (tiles, same floor)
	partyRange = 12,
	-- a monster this far under the killer's level (share of the level, past `grace` levels) drops nothing: trivial kills
	levelGap = {grace = 10, minShare = 0.45},
	-- a summon's death drops nothing; a kill by a summon counts for its owner (the corpse owner), see README
	-- stamina: no globe without stamina for loot (as the loot layer)
	requireStamina = true
}
