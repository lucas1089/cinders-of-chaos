-- luajit layout_test.lua && lua5.3 layout_test.lua (from the repository root or this folder)
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'layout_logic.lua')
local L = ChaosLayoutLogic
local fails = 0
local function eq(a, b, what)
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

eq(L.key('Ashfall', 'Alice'), 'Ashfall/Alice', 'key: world and name')
eq(L.key(nil, 'Alice'), '-/Alice', 'key without a world')
eq(L.key('Ashfall', ''), nil, 'no character, no key')
eq(L.remembered('skillWindow'), true, 'a miniwindow is remembered')
eq(L.remembered('container3'), false, 'container windows are slots, not remembered')

-- snapshot of two right panels and a left one
local containers = {
  { id = 'panel1', side = 'right', persistent = true, windows = {
    { id = 'skillWindow', height = 200, minimized = false, visible = true },
    { id = 'container0', height = 150, visible = true },
    { id = 'battleWindow', height = 300, minimized = true, visible = true, locked = true } } },
  { id = 'rightPanel2', side = 'right', persistent = true, windows = { { id = 'vipWindow', height = 120, visible = false } } },
  { id = 'leftPanel1', side = 'left', persistent = true, windows = { { id = 'partyFramesWindow', height = 180, visible = true } } },
}
local snap = L.snapshot(containers)
eq(snap.mini.skillWindow.index, 1, 'order in its panel')
eq(snap.mini.battleWindow.index, 2, 'containers do not count in the order')
eq(snap.mini.battleWindow.minimized, true, 'collapsed state')
eq(snap.mini.battleWindow.locked, true, 'locked state')
eq(snap.mini.vipWindow.closed, true, 'a closed window')
eq(snap.mini.vipWindow.panel .. '/' .. snap.mini.vipWindow.side, 'rightPanel2/right', 'its panel and side')
eq(snap.mini.container0, nil, 'no container window')
eq(snap.panels.right .. '/' .. snap.panels.left, '2/1', 'side panel counts')

-- merge keeps windows that do not exist now
local saved = { mini = { cosmeticsPanel = { panel = 'leftPanel1', side = 'left', index = 2 } },
  windows = { spellbookWindow = { x = 10, y = 20, width = 640, height = 460 } } }
local merged = L.merge(saved, snap)
eq(merged.mini.cosmeticsPanel ~= nil, true, 'a window not open now keeps its entry')
eq(merged.mini.skillWindow.height, 200, 'the snapshot replaces')
eq(merged.windows.spellbookWindow.x, 10, 'big windows kept')

-- placement: fewer panels at the next login -> the first panel of the side
local place = L.placement(merged, { panel1 = 'right', leftPanel1 = 'left' }, { right = 'panel1', left = 'leftPanel1' })
local ids = {}
for _, e in ipairs(place.panel1) do ids[#ids + 1] = e.id .. ':' .. e.index end
eq(table.concat(ids, ','), 'skillWindow:1,vipWindow:1,battleWindow:2', 'a missing panel falls back to the side\'s first, sorted')
eq(#place.leftPanel1, 2, 'left panel windows')
eq(place.leftPanel1[1].id, 'partyFramesWindow', 'left order')

-- clamp to the window
local area = { x = 0, y = 0, width = 1280, height = 720 }
local r = L.clampRect({ x = 1500, y = -40, width = 640, height = 460 }, area, { width = 300, height = 200 })
eq(r.x .. ',' .. r.y, '640,0', 'moved back inside')
r = L.clampRect({ x = 10, y = 10, width = 3000, height = 2000 }, area, { width = 300, height = 200 })
eq(r.width .. 'x' .. r.height, '1280x720', 'never larger than the window')
r = L.clampRect({ x = 10, y = 10, width = 50, height = 50 }, area, { width = 300, height = 200 })
eq(r.width .. 'x' .. r.height, '300x200', 'never under its minimum')
r = L.clampRect({ x = 0, y = 0, width = 640, height = 460 }, { x = 0, y = 0, width = 500, height = 300 }, { width = 600, height = 400 })
eq(r.width .. 'x' .. r.height, '500x300', 'a tiny window: the window wins over the minimum')

-- the session: nothing saved before the restore, never into another character, only on a change
local st = L.newSession()
L.begin(st)
eq(L.canSave(st, 'w/Alice'), false, 'no save before the restore')
L.restored(st, 'w/Alice', merged)
eq(L.canSave(st, 'w/Alice'), true, 'saves after the restore')
eq(L.canSave(st, 'w/Bob'), false, 'not into another character')
eq(L.changed(st, merged), false, 'the restored layout is not a change')
local moved = L.merge(merged, { mini = { skillWindow = { panel = 'panel1', side = 'right', index = 3, height = 220 } } })
eq(L.changed(st, moved), true, 'a moved window is a change')
eq(L.changed(st, moved), false, 'written once')

-- death -> relogin: the logout ends the session; the next login restores the saved layout before any save
local store = {}
local function login(key, panelsNow)
  L.begin(st)
  local s = store[key]
  -- the panels exist now: the default layout of a fresh login is never written before this restore
  L.restored(st, key, s)
  return L.placement(s, panelsNow, { right = 'panel1', left = 'leftPanel1' })
end
store['w/Alice'] = moved
L.begin(st) -- logout (death -> Ok -> safe logout)
eq(L.canSave(st, 'w/Alice'), false, 'blocked between logout and the restore')
local p = login('w/Alice', { panel1 = 'right', rightPanel2 = 'right', leftPanel1 = 'left' })
eq(p.panel1[#p.panel1].id, 'skillWindow', 'after relogin the moved window is back in its place')
eq(p.rightPanel2[1].id, 'vipWindow', 'and the second panel too')

if fails > 0 then error(fails .. ' failure(s)') end
print('layout_test: OK')
