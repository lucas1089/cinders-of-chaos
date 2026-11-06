-- run from the repo root: luajit client/overlay/modules/game_bossanimate/bossanimatelogic_test.lua
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
print('bossanimatelogic_test: ok')
