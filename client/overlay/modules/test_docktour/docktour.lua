-- docktour.lua: TEST ONLY, the side dock tour of tools/ci/dock_video.sh (O732, client/MANIFEST.md "Side dock (O732)").
-- Armed only by the environment variable CHAOS_DOCKTOUR=1 (docktourlogic.lua parseEnv): then it logs in with the account of
-- CHAOS_LIVE_ACCOUNT / CHAOS_LIVE_PASSWORD, enters with CHAOS_LIVE_CHARACTER, writes "docktour: ready" (the recording starts
-- on that line) and plays docktourlogic.lua STEPS: a key step writes "docktour: key KEY" and the recording script presses
-- that key on the virtual screen (the dock's real binding); when the dock did not follow in 1.5 s the tour calls the dock
-- itself and says so. Tab and sub steps click the dock's own buttons. Every step logs the dock's state (open, tab, width,
-- the window it holds, a window beside it). Without the variable init() returns at once: no window, no hotkey, no hub
-- card. The password is never logged.
ChaosDockTour = {}
local T = ChaosDockTour
local L = ChaosDockTourLogic

local cfg
local events = {}
local finished = false
local t0

local function log(text)
  local at = t0 and (' @' .. (g_clock.millis() - t0)) or ''
  g_logger.info('docktour: ' .. text .. at)
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

local function waitFor(cond, ms, yes, no)
  local start = g_clock.millis()
  local function poll()
    local ok, v = pcall(cond)
    if ok and v then return yes() end
    if g_clock.millis() - start >= ms then return no() end
    later(500, poll)
  end
  poll()
end

local function me()
  return g_game.isOnline() and g_game.getLocalPlayer() or nil
end

local function dockApi()
  local m = modules.game_chaosdock
  return m and rawget(m, 'ChaosDock') or nil
end

local function panel()
  return rootWidget:recursiveGetChildById('chaosDock')
end

-- the dock's own scroll bar (content > scrollBar; a hosted window has bars of its own deeper down)
local function dockBar()
  local p = panel()
  local content = p and p:getChildById('content')
  return content and content:getChildById('scrollBar') or nil
end

local function shownTab()
  for _, id in ipairs({'equip', 'quests', 'attributes', 'spells', 'shop'}) do
    local b = rootWidget:recursiveGetChildById('chaosDockTab_' .. id)
    if b and b:isChecked() then return id end
  end
  return nil
end

local function state()
  local d = dockApi()
  local p = panel()
  local parts = {}
  parts[#parts + 1] = 'open ' .. tostring(d and d.isOpen and d.isOpen())
  parts[#parts + 1] = 'tab ' .. tostring(shownTab())
  if p then
    parts[#parts + 1] = ('panel %dx%d at %d,%d top %d visible %s'):format(p:getWidth(), p:getHeight(), p:getX(), p:getY(), p:getMarginTop(),
      tostring(p:isVisible()))
    local title = p:getChildById('title')
    if title then parts[#parts + 1] = 'title "' .. title:getText() .. '"' end
    local bar = dockBar()
    if bar and bar:isVisible() then
      parts[#parts + 1] = ('scroll %d of %d'):format(bar:getValue(), bar:getMaximum())
    end
    local note = p:getChildById('note')
    if note and note:isVisible() then parts[#parts + 1] = 'note "' .. note:getText() .. '"' end
  else
    parts[#parts + 1] = 'no panel'
  end
  for _, h in ipairs(d and d.held and d.held() or {}) do
    local w = h.widget
    parts[#parts + 1] = ('holds %s %dx%d'):format(tostring(w:getId()), w:getWidth(), w:getHeight())
  end
  return table.concat(parts, ', ')
end

-- the windows a login opens by themselves (patch notes, daily reward) would cover the dock: hidden once after the entry
local function closeWindows()
  local d = dockApi()
  local heldIds = {}
  for _, h in ipairs(d and d.held and d.held() or {}) do heldIds[h.widget:getId()] = true end
  for _, w in ipairs(rootWidget:getChildren()) do
    if w:isVisible() and w.getClassName and w:getClassName() == 'UIWindow' and not heldIds[w:getId()] then
      log('window left open, closed: ' .. tostring(w:getId()))
      pcall(w.hide, w)
    end
  end
end

-- the How it works card (game_howitworks, O331) opens the first time each window opens and would hide the dock in the
-- film: it stays L.CARD_SHOW_MS (its place left of the dock is logged and filmed), then closes; every other window is
-- left alone
local cardsClosed = 0
local cardSeen = nil
local function keepCardsClosed()
  if finished then return end
  -- the Patch Notes window opens by itself a while after the entry (game_patchnotes) and would cover the dock
  local notes = rootWidget:recursiveGetChildById('patchNotesWindow')
  if notes and notes:isVisible() then
    log('Patch Notes window closed')
    pcall(notes.hide, notes)
  end
  local card = rootWidget:recursiveGetChildById('howWindow')
  if card and card:isVisible() then
    if not cardSeen then
      cardSeen = g_clock.millis()
      local p = panel()
      local dockLeft = (p and p:isVisible()) and p:getX() or nil
      local right = card:getX() + card:getWidth()
      log(('How it works card "%s" at x %d..%d, dock left %s: %s'):format(card:getText(), card:getX(), right,
        tostring(dockLeft), (not dockLeft or right <= dockLeft) and 'clear of the dock' or 'OVER THE DOCK'))
    elseif g_clock.millis() - cardSeen >= L.CARD_SHOW_MS then
      cardsClosed = cardsClosed + 1
      log('How it works card closed (' .. cardsClosed .. ')')
      pcall(card.hide, card)
      cardSeen = nil
    end
  else
    cardSeen = nil
  end
  scheduleEvent(keepCardsClosed, 300)
end

function T.finish(how)
  if finished then return end
  finished = true
  log('done ' .. tostring(how))
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

local function fitWindow()
  pcall(function() g_window.move({x = 0, y = 0}) end)
  pcall(function() g_window.resize({width = L.WINDOW.width, height = L.WINDOW.height}) end)
  local ok, w, h = pcall(function() return g_window.getWidth(), g_window.getHeight() end)
  if ok then log(('window %dx%d'):format(w, h)) end
end

local function enter(nextFn)
  if not g_game.isOnline() then
    local i = L.pickCharacter(characterNames(), cfg.character) or 1
    if CharSelect and CharSelect.select then pcall(CharSelect.select, i, true) end
    if CharSelect and CharSelect.play then CharSelect.play() else CharacterList.doLogin() end
  end
  waitFor(function() return me() ~= nil end, 120000, function()
    fitWindow() -- the window takes its size while the login settles, not in the film
    later(8000, function()
      if not me() then
        log('fail in the game, then out again within 8 s')
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

local function clickTab(id)
  local b = rootWidget:recursiveGetChildById('chaosDockTab_' .. id)
  if not b then log('fail no tab button ' .. id) return end
  b.onClick(b)
end

local function clickSub(i)
  local p = panel()
  local subs = p and p:recursiveGetChildById('subs')
  local b = subs and subs:getChildByIndex(i)
  if not b then log('fail no sub tab ' .. i) return end
  log('sub ' .. i .. ' "' .. b:getText() .. '"')
  b.onClick(b)
end

local function runStep(step)
  if step['do'] == 'still' then
    log('still ' .. step.name .. ': ' .. state())
  elseif step['do'] == 'key' then
    log('key ' .. step.key)
    later(L.KEY_CHECK_MS, function()
      local d = dockApi()
      if L.keyWorked(step, d and d.isOpen and d.isOpen(), shownTab()) then
        log('key ' .. step.key .. ' worked: ' .. state())
        return
      end
      log('key ' .. step.key .. ' NOT seen, the tour calls the dock: ' .. state())
      if d then
        if step.open and step.tab and step.key ~= 'Alt+D' then d.openTab(step.tab) else d.toggle() end
      end
    end)
  elseif step['do'] == 'tab' then
    log('tab ' .. step.tab)
    clickTab(step.tab)
    later(1500, function() log('after tab ' .. step.tab .. ': ' .. state()) end)
  elseif step['do'] == 'sub' then
    clickSub(step.sub)
    later(1500, function() log('after sub ' .. step.sub .. ': ' .. state()) end)
  elseif step['do'] == 'scroll' then
    local bar = dockBar()
    if bar and bar:isVisible() then
      bar:setValue(bar:getMaximum())
      log('scroll to ' .. bar:getMaximum())
    else
      log('scroll: no scroll bar (the window fits)')
    end
    later(1000, function() log('after scroll: ' .. state()) end)
  elseif step['do'] == 'exit' then
    T.finish('ok')
  end
end

local function tour()
  fitWindow()
  if not dockApi() then log('fail no game_chaosdock') return T.finish('no dock') end
  log('dock enabled ' .. tostring(dockApi().isEnabled()) .. ': ' .. state())
  t0 = g_clock.millis()
  keepCardsClosed()
  log('ready')
  for _, step in ipairs(L.timeline()) do
    later(step.at, function()
      if not me() then
        log('fail out of the game')
        return T.finish('left the game')
      end
      runStep(step)
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
  log('armed')
  later(L.WATCHDOG_MS, function() T.finish('watchdog') end)
  later(8000, function() login(function() enter(tour) end) end)
end

function T.terminate()
  for _, e in ipairs(events) do removeEvent(e) end
  events = {}
end
