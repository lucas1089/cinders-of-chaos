-- luajit minimapsync_logic_test.lua && lua5.3 minimapsync_logic_test.lua (from the repository root or this folder)
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'minimapsync_logic.lua')
local L = MinimapSyncLogic
local fails = 0
local function eq(a, b, what)
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

local temple = { x = 1000, y = 1000, z = 7 }
local cave = { x = 1200, y = 950, z = 9 }

eq(L.validPos(temple), true, 'a map tile')
eq(L.validPos(nil), false, 'no position')
eq(L.validPos({ x = 65535, y = 65535, z = 255 }), false, 'the invalid position')
eq(L.validPos({ x = 10, y = 10, z = 16 }), false, 'below the last floor')
eq(L.samePos(temple, { x = 1000, y = 1000, z = 7 }), true, 'same tile')
eq(L.samePos(temple, { x = 1000, y = 1000, z = 8 }), false, 'other floor')
eq(L.samePos(nil, temple), false, 'no camera yet')

-- respawn after a death: the camera still on the cave where the character died
local p = L.plan({ reason = 'start', fullmap = false, inWindow = true, windowOpen = true, pos = temple, camera = cave })
eq(p.recentre, true, 'respawn: camera to the temple')
eq(p.exitFullMap, false, 'respawn: no full map to close')
eq(p.reparent, false, 'respawn: widget in its window')
eq(p.open, false, 'respawn: window already open')

-- already on the tile: nothing to do
p = L.plan({ reason = 'start', inWindow = true, windowOpen = true, pos = temple, camera = temple })
eq(p.recentre, false, 'no camera move when it is on the tile')

-- the position is not known yet (before the first map description)
p = L.plan({ reason = 'start', inWindow = true, windowOpen = true, pos = nil, camera = cave })
eq(p.recentre, false, 'no position, no recentre')

-- a full map view left over from the last session: closed, then the minimap follows again
p = L.plan({ reason = 'start', fullmap = true, inWindow = false, windowOpen = false, wantOpen = true, pos = temple,
  camera = cave })
eq(p.exitFullMap, true, 'start: leftover full map closed')
eq(p.reparent, true, 'start: widget back in its window')
eq(p.open, true, 'start: the window open at the end is open again')
eq(p.consumeWant, true, 'start: reopened once')
eq(p.recentre, true, 'start: camera to the character')

-- a teleport while the player looks at the full map: the full map stays
p = L.plan({ reason = 'teleport', fullmap = true, inWindow = false, windowOpen = false, pos = temple, camera = cave })
eq(p.exitFullMap, false, 'teleport: full map kept')
eq(p.reparent or p.open or p.recentre, false, 'teleport: nothing else while the full map is open')

-- the end of a session: only the full map view is closed
p = L.plan({ reason = 'end', fullmap = true, inWindow = false, windowOpen = false, pos = cave, camera = cave })
eq(p.exitFullMap, true, 'end: full map closed')
eq(p.reparent or p.open or p.recentre, false, 'end: nothing else')
p = L.plan({ reason = 'end', fullmap = false, inWindow = true, windowOpen = true, pos = cave, camera = temple })
eq(p.recentre, false, 'end: no camera move')

-- a window the player closed stays closed
p = L.plan({ reason = 'start', inWindow = true, windowOpen = false, wantOpen = nil, pos = temple, camera = temple })
eq(p.open, false, 'closed by the player: not reopened')
-- a window seen open consumes the wish (a later close by the player is kept)
p = L.plan({ reason = 'start', inWindow = true, windowOpen = true, wantOpen = true, pos = temple, camera = temple })
eq(p.consumeWant, true, 'open now: wish consumed')
eq(p.open, false, 'open now: no open call')

eq(L.openAtEnd(true, false), true, 'shown at the end')
eq(L.openAtEnd(false, true), true, 'full map at the end counts as open')
eq(L.openAtEnd(false, false), false, 'closed at the end')

-- the passes cover the minimap's expansion restore (250 ms) and the layout restore (800 ms)
local last = L.PASSES[#L.PASSES]
eq(L.PASSES[1], 0, 'first pass at once')
eq(last > 800, true, 'a pass after game_chaoslayout')

-- the module is wired to these engine events and leaves the explored map alone
local src = io.open(dir .. 'minimapsync.lua'):read('*a')
for _, ev in ipairs({ 'onMapKnown', 'onTeleport', 'onDeath', 'onGameEnd', 'onGameStart' }) do
  eq(src:find(ev .. ' = safe', 1, true) ~= nil, true, 'connected: ' .. ev)
end
eq(src:find('g_minimap.clean', 1, true), nil, 'never cleans the explored map')
eq(src:find('loadOtmm', 1, true), nil, 'never reloads the explored map')

if fails > 0 then
  print(fails .. ' failure(s)')
  os.exit(1)
end
print('minimapsync_logic_test: OK')
