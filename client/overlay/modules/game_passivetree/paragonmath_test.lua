-- luajit paragonmath_test.lua && lua5.3 paragonmath_test.lua
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'paragonmath.lua')
local fails = 0
local function eq(a, b, what)
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end
local M = ParagonMath
local damage = {key = 'damage', name = 'Damage', perPoint = 0.5, maxPoints = 40, points = 38}
local reduction = {key = 'reduction', name = 'Damage Reduction', perPoint = 0.25, maxPoints = 32, points = 0}
local state = {unlocked = true, total = 50, spent = 38, free = 12,
  categories = {{key = 'offense', stats = {damage}}, {key = 'defense', stats = {reduction}}}}
local pending = {}
eq(M.free(state, pending), 12, 'free')
eq(M.add(state, pending, damage, 5), 2, 'add stops at the stat max')
eq(M.canAdd(state, pending, damage), false, 'damage maxed')
eq(M.add(state, pending, reduction, 100), 10, 'add stops at the free points')
eq(M.free(state, pending), 0, 'no free left')
eq(M.canAdd(state, pending, reduction), false, 'nothing left')
eq(M.remove(pending, reduction, 3), 3, 'remove pending')
eq(M.remove(pending, damage, 5), 2, 'remove only what is pending')
eq(pending.damage, nil, 'emptied')
eq(M.canRemove(pending, damage), false, 'applied points stay')
local a = M.alloc(state, pending)
eq(a.reduction, 7, 'absolute allocation'); eq(a.damage, nil, 'unchanged stats left out')
eq(M.fmt(0.25), '0.25', 'fmt 0.25'); eq(M.fmt(1.5), '1.5', 'fmt 1.5'); eq(M.fmt(20), '20', 'fmt 20'); eq(M.fmt(0), '0', 'fmt 0')
eq(M.valueText(damage, 38), '+19% / 20%', 'value text')
eq(M.valueText(reduction, 7), '+1.75% / 8%', 'value text reduction')
eq(M.bonusLines(state)[1], '+19% Damage (Paragon).', 'bonus line'); eq(#M.bonusLines(state), 1, 'only allocated stats')
local locked = {unlocked = false, free = 0, categories = {}}
eq(M.canAdd(locked, {}, reduction), false, 'locked')
eq(M.add(nil, {}, reduction, 1), 0, 'no state')
if fails > 0 then os.exit(1) end
print('paragon math tests OK')
