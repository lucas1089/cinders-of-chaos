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
eq(L.upper(L.toCp1252('Aperte qualquer tecla para come\195\167ar')), 'APERTE QUALQUER TECLA PARA COME\199AR', 'upper: c cedilla')
eq(L.upper('\225\224\226\227\233\234\237\243\244\245\250\252\231'), '\193\192\194\195\201\202\205\211\212\213\218\220\199', 'upper: pt-BR accents')
eq(L.upper('\247\215 1-2 \154\156\158\255 \223'), '\247\215 1-2 \138\140\142\159 \223', 'upper: division sign, carons, sharp s')
eq(L.upper(nil), nil, 'upper: not a string')
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

-- numbers (O506): pt-BR groups thousands with a point and writes decimals with a comma, English as before
local NUM = {
  { 0, '0', '0' }, { 999, '999', '999' }, { 1000, '1,000', '1.000' }, { 1234567, '1,234,567', '1.234.567' },
  { -5, '-5', '-5' }, { -1234, '-1,234', '-1.234' }, { -1234567, '-1,234,567', '-1.234.567' }, { -999, '-999', '-999' },
  { 1.5, '1.5', '1,5' }, { 12.25, '12.25', '12,25' }, { 0.5, '0.5', '0,5' }, { 1234.5, '1,234.5', '1.234,5' },
  { -1234.75, '-1,234.75', '-1.234,75' }, { 100000, '100,000', '100.000' }, { 123456789012, '123,456,789,012', '123.456.789.012' },
  { '1234', '1,234', '1.234' }, { '-1234.5', '-1,234.5', '-1.234,5' }, { '12.25', '12.25', '12,25' },
}
for _, c in ipairs(NUM) do
  eq(L.formatNumber(c[1], 'en'), c[2], 'formatNumber en ' .. tostring(c[1]))
  eq(L.formatNumber(c[1], 'pt-BR'), c[3], 'formatNumber pt-BR ' .. tostring(c[1]))
  eq(L.formatNumber(c[1], 'pt_br'), c[3], 'formatNumber pt_br ' .. tostring(c[1]))
  eq(L.formatNumber(c[1], nil), c[2], 'no language is English ' .. tostring(c[1]))
  eq(L.formatNumber(c[1], 'xx'), c[2], 'an unknown language is English ' .. tostring(c[1]))
end
for _, v in ipairs({ 'abc', '', '12 gold', '1e5', '1,234', '1.2.3', '2026-10-08', '12:30', '-', '0x10', ' 5' }) do
  eq(L.formatNumber(v, 'pt-BR'), v, 'a text that is not a number comes back unchanged: ' .. v)
  eq(L.formatNumber(v, 'en'), v, 'and in English: ' .. v)
end
eq(L.formatNumber(nil, 'pt-BR'), nil, 'nil') eq(L.formatNumber(true, 'pt-BR'), true, 'a boolean')
local tbl = {}
eq(L.formatNumber(tbl, 'pt-BR'), tbl, 'a table')
ok(L.formatNumber(0 / 0, 'pt-BR') ~= L.formatNumber(0 / 0, 'pt-BR'), 'NaN is NaN') eq(L.formatNumber(math.huge, 'pt-BR'), math.huge, 'infinity')
eq(L.formatNumber(1e20, 'pt-BR'), 1e20, 'a number too big for a plain text')
eq(L.formatInteger(1234.9, 'pt-BR'), '1.234', 'formatInteger rounds down') eq(L.formatInteger(1234.9, 'en'), '1,234', 'formatInteger en')
eq(L.formatInteger(-0.5, 'en'), '-1', 'formatInteger of a negative fraction rounds down') eq(L.formatInteger('1500', 'pt-BR'), '1.500', 'formatInteger text')
eq(L.formatInteger('abc', 'pt-BR'), 'abc', 'formatInteger of a text') eq(L.formatInteger(nil, 'pt-BR'), nil, 'formatInteger nil')
-- localize: the English form of the client's own texts, separators swapped, nothing grouped or rounded
local LOC = {
  { '3,300', '3.300' }, { '1,234,567', '1.234.567' }, { '-1,234', '-1.234' }, { '1.5', '1,5' }, { '12.25', '12,25' },
  { '1,234.5', '1.234,5' }, { '3300', '3300' }, { '0', '0' }, { '999', '999' }, { '0.33', '0,33' },
  { '1,23', '1,23' }, { '1,2345', '1,2345' }, { '1.2.3', '1.2.3' }, { '12,345,67', '12,345,67' }, { ',123', ',123' }, { '1,234,', '1,234,' },
  { '2026-10-08', '2026-10-08' }, { '02:44:36', '02:44:36' }, { '1-2', '1-2' }, { '~3,300', '~3,300' }, { '3,300 gold', '3,300 gold' },
  { '1.5%', '1.5%' }, { 'abc', 'abc' }, { '', '' }, { '12 000', '12 000' }, { '1e5', '1e5' },
}
for _, c in ipairs(LOC) do
  eq(L.localize(c[1], 'pt-BR'), c[2], 'localize pt-BR ' .. c[1])
  eq(L.localize(c[1], 'en'), c[1], 'localize en keeps ' .. c[1])
  eq(L.localize(c[1], nil), c[1], 'localize without a language keeps ' .. c[1])
end
eq(L.localize(nil, 'pt-BR'), nil, 'localize nil') eq(L.localize(15, 'pt-BR'), 15, 'localize of a number is the number')
eq(L.separators('pt-BR').group, '.', 'pt-BR groups with a point') eq(L.separators('pt-BR').decimal, ',', 'pt-BR decimal comma')
eq(L.separators('en').group, ',', 'en groups with a comma') eq(L.separators(nil).decimal, '.', 'default decimal point')

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
