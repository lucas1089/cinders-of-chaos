-- Client language, the pure part (no client API; locale_core_test.lua runs it with plain luajit and lua5.3).
-- client/MANIFEST.md "Localization".
--
-- Languages: 'en' (the keys themselves) and 'pt-BR' (pt_br.lua). tr(text, ...) looks the text up in the table of the
-- chosen language, else asks the base client's own tr (its locale files translate the base windows), else keeps the
-- English; with arguments the result is string.format(found, ...). The table's values are UTF-8 in pt_br.lua and
-- become cp1252 here (the client's fonts draw cp1252 bytes, client/MANIFEST.md "OFL fonts").
-- First run: pt-BR when the system's locale is Portuguese (LANG / LC_ALL / LC_MESSAGES / LANGUAGE, or the C locale
-- name: "pt_BR.UTF-8", "Portuguese_Brazil.1252"), else English.

ChaosLocaleCore = ChaosLocaleCore or {}
local L = ChaosLocaleCore

L.LANGS = { 'pt-BR', 'en' }
L.NAMES = { ['pt-BR'] = 'Portugu\234s (Brasil)', en = 'English' }
-- the base client's locale names (client_locales) that match ours, tried in order
L.BASE_NAMES = { ['pt-BR'] = { 'pt-BR', 'pt_BR', 'pt' }, en = { 'en', 'en-US' } }

function L.normalize(lang)
  if type(lang) ~= 'string' then return nil end
  local l = lang:lower():gsub('_', '-')
  if l == 'pt' or l:sub(1, 3) == 'pt-' or l:find('^portugu') then return 'pt-BR' end
  if l == 'en' or l:sub(1, 3) == 'en-' or l:find('^english') then return 'en' end
  return nil
end

-- the language for a first run from the system's locale names (env values, the C locale name); nil when none says
function L.fromSystem(names)
  for _, n in ipairs(names or {}) do
    if type(n) == 'string' and n ~= '' and n ~= 'C' and n ~= 'POSIX' then
      local first = n:match('^[^:]+') or n -- LANGUAGE is a list "pt_BR:en"
      local lang = L.normalize(first:match('^[^.@]+') or first)
      if lang then return lang end
    end
  end
  return nil
end

-- the saved choice, else the system's, else English
function L.choose(saved, systemNames)
  return L.normalize(saved) or L.fromSystem(systemNames) or 'en'
end

local HIGH = { [0x20AC] = 128, [0x201A] = 130, [0x0192] = 131, [0x201E] = 132, [0x2026] = 133, [0x2020] = 134,
  [0x2021] = 135, [0x02C6] = 136, [0x2030] = 137, [0x0160] = 138, [0x2039] = 139, [0x0152] = 140, [0x017D] = 142,
  [0x2018] = 145, [0x2019] = 146, [0x201C] = 147, [0x201D] = 148, [0x2022] = 149, [0x2013] = 150, [0x2014] = 151,
  [0x02DC] = 152, [0x2122] = 153, [0x0161] = 154, [0x203A] = 155, [0x0153] = 156, [0x017E] = 158, [0x0178] = 159 }

-- UTF-8 -> cp1252 (a character cp1252 lacks becomes '?'); a string that is not valid UTF-8 is returned as it is
function L.toCp1252(s)
  if type(s) ~= 'string' or not s:find('[\128-\255]') then return s end
  local out, i, n = {}, 1, #s
  while i <= n do
    local c = s:byte(i)
    if c < 128 then
      out[#out + 1] = string.char(c); i = i + 1
    else
      local extra = (c >= 0xC2 and c <= 0xDF) and 1 or (c >= 0xE0 and c <= 0xEF) and 2 or (c >= 0xF0 and c <= 0xF4) and 3 or nil
      if not extra or i + extra > n then return s end
      local cp = c % (extra == 1 and 32 or extra == 2 and 16 or 8)
      for k = 1, extra do
        local cc = s:byte(i + k)
        if cc < 128 or cc > 191 then return s end
        cp = cp * 64 + (cc - 128)
      end
      i = i + extra + 1
      if cp <= 255 then
        out[#out + 1] = string.char(cp)
      elseif cp ~= 0xFEFF then
        out[#out + 1] = string.char(HIGH[cp] or 63)
      end
    end
  end
  return table.concat(out)
end

-- upper case of a cp1252 string (string.upper only knows ASCII in the C locale: "come\231ar" kept its "\231"):
-- a-z, the accented 224..254 but the division sign 247, and \154 \156 \158 \255 (s/oe/z caron, y diaeresis)
local UPPER_HIGH = { [154] = 138, [156] = 140, [158] = 142, [255] = 159 }
function L.upper(s)
  if type(s) ~= 'string' then return s end
  return (s:gsub('[a-z\128-\255]', function(c)
    local b = c:byte()
    if b < 128 then return string.char(b - 32) end
    if b >= 224 and b <= 254 and b ~= 247 then return string.char(b - 32) end
    local u = UPPER_HIGH[b]
    return u and string.char(u) or c
  end))
end

-- a table {english = utf8} -> {english = cp1252}
function L.prepare(t)
  local out = {}
  for k, v in pairs(t or {}) do
    if type(k) == 'string' and type(v) == 'string' and v ~= '' then out[k] = L.toCp1252(v) end
  end
  return out
end

local function format(pattern, ...)
  if select('#', ...) == 0 then return pattern end
  local ok, s = pcall(string.format, pattern, ...)
  return ok and s or nil
end

-- tr(text, ...) for a language table (nil: English) and the base client's tr (or nil)
function L.translate(table_, baseTr, text, ...)
  if type(text) ~= 'string' then
    if baseTr then
      local ok, s = pcall(baseTr, text, ...)
      if ok then return s end
    end
    return text
  end
  local found = table_ and table_[text]
  if found then
    local s = format(found, ...)
    if s then return s end
  end
  if baseTr then
    local ok, s = pcall(baseTr, text, ...)
    if ok and type(s) == 'string' then return s end
  end
  return format(text, ...) or text
end

-- the hello for the server (opcode 157, server i18n.lua): the language of its texts
function L.hello(lang)
  return { action = 'hello', lang = L.normalize(lang) or 'en' }
end

return L
