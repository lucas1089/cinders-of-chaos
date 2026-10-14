-- chaos_theme_art.lua: the themed art of client pair things_custom24 on the server side, behind one switch.
-- Loaded with  ChaosThemeArt = dofile("data/lib/chaos_theme_art.lua")  (transmog_config.lua and exclusives_config.lua
-- do so at their end). Plain Lua, no engine calls at load (server/tests/theme_art_test.lua reads it with plain Lua).
--
-- Pair switch (M.PAIR24, ON since 2026-10-13: things_custom24 is on windows-assets at 407ad9b6, owner approved): a
-- client on an older pair draws nothing for client items 33660..33903 and outfits 2185..2193. Rollback: set it to
-- false. While it is off nothing in the game
-- names them: the transmog catalogue skips the item ids (an excludeRange, so installed items do not count in the
-- collection), no transmog set, exclusive or ground helper returns them, and install_auras.py / install_outfits.py
-- leave the aura and wings lines out of auras.xml / wings.xml.
--
-- What it holds (art: client/tools/sprites/gen_theme_art.py; client/MANIFEST.md "Themed sets, auras and grounds"):
--   * ten equipment sets of appearance items (server ids 36660..36851, data/lib/chaos_theme_items.lua, installed by
--     server/tools/install_theme_items.py): transmog appearance sets, one per full set and one per class kit of the
--     four kit sets. Twelve sold in the store's weekly rotation, six prestige achievement rewards (M.sets).
--   * two auras and a pair of wings: visual exclusives (boss drops) appended to exclusives_config.lua when on.
--   * four grounds with their border pieces (36852..36903): M.ground(family, piece, fallback), like ChaosDarkTiles.id.
--   * six recolour variants of rift minion looks (outfits 2188..2193): M.looks, for monster files of a later step.

local M = {}

M.PAIR24 = true

local ok, items = pcall(dofile, "data/lib/chaos_theme_items.lua")
M.items = ok and items or {first = 36660, last = 36903, pieces = {}, grounds = {}}

-- set names and lines for the transmog window (keys = the set keys of the art)
-- Sources (owner approval 2026-10-13, "Pode fazer todas as mudanças recomendadas"): twelve sets are sold, only in the
-- store's weekly rotation ("This week", shop_config.lua storefront.featured; M.storeOffers builds their hidden offers),
-- six stay prestige rewards of hard achievements (never sold). PLACEHOLDER PRICES (docs/OWNER_TODO.md): 350 a full set
-- (13 looks), 250 a class kit. A kit set may give each kit its own source (kitSources).
M.sets = {
	{key = "cryptbone", name = "Cryptbone", desc = "Bone and grave iron lit by green soul fire.", source = "store", price = 350},
	{key = "voidmourn", name = "Voidmourn", desc = "Black rift steel; blue light leaks from every seam.",
		source = "achievement", achievement = "cinder_1", how = "Prestige: extinguish the Cinderheart"},
	{key = "wildroot", name = "Wildroot", desc = "Living wood, bark and leaf of the old groves, bound in bronze.",
		source = "store", price = 350},
	{key = "moonsilver", name = "Moonsilver", desc = "Pale silver and night-blue cloth under a crescent moon.",
		source = "store", price = 350},
	{key = "sunsworn", name = "Sunsworn", desc = "Gold and crimson of a sun cult, a ruby at every heart.",
		source = "achievement", achievement = "level_1000", how = "Prestige: reach level 1000"},
	{key = "oathsteel", name = "Oathsteel", desc = "Plain steel and a red cross of the oathbound crusaders.",
		source = "achievement", achievement = "ascended_all", how = "Prestige: defeat every Ascended Omen"},
	{key = "rimeglass", name = "Rimeglass", desc = "Blue glacier crystal that never melts.", kits = true, source = "store",
		price = 250},
	{key = "emeraldine", name = "Emeraldine", desc = "Royal gold set with cut emeralds.", kits = true, source = "store",
		price = 250},
	{key = "starwing", name = "Starwing", desc = "Winged gold of the sky wardens, teal star stones.", kits = true,
		kitSources = {
			melee = {source = "achievement", achievement = "raid_first", how = "Prestige: first clear of the Ashen Sepulchre"},
			caster = {source = "achievement", achievement = "trial_merciless", how = "Prestige: a Merciless Vocation Trial"},
			ranged = {source = "achievement", achievement = "rift_t15", how = "Prestige: seal a tier 15 rift"}
		}},
	{key = "thornwild", name = "Thornwild", desc = "Green leaf armour on orange heartwood.", kits = true, source = "store",
		price = 250}
}
M.kits = {
	{key = "melee", name = "Warplate"},
	{key = "caster", name = "Vestments"},
	{key = "ranged", name = "Hunter's Garb"}
}
-- the kinds a transmog look can be (transmog_config.lua kinds: weapons by type, armour by slot); amulets, rings,
-- backpacks, arrows and bolts have no transmog kind and stay out of the sets
M.transmogKinds = {sword = true, axe = true, club = true, bow = true, crossbow = true, wand = true, rod = true,
	shield = true, spellbook = true, helmet = true, armor = true, legs = true, boots = true}

-- the visual exclusives (exclusives_config.lua format; install_outfits.py reads the wings line from this file when the
-- switch is on), and the boss groups that roll them
M.exclusives = {
	{key = "aura_bloodvortex", kind = "aura", id = 31, look = 2185, icon = 2156, source = "boss",
		name = "Blood Vortex", desc = "Three streams of blood spiral round your feet."},
	{key = "aura_runeseal", kind = "aura", id = 32, look = 2186, icon = 2192, source = "boss",
		name = "Rune Seal", desc = "A pale seal of turning runes glows under you."},
	{key = "wings_runic", kind = "wings", id = 20, look = 2187, icon = 2363, source = "boss",
		name = "Runic Wings", desc = "Pale feathered wings with glowing blue runes."}
}
M.bossRewards = {vharok = "aura_bloodvortex", skaldra = "aura_runeseal", kaelgor = "wings_runic"}

-- recolour variants of shipped rift minion looks (client/tools/sprites/art_import/theme_recolour.csv)
M.looks = {
	crypt_minion_frost = 2188, crypt_minion_venom = 2189, crypt_minion_void = 2190,
	obsidian_minion_frost = 2191, obsidian_minion_venom = 2192, obsidian_minion_void = 2193
}

function M.setName(set, kit)
	for _, s in ipairs(M.sets) do
		if s.key == set then
			if kit and kit ~= "" then
				for _, k in ipairs(M.kits) do
					if k.key == kit then
						return s.name .. " " .. k.name
					end
				end
			end
			return s.name
		end
	end
	return set
end

-- the source fields of a set (or of one kit of a kit set): {source, price, achievement, how}
function M.sourceOf(set, kit)
	local d
	for _, x in ipairs(M.sets) do
		if x.key == set then
			d = x
		end
	end
	local src = d and d.kitSources and kit and d.kitSources[kit] or d
	if not src or not src.source then
		return {source = "exclusive"}
	end
	return {source = src.source, price = src.price, achievement = src.achievement, how = src.how}
end

-- the transmog appearance sets (transmog_config.lua `sets` format): one per full set, one per kit of a kit set
function M.transmogSets()
	local out, byKey = {}, {}
	for _, p in ipairs(M.items.pieces or {}) do
		if M.transmogKinds[p.kind] then
			local key = "theme_" .. p.set .. (p.kit ~= "" and ("_" .. p.kit) or "")
			local s = byKey[key]
			if not s then
				local desc
				for _, d in ipairs(M.sets) do
					if d.key == p.set then
						desc = d.desc
					end
				end
				local src = M.sourceOf(p.set, p.kit ~= "" and p.kit or nil)
				s = {key = key, name = M.setName(p.set, p.kit), source = src.source, price = src.price,
					achievement = src.achievement, how = src.how, desc = desc or "", looks = {}}
				byKey[key] = s
				out[#out + 1] = s
			end
			s.looks[#s.looks + 1] = p.id
		end
	end
	return out
end

-- the store offers of the sold sets (shop_config.lua: a hidden category, shown only through the weekly rotation);
-- empty while the switch is off. icon = the set's first look (its server id).
function M.storeOffers()
	local out = {}
	if not M.PAIR24 then
		return out
	end
	for _, s in ipairs(M.transmogSets()) do
		if s.source == "store" then
			out[#out + 1] = {kind = "unlock", unlock = "transmog_" .. s.key, icon = s.looks[1], cost = s.price,
				name = s.name, gift = false, description = s.desc .. " Appearance set (" .. #s.looks ..
				" looks), account-wide. Character > Transmog."}
		end
	end
	return out
end

-- transmog_config.lua calls this on its table: the sets when on; else the item ids out of the catalogue
function M.addTransmog(cfg)
	if M.PAIR24 then
		for _, s in ipairs(M.transmogSets()) do
			cfg.sets[#cfg.sets + 1] = s
		end
	else
		cfg.excludeRanges = cfg.excludeRanges or {}
		cfg.excludeRanges[#cfg.excludeRanges + 1] = {M.items.first, M.items.last}
	end
	return cfg
end

-- exclusives_config.lua calls this on its table: the auras and wings and their boss groups, only when on
function M.addExclusives(cfg)
	if not M.PAIR24 then
		return cfg
	end
	for _, e in ipairs(M.exclusives) do
		cfg.exclusives[#cfg.exclusives + 1] = e
	end
	for _, b in ipairs(cfg.bosses or {}) do
		local key = M.bossRewards[b.key]
		if key then
			b.rewards[#b.rewards + 1] = key
		end
	end
	return cfg
end

-- a ground or border piece of a family ("swamp", "acid", "lava", "water"; piece nil = the ground, else "n", "e",
-- "s", "w", "outer_ne" ... "inner_sw", named by where the family lies); `fallback` while off or not installed
function M.ground(family, piece, fallback)
	if not M.PAIR24 then
		return fallback
	end
	local f = M.items.grounds and M.items.grounds[family]
	local id = f and f[piece or "ground"]
	if not id then
		return fallback
	end
	if ItemType and ItemType(id):getId() == 0 then
		return fallback
	end
	return id
end

return M
