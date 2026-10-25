-- luajit chaosweather_test.lua && lua5.3 chaosweather_test.lua (from anywhere; CI runs it from the repo root)
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'chaosweather_logic.lua')
local L = ChaosWeatherLogic
local fails, checks = 0, 0
local function eq(a, b, what)
  checks = checks + 1
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end
local function near(a, b, eps, what)
  checks = checks + 1
  if math.abs(a - b) > eps then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end
local function readFile(path)
  local f = io.open(path, 'rb')
  if not f then return nil end
  local s = f:read('*a')
  f:close()
  return s
end
local function pngSize(path)
  local s = readFile(path)
  if not s or #s < 24 or s:sub(2, 4) ~= 'PNG' then return nil end
  local function u32(i) local a, b, c, d = s:byte(i, i + 3) return ((a * 256 + b) * 256 + c) * 256 + d end
  return u32(17), u32(21)
end

-- ---------------------------------------------------------------- the message
eq(L.OPCODE, 114, 'opcode 114')
local w = L.parse({ action = 'set', data = { k = 'rain', i = 2, f = 2500 } })
eq(w.kind, 'rain', 'rain'); eq(w.level, 2, 'level'); eq(w.fadeMs, 2500, 'fade')
w = L.parse({ action = 'set', data = { k = 'none', f = 1000 } })
eq(w.kind, 'none', 'none'); eq(w.level, 0, 'none has no level'); eq(w.fadeMs, 1000, 'none fade')
eq(L.parse({ action = 'set', data = { k = 'rain', i = 9 } }).level, 3, 'level clamped to 3')
eq(L.parse({ action = 'set', data = { k = 'rain', i = 0 } }).level, 1, 'level clamped to 1')
eq(L.parse({ action = 'set', data = { k = 'rain', i = 'x' } }).level, 2, 'no number: normal')
eq(L.parse({ action = 'set', data = { k = 'rain', i = 2.7 } }).level, 2, 'a fraction rounds down')
eq(L.parse({ action = 'set', data = { k = 'rain' } }).fadeMs, L.DEFAULT_FADE_MS, 'no fade: default')
eq(L.parse({ action = 'set', data = { k = 'rain', f = 999999 } }).fadeMs, L.MAX_FADE_MS, 'fade capped')
eq(L.parse({ action = 'set', data = { k = 'rain', f = -5 } }).fadeMs, 0, 'a negative fade is 0')
eq(L.parse({ action = 'set', data = { k = 'rain', f = 0 / 0 } }).fadeMs, L.DEFAULT_FADE_MS, 'NaN fade: default')
eq(L.parse({ action = 'set', data = { k = 'snow', i = 2 } }).kind, 'none', 'an unknown kind shows nothing')
eq(L.parse({ action = 'other', data = {} }), nil, 'another action')
eq(L.parse({ action = 'set' }), nil, 'no data')
eq(L.parse('x'), nil, 'junk'); eq(L.parse(nil), nil, 'nil')

-- ---------------------------------------------------------------- options and targets
eq(L.optionOn(nil), true, 'option default on'); eq(L.optionOn(false), false, 'off kept')
eq(L.optionOn(true), true, 'on kept'); eq(L.optionOn('no'), true, 'junk is on')
local rain2 = { kind = 'rain', level = 2, fadeMs = 2500 }
local t = L.targets(rain2, true, false)
eq(t.far, 1, 'level 2: far'); eq(t.mid, 0, 'level 2: no mid'); eq(t.near, 1, 'level 2: near')
t = L.targets({ kind = 'rain', level = 1, fadeMs = 1 }, true, false)
eq(t.far, 0.6, 'level 1: a thin far layer'); eq(t.near, 0, 'level 1: no near')
t = L.targets({ kind = 'rain', level = 3, fadeMs = 1 }, true, false)
eq(t.far + t.mid + t.near, 3, 'level 3: all three')
for _, v in pairs({ L.targets(rain2, false, false), L.targets(rain2, true, true), L.targets({ kind = 'none', level = 0 }, true, false), L.targets(nil, true, false) }) do
  eq(v.far + v.mid + v.near, 0, 'option off / roof / no rain / no weather: nothing')
end
eq(#L.LAYERS, 3, 'three layers (the cap)')
for level = 1, L.MAX_LEVEL do
  local n = 0
  for _ in pairs(L.PLAN[level]) do n = n + 1 end
  eq(n <= #L.LAYERS, true, 'a plan never uses more layers than exist: ' .. level)
end

-- ---------------------------------------------------------------- fades
eq(L.fadeMs(rain2, false), 2500, 'the server fade')
eq(L.fadeMs(rain2, true), L.COVERED_FADE_MS, 'quick under a roof')
eq(L.fadeMs({ kind = 'none', fadeMs = 200 }, true), 200, 'a shorter server fade stays')
eq(L.fadeMs(nil, false), L.DEFAULT_FADE_MS, 'no weather: default')
near(L.step(0, 1, 250, 2500), 0.1, 1e-9, 'a tenth of the fade')
eq(L.step(0.95, 1, 250, 2500), 1, 'does not overshoot up')
eq(L.step(0.05, 0, 250, 2500), 0, 'does not overshoot down')
eq(L.step(0.5, 1, 10, 0), 1, 'fade 0 jumps')
eq(L.step(0.5, 0, 5000, 2500), 0, 'a long frame reaches it')
local cur, tgt = L.newOpacities(), L.targets(rain2, true, false)
eq(L.busy(cur, tgt), true, 'busy while rain is to come')
local steps = 0
repeat
  steps = steps + 1
  L.stepAll(cur, tgt, L.TICK_MS, 2500)
until cur.far >= 1 or steps > 1000
near(steps * L.TICK_MS, 2500, L.TICK_MS, 'the fade takes the fade time')
eq(cur.far, 1, 'far reaches 1'); eq(cur.near, 1, 'near reaches 1'); eq(cur.mid, 0, 'mid stays 0')
eq(L.busy(cur, tgt), true, 'busy while it rains')
tgt = L.targets({ kind = 'none', level = 0, fadeMs = 2500 }, true, false)
local any = true
for _ = 1, 1000 do
  any = L.stepAll(cur, tgt, L.TICK_MS, 2500)
  if not any then break end
end
eq(any, false, 'faded out')
eq(L.busy(cur, tgt), false, 'idle after the fade: the timer stops')

-- ---------------------------------------------------------------- scroll
local far, near_ = L.LAYERS[1], L.LAYERS[3]
local ox, oy = L.offset(far, 0)
eq(ox, far.phase % L.TILE, 'start x'); eq(oy, far.phase % L.TILE, 'start y')
local prevX, prevY = L.offset(near_, 0)
local wrapsY, wrapsX = 0, 0
for ms = L.TICK_MS, 20000, L.TICK_MS do
  local x, y = L.offset(near_, ms)
  eq(x >= 0 and x < L.TILE and y >= 0 and y < L.TILE and x == math.floor(x) and y == math.floor(y), true, 'whole pixels in range at ' .. ms)
  local dy = (y - prevY) % L.TILE
  eq(dy <= near_.speed * L.TICK_MS / 1000 + 1 and dy >= 0, true, 'a step down is small: ' .. dy)
  local dx = (x - prevX) % L.TILE
  eq(dx <= dy, true, 'sideways is less than down (the slant)')
  if y < prevY then wrapsY = wrapsY + 1 end
  if x < prevX then wrapsX = wrapsX + 1 end
  prevX, prevY = x, y
end
eq(wrapsY > 0 and wrapsX > 0, true, 'the picture wraps and goes on')
-- the slant: over a long run x moves SLANT pixels for each pixel down
local x1, y1 = L.offset(far, 0)
local d = 100000 -- ms
local x2, y2 = L.offset(far, d)
local down = math.floor(far.speed * d / 1000)
near(math.floor(down * L.SLANT) % L.TILE, (x2 - far.phase) % L.TILE, 1, 'slant x')
-- layers do not scroll together
eq(L.offset(L.LAYERS[1], 1000) ~= L.offset(L.LAYERS[2], 1000), true, 'layers at different offsets')
local speeds = {}
for _, layer in ipairs(L.LAYERS) do
  speeds[#speeds + 1] = layer.speed
  eq(layer.speed * L.TICK_MS / 1000 < 24, true, 'a step is under the streak length of ' .. layer.name)
end
eq(speeds[1] < speeds[2] and speeds[2] < speeds[3], true, 'nearer layers are faster')

-- ---------------------------------------------------------------- the image rectangle covers the widget
for _, size in ipairs({ { 1, 1 }, { 640, 480 }, { 1228, 790 }, { 3840, 2160 } }) do
  for _, o in ipairs({ { 0, 0 }, { 1, 1 }, { 255, 255 }, { 128, 7 } }) do
    local r = L.imageRect(o[1], o[2], size[1], size[2])
    eq(r.x <= 0 and r.x + r.width >= size[1], true, 'covers x ' .. size[1] .. ' at ' .. o[1])
    eq(r.y <= 0 and r.y + r.height >= size[2], true, 'covers y ' .. size[2] .. ' at ' .. o[2])
  end
end
-- the cap: a full 4K window draws a few hundred rectangles at most
eq(L.maxQuads(1228, 790) <= 150, true, 'the quads of a 1080p game window: ' .. L.maxQuads(1228, 790))
eq(L.maxQuads(3840, 2160) <= 800, true, 'the quads of a 4K window: ' .. L.maxQuads(3840, 2160))

-- ---------------------------------------------------------------- files
for _, layer in ipairs(L.LAYERS) do
  local pw, ph = pngSize(dir .. 'images/' .. layer.image .. '.png')
  eq(pw, L.TILE, layer.image .. ' width'); eq(ph, L.TILE, layer.image .. ' height')
end
local gen = readFile(dir .. '../../../tools/gen_rain_art.py')
if gen then
  eq(tonumber(gen:match('SLANT = ([%d%.]+)')), L.SLANT, 'the art and the logic share the slant')
  eq(tonumber(gen:match('SIZE = (%d+)')), L.TILE, 'the art and the logic share the tile size')
end
local otmod = readFile(dir .. 'game_chaosweather.otmod')
eq(otmod:find('name: game_chaosweather', 1, true) ~= nil, true, 'module name')
eq(otmod:find('scripts: [ chaosweather_logic, chaosweather ]', 1, true) ~= nil, true, 'module scripts')
local lua = readFile(dir .. 'chaosweather.lua')
eq(lua:find('L.OPCODE', 1, true) ~= nil and lua:find('114', 1, true) ~= nil, true, 'the module names the opcode')
eq(lua:find("g_ui.importStyle('chaosweather')", 1, true) ~= nil and readFile(dir .. 'chaosweather.otui') ~= nil, true, 'style imported')
eq(lua:find('maxQuads', 1, true) ~= nil or lua:find('three layers', 1, true) ~= nil, true, 'the cap is documented in the module')
-- the option is one of game_visualfx's
dofile(dir .. '../game_visualfx/visualfx_logic.lua')
local found = false
for _, name in ipairs(VisualFxLogic.OPTIONS) do if name == 'weather' then found = true end end
eq(found, true, 'weather is a game_visualfx option')
eq(VisualFxLogic.DEFAULTS.weather, true, 'weather is on by default')

if fails > 0 then
  print(string.format('chaosweather: %d of %d checks failed', fails, checks))
  os.exit(1)
end
print(string.format('chaosweather: all %d checks passed', checks))
