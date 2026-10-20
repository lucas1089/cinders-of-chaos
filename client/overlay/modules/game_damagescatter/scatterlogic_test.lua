-- luajit scatterlogic_test.lua && lua5.3 scatterlogic_test.lua (from anywhere; CI runs it from the repo root)
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'scatterlogic.lua')
local L = DamageScatterLogic
local fails, checks = 0, 0
local function eq(a, b, what)
  checks = checks + 1
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

-- key
eq(L.key('Chaos', 'Ana'), 'Chaos/Ana', 'key')
eq(L.key(nil, 'Ana'), '-/Ana', 'key without world')
eq(L.key('Chaos', ''), nil, 'no name, no key')
eq(L.key('Chaos', nil), nil, 'nil name, no key')

-- sanitize
local d = L.sanitize(nil)
eq(d.enabled, true, 'on by default')
eq(d.level, 2, 'level 2 by default')
eq(L.sanitize('junk').level, 2, 'junk -> default')
eq(L.sanitize({ enabled = false }).enabled, false, 'off is kept')
eq(L.sanitize({ enabled = 'no' }).enabled, true, 'a non-boolean flag is ignored')
eq(L.sanitize({ level = 0 }).level, 1, 'level clamps up')
eq(L.sanitize({ level = 9 }).level, 3, 'level clamps down')
eq(L.sanitize({ level = 2.6 }).level, 3, 'level rounds')
eq(L.sanitize({ level = '3' }).level, 3, 'level from text')
eq(L.sanitize({ level = 0 / 0 }).level, 2, 'nan -> default')
eq(L.sanitize({ level = math.huge }).level, 2, 'inf -> default')

-- per character
local node = L.withSettings(nil, 'W/A', { enabled = false, level = 3 })
node = L.withSettings(node, 'W/B', { level = 1, junk = 5 })
eq(L.settingsFor(node, 'W/A').enabled, false, 'A is off')
eq(L.settingsFor(node, 'W/A').level, 3, 'A level')
eq(L.settingsFor(node, 'W/B').enabled, true, 'B is on')
eq(L.settingsFor(node, 'W/B').level, 1, 'B level')
eq(node['W/B'].junk, nil, 'unknown fields are dropped')
eq(L.settingsFor(node, 'W/C').level, 2, 'a new character gets the default')
eq(L.settingsFor(node, nil).enabled, true, 'no key -> default')
eq(L.settingsFor('x', 'W/A').enabled, true, 'a bad node -> default')
local before = L.withSettings(node, 'W/A', { enabled = true })
eq(node['W/A'].enabled, false, 'withSettings does not touch its input')
eq(before['W/B'].level, 1, 'withSettings keeps the others')

-- rng: deterministic, inside [0, 1), not stuck
local r1, r2 = L.newRng(42), L.newRng(42)
local lo, hi = 1, 0
for i = 1, 5000 do
  local a, b = r1.next(), r2.next()
  eq(a, b, 'same seed, same stream')
  if a < lo then lo = a end
  if a > hi then hi = a end
  if a < 0 or a >= 1 then eq(a, 'in [0,1)', 'rng range') break end
end
eq(lo < 0.01 and hi > 0.99, true, 'the stream covers the range')
eq(L.newRng(0).next() >= 0, true, 'seed 0 works')
eq(L.newRng(-5).next() >= 0, true, 'a negative seed works')
eq(L.newRng('x').next() >= 0, true, 'a junk seed works')

-- roll: inside the level's bounds, centred, and the strength grows with the level
local rng = L.newRng(7)
for level = 1, L.LEVELS do
  local s = L.STRENGTH[level]
  local minx, maxx, miny, maxy, minsp, maxsp, sumx = 99, -99, 99, -99, 9, 0, 0
  for i = 1, 4000 do
    local dx, dy, sp = L.roll(level, rng)
    minx, maxx = math.min(minx, dx), math.max(maxx, dx)
    miny, maxy = math.min(miny, dy), math.max(maxy, dy)
    minsp, maxsp = math.min(minsp, sp), math.max(maxsp, sp)
    sumx = sumx + dx
    eq(dx == math.floor(dx) and dy == math.floor(dy), true, 'whole pixels')
  end
  eq(maxx <= s.x and minx >= -s.x, true, 'level ' .. level .. ' x bounds')
  eq(maxy <= s.y and miny >= -s.y, true, 'level ' .. level .. ' y bounds')
  eq(maxx >= s.x - 1 and minx <= -s.x + 1, true, 'level ' .. level .. ' reaches both sides')
  eq(minsp >= 1 - s.speed - 1e-9 and maxsp <= 1 + s.speed + 1e-9, true, 'level ' .. level .. ' speed bounds')
  eq(minsp < 1 and maxsp > 1, true, 'level ' .. level .. ' speed goes both ways')
  eq(math.abs(sumx / 4000) < s.x * 0.1, true, 'level ' .. level .. ' is centred')
end
eq(L.STRENGTH[1].x < L.STRENGTH[2].x and L.STRENGTH[2].x < L.STRENGTH[3].x, true, 'x grows with the level')
eq(L.STRENGTH[1].speed < L.STRENGTH[3].speed, true, 'speed spread grows with the level')
eq(L.STRENGTH[3].speed < 0.5, true, 'the engine clamp (0.5 .. 2) is never reached')
local dx, dy, sp = L.roll(99, L.newRng(1))
eq(type(dx) == 'number' and type(sp) == 'number', true, 'an unknown level uses the default')

-- pick: off -> nil; same square within the window -> same roll; later or elsewhere -> new roll
local on = { enabled = true, level = 3 }
local g = {}
local rng2 = L.newRng(11)
local p1 = { x = 100, y = 100, z = 7 }
eq(L.pick(g, { enabled = false, level = 3 }, p1, 0, rng2), nil, 'off -> nothing')
eq(L.pick(g, nil, p1, 0, rng2), nil, 'no settings -> nothing')
local ax, ay, as = L.pick(g, on, p1, 1000, rng2)
local bx, by, bs = L.pick(g, on, { x = 100, y = 100, z = 7 }, 1000 + L.GROUP_MS, rng2)
eq(ax == bx and ay == by and as == bs, true, 'the two numbers of one hit share a roll')
local changed = 0
for i = 1, 30 do
  local cx, cy = L.pick(g, on, p1, 5000 + i * 500, rng2)
  if cx ~= ax or cy ~= ay then changed = changed + 1 end
end
eq(changed > 15, true, 'later hits roll again')
local gx, gy, gz = {}, nil, nil
local ex = L.pick(gx, on, p1, 0, L.newRng(3))
local other = L.pick(gx, on, { x = 101, y = 100, z = 7 }, 10, L.newRng(99))
local elsewhere = 0
for s = 1, 20 do
  local grp = {}
  local a = L.pick(grp, on, p1, 0, L.newRng(s))
  local rb = L.newRng(s + 1000)
  local b = L.pick(grp, on, { x = 101, y = 100, z = 7 }, 10, rb)
  local c = L.roll(3, L.newRng(s + 1000))
  if b == c then elsewhere = elsewhere + 1 end
end
eq(elsewhere, 20, 'another square is a new roll, not the group')
local grp2 = {}
L.pick(grp2, on, p1, 0, L.newRng(5))
local f = { L.pick(grp2, on, { x = 100, y = 100, z = 8 }, 10, L.newRng(77)) }
eq(f[1], (L.roll(3, L.newRng(77))), 'another floor is a new roll')
eq(select('#', L.pick({}, on, nil, 0, L.newRng(1))), 3, 'a missing position still rolls')

print(string.format('scatterlogic_test: %d checks, %d failed', checks, fails))
os.exit(fails == 0 and 0 or 1)
