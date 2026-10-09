-- luajit mapmath_test.lua && lua5.3 mapmath_test.lua
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'mapmath.lua')
local M = MapOverlayMath
local fails = 0
local function eq(a, b, what)
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

-- zoom / opacity
eq(M.clampZoom(9), M.MAX_ZOOM, 'zoom capped')
eq(M.clampZoom(-3), M.MIN_ZOOM, 'zoom floor')
eq(M.clampZoom(nil), M.DEFAULTS.zoom, 'zoom default')
eq(M.zoomLabel(3), 'x8', 'zoom label')
eq(M.stepOpacity(0.6, 0.1), 0.7, 'opacity up')
eq(M.stepOpacity(0.2, -0.1), 0.2, 'opacity floor')
eq(M.stepOpacity(1.0, 0.1), 1.0, 'opacity cap')
eq(M.stepOpacity(0.30000001, 0), 0.3, 'opacity rounded')
eq(M.percent(0.7), '70%', 'percent')

-- settings
local s = M.sanitize(nil)
eq(s.opacity, M.DEFAULTS.opacity, 'default opacity')
eq(s.mode, 'center', 'default mode')
eq(s.town, true, 'default town marks')
s = M.sanitize({ opacity = 5, zoom = '1', mode = 'corner', party = false, town = 'true', events = 'x' })
eq(s.opacity, 1.0, 'opacity clamped')
eq(s.zoom, 1, 'zoom from string')
eq(s.mode, 'corner', 'corner mode')
eq(s.party, false, 'party off')
eq(s.town, true, 'town from string')
eq(s.events, false, 'junk is off')
eq(M.sanitize({ mode = 'weird' }).mode, 'center', 'unknown mode')

-- marks
local marks = {
  { k = 'party', x = 1, y = 1, z = 7 }, { k = 'npc', x = 2, y = 2, z = 7 }, { k = 'guardian', x = 3, y = 3, z = 7 },
  { k = 'npc', x = 2, y = 2, z = 6 }, { k = 'bogus', x = 1, y = 1, z = 7 }, { k = 'depot', x = 'a', y = 1, z = 7 }, 'junk',
}
eq(#M.visibleMarks(marks, 7, M.sanitize({})), 3, 'floor 7, all categories')
eq(#M.visibleMarks(marks, 7, M.sanitize({ town = false })), 2, 'town off')
eq(#M.visibleMarks(marks, 6, M.sanitize({})), 1, 'other floor')
eq(#M.visibleMarks(nil, 7, M.sanitize({})), 0, 'no marks')
for kind, cat in pairs(M.CATEGORY) do
  assert(cat == 'party' or cat == 'town' or cat == 'events', 'category of ' .. kind)
end

-- default key
local function entry(action, key, secondary)
  return { actionsetting = { action = action }, keysequence = key, secondary = secondary }
end
local list = { entry('NextChannel', 'Tab'), entry('PreviousChannel', 'Shift+Tab') }
eq(M.assignDefaultKey(list), true, 'assigned')
eq(list[1].keysequence, 'Ctrl+Tab', 'next channel moved')
eq(list[3].actionsetting.action, M.ACTION, 'overlay entry')
eq(list[3].keysequence, 'Tab', 'overlay on Tab')
eq(M.assignDefaultKey(list), false, 'only once')
list = { entry('AttackNextTarget', 'Tab') }
eq(M.assignDefaultKey(list), false, 'Tab used by something else')
eq(#list, 1, 'list unchanged')
list = { entry('NextChannel', 'Tab'), entry('Something', 'Ctrl+Tab') }
eq(M.assignDefaultKey(list), false, 'Ctrl+Tab taken')
eq(list[1].keysequence, 'Tab', 'next channel kept')
list = {}
eq(M.assignDefaultKey(list), true, 'free Tab')
eq(list[1].keysequence, 'Tab', 'overlay on the free Tab')
eq(M.assignDefaultKey(nil), false, 'no list')
list = { entry(M.ACTION, '') }
eq(M.assignDefaultKey(list), false, 'cleared by the player stays cleared')

-- rift area
local tokens = {}
local area = { id = '1-2', x1 = 8192, y1 = 8192, x2 = 8255, y2 = 8255, z = 7 }
eq(M.shouldClearRift(tokens, area), true, 'new run')
tokens['1-2'] = true
eq(M.shouldClearRift(tokens, area), false, 'seen run')
eq(M.shouldClearRift(tokens, { id = 'x', x1 = 0, y1 = 0, x2 = 5000, y2 = 1, z = 7 }), false, 'too large')
eq(M.shouldClearRift(tokens, { x1 = 1, y1 = 1, x2 = 2, y2 = 2, z = 7 }), false, 'no id')

-- corner box
local w, h = M.cornerRect(1000, 700)
eq(w, 320, 'corner width')
eq(h, 252, 'corner height')
w, h = M.cornerRect(100, 100)
eq(w, 180, 'corner min width')

-- view geometry: a map drawn at 297..985 x 10..595 inside a bigger panel, 98 px tiles, grid origin off screen
local function probe(x, y)
  if x < 297 or x > 985 or y < 10 or y > 595 then return nil end
  return { x = 1000 + math.floor((x - 250) / 98), y = 2000 + math.floor((y - (-30)) / 98) }
end
local g = M.viewGeometry({ x = 0, y = -88, width = 1280, height = 888 }, probe, { x = 1004, y = 2003 })
eq(g.x, 297, 'map left'); eq(g.width, 689, 'map width'); eq(g.y, 10, 'map top'); eq(g.height, 586, 'map height')
eq(g.ts, 98, 'tile size')
eq(g.cx, 250 + 4 * 98 + 49, 'player centre x')
eq(g.cy, -30 + 3 * 98 + 49, 'player centre y')
eq(M.viewGeometry({ x = 0, y = 0, width = 100, height = 100 }, function() return nil end, { x = 1, y = 1 }), nil, 'no map')

if fails > 0 then error(fails .. ' failure(s)') end
print('mapmath_test: ok')
