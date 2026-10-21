-- Chaos unique items: global ChaosUniqueItems consumed by data/scripts/chaos/loot.lua (contract: LOOT.md).
-- Each unique is a normal copy of a base item that gets its own name, description and stats as item attributes when
-- it is created (ChaosMakeUnique below, data in chaos_unique_specs.lua generated from data/items/chaos_items.xml).
-- items.xml is NOT changed: stock monsters, shops and scripts find items by their stock names.
-- chance = per 10000 per kill BEFORE the tier multiplier in loot_config.lua (magic x1, rare x2, legendary x4, boss x6;
-- normal-tier kills never drop uniques). So chance 8 on a legendary monster = 32 per 10000 = 0.32%.
-- The boss-only entries also list the five world bosses (worldboss.lua): corpse drop through loot.lua, and the same
-- pool is used for the world boss participation reward (Chaos.worldBoss.reward.uniqueChance).
-- season = <id>: a season unique (season_config.lua): during that season it drops only for that season's characters,
-- before it for nobody, after it for everyone (season.lua ChaosSeason.uniqueBlocked, asked by loot.lua).
-- Edit freely, it is plain Lua.

ChaosUniqueItems = {
	{ name = "Nightfang Katana", id = 2412, minTier = "magic", chance = 4, level = 60, slot = "sword",
	  bossOnly = false, monsters = {"Phantom Shade", "Shadowgeist", "Nightdweller", "Abyssal Shadowfiend", "Lost Soul", "Nightstalker", "Death Mage", "Lich", "Vampire", "Banshee", "Ghoul", "Grim Reaper", "Undead Dragon", "Demon Skeleton", "Betrayed Wraith", "Blightwalker"} },
	{ name = "Lichfang Staff", id = 3961, minTier = "magic", chance = 4, level = 70, slot = "club",
	  bossOnly = false, monsters = {"Warlock", "Lich", "Dark Torturer", "Infernalist", "Necromancer", "Priestess", "Death Mage", "Vampire", "Banshee", "Ghoul", "Grim Reaper", "Undead Dragon", "Demon Skeleton", "Betrayed Wraith", "Blightwalker"} },
	{ name = "Bonelord's Gaze", id = 3972, minTier = "magic", chance = 4, level = 60, slot = "head",
	  bossOnly = false, monsters = {"Bonelord", "Elder Bonelord", "Skeleton Warrior", "Demon Skeleton", "Lich", "Undead Gladiator", "Crypt Shambler", "Warlock", "Dark Torturer", "Infernalist", "Necromancer", "Priestess", "Death Mage"} },
	{ name = "Gallowsbolt Crossbow", id = 8849, minTier = "magic", chance = 4, level = 60, slot = "distance",
	  bossOnly = false, monsters = {"Bonelord", "Elder Bonelord", "Skeleton Warrior", "Demon Skeleton", "Lich", "Undead Gladiator", "Crypt Shambler", "Juggernaut", "Behemoth", "Minotaur", "Orc Warlord", "Destroyer", "Dragon Lord", "Hand of Cursed Fate"} },
	{ name = "Pall of Skulls", id = 10296, minTier = "magic", chance = 4, level = 60, slot = "body",
	  bossOnly = false, monsters = {"Bonelord", "Elder Bonelord", "Skeleton Warrior", "Demon Skeleton", "Lich", "Undead Gladiator", "Crypt Shambler", "Vampire", "Banshee", "Ghoul", "Grim Reaper", "Undead Dragon", "Betrayed Wraith", "Blightwalker"} },
	{ name = "Carrion Scarab Amulet", id = 11374, minTier = "magic", chance = 6, level = 50, slot = "necklace",
	  bossOnly = false, monsters = {"Lich", "Vampire", "Banshee", "Ghoul", "Grim Reaper", "Undead Dragon", "Demon Skeleton", "Betrayed Wraith", "Blightwalker", "Bonelord", "Elder Bonelord", "Skeleton Warrior", "Undead Gladiator", "Crypt Shambler"} },
	{ name = "Hellspear of the Damned", id = 19390, minTier = "magic", chance = 6, level = 50, slot = "distance",
	  bossOnly = false, monsters = {"Demon", "Hellhound", "Fire Devil", "Hellfire Fighter", "Diabolic Imp", "Hellspawn", "Defiler", "Destroyer", "Massive Fire Elemental", "Dragon Lord", "Blazebringer"} },
	{ name = "Hornbinder Ring", id = 21693, minTier = "magic", chance = 6, level = 60, slot = "ring",
	  bossOnly = false, monsters = {"Juggernaut", "Behemoth", "Minotaur", "Orc Warlord", "Destroyer", "Dragon Lord", "Hand of Cursed Fate", "Demon", "Hellhound", "Fire Devil", "Hellfire Fighter", "Diabolic Imp", "Hellspawn", "Defiler"} },
	{ name = "Widowmaker", id = 22690, minTier = "magic", chance = 6, level = 40, slot = "sword", season = 1,
	  bossOnly = false, monsters = {"Phantom Shade", "Shadowgeist", "Nightdweller", "Abyssal Shadowfiend", "Lost Soul", "Nightstalker", "Death Mage", "Bonelord", "Elder Bonelord", "Skeleton Warrior", "Demon Skeleton", "Lich", "Undead Gladiator", "Crypt Shambler"} },
	{ name = "Ring of the Last Ember", id = 41640, minTier = "rare", chance = 5, level = 70, slot = "ring",
	  bossOnly = false, monsters = {"Hellfire Fighter", "Fire Devil", "Massive Fire Elemental", "Hellhound", "Dragon Lord", "Blazebringer", "Phantom Shade", "Shadowgeist", "Nightdweller", "Abyssal Shadowfiend", "Lost Soul", "Nightstalker", "Death Mage"} },
	{ name = "Executioner's Reckoning", id = 2440, minTier = "rare", chance = 5, level = 80, slot = "axe",
	  bossOnly = false, monsters = {"Juggernaut", "Behemoth", "Minotaur", "Orc Warlord", "Destroyer", "Dragon Lord", "Hand of Cursed Fate", "Demon", "Hellhound", "Fire Devil", "Hellfire Fighter", "Diabolic Imp", "Hellspawn", "Defiler"} },
	{ name = "Hornsworn Helm", id = 2496, minTier = "rare", chance = 5, level = 70, slot = "head",
	  bossOnly = false, monsters = {"Demon", "Hellhound", "Fire Devil", "Hellfire Fighter", "Diabolic Imp", "Hellspawn", "Defiler", "Destroyer", "Juggernaut", "Behemoth", "Minotaur", "Orc Warlord", "Dragon Lord", "Hand of Cursed Fate"}, set = "embers" },
	{ name = "Emberwarden", id = 3975, minTier = "rare", chance = 5, level = 90, slot = "shield",
	  bossOnly = false, monsters = {"Hellfire Fighter", "Fire Devil", "Massive Fire Elemental", "Hellhound", "Dragon Lord", "Blazebringer", "Demon", "Diabolic Imp", "Hellspawn", "Defiler", "Destroyer"}, set = "embers" },
	{ name = "Bonegrinder", id = 7379, minTier = "rare", chance = 6, level = 90, slot = "club",
	  bossOnly = false, monsters = {"Bonelord", "Elder Bonelord", "Skeleton Warrior", "Demon Skeleton", "Lich", "Undead Gladiator", "Crypt Shambler", "Juggernaut", "Behemoth", "Minotaur", "Orc Warlord", "Destroyer", "Dragon Lord", "Hand of Cursed Fate"} },
	{ name = "Cindermail Coat", id = 8892, minTier = "rare", chance = 5, level = 80, slot = "body",
	  bossOnly = false, monsters = {"Hellfire Fighter", "Fire Devil", "Massive Fire Elemental", "Hellhound", "Dragon Lord", "Blazebringer", "Demon", "Diabolic Imp", "Hellspawn", "Defiler", "Destroyer"}, set = "embers" },
	{ name = "Heart of Cinders", id = 41641, minTier = "rare", chance = 5, level = 80, slot = "necklace",
	  bossOnly = false, monsters = {"Hellfire Fighter", "Fire Devil", "Massive Fire Elemental", "Hellhound", "Dragon Lord", "Blazebringer", "Demon", "Diabolic Imp", "Hellspawn", "Defiler", "Destroyer"} },
	{ name = "Heartbleed Pendant", id = 41642, minTier = "rare", chance = 5, level = 90, slot = "necklace",
	  bossOnly = false, monsters = {"Demon", "Hellhound", "Fire Devil", "Hellfire Fighter", "Diabolic Imp", "Hellspawn", "Defiler", "Destroyer", "Lich", "Vampire", "Banshee", "Ghoul", "Grim Reaper", "Undead Dragon", "Demon Skeleton", "Betrayed Wraith", "Blightwalker"} },
	{ name = "Cinderclaw Band", id = 10314, minTier = "rare", chance = 5, level = 80, slot = "ring",
	  bossOnly = false, monsters = {"Hellfire Fighter", "Fire Devil", "Massive Fire Elemental", "Hellhound", "Dragon Lord", "Blazebringer", "Demon", "Diabolic Imp", "Hellspawn", "Defiler", "Destroyer"}, set = "embers" },
	{ name = "Widow's Last Vow", id = 10510, minTier = "rare", chance = 4, level = 90, slot = "ring",
	  bossOnly = false, monsters = {"Lich", "Vampire", "Banshee", "Ghoul", "Grim Reaper", "Undead Dragon", "Demon Skeleton", "Betrayed Wraith", "Blightwalker", "Phantom Shade", "Shadowgeist", "Nightdweller", "Abyssal Shadowfiend", "Lost Soul", "Nightstalker", "Death Mage"} },
	{ name = "Bloodmoon Edge", id = 11395, minTier = "rare", chance = 6, level = 90, slot = "sword",
	  bossOnly = false, monsters = {"Demon", "Hellhound", "Fire Devil", "Hellfire Fighter", "Diabolic Imp", "Hellspawn", "Defiler", "Destroyer", "Juggernaut", "Behemoth", "Minotaur", "Orc Warlord", "Dragon Lord", "Hand of Cursed Fate"} },
	{ name = "Gorecleaver", id = 11426, minTier = "rare", chance = 5, level = 70, slot = "sword",
	  bossOnly = false, monsters = {"Juggernaut", "Behemoth", "Minotaur", "Orc Warlord", "Destroyer", "Dragon Lord", "Hand of Cursed Fate", "Lich", "Vampire", "Banshee", "Ghoul", "Grim Reaper", "Undead Dragon", "Demon Skeleton", "Betrayed Wraith", "Blightwalker"} },
	{ name = "Riftcaller", id = 13760, minTier = "rare", chance = 5, level = 80, slot = "wand", season = 1,
	  bossOnly = false, monsters = {"Warlock", "Lich", "Dark Torturer", "Infernalist", "Necromancer", "Priestess", "Death Mage", "Phantom Shade", "Shadowgeist", "Nightdweller", "Abyssal Shadowfiend", "Lost Soul", "Nightstalker"} },
	{ name = "Hellspite Arbalest", id = 16111, minTier = "rare", chance = 5, level = 100, slot = "distance", season = 1,
	  bossOnly = false, monsters = {"Demon", "Hellhound", "Fire Devil", "Hellfire Fighter", "Diabolic Imp", "Hellspawn", "Defiler", "Destroyer", "Massive Fire Elemental", "Dragon Lord", "Blazebringer"} },
	{ name = "Tome of Whispers", id = 22474, minTier = "rare", chance = 4, level = 100, slot = "shield",
	  bossOnly = false, monsters = {"Warlock", "Lich", "Dark Torturer", "Infernalist", "Necromancer", "Priestess", "Death Mage", "Phantom Shade", "Shadowgeist", "Nightdweller", "Abyssal Shadowfiend", "Lost Soul", "Nightstalker"} },
	{ name = "Gorehammer", id = 23590, minTier = "rare", chance = 5, level = 100, slot = "club",
	  bossOnly = false, monsters = {"Juggernaut", "Behemoth", "Minotaur", "Orc Warlord", "Destroyer", "Dragon Lord", "Hand of Cursed Fate", "Demon", "Hellhound", "Fire Devil", "Hellfire Fighter", "Diabolic Imp", "Hellspawn", "Defiler"} },
	{ name = "Shroud of the Hollow Wood", id = 27228, minTier = "rare", chance = 4, level = 90, slot = "body",
	  bossOnly = false, monsters = {"Phantom Shade", "Shadowgeist", "Nightdweller", "Abyssal Shadowfiend", "Lost Soul", "Nightstalker", "Death Mage", "Warlock", "Lich", "Dark Torturer", "Infernalist", "Necromancer", "Priestess"} },
	{ name = "Mortis Cowl", id = 27231, minTier = "rare", chance = 5, level = 100, slot = "head", season = 1,
	  bossOnly = false, monsters = {"Phantom Shade", "Shadowgeist", "Nightdweller", "Abyssal Shadowfiend", "Lost Soul", "Nightstalker", "Death Mage", "Lich", "Vampire", "Banshee", "Ghoul", "Grim Reaper", "Undead Dragon", "Demon Skeleton", "Betrayed Wraith", "Blightwalker"} },
	{ name = "Maw Treads", id = 27288, minTier = "rare", chance = 5, level = 70, slot = "feet",
	  bossOnly = false, monsters = {"Demon", "Hellhound", "Fire Devil", "Hellfire Fighter", "Diabolic Imp", "Hellspawn", "Defiler", "Destroyer", "Bonelord", "Elder Bonelord", "Skeleton Warrior", "Demon Skeleton", "Lich", "Undead Gladiator", "Crypt Shambler"} },
	{ name = "Wraithplate", id = 27295, minTier = "rare", chance = 5, level = 100, slot = "body",
	  bossOnly = false, monsters = {"Phantom Shade", "Shadowgeist", "Nightdweller", "Abyssal Shadowfiend", "Lost Soul", "Nightstalker", "Death Mage", "Lich", "Vampire", "Banshee", "Ghoul", "Grim Reaper", "Undead Dragon", "Demon Skeleton", "Betrayed Wraith", "Blightwalker"} },
	{ name = "Bloodstep Boots", id = 27647, minTier = "rare", chance = 5, level = 80, slot = "feet",
	  bossOnly = false, monsters = {"Hellfire Fighter", "Fire Devil", "Massive Fire Elemental", "Hellhound", "Dragon Lord", "Blazebringer", "Juggernaut", "Behemoth", "Minotaur", "Orc Warlord", "Destroyer", "Hand of Cursed Fate"}, set = "embers" },
	{ name = "Emberveil Greaves", id = 27692, minTier = "rare", chance = 5, level = 80, slot = "legs",
	  bossOnly = false, monsters = {"Hellfire Fighter", "Fire Devil", "Massive Fire Elemental", "Hellhound", "Dragon Lord", "Blazebringer", "Demon", "Diabolic Imp", "Hellspawn", "Defiler", "Destroyer"}, set = "embers" },
	{ name = "Nightshade Leggings", id = 27693, minTier = "rare", chance = 5, level = 90, slot = "legs",
	  bossOnly = false, monsters = {"Phantom Shade", "Shadowgeist", "Nightdweller", "Abyssal Shadowfiend", "Lost Soul", "Nightstalker", "Death Mage", "Warlock", "Lich", "Dark Torturer", "Infernalist", "Necromancer", "Priestess"} },
	{ name = "Crown of Cinders", id = 7462, minTier = "legendary", chance = 8, level = 100, slot = "head",
	  bossOnly = false, monsters = {"Hellfire Fighter", "Fire Devil", "Massive Fire Elemental", "Hellhound", "Dragon Lord", "Blazebringer", "Juggernaut", "Behemoth", "Minotaur", "Orc Warlord", "Destroyer", "Hand of Cursed Fate"} },
	{ name = "Soulreaper", id = 8209, minTier = "legendary", chance = 9, level = 120, slot = "sword",
	  bossOnly = false, monsters = {"Demon", "Hellhound", "Fire Devil", "Hellfire Fighter", "Diabolic Imp", "Hellspawn", "Defiler", "Destroyer", "Lich", "Vampire", "Banshee", "Ghoul", "Grim Reaper", "Undead Dragon", "Demon Skeleton", "Betrayed Wraith", "Blightwalker"} },
	{ name = "Harvester of Sorrows", id = 10301, minTier = "legendary", chance = 8, level = 100, slot = "axe",
	  bossOnly = false, monsters = {"Lich", "Vampire", "Banshee", "Ghoul", "Grim Reaper", "Undead Dragon", "Demon Skeleton", "Betrayed Wraith", "Blightwalker", "Phantom Shade", "Shadowgeist", "Nightdweller", "Abyssal Shadowfiend", "Lost Soul", "Nightstalker", "Death Mage"} },
	{ name = "Obsidian Aegis", id = 10318, minTier = "legendary", chance = 8, level = 110, slot = "shield",
	  bossOnly = false, monsters = {"Demon", "Hellhound", "Fire Devil", "Hellfire Fighter", "Diabolic Imp", "Hellspawn", "Defiler", "Destroyer", "Juggernaut", "Behemoth", "Minotaur", "Orc Warlord", "Dragon Lord", "Hand of Cursed Fate"} },
	{ name = "Tear of the Void", id = 24851, minTier = "legendary", chance = 7, level = 100, slot = "necklace",
	  bossOnly = false, monsters = {"Phantom Shade", "Shadowgeist", "Nightdweller", "Abyssal Shadowfiend", "Lost Soul", "Nightstalker", "Death Mage", "Warlock", "Lich", "Dark Torturer", "Infernalist", "Necromancer", "Priestess"} },
	{ name = "Mawmaker", id = 25418, minTier = "legendary", chance = 8, level = 110, slot = "club",
	  bossOnly = false, monsters = {"Demon", "Hellhound", "Fire Devil", "Hellfire Fighter", "Diabolic Imp", "Hellspawn", "Defiler", "Destroyer", "Juggernaut", "Behemoth", "Minotaur", "Orc Warlord", "Dragon Lord", "Hand of Cursed Fate"} },
	{ name = "Voidwalker Boots", id = 26133, minTier = "legendary", chance = 7, level = 100, slot = "feet",
	  bossOnly = false, monsters = {"Phantom Shade", "Shadowgeist", "Nightdweller", "Abyssal Shadowfiend", "Lost Soul", "Nightstalker", "Death Mage", "Demon", "Hellhound", "Fire Devil", "Hellfire Fighter", "Diabolic Imp", "Hellspawn", "Defiler", "Destroyer"} },
	{ name = "Doomtide Longbow", id = 27230, minTier = "legendary", chance = 8, level = 110, slot = "distance",
	  bossOnly = false, monsters = {"Lich", "Vampire", "Banshee", "Ghoul", "Grim Reaper", "Undead Dragon", "Demon Skeleton", "Betrayed Wraith", "Blightwalker", "Phantom Shade", "Shadowgeist", "Nightdweller", "Abyssal Shadowfiend", "Lost Soul", "Nightstalker", "Death Mage"} },
	{ name = "Mortis Shroud", id = 27232, minTier = "legendary", chance = 7, level = 110, slot = "body",
	  bossOnly = false, monsters = {"Warlock", "Lich", "Dark Torturer", "Infernalist", "Necromancer", "Priestess", "Death Mage", "Vampire", "Banshee", "Ghoul", "Grim Reaper", "Undead Dragon", "Demon Skeleton", "Betrayed Wraith", "Blightwalker"} },
	{ name = "Voidscale Legguards", id = 28020, minTier = "legendary", chance = 7, level = 130, slot = "legs",
	  bossOnly = false, monsters = {"Demon", "Hellhound", "Fire Devil", "Hellfire Fighter", "Diabolic Imp", "Hellspawn", "Defiler", "Destroyer", "Bonelord", "Elder Bonelord", "Skeleton Warrior", "Demon Skeleton", "Lich", "Undead Gladiator", "Crypt Shambler"} },
	{ name = "Soulshackle Scepter", id = 29571, minTier = "legendary", chance = 7, level = 120, slot = "wand",
	  bossOnly = false, monsters = {"Warlock", "Lich", "Dark Torturer", "Infernalist", "Necromancer", "Priestess", "Death Mage", "Vampire", "Banshee", "Ghoul", "Grim Reaper", "Undead Dragon", "Demon Skeleton", "Betrayed Wraith", "Blightwalker"} },
	-- the Monk's legendary fist weapon: its base item (36659, "pyre saint's grasp") is a fist weapon of its own
	-- (server/tools/install_fist_weapons.py); it is in no shop and no loot table, so it is only ever found as this unique
	{ name = "Grasp of the Pyre Saint", id = 36659, minTier = "legendary", chance = 8, level = 650, slot = "fist",
	  bossOnly = false, monsters = {"Inferno Juggernaut", "Nightflare Dreadknight", "Orclops Ravager", "Grindmaw the Mauler", "Royal Man", "Grove Keeper", "Garack", "Dreamgorger"} },
	{ name = "Cinderbrand Axe", id = 8925, minTier = "boss", chance = 20, level = 130, slot = "axe",
	  bossOnly = true, monsters = {"Moloveth", "Vharagoth", "Morgashal", "Vhalkareth", "Ghorzuul", "Ashvoran", "The Spawnmother",
	    "Kaelgor the Infernal Warlord", "Skaldra the Rime Queen", "The Rotmother", "Nyxareth the Void Archon", "Vharok the Blood Colossus"} },
	{ name = "Fangs of the Ninth Circle", id = 24790, minTier = "boss", chance = 20, level = 120, slot = "necklace",
	  bossOnly = true, monsters = {"Moloveth", "Vharagoth", "Morgashal", "Vhalkareth", "Ghorzuul", "Ashvoran", "The Spawnmother",
	    "Kaelgor the Infernal Warlord", "Skaldra the Rime Queen", "The Rotmother", "Nyxareth the Void Archon", "Vharok the Blood Colossus"} },
	{ name = "Visage of the Pale King", id = 27675, minTier = "boss", chance = 20, level = 120, slot = "head",
	  bossOnly = true, monsters = {"Moloveth", "Vharagoth", "Morgashal", "Vhalkareth", "Ghorzuul", "Ashvoran", "The Spawnmother",
	    "Kaelgor the Infernal Warlord", "Skaldra the Rime Queen", "The Rotmother", "Nyxareth the Void Archon", "Vharok the Blood Colossus"} },
	{ name = "Duskweaver Wand", id = 29866, minTier = "boss", chance = 20, level = 140, slot = "wand",
	  bossOnly = true, monsters = {"Moloveth", "Vharagoth", "Morgashal", "Vhalkareth", "Ghorzuul", "Ashvoran", "The Spawnmother",
	    "Kaelgor the Infernal Warlord", "Skaldra the Rime Queen", "The Rotmother", "Nyxareth the Void Archon", "Vharok the Blood Colossus"} },
	{ name = "Veil of the Wraith", id = 29868, minTier = "boss", chance = 20, level = 120, slot = "ring",
	  bossOnly = true, monsters = {"Moloveth", "Vharagoth", "Morgashal", "Vhalkareth", "Ghorzuul", "Ashvoran", "The Spawnmother",
	    "Kaelgor the Infernal Warlord", "Skaldra the Rime Queen", "The Rotmother", "Nyxareth the Void Archon", "Vharok the Blood Colossus"} },
	-- the build archetype uniques (docs/BUILDS.md): each strengthens one archetype keystone (archetypes.lua reads the
	-- spec's `archetype` on the worn copy); Knuckles of the Unbound and Stormcaller Recurve also work without it
	{ name = "Pyreheart Mantle", id = 8881, minTier = "legendary", chance = 7, level = 150, slot = "body",
	  bossOnly = false, monsters = {"Hellfire Fighter", "Fire Devil", "Massive Fire Elemental", "Hellhound", "Dragon Lord", "Blazebringer", "Demon", "Diabolic Imp", "Hellspawn", "Defiler", "Destroyer"} },
	{ name = "Vein of the Unsated", id = 27652, minTier = "rare", chance = 5, level = 180, slot = "necklace",
	  bossOnly = false, monsters = {"Lich", "Vampire", "Banshee", "Ghoul", "Grim Reaper", "Undead Dragon", "Demon Skeleton", "Betrayed Wraith", "Blightwalker", "Juggernaut", "Behemoth", "Minotaur", "Orc Warlord", "Destroyer"} },
	{ name = "Spitethorn Bulwark", id = 15413, minTier = "legendary", chance = 7, level = 130, slot = "shield",
	  bossOnly = false, monsters = {"Juggernaut", "Behemoth", "Minotaur", "Orc Warlord", "Destroyer", "Dragon Lord", "Hand of Cursed Fate", "Demon", "Hellhound", "Fire Devil", "Hellfire Fighter"} },
	{ name = "Knuckles of the Unbound", id = 28023, minTier = "legendary", chance = 7, level = 400, slot = "ring",
	  bossOnly = false, monsters = {"Inferno Juggernaut", "Nightflare Dreadknight", "Orclops Ravager", "Grindmaw the Mauler", "Royal Man", "Grove Keeper", "Garack", "Dreamgorger"} },
	{ name = "Rotbloom Phial", id = 21691, minTier = "rare", chance = 5, level = 150, slot = "necklace",
	  bossOnly = false, monsters = {"Phantom Shade", "Shadowgeist", "Nightdweller", "Abyssal Shadowfiend", "Lost Soul", "Nightstalker", "Death Mage", "Bonelord", "Elder Bonelord", "Crypt Shambler"} },
	{ name = "Splintered Instant", id = 28049, minTier = "legendary", chance = 7, level = 400, slot = "ring",
	  bossOnly = false, monsters = {"Inferno Juggernaut", "Nightflare Dreadknight", "Orclops Ravager", "Grindmaw the Mauler", "Royal Man", "Grove Keeper", "Garack", "Dreamgorger"} },
	{ name = "Stormcaller Recurve", id = 8858, minTier = "rare", chance = 5, level = 70, slot = "distance",
	  bossOnly = false, monsters = {"Juggernaut", "Behemoth", "Minotaur", "Orc Warlord", "Destroyer", "Dragon Lord", "Hand of Cursed Fate", "Demon", "Hellhound", "Fire Devil", "Hellfire Fighter"} },
	{ name = "Shard of the Long Winter", id = 26756, minTier = "rare", chance = 5, level = 100, slot = "wand",
	  bossOnly = false, monsters = {"Warlock", "Lich", "Dark Torturer", "Infernalist", "Necromancer", "Priestess", "Death Mage", "Phantom Shade", "Shadowgeist", "Nightdweller"} },
	{ name = "Effigy Carver's Idol", id = 22423, minTier = "rare", chance = 5, level = 120, slot = "shield",
	  bossOnly = false, monsters = {"Warlock", "Lich", "Dark Torturer", "Infernalist", "Necromancer", "Priestess", "Death Mage", "Phantom Shade", "Shadowgeist", "Nightdweller"} },
	{ name = "Brand of the Ashen Choir", id = 18403, minTier = "rare", chance = 5, level = 150, slot = "head",
	  bossOnly = false, monsters = {"Hellfire Fighter", "Fire Devil", "Massive Fire Elemental", "Hellhound", "Dragon Lord", "Blazebringer", "Demon", "Diabolic Imp", "Hellspawn", "Defiler", "Destroyer"} },
	{ name = "Aetherbound Plate", id = 2466, minTier = "rare", chance = 5, level = 120, slot = "body",
	  bossOnly = false, monsters = {"Phantom Shade", "Shadowgeist", "Nightdweller", "Abyssal Shadowfiend", "Lost Soul", "Nightstalker", "Death Mage", "Bonelord", "Elder Bonelord", "Crypt Shambler"} },
	{ name = "Reliquary Censer", id = 27251, minTier = "legendary", chance = 7, level = 220, slot = "necklace",
	  bossOnly = false, monsters = {"Lich", "Vampire", "Banshee", "Ghoul", "Grim Reaper", "Undead Dragon", "Demon Skeleton", "Betrayed Wraith", "Blightwalker", "Juggernaut", "Behemoth", "Minotaur", "Orc Warlord", "Destroyer"} },
	-- the second round (2026-10-12): snares, vigils, Hollow Vessel; the snare and diadem uniques work without a keystone
	{ name = "Snarewalker Greaves", id = 28115, minTier = "rare", chance = 5, level = 120, slot = "feet",
	  bossOnly = false, monsters = {"Phantom Shade", "Shadowgeist", "Nightdweller", "Abyssal Shadowfiend", "Lost Soul", "Nightstalker", "Death Mage", "Bonelord", "Elder Bonelord", "Crypt Shambler"} },
	{ name = "Fusewright's Charm", id = 7890, minTier = "rare", chance = 5, level = 150, slot = "necklace",
	  bossOnly = false, monsters = {"Hellfire Fighter", "Fire Devil", "Massive Fire Elemental", "Hellhound", "Dragon Lord", "Blazebringer", "Demon", "Diabolic Imp", "Hellspawn", "Defiler", "Destroyer"} },
	{ name = "Choirmaster's Circlet", id = 27667, minTier = "legendary", chance = 7, level = 200, slot = "head",
	  bossOnly = false, monsters = {"Warlock", "Lich", "Dark Torturer", "Infernalist", "Necromancer", "Priestess", "Death Mage", "Phantom Shade", "Shadowgeist", "Nightdweller"} },
	{ name = "Oathkeeper's Standard", id = 15453, minTier = "legendary", chance = 7, level = 180, slot = "shield",
	  bossOnly = false, monsters = {"Juggernaut", "Behemoth", "Minotaur", "Orc Warlord", "Destroyer", "Dragon Lord", "Hand of Cursed Fate", "Demon", "Hellhound", "Fire Devil", "Hellfire Fighter"} },
	{ name = "Hollowglass Diadem", id = 27668, minTier = "legendary", chance = 7, level = 250, slot = "head",
	  bossOnly = false, monsters = {"Lich", "Vampire", "Banshee", "Ghoul", "Grim Reaper", "Undead Dragon", "Demon Skeleton", "Betrayed Wraith", "Blightwalker", "Juggernaut", "Behemoth", "Minotaur", "Orc Warlord", "Destroyer"} },
	{ name = "Stillheart Robe", id = 27390, minTier = "legendary", chance = 7, level = 300, slot = "body",
	  bossOnly = false, monsters = {"Inferno Juggernaut", "Nightflare Dreadknight", "Orclops Ravager", "Grindmaw the Mauler", "Royal Man", "Grove Keeper", "Garack", "Dreamgorger"} },
	-- the Ascended uniques (uber.lua, server/README.md "Ascended Omens and the Cinderheart"): ascended = true keeps them
	-- out of the Omen chest pool (rift.lua); corpse drops of the listed bosses (x6 boss tier) and the spoils' unique rolls
	{ name = "Sanguine Crescent", id = 2408, minTier = "boss", chance = 10, level = 1000, slot = "sword",
	  bossOnly = true, ascended = true, monsters = {"Ascended Sangrith", "Ysgrath the Cinderheart"} },
	{ name = "Hollow Crown of Morvane", id = 2493, minTier = "boss", chance = 10, level = 1000, slot = "head",
	  bossOnly = true, ascended = true, monsters = {"Ascended Morvane", "Ysgrath the Cinderheart"} },
	{ name = "Eye of the Unbroken Storm", id = 2171, minTier = "boss", chance = 10, level = 1000, slot = "necklace",
	  bossOnly = true, ascended = true, monsters = {"Ascended Thalcyra", "Ysgrath the Cinderheart"} },
	{ name = "Cinderheart Signet", id = 2123, minTier = "boss", chance = 8, level = 1000, slot = "ring",
	  bossOnly = true, ascended = true, monsters = {"Ysgrath the Cinderheart"} },
}

-- name (and lower-case name) -> entry
ChaosUniqueByName = {}
-- server id -> entry
ChaosUniqueById = {}
for _, e in ipairs(ChaosUniqueItems) do
	ChaosUniqueByName[e.name] = e
	ChaosUniqueByName[e.name:lower()] = e
	ChaosUniqueById[e.id] = e
end

if not ChaosUniqueSpecs then
	dofile('data/lib/chaos_unique_specs.lua')
end

-- Turn a freshly created base item into its unique: name, article, description, attack/defense/armor... as item
-- attributes, skills/critical/leech/absorbs as the custom attributes the stock rarity scripts apply on equip.
-- Returns true when the item id has a unique spec.
function ChaosMakeUnique(item)
	local spec = item and ChaosUniqueSpecs[item:getId()]
	if not spec then
		return false
	end
	item:setAttribute(ITEM_ATTRIBUTE_NAME, spec.name)
	if spec.article ~= "" then
		item:setAttribute(ITEM_ATTRIBUTE_ARTICLE, spec.article)
	end
	item:setAttribute(ITEM_ATTRIBUTE_DESCRIPTION, spec.description)
	for key, value in pairs(spec.attributes) do
		item:setAttribute(key, value)
	end
	for key, value in pairs(spec.custom) do
		item:setCustomAttribute(key, value)
	end
	item:setCustomAttribute("chaos_unique", 1)
	if spec.set then
		item:setCustomAttribute("chaos_set", spec.set) -- a set piece (chaos_item_sets.lua)
	end
	return true
end

-- The uniques with an equip rule of their own (spec `equip`): data/lib/chaos_unique_equip.lua, called from the movement
-- script tools/install_unique_equip.py writes (server/README.md "Unique equip rules").
if not ChaosUniqueEquip then
	dofile('data/lib/chaos_unique_equip.lua')
end

-- Give one unique to a player (admin/quest/reward helper). Accepts the name (case-insensitive) or the server id.
-- Returns the Item, or nil + reason. Falls back to dropping on the floor if the backpack is full.
function ChaosGiveUnique(player, name)
	local e = type(name) == "number" and ChaosUniqueById[name] or ChaosUniqueByName[tostring(name)] or ChaosUniqueByName[tostring(name):lower()]
	if not e then
		return nil, "unknown unique: " .. tostring(name)
	end
	if not player or not player.addItem then
		return nil, "no player"
	end
	local item = player:addItem(e.id, 1, true)
	if not item then
		return nil, "could not create " .. e.name
	end
	ChaosMakeUnique(item)
	if player.sendTextMessage then
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE or MESSAGE_INFO_DESCR, "You received " .. e.name .. ".")
	end
	return item
end

-- ---------------------------------------------------------------------------
-- Item sets: data/lib/chaos_item_sets.lua (the sets, bonuses and sources: chaos_item_sets_config.lua; the game side:
-- data/scripts/chaos/itemsets.lua). Every set piece is a unique; the pieces with monster or world boss drops are
-- added to ChaosUniqueItems here (set = key), the raid, Descent, rift and dungeon pieces drop through their own rolls.
-- ChaosSets[key] = the set ({key, name, pieces = [{id, name, slot, hands, level}], bonuses, sources, ...}).
-- ---------------------------------------------------------------------------
dofile("data/lib/chaos_item_sets.lua")
ChaosItemSets.register(ChaosUniqueItems, ChaosUniqueByName, ChaosUniqueById)
ChaosSets = ChaosItemSets.byKey
