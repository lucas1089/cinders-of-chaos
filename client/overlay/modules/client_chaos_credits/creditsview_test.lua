-- luajit creditsview_test.lua && lua5.3 creditsview_test.lua (CI runs it from the repo root)
-- The Credits window's blocks from the generated data (credits_data.lua from docs/CREDITS.md): every section and
-- entry drawn, headings through tr() with the pt-BR table, the required credit lines word for word, cp1252 text.
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'credits_data.lua')
dofile(dir .. 'creditsview.lua')
dofile(dir .. '../client_chaos_locale/locale_core.lua')
dofile(dir .. '../client_chaos_locale/pt_br.lua')
local V = CreditsView
local D = ChaosCreditsData
local fails = 0
local function ok(cond, what)
  if not cond then print('FAIL ' .. what); fails = fails + 1 end
end
local function eq(a, b, what)
  ok(a == b, what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b))
end

-- the data
ok(type(D) == 'table' and #D >= 5, 'sections in the data')
local titles, entries = {}, 0
for _, s in ipairs(D) do
  titles[s.title] = s
  ok(type(s.pt) == 'string' and s.pt ~= '', 'pt-BR heading of ' .. tostring(s.title))
  for _, e in ipairs(s.entries) do
    entries = entries + 1
    ok(type(e.name) == 'string' and e.name ~= '', 'entry name in ' .. s.title)
  end
end
ok(entries >= 30, 'entries in the data')
for _, t in ipairs({ 'Art with required credit', 'Art packs', 'Free assets', 'Fonts', 'Engine and libraries' }) do
  ok(titles[t] ~= nil, 'section ' .. t)
end

-- the required credit lines, word for word
local credits = V.requiredCredits(D)
local want = {
  ["Will's Pixel Explosions - Will Tice / unTied Games"] = true,
  ['Super Pixel Effects Gigapack - Will Tice / unTied Games'] = true,
}
local seen = 0
for _, c in ipairs(credits) do if want[c] then seen = seen + 1 end end
eq(seen, 2, 'both unTied Games credit lines')

-- blocks in English: intro first, one section block per section, one name block per entry, every credit line drawn
local blocks = V.blocks(D)
eq(blocks[1].style, 'intro', 'intro first')
local count = { section = 0, name = 0, credit = 0 }
local drawn = {}
for _, b in ipairs(blocks) do
  count[b.style] = (count[b.style] or 0) + 1
  drawn[b.text] = true
  ok(type(b.color) == 'string' and b.color:sub(1, 1) == '#', 'colour of a ' .. b.style .. ' block')
end
eq(count.section, #D, 'a heading per section')
eq(count.name, entries, 'a name per entry')
eq(count.credit, #credits, 'a credit block per required line')
for line in pairs(want) do ok(drawn[line], 'drawn: ' .. line) end
ok(drawn['Author: Will Tice / unTied Games'], 'author line')
ok(drawn['Licence: SIL Open Font License 1.1'], 'licence line')

-- pt-BR: the headings and the line labels come from the locale table
local PT = ChaosLocaleCore.prepare(ChaosLocaleStrings['pt-BR']) -- cp1252, as the client's tr() gives it
local function trPt(text, ...)
  local t = PT[text] or text
  if select('#', ...) > 0 then return string.format(t, ...) end
  return t
end
local ptBlocks = V.blocks(D, trPt)
local ptDrawn = {}
for _, b in ipairs(ptBlocks) do ptDrawn[b.text] = true end
for _, s in ipairs(D) do
  eq(PT[s.title] or s.title, s.pt, 'pt_br.lua heading of ' .. s.title)
  ok(ptDrawn[s.pt], 'pt-BR heading drawn: ' .. s.title)
end
ok(ptDrawn['Autor: Will Tice / unTied Games'], 'pt-BR author label')
ok(PT['Cinders of Chaos is made with the work of these people and projects. Thank you!'] ~= nil, 'pt-BR intro')

-- cp1252: no UTF-8 sequence reaches the client's fonts (the generator escapes every non-ASCII character)
for _, b in ipairs(blocks) do
  ok(not b.text:find('[\195\194][\128-\191]'), 'cp1252 text: ' .. b.text)
end
ok(drawn['Author: Copyright 2011 The Alegreya Project Authors, Huerta Tipogr\225fica'], 'accent as cp1252')

-- no data: the intro only, nothing breaks
eq(#V.blocks(nil), 1, 'no data')
eq(#V.blocks({ { title = 'X', note = '', entries = {} } }), 2, 'empty section')

if fails > 0 then
  print(fails .. ' failure(s)')
  os.exit(1)
end
print('creditsview_test: OK')
