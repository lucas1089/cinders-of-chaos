-- perf.lua: the performance overlay of the client (O376). System > Developer > Performance, or Ctrl+Alt+F9.
-- Shows FPS (and the engine's graphics / processing FPS when it has them), frame time (avg from FPS, worst = the
-- longest the main loop did not come back to a 10 ms timer), Lua memory, loaded modules, creatures on screen and open
-- windows. "Record 60 s" takes one sample a second and writes chaos-perf-<time>.csv and .txt into the client's write
-- folder; "Copy summary" puts the text on the clipboard (the way out on a phone).
-- Lua time per module: while a record runs, scheduleEvent / cycleEvent / addEvent and the extended opcode registers are
-- wrapped, so every callback registered by a module adds its time to that module (perf_core.lua C.wrap). With the
-- option "Time Lua per module from client start" (saved, needs a restart) the wrap is in place from this module's load
-- (priority 110, before the game modules), so cycle events started at login count too; it then costs a stack lookup per
-- new timer, and one test per call outside a record. Without the option nothing is wrapped outside a record.
-- Nothing runs while the window is closed and no record is going on. Pure logic: perf_core.lua (perf_core_test.lua).
ChaosPerf = {}
local P = ChaosPerf
local C = ChaosPerfCore

local HOTKEY = 'Ctrl+Alt+F9'
local SETTING_PROFILE = 'chaosPerfProfileStart'
local MODULE = 'client_chaos_perf'

-- the engine functions as they were before any wrap; this module's own timers use them
local raw = { scheduleEvent = scheduleEvent, cycleEvent = cycleEvent, addEvent = addEvent, removeEvent = removeEvent }

local window
local sampleEvent, probeEvent
local probe = C.newProbe()
local recent = {}
local rec, recInfo
local lastReport
local status = ''
local installed, installedForRecord = false, false
local wrapped = {}
local menuAdded = false
local chaosNames

local function warn(text) if g_logger then g_logger.warning('[perf] ' .. tostring(text)) end end

local function safe(name, fn)
  return function(...)
    local ok, err = pcall(fn, ...)
    if not ok then warn(name .. ': ' .. tostring(err)) end
  end
end

local function nowMs()
  if g_clock.realMillis then return g_clock.realMillis() end
  return g_clock.millis()
end

local clockName = 'os.clock'
local function microClock()
  if g_clock and g_clock.realMicros then
    clockName = 'g_clock.realMicros'
    return function() return g_clock.realMicros() end
  end
  clockName = 'os.clock (process CPU time, other threads included)'
  return function() return os.clock() * 1e6 end
end

local timer = C.newTimer(microClock(), function(e) return debug.traceback(tostring(e), 2) end)

local function settingProfile()
  return g_settings and g_settings.getBoolean and g_settings.getBoolean(SETTING_PROFILE) or false
end

-- ---------------------------------------------------------------- wrapping
local function wrapGlobal(name)
  local f = _G[name]
  if type(f) ~= 'function' then return end
  local replacement = function(callback, ...)
    if type(callback) == 'function' then
      callback = C.wrap(timer, callback, C.callerModule(debug.getinfo, 3), name)
    end
    return f(callback, ...)
  end
  wrapped[#wrapped + 1] = { owner = _G, key = name, orig = f, repl = replacement }
  _G[name] = replacement
end

local function wrapOpcode(name)
  local pg = rawget(_G, 'ProtocolGame')
  local f = type(pg) == 'table' and pg[name]
  if type(f) ~= 'function' then return end
  local replacement = function(opcode, callback, ...)
    if type(callback) == 'function' then
      callback = C.wrap(timer, callback, C.callerModule(debug.getinfo, 3), 'opcode')
    end
    return f(opcode, callback, ...)
  end
  wrapped[#wrapped + 1] = { owner = pg, key = name, orig = f, repl = replacement }
  pg[name] = replacement
end

local function install()
  if installed or not (debug and debug.getinfo) then return installed end
  for _, n in ipairs({ 'scheduleEvent', 'cycleEvent', 'addEvent' }) do wrapGlobal(n) end
  wrapOpcode('registerExtendedOpcode')
  wrapOpcode('registerExtendedJSONOpcode')
  installed = true
  return true
end

-- puts back the engine's functions (only where nobody replaced ours since). Callbacks wrapped before stay wrapped and
-- cost one test per call until they end.
local function uninstall()
  for i = #wrapped, 1, -1 do
    local w = wrapped[i]
    if w.owner[w.key] == w.repl then w.owner[w.key] = w.orig end
  end
  wrapped = {}
  installed = false
end

-- ---------------------------------------------------------------- reading the client
local function moduleCounts()
  local total, chaos = 0, 0
  if not chaosNames then
    chaosNames = {}
  end
  local ok = pcall(function()
    for _, m in ipairs(g_modules.getModules() or {}) do
      if m:isLoaded() then
        total = total + 1
        local name = m:getName()
        if chaosNames[name] == nil then
          local a = m.getAuthor and m:getAuthor() or ''
          chaosNames[name] = (a == 'Cinders of Chaos')
        end
        if chaosNames[name] then chaos = chaos + 1 end
      end
    end
  end)
  if not ok then return 0, 0 end
  return total, chaos
end

local function creatureCount()
  if not (g_game.isOnline() and g_map.getSpectators) then return nil end
  local me = g_game.getLocalPlayer()
  if not me then return nil end
  local ok, list = pcall(g_map.getSpectators, me:getPosition(), false)
  if not ok or type(list) ~= 'table' then return nil end
  local n = 0
  for _ in pairs(list) do n = n + 1 end
  return n
end

local function isWindow(w)
  local ok, name = pcall(function() return w:getClassName() end)
  return ok and type(name) == 'string' and name:find('Window') ~= nil
end

-- ids of the visible windows: on the root, the game root panel and the side panels
local function visibleWindows()
  local out, seen = {}, {}
  local function scan(parent, depth)
    if not parent or depth > 1 then return end
    local ok, children = pcall(function() return parent:getChildren() end)
    if not ok or type(children) ~= 'table' then return end
    for _, w in ipairs(children) do
      local okv, vis = pcall(function() return w:isVisible() end)
      if okv and vis then
        if isWindow(w) and w ~= window then
          local id = w:getId()
          if id and id ~= '' and not seen[id] then
            seen[id] = true
            out[#out + 1] = id
          end
        else
          scan(w, depth + 1)
        end
      end
    end
  end
  scan(rootWidget, 0)
  local gi = modules.game_interface
  if gi then
    for _, getter in ipairs({ 'getRootPanel', 'getLeftPanel', 'getRightPanel' }) do
      local ok, panel = pcall(function() return gi[getter] and gi[getter]() end)
      if ok and panel then scan(panel, 0) end
    end
  end
  return out
end

local function engineFps()
  local gfx = g_app.getGraphicsFps and g_app.getGraphicsFps() or nil
  local cpu = g_app.getProcessingFps and g_app.getProcessingFps() or nil
  return g_app.getFps(), gfx, cpu
end

local function isMobile() return g_app.isMobile and g_app.isMobile() or false end

local function engineStats()
  local lines = {}
  if not (g_stats and g_stats.get) then return lines end
  local names = { 'main', 'render', 'events', 'lua' }
  for t = 1, 4 do
    local ok, text = pcall(g_stats.get, t, 10, true)
    if ok and type(text) == 'string' then
      for line in text:gmatch('[^\n]+') do lines[#lines + 1] = names[t] .. ' ' .. line end
    end
  end
  return lines
end

-- ---------------------------------------------------------------- the window
local function setText(id, text)
  local w = window and window[id]
  if w then w:setText(text) end
end

local function refresh()
  if not (window and window:isVisible()) then return end
  local o = C.overlay(recent)
  if o.gfx and o.cpu then
    setText('fpsLabel', tr('FPS: %d (graphics %d, processing %d)', o.fps, o.gfx, o.cpu))
  else
    setText('fpsLabel', tr('FPS: %d', o.fps))
  end
  setText('frameLabel', tr('Frame time: %.1f ms avg, %d ms worst (last %d s)', o.frameAvgMs, math.floor(o.frameWorstMs + 0.5), o.seconds))
  setText('luaLabel', tr('Lua memory: %d KB', math.floor(collectgarbage('count'))))
  local total, chaos = moduleCounts()
  setText('modulesLabel', tr('Modules loaded: %d (%d Chaos)', total, chaos))
  local n = creatureCount()
  setText('creaturesLabel', n and tr('Creatures on screen: %d', n) or tr('Creatures on screen: not in game'))
  setText('windowsLabel', tr('Open windows: %d', #visibleWindows()))
  local line = status
  if rec then
    line = tr('Recording... %d s left. Play as usual.', math.max(rec.seconds - #rec.samples, 0))
  end
  setText('statusLabel', line)
  if window.recordButton then window.recordButton:setEnabled(rec == nil) end
  if window.copyButton then window.copyButton:setEnabled(lastReport ~= nil) end
end

-- ---------------------------------------------------------------- sampling
local function active() return rec ~= nil or (window ~= nil and window:isVisible()) end

local function stopLoops()
  if sampleEvent then raw.removeEvent(sampleEvent); sampleEvent = nil end
  if probeEvent then raw.removeEvent(probeEvent); probeEvent = nil end
  C.probeReset(probe)
end

local function writeRecord()
  local summary = C.summarize(rec, timer.profile, isMobile())
  local total, chaos = moduleCounts()
  local stamp = C.stamp(os.date('*t'))
  local info = {
    stamp = stamp, version = g_app.getVersion and g_app.getVersion() or '?', os = g_app.getOs and g_app.getOs() or '?',
    screen = g_window and (g_window.getWidth() .. 'x' .. g_window.getHeight()) or '?', clock = clockName,
    profiled = recInfo.profiled, modules = total, chaosModules = chaos, stats = engineStats(),
  }
  local text = C.report(summary, info)
  lastReport = text
  local csvName, txtName = C.fileNames(stamp)
  local ok1 = pcall(g_resources.writeFileContents, csvName, C.csv(rec))
  local ok2 = pcall(g_resources.writeFileContents, txtName, text)
  local dir = g_resources.getWriteDir and g_resources.getWriteDir() or ''
  if ok1 and ok2 then
    local name = txtName:sub(2)
    if summary.verdict == 'good' then
      status = tr('Saved %s and .csv in %s. Verdict: good.', name, dir)
    elseif summary.verdict == 'ok' then
      status = tr('Saved %s and .csv in %s. Verdict: ok, some drops.', name, dir)
    else
      status = tr('Saved %s and .csv in %s. Verdict: low.', name, dir)
    end
    if g_logger then g_logger.info('[perf] record saved: ' .. dir .. txtName:sub(2)) end
  else
    status = tr('Could not save the file. Use Copy summary.')
  end
  if g_logger then
    for line in text:gmatch('[^\n]+') do g_logger.info('[perf] ' .. line) end
  end
end

local function finishRecord()
  C.stopTimer(timer)
  local ok, err = pcall(writeRecord)
  if not ok then
    warn('record: ' .. tostring(err))
    status = tr('Could not save the file. Use Copy summary.')
  end
  rec, recInfo = nil, nil
  if installedForRecord then
    uninstall()
    installedForRecord = false
  end
end

local function sample()
  local fps, gfx, cpu = engineFps()
  local s = { t = nowMs(), fps = fps, gfx = gfx, cpu = cpu, gap = C.probeTake(probe),
    luaKb = collectgarbage('count') }
  C.pushLast(recent, s, C.WINDOW_S)
  if rec then
    s.creatures = creatureCount()
    s.windows = visibleWindows()
    if C.addSample(rec, s) then finishRecord() end
  end
  refresh()
  if not active() then stopLoops() end
end

local function startLoops()
  if not sampleEvent then
    sampleEvent = raw.cycleEvent(safe('sample', sample), 1000)
  end
  if not probeEvent then
    C.probeReset(probe)
    probeEvent = raw.cycleEvent(function() C.probeTick(probe, nowMs()) end, C.PROBE_MS)
  end
end

-- ---------------------------------------------------------------- actions
function P.record()
  if rec then return end
  local profiled = 'start'
  if not installed then
    if install() then
      installedForRecord = true
      profiled = 'record'
    else
      profiled = 'off'
    end
  end
  if g_stats and g_stats.clearAll then pcall(g_stats.clearAll) end
  rec = C.newRecording(nowMs(), C.RECORD_S)
  recInfo = { profiled = profiled }
  C.startTimer(timer)
  status = ''
  startLoops()
  refresh()
end

function P.copy()
  if lastReport and g_window and g_window.setClipboardText then
    g_window.setClipboardText(lastReport)
    status = tr('Summary copied to the clipboard.')
    refresh()
  end
end

local function ensureWindow()
  if window then return true end
  g_ui.importStyle('perf')
  local ok, ui = pcall(g_ui.createWidget, 'ChaosPerfWindow', rootWidget)
  if not ok or not ui then
    warn('window not loaded: ' .. tostring(ui))
    return false
  end
  window = ui
  window:hide()
  window.recordButton.onClick = safe('record', P.record)
  window.copyButton.onClick = safe('copy', P.copy)
  window.closeButton.onClick = function() P.hide() end
  window.profileBox:setChecked(settingProfile())
  window.profileBox.onCheckChange = function(_, checked)
    g_settings.set(SETTING_PROFILE, checked and true or false)
    status = checked and tr('Takes effect at the next client start.') or tr('Off from the next client start.')
    refresh()
  end
  if status == '' then status = tr('Record 60 s while you play the part you want to measure.') end
  return true
end

function P.show()
  if not ensureWindow() then return end
  window:show()
  window:raise()
  startLoops()
  refresh()
end

function P.hide()
  if window then window:hide() end
  if not active() then stopLoops() end
end

function P.toggle()
  if window and window:isVisible() then P.hide() else P.show() end
end

function P.isRecording() return rec ~= nil end

-- the last record's text (nil before one ended)
function P.lastReport() return lastReport end

local function addMenu()
  if menuAdded then return end
  local top = modules.client_chaos_topbar
  local api = top and top.ChaosTopBar
  if api and api.addEntry then
    local ok, added = pcall(api.addEntry, 'system',
      { text = 'Performance', icon = 'console', custom = P.toggle, offline = true }, 'Developer')
    menuAdded = ok and added or false
  end
end

function P.init()
  if settingProfile() then install() end
  if g_keyboard then g_keyboard.bindKeyDown(HOTKEY, P.toggle) end
  -- the top menu loads after this module: add the entry once every module is in
  raw.scheduleEvent(safe('menu', addMenu), 0)
  connect(g_game, { onGameStart = addMenu })
end

function P.terminate()
  disconnect(g_game, { onGameStart = addMenu })
  if g_keyboard then pcall(g_keyboard.unbindKeyDown, HOTKEY, P.toggle) end
  stopLoops()
  C.stopTimer(timer)
  rec, recInfo = nil, nil
  uninstall()
  if window then
    window:destroy()
    window = nil
  end
end
