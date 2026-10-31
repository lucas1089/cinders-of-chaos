-- Cinders of Chaos login scene: the parts without client API (tests: loginscene_core_test.lua, LuaJIT and Lua 5.3).
--
-- The scene is a small piece of our own world drawn behind the login widgets: the dark tile set (client ids
-- 27484-27557, client/MANIFEST.md "Dark tile set") laid out as a ruined courtyard at the ash wastes, with our own
-- monsters standing in it. layout() decides every tile, border, object and creature from the grid size and a seed;
-- loginscene.lua turns that into UIItem / UICreature widgets and animates them. Deterministic: the same size and
-- seed give the same scene (a window resize keeps the picture's character).

local M = {}
LoginSceneCore = M

-- ---------------------------------------------------------------- ids (server/data/items/dark_tiles.csv)
M.GROUND = {
  obsidian = 27484, magma = 27485, ash = 27486, bones = 27487, wetRock = 27488, mossyRock = 27489,
  moss = 27490, ruined = 27491, pool = 27492,
}
-- border families: the first id of each family's 12 pieces, in the csv order n e s w, outer ne nw se sw, inner ne nw se sw
M.BORDER_FIRST = { obsidian = 27493, ash = 27505, wetRock = 27517, moss = 27529 }
M.BORDER_PIECES = { 'n', 'e', 's', 'w', 'outer_ne', 'outer_nw', 'outer_se', 'outer_sw',
                    'inner_ne', 'inner_nw', 'inner_se', 'inner_sw' }
M.WALL = { dark = 27541, ruined = 27542, obsidian = 27543 }
-- objects: id and size in tiles (w, h); a thing is drawn up and left of its tile, like on the map
M.OBJECT = {
  deadTree = { 27544, 2, 2 }, twistedTree = { 27545, 2, 2 }, deadBush = { 27546, 1, 1 }, boulder = { 27547, 1, 1 },
  outcrop = { 27548, 2, 2 }, pillar = { 27549, 1, 2 }, brokenPillar = { 27550, 1, 1 }, brazier = { 27551, 1, 2 },
  torch = { 27552, 1, 2 }, glowcapPurple = { 27553, 1, 1 }, glowcapTeal = { 27554, 1, 1 },
  crystals = { 27555, 1, 1 }, bonePile = { 27556, 1, 1 }, rubble = { 27557, 1, 1 },
}
-- which family a ground belongs to (borders are drawn where families meet); the courtyard floor has none
M.FAMILY = {
  [27484] = 'obsidian', [27485] = 'obsidian', [27492] = 'obsidian',
  [27486] = 'ash', [27487] = 'ash', [27488] = 'wetRock', [27489] = 'wetRock', [27490] = 'moss',
}
-- the patch families that draw their border over their neighbours (the base obsidian does not)
M.PATCH_FAMILIES = { 'ash', 'wetRock', 'moss' }

-- our own monsters (server/data/monster/monsters/chaos): look type, name, how they stand
--   'idle'  the outfit's idle frames (or still) while it stands
--   'hover' its walking frames all the time (ghosts, flames: they drift)
-- speed: a stroll speed in the server's units (their hunting speeds of 49 to 800 would crawl or race); it gives the
-- step time the way the client's Creature::getStepDuration does
M.CREATURES = {
  { look = 1539, name = 'Death Mage', idle = 'idle', speed = 180 },
  { look = 1542, name = 'Risen Skeleton', idle = 'idle', speed = 150 },
  { look = 3185, name = 'Bone Golem', idle = 'idle', big = true, speed = 120 },
  { look = 1545, name = 'Lich Shade', idle = 'hover', speed = 160 },
  { look = 2120, name = 'Gloomfire', idle = 'hover', big = true, speed = 140 },
  { look = 1479, name = 'Dreamgorger', idle = 'hover', big = true, speed = 110 },
  { look = 1541, name = 'Dark Sorcerer', idle = 'idle', colors = { 133, 133, 133, 133 }, addons = 3, speed = 190 },
  { look = 1476, name = 'Grindmaw the Mauler', idle = 'idle', big = true, speed = 120 },
}

-- ground speed of each ground (the dat's ground attribute, server/data/items/dark_tiles.csv column "speed")
M.GROUND_SPEED = {
  [27484] = 100, [27485] = 100, [27486] = 120, [27487] = 120, [27488] = 120, [27489] = 120, [27490] = 130,
  [27491] = 100, [27492] = 100,
}
M.SERVER_BEAT = 50

-- one step's time in ms, as Creature::getStepDuration for a monster on 10.98 (no new speed law): 1000 * ground
-- speed / speed, rounded up to the server beat (a ground of speed 0 counts as 150), never below one beat
function M.stepDuration(groundSpeed, speed, beat)
  beat = beat or M.SERVER_BEAT
  if not speed or speed < 1 then return 0 end
  local gs = (groundSpeed and groundSpeed > 0) and groundSpeed or 150
  local interval = math.floor(1000 * gs / speed)
  interval = math.ceil(interval / beat) * beat
  return math.max(interval, beat)
end

function M.dirOf(dx, dy)
  if dx > 0 then return M.EAST elseif dx < 0 then return M.WEST elseif dy < 0 then return M.NORTH end
  return M.SOUTH
end

-- A creature on its patrol. path: { {x, y, ms = step time to reach this node, pause = ms to stand here}, ... },
-- walked as a cycle (the last node steps back to the first). update(dt) moves it on by dt ms and returns
-- x, y (tiles, fractional while stepping), the direction it faces, whether it is stepping, and the tile it is on
-- (tx, ty: while stepping already the one it steps to, as a walking creature on the map). dir: the facing before its
-- first step (south when left out).
function M.newWalker(path, startDelay, dir)
  local w = { path = path, i = 1, t = 0, stepping = false, wait = startDelay or path[1].pause or 0 }
  w.dir = dir or M.SOUTH
  function w.update(dt)
    local n = #w.path
    if n < 2 then
      local p = w.path[1]
      return p.x, p.y, w.dir, false, p.x, p.y
    end
    local left = dt
    while left > 0 do
      if not w.stepping then
        if w.wait > left then
          w.wait = w.wait - left
          left = 0
        else
          left = left - w.wait
          w.wait = 0
          w.stepping, w.t = true, 0
          local a, b = w.path[w.i], w.path[w.i % n + 1]
          w.dir = M.dirOf(b.x - a.x, b.y - a.y)
        end
      else
        local b = w.path[w.i % n + 1]
        local ms = math.max(1, b.ms or 500)
        if w.t + left < ms then
          w.t = w.t + left
          left = 0
        else
          left = left - (ms - w.t)
          w.i = w.i % n + 1
          w.stepping, w.t = false, 0
          w.wait = w.path[w.i].pause or 0
        end
      end
    end
    local a = w.path[w.i]
    if not w.stepping then return a.x, a.y, w.dir, false, a.x, a.y end
    local b = w.path[w.i % n + 1]
    local f = w.t / math.max(1, b.ms or 500)
    return a.x + (b.x - a.x) * f, a.y + (b.y - a.y) * f, w.dir, true, b.x, b.y
  end
  return w
end

M.NORTH, M.EAST, M.SOUTH, M.WEST = 0, 1, 2, 3

-- ---------------------------------------------------------------- random numbers
-- Park-Miller "minimal standard" generator: exact in doubles (products stay below 2^53), the same in Lua 5.1, LuaJIT
-- and 5.3, unlike math.random
function M.rng(seed)
  local s = math.floor(tonumber(seed) or 1) % 2147483647
  if s <= 0 then s = s + 2147483646 end
  local r = {}
  function r.next()
    s = (s * 16807) % 2147483647
    return s
  end
  function r.float() return (r.next() - 1) / 2147483646 end
  function r.int(a, b) return a + math.floor(r.float() * (b - a + 1)) end
  function r.chance(p) return r.float() < p end
  return r
end

-- ---------------------------------------------------------------- settings
M.MODES = { 'scene', 'art', 'alternate' }
M.MODE_LABEL = { scene = 'Living scene', art = 'Artwork', alternate = 'Scene and artwork' }

function M.mode(value)
  for _, m in ipairs(M.MODES) do
    if value == m then return m end
  end
  return 'scene'
end

function M.nextMode(value)
  local cur = M.mode(value)
  for i, m in ipairs(M.MODES) do
    if m == cur then return M.MODES[i % #M.MODES + 1] end
  end
  return 'scene'
end

-- 'alternate': the scene shows for `period` seconds, then the artwork for `period`, crossfading over `fade`
-- seconds. Returns the scene layer's opacity (1 = scene, 0 = artwork) at time t (seconds since the screen opened).
function M.alternateOpacity(t, period, fade)
  period = math.max(1, period or 40)
  fade = math.min(math.max(0, fade or 2), period)
  local p = t % (2 * period)
  local function ramp(x) return x <= 0 and 0 or (x >= 1 and 1 or x * x * (3 - 2 * x)) end
  if p < period then
    -- scene; the last `fade` seconds fade out
    if fade > 0 and p > period - fade then return 1 - ramp((p - (period - fade)) / fade) end
    return 1
  end
  p = p - period
  if fade > 0 and p > period - fade then return ramp((p - (period - fade)) / fade) end
  return 0
end

-- the tile size in pixels for a window: whole multiples of 32 (sprites stay crisp), about 11 rows tall
function M.tileSize(w, h)
  local k = math.floor(math.max(1, h) / 352)
  if k < 1 then k = 1 end
  if k > 4 then k = 4 end
  return 32 * k
end

-- ---------------------------------------------------------------- layout helpers
local function inRect(x, y, r)
  return x >= r[1] and x <= r[3] and y >= r[2] and y <= r[4]
end

local function blocked(x, y, keep)
  for _, r in ipairs(keep or {}) do
    if inRect(x, y, r) then return true end
  end
  return false
end

-- border pieces of family `fam` for the tile (x, y) whose own family is not `fam` (the sample scene's rule in
-- client/tools/sprites/gen_dark_tiles.py: a piece is named by where the family's ground lies)
function M.bordersAt(famAt, x, y, fam)
  if famAt(x, y) == fam then return {} end
  local n, s, w, e = famAt(x, y - 1) == fam, famAt(x, y + 1) == fam, famAt(x - 1, y) == fam, famAt(x + 1, y) == fam
  local pieces = {}
  if n and w then pieces[#pieces + 1] = 'inner_nw'
  elseif n and e then pieces[#pieces + 1] = 'inner_ne'
  elseif s and w then pieces[#pieces + 1] = 'inner_sw'
  elseif s and e then pieces[#pieces + 1] = 'inner_se'
  else
    if n then pieces[#pieces + 1] = 'n' end
    if s then pieces[#pieces + 1] = 's' end
    if w then pieces[#pieces + 1] = 'w' end
    if e then pieces[#pieces + 1] = 'e' end
    if not (n or w) and famAt(x - 1, y - 1) == fam then pieces[#pieces + 1] = 'outer_nw' end
    if not (n or e) and famAt(x + 1, y - 1) == fam then pieces[#pieces + 1] = 'outer_ne' end
    if not (s or w) and famAt(x - 1, y + 1) == fam then pieces[#pieces + 1] = 'outer_sw' end
    if not (s or e) and famAt(x + 1, y + 1) == fam then pieces[#pieces + 1] = 'outer_se' end
  end
  return pieces
end

function M.borderId(fam, piece)
  local first = M.BORDER_FIRST[fam]
  for i, p in ipairs(M.BORDER_PIECES) do
    if p == piece then return first + i - 1 end
  end
end

-- ---------------------------------------------------------------- the scene
-- cols x rows tiles (1-based, x right, y down). keep: tile rectangles {x0, y0, x1, y1} where no creature or tall
-- object goes (behind the logo and the sign-in panel). Returns
--   ground[y][x] = id, borders = { {x, y, id} }, things = { {kind = 'object' | 'wall' | 'creature', x, y, ...} }
--   sorted in drawing order (rows top to bottom), lights = { {x, y, kind} }, place = the caption
function M.layout(cols, rows, seed, keep)
  cols, rows = math.max(4, math.floor(cols)), math.max(4, math.floor(rows))
  local r = M.rng(seed or 1)
  local G = M.GROUND
  local ground = {}
  for y = 1, rows do
    ground[y] = {}
    for x = 1, cols do ground[y][x] = G.obsidian end
  end
  local function setG(x, y, id)
    if x >= 1 and x <= cols and y >= 1 and y <= rows then ground[y][x] = id end
  end
  local function blob(cx, cy, rx, ry, fn)
    for y = math.floor(cy - ry - 1), math.ceil(cy + ry + 1) do
      for x = math.floor(cx - rx - 1), math.ceil(cx + rx + 1) do
        local dx, dy = (x - cx) / rx, (y - cy) / ry
        if dx * dx + dy * dy <= 1 + (r.float() - 0.5) * 0.5 then fn(x, y) end
      end
    end
  end

  -- the courtyard: ash and bones in the middle third, from under the wall to the bottom, with a road of ruined
  -- flagstones up its middle to the wall
  local plazaX0, plazaX1 = math.floor(cols * 0.36) + 1, math.ceil(cols * 0.64)
  local plazaY0 = 4
  local roadX0 = math.floor((plazaX0 + plazaX1) / 2) - 1
  local roadX1 = roadX0 + 2
  -- ash patches with bones, a moss bed and a wet rock shelf on the sides, a magma vein, a cursed pool
  blob(cols * 0.16, rows * 0.62, math.max(2, cols * 0.11), math.max(2, rows * 0.2), function(x, y)
    setG(x, y, r.chance(0.3) and G.bones or G.ash)
  end)
  blob(cols * 0.86, rows * 0.72, math.max(2, cols * 0.1), math.max(2, rows * 0.18), function(x, y)
    setG(x, y, r.chance(0.25) and G.bones or G.ash)
  end)
  blob(cols * 0.9, rows * 0.32, math.max(2, cols * 0.08), math.max(1.5, rows * 0.14), function(x, y)
    setG(x, y, G.moss)
  end)
  blob(cols * 0.08, rows * 0.3, math.max(1.5, cols * 0.06), math.max(1.5, rows * 0.12), function(x, y)
    setG(x, y, r.chance(0.35) and G.mossyRock or G.wetRock)
  end)
  -- the vein: from the bottom edge up and to the left, wandering
  local vx = math.floor(cols * 0.3)
  for y = rows, 3, -1 do
    setG(vx, y, G.magma)
    if r.chance(0.45) then
      vx = vx + (r.chance(0.6) and -1 or 1)
      setG(vx, y, G.magma)
    end
    if vx < 2 then vx = 2 end
  end
  setG(math.floor(cols * 0.74), math.floor(rows * 0.5), G.pool)
  setG(math.floor(cols * 0.74) + 1, math.floor(rows * 0.5), G.pool)
  for y = plazaY0 - 1, rows do
    for x = plazaX0, plazaX1 do
      ground[y][x] = (x >= roadX0 and x <= roadX1) and G.ruined or (r.chance(0.25) and G.bones or G.ash)
    end
  end

  local function famAt(x, y)
    if x < 1 or x > cols or y < 1 or y > rows then
      -- outside the window: the ground continues as it is at the edge
      x = math.min(cols, math.max(1, x))
      y = math.min(rows, math.max(1, y))
    end
    return M.FAMILY[ground[y][x]]
  end
  local borders = {}
  for y = 1, rows do
    for x = 1, cols do
      for _, fam in ipairs(M.PATCH_FAMILIES) do
        for _, piece in ipairs(M.bordersAt(famAt, x, y, fam)) do
          borders[#borders + 1] = { x, y, M.borderId(fam, piece) }
        end
      end
    end
  end

  local things, lights = {}, {}
  local used = {}
  local function key(x, y) return y * 10000 + x end
  local function free(x, y, w, h)
    for yy = y - h + 1, y do
      for xx = x - w + 1, x do
        if xx < 1 or xx > cols or yy < 1 or yy > rows or used[key(xx, yy)] then return false end
      end
    end
    return true
  end
  local function take(x, y, w, h)
    for yy = y - h + 1, y do
      for xx = x - w + 1, x do used[key(xx, yy)] = true end
    end
  end
  local function object(name, x, y, opts)
    local o = M.OBJECT[name]
    if not o or not free(x, y, o[2], o[3]) then return false end
    if (o[3] > 1 or (opts and opts.keepOut)) and blocked(x, y, keep) then return false end
    take(x, y, o[2], o[3])
    things[#things + 1] = { kind = 'object', name = name, id = o[1], x = x, y = y, w = o[2], h = o[3] }
    if name == 'brazier' or name == 'torch' then lights[#lights + 1] = { x = x, y = y - 1, kind = 'fire' } end
    if name == 'glowcapPurple' or name == 'glowcapTeal' then lights[#lights + 1] = { x = x, y = y, kind = name } end
    return true
  end

  -- the wall along the top: a 2x2 wall piece on every tile of row 2 (it covers rows 1-2), ruined every third,
  -- an obsidian stretch on the right
  for x = 1, cols + 1 do
    local id = (x % 3 == 0) and M.WALL.ruined or M.WALL.dark
    if x > cols * 0.8 then id = M.WALL.obsidian end
    things[#things + 1] = { kind = 'wall', id = id, x = x, y = 2, w = 2, h = 2 }
    if x <= cols then used[key(x, 1)] = true; used[key(x, 2)] = true end
  end
  -- torches at the wall's foot, pillars along the road, braziers where it meets the wall
  for x = 3, cols - 2, math.max(4, math.floor(cols / 5)) do
    if x < plazaX0 - 1 or x > plazaX1 + 1 then object('torch', x, 4) end
  end
  for y = plazaY0 + 2, rows, 3 do
    object('pillar', roadX0 - 1, y)
    object('pillar', roadX1 + 1, y)
  end
  object('brazier', roadX0 - 1, plazaY0)
  object('brazier', roadX1 + 1, plazaY0)
  -- the wastes: trees and rocks at the sides, small things scattered by ground
  local big = { 'deadTree', 'twistedTree', 'outcrop', 'deadTree' }
  local tries = 0
  local placedBig = 0
  while placedBig < math.max(3, math.floor(cols * rows / 60)) and tries < 400 do
    tries = tries + 1
    local x = r.chance(0.5) and r.int(2, math.max(2, plazaX0 - 3)) or r.int(math.min(cols, plazaX1 + 3), cols)
    local y = r.int(5, rows)
    if object(big[(placedBig % #big) + 1], x, y) then placedBig = placedBig + 1 end
  end
  -- the monsters (before the small things, so they and their patrols get room): a necromancer with his risen dead
  -- on the left, the big ones and the spirits on the right, facing the courtyard
  local list = M.CREATURES
  local slots = {
    { 0.12, 0.6, 1 }, { 0.2, 0.72, 2 }, { 0.07, 0.8, 2 }, { 0.86, 0.62, 3 }, { 0.76, 0.42, 4 },
    { 0.28, 0.92, 5 }, { 0.92, 0.9, 6 }, { 0.22, 0.46, 7 }, { 0.68, 0.88, 8 },
  }
  for _, s in ipairs(slots) do
    local c = list[s[3]]
    local x0, y0 = math.floor(cols * s[1] + 0.5), math.floor(rows * s[2] + 0.5)
    local w = c.big and 2 or 1
    local done = false
    -- the slot's tile, else the nearest free one in growing rings around it
    for ring = 0, 6 do
      for dy = -ring, ring do
        for dx = -ring, ring do
          local x, y = x0 + dx, y0 + dy
          -- not on the outer columns or the bottom row: they hang over the window's edges
          if not done and math.max(math.abs(dx), math.abs(dy)) == ring and x >= w + 1 and x <= cols - 1 and y >= 4
              and y <= rows - 1 and free(x, y, w, w) and not blocked(x, y, keep) and not blocked(x - w + 1, y - w + 1, keep)
              and not blocked(x - w + 1, y, keep) and not blocked(x, y - w + 1, keep) and ground[y][x] ~= G.pool then
            take(x, y, w, w)
            local dir = x < cols / 2 and M.EAST or M.WEST
            if r.chance(0.3) then dir = M.SOUTH end
            things[#things + 1] = { kind = 'creature', x = x, y = y, w = w, h = w, look = c.look, name = c.name,
                                    idle = c.idle, colors = c.colors, addons = c.addons, dir = dir, speed = c.speed }
            done = true
          end
        end
      end
    end
  end

  -- patrols: each monster walks a few tiles back and forth along its row (or its column), or round a small loop,
  -- pausing at the turns. Every tile a patrol may cover is taken for it, so no two monsters ever meet and none walks
  -- through an object, onto the pool, behind the logo or the sign-in panel, or out of the scene. The outer column on
  -- each side and the bottom row hang over the window's edges (the grid is one tile bigger than the window), so
  -- neither a monster nor its patrol is ever on them. Two passes: first the shortest patrol of each monster's kind,
  -- so a crowded corner still gives everyone room to walk, then each one grows to the longest that still fits.
  local patrolOf = {}   -- tile -> the creature whose patrol covers it
  local function patrolFree(x, y, t)
    local w = t.w
    if x - w + 1 < 2 or x > cols - 1 or y - w + 1 < 4 or y > rows - 1 then return false end
    for yy = y - w + 1, y do
      for xx = x - w + 1, x do
        local k = key(xx, yy)
        local own = xx >= t.x - w + 1 and xx <= t.x and yy >= t.y - w + 1 and yy <= t.y
        if (used[k] and not own) or (patrolOf[k] and patrolOf[k] ~= t) or blocked(xx, yy, keep)
            or ground[yy][xx] == G.pool then
          return false
        end
      end
    end
    return true
  end
  local function nodesOf(t, c, flip)
    local nodes = {}
    if c.kind == 'line' then
      local dx, dy = c.dx * flip, c.dy * flip
      for i = 0, c.len do nodes[#nodes + 1] = { x = t.x + dx * i, y = t.y + dy * i } end
      for i = c.len - 1, 1, -1 do nodes[#nodes + 1] = { x = t.x + dx * i, y = t.y + dy * i } end
    else
      local x0, y0 = t.x, t.y
      for i = 0, c.a do nodes[#nodes + 1] = { x = x0 + c.sx * i, y = y0 } end
      for j = 1, c.b do nodes[#nodes + 1] = { x = x0 + c.sx * c.a, y = y0 + c.sy * j } end
      for i = c.a - 1, 0, -1 do nodes[#nodes + 1] = { x = x0 + c.sx * i, y = y0 + c.sy * c.b } end
      for j = c.b - 1, 1, -1 do nodes[#nodes + 1] = { x = x0, y = y0 + c.sy * j } end
    end
    nodes.kind = c.kind
    return nodes
  end
  local function fits(t, nodes)
    for _, nd in ipairs(nodes) do
      if not patrolFree(nd.x, nd.y, t) then return false end
    end
    return true
  end
  local function mark(t, nodes, who)
    for _, nd in ipairs(nodes) do
      for yy = nd.y - t.w + 1, nd.y do
        for xx = nd.x - t.w + 1, nd.x do patrolOf[key(xx, yy)] = who end
      end
    end
  end
  -- candidates, longest first: lines of 4 to 2 tiles along the row, 3 to 2 along the column, loops of 3x2 tiles
  local cands = {}
  for _, len in ipairs({ 4, 3, 2 }) do
    cands[#cands + 1] = { kind = 'line', dx = 1, dy = 0, len = len }
    cands[#cands + 1] = { kind = 'line', dx = -1, dy = 0, len = len }
  end
  for _, len in ipairs({ 3, 2 }) do
    cands[#cands + 1] = { kind = 'line', dx = 0, dy = 1, len = len }
    cands[#cands + 1] = { kind = 'line', dx = 0, dy = -1, len = len }
  end
  local LOOPS = #cands + 1
  cands[#cands + 1] = { kind = 'loop', sx = 1, sy = 1, a = 2, b = 1 }
  cands[#cands + 1] = { kind = 'loop', sx = -1, sy = 1, a = 2, b = 1 }
  cands[#cands + 1] = { kind = 'loop', sx = 1, sy = -1, a = 2, b = 1 }
  -- last resort where it is crowded: one tile out and back, along the row, else the column
  local ONE = #cands + 1
  cands[#cands + 1] = { kind = 'line', dx = 1, dy = 0, len = 1 }
  cands[#cands + 1] = { kind = 'line', dx = -1, dy = 0, len = 1 }
  cands[#cands + 1] = { kind = 'line', dx = 0, dy = 1, len = 1 }
  cands[#cands + 1] = { kind = 'line', dx = 0, dy = -1, len = 1 }
  local SHORT = { 5, 6, 9, 10, LOOPS, LOOPS + 1, LOOPS + 2, ONE, ONE + 1, ONE + 2, ONE + 3 }
  local walkers = {}
  for _, t in ipairs(things) do
    if t.kind == 'creature' then
      -- a loop for every third monster, else the longest free line; flip: which side it tries first
      walkers[#walkers + 1] = { t = t, loop = r.chance(0.34), flip = r.chance(0.5) and -1 or 1 }
    end
  end
  for _, wk in ipairs(walkers) do
    local order = {}
    if wk.loop then order = { LOOPS, LOOPS + 1, LOOPS + 2, 5, 6, 9, 10, ONE, ONE + 1, ONE + 2, ONE + 3 } else order = SHORT end
    for _, ci in ipairs(order) do
      local nodes = nodesOf(wk.t, cands[ci], wk.flip)
      if fits(wk.t, nodes) then
        wk.nodes = nodes
        mark(wk.t, nodes, wk.t)
        break
      end
    end
  end
  for _, wk in ipairs(walkers) do
    if wk.nodes then
      mark(wk.t, wk.nodes, nil)
      -- the loops first for a loop walker, else the lines longest first; a one-tile shuffle only if nothing else fits
      local first = wk.loop and LOOPS or 1
      for k = 0, ONE - 2 do
        local nodes = nodesOf(wk.t, cands[(first + k - 1) % (ONE - 1) + 1], wk.flip)
        if fits(wk.t, nodes) then
          wk.nodes = nodes
          break
        end
      end
      mark(wk.t, wk.nodes, wk.t)
    end
  end
  for _, wk in ipairs(walkers) do
    local t, tiles = wk.t, wk.nodes
    if tiles then
      local n = #tiles
      for i, nd in ipairs(tiles) do
        -- the step that reaches this node: the ground under the creature's own tile there
        nd.ms = M.stepDuration(M.GROUND_SPEED[ground[nd.y][nd.x]], t.speed)
        -- pauses at the turns (both ends of a line, one corner of a loop), 1.5 to 5 s
        local turn = (tiles.kind == 'line' and (i == 1 or i == math.floor(n / 2) + 1))
          or (tiles.kind == 'loop' and i == 1)
        nd.pause = turn and (1500 + r.int(0, 35) * 100) or 0
        -- taken: the small things scattered next keep off the patrols
        for yy = nd.y - t.w + 1, nd.y do
          for xx = nd.x - t.w + 1, nd.x do used[key(xx, yy)] = true end
        end
      end
      t.path = tiles
    end
  end

  local small = math.floor(cols * rows / 10)
  for _ = 1, small * 3 do
    if small <= 0 then break end
    local x, y = r.int(1, cols), r.int(4, rows)
    local g = ground[y][x]
    local name
    if g == G.ash or g == G.bones then
      name = r.chance(0.6) and 'bonePile' or (r.chance(0.5) and 'rubble' or 'deadBush')
    elseif g == G.moss then
      name = r.chance(0.5) and 'glowcapPurple' or 'glowcapTeal'
    elseif g == G.wetRock or g == G.mossyRock then
      name = r.chance(0.5) and 'boulder' or 'glowcapTeal'
    elseif g == G.ruined then
      name = r.chance(0.3) and 'rubble' or nil
    elseif g == G.obsidian then
      name = r.chance(0.35) and 'crystals' or (r.chance(0.75) and 'rubble' or 'boulder')
    end
    if name and r.chance(0.5) and object(name, x, y) then small = small - 1 end
  end
  -- lights over some of the magma
  for y = 1, rows do
    for x = 1, cols do
      if ground[y][x] == G.magma and r.chance(0.3) then lights[#lights + 1] = { x = x, y = y, kind = 'magma' } end
    end
  end

  -- drawing order: by row, then column; walls before what stands in the same row
  local order = { wall = 1, object = 2, creature = 3 }
  table.sort(things, function(a, b)
    if a.y ~= b.y then return a.y < b.y end
    if order[a.kind] ~= order[b.kind] then return order[a.kind] < order[b.kind] end
    return a.x < b.x
  end)
  return { cols = cols, rows = rows, ground = ground, borders = borders, things = things, lights = lights,
           place = 'THE CINDER OSSUARY' }
end

return M
