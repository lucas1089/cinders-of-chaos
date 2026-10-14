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

-- step timing: as Creature::getStepDuration (1000 * ground speed / speed, up to the 50 ms beat)
check(C.stepDuration(100, 200) == 500, 'step 100/200')
check(C.stepDuration(120, 150) == 800, 'step 120/150')
check(C.stepDuration(130, 180) == 750, 'step 130/180 rounds up to the beat (722 -> 750)')
check(C.stepDuration(0, 150) == 1000, 'ground speed 0 counts as 150')
check(C.stepDuration(100, 100000) == 50, 'never below one beat')
check(C.stepDuration(100, 0) == 0, 'no speed: no step')
-- ground speeds match the dark tile csv
local csv = io.open(dir .. '/../../../../server/data/items/dark_tiles.csv')
if csv then
  local n = 0
  for line in csv:lines() do
    local id, kind, speed = line:match('^(%d+),[^,]*,[^,]*,[^,]*,(%a+),[^,]*,[^,]*,[^,]*,[^,]*,[^,]*,(%d+),')
    if id and kind == 'ground' then
      n = n + 1
      check(C.GROUND_SPEED[tonumber(id)] == tonumber(speed), 'ground speed of ' .. id)
    end
  end
  csv:close()
  check(n == 9, 'nine grounds in the csv')
end

-- the walker: a back-and-forth of 2 tiles with pauses at the ends
local path = { { x = 5, y = 6, ms = 400, pause = 1000 }, { x = 6, y = 6, ms = 400, pause = 0 },
               { x = 7, y = 6, ms = 500, pause = 2000 }, { x = 6, y = 6, ms = 400, pause = 0 } }
local wk = C.newWalker(path)
local x, y, d, moving = wk.update(500)
check(x == 5 and y == 6 and not moving, 'stands through its first pause')
x, y, d, moving = wk.update(700)   -- 1200 ms: 200 into the first step
check(moving and math.abs(x - 5.5) < 1e-9 and y == 6 and d == C.EAST, 'half way through the first step, facing east')
check(select(5, wk.update(0)) == 6 and select(6, wk.update(0)) == 6, 'while stepping it is on the tile it steps to')
x, y, d, moving = wk.update(200 + 500)   -- 1900: the second step (500 ms) ends exactly
check(x == 7 and not moving and select(5, wk.update(0)) == 7, 'at the far end, pausing')
x, y, d, moving = wk.update(2000 + 200)
check(moving and d == C.WEST and math.abs(x - 6.5) < 1e-9, 'walks back west after the pause')
-- a whole cycle is the sum of steps and pauses: after it, the same place again
local w2 = C.newWalker(path)
local cycle = 1000 + 400 + 500 + 2000 + 400 + 400
local ax, ay = w2.update(1234)
local bx, by = w2.update(cycle)
check(math.abs(ax - bx) < 1e-9 and ay == by, 'periodic over one cycle')
-- small updates move at most a tile per step and never diagonally
local w3 = C.newWalker(path)
local px, py = w3.update(0)
for _ = 1, 400 do
  local nx, ny = w3.update(25)
  check(math.abs(nx - px) <= 25 / 400 + 1e-9 and ny == py, 'smooth, axis-aligned motion')
  px, py = nx, ny
end
check(select(1, C.newWalker({ { x = 3, y = 4, pause = 0 } }).update(100)) == 3, 'a one-node path stands')
check(select(3, C.newWalker(path, 500, C.WEST).update(100)) == C.WEST, 'faces its own way until it sets off')
check(select(3, C.newWalker(path).update(100)) == C.SOUTH, 'faces south by default')

-- patrols in the layout: every monster that has one stays legal on every tile of it, apart from the others
local function patrolChecks(cols, rows, seed, keep)
  keep = keep or { { math.floor(cols * 0.3), 1, math.ceil(cols * 0.7), math.floor(rows * 0.45) },
                   { math.floor(cols * 0.35), math.floor(rows * 0.6), math.ceil(cols * 0.65), rows } }
  local s = C.layout(cols, rows, seed, keep)
  local tag = string.format(' (%dx%d seed %d)', cols, rows, seed)
  local static = {}
  for _, t in ipairs(s.things) do
    if t.kind == 'object' then
      for yy = t.y - t.h + 1, t.y do for xx = t.x - t.w + 1, t.x do static[yy * 10000 + xx] = true end end
    end
  end
  local owner, walkers = {}, 0
  for ci, t in ipairs(s.things) do
    if t.kind == 'creature' then
      local nodes = t.path or { { x = t.x, y = t.y } }
      if t.path then
        walkers = walkers + 1
        check(#t.path >= 2 and #t.path % 2 == 0, 'a patrol has steps out and back' .. tag)
        check(t.path[1].x == t.x and t.path[1].y == t.y, 'a patrol starts where the monster stands' .. tag)
        local pauses = 0
        for i, nd in ipairs(t.path) do
          local nx = t.path[i % #t.path + 1]
          check(math.abs(nx.x - nd.x) + math.abs(nx.y - nd.y) == 1, 'one straight tile per step' .. tag)
          check(nd.ms and nd.ms >= 50 and nd.ms <= 2000, 'step time' .. tag)
          if nd.pause > 0 then pauses = pauses + 1 end
        end
        check(pauses >= 1, 'pauses on the patrol' .. tag)
      end
      for ni, nd in ipairs(nodes) do
        check(nd.x - t.w + 1 >= 2 and nd.x <= cols - 1 and nd.y <= rows - 1,
              'monsters and patrols stay off the edge columns and row that hang over the window' .. tag)
        for yy = nd.y - t.w + 1, nd.y do
          for xx = nd.x - t.w + 1, nd.x do
            check(xx >= 1 and xx <= cols and yy >= 4 and yy <= rows, 'patrol inside the scene, below the wall' .. tag)
            check(not static[yy * 10000 + xx], 'no patrol through an object' .. tag)
            check(s.ground[yy][xx] ~= C.GROUND.pool, 'no patrol over the pool' .. tag)
            for _, k in ipairs(keep) do
              check(not (xx >= k[1] and xx <= k[3] and yy >= k[2] and yy <= k[4]), 'no patrol behind the panel or logo' .. tag)
            end
            local o = owner[yy * 10000 + xx]
            check(o == nil or o == ci, 'no two monsters share a patrol tile' .. tag)
            owner[yy * 10000 + xx] = ci
          end
        end
      end
    end
  end
  local placed = 0
  for _, t in ipairs(s.things) do if t.kind == 'creature' then placed = placed + 1 end end
  check(placed == 9, 'all nine monsters are placed' .. tag .. ': ' .. placed)
  check(walkers >= 6, 'most monsters walk' .. tag .. ': ' .. walkers)
end
patrolChecks(21, 13, 1666)
patrolChecks(31, 13, 1666)
patrolChecks(20, 12, 1)
patrolChecks(30, 17, 9)
patrolChecks(40, 23, 3)
-- the sign-in screen's own keep rects (logo, panel) at 1280x720, 1920x1080 (96 px tiles), 1024x768, 1366x768
-- and 1600x900
patrolChecks(21, 13, 1666, { { 7, 4, 15, 10 }, { 6, 9, 16, 12 } })
patrolChecks(21, 13, 1666, { { 7, 4, 15, 10 }, { 8, 9, 14, 11 } })
patrolChecks(17, 13, 1666, { { 6, 5, 12, 9 }, { 4, 9, 14, 12 } })
patrolChecks(23, 13, 1666, { { 7, 4, 17, 10 }, { 7, 9, 17, 13 } })
patrolChecks(26, 16, 1666, { { 8, 5, 19, 12 }, { 9, 11, 18, 14 } })

if fails > 0 then
  print(fails .. ' failure(s)')
  os.exit(1)
end
print('loginscene_core: all tests passed')
