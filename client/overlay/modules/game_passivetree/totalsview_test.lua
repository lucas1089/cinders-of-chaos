-- luajit totalsview_test.lua && lua5.3 totalsview_test.lua
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'totalsview.lua')
local fails = 0
local function eq(a, b, what)
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end
local V = TotalsView
eq(V.num(280), '280', 'integer'); eq(V.num(221.66), '221.7', 'one decimal'); eq(V.num(20.0), '20', 'trailing zero'); eq(V.num(nil), '0', 'nil')
eq(#V.lines(nil), 0, 'nothing sent'); eq(#V.lines({}), 0, 'empty message')
local data = {
  attributes = {{k = 'strength', n = 'Strength', raw = 280, eff = 221.7, cap = 120, effect = 80.3},
    {k = 'vitality', n = 'Vitality', raw = 40, eff = 40, cap = 100, effect = 20}},
  damage = {{k = 'incrementPhysical', n = 'Physical damage', raw = 300, eff = 225.2, cap = 150},
    {k = 'incrementFire', n = 'Fire damage', raw = 30, eff = 30, cap = 150}},
  crit = {chance = {total = 28, tree = 12, other = 16}, amount = {total = 40, tree = 20, paragon = 5, other = 15}}}
local lines = V.lines(data)
eq(#lines, 6, 'six lines')
eq(lines[1].text, 'Strength: 280 points -> 221.7 effective (full value up to 120)', 'over the cap shows both')
eq(lines[1].color, V.OVER, 'over the cap is highlighted')
eq(lines[2].text, 'Vitality: 40 points (full value up to 100)', 'under the cap shows raw only')
eq(lines[3].text, 'Physical damage: +300% -> +225.2% effective (full value up to +150%)', 'damage over')
eq(lines[4].text, 'Fire damage: +30% (full value up to +150%)', 'damage under')
eq(lines[5].text, 'Critical chance: 28% (tree 12%, gear and other 16%)', 'crit chance with gear')
eq(lines[6].text, 'Critical damage: +40% (tree 20%, Paragon 5%, gear and other 15%)', 'crit damage with gear')
eq(#V.lines({crit = {chance = {total = 1}}}), 0, 'a half crit block is ignored')
if fails > 0 then os.exit(1) end
print('totals view tests OK')
