-- luajit chaossound_test.lua && lua5.3 chaossound_test.lua: the engine file against a mocked client (no init(): the
-- hooks other modules call and the guards around g_sounds)
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
local fails, checks = 0, 0
local function eq(a, b, what)
  checks = checks + 1
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

local now = 0
local warnings = {}
g_logger = { warning = function(m) warnings[#warnings + 1] = m end, info = function() end }
g_clock = { millis = function() return now end }
g_game = { isOnline = function() return false end }
modules = {}
SoundChannels = { Music = 1, Ambient = 2, Effect = 3, Bot = 4 }
dofile(dir .. 'soundlogic.lua')

-- 1. a client without g_sounds: nothing plays, one warning
g_sounds = nil
dofile(dir .. 'chaossound.lua')
eq(playEvent('hit', 0), false, 'no g_sounds: nothing plays')
now = 1000
eq(playEvent('hit', 0), false, 'no g_sounds: still nothing')
eq(#warnings, 1, 'no g_sounds: logged once')
eq(warnings[1]:find('g_sounds', 1, true) ~= nil, true, 'the warning names g_sounds')

-- 2. a client with sound
local played, audio, chanOn, chanGain = {}, true, true, 1
local channel = {
  isEnabled = function() return chanOn end,
  getGain = function() return chanGain end,
}
g_sounds = {
  isAudioEnabled = function() return audio end,
  getChannel = function(id) channel.id = id; return channel end,
  play = function(file, fade, gain) played[#played + 1] = { file = file, fade = fade, gain = gain }; return {} end,
  preload = function() end,
}
now = 10000
eq(playEvent('hit', 0), true, 'a hit plays')
eq(#played, 1, 'one sound')
eq(played[1].file:match('^/modules/game_chaossound/sounds/hit_%d%.ogg$') ~= nil, true, 'the file path')
eq(played[1].gain > 0 and played[1].gain <= 1, true, 'the gain')
eq(channel.id, SoundChannels.Effect, 'the Effect channel is asked')

now = 20000
audio = false
eq(playEvent('hit', 0), false, 'the client audio switch off: silent')
audio = true
chanOn = false
now = 30000
eq(playEvent('hit', 0), false, 'the Effect channel disabled: silent')
chanOn = true
chanGain = 0
now = 40000
eq(playEvent('hit', 0), false, 'the Effect channel gain 0: silent')
chanGain = 1
now = 50000
local before = played[#played]
eq(playEvent('goal', 0), true, 'a goal plays')
local full = played[#played].gain
chanGain = 0.5
now = 60000
eq(playEvent('goal', 0), true, 'a goal plays at half the channel gain')
eq(math.abs(played[#played].gain - full / 2) < 1e-9, true, 'the channel gain scales the sound')
chanGain = 1

-- 3. an engine error does not escape
g_sounds.play = function() error('boom') end
now = 70000
eq(playEvent('goal', 0), false, 'a failing play is caught')
eq(#warnings, 2, 'and logged once')
now = 80000
playEvent('goal', 0)
eq(#warnings, 2, 'the same file is not logged again')
g_sounds.play = function(file, fade, gain) played[#played + 1] = { file = file, fade = fade, gain = gain }; return {} end

-- 4. rare loot, and the loot filter's own alert
local n = #played
now = 100000
onLootKill({ drops = { { rank = 100 } } }, true)
eq(#played, n, 'the loot filter already played its alert: silent')
onLootKill({ drops = { { rank = 100 } } }, false)
eq(#played, n + 1, 'a unique plays')
eq(played[#played].file:find('loot_unique', 1, true) ~= nil, true, 'the unique sound')
now = 101000
onLootKill({ drops = { { rank = 2 } } }, false)
eq(#played, n + 1, 'a common drop is silent')
onLootKill('junk', false)
onLootKill(nil)
eq(#played, n + 1, 'junk data is ignored')
now = 102000
onGoalDone()
eq(played[#played].file:find('goal', 1, true) ~= nil, true, 'the goal hook plays the goal sound')

-- 5. the hooks other modules call are exported and the unknown event is harmless
eq(playEvent('no_such_event', 0), false, 'an unknown event')
eq(type(getLastSound()), 'table', 'the last sound is kept for the in-game check')

-- 6. the other modules call it the way they must: guarded, by name
do
  local function read(rel)
    local f = io.open(dir .. rel, 'rb'); local s = f and f:read('*a') or ''; if f then f:close() end
    return s
  end
  eq(read('../game_lootfilter/lootfilter.lua'):find('cs.onLootKill', 1, true) ~= nil, true, 'game_lootfilter calls onLootKill')
  eq(read('../game_goals/goals.lua'):find('cs.onGoalDone', 1, true) ~= nil, true, 'game_goals calls onGoalDone')
end

print(string.format('chaossound_test: %d checks, %d failed', checks, fails))
os.exit(fails == 0 and 0 or 1)
