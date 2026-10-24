-- luajit codextext_test.lua && lua5.3 codextext_test.lua (CI runs every client module test from the repo root)
-- The Codex in pt-BR: CodexText turns a generated English text into its template (numbers -> %s), looks it up in
-- client_chaos_locale/pt_br.lua through the real ChaosLocaleCore.translate, and gives the numbers back.
-- Also checks the real codex_data.lua: every tab name, filter, option, section heading and column head has an entry
-- (a new heading in the generated data fails here until pt_br.lua has it), and the share of paragraphs and table cells
-- the dictionary covers does not fall.
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'codextext.lua')
dofile(dir .. 'codex_data.lua')
dofile(dir .. '../client_chaos_locale/locale_core.lua')
local pt = dofile(dir .. '../client_chaos_locale/pt_br.lua')
local fails, count = 0, 0
local function eq(a, b, what)
  count = count + 1
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end
local function ok(cond, what) eq(cond and true or false, true, what) end

local C = CodexText
-- the key
do
  local key, nums = C.key('Cap: at most 15% from all equipped items together.')
  eq(key, 'Cap: at most %s%% from all equipped items together.', 'key: number and percent')
  eq(table.concat(nums, '|'), '15', 'key: numbers')
  key, nums = C.key('Salvage gives 4 rune shards and 78 Conquest Tokens. Level 40.')
  eq(key, 'Salvage gives %s rune shards and %s Conquest Tokens. Level %s.', 'key: the dot of a sentence stays')
  eq(table.concat(nums, '|'), '4|78|40', 'key: several numbers')
  key, nums = C.key('x0.75, +10-14% (T8)')
  eq(key, 'x%s, +%s-%s%% (T%s)', 'key: decimals, ranges and tiers')
  eq(table.concat(nums, '|'), '0.75|10|14|8', 'key: decimals as written')
end

-- English: no translation, the text comes back as it was (also with a % in it)
C.trFn = function(s, ...)
  if select('#', ...) > 0 then return string.format(s, ...) end
  return s
end
for _, text in ipairs({'Cap: at most 15% from all equipped items together.', 'Orb of Awakening', 'T1-T8: 2% to 5%.', '100% sure', ''}) do
  eq(C.t(text), text, 'English unchanged: ' .. text)
  eq(C.sub(text), text, 'English sub unchanged: ' .. text)
end
eq(C.t(nil), nil, 'nil')
eq(C.sub('Suffix, any gear. +2% (T1) to +10-14% (T8)'), 'Suffix, any gear. +2% (T1) to +10-14% (T8)', 'English list line')

-- pt-BR through the real translate
local prepared = ChaosLocaleCore.prepare(pt)
C.trFn = function(s, ...) return ChaosLocaleCore.translate(pt, nil, s, ...) end
eq(C.t('Cap: at most 15% from all equipped items together.'), 'Limite: no máximo 15% de todos os itens equipados juntos.', 'pt: cap')
eq(C.t('Armor 16'), 'Armadura 16', 'pt: stat with a number')
eq(C.t('A unique keeps its stats: no orb changes it. Salvage gives 4 rune shards and 78 Conquest Tokens.'),
  'Um unique mantém seus atributos: nenhum orbe o muda. O salvage dá 4 rune shards e 78 Conquest Tokens.', 'pt: two numbers')
eq(C.t('Orb of Awakening'), 'Orb of Awakening', 'pt: a name stays English')
eq(C.t('Some paragraph nobody translated, 5 times.'), 'Some paragraph nobody translated, 5 times.', 'pt: no entry, English')
eq(C.t('Prefix: the monsters or the guardian get stronger.'), 'Prefixo: os monstros ou o guardião ficam mais fortes.', 'pt: prefix')
eq(C.sub('Suffix, any gear. +2% (T1) to +10-14% (T8)'), 'Sufixo, qualquer equipamento. +2% (T1) a +10-14% (T8)', 'pt: list line of a modifier')
eq(C.sub('Prefix, Weapon. +2-4% (T1) to +33-52% (T8)'), 'Prefixo, Arma. +2-4% (T1) a +33-52% (T8)', 'pt: list line, weapon')
eq(C.sub('Shield, level 40. Defense 36, Health on Hit +6, Physical Penetration +18%'),
  'Escudo, nível 40. Defesa 36, Vida por golpe +6, Penetração física +18%', 'pt: list line of a unique')
eq(C.sub('Ring, level 120. Armor 6, Life Leech: chance +10%, amount +8%'),
  'Anel, nível 120. Armadura 6, Roubo de vida: chance +10%, quantidade +8%', 'pt: a stat with its own comma stays one part')
eq(C.sub('Legendary power. Prefix, Weapon, Jewel. 3-5% (T1) to 30-45% (T8)'),
  'Poder lendário. Prefixo, Arma, joia. 3-5% (T1) a 30-45% (T8)', 'pt: three sentences')

-- the real data
local function norm(text)
  return (C.key(text))
end
local function translated(text)
  return pt[norm(text)] ~= nil
end
local kept = {['The Ashen Chronicle'] = true, ['Em português'] = true, ['%s'] = true}
local missing = {}
local function need(text, what)
  if type(text) ~= 'string' or text == '' then return end
  count = count + 1
  if not translated(text) and not kept[norm(text)] then missing[#missing + 1] = what .. ': ' .. text end
end
local prose, prose_ok, cells, cells_ok = 0, 0, 0, 0
local function section(s)
  if s.ref then return end
  need(s.h, 'heading')
  for _, p in ipairs(s.p or {}) do
    prose = prose + 1
    if translated(p) then prose_ok = prose_ok + 1 end
  end
  for _, c in ipairs(s.cols or {}) do need(c, 'column') end
  for _, row in ipairs(s.rows or {}) do
    for i = 1, #row do
      cells = cells + 1
      if translated(row[i]) then cells_ok = cells_ok + 1 end
    end
  end
end
for _, s in pairs(CodexData.shared) do section(s) end
for _, tab in ipairs(CodexData.tabs) do
  need(tab.name, 'tab')
  for _, f in ipairs(tab.filters or {}) do
    need(f.label, 'filter')
    for _, o in ipairs(f.options or {}) do need(o[2], 'option') end
  end
  for _, e in ipairs(tab.entries) do
    for _, s in ipairs(e.sections or {}) do section(s) end
  end
end
for i = 1, math.min(#missing, 20) do print('no pt-BR entry for ' .. missing[i]) end
eq(#missing, 0, 'every tab, filter, option, heading and column head of the data has a pt-BR entry')
ok(prose > 1000 and cells > 5000, 'the data has the expected size: ' .. prose .. ' paragraphs, ' .. cells .. ' cells')
ok(prose_ok / prose >= 0.70, 'paragraphs translated: ' .. prose_ok .. ' of ' .. prose)
ok(cells_ok / cells >= 0.40, 'table cells translated: ' .. cells_ok .. ' of ' .. cells .. ' (the rest are names)')

if fails > 0 then print(fails .. ' of ' .. count .. ' FAILED'); os.exit(1) end
print('codextext_test: ' .. count .. ' checks passed (paragraphs ' .. prose_ok .. '/' .. prose .. ', cells ' .. cells_ok .. '/' .. cells .. ')')
