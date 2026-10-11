-- Footprints and outlines: the rules without client API (tested by cosmeticfxlogic_test.lua with luajit and lua5.3).
-- Who wears what comes from the server (cosmetics.lua "looks", forwarded by game_cosmetics); every client draws it.

CosmeticFxLogic = {}
local CF = CosmeticFxLogic

CF.PRINT_LIFE_MS = 3200   -- a print fades out over this long
CF.PRINT_START = 0.9      -- its opacity when it is put down
CF.MAX_PRINTS = 160       -- at most this many prints on screen (the oldest goes first)
CF.MAX_PER_CREATURE = 8   -- and this many per walker
CF.PREVIEW_MS = 6000      -- a store / window preview lasts this long
CF.PULSE_MS = 1800        -- a pulsing outline breathes once in this long
CF.PULSE_LOW = 0.45       -- its lowest opacity
CF.GLOW_TILES = 2         -- the glow picture covers this many tiles each way, centred on the creature
CF.PRINT_TILE = 0.9       -- a print covers this much of a tile
CF.PZ_FLAG = 16384        -- PlayerStates.Pz of the local player: no new prints in a protection zone (crowded towns)

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

-- prints = list of {id, owner, born} (oldest first). Returns the indexes to drop before one more print of `owner` is
-- added: the oldest of that owner past MAX_PER_CREATURE, then the oldest overall past MAX_PRINTS.
function CF.evictions(prints, owner)
  local drop, mine = {}, {}
  for i, p in ipairs(prints) do
    if p.owner == owner then mine[#mine + 1] = i end
  end
  local dropped = {}
  local over = #mine - (CF.MAX_PER_CREATURE - 1)
  for k = 1, over do
    drop[#drop + 1] = mine[k]
    dropped[mine[k]] = true
  end
  local left = #prints - #drop
  local i = 1
  while left >= CF.MAX_PRINTS and i <= #prints do
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

-- a print widget: size and the margins that centre it on its tile (the engine centres a tile widget on the tile's
-- top-left + one sprite size, in screen pixels)
function CF.printBox(tileW, tileH, spriteSize)
  local size = math.floor(math.min(tileW, tileH) * CF.PRINT_TILE + 0.5)
  local spr = spriteSize or 32
  return size, math.floor(tileW / 2 - spr + 0.5), math.floor(tileH / 2 - spr + 0.5)
end

-- a glow widget (map pixels: the engine draws creature widgets in the map's own coordinates)
function CF.glowSize(spriteSize)
  return (spriteSize or 32) * CF.GLOW_TILES
end

function CF.printPath(art)
  return '/modules/game_cosmeticfx/images/prints/' .. art
end

function CF.glowPath(art)
  return '/modules/game_cosmeticfx/images/glows/' .. art
end
