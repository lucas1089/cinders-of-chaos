-- Pure helpers of the Leaderboards board dropdown (no client API), tested by boardpick_test.lua.
-- The boards of the meta as dropdown options, sorted by the name shown (the translated one), and the board each
-- character last chose (g_settings node BoardPick.SETTINGS: lower-case character name -> board key).
BoardPick = {}

BoardPick.DEFAULT = 'worldboss'
BoardPick.SETTINGS = 'leaderboardBoard'

-- the base letter of each code point U+00C0..U+00FF (Latin-1: the pt-BR accents), lower case
local BASE = {
  'a', 'a', 'a', 'a', 'a', 'a', 'ae', 'c', 'e', 'e', 'e', 'e', 'i', 'i', 'i', 'i',
  'd', 'n', 'o', 'o', 'o', 'o', 'o', 'x', 'o', 'u', 'u', 'u', 'u', 'y', 'th', 'ss',
  'a', 'a', 'a', 'a', 'a', 'a', 'ae', 'c', 'e', 'e', 'e', 'e', 'i', 'i', 'i', 'i',
  'd', 'n', 'o', 'o', 'o', 'o', 'o', '/', 'o', 'u', 'u', 'u', 'u', 'y', 'th', 'y',
}

-- the sort form of a name: accents folded to their base letter, lower case. Takes UTF-8 and cp1252 / Latin-1 (the
-- client's tr() gives cp1252), so "Ç" sorts with "c" and "É" with "e" in either.
function BoardPick.fold(s)
  s = tostring(s or '')
  s = s:gsub('\195([\128-\191])', function(c) return BASE[c:byte() - 127] end)
  s = s:gsub('[\192-\255]', function(c) return BASE[c:byte() - 191] end)
  return s:lower()
end

-- a < b by the folded name; ties by the exact text
function BoardPick.less(a, b)
  local fa, fb = BoardPick.fold(a), BoardPick.fold(b)
  if fa ~= fb then return fa < fb end
  return tostring(a) < tostring(b)
end

-- boards: the meta's list ({key, name, ...}). translate: the name as shown (tr), default as is. Returns
-- { {key, text, board}, ... } sorted by text; an entry that is no table or has no key is left out.
function BoardPick.options(boards, translate)
  local out = {}
  for _, b in ipairs(type(boards) == 'table' and boards or {}) do
    if type(b) == 'table' and (type(b.key) == 'string' or type(b.key) == 'number') then
      local name = b.name ~= nil and tostring(b.name) or tostring(b.key)
      local text = translate and translate(name) or name
      out[#out + 1] = { key = b.key, text = tostring(text or name), board = b }
    end
  end
  table.sort(out, function(x, y)
    if x.text ~= y.text then return BoardPick.less(x.text, y.text) end
    return tostring(x.key) < tostring(y.key)
  end)
  return out
end

local function has(options, key)
  if key == nil then return false end
  for _, o in ipairs(options or {}) do
    if o.key == key or tostring(o.key) == tostring(key) then return o.key end
  end
  return false
end

-- the board to show: wanted when it is an option, else the default (World Boss), else the first option, else nil
function BoardPick.resolve(options, wanted, default)
  return has(options, wanted) or has(options, default or BoardPick.DEFAULT) or (options and options[1] and options[1].key) or nil
end

-- the settings key of a character: its name in lower case, trimmed; nil without a name
function BoardPick.charKey(name)
  if type(name) ~= 'string' then return nil end
  name = name:gsub('^%s+', ''):gsub('%s+$', ''):lower()
  if name == '' then return nil end
  return name
end

-- the board a character chose last (node: the g_settings node), or nil
function BoardPick.saved(node, charName)
  local k = BoardPick.charKey(charName)
  local v = k and type(node) == 'table' and node[k] or nil
  if type(v) == 'string' and v ~= '' then return v end
  return nil
end

-- the node with the character's board set (a copy; the node is left as it was)
function BoardPick.remember(node, charName, key)
  local out = {}
  if type(node) == 'table' then
    for k, v in pairs(node) do out[k] = v end
  end
  local k = BoardPick.charKey(charName)
  if k and key ~= nil then out[k] = tostring(key) end
  return out
end
