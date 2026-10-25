-- luajit grademood_test.lua && lua5.3 grademood_test.lua (from anywhere; CI runs it from the repo root)
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'grademood_logic.lua')
local G = GradeMoodLogic
local fails, checks = 0, 0
local function eq(a, b, what)
  checks = checks + 1
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end
local function near(a, b, what) eq(math.abs(a - b) < 1e-9, true, what .. ' (' .. tostring(a) .. ' ~ ' .. tostring(b) .. ')') end

-- presets: the five kinds of the server, all gentle (dark fantasy, not neon)
for _, k in ipairs({ 'ice', 'swamp', 'desert', 'fire', 'crypt' }) do
  local p = G.PRESETS[k]
  eq(type(p), 'table', 'preset ' .. k)
  for _, key in ipairs({ 'r', 'g', 'b' }) do eq(math.abs(p[key]) <= 0.04, true, k .. ' tint ' .. key .. ' is gentle') end
  eq(math.abs(p.sat) <= 0.10, true, k .. ' saturation change is gentle')
  eq(math.abs(p.con) <= 0.03, true, k .. ' contrast change is gentle')
end
local n = 0
for _ in pairs(G.PRESETS) do n = n + 1 end
eq(n, 5, 'no other preset')
-- the direction of each mood
eq(G.PRESETS.ice.b > G.PRESETS.ice.r, true, 'ice is blue')
eq(G.PRESETS.swamp.g > G.PRESETS.swamp.r and G.PRESETS.swamp.g > G.PRESETS.swamp.b, true, 'swamp is green')
eq(G.PRESETS.desert.r > G.PRESETS.desert.b and G.PRESETS.desert.g > G.PRESETS.desert.b, true, 'desert is amber')
eq(G.PRESETS.fire.r > G.PRESETS.fire.g and G.PRESETS.fire.g >= G.PRESETS.fire.b, true, 'fire is warm')
eq(G.PRESETS.crypt.sat < 0, true, 'crypt loses colour')
eq(G.PRESETS.crypt.sat < G.PRESETS.ice.sat and G.PRESETS.crypt.sat < G.PRESETS.swamp.sat, true, 'crypt is the most desaturated')

-- names and messages
eq(G.kindOf('ice'), 'ice', 'known name'); eq(G.kindOf('neon'), nil, 'unknown name'); eq(G.kindOf(5), nil, 'number'); eq(G.kindOf(nil), nil, 'nil')
eq(G.kindOf('__index'), nil, 'a table key that is not a preset')
eq(G.parseKind({ action = 'set', data = { k = 'none', m = 'crypt' } }), 'crypt', 'message with a mood')
eq(G.parseKind({ action = 'set', data = { k = 'none' } }), nil, 'message without a mood')
eq(G.parseKind({ action = 'other', data = { m = 'crypt' } }), nil, 'another action')
eq(G.parseKind({ action = 'set' }), nil, 'no data'); eq(G.parseKind('x'), nil, 'junk')

-- a new state is the plain grade
local s = G.new()
local v = G.values(s, 5000)
for _, key in ipairs(G.KEYS) do eq(v[key], 0, 'neutral ' .. key) end
eq(G.settled(s, 0), false, 'a new state has not settled at t0') -- t0 = 0, ms = 2000
eq(G.settled(s, 2000), true, 'settled after the ease')

-- an ease: starts at the plain grade, ends at the preset, monotonic, smooth ends
local now = 10000
eq(G.setKind(s, now, 'fire'), true, 'a new mood starts')
eq(G.setKind(s, now + 10, 'fire'), false, 'the same mood again does nothing')
v = G.values(s, now)
eq(v.r, 0, 'starts at the plain grade')
v = G.values(s, now + 1000)
near(v.r, G.PRESETS.fire.r / 2, 'half way after half the time')
v = G.values(s, now + 2000)
near(v.r, G.PRESETS.fire.r, 'there after 2 s'); near(v.con, G.PRESETS.fire.con, 'contrast there')
eq(G.settled(s, now + 2000), true, 'settled'); eq(G.settled(s, now + 1999), false, 'not yet')
v = G.values(s, now + 9000)
near(v.r, G.PRESETS.fire.r, 'stays')
local last = -1
for t = 0, 2000, 33 do
  local x = G.values(s, now + t).r
  eq(x >= last, true, 'rising at ' .. t); last = x
end
local early = G.values(s, now + 100).r
eq(early < G.PRESETS.fire.r * 0.05, true, 'a soft start (smoothstep)')

-- a change in the middle of an ease starts from what is shown: no jump
local before = G.values(s, now + 3000) -- settled on fire
eq(G.setKind(s, now + 3000, 'ice'), true, 'fire to ice')
local at = G.values(s, now + 3000)
for _, key in ipairs(G.KEYS) do near(at[key], before[key], 'no jump at the change ' .. key) end
local mid = G.values(s, now + 3000 + 700)
eq(G.setKind(s, now + 3700, 'crypt'), true, 'ice to crypt half way')
local after = G.values(s, now + 3700)
for _, key in ipairs(G.KEYS) do near(after[key], mid[key], 'no jump half way ' .. key) end
-- walking along a border (fire, none, fire, none ...) never leaves the range between the two presets
local b = G.new()
G.snap(b, 0, nil)
local t = 20000
local hi = 0
for i = 1, 40 do
  G.setKind(b, t, (i % 2 == 1) and 'fire' or nil)
  t = t + 150
  local x = G.values(b, t).r
  eq(x >= 0 and x <= G.PRESETS.fire.r + 1e-9, true, 'inside the range while flickering over a border')
  if x > hi then hi = x end
end
eq(hi < G.PRESETS.fire.r, true, 'a quick flicker never reaches the full mood')

-- leaving: back to the plain grade
local e = G.new()
G.snap(e, 0, 'swamp')
eq(G.setKind(e, 5000, nil), true, 'out of the swamp')
near(G.values(e, 5000).g, G.PRESETS.swamp.g, 'starts from the swamp')
near(G.values(e, 7000).g, 0, 'ends at the plain grade')
eq(G.setKind(e, 7000, nil), false, 'none to none')
eq(G.setKind(e, 7001, 'bogus'), false, 'an unknown name is none, which it already is')

-- snap
local sn = G.new()
G.snap(sn, 100, 'crypt')
near(G.values(sn, 100).sat, G.PRESETS.crypt.sat, 'snap shows the preset at once')
eq(G.settled(sn, 100), true, 'snap is settled')
G.snap(sn, 100, nil)
eq(G.values(sn, 100).sat, 0, 'snap to none')

-- values are on the grid, and differ() sees a change only at the grid
local g1 = G.values(s, now + 3333)
for _, key in ipairs(G.KEYS) do
  local x = g1[key] * G.GRID
  near(x, math.floor(x + 0.5), 'on the grid ' .. key)
end
eq(G.differ(nil, g1), true, 'nothing sent yet differs')
eq(G.differ(g1, { r = g1.r, g = g1.g, b = g1.b, sat = g1.sat, con = g1.con }), false, 'same values')
eq(G.differ(g1, { r = g1.r + 0.001, g = g1.g, b = g1.b, sat = g1.sat, con = g1.con }), true, 'one step')
-- the timer's work: about 61 steps for an ease, and the engine call only when something moved
local d, calls, shown = G.new(), 0, nil
G.setKind(d, 0, 'desert')
for tt = 0, 2100, G.STEP_MS do
  local x = G.values(d, tt)
  if G.differ(shown, x) then calls = calls + 1; shown = x end
end
eq(calls <= 66, true, 'at most one engine call per tick')
eq(calls >= 20, true, 'and a visible ease')

if fails > 0 then print(fails .. ' of ' .. checks .. ' checks failed'); os.exit(1) end
print('grademood: all ' .. checks .. ' checks passed')
