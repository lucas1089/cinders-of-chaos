-- luajit tooltipsets_test.lua && lua5.3 tooltipsets_test.lua
-- The set block of an item set piece's tooltip (tooltiplogic.lua L.setLines inside L.lines, L.dropSetTips): the header
-- with the pieces that count, every piece (worn / worn below its level / not worn), every bonus (active / not), the
-- wrap of long bonus texts, an old server's header-only block and the cache drop when the equipment changes.
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'tooltiplogic.lua')
local L = ItemTooltipLogic
local C = L.COLORS
local fails, checks = 0, 0
local function eq(a, b, what)
  checks = checks + 1
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

-- what the server sends for a Bloodsworn Visage when the player wears the visage and the hauberk (2 of 6)
local set = {
  key = 'bloodsworn', name = 'Bloodsworn Reaver', have = 2, total = 6,
  pieces = {
    { n = 'Bloodsworn Greataxe', lv = 300, h = 2 },
    { n = 'Bloodsworn Visage', lv = 300, eq = true },
    { n = 'Bloodsworn Hauberk', lv = 300, eq = true },
    { n = 'Bloodsworn Legplates', lv = 300, low = true },
    { n = 'Bloodsworn Treads', lv = 300 }
  },
  bonuses = {
    { n = 2, t = 'Chance to Bleed +10%, Damage over Time +15%', on = true },
    { n = 4, t = 'Hemorrhage: a monster that dies bleeding from you passes the bleed to 3 monsters within 2 sqm' },
    { n = 6, t = 'Axe Fighting +3, Red Harvest: your critical hits open a fresh bleed on the target' }
  }
}
local rows = L.setLines(set)
eq(rows[1].text, 'Set: Bloodsworn Reaver (2/6)', 'header with the count')
eq(rows[1].color, C.set, 'header in the set colour')
eq(rows[1].sep, true, 'a rule above the block')
eq(rows[2].text, '  Bloodsworn Greataxe (counts 2)', 'a two-handed piece says it counts twice')
eq(rows[2].color, C.empty, 'not worn: dim')
eq(rows[3].text, '  Bloodsworn Visage', 'worn piece')
eq(rows[3].color, C.setOn, 'worn: bright')
eq(rows[4].color, C.setOn, 'the hauberk too')
eq(rows[5].text, '  Bloodsworn Legplates (level 300)', 'worn below its level: the level')
eq(rows[5].color, C.setLow, 'below its level: rust')
eq(rows[6].color, C.empty, 'the treads not worn')
local function rowOf(prefix)
  for i, r in ipairs(rows) do
    if r.text:sub(1, #prefix) == prefix then return i, r end
  end
end
local i2, b2 = rowOf('(2) ')
eq(i2, 7, 'the bonuses after the pieces')
eq(b2.text, '(2) Chance to Bleed +10%, Damage over Time', 'the active bonus, wrapped')
eq(rows[8].text, '    +15%', 'its second line indented')
eq(b2.color, C.setOn, 'active: bright') eq(rows[8].color, C.setOn, 'the second line too')
eq(b2.sep, true, 'a rule above the bonuses')
local i4, b4 = rowOf('(4) Hemorrhage: ')
eq(b4 ~= nil, true, 'the 4-piece bonus starts with its count')
eq(b4.color, C.dim, 'the 4-piece bonus is not active')
eq(rows[i4 + 1].text:sub(1, 4), '    ', 'a wrapped line is indented')
eq(rows[i4 + 1].color, C.dim, 'and keeps the colour')
eq(b4.sep, false, 'one rule for the bonuses')
local longest = 0
for _, r in ipairs(rows) do longest = math.max(longest, #r.text) end
eq(longest <= L.WRAP + 4, true, 'nothing longer than the wrap (+ indent)')
local six = rows[#rows]
eq(six.color, C.dim, 'the 6-piece bonus is not active')

-- inside the whole tooltip: the title says Set, the block follows the stats
local tip = { name = 'Bloodsworn Visage', slot = 'Helmet', rarity = 0, unique = { name = 'Bloodsworn Visage', set = set },
  base = { { k = 'armor', l = 'Armour', v = 11 } }, req = { level = 300 }, desc = 'A face of hammered iron.' }
local lines = L.lines(tip, { level = 400 })
eq(lines[1].text, 'Set Helmet', 'sub title')
eq(L.titleColor(tip), C.set, 'title colour')
local headerAt, reqAt
for i, l in ipairs(lines) do
  if l.text == 'Set: Bloodsworn Reaver (2/6)' then headerAt = i end
  if l.text == 'Requires level 300' then reqAt = i end
end
eq(headerAt ~= nil and reqAt ~= nil and headerAt < reqAt, true, 'the set block before the requirements')
eq(lines[headerAt + 2].color, C.setOn, 'worn pieces bright in the tooltip')

-- a full set: everything bright
local full = { name = 'Duskstalker Garb', have = 6, total = 6, pieces = { { n = 'Duskstalker Fang', eq = true } },
  bonuses = { { n = 2, t = 'Dodge +4%', on = true }, { n = 6, t = 'Umbral Recoil', on = true } } }
rows = L.setLines(full)
eq(rows[1].text, 'Set: Duskstalker Garb (6/6)', 'full')
eq(rows[3].color, C.setOn, 'bonus 2 on') eq(rows[4].color, C.setOn, 'bonus 6 on')

-- an older server: the name and counts only
rows = L.setLines({ name = 'Embers of Aranoth', have = 1, total = 6 })
eq(#rows, 1, 'header only')
eq(rows[1].text, 'Set: Embers of Aranoth (1/6)', 'header text')
eq(#L.setLines(nil), 0, 'nothing for no set')

-- the cache: set pieces are dropped when the equipment changes, other tooltips stay
local c = L.newCache()
L.cachePut(c, '1:1', tip, false, 0)
L.cachePut(c, '2:1', { name = 'Soulreaper', unique = { name = 'Soulreaper' } }, false, 0)
L.cachePut(c, '3:1', { name = 'magic sword' }, false, 0)
eq(L.dropSetTips(c), 1, 'one set piece dropped')
eq(L.cacheGet(c, '1:1', 0), nil, 'the piece is asked again')
eq(L.cacheGet(c, '2:1', 0) ~= nil, true, 'a unique stays')
eq(L.cacheGet(c, '3:1', 0) ~= nil, true, 'a plain item stays')
eq(#c.order, 2, 'the order list follows')
eq(L.dropSetTips(c), 0, 'nothing left to drop')

-- an open set of pair 28 (server tip.set on a plain item): the active tier line, the block shown, dropped from the cache
local open = { name = 'Bloodmoon', have = 4, total = 6, tier = 2, tiers = 3, pieces = { { n = 'bloodmoon greathelm', eq = true } },
  bonuses = { { n = 2, t = 'Health on Hit +8', on = true }, { n = 4, t = 'Life on Kill +40', on = true },
    { n = 6, t = 'Health on Hit +8' } } }
rows = L.setLines(open)
eq(rows[2].text, 'Active tier: 2 of 3', 'the tier line') eq(rows[2].color, C.setOn, 'tier line bright')
eq(rows[#rows].color, C.dim, 'the 6 piece bonus dim')
eq(L.setLines({ name = 'Gildcrown', have = 1, total = 6, tier = 0, tiers = 3 })[2].color, C.dim, 'tier 0 dim')
local plain = { name = 'bloodmoon greathelm', rarityName = 'Rare', rarity = 3, set = open }
local found = false
for _, l in ipairs(L.lines(plain, { level = 500 })) do
  found = found or l.text == 'Active tier: 2 of 3'
end
eq(found, true, 'a plain set piece shows the set block')
local c2 = L.newCache()
L.cachePut(c2, '9:1', plain, false, 0)
eq(L.dropSetTips(c2), 1, 'an open set piece is dropped on an equipment change')

print(string.format('tooltipsets_test: %d checks%s', checks, fails > 0 and (', ' .. fails .. ' failure(s)') or ' OK'))
if fails > 0 then os.exit(1) end
