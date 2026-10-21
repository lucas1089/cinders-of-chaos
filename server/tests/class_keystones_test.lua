-- Run from the server/ folder: lua5.3 tests/class_keystones_test.lua (mock of the engine API; CI runs it)
-- The signature keystones of the Thief, Necromancer, Monk and Templar lines (621 / 624 variants, 2026-10-20):
-- the rules of class_keystones_core.lua, the balance model against Ricochet and Deadeye, the engine glue in
-- passivetree_keystones.lua against mocked creatures (procs, prices, the guard, an error never breaks a hit), the
-- generated tree data per class and that the client tooltips state the server's numbers.
local n = 0
setmetatable(_G, {__index = function(t, k)
  if type(k) == "string" and k:match("^[A-Z_0-9]+$") then n = n + 1; rawset(t, k, n); return n end
end})
local function eq(a, b, m) if a ~= b then error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2) end end
local function near(a, b, m) if math.abs(a - b) > 1e-9 then error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2) end end

-- ---------------------------------------------------------------- engine mocks (as passivetree_keystones_test.lua)
local registered = {}
EventCallback = setmetatable({}, {__newindex = function(t, k, v) rawset(t, "_last", {k, v}) end})
rawset(EventCallback, "register", function(self) local l = rawget(self, "_last"); registered[l[1]] = l[2] end)
function CreatureEvent(name)
  local o = {}
  function o:register() registered[name] = o end
  function o:type() end
  return o
end
bit = bit or {band = function(a, b) return (a % (2 * b) >= b) and b or 0 end}
NOW = 100000
os.mtime = function() return NOW end
local queue = {}
function addEvent(fn, delay, ...) queue[#queue + 1] = {fn = fn, args = {...}, delay = delay} end
local function runEvents()
  local guard = 0
  while #queue > 0 do
    local e = table.remove(queue, 1)
    e.fn((table.unpack or unpack)(e.args))
    guard = guard + 1
    assert(guard < 200, "event loop")
  end
end

local creatures = {}
local function pos(x, y, z) return {x = x, y = y, z = z or 7} end
local effects = {}
Position = function(x, y, z)
  if type(x) == "table" then x, y, z = x.x, x.y, x.z end
  local p = {x = x, y = y, z = z}
  function p:sendMagicEffect(e) effects[#effects + 1] = e end
  function p:sendDistanceEffect() end
  function p:isSightClear() return true end
  return p
end
local function mkCreature(id, p, kind)
  local c = {id = id, p = p, kind = kind, health = 100000, maxHealth = 100000, conds = {}, slots = {}, events = {}, ml = 100,
    level = 300}
  function c:getId() return self.id end
  function c:getPosition() return Position(self.p) end
  function c:getHealth() return self.health end
  function c:getMaxHealth() return self.maxHealth end
  function c:isPlayer() return self.kind == "player" end
  function c:isMonster() return self.kind == "monster" end
  function c:getMaster() return self.master end
  function c:hasCondition(t) return self.conds[t] == true end
  function c:getSlotItem(s) return self.slots[s] end
  function c:getMagicLevel() return self.ml end
  function c:getLevel() return self.level end
  function c:registerEvent(e) self.events[e] = true end
  function c:getParty() return nil end
  creatures[id] = c
  return c
end
local function clear() for id in pairs(creatures) do creatures[id] = nil end end
Creature = function(id) return creatures[id] end
Player = function(id) local c = creatures[id]; return c and c.kind == "player" and c or nil end
Game = {getSpectators = function(center, _, _, rx)
  local list = {}
  for _, c in pairs(creatures) do
    if c.p.z == center.z and math.abs(c.p.x - center.x) <= rx and math.abs(c.p.y - center.y) <= rx then list[#list + 1] = c end
  end
  table.sort(list, function(a, b) return a.id < b.id end)
  return list
end}
local items = {}
local function item(id, weaponType, slotPos)
  items[id] = {wt = weaponType, sp = slotPos or 0}
  return {getId = function() return id end}
end
ItemType = function(id)
  local d = items[id]
  return {getId = function() return id end, getWeaponType = function() return d.wt end,
    getSlotPosition = function() return d.sp end, getAmmoType = function() return 0 end}
end
SLOTP_TWO_HAND = 32
local dealt = {}
function doTargetCombat(attacker, target, ctype, min, max, effect, origin)
  dealt[#dealt + 1] = {attacker = type(attacker) == "table" and attacker.id or attacker, target = target.id, type = ctype,
    amount = min, origin = origin, depth = ChaosKeystones.depth}
  -- the engine runs the target's damage events (and its death) inside this call
  local a = type(attacker) == "table" and attacker or nil
  registered["ChaosKeystones"].onHealthChange(target, a, math.abs(min), ctype, 0, COMBAT_NONE, origin)
  registered["ChaosClassKeystones"].onHealthChange(target, a, math.abs(min), ctype, 0, COMBAT_NONE, origin)
  if target.health <= math.abs(min) then
    target.health = 0
    registered["ChaosClassKeystonesDeath"].onDeath(target, nil, a, a)
  end
  return true
end
ChaosSpell = {
  canAttack = function(caster, target) return target.pvpOk == true end,
  isEnemy = function(caster, target) return target:isMonster() and not target.master end,
}
ChaosPassiveCache = {}

dofile("data/scripts/chaos/passivetree_keystones.lua")
local K, CK = ChaosKeystones, ChaosClassKeystones
local c = CK.cfg
local ev, cev, dev = registered["ChaosKeystones"], registered["ChaosClassKeystones"], registered["ChaosClassKeystonesDeath"]
assert(ev and cev and dev and registered["onSpawn"], "events registered")
local spawned = mkCreature(999, pos(1, 1), "monster")
registered["onSpawn"](spawned, spawned.p, false, false)
assert(spawned.events.ChaosClassKeystones and spawned.events.ChaosClassKeystonesDeath, "every monster gets both at spawn")
clear()

local always, never = function() return 1 end, function() return 100 end

-- ---------------------------------------------------------------- pure rules
eq(CK.shadowTwin(-1000, always), 600, "Shadow Twin: 60% of the hit"); eq(CK.shadowTwin(1000, never), 0, "failed roll")
near(CK.shadowTwinTaken(), 1.06, "Shadow Twin's price")
local m, vital = CK.viperStep(true, always); near(m, 2.0, "Viper's Verdict on a poisoned target"); assert(vital)
m, vital = CK.viperStep(true, never); near(m, 1, "no vital"); assert(not vital)
m, vital = CK.viperStep(false, always); near(m, 0.85, "not poisoned: the price"); assert(not vital)
eq(CK.corpseBlastAmount(10000, 300), 1200, "12% of the maximum health")
eq(CK.corpseBlastAmount(1000000, 300), 4500, "at most 15 x level")
local field = {{id = 5, pos = pos(12, 10)}, {id = 4, pos = pos(11, 10)}, {id = 3, pos = pos(13, 10)}, {id = 9, pos = pos(10, 10)}}
local picked = CK.corpseBlastPick(field, pos(10, 10), 9)
eq(#picked, 2, "within 2 sqm, not the dead one"); eq(picked[1].id, 4, "nearest first")
local many = {}
for i = 1, 10 do many[i] = {id = i, pos = pos(10 + (i % 3) - 1, 10 + 1)} end
eq(#CK.corpseBlastPick(many, pos(10, 10), 0), c.ksCorpseBlast.maxTargets, "at most 6")
m = CK.reaperFactor(40000, 100000); near(m, 2.0, "at 40%: +100%")
m = CK.reaperFactor(40001, 100000); near(m, 0.92, "above: the price")
near(CK.reaperFactor(1, 0), 1, "no maximum health")
local ps, fin = {}, nil
for i = 1, 4 do m, fin = CK.palmStep(ps, i * 100); near(m, 0.9, "palm " .. i); assert(not fin) end
m, fin = CK.palmStep(ps, 500); near(m, 2.2, "the 5th hit is the finisher"); assert(fin)
m, fin = CK.palmStep(ps, 600); near(m, 0.9, "the count starts over")
CK.palmStep(ps, 700); CK.palmStep(ps, 800); CK.palmStep(ps, 900)
m, fin = CK.palmStep(ps, 900 + c.ksSeventhPalm.windowMs + 1); assert(not fin, "4 s without a hit start the count again")
eq(CK.palmShock(-2200), 1100, "shockwave 50% of the finisher")
eq(#CK.palmShockPick(many, pos(10, 10), 1), 4, "at most 4 next to the target")
-- Piercing Palm: the attacker at (10,10), the target east at (11,10); behind it (12,10) and (13,10); one beside the attacker
local line = {{id = 2, pos = pos(11, 10)}, {id = 3, pos = pos(12, 10)}, {id = 4, pos = pos(13, 10)}, {id = 5, pos = pos(10, 11)},
  {id = 6, pos = pos(14, 10)}}
local steps = CK.piercePlan(pos(10, 10), {id = 2, pos = pos(11, 10)}, 1000, function() return line end)
eq(#steps, 2, "two behind"); eq(steps[1].id, 3); eq(steps[1].amount, 700, "70%"); eq(steps[2].id, 4); eq(steps[2].amount, 400, "40%")
steps = CK.piercePlan(pos(10, 10), {id = 2, pos = pos(11, 10)}, 1000, function() return {{id = 5, pos = pos(10, 11)}, {id = 7, pos = pos(11, 11)}} end)
eq(#steps, 0, "nobody farther from the attacker than the target: no pierce")
local rs = {}
local blocked, nova = CK.rebukeBlock(rs, 1000, always); assert(blocked and nova, "block and nova")
blocked, nova = CK.rebukeBlock(rs, 1500, always); assert(blocked and not nova, "nova cooldown 1 s, the block stays")
blocked, nova = CK.rebukeBlock(rs, 2000, always); assert(blocked and nova, "cooldown over")
blocked = CK.rebukeBlock(rs, 9000, never); assert(not blocked, "failed roll")
eq(CK.rebukeNova(-1000, 50), 1200, "the blocked hit + 4 x magic level")
local ring = {}
for i = 1, 12 do ring[i] = {id = i, pos = pos(10 + (i % 5) - 2, 10 + (i % 3) - 1)} end
eq(#CK.rebukePick(ring, pos(10, 10)), 8, "at most 8")
field = {{id = 20, pos = pos(12, 10)}, {id = 21, pos = pos(14, 10)}, {id = 22, pos = pos(18, 10)}, {id = 10, pos = pos(10, 10)}}
steps = CK.dawnchainPlan(pos(10, 10), 10, 1000, function() return field end)
eq(#steps, 2, "two links"); eq(steps[1].id, 20); eq(steps[1].amount, 550, "55%"); eq(steps[2].id, 21); eq(steps[2].amount, 302, "55% of 55%")
eq(#CK.dawnchainPlan(pos(10, 10), 10, 1000, function() return {{id = 22, pos = pos(14, 10)}} end), 0, "out of range (4 > 3)")
assert(CK.holds({ksDawnchain = 1}) and not CK.holds({ksRicochet = 1}) and not CK.holds(nil), "holds")

-- ---------------------------------------------------------------- the balance model against Ricochet and Deadeye
-- Each new keystone, in its best case (one enemy or a pack of five), gains at least what Deadeye gives a crossbow and at
-- most 5% more than Ricochet gives a pack; on one enemy none passes Shadow Twin's +18% or loses more than its price.
local model = CK.model(K.cfg)
near(model.Ricochet.pack, 1 + 0.65 + 0.65 * 0.65, "Ricochet: 2.07 in a pack"); near(model.Deadeye.single, 1.15, "Deadeye +15%")
for _, key in ipairs({"ksShadowTwin", "ksViperVerdict", "ksCorpseBlast", "ksReapersToll", "ksSeventhPalm", "ksPiercingPalm", "ksDawnchain"}) do
  local r = model[key]
  local best = math.max(r.single, r.pack)
  assert(best >= model.Deadeye.single - 1e-9, key .. " best case " .. best .. " below Deadeye's")
  assert(best <= model.Ricochet.pack * 1.05, key .. " best case " .. best .. " above Ricochet's")
  assert(r.single <= 1.20 and r.single >= 0.90, key .. " one enemy " .. r.single)
end
near(model.ksShadowTwin.single, 1.18, "Shadow Twin +18%")
near(model.ksViperVerdict.single, 0.9 * 1.2 + 0.1 * 0.85, "Viper's Verdict with 90% poison uptime")
assert(model.ksRadiantRebuke.takenWeapon < 1 - K.cfg.bulwark.blockChance / 100 + 1e-9, "Radiant Rebuke blocks more than Bulwark")

-- ---------------------------------------------------------------- engine glue
math.random = function() return 1 end -- every chance procs
-- Thief: Shadow Twin and Viper's Verdict on a poisoned target
local thief = mkCreature(1, pos(100, 100), "player")
thief.slots[CONST_SLOT_LEFT] = item(500, WEAPON_SWORD)
ChaosPassiveCache[1] = {ksShadowTwin = 1, ksViperVerdict = 1}
local mob = mkCreature(10, pos(101, 100), "monster")
mob.conds[CONDITION_POISON] = true
dealt = {}
local pd = ev.onHealthChange(mob, thief, 1000, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, ORIGIN_MELEE)
eq(pd, 2000, "a vital on the poisoned target"); runEvents()
eq(#dealt, 1, "the shadow strikes once"); eq(dealt[1].target, 10, "the same target"); eq(dealt[1].amount, -1200, "60% of the hit")
eq(dealt[1].depth, 1, "guarded"); eq(dealt[1].origin, ORIGIN_SPELL)
mob.conds[CONDITION_POISON] = nil
math.random = function() return 100 end; dealt = {}
pd = ev.onHealthChange(mob, thief, 1000, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, ORIGIN_MELEE); runEvents()
eq(pd, 850, "not poisoned: x0.85"); eq(#dealt, 0, "no shadow on a failed roll")
local taken = ev.onHealthChange(thief, mob, 1000, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, ORIGIN_MELEE)
eq(taken, 1060, "Shadow Twin: 6% more damage taken")
thief.slots[CONST_SLOT_LEFT] = item(501, WEAPON_WAND); dealt = {}
math.random = function() return 1 end
pd = ev.onHealthChange(mob, thief, 1000, COMBAT_ENERGYDAMAGE, 0, COMBAT_NONE, ORIGIN_RANGED); runEvents()
eq(pd, 1000, "a wand is no weapon hit for them"); eq(#dealt, 0)
thief.slots[CONST_SLOT_LEFT] = nil
pd = ev.onHealthChange(mob, thief, 1000, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, ORIGIN_MELEE); runEvents()
eq(pd, 1000, "fists: nothing for the Thief line"); eq(#dealt, 0)
K.depth = 1; ev.onHealthChange(mob, thief, 1000, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, ORIGIN_MELEE); K.depth = 0
eq(#queue, 0, "guard: a proc's hit procs nothing")

-- Monk: Seventh Palm with fists, the finisher's shockwave; Piercing Palm through a line
clear()
local monk = mkCreature(2, pos(200, 200), "player")
ChaosPassiveCache[2] = {ksSeventhPalm = 1}
local t1 = mkCreature(20, pos(201, 200), "monster")
mkCreature(21, pos(202, 200), "monster"); mkCreature(22, pos(202, 201), "monster"); mkCreature(23, pos(205, 200), "monster")
dealt = {}
for i = 1, 4 do eq(ev.onHealthChange(t1, monk, 1000, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, ORIGIN_MELEE), 900, "palm " .. i) end
runEvents(); eq(#dealt, 0, "no shockwave before the finisher")
eq(ev.onHealthChange(t1, monk, 1000, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, ORIGIN_MELEE), 2200, "the finisher"); runEvents()
eq(#dealt, 2, "shockwave on the two next to the target"); eq(dealt[1].amount, -1100, "50% of the finisher")
monk.slots[CONST_SLOT_LEFT] = item(510, WEAPON_DISTANCE)
eq(ev.onHealthChange(t1, monk, 1000, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, ORIGIN_MELEE), 1000, "a bow is no palm")
monk.slots[CONST_SLOT_LEFT] = nil
ChaosPassiveCache[2] = {ksPiercingPalm = 1}; dealt = {}
mkCreature(24, pos(203, 200), "monster") -- behind 21 (22 beside it is no farther from the monk than 21)
eq(ev.onHealthChange(t1, monk, 1000, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, ORIGIN_MELEE), 950, "the hit x0.95"); runEvents()
eq(#dealt, 2, "pierces two"); eq(dealt[1].target, 21, "behind the target first"); eq(dealt[1].amount, -665, "70% of 950")
eq(dealt[2].amount, -380, "40% of 950")

-- Templar: Radiant Rebuke blocks and sends the nova, Dawnchain chains weapon hits, its spells pay
clear()
local templar = mkCreature(3, pos(300, 300), "player")
templar.slots[CONST_SLOT_RIGHT] = item(700, WEAPON_SHIELD)
templar.slots[CONST_SLOT_LEFT] = item(701, WEAPON_CLUB)
templar.ml = 50
ChaosPassiveCache[3] = {ksRadiantRebuke = 1}
local brute = mkCreature(30, pos(301, 300), "monster"); mkCreature(31, pos(302, 302), "monster"); mkCreature(32, pos(304, 303), "monster")
dealt = {}
eq(ev.onHealthChange(templar, brute, 800, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, ORIGIN_MELEE), 0, "blocked"); runEvents()
eq(#dealt, 2, "the nova hits the two within 2 sqm"); eq(dealt[1].amount, -1000, "800 + 4 x 50"); eq(dealt[1].type, COMBAT_HOLYDAMAGE)
dealt = {}; ev.onHealthChange(templar, brute, 800, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, ORIGIN_MELEE); runEvents()
eq(#dealt, 0, "blocked again, the nova waits 1 s")
eq(ev.onHealthChange(templar, brute, 800, COMBAT_FIREDAMAGE, 0, COMBAT_NONE, ORIGIN_SPELL), 800, "spells are not blocked")
eq(ev.onHealthChange(brute, templar, 1000, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, ORIGIN_MELEE), 900, "weapon hits x0.90")
templar.slots[CONST_SLOT_RIGHT] = nil
math.random = function() return 1 end
eq(ev.onHealthChange(templar, brute, 800, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, ORIGIN_MELEE), 800, "no shield, no block")
ChaosPassiveCache[3] = {ksDawnchain = 1}; dealt = {}
eq(ev.onHealthChange(brute, templar, 1000, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, ORIGIN_MELEE), 1000, "Dawnchain leaves the hit"); runEvents()
eq(#dealt, 2, "two links"); eq(dealt[1].target, 31); eq(dealt[1].amount, -550); eq(dealt[1].type, COMBAT_HOLYDAMAGE)
eq(dealt[2].target, 32, "then from there"); eq(dealt[2].amount, -302)
local spellHit = cev.onHealthChange(brute, templar, 1000, COMBAT_HOLYDAMAGE, 0, COMBAT_NONE, ORIGIN_SPELL)
eq(spellHit, 900, "Dawnchain: spells x0.90")
eq(cev.onHealthChange(brute, templar, 1000, COMBAT_HOLYDAMAGE, 0, COMBAT_NONE, ORIGIN_CONDITION), 1000, "not damage over time")

-- Necromancer: Reaper's Toll and Corpse Detonation's price on the holder's and its minions' hits; the explosion
clear()
local necro = mkCreature(4, pos(400, 400), "player"); necro.level = 300
ChaosPassiveCache[4] = {ksReapersToll = 1}
local skel = mkCreature(41, pos(401, 401), "monster"); skel.master = necro
local prey = mkCreature(40, pos(401, 400), "monster")
eq(cev.onHealthChange(prey, necro, 1000, COMBAT_DEATHDAMAGE, 0, COMBAT_NONE, ORIGIN_SPELL), 920, "above 40%: x0.92")
prey.health = 40000; effects = {}
eq(cev.onHealthChange(prey, necro, 1000, COMBAT_DEATHDAMAGE, 0, COMBAT_NONE, ORIGIN_SPELL), 2000, "at 40%: x2")
eq(#effects, 1, "the scythe once"); cev.onHealthChange(prey, necro, 1000, COMBAT_DEATHDAMAGE, 0, COMBAT_NONE, ORIGIN_SPELL)
eq(#effects, 1, "not again on the same monster")
eq(cev.onHealthChange(prey, skel, 1000, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, ORIGIN_MELEE), 2000, "the minion's hit too")
eq(cev.onHealthChange(skel, necro, 1000, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, ORIGIN_SPELL), 1000, "not on its own minion")
eq(cev.onHealthChange(prey, necro, 1000, COMBAT_DEATHDAMAGE, 0, COMBAT_NONE, ORIGIN_CONDITION), 1000, "not damage over time")
K.depth = 1
eq(cev.onHealthChange(prey, necro, 1000, COMBAT_DEATHDAMAGE, 0, COMBAT_NONE, ORIGIN_SPELL), 1000, "not a proc")
K.depth = 0
ChaosPassiveCache[4] = {ksCorpseBlast = 1}
prey.health, prey.maxHealth = 100000, 10000
eq(cev.onHealthChange(prey, skel, 1000, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, ORIGIN_MELEE), 920, "Corpse Detonation's price")
local n1 = mkCreature(42, pos(402, 400), "monster"); n1.health = 1000
local n2 = mkCreature(43, pos(403, 401), "monster")
mkCreature(44, pos(405, 400), "monster")
dealt = {}
dev.onDeath(prey, nil, skel, skel); runEvents()
eq(#dealt, 2, "the minion's kill explodes on the two within 2 sqm (not the minion, not the one 4 sqm away)")
eq(dealt[1].amount, -1200, "12% of the maximum health"); eq(dealt[1].type, COMBAT_DEATHDAMAGE)
eq(n1.health, 0, "the explosion killed one"); eq(#queue, 0, "an explosion's kill does not explode")
dealt = {}; dev.onDeath(n2, nil, mkCreature(45, pos(1, 1), "player"), nil); runEvents()
eq(#dealt, 0, "another player's kill: no explosion")

-- an error in a keystone never breaks the hit
clear()
local broken = mkCreature(5, pos(500, 500), "player")
ChaosPassiveCache[5] = {ksSeventhPalm = 1}
local target = mkCreature(50, pos(501, 500), "monster")
local realStep = CK.palmStep
CK.palmStep = function() error("boom") end
local printed = print
print = function() end
eq(ev.onHealthChange(target, broken, 1000, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, ORIGIN_MELEE), 1000, "the hit lands unchanged")
CK.palmStep = realStep
ChaosPassiveCache[5] = {ksReapersToll = 1}
local realReap = CK.reaperFactor
CK.reaperFactor = function() error("boom") end
eq(cev.onHealthChange(target, broken, 1000, COMBAT_DEATHDAMAGE, 0, COMBAT_NONE, ORIGIN_SPELL), 1000, "the factor event too")
CK.reaperFactor = realReap
print = printed

-- ---------------------------------------------------------------- the generated data and the class variants
local data = dofile("data/scripts/chaos/passivetree_data.lua")
for node, byClass in pairs(c.variants) do
  for cls, key in pairs(byClass) do
    eq(data.nodes[node].v[cls] and data.nodes[node].v[cls][key], 1, node .. " " .. cls .. " " .. key)
    eq(data.nodes[node].c[cls], true, node .. " may be taken by " .. cls)
  end
end
local savedChaos = Chaos
Chaos = nil
dofile("data/scripts/chaos/chaos_constants.lua")
local realClasses = Chaos.classes
Chaos = {classes = realClasses, passive = {}, tables = {passiveTree = "chaos_passive_tree"}, storage = {}, load = function(f) return dofile("data/scripts/chaos/" .. f) end,
  select = function() return {{preset = 1, name = "p", nodes = "619,620,621,622,623,624"}} end}
ChaosOpcodes = {}
db = {escapeString = function(s) return "'" .. s .. "'" end, query = function() end}
dofile("data/scripts/chaos/passivetree.lua")
local function voc(id) return {getGuid = function() return 1 end, getVocation = function() return {getId = function() return id end} end} end
local want = {[11] = {"ksShadowTwin", "ksViperVerdict"}, [12] = {"ksShadowTwin", "ksViperVerdict"}, [13] = {"ksShadowTwin", "ksViperVerdict"},
  [20] = {"ksCorpseBlast", "ksReapersToll"}, [21] = {"ksCorpseBlast", "ksReapersToll"}, [22] = {"ksCorpseBlast", "ksReapersToll"},
  [17] = {"ksSeventhPalm", "ksPiercingPalm"}, [18] = {"ksSeventhPalm", "ksPiercingPalm"}, [19] = {"ksOvergrowth", "ksPiercingPalm"},
  [23] = {"ksRadiantRebuke", "ksDawnchain"}, [24] = {"ksRadiantRebuke", "ksDawnchain"}, [25] = {"ksRadiantRebuke", "ksThorns"}}
for vocId, keys in pairs(want) do
  local b = ChaosPassiveTree.getBonuses(voc(vocId))
  for _, key in ipairs(keys) do eq(b[key], 1, "class " .. vocId .. " " .. key) end
  local count = 0
  for key in pairs(b) do if key:sub(1, 2) == "ks" then count = count + 1 end end
  eq(count, 2, "class " .. vocId .. ": exactly its pair")
end
Chaos = savedChaos

-- ---------------------------------------------------------------- the client tooltips state the server's numbers
local nodesFile = "../client/overlay/modules/game_passivetree/treedata/nodes.lua"
local f = io.open(nodesFile)
if f then
  f:close()
  dofile(nodesFile)
  local nodes = getTreeNodes()
  local function pct(x) return tostring(math.floor(x * 100 + 0.5)) .. "%" end
  local function sec(ms) return (ms % 1000 == 0 and tostring(math.floor(ms / 1000)) or tostring(ms / 1000)) .. " s" end
  local needles = {
    ksShadowTwin = {c.ksShadowTwin.chance .. "%", sec(c.ksShadowTwin.delayMs), pct(c.ksShadowTwin.percent), pct(c.ksShadowTwin.taken) .. " more"},
    ksViperVerdict = {c.ksViperVerdict.chance .. "%", "+" .. pct(c.ksViperVerdict.multiplier - 1), pct(1 - c.ksViperVerdict.price) .. "\nless"},
    ksCorpseBlast = {pct(c.ksCorpseBlast.percent), c.ksCorpseBlast.perLevel .. " x your level", "up to " .. c.ksCorpseBlast.maxTargets,
      c.ksCorpseBlast.radius .. " sqm", pct(1 - c.ksCorpseBlast.price) .. " less"},
    ksReapersToll = {pct(c.ksReapersToll.below), pct(c.ksReapersToll.bonus) .. " more", pct(1 - c.ksReapersToll.price) .. " less"},
    ksSeventhPalm = {c.ksSeventhPalm.every .. "th", sec(c.ksSeventhPalm.windowMs), pct(c.ksSeventhPalm.finisher - 1) .. " more",
      "up to " .. c.ksSeventhPalm.maxTargets, pct(c.ksSeventhPalm.shockShare), pct(1 - c.ksSeventhPalm.price) .. " less"},
    ksPiercingPalm = {pct(c.ksPiercingPalm.first), pct(c.ksPiercingPalm.second), pct(1 - c.ksPiercingPalm.price) .. "\nless"},
    ksRadiantRebuke = {c.ksRadiantRebuke.blockChance .. "%", sec(c.ksRadiantRebuke.icdMs), "up to " .. c.ksRadiantRebuke.maxTargets,
      c.ksRadiantRebuke.radius .. " sqm", c.ksRadiantRebuke.perMagicLevel .. " x your magic level", pct(1 - c.ksRadiantRebuke.price) .. " less"},
    ksDawnchain = {c.ksDawnchain.range .. " sqm", pct(c.ksDawnchain.percent) .. " of the hit", "(" .. pct(c.ksDawnchain.percent * c.ksDawnchain.falloff) .. ")",
      pct(1 - c.ksDawnchain.spellPrice) .. " less"},
  }
  for node, byClass in pairs(c.variants) do
    for cls, key in pairs(byClass) do
      local v = nodes[node][cls]
      assert(v and v.customStats[key] == 1 and v.icon == key, node .. " " .. cls .. ": the client variant")
      local text = table.concat(v.stats, "\n")
      local flat = table.concat(v.stats, " ")
      for _, needle in ipairs(needles[key]) do
        local plain = needle:gsub("\n", " ")
        assert(text:find(needle, 1, true) or flat:find(plain, 1, true), cls .. " node " .. node .. " tooltip lacks '" .. plain .. "': " .. flat)
      end
    end
  end
  for _, id in ipairs({621, 624}) do eq(#nodes[id].classes, 21, id .. ": every class may take it") end
end
print("class keystones: all asserts passed")
