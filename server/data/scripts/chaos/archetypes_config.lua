-- archetypes_config.lua: the numbers of the build archetype keystones and uniques (docs/BUILDS.md,
-- server/README.md "Build archetypes"). Pure data; rules in archetypes_core.lua, engine glue in archetypes.lua.
--
-- Each keystone is a converted leaf of the main passive tree (client treedata/nodes.lua, `classes` = who may take it);
-- its flag (customStats key) is the key of the table below. The client tooltips repeat these numbers and
-- server/tests/archetypes_test.lua checks that they match. Every price is part of the keystone.
-- Computed balance (not measured in game): server/data/spells/README.md "Build archetypes".

ChaosArchetypesConfig = {
	-- player storage of the flags the character holds, a bit each in the order of `nodes` (Chaos.storage.archetypeFlags;
	-- written after every apply by archetypes.lua, read by the spells' Lua state: ChaosSpell.meleeAttack for Open Hand)
	storage = 7100024,

	-- node id of each keystone (a leaf of the main tree; passivetree_config.lua reworked versions 2 and 3) and its flag.
	-- Append only: the order is the bit of the flag storage.
	nodes = {
		{id = 108, flag = "arPyreOath"},
		{id = 81, flag = "arSanguine"},
		{id = 77, flag = "arThornbound"},
		{id = 109, flag = "arOpenHand"},
		{id = 107, flag = "arContagion"},
		{id = 78, flag = "arCascade"},
		{id = 82, flag = "arStormstring"},
		{id = 355, flag = "arWinterLattice"},
		{id = 262, flag = "arEffigy"},
		{id = 106, flag = "arCinderSigil"},
		{id = 362, flag = "arAetherEdge"},
		{id = 253, flag = "arReliquary"},
		-- the second round (2026-10-12, reworked version 3): snares, vigils with reserved mana, a pure energy shield
		{id = 105, flag = "arSnarewright"},
		{id = 99, flag = "arVigils"},
		{id = 102, flag = "arIronTithe"},
		{id = 96, flag = "arHollowVessel"},
	},

	-- the classes that may take each keystone (the client nodes carry the same list; the test checks it)
	classes = {
		arPyreOath = {"warrior", "juggernaut", "berserker", "templar", "inquisitor", "sentinel"},
		arSanguine = nil, -- every class
		arThornbound = nil, -- every class
		arOpenHand = {"warrior", "juggernaut", "berserker", "ranger", "deadeye", "beastmaster", "mystic", "elementalist",
			"illusionist", "thief", "ninja", "samurai", "necromancer", "lich", "bonelord", "templar", "inquisitor", "sentinel"},
		arContagion = {"thief", "ninja", "samurai"},
		arCascade = nil, -- every class
		arStormstring = {"ranger", "deadeye", "beastmaster"},
		arWinterLattice = {"mystic", "elementalist", "illusionist", "necromancer", "lich", "bonelord"},
		arEffigy = {"mystic", "elementalist", "illusionist", "necromancer", "lich", "bonelord"},
		arCinderSigil = {"mystic", "elementalist", "illusionist", "templar", "inquisitor", "sentinel"},
		arAetherEdge = {"monk", "shadowfist", "ironsage", "templar", "inquisitor", "sentinel"},
		arReliquary = {"templar", "inquisitor", "sentinel"},
		arSnarewright = {"ranger", "deadeye", "beastmaster", "thief", "ninja", "samurai"},
		arVigils = {"mystic", "elementalist", "illusionist", "necromancer", "lich", "bonelord", "templar", "inquisitor",
			"sentinel"},
		arIronTithe = {"warrior", "juggernaut", "berserker", "monk", "shadowfist", "ironsage", "templar", "inquisitor",
			"sentinel"},
		arHollowVessel = {"mystic", "elementalist", "illusionist", "necromancer", "lich", "bonelord", "monk", "shadowfist",
			"ironsage", "templar", "inquisitor", "sentinel"},
	},

	-- the work one server tick may do for the chain reactions (poison and burn spread, shatter): at most perTick
	-- spreads every tickMs; the rest waits in a queue of at most queueMax (older entries win; the newest are dropped).
	-- One chain (a pack) spreads at most perChain times. Sized after server/README.md "Game loop stalls": a spread is
	-- one spectator query and a condition (about 0.05-0.1 ms), so 24 a tick stay near 2 ms, far below the 20 ms tasks.
	chain = {perTick = 24, tickMs = 50, queueMax = 200, perChain = 40},

	-- Pyre Oath (Warrior and Templar lines): every second, while out of a protection zone and in a fight (or an
	-- enemy is near), enemies within `radius` take auraShare x your maximum health as fire damage (tree bonuses and the
	-- class factor apply as to a spell); you burn for selfBurn x your maximum health as fire damage (your fire
	-- absorbs apply; never lethal) and regenerate regen x your maximum health. Price: every other damage you deal
	-- x ownDamage. Unique Pyreheart Mantle: the aura x (1 + uniqueAura).
	arPyreOath = {radius = 2, auraShare = 0.04, selfBurn = 0.025, regen = 0.02, ownDamage = 0.75, thinkMs = 1000,
		uniqueAura = 0.20},

	-- Sanguine Covenant (every class): every hit you deal (weapon, spell, the aura, minions not) leeches share of the
	-- damage as health, at most capPerSecond x your maximum health in any second. Price: healing you receive (spells,
	-- potions, other players; not the leech) x healingTaken. Unique Vein of the Unsated: share +uniqueShare, cap
	-- +uniqueCap.
	arSanguine = {share = 0.05, capPerSecond = 0.06, healingTaken = 0.70, uniqueShare = 0.01, uniqueCap = 0.03},

	-- Thornbound Oath (every class): a hit taken from a creature (melee, ranged, spell; not damage over time) is
	-- reflected: share of what landed, plus your items' Reflect Damage a second time, as physical damage. Per hit at
	-- most ownCap x your maximum health. Against players (PvP rules): x pvpScale, at most pvpCap x their maximum health
	-- a hit. Against bosses: x bossScale and at most bossPerLevel x your level per second per boss. Reflected damage is
	-- never reflected again (nor by a monster's own reflect inside it). Price: your damage x ownDamage.
	-- Unique Spitethorn Bulwark: share +uniqueShare.
	arThornbound = {share = 0.20, ownCap = 0.5, pvpScale = 1 / 3, pvpCap = 0.05, bossScale = 0.5, bossPerLevel = 2,
		ownDamage = 0.90, uniqueShare = 0.10},

	-- Open Hand Creed (every line but the Monk's, which fights unarmed already): with no weapon in the hands (a shield
	-- is fine), your fist hits use the Monk's fist attack (attackBase + attackPerLevel x level, at most attackMax) and
	-- your best melee skill (fist, sword, axe or club), x damage. The engine's fist hit has attack engineAttack.
	-- Unique Knuckles of the Unbound: the same without the keystone at x uniqueEnable; with it x (1 + uniqueBonus).
	arOpenHand = {attackBase = 40, attackPerLevel = 0.025, attackMax = 60, damage = 1.10, engineAttack = 7,
		uniqueEnable = 0.80, uniqueBonus = 0.10},

	-- Contagion Rite (Thief line): a monster that dies while your poison is on it (a poison tick of yours within
	-- recentMs) spreads it to up to `targets` monsters within `radius`: `ticks` ticks of share x its last tick, every
	-- tickMs. A spread poison spreads again, up to maxGenerations deep (the chain budget above caps the work).
	-- Price: your weapon hits x weaponDamage. Unique Rotbloom Phial: +uniqueTargets target, +uniqueGenerations deep.
	arContagion = {targets = 3, radius = 2, ticks = 5, tickMs = 2000, share = 1.0, maxGenerations = 4, recentMs = 4000,
		weaponDamage = 0.90, uniqueTargets = 1, uniqueGenerations = 1},

	-- Cascade Edge (every class): a critical hit (weapon or spell) releases a burst on the other enemies within `radius`
	-- of the target (not the target: a clearing tool, the single-target order of the classes stays): share x the
	-- critical hit, of your strongest element of the tree (fire, ice, energy, earth, death, holy; energy when none), at
	-- most once every icdMs. Price: your non-critical hits x nonCrit.
	-- Unique Splintered Instant: share +uniqueShare, cooldown -uniqueIcdMs.
	arCascade = {share = 0.60, radius = 1, icdMs = 800, nonCrit = 0.95, uniqueShare = 0.25, uniqueIcdMs = 200},

	-- Stormstring (Ranger line): bow and crossbow hits arc to up to `arcs` other enemies within `radius` (in sight) for
	-- share x the hit as energy damage. Price: the bow hit on its own target x mainDamage.
	-- Unique Stormcaller Recurve: +uniqueArcs arc; without the keystone it arcs to enableArcs enemy for enableShare.
	arStormstring = {arcs = 3, share = 0.40, radius = 3, mainDamage = 0.90, uniqueArcs = 1, enableArcs = 1,
		enableShare = 0.25},

	-- Winter's Lattice (Mystic and Necromancer lines): a monster that dies within recentMs of an ice hit of yours
	-- shatters: enemies within `radius` take share x its maximum health as ice damage, at most perLevel x your level a
	-- burst. A burst that kills shatters again (the chain budget caps the work). Price: your fire and energy damage
	-- x otherElements. Unique Shard of the Long Winter: share +uniqueShare, radius +uniqueRadius.
	arWinterLattice = {share = 0.06, perLevel = 12, radius = 2, recentMs = 2000, otherElements = 0.70,
		uniqueShare = 0.02, uniqueRadius = 1},

	-- Effigy Covenant (Mystic and Necromancer lines): an attack spell that hits minTargets or more raises a Cinder
	-- Effigy on your tile (a stationary summon; at most `max`, the oldest goes) that lives lifeMs and every pulseMs
	-- repeats that cast: each enemy within `radius` of it (as many as the cast hit, nearest first) takes share x the
	-- cast's average hit, of the cast's element. Price: your spells x ownSpell. Unique Effigy Carver's Idol: +uniqueMax.
	arEffigy = {max = 2, lifeMs = 12000, pulseMs = 2000, share = 0.22, radius = 3, minTargets = 2, ownSpell = 0.65,
		monster = "Cinder Effigy", uniqueMax = 1},

	-- Sigil of Cinders (Mystic and Templar lines): your fire and holy spell hits ignite (igniteShare of the hit as
	-- fire over igniteTicks ticks of igniteTickMs; a new one replaces it). A spell cast that hits one enemy brands it
	-- for durationMs (one sigil at a time): every pulseMs the sigil burns enemies within pulseRadius of its bearer for
	-- pulseShare x the hit that branded it; when the bearer dies the sigil jumps to the nearest enemy within
	-- jumpRadius, and an ignited monster that dies spreads its burn to spreadTargets enemies within spreadRadius
	-- (the chain budget caps the work, at most spreadGenerations deep). Price: your damage that is not fire or holy
	-- x otherDamage. Unique Brand of the Ashen Choir: pulses x (1 + uniquePulse).
	arCinderSigil = {igniteShare = 0.15, igniteTicks = 4, igniteTickMs = 1000, durationMs = 8000, pulseMs = 1000,
		pulseShare = 0.05, pulseRadius = 1, jumpRadius = 3, spreadTargets = 2, spreadRadius = 2, spreadGenerations = 3,
		otherDamage = 0.80, uniquePulse = 0.25},

	-- Aether Edge (Monk and Templar lines): your weapon and fist hits add share x your current energy shield as energy
	-- damage. Price: your maximum health x maxHealth (a condition, sub id below). Unique Aetherbound Plate: share
	-- +uniqueShare.
	arAetherEdge = {share = 0.06, maxHealth = 0.80, subId = 71090, uniqueShare = 0.04},

	-- Reliquary Vow (Templar line): a Reliquary Warden (a summon that follows you, cannot be attacked; gone in a
	-- protection zone, back outside) pulses every pulseMs: party members and you within healRadius heal healShare x
	-- their maximum health + healPerMagicLevel x your magic level, other party members there deal +partyDamage for
	-- buffMs, and enemies within damageRadius of the warden take damagePerLevel x your level + damagePerMagicLevel x
	-- your magic level as holy damage. Brought back past leashSqm. Price: your own damage x ownDamage.
	-- Unique Reliquary Censer: the pulses x (1 + uniqueBonus).
	arReliquary = {monster = "Reliquary Warden", pulseMs = 2000, healRadius = 3, healShare = 0.006,
		healPerMagicLevel = 2, partyDamage = 0.05, buffMs = 3000, damageRadius = 2, damagePerLevel = 0.6,
		damagePerMagicLevel = 3, leashSqm = 7, ownDamage = 0.90, uniqueBonus = 0.25},

	-- Snarewright's Creed (Ranger and Thief lines; snares_config.lua keystone): more traps and mines, armed faster, snare
	-- hits harder; every other hit x otherDamage. Its numbers live with the snares (the spells' side reads them there).
	-- Covenant of Vigils (Mystic, Necromancer and Templar lines; vigils_config.lua keystone): vigils reserve less, reach
	-- farther and give the party more; your own damage x ownDamage.
	-- Iron Tithe (Warrior, Monk and Templar lines; vigils_config.lua tithe): vigils reserve maximum health instead of mana
	-- and work on you alone, stronger.

	-- Hollow Vessel (Mystic, Necromancer, Monk and Templar lines): your maximum health becomes `health` (a condition with
	-- sub id subId, set to whatever brings it there). Your maximum energy shield: the items' x (1 + more) + fromHealth x
	-- the health given up. The shield recharges recharge per mille of its maximum a second faster and starts earlyMs
	-- after the last hit instead of the engine's 2000 (the archetypes' one second think adds that part). You take no
	-- earth damage over time (poison, Festering Wounds) and no life drain. Health stays what it is: heals, regeneration
	-- and leech fill only those `health` points. Percent-of-maximum-health damage of the rifts (Scorched Earth,
	-- Rimefloor, Veilstorm, the Wrathful Guardian's nova) counts health + maximum shield for you.
	-- Unique Stillheart Robe: more +uniqueMore. Unique Hollowglass Diadem: recharge +diademRecharge per mille, and the
	-- early start without the keystone too.
	arHollowVessel = {health = 100, fromHealth = 0.5, more = 0.5, recharge = 150, earlyMs = 1000, subId = 71091,
		uniqueMore = 0.4, diademRecharge = 100},

	-- the archetype uniques (data/items/chaos_items.xml `archetype`, chaos_unique_specs.lua): base server id -> the
	-- archetype key the glue reads on the equipped copy (it must carry chaos_unique)
	uniques = {
		[8881] = "pyreMantle", [27652] = "sanguineVein", [15413] = "spitethorn", [28023] = "openHand",
		[21691] = "rotbloom", [28049] = "splinteredInstant", [8858] = "stormcaller", [26756] = "longWinter",
		[22423] = "effigyIdol", [18403] = "ashenChoir", [2466] = "aetherPlate", [27251] = "reliquaryCenser",
		-- the second round: snares, vigils, Hollow Vessel
		[28115] = "snarewalker", [7890] = "fusewright", [27667] = "choirmaster", [15453] = "oathkeeper",
		[27668] = "hollowglass", [27390] = "stillheart",
	},
}

return ChaosArchetypesConfig
