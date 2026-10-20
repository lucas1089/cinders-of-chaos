-- luajit supportspells_ui_test.lua && lua5.3 supportspells_ui_test.lua (from the repository root or this folder)
-- The Support tab against a mock of the helper window (mods/game_helper/helper_window.otui ids, loadMenu's checks) and
-- of the engine's style table: owner beta 2026-10-20 "The helper's Support tab does not open".
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
local fails = 0
local function eq(a, b, what)
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end
local function ok(c, what) eq(not not c, true, what) end

-- ---------------------------------------------------------------- a small widget tree
local W = {}
W.__index = W
local function new(style, parent, id)
  local w = setmetatable({ id = id, children = {}, visible = true, checked = false, style = style, width = 114 }, W)
  if parent then
    w.parent = parent
    parent.children[#parent.children + 1] = w
  end
  return w
end
function W:getId() return self.id end
function W:setId(i) self.id = i end
function W:getParent() return self.parent end
function W:getChildById(i) for _, c in ipairs(self.children) do if c.id == i then return c end end end
function W:recursiveGetChildById(i)
  local c = self:getChildById(i)
  if c then return c end
  for _, ch in ipairs(self.children) do
    local r = ch:recursiveGetChildById(i)
    if r then return r end
  end
end
function W:getChildren() return self.children end
function W:hide() self.visible = false end
function W:show() self.visible = true end
function W:isVisible()
  local w = self
  while w do
    if not w.visible then return false end
    w = w.parent
  end
  return true
end
function W:setChecked(c)
  if self.checked ~= c then
    self.checked = c
    if self.onCheckChange then self.onCheckChange(self, c) end
  end
end
function W:isChecked() return self.checked end
function W:raise() end
function W:addAnchor() end
function W:setWidth(v) self.width = v end
for _, m in ipairs({ 'setMarginLeft', 'setMarginTop', 'setMarginBottom', 'setTooltip', 'setEnabled' }) do W[m] = function() end end
function W:setText(t) self.text = t end
function W:destroy()
  local p = self.parent
  if p then
    for i, c in ipairs(p.children) do if c == self then table.remove(p.children, i) break end end
  end
  self.parent = nil
end
function W:clearOptions() self.options, self.cur = {}, nil end
function W:addOption(t, d)
  self.options = self.options or {}
  self.options[#self.options + 1] = { text = t, data = d }
  if #self.options == 1 then self.cur = 1 end
end
function W:setCurrentOptionByData(d) for i, o in ipairs(self.options or {}) do if o.data == d then self.cur = i end end end
function W:getCurrentOption() return self.options and self.options[self.cur] end
function W:click() if self.onClick then self.onClick(self) end end

-- ---------------------------------------------------------------- the engine's style table (UIManager)
local styles = {}            -- defined styles; 'UI*' are defined by themselves
local function defined(name) return name:sub(1, 2) == 'UI' or styles[name] end
local otui = { -- supportspells.otui in file order: style <- base
  { 'ChaosSupportTab', 'UIButton' }, { 'ChaosSupportRow', 'Panel' }, { 'ChaosSupportPanel', 'Panel' } }
local function importStyle()
  -- UIManager::importStyleFromOTML stops at the first base style that is not defined yet
  for _, s in ipairs(otui) do
    if not defined(s[2]) then return false end
    styles[s[1]] = true
  end
  return true
end
local function build(style, parent)
  if not defined(style) then return nil end -- createWidget logs and gives nil
  local w = new(style, parent)
  if style == 'ChaosSupportTab' then
    new('Label', w, 'caption')
  elseif style == 'ChaosSupportRow' then
    new('CheckBox', w, 'enable') new('Label', w, 'number') new('ComboBox', w, 'spell') new('Label', w, 'status')
  elseif style == 'ChaosSupportPanel' then
    w.visible = false
    local box = new('Panel', w, 'box')
    local o = new('Panel', box, 'options')
    new('CheckBox', o, 'enableAll') new('ComboBox', o, 'reserve')
    new('Panel', box, 'rows') new('Label', box, 'statusLine')
    local b = new('Panel', box, 'buttons')
    new('Button', b, 'fill') new('Button', b, 'clear')
  end
  return w
end

-- ---------------------------------------------------------------- the helper window and its loadMenu
local root = new('Root')
local win, content, bar
local menus = { 'healingMenu', 'toolsMenu', 'shooterMenu', 'equipMenu', 'timerMenu', 'settingsFolderMenu' }
local panelOf = { healingMenu = 'healingPanel', toolsMenu = 'toolsPanelContainer', shooterMenu = 'shooterPanel',
  equipMenu = 'equipPanelContainer', timerMenu = 'timerPanelContainer', settingsFolderMenu = 'settingsPanel' }
local function loadMenu(id)
  for _, m in ipairs(menus) do bar:getChildById(m):setChecked(false) end
  bar:getChildById(id):setChecked(true)
  for _, m in ipairs(menus) do content:getChildById(panelOf[m]):hide() end
  content:getChildById(panelOf[id]):show()
end
local fitted = 0
local function makeHelperWindow()
  win = new('Window', root, 'helperWindow')
  content = new('Panel', win, 'contentPanel')
  bar = new('Panel', content, 'optionsTabBar')
  new('Panel', content, 'helperSidebar')
  for _, m in ipairs(menus) do new('Panel', content, panelOf[m]).visible = false end
  new('Panel', content, 'separator')
  for _, m in ipairs(menus) do
    local b = new('UIButton', bar, m)
    b.onClick = function() loadMenu(m) end
  end
end

local scheduled = {}
g_ui = {
  getRootWidget = function() return root end,
  importStyle = importStyle,
  getStyle = function(name) return defined(name) and {} or nil end,
  createWidget = build,
}
g_game = {
  isOnline = function() return true end,
  getLocalPlayer = function() return { getName = function() return 'Tester' end } end,
  talk = function() end, getAttackingCreature = function() end,
}
g_settings = { getNode = function() return {} end, setNode = function() end, save = function() end }
g_clock = { millis = function() return 0 end }
local logged = {}
g_logger = { error = function(e) logged[#logged + 1] = e end }
tr = function(s) return s end
scheduleEvent = function(f) scheduled[#scheduled + 1] = f return #scheduled end
cycleEvent = function() return 1 end
removeEvent = function() end
connect = function() end
disconnect = function() end
LocalPlayer = {}
AnchorLeft, AnchorRight, AnchorTop, AnchorBottom = 1, 2, 3, 4
modules = { game_helper = { _Helper = {}, onHelperViewportChange = function()
  -- fitHelperWindow: every button of the bar gets the same width
  local n = #bar:getChildren()
  for _, b in ipairs(bar:getChildren()) do b:setWidth(math.floor(933 / n) - 1) end
  fitted = fitted + 1
end } }
Spells = { getSpellList = function() return {} end }

local function runPolls()
  local list = scheduled
  scheduled = {}
  for _, f in ipairs(list) do f() end
end

dofile(dir .. 'supportspells.lua')
dofile(dir .. 'supportspells_ui.lua')
local U = ChaosHelperSupportUI

-- the module loads (priority 100) before client_styles and before the helper (a mod)
U.init()
eq(styles.ChaosSupportPanel, nil, 'init imports no styles (Panel is not defined yet)')
makeHelperWindow()
runPolls()
eq(bar:getChildById(U.TAB_ID), nil, 'no tab while the base styles are missing (no tab without its panel)')
styles.Panel = true -- client_styles is loaded (with the `client` module, after the modules of priority 100-499)
runPolls()
local tab = bar:getChildById(U.TAB_ID)
ok(tab, 'the tab once the base styles exist')
ok(root:recursiveGetChildById(U.PANEL_ID), 'and its panel with it')
eq(fitted, 1, 'the helper refits its tab buttons for the new one')
eq(tab.width, bar:getChildById('healingMenu').width, 'the Support tab is as wide as the others (inside the bar)')
eq(#logged, 0, 'nothing logged')

-- open and close
loadMenu('toolsMenu')
tab:click()
local p = root:recursiveGetChildById(U.PANEL_ID)
ok(p:isVisible(), 'a click on Support opens its panel')
ok(not content:getChildById('toolsPanelContainer'):isVisible(), 'the helper panel goes')
ok(tab:isChecked() and not bar:getChildById('toolsMenu'):isChecked(), 'Support is the checked tab')
bar:getChildById('timerMenu'):click()
ok(not p:isVisible(), 'another tab hides it')
ok(content:getChildById('timerPanelContainer'):isVisible(), 'and shows its own panel')
ok(not tab:isChecked(), 'Support unchecked')
tab:click()
ok(p:isVisible(), 'and Support opens it again')

-- an older build left a tab without its panel: the poll makes both again
p:destroy()
runPolls()
ok(root:recursiveGetChildById(U.PANEL_ID), 'a tab without its panel: the panel is made')
local count = 0
for _, c in ipairs(bar:getChildren()) do if c.id == U.TAB_ID then count = count + 1 end end
eq(count, 1, 'one Support tab')
bar:getChildById(U.TAB_ID):click()
ok(root:recursiveGetChildById(U.PANEL_ID):isVisible(), 'and it opens')
bar:getChildById('healingMenu'):click()
ok(not root:recursiveGetChildById(U.PANEL_ID):isVisible(), 'the wrapped tabs still hide it (wrapped once)')

if fails > 0 then error(fails .. ' failure(s)') end
print('supportspells_ui_test: OK')
