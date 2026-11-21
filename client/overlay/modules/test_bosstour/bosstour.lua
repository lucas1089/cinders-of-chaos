-- bosstour.lua: TEST ONLY, the boss fight tour of .github/workflows/boss-video.yml (O689, server/README.md "Malgrath fight video (O689)").
-- Armed only by the environment variable CHAOS_BOSSTOUR=1 (bosstourlogic.lua parseEnv): then it logs in with the staff account of
-- CHAOS_LIVE_ACCOUNT / CHAOS_LIVE_PASSWORD (the spectator: a group 6 character made in the CI database, never a tester and never in the party),
-- enters, says `/ghost`, and waits quietly: every few seconds it asks `/instances pinnacle`. While the tester bots gear up (an hour or more) it
-- stands where it is. When a fight of the boss is listed it jumps to a party member with `/goto NAME`, writes "bosstour: ready" (the workflow starts
-- the recording on that line), keeps a party member in sight (a jump to the next one when none is), logs the boss's health every 30 s, and when the
-- list says the boss fell (or the fight is gone: the party fell or the clock ran out) it waits a few seconds, writes "bosstour: done ..." and exits.
-- Without the variable init() returns at once: no window, no hotkey, no hub card. The password is never logged.
ChaosBossTour = {}
local T = ChaosBossTour
local L = ChaosBossTourLogic

local cfg, S
local events = {}
local finished = false
local textHook = false

local function log(text)
  g_logger.info('bosstour: ' .. text)
end

local function later(ms, fn)
  events[#events + 1] = scheduleEvent(function()
    local ok, err = pcall(fn)
    if not ok then
      log('fail error ' .. tostring(err))
      T.finish('error', false)
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

-- a window that popped up on its own (daily reward, outfit) would hide the fight
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

-- a window that opens later (the patch notes open by themselves some seconds after the login, a daily reward, a level up) would
-- cover the film too: look again every 2 s until the tour ends
local function keepClear()
  if finished then return end
  closeWindows()
  scheduleEvent(keepClear, 2000)
end

function T.finish(state, ok)
  if finished then return end
  finished = true
  log('done ' .. (ok and 'ok ' or 'fail ') .. tostring(state))
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
      T.finish('login failed', false)
    end)
  end, function()
    log('fail the first-start check holds the login')
    T.finish('login failed', false)
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
        return T.finish('entry failed', false)
      end
      keepClear()
      local p = me():getPosition()
      log(('entered at %d,%d,%d'):format(p.x, p.y, p.z))
      nextFn()
    end)
  end, function()
    log('fail not in the game after 120 s')
    T.finish('entry failed', false)
  end)
end

-- the window fills the virtual screen of the recording (best effort: the log says what the window ended up as)
local function fitWindow()
  pcall(function() g_window.move({x = 0, y = 0}) end)
  pcall(function() g_window.resize({width = L.WINDOW.width, height = L.WINDOW.height}) end)
  local ok, w, h = pcall(function() return g_window.getWidth(), g_window.getHeight() end)
  if ok then log(('window %dx%d'):format(w, h)) end
end

-- the waiting hour does not need 30 frames a second of software GL; the fight does
local function maxFps(n)
  pcall(function() g_app.setMaxFps(n) end)
end

local function chebyshev(a, b)
  return math.max(math.abs(a.x - b.x), math.abs(a.y - b.y))
end

-- what the client sees round the spectator: the distance to the nearest party member and the boss's health percent. O694: the health is
-- the one of the creature locked on at the first match (L.watchBoss: its id, a line when it leaves the view or another one carries the name)
local function look(pos)
  local nearest
  local seen = {}
  local ok, list = pcall(function() return g_map.getSpectators(pos, false) end)
  if not ok or type(list) ~= 'table' then return nil, nil end
  for _, c in ipairs(list) do
    local okName, name = pcall(function() return c:getName() end)
    if okName and name then
      if L.bossMatches(cfg, name) then
        local okHp, hp = pcall(function() return c:getHealthPercent() end)
        local okId, id = pcall(function() return c:getId() end)
        if okHp and okId then seen[#seen + 1] = {id = id, name = name, hp = hp} end
      else
        for _, member in ipairs(cfg.follow) do
          if name:lower() == member:lower() then
            local okPos, cp = pcall(function() return c:getPosition() end)
            if okPos and cp and cp.z == pos.z then
              local d = chebyshev(pos, cp)
              if nearest == nil or d < nearest then nearest = d end
            end
          end
        end
      end
    end
  end
  local bossHp, logs = L.watchBoss(S, seen)
  for _, line in ipairs(logs) do log(line) end
  return nearest, bossHp
end

local function onTextMessage(mode, text)
  if S and type(text) == 'string' then L.onText(S, text) end
end

local function act(action)
  if action.say then
    log('say ' .. action.say)
    g_game.talk(action.say)
  elseif action.log then
    log(action.log)
    if action.log == 'ready' then
      maxFps(30)
      fitWindow()
    end
  elseif action.finish then
    T.finish(action.finish, action.ok)
  end
end

local lastBossLog = -1e9

local function tick()
  if finished then return end
  local player = me()
  if not player then
    log('fail out of the game')
    return T.finish('left the game', false)
  end
  local pos = player:getPosition()
  local now = g_clock.millis()
  local nearest, bossHp = look(pos)
  if bossHp ~= nil and now - lastBossLog >= 30000 then
    lastBossLog = now
    local secs = S.fightAt and math.floor((now - S.fightAt) / 1000) or 0
    log(('boss %d%% at %d s in the fight, party member %s tiles away'):format(bossHp, secs, tostring(nearest)))
  end
  for _, action in ipairs(L.step(S, {now = now, pos = pos, nearest = nearest})) do
    act(action)
  end
  later(1000, tick)
end

local function tour()
  log('ghost')
  g_game.talk(L.GHOST_SAY)
  maxFps(10)
  S = L.new(cfg, g_clock.millis())
  later(3000, tick)
end

function T.init()
  local err
  cfg, err = L.parseEnv(os.getenv)
  if not cfg then
    if err ~= 'off' then log('not armed: ' .. tostring(err)) end
    return
  end
  log(('armed: account %s, boss %s, party of %d, %d s of fight, %d s of waiting at most'):format(
    cfg.account, cfg.boss, #cfg.follow, cfg.seconds, cfg.waitSeconds))
  connect(g_game, {onTextMessage = onTextMessage})
  textHook = true
  -- the login, the waiting, the fight and the outro: the client leaves by itself when a step never came (the workflow cuts it first)
  later((cfg.waitSeconds + cfg.seconds + 600) * 1000, function() T.finish('watchdog', false) end)
  later(8000, function() login(function() enter(tour) end) end)
end

function T.terminate()
  if textHook then
    disconnect(g_game, {onTextMessage = onTextMessage})
    textHook = false
  end
  for _, e in ipairs(events) do removeEvent(e) end
  events = {}
end
