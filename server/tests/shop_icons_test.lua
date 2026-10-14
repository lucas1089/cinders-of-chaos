-- Run from the server/ folder: luajit tests/shop_icons_test.lua (and lua5.3; CI runs both)
-- Store pictures (shop_core.lua C.iconCount, shop.lua). Live test 2026-10-14: the Stormcaller Regalia showed as a dot.
-- Its icon was a small amethyst: a stackable item, drawn by its count, and one small gem is a few pixels in the cell.
-- Every item picture of the store (the offers of shop_config.lua, the cosmetic unlocks of cosmetics_config.lua, the
-- category icons) is checked here: a small stackable item (gems, coins) is drawn as a pile, and a bundle has a real
-- item picture.

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
local K = ChaosShopCore

-- stackable items whose single copy is a few pixels: the small gems, the small enchanted gems, the coins
local TINY = {[2145] = "small diamond", [2146] = "small sapphire", [2147] = "small ruby", [2149] = "small emerald",
	[2150] = "small amethyst", [7759] = "small enchanted sapphire", [7760] = "small enchanted ruby",
	[7761] = "small enchanted emerald", [7762] = "small enchanted amethyst", [2148] = "gold coin",
	[2152] = "platinum coin", [2160] = "crystal coin"}
local MIN_PILE = 5 -- the first count with a pile sprite

-- the count the client draws `icon` with (stackable as the engine says for these ids)
local function drawn(icon, id)
	return K.iconCount(icon, TINY[id] ~= nil)
end

-- an item picture of an offer (shop.lua clientOffer): services, unlocks without a look, frames, bundles
local function itemPicture(o)
	if o.kind == "unlock" and o.look then
		return false
	end
	return o.kind == "service" or o.kind == "unlock" or o.kind == "frame" or o.kind == "bundle"
end

local cfg = dofile("data/scripts/chaos/shop_config.lua")
local seen = 0
for _, cat in ipairs(cfg.categories) do
	if type(cat.icon) == "table" and cat.icon.item then
		local id = cat.icon.item
		check(not TINY[id] or drawn(cat.icon, id) >= MIN_PILE,
			"category " .. cat.name .. ": " .. tostring(TINY[id]) .. " drawn as one (a dot)")
	end
	for _, o in ipairs(cat.offers or {}) do
		if itemPicture(o) then
			seen = seen + 1
			local id = o.icon or 1949
			check(type(id) == "number" and id > 0, (o.name or "?") .. ": an item id")
			check(not TINY[id] or drawn(o, id) >= MIN_PILE,
				(o.name or "?") .. ": " .. tostring(TINY[id]) .. " drawn as one (a dot)")
			if o.kind == "bundle" then
				check(not (TINY[id] or ""):find("small"), (o.name or "?") .. ": a bundle shows a real item, not a "
					.. tostring(TINY[id]))
			end
		end
	end
end
check(seen > 20, "offers with item pictures found (" .. seen .. ")")

-- the cosmetic unlocks (cosmetics_store.lua turns each into {kind = "unlock", icon = c.icon})
local cos = dofile("data/scripts/chaos/cosmetics_config.lua")
local cosSeen = 0
local function walk(t, depth)
	if type(t) ~= "table" or depth > 4 then
		return
	end
	if type(t.icon) == "number" and t.key then
		cosSeen = cosSeen + 1
		local offer = {kind = "unlock", icon = t.icon}
		check(not TINY[t.icon] or drawn(offer, t.icon) >= MIN_PILE, "cosmetic " .. t.key .. ": drawn as one (a dot)")
	end
	for _, v in pairs(t) do
		walk(v, depth + 1)
	end
end
walk(cos, 0)
check(cosSeen > 20, "cosmetic icons found (" .. cosSeen .. ")")

-- the regression itself
for _, cat in ipairs(cfg.categories) do
	for _, o in ipairs(cat.offers or {}) do
		if o.key == "bundle:storm" then
			check(o.icon ~= 2150, "Stormcaller Regalia: no small amethyst")
		end
	end
end
check(K.iconCount({iconCount = 3}, true) == 3, "an own iconCount wins")
check(K.iconCount({count = 7}, true) == 7, "a category's own count wins")
check(K.iconCount({}, false) == 1, "a non-stackable item is drawn once")
check(K.iconCount({}, true) >= MIN_PILE, "a stackable item is drawn as a pile")

if failures > 0 then
	error(string.format("%d of %d checks failed", failures, checks))
end
print(string.format("shop_icons_test: %d checks passed", checks))
