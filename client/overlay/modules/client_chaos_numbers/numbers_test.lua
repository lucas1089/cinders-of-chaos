-- Self test of numbers.lua (no client needed). Run from the repository root (CI runs it with luajit and lua5.3):
--   luajit client/overlay/modules/client_chaos_numbers/numbers_test.lua
local here = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(here .. 'numbers.lua')

local failures, checks = 0, 0
local function eq(got, want, what)
  checks = checks + 1
  if got ~= want then
    failures = failures + 1
    print(string.format('FAIL %s: got %q, want %q', what, tostring(got), tostring(want)))
  end
end

-- formatShortNumber: the rule of chaosShortNumber (base patch 0018)
local short = {
  { 0, '0' }, { 7, '7' }, { 999, '999' }, { 1000, '1k' }, { 1001, '1k' }, { 1010, '1.01k' }, { 1100, '1.1k' },
  { 1150, '1.15k' }, { 1999, '1.99k' }, { 2010, '2.01k' }, { 4100, '4.1k' }, { 9999, '9.99k' },
  { 10000, '10k' }, { 15300, '15.3k' }, { 15350, '15.3k' }, { 99999, '99.9k' }, { 100000, '100k' },
  { 123456, '123k' }, { 999999, '999k' }, { 1000000, '1M' }, { 2450000, '2.45M' }, { 2459999, '2.45M' },
  { 12345678, '12.3M' }, { 999999999, '999M' }, { 1200000000, '1.2B' }, { 1000000000000, '1T' },
  { 1500000000000000, '1500T' }, { -1500, '-1.5k' }, { -999, '-999' }, { -2450000, '-2.45M' },
  { '15300', '15.3k' }, { 1234.9, '1.23k' }, { 12.5, '12.5' },
}
for _, c in ipairs(short) do
  eq(formatShortNumber(c[1]), c[2], 'formatShortNumber(' .. tostring(c[1]) .. ')')
end
-- the display scale's range (server/README.md "Display scale"): a level-1000 median DPS of about 2600 x 1000, a
-- big hit, the uint32 packet limit, a boss's health x the cap, a session total near 2^53
local scaled = {
  { 2598000, '2.59M' }, { 2600000, '2.6M' }, { 46416000, '46.4M' }, { 128000000, '128M' }, { 4294967295, '4.29B' },
  { 1000000000000, '1T' }, { 999999999999, '999B' }, { 9007199254740992, '9007T' },
}
for _, c in ipairs(scaled) do
  eq(formatShortNumber(c[1]), c[2], 'scaled formatShortNumber(' .. tostring(c[1]) .. ')')
end
eq(shortNumbersIn('A dragon loses 2600000 hitpoints due to your attack.'), 'A dragon loses 2.6M hitpoints due to your attack.',
  'a scaled damage message')
eq(shortNumbersIn('You lose 4294967295 hitpoints.'), 'You lose 4.29B hitpoints.', 'the uint32 limit in a message')
eq(formatShortNumber(nil), 'nil', 'formatShortNumber(nil)')
eq(formatShortNumber('abc'), 'abc', 'formatShortNumber(abc)')

-- the same result as an integer reference for every number up to 3 million (the C++ uses doubles)
local function reference(v)
  local units, u, div = { '', 'k', 'M', 'B', 'T' }, 1, 1
  while u < 5 and math.floor(v / div) >= 1000 do div = div * 1000; u = u + 1 end
  local whole = math.floor(v / div)
  if whole >= 100 or div == 1 then return string.format('%d', whole) .. units[u] end
  local f = whole >= 10 and 10 or 100
  local q = math.floor(v * f / div) % f
  local text = string.format('%d.%0' .. (f == 10 and 1 or 2) .. 'd', whole, q):gsub('0+$', ''):gsub('%.$', '')
  return text .. units[u]
end
local mismatches = 0
for v = 1000, 3000000, 7 do
  if formatShortNumber(v) ~= reference(v) then
    mismatches = mismatches + 1
    if mismatches < 5 then print('FAIL reference ' .. v .. ': ' .. formatShortNumber(v) .. ' vs ' .. reference(v)) end
  end
end
checks = checks + 1
if mismatches > 0 then failures = failures + 1 end

eq(formatExactNumber(15300), '15,300', 'formatExactNumber(15300)')
eq(formatExactNumber(-1234567), '-1,234,567', 'formatExactNumber(-1234567)')
eq(formatExactNumber(999), '999', 'formatExactNumber(999)')

-- shortNumbersIn
local texts = {
  { 'You gained 15300 experience points.', 'You gained 15.3k experience points.' },
  { 'A dragon loses 1500 hitpoints due to your attack.', 'A dragon loses 1.5k hitpoints due to your attack.' },
  { 'Loot of a dragon: 1250 gold coins, a dragon ham', 'Loot of a dragon: 1.25k gold coins, a dragon ham' },
  { 'Your balance is 1,234,567 gold.', 'Your balance is 1.23M gold.' },
  { 'Your balance is 1.234.567 gold.', 'Your balance is 1.23M gold.' },
  { 'You heal 999 hitpoints.', 'You heal 999 hitpoints.' },
  { 'Damage: 2450000, healing: 1000', 'Damage: 2.45M, healing: 1k' },
  { 'You lose -1500 health', 'You lose -1.5k health' },
  { '(1500)', '(1.5k)' },
  { '1500/2000', '1500/2000' },
  { 'Server time 02:44:36', 'Server time 02:44:36' },
  { 'Saved on 2026-10-08 at 12:00', 'Saved on 2026-10-08 at 12:00' },
  { 'Saved on 08/10/2026', 'Saved on 08/10/2026' },
  { 'Oct 08 2026', 'Oct 08 2026' },
  { 'Oct 08, 2026', 'Oct 08, 2026' },
  { '8 October 2026', '8 October 2026' },
  { 'in the year 2026', 'in the year 2026' },
  { 'You gained 2000 gold.', 'You gained 2k gold.' },
  { 'You see a sword (id 2304).', 'You see a sword (id 2304).' },
  { 'Item ID: 3366, Position: 32369, 32241, 7', 'Item ID: 3366, Position: 32369, 32241, 7' },
  { 'at 32369,32241,7', 'at 32369,32241,7' },
  { 'x: 1000 y: 1000 z: 7', 'x: 1000 y: 1000 z: 7' },
  { 'order #1234', 'order #1234' },
  { 'item2304 and 2304a', 'item2304 and 2304a' },
  { 'costs 1500gp', 'costs 1500gp' },
  { 'already 1.5k and 15k', 'already 1.5k and 15k' },
  { 'It weighs 1234.50 oz.', 'It weighs 1234.50 oz.' },
  { 'color #ff1234', 'color #ff1234' },
  { 'code 01234', 'code 01234' },
  { '[1234]', '[1234]' },
  { 'range 1000-2000', 'range 1000-2000' },
  { '12345678901', '12.3B' },
  { 'no digits here', 'no digits here' },
  { '', '' },
  { 'Loot of a dragon: {3031:1500|1500 gold coins}, {3577|a meat}', 'Loot of a dragon: {3031:1500|1.5k gold coins}, {3577|a meat}' },
}
for _, c in ipairs(texts) do
  eq(shortNumbersIn(c[1]), c[2], 'shortNumbersIn(' .. c[1] .. ')')
end
eq(shortNumbersIn(nil), nil, 'shortNumbersIn(nil)')
eq(shortNumbersIn(1500), 1500, 'shortNumbersIn(number)')

-- shortNumbersInMessage: only the modes that carry damage, healing, experience, loot, look and status
eq(shortNumbersInMessage(24, 'You gained 15300 experience points.'), 'You gained 15300 experience points.',
  'shortNumbersInMessage without MessageModes')
MessageModes = { Say = 1, PrivateFrom = 4, Login = 16, Look = 20, Exp = 24, Status = 28, Loot = 29 }
eq(shortNumbersInMessage(24, 'You gained 15300 experience points.'), 'You gained 15.3k experience points.', 'Exp')
eq(shortNumbersInMessage(29, 'Loot of a rat: 1500 gold coins'), 'Loot of a rat: 1.5k gold coins', 'Loot')
eq(shortNumbersInMessage(4, 'sell me 1500 gold'), 'sell me 1500 gold', 'PrivateFrom')
eq(shortNumbersInMessage(1, 'I have 1500 hp'), 'I have 1500 hp', 'Say')
eq(shortNumbersInMessage(16, 'Your last visit was on 08 Oct 2026 02:44:36.'), 'Your last visit was on 08 Oct 2026 02:44:36.', 'Login')

-- O506: comma_value (the base client's one, corelib util.lua) and formatExactNumber in the number form of the language
local function baseCommaValue(amount) -- the base client's function, copied: English must stay as it was, byte for byte
  local formatted = tostring(amount or 0)
  while true do
    local k
    formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", '%1,%2')
    if k == 0 then break end
  end
  return formatted
end
local samples = { 0, 7, 999, 1000, 1234, 12345, 123456, 1234567, 1234567890, -5, -1234, -1234567, 15300, 1234.5, '1234', '12345678',
  'abc', '12 gold', '1234 gold', '', '-', '99999999999' }
for _, v in ipairs(samples) do
  eq(comma_value(v), baseCommaValue(v), 'English comma_value ' .. tostring(v) .. ' as the base client has it')
end
eq(comma_value(nil), '0', 'comma_value(nil)')
eq(comma_value(), baseCommaValue(), 'comma_value()')
dofile(here .. '../client_chaos_locale/locale_core.lua')
local lang = 'en'
ChaosLocale = { localize = function(text) return ChaosLocaleCore.localize(text, lang) end }
for _, v in ipairs(samples) do
  eq(comma_value(v), baseCommaValue(v), 'comma_value with ChaosLocale in English ' .. tostring(v))
end
lang = 'pt-BR'
eq(comma_value(3300), '3.300', 'pt-BR 3300') eq(comma_value(999), '999', 'pt-BR 999') eq(comma_value(1000), '1.000', 'pt-BR 1000')
eq(comma_value(1234567), '1.234.567', 'pt-BR 1234567') eq(comma_value(-1234567), '-1.234.567', 'pt-BR negative')
eq(comma_value(1234.5), '1.234,5', 'pt-BR with decimals') eq(comma_value('1234'), '1.234', 'pt-BR text of digits')
eq(comma_value('1234 gold'), '1,234 gold', 'a text with a unit is left as the English form') eq(comma_value('abc'), 'abc', 'not a number')
eq(comma_value(nil), '0', 'pt-BR nil')
eq(formatExactNumber(15300), '15.300', 'pt-BR formatExactNumber') eq(formatExactNumber(-1234567), '-1.234.567', 'pt-BR formatExactNumber negative')
eq(formatExactNumber(999), '999', 'pt-BR formatExactNumber 999') eq(formatExactNumber(1.5), '1,5', 'pt-BR formatExactNumber decimal')
eq(formatExactNumber('x'), 'x', 'pt-BR formatExactNumber text')
-- the short numbers are not language dependent here (the numbers above the map are drawn by the engine, base patch 0018)
eq(formatShortNumber(15300), '15.3k', 'pt-BR short numbers unchanged')
-- the text rule reads the grouped pt-BR number back as one number
eq(shortNumbersIn('You have 1.234.567 gold'), 'You have 1.23M gold', 'shortNumbersIn reads 1.234.567')
lang = 'en'
eq(formatExactNumber(15300), '15,300', 'English again')
ChaosLocale = nil
eq(comma_value(3300), '3,300', 'no ChaosLocale: English')

print(string.format('numbers test: %d checks, %d failed', checks, failures))
if failures > 0 then
  os.exit(1)
end
