-- exclusives_config.lua: the visual exclusives that are never sold, only earned (exclusives.lua, exclusives_core.lua,
-- server/tests/exclusives_test.lua). Plain table, loaded with
--     ChaosExclusivesConfig = dofile("data/scripts/chaos/exclusives_config.lua")
-- No engine calls here. Overview: server/README.md "Exclusives".
--
-- Every visual kind of the store has options here that only an achievement or a boss gives: outfits, outfit addons,
-- mounts, wings, auras, outfit shaders, name plate frames, plus the boss drops of kinds that keep their own catalogue
-- (portal styles, transmog sets, pets, footprints and outlines). Unlocks are account-wide (table chaos_exclusives) and
-- not tradeable: nothing is an item, a drop is a direct unlock for the account of the player who rolled it.
--
-- An exclusive: {key, kind, name, desc, icon, source, ...}
--   key      stable text, unique ([%w_], 40 at most; stored in chaos_exclusives.exclusive)
--   icon     server item id drawn in the wardrobe's Collection tab (a picture only)
--   source   "achievement": achievements_data.lua names it in one achievement's reward.exclusives (key and shown name);
--            the account owns it once any character has that achievement (also for older unlocks)
--            "boss": one group of `bosses` below lists it; a rare personal roll at that boss's kill
-- Kinds and their fields (every look is existing art of the client pair, sold nowhere; exclusives_test.lua checks the
-- store, the generated store list and the other reward sources):
--   outfit   male, female        look types (outfits.xml via server/tools/install_outfits.py, block "Chaos exclusive
--                                outfits", locked); both looks with both addons
--   addons   male, female        the two addons of an outfit everyone has (the store sells no addons of it)
--   mount    id, look            mounts.xml id (install_outfits.py MOUNTS) and its client look type
--   wings    id, look            wings.xml id (install_outfits.py WINGS) and its client look type
--   aura     id, look            auras.xml id (install_auras.py, data/XML/chaos_auras_exclusive.csv) and its look type
--   shader   id, shader          shaders.xml id and name (install_outfits.py SHADERS; client game_chaosshaders)
--   frame    frame               a name plate frame (shop_core.lua FRAMES, nameplate_core.lua N.FRAMES)
--   portal   style               a Town Portal style of townportal_config.lua with route "boss"
--   transmog set                 a transmog set of transmog_config.lua with source "boss"
--   pet      species             a pet of pets_config.lua with source.boss
--   cosmetic cosmetic            a footprint / outline (any cosmetic) of cosmetics_config.lua with source "boss"
-- Where it is chosen, for the window: `use` of the kind in KINDS below.

return {
	table = "chaos_exclusives", -- one row per account and exclusive (server/sql/chaos_exclusives.sql)
	staffGroup = 4, -- /exclusive <character>, <key | all>[, revoke] and /exclusive <character>, roll <kill key>

	-- the window's name of each kind and where it is chosen
	kinds = {
		{key = "outfit", name = "Outfit", use = "Choose it in the Outfit window."},
		{key = "addons", name = "Outfit Addons", use = "Choose them in the Outfit window."},
		{key = "mount", name = "Mount", use = "Choose it in the Outfit window."},
		{key = "wings", name = "Wings", use = "Choose them in the Outfit window."},
		{key = "aura", name = "Aura", use = "Choose it in the Outfit window."},
		{key = "shader", name = "Outfit Shader", use = "Choose it in the Outfit window."},
		{key = "frame", name = "Name Plate Frame", use = "Switch it in Info & Services > Services > Plate frame."},
		{key = "portal", name = "Portal Style", use = "Choose it in Character > Portal Style."},
		{key = "transmog", name = "Transmog Set", use = "Use its looks in Character > Transmog."},
		{key = "pet", name = "Pet", use = "Call it in Character > Pets."},
		{key = "cosmetic", name = "Cosmetic", use = "Choose it in its tab of this window."}
	},

	-- world boss name (lower case, a part of it is enough) -> kill key (worldboss.lua passes the boss's name)
	worldBosses = {kaelgor = "wb_kaelgor", skaldra = "wb_skaldra", rotmother = "wb_rotmother", nyxareth = "wb_nyxareth",
		vharok = "wb_vharok"},

	-- boss groups: kills = the kill keys that roll this group (worldboss.lua "wb_<boss>", raid.lua "raid_<boss key>",
	-- uber.lua "ascended_<kind>" / "cinder", guildboss.lua "guild_<boss key>"); chance = per eligible player and kill
	-- (the players that get the boss's normal rewards: personal loot, every one rolls on its own); a hit gives one of
	-- `rewards` the account does not own yet (none left: nothing). name = the window's "Boss: <name>".
	bosses = {
		{key = "kaelgor", name = "Kaelgor the Infernal Warlord", kills = {"wb_kaelgor"}, chance = 0.02,
			rewards = {"tm_hellforged"}},
		{key = "skaldra", name = "Skaldra the Rime Queen", kills = {"wb_skaldra"}, chance = 0.02,
			rewards = {"mount_rimebone", "foot_rime", "portal_drowned"}},
		{key = "rotmother", name = "The Rotmother", kills = {"wb_rotmother"}, chance = 0.02,
			rewards = {"outfit_mirewarden", "pet_rotling"}},
		{key = "nyxareth", name = "Nyxareth the Void Archon", kills = {"wb_nyxareth"}, chance = 0.02,
			rewards = {"mount_gloomwyrm", "glow_corona", "tm_inferniarch"}},
		{key = "vharok", name = "Vharok the Blood Colossus", kills = {"wb_vharok"}, chance = 0.02,
			rewards = {"mount_bloodwing"}},
		{key = "sepulchre", name = "the Ashen Sepulchre's wardens (first four bosses)", chance = 0.015,
			kills = {"raid_ulthar", "raid_morwen", "raid_colossus", "raid_hexmaw"},
			rewards = {"aura_scarlet", "pet_spiderling", "frame_sepulchre"}},
		{key = "sovereign", name = "Varkhul the Ashen Sovereign", kills = {"raid_sovereign"}, chance = 0.03,
			rewards = {"outfit_ashseraph", "tm_deathlord", "portal_seraph"}},
		{key = "ascended", name = "the Ascended Omens", kills = {"ascended_bloodmoon", "ascended_hollow", "ascended_storm"},
			chance = 0.03, rewards = {"outfit_omenlancer", "shader_cinderspark", "foot_omen"}},
		{key = "cinderheart", name = "Ysgrath the Cinderheart", kills = {"cinder"}, chance = 0.05,
			rewards = {"wings_cinderplumes", "tm_eldritch", "frame_infernal", "glow_cinder"}},
		{key = "gorvath", name = "Gorvath the Banner-Eater (guild boss)", kills = {"guild_gorvath"}, chance = 0.02,
			rewards = {"mount_bannerdrake", "addons_knight"}}
	},

	exclusives = {
		-- ------------------------------------------------------------------ outfits (base looks no outfits.xml line had)
		{key = "outfit_wingbound", kind = "outfit", male = 1455, female = 1456, icon = 2498, source = "achievement",
			name = "Wingbound", desc = "Plate with folded bat wings and a lance of blue steel."},
		{key = "outfit_jadeforged", kind = "outfit", male = 1039, female = 1040, icon = 2155, source = "achievement",
			name = "Jadeforged", desc = "Green scale plate of a master artificer."},
		{key = "outfit_ashseraph", kind = "outfit", male = 1459, female = 1459, icon = 2131, source = "boss",
			name = "Ashen Seraph", desc = "The winged black plate of Varkhul's honour guard."},
		{key = "outfit_omenlancer", kind = "outfit", male = 1457, female = 1458, icon = 6500, source = "boss",
			name = "Omen Lancer", desc = "A hooded lancer who walked out of a broken omen."},
		{key = "outfit_mirewarden", kind = "outfit", male = 1464, female = 1465, icon = 2149, source = "boss",
			name = "Mirewarden", desc = "Swamp-stained armour of the plague pits' wardens."},

		-- ------------------------------------------------------------------ outfit addons (outfits everyone has)
		{key = "addons_mage", kind = "addons", male = 130, female = 138, icon = 2190, source = "achievement",
			name = "Mage", desc = "Both addons of the Mage outfit, male and female look."},
		{key = "addons_knight", kind = "addons", male = 131, female = 139, icon = 2496, source = "boss",
			name = "Knight", desc = "Both addons of the Knight outfit, male and female look."},

		-- ------------------------------------------------------------------ mounts (base looks no mounts.xml line had)
		{key = "mount_tuskhide", kind = "mount", id = 146, look = 1323, icon = 2401, source = "achievement",
			name = "Tuskhide Boar", desc = "A shaggy war boar that never flinches."},
		{key = "mount_duskcrest", kind = "mount", id = 147, look = 428, icon = 2153, source = "achievement",
			name = "Duskcrest Drake", desc = "A violet drake with a burning crest."},
		{key = "mount_rimebone", kind = "mount", id = 148, look = 1444, icon = 2146, source = "boss",
			name = "Rimebone Stalker", desc = "A beast of ice and bone from the Rime Queen's court."},
		{key = "mount_bloodwing", kind = "mount", id = 149, look = 1441, icon = 9020, source = "boss",
			name = "Bloodwing Fiend", desc = "A bat-winged fiend that drank the Colossus's blood."},
		{key = "mount_bannerdrake", kind = "mount", id = 150, look = 596, icon = 1436, source = "boss",
			name = "Bannerdrake", desc = "A blue war drake that carried Gorvath's stolen banners."},
		{key = "mount_gloomwyrm", kind = "mount", id = 151, look = 1450, icon = 6500, source = "boss",
			name = "Gloomwyrm", desc = "A wyrm of the void with tattered shadow wings."},

		-- ------------------------------------------------------------------ wings, auras, shaders
		{key = "wings_cinderplumes", kind = "wings", id = 16, look = 1486, icon = 2353, source = "boss",
			name = "Cinder Plumes", desc = "Wings of ember-tipped feathers from the Cinderheart's pyre."},
		-- achievement wings: donor-library looks 2140..2142 of things_custom17 (picks.csv rows wings_*, client/MANIFEST.md)
		{key = "wings_bloodthorn", kind = "wings", id = 17, look = 2140, icon = 2363, source = "achievement",
			name = "Bloodthorn Pinions", desc = "Thorned black wings veined with the blood of the five colossi."},
		{key = "wings_gravecrow", kind = "wings", id = 18, look = 2141, icon = 7433, source = "achievement",
			name = "Gravecrow Wings", desc = "Grave-black raven wings, a skull mask on each. They never kneel."},
		{key = "wings_riftglass", kind = "wings", id = 19, look = 2142, icon = 2192, source = "achievement",
			name = "Riftglass Wings", desc = "Violet crystal wings that splinter and grow back with every seal."},
		{key = "aura_murmuration", kind = "aura", id = 29, look = 1487, icon = 2229, source = "achievement",
			name = "Ashen Murmuration", desc = "A flock of black birds circles you at the witching hour."},
		{key = "aura_scarlet", kind = "aura", id = 30, look = 712, icon = 2156, source = "boss",
			name = "Scarlet Glimmer", desc = "Red and white glints flicker round you."},
		{key = "shader_verdant", kind = "shader", id = 16, shader = "green_pixent", icon = 2149, source = "achievement",
			name = "Verdant Sparks", desc = "Green sparks dance on your outfit."},
		{key = "shader_cinderspark", kind = "shader", id = 18, shader = "ember_pixent", icon = 2187, source = "boss",
			name = "Cinder Sparks", desc = "Embers dance on your outfit."},

		-- ------------------------------------------------------------------ name plate frames (gen_nameplate_art.py)
		{key = "frame_laurel", kind = "frame", frame = "laurel", icon = 2155, source = "achievement",
			name = "Laurel", desc = "A green-gold laurel frame round your name plate."},
		{key = "frame_sepulchre", kind = "frame", frame = "sepulchre", icon = 2230, source = "boss",
			name = "Sepulchre", desc = "Grave-ash iron with violet rivets round your name plate."},
		{key = "frame_infernal", kind = "frame", frame = "infernal", icon = 2353, source = "boss",
			name = "Infernal", desc = "A frame of molten iron round your name plate."},

		-- ------------------------------------------------------------------ boss drops of the other catalogues
		{key = "portal_drowned", kind = "portal", style = "drowned", icon = 29638, source = "boss",
			name = "Drowned Gate", desc = "Town Portal style: a gate of black water rimmed with frost."},
		{key = "portal_seraph", kind = "portal", style = "seraph", icon = 29639, source = "boss",
			name = "Seraph's Door", desc = "Town Portal style: a radiant door guarded by stone wings."},
		{key = "tm_hellforged", kind = "transmog", set = "hellforged", icon = 29469, source = "boss",
			name = "Hellforged Visage", desc = "Transmog looks: a maliceforged helmet, a demonfang mask and molten plate."},
		{key = "tm_inferniarch", kind = "transmog", set = "inferniarch", icon = 29486, source = "boss",
			name = "Inferniarch Arms", desc = "Transmog looks: the void-touched inferniarch blade, axe, mace, bow and wand."},
		{key = "tm_deathlord", kind = "transmog", set = "deathlord", icon = 29558, source = "boss",
			name = "Deathlord Arms", desc = "Transmog looks: the Deathlord's cleaver, mace and blade."},
		{key = "tm_eldritch", kind = "transmog", set = "eldritch", icon = 27655, source = "boss",
			name = "Gilded Eldritch Arms", desc = "Transmog looks: a gilded claymore, warmace, greataxe, bow and rod."},
		{key = "pet_rotling", kind = "pet", species = "rotling", icon = 2149, source = "boss",
			name = "Rotling", desc = "A green ooze that crawled out of the plague pits after you."},
		{key = "pet_spiderling", kind = "pet", species = "ashweaver", icon = 2230, source = "boss",
			name = "Ashweaver Spiderling", desc = "A small spider that spins ash in the Sepulchre's corners."},
		{key = "foot_rime", kind = "cosmetic", cosmetic = "foot_rime", icon = 2146, source = "boss",
			name = "Rimewalker", desc = "Footprints: frost crystals bloom in your steps."},
		{key = "foot_omen", kind = "cosmetic", cosmetic = "foot_omen", icon = 6500, source = "boss",
			name = "Omen Ash", desc = "Footprints: violet ash drifts behind you."},
		{key = "glow_corona", kind = "cosmetic", cosmetic = "glow_corona", icon = 2153, source = "boss",
			name = "Void Corona", desc = "Outline: a black corona with a violet rim."},
		{key = "glow_cinder", kind = "cosmetic", cosmetic = "glow_cinder", icon = 2353, source = "boss",
			name = "Cinderheart Blaze", desc = "Outline: the Cinderheart's own fire flares round you."}
	}
}
