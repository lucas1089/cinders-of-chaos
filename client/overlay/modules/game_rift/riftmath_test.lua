-- luajit riftmath_test.lua && lua5.3 riftmath_test.lua
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'riftmath.lua')
local fails = 0
local function eq(a, b, what)
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end
eq(RiftMath.clock(75), '1:15', 'clock')
eq(RiftMath.modLine({name = 'Teeming', text = '+30% monster packs'}), 'Teeming: +30% monster packs', 'mod line')
eq(RiftMath.modLine({text = 'x'}), 'x', 'mod line without name')
eq(RiftMath.modLine(nil), '', 'mod line nil')
eq(RiftMath.clock(600), '10:00', 'clock ten minutes')
eq(RiftMath.clock(-3), '0:00', 'clock negative')
eq(RiftMath.clock(nil), '0:00', 'clock nil')
eq(RiftMath.clock(59.9), '0:59', 'clock rounds down')
eq(RiftMath.left(100, 10, 15), 95, 'left counts down')
eq(RiftMath.left(3, 10, 20), 0, 'left never negative')
eq(RiftMath.left(30, 10, 5), 30, 'clock skew ignored')
eq(RiftMath.bossPercent(15, 30, 'waiting'), 50, 'boss percent')
eq(RiftMath.bossPercent(40, 30, 'waiting'), 100, 'boss percent capped')
eq(RiftMath.bossPercent(0, 30, 'alive'), 100, 'boss alive')
eq(RiftMath.bossPercent(0, 0, 'waiting'), 100, 'no threshold')
eq(RiftMath.bossLine({ boss = 'waiting', killed = 7, bossAt = 8 }), 'Guardian in 1 kill', 'boss line singular')
eq(RiftMath.bossLine({ boss = 'waiting', killed = 2, bossAt = 8 }), 'Guardian in 6 kills', 'boss line')
eq(RiftMath.bossLine({ boss = 'alive', bossName = 'Lady bug' }), 'The guardian Lady bug is here!', 'boss alive line')
eq(RiftMath.bossLine({ boss = 'dead' }), 'The guardian is slain.', 'boss dead line')
eq(RiftMath.bonusLine({ quantity = 20, rarity = 0, experience = 10 }), '+20% quantity, +10% experience', 'bonus line')
eq(RiftMath.bonusLine(nil), '', 'bonus nil')
eq(RiftMath.clockColor(500), '#f4d27a', 'colour normal')
eq(RiftMath.clockColor(45), '#ff9a30', 'colour last minute')
eq(RiftMath.clockColor(10), '#ff4030', 'colour last seconds')
if fails > 0 then os.exit(1) end
print('rift hud tests OK')
