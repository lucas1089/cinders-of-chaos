-- Run from the server/ folder: luajit tests/veiled_test.lua (and lua5.3; CI runs both)
-- Veiled modifiers (data/lib/chaos_veiled.lua, chaos_veiled_config.lua; data/scripts/chaos/veiled.lua) against a mocked
-- item: the pool and its caps, roll chances by source and rarity, uniques and set pieces excluded, the item level gates,
-- the offered choices fixed per item, the unveiling through the Orb of Unveiling (ChaosCrafting), the slot surviving the
-- other orbs, the totals under the caps, the hook maths, the tooltip and look text, and the engine side (corpse drops,
-- the window, a choice) against a mocked engine.

local checks = 0
local function eq(a, b, m)
	checks = checks + 1
	if a ~= b then
		error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2)
	end
end
local function ok(v, m)
	eq(not not v, true, m)
end

-- ---------------------------------------------------------------- engine mock
ITEM_ATTRIBUTE_DESCRIPTION, ITEM_ATTRIBUTE_NAME = 1, 2
ITEM_ATTRIBUTE_ATTACK, ITEM_ATTRIBUTE_ARMOR = 11, 12
INDEX_WHEREEVER, FLAG_NOLIMIT, RETURNVALUE_NOERROR = -1, 1, 0

local TYPES = {
	[2400] = {name = "magic sword", weaponType = 1, attack = 48, slot = 48, cid = 3288},
	[2466] = {name = "golden armor", armor = 14, slot = 8, cid = 3360},
	[2195] = {name = "boots of haste", armor = 1, slot = 128, cid = 3079},
	[2173] = {name = "amulet of loss", armor = 1, slot = 2, cid = 3057},
	[2160] = {name = "crystal coin", stackable = true},
	[32257] = {name = "Orb of Unveiling", stackable = true, cid = 25046}
}

function ItemType(id)
	local t = TYPES[id] or {}
	return {
		getId = function() return TYPES[id] and id or 0 end,
		getName = function() return t.name or "" end,
		getClientId = function() return t.cid or 0 end,
		isContainer = function() return false end,
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
function Item:isItem() return true end
function Item:getName() return self.attrs[ITEM_ATTRIBUTE_NAME] or ItemType(self.id):getName() end
function Item:getCustomAttribute(k) return self.custom[k:lower()] end
function Item:setCustomAttribute(k, v) self.custom[k:lower()] = v end
function Item:removeCustomAttribute(k) self.custom[k:lower()] = nil return true end
function Item:getAttribute(k) return self.attrs[k] or (k == ITEM_ATTRIBUTE_DESCRIPTION and "" or nil) end
function Item:setAttribute(k, v) self.attrs[k] = v end
function Item:hasAttribute(k) return self.attrs[k] ~= nil end
function Item:getParent() return self.parent end
function Item:getActionId() return 0 end
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
local C, M, V = ChaosCrafting, ChaosItemMods, ChaosVeiled
local CFG = V.config
M.random = function(a, b) return a end
C.random = function(a, b) return a end

-- dice: queued values, else the lowest
local dice = {}
local function rand(a, b)
	local v = table.remove(dice, 1)
	if v == nil then
		return a
	end
	assert(v >= a and v <= b, "dice value " .. v .. " outside " .. a .. ".." .. b)
	return v
end
V.random = rand

local function gear(id, rarity, level)
	local it = put(newItem(id))
	C.forge(it, rarity, level or 150, function(a) return a end)
	return it
end

-- ---------------------------------------------------------------- the pool and its caps
ok(#CFG.pool >= 15 and #CFG.pool <= 25, "15-25 veiled modifiers")
local hooks, kindsSeen = 0, {}
for _, def in ipairs(CFG.pool) do
	eq(V.byKey[def.key], def, "indexed " .. def.key)
	eq(#def.tiers, #CFG.tiers.levels, def.key .. " has a range per veiled tier")
	ok(type(def.name) == "string" and def.name ~= "" and def.text:find("%d", 1, true), def.key .. " name and text")
	for t = 1, #def.tiers do
		ok(def.tiers[t][1] <= def.tiers[t][2], def.key .. " range " .. t)
		if t > 1 then
			ok(def.tiers[t][1] >= def.tiers[t - 1][1] and def.tiers[t][2] >= def.tiers[t - 1][2], def.key .. " tiers rise")
		end
	end
	for _, e in ipairs(def.effects) do
		local cat, hook = M.byKey[e.k], CFG.hookCaps[e.k]
		ok(cat or hook, def.key .. ": effect " .. e.k .. " is a catalogue modifier or a hook key")
		ok(not (cat and M.isPower(cat)), def.key .. " never adds to a legendary power")
	end
	-- caps: the best roll of every effect fits under its cap
	for _, e in ipairs(V.effectValues(def, def.tiers[#def.tiers][2])) do
		local cap = CFG.hookCaps[e.k] or M.byKey[e.k].cap
		ok(e.v <= cap, def.key .. ": " .. e.k .. " " .. e.v .. " under its cap " .. cap)
	end
	if V.isHook(def) then
		hooks = hooks + 1
	end
	for k in pairs(def.kinds) do
		kindsSeen[k] = true
	end
end
ok(hooks >= 3, "a few modifiers with hook effects")
for _, k in ipairs({"weapon", "shield", "helmet", "armor", "legs", "boots", "jewel", "other"}) do
	ok(kindsSeen[k], "the pool covers " .. k)
	ok(#V.pool(k, 150) >= CFG.offers, k .. " has three choices at item level 150")
end
eq(V.text(V.byKey.wraithstride, 9), "Movement Speed +9%, Dodge +4%", "paired text, second effect at half")
eq(V.text(V.byKey.briarshroud, 150), "Thorns +150, Reflect Damage +6%", "thorns with a share as reflect")
eq(V.rangeText(V.byKey.wraithstride, 5, 10), "Movement Speed +5-10%, Dodge +2-5%", "range text")
eq(V.effectValues(V.byKey.undyingroot, 18)[2].v, 1, "a share is at least 1 point")

-- ---------------------------------------------------------------- the orb
local orb = C.orbByKey.unveiling
ok(orb, "the Orb of Unveiling is a crafting orb")
eq(orb.id, 32257, "its item id")
eq(V.orbId, 32257)
eq(C.orbById[32257], orb, "use-with registration by id")
local inCfg = false
for _, row in ipairs(ChaosOrbsConfig.items) do
	if row.key == "unveiling" then
		inCfg = row.id == 32257 and row.name == "Orb of Unveiling"
	end
end
ok(inCfg, "installed through chaos_orbs_config.lua (install_orbs.py)")
local keys = {}
for _, k in ipairs(C.attributeKeys()) do
	keys[k] = true
end
for _, k in ipairs(V.ATTRS) do
	ok(keys[k], "copied by hand-copy paths: " .. k)
end

-- ---------------------------------------------------------------- sources and chances
eq(V.sourceOf(nil), nil, "no context")
eq(V.sourceOf({}), nil, "open world")
eq(V.sourceOf({riftTier = 9}), nil, "rift tier 9 is not high content")
eq(V.sourceOf({riftTier = 10}), "rift", "rift tier 10")
eq(V.sourceOf({riftTier = 12, omen = true}), "omen", "an Omen arena beats the rift")
eq(V.sourceOf({descentDepth = 7}), nil, "Descent depth 7")
eq(V.sourceOf({descentDepth = 8}), "descent", "Descent depth 8")
eq(V.sourceOf({raid = true, riftTier = 15}), "raid", "raid first")
eq(V.sourceOf({ascended = true}), "ascended", "Ascended")
eq(V.chance("rift", 2), 0, "Uncommon never")
eq(V.chance("rift", 3), 500, "Rare: the base chance")
eq(V.chance("rift", 4), 500, "Epic: the base chance")
eq(V.chance("rift", 5), 1000, "Legendary: the high chance")
eq(V.chance("raid", 9), 2500, "raid, Eternal")
eq(V.chance(nil, 9), 0, "no source")
eq(V.orbChance("rift", "normal"), 5, "orb from a rift kill")
eq(V.orbChance("raid", "boss"), 1000, "orb from a raid boss")
eq(V.orbChance(nil, "boss"), 0, "no orb outside high content")
dice = {5}
ok(V.rollOrb({riftTier = 10}, "normal"), "roll 5 of 5")
dice = {6}
ok(not V.rollOrb({riftTier = 10}, "normal"), "roll 6 of 5")

-- rolls on items
local rift = {riftTier = 11}
local sword = gear(2400, 3)
dice = {500}
ok(V.rollItem(sword, rift), "a Rare sword, roll 500 of 500")
eq(V.stateOf(sword), 1, "veiled")
dice = {1}
ok(not V.rollItem(sword, rift), "never a second slot")
local sword2 = gear(2400, 3)
dice = {501}
ok(not V.rollItem(sword2, rift), "roll 501 of 500")
eq(V.stateOf(sword2), 0)
local leg = gear(2400, 5)
dice = {1000}
ok(V.rollItem(leg, rift), "Legendary, roll 1000 of 1000")
local unc = gear(2400, 2)
dice = {1}
ok(not V.rollItem(unc, {raid = true}), "Uncommon gear never")
local plain = gear(2400, 4)
dice = {1}
ok(not V.rollItem(plain, {riftTier = 3}), "low rifts never")
local uniq = gear(2400, 5)
uniq:setCustomAttribute("chaos_unique", 1)
dice = {1}
ok(not V.rollItem(uniq, {raid = true}), "uniques never")
local setPiece = gear(2466, 5)
setPiece:setCustomAttribute("chaos_set", "ashen")
dice = {1}
ok(not V.rollItem(setPiece, {raid = true}), "set pieces never")
local coin = put(newItem(2160, 1))
coin:setCustomAttribute("rarity", 5)
ok(not V.rollItem(coin, {raid = true}), "not gear")
-- a shielded drop (the rarity as text while the engine's pass runs) still counts
local shielded = gear(2400, 4)
C.shield(shielded)
dice = {1}
ok(V.rollItem(shielded, {ascended = true}), "a shielded drop")

-- ---------------------------------------------------------------- tiers and pool gates
eq(V.maxTier(1), 1); eq(V.maxTier(89), 1); eq(V.maxTier(90), 2); eq(V.maxTier(134), 3); eq(V.maxTier(150), 4)
local rows = V.tierRows(150)
eq(#rows, 3, "the best three tiers"); eq(rows[1][1], 4); eq(rows[3][1], 2)
eq(#V.tierRows(50), 1, "only V1 below item level 90")
dice = {CFG.tiers.weights[2] + CFG.tiers.weights[3] + CFG.tiers.weights[4]}
eq(V.rollTier(150, rand), 2, "the last of the window")
local function has(list, key)
	for _, d in ipairs(list) do
		if d.key == key then
			return true
		end
	end
	return false
end
ok(not has(V.pool("boots", 99), "bloodharvest"), "Blood Harvest needs item level 100")
ok(has(V.pool("boots", 100), "bloodharvest"), "Blood Harvest at item level 100")
ok(not has(V.pool("weapon", 109), "headsman"), "Headsman needs item level 110")
ok(has(V.pool("weapon", 110), "headsman"), "Headsman at 110")
ok(not has(V.pool("weapon", 89), "doombringer"), "Doombringer needs 90")
ok(not has(V.pool("boots", 150), "sundering"), "kind gate: no weapon modifier on boots")
eq(#V.pool(nil, 150), 0, "no kind, no pool")

-- ---------------------------------------------------------------- offered choices
local offers1 = V.offers(sword)
eq(#offers1, 3, "three choices")
local stored = sword:getCustomAttribute(CFG.attrs.offer)
ok(type(stored) == "string" and stored ~= "", "stored on the item")
local seen = {}
for _, o in ipairs(offers1) do
	ok(not seen[o.key], "distinct " .. o.key); seen[o.key] = true
	ok(o.def.kinds.weapon, o.key .. " fits a weapon")
	ok(o.tier >= 2 and o.tier <= 4, "tier in the window of item level 150")
	ok(o.value >= o.def.tiers[o.tier][1] and o.value <= o.def.tiers[o.tier][2], "value inside its tier")
end
-- the same three every time, whatever the dice
V.random = function(a, b) return b end
local offers2 = V.offers(sword)
eq(V.encodeOffer(offers2), stored, "opening again shows the same three (no reroll)")
eq(sword:getCustomAttribute(CFG.attrs.offer), stored, "unchanged")
V.random = rand
-- a broken stored text is rolled again (never a choice outside the pool or the gates)
local swordX = gear(2400, 4)
swordX:setCustomAttribute(CFG.attrs.state, 1)
swordX:setCustomAttribute(CFG.attrs.offer, "wraithstride:4:10;firststrike:4:22")
eq(V.decodeOffer(swordX:getCustomAttribute(CFG.attrs.offer), "weapon", 150), nil, "boots modifier on a weapon refused")
eq(V.decodeOffer("firststrike:4:99", "weapon", 150), nil, "value outside the tier refused")
eq(V.decodeOffer("firststrike:4:20", "weapon", 120), nil, "tier above the item level refused")
eq(V.decodeOffer("firststrike:2:12;firststrike:2:12", "weapon", 150), nil, "a key twice refused")
eq(#V.decodeOffer("firststrike:2:12", "weapon", 150), 1, "a valid one")
local fixed = V.offers(swordX)
eq(#fixed, 3, "rolled again"); ok(V.decodeOffer(swordX:getCustomAttribute(CFG.attrs.offer), "weapon", 150), "valid now")
-- low item level: only V1, only modifiers without a level gate
local low = gear(2400, 4, 60)
low:setCustomAttribute(CFG.attrs.state, 1)
for _, o in ipairs(V.offers(low)) do
	eq(o.tier, 1, "V1 at item level 60")
	eq(o.def.minLevel or 1, 1, "no gated modifier at item level 60: " .. o.key)
end
eq(V.offers(sword2), nil, "no offers without a veil")
local view = V.offerView(offers1)
eq(#view, 3); eq(view[1].i, 1); ok(view[1].text ~= "" and view[1].tn:match("^V%d$"), "window card text and tier name")

-- ---------------------------------------------------------------- the Orb of Unveiling
local okC, why = C.check("unveiling", sword2)
eq(okC, false); eq(why, "notVeiled", "a plain Rare item")
eq(C.check("unveiling", sword), true, "a veiled item")
local okB, whyB = C.check("unveiling", sword, {choice = 4})
eq(okB, false); eq(whyB, "badChoice", "choice 4 of 3")
local fresh = gear(2400, 4)
fresh:setCustomAttribute(CFG.attrs.state, 1)
local okN, whyN = C.check("unveiling", fresh, {choice = 1})
eq(whyN, "noOffer", "choose before the three were shown")
eq(V.unveil(fresh, 1), false, "unveil needs the offer")
uniq:setCustomAttribute(CFG.attrs.state, 1)
eq(select(2, C.check("unveiling", uniq)), "unique", "uniques refused")
eq(V.read(uniq), nil, "a unique never shows a veiled slot")
local ruined = gear(2400, 4)
ruined:setCustomAttribute(CFG.attrs.state, 1)
ruined:setCustomAttribute(M.RUINED, 1)
eq(select(2, C.check("unveiling", ruined)), "ruined", "ruined items refused like every orb")
ok(C.preview("unveiling", sword):find("V2%-V4"), "bench preview names the tiers")

local pick = offers1[2]
local okA, res = C.apply("unveiling", sword, {choice = 2})
ok(okA, "unveiled: " .. tostring(res and res.text or res))
eq(V.stateOf(sword), 2, "state 2")
eq(sword:getCustomAttribute(CFG.attrs.key), pick.key, "the chosen key")
eq(sword:getCustomAttribute(CFG.attrs.tier), pick.tier)
eq(sword:getCustomAttribute(CFG.attrs.value), pick.value)
eq(sword:getCustomAttribute(CFG.attrs.offer), nil, "the offer is gone")
local r = V.read(sword)
eq(r.state, "open"); eq(r.key, pick.key); eq(r.text, V.text(pick.def, pick.value))
ok(sword:getAttribute(ITEM_ATTRIBUTE_DESCRIPTION):find("Veiled: " .. pick.def.name, 1, true), "look text")
local okAgain, msg = C.apply("unveiling", sword, {choice = 1})
eq(okAgain, false); eq(msg, C.reasons.alreadyUnveiled, "final: no second choice")
eq(select(2, V.unveil(sword, 1)), "alreadyUnveiled")
-- the slot is outside the prefixes and suffixes: the item's modifier count is unchanged
local p, s = C.sideCounts(C.readMods(sword))
eq(p + s, M.modCount(3), "readMods does not see the veiled slot")
-- look text of a veiled item
C.rewriteDescription(fresh)
ok(fresh:getAttribute(ITEM_ATTRIBUTE_DESCRIPTION):find("Veiled modifier: not revealed", 1, true), "veiled look text")

-- ---------------------------------------------------------------- the other orbs keep the slot
local chaosOk, chaosRes = C.apply("chaos", sword)
ok(chaosOk, "Upheaval on an unveiled item")
local newSword = chaosRes.item
ok(newSword ~= sword and sword.removed, "a new copy")
eq(V.read(newSword).key, pick.key, "Upheaval keeps the unveiled modifier")
local scOk, scRes = C.apply("scouring", fresh)
ok(scOk, "Erasure")
eq(V.stateOf(scRes.item), 1, "Erasure keeps the veil")
local exOk = C.apply("exalted", gear(2400, 5))
ok(exOk ~= nil, "Grafting still works on other items")
-- Tempering in place leaves it
local tmp = gear(2400, 4)
tmp:setCustomAttribute(CFG.attrs.state, 1)
V.offers(tmp)
C.apply("tempering", tmp)
eq(V.stateOf(tmp), 1, "Tempering leaves the veil")
-- V.copy itself
local cp = newItem(2400)
V.copy(newSword, cp)
eq(V.read(cp).value, V.read(newSword).value, "copy")

-- ---------------------------------------------------------------- totals and caps
local function unveiled(id, key, tier, value, mods)
	local it = gear(id, 4)
	C.clearMods(it)
	for k, v in pairs(mods or {}) do
		M.set(it, k, v, 4)
	end
	it:setCustomAttribute(CFG.attrs.state, 2)
	it:setCustomAttribute(CFG.attrs.key, key)
	it:setCustomAttribute(CFG.attrs.tier, tier)
	it:setCustomAttribute(CFG.attrs.value, value)
	return it
end
local boots = unveiled(2195, "wraithstride", 4, 10, {movespeed = 9})
local amulet = unveiled(2173, "firststrike", 4, 22)
local amulet2 = unveiled(2173, "firststrike", 4, 22)
local armor = unveiled(2466, "gravebound", 4, 16)
local cat, own = V.totals({boots, amulet, amulet2, armor, sword2})
eq(cat.movespeed, 10); eq(cat.dodge, 5, "paired effect")
eq(own.veil_firststrike, 40, "two Veilpiercers (44) capped at 40")
eq(own.veil_gravebound, 16)
eq(own.veil_hexbreaker, 0, "every hook key present")
local totals = M.totals({boots, amulet, armor}, V.merge(nil, cat))
eq(totals.movespeed, 12, "item 9 + veiled 10 under the catalogue cap 12")
eq(totals.dodge, 5)
eq(V.merge({a = 1}, {a = 2, b = 3}).a, 3); eq(V.merge(nil, nil), nil)
-- an excluded item never counts
local u2 = unveiled(2173, "firststrike", 4, 22)
u2:setCustomAttribute("chaos_unique", 1)
eq(select(2, V.totals({u2})).veil_firststrike, 0, "a unique's veil attributes are ignored")
-- a still veiled item gives nothing
eq(select(2, V.totals({fresh})).veil_firststrike, 0)

-- ---------------------------------------------------------------- hook maths
local t = {veil_firststrike = 20, veil_desperation = 15, veil_gravebound = 20, veil_hexbreaker = 12, veil_ashenward = 10,
	veil_bloodharvest = 3, veil_soulharvest = 2}
ok(V.offensive(t), "the damage hooks need the hit event")
ok(not V.offensive({veil_gravebound = 5}), "defensive only")
eq(V.dealtPct(t, {targetHp = 81, targetMax = 100, ownHp = 100, ownMax = 100}), 20, "Veilpiercer above 80%")
eq(V.dealtPct(t, {targetHp = 80, targetMax = 100, ownHp = 100, ownMax = 100}), 0, "not at 80%")
eq(V.dealtPct(t, {targetHp = 10, targetMax = 100, ownHp = 49, ownMax = 100}), 15, "Last Ember below 50%")
eq(V.dealtPct(t, {targetHp = 100, targetMax = 100, ownHp = 10, ownMax = 100}), 35, "both")
eq(V.dealtPct(nil, {}), 0)
-- both hooks at their caps (40 + 40): together at most hook.maxDealt
eq(V.dealtPct({veil_firststrike = 40, veil_desperation = 40}, {targetHp = 100, targetMax = 100, ownHp = 10, ownMax = 100}), 40,
	"Veilpiercer + Last Ember capped at 40 together")
eq(V.dealtPct({veil_firststrike = 40, veil_desperation = 40}, {targetHp = 100, targetMax = 100, ownHp = 100, ownMax = 100}), 40,
	"one hook alone: its own 40")
eq(V.takenPct(t, {hp = 34, maxHp = 100, monster = true}), 20, "Gravebound below 35%")
eq(V.takenPct(t, {hp = 35, maxHp = 100, monster = true}), 0, "not at 35%")
eq(V.takenPct(t, {hp = 90, maxHp = 100, monster = true, boss = true}), 12, "Hexbreaker")
eq(V.takenPct(t, {hp = 90, maxHp = 100, monster = true, elemental = true}), 10, "Ashen Ward")
eq(V.takenPct(t, {hp = 90, maxHp = 100, monster = false, elemental = true}), 0, "players' hits do not count")
eq(V.takenPct(t, {hp = 10, maxHp = 100, monster = true, boss = true, elemental = true}), CFG.hook.maxReduction,
	"42 capped by the combined maximum")
local h, mp = V.killRestore(t, 2000, 1500)
eq(h, 60, "3% of 2000 health"); eq(mp, 30, "2% of 1500 mana")
eq(select(1, V.killRestore(nil, 1, 1)), 0)

-- ---------------------------------------------------------------- tooltip
eq(V.tooltip(sword2), nil, "no veil, no block")
eq(V.tooltip(swordX).s, "veiled", "veiled block")
local tipB = V.tooltip(boots)
eq(tipB.s, "open"); eq(tipB.n, "Wraithstride"); eq(tipB.tr, 4); eq(tipB.tn, "V4"); eq(tipB.lo, 8); eq(tipB.hi, 10)
eq(tipB.t, "Movement Speed +10%, Dodge +5%")
eq(tipB.st[1].k, M.attr("movespeed"), "compare number on the catalogue modifier's key")
eq(tipB.h, nil, "not a hook")
eq(V.tooltip(amulet).h, true, "a hook")
eq(V.descText(sword2), nil)

-- the tooltip builder carries it (item_tooltip_core.lua)
dofile("data/scripts/chaos/item_tooltip_core.lua")
local tip = ChaosItemTooltip.build(boots, {})
eq(tip.veil.s, "open", "tooltip carries the veil")
eq(tip.veil.st, nil, "compare numbers are not sent twice")
local found = false
for _, st in ipairs(tip.stats) do
	if st.k == M.attr("movespeed") then
		found = st.v == 19
	end
end
ok(found, "compare stats add the item's 9 and the veil's 10 movement speed")
eq(ChaosItemTooltip.build(swordX, {}).veil.s, "veiled")
eq(ChaosItemTooltip.build(u2, {}).veil, nil, "never on a unique")

-- ---------------------------------------------------------------- the engine side (veiled.lua)
local sent, events = {}, {}
ChaosOpcodes = nil
Chaos = nil
local wire = {} -- messages from the client: a string key -> the decoded table
json = {encode = function(v) return v end, decode = function(v) return wire[v] end}
local function msgOf(t)
	wire[#wire + 1] = t
	return "msg" .. #wire
end
setmetatable(wire, {__index = function(_, k) return rawget(wire, tonumber(tostring(k):match("%d+$"))) end})
dofile("data/scripts/chaos/chaos_constants.lua")
eq(ChaosOpcodes.veiled, 196, "opcode")
local used = {}
for k, v in pairs(ChaosOpcodes) do
	ok(not used[v] or used[v] == k, "opcode " .. v .. " used once (" .. k .. ", " .. tostring(used[v]) .. ")")
	used[v] = k
end
Chaos.send = function(player, opcode, action, data)
	sent[#sent + 1] = {opcode = opcode, action = action, data = data}
	return true
end
function CreatureEvent(name)
	local e = {name = name}
	function e:type() end
	function e:register() events[name] = self end
	return e
end
local orbCount = 1
local player = {id = 77}
function player:getId() return self.id end
function player:getItemCount(id) return id == 32257 and orbCount or 0 end
function player:registerEvent() end
function player:sendTextMessage() end
function player:getPosition() return {sendMagicEffect = function() end} end
local paths = {}
ChaosCraftingBench = {
	pathOf = function(_, item) return paths[item] end,
	itemAt = function(_, path)
		for it, p2 in pairs(paths) do
			if p2 == path then return it end
		end
	end,
	sendState = function() end,
	craft = function(pl, orbKey, item, orbItem, opts)
		local o = C.orbByKey[orbKey]
		if o.dialog and not (opts and opts.choice) then
			return o.dialog(pl, item)
		end
		local okX, resX = C.apply(orbKey, item, opts)
		if not okX then
			return false, resX
		end
		orbCount = orbCount - 1
		return true, resX.text, resX.item
	end
}
dofile("data/scripts/chaos/veiled.lua")
ok(orb.dialog, "the orb opens the window")
ok(events.ChaosVeiledExtended and events.ChaosVeiledLogin, "events registered")

-- contexts from the runs
ChaosRift = {runOf = {[77] = {key = {tier = 12}, omen = {}}}}
local ctx = V.contextOf(player)
eq(ctx.riftTier, 12); eq(ctx.omen, true); eq(V.sourceOf(ctx), "omen")
ChaosRift = nil
ChaosDescent = {runOf = {[77] = {depth = 9}}}
eq(V.sourceOf(V.contextOf(player)), "descent")
ChaosDescent = nil
ChaosRaid = {runOf = {[77] = {}}}
eq(V.sourceOf(V.contextOf(player)), "raid")

-- a corpse in the raid: the Rare+ gear rolls, the rest not; a boss may drop the orb
local corpse = {items = {}}
function corpse:getSize() return #self.items end
function corpse:getItem(i) return self.items[i + 1] end
function corpse:addItem(id, n)
	local it = newItem(id, n)
	self.items[#self.items + 1] = it
	return it
end
local c1, c2 = gear(2400, 5), gear(2400, 2)
corpse.items = {c1, c2}
local monster = {getType = function() return {isBoss = function() return true end} end}
dice = {1, 1000}
local texts = V.onCorpse(corpse, monster, player, "normal")
eq(V.stateOf(c1), 1, "Legendary gear in the raid veiled")
eq(V.stateOf(c2), 0, "Uncommon not")
eq(#texts, 2, "bonus loot names the veiled item and the orb")
eq(texts[2], "Orb of Unveiling")
eq(corpse.items[3].id, 32257, "the orb in the corpse")
ok(c1:getAttribute(ITEM_ATTRIBUTE_DESCRIPTION):find("Veiled modifier", 1, true), "look text written")
ChaosRaid = nil
eq(#V.onCorpse(corpse, monster, player, "normal"), 0, "nothing outside high content")
local reward = gear(2466, 5)
dice = {1}
ok(V.rollReward(reward, {ascended = true}), "Ascended spoils")

-- the window
paths[c1] = "3"
sent = {}
local okD, textD = ChaosCraftingBench.craft(player, "unveiling", c1, nil, nil)
ok(okD, "use-with opens the window: " .. tostring(textD))
eq(sent[1].action, "open"); eq(sent[1].opcode, 196)
local d = sent[1].data
eq(d.path, "3"); eq(d.id, 2400); eq(#d.offers, 3); eq(d.orbs, 1); eq(d.sig, V.signature(c1))
eq(orbCount, 1, "opening the window takes no orb")
-- open again: the same three
sent = {}
ChaosCraftingBench.craft(player, "unveiling", c1, nil, nil)
for i = 1, 3 do
	eq(sent[1].data.offers[i].key, d.offers[i].key, "the same choice " .. i)
	eq(sent[1].data.offers[i].value, d.offers[i].value)
end
-- a stale signature is refused
sent = {}
events.ChaosVeiledExtended.onExtendedOpcode(player, 196, msgOf({action = "choose", data = {path = "3", id = 2400, sig = "old", choice = 1}}))
eq(sent[1].action, "result"); eq(sent[1].data.ok, false, "changed item refused")
eq(V.stateOf(c1), 1)
-- a bad choice
sent = {}
ChaosRateLimit = nil
events.ChaosVeiledExtended.onExtendedOpcode(player, 196, msgOf({action = "choose", data = {path = "3", id = 2400, sig = d.sig, choice = 9}}))
eq(sent[1].data.ok, false, "choice 9 refused")
-- the choice
sent = {}
events.ChaosVeiledExtended.onExtendedOpcode(player, 196, msgOf({action = "choose", data = {path = "3", id = 2400, sig = d.sig, choice = 3}}))
eq(sent[1].data.ok, true, "choice 3: " .. tostring(sent[1].data.text))
eq(sent[1].data.veil.s, "open"); eq(sent[1].data.veil.n, V.byKey[d.offers[3].key].name, "the third card")
eq(sent[1].data.veil.st, nil)
eq(orbCount, 0, "one orb taken")
eq(V.read(c1).key, d.offers[3].key)
-- the engine's use-with on an item that is not veiled
local okP, textP = ChaosCraftingBench.craft(player, "unveiling", c2, nil, nil)
eq(okP, false); eq(textP, C.reasons.notVeiled)

print(string.format("veiled_test: %d checks OK", checks))
