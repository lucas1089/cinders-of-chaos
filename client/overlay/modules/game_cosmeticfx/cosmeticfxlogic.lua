-- Footprints and outlines: the rules without client API (tested by cosmeticfxlogic_test.lua with luajit and lua5.3).
-- Who wears what comes from the server (cosmetics.lua "looks", forwarded by game_cosmetics); every client draws it.

CosmeticFxLogic = {}
local CF = CosmeticFxLogic

CF.PRINT_LIFE_MS = 3200   -- the pair picture (mode 'pairs', the Customise window's cards) fades out over this long
CF.PRINT_START = 0.9      -- its opacity when it is put down
CF.MAX_PRINTS = 160       -- at most this many marks on screen (the oldest goes first)
CF.MAX_PER_CREATURE = 8   -- and this many per walker (two marks a step: four tiles of trail)
CF.PREVIEW_MS = 6000      -- a store / window preview lasts this long
CF.PULSE_MS = 1800        -- a pulsing outline breathes once in this long
CF.PULSE_LOW = 0.45       -- its lowest opacity
CF.GLOW_TILES = 2         -- the glow picture (old engines only) covers this many tiles each way, centred on the creature
CF.PRINT_TILE = 0.9       -- the pair picture covers this much of a tile
CF.PZ_FLAG = 16384        -- PlayerStates.Pz of the local player: no new prints in a protection zone (crowded towns)

-- footprints under the feet (O499). Marks are placed in sprite pixels at 1x (32 to a tile, the unit of
-- foot_marks.lua); the module scales them to the drawing unit U of the widget it uses (map pixels for a floor widget).
CF.TILE_PX = 32
CF.FEET_FALLBACK = { 12, 19 }  -- a look the table does not know: stock look 128's feet (as CharSelectCore.FEET_FALLBACK)
CF.FEET_MIN, CF.FEET_MAX = -4, 36  -- a measured foot stays within a tile and a bit of the tile (a held weapon is no foot)
CF.LATERAL = 3            -- a foot is this many px (1x) left or right of the walker's line
CF.MARK_CANVAS = 48       -- the foot mark pictures are 48 x 48 (client/tools/gen_cosmeticfx_art.py)
CF.MARK_TILE = 0.67       -- a 64 px canvas of the picture covers this much of a tile: a mark picture is 0.5 tile wide (the print today: 1.8)
CF.STEP_MIN_MS, CF.STEP_MAX_MS = 60, 1500  -- the step time the schedule trusts (a bad value does not stall or flood)

-- how a step is drawn. at: when each mark is put down, as a share of the step time (the walker is then that far
-- along its way; a walk cycle plants a foot about 0.1 and 0.6 into a tile, the middle of each half is 0.25 / 0.75: 0.2
-- and 0.7 keeps the two marks half a tile apart and the first one just after the old tile's centre);
-- kind 'foot' draws images/marks/<art>_l / _r, one per foot, 'pair' draws images/prints/<art> once per step.
-- alpha: opacity of a fresh mark; life: ms; tint: image colour that darkens bright paint (nil: none); rankFade: how
-- much of the opacity the oldest of a walker's marks has lost against the newest, whatever its age (a fast walker's
-- trail still fades along its length).
CF.MODES = {
  pairs = { kind = 'pair', at = { 0.5 }, lateral = false, alpha = 0.9, life = 3200, maxPer = 4, rankFade = 0 },
  feet = { kind = 'foot', at = { 0.2, 0.7 }, lateral = true, alpha = 0.9, life = 2600, maxPer = 8, rankFade = 0.5 },
  soft = { kind = 'foot', at = { 0.2, 0.7 }, lateral = true, alpha = 0.6, life = 1800, maxPer = 6, rankFade = 0.5,
    tint = '#a0a0a0' },
}
CF.MODE = 'feet'          -- the mode in use (the owner chooses from the mock-up sheets, O499)

CF.DEFAULTS = { othersFootprints = true, othersOutlines = true }

-- ---------------------------------------------------------------- looks
local function validArt(s)
  return type(s) == 'string' and s:match('^[%w_]+$') ~= nil and #s <= 24
end
CF.validArt = validArt

-- one look from the server: {f = print art, o = glow art, p = 1 pulse}; nil when it carries nothing valid
function CF.cleanLook(v)
  if type(v) ~= 'table' then return nil end
  local out = { f = validArt(v.f) and v.f or nil, o = validArt(v.o) and v.o or nil, p = (v.p == 1 or v.p == true) or nil }
  if not out.f and not out.o then return nil end
  if not out.o then out.p = nil end
  return out
end

-- current = {[name] = look}; msg = {names, full}: a full list replaces, else entries are added (false removes one)
function CF.mergeLooks(current, msg)
  local out = {}
  if type(msg) ~= 'table' then return current or {} end
  if not msg.full then
    for k, v in pairs(current or {}) do out[k] = v end
  end
  for name, look in pairs(type(msg.names) == 'table' and msg.names or {}) do
    if type(name) == 'string' then out[name] = CF.cleanLook(look) end
  end
  return out
end

-- the look to draw for a player: the local player's preview wins while it lasts
function CF.lookOf(looks, name, isLocal, preview, now)
  if isLocal and preview and (now or 0) < (preview.untilMs or 0) then
    return preview.look
  end
  return looks and looks[name] or nil
end

-- may this be drawn? kind 'footprint' | 'outline'; settings = CF.DEFAULTS shape
function CF.allowed(kind, settings, isLocal)
  if isLocal then return true end
  settings = settings or CF.DEFAULTS
  if kind == 'footprint' then return settings.othersFootprints ~= false end
  return settings.othersOutlines ~= false
end

function CF.hasFlag(states, flag)
  states = tonumber(states) or 0
  return math.floor(states / flag) % 2 == 1
end

-- ---------------------------------------------------------------- steps
-- the rotation (degrees, north = 0, clockwise) of a step from a to b; nil unless it is one step on one floor
function CF.stepRotation(a, b)
  if type(a) ~= 'table' or type(b) ~= 'table' or a.z ~= b.z then return nil end
  local dx, dy = (b.x or 0) - (a.x or 0), (b.y or 0) - (a.y or 0)
  if (dx == 0 and dy == 0) or math.abs(dx) > 1 or math.abs(dy) > 1 then return nil end
  local deg = math.deg(math.atan2 and math.atan2(dx, -dy) or math.atan(dx, -dy))
  deg = math.floor(deg + 0.5) % 360
  return deg
end

-- the opacity of a print `age` ms old (nil: it is gone)
function CF.printOpacity(age)
  if age < 0 then age = 0 end
  if age >= CF.PRINT_LIFE_MS then return nil end
  return CF.PRINT_START * (1 - age / CF.PRINT_LIFE_MS)
end

-- the opacity of a pulsing outline at time t (ms)
function CF.pulseOpacity(t)
  local phase = (t % CF.PULSE_MS) / CF.PULSE_MS
  local wave = 0.5 - 0.5 * math.cos(phase * 2 * math.pi)
  return CF.PULSE_LOW + (1 - CF.PULSE_LOW) * wave
end

-- marks = list of {owner, born, ...} (oldest first). Returns the indexes to drop before `adding` more marks of `owner`
-- are added: the oldest of that owner past maxPer, then the oldest overall past MAX_PRINTS. maxPer defaults to
-- MAX_PER_CREATURE; a step of two marks asks with adding = 2 (or asks once per mark with 1: the same marks go).
function CF.evictions(prints, owner, adding, maxPer)
  adding = adding or 1
  maxPer = maxPer or CF.MAX_PER_CREATURE
  local drop, mine = {}, {}
  for i, p in ipairs(prints) do
    if p.owner == owner then mine[#mine + 1] = i end
  end
  local dropped = {}
  local over = #mine - (maxPer - adding)
  for k = 1, over do
    drop[#drop + 1] = mine[k]
    dropped[mine[k]] = true
  end
  local left = #prints - #drop
  local i = 1
  while left > CF.MAX_PRINTS - adding and i <= #prints do
    if not dropped[i] then
      drop[#drop + 1] = i
      dropped[i] = true
      left = left - 1
    end
    i = i + 1
  end
  table.sort(drop)
  return drop
end

-- the rank of every mark among its walker's marks: 0 the newest, 1 the one before, ... (marks oldest first)
function CF.ranks(marks)
  local count, out = {}, {}
  for i = #marks, 1, -1 do
    local o = marks[i].owner
    out[i] = count[o] or 0
    count[o] = out[i] + 1
  end
  return out
end

-- the opacity of a mark `age` ms old, `rank` among its walker's marks (nil: it is gone). The newest is strongest:
-- the age fades it, the rank takes up to rankFade of the rest away from the oldest of a full trail.
function CF.markOpacity(age, rank, mode)
  mode = mode or CF.MODES[CF.MODE]
  if age < 0 then age = 0 end
  if age >= mode.life then return nil end
  local top = math.max(1, mode.maxPer - 1)
  local share = 1 - mode.rankFade * math.min(rank or 0, top) / top
  return mode.alpha * (1 - age / mode.life) * share
end

-- the same event twice? The local player's position can change once on its pre-walk and once when the server confirms
-- the step: one step of one walker is one set of marks. last = {ox, oy, nx, ny, z, t} of the walker's previous step.
function CF.sameStep(last, oldPos, newPos, nowMs, stepMs)
  if type(last) ~= 'table' then return false end
  return last.ox == oldPos.x and last.oy == oldPos.y and last.nx == newPos.x and last.ny == newPos.y
    and last.z == newPos.z and (nowMs - last.t) < math.max(stepMs, 100)
end

-- is the walker still near where the step led, on the same floor? (a rubber band or a teleport moved it: the rest of
-- the step's marks are not put down; a walker that already took the next step is one tile on and still counts)
function CF.stillWalking(cur, newPos)
  if type(cur) ~= 'table' or type(newPos) ~= 'table' or cur.z ~= newPos.z then return false end
  return math.abs(cur.x - newPos.x) <= 1 and math.abs(cur.y - newPos.y) <= 1
end

-- ---------------------------------------------------------------- feet and marks (O499)
-- the direction a creature faces after a step (0 north, 1 east, 2 south, 3 west, as the pattern x of its look): a
-- diagonal step faces east or west
function CF.facing(dx, dy)
  if dx > 0 then return 1 end
  if dx < 0 then return 3 end
  if dy < 0 then return 0 end
  return 2
end

-- the thing whose feet stand on the ground: a mounted player stands on the mount
function CF.footThing(outfit)
  if type(outfit) ~= 'table' then return nil end
  local mount = tonumber(outfit.mount) or 0
  if mount > 0 then return mount end
  return tonumber(outfit.type)
end

-- the feet (x, y; px at 1x from the top left of the creature's own tile) of a look facing 0..3: from the generated
-- table foot_marks.lua ([look] = {nx, ny, ex, ey, sx, sy, wx, wy}), else the fallback; kept within CF.FEET_MIN..MAX
function CF.feetOf(table_, look, facing)
  local row = type(table_) == 'table' and look and table_[look] or nil
  local x, y = CF.FEET_FALLBACK[1], CF.FEET_FALLBACK[2]
  if type(row) == 'table' then
    local k = (math.max(0, math.min(3, facing or 2))) * 2 + 1
    if type(row[k]) == 'number' and type(row[k + 1]) == 'number' then x, y = row[k], row[k + 1] end
  end
  return math.max(CF.FEET_MIN, math.min(CF.FEET_MAX, x)), math.max(CF.FEET_MIN, math.min(CF.FEET_MAX, y))
end

-- the marks of one step (dx, dy in -1..1, not both 0) of a walker whose feet stand at (fx, fy) in its own tile.
-- parity: which foot comes first (0 left, 1 right); the walker alternates from one mark to the next, over steps.
-- Returns the list {at, tx, ty, px, py, side} and the parity for the next step:
--   at     when to put it down, a share of the step time (CF.MODES[..].at)
--   tx, ty the tile it lies on, from the old tile of the step (a foot is over the old tile, the new one, or a tile
--          beside them): the host of the mark
--   px, py its centre in that tile, px at 1x from the tile's top left (the walker is `at` of the way to its new tile;
--          the foot is its feet point there, moved to the side by CF.LATERAL: left or right of the walking line)
--   side   0 left foot, 1 right foot
function CF.stepMarks(dx, dy, fx, fy, parity, mode)
  mode = mode or CF.MODES[CF.MODE]
  local len = math.sqrt(dx * dx + dy * dy)
  if len == 0 then return {}, parity or 0 end
  parity = parity or 0
  local nx, ny = -dy / len, dx / len   -- to the walker's right (screen y points down)
  local out = {}
  for j, at in ipairs(mode.at) do
    local side = (parity + j - 1) % 2
    local lat = (not mode.lateral) and 0 or (side == 1 and CF.LATERAL or -CF.LATERAL)
    local x = fx + at * dx * CF.TILE_PX + lat * nx
    local y = fy + at * dy * CF.TILE_PX + lat * ny
    local tx, ty = math.floor(x / CF.TILE_PX), math.floor(y / CF.TILE_PX)
    out[#out + 1] = { at = at, tx = tx, ty = ty, px = x - tx * CF.TILE_PX, py = y - ty * CF.TILE_PX, side = side }
  end
  return out, (parity + #mode.at) % 2
end

-- the step time the schedule works with (ms)
function CF.stepTime(ms)
  ms = tonumber(ms) or 300
  return math.max(CF.STEP_MIN_MS, math.min(CF.STEP_MAX_MS, ms))
end

-- ---------------------------------------------------------------- sizes
-- the screen size of a tile of the map panel: visible dimension and rect; keepAspect = isKeepAspectRatioEnabled
function CF.tileSize(rectW, rectH, visW, visH, keepAspect)
  if not rectW or not visW or visW <= 0 or visH <= 0 then return 64, 64 end
  local w, h = rectW / visW, rectH / visH
  if keepAspect then
    local s = math.min(w, h)
    return s, s
  end
  return w, h
end

-- Drawing units. A floor widget (base patch 0078) is drawn inside the map's own pixel space, scaled with the zoom by
-- the map: U = the sprite size (32) per tile, whatever the screen size of a tile. Only the old Tile:setWidget fallback
-- draws in screen pixels (U = the screen size of a tile). The engine centres a tile widget on the tile's top-left plus
-- one sprite size, then moves it by its margins. O499: the first version took the screen size of a tile for a floor
-- widget too, so at 64 px tiles a print was 1.8 tiles wide and sat half a tile right and down of its tile.
--
-- the host: the widget on the tile that carries the marks (a floor widget holds one widget per tile, so it is a
-- plain container with the marks as its children). 3 x 3 tiles centred on its tile (a mark may lie on any of the
-- tile's neighbours' side of the tile), margins that centre it
function CF.hostBox(U, spr)
  U = U or 32
  spr = spr or 32
  local m = math.floor(U / 2 - spr + 0.5)
  return math.floor(3 * U + 0.5), m, m
end

-- a mark's size in drawing units: kind 'foot' a mark picture, 'pair' the pair picture
function CF.markSize(U, kind)
  if kind == 'pair' then return math.max(2, math.floor(U * CF.PRINT_TILE + 0.5)) end
  return math.max(2, math.floor(U * CF.MARK_TILE * CF.MARK_CANVAS / 64 + 0.5))
end

-- the margins that put a mark of `size` with its centre at (px, py) (px at 1x in the host's tile) inside the host box
function CF.markMargins(U, px, py, size)
  return math.floor(U + px * U / CF.TILE_PX - size / 2 + 0.5), math.floor(U + py * U / CF.TILE_PX - size / 2 + 0.5)
end

-- the screen size of a tile of the map panel: visible dimension and rect; keepAspect = isKeepAspectRatioEnabled
function CF.tileSize(rectW, rectH, visW, visH, keepAspect)
  if not rectW or not visW or visW <= 0 or visH <= 0 then return 64, 64 end
  local w, h = rectW / visW, rectH / visH
  if keepAspect then
    local s = math.min(w, h)
    return s, s
  end
  return w, h
end

-- a glow widget (map pixels: the engine draws creature widgets in the map's own coordinates)
function CF.glowSize(spriteSize)
  return (spriteSize or 32) * CF.GLOW_TILES
end

function CF.printPath(art)
  return '/modules/game_cosmeticfx/images/prints/' .. art
end

-- one foot's mark picture (side 0 left, 1 right)
function CF.markPath(art, side)
  return '/modules/game_cosmeticfx/images/marks/' .. art .. (side == 1 and '_r' or '_l')
end

-- the glow picture: only for a client whose engine has no outline pass (no Creature:setOutline, base patch 0038)
function CF.glowPath(art)
  return '/modules/game_cosmeticfx/images/glows/' .. art
end

-- ---------------------------------------------------------------- outlines (engine line, base patch 0038)
CF.OUTLINE_WIDTH = 2      -- sprite pixels (the engine scales it with the sprite size, so HD upscaling keeps the look)
CF.OUTLINE_ALPHA = 235    -- 0-255

-- art key (server cosmetics_config.lua `glows`) -> c = the colour at the feet, top = the colour at the top of the
-- silhouette (a vertical gradient; none = one colour). The pulse comes with the look (p), like the glows.
CF.OUTLINES = {
  gold = { c = { 255, 208, 64 } },
  crimson = { c = { 232, 52, 48 } },
  void = { c = { 160, 84, 236 } },
  frost = { c = { 128, 204, 255 } },
  verdant = { c = { 110, 228, 112 } },
  ember = { c = { 228, 48, 12 }, top = { 255, 214, 70 } },
  storm = { c = { 40, 96, 232 }, top = { 236, 250, 255 } },
  radiant = { c = { 255, 238, 150 } },
  abyssal = { c = { 128, 70, 216 } },
  absolute = { c = { 255, 210, 90 }, top = { 255, 255, 248 } },
  chronicle = { c = { 92, 204, 194 } },
  corona = { c = { 70, 20, 120 }, top = { 176, 96, 255 } },
  cinder = { c = { 230, 60, 0 }, top = { 255, 190, 60 } },
}

-- the engine call for a look's outline: {r, g, b, a, width, pulseMs, top = {r, g, b, a} | nil}; nil for an unknown art
function CF.outlineArgs(art, pulse)
  local spec = validArt(art) and CF.OUTLINES[art] or nil
  if not spec then return nil end
  local c = spec.c
  local out = { c[1], c[2], c[3], CF.OUTLINE_ALPHA, CF.OUTLINE_WIDTH, pulse and CF.PULSE_MS or 0 }
  if spec.top then
    out.top = { spec.top[1], spec.top[2], spec.top[3], CF.OUTLINE_ALPHA }
  end
  return out
end

-- does this engine draw outlines? (a creature of a client with base patch 0038 has setOutline; older ones do not,
-- and they keep the glow picture)
function CF.hasEngineOutline(creature)
  if creature == nil then return false end
  local ok, fn = pcall(function() return creature.setOutline end)
  return ok and type(fn) == 'function'
end
