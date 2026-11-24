-- Run from the server/ folder: luajit tests/pack_wear_test.lua (and lua5.3; CI runs both)
-- The purchased wings, head pieces and capes of client pair 83 (O747, data/lib/chaos_wst_wear.lua and the generated
-- chaos_wst_wear_ids.lua): ids and looks follow pair 82 in order, the gate is config.lua chaosClientPair >= 83 (below it the
-- cosmetics, the kinds, the store offers and the hidden auras are all absent), and when it is on: the 144 cosmetics of the kinds
-- head and cape validate with the real core, the store sells them in two subcategories and the new wing at the end of Wings,
-- the pair 33 twin auras leave the store, an aura's owner gets the twin piece, rows and the store look carry the client look,
-- and every description sentence has its pt-BR text.
CONST_ME_FIREWORK_YELLOW = CONST_ME_FIREWORK_YELLOW or 29 -- shop_config.lua reads it
dofile("data/scripts/chaos/chaos_constants.lua")
dofile("data/scripts/chaos/transmog_core.lua")
dofile("data/scripts/chaos/exclusives_core.lua")
dofile("data/scripts/chaos/shop_core.lua")
dofile("data/scripts/chaos/nameplate_core.lua")
dofile("data/scripts/chaos/cosmetics_core.lua")
local K = ChaosCosmeticsCore

local n = 0
local function eq(a, b, m)
	n = n + 1
	if a ~= b then
		error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2)
	end
end

local LIB = "data/lib/chaos_wst_wear.lua"
local realDofile = dofile

-- the library with the gate set by hand (ChaosWstWearOn is read at load)
local function lib(on)
	ChaosWstWearOn = on
	local M = realDofile(LIB)
	ChaosWstWearOn = nil
	return M
end

local M = realDofile(LIB)
eq(M.PAIR, 83, "pair 83")
eq(M.on, false, "no config.lua next to the tests: the gate is off")
eq(M.parsePair("chaosClientPair = 83"), 83, "plain")
eq(M.parsePair("x = 1\nchaosClientPair=82 -- shipped\n"), 82, "comment, other lines")
eq(M.parsePair("x = 1\n"), nil, "no key")

-- ---------------------------------------------------------------- the generated ids
eq(#M.wings, 1, "one new wing")
eq(M.wings[1].id, 128, "wings.xml id 128, after the drawn wings 122-127")
eq(M.wings[1].look, 3589, "the first look after pair 82's 3588 outfits")
eq(#M.heads, 66, "66 head pieces")
eq(#M.capes, 78, "78 capes")
local look = 3589
for _, list in ipairs({M.heads, M.capes}) do
	for _, p in ipairs(list) do
		look = look + 1
		eq(p.look, look, p.key .. ": looks in order")
		eq(type(p.name) == "string" and p.name ~= "", true, p.key .. ": name")
		eq(p.cost >= 150 and p.cost <= 250, true, p.key .. ": price 150-250")
	end
end
local pack33 = realDofile("data/lib/chaos_pack33_cosmetics.lua")
local auraById = {}
for _, slug in ipairs({"heads", "capes"}) do
	for _, a in ipairs(pack33[slug]) do
		auraById[a.id] = {slug = slug, a = a}
	end
end
local twins = 0
for slug, list in pairs({heads = M.heads, capes = M.capes}) do
	for _, p in ipairs(list) do
		if p.aura then
			twins = twins + 1
			local t = auraById[p.aura]
			eq(t ~= nil and t.slug == slug, true, p.key .. ": the twin is a pair 33 piece of the same list")
			eq(p.cost, t.a.cost, p.key .. ": the twin's price")
		end
	end
end
eq(twins, 137, "64 heads and 73 capes have a twin")

-- ---------------------------------------------------------------- gate off: nothing changes
local function configWith(on)
	ChaosWstWear = lib(on)
	local cfg = realDofile("data/scripts/chaos/cosmetics_config.lua")
	ChaosWstWear = nil
	return cfg
end
local function kindsOf(cfg)
	local out, count = {}, {}
	for _, k in ipairs(cfg.kinds) do
		out[k.key] = k
	end
	for _, c in ipairs(cfg.cosmetics) do
		count[c.kind] = (count[c.kind] or 0) + 1
	end
	return out, count
end
local offCfg = configWith(false)
local offKinds, offCount = kindsOf(offCfg)
eq(offKinds.head, nil, "no head kind while off")
eq(offKinds.cape, nil, "no cape kind while off")
eq(offCount.head, nil, "no head cosmetic while off")
eq(M.hidesAura(34), false, "no hidden aura while off")
eq(#M.twinGrants(function() return true end), 0, "no twin grant while off")
eq(#M.storeOffers(), 0, "no wing offer while off")

local function shopWith(on)
	local W = lib(on)
	local P33 = realDofile("data/lib/chaos_pack33.lua")
	P33.wearLib = W
	dofile = function(path, ...)
		if path == LIB then
			return W
		elseif path == "data/lib/chaos_pack33.lua" then
			return P33
		end
		return realDofile(path, ...)
	end
	ChaosWstWear = W
	local ok, shop = pcall(realDofile, "data/scripts/chaos/shop_config.lua")
	dofile = realDofile
	ChaosWstWear = nil
	if not ok then error(shop) end
	return shop
end
local function catOf(shop, name)
	for _, c in ipairs(shop.categories) do
		if c.name == name then return c end
	end
end
local offShop = shopWith(false)
eq(catOf(offShop, "Head Pieces"), nil, "no Head Pieces category while off")
eq(catOf(offShop, "Cloaks and Capes"), nil, "no Cloaks and Capes category while off")
for _, o in ipairs(catOf(offShop, "Wings").offers) do
	eq(o.kind ~= "wings" or o.id ~= 128, true, "no Plasma Fly Wings offer while off")
end
local offHeadAuras = #catOf(offShop, "Head Accessories").offers

-- ---------------------------------------------------------------- gate on
local W = lib(true)
eq(W.on, true, "the gate set by hand")
local cfg = configWith(true)
local kinds, count = kindsOf(cfg)
eq(kinds.head ~= nil and kinds.cape ~= nil, true, "both kinds while on")
eq(count.head, 66, "66 head cosmetics")
eq(count.cape, 78, "78 cape cosmetics")
eq(cfg.storage.head, 7102005, "head storage in the wardrobe block")
eq(cfg.storage.cape, 7102006, "cape storage in the wardrobe block")
eq(K.storageOf(cfg, "head"), 7102005, "storageOf head")
local c1 = K.byKey(cfg, "head_antelope_horns")
eq(c1 and c1.id, 1001, "the first head is id 1001")
eq(c1.look, 3590, "its look")
eq(K.byKey(cfg, "cape_academic_gown_cape").id, 1101, "the first cape is id 1101")
local problems = K.validate(cfg, {})
eq(#problems, 0, "the config with the pieces validates: " .. table.concat(problems, "; "))

-- the core's checks of a piece
local function problemsWith(change)
	local copy = {}
	for k, v in pairs(cfg) do copy[k] = v end
	copy.cosmetics = {}
	for _, c in ipairs(cfg.cosmetics) do
		local d = {}
		for k, v in pairs(c) do d[k] = v end
		copy.cosmetics[#copy.cosmetics + 1] = d
	end
	change(copy.cosmetics)
	return table.concat(K.validate(copy, {}), "\n")
end
local function find(list, key)
	for _, c in ipairs(list) do
		if c.key == key then return c end
	end
end
eq(problemsWith(function(l) find(l, "head_antelope_horns").look = 3000 end):find("client look of pair 83", 1, true) ~= nil, true,
	"a look below pair 83 is refused")
eq(problemsWith(function(l) find(l, "head_atom_orbit").look = 3590 end):find("look 3590 used by", 1, true) ~= nil, true,
	"a look used twice is refused")
eq(problemsWith(function(l) find(l, "head_antelope_horns").pair = nil end):find("needs `pair` 83", 1, true) ~= nil, true,
	"a piece without the pair gate is refused")
eq(problemsWith(function(l) find(l, "skin_necro_rift").look = 3600 end):find("look is only for head pieces", 1, true) ~= nil, true,
	"a look on another kind is refused")

-- rows, the store preview and the store look
local owned = {head_antelope_horns = true}
local rows = K.rows(cfg, owned, {head = 1001})
local row
for _, r in ipairs(rows) do
	if r.key == "head_antelope_horns" then row = r end
end
eq(row.look, 3590, "the row carries the look")
eq(row.selected, true, "the chosen head is selected")
eq(row.preview, true, "the client previews it")
local lk = K.offerLook(cfg, "cosmetic_head_antelope_horns")
eq(lk.kind, "wear", "the store look is a worn piece")
eq(lk.slot, "head", "slot head")
eq(lk.look, 3590, "look")
eq(K.offerLook(cfg, "cosmetic_cape_academic_gown_cape").slot, "cape", "slot cape")
eq(K.offerPreview(c1).effect, true, "the SHOW button")
local chosen, why = K.choose(cfg, owned, "head", 1001)
eq(chosen and chosen.id, 1001, "an owned head can be chosen")
chosen, why = K.choose(cfg, owned, "cape", 1101)
eq(chosen, nil, "a cape not owned cannot")
eq(why:find("Cloaks and Capes", 1, true) ~= nil, true, "the store category in the refusal")
eq(K.choose(cfg, owned, "cape", 1001), nil, "a head id is not a cape")

-- twins
eq(W.hidesAura(34), true, "the twin aura of Antelope Horns leaves the store")
eq(W.hidesAura(33), false, "an aura with no twin stays")
local grants = W.twinGrants(function(id) return id == 34 or id == 126 end)
eq(#grants, 2, "two twin grants")
eq(grants[1], "head_antelope_horns", "the head twin")
eq(grants[2], "cape_assassin_hood", "the cape twin")

-- the store
local shop = shopWith(true)
local heads, capes = catOf(shop, "Head Pieces"), catOf(shop, "Cloaks and Capes")
eq(heads ~= nil and capes ~= nil, true, "both categories while on")
eq(#heads.offers, 66, "66 head offers")
eq(#capes.offers, 78, "78 cape offers")
eq(heads.parent, "Cosmetics", "under Cosmetics")
for _, o in ipairs(heads.offers) do
	local c = K.ofUnlock(cfg, o.unlock)
	eq(c ~= nil and c.kind == "head" and o.cost == c.price, true, o.unlock .. ": an unlock at the price")
end
local wings = catOf(shop, "Wings").offers
eq(wings[#wings].kind == "wings" and wings[#wings].id == 128 and wings[#wings].cost == 300, true, "Plasma Fly Wings at the end of Wings")
eq(#catOf(shop, "Head Accessories").offers, offHeadAuras - 64 + (function()
	-- the twin auras that were exclusives were never offered: they cannot leave the store
	local ex = 0
	local P33 = realDofile("data/lib/chaos_pack33.lua")
	for _, e in ipairs(P33.exclusives or {}) do
		for _, p in ipairs(W.heads) do
			local a = auraById[p.aura or -1]
			if a and a.a.key == e.key then ex = ex + 1 end
		end
	end
	return ex
end)(), "the 64 twin head auras leave the store")
for _, o in ipairs(catOf(shop, "Head Accessories").offers) do
	eq(W.hidesAura(o.id), false, "aura " .. tostring(o.id) .. " has no twin")
end
local EX = ChaosShopCore.exclusions({classLooks = (function()
	realDofile("data/scripts/chaos/class_looks_core.lua")
	return ChaosClassLooks.looks
end)(), classOutfits = Chaos.classes.outfits,
	achievements = realDofile("data/scripts/chaos/achievements_data.lua"), season = realDofile("data/scripts/chaos/season_config.lua"),
	seasonpass = realDofile("data/scripts/chaos/seasonpass_config.lua"), exclusives = realDofile("data/scripts/chaos/exclusives_config.lua")})
local shopProblems = ChaosShopCore.validate(shop, EX)
eq(#shopProblems, 0, "the store with the pieces validates: " .. table.concat(shopProblems, "; "))
local cosProblems = K.validate(cfg, {shop = shop})
eq(#cosProblems, 0, "every store cosmetic has its offer: " .. table.concat(cosProblems, "; "))

-- every sentence of the descriptions has a pt-BR text
local pt = realDofile("data/scripts/chaos/i18n_strings.lua")["pt-BR"]
local texts = {}
for _, c in ipairs(W.cosmetics()) do
	texts[#texts + 1] = c.desc
end
for _, o in ipairs(W.storeOffers()) do
	texts[#texts + 1] = o.description
end
for _, d in ipairs(texts) do
	eq(d:sub(-1), ".", d .. ": sentences")
	for sentence in d:gmatch("([^%.]+)%.?") do
		sentence = sentence:gsub("^%s+", "")
		eq(type(pt[sentence]), "string", "pt-BR text of '" .. sentence .. "'")
	end
end

print("pack_wear_test: " .. n .. " checks passed")
