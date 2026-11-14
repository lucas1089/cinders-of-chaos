-- Run from the server/ folder: luajit tests/monster_defence_test.lua (CI runs it with LuaJIT and Lua 5.3)
--   luajit tests/monster_defence_test.lua --table   prints the table of the README "Monster defence (O462)"
-- Monster defence (O462): monster_defence_core.lua (armour by hit size, the one resistance cap, the rank modifiers), the
-- engine file monster_defence.lua and the modifiers of monster_tiers.lua against a mocked engine: the table of a small,
-- a median and a five times median hit against a normal monster, an elite and a boss at levels 100, 500 and 1000; which
-- hits armour and the rank modifiers touch (weapon, spell, tick, summon); the resistance cap, rank bonus, Resistant and
-- penetration; the physical cap; block; Ruthless; the extra element and its absorb; the registration order.

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
local function near(a, b, tol, what)
	ok(math.abs(a - b) <= tol, (what or "check") .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end
local PRINT_TABLE = arg and arg[1] == "--table"

-- ---------------------------------------------------------------- engine mock
COMBAT_NONE, COMBAT_PHYSICALDAMAGE, COMBAT_ENERGYDAMAGE, COMBAT_EARTHDAMAGE, COMBAT_FIREDAMAGE = 0, 1, 2, 4, 8
COMBAT_UNDEFINEDDAMAGE, COMBAT_LIFEDRAIN, COMBAT_MANADRAIN, COMBAT_HEALING = 16, 32, 64, 128
COMBAT_DROWNDAMAGE, COMBAT_ICEDAMAGE, COMBAT_HOLYDAMAGE, COMBAT_DEATHDAMAGE = 256, 512, 1024, 2048
ORIGIN_NONE, ORIGIN_CONDITION, ORIGIN_SPELL, ORIGIN_MELEE, ORIGIN_RANGED, ORIGIN_WAND = 0, 1, 2, 3, 4, 5
RETURNVALUE_NOERROR = 0
CONST_ME_BLOCKHIT = 3
local n = 0
setmetatable(_G, {__index = function(t, k)
	if type(k) == "string" and k:match("^[A-Z_0-9]+$") then n = n + 1; rawset(t, k, 1000 + n); return 1000 + n end
end})
loadstring = loadstring or load
dofile("data/scripts/chaos/chaos_constants.lua")

local events = {}
function CreatureEvent(name)
	local e = {name = name}
	function e:register()
		events[name] = self
	end
	return e
end

local spawnCallbacks, targetCallbacks = {}, {}
local function registerCallback(self, index)
	local p = rawget(self, "_pending")
	rawset(self, "_pending", nil)
	local list = p[1] == "onSpawn" and spawnCallbacks or p[1] == "onTargetCombat" and targetCallbacks or nil
	if list then
		list[#list + 1] = {fn = p[2], index = index or 0, order = #list}
		table.sort(list, function(a, b)
			if a.index ~= b.index then
				return a.index < b.index
			end
			return a.order < b.order
		end)
	end
end
EventCallback = setmetatable({register = registerCallback}, {__newindex = function(t, k, v) rawset(t, "_pending", {k, v}) end})
function addEvent() end
Game = {getSpectators = function() return {} end}

local function position(x, y, z)
	return {x = x, y = y, z = z, effects = {}, sendMagicEffect = function(self, e) self.effects[#self.effects + 1] = e end,
		getDistance = function(a, b) return math.max(math.abs(a.x - b.x), math.abs(a.y - b.y)) end}
end

-- element lists by type name: combat type -> percent
local elementLists = {}
local nextId = 0x40000000
local function newMonster(typeName, opts)
	opts = opts or {}
	nextId = nextId + 1
	local list = elementLists[typeName] or {}
	local mt = {isBoss = function() return opts.boss or false end, getElementList = function() return list end}
	local m = {id = nextId, typeName = typeName, level = opts.level or 100, events = {}, order = {}, pos = position(1, 1, 7),
		maxHealth = opts.hp or 5000, health = opts.hp or 5000, master = opts.master}
	function m:getId() return self.id end
	function m:isMonster() return true end
	function m:isPlayer() return false end
	function m:getType() return mt end
	function m:getName() return typeName end
	function m:getMaster() return self.master end
	function m:getDisplayLevel() return self.level end
	function m:getMaxHealth() return self.maxHealth end
	function m:setMaxHealth(v) self.maxHealth = v end
	function m:getHealth() return self.health end
	function m:setHealth(v) self.health = v end
	function m:changeSpeed() end
	function m:getOutfit() return {lookType = 1, lookShader = 0} end
	function m:setOutfit() end
	function m:getPosition() return self.pos end
	function m:registerEvent(name)
		if self.events[name] then
			return false
		end
		self.events[name] = true
		self.order[#self.order + 1] = name
		return true
	end
	return m
end

local function newPlayer(absorb)
	nextId = nextId + 1
	local p = {id = nextId, slots = absorb or {}}
	function p:getId() return self.id end
	function p:isPlayer() return true end
	function p:isMonster() return false end
	function p:getMaster() return nil end
	function p:getSlotItem(slot) return self.slots[slot] end
	function p:getName() return "Hero" end
	function p:getVocation() local v = self.voc or 4; return {getId = function() return v end} end
	return p
end
-- an item with absorbPercent by ItemType (the engine's ability list, index from 1 = physical, 2 = energy, ...)
local abilityOf = {}
function ItemType(id)
	return {getAbilities = function() return abilityOf[id] end}
end

local spawnMonster = function(typeName, opts)
	local m = newMonster(typeName, opts)
	for _, cb in ipairs(spawnCallbacks) do
		cb.fn(m, m.pos, false, true)
	end
	return m
end

-- ---------------------------------------------------------------- load the scripts
local DEF = dofile("data/scripts/chaos/defence_config.lua")
local CFG
dofile("data/scripts/chaos/monster_tiers.lua")
dofile("data/scripts/chaos/monster_defence.lua")
local C = ChaosMonsterDefenceCore
local MD = ChaosMonsterDefence
CFG = Chaos.monsterDefence -- the table the scripts use (monster_tiers.lua reads the same one)
eq(ChaosMonsterDefenceConfig, CFG, "one config table for the layer and the tiers")
local K = C.engineConstants()
local defence = events.ChaosMonsterDefence
ok(defence ~= nil, "the event exists")

-- the shared numbers live in ONE file
eq(DEF.armourHitFactor, 0.07, "armourHitFactor")
eq(DEF.physicalReductionCap, 90, "physicalReductionCap")
eq(DEF.resistCap, 75, "resistCap")
eq(DEF.blockCap, 75, "blockCap")
eq(Chaos.defence.resistCap, 75, "Chaos.defence is the shared file")

local rolls = {}
local realRandom = math.random
local function scriptRandom(...)
	rolls = {...}
end
local function fixRoll(v)
	math.random = function(a, b)
		if a == 100 and b == nil then
			return v
		end
		return realRandom(a, b)
	end
end
local function freeRoll()
	math.random = realRandom
end

local player = newPlayer()
local function hit(monster, attacker, value, ctype, origin, secondary, stype)
	local p, pt, s, st = defence.onHealthChange(monster, attacker or player, value, ctype or COMBAT_PHYSICALDAMAGE, secondary or 0,
		stype or COMBAT_NONE, origin or ORIGIN_MELEE)
	return p, s, pt, st
end

-- ---------------------------------------------------------------- the curve and the armour
do
	local c = CFG.hitCurve
	for _, row in ipairs(c) do
		near(C.hitAtLevel(CFG, row.level), row.hit, 1e-6, "curve: the anchor " .. row.level)
	end
	local last = c[#c]
	ok(C.hitAtLevel(CFG, 3000) > last.hit, "curve: beyond the last row it keeps growing")
	ok(C.hitAtLevel(CFG, 0) > 0 and C.hitAtLevel(CFG, 0) <= c[1].hit, "curve: level 0 reads as level 1")
	local between = C.hitAtLevel(CFG, 700)
	ok(between > C.hitAtLevel(CFG, 500) and between < C.hitAtLevel(CFG, 1000), "curve: between two rows")
	-- the median class hit loses 25 / 40 / 50 percent at every level
	for _, lv in ipairs({1, 10, 100, 333, 500, 1000, 2200}) do
		for class, want in pairs(CFG.armourTarget) do
			local A = C.armourValue(DEF, CFG, lv, class)
			near(C.armourReduction(DEF, A, C.hitAtLevel(CFG, lv)), want / 100, 1e-9, "median hit at level " .. lv .. ": " .. class)
		end
	end
	eq(C.armourValue(DEF, CFG, 100, "boss", "Pestrogh") > C.armourValue(DEF, CFG, 100, "elite", "x"), true, "armour grows with the class")
	local saved = CFG.armourOverride
	CFG.armourOverride = {["troll"] = 777}
	eq(C.armourValue(DEF, CFG, 100, "boss", "Troll"), 777, "per-monster override (lower case name)")
	CFG.armourOverride = saved
	eq(next(CFG.armourOverride), nil, "the override table is empty at the start")
	-- a big hit loses less than a small one
	local A = C.armourValue(DEF, CFG, 500, "normal")
	ok(C.armourReduction(DEF, A, 100) > C.armourReduction(DEF, A, 1000) and C.armourReduction(DEF, A, 1000) > C.armourReduction(DEF, A, 100000),
		"armour: a small hit loses more than a big one")
	eq(C.armourReduction(DEF, 0, 1000), 0, "no armour, no reduction")
	eq(C.armourReduction(DEF, A, 0), 0, "no hit, no reduction")
end

-- ---------------------------------------------------------------- the table: small, median, 5x median; normal, elite, boss
local TABLE = {}
do
	local classes = {
		normal = function(level) return spawnMonster("Rotling", {level = level}) end,
		elite = function(level)
			local m = spawnMonster("Rotling", {level = level})
			ChaosTierState[m:getId()] = {tier = "rare", depth = 0, mods = {}, step = 0}
			return m
		end,
		boss = function(level) return spawnMonster("Rotling", {level = level, boss = true}) end
	}
	for _, level in ipairs({100, 500, 1000}) do
		local median = C.hitAtLevel(CFG, level)
		for _, class in ipairs({"normal", "elite", "boss"}) do
			local m = classes[class](level)
			eq(MD.classOf(m), class, "class of the test monster " .. class)
			eq(MD.levelOf(m), level, "level of the test monster")
			local A = MD.armourOf(m)
			for _, size in ipairs({{"small", 0.2}, {"median", 1}, {"5x median", 5}}) do
				local H = math.floor(median * size[2] + 0.5)
				-- O501: a SPELL is measured against the median class hit (a weapon hit has its own table below)
				local out = hit(m, player, H, COMBAT_PHYSICALDAMAGE, ORIGIN_SPELL)
				local red = C.armourReduction(DEF, A, H)
				local want = math.floor(H * (1 - red) + 0.5)
				eq(out, want, "table: " .. class .. " level " .. level .. " " .. size[1] .. " hit " .. H)
				TABLE[#TABLE + 1] = {level = level, class = class, size = size[1], hit = H, out = out, red = (1 - out / H) * 100, A = A}
				if size[1] == "median" then
					near(1 - out / H, CFG.armourTarget[class] / 100, 0.002, "table: the median hit of level " .. level .. " loses " .. class .. " share")
				end
			end
		end
	end
	if PRINT_TABLE then
		print("level  class   hit size   hit     after    removed   A")
		for _, r in ipairs(TABLE) do
			print(string.format("%5d  %-6s  %-9s %6d  %6d  %6.1f%%  %8.1f", r.level, r.class, r.size, r.hit, r.out, r.red, r.A))
		end
	end
end

-- ---------------------------------------------------------------- which hits armour touches
do
	local m = spawnMonster("Rotling", {level = 500})
	local H = 1000
	local melee = hit(m, player, H, COMBAT_PHYSICALDAMAGE, ORIGIN_MELEE)
	local ranged = hit(m, player, H, COMBAT_PHYSICALDAMAGE, ORIGIN_RANGED)
	local spell = hit(m, player, H, COMBAT_PHYSICALDAMAGE, ORIGIN_SPELL)
	eq(melee, ranged, "weapon hit: melee and ranged alike")
	-- O501: a weapon hit has its own armour value and cap, a spell keeps the class curve
	local mA, mAw = MD.armourOf(m), MD.weaponArmourOf(m)
	eq(spell, math.floor(H * (1 - C.armourReduction(DEF, mA, H)) + 0.5), "a physical spell is armoured by the class curve")
	eq(melee, math.floor(H * (1 - C.weaponShare(DEF, mAw, H, C.weaponShareCap(CFG, "normal"))) + 0.5), "a weapon hit is armoured by the weapon curve")
	ok(melee < H and spell < H, "weapon hit and spell: armoured")
	eq(hit(m, player, H, COMBAT_PHYSICALDAMAGE, ORIGIN_CONDITION), H, "a physical tick (bleeding): no armour")
	eq(hit(m, player, H, COMBAT_FIREDAMAGE, ORIGIN_SPELL), H, "an elemental spell: no armour, no resistance on the base 0")
	eq(hit(m, player, H, COMBAT_FIREDAMAGE, ORIGIN_CONDITION), H, "a fire tick: untouched")
	-- O474: a scripted tick of a dot spell (Gorehook, the kit and necro dots, the side dots) is a damage over time tick like an
	-- engine condition's: it skips the armour. A plain hit of the same spell stays armoured; the resistance still applies.
	do
		dofile("data/scripts/chaos/dot_config.lua")
		dofile("data/scripts/chaos/dot_core.lua")
		local store = {}
		function player:getStorageValue(k) local v = store[k]; if v == nil then return -1 end return v end
		function player:setStorageValue(k, v) store[k] = v end
		local tickHit, tickFire
		ChaosDot.run(player, m, function()
			tickHit = hit(m, player, H, COMBAT_PHYSICALDAMAGE, ORIGIN_SPELL)
			tickFire = hit(m, player, H, COMBAT_FIREDAMAGE, ORIGIN_SPELL)
		end)
		eq(tickHit, H, "O474: a scripted physical tick skips the armour (it lost 74 to 84% of a Gorehook tick)")
		eq(tickFire, H, "O474: a scripted fire tick is untouched on a monster with no resistance")
		eq(hit(m, player, H, COMBAT_PHYSICALDAMAGE, ORIGIN_SPELL), spell, "O474: the same spell's direct hit is armoured as before")
		local other = spawnMonster("Rotling", {level = 500})
		local onOther
		ChaosDot.run(player, m, function() onOther = hit(other, player, H, COMBAT_PHYSICALDAMAGE, ORIGIN_SPELL) end)
		ok(onOther < H, "O474: the flag names one target: a hit on another monster is armoured")
	end
	-- the weapon's element part is the secondary: element rules only
	local p, s = hit(m, player, H, COMBAT_PHYSICALDAMAGE, ORIGIN_MELEE, 400, COMBAT_FIREDAMAGE)
	eq(p, melee, "weapon hit with an element part: the physical part is armoured")
	eq(s, 400, "weapon hit with an element part: the element part is not")
	-- a summon or companion (a monster whose master is a player) hits like its player
	local summon = newMonster("Wolf", {master = player})
	eq(hit(m, summon, H, COMBAT_PHYSICALDAMAGE, ORIGIN_MELEE), melee, "a summon's hit is armoured like the player's")
	-- another monster, no attacker, a monster's summon of a monster: left alone
	local foe = newMonster("Foe")
	eq(hit(m, foe, H, COMBAT_PHYSICALDAMAGE, ORIGIN_MELEE), H, "a monster hurting a monster: untouched")
	eq(defence.onHealthChange(m, nil, H, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, ORIGIN_MELEE), H, "no attacker: untouched")
	eq(hit(m, player, H, COMBAT_HEALING, ORIGIN_SPELL), H, "healing: untouched")
	eq(hit(m, player, H, COMBAT_LIFEDRAIN, ORIGIN_SPELL), H, "life drain: untouched")
	eq(hit(m, player, H, COMBAT_UNDEFINEDDAMAGE, ORIGIN_SPELL), H, "undefined damage: untouched")
	-- the sign of the value is kept
	eq(hit(m, player, -H, COMBAT_PHYSICALDAMAGE, ORIGIN_MELEE), -melee, "a negative value stays negative")
	-- a tiny hit never rounds to nothing
	eq(hit(m, player, 1, COMBAT_PHYSICALDAMAGE, ORIGIN_MELEE), 1, "a hit of 1 stays 1")
	-- off switch
	CFG.enabled = false
	eq(hit(m, player, H, COMBAT_PHYSICALDAMAGE, ORIGIN_MELEE), H, "enabled = false: untouched")
	CFG.enabled = true
end

-- ---------------------------------------------------------------- O505: a spell of a weapon class is a weapon-size hit
do
	local m = spawnMonster("Rotling", {level = 500})
	local mA, mAw = MD.armourOf(m), MD.weaponArmourOf(m)
	local cap = C.weaponShareCap(CFG, "normal")
	local savedSS = rawget(_G, "ChaosSupportsSpell")
	local castPid -- the player id of the running cast, nil outside one (ChaosSupportsSpell.cast of data/spells/chaos/_supports.lua)
	ChaosSupportsSpell = {cast = function() if castPid then return castPid, 201 end return nil end}
	local function spell(H, who, ctype)
		return hit(m, who or player, H, ctype or COMBAT_PHYSICALDAMAGE, ORIGIN_SPELL)
	end
	-- the pure rule
	eq(C.weaponSpellHit(CFG, 4, 7, 7), true, "weaponSpellHit: a Warrior inside its own cast")
	eq(C.weaponSpellHit(CFG, 4, nil, 7), false, "weaponSpellHit: outside any cast")
	eq(C.weaponSpellHit(CFG, 4, 8, 7), false, "weaponSpellHit: another player's cast")
	eq(C.weaponSpellHit(CFG, 4, 7, nil), false, "weaponSpellHit: no attacker")
	for _, v in ipairs({1, 5, 10, 20, 21, 22}) do
		eq(C.weaponSpellHit(CFG, v, 7, 7), false, "weaponSpellHit: caster vocation " .. v .. " keeps the class curve")
	end
	for _, v in ipairs({3, 4, 7, 8, 11, 12, 13, 14, 15, 17, 18, 19, 23, 24, 25}) do
		eq(C.weaponSpellHit(CFG, v, 7, 7), true, "weaponSpellHit: weapon vocation " .. v)
	end
	eq(C.weaponSpellHit(CFG, nil, 7, 7), false, "weaponSpellHit: no vocation")
	eq(C.weaponSpellHit(CFG, 0, 7, 7), false, "weaponSpellHit: vocation 0 (no vocation)")
	eq(#CFG.casterVocations, 6, "six casting classes in the config")
	-- the layer: the same physical spell hit, outside a cast and inside the player's own cast
	local H, small = 1000, 100
	castPid = nil
	local outside, outsideSmall = spell(H), spell(small)
	eq(outside, math.floor(H * (1 - C.armourReduction(DEF, mA, H)) + 0.5), "outside a cast: the class curve")
	castPid = player:getId()
	local inside, insideSmall = spell(H), spell(small)
	eq(inside, math.floor(H * (1 - C.weaponShare(DEF, mAw, H, cap)) + 0.5), "inside the player's own cast: the weapon armour value and cap")
	eq(insideSmall, math.floor(small * (1 - C.weaponShare(DEF, mAw, small, cap)) + 0.5), "a small hit: the weapon cap")
	ok(inside > outside and insideSmall > outsideSmall, "the weapon rule takes less of a weapon-size spell hit than the class curve did")
	ok(insideSmall >= small * (1 - cap) - 1, "a spell hit of a weapon class never loses more than the weapon cap")
	-- a hit of a weapon spell is the same hit as an auto attack of the same size
	eq(inside, hit(m, player, H, COMBAT_PHYSICALDAMAGE, ORIGIN_MELEE), "the same share as a weapon hit of that size")
	-- a caster inside its own cast keeps the class curve
	local mage = newPlayer(); mage.voc = 1
	castPid = mage:getId()
	eq(spell(H, mage), outside, "a caster's physical spell keeps the class curve")
	-- a summon (a minion, a wolf) of a player inside the player's cast is not the player: the class curve
	castPid = player:getId()
	local minion = newMonster("Minion", {master = player})
	eq(hit(m, minion, H, COMBAT_PHYSICALDAMAGE, ORIGIN_SPELL), outside, "a summon's spell hit keeps the class curve")
	-- another player's cast does not make this player's hit a weapon spell
	local other = newPlayer(); other.voc = 4
	castPid = other:getId()
	eq(spell(H), outside, "another player's cast: no mark leaks to this hit")
	-- the cast is over: the next hit is a class-curve hit again
	castPid = nil
	eq(spell(H), outside, "after the cast the mark is gone")
	-- the element part of a spell is the resistance's business only, whatever the cast
	castPid = player:getId()
	eq(spell(H, player, COMBAT_FIREDAMAGE), H, "an elemental spell: no armour")
	-- a tick of a dot spell inside a cast still skips the armour; Bulwark never blocks a spell
	castPid = nil
	-- an error in the cast function: the layer reads the supports context only, and a failing reader leaves the class curve
	ChaosSupportsSpell = {cast = function() error("boom") end}
	eq(spell(H), outside, "a failing context reader: the class curve, no error")
	ChaosSupportsSpell = nil
	eq(spell(H), outside, "no supports wrapper at all: the class curve")
	ChaosSupportsSpell = savedSS
	-- a snare's or a mine's burst and the engine's precast of a spell: the combat log knows the cast (ChaosCombatLog.inSpell)
	local savedCL = rawget(_G, "ChaosCombatLog")
	ChaosSupportsSpell = {cast = function() return nil end}
	local logPid
	ChaosCombatLog = {inSpell = function(pid) return pid == logPid end}
	logPid = player:getId()
	eq(spell(H), inside, "a burst named by the combat log is the player's own spell: the weapon rule")
	logPid = other:getId()
	eq(spell(H), outside, "the combat log naming another player's cast: no mark leaks")
	logPid = player:getId()
	eq(hit(m, minion, H, COMBAT_PHYSICALDAMAGE, ORIGIN_SPELL), outside, "a summon's hit keeps the class curve even while its master casts")
	eq(spell(H, mage), outside, "a caster keeps the class curve")
	ChaosCombatLog = {inSpell = function() error("boom") end}
	eq(spell(H), outside, "a failing combat log: the class curve, no error")
	ChaosCombatLog = savedCL
	ChaosSupportsSpell = savedSS
	-- Bulwark (weapon hits only) does not block a weapon spell
	local bulwark = spawnMonster("Rotling", {level = 500})
	ChaosTierState[bulwark:getId()] = {tier = "rare", depth = 0, mods = {"bulwark"}, step = 0}
	ChaosSupportsSpell = {cast = function() return player:getId(), 201 end}
	local realRand = math.random
	math.random = function() return 1 end -- every block roll would block
	local blockedMelee = hit(bulwark, player, H, COMBAT_PHYSICALDAMAGE, ORIGIN_MELEE)
	local spellVsBulwark = hit(bulwark, player, H, COMBAT_PHYSICALDAMAGE, ORIGIN_SPELL)
	math.random = realRand
	eq(blockedMelee, 0, "Bulwark blocks a weapon hit")
	ok(spellVsBulwark > 0, "Bulwark never blocks a spell, weapon class or not")
	ChaosSupportsSpell = savedSS
end

-- ---------------------------------------------------------------- element resistance: one cap, rank bonus, Resistant, penetration
do
	elementLists["Ember Troll"] = {[COMBAT_FIREDAMAGE] = 30, [COMBAT_ICEDAMAGE] = 90, [COMBAT_ENERGYDAMAGE] = -20,
		[COMBAT_PHYSICALDAMAGE] = 0}
	local normal = spawnMonster("Ember Troll", {level = 500})
	local H = 1000
	-- the engine applied 30% already: a hit that arrives as 700 stays 700
	eq(hit(normal, player, 700, COMBAT_FIREDAMAGE, ORIGIN_SPELL), 700, "normal: base 30 is under the cap, unchanged")
	-- base 90 (data the install tool has not capped): the cap 75 gives damage back: arrived 100 -> 100 x 0.25 / 0.10 = 250
	eq(hit(normal, player, 100, COMBAT_ICEDAMAGE, ORIGIN_SPELL), 250, "normal: base 90 is capped at 75")
	-- O474: a scripted tick skips the armour, not the resistance: the same cap applies to it
	do
		local tick
		ChaosDot.run(player, normal, function() tick = hit(normal, player, 100, COMBAT_ICEDAMAGE, ORIGIN_SPELL) end)
		eq(tick, 250, "O474: a scripted ice tick still meets the resistance (capped at 75)")
	end
	-- a weakness stays
	eq(hit(normal, player, 1200, COMBAT_ENERGYDAMAGE, ORIGIN_SPELL), 1200, "normal: a weakness is untouched")
	near(MD.effectiveResist(normal, COMBAT_FIREDAMAGE, 0), 30, 1e-9, "effective resist: normal fire")
	near(MD.effectiveResist(normal, COMBAT_ICEDAMAGE, 0), 75, 1e-9, "effective resist: capped")
	near(MD.effectiveResist(normal, COMBAT_ENERGYDAMAGE, 0), -20, 1e-9, "effective resist: a weakness")
	near(MD.effectiveResist(normal, COMBAT_FIREDAMAGE, 10), 20, 1e-9, "effective resist: penetration comes off the capped value")
	near(MD.effectiveResist(normal, COMBAT_ICEDAMAGE, 10), 65, 1e-9, "effective resist: penetration after the cap")
	near(MD.effectiveResist(normal, COMBAT_ENERGYDAMAGE, 25), -45, 1e-9, "effective resist: penetration beyond a weakness")
	-- no penetration without item modifiers
	eq(hit(normal, player, 100, COMBAT_ICEDAMAGE, ORIGIN_SPELL), 250, "no penetration, nothing taken off")
	-- penetration (O464): the attacking player's item modifiers, off the capped resistance, down to -100; physical penetration
	-- is points off the ARMOUR share down to 0, never off the file's physical percent
	local savedMods = ChaosItemMods
	local bonusOf = {}
	ChaosItemMods = {playerBonus = function(p, key) return (bonusOf[p:getId()] or {})[key] or 0 end}
	local pener = newPlayer()
	bonusOf[pener:getId()] = {elepen = 20, physpen = 10}
	-- fire 30: raw 1000 arrives as 700; 20 points off -> resistance 10 -> 900
	eq(hit(normal, pener, 700, COMBAT_FIREDAMAGE, ORIGIN_SPELL), 900, "elemental penetration off a resistance of 30")
	-- ice 90 capped at 75: raw 1000 arrives as 100; 20 off the CAPPED value -> 55 -> 450
	eq(hit(normal, pener, 100, COMBAT_ICEDAMAGE, ORIGIN_SPELL), 450, "elemental penetration is taken after the cap")
	-- a weakness of -20: 25 more points -> -40 (raw 1000 arrives as 1200) -> 1400 / 1200
	bonusOf[pener:getId()].elepen = 20
	eq(hit(normal, pener, 1200, COMBAT_ENERGYDAMAGE, ORIGIN_SPELL), 1400, "penetration beyond a weakness raises the damage")
	-- the floor is -100: raw 1000 arrives as 700 at 30; 400 points off -> -100 -> 2000
	bonusOf[pener:getId()].elepen = 400
	eq(hit(normal, pener, 700, COMBAT_FIREDAMAGE, ORIGIN_SPELL), 2000, "the resistance never goes below -100")
	near(MD.effectiveResist(normal, COMBAT_FIREDAMAGE, 400), -100, 1e-9, "effective resist: floor -100")
	-- a condition tick meets elemental penetration too
	bonusOf[pener:getId()].elepen = 20
	eq(hit(normal, pener, 700, COMBAT_FIREDAMAGE, ORIGIN_CONDITION), 900, "elemental penetration on a tick")
	-- physical: the level 500 normal monster's armour takes 25% of the median hit 3645; 10 points of physical penetration -> 15%
	elementLists["Plain Orc"] = {}
	local orc = spawnMonster("Plain Orc", {level = 500})
	local medianHit = math.floor(C.hitAtLevel(CFG, 500) + 0.5)
	bonusOf[pener:getId()] = {physpen = 10}
	near(hit(orc, pener, medianHit, COMBAT_PHYSICALDAMAGE, ORIGIN_SPELL), medianHit * 0.85, 1.5, "10 physical penetration: 15% armour share (a spell)")
	-- O501: the same on a weapon hit of the median weapon size: the weapon armour share minus 10 points
	local medianW = math.floor(C.weaponHitAtLevel(CFG, 500) + 0.5)
	local shareW = C.weaponShare(DEF, MD.weaponArmourOf(orc), medianW, C.weaponShareCap(CFG, "normal"))
	near(hit(orc, pener, medianW, COMBAT_PHYSICALDAMAGE, ORIGIN_MELEE), medianW * (1 - (shareW - 0.10)), 1.5, "10 physical penetration: 10 points off the weapon armour share")
	bonusOf[pener:getId()] = {physpen = 80}
	eq(hit(orc, pener, medianHit, COMBAT_PHYSICALDAMAGE, ORIGIN_SPELL), medianHit, "penetration beyond the armour share: down to 0, not below")
	eq(hit(orc, pener, medianW, COMBAT_PHYSICALDAMAGE, ORIGIN_MELEE), medianW, "penetration beyond the weapon armour share: down to 0, not below")
	-- the file's physical percent is not touched by physical penetration (the engine took 30 already: arrived 700 of 1000)
	elementLists["Stone Orc"] = {[COMBAT_PHYSICALDAMAGE] = 30}
	local stone = spawnMonster("Stone Orc", {level = 500})
	bonusOf[pener:getId()] = {physpen = 80}
	eq(hit(stone, pener, 700, COMBAT_PHYSICALDAMAGE, ORIGIN_MELEE), 700, "physical penetration does not lower the file's physical percent")
	-- a summon's hit counts the master's penetration
	local summon = newMonster("Wolf", {master = pener})
	bonusOf[pener:getId()] = {elepen = 20}
	eq(hit(normal, summon, 700, COMBAT_FIREDAMAGE, ORIGIN_SPELL), 900, "a summon uses its master's penetration")
	ChaosItemMods = savedMods
	-- an elite rank: +15 on the element resistance, before the cap
	local elite = spawnMonster("Ember Troll", {level = 500})
	ChaosTierState[elite:getId()] = {tier = "legendary", depth = 0, mods = {}, step = 0}
	near(MD.effectiveResist(elite, COMBAT_FIREDAMAGE, 0), 45, 1e-9, "elite: fire 30 + 15")
	near(MD.effectiveResist(elite, COMBAT_ICEDAMAGE, 0), 75, 1e-9, "elite: 90 + 15 capped at 75")
	near(MD.effectiveResist(elite, COMBAT_ENERGYDAMAGE, 0), -5, 1e-9, "elite: a weakness of -20 becomes -5")
	-- arrives 700 (30% off): 45% off the raw hit is 550 -> 700 x 0.55 / 0.7 = 550
	eq(hit(elite, player, 700, COMBAT_FIREDAMAGE, ORIGIN_SPELL), 550, "elite: fire corrected from 30 to 45")
	-- the magic rank is no elite rank: no bonus
	local magic = spawnMonster("Ember Troll", {level = 500})
	ChaosTierState[magic:getId()] = {tier = "magic", depth = 0, mods = {}, step = 0}
	near(MD.effectiveResist(magic, COMBAT_FIREDAMAGE, 0), 30, 1e-9, "magic: no rank bonus")
	-- a boss: no rank bonus either, the cap holds
	local boss = spawnMonster("Ember Troll", {level = 500, boss = true})
	near(MD.effectiveResist(boss, COMBAT_FIREDAMAGE, 0), 30, 1e-9, "boss: no rank bonus")
	near(MD.effectiveResist(boss, COMBAT_ICEDAMAGE, 0), 75, 1e-9, "boss: capped at 75")
	-- Resistant: the drawn element is raised to 75 (inside the cap), the others are not
	local res = spawnMonster("Ember Troll", {level = 500})
	ChaosTierState[res:getId()] = {tier = "rare", depth = 0, mods = {"resistant"}, step = 0, draw = {resistant = "fire"}}
	near(MD.effectiveResist(res, COMBAT_FIREDAMAGE, 0), 75, 1e-9, "Resistant: the drawn element 75")
	near(MD.effectiveResist(res, COMBAT_ENERGYDAMAGE, 0), -5, 1e-9, "Resistant: another element keeps its number")
	-- arrives 700 -> raw 1000 -> 25% -> 250
	eq(hit(res, player, 700, COMBAT_FIREDAMAGE, ORIGIN_SPELL), 250, "Resistant: the drawn element hit")
	-- a tick is resisted too (fields and conditions)
	eq(hit(res, player, 700, COMBAT_FIREDAMAGE, ORIGIN_CONDITION), 250, "Resistant: a tick is resisted")
	-- physical is no element: the rank bonus and Resistant do not touch it
	eq(hit(res, player, 1000, COMBAT_PHYSICALDAMAGE, ORIGIN_CONDITION), 1000, "physical tick: no resistance rule but the cap")
end

-- ---------------------------------------------------------------- physical: one cap for armour, the monster's percent and Plated
do
	elementLists["Stone Ogre"] = {[COMBAT_PHYSICALDAMAGE] = 60}
	local m = spawnMonster("Stone Ogre", {level = 100, boss = true})
	local A = MD.armourOf(m)
	-- the engine took 60% already: a small hit arrives as 40; armour and the 60 together are capped at 90 in all
	local small = hit(m, player, 40, COMBAT_PHYSICALDAMAGE, ORIGIN_SPELL) -- 100 raw
	eq(small, 10, "physical cap: raw 100 against 60% and a boss's armour is at most 90% off, 10 left")
	-- a big hit: armour hardly counts: 60% + a little
	local big = hit(m, player, 40000, COMBAT_PHYSICALDAMAGE, ORIGIN_SPELL) -- 100000 raw
	local red = C.armourReduction(DEF, A, 40000)
	eq(big, math.floor(40000 * (1 - red) + 0.5), "physical: a big hit loses only a little more to armour")
	-- Plated: 50% less, inside the same cap
	local plated = spawnMonster("Stone Ogre", {level = 100})
	ChaosTierState[plated:getId()] = {tier = "rare", depth = 0, mods = {"plated"}, step = 0}
	local Ap = MD.armourOf(plated)
	local h = 1000
	local out = hit(plated, player, h, COMBAT_PHYSICALDAMAGE, ORIGIN_SPELL)
	local want = h * (1 - C.armourReduction(DEF, Ap, h)) * 0.5
	-- 60% off + armour + 50% would be ~ 1 - 0.4 x 0.8 x 0.5 = 84% off; the cap is 90: no cap here
	near(out, math.floor(want + 0.5), 1, "Plated: 50% less physical on top of armour")
	-- with a physical 85: 85% + armour + 50% is far over 90: the total stays 90
	elementLists["Iron Ogre"] = {[COMBAT_PHYSICALDAMAGE] = 85}
	local iron = spawnMonster("Iron Ogre", {level = 100})
	ChaosTierState[iron:getId()] = {tier = "rare", depth = 0, mods = {"plated"}, step = 0}
	local capped = hit(iron, player, 150, COMBAT_PHYSICALDAMAGE, ORIGIN_MELEE) -- 1000 raw
	near(capped, 100, 1, "the total physical reduction never passes 90% (1000 raw -> 100)")
	-- a tick: Plated and the cap, no armour
	elementLists["Bone Ogre"] = {[COMBAT_PHYSICALDAMAGE] = 0}
	local bone = spawnMonster("Bone Ogre", {level = 100})
	ChaosTierState[bone:getId()] = {tier = "rare", depth = 0, mods = {"plated"}, step = 0}
	eq(hit(bone, player, 1000, COMBAT_PHYSICALDAMAGE, ORIGIN_CONDITION), 500, "Plated: a physical tick is halved, no armour")
end


-- ---------------------------------------------------------------- O501: a weapon hit has its own curve and its own cap
-- Owner 2026-11-11: "the auto attack is hitting practically nothing on the monsters". The armour was sized for the median CLASS
-- hit (what a spell is); an auto attack arrives at the layer as the engine rolled it, a fifth to a half of that, and lost 50 to 90%.
do
	local W = CFG.weaponHitCurve
	ok(W ~= nil and #W >= 13, "O501: the config has the weapon curve")
	for _, row in ipairs(W) do
		near(C.weaponHitAtLevel(CFG, row.level), row.hit, 1e-6, "weapon curve: the anchor " .. row.level)
	end
	ok(C.weaponHitAtLevel(CFG, 3000) > W[#W].hit, "weapon curve: beyond the last row it keeps growing")
	ok(C.weaponHitAtLevel(CFG, 0) > 0, "weapon curve: level 0 reads as level 1")
	for _, lv in ipairs({100, 500, 1000, 2000}) do
		ok(C.weaponHitAtLevel(CFG, lv) < C.hitAtLevel(CFG, lv), "weapon curve: the median weapon hit is under the median class hit at level " .. lv)
	end
	-- the median weapon hit loses weaponTarget percent: the weapon armour value is derived from its own curve
	for _, lv in ipairs({1, 10, 100, 333, 500, 1000, 2200}) do
		for class, want in pairs(CFG.weaponTarget) do
			local A = C.armourValue(DEF, CFG, lv, class, nil, true)
			near(C.armourReduction(DEF, A, C.weaponHitAtLevel(CFG, lv)), want / 100, 1e-9, "median weapon hit at level " .. lv .. ": " .. class)
		end
	end
	-- the caps are the ceilings of the auto attack (tools/defence_curve.py G2): 40 / 55 / 65 percent
	eq(C.weaponShareCap(CFG, "normal"), 0.40, "cap: normal")
	eq(C.weaponShareCap(CFG, "elite"), 0.55, "cap: elite")
	eq(C.weaponShareCap(CFG, "boss"), 0.65, "cap: boss")
	eq(C.weaponShare(DEF, 1000, 1, 0.4), 0.4, "weaponShare: a tiny hit against a big armour loses the cap")
	ok(C.weaponShare(DEF, 1, 1000, 0.4) < 0.4, "weaponShare: a big hit loses under the cap")

	local classes = {
		normal = function(level) return spawnMonster("Rotling", {level = level}) end,
		elite = function(level)
			local m = spawnMonster("Rotling", {level = level})
			ChaosTierState[m:getId()] = {tier = "rare", depth = 0, mods = {}, step = 0}
			return m
		end,
		boss = function(level) return spawnMonster("Rotling", {level = level, boss = true}) end
	}
	local WTABLE = {}
	for _, level in ipairs({20, 100, 500, 1000}) do
		local median = C.weaponHitAtLevel(CFG, level)
		for _, class in ipairs({"normal", "elite", "boss"}) do
			local m = classes[class](level)
			local Aw, A = MD.weaponArmourOf(m), MD.armourOf(m)
			ok(Aw < A, "the weapon armour value is under the spell's: " .. class .. " " .. level)
			eq(MD.weaponArmourOf(m), Aw, "the weapon armour value is cached")
			local cap = C.weaponShareCap(CFG, class)
			for _, size in ipairs({{"tiny", 0.05}, {"small", 0.2}, {"median", 1}, {"5x median", 5}}) do
				local H = math.max(1, math.floor(median * size[2] + 0.5))
				local out = hit(m, player, H, COMBAT_PHYSICALDAMAGE, ORIGIN_MELEE)
				local share = C.weaponShare(DEF, Aw, H, cap)
				eq(out, math.max(1, math.floor(H * (1 - share) + 0.5)), "weapon table: " .. class .. " level " .. level .. " " .. size[1] .. " hit " .. H)
				ok(H - out <= H * cap + 1, "weapon cap: " .. class .. " level " .. level .. " " .. size[1] .. " hit " .. H .. " loses at most the cap")
				WTABLE[#WTABLE + 1] = {level = level, class = class, size = size[1], hit = H, out = out, red = (1 - out / H) * 100, A = Aw}
				if size[1] == "median" then
					near(1 - out / H, CFG.weaponTarget[class] / 100, 0.02 + 0.5 / H, "weapon table: the median weapon hit of level " .. level .. " loses its " .. class .. " share")
				end
				-- a ranged weapon hit is the same
				eq(hit(m, player, H, COMBAT_PHYSICALDAMAGE, ORIGIN_RANGED), out, "weapon table: ranged is melee")
				-- a spell of the same size meets the class armour: its number is the one of before O501
				local sp = hit(m, player, H, COMBAT_PHYSICALDAMAGE, ORIGIN_SPELL)
				eq(sp, math.max(1, math.floor(H * math.max(1 - C.armourReduction(DEF, A, H), 1 - DEF.physicalReductionCap / 100) + 0.5)), "O501: a spell is unchanged: " .. class .. " level " .. level .. " " .. size[1])
			end
			-- a big hit still loses less than a small one of the same kind (the idea of O462)
			local small, big = math.floor(median * 0.3 + 0.5), math.floor(median * 30 + 0.5)
			local so = hit(m, player, small, COMBAT_PHYSICALDAMAGE, ORIGIN_MELEE)
			local bo = hit(m, player, big, COMBAT_PHYSICALDAMAGE, ORIGIN_MELEE)
			ok(bo / big > so / small, "a big weapon hit keeps more of itself than a small one: " .. class .. " " .. level)
		end
	end
	if PRINT_TABLE then
		print("weapon hits: level  class   hit size   hit     after    removed   A")
		for _, r in ipairs(WTABLE) do
			print(string.format("%5d  %-6s  %-9s %6d  %6d  %6.1f%%  %8.2f", r.level, r.class, r.size, r.hit, r.out, r.red, r.A))
		end
	end

	-- REGRESSION (O501): a level 20 character's 15 damage auto attack on a level 20 normal monster keeps at least 60%
	do
		local m = classes.normal(20)
		local out = hit(m, player, 15, COMBAT_PHYSICALDAMAGE, ORIGIN_MELEE)
		ok(out >= 9, "O501 regression: a level 20 character's 15 damage auto attack on a level 20 normal monster keeps at least 60% (kept " .. out .. ")")
		-- and a level 8 hit of 12 and a bow hit of 60 at level 60
		ok(hit(classes.normal(8), player, 12, COMBAT_PHYSICALDAMAGE, ORIGIN_MELEE) >= 7, "O501 regression: a level 8 hit of 12 keeps at least 60%")
		ok(hit(classes.normal(60), player, 60, COMBAT_PHYSICALDAMAGE, ORIGIN_RANGED) >= 36, "O501 regression: a level 60 bow hit of 60 keeps at least 60%")
		-- before the change the same level 20 hit lost 62.5%
		local A20 = C.armourValue(DEF, CFG, 20, "normal")
		ok(C.armourReduction(DEF, A20, 15) > 0.4, "O501: with the class curve a hit of 15 at level 20 lost over 40% (the report)")
	end

	-- a Plated monster: 50% less on top of the weapon armour; a monster with its own physical percent: the three in one cap
	do
		elementLists["Plate Ogre"] = {[COMBAT_PHYSICALDAMAGE] = 0}
		local plated = spawnMonster("Plate Ogre", {level = 100})
		ChaosTierState[plated:getId()] = {tier = "rare", depth = 0, mods = {"plated"}, step = 0}
		local Aw = MD.weaponArmourOf(plated)
		local H = 300
		local out = hit(plated, player, H, COMBAT_PHYSICALDAMAGE, ORIGIN_MELEE)
		near(out, math.floor(H * (1 - C.weaponShare(DEF, Aw, H, 0.55)) * 0.5 + 0.5), 1, "weapon hit on a Plated monster: armour and 50% less")
		elementLists["Stone Colossus"] = {[COMBAT_PHYSICALDAMAGE] = 60}
		local m = spawnMonster("Stone Colossus", {level = 100, boss = true})
		ChaosTierState[m:getId()] = {tier = "boss", depth = 0, mods = {"plated"}, step = 0}
		-- the engine took 60%: raw 1000 arrives as 400; the weapon armour of a boss and Plated add to the 60 without passing 90
		local both = hit(m, player, 400, COMBAT_PHYSICALDAMAGE, ORIGIN_MELEE)
		near(both, math.floor(400 * (1 - C.weaponShare(DEF, MD.weaponArmourOf(m), 400, 0.65)) * 0.5 + 0.5), 1, "weapon hit: the file's percent, armour and Plated")
		-- a file percent of 85, armour and Plated: far over 90, the cap leaves 10% of the raw hit (raw 1000 arrives as 150)
		elementLists["Iron Colossus"] = {[COMBAT_PHYSICALDAMAGE] = 85}
		local iron = spawnMonster("Iron Colossus", {level = 100, boss = true})
		ChaosTierState[iron:getId()] = {tier = "boss", depth = 0, mods = {"plated"}, step = 0}
		local capped = hit(iron, player, 150, COMBAT_PHYSICALDAMAGE, ORIGIN_MELEE)
		ok(capped >= 100 and capped <= 101, "weapon hit: the file's percent, armour and Plated stay inside the 90% cap (raw 1000 -> " .. capped .. ")")
		-- no Plated: 1 - 0.4 x (1 - share): never under 10% of the raw hit either
		local ogre = spawnMonster("Stone Colossus", {level = 100, boss = true})
		local plain = hit(ogre, player, 400, COMBAT_PHYSICALDAMAGE, ORIGIN_MELEE)
		local sh = C.weaponShare(DEF, MD.weaponArmourOf(ogre), 400, 0.65)
		near(plain, math.floor(400 * (1 - sh) + 0.5), 1, "weapon hit on a monster with its own physical percent")
		ok(plain >= 100, "weapon hit: the cap leaves at least 10% of the raw hit")
	end

	-- penetration lowers the weapon share (the same rule as the spell's), a ranged hit too
	do
		local savedMods = ChaosItemMods
		local bonus = {}
		ChaosItemMods = {playerBonus = function(p, key) return (bonus[p:getId()] or {})[key] or 0 end}
		local pen = newPlayer()
		local m = classes.normal(500)
		local H = math.floor(C.weaponHitAtLevel(CFG, 500) + 0.5)
		local base = hit(m, pen, H, COMBAT_PHYSICALDAMAGE, ORIGIN_RANGED)
		bonus[pen:getId()] = {physpen = 10}
		local pe = hit(m, pen, H, COMBAT_PHYSICALDAMAGE, ORIGIN_RANGED)
		near(pe - base, H * 0.10, 1.5, "weapon hit: ten points of penetration give ten points of the hit back")
		bonus[pen:getId()] = {physpen = 90}
		eq(hit(m, pen, H, COMBAT_PHYSICALDAMAGE, ORIGIN_RANGED), H, "weapon hit: penetration beyond the share: nothing taken")
		ChaosItemMods = savedMods
	end

	-- a wand hit (ORIGIN_WAND) and a tick are no armoured weapon hit; a summon hits like its player
	do
		local m = classes.normal(100)
		eq(hit(m, player, 80, COMBAT_PHYSICALDAMAGE, ORIGIN_WAND), 80, "a wand hit is never armoured")
		eq(hit(m, player, 80, COMBAT_FIREDAMAGE, ORIGIN_MELEE), 80, "the element of a weapon hit is not armour")
		local wolf = newMonster("Wolf", {master = player})
		eq(hit(m, wolf, 80, COMBAT_PHYSICALDAMAGE, ORIGIN_MELEE), hit(m, player, 80, COMBAT_PHYSICALDAMAGE, ORIGIN_MELEE), "a summon's weapon hit meets the weapon curve of the monster's level")
	end

	-- a config without the weapon curve and cap is the state before O501: the class curve and no cap
	do
		local savedCurve, savedCaps, savedTargets = CFG.weaponHitCurve, CFG.weaponShareCap, CFG.weaponTarget
		CFG.weaponHitCurve, CFG.weaponShareCap, CFG.weaponTarget = nil, nil, nil
		local m = spawnMonster("Rotling", {level = 100})
		local H = 100
		eq(hit(m, player, H, COMBAT_PHYSICALDAMAGE, ORIGIN_MELEE), math.floor(H * (1 - C.armourReduction(DEF, MD.armourOf(m), H)) + 0.5), "no weapon curve: a weapon hit meets the class curve")
		CFG.weaponHitCurve, CFG.weaponShareCap, CFG.weaponTarget = savedCurve, savedCaps, savedTargets
	end
end

-- ---------------------------------------------------------------- block (Bulwark)
do
	local m = spawnMonster("Rotling", {level = 100})
	ChaosTierState[m:getId()] = {tier = "magic", depth = 0, mods = {"bulwark"}, step = 0} -- magic: no elite resistance bonus
	m.pos = position(1, 1, 7)
	-- the roll is math.random(100) <= 50
	fixRoll(50)
	local p, s = hit(m, player, 500, COMBAT_PHYSICALDAMAGE, ORIGIN_MELEE, 200, COMBAT_FIREDAMAGE)
	eq(p, 0, "block: a roll of 50 blocks the hit")
	eq(s, 0, "block: the element part too")
	eq(m.pos.effects[#m.pos.effects], CONST_ME_BLOCKHIT, "block: the block effect")
	eq(hit(m, player, 500, COMBAT_PHYSICALDAMAGE, ORIGIN_RANGED), 0, "block: a ranged weapon hit")
	fixRoll(51)
	ok(hit(m, player, 500, COMBAT_PHYSICALDAMAGE, ORIGIN_MELEE) > 0, "block: a roll of 51 does not")
	fixRoll(1)
	ok(hit(m, player, 500, COMBAT_PHYSICALDAMAGE, ORIGIN_SPELL) > 0, "block: never a spell")
	eq(hit(m, player, 500, COMBAT_FIREDAMAGE, ORIGIN_SPELL), 500, "block: never an elemental spell")
	eq(hit(m, player, 500, COMBAT_FIREDAMAGE, ORIGIN_CONDITION), 500, "block: never a tick")
	eq(hit(m, player, 500, COMBAT_PHYSICALDAMAGE, ORIGIN_CONDITION), 500, "block: never a physical tick")
	-- the cap
	CFG.mods.block.chance = 90
	fixRoll(75)
	eq(hit(m, player, 500, COMBAT_PHYSICALDAMAGE, ORIGIN_MELEE), 0, "block: 90% is capped at 75: 75 blocks")
	fixRoll(76)
	ok(hit(m, player, 500, COMBAT_PHYSICALDAMAGE, ORIGIN_MELEE) > 0, "block: 90% is capped at 75: 76 does not")
	CFG.mods.block.chance = 50
	freeRoll()
	-- a monster without the modifier never blocks
	local plain = spawnMonster("Rotling", {level = 100})
	fixRoll(1)
	ok(hit(plain, player, 500, COMBAT_PHYSICALDAMAGE, ORIGIN_MELEE) > 0, "no Bulwark: no block")
	freeRoll()
end

-- ---------------------------------------------------------------- the modifiers of the ranks: names, state, the draw
do
	for _, key in ipairs({"emberforged", "frostforged", "stormforged", "plated", "resistant", "ruthless", "bulwark"}) do
		ok(ChaosMods[key] ~= nil and type(ChaosMods[key].name) == "string", "modifier " .. key .. " is in ChaosMods")
		ok(C.MOD[key] ~= nil, "modifier " .. key .. " has a rule")
		ok(ChaosMods[key] and ChaosMods[key].shader and ChaosMods[key].shader <= 17, "modifier " .. key .. " uses a shader the client has")
	end
	eq(ChaosMods.juggernaut.hp, 1.6, "the family 'more health' is Juggernaut and is kept")
	-- every new modifier can be rolled, Resistant draws an element from the list
	local seen, drawn = {}, {}
	ChaosMonsterDefenceConfig.resistElements = CFG.resistElements
	for i = 1, 3000 do
		local m = spawnMonster("Rotling", {level = 100, hp = 1000})
		if ChaosApplyTier(m, "legendary") then
			local s = ChaosTierState[m:getId()]
			for _, key in ipairs(s.mods) do
				seen[key] = true
				if key == "resistant" then
					drawn[s.draw.resistant] = true
					ok(s.draw and s.draw.resistant, "Resistant: an element is drawn")
				end
			end
			if seen.emberforged and seen.frostforged and seen.stormforged and seen.plated and seen.resistant and seen.ruthless
					and seen.bulwark then
				break
			end
		end
	end
	for _, key in ipairs({"emberforged", "frostforged", "stormforged", "plated", "resistant", "ruthless", "bulwark"}) do
		ok(seen[key], "modifier " .. key .. " is rolled")
	end
	local listed = {}
	for _, e in ipairs(CFG.resistElements) do
		listed[e] = true
	end
	for e in pairs(drawn) do
		ok(listed[e], "Resistant draws from resistElements: " .. e)
	end
	ok(C.modSet({"juggernaut", "blazing"}) == nil, "a monster without rank modifiers has no set")
	local set = C.modSet({"plated", "ruthless", "bulwark", "frostforged", "resistant"}, {resistant = "holy"})
	ok(set.physReduction and set.crit and set.block and set.added == "ice" and set.resist == "holy", "modSet")
	ok(C.modSet({"resistant"}).resist == nil, "Resistant without a draw does nothing")
end

-- ---------------------------------------------------------------- hits a tiered monster deals: Ruthless and the extra element
do
	local hitEvent = events.ChaosTierHit
	ok(hitEvent ~= nil, "ChaosTierHit exists")
	local function attackerWith(mods, draw)
		local m = spawnMonster("Rotling", {level = 100})
		ChaosTierState[m:getId()] = {tier = "magic", depth = 0, mods = mods, step = 0, draw = draw}
		return m
	end
	local function onPlayer(attacker, p, pt, s, st, origin, who)
		who = who or player
		local rp, rpt, rs, rst = hitEvent.onHealthChange(who, attacker, p, pt, s or 0, st or COMBAT_NONE, origin)
		return rp, rpt, rs, rst
	end
	-- the rank multiplier alone (x1.30 magic)
	local plain = attackerWith({})
	near(onPlayer(plain, 1000, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, ORIGIN_MELEE), 1300, 1, "magic hit x1.30")
	-- Ruthless: 20% of hits deal 150%
	local ruthless = attackerWith({"ruthless"})
	fixRoll(20)
	near(onPlayer(ruthless, 1000, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, ORIGIN_MELEE), 1950, 1, "Ruthless: a roll of 20 is critical (1300 x 1.5)")
	fixRoll(21)
	near(onPlayer(ruthless, 1000, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, ORIGIN_MELEE), 1300, 1, "Ruthless: a roll of 21 is not")
	fixRoll(1)
	near(onPlayer(ruthless, 1000, COMBAT_FIREDAMAGE, 0, COMBAT_NONE, ORIGIN_SPELL), 1950, 1, "Ruthless: a spell can be critical too")
	near(onPlayer(ruthless, 1000, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, ORIGIN_CONDITION), 1300, 1, "Ruthless: a tick is never critical")
	freeRoll()
	-- the mana shield part (the same event of manashield.lua): Ruthless counts
	local provider = ChaosManaShield.providers.tiers
	fixRoll(1)
	near(provider.hit(player, ruthless, 1000, {origin = ORIGIN_MELEE}), 1950, 1, "mana shield part: Ruthless")
	near(provider.hit(player, ruthless, 1000, {origin = ORIGIN_CONDITION}), 1300, 1, "mana shield part: no critical tick")
	freeRoll()
	-- Emberforged: 50% of the physical hit as fire; the player's absorb comes off the added part
	local ember = attackerWith({"emberforged"})
	local p, pt, s, st = onPlayer(ember, 1000, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, ORIGIN_MELEE)
	near(p, 1300, 1, "Emberforged: the physical part is the rank hit")
	near(s, 650, 1, "Emberforged: 50% of it as fire")
	eq(st, COMBAT_FIREDAMAGE, "Emberforged: fire")
	eq(pt, COMBAT_PHYSICALDAMAGE, "Emberforged: the primary type stays")
	local _, _, s2, st2 = onPlayer(attackerWith({"frostforged"}), 1000, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, ORIGIN_RANGED)
	near(s2, 650, 1, "Frostforged: 50% as ice (a ranged hit)")
	eq(st2, COMBAT_ICEDAMAGE, "Frostforged: ice")
	local _, _, s3, st3 = onPlayer(attackerWith({"stormforged"}), 1000, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, ORIGIN_MELEE)
	near(s3, 650, 1, "Stormforged: 50% as energy")
	eq(st3, COMBAT_ENERGYDAMAGE, "Stormforged: energy")
	-- never to a tick, a spell, a non-physical hit or a taken secondary
	local _, _, sx = onPlayer(ember, 1000, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, ORIGIN_CONDITION)
	eq(sx, 0, "extra element: not on a tick")
	_, _, sx = onPlayer(ember, 1000, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, ORIGIN_SPELL)
	eq(sx, 0, "extra element: not on a spell")
	_, _, sx = onPlayer(ember, 1000, COMBAT_FIREDAMAGE, 0, COMBAT_NONE, ORIGIN_MELEE)
	eq(sx, 0, "extra element: only a physical hit")
	local _, _, sy, sty = onPlayer(ember, 1000, COMBAT_PHYSICALDAMAGE, 200, COMBAT_ICEDAMAGE, ORIGIN_MELEE)
	eq(sty, COMBAT_ICEDAMAGE, "extra element: a secondary that is taken stays")
	near(sy, 260, 1, "extra element: the taken secondary is only the rank multiplier")
	-- the absorb of the player for the added element: worn items, each on what the previous left
	abilityOf[101] = {absorbPercent = {0, 0, 0, 40, 0, 0, 0, 0, 0, 0, 0, 0}} -- index 4 = fire (8 = 2^3)
	abilityOf[102] = {absorbPercent = {0, 0, 0, 25, 0, 0, 0, 0, 0, 0, 0, 0}}
	local hero = newPlayer({[1] = {getId = function() return 101 end}, [4] = {getId = function() return 102 end}})
	near(MD.playerAbsorb(hero, COMBAT_FIREDAMAGE), 55, 1e-9, "playerAbsorb: 40% then 25% of the rest = 55%")
	near(MD.playerAbsorb(hero, COMBAT_ICEDAMAGE), 0, 1e-9, "playerAbsorb: another element 0")
	local _, _, sz, stz = onPlayer(ember, 1000, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, ORIGIN_MELEE, hero)
	eq(stz, COMBAT_FIREDAMAGE, "extra element with absorb: fire")
	near(sz, 292, 2, "extra element with absorb: 650 x 0.45")
	-- O464: with the player defence layer on the added part keeps its size here (the layer reduces it by the resistance of its
	-- group once, as the next healthchange event): nothing is taken twice
	ChaosPlayerDefence = {active = function() return true end}
	near(MD.playerAbsorb(hero, COMBAT_FIREDAMAGE), 0, 1e-9, "playerAbsorb: 0 while the layer is on")
	local _, _, sl = onPlayer(ember, 1000, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, ORIGIN_MELEE, hero)
	near(sl, 650, 2, "extra element with the layer on: 650, not reduced here")
	ChaosPlayerDefence = nil
	abilityOf[103] = {absorbPercent = {0, 0, 0, 100, 0, 0, 0, 0, 0, 0, 0, 0}}
	local immune = newPlayer({[1] = {getId = function() return 103 end}})
	local _, _, si, sti = onPlayer(ember, 1000, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, ORIGIN_MELEE, immune)
	eq(si, 0, "extra element: 100% absorb leaves nothing")
	-- a hit on something that is no player: no modifier effect
	local monsterTarget = {isPlayer = function() return false end, getId = function() return 5 end}
	local _, _, sm = onPlayer(ember, 1000, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, ORIGIN_MELEE, monsterTarget)
	eq(sm, 0, "extra element: only against a player")
	-- the negative sign is kept
	local pn, _, sn = onPlayer(ember, -1000, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, ORIGIN_MELEE)
	ok(pn < 0 and sn < 0, "extra element: negative values stay negative")
end

-- ---------------------------------------------------------------- the registration order
do
	local m = spawnMonster("Dragon", {level = 100, hp = 1000})
	eq(m.order[1], "ChaosMonsterDefence", "the layer is the first event registered on a monster")
	-- a tiered monster gets ChaosModTaken at its tier: behind the layer
	ok(ChaosApplyTier(m, "rare"), "the monster is tiered")
	local posDef, posTaken
	for i, name in ipairs(m.order) do
		posDef = name == "ChaosMonsterDefence" and i or posDef
		posTaken = name == "ChaosModTaken" and i or posTaken
	end
	ok(posDef and posTaken and posDef < posTaken, "the layer runs before the tier modifiers (ChaosModTaken)")
	-- the spawn callback index is below the name callback of monster_tiers.lua (-100) and the natural roll (0)
	local firstIndex = spawnCallbacks[1].index
	ok(firstIndex <= -150, "the first onSpawn callback is at -150 or lower: " .. tostring(firstIndex))
	-- a monster that never passed onSpawn gets the layer at the first target
	local late = newMonster("Summoned Thing", {})
	ok(not late.events.ChaosMonsterDefence, "a created monster: no layer yet")
	for _, cb in ipairs(targetCallbacks) do
		cb.fn(player, late)
	end
	ok(late.events.ChaosMonsterDefence, "the first hit that targets it registers the layer")
end

-- ---------------------------------------------------------------- bosses: every kind the code treats as one
do
	local function classOf(m) return MD.classOf(m) end
	eq(classOf(spawnMonster("Rotling", {level = 100, boss = true})), "boss", "the type flag isboss")
	local guardian = spawnMonster("Rotling", {level = 100})
	ChaosRift = {monsterRun = {[guardian:getId()] = {bossIds = {[guardian:getId()] = true}}}}
	eq(classOf(guardian), "boss", "a rift guardian")
	local omen = spawnMonster("Rotling", {level = 100})
	ChaosRift.monsterRun[omen:getId()] = {omen = "storm", bossIds = {[omen:getId()] = true}}
	eq(classOf(omen), "boss", "an Omen guardian")
	local pack = spawnMonster("Rotling", {level = 100})
	ChaosRift.monsterRun[pack:getId()] = {bossIds = {}}
	eq(classOf(pack), "normal", "a rift pack monster")
	ChaosRift = nil
	local tower = spawnMonster("Rotling", {level = 100})
	ChaosTowerRun = {isBoss = function(mon) return mon:getId() == tower:getId() end}
	eq(classOf(tower), "boss", "a tower boss")
	ChaosTowerRun = nil
	local world = spawnMonster("Rotling", {level = 100})
	ChaosWorldBoss = {state = {bossId = world:getId()}}
	eq(classOf(world), "boss", "the world boss")
	ChaosWorldBoss = nil
	local pillar = spawnMonster("Rotling", {level = 100})
	ChaosWaystoneTiers = {entryOf = function(mon) return {boss = mon:getId() == pillar:getId()} end}
	eq(classOf(pillar), "boss", "a waystone tier boss")
	ChaosWaystoneTiers = nil
	-- the boss list of ChaosTiers (a cfg.bosses name) and the nemesis tier
	local nem = spawnMonster("Rotling", {level = 100})
	ChaosTierState[nem:getId()] = {tier = "nemesis", depth = 0, mods = {}, step = 0}
	eq(classOf(nem), "elite", "a Nemesis is an elite")
	local magic = spawnMonster("Rotling", {level = 100})
	ChaosTierState[magic:getId()] = {tier = "magic", depth = 0, mods = {}, step = 0}
	eq(classOf(magic), "normal", "a magic monster takes the normal armour")
end

if PRINT_TABLE then
	return
end
-- ---------------------------------------------------------------- trainers (O573)
-- a training monster defends like a normal / elite / boss monster of the hitting player's level (trainer_meter.lua sets the
-- two hooks the layer asks); with the profile off it keeps its own level and rank; every other monster is untouched
do
	local realCE = CreatureEvent
	CreatureEvent = function(name)
		local o = {name = name}
		function o:type() end
		function o:register() end
		return o
	end
	local realGE = GlobalEvent
	GlobalEvent = function(name)
		local o = {}
		function o:interval() end
		function o:register() end
		return o
	end
	local realJson = json
	json = json or {encode = function() return "" end, decode = function() return nil end}
	dofile("data/scripts/chaos/trainer_meter.lua")
	CreatureEvent, GlobalEvent, json = realCE, realGE, realJson
	local TC = ChaosTrainerMeter.cfg
	local function playerAt(level)
		local p = newPlayer()
		p.getLevel = function() return level end
		return p
	end
	local function dmg(monster, attacker, value, origin)
		local pd = hit(monster, attacker, value, COMBAT_PHYSICALDAMAGE, origin)
		return pd
	end
	local dummy = spawnMonster("Training Dummy", {level = 5})
	ok(dummy.events.ChaosMonsterDefence, "a trainer gets the layer like every monster")
	eq(MD.classOf(dummy), "normal", "the default profile: a normal monster")
	for _, lv in ipairs({100, 500, 1000}) do
		for _, origin in ipairs({ORIGIN_MELEE, ORIGIN_SPELL}) do
			local wyrm = spawnMonster("Wyrm", {level = lv})
			local who = playerAt(lv)
			eq(dmg(dummy, who, 1000, origin), dmg(wyrm, who, 1000, origin),
				"the trainer takes what a normal monster of the player's level " .. lv .. " takes (origin " .. origin .. ")")
		end
	end
	ok(dmg(dummy, playerAt(100), 1000, ORIGIN_SPELL) ~= dmg(dummy, playerAt(1000), 1000, ORIGIN_SPELL),
		"the armour follows the level of the player that hits")
	ok(dmg(dummy, playerAt(500), 1000, ORIGIN_SPELL) < 1000, "a trainer has armour now")
	-- a summon's hit counts for its master's level
	local master = playerAt(700)
	local wolf = newMonster("Wolf", {master = master})
	eq(dmg(dummy, wolf, 1000, ORIGIN_SPELL), dmg(spawnMonster("Wyrm", {level = 700}), master, 1000, ORIGIN_SPELL),
		"a summon is measured at its master's level")
	-- a player with no level to read: level 1, no error
	local blank = newPlayer()
	ok(dmg(dummy, blank, 1000, ORIGIN_SPELL) <= 1000, "a player without getLevel")
	-- a profile of its own: a boss of a fixed level
	TC.byName["boss trainer"] = {class = "boss", level = 300}
	local bt = spawnMonster("Boss Trainer", {level = 5})
	eq(MD.classOf(bt), "boss", "per name class")
	local boss300 = spawnMonster("Pestrogh", {level = 300, boss = true})
	eq(dmg(bt, playerAt(10), 1000, ORIGIN_SPELL), dmg(boss300, playerAt(10), 1000, ORIGIN_SPELL),
		"a boss profile at a fixed level takes what a level 300 boss takes, whoever hits")
	TC.byName["elite trainer"] = {class = "elite"}
	local et = spawnMonster("Elite Trainer", {level = 5})
	eq(MD.classOf(et), "elite", "an elite profile")
	ok(MD.effectiveResist(et, COMBAT_FIREDAMAGE, 0) >= MD.effectiveResist(dummy, COMBAT_FIREDAMAGE, 0),
		"an elite also gets the rank resistance bonus")
	-- off: the trainer keeps its own level and rank
	TC.profile.enabled = false
	local plain = spawnMonster("Training Monk", {level = 200})
	eq(MD.classOf(plain), "normal", "profile off: normal")
	eq(dmg(plain, playerAt(900), 1000, ORIGIN_SPELL), dmg(spawnMonster("Wyrm", {level = 200}), playerAt(900), 1000, ORIGIN_SPELL),
		"profile off: the trainer's own level, whoever hits")
	TC.profile.enabled = true
	-- no other monster is touched
	local wyrm = spawnMonster("Wyrm", {level = 300})
	ok(wyrm.events.ChaosMonsterDefence and MD.trainerProfile(wyrm) == nil, "a normal monster has no trainer profile")
end

print(string.format("monster defence tests: %d checks, %d failed", checks, fails))
if fails > 0 then
	os.exit(1)
end
