-- luajit npcmarkmath_test.lua && lua5.3 npcmarkmath_test.lua (CI runs it from the repo root)
-- The marks over NPC heads (O415): the server message (a full list, then differences), the marks by NPC name, the screen
-- maths (the same as the NPC dialogue's bubble: stretch, walk offsets, the tile centre) and where the mark goes over the
-- name, hidden on another floor and outside the map, and the setting.
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'markermath.lua')
dofile(dir .. 'npcmarkmath.lua')
local M = NpcMarkMath
local fails, checks = 0, 0
local function eq(a, b, what)
  checks = checks + 1
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end
local function ok(c, what) eq(not not c, true, what) end

-- the setting: on by default, old settings keep it on
eq(MapMarkerMath.sanitize(nil).npcmarks, true, 'NPC marks on by default')
eq(MapMarkerMath.sanitize({ npcmarks = false }).npcmarks, false, 'off when the player turned it off')
eq(MapMarkerMath.sanitize({ party = false }).npcmarks, true, 'old settings: on')
eq(MapMarkerMath.sanitize({ npcmarks = 'false' }).npcmarks, false, 'the stored string')

-- the art
eq(M.image('new'), '/images/chaos/mapmarkers/npcmark_new', 'gold !')
eq(M.image('ready'), '/images/chaos/mapmarkers/npcmark_ready', 'gold ?')
eq(M.image('locked'), '/images/chaos/mapmarkers/npcmark_locked', 'grey !')
eq(M.image('sparkly'), nil, 'an unknown mark has no image')
eq(M.image(nil), nil, 'no mark')

-- parse: junk dropped
local p = M.parse({ full = true, set = { { n = 'Archivist Maelis', m = 'new' }, { n = 'X', m = 'sparkly' }, { n = '', m = 'new' }, 'junk',
  { m = 'ready' } }, clear = { 'Gone', '', 5 } })
eq(p.full, true, 'full'); eq(#p.set, 1, 'one valid mark'); eq(p.set[1].n, 'Archivist Maelis', 'its name'); eq(#p.clear, 1, 'one valid clear')
p = M.parse(nil); eq(p.full, false, 'nil message'); eq(#p.set + #p.clear, 0, 'nothing in it')
p = M.parse({ set = 'x', clear = 3 }); eq(#p.set + #p.clear, 0, 'bad fields')

-- apply: a full list starts again, a difference changes what it names, names are case-blind
local state = {}
eq(M.apply(state, M.parse({ full = true, set = { { n = 'Archivist Maelis', m = 'new' }, { n = 'Warden Ysolde', m = 'locked' } } })), 2, 'two marks')
eq(M.markFor(state, 'archivist maelis'), 'new', 'matched by lower case name'); eq(M.markFor(state, 'ARCHIVIST MAELIS'), 'new', 'any case')
eq(M.markFor(state, 'Nobody'), nil, 'an unmarked NPC')
M.apply(state, M.parse({ set = { { n = 'Archivist Maelis', m = 'ready' } }, clear = { 'Warden Ysolde' } }))
eq(M.markFor(state, 'Archivist Maelis'), 'ready', 'a difference changes a mark'); eq(M.markFor(state, 'Warden Ysolde'), nil, 'and clears one')
M.apply(state, M.parse({ full = true, set = { { n = 'Cantor Velith', m = 'new' } } }))
eq(M.markFor(state, 'Archivist Maelis'), nil, 'a full list forgets the old ones'); eq(M.markFor(state, 'Cantor Velith'), 'new', 'and keeps the new')
M.apply(state, M.parse({ full = true, set = {} }))
eq(next(state), nil, 'an empty full list clears everything')
local many = {}
for i = 1, M.MAX + 10 do many[#many + 1] = { n = 'Npc ' .. i, m = 'new' } end
local count = M.apply(state, M.parse({ full = true, set = many }))
eq(count, M.MAX, 'at most MAX marks are kept')

-- which creatures get a widget
state = {}
M.apply(state, M.parse({ full = true, set = { { n = 'Archivist Maelis', m = 'new' }, { n = 'Cantor Velith', m = 'ready' } } }))
local w = M.wanted(state, { [30] = { name = 'Archivist Maelis' }, [10] = { name = 'Cantor Velith' }, [20] = { name = 'Loot Buyer' } })
eq(#w, 2, 'the marked NPCs only'); eq(w[1].id, 10, 'ordered by id'); eq(w[1].mark, 'ready', 'with its mark'); eq(w[2].id, 30, 'the other')
eq(#M.wanted({}, { [1] = { name = 'Archivist Maelis' } }), 0, 'no marks, none wanted')

-- the screen maths
local rect = { x = 100, y = 50, width = 960, height = 704 } -- 15 x 11 tiles of 64 px: stretch 2
local vis = { width = 15, height = 11 }
eq(M.stretch(rect, vis, 32), 2, 'the visible tiles fill the map widget')
eq(M.stretch(rect, { width = 0, height = 0 }, 32), 1, 'no visible dimension')
local keep = M.mapRect({ x = 0, y = 0, width = 1000, height = 500 }, vis, true, 32)
eq(keep.height, 500, 'kept aspect: the height fills'); ok(keep.width < 1000 and keep.x > 0, 'kept aspect: centred, narrower')
eq(M.mapRect(rect, vis, false, 32), rect, 'not kept: the widget')
local ox, oy = M.walkOffset({ x = 5, y = 5, z = 7 }, { x = 6, y = 5, z = 7 }, 0.25, 32)
eq(ox, -24, 'a creature that stepped east is drawn 3/4 of a tile to the west of its tile'); eq(oy, 0, 'no vertical')
ox = M.walkOffset({ x = 5, y = 5, z = 7 }, { x = 6, y = 5, z = 7 }, 1, 32); eq(ox, 0, 'the step is done')
ox, oy = M.walkOffset({ x = 5, y = 5, z = 7 }, { x = 5, y = 5, z = 6 }, 0, 32); eq(ox + oy, 0, 'another floor: no offset')
ox, oy = M.walkOffset({ x = 1, y = 5, z = 7 }, { x = 6, y = 5, z = 7 }, 0, 32); eq(ox + oy, 0, 'a jump (a teleport) is no step')
local cam = { x = 1000, y = 1000, z = 7 }
local c = M.tileCenter(rect, 2, 32, cam, { x = 0, y = 0 }, { x = 1000, y = 1000, z = 7 }, nil)
eq(c.x, 100 + 480, 'the camera tile is the middle'); eq(c.y, 50 + 352, 'of the widget')
c = M.tileCenter(rect, 2, 32, cam, { x = 0, y = 0 }, { x = 1002, y = 999, z = 7 }, nil)
eq(c.x, 580 + 128, '2 tiles east'); eq(c.y, 402 - 64, '1 tile north')
c = M.tileCenter(rect, 2, 32, cam, { x = 16, y = 0 }, { x = 1002, y = 999, z = 7 }, { x = -32, y = 0 })
eq(c.x, 580 + 128 - 32 - 64, 'the camera creature and the NPC both walking')
eq(M.tileCenter(rect, 2, 32, cam, nil, { x = 1000, y = 1000, z = 6 }, nil), nil, 'another floor: nothing')
eq(M.tileCenter(rect, 2, 32, nil, nil, { x = 1000, y = 1000, z = 6 }, nil), nil, 'no camera')

-- the mark's size and place: over the name, which is over the head
local sw, sh = M.size(1); eq(sw, 16, 'width at stretch 1'); eq(sh, 24, 'height at stretch 1')
sw, sh = M.size(2); eq(sw, 32, 'doubled'); eq(sh, 48, 'doubled')
sw, sh = M.size(5); eq(sw, 32, 'capped at twice'); sw, sh = M.size(0.1); eq(sw, 12, 'kept readable below')
local x, y, mw, mh = M.place(rect, 1, 32, { x = 500, y = 400 }, 8, 0, 2)
eq(mw, 16, 'width'); eq(mh, 24, 'height'); eq(x, 500 - 8, 'centred over the NPC')
eq(y, 400 - (16 + 8 + 2) - 16 - 2 - 24, 'the bottom edge 2 px over the name, which is 16 px over the head point')
local _, y2 = M.place(rect, 1, 32, { x = 500, y = 400 }, 8, 12, 2)
eq(y2, y - 12, 'a tall look lifts it with its name')
local _, y3 = M.place(rect, 1, 32, { x = 500, y = 400 }, 20, 0, 2)
eq(y3, y - 12, 'a look with a larger displacement')
eq(M.place(rect, 1, 32, { x = 2000, y = 400 }, 8, 0, 2), nil, 'outside the map to the right: hidden')
eq(M.place(rect, 1, 32, { x = 500, y = 10 }, 8, 0, 2), nil, 'above the map: hidden')
ok(M.place(rect, 1, 32, { x = 108, y = 400 }, 8, 0, 2), 'at the edge: still drawn')
ok(M.TICK_MS <= 50, 'follows every few frames')

print(string.format('npcmarkmath_test: %d checks, %d failed', checks, fails))
if fails > 0 then os.exit(1) end
