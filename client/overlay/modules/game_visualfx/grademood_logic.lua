-- game_visualfx area colour mood (O234, base patch 0153): a gentle colour grade of the map picture that changes by area
-- (cold blue on ice, sickly green in swamps, warm amber in deserts and fire places, desaturated in crypts) and eases over about
-- 2 s when the player crosses into another area. The server only names the mood (weather opcode 114, field `m`,
-- weather_core.lua moodAt); the numbers are here. No engine calls, so grademood_test.lua can run it. Every function takes the
-- time (ms).
-- The five values are what g_shaders.setMapGrade takes and what chaos_map_grade.frag adds on top of its own grade: a tint added
-- to the colour (red, green, blue; 1.0 would be full scale), the change of the colour kept (sat; + is more colour, - less)
-- and the change of the contrast factor (con). All 0 is the plain grade of 0126. The engine clamps tint to +-0.15 and the
-- other two to +-0.35; these presets stay far below that on purpose (dark fantasy, not neon): the largest tint is 0.036
-- (about 9 of 255), the largest saturation change 0.10 and the largest contrast change 0.03.
GradeMoodLogic = {}
local G = GradeMoodLogic

G.EASE_MS = 2000   -- how long a change of mood takes
G.STEP_MS = 33     -- the timer runs at about 30 Hz and only while the mood changes
G.GRID = 1000      -- the values are rounded to 1/1000 so the engine is only called when a value really moved

G.KEYS = { 'r', 'g', 'b', 'sat', 'con' }

-- the presets (the kinds of ChaosWeather.MOOD_KINDS of the server)
G.PRESETS = {
  ice    = { r = -0.020, g =  0.004, b =  0.034, sat = -0.02, con = 0.00 },  -- cold blue, a little paler
  swamp  = { r = -0.012, g =  0.026, b = -0.018, sat = -0.03, con = 0.01 },  -- sickly green, a little muddy
  desert = { r =  0.032, g =  0.016, b = -0.022, sat =  0.02, con = 0.01 },  -- warm amber
  fire   = { r =  0.036, g =  0.004, b = -0.030, sat =  0.02, con = 0.03 },  -- amber red, harder shadows
  crypt  = { r = -0.006, g = -0.002, b =  0.004, sat = -0.10, con = 0.02 },  -- drained, almost grey
}

local NEUTRAL = { r = 0, g = 0, b = 0, sat = 0, con = 0 }

function G.neutral()
  return { r = 0, g = 0, b = 0, sat = 0, con = 0 }
end

-- the kind of a mood name from the server, or nil: an unknown name (a later server) is no mood
function G.kindOf(name)
  if type(name) == 'string' and G.PRESETS[name] then return name end
  return nil
end

-- the kind of a set message of the server ({action = 'set', data = {m = ...}}), or nil for no mood
function G.parseKind(msg)
  if type(msg) ~= 'table' or msg.action ~= 'set' or type(msg.data) ~= 'table' then return nil end
  return G.kindOf(msg.data.m)
end

local function target(kind)
  return G.PRESETS[kind] or NEUTRAL
end

local function smooth(t)
  if t <= 0 then return 0 end
  if t >= 1 then return 1 end
  return t * t * (3 - 2 * t)
end

local function round(v)
  local g = G.GRID
  return math.floor(v * g + 0.5) / g
end

function G.new()
  return { kind = nil, from = G.neutral(), t0 = 0, ms = G.EASE_MS }
end

-- the values at this moment: the start values moving to the preset along a smoothstep
function G.values(state, now)
  local to = target(state.kind)
  local k = smooth((now - state.t0) / state.ms)
  local out = {}
  for _, key in ipairs(G.KEYS) do
    local a = state.from[key]
    out[key] = round(a + (to[key] - a) * k)
  end
  return out
end

-- true when the picture has reached the preset (the timer can stop)
function G.settled(state, now)
  return now - state.t0 >= state.ms
end

-- the mood changes to `kind` (nil = none). The ease starts from what is on the screen now, so a change in the middle of
-- another one (walking along a border) never jumps. Returns true when something started; the same kind again does nothing.
function G.setKind(state, now, kind)
  kind = G.kindOf(kind)
  if kind == state.kind then return false end
  state.from = G.values(state, now)
  state.kind = kind
  state.t0, state.ms = now, G.EASE_MS
  return true
end

-- no ease: the preset at once (the game starts, the option is switched on), or the plain grade with kind nil
function G.snap(state, now, kind)
  state.kind = G.kindOf(kind)
  state.from = G.neutral()
  state.t0, state.ms = now - G.EASE_MS, G.EASE_MS
end

-- whether two value tables differ at the engine's resolution
function G.differ(a, b)
  if not a or not b then return true end
  for _, key in ipairs(G.KEYS) do
    if a[key] ~= b[key] then return true end
  end
  return false
end
