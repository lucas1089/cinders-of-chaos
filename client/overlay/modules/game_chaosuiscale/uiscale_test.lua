-- luajit uiscale_test.lua && lua5.3 uiscale_test.lua (from anywhere; CI runs it from the repo root)
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'uiscale_logic.lua')
local L = UiScaleLogic
local fails, checks = 0, 0
local function eq(a, b, what)
  checks = checks + 1
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

-- steps: whole numbers only (bitmap fonts stay sharp), ascending, the first is 100
eq(L.STEPS[1], 100, 'first step is 100')
for i, p in ipairs(L.STEPS) do
  eq(p % 100, 0, 'step ' .. i .. ' is a whole multiple')
  if i > 1 then eq(p > L.STEPS[i - 1], true, 'step ' .. i .. ' ascending') end
end

-- saved value
eq(L.parseSaved(nil), 1, 'nil -> default')
eq(L.parseSaved('junk'), 1, 'junk -> default')
eq(L.parseSaved(0 / 0), 1, 'nan -> default')
eq(L.parseSaved(math.huge), 1, 'inf -> default')
eq(L.parseSaved(true), 1, 'boolean -> default')
eq(L.parseSaved({}), 1, 'table -> default')
eq(L.parseSaved(1), 1, 'index 1')
eq(L.parseSaved(2), 2, 'index 2')
eq(L.parseSaved(3), 3, 'index 3')
eq(L.parseSaved(2.4), 2, 'index rounds')
eq(L.parseSaved(0), 1, 'index below -> 1')
eq(L.parseSaved(-5), 1, 'negative -> 1')
eq(L.parseSaved(4), 3, 'index above -> last')
eq(L.parseSaved(100), 1, 'percent 100')
eq(L.parseSaved(200), 2, 'percent 200')
eq(L.parseSaved(300), 3, 'percent 300')
eq(L.parseSaved(150), 1, 'percent 150 is nearest the lower on a tie')
eq(L.parseSaved(160), 2, 'percent 160 -> 200')
eq(L.parseSaved(900), 3, 'percent 900 -> last')
eq(L.parseSaved('200%'), 2, 'string 200%')
eq(L.parseSaved(' 300 % '), 3, 'string with spaces')
eq(L.parseSaved('2'), 2, 'string index')
eq(L.parseSaved(''), 1, 'empty string')

eq(L.clampIndex(nil), 1, 'clamp nil')
eq(L.percent(2), 200, 'percent of 2')
eq(L.percent(99), 300, 'percent of 99 clamps')
eq(L.percent(-1), 100, 'percent of -1 clamps')

-- what fits (window size -> highest step with a 1024x576 interface)
eq(L.maxIndex(1280, 720), 1, '720p -> 100 only')
eq(L.maxIndex(1366, 768), 1, '768p -> 100 only')
eq(L.maxIndex(1920, 1080), 1, '1080p -> 100 only (960x540 is too small)')
eq(L.maxIndex(2048, 1152), 2, '2048x1152 -> 200')
eq(L.maxIndex(2560, 1440), 2, '1440p -> 200')
eq(L.maxIndex(3440, 1440), 2, 'ultrawide 1440p -> 200')
eq(L.maxIndex(3840, 2160), 3, '4K -> 300')
eq(L.maxIndex(3072, 1728), 3, '3072x1728 -> 300 (1024x576 exactly)')
eq(L.maxIndex(3071, 1728), 2, 'one pixel short -> 200')
eq(L.maxIndex(0, 0), 1, 'minimised window -> 100')
eq(L.maxIndex(nil, 1000), 1, 'nil width -> 100')

-- effective and factor
eq(L.effectiveIndex(3, 2560, 1440), 2, '300 asked on 1440p -> 200')
eq(L.effectiveIndex(2, 1920, 1080), 1, '200 asked on 1080p -> 100')
eq(L.effectiveIndex(2, 3840, 2160), 2, '200 on 4K stays')
eq(L.effectiveIndex(1, 3840, 2160), 1, '100 on 4K stays')
eq(L.factor(2, 2560, 1440), 2.0, 'factor 2.0')
eq(L.factor(3, 3840, 2160), 3.0, 'factor 3.0')
eq(L.factor(3, 1920, 1080), 1.0, 'factor 1.0 on a small window')
eq(L.factor('junk', 3840, 2160), 1.0, 'junk wanted -> 1.0')

print(string.format('uiscale_test: %d checks, %d failed', checks, fails))
os.exit(fails == 0 and 0 or 1)
