-- Short numbers for everything the client shows: 1000 -> 1k, 15300 -> 15.3k, 2450000 -> 2.45M, 1200000000 -> 1.2B.
-- The rule is the one of chaosShortNumber (base patch 0018, the numbers above the map): three significant
-- digits, trailing zeros dropped, rounded down (999999 is 999k, never 1000k), below 1000 the number is shown
-- as it is, a negative number keeps its sign. Integer arithmetic only, so 1150 is 1.15k and not 1.14k.
-- Globals (this module is not sandboxed and loads before every other one, autoload-priority 10):
--   formatShortNumber(n)  -> '15.3k'
--   formatExactNumber(n)  -> '15,300' (for tooltips that show the exact value)
--   shortNumbersIn(text)  -> the text with every standalone integer >= 1000 shortened (see below)
--   shortNumbersInMessage(mode, text) -> shortNumbersIn for server messages of the modes that carry damage,
--                           healing, experience, loot, look and status; any other mode (chat, private,
--                           NPC talk, broadcasts, login) comes back as it is
-- Pure Lua 5.1/5.3, no client API, so numbers_test.lua (next to this file) runs it with plain luajit and lua5.3.

local floor = math.floor
local UNITS = { '', 'k', 'M', 'B', 'T' }

-- floor(a / b) for non-negative integers that a double holds exactly (< 2^53); corrected, since a / b is rounded
local function idiv(a, b)
  local q = floor(a / b)
  if q * b > a then
    q = q - 1
  elseif (q + 1) * b <= a then
    q = q + 1
  end
  return q
end

local function intString(n)
  return string.format('%d', n)
end

function formatShortNumber(n)
  local value = tonumber(n)
  if not value or value ~= value or value == math.huge or value == -math.huge then
    return tostring(n)
  end
  local sign = ''
  if value < 0 then
    sign = '-'
    value = -value
  end
  if value < 1000 then
    if value == floor(value) then
      return sign .. intString(value)
    end
    return sign .. tostring(value)
  end
  value = floor(value)
  local unit, div = 1, 1
  while unit < #UNITS and idiv(value, div) >= 1000 do
    div = div * 1000
    unit = unit + 1
  end
  local whole = idiv(value, div)
  local decimals = whole >= 100 and 0 or (whole >= 10 and 1 or 2)
  local text
  if decimals == 0 then
    text = intString(whole)
  else
    local factor = decimals == 2 and 100 or 10
    local scaled = idiv(value, div / factor) -- div is a power of 1000, so div / factor is an integer
    local frac = scaled - whole * factor
    text = intString(whole) .. '.' .. string.format('%0' .. decimals .. 'd', frac)
    text = text:gsub('0+$', ''):gsub('%.$', '')
  end
  return sign .. text .. UNITS[unit]
end

function formatExactNumber(n)
  local value = tonumber(n)
  if not value then
    return tostring(n)
  end
  local text = value == floor(value) and intString(value) or tostring(value)
  local k
  repeat
    text, k = text:gsub('^(-?%d+)(%d%d%d)', '%1,%2')
  until k == 0
  return text
end

-- shortNumbersIn: conservative. A number is shortened only when it stands alone. Left as it is:
--   glued to letters, digits, '_', '#', '@' or '\' (ids, colours, '2304a', '#123', 'x1500', '1500gp'),
--   next to ':' (times 02:44:36), a decimal or an already short number (12.5, 1.5k), a list or coordinates
--   without spaces (32369,32241,7), any number of a 'a, b, c' triple (positions), a number after a keyword
--   such as id, uid, aid, x, y, z, pos, position, port, version (with or without ':'), a range or date part
--   ('2026-10-08', '10/08/2026', '1000-2000'), a year 1900..2100 next to a month name or the word 'year',
--   a number with leading zeros, '[1234]', the item id of the loot markup '{3031|gold coin}' / '{3031:500|...}'.
-- Thousands separators are understood: '1,234,567' and '1.234.567' (dots need two groups; '1.234' is left).
local KEYWORDS = {
  id = true, ids = true, uid = true, aid = true, cid = true, sid = true, actionid = true, uniqueid = true,
  itemid = true, clientid = true, serverid = true, x = true, y = true, z = true, pos = true, position = true,
  coord = true, coords = true, coordinates = true, port = true, version = true, ver = true, protocol = true,
  code = true, pin = true, ticket = true, nr = true, serial = true, build = true, opcode = true,
}
local MONTHS = {
  jan = true, feb = true, mar = true, apr = true, may = true, jun = true, jul = true, aug = true, sep = true,
  sept = true, oct = true, nov = true, dec = true, january = true, february = true, march = true, april = true,
  june = true, july = true, august = true, september = true, october = true, november = true, december = true,
  year = true, years = true,
}

local function isWordByte(c)
  return c ~= nil and c ~= '' and (c:find('^[%w_]') ~= nil or c:byte() >= 128)
end

local function isDigit(c)
  return c ~= nil and c ~= '' and c:find('^%d') ~= nil
end

-- the last word before position i (skipping spaces and one ':', '=', '#' or '.')
local function wordBefore(text, i)
  local head = text:sub(math.max(1, i - 40), i - 1)
  head = head:gsub('%s*[:=#%.]?%s*$', '')
  local word = head:match('(%a+)$')
  return word and word:lower() or nil, head
end

local function wordAfter(text, j)
  local word = text:match('^[%s,]*(%a+)', j + 1)
  return word and word:lower() or nil
end

local function looksLikeYear(text, s, e, digits)
  if #digits ~= 4 then
    return false
  end
  local n = tonumber(digits)
  if n < 1900 or n > 2100 then
    return false
  end
  local before, head = wordBefore(text, s)
  if before and MONTHS[before] then
    return true
  end
  -- 'Oct 08, 2026' / '8 October 2026': a day number between the month name and the year
  local monthDay = head:match('(%a+)%s+%d%d?%s*,?$') or head:match('%d%d?%s+(%a+)%s*,?$')
  if monthDay and MONTHS[monthDay:lower()] then
    return true
  end
  local after = wordAfter(text, e)
  return after ~= nil and MONTHS[after] == true and after ~= 'year' and after ~= 'years'
end

-- scans a number starting at s (a digit, the byte before is not a digit); returns its end, the digits only,
-- and whether it may be shortened
local function scanNumber(text, s)
  local _, plainEnd = text:find('^%d+', s)
  local e, digits = plainEnd, text:sub(s, plainEnd)
  if #digits <= 3 then
    for _, sep in ipairs({ ',', '.' }) do
      local pattern = '^%' .. sep .. '%d%d%d'
      local j, groups, collected = plainEnd, 0, digits
      while text:find(pattern, j + 1) and not isDigit(text:sub(j + 5, j + 5)) do
        collected = collected .. text:sub(j + 2, j + 4)
        j = j + 4
        groups = groups + 1
      end
      if groups >= (sep == ',' and 1 or 2) then
        e, digits = j, collected
        break
      end
    end
  end
  return e, digits
end

local function canShorten(text, s, e, digits)
  if #digits < 4 or digits:sub(1, 1) == '0' then
    return false
  end
  local prev, prev2 = text:sub(s - 1, s - 1), text:sub(s - 2, s - 2)
  local nextc, next2 = text:sub(e + 1, e + 1), text:sub(e + 2, e + 2)
  if isWordByte(prev) or prev:find('^[#@\\:%.,/]') then
    return false
  end
  if prev == '-' and (isWordByte(prev2) or prev2:find('^[%-/]')) then
    return false
  end
  if isWordByte(nextc) or nextc:find('^[#@\\|]') then
    return false
  end
  if nextc:find('^[:%.,/%-]') and (isDigit(next2) or isWordByte(next2)) then
    return false
  end
  if prev == '[' and nextc == ']' then
    return false
  end
  local before = wordBefore(text, s)
  if before and KEYWORDS[before] then
    return false
  end
  if looksLikeYear(text, s, e, digits) then
    return false
  end
  return true
end

-- marks the numbers of every 'a, b, c' triple (positions) so that none of them is shortened
local function triplePositions(text)
  local skip = {}
  local init = 1
  while true do
    local s, e = text:find('%d+%s*,%s*%d+%s*,%s*%d+', init)
    if not s then
      break
    end
    -- a grouped number such as '1,234,567' is not a triple: it has no space and groups of three digits
    local chunk = text:sub(s, e)
    if not chunk:find('^%d%d?%d?,%d%d%d,%d%d%d$') then
      for i = s, e do
        skip[i] = true
      end
    end
    init = e + 1
  end
  return skip
end

function shortNumbersIn(text)
  if type(text) ~= 'string' then
    return text
  end
  if not text:find('%d%d%d') then
    return text
  end
  local skip = triplePositions(text)
  local out = {}
  local i, len = 1, #text
  while i <= len do
    local s = text:find('%d', i)
    if not s then
      out[#out + 1] = text:sub(i)
      break
    end
    out[#out + 1] = text:sub(i, s - 1)
    local e, digits = scanNumber(text, s)
    if not skip[s] and canShorten(text, s, e, digits) then
      out[#out + 1] = formatShortNumber(tonumber(digits))
    else
      -- leave the whole run of digits and separators as it is ('1.5k', '32369,32241,7', '1234.56')
      local _, runEnd = text:find('^[%d%.,]*%d', s)
      e = math.max(e, runEnd or e)
      out[#out + 1] = text:sub(s, e)
    end
    i = e + 1
  end
  return table.concat(out)
end

-- message modes whose text is shortened (names of MessageModes in gamelib/const.lua, read when first used)
local SHORT_MESSAGE_MODES = {
  'Look', 'DamageDealed', 'DamageReceived', 'Heal', 'Exp', 'DamageOthers', 'HealOthers', 'ExpOthers',
  'Status', 'Loot', 'TradeNpc', 'Mana', 'Potion',
}
local shortModes = nil

function shortNumbersInMessage(mode, text)
  if type(text) ~= 'string' or type(MessageModes) ~= 'table' then
    return text
  end
  if not shortModes then
    shortModes = {}
    for _, name in ipairs(SHORT_MESSAGE_MODES) do
      if MessageModes[name] then
        shortModes[MessageModes[name]] = true
      end
    end
  end
  if not shortModes[mode] then
    return text
  end
  return shortNumbersIn(text)
end
