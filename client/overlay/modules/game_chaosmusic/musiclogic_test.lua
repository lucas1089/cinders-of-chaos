-- luajit musiclogic_test.lua && lua5.3 musiclogic_test.lua: the rules of the region music (no client needed)
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'musiclogic.lua')
local M = ChaosMusicLogic

local fails, checks = 0, 0
local function eq(a, b, what)
  checks = checks + 1
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

-- 1. settings
local s = M.normalize(nil)
eq(s.enabled, true, 'default: on')
eq(s.volume, 50, 'default: moderate volume')
eq(s.background, false, 'default: plays when not focused')
s = M.normalize({ enabled = false, volume = '130', background = true })
eq(s.enabled, false, 'off kept')
eq(s.volume, 100, 'volume clamped high')
eq(s.background, true, 'background kept')
eq(M.normalize({ volume = -4 }).volume, 0, 'volume clamped low')
eq(M.normalize({ volume = 0 / 0 }).volume, 50, 'NaN volume is the default')
eq(M.normalize({ volume = 37.6 }).volume, 38, 'volume rounded')

-- 2. gain curve
eq(M.gain({ enabled = false, volume = 80 }), 0, 'off: no gain')
eq(M.gain({ enabled = true, volume = 0 }), 0, 'volume 0: no gain')
eq(M.gain({ enabled = true, volume = 100 }), 1, 'full volume: 1')
local half = M.gain({ enabled = true, volume = 50 })
eq(half > 0.3 and half < 0.4, true, 'half way is about -9 dB')
eq(M.gain({ enabled = true, volume = 60 }) > half, true, 'louder slider, louder music')

-- 3. files: one per region, all under the module
for _, r in ipairs(M.REGIONS) do
  eq(M.file(r), '/modules/game_chaosmusic/music/music_' .. r .. '.ogg', 'file of ' .. r)
end
eq(M.file('nowhere'), nil, 'no file for an unknown region')
-- the committed files and the generator's csv agree with the table
local csv = io.open(dir .. '../../../tools/music_sources.csv')
if csv then
  local rows = {}
  for line in csv:lines() do
    local file, region = line:match('^([^,]+),([^,]+),')
    if file and file ~= 'file' then rows[region] = file end
  end
  csv:close()
  for _, r in ipairs(M.REGIONS) do eq(rows[r], M.TRACKS[r], 'csv row of ' .. r) end
  for r in pairs(rows) do eq(M.TRACKS[r] ~= nil, true, 'csv region ' .. r .. ' is played') end
  for _, r in ipairs(M.REGIONS) do
    local f = io.open(dir .. 'music/' .. M.TRACKS[r] .. '.ogg', 'rb')
    eq(f ~= nil, true, 'music file of ' .. r .. ' is there')
    if f then f:close() end
  end
else
  print('note: client/tools/music_sources.csv not found from here; csv checks skipped')
end

-- 4. points of interest
local pos = { x = 100, y = 100, z = 7 }
eq(M.poiRegion(pos, { { k = 'temple', x = 110, y = 95, z = 7 } }), 'town', 'a temple near: town')
eq(M.poiRegion(pos, { { k = 'depot', x = 118, y = 100, z = 7 } }), 'town', 'a depot at the edge of the range')
eq(M.poiRegion(pos, { { k = 'depot', x = 119, y = 100, z = 7 } }), nil, 'a depot out of range')
eq(M.poiRegion(pos, { { k = 'temple', x = 100, y = 100, z = 6 } }), nil, 'a temple on another floor')
eq(M.poiRegion(pos, { { k = 'hunt', x = 100, y = 100, z = 7 } }), nil, 'a hunting area is not town')
eq(M.poiRegion(pos, { { k = 'dungeon', x = 105, y = 105, z = 7 } }), 'dungeon', 'a dungeon entrance near')
eq(M.poiRegion(pos, { { k = 'dungeon', x = 105, y = 105, z = 7 }, { k = 'bank', x = 101, y = 101, z = 7 } }), 'town',
  'town wins over a dungeon entrance')
eq(M.poiRegion(nil, {}), nil, 'no position')
eq(M.poiRegion(pos, 'junk'), nil, 'junk list')
eq(M.poiRegion(pos, { 'junk', { k = 'bank' } }), nil, 'junk rows')

-- 5. activities
eq(M.activityRegion({ game_rift = { hud = true } }), 'dungeon', 'a rift HUD: dungeon')
eq(M.activityRegion({ game_arena = { hud = true } }), 'arena', 'an arena HUD: arena')
eq(M.activityRegion({ game_battleground = { hud = true, window = true } }), 'arena', 'battleground')
eq(M.activityRegion({ game_rift = { hud = false }, game_raid = { window = true } }), nil, 'windows alone do not count')
eq(M.activityRegion({ game_arena = { hud = true }, game_rift = { hud = true } }), 'arena', 'the first listed wins')
eq(M.activityRegion(nil), nil, 'no states')
for _, a in ipairs(M.ACTIVITIES) do
  eq(M.REGIONS[1] ~= nil and M.TRACKS[a.region] ~= nil, true, a.module .. ' maps to a track')
end

-- 6. boss
eq(M.bossEngaged({ tier = 'boss', health = 80 }, {}, pos), true, 'attacking a boss')
eq(M.bossEngaged({ tier = 'boss', health = 0 }, {}, pos), false, 'a dead boss target')
eq(M.bossEngaged({ tier = 'elite', health = 50 }, {}, pos), false, 'an elite is not a boss')
eq(M.bossEngaged(nil, { { pos = { x = 104, y = 98, z = 7 }, health = 60 } }, pos), true, 'a hurt boss near')
eq(M.bossEngaged(nil, { { pos = { x = 104, y = 98, z = 7 }, health = 100 } }, pos), false, 'a boss at full health is not a fight')
eq(M.bossEngaged(nil, { { pos = { x = 120, y = 98, z = 7 }, health = 60 } }, pos), false, 'a hurt boss far away')
eq(M.bossEngaged(nil, { { pos = { x = 104, y = 98, z = 8 }, health = 60 } }, pos), false, 'a hurt boss on another floor')

-- 7. the wanted region
eq(M.wanted(nil), 'login', 'nothing: login')
eq(M.wanted({ online = false, pz = true }), 'login', 'offline: login')
eq(M.wanted({ online = true }), 'hunt', 'online, nowhere special: hunt')
eq(M.wanted({ online = true, pz = true }), 'town', 'protection zone: town')
eq(M.wanted({ online = true, pz = true, activity = 'arena' }), 'arena', 'an activity wins over the protection zone')
eq(M.wanted({ online = true, activity = 'dungeon', boss = true }), 'boss', 'a boss wins over everything')
eq(M.wanted({ online = true, pos = pos, pois = { { k = 'temple', x = 101, y = 101, z = 7 } } }), 'town', 'near a temple: town')

-- 8. hysteresis
local st = M.newState()
local r, changed = M.step(st, 'login', 0)
eq(r, 'login', 'first: login at once')
eq(changed, true, 'first: a change')
r, changed = M.step(st, 'login', 500)
eq(changed, false, 'same region: no change')
r, changed = M.step(st, 'town', 1000)
eq(r, 'town', 'login -> town at once')
-- a short step out of town keeps the town track
local t = 10000
r = M.step(st, 'hunt', t)
eq(r, 'town', 'out of town: not yet')
r = M.step(st, 'hunt', t + 5000)
eq(r, 'town', 'out of town 5 s: still town')
r = M.step(st, 'town', t + 6000)
eq(r, 'town', 'back in town')
eq(st.pending, nil, 'back in town clears the pending change')
r = M.step(st, 'hunt', t + 7000)
eq(r, 'town', 'out again: the timer starts again')
r = M.step(st, 'hunt', t + 14500)
eq(r, 'town', 'out 7.5 s: still town')
r, changed = M.step(st, 'hunt', t + 15000)
eq(r, 'hunt', 'out 8 s: hunt')
eq(changed, true, 'the change is reported once')
-- a boss starts at once (after the hold of the last cross-fade) and stays a while
r = M.step(st, 'boss', t + 16000)
eq(r, 'hunt', 'boss within the hold of the last switch: not yet')
r = M.step(st, 'boss', t + 18000)
eq(r, 'boss', 'boss after the hold: at once')
r = M.step(st, 'hunt', t + 20000)
eq(r, 'boss', 'the boss died: the boss track stays')
r = M.step(st, 'hunt', t + 29900)
eq(r, 'boss', 'still boss before 10 s')
r = M.step(st, 'hunt', t + 30000)
eq(r, 'hunt', 'after 10 s: hunt')
-- into a rift quickly, into town after 3 s
r = M.step(st, 'dungeon', t + 40000)
eq(r, 'hunt', 'into a rift: not at once')
r = M.step(st, 'dungeon', t + 41000)
eq(r, 'dungeon', 'into a rift after 1 s')
r = M.step(st, 'town', t + 50000)
r = M.step(st, 'town', t + 52900)
eq(r, 'dungeon', 'into town: not before 3 s')
r = M.step(st, 'town', t + 53000)
eq(r, 'town', 'into town after 3 s')
-- flapping between two places never switches
local flap = M.newState()
M.step(flap, 'town', 0)
M.step(flap, 'town', 100)
local switches = 0
for i = 1, 200 do
  local _, c = M.step(flap, (i % 2 == 0) and 'hunt' or 'town', 100 + i * 1000)
  if c then switches = switches + 1 end
end
eq(switches, 0, 'stepping in and out of town every second never switches')
-- logout: login at once
r = M.step(st, 'login', t + 53500)
eq(r, 'login', 'logout: login at once')

-- 9. silence
eq(M.silentReason({ enabled = true, gain = 0.3, audio = true, visible = true, focused = true }), nil, 'plays')
eq(M.silentReason({ enabled = false, gain = 0.3 }), 'off', 'off')
eq(M.silentReason({ enabled = true, gain = 0 }), 'volume', 'volume 0')
eq(M.silentReason({ enabled = true, gain = 0.3, audio = false }), 'audio', 'client audio off')
eq(M.silentReason({ enabled = true, gain = 0.3, visible = false }), 'hidden', 'minimized')
eq(M.silentReason({ enabled = true, gain = 0.3, focused = false }), nil, 'unfocused plays by default')
eq(M.silentReason({ enabled = true, gain = 0.3, focused = false, background = true }), 'unfocused', 'unfocused muted on request')
eq(M.silentReason({ enabled = true, gain = 0.3, file = false }), 'file', 'missing file')

print(string.format('musiclogic_test: %d checks, %d failures', checks, fails))
if fails > 0 then os.exit(1) end
