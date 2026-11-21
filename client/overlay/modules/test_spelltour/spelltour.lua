-- spelltour.lua: TEST ONLY, the spell showcase tour of .github/workflows/spells-video.yml (O692, server/README.md "Spell showcase video (O692)").
-- Armed only by the environment variable CHAOS_SPELLTOUR=1 (spelltourlogic.lua parseEnv): then it logs in with the staff account of
-- CHAOS_LIVE_ACCOUNT / CHAOS_LIVE_PASSWORD (a group 6 character of one showcase class, made in the CI database; the class is
-- CHAOS_SPELLTOUR_CLASS), enters, sets the ranks with `/spellrank ID 20`, writes "spelltour: ready" (the script starts the recording on that
-- line) and plays the timeline of the class: every shown spell cast with no Form, Form I A / B, Form II A / B (the Form picked by opcode 168
-- `pick`), then the combos, each with a caption (pt-BR) naming the spell and the Form. It ends with "spelltour: done ok" and exits.
-- Without the variable init() returns at once: no window, no hotkey, no hub card. The password is never logged.
ChaosSpellTour = {}
local T = ChaosSpellTour
local L = ChaosSpellTourLogic

local cfg
local events = {}
local finished = false
local caption

local function log(text)
  g_logger.info('spelltour: ' .. text)
end

local function later(ms, fn)
  events[#events + 1] = scheduleEvent(function()
    local ok, err = pcall(fn)
    if not ok then
      log('fail error ' .. tostring(err))
      T.finish('error', false)
    end
  end, math.max(0, ms))
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

-- a window that popped up on its own (daily reward, outfit) would hide the casts
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
  if caption then pcall(function() caption:destroy() end) caption = nil end
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

-- ---------------------------------------------------------------- the caption over the game
local function showCaption(text)
  if not caption then
    caption = g_ui.createWidget('Label', rootWidget)
    pcall(function()
      caption:setId('spellTourCaption')
      caption:setTextAlign(AlignCenter)
      caption:setColor('#ffe9a8')
      caption:setBackgroundColor('#000000b0')
      caption:setHeight(34)
      caption:setMarginTop(14)
      caption:addAnchor(AnchorTop, 'parent', AnchorTop)
      caption:addAnchor(AnchorHorizontalCenter, 'parent', AnchorHorizontalCenter)
      caption:setWidth(960)
      caption:setFocusable(false)
      caption:setPhantom(true)
    end)
  end
  pcall(function()
    caption:setText(text)
    caption:raise()
  end)
end

-- ---------------------------------------------------------------- the actions
local function distance(a, b)
  return math.max(math.abs(a.x - b.x), math.abs(a.y - b.y))
end

-- the nearest monster in view becomes the target (a spell that needs one); false when there is none
local function targetNearest()
  local player = me()
  if not player then return false end
  local pos = player:getPosition()
  local ok, list = pcall(function() return g_map.getSpectators(pos, false) end)
  if not ok or type(list) ~= 'table' then return false end
  local best, bestD
  for _, c in ipairs(list) do
    local okM, isMonster = pcall(function() return c:isMonster() end)
    if okM and isMonster then
      local okP, cp = pcall(function() return c:getPosition() end)
      if okP and cp and cp.z == pos.z then
        local d = distance(pos, cp)
        if bestD == nil or d < bestD then best, bestD = c, d end
      end
    end
  end
  if not best then return false end
  pcall(function() g_game.attack(best) end)
  return true
end

local function sendPick(spell, tier, pick)
  local protocol = g_game.getProtocolGame()
  if not protocol then return false end
  protocol:sendExtendedOpcode(L.OPCODE, json.encode({action = 'pick', data = {spell = spell, tier = tier, pick = pick}}))
  return true
end

local function act(a)
  local what = a['do']
  if what == 'rank' then
    log('rank ' .. a.spell)
    g_game.talk(L.RANK_SAY .. a.spell .. ' ' .. L.RANK)
  elseif what == 'caption' then
    local text = L.captionText(a.caption, rawget(_G, 'tr') or (rawget(_G, 'ChaosLocale') or {}).tr)
    log('caption ' .. text)
    showCaption(text)
  elseif what == 'pick' then
    log(('pick spell %d tier %d pick %d%s'):format(a.spell, a.tier, a.pick, sendPick(a.spell, a.tier, a.pick) and '' or ' (not connected)'))
  elseif what == 'cast' then
    local s = L.spell(a.spell)
    if not s then return log('fail no spell ' .. tostring(a.spell)) end
    if s.needTarget and not targetNearest() then log('no monster to target for ' .. s.name) end
    log(('cast %d %s%s'):format(a.spell, s.name, a.combo and (' (combo ' .. a.combo .. ' part ' .. a.part .. ')') or ''))
    g_game.talk(s.words)
  elseif what == 'phase' then
    log('phase ' .. a.name)
  elseif what == 'finish' then
    T.finish('script played', true)
  end
end

local function play(list, startAt)
  local limit = cfg.seconds * 1000
  for _, a in ipairs(list) do
    if a.at >= 0 then
      if a.at > limit and a['do'] ~= 'finish' then
        -- the time limit of the film: the script ends where it is
      else
        later(startAt + a.at - g_clock.millis(), function()
          if finished then return end
          if not me() then
            log('fail out of the game')
            return T.finish('left the game', false)
          end
          act(a)
        end)
      end
    end
  end
  if list[#list].at > limit then
    later(startAt + limit - g_clock.millis(), function() T.finish('time limit', true) end)
  end
end

local function tour()
  pcall(function() g_game.setChaseMode(DontChase) end)
  local list, length = L.timeline(cfg.class)
  if not list then
    log('fail ' .. tostring(length))
    return T.finish('no timeline', false)
  end
  local kinds, combos = L.shows(cfg.class)
  local names = {}
  for k in pairs(kinds) do names[#names + 1] = k end
  table.sort(names)
  log(('class %s: %d actions, %d s long; Form kinds: %s; combos: %s'):format(cfg.class, #list, math.floor(length / 1000), table.concat(names, ' '), table.concat(combos, ' ')))
  -- the set-up (ranks) runs before the ready line, at its negative times from "now + the length of the set-up"
  local first = 0
  for _, a in ipairs(list) do if a.at < first then first = a.at end end
  local base = g_clock.millis() - first
  for _, a in ipairs(list) do
    if a.at < 0 then
      later(base + a.at - g_clock.millis(), function() act(a) end)
    end
  end
  local readyAt = base
  later(readyAt - g_clock.millis(), function()
    fitWindow()
    pcall(function() g_app.setMaxFps(30) end)
    log('ready')
    play(list, g_clock.millis())
  end)
end

function T.init()
  local err
  cfg, err = L.parseEnv(os.getenv)
  if not cfg then
    if err ~= 'off' then log('not armed: ' .. tostring(err)) end
    return
  end
  log(('armed: account %s, class %s, at most %d s of film'):format(cfg.account, cfg.class, cfg.seconds))
  -- game_chaosspells and game_spellranks are sandboxed: their data tables live in modules.<name>, not in _G, where the logic reads them
  local mods = rawget(_G, 'modules') or {}
  for name, key in pairs({game_chaosspells = 'ChaosSpellData', game_spellranks = 'ChaosFormsData', client_chaos_locale = 'ChaosLocale'}) do
    local value = mods[name] and mods[name][key]
    if rawget(_G, key) == nil and value ~= nil then rawset(_G, key, value) end
  end
  if rawget(_G, 'ChaosSpellData') == nil then log('no spell data: game_chaosspells not loaded') end
  if rawget(_G, 'ChaosFormsData') == nil then log('no Forms data: game_spellranks not loaded') end
  -- the login, the set-up, the film and the outro: the client leaves by itself when a step never came (the script cuts it first)
  later((cfg.seconds + 900) * 1000, function() T.finish('watchdog', false) end)
  later(8000, function() login(function() enter(tour) end) end)
end

function T.terminate()
  for _, e in ipairs(events) do removeEvent(e) end
  events = {}
  if caption then pcall(function() caption:destroy() end) caption = nil end
end
