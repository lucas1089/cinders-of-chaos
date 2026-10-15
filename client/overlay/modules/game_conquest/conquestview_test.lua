-- luajit conquestview_test.lua (CI runs every client *_test.lua from the repo root, under LuaJIT and Lua 5.3)
dofile((arg and arg[0] and arg[0]:match('^(.*[/\\])') or '') .. 'conquestview.lua')
local V = ConquestView
local n = 0
local function eq(a, b, m) n = n + 1 if a ~= b then error((m or '') .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b), 2) end end
local function has(text, part, m) n = n + 1 if not tostring(text):find(part, 1, true) then error((m or '') .. ': ' .. tostring(text), 2) end end

local s = {
  bal = 1500, level = 120, pz = true, band = 50,
  groups = { { g = 'monster', n = 'Monster unique' }, { g = 'boss', n = 'Boss unique' }, { g = 'set', n = 'Set piece' },
    { g = 'raid', n = 'Raid unique' }, { g = 'ascended', n = 'Ascended unique' } },
  offers = {
    { k = 'u:2412', id = 2412, c = 2411, n = 'Nightfang Katana', g = 'monster', l = 60, p = 690, ok = true },
    { k = 'u:36659', id = 36659, c = 36658, n = 'Grasp of the Pyre Saint', g = 'monster', l = 650, p = 1580, ok = true },
    { k = 'u:8925', id = 8925, c = 8924, n = 'Cinderbrand Axe', g = 'boss', l = 130, p = 1390, ok = true },
    { k = 'u:2123', id = 2123, c = 2122, n = 'Cinderheart Signet', g = 'ascended', l = 1000, p = 5400, why = 'not seen' },
    { k = 'u:2496', id = 2496, c = 2495, n = 'Hornsworn Helm', g = 'set', l = 70, p = 980, ok = true, set = 'Embers of Aranoth' },
  },
  pity = { { g = 'raid', n = 'Raid uniques', m = 4, x = 2 } },
  today = { { k = 'boss_world', n = 'world boss', got = 24, cap = 72 } },
  cinder = { omenKey = 150, attune = 40, shard = 300, convert = { shards = 2, relics = 2, fee = 0 },
    omens = { { k = 'storm', n = 'Stormcall' } }, ascended = { { k = 'storm', n = 'Storm' }, { k = 'hollow', n = 'Hollow Crown' } },
    shards = { storm = 3 }, relics = {} },
  refine = { { slot = 6, n = 'a blade', c = 100, r = 5, rn = 'Legendary', to = 'Exotic', p = 300, ok = true } },
}

has(V.header(s), '1,500', 'balance in the header')
has(V.header(s), 'level 170', 'the band')
local rows = V.rows(s, 'uniques')
eq(#rows, 3, 'monster and boss uniques')
eq(rows[1].key, 'u:2412', 'key')
eq(rows[1].canBuy, true, 'affordable and on sale')
eq(rows[2].canBuy, false, 'the Grasp costs more than the balance')
has(rows[2].tip, '1,580', 'why')
has(rows[1].sub, 'Monster unique, level 60', 'sub text')
rows = V.rows(s, 'sets')
eq(#rows, 1, 'set pieces')
has(rows[1].sub, 'Embers of Aranoth', 'the set name')
rows = V.rows(s, 'chase')
eq(rows[1].canBuy, false, 'a hidden item')
eq(rows[1].locked, true, 'shown locked')
eq(rows[1].tip, 'not seen', 'the server reason')
rows = V.rows(s, 'cinder')
eq(rows[1].key, 'omen:storm', 'an Omen Key of a kind')
eq(rows[2].canBuy, false, 'attune needs a key')
local conv
for _, r in ipairs(rows) do if r.key == 'conv:shards:storm:hollow' then conv = r end end
eq(conv and conv.canBuy, true, 'two storm shards convert')
rows = V.rows(s, 'refine')
eq(rows[1].key, 'refine:6', 'refine the worn slot')
has(rows[1].sub, 'Legendary to Exotic', 'refine text')
local lines = V.progressLines(s)
has(table.concat(lines, '\n'), 'Raid uniques: 4 misses in a row, chance x2.00', 'pity line')
has(table.concat(lines, '\n'), 'world boss: 24 of 72', 'today line')
s.pz = false
eq(V.rows(s, 'uniques')[1].canBuy, false, 'outside a protection zone')
-- bad states never error
for _, bad in ipairs({ nil, 5, {}, { offers = 5 }, { offers = { 5, 'x' }, cinder = 3 }, { refine = { 7 } } }) do
  for _, t in ipairs(V.TABS) do V.rows(bad, t.id) end
  V.progressLines(bad)
  V.header(bad)
  V.placeText(bad)
end
eq(V.clientId(70000), 0, 'client id range')
eq(V.tab('nope').id, 'uniques', 'unknown tab')
print('conquestview_test: ' .. n .. ' checks OK')
