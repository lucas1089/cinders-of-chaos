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
print('bossanimatelogic_test: ok')
