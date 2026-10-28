-- Run from the server/ folder: luajit tests/item_names_test.lua (and lua5.3; CI runs both)
-- Item names after the modifiers (data/lib/chaos_crafting.lua C.affixName / C.applyName; words in
-- data/lib/chaos_item_mods.lua config.names): every affix has a word, the best prefix and suffix win, the stock name
-- is the base, uniques / waystones / foreign names are left alone, and a normal item gets its stock name back.

local function eq(a, b, m)
	if a ~= b then
		error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2)
	end
end

ITEM_ATTRIBUTE_DESCRIPTION, ITEM_ATTRIBUTE_NAME, ITEM_ATTRIBUTE_ARTICLE = 1, 2, 3
local TYPES = {[2400] = {name = "longsword"}, [2466] = {name = "plate armor"}, [2214] = {name = "ring of healing"},
	[3000] = {name = "unicorn pelt"}}
function ItemType(id)
	local t = TYPES[id] or {}
	return {getName = function() return t.name or "" end}
end
local Item = {}
Item.__index = Item
local function newItem(id)
	return setmetatable({id = id, attrs = {}, custom = {}}, Item)
end
function Item:getId() return self.id end
function Item:getName() return self.attrs[ITEM_ATTRIBUTE_NAME] or ItemType(self.id):getName() end
function Item:getCustomAttribute(k) return self.custom[k:lower()] end
function Item:setCustomAttribute(k, v) self.custom[k:lower()] = v end
function Item:removeCustomAttribute(k) self.custom[k:lower()] = nil return true end
function Item:getAttribute(k) return self.attrs[k] end
function Item:setAttribute(k, v) self.attrs[k] = v end
function Item:removeAttribute(k) self.attrs[k] = nil end

dofile("data/lib/chaos_crafting.lua")
local C, M = ChaosCrafting, ChaosItemMods

-- every affix has a name word; the words are plain text and unique per side
local seen = {}
for _, a in ipairs(C.affixes()) do
	local key = a.chaosKey or a.key:lower()
	local w = M.config.names.words[key]
	eq(type(w) == "table" and type(w[1]) == "string", true, "word for " .. key)
	for i = 1, 2 do
		if w[i] then
			eq(w[i]:find("[Oo][Rr][Bb]") == nil, true, "no orb in " .. w[i])
			eq(w[i]:find("[%[%]{}]") == nil, true, "no bracket in " .. w[i])
			eq(w[i]:find("^of ") ~= nil, a.side == "suffix", "side shape of " .. w[i])
			if key ~= "rarity_clubskill" and key ~= "rarity_axeskill" and key ~= "rarity_swordskill" then
				eq(seen[w[i]], nil, "word used twice: " .. w[i])
				seen[w[i]] = key
			end
		end
	end
end
local known = {}
for _, a in ipairs(C.affixes()) do
	known[a.chaosKey or a.key:lower()] = true
end
for k in pairs(M.config.names.words) do
	eq(known[k], true, "word of an unknown affix " .. k)
end

-- the pure name
local function mod(key, side, tier, value, chaosKey)
	return {key = key, chaosKey = chaosKey, side = side, tier = tier, value = value}
end
local crit = mod("rarity_criticalHitChance", "prefix", 3, 4)
local haste = mod("chaos_mod_attackspeed", "suffix", 3, 5, "attackspeed")
eq(C.affixName("longsword", {crit, haste}), "Vicious Longsword of Haste", "the example")
eq(C.affixName("longsword", {crit}), "Vicious Longsword", "prefix only")
eq(C.affixName("longsword", {haste}), "Longsword of Haste", "suffix only")
eq(C.affixName("longsword", {}), nil, "no mods")
eq(C.affixName("longsword", {mod("rarity_elementfire", "prefix", 3, 5), crit}), "Searing Longsword",
	"equal tier and value: the earlier one")
eq(C.affixName("longsword", {mod("rarity_elementfire", "prefix", 3, 5), mod("rarity_criticalHitChance", "prefix", 3, 6)}),
	"Vicious Longsword", "equal tier: the larger value")
eq(C.affixName("longsword", {mod("rarity_elementfire", "prefix", 4, 1), mod("rarity_criticalHitChance", "prefix", 3, 9)}),
	"Searing Longsword", "the higher tier first")
eq(C.affixName("longsword", {mod("rarity_criticalHitChance", "prefix", 8, 9)}), "Murderous Longsword", "top word")
eq(C.affixName("ring of healing", {haste}), "Ring of Healing of Haste", "small words stay small")
eq(C.affixName("longsword", {mod("chaos_mod_x", "implicit", 3, 5, "attackspeed")}), nil, "an implicit gives no name")
eq(C.articleOf("Ensorcelled Ring"), "an")
eq(C.articleOf("Vicious Longsword"), "a")
eq(C.articleOf("Unicorn Pelt"), "a")
eq(C.articleOf("Umbral Cloak"), "an")

-- on an item
local sword = newItem(2400)
sword:setCustomAttribute("rarity", 3)
sword:setCustomAttribute("chaos_ilvl", 40)
sword:setCustomAttribute("rarity_criticalHitChance", 3)
sword:setCustomAttribute("rarity_criticalHitAmount", 4)
sword:setCustomAttribute(M.attr("attackspeed"), 5)
sword:setAttribute(ITEM_ATTRIBUTE_DESCRIPTION, "")
C.rewriteDescription(sword)
local first = sword:getName()
eq(first:find("Longsword") ~= nil, true, "named " .. first)
eq(sword:getAttribute(ITEM_ATTRIBUTE_ARTICLE) ~= nil, true, "article set")
eq(sword:getCustomAttribute(M.NAME_MARK), 1, "marked")
C.rewriteDescription(sword)
eq(sword:getName(), first, "idempotent")
eq(ItemType(2400):getName(), "longsword")
-- the modifiers go: the stock name comes back
C.clearMods(sword)
sword:setCustomAttribute("rarity", 0)
C.rewriteDescription(sword)
eq(sword:getAttribute(ITEM_ATTRIBUTE_NAME), nil, "name removed")
eq(sword:getAttribute(ITEM_ATTRIBUTE_ARTICLE), nil, "article removed")
eq(sword:getCustomAttribute(M.NAME_MARK), nil, "mark removed")
eq(sword:getName(), "longsword", "stock name")

-- uniques and names of other scripts stay
local uniq = newItem(2400)
uniq:setCustomAttribute("chaos_unique", 1)
uniq:setCustomAttribute(M.attr("attackspeed"), 5)
uniq:setAttribute(ITEM_ATTRIBUTE_NAME, "dawnbreaker")
C.rewriteDescription(uniq)
eq(uniq:getName(), "dawnbreaker", "a unique keeps its name")
local foreign = newItem(2466)
foreign:setAttribute(ITEM_ATTRIBUTE_NAME, "starter armor")
foreign:setCustomAttribute(M.attr("attackspeed"), 5)
foreign:setCustomAttribute("rarity", 1)
C.rewriteDescription(foreign)
eq(foreign:getName(), "starter armor", "a name of another script stays")

-- the mark travels with a copy
local keys = {}
for _, k in ipairs(C.attributeKeys()) do
	keys[k] = true
end
eq(keys[M.NAME_MARK], true, "mark copied with the item")
print("item_names_test: OK")
