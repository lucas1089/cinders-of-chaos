-- luajit killdissolve_core_test.lua && lua5.3 killdissolve_core_test.lua (CI runs every client/overlay/modules/*/*_test.lua)
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'killdissolve_core.lua')
local K = KillDissolveCore
local fails, checks = 0, 0
local function eq(a, b, what)
  checks = checks + 1
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end
local function near(a, b, what) eq(math.abs(a - b) < 1e-6, true, what .. ' (' .. tostring(a) .. ' vs ' .. tostring(b) .. ')') end

-- modes: seven, each with a duration of about a second, in the generator's order
eq(#K.ORDER, 7, 'seven modes')
for _, m in ipairs(K.ORDER) do
  eq(K.isMode(m), true, m .. ' is a mode')
  eq(K.duration(m) >= 800 and K.duration(m) <= 1500, true, m .. ' lasts about a second')
  eq(K.shaderName(m), 'chaos_kd_' .. m, m .. ' shader name')
end
eq(K.isMode('plasma'), false, 'unknown mode')
eq(K.isMode(nil), false, 'no mode')
eq(K.shaderName('plasma'), nil, 'no shader for an unknown mode')

-- progress: linear, clamped, never 0 (the engine skips an all-0 set of shader numbers)
near(K.progress('sand', 0), K.MIN_PROGRESS, 'progress at the start')
near(K.progress('sand', 500), 0.5, 'progress at half')
near(K.progress('sand', 5000), 1, 'progress capped at 1')
near(K.progress('sand', -20), K.MIN_PROGRESS, 'negative time')
near(K.progress('sand', 'x'), K.MIN_PROGRESS, 'garbage time')

-- the outfit of a frame: the look kept, the shader numbers set
local o = K.outfitFor({ type = 5, head = 1, body = 2, legs = 3, feet = 4, addons = 0 }, 'burn', 7, 0.5, 0.25, 64)
eq(o.type, 5, 'look kept') eq(o.legs, 3, 'colours kept')
eq(o.shader, 'chaos_kd_burn', 'shader') eq(o.shaderA, 0.5, 'progress') eq(o.shaderB, 8, 'tint + 1') eq(o.shaderC, 0.25, 'seed')
eq(o.shaderD, 64, 'width')
local o2 = K.outfitFor({ type = 5 }, 'burn', 99, 7, -3, 0)
eq(o2.shaderB, 8, 'tint capped') eq(o2.shaderA, 1, 'progress capped') eq(o2.shaderC, 0, 'seed floor') eq(o2.shaderD, 8, 'width floor')
eq(K.outfitFor({ type = 5 }, 'nope', 0, 0.5, 0, 32), nil, 'unknown mode: no outfit')
eq(K.outfitFor(nil, 'sand', 0, 0.5, 0, 32), nil, 'no base: no outfit')
local src = { type = 5 }
K.outfitFor(src, 'sand', 0, 0.5, 0, 32)
eq(src.shader, nil, 'the base look is not changed')
for _, m in ipairs(K.ORDER) do
  local f = K.outfitFor({ type = 1 }, m, 0, K.progress(m, 0), 0, 32)
  eq(f.shaderA > 0 or f.shaderB > 0, true, m .. ': the numbers are never all 0')
end

-- the seed: 0 .. 1, steady for a place, different between places
for i = 1, 50 do
  local s = K.seedOf(1000 + i, 900 - i, 7, i * 31)
  eq(s >= 0 and s <= 1, true, 'seed in range')
end
eq(K.seedOf(1, 2, 3, 4), K.seedOf(1, 2, 3, 4), 'seed is steady')
local seen = {}
for i = 1, 40 do seen[K.seedOf(1000 + i, 1000, 7, i)] = true end
local distinct = 0
for _ in pairs(seen) do distinct = distinct + 1 end
eq(distinct > 20, true, 'seeds differ between kills')

-- looks and places of a message
eq(K.sanitizeLook(nil), nil, 'no look')
eq(K.sanitizeLook({ l = 0 }), nil, 'look 0 is no creature')
eq(K.sanitizeLook({ l = -4 }), nil, 'negative look')
eq(K.sanitizeLook({ l = 70000 }), nil, 'look beyond the id range')
eq(K.sanitizeLook({ l = 'x' }), nil, 'look as text')
local lk = K.sanitizeLook({ l = 12, h = 500, b = -1, g = 20, f = 'x', a = 9 })
eq(lk.type, 12, 'type') eq(lk.head, 132, 'colour capped') eq(lk.body, 0, 'colour floor') eq(lk.legs, 20, 'colour kept') eq(lk.feet, 0, 'junk colour') eq(lk.addons, 3, 'addons capped')
eq(K.sanitizePos({ x = 100, y = 200, z = 7 }).y, 200, 'position')
eq(K.sanitizePos({ x = 0, y = 200, z = 7 }), nil, 'no x')
eq(K.sanitizePos({ x = 5, y = 5, z = 16 }), nil, 'floor out of range')
eq(K.sanitizePos(nil), nil, 'no message')
local pe = K.plainEffect({ v = { id = 77, dx = 1, dy = 2 } })
eq(pe.id, 77, 'plain effect id') eq(pe.dx, 1, 'plain dx') eq(pe.dy, 2, 'plain dy')
eq(K.plainEffect({}), nil, 'no plain effect') eq(K.plainEffect({ v = { id = 0 } }), nil, 'plain id 0')

-- the cap
local cap = K.newCap(2)
eq(K.admit(cap), true, 'first') eq(K.admit(cap), true, 'second') eq(K.admit(cap), false, 'third is over the cap')
eq(cap.dropped, 1, 'one dropped') eq(cap.active, 2, 'two active')
K.release(cap) eq(cap.active, 1, 'one released') eq(K.admit(cap), true, 'room again')
K.release(cap) K.release(cap) K.release(cap)
eq(cap.active, 0, 'never below 0')
eq(K.MAX_ACTIVE, 6, 'six at once') eq(K.MAX_ACTIVE_MOBILE, 3, 'three on a phone')
eq(K.admit(K.newCap(0)), false, 'a cap of 0 admits nothing')

-- the decision
local function msg(over)
  local m = { m = 'sand', t = 0, i = 4001, x = 1000, y = 1000, z = 7, o = { l = 5, h = 0, b = 0, g = 0, f = 0, a = 0 }, d = 2,
    v = { id = 200, dx = 1, dy = 1 } }
  for k, v in pairs(over or {}) do m[k] = v end
  return m
end
local function env(over)
  local e = { enabled = true, hasParams = true, ready = function() return true end, cap = K.newCap(2) }
  for k, v in pairs(over or {}) do e[k] = v end
  return e
end
local p = K.plan(msg(), env())
eq(p.action, 'dissolve', 'a plain kill dissolves') eq(p.mode, 'sand', 'mode') eq(p.look.type, 5, 'look') eq(p.pos.x, 1000, 'pos') eq(p.direction, 2, 'direction')
eq(K.plan(msg(), env({ enabled = false })).action, 'plain', 'option off: plain effect')
eq(K.plan(msg(), env({ enabled = false })).why, 'off', 'option off: why')
eq(K.plan(msg(), env({ hasParams = false })).why, 'engine', 'an engine without base patch 0201: plain')
eq(K.plan(msg(), env({ ready = function() return false end })).why, 'shader', 'a shader that did not compile: plain')
eq(K.plan(msg({ m = 'plasma' }), env()).why, 'mode', 'unknown mode: plain')
eq(K.plan(msg({ o = { l = 0 } }), env()).why, 'look', 'no look: plain')
eq(K.plan(msg({ v = false }), env({ enabled = false })).action, 'none', 'nothing to fall back to: nothing')
eq(K.plan(msg({ x = 0 }), env()).action, 'none', 'no place: nothing')
eq(K.plan(nil, env()).action, 'none', 'no message') eq(K.plan(msg(), nil).action, 'none', 'no environment')
-- the cap: the third kill at once plays the plain effect and does not take a slot
local e3 = env()
eq(K.plan(msg(), e3).action, 'dissolve', 'one') eq(K.plan(msg(), e3).action, 'dissolve', 'two')
local third = K.plan(msg(), e3)
eq(third.action, 'plain', 'three: plain') eq(third.why, 'cap', 'three: over the cap') eq(third.effect.id, 200, 'the server effect plays')
eq(e3.cap.active, 2, 'the plain kill took no slot')
eq(K.plan(msg({ t = 99 }), env()).tint, 7, 'tint capped')

-- a decision that falls back never takes a slot
local e4 = env({ enabled = false })
K.plan(msg(), e4)
eq(e4.cap.active, 0, 'plain: no slot')

-- the preview loop: stand, dissolve, gone, appear
local total = K.loopMs('sand')
eq(total, K.STAND_MS + 1000 + K.GONE_MS + K.APPEAR_MS, 'loop length')
eq(K.stage('sand', 0).phase, 'stand', 'loop starts standing')
eq(K.stage('sand', K.STAND_MS - 1).phase, 'stand', 'still standing')
eq(K.stage('sand', K.STAND_MS + 10).phase, 'dissolve', 'dissolving')
near(K.stage('sand', K.STAND_MS + 500).progress, 0.5, 'half way')
eq(K.stage('sand', K.STAND_MS + 1000 + 10).phase, 'gone', 'gone')
local ap = K.stage('sand', total - 5)
eq(ap.phase, 'appear', 'appearing') eq(ap.alpha > 0.9, true, 'nearly back')
eq(K.stage('sand', total).phase, 'stand', 'the loop starts over')
eq(K.stage('sand', total * 3 + K.STAND_MS + 10).phase, 'dissolve', 'the loop repeats')
eq(K.stage('nope', 100).phase, 'stand', 'unknown mode stands')
eq(K.tileFps(true, false), 30, 'a hovered tile animates at 30 per second')
eq(K.tileFps(false, true), 30, 'a selected tile animates')
eq(K.tileFps(false, false), 0, 'the other tiles are still')

if fails > 0 then print(fails .. ' of ' .. checks .. ' checks FAILED'); os.exit(1) end
print('killdissolve_core_test: ' .. checks .. ' checks ok')
