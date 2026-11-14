-- luajit chaos_topbar_test.lua (CI runs every client *_test.lua from the repo root, under LuaJIT and Lua 5.3)
-- chaos_topbar.lua with topbar_hub.lua on a fake engine: the two looks of the bar (hubs by default, the text menu), the switch
-- both ways, the fallback to the text menu when the hub code raises an error or the glyph art is missing, ChaosTopBar.open on
-- a category, and the kept API (available, run, addEntry). The fake builds the children of the hub styles from the real
-- topbar_hub.otui (see topbar_hub_test.lua).
local here = (arg and arg[0] and arg[0]:match('^(.*[/\\])') or '')
local n = 0
local function eq(a, b, m) n = n + 1 if a ~= b then error((m or '') .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b), 2) end end

local f = assert(io.open(here .. 'topbar_hub.otui', 'r'))
local otui = f:read('*a')
f:close()
local styles, cur = {}, nil
for line in (otui .. '\n'):gmatch('([^\n]*)\n') do
  local name = line:match('^([%a]%w*)%s*<%s*%w+%s*$')
  if name then cur = { ids = {}, kids = {} } styles[name] = cur
  elseif cur then
    local id = line:match('^%s+id:%s*([%w_]+)%s*$')
    if id then cur.ids[#cur.ids + 1] = id end
    local kid = line:match('^  ([%a]%w*)%s*$')
    if kid then cur.kids[#cur.kids + 1] = kid end
  end
end
local function idsOf(style, out, seen)
  out, seen = out or {}, seen or {}
  local s = styles[style]
  if not s or seen[style] then return out end
  seen[style] = true
  for _, id in ipairs(s.ids) do out[#out + 1] = id end
  for _, k in ipairs(s.kids) do idsOf(k, out, seen) end
  return out
end

local Widget = {}
Widget.__index = function(t, k)
  if Widget[k] then return Widget[k] end
  if k:match('^set') or k:match('^add') or k == 'show' or k == 'hide' or k == 'raise' or k == 'focus' or k == 'breakAnchors' then return function() end end
  return nil
end
local function new(style, parent)
  local w = setmetatable({ style = style, parent = parent, kids = {}, byId = {}, text = '', visible = true, destroyed = false, h = 36 }, Widget)
  if parent then parent.kids[#parent.kids + 1] = w end
  for _, id in ipairs(idsOf(style)) do w.byId[id] = w.byId[id] or setmetatable({ kids = {}, byId = {}, text = '', visible = true, parent = w }, Widget) end
  if style == 'ChaosMenuBar' then w.byId.buttons = setmetatable({ kids = {}, byId = {}, visible = true, parent = w, margins = {} }, Widget) end
  return w
end
function Widget:isDestroyed() return self.destroyed end
function Widget:destroy() self.destroyed = true if self.parent then for i, k in ipairs(self.parent.kids) do if k == self then table.remove(self.parent.kids, i) break end end end end
function Widget:destroyChildren() for i = #self.kids, 1, -1 do self.kids[i]:destroy() end end
function Widget:recursiveGetChildById(id) return self.byId[id] end
function Widget:getChildById(id) return self.byId[id] end
function Widget:setId(id) self.id = id end
function Widget:setText(t) self.text = t end
function Widget:getTextSize() return { width = #self.text * 6, height = 12 } end
function Widget:setWidth(w) self.width = w end
function Widget:getWidth() return self.width or 40 end
function Widget:setHeight(h) self.h = h end
function Widget:setVisible(v) self.visible = v end
function Widget:isVisible() return self.visible end
function Widget:show() self.visible = true end
function Widget:hide() self.visible = false end
function Widget:setMarginTop(v) self.marginTop = v end
function Widget:setMarginBottom(v) self.marginBottom = v end
function Widget:getParent() return self.parent end
function Widget:setParent(p) self.parent = p end
function Widget:getLastChild() return self.kids[#self.kids] end
function Widget:getPosition() return { x = 0, y = 0 } end
function Widget:getHeight() return self.h end
function Widget:containsPoint() return true end

local settings, logged, events = {}, {}, {}
local gameRoot = new('root')
g_ui = { importStyle = function() end, getRootWidget = function() return gameRoot end,
         createWidget = function(style, parent) return new(style, parent) end }
g_app = { isMobile = function() return false end, exit = function() end }
g_game = { isOnline = function() return false end, getCharacterName = function() return '' end }
g_settings = { getString = function(k) return settings[k] or '' end, set = function(k, v) settings[k] = v end }
g_logger = { warning = function(m) logged[#logged + 1] = m end, error = function(m) logged[#logged + 1] = m end }
g_keyboard = { isShiftPressed = function() return false end, bindKeyDown = function() end, unbindKeyDown = function() end }
local artExists = true
g_resources = { fileExists = function() return artExists end }
-- the stock top strip of client_topmenu (the old menu panel): a widget the module hands out; the engine keeps its frame while it is hidden
local stock = setmetatable({ kids = {}, byId = {}, visible = true, h = 22, phantom = false, destroyed = false }, {
  __index = function(t, k)
    if k:match('^set') then return function() end end
  end })
function stock:isDestroyed() return self.destroyed end
function stock:isVisible() return self.visible end
function stock:show() self.visible = true if self.onVisibilityChange then self.onVisibilityChange(self, true) end end
function stock:hide() self.visible = false end
function stock:getHeight() return self.h end
function stock:setHeight(v) self.h = v end
function stock:setPhantom(v) self.phantom = v end
modules = { client_settings = nil, client_topmenu = { getTopMenu = function() return stock end } }
function connect() end
function disconnect() end
function scheduleEvent(fn) events[#events + 1] = fn return #events end
function removeEvent() end
function displayInfoBox() end
tr = function(k) return k end
ChaosTheme = { palette = {} }
AnchorTop, AnchorLeft, AnchorRight, AnchorVerticalCenter, AnchorHorizontalCenter = 1, 2, 3, 4, 5
MouseLeftButton, MouseRightButton = 1, 2
local function runEvents() local e = events events = {} for _, fn in ipairs(e) do fn() end end

for _, file in ipairs({ 'topbarlogic', 'topbarhublogic', 'topbar_tree', 'topbar_cards', 'topbar_glyph_index', 'topbar_hub',
                        'topbarunlockslogic', 'chaos_topbar' }) do
  dofile(here .. file .. '.lua')
end

init()
local bar = gameRoot.kids[1]
eq(bar.style, 'ChaosMenuBar', 'the bar exists')
local panel = bar.byId.buttons
local function badgeIds()
  local out = {}
  for _, k in ipairs(panel.kids) do if k.id and k.id:match('^chaosHub_') then out[#out + 1] = k.id end end
  return table.concat(out, ',')
end

-- the old top menu strip is gone in hub mode: hidden, no mouse, no height (it peeked out above the hub bar, owner 2026-11-14)
eq(stock.visible, false, 'the stock top strip is hidden'); eq(stock.h, 0, 'sized to nothing'); eq(stock.phantom, true, 'and out of the mouse way')
stock.visible, stock.h = true, 22   -- something showed it again (a logout, a relayout of the base)
ChaosTopBar.refresh()
eq(stock.visible, false, 'a refresh hides it again'); eq(stock.h, 0, 'and sizes it to nothing again')
stock.h = 22; stock.visible = false -- grown while hidden
ChaosTopBar.refresh()
eq(stock.h, 0, 'a refresh takes the height away again')

-- the login screen in the hub look: the System hub only (Join Discord, Exit, Options... whatever the offline entries give)
eq(ChaosTopBar.getStyle(), 'hubs', 'the default look is the hubs')
eq(badgeIds(), 'chaosHub_system', 'the login screen shows the System hub only')
eq(bar.h, 42, 'the hub bar is 42 high'); eq(panel.marginTop, 5, 'badge margins')
local hubWidth = bar.width
eq(hubWidth, ChaosTopBarHubLogic.barWidth({ { kind = 'hub' } }, 32), 'the bar is as wide as its badge')
for _, k in ipairs(panel.kids) do if k.style == 'ChaosMenuButton' then eq(k.visible, false, 'the category buttons are hidden in the hub look') end end

-- the kept API
local avail = ChaosTopBar.available()
eq(type(avail.system), 'table', 'available() still lists the categories')
eq(ChaosTopBar.open('system'), true, 'open(category) opens the hub of the category'); eq(ChaosTopBarHub.openId(), 'system', 'the System hub')
ChaosTopBarHub.close()
eq(ChaosTopBar.open('admin'), true, 'the admin id maps to the System hub'); ChaosTopBarHub.close()

-- the way to the text menu and back
ChaosTopBar.setStyle('text')
eq(settings.chaosMenuStyle, 'text', 'the choice is saved'); eq(ChaosTopBar.getStyle(), 'text', 'the text look')
eq(badgeIds(), '', 'the hub badges are gone'); eq(bar.h, 36, 'the text bar is 36 high'); eq(panel.marginTop, 4, 'text margins back')
local shownButtons = 0
for _, k in ipairs(panel.kids) do if k.style == 'ChaosMenuButton' and k.visible then shownButtons = shownButtons + 1 end end
eq(shownButtons >= 1, true, 'the category buttons are back')
eq(ChaosTopBarHub.isOpen(), false, 'no hub window in the text look')
eq(stock.visible, false, 'the stock strip stays hidden in the text look too (its buttons are in the text menu)'); eq(stock.h, 0, 'with no height')
ChaosTopBar.setStyle('hubs')
eq(ChaosTopBar.getStyle(), 'hubs', 'back to the hubs'); eq(badgeIds(), 'chaosHub_system', 'the badge is back')

-- the option writes the same choice and does not loop
modules.client_settings = { setOption = function(k, v) settings['opt_' .. k] = v; onOption(k, v) end, getOption = function() return nil end }
onOption('hubMenu', false)
eq(ChaosTopBar.getStyle(), 'text', 'the option turns the text menu on')
ChaosTopBar.setStyle('hubs')
eq(settings.opt_hubMenu, true, 'setStyle writes the option too'); eq(ChaosTopBar.getStyle(), 'hubs', 'and stays on the hubs')

-- an error in the hub code: the text menu, once
local origLayout = ChaosTopBarHub.layoutBar
ChaosTopBarHub.layoutBar = function() return nil end   -- what a guarded failure returns
ChaosTopBar.refresh()
eq(ChaosTopBar.getStyle(), 'text', 'a failed hub layout puts the text menu back')
ChaosTopBarHub.layoutBar = origLayout
ChaosTopBar.setStyle('hubs')
eq(ChaosTopBar.getStyle(), 'hubs', 'picking the hubs again clears the error')
-- the art is missing: the text menu and one warning
ChaosTopBar.setStyle('hubs')
artExists = false
ChaosTopBar.refresh()
eq(ChaosTopBar.getStyle(), 'text', 'no glyph art means the text menu')
local warned = 0
for _, m in ipairs(logged) do if m:find('glyph art is missing', 1, true) then warned = warned + 1 end end
ChaosTopBar.refresh(); ChaosTopBar.getStyle()
local warned2 = 0
for _, m in ipairs(logged) do if m:find('glyph art is missing', 1, true) then warned2 = warned2 + 1 end end
eq(warned, 1, 'one warning'); eq(warned2, 1, 'and not one per refresh')
artExists = true

-- addEntry: the text menu and the hubs both get it (an entry with a card lands on it)
ChaosTopBar.setStyle('hubs')
eq(ChaosTopBar.addEntry('hunt', { text = 'Battle List', icon = 'battlelist', custom = function() end, offline = true }), true, 'addEntry still works')
runEvents()
eq(badgeIds():find('chaosHub_hunt', 1, true) ~= nil, true, 'a new usable entry shows its hub')
eq(ChaosTopBar.run('Battle List'), true, 'run finds it')

-- the hub code's own failure path: host.failed through a raising items()
local failedBefore = #logged
local realItems = ChaosTopBarHub
ChaosTopBarHub.init({ parent = function() return gameRoot end, items = function() error('boom') end, failed = function() end })
ChaosTopBarHub.layoutBar(panel)
eq(#logged > failedBefore, true, 'the hub error is logged')

terminate()
eq(stock.h, 22, 'terminate gives the stock strip its height back'); eq(stock.phantom, false, 'and the mouse'); eq(stock.visible, true, 'and shows it')
print('chaos_topbar_test: ' .. n .. ' checks ok')
