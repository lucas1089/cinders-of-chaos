-- Top bar menu logic without client API (chaos_topbar.lua uses it; topbarlogic_test.lua tests it).
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.

ChaosTopBarLogic = {}
local T = ChaosTopBarLogic

-- windows an NPC opens when you talk to it (owner 2026-11-05: out of the top menu). The modules still ask to add them;
-- addEntry drops them. The window keeps working from its NPC: Mordecai Ashwager, Osric the Chandler, Iselde Varrow
-- and the four faction NPCs.
T.NPC_ONLY = { ['The Gambler'] = true, ['Candlemarks'] = true, ['Conquest Vendor'] = true, ['Factions'] = true }

function T.npcOnly(text)
  return T.NPC_ONLY[text] == true
end

-- accented letters of the menu languages (UTF-8 and the client's cp1252) folded to their plain letter, so "É" sorts
-- with "E" in pt-BR
local FOLD = {
  ['á'] = 'a', ['à'] = 'a', ['â'] = 'a', ['ã'] = 'a', ['ä'] = 'a', ['é'] = 'e', ['ê'] = 'e', ['è'] = 'e', ['ë'] = 'e',
  ['í'] = 'i', ['ì'] = 'i', ['î'] = 'i', ['ï'] = 'i', ['ó'] = 'o', ['ò'] = 'o', ['ô'] = 'o', ['õ'] = 'o', ['ö'] = 'o',
  ['ú'] = 'u', ['ù'] = 'u', ['û'] = 'u', ['ü'] = 'u', ['ç'] = 'c', ['ñ'] = 'n',
  ['Á'] = 'a', ['À'] = 'a', ['Â'] = 'a', ['Ã'] = 'a', ['Ä'] = 'a', ['É'] = 'e', ['Ê'] = 'e', ['È'] = 'e', ['Ë'] = 'e',
  ['Í'] = 'i', ['Ì'] = 'i', ['Î'] = 'i', ['Ï'] = 'i', ['Ó'] = 'o', ['Ò'] = 'o', ['Ô'] = 'o', ['Õ'] = 'o', ['Ö'] = 'o',
  ['Ú'] = 'u', ['Ù'] = 'u', ['Û'] = 'u', ['Ü'] = 'u', ['Ç'] = 'c', ['Ñ'] = 'n',
}

-- the same letters as single cp1252 bytes (a UTF-8 pair 0xC3 xx is the cp1252 byte xx + 0x40)
local FOLD1252 = {}
for from, to in pairs(FOLD) do
  local a, b = from:byte(1, 2)
  if a == 0xC3 and b then FOLD1252[string.char(b + 0x40)] = to end
end

-- the sort key of a shown text: lower case, accents folded, leading spaces and marks dropped
function T.sortKey(text)
  local s = tostring(text or '')
  for from, to in pairs(FOLD) do
    s = s:gsub(from, to)
  end
  for from, to in pairs(FOLD1252) do
    s = s:gsub(from, to)
  end
  s = s:lower():gsub('^[%s%p]+', '')
  return s
end

-- a drop-down or sub-menu list (chaos_topbar.lua availableEntries: {entry, action}, {entry, sub}, {separator}) in
-- alphabetical order of the shown, translated text (textOf(item) -> text; owner request 2026-10-16). The groups
-- between separators stay groups and are sorted each on its own; a sub-menu entry ("More >") goes after the plain
-- entries of its group, so "More" stays last. Ties keep the order of the list. A new list; sub lists are sorted too.
function T.sortList(list, textOf)
  local out, group = {}, {}
  local function flush()
    local plain, subs = {}, {}
    for i, item in ipairs(group) do
      local key = T.sortKey(textOf(item))
      local row = { item = item, key = key, i = i }
      if item.sub then subs[#subs + 1] = row else plain[#plain + 1] = row end
    end
    local function less(a, b)
      if a.key ~= b.key then return a.key < b.key end
      return a.i < b.i
    end
    table.sort(plain, less)
    table.sort(subs, less)
    for _, r in ipairs(plain) do out[#out + 1] = r.item end
    for _, r in ipairs(subs) do out[#out + 1] = r.item end
    group = {}
  end
  for _, item in ipairs(list or {}) do
    if item.separator then
      flush()
      out[#out + 1] = item
    else
      if item.sub then
        local copy = {}
        for k, v in pairs(item) do copy[k] = v end
        copy.sub = T.sortList(item.sub, textOf)
        item = copy
      end
      group[#group + 1] = item
    end
  end
  flush()
  return out
end

return T
