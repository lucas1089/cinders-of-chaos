-- Run from the server/ folder: lua5.3 tests/paragon_test.lua (mock of the engine API; CI runs it)
-- Paragon points, caps, validation, the protocol handlers against a mocked db, gold find, and that the Paragon
-- bonuses stack with the passive tree's in passivetree_effects.lua (one condition / storage for both).
local n = 0
setmetatable(_G, {__index = function(t, k)
  if type(k) == "string" and k:match("^[A-Z_0-9]+$") then n = n + 1; rawset(t, k, n); return n end
end})
dofile("data/scripts/chaos/chaos_constants.lua")
function Chaos.load() end
local sent = {}
function Chaos.send(player, opcode, action, data) sent[#sent + 1] = {action = action, data = data}; return true end
-- db mock: rows of chaos_paragon by player guid
local rows = {}
db = {}
function db.escapeString(s) return "'" .. s .. "'" end
function db.query(q)
  local guid = q:match("DELETE FROM `chaos_paragon` WHERE `player_id` = (%d+)")
  if guid then rows[tonumber(guid)] = {} return true end
  if q:match("^INSERT INTO `chaos_paragon`") then
    for g, stat, points in q:gmatch("%((%d+), '([%w]+)', (%d+)%)") do
      rows[tonumber(g)] = rows[tonumber(g)] or {}
      rows[tonumber(g)][stat] = tonumber(points)
    end
  end
  return true
end
function Chaos.select(q)
  local guid = tonumber(q:match("`player_id` = (%d+)"))
  local out = {}
  for stat, points in pairs(rows[guid] or {}) do out[#out + 1] = {stat = stat, points = points} end
  return out
end
local registered = {}
EventCallback = setmetatable({}, {__newindex = function(t, k, v) rawset(t, "_last", {k, v}) end})
rawset(EventCallback, "register", function(self) local l = rawget(self, "_last"); registered[l[1]] = l[2] end)
function CreatureEvent(name) local o = {}; function o:register() registered[name] = o end; return o end
function Condition(t) local c = {t = t, p = {}}; function c:setTicks(x) end; function c:setParameter(k, v) self.p[k] = v end; return c end
function addEvent() end

local added = {}
local function mkPlayer(level, money)
  local st, speed = {}, 0
  local p = {money = money or 0}
  function p:getId() return 7 end
  function p:getGuid() return 70 end
  function p:getLevel() return level end
  function p:getBaseSpeed() return 220 + 2 * (level - 1) end
  function p:getMaxHealth() return 10000 end
  function p:getMaxMana() return 4000 end
  function p:removeMoney(c) if self.money >= c then self.money = self.money - c; return true end return false end
  function p:removeCondition(a, b, sub) added[sub] = nil end
  function p:addCondition(c) added[c.p[CONDITION_PARAM_SUBID]] = c end
  function p:setStorageValue(k, v) st[k] = v end
  function p:getStorageValue(k) return st[k] or 0 end
  function p:changeSpeed(d) speed = speed + d end
  function p:isPlayer() return true end
  function p:sendTextMessage() end
  return p, st, function() return speed end
end

dofile("data/scripts/chaos/paragon.lua")
dofile("data/scripts/chaos/passivetree_effects.lua")
local P = ChaosParagon
local function eq(a, b, m) if a ~= b then error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2) end end
local function near(a, b, m) if math.abs(a - b) > 1e-9 then error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2) end end

-- points
eq(P.totalPoints(562), 0, "below start"); eq(P.totalPoints(1000), 0, "at start"); eq(P.totalPoints(1001), 1, "first point")
eq(P.totalPoints(1050), 50, "1050")
eq(P.unlocked(999), false, "locked 999"); eq(P.unlocked(1000), true, "unlocked 1000")

-- definitions: four categories of two stats, modest caps, the strong ones lower
eq(#Chaos.paragon.categories, 4, "categories"); eq(#P.order, 8, "stats")
for _, key in ipairs(P.order) do
  local d = P.defs[key]
  assert(d.perPoint > 0 and d.perPoint <= 1, key .. " per point modest")
  assert(P.cap(key) <= 20 + 1e-9, key .. " cap at most 20%")
end
near(P.cap("damage"), 20, "damage cap"); near(P.cap("health"), 20, "health cap")
assert(P.cap("reduction") < 10, "damage reduction capped lower"); assert(P.cap("speed") <= 10, "speed capped lower")
near(P.value("damage", 3), 1.5, "damage per point"); near(P.value("damage", 999), 20, "value is capped")
near(P.value("critDamage", 10), 3, "crit per point"); near(P.value("goldFind", 5), 5, "gold per point")
eq(P.bonusKey("goldFind"), "paragonGoldFind", "bonus key")
local b = P.bonusesOf({damage = 4, itemFind = 2})
near(b.paragonDamage, 2, "bonusesOf damage"); near(b.paragonItemFind, 1, "bonusesOf item find"); eq(b.paragonHealth, nil, "nothing else")

-- validation
local ok, err = P.validate({damage = 1}, {}, 0, 999)
eq(ok, nil, "locked"); assert(err:find("1000"), "locked message names the level")
ok, err = P.validate({damage = 1}, {}, 0, 1000); eq(ok, nil, "level 1000 has no points yet")
ok = P.validate({damage = 2, health = 3}, {}, 10, 1010); eq(ok.damage, 2, "ok damage"); eq(ok.health, 3, "ok health")
ok, err = P.validate({damage = 6, health = 5}, {}, 10, 1010); eq(ok, nil, "over budget")
ok, err = P.validate({damage = 41}, {}, 100, 1100); eq(ok, nil, "over the stat's max points")
ok, err = P.validate({damage = 1.5}, {}, 100, 1100); eq(ok, nil, "fraction refused")
ok, err = P.validate({damage = -1}, {}, 100, 1100); eq(ok, nil, "negative refused")
ok, err = P.validate({bogus = 1}, {}, 100, 1100); eq(ok, nil, "unknown stat")
ok, err = P.validate({[1] = 1}, {}, 100, 1100); eq(ok, nil, "numeric key")
ok, err = P.validate("x", {}, 100, 1100); eq(ok, nil, "malformed")
ok, err = P.validate({damage = 1}, {damage = 3}, 100, 1100); eq(ok, nil, "no free decrease"); assert(err:find("reset"), "decrease names the reset")
ok = P.validate({health = 2}, {damage = 3}, 5, 1005); eq(ok.damage, 3, "keys left out keep their points"); eq(ok.health, 2, "added")
ok = P.validate({health = 0}, {damage = 3}, 5, 1005); eq(ok.health, nil, "zero is not stored")

-- protocol against the mocked db
local p, st, speed = mkPlayer(1100, 1100 * 250)
P.actions.paragonRequest(p)
local s = sent[#sent]; eq(s.action, "paragonState", "state sent")
eq(s.data.unlocked, true, "unlocked"); eq(s.data.total, 100, "total"); eq(s.data.free, 100, "free"); eq(s.data.spent, 0, "spent")
eq(s.data.resetCost, 1100 * 250, "reset cost = tree rule"); eq(#s.data.categories, 4, "categories sent")
eq(s.data.categories[1].stats[1].maxPoints, 40, "max points sent")
P.actions.paragonApply(p, {alloc = {damage = 10, health = 20, reduction = 8, speed = 10, critDamage = 10, itemFind = 10}})
eq(rows[70].damage, 10, "saved damage"); eq(rows[70].health, 20, "saved health")
s = sent[#sent]; eq(s.data.spent, 68, "spent after apply"); eq(s.data.free, 32, "free after apply")
P.actions.paragonApply(p, {alloc = {mana = 33}}); eq(sent[#sent - 1].action, "sendMessage", "over budget refused"); eq(rows[70].mana, nil, "not saved")
P.actions.paragonApply(p, {alloc = {damage = 5}}); eq(rows[70].damage, 10, "decrease refused")
-- the cache is reloaded from the db after a relog
P.cache[7] = nil
eq(P.allocation(p).reduction, 8, "persisted")

-- stacking with the tree: the tree's own bonuses + Paragon in one table, applied by passivetree_effects.lua
local tree = {vitality = 20, spirit = 10, criticalHitAmount = 5, absorbFire = 10, loot = 50, speed = 200, incrementFire = 10}
local bonuses = P.addBonuses(p, tree)
near(bonuses.paragonDamage, 5, "damage 10 pts"); near(bonuses.paragonHealth, 10, "health 20 pts")
local applyAll = ChaosPassiveTree.listeners[1]
applyAll(p, bonuses)
eq(added[7220].p[CONDITION_PARAM_STAT_MAXHITPOINTSPERCENT], 130, "one health condition: vitality 20 + Paragon 10")
eq(added[7221].p[CONDITION_PARAM_STAT_MAXMANAPOINTSPERCENT], 110, "mana: spirit only")
eq(added[7215].p[CONDITION_PARAM_SPECIALSKILL_CRITICALHITAMOUNT], 8, "crit 5 + 3")
eq(st[977562], 12, "fire absorb 10 + reduction 2"); eq(st[977563], 2, "physical gets the reduction too")
eq(st[7100040], 15, "item find 10 + 5")
eq(speed(), 20 + math.floor(2418 * 0.05), "speed: tree 20 flat + 5% of base 2418")
-- a fractional health sum uses the flat parameter (engine formula, max x percent / 100)
applyAll(p, {vitality = 20, paragonHealth = 0.5})
eq(added[7220].p[CONDITION_PARAM_STAT_MAXHITPOINTSPERCENT], nil, "no percent param for 20.5%")
eq(added[7220].p[CONDITION_PARAM_STAT_MAXHITPOINTS], 2050, "20.5% of 10000")
-- the tree's own caps still apply to the tree share only
applyAll(p, {vitality = 500, paragonHealth = 20})
eq(added[7220].p[CONDITION_PARAM_STAT_MAXHITPOINTSPERCENT], 170, "tree vitality capped at 50, + Paragon 20")
-- Paragon alone, then nothing (respec)
applyAll(p, {paragonHealth = 2})
eq(added[7220].p[CONDITION_PARAM_STAT_MAXHITPOINTSPERCENT], 102, "Paragon alone")
applyAll(p, {})
eq(added[7220], nil, "removed"); eq(speed(), 0, "speed removed"); eq(st[977563], 0, "reduction removed")

-- damage: Paragon multiplies after the tree's bonuses, never healing
eq(ChaosParagonDamageMultiplier({paragonDamage = 10}, COMBAT_FIREDAMAGE), 1.1, "damage multiplier")
eq(ChaosParagonDamageMultiplier({paragonDamage = 10}, COMBAT_HEALING), 1, "no healing")
eq(ChaosParagonDamageMultiplier({}, COMBAT_FIREDAMAGE), 1, "none")
ChaosPassiveCache[7] = {incrementFire = 10, paragonDamage = 10}
local atk = {isPlayer = function() return true end, getId = function() return 7 end}
local d1 = registered["ChaosPassiveDealt"].onHealthChange({}, atk, -1000, COMBAT_FIREDAMAGE, 0, COMBAT_NONE, 0)
eq(d1, -1210, "fire: tree +10% x Paragon +10%")
local h1 = registered["ChaosPassiveDealt"].onHealthChange({}, atk, 1000, COMBAT_HEALING, 0, COMBAT_NONE, 0)
eq(h1, 1000, "heal unchanged")

-- speed follows the base speed on level up
ChaosPassiveCache[7] = {paragonSpeed = 10}
applyAll(p, ChaosPassiveCache[7]); eq(speed(), 241, "10% of 2418")
p.getBaseSpeed = function() return 2518 end
ChaosPassiveRefreshSpeed(p); eq(speed(), 251, "refreshed to 10% of 2518")

-- gold find
eq(P.goldBonus(1000, 10, function() return 0.99 end), 100, "10% of 1000")
eq(P.goldBonus(15, 10, function() return 0.4 end), 2, "1.5 rounds up when the roll is below the fraction")
eq(P.goldBonus(15, 10, function() return 0.6 end), 1, "1.5 rounds down otherwise")
eq(P.goldBonus(0, 10), 0, "no gold, no bonus"); eq(P.goldBonus(100, 0), 0, "no pct")
local c = P.coins(12345)
eq(c[1][1], 2160, "crystal"); eq(c[1][2], 1, "1 crystal"); eq(c[2][2], 23, "23 platinum"); eq(c[3][2], 45, "45 gold")
eq(#P.coins(25000), 2, "2 crystal, no empty stacks")

-- reset: tree rule cost, then nothing to reset
P.cache[7] = nil
local before = p.money
P.actions.paragonReset(p)
eq(p.money, before - 1100 * 250, "reset cost"); eq(P.spent(P.allocation(p)), 0, "reset"); eq(next(rows[70]), nil, "db emptied")
P.actions.paragonReset(p); eq(sent[#sent - 1].data.message, "There is nothing to reset.", "nothing to reset")
-- not enough gold
P.actions.paragonApply(p, {alloc = {damage = 1}})
p.money = 0
P.actions.paragonReset(p); eq(rows[70].damage, 1, "no gold, no reset")
-- the store service resets for free
P.resetAll(p, true); eq(next(rows[70]), nil, "store reset")

-- level dropped below what was spent: refunded at login
rows[70] = {damage = 30}
P.cache[7] = nil
local low = mkPlayer(1010)
registered["ChaosParagonLogin"].onLogin(setmetatable({registerEvent = function() end}, {__index = low}))
eq(next(rows[70]), nil, "over budget refunded")
-- the locked state is sent below level 1000
local young = mkPlayer(562)
P.cache[7] = nil
P.actions.paragonRequest(young); eq(sent[#sent].data.unlocked, false, "locked below 1000"); eq(sent[#sent].data.free, 0, "no points")
print("paragon: all asserts passed")
