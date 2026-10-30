-- RmlUi spike (docs/RMLUI_SPIKE.md): one test window written in HTML (rmltest.rml) and RCSS (rmltest.rcss), driven
-- from Lua through g_rml. Only a client built with -DCHAOS_RMLUI=ON has g_rml; without it every function here is a no-op.
--   ChaosRmlTest.open()  /  .close()  /  .toggle()      (hotkey Ctrl+Alt+F10 when g_rml exists)
-- Phase 2 (RmlUi layer production ready): the window also shows hover, scroll (wheel, scroll bar, finger drag), a text field
-- and the reload of the module (reloader) for the checks in docs/RMLUI_SPIKE.md.

ChaosRmlTest = ChaosRmlTest or {}

local PATH = '/modules/client_chaos_rmltest/'
local ROWS = 30

local doc = 0
local round = 0

-- Row text: a pure function so the test can check it without a client.
function ChaosRmlTest.rowsRml(count, escape, label, value)
  local out = {}
  for i = 1, count do
    out[#out + 1] = string.format('<div class="row%s"><span class="name">%s</span><span class="value">%s</span></div>', -- i18n-ok: markup
      i % 2 == 0 and ' alt' or '', escape(string.format(label, i)), escape(value(i)))
  end
  return table.concat(out)
end

local function fill()
  local rows = ChaosRmlTest.rowsRml(ROWS, g_rml.escape, tr('Test row %d'), function(i)
    return tostring((i * 37 + round * 11) % 1000)
  end)
  g_rml.setInnerRml(doc, 'list', rows)
  g_rml.setText(doc, 'subtitle', string.format(tr('%d rows, refreshed %d times'), ROWS, round))
end

local function onEvent(docId, elementId, eventType)
  if docId ~= doc or eventType ~= 'click' then return end
  if elementId == 'x' or elementId == 'done' then
    ChaosRmlTest.close()
  elseif elementId == 'refresh' then
    round = round + 1
    fill()
  end
end

-- Touch check (Ctrl+Alt+F11): the event sequence of the Android window for one finger drag over the list, fed to the layer
-- with g_rml.injectMouse. Steps are data (a pure function), so the test can check them without a client.
-- Android order (androidwindow.cpp): Move, Press(touch), Moves; after 8 px a Move back to the start and Press(left);
-- at the end Release(touch), Release(left).
function ChaosRmlTest.touchSteps(x, y, dy, step)
  local steps = { { 'move', x, y, 'left' }, { 'press', x, y, 'touch' } }
  local pressed, py = false, y
  local n = math.floor(math.abs(dy) / step)
  local dir = dy < 0 and -1 or 1
  for i = 1, n do
    py = y + dir * step * i
    if not pressed and math.abs(py - y) > 8 then
      pressed = true
      steps[#steps + 1] = { 'move', x, y, 'left' }
      steps[#steps + 1] = { 'press', x, y, 'left' }
    end
    steps[#steps + 1] = { 'move', x, py, 'left' }
  end
  steps[#steps + 1] = { 'release', x, py, 'touch' }
  steps[#steps + 1] = { 'release', x, py, 'left' }
  return steps
end

function ChaosRmlTest.touchDemo()
  if not ChaosRmlTest.available() or doc == 0 then return false end
  local r = g_rml.getRect(doc, 'list')
  local x, y = r.x + math.floor(r.width / 2), r.y + math.floor(r.height / 2)
  local steps = ChaosRmlTest.touchSteps(x, y, -90, 6) -- finger up 90 px = the list moves down 90 px
  local before = g_rml.getScrollTop(doc, 'list')
  local i = 0
  local function nextStep()
    i = i + 1
    local st = steps[i]
    if not st then
      g_logger.info(string.format('RMLTEST touch: scrollTop %d -> %d, pointer over RmlUi after release: %s', -- i18n-ok: log
        before, g_rml.getScrollTop(doc, 'list'), tostring(g_rml.isPointerOver())))
      return
    end
    g_rml.injectMouse(st[1], st[2], st[3], st[4])
    scheduleEvent(nextStep, 16)
  end
  nextStep()
  return true
end

-- Scale check (Ctrl+Alt+F12): the engine interface scale 1 and 2 (g_app.scale), logged with what the layer sees.
function ChaosRmlTest.toggleScale(n)
  if type(n) ~= 'number' then
    ChaosRmlTest.scale2 = not ChaosRmlTest.scale2
    n = ChaosRmlTest.scale2 and 2 or 1
  end
  g_app.scale(n)
  scheduleEvent(function()
    g_logger.info(string.format('RMLTEST scale: engine %.2f, dp ratio %.2f', g_rml.getEngineScale(), g_rml.getDpRatio())) -- i18n-ok: log
  end, 500)
end

function ChaosRmlTest.available()
  return g_rml ~= nil and g_rml.init()
end

function ChaosRmlTest.open()
  if not ChaosRmlTest.available() then return false end
  if doc ~= 0 then g_rml.show(doc) return true end
  g_rml.loadFont(PATH .. 'fonts/AlegreyaSans-Medium.ttf', true)
  g_rml.loadFont(PATH .. 'fonts/AlegreyaSC-Bold.ttf', false)
  doc = g_rml.loadDocument(PATH .. 'rmltest.rml')
  if doc == 0 then return false end
  g_rml.setEventCallback(onEvent)
  g_rml.setText(doc, 'title', tr('RmlUi test window'))
  g_rml.setText(doc, 'refresh', tr('Refresh'))
  g_rml.setText(doc, 'done', tr('Close'))
  round = 0
  fill()
  g_rml.show(doc)
  return true
end

function ChaosRmlTest.close()
  if doc ~= 0 then
    g_rml.close(doc)
    doc = 0
  end
end

function ChaosRmlTest.toggle()
  if doc ~= 0 and g_rml.isVisible(doc) then ChaosRmlTest.close() else ChaosRmlTest.open() end
end

-- Scripted run for the checks without a keyboard (Xvfb, CI): the environment variable CHAOS_RMLTEST holds steps separated by
-- semicolons: open, touch, scale, scale<N> (g_app.scale(N)), close, wait<ms>. Example: CHAOS_RMLTEST="open;wait3000;touch;wait4000;scale". Pure: the
-- parser only turns the text into steps, so the test can check it.
function ChaosRmlTest.parseScript(text)
  local steps = {}
  for word in tostring(text or ''):gmatch('[^;%s]+') do
    local ms = word:match('^wait(%d+)$')
    if ms then
      steps[#steps + 1] = { 'wait', tonumber(ms) }
    elseif word:match('^scale%d$') then
      steps[#steps + 1] = { 'scale', tonumber(word:sub(6)) }
    elseif word == 'open' or word == 'touch' or word == 'scale' or word == 'close' then
      steps[#steps + 1] = { word }
    end
  end
  return steps
end

local function runScript(steps)
  local i = 0
  local function nextStep()
    i = i + 1
    local st = steps[i]
    if not st then return end
    if st[1] == 'wait' then return scheduleEvent(nextStep, st[2]) end
    if st[1] == 'open' then ChaosRmlTest.open()
    elseif st[1] == 'touch' then ChaosRmlTest.touchDemo()
    elseif st[1] == 'scale' then ChaosRmlTest.toggleScale(st[2])
    elseif st[1] == 'close' then ChaosRmlTest.close() end
    scheduleEvent(nextStep, 50)
  end
  nextStep()
end

-- Hot reload: the module reloader calls terminate() and then init() again. An open window is closed, the style sheet and
-- template caches are dropped (so an edited .rml or .rcss is read again) and the window opens again from the files.
-- ChaosRmlTest is a global of an unsandboxed module, so the flag survives the reload.
function init()
  if g_rml and g_logger then g_logger.info('RMLTEST module ready: Ctrl+Alt+F10 open, F11 touch check, F12 scale') end
  if g_rml and g_keyboard then
    g_keyboard.bindKeyDown('Ctrl+Alt+F10', ChaosRmlTest.toggle)
    g_keyboard.bindKeyDown('Ctrl+Alt+F11', ChaosRmlTest.touchDemo)
    g_keyboard.bindKeyDown('Ctrl+Alt+F12', function() ChaosRmlTest.toggleScale() end)
  end
  if g_rml and os.getenv and os.getenv('CHAOS_RMLTEST') then runScript(ChaosRmlTest.parseScript(os.getenv('CHAOS_RMLTEST'))) end
  if g_rml and ChaosRmlTest.reopen then
    ChaosRmlTest.reopen = false
    ChaosRmlTest.open()
  end
end

function terminate()
  if g_rml then
    ChaosRmlTest.reopen = doc ~= 0
    ChaosRmlTest.close()
    if g_rml.clearCaches then g_rml.clearCaches() end
    if g_keyboard then
      pcall(function() g_keyboard.unbindKeyDown('Ctrl+Alt+F10', ChaosRmlTest.toggle) end)
      pcall(function() g_keyboard.unbindKeyDown('Ctrl+Alt+F11', ChaosRmlTest.touchDemo) end)
      pcall(function() g_keyboard.unbindKeyDown('Ctrl+Alt+F12', ChaosRmlTest.toggleScale) end)
    end
  end
end
