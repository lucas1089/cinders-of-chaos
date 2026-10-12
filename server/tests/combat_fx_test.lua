-- Run from the server/ folder: lua5.3 tests/combat_fx_test.lua (mock engine API; CI runs it)
local n = 0
setmetatable(_G, {__index = function(t, k)
  if type(k) == "string" and k:match("^[A-Z_0-9]+$") then n = n + 1; rawset(t, k, n); return n end
end})
COMBAT_NONE, COMBAT_PHYSICALDAMAGE, COMBAT_FIREDAMAGE, COMBAT_ICEDAMAGE, COMBAT_HEALING = 0, 1, 8, 512, 128
local clock = 1000
os.mtime = function() return clock end
local registry, callbacks, effects, packets = {}, {}, {}, {}
function CreatureEvent(name) local o = {}; function o:register() registry[name] = o end; return o end
EventCallback = setmetatable({}, {__newindex = function(t, k, v) rawset(t, k, v) end})
function EventCallback:register(i) callbacks[#callbacks + 1] = {self.onTargetCombat, i} end
local function pos(x, y) return {x = x, y = y, z = 7, sendMagicEffect = function(p, id) effects[#effects + 1] = {x = p.x, y = p.y, id = id} end} end
Game = {getSpectators = function() return {{}} end}
function NetworkMessage()
  local m = {bytes = {}}
  function m:addByte(b) self.bytes[#self.bytes + 1] = b end
  function m:addPosition(p) self.pos = p end
  function m:addString(s) self.text = s end
  function m:sendToPlayer() packets[#packets + 1] = self end
  return m
end
local function creature(id, x, y, player, st)
  return {getId = function() return id end, getPosition = function() return pos(x, y) end,
    isPlayer = function() return player end, getStorageValue = function(_, k) return (st or {})[k] or -1 end}
end
dofile("data/lib/chaos_fx.lua")
dofile("data/scripts/chaos/combat_fx.lua")
local fx = ChaosCombatFx
local ev = registry["ChaosCombatFx"]
assert(ev and ev.onHealthChange, "event registered")
local function eq(a, b, m) if a ~= b then error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2) end end
local function reset() effects, packets = {}, {}; fx.resetThrottle(); clock = clock + 10000 end

-- the event returns the damage unchanged
local player = creature(1, 100, 100, true)
local a, b, c, d = ev.onHealthChange(creature(2, 101, 100, false), player, -50, COMBAT_PHYSICALDAMAGE, -20, COMBAT_FIREDAMAGE, ORIGIN_MELEE, false)
eq(a, -50); eq(b, COMBAT_PHYSICALDAMAGE); eq(c, -20); eq(d, COMBAT_FIREDAMAGE)
eq(#effects, 1, "fire weapon hit: one sprite"); eq(effects[1].id, ChaosFx.imbue_fire, "fire sprite")
eq(#packets, 0, "no extra number: the engine sends the element number")

-- spells do not get weapon element sprites; heals get nothing
reset()
ev.onHealthChange(creature(2, 101, 100, false), player, -50, COMBAT_FIREDAMAGE, -20, COMBAT_ICEDAMAGE, ORIGIN_SPELL, false)
eq(#effects, 0, "spell: no element sprite")
ev.onHealthChange(creature(2, 101, 100, false), player, 50, COMBAT_HEALING, 0, COMBAT_NONE, ORIGIN_SPELL, true)
eq(#effects, 0, "heal: nothing")

-- distance and wand hits with a secondary element
reset()
ev.onHealthChange(creature(2, 101, 100, false), player, -50, COMBAT_PHYSICALDAMAGE, -20, COMBAT_ICEDAMAGE, ORIGIN_RANGED, false)
ev.onHealthChange(creature(3, 102, 100, false), player, -50, COMBAT_ENERGYDAMAGE, -20, COMBAT_ICEDAMAGE, ORIGIN_WAND, false)
eq(#effects, 2); eq(effects[1].id, ChaosFx.imbue_ice); eq(effects[2].id, ChaosFx.imbue_ice)

-- rarity element before the rarity script added the secondary damage
reset()
local rare = creature(5, 100, 100, true, {[977554] = 12})
ev.onHealthChange(creature(2, 101, 100, false), rare, -50, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, ORIGIN_MELEE, false)
eq(#effects, 1, "rarity fire"); eq(effects[1].id, ChaosFx.imbue_fire)

-- crit: burst + "CRIT!" label; nil (unpatched engine) shows nothing
reset()
ev.onHealthChange(creature(2, 101, 100, false), player, -50, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, ORIGIN_MELEE, nil)
eq(#effects, 0, "no crit without the engine patch")
ev.onHealthChange(creature(2, 101, 100, false), player, -50, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, ORIGIN_MELEE, true)
eq(#effects, 1); eq(effects[1].id, ChaosFx.crit_burst); eq(#packets, 1); eq(packets[1].text, "CRIT!")
eq(packets[1].bytes[1], 0x84, "animated text opcode")

-- throttle: an area crit on 20 monsters shows perSource bursts and one label
reset()
for i = 1, 20 do
  ev.onHealthChange(creature(10 + i, 100 + i, 100, false), player, -50, COMBAT_FIREDAMAGE, 0, COMBAT_NONE, ORIGIN_SPELL, true)
end
eq(#effects, fx.config.perSource, "throttled bursts"); eq(#packets, 1, "one label")
clock = clock + fx.config.windowMs
ev.onHealthChange(creature(40, 140, 100, false), player, -50, COMBAT_FIREDAMAGE, 0, COMBAT_NONE, ORIGIN_SPELL, true)
eq(#effects, fx.config.perSource + 1, "window reopens")
-- same tile twice in a row: once
reset()
fx.element(pos(5, 5), COMBAT_FIREDAMAGE, -10, 1); fx.element(pos(5, 5), COMBAT_FIREDAMAGE, -10, 2)
eq(#effects, 1, "one per tile")

-- dodge / reflect API and the on/off switches
reset()
local mon = creature(7, 50, 50, false)
assert(fx.dodge(mon)); eq(effects[1].id, ChaosFx.dodge_whoosh); eq(packets[1].text, "DODGE")
assert(fx.reflect(mon)); eq(effects[2].id, ChaosFx.reflect_aegis); eq(#packets, 1, "reflect label off by default")
reset()
fx.config.dodge = false
assert(not fx.dodge(mon)); eq(#effects, 0, "dodge off")
fx.config.dodge = true
fx.config.enabled = false
assert(not fx.crit(pos(1, 1), 1)); assert(not fx.element(pos(1, 1), COMBAT_FIREDAMAGE, -1, 1))
fx.config.enabled = true
assert(not fx.dodge(nil), "nil creature is fine")

-- target registration callback adds the event for player attackers only
local registered = {}
local target = {registerEvent = function(_, name) registered[#registered + 1] = name end}
eq(callbacks[1][1](player, target), RETURNVALUE_NOERROR)
eq(registered[1], "ChaosCombatFx")
callbacks[1][1](creature(9, 1, 1, false), target)
eq(#registered, 1, "monster attackers do not register")

-- label colours: a palette byte passes through, "#rrggbb" maps to r*36 + g*6 + b (51 per step), anything else white
eq(fx.paletteByte(154), 154, "byte kept"); eq(fx.paletteByte(0), 0); eq(fx.paletteByte(255), 255)
eq(fx.paletteByte("#ff6633"), 193, "ember"); eq(fx.paletteByte("#66ccff"), 101, "frost")
eq(fx.paletteByte("#ffb347"), 205, "rounds to nearest step"); eq(fx.paletteByte("#FFFFFF"), 215, "upper case hex")
eq(fx.paletteByte("#000000"), 0, "black")
for _, bad in ipairs({256, -1, 1.5, "ff6633", "#ff663", "orange", true}) do
  eq(fx.paletteByte(bad), fx.defaultColor, "fallback for " .. tostring(bad))
end
eq(fx.paletteByte(nil), fx.defaultColor, "fallback for nil")
reset()
assert(fx.label(pos(5, 5), "Death Blast", "#ff6633"))
eq(#packets, 1); eq(packets[1].bytes[1], 0x84, "animated text opcode")
eq(packets[1].bytes[2], 193, "hex sent as its palette byte"); eq(packets[1].text, "Death Blast")
reset()
assert(fx.label(pos(5, 5), "x", 154)); eq(packets[1].bytes[2], 154, "byte sent as is")
reset()
assert(fx.label(pos(5, 5), "x")); eq(packets[1].bytes[2], fx.defaultColor, "no colour: white")
print("combat_fx_test: ok")
