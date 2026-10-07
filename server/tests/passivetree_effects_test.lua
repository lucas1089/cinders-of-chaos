-- Run from the server/ folder: lua5.3 tests/passivetree_effects_test.lua (mock of the engine API; CI runs it)
-- mock harness: constants autogenerate, EventCallback/CreatureEvent record registrations
local n = 0
setmetatable(_G, {__index = function(t, k)
  if type(k) == "string" and k:match("^[A-Z_0-9]+$") then n = n + 1; rawset(t, k, n); return n end
end})
Chaos = {storage = {}, tables = {}, passive = {}}
function Chaos.load() end
ChaosOpcodes = {}
local registered = {}
EventCallback = setmetatable({}, {__newindex = function(t, k, v) rawset(t, "_last", {k, v}) end})
rawset(EventCallback, "register", function(self) local l = rawget(self, "_last"); registered[l[1]] = l[2] end)
function CreatureEvent(name) local o = {}; function o:register() registered[name] = o end; return o end
function Condition(t) local c = {t = t, p = {}}; function c:setTicks(x) end; function c:setParameter(k, v) self.p[k] = v end; return c end
local added, removed = {}, {}
local function mkPlayer()
  local st, stats, speed = {}, {}, 0
  local p = {id = 7}
  function p:getId() return 7 end
  function p:removeCondition(a, b, sub) removed[sub] = true; added[sub] = nil end
  function p:addCondition(c) added[c.p[CONDITION_PARAM_SUBID]] = c end
  function p:setStorageValue(k, v) st[k] = v end
  function p:getStorageValue(k) return st[k] or 0 end
  function p:getCharacterStat(i) return stats[i] or 0 end
  function p:setCharacterStat(i, v) stats[i] = v end
  function p:changeSpeed(d) speed = speed + d end
  function p:isPlayer() return true end
  return p, st, stats, function() return speed end
end
function addEvent() end
dofile("data/scripts/chaos/passivetree_effects.lua")
local assertEq = function(a, b, m) if a ~= b then error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2) end end
local b = {strength = 100, vitality = 20, absorbFire = 10, absorbAllElements = 5, absorbPhysical = 90, swordSkill = 4,
  incrementFire = 10, multiIncrement = 3, incrementPhysical = 7, experience = 100, loot = 50, rarityLoot = 4, speed = 2000, criticalHitChance = 5}
assertEq(ChaosPassiveDamagePercent(b, COMBAT_FIREDAMAGE), 13, "fire")
assertEq(ChaosPassiveDamagePercent(b, COMBAT_PHYSICALDAMAGE), 7, "phys")
assertEq(ChaosPassiveDamagePercent(b, COMBAT_ICEDAMAGE), 3, "ice multi")
assertEq(ChaosPassiveAbsorbPercent(b, "absorbFire"), 15, "absorb fire+all")
assertEq(ChaosPassiveAbsorbPercent(b, "absorbPhysical"), 80, "absorb cap")
assertEq(ChaosPassiveSpeed(b), 80, "speed cap")
assertEq(ChaosPassiveItemFind(b), 14, "item find")
assertEq(ChaosPassiveExperienceMultiplier(b), 1.1, "xp")
local p, st, stats, speed = mkPlayer()
local applyAll = ChaosPassiveTree.listeners[1]
applyAll(p, b)
assertEq(stats[CHARSTAT_STRENGTH], 60, "str cap")
assertEq(stats[CHARSTAT_VITALITY], 20, "vit")
assertEq(st[977562], 15, "storage fire")
assertEq(st[977563], 80, "storage phys")
assertEq(st[7100040], 14, "item find storage")
assertEq(speed(), 80, "speed")
assert(added[7200] and added[7200].p[CONDITION_PARAM_SKILL_SWORD] == 4, "sword condition")
assert(added[7214].p[CONDITION_PARAM_SPECIALSKILL_CRITICALHITCHANCE] == 5, "crit condition")
-- stat window rewrites strength to 10: re-sync must re-add our part on top
stats[CHARSTAT_STRENGTH] = 10
applyAll(p, b)
assertEq(stats[CHARSTAT_STRENGTH], 70, "resync after external write")
-- respec: bonuses removed
applyAll(p, {})
assertEq(stats[CHARSTAT_STRENGTH], 10, "strength back to base")
assertEq(speed(), 0, "speed removed")
assert(added[7200] == nil, "condition removed")
-- damage event
ChaosPassiveCache[7] = b
local ev = registered["ChaosPassiveDealt"]
local atk = {isPlayer = function() return true end, getId = function() return 7 end}
local d1, t1, d2, t2 = ev.onHealthChange({}, atk, -100, COMBAT_FIREDAMAGE, -50, COMBAT_PHYSICALDAMAGE, 0)
assertEq(d1, -113, "fire dealt"); assertEq(d2, -53, "phys dealt")
local xp = registered["onGainExperience"]
assertEq(xp(p, {}, 1000, 1000), 1100, "xp")
print("passive effects: all asserts passed")
