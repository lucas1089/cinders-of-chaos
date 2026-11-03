-- luajit perf_test.lua && lua5.3 perf_test.lua: perf.lua against a mocked engine (CI runs every
-- client/overlay/modules/*/*_test.lua from the repo root). Record, the wrap of the timers, the files, put back.
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
local fails, checks = 0, 0
local function eq(a, b, what)
  checks = checks + 1
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

-- ---------------------------------------------------------------- engine mock
local ms, us = 100000, 0
local events, nextId = {}, 0
local function addTimer(kind, fn, delay)
  nextId = nextId + 1
  local e = { id = nextId, kind = kind, fn = fn, delay = delay }
  events[nextId] = e
  return e
end
local function engineSchedule(fn, delay) return addTimer('schedule', fn, delay) end
local function engineCycle(fn, delay) return addTimer('cycle', fn, delay) end
local function engineAdd(fn) return addTimer('add', fn, 0) end
scheduleEvent, cycleEvent, addEvent = engineSchedule, engineCycle, engineAdd
removeEvent = function(e) if e then events[e.id] = nil end end
local opcodes = {}
local function engineRegister(op, cb) opcodes[op] = cb end
ProtocolGame = { registerExtendedOpcode = engineRegister, registerExtendedJSONOpcode = engineRegister }

g_clock = { millis = function() return ms end, realMillis = function() return ms end, realMicros = function() return us end }
g_app = { getFps = function() return 58 end, isMobile = function() return false end, getVersion = function() return '1.0' end,
  getOs = function() return 'linux' end }
local settings = {}
g_settings = { getBoolean = function(k) return settings[k] == true end, set = function(k, v) settings[k] = v end }
local keys = {}
g_keyboard = { bindKeyDown = function(k, f) keys[k] = f end, unbindKeyDown = function(k) keys[k] = nil end }
local files = {}
g_resources = { writeFileContents = function(p, t) files[p] = t; return true end, getWriteDir = function() return '/home/x/' end }
g_window = { getWidth = function() return 1920 end, getHeight = function() return 1080 end,
  setClipboardText = function(t) g_window.clip = t end }
g_logger = { info = function() end, warning = function(t) print('warning ' .. t) end }
g_game = { isOnline = function() return false end }
g_map = {}
local function mod(name, author) return { isLoaded = function() return true end, getName = function() return name end,
  getAuthor = function() return author end } end
g_modules = { getModules = function() return { mod('game_a', 'Cinders of Chaos'), mod('game_b', 'base') } end }
connect, disconnect = function() end, function() end
tr = function(s, ...) if select('#', ...) > 0 then return s:format(...) end return s end
local function widget(id, visible, class)
  local w = { id = id, visible = visible, class = class or 'UIWidget', children = {} }
  function w:getId() return self.id end
  function w:isVisible() return self.visible end
  function w:getClassName() return self.class end
  function w:getChildren() return self.children end
  function w:setText(t) self.text = t end
  function w:setEnabled(v) self.enabled = v end
  function w:setChecked(v) self.checked = v end
  function w:show() self.visible = true end
  function w:hide() self.visible = false end
  function w:raise() end
  function w:destroy() self.destroyed = true end
  return w
end
rootWidget = widget('root', true)
rootWidget.children = { widget('shopWindow', true, 'UIWindow'), widget('hiddenWindow', false, 'UIWindow'),
  widget('panel', true) }
rootWidget.children[3].children = { widget('innerWindow', true, 'UIMiniWindow') }
local created
g_ui = { importStyle = function() end, createWidget = function()
  created = widget('chaosPerfWindow', true, 'UIWindow')
  for _, id in ipairs({ 'fpsLabel', 'frameLabel', 'luaLabel', 'modulesLabel', 'creaturesLabel', 'windowsLabel',
    'statusLabel', 'recordButton', 'copyButton', 'closeButton', 'profileBox' }) do created[id] = widget(id, true) end
  return created
end }
modules = {}

dofile(dir .. 'perf_core.lua')
dofile(dir .. 'perf.lua')
local P = ChaosPerf

-- ---------------------------------------------------------------- init: nothing wrapped
P.init()
eq(type(keys['Ctrl+Alt+F9']), 'function', 'hotkey bound')
eq(scheduleEvent, engineSchedule, 'no wrap without a record')
eq(cycleEvent, engineCycle, 'cycleEvent untouched')
local menuAdds = {}
modules.client_chaos_topbar = { ChaosTopBar = { addEntry = function(cat, e, under)
  menuAdds[#menuAdds + 1] = cat .. '/' .. tostring(under) .. '/' .. e.text
  return true
end } }
for id, e in pairs(events) do if e.kind == 'schedule' then events[id] = nil; e.fn() end end
eq(menuAdds[1], 'system/Developer/Performance', 'menu entry under System > Developer')

-- a module's code, with a module source name
local fake = assert(load([[
  local spin = ...
  return function()
    return cycleEvent(function() spin(400) end, 100), ProtocolGame.registerExtendedJSONOpcode(77, function() spin(1500) end)
  end
]], '@/modules/game_fake/fake.lua'))(function(n) us = us + n end)

-- ---------------------------------------------------------------- show, then record
P.show()
eq(created.visible, true, 'window shown')
local cycles = 0
for _, e in pairs(events) do if e.kind == 'cycle' then cycles = cycles + 1 end end
eq(cycles, 2, 'sample and probe timers while the window is open')
P.record()
eq(P.isRecording(), true, 'recording')
eq(scheduleEvent ~= engineSchedule, true, 'scheduleEvent wrapped during the record')
eq(ProtocolGame.registerExtendedJSONOpcode ~= engineRegister, true, 'opcode register wrapped')
local fakeEvent = fake()
local sampleFn, probeFn
for _, e in pairs(events) do
  if e.kind == 'cycle' and e.delay == 1000 then sampleFn = e.fn end
  if e.kind == 'cycle' and e.delay == 10 then probeFn = e.fn end
end
eq(type(sampleFn), 'function', 'sample timer')
for sec = 1, 60 do
  for _ = 1, 100 do ms = ms + 10; probeFn() end
  if sec == 30 then ms = ms + 250; probeFn() end
  fakeEvent.fn()
  opcodes[77]()
  sampleFn()
end
eq(P.isRecording(), false, 'record ends after 60 samples')
eq(scheduleEvent, engineSchedule, 'scheduleEvent put back')
eq(ProtocolGame.registerExtendedJSONOpcode, engineRegister, 'opcode register put back')
local txt, csv
for p, t in pairs(files) do
  if p:match('^/chaos%-perf%-.*%.txt$') then txt = t end
  if p:match('^/chaos%-perf%-.*%.csv$') then csv = t end
end
eq(txt ~= nil, true, 'summary written')
eq(csv ~= nil, true, 'csv written')
txt, csv = txt or '', csv or ''
eq(txt:find('1. game_fake', 1, true) ~= nil, true, 'game_fake is the costliest module')
eq(txt:find('114.0 ms', 1, true) ~= nil, true, 'game_fake time: 60 x (0.4 + 1.5) ms')
eq(txt:find('worst 250 ms', 1, true) ~= nil, true, 'the stall is seen')
eq(txt:find('modules loaded: 2 (1 Chaos)', 1, true) ~= nil, true, 'module counts')
eq(txt:find('shopWindow 60', 1, true) ~= nil, true, 'open window counted')
eq(txt:find('innerWindow 60', 1, true) ~= nil, true, 'window inside a panel counted')
eq(txt:find('hiddenWindow', 1, true), nil, 'hidden window not counted')
eq(txt:find('only callbacks registered during the record', 1, true) ~= nil, true, 'record-only note')
local rows = 0
for _ in csv:gmatch('\n') do rows = rows + 1 end
eq(rows, 61, 'csv header and 60 rows')
eq(created.statusLabel.text:find('Verdict: good', 1, true) ~= nil, true, 'status says the verdict')
P.copy()
eq(g_window.clip, P.lastReport(), 'copy puts the summary on the clipboard')

-- after the record a wrapped callback runs untimed
local before = us
fakeEvent.fn()
eq(us - before, 400, 'callback still runs after the record')

-- hide: the timers stop
P.hide()
local left = 0
for _, e in pairs(events) do if e.kind == 'cycle' and (e.delay == 1000 or e.delay == 10) then left = left + 1 end end
eq(left, 0, 'no timer left with the window closed')

-- the option wraps from the load on
P.terminate()
settings.chaosPerfProfileStart = true
dofile(dir .. 'perf.lua')
ChaosPerf.init()
eq(scheduleEvent ~= engineSchedule, true, 'option: wrapped from the load')
ChaosPerf.terminate()
eq(scheduleEvent, engineSchedule, 'terminate puts back')

if fails > 0 then
  print(('perf_test: %d of %d checks failed'):format(fails, checks))
  os.exit(1)
end
print(('perf_test: %d checks passed'):format(checks))
