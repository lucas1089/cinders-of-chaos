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

-- remember: an open window (or the full map view that replaced it) is wanted back, a closed one is not
local w = L.remember({ visible = true, panelId = 'gameRightPanel', index = 1, height = 200 })
eq(w and w.panelId, 'gameRightPanel', 'remember: its panel')
eq(w and w.height, 200, 'remember: its height')
eq(L.remember({ visible = false, panelId = 'gameRightPanel' }), nil, 'a closed window is not wanted back')
eq(L.remember({ visible = false, fullmap = true }) ~= nil, true, 'the full map view counts as open')
eq(L.remember(nil), nil, 'no window')

-- the panel to put it back in
local panels = { { id = 'rightPanel2', usable = true }, { id = 'gameRightPanel', usable = true } }
eq(L.pickPanel(w, panels, 'gameRightPanel'), 'gameRightPanel', 'its own panel when it is there')
eq(L.pickPanel({ panelId = 'rightPanel3' }, panels, 'gameRightPanel'), 'gameRightPanel', 'a panel gone: the fallback')
eq(L.pickPanel({ panelId = 'rightPanel2' }, { { id = 'rightPanel2', usable = false } }, 'gameRightPanel'),
  'gameRightPanel', 'a hidden panel: the fallback')
eq(L.pickPanel(nil, panels, 'gameRightPanel'), 'gameRightPanel', 'nothing remembered: the fallback')

-- the beta report: after the death relog the window is closed (the layout restore stopped before it)
local p = L.plan({ reason = 'start', inWindow = true, windowShown = false, inPanel = true, want = w, pos = temple,
  camera = cave })
eq(p.restore, true, 'closed after the respawn: back in a panel and open')
eq(p.consumeWant, false, 'kept until it is seen open')
eq(p.recentre, true, 'camera to the temple')
-- or it is in no shown panel (a panel that is gone or hidden)
p = L.plan({ reason = 'start', inWindow = true, windowShown = true, inPanel = false, want = w, pos = temple,
  camera = temple })
eq(p.restore, true, 'open but in no shown panel: back in a panel')
-- seen open in a panel: the wish is used up, a later close by the player stays
p = L.plan({ reason = 'start', inWindow = true, windowShown = true, inPanel = true, want = w, pos = temple,
  camera = temple })
eq(p.restore, false, 'open in a panel: left alone')
eq(p.consumeWant, true, 'wish used up')
eq(p.recentre, false, 'already on the tile')
-- closed by the player before the death: nothing wanted, nothing reopened
p = L.plan({ reason = 'start', inWindow = true, windowShown = false, inPanel = true, want = nil, pos = temple,
  camera = temple })
eq(p.restore, false, 'closed by the player: stays closed')

-- no position yet (before the first map description)
p = L.plan({ reason = 'start', inWindow = true, windowShown = true, inPanel = true, pos = nil, camera = cave })
eq(p.recentre, false, 'no position, no recentre')

-- a full map view left over from the last session: closed, then the minimap follows again
p = L.plan({ reason = 'start', fullmap = true, inWindow = false, windowShown = false, inPanel = true, want = w,
  pos = temple, camera = cave })
eq(p.exitFullMap, true, 'start: leftover full map closed')
eq(p.reparent, true, 'start: widget back in its window')
eq(p.recentre, true, 'start: camera to the character')

-- a teleport while the player looks at the full map: the full map stays
p = L.plan({ reason = 'teleport', fullmap = true, inWindow = false, windowShown = false, want = w, pos = temple,
  camera = cave })
eq(p.exitFullMap, false, 'teleport: full map kept')
eq(p.reparent or p.restore or p.recentre, false, 'teleport: nothing else while the full map is open')

-- the end of a session: only the full map view is closed
p = L.plan({ reason = 'end', fullmap = true, inWindow = false, windowShown = false, want = w, pos = cave, camera = cave })
eq(p.exitFullMap, true, 'end: full map closed')
eq(p.reparent or p.restore or p.recentre, false, 'end: nothing else')

-- passes cover the layout restore (addEvent), the expansion restore (250 ms) and game_chaoslayout (800 ms)
eq(L.PASSES[1], 0, 'first pass at once')
eq(L.PASSES[#L.PASSES] > 800, true, 'a pass after game_chaoslayout')

-- the module is wired to these engine events, reopens through game_minimap.move and leaves the explored map alone
local src = io.open(dir .. 'minimapsync.lua'):read('*a')
for _, ev in ipairs({ 'onMapKnown', 'onTeleport', 'onDeath', 'onGameEnd', 'onGameStart' }) do
  eq(src:find(ev .. ' = safe', 1, true) ~= nil, true, 'connected: ' .. ev)
end
eq(src:find("call(m, 'move'", 1, true) ~= nil, true, 'reopens through game_minimap.move')
eq(src:find("call(m, 'open'", 1, true), nil, 'no second reopen path')
eq(src:find('g_minimap.clean', 1, true), nil, 'never cleans the explored map')
eq(src:find('loadOtmm', 1, true), nil, 'never reloads the explored map')

-- base patch 0096: each saved window is restored on its own (an error no longer leaves the rest closed)
local pf = io.open(dir .. '../../../base-patches/0096-layout-restore-each-window.patch')
eq(pf ~= nil, true, 'patch 0096 present')
if pf then
  local patch = pf:read('*a')
  pf:close()
  local n = 0
  for _ in patch:gmatch('%+%s*restoreEach%(config%.') do n = n + 1 end
  eq(n, 4, 'patch 0096: the four restore loops (right, left, horizontal right, horizontal left)')
  eq(patch:find('pcall(fn, k, x)', 1, true) ~= nil, true, 'patch 0096: each window in a pcall')
end

if fails > 0 then
  print(fails .. ' failure(s)')
  os.exit(1)
end
print('minimapsync_logic_test: OK')
