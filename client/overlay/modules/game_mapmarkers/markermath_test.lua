-- luajit markermath_test.lua && lua5.3 markermath_test.lua (CI runs it from the repo root)
-- The map markers' view rules: settings, party colours, floor arrows, the edge clamp and its direction, the glide,
-- the hover text, the category filters and the visible points of interest.
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'markermath.lua')
local M = MapMarkerMath
local fails, checks = 0, 0
local function eq(a, b, what)
  checks = checks + 1
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end
local function ok(c, what) eq(not not c, true, what) end

-- settings
local s = M.sanitize(nil)
eq(s.party, true, 'party on by default'); eq(s.poi, true, 'points of interest on by default')
for _, c in ipairs(M.CATEGORIES) do eq(s.cats[c], true, 'category on by default: ' .. c) end
s = M.sanitize({ party = false, poi = 'true', cats = { hunt = false, shop = 'false', junk = false } })
eq(s.party, false, 'party off'); eq(s.poi, true, 'string true'); eq(s.cats.hunt, false, 'hunt off'); eq(s.cats.shop, false, 'shop off')
eq(s.cats.junk, nil, 'unknown category dropped'); eq(s.cats.town, true, 'others stay on')
eq(M.sanitize({ cats = 'x' }).cats.boss, true, 'bad cats')
for kind, cat in pairs(M.KIND_CATEGORY) do
  local found = false
  for _, c in ipairs(M.CATEGORIES) do if c == cat then found = true end end
  ok(found, 'kind ' .. kind .. ' has a category with a check box')
  ok(M.CATEGORY_LABEL[cat], 'category label ' .. cat)
end

-- colours: a member keeps its colour, a leaver frees it, a newcomer takes the lowest free slot
local slots = M.assignColors({}, { 5, 9, 2 })
eq(slots[5], 1, 'first'); eq(slots[9], 2, 'second'); eq(slots[2], 3, 'third')
M.assignColors(slots, { 2, 5, 7 })
eq(slots[5], 1, 'kept'); eq(slots[2], 3, 'kept 2'); eq(slots[9], nil, 'leaver freed'); eq(slots[7], 2, 'newcomer takes the free slot')
eq(M.color(1), M.COLORS[1], 'colour 1'); eq(M.color(#M.COLORS + 1), M.COLORS[1], 'colours wrap')

-- floor arrows
eq(M.floorArrow(6, 7), 'up', 'z 6 seen from 7 is up'); eq(M.floorArrow(9, 7), 'down', 'below'); eq(M.floorArrow(7, 7), nil, 'same floor')

-- directions
eq(M.dir8(1, 0), 'e', 'east'); eq(M.dir8(0, -1), 'n', 'north'); eq(M.dir8(-1, 0), 'w', 'west'); eq(M.dir8(0, 1), 's', 'south')
eq(M.dir8(1, 1), 'se', 'south-east'); eq(M.dir8(-1, -1), 'nw', 'north-west'); eq(M.dir8(1, -1), 'ne', 'north-east')
eq(M.dir8(-1, 1), 'sw', 'south-west'); eq(M.dir8(10, 3), 'e', 'mostly east'); eq(M.dir8(0, 0), nil, 'no vector')

-- the edge clamp: a 200x100 minimap at (100, 50)
local rect = { x = 100, y = 50, width = 200, height = 100 }
local inside, x, y, d = M.edge(150, 80, rect, 7)
eq(inside, true, 'inside'); eq(x, 150, 'inside x'); eq(d, nil, 'no arrow inside')
inside, x, y, d = M.edge(1000, 100, rect, 7)
eq(inside, false, 'far east is outside'); eq(x, 293, 'clamped to the right edge'); eq(y, 100, 'on the centre line'); eq(d, 'e', 'points east')
inside, x, y, d = M.edge(200, -500, rect, 7)
eq(x, 200, 'north: centre x'); eq(y, 57, 'top edge'); eq(d, 'n', 'points north')
inside, x, y, d = M.edge(-1000, 1000, rect, 7)
eq(d, 'sw', 'south-west'); ok(x >= 107 and x <= 293 and y >= 57 and y <= 143, 'clamped inside the inset rect')
ok(x == 107 or y == 143, 'on an edge of the inset rect')
inside = M.edge(103, 100, rect, 7)
eq(inside, false, 'closer than the margin counts as outside')

-- the controls over the minimap's right side cut the edge arrows' area
local cr = M.clampRect(rect, { { x = 270, y = 50, width = 30, height = 40 }, { x = 290, y = 60, width = 10, height = 60 },
  { x = 100, y = 40, width = 200, height = 12 }, { x = 120, y = 60, width = 20, height = 20 }, { x = 400, y = 60, width = 20, height = 20 } })
eq(cr.width, 170, 'the leftmost control on the right side sets the edge'); eq(cr.x, 100, 'left kept'); eq(cr.height, 100, 'height kept')
eq(M.clampRect(rect, nil).width, 200, 'no controls: the whole minimap')

-- the glide
local a = M.retarget(nil, 100, 100, 7, 0)
eq(a.jump, true, 'first position: no glide')
local gx, gy, done = M.glide(a, 0)
eq(gx, 100, 'at the target'); eq(done, true, 'done')
a = M.retarget(a, 104, 100, 7, 1000)
gx, gy, done = M.glide(a, 1000 + M.ANIM_MS / 2)
eq(gx, 102, 'half way'); eq(done, false, 'still gliding')
gx, gy, done = M.glide(a, 1000 + M.ANIM_MS)
eq(gx, 104, 'arrived'); eq(done, true, 'arrived: done')
local mid = M.retarget(M.retarget(M.retarget(nil, 0, 0, 7, 0), 8, 0, 7, 0), 8, 8, 7, M.ANIM_MS / 2)
eq(mid.from.x, 4, 'a new target glides from where it is shown now'); eq(mid.to.y, 8, 'to the new one')
eq(M.retarget(a, 104, 100, 6, 5000).jump, true, 'a floor change jumps')
eq(M.retarget(a, 104 + M.JUMP_TILES + 1, 100, 7, 5000).jump, true, 'a teleport jumps')

-- the hover text
eq(M.memberText({ n = 'Aria', p = 80, x = 110, y = 90, z = 5 }, { x = 100, y = 100, z = 7 }),
  'Aria, 80% health, 2 floors up, 10 squares north-east', 'hover text')
eq(M.memberText({ n = 'Bo', p = 100, x = 100, y = 101, z = 8 }, { x = 100, y = 100, z = 7 }),
  'Bo, 100% health, 1 floor down, 1 square south', 'one floor, one square')
eq(M.memberText({ n = 'Cy', x = 100, y = 100, z = 7 }, { x = 100, y = 100, z = 7 }), 'Cy', 'same tile')
local others = M.others({ { i = 1, x = 1, y = 1, z = 7 }, { i = 2, x = 1, y = 1, z = 7 }, { i = 3 }, 'junk' }, 1)
eq(#others, 1, 'the viewer and broken entries left out'); eq(others[1].i, 2, 'the other member')

-- points of interest
local marks = {
  { k = 'temple', x = 100, y = 100, z = 7, n = 'Temple' }, { k = 'hunt', x = 120, y = 100, z = 7, n = 'Hunting' },
  { k = 'shop', x = 300, y = 100, z = 7, n = 'Far shop' }, { k = 'depot', x = 100, y = 100, z = 6, n = 'Depot' },
  { k = 'castle', x = 1, y = 1, z = 7 }, 'junk',
}
local floors = M.byFloor(marks)
eq(#floors[7], 3, 'three on floor 7 (unknown kind dropped)'); eq(#floors[6], 1, 'one on floor 6')
local cats = M.sanitize(nil).cats
local b = M.viewBounds({ x = 110, y = 100, z = 7 }, 100, 100, 2, 1)
eq(b.x1, 84, 'bounds: 25 tiles each side plus the margin'); eq(b.x2, 136, 'bounds right')
local vis = M.visiblePoi(floors, b, cats)
eq(#vis, 2, 'the far shop is not in view')
cats.hunt = false
vis = M.visiblePoi(floors, b, cats)
eq(#vis, 1, 'category filter: hunting areas off'); eq(vis[1].k, 'temple', 'the temple stays')
cats.town = false
eq(#M.visiblePoi(floors, b, cats), 0, 'town off too: nothing')
cats = M.sanitize(nil).cats
b.z = 6
eq(#M.visiblePoi(floors, b, cats), 1, 'another floor shows its own marks')
b.z = 7
vis = M.visiblePoi(floors, M.viewBounds({ x = 100, y = 100, z = 7 }, 1000, 1000, 1, 1), cats, 2)
eq(#vis, 2, 'limit'); eq(vis[1].k, 'temple', 'nearest the centre first')
local list = { { k = 'temple', x = 1, y = 1, z = 7 } }
eq(M.addMarks(list, { { k = 'temple', x = 1, y = 1, z = 7 }, { k = 'hunt', x = 5, y = 5, z = 7, n = 'h' } }), 1, 'reveal adds the new one only')
eq(#list, 2, 'two marks now')

-- hover hit test: the last drawn wins
local hits = { { rect = { x = 0, y = 0, width = 10, height = 10 }, text = 'a' }, { rect = { x = 5, y = 5, width = 10, height = 10 }, text = 'b' } }
eq(M.hit(hits, 7, 7).text, 'b', 'top marker'); eq(M.hit(hits, 2, 2).text, 'a', 'lower marker'); eq(M.hit(hits, 50, 50), nil, 'nothing')

-- game view indicator
eq(M.sanitize(nil).game, true, 'game view arrows on by default'); eq(M.sanitize({ game = false }).game, false, 'game view arrows off')
local vd = { width = 15, height = 11 }
ok(M.inView(7, 5, vd), 'edge tile is in view'); ok(not M.inView(8, 0, vd), 'one past sideways'); ok(not M.inView(0, 6, vd), 'one past down')
ok(M.inView(-7, -5, vd), 'far corner in view')
local panel = { x = 100, y = 50, width = 750, height = 550 }  -- 50 px tiles
local me = { x = 1000, y = 1000, z = 7 }
eq(M.gameIndicator(me, { x = 1003, y = 1002, z = 7 }, vd, panel, false), nil, 'in view: no arrow')
eq(M.gameIndicator(me, { x = 1030, y = 1000, z = 6 }, vd, panel, false), nil, 'other floor: no arrow')
eq(M.gameIndicator(me, { x = 1030, y = 1000, z = 8 }, vd, panel, false), nil, 'floor below: no arrow')
local g = M.gameIndicator(me, { x = 1030, y = 1000, z = 7 }, vd, panel, false)
eq(g.dir, 'e', 'east'); eq(g.dist, 30, 'distance'); eq(g.x, 100 + 750 - M.GAME_MARGIN, 'clamped to the right edge with margin')
eq(g.y, 50 + 275, 'on the middle row'); eq(g.side, 'left', 'label left of an arrow on the right edge')
g = M.gameIndicator(me, { x = 990, y = 985, z = 7 }, vd, panel, false)
eq(g.dir, 'nw', 'north-west'); eq(g.dist, 15, 'larger axis'); eq(g.side, 'right', 'label right of an arrow on the left')
ok(g.x >= panel.x + M.GAME_MARGIN and g.y >= panel.y + M.GAME_MARGIN, 'inside the inset rect')
g = M.gameIndicator(me, { x = 1000, y = 1008, z = 7 }, vd, panel, false)
eq(g.dir, 's', 'south'); eq(g.y, 50 + 550 - M.GAME_MARGIN, 'bottom edge'); eq(g.x, 100 + 375, 'centred column')
g = M.gameIndicator(me, { x = 1008, y = 1000, z = 7 }, vd, panel, true)
eq(g.dir, 'e', 'kept aspect: still east'); ok(g.x <= panel.x + panel.width - M.GAME_MARGIN, 'kept aspect: inside the panel')
local tw, th = M.tileSize(panel, vd, true); eq(tw, th, 'aspect kept: square tiles'); eq(tw, 50, 'min of both')
eq(M.gameText('Ann', 12), 'Ann 12', 'label text'); eq(M.gameText(nil, 3), '? 3', 'label without a name')

print(string.format('markermath_test: %d checks, %d failed', checks, fails))
if fails > 0 then os.exit(1) end
