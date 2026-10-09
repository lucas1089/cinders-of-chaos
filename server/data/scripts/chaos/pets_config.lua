-- Pets: every number and every species (pets.lua, pets_core.lua, tests/pets_test.lua). Loaded with
--     ChaosPetsConfig = dofile("data/scripts/chaos/pets_config.lua")
-- The engine also loads this file as a script because it lives under data/scripts; it only returns a table.
-- Overview: server/README.md "Pets". Lua 5.1 / LuaJIT and Lua 5.3 compatible; no engine calls.
--
-- A pet is a small non-combat companion: one out at a time, it follows its owner, levels from the owner's kills and has
-- two small abilities (one from level 1, one from level `secondAt`). It cannot be attacked, takes no damage, never
-- attacks, and does not count against the class companions (Beastmaster wolves, Necromancer minions keep their own caps).

return {
	-- ------------------------------------------------------------------ levels
	maxLevel = 50,
	-- pet XP from level L to L + 1 = floor(curve.base * L ^ curve.power)
	-- (L1: 8, L10: 200, L25: 724, L49: 1,859; 736 XP to level 10, 7,180 to 25, 38,871 to 50 = about 45 hours of
	-- hunting at 700 counted kills an hour with a few tiered kills)
	curve = {base = 8, power = 1.4},
	-- XP per kill of the owner while the pet is out (a monster that gives the owner experience, not a summon):
	-- 1, plus the tier bonus. A kill counts only if the monster's base experience is at least the owner's level x
	-- minExpPerLevel (tiered monsters and bosses always count), so farming trivial monsters gives nothing.
	xp = {perKill = 1, tier = {magic = 1, rare = 3, legendary = 7, boss = 10}, minExpPerLevel = 2},
	-- a second copy of a species the character already owns (drop, achievement) becomes pet XP for that pet
	duplicateXp = 400,

	-- ------------------------------------------------------------------ rules
	summonCooldown = 5, -- seconds between summon / dismiss / switching pets
	deathCooldown = 60, -- seconds: the owner died, the pet fled home and cannot be summoned before this
	renameCooldown = 30, -- seconds between renames
	name = {min = 2, max = 16}, -- letters and single spaces, starts and ends with a letter
	thinkMs = 500, -- the follow / leash / ability tick
	leashRange = 6, -- farther (or another floor): the pet is put next to its owner
	-- no anti-block: a pet is passable (flag in its monster type, engine patch in server/src-patches), so players and
	-- monsters walk through it and it never stands in anyone's way
	-- the pet only exists next to its owner outside protection zones; it waits (despawned) while the owner is in one and
	-- comes back when the owner leaves (also after a teleport too far for the engine, which removes summons)
	-- hide: how a pet that rests (protection zone, banned zone, other summons) shows: it is removed with a
	-- puff and put back next to its owner when the reason ends; its XP and abilities wait meanwhile (utility abilities
	-- keep working while it rests, combat abilities do not)
	-- other summons: a pet rests while its owner has a summon that is not a class companion (Call Thrall, Moonfang Pack),
	-- so the stock two-summon limit and Moonfang's cap of four are never reduced by a pet. Class companions are read at
	-- run time (Chaos.classes.companion.monsters, ChaosNecroConfig.minions); these names are added to them:
	classSummons = {"War Wolf", "Risen Skeleton", "Lich Shade", "Bone Golem"},

	-- where pets may go: "banned" = sent home and cannot be summoned there; "utility" = out, but only the utility
	-- abilities (gold find, item find, fetch) work; anything else = everything works
	zones = {
		arena = "banned", -- ranked PvP arena (ChaosArena.isInside)
		siege = "banned", -- guild siege (ChaosSiege.isInside)
		pvpZone = "banned", -- PvP-zone tiles of the map
		rift = "utility", -- rifts keep their own leaderboard: no heal, ward or aura inside
		worldBoss = "utility", -- world boss arena and lobby (damage / healing / tank boards)
		tower = "utility", -- Infinity Tower runs
		dungeon = "utility" -- dungeons (speed and flawless rankings)
	},
	-- in PvP combat (ChaosHealing.inPvp: recent player damage, a fight lock, an arena or siege match) the combat abilities
	-- (heal, ward, aura) pause; the aura never hits players or their summons anyway

	-- ------------------------------------------------------------------ abilities (pet level L = 1..50)
	-- value = base + perLevel x (L - 1); cooldowns in seconds
	abilities = {
		mend = {name = "Mend", kind = "combat", base = 4, perLevel = 0.08, cooldown = 30, below = 50,
			desc = "Heals you for %s%% of your maximum health when you fall below half health."},
		ward = {name = "Ward", kind = "combat", base = 6, perLevel = 0.12, cooldown = 45, below = 60, duration = 6,
			desc = "Below 60%% health: %s%% less damage from monsters for 6 seconds."},
		-- damage per pulse to up to `targets` monsters next to the pet (never players or summons):
		-- owner level x levelFactor + L x petFactor, +/- spread (owner 300 / pet 50: ~275 every 2 s; owner 1000 / pet 50: ~450)
		aura = {name = "Spark Aura", kind = "combat", levelFactor = 0.25, petFactor = 4, interval = 2, targets = 3, spread = 0.2,
			desc = "Every 2 seconds, hits up to 3 monsters next to the pet for about %s damage of its element."},
		goldFind = {name = "Gold Sniffer", kind = "utility", base = 2, perLevel = 0.1,
			desc = "+%s%% gold coins in the corpses of your kills."},
		itemFind = {name = "Treasure Sense", kind = "utility", base = 1, perLevel = 0.1,
			desc = "+%s%% item find (extra rolls, rarity, uniques)."},
		fetch = {name = "Fetch", kind = "utility", base = 3, perLevel = 0.05,
			desc = "Carries the gold coins of your kills within %s squares straight to your bank."}
	},
	secondAt = 20, -- the second ability of every species unlocks at this pet level

	-- ------------------------------------------------------------------ species
	-- key: stable id (stored in chaos_pets.species; never rename a live one). monster: the pet's monster type
	-- (data/monster/monsters/chaos/pets/*.xml; the look is the monster's, listed here for the window). element: the aura's.
	-- source: how it is obtained (drop = {chance = 1 / N per kill, monsters = names or nil for any monster,
	-- tierMult = extra factor for tiered kills}; a drop from any monster needs a kill that counts for pet XP (see `xp`),
	-- a drop from listed monsters needs only a kill that gives the owner experience; store = the store unlock key (shop_config.lua "Pets");
	-- achievement = the achievement id (achievements_data.lua), account-wide like achievements)
	species = {
		{key = "ember_whelp", name = "Ember Whelp", monster = "Ember Whelp", look = 272, element = "fire",
			abilities = {"aura", "ward"},
			source = {drop = {chance = 1 / 2500, monsters = {"dragon", "dragon lord", "dragon hatchling", "dragon lord hatchling"}}},
			how = "Rare drop from dragons (1 in 2,500 kills)."},
		{key = "frost_whelp", name = "Frost Whelp", monster = "Frost Whelp", look = 283, element = "ice",
			abilities = {"ward", "aura"},
			source = {drop = {chance = 1 / 2500, monsters = {"frost dragon", "frost dragon hatchling", "ice dragon", "elite ice dragon"}}},
			how = "Rare drop from frost dragons (1 in 2,500 kills)."},
		{key = "duskwing", name = "Duskwing", monster = "Duskwing", look = 122, element = "death",
			abilities = {"fetch", "goldFind"},
			source = {drop = {chance = 1 / 20000, tierMult = {magic = 2, rare = 4, legendary = 8, boss = 10}}},
			how = "Very rare drop from any monster (1 in 20,000 kills; more often from magic, rare and legendary ones)."},
		{key = "lantern_wisp", name = "Lantern Wisp", monster = "Lantern Wisp", look = 294, element = "holy",
			abilities = {"mend", "ward"},
			source = {store = "petLanternWisp"},
			how = "Store (Pets): 400 Chaos Coins."},
		{key = "hoarder_squirrel", name = "Hoarder Squirrel", monster = "Hoarder Squirrel", look = 274, element = "earth",
			abilities = {"goldFind", "itemFind"},
			source = {store = "petHoarderSquirrel"},
			how = "Store (Pets): 400 Chaos Coins."},
		{key = "ash_cat", name = "Ash Cat", monster = "Ash Cat", look = 276, element = "fire",
			abilities = {"fetch", "mend"},
			source = {achievement = "bounty_25"},
			how = "Achievement: Hired Blade (complete 25 bounty contracts)."},
		{key = "gilded_goblin", name = "Gilded Goblin", monster = "Gilded Goblin", look = 61, element = "physical",
			abilities = {"goldFind", "fetch"},
			source = {achievement = "goblin_10"},
			how = "Achievement: Greed Is Good (slay 10 Treasure Goblins)."},
		{key = "riftling", name = "Riftling", monster = "Riftling", look = 232, element = "death",
			abilities = {"itemFind", "aura"},
			source = {achievement = "rift_t5"},
			how = "Achievement: Deeper Wounds (seal a tier 5 rift)."}
	},

	-- store unlocks (shop_config.lua category "Pets"; the offer's unlock key -> species)
	store = {petLanternWisp = "lantern_wisp", petHoarderSquirrel = "hoarder_squirrel"},

	staffAccess = true, -- /pet give|xp|level|reset for characters with an access group
	tables = {pets = "chaos_pets"}
}
