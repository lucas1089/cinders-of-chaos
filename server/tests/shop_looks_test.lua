-- Run from the server/ folder: luajit tests/shop_looks_test.lua (and lua5.3; CI runs both)
-- Store icons and previews (owner 2026-10-17: "os icones da store estao repetidos ... use os proprios cosmeticos como
-- icones"). Every appearance offer of shop_config.lua must carry its own look (shop_core.lua K.lookOf, cosmetics_core.lua
-- K.offerLook) and no two offers may share one; a cosmetic is never drawn with a stand-in item.
local n = 0
setmetatable(_G, {__index = function(t, k)
	if type(k) == "string" and k:match("^[A-Z_0-9]+$") then n = n + 1; rawset(t, k, n); return n end
end})

local checks, failures = 0, 0
local function check(cond, label)
	checks = checks + 1
	if not cond then
		failures = failures + 1
		print("FAIL " .. label)
	end
end

dofile("data/scripts/chaos/shop_core.lua")
dofile("data/scripts/chaos/cosmetics_core.lua")
local K, CK = ChaosShopCore, ChaosCosmeticsCore
local cfg = dofile("data/scripts/chaos/shop_config.lua")
local ccfg = dofile("data/scripts/chaos/cosmetics_config.lua")

-- a stable text of a look, to compare two
local function ser(v)
	if type(v) ~= "table" then
		return tostring(v)
	end
	local keys = {}
	for k in pairs(v) do
		keys[#keys + 1] = k
	end
	table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
	local out = {}
	for _, k in ipairs(keys) do
		out[#out + 1] = tostring(k) .. "=" .. ser(v[k])
	end
	return "{" .. table.concat(out, ",") .. "}"
end

-- the engine side, mocked: ids from the offer id, effects from the effect name (a hash)
local function hash(s)
	local h = 7
	for i = 1, #s do
		h = (h * 31 + s:byte(i)) % 100003
	end
	return h
end
local src = {
	outfitLook = function(o) return o.looktype end,
	wings = function(id) return 1000 + id end,
	aura = function(id) return 2000 + id end,
	shader = function(id) return "shader_" .. id end,
	cosmetic = function(unlock)
		return CK.offerLook(ccfg, unlock, function(t, name) return {id = hash(t .. name)} end)
	end,
}

local byKey = {}
for _, cat in ipairs(cfg.categories) do
	for _, o in ipairs(cat.offers) do
		o.key = K.offerKey(o)
		byKey[o.key] = o
	end
end

local VISUAL = {outfit = true, addons = true, mount = true, wings = true, aura = true, shader = true, frame = true}
local seen, dup = {}, {}
local counts = {}
for _, cat in ipairs(cfg.categories) do
	for _, o in ipairs(cat.offers) do
		local look = K.lookOf(o, src)
		local what = cat.name .. " / " .. tostring(o.name or o.key)
		local isCosmeticUnlock = o.kind == "unlock" and type(o.unlock) == "string" and o.unlock:match("^cosmetic_")
		if VISUAL[o.kind] or isCosmeticUnlock then
			check(look ~= nil, what .. ": an appearance offer has a look")
			if look then
				counts[look.kind] = (counts[look.kind] or 0) + 1
				local s = ser(look)
				if seen[s] and cat.name == seen[s].cat then
					dup[#dup + 1] = what .. " = " .. seen[s].what
				end
				seen[s] = seen[s] or {what = what, cat = cat.name}
			end
		end
	end
end
check(#dup == 0, "no two offers of a category share a look: " .. table.concat(dup, "; "))
for _, kind in ipairs({"outfit", "addons", "mount", "wings", "aura", "shader", "nameplate", "outline", "footprint", "effects", "swatch"}) do
	check((counts[kind] or 0) > 0, "the store has " .. kind .. " looks (" .. tostring(counts[kind]) .. ")")
end

-- bundles carry their parts (the ones that are an appearance)
local bundles = 0
for _, cat in ipairs(cfg.categories) do
	for _, o in ipairs(cat.offers) do
		if o.kind == "bundle" then
			o.resolved = {}
			for _, p in ipairs(o.parts) do
				local part = type(p) == "string" and byKey[p] or p
				if part then
					o.resolved[#o.resolved + 1] = part
				end
			end
			local look = K.lookOf(o, src)
			if look then
				bundles = bundles + 1
				check(look.kind == "bundle" and #look.parts >= 1, o.key .. ": bundle look")
				local outfit = K.iconOutfit(look, {type = 128, head = 114}, {type = 128})
				check(outfit ~= nil and outfit.rotating == true, o.key .. ": a bundle icon is a creature wearing its parts")
				for _, p in ipairs(look.parts) do
					if p.kind == "mount" or p.kind == "wings" or p.kind == "aura" then
						check(outfit[p.kind] == p.look, o.key .. ": " .. p.kind .. " on the icon")
					elseif p.kind == "shader" then
						check(outfit.shader == p.shader, o.key .. ": shader on the icon")
					elseif p.kind == "outfit" or p.kind == "addons" then
						check(outfit.type == p.look and outfit.addons == 3, o.key .. ": outfit on the icon")
					end
				end
			end
		end
	end
end
check(bundles >= 6, "bundles with a look found (" .. bundles .. ")")

-- items, services and premium time are no appearance: the item picture stays
check(K.lookOf({kind = "item", id = 2160}, src) == nil, "item: no look")
check(K.lookOf({kind = "service", service = "stamina"}, src) == nil, "service: no look")
check(K.lookOf({kind = "premium", days = 30}, src) == nil, "premium: no look")
check(K.lookOf({kind = "unlock", unlock = "autoSeller"}, src) == nil, "convenience unlock: no look")
check(K.lookOf({kind = "bundle", resolved = {{kind = "item", id = 1}}}, src) == nil, "an items-only bundle: no look")
check(K.lookOf({kind = "wings", id = 4}, {wings = function() return 0 end}) == nil, "wings the XML lacks: no look")
check(K.lookOf({kind = "unlock", look = 294}, src).kind == "subject", "a pet is a subject")

-- the icon creature of each look
local PREVIEW, NEUTRAL = {type = 128, head = 114, body = 94, addons = 3}, {type = 128, head = 76}
check(K.iconOutfit({kind = "outline", art = "gold"}, PREVIEW, NEUTRAL).head == 76, "an outline is worn by the plain figure")
check(K.iconOutfit({kind = "shader", shader = "x"}, PREVIEW, NEUTRAL).shader == "x", "a shader unlock is worn by the preview figure")
check(K.iconOutfit({kind = "mount", look = 1561}, PREVIEW, NEUTRAL).type == 1561, "a mount is drawn alone")
check(K.iconOutfit({kind = "wings", look = 5}, PREVIEW, NEUTRAL).wings == 5, "wings on the figure")
check(K.iconOutfit({kind = "footprint", art = "ash"}, PREVIEW, NEUTRAL) == nil, "a print is a picture, no creature")
check(K.iconOutfit({kind = "effects", play = {}}, PREVIEW, NEUTRAL) == nil, "an effect is drawn from its sprites")
check(K.iconOutfit({kind = "nameplate", frame = "frost"}, PREVIEW, NEUTRAL) == nil, "a plate frame is a picture")
check(K.iconOutfit({kind = "bundle", parts = {{kind = "swatch", color = "#ffffff"}}}, PREVIEW, NEUTRAL) == nil, "a bundle with nothing to wear")

-- cosmetics_core offerLook
local function look(key) return CK.offerLook(ccfg, "cosmetic_" .. key, function(t, name) return {id = hash(name)} end) end
local o = look("glow_radiant")
check(o and o.kind == "outline" and o.art == "radiant" and o.pulse == true, "outline look")
check(look("glow_gold").pulse == nil, "a steady outline does not pulse")
check(CK.offerLook(ccfg, "cosmetic_nope", nil) == nil, "an unknown unlock has no look")
check(CK.offerLook(ccfg, "autoSeller", nil) == nil, "a non-cosmetic unlock has no look")
local sh = CK.offerLook(ccfg, "cosmetic_shader_ember_glow", nil)
check(sh and sh.kind == "shader" and sh.shader == "chaos_ember_glow", "outfit shader unlock look")
local fx = 0
for _, c in ipairs(ccfg.cosmetics) do
	if c.source == "store" then
		local l = CK.offerLook(ccfg, "cosmetic_" .. c.key, function(t, name) return {id = hash(name)} end)
		check(l ~= nil, c.key .. ": a store cosmetic has a look")
		if l and l.kind == "effects" then
			fx = fx + 1
			check(#l.play >= 1 and l.play[1].b.id > 0, c.key .. ": its effects")
		end
	end
end
check(fx > 5, "spell skins and kill effects carry their effects (" .. fx .. ")")

if failures > 0 then
	error(string.format("%d of %d checks failed", failures, checks))
end
print(string.format("shop_looks_test: %d checks passed", checks))
