-- run from the repo root: luajit client/overlay/modules/game_bossanimate/bossanimatelogic_test.lua
dofile('client/overlay/modules/game_bossanimate/idle_walk_looks.lua')
dofile('client/overlay/modules/game_bossanimate/bossanimatelogic.lua')
local L = BossAnimateLogic
local set = {}
local function thing(id)
  return { id = id, setAnimateAlways = function(self, v) set[self.id] = v end }
end
local types = { [1534] = thing(1534), [7] = { id = 7 } } -- 7: an engine without patch 0189 (no setter)
local n = L.apply(function(id) return types[id] end, { 1534, 7, 99 })
assert(n == 1, 'one look set')
assert(set[1534] == true, 'Skaldra animates')
assert(set[7] == nil, 'no setter: skipped')
assert(L.apply(function() return nil end) == 0, 'no types: nothing')
assert(L.apply(function() return 5 end) == 0, 'a number: skipped')
local found = false
for _, id in ipairs(L.LOOKS) do if id == 1534 then found = true end end
assert(found, 'Skaldra on the list')
-- shifts: Gravewarden Ulthar's look onto its tile
local disp = {}
local function shiftable(id, refuse)
  return { id = id, setDisplacement = function(self, p) if refuse then return false end disp[self.id] = p return true end }
end
local st = { [2127] = shiftable(2127), [8] = shiftable(8, true), [9] = { id = 9 } }
assert(L.shift(function(id) return st[id] end, { [2127] = { -28, -28 }, [8] = { -1, -1 }, [9] = { 1, 1 }, [77] = { 2, 2 } }) == 1,
  'one shift set: refused, no setter and missing skipped')
assert(disp[2127].x == -28 and disp[2127].y == -28, 'the shift as a point')
assert(L.SHIFTS[2127] and L.SHIFTS[2127][1] < 0 and L.SHIFTS[2127][2] < 0, 'Ulthar moves down and right')
assert(L.shift(function() return 'x' end) == 0, 'a string: skipped')
-- walk in place (O534): the generated list, animateAlways on each look, walkInPlace where the engine has it
assert(type(IdleWalkLooks) == 'table' and #IdleWalkLooks > 100, 'the generated list is loaded')
assert(L.WALK == IdleWalkLooks, 'the module reads it')
for i = 2, #IdleWalkLooks do assert(IdleWalkLooks[i] > IdleWalkLooks[i - 1], 'sorted, no look twice') end
local seen = {}
for _, id in ipairs(IdleWalkLooks) do
  assert(math.type == nil or math.type(id) == 'integer' or id == math.floor(id), 'integers')
  seen[id] = true
end
assert(not seen[1534], 'the boss look keeps its own list')
for _, id in ipairs({ 128, 129, 136, 268 }) do assert(not seen[id], 'player outfit look ' .. id .. ' is not on the list') end
local always, inplace = {}, {}
local function walker(id, noPatch)
  local t = { id = id, setAnimateAlways = function(self, v) always[self.id] = v end }
  if not noPatch then t.setWalkInPlace = function(self, v) inplace[self.id] = v end end
  return t
end
local wt = { [2] = walker(2), [3] = walker(3, true), [4] = { id = 4 } }
assert(L.applyWalk(function(id) return wt[id] end, { 2, 3, 4, 99 }) == 2, 'two looks set: no setter and missing skipped')
assert(always[2] == true and always[3] == true and always[4] == nil, 'animateAlways set')
assert(inplace[2] == true and inplace[3] == nil, 'walkInPlace only where the engine has it (base 0195)')
local refuse = { id = 5, setAnimateAlways = function() error('no') end, setWalkInPlace = function() inplace[5] = true end }
assert(L.applyWalk(function() return refuse end, { 5 }) == 0 and inplace[5] == nil, 'a failing setter counts nothing')
assert(L.applyWalk(function() return nil end) == 0, 'no types: nothing')
assert(L.applyWalk(function() return 'x' end) == 0, 'a string: skipped')
-- the whole list on a fake engine
local count = 0
local all = L.applyWalk(function(id) count = count + 1 return walker(id) end)
assert(all == #IdleWalkLooks and count == #IdleWalkLooks, 'every listed look is set')
print('bossanimatelogic_test: ok')
