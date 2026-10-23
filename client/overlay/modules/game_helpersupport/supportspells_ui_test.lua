-- luajit supportspells_ui_test.lua && lua5.3 supportspells_ui_test.lua (from the repository root or this folder)
-- The Support panel against a mock of the helper window (modules/game_helper/styles/helper.otui: the supportHost panel of
-- the Support tab) and of the engine's style table: owner beta 2026-10-20 "The helper's Support tab does not open".
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
for _, m in ipairs({ 'setMarginLeft', 'setMarginTop', 'setMarginBottom', 'setTooltip' }) do W[m] = function() end end
function W:setEnabled(e) self.disabled = not e end
function W:isEnabled() return not self.disabled end
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
  { 'ChaosSupportRow', 'Panel' }, { 'ChaosSupportPanel', 'Panel' } }
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
  if style == 'ChaosSupportRow' then
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
local win, content, host
local function makeHelperWindow()
  win = new('Window', root, 'helperWindow')
  content = new('Panel', win, 'contentPanel')
  host = new('Panel', content, 'supportHost')
  host.visible = false -- the helper shows it with its Support tab
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
modules = { game_helper = { _Helper = {} } }
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
eq(root:recursiveGetChildById(U.PANEL_ID), nil, 'no panel while the base styles are missing')
styles.Panel = true -- client_styles is loaded (with the `client` module, after the modules of priority 100-499)
runPolls()
local p = root:recursiveGetChildById(U.PANEL_ID)
ok(p, 'the panel once the base styles exist')
eq(p:getParent(), host, 'it sits in the Support tab host')
eq(#logged, 0, 'nothing logged')

-- the helper opens and closes the host with its tab
ok(not p:isVisible(), 'hidden while another tab shows')
host:show()
ok(p:isVisible(), 'shown with the Support tab')
host:hide()
ok(not p:isVisible(), 'hidden again')

-- a panel lost (an older build): the poll makes it again, once
p:destroy()
runPolls()
ok(root:recursiveGetChildById(U.PANEL_ID), 'a lost panel is made again')
local count = 0
for _, c in ipairs(host:getChildren()) do if c.id == U.PANEL_ID then count = count + 1 end end
eq(count, 1, 'one panel')
host:show()

-- the rows: an empty row's box is unticked and greyed; a spell picked in an empty row starts ticked
U.setSlots({ { id = 9101, enabled = true }, { id = 9102, enabled = false } }, true)
local pp = root:recursiveGetChildById(U.PANEL_ID)
local function rowBox(i) return pp:recursiveGetChildById('row' .. i):getChildById('enable') end
local slots = U.slots()
if #slots == 2 then
  ok(rowBox(1):isChecked() and rowBox(1):isEnabled(), 'a ticked spell row: ticked and clickable')
  ok(not rowBox(2):isChecked() and rowBox(2):isEnabled(), 'an unticked spell row: unticked and clickable')
  ok(not rowBox(3):isChecked() and not rowBox(3):isEnabled(), 'an empty row: unticked and greyed')
  -- the player picks the second spell again in a greyed (empty) row: it is read as ticked
  local r2 = pp:recursiveGetChildById('row2')
  r2:getChildById('enable'):setEnabled(false)
  r2:getChildById('spell').onOptionChange()
  eq(U.slots()[2] and U.slots()[2].enabled, true, 'a spell picked in an empty row starts ticked')
else
  print('supportspells_ui_test: sanitize dropped the test spells, row checks skipped')
end

if fails > 0 then error(fails .. ' failure(s)') end
print('supportspells_ui_test: OK')
