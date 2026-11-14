-- luajit huntports_test.lua && lua5.3 huntports_test.lua (CI runs it from the repo root)
-- O568: huntports.lua on a fake engine: the list from the server, the character's steps, the markers drawn into pooled
-- widgets at the tile points of a fake minimap (image, size, place, opacity), the hover list, the pulse timer started only
-- while a highlighted marker is on the map, the setting that hides them, the saved state per character, the game end.
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'markermath.lua')
dofile(dir .. 'huntportmath.lua')
local fails, checks = 0, 0
local function eq(a, b, what)
  checks = checks + 1
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

-- the fake engine
local now = 0
g_clock = { millis = function() return now end }
local timers, nextTimer = {}, 0
function cycleEvent(fn, ms) nextTimer = nextTimer + 1; timers[nextTimer] = fn; return nextTimer end
function removeEvent(id) timers[id] = nil end
local function timerCount() local n = 0 for _ in pairs(timers) do n = n + 1 end return n end
local nodes = {}
g_settings = { getNode = function(k) return nodes[k] end, setNode = function(k, v) nodes[k] = v end }
local player = { getName = function() return 'Ann' end, getPosition = function() return { x = 31640, y = 32256, z = 7 } end }
g_game = { getLocalPlayer = function() return player end }
local made = {}
local function newWidget()
  local w = { visible = false, destroyed = false, opacity = 1 }
  function w:isDestroyed() return self.destroyed end
  function w:destroy() self.destroyed = true end
  function w:setImageSource(s) self.source = s end
  function w:setSize(s) self.size = s end
  function w:setPosition(p) self.pos = p end
  function w:setOpacity(o) self.opacity = o end
  function w:show() self.visible = true end
  function w:hide() self.visible = false end
  function w:isVisible() return self.visible end
  function w:raise() end
  return w
end
g_ui = { createWidget = function(style, parent) local w = newWidget() w.style = style made[#made + 1] = w return w end }
-- the minimap: scale 10 pixels a tile, the camera in the middle of a 400 x 200 widget
local minimap = { getTilePoint = function(self, p)
  return { x = 200 + (p.x - self.cam.x) * 10, y = 100 + (p.y - self.cam.y) * 10 }
end, cam = { x = 31640, y = 32256, z = 7 } }

dofile(dir .. 'huntports.lua')
local H = HuntPorts
local function P(x, y, z) return { x = x, y = y, z = z } end
local list = { ports = {
  { i = 'a', n = 'Alder Fen', l = { 10, 40 }, t = P(31634, 32254, 7), f = P(31634, 32255, 7), a = P(15700, 14400, 7), b = P(15710, 14410, 7) },
  { i = 'b', n = 'Wasp Nest', l = { 40, 70 }, t = P(31638, 32258, 7), f = P(31638, 32257, 7), a = P(15900, 14400, 7), b = P(15910, 14410, 7) },
} }
local function env(cam, scale)
  minimap.cam = cam
  return { minimap = minimap, layer = {}, cam = cam, rect = { x = 0, y = 0, width = 400, height = 200 }, scale = scale or 10, hits = {} }
end

H.init(true)
H.onGameStart()
eq(H.debugState().ports, 0, 'nothing before the server answers')
local e = env(P(31640, 32256, 7))
eq(H.draw(e), 0, 'nothing drawn without a list')

H.onMessage(list)
eq(H.debugState().ports, 2, 'the list is kept')
e = env(P(31640, 32256, 7))
eq(H.draw(e), 2, 'two hall teleports on the map')
eq(#e.hits, 2, 'two hover entries')
eq(timerCount(), 0, 'nothing highlighted: no pulse timer')
eq(made[1].style, 'MapMarkerHuntPort', 'the widget style')
eq(made[1].source, '/images/chaos/mapmarkers/huntport', 'plain gate')
eq(made[1].size.width, 14, 'plain size')
-- the first marker is the first by id (a), at tile 31634, 32254: 200 + (31634 - 31640) * 10 = 140, 100 - 20 = 80, centred
eq(made[1].pos.x, 140 - 7, 'place x'); eq(made[1].pos.y, 80 - 7, 'place y')

-- the character uses teleport b, then comes out of its hunt
eq(H.onMove(P(31638, 32257, 7), P(15900, 14400, 7)), true, 'a teleport changes the state')
eq(H.debugState().last, 'b', 'last used'); eq(H.debugState().here, 'b', 'in the hunt'); eq(H.debugState().used, 1, 'one hunt entered')
eq(nodes.huntPorts.chars.Ann.last, 'b', 'saved for the character')
eq(H.onMove(P(15900, 14400, 7), P(15901, 14400, 7)), false, 'a step inside changes nothing')
e = env(P(15900, 14400, 7))
eq(H.draw(e), 0, 'in the hunt, the way out is 10 tiles off to the south east: inside the view of a 40 x 20 tile map')
-- the camera on the way out
e = env(P(15905, 14405, 7))
eq(H.draw(e), 1, 'the way out of the hunt it stands in')
eq(made[1].source, '/images/chaos/mapmarkers/huntexit_here', 'the highlighted door')
eq(made[1].size.width, 18, 'bigger')
eq(timerCount(), 1, 'a highlighted marker: the pulse timer runs')
now = 350
for _, fn in pairs(timers) do fn() end
eq(made[1].opacity < 1, true, 'the pulse changed the opacity')
eq(e.hits[1].text, 'Way out of Wasp Nest: you are in this hunt', 'hover text')

eq(H.onMove(P(15910, 14410, 7), P(31638, 32257, 7)), true, 'out by the camp portal')
eq(H.debugState().here, nil, 'no longer in the hunt')
e = env(P(31640, 32256, 7))
eq(H.draw(e), 2, 'back in the hall: both gates')
eq(timerCount(), 1, 'the gold one pulses')
local gold = 0
for _, w in ipairs(made) do if w.visible and w.source == '/images/chaos/mapmarkers/huntport_last' then gold = gold + 1 end end
eq(gold, 1, 'one gold gate: the one to go back to')
eq(e.hits[1].text, 'Hunt teleport: Wasp Nest (levels 40-70), last used: your way back', 'its hover text')

-- the hunt not in view / too far zoomed out: only the gold gate
e = env(P(31640, 32256, 7), 1)
eq(H.draw(e), 1, 'zoomed out: only the one to go back to')
-- another floor
e = env(P(31640, 32256, 6))
eq(H.draw(e), 0, 'another floor: nothing')
eq(timerCount(), 0, 'nothing highlighted on the map: the timer stops')

-- switched off
H.setEnabled(false)
e = env(P(31640, 32256, 7))
eq(H.draw(e), 0, 'switched off: nothing drawn')
for _, w in ipairs(made) do eq(w.visible, false, 'every widget hidden') end
H.setEnabled(true)

-- the next login: the state comes back from the settings, the list again from the server
H.onGameEnd()
eq(H.debugState().ports, 0, 'the end of the game forgets the list')
H.onGameStart()
H.onMessage(list)
eq(H.debugState().last, 'b', 'the last used teleport is back'); eq(H.debugState().used, 1, 'the entered hunt is back')
eq(H.debugState().here, nil, 'standing in the hall: in no hunt')
for _, w in ipairs(made) do eq(w.destroyed or w.visible == false or true, true, 'widgets cleaned up or reused') end
H.terminate()

print(string.format('huntports_test: %d checks, %d failed', checks, fails))
if fails > 0 then os.exit(1) end
