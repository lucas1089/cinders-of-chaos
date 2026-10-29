-- luajit howcore_test.lua && lua5.3 howcore_test.lua (CI runs every client module test from the repo root)
-- The "How it works" cards on the real generated data (howitworks_data.lua): every card has a title and rows in both
-- languages, the rows are in the fixed order, no {place} is left over, pt-BR converts to the client font, the lookups
-- (unlock key, goal key, window) find the card, and the combat features answer the five questions of the tester report
-- (who, monster levels, what drops, what a death costs, how often). The row headings have a pt-BR entry.
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'howitworks_data.lua')
dofile(dir .. 'howcore.lua')
dofile(dir .. '../client_chaos_locale/locale_core.lua')
local pt = dofile(dir .. '../client_chaos_locale/pt_br.lua')
local H, L = HowCore, ChaosLocaleCore
local fails, count = 0, 0
local function eq(a, b, what)
  count = count + 1
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end
local function ok(cond, what) eq(cond and true or false, true, what) end

local rank = {}
for i, id in ipairs(H.ROWS) do rank[id] = i end

local seen = {}
for _, f in ipairs(HowData.features) do
  ok(not seen[f.key], f.key .. ': unique key')
  seen[f.key] = true
  ok(type(f.title) == 'table' and f.title.en and f.title.pt, f.key .. ': title in both languages')
  ok(#f.rows >= 2, f.key .. ': at least two rows')
  local last = 0
  for _, r in ipairs(f.rows) do
    ok(rank[r.id], f.key .. ': known row id ' .. tostring(r.id))
    ok(rank[r.id] and rank[r.id] > last, f.key .. ': rows in order at ' .. tostring(r.id))
    last = rank[r.id] or last
    for _, lang in ipairs({ 'en', 'pt' }) do
      local t = r[lang]
      ok(type(t) == 'string' and #t > 8, f.key .. '.' .. r.id .. '.' .. lang .. ': has text')
      ok(not t:find('[{}]'), f.key .. '.' .. r.id .. '.' .. lang .. ': no place left over')
      ok(not t:find('\226\128\148'), f.key .. '.' .. r.id .. '.' .. lang .. ': no em-dash')
      ok(#t <= 460, f.key .. '.' .. r.id .. '.' .. lang .. ': short enough (' .. #t .. ')')
    end
    ok(r.en ~= r.pt or r.id == 'who' and #r.en < 30, f.key .. '.' .. r.id .. ': pt is not a copy of en')
    ok(not L.toCp1252(r.pt):find('?', 1, true), f.key .. '.' .. r.id .. ': pt converts to cp1252')
  end
end

-- the five questions on the combat features of the tester report
for _, key in ipairs({ 'tower', 'rift', 'arena', 'battleground', 'descent', 'raid', 'siege', 'bosses' }) do
  local f = H.find(HowData, key)
  ok(f, key .. ': card exists')
  local have = {}
  for _, r in ipairs(f.rows) do have[r.id] = true end
  for _, id in ipairs({ 'who', 'levels', 'drops', 'death', 'often' }) do ok(have[id], key .. ': row ' .. id) end
end

-- lookups
eq(H.find(HowData, 'tower').key, 'tower', 'find')
eq(H.find(HowData, 'nope'), nil, 'find: unknown')
eq(H.forUnlock(HowData, 'rifts').key, 'rift', 'unlock rifts -> rift')
eq(H.forUnlock(HowData, 'events').key, 'invasion', 'unlock events -> invasion')
eq(H.forUnlock(HowData, 'pets').key, 'pets', 'unlock without a hand card gets its own')
eq(H.forGoal(HowData, 'rift6').key, 'rift', 'goal rift6 -> rift')
eq(H.forGoal(HowData, 'pocket10').key, 'bosses', 'goal pocket10 -> bosses')
eq(H.forGoal(HowData, 'lvl300'), nil, 'a level goal has no card')
eq(H.forWindow(HowData, 'game_arena').key, 'arena', 'window arena')
eq(H.forWindow(HowData, 'game_crafting').key, 'crafting', 'window crafting is the first of crafting and salvage')
eq(H.forUnlock(HowData, nil), nil, 'nil unlock')

-- language
eq(H.langKey('pt-BR'), 'pt', 'lang pt-BR')
eq(H.langKey('en'), 'en', 'lang en')
eq(H.langKey(nil), 'en', 'lang nil')
local arena = H.find(HowData, 'arena')
eq(H.title(arena, 'en'), 'Arena', 'title en')
local rowsEn = H.rows(arena, 'en')
local rowsPt = H.rows(arena, 'pt-BR', L.toCp1252)
eq(#rowsEn, #arena.rows, 'rows count')
eq(rowsEn[1].id, 'who', 'first row')
ok(rowsPt[1].text ~= rowsEn[1].text, 'pt row differs')
eq(H.pick({ en = 'a' }, 'pt-BR'), 'a', 'a missing pt falls back to en')
eq(H.pick(nil, 'en'), '', 'pick nil')
eq(H.pick({ en = 'a', pt = 'N\195\173vel' }, 'pt', L.toCp1252), 'N\237vel', 'pt converted to cp1252')

-- the headings the module draws exist in pt-BR
for _, k in ipairs({ 'What it is', 'Who is it for', 'Monster levels', 'What drops', 'If you die', 'How often', 'How it works',
    'Close' }) do
  ok(pt[k] and pt[k] ~= '', 'pt-BR entry for "' .. k .. '"')
end

print(string.format('howcore: %d checks, %d failed', count, fails))
if fails > 0 then os.exit(1) end
