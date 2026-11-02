-- phonetest.lua: the emulator play test of the Android client (android-client.yml smoke_play, O313). With the marker
-- file phonetest_run in the write folder (written by client/android/tools/smoke_play.sh through run-as, debug APKs only)
-- it logs in with the account the marker names, enters with the first character, walks, opens and closes the main
-- windows (size against the screen), summons an NPC and trades with it, summons a monster and kills it, opens its
-- corpse and says a line. Every step logs "phonetest: <step> ok|fail <detail>"; "phonetest: shot <name>" asks the
-- script for a screenshot (it waits SHOT_MS). From the start to done, "phonetest: stall N ms: <stack>" samples a blocked
-- client (the first-start check, the login, entering the game).
-- Without the marker the module does nothing.
ChaosPhoneTest = {}
local P = ChaosPhoneTest
local C = ChaosPhoneTestCore

local SHOT_MS = 3000
local cfg
local events = {}
local results = {}
local talkSeen = {}
local tradeOpened = false
local containerOpened = nil

local function log(text)
  g_logger.info('phonetest: ' .. text)
end

local function later(ms, fn)
  events[#events + 1] = scheduleEvent(function()
    local ok, err = pcall(fn)
    if not ok then
      log('fail error ' .. tostring(err))
      log('done error')
    end
  end, ms)
end

local function result(step, ok, detail)
  results[#results + 1] = {step = step, ok = ok}
  log(('%s %s %s'):format(step, ok and 'ok' or 'fail', detail or ''))
end

local function shot(name, nextFn)
  log('shot ' .. name)
  later(SHOT_MS, nextFn)
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

local function posCopy(p)
  return p and {x = p.x, y = p.y, z = p.z} or nil
end

local function spectators()
  local p = me()
  if not p then return {} end
  return g_map.getSpectators(p:getPosition(), false) or {}
end

local function findCreature(name, kind)
  local best, bestD
  local mp = me() and me():getPosition()
  for _, c in ipairs(spectators()) do
    local hit
    if kind == 'npc' then
      hit = c:isNpc() and (not name or c:getName():lower() == name:lower())
    else
      hit = c:isMonster() and C.isTarget(c:getName(), name, me():getName())
    end
    if hit and mp then
      local cp = c:getPosition()
      local d = math.max(math.abs(cp.x - mp.x), math.abs(cp.y - mp.y))
      if not bestD or d < bestD then best, bestD = c, d end
    end
  end
  return best
end

local function visibleWindows()
  local out = {}
  local parents = {rootWidget}
  if modules.game_interface and modules.game_interface.getRootPanel then
    parents[#parents + 1] = modules.game_interface.getRootPanel()
  end
  for _, parent in ipairs(parents) do
    for _, w in ipairs(parent and parent:getChildren() or {}) do
      if w:isVisible() and w.getClassName and w:getClassName() == 'UIWindow' then
        out[w:getId()] = w
      end
    end
  end
  return out
end

local function closeWindows()
  for id, w in pairs(visibleWindows()) do
    log('window left open, closed: ' .. id)
    pcall(w.hide, w)
  end
end


-- stall probe: a count hook samples the Lua stack while one dispatcher event runs for over 1.5 s (the tick below did
-- not run), so the log names the code that keeps the client silent; on for ms milliseconds
local function stallProbe(ms)
  if not (debug and debug.sethook and debug.traceback) then return end
  local last, lastSample = g_clock.millis(), 0
  local stopAt = last + ms
  local function tick()
    last = g_clock.millis()
    if last < stopAt then
      later(50, tick)
    else
      debug.sethook()
      log('stall probe off')
    end
  end
  debug.sethook(function()
    local now = g_clock.millis()
    if now - last > 1500 and now - lastSample > 1000 then
      lastSample = now
      local tb = debug.traceback('', 2):gsub('\n%s*', ' | ')
      log(('stall %d ms: %s'):format(now - last, tb:sub(1, 700)))
    end
  end, '', 100000)
  log('stall probe on')
  tick()
end

local steps = {}

function steps.login(nextFn)
  if g_game.isOnline() then
    result('login', true, 'already in the game')
    return nextFn()
  end
  -- the first-start check holds the login (ChaosFirstStart.blocking); the emulator is slow, so the limits are wide
  local fs = ChaosFirstStart
  local t0 = g_clock.millis()
  waitFor(function() return not (fs and fs.blocking and fs.blocking()) end, 40 * 60000, function()
    log(('login: the first-start check let go after %d s'):format(math.floor((g_clock.millis() - t0) / 1000)))
    local t1 = g_clock.millis()
    EnterGame.doLogin(cfg.account, cfg.password)
    waitFor(function()
      return (CharSelect and CharSelect.isVisible and CharSelect.isVisible()) or
        (CharacterList and CharacterList.isVisible and CharacterList.isVisible()) or g_game.isOnline()
    end, 300000, function()
      result('login', true, ('character list shown after %d s'):format(math.floor((g_clock.millis() - t1) / 1000)))
      shot('charlist', nextFn)
    end, function()
      result('login', false, 'no character list in 300 s')
      shot('login_failed', function() steps.done() end)
    end)
  end, function()
    result('login', false, 'the first-start check still holds the login after 40 min')
    shot('login_failed', function() steps.done() end)
  end)
end

function steps.enter(nextFn)
  if not g_game.isOnline() then
    if CharSelect and CharSelect.select then pcall(CharSelect.select, 1, true) end
    if CharSelect and CharSelect.play then CharSelect.play() else CharacterList.doLogin() end
  end
  waitFor(function() return me() ~= nil end, 300000, function()
    later(5000, function()
      local p = me()
      if not p then
        result('enter', false, 'in the game, then out again within 5 s (the server closed the connection?)')
        return shot('enter_failed', function() steps.done() end)
      end
      result('enter', true, ('%s level %d at %d,%d,%d'):format(p:getName(), p:getLevel(), p:getPosition().x,
        p:getPosition().y, p:getPosition().z))
      shot('ingame', nextFn)
    end)
  end, function()
    result('enter', false, 'not in the game after 300 s')
    shot('enter_failed', function() steps.done() end)
  end)
end

function steps.walk(nextFn)
  local dirs = {North, North, East, East, South, South, West, West}
  local positions = {posCopy(me():getPosition())}
  local i = 0
  local function stepOnce()
    i = i + 1
    if i > #dirs then
      local n = C.moved(positions)
      result('walk', n > 0, ('%d of %d steps moved'):format(n, #dirs))
      return shot('walk', nextFn)
    end
    g_game.walk(dirs[i])
    later(1200, function()
      positions[#positions + 1] = posCopy(me():getPosition())
      stepOnce()
    end)
  end
  stepOnce()
end

-- frames per second standing in the game for PERF_MS, then the engine's own timings (g_stats: main thread, render
-- thread, dispatcher events, Lua) of that time. Information only: an emulator draws in software, so the numbers say
-- where the time goes, not what a phone reaches.
local PERF_MS = 20000
local STAT_NAMES = {[1] = 'main', [2] = 'render', [3] = 'events', [4] = 'lua'}
function steps.perf(nextFn)
  if g_stats and g_stats.clearAll then pcall(g_stats.clearAll) end
  local samples = {}
  local t0 = g_clock.millis()
  local function sample()
    samples[#samples + 1] = {fps = g_app.getFps(), gfx = g_app.getGraphicsFps and g_app.getGraphicsFps() or 0,
      cpu = g_app.getProcessingFps and g_app.getProcessingFps() or 0}
    if g_clock.millis() - t0 < PERF_MS then return later(1000, sample) end
    local s = C.fpsSummary(samples)
    result('perf', true, ('fps median %d min %d, graphics %d, processing %d, screen %dx%d'):format(s.fps, s.minFps,
      s.gfx, s.cpu, g_window.getWidth(), g_window.getHeight()))
    if g_stats and g_stats.get then
      for t = 1, 4 do
        local ok, text = pcall(g_stats.get, t, 12, true)
        if ok and text and text ~= '' then
          for line in text:gmatch('[^\n]+') do log('stat ' .. STAT_NAMES[t] .. ' ' .. line) end
        end
      end
    end
    nextFn()
  end
  later(1000, sample)
end

function steps.windows(nextFn)
  local sw, sh = rootWidget:getWidth(), rootWidget:getHeight()
  local list, i, opened, tooBig = C.WINDOWS, 0, 0, 0
  local function one()
    i = i + 1
    if i > #list then
      result('windows', opened > 0 and tooBig == 0, ('%d opened, %d outside the screen'):format(opened, tooBig))
      -- a window still open (one that popped up on its own: daily reward, outfit) would hide the next steps
      closeWindows()
      return nextFn()
    end
    local m = modules[list[i]]
    if not (m and type(m.toggle) == 'function') then
      log(('window %s: no toggle'):format(list[i]))
      return one()
    end
    local before = visibleWindows()
    local ok, err = pcall(m.toggle)
    later(1500, function()
      local found
      for id, w in pairs(visibleWindows()) do
        if not before[id] then found = w end
      end
      if found then
        opened = opened + 1
        local r = found:getRect()
        local fits, text = C.fits(r.x, r.y, r.width, r.height, sw, sh)
        if not fits then tooBig = tooBig + 1 end
        log(('window %s: %s %s'):format(list[i], found:getId(), text))
      else
        log(('window %s: no new window%s'):format(list[i], ok and '' or (' (' .. tostring(err) .. ')')))
      end
      shot('win_' .. list[i], function()
        pcall(m.toggle)
        later(800, one)
      end)
    end)
  end
  one()
end

function steps.npc(nextFn)
  g_game.talk('/s ' .. cfg.npc)
  later(2500, function()
    local npc = findCreature(cfg.npc, 'npc') or findCreature(nil, 'npc')
    if not npc then
      result('npc', false, 'no NPC in view after /s ' .. cfg.npc)
      return shot('npc', nextFn)
    end
    local name = npc:getName()
    talkSeen[name] = nil
    tradeOpened = false
    g_game.talk('hi')
    later(2500, function()
      g_game.talk('trade')
      waitFor(function() return tradeOpened end, 6000, function()
        result('npc', true, ('%s answered (%s), the trade window opened'):format(name, talkSeen[name] and 'yes' or 'no'))
        shot('npc_trade', function()
          pcall(g_game.closeNpcTrade)
          g_game.talk('bye')
          later(1000, nextFn)
        end)
      end, function()
        result('npc', talkSeen[name] ~= nil, ('%s answered: %s; no trade window'):format(name,
          tostring(talkSeen[name] or 'nothing')))
        shot('npc', nextFn)
      end)
    end)
  end)
end

local corpsePos
local function inPz()
  local p = me()
  return p and PlayerStates and PlayerStates.Pz and p:hasState(PlayerStates.Pz) or false
end

-- no monster can stand in a protection zone and no one attacks there: step out first, turning each time
local function leavePz(done)
  local tries = 0
  local function try()
    local pos = me():getPosition()
    if not inPz() then
      log(('fight: out of the protection zone after %d jump(s) at %d,%d,%d'):format(tries, pos.x, pos.y, pos.z))
      return done(true)
    end
    if tries >= #C.OUT_OF_PZ then
      log(('fight: still in a protection zone at %d,%d,%d after %d jump(s)'):format(pos.x, pos.y, pos.z, tries))
      return done(false)
    end
    tries = tries + 1
    local j = C.OUT_OF_PZ[tries]
    -- face the next way and jump on from where the last jump landed
    later(300, function()
      g_game.turn(j.dir)
      later(400, function()
        g_game.talk('/a ' .. j.n)
        later(1200, function()
          local p = me():getPosition()
          log(('fight: /a %d facing %d -> %d,%d,%d%s'):format(j.n, j.dir, p.x, p.y, p.z, inPz() and ' (protection zone)' or ''))
          try()
        end)
      end)
    end)
  end
  try()
end

function steps.fight(nextFn)
  closeWindows()
  leavePz(function(out)
  if not out then
    result('fight', false, 'no tile outside the protection zone in reach of /a')
    return shot('fight', nextFn)
  end
  g_game.talk('/m ' .. cfg.monster)
  later(2500, function()
    local mon = findCreature(cfg.monster, 'monster')
    if not mon then
      result('fight', false, 'no monster in view after /m ' .. cfg.monster)
      return shot('fight', nextFn)
    end
    local id, name = mon:getId(), mon:getName()
    corpsePos = posCopy(mon:getPosition())
    g_game.attack(mon)
    later(1500, function() shot('fight', function() end) end)
    waitFor(function()
      local c = g_map.getCreatureById(id)
      if c then corpsePos = posCopy(c:getPosition()) end
      return not c or c:isDead() or c:getHealthPercent() == 0
    end, 60000, function()
      result('fight', true, name .. ' died')
      later(1500, nextFn)
    end, function()
      local c = g_map.getCreatureById(id)
      result('fight', false, ('%s still alive after 60 s (%s%%)'):format(name, c and c:getHealthPercent() or '?'))
      shot('fight_end', nextFn)
    end)
  end)
  end)
end

function steps.loot(nextFn)
  local tile = corpsePos and g_map.getTile(corpsePos)
  local thing = tile and tile:getTopUseThing()
  if not (thing and thing:isContainer()) then
    result('loot', false, 'no corpse to open at the monster\'s tile')
    return nextFn()
  end
  containerOpened = nil
  g_game.open(thing)
  waitFor(function() return containerOpened ~= nil end, 6000, function()
    result('loot', true, ('the corpse opened, %d item(s)'):format(containerOpened))
    shot('loot', nextFn)
  end, function()
    result('loot', false, 'the corpse did not open')
    shot('loot', nextFn)
  end)
end

function steps.chat(nextFn)
  g_game.talk('phone test')
  later(1500, function()
    result('chat', true, 'said a line')
    shot('chat', nextFn)
  end)
end

function steps.done()
  local fails = 0
  for _, r in ipairs(results) do
    if not r.ok then fails = fails + 1 end
  end
  log(('done %d steps, %d failed'):format(#results, fails))
  if debug and debug.sethook then debug.sethook() end
end

local function onTalk(name, level, mode, text)
  if name and name ~= '' then talkSeen[name] = text end
end
local function onOpenNpcTrade() tradeOpened = true end
local function onContainerOpen(container)
  containerOpened = container and container:getItemsCount() or 0
end

function P.init()
  if not g_resources.fileExists('/' .. C.MARKER) then return end
  local text = g_resources.readFileContents('/' .. C.MARKER)
  local err
  cfg, err = C.parseMarker(text)
  if not cfg then
    log('fail marker ' .. tostring(err))
    return
  end
  connect(g_game, {onTalk = onTalk, onOpenNpcTrade = onOpenNpcTrade})
  connect(Container, {onOpen = onContainerOpen})
  log('armed: account ' .. cfg.account .. ', npc ' .. cfg.npc .. ', monster ' .. cfg.monster)
  stallProbe(45 * 60 * 1000)
  local order, i = C.STEPS, 0
  local function nextStep()
    i = i + 1
    local name = order[i]
    if not name then return end
    log('step ' .. name)
    steps[name](nextStep)
  end
  -- the login screen and the other modules first
  later(8000, nextStep)
end

function P.terminate()
  for _, e in ipairs(events) do removeEvent(e) end
  events = {}
  if cfg then
    disconnect(g_game, {onTalk = onTalk, onOpenNpcTrade = onOpenNpcTrade})
    disconnect(Container, {onOpen = onContainerOpen})
  end
end
