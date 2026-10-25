-- Game sound (O238; client/MANIFEST.md "Game sound"): short sounds for the fight, spells and rewards. Lua only, no base
-- patch beyond 0032 (the sound framework, g_sounds). The rules (which sound, how loud, the rate limits) are in
-- soundlogic.lua; this file connects them to the client.
--
-- Where each event comes from:
--   your hit, critical hit    g_map.onImpactText (base patch 0100): a damage number of mode "dealt"; a hit you take is mode "received"
--   a kill                    Creature.onHealthPercentChange to 0 on a monster that a number of yours hit in the last 2.5 s
--   spell casts               a magic effect added to a tile (Tile.onAddThing; the engine switch is
--                             g_game.enableTileThingLuaCallback, shared with game_tileoverlays); the effect id is mapped
--                             to an element with game_visualfx's VisualFxLogic.EFFECT_THEME
--   dodge, block              the dodge whoosh (416) / the stock block hit (3) on the player's own tile
--   level up                  LocalPlayer.onLevelChange to a higher level
--   rare loot                 game_lootfilter forwards each kill's drops (onLootKill); silent when the loot filter's own
--                             rule sound already played for that kill
--   goals                     game_goals forwards "done" (onGoalDone)
--   windows, buttons          UIWindow.onVisibilityChange and UIButton.onMouseRelease (off by default)
--
-- Volume: the engine plays every sound with g_sounds.play (not the Effect channel's play, which cuts the sound before it:
-- one sound at a time); the gain is the module's volume x the Effect channel's gain (the client's own sound options,
-- SoundChannels.Effect; the Interface sounds use the UI channel when the client has one) x the distance fade. The client's
-- audio switch (g_sounds.isAudioEnabled) and a disabled channel mute everything. A client without g_sounds logs once and
-- plays nothing. Every engine call is guarded.

local S = ChaosSoundLogic

local SETTLE_MS = 2500      -- after the game starts: no window and button sounds (the windows come up)
local KEEPALIVE_MS = 2000   -- the engine's tile callback switch is re-asserted this often while spell sounds are on

local settings = S.normalize(nil)
local mixer = S.newMixer()
local myHits = S.newHits()
local window
local updatingUi = false
local noSoundLogged = false
local reported = {}
local events, handlers = {}, {}
local gameStartedAt = 0
local lastLevel
local themesCache
local lastPlayed          -- {key, file, gain, at}: the last sound (for the in-game check)
local preloaded = false

local function safe(name, fn)
  return function(...)
    local ok, res = pcall(fn, ...)
    if not ok then
      if not reported[name] then
        reported[name] = true
        g_logger.warning('[chaossound] ' .. name .. ': ' .. tostring(res))
      end
      return nil
    end
    return res
  end
end

local function nowMs()
  return g_clock.millis()
end

-- ---------------------------------------------------------------- engine
local function hasSounds()
  if g_sounds then return true end
  if not noSoundLogged then
    noSoundLogged = true
    g_logger.warning('[chaossound] this client has no sound support (g_sounds, base patch 0032): game sounds are not played')
  end
  return false
end

-- the channel a group plays on: the Effect channel, and for the interface sounds the UI channel when the client has one
local function channelOf(group)
  if not g_sounds.getChannel then return nil end
  local id
  if group == 'ui' and type(ENumericSoundType) == 'table' then id = ENumericSoundType.UI end
  id = id or (type(SoundChannels) == 'table' and SoundChannels.Effect) or nil
  if not id then return nil end
  local ok, ch = pcall(g_sounds.getChannel, id)
  return ok and ch or nil
end

-- 0..1: the client's own volume for this group (0 when the audio is off or the channel is disabled); 1 when unknown
local function clientVolume(group)
  if g_sounds.isAudioEnabled then
    local ok, on = pcall(g_sounds.isAudioEnabled)
    if ok and on == false then return 0 end
  end
  local ch = channelOf(group)
  if not ch then return 1 end
  if ch.isEnabled then
    local ok, on = pcall(ch.isEnabled, ch)
    if ok and on == false then return 0 end
  end
  if ch.getGain then
    local ok, gain = pcall(ch.getGain, ch)
    if ok and type(gain) == 'number' then return math.max(0, math.min(1, gain)) end
  end
  return 1
end

local function playFile(path, gain)
  local ok, src = pcall(g_sounds.play, path, 0, gain)
  if not ok then
    if not reported[path] then
      reported[path] = true
      g_logger.warning('[chaossound] ' .. path .. ': ' .. tostring(src))
    end
    return false
  end
  return src ~= nil
end

local function preload()
  if preloaded or not hasSounds() or not g_sounds.preload then return end
  preloaded = true
  for _, name in ipairs(S.allFiles()) do pcall(g_sounds.preload, S.DIR .. name .. '.ogg') end
end

-- one event: the mixer decides, the engine plays. opts.dist: tiles from the player
local function fire(key, dist)
  if not settings.enabled then return false end
  local set = S.SETS[key]
  if not set or not settings[set.group] then return false end
  if not hasSounds() then return false end
  local volume = clientVolume(set.group)
  if volume <= 0 then return false end
  local path, gain = S.request(mixer, key, nowMs(), { dist = dist, settings = settings, volume = volume })
  if not path then return false end
  lastPlayed = { key = key, file = path, gain = gain, at = nowMs() }
  return playFile(path, gain)
end

-- ---------------------------------------------------------------- the player
local function playerPos()
  if not g_game.isOnline() then return nil end
  local p = g_game.getLocalPlayer()
  return p and p:getPosition() or nil
end

local function distanceTo(pos)
  return S.distance(playerPos(), pos)
end

-- ---------------------------------------------------------------- combat: damage numbers and kills
local function onImpactText(thing, text, mode, typeId, value, percent, creatureId, pos)
  if not (settings.enabled and settings.combat) then return false end
  local key = S.impactEvent(mode, typeId, value)
  if not key then return false end
  local dist = 0
  if mode == S.MODE.DAMAGE_DEALT then
    S.noteHit(myHits, creatureId, nowMs())
    dist = distanceTo(pos)
  end
  fire(key, dist)
  return false -- never drops the number
end

local function onHealthPercentChange(creature, percent)
  if not (settings.enabled and settings.combat) or percent == nil or percent > 0 then return end
  if not creature or creature:isLocalPlayer() or not creature:isMonster() then return end
  if not S.isMyKill(myHits, creature:getId(), nowMs()) then return end
  fire('kill', distanceTo(creature:getPosition()))
end

-- ---------------------------------------------------------------- spells: magic effects
local function themes()
  if themesCache == nil then
    local vfx = modules.game_visualfx
    local logic = vfx and vfx.VisualFxLogic
    themesCache = logic and logic.EFFECT_THEME or false
    if not themesCache then
      g_logger.warning('[chaossound] game_visualfx is not loaded: spell sounds are not played')
    end
  end
  return themesCache or nil
end

local function onAddThing(tile, thing)
  if not thing or not (settings.enabled and (settings.spells or settings.combat)) then return end
  if not thing:isEffect() then return end
  local key, own = S.effectEvent(thing:getId(), themes())
  if not key then return end
  local pos = tile:getPosition()
  local dist = distanceTo(pos)
  if own and dist > 0 then return end
  fire(key, dist)
end

-- the tile callback switch is shared with game_tileoverlays (it turns it off with its option): keep it on while we need it
local function wantTileCallback()
  return settings.enabled and (settings.spells or settings.combat) and g_game.isOnline()
end

local function keepTileCallback()
  if not g_game.enableTileThingLuaCallback then return end
  if wantTileCallback() then
    if not (g_game.isTileThingLuaCallbackEnabled and g_game.isTileThingLuaCallbackEnabled()) then
      g_game.enableTileThingLuaCallback(true)
    end
  end
end

-- ---------------------------------------------------------------- level up
local function onLevelChange(player, level, percent, oldLevel)
  level = tonumber(level)
  if not level then return end
  local was = tonumber(oldLevel)
  if not was or was < 1 then was = lastLevel end
  lastLevel = level
  -- the first level the client is told about at login is not a level up
  if nowMs() - gameStartedAt < SETTLE_MS then return end
  if was and level > was then fire('levelup', 0) end
end

-- ---------------------------------------------------------------- interface
local function onVisibilityChange(widget, visible)
  if not (settings.enabled and settings.ui) or not g_game.isOnline() then return end
  if nowMs() - gameStartedAt < SETTLE_MS or not widget or widget == window then return end
  if not widget:getParent() then return end
  fire(visible and 'ui_open' or 'ui_close', 0)
end

local function onMouseRelease(button, mousePos, mouseButton)
  if not (settings.enabled and settings.ui) or not g_game.isOnline() then return false end
  if nowMs() - gameStartedAt < SETTLE_MS then return false end
  if mouseButton ~= MouseLeftButton or not button:isEnabled() then return false end
  if mousePos and button.containsPoint and not button:containsPoint(mousePos) then return false end
  fire('ui_click', 0)
  return false -- never takes the click
end

-- ---------------------------------------------------------------- hooks other modules call
-- game_lootfilter: a kill's drops (the server's rare-drop lines) and whether its own rule sound played for the kill
function onLootKill(data, alerted)
  if type(data) ~= 'table' then return end
  local key = S.lootEvent(data.drops, alerted)
  if key then fire(key, 0) end
end

-- game_goals: a goal was completed
function onGoalDone()
  fire('goal', 0)
end

-- any module: play an event of the sets by name (a sound for a feature that has its own hook), dist in tiles
function playEvent(key, dist)
  return fire(key, tonumber(dist) or 0)
end

function getLastSound()
  return lastPlayed
end

-- ---------------------------------------------------------------- settings
local function loadSettings()
  settings = S.normalize(g_settings.getNode('chaosSound'))
end

local function saveSettings()
  g_settings.setNode('chaosSound', settings)
end

local function volumeNames()
  return { quiet = tr('Quiet'), normal = tr('Normal'), loud = tr('Loud') }
end

local function refreshWindow()
  if not window then return end
  updatingUi = true
  for _, id in ipairs({ 'enabled', 'combat', 'spells', 'events', 'ui' }) do window[id]:setChecked(settings[id]) end
  local combo = window.volumeCombo
  local names = volumeNames()
  combo:clearOptions()
  for _, k in ipairs(S.VOLUME_ORDER) do combo:addOption(names[k], k) end
  for i, k in ipairs(S.VOLUME_ORDER) do
    if k == settings.volume then combo:setCurrentIndex(i) end
  end
  for _, id in ipairs({ 'combat', 'spells', 'events', 'ui' }) do window[id]:setEnabled(settings.enabled) end
  combo:setEnabled(settings.enabled)
  updatingUi = false
end

local function onUiChange()
  if updatingUi or not window then return end
  local t = {}
  for _, id in ipairs({ 'enabled', 'combat', 'spells', 'events', 'ui' }) do t[id] = window[id]:isChecked() end
  local v = window.volumeCombo:getCurrentOption()
  t.volume = v and S.VOLUMES[v.data] and v.data or settings.volume
  settings = S.normalize(t)
  saveSettings()
  refreshWindow()
  keepTileCallback()
end

function show()
  if not window then return end
  refreshWindow()
  window:show()
  window:raise()
  window:focus()
end

function hide()
  if window then window:hide() end
end

function toggle()
  if window and window:isVisible() then hide() else show() end
end

-- ---------------------------------------------------------------- game start and end
local function reset()
  mixer = S.newMixer()
  myHits = S.newHits()
  lastLevel = nil
  gameStartedAt = nowMs()
end

local function onGameStart()
  reset()
  preload()
  local p = g_game.getLocalPlayer()
  lastLevel = p and p:getLevel() or nil
  keepTileCallback()
end

local function onGameEnd()
  reset()
end

local function tick()
  if not g_game.isOnline() then return end
  keepTileCallback()
  S.prune(myHits, nowMs())
end

-- ---------------------------------------------------------------- init
function init()
  g_ui.importStyle('chaossound')
  loadSettings()
  handlers.map = { onImpactText = safe('impact', onImpactText) }
  handlers.creature = { onHealthPercentChange = safe('health', onHealthPercentChange) }
  handlers.tile = { onAddThing = safe('effect', onAddThing) }
  handlers.player = { onLevelChange = safe('level', onLevelChange) }
  handlers.game = { onGameStart = safe('start', onGameStart), onGameEnd = safe('end', onGameEnd) }
  handlers.window = { onVisibilityChange = safe('window', onVisibilityChange) }
  handlers.button = { onMouseRelease = safe('click', onMouseRelease) }
  local ok, ui = pcall(g_ui.createWidget, 'ChaosSoundWindow', rootWidget)
  if ok and ui then
    window = ui
    window:hide()
    for _, id in ipairs({ 'enabled', 'combat', 'spells', 'events', 'ui' }) do window[id].onCheckChange = safe('ui', onUiChange) end
    window.volumeCombo.onOptionChange = safe('ui', onUiChange)
  else
    g_logger.warning('[chaossound] settings window not loaded: ' .. tostring(ui))
  end
  connect(g_map, handlers.map)
  connect(Creature, handlers.creature)
  connect(Tile, handlers.tile)
  connect(LocalPlayer, handlers.player)
  connect(g_game, handlers.game)
  connect(UIWindow, handlers.window)
  connect(UIButton, handlers.button)
  events.tick = cycleEvent(safe('tick', tick), KEEPALIVE_MS)
  if g_game.isOnline() then onGameStart() end
end

function terminate()
  if events.tick then removeEvent(events.tick) end
  events = {}
  disconnect(g_map, handlers.map)
  disconnect(Creature, handlers.creature)
  disconnect(Tile, handlers.tile)
  disconnect(LocalPlayer, handlers.player)
  disconnect(g_game, handlers.game)
  disconnect(UIWindow, handlers.window)
  disconnect(UIButton, handlers.button)
  -- the tile callback switch belongs to game_tileoverlays when it is loaded; without it nothing else needs the switch
  if not modules.game_tileoverlays and g_game.enableTileThingLuaCallback then g_game.enableTileThingLuaCallback(false) end
  if window then window:destroy() window = nil end
  handlers = {}
end
