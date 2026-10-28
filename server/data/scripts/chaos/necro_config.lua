-- necro_config.lua: every number of the Necromancer line (docs/CLASSES.md "Necromancer"): the Necromancer and its
-- ascended classes Lich (curses, damage over time, life drain, corpse explosion; few strong minions) and Bone Lord
-- (the army: more skeletons, the Bone Golem, an aura, sacrifices).
-- Plain table, loaded as ChaosNecroConfig = dofile("data/scripts/chaos/necro_config.lua") by necro_core.lua users:
-- necro_minions.lua and necromancer_combat.lua (scripts Lua state) and the spells in data/spells/chaos/necromancer,
-- lich and bonelord (spells Lua state, through necromancer/_necro.lua). Pure logic: necro_core.lua
-- (tests: server/tests/necro_test.lua). Balance: server/data/spells/README.md "Necromancer line".
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible. Edit here, then /reload scripts and /reload spells (or restart).
return {
	-- vocation ids (server/data/XML/chaos_vocations_necro.xml) and the client's class byte (base slot 7, + 10 / + 20 for
	-- the ascended classes; client/base-patches/0016-chaos-vocation-ids.patch maps it back to these ids)
	ids = {necromancer = 20, lich = 21, bonelord = 22},
	clientIds = {necromancer = 7, lich = 17, bonelord = 27},
	-- the class key of the store unlock (class_unlocks.lua, ChaosClassUnlocks)
	unlockKey = "necromancer",
	-- !ascend words of the base class
	ascension = {lich = 21, bonelord = 22},

	-- spell ids (spells_chaos.xml; below 256: the 10.98 cooldown packet sends the id as one byte)
	spellIds = {
		raiseDead = 180, boneSpear = 181, witheringCurse = 182,
		soulRot = 183, lifeSiphon = 184, corpseExplosion = 185,
		boneGolem = 186, bannerOfBones = 187, boneOffering = 188,
		-- the summon spells (2026-10-18): free in the base server, the client and the Chaos block (the stock spells end
		-- at 178 and the packs use 194-199), below 256
		raiseWarrior = 192, raiseMage = 176, -- (193, the archer's, is the attack spell Splinter Volley since O254)
		-- the area attack (2026-10-22): the id of the stock Conjure Rations, a conjure spell the runes step removed
		-- (no rune carries it); register_spells.py and spell_ids_test.lua count it as free
		graveNova = 42
	},

	-- condition sub ids (CONDITIONID_COMBAT): the spells and the scripts run in different Lua states, so the
	-- conditions are the state both see. Next to the class sub ids of chaos_constants.lua (71010-71014).
	subId = {
		curse = 71020, -- Withering Curse of a Necromancer or Bone Lord on a monster (timer)
		curseLich = 71021, -- the Lich's stronger Withering Curse on a monster (timer)
		boneAura = 71022, -- Banner of Bones on the Bone Lord (timer)
		boneShield = 71023 -- Bone Offering's shield on the Bone Lord (timer)
	},

	-- levelScale = {from, per, max}: spell strikes (not minions) x (1 + (level - from) / per), at most max. It stood in for
	-- the passive tree and was dropped with the class trees (no entry: 1).

	-- ---------------------------------------------------------------- minions
	-- Minions are real monster types (data/monster/monsters/chaos/necro_*.xml) summoned as the player's summons. They
	-- deal no damage of their own: necro_minions.lua makes them hit every `intervalMs` the creature they target, and
	-- the hit is dealt as the owner (it counts for the owner: experience, loot, bounties, leaderboards, curses).
	-- hit: avg = level x a + magic level x b, min/max = avg x (1 -/+ spread), times the class factor.
	-- health: base + level x perLevel + magic level x perMl, times the class factor.
	-- The XML health is a placeholder below the monster tiers' minimum (monster_tiers.lua minMaxHealth 50), so a new
	-- minion never rolls a tier; the spell sets the real health right after it is created.
	minions = {
		skeleton = {
			monster = "Risen Skeleton", range = 1, intervalMs = 2000, combat = "physical",
			hit = {a = 0.24, b = 0.5}, health = {base = 200, perLevel = 9, perMl = 6},
		},
		shade = {
			monster = "Lich Shade", range = 4, intervalMs = 2000, combat = "death",
			hit = {a = 0.24, b = 0.5}, health = {base = 200, perLevel = 9, perMl = 6},
		},
		golem = {
			monster = "Bone Golem", range = 1, intervalMs = 2500, combat = "physical",
			hit = {a = 0.24, b = 0.5}, health = {base = 200, perLevel = 9, perMl = 6},
			-- the golem's hit strikes every enemy next to it (a slam), and it taunts monsters near it
			slam = true, tauntMs = 6000, tauntRadius = 3,
		},
		-- The two summon spells' minions (Raise Bone Warrior / Mage; the monster types necro_risen_warrior.xml,
		-- necro_risen_mage.xml; the Raise Bone Archer left in O254). Same formulas as the others, with `mult` on top of the
		-- hit and the health (and then the class factors below, so the Lich's single minion is strong and the Bone Lord's weaker).
		-- `summon = true`: raised by a summon spell, not by Raise Dead: no cap of its own, only the total cap (`total`).
		-- ani / effect / hitEffect: the animation the ranged ones throw (a name of necro_lib.lua M.ANI / M.EFFECT), the
		-- effect on the target; fx: a Chaos missile name (chaos_fx.lua) tried before `ani`.
		warrior = {
			monster = "Risen Warrior", range = 1, intervalMs = 2000, combat = "physical", summon = true,
			hit = {a = 0.24, b = 0.5}, health = {base = 200, perLevel = 9, perMl = 6},
			mult = {hit = 1.0, health = 1.8}, hitEffect = "hitarea",
			-- Bone Challenge: the warrior taunts the monsters near it, like the golem (beta 2026-10-22)
			tauntMs = 8000, tauntRadius = 2,
		},
		mage = {
			monster = "Risen Mage", range = 4, intervalMs = 2000, combat = "energy", summon = true,
			hit = {a = 0.24, b = 0.5}, health = {base = 200, perLevel = 9, perMl = 6},
			mult = {hit = 1.35, health = 0.6}, ani = "energy", hitEffect = "energyhit",
		},
		spread = 0.2,
		-- what each class raises and how strong: {kind, caps = {{level, count}, ...}, total = {{level, count}, ...}, hit,
		-- health} (factors). caps: the most minions of the Raise Dead kind. total: the most minions of ALL kinds at once
		-- (skeletons, shades, the golem and the three summon spells' minions together); a new minion past it kills the
		-- OLDEST one first (necro_core.lua N.makeRoom, necro_lib.lua M.raise); the total wins over `caps`. The
		-- Necromancer's total is 3 at every level (its skeleton caps of 3 and 4 are never reached on their own). The Lich
		-- (one shade) and the Bone Lord (5 / 6 skeletons + the golem) keep their old sums, so their identities stay:
		-- a Lich's Raise Bone Warrior replaces its shade, a Bone Lord has room for the three kinds beside his army.
		-- The passive tree's Legion (+skeletons) raises the total by the same number.
		classes = {
			necromancer = {kind = "skeleton", caps = {{0, 1}, {40, 2}, {80, 3}, {200, 4}}, total = {{0, 3}},
				-- hit 1.0 (0.92 from O160 to O254): the archer left the trio in O254 (trio: warrior, warrior, mage), whose damage was lower, so the factor goes back up to keep level 50 at the median
				hit = 1.0, health = 1.0},
			lich = {kind = "shade", caps = {{0, 1}}, total = {{0, 1}}, hit = 2.4, health = 2.5},
			bonelord = {kind = "skeleton", caps = {{0, 5}, {400, 6}}, total = {{0, 6}, {400, 7}}, hit = 0.6, health = 1.2,
				-- Bone Lord skeletons: shards of each hit strike the other enemies next to the target for this share
				splash = 0.75},
		},
		-- the Bone Golem (Bone Lord spell): one at a time, on top of the skeleton cap
		golemClass = {count = 1, hit = 1.8, health = 4.0},
		-- What the monsters do to the minions (O160, 2026-10-24; owner report: "the Necromancer's minions are still weak").
		-- incoming: a monster's hit on a minion is x factor, and x the monster's pace damage curve (pace_config.lua damage,
		-- 0.85 at level 50 .. 0.40 at 1000: what the monster deals to the OWNER) when `pace` is on. Before, a minion took the
		-- hit whole: about 2.5 times what its owner took at level 1000, with an owner's armour, evasion and potions none of
		-- which a minion has. A monster that is not paced (a boss, a rift or tower monster) hits as before.
		-- regen: the share of its maximum health a minion gets back per second, `combat` while the fight goes on, `idle` once
		-- no minion was hit and the owner had no target for idleAfterMs (necro_core.lua N.minionRegen / N.minionIdle).
		-- Before, only the Bone Lord's banner healed them, so a minion went into every pack with what the last pack left.
		incoming = {pace = true, factor = 1.0},
		regen = {combat = 0.005, idle = 0.10, idleAfterMs = 2000},
		-- first strike (class identity pass, 2026-10-28): a minion that has just risen waits this long before its first hit, per
		-- class, so the minion classes start slower and win long fights (a ramp of 4-8 s; weakness_model.py reads it). The Bone
		-- Lord needs none: its army takes 13 s to raise. Minions persist between packs, so a hunt pays it once; a boss pull, a
		-- death or a protection zone rest pays it again.
		firstStrikeMs = {necromancer = 2000, lich = 4000, bonelord = 0},
		-- leash: a minion farther than this from its owner, or on another floor, is brought next to it
		leashRange = 7,
		thinkMs = 500,
		-- protection zones: monsters cannot enter them, so when the owner steps into one its minions are put to rest
		-- (removed, kind and health kept) and rise again next to it when it steps out; a rest older than this is lost
		restKeepSeconds = 1800,
	},

	-- Minion spells (beta 2026-10-22): every kind has a single target spell and an area spell. A minion whose hit is due
	-- casts one of them in place of the hit when it is ready: the area spell when at least minArea enemies stand in it,
	-- else the single target one, else the plain hit. Damage: the kind's hit (minions above, all its factors) x mult.
	-- center: "self" = around the minion, "target" = around its target. ani / hitEffect: names of necro_lib.lua
	-- M.ANI / M.EFFECT; areaEffect: the effect on every tile of the area.
	minionSpells = {
		minArea = 2,
		skeleton = {
			single = {name = "Marrow Rend", mult = 2.2, cooldownMs = 8000, hitEffect = "drawblood"},
			area = {name = "Bone Sweep", mult = 1.2, cooldownMs = 12000, radius = 1, center = "self",
				hitEffect = "hitarea", areaEffect = "groundshaker"},
		},
		shade = {
			single = {name = "Grave Bolt", mult = 2.4, cooldownMs = 8000, ani = "death", hitEffect = "mortarea"},
			area = {name = "Soul Wail", mult = 1.3, cooldownMs = 12000, radius = 2, center = "target",
				hitEffect = "mortarea", areaEffect = "mortarea"},
		},
		golem = {
			single = {name = "Crushing Fist", mult = 2.5, cooldownMs = 9000, hitEffect = "groundshaker"},
			area = {name = "Ossuary Quake", mult = 1.4, cooldownMs = 14000, radius = 2, center = "self",
				hitEffect = "hitarea", areaEffect = "groundshaker"},
		},
		warrior = {
			single = {name = "Sundering Cleave", mult = 2.4, cooldownMs = 8000, hitEffect = "drawblood"},
			area = {name = "Whirling Bones", mult = 1.3, cooldownMs = 12000, radius = 1, center = "self",
				hitEffect = "hitarea", areaEffect = "blackspark"},
		},
		mage = {
			single = {name = "Arc Bolt", mult = 2.4, cooldownMs = 8000, ani = "energy", hitEffect = "energyhit"},
			area = {name = "Static Nova", mult = 1.3, cooldownMs = 12000, radius = 2, center = "target", ani = "energy",
				hitEffect = "energyhit", areaEffect = "energyarea"},
		},
	},

	-- ---------------------------------------------------------------- spells
	-- Raise Dead: raises minions from usable corpses within `radius` of the caster (at most perCast per cast), or one
	-- from nothing for `nothingManaFactor` x the spell's mana on top. A corpse is usable when it is a monster corpse,
	-- holds no items (never destroys loot) and belongs to nobody else (corpse owner: the caster, its party, or none).
	raiseDead = {radius = 4, perCast = {necromancer = 2, lich = 1, bonelord = 3}, nothingManaFactor = 1.0, mana = 35},

	-- The summon spells (Raise Bone Warrior / Mage): each creates ONE minion of its kind next to the caster; the
	-- total cap of the class (minions.classes[].total) decides what happens to the oldest minion. The xml entries
	-- (spells_chaos.xml) carry level / mana / cooldown; they are repeated here for the tests and the docs.
	summonSpells = {
		warrior = {spell = "raiseWarrior", name = "Raise Bone Warrior", words = "vael oss brak", level = 8, mana = 30, cooldownMs = 4000},
		mage = {spell = "raiseMage", name = "Raise Bone Mage", words = "vael oss mynd", level = 16, mana = 40, cooldownMs = 4000},
	},

	-- Bone Spear: physical; the creature right behind the target takes `pierce` of it. Formula as mlValues:
	-- (level / 5 + ml x mlMin + baseMin) x scale .. (level / 5 + ml x mlMax + baseMax) x scale, then the level scale.
	boneSpear = {mlMin = 1.6, mlMax = 2.6, baseMin = 20, baseMax = 40, scale = 1.0, pierce = 0.5},

	-- Grave Nova (the Necromancer, level 50, after Withering Curse): death damage on every enemy within `radius` sqm of the
	-- caster (a circle), each hit (level / 5 + ml x mlMin + baseMin) .. (level / 5 + ml x mlMax + baseMax) x scale.
	-- Players only where PvP allows it. A main-target hit a little over Bone Shrapnel's keeps it on rung 3 of the
	-- Necromancer's cooldown ladder (6 s; server/data/spells/README.md "Cooldown ladder"), nothing else moves.
	graveNova = {mlMin = 1.8, mlMax = 2.8, baseMin = 25, baseMax = 45, scale = 1.0, radius = 3},

	-- Withering Curse: the target takes +amplify more damage from everyone for durationMs, and rots for
	-- `ticks` x a tick of death damage (one per second). The Lich's curse is stronger and also curses up to
	-- `spread` more enemies within spreadRadius of the target. Against players: only the rot (no amplify).
	witheringCurse = {
		durationMs = 12000, ticks = 10, tickMs = 1000,
		amplify = {necromancer = 0.15, bonelord = 0.15, lich = 0.25},
		spread = {lich = 2}, spreadRadius = 2,
		tick = {mlMin = 0.25, mlMax = 0.35, baseMin = 5, baseMax = 10, scale = 1.0},
		tickLich = 1.8, -- the Lich's rot ticks harder
	},

	-- Soul Rot (Lich): heavy death damage over time; when the target dies before the rot ends, the remaining
	-- ticks jump to the nearest enemy within jumpRadius.
	soulRot = {ticks = 6, tickMs = 1000, jumpRadius = 3,
		tick = {mlMin = 1.2, mlMax = 1.6, baseMin = 20, baseMax = 40, scale = 1.15}},

	-- Life Siphon (Lich): `pulses` death strikes `pulseMs` apart; the Lich heals `heal` of the damage dealt
	lifeSiphon = {pulses = 3, pulseMs = 500, heal = 0.5,
		hit = {mlMin = 1.1, mlMax = 1.6, baseMin = 20, baseMax = 40, scale = 1.15}},

	-- Corpse Explosion (Lich): up to maxCorpses usable corpses within radius of the target burst, each hitting every
	-- enemy within burstRadius of it (death damage). Without a corpse the spell fails (no mana spent).
	corpseExplosion = {radius = 3, maxCorpses = 3, burstRadius = 1,
		hit = {mlMin = 2.0, mlMax = 3.0, baseMin = 40, baseMax = 80, scale = 1.0}},

	-- Lich, Soul Hoard (passive): spells deal +perFreeSlot for every shade slot left empty (fewer minions, more
	-- personal damage)
	soulHoard = {perFreeSlot = 0.25},

	-- Banner of Bones (Bone Lord): for durationMs the Bone Lord's minions deal +damage, take -reduction and heal
	-- regen of their maximum health every second
	bannerOfBones = {durationMs = 20000, damage = 0.30, reduction = 0.25, regen = 0.03},

	-- Bone Offering (Bone Lord): the skeleton nearest to the target bursts (it dies): physical damage to every enemy
	-- within radius of it, the formula plus healthShare of the skeleton's health; the Bone Lord takes -shield damage
	-- for shieldMs
	boneOffering = {radius = 2, healthShare = 0.15, shield = 0.2, shieldMs = 6000,
		hit = {mlMin = 4.5, mlMax = 6.5, baseMin = 80, baseMax = 160, scale = 1.0}},

	-- Bone Golem (Bone Lord): a cast with the golem out calls it back and heals `heal` of its health
	boneGolem = {heal = 0.5},
}
