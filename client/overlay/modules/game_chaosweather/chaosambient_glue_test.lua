-- luajit chaosambient_glue_test.lua && lua5.3 chaosambient_glue_test.lua: chaosambient.lua against mocked widgets and timers:
-- nothing runs without a mood or with the option off, the timer stops while the window is hidden (one slow poll waits), the
-- widgets are two per kind at most visible, a reset leaves nothing behind.
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'chaosweather_logic.lua')
dofile(dir .. 'chaosambient_logic.lua')
local fails, checks = 0, 0
local function eq(a, b, what)
  checks = checks + 1
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

local clock, windowShown = 0, true
local events, nextId, created = {}, 0, {}
g_clock = { millis = function() return clock end }
g_logger = { warning = function() end }
g_window = { isVisible = function() return windowShown end }
function cycleEvent(fn, ms) nextId = nextId + 1; events[nextId] = { fn = fn, ms = ms }; return nextId end
function removeEvent(id) events[id] = nil end
local function count() local n = 0 for _ in pairs(events) do n = n + 1 end return n end
local function newWidget(name)
  local w = { name = name, visible = false, opacity = 0, destroyed = false, children = {} }
  function w:isDestroyed() return self.destroyed end
  function w:destroy() self.destroyed = true for _, c in ipairs(self.children) do c:destroy() end end
  function w:setVisible(v) self.visible = v end
  function w:isVisible() return self.visible end
  function w:setOpacity(o) self.opacity = o; self.opacityCalls = (self.opacityCalls or 0) + 1 end
  function w:setImageSource(s) self.image = s end
  function w:setImageRect(r) self.rect = r; self.rectCalls = (self.rectCalls or 0) + 1 end
  function w:getSize() return { width = 1000, height = 700 } end
  function w:fill() end
  function w:insertChild() end
  return w
end
g_ui = { createWidget = function(style, parent) local w = newWidget(style); created[#created + 1] = w; if parent then parent.children[#parent.children + 1] = w end return w end }
modules = { game_interface = { getMapPanel = function() return newWidget('panel') end } }
dofile(dir .. 'chaosambient.lua')
local M = ChaosAmbient

local function run(ms, step)
  for _ = 1, math.floor(ms / step) do
    clock = clock + step
    local snap = {}
    for id, e in pairs(events) do snap[#snap + 1] = { id = id, e = e } end
    for _, x in ipairs(snap) do if events[x.id] and x.e.ms == step then x.e.fn() end end
  end
end
local function shown()
  local n = 0
  for _, w in ipairs(created) do if w.name == 'ChaosWeatherLayer' and w.visible and not w.destroyed then n = n + 1 end end
  return n
end

eq(count(), 0, 'nothing runs at the start'); eq(#created, 0, 'no widget at the start')
M.setKind(nil, 100); eq(count(), 0, 'no mood: still nothing')
M.setKind('snow', 100); eq(count(), 0, 'an unknown mood: nothing')
M.setKind('embers', 1000)
eq(count(), 1, 'a mood starts one timer'); eq(#created, 1 + #ChaosAmbientLogic.LAYERS, 'one root and six layers made')
run(1500, 50)
eq(shown(), 2, 'embers show two layers')
M.setKind('motes', 400)
run(600, 50)
eq(shown(), 2, 'a mood change cross-fades and ends on two layers')
-- the window is hidden: the timer stops, the layers go, a slow poll waits
windowShown = false
run(100, 50)
eq(shown(), 0, 'hidden window: no layer shown')
local ticking, polling = 0, 0
for _, e in pairs(events) do if e.ms == 50 then ticking = ticking + 1 elseif e.ms == 1000 then polling = polling + 1 end end
eq(ticking, 0, 'hidden window: no drift timer'); eq(polling, 1, 'hidden window: one slow poll')
run(3000, 1000); eq(shown(), 0, 'still hidden: still nothing')
windowShown = true
run(2000, 1000)
eq(polling, 1, 'one poll')
local t2 = 0
for _, e in pairs(events) do if e.ms == 50 then t2 = t2 + 1 end end
eq(t2, 1, 'back: the drift timer runs again')
run(3000, 50); eq(shown(), 2, 'back: the mood fades in again')
-- the option off hides it at once and stops the timer
M.setEnabled(false)
eq(shown(), 0, 'option off: hidden at once'); eq(count(), 0, 'option off: no timer, no poll')
M.setKind('dust', 100); eq(count(), 0, 'option off: a new mood starts nothing')
M.setEnabled(true); eq(count(), 1, 'option on: it starts again')
run(3000, 50); eq(shown(), 2, 'dust: two layers')
-- no mood ends the timer after the fade
M.setKind(nil, 500)
run(2000, 50); eq(count(), 0, 'the mood is gone: the timer stopped'); eq(shown(), 0, 'and the layers are hidden')
-- a reset (game end) leaves nothing
M.setKind('embers', 100); run(500, 50)
M.reset(nil); eq(count(), 0, 'reset: no timers'); eq(M.state().kind, nil, 'reset: no mood')
local alive = 0
for _, w in ipairs(created) do if not w.destroyed then alive = alive + 1 end end
eq(alive, 0 + (function() local n = 0 for _, w in ipairs(created) do if not w.destroyed and w.name == 'panel' then n = n + 1 end end return n end)(), 'reset: every widget destroyed')

-- O235: dust has no twinkle, so once it has faded in the opacity is set no more, and the slow drift calls setImageRect only
-- on the ticks where the whole-pixel rectangle moved
M.setEnabled(true)
M.setKind('dust', 100); run(2000, 50)
local layers, op0, rect0 = {}, 0, 0
for _, w in ipairs(created) do
  if w.name == 'ChaosWeatherLayer' and w.visible and not w.destroyed then layers[#layers + 1] = w; op0 = op0 + (w.opacityCalls or 0); rect0 = rect0 + (w.rectCalls or 0) end
end
eq(#layers, 2, 'dust shows two layers')
run(1000, 50)
local op1, rect1 = 0, 0
for _, w in ipairs(layers) do op1 = op1 + (w.opacityCalls or 0); rect1 = rect1 + (w.rectCalls or 0) end
eq(op1, op0, 'dust: a steady opacity is not set again')
eq(rect1 > rect0, true, 'dust: the drift still moves the picture')
eq(rect1 - rect0 < 2 * 20, true, 'dust: setImageRect only when the rectangle moved (less than every tick)')

if fails > 0 then print(string.format('chaosambient_glue: %d of %d checks failed', fails, checks)) os.exit(1) end
print(string.format('chaosambient_glue: all %d checks passed', checks))
