-- Run from the server/ folder: luajit tests/rarity_elements_test.lua (CI runs it with LuaJIT and Lua 5.3)
-- Several rarity elements on one character: data/scripts/chaos/rarity_elements.lua and the patch of the base script
-- customs/rarity/rarity_onCombat_elementdamage.lua (tools/patch_base_events.py step 9), mock engine.
local fails, checks = 0, 0
local function ok(cond, what)
	checks = checks + 1
	if not cond then
		fails = fails + 1
		print("FAIL " .. what)
	end
end
local function eq(a, b, what)
	ok(a == b, (what or "check") .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end

-- ---------------------------------------------------------------- mock engine
COMBAT_NONE, COMBAT_PHYSICALDAMAGE = 0, 1
COMBAT_ENERGYDAMAGE, COMBAT_EARTHDAMAGE, COMBAT_FIREDAMAGE = 2, 4, 8
COMBAT_ICEDAMAGE, COMBAT_HOLYDAMAGE, COMBAT_DEATHDAMAGE = 512, 1024, 2048
COMBAT_WATERDAMAGE, COMBAT_ARCANEDAMAGE = 4096, 8192
ORIGIN_NONE, ORIGIN_CONDITION, ORIGIN_SPELL, ORIGIN_MELEE, ORIGIN_RANGED = 0, 1, 2, 3, 4
CONST_ME_NONE, CONST_SLOT_RIGHT, CONST_SLOT_LEFT, RETURNVALUE_NOERROR = 255, 5, 6, 0

local events, combats, creatures = {}, {}, {}
function addEvent(fn, delay, ...)
	events[#events + 1] = {fn = fn, args = {...}}
end
local function runEvents()
	local list = events
	events = {}
	for _, e in ipairs(list) do
		e.fn((table.unpack or unpack)(e.args))
	end
end
function doTargetCombat(source, target, ctype, min, max, effect, origin)
	combats[#combats + 1] = {source = source, target = target, type = ctype, min = min, max = max, origin = origin}
	return true
end
function Creature(id)
	return creatures[id]
end

local function makePlayer(storages, weaponElement, weaponType)
	local p = {id = 100, storages = storages}
	function p:getId() return self.id end
	function p:isPlayer() return true end
	function p:getStorageValue(k) return self.storages[k] or -1 end
	function p:getSlotItem(slot)
		if slot ~= CONST_SLOT_RIGHT then
			return nil
		end
		return {getType = function()
			return {getElementDamage = function() return weaponElement or 0 end,
				getElementType = function() return weaponType or COMBAT_NONE end}
		end}
	end
	function p:getHealth() return 1000 end
	creatures[p.id] = p
	return p
end
local monster = {id = 200, health = 1000}
function monster:getId() return self.id end
function monster:isPlayer() return false end
function monster:getHealth() return self.health end
creatures[monster.id] = monster

dofile("data/scripts/chaos/rarity_elements.lua")
local R = ChaosRarityElements
local FIRE, ICE, HOLY = 977554, 977555, 977560

-- ---------------------------------------------------------------- pure parts
local shares = R.shares(0, COMBAT_NONE, {{type = COMBAT_FIREDAMAGE, percent = 10}, {type = COMBAT_ICEDAMAGE, percent = 20}})
eq(#shares, 2, "two rarity elements, two shares")
eq(shares[1].type, COMBAT_FIREDAMAGE, "fire first (base script order)")
shares = R.shares(5, COMBAT_FIREDAMAGE, {{type = COMBAT_FIREDAMAGE, percent = 10}, {type = COMBAT_ICEDAMAGE, percent = 20}})
eq(#shares, 2, "the weapon's element and the same rarity element add up")
eq(shares[1].percent, 15, "fire weapon 5% + fire rarity 10%")

-- 1330 physical, fire 10% (100) + ice 20% (200): the larger share inline, the other one an extra hit
local p, pt, s, st, extra = R.split(R.shares(0, COMBAT_NONE, {{type = COMBAT_FIREDAMAGE, percent = 10},
	{type = COMBAT_ICEDAMAGE, percent = 20}}), -1330, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE)
eq(p, -1330, "primary unchanged")
eq(pt, COMBAT_PHYSICALDAMAGE, "primary type unchanged")
eq(s, -200, "ice share inline")
eq(st, COMBAT_ICEDAMAGE, "secondary type: the largest share")
eq(#extra, 1, "one extra hit")
eq(extra[1].type, COMBAT_FIREDAMAGE, "the extra hit is fire")
eq(extra[1].damage, 100, "fire share 1330 * 10 / 133")

-- the hit already has a fire secondary (fire weapon): the fire share joins it, ice is extra
p, pt, s, st, extra = R.split(R.shares(0, COMBAT_NONE, {{type = COMBAT_FIREDAMAGE, percent = 10},
	{type = COMBAT_ICEDAMAGE, percent = 20}}), -1330, COMBAT_PHYSICALDAMAGE, -50, COMBAT_FIREDAMAGE)
eq(s, -150, "fire share added to the fire secondary")
eq(st, COMBAT_FIREDAMAGE, "secondary type kept")
eq(#extra, 1, "ice as an extra hit")
eq(extra[1].type, COMBAT_ICEDAMAGE, "ice extra")

-- secondary holds another element (energy): both shares are extra hits, the secondary stays
p, pt, s, st, extra = R.split(R.shares(0, COMBAT_NONE, {{type = COMBAT_FIREDAMAGE, percent = 10},
	{type = COMBAT_ICEDAMAGE, percent = 20}}), -1330, COMBAT_PHYSICALDAMAGE, -40, COMBAT_ENERGYDAMAGE)
eq(s, -40, "energy secondary unchanged")
eq(st, COMBAT_ENERGYDAMAGE, "energy type unchanged")
eq(#extra, 2, "both shares extra")

-- no physical part (e.g. a blocked hit): nothing added, nothing zeroed
p, pt, s, st, extra = R.split(R.shares(0, COMBAT_NONE, {{type = COMBAT_FIREDAMAGE, percent = 10},
	{type = COMBAT_ICEDAMAGE, percent = 20}}), 0, COMBAT_PHYSICALDAMAGE, -30, COMBAT_EARTHDAMAGE)
eq(s, -30, "no physical: secondary as it was")
eq(#extra, 0, "no physical: no extra hits")

-- the amount handed to doTargetCombat: Intelligence and the PvP halving taken back out
eq(R.sentAmount(100, 0, false), 100, "no stats")
eq(R.sentAmount(120, 20, false), 100, "Intelligence 20: 100 sent, 120 taken")
eq(R.sentAmount(50, 0, true), 100, "between players: doubled before the engine halves it")
eq(R.sentAmount(0, 0, false), 1, "at least 1")

-- ---------------------------------------------------------------- onHealthChange with the mock engine
local player = makePlayer({[FIRE] = 10, [ICE] = 20, [HOLY] = 7})
p, pt, s, st = R.onHealthChange(player, monster, 0, COMBAT_NONE, -1330, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE)
eq(p, -1330, "hook: primary kept")
eq(s, -200, "hook: ice inline")
eq(st, COMBAT_ICEDAMAGE, "hook: ice type")
eq(#events, 1, "hook: one deferred event for the extra hits")
runEvents()
eq(#combats, 2, "fire and holy dealt as their own hits")
eq(combats[1].type, COMBAT_FIREDAMAGE, "fire hit")
eq(combats[1].min, -100, "fire hit amount")
eq(combats[2].type, COMBAT_HOLYDAMAGE, "holy hit")
eq(combats[2].min, -70, "holy hit amount 1330 * 7 / 133")
eq(combats[1].origin, ORIGIN_NONE, "extra hits skip the damage events")
eq(combats[1].source, player, "extra hits from the attacker")
-- the target died before the event: nothing dealt
combats = {}
R.onHealthChange(player, monster, 0, COMBAT_NONE, -1330, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE)
monster.health = 0
runEvents()
eq(#combats, 0, "dead target: no extra hits")
monster.health = 1000

-- ---------------------------------------------------------------- the patch of the base script
-- A condensed copy of the stock handlers (the lines the patch matches are verbatim).
local STOCK = [[
local creatureEvent = CreatureEvent("rarity_onHealthChangeDamage")

function creatureEvent.onHealthChange(target, source, primaryDamage, primaryType, secondaryDamage, secondaryType, origin)
    if not source or not source:isPlayer() then
        return primaryDamage, primaryType, secondaryDamage, secondaryType
    end
    if origin ~= ORIGIN_MELEE and origin ~= ORIGIN_RANGED then
        return primaryDamage, primaryType, secondaryDamage, secondaryType
    end
    local weapon = source:getSlotItem(CONST_SLOT_RIGHT) or source:getSlotItem(CONST_SLOT_LEFT)
    if not weapon then
        return primaryDamage, primaryType, secondaryDamage, secondaryType
    end
    local itemType = weapon:getType()
    local baseElement = itemType and itemType:getElementDamage() or 0
    local baseElementType = itemType and itemType:getElementType() or COMBAT_NONE
    local elementTypes = {
        {combatType = COMBAT_FIREDAMAGE,   storage = 977554, name = "Fire"},
        {combatType = COMBAT_ICEDAMAGE,    storage = 977555, name = "Ice"},
        {combatType = COMBAT_HOLYDAMAGE,   storage = 977560, name = "Holy"},
    }
    local totalBonus = 0
    local chosenBonusType = COMBAT_NONE

    for _, elemData in ipairs(elementTypes) do
        local bonusValue = source:getStorageValue(elemData.storage) or 0
        if bonusValue > 0 then
            totalBonus = totalBonus + bonusValue
            if chosenBonusType == COMBAT_NONE then
                chosenBonusType = elemData.combatType
            elseif chosenBonusType ~= elemData.combatType then
                return
            end
        end
    end

    local finalElementType = (baseElementType ~= COMBAT_NONE) and baseElementType or chosenBonusType
    local elementPercent = baseElement + totalBonus
    if elementPercent <= 0 or finalElementType == COMBAT_NONE then
        return primaryDamage, primaryType, secondaryDamage, secondaryType
    end
    local mainPhysical = 0
    if primaryDamage < 0 then
        mainPhysical = -primaryDamage
    end
    local newElementalDamage = -math.floor((mainPhysical * elementPercent) / 133)
    if newElementalDamage >= 0 then
        return primaryDamage, primaryType, secondaryDamage, secondaryType
    end
    if secondaryType ~= COMBAT_NONE and secondaryDamage < 0 and secondaryType ~= finalElementType then
        secondaryDamage = secondaryDamage + newElementalDamage
    else
        secondaryType = finalElementType
        if secondaryDamage < 0 then
            secondaryDamage = secondaryDamage + newElementalDamage
        else
            secondaryDamage = newElementalDamage
        end
    end
    return primaryDamage, primaryType, secondaryDamage, secondaryType
end

creatureEvent:register()

local creatureEvent = CreatureEvent("rarity_onManaChangeDamage")

function creatureEvent.onManaChange(target, source, manaChange, origin)
    local baseElement, baseElementType = 0, COMBAT_NONE
    local elementTypes = {
        {combatType = COMBAT_FIREDAMAGE,   storage = 977554},
        {combatType = COMBAT_ICEDAMAGE,    storage = 977555},
    }
    local totalBonus = 0
    local chosenBonusType = COMBAT_NONE

    for _, elemData in ipairs(elementTypes) do
        local bonusValue = source:getStorageValue(elemData.storage) or 0
        if bonusValue > 0 then
            totalBonus = totalBonus + bonusValue
            if chosenBonusType == COMBAT_NONE then
                chosenBonusType = elemData.combatType
            elseif chosenBonusType ~= elemData.combatType then
                return manaChange
            end
        end
    end

    local finalElementType = (baseElementType ~= COMBAT_NONE) and baseElementType or chosenBonusType
    local elementPercent = baseElement + totalBonus
    if elementPercent <= 0 or finalElementType == COMBAT_NONE then
        return manaChange
    end
    if manaChange < 0 then
        manaChange = manaChange - math.floor((-manaChange * elementPercent) / 133)
    end
    return manaChange
end

creatureEvent:register()
]]

local handlers = {}
function CreatureEvent(name)
	local ev = {name = name}
	function ev:register()
		handlers[self.name] = self
	end
	return ev
end
local function loadScript(text)
	handlers = {}
	local chunk = assert((loadstring or load)(text))
	chunk()
	return handlers.rarity_onHealthChangeDamage.onHealthChange, handlers.rarity_onManaChangeDamage.onManaChange
end

-- the bug: two elements -> the stock handler returns nothing (the engine reads 0 damage)
local health, mana = loadScript(STOCK)
local twoElements = makePlayer({[FIRE] = 10, [ICE] = 20})
eq(select("#", health(monster, twoElements, -1330, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, ORIGIN_MELEE)), 0,
	"stock: two elements return nothing (the bug)")

local python = io.popen and io.popen("python3 -V 2>/dev/null")
local hasPython = python and (python:read("*a") or ""):find("Python 3")
if python then
	python:close()
end
if not hasPython then
	print("rarity_elements_test: python3 not found, patch checks skipped")
else
	local function runPatch(text)
		local path = os.tmpname()
		local f = assert(io.open(path, "wb"))
		f:write(text)
		f:close()
		local cmd = "python3 -I -c \"import sys; sys.path.insert(0, 'tools'); import patch_base_events as p; "
			.. "t = open(sys.argv[1]).read(); n, s = p.patch_rarity_elements(t); "
			.. "open(sys.argv[1], 'w').write(n); print(s)\" " .. path
		local h = assert(io.popen(cmd))
		local status = (h:read("*a") or ""):gsub("%s+$", "")
		h:close()
		f = assert(io.open(path, "rb"))
		local out = f:read("*a")
		f:close()
		os.remove(path)
		return out, status
	end
	local patched, status = runPatch(STOCK)
	eq(status, "patched", "patch applies to the stock lines")
	local again, status2 = runPatch(patched)
	eq(status2, "already", "second run: already")
	eq(again, patched, "second run changes nothing")
	local _, status3 = runPatch("local x = 1\n")
	ok(status3:find("unexpected", 1, true) ~= nil, "unknown file reported: " .. status3)

	health, mana = loadScript(patched)
	combats, events = {}, {}
	p, pt, s, st = health(monster, twoElements, -1330, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, ORIGIN_MELEE)
	eq(p, -1330, "patched: primary kept")
	eq(pt, COMBAT_PHYSICALDAMAGE, "patched: primary type kept")
	eq(s, -200, "patched: ice share")
	eq(st, COMBAT_ICEDAMAGE, "patched: ice type")
	runEvents()
	eq(#combats, 1, "patched: fire as its own hit")
	eq(combats[1] and combats[1].min, -100, "patched: fire amount")

	-- one element: the base script's own path, unchanged
	local oneElement = makePlayer({[FIRE] = 10})
	p, pt, s, st = health(monster, oneElement, -1330, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, ORIGIN_MELEE)
	eq(s, -100, "one element: base path")
	eq(st, COMBAT_FIREDAMAGE, "one element: fire")

	-- the helper script missing: the hit is kept as it was (never 0)
	local saved = ChaosRarityElements
	ChaosRarityElements = nil
	p, pt, s, st = health(monster, twoElements, -1330, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, ORIGIN_MELEE)
	eq(p, -1330, "no helper: primary kept")
	eq(st, COMBAT_NONE, "no helper: secondary as it was")
	ChaosRarityElements = saved

	-- mana: every element's % counts (stock: 0 bonus with two elements)
	eq(mana(monster, twoElements, -1330, ORIGIN_MELEE), -1330 - 300, "mana: 10% + 20% of 1330 / 133")
	local _, stockMana = loadScript(STOCK)
	eq(stockMana(monster, twoElements, -1330, ORIGIN_MELEE), -1330, "stock mana: no bonus with two elements")
end

if fails > 0 then
	print(("rarity_elements_test: %d of %d checks failed"):format(fails, checks))
	os.exit(1)
end
print(("rarity_elements_test: ok (%d checks)"):format(checks))
