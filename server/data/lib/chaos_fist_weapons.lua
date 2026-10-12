-- The Monk line's fist weapons (server/tools/install_fist_weapons.py --lua, from server/data/items/fist_items.csv).
-- Generated; do not edit by hand. The items exist after the "fistweapons" install step and need the matching
-- client pair (client/tools/sprites/import_art_things.py with art_import/fist_weapons.csv).
-- ids: the server ids (the same list as ChaosMonk.cfg.unarmed.fistWeapons); items[id]: key, name, attack,
-- defense, level; loot: {monster, item id, chance per 100000} added to the monster types at startup
-- (data/scripts/chaos/fist_weapons.lua).

ChaosFistWeapons = {
	ids = {36654, 36655, 36656, 36657, 36658, 36659},
	items = {
		[36654] = {key = "fist_t1", name = "pair of charred hand wraps", attack = 42, defense = 4, level = 8},
		[36655] = {key = "fist_t2", name = "ashbound cestus", attack = 44, defense = 8, level = 60},
		[36656] = {key = "fist_t3", name = "pair of ember knuckles", attack = 46, defense = 12, level = 150},
		[36657] = {key = "fist_t4", name = "ossuary gauntlet", attack = 50, defense = 16, level = 300},
		[36658] = {key = "fist_t5", name = "pair of cinderforged talons", attack = 55, defense = 20, level = 500},
		[36659] = {key = "fist_pyre", name = "pyre saint's grasp", attack = 62, defense = 22, level = 650, unique = "Grasp of the Pyre Saint"},
	},
	loot = {
		{"Monk", 36654, 900},
		{"Dark Monk", 36654, 700},
		{"Undead Gladiator", 36655, 400},
		{"Renegade Knight", 36655, 300},
		{"Burning Gladiator", 36656, 350},
		{"Hellfire Fighter", 36656, 300},
		{"Bonecleaver", 36657, 250},
		{"Doombone", 36657, 250},
		{"Bonelich", 36657, 250},
		{"Grimbone", 36657, 250},
		{"Bonecrusher", 36657, 250},
		{"Inferno Juggernaut", 36658, 150},
		{"Nightflare Dreadknight", 36658, 150},
		{"Orclops Ravager", 36658, 120},
		{"Grindmaw the Mauler", 36658, 150},
	}
}
