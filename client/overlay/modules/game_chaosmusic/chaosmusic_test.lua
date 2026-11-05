-- luajit chaosmusic_test.lua && lua5.3 chaosmusic_test.lua: the engine file against a mocked client (channels,
-- cross-fade, loops, settings, window, game start and end)
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
local fails, checks = 0, 0
local function eq(a, b, what)
  checks = checks + 1
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

-- ---------------------------------------------------------------- the mocked client
local now = 0
local warnings = {}
g_logger = { warning = function(m) warnings[#warnings + 1] = m end, info = function() end }
g_clock = { millis = function() return now end }
local cycles, scheduled = {}, {}
function cycleEvent(fn, ms) local e = { fn = fn, ms = ms } cycles[#cycles + 1] = e return e end
function scheduleEvent(fn, ms) local e = { fn = fn, at = now + ms } scheduled[#scheduled + 1] = e return e end
function removeEvent(e) if e then e.dead = true end end
function connect(obj, t) obj.__handlers = t end
function disconnect(obj) obj.__handlers = nil end
local store = {}
g_settings = { getNode = function(k) return store[k] end, setNode = function(k, v) store[k] = v end }
local visible, focused = true, true
g_window = { isVisible = function() return visible end, hasFocus = function() return focused end }
local files = {}
g_resources = { fileExists = function(p) return files[p] ~= false end }

local online, pz, attacking = false, false, nil
local player = {
  getPosition = function() return { x = 100, y = 100, z = 7 } end,
  isInProtectionZone = function() return pz end,
}
g_game = {
  isOnline = function() return online end,
  getLocalPlayer = function() return online and player or nil end,
  getAttackingCreature = function() return attacking end,
}
local spectators = {}
g_map = { getSpectators = function() return spectators end }
local tiers = {}
modules = { game_monsterbar = { tierInfo = function(id) return tiers[id] end } }

-- channels: what each one was told
local looping = true -- the source has setLooping (base patch 0188)
local audio = true
local log = {}
local function newChannel(id)
  local ch = { id = id, gain = 1 }
  function ch.play(self, file, fade, gain)
    local src = { file = file, playing = true }
    if looping then
      function src.setLooping(s, on) s.loop = on end
      function src.isPlaying(s) return s.playing end
    end
    self.src = src
    log[#log + 1] = { 'play', self.id, file, fade, self.gain }
    return src
  end
  function ch.stop(self, fade) log[#log + 1] = { 'stop', self.id, fade } end
  function ch.enqueue(self, file, fade, gain) log[#log + 1] = { 'enqueue', self.id, file, fade } end
  function ch.setGain(self, g) self.gain = g; log[#log + 1] = { 'gain', self.id, g } end
  return ch
end
local channels = {}
local function installSounds()
  g_sounds = {
    getChannel = function(id) channels[id] = channels[id] or newChannel(id) return channels[id] end,
    isAudioEnabled = function() return audio end,
  }
end

local function tick(ms)
  now = now + (ms or 500)
  for _, e in ipairs(scheduled) do
    if not e.dead and not e.done and e.at <= now then e.done = true e.fn() end
  end
  for _, c in ipairs(cycles) do if not c.dead then c.fn() end end
end

local function last(kind)
  for i = #log, 1, -1 do if log[i][1] == kind then return log[i] end end
  return nil
end
local function count(kind)
  local n = 0
  for _, e in ipairs(log) do if e[1] == kind then n = n + 1 end end
  return n
end

dofile(dir .. 'musiclogic.lua')
local M = ChaosMusicLogic

-- 1. no g_sounds: one warning, nothing breaks
g_sounds = nil
dofile(dir .. 'chaosmusic.lua')
init()
tick() tick()
eq(#warnings, 1, 'no g_sounds: one warning')
eq(warnings[1] and warnings[1]:find('g_sounds', 1, true) ~= nil, true, 'the warning names g_sounds')
terminate()

-- 2. login screen: the login track on the first private channel, looped by the engine
installSounds()
warnings = {}
cycles, scheduled = {}, {}
dofile(dir .. 'chaosmusic.lua')
init()
local p = last('play')
eq(p and p[3], M.file('login'), 'offline: the login track')
eq(p and p[2], 21, 'on channel 21 (the base Music channel 1 is left alone)')
eq(p and p[4], M.FIRST_FADE, 'first track fades in')
eq(channels[21].src.loop, true, 'the source loops in the engine')
eq(count('enqueue'), 0, 'no channel queue when the source loops')
eq(math.abs(channels[21].gain - M.gain(M.normalize(nil))) < 1e-9, true, 'gain from the default volume')
tick() tick()
eq(count('play'), 1, 'no restart while the region holds')

-- 3. into the game in a protection zone: cross-fade to town
online, pz = true, true
g_game.__handlers.onGameStart()
tick(500)
p = last('play')
eq(p and p[3], M.file('town'), 'in game in a protection zone: town')
eq(p and p[2], 22, 'the new track on the other channel')
eq(p and p[4], M.CROSSFADE, 'it fades in over the cross-fade')
local faded = false
for _, e in ipairs(log) do if e[1] == 'stop' and e[2] == 21 and e[3] == M.CROSSFADE then faded = true end end
eq(faded, true, 'the login track fades out over the cross-fade')
local plays = count('play')

-- 4. a short step out of town keeps the track; a longer one switches to hunt
pz = false
for _ = 1, 10 do tick(500) end -- 5 s
eq(count('play'), plays, 'out of town 5 s: no change')
pz = true
tick(500)
pz = false
for _ = 1, 15 do tick(500) end -- 7.5 s
eq(count('play'), plays, 'out again 7.5 s: no change')
tick(500) tick(500)
p = last('play')
eq(p and p[3], M.file('hunt'), 'out of town 8 s: hunt')
eq(p and p[2], 21, 'channels take turns')

-- 5. a boss: at once (after the hold), and it stays after the fight
attacking = { getId = function() return 77 end, getHealthPercent = function() return 90 end }
tiers[77] = 'boss'
for _ = 1, 6 do tick(500) end
p = last('play')
eq(p and p[3], M.file('boss'), 'attacking a boss: the boss track')
attacking = nil
for _ = 1, 10 do tick(500) end
eq(last('play')[3], M.file('boss'), 'boss gone 5 s: still the boss track')
for _ = 1, 12 do tick(500) end
eq(last('play')[3], M.file('hunt'), 'boss gone over 10 s: hunt again')

-- 6. an activity HUD: arena
modules.game_arena = { getState = function() return { hud = true } end }
for _ = 1, 8 do tick(500) end
eq(last('play')[3], M.file('arena'), 'arena HUD: the arena track')
modules.game_arena = nil

-- 7. the volume slider changes the playing channel's gain live
setSettings({ volume = 80 })
local g = last('gain')
eq(g and math.abs(g[3] - M.gain({ enabled = true, volume = 80 })) < 1e-9, true, 'volume: the playing channel follows')
eq(store.chaosMusic and store.chaosMusic.volume, 80, 'volume saved')
eq(getSettings().volume, 80, 'getSettings reads it back')

-- 8. music off: both channels fade out; on again: the track starts again
plays = count('play')
local stops = count('stop')
setSettings({ enabled = false })
eq(count('stop') - stops, 2, 'off: both channels stop')
eq(last('stop')[3], M.MUTE_FADE, 'with the mute fade')
tick() tick()
eq(count('play'), plays, 'off: nothing starts')
eq(debugState().silent, 'off', 'debug: silent because off')
setSettings({ enabled = true })
eq(count('play'), plays + 1, 'on again: the track starts')

-- 9. minimized: silent; back: plays; unfocused plays unless asked
plays = count('play')
visible = false
tick()
eq(debugState().silent, 'hidden', 'minimized: silent')
visible = true
tick()
eq(count('play'), plays + 1, 'shown again: the music comes back')
focused = false
tick()
eq(debugState().silent, nil, 'unfocused: plays by default')
setSettings({ background = true })
eq(debugState().silent, 'unfocused', 'unfocused muted on request')
focused = true
setSettings({ background = false })
tick()

-- 10. the client stopped the source behind our back (logout's stopAll, a failed stream): it starts again
plays = count('play')
local cur = debugState().channel == 1 and channels[21] or channels[22]
cur.src.playing = false
tick(2000)
eq(count('play'), plays + 1, 'a source that ended is started again')

-- 11. logout: the login track after the client's stopAll
online = false
g_game.__handlers.onGameEnd()
tick(500)
eq(last('play')[3], M.file('login'), 'logout: the login track')
eq(last('play')[4], M.FIRST_FADE, 'from silence: the first fade')

-- 12. an old client (no source bindings): the channel queue loops the track
looping = false
online, pz = true, true
g_game.__handlers.onGameStart()
tick(500)
local q = last('enqueue')
eq(q and q[3], M.file('town'), 'no setLooping: the track is queued on its channel')
eq(q and q[4], 0, 'the repeat has no fade')
looping = true

-- 13. a missing file: one warning, silence
files[M.file('hunt')] = false
pz = false
warnings = {}
for _ = 1, 24 do tick(500) end
eq(debugState().silent, 'file', 'a missing file: silent')
eq(#warnings, 1, 'a missing file: one warning')
tick() tick()
eq(#warnings, 1, 'still one warning')

terminate()
eq(#cycles > 0 and cycles[#cycles].dead, true, 'terminate removes the tick')

print(string.format('chaosmusic_test: %d checks, %d failures', checks, fails))
if fails > 0 then os.exit(1) end
