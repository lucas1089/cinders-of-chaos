-- game_chaosweather, ambient particles (O226; client/MANIFEST.md "Ambient particles (O226)"): the mood of the place, which
-- layers show, the fades and the slow drift of the specks, with no engine calls so chaosambient_test.lua can run it. Time in ms.
--
-- The server (weather.lua) adds a = 'embers' | 'motes' | 'dust' to its set message in a region with a mood. The picture is
-- the same trick as the rain: seamless tiles (tools/gen_ambient_art.py) of sparse specks, one repeated-image widget per layer
-- over the game map, whose image rectangle moves by whole pixels every TICK_MS. A kind uses two layers (far, near), so the
-- cost is two widgets and two setImageRect calls per tick, and only while a mood is visible. The number of specks is the art:
-- L.ART counts them per tile.
ChaosAmbientLogic = {}
local A = ChaosAmbientLogic

A.TILE = 512                      -- the size of every tile (gen_ambient_art.py SIZE)
A.TICK_MS = 50                    -- the drift step while a mood is visible (slow specks: under 1.5 pixels a step)
A.HIDDEN_POLL_MS = 1000           -- while the window is hidden nothing is drawn; this is how often it is looked at again
A.DEFAULT_FADE_MS = 2500
A.MAX_FADE_MS = 10000
A.MIN_OPACITY = 0.01              -- below this a layer is hidden
A.IMAGES = '/modules/game_chaosweather/images/'
A.KINDS = { embers = true, motes = true, dust = true }

-- the layers, back to front. Drift: vx, vy in pixels per second; sway and swayY in pixels, period in ms (a sine on top, so the
-- specks wander instead of sliding in a line); pulse = how deep the twinkle goes (0 none), pulseMs its period; max = opacity.
A.LAYERS = {
  { name = 'embers_far',  kind = 'embers', image = 'ember_far',  vx = 5,  vy = -13, sway = 10, swayY = 3, period = 5200, phase = 0,   pulse = 0.15, pulseMs = 1700, max = 0.9 },
  { name = 'embers_near', kind = 'embers', image = 'ember_near', vx = 9,  vy = -24, sway = 16, swayY = 4, period = 3800, phase = 97,  pulse = 0.20, pulseMs = 1300, max = 1 },
  { name = 'motes_far',   kind = 'motes',  image = 'mote_far',   vx = 3,  vy = -3,  sway = 14, swayY = 9, period = 7000, phase = 41,  pulse = 0.60, pulseMs = 4700, max = 0.9 },
  { name = 'motes_near',  kind = 'motes',  image = 'mote_near',  vx = -4, vy = 2,   sway = 22, swayY = 12, period = 5600, phase = 211, pulse = 0.70, pulseMs = 3300, max = 1 },
  { name = 'dust_far',    kind = 'dust',   image = 'dust_far',   vx = 3,  vy = 2,   sway = 8,  swayY = 5, period = 9000, phase = 133, pulse = 0,    pulseMs = 1000, max = 0.8 },
  { name = 'dust_near',   kind = 'dust',   image = 'dust_near',  vx = 6,  vy = 4,   sway = 12, swayY = 7, period = 7400, phase = 301, pulse = 0,    pulseMs = 1000, max = 0.9 },
}
-- the specks in one tile of each layer (gen_ambient_art.py COUNTS; the test compares them): the cap of the effect
A.ART = { embers_far = 12, embers_near = 5, motes_far = 9, motes_near = 4, dust_far = 16, dust_near = 6 }
A.MAX_SPECKS_PER_TILE = 24        -- the most any one kind shows in a tile (its two layers together)

-- the option (Options > Graphics "Ambient particles", dataset.lua `ambientParticles`): on unless it is the boolean false
function A.optionOn(value)
  return value ~= false
end

-- the kind of a set message of the server ({action = 'set', data = {a = ...}}): 'embers' | 'motes' | 'dust', or nil for no mood.
-- An unknown name (a later server) and a message of another action show nothing.
function A.parseKind(msg)
  if type(msg) ~= 'table' or msg.action ~= 'set' or type(msg.data) ~= 'table' then return nil end
  local a = msg.data.a
  if type(a) == 'string' and A.KINDS[a] then return a end
  return nil
end

-- the fade of the message in ms, like the rain's
function A.parseFade(msg)
  local d = type(msg) == 'table' and type(msg.data) == 'table' and msg.data or {}
  local fade = tonumber(d.f)
  if not fade or fade ~= fade then fade = A.DEFAULT_FADE_MS end
  return math.max(0, math.min(A.MAX_FADE_MS, math.floor(fade)))
end

function A.newOpacities()
  local c = {}
  for _, layer in ipairs(A.LAYERS) do c[layer.name] = 0 end
  return c
end

-- the opacity every layer should reach: the layers of the current kind at their max, all others 0; all 0 when the option is
-- off or the window is hidden
function A.targets(kind, optionOn, windowVisible)
  local t = A.newOpacities()
  if not optionOn or not windowVisible or not A.KINDS[kind or ''] then return t end
  for _, layer in ipairs(A.LAYERS) do
    if layer.kind == kind then t[layer.name] = layer.max end
  end
  return t
end

-- one step of a fade: `cur` moves toward `tgt` by dtMs / fadeMs of the full range; fadeMs 0 jumps
function A.step(cur, tgt, dtMs, fadeMs)
  if fadeMs <= 0 or dtMs >= fadeMs then return tgt end
  local delta = dtMs / fadeMs
  if cur < tgt then return math.min(tgt, cur + delta) end
  return math.max(tgt, cur - delta)
end

-- steps every layer; returns whether any is still visible
function A.stepAll(cur, tgt, dtMs, fadeMs)
  local any = false
  for _, layer in ipairs(A.LAYERS) do
    local v = A.step(cur[layer.name] or 0, tgt[layer.name] or 0, dtMs, fadeMs)
    cur[layer.name] = v
    if v > A.MIN_OPACITY then any = true end
  end
  return any
end

-- true when something is visible now or still has to fade to a target (the timer runs while it is)
function A.busy(cur, tgt)
  for _, layer in ipairs(A.LAYERS) do
    local c, t = cur[layer.name] or 0, tgt[layer.name] or 0
    if c > A.MIN_OPACITY or t > A.MIN_OPACITY then return true end
  end
  return false
end

-- where the tile starts for a layer at a time (ms since the widgets were made): whole pixels, 0 .. TILE - 1 each way. The
-- picture repeats every TILE both ways, so the wrap of each coordinate shows no jump.
function A.offset(layer, tMs)
  local s = tMs / 1000
  local w = 2 * math.pi * tMs / layer.period + layer.phase
  local x = layer.vx * s + layer.sway * math.sin(w)
  local y = layer.vy * s + layer.swayY * math.cos(w * 0.77)
  return math.floor(x + layer.phase) % A.TILE, math.floor(y + layer.phase) % A.TILE
end

-- the twinkle: 1 - pulse * (a slow wave 0..1), so a layer with pulse 0.6 dims to 0.4 of its opacity and back
function A.pulse(layer, tMs)
  if layer.pulse <= 0 then return 1 end
  local wave = 0.5 + 0.5 * math.sin(2 * math.pi * tMs / layer.pulseMs + layer.phase)
  return 1 - layer.pulse * wave
end

-- the image rectangle that fills a w x h widget for an offset (it starts a tile before the offset; the engine clips)
function A.imageRect(ox, oy, w, h)
  return { x = ox - A.TILE, y = oy - A.TILE, width = w + A.TILE, height = h + A.TILE }
end

-- the most textured rectangles one kind draws on a w x h game window (its two layers): the cap of the drawing
function A.maxQuads(w, h)
  local per = (math.ceil((w + A.TILE) / A.TILE) + 1) * (math.ceil((h + A.TILE) / A.TILE) + 1)
  return per * 2
end

-- the most specks one kind puts on a w x h window: the tiles it covers times the specks of a tile (an upper bound, the
-- specks outside the window are clipped)
function A.maxSpecks(w, h)
  local tiles = math.ceil(w / A.TILE + 1) * math.ceil(h / A.TILE + 1)
  return tiles * A.MAX_SPECKS_PER_TILE
end

-- how often the module wakes up: the drift step while it draws, the slow poll while the window is hidden
function A.paceMs(windowVisible)
  return windowVisible and A.TICK_MS or A.HIDDEN_POLL_MS
end
