-- Loot burst: the rules without client API (tested by lootburst_test.lua with luajit and lua5.3). O677, client/MANIFEST.md "Loot burst
-- (O677)", server/README.md "Loot explosion (O669)".
-- The server sends ONE message per kill on opcode 230 (action "explode", loot_explosion_core.lua X.explodePayload):
--   {o = [x, y, z] the death tile, k = kill id, f = [{id = client id, c = count, to = [x, y, z] the landing tile, d = ms until it leaves,
--    fl = ms of the flight, g = beam group "orange" | "divine" | "set" | "unique" or nil}, ...]}
-- and puts the real item on the landing tile exactly at d + fl. This file turns that into poses: where an item is `age` ms after the
-- message came (an arc: ease-out along the ground, gravity upwards, a pop of size), where its shadow is, the glows of its trail, what
-- happens where it lands and what the flash on the death tile looks like. The engine file lootburst.lua draws them as widgets.

LootBurstLogic = {}
local LBL = LootBurstLogic

LBL.TILE = 32           -- px of a tile in the art (the engine scales it to the tile on screen)
LBL.TICK_MS = 30        -- the animation steps about every 30 ms while a burst is on; nothing runs when none is
LBL.MAX_FLIGHTS = 14    -- the server's per-kill cap
LBL.MAX_FLIGHT_MS = 1500
LBL.MAX_DELAY_MS = 3000
LBL.MIN_FLIGHT_MS = 60
LBL.MAX_RADIUS = 3      -- tiles from the death tile (the server lands within 2)
LBL.HOLD_MS = 60        -- a flying item's widget stays this long after its flight ends: the real item is there from the flight's end
LBL.BOUNCE_MS = 60      -- the hop at the landing, inside the hold
LBL.BOUNCE = 0.15       -- the hop is this share of the arc's height
LBL.EFFECT_GRACE_MS = 700 -- the dust and the ring play this long after a landing
LBL.SAFETY_MS = 2500    -- a burst that is still on this long after its last effect should have ended is dropped (a stuck timer, a lost widget)
LBL.MAX_PER_TILE = 12   -- widgets a burst puts on one tile (the engine keeps 16 per tile and drops the oldest)

-- the art (client/tools/gen_lootburst_art.py SHEETS and its frame times; lootburst_test.lua reads the files against these numbers)
LBL.ART = {
  flash  = { w = 64, h = 64, frames = 8, ms = 45 },
  ring   = { w = 64, h = 40, frames = 6, ms = 60 },
  dust   = { w = 48, h = 48, frames = 6, ms = 55 },
  shadow = { w = 32, h = 20, frames = 1, ms = 0 },
  glow   = { w = 24, h = 24, frames = 1, ms = 0 },
}
LBL.ART_ORDER = { 'flash', 'ring', 'dust', 'shadow', 'glow' }

-- the beam group colours of game_lootbeams (LootBeamsLogic.GROUPS): the trail and the landing ring wear them; a plain item has none
LBL.COLORS = { orange = '#ff8c1a', divine = '#7fe3ff', set = '#c8e04a', unique = '#2bff7a' }
LBL.WARM = '#ffe6a8'   -- the flash of a kill that holds only plain items

-- the drama by group ('plain' is every item with no group, gold too). peak: the arc's height against the base rule (0.9 tile + 0.25 per
-- tile of distance); trail: glows behind it; ring: a ring where it lands; flash: the size of the flash on the death tile when the kill
-- starts (a plain kill 1.0); launch: a flash when this item itself leaves (the strongest one is the unique's); dust: the puff's size
LBL.STYLES = {
  plain  = { order = 0, peak = 0.6, trail = 0, ring = false, flash = 0.9, launch = 0, dust = 0.8 },
  orange = { order = 1, peak = 1.0, trail = 2, ring = true, ringSize = 0.9, flash = 1.1, launch = 0, dust = 1.0 },
  divine = { order = 2, peak = 1.15, trail = 3, ring = true, ringSize = 1.05, flash = 1.25, launch = 0, dust = 1.0 },
  set    = { order = 3, peak = 1.1, trail = 3, ring = true, ringSize = 1.0, flash = 1.2, launch = 0, dust = 1.0 },
  unique = { order = 4, peak = 1.3, trail = 4, ring = true, ringSize = 1.25, flash = 1.5, launch = 1.9, dust = 1.15 },
}

function LBL.styleOf(group)
  return LBL.STYLES[group] or LBL.STYLES.plain
end

-- ---------------------------------------------------------------- the message
local function int(v)
  v = tonumber(v)
  if not v or v ~= v or v == math.huge or v == -math.huge then return nil end
  return math.floor(v)
end

local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

local function pos3(p)
  if type(p) ~= 'table' then return nil end
  local x, y, z = int(p[1] or p.x), int(p[2] or p.y), int(p[3] or p.z)
  if not x or not y or not z then return nil end
  return { x = x, y = y, z = z }
end

-- the height of the arc's top in tiles for a distance and a group: 0.9 tile and 0.25 per tile of distance, times the group's share
function LBL.peak(dist, group)
  local d = math.max(1, tonumber(dist) or 1)
  return (0.9 + 0.25 * d) * LBL.styleOf(group).peak
end

-- a server "explode" message -> {origin, kill, flights = {{id, count, dx, dy, to, d, fl, group, dist, peak}, ...}, endMs, best} or nil.
-- Flights that are malformed, on another floor or farther than MAX_RADIUS are dropped; at most MAX_FLIGHTS are kept.
function LBL.parse(data)
  if type(data) ~= 'table' then return nil end
  local origin = pos3(data.o)
  if not origin or type(data.f) ~= 'table' then return nil end
  local flights, endMs, best = {}, 0, nil
  for _, e in ipairs(data.f) do
    if #flights >= LBL.MAX_FLIGHTS then break end
    if type(e) == 'table' then
      local to = pos3(e.to)
      local id = int(e.id)
      if to and id and id >= 1 and id <= 65535 and to.z == origin.z then
        local dx, dy = to.x - origin.x, to.y - origin.y
        if math.abs(dx) <= LBL.MAX_RADIUS and math.abs(dy) <= LBL.MAX_RADIUS then
          local group = LBL.COLORS[e.g] and e.g or nil
          local f = {
            id = id, count = clamp(int(e.c) or 1, 1, 65535), dx = dx, dy = dy, to = to,
            d = clamp(int(e.d) or 0, 0, LBL.MAX_DELAY_MS),
            fl = clamp(int(e.fl) or 0, LBL.MIN_FLIGHT_MS, LBL.MAX_FLIGHT_MS),
            group = group, dist = math.max(math.abs(dx), math.abs(dy)),
          }
          f.peak = LBL.peak(f.dist, group)
          f.landAt = f.d + f.fl
          f.endAt = f.landAt + LBL.HOLD_MS
          endMs = math.max(endMs, f.endAt + LBL.EFFECT_GRACE_MS)
          if not best or LBL.styleOf(group).order > LBL.styleOf(best).order then best = group or best end
          flights[#flights + 1] = f
        end
      end
    end
  end
  if #flights == 0 then return nil end
  return { origin = origin, kill = int(data.k), flights = flights, endMs = endMs, best = best }
end

-- ---------------------------------------------------------------- the arc
local function smooth(e0, e1, v)
  local t = clamp((v - e0) / (e1 - e0), 0, 1)
  return t * t * (3 - 2 * t)
end

-- the size of the item in the air against its resting size: a pop (small, up to 1.2 a third of the way, down to 1)
function LBL.popScale(t)
  t = clamp(tonumber(t) or 0, 0, 1)
  if t < 0.3 then return 0.55 + 0.65 * smooth(0, 0.3, t) end
  return 1.2 - 0.2 * (t - 0.3) / 0.7
end

-- the ground point and the height after a share t (0 .. 1) of the flight: ease-out along the ground, gravity upwards (a parabola in
-- time with its top, `peak` tiles, half way). Returns ex (share of the way along the ground), h (tiles above the ground)
function LBL.arc(t, peak)
  t = clamp(tonumber(t) or 0, 0, 1)
  local ex = 1 - (1 - t) * (1 - t)
  local h = 4 * peak * t * (1 - t)
  return ex, h
end

-- the pose of a flight `age` ms after the message came. phase: 'wait' (not left yet), 'fly', 'land' (the hop and the hold), 'done'.
-- x, y: the item's centre in tiles from the DEATH tile (y up is negative), gx, gy: the ground point under it, h: the height in tiles,
-- scale: the size against the resting one, shadow: {scale, alpha} of the soft ellipse under it
function LBL.pose(f, age)
  age = tonumber(age) or 0
  if age < f.d then return { phase = 'wait' } end
  local a = age - f.d
  if a >= f.fl + LBL.HOLD_MS then return { phase = 'done' } end
  if a < f.fl then
    local t = a / f.fl
    local ex, h = LBL.arc(t, f.peak)
    local gx, gy = f.dx * ex, f.dy * ex
    local lift = f.peak > 0 and h / f.peak or 0
    return { phase = 'fly', t = t, x = gx, y = gy - h, gx = gx, gy = gy, h = h, scale = LBL.popScale(t),
      shadow = { scale = 1 - 0.5 * lift, alpha = 0.55 * (1 - 0.45 * lift) * math.min(1, t / 0.12) } }
  end
  local b = a - f.fl
  local h = 0
  if b < LBL.BOUNCE_MS then
    local u = b / LBL.BOUNCE_MS
    h = f.peak * LBL.BOUNCE * 4 * u * (1 - u)
  end
  return { phase = 'land', t = 1, x = f.dx, y = f.dy - h, gx = f.dx, gy = f.dy, h = h, scale = 1,
    shadow = { scale = 1, alpha = 0.55 * math.max(0, 1 - b / LBL.HOLD_MS) } }
end

-- the glows behind a flying item: up to the group's trail count, each a step of the flight behind it, fainter and smaller. Only in the
-- air. Returns {{x, y, alpha, size}, ...} (tiles from the death tile, size against a tile)
function LBL.trail(f, age)
  local n = LBL.styleOf(f.group).trail
  local out = {}
  local a = (tonumber(age) or 0) - f.d
  if n <= 0 or a <= 0 or a >= f.fl then return out end
  local step = math.max(25, f.fl * 0.07)
  for k = 1, n do
    local at = a - k * step
    if at <= 0 then break end
    local ex, h = LBL.arc(at / f.fl, f.peak)
    out[#out + 1] = { x = f.dx * ex, y = f.dy * ex - h, alpha = 0.7 / k, size = 0.5 / (1 + 0.28 * (k - 1)) }
  end
  return out
end

-- what the landing of a flight sets off: a dust puff always, a ring (in the group's colour) for the groups that have one.
-- Returns {dust = size, ring = {color, size} or nil}
function LBL.landing(f)
  local s = LBL.styleOf(f.group)
  local out = { dust = s.dust }
  if s.ring and f.group then out.ring = { color = LBL.COLORS[f.group], size = s.ringSize } end
  return out
end

-- the flashes on the death tile: one when the kill starts (as big as the best group of the kill; in its colour), and one more where a
-- unique leaves (the strongest of all). Returns {{at, size, tint}, ...}
function LBL.flashes(burst)
  local best = burst.best
  local s = LBL.styleOf(best)
  local out = { { at = 0, size = s.flash, tint = best and LBL.COLORS[best] or LBL.WARM } }
  for _, f in ipairs(burst.flights) do
    local fs = LBL.styleOf(f.group)
    if fs.launch > 0 and #out < 3 then out[#out + 1] = { at = f.d, size = fs.launch, tint = LBL.COLORS[f.group] } end
  end
  return out
end

-- ---------------------------------------------------------------- frames, sizes, margins
-- the frame of a strip `age` ms after its start (0-based), or nil when it has played out
function LBL.frame(kind, age)
  local a = LBL.ART[kind]
  if not a or a.frames <= 1 then return 0 end
  age = tonumber(age) or 0
  if age < 0 then age = 0 end
  local i = math.floor(age / a.ms)
  if i >= a.frames then return nil end
  return i
end

function LBL.duration(kind)
  local a = LBL.ART[kind]
  return a and a.frames * a.ms or 0
end

function LBL.clip(kind, i)
  local a = LBL.ART[kind]
  return string.format('%d 0 %d %d', i * a.w, a.w, a.h)
end

function LBL.artPath(kind)
  if not LBL.ART[kind] then return nil end
  return '/modules/game_lootburst/images/' .. kind .. '.png'
end

-- the size in px of a picture of the art at a scale on a screen whose tile is tw x th px
function LBL.size(kind, scale, tw, th)
  local a = LBL.ART[kind]
  tw, th = tonumber(tw) or 64, tonumber(th) or 64
  if tw <= 0 then tw = 64 end
  if th <= 0 then th = 64 end
  scale = tonumber(scale) or 1
  return math.floor(a.w * tw / LBL.TILE * scale + 0.5), math.floor(a.h * th / LBL.TILE * scale + 0.5)
end

-- the margins that put the CENTRE of a widget on its tile's centre moved by (ox, oy) tiles. The engine centres a tile widget on its
-- tile's top left + spriteSize px (base patch 0041), so the margins that centre it are tile / 2 - spr (as game_lootbeams LB.box
-- does); spr = g_sprites.spriteSize(): 32, or 64 with HD Sprite Upscaling (default 32; seen in a client 2026-11-25, V8)
function LBL.margins(tw, th, ox, oy, spr)
  tw, th = tonumber(tw) or 64, tonumber(th) or 64
  spr = tonumber(spr) or 32
  if spr <= 0 then spr = 32 end
  return math.floor(tw / 2 - spr + (ox or 0) * tw + 0.5), math.floor(th / 2 - spr + (oy or 0) * th + 0.5)
end

-- widgets of a burst on one tile: the engine keeps 16 and drops the oldest, so a burst stops adding the extras (trail glows) at MAX_PER_TILE
function LBL.canAdd(counts, key, extra)
  local n = counts[key] or 0
  if extra and n >= LBL.MAX_PER_TILE then return false end
  return n < 15
end

function LBL.posKey(p)
  return p.x .. ',' .. p.y .. ',' .. p.z
end

-- ---------------------------------------------------------------- the settings
-- the option "Loot burst animation" (Ground Labels window) is a plain on / off, on by default; g_settings hands strings back
function LBL.enabledOf(v, default)
  if v == nil then return default ~= false end
  return v == true or v == 1 or v == '1' or v == 'true'
end

-- the capability message of the client: what the server must know (opcode 230 `burst {on}`)
function LBL.capability(enabled, capable)
  return { on = (enabled and capable) and 1 or 0 }
end
