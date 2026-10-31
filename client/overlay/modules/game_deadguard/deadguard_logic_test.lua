-- luajit deadguard_logic_test.lua && lua5.3 deadguard_logic_test.lua (CI runs every client/overlay/modules/*/*_test.lua)
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'deadguard_logic.lua')
local L = DeadGuardLogic
local fails, checks = 0, 0
local function eq(a, b, what)
  checks = checks + 1
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

local function mon(over)
  local t = { isPlayer = false, isLocalPlayer = false, healthPercent = 0, removed = false, onMap = true }
  for k, v in pairs(over or {}) do t[k] = v end
  return t
end

eq(L.GRACE_MS, 3000, 'grace is 3 seconds')
eq(L.decide(mon(), 0), 'wait', 'just died')
eq(L.decide(mon(), 2999), 'wait', 'inside the grace')
eq(L.decide(mon(), 3000), 'remove', 'at the grace')
eq(L.decide(mon(), 60000), 'remove', 'long after')
eq(L.decide(mon({ isPlayer = true }), 60000), 'skip', 'a player is never removed')
eq(L.decide(mon({ isLocalPlayer = true }), 60000), 'skip', 'the local player is never removed')
eq(L.decide(mon({ isPlayer = true, healthPercent = 0 }), 0), 'skip', 'a player at 0 percent')
eq(L.decide(mon({ healthPercent = 1 }), 60000), 'skip', 'alive')
eq(L.decide(mon({ healthPercent = 100 }), 60000), 'skip', 'full health')
local unk = mon(); unk.healthPercent = nil
eq(L.decide(unk, 60000), 'skip', 'unknown health')
eq(L.decide(mon({ removed = true }), 60000), 'skip', 'the engine removed it')
eq(L.decide(mon({ onMap = false }), 60000), 'skip', 'not on a tile')
eq(L.decide(nil, 60000), 'skip', 'no info')
eq(L.decide(mon(), nil), 'wait', 'no age counts as zero')

local s = L.newState()
eq(L.wantsWatch(s, 7, false, false, 0), true, 'a monster at 0')
eq(L.wantsWatch(s, 7, true, false, 0), false, 'a player')
eq(L.wantsWatch(s, 7, false, true, 0), false, 'the local player')
eq(L.wantsWatch(s, 7, false, false, 50), false, 'alive')
eq(L.wantsWatch(s, 7, false, false, nil), false, 'no percent')
eq(L.wantsWatch(s, nil, false, false, 0), false, 'no id')
s.pending[7] = true
eq(L.wantsWatch(s, 7, false, false, 0), false, 'already watched')
L.forget(s, 7)
eq(L.wantsWatch(s, 7, false, false, 0), true, 'watched again after forget')

eq(L.shouldLog(s, 42), true, 'first report of an id')
eq(L.shouldLog(s, 42), false, 'once per id')
eq(L.shouldLog(s, 43), true, 'another id logs')
L.reset(s)
eq(L.shouldLog(s, 42), true, 'after reset logs again')

-- the sweep
local A, B, C = {}, {}, {}
local function ent(id, obj, hp, over)
  local t = { id = id, obj = obj, isPlayer = false, isLocalPlayer = false, healthPercent = hp, removed = false, onMap = true }
  for k, v in pairs(over or {}) do t[k] = v end
  return t
end
local function canonOf(map) return function(id) return map[id] end end
local st = L.newState()
-- a duplicate: the map knows A for id 5, B is the leftover
local r = L.sweep(st, { ent(5, A, 40), ent(5, B, 40), ent(6, C, 100) }, canonOf({ [5] = A, [6] = C }), 0)
eq(#r, 1, 'one leftover of a duplicate')
eq(r[1].entry.obj, B, 'the non canon object goes')
eq(r[1].why, 'duplicate', 'reason duplicate')
-- the wrappers are not stable: the canon object is none of the two: nothing is touched
r = L.sweep(st, { ent(5, A, 40), ent(5, B, 40) }, canonOf({ [5] = C }), 0)
eq(#r, 0, 'no canon among the objects: nothing removed')
-- both are the canon (equal wrappers): nothing
r = L.sweep(st, { ent(5, A, 40), ent(5, A, 40) }, canonOf({ [5] = A }), 0)
eq(#r, 0, 'two equal wrappers: nothing removed')
-- no canon known
r = L.sweep(st, { ent(5, A, 40), ent(5, B, 40) }, canonOf({}), 0)
eq(#r, 0, 'the map does not know the id: nothing removed')
-- a single object is never a duplicate
local st0 = L.newState()
r = L.sweep(st0, { ent(7, A, 80) }, canonOf({ [7] = B }), 0)
eq(#r, 0, 'a single object is left alone when canon differs and wrappers are unproven')
r = L.sweep(st0, { ent(7, A, 80) }, canonOf({ [7] = B }), 5000)
eq(#r, 0, 'still unproven: left alone')
-- stale (O352): a lone object the map knows as another object, once wrappers are proven stable
st0 = L.newState()
r = L.sweep(st0, { ent(7, A, 80), ent(9, C, 100) }, canonOf({ [7] = B, [9] = C }), 0)
eq(#r, 0, 'stale: wait for the grace')
eq(st0.stable, true, 'C is its canon: wrappers proven')
r = L.sweep(st0, { ent(7, A, 80), ent(9, C, 100) }, canonOf({ [7] = B, [9] = C }), 2999)
eq(#r, 0, 'stale: inside the grace')
r = L.sweep(st0, { ent(7, A, 80), ent(9, C, 100) }, canonOf({ [7] = B, [9] = C }), 3000)
eq(#r, 1, 'stale: removed after the grace')
eq(r[1].entry.obj, A, 'stale: the leftover goes')
eq(r[1].why, 'stale', 'reason stale')
-- stale: the map forgot the id, no proof needed
st0 = L.newState()
L.sweep(st0, { ent(11, A, 60) }, canonOf({}), 0)
r = L.sweep(st0, { ent(11, A, 60) }, canonOf({}), 3000)
eq(#r, 1, 'forgotten id: removed after the grace')
eq(r[1].why, 'stale', 'forgotten id: reason stale')
-- the map knows it again: the clock resets
st0 = L.newState()
L.sweep(st0, { ent(11, A, 60) }, canonOf({}), 0)
L.sweep(st0, { ent(11, A, 60) }, canonOf({ [11] = A }), 1000)
r = L.sweep(st0, { ent(11, A, 60) }, canonOf({}), 3500)
eq(#r, 0, 'known again in between: the clock restarts')
-- stale and zero on one object: listed once
st0 = L.newState()
L.sweep(st0, { ent(12, A, 0) }, canonOf({}), 0)
r = L.sweep(st0, { ent(12, A, 0) }, canonOf({}), 3000)
eq(#r, 1, 'stale and zero: one entry')
-- zero health: only after the grace, counted from the first sweep that saw it
st = L.newState()
r = L.sweep(st, { ent(8, A, 0) }, canonOf({ [8] = A }), 1000)
eq(#r, 0, 'first sight at 0: wait')
r = L.sweep(st, { ent(8, A, 0) }, canonOf({ [8] = A }), 3999)
eq(#r, 0, 'inside the grace: wait')
r = L.sweep(st, { ent(8, A, 0) }, canonOf({ [8] = A }), 4000)
eq(#r, 1, 'after the grace: remove')
eq(r[1].why, 'zero', 'reason zero')
-- healed or gone resets the clock
st = L.newState()
L.sweep(st, { ent(8, A, 0) }, canonOf({ [8] = A }), 1000)
L.sweep(st, {}, canonOf({}), 2000)
r = L.sweep(st, { ent(8, A, 0) }, canonOf({ [8] = A }), 4500)
eq(#r, 0, 'the clock restarted after it left the list')
-- players, removed and off map entries are never swept
st = L.newState()
L.sweep(st, { ent(9, A, 0, { isPlayer = true }), ent(10, B, 0, { removed = true }), ent(11, C, 0, { onMap = false }) }, canonOf({}), 0)
r = L.sweep(st, { ent(9, A, 0, { isPlayer = true }), ent(10, B, 0, { removed = true }), ent(11, C, 0, { onMap = false }) }, canonOf({}), 9000)
eq(#r, 0, 'players, removed and off map creatures are skipped')
-- a duplicate at 0 percent is reported once
st = L.newState()
L.sweep(st, { ent(12, A, 0), ent(12, B, 0) }, canonOf({ [12] = A }), 0)
r = L.sweep(st, { ent(12, A, 0), ent(12, B, 0) }, canonOf({ [12] = A }), 5000)
local n = 0
for _, v in ipairs(r) do if v.entry.obj == B then n = n + 1 end end
eq(n, 1, 'a leftover at 0 percent is listed once')
eq(L.SWEEP_MS, 1000, 'sweep every second')

-- the own character off its tile
st = L.newState()
eq(L.selfOffTile(st, { onMap = true, walking = false, listed = false }, 0), nil, 'off the tile: wait')
eq(L.selfOffTile(st, { onMap = true, walking = false, listed = false }, 1499), nil, 'still inside the time')
eq(L.selfOffTile(st, { onMap = true, walking = false, listed = false }, 1500), 'readd', 'after the time: put it back')
eq(L.selfOffTile(st, { onMap = true, walking = false, listed = false }, 1600), nil, 'the clock restarts after a re-add')
st = L.newState()
L.selfOffTile(st, { onMap = true, walking = false, listed = false }, 0)
eq(L.selfOffTile(st, { onMap = true, walking = true, listed = false }, 1000), nil, 'walking: the engine draws it, reset')
eq(L.selfOffTile(st, { onMap = true, walking = false, listed = false }, 2000), nil, 'the clock started again')
eq(L.selfOffTile(st, { onMap = true, walking = false, listed = true }, 9000), nil, 'listed: fine')
eq(L.selfOffTile(st, { onMap = true, walking = false, listed = nil }, 9000), nil, 'unknown: nothing')
eq(L.selfOffTile(st, { onMap = false, walking = false, listed = false }, 9000), nil, 'not on a map tile: nothing')
eq(L.selfOffTile(st, nil, 9000), nil, 'no info')

if fails > 0 then print(fails .. ' of ' .. checks .. ' checks FAILED'); os.exit(1) end
print('deadguard_logic_test ok (' .. checks .. ' checks)')
