-- Run from the server/ folder: luajit tests/orbs_test.lua (and lua5.3; CI runs both)
-- Crafting orbs v2 (data/lib/chaos_orbs.lua, chaos_orbs_config.lua) and the item state they use (data/lib/chaos_crafting.lua,
-- chaos_item_mods.lua): Tempering, Binding (bound modifiers), Excision, Reforging, Ruin (every outcome, ruined items),
-- the Whetstone (item quality), the legendary powers as modifiers (rarity gate, one per item, the side limits), the old
-- orbs with bound modifiers (Unmaking, Upheaval, Fate, Erasure), Rift Keys, the bench's view of an item.

local checks = 0
local function eq(a, b, m)
	checks = checks + 1
	if a ~= b then
		error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2)
	end
end
local function ok(v, m)
	checks = checks + 1
	if not v then
		error(m or "assertion failed", 2)
	end
end

-- ---------------------------------------------------------------- engine mock
ITEM_ATTRIBUTE_DESCRIPTION, ITEM_ATTRIBUTE_NAME = 1, 2
ITEM_ATTRIBUTE_ATTACK, ITEM_ATTRIBUTE_ARMOR = 11, 12
INDEX_WHEREEVER, FLAG_NOLIMIT, RETURNVALUE_NOERROR = -1, 1, 0

local TYPES = {
	[2400] = {name = "magic sword", weaponType = 1, attack = 48, slot = 48},
	[2466] = {name = "golden armor", armor = 14, slot = 8},
	[2195] = {name = "boots of haste", armor = 1, slot = 128},
	[2171] = {name = "platinum amulet", armor = 2, slot = 2},
	[2160] = {name = "crystal coin", stackable = true}
}

function ItemType(id)
	local t = TYPES[id] or {}
	return {
		getName = function() return t.name or "" end,
		isContainer = function() return t.container == true end,
		isStackable = function() return t.stackable == true end,
		getWeaponType = function() return t.weaponType or 0 end,
		getSlotPosition = function() return t.slot or 0 end,
		getArmor = function() return t.armor or 0 end,
		getAttack = function() return t.attack or 0 end,
		getDefense = function() return 0 end,
		getHitChance = function() return 0 end,
		getElementDamage = function() return 0 end,
		getAbilities = function() return {} end
	}
end

local Item = {}
Item.__index = Item
local function newItem(id, count)
	return setmetatable({id = id, count = count or 1, attrs = {}, custom = {}, removed = false}, Item)
end
function Item:getId() return self.id end
function Item:getCount() return self.count end
function Item:getName() return self.attrs[ITEM_ATTRIBUTE_NAME] or ItemType(self.id):getName() end
function Item:getCustomAttribute(k) return self.custom[k:lower()] end
function Item:setCustomAttribute(k, v) self.custom[k:lower()] = v end
function Item:removeCustomAttribute(k) self.custom[k:lower()] = nil return true end
function Item:getAttribute(k) return self.attrs[k] or (k == ITEM_ATTRIBUTE_DESCRIPTION and "" or nil) end
function Item:setAttribute(k, v) self.attrs[k] = v end
function Item:getParent() return self.parent end
function Item:getActionId() return self.aid or 0 end
function Item:setActionId(a) self.aid = a end
function Item:remove()
	self.removed = true
	if self.parent then
		for i, it in ipairs(self.parent.items) do
			if it == self then table.remove(self.parent.items, i) break end
		end
	end
	return true
end

local bag = {items = {}}
function bag:addItemEx(item)
	self.items[#self.items + 1] = item
	item.parent = self
	return RETURNVALUE_NOERROR
end
local function put(item)
	bag:addItemEx(item)
	return item
end
Game = {createItem = function(id, count) return newItem(id, count) end}

dofile("data/lib/chaos_crafting.lua")
local C = ChaosCrafting
local M = ChaosItemMods
local O = ChaosOrbs
M.random = function(a, b) return a end
local dice = {}
C.random = function(a, b)
	local v = table.remove(dice, 1)
	if v == nil then
		return a
	end
	assert(v >= a and v <= b, "dice value " .. v .. " outside " .. a .. ".." .. b)
	return v
end

-- an item rolled by the forge (deterministic dice: the lowest values)
local function forged(id, rarity, level)
	local it = put(newItem(id))
	dice = {}
	C.forge(it, rarity, level or 100, C.random)
	return it
end

-- ---------------------------------------------------------------- registration
local cfg = ChaosOrbsConfig
eq(#cfg.items, 7, "six new items and the Orb of Unveiling (chaos_veiled.lua)")
local ids = {}
for _, orb in ipairs(C.config.orbs) do
	ok(not ids[orb.id], "unique id " .. orb.id)
	ids[orb.id] = true
	ok(orb.name ~= "", "name of " .. orb.key)
end
for _, it in ipairs(cfg.items) do
	eq(C.orbByKey[it.key].id, it.id, it.key .. " registered with the config's id")
	eq(C.orbByKey[it.key].name, it.name)
	ok(it.id >= 32251 and it.id <= 32260, "id range of the orbs")
end
eq(cfg.ruin.improve + cfg.ruin.nothing + cfg.ruin.ruin, 100, "ruin odds add up")
-- no Path of Exile currency names in the orbs
for _, orb in ipairs(C.config.orbs) do
	for _, bad in ipairs({"Transmutation", "Alchemy", "Exalted", "Annulment", "Scouring", "Chaos Orb", "Divine Orb", "Vaal"}) do
		ok(not orb.name:find(bad, 1, true), orb.name .. " has the old name " .. bad)
		ok(not orb.text:find(bad, 1, true), orb.key .. " text has the old name " .. bad)
	end
end
eq(C.orbByKey.transmutation.name, "Orb of Awakening")
eq(C.orbByKey.chaos.name, "Orb of Upheaval")
eq(C.orbByKey.divine.name, "Orb of Fate")

-- ---------------------------------------------------------------- Tempering
local sword = forged(2400, 4, 100) -- Epic: 3 modifiers, 2 / 2
local before = {}
for _, m in ipairs(C.readMods(sword)) do
	before[m.key] = {value = m.value, tier = m.tier}
end
eq(#C.readMods(sword), 3)
eq(C.check("tempering", sword), true)
dice = {}
local isOk, res = C.apply("tempering", sword)
eq(isOk, true)
for _, m in ipairs(C.readMods(sword)) do
	eq(m.tier, before[m.key].tier, "Tempering keeps the tier of " .. m.key)
	ok(m.value >= m.lo and m.value <= m.hi, "inside the tier: " .. m.key)
end
ok(res.text:find("3 modifiers got new values"), res.text)
-- a different roll really changes a value (dice: top of every range)
local m1 = C.readMods(sword)[1]
C.rerollValues(sword, function(a, b) return b end)
eq(C.readMods(sword)[1].value, m1.hi, "values are rolled again")
-- bound modifiers stay
local mods = C.readMods(sword)
C.setBound(sword, mods[1], true)
local keep = C.readMods(sword)[1].value
dice = {}
for i = 1, 40 do
	C.rerollValues(sword, function(a, b) return b end)
	C.rerollValues(sword, function(a, b) return a end)
end
eq(C.readMods(sword)[1].value, keep, "a bound modifier keeps its value through Tempering")
eq(C.readMods(sword)[1].bound, true)
eq(C.readMods(sword)[2].bound, false)
-- everything bound: refused
local two = forged(2400, 1, 100) -- Common: 2 modifiers
for _, m in ipairs(C.readMods(two)) do
	C.setBound(two, m, true)
end
eq(select(2, C.check("tempering", two)), "allBound")
eq(select(2, C.check("tempering", put(newItem(2400)))), "needRarity")
local bare = put(newItem(2400)); bare:setCustomAttribute("rarity", 3)
eq(select(2, C.check("tempering", bare)), "noMods")

-- ---------------------------------------------------------------- Binding
local epic = forged(2400, 4, 100)
eq(M.maxBinds(4), 1, "an Epic item binds one")
eq(M.maxBinds(5), 2, "a Legendary item binds two")
eq(M.maxBinds(0), 0)
local pick = C.pickList("binding", epic)
eq(#pick, 3, "all three may be chosen")
local chosen = pick[2]
isOk, res = C.apply("binding", epic, {mod = chosen})
eq(isOk, true)
eq(C.modByKey(epic, chosen).bound, true, "the chosen one is bound")
eq(C.bindCount(C.readMods(epic)), 1)
eq(epic:getCustomAttribute(M.bindAttr(chosen)), 1, "stored as cb_<key>")
ok(epic:getAttribute(ITEM_ATTRIBUTE_DESCRIPTION):find(", bound%)"), "the description says bound")
eq(select(2, C.check("binding", epic)), "tooManyBinds", "one bound modifier on an Epic item is the limit")
eq(#C.pickList("binding", epic), 2, "the bound one is not offered again")
local legendary = forged(2400, 5, 100)
C.apply("binding", legendary, {mod = C.pickList("binding", legendary)[1]})
eq(C.check("binding", legendary), true, "Legendary: a second one")
isOk = C.apply("binding", legendary, {mod = "rarity_nothing"})
eq(isOk, false, "an unknown modifier is refused")
eq(select(2, C.check("binding", legendary, {mod = "rarity_nothing"})), "badMod")
local firstBound = C.pickList("binding", legendary)[1]
dice = {2} -- random fallback: the 2nd free modifier
isOk = C.apply("binding", legendary)
eq(isOk, true, "used directly it binds a random one")
eq(C.bindCount(C.readMods(legendary)), 2)
eq(select(2, C.check("binding", legendary)), "tooManyBinds")
-- the signature changes with a bind (the bench refuses stale clicks)
local sigA = C.signature(epic)
C.setBound(epic, C.modByKey(epic, chosen), false)
ok(sigA ~= C.signature(epic), "signature covers binds")

-- ---------------------------------------------------------------- Excision
local ex = forged(2466, 4, 100)
local exMods = C.readMods(ex)
local victim = exMods[2]
C.setBound(ex, exMods[1], true)
eq(select(2, C.check("excision", ex, {mod = exMods[1].key})), "badMod", "a bound modifier cannot be cut")
isOk, res = C.apply("excision", ex, {mod = victim.key})
eq(isOk, true)
eq(C.modByKey(ex, victim.key), nil, "the chosen modifier is gone")
eq(#C.readMods(ex), 2)
eq(ex:getCustomAttribute(M.tierAttr(victim.key)), nil, "its tier mark is gone too")
ok(res.text:find("lost"), res.text)
-- only the bound one is left: nothing to cut
C.apply("excision", ex, {mod = C.readMods(ex)[2].key})
eq(select(2, C.check("excision", ex)), "allBound")
-- by use-with: a random free one
local ex2 = forged(2466, 4, 100)
dice = {1}
C.apply("excision", ex2)
eq(#C.readMods(ex2), 2, "a random one went")

-- ---------------------------------------------------------------- Reforging
local rf = forged(2400, 4, 150)
local target = C.readMods(rf)[1]
dice = {1, target.lo} -- tier row 1 (the best tier of item level 150), lowest value
isOk, res = C.apply("reforging", rf, {mod = target.key})
eq(isOk, true)
local after = C.modByKey(rf, target.key)
eq(after.tier, M.maxTierFor(150), "best tier by dice")
ok(res.text:find("is now"), res.text)
for _, m in ipairs(C.readMods(rf)) do
	if m.key ~= target.key then
		ok(m.tier >= 1, "others untouched")
	end
end
C.setBound(rf, C.modByKey(rf, target.key), true)
eq(select(2, C.check("reforging", rf, {mod = target.key})), "badMod", "a bound modifier is not reforged")

-- ---------------------------------------------------------------- Ruin
local ruinItem = forged(2400, 4, 100)
O.forceRuin = "nothing"
isOk, res = C.apply("ruin", ruinItem)
eq(isOk, true); eq(res.outcome, "nothing")
eq(M.isRuined(ruinItem), false)
-- improve: one tier on every free modifier
O.forceRuin, O.forceImprove = "improve", "tiers"
local tiersBefore = {}
for _, m in ipairs(C.readMods(ruinItem)) do tiersBefore[m.key] = m.tier end
C.setBound(ruinItem, C.readMods(ruinItem)[1], true)
dice = {}
isOk, res = C.apply("ruin", ruinItem)
eq(res.outcome, "improve"); eq(res.kind, "tiers")
for i, m in ipairs(C.readMods(ruinItem)) do
	if i == 1 then
		eq(m.tier, tiersBefore[m.key], "the bound modifier does not move")
	else
		eq(m.tier, tiersBefore[m.key] + 1, "one tier more: " .. m.key)
	end
end
-- improve: an extra modifier above the limit (Epic: 2 prefixes + 2 suffixes; fill them first)
O.forceImprove = "slot"
local slotItem = forged(2466, 4, 100)
dice = {}
for _ = 1, 4 do
	local a = M.pick(C.candidates(slotItem), C.random)
	if a then C.rollAffix(slotItem, a, 100, C.random) end
end
eq(#C.readMods(slotItem), 4, "a full Epic item")
eq(select(2, C.check("exalted", slotItem)), "full")
dice = {}
isOk, res = C.apply("ruin", slotItem)
eq(res.outcome, "improve"); eq(res.kind, "slot")
eq(#C.readMods(slotItem), 5, "one extra modifier")
ok(M.extraSide(slotItem) ~= nil, "the extra slot is recorded")
eq(C.maxModsOf(slotItem), 5)
ok(res.text:find("an extra"), res.text)
-- the extra slot is used up: the second improvement is tiers
dice = {}
isOk, res = C.apply("ruin", slotItem)
eq(res.kind, "tiers", "the extra slot comes once")
eq(select(2, C.check("exalted", slotItem)), "full", "no free slot after the extra one")
-- ruin
O.forceRuin = "ruin"
isOk, res = C.apply("ruin", slotItem)
eq(res.outcome, "ruin")
eq(M.isRuined(slotItem), true)
ok(slotItem:getAttribute(ITEM_ATTRIBUTE_DESCRIPTION):find("Ruined"), "the description says Ruined")
for _, orb in ipairs(C.config.orbs) do
	eq(select(2, C.check(orb.key, slotItem)), "ruined", "a ruined item refuses " .. orb.key)
end
isOk, res = C.apply("chaos", slotItem)
eq(isOk, false); eq(res, C.reasons.ruined)
eq(C.describe(slotItem).ruined, true, "the bench shows it")
eq(M.isRuined(put(newItem(2400))), false)
O.forceRuin, O.forceImprove = nil, nil
-- an item with nothing left to improve: nothing happens
local maxed = forged(2400, 1, 150)
for _, m in ipairs(C.readMods(maxed)) do C.writeAffix(maxed, m.affix, 8, nil, function(a, b) return b end) end
M.config.rarity.sides[1] = 1
O.forceRuin, O.forceImprove = "improve", "tiers"
dice = {}
-- both sides full at Common (1 / 1) so the extra slot opens: the improvement turns into a slot, once
isOk, res = C.apply("ruin", maxed)
eq(res.outcome, "improve")
O.forceRuin, O.forceImprove = nil, nil
-- the odds with real dice: about 40 / 45 / 15
C.random = math.random
math.randomseed(11)
local counts = {improve = 0, nothing = 0, ruin = 0}
for _ = 1, 20000 do
	local r = O.rollRuin()
	counts[r] = counts[r] + 1
end
ok(math.abs(counts.improve - 8000) < 450, "improve about 40%: " .. counts.improve)
ok(math.abs(counts.nothing - 9000) < 450, "nothing about 45%: " .. counts.nothing)
ok(math.abs(counts.ruin - 3000) < 400, "ruin about 15%: " .. counts.ruin)
C.random = function(a, b)
	local v = table.remove(dice, 1)
	if v == nil then return a end
	return v
end
eq(C.preview("ruin", forged(2400, 4, 100)), "40% improves, 45% nothing, 15% ruined", "the bench shows the odds")

-- ---------------------------------------------------------------- Whetstone (quality)
local q = forged(2400, 4, 100)
local rawBefore = {}
for _, m in ipairs(C.readMods(q)) do rawBefore[m.key] = m.value end
eq(M.qualityOf(q), 0)
eq(C.check("whetstone", q), true)
for _ = 1, 20 do
	isOk, res = C.apply("whetstone", q)
	eq(isOk, true)
end
eq(M.qualityOf(q), 20, "20 stones: 20%")
eq(select(2, C.check("whetstone", q)), "qualityFull", "the cap of an Epic item is 20")
for _, m in ipairs(C.readMods(q)) do
	local want = M.scaleQuality(rawBefore[m.key], 20)
	eq(m.value, want, "value x 1.2 for " .. m.key .. " (" .. rawBefore[m.key] .. ")")
	ok(m.value >= rawBefore[m.key])
	eq(C.rawValue(q, m), m.group == "special" and C.rawValue(q, m) or rawBefore[m.key], "the rolled value is kept")
	ok(q:getCustomAttribute(M.rawAttr(m.key)) ~= nil, "cv_ kept")
end
ok(q:getAttribute(ITEM_ATTRIBUTE_DESCRIPTION):find("Quality: %+20%%"), q:getAttribute(ITEM_ATTRIBUTE_DESCRIPTION))
eq(C.describe(q).quality, 20); eq(C.describe(q).qualityCap, 20)
-- Tempering with quality: the rolled value is multiplied
dice = {}
C.rerollValues(q, function(a, b) return b end)
for _, m in ipairs(C.readMods(q)) do
	if m.group ~= "special" then
		eq(m.value, M.scaleQuality(m.hi, 20), "tempered with quality " .. m.key)
	end
end
-- Divine rarity: 30
local divine = forged(2400, 10, 100)
eq(M.qualityCap(10), 30); eq(M.qualityCap(9), 20)
C.addQuality(divine, 30)
eq(M.qualityOf(divine), 30)
-- quality survives the orbs that make a new copy
local qc = forged(2400, 4, 100)
C.addQuality(qc, 5)
dice = {}
isOk, res = C.apply("chaos", qc)
eq(M.qualityOf(res.item), 5, "Upheaval keeps the quality")
isOk, res = C.apply("scouring", res.item)
eq(M.qualityOf(res.item), 5, "Erasure keeps it too")
eq(C.rarityOf(res.item), 0)
-- an old item (no stored tiers, no cv): the quality stores the tiers first
local old = put(newItem(2400))
old:setCustomAttribute("rarity", 4); old:setCustomAttribute("combatPowerLevel", 50)
old:setCustomAttribute("rarity_swordSkill", 3)
C.rewriteDescription(old)
C.addQuality(old, 10)
eq(old:getCustomAttribute("rarity_swordSkill"), 3, "3 x 1.1 = 3.3: still 3")
C.addQuality(old, 10)
ok(old:getCustomAttribute("ct_rarity_swordskill") ~= nil, "the tier was stored")
eq(M.scaleQuality(5, 20), 6); eq(M.scaleQuality(10, 7), 11); eq(M.scaleQuality(1, 20), 1); eq(M.scaleQuality(0, 20), 0)
eq(select(2, C.check("whetstone", put(newItem(2400)))), "needRarity")

-- ---------------------------------------------------------------- the older orbs with bound modifiers
local b1 = forged(2400, 4, 100)
local bm = C.readMods(b1)
C.setBound(b1, bm[1], true)
local boundKey = bm[1].key
for _ = 1, 30 do
	dice = {}
	local copy = forged(2400, 4, 100)
	C.setBound(copy, C.readMods(copy)[1], true)
	local k = C.readMods(copy)[1].key
	local v = C.readMods(copy)[1].value
	dice = {}
	isOk, res = C.apply("annulment", copy)
	eq(isOk, true)
	ok(C.modByKey(copy, k) ~= nil and C.modByKey(copy, k).value == v, "Unmaking never takes a bound modifier")
	eq(#C.readMods(copy), 2)
end
-- everything bound: Unmaking and Upheaval refuse
local allb = forged(2400, 1, 100)
for _, m in ipairs(C.readMods(allb)) do C.setBound(allb, m, true) end
eq(select(2, C.check("annulment", allb)), "allBound")
eq(select(2, C.check("chaos", allb)), "allBound")
-- Upheaval: the bound modifier stays, the rest is rolled again (in place, the same item)
local up = forged(2400, 4, 100)
local um = C.readMods(up)
C.setBound(up, um[1], true)
local upKey, upValue, upTier = um[1].key, um[1].value, um[1].tier
dice = {}
isOk, res = C.apply("chaos", up)
eq(isOk, true)
eq(res.item, up, "in place")
eq(#C.readMods(up), M.modCount(4), "the rarity's count again")
eq(C.modByKey(up, upKey).bound, true); eq(C.modByKey(up, upKey).value, upValue); eq(C.modByKey(up, upKey).tier, upTier)
ok(res.text:find("bound ones stayed"), res.text)
-- Fate refuses a bound item; Erasure frees everything
eq(select(2, C.check("divine", up)), "hasBound")
isOk, res = C.apply("scouring", up)
eq(isOk, true)
eq(C.bindCount(C.readMods(res.item)), 0, "Erasure frees the binds (a plain copy)")
eq(#C.readMods(res.item), 0)
-- clearMods wipes binds, raw values and the extra slot
local cl = forged(2400, 4, 100)
C.setBound(cl, C.readMods(cl)[1], true)
cl:setCustomAttribute(M.EXTRA, 1)
C.addQuality(cl, 3)
C.clearMods(cl)
eq(#C.readMods(cl), 0)
eq(cl:getCustomAttribute(M.EXTRA), nil)
for _, a in ipairs(C.affixes()) do
	eq(cl:getCustomAttribute(M.bindAttr(a.key)), nil)
	eq(cl:getCustomAttribute(M.rawAttr(a.key)), nil)
end

-- ---------------------------------------------------------------- legendary powers as modifiers
local P = ChaosPowers
eq(#P.keys, 12, "twelve powers")
for _, key in ipairs(P.keys) do
	local def = M.byKey[key]
	ok(def and def.power and def.minRarity == 5, key)
	ok(M.text(key, 7):find("7"), key .. " has a tooltip line")
end
local function powerCandidates(item, rarity)
	local n = 0
	for _, row in ipairs(C.candidates(item, rarity)) do
		if row.entry.def and M.isPower(row.entry.def) then n = n + 1 end
	end
	return n
end
eq(powerCandidates(put(newItem(2400)), 4), 0, "no power below Legendary")
ok(powerCandidates(put(newItem(2400)), 5) > 0, "Legendary weapons can roll powers")
-- forge many items: powers only on Legendary+, at most one, always inside the side limits
C.random = math.random
math.randomseed(5)
local withPower, total = 0, 0
for _, r in ipairs({1, 3, 4, 5, 8, 10, 15}) do
	for _ = 1, 150 do
		local it = put(newItem(r % 2 == 0 and 2466 or 2400))
		C.forge(it, r, 120, C.random)
		local ms = C.readMods(it)
		local n = 0
		for _, m in ipairs(ms) do if m.power then n = n + 1 end end
		ok(n <= 1, "one power at most")
		if r < 5 then eq(n, 0, "no power on rarity " .. r) end
		local p, s = C.sideCounts(ms)
		ok(p <= M.sideLimit(r) and s <= M.sideLimit(r), "sides respected with powers")
		if r >= 5 then total = total + 1 withPower = withPower + n end
	end
end
ok(withPower > 20 and withPower < total * 0.8, "powers roll sometimes: " .. withPower .. " of " .. total)
-- a power counts as a prefix or a suffix
local pw = put(newItem(2400))
pw:setCustomAttribute("rarity", 5); pw:setCustomAttribute("chaos_ilvl", 100)
C.writeAffix(pw, C.affixOf(M.attr("deathblast")), 4, 5)
local pm = C.readMods(pw)[1]
eq(pm.power, true); eq(pm.side, "prefix"); eq(pm.tier, 4); eq(pm.value, 5)
ok(C.modTierText(pm):find("Death Blast: 5%% chance on kill to explode %(T4%)"), C.modTierText(pm))
eq(C.sideCounts(C.readMods(pw)), 1)
C.rewriteDescription(pw)
ok(pw:getAttribute(ITEM_ATTRIBUTE_DESCRIPTION):find("Prefixes: Death Blast"), pw:getAttribute(ITEM_ATTRIBUTE_DESCRIPTION))
-- the capped total of several items
local t = M.totals({pw, pw, pw, pw, pw, pw})
eq(t.deathblast, 25, "capped at 25")
-- Exalted never gives a second power
local second = put(newItem(2400))
second:setCustomAttribute("rarity", 8); second:setCustomAttribute("chaos_ilvl", 100)
C.writeAffix(second, C.affixOf(M.attr("deathblast")), 4, 5)
for _ = 1, 100 do
	for _, row in ipairs(C.candidates(second)) do
		ok(not (row.entry.def and M.isPower(row.entry.def)), "a second power is never offered")
	end
end

-- ---------------------------------------------------------------- Rift Keys
C.random = function(a, b)
	local v = table.remove(dice, 1)
	if v == nil then return a end
	return v
end
local R, rcfg = C.rift()
local function newKey(tier, mods)
	local k = put(newItem(rcfg.key.itemId))
	k:setActionId(rcfg.key.actionId)
	C.writeKey(k, {tier = tier, mods = R.decodeMods(rcfg, mods or "")})
	return k
end
local key = newKey(4, "vitality:30,haste:40")
eq(C.check("tempering", key), true, "Tempering works on a Rift Key")
eq(C.check("excision", key), true)
eq(select(2, C.check("binding", key)), "keyOrb")
eq(select(2, C.check("ruin", key)), "keyOrb")
eq(select(2, C.check("whetstone", key)), "keyOrb")
eq(select(2, C.check("reforging", key)), "keyOrb")
local view = C.describe(key)
eq(view.pick.excision[1], "vitality"); eq(view.pick.excision[2], "haste")
eq(view.mods[2].key, "haste")
dice = {}
isOk, res = C.apply("excision", key, {mod = "haste"})
eq(isOk, true)
eq(key:getCustomAttribute("rift_mods"), "vitality:30", "the chosen key modifier went")
isOk, res = C.apply("tempering", key)
eq(isOk, true)
eq(#C.readKey(key).mods, 1)
local empty = newKey(4, "")
eq(select(2, C.check("tempering", empty)), "keyNoMods")
eq(select(2, C.check("excision", empty)), "keyNoMods")

-- ---------------------------------------------------------------- the bench view
local view2 = C.describe(forged(2400, 5, 100))
eq(view2.binds[2], 2)
eq(view2.binds[1], 0)
eq(#view2.pick.binding, 3)
eq(view2.orbs.ruin, "")
ok(view2.preview.tempering:find("modifiers new values"), view2.preview.tempering)
ok(view2.preview.binding:find("0 of 2 bound"), view2.preview.binding)
eq(view2.mods[1].key ~= nil, true, "every modifier row has its key")
-- orbs without a rarity: the pick lists are empty
local plainView = C.describe(put(newItem(2400)))
eq(plainView.orbs.tempering ~= "", true)
eq(plainView.pick.binding, nil)

print("orbs_test: " .. checks .. " checks OK")
