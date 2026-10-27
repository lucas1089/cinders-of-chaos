-- luajit chaos_theme_test.lua (CI runs every client *_test.lua from the repo root, under LuaJIT and Lua 5.3)
-- Popup menu separators (chaos_theme.lua wrapPopupMenu): live test winpkg-35, the item menu showed three empty lines in
-- a row, and a right-click on bare grass showed "Look", empty lines and "Where to find".
local here = (arg and arg[0] and arg[0]:match('^(.*[/\\])') or '')
local n = 0
local function eq(a, b, m) n = n + 1 if a ~= b then error((m or '') .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b), 2) end end

-- a popup menu as the engine's corelib builds it: children in order, a separator is a child too
UIPopupMenu = {}
UIPopupMenu.__index = UIPopupMenu
local function widget(menu, kind, text)
  local w = { kind = kind, text = text, menu = menu }
  function w:getHeight() return kind == 'sep' and 2 or 18 end
  function w:destroy()
    for i, c in ipairs(menu.children) do if c == self then table.remove(menu.children, i) break end end
  end
  menu.children[#menu.children + 1] = w
  return w
end
function UIPopupMenu.new() return setmetatable({ children = {}, height = 0 }, UIPopupMenu) end
function UIPopupMenu:getChildCount() return #self.children end
function UIPopupMenu:getChildByIndex(i) return self.children[i] end
function UIPopupMenu:getHeight() return self.height end
function UIPopupMenu:setHeight(h) self.height = h end
function UIPopupMenu:addOption(text) widget(self, 'option', text) self.height = self.height + 18 end
function UIPopupMenu:addSeparator() widget(self, 'sep') self.height = self.height + 6 end
function UIPopupMenu:display() self.shown = true end

ChaosSkinCore = dofile(here .. 'skin_core.lua') -- the module loads it by its client path
dofile(here .. 'chaos_theme.lua')
ChaosTheme.wrapPopupMenu()

local function layout(menu)
  local out = {}
  for _, c in ipairs(menu.children) do out[#out + 1] = c.kind == 'sep' and '-' or c.text end
  return table.concat(out, '|')
end

-- the item menu of the live test: the hook categories each add a separator; Report Player, Talk and Inspect Player
-- have no entry for an item
local m = UIPopupMenu.new()
m:addOption('Look') m:addOption('Open')
m:addSeparator() m:addOption('Trade with ...')
m:addSeparator() m:addOption('Add to Quick Sell BlackList')
m:addSeparator() m:addSeparator() m:addSeparator() -- three empty hook categories
m:addSeparator() m:addOption('Pouch settings')
m:addSeparator() m:addOption('Where to find')
m:display()
eq(layout(m), 'Look|Open|-|Trade with ...|-|Add to Quick Sell BlackList|-|Pouch settings|-|Where to find',
  'one separator between groups')
eq(m.shown, true, 'shown')

-- the Lock item / Unlock item hooks (game_crafting): one of the two shows, the other adds only a separator
local lk = UIPopupMenu.new()
lk:addOption('Look')
lk:addSeparator() -- Lock item hidden
lk:addSeparator() lk:addOption('Unlock item')
lk:addSeparator() lk:addOption('Where to find')
lk:display()
eq(layout(lk), 'Look|-|Unlock item|-|Where to find', 'a hidden Lock item entry leaves no empty line')
local lk2 = UIPopupMenu.new()
lk2:addOption('Look')
lk2:addSeparator() lk2:addOption('Lock item')
lk2:addSeparator() -- Unlock item hidden
lk2:display()
eq(layout(lk2), 'Look|-|Lock item', 'a hidden Unlock item entry as the last one: no trailing line')

-- bare grass: "Look", then every hook category empty ("Where to find" is hidden on ground: itemfinderlogic menuThing)
local g = UIPopupMenu.new()
g:addSeparator() -- a leading one
g:addOption('Look')
for _ = 1, 6 do g:addSeparator() end
local h = g:getHeight()
g:display()
eq(layout(g), 'Look', 'bare grass: Look only, no empty lines')
eq(g:getHeight(), h - 6, 'the trailing separator is taken out of the height')

-- unwrap restores the engine's own
ChaosTheme.unwrapPopupMenu()
local u = UIPopupMenu.new()
u:addSeparator() u:addSeparator()
eq(#u.children, 2, 'unwrapped: as the engine does')

-- interface skin: palette of the skin on screen, the saved choice, restart note
local store, infos = {}, {}
g_settings = { getString = function(k) return store[k] or '' end, set = function(k, v) store[k] = v end }
tr = function(s, ...) return (select('#', ...) > 0) and s:format(...) or s end
displayInfoBox = function(title, text) infos[#infos + 1] = text end
eq(ChaosTheme.skin, 'classic', 'no boot: classic on screen')
eq(ChaosTheme.palette.title, '#e8c477', 'classic title colour')
eq(ChaosTheme.selectedSkin(), 'classic', 'nothing saved: classic')
eq(ChaosTheme.skinName('forge'), 'Forge and Embers', 'name')
eq(ChaosTheme.setSkin('abyss'), 'abyss', 'set')
eq(store['chaos-skin'], 'abyss', 'saved')
eq(#infos, 1, 'the restart note is shown')
eq(ChaosTheme.skinPending(), true, 'saved choice is not on screen yet')
eq(ChaosTheme.setSkin('bone', true), 'classic', 'unknown value saved as classic')
eq(store['chaos-skin'], 'classic', 'classic saved')
eq(ChaosTheme.skinPending(), false, 'nothing pending')

print('chaos_theme_test: ' .. n .. ' checks ok')
