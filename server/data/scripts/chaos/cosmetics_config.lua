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
--            the achievement `achievement` of achievements_data.lua; granted at login and when the window opens; or,
--            the reward track, `points` = N account achievement points / `category` = every achievement of a category,
--            also granted when the account's achievements change; never sold, never taken back) |
--            "pvp" (granted by battleground.lua / arena_season.lua: the honor vendor, the season rewards; pvp = how)
-- Kinds:
--   spellskin  line = a key of `lines`; spells = spell ids of that line (2-3); swaps per effect type, default name ->
--              variant name, both in the same recolour family of `families` (the same picture in another colour, an
--              effect of the client pair): fx (chaos_fx.lua Fx names), missile (chaos_fx.lua FxMissile names), vfx
--              (chaos_vfx.lua Vfx names), vmissile (chaos_vfx.lua VfxShoot names). Only those spells and only those
--              effects change; a variant the server does not know falls back to the default effect.
--   killfx     vfx = a chaos_vfx.lua effect played on the monster's tile when the character lands the killing blow;
--              dissolve = a mode of `dissolve.modes` (O563), tint = 0 .. 7 (the shader's palette, 0 = the mode's own
--              colour): instead of the effect the monster's own sprite comes apart (client game_killdissolve); the
--              `vfx` stays as the plain effect when the cap is over, the client has no shader for it or an old client
--              plays it. The Customise window's preview plays the same shader on its dummy monster.
--   lootbeam   accent = background of the character's own highlighted ground loot labels (client game_groundlabels);
--              the text and the border keep the rarity colour, the corpse loot rays keep their rarity colours
--   chatcolor  color = the colour of the character's own name in chat (every viewer); readable on the console
--   footprint  art = a key of `prints`: the prints every viewer's client leaves behind the walking character (client
--              game_cosmeticfx draws its own generated pictures on the tiles left; no server work per step); color =
--              the window's swatch
--   outline    art = a key of `glows`: a coloured line around the character's silhouette for every viewer
--              (game_cosmeticfx CF.OUTLINES holds each art's colours; an old client without base patch 0038 shows a
--              soft glow picture instead); pulse = true: it breathes in and out; color = the window's swatch
-- Sources also: "boss" (boss = the boss's name for the window): a rare personal drop of that boss, granted by
-- exclusives.lua (exclusives_config.lua `bosses`), never sold.
-- And "pact" (pact = the window's line): the Chaos Pact's perks (pact_config.lua perks, pact_perks.lua): the chat
-- colour while the Pact is active, the monthly cosmetic kept for good; never sold.
-- And "candlemarks": bought for Candlemarks at Osric the Chandler (candlemarks_config.lua offers of kind "cosmetic",
-- one per account); never sold for Chaos Coins.
-- And "daily" (days = the streak length): a login streak milestone (daily_config.lua milestones `cosmetic`, O409),
-- granted once per account by daily.lua; never sold.

return {
	opcode = 225, -- ChaosOpcodes.cosmetics (client game_cosmetics)
	table = "chaos_cosmetics", -- one row per account and unlocked cosmetic (server/sql/chaos_cosmetics.sql)
	-- player storages, 7100940 - 7100949 reserved (chaos_constants.lua): the id of the chosen cosmetic per kind, and per
	-- class line for the spell skins (skinBase + line slot, slots 0..6); 0 / unset = the default
	storage = {killfx = 7100940, lootbeam = 7100941, chatcolor = 7100942, skinBase = 7100943,
		-- footprints and outlines: the wardrobe block 7102000 - 7102049 (chaos_constants.lua Chaos.storage.wardrobe)
		footprint = 7102000, outline = 7102001,
		-- combat cosmetics others see (O318): the level-up effect and the rare-loot effect. 7102004 was the victory emote
		-- (removed, O564): the key stays reserved, nothing reads or writes it, never reuse it
		levelfx = 7102002, rarefx = 7102003},
	staffGroup = 4, -- /cosmetic <character>, <key | all>[, revoke]
	previewCooldownMs = 1500, -- a store / window preview (an effect only the asking player sees)
	-- the dissolve kill effects (O563, cosmetics.lua `dissolve`): the server sends {action = "kdis"} on the cosmetics opcode
	-- to the players near the kill (their clients draw the monster's sprite dissolving, game_killdissolve); at most
	-- `perSec` dissolves per killer and second, `maxViewers` players per kill, the rest see the plain effect (`vfx`)
	-- played by the server. The client has its own cap too (6 at once, 3 on a phone). Modes (client/tools/gen_kill_dissolve.py,
	-- data/shaders/chaos_outfit_kd_<mode>.frag): sand (blown away top first), pixels (the sprite's pixels drift apart),
	-- ash (crumbles and falls), burn (burns from the edges inward), void (collapses to a point), frost (shatters and melts),
	-- gold (rises as dust).
	dissolve = {
		modes = {"sand", "pixels", "ash", "burn", "void", "frost", "gold"},
		tints = 8,
		perSec = 4,
		maxViewers = 12,
		range = {x = 9, y = 7}
	},
	consoleBackground = "#1c1a18", -- chat colours must stay readable on this (contrast 4.5 or more)
	labelRarityColors = { -- the rarity colours of the ground labels (client game_lootfilter): Common, Uncommon, Magic, Rare,
		-- Legendary, Divine, Unique (data/lib/chaos_rarity.lua); accents keep them readable
		"#c8c8c8", "#5ccf5c", "#4a90ff", "#a35cf0", "#ffd040", "#c8e8ff", "#e07b24"},

	kinds = {
		{key = "spellskin", name = "Spell Effects", store = "Spell Effects"},
		{key = "killfx", name = "Kill Effects", store = "Kill Effects"},
		{key = "lootbeam", name = "Loot Labels", store = "Loot Labels"},
		{key = "chatcolor", name = "Chat Name Colours", store = "Chat Colours"},
		{key = "footprint", name = "Footprints", store = "Footprints"},
		{key = "outline", name = "Outlines", store = "Outlines"},
		{key = "levelfx", name = "Level-up Effects", store = "Level-up Effects"},
		{key = "rarefx", name = "Rare Loot Effects", store = "Rare Loot Effects"}
	},

	-- The cosmetics taken out of the game (O564, owner 2026-11-14: the Victory Emotes "do not make sense, take them
	-- out"): id, key and the store list price stay here so their ids and keys are never reused and the refund
	-- (server/sql/chaos_zz_emote_removal.sql, server/README.md "Victory emotes removed") is held to this list by
	-- tests/cosmetics_removal_test.lua. Nothing else reads it.
	retired = {
		{id = 801, key = "emote_roar", kind = "emote", price = 200},
		{id = 802, key = "emote_salute", kind = "emote", price = 200},
		{id = 803, key = "emote_flourish", kind = "emote", price = 250},
		{id = 804, key = "emote_halo", kind = "emote", price = 250},
		{id = 805, key = "emote_shadow", kind = "emote", price = 200}
	},

	-- Combat cosmetics others see (O318, cosmetics.lua). Visual only: an effect on a tile, sent to everyone who stands
	-- near, never a number. Throttled on the server per character and kind:
	--   levelup  the effect of `levelfx` on the character's tile when it gains a level (once per levelMs)
	--   rare     the effect of `rarefx` on the corpse's tile when the kill drops an item of `rarity` or better (the
	--            data/lib/chaos_rarity.lua key), for the character that owns the corpse (once per rareMs)
	combat = {
		levelMs = 4000,
		rareMs = 3000,
		rarity = "legendary"
	},

	-- the pictures of the client (client/tools/gen_cosmeticfx_art.py -> game_cosmeticfx/images/prints|glows/<art>.png);
	-- a footprint / outline names one of these
	prints = {"ember", "frost", "blood", "ash", "petal", "shadow", "gilded", "venom", "spark",
		"hunter", "chronicle", "rime", "omen", "laurel"},
	glows = {"gold", "crimson", "void", "frost", "ember", "verdant", "radiant", "abyssal", "storm",
		"absolute", "chronicle", "corona", "cinder"},

	-- ------------------------------------------------------------------ Chaos outfit shaders (on sale)
	-- Six outfit shaders written for this server (client data/shaders/chaos_outfit_*.frag, registered by client
	-- game_chaosshaders under `shader`; shaders.xml ids `shaderId` 19-24 by server/tools/install_outfits.py). Kept out
	-- of `cosmetics` and `kinds` on purpose: they are engine outfit shaders, chosen in the Outfit window like the store's
	-- other shaders, so the Cosmetics window lists them but has no "use" for them.
	-- enabled = false (the off switch): nothing is granted, listed or sold; owned unlocks stay in chaos_cosmetics.
	-- enabled = true: an owned one is added to every character of the account at login and when it is unlocked
	-- (Player:addShader), and the Cosmetics window shows them. Unpriced (no `price`): not sold yet. To sell one, give it
	-- price = N (Chaos Coins) and add dofile("data/scripts/chaos/cosmetics_store.lua")("outfitshader") to the
	-- Cosmetics hunk of shop_config.lua; cosmetics_test.lua checks the offers against these prices.
	-- Entry: {key, shaderId, shader, icon, color (the window's swatch), name, desc[, price]}; key is the unlock
	-- "cosmetic_<key>" and must not clash with a key of `cosmetics`.
	-- Switched on with prices on 2026-10-13 (owner: "Pode fazer todas as mudanças recomendadas"). PLACEHOLDER PRICES
	-- (docs/OWNER_TODO.md): 250 coins (US$ 4.99 in the 250 pack) for the four, 300 for Holy Radiance and Spectral
	-- Ghost (the two with the most motion); the stock shaders cost 120-150, auras 150-300, wings 200-350.
	outfitShaders = {
		enabled = true,
		list = {
			{key = "shader_ember_glow", shaderId = 19, shader = "chaos_ember_glow", icon = 2187, color = "#ff7a2a", price = 250,
				name = "Ember Glow", desc = "Your outfit smoulders: a flickering ember edge and sparks drifting up."},
			{key = "shader_frost_rime", shaderId = 20, shader = "chaos_frost_rime", icon = 2146, color = "#bfe6ff", price = 250,
				name = "Frost Rime", desc = "Your outfit turns to ice, rimed at the edges, with crystals that glint."},
			{key = "shader_void_flicker", shaderId = 21, shader = "chaos_void_flicker", icon = 2153, color = "#9a4ce0", price = 250,
				name = "Void Flicker", desc = "Your outfit sinks into violet dark; its edge flickers and slips away."},
			{key = "shader_holy_radiance", shaderId = 22, shader = "chaos_holy_radiance", icon = 2145, color = "#ffe08a", price = 300,
				name = "Holy Radiance", desc = "A golden light breathes through your outfit, rays crossing it slowly."},
			{key = "shader_blood_pulse", shaderId = 23, shader = "chaos_blood_pulse", icon = 9020, color = "#c81e24", price = 250,
				name = "Heartblood", desc = "A heartbeat floods your outfit red and lights the veins beneath."},
			{key = "shader_spectral_ghost", shaderId = 24, shader = "chaos_spectral_ghost", icon = 2150, color = "#a8f0f0", price = 300,
				name = "Spectral Ghost", desc = "Your outfit fades to a pale, see-through ghost with a cold glow."}
		}
	},

	-- class lines (spell skins): slot = storage offset (skinBase + slot, 0 .. 6)
	lines = {
		{key = "warrior", slot = 0, name = "Warrior line", vocations = {"Warrior", "Juggernaut", "Berserker"}},
		{key = "ranger", slot = 1, name = "Ranger line", vocations = {"Ranger", "Deadeye", "Beastmaster"}},
		{key = "mystic", slot = 2, name = "Mystic line", vocations = {"Mystic", "Elementalist", "Illusionist"}},
		{key = "thief", slot = 3, name = "Thief line", vocations = {"Thief", "Ninja", "Samurai"}},
		{key = "monk", slot = 4, name = "Monk line", vocations = {"Monk", "Shadowfist", "Iron Sage"}},
		{key = "templar", slot = 5, name = "Templar line", vocations = {"Templar", "Inquisitor", "Sentinel"}},
		{key = "necromancer", slot = 6, name = "Necromancer line", vocations = {"Necromancer", "Lich", "Bone Lord"}}
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
			flame = {"shadow_flame", "poison_flame"},
			shards = {"frost_burst", "ice_spikes"}
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

		-- ------------------------------------------------------------------ kill effects (store 200, two from achievements; one more at the end)
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
			desc = "Your name in chat shows old gold for everyone. Achievement: Veteran of the Wastes."},

		-- ------------------------------------------------------------------ the Cinderheart (uber.lua; last, so the list
		-- positions the tests use stay)
		{id = 108, key = "kill_cinderheart", kind = "killfx", icon = 2353, source = "achievement", achievement = "cinder_1",
			vfx = "ember_crown", name = "Cinderheart Crown", desc = "A crown of embers burns over your kills. Achievement: Cinderbreaker."},
		-- the Ashen Sepulchre's final boss (raid.lua; the achievement raid_sovereign)
		{id = 109, key = "kill_sovereign", kind = "killfx", icon = 2498, source = "achievement", achievement = "raid_sovereign",
			vfx = "dome_blast_violet", name = "Sovereign's Pyre", desc = "A pyre of violet ash rises from your kills. Achievement: The Last Door."},
		-- PvP (battleground.lua, arena_season.lua; source "pvp", pvp = how): the honor vendor and the season rewards
		{id = 110, key = "kill_honorbrand", kind = "killfx", icon = 2400, source = "pvp", pvp = "Battleground vendor (honor)",
			vfx = "px448_crimson", dissolve = "ash", tint = 2, name = "Honor Brand",
			desc = "The monster you finish crumbles to crimson ash and falls away."},
		{id = 111, key = "kill_cinderthrone", kind = "killfx", icon = 2343, source = "pvp", pvp = "PvP season reward: Cinder Sovereign",
			vfx = "aura_burst_god", name = "Cinder Throne", desc = "A storm of light crowns your kills. PvP season: Cinder Sovereign."},
		{id = 206, key = "loot_warbanner", kind = "lootbeam", icon = 1436, source = "pvp", pvp = "Battleground vendor (honor)",
			accent = "#2c1010f0", name = "Warbanner Labels", desc = "Your highlighted loot labels sit on war-torn crimson. Rarity colours stay."},
		{id = 207, key = "loot_blazing", kind = "lootbeam", icon = 1481, source = "pvp", pvp = "PvP season reward: Blazing or better",
			accent = "#3a1c06f0", name = "Blazing Labels", desc = "Your highlighted loot labels sit on banked fire. PvP season: Blazing."},
		{id = 307, key = "chat_gladiator", kind = "chatcolor", icon = 2392, source = "pvp", pvp = "Battleground vendor (honor)",
			color = "#b8c4d4", name = "Gladiator Steel", desc = "Your name in chat shows polished steel for everyone."},
		{id = 308, key = "chat_infernal", kind = "chatcolor", icon = 2343, source = "pvp", pvp = "PvP season reward: Infernal or better",
			color = "#ff6a4a", name = "Infernal Name", desc = "Your name in chat burns infernal red for everyone. PvP season: Infernal."},
		-- Candlemarks (candlemarks_config.lua; source "candlemarks"): bought at Osric the Chandler, never for coins
		{id = 140, key = "kill_candleseal", kind = "killfx", icon = 2050, source = "candlemarks", vfx = "holy_seal",
			name = "Candle Seal", desc = "A seal of candlelight glows where your killing blow lands."},
		{id = 230, key = "loot_tallow", kind = "lootbeam", icon = 2048, source = "candlemarks", accent = "#2e2412f0",
			name = "Tallow Labels", desc = "Your highlighted loot labels sit on warm tallow. Rarity colours stay."},
		{id = 330, key = "chat_candlelight", kind = "chatcolor", icon = 2047, source = "candlemarks", color = "#ffd98a",
			name = "Candlelight Name", desc = "Your name in chat glows soft candlelight for everyone."},
		-- the Scorched Marches vendor (pvpzone.lua; banked embers)
		{id = 120, key = "kill_marchfire", kind = "killfx", icon = 2353, source = "pvp", pvp = "Scorched Marches vendor (embers)",
			vfx = "meteor_strike", name = "Marchfire", desc = "A burning star falls where your killing blow lands."},
		{id = 212, key = "loot_scorched", kind = "lootbeam", icon = 2249, source = "pvp", pvp = "Scorched Marches vendor (embers)",
			accent = "#2a1608f0", name = "Scorched Earth Labels", desc = "Your highlighted loot labels sit on scorched earth. Rarity colours stay."},
		{id = 314, key = "chat_marchember", kind = "chatcolor", icon = 1481, source = "pvp", pvp = "Scorched Marches vendor (embers)",
			color = "#e8925a", name = "Marchember", desc = "Your name in chat glows like a banked ember for everyone."},

		-- ------------------------------------------------------------------ the achievement reward track (source
		-- "achievement", never sold). points = N: the account has N achievement points (each achievement once, any of its
		-- characters); category = key: the account has every achievement of that category of achievements_data.lua (the
		-- category's title is in its categoryRewards). Palette variants of effects and colours that already exist.
		{id = 309, key = "chat_ashen", kind = "chatcolor", icon = 2147, source = "achievement", points = 100,
			color = "#cfc4b4", name = "Ashen Name", desc = "Your name in chat shows pale ash for everyone. Reward track: 100 points."},
		{id = 208, key = "loot_chronicle", kind = "lootbeam", icon = 18415, source = "achievement", points = 250,
			accent = "#0b2626f0", name = "Chronicle Labels", desc = "Your highlighted loot labels sit on deep teal. Reward track: 250 points."},
		{id = 112, key = "kill_verdigris", kind = "killfx", icon = 2229, source = "achievement", points = 500,
			vfx = "px448_green", dissolve = "pixels", tint = 1, name = "Verdigris Splash",
			desc = "The monster you finish comes apart into green pixels that drift and fade. Reward track: 500 points."},
		{id = 310, key = "chat_chronicler", kind = "chatcolor", icon = 13531, source = "achievement", points = 1000,
			color = "#5cc8c0", name = "Chronicler's Teal", desc = "Your name in chat shows chronicle teal for everyone. Reward track: 1000 points."},
		{id = 113, key = "kill_vortex", kind = "killfx", icon = 2153, source = "achievement", points = 1750,
			vfx = "px03_arcane", name = "Arcane Vortex", desc = "An arcane vortex swallows your kills. Reward track: 1750 points."},
		{id = 209, key = "loot_obsidian", kind = "lootbeam", icon = 18414, source = "achievement", points = 2500,
			accent = "#140f1af0", name = "Obsidian Labels", desc = "Your highlighted loot labels sit on obsidian. Reward track: 2500 points."},
		{id = 114, key = "kill_ascent", kind = "killfx", icon = 2343, source = "achievement", points = 3500,
			vfx = "aura_burst_gold", name = "Gilded Ascent", desc = "A golden burst crowns your kills. Reward track: 3500 points."},
		{id = 115, key = "kill_warsurge", kind = "killfx", icon = 2400, source = "achievement", category = "combat",
			vfx = "aura_burst_red", name = "War Surge", desc = "A red surge rises from your kills. Complete Combat & Leveling."},
		{id = 116, key = "kill_thornbloom", kind = "killfx", icon = 18415, source = "achievement", category = "monsters",
			vfx = "px286_green", name = "Thornbloom", desc = "Petals burst over your kills. Complete Monsters."},
		{id = 117, key = "kill_titanpyre", kind = "killfx", icon = 2498, source = "achievement", category = "bosses",
			vfx = "dome_blast_holy", name = "Titan's Pyre", desc = "A dome of holy fire rises from your kills. Complete World Bosses."},
		{id = 118, key = "kill_riftsigil", kind = "killfx", icon = 6500, source = "achievement", category = "rifts",
			vfx = "px674_arcane", name = "Rift Sigil", desc = "An arcane sigil seals your kills. Complete Rifts."},
		{id = 210, key = "loot_sepulchre", kind = "lootbeam", icon = 2498, source = "achievement", category = "raids",
			accent = "#1d1712f0", name = "Sepulchre Labels", desc = "Your highlighted loot labels sit on grave ash. Complete Raids."},
		{id = 311, key = "chat_huntsman", kind = "chatcolor", icon = 2392, source = "achievement", category = "bounties",
			color = "#e8a070", name = "Huntsman's Copper", desc = "Your name in chat shows copper for everyone. Complete Bounties."},
		{id = 211, key = "loot_tempered", kind = "lootbeam", icon = 2154, source = "achievement", category = "items",
			accent = "#182028f0", name = "Tempered Labels", desc = "Your highlighted loot labels sit on tempered steel. Complete Items & Crafting."},
		{id = 312, key = "chat_bloodsteel", kind = "chatcolor", icon = 1436, source = "achievement", category = "pvp",
			color = "#e8848c", name = "Bloodsteel Name", desc = "Your name in chat shows bloodsteel for everyone. Complete PvP."},
		{id = 313, key = "chat_lantern", kind = "chatcolor", icon = 2145, source = "achievement", category = "explore",
			color = "#e8d890", name = "Lantern Name", desc = "Your name in chat shows lantern light for everyone. Complete Exploration & Social."},
		{id = 119, key = "kill_starfall", kind = "killfx", icon = 2150, source = "achievement", category = "secrets",
			vfx = "starfall_crown", name = "Falling Stars", desc = "Stars fall over your kills. Complete Secrets."},
		{id = 121, key = "kill_summit", kind = "killfx", icon = 2353, source = "achievement", category = "milestones",
			vfx = "infernal_seal", name = "Summit Seal",
			desc = "A seal of hellfire burns where your killing blow lands. Complete Level Milestones."},

		-- ------------------------------------------------------------------ footprints (store 200)
		-- every viewer's client draws them (game_cosmeticfx), behind the walking character, fading in about 2.5 s
		{id = 401, key = "foot_ember", kind = "footprint", icon = 2187, source = "store", price = 200, art = "ember",
			color = "#ff8a3a", name = "Ember Steps", desc = "Glowing ember prints smoulder where you walk."},
		{id = 402, key = "foot_frost", kind = "footprint", icon = 2274, source = "store", price = 200, art = "frost",
			color = "#9ad8ff", name = "Frost Steps", desc = "Each step leaves a print of rime."},
		{id = 403, key = "foot_blood", kind = "footprint", icon = 9020, source = "store", price = 200, art = "blood",
			color = "#c83030", name = "Blood Trail", desc = "Drops of blood mark your way."},
		{id = 404, key = "foot_ash", kind = "footprint", icon = 2229, source = "store", price = 200, art = "ash",
			color = "#a8a29a", name = "Ash Prints", desc = "Grey ash settles in your footprints."},
		{id = 405, key = "foot_petal", kind = "footprint", icon = 18415, source = "store", price = 200, art = "petal",
			color = "#ff9ec4", name = "Petal Trail", desc = "Pink petals fall where you step."},
		{id = 406, key = "foot_venom", kind = "footprint", icon = 2149, source = "store", price = 200, art = "venom",
			color = "#7ee05a", name = "Venom Drips", desc = "Green venom drips from your steps."},
		{id = 407, key = "foot_shadow", kind = "footprint", icon = 2150, source = "store", price = 200, art = "shadow",
			color = "#9a6ae0", name = "Shadow Wisps", desc = "Violet wisps of shadow curl behind you."},
		{id = 408, key = "foot_gilded", kind = "footprint", icon = 2154, source = "store", price = 200, art = "gilded",
			color = "#ffd040", name = "Gilded Steps", desc = "Golden prints that sparkle a moment."},
		{id = 409, key = "foot_spark", kind = "footprint", icon = 7759, source = "store", price = 200, art = "spark",
			color = "#a8e4ff", name = "Storm Sparks", desc = "Crackling sparks jump from every step."},
		-- never sold: an achievement, the reward track and boss drops (exclusives_config.lua)
		{id = 451, key = "foot_hunter", kind = "footprint", icon = 2392, source = "achievement", achievement = "bounty_week_10",
			art = "hunter", color = "#c89060", name = "Hunter's Tracks", desc = "Paw-and-claw tracks of a bounty hunter. Achievement: Never Off Duty."},
		{id = 452, key = "foot_chronicle", kind = "footprint", icon = 13531, source = "achievement", points = 750,
			art = "chronicle", color = "#5cc8c0", name = "Inkstep", desc = "Teal ink runes mark your path. Reward track: 750 points."},
		{id = 453, key = "foot_rime", kind = "footprint", icon = 2146, source = "boss", boss = "Skaldra the Rime Queen",
			art = "rime", color = "#d8f4ff", name = "Rimewalker", desc = "Crystals of the Rime Queen's frost bloom in your steps."},
		{id = 454, key = "foot_omen", kind = "footprint", icon = 6500, source = "boss", boss = "the Ascended Omens",
			art = "omen", color = "#b070ff", name = "Omen Ash", desc = "Violet ash of a broken omen drifts behind you."},

		-- ------------------------------------------------------------------ outlines (store 250, pulsing ones too)
		{id = 501, key = "glow_gold", kind = "outline", icon = 2154, source = "store", price = 250, art = "gold",
			color = "#ffd040", name = "Gilded Glow", desc = "A warm golden line traces your outline."},
		{id = 502, key = "glow_crimson", kind = "outline", icon = 2156, source = "store", price = 250, art = "crimson",
			color = "#e03838", name = "Crimson Glow", desc = "A blood-red line traces your outline."},
		{id = 503, key = "glow_void", kind = "outline", icon = 2153, source = "store", price = 250, art = "void",
			color = "#9a4ce0", name = "Void Glow", desc = "A deep violet line traces your outline."},
		{id = 504, key = "glow_frost", kind = "outline", icon = 2146, source = "store", price = 250, art = "frost",
			color = "#7fc8ff", name = "Frost Glow", desc = "A cold blue line traces your outline."},
		{id = 505, key = "glow_verdant", kind = "outline", icon = 2149, source = "store", price = 250, art = "verdant",
			color = "#6ee070", name = "Verdant Glow", desc = "A living green line traces your outline."},
		{id = 506, key = "glow_ember", kind = "outline", icon = 2187, source = "store", price = 250, art = "ember",
			color = "#ff7a2a", name = "Ember Gradient", desc = "Your outline runs red at your feet, burning gold at your crown."},
		{id = 507, key = "glow_storm", kind = "outline", icon = 7759, source = "store", price = 250, art = "storm",
			color = "#a8f0ff", name = "Storm Gradient", desc = "Your outline runs deep blue below, white lightning above."},
		{id = 508, key = "glow_radiant", kind = "outline", icon = 2145, source = "store", price = 250, art = "radiant",
			pulse = true, color = "#fff0a0", name = "Radiant Pulse", desc = "A golden outline that breathes in and out."},
		{id = 509, key = "glow_abyssal", kind = "outline", icon = 6500, source = "store", price = 250, art = "abyssal",
			pulse = true, color = "#7040c0", name = "Abyssal Pulse", desc = "A violet outline of darkness that swells and fades."},
		-- never sold
		{id = 551, key = "glow_absolute", kind = "outline", icon = 2343, source = "achievement", achievement = "paragon_282",
			art = "absolute", pulse = true, color = "#fff8e0", name = "Paragon's Radiance",
			desc = "A white-gold outline that pulses with every breath. Achievement: Absolute."},
		{id = 552, key = "glow_chronicle", kind = "outline", icon = 13531, source = "achievement", points = 2000,
			art = "chronicle", color = "#5cc8c0", name = "Chronicler's Halo", desc = "A teal outline of old ink. Reward track: 2000 points."},
		{id = 553, key = "glow_corona", kind = "outline", icon = 2153, source = "boss", boss = "Nyxareth the Void Archon",
			art = "corona", pulse = true, color = "#5a2a90", name = "Void Corona", desc = "A dark outline burning to violet, torn from the Void Archon."},
		{id = 554, key = "glow_cinder", kind = "outline", icon = 2353, source = "boss", boss = "Ysgrath the Cinderheart",
			art = "cinder", pulse = true, color = "#ff5a1a", name = "Cinderheart Blaze", desc = "The Cinderheart's own fire, flaring along your outline."},
		-- ------------------------------------------------------------------ combat cosmetics others see (O318; store 150-250)
		-- level-up effects: `vfx` rises on the character's tile when it gains a level (cfg.combat.levelMs apart)
		{id = 601, key = "lvl_dawn", kind = "levelfx", icon = 2145, source = "store", price = 200, vfx = "holy_smite",
			name = "Dawn Ascent", desc = "A column of dawn light rises round you when you gain a level."},
		{id = 602, key = "lvl_ember", kind = "levelfx", icon = 2187, source = "store", price = 200, vfx = "ember_crown",
			name = "Ember Ascent", desc = "A crown of embers burns over you when you gain a level."},
		{id = 603, key = "lvl_frost", kind = "levelfx", icon = 2146, source = "store", price = 200, vfx = "frost_bastion",
			name = "Frost Ascent", desc = "A ring of ice crystals rises round you when you gain a level."},
		{id = 604, key = "lvl_grove", kind = "levelfx", icon = 2149, source = "store", price = 150, vfx = "verdant_bloom",
			name = "Verdant Ascent", desc = "Leaves bloom round you when you gain a level."},
		{id = 605, key = "lvl_void", kind = "levelfx", icon = 2153, source = "store", price = 250, vfx = "void_rift",
			name = "Void Ascent", desc = "A violet rift opens and closes round you when you gain a level."},
		-- the level milestones (O378, milestones_config.lua): a level-up effect tier at level 1000, 1500 and 2000, never sold
		{id = 606, key = "lvl_thousand", kind = "levelfx", icon = 7759, source = "achievement", achievement = "level_1000",
			vfx = "storm_mantle", name = "Thousandth Ascent",
			desc = "A crackling storm mantle wraps you when you gain a level. Achievement: The Thousandth Step."},
		{id = 607, key = "lvl_dusk", kind = "levelfx", icon = 2150, source = "achievement", achievement = "level_1500",
			vfx = "shadow_shroud", name = "Dusk Ascent",
			desc = "A cloak of shadow rises round you when you gain a level. Achievement: The Long Dusk."},
		{id = 608, key = "lvl_undimmed", kind = "levelfx", icon = 2343, source = "achievement", achievement = "level_2000",
			vfx = "arcane_orbit", name = "Undimmed Ascent",
			desc = "Runes orbit you when you gain a level. Achievement: Two Thousand Fires."},
		-- rare-loot effects: `vfx` on the corpse's tile when your kill drops a Legendary item or better
		{id = 701, key = "rare_gilded", kind = "rarefx", icon = 2154, source = "store", price = 200, vfx = "aura_burst_gold",
			name = "Gilded Glint", desc = "A golden burst flares over the corpse when it drops a Legendary item or better."},
		{id = 702, key = "rare_crimson", kind = "rarefx", icon = 2156, source = "store", price = 200, vfx = "aura_burst_red",
			name = "Crimson Gleam", desc = "A red burst flares over the corpse when it drops a Legendary item or better."},
		{id = 703, key = "rare_starfall", kind = "rarefx", icon = 2150, source = "store", price = 250, vfx = "starfall_crown",
			name = "Starfall Find", desc = "Stars fall over the corpse when it drops a Legendary item or better."},
		{id = 704, key = "rare_seal", kind = "rarefx", icon = 2145, source = "store", price = 150, vfx = "holy_seal",
			name = "Holy Seal Find", desc = "A seal of light glows on the corpse when it drops a Legendary item or better."},
		{id = 705, key = "rare_royal", kind = "rarefx", icon = 18414, source = "store", price = 250, vfx = "dome_blast_violet",
			name = "Royal Pyre", desc = "A dome of violet fire rises over the corpse when it drops a Legendary item or better."},

		-- ------------------------------------------------------------------ the collection score rewards (O318,
		-- collection_config.lua milestones; source "collection": granted once when the account reaches `collection`
		-- points, never sold, never counted in the score)
		{id = 460, key = "foot_collector", kind = "footprint", icon = 18415, source = "collection", collection = 60, art = "laurel",
			color = "#c8e070", name = "Laurel Steps", desc = "Pale laurel leaves mark your steps. Collection score: 60 points."},
		{id = 340, key = "chat_collector", kind = "chatcolor", icon = 2154, source = "collection", collection = 220,
			color = "#f2d27a", name = "Collector's Gold", desc = "Your name in chat shows museum gold for everyone. Collection score: 220 points."},

		-- ------------------------------------------------------------------ the login streak rewards (O409,
		-- daily_config.lua milestones `cosmetic`; source "daily": granted once when the account's streak reaches `days`,
		-- never sold; daily_test.lua checks the link)
		{id = 240, key = "loot_devoted", kind = "lootbeam", icon = 2048, source = "daily", days = 7, accent = "#2c1a0cf0",
			name = "Devoted Labels", desc = "Your highlighted loot labels sit on banked ember brown. Rarity colours stay. Login streak: 7 days."},
		{id = 610, key = "lvl_vigil", kind = "levelfx", icon = 2050, source = "daily", days = 60, vfx = "holy_seal",
			name = "Vigil Ascent", desc = "A seal of candlelight blooms under you when you gain a level. Login streak: 60 days."},

		-- the Chaos Pact (VIP) perks (pact_config.lua perks): the chat colour while active, one cosmetic a month
		{id = 315, key = "chat_pactbound", kind = "chatcolor", icon = 16101, source = "pact", pact = "While the Chaos Pact is active",
			color = "#e0664a", name = "Pactbound Name", desc = "Your name in chat burns Pact red for everyone while your Chaos Pact lasts."},
		{id = 130, key = "kill_pact_ember", kind = "killfx", icon = 16101, source = "pact", pact = "Chaos Pact, November 2026",
			vfx = "px448_crimson", dissolve = "burn", tint = 2, name = "Pact Ember",
			desc = "The monster you finish burns from its edges inward in crimson embers."},
		{id = 220, key = "loot_pact_frost", kind = "lootbeam", icon = 16101, source = "pact", pact = "Chaos Pact, December 2026",
			accent = "#0a2028f0", name = "Pact Frost Labels", desc = "Your highlighted loot labels sit on frozen teal. Rarity colours stay."},
		{id = 131, key = "kill_pact_venom", kind = "killfx", icon = 16101, source = "pact", pact = "Chaos Pact, January 2027",
			vfx = "px633_green", name = "Pact Venom", desc = "A green skull rises from the monster you finish."},
		{id = 221, key = "loot_pact_rose", kind = "lootbeam", icon = 16101, source = "pact", pact = "Chaos Pact, February 2027",
			accent = "#4a1230f0", name = "Pact Rose Labels", desc = "Your highlighted loot labels sit on deep rose. Rarity colours stay."},
		{id = 132, key = "kill_pact_frost", kind = "killfx", icon = 16101, source = "pact", pact = "Chaos Pact, March 2027",
			vfx = "px195_ice", name = "Pact Frost", desc = "An icy rune bursts where your killing blow lands."},
		{id = 222, key = "loot_pact_gold", kind = "lootbeam", icon = 16101, source = "pact", pact = "Chaos Pact, April 2027",
			accent = "#2a2006f0", name = "Pact Gold Labels", desc = "Your highlighted loot labels sit on old gold. Rarity colours stay."},

		-- ------------------------------------------------------------------ O563 (appended: the list positions the tests use stay)
		-- Dissolve kill effects (client game_killdissolve): the monster's own sprite blows away, comes apart, crumbles,
		-- burns, collapses, shatters or rises as dust. Store 200 like the other kill effects; three from achievements.
		{id = 122, key = "kill_windswept", kind = "killfx", icon = 2147, source = "store", price = 200, vfx = "px586_white",
			dissolve = "sand", name = "Windswept", desc = "The monster you finish blows away as sand in the wind, top first."},
		{id = 123, key = "kill_unravel", kind = "killfx", icon = 2150, source = "store", price = 200, vfx = "px03_arcane",
			dissolve = "pixels", name = "Unravelling", desc = "The monster you finish comes apart into its own pixels that drift and fade."},
		{id = 124, key = "kill_ashfall", kind = "killfx", icon = 2147, source = "store", price = 200, vfx = "necro_seal",
			dissolve = "ash", name = "Ashfall", desc = "The monster you finish crumbles to grey ash and falls."},
		{id = 125, key = "kill_frostmelt", kind = "killfx", icon = 2146, source = "store", price = 200, vfx = "px195_ice",
			dissolve = "frost", name = "Frostmelt", desc = "The monster you finish freezes, shatters into shards and melts away."},
		{id = 126, key = "kill_emberfade", kind = "killfx", icon = 2353, source = "achievement", achievement = "cinder_10", vfx = "ember_crown",
			dissolve = "burn", tint = 7, name = "Emberfade",
			desc = "The monster you finish burns from its edges inward and the embers rise. Achievement: Keeper of the Ashes."},
		{id = 127, key = "kill_voidcollapse", kind = "killfx", icon = 2153, source = "achievement", achievement = "omen_10", vfx = "void_rift",
			dissolve = "void", name = "Void Collapse",
			desc = "The monster you finish is pulled into a point and swallowed. Achievement: Herald of Omens."},
		{id = 128, key = "kill_gildeddust", kind = "killfx", icon = 2148, source = "achievement", achievement = "goblin_50", vfx = "aura_burst_gold",
			dissolve = "gold", tint = 4, name = "Gilded Dust",
			desc = "The monster you finish turns to gold and rises as dust. Achievement: Hoardbreaker."},

		-- Spell effect skins for the spells the starter builds lean on (O563; store 250 like the others). Each keeps the
		-- element readable: a fire spell stays fire (ember), ice stays ice, a war cry or a strike only changes colour.
		{id = 13, key = "skin_mystic_ember", kind = "spellskin", icon = 2187, line = "mystic", source = "store", price = 250,
			name = "Emberwreath", desc = "Witchfire Bolt, Falling Pyre and Doomtide burn in a ring of banked embers.",
			spells = {201, 204, 206}, fx = {fire_nova = "fire_ring"}},
		{id = 14, key = "skin_mystic_rime", kind = "spellskin", icon = 2146, line = "mystic", source = "store", price = 250,
			name = "Glacial Spikes", desc = "Rime Bloom and Frozen Crypt burst in tall spikes of ice.",
			spells = {200, 205}, fx = {frost_burst = "ice_spikes"}},
		{id = 15, key = "skin_mystic_umbral", kind = "spellskin", icon = 2153, line = "mystic", source = "store", price = 250,
			name = "Umbral Covenant", desc = "Crimson Covenant spreads a ring of shadow instead of blood.",
			spells = {203}, fx = {blood_nova = "shadow_ring"}},
		{id = 16, key = "skin_mystic_aether", kind = "spellskin", icon = 2150, line = "mystic", source = "store", price = 250,
			name = "Aether Storm", desc = "Forked Storm throws arcane orbs and violet lightning.",
			spells = {202}, missile = {lightning_orb = "arcane_orb"}, fx = {chain_lightning = "lightning_violet"}},
		{id = 17, key = "skin_ranger_gloom", kind = "spellskin", icon = 7761, line = "ranger", source = "store", price = 250,
			name = "Gloom Darts", desc = "Packhunter's Dart bursts in a cloud of shadow instead of spores.",
			spells = {23}, fx = {poison_burst = "shadow_smoke"}},
		{id = 28, key = "skin_mystic_gloom", kind = "spellskin", icon = 7761, line = "mystic", source = "store", price = 250,
			name = "Gloomswarm", desc = "Blightswarm, Briar Prison and Primordial Squall burst in a cloud of shadow instead of spores.",
			spells = {207, 210, 213}, fx = {poison_burst = "shadow_smoke"}},
		{id = 18, key = "skin_templar_wildfire", kind = "spellskin", icon = 18420, line = "templar", source = "store", price = 250,
			name = "Wildfire Pyre", desc = "Martyr's Pyre and Pyre of Absolution burn in a flaring ring of fire.",
			spells = {127, 177}, fx = {fire_ring = "fire_nova"}},
		{id = 19, key = "skin_templar_violet", kind = "spellskin", icon = 18414, line = "templar", source = "store", price = 250,
			name = "Violet Verdict", desc = "Bell of Reckoning, Rampart Quake and Pyre of Absolution strike in a violet dome.",
			spells = {128, 141, 177}, vfx = {dome_blast_holy = "dome_blast_violet"}},
		{id = 20, key = "skin_templar_crimson", kind = "spellskin", icon = 7760, line = "templar", source = "store", price = 250,
			name = "Crimson Verdict", desc = "Sanctum Verdict, Zealot's Wrath and Hammer of Ember Dawn flare in red.",
			spells = {131, 139, 237}, vfx = {aura_burst_gold = "aura_burst_red"}},
		{id = 21, key = "skin_warrior_gilded", kind = "spellskin", icon = 2154, line = "warrior", source = "store", price = 250,
			name = "Gilded Verdict", desc = "Judgment of Iron and Red Frenzy burst in gold instead of red.",
			spells = {148, 222}, vfx = {aura_burst_red = "aura_burst_gold"}},
		{id = 22, key = "skin_monk_azure", kind = "spellskin", icon = 2145, line = "monk", source = "store", price = 250,
			name = "Azure Palms", desc = "Thousand-Echo Palm and Tidal Palm strike in cold blue.",
			spells = {172, 89}, vfx = {ki_hit_gold = "ki_hit_blue"}},
		{id = 23, key = "skin_monk_golden", kind = "spellskin", icon = 2154, line = "monk", source = "store", price = 250,
			name = "Golden Lance", desc = "Chi Lance and Mistborne Strike strike in gold.",
			spells = {87, 67}, vfx = {ki_hit_blue = "ki_hit_gold"}},
		{id = 24, key = "skin_monk_bloodied", kind = "spellskin", icon = 2156, line = "monk", source = "store", price = 250,
			name = "Bloodied Knuckles", desc = "Hollow Knuckle strikes in red, Chi Lance and Thousand-Echo Palm send a wave of blood.",
			spells = {82, 87, 172}, vfx = {punch_hit_violet = "punch_hit_red"}, fx = {shockwave = "blood_nova"}},
		{id = 25, key = "skin_necro_gravefire", kind = "spellskin", icon = 7762, line = "necromancer", source = "store", price = 250,
			name = "Gravefire", desc = "Blightbrand burns with grave-light, not venom.",
			spells = {113}, fx = {poison_flame = "shadow_flame"}},
		{id = 26, key = "skin_necro_rift", kind = "spellskin", icon = 2153, line = "necromancer", source = "store", price = 250,
			name = "Wail of the Rift", desc = "Soulrend Beam opens a rift of arcane light.",
			spells = {118}, fx = {void_eye = "summon_portal"}},
		{id = 27, key = "skin_necro_pale", kind = "spellskin", icon = 2147, line = "necromancer", source = "store", price = 250,
			name = "Pale Wail", desc = "Gravewail sends a ring of shadow instead of blood.",
			spells = {112}, fx = {blood_nova = "shadow_ring"}}
	}
}
