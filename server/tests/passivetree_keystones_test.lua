-- Run from the server/ folder: lua5.3 tests/passivetree_keystones_test.lua (mock of the engine API; CI runs it)
-- Covers the keystone maths (chances, ricochet targets, cooldowns, overload), the engine glue against mocked
-- creatures (cleave, ricochet, deadeye, bulwark, thorns, regrowth, recursion guard), the per-vocation stats of the
-- generated tree data and that the client tooltips state the numbers the server uses.
local n = 0
setmetatable(_G, {__index = function(t, k)
  if type(k) == "string" and k:match("^[A-Z_0-9]+$") then n = n + 1; rawset(t, k, n); return n end
end})
local function eq(a, b, m) if a ~= b then error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2) end end

-- ---------------------------------------------------------------- engine mocks
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
os.mtime = function() return NOW end
NOW = 100000
local queue = {}
function addEvent(fn, delay, ...) queue[#queue + 1] = {fn = fn, args = {...}, delay = delay} end
local function runEvents()
  local guard = 0
  while #queue > 0 do
    local e = table.remove(queue, 1)
    e.fn((table.unpack or unpack)(e.args))
    guard = guard + 1
    assert(guard < 100, "event loop")
  end
end

local creatures = {}
local function pos(x, y, z) return {x = x, y = y, z = z or 7} end
Position = function(x, y, z)
  if type(x) == "table" then x, y, z = x.x, x.y, x.z end
  local p = {x = x, y = y, z = z}
  function p:sendMagicEffect() end
  function p:sendDistanceEffect() end
  function p:isSightClear() return true end
  return p
end
local function mkCreature(id, p, kind)
  local c = {id = id, p = p, kind = kind, health = 100000, conds = {}, slots = {}, events = {}, ml = 100}
  function c:getId() return self.id end
  function c:getPosition() return Position(self.p) end
  function c:getHealth() return self.health end
  function c:isPlayer() return self.kind == "player" end
  function c:isMonster() return self.kind == "monster" end
  function c:getMaster() return nil end
  function c:hasCondition(t) return self.conds[t] == true end
  function c:getSlotItem(s) return self.slots[s] end
  function c:getMagicLevel() return self.ml end
  function c:registerEvent(e) self.events[e] = true end
  function c:getParty() return nil end
  creatures[id] = c
  return c
end
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
local function item(id, weaponType, slotPos, ammoType)
  items[id] = {wt = weaponType, sp = slotPos or 0, at = ammoType or 0}
  return {getId = function() return id end}
end
ItemType = function(id)
  local d = items[id]
  return {getId = function() return id end, getWeaponType = function() return d.wt end,
    getSlotPosition = function() return d.sp end, getAmmoType = function() return d.at end}
end
SLOTP_TWO_HAND = 32
local dealt = {}
function doTargetCombat(attacker, target, ctype, min, max, effect, origin)
  dealt[#dealt + 1] = {attacker = type(attacker) == "table" and attacker.id or attacker, target = target.id, type = ctype,
    amount = min, origin = origin, depth = ChaosKeystones.depth}
  -- the engine runs the target's damage events inside this call: they must not start new procs
  local ev = registered["ChaosKeystones"]
  ev.onHealthChange(target, type(attacker) == "table" and attacker or nil, math.abs(min), ctype, 0, COMBAT_NONE, origin)
  return true
end
ChaosSpell = {
  canAttack = function(caster, target) return target.pvpOk == true end,
  isEnemy = function(caster, target) return target:isMonster() end,
}
ChaosPassiveCache = {}

dofile("data/scripts/chaos/passivetree_keystones.lua")
local K, cfg = ChaosKeystones, ChaosKeystones.cfg
local ev = registered["ChaosKeystones"]
assert(ev and registered["onTargetCombat"], "events registered")

-- ---------------------------------------------------------------- pure logic
local always, never = function() return 1 end, function() return 100 end
assert(K.roll(30, always) and not K.roll(30, never) and not K.roll(0, always), "roll")
assert(K.roll(30, function() return 30 end) and not K.roll(30, function() return 31 end), "roll edge")
eq(K.scale(-1000, 0.4), -400, "scale keeps sign"); eq(K.scale(113, 1.25), 141, "scale rounds down")
eq(K.distance(pos(1, 1), pos(3, 2)), 2, "distance"); eq(K.distance(pos(1, 1, 7), pos(1, 1, 8)), math.huge, "floors")

local around = {{id = 5, pos = pos(11, 10)}, {id = 2, pos = pos(9, 9)}, {id = 3, pos = pos(10, 11)},
  {id = 4, pos = pos(12, 10)}, {id = 1, pos = pos(11, 11)}, {id = 6, pos = pos(9, 11)}}
local picked = K.cleavePick(around, pos(10, 10), 5, 3)
eq(#picked, 3, "cleave max 3"); eq(picked[1].id, 1, "cleave lowest ids"); eq(picked[3].id, 3, "cleave third")
for _, v in ipairs(picked) do assert(v.id ~= 5 and v.id ~= 4, "no main target, nothing two tiles away") end

-- ricochet: start at (10,10); A at 2 tiles, B at 3 tiles from start but 1 from A, C at 6 tiles (out of range)
local field = {{id = 20, pos = pos(12, 10)}, {id = 21, pos = pos(13, 10)}, {id = 22, pos = pos(16, 10)}, {id = 10, pos = pos(10, 10)}}
local function near(p) return field end
local steps = K.planRicochet(pos(10, 10), 10, 1000, near)
eq(#steps, 2, "two bounces"); eq(steps[1].id, 20, "nearest first"); eq(steps[1].amount, 650, "65%")
eq(steps[2].id, 21, "then nearest to the first bounce"); eq(steps[2].amount, 422, "65% of 65%")
for _, s in ipairs(steps) do assert(s.id ~= 10, "never the first target again") end
field = {{id = 20, pos = pos(12, 10)}, {id = 10, pos = pos(10, 10)}}
steps = K.planRicochet(pos(10, 10), 10, 1000, near)
eq(#steps, 1, "no second target: one bounce, no bounce back to the first")
field = {{id = 22, pos = pos(15, 10)}}
eq(#K.planRicochet(pos(10, 10), 10, 1000, near), 0, "out of range (5 > 4)")
eq(K.pickNearest(pos(0, 0), {{id = 9, pos = pos(2, 0)}, {id = 8, pos = pos(0, 2)}}, {}, 4).id, 8, "tie: lowest id")

-- echo: chance, minimum targets, cooldown
local st = {}
assert(not K.echoDecide(st, 0, 1, always), "one target is not an area hit")
assert(not K.echoDecide(st, 0, 3, never), "failed roll")
assert(K.echoDecide(st, 0, 3, always), "echo")
assert(not K.echoDecide(st, cfg.echo.cooldown - 1, 3, always), "cooldown")
assert(K.echoDecide(st, cfg.echo.cooldown, 3, always), "cooldown over")

-- overload: fire primes, the next ice cast gets +20% on all its hits, then ice primes the next other element
st = {}
eq(K.overloadStep(st, COMBAT_FIREDAMAGE, 0), 1, "first spell")
eq(K.overloadStep(st, COMBAT_FIREDAMAGE, 1000), 1, "same element")
eq(K.overloadStep(st, COMBAT_ICEDAMAGE, 2000), 1.2, "other element boosted")
eq(K.overloadStep(st, COMBAT_ICEDAMAGE, 2050), 1.2, "rest of the same cast boosted too")
eq(K.overloadStep(st, COMBAT_ICEDAMAGE, 4000), 1, "next ice cast: not boosted")
eq(K.overloadStep(st, COMBAT_FIREDAMAGE, 4000 + cfg.overload.window + 1), 1, "primed element expired")
eq(K.overloadStep(st, COMBAT_ENERGYDAMAGE, 20000), 1.2, "fire primed energy")

eq(K.thornsAmount(1000, 100), 500, "thorns 30% + 2 x ml"); eq(K.overgrowthPulse(900), 30, "regrowth pulse 10% / 3")
-- Overgrowth: a heal's share over the pulses, exactly (the last takes the rest); a new heal adds what is left
local plan, pool = K.overgrowthPlan(0, 1000)
eq(pool, 100, "10% of the heal"); eq(#plan, 3, "3 pulses"); eq(plan[1], 33); eq(plan[3], 34, "the last takes the rest")
plan, pool = K.overgrowthPlan(0, 1209)
eq(pool, 120, "rounded down"); eq(plan[1] + plan[2] + plan[3], 120, "the pulses heal the share")
plan, pool = K.overgrowthPlan(50, -1000)
eq(pool, 150, "the rest of the running regrowth + the new share"); eq(plan[1], 50); eq(plan[3], 50)
eq(select(2, K.overgrowthPlan(0, 0)), 0, "no heal, no regrowth")
assert(K.hasKeystone({ksBulwark = 1}) and not K.hasKeystone({strength = 3}) and not K.hasKeystone(nil), "hasKeystone")

-- ---------------------------------------------------------------- engine glue
math.random = function() return 1 end -- every chance procs
local knight = mkCreature(1, pos(100, 100), "player")
knight.slots[CONST_SLOT_LEFT] = item(500, WEAPON_SWORD, SLOTP_TWO_HAND)
ChaosPassiveCache[1] = {ksCleavingArc = 1}
local main = mkCreature(10, pos(101, 100), "monster")
mkCreature(11, pos(101, 101), "monster"); mkCreature(12, pos(99, 99), "monster"); mkCreature(13, pos(102, 100), "monster")
local other = mkCreature(14, pos(100, 101), "player") -- next to the knight, PvP not allowed
registered["onTargetCombat"](knight, main); assert(main.events.ChaosKeystones, "event put on the target")
local pd = ev.onHealthChange(main, knight, 1000, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, ORIGIN_MELEE)
eq(pd, 1000, "cleave does not change the hit"); runEvents()
eq(#dealt, 2, "cleave: two adjacent monsters, not the player, not the monster two tiles away")
eq(dealt[1].target, 11); eq(dealt[2].target, 12)
eq(dealt[1].amount, -400, "40% of the hit (the two-handed factor is already in it: this event runs after weapon_styles)")
eq(dealt[1].origin, ORIGIN_SPELL, "procs are spell origin (weapon_styles ignores them)"); eq(dealt[1].depth, 1, "guard up")
eq(#queue, 0, "the proc's own damage events started nothing")
other.pvpOk = true; dealt = {}
ev.onHealthChange(main, knight, 1000, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, ORIGIN_MELEE); runEvents()
eq(#dealt, 3, "a player PvP rules allow is cleaved too")
other.pvpOk = false
knight.slots[CONST_SLOT_LEFT] = item(501, WEAPON_SWORD, 0); dealt = {}
ev.onHealthChange(main, knight, 1000, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, ORIGIN_MELEE); runEvents()
eq(#dealt, 0, "one-handed: no cleave")
ev.onHealthChange(main, knight, 1000, COMBAT_FIREDAMAGE, 0, COMBAT_NONE, ORIGIN_SPELL); runEvents()
eq(#dealt, 0, "spells do not cleave")
-- under the guard nothing procs (a proc hitting a creature runs these events synchronously)
knight.slots[CONST_SLOT_LEFT] = item(500, WEAPON_SWORD, SLOTP_TWO_HAND)
K.depth = 1; ev.onHealthChange(main, knight, 1000, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, ORIGIN_MELEE); K.depth = 0
eq(#queue, 0, "guard")

-- paladin: deadeye doubles a crossbow hit (no ammunition: data/lib/chaos_archery_config.lua says 2455 is a crossbow),
-- ricochet bounces to the nearest monsters within 4
for id in pairs(creatures) do creatures[id] = nil end
local pal = mkCreature(2, pos(200, 200), "player")
pal.slots[CONST_SLOT_LEFT] = item(2455, WEAPON_DISTANCE, SLOTP_TWO_HAND)
ChaosPassiveCache[2] = {ksRicochet = 1, ksDeadeye = 1}
local t1 = mkCreature(20, pos(204, 200), "monster")
mkCreature(21, pos(206, 200), "monster"); mkCreature(22, pos(207, 201), "monster"); mkCreature(23, pos(212, 200), "monster")
dealt = {}
pd = ev.onHealthChange(t1, pal, 500, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, ORIGIN_RANGED)
eq(pd, 1000, "deadeye: double damage"); runEvents()
eq(#dealt, 2, "two bounces"); eq(dealt[1].target, 21); eq(dealt[2].target, 22)
eq(dealt[1].amount, -650, "65% of the deadeye hit")
eq(dealt[2].amount, -422, "65% of that")
pal.slots[CONST_SLOT_LEFT] = item(2456, WEAPON_DISTANCE, SLOTP_TWO_HAND); dealt = {} -- a bow
pd = ev.onHealthChange(t1, pal, 500, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, ORIGIN_RANGED)
eq(pd, 500, "deadeye needs a crossbow"); runEvents()
pal.slots[CONST_SLOT_LEFT] = item(2455, WEAPON_DISTANCE, SLOTP_TWO_HAND)
-- the ricochet is a sure bounce (chance 100 since 2026-10-17): a failing roll needs a lower chance
local ricochetChance = cfg.ricochet.chance
cfg.ricochet.chance = 50
math.random = function() return 100 end; dealt = {}
ev.onHealthChange(t1, pal, 500, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, ORIGIN_RANGED); runEvents()
eq(#dealt, 0, "no proc when the roll fails")
cfg.ricochet.chance = ricochetChance
math.random = function() return 1 end

-- knight with a shield: block, reflect; sentinel: thorns; both only against weapon attacks
for id in pairs(creatures) do creatures[id] = nil end
local tank = mkCreature(3, pos(300, 300), "player")
tank.slots[CONST_SLOT_RIGHT] = item(700, WEAPON_SHIELD)
ChaosPassiveCache[3] = {ksBulwark = 1}
local mob = mkCreature(30, pos(301, 300), "monster")
local fxCalls = {}
ChaosCombatFx = {dodge = function(c) fxCalls.dodge = c.id end, reflect = function(c) fxCalls.reflect = c.id end}
local d1 = ev.onHealthChange(tank, mob, 800, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, ORIGIN_MELEE)
eq(d1, 0, "blocked"); runEvents()
eq(fxCalls.dodge, 3, "block shows ChaosCombatFx.dodge")
math.random = function(a, b) return 50 end; dealt = {}
d1 = ev.onHealthChange(tank, mob, 800, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, ORIGIN_MELEE)
eq(d1, 800, "not blocked"); runEvents()
eq(#dealt, 1, "reflected"); eq(dealt[1].target, 30); eq(dealt[1].amount, -240, "30% reflected")
eq(fxCalls.reflect, 3, "reflect shows ChaosCombatFx.reflect")
ChaosCombatFx = nil
dealt = {}; ev.onHealthChange(tank, mob, 800, COMBAT_FIREDAMAGE, 0, COMBAT_NONE, ORIGIN_SPELL); runEvents()
eq(#dealt, 0, "spells are not reflected")
math.random = function() return 1 end
local sentinel = mkCreature(4, pos(400, 400), "player"); sentinel.ml = 120
ChaosPassiveCache[4] = {ksThorns = 1}
local mob2 = mkCreature(40, pos(401, 400), "monster")
dealt = {}; ev.onHealthChange(sentinel, mob2, 1000, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, ORIGIN_MELEE); runEvents()
eq(#dealt, 1, "thorns"); eq(dealt[1].amount, -540, "300 + 2 x 120"); eq(dealt[1].type, COMBAT_EARTHDAMAGE, "earth")
dealt = {}; ev.onHealthChange(sentinel, mob2, 1000, COMBAT_FIREDAMAGE, 0, COMBAT_NONE, ORIGIN_SPELL); runEvents()
eq(#dealt, 0, "no thorns against a spell")

-- regrowth (Iron Sage): a heal on another player plants 3 pulses of 10% / 3, as plain health (Chaos.heal: no health
-- event, so the healing rules and the stat window do not count again); self heals plant nothing
local healed = {}
Chaos = {heal = function(c, amount) healed[#healed + 1] = {target = c.id, amount = amount}; return amount end}
local sage = mkCreature(9, pos(403, 400), "player")
ChaosPassiveCache[9] = {ksOvergrowth = 1}
local ally = mkCreature(5, pos(402, 400), "player")
dealt = {}; ev.onHealthChange(ally, sage, 900, COMBAT_HEALING, 0, COMBAT_NONE, ORIGIN_SPELL); runEvents()
eq(#healed, 3, "three pulses"); eq(healed[1].amount, 30, "10% / 3"); eq(healed[3].target, 5, "on the ally")
eq(#dealt, 0, "the pulses are no new heal (no doTargetCombat)")
healed = {}; ev.onHealthChange(sage, sage, 900, COMBAT_HEALING, 0, COMBAT_NONE, ORIGIN_SPELL); runEvents()
eq(#healed, 0, "no regrowth on self heals")
ev.onHealthChange(ally, sage, 900, COMBAT_HEALING, 0, COMBAT_NONE, ORIGIN_CONDITION); runEvents()
eq(#healed, 0, "no regrowth from a heal over time")
-- a second heal while the first regrowth runs: what is left is added, nothing is lost
local held = {}
local realAdd = addEvent
addEvent = function(fn, delay, ...) held[#held + 1] = {fn = fn, args = {...}} end
ev.onHealthChange(ally, sage, 900, COMBAT_HEALING, 0, COMBAT_NONE, ORIGIN_SPELL)
eq(#held, 3, "three pulses planned")
held[1].fn((table.unpack or unpack)(held[1].args)) -- the first pulse (30) lands
ev.onHealthChange(ally, sage, 600, COMBAT_HEALING, 0, COMBAT_NONE, ORIGIN_SPELL) -- 60 left + 60 new
for i = 2, #held do held[i].fn((table.unpack or unpack)(held[i].args)) end
addEvent = realAdd
local total = 0
for _, h in ipairs(healed) do total = total + h.amount end
eq(total, 30 + 120, "the first pulse, then the rest of the first heal and the second's share")
eq(healed[#healed].amount, 40, "the new pulses: 120 / 3")
Chaos = nil

-- sorcerer echo: hits of one cast are buffered, the echo hits the same spots for 50% after the delay
local sorc = mkCreature(6, pos(500, 500), "player")
ChaosPassiveCache[6] = {ksArcaneEcho = 1}
local e1, e2 = mkCreature(60, pos(503, 500), "monster"), mkCreature(61, pos(504, 501), "monster")
dealt = {}
ev.onHealthChange(e1, sorc, 1000, COMBAT_ICEDAMAGE, 0, COMBAT_NONE, ORIGIN_SPELL)
ev.onHealthChange(e2, sorc, 800, COMBAT_ICEDAMAGE, 0, COMBAT_NONE, ORIGIN_SPELL)
runEvents()
eq(#dealt, 2, "echo on both"); eq(dealt[1].amount, -500, "50%"); eq(dealt[2].amount, -400, "50%")
dealt = {}
ev.onHealthChange(e1, sorc, 1000, COMBAT_ICEDAMAGE, 0, COMBAT_NONE, ORIGIN_SPELL)
ev.onHealthChange(e2, sorc, 800, COMBAT_ICEDAMAGE, 0, COMBAT_NONE, ORIGIN_SPELL)
runEvents(); eq(#dealt, 0, "echo cooldown")
NOW = NOW + cfg.echo.cooldown
ev.onHealthChange(e1, sorc, 1000, COMBAT_ICEDAMAGE, 0, COMBAT_NONE, ORIGIN_SPELL); runEvents()
eq(#dealt, 0, "a single-target hit does not echo")

-- illusionist (support): Shared Phantasm marks, Inspiring Illusion aura; party members profit, the illusionist not
local function eqm(a, b, m) eq(math.floor(a * 1000 + 0.5), math.floor(b * 1000 + 0.5), m) end
local hit = {attackerId = 2, party = 1, pos = pos(10, 10), now = 1000}
local mark = {owner = 1, party = 1, untilTime = 5000}
eqm(K.partyMultiplier(hit, nil, {}), 1, "nothing")
eqm(K.partyMultiplier(hit, mark, {}), 1.12, "marked: +12% for a party member")
eqm(K.partyMultiplier({attackerId = 1, party = 1, pos = pos(10, 10), now = 1000}, mark, {}), 1, "not for the illusionist")
eqm(K.partyMultiplier({attackerId = 2, party = 9, pos = pos(10, 10), now = 1000}, mark, {}), 1, "other party")
eqm(K.partyMultiplier({attackerId = 2, party = 1, pos = pos(10, 10), now = 5001}, mark, {}), 1, "mark expired")
eqm(K.partyMultiplier({attackerId = 2, pos = pos(10, 10), now = 1000}, mark, {}), 1, "no party")
local givers = {{id = 1, pos = pos(18, 10)}}
eqm(K.partyMultiplier(hit, nil, givers), 1.08, "aura within 8 sqm")
eqm(K.partyMultiplier(hit, nil, {{id = 1, pos = pos(19, 10)}}), 1, "aura out of range")
eqm(K.partyMultiplier(hit, nil, {{id = 1, pos = pos(10, 10, 6)}}), 1, "aura other floor")
eqm(K.partyMultiplier({attackerId = 1, party = 1, pos = pos(10, 10), now = 1000}, nil, givers), 1, "aura not on the giver")
eqm(K.partyMultiplier(hit, mark, {{id = 1, pos = pos(11, 10)}, {id = 3, pos = pos(11, 10)}}), 1.2, "both, one aura at most")
eqm(K.partyMultiplier({attackerId = 2, party = 1, pos = pos(10, 10), now = 1000, multiClient = true}, mark, givers), 1, "multi-client member gets nothing")
eqm(K.partyMultiplier(hit, {owner = 1, party = 1, untilTime = 5000, multiClient = true}, {{id = 1, pos = pos(11, 10), multiClient = true}}), 1, "multi-client illusionist gives nothing")
-- Shared Phantasm also heals the hitting party member for a share of the hit (the illusionist's own hits: nothing)
eq(K.phantasmLeech(hit, mark, 1000), math.floor(1000 * cfg.phantasm.leech), "leech on a marked enemy")
eq(K.phantasmLeech(hit, nil, 1000), 0, "no mark, no leech")
eq(K.phantasmLeech({attackerId = 1, party = 1, pos = pos(10, 10), now = 1000}, mark, 1000), 0, "not for the illusionist")
eq(K.phantasmLeech({attackerId = 2, party = 9, pos = pos(10, 10), now = 1000}, mark, 1000), 0, "other party")
eq(K.phantasmLeech({attackerId = 2, party = 1, pos = pos(10, 10), now = 5001}, mark, 1000), 0, "mark expired")
eq(K.phantasmLeech({attackerId = 2, party = 1, pos = pos(10, 10), now = 1000, multiClient = true}, mark, 1000), 0, "multi-client")

-- engine glue: the illusionist marks, a party member hits the marked enemy harder
local leader = mkCreature(7, pos(600, 600), "player")
local member = mkCreature(8, pos(601, 601), "player")
local party = {getLeader = function() return leader end, getMembers = function() return {member} end}
leader.getParty = function() return party end; member.getParty = function() return party end
ChaosPassiveCache[7] = {ksSharedPhantasm = 1, ksInspiringIllusion = 1}
ChaosPassiveCache[8] = {}
local m1 = mkCreature(70, pos(603, 600), "monster")
dealt = {}
eq(ev.onHealthChange(m1, member, 1000, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, ORIGIN_MELEE), 1080, "aura only (no mark yet)")
eq(ev.onHealthChange(m1, leader, 1000, COMBAT_DEATHDAMAGE, 0, COMBAT_NONE, ORIGIN_SPELL), 1000, "the illusionist gets nothing")
eq(ev.onHealthChange(m1, member, 1000, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, ORIGIN_MELEE), 1200, "mark + aura")
member.p = pos(620, 600)
eq(ev.onHealthChange(m1, member, 1000, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, ORIGIN_RANGED), 1120, "far away: mark only")
NOW = NOW + cfg.phantasm.duration + 1
eq(ev.onHealthChange(m1, member, 1000, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, ORIGIN_RANGED), 1000, "mark gone")
runEvents()
local heals = {}
for _, d in ipairs(dealt) do if d.type == COMBAT_HEALING then heals[#heals + 1] = d end end
eq(#heals, 1, "one Shared Phantasm heal per tick and member")
eq(heals[1].target, 8, "the party member is healed"); eq(heals[1].attacker, 7, "by the illusionist")
eq(heals[1].amount, math.floor(1200 * cfg.phantasm.leech) + math.floor(1120 * cfg.phantasm.leech), "4% of the marked hits")

-- ---------------------------------------------------------------- per-vocation stats in the generated data
local data = dofile("data/scripts/chaos/passivetree_data.lua")
local expected = {
  [621] = {knight = "ksCleavingArc", paladin = "ksRicochet", sorcerer = "ksArcaneEcho", ironsage = "ksOvergrowth", illusionist = "ksSharedPhantasm",
    juggernaut = "ksImmovable", berserker = "ksCleavingArc", deadeye = "ksHuntersFocus", beastmaster = "ksRicochet"},
  [624] = {knight = "ksBulwark", paladin = "ksDeadeye", sorcerer = "ksOverload", sentinel = "ksThorns", illusionist = "ksInspiringIllusion",
    juggernaut = "ksBulwark", berserker = "ksUndyingRage", deadeye = "ksDeadeye", beastmaster = "ksPackAlpha"},
}
for id, byVoc in pairs(expected) do
  local node = data.nodes[id]
  assert(node and node.v and not node.s, "keystone " .. id .. " has only per-vocation stats")
  for voc, key in pairs(byVoc) do eq(node.v[voc][key], 1, id .. " " .. voc) end
  eq(#node.n, 1, "keystone " .. id .. " ends its path")
end
eq(data.nodes[600].n[3], 619, "Wrath path starts at node 600"); eq(data.nodes[489], nil, "node 489 (drown) left the tree"); local has623 = false; for _, nb in ipairs(data.nodes[622].n) do has623 = has623 or nb == 623 end; eq(has623, true, "Resolve path: 622 leads to 623")

-- passivetree.lua picks the class's variant (the real class table: class keys)
local savedChaos = Chaos
Chaos = nil
dofile("data/scripts/chaos/chaos_constants.lua")
local realClasses = Chaos.classes
Chaos = savedChaos
Chaos = {classes = realClasses, passive = {}, tables = {passiveTree = "chaos_passive_tree"}, storage = {}, load = function(f) return dofile("data/scripts/chaos/" .. f) end,
  select = function() return {{preset = 1, name = "p", nodes = "619,620,621,622,623,624"}} end}
ChaosOpcodes = {}
db = {escapeString = function(s) return "'" .. s .. "'" end, query = function() end}
dofile("data/scripts/chaos/passivetree.lua")
local function voc(id) return {getGuid = function() return 1 end, getVocation = function() return {getId = function() return id end} end} end
local b = ChaosPassiveTree.getBonuses(voc(8))
eq(b.ksImmovable, 1, "juggernaut wrath"); eq(b.ksBulwark, 1, "juggernaut resolve"); eq(b.ksRicochet, nil, "no paladin keystone")
eq(b.ksCleavingArc, nil, "the juggernaut swapped Cleaving Arc")
eq(b.incrementPhysical, 7, "the path notables count for everyone")
b = ChaosPassiveTree.getBonuses(voc(14)); eq(b.ksCleavingArc, 1, "berserker wrath"); eq(b.ksUndyingRage, 1, "berserker resolve")
eq(b.ksBulwark, nil, "the berserker swapped Bulwark")
b = ChaosPassiveTree.getBonuses(voc(4)); eq(b.ksBulwark, 1, "warrior: the knight variant")
b = ChaosPassiveTree.getBonuses(voc(7)); eq(b.ksHuntersFocus, 1, "deadeye"); eq(b.ksDeadeye, 1, "deadeye resolve")
b = ChaosPassiveTree.getBonuses(voc(15)); eq(b.ksRicochet, 1, "beastmaster wrath"); eq(b.ksPackAlpha, 1, "beastmaster resolve")
b = ChaosPassiveTree.getBonuses(voc(3)); eq(b.ksRicochet, 1, "ranger: the paladin variant"); eq(b.ksDeadeye, 1, "ranger")
b = ChaosPassiveTree.getBonuses(voc(5)); eq(b.ksArcaneEcho, 1, "elementalist"); eq(b.ksOverload, 1, "elementalist resolve")
b = ChaosPassiveTree.getBonuses(voc(1)); eq(b.ksArcaneEcho, 1, "mystic: the sorcerer variant")
b = ChaosPassiveTree.getBonuses(voc(10)); eq(b.ksSharedPhantasm, 1, "illusionist"); eq(b.ksInspiringIllusion, 1, "illusionist resolve")
eq(b.ksOvergrowth, nil, "Overgrowth is the Iron Sage's")
b = ChaosPassiveTree.getBonuses(voc(19)); eq(b.ksOvergrowth, 1, "iron sage wrath: Overgrowth")
eq(b.ksThorns, nil, "624 is not the Iron Sage's"); eq(b.ksSharedPhantasm, nil, "no other class's keystone")
b = ChaosPassiveTree.getBonuses(voc(25)); eq(b.ksThorns, 1, "sentinel resolve: Thorns")
eq(b.ksOvergrowth, nil, "621 is not the Sentinel's"); eq(b.ksBulwark, nil, "no other class's keystone")
-- since 2026-10-20 the Thief, Necromancer, Monk and Templar lines have their own pair (class_keystones_test.lua)
b = ChaosPassiveTree.getBonuses(voc(0)); assert(not K.hasKeystone(b), "no vocation: no keystone")
b = ChaosPassiveTree.getBonuses(voc(12)); eq(b.ksShadowTwin, 1, "the Ninja's own Wrath"); eq(b.ksRicochet, nil, "no Ranger keystone")
eq(b.incrementPhysical, 7, "a Ninja gets the shared notables of those paths")

-- ---------------------------------------------------------------- the client tooltips state the server numbers
local nodesFile = "../client/overlay/modules/game_passivetree/treedata/nodes.lua"
local f = io.open(nodesFile)
if f then
  f:close()
  dofile(nodesFile)
  local nodes = getTreeNodes()
  local function pct(x) return tostring(math.floor(x * 100 + 0.5)) .. "%" end
  local function sec(ms) return (ms % 1000 == 0 and tostring(math.floor(ms / 1000)) or tostring(ms / 1000)) .. " s" end
  local want = {
    knight = {[621] = {pct(cfg.cleave.percent), "up to " .. cfg.cleave.maxTargets},
      [624] = {cfg.bulwark.blockChance .. "%", pct(cfg.bulwark.reflectPercent)}},
    paladin = {[621] = {cfg.ricochet.chance .. "%", cfg.ricochet.range .. " sqm", pct(cfg.ricochet.percent),
      "(" .. pct(cfg.ricochet.percent * cfg.ricochet.falloff) .. ")"},
      [624] = {cfg.deadeye.chance .. "%", "+" .. pct(cfg.deadeye.multiplier - 1)}},
    sorcerer = {[621] = {cfg.echo.chance .. "%", sec(cfg.echo.delay), pct(cfg.echo.percent), "Cooldown " .. sec(cfg.echo.cooldown),
      cfg.echo.minTargets .. " or more"}, [624] = {sec(cfg.overload.window), "+" .. pct(cfg.overload.bonus)}},
    ironsage = {[621] = {pct(cfg.overgrowth.percent), sec(cfg.overgrowth.pulses * cfg.overgrowth.interval), cfg.overgrowth.pulses .. " pulses"}},
    sentinel = {[624] = {pct(cfg.thorns.percent), cfg.thorns.perMagicLevel .. " x your magic level"}},
    illusionist = {[621] = {sec(cfg.phantasm.duration), "+" .. pct(cfg.phantasm.bonus), "heal for " .. pct(cfg.phantasm.leech)},
      [624] = {cfg.inspire.range .. " sqm", "+" .. pct(cfg.inspire.bonus)}},
  }
  for vocName, byNode in pairs(want) do
    for id, needles in pairs(byNode) do
      local text = table.concat(nodes[id][vocName].stats, " ")
      for _, needle in ipairs(needles) do
        assert(text:find(needle, 1, true), vocName .. " node " .. id .. " tooltip lacks '" .. needle .. "': " .. text)
      end
    end
  end
end
-- ---------------------------------------------------------------- the per-ascended keystones (numbers: class_tree.lua)
local near = function(a, b, m) assert(math.abs(a - b) < 1e-9, (m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b)) end
near(K.immovableFactor(900, 1000), 0.92, "Immovable"); near(K.immovableFactor(400, 1000), 0.84, "Immovable below half")
eq(K.undyingHeal(-1000, 900, 1000), 40, "Undying Rage"); eq(K.undyingHeal(1000, 300, 1000), 80, "Undying Rage low")
local fs = {}
near(K.focusStep(fs, 5, 0), 1, "first hit"); near(K.focusStep(fs, 5, 100), 1.04); near(K.focusStep(fs, 5, 200), 1.08)
for t = 3, 9 do K.focusStep(fs, 5, t * 100) end
near(K.focusStep(fs, 5, 1000), 1.20, "capped at +20%")
near(K.focusStep(fs, 6, 1100), 1, "another target starts again")
K.focusStep(fs, 6, 1200); near(K.focusStep(fs, 6, 9000), 1, "6 s without a hit starts again")
print("passive keystones: all asserts passed")
