-- Run from the server/ folder: luajit tests/ninja_guard_test.lua (and lua5.3; CI runs both)
-- Ninja guard (O367, Chaos.classes.guard, classes.lua guardReduction / guardFactor, thief_combat.lua onDefence on a mock
-- engine): a monster's hit that lands on a Ninja is cut by the reduction of the Ninja's level; a Thief, a Samurai and
-- every other class are not; a player's hit, a player's summon and conditions are never cut; a monster's summon is; a
-- dodge still takes the whole hit. tools/survival_model.py reads the same function (tools/survival_numbers.lua).
local n = 0
setmetatable(_G, {__index = function(t, k)
	if type(k) == "string" and k:match("^[A-Z_0-9]+$") then n = n + 1; rawset(t, k, n); return n end
end})
local function eq(a, b, m) if a ~= b then error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2) end end
local function near(a, b, m) if math.abs(a - b) > 1e-9 then error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2) end end

local events = {}
local function obj(name) local o = {} function o:register() events[name] = o end function o:interval() end return o end
function CreatureEvent(name) return obj(name) end
function GlobalEvent(name) return obj(name) end
EventCallback = setmetatable({}, {__index = function(_, k) if k == "register" then return function() end end end,
	__newindex = function() end})
function addEvent() end
ChaosSpell = {canAttack = function() return true end}
function Condition(t) local c = {type = t, p = {}} function c:setParameter(k, v) c.p[k] = v end function c:addDamage() end return c end
local M = {} M.__index = M
function M:getId() return self.id end
function M:isPlayer() return self.player == true end
function M:isMonster() return self.monster == true end
function M:getMaster() return self.master end
function M:getPlayer() return self.player and self or nil end
function M:getLevel() return self.level or 1 end
function M:getVocation() local v = self.voc return {getId = function() return v end} end
function M:getCondition() return nil end
function M:hasCondition() return false end
function M:removeCondition() end
function M:addCondition() end
function M:registerEvent() end
function M:getStorageValue() return -1 end
function M:setStorageValue() end
function M:getPosition() return {sendMagicEffect = function() end} end
function M:getSlotItem() return nil end
local function mk(o) return setmetatable(o, M) end
function Player() return nil end
dofile("data/scripts/chaos/thief_combat.lua")

local C = ChaosClasses
local g = Chaos.classes.guard
eq(g.vocations[12], true, "the Ninja is listed")
eq(g.vocations[11], nil, "the Thief is not") eq(g.vocations[13], nil, "the Samurai is not")
-- the reduction by level: linear between the points, flat outside
local pts = g.points
near(C.guardReduction(12, 1), pts[1][2], "below the first point: the first")
for _, p in ipairs(pts) do near(C.guardReduction(12, p[1]), p[2], "at the point " .. p[1]) end
near(C.guardReduction(12, 5000), pts[#pts][2], "above the last point: the last")
near(C.guardReduction(12, (pts[1][1] + pts[2][1]) / 2), (pts[1][2] + pts[2][2]) / 2, "half way")
for lv = 1, 2000, 7 do
	local r = C.guardReduction(12, lv)
	if r < 0 or r >= 0.5 then error("reduction out of 0..0.5 at " .. lv) end
	if lv > 1 and r + 1e-12 < C.guardReduction(12, lv - 7) then error("the reduction never falls with the level, " .. lv) end
end
eq(C.guardReduction(11, 757), 0, "Thief") eq(C.guardReduction(13, 757), 0, "Samurai") eq(C.guardReduction(4, 757), 0, "Warrior")
eq(C.guardFactor(12, 757, false), 1, "not a monster's hit")
near(C.guardFactor(12, 757, true), 1 - C.guardReduction(12, 757), "a monster's hit")

-- the hook: no dodge (math.random returns the top of [0, 1))
local realRandom = math.random
math.random = function(a, b) if a then return realRandom(a, b) end return 0.999 end
local ev = events.ChaosThiefCombat
local function hit(target, attacker, dmg, origin, ctype)
	local p, _, s = ev.onHealthChange(target, attacker, dmg, ctype or COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, origin or ORIGIN_MELEE)
	return p, s
end
local monster = mk{id = 900, monster = true}
local ninja = mk{id = 1, voc = 12, player = true, level = 757}
local cut = 1 - C.guardReduction(12, 757)
eq(hit(ninja, monster, -1000), -math.floor(1000 * cut + 0.5), "a monster's melee hit on a level 757 Ninja")
eq(hit(ninja, monster, -1000, ORIGIN_RANGED), -math.floor(1000 * cut + 0.5), "a monster's ranged hit")
eq(hit(ninja, monster, -1000, ORIGIN_SPELL, COMBAT_FIREDAMAGE), -math.floor(1000 * cut + 0.5), "a monster's fire spell")
eq(hit(ninja, monster, -500, ORIGIN_CONDITION, COMBAT_FIREDAMAGE), -500, "a burn tick is not cut")
local low = mk{id = 2, voc = 12, player = true, level = 200}
eq(hit(low, monster, -1000), -math.floor(1000 * (1 - C.guardReduction(12, 200)) + 0.5), "a level 200 Ninja: the level's cut")
local summoner = mk{id = 901, monster = true}
eq(hit(ninja, mk{id = 902, monster = true, master = summoner}, -1000), -math.floor(1000 * cut + 0.5), "a monster's summon")
local enemy = mk{id = 3, voc = 4, player = true, level = 757}
eq(hit(ninja, enemy, -1000), -1000, "a player's hit (PvP) is not cut")
eq(hit(ninja, mk{id = 903, monster = true, master = enemy}, -1000), -1000, "a player's summon is not cut")
eq(hit(mk{id = 4, voc = 11, player = true, level = 757}, monster, -1000), -1000, "a Thief is not cut")
eq(hit(mk{id = 5, voc = 13, player = true, level = 757}, monster, -1000), -1000, "a Samurai is not cut")
eq(hit(mk{id = 6, voc = 4, player = true, level = 757}, monster, -1000), -1000, "a Warrior is not cut")
eq(hit(ninja, monster, 300, ORIGIN_NONE, COMBAT_HEALING), 300, "healing is untouched")
-- a dodge still takes the whole hit
math.random = function(a, b) if a then return realRandom(a, b) end return 0 end
eq(hit(ninja, monster, -1000), 0, "a dodged hit")
math.random = realRandom

print("ninja_guard_test: OK")
