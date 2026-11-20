-- cliptour.lua: TEST ONLY, the mechanics clip tour of tools/ci/clip_tour.sh (O687, website/README.md "Mechanics clips").
-- Armed only by the environment variable CHAOS_CLIPTOUR=1 (cliptourlogic.lua parseEnv): then it logs in with the account of
-- CHAOS_LIVE_ACCOUNT / CHAOS_LIVE_PASSWORD (a "Tester Xxx" character, so the test helper answers), enters the game with the
-- character of CHAOS_LIVE_CHARACTER, writes "cliptour: ready", and plays the shots of CHAOS_CLIPTOUR_SHOTS (every shot when empty)
-- one after the other: its setup lines, then "cliptour: begin ID SECONDS" (the script starts a recording of that many seconds on
-- that line), the action (helper lines, a window toggled, the map zoom, a hotkey), "cliptour: end ID", the cleanup. At the end it
-- writes "cliptour: done ok" and exits. Every helper line and window is logged, so a shot whose staging is wrong shows in the log
-- (a dry run, CLIP_DRY=1, records nothing). Without the variable init() returns at once: no window, no hotkey, no hub card.
-- The password is never logged. Modelled on test_loottour (O676).
ChaosClipTour = {}
local T = ChaosClipTour
local L = ChaosClipTourLogic

local cfg
local events = {}
local finished = false

local function log(text)
  g_logger.info('cliptour: ' .. text)
end

local function later(ms, fn)
  events[#events + 1] = scheduleEvent(function()
    local ok, err = pcall(fn)
    if not ok then
      log('fail error ' .. tostring(err))
      T.finish('error')
    end
  end, ms)
end

-- polls cond every 500 ms until it holds (then yes()) or ms ran out (then no())
local function waitFor(cond, ms, yes, no)
  local t0 = g_clock.millis()
  local function poll()
    local ok, v = pcall(cond)
    if ok and v then return yes() end
    if g_clock.millis() - t0 >= ms then return no() end
    later(500, poll)
  end
  poll()
end

local function me()
  return g_game.isOnline() and g_game.getLocalPlayer() or nil
end

-- a window that popped up on its own (daily reward, outfit) would hide the shot
local function closeWindows()
  local parents = {rootWidget}
  if modules.game_interface and modules.game_interface.getRootPanel then
    parents[#parents + 1] = modules.game_interface.getRootPanel()
  end
  for _, parent in ipairs(parents) do
    for _, w in ipairs(parent and parent:getChildren() or {}) do
      if w:isVisible() and w.getClassName and w:getClassName() == 'UIWindow' then
        log('window left open, closed: ' .. tostring(w:getId()))
        pcall(w.hide, w)
      end
    end
  end
end

function T.finish(state)
  if finished then return end
  finished = true
  log('done ' .. tostring(state))
  -- one second for the last frames and the log line to reach the file, then the client leaves
  scheduleEvent(function() g_app.exit() end, 1000)
end

local function characterNames()
  local out = {}
  for _, c in ipairs(type(G) == 'table' and G.characters or {}) do out[#out + 1] = c.name end
  return out
end

local function login(nextFn)
  if g_game.isOnline() then return nextFn() end
  local fs = ChaosFirstStart
  waitFor(function() return not (fs and fs.blocking and fs.blocking()) end, 60000, function()
    EnterGame.doLogin(cfg.account, cfg.password)
    waitFor(function()
      return (CharSelect and CharSelect.isVisible and CharSelect.isVisible()) or
        (CharacterList and CharacterList.isVisible and CharacterList.isVisible()) or g_game.isOnline()
    end, 120000, function()
      log('character list shown')
      nextFn()
    end, function()
      log('fail no character list in 120 s')
      T.finish('login failed')
    end)
  end, function()
    log('fail the first-start check holds the login')
    T.finish('login failed')
  end)
end

local function enter(nextFn)
  if not g_game.isOnline() then
    local i = L.pickCharacter(characterNames(), cfg.character) or 1
    if CharSelect and CharSelect.select then pcall(CharSelect.select, i, true) end
    if CharSelect and CharSelect.play then CharSelect.play() else CharacterList.doLogin() end
  end
  waitFor(function() return me() ~= nil end, 120000, function()
    later(6000, function()
      if not me() then
        log('fail in the game, then out again within 6 s')
        return T.finish('entry failed')
      end
      closeWindows()
      local p = me():getPosition()
      log(('entered at %d,%d,%d'):format(p.x, p.y, p.z))
      nextFn()
    end)
  end, function()
    log('fail not in the game after 120 s')
    T.finish('entry failed')
  end)
end

-- the window fills the virtual screen of the recording (best effort: the log says what the window ended up as)
local function fitWindow()
  pcall(function() g_window.move({x = 0, y = 0}) end)
  pcall(function() g_window.resize({width = L.WINDOW.width, height = L.WINDOW.height}) end)
  local ok, w, h = pcall(function() return g_window.getWidth(), g_window.getHeight() end)
  if ok then log(('window %dx%d'):format(w, h)) end
end

-- toggles the window of a module (its toggle(), else show()); the log says which
local function toggleWindow(name)
  local m = modules[name]
  if not m then return log('window ' .. name .. ': no such module') end
  local fn = m.toggle or m.show
  if type(fn) ~= 'function' then return log('window ' .. name .. ': no toggle') end
  local ok, err = pcall(fn)
  log('window ' .. name .. (ok and ' toggled' or (' failed ' .. tostring(err))))
end

-- the map zoom, best effort: setZoom, else zoomOut / zoomIn steps from the current view; the log says what worked
local function zoom(tiles)
  local panel = modules.game_interface and modules.game_interface.getMapPanel and modules.game_interface.getMapPanel()
  if not panel then return log('zoom: no map panel') end
  if panel.setZoom and pcall(panel.setZoom, panel, tiles) then return log('zoom ' .. tiles .. ' (setZoom)') end
  if panel.setVisibleDimension and pcall(panel.setVisibleDimension, panel, {width = tiles * 2 + 1, height = tiles * 2 - 3}) then
    return log('zoom ' .. tiles .. ' (visible dimension)')
  end
  log('zoom ' .. tiles .. ': not applied')
end

local function pressKey(key)
  local hk = modules.game_hotkeys
  if hk and type(hk.doKeyCombo) == 'function' then
    local ok = pcall(hk.doKeyCombo, key)
    return log('key ' .. key .. (ok and ' pressed' or ' failed'))
  end
  log('key ' .. key .. ': no game_hotkeys')
end

local function run(step)
  if not me() then
    log('fail out of the game')
    return T.finish('left the game')
  end
  local what = step['do']
  if what == 'say' then
    log('say ' .. step.text)
    g_game.talk(step.text)
  elseif what == 'window' then
    toggleWindow(step.module)
  elseif what == 'zoom' then
    zoom(step.tiles)
  elseif what == 'key' then
    pressKey(step.key)
  elseif what == 'mark' then
    if step.what == 'begin' then log(('begin %s %d'):format(step.shot, step.seconds)) else log('end ' .. step.shot) end
  else
    T.finish('ok')
  end
end

local function tour()
  fitWindow()
  log('ready')
  local timeline = L.timeline(cfg.shots)
  log(('tour: %d shots, %d steps, %d s'):format(#cfg.shots, #timeline, math.floor(timeline[#timeline].at / 1000)))
  for _, step in ipairs(timeline) do
    later(step.at, function() run(step) end)
  end
end

function T.init()
  local err
  cfg, err = L.parseEnv(os.getenv)
  if not cfg then
    if err ~= 'off' then log('not armed: ' .. tostring(err)) end
    return
  end
  log('armed: account ' .. cfg.account .. ', shots ' .. table.concat(cfg.shots, ','))
  later(L.WATCHDOG_MS, function() T.finish('watchdog') end)
  later(8000, function() login(function() enter(tour) end) end)
end

function T.terminate()
  for _, e in ipairs(events) do removeEvent(e) end
  events = {}
end
