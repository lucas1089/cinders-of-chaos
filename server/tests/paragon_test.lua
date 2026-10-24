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
  function p:getMoney() return self.money end
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
-- O135: 1 point a level to 1100, then 1 every 6 levels; the 282 points of the track are all earned at level 2192
eq(P.totalPoints(1100), 100, "1100"); eq(P.totalPoints(1105), 100, "1105"); eq(P.totalPoints(1106), 101, "1106")
eq(P.totalPoints(1282), 130, "1282 (it was 282)"); eq(P.totalPoints(2191), 281, "2191"); eq(P.totalPoints(2192), 282, "2192")
do
  local maxAll = 0
  for _, key in ipairs(P.order) do maxAll = maxAll + P.defs[key].maxPoints end
  eq(maxAll, 282, "points to max the track")
  local last = 1000
  for L = 1001, 2400 do
    local t, before = P.totalPoints(L), P.totalPoints(L - 1)
    assert(t >= before and t - before <= 1, "never more than one point a level, never fewer in total")
    if t > before then last = L end
    if t < maxAll then assert(L - last <= Chaos.paragon.levelsPerPointSlow, "a point at least every 6 levels until maxed (" .. L .. ")") end
  end
  assert(P.totalPoints(2200) >= maxAll and P.totalPoints(2185) < maxAll, "the track lasts to the end of the level range (2200)")
end
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
local tree = {vitality = 25, spirit = 10, criticalHitAmount = 5, absorbFire = 10, loot = 50, speed = 200, incrementFire = 10}
local bonuses = P.addBonuses(p, tree)
near(bonuses.paragonDamage, 5, "damage 10 pts"); near(bonuses.paragonHealth, 10, "health 20 pts")
local applyAll = ChaosPassiveTree.listeners[1]
applyAll(p, bonuses)
eq(added[7220].p[CONDITION_PARAM_STAT_MAXHITPOINTSPERCENT], 130, "one health condition: vitality 25 (x 0.8 = 20%) + Paragon 10")
eq(added[7221].p[CONDITION_PARAM_STAT_MAXMANAPOINTSPERCENT], 108, "mana: spirit 10 (x 0.8 = 8%) only")
eq(added[7215].p[CONDITION_PARAM_SPECIALSKILL_CRITICALHITAMOUNT], 8, "crit 5 + 3")
eq(st[977562], 12, "fire absorb 10 + reduction 2"); eq(st[977563], 2, "physical gets the reduction too")
eq(st[7100040], 15, "item find 10 + 5")
eq(speed(), 20 + math.floor(2418 * 0.05), "speed: tree 20 flat + 5% of base 2418")
-- a fractional health sum uses the flat parameter (engine formula, max x percent / 100)
applyAll(p, {vitality = 25, paragonHealth = 0.5})
eq(added[7220].p[CONDITION_PARAM_STAT_MAXHITPOINTSPERCENT], nil, "no percent param for 20.5%")
eq(added[7220].p[CONDITION_PARAM_STAT_MAXHITPOINTS], 2050, "20.5% of 10000")
-- the tree's own caps still apply to the tree share only
applyAll(p, {vitality = 100, paragonHealth = 20})
eq(added[7220].p[CONDITION_PARAM_STAT_MAXHITPOINTSPERCENT], 170, "tree vitality at the 100 points cap (+50%), + Paragon 20")
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

-- level dropped below what was spent (O190): the allocation stays, login never wipes it
rows[70] = {damage = 30}
P.cache[7] = nil
local low = mkPlayer(1010)
registered["ChaosParagonLogin"].onLogin(setmetatable({registerEvent = function() end}, {__index = low}))
eq(rows[70].damage, 30, "over budget keeps the allocation (O190)")
-- the locked state is sent below level 1000
rows[70] = {}
local young = mkPlayer(562)
P.cache[7] = nil
P.actions.paragonRequest(young); eq(sent[#sent].data.unlocked, false, "locked below 1000"); eq(sent[#sent].data.free, 0, "no points")

-- ---------------------------------------------------------------- O146: Paragon Mastery, the endless sink
local M = Chaos.paragon.mastery
eq(#P.masteryOrder, 7, "seven masteries"); eq(M.maxRanks <= 65535, true, "ranks fit the smallint column")
for _, key in ipairs(P.masteryOrder) do
  local d = P.mastery[key]
  assert(P.defs[d.bonus], key .. " adds to the category stat " .. tostring(d.bonus))
  eq(P.defs[d.bonus].category, d.category, key .. " sits in its stat's category")
  -- scale x ln(1 + ranks / h): zero at 0, strictly increasing, concave, never capped
  near(P.masteryValue(key, 0), 0, key .. " zero ranks")
  local prev, prevGain = 0, math.huge
  for r = 1, 3000 do
    local v = P.masteryValue(key, r)
    local gain = v - prev
    assert(gain > 0, key .. ": every rank adds something (" .. r .. ")")
    assert(gain < prevGain, key .. ": each rank adds less than the one before (" .. r .. ")")
    prev, prevGain = v, gain
  end
  assert(P.masteryValue(key, 60000) > P.masteryValue(key, 3000), key .. ": no maximum")
  -- modest: 300 ranks stay under the whole category stat's cap, and the first rank is a fraction of a category point
  assert(P.masteryValue(key, 300) <= P.cap(d.bonus) * 1.1, key .. ": 300 ranks about the category cap at most")
  assert(P.masteryValue(key, 1) < P.defs[d.bonus].perPoint, key .. ": a rank is worth less than a category point")
end
near(P.masteryValue("mDamage", 300), 6 * math.log(7), "damage mastery 300 ranks"); assert(math.abs(P.masteryValue("mDamage", 300) - 11.67) < 0.01)
eq(P.masteryValue("bogus", 5), 0, "unknown mastery"); eq(P.masteryValue("mDamage", -4), 0, "negative ranks")

-- bonusesOf: masteries and category points add up under one key
b = P.bonusesOf({damage = 40, mDamage = 300, mHealth = 50})
near(b.paragonDamage, 20 + 6 * math.log(7), "category + mastery damage"); near(b.paragonHealth, 8 * math.log(2), "health mastery")

-- validateMastery
ok, err = P.validateMastery("mDamage", 5, {}, 10, 999); eq(ok, nil, "locked"); assert(err:find("1000"), "names the level")
ok = P.validateMastery("mDamage", 5, {damage = 3}, 10, 1010); eq(ok.mDamage, 5, "ranks added"); eq(ok.damage, 3, "others kept")
ok = P.validateMastery("mDamage", 5, {mDamage = 2}, 10, 1010); eq(ok.mDamage, 7, "ranks stack")
ok, err = P.validateMastery("mDamage", 8, {damage = 3}, 10, 1010); eq(ok, nil, "over budget (3 spent + 8 > 10)")
ok = P.validateMastery("mDamage", 7, {damage = 3}, 10, 1010); eq(ok.mDamage, 7, "exactly the free points")
for _, bad in ipairs({0, -1, 1.5, "x", 1e9}) do ok = P.validateMastery("mDamage", bad, {}, 1e12, 1500); eq(ok, nil, "refused n " .. tostring(bad)) end
ok = P.validateMastery("damage", 1, {}, 10, 1500); eq(ok, nil, "a category stat is no mastery"); ok = P.validateMastery({}, 1, {}, 10, 1500); eq(ok, nil, "table key")
ok = P.validateMastery("mDamage", 2, {mDamage = M.maxRanks - 1}, 1e9, 1500); eq(ok, nil, "max ranks")

-- the protocol: a level 2200 character (the whole track earned at 2192) with the categories bought and 100 exchanged tree
-- points has points left to spend. (The beta report, "300 points at level 1500", was the pre-O135 pace: maxed at 1282.)
rows[70] = {}; P.cache = {}
local q, qst, qspeed = mkPlayer(2200, 2200 * 250)
qst[Chaos.storage.paragonConverted] = 100
local maxAll = 282
P.actions.paragonApply(q, {alloc = {damage = 40, critDamage = 50, health = 40, reduction = 32, speed = 20, mana = 40, goldFind = 20, itemFind = 40}})
P.actions.paragonRequest(q); s = sent[#sent]
eq(s.data.total, P.totalPoints(2200) + 100, "total at 2200 with the exchange"); eq(s.data.free, P.totalPoints(2200) + 100 - maxAll, "free after the full track")
assert(s.data.free > 100, "spare points after the whole track")
eq(#s.data.mastery.rows, 7, "mastery rows sent"); eq(s.data.mastery.rows[1].key, "mDamage", "order")
assert(s.data.mastery.rows[1].next > 0 and s.data.mastery.rows[1].ranks == 0, "first rank value")
local free0 = s.data.free
P.actions.paragonMastery(q, {key = "mDamage", n = 10})
s = sent[#sent]; eq(s.action, "paragonState", "state after the mastery"); eq(s.data.free, free0 - 10, "ten points spent")
eq(rows[70].mDamage, 10, "saved"); eq(s.data.mastery.rows[1].ranks, 10, "ranks shown")
near(s.data.mastery.rows[1].value, 6 * math.log(1 + 10 / 50), "value shown")
P.actions.paragonMastery(q, {key = "mDamage", n = free0})
eq(sent[#sent - 1].action, "sendMessage", "more than the free points: refused with a message"); eq(rows[70].mDamage, 10, "nothing saved")
P.actions.paragonMastery(q, {key = "nope", n = 1}); eq(rows[70].mDamage, 10, "unknown key refused")
P.actions.paragonMastery(q, nil)
-- spend everything: points earned later are not lost, they are one more rank away
P.actions.paragonMastery(q, {key = "mItemFind", n = free0 - 10})
eq(sent[#sent].data.free, 0, "all spent")
-- a level up gives a point; it can go into a rank at once
local grown = mkPlayer(2206, 0); P.cache[7] = rows[70]
eq(P.pointsOf(grown), P.totalPoints(2206), "level 2206 total"); assert(P.pointsOf(grown) > P.totalPoints(2200), "a later level owns one more")
-- masteries reach the bonus table the effects use
local bonuses = {}; P.addBonuses(q, bonuses)
near(bonuses.paragonDamage, 20 + P.masteryValue("mDamage", 10), "damage mastery is in the bonus table")
near(bonuses.paragonItemFind, 20 + P.masteryValue("mItemFind", free0 - 10), "item find mastery is in the bonus table")
-- the load keeps mastery rows and cuts a row above the max
rows[70] = {mDamage = 70000, mMana = 4, bogus = 3}; P.cache = {}
local loaded = P.load(70); eq(loaded.mDamage, M.maxRanks, "cut at max ranks"); eq(loaded.mMana, 4, "mastery loaded"); eq(loaded.bogus, nil, "unknown row dropped")

-- the exchange: free tree points become Paragon points for good
local treeSpent, treePoints, pointsSent = 3, 20, 0
ChaosPassiveTree.internal = {
  totalPoints = function(pl) return treePoints - pl:getStorageValue(Chaos.storage.paragonConverted) end,
  loadPresets = function() return {{nodes = {1, 2, 3}}} end,
  sendPoints = function() pointsSent = pointsSent + 1 end
}
rows[70] = {}; P.cache = {}
local x, xst = mkPlayer(1500, 0)
eq(P.treeFree(x), 17, "free tree points")
P.actions.paragonConvert(x, {n = 5})
eq(xst[Chaos.storage.paragonConverted], 5, "5 converted"); eq(P.converted(x), 5, "converted read back"); eq(pointsSent, 1, "tree points resent")
eq(P.pointsOf(x), P.totalPoints(1500) + 5, "five more Paragon points"); eq(P.treeFree(x), 12, "five fewer tree points")
eq(sent[#sent - 1].action, "paragonState", "state sent"); eq(sent[#sent - 1].data.exchange.converted, 5, "exchange block")
eq(sent[#sent - 1].data.exchange.treeFree, 12, "tree free in the state"); eq(sent[#sent - 1].data.total, P.totalPoints(1500) + 5, "total in the state")
P.actions.paragonConvert(x, {n = 13}); eq(xst[Chaos.storage.paragonConverted], 5, "more than the free tree points: refused")
P.actions.paragonConvert(x, {n = 0}); P.actions.paragonConvert(x, {n = 1.5}); P.actions.paragonConvert(x, {n = "a"}); P.actions.paragonConvert(x, nil)
eq(xst[Chaos.storage.paragonConverted], 5, "malformed refused")
P.actions.paragonConvert(x, {n = 12}); eq(P.converted(x), 17, "all of them"); eq(P.treeFree(x), 0, "none left")
local lowx, lowst = mkPlayer(900, 0); P.actions.paragonConvert(lowx, {n = 1}); eq(lowst[Chaos.storage.paragonConverted], nil, "locked below 1000")
-- converted points are spendable and survive the login check
P.actions.paragonMastery(x, {key = "mMana", n = 17})
eq(rows[70].mMana, 17, "the exchanged points buy ranks")
P.cache = {}; local xl = mkPlayer(1500, 0)
registered["ChaosParagonLogin"].onLogin(setmetatable({registerEvent = function() end}, {__index = x}))
eq(rows[70].mMana, 17, "no refund at login")
ChaosPassiveTree.internal = nil

-- beta 2026-10-24: the O135 cut (1 point every 6 levels past 1100) took points, and the login refund wiped the
-- allocation. The first login after the fix gives the old track's points back, once.
eq(P.legacyPoints(1000), 0, "no legacy at the start"); eq(P.legacyPoints(1100), 0, "none up to slowFrom")
eq(P.legacyPoints(1500), 500 - P.totalPoints(1500), "level 1500: the old 500 minus the new total")
eq(P.totalPoints(1500) + P.legacyPoints(1500), 500, "level 1500 owns the old 500 again")
for L = 1000, 2400, 7 do assert(P.legacyPoints(L) >= 0, "never negative " .. L) end
local LEG = Chaos.storage.paragonLegacy; assert(LEG, "legacy storage key")
P.cache = {}; rows[70] = {}
local old1500, oldst = mkPlayer(1500, 0); oldst[LEG] = -1
registered["ChaosParagonLogin"].onLogin(setmetatable({registerEvent = function() end}, {__index = old1500}))
eq(oldst[LEG], 500 - P.totalPoints(1500), "granted at login")
eq(P.pointsOf(old1500), 500, "the old total is back")
P.actions.paragonMastery(old1500, {key = "mDamage", n = 400}); eq(rows[70].mDamage, 400, "the points back are spendable")
registered["ChaosParagonLogin"].onLogin(setmetatable({registerEvent = function() end}, {__index = old1500}))
eq(oldst[LEG], 500 - P.totalPoints(1500), "granted once"); eq(rows[70].mDamage, 400, "no refund at the next login")
-- a character at 1050 at the fix gets nothing, and later levels follow the new track
local mid, midst = mkPlayer(1050, 0); midst[LEG] = -1; P.cache = {}
registered["ChaosParagonLogin"].onLogin(setmetatable({registerEvent = function() end}, {__index = mid}))
eq(midst[LEG], 0, "nothing below slowFrom"); eq(P.pointsOf(mid), 50, "new track only")

-- O190 (beta 2026-10-24: "the tree keeps resetting when the player dies"): death -> level loss -> relogin keeps the
-- allocation, at every level around the point thresholds and past 1100. Spending is capped by the points owned.
do
  local levels = {}
  for _, base in ipairs({1000, 1001, 1099, 1100, 1101, 1105, 1106, 1112, 1500, 2192}) do
    for d = -1, 1 do levels[#levels + 1] = base + d end
  end
  local checks = 0
  for _, L in ipairs(levels) do
    local own = P.totalPoints(L)
    for _, loss in ipairs({1, 2, 5, 6, 50, 400}) do
      local after = L - loss
      local alloc = {}
      local left = own
      for _, key in ipairs(P.order) do
        local n = math.min(left, P.defs[key].maxPoints)
        if n > 0 then alloc[key] = n; left = left - n end
      end
      if left > 0 then alloc.mDamage = left end
      rows[70] = {}; for k, v in pairs(alloc) do rows[70][k] = v end
      -- death: the level falls, the character logs in again (a fresh cache)
      local dead = mkPlayer(after, 0)
      P.cache = {}
      registered["ChaosParagonLogin"].onLogin(setmetatable({registerEvent = function() end, getLevel = function() return after end,
        getStorageValue = function(_, k) if k == LEG then return 0 end return 0 end}, {__index = dead}))
      for k, v in pairs(alloc) do eq(rows[70][k], v, "kept " .. k .. " at " .. L .. " -> " .. after) end
      eq(P.debt(alloc, P.totalPoints(after)), math.max(0, own - P.totalPoints(after)), "debt")
      -- over budget: nothing more can be spent until the points are back
      if P.totalPoints(after) < own then
        local more = P.validate({damage = (alloc.damage or 0) + 1}, alloc, P.totalPoints(after), after)
        eq(more, nil, "no new spending in debt")
      end
      checks = checks + 1
    end
  end
  assert(checks > 100)
end
eq(Chaos.paragon.slowFrom, 1100, "death test thresholds follow the config")

print("paragon: all asserts passed")
