-- Combat decals: the rules without client API (tested by combatdecals_test.lua with luajit and lua5.3).
-- A blood stain where a creature dies; a scorch mark under a fire hit, frost cracks under an ice hit, a green stain
-- under poison or earth. Each fades out over 20-30 s, at most MAX are alive, only on screen.

CombatDecalsLogic = {}
local CD = CombatDecalsLogic

CD.MAX = 24              -- decals alive at once; a death stain pushes the oldest out, a hit stain waits for room
CD.LIFE_MIN_MS = 20000   -- a decal lasts this long at least ...
CD.LIFE_MAX_MS = 30000   -- ... and this long at most (drawn per decal)
CD.START = 0.8           -- opacity when it is put down
CD.HOLD = 0.2            -- the first fifth of the life stays at START, then it fades out
CD.TICK_MS = 100         -- the fade timer (runs only while a decal is alive)
CD.HIT_GAP_MS = 250      -- a new hit stain at most this often (a spray of hits is one stain)
CD.TILE = 1.0            -- a decal covers this much of a tile
CD.VARIANTS = 2          -- pictures per kind
CD.SPREAD = 2            -- a death stain may lie on one of this many tiles next to the creature when its own is taken

CD.DEFAULTS = { combatDecals = true }

-- Otc::MessageMode of g_map.onImpactText (same numbers as game_visualfx's L.MODE) and the number types of the server
-- (ChaosImpactType): plain, critical hits and damage-over-time ticks leave a stain; mana and shield numbers do not
CD.MODE = { DAMAGE_DEALT = 21, DAMAGE_RECEIVED = 22, DAMAGE_OTHERS = 25 }
CD.TYPE = { NORMAL = 0, CRITICAL = 1, CONDITION = 2 }

-- an option value from the settings: a boolean is kept, anything else (nil, junk, an older settings file) is the default
function CD.optionOn(value)
  if type(value) == 'boolean' then return value end
  return CD.DEFAULTS.combatDecals == true
end

-- ---------------------------------------------------------------- which decal
-- The damage number has no element, only a colour (the server's combat colour of the hit: g_map.onImpactText gets the
-- AnimatedText, whose getColor() is that colour). The 8-bit palette colours of the hits are orange for fire, cyan for
-- ice, green for earth / poison, red for physical, purple for energy, blue for drowning. So the hue tells the element:
-- 15-55 degrees fire, 80-160 poison / earth, 165-200 ice; everything else (red, blue, purple, grey, white) none.
CD.HUE = { fire = { 15, 55 }, poison = { 80, 160 }, ice = { 165, 200 } }
CD.MIN_SAT = 0.45
CD.MIN_VALUE = 90        -- of 255: dark colours say nothing

-- r, g, b (0-255) of a colour as the Lua side gets it: "#rrggbb[aa]", a table {r, g, b} or {r =, g =, b =}
-- (fields 0-255, or all 0-1), or an object with r / g / b fields; nil when it is none of these
function CD.rgbOf(color)
  if type(color) == 'string' then
    local h = color:match('^#(%x%x%x%x%x%x)%x?%x?$')
    if not h then return nil end
    return tonumber(h:sub(1, 2), 16), tonumber(h:sub(3, 4), 16), tonumber(h:sub(5, 6), 16)
  end
  local ok, r, g, b = pcall(function()
    local x, y, z = color.r or color[1], color.g or color[2], color.b or color[3]
    return x, y, z
  end)
  if not ok then return nil end
  r, g, b = tonumber(r), tonumber(g), tonumber(b)
  if not r or not g or not b then return nil end
  if r <= 1 and g <= 1 and b <= 1 then r, g, b = r * 255, g * 255, b * 255 end
  return r, g, b
end

-- hue (degrees 0-360), saturation (0-1), value (0-255); nil for a grey
local function hsv(r, g, b)
  local mx, mn = math.max(r, g, b), math.min(r, g, b)
  local d = mx - mn
  if mx <= 0 or d <= 0 then return nil end
  local h
  if mx == r then
    h = ((g - b) / d) % 6
  elseif mx == g then
    h = (b - r) / d + 2
  else
    h = (r - g) / d + 4
  end
  return h * 60, d / mx, mx
end

-- 'fire' | 'ice' | 'poison' for the colour of a damage number; nil for the rest
function CD.kindOfColor(color)
  local r, g, b = CD.rgbOf(color)
  if not r then return nil end
  local h, s, v = hsv(r, g, b)
  if not h or s < CD.MIN_SAT or v < CD.MIN_VALUE then return nil end
  for kind, range in pairs(CD.HUE) do
    if h >= range[1] and h <= range[2] then return kind end
  end
  return nil
end

-- the decal a damage number asks for, or nil: only damage numbers (mode), of a plain, critical or tick type, with a
-- value, that name an element by colour
function CD.hitKind(mode, typeId, value, color)
  local M = CD.MODE
  if mode ~= M.DAMAGE_DEALT and mode ~= M.DAMAGE_RECEIVED and mode ~= M.DAMAGE_OTHERS then return nil end
  typeId = tonumber(typeId) or 0
  if typeId ~= CD.TYPE.NORMAL and typeId ~= CD.TYPE.CRITICAL and typeId ~= CD.TYPE.CONDITION then return nil end
  if (tonumber(value) or 0) <= 0 then return nil end
  return CD.kindOfColor(color)
end

-- Creatures that bleed no red: a cheap guess from the name, the client knows no blood type. Substrings, lower case.
CD.BLOODLESS = {
  'skeleton', 'bonelord', 'ghost', 'spectre', 'wraith', 'banshee', 'lich', 'mummy', 'golem', 'elemental', 'slime',
  'ooze', 'construct', 'statue', 'phantom', 'shade', 'djinn', 'wisp', 'revenant', 'undead', 'bone',
}

function CD.bleeds(name)
  if type(name) ~= 'string' or name == '' then return true end
  local lower = name:lower()
  for _, part in ipairs(CD.BLOODLESS) do
    if lower:find(part, 1, true) then return false end
  end
  return true
end

-- ---------------------------------------------------------------- state
-- state = CD.newState(): {decals = {...oldest first}, lastHit = ms}
function CD.newState()
  return { decals = {}, lastHit = -1e9 }
end

-- the length of one decal's life, from a random number in [0, 1)
function CD.lifeFor(rnd)
  rnd = tonumber(rnd) or 0
  if rnd < 0 then rnd = 0 elseif rnd >= 1 then rnd = 0.999999 end
  return math.floor(CD.LIFE_MIN_MS + (CD.LIFE_MAX_MS - CD.LIFE_MIN_MS) * rnd)
end

-- the opacity `age` ms into a life of `life` ms (nil: it is gone). Holds at START, then falls to 0 (smoothstep).
function CD.alphaAt(age, life)
  if not life or life <= 0 then return nil end
  if age < 0 then age = 0 end
  if age >= life then return nil end
  local hold = life * CD.HOLD
  if age <= hold then return CD.START end
  local u = (age - hold) / (life - hold)
  return CD.START * (1 - u * u * (3 - 2 * u))
end

-- may a new decal of this kind be put down now? A death stain always may (it pushes the oldest out); a hit stain only
-- with room and after the gap since the last one
function CD.mayAdd(state, kind, now)
  if kind == 'blood' then return true end
  if #state.decals >= CD.MAX then return false end
  return now - state.lastHit >= CD.HIT_GAP_MS
end

-- the indexes (of state.decals) to drop before one more is added: the oldest past MAX - 1
function CD.evictions(state)
  local drop = {}
  for i = 1, #state.decals - (CD.MAX - 1) do drop[#drop + 1] = i end
  return drop
end

-- records a decal that was put down (the caller made the widget); `entry` = {kind, born, life, ...}
function CD.add(state, entry)
  state.decals[#state.decals + 1] = entry
  if entry.kind ~= 'blood' then state.lastHit = entry.born end
end

-- the entries still alive at `now`, each with its opacity; returns alive, expired (lists, order kept)
function CD.step(state, now)
  local alive, gone = {}, {}
  for _, d in ipairs(state.decals) do
    local a = CD.alphaAt(now - d.born, d.life)
    if a then
      d.alpha = a
      alive[#alive + 1] = d
    else
      gone[#gone + 1] = d
    end
  end
  state.decals = alive
  return alive, gone
end

-- ---------------------------------------------------------------- where
-- is `pos` on the screen of a map of vw x vh tiles centred on `center`? Same floor only.
function CD.onScreen(pos, center, vw, vh)
  if type(pos) ~= 'table' or type(center) ~= 'table' or pos.z ~= center.z then return false end
  vw, vh = tonumber(vw) or 0, tonumber(vh) or 0
  if vw <= 0 or vh <= 0 then return false end
  return math.abs(pos.x - center.x) <= math.floor(vw / 2) and math.abs(pos.y - center.y) <= math.floor(vh / 2)
end

-- the tile for a stain: `pos` itself when `free(p)` says so; a death stain (spread > 0) tries up to `spread` of the
-- eight neighbours in an order drawn with rnd() when its own tile is taken. Returns a new position table or nil.
local NEIGHBOURS = { { 0, -1 }, { 1, 0 }, { 0, 1 }, { -1, 0 }, { 1, -1 }, { 1, 1 }, { -1, 1 }, { -1, -1 } }
function CD.pickTile(pos, free, spread, rnd)
  if free(pos) then return { x = pos.x, y = pos.y, z = pos.z } end
  spread = tonumber(spread) or 0
  if spread <= 0 then return nil end
  local start = math.floor((rnd and rnd() or 0) * #NEIGHBOURS) % #NEIGHBOURS
  for k = 0, #NEIGHBOURS - 1 do
    if k >= spread * 4 then break end -- a few tries only: the cost stays small
    local n = NEIGHBOURS[(start + k) % #NEIGHBOURS + 1]
    local p = { x = pos.x + n[1], y = pos.y + n[2], z = pos.z }
    if free(p) then return p end
  end
  return nil
end

-- ---------------------------------------------------------------- pictures
-- the screen size of a tile of the map panel (rect and visible dimension of the panel)
function CD.tileSize(rectW, rectH, visW, visH, keepAspect)
  if not rectW or not visW or visW <= 0 or visH <= 0 then return 64, 64 end
  local w, h = rectW / visW, rectH / visH
  if keepAspect then
    local s = math.min(w, h)
    return s, s
  end
  return w, h
end

-- size and the margins that centre a decal on its tile (the engine centres a tile widget on the tile's top-left plus
-- one sprite size, in screen pixels: the rule of the footprints of game_cosmeticfx)
function CD.box(tileW, tileH, spriteSize)
  local size = math.floor(math.min(tileW, tileH) * CD.TILE + 0.5)
  local spr = spriteSize or 32
  return size, math.floor(tileW / 2 - spr + 0.5), math.floor(tileH / 2 - spr + 0.5)
end

CD.KINDS = { blood = true, fire = true, ice = true, poison = true }
CD.ART = { blood = 'blood', fire = 'scorch', ice = 'frost', poison = 'stain' }

-- the picture of a kind and variant (1..VARIANTS); client/tools/gen_decal_art.py draws them
function CD.path(kind, variant)
  local art = CD.ART[kind]
  if not art then return nil end
  variant = math.floor(tonumber(variant) or 1)
  if variant < 1 or variant > CD.VARIANTS then variant = 1 end
  return '/modules/game_combatdecals/images/' .. art .. variant
end

-- a random rotation, a quarter turn at a time (degrees)
function CD.rotation(rnd)
  return (math.floor((rnd or 0) * 4) % 4) * 90
end
