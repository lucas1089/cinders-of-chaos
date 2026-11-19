-- loottour.lua: TEST ONLY, the loot explosion tour of .github/workflows/loot-video.yml (O676, server/README.md "Loot explosion (O669)").
-- Armed only by the environment variable CHAOS_LOOTTOUR=1 (loottourlogic.lua parseEnv): then it logs in with the account of
-- CHAOS_LIVE_ACCOUNT / CHAOS_LIVE_PASSWORD (a "Tester Xxx" character, so the test helper answers), enters the game with the
-- character of CHAOS_LIVE_CHARACTER, writes "loottour: ready" (the workflow starts the recording on that line), says
-- `!tester explode run` twice, presses Loot all, writes "loottour: done" and exits. Without the variable init() returns at once:
-- no window, no hotkey, no hub card. The password is never logged.
ChaosLootTour = {}
local T = ChaosLootTour
local L = ChaosLootTourLogic

local cfg
local events = {}
local finished = false

local function log(text)
  g_logger.info('loottour: ' .. text)
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

-- a window that popped up on its own (daily reward, outfit) would hide the explosion
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
  -- the stock login keeps the list in G.characters; the card list of client_chaos_charselect follows its order
  for _, c in ipairs(type(G) == 'table' and G.characters or {}) do out[#out + 1] = c.name end
  return out
end

local function login(nextFn)
  if g_game.isOnline() then return nextFn() end
  -- the first-start check (Android data download) holds the login; it is not blocking on a desktop client
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
    -- the login events (kit, welcome, hello of every module) settle, then the windows that opened go
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

local function lootAll()
  local gl = modules.game_groundlabels
  if gl and type(gl.lootAll) == 'function' then
    local ok, sent = pcall(gl.lootAll)
    log('loot all ' .. ((ok and sent) and 'sent' or 'not sent'))
  else
    log('loot all: no game_groundlabels')
  end
end

-- the window fills the virtual screen of the recording (best effort: the log says what the window ended up as)
local function fitWindow()
  pcall(function() g_window.move({x = 0, y = 0}) end)
  pcall(function() g_window.resize({width = L.WINDOW.width, height = L.WINDOW.height}) end)
  local ok, w, h = pcall(function() return g_window.getWidth(), g_window.getHeight() end)
  if ok then log(('window %dx%d'):format(w, h)) end
end

local function tour()
  fitWindow()
  log('ready')   -- the workflow starts the recording on this line
  for _, step in ipairs(L.timeline()) do
    later(step.at, function()
      if not me() then
        log('fail out of the game')
        return T.finish('left the game')
      end
      if step['do'] == 'say' then
        log('say ' .. step.text)
        g_game.talk(step.text)
      elseif step['do'] == 'lootall' then
        lootAll()
      else
        T.finish('ok')
      end
    end)
  end
end

function T.init()
  local err
  cfg, err = L.parseEnv(os.getenv)
  if not cfg then
    if err ~= 'off' then log('not armed: ' .. tostring(err)) end
    return
  end
  log('armed: account ' .. cfg.account)
  later(L.WATCHDOG_MS, function() T.finish('watchdog') end)
  -- the login screen and the other modules first
  later(8000, function() login(function() enter(tour) end) end)
end

function T.terminate()
  for _, e in ipairs(events) do removeEvent(e) end
  events = {}
end
