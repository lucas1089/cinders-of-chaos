-- luajit locale_core_test.lua && lua5.3 locale_core_test.lua (from the repo root or this folder)
-- The client language (locale_core.lua): names, the first-run choice from the system's locale, UTF-8 -> cp1252, the
-- lookup with the base client's tr behind it and English last, formats, the hello for the server; and the pt-BR table
-- (pt_br.lua): every value in cp1252 range, the same % conversions in the same order as its key.
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'locale_core.lua')
dofile(dir .. 'pt_br.lua')
local L = ChaosLocaleCore

local fails, checks = 0, 0
local function eq(a, b, what)
  checks = checks + 1
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end
local function ok(v, what) eq(not not v, true, what) end

-- names
eq(L.normalize('pt-BR'), 'pt-BR', 'pt-BR') eq(L.normalize('pt_br'), 'pt-BR', 'pt_br') eq(L.normalize('PT'), 'pt-BR', 'pt')
eq(L.normalize('Portuguese_Brazil'), 'pt-BR', 'Windows name') eq(L.normalize('en_US'), 'en', 'en_US')
eq(L.normalize('de'), nil, 'unknown') eq(L.normalize(nil), nil, 'nil')

-- the first run
eq(L.fromSystem({ 'pt_BR.UTF-8' }), 'pt-BR', 'LANG pt_BR.UTF-8')
eq(L.fromSystem({ '', 'Portuguese_Brazil.1252' }), 'pt-BR', 'the C locale name on Windows')
eq(L.fromSystem({ 'pt_PT.UTF-8' }), 'pt-BR', 'any Portuguese')
eq(L.fromSystem({ 'C', 'en_US.UTF-8' }), 'en', 'C is skipped')
eq(L.fromSystem({ 'pt_BR:en' }), 'pt-BR', 'a LANGUAGE list')
eq(L.fromSystem({ 'de_DE.UTF-8' }), nil, 'another language: none')
eq(L.fromSystem({}), nil, 'nothing')
eq(L.choose('en', { 'pt_BR.UTF-8' }), 'en', 'a saved choice wins')
eq(L.choose(nil, { 'pt_BR.UTF-8' }), 'pt-BR', 'first run in Portuguese')
eq(L.choose(nil, { 'C' }), 'en', 'first run elsewhere: English')
eq(L.choose('xx', {}), 'en', 'a bad saved value: English')

-- UTF-8 -> cp1252
eq(L.toCp1252('Op\195\167\195\181es'), 'Op\231\245es', 'ç õ')
eq(L.toCp1252('\226\130\172 \226\128\148 \226\128\166'), '\128 \151 \133', '€ — …')
eq(L.toCp1252('plain'), 'plain', 'ASCII')
eq(L.toCp1252('\231a'), '\231a', 'not UTF-8: as it is')
eq(L.toCp1252('\228\184\173'), '?', 'outside cp1252: ?')

-- the lookup
local t = L.prepare({ ['Close'] = 'Fechar', ['Level %d'] = 'N\195\173vel %d', ['%s of %s'] = '%s de %s' })
eq(L.translate(t, nil, 'Close'), 'Fechar', 'found')
eq(L.translate(t, nil, 'Level %d', 5), 'N\237vel 5', 'found, formatted, cp1252')
eq(L.translate(t, nil, 'Missing %d', 5), 'Missing 5', 'missing: English, formatted')
eq(L.translate(t, nil, '100%'), '100%', 'no arguments: no format')
eq(L.translate(nil, nil, 'Level %d', 7), 'Level 7', 'English')
local base = function(text, ...) if text == 'Options' then return 'Op\231\245es' end return string.format(text, ...) end
eq(L.translate(t, base, 'Options'), 'Op\231\245es', 'the base client translates what the table lacks')
eq(L.translate(t, base, 'Close'), 'Fechar', 'the table first')
local broken = function() error('boom') end
eq(L.translate(t, broken, 'Missing'), 'Missing', 'a failing base tr: English')
eq(L.translate(t, nil, 'Level %d', 'x'), 'Level %d', 'a bad argument: the pattern, no error')
eq(L.translate(t, base, 12), '12', 'a number goes to the base')

-- the hello
local h = L.hello('pt_BR')
eq(h.action, 'hello', 'hello') eq(h.lang, 'pt-BR', 'its language')
eq(L.hello('xx').lang, 'en', 'unknown: en')

-- the pt-BR table
local FMT = '%%[-+#0]*%d*%.?%d*([diouxXeEfgGqsaAc])'
local function formats(s)
  local out = {}
  for c in s:gsub('%%%%', ''):gmatch(FMT) do out[#out + 1] = c end
  return table.concat(out, ',')
end
local pt = ChaosLocaleStrings['pt-BR']
local n = 0
for k, v in pairs(pt) do
  n = n + 1
  ok(type(v) == 'string' and v ~= '', 'a value for ' .. k)
  eq(formats(v), formats(k), 'the % conversions of ' .. k)
  local c = L.toCp1252(v)
  ok(not c:find('?', 1, true) or v:find('?', 1, true), 'every character drawable in cp1252: ' .. k)
end
ok(n > 2000, 'the table has its entries (' .. n .. ')')
eq(L.translate(L.prepare(pt), nil, 'Close'), 'Fechar', 'Close')

if fails > 0 then error(string.format('locale_core_test: %d of %d checks failed', fails, checks)) end
print('locale_core_test: ok (' .. checks .. ' checks)')
