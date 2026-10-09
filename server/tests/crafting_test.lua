-- Run from the server/ folder: luajit tests/crafting_test.lua (and lua5.3; CI runs both)
-- The crafting orbs (data/lib/chaos_crafting.lua) against a mocked item: eligibility, what every orb does, the
-- modifier slot limits, the description text, and that uniques are never touched. Also the Chaos item modifiers through
-- the orbs (Exalted adds, Annulment removes, Chaos / Scouring), the bench preview, and the orbs on Rift Keys.

local function eq(a, b, m)
	if a ~= b then
		error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2)
	end
end

-- ---------------------------------------------------------------- engine mock
ITEM_ATTRIBUTE_DESCRIPTION, ITEM_ATTRIBUTE_NAME = 1, 2
INDEX_WHEREEVER, FLAG_NOLIMIT, RETURNVALUE_NOERROR = -1, 1, 0

local TYPES = {
	[2400] = {name = "magic sword", weaponType = 1, attack = 48, slot = 48}, -- a weapon
	[2466] = {name = "golden armor", armor = 14, slot = 8},                -- body armor: no element modifiers
	[2160] = {name = "crystal coin", stackable = true},                   -- not gear
	[1988] = {name = "backpack", container = true, slot = 4},
	[8925] = {name = "solar axe", weaponType = 3, attack = 52, slot = 48, element = 12}, -- own element
	[27797] = {name = "boat", armor = 1, slot = 8}                         -- excluded id
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
		getElementDamage = function() return t.element or 0 end,
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
function Item:remove() self.removed = true
	if self.parent then
		for i, it in ipairs(self.parent.items) do
			if it == self then table.remove(self.parent.items, i) break end
		end
	end
	return true
end

local bag = {items = {}}
function bag:addItemEx(item, index, flags)
	self.items[#self.items + 1] = item
	item.parent = self
	return RETURNVALUE_NOERROR
end
local function put(item)
	bag:addItemEx(item)
	return item
end

-- the engine's rarity roll, simplified: an item level, the stat bonus and two modifiers
local engineRolls = 0
Game = {
	createItem = function(id, count) return newItem(id, count) end,
	createItemWithRarity = function(id, count, rarity)
		engineRolls = engineRolls + 1
		local it = newItem(id, count)
		if (TYPES[id] or {}).slot then
			it:setCustomAttribute("rarity", rarity)
			it:setCustomAttribute("combatPowerLevel", rarity * 10 - 3)
			it:setCustomAttribute("rarity_swordSkill", 1)
			it:setCustomAttribute("rarity_earthAbsorb", 1)
			it:setAttribute(ITEM_ATTRIBUTE_DESCRIPTION, "Level: " .. (rarity * 10 - 3) .. ", Earth +1%, Sword +1")
		end
		return it
	end
}

dofile("data/lib/chaos_crafting.lua")
local C = ChaosCrafting
local M = ChaosItemMods
-- drops and recreated items roll Chaos modifiers with M.random: by default never (the highest roll fails every chance)
M.random = function(a, b) return b end
-- deterministic dice: queue values, else the lowest
local dice = {}
C.random = function(a, b)
	local v = table.remove(dice, 1)
	if v == nil then
		return a
	end
	assert(v >= a and v <= b, "dice value " .. v .. " outside " .. a .. ".." .. b)
	return v
end

-- an item as the engine makes it with rarity r and the given modifiers
local function rareItem(id, r, mods)
	local it = put(newItem(id))
	it:setCustomAttribute("rarity", r)
	it:setCustomAttribute("combatPowerLevel", 42)
	for k, v in pairs(mods or {}) do
		it:setCustomAttribute(k, v)
	end
	C.rewriteDescription(it)
	return it
end

-- ---------------------------------------------------------------- reading
local sword = rareItem(2400, 4, {rarity_physicalAbsorb = 2, rarity_swordSkill = 1, rarity_criticalHitChance = 2,
	rarity_criticalHitAmount = 2, rarity_elementfire = 7})
local mods = C.readMods(sword)
eq(#mods, 4, "critical chance + amount is ONE modifier")
eq(mods[1].group, "absorb")
eq(mods[3].group, "special")
eq(sword:getAttribute(ITEM_ATTRIBUTE_DESCRIPTION),
	"Level: 42, Physical +2%, Sword +1, Critical Chance +2%, Critical Hit +2%, Element: Fire +7% dmg",
	"description in the engine's format")
eq(C.rarityOf(sword), 4)
eq(C.rarityName(4), "Epic")
-- keys are case-insensitive like the engine's (the stock equip script reads rarity_FireAbsorb)
local fireArmor = rareItem(2466, 2, {rarity_FireAbsorb = 1})
eq(C.readMods(fireArmor)[1].label, "Fire", "rarity_FireAbsorb is the fire absorb")

-- ---------------------------------------------------------------- eligibility
local coin = put(newItem(2160, 5))
eq(C.check("exalted", coin), false, "coins are not gear")
local bp = put(newItem(1988))
eq(select(2, C.check("transmutation", bp)), "notGear", "containers are not gear")
eq(select(2, C.check("transmutation", put(newItem(27797)))), "notGear", "boats are excluded")
eq(select(2, C.check("nothing", sword)), "unknownOrb")
local normal = put(newItem(2400))
eq(C.isNormal(normal), true)
eq(C.check("transmutation", normal), true, "transmutation on a normal item")
eq(C.check("alchemy", normal), true, "alchemy on a normal item")
eq(select(2, C.check("exalted", normal)), "needRarity", "exalted needs a rarity")
eq(select(2, C.check("annulment", normal)), "needRarity")
eq(select(2, C.check("scouring", normal)), "needRarity")
eq(select(2, C.check("chaos", normal)), "needRarity", "chaos keeps the rarity, so it needs one")
eq(C.check("divine", normal), true, "the stock divine roll works on any gear")
eq(select(2, C.check("transmutation", sword)), "needNormal", "transmutation refuses a rarity item")
-- an item level without a rarity (upgrade scripts) is not normal either
local upgraded = put(newItem(2466))
upgraded:setCustomAttribute("combatPowerLevel", 5)
eq(select(2, C.check("alchemy", upgraded)), "needNormal", "upgraded item is not normal")

-- ---------------------------------------------------------------- uniques
local unique = put(newItem(2400))
unique:setCustomAttribute("chaos_unique", 1)
unique:setCustomAttribute("rarity_swordSkill", 4)
for _, orb in ipairs(C.config.orbs) do
	eq(select(2, C.check(orb.key, unique)), "unique", "unique refused by " .. orb.key)
	local ok, msg = C.apply(orb.key, unique)
	eq(ok, false, "apply refused: " .. orb.key)
	eq(msg, C.reasons.unique)
end
eq(unique:getCustomAttribute("rarity_swordSkill"), 4, "unique untouched")
eq(unique.removed, false, "unique not replaced")
-- an old unique without the marker: recognised by its spec name
ChaosUniqueSpecs = {[2466] = {name = "Ironclad Bulwark"}}
local oldUnique = put(newItem(2466))
oldUnique:setAttribute(ITEM_ATTRIBUTE_NAME, "Ironclad Bulwark")
eq(C.isUnique(oldUnique), true, "unique by spec name")
eq(C.isUnique(put(newItem(2466))), false, "a plain copy of the base item is not unique")
ChaosUniqueSpecs = nil

-- ---------------------------------------------------------------- slot limits
eq(C.maxMods(1), 3)
eq(C.maxMods(15), 9)
for r = 1, 15 do
	assert(C.maxMods(r) >= 3, "every rarity has room")
end
local full = rareItem(2466, 1, {rarity_physicalAbsorb = 1, rarity_iceAbsorb = 1, rarity_clubSkill = 1})
eq(select(2, C.check("exalted", full)), "full", "3 modifiers on a Common item: full")
eq(C.apply("exalted", full), false)
eq(#C.readMods(full), 3, "nothing added to a full item")
eq(C.check("annulment", full), true, "a full item can still be annulled")

-- ---------------------------------------------------------------- Exalted Orb
-- armor: no element group. Groups sorted: absorb(30), skill(30), special(25) -> 85; roll 61 = special
local armor = rareItem(2466, 6, {rarity_holyAbsorb = 2})
dice = {61, 2, 3} -- group special, entry 2 (mana leech), value 3
local ok, res = C.apply("exalted", armor)
eq(ok, true, "exalted on armor")
eq(res.added.key, "rarity_manaLeechChance")
eq(armor:getCustomAttribute("rarity_manaLeechChance"), 2, "the chance is two thirds of the roll (uniform chance rolls)")
eq(armor:getCustomAttribute("rarity_manaLeechAmount"), 3, "leech pair gets both keys, the amount the full roll")
eq(#C.readMods(armor), 2)
eq(armor:getAttribute(ITEM_ATTRIBUTE_DESCRIPTION), "Level: 42, Holy +2%, Mana Chance +2%, Mana Amount +3%")
eq(res.text, "golden armor gained Mana Chance +2%, Mana Amount +3%.")
for v, want in ipairs({1, 1, 2, 3, 3, 4}) do
	eq(C.specialChance(v), want, "special chance of a roll of " .. v .. " (as engine patch 0004)")
end
-- the value range follows the rarity (rarity 6: 1..3 for absorbs)
dice = {1, 1, 2}
C.apply("exalted", armor)
eq(armor:getCustomAttribute("rarity_physicalAbsorb"), 2, "absorb added within 1..3")
-- an element only on weapons without an own element, and at most one
local w = rareItem(2400, 3, {})
local add = C.addable(w)
eq(#add.element, 8, "weapon can get an element")
eq(#C.addable(armor).element, 0, "armor cannot")
eq(#C.addable(rareItem(8925, 3, {})).element, 0, "weapon with its own element cannot")
eq(#C.addable(sword).element, 0, "only one element modifier")
-- groups sorted absorb, element, skill, special = 30, 15, 30, 25 -> roll 31..45 = element
dice = {40, 3, 5}
ok, res = C.apply("exalted", w)
eq(res.added.group, "element")
eq(w:getCustomAttribute("rarity_elementenergy"), 5)
eq(w:getAttribute(ITEM_ATTRIBUTE_DESCRIPTION), "Level: 42, Element: Energy +5% dmg")
-- never a modifier the item already has
dice = {1, 1, 1}
local before = armor:getCustomAttribute("rarity_physicalAbsorb")
C.apply("exalted", armor)
eq(armor:getCustomAttribute("rarity_physicalAbsorb"), before, "existing modifier unchanged")
eq(armor:getCustomAttribute("rarity_energyAbsorb"), 1, "the next free absorb was taken")
-- skill weights: profession skills are rarer
local skillRows = C.addable(rareItem(2466, 1, {})).skill
local combat, prof = 0, 0
for _, row in ipairs(skillRows) do
	if row.entry.kind == "combat" then combat = combat + row.weight else prof = prof + row.weight end
end
eq(combat, 7 * 4)
eq(prof, 8)

-- ---------------------------------------------------------------- Orb of Annulment
local ann = rareItem(2400, 6, {rarity_swordSkill = 2, rarity_lifeLeechChance = 3, rarity_lifeLeechAmount = 3})
dice = {2}
ok, res = C.apply("annulment", ann)
eq(ok, true)
eq(res.removed.key, "rarity_lifeLeechChance", "second modifier removed")
eq(ann:getCustomAttribute("rarity_lifeLeechAmount"), nil, "both keys of the pair go")
eq(ann:getCustomAttribute("rarity_swordSkill"), 2, "the other stays")
eq(C.rarityOf(ann), 6, "rarity stays")
eq(ann:getAttribute(ITEM_ATTRIBUTE_DESCRIPTION), "Level: 42, Sword +2")
dice = {1}
C.apply("annulment", ann)
eq(#C.readMods(ann), 0)
eq(ann:getAttribute(ITEM_ATTRIBUTE_DESCRIPTION), "Level: 42", "no modifiers left")
eq(select(2, C.check("annulment", ann)), "noMods", "nothing left to annul")
eq(C.check("exalted", ann), true, "but it can be exalted again")

-- description: text in front of the rarity part and upgrade slots behind it are kept
local deco = rareItem(2466, 2, {rarity_iceAbsorb = 1})
deco:setAttribute(ITEM_ATTRIBUTE_DESCRIPTION, "Forged by Ana, Level: 42, Ice +1% [Armor+2]")
dice = {1, 1, 1}
C.apply("exalted", deco)
eq(deco:getAttribute(ITEM_ATTRIBUTE_DESCRIPTION), "Forged by Ana, Level: 42, Physical +1%, Ice +1% [Armor+2]")

-- ---------------------------------------------------------------- Orb of Scouring (a new plain copy)
local sc = rareItem(2466, 7, {rarity_deathAbsorb = 3})
ok, res = C.apply("scouring", sc)
eq(ok, true)
eq(sc.removed, true, "old copy removed")
eq(res.item.removed, false)
eq(res.item.parent, bag, "new copy in the same container")
eq(C.isNormal(res.item), true, "normal now")
eq(res.text, "golden armor is now a normal item.")

-- ---------------------------------------------------------------- Transmutation / Alchemy / Chaos / Divine
local tr = put(newItem(2466))
dice = {80} -- transmutation weights 65 / 35 -> rarity 2
engineRolls = 0
ok, res = C.apply("transmutation", tr)
eq(ok, true)
eq(engineRolls, 1, "the engine rolled the rarity")
eq(C.rarityOf(res.item), 2, "Uncommon")
eq(tr.removed, true)
eq(res.text, "golden armor is now Uncommon (level 17): Earth +1%, Sword +1.")
dice = {100} -- alchemy 55 / 30 / 15 -> rarity 5
ok, res = C.apply("alchemy", put(newItem(2400)))
eq(C.rarityOf(res.item), 5, "Legendary")
local ch = rareItem(2400, 9, {rarity_axeSkill = 3})
ok, res = C.apply("chaos", ch)
eq(C.rarityOf(res.item), 9, "chaos keeps the rarity")
eq(res.item:getCustomAttribute("rarity_axeSkill"), nil, "and rolls new modifiers")
dice = {16} -- above the 15% stock chance: no rarity
ok, res = C.apply("divine", rareItem(2400, 12, {}))
eq(res.rarity, 0, "the stock divine roll mostly removes the rarity")
dice = {15, 100, 18} -- inside 15%, rarity 1 fails (100 > 25), rarity 2 hits (18 <= 18)
eq(C.rollDivineRarity(), 2)

-- the engine refused a rarity (no equipment slot in the real items.otb): nothing changes
local saved = Game.createItemWithRarity
Game.createItemWithRarity = function(id, count) return newItem(id, count) end
local keep = put(newItem(2466))
dice = {1}
ok, res = C.apply("transmutation", keep)
eq(ok, false, "refused")
eq(keep.removed, false, "original kept")
Game.createItemWithRarity = saved

-- ---------------------------------------------------------------- describe / signature
local d = C.describe(sword)
eq(d.rarityName, "Epic")
eq(d.maxMods, 5)
eq(#d.mods, 4)
eq(d.orbs.exalted, "", "exalted usable on the sword")
eq(d.orbs.transmutation, C.reasons.needNormal)
local sig = C.signature(sword)
dice = {1, 1, 1}
C.apply("exalted", sword)
assert(C.signature(sword) ~= sig, "signature changes with the modifiers")
eq(C.describe(sword).orbs.exalted, C.reasons.full, "five of five: full")


-- ---------------------------------------------------------------- Chaos item modifiers through the orbs
-- Exalted: the Chaos group comes after the engine's groups. Armor (kind "armor"): absorb 30, skill 30, special 25,
-- chaos 25 -> roll 86..110 is the Chaos group; its entries for armor: dodge 6, reflect 6, thorns 8, damage from
-- monsters 8 (28) -> roll 13..20 = thorns; rarity 4 (tier 2, 8..15) at level 42 (window 31..60: no pull) -> 11
local ca = rareItem(2466, 4, {rarity_iceAbsorb = 2})
dice = {100, 15, 11}
ok, res = C.apply("exalted", ca)
eq(ok, true, "exalted adds a Chaos modifier")
eq(res.added.group, "chaos")
eq(ca:getCustomAttribute("chaos_mod_thorns"), 11, "stored as chaos_mod_thorns")
eq(res.text, "golden armor gained Thorns +11.")
eq(ca:getAttribute(ITEM_ATTRIBUTE_DESCRIPTION), "Level: 42, Ice +2%, Thorns +11", "description shows it")
eq(#C.readMods(ca), 2, "a Chaos modifier is one modifier")
-- a weapon never gets an armor modifier, and armor never attack speed
local kinds = {}
for _, row in ipairs(C.addable(ca).chaos) do kinds[row.entry.key] = true end
eq(kinds.attackspeed, nil, "no attack speed on armor")
eq(kinds.thorns, nil, "thorns already there")
eq(kinds.dodge, true)
-- the slot limit counts Chaos modifiers: Common armor (3 slots) with 2 engine modifiers + 1 Chaos modifier is full
local cfull = rareItem(2466, 1, {rarity_physicalAbsorb = 1, rarity_clubSkill = 1, chaos_mod_dodge = 1})
eq(select(2, C.check("exalted", cfull)), "full", "Chaos modifiers take slots")
-- Annulment can take the Chaos modifier (mods in description order: absorb, skill, special, chaos, element)
dice = {2}
ok, res = C.apply("annulment", ca)
eq(res.removed.group, "chaos", "annulment removes a Chaos modifier")
eq(ca:getCustomAttribute("chaos_mod_thorns"), nil)
eq(ca:getAttribute(ITEM_ATTRIBUTE_DESCRIPTION), "Level: 42, Ice +2%")
-- attack speed is the weapon's own interval (ITEM_ATTRIBUTE_ATTACK_SPEED); removing it gives the base back
ITEM_ATTRIBUTE_ATTACK_SPEED = 99
function Item:removeAttribute(k) self.attrs[k] = nil end
local aw = rareItem(2400, 7, {})
M.set(aw, "attackspeed", 8)
eq(aw:getAttribute(ITEM_ATTRIBUTE_ATTACK_SPEED), 1840, "2000 ms base (no own interval) -8%")
eq(aw:getAttribute(ITEM_ATTRIBUTE_DESCRIPTION), "Level: 42", "the description is the caller's job")
C.rewriteDescription(aw)
eq(aw:getAttribute(ITEM_ATTRIBUTE_DESCRIPTION), "Level: 42, Attack Speed +8%")
dice = {1}
C.apply("annulment", aw)
eq(aw:getAttribute(ITEM_ATTRIBUTE_ATTACK_SPEED), nil, "interval back to the item type's")
ITEM_ATTRIBUTE_ATTACK_SPEED = nil
-- orbs that make a new copy roll Chaos modifiers like a drop (M.random: lowest = every chance hits)
M.random = function(a, b) return a end
ok, res = C.apply("chaos", rareItem(2400, 9, {}))
local cm = M.read(res.item)
eq(#cm, 2, "a Chaos Orb copy of rarity 9 rolled two Chaos modifiers (first and second chance hit)")
eq(cm[1].key, "attackspeed", "lowest weighted pick = the first weapon modifier")
eq(#C.readMods(res.item), 4, "2 engine + 2 Chaos, under the maximum of 7")
assert(res.text:find("Attack Speed %+"), "the result text lists them")
-- Scouring makes a plain copy: no Chaos modifiers survive
ok, res = C.apply("scouring", res.item)
eq(#M.read(res.item), 0, "scoured")
-- no free slot: nothing is rolled
local tight = rareItem(2466, 1, {rarity_physicalAbsorb = 1, rarity_clubSkill = 1, rarity_iceAbsorb = 1})
eq(#C.rollDropMods(tight), 0, "full item gets no Chaos modifier")
eq(#C.rollDropMods(unique), 0, "uniques never")
-- a monster drop the engine has not rolled yet (rarity only, no item level): room for the engine's modifiers is kept
-- (a weapon one Chaos modifier, other gear two) and the description waits for the engine
local pending = put(newItem(2400))
pending:setCustomAttribute("rarity", 9)
eq(#C.rollDropMods(pending), 1, "pending weapon: one, though rarity 9 rolled two")
eq(pending:getAttribute(ITEM_ATTRIBUTE_DESCRIPTION), "", "description left to the engine")
local pendingArmor = put(newItem(2466))
pendingArmor:setCustomAttribute("rarity", 9)
eq(#C.rollDropMods(pendingArmor), 2, "pending armor: two")
M.random = function(a, b) return b end

-- ---------------------------------------------------------------- bench preview
local pv = C.describe(rareItem(2466, 4, {rarity_iceAbsorb = 2}))
eq(pv.preview.exalted, "1 -> 2 of 5 modifiers")
eq(pv.preview.annulment, "one of 1 modifiers goes")
eq(pv.preview.transmutation, "", "no preview for an orb that does not fit")
eq(C.describe(put(newItem(2400))).preview.alchemy, "Rare 55%, Epic 30%, Legendary 15%")

-- ---------------------------------------------------------------- Rift Keys
local R, rcfg = C.rift()
local function newKey(tier, mods)
	local k = put(newItem(rcfg.key.itemId))
	k:setActionId(rcfg.key.actionId)
	C.writeKey(k, {tier = tier, mods = R.decodeMods(rcfg, mods or "")})
	return k
end
local key = newKey(4, "")
eq(C.isRiftKey(key), true, "a key")
eq(C.isRiftKey(put(newItem(rcfg.key.itemId))), false, "the base item without the action id is no key")
eq(C.check("exalted", key), true, "exalted on an empty key")
eq(select(2, C.check("annulment", key)), "keyNoMods")
eq(select(2, C.check("scouring", key)), "keyNoMods")
eq(select(2, C.check("chaos", key)), "keyNoMods")
eq(select(2, C.check("divine", key)), "keyNoMods")
-- Transmutation: one modifier. pool of 8, pick 3 = haste, value step 0 -> 40
dice = {300, 0} -- weighted pick: the old eight weigh 100 each, so 300 is the third (haste)
ok, res = C.apply("transmutation", key)
eq(ok, true, "transmutation on a key")
eq(key:getCustomAttribute("rift_mods"), "haste:40")
eq(key:getAttribute(ITEM_ATTRIBUTE_NAME), "Rift Key (Tier 4)")
eq(key:getCustomAttribute("rift_tier"), 4, "tier unchanged")
assert(key:getAttribute(ITEM_ATTRIBUTE_DESCRIPTION):find("Monsters move %+40 faster"), "description rewritten")
eq(res.text, "Rift Key (Tier 4): Monsters move +40 faster. Rewards: +6% quantity, +0% rarity, +0% experience.")
eq(select(2, C.check("transmutation", key)), "keyNeedNone", "transmutation needs an empty key")
eq(select(2, C.check("alchemy", key)), "keyNeedNone")
-- Exalted up to the maximum (3)
dice = {100, 2}
C.apply("exalted", key) -- pool without haste: vitality first, value 20 + 2 x 5
eq(key:getCustomAttribute("rift_mods"), "vitality:30,haste:40", "config order")
dice = {600, 0}
C.apply("exalted", key) -- pool of 6 left (vitality and haste taken): the 6th is swarm, value 1
eq(#C.readKey(key).mods, 3)
eq(select(2, C.check("exalted", key)), "keyFull", "three is the maximum")
eq(C.describe(key).maxMods, 3)
eq(C.describe(key).kind, "riftkey")
-- Divine: same modifiers, new values inside the ranges
dice = {8, 0, 2}
C.apply("divine", key)
local dk = C.readKey(key).mods
eq(dk[1].key, "vitality"); eq(dk[1].value, 60, "vitality 20 + 8 x 5")
eq(dk[2].key, "haste"); eq(dk[2].value, 40)
eq(#dk, 3)
-- Annulment: one goes
dice = {1}
ok, res = C.apply("annulment", key)
eq(#C.readKey(key).mods, 2)
eq(C.readKey(key).mods[1].key, "haste", "the first one went")
assert(res.text:find("lost \"Monsters have %+60%% health\""), res.text)
-- Chaos: new modifiers (1-3 by the drop weights)
dice = {100} -- count roll 100 of 100 -> 3 modifiers; then the lowest dice: the first of the pool each time
C.apply("chaos", key)
local ck = C.readKey(key).mods
eq(#ck, 3, "chaos rolled three")
eq(ck[1].key, "vitality"); eq(ck[2].key, "brutality"); eq(ck[3].key, "haste")
-- Scouring: all go
C.apply("scouring", key)
eq(key:getCustomAttribute("rift_mods"), "", "scoured key")
assert(key:getAttribute(ITEM_ATTRIBUTE_DESCRIPTION):find("Modifiers: none"), "description says none")
-- Alchemy: 2 or 3 on an empty key ({2, 60}, {3, 40}: roll 61 -> 3)
dice = {61}
C.apply("alchemy", key)
eq(#C.readKey(key).mods, 3, "alchemy gave three")
-- uniques and rarity rules do not apply; a stack of keys does not exist (not stackable). The signature follows mods
local ksig = C.signature(key)
dice = {1}
C.apply("annulment", key)
assert(C.signature(key) ~= ksig, "key signature changes")
-- maxMods from the config caps the decoded list too
eq(#R.decodeMods(rcfg, "vitality:20,brutality:20,haste:40,elites:50"), 3, "at most key.maxMods")

print("crafting_test: OK")
