-- luajit / lua5.3, from the repo root: client/overlay/modules/game_passivetree/treetips_test.lua
local dir = (arg and arg[0] or ''):match('^(.*)/[^/]*$') or '.'
dofile(dir .. '/treetips.lua')
local function tr(s) return '<' .. s .. '>' end
local function eq(a, b, msg)
  assert(#a == #b, msg .. ': count ' .. #a .. ' ~= ' .. #b)
  for i = 1, #a do assert(a[i] == b[i], msg .. ': line ' .. i .. ' ' .. tostring(a[i]) .. ' ~= ' .. tostring(b[i])) end
end
local base = { '+10 Strength', 'Requires: Knight.' }
local extra = { 'Strength: more melee damage.' }
eq(TreeTips.lines(base, extra, false, tr), { '+10 Strength', 'Requires: Knight.', '<Hold Alt for what each bonus does.>' }, 'no alt')
eq(TreeTips.lines(base, extra, true, tr), { '+10 Strength', 'Requires: Knight.', 'Strength: more melee damage.' }, 'alt')
eq(TreeTips.lines(base, {}, false, tr), base, 'no explanation, no hint')
eq(TreeTips.lines(base, nil, true, tr), base, 'nil explanation')
eq(TreeTips.lines(nil, extra, true, tr), extra, 'nil texts')
-- the input lists are not changed
assert(#base == 2 and #extra == 1, 'inputs untouched')
print('treetips_test: ok')
