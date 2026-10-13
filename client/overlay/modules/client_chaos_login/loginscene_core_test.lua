-- Tests of loginscene_core.lua (no client API): luajit / lua5.3 client/overlay/modules/client_chaos_login/loginscene_core_test.lua
local dir = (arg and arg[0] or ''):match('^(.*)[/\\]') or '.'
local C = dofile(dir .. '/loginscene_core.lua')

local fails = 0
local function check(cond, what)
  if not cond then
    fails = fails + 1
    print('FAIL: ' .. what)
  end
end

-- random numbers: the same in every interpreter, in range
local r = C.rng(42)
local first = { r.next(), r.next(), r.next() }
check(first[1] == 705894 and first[2] == 1126542223 and first[3] == 1579310009, 'Park-Miller sequence')
local r2 = C.rng(7)
for _ = 1, 1000 do
  local v = r2.int(3, 9)
  check(v >= 3 and v <= 9 and v == math.floor(v), 'int in range')
  local f = r2.float()
  check(f >= 0 and f < 1, 'float in [0, 1)')
end
check(C.rng(0).next() > 0 and C.rng(-5).next() > 0, 'seed 0 and negative seeds work')

-- settings
check(C.mode('art') == 'art' and C.mode('alternate') == 'alternate', 'known modes')
check(C.mode(nil) == 'scene' and C.mode('nonsense') == 'scene', 'default mode')
check(C.nextMode('scene') == 'art' and C.nextMode('art') == 'alternate' and C.nextMode('alternate') == 'scene', 'cycle')
for _, m in ipairs(C.MODES) do check(C.MODE_LABEL[m] ~= nil, 'label for ' .. m) end

-- alternating: scene, fade out, artwork, fade in
check(C.alternateOpacity(0, 40, 2) == 1, 'scene first')
check(C.alternateOpacity(37.9, 40, 2) == 1, 'scene until the fade')
local mid = C.alternateOpacity(39, 40, 2)
check(mid > 0.4 and mid < 0.6, 'half way through the fade out')
check(C.alternateOpacity(45, 40, 2) == 0, 'artwork')
check(C.alternateOpacity(79, 40, 2) > 0.4, 'fading back in')
check(C.alternateOpacity(80, 40, 2) == 1, 'scene again after a whole cycle')
local prev = 1
for t = 38, 40, 0.1 do
  local o = C.alternateOpacity(t, 40, 2)
  check(o <= prev + 1e-9, 'fade out never brightens')
  prev = o
end

-- tile size: whole sprites, about 11 rows
check(C.tileSize(1920, 1080) == 96, '1080p: 96 px tiles')
check(C.tileSize(1280, 720) == 64, '720p: 64 px tiles')
check(C.tileSize(800, 300) == 32, 'small window: 32 px')
check(C.tileSize(7680, 4320) == 128, 'at most 4x')

-- borders: a 1-tile ash patch in obsidian gets the four sides and the four outer corners around it
local function famGrid(map)
  return function(x, y)
    local row = map[y]
    local c = row and row:sub(x, x) or ''
    if c == 'a' then return 'ash' end
    if c == '' then return nil end
    return 'obsidian'
  end
end
local single = famGrid({ '...', '.a.', '...' })
local function has(list, p)
  for _, v in ipairs(list) do if v == p then return true end end
  return false
end
check(#C.bordersAt(single, 2, 2, 'ash') == 0, 'no border on the patch itself')
check(has(C.bordersAt(single, 2, 3, 'ash'), 'n'), 'south neighbour: the ash is north')
check(has(C.bordersAt(single, 1, 2, 'ash'), 'e'), 'west neighbour: the ash is east')
check(has(C.bordersAt(single, 1, 1, 'ash'), 'outer_se'), 'north-west diagonal: outer south-east')
check(#C.bordersAt(single, 1, 1, 'ash') == 1, 'a diagonal gets only its corner')
local corner = famGrid({ 'aa', 'a.' })
local p = C.bordersAt(corner, 2, 2, 'ash')
check(#p == 1 and p[1] == 'inner_nw', 'ash north and west: inner north-west')
check(C.borderId('ash', 'n') == 27505 and C.borderId('ash', 'inner_sw') == 27516, 'ash border ids')
check(C.borderId('moss', 'n') == 27529 and C.borderId('wetRock', 'outer_sw') == 27524, 'moss and wet rock ids')

-- the layout
local function layoutChecks(cols, rows, seed)
  local keep = { { math.floor(cols * 0.3), 1, math.ceil(cols * 0.7), math.floor(rows * 0.45) },
                 { math.floor(cols * 0.35), math.floor(rows * 0.6), math.ceil(cols * 0.65), rows } }
  local s = C.layout(cols, rows, seed, keep)
  local tag = string.format(' (%dx%d seed %d)', cols, rows, seed)
  check(s.cols == cols and s.rows == rows, 'size' .. tag)
  local validGround = {}
  for _, id in pairs(C.GROUND) do validGround[id] = true end
  for y = 1, rows do
    for x = 1, cols do check(validGround[s.ground[y][x]], 'ground id' .. tag) end
  end
  for _, b in ipairs(s.borders) do
    check(b[3] >= 27493 and b[3] <= 27540, 'border id' .. tag)
    check(b[1] >= 1 and b[1] <= cols and b[2] >= 1 and b[2] <= rows, 'border inside' .. tag)
  end
  local creatures, objects, walls, lastY = 0, 0, 0, 0
  local occupied = {}
  for _, t in ipairs(s.things) do
    check(t.y >= lastY, 'drawing order by row' .. tag)
    lastY = t.y
    if t.kind == 'creature' then
      creatures = creatures + 1
      check(t.look and t.look > 0 and t.name, 'creature look' .. tag)
      check(t.y >= 4, 'creatures stand below the wall' .. tag)
      for _, k in ipairs(keep) do
        check(not (t.x >= k[1] and t.x <= k[3] and t.y >= k[2] and t.y <= k[4]), 'no creature behind the panel or logo' .. tag)
      end
      check(t.dir >= 0 and t.dir <= 3, 'direction' .. tag)
    elseif t.kind == 'object' then
      objects = objects + 1
      check(t.id >= 27544 and t.id <= 27557, 'object id' .. tag)
    else
      walls = walls + 1
      check(t.id >= 27541 and t.id <= 27543, 'wall id' .. tag)
    end
    if t.kind ~= 'wall' then
      for yy = t.y - t.h + 1, t.y do
        for xx = t.x - t.w + 1, t.x do
          local k = yy * 10000 + xx
          check(not occupied[k], 'no two things on one tile' .. tag)
          occupied[k] = true
          check(xx >= 1 and xx <= cols and yy >= 1 and yy <= rows, 'thing inside' .. tag)
        end
      end
    end
  end
  check(creatures >= 5, 'at least five monsters' .. tag .. ': ' .. creatures)
  check(objects >= 8, 'objects' .. tag .. ': ' .. objects)
  check(walls == cols + 1, 'a wall piece per column' .. tag)
  check(#s.lights >= 2, 'lights' .. tag)
  return s
end
local a = layoutChecks(20, 12, 1)
layoutChecks(20, 12, 2)
layoutChecks(14, 9, 5)
layoutChecks(30, 17, 9)
layoutChecks(40, 23, 3)

-- deterministic
local b = C.layout(20, 12, 1, { { 6, 1, 14, 5 }, { 7, 7, 13, 12 } })
local a2 = C.layout(20, 12, 1, { { 6, 1, 14, 5 }, { 7, 7, 13, 12 } })
local same = #b.things == #a2.things and #b.borders == #a2.borders
for i, t in ipairs(b.things) do
  local u = a2.things[i]
  same = same and u and t.x == u.x and t.y == u.y and (t.id or t.look) == (u.id or u.look)
end
for y = 1, 12 do
  for x = 1, 20 do same = same and b.ground[y][x] == a2.ground[y][x] end
end
check(same, 'same size and seed: same scene')
check(a.place and #a.place > 0 and not a.place:find('[^ -~]'), 'the caption is ASCII (display font: space..~)')

if fails > 0 then
  print(fails .. ' failure(s)')
  os.exit(1)
end
print('loginscene_core: all tests passed')
