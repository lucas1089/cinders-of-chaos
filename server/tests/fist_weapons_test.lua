-- Run from the server/ folder: luajit tests/fist_weapons_test.lua (no engine needed; CI runs it with luajit and lua5.3)
-- The Monk line's fist weapons and the Necromancer bone effects: the ids the Monk code uses match the generated item
-- data, each tier beats bare fists at its level (and the damage factor follows the weapon), the loot rows reach the
-- monster types once (mocked MonsterType / ItemType / Loot), the item modifiers treat a fist weapon as a weapon, the
-- legendary unique is wired, and chaos_vfx_art.lua adds the bone effects without dropping the pack effects.
dofile("data/scripts/chaos/chaos_constants.lua")
dofile("data/scripts/chaos/classes.lua")
dofile("data/scripts/chaos/monk_chi_core.lua")
dofile("data/lib/chaos_fist_weapons.lua")
local M, F = ChaosMonk, ChaosFistWeapons

local function eq(a, b, m) if a ~= b then error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2) end end

-- ------------------------------------------------------------------ ids: the Monk code and the item data agree
local ids = M.cfg.unarmed.fistWeapons
eq(#ids, #F.ids, "same count")
for i, id in ipairs(F.ids) do
	eq(ids[i], id, "fistWeapons[" .. i .. "]")
	eq(F.items[id] ~= nil, true, "item data for " .. id)
end

-- ------------------------------------------------------------------ each tier is worth wearing at its level
local lastLevel, lastAttack = 0, 0
for _, id in ipairs(F.ids) do
	local it = F.items[id]
	eq(it.level > lastLevel, true, it.name .. ": levels rise")
	eq(it.attack > lastAttack, true, it.name .. ": attack rises")
	lastLevel, lastAttack = it.level, it.attack
	local bare = M.fistAttack(it.level)
	eq(it.attack > bare, true, it.name .. " beats bare fists at level " .. it.level)
	eq(M.fistAttack(it.level, it.attack), it.attack, it.name .. ": the weapon's attack counts")
	-- the gain at its own level is modest (at most +10% damage over bare fists): the balance was measured unarmed
	local fac = M.unarmedFactor(17, it.level, 100, it.attack, 1) / M.unarmedFactor(17, it.level, 100, 0, 1)
	eq(fac > 1 and fac <= 1.10, true, it.name .. ": damage gain " .. fac)
end
-- the legendary is the only one above the bare-fist cap (attackMax 60, level 800+)
eq(F.items[36659].attack > M.cfg.unarmed.attackMax, true, "the unique tops the cap")
eq(F.items[36658].attack < M.cfg.unarmed.attackMax, true, "tier 5 is passed by bare fists at level 800")
-- a fist weapon raises the spell strikes' fist power too
eq(M.fistPower(300, 110, 50) > M.fistPower(300, 110, 0), true, "fist power")

-- ------------------------------------------------------------------ loot rows added once (mocked engine)
local types, added = {["monk"] = {}, ["dark monk"] = {}}, {}
function MonsterType(name)
	local t = types[name:lower()]
	if not t then return nil end
	return {addLoot = function(_, loot) added[#added + 1] = {name, loot.id, loot.chance, loot.max}; return true end}
end
function ItemType(id) return {getId = function() return id end} end
function Loot()
	local l = {}
	function l:setId(v) self.id = v end
	function l:setChance(v) self.chance = v end
	function l:setMaxCount(v) self.max = v end
	return l
end
GlobalEvent = function() return {register = function() end} end
local printed = print
print = function() end
dofile("data/scripts/chaos/fist_weapons.lua")
local a, s = ChaosFistLoot.addAll({{"Monk", 36654, 900}, {"Dark Monk", 36654, 700}, {"Nobody", 36654, 5}})
print = printed
eq(a, 2, "two rows added"); eq(s, 1, "a missing monster is skipped")
eq(added[1][1], "Monk"); eq(added[1][2], 36654); eq(added[1][3], 900); eq(added[1][4], 1)
eq(select(1, ChaosFistLoot.addAll()), 0, "only once per server run")
for _, row in ipairs(F.loot) do
	local id = row[2]
	eq(F.items[id] ~= nil and F.items[id].unique == nil, true, "loot of a plain tier: " .. row[1])
	eq(row[3] > 0 and row[3] <= 1000, true, "chance per 100000")
end

-- ------------------------------------------------------------------ item modifiers: a fist weapon rolls weapon mods
dofile("data/lib/chaos_item_mods.lua")
local function itype(wt, attack, slots)
	return {getWeaponType = function() return wt end, getAttack = function() return attack end,
		getSlotPosition = function() return slots or 48 end}
end
local SHIELD = WEAPON_SHIELD or 4
eq(ChaosItemMods.kindOfType(itype(SHIELD, 50)), "weapon", "a shield with an attack is a fist weapon")
eq(ChaosItemMods.kindOfType(itype(SHIELD, 0)), "shield", "a plain shield")

-- ------------------------------------------------------------------ the legendary unique
ITEM_ATTRIBUTE_ATTACK, ITEM_ATTRIBUTE_DEFENSE, ITEM_ATTRIBUTE_EXTRADEFENSE = ITEM_ATTRIBUTE_ATTACK or 1, ITEM_ATTRIBUTE_DEFENSE or 2, ITEM_ATTRIBUTE_EXTRADEFENSE or 3
ITEM_ATTRIBUTE_ARMOR, ITEM_ATTRIBUTE_HITCHANCE, ITEM_ATTRIBUTE_SHOOTRANGE = ITEM_ATTRIBUTE_ARMOR or 4, ITEM_ATTRIBUTE_HITCHANCE or 5, ITEM_ATTRIBUTE_SHOOTRANGE or 6
dofile("data/lib/chaos_unique_items.lua")
dofile("data/lib/chaos_unique_specs.lua")
local u
for _, e in ipairs(ChaosUniqueItems) do
	if e.id == 36659 then u = e end
end
eq(u ~= nil, true, "Grasp of the Pyre Saint is a unique")
eq(u.minTier, "legendary"); eq(u.level, F.items[36659].level, "same level")
eq(ChaosUniqueSpecs[36659].name, u.name, "spec name")
eq(ChaosUniqueSpecs[36659].custom.rarity_fistSkill, 5, "fist skill as the rarity attribute")

-- ------------------------------------------------------------------ bone effects: merged, nothing dropped
ChaosVfx, ChaosVfxMissile = nil, nil
Position = function(x, y, z) return {x = x, y = y, z = z} end
dofile("data/lib/chaos_vfx.lua")
local before = 0
for _ in pairs(ChaosVfx) do before = before + 1 end
dofile("data/lib/chaos_vfx_art.lua")
local after = 0
for _ in pairs(ChaosVfx) do after = after + 1 end
eq(after, before + 3, "three effects added")
eq(ChaosVfx.necro_seal ~= nil, true, "pack effects kept")
local maxId = 0
for name, e in pairs(ChaosVfx) do
	if name:sub(1, 5) ~= "bone_" then maxId = math.max(maxId, e.id) end
end
for _, n in ipairs({"bone_spear", "bone_burst", "bone_aura"}) do
	eq(ChaosVfx[n].id > maxId, true, n .. " after the pack ids")
end
eq(ChaosVfxMissile.bone_spear ~= nil and ChaosVfxMissile.bone_spear.id <= 255, true, "missile id fits a byte")

print("fist_weapons_test: all ok")
