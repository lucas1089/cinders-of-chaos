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

local function close(a, b, what, tol)
  if math.abs(a - b) > (tol or 1e-9) then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

-- following the character's walk: a 15 x 11 view of 64 px tiles at 100, 50; the camera (sprite) tile is the
-- middle one; the destination tile slides in from a step away
local VW, VH, TS, OX, OY = 15, 11, 64, 100, 50
local function walkProbe(dx, dy)   -- dx, dy = sprite offset from its tile in pixels (stock walk offset)
  return function(x, y)
    if x < OX or y < OY or x >= OX + VW * TS or y >= OY + VH * TS then return nil end
    -- the map scrolls with the sprite: the tile under a point shifts by the walk offset
    return { x = 500 - 7 + math.floor((x - OX + dx) / TS), y = 600 - 5 + math.floor((y - OY + dy) / TS) }
  end
end
local panel = { x = 0, y = 0, width = 1200, height = 900 }
local sprite = { x = OX + math.floor(VW * TS / 2), y = OY + math.floor(VH * TS / 2) }
-- 8 directions, at the start (a whole tile), a quarter and the middle of a step, plus standing still
for _, d in ipairs({ { 0, -1 }, { 0, 1 }, { -1, 0 }, { 1, 0 }, { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 }, { 0, 0 } }) do
  for _, frac in ipairs({ 1, 0.75, 0.5, 0.25, 0 }) do
    -- walking in direction d: the character's tile is already the new one, the sprite still frac of a tile back
    local ox, oy = -d[1] * frac * TS, -d[2] * frac * TS
    local player = { x = 500 + d[1], y = 600 + d[2] }
    -- the stock view puts the new tile at sprite - offset: the probe sees it shifted the other way
    local gg = M.viewGeometry(panel, walkProbe(d[1] * TS + ox, d[2] * TS + oy), player)
    local what = string.format(' (%d,%d) %.2f', d[1], d[2], frac)
    eq(gg ~= nil, true, 'walk geometry' .. what)
    local sx, sy, wx, wy = M.follow(gg)
    -- the cheap per-frame lookup finds the same tile centre with a handful of probes
    local calls = 0
    local wp = walkProbe(d[1] * TS + ox, d[2] * TS + oy)
    local qx, qy = M.tileCentreNear(function(x, y) calls = calls + 1 return wp(x, y) end, sx, sy, gg.ts, player)
    eq(qx, gg.cx, 'cheap centre x' .. what); eq(qy, gg.cy, 'cheap centre y' .. what)
    eq(calls <= 20, true, 'cheap lookup probes' .. what .. ' ' .. calls)
    eq(sx, sprite.x, 'sprite stays centred x' .. what)
    eq(sy, sprite.y, 'sprite stays centred y' .. what)
    close(wx, -d[1] * frac, 'walk offset x' .. what)
    close(wy, -d[2] * frac, 'walk offset y' .. what)
    -- the shown fractional position = tile + offset = where the sprite really is
    close(player.x + wx, 500 + d[1] * (1 - frac), 'shown position x' .. what)
    close(player.y + wy, 600 + d[2] * (1 - frac), 'shown position y' .. what)
  end
end
-- not following (free camera): the tile is used
local fx, fy, fwx, fwy = M.follow({ x = 0, y = 0, width = 640, height = 640, ts = 64, cx = 100, cy = 100 })
eq(fx, 100, 'free camera x'); eq(fy, 100, 'free camera y'); eq(fwx, 0, 'free camera wx'); eq(fwy, 0, 'free camera wy')
fx, fy, fwx, fwy = M.follow({ x = 0, y = 0, width = 641, height = 641, ts = 64, cx = 321, cy = 319 })
eq(fx, 320, 'standing: sprite x'); eq(fwx, 0, 'standing: rounding is no step x'); eq(fwy, 0, 'standing: rounding is no step y')
-- a scaled view (45.5 px tiles): the cheap lookup stays within a pixel of the full measure
do
  local T = 45.5
  local function sp(x, y)
    if x < 10 or y < 10 or x >= 10 + 15 * T or y >= 10 + 11 * T then return nil end
    return { x = 300 + math.floor((x - 10 + 20) / T), y = 400 + math.floor((y - 10 + 7) / T) }
  end
  local pl = { x = 307, y = 405 }
  local gg = M.viewGeometry({ x = 0, y = 0, width = 800, height = 600 }, sp, pl)
  local sx, sy = M.follow(gg)
  local qx, qy = M.tileCentreNear(sp, sx, sy, gg.ts, pl)
  close(qx, gg.cx, 'scaled cheap centre x', 1); close(qy, gg.cy, 'scaled cheap centre y', 1)
  eq(M.tileCentreNear(function() return nil end, sx, sy, gg.ts, pl), nil, 'cheap lookup off the map')
  -- tiles grew (game view zoomed in) since the measure: no answer, measure again
  eq(M.tileCentreNear(sp, sx, sy, 10, pl), nil, 'cheap lookup with a stale tile size')
end
-- walk offset to minimap pixels
local px, py = M.walkPixels(-0.5, 0.25, 3)
eq(px, -4, 'walk pixels x'); eq(py, 2, 'walk pixels y')
px, py = M.walkPixels(-1, 1, 4)
eq(px, -16, 'walk pixels full tile x'); eq(py, 16, 'walk pixels full tile y')
-- the camera tile plus the minimap shift: the drawn point of the sprite's position is the anchor, at every zoom
for z = 0, 4 do
  for _, w in ipairs({ -1, -0.75, -0.5, -0.3, 0, 0.3, 0.5, 1 }) do
    local cox, _, rx = M.splitPan(w, 0, z)
    local ppt = M.pixelsPerTile(z)
    -- the camera tile (pos + cox) sits at anchor + rx; the sprite (pos + w) at anchor + rx + (w - cox) * ppt
    close(rx + (w - cox) * ppt, 0, string.format('sprite on the anchor z%d w%.2f', z, w), 0.5)
  end
end

-- pan, zoom toward the cursor
local function near(a, b, what)
  if math.abs(a - b) > 1e-9 then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end
eq(M.pixelsPerTile(3), 8, 'pixels per tile')
eq(M.isPanned(0, 0), false, 'centred is not panned')
eq(M.isPanned(0, 0.01), false, 'tiny pan is not panned')
eq(M.isPanned(2, 0), true, 'panned')
local px, py = M.clampPan(9999, -9999)
eq(px, M.PAN_LIMIT, 'pan clamped x'); eq(py, -M.PAN_LIMIT, 'pan clamped y')
px, py = M.clampPan('x', nil)
eq(px, 0, 'junk pan x'); eq(py, 0, 'junk pan y')
-- dragging right by 40 px at 4 px/tile moves the view 10 tiles left (the map follows the mouse)
px, py = M.dragPan(0, 0, 40, -20, 2)
near(px, -10, 'drag x'); near(py, 5, 'drag y')
px, py = M.dragPan(3, 3, 0, 0, 2)
near(px, 3, 'drag zero keeps pan')
px, py = M.dragPan(0, 0, 100000, 0, 0)
eq(px, -M.PAN_LIMIT, 'drag clamped')
px, py = M.keyPan(0, 0, 1, 0, 2, 48)
near(px, 12, 'key pan right 48px at x4'); near(py, 0, 'key pan y')
px, py = M.keyPan(0, 0, 0, -1, 4, 8)
near(py, -1, 'key pan at least one tile')
-- zoom toward the cursor keeps the point under it: world = pan + offset / ppt
local ox, oy = 100, -60
local ax, ay = 3.5, -2
local bx, by = M.zoomToward(ax, ay, 2, 4, ox, oy)
near(ax + ox / 4, bx + ox / 16, 'zoom keeps the point under the cursor x')
near(ay + oy / 4, by + oy / 16, 'zoom keeps the point under the cursor y')
bx, by = M.zoomToward(0, 0, 2, 2, ox, oy)
near(bx, 0, 'same zoom is a no-op x'); near(by, 0, 'same zoom is a no-op y')
bx, by = M.zoomToward(0, 0, 2, 1, 0, 0)
near(bx, 0, 'cursor on the anchor: no pan')
bx, by = M.zoomToward(500, 0, 4, 0, -1000, 0)
eq(bx, M.PAN_LIMIT, 'zoom result clamped')
-- zoom in then out at the same cursor returns to the start
bx, by = M.zoomToward(ax, ay, 2, 4, ox, oy)
bx, by = M.zoomToward(bx, by, 4, 2, ox, oy)
near(bx, ax, 'zoom round trip x'); near(by, ay, 'zoom round trip y')
-- whole-tile camera + sub-tile rest
local cx, cy, rx, ry = M.splitPan(2.25, -3.5, 3)
eq(cx, 2, 'camera x'); eq(cy, -3, 'camera y (half rounds up)')
eq(rx, -2, 'rest x px'); eq(ry, 4, 'rest y px')
cx, cy, rx, ry = M.splitPan(0, 0, 4)
eq(cx, 0, 'unpanned camera'); eq(rx, 0, 'unpanned rest x'); eq(ry, 0, 'unpanned rest y')
-- marker of the character when it is outside the view
eq(M.edgeMarker(50, 50, 200, 100), nil, 'inside')
local ex, ey, ea = M.edgeMarker(-80, 50, 200, 100)
eq(ex, 14, 'edge x'); eq(ey, 50, 'edge y'); eq(ea, '<', 'arrow left')
ex, ey, ea = M.edgeMarker(300, 400, 200, 100)
eq(ex, 186, 'edge x clamped'); eq(ey, 86, 'edge y clamped'); eq(ea, 'v', 'arrow down')
ex, ey, ea = M.edgeMarker(100, -500, 200, 100)
eq(ea, '^', 'arrow up')
eq(select(3, M.edgeMarker(900, 40, 200, 100)), '>', 'arrow right')
-- free area of the view
local fa = M.freeArea({ x = 0, y = -88, width = 1280, height = 888 }, { width = 1280, height = 800 },
  { top = 40, right = 177, bottom = 205 })
eq(fa.x, 0, 'free x'); eq(fa.y, 40, 'free y'); eq(fa.width, 1103, 'free width'); eq(fa.height, 555, 'free height')
fa = M.freeArea({ x = 300, y = 10, width = 400, height = 300 }, { width = 1280, height = 800 })
eq(fa.x, 300, 'inner view x'); eq(fa.width, 400, 'inner view width')
fa = M.freeArea({ x = 0, y = 0, width = 100, height = 100 }, { width = 50, height = 50 }, { left = 80 })
eq(fa.width, 0, 'empty free area')
-- default centre key
list = {}
eq(M.assignKey(list, M.CENTRE_ACTION, M.CENTRE_KEY), true, 'centre key added')
eq(M.assignKey(list, M.CENTRE_ACTION, M.CENTRE_KEY), false, 'centre key only once')
list = { entry('Other', 'Home') }
eq(M.assignKey(list, M.CENTRE_ACTION, M.CENTRE_KEY), false, 'Home taken: stays unbound')
eq(#list, 1, 'list kept')
eq(M.assignKey(nil, M.CENTRE_ACTION, M.CENTRE_KEY), false, 'no list for the centre key')
eq(M.sanitize({}).strip, true, 'strip on by default')
eq(M.sanitize({ strip = false }).strip, false, 'strip off')

-- click-through: only modified input (or input over the strip) belongs to the overlay
eq(M.wheelAction(false, false, false), nil, 'plain wheel reaches the game map')
eq(M.wheelAction(true, false, false), 'opacity', 'Ctrl+wheel opacity')
eq(M.wheelAction(true, true, false), 'opacity', 'Ctrl+Shift+wheel opacity')
eq(M.wheelAction(false, true, false), 'zoom', 'Shift+wheel zoom')
eq(M.wheelAction(false, false, true), 'zoom', 'wheel over the strip zooms')
eq(M.startsPan(true, false, false), false, 'plain middle press reaches the game map')
eq(M.startsPan(true, true, false), true, 'Shift+middle pans')
eq(M.startsPan(true, true, true), false, 'not over the strip')
eq(M.startsPan(false, true, false), false, 'Shift+left click reaches the game map (look)')

if fails > 0 then error(fails .. ' failure(s)') end
print('mapmath_test: ok')
