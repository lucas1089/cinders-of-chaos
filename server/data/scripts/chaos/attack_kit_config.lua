-- attack_kit_config.lua: the numbers of the attack kit (ChaosAttackKit): 37 attack spells that give every class
-- line the same count of attack spells (10 per class; owner 2026-10-23, "devem ter a mesma quantidade"), and 7 more (O254)
-- that took over the ids of weak support spells, so every class has 11, and the 7 level 500 spells of the line spell
-- quests (`quest = 1`), so every class has 12, and the 7 level 1200 ultimates (`quest = 3`), so every class has 13.
-- The numbers were fitted with server/tools/rotation_sim.py. Change one here, in spells_chaos.xml and in
-- rotation_model.csv together: tests/attack_kit_test.lua checks all three. Rules and shapes: attack_kit_core.lua; the cast:
-- data/spells/chaos/_attackkit.lua; the balance: server/data/spells/README.md "Attack spell parity".
--
-- Fields: id/name/words/level/mana as spells_chaos.xml; vocations (class names); school (how the hit is dealt and
-- what scales it: melee, distance, magic, monk, blade, shuriken, spell, templar, necro); power (what the hit scales
-- with: melee, distance, magic, monk, blade, shuriken); ctype; the hit (l + P x pMin + ML x mMin + bMin ..
-- l + P x pMax + ML x mMax + bMax) x scale, l = level / 5, P = skill x attack, ML = magic level; shape (single,
-- dot, circle at the target, around the caster, wave, line); chi (a builder), finisher (spends all chi).

ChaosAttackKit = ChaosAttackKit or {}
ChaosAttackKit.cfg = {
	spells = {
		gorehook = {
			id = 2, name = "Gorehook", words = "kah sang hrak", level = 130, mana = 45,
			vocations = {"Warrior", "Juggernaut", "Berserker"}, school = "melee", power = "melee", ctype = "physical",
			pMin = 0.0199, pMax = 0.0318, mMin = 0, mMax = 0, bMin = 8, bMax = 16, scale = 1, shape = "dot", range = 1,
			ticks = 5, tickMs = 1000, melee = true, fx = "blood_slash", vfx = "claw_rake", hitFx = "CONST_ME_DRAWBLOOD"
		},
		riftcleaver = {
			id = 9, name = "Rift Cleaver", words = "kah rhim brak", level = 220, mana = 55,
			vocations = {"Warrior", "Juggernaut"}, school = "melee", power = "melee", ctype = "physical", pMin = 0.1271,
			pMax = 0.2034, mMin = 0, mMax = 0, bMin = 20, bMax = 40, scale = 1, shape = "line", range = 2, length = 3,
			fx = "ground_slam", vfx = "heavy_cleave"
		},
		sunspear = {
			id = 19, name = "Sunspear", words = "kah aur lanc", level = 160, mana = 115,
			vocations = {"Ranger", "Deadeye", "Beastmaster"}, school = "distance", power = "distance", ctype = "holy",
			pMin = 0.1235, pMax = 0.1976, mMin = 0, mMax = 0, bMin = 20, bMax = 40, scale = 1, shape = "single",
			range = 7, shot = "holy_spear", pshot = "proj_piercing_arrow_holy", fx = "holy_smite", vfx = "holy_hit"
		},
		arrowstorm = {
			id = 22, name = "Arrowstorm", words = "drai sag vex", level = 220, mana = 85,
			vocations = {"Ranger"}, school = "distance", power = "distance", ctype = "physical",
			pMin = 0.0669, pMax = 0.107, mMin = 0, mMax = 0, bMin = 20, bMax = 40, scale = 1, shape = "circle",
			range = 7, radius = 2, shot = "gale_arrow", fx = "crit_burst"
		},
		packdart = {
			id = 23, name = "Packhunter's Dart", words = "kah ferh sag", level = 140, mana = 50,
			vocations = {"Beastmaster"}, school = "distance", power = "distance", ctype = "earth", pMin = 0.0491,
			pMax = 0.0786, mMin = 0, mMax = 0, bMin = 20, bMax = 40, scale = 1, shape = "single", range = 7,
			shot = "poison_dart", fx = "poison_burst"
		},
		phantomneedles = {
			id = 24, name = "Phantom Needles", words = "kah mynd sag", level = 130, mana = 275,
			vocations = {"Illusionist"}, school = "magic", power = "magic", ctype = "energy", pMin = 0, pMax = 0,
			mMin = 12.508, mMax = 20.013, bMin = 20, bMax = 40, scale = 1, shape = "single", range = 5,
			shot = "arcane_orb", fx = "arcane_burst", vfx = "arcane_hit"
		},
		mirrorshards = {
			id = 38, name = "Mirror Shards", words = "drai umh krak", level = 170, mana = 345,
			vocations = {"Illusionist"}, school = "magic", power = "magic", ctype = "ice", pMin = 0, pMax = 0,
			mMin = 12.508, mMax = 20.013, bMin = 20, bMax = 40, scale = 1, shape = "around", radius = 1,
			fx = "ice_crystal", vfx = "ice_shatter"
		},
		dreamrot = {
			id = 43, name = "Dreamrot", words = "kah mynd putr", level = 230, mana = 470, vocations = {"Illusionist"},
			school = "magic", power = "magic", ctype = "death", pMin = 0, pMax = 0, mMin = 3.218, mMax = 5.149,
			bMin = 8, bMax = 16, scale = 1, shape = "dot", range = 5, ticks = 6, tickMs = 1000, pshot = "proj_water_bolt_abyss", fx = "shadow_smoke",
			hitFx = "CONST_ME_SMALLCLOUDS"
		},
		guttingslash = {
			id = 45, name = "Gutting Slash", words = "kah vorn kaen", level = 100, mana = 60,
			vocations = {"Thief", "Ninja", "Samurai"}, school = "blade", power = "blade", ctype = "physical",
			pMin = 0.0655, pMax = 0.1048, mMin = 0, mMax = 0, bMin = 20, bMax = 40, scale = 1, shape = "single",
			range = 1, melee = true, fx = "blood_slash", vfx = "sword_slash", hitFx = "CONST_ME_DRAWBLOOD"
		},
		razorrain = {
			id = 56, name = "Razor Rain", words = "drai shur vex", level = 130, mana = 75,
			vocations = {"Thief", "Ninja", "Samurai"}, school = "shuriken", power = "shuriken", ctype = "physical",
			pMin = 0.0655, pMax = 0.1048, mMin = 0, mMax = 0, bMin = 20, bMax = 40, scale = 1, shape = "circle",
			range = 5, radius = 2, shot = "razor_disc", pshotBy = {Samurai = "proj_razor_leaf_sakura"}, fx = "crit_burst", hitFx = "CONST_ME_DRAWBLOOD"
		},
		venomspiral = {
			id = 57, name = "Venom Spiral", words = "kah shur putr", level = 150, mana = 85,
			vocations = {"Thief", "Ninja"}, school = "spell", power = "blade", ctype = "earth", pMin = 0.0128,
			pMax = 0.0205, mMin = 0, mMax = 0, bMin = 8, bMax = 16, scale = 1, shape = "dot", range = 5, ticks = 5,
			tickMs = 1000, shot = "venom_glob", fx = "poison_ring", hitFx = "CONST_ME_POISONAREA"
		},
		crescentcut = {
			id = 62, name = "Crescent Cut", words = "drai kaen sol", level = 170, mana = 85,
			vocations = {"Thief", "Samurai"}, school = "blade", power = "blade", ctype = "physical", pMin = 0.0765,
			pMax = 0.1224, mMin = 0, mMax = 0, bMin = 20, bMax = 40, scale = 1, shape = "wave", range = 2, depth = 2,
			halfWidth = 1, fx = "blood_slash", vfx = "heavy_cleave", hitFx = "CONST_ME_DRAWBLOOD"
		},
		lastbreath = {
			id = 80, name = "Last Breath", words = "kah nyx kaen", level = 230, mana = 150,
			vocations = {"Thief", "Samurai"}, school = "blade", power = "blade", ctype = "physical", pMin = 0.1808,
			pMax = 0.2893, mMin = 0, mMax = 0, bMin = 20, bMax = 40, scale = 1, shape = "single", range = 1,
			melee = true, fx = "crit_burst", vfx = "thrust", hitFx = "CONST_ME_DRAWBLOOD"
		},
		hollowknuckle = {
			id = 82, name = "Hollow Knuckle", words = "kah hol dhun", level = 70, mana = 45,
			vocations = {"Monk", "Shadowfist", "Iron Sage"}, school = "monk", power = "monk", ctype = "physical",
			pMin = 0.053, pMax = 0.0848, mMin = 0, mMax = 0, bMin = 20, bMax = 40, scale = 1, shape = "single",
			range = 1, chi = 1, melee = true, fx = "shockwave", vfx = "punch_hit_violet"
		},
		quakingstomp = {
			id = 84, name = "Quaking Stomp", words = "drai krak dhun", level = 90, mana = 60,
			vocations = {"Monk", "Iron Sage"}, school = "monk", power = "monk", ctype = "physical", pMin = 0.0587,
			pMax = 0.0939, mMin = 0, mMax = 0, bMin = 20, bMax = 40, scale = 1, shape = "around", radius = 1, chi = 1,
			fx = "ground_slam", vfx = "earth_spikes"
		},
		chilance = {
			id = 87, name = "Chi Lance", words = "kah lanc dhun", level = 120, mana = 145,
			vocations = {"Monk", "Shadowfist"}, school = "monk", power = "monk", ctype = "physical", pMin = 0.1572,
			pMax = 0.2515, mMin = 0, mMax = 0, bMin = 20, bMax = 40, scale = 1, shape = "line", range = 4, length = 4,
			finisher = true, fx = "shockwave", vfx = "ki_hit_blue"
		},
		cleavingheel = {
			id = 88, name = "Cleaving Heel", words = "kah rhim dhun", level = 150, mana = 60,
			vocations = {"Monk", "Iron Sage"}, school = "monk", power = "monk", ctype = "physical", pMin = 0.072,
			pMax = 0.1152, mMin = 0, mMax = 0, bMin = 20, bMax = 40, scale = 1, shape = "single", range = 1, chi = 1,
			melee = true, fx = "blood_slash", vfx = "punch_hit_red"
		},
		tidalpalm = {
			id = 89, name = "Tidal Palm", words = "drai hyr dhun", level = 190, mana = 75,
			vocations = {"Monk", "Iron Sage"}, school = "monk", power = "monk", ctype = "physical", pMin = 0.0776,
			pMax = 0.1242, mMin = 0, mMax = 0, bMin = 20, bMax = 40, scale = 1, shape = "wave", range = 2, depth = 2,
			halfWidth = 1, chi = 1, fx = "frost_ripple", vfx = "ki_hit_gold"
		},
		skysplitter = {
			id = 90, name = "Skysplitter Fist", words = "kah gal sol dhun", level = 250, mana = 220,
			vocations = {"Monk", "Shadowfist"}, school = "monk", power = "monk", ctype = "physical", pMin = 0.3086,
			pMax = 0.4938, mMin = 0, mMax = 0, bMin = 20, bMax = 40, scale = 1, shape = "single", range = 1,
			melee = true, finisher = true, fx = "meteor_strike", vfx = "aura_burst_red"
		},
		marrowbolt = {
			id = 106, name = "Marrow Bolt", words = "kah oss sag", level = 70, mana = 135,
			vocations = {"Necromancer", "Lich", "Bone Lord"}, school = "necro", power = "magic", ctype = "death",
			pMin = 0, pMax = 0, mMin = 5.915, mMax = 9.464, bMin = 20, bMax = 40, scale = 1, shape = "single",
			range = 7, shot = "skull_orb", pshot = "proj_blood_spike_necrotic", fx = "necro_skull", hitFx = "CONST_ME_MORTAREA"
		},
		wraithwind = {
			id = 107, name = "Wraithwind", words = "drai nyx vael", level = 90, mana = 180,
			vocations = {"Necromancer", "Lich", "Bone Lord"}, school = "necro", power = "magic", ctype = "death",
			pMin = 0, pMax = 0, mMin = 6.315, mMax = 10.104, bMin = 20, bMax = 40, scale = 1, shape = "wave", range = 3,
			depth = 3, halfWidth = 1, fx = "shadow_cloud", vfx = "plague_mist"
		},
		gravewail = {
			id = 112, name = "Gravewail", words = "drai oss ul", level = 110, mana = 200,
			vocations = {"Necromancer", "Lich", "Bone Lord"}, school = "necro", power = "magic", ctype = "death",
			pMin = 0, pMax = 0, mMin = 6.916, mMax = 11.066, bMin = 20, bMax = 40, scale = 1, shape = "circle",
			range = 7, radius = 2, fx = "blood_nova", vfx = "necro_seal"
		},
		blightbrand = {
			id = 113, name = "Blightbrand", words = "kah putr brak", level = 135, mana = 310,
			vocations = {"Necromancer", "Lich", "Bone Lord"}, school = "necro", power = "magic", ctype = "death",
			pMin = 0, pMax = 0, mMin = 1.949, mMax = 3.118, bMin = 8, bMax = 16, scale = 1, shape = "dot", range = 7,
			ticks = 6, tickMs = 1000, pshot = "proj_venom_glob_necrotic", fx = "poison_flame", hitFx = "CONST_ME_SMALLCLOUDS"
		},
		soulrendbeam = {
			id = 118, name = "Soulrend Beam", words = "kah nyx lanc", level = 170, mana = 270,
			vocations = {"Necromancer", "Lich", "Bone Lord"}, school = "necro", power = "magic", ctype = "death",
			pMin = 0, pMax = 0, mMin = 9.719, mMax = 15.55, bMin = 20, bMax = 40, scale = 1, shape = "line", range = 6,
			length = 6, pshot = "proj_flame_lance_spirit", fx = "void_eye", vfx = "void_rift"
		},
		cryptcollapse = {
			id = 119, name = "Crypt Collapse", words = "drai gal oss", level = 210, mana = 415,
			vocations = {"Necromancer", "Bone Lord"}, school = "necro", power = "magic", ctype = "death", pMin = 0,
			pMax = 0, mMin = 15.325, mMax = 24.52, bMin = 20, bMax = 40, scale = 1, shape = "circle", range = 7,
			radius = 2, fx = "ground_slam", vfx = "bone_burst"
		},
		ossuarysurge = {
			id = 120, name = "Ossuary Surge", words = "drai oss vael", level = 250, mana = 365,
			vocations = {"Bone Lord"}, school = "necro", power = "magic", ctype = "death", pMin = 0, pMax = 0,
			mMin = 13.324, mMax = 21.318, bMin = 20, bMax = 40, scale = 1, shape = "around", radius = 2,
			fx = "necro_skull", vfx = "bone_aura"
		},
		hallowedcut = {
			id = 121, name = "Hallowed Cut", words = "kah sol brak", level = 80, mana = 60,
			vocations = {"Templar", "Inquisitor", "Sentinel"}, school = "templar", power = "melee", ctype = "holy",
			pMin = 0.1345, pMax = 0.2152, mMin = 0.5, mMax = 0.8, bMin = 20, bMax = 40, scale = 1, shape = "single",
			range = 1, melee = true, fx = "holy_smite", vfx = "holy_hit"
		},
		censerswing = {
			id = 122, name = "Censer Swing", words = "drai sol hrak", level = 100, mana = 70,
			vocations = {"Templar", "Sentinel"}, school = "templar", power = "melee", ctype = "holy", pMin = 0.1246,
			pMax = 0.1994, mMin = 0.5, mMax = 0.8, bMin = 20, bMax = 40, scale = 1, shape = "around", radius = 1,
			fx = "holy_spiral", vfx = "holy_seal"
		},
		penitentlash = {
			id = 126, name = "Penitent Lash", words = "kah sol vael", level = 120, mana = 70,
			vocations = {"Templar", "Inquisitor"}, school = "templar", power = "melee", ctype = "holy", pMin = 0.1345,
			pMax = 0.2152, mMin = 0.5, mMax = 0.8, bMin = 20, bMax = 40, scale = 1, shape = "wave", range = 2,
			depth = 2, halfWidth = 1, fx = "holy_cross", vfx = "holy_smite"
		},
		martyrspyre = {
			id = 127, name = "Martyr's Pyre", words = "kah sol pyr", level = 140, mana = 70,
			vocations = {"Templar", "Sentinel"}, school = "templar", power = "melee", ctype = "holy", pMin = 0.0258,
			pMax = 0.0413, mMin = 0.5, mMax = 0.8, bMin = 8, bMax = 16, scale = 1, shape = "dot", range = 3, ticks = 5,
			tickMs = 1000, fx = "fire_ring", hitFx = "CONST_ME_HOLYDAMAGE"
		},
		bellofreckoning = {
			id = 128, name = "Bell of Reckoning", words = "drai sol krak", level = 160, mana = 80,
			vocations = {"Templar", "Inquisitor", "Sentinel"}, school = "templar", power = "melee", ctype = "holy",
			pMin = 0.1542, pMax = 0.2467, mMin = 0.5, mMax = 0.8, bMin = 20, bMax = 40, scale = 1, shape = "circle",
			range = 5, radius = 2, fx = "holy_cross", vfx = "dome_blast_holy"
		},
		lanceofvigil = {
			id = 129, name = "Lance of Vigil", words = "kah sol sag lanc", level = 190, mana = 90,
			vocations = {"Templar", "Inquisitor"}, school = "templar", power = "melee", ctype = "holy", pMin = 0.1739,
			pMax = 0.2782, mMin = 0.5, mMax = 0.8, bMin = 20, bMax = 40, scale = 1.1, shape = "line", range = 3,
			length = 3, shot = "holy_spear", fx = "holy_smite", vfx = "holy_hit"
		},
		sanctumverdict = {
			id = 131, name = "Sanctum Verdict", words = "kah sol judh brak", level = 230, mana = 145,
			vocations = {"Templar", "Sentinel"}, school = "templar", power = "melee", ctype = "holy", pMin = 0.3565,
			pMax = 0.5704, mMin = 0.5, mMax = 0.8, bMin = 20, bMax = 40, scale = 1, shape = "single", range = 2,
			fx = "holy_smite", vfx = "aura_burst_gold"
		},
		hereticsbrand = {
			id = 138, name = "Heretic's Brand", words = "kah sol putr", level = 90, mana = 90,
			vocations = {"Inquisitor"}, school = "templar", power = "melee", ctype = "holy", pMin = 0.2085,
			pMax = 0.3336, mMin = 0.5, mMax = 0.8, bMin = 20, bMax = 40, scale = 1, shape = "single", range = 3,
			shot = "holy_spear", fx = "holy_smite", vfx = "holy_hit"
		},
		zealotswrath = {
			id = 139, name = "Zealot's Wrath", words = "drai sol vael", level = 200, mana = 85,
			vocations = {"Inquisitor"}, school = "templar", power = "melee", ctype = "holy", pMin = 0.1591,
			pMax = 0.2546, mMin = 0.5, mMax = 0.8, bMin = 20, bMax = 40, scale = 1, shape = "around", radius = 2,
			fx = "holy_spiral", vfx = "aura_burst_gold"
		},
		bulwarkslam = {
			id = 140, name = "Bulwark Slam", words = "kah sol aeg", level = 110, mana = 60, vocations = {"Sentinel"},
			school = "templar", power = "melee", ctype = "holy", pMin = 0.1443, pMax = 0.2309, mMin = 0.5, mMax = 0.8,
			bMin = 20, bMax = 40, scale = 1, shape = "single", range = 1, melee = true, fx = "ground_slam",
			vfx = "blunt_smash"
		},
		rampartquake = {
			id = 141, name = "Rampart Quake", words = "drai sol aeg krak", level = 210, mana = 90,
			vocations = {"Sentinel"}, school = "templar", power = "melee", ctype = "holy", pMin = 0.1641, pMax = 0.2626,
			mMin = 0.5, mMax = 0.8, bMin = 20, bMax = 40, scale = 1, shape = "around", radius = 2, fx = "shockwave",
			vfx = "dome_blast_holy"
		},
		-- the converted supports (O254: the owner asked for faster, more fluid fights, more attack spells and fewer support
		-- spells). Each took the spell id of a weak support, so its icon cell stays; see server/data/spells/README.md
		-- "Support to attack (O254)". The coefficients are scaled from the class's comparable spell at the same level.
		bastioncry = {
			id = 29, name = "Bastion Cry", words = "vok gal rhov kor", level = 340, mana = 80,
			vocations = {"Warrior", "Juggernaut", "Berserker"}, school = "melee", power = "melee", ctype = "physical",
			pMin = 0.1538, pMax = 0.2461, mMin = 0, mMax = 0, bMin = 20, bMax = 40, scale = 1, shape = "wave", range = 3,
			depth = 3, halfWidth = 1, fx = "shockwave", vfx = "aura_burst_gold"
		},
		galevolley = {
			id = 134, name = "Gale Volley", words = "ruan vert", level = 240, mana = 110,
			vocations = {"Ranger", "Deadeye"}, school = "distance", power = "distance", ctype = "physical",
			pMin = 0.1352, pMax = 0.2163, mMin = 0, mMax = 0, bMin = 20, bMax = 40, scale = 1, shape = "line", range = 6,
			length = 6, shot = "gale_arrow", fx = "crit_burst"
		},
		crimsoncovenant = {
			id = 203, name = "Crimson Covenant", words = "tor nyx cruor", level = 200, mana = 450,
			vocations = {"Mystic", "Elementalist", "Illusionist"}, school = "magic", power = "magic", ctype = "death",
			pMin = 0, pMax = 0, mMin = 1.626, mMax = 2.602, bMin = 8, bMax = 16, scale = 1, shape = "dot", range = 6,
			ticks = 6, tickMs = 1000, pshot = "proj_shadow_bolt_blood", fx = "blood_nova", hitFx = "CONST_ME_DRAWBLOOD"
		},
		smokebomb = {
			id = 241, name = "Smoke Bomb", words = "drai nebh", level = 200, mana = 150,
			vocations = {"Thief", "Ninja", "Samurai"}, school = "spell", power = "blade", ctype = "earth",
			pMin = 0.1157, pMax = 0.1851, mMin = 0, mMax = 0, bMin = 20, bMax = 40, scale = 1, shape = "around", radius = 1,
			fx = "shadow_smoke", hitFx = "CONST_ME_POISONAREA"
		},
		splintervolley = {
			id = 193, name = "Splinter Volley", words = "vael oss sag", level = 270, mana = 400,
			vocations = {"Necromancer", "Lich", "Bone Lord"}, school = "necro", power = "magic", ctype = "death",
			pMin = 0, pMax = 0, mMin = 15.85, mMax = 25.36, bMin = 20, bMax = 40, scale = 1, shape = "circle", range = 6,
			radius = 1, fx = "necro_skull", vfx = "bone_burst"
		},
		mistbornestrike = {
			id = 67, name = "Mistborne Strike", words = "ash qhal", level = 190, mana = 150,
			vocations = {"Monk", "Shadowfist", "Iron Sage"}, school = "monk", power = "monk", ctype = "physical",
			pMin = 0.2076, pMax = 0.3322, mMin = 0, mMax = 0, bMin = 20, bMax = 40, scale = 1, shape = "wave", range = 3,
			depth = 3, halfWidth = 1, finisher = true, fx = "shadow_cloud", vfx = "ki_hit_blue"
		},
		crusaderssweep = {
			id = 250, name = "Crusader's Sweep", words = "vyr sol zel", level = 250, mana = 115,
			vocations = {"Templar", "Inquisitor", "Sentinel"}, school = "templar", power = "melee", ctype = "holy",
			pMin = 0.2154, pMax = 0.3446, mMin = 0.5, mMax = 0.8, bMin = 20, bMax = 40, scale = 1, shape = "wave", range = 2,
			depth = 3, halfWidth = 1, fx = "holy_cross", vfx = "holy_smite"
		},
		-- the level 500 spells of the line spell quests (spellquest_config.lua, server/README.md "Line spell quests"): one per class
		-- line, shared by the base class and both ascensions, needlearn="1" (only the quest teaches them, class_spells skips
		-- them). `quest = 1` marks them. Coefficients 1.25 x the line's 13 s spell, cooldown 13 s, mana 1.2 x; the ids are the
		-- first of each line's triple in spell_id_pool_config.lua (quest 2 and 3 take the next two).
		-- Trimmed 2026-10-28 (phase 3): the coefficients below were 1.25 x the reference and added 8 to 33% to the best set of a class; the
		-- owner wants about 4.5% (rotation_sim.py --quest), so each scale was cut (Keepfall 1.6 -> 0.98, Moonshard Rain 27.5 -> 9.4,
		-- Prismatic Rupture 1.5 -> 1.18, Eclipse Edge 1.25 -> 1, Soulflay Wave 1.25 -> 1.1, Thousand-Echo Palm 1.25 -> 0.65, Pyre of
		-- Absolution 1.25 -> 0.62) and each class has a factor on top (quest_spell_scale_config.lua).
		-- Keepfall: Headsman's Hurl x 1.28 x 1.25 = scale 1.6, trimmed
		keepfall = {
			id = 142, name = "Keepfall", words = "vok aeg thun brak", level = 500, mana = 30, quest = 1,
			vocations = {"Warrior", "Juggernaut", "Berserker"}, school = "melee", power = "melee", ctype = "physical",
			pMin = 0.17, pMax = 0.2, mMin = 0, mMax = 0, bMin = 17, bMax = 40, scale = 0.98, shape = "circle", range = 3,
			radius = 2, fx = "ground_slam", vfx = "heavy_cleave"
		},
		-- Moonshard Rain: 1.25 x ONE volley of Hail of Dawn (4 arrows x 1.1), not its whole cast of three: the whole cast, as an
		-- area, put the Ranger's best set +80% and pushed the distance weapon power to 2.1 (weapon_sim.py --power). Hail of Dawn
		-- is (level + ...) x 12 x 1.1, the level term at full level; the kit's level term is level / 5, so the scale carries the
		-- factor 5: 4 x 1.1 x 1.25 x 5 = 27.5 and every other term is the ref's divided by 5
		moonshardrain = {
			id = 149, name = "Moonshard Rain", words = "drai lun sag vex", level = 500, mana = 576, quest = 1,
			vocations = {"Ranger", "Deadeye", "Beastmaster"}, school = "distance", power = "distance", ctype = "physical",
			pMin = 0.0042, pMax = 0.0068, mMin = 0.1, mMax = 0.16, bMin = 3, bMax = 6, scale = 9.4, shape = "circle",
			range = 7, radius = 3, shot = "gale_arrow", fx = "crit_burst"
		},
		-- Prismatic Rupture: Falling Pyre x 1.2 x 1.25 = scale 1.5 (its burn is not part of it)
		prismaticrupture = {
			id = 152, name = "Prismatic Rupture", words = "drai zhul prys vael", level = 500, mana = 840, quest = 1,
			vocations = {"Mystic", "Elementalist", "Illusionist"}, school = "magic", power = "magic", ctype = "energy",
			pMin = 0, pMax = 0, mMin = 6.6, mMax = 10.8, bMin = 145, bMax = 265, scale = 1.18, shape = "circle", range = 7,
			radius = 2, fx = "arcane_burst", vfx = "arcane_hit"
		},
		-- Eclipse Edge: Last Breath x 1.25
		eclipseedge = {
			id = 155, name = "Eclipse Edge", words = "kah ecl nyx kaen", level = 500, mana = 180, quest = 1,
			vocations = {"Thief", "Ninja", "Samurai"}, school = "blade", power = "blade", ctype = "physical",
			pMin = 0.1808, pMax = 0.2893, mMin = 0, mMax = 0, bMin = 20, bMax = 40, scale = 1, shape = "line", range = 5,
			length = 5, fx = "blood_slash", vfx = "heavy_cleave", hitFx = "CONST_ME_DRAWBLOOD"
		},
		-- Soulflay Wave: Crypt Collapse x 1.25
		soulflaywave = {
			id = 158, name = "Soulflay Wave", words = "drai oss flay vael", level = 500, mana = 498, quest = 1,
			vocations = {"Necromancer", "Lich", "Bone Lord"}, school = "necro", power = "magic", ctype = "death",
			pMin = 0, pMax = 0, mMin = 15.325, mMax = 24.52, bMin = 20, bMax = 40, scale = 1.1, shape = "wave", range = 4,
			depth = 4, halfWidth = 2, fx = "shadow_cloud", vfx = "plague_mist"
		},
		-- Thousand-Echo Palm: Skysplitter Fist x 1.25, a finisher
		thousandechopalm = {
			id = 172, name = "Thousand-Echo Palm", words = "kah mil ech dhun", level = 500, mana = 264, quest = 1,
			vocations = {"Monk", "Shadowfist", "Iron Sage"}, school = "monk", power = "monk", ctype = "physical",
			pMin = 0.3086, pMax = 0.4938, mMin = 0, mMax = 0, bMin = 20, bMax = 40, scale = 0.65, shape = "wave", range = 3,
			depth = 3, halfWidth = 2, finisher = true, fx = "shockwave", vfx = "ki_hit_gold"
		},
		-- Pyre of Absolution: Sanctum Verdict x 1.25
		pyreofabsolution = {
			id = 177, name = "Pyre of Absolution", words = "kah sol pyr absl", level = 500, mana = 174, quest = 1,
			vocations = {"Templar", "Inquisitor", "Sentinel"}, school = "templar", power = "melee", ctype = "holy",
			pMin = 0.3565, pMax = 0.5704, mMin = 0.5, mMax = 0.8, bMin = 20, bMax = 40, scale = 0.62, shape = "circle",
			range = 5, radius = 2, fx = "fire_ring", vfx = "dome_blast_holy"
		},
		-- the level 1200 ultimates of the line spell quests (`quest = 3`; server/README.md "Line spell quests", server/data/spells/README.md
		-- "Line spell quests, level 1200 ultimates"): one per class line, shared by the base class and both ascensions, needlearn="1".
		-- the coefficients of the line's 13 s spell (the whole cast) x 3.5 first, cooldown 35 to 50 s, mana 3 x, off the cooldown ladder; the
		-- ids are the third of each line's triple in spell_id_pool_config.lua. They take no slot of the helper's 5 (rotation_sim.py
		-- `ultimate`). Scales fitted so that an ultimate adds 8 to 10% of the class's best-set damage per second at level 1200.
		-- Judgment of Iron: Colossus Fall (two blows) x 3.5 = one blow of scale 7 would add 15.5% of the best sets at level 1200: scale 4.7
		judgmentofiron = {
			id = 148, name = "Judgment of Iron", words = "vok aeg mor thun", level = 1200, mana = 285, quest = 3,
			vocations = {"Warrior", "Juggernaut", "Berserker"}, school = "melee", power = "melee", ctype = "physical",
			pMin = 0.052, pMax = 0.093, mMin = 0, mMax = 0, bMin = 20, bMax = 40, scale = 4.7, shape = "around", radius = 3,
			fx = "ground_slam", vfx = "aura_burst_red"
		},
		-- Dawnbreaker Shot: Sunspear x 3.5 added only 3.5% (the Ranger line's best sets are the strongest of the game): scale 6.6, a piercing line of 8
		dawnbreakershot = {
			id = 151, name = "Dawnbreaker Shot", words = "drai sol aur vyx", level = 1200, mana = 345, quest = 3,
			vocations = {"Ranger", "Deadeye", "Beastmaster"}, school = "distance", power = "distance", ctype = "holy",
			pMin = 0.1235, pMax = 0.1976, mMin = 0, mMax = 0, bMin = 20, bMax = 40, scale = 6.6, shape = "line", range = 8,
			length = 8, shot = "holy_spear", fx = "holy_smite", vfx = "holy_hit", vfx2 = "holy_smite"
		},
		-- Eclipse of Ruin: Glacial Doom (three waves of x 1.9) x 3.5 = one hit of scale 19.95 would add 37% (a circle of radius 4 on a
		-- 50 s cooldown, on the line with the weakest rotations): scale 6.4
		eclipseofruin = {
			id = 154, name = "Eclipse of Ruin", words = "drai ecl zhul vorn", level = 1200, mana = 4950, quest = 3,
			vocations = {"Mystic", "Elementalist", "Illusionist"}, school = "magic", power = "magic", ctype = "ice",
			pMin = 0, pMax = 0, mMin = 3.5, mMax = 6.5, bMin = 80, bMax = 160, scale = 6.4, shape = "circle", range = 7,
			radius = 5, vfx = "frost_nova", vfx2 = "storm_ring"
		},
		-- Death Between Heartbeats: Last Breath x 3.5 would add 19% (scale 2 x the critical hit 1.75); scale 1.2 x 1.75 = 2.1
		deathbetweenheartbeats = {
			id = 157, name = "Death Between Heartbeats", words = "kah nyx mor kaen", level = 1200, mana = 450, quest = 3,
			vocations = {"Thief", "Ninja", "Samurai"}, school = "blade", power = "blade", ctype = "physical",
			pMin = 0.1808, pMax = 0.2893, mMin = 0, mMax = 0, bMin = 20, bMax = 40, scale = 1.2, shape = "single", range = 1,
			melee = true, critAbove = {hp = 50, mult = 1.75}, fx = "crit_burst", vfx = "thrust", hitFx = "CONST_ME_DRAWBLOOD"
		},
		-- Funeral of Kings: Splinter Volley x 3.5 would add 18%: scale 2, a circle of radius 4
		funeralofkings = {
			id = 160, name = "Funeral of Kings", words = "drai oss mor kyng", level = 1200, mana = 1200, quest = 3,
			vocations = {"Necromancer", "Lich", "Bone Lord"}, school = "necro", power = "magic", ctype = "death",
			pMin = 0, pMax = 0, mMin = 15.85, mMax = 25.36, bMin = 20, bMax = 40, scale = 2, shape = "circle", range = 6,
			radius = 5, vfx = "bone_burst"
		},
		-- Heaven's Ninth Gate: Skysplitter Fist x 3.5 would add 14.5%: scale 2.5, a finisher: the fist hits with the chi spent
		heavensninthgate = {
			id = 174, name = "Heaven's Ninth Gate", words = "kah nin dhun sol", level = 1200, mana = 660, quest = 3,
			vocations = {"Monk", "Shadowfist", "Iron Sage"}, school = "monk", power = "monk", ctype = "physical",
			pMin = 0.3086, pMax = 0.4938, mMin = 0, mMax = 0, bMin = 20, bMax = 40, scale = 2.5, shape = "single", range = 1,
			melee = true, finisher = true, fx = "meteor_strike", vfx = "aura_burst_red"
		},
		-- Hammer of Ember Dawn: Sanctum Verdict x 3.5 on the target (main = 2 x scale 1.75) would add 19%: the target takes 2 x scale 1 =
		-- 2 x Sanctum Verdict, every other enemy within 2 sqm of it half of that
		hammerofemberdawn = {
			id = 237, name = "Hammer of Ember Dawn", words = "kah sol emb hamr", level = 1200, mana = 435, quest = 3,
			vocations = {"Templar", "Inquisitor", "Sentinel"}, school = "templar", power = "melee", ctype = "holy",
			pMin = 0.3565, pMax = 0.5704, mMin = 0.5, mMax = 0.8, bMin = 20, bMax = 40, scale = 1, shape = "circle", range = 3,
			radius = 2, main = 2, vfx = "dome_blast_holy", vfx2 = "aura_burst_gold"
		},
	},
	order = {"gorehook", "riftcleaver", "sunspear", "arrowstorm", "packdart", "phantomneedles", "mirrorshards", "dreamrot", "guttingslash", "razorrain", "venomspiral", "crescentcut", "lastbreath", "hollowknuckle", "quakingstomp", "chilance", "cleavingheel", "tidalpalm", "skysplitter", "marrowbolt", "wraithwind", "gravewail", "blightbrand", "soulrendbeam", "cryptcollapse", "ossuarysurge", "hallowedcut", "censerswing", "penitentlash", "martyrspyre", "bellofreckoning", "lanceofvigil", "sanctumverdict", "hereticsbrand", "zealotswrath", "bulwarkslam", "rampartquake", "bastioncry", "galevolley", "crimsoncovenant", "smokebomb", "splintervolley", "mistbornestrike", "crusaderssweep", "keepfall", "moonshardrain", "prismaticrupture", "eclipseedge", "soulflaywave", "thousandechopalm", "pyreofabsolution", "judgmentofiron", "dawnbreakershot", "eclipseofruin", "deathbetweenheartbeats", "funeralofkings", "heavensninthgate", "hammerofemberdawn"},
}
