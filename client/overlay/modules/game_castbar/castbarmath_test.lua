-- luajit castbarmath_test.lua && lua5.3 castbarmath_test.lua
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'castbarmath.lua')
local M = CastbarMath
local fails, checks = 0, 0
local function eq(a, b, what)
  checks = checks + 1
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

eq(M.progress(1000, 1500, 1000), 0, 'start')
eq(M.progress(1000, 1500, 1750), 0.5, 'half')
eq(M.progress(1000, 1500, 9000), 1, 'clamped at 1')
eq(M.progress(1000, 1500, 500), 0, 'clamped at 0')
eq(M.progress(1000, 0, 500), 1, 'no time')
eq(M.label('Doomtide', 1500, 700), 'Doomtide  0.8s', 'label')
eq(M.label('Doomtide', 1500, 2000), 'Doomtide  0.0s', 'label never negative')
eq(M.resultText('done'), nil, 'done has no text')
eq(M.resultText('moved'), 'Interrupted: moved', 'moved')
eq(M.resultText('whatever'), 'Interrupted', 'unknown reason')

-- tiles: 15 x 11 visible on 960 x 704 -> 64 x 64
local rect, vd = { x = 100, y = 50, width = 960, height = 704 }, { width = 15, height = 11 }
local tw, th = M.tileSize(rect, vd, true)
eq(tw, 64, 'tile w'); eq(th, 64, 'tile h')
local x, y = M.place(rect, vd, true, 0, 0, 150, 14, 1)
eq(x, 100 + 480 - 75, 'own bar x'); eq(y, 50 + 352 - 64 - 14, 'own bar y')
x, y = M.place(rect, vd, true, 2, -1, 96, 9, 1)
eq(x, 100 + 480 + 128 - 48, 'other bar x'); eq(y, 50 + 352 - 64 - 64 - 9, 'other bar y')
eq(M.place(rect, vd, true, 20, 0, 96, 9, 1), nil, 'off the map')
eq(M.tileSize(nil, vd, true), 32, 'no rect')

-- messages
local m = M.parse({ action = 'start', data = { s = 4, n = 'Doomtide', ms = 1500, id = 206 } })
eq(m.action, 'start', 'start'); eq(m.ms, 1500, 'start ms'); eq(m.serial, 4, 'serial'); eq(m.name, 'Doomtide', 'name')
eq(M.parse({ action = 'start', data = { n = 'x' } }), nil, 'start without ms')
eq(M.parse({ action = 'start', data = { ms = 999999 } }).ms, 60000, 'ms capped')
eq(M.parse({ action = 'end', data = { s = 4, r = 'moved' } }).result, 'moved', 'end')
eq(M.parse({ action = 'other', data = { c = 7, n = 'Hail of Dawn', ms = 1000 } }).cid, 7, 'other')
eq(M.parse({ action = 'other', data = { n = 'x', ms = 1 } }), nil, 'other without cid')
eq(M.parse({ action = 'otherEnd', data = { c = 7, r = 'done' } }).result, 'done', 'otherEnd')
eq(M.parse({ action = 'nope' }), nil, 'unknown action')
eq(M.parse('text'), nil, 'not a table')

print(string.format('castbarmath_test: %d checks, %d failed', checks, fails))
if fails > 0 then os.exit(1) end
