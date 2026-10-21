-- luajit levelwingsmath_test.lua && lua5.3 levelwingsmath_test.lua (from anywhere; CI runs it from the repo root)
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'levelwingsmath.lua')
local M = LevelWingsMath
local fails = 0
local function eq(a, b, what)
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end
local function near(a, b, what)
  if math.abs(a - b) > 1e-6 then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

-- the timeline: 12 frames, one per 55 ms, then the last one held and faded
eq(M.FRAMES * M.FRAME_MS, 660, 'opening length')
local f, o, done = M.at(0)
eq(f, 1, 'first frame'); near(o, 0.25, 'starts faint'); eq(done, false, 'not done')
f = M.at(54); eq(f, 1, 'still frame 1 at 54 ms')
f = M.at(55); eq(f, 2, 'frame 2 at 55 ms')
f, o = M.at(60); near(o, 0.25 + 0.75 * 60 / 120, 'fading in')
f, o = M.at(120); eq(f, 3, 'frame 3 at 120 ms'); near(o, 1, 'full after the fade-in')
f = M.at(659); eq(f, 12, 'last frame at 659 ms')
f = M.at(660); eq(f, 12, 'held after the opening')
f, o = M.at(1150); eq(f, 12, 'held'); near(o, 1, 'full until the hold ends')
f, o = M.at(1475); near(o, 0.5, 'half way through the fade')
f, o, done = M.at(1799); eq(done, false, 'not over at 1799'); eq(o > 0 and o < 0.01, true, 'almost gone')
f, o, done = M.at(1800); eq(done, true, 'over at 1800'); eq(o, 0, 'invisible when over')
f, o, done = M.at(99999); eq(done, true, 'long over')
f, o, done = M.at(-50); eq(f, 1, 'clock went back: first frame'); eq(done, false, 'not over')
f = M.at(nil); eq(f, 1, 'nil elapsed')
-- frames only go forward and opacity never rises after the hold
local lastF, lastO = 0, 1
for t = 0, 1799, 7 do
  local fr, op = M.at(t)
  eq(fr >= lastF, true, 'frames go forward at ' .. t)
  if t > M.HOLD_UNTIL_MS then eq(op <= lastO, true, 'fading at ' .. t) end
  lastF, lastO = fr, op
end
-- total length within the asked 1.5 - 2 s
eq(M.TOTAL_MS >= 1500 and M.TOTAL_MS <= 2000, true, 'about 1.5 - 2 s')

eq(M.framePath(1), '/modules/game_levelwings/images/wings_01', 'path 1')
eq(M.framePath(12), '/modules/game_levelwings/images/wings_12', 'path 12')
eq(M.framePath(40), '/modules/game_levelwings/images/wings_12', 'path clamped')
-- a frame set per view: the front pair facing south or north, the side pair facing east or west
eq(M.framePath(1, 'south'), '/modules/game_levelwings/images/wings_01', 'south: front pair')
eq(M.framePath(7, 'north'), '/modules/game_levelwings/images/wings_07', 'north: front pair')
eq(M.framePath(3, 'east'), '/modules/game_levelwings/images/wings_east_03', 'east: side pair')
eq(M.framePath(12, 'west'), '/modules/game_levelwings/images/wings_west_12', 'west: mirrored side pair')
eq(M.framePath(0, 'east'), '/modules/game_levelwings/images/wings_east_01', 'side path clamped low')
eq(M.framePath(99, 'west'), '/modules/game_levelwings/images/wings_west_12', 'side path clamped high')
eq(M.framePath(5, 'up'), '/modules/game_levelwings/images/wings_05', 'unknown view: front pair')

-- view of a direction (0 N, 1 E, 2 S, 3 W, 4 NE, 5 SE, 6 SW, 7 NW)
eq(M.viewFor(0), 'north', 'view north'); eq(M.viewFor(1), 'east', 'view east')
eq(M.viewFor(2), 'south', 'view south'); eq(M.viewFor(3), 'west', 'view west')
eq(M.viewFor(4), 'north', 'north-east: the back'); eq(M.viewFor(7), 'north', 'north-west: the back')
eq(M.viewFor(5), 'south', 'south-east: the front'); eq(M.viewFor(6), 'south', 'south-west: the front')
eq(M.viewFor(nil), 'south', 'unknown: south'); eq(M.viewFor(8), 'south', 'out of range: south')
eq(M.viewFor('1'), 'south', 'not a number: south')

-- layer: in front only with the back to the viewer; the side pair is behind
eq(M.layerFor(0), 'top', 'north'); eq(M.layerFor(4), 'top', 'north-east'); eq(M.layerFor(7), 'top', 'north-west')
eq(M.layerFor(1), 'bottom', 'east'); eq(M.layerFor(2), 'bottom', 'south'); eq(M.layerFor(3), 'bottom', 'west')
eq(M.layerFor(5), 'bottom', 'south-east'); eq(M.layerFor(nil), 'bottom', 'unknown')

-- a turn during the animation: the frame index comes from the elapsed time only, the set from the direction, so a
-- turn changes the set and keeps the frame (no restart)
do
  local t = 4 * M.FRAME_MS + 10
  local fr = M.at(t)
  local before = M.framePath(fr, M.viewFor(2))
  local after = M.framePath(M.at(t), M.viewFor(1))
  eq(before, '/modules/game_levelwings/images/wings_05', 'south at 230 ms: front frame 5')
  eq(after, '/modules/game_levelwings/images/wings_east_05', 'turned east at 230 ms: side frame 5')
end

-- size
local w, h = M.sizeFor(32, 1); eq(w, 96, '1x w'); eq(h, 80, '1x h')
w, h = M.sizeFor(64, 1); eq(w, 192, 'HD w'); eq(h, 160, 'HD h')
w, h = M.sizeFor(32, 1.5); eq(w, 144, 'draw scale w'); eq(h, 120, 'draw scale h')
w, h = M.sizeFor(nil, 0); eq(w, 96, 'defaults w'); eq(h, 80, 'defaults h')

-- settings
eq(M.wanted(true, true, false), true, 'own on, others off: own plays')
eq(M.wanted(false, true, false), false, 'others off')
eq(M.wanted(true, false, true), false, 'own off')
eq(M.wanted(false, false, true), true, 'others on')
eq(M.wanted(true, nil, nil), true, 'no settings: on')
eq(M.wanted(false, nil, nil), true, 'no settings: on for others')

-- messages
eq(M.playId({ action = 'play', data = { id = 268435457, lv = 44, n = 3 } }), 268435457, 'play id')
eq(M.playId({ action = 'play', data = { id = '12' } }), 12, 'id as text')
eq(M.playId({ action = 'other', data = { id = 5 } }), nil, 'other action')
eq(M.playId({ action = 'play' }), nil, 'no data')
eq(M.playId({ action = 'play', data = { id = 0 } }), nil, 'id 0')
eq(M.playId({ action = 'play', data = { id = 1.5 } }), nil, 'fraction')
eq(M.playId('play'), nil, 'not a table')

-- eviction
local active = {}
eq(M.evict(active, 0), nil, 'empty: room')
for i = 1, M.MAX_ACTIVE - 1 do active[100 + i] = { start = 1000 + i } end
eq(M.evict(active, 0), nil, 'one place left')
active[999] = { start = 500 }
eq(M.evict(active, 0), 999, 'full: the oldest gives way')

-- place: the wing roots on the shoulders (anchors of client_chaos_charselect/outfit_anchors.lua, pair 28)
local wx, wy = M.widgetCentre(8, 8); eq(wx, 8, 'widget centre x, displacement 8'); eq(wy, 8, 'widget centre y')
wx, wy = M.widgetCentre(-32, 0); eq(wx, 16, 'negative displacement: tile centre x'); eq(wy, 16, 'tile centre y')
wx, wy = M.widgetCentre(nil, nil); eq(wx, 16, 'no displacement x'); eq(wy, 16, 'no displacement y')
local ox, oy = M.offsetFor({15, 17, -23, -12, 22}, 8, 8, 1)   -- look 130 (2x2, displacement 8)
eq(ox, -3, '2x2: the box middle, 3 px left'); eq(oy, -13, '2x2: 13 px up')
ox, oy = M.offsetFor({16, 18, -25, -3, 33}, -32, 0, 1)        -- look 1559, the Archmage (3x3, displacement -32, 0)
eq(ox, -1, 'Archmage: centred'); eq(oy, -22, 'Archmage: 22 px up')
ox, oy = M.offsetFor({16, 18, -25, -3, 33}, -32, 0, 2)
eq(ox, -2, 'HD x'); eq(oy, -44, 'HD: twice the pixels')
ox, oy = M.offsetFor(nil, 8, 8, 1)
eq(ox, -2, 'unknown look: the default body x'); eq(oy, -13, 'unknown look: the default body y')
ox, oy = M.offsetFor({16, 21, -8}, 0, 0, 0)           -- a 1x1 look without box: its centre x
eq(ox, 0, '1x1 x'); eq(oy, -9, '1x1: roots on its shoulders')

-- place facing east or west: the same height, moved onto the back (left facing east, right facing west)
local a130 = {15, 17, -23, -12, 22}
local sx, sy = M.offsetFor(a130, 8, 8, 1, 'south')
eq(sx, -3, 'south view: as before'); eq(sy, -13, 'south view y')
local nx, ny = M.offsetFor(a130, 8, 8, 1, 'north')
eq(nx, sx, 'north: the front place x'); eq(ny, sy, 'north: the front place y')
local ex, ey = M.offsetFor(a130, 8, 8, 1, 'east')
eq(ex, sx + M.SIDE_X.east, 'east: moved by SIDE_X.east'); eq(ey, sy, 'east: same height')
local wx2, wy2 = M.offsetFor(a130, 8, 8, 1, 'west')
eq(wx2, sx + M.SIDE_X.west, 'west: moved by SIDE_X.west'); eq(wy2, sy, 'west: same height')
eq(ex < sx, true, 'east: the back is left of the front place')
eq(wx2 > ex, true, 'west: right of the east place (the back on the other side)')
eq(ex, -9, 'east: 2x2 look 130, 9 px left'); eq(wx2, -1, 'west: 2x2 look 130, 1 px left')
-- scaled with the sprite size and draw scale like the front place
ex, ey = M.offsetFor({16, 18, -25, -3, 33}, -32, 0, 2, 'east')
eq(ex, -14, 'HD east x: twice (-1 - 6)'); eq(ey, -44, 'HD east y')
ex, ey = M.offsetFor(nil, 8, 8, 1, 'west')
eq(ex, -2 + M.SIDE_X.west, 'unknown look, west: the default body moved'); eq(ey, -13, 'unknown look, west y')
-- an unknown view counts as the front
ex, ey = M.offsetFor(a130, 8, 8, 1, 'sideways')
eq(ex, sx, 'unknown view x'); eq(ey, sy, 'unknown view y')
-- the sides mirror each other around the body: west sits right of the front place, east left
eq(M.SIDE_X.east < 0 and M.SIDE_X.west > 0, true, 'east left, west right of the front place')
-- every view has a frame set
for _, v in ipairs({ 'south', 'north', 'east', 'west' }) do
  eq(type(M.SETS[v]), 'string', 'set of ' .. v)
end

if fails > 0 then os.exit(1) end
print('level-up wings tests OK')
