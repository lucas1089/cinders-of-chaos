-- luajit errorcolor_test.lua && lua5.3 errorcolor_test.lua
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'errorcolor_core.lua')
local fails = 0
local function eq(a, b, what)
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end
local small = { color = 'white', screenTarget = 'statusLabel' }
local types = { [19] = small, [20] = small }
local prev = ErrorColor.apply(types, 19, '#ff7a5c')
eq(prev, small, 'previous entry returned')
eq(types[19].color, '#ff7a5c', 'error mode coloured')
eq(types[19].screenTarget, 'statusLabel', 'target kept')
eq(types[20].color, 'white', 'other mode sharing the table untouched')
eq(small.color, 'white', 'stock table not modified')
eq(ErrorColor.apply(types, 19, '#00ff00'), false, 'second apply does nothing')
eq(types[19].color, '#ff7a5c', 'second apply keeps the colour')
ErrorColor.restore(types, 19, prev)
eq(types[19], small, 'restored')
eq(ErrorColor.withColor(small, 'bad').color, ErrorColor.COLOR, 'bad colour falls back')
eq(ErrorColor.withColor(nil), nil, 'nil base')
eq(ErrorColor.apply(nil, 19), false, 'nil types')
eq(ErrorColor.apply({}, 19), false, 'missing mode entry')
if fails > 0 then os.exit(1) end
print('errorcolor tests OK')
