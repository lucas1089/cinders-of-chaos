-- Region music (O408; client/MANIFEST.md "Region music"): a looping track for where the player is, cross-faded on a
-- change of place. The rules are in musiclogic.lua; this file reads the client and drives g_sounds (base patch 0032).
--
-- Where the region comes from (client data only, no server message):
--   login     not in game (login and character list)
--   boss      the attacked creature is a boss (game_monsterbar's tier from the server), or a hurt boss is near
--   arena     the HUD of the arena, battleground, guild siege, Scorched Marches or invasion shows
--   dungeon   the HUD of a rift, dungeon, Infinity Tower, Ember Descent or raid shows; or a dungeon entrance is near
--   town      a protection zone, or a temple, depot or bank of the map markers is near (game_mapmarkers points)
--   hunt      anywhere else
--
-- Playback: two private sound channels (21 and 22; the base's Music channel 1 is faded out by the client at login and
-- left alone). A change starts the new track on the idle channel with a fade-in and fades the other one out: a
-- cross-fade. With base patch 0188 the played source loops in the engine (no gap) and can be watched (isPlaying); without
-- it the track loops through the channel queue (a short gap at each end). The client's audio switch, a hidden window and
-- (optional) an unfocused window fade the music out. Every engine call is guarded; no g_sounds: one warning, silence.

local M = ChaosMusicLogic

local CHANNEL_A, CHANNEL_B = 21, 22

local settings = M.normalize(nil)
local region = M.newState()
local events, handlers = {}, {}
local reported = {}
local noSoundLogged = false
local missing = {}
local playing        -- {region, channel, source, looping, at}: what sounds now
local idle = 1       -- the channel index the next track starts on (1 = A, 2 = B)
local silent         -- why the music is silent now (M.silentReason), or nil
local lastSnap, lastWanted

local function warnOnce(key, text)
  if reported[key] then return end
  reported[key] = true
  g_logger.warning('[chaosmusic] ' .. text)
end

local function safe(name, fn)
  return function(...)
    local ok, res = pcall(fn, ...)
    if not ok then
      warnOnce(name, name .. ': ' .. tostring(res))
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
  if g_sounds and g_sounds.getChannel then return true end
  if not noSoundLogged then
    noSoundLogged = true
    g_logger.warning('[chaosmusic] this client has no sound support (g_sounds, base patch 0032): no music')
  end
  return false
end

local function channel(i)
  local ok, ch = pcall(g_sounds.getChannel, i == 1 and CHANNEL_A or CHANNEL_B)
  return ok and ch or nil
end

local function audioOn()
  if not g_sounds.isAudioEnabled then return true end
  local ok, on = pcall(g_sounds.isAudioEnabled)
  return not ok or on ~= false
end

local function fileThere(path)
  if not path then return false end
  if not (g_resources and g_resources.fileExists) then return true end
  local ok, there = pcall(g_resources.fileExists, path)
  if not ok or there then return true end
  if not missing[path] then
    missing[path] = true
    g_logger.warning('[chaosmusic] music file missing: ' .. path)
  end
  return false
end

local function windowState()
  local visible, focused = true, true
  if g_window then
    if g_window.isVisible then
      local ok, v = pcall(g_window.isVisible)
      if ok and v == false then visible = false end
    end
    if g_window.hasFocus then
      local ok, f = pcall(g_window.hasFocus)
      if ok and f == false then focused = false end
    end
  end
  return visible, focused
end

-- fade out what plays (both channels: a cross-fade may still run)
local function stopAll(fade)
  if not g_sounds then return end
  for i = 1, 2 do
    local ch = channel(i)
    if ch then pcall(ch.stop, ch, fade or 0) end
  end
  playing = nil
end

-- start a region's track on the idle channel, fade the other one out
local function startTrack(name, fade)
  local path = M.file(name)
  local ch = channel(idle)
  if not ch then return false end
  local old = playing and channel(playing.channel) or nil
  if old then pcall(old.stop, old, M.CROSSFADE) end
  pcall(ch.stop, ch, 0)
  pcall(ch.setGain, ch, M.gain(settings))
  local ok, src = pcall(ch.play, ch, path, fade, 1.0)
  if not ok then
    warnOnce(path, path .. ': ' .. tostring(src))
    playing = nil
    return false
  end
  local looping = false
  if src ~= nil and src.setLooping then
    looping = pcall(src.setLooping, src, true)
  end
  if not looping then
    -- the channel replays its queue when the source ends (no fade on the repeat)
    pcall(ch.enqueue, ch, path, 0, 1.0)
  end
  playing = { region = name, channel = idle, source = src, looping = looping, at = nowMs() }
  idle = (idle == 1) and 2 or 1
  return true
end

-- true when the playing source ended without us (the client's stopAll at logout, the audio switch, a failed stream)
local function sourceGone()
  if not playing or not playing.source then return false end
  local src = playing.source
  if not src.isPlaying then return false end
  local ok, on = pcall(src.isPlaying, src)
  return ok and on == false and nowMs() - playing.at > 1500
end

-- ---------------------------------------------------------------- where the player is
local function moduleState(name)
  local mod = modules[name]
  if not mod or type(mod.getState) ~= 'function' then return nil end
  local ok, st = pcall(mod.getState)
  return ok and st or nil
end

local function tierOf(creature)
  local bar = modules.game_monsterbar
  if not creature or not bar or type(bar.tierInfo) ~= 'function' then return nil end
  local ok, tier = pcall(bar.tierInfo, creature:getId())
  return ok and tier or nil
end

local function bossInfo(player, pos)
  local target
  local c = g_game.getAttackingCreature and g_game.getAttackingCreature()
  if c then target = { tier = tierOf(c), health = c:getHealthPercent() } end
  local bosses = {}
  if g_map.getSpectators and pos then
    for _, s in ipairs(g_map.getSpectators(pos, false) or {}) do
      if s ~= player and s:isMonster() and tierOf(s) == 'boss' then
        bosses[#bosses + 1] = { pos = s:getPosition(), health = s:getHealthPercent() }
      end
    end
  end
  return target, bosses
end

local function inPz(player)
  if player.isInProtectionZone then
    local ok, pz = pcall(player.isInProtectionZone, player)
    if ok then return pz == true end
  end
  if PlayerStates and PlayerStates.Pz and player.hasState then
    local ok, pz = pcall(player.hasState, player, PlayerStates.Pz)
    if ok then return pz == true end
  end
  return false
end

local function snapshot()
  local snap = { online = g_game.isOnline() }
  if not snap.online then return snap end
  local player = g_game.getLocalPlayer()
  if not player then return snap end
  snap.pos = player:getPosition()
  snap.pz = inPz(player)
  local target, bosses = bossInfo(player, snap.pos)
  snap.boss = M.bossEngaged(target, bosses, snap.pos)
  local states = {}
  for _, a in ipairs(M.ACTIVITIES) do states[a.module] = moduleState(a.module) end
  snap.activity = M.activityRegion(states)
  local markers = modules.game_mapmarkers
  if markers and type(markers.getPois) == 'function' then
    local ok, pois = pcall(markers.getPois)
    if ok then snap.pois = pois end
  end
  return snap
end

-- ---------------------------------------------------------------- the loop
local function tick()
  if not hasSounds() then return end
  local snap = snapshot()
  lastSnap = snap
  lastWanted = M.wanted(snap)
  local name, changed = M.step(region, lastWanted, nowMs())
  local visible, focused = windowState()
  local why = M.silentReason({ enabled = settings.enabled, gain = M.gain(settings), audio = audioOn(), visible = visible,
    focused = focused, background = settings.background, file = fileThere(M.file(name)) })
  if why then
    if not silent and playing then stopAll(M.MUTE_FADE) end
    silent = why
    return
  end
  local wasSilent = silent ~= nil
  silent = nil
  if not playing or wasSilent or sourceGone() then
    startTrack(name, M.FIRST_FADE)
  elseif changed or playing.region ~= name then
    startTrack(name, M.CROSSFADE)
  end
end

-- the next tick soon (a game start: cross-fade from the login track without waiting for the cycle). forget: the client
-- stops every sound when a game ends (client.lua: g_sounds.stopAll), so the old track is gone: start afresh after it
local function restartSoon(forget)
  if forget then stopAll(0) end
  if events.restart then removeEvent(events.restart) end
  events.restart = scheduleEvent(function()
    events.restart = nil
    safe('tick', tick)()
  end, 400)
end

local function onGameStart()
  restartSoon(false)
end

local function onGameEnd()
  region = M.newState()
  restartSoon(true)
end

-- ---------------------------------------------------------------- settings (the System > Sound window of game_chaossound)
local function loadSettings()
  settings = M.normalize(g_settings.getNode('chaosMusic'))
end

local function saveSettings()
  g_settings.setNode('chaosMusic', settings)
end

function getSettings()
  return { enabled = settings.enabled, volume = settings.volume, background = settings.background }
end

-- t: {enabled, volume (0..100), background}; missing keys keep their value
function setSettings(t)
  if type(t) ~= 'table' then return end
  local merged = getSettings()
  for k, v in pairs(t) do merged[k] = v end
  local before = settings
  settings = M.normalize(merged)
  saveSettings()
  if playing and settings.enabled and before.volume ~= settings.volume then
    local ch = channel(playing.channel)
    if ch then pcall(ch.setGain, ch, M.gain(settings)) end
  end
  safe('tick', tick)()
end

-- for the live check (terminal: modules.game_chaosmusic.debugState())
function debugState()
  return { wanted = lastWanted, region = region.current, pending = region.pending,
    playing = playing and playing.region or nil, looping = playing and playing.looping or nil,
    channel = playing and playing.channel or nil, silent = silent, gain = M.gain(settings),
    pz = lastSnap and lastSnap.pz, boss = lastSnap and lastSnap.boss, activity = lastSnap and lastSnap.activity }
end

-- ---------------------------------------------------------------- init
function init()
  loadSettings()
  handlers.game = { onGameStart = safe('start', onGameStart), onGameEnd = safe('end', onGameEnd) }
  connect(g_game, handlers.game)
  events.tick = cycleEvent(safe('tick', tick), M.TICK_MS)
  safe('tick', tick)()
end

function terminate()
  for _, e in pairs(events) do removeEvent(e) end
  events = {}
  if handlers.game then disconnect(g_game, handlers.game) end
  handlers = {}
  stopAll(0)
end
