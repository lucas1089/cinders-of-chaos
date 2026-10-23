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
  function p:getMaxHealth() return 1000 end
  return p, st, stats, function() return speed end
end
function addEvent() end
dofile("data/scripts/chaos/passivetree_effects.lua")
local assertEq = function(a, b, m) if a ~= b then error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2) end end
local b = {strength = 120, vitality = 25, absorbFire = 10, absorbAllElements = 5, absorbPhysical = 90, swordSkill = 4,
  incrementFire = 10, multiIncrement = 3, incrementPhysical = 7, experience = 100, loot = 50, rarityLoot = 4, speed = 2000, criticalHitChance = 5}
assertEq(ChaosPassiveDamagePercent(b, COMBAT_FIREDAMAGE), 13, "fire")
assertEq(ChaosPassiveDamagePercent(b, COMBAT_PHYSICALDAMAGE), 7, "phys")
assertEq(ChaosPassiveDamagePercent(b, COMBAT_ICEDAMAGE), 3, "ice multi")
assertEq(ChaosPassiveAbsorbPercent(b, "absorbFire"), 15, "absorb fire+all")
assertEq(ChaosPassiveAbsorbPercent(b, "absorbPhysical"), 75, "absorb cap")
assertEq(ChaosPassiveSpeed(b), 80, "speed cap")
assertEq(ChaosPassiveItemFind(b), 14, "item find")
assertEq(ChaosPassiveExperienceMultiplier(b), 1.1, "xp")
local p, st, stats, speed = mkPlayer()
local applyAll = ChaosPassiveTree.listeners[1]
applyAll(p, b)
-- character stats are never written (they are the stat window's points, saved with the player)
assertEq(stats[CHARSTAT_STRENGTH], nil, "strength not written")
assertEq(stats[CHARSTAT_VITALITY], nil, "vitality not written")
assert(added[7220] and added[7220].p[CONDITION_PARAM_STAT_MAXHITPOINTSPERCENT] == 120, "vitality 25 as +20% max health (0.8 a point below the knee)")
assert(added[7221] == nil, "no spirit, no mana condition")
assertEq(st[977562], 15, "storage fire")
assertEq(st[977563], 75, "storage phys")
assertEq(st[7100040], 14, "item find storage")
assertEq(speed(), 80, "speed")
assert(added[7200] and added[7200].p[CONDITION_PARAM_SKILL_SWORD] == 4, "sword condition")
assert(added[7214].p[CONDITION_PARAM_SPECIALSKILL_CRITICALHITCHANCE] == 5, "crit condition")
-- the stat window's own value is left alone across re-applies
stats[CHARSTAT_STRENGTH] = 10
applyAll(p, b)
assertEq(stats[CHARSTAT_STRENGTH], 10, "stat window value untouched")
-- respec: bonuses removed
applyAll(p, {})
assert(added[7220] == nil, "vitality condition removed")
assertEq(speed(), 0, "speed removed")
assert(added[7200] == nil, "condition removed")
-- a Vocation Trial node's max health (Steelblood +8%) is not cut by the tree's own +50% cap
applyAll(p, {vitality = 108, trialVitality = 8})
assertEq(added[7220].p[CONDITION_PARAM_STAT_MAXHITPOINTSPERCENT], 158, "tree at the 100 points cap (+50%), plus the trial's 8 unscaled")
applyAll(p, {vitality = 38, trialVitality = 8})
assertEq(added[7220].p[CONDITION_PARAM_STAT_MAXHITPOINTSPERCENT], 132, "under the knee: 30 tree points x 0.8 + the trial's 8")
applyAll(p, {vitality = 83, trialVitality = 8})
assertEq(added[7220].p[CONDITION_PARAM_STAT_MAXHITPOINTSPERCENT], 153, "past the knee: 40 + 25 x 0.2 + the trial's 8")
applyAll(p, {vitality = 100})
assertEq(added[7220].p[CONDITION_PARAM_STAT_MAXHITPOINTSPERCENT], 150, "no trial node: the cap as before")
applyAll(p, {vitality = 3})
assertEq(added[7220].p[CONDITION_PARAM_STAT_MAXHITPOINTSPERCENT], nil, "2.4% is not a whole percent")
assertEq(added[7220].p[CONDITION_PARAM_STAT_MAXHITPOINTS], 24, "2.4% of 1000 max health as flat points")
applyAll(p, {vitality = 5, paragonHealth = 2})
assertEq(added[7220].p[CONDITION_PARAM_STAT_MAXHITPOINTSPERCENT], 106, "Paragon health is added unscaled")
applyAll(p, {})
assert(added[7220] == nil, "the trial node dropped: no condition left")
-- damage event
ChaosPassiveCache[7] = b
local ev = registered["ChaosPassiveDealt"]
local atk = {isPlayer = function() return true end, getId = function() return 7 end}
-- b: fire +13%, physical +7%, strength 200 (capped at 120: value 60 -> x1.2609), no intelligence, no dexterity
local d1, t1, d2, t2 = ev.onHealthChange({}, atk, -100, COMBAT_FIREDAMAGE, -50, COMBAT_PHYSICALDAMAGE, 0)
assertEq(d1, -113, "fire dealt"); assertEq(d2, -67, "phys dealt with strength (50 x 1.07 x 1.2609)")
assertEq(ChaosPassiveStatMultiplier({intelligence = 60}, COMBAT_FIREDAMAGE, 0), 1 + 48 / 230, "intelligence 60 (the knee: value 48) -> +20.9%")
assertEq(ChaosPassiveStatMultiplier({dexterity = 80}, COMBAT_FIREDAMAGE, 0), 1, "dexterity ignores spells")
assertEq(ChaosPassiveStatMultiplier({dexterity = 80}, COMBAT_PHYSICALDAMAGE, ORIGIN_MELEE), 1.25, "dexterity 80 (the cap: value 20) on a weapon hit")
assertEq(ChaosPassiveStatMultiplier({dexterity = 20}, COMBAT_PHYSICALDAMAGE, ORIGIN_MELEE), 1 / (1 - 16 / 100), "dexterity 20 (the knee: value 16)")
assert(ChaosPassiveStatMultiplier({dexterity = 300}, COMBAT_PHYSICALDAMAGE, ORIGIN_MELEE) > 1.25, "dexterity past 80: the soft cap still adds")
-- 2026-10-22 two-tier curve: up to the knee (the old cap) 80% of the old maximum, from the knee to the new cap the
-- other 20%, nothing above; increasing all the way, each point past the knee worth less than one before it
local E = ChaosPassiveEffectsConfig
local OLD = {strength = {60, 120, 60}, intelligence = {60, 120, 60}, dexterity = {20, 80, 20}, vitality = {50, 100, 50},
  spirit = {50, 100, 50}} -- knee, cap, maximum value
for stat, t in pairs(OLD) do
  local knee, cap, max = t[1], t[2], t[3]
  assertEq(E.charStatKnee[stat], knee, stat .. " knee"); assertEq(E.charStatCap[stat], cap, stat .. " cap")
  assertEq(E.charStatMax[stat], max, stat .. " max")
  assertEq(ChaosPassiveCharStat(knee, stat), max * 0.8, stat .. ": the knee gives 80% of the old maximum")
  assertEq(ChaosPassiveCharStat(cap, stat), max, stat .. ": the cap gives the old maximum")
  assert(ChaosPassiveCharStat(cap + 50, stat) > max, stat .. ": past the cap the soft cap still adds (O146)")
  assert(math.abs(ChaosPassiveCharStat(knee / 2, stat) - max * 0.4) < 1e-6, stat .. ": linear before the knee")
  assert(math.abs(ChaosPassiveCharStat((knee + cap) / 2, stat) - max * 0.9) < 1e-6, stat .. ": linear after the knee")
  local prev = 0
  for p = 1, cap * 6 do
    local v = ChaosPassiveCharStat(p, stat)
    assert(v > prev, stat .. ": strictly increasing, also past the cap (" .. p .. ")")
    prev = v
  end
  assert(ChaosPassiveCharStat(1, stat) > ChaosPassiveCharStat(knee + 1, stat) - ChaosPassiveCharStat(knee, stat),
    stat .. ": a point past the knee is worth less")
end
assertEq(E.charStatKneeShare, 0.8, "the knee share")
assertEq(ChaosPassiveCharStat(nil, "strength"), 0, "no points")
assertEq(ChaosPassiveCharStat(-5, "strength"), 0, "never negative")
assertEq(ChaosPassiveStatMultiplier({strength = 120}, COMBAT_PHYSICALDAMAGE, 0), 1 + 60 / 230, "strength: +26% at the new cap, as before")
assertEq(ChaosPassiveStatMultiplier({intelligence = 120}, COMBAT_FIREDAMAGE, 0), 1 + 60 / 230, "intelligence: +26% at the new cap")
assertEq(ChaosPassiveMaxPercent({spirit = 100}, "spirit"), 50, "spirit: +50% at the new cap")
assertEq(ChaosPassiveMaxPercent({spirit = 105, trialSpirit = 5, paragonMana = 3}, "spirit"), 50 + 5 + 3, "spirit: the trial and Paragon shares stay outside the cap")
-- legacy clamp: stats an older version wrote are cut back to the stat window maximum once
Chaos.storage.passiveStatsFixed = 4242
StatsMaxValues = {[CHARSTAT_STRENGTH] = 20, [CHARSTAT_INTELLIGENCE] = 20, [CHARSTAT_DEXTERITY] = 20,
  [CHARSTAT_VITALITY] = 20, [CHARSTAT_SPIRIT] = 20, [CHARSTAT_WISDOM] = 0}
stats[CHARSTAT_STRENGTH], stats[CHARSTAT_WISDOM] = 204, 120
ChaosPassiveFixLegacyStats(p)
assertEq(stats[CHARSTAT_STRENGTH], 20, "legacy strength clamped"); assertEq(stats[CHARSTAT_WISDOM], 0, "legacy wisdom clamped")
assertEq(st[4242], 1, "done flag")
stats[CHARSTAT_STRENGTH] = 30
ChaosPassiveFixLegacyStats(p)
assertEq(stats[CHARSTAT_STRENGTH], 30, "only once")
local xp = registered["onGainExperience"]
assertEq(xp(p, {}, 1000, 1000), 1100, "xp")
print("passive effects: all asserts passed")
