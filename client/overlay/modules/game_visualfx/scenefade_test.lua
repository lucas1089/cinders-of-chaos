-- luajit scenefade_test.lua && lua5.3 scenefade_test.lua (from anywhere; CI runs it from the repo root)
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'scenefade_logic.lua')
dofile(dir .. 'visualfx_logic.lua')
local S, C = SceneFadeLogic, SceneFadeLogic.CFG
local fails, checks = 0, 0
local function eq(a, b, what)
  checks = checks + 1
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end
local function P(x, y, z) return { x = x, y = y, z = z } end

-- classify
eq(S.classify(P(100, 100, 7), P(101, 100, 7)), nil, 'a step is a walk')
eq(S.classify(P(101, 101, 7), P(100, 100, 7)), nil, 'a diagonal step is a walk')
eq(S.classify(P(103, 100, 7), P(100, 100, 7)), nil, 'a push of 3 tiles is not a teleport')
eq(S.classify(P(104, 100, 7), P(100, 100, 7)), 'portal', 'four tiles is a teleport')
eq(S.classify(P(100, 96, 7), P(100, 100, 7)), 'portal', 'four tiles in y too')
eq(S.classify(P(100, 100, 6), P(100, 100, 7)), 'floor', 'stairs up')
eq(S.classify(P(101, 100, 8), P(100, 100, 7)), 'floor', 'a hole down, one tile aside')
eq(S.classify(P(100, 100, 9), P(100, 100, 7)), 'portal', 'two floors at once')
eq(S.classify(P(300, 100, 6), P(100, 100, 7)), 'portal', 'far and another floor')
eq(S.classify(nil, P(1, 1, 7)), nil, 'no new position')
eq(S.classify(P(1, 1, 7), nil), nil, 'no old position (login)')
eq(S.classify({}, {}), nil, 'junk')

-- trigger and level
local s = S.new()
S.reset(s, 10000)
eq(S.trigger(s, 10500, 'floor'), false, 'quiet after a game start')
eq(S.trigger(s, 10000 + C.quietMs, 'floor'), true, 'after the quiet time a floor change fades')
local t0 = 10000 + C.quietMs
eq(S.level(s, t0), math.floor(C.floorStart * C.steps + 0.5) / C.steps, 'starts at the floor level')
eq(S.level(s, t0 + C.floorMs), 0, 'clear after floorMs')
eq(S.level(s, t0 + C.floorMs + 1000), 0, 'and stays clear')
local prev = 2
for ms = 0, C.floorMs, 11 do
  local v = S.level(s, t0 + ms)
  eq(v <= prev, true, 'never rises while it clears at ' .. ms)
  eq(v >= 0 and v <= C.maxLevel, true, 'inside 0..max at ' .. ms)
  prev = v
end
eq(S.level(s, t0 + C.floorMs / 2) < C.floorStart / 2 + 0.03, true, 'eases out: under half the start at half the time')

-- a portal is stronger and longer; a weaker trigger never shortens a running one
S.reset(s, 0)
local t = C.quietMs
eq(S.trigger(s, t, 'portal'), true, 'portal fades')
eq(S.level(s, t) > S.level(s, t + 1) - 1e-9, true, 'portal starts dark')
eq(S.level(s, t + C.floorMs) > 0, true, 'still up at the floor time')
eq(S.level(s, t + C.portalMs), 0, 'clear after portalMs')
local before = S.level(s, t + 100)
eq(S.trigger(s, t + 100, 'floor'), true, 'a floor change inside a portal fade')
eq(S.level(s, t + 100) >= before - 1e-9, true, 'does not make it clearer')
eq(S.level(s, t + C.portalMs - 100) > 0, true, 'ends no earlier than the portal fade')
eq(S.level(s, t + C.portalMs), 0, 'and ends with it')
eq(S.trigger(s, t + 5, 'walk'), false, 'an unknown kind does nothing')
eq(S.trigger(s, t + 5, nil), false, 'nil kind does nothing')

-- the cap
local old = C.portalStart
C.portalStart = 5
S.reset(s, 0)
S.trigger(s, C.quietMs, 'portal')
eq(S.level(s, C.quietMs) <= C.maxLevel, true, 'never darker than maxLevel')
C.portalStart = old

-- step: the widget is touched only when the level changes
S.reset(s, 0)
S.trigger(s, C.quietMs, 'floor')
local touches, done, now = 0, false, C.quietMs
while not done and now < C.quietMs + 2000 do
  local _, changed, over = S.step(s, now)
  if changed then touches = touches + 1 end
  done = over
  now = now + C.tickMs
end
eq(done, true, 'the fade ends')
eq(touches <= C.steps + 1, true, 'at most one widget update per level step')
eq(touches >= 4, true, 'and a visible number of them')
local _, ch, over = S.step(s, now + 100)
eq(ch, false, 'no change once clear'); eq(over, true, 'still over')

-- option and wiring
eq(VisualFxLogic.DEFAULTS.sceneFade, true, 'the scene fade is on by default')
eq(VisualFxLogic.optionOn('sceneFade', nil), true, 'default when unset')
eq(VisualFxLogic.optionOn('sceneFade', false), false, 'off is kept')
do
  local f = io.open(dir .. 'visualfx.lua', 'r')
  local src = f and f:read('*a') or ''
  if f then f:close() end
  eq(src:find("name == 'sceneFade'", 1, true) ~= nil, true, 'onOption handles sceneFade')
  eq(src:find("optionValue('sceneFade')", 1, true) ~= nil, true, 'the option value is read')
  eq(src:find('SceneFadeLogic', 1, true) ~= nil, true, 'the logic is used')
  local o = io.open(dir .. 'game_visualfx.otmod', 'r')
  local mod = o and o:read('*a') or ''
  if o then o:close() end
  eq(mod:find('scenefade_logic', 1, true) ~= nil, true, 'the logic file is loaded by the module')
end

if fails > 0 then
  print(fails .. ' of ' .. checks .. ' checks failed')
  os.exit(1)
end
print('scenefade_test: ' .. checks .. ' checks ok')
