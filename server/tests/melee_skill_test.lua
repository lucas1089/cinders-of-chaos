-- Run from the server/ folder: luajit tests/melee_skill_test.lua (no engine needed; CI runs it with luajit and lua5.3)
-- Covers ONE melee skill (owner debug item 46, server/README.md "One melee skill"):
--   * melee_skill_core.lua: the best of sword / club / axe, the hit multiplier (the ratio of the two maximum hits of the
--     engine's formula), the training route
--   * melee_skill.lua (the training callback) against a mocked player: the tries of a weaker melee skill go to the best
--     one, once, through the same chain; other skills, a tie and a zero are left alone
--   * weapon_styles.lua (the hit): a sword, axe or club hit is the hit of the best melee skill; a two-handed melee hit
--     gets the level's style factor; a one-handed hit with the best skill is untouched; a wand hit is scaled by the
--     magic level (weapon_skill_core.lua)
--   * the spells' helper ChaosSpell.meleeSkillLevel and the vocations' equal melee multipliers (chaos_vocations*.xml)
dofile("data/scripts/chaos/melee_skill_core.lua")
local M = ChaosMeleeSkill

local fails, checks = 0, 0
local function ok(cond, what)
	checks = checks + 1
	if not cond then
		fails = fails + 1
		print("FAIL " .. what)
	end
end
local function eq(a, b, what)
	ok(a == b, what .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end
local function near(a, b, tol, what)
	ok(math.abs(a - b) <= tol, what .. ": " .. tostring(a) .. " ~ " .. tostring(b))
end

-- ------------------------------------------------------------------ the core
local name, value = M.best({sword = 100, club = 40, axe = 70})
eq(name, "sword", "best: the sword"); eq(value, 100, "best: its level")
name = M.best({sword = 30, club = 40, axe = 70})
eq(name, "axe", "best: the axe")
name = M.best({sword = 50, club = 50, axe = 50})
eq(name, "sword", "a tie: the first")
name = M.best({sword = 50, club = 50, axe = 50}, {sword = 10, club = 60, axe = 30})
eq(name, "club", "a tie in level: the percent decides")
eq((M.best({})), "sword", "no levels: sword at 0")
-- the engine's formula (Weapons::getMaxWeaponDamage): level 100, skill 100, attack 60: 20 + 26 x 20 x 1.03
near(M.maxHit(100, 100, 60), 20 + 26 * 20 * 1.03, 1e-9, "maxHit")
near(M.maxHit(100, 100, 60, 2), 20 + 26 * 20 * 1.03 / 2, 1e-9, "maxHit, defensive stance")
eq(M.hitMultiplier(100, 100, 100, 60, 1), 1, "own skill is the best: 1")
eq(M.hitMultiplier(100, 120, 100, 60, 1), 1, "own skill above: 1")
eq(M.hitMultiplier(100, 10, 100, 0, 1), 1, "no attack: 1")
near(M.hitMultiplier(100, 10, 100, 60, 1), M.maxHit(100, 100, 60) / M.maxHit(100, 10, 60), 1e-9, "the ratio of the two maximum hits")
ok(M.hitMultiplier(100, 10, 100, 60, 1) > 5, "a fresh axe with a trained sword hits several times harder than before")
-- the level term does not scale with the skill: a hit multiplier is below the skill ratio
ok(M.hitMultiplier(300, 10, 20, 60, 1) < 20 / 10, "below the skill ratio (the level term)")
eq(M.routeTarget("axe", {sword = 100, club = 10, axe = 20}, {}), "sword", "axe tries go to the sword")
eq(M.routeTarget("sword", {sword = 100, club = 10, axe = 20}, {}), nil, "sword tries stay")
eq(M.routeTarget("axe", {sword = 50, club = 50, axe = 50}, {sword = 0, club = 0, axe = 0}), nil, "a tie: stay (no ping-pong)")
eq(M.routeTarget("axe", {sword = 50, club = 50, axe = 50}, {sword = 40, club = 0, axe = 10}), "sword", "same level, less percent: go")
eq(M.routeTarget("distance", {sword = 100, club = 10, axe = 20}, {}), nil, "distance is no melee skill")
eq(M.routeTarget(0, {sword = 100, club = 10, axe = 20}, {}), nil, "fist is no melee skill")

-- ------------------------------------------------------------------ engine constants and mocks
SKILL_FIST, SKILL_CLUB, SKILL_SWORD, SKILL_AXE, SKILL_DISTANCE, SKILL_SHIELD = 0, 1, 2, 3, 4, 5
WEAPON_NONE, WEAPON_SWORD, WEAPON_CLUB, WEAPON_AXE, WEAPON_SHIELD, WEAPON_DISTANCE, WEAPON_WAND, WEAPON_AMMO = 0, 1, 2, 3, 4, 5, 6, 7
WEAPON_QUIVER = 8
CONST_SLOT_LEFT, CONST_SLOT_RIGHT = 6, 5
SLOTP_TWO_HAND = 2048
ITEM_ATTRIBUTE_ATTACK = 2
COMBAT_NONE, COMBAT_PHYSICALDAMAGE, COMBAT_HEALING = 0, 1, 128
ORIGIN_NONE, ORIGIN_SPELL, ORIGIN_MELEE, ORIGIN_RANGED = 0, 2, 3, 4
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

-- ------------------------------------------------------------------ the training callback
local callbacks = {}
EventCallback = setmetatable({}, {__newindex = function(t, k, v) rawset(t, k, v) end})
local registered = {}
setmetatable(EventCallback, {__index = function() return nil end})
-- each `local cb = EventCallback` in the scripts is the same table: the script sets onGainSkillTries on it and
-- registers; capture both
EventCallback.register = function(self, index) registered.index = index end
dofile("data/scripts/chaos/melee_skill.lua")
local train = EventCallback.onGainSkillTries
ok(type(train) == "function", "the callback is set")
eq(registered.index, 2, "registered at index 2 (after the class lock, before the multipliers)")

local function player(levels, percents)
	local p = {levels = levels, percents = percents or {}, added = {}}
	function p:getSkillLevel(id) return self.levels[id] or 10 end
	function p:getSkillPercent(id) return self.percents[id] or 0 end
	function p:addSkillTries(id, tries)
		self.added[#self.added + 1] = {id, tries}
		return train(self, id, tries) -- the engine runs the same chain on the rerouted tries
	end
	return p
end
local p = player({[SKILL_SWORD] = 100, [SKILL_AXE] = 20, [SKILL_CLUB] = 10})
eq(train(p, SKILL_AXE, 50), 0, "axe tries: zero left for the axe")
eq(#p.added, 1, "and added once to the best")
eq(p.added[1][1], SKILL_SWORD, "to the sword")
eq(p.added[1][2], 50, "all of them")
p = player({[SKILL_SWORD] = 100, [SKILL_AXE] = 20, [SKILL_CLUB] = 10})
eq(train(p, SKILL_SWORD, 50), 50, "sword tries stay")
eq(#p.added, 0, "nothing added")
eq(train(p, SKILL_DISTANCE, 50), 50, "distance tries stay")
eq(train(p, SKILL_FIST, 50), 50, "fist tries stay")
eq(train(p, SKILL_AXE, 0), 0, "zero tries: nothing")
eq(#p.added, 0, "nothing added for zero")
p = player({[SKILL_SWORD] = 10, [SKILL_AXE] = 10, [SKILL_CLUB] = 10})
eq(train(p, SKILL_CLUB, 7), 7, "a fresh character: the skill it swings with trains")
eq(#p.added, 0, "no rerouting on a tie")
-- the rerouted call does not route again (the chain re-enters the callback)
p = player({[SKILL_SWORD] = 100, [SKILL_AXE] = 120, [SKILL_CLUB] = 10})
eq(train(p, SKILL_SWORD, 30), 0, "sword tries go to the better axe")
eq(#p.added, 1, "once")
eq(p.added[1][1], SKILL_AXE, "to the axe")
-- a failing addSkillTries keeps the tries where they were
p = player({[SKILL_SWORD] = 100, [SKILL_AXE] = 20, [SKILL_CLUB] = 10})
function p:addSkillTries() error("boom") end
local real_print = print
print = function() end
eq(train(p, SKILL_AXE, 9), 9, "an error in the engine call: the tries are not lost")
print = real_print

-- ------------------------------------------------------------------ the hit (weapon_styles.lua)
local styleEvents, timers = {}, {}
CreatureEvent = function(n)
	local o = {}
	o.register = function() styleEvents[n] = o end
	return o
end
EventCallback = setmetatable({}, {__newindex = function() end, __index = function(_, k)
	if k == "register" then return function() end end end})
createCombatArea = function(t) return t end
addEvent = function(fn, ms, ...) timers[#timers + 1] = fn end
doAreaCombat = function() end
doTargetCombatHealth = function() end
ChaosCombatFx = {crit = function() end}
ChaosItemModsCache = {}
Game = {getSpectators = function() return {} end}

local ITEMS = {
	[1] = {weaponType = WEAPON_SWORD, attack = 50, slot = 0},
	[2] = {weaponType = WEAPON_AXE, attack = 50, slot = 0},
	[3] = {weaponType = WEAPON_AXE, attack = 53, slot = SLOTP_TWO_HAND},
	[4] = {weaponType = WEAPON_CLUB, attack = 50, slot = 0},
	[5] = {weaponType = WEAPON_SHIELD, attack = 0, slot = 0},
	[6] = {weaponType = WEAPON_WAND, attack = 0, slot = 0}
}
function ItemType(id)
	local t = ITEMS[id]
	return {
		getId = function() return id end,
		getWeaponType = function() return t.weaponType end,
		getSlotPosition = function() return t.slot end,
		getAttack = function() return t.attack end,
		getAmmoType = function() return 0 end,
		getName = function() return "item" .. id end,
		isContainer = function() return false end,
		isStackable = function() return false end
	}
end
local function newItem(id, attackAttr)
	return {
		getId = function() return id end,
		getAttribute = function(_, attr) if attr == ITEM_ATTRIBUTE_ATTACK then return attackAttr or 0 end return 0 end
	}
end

dofile("data/scripts/chaos/weapon_styles.lua")
local hit = styleEvents.ChaosWeaponStyle
ok(hit ~= nil, "the weapon style event is registered")

local function attacker(level, skills, mode)
	local a = {slots = {}, level = level, skills = skills, mode = mode or 1}
	function a:getId() return 1 end
	function a:isPlayer() return true end
	function a:getLevel() return self.level end
	function a:getSlotItem(s) return self.slots[s] end
	function a:getEffectiveSkillLevel(id) return self.skills[id] or 10 end
	function a:getFightMode() return self.mode end
	a.storage = {}
	function a:getStorageValue(k) return self.storage[k] or -1 end
	return a
end
local victim = {getId = function() return 2 end, isPlayer = function() return false end, isMonster = function() return true end}
local function swing(a, damage, origin)
	return (hit.onHealthChange(victim, a, damage, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, origin or ORIGIN_MELEE))
end

-- a sword with the best skill: untouched
local a = attacker(100, {[SKILL_SWORD] = 100, [SKILL_AXE] = 20, [SKILL_CLUB] = 10})
a.slots[CONST_SLOT_LEFT] = newItem(1)
eq(swing(a, -100), -100, "a one-handed sword with the best skill: the hit is the engine's")
-- an axe with a trained sword: the hit of the sword skill
a.slots[CONST_SLOT_LEFT] = newItem(2)
local want = M.hitMultiplier(100, 20, 100, 50, 1)
eq(swing(a, -100), -math.floor(100 * want + 0.5), "a one-handed axe hits with the sword skill")
ok(want > 3, "(by a lot: " .. string.format("%.2f", want) .. ")")
-- the rolled attack counts
a.slots[CONST_SLOT_LEFT] = newItem(2, 70)
eq(swing(a, -100), -math.floor(100 * M.hitMultiplier(100, 20, 100, 70, 1) + 0.5), "a rolled attack attribute is the item's attack")
-- the stance counts
a.slots[CONST_SLOT_LEFT] = newItem(4)
a.mode = 3
eq(swing(a, -100), -math.floor(100 * M.hitMultiplier(100, 10, 100, 50, 2.0) + 0.5), "the defensive stance factor")
a.mode = 1
-- melee skills of the best being the weapon's own after a skill item: effective levels count
a.skills[SKILL_CLUB] = 100
eq(swing(a, -100), -100, "an equal skill: untouched")
-- a spell's scripted weapon strike (ChaosSpell.weaponStrike sets storage 7100028 during the call) was worked out with the
-- best skill already: no second multiplication
a.skills[SKILL_CLUB] = 10
a.slots[CONST_SLOT_LEFT] = newItem(4)
a.storage[7100028] = 1
eq(swing(a, -100), -100, "a scripted weapon strike is left alone")
a.storage[7100028] = 0
ok(swing(a, -100) < -100, "and a real swing a moment later is not")
-- a spell strike, a ranged hit and a heal are not melee weapon hits
a.skills[SKILL_CLUB] = 10
eq(swing(a, -100, ORIGIN_SPELL), -100, "a spell is untouched")
eq((hit.onHealthChange(victim, a, 100, COMBAT_HEALING, 0, COMBAT_NONE, ORIGIN_MELEE)), 100, "a heal is untouched")
-- a two-handed axe: the skill rule, then the level's style factor
a.slots[CONST_SLOT_LEFT] = newItem(3)
local W = ChaosWeaponBalance
local f = W.factor("twoHanded", 100)
local expect = math.floor(100 * M.hitMultiplier(100, 20, 100, 53, 1) + 0.5)
expect = math.floor(expect * f + 0.5)
eq(swing(a, -100), -expect, "a two-handed axe: the best skill, then the style factor of the level")
-- with the best skill: only the style factor
a.skills[SKILL_AXE] = 100
eq(swing(a, -100), -math.floor(100 * f + 0.5), "a two-handed axe with the best skill: the style factor alone")
ok(f > 1.3 and f < 1.6, "the two-handed factor is below the old flat 1.6 (" .. string.format("%.3f", f) .. ")")
-- no weapon: nothing
local bare = attacker(100, {[SKILL_SWORD] = 100})
eq(swing(bare, -100), -100, "no weapon in the hands")

-- a wand or rod (weapon_skill_core.lua): the engine's flat hit (melee origin in this engine) x the magic level against
-- the typical one of the level; no melee skill rule, no style factor
local WS = ChaosWeaponSkill
local mage = attacker(300, {})
mage.ml = 100
function mage:getMagicLevel() return self.ml end
mage.slots[CONST_SLOT_LEFT] = newItem(6)
eq(swing(mage, -100), -100, "a wand at the typical magic level of level 300: the engine's hit")
mage.ml = 140
eq(swing(mage, -100), -math.floor(100 * WS.wandFactor(300, 140) + 0.5), "a higher magic level hits harder")
ok(swing(mage, -100) < -110, "(by more than 10%)")
mage.ml = 60
eq(swing(mage, -100), -math.floor(100 * WS.wandFactor(300, 60) + 0.5), "a lower magic level hits less")
ok(swing(mage, -100) > -90, "(by more than 10%)")
eq(swing(mage, -100, ORIGIN_SPELL), -100, "a spell with a wand in hand is untouched")
mage.storage[7100028] = 1
eq(swing(mage, -100), -100, "a scripted strike is untouched")
mage.storage[7100028] = 0

-- ------------------------------------------------------------------ the spells' helper
ChaosSpell = {}
do -- the two helpers, cut out of the spell library (it needs a whole engine to load)
	local f3 = assert(io.open("data/spells/chaos/_common.lua", "r"))
	local source = f3:read("*a")
	f3:close()
	local from = source:find("function ChaosSpell.bestMeleeSkill", 1, true)
	local to = source:find("function ChaosSpell.spectators", 1, true)
	assert(from and to and to > from, "the helpers are in _common.lua")
	assert(load(source:sub(from, to - 1)))()
	ok(source:find("return ChaosSpell.meleeSkillLevel(player) * ChaosSpell.meleeAttack(player)", 1, true) ~= nil,
		"bladePower uses the melee skill")
	ok(source:find("math.max(ChaosSpell.meleeSkillLevel(player), player:getEffectiveSkillLevel(SKILL_DISTANCE))", 1, true) ~= nil,
		"shurikenPower uses the melee skill")
	local g = assert(io.open("data/spells/chaos/_monk.lua", "r"))
	local monk = g:read("*a")
	g:close()
	ok(monk:find("ChaosSpell.meleeSkillLevel(player) * math.max(20, itemAttack(item))", 1, true) ~= nil, "the Monk's staff strike uses the melee skill")
end
local sp = attacker(100, {[SKILL_SWORD] = 30, [SKILL_AXE] = 80, [SKILL_CLUB] = 55})
eq(ChaosSpell.bestMeleeSkill(sp), SKILL_AXE, "the spells' best melee skill")
eq(ChaosSpell.meleeSkillLevel(sp), 80, "the level a melee spell uses")

-- ChaosSpell.weaponStrike marks its strike in the storage the hit reads, and always unmarks it
do
	local f4 = assert(io.open("data/spells/chaos/_common.lua", "r"))
	local source = f4:read("*a")
	f4:close()
	local from = source:find("function ChaosSpell.weaponStrike", 1, true)
	local to = source:find("-- Make monsters around `pos`", 1, true)
	assert(from and to and to > from, "weaponStrike is in _common.lua")
	ChaosSpell.canAttack = function() return true end
	ChaosSpell.thiefLevelScale = function() return 1 end
	assert(load(source:sub(from, to - 1)))()
	ORIGIN_MELEE = 3
	COMBAT_PHYSICALDAMAGE = 1
	local caster = attacker(100, {})
	local seen
	doTargetCombat = function(c, t, ct, mn, mx, effect, origin)
		seen = {c:getStorageValue(7100028), mn, mx, origin}
		return true
	end
	function caster:setStorageValue(k, v) self.storage[k] = v end
	eq(ChaosSpell.weaponStrike(caster, {}, 10.6, 20.2, 0), true, "the strike goes through")
	eq(seen[1], 1, "the storage is 1 during the strike")
	eq(seen[2], -10, "the numbers are the caller's"); eq(seen[3], -20, "and its maximum"); eq(seen[4], ORIGIN_MELEE, "melee origin")
	eq(caster:getStorageValue(7100028), 0, "and 0 after it")
	doTargetCombat = function() error("boom") end
	local fine, err = pcall(ChaosSpell.weaponStrike, caster, {}, 1, 2, 0)
	ok(not fine and tostring(err):find("boom", 1, true) ~= nil, "an error is raised again")
	eq(caster:getStorageValue(7100028), 0, "but the storage is unmarked")
end

-- ------------------------------------------------------------------ the vocations: one multiplier for the three
for _, file in ipairs({"chaos_vocations.xml", "chaos_vocations_monk.xml", "chaos_vocations_necro.xml", "chaos_vocations_templar.xml"}) do
	local f2 = assert(io.open("data/XML/" .. file, "r"))
	local text = f2:read("*a")
	f2:close()
	text = text:gsub("<!%-%-.-%-%->", "")
	for vocation in text:gmatch("<vocation%s.-</vocation>") do
		local vname = vocation:match('name="([^"]+)"')
		local m = {}
		for id, mult in vocation:gmatch('<skill id="(%d)" multiplier="([%d.]+)"') do
			m[tonumber(id)] = tonumber(mult)
		end
		ok(m[1] and m[1] == m[2] and m[2] == m[3], vname .. ": club, sword and axe train alike (" .. tostring(m[1]) .. ", " .. tostring(m[2]) .. ", " .. tostring(m[3]) .. ")")
	end
end

-- the look text of equipment (beta report 2026-10-22): one melee number, "ranged" for distance
do
	local L = M.lookText
	local function same(a, b, what) ok(a == b, what .. ": " .. tostring(a)) end
	same(L("You see a ring (club fighting +4, sword fighting +4, axe fighting +4)."), "You see a ring (melee +4).",
		"look: the three melee skills of a stock item are one")
	same(L("a helmet (sword fighting +2, distance fighting +1, shielding +3)"), "a helmet (melee +2, ranged +1, shielding +3)",
		"look: a lone sword number is melee, distance is ranged, shielding stays")
	same(L("gloves (fist fighting +2)"), "gloves (fist fighting +2)", "look: fist stays (the Monk line)")
	same(L("a club (Atk:30, Def:10 club fighting -1)"), "a club (Atk:30, Def:10 melee -1)", "look: a malus too")
	same(L("a stone"), "a stone", "look: other texts unchanged")
end

if fails > 0 then
	print(fails .. " of " .. checks .. " checks failed")
	os.exit(1)
end
print("melee_skill_test: OK (" .. checks .. " checks)")
