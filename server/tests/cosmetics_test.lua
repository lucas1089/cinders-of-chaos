-- Run from the server/ folder: luajit tests/cosmetics_test.lua (and lua5.3; CI runs both)
-- Cosmetics (cosmetics_core.lua, cosmetics_config.lua, cosmetics_store.lua, cosmetics.lua, the skin hook of
-- data/spells/chaos/_common.lua): the shipped config against the real effect catalogues of the client pair (every swap
-- is a recolour inside one family, every variant exists), the spells of each line, the achievements, the store
-- categories, readable colours; ownership, choosing, the spell skin lookup; then cosmetics.lua on a mocked engine
-- (store unlock, choosing, the cast hook, kill effects on the killing blow only, chat name colours for everybody, the
-- label accent, previews to the asking player only) and _common.lua's swap during a cast with the default fallback.
CONST_ME_FIREWORK_YELLOW = CONST_ME_FIREWORK_YELLOW or 29 -- shop_config.lua reads it
dofile("data/scripts/chaos/chaos_constants.lua")
dofile("data/scripts/chaos/cosmetics_core.lua")
local K = ChaosCosmeticsCore
local cfg = dofile("data/scripts/chaos/cosmetics_config.lua")
local shop = dofile("data/scripts/chaos/shop_config.lua")
local achievementsData = dofile("data/scripts/chaos/achievements_data.lua")

local n = 0
local function eq(a, b, m)
	n = n + 1
	if a ~= b then
		error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2)
	end
end

local function readFile(path)
	local f = io.open(path, "r")
	if not f then
		return nil
	end
	local s = f:read("*a")
	f:close()
	return s
end

-- ---------------------------------------------------------------- the client pair's effects (catalogues)
local function csv(path)
	local rows, header = {}, nil
	for line in (readFile(path) or ""):gmatch("[^\r\n]+") do
		local cells, i = {}, 1
		-- simple CSV: quoted cells may hold commas
		while i <= #line do
			if line:sub(i, i) == '"' then
				local j = line:find('"', i + 1, true)
				cells[#cells + 1] = line:sub(i + 1, j - 1)
				i = j + 2
			else
				local j = line:find(",", i, true) or (#line + 1)
				cells[#cells + 1] = line:sub(i, j - 1)
				i = j + 1
			end
		end
		if not header then
			header = cells
		else
			local row = {}
			for k, h in ipairs(header) do
				row[h] = cells[k]
			end
			rows[#rows + 1] = row
		end
	end
	return rows
end
local catalog = {fx = {}, missile = {}, vfx = {}, vmissile = {}}
local style, size = {fx = {}, missile = {}}, {vfx = {}, vmissile = {}}
for _, r in ipairs(csv("data/spells/effects_catalog.csv")) do
	local t = r.category == "missile" and "missile" or "fx"
	catalog[t][r.name] = true
	style[t][r.name] = r.style
end
for _, path in ipairs({"data/spells/vfx_catalog.csv", "data/spells/vfx_art_catalog.csv"}) do
	for _, r in ipairs(csv(path)) do
		local t = r.kind == "missile" and "vmissile" or (r.kind == "effect" and "vfx" or nil)
		if t then
			catalog[t][r.name] = true
			size[t][r.name] = r.size .. "/" .. r.frames
		end
	end
end
eq(catalog.vfx.aura_burst_god, true, "the catalogue was read")
eq(catalog.fx.shadow_ring, true, "the procedural catalogue was read")

-- a recolour family is one picture: the same style (procedural) or the same size and frame count (pack effects)
for t, fams in pairs(cfg.families) do
	for fam, members in pairs(fams) do
		local first
		for _, m in ipairs(members) do
			local shape = (style[t] or size[t])[m]
			eq(shape ~= nil, true, t .. " " .. m .. " is in the pair")
			first = first or shape
			eq(shape, first, "family " .. t .. "." .. fam .. ": " .. m .. " has the shape of the others")
		end
	end
end

-- spells of the lines (spells_chaos.xml): spell id -> {[vocation] = true}
local spellVocations = {}
local xml = readFile("data/spells/chaos/spells_chaos.xml")
for attrs, body in xml:gmatch("<instant ([^>]-)>(.-)</instant>") do
	local id = tonumber(attrs:match('spellid="(%d+)"'))
	if id then
		spellVocations[id] = {}
		for v in body:gmatch('vocation name="([^"]+)"') do
			spellVocations[id][v] = true
		end
	end
end
local achievements = {}
for _, a in ipairs(achievementsData.list) do
	achievements[a.id] = a.name
end

-- ---------------------------------------------------------------- the shipped config
local problems, warnings = K.validate(cfg, {catalog = catalog, achievements = achievements, shop = shop,
	spellVocations = spellVocations})
for _, p in ipairs(problems) do
	print("problem: " .. p)
end
for _, w in ipairs(warnings) do
	print("note: " .. w)
end
eq(#problems, 0, "shipped config validates")
eq(#warnings, 0, "every store cosmetic is sold")
eq(cfg.opcode, ChaosOpcodes.cosmetics, "opcode in chaos_constants.lua")
local usedOpcodes = {}
for name, op in pairs(ChaosOpcodes) do
	eq(usedOpcodes[op], nil, "opcode " .. op .. " used once (" .. name .. ")")
	usedOpcodes[op] = name
end
-- storages in the Chaos range, inside the reserved block, distinct
local st, seen = cfg.storage, {}
for _, key in ipairs({st.killfx, st.lootbeam, st.chatcolor}) do
	eq(key >= 7100940 and key <= 7100949 and not seen[key], true, "storage " .. key)
	seen[key] = true
end
for _, l in ipairs(cfg.lines) do
	local key = st.skinBase + l.slot
	eq(key >= 7100940 and key <= 7100949 and not seen[key], true, "line storage " .. key)
	seen[key] = true
end

-- counts and prices (README "Cosmetics")
local count, store = {}, {}
for _, c in ipairs(cfg.cosmetics) do
	count[c.kind] = (count[c.kind] or 0) + 1
	if c.source == "store" then
		store[c.kind] = store[c.kind] or c.price
		eq(c.price, store[c.kind], "one price per kind: " .. c.key)
	end
end
eq(count.spellskin, 12, "12 spell skins")
eq(count.killfx, 20, "20 kill effects (the Cinderheart Crown of uber.lua, Sovereign's Pyre of raid.lua, three PvP, 8 reward track)")
eq(count.lootbeam, 12, "12 label accents (three PvP, 4 reward track)")
eq(count.chatcolor, 14, "14 chat colours (three PvP, 5 reward track)")
eq(store.spellskin, 250, "skins 250") eq(store.killfx, 200, "kill effects 200")
eq(store.lootbeam, 150, "label accents 150") eq(store.chatcolor, 200, "chat colours 200")
eq(count.footprint, 13, "13 footprints (9 store, an achievement, the reward track, two boss drops)")
eq(count.outline, 13, "13 outlines (9 store, an achievement, the reward track, two boss drops)")
eq(store.footprint, 200, "footprints 200") eq(store.outline, 250, "outlines 250")
-- every line but the Necromancer's has 2-3 skins of 2-3 spells
for _, l in ipairs(cfg.lines) do
	local skins = K.index(cfg).skinsOfLine[l.key]
	eq(#skins >= 1 and #skins <= 3, true, l.key .. ": skins")
end

-- the validator refuses what is not a recolour, unknown effects, power, unreadable colours, a wrong store price
local function broken(change)
	local copy = {}
	for k, v in pairs(cfg) do
		copy[k] = v
	end
	copy.cosmetics = {}
	for i, c in ipairs(cfg.cosmetics) do
		local cc = {}
		for k, v in pairs(c) do
			cc[k] = v
		end
		copy.cosmetics[i] = cc
	end
	change(copy.cosmetics)
	local p = K.validate(copy, {catalog = catalog, achievements = achievements, shop = shop, spellVocations = spellVocations})
	return table.concat(p, "\n")
end
eq(broken(function(l) l[1].vfx = {aura_burst_gold = "dome_blast_fire"} end):find("not a recolour", 1, true) ~= nil, true,
	"another picture is refused")
eq(broken(function(l) l[1].fx = {blood_rune = "no_such_rune"} end):find("not a recolour", 1, true) ~= nil, true,
	"an unknown variant is refused")
eq(broken(function(l) l[1].damage = 10 end):find("not cosmetic", 1, true) ~= nil, true, "power is refused")
eq(broken(function(l) l[1].spells = {200} end):find("not a spell of", 1, true) ~= nil, true, "a spell of another line")
eq(broken(function(l) l[1].spells = {223, 222, 247, 220} end):find("1 to 3 spells", 1, true) ~= nil, true, "3 spells at most")
eq(broken(function(l) l[13].vfx = "no_such_effect" end):find("not an effect", 1, true) ~= nil, true, "kill effect unknown")
eq(broken(function(l) l[20].accent = "#c0c0c0f0" end):find("unreadable", 1, true) ~= nil, true, "a light accent")
eq(broken(function(l) l[20].accent = "#46180940" end):find("transparent", 1, true) ~= nil, true, "a see-through accent")
eq(broken(function(l) l[25].color = "#303030" end):find("not readable", 1, true) ~= nil, true, "a dark chat colour")
eq(broken(function(l) l[1].price = 999 end):find("store price", 1, true) ~= nil, true, "price mismatch with the store")
eq(broken(function(l) l[18].achievement = "nope" end):find("does not exist", 1, true) ~= nil, true, "unknown achievement")
eq(broken(function(l) l[2].id = 1 end):find("used twice", 1, true) ~= nil, true, "id twice")

-- colours: contrast maths
eq(math.floor(K.contrast("#ffffff", "#000000") + 0.5), 21, "white on black is 21")
eq(K.contrast("#123456", "#123456"), 1, "same colour is 1")
eq(K.contrast("nope", "#000000"), nil, "bad colour")

-- ---------------------------------------------------------------- the store categories (cosmetics_store.lua)
local cats = {}
for _, c in ipairs(shop.categories) do
	cats[c.name] = c
end
for _, k in ipairs(cfg.kinds) do
	local cat = cats[k.store]
	eq(cat ~= nil, true, "store category " .. k.store)
	for _, o in ipairs(cat.offers) do
		local c = K.ofUnlock(cfg, o.unlock)
		eq(c ~= nil and c.kind == k.key, true, "offer " .. o.unlock .. " is a " .. k.key)
		eq(o.gift, false, "not giftable (unlocks run on the buyer)")
		eq(type(o.icon), "number", "icon")
		eq(#o.description <= 140, true, "description fits the offer: " .. o.unlock)
	end
end
eq(K.ofUnlock(cfg, "cosmetic_kill_voidring"), nil, "an achievement cosmetic is no store unlock")
eq(K.ofUnlock(cfg, "transmog_falconer"), nil, "other unlocks are not ours")
eq(cats["Name Plates"] ~= nil and #cats["Name Plates"].offers, 13, "13 frames in the store")
-- the transmog store sets (follow-up): offers at the sets' prices
local tm = {}
for _, o in ipairs(cats["Appearances"].offers) do
	tm[o.unlock] = o.cost
end
eq(tm.transmog_falconer, 300, "Falconer's Regalia 300") eq(tm.transmog_lionguard, 350, "Lionguard 350")
-- every store and exclusive frame exists everywhere a frame must (shop_core.lua FRAMES is shop.lua's list)
dofile("data/scripts/chaos/nameplate_core.lua")
dofile("data/scripts/chaos/shop_core.lua")
local framesSold = {}
for _, o in ipairs(cats["Name Plates"].offers) do
	framesSold[o.frame] = true
end
for i, f in ipairs(ChaosShopCore.FRAMES) do
	eq(ChaosNameplate.FRAMES[f], true, "nameplate_core frame " .. f)
	eq(readFile("../client/overlay/modules/game_nameplate/images/plate_" .. f .. ".png") ~= nil, true, "art plate_" .. f)
	eq(ChaosShopCore.frameStorage(Chaos.storage, i) ~= nil, true, "a storage slot for " .. f)
	eq(framesSold[f] == true, i <= 13, f .. ": the first 13 are sold, the exclusives never")
end
for f in pairs(framesSold) do
	eq(ChaosShopCore.frameIndex(f) ~= nil, true, "shop_core.lua FRAMES has " .. f)
end
eq(ChaosShopCore.frameStorage(Chaos.storage, 8), 7100768, "slot 8 in the first block")
eq(ChaosShopCore.frameStorage(Chaos.storage, 9), 7102010, "slot 9 in the wardrobe block")
eq(ChaosShopCore.frameStorage(Chaos.storage, 39), nil, "past the block")
-- the store unlock hooks of shop_services.lua
local services = readFile("data/scripts/chaos/shop_services.lua")
eq(services:find("ChaosTransmog.storeUnlock(name)", 1, true) ~= nil, true, "unlockEntry asks the transmog sets")
eq(services:find("ChaosCosmetics.storeUnlock(name)", 1, true) ~= nil, true, "unlockEntry asks the cosmetics")

-- ---------------------------------------------------------------- Chaos outfit shaders (cfg.outfitShaders, off)
do
	local os_ = cfg.outfitShaders
	eq(os_.enabled, false, "the outfit shaders ship switched off")
	eq(#os_.list, 6, "six outfit shaders")
	local ids, priced = {}, 0
	for _, s in ipairs(os_.list) do
		ids[s.shaderId] = true
		priced = priced + (s.price and 1 or 0)
	end
	eq(priced, 0, "store-ready but unpriced (the owner decides)")
	for id = 19, 24 do
		eq(ids[id], true, "shaders.xml id " .. id)
	end
	-- off: nothing listed, granted, sold or added
	eq(#K.outfitShaderList(cfg), 0, "off: no list")
	eq(K.outfitShaderByKey(cfg, "shader_ember_glow"), nil, "off: no key")
	eq(#K.outfitShaderIds(cfg, {shader_ember_glow = true}), 0, "off: an owned one is not added")
	eq(#K.outfitShaderRows(cfg, {}), 0, "off: no Collection rows")
	eq(#dofile("data/scripts/chaos/cosmetics_store.lua")("outfitshader").offers, 0, "off: no store offers")
	-- the client registers every shader name (game_chaosshaders) and has its fragment file
	local client = readFile("../client/overlay/modules/game_chaosshaders/chaosshaders.lua") or ""
	local clientShaders = {}
	for name, frag in client:gmatch('{ "([%w_ ]+)", "/shaders/[%w_]+", "/shaders/([%w_]+)" }') do
		clientShaders[name] = frag
	end
	for _, s in ipairs(os_.list) do
		eq(clientShaders[s.shader] ~= nil, true, s.shader .. " registered by the client")
		eq(readFile("../client/overlay/data/shaders/" .. (clientShaders[s.shader] or "?") .. ".frag") ~= nil, true,
			s.shader .. ": its fragment file")
	end
	-- no shaders.xml id of the exclusives or the store's shader offers
	local taken = {}
	for _, cat in ipairs(shop.categories) do
		for _, o in ipairs(cat.offers or {}) do
			if o.kind == "shader" then taken[o.id] = true end
		end
	end
	for _, line in ipairs({readFile("data/scripts/chaos/exclusives_config.lua") or ""}) do
		for id in line:gmatch('kind = "shader", id = (%d+)') do taken[tonumber(id)] = true end
	end
	eq(#K.validateOutfitShaders(cfg, {clientShaders = clientShaders, takenShaderIds = taken}), 0, "the shipped list is valid")
	-- switched on (a copy): listed, owned ids, rows in the Collection format, only priced ones sold
	local on = {cosmetics = cfg.cosmetics, outfitShaders = {enabled = true, list = {}}}
	for i, s in ipairs(os_.list) do
		local c = {}
		for k, v in pairs(s) do c[k] = v end
		on.outfitShaders.list[i] = c
	end
	on.outfitShaders.list[1].price = 300
	eq(#K.outfitShaderList(on), 6, "on: listed")
	eq(K.outfitShaderByKey(on, "shader_frost_rime").shaderId, 20, "on: by key")
	local owned = K.outfitShaderIds(on, {shader_frost_rime = true, shader_spectral_ghost = true, kill_sunring = true})
	eq(#owned, 2, "on: the owned ones only") eq(owned[1], 20, "frost id") eq(owned[2], 24, "ghost id")
	local rows = K.outfitShaderRows(on, {shader_frost_rime = true})
	eq(#rows, 6, "on: six Collection rows") eq(rows[2].owned, true, "owned row") eq(rows[1].owned, nil, "missing row")
	eq(rows[2].kind, "shader", "shown like a shader exclusive") eq(rows[2].with, "shader", "on the character's outfit")
	eq(rows[2].shader, "chaos_frost_rime", "the shader's name") eq(rows[1].how, "Store: 300 Chaos Coins", "priced how")
	eq(rows[2].how, "Store: not on sale yet", "unpriced how")
	eq(K.outfitShaderOfUnlock(on, "cosmetic_shader_ember_glow").shaderId, 19, "a priced one is a store unlock")
	eq(K.outfitShaderOfUnlock(on, "cosmetic_shader_frost_rime"), nil, "an unpriced one is not")
	eq(K.outfitShaderOfUnlock(cfg, "cosmetic_shader_ember_glow"), nil, "off: not a store unlock")
	-- the validator
	local function badShaders(change)
		local c = {cosmetics = cfg.cosmetics, outfitShaders = {enabled = false, list = {}}}
		for i, s in ipairs(os_.list) do
			local cc = {}
			for k, v in pairs(s) do cc[k] = v end
			c.outfitShaders.list[i] = cc
		end
		change(c.outfitShaders.list, c)
		return table.concat(K.validateOutfitShaders(c, {clientShaders = clientShaders, takenShaderIds = taken}), "\n")
	end
	eq(badShaders(function(l) l[2].shaderId = 19 end):find("used twice", 1, true) ~= nil, true, "id twice")
	eq(badShaders(function(l) l[1].shaderId = 16 end):find("19..255", 1, true) ~= nil, true, "a base / exclusive id")
	eq(badShaders(function(l) l[1].shader = "chaos_nope" end):find("not registered", 1, true) ~= nil, true, "unknown to the client")
	eq(badShaders(function(l) l[1].key = "kill_sunring" end):find("key used twice", 1, true) ~= nil, true, "a cosmetic's key")
	eq(badShaders(function(l) l[1].price = 0 end):find("price", 1, true) ~= nil, true, "a zero price")
	eq(badShaders(function(l) l[1].damage = 5 end):find("not cosmetic", 1, true) ~= nil, true, "power")
	eq(badShaders(function(l, c) c.outfitShaders.enabled = "yes" end):find("enabled = true / false", 1, true) ~= nil, true,
		"the switch is a boolean")
end

-- ---------------------------------------------------------------- core rules
local owned = {skin_warrior_void = true, kill_soulspark = true, chat_frost = true}
eq(K.owns(owned, K.byKey(cfg, "kill_soulspark")), true, "owned")
eq(K.owns(owned, K.byKey(cfg, "kill_sunring")), false, "not owned")
local c, why = K.choose(cfg, owned, "killfx", 102)
eq(c, nil, "not owned: refused") eq(why:find("Store > Kill Effects", 1, true) ~= nil, true, "where to get it")
eq(K.choose(cfg, owned, "killfx", 101).key, "kill_soulspark", "owned: chosen")
eq(K.choose(cfg, owned, "killfx", 0), false, "0 = the default")
eq(K.choose(cfg, owned, "chatcolor", 101), nil, "an id of another kind")
eq(K.choose(cfg, owned, "stats", 1), nil, "unknown kind")
c, why = K.choose(cfg, owned, "killfx", 106)
eq(why, "Void Ring is not unlocked yet.", "achievement cosmetic text")
-- the achievement syncs
local syncs = K.syncs(cfg, function(id) return id == "level_300" or id == "goblin_10" end, {loot_gilded = true})
eq(#syncs, 1, "one to grant") eq(syncs[1], "chat_veteran", "Veteran's Gold")
-- footprints and outlines from achievements and the track; boss ones only through exclusives.lua
syncs = K.syncs(cfg, function(id) return id == "bounty_week_10" or id == "paragon_282" end, {}, {points = 2000})
local got = {}
for _, k in ipairs(syncs) do got[k] = true end
eq(got.foot_hunter and got.glow_absolute and got.foot_chronicle and got.glow_chronicle, true, "achievement and track looks")
eq(got.foot_rime or got.glow_cinder, nil, "boss looks are never synced")
eq(K.earned(K.byKey(cfg, "glow_corona"), function() return true end, {points = 99999}), false, "a boss look is never earned")
eq(K.how(K.byKey(cfg, "glow_cinder")), "Boss: Ysgrath the Cinderheart", "boss line of the window")
c, why = K.choose(cfg, {}, "outline", 554)
eq(why, "Cinderheart Blaze is not unlocked yet.", "a boss outline not owned")
eq(K.choose(cfg, {glow_cinder = true}, "outline", 554).art, "cinder", "owned: chosen")
eq(K.choose(cfg, {glow_cinder = true}, "footprint", 554), nil, "an outline is no footprint")
local fp = K.offerPreview(K.byKey(cfg, "foot_ember"))
eq(fp.effect, true, "footprints: the SHOW button") eq(fp.color, "#ff8a3a", "and the swatch colour")
eq(K.storageOf(cfg, "footprint"), 7102000, "footprint storage") eq(K.storageOf(cfg, "outline"), 7102001, "outline storage")
eq(K.storageOf(cfg, "footprint"), Chaos.storage.wardrobe, "the wardrobe block of chaos_constants.lua")

-- ---------------------------------------------------------------- the reward track (achievement points, categories)
dofile("data/scripts/chaos/achievements_core.lua")
local AK = ChaosAchievementsCore
local aIndex = AK.build(achievementsData)
local catSet = {}
for _, cat in ipairs(achievementsData.categories) do
	catSet[cat.key] = true
end
local trackProblems = K.validate(cfg, {achievements = achievements, categories = catSet, maxPoints = AK.maxPoints(aIndex)})
eq(#trackProblems, 0, "the reward track validates: " .. table.concat(trackProblems, "; "))
local steps = K.trackSteps(cfg)
local milestones = {100, 250, 500, 750, 1000, 1750, 2000, 2500, 3500}
eq(#steps, #milestones, "nine point milestones (750 Inkstep footprints, 2000 Chronicler's Halo outline)")
for i, p in ipairs(milestones) do
	eq(steps[i].points, p, "milestone " .. i)
	eq(steps[i].cosmetic.source, "achievement", "milestone " .. p .. " is an achievement cosmetic")
end
eq(steps[#steps].points <= AK.maxPoints(aIndex), true, "the last milestone can be reached")
for _, cat in ipairs(achievementsData.categories) do
	local cc = K.categoryCosmetic(cfg, cat.key)
	eq(cc ~= nil and cc.source == "achievement", true, "category " .. cat.key .. " gives a cosmetic")
	eq(aIndex.categoryRewards[cat.key] ~= nil, true, "category " .. cat.key .. " gives a title")
end
-- never sold: no price, no store unlock, in no store category (shop_config.lua and cosmetics_store.lua)
local storeGen = dofile("data/scripts/chaos/cosmetics_store.lua")
local offered = {}
for _, cat in ipairs(shop.categories) do
	for _, o in ipairs(cat.offers or {}) do
		offered[o.unlock or ""] = true
	end
end
for _, k in ipairs(cfg.kinds) do
	for _, o in ipairs(storeGen(k.key).offers) do
		offered[o.unlock] = true
	end
end
local trackCount = 0
for _, tc in ipairs(cfg.cosmetics) do
	if tc.points or tc.category then
		trackCount = trackCount + 1
		eq(tc.source, "achievement", tc.key .. ": source achievement")
		eq(tc.price, nil, tc.key .. ": no price")
		eq(K.ofUnlock(cfg, K.unlockName(tc)), nil, tc.key .. ": no store unlock")
		eq(offered[K.unlockName(tc)], nil, tc.key .. ": not in the store")
	end
end
eq(trackCount, 19, "19 reward track cosmetics (9 milestones, 10 categories)")
-- the last category cosmetic of the list (Falling Stars)
local function starfall(l)
	for _, c in ipairs(l) do
		if c.key == "kill_starfall" then
			return c
		end
	end
end
eq(broken(function(l) starfall(l).price = 100 end):find("no price", 1, true) ~= nil, true, "a priced track cosmetic is refused")
eq(broken(function(l) starfall(l).points = 100 end):find("one of achievement, points or category", 1, true) ~= nil, true,
	"one way to earn it")
-- footprints and outlines: art of the client's list, one per cosmetic, pulse for outlines only, boss ones named
local function byKeyIn(l, key)
	for _, c in ipairs(l) do
		if c.key == key then
			return c
		end
	end
end
eq(broken(function(l) byKeyIn(l, "foot_ember").art = "nope" end):find("art nope is not in cfg.prints", 1, true) ~= nil, true,
	"unknown print art")
eq(broken(function(l) byKeyIn(l, "foot_ember").art = "frost" end):find("art frost used by", 1, true) ~= nil, true,
	"one picture per footprint")
eq(broken(function(l) byKeyIn(l, "foot_ember").pulse = true end):find("only for outlines", 1, true) ~= nil, true,
	"a footprint does not pulse")
eq(broken(function(l) byKeyIn(l, "glow_cinder").boss = nil end):find("needs the boss's name", 1, true) ~= nil, true,
	"a boss cosmetic names its boss")
eq(broken(function(l) byKeyIn(l, "glow_cinder").price = 300 end):find("a boss cosmetic has no price", 1, true) ~= nil, true,
	"a boss cosmetic is never sold")
eq(table.concat(K.validate(cfg, {maxPoints = 3000}), "\n"):find("above the 3000", 1, true) ~= nil, true,
	"an unreachable milestone is refused")
eq(table.concat(K.validate(cfg, {categories = {combat = true}}), "\n"):find("category rifts does not exist", 1, true) ~= nil,
	true, "an unknown category is refused")
-- thresholds: granted at the milestone, not before
local function track(points, cats, have)
	return K.syncs(cfg, function() return false end, have or {}, {points = points, categories = cats or {}})
end
eq(#track(0), 0, "0 points: nothing") eq(#track(99), 0, "99 points: nothing")
eq(#track(100), 1, "100 points: one") eq(track(100)[1], "chat_ashen", "Ashen Name at 100")
eq(#track(999), 4, "999 points: four") eq(#track(1000), 5, "1000 points: five")
eq(#track(AK.maxPoints(aIndex)), 9, "every milestone at the maximum")
-- idempotent: what the account owns is not granted again; never taken back (fewer points grant nothing, revoke nothing)
local have = {}
for _, key in ipairs(track(1000)) do
	have[key] = true
end
eq(#track(1000, nil, have), 0, "a second sync grants nothing")
eq(#track(1750, nil, have), 1, "the next milestone only") eq(track(1750, nil, have)[1], "kill_vortex", "Arcane Vortex at 1750")
eq(#track(0, nil, have), 0, "points went down: nothing to grant")
eq(K.owns(have, K.byKey(cfg, "chat_ashen")), true, "and nothing taken back")
-- category completion
eq(#track(0, {rifts = true}), 1, "one completed category: one cosmetic")
eq(track(0, {rifts = true})[1], "kill_riftsigil", "Rifts: Rift Sigil")
eq(#track(0, catSet), 10, "every category: ten")
eq(K.earned(K.byKey(cfg, "chat_veteran"), function(id) return id == "level_300" end), true, "an achievement cosmetic")
eq(K.earned(K.byKey(cfg, "kill_sunring"), function() return true end, {points = 99999}), false, "a store one is never earned")
eq(#K.syncs(cfg, function(id) return id == "level_300" end, {}), 1, "without track facts: the achievement cosmetics only")
-- the window's view (one message: fits an extended opcode)
local tv = K.trackView(cfg, 640, {chat_ashen = true, loot_chronicle = true, kill_riftsigil = true},
	AK.categoryTrack(aIndex, {rift_t1 = true}))
eq(tv.ap, 640, "account points") eq(#tv.steps, 9, "nine steps") eq(tv.steps[1].p, 100, "lowest first")
eq(tv.steps[4].k, "footprint", "750: footprints") eq(tv.steps[4].c, "#5cc8c0", "with the swatch colour")
eq(tv.steps[1].o, 1, "owned") eq(tv.steps[3].o, nil, "not owned") eq(tv.steps[1].c, "#cfc4b4", "the colour for the preview")
eq(tv.steps[2].a, "#0b2626f0", "the accent for the preview") eq(tv.steps[3].k, "killfx", "the kind")
eq(#tv.cats, #achievementsData.categories, "a row per category")
local rifts
for _, e in ipairs(tv.cats) do
	if e.key == "rifts" then
		rifts = e
	end
end
eq(rifts.dn, 1, "one rift achievement done") eq(rifts.ti, "Riftwarden", "the title") eq(rifts.n, "Rift Sigil", "the cosmetic")
eq(rifts.x, nil, "not complete") eq(rifts.o, 1, "owned anyway (granted before)")
local function jsonSize(v)
	if type(v) == "table" then
		local n = 2
		for k, x in pairs(v) do
			n = n + #tostring(k) + 4 + jsonSize(x)
		end
		return n
	end
	return #tostring(v) + 2
end
local fullView = K.trackView(cfg, 99999, {}, AK.categoryTrack(aIndex, {}))
eq(jsonSize({action = "track", data = fullView}) < 7000, true, "the track message fits one opcode (" ..
	jsonSize({action = "track", data = fullView}) .. ")")
-- spell skins: only the listed spells, only the swapped effects
local void = K.byKey(cfg, "skin_warrior_void")
eq(K.swap(void, 223, "vfx", "aura_burst_gold"), "aura_burst_violet", "Iron Bellow burst")
eq(K.swap(void, 223, "fx", "blood_rune"), "arcane_circle", "Iron Bellow rune")
eq(K.swap(void, 223, "fx", "aura_ring"), nil, "an effect the skin leaves alone")
eq(K.swap(void, 220, "vfx", "aura_burst_gold"), nil, "a spell the skin leaves alone")
eq(K.swap(void, 223, "missile", "aura_burst_gold"), nil, "another effect type")
local chosenLines = {warrior = 1}
eq(K.skinForSpell(cfg, 222, function(line) return chosenLines[line] end), void, "Red Frenzy uses the warrior skin")
eq(K.skinForSpell(cfg, 63, function(line) return chosenLines[line] end), nil, "the monk line has none chosen")
chosenLines.warrior = 8 -- a monk skin stored in the warrior slot is ignored
eq(K.skinForSpell(cfg, 222, function(line) return chosenLines[line] end), nil, "a skin of another line is ignored")
eq(K.lineOfVocation(cfg, "Iron Sage"), "monk", "Iron Sage is the monk line")
eq(K.lineOfVocation(cfg, "Lich"), nil, "the Necromancer line has no skins")
eq(K.storageOf(cfg, "spellskin", "templar"), 7100948, "templar slot storage")
eq(K.storageOf(cfg, "chatcolor"), 7100942, "chat colour storage")
-- previews
local pv = K.previewOf(K.byKey(cfg, "skin_mystic_voidfire"))
eq(#pv, 3, "Voidfire preview: three variants")
eq(K.previewOf(K.byKey(cfg, "kill_shatter"))[1].name, "ice_shatter", "kill effect preview")
eq(#K.previewOf(K.byKey(cfg, "chat_rose")), 0, "a colour has no effect preview")
eq(K.offerPreview(K.byKey(cfg, "chat_rose")).color, "#ff8fb0", "colour preview in the store")
eq(K.offerPreview(K.byKey(cfg, "loot_azure")).accent, "#0f2250f0", "accent preview in the store")
eq(K.offerPreview(K.byKey(cfg, "kill_shatter")).effect, true, "effect preview button")
-- window rows
local rows = K.rows(cfg, owned, {killfx = 101, lines = {warrior = 1}}, {line = "warrior",
	achievementName = function(id) return achievements[id] end})
eq(#rows, #cfg.cosmetics, "a row per cosmetic")
local byKey = {}
for _, r in ipairs(rows) do
	byKey[r.key] = r
end
eq(byKey.kill_soulspark.selected, true, "chosen kill effect") eq(byKey.skin_warrior_void.selected, true, "chosen skin")
eq(byKey.skin_warrior_void.mine, true, "the character's line") eq(byKey.skin_monk_void.mine, nil, "another line")
eq(byKey.kill_voidring.how, "Achievement: Legend's Bane", "how to get it")
eq(byKey.kill_sunring.how, "Store: 200 Chaos Coins", "store price")
eq(byKey.chat_ashen.how, "Achievements: 100 account points", "reward track: points")
eq(byKey.kill_riftsigil.how, "Achievements: complete rifts", "reward track: category (no name known)")
for _, r in ipairs(K.rows(cfg, owned, {}, {categoryName = function(key) return key == "rifts" and "Rifts" or nil end})) do
	if r.key == "kill_riftsigil" then
		eq(r.how, "Achievements: complete Rifts", "reward track: the category's name")
	end
end
eq(byKey.chat_frost.color, "#7fc8ff", "colour in the row")
-- SQL
eq(K.sqlInsert(cfg, 7, "kill';drop", "st;ore", 1):find("'killdrop', 'store'", 1, true) ~= nil, true, "keys sanitised")
eq(K.sqlSelect(cfg, "3 or 1"), "SELECT `cosmetic` FROM `chaos_cosmetics` WHERE `account_id` = 0", "account id numeric")
eq(readFile("sql/chaos_cosmetics.sql"):find("CREATE TABLE IF NOT EXISTS `chaos_cosmetics`", 1, true) ~= nil, true, "sql file")

-- ---------------------------------------------------------------- cosmetics.lua on a mocked engine
local inbox, seq = {}, 0
json = {
	encode = function(t)
		seq = seq + 1
		local k = "{J" .. seq .. "}"
		inbox[k] = t
		return k
	end,
	decode = function(s)
		return inbox[s]
	end
}
local effects, distance, sent = {}, {}, {}
Position = function(x, y, z)
	if type(x) == "table" then
		x, y, z = x.x, x.y, x.z
	end
	return {x = x, y = y, z = z,
		sendMagicEffect = function(self, id, only)
			effects[#effects + 1] = {x = self.x, y = self.y, id = id, only = only and only:getName() or nil}
		end,
		sendDistanceEffect = function(self, to, id, only)
			distance[#distance + 1] = {id = id, only = only and only:getName() or nil}
		end}
end
local storages, players = {}, {}
local function newPlayer(id, name, account, vocation)
	local p = {id = id, name = name, account = account, events = {}}
	storages[id] = storages[id] or {}
	function p:getId() return self.id end
	function p:getName() return self.name end
	function p:getAccountId() return self.account end
	function p:getGuid() return self.id end
	function p:isPlayer() return true end
	function p:getStorageValue(k) return storages[self.id][k] or -1 end
	function p:setStorageValue(k, v) storages[self.id][k] = v end
	function p:getVocation() return {getName = function() return vocation end} end
	function p:getPosition() return Position(100, 100, 7) end
	function p:registerEvent(e) self.events[e] = true end
	function p:getGroup() return {getId = function() return 1 end} end
	function p:sendTextMessage(_, text) sent[#sent + 1] = {to = self.name, text = text} end
	function p:sendExtendedOpcode(op, payload)
		sent[#sent + 1] = {to = self.name, op = op, msg = inbox[payload]}
	end
	players[id] = p
	return p
end
Player = function(id)
	if type(id) == "string" then
		for _, p in pairs(players) do
			if p.name == id then
				return p
			end
		end
		return nil
	end
	return players[id]
end
Game = {getPlayers = function()
	local out = {}
	for _, p in pairs(players) do
		out[#out + 1] = p
	end
	table.sort(out, function(a, b) return a.id < b.id end)
	return out
end}
local queries, rows = {}, {} -- rows[account] = {keys}
db = {query = function(q)
	queries[#queries + 1] = q
	local acc, key = q:match("VALUES %((%d+), '([%w_]+)'")
	if acc then
		rows[tonumber(acc)] = rows[tonumber(acc)] or {}
		table.insert(rows[tonumber(acc)], key)
	end
	return true
end, storeQuery = function(q)
	local acc = tonumber(q:match("`account_id` = (%d+)"))
	if acc and rows[acc] and #rows[acc] > 0 then
		return {acc = acc, i = 1}
	end
	return false
end, escapeString = function(s) return "'" .. s .. "'" end}
result = {
	getString = function(r) return rows[r.acc][r.i] end,
	next = function(r) r.i = r.i + 1; return r.i <= #rows[r.acc] end,
	free = function() end
}
local timers = {}
addEvent = function(fn, ms, ...)
	timers[#timers + 1] = {fn = fn, ms = ms, args = {...}}
	return #timers
end
local function runTimers()
	local list = timers
	timers = {}
	for _, t in ipairs(list) do
		t.fn((unpack or table.unpack)(t.args))
	end
end
os.mtime = os.mtime or function() return os.time() * 1000 end
MESSAGE_INFO_DESCR, MESSAGE_EVENT_ADVANCE = 22, 19
local registered = {}
local function event(kind)
	return function(name)
		local e = {name = name}
		function e:register() registered[name] = self end
		function e:type() end
		function e:separator() end
		return e
	end
end
CreatureEvent, GlobalEvent, TalkAction = event("creature"), event("global"), event("talk")
EventCallback = nil -- the onSpawn registration is engine-only
ChaosAchievements = {has = function(player, id) return player.name == "Vet" and id == "level_300" end,
	data = achievementsData}
ChaosRateLimit = nil

dofile("data/scripts/chaos/cosmetics.lua")
local M = ChaosCosmetics
eq(type(M.swapFor), "function", "cosmetics.lua loaded")
eq(registered.ChaosCosmeticsStartup.onStartup(), true, "startup validates") -- prints nothing on the shipped config

local ann = newPlayer(1, "Ann", 10, "Juggernaut")
local bob = newPlayer(2, "Bob", 20, "Monk")
registered.ChaosCosmeticsLogin.onLogin(ann)
registered.ChaosCosmeticsLogin.onLogin(bob)
eq(ann.events.ChaosCosmeticsExtended, true, "opcode event registered")

-- the store unlock (shop_services.lua) and ownership
local u = M.storeUnlock("cosmetic_skin_warrior_void")
eq(u.name, "Voidborn War Cries", "store unlock name")
eq(u.owned(ann), false, "not owned yet")
eq(u.grant(ann), true, "bought")
eq(u.owned(ann), true, "owned now")
eq(M.storeUnlock("cosmetic_kill_voidring"), nil, "achievement cosmetics are not sold")
eq(M.storeUnlock("transmog_falconer"), nil, "not ours")
local ok, err = u.grant(ann)
eq(ok, false, "a second purchase is refused") eq(err:find("already", 1, true) ~= nil, true, "owned already")
M.owned = {} -- the cache is rebuilt from the table
eq(M.owns(10, "skin_warrior_void"), true, "kept in chaos_cosmetics")

-- choosing through the opcode
local function opcode(p, action, data)
	registered.ChaosCosmeticsExtended.onExtendedOpcode(p, cfg.opcode, json.encode({action = action, data = data}))
end
local function lastTo(name, action)
	for i = #sent, 1, -1 do
		local s = sent[i]
		if s.to == name and s.msg and s.msg.action == action then
			return s.msg.data
		end
	end
end
opcode(ann, "open", {})
local state = lastTo("Ann", "state")
eq(state.open, true, "window opens") eq(state.line, "warrior", "Ann's line")
opcode(ann, "select", {kind = "spellskin", id = 9})
eq(lastTo("Ann", "result").ok, false, "a skin not owned is refused")
opcode(ann, "select", {kind = "spellskin", id = 1})
eq(lastTo("Ann", "result").ok, true, "the owned skin is chosen")
eq(storages[1][7100943], 1, "stored in the warrior slot")
eq(M.swapFor(1, 223, "vfx", "aura_burst_gold"), "aura_burst_violet", "Iron Bellow casts violet")
eq(M.swapFor(1, 225, "fx", "ground_slam"), nil, "Colossus Fall unchanged")
eq(M.swapFor(2, 223, "vfx", "aura_burst_gold"), nil, "Bob has no skin")

-- the cast hook in _common.lua: the variant during a cast, the default outside it and when the pair lacks the variant
NORTH, EAST, SOUTH, WEST, SOUTHWEST, SOUTHEAST, NORTHWEST, NORTHEAST = 0, 1, 2, 3, 4, 5, 6, 7
local castPid, castSpell
ChaosSupportsSpell = {cast = function() return castPid, castSpell end}
dofile("data/spells/chaos/_common.lua")
local function lastEffect()
	return effects[#effects].id
end
castPid, castSpell = 1, 223
ChaosSpell.vfx({x = 50, y = 50, z = 7}, "aura_burst_gold")
eq(lastEffect(), ChaosVfx.aura_burst_violet.id, "a cast of Iron Bellow sends the violet burst")
ChaosSpell.fx({x = 50, y = 50, z = 7}, "blood_rune", 1)
eq(lastEffect(), ChaosFx.arcane_circle, "and the arcane rune (Fx is swapped)")
eq(Fx("blood_rune", 1), ChaosFx.arcane_circle, "Fx inside the cast")
castPid, castSpell = 2, 223
ChaosSpell.vfx({x = 50, y = 50, z = 7}, "aura_burst_gold")
eq(lastEffect(), ChaosVfx.aura_burst_gold.id, "another caster: the default")
castPid, castSpell = nil, nil
eq(Fx("blood_rune", 1), ChaosFx.blood_rune, "outside a cast: the default")
castPid, castSpell = 1, 223
local saved = ChaosVfx.aura_burst_violet
ChaosVfx.aura_burst_violet = nil -- a pair without the variant
ChaosSpell.vfx({x = 50, y = 50, z = 7}, "aura_burst_gold")
eq(lastEffect(), ChaosVfx.aura_burst_gold.id, "missing variant: the default effect")
ChaosVfx.aura_burst_violet = saved
castPid, castSpell = nil, nil

-- kill effects: the killing blow only, seen by everybody
local kill = M.storeUnlock("cosmetic_kill_shatter")
kill.grant(ann)
opcode(ann, "select", {kind = "killfx", id = 103})
local monster = {getPosition = function() return Position(200, 200, 7) end}
local before = #effects
registered.ChaosCosmeticsDeath.onDeath(monster, nil, ann, bob)
eq(#effects, before + 1, "Ann's killing blow shows the effect")
eq(effects[#effects].id, ChaosVfx.ice_shatter.id, "Frost Shatter") eq(effects[#effects].only, nil, "everybody sees it")
eq(effects[#effects].x, 200 + ChaosVfx.ice_shatter.dx, "at the monster, at the effect's offset")
before = #effects
registered.ChaosCosmeticsDeath.onDeath(monster, nil, bob, ann)
eq(#effects, before, "Ann did most damage, Bob the last hit: nothing")
registered.ChaosCosmeticsDeath.onDeath(monster, nil, {isPlayer = function() return false end}, ann)
eq(#effects, before, "a monster's last hit: nothing")
opcode(ann, "select", {kind = "killfx", id = 0})
registered.ChaosCosmeticsDeath.onDeath(monster, nil, ann, ann)
eq(#effects, before, "back to the default: nothing")

-- chat name colours: for every online character, sent at login and on a change
M.storeUnlock("cosmetic_chat_frost").grant(bob)
opcode(bob, "select", {kind = "chatcolor", id = 302})
eq(M.colors.Bob, "#7fc8ff", "Bob's name colour")
eq(lastTo("Ann", "colors").names.Bob, "#7fc8ff", "Ann's client learns it")
local carl = newPlayer(3, "Carl", 30, "Ranger")
registered.ChaosCosmeticsLogin.onLogin(carl)
local full = lastTo("Carl", "colors")
eq(full.full, true, "full list at login") eq(full.names.Bob, "#7fc8ff", "with Bob's colour")
opcode(bob, "select", {kind = "chatcolor", id = 0})
eq(lastTo("Carl", "colors").names.Bob, false, "switched off: removed everywhere")
registered.ChaosCosmeticsLogout.onLogout(carl)
eq(M.active[3], nil, "logout clears the cache")

-- footprints and outlines: who wears what goes to every client (each client draws them), a change to everyone
M.storeUnlock("cosmetic_foot_ember").grant(bob)
M.storeUnlock("cosmetic_glow_radiant").grant(bob)
opcode(bob, "select", {kind = "footprint", id = 401})
eq(storages[2][7102000], 401, "footprint stored in the wardrobe block")
eq(lastTo("Ann", "looks").names.Bob.f, "ember", "Ann's client learns Bob's footprints")
opcode(bob, "select", {kind = "outline", id = 508})
local lk = lastTo("Ann", "looks").names.Bob
eq(lk.f, "ember", "footprints kept") eq(lk.o, "radiant", "and the outline") eq(lk.p, 1, "a pulsing one")
opcode(bob, "select", {kind = "outline", id = 503})
eq(lastTo("Bob", "result").ok, false, "an outline not owned is refused")
eq(lastTo("Ann", "looks").names.Bob.o, "radiant", "still the owned outline")
local carl2 = newPlayer(5, "Cid", 30, "Ranger")
registered.ChaosCosmeticsLogin.onLogin(carl2)
local fullLooks = lastTo("Cid", "looks")
eq(fullLooks.full, true, "full looks at login") eq(fullLooks.names.Bob.o, "radiant", "with Bob's outline")
-- the client's hello once it is in the game: the full lists again (a login send can arrive too early, a reconnect
-- into a character still online runs no login event)
opcode(carl2, "hello", {})
local again = lastTo("Cid", "looks")
eq(again.full, true, "hello: full looks again") eq(again.names.Bob.o, "radiant", "hello: with Bob's outline")
eq(lastTo("Cid", "colors").full, true, "hello: full colours again")
-- a reconnect: the old session of Bob logs out after the new one logged in; Bob's look stays known
local bob2 = newPlayer(6, "Bob", 20, "Warrior")
storages[6] = storages[2]
registered.ChaosCosmeticsLogin.onLogin(bob2)
registered.ChaosCosmeticsLogout.onLogout(bob)
eq(M.looks.Bob ~= nil and M.looks.Bob.o, "radiant", "the old session's logout keeps the new session's look")
players[6] = nil
opcode(bob, "select", {kind = "footprint", id = 0})
opcode(bob, "select", {kind = "outline", id = 0})
eq(lastTo("Cid", "looks").names.Bob, false, "both off: removed everywhere")
registered.ChaosCosmeticsLogout.onLogout(carl2)
-- the store's SHOW button: the buyer's own client draws it (no effect sent to anybody)
local beforeFx = #effects
M.storePreview(carl2, "cosmetic_glow_abyssal")
local try = lastTo("Cid", "tryfx")
eq(try ~= nil and try.kind, "outline", "a preview to the asking client") eq(try.art, "abyssal", "its art")
eq(try.pulse, 1, "pulsing") eq(#effects, beforeFx, "no magic effect")
eq(M.offerPreview("cosmetic_foot_petal").effect, true, "footprint offers have the SHOW button")
-- the state carries the Collection rows when exclusives.lua is loaded
ChaosExclusives = {rows = function(p) return {{key = "x", kind = "mount", name = "X", owned = true}} end}
opcode(ann, "open", {})
eq(lastTo("Ann", "state").collection[1].key, "x", "collection rows in the state")
ChaosExclusives = nil
opcode(ann, "open", {})
eq(lastTo("Ann", "state").collection, nil, "no exclusives: no collection")

-- the label accent: only the character's own client
M.storeUnlock("cosmetic_loot_azure").grant(bob)
opcode(bob, "select", {kind = "lootbeam", id = 203})
eq(lastTo("Bob", "style").accent, "#0f2250f0", "Bob's accent")
eq(lastTo("Bob", "colors") ~= nil, true, "Bob got colour updates")

-- achievement cosmetics are granted at login
local vet = newPlayer(4, "Vet", 40, "Templar")
registered.ChaosCosmeticsLogin.onLogin(vet)
eq(M.owns(40, "chat_veteran"), true, "Veteran's Gold granted from the achievement")
eq(M.owns(40, "kill_voidring"), false, "not the other ones")

-- the reward track at login and when the account's achievements change (achievements.lua calls ChaosCosmetics.sync)
local accounts = {[50] = {ids = {}, points = 120}}
ChaosAchievements.index = aIndex
ChaosAchievements.accountOf = function(who)
	local id = type(who) == "number" and who or who:getAccountId()
	return accounts[id] or {ids = {}, points = 0}
end
local hero = newPlayer(5, "Hero", 50, "Mystic")
registered.ChaosCosmeticsLogin.onLogin(hero)
eq(M.owns(50, "chat_ashen"), true, "120 points: Ashen Name at login")
eq(M.owns(50, "loot_chronicle"), false, "not the 250 one")
local toldHero = false
for _, m in ipairs(sent) do
	if m.to == "Hero" and m.text and m.text:find("Cosmetic unlocked: Ashen Name", 1, true) then
		toldHero = true
	end
end
eq(toldHero, true, "told in chat")
accounts[50].points = 260
local riftIds = {}
for _, def in ipairs(aIndex.list) do
	if def.cat == "rifts" then
		riftIds[def.id] = true
	end
end
accounts[50].ids = riftIds
local granted = M.sync(hero)
eq(#granted, 2, "points and a category changed: two") eq(M.owns(50, "loot_chronicle"), true, "Chronicle Labels at 250")
eq(M.owns(50, "kill_riftsigil"), true, "every rift achievement: Rift Sigil")
local inserts = #queries
eq(#M.sync(hero), 0, "a second sync grants nothing") eq(#queries, inserts, "and writes nothing")
accounts[50].points, accounts[50].ids = 0, {} -- a staff reset of the achievements
eq(#M.sync(hero), 0, "fewer points: nothing") eq(M.owns(50, "loot_chronicle"), true, "never taken back")
M.owned = {}
eq(M.owns(50, "kill_riftsigil"), true, "kept in chaos_cosmetics")
opcode(hero, "select", {kind = "killfx", id = 118})
eq(lastTo("Hero", "result").ok, true, "a track kill effect can be chosen")
eq(M.storeUnlock("cosmetic_kill_riftsigil"), nil, "a track cosmetic is no store unlock")

-- previews: to the asking player only, one after the other, rate limited
effects = {}
eq(M.storePreview(ann, "cosmetic_skin_mystic_voidfire"), true, "store preview")
eq(M.storePreview(ann, "cosmetic_skin_mystic_voidfire"), false, "again at once: refused")
runTimers()
eq(#effects, 3, "Voidfire: its three variants")
for _, e in ipairs(effects) do
	eq(e.only, "Ann", "only Ann sees the preview")
end
eq(M.storePreview(bob, "cosmetic_chat_frost"), false, "a colour has no effect preview")
eq(M.offerPreview("cosmetic_chat_frost").color, "#7fc8ff", "the store shows the colour")
eq(M.offerPreview("transmog_falconer"), nil, "nothing for other unlocks")

-- staff
local gm = newPlayer(9, "Gm", 90, "Warrior")
gm.getGroup = function() return {getId = function() return 6 end, getAccess = function() return true end} end
-- a gamemaster (group 4) may not grant (docs/GM_HANDBOOK.md: staff never give value); sync and revoke stay at group 4
local gm4 = newPlayer(19, "Gmfour", 91, "Warrior")
gm4.getGroup = function() return {getId = function() return 4 end, getAccess = function() return true end} end
gm4.sendCancelMessage = function(self, text) self.cancel = text end
db.storeQuery = (function(old)
	return function(q)
		if q:find("FROM `players`", 1, true) then
			return {player = q:match("'([^']+)'")}
		end
		return old(q)
	end
end)(db.storeQuery)
result.getNumber = function(r) return Player(r.player) and Player(r.player).account or nil end
registered["/cosmetic"].onSay(gm4, "/cosmetic", "Carl, kill_sunring")
eq(M.owns(30, "kill_sunring"), false, "a gamemaster cannot grant")
eq(gm4.cancel ~= nil, true, "and is told why")
registered["/cosmetic"].onSay(gm, "/cosmetic", "Carl, kill_sunring")
eq(M.owns(30, "kill_sunring"), true, "/cosmetic grants")
registered["/cosmetic"].onSay(gm4, "/cosmetic", "Carl, kill_sunring, revoke")
eq(M.owns(30, "kill_sunring"), false, "/cosmetic revokes (a gamemaster may)")
-- /cosmetic <character>, sync: the account's achievement cosmetics and reward track (idempotent)
accounts[30] = {ids = {}, points = 600}
registered["/cosmetic"].onSay(gm, "/cosmetic", "Carl, sync")
eq(M.owns(30, "kill_verdigris"), true, "/cosmetic sync grants the 500 milestone")
eq(sent[#sent].text:find("Synced the account of Carl", 1, true) ~= nil, true, "the staff member is told")
registered["/cosmetic"].onSay(gm, "/cosmetic", "Carl, sync")
eq(sent[#sent].text:find("every cosmetic it earned", 1, true) ~= nil, true, "a second sync changes nothing")

-- the Chaos outfit shaders on the engine: off (as shipped) nothing; switched on, a priced one is sold, added to the
-- buyer and to the account's other characters at login, and listed in the Collection tab
do
	local shaders = {}
	local dee = newPlayer(40, "Dee", 50, "Monk")
	function dee:addShader(id) shaders[#shaders + 1] = id end
	eq(M.storeUnlock("cosmetic_shader_ember_glow"), nil, "off: not sold")
	eq(M.grant(50, "shader_ember_glow"), false, "off: not granted")
	registered.ChaosCosmeticsLogin.onLogin(dee)
	eq(#shaders, 0, "off: nothing added at login")
	local live = ChaosCosmeticsConfig.outfitShaders
	live.enabled = true
	live.list[1].price = 300
	local u2 = M.storeUnlock("cosmetic_shader_ember_glow")
	eq(u2 ~= nil and u2.name, "Ember Glow", "on and priced: a store unlock")
	eq(M.storeUnlock("cosmetic_shader_frost_rime"), nil, "on but unpriced: not sold")
	eq(u2.grant(dee), true, "bought")
	eq(shaders[#shaders], 19, "added to the buyer")
	eq(u2.owned(dee), true, "owned by the account")
	local state
	for i = #sent, 1, -1 do
		if sent[i].to == "Dee" and sent[i].msg and sent[i].msg.action == "state" then state = sent[i].msg.data break end
	end
	local found
	for _, r in ipairs(state and state.collection or {}) do
		if r.key == "shader_ember_glow" then found = r end
	end
	eq(found ~= nil and found.owned, true, "in the Collection tab, owned")
	eq(found and found.icon, nil, "the icon became a client item id")
	local dee2 = newPlayer(41, "Dee Two", 50, "Monk")
	local shaders2 = {}
	function dee2:addShader(id) shaders2[#shaders2 + 1] = id end
	registered.ChaosCosmeticsLogin.onLogin(dee2)
	eq(shaders2[1], 19, "the account's other character gets it at login")
	live.enabled = false
	live.list[1].price = nil
end

-- the client side files exist
for _, f in ipairs({"game_cosmetics/game_cosmetics.otmod", "game_cosmetics/cosmetics.lua", "game_cosmetics/cosmeticslogic.lua"}) do
	eq(readFile("../client/overlay/modules/" .. f) ~= nil, true, "client " .. f)
end

print(string.format("cosmetics_test: %d checks OK", n))
