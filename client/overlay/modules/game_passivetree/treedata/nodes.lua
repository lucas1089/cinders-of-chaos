--- Example for 1 node for many vocations:
--- 
--- ---- 2 ---
		-- {
		-- 	orbit = 3,
		-- 	orbitDist = 128,
		-- 	group = 1,
		-- 	orbitIndex = 210,
		-- 	sorcerer = {
		-- 		icon = "baseStat",
		-- 		name = "Mage's Wisdom",
		-- 		customStats = {
		-- 			magicLevel = 5,
		-- 		}
		-- 	},
		-- 	druid = {
		-- 		icon = "baseStat",
		-- 		name = "Druid's Initiation",
		-- 		customStats = {
		-- 			healing = 15,
		-- 			manaPercent = 80
		-- 		}
		-- 	},
		-- 	knight = {
		-- 		icon = "baseStat",
		-- 		name = "Warrior's Soul",
		-- 		customStats = {
		-- 			healthPercent = 80,
		-- 			damage = 40
		-- 		}
		-- 	},
		-- 	paladin = {
		-- 		icon = "baseStat",
		-- 		name = "Bowman's Aim",
		-- 		customStats = {
		-- 			criticalHitChance = 50,
		-- 			criticalDamage = 80
		-- 		}
		-- 	},
		-- 	illusionist = {
		-- 		icon = "baseStat",
		-- 		name = "Mage's Wisdom",
		-- 		customStats = {
		-- 			strength = 2,
		-- 		}
		-- 	},
		-- 	inputs = {
		-- 		1
		-- 	},
		-- 	out = {
		-- 		9, 30
		-- 	}
		-- },
		-- 	monk = {
		-- 		icon = "baseStat",
		-- 		name = "Mage's Wisdom",
		-- 		customStats = {
		-- 			strength = 2,
		-- 		}
		-- 	},
		-- 	inputs = {
		-- 		1
		-- 	},
		-- 	out = {
		-- 		9, 30
		-- 	}
		-- },




function getTreeNodes()
	return {
		--- 1 ---
		{	
			isStartNode = true,
			group = 1,
			icon = "startNode",
			inputs = {},
			out = {
				2
			}
		},
		---- 2 ---
		{
			orbit = 3,
			orbitDist = 128,
			group = 1,
			orbitIndex = 210,
			icon = "strength",
			name = "Attribute",
			customStats = {
				strength = 1,
			},
			inputs = {
				1
			},
			out = {
				9, 30
			}
		},
		--- 3 ---
		{
			orbit = 3,
			orbitDist = 130,
			name = "Attribute",
			orbitIndex = 150,
			group = 1,
			icon = "dexterity",
			customStats = {
				dexterity = 1,
			},
			inputs = {
				1
			},
			out = {
				8, 32
			}
		},
		--- 4 ---
		{
			orbit = 3,
			orbitDist = 132,
			name = "Attribute",
			orbitIndex = 270,
			group = 1,
			icon = "life",
			customStats = {
				vitality = 1,
			},
			inputs = {
				1
			},
			out = {
				14, 29
			}
		},
		--- 5 ---
		{
			orbit = 3,
			orbitDist = 130,
			name = "Attribute",
			orbitIndex = -30,
			group = 1,
			icon = "cooldownRecovery",
			customStats = {
				wisdom = 1,
			},
			inputs = {
				1
			},
			out = {
				17, 26
			}
		},
		--- 6 ---
		{
			orbit = 3,
			orbitDist = 130,
			name = "Attribute",
			orbitIndex = 30,
			group = 1,
			icon = "mana",
			customStats = {
				spirit = 1,
			},
			inputs = {
				1
			},
			out = {
				23, 27
			}
		},
		--- 7 ---
		{
			orbit = 3,
			orbitDist = 132,
			name = "Attribute",
			orbitIndex = -270,
			group = 1,
			icon = "intelligence",
			customStats = {
				intelligence = 1,
			},
			inputs = {
				1
			},
			out = {
				20, 33
			}
		},
		--- 8 ---
		{
			orbit = 1,
			orbitDist = 70,
			name = "Drown Damage",
			orbitIndex = -330,
			group = 2,
			icon = "drownDamage",
			customStats = {
				incrementDrown = 2,
			},
			inputs = {
				3
			},
			out = {
				10
			}
		},
		--- 9 ---
		{
			orbit = 1,
			orbitDist = 70,
			name = "Physical Damage",
			orbitIndex = 330,
			group = 2,
			icon = "physicalDamage",
			customStats = {
				incrementPhysical = 2,
			},
			inputs = {
				2
			},
			out = {
				11
			}
		},
		--- 10 ---
		{
			orbit = 1,
			orbitDist = 75,
			name = "Drown Absorption",
			orbitIndex = -270,
			group = 2,
			icon = "absorbDrown",
			customStats = {
				absorbDrown = 1,
			},
			inputs = {
				8
			},
			out = {
				12, 104
			}
		},
		--- 11 ---
		{
			orbit = 1,
			orbitDist = 75,
			name = "Physical Absorption",
			orbitIndex = 270,
			group = 2,
			icon = "absorbPhysical",
			customStats = {
				absorbPhysical = 1,
			},
			inputs = {
				9
			},
			out = {
				13, 101
			}
		},
		--- 12 ---
		{
			orbit = 1,
			orbitDist = 75,
			name = "Attribute",
			orbitIndex = -210,
			group = 2,
			icon = "dexterity",
			customStats = {
				dexterity = 1,
			},
			inputs = {
				10
			},
			out = {
				61
			}
		},
		--- 13 ---
		{
			orbit = 1,
			orbitDist = 75,
			name = "Attribute",
			orbitIndex = 210,
			group = 2,
			icon = "strength",
			customStats = {
				strength = 1,
			},
			inputs = {
				11
			},
			out = {
				61
			}
		},
		--- 14 ---
		{
			orbit = 1,
			orbitDist = 72,
			name = "Arcane Damage",
			orbitIndex = 146,
			group = 3,
			icon = "arcaneDamage",
			customStats = {
				incrementArcane = 2,
			},
			inputs = {
				4
			},
			out = {
				15
			}
		},
		--- 15 ---
		{
			orbit = 1,
			orbitDist = 70,
			name = "Arcane Absorption",
			orbitIndex = 211,
			group = 3,
			icon = "absorbArcane",
			customStats = {
				absorbArcane = 1,
			},
			inputs = {
				14
			},
			out = {
				16
			}
		},
		--- 16 ---
		{
			orbit = 1,
			orbitDist = 70,
			name = "Attribute",
			orbitIndex = 275,
			group = 3,
			icon = "life",
			customStats = {
				vitality = 1,
			},
			inputs = {
				15
			},
			out = {
				70
			}
		},
		--- 17 ---
		{
			orbit = 1,
			orbitDist = 72,
			name = "Ice Damage",
			orbitIndex = 445,
			group = 3,
			icon = "coldDamage",
			customStats = {
				incrementIce = 2,
			},
			inputs = {
				5
			},
			out = {
				18
			}
		},
		--- 18 ---
		{
			orbit = 1,
			orbitDist = 70,
			name = "Ice Absorption",
			orbitIndex = 388,
			group = 3,
			icon = "absorbIce",
			customStats = {
				absorbIce = 1,
			},
			inputs = {
				17
			},
			out = {
				19, 95
			}
		},
		--- 19 ---
		{
			orbit = 1,
			orbitDist = 70,
			name = "Attribute",
			orbitIndex = 334,
			group = 3,
			icon = "cooldownRecovery",
			customStats = {
				wisdom = 1,
			},
			inputs = {
				18
			},
			out = {
				70
			}
		},
		--- 20 ---
		{
			orbit = 1,
			orbitDist = 70,
			name = "Fire Damage",
			orbitIndex = 209,
			group = 4,
			icon = "fireDamage",
			customStats = {
				incrementFire = 2,
			},
			inputs = {
				7
			},
			out = {
				21
			}
		},
		--- 21 ---
		{
			orbit = 1,
			orbitDist = 72,
			name = "Absorption Fire Damage",
			orbitIndex = 148,
			group = 4,
			icon = "absorbFire",
			customStats = {
				absorbFire = 1,
			},
			inputs = {
			   20
			},
			out = {
			    22
			}
		},
		--- 22 ---
		{
			orbit = 1,
			orbitDist = 70,
			name = "Attribute",
			orbitIndex = 88,
			group = 4,
			icon = "intelligence",
			customStats = {
				intelligence = 1,
			},
			inputs = {
				21
			},
			out = {
				63
			}
		},
		--- 23 ---
		{
			orbit = 1,
			orbitDist = 70,
			name = "Death Damage",
			orbitIndex = 270,
			group = 4,
			icon = "deathDamage",
			customStats = {
				incrementDeath = 2,
			},
			inputs = {
				6
			},
			out = {
				24
			}
		},
		--- 24 ---
		{
			orbit = 1,
			orbitDist = 70,
			name = "Death Absorption",
			orbitIndex = 330,
			group = 4,
			icon = "absorbDeath",
			customStats = {
				absorbDeath = 1,
			},
			inputs = {
				23
			},
			out = {
				25, 98
			}
		},
		--- 25 ---
		{
			orbit = 1,
			orbitDist = 70,
			name = "Attribute",
			orbitIndex = 390,
			group = 4,
			icon = "mana",
			customStats = {
				spirit = 1,
			},
			inputs = {
				24
			},
			out = {
				63
			}
		},
		--- 26 ---
		{
			orbit = 1,
			orbitDist = 37,
			name = "Energy Damage",
			orbitIndex = 260,
			group = 5,
			icon = "lightningDamage",
			customStats = {
				incrementEnergy = 2,
			},
			inputs = {
				5
			},
			out = {
				28
			}
		},
		--- 27 ---
		{
			orbit = 1,
			orbitDist = 37,
			name = "Health Increment",
			orbitIndex = 100,
			group = 5,
			icon = "healthDamage",
			customStats = {
				incrementHealth = 2,
			},
			inputs = {
				6
			},
			out = {
				28
			}
		},
		--- 28 ---
		{
			orbit = 1,
			orbitDist = 39,
			name = "Energy Absorption",
			orbitIndex = 362,
			group = 5,
			icon = "absorbEnergy",
			customStats = {
				absorbEnergy = 1,
			},
			inputs = {
				26, 27
			},
			out = {
				58
			}
		},
		--- 29 ---
		{
			orbit = 1,
			orbitDist = 39,
			name = "Life & Mana Drain Damage",
			orbitIndex = 362,
			group = 6,
			icon = "lifeManaDrain",
			customStats = {
				incrementLifeDrain = 2,
				incrementManaDrain = 2,
			},
			inputs = {
				4
			},
			out = {
				31
			}
		},
		--- 30 ---
		{
			orbit = 1,
			orbitDist = 39,
			name = "Water Damage",
			orbitIndex = 120,
			group = 6,
			icon = "waterDamage",
			customStats = {
				incrementWater = 2,
			},
			inputs = {
				2
			},
			out = {
				31
			}
		},
		--- 31 ---
		{
			orbit = 1,
			orbitDist = 39,
			name = "Water Absorption",
			orbitIndex = 239,
			group = 6,
			icon = "absorbWater",
			customStats = {
				absorbWater = 1,
			},
			inputs = {
				30, 29
			},
			out = {
				43
			}
		},
		--- 32 ---
		{
			orbit = 1,
			orbitDist = 39,
			name = "Holy Damage",
			orbitIndex = 239,
			group = 7,
			icon = "holyDamage",
			customStats = {
				incrementHoly = 2,
			},
			inputs = {
				3
			},
			out = {
				34
			}
		},
		--- 33 ---
		{
			orbit = 1,
			orbitDist = 39,
			name = "Earth Damage",
			orbitIndex = 0,
			group = 7,
			icon = "earthDamage",
			customStats = {
				incrementEarth = 2,
			},
			inputs = {
				7
			},
			out = {
				34
			}
		},
		--- 34 ---
		{
			orbit = 1,
			orbitDist = 41,
			name = "Holy Absorption",
			orbitIndex = 120,
			group = 7,
			icon = "absorbHoly",
			customStats = {
				absorbHoly = 1,
			},
			inputs = {
				32, 33
			},
			out = {
				35
			}
		},
		--- 35 ---
		{
			orbit = 2,
			orbitDist = 115,
			name = "Attribute",
			orbitIndex = 300,
			group = 8,
			icon = "dexterity",
			customStats = {
				dexterity = 1,
			},
			inputs = {
			  	34
			},
			out = {
			 	36, 39
			}
		},
		--- 36 ---
		{
			orbit = 2,
			orbitDist = 115,
			name = "Attribute",
			orbitIndex = 240,
			group = 8,
			icon = "intelligence",
			customStats = {
				intelligence = 1,
			},
			inputs = {
				35
			},
			out = {
				37
			}
		},
		--- 37 ---
		{
			orbit = 1,
			orbitDist = 115,
			name = "Attribute",
			orbitIndex = 210,
			group = 8,
			icon = "dexterity",
			customStats = {
				dexterity = 1,
			},
			inputs = {
				36
			},
			out = {
				38, 74, 84
			}
		},
		--- 38 ---
		{
			orbit = 2,
			orbitDist = 115,
			name = "Attribute",
			orbitIndex = 180,
			group = 8,
			icon = "intelligence",
			customStats = {
				intelligence = 1,
			},
			inputs = {
				37
			},
			out = {
				42
			}
		},
		--- 39 ---
		{
			orbit = 2,
			orbitDist = 118,
			name = "Attribute",
			orbitIndex = 360,
			group = 8,
			icon = "intelligence",
			customStats = {
				intelligence = 1,
			},
			inputs = {
				35
			},
			out = {
				40
			}
		},
		--- 40 ---
		{
			orbit = 1,
			orbitDist = 118,
			name = "Attribute",
			orbitIndex = 30,
			group = 8,
			icon = "dexterity",
			customStats = {
				dexterity = 1,
			},
			inputs = {
				39
			},
			out = {
				41, 73, 84
			}
		},
		--- 41 ---
		{
			orbit = 2,
			orbitDist = 118,
			name = "Attribute",
			orbitIndex = 60,
			group = 8,
			icon = "intelligence",
			customStats = {
				intelligence = 1,
			},
			inputs = {
				40
			},
			out = {
				42
			}
		},
		--- 42 ---
		{
			orbit = 2,
			orbitDist = 115,
			name = "Attribute",
			orbitIndex = 120,
			group = 8,
			icon = "dexterity",
			customStats = {
				dexterity = 1,
			},
			inputs = {
			  38, 41
			},
			out = {
				129
			}
		},
		--- 43 ---
		{
			orbit = 2,
			orbitDist = 115,
			name = "Attribute",
			orbitIndex = 60,
			group = 9,
			icon = "life",
			customStats = {
				vitality = 1,
			},
			inputs = {
			  	31
			},
			out = {
			 	44, 47
			}
		},
		--- 44 ---
		{
			orbit = 2,
			orbitDist = 115,
			name = "Attribute",
			orbitIndex = 0,
			group = 9,
			icon = "strength",
			customStats = {
				strength = 1,
			},
			inputs = {
				43
			},
			out = {
				45
			}
		},
		--- 45 ---
		{
			orbit = 1,
			orbitDist = 115,
			name = "Attribute",
			orbitIndex = 330,
			group = 9,
			icon = "life",
			customStats = {
				vitality = 1,
			},
			inputs = {
				44
			},
			out = {
				46, 72, 85
			}
		},
		--- 46 ---
		{
			orbit = 2,
			orbitDist = 115,
			name = "Attribute",
			orbitIndex = 300,
			group = 9,
			icon = "strength",
			customStats = {
				strength = 1,
			},
			inputs = {
				45
			},
			out = {
				50
			}
		},
		--- 47 ---
		{
			orbit = 2,
			orbitDist = 118,
			name = "Attribute",
			orbitIndex = 120,
			group = 9,
			icon = "strength",
			customStats = {
				strength = 1,
			},
			inputs = {
				43
			},
			out = {
				48
			}
		},
		--- 48 ---
		{
			orbit = 1,
			orbitDist = 118,
			name = "Attribute",
			orbitIndex = 150,
			group = 9,
			icon = "life",
			customStats = {
				vitality = 1,
			},
			inputs = {
				47
			},
			out = {
				49, 76, 85
			}
		},
		--- 49 ---
		{
			orbit = 2,
			orbitDist = 118,
			name = "Attribute",
			orbitIndex = 180,
			group = 9,
			icon = "strength",
			customStats = {
				strength = 1,
			},
			inputs = {
				48
			},
			out = {
				50
			}
		},
		--- 50 ---
		{
			orbit = 2,
			orbitDist = 115,
			name = "Attribute",
			orbitIndex = 240,
			group = 9,
			icon = "life",
			customStats = {
				vitality = 1,
			},
			inputs = {
			  49, 46
			},
			out = {
				115
			}
		},
		--- 51 ---
		{
			orbit = 2,
			orbitDist = 115,
			name = "Attribute",
			orbitIndex = 1,
			group = 10,
			icon = "cooldownRecovery",
			customStats = {
				wisdom = 1,
			},
			inputs = {
			  52, 55
			},
			out = {
			  209, 206
			}
		},
		--- 52 ---
		{
			orbit = 2,
			orbitDist = 115,
			name = "Attribute",
			orbitIndex = -59,
			group = 10,
			icon = "mana",
			customStats = {
				spirit = 1,
			},
			inputs = {
				53
			},
			out = {
				51
			}
		},
		--- 53 ---
		{
			orbit = 1,
			orbitDist = 115,
			name = "Attribute",
			orbitIndex = 270,
			group = 10,
			icon = "cooldownRecovery",
			customStats = {
				wisdom = 1,
			},
			inputs = {
				54
			},
			out = {
				52, 71, 83
			}
		},
		--- 54 ---
		{
			orbit = 2,
			orbitDist = 115,
			name = "Attribute",
			orbitIndex = 240,
			group = 10,
			icon = "mana",
			customStats = {
				spirit = 1,
			},
			inputs = {
				58
			},
			out = {
				53
			}
		},
		--- 55 ---
		{
			orbit = 2,
			orbitDist = 118,
			name = "Attribute",
			orbitIndex = 60,
			group = 10,
			icon = "mana",
			customStats = {
				spirit = 1,
			},
			inputs = {
				56
			},
			out = {
				51
			}
		},
		--- 56 ---
		{
			orbit = 1,
			orbitDist = 118,
			name = "Attribute",
			orbitIndex = 90,
			group = 10,
			icon = "cooldownRecovery",
			customStats = {
				wisdom = 1,
			},
			inputs = {
				57
			},
			out = {
				55, 75, 83
			}
		},
		--- 57 ---
		{
			orbit = 2,
			orbitDist = 118,
			name = "Attribute",
			orbitIndex = 120,
			group = 10,
			icon = "mana",
			customStats = {
				spirit = 1,
			},
			inputs = {
				58
			},
			out = {
				56
			}
		},
		--- 58 ---
		{
			orbit = 2,
			orbitDist = 115,
			name = "Attribute",
			orbitIndex = 180,
			group = 10,
			icon = "cooldownRecovery",
			customStats = {
				wisdom = 1,
			},
			inputs = {
			    28
			},
			out = {
				54, 57
			}
		},
		--- 59 ---
		{
			orbit = 1,
			orbitDist = 50,
			name = "Attribute",
			orbitIndex = 270,
			group = 11,
			icon = "jewelsmithSkill",
			customStats = {
				jewelsmithSkill = 1,
			},
			inputs = {
				61
			},
			out = {
				62, 76
			}
		},
		--- 60 ---
		{
			orbit = 1,
			orbitDist = 50,
			name = "Attribute",
			orbitIndex = 90,
			group = 11,
			icon = "armorsmithSkill",
			customStats = {
				armorsmithSkill = 1,
			},
			inputs = {
				61
			},
			out = {
				62, 74
			}
		},
		--- 61 ---
		{
			orbit = 1,
			orbitDist = 50,
			name = "Attribute",
			orbitIndex = 362,
			group = 11,
			icon = "weaponsmithSkill",
			customStats = {
				weaponsmithSkill = 1,
			},
			inputs = {
				12, 13
			},
			out = {
				59, 60	
			}
		},
		--- 62 ---
		{
			orbit = 1,
			orbitDist = 50,
			name = "Attribute",
			orbitIndex = 180,
			group = 11,
			icon = "herbalistSkill",
			customStats = {
				herbalistSkill = 1,
				craftingSkill = 1
			},
			inputs = {
				60, 59
			},
			out = {
				198, 201
			}
		},
		--- 63 ---
		{
			orbit = 1,
			orbitDist = 50,
			name = "Attribute",
			orbitIndex = 240,
			group = 12,
			icon = "herbalistSkill",
			customStats = {
				herbalistSkill = 1,
			},
			inputs = {
				22, 25
			},
			out = {
				65, 66
			}
		},
		--- 64 ---
		{
			orbit = 1,
			orbitDist = 50,
			name = "Attribute",
			orbitIndex = 60,
			group = 12,
			icon = "miningSkill",
			customStats = {
				miningSkill = 1,
				craftingSkill = 1
			},
			inputs = {
				66, 65
			},
			out = {
				122
			}
		},
		--- 65 ---
		{
			orbit = 1,
			orbitDist = 50,
			name = "Attribute",
			orbitIndex = 332,
			group = 12,
			icon = "jewelsmithSkill",
			customStats = {
				jewelsmithSkill = 1,
			},
			inputs = {
				63
			},
			out = {
				64, 75
			}
		},
		--- 66 ---
		{
			orbit = 1,
			orbitDist = 50,
			name = "Attribute",
			orbitIndex = 150,
			group = 12,
			icon = "woodcuttingSkill",
			customStats = {
				woodcuttingSkill = 1,
			},
			inputs = {
				63
			},
			out = {
				64, 73
			}
		},
		--- 67 ---
		{
			orbit = 1,
			orbitDist = 50,
			name = "Attribute",
			orbitIndex = 220,
			group = 13,
			icon = "miningSkill",
			customStats = {
				miningSkill = 1,
			},
			inputs = {
				70
			},
			out = {
				69, 72
			}
		},
		--- 68 ---
		{
			orbit = 1,
			orbitDist = 50,
			name = "Attribute",
			orbitIndex = 40,
			group = 13,
			icon = "woodcuttingSkill",
			customStats = {
				woodcuttingSkill = 1,
			},
			inputs = {
				70
			},
			out = {
			 	69, 71
			}
		},
		--- 69 ---
		{
			orbit = 1,
			orbitDist = 50,
			name = "Attribute",
			orbitIndex = 312,
			group = 13,
			icon = "armorsmithSkill",
			customStats = {
				armorsmithSkill = 1,
				craftingSkill = 1
			},
			inputs = {
				67, 68
			},
			out = {
				113
			}
		},
		--- 70 ---
		{
			orbit = 1,
			orbitDist = 50,
			name = "Attribute",
			orbitIndex = 130,
			group = 13,
			icon = "weaponsmithSkill",
			customStats = {
				weaponsmithSkill = 1,
			},
			inputs = {
				16, 19
			},
			out = {
				67, 68
			}
		},
		--- 71 ---
		{
			orbit = 0,
			orbitDist = 3,
			name = "Attribute",
			orbitIndex = 30,
			group = 14,
			isRare = true,
			icon = "clubSkill",
			customStats = {
				clubSkill = 2,
			},
			inputs = {
				53,68
			},
			out = {
				78, 264
			}
		},
		--- 72 ---
		{
			orbit = 0,
			orbitDist = 3,
			name = "Attribute",
			orbitIndex = 60,
			group = 15,
			isRare = true,
			icon = "axeSkill",
			customStats = {
				axeSkill = 2,
			},
			inputs = {
				45, 67 
			},
			out = {
				79, 86, 88
			}
		},
		--- 73 ---
		{
			orbit = 0,
			orbitDist = 3,
			name = "Attribute",
			orbitIndex = 60,
			group = 16,
			isRare = true,
			icon = "magicSkill",
			customStats = {
				magicSkill = 2,
			},
			inputs = {
				40, 66
			},
			out = {
				80, 93, 91
			}
		},
		--- 74 ---
		{
			orbit = 0,
			orbitDist = 3,
			name = "Attribute",
			orbitIndex = 60,
			group = 17,
			isRare = true,
			icon = "distanceSkill",
			customStats = {
				distanceSkill = 2,
			},
			inputs = {
				37, 60
			},
			out = {
				82, 269
			}
		},
		--- 75 ---
		{
			orbit = 0,
			orbitDist = 3,
			name = "Attribute",
			orbitIndex = 60,
			group = 18,
			isRare = true,
			icon = "shieldingSkill",
			customStats = {
				shieldingSkill = 2,
			},
			inputs = {
				56, 65
			},
			out = {
				77, 268
			}
		},
		--- 76 ---
		{
			orbit = 0,
			orbitDist = 3,
			name = "Attribute",
			orbitIndex = 40,
			group = 19,
			isRare = true,
			icon = "swordSkill",
			customStats = {
				swordSkill = 2,
			},
			inputs = {
				48, 59
			},
			out = {
				81, 272
			}
		},
		--- 77 ---
		{
			orbit = 0,
			orbitDist = 0,
			name = "Attribute",
			orbitIndex = 0,
			group = 20,
			icon = "manaLeechChance",
			customStats = {
				manaLeechChance = 1,
				manaLeechAmount = 2
			},
			inputs = {
				75
			},
			out = {
				
			}
		},
		--- 78 ---
		{
			orbit = 0,
			orbitDist = 0,
			name = "Attribute",
			orbitIndex = 0,
			group = 21,
			icon = "criticalHitChance",
			customStats = {
				criticalHitChance = 1,
				criticalHitAmount = 1
			},
			inputs = {
				71
			},
			out = {
				
			}
		},
		--- 79 ---
		{
			orbit = 0,
			orbitDist = 0,
			name = "Attribute",
			orbitIndex = 0,
			group = 22,
			icon = "life",
			customStats = {
				vitality = 5,
			},
			inputs = {
				72
			},
			out = {
				108, 109
			}
		},
		--- 80 ---
		{
			orbit = 0,
			orbitDist = 0,
			name = "Attribute",
			orbitIndex = 0,
			group = 23,
			icon = "intelligence",
			customStats = {
				intelligence = 5,
			},
			inputs = {
				73
			},
			out = {
				106, 107
			}
		},
		--- 81 ---
		{
			orbit = 0,
			orbitDist = 0,
			name = "Attribute",
			orbitIndex = 0,
			group = 24,
			icon = "lifeLeechChance",
			customStats = {
				lifeLeechChance = 1,
				lifeLeechAmount = 2,
			},
			inputs = {
				76
			},
			out = {
				
			}
		},
		--- 82 ---
		{
			orbit = 0,
			orbitDist = 0,
			name = "Attribute",
			orbitIndex = 0,
			group = 25,
			icon = "criticalHitChance",
			customStats = {
				criticalHitChance = 1,
				criticalHitAmount = 1
			},
			inputs = {
				74
			},
			out = {
				
			}
		},
		--- 83 ---
		{
			orbit = 0,
			orbitDist = 0,
			name = "Orion Horizon",
			isRare = true,
			orbitIndex = 0,
			group = 10,
			icon = "orionHorizon",
			customStats = {
				experience = 10,
				incrementHealth = 3,
				incrementEnergy = 3,
				absorbEnergy = 2
			},
			inputs = {
			  53, 56
			},
			out = {
			  
			}
		},
		--- 84 ---
		{
			orbit = 0,
			orbitDist = 3,
			name = "Fulgured Dream",
			orbitIndex = 0,
			isRare = true,
			group = 8,
			icon = "fulguredDream",
			customStats = {
				absorbEarth = 3,
				incrementEarth = 2,
				incrementHoly = 2,
				loot = 10,
			},
			inputs = {
			  	37, 40
			},
			out = {
			}
		},
		--- 85 ---
		{
			orbit = 0,
			orbitDist = 2,
			name = "Ball and Chain",
			orbitIndex = 0,
			isRare = true,
			group = 9,
			icon = "ballAndChain",
			customStats = {
				incrementWater = 3,
				incrementLifeDrain = 3,
				incrementManaDrain = 3,
				absorbWater = 2,
				rarityLoot = 1,
			},
			inputs = {
			  	45, 48
			},
			out = {
			}
		},
		--- 86 ---
		{
			orbit = 1,
			orbitDist = 72,
			name = "Attribute",
			orbitIndex = 146,
			group = 26,
			icon = "life",
			customStats = {
				vitality = 2,
			},
			inputs = {
				72
			},
			out = {
				87
			}
		},
		--- 87 ---
		{
			orbit = 1,
			orbitDist = 70,
			name = "Attribute",
			orbitIndex = 211,
			group = 26,
			icon = "life",
			customStats = {
				vitality = 2,
			},
			inputs = {
				86
			},
			out = {
				130
			}
		},
		--- 88 ---
		{
			orbit = 1,
			orbitDist = 72,
			name = "Attribute",
			orbitIndex = 390,
			group = 26,
			icon = "life",
			customStats = {
				vitality = 2,
			},
			inputs = {
				89, 72
			},
			out = {
			    	
			}
		},
		--- 89 ---
		{
			orbit = 1,
			orbitDist = 70,
			name = "Attribute",
			orbitIndex = 334,
			group = 26,
			icon = "life",
			customStats = {
				vitality = 2,
			},
			inputs = {
				
			},
			out = {
				88, 131
			}
		},
		--- 90 ---
		{
			orbit = 1,
			orbitDist = 72,
			name = "Attribute",
			orbitIndex = 146,
			group = 27,
			icon = "intelligence",
			customStats = {
				intelligence = 2,
			},
			inputs = {
				91
			},
			out = {
				132
			}
		},
		--- 91 ---
		{
			orbit = 1,
			orbitDist = 70,
			name = "Attribute",
			orbitIndex = 211,
			group = 27,
			icon = "intelligence",
			customStats = {
				intelligence = 2,
			},
			inputs = {
				73
			},
			out = {
				90
			}
		},
		--- 92 ---
		{
			orbit = 1,
			orbitDist = 72,
			name = "Attribute",
			orbitIndex = 390,
			group = 27,
			icon = "intelligence",
			customStats = {
				intelligence = 2,
			},
			inputs = {
				93
			},
			out = {
				133
			}
		},
		--- 93 ---
		{
			orbit = 1,
			orbitDist = 70,
			name = "Attribute",
			orbitIndex = 334,
			group = 27,
			icon = "intelligence",
			customStats = {
				intelligence = 2,
			},
			inputs = {
				73
			},
			out = {
				92
			}
		},
		--- 94 ---
		{
			orbit = 0,
			orbitDist = 0,
			name = "Attribute",
			orbitIndex = 0,
			group = 28,
			icon = "cooldownRecovery",
			customStats = {
				wisdom = 2,
			},
			inputs = {
				95
			},
			out = {
				96
			}
		},
		--- 95 ---
		{
			orbit = 1,
			orbitDist = 118,
			name = "Attribute",
			orbitIndex = 220,
			group = 28,
			icon = "cooldownRecovery",
			customStats = {
				wisdom = 1,
			},
			inputs = {
				18
			},
			out = {
				94
			}
		},
		--- 96 ---
		{
			orbit = 2,
			orbitDist = 118,
			name = "Cold Nature",
			orbitIndex = 330,
			isUncommon = true,
			group = 28,
			icon = "coldNature",
			customStats = {
				wisdom = 3,
				incrementIce = 3,
				absorbIce = 2
			},
			inputs = {
				94
			},
			out = {
				
			}
		},
		--- 97 ---
		{
			orbit = 0,
			orbitDist = 0,
			name = "Attribute",
			orbitIndex = 0,
			group = 29,
			icon = "mana",
			customStats = {
				spirit = 2,
			},
			inputs = {
				98	
			},
			out = {
				99
			}
		},
		--- 98 ---
		{
			orbit = 1,
			orbitDist = 118,
			name = "Attribute",
			orbitIndex = 150,
			group = 29,
			icon = "mana",
			customStats = {
				spirit = 1,
			},
			inputs = {
				24
			},
			out = {
				97
			}
		},
		--- 99 ---
		{
			orbit = 2,
			orbitDist = 118,
			name = "Tides of Changes",
			isUncommon = true,
			orbitIndex = 30,
			group = 29,
			icon = "tidesOfChange",
			customStats = {
				spirit = 3,
				incrementDeath = 3,
				absorbDeath = 2
			},
			inputs = {
				97
			},
			out = {
				
			}
		},
		--- 100 ---
		{
			orbit = 0,
			orbitDist = 0,
			name = "Attribute",
			orbitIndex = 0,
			group = 30,
			icon = "strength",
			customStats = {
				strength = 2,
			},
			inputs = {
				101
			},
			out = {
				102
			}
		},
		--- 101 ---
		{
			orbit = 1,
			orbitDist = 118,
			name = "Attribute",
			orbitIndex = 110,
			group = 30,
			icon = "strength",
			customStats = {
				strength = 1,
			},
			inputs = {
				11
			},
			out = {
				100
			}
		},
		--- 102 ---
		{
			orbit = 2,
			orbitDist = 118,
			name = "Hulking Smash",
			isUncommon = true,
			orbitIndex = 230,
			group = 30,
			icon = "hulkingSmash",
			customStats = {
				strength = 3,
				incrementPhysical = 3,
				absorbPhysical = 2
			},
			inputs = {
				100
			},
			out = {
				
			}
		},
		--- 103 ---
		{
			orbit = 0,
			orbitDist = 0,
			name = "Attribute",
			orbitIndex = 0,
			group = 31,
			icon = "dexterity",
			customStats = {
				dexterity = 2,
			},
			inputs = {
				104	
			},
			out = {
				105
			}
		},
		--- 104 ---
		{
			orbit = 1,
			orbitDist = 110,
			name = "Attribute",
			orbitIndex = 245,
			group = 31,
			icon = "dexterity",
			customStats = {
				dexterity = 1,
			},
			inputs = {
				10
			},
			out = {
				103
			}
		},
		--- 105 ---
		{
			orbit = 2,
			orbitDist = 118,
			name = "Anticipation",
			isUncommon = true,
			orbitIndex = 130,
			group = 31,
			icon = "anticipation",
			customStats = {
				dexterity = 3,
				incrementDrown = 3,
				absorbDrown = 2
			},
			inputs = {
				103
			},
			out = {
				
			}
		},
		--- 106 ---
		{
			orbit = 2,
			orbitDist = 120,
			name = "Total Incineration",
			orbitIndex = 35,
			isUncommon = true,
			group = 23,
			icon = "totalIncineration",
			customStats = {
				intelligence = 3,
				absorbFire = 2,
				incrementFire = 3
			},
			inputs = {
				80
			},
			out = {
				
			}
		},
		--- 107 ---
		{
			orbit = 2,
			orbitDist = 120,
			name = "Wildwood Fury",
			isUncommon = true,
			orbitIndex = 135,
			group = 23,
			icon = "wrathOfNature",
			customStats = {
				dexterity = 3,
				incrementEarth = 3,
				absorbEarth = 2
			},
			inputs = {
				80
			},
			out = {
				
			}
		},
		--- 108 ---
		{
			orbit = 2,
			orbitDist = 120,
			name = "Fleshcrafting",
			orbitIndex = 325,
			isUncommon = true,
			group = 22,
			icon = "fleshcrafting",
			customStats = {
				vitality = 3,
				incrementArcane = 3,
				absorbArcane = 2
			},
			inputs = {
				79
			},
			out = {
				
			}
		},
		--- 109 ---
		{
			orbit = 2,
			orbitDist = 120,
			name = "Carving Structure",
			isUncommon = true,
			orbitIndex = 220,
			group = 22,
			icon = "carvingStructure",
			customStats = {
				strength = 3,
				incrementLifeDrain = 3,
				incrementManaDrain = 3,
				absorbLife = 2,
				absorbMana = 2
			},
			inputs = {
				79
			},
			out = {
				
			}
		},
		--- 110 ---
		{
			orbit = 0,
			orbitDist = 0,
			name = "Speed",
			orbitIndex = 0,
			group = 32,
			icon = "speed",
			customStats = {
				speed = 500,
			},
			inputs = {
				113
			},
			out = {
				114
			}
		},
		--- 111 ---
		{
			orbit = 1,
			orbitDist = 70,
			name = "Attribute",
			orbitIndex = 30,
			group = 32,
			icon = "mana",
			customStats = {
				wisdom = 2,
			},
			inputs = {
				113
			},
			out = {
				114
			}
		},
		--- 112 ---
		{
			orbit = 1,
			orbitDist = 72,
			name = "Attribute",
			orbitIndex = 210,
			group = 32,
			icon = "life",
			customStats = {
				vitality = 2,
			},
			inputs = {
				113
			},
			out = {
				114
			}
		},
		--- 113 ---
		{
			orbit = 1,
			orbitDist = 70,
			name = "Attribute",
			orbitIndex = 120,
			group = 32,
			icon = "arcaneDamage",
			customStats = {
				incrementArcane = 1,
			},
			inputs = {
				69
			},
			out = {
				110, 111, 112
			}
		},
		--- 114 ---
		{
			orbit = 1,
			orbitDist = 72,
			name = "Attribute",
			orbitIndex = 300,
			group = 32,
			icon = "criticalHitChance",
			customStats = {
				criticalHitChance = 1,
				criticalHitAmount = 1
			},
			inputs = {
				112, 110, 111
			},
			out = {
				150
			}
		},
		--- 115 ---
		{
			orbit = 0,
			orbitDist = 0,
			name = "Speed",
			orbitIndex = 0,
			group = 33,
			icon = "speed",
			customStats = {
				speed = 500,
			},
			inputs = {
				116
			},
			out = {
				117
			}
		},
		--- 116 ---
		{
			orbit = 1,
			orbitDist = 70,
			name = "Attribute",
			orbitIndex = 60,
			group = 33,
			icon = "waterDamage",
			customStats = {
				incrementWater = 2,
			},
			inputs = {
				50
			},
			out = {
				115, 119, 118
			}
		},
		--- 117 ---
		{
			orbit = 1,
			orbitDist = 72,
			name = "Attribute",
			orbitIndex = 240,
			group = 33,
			icon = "baseStat",
			customStats = {
				manaLeechChance = 1,
				manaLeechAmount = 1
			},
			inputs = {
				115, 119, 118
			},
			out = {
				162
			}
		},
		--- 118 ---
		{
			orbit = 1,
			orbitDist = 70,
			name = "Attribute",
			orbitIndex = 150,
			group = 33,
			icon = "baseStat",
			customStats = {
				incrementEnergy = 1,
			},
			inputs = {
				116
			},
			out = {
				117
			}
		},
		--- 119 ---
		{
			orbit = 1,
			orbitDist = 72,
			name = "Attribute",
			orbitIndex = 330,
			group = 33,
			icon = "baseStat",
			customStats = {
				absorbWater = 1,
			},
			inputs = {
				116
			},
			out = {
				117
			}
		},
		--- 120 ---
		{
			orbit = 0,
			orbitDist = 0,
			name = "Speed",
			orbitIndex = 0,
			group = 34,
			icon = "speed",
			customStats = {
				speed = 500,
			},
			inputs = {
				122, 121
			},
			out = {
				121
			}
		},
		--- 121 ---
		{
			orbit = 1,
			orbitDist = 70,
			name = "Attribute",
			orbitIndex = 60,
			group = 34,
			icon = "magicSkill",
			customStats = {
				magicSkill = 1,
			},
			inputs = {
				120, 123, 124
			},
			out = {
				168
			}
		},
		--- 122 ---
		{
			orbit = 1,
			orbitDist = 72,
			name = "Attribute",
			orbitIndex = 240,
			group = 34,
			icon = "fireDamage",
			customStats = {
				incrementFire = 1,
			},
			inputs = {
				64
			},
			out = {
				120, 124, 123
			}
		},
		--- 123 ---
		{
			orbit = 1,
			orbitDist = 70,
			name = "Attribute",
			orbitIndex = 150,
			group = 34,
			icon = "baseStat",
			customStats = {
				absorbFire = 1,
			},
			inputs = {
				122, 121
			},
			out = {
				121
			}
		},
		--- 124 ---
		{
			orbit = 1,
			orbitDist = 72,
			name = "Attribute",
			orbitIndex = 330,
			group = 34,
			icon = "intelligence",
			customStats = {
				intelligence = 1,
			},
			inputs = {
				122
			},
			out = {
				121
			}
		},
		--- 125 ---
		{
			orbit = 0,
			orbitDist = 0,
			name = "Speed",
			orbitIndex = 0,
			group = 35,
			icon = "speed",
			customStats = {
				speed = 500,
			},
			inputs = {
				129
			},
			out = {
				128
			}
		},
		--- 126 ---
		{
			orbit = 1,
			orbitDist = 70,
			name = "Attribute",
			orbitIndex = 30,
			group = 35,
			icon = "distanceSkill",
			customStats = {
				distanceSkill = 1,
			},
			inputs = {
				129
			},
			out = {
				128
			}
		},
		--- 127 ---
		{
			orbit = 1,
			orbitDist = 72,
			name = "Attribute",
			orbitIndex = 210,
			group = 35,
			icon = "absorbHoly",
			customStats = {
				absorbHoly = 1,
			},
			inputs = {
				129
			},
			out = {
				128
			}
		},
		--- 128 ---
		{
			orbit = 1,
			orbitDist = 70,
			name = "Attribute",
			orbitIndex = 120,
			group = 35,
			icon = "baseStat",
			customStats = {
				lifeLeechChance = 1,
				lifeLeechAmount = 1,
			},
			inputs = {
				125, 126, 127	
			},
			out = {
				180
			}
		},
		--- 129 ---
		{
			orbit = 1,
			orbitDist = 72,
			name = "Attribute",
			orbitIndex = 300,
			group = 35,
			icon = "holyDamage",
			customStats = {
				incrementHoly = 2,
			},
			inputs = {
				42
			},
			out = {
				125, 126, 127
			}
		},
		--- 130 ---
		{
			orbit = 0,
			orbitDist = 0,
			name = "Attribute",
			orbitIndex = 0,
			isVeryRare = true,
			group = 36,
			icon = "life",
			customStats = {
				vitality = 10,
			},
			inputs = {
				87
			},
			out = {
				143
			}
		},
		--- 131 ---
		{
			orbit = 0,
			orbitDist = 0,
			name = "Attribute",
			isVeryRare = true,
			orbitIndex = 0,
			group = 37,
			icon = "life",
			customStats = {
				vitality = 10,
			},
			inputs = {
				89
			},
			out = {
				134
			}
		},
		--- 132 ---
		{
			orbit = 0,
			orbitDist = 0,
			name = "Attribute",
			orbitIndex = 0,
			isVeryRare = true,
			group = 38,
			icon = "intelligence",
			customStats = {
				intelligence = 10,
			},
			inputs = {
				90
			},
			out = {
				137
			}
		},
		--- 133 ---
		{
			orbit = 0,
			orbitDist = 0,
			name = "Attribute",
			isVeryRare = true,
			orbitIndex = 0,
			group = 39,
			icon = "intelligence",
			customStats = {
				intelligence = 10,
			},
			inputs = {
				92
			},
			out = {
				140
			}
		},
		--- 134 ---
		{
			orbit = 1,
			orbitDist = 100,
			name = "Attribute",
			orbitIndex = 300,
			group = 37,
			icon = "lifeLeechChance",
			customStats = {
				lifeLeechChance = 1,
				lifeLeechAmount = 2
			},
			inputs = {
				131
			},
			out = {
				135
			}
		},
		--- 135 ---
		{
			orbit = 2,
			orbitDist = 100,
			name = "Attribute",
			orbitIndex = 270,
			group = 37,
			icon = "criticalHitChance",
			customStats = {
				criticalHitChance = 1,
				criticalHitAmount = 1
			},
			inputs = {
				134
			},
			out = {
				136
			}
		},
		--- 136 ---
		{
			orbit = 3,
			orbitDist = 150,
			name = "Attribute",
			orbitIndex = 270,
			group = 37,
			icon = "swordSkill",
			customStats = {
				axeSkill = 1,
				clubSkill = 1,
				swordSkill = 1

			},
			inputs = {
				135
			},
			out = {
				146
			}
		},
		--- 137 ---
		{
			orbit = 1,
			orbitDist = 100,
			name = "Attribute",
			orbitIndex = 120,
			group = 38,
			icon = "manaLeechChance",
			customStats = {
				manaLeechChance = 1,
				manaLeechAmount = 2
			},
			inputs = {
				132
			},
			out = {
				138
			}
		},
		--- 138 ---
		{
			orbit = 2,
			orbitDist = 100,
			name = "Attribute",
			orbitIndex = 90,
			group = 38,
			icon = "criticalHitChance",
			customStats = {
				criticalHitChance = 1,
				criticalHitAmount = 1
			},
			inputs = {
				137
			},
			out = {
				139
			}
		},
		--- 139 ---
		{
			orbit = 3,
			orbitDist = 150,
			name = "Attribute",
			orbitIndex = 90,
			group = 38,
			icon = "magicSkill",
			customStats = {
				magicSkill = 1,
			},
			inputs = {
				138
			},
			out = {
				149
			}
		},
		--- 140 ---
		{
			orbit = 1,
			orbitDist = 100,
			name = "Attribute",
			orbitIndex = 60,
			group = 39,
			icon = "lifeLeechChance",
			customStats = {
				lifeLeechChance = 1,
				lifeLeechAmount = 2
			},
			inputs = {
				133
			},
			out = {
				141
			}
		},
		--- 141 ---
		{
			orbit = 2,
			orbitDist = 100,
			name = "Attribute",
			orbitIndex = 90,
			group = 39,
			icon = "criticalHitChance",
			customStats = {
				criticalHitChance = 1,
				criticalHitAmount = 1
			},
			inputs = {
				140
			},
			out = {
				142
			}
		},
		--- 142 ---
		{
			orbit = 3,
			orbitDist = 150,
			name = "Attribute",
			orbitIndex = 90,
			group = 39,
			icon = "magicSkill",
			customStats = {
				magicSkill = 1,
			},
			inputs = {
				141
			},
			out = {
				148
			}
		},
		--- 143 ---
		{
			orbit = 1,
			orbitDist = 100,
			name = "Attribute",
			orbitIndex = 230,
			group = 36,
			icon = "manaLeechChance",
			customStats = {
				manaLeechChance = 1,
				manaLeechAmount = 2
			},
			inputs = {
				130
			},
			out = {
				144
			}
		},
		--- 144 ---
		{
			orbit = 2,
			orbitDist = 100,
			name = "Attribute",
			orbitIndex = 260,
			group = 36,
			icon = "criticalHitChance",
			customStats = {
				criticalHitChance = 1,
				criticalHitAmount = 1
			},
			inputs = {
				143
			},
			out = {
				145
			}
		},
		--- 145 ---
		{
			orbit = 3,
			orbitDist = 150,
			name = "Attribute",
			orbitIndex = 263,
			group = 36,
			icon = "swordSkill",
			customStats = {
				axeSkill = 1,
				clubSkill = 1,
				swordSkill = 1

			},
			inputs = {
				144
			},
			out = {
				147
			}
		},
		--- 146 ---
		{
			orbit = 4,
			orbitDist = 250,
			name = "Grave Intentions",
			orbitIndex = 245,
			group = 37,
			isRare = true,
			icon = "absorbPhysical",
			customStats = {
				lifeLeechChance = 2,
				lifeLeechAmount = 3,
				vitality = 3,
				absorbPhysical = 3
			},
			inputs = {
				136
			},
			out = {
				326
			}
		},
		--- 147 ---
		{
			orbit = 4,
			orbitDist = 250,
			name = "Indomitable",
			orbitIndex = 293,
			group = 36,
			isRare = true,
			icon = "absorbFire",
			customStats = {
				lifeLeechChance = 2,
				lifeLeechAmount = 3,
				vitality = 3,
				absorbFire = 3
			},
			inputs = {
				145
			},
			out = {
				326
			}
		},
		--- 148 ---
		{
			orbit = 4,
			orbitDist = 250,
			name = "Earth Walker",
			orbitIndex = 110,
			group = 39,
			isRare = true,
			icon = "absorbEarth",
			customStats = {
				manaLeechChance = 2,
				manaLeechAmount = 3,
				spirit = 3,
				absorbEarth = 3
			},
			inputs = {
				142
			},
			out = {
				342
			}
		},
		--- 149 ---
		{
			orbit = 4,
			orbitDist = 250,
			name = "Hollow Effigy",
			isRare = true,
			orbitIndex = 70,
			group = 38,
			icon = "absorbEnergy",
			customStats = {
				manaLeechChance = 2,
				manaLeechAmount = 3,
				spirit = 3,
				absorbEnergy = 3
			},
			inputs = {
				139
			},
			out = {
				342
			}
		},
		--- 150 ---
		{
			orbit = 2,
			orbitDist = 70,
			name = "Attribute",
			orbitIndex = 135,
			group = 40,
			icon = "absorbDeath",
			customStats = {
				absorbDeath = 1,
			},
			inputs = {
				114
			},
			out = {
				151, 154
			}
		},
		--- 151 ---
		{
			orbit = 0,
			orbitDist = 70,
			name = "Attribute",
			orbitIndex = 185,
			group = 40,
			icon = "strength",
			customStats = {
				strength = 1,
			},
			inputs = {
				150
			},
			out = {
				152
			}
		},
		--- 152 ---
		{
			orbit = 1,
			orbitDist = 70,
			name = "Attribute",
			orbitIndex = 230,
			group = 40,
			icon = "healthDamage",
			customStats = {
				incrementHealth = 2,
			},
			inputs = {
				151
			},
			out = {
				153, 361
			}
		},
		--- 153 ---
		{
			orbit = 2,
			orbitDist = 70,
			name = "Attribute",
			orbitIndex = 275,
			group = 40,
			icon = "holyDamage",
			customStats = {
				incrementHoly = 2,
			},
			inputs = {
				152
			},
			out = {
				156
			}
		},
		--- 154 ---
		{
			orbit = 1,
			orbitDist = 70,
			name = "Attribute",
			orbitIndex = 90,
			group = 40,
			icon = "lifeManaDrain",
			customStats = {
				incrementLifeDrain = 2,
				incrementManaDrain = 2
			},
			inputs = {
				150
			},
			out = {
				157
			}
		},
		--- 155 ---
		{
			orbit = 3,
			orbitDist = 70,
			name = "Attribute",
			orbitIndex = 359,
			group = 40,
			icon = "absorbEnergy",
			customStats = {
				absorbEnergy = 1,
			},
			inputs = {
				156
			},
			out = {
				157
			}
		},
		--- 156 ---
		{
			orbit = 1,
			orbitDist = 70,
			name = "Attribute",
			orbitIndex = 315,
			group = 40,
			icon = "strength",
			customStats = {
				strength = 1,
			},
			inputs = {
				153
			},
			out = {
				155, 411
			}
		},
		--- 157 ---
		{
			orbit = 0,
			orbitDist = 0,
			name = "Attribute",
			isVeryRare = true,
			orbitIndex = 0,
			group = 40,
			icon = "strength",
			customStats = {
				strength = 10,
			},
			inputs = {
				154, 155
			},
			out = {
				182
			}
		},
		--- 158 ---
		{
			orbit = 2,
			orbitDist = 70,
			name = "Attribute",
			orbitIndex = 90,
			group = 41,
			icon = "absorbArcane",
			customStats = {
				absorbArcane = 1,
			},
			inputs = {
				162
			},
			out = {
				165
			}
		},
		--- 159 ---
		{
			orbit = 4,
			orbitDist = 70,
			name = "Attribute",
			orbitIndex = 180,
			group = 41,
			icon = "absorbPhysical",
			customStats = {
				absorbPhysical = 1,
			},
			inputs = {
				160	
			},
			out = {
				165
			}
		},
		--- 160 ---
		{
			orbit = 1,
			orbitDist = 70,
			name = "Attribute",
			orbitIndex = 225,
			group = 41,
			icon = "holyDamage",
			customStats = {
				incrementHoly = 2,
			},
			inputs = {
				161
			},
			out = {
				159, 448
			}
		},
		--- 161 ---
		{
			orbit = 2,
			orbitDist = 70,
			name = "Attribute",
			orbitIndex = 270,
			group = 41,
			icon = "physicalDamage",
			customStats = {
				incrementPhysical = 2,
			},
			inputs = {
				164
			},
			out = {
				160
			}
		},
		--- 162 ---
		{
			orbit = 1,
			orbitDist = 70,
			name = "Attribute",
			orbitIndex = 45,
			group = 41,
			icon = "fireDamage",
			customStats = {
				incrementFire = 2,
			},
			inputs = {
				117
			},
			out = {
				158, 163
			}
		},
		--- 163 ---
		{
			orbit = 3,
			orbitDist = 70,
			name = "Attribute",
			orbitIndex = 2,
			group = 41,
			icon = "absorbFire",
			customStats = {
				absorbFire = 1,
			},
			inputs = {
				162
			},
			out = {
				164
			}
		},
		--- 164 ---
		{
			orbit = 1,
			orbitDist = 70,
			name = "Attribute",
			orbitIndex = 315,
			group = 41,
			icon = "absorbWater",
			customStats = {
				absorbWater = 1,
			},
			inputs = {
				163
			},
			out = {
				161, 350
			}
		},
		--- 165 ---
		{
			orbit = 0,
			orbitDist = 0,
			name = "Attribute",
			isVeryRare = true,
			orbitIndex = 0,
			group = 41,
			icon = "experience",
			customStats = {
				experience = 30,
			},
			inputs = {
				158, 159
			},
			out = {
				192
			}
		},
		--- 166 ---
		{
			orbit = 2,
			orbitDist = 70,
			name = "Attribute",
			orbitIndex = 135,
			group = 42,
			icon = "intelligence",
			customStats = {
				intelligence = 1,
			},
			inputs = {
				167
			},
			out = {
				170, 374
			}
		},
		--- 167 ---
		{
			orbit = 0,
			orbitDist = 70,
			name = "Attribute",
			orbitIndex = 180,
			group = 42,
			icon = "drownDamage",
			customStats = {
				incrementDrown = 2,
			},
			inputs = {
				168
			},
			out = {
				166
			}
		},
		--- 168 ---
		{
			orbit = 1,
			orbitDist = 70,
			name = "Attribute",
			orbitIndex = 225,
			group = 42,
			icon = "coldDamage",
			customStats = {
				incrementIce = 2,
			},
			inputs = {
				121
			},
			out = {
				169, 167
			}
		},
		--- 169 ---
		{
			orbit = 2,
			orbitDist = 70,
			name = "Attribute",
			orbitIndex = 270,
			group = 42,
			icon = "absorbEarth",
			customStats = {
				absorbEarth = 1,
			},
			inputs = {
				168
			},
			out = {
				173
			}
		},
		--- 170 ---
		{
			orbit = 1,
			orbitDist = 70,
			name = "Attribute",
			orbitIndex = 90,
			group = 42,
			icon = "absorbLife",
			customStats = {
				absorbLife = 1,
			},
			inputs = {
				166
			},
			out = {
				171
			}
		},
		--- 171 ---
		{
			orbit = 3,
			orbitDist = 70,
			name = "Attribute",
			orbitIndex = 45,
			group = 42,
			icon = "absorbMana",
			customStats = {
				absorbMana = 1,
			},
			inputs = {
				170
			},
			out = {
				172, 565
			}
		},
		--- 172 ---
		{
			orbit = 1,
			orbitDist = 70,
			name = "Attribute",
			orbitIndex = 1,
			group = 42,
			icon = "intelligence",
			customStats = {
				intelligence = 1,
			},
			inputs = {
				171
			},
			out = {
				173
			}
		},
		--- 173 ---
		{
			orbit = 0,
			orbitDist = 0,
			name = "Attribute",
			isVeryRare = true,
			orbitIndex = 0,
			group = 42,
			icon = "intelligence",
			customStats = {
				intelligence = 10,
			},
			inputs = {
				169, 172
			},
			out = {
				197
			}
		},
		--- 174 ---
		{
			orbit = 2,
			orbitDist = 70,
			name = "Attribute",
			orbitIndex = 90,
			group = 43,
			icon = "physicalDamage",
			customStats = {
				incrementPhysical = 2,
			},
			inputs = {
				178
			},
			out = {
				175
			}
		},
		--- 175 ---
		{
			orbit = 0,
			orbitDist = 70,
			name = "Attribute",
			orbitIndex = 135,
			group = 43,
			icon = "absorbWater",
			customStats = {
				absorbWater = 1,
			},
			inputs = {
				174
			},
			out = {
				176, 529
			}
		},
		--- 176 ---
		{
			orbit = 1,
			orbitDist = 70,
			name = "Attribute",
			orbitIndex = 180,
			group = 43,
			icon = "holyDamage",
			customStats = {
				incrementHoly = 2,
			},
			inputs = {
				175
			},
			out = {
				181
			}
		},
		--- 177 ---
		{
			orbit = 2,
			orbitDist = 70,
			name = "Attribute",
			orbitIndex = 270,
			group = 43,
			icon = "dexterity",
			customStats = {
				dexterity = 1,
			},
			inputs = {
				180
			},
			out = {
				181
			}
		},
		--- 178 ---
		{
			orbit = 1,
			orbitDist = 70,
			name = "Attribute",
			orbitIndex = 45,
			group = 43,
			icon = "absorbPhysical",
			customStats = {
				absorbPhysical = 1,
			},
			inputs = {
				179
			},
			out = {
				174, 377
			}
		},
		--- 179 ---
		{
			orbit = 3,
			orbitDist = 70,
			name = "Attribute",
			orbitIndex = 359,
			group = 43,
			icon = "dexterity",
			customStats = {
				dexterity = 1,
			},
			inputs = {
				180
			},
			out = {
				178
			}
		},
		--- 180 ---
		{
			orbit = 1,
			orbitDist = 70,
			name = "Attribute",
			orbitIndex = 315,
			group = 43,
			icon = "waterDamage",
			customStats = {
				incrementWater = 2,
			},
			inputs = {
				128
			},
			out = {
				177, 179
			}
		},
		--- 181 ---
		{
			orbit = 0,
			orbitDist = 0,
			name = "Attribute",
			isVeryRare = true,
			orbitIndex = 0,
			group = 43,
			icon = "dexterity",
			customStats = {
				dexterity = 10,
			},
			inputs = {
				176, 177
			},
			out = {
				187
			}
		},
		--- 182 ---
		{
			orbit = 1,
			orbitDist = 50,
			name = "Attribute",
			orbitIndex = 220,
			group = 44,
			icon = "strength",
			customStats = {
				strength = 1,
			},
			inputs = {
				157
			},
			out = {
				184, 185
			}
		},
		--- 183 ---
		{
			orbit = 1,
			orbitDist = 50,
			name = "Attribute",
			orbitIndex = 40,
			group = 44,
			icon = "strength",
			customStats = {
				strength = 1,
			},
			inputs = {
				184, 185
			},
			out = {
				241
			}
		},
		--- 184 ---
		{
			orbit = 1,
			orbitDist = 50,
			name = "Attribute",
			orbitIndex = 312,
			group = 44,
			icon = "axeSkill",
			customStats = {
				axeSkill = 1,
			},
			inputs = {
				182
			},
			out = {
				183, 392
			}
		},
		--- 185 ---
		{
			orbit = 1,
			orbitDist = 50,
			name = "Attribute",
			orbitIndex = 130,
			group = 44,
			icon = "clubSkill",
			customStats = {
				clubSkill = 1,
			},
			inputs = {
				182
			},
			out = {
				183
			}
		},
		--- 186 ---
		{
			orbit = 1,
			orbitDist = 50,
			name = "Attribute",
			orbitIndex = 220,
			group = 45,
			icon = "intelligence",
			customStats = {
				intelligence = 1,
			},
			inputs = {
				188, 189
			},
			out = {
				240
			}
		},
		--- 187 ---
		{
			orbit = 1,
			orbitDist = 50,
			name = "Attribute",
			orbitIndex = 40,
			group = 45,
			icon = "intelligence",
			customStats = {
				intelligence = 1,
			},
			inputs = {
				181
			},
			out = {
				188, 189
			}
		},
		--- 188 ---
		{
			orbit = 1,
			orbitDist = 50,
			name = "Attribute",
			orbitIndex = 312,
			group = 45,
			icon = "manaLeechChance",
			customStats = {
				manaLeechChance = 1,
				manaLeechAmount = 1
			},
			inputs = {
				187
			},
			out = {
				186
			}
		},
		--- 189 ---
		{
			orbit = 1,
			orbitDist = 50,
			name = "Attribute",
			orbitIndex = 130,
			group = 45,
			icon = "lifeLeechChance",
			customStats = {
				lifeLeechChance = 1,
				lifeLeechAmount = 1
			},
			inputs = {
				187
			},
			out = {
				186, 510
			}
		},
		--- 190 ---
		{
			orbit = 1,
			orbitDist = 50,
			name = "Attribute",
			orbitIndex = 220,
			group = 46,
			icon = "mana",
			customStats = {
				spirit = 1,
			},
			inputs = {
				192
			},
			out = {
				193, 467
			}
		},
		--- 191 ---
		{
			orbit = 1,
			orbitDist = 50,
			name = "Attribute",
			orbitIndex = 40,
			group = 46,
			icon = "life",
			customStats = {
				vitality = 1,
			},
			inputs = {
				192
			},
			out = {
				193
			}
		},
		--- 192 ---
		{
			orbit = 1,
			orbitDist = 50,
			name = "Attribute",
			orbitIndex = 312,
			group = 46,
			icon = "dexterity",
			customStats = {
				dexterity = 1,
			},
			inputs = {
				165
			},
			out = {
				190, 191
			}
		},
		--- 193 ---
		{
			orbit = 1,
			orbitDist = 50,
			name = "Attribute",
			orbitIndex = 130,
			group = 46,
			icon = "dexterity",
			customStats = {
				dexterity = 1,
			},
			inputs = {
				190, 191
			},
			out = {
				238
			}
		},
		--- 194 ---
		{
			orbit = 1,
			orbitDist = 50,
			name = "Attribute",
			orbitIndex = 220,
			group = 47,
			icon = "swordSkill",
			customStats = {
				swordSkill = 1,
			},
			inputs = {
				197
			},
			out = {
				196
			}
		},
		--- 195 ---
		{
			orbit = 1,
			orbitDist = 50,
			name = "Attribute",
			orbitIndex = 40,
			group = 47,
			icon = "shieldingSkill",
			customStats = {
				shieldingSkill = 1,
			},
			inputs = {
				197
			},
			out = {
				196, 584
			}
		},
		--- 196 ---
		{
			orbit = 1,
			orbitDist = 50,
			name = "Attribute",
			orbitIndex = 312,
			group = 47,
			icon = "cooldownRecovery",
			customStats = {
				wisdom = 1,
			},
			inputs = {
				194, 195
			},
			out = {
				242
			}
		},
		--- 197 ---
		{
			orbit = 1,
			orbitDist = 50,
			name = "Attribute",
			orbitIndex = 130,
			group = 47,
			icon = "cooldownRecovery",
			customStats = {
				wisdom = 1,
			},
			inputs = {
				173
			},
			out = {
				194, 195
			}
		},
		--- 198 ---
		{
			orbit = 1,
			orbitDist = 75,
			name = "Attribute",
			orbitIndex = 1,
			group = 48,
			icon = "strength",
			customStats = {
				strength = 2,
			},
			inputs = {
				62
			},
			out = {
				199	
			}
		},
		--- 199 ---
		{
			orbit = 0,
			orbitDist = 0,
			isMythic = true,
			name = "Attribute",
			orbitIndex = 0,
			group = 48,
			icon = "strength",
			customStats = {
				strength = 10,
			},
			inputs = {
				198
			},
			out = {
				200
			}
		},
		--- 200 ---
		{
			orbit = 1,
			orbitDist = 75,
			name = "Attribute",
			orbitIndex = 180,
			group = 48,
			icon = "strength",
			customStats = {
				strength = 2,
			},
			inputs = {
				199
			},
			out = {
				215
			}
		},
		--- 201 ---
		{
			orbit = 1,
			orbitDist = 75,
			name = "Attribute",
			orbitIndex = 1,
			group = 49,
			icon = "dexterity",
			customStats = {
				dexterity = 2,
			},
			inputs = {
				62
			},
			out = {
				202
			}
		},
		--- 202 ---
		{
			orbit = 0,
			orbitDist = 0,
			isMythic = true,
			name = "Attribute",
			orbitIndex = 0,
			group = 49,
			icon = "dexterity",
			customStats = {
				dexterity = 10,
			},
			inputs = {
				201	
			},
			out = {
				203
			}
		},
		--- 203 ---
		{
			orbit = 1,
			orbitDist = 75,
			name = "Attribute",
			orbitIndex = 180,
			group = 49,
			icon = "dexterity",
			customStats = {
				dexterity = 2,
			},
			inputs = {
				202
			},
			out = {
				222
			}
		},
		--- 204 ---
		{
			orbit = 1,
			orbitDist = 75,
			name = "Attribute",
			orbitIndex = 1,
			group = 50,
			icon = "mana",
			customStats = {
				spirit = 2,
			},
			inputs = {
				205
			},
			out = {
				229
			}
		},
		--- 205 ---
		{
			orbit = 0,
			orbitDist = 0,
			isMythic = true,
			name = "Attribute",
			orbitIndex = 0,
			group = 50,
			icon = "mana",
			customStats = {
				spirit = 10,
			},
			inputs = {
				206
			},
			out = {
				204
			}
		},
		--- 206 ---
		{
			orbit = 1,
			orbitDist = 75,
			name = "Attribute",
			orbitIndex = 180,
			group = 50,
			icon = "mana",
			customStats = {
				spirit = 2,
			},
			inputs = {
				51
			},
			out = {
				205
			}
		},
		--- 207 ---
		{
			orbit = 1,
			orbitDist = 75,
			name = "Attribute",
			orbitIndex = 1,
			group = 51,
			icon = "cooldownRecovery",
			customStats = {
				wisdom = 2,
			},
			inputs = {
				208
			},
			out = {
				236
			}
		},
		--- 208 ---
		{
			orbit = 0,
			orbitDist = 0,
			isMythic = true,
			name = "Attribute",
			orbitIndex = 0,
			group = 51,
			icon = "cooldownRecovery",
			customStats = {
				wisdom = 10,
			},
			inputs = {
				209
			},
			out = {
				207
			}
		},
		--- 209 ---
		{
			orbit = 1,
			orbitDist = 75,
			name = "Attribute",
			orbitIndex = 180,
			group = 51,
			icon = "cooldownRecovery",
			customStats = {
				wisdom = 2,
			},
			inputs = {
				51
			},
			out = {
				208
			}
		},
		--- 210 ---
		{
			orbit = 2,
			orbitDist = 70,
			name = "Attribute",
			orbitIndex = 90,
			group = 52,
			icon = "waterDamage",
			customStats = {
				incrementWater = 2,
			},
			inputs = {
				214
			},
			out = {
				211
			}
		},
		--- 211 ---
		{
			orbit = 4,
			orbitDist = 70,
			name = "Attribute",
			orbitIndex = 135,
			group = 52,
			icon = "dexterity",
			customStats = {
				dexterity = 1,
			},
			inputs = {
				210
			},
			out = {
				244
			}
		},
		--- 212 ---
		{
			orbit = 1,
			orbitDist = 70,
			name = "Attribute",
			orbitIndex = 225,
			group = 52,
			icon = "drownDamage",
			customStats = {
				incrementDrown = 2,
			},
			inputs = {
				213
			},
			out = {
				238
			}
		},
		--- 213 ---
		{
			orbit = 2,
			orbitDist = 70,
			name = "Attribute",
			orbitIndex = 270,
			group = 52,
			icon = "absorbDrown",
			customStats = {
				absorbDrown = 2,
			},
			inputs = {
				216	
			},
			out = {
				212
			}
		},
		--- 214 ---
		{
			orbit = 1,
			orbitDist = 70,
			name = "Attribute",
			orbitIndex = 45,
			group = 52,
			icon = "strength",
			customStats = {
				strength = 1,
			},
			inputs = {
				215
			},
			out = {
				210
			}
		},
		--- 215 ---
		{
			orbit = 3,
			orbitDist = 70,
			name = "Attribute",
			orbitIndex = 2,
			group = 52,
			icon = "healthDamage",
			customStats = {
				incrementHealth = 1,
			},
			inputs = {
				200
			},
			out = {
				214, 216
			}
		},
		--- 216 ---
		{
			orbit = 1,
			orbitDist = 70,
			name = "Attribute",
			orbitIndex = 315,
			group = 52,
			icon = "intelligence",
			customStats = {
				intelligence = 1,
			},
			inputs = {
				215
			},
			out = {
				213
			}
		},
		--- 217 ---
		{
			orbit = 2,
			orbitDist = 70,
			name = "Attribute",
			orbitIndex = 90,
			group = 53,
			icon = "rarityLoot",
			customStats = {
				rarityLoot = 3,
			},
			inputs = {
				221
			},
			out = {
				218
			}
		},
		--- 218 ---
		{
			orbit = 4,
			orbitDist = 70,
			name = "Attribute",
			orbitIndex = 135,
			group = 53,
			icon = "baseStat",
			customStats = {
				incrementEnergy = 2,
			},
			inputs = {
				217
			},
			out = {
				240
			}
		},
		--- 219 ---
		{
			orbit = 1,
			orbitDist = 70,
			name = "Attribute",
			orbitIndex = 225,
			group = 53,
			icon = "baseStat",
			customStats = {
				incrementIce = 2,
			},
			inputs = {
				220
			},
			out = {
				244
			}
		},
		--- 220 ---
		{
			orbit = 2,
			orbitDist = 70,
			name = "Attribute",
			orbitIndex = 270,
			group = 53,
			icon = "absorbEnergy",
			customStats = {
				absorbEnergy = 1,
			},
			inputs = {
				223
			},
			out = {
				219
			}
		},
		--- 221 ---
		{
			orbit = 1,
			orbitDist = 70,
			name = "Attribute",
			orbitIndex = 45,
			group = 53,
			icon = "dexterity",
			customStats = {
				dexterity = 1,
			},
			inputs = {
				222
			},
			out = {
				217
			}
		},
		--- 222 ---
		{
			orbit = 3,
			orbitDist = 70,
			name = "Attribute",
			orbitIndex = 2,
			group = 53,
			icon = "holyDamage",
			customStats = {
				incrementHoly = 2,
			},
			inputs = {
				203
			},
			out = {
				221, 223
			}
		},
		--- 223 ---
		{
			orbit = 1,
			orbitDist = 70,
			name = "Attribute",
			orbitIndex = 315,
			group = 53,
			icon = "strength",
			customStats = {
				strength = 1,
			},
			inputs = {
				222
			},
			out = {
				220
			}
		},
		--- 224 ---
		{
			orbit = 2,
			orbitDist = 70,
			name = "Attribute",
			orbitIndex = 90,
			group = 54,
			icon = "intelligence",
			customStats = {
				intelligence = 1,
			},
			inputs = {
				225
			},
			out = {
				228
			}
		},
		--- 225 ---
		{
			orbit = 4,
			orbitDist = 70,
			name = "Attribute",
			orbitIndex = 135,
			group = 54,
			icon = "baseStat",
			customStats = {
				incrementEarth = 1,
			},
			inputs = {
				229
			},
			out = {
				224
			}
		},
		--- 226 ---
		{
			orbit = 1,
			orbitDist = 70,
			name = "Attribute",
			orbitIndex = 225,
			group = 54,
			icon = "baseStat",
			customStats = {
				absorbEarth = 1,
			},
			inputs = {
				229
			},
			out = {
				227
			}
		},
		--- 227 ---
		{
			orbit = 2,
			orbitDist = 70,
			name = "Attribute",
			orbitIndex = 270,
			group = 54,
			icon = "loot",
			customStats = {
				loot = 10,
			},
			inputs = {
				226
			},
			out = {
				230
			}
		},
		--- 228 ---
		{
			orbit = 1,
			orbitDist = 70,
			name = "Attribute",
			orbitIndex = 45,
			group = 54,
			icon = "strength",
			customStats = {
				strength = 1,
			},
			inputs = {
				224
			},
			out = {
				242
			}
		},
		--- 229 ---
		{
			orbit = 3,
			orbitDist = 70,
			name = "Attribute",
			orbitIndex = 180,
			group = 54,
			icon = "herbalistSkill",
			customStats = {
				herbalistSkill = 1,
			},
			inputs = {
				204
			},
			out = {
				225, 226
			}
		},
		--- 230 ---
		{
			orbit = 1,
			orbitDist = 70,
			name = "Attribute",
			orbitIndex = 315,
			group = 54,
			icon = "dexterity",
			customStats = {
				dexterity = 1,
			},
			inputs = {
				227
			},
			out = {
				243
			}
		},
		--- 231 ---
		{
			orbit = 2,
			orbitDist = 70,
			name = "Attribute",
			orbitIndex = 90,
			group = 55,
			icon = "magicSkill",
			customStats = {
				magicSkill = 1,
			},
			inputs = {
				232
			},
			out = {
				235
			}
		},
		--- 232 ---
		{
			orbit = 4,
			orbitDist = 70,
			name = "Attribute",
			orbitIndex = 135,
			group = 55,
			icon = "dexterity",
			customStats = {
				dexterity = 1,
			},
			inputs = {
				236
			},
			out = {
				231
			}
		},
		--- 233 ---
		{
			orbit = 1,
			orbitDist = 70,
			name = "Attribute",
			orbitIndex = 225,
			group = 55,
			icon = "baseStat",
			customStats = {
				strength = 1,
			},
			inputs = {
				236
			},
			out = {
				234
			}
		},
		--- 234 ---
		{
			orbit = 2,
			orbitDist = 70,
			name = "Attribute",
			orbitIndex = 270,
			group = 55,
			icon = "craftingSkill",
			customStats = {
				craftingSkill = 1,
			},
			inputs = {
				233
			},
			out = {
				237
			}
		},
		--- 235 ---
		{
			orbit = 1,
			orbitDist = 70,
			name = "Attribute",
			orbitIndex = 45,
			group = 55,
			icon = "intelligence",
			customStats = {
				intelligence = 1,
			},
			inputs = {
				231
			},
			out = {
				243
			}
		},
		--- 236 ---
		{
			orbit = 3,
			orbitDist = 70,
			name = "Attribute",
			orbitIndex = 180,
			group = 55,
			icon = "shieldingSkill",
			customStats = {
				shieldingSkill = 1,
			},
			inputs = {
				207
			},
			out = {
				232, 233
			}
		},
		--- 237 ---
		{
			orbit = 1,
			orbitDist = 70,
			name = "Attribute",
			orbitIndex = 315,
			group = 55,
			icon = "baseStat",
			customStats = {
				absorbDrown = 1,
			},
			inputs = {
				234
			},
			out = {
				241
			}
		},
		--- 238 ---
		{
			orbit = 0,
			orbitDist = 0,
			name = "Attribute",
			isMythic = true,
			orbitIndex = 0,
			group = 56,
			icon = "life",
			customStats = {
				vitality = 10,
			},
			inputs = {
				193, 212
			},
			out = {
				255, 467
			}
		},
		--- 239 ---
		{
			orbit = 0,
			orbitDist = 0,
			name = "Attribute",
			isMythic = true,
			orbitIndex = 0,
			group = 57,
			icon = "baseStat",
			customStats = {
				strength = 239,
			},
			inputs = {
				
			},
			out = {
				
			}
		},
		--- 240 ---
		{
			orbit = 0,
			orbitDist = 0,
			name = "Attribute",
			isMythic = true,
			orbitIndex = 0,
			group = 57,
			icon = "dexterity",
			customStats = {
				dexterity = 5,
			},
			inputs = {
				186, 218
			},
			out = {
				258, 510
			}
		},
		--- 241 ---
		{
			orbit = 0,
			orbitDist = 0,
			name = "Attribute",
			isMythic = true,
			orbitIndex = 0,
			group = 58,
			icon = "strength",
			customStats = {
				strength = 5,
			},
			inputs = {
				183, 237
			},
			out = {
				248, 392
			}
		},
		--- 242 ---
		{
			orbit = 0,
			orbitDist = 0,
			name = "Attribute",
			isMythic = true,
			orbitIndex = 0,
			group = 59,
			icon = "intelligence",
			customStats = {
				intelligence = 5,
			},
			inputs = {
				196, 228
			},
			out = {
				251, 584
			}
		},
		--- 243 ---
		{
			orbit = 0,
			orbitDist = 0,
			name = "Long Side",
			isMythic = true,
			orbitIndex = 0,
			group = 60,
			icon = "longSide",
			customStats = {
				strength = 2,
				dexterity = 2,
				intelligence = 2,
				absorbPhysical = 1,
				absorbEnergy = 1,
				absorbEarth = 1
			},
			inputs = {
				230, 235
			},
			out = {
				252, 312, 313
			}
		},
		--- 244 ---
		{
			orbit = 0,
			orbitDist = 0,
			name = "Arcane Guarding",
			isMythic = true,
			orbitIndex = 0,
			group = 61,
			icon = "arcaneGuarding",
			customStats = {
				strength = 2,
				dexterity = 2,
				intelligence = 2,
				absorbArcane = 1,
				absorbDeath = 1,
				absorbWater = 1
			},
			inputs = {
				211, 219
			},
			out = {
				254, 303, 304 
			}
		},
		--- 245 ---
		{
			orbit = 2,
			orbitDist = 115,
			name = "Attribute",
			orbitIndex = 1,
			group = 62,
			icon = "holyDamage",
			customStats = {
				incrementHoly = 2,
				absorbHoly = 1
			},
			inputs = {
			  246, 249
			},
			out = {
				253, 602
			}
		},
		--- 246 ---
		{
			orbit = 2,
			orbitDist = 115,
			name = "Attribute",
			orbitIndex = -59,
			group = 62,
			icon = "lightningDamage",
			customStats = {
				incrementEnergy = 2,
			},
			inputs = {
				247
			},
			out = {
				245
			}
		},
		--- 247 ---
		{
			orbit = 1,
			orbitDist = 115,
			name = "Attribute",
			orbitIndex = 270,
			group = 62,
			icon = "waterDamage",
			customStats = {
				incrementWater = 2,
			},
			inputs = {
				248
			},
			out = {
				246
			}
		},
		--- 248 ---
		{
			orbit = 2,
			orbitDist = 115,
			name = "Attribute",
			orbitIndex = 240,
			group = 62,
			icon = "baseStat",
			customStats = {
				incrementEarth = 2,
			},
			inputs = {
				241, 252
			},
			out = {
				247
			}
		},
		--- 249 ---
		{
			orbit = 2,
			orbitDist = 118,
			name = "Attribute",
			orbitIndex = 60,
			group = 62,
			icon = "absorbEnergy",
			customStats = {
				absorbEnergy = 1,
			},
			inputs = {
				250	
			},
			out = {
				245	
			}
		},
		--- 250 ---
		{
			orbit = 1,
			orbitDist = 118,
			name = "Attribute",
			orbitIndex = 90,
			group = 62,
			icon = "absorbWater",
			customStats = {
				absorbWater = 1,
			},
			inputs = {
				251
			},
			out = {
				249
			}
		},
		--- 251 ---
		{
			orbit = 2,
			orbitDist = 118,
			name = "Attribute",
			orbitIndex = 120,
			group = 62,
			icon = "absorbEarth",
			customStats = {
				absorbEarth = 1,
			},
			inputs = {
				242, 252
			},
			out = {
				250
			}
		},
		--- 252 ---
		{
			orbit = 2,
			orbitDist = 115,
			name = "Attribute",
			orbitIndex = 180,
			group = 62,
			icon = "healthDamage",
			customStats = {
				incrementHealth = 2,
			},
			inputs = {
			    243
			},
			out = {
				248, 251
			}
		},
		--- 253 ---
		{
			orbit = 0,
			orbitDist = 0,
			name = "Heart of Darkness",
			orbitIndex = 0,
			group = 62,
			isMythic = true,
			icon = "heartOfDarkness",
			customStats = {
				absorbAllElements = 1,
				experience = 10
			},
			inputs = {
			    245
			},
			out = {
				
			}
		},
		--- 254 ---
		{
			orbit = 2,
			orbitDist = 115,
			name = "Attribute",
			orbitIndex = 1,
			group = 63,
			icon = "strength",
			customStats = {
				strength = 1,
			},
			inputs = {
				244
			},
			out = {
				255, 258
			}
		},
		--- 255 ---
		{
			orbit = 2,
			orbitDist = 115,
			name = "Attribute",
			orbitIndex = -59,
			group = 63,
			icon = "life",
			customStats = {
				vitality = 2,
			},
			inputs = {
				238, 254
			},
			out = {
				256
			}
		},
		--- 256 ---
		{
			orbit = 1,
			orbitDist = 115,
			name = "Attribute",
			orbitIndex = 270,
			group = 63,
			icon = "arcaneDamage",
			customStats = {
				incrementArcane = 2,
			},
			inputs = {
				255
			},
			out = {
				257
			}
		},
		--- 257 ---
		{
			orbit = 2,
			orbitDist = 115,
			name = "Attribute",
			orbitIndex = 240,
			group = 63,
			icon = "physicalDamage",
			customStats = {
				incrementPhysical = 2,
			},
			inputs = {
				256
			},
			out = {
				261
			}
		},
		--- 258 ---
		{
			orbit = 2,
			orbitDist = 118,
			name = "Attribute",
			orbitIndex = 60,
			group = 63,
			icon = "mana",
			customStats = {
				wisdom = 2,
			},
			inputs = {
				240, 254
			},
			out = {
				259
			}
		},
		--- 259 ---
		{
			orbit = 1,
			orbitDist = 118,
			name = "Attribute",
			orbitIndex = 90,
			group = 63,
			icon = "absorbArcane",
			customStats = {
				absorbArcane = 1,
			},
			inputs = {
				258
			},
			out = {
				260
			}
		},
		--- 260 ---
		{
			orbit = 2,
			orbitDist = 118,
			name = "Attribute",
			orbitIndex = 120,
			group = 63,
			icon = "absorbPhysical",
			customStats = {
				absorbPhysical = 1,
			},
			inputs = {
				259
			},
			out = {
				261
			}
		},
		--- 261 ---
		{
			orbit = 2,
			orbitDist = 115,
			name = "Attribute",
			orbitIndex = 180,
			group = 63,
			icon = "deathDamage",
			customStats = {
				incrementDeath = 2,
				absorbDeath = 1
			},
			inputs = {
			   257, 260
			},
			out = {
				262, 490
			}
		},
		--- 262 ---
		{
			orbit = 0,
			orbitDist = 0,
			name = "Discipline of the Forbidden",
			orbitIndex = 0,
			isMythic = true,
			group = 63,
			icon = "disciplineForbidden",
			customStats = {
				incrementHealth = 3,
				incrementLifeDrain = 3,
				incrementManaDrain = 3,
				incrementPhysical = 3,
				loot = 10,

			},
			inputs = {
			    261
			},
			out = {
				
			}
		},
		--- 263 ---
		{
			orbit = 1,
			orbitDist = 39,
			name = "Attribute",
			orbitIndex = 60,
			group = 64,
			icon = "cooldownRecovery",
			customStats = {
				wisdom = 2,
			},
			inputs = {
				264
			},
			out = {
				278
			}
		},
		--- 264 ---
		{
			orbit = 1,
			orbitDist = 39,
			name = "Speed",
			orbitIndex = 180,
			group = 64,
			icon = "speed",
			customStats = {
				speed = 200,
			},
			inputs = {
				71
			},
			out = {
				263, 265
			}
		},
		--- 265 ---
		{
			orbit = 1,
			orbitDist = 39,
			name = "Attribute",
			orbitIndex = 300,
			group = 64,
			icon = "cooldownRecovery",
			customStats = {
				wisdom = 2,
			},
			inputs = {
				264
			},
			out = {
				275
			}
		},
		--- 266 ---
		{
			orbit = 1,
			orbitDist = 39,
			name = "Attribute",
			orbitIndex = 300,
			group = 65,
			icon = "mana",
			customStats = {
				spirit = 2,
			},
			inputs = {
				268
			},
			out = {
				282
			}
		},
		--- 267 ---
		{
			orbit = 1,
			orbitDist = 39,
			name = "Attribute",
			orbitIndex = 60,
			group = 65,
			icon = "mana",
			customStats = {
				spirit = 2,
			},
			inputs = {
				268
			},
			out = {
				285
			}
		},
		--- 268 ---
		{
			orbit = 1,
			orbitDist = 39,
			name = "Speed",
			orbitIndex = 180,
			group = 65,
			icon = "speed",
			customStats = {
				speed = 200,
			},
			inputs = {
				75
			},
			out = {
				266, 267
			}
		},
		--- 269 ---
		{
			orbit = 1,
			orbitDist = 39,
			name = "Speed",
			orbitIndex = 362,
			group = 66,
			icon = "speed",
			customStats = {
				speed = 200,
			},
			inputs = {
				74
			},
			out = {
				270, 271
			}
		},
		--- 270 ---
		{
			orbit = 1,
			orbitDist = 39,
			name = "Attribute",
			orbitIndex = 482,
			group = 66,
			icon = "dexterity",
			customStats = {
				dexterity = 2,
			},
			inputs = {
				269
			},
			out = {
				301
			}
		},
		--- 271 ---
		{
			orbit = 1,
			orbitDist = 39,
			name = "Attribute",
			orbitIndex = 239,
			group = 66,
			icon = "dexterity",
			customStats = {
				dexterity = 2,
			},
			inputs = {
				269
			},
			out = {
				298
			}
		},
		--- 272 ---
		{
			orbit = 1,
			orbitDist = 39,
			name = "Speed",
			orbitIndex = 362,
			group = 67,
			icon = "speed",
			customStats = {
				speed = 200,
			},
			inputs = {
				76
			},
			out = {
				273, 274
			}
		},
		--- 273 ---
		{
			orbit = 1,
			orbitDist = 39,
			name = "Attribute",
			orbitIndex = 482,
			group = 67,
			icon = "strength",
			customStats = {
				strength = 2,
			},
			inputs = {
				272
			},
			out = {
				294
			}
		},
		--- 274 ---
		{
			orbit = 1,
			orbitDist = 39,
			name = "Attribute",
			orbitIndex = 239,
			group = 67,
			icon = "strength",
			customStats = {
				strength = 2,
			},
			inputs = {
				272
			},
			out = {
				291
			}
		},
		--- 275 ---
		{
			orbit = 1,
			orbitDist = 43,
			name = "Attribute",
			orbitIndex = 180,
			group = 68,
			icon = "lifeLeechChance",
			customStats = {
				lifeLeechChance = 1,
				lifeLeechAmount = 2
			},
			inputs = {
				265
			},
			out = {
				276
			}
		},
		--- 276 ---
		{
			orbit = 1,
			orbitDist = 43,
			name = "Attribute",
			orbitIndex = 270,
			group = 68,
			icon = "criticalHitChance",
			customStats = {
				criticalHitChance = 1,
				criticalHitAmount = 1
			},
			inputs = {
				275
			},
			out = {
				277
			}
		},
		--- 277 ---
		{
			orbit = 1,
			orbitDist = 43,
			name = "Attribute",
			orbitIndex = 359,
			group = 68,
			icon = "shieldingSkill",
			customStats = {
				shieldingSkill = 2,
			},
			inputs = {
				276
			},
			out = {
				281
			}
		},
		--- 278 ---
		{
			orbit = 1,
			orbitDist = 43,
			name = "Attribute",
			orbitIndex = 180,
			group = 69,
			icon = "manaLeechChance",
			customStats = {
				manaLeechChance = 1,
				manaLeechAmount = 2
			},
			inputs = {
				263
			},
			out = {
				279
			}
		},
		--- 279 ---
		{
			orbit = 1,
			orbitDist = 43,
			name = "Attribute",
			orbitIndex = 90,
			group = 69,
			icon = "criticalHitChance",
			customStats = {
				criticalHitChance = 1,
				criticalHitAmount = 1
			},
			inputs = {
				278
			},
			out = {
				280
			}
		},
		--- 280 ---
		{
			orbit = 1,
			orbitDist = 43,
			name = "Attribute",
			orbitIndex = 1,
			group = 69,
			icon = "shieldingSkill",
			customStats = {
				shieldingSkill = 2,
			},
			inputs = {
				279
			},
			out = {
				281
			}
		},
		--- 281 ---
		{
			orbit = 0,
			orbitDist = 0,
			name = "Arcing Blows",
			isMythic = true,
			orbitIndex = 0,
			group = 70,
			icon = "heartAndSoul",
			customStats = {
				wisdom = 10,
				loot = 10,
				speed = 200,
				multiIncrement = 3,
				absorbAllElements = 2
			},
			inputs = {
				277, 280
			},
			out = {
				
			}
		},
		--- 282 ---
		{
			orbit = 1,
			orbitDist = 43,
			name = "Attribute",
			orbitIndex = 180,
			group = 72,
			icon = "lifeLeechChance",
			customStats = {
				lifeLeechChance = 1,
				lifeLeechAmount = 2
			},
			inputs = {
				266
			},
			out = {
				283
			}
		},
		--- 283 ---
		{
			orbit = 1,
			orbitDist = 43,
			name = "Attribute",
			orbitIndex = 270,
			group = 72,
			icon = "criticalHitChance",
			customStats = {
				criticalHitChance = 1,
				criticalHitAmount = 1
			},
			inputs = {
				282
			},
			out = {
				284
			}
		},
		--- 284 ---
		{
			orbit = 1,
			orbitDist = 43,
			name = "Attribute",
			orbitIndex = 359,
			group = 72,
			icon = "craftingSkill",
			customStats = {
				craftingSkill = 1,
				woodcuttingSkill = 1,
				miningSkill = 1,
				herbalistSkill = 1,
				jewelsmithSkill = 1,
				armorsmithSkill = 1,
				weaponsmithSkill = 1
			},
			inputs = {
				283
			},
			out = {
				288
			}
		},
		--- 285 ---
		{
			orbit = 1,
			orbitDist = 43,
			name = "Attribute",
			orbitIndex = 180,
			group = 71,
			icon = "manaLeechChance",
			customStats = {
				manaLeechChance = 1,
				manaLeechAmount = 2
			},
			inputs = {
				267
			},
			out = {
				286
			}
		},
		--- 286 ---
		{
			orbit = 1,
			orbitDist = 43,
			name = "Attribute",
			orbitIndex = 90,
			group = 71,
			icon = "criticalHitChance",
			customStats = {
				criticalHitChance = 1,
				criticalHitAmount = 1
			},
			inputs = {
				285
			},
			out = {
				287
			}
		},
		--- 287 ---
		{
			orbit = 1,
			orbitDist = 43,
			name = "Attribute",
			orbitIndex = 1,
			group = 71,
			icon = "craftingSkill",
			customStats = {
				craftingSkill = 1,
				woodcuttingSkill = 1,
				miningSkill = 1,
				herbalistSkill = 1,
				jewelsmithSkill = 1,
				armorsmithSkill = 1,
				weaponsmithSkill = 1
			},
			inputs = {
				286
			},
			out = {
				288
			}
		},
		--- 288 ---
		{
			orbit = 0,
			orbitDist = 0,
			name = "Depth Perception",
			isMythic = true,
			orbitIndex = 0,
			group = 73,
			icon = "orbHunter",
			customStats = {
				spirit = 10,
				experience = 10,
				speed = 200,
				multiIncrement = 3,
				absorbAllElements = 2
			},
			inputs = {
				284, 287
			},
			out = {
				
			}
		},
		--- 289 ---
		{
			orbit = 1,
			orbitDist = 43,
			name = "Attribute",
			orbitIndex = 180,
			group = 74,
			icon = "axeSkill",
			customStats = {
				axeSkill = 1,
				clubSkill = 1,
				swordSkill = 1

			},
			inputs = {
				290
			},
			out = {
				295
			}
		},
		--- 290 ---
		{
			orbit = 1,
			orbitDist = 43,
			name = "Attribute",
			orbitIndex = 270,
			group = 74,
			icon = "criticalHitChance",
			customStats = {
				criticalHitChance = 1,
				criticalHitAmount = 1
			},
			inputs = {
				291
			},
			out = {
				289
			}
		},
		--- 291 ---
		{
			orbit = 1,
			orbitDist = 43,
			name = "Attribute",
			orbitIndex = 359,
			group = 74,
			icon = "lifeLeechChance",
			customStats = {
				lifeLeechChance = 1,
				lifeLeechAmount = 2
			},
			inputs = {
				274
			},
			out = {
				290
			}
		},
		--- 292 ---
		{
			orbit = 1,
			orbitDist = 43,
			name = "Attribute",
			orbitIndex = 180,
			group = 75,
			icon = "clubSkill",
			customStats = {
				axeSkill = 1,
				clubSkill = 1,
				swordSkill = 1

			},
			inputs = {
				293
			},
			out = {
				295
			}
		},
		--- 293 ---
		{
			orbit = 1,
			orbitDist = 43,
			name = "Attribute",
			orbitIndex = 90,
			group = 75,
			icon = "criticalHitChance",
			customStats = {
				criticalHitChance = 1,
				criticalHitAmount = 1
			},
			inputs = {
				294
			},
			out = {
				292
			}
		},
		--- 294 ---
		{
			orbit = 1,
			orbitDist = 43,
			name = "Attribute",
			orbitIndex = 1,
			group = 75,
			icon = "manaLeechChance",
			customStats = {
				manaLeechChance = 1,
				manaLeechAmount = 2
			},
			inputs = {
				273
			},
			out = {
				293
			}
		},
		--- 295 ---
		{
			orbit = 0,
			orbitDist = 0,
			name = "Lursk Bringer",
			isMythic = true,
			orbitIndex = 0,
			group = 76,
			icon = "lurskBringer",
			customStats = {
				strength = 10,
				rarityLoot = 10,
				speed = 200,
				multiIncrement = 3,
				absorbAllElements = 2
			},
			inputs = {
				289, 292
			},
			out = {
				
			}
		},
		--- 296 ---
		{
			orbit = 1,
			orbitDist = 43,
			name = "Attribute",
			orbitIndex = 180,
			group = 78,
			icon = "distanceSkill",
			customStats = {
				distanceSkill = 1,
			},
			inputs = {
				297
			},
			out = {
				302
			}
		},
		--- 297 ---
		{
			orbit = 1,
			orbitDist = 43,
			name = "Attribute",
			orbitIndex = 270,
			group = 78,
			icon = "criticalHitChance",
			customStats = {
				criticalHitChance = 1,
				criticalHitAmount = 1
			},
			inputs = {
				298
			},
			out = {
				296
			}
		},
		--- 298 ---
		{
			orbit = 1,
			orbitDist = 43,
			name = "Attribute",
			orbitIndex = 359,
			group = 78,
			icon = "lifeLeechChance",
			customStats = {
				lifeLeechChance = 1,
				lifeLeechAmount = 2
			},
			inputs = {
				271
			},
			out = {
				297
			}
		},
		--- 299 ---
		{
			orbit = 1,
			orbitDist = 43,
			name = "Attribute",
			orbitIndex = 180,
			group = 77,
			icon = "distanceSkill",
			customStats = {
				distanceSkill = 1,
			},
			inputs = {
				300	
			},
			out = {
				302
			}
		},
		--- 300 ---
		{
			orbit = 1,
			orbitDist = 43,
			name = "Attribute",
			orbitIndex = 90,
			group = 77,
			icon = "criticalHitChance",
			customStats = {
				criticalHitChance = 1,
				criticalHitAmount = 1
			},
			inputs = {
				301
			},
			out = {
				299
			}
		},
		--- 301 ---
		{
			orbit = 1,
			orbitDist = 43,
			name = "Attribute",
			orbitIndex = 1,
			group = 77,
			icon = "manaLeechChance",
			customStats = {
				manaLeechChance = 1,
				manaLeechAmount = 2
			},
			inputs = {
				270
			},
			out = {
				300
			}
		},
		--- 302 ---
		{
			orbit = 0,
			orbitDist = 0,
			name = "Mysticism",
			isMythic = true,
			orbitIndex = 0,
			group = 79,
			icon = "mysticism",
			customStats = {
				dexterity = 10,
				loot = 10,
				speed = 200,
				multiIncrement = 3,
				absorbAllElements = 2
			},
			inputs = {
				296, 299
			},
			out = {
				
			}
		},
		--- 303 ---
		{
			orbit = 1,
			orbitDist = 72,
			name = "Attribute",
			orbitIndex = 146,
			group = 80,
			icon = "jewelsmithSkill",
			customStats = {
				jewelsmithSkill = 1,
			},
			inputs = {
				244
			},
			out = {
				307
			}
		},
		--- 304 ---
		{
			orbit = 1,
			orbitDist = 70,
			name = "Attribute",
			orbitIndex = 211,
			group = 80,
			icon = "weaponsmithSkill",
			customStats = {
				weaponsmithSkill = 1,
			},
			inputs = {
				244
			},
			out = {
				308
			}
		},
		--- 305 ---
		{
			orbit = 1,
			orbitDist = 72,
			name = "Attribute",
			orbitIndex = 30,
			group = 80,
			icon = "herbalistSkill",
			customStats = {
				herbalistSkill = 1,
			},
			inputs = {
				307
			},
			out = {
			    309	
			}
		},
		--- 306 ---
		{
			orbit = 1,
			orbitDist = 70,
			name = "Attribute",
			orbitIndex = 334,
			group = 80,
			icon = "armorsmithSkill",
			customStats = {
				armorsmithSkill = 1,
			},
			inputs = {
				308
			},
			out = {
				309
			}
		},
		--- 307 ---
		{
			orbit = 1,
			orbitDist = 70,
			name = "Attribute",
			orbitIndex = 90,
			group = 80,
			icon = "miningSkill",
			customStats = {
				miningSkill = 1,
			},
			inputs = {
				303
			},
			out = {
				305
			}
		},
		--- 308 ---
		{
			orbit = 1,
			orbitDist = 70,
			name = "Attribute",
			orbitIndex = 270,
			group = 80,
			icon = "woodcuttingSkill",
			customStats = {
				woodcuttingSkill = 1,
			},
			inputs = {
				304
			},
			out = {
				306
			}
		},
		--- 309 ---
		{
			orbit = 0,
			orbitDist = 0,
			name = "Master Skill",
			orbitIndex = 270,
			group = 80,
			icon = "masterSkill",
			isVeryRare = true,
			customStats = {
				craftingSkill = 2,
				herbalistSkill = 2,
				woodcuttingSkill = 2,
				miningSkill = 2,
				jewelsmithSkill = 2,
				weaponsmithSkill = 2,
				armorsmithSkill = 2
			},
			inputs = {
				305, 306 
			},
			out = {
			
			}
		},
		--- 310 ---
		{
			orbit = 1,
			orbitDist = 72,
			name = "Attribute",
			orbitIndex = 146,
			group = 81,
			icon = "absorbPhysical",
			customStats = {
				absorbPhysical = 1,
			},
			inputs = {
				314
			},
			out = {
				316
			}
		},
		--- 311 ---
		{
			orbit = 1,
			orbitDist = 70,
			name = "Attribute",
			orbitIndex = 211,
			group = 81,
			icon = "absorbFire",
			customStats = {
				absorbFire = 1,
			},
			inputs = {
				315	
			},
			out = {
				316
			}
		},
		--- 312 ---
		{
			orbit = 1,
			orbitDist = 72,
			name = "Attribute",
			orbitIndex = 30,
			group = 81,
			icon = "intelligence",
			customStats = {
				intelligence = 1,
			},
			inputs = {
				243
			},
			out = {
			    314	
			}
		},
		--- 313 ---
		{
			orbit = 1,
			orbitDist = 70,
			name = "Attribute",
			orbitIndex = 334,
			group = 81,
			icon = "strength",
			customStats = {
				strength = 1,
			},
			inputs = {
				243
			},
			out = {
				315
			}
		},
		--- 314 ---
		{
			orbit = 1,
			orbitDist = 70,
			name = "Attribute",
			orbitIndex = 90,
			group = 81,
			icon = "coldDamage",
			customStats = {
				incrementIce = 2,
			},
			inputs = {
				312
			},
			out = {
				310
			}
		},
		--- 315 ---
		{
			orbit = 1,
			orbitDist = 70,
			name = "Attribute",
			orbitIndex = 270,
			group = 81,
			icon = "physicalDamage",
			customStats = {
				incrementPhysical = 2
			},
			inputs = {
				313
			},
			out = {
				311
			}
		},
		--- 316 ---
		{
			orbit = 0,
			orbitDist = 0,
			name = "Blunt Trauma",
			isVeryRare = true,
			orbitIndex = 0,
			group = 81,
			icon = "bluntTrauma",
			customStats = {
				criticalHitChance = 2,
				criticalHitAmount = 3,
				wisdom = 5,
				multiIncrement = 1
			},
			inputs = {
				310, 311 
			},
			out = {
			
			}
		},
		--- 317 ---
		{
			orbit = 2,
			orbitDist = 115,
			name = "Attribute",
			orbitIndex = 60,
			group = 82,
			icon = "lifeManaDrain",
			customStats = {
				incrementLifeDrain = 2,
			},
			inputs = {
			  	326
			},
			out = {
			 	325
			}
		},
		--- 318 ---
		{
			orbit = 2,
			orbitDist = 115,
			name = "Attribute",
			orbitIndex = 0,
			group = 82,
			icon = "life",
			customStats = {
				vitality = 2,
			},
			inputs = {
				325
			},
			out = {
				329, 319
			}
		},
		--- 319 ---
		{
			orbit = 1,
			orbitDist = 115,
			name = "Attribute",
			orbitIndex = 330,
			group = 82,
			icon = "absorbPhysical",
			customStats = {
				absorbPhysical = 2,
			},
			inputs = {
				318
			},
			out = {
				320
			}
		},
		--- 320 ---
		{
			orbit = 2,
			orbitDist = 115,
			name = "Attribute",
			orbitIndex = 300,
			group = 82,
			icon = "shieldingSkill",
			customStats = {
				shieldingSkill = 1,
			},
			inputs = {
				319
			},
			out = {
				327
			}
		},
		--- 321 ---
		{
			orbit = 2,
			orbitDist = 118,
			name = "Attribute",
			orbitIndex = 120,
			group = 82,
			icon = "lifeManaDrain",
			customStats = {
				incrementManaDrain = 2,
			},
			inputs = {
				326
			},
			out = {
				326, 322
			}
		},
		--- 322 ---
		{
			orbit = 1,
			orbitDist = 118,
			name = "Attribute",
			orbitIndex = 150,
			group = 82,
			icon = "drownDamage",
			customStats = {
				incrementDrown = 2,
			},
			inputs = {
				323, 321
			},
			out = {
				321
			}
		},
		--- 323 ---
		{
			orbit = 2,
			orbitDist = 118,
			name = "Attribute",
			orbitIndex = 180,
			group = 82,
			icon = "life",
			customStats = {
				vitality = 2,
			},
			inputs = {
				328
			},
			out = {
				332, 322
			}
		},
		--- 324 ---
		{
			orbit = 2,
			orbitDist = 115,
			name = "Attribute",
			orbitIndex = 240,
			group = 82,
			icon = "shieldingSkill",
			customStats = {
				shieldingSkill = 1,
			},
			inputs = {
				327
			},
			out = {
				328
			}
		},
		--- 325 ---
		{
			orbit = 1,
			orbitDist = 115,
			name = "Attribute",
			orbitIndex = 30,
			group = 82,
			icon = "drownDamage",
			customStats = {
				incrementDrown = 2,
			},
			inputs = {
				317
			},
			out = {
				318
			}
		},
		--- 326 ---
		{
			orbit = 1,
			orbitDist = 115,
			name = "Attribute",
			orbitIndex = 90,
			group = 82,
			icon = "speed",
			customStats = {
				speed = 300,
			},
			inputs = {
				146, 147, 317, 321	
			},
			out = {
				317
			}
		},
		--- 327 ---
		{
			orbit = 1,
			orbitDist = 115,
			name = "Attribute",
			orbitIndex = 270,
			group = 82,
			icon = "criticalHitChance",
			customStats = {
				criticalHitChance = 2,
				criticalHitAmount = 3
			},
			inputs = {
				320
			},
			out = {
				324
			}
		},
		--- 328 ---
		{
			orbit = 1,
			orbitDist = 115,
			name = "Attribute",
			orbitIndex = 210,
			group = 82,
			icon = "physicalDamage",
			customStats = {
				incrementPhysical = 2,
			},
			inputs = {
				324
			},
			out = {
				323
			}
		},
		--- 329 ---
		{
			orbit = 1,
			orbitDist = 50,
			name = "Bastion of Faith",
			orbitIndex = 1,
			group = 82,
			isRare = true,
			icon = "longLife",
			customStats = {
				vitality = 10,
				spirit = 5,
				wisdom = 5,
				strength = 5
			},
			inputs = {
				318
			},
			out = {
				330, 331
			}
		},
		--- 330 ---
		{
			orbit = 0,
			orbitDist = 50,
			name = "Purity of Robustness",
			isRare = true,
			orbitIndex = 90,
			group = 82,
			icon = "brokenPast",
			customStats = {
				strength = 10,
				skillShield = 1,
				lifeLeechChance = 2,
				lifeLeechAmount = 3
			},
			inputs = {
				329
			},
			out = {
				332, 329
			}
		},
		--- 331 ---
		{
			orbit = 0,
			orbitDist = 50,
			isRare = true,
			name = "Galvanick",
			orbitIndex = 270,
			group = 82,
			icon = "deactivity",
			customStats = {
				dexterity = 10,
				speed = 300,
				manaLeechChance = 2,
				manaLeechAmount = 3
			},
			inputs = {
				329, 332
			},
			out = {
				332, 329
			}
		},
		--- 332 ---
		{
			orbit = 1,
			orbitDist = 50,
			isRare = true,
			name = "Sanctity",
			orbitIndex = 180,
			group = 82,
			icon = "defensiveWay",
			customStats = {
				absorbEnergy = 1,
				absorbPhysical = 1,
				incrementPhysical = 2,
				incrementEnergy = 2
			},
			inputs = {
				323
			},
			out = {
				331, 330
			}
		},
		--- 333 ---
		{
			orbit = 2,
			orbitDist = 115,
			name = "Attribute",
			orbitIndex = 0,
			group = 83,
			icon = "intelligence",
			customStats = {
				intelligence = 2,
			},
			inputs = {
				334
			},
			out = {
				340, 344
			}
		},
		--- 334 ---
		{
			orbit = 1,
			orbitDist = 115,
			name = "Attribute",
			orbitIndex = 330,
			group = 83,
			icon = "absorbDeath",
			customStats = {
				absorbDeath = 1,
			},
			inputs = {
				335
			},
			out = {
				333
			}
		},
		--- 335 ---
		{
			orbit = 2,
			orbitDist = 115,
			name = "Attribute",
			orbitIndex = 300,
			group = 83,
			icon = "coldDamage",
			customStats = {
				incrementIce = 1,
			},
			inputs = {
				342
			},
			out = {
				334
			}
		},
		--- 336 ---
		{
			orbit = 2,
			orbitDist = 118,
			name = "Attribute",
			orbitIndex = 120,
			group = 83,
			icon = "mana",
			customStats = {
				spirit = 2,
			},
			inputs = {
				341
			},
			out = {
				337
			}
		},
		--- 337 ---
		{
			orbit = 1,
			orbitDist = 118,
			name = "Attribute",
			orbitIndex = 150,
			group = 83,
			icon = "shieldingSkill",
			customStats = {
				shieldingSkill = 1,
			},
			inputs = {
				336
			},
			out = {
				338
			}
		},
		--- 338 ---
		{
			orbit = 2,
			orbitDist = 118,
			name = "Attribute",
			orbitIndex = 180,
			group = 83,
			icon = "intelligence",
			customStats = {
				intelligence = 2,
			},
			inputs = {
				337
			},
			out = {
				343, 347
			}
		},
		--- 339 ---
		{
			orbit = 2,
			orbitDist = 115,
			name = "Attribute",
			orbitIndex = 240,
			group = 83,
			icon = "absorbIce",
			customStats = {
				absorbIce = 1,
			},
			inputs = {
				342, 343
			},
			out = {
				
			}
		},
		--- 340 ---
		{
			orbit = 1,
			orbitDist = 115,
			name = "Attribute",
			orbitIndex = 30,
			group = 83,
			icon = "magicSkill",
			customStats = {
				magicSkill = 1,
			},
			inputs = {
				333
			},
			out = {
				348
			}
		},
		--- 341 ---
		{
			orbit = 1,
			orbitDist = 115,
			name = "Attribute",
			orbitIndex = 90,
			group = 83,
			icon = "manaLeechChance",
			customStats = {
				manaLeechChance = 1,
				manaLeechAmount = 2,
			},
			inputs = {
				348
			},
			out = {
				336
			}
		},
		--- 342 ---
		{
			orbit = 1,
			orbitDist = 115,
			name = "Attribute",
			orbitIndex = 270,
			group = 83,
			icon = "speed",
			customStats = {
				speed = 300,
			},
			inputs = {
				148, 149
			},
			out = {
				335, 339
			}
		},
		--- 343 ---
		{
			orbit = 1,
			orbitDist = 115,
			name = "Attribute",
			orbitIndex = 210,
			group = 83,
			icon = "deathDamage",
			customStats = {
				incrementDeath = 1,
			},
			inputs = {
				338
			},
			out = {
				339
			}
		},
		--- 344 ---
		{
			orbit = 1,
			orbitDist = 50,
			name = "Soul of Steel",
			orbitIndex = 1,
			group = 83,
			isRare = true,
			icon = "soulOfSteel",
			customStats = {
				intelligence = 5,
				spirit = 3,
				vitality = 3,
				dexterity = 2
			},
			inputs = {
				333
			},
			out = {
				346, 345
			}
		},
		--- 345 ---
		{
			orbit = 0,
			orbitDist = 50,
			name = "Natural Wrath",
			isRare = true,
			orbitIndex = 90,
			group = 83,
			icon = "naturalWrath",
			customStats = {
				incrementEarth = 2,
				incrementFire = 2,
				absorbEarth = 1,
				absorbFire = 1
			},
			inputs = {
				344
			},
			out = {
				347
			}
		},
		--- 346 ---
		{
			orbit = 0,
			orbitDist = 50,
			isRare = true,
			name = "Wi Hazard",
			orbitIndex = 270,
			group = 83,
			icon = "wihazard",
			customStats = {
				manaLeechChance = 2,
				manaLeechAmount = 3,
				magicSkill = 1
			},
			inputs = {
				344
			},
			out = {
				347
			}
		},
		--- 347 ---
		{
			orbit = 1,
			orbitDist = 50,
			isRare = true,
			name = "Enslaved Fighter",
			orbitIndex = 180,
			group = 83,
			icon = "charisma",
			customStats = {
				incrementEnergy = 2,
				incrementIce = 2,
				absorbFire = 1,
				absorbEarth = 1
			},
			inputs = {
				338, 345, 346
			},
			out = {
				
			}
		},
		--- 348 ---
		{
			orbit = 2,
			orbitDist = 115,
			name = "Attribute",
			orbitIndex = 60,
			group = 83,
			icon = "cooldownRecovery",
			customStats = {
				wisdom = 2,
			},
			inputs = {
				340
			},
			out = {
				341
			}
		},
		--- 349 ---
		{
			orbit = 3,
			orbitDist = 70,
			name = "Attribute",
			orbitIndex = 209,
			group = 84,
			icon = "absorbIce",
			customStats = {
				absorbIce = 1,
			},
			inputs = {
				350
			},
			out = {
				352, 448
			}
		},
		--- 350 ---
		{
			orbit = 2,
			orbitDist = 72,
			name = "Attribute",
			orbitIndex = 148,
			group = 84,
			icon = "criticalHitAmount",
			customStats = {
				criticalHitChance = 1,
				criticalHitAmount = 1
			},
			inputs = {
			   164
			},
			out = {
			    351, 349
			}
		},
		--- 351 ---
		{
			orbit = 1,
			orbitDist = 70,
			name = "Attribute",
			orbitIndex = 88,
			group = 84,
			icon = "coldDamage",
			customStats = {
				incrementIce = 1,
			},
			inputs = {
				350
			},
			out = {
				354
			}
		},
		--- 352 ---
		{
			orbit = 2,
			orbitDist = 70,
			name = "Attribute",
			orbitIndex = 270,
			group = 84,
			icon = "absorbLife",
			customStats = {
				absorbLife = 1,
			},
			inputs = {
				349
			},
			out = {
				353
			}
		},
		--- 353 ---
		{
			orbit = 3,
			orbitDist = 70,
			name = "Attribute",
			orbitIndex = 330,
			group = 84,
			icon = "deathDamage",
			customStats = {
				incrementDeath = 2,
			},
			inputs = {
				354, 352, 355
			},
			out = {
				355, 364
			}
		},
		--- 354 ---
		{
			orbit = 2,
			orbitDist = 70,
			name = "Attribute",
			orbitIndex = 30,
			group = 84,
			icon = "absorbMana",
			customStats = {
				absorbMana = 1,
			},
			inputs = {
				351
			},
			out = {
				353
			}
		},
		--- 355 ---
		{
			orbit = 0,
			orbitDist = 0,
			name = "Attribute",
			isMythic = true,
			orbitIndex = 0,
			group = 84,
			icon = "criticalHitChance",
			customStats = {
				criticalHitChance = 3,
				criticalHitAmount = 5
			},
			inputs = {
				353
			},
			out = {
				
			}
		},
		--- 356 ---
		{
			orbit = 3,
			orbitDist = 70,
			name = "Attribute",
			orbitIndex = 209,
			group = 85,
			icon = "life",
			customStats = {
				vitality = 2,
			},
			inputs = {
				357, 359
			},
			out = {
				362, 368
			}
		},
		--- 357 ---
		{
			orbit = 2,
			orbitDist = 72,
			name = "Attribute",
			orbitIndex = 148,
			group = 85,
			icon = "absorbEnergy",
			customStats = {
				absorbEnergy = 1,
			},
			inputs = {
			   358
			},
			out = {
			   356
			}
		},
		--- 358 ---
		{
			orbit = 1,
			orbitDist = 70,
			name = "Attribute",
			orbitIndex = 88,
			group = 85,
			icon = "healthDamage",
			customStats = {
				incrementHealth = 2,
			},
			inputs = {
				361
			},
			out = {
				357
			}
		},
		--- 359 ---
		{
			orbit = 2,
			orbitDist = 70,
			name = "Attribute",
			orbitIndex = 270,
			group = 85,
			icon = "lightningDamage",
			customStats = {
				incrementEnergy = 2,
			},
			inputs = {
				360
			},
			out = {
				356
			}
		},
		--- 360 ---
		{
			orbit = 3,
			orbitDist = 70,
			name = "Attribute",
			orbitIndex = 330,
			group = 85,
			icon = "life",
			customStats = {
				vitality = 2,
			},
			inputs = {
				361
			},
			out = {
				359, 411
			}
		},
		--- 361 ---
		{
			orbit = 2,
			orbitDist = 70,
			name = "Attribute",
			orbitIndex = 30,
			group = 85,
			icon = "loot",
			customStats = {
				loot = 10,
			},
			inputs = {
				152
			},
			out = {
				358, 360
			}
		},
		--- 362 ---
		{
			orbit = 0,
			orbitDist = 0,
			name = "Attribute",
			isMythic = true,
			orbitIndex = 0,
			group = 85,
			icon = "life",
			customStats = {
				vitality = 10,
			},
			inputs = {
				356
			},
			out = {
				
			}
		},
		--- 363 ---
		{
			orbit = 3,
			orbitDist = 70,
			name = "Attribute",
			orbitIndex = 209,
			group = 86,
			icon = "shieldingSkill",
			customStats = {
				shieldingSkill = 1,
			},
			inputs = {
				364
			},
			out = {
				366
			}
		},
		--- 364 ---
		{
			orbit = 2,
			orbitDist = 72,
			name = "Attribute",
			orbitIndex = 148,
			group = 86,
			icon = "clubSkill",
			customStats = {
				clubSkill = 1,
			},
			inputs = {
			   364, 353
			},
			out = {
			   363
			}
		},
		--- 365 ---
		{
			orbit = 1,
			orbitDist = 70,
			name = "Attribute",
			orbitIndex = 88,
			group = 86,
			icon = "magicSkill",
			customStats = {
				magicSkill = 1,
			},
			inputs = {
				368
			},
			out = {
				364
			}
		},
		--- 366 ---
		{
			orbit = 2,
			orbitDist = 70,
			name = "Attribute",
			orbitIndex = 270,
			group = 86,
			icon = "axeSkill",
			customStats = {
				axeSkill = 1,
			},
			inputs = {
				367, 363
			},
			out = {
				369, 429
			}
		},
		--- 367 ---
		{
			orbit = 3,
			orbitDist = 70,
			name = "Attribute",
			orbitIndex = 330,
			group = 86,
			icon = "swordSkill",
			customStats = {
				swordSkill = 1,
			},
			inputs = {
				368
			},
			out = {
				366
			}
		},
		--- 368 ---
		{
			orbit = 2,
			orbitDist = 70,
			name = "Attribute",
			orbitIndex = 30,
			group = 86,
			icon = "distanceSkill",
			customStats = {
				distanceSkill = 1,
			},
			inputs = {
				356
			},
			out = {
				367, 365
			}
		},
		--- 369 ---
		{
			orbit = 0,
			orbitDist = 0,
			name = "Attribute",
			isMythic = true,
			orbitIndex = 0,
			group = 86,
			icon = "mana",
			customStats = {
				spirit = 10,
			},
			inputs = {
				366
			},
			out = {
				
			}
		},
		--- 370 ---
		{
			orbit = 3,
			orbitDist = 70,
			name = "Attribute",
			orbitIndex = 209,
			group = 87,
			icon = "absorbArcane",
			customStats = {
				absorbArcane = 1,
			},
			inputs = {
				373	
			},
			out = {
				371
			}
		},
		--- 371 ---
		{
			orbit = 2,
			orbitDist = 72,
			name = "Attribute",
			orbitIndex = 148,
			group = 87,
			icon = "rarityLoot",
			customStats = {
				rarityLoot = 3,
			},
			inputs = {
			   370, 372
			},
			out = {
			   376, 388
			}
		},
		--- 372 ---
		{
			orbit = 1,
			orbitDist = 70,
			name = "Attribute",
			orbitIndex = 88,
			group = 87,
			icon = "absorbPhysical",
			customStats = {
				absorbPhysical = 1,
			},
			inputs = {
				375
			},
			out = {
				371
			}
		},
		--- 373 ---
		{
			orbit = 2,
			orbitDist = 70,
			name = "Attribute",
			orbitIndex = 270,
			group = 87,
			icon = "life",
			customStats = {
				vitality = 1,
			},
			inputs = {
				374
			},
			out = {
				370
			}
		},
		--- 374 ---
		{
			orbit = 3,
			orbitDist = 70,
			name = "Attribute",
			orbitIndex = 330,
			group = 87,
			icon = "mana",
			customStats = {
				spirit = 1,
			},
			inputs = {
				166
			},
			out = {
				373, 375
			}
		},
		--- 375 ---
		{
			orbit = 2,
			orbitDist = 70,
			name = "Attribute",
			orbitIndex = 30,
			group = 87,
			icon = "cooldownRecovery",
			customStats = {
				wisdom = 1,
			},
			inputs = {
				374
			},
			out = {
				372, 565
			}
		},
		--- 376 ---
		{
			orbit = 0,
			orbitDist = 0,
			name = "Attribute",
			isMythic = true,
			orbitIndex = 0,
			group = 87,
			icon = "healthDamage",
			customStats = {
				incrementHealth = 5,
			},
			inputs = {
				371
			},
			out = {
				
			}
		},
		--- 377 ---
		{
			orbit = 3,
			orbitDist = 70,
			name = "Attribute",
			orbitIndex = 209,
			group = 88,
			icon = "magicSkill",
			customStats = {
				magicSkill = 1,
			},
			inputs = {
				178
			},
			out = {
				378, 380
			}
		},
		--- 378 ---
		{
			orbit = 2,
			orbitDist = 72,
			name = "Attribute",
			orbitIndex = 148,
			group = 88,
			icon = "absorbFire",
			customStats = {
				absorbFire = 1,
			},
			inputs = {
			   377
			},
			out = {
			   379, 529
			}
		},
		--- 379 ---
		{
			orbit = 1,
			orbitDist = 70,
			name = "Attribute",
			orbitIndex = 88,
			group = 88,
			icon = "absorbEarth",
			customStats = {
				absorbEarth = 1,
			},
			inputs = {
				378, 382
			},
			out = {
				
			}
		},
		--- 380 ---
		{
			orbit = 2,
			orbitDist = 70,
			name = "Attribute",
			orbitIndex = 270,
			group = 88,
			icon = "fireDamage",
			customStats = {
				incrementFire = 2,
			},
			inputs = {
				377
			},
			out = {
				381	
			}
		},
		--- 381 ---
		{
			orbit = 3,
			orbitDist = 70,
			name = "Attribute",
			orbitIndex = 330,
			group = 88,
			icon = "earthDamage",
			customStats = {
				incrementEarth = 2,
			},
			inputs = {
				380
			},
			out = {
				382
			}
		},
		--- 382 ---
		{
			orbit = 2,
			orbitDist = 70,
			name = "Attribute",
			orbitIndex = 30,
			group = 88,
			icon = "distanceSkill",
			customStats = {
				distanceSkill = 1,
			},
			inputs = {
				381
			},
			out = {
				379, 383, 384
			}
		},
		--- 383 ---
		{
			orbit = 0,
			orbitDist = 0,
			name = "Attribute",
			isMythic = true,
			orbitIndex = 0,
			group = 88,
			icon = "cooldownRecovery",
			customStats = {
				wisdom = 10,
			},
			inputs = {
				382
			},
			out = {
				
			}
		},
		--- 384 ---
		{
			orbit = 3,
			orbitDist = 70,
			name = "Attribute",
			orbitIndex = 209,
			group = 89,
			icon = "speed",
			customStats = {
				speed = 150,
			},
			inputs = {
				385, 387, 382
			},
			out = {
				
			}
		},
		--- 385 ---
		{
			orbit = 2,
			orbitDist = 72,
			name = "Attribute",
			orbitIndex = 148,
			group = 89,
			icon = "dexterity",
			customStats = {
				dexterity = 1,
			},
			inputs = {
			   386
			},
			out = {
			   384
			}
		},
		--- 386 ---
		{
			orbit = 1,
			orbitDist = 70,
			name = "Attribute",
			orbitIndex = 90,
			group = 89,
			icon = "absorbIce",
			customStats = {
				absorbIce = 1,
			},
			inputs = {
				389
			},
			out = {
				385, 390, 546
			}
		},
		--- 387 ---
		{
			orbit = 2,
			orbitDist = 70,
			name = "Attribute",
			orbitIndex = 270,
			group = 89,
			icon = "fireDamage",
			customStats = {
				incrementFire = 1,
			},
			inputs = {
				388
			},
			out = {
				384
			}
		},
		--- 388 ---
		{
			orbit = 3,
			orbitDist = 70,
			name = "Attribute",
			orbitIndex = 330,
			group = 89,
			icon = "arcaneDamage",
			customStats = {
				incrementArcane = 2,
			},
			inputs = {
				371
			},
			out = {
				387, 389
			}
		},
		--- 389 ---
		{
			orbit = 2,
			orbitDist = 70,
			name = "Attribute",
			orbitIndex = 30,
			group = 89,
			icon = "absorbFire",
			customStats = {
				absorbFire = 1,
			},
			inputs = {
				388
			},
			out = {
				386
			}
		},
		--- 390 ---
		{
			orbit = 0,
			orbitDist = 0,
			name = "Attribute",
			isMythic = true,
			orbitIndex = 0,
			group = 89,
			icon = "lifeLeechChance",
			customStats = {
				lifeLeechChance = 5,
				lifeLeechAmount = 7
			},
			inputs = {
				386
			},
			out = {
				
			}
		},
		--- 391 ---
		{
			orbit = 1,
			orbitDist = 300,
			name = "Attribute",
			orbitIndex = 60,
			group = 90,
			icon = "fireDamage",
			customStats = {
				incrementFire = 1,
			},
			inputs = {
				392
			},
			out = {
				395
			}
		},
		--- 392 ---
		{
			orbit = 3,
			orbitDist = 300,
			name = "Attribute",
			orbitIndex = 120,
			group = 90,
			icon = "absorbFire",
			customStats = {
				absorbFire = 1,
			},
			inputs = {
				241, 184
			},
			out = {
				391, 393
			}
		},
		--- 393 ---
		{
			orbit = 1,
			orbitDist = 300,
			name = "Attribute",
			orbitIndex = 180,
			group = 90,
			icon = "fireDamage",
			customStats = {
				incrementFire = 1,
			},
			inputs = {
				392
			},
			out = {
				394
			}
		},
		--- 394 ---
		{
			orbit = 2,
			orbitDist = 300,
			name = "Attribute",
			orbitIndex = 240,
			group = 90,
			icon = "absorbFire",
			customStats = {
				absorbFire = 1,
			},
			inputs = {
				393
			},
			out = {
				396
			}
		},
		--- 395 ---
		{
			orbit = 3,
			orbitDist = 300,
			name = "Attribute",
			orbitIndex = 1,
			group = 90,
			icon = "absorbFire",
			customStats = {
				absorbFire = 1,
			},
			inputs = {
				391
			},
			out = {
				396
			}
		},
		--- 396 ---
		{
			orbit = 1,
			orbitDist = 300,
			name = "Attribute",
			orbitIndex = 300,
			group = 90,
			icon = "fireDamage",
			customStats = {
				incrementFire = 2,
			},
			inputs = {
				394, 395
			},
			out = {
				397
			}
		},
		--- 397 ---
		{
			orbit = 2,
			orbitDist = 180,
			name = "Attribute",
			orbitIndex = 300,
			isUncommon = true,
			group = 90,
			icon = "intelligence",
			customStats = {
				intelligence = 3,
			},
			inputs = {
				396
			},
			out = {
				398, 399
			}
		},
		--- 398 ---
		{
			orbit = 3,
			orbitDist = 180,
			name = "Attribute",
			orbitIndex = 240,
			isUncommon = true,
			group = 90,
			icon = "absorbFire",
			customStats = {
				absorbFire = 2,
			},
			inputs = {
				397
			},
			out = {
				400
			}
		},
		--- 399 ---
		{
			orbit = 3,
			orbitDist = 180,
			name = "Attribute",
			orbitIndex = 1,
			isUncommon = true,
			group = 90,
			icon = "fireDamage",
			customStats = {
				incrementFire = 4,
			},
			inputs = {
				397
			},
			out = {
				401
			}
		},
		--- 400 ---
		{
			orbit = 1,
			orbitDist = 180,
			name = "Attribute",
			orbitIndex = 180,
			isUncommon = true,
			group = 90,
			icon = "rarityLoot",
			customStats = {
				dexterity = 3,
				rarityLoot = 3,
				experience = 5
			},
			inputs = {
				398
			},
			out = {
				402
			}
		},
		--- 401 ---
		{
			orbit = 2,
			orbitDist = 180,
			name = "Attribute",
			orbitIndex = 60,
			isUncommon = true,
			group = 90,
			icon = "loot",
			customStats = {
				strength = 3,
				loot = 5,
				experience = 5
			},
			inputs = {
				399
			},
			out = {
				402
			}
		},
		--- 402 ---
		{
			orbit = 3,
			orbitDist = 180,
			name = "Attribute",
			orbitIndex = 120,
			isUncommon = true,
			group = 90,
			icon = "absorbFire",
			customStats = {
				absorbFire = 2,
				incrementFire = 4
			},
			inputs = {
				401, 400
			},
			out = {
				403
			}
		},
		--- 403 ---
		{
			orbit = 1,
			orbitDist = 90,
			name = "Attribute",
			orbitIndex = 120,
			isMythic = true,
			group = 90,
			icon = "fireDamage",
			customStats = {
				incrementFire = 5,
			},
			inputs = {
				402
			},
			out = {
				404, 408
			}
		},
		--- 404 ---
		{
			orbit = 2,
			orbitDist = 90,
			name = "Attribute",
			orbitIndex = 180,
			isMythic = true,
			group = 90,
			icon = "absorbFire",
			customStats = {
				absorbFire = 3,
			},
			inputs = {
				403
			},
			out = {
				405	
			}
		},
		--- 405 ---
		{
			orbit = 3,
			orbitDist = 90,
			name = "Attribute",
			orbitIndex = 240,
			isMythic = true,
			group = 90,
			icon = "fireDamage",
			customStats = {
				incrementFire = 6,
			},
			inputs = {
				404
			},
			out = {
				406
			}
		},
		--- 406 ---
		{
			orbit = 1,
			orbitDist = 90,
			name = "Attribute",
			orbitIndex = 300,
			isMythic = true,
			group = 90,
			icon = "absorbFire",
			customStats = {
				absorbFire = 4,
			},
			inputs = {
				407, 405
			},
			out = {
				409
			}
		},
		--- 407 ---
		{
			orbit = 3,
			orbitDist = 90,
			name = "Attribute",
			orbitIndex = 1,
			isMythic = true,
			group = 90,
			icon = "fireDamage",
			customStats = {
				incrementFire = 6,
			},
			inputs = {
				408
			},
			out = {
				406
			}
		},
		--- 408 ---
		{
			orbit = 4,
			orbitDist = 90,
			name = "Attribute",
			orbitIndex = 60,
			isMythic = true,
			group = 90,
			icon = "absorbFire",
			customStats = {
				absorbFire = 3,
			},
			inputs = {
				403
			},
			out = {
				407
			}
		},
		--- 409 ---
		{
			orbit = 0,
			orbitDist = 0,
			name = "Breath Of Flames",
			orbitIndex = 0,
			isDivine = true,
			group = 90,
			icon = "breathOfFlames",
			customStats = {
				absorbFire = 6,
				incrementFire = 15,
				shieldingSkill = 3
			},
			inputs = {
				406
			},
			out = {
				
			}
		},
		--- 410 ---
		{
			orbit = 1,
			orbitDist = 300,
			name = "Attribute",
			orbitIndex = 60,
			group = 91,
			icon = "physicalDamage",
			customStats = {
				incrementPhysical = 1,
			},
			inputs = {
				411
			},
			out = {
				414
			}
		},
		--- 411 ---
		{
			orbit = 3,
			orbitDist = 300,
			name = "Attribute",
			orbitIndex = 120,
			group = 91,
			icon = "absorbPhysical",
			customStats = {
				absorbPhysical = 1,
			},
			inputs = {
				156, 360
			},
			out = {
				412, 410
			}
		},
		--- 412 ---
		{
			orbit = 1,
			orbitDist = 300,
			name = "Attribute",
			orbitIndex = 180,
			group = 91,
			icon = "physicalDamage",
			customStats = {
				incrementPhysical = 1,
			},
			inputs = {
				411
			},
			out = {
				413
			}
		},
		--- 413 ---
		{
			orbit = 2,
			orbitDist = 300,
			name = "Attribute",
			orbitIndex = 240,
			group = 91,
			icon = "absorbPhysical",
			customStats = {
				absorbPhysical = 1,
			},
			inputs = {
				412
			},
			out = {
				415
			}
		},
		--- 414 ---
		{
			orbit = 3,
			orbitDist = 300,
			name = "Attribute",
			orbitIndex = 1,
			group = 91,
			icon = "absorbPhysical",
			customStats = {
				absorbPhysical = 1,
			},
			inputs = {
				410
			},
			out = {
				415
			}
		},
		--- 415 ---
		{
			orbit = 1,
			orbitDist = 300,
			name = "Attribute",
			orbitIndex = 300,
			group = 91,
			icon = "physicalDamage",
			customStats = {
				incrementPhysical = 1,
			},
			inputs = {
				413, 414
			},
			out = {
				416
			}
		},
		--- 416 ---
		{
			orbit = 2,
			orbitDist = 180,
			name = "Attribute",
			orbitIndex = 300,
			isUncommon = true,
			group = 91,
			icon = "strength",
			customStats = {
				strength = 3,
			},
			inputs = {
				415
			},
			out = {
				417, 418
			}
		},
		--- 417 ---
		{
			orbit = 3,
			orbitDist = 180,
			name = "Attribute",
			orbitIndex = 240,
			isUncommon = true,
			group = 91,
			icon = "absorbPhysical",
			customStats = {
				absorbPhysical = 2,
			},
			inputs = {
				416
			},
			out = {
				419
			}
		},
		--- 418 ---
		{
			orbit = 3,
			orbitDist = 180,
			name = "Attribute",
			orbitIndex = 1,
			isUncommon = true,
			group = 91,
			icon = "physicalDamage",
			customStats = {
				incrementPhysical = 4,
			},
			inputs = {
				416
			},
			out = {
				420
			}
		},
		--- 419 ---
		{
			orbit = 1,
			orbitDist = 180,
			name = "Attribute",
			orbitIndex = 180,
			isUncommon = true,
			group = 91,
			icon = "rarityLoot",
			customStats = {
				dexterity = 3,
				experience = 10,
				rarityLoot = 3
			},
			inputs = {
				417
			},
			out = {
				421
			}
		},
		--- 420 ---
		{
			orbit = 2,
			orbitDist = 180,
			name = "Attribute",
			orbitIndex = 60,
			isUncommon = true,
			group = 91,
			icon = "experience",
			customStats = {
				intelligence = 3,
				experience = 10,
				loot = 10
			},
			inputs = {
				418
			},
			out = {
				421
			}
		},
		--- 421 ---
		{
			orbit = 3,
			orbitDist = 180,
			name = "Attribute",
			orbitIndex = 120,
			isUncommon = true,
			group = 91,
			icon = "absorbPhysical",
			customStats = {
				absorbPhysical = 2,
				incrementPhysical = 4
			},
			inputs = {
				419, 420
			},
			out = {
				422
			}
		},
		--- 422 ---
		{
			orbit = 1,
			orbitDist = 90,
			name = "Attribute",
			orbitIndex = 120,
			isMythic = true,
			group = 91,
			icon = "physicalDamage",
			customStats = {
				incrementPhysical = 5,
			},
			inputs = {
				421
			},
			out = {
				423, 427
			}
		},
		--- 423 ---
		{
			orbit = 2,
			orbitDist = 90,
			name = "Attribute",
			orbitIndex = 180,
			isMythic = true,
			group = 91,
			icon = "absorbPhysical",
			customStats = {
				absorbPhysical = 3,
			},
			inputs = {
				422
			},
			out = {
				424
			}
		},
		--- 424 ---
		{
			orbit = 3,
			orbitDist = 90,
			name = "Attribute",
			orbitIndex = 240,
			isMythic = true,
			group = 91,
			icon = "physicalDamage",
			customStats = {
				incrementPhysical = 6,
			},
			inputs = {
				423
			},
			out = {
				425
			}
		},
		--- 425 ---
		{
			orbit = 1,
			orbitDist = 90,
			name = "Attribute",
			orbitIndex = 300,
			isMythic = true,
			group = 91,
			icon = "absorbPhysical",
			customStats = {
				absorbPhysical = 4,
			},
			inputs = {
				424, 426
			},
			out = {
				428
			}
		},
		--- 426 ---
		{
			orbit = 3,
			orbitDist = 90,
			name = "Attribute",
			orbitIndex = 1,
			isMythic = true,
			group = 91,
			icon = "physicalDamage",
			customStats = {
				incrementPhysical = 6,
			},
			inputs = {
				427
			},
			out = {
				425
			}
		},
		--- 427 ---
		{
			orbit = 4,
			orbitDist = 90,
			name = "Attribute",
			orbitIndex = 60,
			isMythic = true,
			group = 91,
			icon = "absorbPhysical",
			customStats = {
				absorbPhysical = 3,
			},
			inputs = {
				422
			},
			out = {
				426
			}
		},
		--- 428 ---
		{
			orbit = 0,
			orbitDist = 0,
			name = "Whisper Of Doom",
			orbitIndex = 0,
			isDivine = true,
			group = 91,
			icon = "whisperOfDoom",
			customStats = {
				incrementPhysical = 15,
				absorbPhysical = 6,
				swordSkill = 2,
				axeSkill = 2,
				clubSkill = 2
			},
			inputs = {
				425
			},
			out = {
				
			}
		},
		--- 429 ---
		{
			orbit = 1,
			orbitDist = 300,
			name = "Attribute",
			orbitIndex = 90,
			group = 92,
			icon = "absorbEnergy",
			customStats = {
				absorbEnergy = 1,
			},
			inputs = {
				366
			},
			out = {
				430, 433
			}
		},
		--- 430 ---
		{
			orbit = 3,
			orbitDist = 300,
			name = "Attribute",
			orbitIndex = 150,
			group = 92,
			icon = "lightningDamage",
			customStats = {
				incrementEnergy = 1,
			},
			inputs = {
				429
			},
			out = {
				431
			}
		},
		--- 431 ---
		{
			orbit = 1,
			orbitDist = 300,
			name = "Attribute",
			orbitIndex = 210,
			group = 92,
			icon = "absorbEnergy",
			customStats = {
				absorbEnergy = 1,
			},
			inputs = {
				430
			},
			out = {
				432
			}
		},
		--- 432 ---
		{
			orbit = 2,
			orbitDist = 300,
			name = "Attribute",
			orbitIndex = 270,
			group = 92,
			icon = "lightningDamage",
			customStast = {
				incrementEnergy = 1,
			},
			inputs = {
				431, 434
			},
			out = {
				436
			}
		},
		--- 433 ---
		{
			orbit = 3,
			orbitDist = 300,
			name = "Attribute",
			orbitIndex = 25,
			group = 92,
			icon = "lightningDamage",
			customStats = {
				incrementEnergy = 1,
			},
			inputs = {
				429
			},
			out = {
				434
			}
		},
		--- 434 ---
		{
			orbit = 1,
			orbitDist = 300,
			name = "Attribute",
			orbitIndex = 335,
			group = 92,
			icon = "absorbEnergy",
			customStats = {
				absorbEnergy = 1,
			},
			inputs = {
				433
			},
			out = {
				432
			}
		},
		--- 435 ---
		{
			orbit = 2,
			orbitDist = 180,
			name = "Attribute",
			orbitIndex = 330,
			isUncommon = true,
			group = 92,
			icon = "lightningDamage",
			customStats = {
				incrementEnergy = 4,
			},
			inputs = {
				436
			},
			out = {
				437
			}
		},
		--- 436 ---
		{
			orbit = 3,
			orbitDist = 180,
			name = "Attribute",
			orbitIndex = 270,
			isUncommon = true,
			group = 92,
			icon = "intelligence",
			customStats = {
				intelligence = 3,
			},
			inputs = {
				432
			},
			out = {
				435, 438
			}
		},
		--- 437 ---
		{
			orbit = 3,
			orbitDist = 180,
			name = "Attribute",
			orbitIndex = 30,
			isUncommon = true,
			group = 92,
			icon = "loot",
			customStats = {
				strength = 3,
				loot = 10,
				experience = 10
			},
			inputs = {
				435
			},
			out = {
				439
			}
		},
		--- 438 ---
		{
			orbit = 1,
			orbitDist = 180,
			name = "Attribute",
			orbitIndex = 210,
			isUncommon = true,
			group = 92,
			icon = "absorbEnergy",
			customStats = {
				absorbEnergy = 2,
			},
			inputs = {
				436	
			},
			out = {
				440
			}
		},
		--- 439 ---
		{
			orbit = 2,
			orbitDist = 180,
			name = "Attribute",
			orbitIndex = 90,
			isUncommon = true,
			group = 92,
			icon = "absorbEnergy",
			customStats = {
				incrementEnergy = 4,
				absorbEnergy = 2
			},
			inputs = {
				437, 440
			},
			out = {
				446
			}
		},
		--- 440 ---
		{
			orbit = 3,
			orbitDist = 180,
			name = "Attribute",
			orbitIndex = 150,
			isUncommon = true,
			group = 92,
			icon = "rarityLoot",
			customStats = {
				dexterity = 3,
				loot = 10,
				rarityLoot = 3
			},
			inputs = {
				438
			},
			out = {
				439
			}
		},
		--- 441 ---
		{
			orbit = 1,
			orbitDist = 90,
			name = "Attribute",
			orbitIndex = 150,
			isMythic = true,
			group = 92,
			icon = "absorbEnergy",
			customStats = {
				absorbEnergy = 3,
			},
			inputs = {
				446
			},
			out = {
				442
			}
		},
		--- 442 ---
		{
			orbit = 2,
			orbitDist = 90,
			name = "Attribute",
			orbitIndex = 210,
			isMythic = true,
			group = 92,
			icon = "lightningDamage",
			customStats = {
				incrementEnergy = 6,
			},
			inputs = {
				441
			},
			out = {
				443
			}
		},
		--- 443 ---
		{
			orbit = 3,
			orbitDist = 90,
			name = "Attribute",
			orbitIndex = 270,
			isMythic = true,
			group = 92,
			icon = "absorbEnergy",
			customStats = {
				absorbEnergy = 4,
			},
			inputs = {
				444, 442
			},
			out = {
				447
			}
		},
		--- 444 ---
		{
			orbit = 1,
			orbitDist = 90,
			name = "Attribute",
			orbitIndex = 330,
			isMythic = true,
			group = 92,
			icon = "lightningDamage",
			customStats = {
				incrementEnergy = 6,
			},
			inputs = {
				445
			},
			out = {
				443
			}
		},
		--- 445 ---
		{
			orbit = 3,
			orbitDist = 90,
			name = "Attribute",
			orbitIndex = 30,
			isMythic = true,
			group = 92,
			icon = "absorbEnergy",
			customStats = {
				absorbEnergy = 3,
			},
			inputs = {
				446
			},
			out = {
				444
			}
		},
		--- 446 ---
		{
			orbit = 4,
			orbitDist = 90,
			name = "Attribute",
			orbitIndex = 90,
			isMythic = true,
			group = 92,
			icon = "lightningDamage",
			customStats = {
				incrementEnergy = 5,
			},
			inputs = {
				439
			},
			out = {
				441, 445
			}
		},
		--- 447 ---
		{
			orbit = 0,
			orbitDist = 0,
			name = "Tempest Blast",
			orbitIndex = 0,
			isDivine = true,
			group = 92,
			icon = "tempestBlast",
			customStats = {
				incrementEnergy = 15,
				absorbEnergy = 6,
				magicSkill = 2,
				speed = 600
			},
			inputs = {
				443
			},
			out = {
				
			}
		},
		--- 448 ---
		{
			orbit = 1,
			orbitDist = 300,
			name = "Attribute",
			orbitIndex = 60,
			group = 93,
			icon = "absorbEarth",
			customStats = {
				absorbEarth = 1,
			},
			inputs = {
				349, 160
			},
			out = {
				452, 449
			}
		},
		--- 449 ---
		{
			orbit = 3,
			orbitDist = 300,
			name = "Attribute",
			orbitIndex = 120,
			group = 93,
			icon = "earthDamage",
			customStats = {
				incrementEarth = 1,
			},
			inputs = {
				448
			},
			out = {
				450	
			}
		},
		--- 450 ---
		{
			orbit = 1,
			orbitDist = 300,
			name = "Attribute",
			orbitIndex = 180,
			group = 93,
			icon = "absorbEarth",
			customStats = {
				absorbEarth = 1,
			},
			inputs = {
				449
			},
			out = {
				451
			}
		},
		--- 451 ---
		{
			orbit = 2,
			orbitDist = 300,
			name = "Attribute",
			orbitIndex = 240,
			group = 93,
			icon = "earthDamage",
			customStats = {
				incrementEarth = 1,
			},
			inputs = {
				450, 453
			},
			out = {
				455
			}
		},
		--- 452---
		{
			orbit = 3,
			orbitDist = 300,
			name = "Attribute",
			orbitIndex = 1,
			group = 93,
			icon = "earthDamage",
			customStats = {
				incrementEarth = 1,
			},
			inputs = {
				448
			},
			out = {
				453
			}
		},
		--- 453 ---
		{
			orbit = 1,
			orbitDist = 300,
			name = "Attribute",
			orbitIndex = 300,
			group = 93,
			icon = "absorbEarth",
			customStats = {
				absorbEarth = 1,
			},
			inputs = {
				452
			},
			out = {
				451
			}
		},
		--- 454 ---
		{
			orbit = 2,
			orbitDist = 180,
			name = "Attribute",
			orbitIndex = 300,
			isUncommon = true,
			group = 93,
			icon = "earthDamage",
			customStats = {
				incrementEarth = 2,
			},
			inputs = {
				455
			},
			out = {
				456
			}
		},
		--- 455 ---
		{
			orbit = 3,
			orbitDist = 180,
			name = "Attribute",
			orbitIndex = 240,
			isUncommon = true,
			group = 93,
			icon = "multiStat",
			customStats = {
				intelligence = 1,
				dexterity = 1,
				strength = 1
			},
			inputs = {
				451
			},
			out = {
				454, 457
			}
		},
		--- 456 ---
		{
			orbit = 3,
			orbitDist = 180,
			name = "Attribute",
			orbitIndex = 1,
			isUncommon = true,
			group = 93,
			icon = "experience",
			customStats = {
				dexterity = 1,
				strength = 1,
				loot = 10,
				experience = 10
			},
			inputs = {
				454
			},
			out = {
				458
			}
		},
		--- 457 ---
		{
			orbit = 1,
			orbitDist = 180,
			name = "Attribute",
			orbitIndex = 180,
			isUncommon = true,
			group = 93,
			icon = "absorbEarth",
			customStats = {
				absorbEarth = 2,
			},
			inputs = {
				455
			},
			out = {
				459
			}
		},
		--- 458 ---
		{
			orbit = 2,
			orbitDist = 180,
			name = "Attribute",
			orbitIndex = 60,
			isUncommon = true,
			group = 93,
			icon = "absorbEarth",
			customStats = {
				incrementEarth = 4,
				absorbEarth = 2
			},
			inputs = {
				456, 459
			},
			out = {
				465
			}
		},
		--- 459 ---
		{
			orbit = 3,
			orbitDist = 180,
			name = "Attribute",
			orbitIndex = 120,
			isUncommon = true,
			group = 93,
			icon = "experience",
			customStats = {
				strength = 1,
				intelligence = 1,
				rarityLoot = 3,
				experience = 10
			},
			inputs = {
				457
			},
			out = {
				458
			}
		},
		--- 460 ---
		{
			orbit = 1,
			orbitDist = 90,
			name = "Attribute",
			orbitIndex = 120,
			isMythic = true,
			group = 93,
			icon = "absorbEarth",
			customStats = {
				absorbEarth = 3,
			},
			inputs = {
				465
			},
			out = {
				461
			}
		},
		--- 461 ---
		{
			orbit = 2,
			orbitDist = 90,
			name = "Attribute",
			orbitIndex = 180,
			isMythic = true,
			group = 93,
			icon = "earthDamage",
			customStats = {
				incrementEarth = 6,
			},
			inputs = {
				460
			},
			out = {
				462
			}
		},
		--- 462 ---
		{
			orbit = 3,
			orbitDist = 90,
			name = "Attribute",
			orbitIndex = 240,
			isMythic = true,
			group = 93,
			icon = "absorbEarth",
			customStats = {
				absorbEarth = 4,
			},
			inputs = {
				461, 463
			},
			out = {
				466
			}
		},
		--- 463 ---
		{
			orbit = 1,
			orbitDist = 90,
			name = "Attribute",
			orbitIndex = 300,
			isMythic = true,
			group = 93,
			icon = "earthDamage",
			customStats = {
				incrementEarth = 6,
			},
			inputs = {
				464
			},
			out = {
				462
			}
		},
		--- 464 ---
		{
			orbit = 3,
			orbitDist = 90,
			name = "Attribute",
			orbitIndex = 1,
			isMythic = true,
			group = 93,
			icon = "absorbEarth",
			customStats = {
				absorbEarth = 3,
			},
			inputs = {
				465
			},
			out = {
				463
			}
		},
		--- 465 ---
		{
			orbit = 4,
			orbitDist = 90,
			name = "Attribute",
			orbitIndex = 60,
			isMythic = true,
			group = 93,
			icon = "earthDamage",
			customStats = {
				incrementEarth = 5,
			},
			inputs = {
				458
			},
			out = {
				464, 460
			}
		},
		--- 466 ---
		{
			orbit = 0,
			orbitDist = 0,
			name = "Divine Fervour",
			orbitIndex = 0,
			isDivine = true,
			group = 93,
			icon = "divineFervour",
			customStats = {
				incrementEarth = 15,
				absorbEarth = 6,
				strength = 3,
				dexterity = 3,
				intelligence = 3
			},
			inputs = {
				462
			},
			out = {
				
			}
		},
		--- 467 ---
		{
			orbit = 1,
			orbitDist = 300,
			name = "Attribute",
			orbitIndex = 60,
			group = 94,
			icon = "absorbDeath",
			customStats = {
				absorbDeath = 1,
			},
			inputs = {
				190, 238
			},
			out = {
				468, 471
			}
		},
		--- 468 ---
		{
			orbit = 3,
			orbitDist = 300,
			name = "Attribute",
			orbitIndex = 120,
			group = 94,
			icon = "deathDamage",
			customStats = {
				incrementDeath = 1,
			},
			inputs = {
				467
			},
			out = {
				469
			}
		},
		--- 469 ---
		{
			orbit = 1,
			orbitDist = 300,
			name = "Attribute",
			orbitIndex = 180,
			group = 94,
			icon = "absorbDeath",
			customStats = {
				absorbDeath = 1,
			},
			inputs = {
				468
			},
			out = {
				470
			}
		},
		--- 470 ---
		{
			orbit = 2,
			orbitDist = 300,
			name = "Attribute",
			orbitIndex = 240,
			group = 94,
			icon = "deathDamage",
			customStats = {
				incrementDeath = 1,
			},
			inputs = {
				469, 472
			},
			out = {
				474
			}
		},
		--- 471---
		{
			orbit = 3,
			orbitDist = 300,
			name = "Attribute",
			orbitIndex = 1,
			group = 94,
			icon = "deathDamage",
			customStats = {
				incrementDeath = 1,
			},
			inputs = {
				467
			},
			out = {
				472	
			}
		},
		--- 472 ---
		{
			orbit = 1,
			orbitDist = 300,
			name = "Attribute",
			orbitIndex = 300,
			group = 94,
			icon = "absorbDeath",
			customStats = {
				absorbDeath = 1,
			},
			inputs = {
				471
			},
			out = {
				470
			}
		},
		--- 473 ---
		{
			orbit = 2,
			orbitDist = 180,
			name = "Attribute",
			orbitIndex = 300,
			isUncommon = true,
			group = 94,
			icon = "deathDamage",
			customStats = {
				incrementDeath = 2,
			},
			inputs = {
				474
			},
			out = {
				475
			}
		},
		--- 474 ---
		{
			orbit = 3,
			orbitDist = 180,
			name = "Attribute",
			orbitIndex = 240,
			isUncommon = true,
			group = 94,
			icon = "intelligence",
			customStats = {
				intelligence = 5,
			},
			inputs = {
				470
			},
			out = {
				473, 476
			}
		},
		--- 475 ---
		{
			orbit = 3,
			orbitDist = 180,
			name = "Attribute",
			orbitIndex = 1,
			isUncommon = true,
			group = 94,
			icon = "loot",
			customStats = {
				strength = 3,
				loot = 10,
				experience = 10
			},
			inputs = {
				473
			},
			out = {
				477
			}
		},
		--- 476 ---
		{
			orbit = 1,
			orbitDist = 180,
			name = "Attribute",
			orbitIndex = 180,
			isUncommon = true,
			group = 94,
			icon = "absorbDeath",
			customStats = {
				absorbDeath = 2,
			},
			inputs = {
				474
			},
			out = {
				478
			}
		},
		--- 477 ---
		{
			orbit = 2,
			orbitDist = 180,
			name = "Attribute",
			orbitIndex = 60,
			isUncommon = true,
			group = 94,
			icon = "absorbDeath",
			customStats = {
				absorbDeath = 2,
				incrementDeath = 4
			},
			inputs = {
				475, 478
			},
			out = {
				484
			}
		},
		--- 478 ---
		{
			orbit = 3,
			orbitDist = 180,
			name = "Attribute",
			orbitIndex = 120,
			isUncommon = true,
			group = 94,
			icon = "experience",
			customStats = {
				dexterity = 3,
				rarityLoot = 3,
				experience = 10
			},
			inputs = {
				476
			},
			out = {
				477
			}
		},
		--- 479 ---
		{
			orbit = 1,
			orbitDist = 90,
			name = "Attribute",
			orbitIndex = 120,
			isMythic = true,
			group = 94,
			icon = "absorbDeath",
			customStats = {
				absorbDeath = 3,
			},
			inputs = {
				484
			},
			out = {
				480
			}
		},
		--- 480 ---
		{
			orbit = 2,
			orbitDist = 90,
			name = "Attribute",
			orbitIndex = 180,
			isMythic = true,
			group = 94,
			icon = "deathDamage",
			customStats = {
				incrementDeath = 6,
			},
			inputs = {
				479
			},
			out = {
				481
			}
		},
		--- 481 ---
		{
			orbit = 3,
			orbitDist = 90,
			name = "Attribute",
			orbitIndex = 240,
			isMythic = true,
			group = 94,
			icon = "absorbDeath",
			customStats = {
				absorbDeath = 4,
			},
			inputs = {
				480, 482
			},
			out = {
				485
			}
		},
		--- 482 ---
		{
			orbit = 1,
			orbitDist = 90,
			name = "Attribute",
			orbitIndex = 300,
			isMythic = true,
			group = 94,
			icon = "deathDamage",
			customStats = {
				incrementDeath = 6,
			},
			inputs = {
				483
			},
			out = {
				481
			}
		},
		--- 483 ---
		{
			orbit = 3,
			orbitDist = 90,
			name = "Attribute",
			orbitIndex = 1,
			isMythic = true,
			group = 94,
			icon = "absorbDeath",
			customStats = {
				absorbDeath = 3,
			},
			inputs = {
				484
			},
			out = {
				482
			}
		},
		--- 484 ---
		{
			orbit = 4,
			orbitDist = 90,
			name = "Attribute",
			orbitIndex = 60,
			isMythic = true,
			group = 94,
			icon = "deathDamage",
			customStats = {
				incrementDeath = 5,
			},
			inputs = {
				477
			},
			out = {
				479, 483
			}
		},
		--- 485 ---
		{
			orbit = 0,
			orbitDist = 0,
			name = "Resolute Technique",
			orbitIndex = 0,
			isDivine = true,
			group = 94,
			icon = "resoluteTechnique",
			customStats = {
				incrementDeath = 15,
				absorbDeath = 6,
				experience = 20,
				shieldingSkill = 3
			},
			inputs = {
				481
			},
			out = {
				
			}
		},
		--- 486 ---
		{
			orbit = 1,
			orbitDist = 300,
			name = "Attribute",
			orbitIndex = 60,
			group = 95,
			icon = "drownDamage",
			customStats = {
				incrementDrown = 1,
			},
			inputs = {
				490
			},
			out = {
				487
			}
		},
		--- 487 ---
		{
			orbit = 3,
			orbitDist = 300,
			name = "Attribute",
			orbitIndex = 120,
			group = 95,
			icon = "absorbDrown",
			customStats = {
				absorbDrown = 1,
			},
			inputs = {
				486
			},
			out = {
				488
			}
		},
		--- 488 ---
		{
			orbit = 1,
			orbitDist = 300,
			name = "Attribute",
			orbitIndex = 180,
			group = 95,
			icon = "drownDamage",
			customStats = {
				incrementDrown = 1,
			},
			inputs = {
				487, 489
			},
			out = {
				495
			}
		},
		--- 489 ---
		{
			orbit = 2,
			orbitDist = 300,
			name = "Attribute",
			orbitIndex = 240,
			group = 95,
			icon = "absorbDrown",
			customStats = {
				absorbDrown = 1,
			},
			inputs = {
				491	
			},
			out = {
				488, 622
			}
		},
		--- 490---
		{
			orbit = 3,
			orbitDist = 300,
			name = "Attribute",
			orbitIndex = 1,
			group = 95,
			icon = "absorbDrown",
			customStats = {
				absorbDrown = 1,
			},
			inputs = {
				261	
			},
			out = {
				486, 491
			}
		},
		--- 491 ---
		{
			orbit = 1,
			orbitDist = 300,
			name = "Attribute",
			orbitIndex = 300,
			group = 95,
			icon = "drownDamage",
			customStats = {
				incrementDrown = 1,
			},
			inputs = {
				490
			},
			out = {
				489
			}
		},
		--- 492 ---
		{
			orbit = 2,
			orbitDist = 180,
			name = "Attribute",
			orbitIndex = 300,
			isUncommon = true,
			group = 95,
			icon = "loot",
			customStats = {
				strength = 2,
				vitality = 2,
				experience = 10,
				loot = 10
			},
			inputs = {
				493
			},
			out = {
				494
			}
		},
		--- 493 ---
		{
			orbit = 3,
			orbitDist = 180,
			name = "Attribute",
			orbitIndex = 240,
			isUncommon = true,
			group = 95,
			icon = "drownDamage",
			customStats = {
				incrementDrown = 2,
			},
			inputs = {
				495
			},
			out = {
				492
			}
		},
		--- 494 ---
		{
			orbit = 3,
			orbitDist = 180,
			name = "Attribute",
			orbitIndex = 1,
			isUncommon = true,
			group = 95,
			icon = "drownDamage",
			customStats = {
				incrementDrown = 4,
				absorbDrown = 2
			},
			inputs = {
				492, 496
			},
			out = {
				502
			}
		},
		--- 495 ---
		{
			orbit = 2,
			orbitDist = 180,
			name = "Attribute",
			orbitIndex = 180,
			isUncommon = true,
			group = 95,
			icon = "multiStat",
			customStats = {
				strength = 1,
				dexterity = 1,
				intelligence = 1
			},
			inputs = {
				488
			},
			out = {
				493, 497
			}
		},
		--- 496 ---
		{
			orbit = 2,
			orbitDist = 180,
			name = "Attribute",
			orbitIndex = 60,
			isUncommon = true,
			group = 95,
			icon = "rarityLoot",
			customStats = {
				dexterity = 2,
				spirit = 2,
				experience = 10,
				rarityLoot = 3
			},
			inputs = {
				497
			},
			out = {
				494
			}
		},
		--- 497 ---
		{
			orbit = 3,
			orbitDist = 180,
			name = "Attribute",
			orbitIndex = 120,
			isUncommon = true,
			group = 95,
			icon = "absorbDrown",
			customStats = {
				absorbDrown = 2,
			},
			inputs = {
				495
			},
			out = {
				496
			}
		},
		--- 498 ---
		{
			orbit = 1,
			orbitDist = 90,
			name = "Attribute",
			orbitIndex = 120,
			isMythic = true,
			group = 95,
			icon = "drownDamage",
			customStats = {
				incrementDrown = 6,
			},
			inputs = {
				503
			},
			out = {
				499
			}
		},
		--- 499 ---
		{
			orbit = 2,
			orbitDist = 90,
			name = "Attribute",
			orbitIndex = 180,
			isMythic = true,
			group = 95,
			icon = "absorbDrown",
			customStats = {
				absorbDrown = 4,
			},
			inputs = {
				500, 498
			},
			out = {
				504
			}
		},
		--- 500 ---
		{
			orbit = 3,
			orbitDist = 90,
			name = "Attribute",
			orbitIndex = 240,
			isMythic = true,
			group = 95,
			icon = "drownDamage",
			customStats = {
				incrementDrown = 6,
			},
			inputs = {
				501
			},
			out = {
				499
			}
		},
		--- 501 ---
		{
			orbit = 1,
			orbitDist = 90,
			name = "Attribute",
			orbitIndex = 300,
			isMythic = true,
			group = 95,
			icon = "absorbDrown",
			customStats = {
				absorbDrown = 3,
			},
			inputs = {
				502
			},
			out = {
				500
			}
		},
		--- 502 ---
		{
			orbit = 2,
			orbitDist = 90,
			name = "Attribute",
			orbitIndex = 1,
			isMythic = true,
			group = 95,
			icon = "drownDamage",
			customStats = {
				incrementDrown = 5,
			},
			inputs = {
				494
			},
			out = {
				501, 503
			}
		},
		--- 503 ---
		{
			orbit = 3,
			orbitDist = 90,
			name = "Attribute",
			orbitIndex = 60,
			isMythic = true,
			group = 95,
			icon = "absorbDrown",
			customStats = {
				absorbDrown = 3,
			},
			inputs = {
				502
			},
			out = {
				498
			}
		},
		--- 504 ---
		{
			orbit = 0,
			orbitDist = 0,
			name = "Shamanistic Fury",
			orbitIndex = 0,
			isDivine = true,
			group = 95,
			icon = "shamanisticFury",
			customStats = {
				incrementDrown = 20,
				absorbDrown = 6,
				vitality = 8,
				spirit = 8,
				experience = 10
			},
			inputs = {
				499
			},
			out = {
				
			}
		},
		--- 505 ---
		{
			orbit = 1,
			orbitDist = 300,
			name = "Attribute",
			orbitIndex = 60,
			group = 96,
			icon = "absorbIce",
			customStats = {
				absorbIce = 1,
			},
			inputs = {
				509
			},
			out = {
				506
			}
		},
		--- 506 ---
		{
			orbit = 3,
			orbitDist = 300,
			name = "Attribute",
			orbitIndex = 120,
			group = 96,
			icon = "coldDamage",
			customStats = {
				incrementIce = 1,
			},
			inputs = {
				505, 507
			},
			out = {
				516
			}
		},
		--- 507 ---
		{
			orbit = 1,
			orbitDist = 300,
			name = "Attribute",
			orbitIndex = 180,
			group = 96,
			icon = "absorbIce",
			customStats = {
				absorbIce = 1,
			},
			inputs = {
				508
			},
			out = {
				506
			}
		},
		--- 508 ---
		{
			orbit = 2,
			orbitDist = 300,
			name = "Attribute",
			orbitIndex = 240,
			group = 96,
			icon = "coldDamage",
			customStats = {
				incrementIce = 1,
			},
			inputs = {
				510
			},
			out = {
				507
			}
		},
		--- 509---
		{
			orbit = 3,
			orbitDist = 300,
			name = "Attribute",
			orbitIndex = 1,
			group = 96,
			icon = "coldDamage",
			customStats = {
				incrementIce = 1,
			},
			inputs = {
				510
			},
			out = {
				505	
			}
		},
		--- 510 ---
		{
			orbit = 1,
			orbitDist = 300,
			name = "Attribute",
			orbitIndex = 300,
			group = 96,
			icon = "absorbIce",
			customStats = {
				absorbIce = 1,
			},
			inputs = {
				240, 189
			},
			out = {
				508, 509
			}
		},
		--- 511 ---
		{
			orbit = 2,
			orbitDist = 180,
			name = "Attribute",
			orbitIndex = 300,
			isUncommon = true,
			group = 96,
			icon = "absorbIce",
			customStats = {
				incrementIce = 4,
				absorbIce = 2
			},
			inputs = {
				512, 513
			},
			out = {
				520
			}
		},
		--- 512 ---
		{
			orbit = 3,
			orbitDist = 180,
			name = "Attribute",
			orbitIndex = 240,
			isUncommon = true,
			group = 96,
			icon = "loot",
			customStats = {
				dexterity = 3,
				experience = 10,
				loot = 10
			},
			inputs = {
				514
			},
			out = {
				511
			}
		},
		--- 513 ---
		{
			orbit = 3,
			orbitDist = 180,
			name = "Attribute",
			orbitIndex = 1,
			isUncommon = true,
			group = 96,
			icon = "experience",
			customStats = {
				strength = 3,
				experience = 10,
				rarityLoot = 3
			},
			inputs = {
				515
			},
			out = {
				511
			}
		},
		--- 514 ---
		{
			orbit = 1,
			orbitDist = 180,
			name = "Attribute",
			orbitIndex = 180,
			isUncommon = true,
			group = 96,
			icon = "coldDamage",
			customStats = {
				incrementIce = 2,
			},
			inputs = {
				516
			},
			out = {
				512
			}
		},
		--- 515 ---
		{
			orbit = 1,
			orbitDist = 180,
			name = "Attribute",
			orbitIndex = 60,
			isUncommon = true,
			group = 96,
			icon = "absorbIce",
			customStats = {
				absorbIce = 2,
			},
			inputs = {
				516
			},
			out = {
				513
			}
		},
		--- 516 ---
		{
			orbit = 2,
			orbitDist = 180,
			name = "Attribute",
			orbitIndex = 120,
			isUncommon = true,
			group = 96,
			icon = "intelligence",
			customStats = {
				intelligence = 5,
			},
			inputs = {
				506
			},
			out = {
				515, 514
			}
		},
		--- 517 ---
		{
			orbit = 1,
			orbitDist = 90,
			name = "Attribute",
			orbitIndex = 120,
			isMythic = true,
			group = 96,
			icon = "absorbIce",
			customStats = {
				absorbIce = 4,
			},
			inputs = {
				522, 518
			},
			out = {
				523
			}
		},
		--- 518 ---
		{
			orbit = 2,
			orbitDist = 90,
			name = "Attribute",
			orbitIndex = 180,
			isMythic = true,
			group = 96,
			icon = "coldDamage",
			customStats = {
				incrementIce = 6,
			},
			inputs = {
				519
			},
			out = {
				517
			}
		},
		--- 519 ---
		{
			orbit = 3,
			orbitDist = 90,
			name = "Attribute",
			orbitIndex = 240,
			isMythic = true,
			group = 96,
			icon = "absorbIce",
			customStats = {
				absorbIce = 3,
			},
			inputs = {
				520
			},
			out = {
				518
			}
		},
		--- 520 ---
		{
			orbit = 1,
			orbitDist = 90,
			name = "Attribute",
			orbitIndex = 300,
			isMythic = true,
			group = 96,
			icon = "coldDamage",
			customStats = {
				incrementIce = 5,
			},
			inputs = {
				511
			},
			out = {
				519, 521
			}
		},
		--- 521 ---
		{
			orbit = 3,
			orbitDist = 90,
			name = "Attribute",
			orbitIndex = 1,
			isMythic = true,
			group = 96,
			icon = "absorbIce",
			customStats = {
				absorbIce = 3,
			},
			inputs = {
				520
			},
			out = {
				522
			}
		},
		--- 522 ---
		{
			orbit = 2,
			orbitDist = 90,
			name = "Attribute",
			orbitIndex = 60,
			isMythic = true,
			group = 96,
			icon = "coldDamage",
			customStats = {
				incrementIce = 6,
			},
			inputs = {
				521
			},
			out = {
				517
			}
		},
		--- 523 ---
		{
			orbit = 0,
			orbitDist = 0,
			name = "Revelry",
			orbitIndex = 0,
			isDivine = true,
			group = 96,
			icon = "revelry",
			customStats = {
				incrementIce = 15,
				absorbIce = 6,
				magicSkill = 2,
				speed = 600
			},
			inputs = {
				517	
			},
			out = {
				
			}
		},
		--- 524 ---
		{
			orbit = 1,
			orbitDist = 300,
			name = "Attribute",
			orbitIndex = 60,
			group = 97,
			icon = "absorbLifeMana",
			customStats = {
				absorbLife = 1,
				absorbMana = 1
			},
			inputs = {
				528
			},
			out = {
				525
			}
		},
		--- 525 ---
		{
			orbit = 3,
			orbitDist = 300,
			name = "Attribute",
			orbitIndex = 120,
			group = 97,
			icon = "lifeManaDrain",
			customStats = {
				incrementLifeDrain = 1,
				incrementManaDrain = 1
			},
			inputs = {
				524, 526
			},
			out = {
				535
			}
		},
		--- 526 ---
		{
			orbit = 1,
			orbitDist = 300,
			name = "Attribute",
			orbitIndex = 180,
			group = 97,
			icon = "absorbLifeMana",
			customStats = {
				absorbLife = 1,
				absorbMana = 1
			},
			inputs = {
				527
			},
			out = {
				525
			}
		},
		--- 527 ---
		{
			orbit = 2,
			orbitDist = 300,
			name = "Attribute",
			orbitIndex = 240,
			group = 97,
			icon = "lifeManaDrain",
			customStats = {
				incrementLifeDrain = 1,
				incrementManaDrain = 1
			},
			inputs = {
				529
			},
			out = {
				526
			}
		},
		--- 528---
		{
			orbit = 3,
			orbitDist = 300,
			name = "Attribute",
			orbitIndex = 1,
			group = 97,
			icon = "lifeManaDrain",
			customStats = {
				incrementLifeDrain = 1,
				incrementManaDrain = 1
			},
			inputs = {
				529
			},
			out = {
				524
			}
		},
		--- 529 ---
		{
			orbit = 1,
			orbitDist = 300,
			name = "Attribute",
			orbitIndex = 300,
			group = 97,
			icon = "absorbLifeMana",
			customStats = {
				absorbLife = 1,
				absorbMana = 1
			},
			inputs = {
				175, 378
			},
			out = {
				527, 528
			}
		},
		--- 530 ---
		{
			orbit = 2,
			orbitDist = 180,
			name = "Attribute",
			orbitIndex = 300,
			isUncommon = true,
			group = 97,
			icon = "absorbLifeMana",
			customStats = {
				incrementLifeDrain = 4,
				incrementManaDrain = 4,
				absorbLife = 2,
				absorbMana = 2
			},
			inputs = {
				531, 532
			},
			out = {
				539
			}
		},
		--- 531 ---
		{
			orbit = 3,
			orbitDist = 180,
			name = "Attribute",
			orbitIndex = 240,
			isUncommon = true,
			group = 97,
			icon = "rarityLoot",
			customStats = {
				intelligence = 3,
				experience = 10,
				rarityLoot = 3
			},
			inputs = {
				533
			},
			out = {
				530
			}
		},
		--- 532 ---
		{
			orbit = 3,
			orbitDist = 180,
			name = "Attribute",
			orbitIndex = 1,
			isUncommon = true,
			group = 97,
			icon = "experience",
			customStats = {
				strength = 3,
				experience = 10,
				loot = 10
			},
			inputs = {
				534
			},
			out = {
				530
			}
		},
		--- 533 ---
		{
			orbit = 1,
			orbitDist = 180,
			name = "Attribute",
			orbitIndex = 180,
			isUncommon = true,
			group = 97,
			icon = "lifeManaDrain",
			customStats = {
				incrementLifeDrain = 2,
				incrementManaDrain = 2
			},
			inputs = {
				535
			},
			out = {
				531
			}
		},
		--- 534 ---
		{
			orbit = 1,
			orbitDist = 180,
			name = "Attribute",
			orbitIndex = 60,
			isUncommon = true,
			group = 97,
			icon = "absorbLifeMana",
			customStats = {
				absorbMana = 2,
				absorbLife = 2
			},
			inputs = {
				535
			},
			out = {
				532
			}
		},
		--- 535 ---
		{
			orbit = 2,
			orbitDist = 180,
			name = "Attribute",
			orbitIndex = 120,
			isUncommon = true,
			group = 97,
			icon = "dexterity",
			customStats = {
				dexterity = 5,
			},
			inputs = {
				525
			},
			out = {
				533, 534
			}
		},
		--- 536 ---
		{
			orbit = 1,
			orbitDist = 90,
			name = "Attribute",
			orbitIndex = 120,
			isMythic = true,
			group = 97,
			icon = "absorbLifeMana",
			customStats = {
				absorbLife = 4,
				absorbMana = 4
			},
			inputs = {
				537, 541
			},
			out = {
				542
			}
		},
		--- 537 ---
		{
			orbit = 2,
			orbitDist = 90,
			name = "Attribute",
			orbitIndex = 180,
			isMythic = true,
			group = 97,
			icon = "lifeManaDrain",
			customStats = {
				incrementLifeDrain = 6,
				incrementManaDrain = 6
			},
			inputs = {
				538
			},
			out = {
				536
			}
		},
		--- 538 ---
		{
			orbit = 3,
			orbitDist = 90,
			name = "Attribute",
			orbitIndex = 240,
			isMythic = true,
			group = 97,
			icon = "absorbLifeMana",
			customStats = {
				absorbLife = 3,
				absorbMana = 3
			},
			inputs = {
				539
			},
			out = {
				537
			}
		},
		--- 539 ---
		{
			orbit = 1,
			orbitDist = 90,
			name = "Attribute",
			orbitIndex = 300,
			isMythic = true,
			group = 97,
			icon = "lifeManaDrain",
			customStats = {
				incrementLifeDrain = 5,
				incrementManaDrain = 5
			},
			inputs = {
				530
			},
			out = {
				540, 538
			}
		},
		--- 540 ---
		{
			orbit = 3,
			orbitDist = 90,
			name = "Attribute",
			orbitIndex = 1,
			isMythic = true,
			group = 97,
			icon = "absorbLifeMana",
			customStats = {
				absorbLife = 3,
				absorbMana = 3
			},
			inputs = {
				539
			},
			out = {
				541
			}
		},
		--- 541 ---
		{
			orbit = 2,
			orbitDist = 90,
			name = "Attribute",
			orbitIndex = 60,
			isMythic = true,
			group = 97,
			icon = "lifeManaDrain",
			customStats = {
				incrementLifeDrain = 6,
				incrementManaDrain = 6
			},
			inputs = {
				540
			},
			out = {
				536
			}
		},
		--- 542 ---
		{
			orbit = 0,
			orbitDist = 0,
			name = "Brutal Skewering",
			orbitIndex = 0,
			isDivine = true,
			group = 97,
			icon = "brutalSkewering",
			customStats = {
				incrementLifeDrain = 20,
				incrementManaDrain = 20,
				absorbLife = 6,
				absorbMana = 6,
				vitality = 8,
				spirit = 8
			},
			inputs = {
				536
			},
			out = {
				
			}
		},
		--- 543 ---
		{
			orbit = 2,
			orbitDist = 300,
			name = "Attribute",
			orbitIndex = 90,
			group = 98,
			icon = "holyDamage",
			customStats = {
				incrementHoly = 1,
			},
			inputs = {
				544, 547
			},
			out = {
				553
			}
		},
		--- 544 ---
		{
			orbit = 3,
			orbitDist = 300,
			name = "Attribute",
			orbitIndex = 150,
			group = 98,
			icon = "absorbHoly",
			customStats = {
				absorbHoly = 1,
			},
			inputs = {
				545	
			},
			out = {
				543
			}
		},
		--- 545 ---
		{
			orbit = 1,
			orbitDist = 300,
			name = "Attribute",
			orbitIndex = 210,
			group = 98,
			icon = "holyDamage",
			customStats = {
				incrementHoly = 1,
			},
			inputs = {
				546
			},
			out = {
				544
			}
		},
		--- 546 ---
		{
			orbit = 2,
			orbitDist = 300,
			name = "Attribute",
			orbitIndex = 270,
			group = 98,
			icon = "absorbHoly",
			customStats = {
				absorbHoly = 1,
			},
			inputs = {
				386
			},
			out = {
				548, 545
			}
		},
		--- 547---
		{
			orbit = 3,
			orbitDist = 300,
			name = "Attribute",
			orbitIndex = 30,
			group = 98,
			icon = "absorbHoly",
			customStats = {
				absorbHoly = 1,
			},
			inputs = {
				548
			},
			out = {
				543	
			}
		},
		--- 548 ---
		{
			orbit = 1,
			orbitDist = 300,
			name = "Attribute",
			orbitIndex = 330,
			group = 98,
			icon = "holyDamage",
			customStats = {
				incrementHoly = 1,
			},
			inputs = {
				546
			},
			out = {
				547
			}
		},
		--- 549 ---
		{
			orbit = 4,
			orbitDist = 180,
			name = "Attribute",
			orbitIndex = 330,
			isUncommon = true,
			group = 98,
			icon = "loot",
			customStats = {
				strength = 3,
				experience = 10,
				loot = 10
			},
			inputs = {
				551
			},
			out = {
				550
			}
		},
		--- 550 ---
		{
			orbit = 2,
			orbitDist = 180,
			name = "Attribute",
			orbitIndex = 270,
			isUncommon = true,
			group = 98,
			icon = "absorbHoly",
			customStats = {
				incrementHoly = 4,
				absorbHoly = 2
			},
			inputs = {
				549, 552
			},
			out = {
				557
			}
		},
		--- 551 ---
		{
			orbit = 3,
			orbitDist = 180,
			name = "Attribute",
			orbitIndex = 30,
			isUncommon = true,
			group = 98,
			icon = "absorbHoly",
			customStats = {
				absorbHoly = 2,
			},
			inputs = {
				553
			},
			out = {
				549
			}
		},
		--- 552 ---
		{
			orbit = 1,
			orbitDist = 180,
			name = "Attribute",
			orbitIndex = 210,
			isUncommon = true,
			group = 98,
			icon = "rarityLoot",
			customStats = {
				intelligence = 3,
				experience = 10,
				rarityLoot = 3
			},
			inputs = {
				554
			},
			out = {
				550
			}
		},
		--- 553 ---
		{
			orbit = 1,
			orbitDist = 180,
			name = "Attribute",
			orbitIndex = 90,
			isUncommon = true,
			group = 98,
			icon = "dexterity",
			customStats = {
				dexterity = 5,
			},
			inputs = {
				543
			},
			out = {
				551, 554
			}
		},
		--- 554 ---
		{
			orbit = 2,
			orbitDist = 180,
			name = "Attribute",
			orbitIndex = 150,
			isUncommon = true,
			group = 98,
			icon = "holyDamage",
			customStats = {
				incrementHoly = 2,
			},
			inputs = {
				553
			},
			out = {
				552
			}
		},
		--- 555 ---
		{
			orbit = 1,
			orbitDist = 90,
			name = "Attribute",
			orbitIndex = 150,
			isMythic = true,
			group = 98,
			icon = "holyDamage",
			customStats = {
				incrementHoly = 6,
			},
			inputs = {
				556
			},
			out = {
				560
			}
		},
		--- 556 ---
		{
			orbit = 2,
			orbitDist = 90,
			name = "Attribute",
			orbitIndex = 210,
			isMythic = true,
			group = 98,
			icon = "absorbHoly",
			customStats = {
				absorbHoly = 3,
			},
			inputs = {
				557
			},
			out = {
				555
			}
		},
		--- 557 ---
		{
			orbit = 3,
			orbitDist = 90,
			name = "Attribute",
			orbitIndex = 270,
			isMythic = true,
			group = 98,
			icon = "holyDamage",
			customStats = {
				incrementHoly = 5,
			},
			inputs = {
				550
			},
			out = {
				556, 558
			}
		},
		--- 558 ---
		{
			orbit = 1,
			orbitDist = 90,
			name = "Attribute",
			orbitIndex = 330,
			isMythic = true,
			group = 98,
			icon = "absorbHoly",
			customStats = {
				absorbHoly = 3,
			},
			inputs = {
				557
			},
			out = {
				559
			}
		},
		--- 559 ---
		{
			orbit = 3,
			orbitDist = 90,
			name = "Attribute",
			orbitIndex = 30,
			isMythic = true,
			group = 98,
			icon = "holyDamage",
			customStats = {
				incrementHoly = 6,
			},
			inputs = {
				558
			},
			out = {
				560
			}
		},
		--- 560 ---
		{
			orbit = 2,
			orbitDist = 90,
			name = "Attribute",
			orbitIndex = 90,
			isMythic = true,
			group = 98,
			icon = "absorbHoly",
			customStats = {
				absorbHoly = 4,
			},
			inputs = {
				559, 555
			},
			out = {
				561
			}
		},
		--- 561 ---
		{
			orbit = 0,
			orbitDist = 0,
			name = "Concusive Dexterity",
			orbitIndex = 0,
			isDivine = true,
			group = 98,
			icon = "concusiveDexterity",
			customStats = {
				dexterity = 3,
				incrementHoly = 15,
				absorbHoly = 6,
				speed = 500,
				distanceSkill = 2
			},
			inputs = {
				560
			},
			out = {
				
			}
		},
		--- 562 ---
		{
			orbit = 1,
			orbitDist = 300,
			name = "Attribute",
			orbitIndex = 60,
			group = 99,
			icon = "healthDamage",
			customStats = {
				incrementHealth = 2,
			},
			inputs = {
				566, 563
			},
			out = {
				572
			}
		},
		--- 563 ---
		{
			orbit = 3,
			orbitDist = 300,
			name = "Attribute",
			orbitIndex = 120,
			group = 99,
			icon = "lifeLeechAmount",
			customStats = {
				lifeLeechChance = 1,
				lifeLeechAmount = 1
			},
			inputs = {
				564
			},
			out = {
				562
			}
		},
		--- 564 ---
		{
			orbit = 1,
			orbitDist = 300,
			name = "Attribute",
			orbitIndex = 180,
			group = 99,
			icon = "manaLeechAmount",
			customStats = {
				manaLeechChance = 1,
				manaLeechAmount = 1
			},
			inputs = {
				565
			},
			out = {
				563
			}
		},
		--- 565 ---
		{
			orbit = 2,
			orbitDist = 300,
			name = "Attribute",
			orbitIndex = 240,
			group = 99,
			icon = "healthDamage",
			customStats = {
				incrementHealth = 1,
			},
			inputs = {
				171, 375
			},
			out = {
				564, 567
			}
		},
		--- 566---
		{
			orbit = 3,
			orbitDist = 300,
			name = "Attribute",
			orbitIndex = 1,
			group = 99,
			icon = "manaLeechChance",
			customStats = {
				manaLeechChance = 1,
				manaLeechAmount = 1
			},
			inputs = {
				567
			},
			out = {
				562
			}
		},
		--- 567 ---
		{
			orbit = 1,
			orbitDist = 300,
			name = "Attribute",
			orbitIndex = 300,
			group = 99,
			icon = "lifeLeechChance",
			customStats = {
				lifeLeechChance = 1,
				lifeLeechAmount = 1
			},
			inputs = {
				565	
			},
			out = {
				566
			}
		},
		--- 568 ---
		{
			orbit = 2,
			orbitDist = 180,
			name = "Attribute",
			orbitIndex = 300,
			isUncommon = true,
			group = 99,
			icon = "loot",
			customStats = {
				strength = 3,
				loot = 10,
				experience = 10
			},
			inputs = {
				570
			},
			out = {
				569
			}
		},
		--- 569 ---
		{
			orbit = 3,
			orbitDist = 180,
			name = "Attribute",
			orbitIndex = 240,
			isUncommon = true,
			group = 99,
			icon = "lifeLeechChance",
			customStats = {
				lifeLeechChance = 1,
				lifeLeechAmount = 1,
				manaLeechChance = 1,
				manaLeechAmount = 1
			},
			inputs = {
				568, 571
			},
			out = {
				576
			}
		},
		--- 570 ---
		{
			orbit = 3,
			orbitDist = 180,
			name = "Attribute",
			orbitIndex = 1,
			isUncommon = true,
			group = 99,
			icon = "healthDamage",
			customStats = {
				incrementHealth = 4,
			},
			inputs = {
				572
			},
			out = {
				568
			}
		},
		--- 571 ---
		{
			orbit = 1,
			orbitDist = 180,
			name = "Attribute",
			orbitIndex = 180,
			isUncommon = true,
			group = 99,
			icon = "experience",
			customStats = {
				dexterity = 3,
				experience = 10,
				rarityLoot = 3
			},
			inputs = {
				573
			},
			out = {
				569
			}
		},
		--- 572 ---
		{
			orbit = 4,
			orbitDist = 180,
			name = "Attribute",
			orbitIndex = 60,
			isUncommon = true,
			group = 99,
			icon = "intelligence",
			customStats = {
				intelligence = 5,
			},
			inputs = {
				562
			},
			out = {
				570, 573
			}
		},
		--- 573 ---
		{
			orbit = 2,
			orbitDist = 180,
			name = "Attribute",
			orbitIndex = 120,
			isUncommon = true,
			group = 99,
			icon = "healthDamage",
			customStats = {
				incrementHealth = 4,
			},
			inputs = {
				572
			},
			out = {
				571
			}
		},
		--- 574 ---
		{
			orbit = 1,
			orbitDist = 90,
			name = "Attribute",
			orbitIndex = 120,
			isMythic = true,
			group = 99,
			icon = "manaLeechAmount",
			customStats = {
				manaLeechChance = 1,
				manaLeechAmount = 2
			},
			inputs = {
				575
			},
			out = {
				579
			}
		},
		--- 575 ---
		{
			orbit = 2,
			orbitDist = 90,
			name = "Attribute",
			orbitIndex = 180,
			isMythic = true,
			group = 99,
			icon = "criticalHitAmount",
			customStats = {
				criticalHitChance = 1,
				criticalHitAmount = 2
			},
			inputs = {
				576
			},
			out = {
				574
			}
		},
		--- 576 ---
		{
			orbit = 4,
			orbitDist = 90,
			name = "Attribute",
			orbitIndex = 240,
			isMythic = true,
			group = 99,
			icon = "healthDamage",
			customStats = {
				incrementHealth = 5,
			},
			inputs = {
				569
			},
			out = {
				575, 577
			}
		},
		--- 577 ---
		{
			orbit = 1,
			orbitDist = 90,
			name = "Attribute",
			orbitIndex = 300,
			isMythic = true,
			group = 99,
			icon = "criticalHitChance",
			customStats = {
				criticalHitChance = 1,
				criticalHitAmount = 2
			},
			inputs = {
				576
			},
			out = {
				578
			}
		},
		--- 578 ---
		{
			orbit = 3,
			orbitDist = 90,
			name = "Attribute",
			orbitIndex = 1,
			isMythic = true,
			group = 99,
			icon = "lifeLeechChance",
			customStats = {
				lifeLeechChance = 1,
				lifeLeechAmount = 2
			},
			inputs = {
				577
			},
			out = {
				579
			}
		},
		--- 579 ---
		{
			orbit = 2,
			orbitDist = 90,
			name = "Attribute",
			orbitIndex = 60,
			isMythic = true,
			group = 99,
			icon = "healthDamage",
			customStats = {
				incrementHealth = 3,
				criticalHitChance = 2,
				criticalHitAmount = 3
			},
			inputs = {
				574, 578
			},
			out = {
				580
			}
		},
		--- 580 ---
		{
			orbit = 0,
			orbitDist = 0,
			name = "Diamond Skin",
			orbitIndex = 0,
			isDivine = true,
			group = 99,
			icon = "diamondSkin",
			customStats = {
				incrementHealth = 20,
				criticalHitChance = 2,
				criticalHitAmount = 3,
				lifeLeechChance = 2,
				lifeLeechAmount = 3,
				manaLeechAmount = 3,
				manaLeechChance = 2
			},
			inputs = {
				579
			},
			out = {
				
			}
		},
		--- 581 ---
		{
			orbit = 4,
			orbitDist = 300,
			name = "Attribute",
			orbitIndex = 60,
			group = 100,
			icon = "arcaneDamage",
			customStats = {
				incrementArcane = 1,
			},
			inputs = {
				582, 585
			},
			out = {
				591
			}
		},
		--- 582 ---
		{
			orbit = 3,
			orbitDist = 300,
			name = "Attribute",
			orbitIndex = 120,
			group = 100,
			icon = "absorbArcane",
			customStats = {
				absorbArcane = 1,
			},
			inputs = {
				583
			},
			out = {
				581
			}
		},
		--- 583 ---
		{
			orbit = 1,
			orbitDist = 300,
			name = "Attribute",
			orbitIndex = 180,
			group = 100,
			icon = "arcaneDamage",
			customStats = {
				incrementArcane = 1,
			},
			inputs = {
				584
			},
			out = {
				582
			}
		},
		--- 584 ---
		{
			orbit = 2,
			orbitDist = 300,
			name = "Attribute",
			orbitIndex = 240,
			group = 100,
			icon = "absorbArcane",
			customStats = {
				absorbArcane = 1,
			},
			inputs = {
				195, 242
			},
			out = {
				583, 586
			}
		},
		--- 585---
		{
			orbit = 3,
			orbitDist = 300,
			name = "Attribute",
			orbitIndex = 1,
			group = 100,
			icon = "absorbArcane",
			customStats = {
				absorbArcane = 1,
			},
			inputs = {
				586
			},
			out = {
				581
			}
		},
		--- 586 ---
		{
			orbit = 1,
			orbitDist = 300,
			name = "Attribute",
			orbitIndex = 300,
			group = 100,
			icon = "arcaneDamage",
			customStats = {
				incrementArcane = 1,
			},
			inputs = {
				584
			},
			out = {
				585
			}
		},
		--- 587 ---
		{
			orbit = 2,
			orbitDist = 180,
			name = "Attribute",
			orbitIndex = 300,
			isUncommon = true,
			group = 100,
			icon = "loot",
			customStats = {
				strength = 3,
				loot = 10,
				experience = 10
			},
			inputs = {
				589
			},
			out = {
				588
			}
		},
		--- 588 ---
		{
			orbit = 3,
			orbitDist = 180,
			name = "Attribute",
			orbitIndex = 240,
			isUncommon = true,
			group = 100,
			icon = "absorbArcane",
			customStats = {
				incrementArcane = 4,
				absorbArcane = 2
			},
			inputs = {
				587, 590
			},
			out = {
				595
			}
		},
		--- 589 ---
		{
			orbit = 3,
			orbitDist = 180,
			name = "Attribute",
			orbitIndex = 1,
			isUncommon = true,
			group = 100,
			icon = "absorbArcane",
			customStats = {
				absorbArcane = 2,
			},
			inputs = {
				591
			},
			out = {
				587
			}
		},
		--- 590 ---
		{
			orbit = 1,
			orbitDist = 180,
			name = "Attribute",
			orbitIndex = 180,
			isUncommon = true,
			group = 100,
			icon = "rarityLoot",
			customStats = {
				dexterity = 3,
				rarityLoot = 3,
				experience = 10
			},
			inputs = {
				592
			},
			out = {
				588
			}
		},
		--- 591 ---
		{
			orbit = 1,
			orbitDist = 180,
			name = "Attribute",
			orbitIndex = 60,
			isUncommon = true,
			group = 100,
			icon = "intelligence",
			customStats = {
				intelligence = 5,
			},
			inputs = {
				581
			},
			out = {
				589, 592
			}
		},
		--- 592 ---
		{
			orbit = 2,
			orbitDist = 180,
			name = "Attribute",
			orbitIndex = 120,
			isUncommon = true,
			group = 100,
			icon = "arcaneDamage",
			customStats = {
				incrementArcane = 2,
			},
			inputs = {
				591
			},
			out = {
				590
			}
		},
		--- 593 ---
		{
			orbit = 1,
			orbitDist = 90,
			name = "Attribute",
			orbitIndex = 120,
			isMythic = true,
			group = 100,
			icon = "arcaneDamage",
			customStats = {
				incrementArcane = 6,
			},
			inputs = {
				594
			},
			out = {
				598	
			}
		},
		--- 594 ---
		{
			orbit = 2,
			orbitDist = 90,
			name = "Attribute",
			orbitIndex = 180,
			isMythic = true,
			group = 100,
			icon = "absorbArcane",
			customStats = {
				absorbArcane = 3,
			},
			inputs = {
				595
			},
			out = {
				593
			}
		},
		--- 595 ---
		{
			orbit = 4,
			orbitDist = 90,
			name = "Attribute",
			orbitIndex = 240,
			isMythic = true,
			group = 100,
			icon = "arcaneDamage",
			customStats = {
				incrementArcane = 5,
			},
			inputs = {
				588
			},
			out = {
				594, 596
			}
		},
		--- 596 ---
		{
			orbit = 1,
			orbitDist = 90,
			name = "Attribute",
			orbitIndex = 300,
			isMythic = true,
			group = 100,
			icon = "absorbArcane",
			customStats = {
				absorbArcane = 3,
			},
			inputs = {
				595
			},
			out = {
				597
			}
		},
		--- 597 ---
		{
			orbit = 3,
			orbitDist = 90,
			name = "Attribute",
			orbitIndex = 1,
			isMythic = true,
			group = 100,
			icon = "arcaneDamage",
			customStats = {
				incrementArcane = 6,
			},
			inputs = {
				596
			},
			out = {
				598
			}
		},
		--- 598 ---
		{
			orbit = 2,
			orbitDist = 90,
			name = "Attribute",
			orbitIndex = 60,
			isMythic = true,
			group = 100,
			icon = "absorbArcane",
			customStats = {
				absorbArcane = 4,
			},
			inputs = {
				593, 597
			},
			out = {
				599
			}
		},
		--- 599 ---
		{
			orbit = 0,
			orbitDist = 0,
			name = "Arcane Surge",
			orbitIndex = 0,
			isDivine = true,
			group = 100,
			icon = "arcaneSurge",
			customStats = {
				intelligence = 3,
				speed = 500,
				incrementArcane = 15,
				absorbArcane = 6,
				magicSkill = 2
			},
			inputs = {
				598
			},
			out = {
				
			}
		},
		--- 600 ---
		{
			orbit = 1,
			orbitDist = 300,
			name = "Attribute",
			orbitIndex = 60,
			group = 101,
			icon = "absorbWater",
			customStats = {
				absorbWater = 1,
			},
			inputs = {
				601
			},
			out = {
				604, 619
			}
		},
		--- 601 ---
		{
			orbit = 3,
			orbitDist = 300,
			name = "Attribute",
			orbitIndex = 120,
			group = 101,
			icon = "waterDamage",
			customStats = {
				incrementWater = 1,
			},
			inputs = {
				602
			},
			out = {
				600
			}
		},
		--- 602 ---
		{
			orbit = 1,
			orbitDist = 300,
			name = "Attribute",
			orbitIndex = 180,
			group = 101,
			icon = "absorbWater",
			customStats = {
				absorbWater = 1,
			},
			inputs = {
				245
			},
			out = {
				603, 601
			}
		},
		--- 603 ---
		{
			orbit = 2,
			orbitDist = 300,
			name = "Attribute",
			orbitIndex = 240,
			group = 101,
			icon = "waterDamage",
			customStats = {
				incrementWater = 1,
			},
			inputs = {
				602	
			},
			out = {
				605
			}
		},
		--- 604---
		{
			orbit = 3,
			orbitDist = 300,
			name = "Attribute",
			orbitIndex = 1,
			group = 101,
			icon = "waterDamage",
			customStats = {
				incrementWater = 1,
			},
			inputs = {
				600, 605	
			},
			out = {
				608
			}
		},
		--- 605 ---
		{
			orbit = 1,
			orbitDist = 300,
			name = "Attribute",
			orbitIndex = 300,
			group = 101,
			icon = "absorbWater",
			customStats = {
				absorbWater = 1,
			},
			inputs = {
				603
			},
			out = {
				604
			}
		},
		--- 606 ---
		{
			orbit = 2,
			orbitDist = 180,
			name = "Attribute",
			orbitIndex = 300,
			isUncommon = true,
			group = 101,
			icon = "absorbWater",
			customStats = {
				absorbWater = 2,
			},
			inputs = {
				608
			},
			out = {
				607
			}
		},
		--- 607 ---
		{
			orbit = 3,
			orbitDist = 180,
			name = "Attribute",
			orbitIndex = 240,
			isUncommon = true,
			group = 101,
			icon = "experience",
			customStats = {
				strength = 2,
				dexterity = 2,
				experience = 10,
				loot = 10
			},
			inputs = {
				606
			},
			out = {
				609
			}
		},
		--- 608 ---
		{
			orbit = 4,
			orbitDist = 180,
			name = "Attribute",
			orbitIndex = 1,
			isUncommon = true,
			group = 101,
			icon = "multiStat",
			customStats = {
				intelligence = 2,
				strength = 2,
				dexterity = 2
			},
			inputs = {
				604
			},
			out = {
				606, 610
			}
		},
		--- 609 ---
		{
			orbit = 4,
			orbitDist = 180,
			name = "Attribute",
			orbitIndex = 180,
			isUncommon = true,
			group = 101,
			icon = "absorbWater",
			customStats = {
				incrementWater = 4,
				absorbWater= 2
			},
			inputs = {
				607, 611
			},
			out = {
				613
			}
		},
		--- 610 ---
		{
			orbit = 2,
			orbitDist = 180,
			name = "Attribute",
			orbitIndex = 60,
			isUncommon = true,
			group = 101,
			icon = "waterDamage",
			customStats = {
				incrementWater = 2,
			},
			inputs = {
				608
			},
			out = {
				611
			}
		},
		--- 611 ---
		{
			orbit = 3,
			orbitDist = 180,
			name = "Attribute",
			orbitIndex = 120,
			isUncommon = true,
			group = 101,
			icon = "rarityLoot",
			customStats = {
				dexterity = 2,
				intelligence = 2,
				rarityLoot = 3,
				experience = 10
			},
			inputs = {
				610
			},
			out = {
				609
			}
		},
		--- 612 ---
		{
			orbit = 1,
			orbitDist = 90,
			name = "Attribute",
			orbitIndex = 120,
			isMythic = true,
			group = 101,
			icon = "absorbWater",
			customStats = {
				absorbWater = 3,
			},
			inputs = {
				613
			},
			out = {
				617
			}
		},
		--- 613 ---
		{
			orbit = 2,
			orbitDist = 90,
			name = "Attribute",
			orbitIndex = 180,
			isMythic = true,
			group = 101,
			icon = "waterDamage",
			customStats = {
				incrementWater = 5,
			},
			inputs = {
				609
			},
			out = {
				612, 614
			}
		},
		--- 614 ---
		{
			orbit = 3,
			orbitDist = 90,
			name = "Attribute",
			orbitIndex = 240,
			isMythic = true,
			group = 101,
			icon = "absorbWater",
			customStats = {
				absorbWater = 3,
			},
			inputs = {
				613
			},
			out = {
				615
			}
		},
		--- 615 ---
		{
			orbit = 1,
			orbitDist = 90,
			name = "Attribute",
			orbitIndex = 300,
			isMythic = true,
			group = 101,
			icon = "waterDamage",
			customStats = {
				incrementWater = 6,
			},
			inputs = {
				614
			},
			out = {
				616
			}
		},
		--- 616 ---
		{
			orbit = 2,
			orbitDist = 90,
			name = "Attribute",
			orbitIndex = 1,
			isMythic = true,
			group = 101,
			icon = "absorbWater",
			customStats = {
				absorbWater = 4,
			},
			inputs = {
				615, 617
			},
			out = {
				618
			}
		},
		--- 617 ---
		{
			orbit = 3,
			orbitDist = 90,
			name = "Attribute",
			orbitIndex = 60,
			isMythic = true,
			group = 101,
			icon = "waterDamage",
			customStats = {
				incrementWater = 6,
			},
			inputs = {
				612
			},
			out = {
				616
			}
		},
		--- 618 ---
		{
			orbit = 0,
			orbitDist = 0,
			name = "Forethought",
			orbitIndex = 0,
			isDivine = true,
			group = 101,
			icon = "forethought",
			customStats = {
				incrementWater = 15,
				absorbWater = 6,
				spirit = 5,
				vitality = 5,
				wisdom = 3,
				intelligence = 2,
				experience = 20
			},
			inputs = {
				616
			},
			out = {
				
			}
		},

		--- Keystones (619-624): two paths of two notables, each ending in a per-vocation keystone ---
		--- 619 ---
		{
			orbit = 2,
			orbitDist = 340,
			name = "Gathering Fury",
			orbitIndex = 310,
			isMythic = true,
			group = 102,
			icon = "attackDamage",
			customStats = {
				incrementPhysical = 3,
				multiIncrement = 3
			},
			inputs = {
				600
			},
			out = {
				620
			}
		},
		--- 620 ---
		{
			orbit = 1,
			orbitDist = 150,
			name = "Edge of Ruin",
			orbitIndex = 310,
			isMythic = true,
			group = 102,
			icon = "spellDamage",
			customStats = {
				incrementPhysical = 4,
				multiIncrement = 4,
				incrementHealth = 4
			},
			inputs = {
				619
			},
			out = {
				621
			}
		},
		--- 621 ---
		-- keystone: every class of the Warrior, Ranger and Mystic lines sees (and gets) its own keystone here (the
		-- variant key is ChaosClasses.keystoneKey); the server reads the same per-class customStats (passivetree_data.lua `v`); effects in passivetree_keystones.lua
		{
			orbit = 0,
			orbitDist = 0,
			name = "Wrath Keystone",
			orbitIndex = 0,
			isDivine = true,
			isKeystone = true,
			group = 102,
			icon = "ksWrath",
			stats = {
				"Holds the keystone of your class (Warrior,",
				"Ranger and Mystic lines; the other lines have",
				"theirs in their class section)."
			},
			knight = {
				icon = "ksCleavingArc",
				name = "Cleaving Arc",
				customStats = {
					ksCleavingArc = 1
				},
				stats = {
					"Two-handed melee hits cleave: up to 3 other",
					"enemies next to you take 40% of the hit."
				}
			},
			paladin = {
				icon = "ksRicochet",
				name = "Ricochet",
				customStats = {
					ksRicochet = 1
				},
				stats = {
					"Bow and crossbow hits: 30% chance to ricochet to",
					"the nearest other enemy within 4 sqm for 65% of",
					"the hit, then once more for 65% of that (42%).",
					"Never the same target twice."
				}
			},
			sorcerer = {
				icon = "ksArcaneEcho",
				name = "Arcane Echo",
				customStats = {
					ksArcaneEcho = 1
				},
				stats = {
					"Spells that hit 2 or more enemies: 35% chance to",
					"echo 0.6 s later on the same spots for 50% of",
					"their damage. Cooldown 3 s."
				}
			},
			druid = {
				icon = "ksOvergrowth",
				name = "Overgrowth",
				customStats = {
					ksOvergrowth = 1
				},
				stats = {
					"Heals you cast on others also plant regrowth:",
					"30% of the heal again over 6 s (3 pulses).",
					"A new heal refreshes it."
				}
			},
			illusionist = {
				icon = "ksSharedPhantasm",
				name = "Shared Phantasm",
				customStats = {
					ksSharedPhantasm = 1
				},
				stats = {
					"Support (needs a party): your hits mark the enemy",
					"for 6 s. Other party members deal +12% damage",
					"to a marked enemy and heal for 4% of it."
				}
			},
			juggernaut = {
				icon = "ksImmovable",
				name = "Immovable",
				customStats = {
					ksImmovable = 1
				},
				stats = {
					"You take 8% less damage, 16% less while",
					"below 50% health."
				}
			},
			berserker = {
				icon = "ksCleavingArc",
				name = "Cleaving Arc",
				customStats = {
					ksCleavingArc = 1
				},
				stats = {
					"Two-handed melee hits cleave: up to 3 other",
					"enemies next to you take 40% of the hit."
				}
			},
			deadeye = {
				icon = "ksHuntersFocus",
				name = "Hunter's Focus",
				customStats = {
					ksHuntersFocus = 1
				},
				stats = {
					"Bow and crossbow hits on the same target deal",
					"+4% more each, up to +20%. Another target",
					"(or 6 s without a hit) starts again."
				}
			},
			beastmaster = {
				icon = "ksRicochet",
				name = "Ricochet",
				customStats = {
					ksRicochet = 1
				},
				stats = {
					"Bow and crossbow hits: 30% chance to ricochet to",
					"the nearest other enemy within 4 sqm for 65% of",
					"the hit, then once more for 65% of that (42%).",
					"Never the same target twice."
				}
			},
			classes = {"warrior", "juggernaut", "berserker", "ranger", "deadeye", "beastmaster", "mystic", "elementalist", "illusionist"},
			inputs = {
				620
			},
			out = {
			}
		},
		--- 622 ---
		{
			orbit = 2,
			orbitDist = 340,
			name = "Iron Resolve",
			orbitIndex = 130,
			isMythic = true,
			group = 103,
			icon = "life",
			customStats = {
				vitality = 2,
				spirit = 2
			},
			inputs = {
				489
			},
			out = {
				623
			}
		},
		--- 623 ---
		{
			orbit = 1,
			orbitDist = 150,
			name = "Unbroken Will",
			orbitIndex = 130,
			isMythic = true,
			group = 103,
			icon = "damageReduction",
			customStats = {
				absorbPhysical = 2,
				absorbAllElements = 2
			},
			inputs = {
				622
			},
			out = {
				624
			}
		},
		--- 624 ---
		-- keystone: every class of the Warrior, Ranger and Mystic lines sees (and gets) its own keystone here (the
		-- variant key is ChaosClasses.keystoneKey); the server reads the same per-class customStats (passivetree_data.lua `v`); effects in passivetree_keystones.lua
		{
			orbit = 0,
			orbitDist = 0,
			name = "Resolve Keystone",
			orbitIndex = 0,
			isDivine = true,
			isKeystone = true,
			group = 103,
			icon = "ksResolve",
			stats = {
				"Holds the keystone of your class (Warrior,",
				"Ranger and Mystic lines; the other lines have",
				"theirs in their class section)."
			},
			knight = {
				icon = "ksBulwark",
				name = "Bulwark",
				customStats = {
					ksBulwark = 1
				},
				stats = {
					"With a shield: 15% chance to block a melee or",
					"ranged attack completely, and 30% of melee",
					"damage taken is reflected to the attacker."
				}
			},
			paladin = {
				icon = "ksDeadeye",
				name = "Deadeye",
				customStats = {
					ksDeadeye = 1
				},
				stats = {
					"Crossbow and bolts: 15% chance for a Deadeye",
					"shot that deals double damage (+100%)."
				}
			},
			sorcerer = {
				icon = "ksOverload",
				name = "Elemental Overload",
				customStats = {
					ksOverload = 1
				},
				stats = {
					"A spell hit primes the other elements: your next",
					"spell of a different element within 8 s deals",
					"+20% damage."
				}
			},
			druid = {
				icon = "ksThorns",
				name = "Thorns",
				customStats = {
					ksThorns = 1
				},
				stats = {
					"Melee and ranged attackers take earth damage",
					"back: 30% of their hit + 2 x your magic level."
				}
			},
			illusionist = {
				icon = "ksInspiringIllusion",
				name = "Inspiring Illusion",
				customStats = {
					ksInspiringIllusion = 1
				},
				stats = {
					"Support (needs a party): other party members",
					"within 8 sqm of you deal +8% damage."
				}
			},
			juggernaut = {
				icon = "ksBulwark",
				name = "Bulwark",
				customStats = {
					ksBulwark = 1
				},
				stats = {
					"With a shield: 15% chance to block a melee or",
					"ranged attack completely, and 30% of melee",
					"damage taken is reflected to the attacker."
				}
			},
			berserker = {
				icon = "ksUndyingRage",
				name = "Undying Rage",
				customStats = {
					ksUndyingRage = 1
				},
				stats = {
					"Melee weapon hits heal you for 4% of the",
					"damage dealt, 8% while below 50% health."
				}
			},
			deadeye = {
				icon = "ksDeadeye",
				name = "Deadeye",
				customStats = {
					ksDeadeye = 1
				},
				stats = {
					"Crossbow and bolts: 15% chance for a Deadeye",
					"shot that deals double damage (+100%)."
				}
			},
			beastmaster = {
				icon = "ksPackAlpha",
				name = "Pack Alpha",
				customStats = {
					ksPackAlpha = 1
				},
				stats = {
					"Your companions' bites and Feral Command deal",
					"+35% damage, and companions take 20% less."
				}
			},
			classes = {"warrior", "juggernaut", "berserker", "ranger", "deadeye", "beastmaster", "mystic", "elementalist", "illusionist"},
			inputs = {
				623
			},
			out = {
			}
		},
		--- Class sections (625-664): the Thief, Necromancer, Monk and Templar lines. Each line: a start node (its edges are
		--- the root's on the server), three line nodes and two ascended paths ending in a keystone. `line`: shown only to that
		--- line; `classes`: the classes that may take the node (the server checks the same, passivetree_data.lua `c`).
		--- Flags (ks..., ct...) and their numbers: server/data/scripts/chaos/class_tree.lua. All four sections share one place.
		--- 625: Thief section ---
		{
			isStartNode = true, group = 104, icon = "csThief", name = "Thief", line = "thief", inputs = {}, out = {626}
		},
		--- 626 ---
		{
			orbit = 0, orbitDist = 0, orbitIndex = 0, group = 105, isRare = true,
			name = "Light Feet", icon = "dexterity", line = "thief", classes = {"thief", "ninja", "samurai"},
			customStats = {dexterity = 4, speed = 200},
			inputs = {625}, out = {627}
		},
		--- 627 ---
		{
			orbit = 0, orbitDist = 0, orbitIndex = 0, group = 106, isRare = true,
			name = "Venom Craft", icon = "earthDamage", line = "thief", classes = {"thief", "ninja", "samurai"},
			customStats = {incrementEarth = 6, strength = 3},
			inputs = {626}, out = {628}
		},
		--- 628 ---
		{
			orbit = 0, orbitDist = 0, orbitIndex = 0, group = 107, isRare = true,
			name = "Shadow-born", icon = "swordSkill", line = "thief", classes = {"thief", "ninja", "samurai"},
			customStats = {swordSkill = 3, distanceSkill = 3, criticalHitChance = 1},
			inputs = {627}, out = {629, 632}
		},
		--- 629 ---
		{
			orbit = 0, orbitDist = 0, orbitIndex = 0, group = 108, isMythic = true,
			name = "Twin Fangs", icon = "attackDamage", line = "thief", classes = {"ninja"},
			customStats = {ctTwinFangs = 1, strength = 2},
			stats = {"Dual wield: the off-hand strike deals 65%", "of the main-hand hit (instead of 50%)."},
			inputs = {628}, out = {630}
		},
		--- 630 ---
		{
			orbit = 0, orbitDist = 0, orbitIndex = 0, group = 109, isMythic = true,
			name = "Fleet Shadow", icon = "dodgeLife", line = "thief", classes = {"ninja"},
			customStats = {ctFleetShadow = 1, dexterity = 2},
			stats = {"Evasion +4%."},
			inputs = {629}, out = {631}
		},
		--- 631 ---
		{
			orbit = 0, orbitDist = 0, orbitIndex = 0, group = 110, isDivine = true, isKeystone = true,
			name = "Living Shadow", icon = "ksLivingShadow", line = "thief", classes = {"ninja"},
			customStats = {ksLivingShadow = 1},
			stats = {"A dodge, or your first hit out of Shadow Veil,", "opens a 4 s window: your weapon hits and", "strikes deal +25% damage."},
			inputs = {630}, out = {}
		},
		--- 632 ---
		{
			orbit = 0, orbitDist = 0, orbitIndex = 0, group = 111, isMythic = true,
			name = "Steel Discipline", icon = "armor", line = "thief", classes = {"samurai"},
			customStats = {vitality = 5, absorbPhysical = 3},
			inputs = {628}, out = {633}
		},
		--- 633 ---
		{
			orbit = 0, orbitDist = 0, orbitIndex = 0, group = 112, isMythic = true,
			name = "Iron Parry", icon = "shield", line = "thief", classes = {"samurai"},
			customStats = {ctIronParry = 1, shieldingSkill = 2},
			stats = {"Counter Stance: the answer deals +50% and", "the stance lasts 1 s longer."},
			inputs = {632}, out = {634}
		},
		--- 634 ---
		{
			orbit = 0, orbitDist = 0, orbitIndex = 0, group = 113, isDivine = true, isKeystone = true,
			name = "Way of the Blade", icon = "ksWayOfTheBlade", line = "thief", classes = {"samurai"},
			customStats = {ksWayOfTheBlade = 1},
			stats = {"Counter Stance parries every melee hit while", "it lasts (not only the first). Bushido Focus:", "a hit taken keeps half of the stacks."},
			inputs = {633}, out = {}
		},
		--- 635: Necromancer section ---
		{
			isStartNode = true, group = 104, icon = "csNecromancer", name = "Necromancer", line = "necromancer", inputs = {}, out = {636}
		},
		--- 636 ---
		{
			orbit = 0, orbitDist = 0, orbitIndex = 0, group = 105, isRare = true,
			name = "Grave Lore", icon = "magicSkill", line = "necromancer", classes = {"necromancer", "lich", "bonelord"},
			customStats = {magicSkill = 2, intelligence = 3},
			inputs = {635}, out = {637}
		},
		--- 637 ---
		{
			orbit = 0, orbitDist = 0, orbitIndex = 0, group = 106, isRare = true,
			name = "Bone Craft", icon = "physicalDamage", line = "necromancer", classes = {"necromancer", "lich", "bonelord"},
			customStats = {incrementPhysical = 6, incrementDeath = 4},
			inputs = {636}, out = {638}
		},
		--- 638 ---
		{
			orbit = 0, orbitDist = 0, orbitIndex = 0, group = 107, isRare = true,
			name = "Dark Pact", icon = "life", line = "necromancer", classes = {"necromancer", "lich", "bonelord"},
			customStats = {spirit = 4, vitality = 4},
			inputs = {637}, out = {639, 642}
		},
		--- 639 ---
		{
			orbit = 0, orbitDist = 0, orbitIndex = 0, group = 108, isMythic = true,
			name = "Spreading Blight", icon = "deathDamage", line = "necromancer", classes = {"lich"},
			customStats = {ctSpreadingBlight = 1, incrementDeath = 3},
			stats = {"Withering Curse spreads to one more enemy."},
			inputs = {638}, out = {640}
		},
		--- 640 ---
		{
			orbit = 0, orbitDist = 0, orbitIndex = 0, group = 109, isMythic = true,
			name = "Lingering Rot", icon = "vitalityDrain", line = "necromancer", classes = {"lich"},
			customStats = {ctLingeringRot = 1, magicSkill = 1},
			stats = {"Soul Rot deals +25% damage."},
			inputs = {639}, out = {641}
		},
		--- 641 ---
		{
			orbit = 0, orbitDist = 0, orbitIndex = 0, group = 110, isDivine = true, isKeystone = true,
			name = "Hoarded Souls", icon = "ksHoardedSouls", line = "necromancer", classes = {"lich"},
			customStats = {ksHoardedSouls = 1},
			stats = {"Soul Hoard: +40% spell damage per empty shade", "slot (instead of 25%), and +15% while your", "shade is out."},
			inputs = {640}, out = {}
		},
		--- 642 ---
		{
			orbit = 0, orbitDist = 0, orbitIndex = 0, group = 111, isMythic = true,
			name = "Legion", icon = "skill", line = "necromancer", classes = {"bonelord"},
			customStats = {ctLegion = 1, spirit = 2},
			stats = {"Raise Dead: one more skeleton."},
			inputs = {638}, out = {643}
		},
		--- 643 ---
		{
			orbit = 0, orbitDist = 0, orbitIndex = 0, group = 112, isMythic = true,
			name = "Banner Bearer", icon = "multiStat", line = "necromancer", classes = {"bonelord"},
			customStats = {ctBannerBearer = 1, vitality = 2},
			stats = {"Banner of Bones: your minions deal +45%", "damage (instead of 30%)."},
			inputs = {642}, out = {644}
		},
		--- 644 ---
		{
			orbit = 0, orbitDist = 0, orbitIndex = 0, group = 113, isDivine = true, isKeystone = true,
			name = "Bone Colossus", icon = "ksBoneColossus", line = "necromancer", classes = {"bonelord"},
			customStats = {ksBoneColossus = 1},
			stats = {"Your Bone Golem hits +60% harder and has", "+50% health."},
			inputs = {643}, out = {}
		},
		--- 645: Monk section ---
		{
			isStartNode = true, group = 104, icon = "csMonk", name = "Monk", line = "monk", inputs = {}, out = {646}
		},
		--- 646 ---
		{
			orbit = 0, orbitDist = 0, orbitIndex = 0, group = 105, isRare = true,
			name = "Iron Fist", icon = "physicalDamage", line = "monk", classes = {"monk", "shadowfist", "ironsage"},
			customStats = {incrementPhysical = 6, strength = 3},
			inputs = {645}, out = {647}
		},
		--- 647 ---
		{
			orbit = 0, orbitDist = 0, orbitIndex = 0, group = 106, isRare = true,
			name = "Centered", icon = "dexterity", line = "monk", classes = {"monk", "shadowfist", "ironsage"},
			customStats = {dexterity = 4, vitality = 3},
			inputs = {646}, out = {648}
		},
		--- 648 ---
		{
			orbit = 0, orbitDist = 0, orbitIndex = 0, group = 107, isRare = true,
			name = "Flowing Chi", icon = "criticalHitChance", line = "monk", classes = {"monk", "shadowfist", "ironsage"},
			customStats = {criticalHitChance = 2, speed = 200},
			inputs = {647}, out = {649, 652}
		},
		--- 649 ---
		{
			orbit = 0, orbitDist = 0, orbitIndex = 0, group = 108, isMythic = true,
			name = "Precise Strikes", icon = "criticalHitAmount", line = "monk", classes = {"shadowfist"},
			customStats = {criticalHitChance = 2, criticalHitAmount = 6},
			inputs = {648}, out = {650}
		},
		--- 650 ---
		{
			orbit = 0, orbitDist = 0, orbitIndex = 0, group = 109, isMythic = true,
			name = "Nerve Strike", icon = "trueStrike", line = "monk", classes = {"shadowfist"},
			customStats = {ctNerveStrike = 1, strength = 2},
			stats = {"Pressure Points: +6% damage taken per stack", "(instead of 5%)."},
			inputs = {649}, out = {651}
		},
		--- 651 ---
		{
			orbit = 0, orbitDist = 0, orbitIndex = 0, group = 110, isDivine = true, isKeystone = true,
			name = "Hundred Hands", icon = "ksHundredHands", line = "monk", classes = {"shadowfist"},
			customStats = {ksHundredHands = 1},
			stats = {"Focus critical hits also give you a chi", "(at most one per second)."},
			inputs = {650}, out = {}
		},
		--- 652 ---
		{
			orbit = 0, orbitDist = 0, orbitIndex = 0, group = 111, isMythic = true,
			name = "Healing Hands", icon = "healing", line = "monk", classes = {"ironsage"},
			customStats = {incrementHealth = 8, vitality = 3},
			inputs = {648}, out = {653}
		},
		--- 653 ---
		{
			orbit = 0, orbitDist = 0, orbitIndex = 0, group = 112, isMythic = true,
			name = "Deep Mantra", icon = "damageReduction", line = "monk", classes = {"ironsage"},
			customStats = {ctDeepMantra = 1, vitality = 2},
			stats = {"Mantra of Stone: 11% less damage taken", "(instead of 8%)."},
			inputs = {652}, out = {654}
		},
		--- 654 ---
		{
			orbit = 0, orbitDist = 0, orbitIndex = 0, group = 113, isDivine = true, isKeystone = true,
			name = "Flowing Mercy", icon = "ksFlowingMercy", line = "monk", classes = {"ironsage"},
			customStats = {ksFlowingMercy = 1},
			stats = {"Kindled Breath also heals the next most hurt", "party member for 40% of it (and its heal", "over time)."},
			inputs = {653}, out = {}
		},
		--- 655: Templar section ---
		{
			isStartNode = true, group = 104, icon = "csTemplar", name = "Templar", line = "templar", inputs = {}, out = {656}
		},
		--- 656 ---
		{
			orbit = 0, orbitDist = 0, orbitIndex = 0, group = 105, isRare = true,
			name = "Holy Vigor", icon = "holyDamage", line = "templar", classes = {"templar", "inquisitor", "sentinel"},
			customStats = {incrementHoly = 6, vitality = 3},
			inputs = {655}, out = {657}
		},
		--- 657 ---
		{
			orbit = 0, orbitDist = 0, orbitIndex = 0, group = 106, isRare = true,
			name = "Shield of Faith", icon = "shieldingSkill", line = "templar", classes = {"templar", "inquisitor", "sentinel"},
			customStats = {shieldingSkill = 3, absorbPhysical = 2},
			inputs = {656}, out = {658}
		},
		--- 658 ---
		{
			orbit = 0, orbitDist = 0, orbitIndex = 0, group = 107, isRare = true,
			name = "Righteous Arm", icon = "swordSkill", line = "templar", classes = {"templar", "inquisitor", "sentinel"},
			customStats = {swordSkill = 2, clubSkill = 2, strength = 3},
			inputs = {657}, out = {659, 662}
		},
		--- 659 ---
		{
			orbit = 0, orbitDist = 0, orbitIndex = 0, group = 108, isMythic = true,
			name = "Sacred Fire", icon = "divineFervour", line = "templar", classes = {"inquisitor"},
			customStats = {incrementHoly = 8, magicSkill = 2},
			inputs = {658}, out = {660}
		},
		--- 660 ---
		{
			orbit = 0, orbitDist = 0, orbitIndex = 0, group = 109, isMythic = true,
			name = "Burning Zeal", icon = "righteousDecree", line = "templar", classes = {"inquisitor"},
			customStats = {ctBurningZeal = 1, strength = 2},
			stats = {"Radiant Strikes: the holy strike deals 30%", "of the hit (instead of 25%)."},
			inputs = {659}, out = {661}
		},
		--- 661 ---
		{
			orbit = 0, orbitDist = 0, orbitIndex = 0, group = 110, isDivine = true, isKeystone = true,
			name = "Divine Verdict", icon = "ksDivineVerdict", line = "templar", classes = {"inquisitor"},
			customStats = {ksDivineVerdict = 1},
			stats = {"Your Radiant Strikes have a 20% chance to", "judge their target (Judgement: +20% holy", "damage taken from everyone for 8 s)."},
			inputs = {660}, out = {}
		},
		--- 662 ---
		{
			orbit = 0, orbitDist = 0, orbitIndex = 0, group = 111, isMythic = true,
			name = "Steadfast", icon = "absorbLifeMana", line = "templar", classes = {"sentinel"},
			customStats = {absorbAllElements = 2, absorbPhysical = 2},
			inputs = {658}, out = {663}
		},
		--- 663 ---
		{
			orbit = 0, orbitDist = 0, orbitIndex = 0, group = 112, isMythic = true,
			name = "Sanctuary", icon = "healing", line = "templar", classes = {"sentinel"},
			customStats = {ctSanctuary = 1, vitality = 2},
			stats = {"Your aura regenerates 0.5% of the maximum", "health per second (instead of 0.4%)."},
			inputs = {662}, out = {664}
		},
		--- 664 ---
		{
			orbit = 0, orbitDist = 0, orbitIndex = 0, group = 113, isDivine = true, isKeystone = true,
			name = "Bastion", icon = "ksBastion", line = "templar", classes = {"sentinel"},
			customStats = {ksBastion = 1},
			stats = {"Your aura: 4% less damage more and 1 sqm", "wider. Aegis of Faith also covers the party", "members under your aura, at half strength."},
			inputs = {663}, out = {}
		},
}
end

return 