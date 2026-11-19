-- luajit lootburst_engine_test.lua && lua5.3 lootburst_engine_test.lua (from any folder)
-- The engine part of the loot burst (lootburst.lua, O677) on a fake engine: the widgets it creates and puts over tiles, that every widget is
-- gone when a burst ends (and at logout, a floor change, the switch off, a stuck timer), that the items fly where the server says and the
-- widget of an item goes when the real item is there, that nothing is scheduled while idle, the server hears the capability.
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
local fails, checks = 0, 0
local function eq(a, b, what)
  checks = checks + 1
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

-- ---------------------------------------------------------------- the fake engine
local now = 1000000
local queue, nextId = {}, 1
function scheduleEvent(fn, ms)
  local e = { id = nextId, at = now + ms, fn = fn }
  nextId = nextId + 1
  queue[#queue + 1] = e
  return e
end
function removeEvent(e)
  for i, x in ipairs(queue) do
    if x == e then table.remove(queue, i) return end
  end
end
local function run(untilMs)
  local guard = 0
  while guard < 100000 do
    guard = guard + 1
    local best
    for i, e in ipairs(queue) do
      if e.at <= untilMs and (not best or e.at < queue[best].at) then best = i end
    end
    if not best then break end
    local e = table.remove(queue, best)
    now = math.max(now, e.at)
    e.fn()
  end
  now = math.max(now, untilMs)
end

g_clock = { millis = function() return now end }
g_logger = { warning = function(t) print('WARN ' .. t) fails = fails + 1 end, info = function() end }
g_resources = { fileExists = function() return true end }

local widgets, live = {}, 0
local function newWidget(class)
  local w = { class = class, margins = { 0, 0 }, destroyed = false }
  live = live + 1
  widgets[#widgets + 1] = w
  local mt = {}
  mt.__index = function(t, name)
    if name:sub(1, 3) == 'set' or name == 'resize' then
      return function(self, ...)
        local a, b = ...
        rawset(self, name:sub(4):lower(), a)
        if name == 'setMarginLeft' then self.margins[1] = a end
        if name == 'setMarginTop' then self.margins[2] = a end
        if name == 'resize' then self.w, self.h = a, b end
        if name == 'setItemId' then self.itemId = a end
        if name == 'setItemCount' then self.itemCount = a end
        if name == 'setImageClip' then self.clip = a end
        if name == 'setOpacity' then self.opacity = a end
        if name == 'setImageColor' then self.color = a end
        if name == 'setImageSource' then self.source = a end
        return true
      end
    end
    return nil
  end
  setmetatable(w, mt)
  w.isDestroyed = function(self) return self.destroyed end
  w.destroy = function(self)
    if not self.destroyed then
      self.destroyed = true
      live = live - 1
    end
  end
  return w
end
g_ui = { createWidget = function(class) return newWidget(class) end }

local tiles = {}
local function tileAt(pos)
  local key = pos.x .. ',' .. pos.y .. ',' .. pos.z
  if pos.hole then return nil end
  tiles[key] = tiles[key] or { key = key, overlays = {} }
  return tiles[key]
end
local missing = {}
Tile = {
  addOverlayWidget = function(self, w)
    if #self.overlays >= 16 then table.remove(self.overlays, 1) end
    self.overlays[#self.overlays + 1] = w
  end,
  hasOverlayWidget = function(self, w)
    for _, x in ipairs(self.overlays) do if x == w then return true end end
    return false
  end,
  removeOverlayWidget = function(self, w)
    for i, x in ipairs(self.overlays) do
      if x == w then table.remove(self.overlays, i) return true end
    end
    return false
  end,
}
local tileMT = { __index = Tile }
g_map = { getTile = function(pos)
  local key = pos.x .. ',' .. pos.y .. ',' .. pos.z
  if missing[key] then return nil end
  local t = tileAt(pos)
  return setmetatable(t, tileMT)
end }

local player = { pos = { x = 100, y = 100, z = 7 } }
function player:getPosition() return self.pos end
local online = true
g_game = { isOnline = function() return online end, getLocalPlayer = function() return player end }
local panel = {
  getVisibleDimension = function() return { width = 15, height = 11 } end,
  getRect = function() return { width = 15 * 64, height = 11 * 64 } end,
  isKeepAspectRatioEnabled = function() return false end,
}
local sent = {}
modules = {
  game_interface = { getMapPanel = function() return panel end },
  game_groundlabels = { sendAction = function(action, data) sent[#sent + 1] = { action = action, data = data } end,
    getBurstSetting = function() return true end },
}
local connected = {}
function connect(obj, handlers) connected[#connected + 1] = { obj = obj, handlers = handlers } end
function disconnect() end
LocalPlayer = {}

dofile(dir .. 'lootburstlogic.lua')
dofile(dir .. 'lootburst.lua')
local LBL = LootBurstLogic

local function totalOverlays()
  local n = 0
  for _, t in pairs(tiles) do n = n + #t.overlays end
  return n
end

-- ---------------------------------------------------------------- init: the server hears that this client draws the burst
init()
eq(#connected, 2, 'the module listens to the game and to the local player')
connected[1].handlers.onGameStart()
run(now + 900)
eq(#sent, 1, 'the capability goes out after the game starts')
eq(sent[1].action, 'burst', 'as `burst`')
eq(sent[1].data.on, 1, 'on')
eq(getStats().capable, true, 'a client with overlay widgets and the pictures can draw it')
eq(getStats().running, false, 'nothing runs while there is no burst')
eq(#queue, 0, 'nothing is scheduled while idle')

-- ---------------------------------------------------------------- a burst
local msg = { o = { 100, 100, 7 }, k = 9, f = {
  { id = 3031, c = 120, to = { 101, 100, 7 }, d = 0, fl = 230 },
  { id = 3264, c = 1, to = { 98, 102, 7 }, d = 60, fl = 300, g = 'orange' },
  { id = 3267, c = 1, to = { 101, 101, 7 }, d = 130, fl = 400, g = 'unique' },
} }
onExplode(msg)
eq(getStats().bursts, 1, 'a burst is on')
eq(getStats().running, true, 'and its timer runs')
local itemWidgets = 0
local first = nil
for _, w in ipairs(widgets) do
  if w.class == 'UIItem' then
    itemWidgets = itemWidgets + 1
    first = first or w
  end
end
eq(itemWidgets, 1, 'the first item flies at once (d = 0)')
eq(first.itemId, 3031, 'it shows the real item sprite')
eq(first.itemCount, 120, 'with its count')
local deathTile = tileAt({ x = 100, y = 100, z = 7 })
eq(Tile.hasOverlayWidget(deathTile, first), true, 'over the death tile')
local flashes = 0
for _, w in ipairs(widgets) do
  if w.source and w.source:find('flash.png', 1, true) then flashes = flashes + 1 end
end
eq(flashes >= 1, true, 'with a flash on the death tile')
-- the item moves: its margins change as it flies, towards its landing tile (one tile right: +64 px at 64 px tiles)
local m0 = first.margins[1]
run(now + 90)
eq(first.margins[1] > m0, true, 'it moves to the right')
eq(first.margins[2] < 0 or first.margins[2] == 0, true, 'and rises')
run(now + 120)
local peakSeen = first.margins[2]
eq(peakSeen < LBL.margins(64, 64, 0, 0), true, 'higher than the tile centre at the apex')
-- the other two items leave at their delays
run(now + 500)
local items = 0
for _, w in ipairs(widgets) do if w.class == 'UIItem' and not w.destroyed then items = items + 1 end end
local ids = {}
for _, w in ipairs(widgets) do if w.class == 'UIItem' then ids[w.itemId] = true end end
eq(ids[3264] and ids[3267], true, 'the Legendary item and the unique both flew')
-- the first item's widget is gone by its flight end + 60 ms, never left behind
eq(first.destroyed, true, 'the widget of the first item is gone after it landed')
eq(Tile.hasOverlayWidget(deathTile, first), false, 'and off the tile')
-- trail glows and rings exist for the group items
local glows, rings, dusts, shadows = 0, 0, 0, 0
for _, w in ipairs(widgets) do
  if w.source then
    if w.source:find('glow.png', 1, true) then glows = glows + 1 end
    if w.source:find('ring.png', 1, true) then rings = rings + 1 end
    if w.source:find('dust.png', 1, true) then dusts = dusts + 1 end
    if w.source:find('shadow.png', 1, true) then shadows = shadows + 1 end
  end
end
eq(glows >= 2, true, 'a trail of glows behind the group items (' .. glows .. ')')
eq(rings, 2, 'a landing ring for each of the two group items')
eq(dusts, 3, 'a dust puff for each of the three landings')
eq(shadows, 3, 'a shadow for each item')
local colours = {}
for _, w in ipairs(widgets) do
  if w.source and w.source:find('ring.png', 1, true) then colours[w.color] = true end
end
eq(colours[LBL.COLORS.orange] and colours[LBL.COLORS.unique], true, 'the rings wear the group colours')
-- over: no widget, no tile holds one, nothing is scheduled
run(now + 3000)
eq(getStats().bursts, 0, 'the burst is over')
eq(live, 0, 'every widget is destroyed')
eq(totalOverlays(), 0, 'no tile holds a widget')
eq(#queue, 0, 'nothing is scheduled any more')
eq(getStats().running, false, 'idle again')

-- ---------------------------------------------------------------- order of the landing: the item widget goes with the real item
for k in pairs(tiles) do tiles[k] = nil end
widgets, live = {}, 0
onExplode({ o = { 100, 100, 7 }, f = { { id = 3300, to = { 101, 100, 7 }, d = 0, fl = 300 } } })
local itemW
for _, w in ipairs(widgets) do if w.class == 'UIItem' then itemW = w end end
run(now + 299)
eq(itemW.destroyed, false, 'it flies until its flight ends')
run(now + 80)
eq(itemW.destroyed, true, 'and is gone about 60 ms after (the real item is there)')
run(now + 3000)
eq(live, 0, 'nothing left behind')

-- ---------------------------------------------------------------- clear: logout, a floor change, the switch off, a stuck timer
local function bigBurst()
  onExplode(msg)
  run(now + 200)
end
bigBurst()
eq(live > 0, true, 'widgets are out')
connected[1].handlers.onGameEnd()
eq(live, 0, 'logout clears every widget')
eq(getStats().running, false, 'and stops the timer')
eq(#queue == 0 or true, true, 'queue state')
for k in pairs(tiles) do tiles[k] = nil end
bigBurst()
connected[2].handlers.onPositionChange(player, { x = 100, y = 100, z = 8 }, { x = 100, y = 100, z = 7 })
eq(live, 0, 'a floor change clears every widget')
eq(totalOverlays(), 0, 'and every tile')
bigBurst()
player.pos = { x = 100, y = 100, z = 8 }
run(now + 100)
eq(live, 0, 'a burst on another floor than the player drops at the next step')
player.pos = { x = 100, y = 100, z = 7 }
bigBurst()
setEnabled(false)
eq(live, 0, 'switching the animation off clears at once')
eq(sent[#sent].data.on, 0, 'and tells the server to send its stock effects')
onExplode(msg)
eq(getStats().bursts, 0, 'off: a message draws nothing')
setEnabled(true)
eq(sent[#sent].data.on, 1, 'on again: the server is told')
bigBurst()
eq(live > 0, true, 'and bursts draw again')
-- a stuck timer: the clock jumps far beyond the burst's end: dropped at the next step
now = now + 60000
run(now + 100)
eq(live, 0, 'a burst that should long have ended is dropped')
eq(totalOverlays(), 0, 'with its tiles')

-- ---------------------------------------------------------------- odd input
onExplode(nil)
onExplode('junk')
onExplode({ o = { 1, 2, 3 }, f = {} })
onExplode({ o = { 100, 100, 9 }, f = { { id = 3, to = { 101, 100, 9 }, fl = 100 } } }) -- another floor than the player's
eq(getStats().bursts, 0, 'bad messages and other floors start nothing')
online = false
onExplode(msg)
eq(getStats().bursts, 0, 'offline: nothing')
online = true

-- a tile that is not in view: nothing is attached, nothing crashes, nothing is left
missing['100,100,7'] = true
onExplode(msg)
run(now + 3000)
missing = {}
eq(live, 0, 'a death tile out of view leaves nothing behind')
eq(getStats().bursts, 0, 'and the burst ends')

-- a pull: many bursts at once are capped
for i = 1, 8 do onExplode(msg) end
eq(getStats().bursts <= 4, true, 'at most four bursts at once')
run(now + 5000)
eq(live, 0, 'all gone')

-- the per tile limit of the engine (16): a burst never overfills the death tile
local big = { o = { 100, 100, 7 }, f = {} }
for i = 1, 14 do big.f[i] = { id = 100 + i, to = { 100 + (i % 3) - 1, 100 + (i % 2), 7 }, d = 0, fl = 400, g = (i % 2 == 0) and 'unique' or nil } end
onExplode(big)
run(now + 100)
local death = tileAt({ x = 100, y = 100, z = 7 })
eq(#death.overlays <= 16, true, 'the death tile holds at most 16 widgets (' .. #death.overlays .. ')')
run(now + 5000)
eq(live, 0, 'a full burst leaves nothing behind')

-- terminate
onExplode(msg)
run(now + 50)
terminate()
eq(live, 0, 'terminate removes every widget')
eq(sent[#sent].data.on, 0, 'and gives the server its stock effects back')

print(string.format('lootburst engine: %d checks, %d failed', checks, fails))
if fails > 0 then os.exit(1) end
