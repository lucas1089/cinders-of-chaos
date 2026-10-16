-- Run from the server/ folder: luajit tests/wardrobe_test.lua (and lua5.3; CI runs both)
-- The wardrobe catalogue (wardrobe_core.lua, wardrobe.lua): the XML catalogues per sex, the engine's ownership rules
-- (outfit addons, mounts, the storage bits of wings, auras and shaders, access and premium), the unlock sources (store
-- offers of the real shop_config.lua, exclusives, class looks) and the list the client gets.
CONST_ME_FIREWORK_YELLOW = CONST_ME_FIREWORK_YELLOW or 29 -- shop_config.lua reads it
dofile("data/scripts/chaos/chaos_constants.lua")
dofile("data/scripts/chaos/wardrobe_core.lua")
local W = ChaosWardrobeCore

local n = 0
local function eq(a, b, m)
	n = n + 1
	if a ~= b then
		error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2)
	end
end

local xml = {
	outfits = [[<?xml version="1.0"?>
<outfits>
	<!-- Female outfits -->
	<outfit type="0" looktype="136" name="Citizen" premium="no" unlocked="yes" enabled="yes" />
	<outfit type="0" looktype="137" name="Hunter" premium="no" unlocked="yes" enabled="yes" />
	<outfit type="0" looktype="2074" name="Warrior Class" premium="no" unlocked="no" enabled="yes" />
	<!-- <outfit type="0" looktype="999" name="Commented" unlocked="yes" enabled="yes" /> -->
	<outfit type="1" looktype="128" name="Citizen" premium="no" unlocked="yes" enabled="yes" />
	<outfit type="1" looktype="2073" name="Warrior Class" premium="no" unlocked="no" enabled="yes" />
	<outfit type="1" looktype="1455" name="Wingbound" premium="no" unlocked="no" enabled="yes" />
	<outfit type="1" looktype="700" name="Disabled" premium="no" unlocked="no" enabled="no" />
	<outfit type="1" looktype="128" name="Citizen again" premium="no" unlocked="yes" enabled="yes" />
</outfits>]],
	mounts = [[<mounts>
	<mount id="1" clientid="368" name="Widow Queen" speed="20" premium="yes" />
	<mount id="2" clientid="369" name="Racing Bird" speed="20" premium="no" />
	<mount id="146" clientid="1323" name="Tuskhide Boar" speed="20" premium="no" />
</mounts>]],
	wings = [[<wings>
<wing id="1" clientid="937" name="Fiery Wings" speed="20" />
<wing id="33" clientid="990" name="Late Wings" speed="20" />
</wings>]],
	auras = [[<auras>
<aura id="1" clientid="932" name="Fire Essence" speed="20" />
<aura id="2" clientid="933" name="Electric Shock" speed="20" premium="yes" />
</auras>]],
	shaders = [[<shaders>
    <shader id="1" name="blue_loohs" premium="no" />
     <shader id="19" name="chaos_ember_glow" premium="no" />
</shaders>]]
}

-- ---------------------------------------------------------------- the catalogue
local male = W.catalogue(xml, 1)
eq(#male.outfit, 3, "male outfits: disabled, female and a repeated look left out")
eq(male.outfit[1].look, 128, "file order")
eq(male.outfit[1].free, true, "unlocked = free")
eq(male.outfit[2].free, false, "class look is not free")
local female = W.catalogue(xml, 0)
eq(#female.outfit, 3, "female outfits (the commented one is skipped)")
eq(#male.mount, 3, "mounts")
eq(male.mount[1].premium, true, "premium mount")
eq(male.mount[3].look, 1323, "mount client look")
eq(#male.wings, 2, "wings")
eq(#male.aura, 2, "auras")
eq(male.shader[2].name, "chaos_ember_glow", "shader name")

-- ---------------------------------------------------------------- ownership
local storage = {}
local function value(k) return storage[k] end
eq(W.bitOwned(W.RANGES.wings, 1, value), false, "no storage, no wing")
storage[W.RANGES.wings] = 1 -- bit 0: wing 1
eq(W.bitOwned(W.RANGES.wings, 1, value), true, "wing 1 bit")
eq(W.bitOwned(W.RANGES.wings, 2, value), false, "wing 2 not set")
storage[W.RANGES.wings + 1] = 2 ^ (32 % 31) -- wing 33: key +1, bit 1
eq(W.bitOwned(W.RANGES.wings, 33, value), true, "wing 33 in the second key")
storage[W.RANGES.shader] = 2 ^ 18 + 1 -- shaders 1 and 19
eq(W.bitOwned(W.RANGES.shader, 19, value), true, "shader 19")
eq(W.bitOwned(W.RANGES.shader, 0, value), false, "id 0 is never owned")
storage[W.RANGES.aura] = -1
eq(W.bitOwned(W.RANGES.aura, 1, value), false, "unset storage (-1) owns nothing")

local outfits = {[128] = 3, [2073] = 0, [137] = 1}
local function hasOutfit(look, addons)
	local have = outfits[look]
	if have == nil then return false end
	if addons == 0 then return true end
	return have == 3 or have == addons
end
eq(W.outfitAddons(128, hasOutfit), 3, "full addons")
eq(W.outfitAddons(2073, hasOutfit), 0, "no addons")
eq(W.outfitAddons(137, hasOutfit), 1, "first addon")
eq(W.outfitAddons(1455, hasOutfit), nil, "not owned")

-- ---------------------------------------------------------------- sources (the real store, exclusives, class looks)
local shop = dofile("data/scripts/chaos/shop_config.lua")
local excl = dofile("data/scripts/chaos/exclusives_config.lua")
local src = W.sources({shopOffers = shop, exclusives = excl.exclusives, how = function(e) return "Boss: " .. e.name end,
	classLooks = {[4] = {name = "Warrior Class", male = 2073, female = 2074}}})
eq(src.wings[1], "Store", "store wings 1")
eq(src.outfit[1455], "Boss: Wingbound", "exclusive outfit source")
eq(src.mount[146], "Boss: Tuskhide Boar", "exclusive mount source (mounts.xml id)")
eq(src.outfit[2073], "Class: Warrior Class", "class look source")
local storeLooks = 0
for _ in pairs(src.outfit) do storeLooks = storeLooks + 1 end
eq(storeLooks > 10, true, "store outfits found at any depth of shop_config.lua")
-- an exclusive is never sold, so its text stays first
local src2 = W.sources({exclusives = {{kind = "mount", id = 5}}, how = function() return "Achievement" end,
	shopOffers = {{kind = "mount", id = 5}}})
eq(src2.mount[5], "Achievement", "the first source is kept")

-- ---------------------------------------------------------------- the list
local mounts = {[2] = true}
local own = {access = false, premium = false, hasOutfit = hasOutfit, hasMount = function(id) return mounts[id] == true end,
	value = value}
local list = W.list(male, src, own)
eq(#list.outfit, 3, "every outfit listed")
eq(list.outfit[1].o, 1, "Citizen owned")
eq(list.outfit[1].a, 3, "with addons")
eq(list.outfit[1].s, "Free; addons: Store", "Citizen is free, its addons in the store")
eq(list.outfit[3].o, nil, "Wingbound not owned")
eq(list.outfit[3].s, "Boss: Wingbound", "Wingbound source")
eq(list.mount[2].o, 1, "Racing Bird owned")
eq(list.mount[1].o, nil, "Widow Queen not owned")
eq(list.mount[2].l, 369, "mount listed by client look")
eq(list.wings[1].o, 1, "wing 1 owned")
eq(list.wings[2].o, 1, "wing 33 owned")
eq(list.aura[1].o, nil, "aura 1 not owned")
eq(list.shader[1].o, 1, "shader 1 owned")
eq(list.shader[2].n, "chaos_ember_glow", "shader by name")
-- premium: a premium entry needs premium even with its bit set
mounts[1] = true
storage[W.RANGES.aura] = 3 -- auras 1, 2
eq(W.list(male, src, own).mount[1].o, nil, "premium mount without premium")
eq(W.list(male, src, own).aura[2].o, nil, "premium aura without premium")
own.premium = true
eq(W.list(male, src, own).mount[1].o, 1, "premium mount with premium")
eq(W.list(male, src, own).aura[2].o, 1, "premium aura with premium")
-- access players own everything
local all = W.list(male, src, {access = true, hasOutfit = function() return false end, hasMount = function() return false end,
	value = function() return nil end})
for _, kind in ipairs(W.KINDS) do
	for _, e in ipairs(all[kind]) do
		eq(e.o, 1, "access owns " .. kind .. " " .. tostring(e.n))
	end
end
eq(all.outfit[2].a, 3, "access has every addon")
eq(W.hash("abc"), W.hash("abc"), "hash stable")
eq(W.hash("abc") ~= W.hash("abd"), true, "hash differs")
eq(#W.hash("x"), 8, "hash length")

-- the engine file names the cosmetics opcode and the action the client sends
local f = io.open("data/scripts/chaos/wardrobe.lua", "r")
local text = f:read("*a")
f:close()
eq(text:find("ChaosOpcodes.cosmetics", 1, true) ~= nil, true, "wardrobe.lua uses the cosmetics opcode")
eq(text:find("Chaos.sendChunked", 1, true) ~= nil, true, "the list is sent in chunks")
f = io.open("data/scripts/chaos/cosmetics.lua", "r")
text = f:read("*a")
f:close()
eq(text:find('msg.action == "wardrobe"', 1, true) ~= nil, true, "cosmetics.lua routes the wardrobe action")

print(string.format("wardrobe_test: %d checks OK", n))
