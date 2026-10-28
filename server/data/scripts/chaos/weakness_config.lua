-- weakness_config.lua: the inputs and the pinned facts of the class weakness model (owner approved the class identity plan,
-- 2026-10-28, step 3), enforced by tools/weakness_model.py --check. Plain table, read by the tool. Lua 5.3 and LuaJIT
-- compatible. No engine calls. server/data/spells/README.md "Class weaknesses (measured)" and docs/CLASSES.md "Class
-- weaknesses (measured)" have the method and the table.
--
-- The model measures what each class pays for its strength: mana pressure (mana the best rotation spends a minute against what
-- the class regenerates, and the seconds of runway), ramp-up (seconds from a cold start to 80% of the steady damage) and
-- exposure (the share of the damage dealt from a reach of 1, 2 and 3+, and the effective health per level). Nothing here
-- changes a balance number: the pins only fix an ORDER that holds today (who is lowest, who is slowest), so tuning that keeps
-- the identity passes and tuning that erases it fails.
return {
	levels = {300, 800, 1000, 1200},

	-- a class has ramped up when the damage it has dealt since the pull is at least this share of what its steady damage would
	-- have dealt by then, from that second on
	rampShare = 0.8,

	-- seconds a raised minion needs to walk to its target and hit (the Necromancer line); the model raises from a cold start
	minionTravel = 1.0,

	-- minions a Raise Dead cast raises at the pull: 1, since a fresh fight (a boss, a rift) has no corpse to raise from (the
	-- Necromancer raises 2, the Lich 1 and the Bone Lord 3 from corpses: necro_config.lua raiseDead.perCast)
	raisePerCast = 1,

	-- the share of a class's damage on one target that its weapon holds (auto attack), by the kind of stats (rotation_sim.py
	-- CLASSES): melee, fist and distance 0.35 (the Templar's auto attack holds 44% of its single target total at level 300 and 30%
	-- at 1000, server/data/spells/README.md "Templar line"); caster 0.13 (the wand holds wandShare 0.15 of the spells,
	-- necro_balance_config.lua). The sword, the fist and the dagger reach 1; a bow, a crossbow and a wand 3 or more.
	autoShare = {melee = 0.35, fist = 0.35, distance = 0.35, caster = 0.13},

	-- damage taken factor of the classes that have a toughness model (server/data/spells/README.md "Templar line": Juggernaut
	-- Iron Will -25% at 40% uptime and Bulwark 15% block = 0.765, 19.6 health per level; Sentinel 0.81, 17.3; "Classes with the
	-- passive trees": the Samurai 13 health per level, 15.4 effective). Every class not listed has no toughness model: 1.0.
	toughness = {
		["Juggernaut"] = 0.765,
		["Sentinel"] = 0.81,
		["Samurai"] = 0.844,
	},

	-- reach in squares of the spells whose range the xml does not state: the stock spells (their files are not in the repo;
	-- a strike or an area of the stock set as the installed server has it) and two strikes that build their area by hand
	reach = {
		["Scything Arc"] = 1,
		["Butcher's Gyre"] = 1,
		["Headsman's Hurl"] = 4,
		["Sanctum Burst"] = 3,
		["Arcane Ripple"] = 4,
		["Bewitching Hex"] = 3,
		["Pyre Torrent"] = 3,
		["Blade Flurry"] = 1,
		["Sanctified Ground"] = 2,
	},

	-- ENFORCED: the identity facts that hold today (orders, no values)
	-- "rank measure scope N names": every name is among the N lowest (or highest) classes (or lines, the mean of the line's three
	-- classes) of the measure at EVERY level above. Measures: health (effective health per level), ramp (seconds to 80%),
	-- far (share of the damage dealt from reach 3+), near (reach 1), runway, drain.
	pins = {
		-- the Mystic line is the frailest: the two base classes have the least health, the line the lowest mean
		"lowest health class 2 Mystic,Elementalist",
		"lowest health line 1 Mystic",
		-- the Ranger line is frail too (third lowest) and, with the casters, the three most ranged lines
		"lowest health line 3 Ranger",
		"highest far line 3 Mystic,Necromancer,Ranger",
		-- the tanks keep the most effective health
		"highest health class 3 Juggernaut,Sentinel,Samurai",
		-- the Warrior and Templar lines stand with the Monk and Thief among the four least ranged lines
		"lowest far line 4 Warrior,Templar,Monk,Thief",
		-- the Monk line (chi build, Shadowfist's stacks) and the Necromancer line (the Bone Lord's army) are the two slowest to start
		"highest ramp line 2 Monk,Necromancer",
		"highest ramp class 2 Bone Lord,Shadowfist",
	},
}
