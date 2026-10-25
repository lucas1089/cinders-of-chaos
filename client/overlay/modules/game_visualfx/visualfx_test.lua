-- luajit visualfx_test.lua && lua5.3 visualfx_test.lua (from anywhere; CI runs it from the repo root)
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'visualfx_logic.lua')
local L = VisualFxLogic
local fails, checks = 0, 0
local function eq(a, b, what)
  checks = checks + 1
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

-- options: the grade is off by default (it shifts the biome colours), the rest on; a boolean wins, junk is the default
local wantDefault = { hitFlash = true, screenShake = true, creatureShadow = true, screenGrade = false }
for _, name in ipairs(L.OPTIONS) do
  local d = wantDefault[name]
  eq(L.optionOn(name, nil), d, name .. ' default')
  eq(L.optionOn(name, false), false, name .. ' off is kept')
  eq(L.optionOn(name, true), true, name .. ' on is kept')
  eq(L.optionOn(name, 'no'), d, name .. ' junk -> default')
  eq(L.optionOn(name, 0), d, name .. ' number -> default')
end
eq(#L.OPTIONS, 4, 'four options')
eq(L.optionOn('nothing', nil), false, 'an unknown option is off')

-- hit flash
local M = L.MODE
local f = L.newFlasher()
local shader, ms = L.flashPlan(f, 1000, 7, M.DAMAGE_DEALT, 0, 120, false)
eq(shader, 'chaos_hit_white', 'a hit on a monster flashes white')
eq(ms, 80, 'a plain hit: 80 ms')
shader, ms = L.flashPlan(f, 1000, 8, M.DAMAGE_RECEIVED, 0, 50, true)
eq(shader, 'chaos_hit_red', 'a hit on the player flashes red')
shader, ms = L.flashPlan(f, 1000, 9, M.DAMAGE_OTHERS, 1, 300, false)
eq(shader, 'chaos_hit_white', 'a critical hit of someone else')
eq(ms, 110, 'a critical hit: 110 ms')
eq(L.flashPlan(f, 1050, 7, M.DAMAGE_DEALT, 0, 120, false), nil, 'the same creature inside the gap does not flash again')
eq(L.flashPlan(f, 1139, 7, M.DAMAGE_DEALT, 0, 120, false), nil, 'one ms before the gap ends')
eq(L.flashPlan(f, 1140, 7, M.DAMAGE_DEALT, 0, 120, false), 'chaos_hit_white', 'at the gap it flashes again')
eq(L.flashPlan(f, 2000, 20, M.HEAL or 23, 0, 100, false), nil, 'a heal does not flash')
eq(L.flashPlan(f, 2000, 20, 24, 0, 100, false), nil, 'experience does not flash')
eq(L.flashPlan(f, 2000, 20, M.DAMAGE_DEALT, 2, 100, false), nil, 'a damage-over-time tick does not flash')
eq(L.flashPlan(f, 2000, 20, M.DAMAGE_DEALT, 3, 100, false), nil, 'a mana drain does not flash')
eq(L.flashPlan(f, 2000, 20, M.DAMAGE_DEALT, 0, 0, false), nil, 'a zero hit does not flash')
eq(L.flashPlan(f, 2000, 0, M.DAMAGE_DEALT, 0, 10, false), nil, 'no creature id, no flash')
eq(L.flashPlan(f, 2000, nil, M.DAMAGE_DEALT, 0, 10, false), nil, 'nil creature id, no flash')
eq(L.flashPlan(f, 2000, 21, M.DAMAGE_DEALT, nil, 10, false), 'chaos_hit_white', 'a missing type is a plain hit')

-- the cap on flashes alive at once, and it opens as they end
local c = L.newFlasher()
local fired = 0
for id = 1, 20 do
  if L.flashPlan(c, 5000, id, M.DAMAGE_DEALT, 0, 10, false) then fired = fired + 1 end
end
eq(fired, L.FLASH.maxActive, 'at most maxActive flashes at once')
eq(L.flashPlan(c, 5079, 30, M.DAMAGE_DEALT, 0, 10, false), nil, 'still full 79 ms in')
eq(L.flashPlan(c, 5080, 30, M.DAMAGE_DEALT, 0, 10, false), 'chaos_hit_white', 'room again when they end')

-- the memory of old creatures is pruned
local p = L.newFlasher()
for id = 1, 200 do L.flashPlan(p, id * 3000, id, M.DAMAGE_DEALT, 0, 10, false) end
local n = 0
for _ in pairs(p.last) do n = n + 1 end
eq(n < 100, true, 'old creatures are forgotten')

-- shake strength
eq(L.shakeAmp(0, 0), 0, 'no percent, no shake')
eq(L.shakeAmp(0, 1499), 0, 'a plain 14.99% hit does not shake')
eq(L.shakeAmp(0, 1500), 2, 'a plain 15% hit shakes by 2')
eq(L.shakeAmp(0, 3000), 3, '30% shakes by 3')
eq(L.shakeAmp(0, 5000), 4, '50% shakes by 4')
eq(L.shakeAmp(0, 10000), 4, 'never above the cap')
eq(L.shakeAmp(1, 299), 0, 'a small critical hit does not shake')
eq(L.shakeAmp(1, 300), 2, 'a critical hit of 3% shakes by 2')
eq(L.shakeAmp(2, 5000), 4, 'a big tick still counts as a big hit')
eq(L.shakeAmp(nil, 'x'), 0, 'junk -> none')
eq(L.shakeAmp(0, -5), 0, 'negative -> none')
eq(L.shakeAmp(0, 65535) <= L.SHAKE.maxPx, true, 'u16 maximum stays under the cap')

-- shake run: starts, falls off, ends, gap, a stronger hit restarts
local function const(v) return function() return v end end
local s = L.newShake()
eq(L.shakeStart(s, 1000, 0), false, 'no strength, no shake')
eq(L.shakeStart(s, 1000, 3), true, 'starts')
eq(L.shakeNow(s, 1000), 3, 'full strength at the start')
eq(L.shakeNow(s, 1090) <= 2, true, 'falls off halfway')
eq(L.shakeNow(s, 1179) >= 1, true, 'still 1 px at the very end')
eq(L.shakeNow(s, 1180), 0, 'over after 180 ms')
local x, y, done = L.shakeOffset(s, 1000, const(0.99))
eq(x, 3, 'offset x at the top of the roll')
eq(y, 3, 'offset y at the top of the roll')
eq(done, false, 'running')
x, y, done = L.shakeOffset(s, 1000, const(0))
eq(x, -3, 'offset x at the bottom of the roll')
x, y, done = L.shakeOffset(s, 1000, const(0.5))
eq(x ~= 0 or y ~= 0, true, 'a running frame is never a no-op')
x, y, done = L.shakeOffset(s, 1200, const(0.5))
eq(x, 0, 'no offset when over')
eq(done, true, 'reports done')
eq(L.shakeStart(s, 1100, 2), false, 'a weaker hit while running does not restart')
eq(L.shakeStart(s, 1100, 4), true, 'a stronger hit while running restarts')
eq(L.shakeNow(s, 1100), 4, 'at the new strength')
eq(L.shakeStart(s, 1100 + 180 + 50, 3), false, 'inside the gap after the last start')
eq(L.shakeStart(s, 1100 + 300, 3), true, 'after the gap')
eq(L.shakeStart(L.newShake(), 5, 99), true, 'a huge strength starts')
local capped = L.newShake()
L.shakeStart(capped, 0, 99)
eq(L.shakeNow(capped, 0), L.SHAKE.maxPx, 'a huge strength is capped')

-- the cap holds for every frame of a long run with random rolls
local r = L.newShake()
L.shakeStart(r, 0, 4)
local worst, seed = 0, 12345
local function rnd() seed = (seed * 1103515245 + 12345) % 2147483648; return seed / 2147483648 end
for t = 0, 400, 16 do
  local ox, oy = L.shakeOffset(r, t, rnd)
  worst = math.max(worst, math.abs(ox), math.abs(oy))
end
eq(worst <= L.SHAKE.maxPx, true, 'no frame goes over the cap')
eq(worst >= 1, true, 'the run moved the picture')

if fails > 0 then
  print(fails .. ' of ' .. checks .. ' checks failed')
  os.exit(1)
end
print('visualfx_test: ' .. checks .. ' checks ok')
