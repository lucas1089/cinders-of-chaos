-- luajit topbarlogic_test.lua (CI runs every client *_test.lua from the repo root, under LuaJIT and Lua 5.3)
local here = (arg and arg[0] and arg[0]:match('^(.*[/\\])') or '')
dofile(here .. 'topbarlogic.lua')
local T = ChaosTopBarLogic
local n = 0
local function eq(a, b, m) n = n + 1 if a ~= b then error((m or '') .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b), 2) end end

local function item(text, key) return { entry = { text = text, key = key }, action = function() end } end
local function sub(text, list) return { entry = { text = text }, sub = list } end
local SEP = { separator = true }
local function texts(list, textOf)
  local out = {}
  for _, it in ipairs(list) do out[#out + 1] = it.separator and '-' or textOf(it) end
  return table.concat(out, '|')
end
local en = function(it) return it.entry.text end

-- windows an NPC opens stay out of the menu
eq(T.npcOnly('The Gambler'), true, 'gambler'); eq(T.npcOnly('Candlemarks'), true, 'candlemarks')
eq(T.npcOnly('Conquest Vendor'), true, 'conquest'); eq(T.npcOnly('Factions'), true, 'factions')
eq(T.npcOnly('Bank'), false, 'bank stays'); eq(T.npcOnly(nil), false, 'nil')

-- a drop-down with a "More" sub-menu: alphabetical, More last, the shortcut kept
local hunt = {
  item('Loot Filter', 'Alt+L'), item('Bestiary', 'Alt+B'), item('Hunt Tracker'), item('analyzer'),
  sub('More', { item('Unjustified Points'), item('Map Markers'), item('Prey'), item('Loot Splitter') }),
}
local sorted = T.sortList(hunt, en)
eq(texts(sorted, en), 'analyzer|Bestiary|Hunt Tracker|Loot Filter|More', 'alphabetical, case-insensitive, More last')
eq(texts(sorted[#sorted].sub, en), 'Loot Splitter|Map Markers|Prey|Unjustified Points', 'the sub-menu sorted too')
eq(sorted[2].entry.key, 'Alt+B', 'the shortcut stays with its entry')
eq(hunt[1].entry.text, 'Loot Filter', 'the list itself is not changed')

-- the translated text decides (pt-BR), accents folded
local PT = { ['Bestiary'] = 'Bestiário', ['Loot Filter'] = 'Filtro de Saque', ['Hunt Tracker'] = 'Rastreador de Caça',
  ['analyzer'] = 'Análise', ['More'] = 'Mais' }
local pt = function(it) return PT[it.entry.text] or it.entry.text end
eq(texts(T.sortList(hunt, pt), pt), 'Análise|Bestiário|Filtro de Saque|Rastreador de Caça|Mais', 'pt-BR order')
eq(T.sortKey('Économie') < T.sortKey('Fichier'), true, 'É sorts as E')
eq(T.sortKey(string.char(201) .. 'conomie') < T.sortKey('Fichier'), true, 'a cp1252 É too')

-- groups between separators stay groups (System: ... | Developer > | Logout, Exit)
local system = { item('Options'), item('Credits'), item('Hotkeys'), SEP, sub('Developer', { item('Console'), item('DAT Offset Studio') }),
  SEP, item('Logout'), item('Exit') }
eq(texts(T.sortList(system, en), en), 'Credits|Hotkeys|Options|-|Developer|-|Exit|Logout', 'groups sorted each on their own')

-- the bar stays below a visible window that overlaps it (the Passive Tree fills the game root panel)
local barRect = { x = 400, y = 2, width = 300, height = 42 }
local function win(o) local w = { visible = true, window = true, x = 0, y = 0, width = 1280, height = 720 } for k, v in pairs(o or {}) do w[k] = v end return w end
eq(T.coveredByWindow(barRect, { win() }), true, 'a full window above covers the bar')
eq(T.coveredByWindow(barRect, { win({ visible = false }) }), false, 'a hidden one does not')
eq(T.coveredByWindow(barRect, { win({ window = false }) }), false, 'a panel or HUD is not a window')
eq(T.coveredByWindow(barRect, { win({ y = 100, height = 300 }) }), false, 'a window below the bar does not overlap')
eq(T.coveredByWindow(barRect, { win({ x = 800, width = 200 }) }), false, 'a window beside the bar does not overlap')
eq(T.coveredByWindow(barRect, { win({ y = 30, height = 300 }) }), true, 'a window over the bar bottom edge covers it')
eq(T.coveredByWindow(barRect, {}), false, 'nothing above')
eq(T.coveredByWindow(nil, { win() }), false, 'no bar rect: raise as before')
eq(T.coveredByWindow({ x = 0, y = 0, width = 0, height = 0 }, { win() }), false, 'an empty bar rect: raise as before')

print('topbarlogic_test: ' .. n .. ' checks ok')
