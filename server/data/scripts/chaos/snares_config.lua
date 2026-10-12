-- snares_config.lua: the numbers of the snares, traps and mines (docs/BUILDS.md "Snares", server/README.md "Snares").
-- Pure data. Rules: snares_core.lua (tested by server/tests/snares_test.lua). Engine glue: the spells' Lua side,
-- data/spells/chaos/_snares.lua, and the spells Snare Trap, Seeker Mine and Detonate Mines (spells_chaos.xml).
--
-- A snare is a spot on the map, not an item: nothing is created on the tile, nothing is saved, nothing can be picked up
-- or moved. The spells keep a list in memory; a scheduler looks at a few of them every tick (scan below), so a full
-- screen of snares costs a bounded amount of work per tick, like the archetypes' chain budget.
-- Computed balance (not measured in game): server/data/spells/README.md "Snares and vigils".

ChaosSnaresConfig = {
	-- how many snares one player may have out at once; the oldest goes when a new one passes the cap. The keystone and
	-- the uniques add to it (keystone / uniques below).
	caps = {trap = 3, mine = 5},
	-- all players together: a new snare over this is refused ("There are too many snares here already.")
	globalCap = 400,

	-- the scheduler: every tickMs it checks at most perTick armed traps (round robin over the list) and detonates at most
	-- burstsPerTick snares; the rest waits for the next tick. A check is one spectator query of 3x3 tiles; a burst one of
	-- 5x5 and at most maxTargets hits. 60 checks and 16 bursts a tick stay near 2 ms (server/README.md "Game loop
	-- stalls": a spectator query is about 0.02-0.05 ms, a hit about 0.05 ms).
	scan = {tickMs = 200, perTick = 60, burstsPerTick = 16, burstQueueMax = 200},

	-- a snare is gone when its owner logs out, dies, changes floor, goes farther than leashSqm from it or steps into a
	-- protection zone (checked on every scheduler visit; the owner's death and logout also clear them at once when the
	-- scripts' side reports it)
	leashSqm = 30,

	-- Snare Trap: thrown at most throwRange sqm (to the attack target in sight, else straight ahead); armed armMs
	-- later; a monster within triggerRadius sqm of an armed trap sets it off: every enemy within burstRadius (nearest
	-- first, at most maxTargets, in sight of the trap) takes the trap's hit. A trap lasts lifeMs.
	trap = {throwRange = 4, armMs = 600, triggerRadius = 1, burstRadius = 2, maxTargets = 8, lifeMs = 20000},
	-- Seeker Mine: thrown like a trap; armed armMs later; it waits for Detonate Mines (every armed mine of the caster
	-- goes off, staggerMs apart) or its fuse. Its hit is the trap's x damageFactor.
	mine = {throwRange = 4, armMs = 800, fuseMs = 8000, burstRadius = 2, maxTargets = 8, staggerMs = 100,
		damageFactor = 1.15},

	-- the snare's hit (per target), before the tree, the class factor and the prices; power = the best of distance skill
	-- x distance attack, sword skill x blade attack and the shuriken power (ChaosSpell.distanceAttack, bladePower,
	-- shurikenPower). About 3 Skewering Line hits at the same power (its formula: level / 5 + power x 0.0195 + 20 ..
	-- level / 5 + power x 0.0325 + 40): a snare costs a cast and hits only when a monster comes, so it hits harder.
	damage = {
		min = {perLevel = 0.4, perPower = 0.09, base = 20},
		max = {perLevel = 0.4, perPower = 0.135, base = 40}
	},

	-- the element a snare carries: the word after the spell's words (drai snar "fire"), else the element remembered from
	-- the last such word (storage below), else the brand rune socketed in the spell (spell supports: Emberbrand fire,
	-- Rimebrand ice, Dawnbrand holy, Gravebrand death, Stormbrand energy), else physical.
	-- What each element does on top of its damage type:
	--   fire: burns (burnShare of the hit over burnTicks seconds, a fire condition of the owner)
	--   ice: slows by slowPercent for slowMs
	--   energy: the burst reaches energyRadius sqm farther, at energyFactor of the hit
	--   earth: poisons (poisonShare of the hit over poisonTicks seconds, an earth condition of the owner)
	--   death: the owner drains deathLeech of the damage as health
	--   holy: the owner and party members within holyRadius sqm of the snare heal holyHeal of their maximum health
	--   physical: the hit x physicalFactor
	elements = {"fire", "ice", "energy", "earth", "death", "holy", "physical"},
	effects = {burnShare = 0.30, burnTicks = 4, slowPercent = 0.40, slowMs = 3000, energyRadius = 1, energyFactor = 0.85,
		poisonShare = 0.36, poisonTicks = 6, deathLeech = 0.04, holyRadius = 2, holyHeal = 0.02, physicalFactor = 1.15},
	-- the supports' brand runes by support number (data/lib/chaos_supports_config.lua; ids firstId + (n - 1) x 5 + level - 1)
	brands = {[1] = "fire", [2] = "ice", [3] = "holy", [4] = "death", [5] = "energy"},

	-- player storages (chaos_constants.lua Chaos.storage, server/README.md "Storage keys"): the element chosen last
	-- (index into `elements`), and the marker the scripts' side reads to know a hit comes from a snare (1 while the
	-- snare's hits are dealt): the Snarewright price and the archetype rules read it
	storage = {element = 7100026, hit = 7100027},

	-- Snarewright's Creed (keystone, archetypes_config.lua arSnarewright): more snares, armed faster, harder hits;
	-- every other hit of yours x otherDamage (archetypes_core.lua hitFactor)
	keystone = {traps = 2, mines = 3, armFactor = 0.5, damage = 0.25, otherDamage = 0.85},

	-- the snare uniques (archetypes_config.lua uniques; they work without the keystone)
	-- Snarewalker Greaves: +1 trap, traps arm armMs faster, trap hits +trapDamage
	-- Fusewright's Charm: +2 mines, mine hits +mineDamage, the fuse fuseMs longer
	uniques = {
		snarewalker = {traps = 1, armMs = 300, trapDamage = 0.10},
		fusewright = {mines = 2, mineDamage = 0.10, fuseMs = 4000}
	},

	-- the spells (spells_chaos.xml): ids for the scheduler's messages and the tests
	spells = {trap = 99, mine = 100, detonate = 104}
}

return ChaosSnaresConfig
