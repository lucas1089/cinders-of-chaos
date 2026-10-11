-- Item sets: every set, its pieces, its bonuses, its drop sources and every number of the set effects
-- (data/lib/chaos_item_sets.lua, data/scripts/chaos/itemsets.lua; server/README.md "Item sets").
-- Loaded with  ChaosItemSetsConfig = dofile("data/lib/chaos_item_sets_config.lua"). Plain Lua, edit freely; then
-- regenerate the unique specs (stats of the pieces live in data/items/chaos_items.xml) and the Codex:
--   cd server && python3 -I tools/gen_unique_specs.py && luajit tools/gen_codex_data.lua
--
-- A piece is a unique (ChaosMakeUnique): a copy of a stock base item with its own name, description and stats from
-- chaos_items.xml, plus the custom attribute "chaos_set" = the set key. pieces: id = the base server id (also the id
-- of its chaos_items.xml entry), name (must be the XML name), slot (head, body, legs, feet, necklace, ring, shield,
-- weapon), hands = 2 for a two-handed weapon (it counts as two pieces), level = the level the piece needs to count
-- (default: the set's level). Every base item's own equip rules (level, classes: data/movements/movements.xml) stay, so
-- a set's level is at least the highest equip level of its base items and its pieces suit the classes it is for.
--
-- bonuses: {n = pieces needed, stats = {key = value}, effect = key of `effects`}. Stat keys:
--   any modifier key of chaos_item_mods.lua (bleedchance, dot, block, dodge, thorns, monsterreduction, physpen, elepen,
--     bossdamage, movespeed, lifeonkill, regen, healing, cdr, manacost, ...) and of the legendary powers (deathblast, ...):
--     added to the equipped items' totals BEFORE the caps, so a set never lifts a cap
--   magic, skill_sword, skill_axe, skill_club, skill_dist, skill_shield, skill_fist, maxhealth, maxmana,
--     maxhealthpct, maxmanapct: one CONDITION_ATTRIBUTES (sub id conditionSubId)
--   res_fire, res_ice, res_earth, res_energy, res_death, res_holy, res_physical: percent less damage of that type taken
--
-- family: melee, ranged, caster, support, hybrid (the Codex filter); classes: who it is built for (text only).
-- sources: where the pieces drop (every piece of the set from every source listed):
--   uniques = {minTier, chance, monsters, bossOnly}  one ChaosUniqueItems entry per piece (loot.lua: corpse drops; the
--                                                    world bosses' participation pool takes the bossOnly ones naming them)
--   rift = {theme, minTier}                          the rift chest of that theme from that key tier (chase.rift)
--   raid = {boss key, ...}                           the Ashen Sepulchre's spoils of those bosses (chase.raid)
--   descent = {minDepth}                             the Ember Descent's exit rewards from that depth (chase.descent)
--   dungeon = true                                   a dungeon clear (chase.dungeon)
-- Chase pieces only drop for a character of at least (set level - chase.levelBelow).

local WORLD = {
	kaelgor = "Kaelgor the Infernal Warlord", skaldra = "Skaldra the Rime Queen", rotmother = "The Rotmother",
	nyxareth = "Nyxareth the Void Archon", vharok = "Vharok the Blood Colossus"
}

return {
	conditionSubId = 7245, -- next to the gems' condition (7240) and the passive tree's (7200-7221)

	-- chase drops (chances per 10000, x the player's item find, capped by max)
	chase = {
		levelBelow = 50,
		rift = {base = 250, perTier = 25, max = 800}, -- per finisher's chest, + perTier for every tier above the set's
		raid = {boss = 200, final = 500},              -- per boss loot (a character loots each boss once a week)
		descent = {base = 300, perDepth = 100, clear = 500, max = 1200}, -- per run exit from minDepth
		dungeon = {base = 150, perDifficulty = 50, max = 600} -- per dungeon clear, + per difficulty step
	},

	-- the signature effects (itemsets.lua). text: what the tooltip and the Codex say, {field} = a number of the effect
	effects = {
		pyrebulwark = {pct = 40, rounds = 6, interval = 1000, cooldownMs = 1000,
			text = "Pyre Bulwark: a hit you block or dodge sets the attacker ablaze for {pct}% of it as fire over {rounds} s"},
		hemorrhage = {radius = 2, targets = 3, windowMs = 4000,
			text = "Hemorrhage: a monster that dies bleeding from you passes the bleed to {targets} monsters within {radius} sqm"},
		redharvest = {cooldownMs = 500,
			text = "Red Harvest: your critical hits open a fresh bleed on the target"},
		oathward = {radius = 3, healPct = 2, cooldownMs = 2000,
			text = "Ashen Oath: when you block, party members within {radius} sqm heal {healPct}% of their health (2 s)"},
		hangingverdict = {below = 35, pct = 20,
			text = "Hanging Verdict: your ranged hits deal {pct}% more to monsters below {below}% health"},
		thornvolley = {pct = 30, radius = 2, cooldownMs = 1500,
			text = "Thorn Volley: a ranged hit splinters {pct}% of it onto a monster within {radius} sqm (1.5 s)"},
		soulsiphon = {pct = 6,
			text = "Soul Siphon: your damage over time heals you for {pct}% of the damage it deals"},
		mirrorgrace = {pct = 25,
			text = "Mirror Grace: your heals on another player heal you for {pct}% of the amount"},
		umbralrecoil = {speed = 40, ms = 3000, windowMs = 3000, pct = 40, cooldownMs = 4000,
			text = "Umbral Recoil: a dodge gives haste and +{pct}% on your next hit within 3 s (4 s cooldown)"},
		packbond = {pct = 20, healPct = 2,
			text = "Pack Bond: your summons deal {pct}% more damage; their kills heal you {healPct}% of your health"}
	},

	sets = {
		-- ------------------------------------------------------------------ melee
		-- the six pieces were uniques before the sets; three of their base items are Mystic / Necromancer gear (the
		-- engine's equip rules), so this is a battle-mage's set. Piece levels: the higher of the unique's and the base
		-- item's equip level.
		{key = "embers", name = "Embers of Aranoth", family = "support", classes = "Illusionist, Elementalist holding the line",
			level = 70,
			lore = "The armour of the last warden-mage of Aranoth, who held the burning gate until the gate itself gave way.",
			pieces = {
				{id = 2496, name = "Hornsworn Helm", slot = "head", level = 70},
				{id = 8892, name = "Cindermail Coat", slot = "body", level = 80},
				{id = 27692, name = "Emberveil Greaves", slot = "legs", level = 250},
				{id = 27647, name = "Bloodstep Boots", slot = "feet", level = 150},
				{id = 3975, name = "Emberwarden", slot = "shield", level = 90},
				{id = 10314, name = "Cinderclaw Band", slot = "ring", level = 100}
			},
			bonuses = {
				{n = 2, stats = {res_fire = 6, magic = 1}},
				{n = 4, stats = {monsterreduction = 5, block = 4}},
				{n = 6, stats = {maxhealthpct = 6}, effect = "pyrebulwark"}
			},
			-- the pieces were uniques before the sets: their ChaosUniqueItems entries (fire monsters, rare tier) stay
			sources = {}},
		{key = "bloodsworn", name = "Bloodsworn Reaver", family = "melee", classes = "Berserker, two-handed Warrior",
			level = 300,
			lore = "Sworn on the Blood Colossus's own altar: every wound you open must stay open.",
			pieces = {
				{id = 27658, name = "Bloodsworn Greataxe", slot = "weapon", hands = 2},
				{id = 25410, name = "Bloodsworn Visage", slot = "head"},
				{id = 25175, name = "Bloodsworn Hauberk", slot = "body"},
				{id = 28100, name = "Bloodsworn Legplates", slot = "legs"},
				{id = 28101, name = "Bloodsworn Treads", slot = "feet"}
			},
			bonuses = {
				{n = 2, stats = {bleedchance = 10, dot = 15}},
				{n = 4, stats = {}, effect = "hemorrhage"},
				{n = 6, stats = {skill_axe = 3}, effect = "redharvest"}
			},
			sources = {
				uniques = {minTier = "boss", chance = 8, bossOnly = true, monsters = {WORLD.vharok}},
				rift = {theme = "Ashen Crypt", minTier = 5}
			}},
		{key = "ashwarden", name = "Oath of the Ashen Warden", family = "melee", classes = "Sentinel, Juggernaut, Templar",
			level = 800,
			lore = "The wardens of the Sepulchre swore to keep the dead in. Their oath outlived them; their armour still keeps it.",
			pieces = {
				{id = 29560, name = "Ashwarden Visor", slot = "head"},
				{id = 29561, name = "Ashwarden Cuirass", slot = "body"},
				{id = 29559, name = "Ashwarden Bulwark", slot = "shield"},
				{id = 27403, name = "Ashwarden Seal", slot = "necklace"}
			},
			bonuses = {
				{n = 2, stats = {block = 5, maxhealthpct = 4}},
				{n = 4, stats = {monsterreduction = 4}, effect = "oathward"}
			},
			sources = {raid = {"ulthar", "sovereign"}}},

		-- ------------------------------------------------------------------ ranged
		{key = "gallows", name = "Gallows Marksman", family = "ranged", classes = "Deadeye, crossbow Ranger",
			level = 600,
			lore = "A hangman's kit for the patient: one bolt, one verdict, no appeal.",
			pieces = {
				{id = 27474, name = "Gallows Arbalest", slot = "weapon", hands = 2},
				{id = 29470, name = "Gallows Hood", slot = "head"},
				{id = 15407, name = "Gallows Coat", slot = "body"},
				{id = 28114, name = "Gallows Leggings", slot = "legs"}
			},
			bonuses = {
				{n = 2, stats = {skill_dist = 2, physpen = 6}},
				{n = 4, stats = {bossdamage = 8}, effect = "hangingverdict"}
			},
			sources = {
				uniques = {minTier = "boss", chance = 8, bossOnly = true, monsters = {WORLD.nyxareth}},
				rift = {theme = "Obsidian Hall", minTier = 7}
			}},
		{key = "thornwake", name = "Thornwake Volley", family = "ranged", classes = "Beastmaster, bow Ranger",
			level = 150,
			lore = "Cut from the briar that swallowed the Wildwood's first road; its arrows still remember the thorns.",
			pieces = {
				{id = 27646, name = "Thornwake Longbow", slot = "weapon", hands = 2},
				{id = 2500, name = "Thornwake Jerkin", slot = "body"},
				{id = 18406, name = "Thornwake Striders", slot = "feet"},
				{id = 28691, name = "Thornwake Loop", slot = "ring"}
			},
			bonuses = {
				{n = 2, stats = {movespeed = 4, lifeonkill = 40}},
				{n = 4, stats = {}, effect = "thornvolley"}
			},
			sources = {
				uniques = {minTier = "rare", chance = 3, monsters = {"Ancient Treant", "Mushroom King", "Mycelium Horror",
					"Elk Guardian", "Owlbear", "Dire Bear"}},
				rift = {theme = "Forsaken Sanctum", minTier = 1},
				dungeon = true
			}},

		-- ------------------------------------------------------------------ caster
		{key = "cinderstorm", name = "Cinderstorm Court", family = "caster", classes = "Elementalist, area Mystic",
			level = 400,
			lore = "Woven by the fire and frost queens' court mages, who never agreed on anything but the burning.",
			pieces = {
				{id = 27666, name = "Cinderstorm Wand", slot = "weapon"},
				{id = 29471, name = "Cinderstorm Crown", slot = "head"},
				{id = 7899, name = "Cinderstorm Mantle", slot = "body"},
				{id = 7894, name = "Cinderstorm Kilt", slot = "legs"},
				{id = 24637, name = "Cinderstorm Sandals", slot = "feet"},
				{id = 28041, name = "Cinderstorm Signet", slot = "ring"}
			},
			bonuses = {
				{n = 2, stats = {magic = 2, elepen = 6}},
				{n = 4, stats = {cdr = 6, manacost = 8}},
				{n = 6, stats = {deathblast = 15, ignitechance = 10}}
			},
			sources = {
				uniques = {minTier = "boss", chance = 8, bossOnly = true, monsters = {WORLD.kaelgor, WORLD.skaldra}},
				rift = {theme = "Abyssal Rift", minTier = 6}
			}},
		{key = "lichbound", name = "Lichbound Vestments", family = "caster", classes = "Lich, Necromancer, curse casters",
			level = 400,
			lore = "Found on the ninth landing of the Descent, still warm, still whispering the names of the burned.",
			pieces = {
				{id = 29573, name = "Lichbound Mask", slot = "head"},
				{id = 8890, name = "Lichbound Robe", slot = "body"},
				{id = 29575, name = "Lichbound Kilt", slot = "legs"},
				{id = 28126, name = "Lichbound Phylactery", slot = "necklace"}
			},
			bonuses = {
				{n = 2, stats = {magic = 2, dot = 15}},
				{n = 4, stats = {poisonchance = 10}, effect = "soulsiphon"}
			},
			sources = {descent = {minDepth = 8}}},

		-- ------------------------------------------------------------------ support
		{key = "mirrorweave", name = "Mirrorweave Raiment", family = "support", classes = "Illusionist, Iron Sage",
			level = 300,
			lore = "Every thread was spun twice, once for the wearer and once for the reflection that heals beside her.",
			pieces = {
				{id = 28111, name = "Mirrorweave Codex", slot = "shield"},
				{id = 28106, name = "Mirrorweave Circlet", slot = "head"},
				{id = 28107, name = "Mirrorweave Robe", slot = "body"},
				{id = 28108, name = "Mirrorweave Skirt", slot = "legs"},
				{id = 28109, name = "Mirrorweave Slippers", slot = "feet"},
				{id = 28125, name = "Mirrorweave Band", slot = "ring"}
			},
			bonuses = {
				{n = 2, stats = {healing = 6, magic = 1}},
				{n = 4, stats = {manacost = 8, maxmanapct = 5}},
				{n = 6, stats = {healing = 4}, effect = "mirrorgrace"}
			},
			sources = {
				uniques = {minTier = "boss", chance = 8, bossOnly = true, monsters = {WORLD.rotmother}},
				rift = {theme = "Forsaken Sanctum", minTier = 5}
			}},

		-- ------------------------------------------------------------------ hybrid
		{key = "duskstalker", name = "Duskstalker Garb", family = "hybrid", classes = "Ninja, Thief, Shadowfist (without the blades)",
			level = 300,
			lore = "The Void Archon's knife-hands wore it to walk between his heartbeats. Two blades, never one.",
			pieces = {
				{id = 7404, name = "Duskstalker Fang", slot = "weapon"},
				{id = 7418, name = "Duskstalker Sting", slot = "weapon"},
				{id = 28112, name = "Duskstalker Cowl", slot = "head"},
				{id = 11301, name = "Duskstalker Jerkin", slot = "body"},
				{id = 11304, name = "Duskstalker Breeches", slot = "legs"},
				{id = 27249, name = "Duskstalker Tabi", slot = "feet"}
			},
			bonuses = {
				{n = 2, stats = {dodge = 4, movespeed = 4}},
				{n = 4, stats = {poisonchance = 12, dot = 10}},
				{n = 6, stats = {}, effect = "umbralrecoil"}
			},
			sources = {
				uniques = {minTier = "boss", chance = 8, bossOnly = true, monsters = {WORLD.nyxareth}},
				rift = {theme = "Abyssal Rift", minTier = 4},
				dungeon = true
			}},
		{key = "hollowpack", name = "Hollowpack Covenant", family = "hybrid", classes = "Beastmaster, Bone Lord, summoners",
			level = 250,
			lore = "A pact sealed in the Rotmother's den: the pack feeds the master, the master feeds the pack.",
			pieces = {
				{id = 24718, name = "Hollowpack Mask", slot = "head"},
				{id = 24741, name = "Hollowpack Hide", slot = "body"},
				{id = 2129, name = "Hollowpack Fang Chain", slot = "necklace"},
				{id = 26808, name = "Hollowpack Bond", slot = "ring"}
			},
			bonuses = {
				{n = 2, stats = {maxhealthpct = 4, regen = 20}},
				{n = 4, stats = {}, effect = "packbond"}
			},
			sources = {
				uniques = {minTier = "boss", chance = 8, bossOnly = true, monsters = {WORLD.rotmother}},
				rift = {theme = "Ashen Crypt", minTier = 4},
				dungeon = true
			}}
	}
}
