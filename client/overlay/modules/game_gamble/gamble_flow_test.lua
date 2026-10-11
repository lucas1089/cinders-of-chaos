-- luajit client/overlay/modules/game_gamble/gamble_flow_test.lua (CI runs every client *_test.lua from the repo root,
-- under LuaJIT and Lua 5.3)
-- gamble.lua on a mock UI: quick clicks on several crates send one purchase, the answer to a purchase fills the grid in
-- place (no cell is destroyed, least of all the Buy button just clicked), the reveal starts a new engine item for a new
-- look and never hands the engine an id outside 1..65535, and answers after Close or after the module is unloaded (the
-- window destroyed) are ignored without an error.
local dir = (arg and arg[0] and arg[0]:match('^(.*[/\\])') or '')
local n = 0
local function ok(cond, m) n = n + 1 if not cond then error(m or 'check failed', 2) end end
local function eq(a, b, m) n = n + 1 if a ~= b then error((m or '') .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b), 2) end end

-- ---------------------------------------------------------------- mock UI
local created, destroyed, itemIds = 0, 0, {}
local Widget = {}
Widget.__index = Widget
local function widget(id, kids)
  local w = setmetatable({ id = id, children = {}, visible = true, enabled = true, destroyedFlag = false }, Widget)
  created = created + 1
  for _, k in ipairs(kids or {}) do
    w[k.id] = k
    k.parent = w
    w.children[#w.children + 1] = k
  end
  return w
end
function Widget:isDestroyed() return self.destroyedFlag end
function Widget:destroy()
  if self.destroyedFlag then error('a widget destroyed twice: ' .. tostring(self.id)) end
  self.destroyedFlag = true
  destroyed = destroyed + 1
  for _, k in ipairs(self.children) do if not k.destroyedFlag then k:destroy() end end
end
function Widget:destroyChildren()
  for _, k in ipairs(self.children) do k:destroy() end
  self.children = {}
end
local function live(w)
  if w.destroyedFlag then error('a call on a destroyed widget: ' .. tostring(w.id), 3) end
end
for _, m in ipairs({ 'setText', 'setColor', 'setTooltip', 'setOpacity', 'setBorderColor', 'raise', 'focus' }) do
  Widget[m] = function(self, v) live(self) self[m .. 'V'] = v end
end
function Widget:setEnabled(v)
  live(self)
  if type(v) ~= 'boolean' then error('setEnabled with ' .. type(v), 2) end
  self.enabled = v
end
function Widget:setVisible(v) live(self) self.visible = v end
function Widget:show() live(self) self.visible = true end
function Widget:hide() live(self) self.visible = false end
function Widget:isVisible() return self.visible end
function Widget:setItemId(v)
  live(self)
  if type(v) ~= 'number' or v < 0 or v > 65535 or v ~= math.floor(v) then error('setItemId(' .. tostring(v) .. ')', 2) end
  self.itemId = v
  itemIds[#itemIds + 1] = v
end

local function cell()
  return widget('cell', { widget('item'), widget('seal'), widget('name'), widget('slot'), widget('level'),
    widget('price'), widget('buy') })
end
local function gambleWindow()
  return widget('gambleWindow', {
    widget('header'), widget('nearLabel'), widget('gridPlate', { widget('refreshLabel') }),
    widget('gridFrame', { widget('grid') }), widget('revealPanel', { widget('frame'), widget('item'), widget('text') }),
    widget('oddsLabel'), widget('status'), widget('rerollButton'), widget('closeButton') })
end

g_ui = {
  importStyle = function() end,
  createWidget = function(style, parent)
    local w = style == 'GambleCell' and cell() or gambleWindow()
    if parent and parent.children then
      parent.children[#parent.children + 1] = w
      w.parent = parent
    end
    return w
  end
}
rootWidget = widget('root')
g_logger = { warning = function(m) error('warning: ' .. m) end }
local clock = 1000
g_clock = { seconds = function() return clock end }
local sent = {}
local protocol = { sendExtendedOpcode = function(_, op, msg) sent[#sent + 1] = msg end }
g_game = { getProtocolGame = function() return protocol end, isOnline = function() return true end }
local jsonHandler
ProtocolGame = {
  registerExtendedJSONOpcode = function(op, fn) jsonHandler = fn end,
  unregisterExtendedJSONOpcode = function() jsonHandler = nil end
}
function connect() end
function disconnect() end
json = { encode = function(t) return t end }
function tr(s) return s end
local events, nextEvent = {}, 0
function scheduleEvent(fn, ms) nextEvent = nextEvent + 1 events[nextEvent] = fn return nextEvent end
function removeEvent(e) if e then events[e] = nil end end
local function runEvents()
  local list = events
  events = {}
  for _, fn in pairs(list) do fn() end
end
modules = {}

dofile(dir .. 'gambleview.lua')
dofile(dir .. 'gamble.lua')

-- ---------------------------------------------------------------- the flow
init()
local window = getWindow()
ok(window and jsonHandler, 'window and opcode handler')
local handler = jsonHandler
local function serverSends(action, data) handler(protocol, 199, { action = action, data = data }) end
local function lastSent() local m = sent[#sent] return m and m.action, m and m.data end

local function stock(w, sold)
  return {
    w = w, level = 300, gate = 120, near = true, money = 9000000, left = 3600, at = '08:00', tz = 'UTC',
    rerollMax = 0, odds = {}, npc = 'the Gambler',
    items = {
      { i = 1, id = 29883, c = 9883, n = 'blade', sn = 'Weapon', l = 120, p = 100000, sold = sold == 1 },
      { i = 2, id = 29879, c = 9879, n = 'plate', sn = 'Armor', l = 119, p = 100000, sold = sold == 2 },
      { i = 3, id = 2643, c = 2643, n = 'boots', sn = 'Boots', l = 118, p = 100000 },
    }
  }
end

show()
eq(lastSent(), 'open', 'show asks for the state')
serverSends('state', stock(7))
local grid = window.gridFrame.grid
eq(#grid.children, 3, 'one cell per crate')
local firstCells = { grid.children[1], grid.children[2], grid.children[3] }
eq(firstCells[1].item.itemId, 9883, 'cell look')

-- quick clicks on three crates: one purchase goes out, every Buy button waits
sent = {}
firstCells[1].buy.onClick()
firstCells[2].buy.onClick()
firstCells[3].buy.onClick()
eq(#sent, 1, 'one purchase at a time')
local action, data = lastSent()
eq(action, 'buy', 'a buy request')
eq(data.i, 1, 'the first crate')
eq(data.w, 7, 'the stock window')
for k = 1, 3 do eq(firstCells[k].buy.enabled, false, 'button ' .. k .. ' waits') end
eq(getState().buying, true, 'buying')

-- the answer: the reveal and then the state; the grid is filled in place
local before = destroyed
serverSends('result', { ok = true, text = 'The seal breaks', reveal = { r = 5, rn = 'Legendary', c = 9883, n = 'blade', l = 120 } })
eq(getState().buying, false, 'the answer frees the buttons')
local panel = window.revealPanel
eq(panel.item.itemId, 9883, 'reveal look')
eq(panel.item.visible, true, 'reveal shown')
serverSends('state', stock(7, 1))
eq(destroyed, before, 'no widget destroyed by the answer to a purchase')
eq(grid.children[1], firstCells[1], 'the same cell widgets')
eq(firstCells[1].buy.enabled, false, 'the sold crate cannot be bought')
eq(firstCells[2].buy.enabled, true, 'the others can again')

-- a new look in the reveal: a fresh engine item (0 first), never an id the engine would cut to 16 bits
itemIds = {}
serverSends('result', { ok = true, reveal = { r = 2, c = 9879, n = 'plate', l = 119 } })
eq(itemIds[1], 0, 'the old item goes first')
eq(itemIds[2], 9879, 'then the new look')
for _, bad in ipairs({ 70000, -1, 0, 'x', 12.5, 1e12 }) do
  serverSends('result', { ok = true, reveal = { r = 2, c = bad, n = 'plate', l = 119 } })
  eq(panel.item.visible, false, 'no look for client id ' .. tostring(bad))
end
serverSends('result', { ok = true, reveal = 5 })
serverSends('result', { ok = false, text = 'One crate at a time.' })

-- no answer at all (the server's rate limit dropped the request): the buttons come back
firstCells[2].buy.onClick()
eq(getState().buying, true, 'waiting again')
runEvents()
eq(getState().buying, false, 'the wait ends')
eq(firstCells[2].buy.enabled, true, 'the button is back')

-- closed in the middle of a reveal: the answers still land on the hidden window
firstCells[3].buy.onClick()
hide()
eq(lastSent(), 'close', 'close sent')
serverSends('result', { ok = true, reveal = { r = 7, c = 2643, n = 'boots', l = 118 } })
serverSends('state', stock(7, 3))
eq(window:isVisible(), false, 'still closed')

-- a new stock (other crates) rebuilds the grid
local fresh = stock(8)
fresh.items[1].id, fresh.items[1].c = 2465, 2465
serverSends('state', fresh)
ok(grid.children[1] ~= firstCells[1], 'new cells for a new stock')
ok(firstCells[1]:isDestroyed(), 'the old cells are gone')

-- malformed states
serverSends('state', { w = 9, items = { 1, 'x', { i = 1, c = 99999 } } })
serverSends('state', { w = 9, items = 'none', last = 'x' })

-- unloaded (module reload) while answers are on their way: the old handler gets them, the window is gone
terminate()
ok(window:isDestroyed(), 'window destroyed on unload')
serverSends('result', { ok = true, reveal = { r = 5, c = 9883, n = 'blade', l = 120 } })
serverSends('state', stock(8))
runEvents()

print('gamble_flow_test: ' .. n .. ' checks passed')
