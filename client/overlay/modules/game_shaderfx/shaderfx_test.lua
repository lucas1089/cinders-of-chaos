-- luajit shaderfx_test.lua && lua5.3 shaderfx_test.lua
-- Pure helpers of game_shaderfx: orb fill and slosh, the frame shine rule, greyscale of locked items, and the shader
-- files the module registers.
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'shaderfxlogic.lua')
local L = ShaderFxLogic
local fails, checks = 0, 0
local function eq(a, b, what)
  checks = checks + 1
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

-- fill
eq(L.fill(50, 100), 0.5, 'half') eq(L.fill(100, 100), 1, 'full') eq(L.fill(150, 100), 1, 'over max')
eq(L.fill(0, 100), 0, 'empty') eq(L.fill(10, 0), 0, 'no max') eq(L.fill(nil, nil), 0, 'nil') eq(L.fill(-5, 10), 0, 'negative')

-- slosh: a change raises it (bigger change, more), rest decays it to 0
eq(L.sloshAfter(0.5, 0.5, 0), 0, 'no change, no slosh')
local small, big = L.sloshAfter(0.5, 0.48, 0), L.sloshAfter(0.9, 0.2, 0)
eq(small > 0 and small < big, true, 'a big hit sloshes more') eq(big, 1, 'capped at 1')
eq(L.sloshAfter(0.5, 0.49, 0.9), 0.9, 'a change never calms it')
eq(L.decay(1, 0), 1, 'no time, no decay')
eq(L.decay(1, 1000) < 0.2, true, 'one second calms most of it')
eq(L.decay(0.02, 1000), 0, 'too small to see: 0')
local s, ticks = 1, 0
while s > 0 and ticks < 1000 do s = L.decay(s, 50) ticks = ticks + 1 end
eq(ticks < 60, true, 'calm within 3 s of 50 ms ticks')

-- orb params are clamped
local a, b, c, d = L.orbParams(1.5, -1, 0.3)
eq(a, 1, 'fill clamped') eq(b, 0, 'slosh clamped') eq(c, 0.3, 'phase') eq(d, 1, 'foam on')

-- phase: stable, in 0..1, differs between keys
eq(L.phaseOf('slot1'), L.phaseOf('slot1'), 'stable')
eq(L.phaseOf('slot1') ~= L.phaseOf('slot2'), true, 'different keys differ')
eq(L.phaseOf(nil) >= 0 and L.phaseOf(nil) < 1, true, 'in range')

-- shine: legendary (5) and up and uniques, only with the option on
eq(L.shineParams(4, false, true, 'k'), nil, 'epic: no shine')
eq(L.shineParams(5, false, true, 'k') ~= nil, true, 'legendary shines')
eq(L.shineParams(15, false, true, 'k') ~= nil, true, 'transcendent shines')
eq(L.shineParams(1, true, true, 'k') ~= nil, true, 'a unique shines whatever its rarity')
eq(L.shineParams(9, false, false, 'k'), nil, 'option off: no shine')
local p1, p2, p3, p4 = L.shineParams(5, false, true, 'k')
eq(p1 >= 0 and p1 < L.SHINE_PERIOD, true, 'phase within a period') eq(p2, L.SHINE_PERIOD, 'period')
eq(p3, L.SHINE_STRENGTH, 'strength') eq(p4, L.SHINE_WIDTH, 'width')
eq(select(3, L.shineParams(2, true, true, 'k')), L.UNIQUE_SHINE_STRENGTH, 'uniques shine brighter')

-- greyscale of locked items
local function item(attrs) return { getCustomAttribute = function(self, k) return attrs[k] or 0 end } end
eq(L.isLocked(item({ [3] = 1 })), true, 'locked') eq(L.isLocked(item({})), false, 'not locked')
eq(L.isLocked(nil), false, 'no item') eq(L.isLocked({}), false, 'an item without attributes')
eq(L.greyAction(true, false), 'grey', 'grey a locked item') eq(L.greyAction(true, true), nil, 'already grey')
eq(L.greyAction(false, true), 'clear', 'unlocked: take our grey back') eq(L.greyAction(false, false), nil, 'leave other shaders')

-- a slot whose setItemShader re-enters (the engine's onItemChange -> game_itemrarity -> onSlotItem): one shader call
-- each way, no endless recursion (live test 2026-10-14: "stack overflow" opening a backpack with the Loot Bag)
do
  local calls, depth, maxDepth = 0, 0, 0
  local slot = {}
  local locked = true
  function slot:setItemShader(name)
    calls = calls + 1
    depth = depth + 1
    if depth > maxDepth then maxDepth = depth end
    if depth < 50 then L.applyItemGrey(self, locked) end
    depth = depth - 1
  end
  eq(L.applyItemGrey(slot, true), 'grey', 're-entrant slot: greyed')
  eq(calls, 1, 're-entrant slot: one shader call to grey')
  eq(maxDepth < 50, true, 're-entrant slot: no recursion')
  locked = false
  calls = 0
  eq(L.applyItemGrey(slot, false), 'clear', 're-entrant slot: cleared')
  eq(calls, 1, 're-entrant slot: one shader call to clear')
  eq(slot.sfxGrey, nil, 're-entrant slot: mark gone')
end

-- the registered shader files exist (client/overlay/data/shaders)
local shaders = dir .. '../../data/shaders/'
for _, s in ipairs(L.UI_SHADERS) do
  for _, f in ipairs({ s.vertex, s.fragment }) do
    local fh = io.open(shaders .. f:match('[^/]+$') .. '.frag', 'r')
    eq(fh ~= nil, true, s.name .. ': ' .. f .. '.frag exists')
    if fh then fh:close() end
  end
end

if fails > 0 then
  print(fails .. ' failure(s)')
  os.exit(1)
end
print('shaderfx_test: ' .. checks .. ' checks OK')
