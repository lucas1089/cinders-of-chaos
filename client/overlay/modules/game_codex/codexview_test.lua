-- Run from the repo root: luajit client/overlay/modules/game_codex/codexview_test.lua (also lua5.3)
-- The Codex view logic (codexview.lua) on small hand-made data and on the generated codex_data.lua.
local here = (arg and arg[0] or ''):match('^(.*)/[^/]*$') or '.'
dofile(here .. '/codexview.lua')
local V = CodexView
local fails, n = 0, 0
local function eq(a, b, name)
  n = n + 1
  if a ~= b then fails = fails + 1; print('FAIL ' .. name .. ': got ' .. tostring(a) .. ', want ' .. tostring(b)) end
end

-- ---------------------------------------------------------------- search and filters on a small tab
local shared = { ['orbs:prefix'] = { h = 'Orbs', cols = { 'Orb', 'Effect' }, rows = { { 'Orb of Grafting', 'Adds it' } } } }
local tab = {
  filters = {
    { key = 'side', match = 'eq', options = { { '', 'Any' }, { 'prefix', 'Prefixes' } } },
    { key = 'kind', match = 'has', options = { { '', 'Any' }, { 'weapon', 'Weapon' } } },
    { key = 'level', match = 'max', options = { { '', 'Any' }, { '70', '70' } } },
    { key = 'ilvl', match = 'ilvl', options = { { '', 'Any' }, { '150', '150' } } },
  },
  entries = {
    { id = 'a', name = 'Attack Speed', sub = 'Suffix', f = { side = 'suffix', kind = { 'weapon' }, level = 50 },
      sections = { { h = 'Overview', p = { 'Local to the weapon.' } } } },
    { id = 'b', name = 'Thorns', sub = 'Prefix', f = { side = 'prefix', kind = { 'armor', 'shield' }, level = 90 },
      sections = { { h = 'Tiers', cols = { 'Tier', 'Value' }, rows = { { 'T1', '+1-4' } } }, { ref = 'orbs:prefix' } } },
    { id = 'c', name = 'Block Chance', sub = 'Prefix', f = { side = 'prefix', kind = { 'shield' } },
      sections = { { h = 'Overview', p = { 'Shields only.' } } } },
  }
}
local function ids(list)
  local out = {}
  for _, e in ipairs(list) do out[#out + 1] = e.id end
  return table.concat(out, ',')
end

eq(table.concat(V.tokens('  Attack   SPEED '), '|'), 'attack|speed', 'tokens')
eq(#V.tokens(''), 0, 'no tokens')
eq(ids(V.list(tab, '', {}, shared)), 'a,b,c', 'everything')
eq(ids(V.list(tab, 'speed', {}, shared)), 'a', 'search by name')
eq(ids(V.list(tab, 'WEAPON', {}, shared)), 'a', 'search in the page, any case')
eq(ids(V.list(tab, 'grafting', {}, shared)), 'b', 'search in a shared section')
eq(ids(V.list(tab, '+1-4', {}, shared)), 'b', 'search in table cells')
eq(ids(V.list(tab, 'prefix shields', {}, shared)), 'c', 'every word must match')
eq(ids(V.list(tab, 'nothing-like-this', {}, shared)), '', 'no hit')
eq(V.hasWord('life on kill', 'kill'), true, 'word start')
eq(V.hasWord('armorsmithing skill', 'kill'), false, 'not inside a word')
eq(V.hasWord('chance +5% (t1)', '+5%'), true, 'sign word anywhere')
eq(V.hasWord('critical hit', 'crit'), true, 'prefix of a word')
eq(V.hasWord("hunter's rush", "hunter's"), true, 'apostrophe')
eq(V.hasWord('a.b', 'b'), true, 'after punctuation')
eq(ids(V.list(tab, '', { side = 'prefix' }, shared)), 'b,c', 'eq filter')
eq(ids(V.list(tab, '', { kind = 'shield' }, shared)), 'b,c', 'has filter')
eq(ids(V.list(tab, '', { kind = 'weapon', side = 'prefix' }, shared)), '', 'two filters')
eq(ids(V.list(tab, '', { level = '70' }, shared)), 'a', 'max filter (no level = out)')
eq(ids(V.list(tab, '', { ilvl = '150' }, shared)), 'a,b,c', 'item level does not filter')
eq(ids(V.list(tab, '', { side = '' }, shared)), 'a,b,c', 'empty value')
eq(V.section({ ref = 'orbs:prefix' }, shared).h, 'Orbs', 'shared section')
eq(V.section({ ref = 'missing' }, shared), nil, 'missing shared section')
eq(V.levelOf({ ilvl = '95' }, tab.filters), 95, 'chosen item level')
eq(V.levelOf({ ilvl = '' }, tab.filters), nil, 'no item level')

-- ---------------------------------------------------------------- tiers at an item level
local data = { tierLevels = { 1, 15, 30, 50, 70, 95, 120, 140 }, tierWeights = { 100, 90, 80, 65, 50, 35, 22, 12 },
  tierWindow = 5 }
eq(V.maxTier(1, data), 1, 'T1 at 1')
eq(V.maxTier(149, data), 8, 'T8 at 149')
eq(V.maxTier(94, data), 5, 'T5 at 94')
local rows = V.tierRows(150, data)
eq(#rows, 5, 'five tiers roll')
eq(rows[1][1], 8, 'best first')
eq(rows[5][1], 4, 'T4 lowest at 150')
eq(#V.tierRows(20, data), 2, 'only two tiers at 20')
local ch = V.tierChances(150, data)
eq(ch[8], 6.5, 'T8 6.5% at 150 (server README)')
eq(ch[4], 35.3, 'T4 at 150')
ch = V.tierChances(40, data)
eq(ch[3], 29.6, 'T3 at 40'); eq(ch[1], 37, 'T1 at 40')
local entry = { sub = 'own line', tv = { '+1', '+2', '+3', '+4', '+5', '+6', '+7', '+8' } }
eq(V.subline(entry, nil, data), 'own line', 'no level: own line')
eq(V.subline(entry, 150, data), 'Item level 150: T4-T8: +4 to +8', 'tiers at 150')
eq(V.subline(entry, 1, data), 'Item level 1: T1 +1', 'one tier')
eq(V.subline({ sub = 'x' }, 150, data), 'x', 'no tiers: own line')
local hl = V.highlight({ tiers = true }, entry, 30, data)
eq(hl[3], true, 'T3 rolls at 30'); eq(hl[1], true, 'T1 rolls at 30'); eq(hl[4], nil, 'T4 does not')
eq(next(V.highlight({ tiers = true }, entry, nil, data)), nil, 'no level: nothing marked')
eq(next(V.highlight({}, entry, 30, data)), nil, 'not a tier table')

-- ---------------------------------------------------------------- columns
local cols = V.columns({ 30, 70 }, 400, 10)
eq(cols[1] + cols[2], 390, 'widths add up')
eq(cols[1], 117, 'share')
cols = V.columns({ 14, 22, 40, 24 }, 503, 6)
eq(cols[1] + cols[2] + cols[3] + cols[4], 485, 'four columns add up')
cols = V.columns({ 0, 0 }, 100, 0)
eq(cols[1], 50, 'no weights: equal')
cols = V.columns({ 1, 1, 1 }, 2, 5)
eq(cols[1] >= 1 and cols[2] >= 1 and cols[3] >= 1, true, 'never below one pixel')

-- ---------------------------------------------------------------- the generated data
dofile(here .. '/codex_data.lua')
local D = CodexData
eq(type(D), 'table', 'codex data loads')
eq(#D.tabs, 11, 'eleven tabs (Lore is the last)')
local total = 0
for _, t in ipairs(D.tabs) do
  total = total + #t.entries
  eq(#V.list(t, '', {}, D.shared), #t.entries, 'unfiltered ' .. t.id)
  for _, f in ipairs(t.filters) do
    for _, o in ipairs(f.options) do
      if o[1] ~= '' and f.match ~= 'ilvl' then
        -- every option of a filter keeps something (no dead options)
        local values = { [f.key] = o[1] }
        eq(#V.list(t, '', values, D.shared) > 0, true, 'option ' .. t.id .. '/' .. f.key .. '=' .. o[1])
      end
    end
  end
end
eq(total > 150, true, 'many entries')
local ti, e = V.find(D, 'mod:chaos_mod_attackspeed')
eq(D.tabs[ti].id, 'modifiers', 'attack speed tab')
eq(e.name, 'Attack Speed', 'attack speed entry')
eq(V.idForMod('chaos_mod_attackspeed', 'chaos', D), 'mod:chaos_mod_attackspeed', 'bench key chaos')
eq(V.idForMod('rarity_swordSkill', 'skill', D), 'mod:rarity_swordskill', 'bench key any case')
eq(V.idForMod('chaos_mod_deathblast', 'chaos', D), 'power:deathblast', 'bench key of a power')
eq(V.idForMod('vitality', 'rift', D), 'rift:vitality', 'bench key of a rift modifier')
eq(V.idForMod('nope', 'chaos', D), nil, 'unknown key')
eq(V.idForMod(nil, 'chaos', D), nil, 'no key')
local mods = D.tabs[1]
eq(#V.list(mods, 'attack speed', {}, D.shared) >= 1, true, 'search the real data')
eq(#V.list(mods, '', { side = 'prefix', kind = 'boots' }, D.shared) > 0, true, 'prefixes on boots')
for _, x in ipairs(V.list(mods, '', { kind = 'boots' }, D.shared)) do
  local ok = false
  for _, k in ipairs(x.f.kind) do if k == 'boots' then ok = true end end
  eq(ok, true, 'boots filter: ' .. x.id)
end
eq(V.subline(e, 150, D), 'Item level 150: T4-T8: +4-6% to +11-14%', 'attack speed at 150')
local _, unique = V.find(D, 'unique:8209')
eq(unique.name, 'Soulreaper', 'unique entry')
eq(#V.list(D.tabs[5], 'soulreaper', { level = '130' }, D.shared), 1, 'unique by level')
eq(#V.list(D.tabs[5], 'soulreaper', { level = '110' }, D.shared), 0, 'unique above the level')

print(string.format('codexview_test: %d checks, %d failed', n, fails))
if fails > 0 then os.exit(1) end
