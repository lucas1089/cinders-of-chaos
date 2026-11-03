-- Pure helpers of the new player survey window (no client API), tested by surveylogic_test.lua.
-- Server: server/data/scripts/chaos/survey.lua (opcode 122); TEXT_MAX equals survey_config.lua textMax
-- (server/tests/survey_test.lua checks it).
SurveyLogic = {}
local L = SurveyLogic

L.TEXT_MAX = 200
L.STAGES = { 20, 50 }

-- The engine's text edits hold cp1252 (one byte a letter; client_chaos_locale locale_core.lua): the edit's max-length
-- is the letter limit, and the text is turned into UTF-8 before it is sent (the server keeps UTF-8).
local CP = { [0x80] = 0x20AC, [0x82] = 0x201A, [0x83] = 0x0192, [0x84] = 0x201E, [0x85] = 0x2026, [0x86] = 0x2020,
  [0x87] = 0x2021, [0x88] = 0x02C6, [0x89] = 0x2030, [0x8A] = 0x0160, [0x8B] = 0x2039, [0x8C] = 0x0152, [0x8E] = 0x017D,
  [0x91] = 0x2018, [0x92] = 0x2019, [0x93] = 0x201C, [0x94] = 0x201D, [0x95] = 0x2022, [0x96] = 0x2013, [0x97] = 0x2014,
  [0x98] = 0x02DC, [0x99] = 0x2122, [0x9A] = 0x0161, [0x9B] = 0x203A, [0x9C] = 0x0153, [0x9E] = 0x017E, [0x9F] = 0x0178 }

local function utf8char(cp)
  if cp < 0x80 then return string.char(cp) end
  if cp < 0x800 then return string.char(0xC0 + math.floor(cp / 64), 0x80 + cp % 64) end
  return string.char(0xE0 + math.floor(cp / 4096), 0x80 + math.floor(cp / 64) % 64, 0x80 + cp % 64)
end

-- cp1252 -> UTF-8 (the 5 bytes cp1252 leaves undefined are dropped)
function L.toUtf8(s)
  return (tostring(s or ''):gsub('[\128-\255]', function(c)
    local b = c:byte()
    if b < 0xA0 and not CP[b] then return '' end
    return utf8char(CP[b] or b)
  end))
end

-- the text cut to `max` letters (cp1252: one byte a letter)
function L.cut(text, max)
  if type(text) ~= 'string' then return '' end
  return text:sub(1, max or L.TEXT_MAX)
end

-- one line, spaces folded and trimmed
function L.tidy(text)
  if type(text) ~= 'string' then return '' end
  text = text:gsub('[%c]', ' '):gsub(' +', ' ')
  return (text:gsub('^ ', ''):gsub(' $', ''))
end

-- the open message: {stage, max} or nil
function L.parseOpen(data)
  if type(data) ~= 'table' then return nil end
  local s = tonumber(data.s)
  local known = false
  for _, st in ipairs(L.STAGES) do
    if st == s then known = true end
  end
  if not known then return nil end
  local max = tonumber(data.max) or L.TEXT_MAX
  if max < 1 or max > L.TEXT_MAX then max = L.TEXT_MAX end
  return { stage = s, max = math.floor(max) }
end

-- the answer the server reads; fun 1..5 or nil, rec true / false / nil
function L.answer(stage, fun, rec, text, max)
  local data = { s = stage }
  if type(fun) == 'number' and fun >= 1 and fun <= 5 then data.fun = math.floor(fun) end
  if rec == true or rec == false then data.rec = rec end
  local t = L.toUtf8(L.cut(L.tidy(text), max or L.TEXT_MAX))
  if t ~= '' then data.text = t end
  return { action = 'answer', data = data }
end

function L.skip(stage)
  return { action = 'skip', data = { s = stage } }
end

-- the Send button: something was given
function L.canSend(fun, rec, text)
  return (type(fun) == 'number' and fun >= 1 and fun <= 5) or rec == true or rec == false or L.tidy(text) ~= ''
end

function L.counter(text, max)
  return string.format('%d/%d', type(text) == 'string' and #text or 0, max or L.TEXT_MAX)
end
