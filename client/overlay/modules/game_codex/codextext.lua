-- The Codex texts in the player's language (no client API, tested by codextext_test.lua).
-- codex_data.lua is generated English (server/tools/gen_codex_data.lua) and full of numbers that change with the server's
-- data, so a text is looked up with its numbers taken out: every number of the text becomes %s and every % becomes %%,
-- the result is the key given to tr() (pt_br.lua, "Codex") and the numbers are its arguments:
--   "Cap: at most 15% from all equipped items together."  ->  tr("Cap: at most %s%% from all equipped items together.", "15")
-- A text without an entry comes back as it was (English): names of items, orbs, monsters and uniques, and the long
-- one-off paragraphs, stay English.
--   CodexText.key(text)            key, {numbers as written}
--   CodexText.t(text)              the text in the client's language
--   CodexText.sub(text)            a list line ("Suffix, any gear. +2% (T1) to +10-14% (T8)"): its comma separated parts
--                                  one by one (the parts of a stat with its own comma, "Critical Hit: chance +5%, damage
--                                  +25%", as one), the numbers kept
--   CodexText.trFn                 the tr function to use (default: the global tr; the test sets its own)
local unpack = unpack or table.unpack

CodexText = {}
local C = CodexText

local function globalTr(s, ...)
  local g = rawget(_G, 'tr')
  if g then return g(s, ...) end
  if select('#', ...) > 0 then return string.format(s, ...) end
  return s
end

function C.key(text)
  local nums = {}
  local key = tostring(text):gsub('%%', '%%%%'):gsub('%d+%.?%d*', function(n)
    -- a number ends before the dot of a sentence ("level 40." -> 40, then the dot)
    local dot = ''
    if n:sub(-1) == '.' then n, dot = n:sub(1, -2), '.' end
    nums[#nums + 1] = n
    return '%s' .. dot
  end)
  return key, nums
end

-- the text in the language, and whether it has an entry
local function lookup(text)
  local fn = C.trFn or globalTr
  local key, nums = C.key(text)
  local shown = fn(key, unpack(nums))
  local plain = (#nums > 0) and string.format(key, unpack(nums)) or key
  if type(shown) ~= 'string' then return text, false end
  return shown, shown ~= plain
end

function C.t(text)
  if type(text) ~= 'string' or text == '' then return text end
  local shown = lookup(text)
  return shown
end

-- the parts of a comma separated list, longest known span first (up to 4 parts)
local function parts(text)
  local list = {}
  for piece in (text .. ', '):gmatch('(.-), ') do list[#list + 1] = piece end
  local out, i = {}, 1
  while i <= #list do
    local used, shown = 1, nil
    for span = math.min(4, #list - i + 1), 1, -1 do
      local candidate = table.concat(list, ', ', i, i + span - 1)
      local s, found = lookup(candidate)
      if found then used, shown = span, s break end
    end
    out[#out + 1] = shown or list[i]
    i = i + used
  end
  return table.concat(out, ', ')
end

function C.sub(text)
  if type(text) ~= 'string' or text == '' then return text end
  local whole, found = lookup(text)
  if found then return whole end
  local sentences = {}
  local body = text:gsub('%.$', '')
  for sentence in (body .. '. '):gmatch('(.-)%. ') do sentences[#sentences + 1] = sentence end
  for i, sentence in ipairs(sentences) do
    local shown = parts(sentence)
    -- "+2% (T1) to +10% (T8)": the word between the two ends of the range
    shown = shown:gsub(' %(T(%d+)%) to ', function(n) return C.t(' (T' .. n .. ') to ') end)
    sentences[i] = shown
  end
  local out = table.concat(sentences, '. ')
  if text:sub(-1) == '.' then return out .. '.' end
  return out
end

return C
