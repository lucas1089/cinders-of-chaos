-- Infinite arrows and quivers: every number (data/lib/chaos_archery_core.lua reads it; server/README.md "Infinite
-- arrows and quivers"). Plain table, loaded with  ChaosArcheryConfig = dofile("data/lib/chaos_archery_config.lua").
-- server/tools/patch_base_archery.py reads the same file (launchers, bands, quivers, ammo) with regular expressions, so
-- keep one entry per line where the tool expects it and no Lua expressions in those tables. Lua 5.1 / LuaJIT and 5.3.
--
-- Bows and crossbows fire without ammunition. The engine's distance weapon formula (weapons.cpp WeaponDistance) adds
-- the ammunition's attack to the bow's; with no ammunition the bow's own attack is all there is. So the install tool
-- gives every launcher the attack, the hit chance and the missile of the ammunition its level band used to fire
-- (`bands`): the damage of a launcher with the typical ammunition of its band is unchanged. Arrows and bolts are gone
-- from the game (loot, shops, quest rewards, conjure spells); what players still own is turned into gold.

return {
	-- player storages 7101100 - 7101109 (server/README.md "Storage keys"): +0 the one-time ammunition sweep of the
	-- character (inventory, depots, inbox) is done, +1 the stash part of it is done
	storage = 7101100,

	-- ------------------------------------------------------------------ launchers
	-- every bow and crossbow of the base items: [server id] = {kind, level}. kind "bow" fired arrows, "crossbow" bolts.
	-- level = the weapons.xml required level; launchers without one and an attack of 4 or more count as level 100 (the
	-- reward and set bows of the late game). A two-handed distance weapon missing here counts as a bow of its required
	-- level, or a crossbow when its name holds one of `crossbowWords` (the install tool prints it). The launchers that
	-- are looks of the transmog sets are left out on purpose: only the transmog files may name a set look by id
	-- (tests/transmog_test.lua). Their weapons.xml levels and names give the same band and kind.
	launchers = {
		[2455] = {"crossbow", 0}, [2456] = {"bow", 0}, [5803] = {"crossbow", 75}, [7438] = {"bow", 0},
		[8849] = {"crossbow", 45}, [8850] = {"crossbow", 60}, [8851] = {"crossbow", 130}, [8852] = {"crossbow", 100},
		[8853] = {"crossbow", 80}, [8854] = {"bow", 80}, [8855] = {"bow", 50}, [8856] = {"bow", 60}, [8857] = {"bow", 40},
		[8858] = {"bow", 70}, [10295] = {"bow", 0}, [13873] = {"bow", 40}, [15643] = {"bow", 85},
		[15644] = {"crossbow", 50}, [16111] = {"crossbow", 150}, [18453] = {"crossbow", 90}, [18454] = {"bow", 105},
		[21690] = {"crossbow", 70}, [22416] = {"bow", 75}, [22417] = {"bow", 150}, [22418] = {"bow", 250},
		[22419] = {"crossbow", 75}, [22420] = {"crossbow", 150}, [22421] = {"crossbow", 250}, [25522] = {"bow", 120},
		[25523] = {"crossbow", 120}, [25885] = {"bow", 100}, [25886] = {"crossbow", 100}, [25943] = {"bow", 100},
		[25944] = {"bow", 100}, [25945] = {"bow", 100}, [25946] = {"bow", 100}, [25947] = {"crossbow", 100},
		[25948] = {"crossbow", 100}, [25949] = {"crossbow", 100}, [25950] = {"crossbow", 100}, [25983] = {"bow", 100},
		[25984] = {"bow", 100}, [25985] = {"bow", 100}, [25986] = {"bow", 100}, [25987] = {"crossbow", 100},
		[25988] = {"crossbow", 100}, [25989] = {"crossbow", 100}, [25990] = {"crossbow", 100}, [26758] = {"bow", 100},
		[26765] = {"bow", 100}, [27199] = {"bow", 300}, [27212] = {"crossbow", 220}, [27230] = {"bow", 220},
		[27383] = {"bow", 400}, [27384] = {"crossbow", 400}, [27471] = {"bow", 600}, [27473] = {"crossbow", 600},
		[27474] = {"crossbow", 600}, [27646] = {"bow", 150}, [27661] = {"bow", 250}, [27685] = {"crossbow", 300},
		[28051] = {"crossbow", 100}, [28052] = {"bow", 100}, [28116] = {"bow", 300}, [28131] = {"bow", 330},
		[28137] = {"crossbow", 330}, [28377] = {"bow", 350}, [28378] = {"crossbow", 350}, [28713] = {"bow", 220},
		[28715] = {"crossbow", 220}, [29477] = {"bow", 300}, [29479] = {"crossbow", 300}, [29480] = {"crossbow", 300},
		[29874] = {"bow", 1000}, [29875] = {"crossbow", 1000}
	},

	crossbowWords = {"crossbow", "bolter", "arbalest", "piercer"},

	-- the ammunition a launcher of a level band used to fire: the best one an NPC sold for that level (the items.xml
	-- values of the base ammunition). {from level, added attack, hit chance %, missile}. The launcher's new attack is its
	-- own + `attack`, its hit chance `hit` + its own hit bonus (the engine added the bow's hit chance to the
	-- ammunition's), at most 100. The missile is an items.xml shootType.
	-- The level 0 launchers (bow, crossbow) are the only ones up to level 40 / 45, so their band is what characters of
	-- levels 1-39 fired on average: arrows (25) to 19, sniper arrows (28) to 29, tarsal arrows (33) to 39 make 29;
	-- bolts (30) to 29, piercing bolts (33) to 39, vortex bolts (36) to 44 make 32 (server/data/spells/README.md
	-- "Infinite arrows").
	bands = {
		bow = {
			{0, 29, 93, "arrow"}, -- arrow, sniper and tarsal arrows (levels 1-39)
			{20, 29, 95, "sniperarrow"}, -- sniper arrow (no launcher of the base needs a level from 20 to 39)
			{30, 33, 94, "tarsalarrow"}, -- tarsal arrow
			{40, 38, 94, "onyxarrow"}, -- onyx arrow
			{90, 65, 95, "crystallinearrow"} -- crystalline arrow (every launcher of level 90 and up)
		},
		crossbow = {
			{0, 32, 87, "bolt"}, -- bolt, piercing and vortex bolts (levels 1-44)
			{30, 33, 87, "piercingbolt"}, -- piercing bolt
			{40, 36, 89, "vortexbolt"}, -- vortex bolt
			{55, 40, 91, "powerbolt"}, -- power bolt
			{70, 56, 90, "drillbolt"}, -- drill bolt
			{90, 66, 90, "prismaticbolt"} -- prismatic bolt
		}
	},
	-- a launcher whose name holds one of these words shoots the elemental missile instead of its band's
	missileByName = {
		{"water", "waterarrow", "waterbolt"},
		{"arcane", "arcanearrow", "arcanebolt"},
		{"icicle", "shiverarrow", "bolt"}
	},

	-- ------------------------------------------------------------------ quivers
	-- the base quivers become equipment of the ammunition slot (no longer containers): [server id] = {level, implicit}.
	-- level = the required level (movements.xml) and the band the Gambler offers it from; implicit = the base's own
	-- modifiers (keys of the item modifier catalogue, under its caps), active like every quiver modifier only while
	-- the wearer holds a bow or crossbow. The stock hunter's quiver (12425) stays a decoration: it is stackable in the
	-- client's data, which an item of the ammunition slot must not be.
	quivers = {
		[28693] = {20, {bowspeed = 2}},
		[27651] = {50, {bowdistance = 2}},
		[27694] = {80, {bowcrit = 3}},
		[27696] = {120, {multishot = 5}},
		[27663] = {150, {arrowenergy = 8}},
		[27686] = {200, {arrowearth = 8}},
		[27676] = {250, {bowcrit = 5, bowdistance = 2}},
		[28379] = {300, {arrowice = 10}},
		[27695] = {350, {arrowfire = 12}},
		[29566] = {400, {bowdistance = 3, bowspeed = 4}},
		[28050] = {500, {multishot = 10, bowcrit = 4}},
		[29873] = {1000, {bowdistance = 4, multishot = 8, bowspeed = 5}}
	},
	-- the quiver's own modifiers in the item catalogue (chaos_item_mods.lua), quivers only. Same fields as there.
	mods = {
		{key = "bowdistance", label = "Distance Fighting", fmt = "flat", side = "prefix", weight = 8, cap = 12,
			tiers = {{1, 1}, {1, 2}, {2, 3}, {2, 4}, {3, 5}, {4, 6}, {5, 7}, {6, 8}}},
		{key = "bowcrit", label = "Critical Strike Chance with Bows", fmt = "pct", side = "prefix", weight = 7, cap = 20,
			tiers = {{1, 2}, {2, 3}, {3, 4}, {4, 5}, {5, 6}, {6, 7}, {7, 8}, {8, 10}}},
		{key = "multishot", label = "Extra Projectile Chance", fmt = "pct", side = "prefix", weight = 6, cap = 30,
			tiers = {{2, 4}, {3, 5}, {4, 7}, {6, 9}, {7, 11}, {9, 13}, {11, 16}, {14, 20}}},
		{key = "arrowfire", label = "Fire Damage with Bows", text = "Adds %d%% of Bow Damage as Fire", side = "prefix",
			weight = 3, cap = 40, tiers = {{2, 4}, {4, 6}, {6, 9}, {8, 12}, {10, 15}, {13, 19}, {16, 23}, {20, 28}}},
		{key = "arrowice", label = "Ice Damage with Bows", text = "Adds %d%% of Bow Damage as Ice", side = "prefix",
			weight = 3, cap = 40, tiers = {{2, 4}, {4, 6}, {6, 9}, {8, 12}, {10, 15}, {13, 19}, {16, 23}, {20, 28}}},
		{key = "arrowenergy", label = "Energy Damage with Bows", text = "Adds %d%% of Bow Damage as Energy",
			side = "prefix", weight = 3, cap = 40,
			tiers = {{2, 4}, {4, 6}, {6, 9}, {8, 12}, {10, 15}, {13, 19}, {16, 23}, {20, 28}}},
		{key = "arrowearth", label = "Earth Damage with Bows", text = "Adds %d%% of Bow Damage as Earth",
			side = "prefix", weight = 3, cap = 40,
			tiers = {{2, 4}, {4, 6}, {6, 9}, {8, 12}, {10, 15}, {13, 19}, {16, 23}, {20, 28}}},
		{key = "bowspeed", label = "Attack Speed with Bows", fmt = "pct", side = "suffix", weight = 8, cap = 12,
			tiers = {{1, 2}, {2, 3}, {3, 4}, {4, 5}, {5, 6}, {6, 8}, {7, 9}, {8, 10}}}
	},
	-- modifiers of the catalogue that quivers may roll as well (their numbers and caps stay the catalogue's)
	sharedMods = {"bossdamage", "physpen", "elepen", "lifeonhit", "manaonhit", "lifeonkill", "manaonkill", "bleedchance",
		"poisonchance"},

	-- what the quiver modifiers do (weapon_styles.lua, on a bow or crossbow hit)
	effects = {
		critDamage = 50, -- a Critical Strike with Bows deals +50%
		multishotShare = 60, -- an extra projectile deals 60% of the hit
		multishotRange = 3, -- to another monster this close to the target (the target itself when there is none)
		conditionSubId = 7101100 -- the Distance Fighting condition of the quiver (a sub id of its own)
	},

	-- ------------------------------------------------------------------ the ammunition that goes
	-- every arrow and bolt (items.xml weaponType "ammunition", ammoType arrow or bolt): [server id] = gold per piece paid
	-- back. No NPC buys ammunition, so the refund is half the cheapest NPC price (hunt_supplies.lua); ammunition no NPC
	-- sold (simple arrow, burst arrow, spectral bolt) and the infernal bolt (300,000 gold, a placeholder price) are
	-- priced like the ammunition of their level. Any other arrow or bolt pays `defaultRefund`.
	ammo = {
		[2543] = 1, [2544] = 1, [2545] = 9, [2546] = 3, [2547] = 3, [6529] = 10, [7363] = 2, [7364] = 2, [7365] = 3,
		[7838] = 2, [7839] = 2, [7840] = 2, [7850] = 2, [15648] = 3, [15649] = 3, [18304] = 10, [18435] = 10,
		[18436] = 6, [18437] = 6, [23839] = 1, [27641] = 9, [28140] = 10, [29491] = 11, [29492] = 11, [29493] = 11,
		[29494] = 11
	},
	defaultRefund = 1,
	-- the conjure spells that made ammunition (data/spells/scripts/conjuring/), switched off by the install tool
	conjureScripts = {"arrow_call.lua", "conjure_arrow.lua", "conjure_bolt.lua", "conjure_diamond_arrow.lua",
		"conjure_explosive_arrow.lua", "conjure_piercing_bolt.lua", "conjure_poisoned_arrow.lua",
		"conjure_power_bolt.lua", "conjure_sniper_arrow.lua", "spectral_bolt.lua"}
}
