-- luajit chaosambient_test.lua && lua5.3 chaosambient_test.lua (from anywhere; CI runs it from the repo root)
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'chaosambient_logic.lua')
local A = ChaosAmbientLogic
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
eq(A.parseKind({ action = 'set', data = { k = 'none', a = 'embers' } }), 'embers', 'embers')
eq(A.parseKind({ action = 'set', data = { k = 'rain', i = 2, a = 'motes' } }), 'motes', 'a mood in the rain')
eq(A.parseKind({ action = 'set', data = { k = 'none', a = 'dust' } }), 'dust', 'dust')
eq(A.parseKind({ action = 'set', data = { k = 'rain', i = 2 } }), nil, 'the old message: no mood')
eq(A.parseKind({ action = 'set', data = { a = 'snow' } }), nil, 'an unknown mood shows nothing')
eq(A.parseKind({ action = 'set', data = { a = 5 } }), nil, 'a number is no mood')
eq(A.parseKind({ action = 'set', data = { a = '__index' } }), nil, 'a table key name is no mood')
eq(A.parseKind({ action = 'other', data = { a = 'dust' } }), nil, 'another action')
eq(A.parseKind({ action = 'set' }), nil, 'no data'); eq(A.parseKind('x'), nil, 'junk'); eq(A.parseKind(nil), nil, 'nil')
eq(A.parseFade({ action = 'set', data = { f = 1000 } }), 1000, 'fade')
eq(A.parseFade({ action = 'set', data = {} }), A.DEFAULT_FADE_MS, 'no fade: default')
eq(A.parseFade({ action = 'set', data = { f = 999999 } }), A.MAX_FADE_MS, 'fade capped')
eq(A.parseFade({ action = 'set', data = { f = -4 } }), 0, 'negative fade is 0')
eq(A.parseFade({ action = 'set', data = { f = 0 / 0 } }), A.DEFAULT_FADE_MS, 'NaN fade: default')
eq(A.parseFade(nil), A.DEFAULT_FADE_MS, 'nil: default')

-- ---------------------------------------------------------------- option and targets
eq(A.optionOn(nil), true, 'default on'); eq(A.optionOn(false), false, 'off kept'); eq(A.optionOn('no'), true, 'junk is on')
local function sum(t) local n = 0 for _, v in pairs(t) do n = n + v end return n end
local t = A.targets('embers', true, true)
eq(t.embers_far > 0 and t.embers_near > 0, true, 'embers: both layers')
eq(t.motes_far + t.motes_near + t.dust_far + t.dust_near, 0, 'embers: no other kind')
t = A.targets('motes', true, true); eq(t.motes_far > 0 and t.embers_far == 0, true, 'motes only')
t = A.targets('dust', true, true); eq(t.dust_near > 0 and t.motes_near == 0, true, 'dust only')
eq(sum(A.targets('embers', false, true)), 0, 'option off: nothing')
eq(sum(A.targets('embers', true, false)), 0, 'window hidden: nothing')
eq(sum(A.targets(nil, true, true)), 0, 'no mood: nothing')
eq(sum(A.targets('rain', true, true)), 0, 'unknown mood: nothing')
eq(#A.LAYERS, 6, 'six layers, two per kind')
local perKind = {}
for _, layer in ipairs(A.LAYERS) do perKind[layer.kind] = (perKind[layer.kind] or 0) + 1 end
eq(perKind.embers, 2, 'two embers layers'); eq(perKind.motes, 2, 'two motes layers'); eq(perKind.dust, 2, 'two dust layers')

-- ---------------------------------------------------------------- fades and the idle timer
local cur, tgt = A.newOpacities(), A.targets('motes', true, true)
eq(A.busy(cur, tgt), true, 'busy while a mood is to come')
local steps = 0
repeat steps = steps + 1; A.stepAll(cur, tgt, A.TICK_MS, 2500) until cur.motes_near >= 1 or steps > 5000
near(steps * A.TICK_MS, 2500, A.TICK_MS, 'the fade takes the fade time')
eq(cur.motes_far, tgt.motes_far, 'far reaches its max'); eq(cur.dust_far, 0, 'other kinds stay 0')
-- a change of mood cross-fades: motes out, embers in
tgt = A.targets('embers', true, true)
A.stepAll(cur, tgt, 500, 2500)
eq(cur.motes_near < 1 and cur.motes_near > 0 and cur.embers_near > 0, true, 'cross-fade: both partly visible')
tgt = A.targets(nil, true, true)
local any = true
for _ = 1, 5000 do any = A.stepAll(cur, tgt, A.TICK_MS, 2500) if not any then break end end
eq(any, false, 'faded out'); eq(A.busy(cur, tgt), false, 'idle after the fade: the timer stops')
eq(A.step(0.5, 1, 10, 0), 1, 'fade 0 jumps')
eq(A.paceMs(true), A.TICK_MS, 'visible window: the drift step'); eq(A.paceMs(false), A.HIDDEN_POLL_MS, 'hidden window: slow poll')
eq(A.HIDDEN_POLL_MS >= 500, true, 'the hidden poll is slow')

-- ---------------------------------------------------------------- drift
for _, layer in ipairs(A.LAYERS) do
  local px, py = A.offset(layer, 0)
  local maxStep = 0
  for ms = A.TICK_MS, 60000, A.TICK_MS do
    local x, y = A.offset(layer, ms)
    eq(x >= 0 and x < A.TILE and y >= 0 and y < A.TILE and x == math.floor(x) and y == math.floor(y), true, 'whole pixels in range ' .. layer.name .. ' ' .. ms)
    local dx, dy = math.abs(x - px), math.abs(y - py)
    dx, dy = math.min(dx, A.TILE - dx), math.min(dy, A.TILE - dy)   -- a wrap is a step of 1, not of TILE
    maxStep = math.max(maxStep, dx, dy)
    px, py = x, y
  end
  eq(maxStep <= 4, true, 'slow: at most 4 pixels a step for ' .. layer.name .. ' (' .. maxStep .. ')')
  local o1x, o1y = A.offset(layer, 1000)
  local o2x, o2y = A.offset(layer, 1000 + A.TICK_MS)
  eq(o1x ~= nil and o2y ~= nil, true, 'defined')
  eq(layer.pulse >= 0 and layer.pulse < 1, true, 'pulse in range ' .. layer.name)
  eq(layer.max > 0 and layer.max <= 1, true, 'max in range ' .. layer.name)
end
-- the layers of a kind do not move together
eq(A.offset(A.LAYERS[1], 4000) ~= A.offset(A.LAYERS[2], 4000) or select(2, A.offset(A.LAYERS[1], 4000)) ~= select(2, A.offset(A.LAYERS[2], 4000)), true, 'layers at different offsets')
-- embers rise (their y offset goes down over time), the others barely move up or down
local e = A.LAYERS[2]
eq(e.vy < 0, true, 'embers rise')
-- the twinkle
for _, layer in ipairs(A.LAYERS) do
  local lo, hi = 2, -1
  for ms = 0, 20000, 50 do
    local p = A.pulse(layer, ms)
    lo, hi = math.min(lo, p), math.max(hi, p)
  end
  eq(lo >= 1 - layer.pulse - 1e-9 and hi <= 1 + 1e-9, true, 'pulse stays in its band ' .. layer.name)
  if layer.pulse > 0 then eq(hi - lo > layer.pulse * 0.8, true, 'the twinkle reaches its depth ' .. layer.name) end
end
eq(A.pulse(A.LAYERS[5], 1234), 1, 'dust does not twinkle')

-- ---------------------------------------------------------------- the image rectangle covers the widget; the caps
for _, size in ipairs({ { 1, 1 }, { 640, 480 }, { 1228, 790 }, { 3840, 2160 } }) do
  for _, o in ipairs({ { 0, 0 }, { 1, 1 }, { 511, 511 }, { 300, 7 } }) do
    local r = A.imageRect(o[1], o[2], size[1], size[2])
    eq(r.x <= 0 and r.x + r.width >= size[1], true, 'covers x ' .. size[1] .. ' at ' .. o[1])
    eq(r.y <= 0 and r.y + r.height >= size[2], true, 'covers y ' .. size[2] .. ' at ' .. o[2])
  end
end
eq(A.maxQuads(1228, 790) <= 40, true, 'the quads of a game window: ' .. A.maxQuads(1228, 790))
eq(A.maxQuads(3840, 2160) <= 220, true, 'the quads of a 4K window: ' .. A.maxQuads(3840, 2160))
eq(A.maxSpecks(1228, 790) <= 400, true, 'the specks of a game window: ' .. A.maxSpecks(1228, 790))
eq(A.maxSpecks(3840, 2160) <= 1500, true, 'the specks of a 4K window: ' .. A.maxSpecks(3840, 2160))
for kind in pairs(A.KINDS) do
  local n = 0
  for _, layer in ipairs(A.LAYERS) do if layer.kind == kind then n = n + A.ART[layer.name] end end
  eq(n <= A.MAX_SPECKS_PER_TILE, true, 'specks per tile of ' .. kind .. ': ' .. n)
end

-- ---------------------------------------------------------------- files
for _, layer in ipairs(A.LAYERS) do
  local pw, ph = pngSize(dir .. 'images/' .. layer.image .. '.png')
  eq(pw, A.TILE, layer.image .. ' width'); eq(ph, A.TILE, layer.image .. ' height')
end
local gen = readFile(dir .. '../../../tools/gen_ambient_art.py')
if gen then
  eq(tonumber(gen:match('\nSIZE = (%d+)')), A.TILE, 'the art and the logic share the tile size')
  for _, layer in ipairs(A.LAYERS) do
    local count = gen:match("%('" .. layer.image .. "', '%w+', (%d+),")
    eq(tonumber(count), A.ART[layer.name], 'the art counts the specks the logic says: ' .. layer.name)
  end
end
local otmod = readFile(dir .. 'game_chaosweather.otmod')
eq(otmod:find('scripts: [ chaosweather_logic, chaosambient_logic, chaosambient, chaosweather ]', 1, true) ~= nil, true, 'module scripts')
local glue = readFile(dir .. 'chaosambient.lua')
eq(glue:find('g_window.isVisible', 1, true) ~= nil, true, 'the glue looks at the window')
eq(glue:find('HIDDEN_POLL_MS', 1, true) ~= nil, true, 'and slows down while it is hidden')
local weather = readFile(dir .. 'chaosweather.lua')
eq(weather:find('ChaosAmbient.', 1, true) ~= nil, true, 'the weather module feeds the ambient layer')
-- the option is one of game_visualfx's, on by default
dofile(dir .. '../game_visualfx/visualfx_logic.lua')
local found = false
for _, name in ipairs(VisualFxLogic.OPTIONS) do if name == 'ambientParticles' then found = true end end
eq(found, true, 'ambientParticles is a game_visualfx option')
eq(VisualFxLogic.DEFAULTS.ambientParticles, true, 'ambientParticles is on by default')

if fails > 0 then
  print(string.format('chaosambient: %d of %d checks failed', fails, checks))
  os.exit(1)
end
print(string.format('chaosambient: all %d checks passed', checks))
