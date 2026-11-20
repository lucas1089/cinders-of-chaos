-- Run from the server/ folder: luajit tests/weapon_element_attack_test.lua && lua5.3 tests/weapon_element_attack_test.lua (no engine needed; CI runs both)
-- O679: the attack a melee weapon spell reads. Before, a spell read the physical attack of the weapon only (skill x max(20, attack)); the
-- engine's auto attack and the tooltip's Estimated DPS count the element damage of the weapon too (Weapon::getElementDamage rolls it like
-- the physical hit with the element value as its attack). The equipment sets give 35% of their tier as element and the stock weapons of the
-- levels 600 to 999 carry mostly element, so a level 813 Juggernaut cast at 0.64 of the model with the best weapon of its level (live,
-- server/README.md "Weapon element in the spell attack (O679)"). This test holds:
--   * spell_scaling_core.lua S.spellAttack: the share of the config, no config, bad numbers
--   * ChaosSpell.meleeAttack of data/spells/chaos/_common.lua (cut out of the library, it needs a whole engine to load) against mocked
--     players: the real numbers of the live runs (sanguine hatchet 13 + fire 73, Azure Vigil blade 71 + 39), a shield, no weapon, a rolled
--     attack attribute, the switch at 0, a wand
--   * the numbers of the config against the physical rule of the weapon audit (tools/weapon_coverage_config.lua)
local checks, fails = 0, 0
local function ok(c, m)
	checks = checks + 1
	if not c then
		fails = fails + 1
		print("FAIL " .. (m or ""))
	end
end
local function eq(a, b, m)
	ok(a == b, (m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end

dofile("data/scripts/chaos/spell_scaling_config.lua")
dofile("data/scripts/chaos/spell_scaling_core.lua")
local S, cfg = ChaosSpellScaling, ChaosSpellScalingConfig

-- ------------------------------------------------------------------ the core
eq(cfg.weaponElement, 1, "the whole element damage joins the attack (the engine's own rule for the auto attack)")
eq(S.spellAttack(13, 73), 86, "sanguine hatchet: attack 13 + fire 73")
eq(S.spellAttack(71, 39), 110, "Azure Vigil blade: attack 71 + element 39")
eq(S.spellAttack(157, 0), 157, "a weapon with no element: its attack")
eq(S.spellAttack(0, 62), 62, "an amber weapon: attack 0, only element")
eq(S.spellAttack(nil, nil), 0, "no numbers: 0")
eq(S.spellAttack(-5, -7), 0, "no negative attack or element")
eq(S.spellAttack("40", "10"), 50, "numbers as text")
eq(S.spellAttack(13, 73, {weaponElement = 0}), 13, "share 0: the physical attack alone (the rule before O679)")
eq(S.spellAttack(60, 40, {weaponElement = 0.5}), 80, "share 0.5: half of the element")
eq(S.spellAttack(60, 40, {}), 60, "a config with no weaponElement: the physical attack alone")
-- no config at all (the table is not loaded): the physical attack alone
do
	local saved = ChaosSpellScalingConfig
	ChaosSpellScalingConfig = nil
	eq(S.spellAttack(13, 73), 13, "no config table: the physical attack alone")
	ChaosSpellScalingConfig = saved
end

-- ------------------------------------------------------------------ ChaosSpell.meleeAttack cut out of _common.lua
CONST_SLOT_LEFT, CONST_SLOT_RIGHT = 6, 5
WEAPON_NONE, WEAPON_SWORD, WEAPON_CLUB, WEAPON_AXE, WEAPON_SHIELD, WEAPON_DISTANCE, WEAPON_WAND = 0, 1, 2, 3, 4, 5, 6
ITEM_ATTRIBUTE_ATTACK = 20

-- the item types of the live runs (items.xml after install_all.py)
local TYPES = {
	[27462] = {name = "sanguine hatchet", wt = WEAPON_AXE, attack = 13, element = 73},
	[37219] = {name = "azure vigil blade", wt = WEAPON_SWORD, attack = 71, element = 39},
	[29558] = {name = "Deathlord Blade", wt = WEAPON_SWORD, attack = 85, element = 0},
	[29883] = {name = "Dawnforged Blade", wt = WEAPON_SWORD, attack = 157, element = 0},
	[2400] = {name = "stock mace", wt = WEAPON_CLUB, attack = 24, element = 0},
	[37211] = {name = "azure vigil shield", wt = WEAPON_SHIELD, attack = 0, element = 0},
	[2190] = {name = "wand", wt = WEAPON_WAND, attack = 0, element = 0},
	[44999] = {name = "amber bludgeon", wt = WEAPON_CLUB, attack = 0, element = 58},
}
function ItemType(id)
	local t = TYPES[id]
	return {
		getWeaponType = function() return t.wt end,
		getAttack = function() return t.attack end,
		getElementDamage = function() return t.element end,
	}
end
local function item(id, rolledAttack)
	return {
		getId = function() return id end,
		getAttribute = function(_, key) return key == ITEM_ATTRIBUTE_ATTACK and rolledAttack or nil end,
	}
end
local function player(left, right)
	return {getSlotItem = function(_, slot) if slot == CONST_SLOT_LEFT then return left end return right end}
end

ChaosSpell = {}
do
	local f = assert(io.open("data/spells/chaos/_common.lua", "r"))
	local source = f:read("*a")
	f:close()
	local a1 = source:find("local function itemAttack(item)", 1, true)
	local a2 = source:find("function ChaosSpell.distanceAttack", 1, true)
	local b1 = source:find("function ChaosSpell.meleeAttack", 1, true)
	local b2 = source:find("-- skill x attack of a Thief-line weapon strike", 1, true)
	assert(a1 and a2 and a2 > a1 and b1 and b2 and b2 > b1, "itemAttack and meleeAttack are in _common.lua")
	assert(load(source:sub(a1, a2 - 1) .. "\n" .. source:sub(b1, b2 - 1)))()
end
local atk = ChaosSpell.meleeAttack

eq(atk(player(item(27462), nil)), 86, "sanguine hatchet in the hand: 13 + 73, not the floor of 20 (live: a level 817 Juggernaut cast with 20)")
eq(atk(player(item(37219), nil)), 110, "Azure Vigil blade: 71 + 39 (the tier of level 800 is 111)")
eq(atk(player(item(29558), nil)), 85, "a weapon with no element: its attack")
eq(atk(player(item(29883), nil)), 157, "Dawnforged blade: 157")
eq(atk(player(item(2400), nil)), 24, "a stock mace: 24")
eq(atk(player(item(44999), nil)), 58, "an amber weapon (attack 0, element 58) reads its element, not the floor of 20")
eq(atk(player(item(37211), item(37219))), 110, "a shield in the left hand: the weapon in the right is read")
eq(atk(player(item(37219), item(37211))), 110, "a shield in the right hand: the weapon in the left")
eq(atk(player(nil, nil)), 20, "an empty hand: 20 (no archetype module in this test)")
eq(atk(player(item(2190), nil)), 20, "a wand is no melee weapon: 20")
eq(atk(player(item(37219, 60), nil)), 99, "a rolled attack attribute wins over the type's attack, the element of the type is added")
eq(atk(player(item(27462, 0), nil)), 86, "a rolled attack of 0 falls back to the type's attack")

-- the switch: share 0 is the rule before O679
do
	local saved = ChaosSpellScalingConfig.weaponElement
	ChaosSpellScalingConfig.weaponElement = 0
	eq(atk(player(item(27462), nil)), 20, "share 0: the hatchet reads 13, floored to 20")
	eq(atk(player(item(37219), nil)), 71, "share 0: the Azure Vigil blade reads its 71")
	ChaosSpellScalingConfig.weaponElement = saved
end
-- no scaling library loaded (a spell state that never loaded it): the physical attack
do
	local saved = ChaosSpellScaling
	ChaosSpellScaling = nil
	eq(atk(player(item(37219), nil)), 71, "no scaling library: the physical attack")
	ChaosSpellScaling = saved
end

-- an item type without getElementDamage (an older engine): the physical attack, no error
do
	local saved = ItemType
	ItemType = function(id)
		local t = TYPES[id]
		return {getWeaponType = function() return t.wt end, getAttack = function() return t.attack end}
	end
	eq(atk(player(item(37219), nil)), 71, "an engine with no getElementDamage: the physical attack")
	ItemType = saved
end

-- the plan: a set weapon of level 813 reads about the tier (the model's typical attack), which the physical part alone did not
do
	local tier = 111          -- install_gear_sets.py WEAPON_CURVES 'melee' between 700 (94) and 850 (118) at level 813
	local physical = atk(player(item(37219), nil)) - 39
	ok(physical / tier < 0.66, "the physical part alone was 0.64 of the tier")
	ok(atk(player(item(37219), nil)) / tier > 0.98, "with the element the weapon reads the tier")
end

print(string.format("weapon_element_attack_test: %d checks, %d failed", checks, fails))
os.exit(fails == 0 and 0 or 1)
