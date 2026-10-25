-- game_chaosweather logic (client/MANIFEST.md "Weather on the client (O208)"): the message of the server, what to show, the
-- fades and the scroll of the rain pictures, with no engine calls so chaosweather_test.lua can run it. Time in ms.
--
-- The picture: three seamless tiles (tools/gen_rain_art.py) of thin slanted streaks. Each is the image of one widget that
-- fills the game map and repeats it; moving the image's rectangle by whole pixels every TICK_MS scrolls it down and to the
-- right, along the slant of the streaks. A level of rain shows some of the layers. The cost is those three widgets: a
-- handful of textured rectangles (maxQuads) and three setImageRect calls per tick, only while rain is visible.
ChaosWeatherLogic = {}
local L = ChaosWeatherLogic

L.OPCODE = 114                   -- server weather.lua, ChaosOpcodes.weather
L.TILE = 256                     -- the size of every rain tile (gen_rain_art.py SIZE)
L.SLANT = 0.30                   -- pixels right for each pixel down (gen_rain_art.py SLANT)
L.TICK_MS = 33                   -- the scroll step while rain is visible
L.COVER_MS = 400                 -- how often the player's tile is checked for a roof
L.COVERED_FADE_MS = 600          -- the rain fades this fast (at most) when the player steps under a roof
L.DEFAULT_FADE_MS = 2500
L.MAX_FADE_MS = 10000
L.MIN_OPACITY = 0.01             -- below this a layer is hidden
L.IMAGES = '/modules/game_chaosweather/images/'

-- the layers, back to front; speed in pixels per second (down)
L.LAYERS = {
  { name = 'far',  image = 'rain_far',  speed = 360, phase = 0 },
  { name = 'mid',  image = 'rain_mid',  speed = 480, phase = 83 },
  { name = 'near', image = 'rain_near', speed = 640, phase = 171 },
}
L.MAX_LEVEL = 3
-- what each level of rain shows: the opacity of every layer it uses. 2 is the level of the base server's rain.
L.PLAN = {
  [1] = { far = 0.6 },
  [2] = { far = 1, near = 1 },
  [3] = { far = 1, mid = 1, near = 1 },
}

-- the option (Options > Graphics "Rain and weather", dataset.lua `weather`): on unless it is the boolean false
function L.optionOn(value)
  return value ~= false
end

-- The message of the server: {action = 'set', data = {k = 'rain' | 'none', i = 1..3, f = fade ms}}. Returns
-- {kind = 'rain' | 'none', level = 0..3, fadeMs} or nil for anything else. A level out of range is clamped; an unknown kind
-- is "none" (a later server may send snow: an old client shows nothing).
function L.parse(msg)
  if type(msg) ~= 'table' or msg.action ~= 'set' or type(msg.data) ~= 'table' then return nil end
  local d = msg.data
  local fade = tonumber(d.f)
  if not fade or fade ~= fade then fade = L.DEFAULT_FADE_MS end
  fade = math.max(0, math.min(L.MAX_FADE_MS, math.floor(fade)))
  if d.k == 'rain' then
    local level = tonumber(d.i) or 2
    level = math.max(1, math.min(L.MAX_LEVEL, math.floor(level)))
    return { kind = 'rain', level = level, fadeMs = fade }
  end
  return { kind = 'none', level = 0, fadeMs = fade }
end

-- the opacity every layer should reach; all 0 when it does not rain, the option is off or the player is under a roof
function L.targets(weather, optionOn, covered)
  local t = {}
  for _, layer in ipairs(L.LAYERS) do t[layer.name] = 0 end
  if not optionOn or covered or not weather or weather.kind ~= 'rain' then return t end
  local plan = L.PLAN[weather.level] or L.PLAN[2]
  for name, opacity in pairs(plan) do t[name] = opacity end
  return t
end

-- the fade (ms for a full 0 -> 1) to use now: the server's, but quick under a roof
function L.fadeMs(weather, covered)
  local ms = weather and weather.fadeMs or L.DEFAULT_FADE_MS
  if covered then ms = math.min(ms, L.COVERED_FADE_MS) end
  return ms
end

-- one step of a fade: `cur` moves toward `tgt` by dtMs / fadeMs of the full range; fadeMs 0 jumps
function L.step(cur, tgt, dtMs, fadeMs)
  if fadeMs <= 0 or dtMs >= fadeMs then return tgt end
  local delta = dtMs / fadeMs
  if cur < tgt then return math.min(tgt, cur + delta) end
  return math.max(tgt, cur - delta)
end

-- steps every layer; returns whether any is still visible (the timer runs while it is)
function L.stepAll(cur, tgt, dtMs, fadeMs)
  local any = false
  for _, layer in ipairs(L.LAYERS) do
    local v = L.step(cur[layer.name] or 0, tgt[layer.name] or 0, dtMs, fadeMs)
    cur[layer.name] = v
    if v > L.MIN_OPACITY then any = true end
  end
  return any
end

function L.newOpacities()
  local c = {}
  for _, layer in ipairs(L.LAYERS) do c[layer.name] = 0 end
  return c
end

-- true when something is visible now or still has to fade to a target
function L.busy(cur, tgt)
  for _, layer in ipairs(L.LAYERS) do
    local c, t = cur[layer.name] or 0, tgt[layer.name] or 0
    if c > L.MIN_OPACITY or t > L.MIN_OPACITY then return true end
  end
  return false
end

-- where the tile starts for a layer at a time (ms since the rain widgets were made): whole pixels, 0 .. TILE - 1 each way.
-- The picture repeats every TILE both ways, so the wrap of each coordinate shows no jump.
function L.offset(layer, tMs)
  local d = math.floor(layer.speed * tMs / 1000)
  return (math.floor(d * L.SLANT) + layer.phase) % L.TILE, (d + layer.phase) % L.TILE
end

-- the image rectangle that fills a w x h widget for an offset: it starts a tile before the offset, so the repeated tiles
-- cover the whole widget (the engine clips the part outside)
function L.imageRect(ox, oy, w, h)
  return { x = ox - L.TILE, y = oy - L.TILE, width = w + L.TILE, height = h + L.TILE }
end

-- O235: what was last handed to every widget, so a tick calls setImageRect / setOpacity only for a value that changed (the
-- scroll of the rain moves the rectangle every tick, but a steady opacity and a still window do not need a call each time).
-- rect(name, r) and opacity(name, o) return true when the value differs from the last one given for that name (and remember
-- it); forget(name) / reset() when the widget was hidden or remade, so the next value always goes through.
function L.newPaint()
  local rects, ops = {}, {}
  local P = {}
  function P.rect(name, r)
    local l = rects[name]
    if l and l.x == r.x and l.y == r.y and l.width == r.width and l.height == r.height then return false end
    rects[name] = { x = r.x, y = r.y, width = r.width, height = r.height }
    return true
  end
  function P.opacity(name, o)
    if ops[name] == o then return false end
    ops[name] = o
    return true
  end
  function P.forget(name) rects[name], ops[name] = nil, nil end
  function P.reset() rects, ops = {}, {} end
  return P
end

-- the most textured rectangles the layers draw on a w x h game window: the cap of the drawing
function L.maxQuads(w, h)
  local per = (math.ceil((w + L.TILE) / L.TILE) + 1) * (math.ceil((h + L.TILE) / L.TILE) + 1)
  return per * #L.LAYERS
end
