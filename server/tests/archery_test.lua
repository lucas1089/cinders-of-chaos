-- Run from the server/ folder: luajit tests/archery_test.lua (and lua5.3; CI runs both). Mock engine API.
-- Infinite arrows and quivers (server/README.md "Infinite arrows and quivers"):
--   * data/lib/chaos_archery_core.lua: the launcher bands, the attack and hit chance without ammunition, the balance
--     bands (the engine's damage formula with the ammunition of before against the launcher alone), old items, refunds
--   * quivers in the item system: kind, gear, which modifiers they roll (and weapons never roll), item level gates,
--     the slot rules (the quiver counts in the off-hand only with a bow or crossbow), implicits, the crafting bonus,
--     the tooltip ("Off-hand: Quiver")
--   * the hands (engine src-patch 0023, mirrored in ChaosArchery.handsAllowed): bow or crossbow + quiver allowed, a
--     shield or anything else beside a launcher refused, a quiver beside an empty weapon hand allowed and beside any
--     other weapon refused, the ammunition slot refused; the login check (archery.lua A.checkHands) moves a quiver
--     out of the ammunition slot to the off-hand, else the backpack, else the inbox, saved, idempotent; a ring left in
--     the ammunition slot (0023's second ring slot, gone with src-patch 0058) goes to the backpack or the inbox
--   * data/scripts/chaos/archery.lua: the ammunition sweep (save-safe, once, the stash), the quiver's skill and speed,
--     old launchers; weapon_styles.lua: the no-ammunition hit (splash by kind, critical strike, element, extra shot)
--   * loot.lua: quivers are gear drops, arrows and bolts are none; server/sql/chaos_archery.sql names the quivers
local checks, fails = 0, 0
local function ok(c, m)
	checks = checks + 1
	if not c then
		fails = fails + 1
		print("FAIL " .. tostring(m))
	end
end
local function eq(a, b, m)
	ok(a == b, (m or "check") .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end

-- Lua 5.3 has no `bit` library (the engine's LuaJIT has); weapon_styles.lua uses bit.band
bit = bit or {band = function(a, b)
	local r, p = 0, 1
	while a > 0 and b > 0 do
		if a % 2 == 1 and b % 2 == 1 then
			r = r + p
		end
		a, b, p = math.floor(a / 2), math.floor(b / 2), p * 2
	end
	return r
end}

-- ---------------------------------------------------------------- engine constants
CONST_SLOT_HEAD, CONST_SLOT_NECKLACE, CONST_SLOT_BACKPACK, CONST_SLOT_ARMOR, CONST_SLOT_RIGHT, CONST_SLOT_LEFT = 1, 2, 3, 4, 5, 6
CONST_SLOT_LEGS, CONST_SLOT_FEET, CONST_SLOT_RING, CONST_SLOT_AMMO = 7, 8, 9, 10
CONST_SLOT_FIRST, CONST_SLOT_LAST = 1, 10
SLOTP_HEAD, SLOTP_NECKLACE, SLOTP_BACKPACK, SLOTP_ARMOR, SLOTP_RIGHT, SLOTP_LEFT = 1, 2, 4, 8, 16, 32
SLOTP_LEGS, SLOTP_FEET, SLOTP_RING, SLOTP_AMMO, SLOTP_TWO_HAND = 64, 128, 256, 512, 2048
WEAPON_NONE, WEAPON_SWORD, WEAPON_CLUB, WEAPON_AXE, WEAPON_SHIELD, WEAPON_DISTANCE, WEAPON_WAND, WEAPON_AMMO = 0, 1, 2, 3, 4, 5, 6, 7
WEAPON_QUIVER = 8 -- engine src-patch 0023
AMMO_NONE, AMMO_BOLT, AMMO_ARROW = 0, 1, 2
ITEM_ATTRIBUTE_DESCRIPTION, ITEM_ATTRIBUTE_ATTACK, ITEM_ATTRIBUTE_HITCHANCE, ITEM_ATTRIBUTE_ATTACK_SPEED = 1, 2, 3, 4
ITEM_ATTRIBUTE_DEFENSE, ITEM_ATTRIBUTE_ARMOR = 5, 6
COMBAT_NONE, COMBAT_PHYSICALDAMAGE, COMBAT_ENERGYDAMAGE, COMBAT_EARTHDAMAGE, COMBAT_FIREDAMAGE = 0, 1, 2, 4, 8
COMBAT_ICEDAMAGE, COMBAT_HEALING = 512, 128
ORIGIN_NONE, ORIGIN_CONDITION, ORIGIN_SPELL, ORIGIN_MELEE, ORIGIN_RANGED = 0, 1, 2, 3, 4
CONDITION_ATTRIBUTES, CONDITIONID_DEFAULT = 1, 0
CONDITION_PARAM_SUBID, CONDITION_PARAM_TICKS, CONDITION_PARAM_SKILL_DISTANCE = 1, 2, 3
CONST_ME_NONE, CONST_ME_HITAREA, CONST_ME_HITBYFIRE = 0, 1, 2
CONST_ANI_ARROW, CONST_ANI_BOLT, CONST_ANI_FIRE = 3, 2, 4
MESSAGE_EVENT_ADVANCE, RETURNVALUE_NOERROR = 19, 0
CONTAINER_POSITION = 0xFFFF

-- ---------------------------------------------------------------- item types (fixture: numbers of the base items.xml)
-- launchers before the patch: attack and hit bonus of the base items; ammoType says what they fired
local BASE = {
	[2456] = {name = "bow", attack = 0, hit = 0, ammo = AMMO_ARROW},
	[2455] = {name = "crossbow", attack = 0, hit = 0, ammo = AMMO_BOLT},
	[8857] = {name = "silkweaver bow", attack = 0, hit = 3, ammo = AMMO_ARROW},
	[8856] = {name = "an old bow", attack = 0, hit = 7, ammo = AMMO_ARROW},
	[8849] = {name = "modified crossbow", attack = 0, hit = 1, ammo = AMMO_BOLT},
	[18453] = {name = "crystal crossbow", attack = 4, hit = 3, ammo = AMMO_BOLT},
	[22417] = {name = "umbral bow", attack = 4, hit = 5, ammo = AMMO_ARROW},
	[27199] = {name = "falcon bow", attack = 7, hit = 5, ammo = AMMO_ARROW},
	[27384] = {name = "soulpiercer", attack = 9, hit = 6, ammo = AMMO_BOLT},
	[27471] = {name = "sanguine bow", attack = 9, hit = 6, ammo = AMMO_ARROW},
	[29874] = {name = "seraphic bleeder", attack = 6, hit = 8, ammo = AMMO_ARROW},
	[29875] = {name = "seraphic piercer", attack = 12, hit = 3, ammo = AMMO_BOLT}
}
local A_CFG = dofile("data/lib/chaos_archery_config.lua")
local TYPES = {
	[2400] = {name = "magic sword", weaponType = WEAPON_SWORD, attack = 48, slot = 48},
	[2466] = {name = "golden armor", armor = 14, slot = SLOTP_ARMOR},
	[2050] = {name = "torch", slot = SLOTP_AMMO}, -- an ammunition-slot item that is no quiver
	[2544] = {name = "arrow", weaponType = WEAPON_AMMO, ammoType = AMMO_ARROW, slot = SLOTP_AMMO, stackable = true},
	[2543] = {name = "bolt", weaponType = WEAPON_AMMO, ammoType = AMMO_BOLT, slot = SLOTP_AMMO, stackable = true},
	[99001] = {name = "odd arrow", weaponType = WEAPON_AMMO, ammoType = AMMO_ARROW, slot = SLOTP_AMMO, stackable = true},
	[2389] = {name = "spear", weaponType = WEAPON_DISTANCE, attack = 25, slot = 48, stackable = true},
	[2148] = {name = "gold coin", stackable = true},
	[1988] = {name = "backpack", container = true, slot = SLOTP_BACKPACK},
	[99002] = {name = "old bolter", weaponType = WEAPON_DISTANCE, attack = 70, slot = 48 + SLOTP_TWO_HAND, minLevel = 400},
	[99003] = {name = "old quiver", container = true, slot = SLOTP_AMMO},
	[2520] = {name = "demon shield", weaponType = WEAPON_SHIELD, slot = 48},
	[2454] = {name = "war axe", weaponType = WEAPON_AXE, attack = 45, slot = 48 + SLOTP_TWO_HAND},
	[2410] = {name = "throwing knife", weaponType = WEAPON_DISTANCE, attack = 15, slot = 48, stackable = true},
	[2357] = {name = "ring of wisdom", slot = SLOTP_RING + 48},
	[2165] = {name = "stealth ring", slot = SLOTP_RING + 48},
	[2164] = {name = "might ring", slot = SLOTP_RING + 48, might = true}, -- items.xml chaosMightRing (0023)
	[2169] = {name = "time ring", slot = SLOTP_RING + 48}
}
-- the patched launchers: attack and hit chance of their band, no ammunition type
local A -- ChaosArchery, loaded below
local function patchedLaunchers()
	for id, b in pairs(BASE) do
		local kind, level = A.launcherOf(id)
		TYPES[id] = {name = b.name, weaponType = WEAPON_DISTANCE, slot = 48 + SLOTP_TWO_HAND,
			attack = A.newAttack(b.attack, kind, level), hit = A.newHit(b.hit, kind, level), ammoType = AMMO_NONE,
			minLevel = level}
	end
	for id in pairs(A_CFG.quivers) do
		-- the install tool's quiver: weapon type quiver, the off-hand (items.xml slotType right-hand)
		TYPES[id] = {name = "quiver " .. id, weaponType = WEAPON_QUIVER, slot = SLOTP_RIGHT, minLevel = A_CFG.quivers[id][1],
			description = "Implicit: the type text"}
	end
end

function ItemType(id)
	local t = TYPES[id] or {}
	return {
		getId = function() return t.name and id or 0 end,
		getName = function() return t.name or "" end,
		isContainer = function() return t.container == true end,
		isStackable = function() return t.stackable == true end,
		isRune = function() return false end,
		getWeaponType = function() return t.weaponType or 0 end,
		getAmmoType = function() return t.ammoType or 0 end,
		getSlotPosition = function() return t.slot or 0 end,
		getArmor = function() return t.armor or 0 end,
		getAttack = function() return t.attack or 0 end,
		getDefense = function() return 0 end,
		getExtraDefense = function() return 0 end,
		getHitChance = function() return t.hit or 0 end,
		getShootRange = function() return 1 end,
		getElementDamage = function() return 0 end,
		getElementType = function() return 0 end,
		getAttackSpeed = function() return t.attackSpeed or 0 end,
		getAbilities = function() return {} end,
		getMinReqLevel = function() return t.minLevel or 0 end,
		getMinReqMagicLevel = function() return 0 end,
		getVocationString = function() return "" end,
		getDescription = function() return t.description or "" end,
		getClientId = function() return id end,
		getCharges = function() return 0 end,
		isMightRing = function() return t.might == true end,
		getDuration = function() return 0 end
	}
end

-- items
local Item = {}
Item.__index = Item
local function newItem(id, count)
	return setmetatable({id = id, count = count or 1, attrs = {}, custom = {}, inner = {}}, Item)
end
function Item:getId() return self.id end
function Item:getType() return ItemType(self.id) end
function Item:getCount() return self.count end
function Item:getName() return ItemType(self.id):getName() end
function Item:getWeight() return 100 end
function Item:isItem() return true end
function Item:isContainer() return TYPES[self.id] and TYPES[self.id].container == true end
function Item:getCustomAttribute(k) return self.custom[tostring(k):lower()] end
function Item:setCustomAttribute(k, v) self.custom[tostring(k):lower()] = v end
function Item:removeCustomAttribute(k) self.custom[tostring(k):lower()] = nil return true end
function Item:hasAttribute(k) return self.attrs[k] ~= nil end
function Item:getAttribute(k) return self.attrs[k] or (k == ITEM_ATTRIBUTE_DESCRIPTION and "" or nil) end
function Item:setAttribute(k, v) self.attrs[k] = v end
function Item:removeAttribute(k) self.attrs[k] = nil end
function Item:getActionId() return 0 end
function Item:remove() self.removed = true return true end
function Item:getItems(recursive)
	local out = {}
	local function add(list)
		for _, it in ipairs(list) do
			if not it.removed then
				out[#out + 1] = it
				if recursive then add(it.inner) end
			end
		end
	end
	add(self.inner)
	return out
end
function Item:addInner(it) self.inner[#self.inner + 1] = it return it end

-- ---------------------------------------------------------------- 1. bands and the launcher alone
dofile("data/lib/chaos_item_mods.lua") -- loads chaos_archery_core.lua
A = ChaosArchery
local M = ChaosItemMods
eq(type(A), "table", "ChaosArchery loaded with the item modifiers")
patchedLaunchers()

eq(A.band("bow", 0)[2], 29, "bow at 0: the arrows of levels 1-39 on average")
eq(A.band("bow", 39)[2], 33, "bow at 39: tarsal arrow")
eq(A.band("bow", 40)[2], 38, "bow at 40: onyx arrow")
eq(A.band("bow", 1000)[2], 65, "bow from 90: crystalline arrow")
eq(A.band("crossbow", 0)[2], 32, "crossbow at 0: the bolts of levels 1-44 on average")
eq(A.band("crossbow", 55)[2], 40, "crossbow at 55: power bolt")
eq(A.band("crossbow", 90)[2], 66, "crossbow from 90: prismatic bolt")
eq(A.newAttack(9, "bow", 600), 74, "sanguine bow: 9 + 65")
eq(A.newHit(6, "bow", 600), 100, "hit chance at most 100 (95 + 6)")
eq(A.newHit(-20, "crossbow", 100), 70, "a hit malus stays (90 - 20)")
eq(A.missile("bow", 150, "Umbral Bow"), "crystallinearrow", "band missile")
eq(A.missile("crossbow", 300, "water arbalest"), "waterbolt", "elemental missile by name")
eq(A.missile("bow", 0, "icicle bow"), "shiverarrow", "icicle bow")
for kind, rows in pairs(A_CFG.bands) do
	for i = 2, #rows do
		ok(rows[i][1] > rows[i - 1][1] and rows[i][2] >= rows[i - 1][2], kind .. " bands grow with the level")
	end
	ok(rows[1][1] == 0, kind .. " bands start at level 0")
	-- the old-item rule needs every band above the biggest rarity bonus of chaos_crafting.lua (Transcendent at 150)
	ok(rows[1][2] > 9 + math.floor(150 * 7 / 100), kind .. ": the smallest band beats any rarity bonus")
end
for id, e in pairs(A_CFG.launchers) do
	ok(e[1] == "bow" or e[1] == "crossbow", "launcher " .. id .. " kind")
	ok(e[2] >= 0 and e[2] <= 1000, "launcher " .. id .. " level")
end

-- kinds: config, fallback by name (a set look the config may not name), throwing weapons, unpatched launchers
eq(A.kindOfType(ItemType(2456)), "bow", "bow")
eq(A.kindOfType(ItemType(29875)), "crossbow", "crossbow from the config")
eq(A.kindOfType(ItemType(99002)), "crossbow", "a launcher missing from the config: a crossbow by its name")
eq(select(2, A.launcherOf(99002, ItemType(99002))), 400, "its level from the type")
eq(A.kindOfType(ItemType(2389)), nil, "a spear is no launcher (one-handed)")
eq(A.kindOfType(ItemType(2400)), nil, "a sword is no launcher")

-- old items: an attack attribute below the new type attack gets the band once; uniques too
eq(A.legacyAttack(9 + 3, A.newAttack(9, "bow", 600), 27471), 77, "a Rare sanguine bow of before: 12 + 65")
eq(A.legacyAttack(74 + 3, 74, 27471), nil, "rolled after the patch: unchanged")
eq(A.legacyAttack(74, 74, 27471), nil, "equal to the type: unchanged")
eq(A.legacyAttack(nil, 74, 27471), nil, "no attribute")
eq(A.legacyAttack(5, 74, 2400), nil, "not a launcher")
local maxBonus = 9 + math.floor(150 * 7 / 100) -- chaos_crafting.lua baseBonus of Transcendent at item level 150
for id, b in pairs(BASE) do
	local kind, level = A.launcherOf(id)
	local typeAttack = TYPES[id].attack
	eq(A.legacyAttack(b.attack + maxBonus, typeAttack, id), b.attack + maxBonus + A.addedAttack(kind, level),
		"the best old roll of " .. id .. " is still below the new type attack")
end

-- ---------------------------------------------------------------- 2. balance bands
-- the engine's formula (weapons.cpp): max = level / 5 + (skill / 4 + 1) * attack / 3 * 1.03, min = level / 5,
-- average = (min + max) / 2 x hit chance. Before: launcher attack + the ammunition's, the ammunition's hit chance +
-- the launcher's bonus. Now: the launcher alone (A.newAttack, A.newHit). The characters: a typical distance skill at
-- each level and the launcher of their band, firing the best ammunition an NPC sold for their own level.
-- the ammunition of before (items.xml of the base: attack, the hit chance it gave at these skills), by the level an NPC
-- sold it from
local AMMO_AT = {
	bow = {{0, 25, 91}, {20, 28, 95}, {30, 33, 94}, {40, 38, 94}, {90, 65, 95}},
	crossbow = {{0, 30, 87}, {30, 33, 87}, {40, 36, 89}, {55, 40, 91}, {70, 56, 90}, {90, 66, 90}}
}
local function ammoFor(kind, charLevel)
	local best = AMMO_AT[kind][1]
	for _, r in ipairs(AMMO_AT[kind]) do
		if charLevel >= r[1] then
			best = r
		end
	end
	return best
end
local ROWS = {
	-- character level, distance skill, launcher
	{8, 30, 2456}, {15, 40, 2456}, {25, 50, 2456}, {35, 58, 2456}, {45, 62, 8857}, {65, 70, 8856}, {150, 88, 22417},
	{300, 102, 27199}, {600, 115, 27471}, {1000, 125, 29874},
	{8, 30, 2455}, {20, 45, 2455}, {35, 58, 2455}, {42, 60, 2455}, {50, 62, 8849}, {95, 80, 18453}, {400, 108, 27384},
	{1000, 125, 29875}
}
local report = {}
for _, r in ipairs(ROWS) do
	local lv, skill, id = r[1], r[2], r[3]
	local b = BASE[id]
	local kind, level = A.launcherOf(id)
	local ammo = ammoFor(kind, lv)
	local before = A.averageHit(lv, skill, b.attack + ammo[2], math.min(100, ammo[3] + b.hit))
	local after = A.averageHit(lv, skill, TYPES[id].attack, TYPES[id].hit)
	local pct = (after - before) / before * 100
	report[#report + 1] = string.format("| %d | %d | %s (%d) | %s %d | %.1f | %.1f | %+.1f%% |", lv, skill, b.name, level,
		kind == "bow" and "arrow" or "bolt", ammo[2], before, after, pct)
	local own = A.band(kind, level)
	if own[2] == ammo[2] and own[3] == ammo[3] then
		ok(math.abs(pct) < 0.01, "level " .. lv .. " " .. b.name .. ": the same damage with the band's ammunition")
	else
		-- the level 0 launchers serve levels 1-39 with the average arrow of those levels: within 20% either way
		ok(level == 0 and math.abs(pct) < 20, "level " .. lv .. " " .. b.name .. ": within 20% (" .. pct .. ")")
	end
end
if os.getenv("ARCHERY_REPORT") then
	print("| Level | Distance | Launcher (band level) | Ammunition before | Average hit before | Average hit after | Change |")
	print("|---|---|---|---|---|---|---|")
	for _, line in ipairs(report) do
		print(line)
	end
end

-- ---------------------------------------------------------------- 3. quivers in the item system
dofile("data/lib/chaos_crafting.lua")
local C = ChaosCrafting
local QUIVER = 29566
eq(M.kindOfType(ItemType(QUIVER)), "quiver", "a quiver base is a quiver")
eq(M.kindOfType(ItemType(2050)), "other", "a torch is no quiver")
eq(M.kindOfType(ItemType(99003)), "other", "an unpatched (container) quiver id is no quiver")
eq(A.isQuiverType(ItemType(99003)), false, "not a quiver while a container")
ok(C.isGear(newItem(QUIVER)), "a quiver carries modifiers")
ok(not C.isGear(newItem(2544, 10)), "arrows do not")
for id, q in pairs(A_CFG.quivers) do
	ok(q[1] >= 1 and q[1] <= 1000, "quiver " .. id .. " level")
	for key, v in pairs(q[2]) do
		local def = M.byKey[key]
		ok(def and def.kinds and def.kinds.quiver, "quiver " .. id .. " implicit " .. key .. " is a quiver modifier")
		ok(def and v <= def.cap, "quiver " .. id .. " implicit " .. key .. " under the cap")
	end
end
-- the pool: quiver modifiers and the shared ones, never the engine's open ones; weapons never get quiver modifiers
local qpool, wpool = {}, {}
for _, a in ipairs(C.affixes()) do
	if M.allowed(a, "quiver") then qpool[a.chaosKey or a.key] = true end
	if M.allowed(a, "weapon") then wpool[a.chaosKey or a.key] = true end
end
for _, def in ipairs(A_CFG.mods) do
	ok(qpool[def.key], "quivers roll " .. def.key)
	ok(not wpool[def.key], "weapons never roll " .. def.key)
end
for _, key in ipairs(A_CFG.sharedMods) do
	ok(qpool[key], "quivers roll the shared " .. key)
end
ok(not qpool["rarity_distanceSkill"] and not qpool["rarity_criticalHitChance"] and not qpool["rarity_fireAbsorb"],
	"no engine modifier on a quiver (the base rarity script would apply it without a bow)")
ok(not qpool.movespeed and not qpool.attackspeed, "no boots or weapon modifiers")
ok(wpool.attackspeed and wpool["rarity_distanceSkill"], "weapons keep theirs")

-- rolls: a deterministic generator; every modifier allowed, the count by rarity, tiers inside the item level's window
local function lcg(seed)
	local s = seed
	return function(a, b)
		s = (s * 1103515245 + 12345) % 2147483648
		return a + s % (b - a + 1)
	end
end
for _, level in ipairs({5, 40, 100, 145}) do
	for seed = 1, 30 do
		local q = newItem(QUIVER)
		local added = C.forge(q, 5, level, lcg(seed * 7 + level))
		eq(#added, M.modCount(5), "a Legendary quiver gets its rarity's modifiers")
		local top = M.maxTierFor(level)
		for _, m in ipairs(added) do
			ok(m.affix and M.allowed(m.affix, "quiver"), "rolled " .. tostring(m.key) .. " is a quiver modifier")
			ok(m.tier <= top and m.tier >= math.max(1, top - M.config.tierWindow + 1),
				"item level " .. level .. " gate: T" .. m.tier)
		end
		local p, s = C.sideCounts(C.readMods(q))
		ok(p <= M.sideLimit(5) and s <= M.sideLimit(5), "sides within the rarity's limit")
	end
end
for seed = 1, 40 do
	local sword = newItem(2400)
	for _, m in ipairs(C.forge(sword, 8, 120, lcg(seed))) do
		ok(not (m.affix.kinds and m.affix.kinds.quiver and not m.affix.kinds.weapon), "a sword rolled " .. tostring(m.key))
	end
end

-- slot rules: a quiver counts in the off-hand (the shield hand) only while a bow or crossbow is held
local function newPlayer()
	return {slots = {}, storage = {}, bank = 0, conditions = {}, msgs = {}, id = 0x10000001,
		getId = function(self) return self.id end,
		getGuid = function() return 7 end,
		getName = function() return "Archer" end,
		getSlotItem = function(self, s) local it = self.slots[s] return it and not it.removed and it or nil end,
		getStorageValue = function(self, k) return self.storage[k] or -1 end,
		setStorageValue = function(self, k, v) self.storage[k] = v end,
		getBankBalance = function(self) return self.bank end,
		setBankBalance = function(self, v) self.bank = v end,
		sendTextMessage = function(self, _, text) self.msgs[#self.msgs + 1] = text end,
		addCondition = function(self, c) self.conditions[#self.conditions + 1] = c end,
		removeCondition = function(self) self.removed = (self.removed or 0) + 1 end,
		isPlayer = function() return true end}
end
local p = newPlayer()
local quiver = newItem(QUIVER)
C.forge(quiver, 5, 100, lcg(3))
p.slots[CONST_SLOT_RIGHT] = quiver
local bits = M.slotBits()
eq(bits[CONST_SLOT_AMMO], nil, "the ammunition slot takes nothing (engine patch 0058; 0023 made it a second ring slot)")
eq(bits[CONST_SLOT_BADGE], SLOTP_BADGE, "the badge slot counts (engine patch 0058)")
ok(not M.fits(quiver, CONST_SLOT_RIGHT, bits, p), "no launcher: the quiver does not count")
ok(not M.fits(quiver, CONST_SLOT_RIGHT, bits), "no player given: never")
p.slots[CONST_SLOT_LEFT] = newItem(2400)
ok(not M.fits(quiver, CONST_SLOT_RIGHT, bits, p), "a sword: the quiver does not count")
p.slots[CONST_SLOT_LEFT] = newItem(2456)
ok(M.fits(quiver, CONST_SLOT_RIGHT, bits, p), "a bow: it counts in the off-hand")
eq(#M.equippedItems(p), 2, "bow and quiver")
ok(not M.fits(quiver, CONST_SLOT_LEFT, bits, p), "never in the weapon hand")
ok(not M.fits(quiver, CONST_SLOT_AMMO, bits, p), "never in the ammunition slot")
p.slots[CONST_SLOT_LEFT] = newItem(29875)
ok(M.fits(quiver, CONST_SLOT_RIGHT, bits, p), "a crossbow: it counts")
eq(M.handLauncher(p), "crossbow", "the hand's launcher kind (the quiver in the other hand is none)")
eq(M.kindOfType(ItemType(QUIVER)), "quiver", "a quiver of weapon type quiver is no weapon")
p.slots[CONST_SLOT_LEFT] = nil
eq(M.handLauncher(p), nil, "a quiver alone: no launcher")
local torch = newItem(2050)
ok(not M.fits(torch, CONST_SLOT_AMMO, bits, p), "a torch never counts")
-- a ring in the ammunition slot (worn there before engine patch 0058) does not count; the ring slot's does
local pr2 = newPlayer()
local ringA, ringB = newItem(2357), newItem(2165)
C.forge(ringA, 5, 120, lcg(21))
C.forge(ringB, 5, 120, lcg(22))
pr2.slots[CONST_SLOT_RING], pr2.slots[CONST_SLOT_AMMO] = ringA, ringB
ok(M.fits(ringA, CONST_SLOT_RING, bits, pr2), "the ring slot's ring counts")
ok(not M.fits(ringB, CONST_SLOT_AMMO, bits, pr2), "a ring in the ammunition slot does not")
eq(#M.equippedItems(pr2), 1, "one ring equipped")
local one = M.totals({ringA})
local keys = 0
for k, v in pairs(M.totals(M.equippedItems(pr2))) do
	eq(v, one[k], "one ring: " .. k .. " is the ring slot's")
	keys = keys + 1
end
ok(keys >= 1, "the ring rolled modifiers")
-- the jewel budget: at the top tier every modifier a ring may roll reaches its cap from the slots a character wears
-- (weapon, shield, helmet, armour, legs, boots, amulet + ring, the badge), without a second ring and without gloves or
-- a belt (server/data/spells/README.md "Badge slot")
local WORN = {weapon = 1, shield = 1, helmet = 1, armor = 1, legs = 1, boots = 1, jewel = 2, other = 1}
local short = {}
for _, def in ipairs(M.config.mods) do
	if def.kinds and def.kinds.jewel and def.cap then
		local n = 0
		for k, c in pairs(WORN) do
			if def.kinds[k] then n = n + c end
		end
		if n * def.tiers[#def.tiers][2] < def.cap then short[#short + 1] = def.key end
	end
end
eq(table.concat(short, ","), "", "every jewel modifier reaches its cap at T8 with one ring and the badge")
-- implicits under the caps
local imp = A.implicits(29873)
local totals = M.totals({}, imp)
eq(totals.bowdistance, 4, "the Seraphic quiver's implicit Distance Fighting")
eq(totals.multishot, 8, "and Extra Projectile Chance")
local capped = M.totals({}, A.merge(A.merge({}, imp), {bowdistance = 50}))
eq(capped.bowdistance, M.byKey.bowdistance.cap, "implicit + more stays under the cap")

-- the crafting bonus counts a quiver as equipment (not a tool)
dofile("data/scripts/chaos/craft_bonus_core.lua")
local CB = dofile("data/scripts/chaos/craft_bonus_config.lua")
ok(not ChaosCraftBonusCore.isTool(CB, "quiver", SLOTP_RIGHT), "a crafted quiver rolls a rarity")
local craftLevel = ChaosCraftBonusCore.itemLevel(CB, 35, 60, 0)
local cq = C.createItem and nil
ok(craftLevel >= 35 and craftLevel <= CB.gear.itemLevel.max, "a crafted quiver's item level " .. craftLevel)
Game = Game or {}
Game.createItem = function(id, n) return newItem(id, n) end
cq = C.createItem(QUIVER, 3, craftLevel, lcg(11))
eq(C.rarityOf(cq), 3, "the crafted quiver's rarity")
ok(#C.readMods(cq) == M.modCount(3), "and its modifiers")

-- the tooltip: slot, implicit rows, the note, no type text
dofile("data/scripts/chaos/item_tooltip_core.lua")
local T = ChaosItemTooltip
local tip = T.build(newItem(29873), {})
eq(tip.kind, "quiver", "tooltip kind")
eq(tip.slot, "Off-hand: Quiver", "tooltip slot")
eq(tip.cmp and tip.cmp[1], CONST_SLOT_RIGHT, "compared with the off-hand")
eq(tip.cmp and #tip.cmp, 1, "and only there")
eq(T.SLOT_SET[10], nil, "the tooltip asks for no ammunition slot (it takes nothing, engine patch 0058)")
eq(T.decodePos({x = CONTAINER_POSITION, y = 13, z = 0}).slot, 13, "a badge in the badge slot has a tooltip")
eq(tip.note, T.QUIVER_NOTE, "the bow note")
eq(tip.desc, nil, "no type text (it repeats the implicits)")
local imps = 0
for _, b in ipairs(tip.base) do
	if b.imp then
		imps = imps + 1
		ok(b.k:find("^chaos_mod_") ~= nil, "an implicit row uses the modifier key " .. b.k)
	end
end
eq(imps, 3, "three implicit rows on the Seraphic quiver")

-- ---------------------------------------------------------------- 3b. the hands (engine src-patch 0023)
eq(A.handKind(ItemType(QUIVER)), "quiver", "a quiver")
eq(A.handKind(ItemType(2456)), "launcher", "a bow")
eq(A.handKind(ItemType(29875)), "launcher", "a crossbow")
eq(A.handKind(ItemType(2520)), "shield", "a shield")
eq(A.handKind(ItemType(2454)), "twohanded", "a two-handed axe")
eq(A.handKind(ItemType(2400)), "weapon", "a one-handed sword")
eq(A.handKind(ItemType(2410)), "weapon", "a throwing weapon is one-handed")
eq(A.handKind(ItemType(2466)), "other", "an armour")
eq(A.handKind(ItemType(2357)), "ring", "a ring")
eq(A.handKind(ItemType(2050)), "other", "a torch (slot position ammo) is no ring")
-- WEAPON_QUIVER is the engine's constant; without it the core uses the same value
local savedWQ = WEAPON_QUIVER
WEAPON_QUIVER = nil
eq(A.quiverWeaponType(), 8, "the weapon type quiver without the engine constant")
WEAPON_QUIVER = savedWQ
-- main = the weapon hand, off = the shield hand
ok(A.handsAllowed("launcher", "quiver"), "bow or crossbow + quiver: allowed")
ok(not A.handsAllowed("launcher", "shield"), "bow + shield: refused")
ok(not A.handsAllowed("launcher", "weapon"), "bow + an off-hand blade: refused")
ok(not A.handsAllowed("launcher", "other"), "bow + anything else: refused")
ok(A.handsAllowed("launcher", nil), "bow alone")
ok(A.handsAllowed(nil, "quiver"), "quiver without a bow: allowed (equip it first, or take the bow off; it does nothing)")
ok(not A.handsAllowed("weapon", "quiver"), "quiver beside a sword: refused")
ok(not A.handsAllowed("twohanded", "quiver"), "quiver beside a two-handed axe: refused")
ok(not A.handsAllowed("quiver", nil), "a quiver never in the weapon hand")
ok(not A.handsAllowed(nil, "launcher"), "a bow never in the shield hand")
ok(not A.handsAllowed("twohanded", "shield"), "two-handed + shield: refused (as the engine always did)")
ok(A.handsAllowed("weapon", "shield"), "sword + shield")
ok(A.handsAllowed("weapon", "weapon"), "dual wield (the engine asks the storage)")
ok(not A.slotAllowed(CONST_SLOT_AMMO, "ring"), "the ammunition slot takes no ring (engine patch 0058)")
ok(not A.slotAllowed(CONST_SLOT_AMMO, "quiver"), "not a quiver")
ok(not A.slotAllowed(CONST_SLOT_AMMO, "other"), "not a torch or anything else")
ok(not A.slotAllowed(CONST_SLOT_AMMO, nil), "not an unknown item")
ok(A.slotAllowed(CONST_SLOT_RING, "ring"), "the ring slot takes a ring as always")
-- the login plan
local function plan(s)
	local out = {}
	for _, st in ipairs(A.loginPlan(s)) do
		out[#out + 1] = st.from .. ">" .. st.to
	end
	return table.concat(out, ",")
end
eq(plan({}), "", "nothing equipped: nothing to do")
eq(plan({main = "launcher", off = "quiver"}), "", "bow + quiver: nothing to do (idempotent)")
eq(plan({main = "launcher", ammo = "quiver"}), "ammo>off", "a quiver of before beside a bow: to the off-hand")
eq(plan({ammo = "quiver"}), "ammo>off", "a quiver of before, empty hands: to the off-hand")
eq(plan({main = "weapon", off = "shield", ammo = "quiver"}), "ammo>stow", "the off-hand is taken: stowed")
eq(plan({main = "weapon", ammo = "quiver"}), "ammo>stow", "beside a sword: stowed")
eq(plan({main = "launcher", ammo = "other"}), "ammo>stow", "anything else in the ammunition slot: stowed")
eq(plan({main = "launcher", off = "quiver", ammo = "ring"}), "ammo>stow", "a ring in the old second ring slot: stowed")
eq(plan({main = "launcher", ammo = "ring"}), "ammo>stow", "a ring is stowed even with the off-hand free")
eq(A.loginPlan({ammo = "ring"})[1].why, "ring", "for the ring rule (its own message)")
eq(plan({main = "launcher", off = "shield", ammo = "quiver"}), "off>stow,ammo>off",
	"a refused pair loses its off-hand item first; then the quiver goes there")
eq(plan({main = "weapon", off = "quiver"}), "off>stow", "a quiver beside a sword: stowed")
eq(plan({main = "quiver", ammo = "quiver"}), "main>stow,ammo>off", "a quiver in the weapon hand: stowed")
-- the might rings (items.xml chaosMightRing, 0023): one ring slot now, so one at a time without a rule of its own
ok(A.isMightRing(ItemType(2164)), "a might ring")
ok(not A.isMightRing(ItemType(2169)) and not A.isMightRing(ItemType(2357)), "a time ring or another ring is none")
ok(not A.isMightRing(nil) and not A.isMightRing({}), "no item type, or an engine without isMightRing: none")
eq(plan({ammo = "ring", ammoMight = true, ringMight = true}), "ammo>stow", "a might ring in the ammunition slot: stowed")
eq(plan({main = "launcher", off = "shield", ammo = "ring"}), "off>stow,ammo>stow", "the hands and the ring in one check")

-- ---------------------------------------------------------------- 4. the ammunition, refunds
ok(A.isAmmoId(2544), "arrow")
ok(A.isAmmoId(99001, ItemType(99001)), "any arrow by its type")
ok(not A.isAmmoId(2389, ItemType(2389)), "a spear is no ammunition")
eq(A.refundOf(18304, 100), 1000, "crystalline arrows: 10 gold each")
eq(A.refundOf(99001, 7), 7 * A_CFG.defaultRefund, "an unlisted arrow")
local take, gold, pieces = A.plan({{id = 2544, count = 100}, {id = 2400, count = 1}, {id = 2543, count = 30}})
eq(#take, 2, "two ammunition entries")
eq(gold, 130, "refund")
eq(pieces, 130, "pieces")
ok(A.refundText(1, 1):find("1 arrow and bolt left") ~= nil, "singular text")

-- ---------------------------------------------------------------- 5. archery.lua: sweep, skill, speed, old launchers
local events, callbacks, dbq = {}, {}, {}
CreatureEvent = function(name)
	local o = {}
	o.register = function() events[name] = o end
	return o
end
EventCallback = setmetatable({}, {__newindex = function(t, k, v) rawset(t, "_p", {k, v}) end,
	__index = function(t, k)
		if k == "register" then
			return function(this)
				local pnd = rawget(this, "_p")
				callbacks[pnd[1]] = pnd[2]
			end
		end
	end})
Condition = function(t, id)
	local c = {params = {}}
	function c:setParameter(k, v) self.params[k] = v end
	return c
end
local saveOk = true
local saves = 0
Chaos = {tables = {stash = "chaos_stash"}, saveCharacter = function() saves = saves + 1 return saveOk end}
local stashRows = {}
function Chaos.select(q, cols)
	local out = {}
	for _, r in ipairs(stashRows) do
		out[#out + 1] = {item_id = r[1], count = r[2]}
	end
	return out
end
db = {query = function(q) dbq[#dbq + 1] = q return true end}
local towns = {{getId = function() return 1 end}, {getId = function() return 2 end}}
Game.getTowns = function() return towns end
dofile("data/scripts/chaos/archery.lua")

local function archer()
	local pl = newPlayer()
	local bag = newItem(1988)
	pl.slots[CONST_SLOT_BACKPACK] = bag
	bag:addInner(newItem(2544, 100))
	local inner = bag:addInner(newItem(1988))
	inner:addInner(newItem(2543, 30))
	inner:addInner(newItem(2400))
	pl.slots[CONST_SLOT_AMMO] = newItem(18304, 50) -- crystalline arrows still in the ammunition slot
	local depot = newItem(1988)
	depot:addInner(newItem(29492, 10))
	local inbox = newItem(1988)
	inbox:addInner(newItem(99001, 4))
	pl.getDepotChest = function(self, town) return town == 2 and depot or nil end
	pl.getInbox = function() return inbox end
	return pl, bag, depot, inbox
end
local pl, bag, depot, inbox = archer()
stashRows = {{2544, 500}, {2400, 1}}
local n, g = A.sweep(pl)
eq(n, 100 + 30 + 50 + 10 + 4 + 500, "every arrow and bolt found (inventory, nested bags, slot, depot, inbox, stash)")
eq(g, 100 + 30 + 500 + 110 + 4 + 500, "the refund")
eq(pl.bank, g, "paid to the bank")
eq(pl.storage[A_CFG.storage], 1, "the sweep is marked done")
eq(pl.storage[A_CFG.storage + 1], 1, "the stash part too")
eq(#bag:getItems(true), 2, "the bag keeps the inner bag and the sword")
ok(pl.slots[CONST_SLOT_AMMO].removed, "the ammunition slot is empty")
eq(#depot:getItems(true), 0, "depot swept")
eq(#inbox:getItems(true), 0, "inbox swept")
eq(saves, 2, "saved after the items and before the stash rows go")
eq(#dbq, 1, "one stash row deleted")
ok(dbq[1]:find("item_id` = 2544", 1, true) ~= nil, "the arrows' row")
eq(#pl.msgs, 1, "one message")
local bankBefore = pl.bank
local n2 = A.sweep(pl)
eq(n2, 0, "a second login finds nothing")
eq(pl.bank, bankBefore, "and pays nothing")
eq(#dbq, 1, "no stash query again")
-- a later login: a script gave arrows again; the inventory is looked at, no save needed
bag:addInner(newItem(2544, 3))
eq((A.sweep(pl)), 3, "later arrivals in the inventory")
eq(pl.bank, bankBefore + 3, "refunded")

-- a failed save before the stash rows: refund and mark taken back, rows kept for the next login
local pl2 = archer()
stashRows = {{2543, 40}}
dbq = {}
saveOk = false
A.sweepItems(pl2)
eq(pl2.storage[A_CFG.storage], 1, "the item part stays done in memory (the logout save keeps it)")
local bank2 = pl2.bank
local sp, sg, sdone = A.sweepStash(pl2)
eq(sdone, false, "stash not done")
eq(pl2.bank, bank2, "its refund taken back")
eq(pl2.storage[A_CFG.storage + 1], -1, "its mark taken back")
eq(#dbq, 0, "no row deleted")
saveOk = true
sp, sg, sdone = A.sweepStash(pl2)
eq(sdone and sp, 40, "the next try sweeps the stash")
eq(pl2.bank, bank2 + 40, "and pays once")
eq(#dbq, 1, "and deletes the row")

-- a character with nothing to sweep (made after the update): both marks set, no save (a login rush on a busy disk)
local fresh = newPlayer()
fresh.getDepotChest = function() return nil end
fresh.getInbox = function() return newItem(1988) end
stashRows = {}
saves, dbq = 0, {}
local fn, fg = A.sweep(fresh)
eq(fn, 0, "nothing swept")
eq(fg, 0, "nothing paid")
eq(saves, 0, "no save at the first login of a fresh character")
eq(fresh.storage[A_CFG.storage], 1, "the item sweep is marked done (saved with the character later)")
eq(fresh.storage[A_CFG.storage + 1], 1, "the stash part too")
eq(#dbq, 0, "no stash query")
eq(#fresh.msgs, 0, "no message")
-- arrows but no stash rows: one save (the items), none for the empty stash
local onlyBag = newPlayer()
onlyBag.getDepotChest = function() return nil end
onlyBag.getInbox = function() return newItem(1988) end
local bag3 = newItem(1988)
onlyBag.slots[CONST_SLOT_BACKPACK] = bag3
bag3:addInner(newItem(2544, 7))
saves = 0
eq((A.sweep(onlyBag)), 7, "the arrows are swept")
eq(saves, 1, "one save: the items; an empty stash needs none")
eq(onlyBag.storage[A_CFG.storage + 1], 1, "the empty stash is marked done")

-- the hands at login (A.checkHands): the mock engine refuses what Player::queryAdd (0023) refuses
function Item:clone()
	local c = newItem(self.id, self.count)
	for k, v in pairs(self.attrs) do c.attrs[k] = v end
	for k, v in pairs(self.custom) do c.custom[k] = v end
	return c
end
function Item:moveTo(target)
	if target.full then
		return false
	end
	self.moved = true -- out of its slot (the mock player's getSlotItem skips it)
	target:addInner(self)
	return true
end
local function handsPlayer(left, right, ammo, opts)
	opts = opts or {}
	local pl = newPlayer()
	local getSlot = pl.getSlotItem
	pl.getSlotItem = function(self, s)
		local it = getSlot(self, s)
		return it and not it.moved and it or nil
	end
	pl.slots[CONST_SLOT_LEFT], pl.slots[CONST_SLOT_RIGHT], pl.slots[CONST_SLOT_AMMO] = left, right, ammo
	local bp = newItem(1988)
	bp.full = opts.bagFull
	pl.slots[CONST_SLOT_BACKPACK] = bp
	local inbox = newItem(1988)
	pl.getInbox = function() return inbox end
	local store = newItem(1988) -- the store inbox ("Purse")
	store.full = opts.storeFull
	pl.getStoreInbox = function() return store end
	pl.addItemEx = function(self, item, _, slot)
		if not A.slotAllowed(slot, A.handKind(ItemType(item:getId()))) or self:getSlotItem(slot) or opts.refuseOff then
			return 1
		end
		local function kind(s)
			local it = self:getSlotItem(s)
			return it and A.handKind(ItemType(it:getId())) or nil
		end
		local main, off = kind(CONST_SLOT_LEFT), kind(CONST_SLOT_RIGHT)
		local k = A.handKind(ItemType(item:getId()))
		if slot == CONST_SLOT_RIGHT then off = k else main = k end
		if not A.handsAllowed(main, off) then
			return 1
		end
		self.slots[slot] = item
		return RETURNVALUE_NOERROR
	end
	return pl, bp, inbox, store
end
local function rolledQuiver()
	local q = newItem(QUIVER)
	q.custom.chaos_iid = "123456"
	q.attrs[ITEM_ATTRIBUTE_ATTACK] = 0
	return q
end
saves = 0
-- a bow and a quiver of before in the ammunition slot: the quiver moves to the off-hand, keeps its rolls, saved
local oldQ = rolledQuiver()
local ph, bpH, inboxH = handsPlayer(newItem(2456), nil, oldQ)
eq(A.checkHands(ph), 1, "one item moved")
local nowQ = ph:getSlotItem(CONST_SLOT_RIGHT)
ok(nowQ and nowQ.id == QUIVER and nowQ ~= oldQ, "the quiver is in the off-hand")
eq(nowQ and nowQ.custom.chaos_iid, "123456", "with its rolls (one item, moved)")
ok(oldQ.removed, "the old one is gone")
eq(ph:getSlotItem(CONST_SLOT_AMMO), nil, "the ammunition slot is empty")
eq(saves, 1, "saved at once")
ok(ph.msgs[1] and ph.msgs[1]:find("your off-hand", 1, true) ~= nil, "the player is told")
eq(A.checkHands(ph), 0, "a second login: nothing to do")
eq(saves, 1, "and no save")
-- the off-hand is taken by a shield (a sword in the hand): the quiver goes to the store inbox (the ammunition slot
-- is drawn by no client; never the backpack: the hidden slots all empty into the Purse)
local q2 = rolledQuiver()
local ps, _, _, storeS = handsPlayer(newItem(2400), newItem(2520), q2)
eq(A.checkHands(ps), 1, "moved")
ok(q2.moved and storeS:getItems()[1] == q2, "into the store inbox")
ok(ps.msgs[1]:find("your Purse", 1, true) ~= nil, "the message names the Purse")
eq(ps:getSlotItem(CONST_SLOT_RIGHT).id, 2520, "the shield stays")
-- the store inbox refuses it: the depot inbox
local q3 = rolledQuiver()
local pf, _, inboxF = handsPlayer(newItem(2400), nil, q3, {storeFull = true})
eq(A.checkHands(pf), 1, "moved")
ok(inboxF:getItems()[1] == q3, "into the inbox")
ok(pf.msgs[1]:find("your inbox", 1, true) ~= nil, "the message names the inbox")
-- the engine refuses the off-hand (a vocation or level of movements.xml): stowed instead
local q4 = rolledQuiver()
local pr, _, _, storeR = handsPlayer(newItem(2456), nil, q4, {refuseOff = true})
eq(A.checkHands(pr), 1, "moved")
ok(storeR:getItems()[1] == q4 and not q4.removed, "the quiver kept, in the store inbox")
eq(pr:getSlotItem(CONST_SLOT_RIGHT), nil, "the off-hand stays empty")
-- something else left in the ammunition slot (a torch): the backpack
local torch2 = newItem(2050)
local pt, _, _, bpT = handsPlayer(newItem(2456), nil, torch2)
eq(A.checkHands(pt), 1, "moved")
ok(bpT:getItems()[1] == torch2, "the torch into the store inbox")
-- a ring in the old second ring slot (engine patch 0058): to the backpack, saved, the player told; once
local ring2 = newItem(2357)
local pring, _, _, bpRing = handsPlayer(newItem(2456), rolledQuiver(), ring2)
saves = 0
eq(A.checkHands(pring), 1, "a ring in the ammunition slot: moved")
ok(bpRing:getItems()[1] == ring2 and not ring2.removed, "the ring is in the store inbox, kept")
eq(pring:getSlotItem(CONST_SLOT_AMMO), nil, "the ammunition slot is empty")
eq(saves, 1, "saved at once")
eq(#pring.msgs, 1, "one message")
ok(pring.msgs[1]:find("The second ring slot is gone: the badge slot took its place.", 1, true) == 1
	and pring.msgs[1]:find("-> your Purse", 1, true) ~= nil, "the player is told why: " .. tostring(pring.msgs[1]))
eq(A.checkHands(pring), 0, "a second login: nothing to do")
eq(saves, 1, "and no save")
-- bow + quiver already right: nothing; a quiver beside a sword: stowed
local pk = handsPlayer(newItem(2456), rolledQuiver(), nil)
eq(A.checkHands(pk), 0, "bow + quiver in the off-hand: nothing to do")
local qw = rolledQuiver()
local pw, bpW = handsPlayer(newItem(2400), qw, nil)
eq(A.checkHands(pw), 1, "a quiver beside a sword is moved")
ok(bpW:getItems()[1] == qw, "to the backpack")
-- two might rings worn from before: the one in the ammunition slot goes, the ring slot's stays
local might9, might10 = newItem(2164), newItem(2164)
local pm, _, _, bpM = handsPlayer(nil, nil, might10)
pm.slots[CONST_SLOT_RING] = might9
saves = 0
eq(A.checkHands(pm), 1, "two might rings: one moved")
ok(bpM:getItems()[1] == might10 and not might10.removed, "the ammunition slot's might ring is in the store inbox")
ok(pm:getSlotItem(CONST_SLOT_RING) == might9 and not might9.moved, "the ring slot's might ring stays")
eq(pm:getSlotItem(CONST_SLOT_AMMO), nil, "the ammunition slot is empty")
eq(saves, 1, "saved at once")
-- the backpack is full: the inbox
local mightF = newItem(2164)
local pmf, _, inboxMF = handsPlayer(nil, nil, mightF, {storeFull = true})
pmf.slots[CONST_SLOT_RING] = newItem(2164)
eq(A.checkHands(pmf), 1, "moved")
ok(inboxMF:getItems()[1] == mightF, "into the inbox")
-- a ring in the ring slot alone: nothing moves
local pmr = handsPlayer(nil, nil, nil)
pmr.slots[CONST_SLOT_RING] = newItem(2164)
saves = 0
eq(A.checkHands(pmr), 0, "a ring in the ring slot: nothing to do")
eq(saves, 0, "no save")
-- the quiver message alone when only a quiver moved
local pqm = handsPlayer(newItem(2456), nil, rolledQuiver())
eq(A.checkHands(pqm), 1, "a quiver of before moved")
eq(#pqm.msgs, 1, "only the quiver message")
ok(pqm.msgs[1]:find("ring", 1, true) == nil, "no ring text")
-- the login event runs the check before the sweep
local pe = handsPlayer(newItem(29875), nil, rolledQuiver())
pe.getDepotChest = function() return nil end
events.ChaosArcheryLogin.onLogin(pe)
eq(pe:getSlotItem(CONST_SLOT_RIGHT) and pe:getSlotItem(CONST_SLOT_RIGHT).id, QUIVER, "login: the quiver is in the off-hand")
eq(pe:getSlotItem(CONST_SLOT_AMMO), nil, "login: the ammunition slot is empty")

-- the quiver's Distance Fighting condition and Attack Speed with Bows
local pa = newPlayer()
local bow = newItem(2456)
pa.slots[CONST_SLOT_LEFT] = bow
A.apply(pa, {bowdistance = 0})
eq(pa.removed, 1, "the first refresh of a session clears a condition saved with the character")
eq(#pa.conditions, 0, "and adds none for 0")
A.apply(pa, {bowdistance = 3, bowspeed = 5})
eq(#pa.conditions, 1, "one condition")
eq(pa.conditions[1].params[CONDITION_PARAM_SKILL_DISTANCE], 3, "Distance Fighting +3")
eq(pa.conditions[1].params[CONDITION_PARAM_SUBID], A_CFG.effects.conditionSubId, "its own sub id")
eq(bow:getCustomAttribute(M.QUIVER_SPEED), 5, "the speed on the bow")
eq(bow.attrs[ITEM_ATTRIBUTE_ATTACK_SPEED], math.floor(M.config.defaultAttackSpeed * 0.95), "a faster interval")
A.apply(pa, {bowdistance = 3, bowspeed = 5})
eq(#pa.conditions, 1, "unchanged totals: no new condition")
A.apply(pa, {bowdistance = 0, bowspeed = 0})
eq(#pa.conditions, 1, "zero: the condition goes, none added")
eq(bow:getCustomAttribute(M.QUIVER_SPEED), nil, "the speed comes off")
eq(bow.attrs[ITEM_ATTRIBUTE_ATTACK_SPEED], nil, "the interval is the bow's own again")
-- the bow leaves the hands: the quiver's speed comes off the bow
A.apply(pa, {bowspeed = 4})
callbacks.onItemMoved(pa, bow, 1, {x = CONTAINER_POSITION, y = CONST_SLOT_LEFT, z = 0}, {x = CONTAINER_POSITION, y = 64, z = 0})
eq(bow:getCustomAttribute(M.QUIVER_SPEED), nil, "unequipped bow: no quiver speed")

-- old launchers: the attack of before gets its band, the hit chance attribute goes; a new roll stays
local old = newItem(27471)
old.attrs[ITEM_ATTRIBUTE_ATTACK] = 12
old.attrs[ITEM_ATTRIBUTE_HITCHANCE] = 8
ok(A.migrate(old), "an old sanguine bow changes")
eq(old.attrs[ITEM_ATTRIBUTE_ATTACK], 77, "12 + 65")
eq(old.attrs[ITEM_ATTRIBUTE_HITCHANCE], nil, "hit chance attribute gone")
ok(not A.migrate(old), "once")
local fresh = newItem(27471)
fresh.attrs[ITEM_ATTRIBUTE_ATTACK] = 77
ok(not A.migrate(fresh), "a roll of after the patch stays")
TYPES[27471].ammoType = AMMO_ARROW -- a base server without the install tool
local unpatched = newItem(27471)
unpatched.attrs[ITEM_ATTRIBUTE_ATTACK] = 12
ok(not A.migrate(unpatched), "nothing changes on an unpatched server")
TYPES[27471].ammoType = AMMO_NONE
-- moved into the hands: migrated; ammunition moved into the inventory: refunded
local moving = newItem(27471)
moving.attrs[ITEM_ATTRIBUTE_ATTACK] = 10
callbacks.onItemMoved(pa, moving, 1, {x = 100, y = 100, z = 7}, {x = CONTAINER_POSITION, y = CONST_SLOT_LEFT, z = 0})
eq(moving.attrs[ITEM_ATTRIBUTE_ATTACK], 75, "a bow taken into the hand is migrated")
local found = newItem(2543, 25)
local bankA = pa.bank
callbacks.onItemMoved(pa, found, 25, {x = 100, y = 100, z = 7}, {x = CONTAINER_POSITION, y = 70, z = 0})
ok(found.removed, "bolts picked up are taken")
eq(pa.bank, bankA + 25, "and paid back")

-- ---------------------------------------------------------------- 6. weapon_styles.lua: the hit without ammunition
local styleEvents, timers, area, dealt, fx = {}, {}, {}, {}, {}
CreatureEvent = function(name)
	local o = {}
	o.register = function() styleEvents[name] = o end
	return o
end
EventCallback = setmetatable({}, {__newindex = function(t, k, v) end, __index = function(t, k)
	if k == "register" then return function() end end end})
createCombatArea = function(t) return t end
addEvent = function(fn, ms, ...) timers[#timers + 1] = {fn, {...}} end
doAreaCombat = function(a, ctype, pos, ar, min) area[#area + 1] = {type = ctype, amount = min} end
doTargetCombatHealth = function(a, target, ctype, min) dealt[#dealt + 1] = {target = target, amount = min} end
ChaosCombatFx = {crit = function() fx.crit = (fx.crit or 0) + 1 end}
ChaosItemModsCache = {}
local creatures = {}
Creature = function(id) return creatures[id] end
local function mkCreature(id, kind, x)
	local c = {id = id, kind = kind, x = x, health = 1000}
	function c:getId() return self.id end
	function c:isPlayer() return self.kind == "player" end
	function c:isMonster() return self.kind == "monster" end
	function c:getName() return "Mob" end
	function c:getHealth() return self.health end
	function c:getMaster() return nil end
	function c:getType() return {getElementList = function() return {[COMBAT_FIREDAMAGE] = 50} end} end
	function c:getPosition()
		return {x = self.x, y = 100, z = 7, sendMagicEffect = function() end, sendDistanceEffect = function() end}
	end
	creatures[id] = c
	return c
end
Game.getSpectators = function()
	local out = {}
	for _, c in pairs(creatures) do
		out[#out + 1] = c
	end
	return out
end
dofile("data/scripts/chaos/weapon_styles.lua")
local hitEv = styleEvents.ChaosWeaponStyle
local shooter = mkCreature(1, "player", 90)
shooter.slots = {}
function shooter:getSlotItem(s) return self.slots[s] end
function shooter:getLevel() return 100 end -- the style factor is a function of the level (weapon_balance_core.lua)
-- the factor of a launcher style at level 100, as the hit is scaled (rounded to a whole number)
local W = ChaosWeaponBalance
local function styled(n, style) return math.floor(n * W.factor(style, 100) + 0.5) end
local mob = mkCreature(2, "monster", 100)
local mob2 = mkCreature(3, "monster", 102)
local function runTimers()
	local list = timers
	timers = {}
	for _, t in ipairs(list) do
		local unpackf = unpack or table.unpack
		t[1](unpackf(t[2]))
	end
end
local cache = {}
ChaosItemMods.playerBonus = function(pl, key) return cache[key] or 0 end
-- a crossbow: its style factor (weapon_balance_config.lua), no splash, no quiver
shooter.slots[CONST_SLOT_LEFT] = newItem(29875)
math.random = function(a, b) return b or a end -- every roll fails (the highest number)
local d = hitEv.onHealthChange(mob, shooter, -100, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, ORIGIN_RANGED)
eq(d, -styled(100, "crossbow"), "crossbow: its style factor, no ammunition needed")
ok(styled(100, "crossbow") > 0 and styled(100, "bow") > 0, "the launcher factors are set")
runTimers()
eq(#area, 0, "crossbow: no splash")
-- a bow: splash
shooter.slots[CONST_SLOT_LEFT] = newItem(2456)
hitEv.onHealthChange(mob, shooter, -100, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, ORIGIN_RANGED)
runTimers()
eq(#area, 1, "bow: splash")
eq(area[1].amount, -math.floor(styled(100, "bow") * 0.5), "half of the hit")
-- the quiver: critical strike, element share against the resistance, extra projectile at the other monster
math.random = function(a, b) return a end -- every roll succeeds
cache = {bowcrit = 10, multishot = 20}
ChaosItemModsCache[shooter:getId()] = {arrowfire = 20}
area = {}
local pd, pt, sd, st = hitEv.onHealthChange(mob, shooter, -100, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, ORIGIN_RANGED)
eq(pd, -(math.floor(styled(100, "bow") * 3 / 2)), "the style factor, then a +50% critical strike")
eq(st, COMBAT_FIREDAMAGE, "fire share")
eq(sd, -math.floor(math.floor(styled(100, "bow") * 3 / 2) * 20 / 100 * 0.5), "20% of the hit against 50% fire resistance")
eq(fx.crit, 1, "the crit shows")
runTimers()
eq(#dealt, 1, "one extra projectile")
eq(dealt[1].target, mob2, "at the other monster")
eq(dealt[1].amount, -math.floor((math.floor(styled(100, "bow") * 3 / 2) + -sd) * A_CFG.effects.multishotShare / 100), "60% of the hit")
eq(#area, 1, "and the bow's splash")
-- another type shown under the same name (a rift name): its own resistance, not the cached one of the first "Mob"
local wisp = mkCreature(4, "monster", 140)
function wisp:getType()
	return {name = function() return "Ember Wisp" end, getElementList = function() return {[COMBAT_FIREDAMAGE] = 0} end}
end
local _, _, wsd = hitEv.onHealthChange(wisp, shooter, -100, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, ORIGIN_RANGED)
eq(wsd, -math.floor(math.floor(styled(100, "bow") * 3 / 2) * 20 / 100), "same shown name, other type: 20% of the hit against 0% fire resistance")
creatures[4] = nil
timers, area, dealt = {}, {}, {}
-- melee and spells are not touched by the quiver
cache = {bowcrit = 100}
eq((hitEv.onHealthChange(mob, shooter, -100, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, ORIGIN_SPELL)), -100, "spells untouched")

-- ---------------------------------------------------------------- 7. loot and the SQL
MAX_LOOTCHANCE = 100000
EventCallback = setmetatable({register = function() end}, {__newindex = rawset})
dofile("data/scripts/chaos/loot.lua")
ok(ChaosLoot.isGearId(QUIVER), "a quiver is a gear drop")
ok(not ChaosLoot.isGearId(2544), "an arrow is none")
local sql = io.open("sql/chaos_archery.sql"):read("*a")
local ids = {}
for list in sql:gmatch("IN %(([%d, ]+)%)") do
	local n2 = 0
	for id in list:gmatch("%d+") do
		ids[tonumber(id)] = true
		n2 = n2 + 1
	end
	local want = 0
	for _ in pairs(A_CFG.quivers) do want = want + 1 end
	eq(n2, want, "the SQL lists every quiver")
end
for id in pairs(A_CFG.quivers) do
	ok(ids[id], "the SQL names quiver " .. id)
end

print(string.format("archery_test: %d checks, %d failures", checks, fails))
if fails > 0 then
	os.exit(1)
end
