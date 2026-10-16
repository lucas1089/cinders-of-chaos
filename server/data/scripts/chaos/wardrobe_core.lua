-- wardrobe_core.lua: the full appearance catalogue of the Customise Character window, without engine calls
-- (server/tests/wardrobe_test.lua). See wardrobe.lua and server/README.md "Wardrobe catalogue".
-- The stock 10.98 outfit window packet lists only what the character owns. The client (game_unlocks, base patch 0058)
-- shows every outfit, mount, wing, aura and shader of the game instead, the ones not owned greyed out with where they
-- come from. This builds that list: the XML catalogues (outfits.xml for the character's sex, mounts.xml, wings.xml,
-- auras.xml, shaders.xml), an owned flag per entry and the unlock source when it is known.
-- Ownership is the engine's own rule: Player:hasOutfit / hasMount, and for wings, auras and shaders the bits of the
-- reserved storages the engine reads in Player::hasWing / hasAura / hasShader (key = range start + (id - 1) // 31,
-- bit (id - 1) % 31); an access player owns everything; a premium entry needs premium. The engine still refuses an
-- outfit change with anything not owned (Game::playerChangeOutfit), whatever the client sends.
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.

ChaosWardrobeCore = ChaosWardrobeCore or {}
local W = ChaosWardrobeCore

-- the engine's reserved storage ranges (src/const.h PSTRG_*: 10000000 + 2012 / 2023 / 2034)
W.RANGES = {wings = 10002012, aura = 10002023, shader = 10002034}
W.KINDS = {"outfit", "mount", "wings", "aura", "shader"}

local function attrs(tagText)
	local t = {}
	for k, v in tagText:gmatch('([%w_]+)%s*=%s*"([^"]*)"') do
		t[k] = v
	end
	return t
end

local function yes(v)
	return v == "yes" or v == "1" or v == "true"
end

-- every <tag .../> of an XML text, as attribute tables, in file order; comments are skipped
function W.parseXml(text, tag)
	local out = {}
	text = (text or ""):gsub("<!%-%-.-%-%->", "")
	for body in text:gmatch("<" .. tag .. "%s([^>]*)>") do
		out[#out + 1] = attrs(body)
	end
	return out
end

-- the catalogue of one sex (0 female, 1 male) from the XML texts {outfits, mounts, wings, auras, shaders}:
-- {outfit = {{look, name, premium, free}}, mount = {{id, look, name, premium}}, wings = ..., aura = ..., shader =
-- {{id, name, premium}}}. Disabled outfits are left out; a look type is listed once.
function W.catalogue(xml, sex)
	local cat = {outfit = {}, mount = {}, wings = {}, aura = {}, shader = {}}
	local seen = {}
	for _, a in ipairs(W.parseXml(xml.outfits, "outfit")) do
		local look = tonumber(a.looktype)
		if look and tonumber(a.type) == sex and a.enabled ~= "no" and not seen[look] then
			seen[look] = true
			cat.outfit[#cat.outfit + 1] = {look = look, name = a.name or "", premium = yes(a.premium), free = yes(a.unlocked)}
		end
	end
	for kind, src in pairs({mount = {xml.mounts, "mount"}, wings = {xml.wings, "wing"}, aura = {xml.auras, "aura"}}) do
		for _, a in ipairs(W.parseXml(src[1], src[2])) do
			local id, look = tonumber(a.id), tonumber(a.clientid)
			if id and look then
				cat[kind][#cat[kind] + 1] = {id = id, look = look, name = a.name or "", premium = yes(a.premium)}
			end
		end
	end
	for _, a in ipairs(W.parseXml(xml.shaders, "shader")) do
		local id = tonumber(a.id)
		if id and a.name then
			cat.shader[#cat.shader + 1] = {id = id, name = a.name, premium = yes(a.premium)}
		end
	end
	return cat
end

-- ---------------------------------------------------------------- ownership
-- is bit `id` set in the engine's storage bitmap starting at `base` (value(key) -> the storage value or nil)
function W.bitOwned(base, id, value)
	id = tonumber(id) or 0
	if id < 1 then
		return false
	end
	local v = tonumber(value(base + math.floor((id - 1) / 31))) or 0
	if v <= 0 then
		return false
	end
	local bit = 2 ^ ((id - 1) % 31)
	return math.floor(v / bit) % 2 == 1
end

-- the owned addons of an outfit (0-3) from has(look, addons) = Player:hasOutfit; nil when the look is not owned
function W.outfitAddons(look, has)
	if not has(look, 0) then
		return nil
	end
	if has(look, 3) then
		return 3
	end
	return (has(look, 1) and 1 or 0) + (has(look, 2) and 2 or 0)
end

-- ---------------------------------------------------------------- unlock sources
-- {outfit = {[look] = text}, mount = {[mounts.xml id] = text}, wings / aura / shader = {[xml id] = text}} from:
--   shopOffers  every store offer (shop_config.lua, any depth): kind outfit / addons (looktype, lookfemale), mount,
--               wings, aura, shader (id) -> "Store"
--   exclusives  exclusives_config.lua entries with how(e) (exclusives_core.lua K.how): their text
--   classLooks  {[vocation id] = {name, male, female}} -> "Class: <name>"
-- Later sources do not overwrite earlier ones: an exclusive is never sold, a class look never in the store.
function W.sources(opts)
	opts = opts or {}
	local src = {outfit = {}, mount = {}, wings = {}, aura = {}, shader = {}}
	local function put(kind, key, text)
		key = tonumber(key)
		if key and text and src[kind][key] == nil then
			src[kind][key] = text
		end
	end
	for _, e in ipairs(opts.exclusives or {}) do
		local how = opts.how and opts.how(e) or nil
		if e.kind == "outfit" or e.kind == "addons" then
			put("outfit", e.male, how)
			put("outfit", e.female, how)
		elseif src[e.kind] then
			put(e.kind, e.id, how)
		end
	end
	for _, l in pairs(opts.classLooks or {}) do
		local text = "Class: " .. tostring(l.name or "")
		put("outfit", l.male, text)
		put("outfit", l.female, text)
	end
	local function walk(t, depth)
		if type(t) ~= "table" or depth > 8 then
			return
		end
		if type(t.kind) == "string" then
			if t.kind == "outfit" or t.kind == "addons" then
				put("outfit", t.looktype, "Store")
				put("outfit", t.lookfemale, "Store")
			elseif t.kind == "mount" or t.kind == "wings" or t.kind == "aura" or t.kind == "shader" then
				put(t.kind, t.id, "Store")
			end
		end
		for _, v in pairs(t) do
			if type(v) == "table" then
				walk(v, depth + 1)
			end
		end
	end
	walk(opts.shopOffers, 0)
	return src
end

-- ---------------------------------------------------------------- the client's list
-- cat = W.catalogue; src = W.sources; own = {access, premium, hasOutfit(look, addons), hasMount(id), value(key)}.
-- Returns {outfit = {{l, n, o, a, s}}, mount = {{l, n, o, s}}, wings = ..., aura = ..., shader = {{n, o, s}}}:
-- l the client look type, n the name (shaders: the shader name), o = 1 owned, a the owned addons of an owned outfit,
-- s the unlock source ("Free" for an outfit everyone has, "Free; addons: <source>" when its addons come from
-- somewhere). Order: the catalogue's.
function W.list(cat, src, own)
	src = src or {outfit = {}, mount = {}, wings = {}, aura = {}, shader = {}}
	local function premiumOk(e)
		return own.access or not e.premium or own.premium
	end
	local out = {outfit = {}, mount = {}, wings = {}, aura = {}, shader = {}}
	for _, e in ipairs(cat.outfit or {}) do
		local addons = (own.access and 3) or W.outfitAddons(e.look, own.hasOutfit)
		local s = src.outfit[e.look]
		if e.free then
			s = s and ("Free; addons: " .. s) or "Free" -- an outfit everyone has: the source is its addons'
		end
		out.outfit[#out.outfit + 1] = {l = e.look, n = e.name, o = addons and 1 or nil, a = addons, s = s}
	end
	for _, e in ipairs(cat.mount or {}) do
		local o = own.access or (premiumOk(e) and own.hasMount(e.id) == true)
		out.mount[#out.mount + 1] = {l = e.look, n = e.name, o = o and 1 or nil, s = src.mount[e.id]}
	end
	for _, kind in ipairs({"wings", "aura"}) do
		for _, e in ipairs(cat[kind] or {}) do
			local o = own.access or (premiumOk(e) and W.bitOwned(W.RANGES[kind], e.id, own.value))
			out[kind][#out[kind] + 1] = {l = e.look, n = e.name, o = o and 1 or nil, s = src[kind][e.id]}
		end
	end
	for _, e in ipairs(cat.shader or {}) do
		local o = own.access or (premiumOk(e) and W.bitOwned(W.RANGES.shader, e.id, own.value))
		out.shader[#out.shader + 1] = {n = e.name, o = o and 1 or nil, s = src.shader[e.id]}
	end
	return out
end

-- a short fingerprint of a list (the client keeps the last one; "wardrobe" answers carry it)
function W.hash(text)
	local h = 5381
	for i = 1, #text do
		h = (h * 33 + text:byte(i)) % 4294967296
	end
	return string.format("%08x", h)
end

return W
