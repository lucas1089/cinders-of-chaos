-- RmlUi spike (docs/RMLUI_SPIKE.md): one test window written in HTML (rmltest.rml) and RCSS (rmltest.rcss), driven
-- from Lua through g_rml. Only a client built with -DCHAOS_RMLUI=ON has g_rml; without it every function here is a no-op.
--   ChaosRmlTest.open()  /  .close()  /  .toggle()      (hotkey Ctrl+Alt+F10 when g_rml exists)

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

function init()
  if g_rml and g_keyboard then
    g_keyboard.bindKeyDown('Ctrl+Alt+F10', ChaosRmlTest.toggle)
  end
end

function terminate()
  if g_rml then
    ChaosRmlTest.close()
    if g_keyboard then pcall(function() g_keyboard.unbindKeyDown('Ctrl+Alt+F10', ChaosRmlTest.toggle) end) end
  end
end
