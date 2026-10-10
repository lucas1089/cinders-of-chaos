-- cosmetics_config.lua: the cosmetic kinds of cosmetics.lua (spell effect skins, kill effects, loot label accents, chat
-- name colours). Plain table, loaded with  ChaosCosmeticsConfig = dofile("data/scripts/chaos/cosmetics_config.lua")
-- No engine calls here (server/tests/cosmetics_test.lua reads it with plain Lua). See server/README.md "Cosmetics".
--
-- Cosmetic only, never power: a cosmetic changes a picture or a colour and nothing else (no damage, no area, no drop,
-- no timing). Unlocks are account-wide (table chaos_cosmetics); what a character shows is chosen per character
-- (storages below) in Character > Cosmetics (client game_cosmetics).
--
-- Every cosmetic: {id, key, kind, icon, name, desc, source, ...}
--   id       stable number, unique (the selection storages hold it); never reuse one
--   key      stable text, unique; the store offer is {kind = "unlock", unlock = "cosmetic_<key>"} (built by
--            cosmetics_store.lua into the store's cosmetic categories, see the Cosmetics hunk of shop_config.lua)
--   icon     server item id drawn for it in the store and the window (a picture only)
--   source   "store" (price = the store price; the offer must carry it) | "achievement" (owned once the account has
--            the achievement `achievement` of achievements_data.lua; granted at login and when the window opens)
-- Kinds:
--   spellskin  line = a key of `lines`; spells = spell ids of that line (2-3); swaps per effect type, default name ->
--              variant name, both in the same recolour family of `families` (the same picture in another colour, an
--              effect of the client pair): fx (chaos_fx.lua Fx names), missile (chaos_fx.lua FxMissile names), vfx
--              (chaos_vfx.lua Vfx names), vmissile (chaos_vfx.lua VfxShoot names). Only those spells and only those
--              effects change; a variant the server does not know falls back to the default effect.
--   killfx     vfx = a chaos_vfx.lua effect played on the monster's tile when the character lands the killing blow
--   lootbeam   accent = background of the character's own highlighted ground loot labels (client game_groundlabels);
--              the text and the border keep the rarity colour, the corpse loot rays keep their rarity colours
--   chatcolor  color = the colour of the character's own name in chat (every viewer); readable on the console

return {
	opcode = 225, -- ChaosOpcodes.cosmetics (client game_cosmetics)
	table = "chaos_cosmetics", -- one row per account and unlocked cosmetic (server/sql/chaos_cosmetics.sql)
	-- player storages, 7100940 - 7100949 reserved (chaos_constants.lua): the id of the chosen cosmetic per kind, and per
	-- class line for the spell skins (skinBase + line slot, slots 0..6); 0 / unset = the default
	storage = {killfx = 7100940, lootbeam = 7100941, chatcolor = 7100942, skinBase = 7100943},
	staffGroup = 4, -- /cosmetic <character>, <key | all>[, revoke]
	previewCooldownMs = 1500, -- a store / window preview (an effect only the asking player sees)
	consoleBackground = "#1c1a18", -- chat colours must stay readable on this (contrast 4.5 or more)
	labelRarityColors = { -- the rarity colours of the ground labels (client game_lootfilter); accents keep them readable
		"#c8c8c8", "#5ccf5c", "#4a90ff", "#a35cf0", "#ffd040", "#f5b13a", "#ff5a5a", "#e02424", "#ff8a70",
		"#c8e8ff", "#9ad8ff", "#e4f2ff", "#b878ff", "#9a4ce0", "#e070ff", "#e07b24"},

	kinds = {
		{key = "spellskin", name = "Spell Effects", store = "Spell Effects"},
		{key = "killfx", name = "Kill Effects", store = "Kill Effects"},
		{key = "lootbeam", name = "Loot Labels", store = "Loot Labels"},
		{key = "chatcolor", name = "Chat Name Colours", store = "Chat Colours"}
	},

	-- class lines (spell skins): slot = storage offset (skinBase + slot); the Necromancer line has no skins yet
	lines = {
		{key = "warrior", slot = 0, name = "Warrior line", vocations = {"Warrior", "Juggernaut", "Berserker"}},
		{key = "ranger", slot = 1, name = "Ranger line", vocations = {"Ranger", "Deadeye", "Beastmaster"}},
		{key = "mystic", slot = 2, name = "Mystic line", vocations = {"Mystic", "Elementalist", "Illusionist"}},
		{key = "thief", slot = 3, name = "Thief line", vocations = {"Thief", "Ninja", "Samurai"}},
		{key = "monk", slot = 4, name = "Monk line", vocations = {"Monk", "Shadowfist", "Iron Sage"}},
		{key = "templar", slot = 5, name = "Templar line", vocations = {"Templar", "Inquisitor", "Sentinel"}}
	},

	-- recolour families: the same picture in other colours, all in the client pair (effects_catalog.csv style, or the
	-- colour sets of vfx_catalog.csv). A swap stays inside one family.
	families = {
		fx = {
			nova = {"fire_nova", "frost_nova", "fire_ring", "blood_nova", "shadow_ring", "shockwave"},
			sparks = {"chain_lightning", "lightning_violet", "lightning_zap"},
			circle = {"blood_rune", "poison_pentagram", "arcane_circle"},
			aura = {"blood_ring", "poison_ring", "arcane_aura"},
			cloud = {"shadow_smoke", "poison_burst"},
			swirl = {"holy_spiral", "void_eye", "summon_portal", "summon_vortex"},
			burst = {"fire_explosion", "inferno_burst"},
			impact = {"fire_burst", "arcane_burst"},
			flame = {"shadow_flame", "poison_flame"}
		},
		missile = {
			orb = {"fire_bolt", "arcane_orb", "lightning_orb", "skull_orb"},
			bolt = {"fire_streak", "shadow_bolt"},
			arrow = {"holy_bolt", "blood_spear"}
		},
		vfx = {
			aura_burst = {"aura_burst_gold", "aura_burst_red", "aura_burst_violet", "aura_burst_god"},
			dome_blast = {"dome_blast_fire", "dome_blast_violet", "dome_blast_holy"},
			ki_hit = {"ki_hit_gold", "ki_hit_blue"},
			punch_hit = {"punch_hit_gold", "punch_hit_red", "punch_hit_violet"},
			vanish = {"shade_vanish", "blink_vanish"},
			appear = {"shade_appear", "blink_appear"},
			px03 = {"px03_arcane", "px03_ice"},
			px195 = {"px195_arcane", "px195_ice"},
			px448 = {"px448_crimson", "px448_green"},
			px586 = {"px586_fire", "px586_white"},
			px633 = {"px633_indigo", "px633_green"}
		},
		vmissile = {
			ki_blast = {"ki_blast_gold", "ki_blast_blue"}
		}
	},

	cosmetics = {
		-- ------------------------------------------------------------------ spell effect skins (store, 250)
		{id = 1, key = "skin_warrior_void", kind = "spellskin", icon = 7762, line = "warrior", source = "store", price = 250,
			name = "Voidborn War Cries", desc = "Iron Bellow, Red Frenzy and Bloodrage burst in violet; the bellow's rune turns arcane.",
			spells = {223, 222, 247}, vfx = {aura_burst_gold = "aura_burst_violet", aura_burst_red = "aura_burst_violet"},
			fx = {blood_rune = "arcane_circle"}},
		{id = 2, key = "skin_warrior_storm", kind = "spellskin", icon = 7759, line = "warrior", source = "store", price = 250,
			name = "Stormborn War Cries", desc = "Iron Bellow, Red Frenzy and Bloodrage burst in storm blue.",
			spells = {223, 222, 247}, vfx = {aura_burst_gold = "aura_burst_god", aura_burst_red = "aura_burst_god"}},
		{id = 3, key = "skin_ranger_sunfire", kind = "spellskin", icon = 2187, line = "ranger", source = "store", price = 250,
			name = "Sunfire Hunt", desc = "Skewering Line flies golden arrows, Feral Command fiery bolts, Wild Bond a storm vortex.",
			spells = {215, 249, 248}, missile = {blood_spear = "holy_bolt", shadow_bolt = "fire_streak"},
			fx = {summon_portal = "summon_vortex"}},
		{id = 4, key = "skin_mystic_voidfire", kind = "spellskin", icon = 2153, line = "mystic", source = "store", price = 250,
			name = "Voidfire", desc = "Doomtide, Forked Storm and Falling Pyre burn and crackle in violet.",
			spells = {206, 202, 204}, vfx = {dome_blast_fire = "dome_blast_violet"},
			fx = {fire_nova = "shadow_ring", chain_lightning = "lightning_violet"}},
		{id = 5, key = "skin_mystic_bloodfire", kind = "spellskin", icon = 7760, line = "mystic", source = "store", price = 250,
			name = "Bloodfire", desc = "Doomtide and Falling Pyre burn blood red.",
			spells = {206, 204}, fx = {fire_nova = "blood_nova", fire_explosion = "inferno_burst"}},
		{id = 6, key = "skin_thief_dawnstep", kind = "spellskin", icon = 2145, line = "thief", source = "store", price = 250,
			name = "Dawnstep", desc = "Shadow Veil, Shadow Step and Shadow Mend vanish in a pillar of light.",
			spells = {238, 240, 98}, vfx = {shade_vanish = "blink_vanish", shade_appear = "blink_appear"}},
		{id = 7, key = "skin_thief_venom", kind = "spellskin", icon = 7761, line = "thief", source = "store", price = 250,
			name = "Venom Smoke", desc = "Smoke Bomb and Shadow Mend leave a green, venomous smoke.",
			spells = {241, 98}, fx = {shadow_smoke = "poison_burst"}},
		{id = 8, key = "skin_monk_crimson", kind = "spellskin", icon = 2156, line = "monk", source = "store", price = 250,
			name = "Crimson Palms", desc = "Ashen Fist, Sundering Palm and Pressure Points strike in red.",
			spells = {63, 64, 68}, vfx = {punch_hit_gold = "punch_hit_red", punch_hit_violet = "punch_hit_red"},
			fx = {shockwave = "blood_nova"}},
		{id = 9, key = "skin_monk_void", kind = "spellskin", icon = 2150, line = "monk", source = "store", price = 250,
			name = "Void Palms", desc = "Ashen Fist, Sundering Palm and Pressure Points strike in violet.",
			spells = {63, 64, 68}, vfx = {punch_hit_gold = "punch_hit_violet", punch_hit_red = "punch_hit_violet"},
			fx = {shockwave = "shadow_ring"}},
		{id = 10, key = "skin_monk_gilded", kind = "spellskin", icon = 2154, line = "monk", source = "store", price = 250,
			name = "Gilded Palms", desc = "Sundering Palm, Pressure Points and Shadowfist Flurry strike in gold.",
			spells = {64, 68, 69}, vfx = {punch_hit_red = "punch_hit_gold", punch_hit_violet = "punch_hit_gold"}},
		{id = 11, key = "skin_templar_umbral", kind = "spellskin", icon = 18414, line = "templar", source = "store", price = 250,
			name = "Umbral Rite", desc = "Zealotry, Purging Nova and Vow of Mending glow in violet.",
			spells = {250, 199, 191}, vfx = {aura_burst_gold = "aura_burst_violet", dome_blast_holy = "dome_blast_violet"},
			fx = {holy_spiral = "void_eye"}},
		{id = 12, key = "skin_templar_pyre", kind = "spellskin", icon = 18420, line = "templar", source = "store", price = 250,
			name = "Pyre Rite", desc = "Zealotry and Purging Nova burn in red and fire.",
			spells = {250, 199}, vfx = {aura_burst_gold = "aura_burst_red", dome_blast_holy = "dome_blast_fire"}},

		-- ------------------------------------------------------------------ kill effects (store 200, two from achievements)
		{id = 101, key = "kill_soulspark", kind = "killfx", icon = 5944, source = "store", price = 200, vfx = "px633_indigo",
			name = "Soul Spark", desc = "A violet skull rises from the monster you finish."},
		{id = 102, key = "kill_sunring", kind = "killfx", icon = 2304, source = "store", price = 200, vfx = "px586_fire",
			name = "Sun Ring", desc = "A ring of fire flares where your killing blow lands."},
		{id = 103, key = "kill_shatter", kind = "killfx", icon = 2274, source = "store", price = 200, vfx = "ice_shatter",
			name = "Frost Shatter", desc = "Your kills shatter into shards of ice."},
		{id = 104, key = "kill_bloodbloom", kind = "killfx", icon = 9020, source = "store", price = 200, vfx = "px197_crimson",
			name = "Blood Bloom", desc = "A spiky burst of blood marks every kill."},
		{id = 105, key = "kill_radiant", kind = "killfx", icon = 10305, source = "store", price = 200, vfx = "px586_white",
			name = "Radiant Ring", desc = "A white sun ring shines over your kills."},
		{id = 106, key = "kill_voidring", kind = "killfx", icon = 6500, source = "achievement", achievement = "legendary_250",
			vfx = "px396_indigo", name = "Void Ring", desc = "A dark ring closes over your kills. Achievement: Legend's Bane."},
		{id = 107, key = "kill_harbinger", kind = "killfx", icon = 2229, source = "achievement", achievement = "tiered_1000",
			vfx = "px633_green", name = "Harbinger's Toll", desc = "A green skull tolls for your kills. Achievement: Chaos Culler."},

		-- ------------------------------------------------------------------ loot label accents (store 150, one achievement)
		{id = 201, key = "loot_ember", kind = "lootbeam", icon = 18420, source = "store", price = 150, accent = "#461809f0",
			name = "Ember Labels", desc = "Your highlighted loot labels sit on smouldering ember. Rarity colours stay."},
		{id = 202, key = "loot_verdant", kind = "lootbeam", icon = 18415, source = "store", price = 150, accent = "#0e2d15f0",
			name = "Verdant Labels", desc = "Your highlighted loot labels sit on deep green. Rarity colours stay."},
		{id = 203, key = "loot_azure", kind = "lootbeam", icon = 18418, source = "store", price = 150, accent = "#0f2250f0",
			name = "Azure Labels", desc = "Your highlighted loot labels sit on night blue. Rarity colours stay."},
		{id = 204, key = "loot_royal", kind = "lootbeam", icon = 18414, source = "store", price = 150, accent = "#380f52f0",
			name = "Royal Labels", desc = "Your highlighted loot labels sit on royal violet. Rarity colours stay."},
		{id = 205, key = "loot_gilded", kind = "lootbeam", icon = 2154, source = "achievement", achievement = "goblin_10",
			accent = "#322606f0", name = "Gilded Labels",
			desc = "Your highlighted loot labels sit on dark gold. Achievement: Greed Is Good."},

		-- ------------------------------------------------------------------ chat name colours (store 200, one achievement)
		{id = 301, key = "chat_cinder", kind = "chatcolor", icon = 2147, source = "store", price = 200, color = "#ff9a4a",
			name = "Cinder Name", desc = "Your name in chat glows cinder orange for everyone."},
		{id = 302, key = "chat_frost", kind = "chatcolor", icon = 2146, source = "store", price = 200, color = "#7fc8ff",
			name = "Frost Name", desc = "Your name in chat shows frost blue for everyone."},
		{id = 303, key = "chat_verdant", kind = "chatcolor", icon = 2149, source = "store", price = 200, color = "#7ee08a",
			name = "Verdant Name", desc = "Your name in chat shows leaf green for everyone."},
		{id = 304, key = "chat_amethyst", kind = "chatcolor", icon = 2150, source = "store", price = 200, color = "#c49cff",
			name = "Amethyst Name", desc = "Your name in chat shows amethyst for everyone."},
		{id = 305, key = "chat_rose", kind = "chatcolor", icon = 2145, source = "store", price = 200, color = "#ff8fb0",
			name = "Rose Name", desc = "Your name in chat shows rose for everyone."},
		{id = 306, key = "chat_veteran", kind = "chatcolor", icon = 13531, source = "achievement", achievement = "level_300",
			color = "#f0cf6a", name = "Veteran's Gold",
			desc = "Your name in chat shows old gold for everyone. Achievement: Veteran of the Wastes."}
	}
}
