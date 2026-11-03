-- luajit / lua5.3 from the repo root: the pure part of the crafting bench Guide window (craftguideview.lua)
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'craftguideview.lua')
local V = CraftGuideView
local fails, count = 0, 0
local function eq(a, b, what)
  count = count + 1
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end
local function tr(s, ...) if select('#', ...) > 0 then return string.format(s, ...) end return s end

-- every orb of the bench has advice and a risk (the keys of server data/lib/chaos_crafting.lua and chaos_orbs_config.lua)
for _, key in ipairs({ 'transmutation', 'alchemy', 'exalted', 'annulment', 'scouring', 'chaos', 'divine', 'sockets',
    'tempering', 'binding', 'excision', 'reforging', 'ruin', 'whetstone', 'unveiling', 'ember', 'crown', 'void' }) do
  eq(V.advice(key, tr) ~= '', true, 'advice for ' .. key)
  eq(V.RISK_COLOR[V.RISK[key]] ~= nil, true, 'risk for ' .. key)
  eq(V.riskText(V.RISK[key], tr) ~= '', true, 'risk text for ' .. key)
end
eq(V.advice('nope', tr), '', 'unknown orb: no advice')
eq(V.riskText(nil, tr), '', 'unknown risk')
eq(#V.basics(tr), 5, 'five basics')
eq(#V.plan(tr), 8, 'eight plan steps')

eq(V.number(1234567), '1,234,567', 'number with commas')
eq(V.number(200), '200', 'small number')
eq(V.number(nil), '0', 'nil number')

local guide = {
  tiers = { 'Chipped', 'Flawed', 'Polished', 'Flawless', 'Perfect' },
  removeCost = { 2000, 6000, 20000, 60000, 200000 },
  socketOrb = 'Orb of Sockets',
  effects = {
    dmg_fire = { label = 'Fire Damage', fmt = 'pct', cap = 40 },
    maxhealth = { label = 'Max Health', fmt = 'flat', cap = 2000 },
    crit = { label = 'Critical Chance', label2 = 'Critical Hit', fmt = 'pair', cap = 10 },
  },
  types = {
    { name = 'Ruby', color = '#ff5a4a', look = { 1, 2, 3, 4, 5 },
      weapon = { effect = 'dmg_fire', values = { 2, 4, 6, 9, 12 } },
      armour = { effect = 'maxhealth', values = { 20, 45, 80, 130, 200 } },
      jewel = { effect = 'crit', values = { 1, 1, 2, 3, 3 }, values2 = { 5, 10, 15, 20, 25 } } },
  },
}
local rows = V.gemRows(guide, tr)
eq(#rows, 1, 'one gem row')
eq(rows[1].name, 'Ruby', 'gem name')
eq(rows[1].look, 5, 'best quality look')
eq(rows[1].groups[1].label, 'Weapon', 'weapon first')
eq(rows[1].groups[1].text, 'Fire Damage +2 / 4 / 6 / 9 / 12%', 'pct series')
eq(rows[1].groups[1].cap, '40%', 'pct cap')
eq(rows[1].groups[2].text, 'Max Health +20 / 45 / 80 / 130 / 200', 'flat series')
eq(rows[1].groups[2].cap, '2000', 'flat cap')
eq(rows[1].groups[3].label, 'Jewellery', 'jewellery last')
eq(rows[1].groups[3].text, 'Critical Chance +1 / 1 / 2 / 3 / 3%, Critical Hit +5 / 10 / 15 / 20 / 25%', 'pair series')
eq(#V.gemRows(nil, tr), 0, 'no guide yet')
eq(#V.gemRows({ types = { { name = 'X' } } }, tr)[1].groups, 0, 'a gem without groups')

local basics = V.gemBasics(guide, tr)
eq(#basics, 6, 'six gem paragraphs')
eq(basics[4][2]:find('Chipped, Flawed, Polished, Flawless, Perfect', 1, true) ~= nil, true, 'qualities listed')
eq(basics[5][2]:find('2,000 / 6,000 / 20,000 / 60,000 / 200,000', 1, true) ~= nil, true, 'remove costs listed')
eq(#V.gemBasics(nil, tr), 6, 'gem paragraphs without data')

print(string.format('craftguideview: %d checks, %d failed', count, fails))
if fails > 0 then os.exit(1) end
