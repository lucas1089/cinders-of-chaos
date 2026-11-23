-- luajit groundlabels_engine_test.lua && lua5.3 groundlabels_engine_test.lua (from any folder)
-- The engine part of the ground labels (groundlabels.lua) on a fake engine with the real module code: the tile scan, the server's
-- answer, the label widgets, and a left click on a label (O716, owner 2026-11-22: "clickar no nome do item no chao nao esta fazendo
-- nada. era pra pegar ele"). A click must move the item into the backpack, also when the labels were rebuilt between the press and
-- the release (the label text carries the despawn timer, so every second a layout builds new label widgets), a pile's lower item
-- goes through `raise`, a corpse opens, a drag is no click.
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
local fails, checks = 0, 0
local function eq(a, b, what)
  checks = checks + 1
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

-- ---------------------------------------------------------------- the fake engine
MouseLeftButton, MouseRightButton = 1, 2
AnchorTop, AnchorLeft = 1, 2
local TILE = 64
local PLAYER = { x = 100, y = 100, z = 7 }
local clock = 1000
g_clock = { millis = function() return clock * 1000 end, seconds = function() return clock end }
local sentOpcodes, moves, opened, messages = {}, {}, {}, {}
local replies = {}
json = {
  encode = function(t) replies[#replies + 1] = t return 'json:' .. #replies end,
  decode = function(s) return replies[tonumber(s:match('^json:(%d+)$'))] end,
}
local panelRect = { x = 0, y = 0, width = 15 * TILE, height = 11 * TILE }

-- a widget with a rect; a child's rect follows its parent's (anchors left / top plus margins), a block's rect is set by the
-- "engine" below (a tile widget is drawn centred on its tile)
local function newWidget(kind, parent)
  local w = { kind = kind, parent = parent, children = {}, margins = { l = 0, t = 0 }, size = { w = 0, h = 0 }, destroyed = false,
    text = '', abs = nil, bg = '#000000' }
  if parent then parent.children[#parent.children + 1] = w end
  function w:setFont() end
  function w:setText(t) self.text = t end
  function w:getText() return self.text end
  function w:getTextSize() return { width = #self.text * 6, height = 12 } end
  function w:resize(a, b) self.size = { w = a, h = b } end
  function w:addAnchor() end
  function w:setId(id) self.id = id end
  function w:getId() return self.id end
  function w:setMarginTop(v) self.margins.t = v end
  function w:setMarginLeft(v) self.margins.l = v end
  function w:setColor() end
  function w:setBorderWidth() end
  function w:setBorderColor() end
  function w:setImageSource() end
  function w:setImageBorder() end
  function w:setBackgroundColor(c) self.bg = c end
  function w:getBackgroundColor() return self.bg end
  function w:setOpacity() end
  function w:isDestroyed() return self.destroyed end
  function w:destroy() self.destroyed = true end
  function w:getRect()
    local x, y
    if self.parent and self.parent.abs then
      x, y = self.parent.abs.x + self.margins.l, self.parent.abs.y + self.margins.t
    elseif self.abs then
      x, y = self.abs.x, self.abs.y
    else
      x, y = -10000, -10000
    end
    return { x = x, y = y, width = self.size.w, height = self.size.h }
  end
  function w:containsPoint(p)
    local r = self:getRect()
    return p.x >= r.x and p.x < r.x + r.width and p.y >= r.y and p.y < r.y + r.height
  end
  return w
end
g_ui = {
  importStyle = function() end,
  createWidget = function(kind, parent)
    if kind == 'GroundLabelsWindow' then error('no window in the fake') end
    return newWidget(kind, parent)
  end,
}

local function newItem(id, count, stack, attrs, flags)
  flags = flags or {}
  local it = { id = id, count = count, stack = stack, attrs = attrs or {} }
  function it:getId() return self.id end
  function it:getCount() return self.count end
  function it:getStackPos() return self.stack end
  function it:isGround() return false end
  function it:isGroundBorder() return false end
  function it:isOnBottom() return false end
  function it:isOnTop() return false end
  function it:isPickupable() return flags.corpse ~= true end
  function it:isContainer() return flags.corpse == true end
  function it:isCorpse() return flags.corpse == true end
  function it:isLyingCorpse() return false end
  function it:getCustomAttribute(k) return self.attrs[k] end
  return it
end

local tiles = {}
local function tileAt(pos)
  local k = pos.x .. ',' .. pos.y .. ',' .. pos.z
  return tiles[k]
end
local function addTile(pos, items)
  local ground = newItem(100, 1, 0)
  function ground:isGround() return true end
  local list = { ground }
  for _, it in ipairs(items) do list[#list + 1] = it end
  local t = { pos = pos, items = list }
  function t:getItems() return self.items end
  function t:getThingCount() return #self.items end
  function t:setWidget(w) self.widget = w end
  function t:getWidget() return self.widget end
  function t:removeWidget() self.widget = nil end
  tiles[pos.x .. ',' .. pos.y .. ',' .. pos.z] = t
  return t
end
g_map = { getTile = function(pos) return tileAt(pos) end }

local player = {
  getPosition = function() return PLAYER end,
  getInventoryItem = function() return {} end,
}
local protocol = { sendExtendedOpcode = function(_, op, buf) sentOpcodes[#sentOpcodes + 1] = { op = op, data = json.decode(buf) } end }
g_game = {
  isOnline = function() return true end,
  getLocalPlayer = function() return player end,
  getProtocolGame = function() return protocol end,
  move = function(thing, pos, count) moves[#moves + 1] = { thing = thing, pos = pos, count = count } end,
  open = function(thing) opened[#opened + 1] = thing end,
}
g_logger = { warning = function() end, info = function() end }
g_settings = { getNode = function() return nil end, setNode = function() end }
g_keyboard = { isAltPressed = function() return false end }
g_tooltip = { hide = function() end, displayText = function() end }
local opcodeHandler
ProtocolGame = { registerExtendedOpcode = function(_, fn) opcodeHandler = fn end, unregisterExtendedOpcode = function() end }
LocalPlayer = {}
local cycles, scheduled = {}, {}
function cycleEvent(fn, ms) cycles[#cycles + 1] = { fn = fn, ms = ms } return fn end
function scheduleEvent(fn) scheduled[#scheduled + 1] = fn return fn end
function removeEvent() end
local connected = {}
function connect(obj, handlers) if obj == panel then connected = handlers end end
function disconnect() end
rootWidget = {}
local panel = {
  getVisibleDimension = function() return { width = 15, height = 11 } end,
  getRect = function() return panelRect end,
  isKeepAspectRatioEnabled = function() return false end,
  isDestroyed = function() return false end,
}
modules = { game_interface = { getMapPanel = function() return panel end } }
function tr(s) return s end
function getItemAttribute() return 0 end
dofile(dir .. '../game_lootfilter/lootfilterlogic.lua')
dofile(dir .. 'labelplates.lua')
dofile(dir .. 'groundlabelslogic.lua')
dofile(dir .. 'groundlabels.lua')
-- connect() is called inside init() with the panel upvalue of the module: take the handlers from the module's own call
function connect(obj, handlers) if obj == panel then connected = handlers end end
init()
local function cycle(ms) for _, c in ipairs(cycles) do if c.ms == ms then c.fn() end end end

-- the engine draws a tile's widget centred on its tile (the live client's convention: centre at the tile centre + 32 + margins, no
-- margins on a label block, O715), then the children follow it
local function placeBlocks()
  for _, t in pairs(tiles) do
    local w = t.widget
    if w and not w.destroyed then
      local cx = panelRect.width / 2 + (t.pos.x - PLAYER.x) * TILE
      local cy = panelRect.height / 2 + (t.pos.y - PLAYER.y) * TILE
      w.abs = { x = cx - w.size.w / 2, y = cy - w.size.h / 2 }
    end
  end
end

-- the server's answer to the module's `look`
local function answer(rowsByPos)
  local entries = {}
  for _, p in ipairs(rowsByPos) do entries[#entries + 1] = { p = { p.pos.x, p.pos.y, p.pos.z }, i = p.rows } end
  opcodeHandler(protocol, 230, json.encode({ action = 'tiles', data = { t = entries } }))
end

-- ---------------------------------------------------------------- a Rare shield on the ground, 2 tiles east
local pos = { x = 102, y = 100, z = 7 }
local shield = newItem(3425, 1, 1, { [1] = 4 })
addTile(pos, { shield })
cycle(400) -- the scan sees the tile and asks the server
local asked = sentOpcodes[#sentOpcodes]
eq(asked ~= nil and asked.data.action, 'look', 'the scan asks the server about the tile')
local rowShield = { s = 1, id = 3425, c = 1, nm = 'brawling great shield of insulation', r = 4, g = 'equipment', e = 162 }
answer({ { pos = pos, rows = { rowShield } } })
placeBlocks()
local lab = getLabels()
eq(#lab, 1, 'one label is drawn')
eq(lab[1] and lab[1].text:find('Brawling Great Shield Of Insulation', 1, true) ~= nil, true, 'with the item name: ' .. tostring(lab[1] and lab[1].text))
local function centreOfLabel()
  local l = getLabels()[1]
  return { x = l.rect.x + l.rect.width / 2, y = l.rect.y + l.rect.height / 2 }
end

local function click(at, button, upAt)
  button = button or MouseLeftButton
  local pressTaken = connected.onMousePress(panel, at, button)
  local releaseTaken = connected.onMouseRelease(panel, upAt or at, button)
  return pressTaken, releaseTaken
end

local at = centreOfLabel()
local _, taken = click(at)
eq(#moves, 1, 'a left click on the label moves the item')
eq(moves[1] and moves[1].thing, shield, 'it is that item')
eq(moves[1] and moves[1].pos.x, 65535, 'into the backpack slot') eq(moves[1] and moves[1].pos.y, 3, 'of the backpack')
eq(moves[1] and moves[1].count, 1, 'one of them')
eq(taken, true, 'the release is taken (the map does not also walk there)')

-- a click that is a drag (the pointer moved 10 px) is not a click
moves = {}
click(at, MouseLeftButton, { x = at.x + 10, y = at.y })
eq(#moves, 0, 'a drag moves nothing here (the engine drags the item)')

-- the labels are rebuilt between the press and the release (the timer text changed, a layout ran): the click still lands
moves = {}
local pressAt = centreOfLabel()
connected.onMousePress(panel, pressAt, MouseLeftButton)
clock = clock + 1 -- the despawn timer shows another second
rowShield.at = nil
cycle(1000) -- the timers tick
-- something changes the rows, so a layout runs and may build the label again
answer({ { pos = pos, rows = { rowShield } } })
placeBlocks()
connected.onMouseRelease(panel, centreOfLabel(), MouseLeftButton)
eq(#moves, 1, 'a click survives a layout between press and release')

-- the same after a longer wait: the second of the timer changes the text every layout
moves = {}
for _ = 1, 3 do
  clock = clock + 1
  connected.onMousePress(panel, centreOfLabel(), MouseLeftButton)
  answer({ { pos = pos, rows = { rowShield } } })
  placeBlocks()
  connected.onMouseRelease(panel, centreOfLabel(), MouseLeftButton)
end
eq(#moves, 3, 'every click lands, with the timer text changing under it')

-- a layout runs between the press and the release with no new answer (the despawn timer moved on a second, so the label text
-- differs and the widgets are built again: Alt pressed here forces the layout)
moves = {}
do
  local altDown = false
  g_keyboard.isAltPressed = function() return altDown end
  local before = getLabels()[1]
  connected.onMousePress(panel, centreOfLabel(), MouseLeftButton)
  clock = clock + 2
  altDown = true
  cycle(100) -- the Alt poll relayouts: the labels of this tile are built again
  placeBlocks()
  altDown = false
  cycle(100)
  placeBlocks()
  connected.onMouseRelease(panel, centreOfLabel(), MouseLeftButton)
  eq(#moves, 1, 'a click survives the labels being built again (a new second on the timer) between press and release')
  g_keyboard.isAltPressed = function() return false end
end

-- right button: the usual item menu, never a move
moves = {}
click(centreOfLabel(), MouseRightButton)
eq(#moves, 0, 'a right click does not pick up')

-- a click outside every label is nobody's
moves = {}
local _, tk = click({ x = 5, y = 5 })
eq(#moves, 0, 'a click elsewhere moves nothing') eq(tk, false, 'and is left to the map')

-- ---------------------------------------------------------------- a pile: the lower item is raised first
local pos2 = { x = 101, y = 99, z = 7 }
local top = newItem(2148, 5, 1) -- the engine only moves the candidate with the lowest stack position
local low = newItem(3425, 1, 2, { [1] = 4 })
addTile(pos2, { low, top })
cycle(400)
answer({ { pos = pos2, rows = { { s = 2, id = 3425, c = 1, nm = 'brawling great shield of insulation', r = 4, g = 'equipment' } } } })
placeBlocks()
moves = {}
sentOpcodes = {}
local l2
for _, l in ipairs(getLabels()) do if l.pos.x == pos2.x then l2 = l end end
eq(l2 ~= nil, true, 'the lower item of a pile has a label')
if l2 then
  click({ x = l2.rect.x + l2.rect.width / 2, y = l2.rect.y + l2.rect.height / 2 })
  eq(#moves, 0, 'a lower item is not moved at once')
  eq(sentOpcodes[#sentOpcodes] ~= nil and sentOpcodes[#sentOpcodes].data.action, 'raise', 'the server is asked to put it on top')
end

print(string.format('groundlabels_engine_test: %d checks, %d failed', checks, fails))
if fails > 0 then os.exit(1) end
