-- luajit uifade_test.lua && lua5.3 uifade_test.lua (from anywhere; CI runs it from the repo root)
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'uifade_logic.lua')
local L = UiFadeLogic
local fails, checks = 0, 0
local function eq(a, b, what)
  checks = checks + 1
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end
local function near(a, b, what) eq(math.abs(a - b) < 1e-9, true, what .. ' (' .. tostring(a) .. ' vs ' .. tostring(b) .. ')') end

-- the brief: opens in 120-160 ms, closes quickly
eq(L.CFG.inMs >= 120 and L.CFG.inMs <= 160, true, 'open time 120-160 ms')
eq(L.CFG.outMs >= 80 and L.CFG.outMs <= 160, true, 'close time at most the open time')
eq(L.CFG.tickMs >= 10, true, 'timer not faster than 100 Hz')

-- eligibility
local ok = { on = true, className = 'UIWindow', topLevel = true, phantom = false, w = 300, h = 200 }
local function with(k, v) local t = {}; for a, b in pairs(ok) do t[a] = b end; t[k] = v; return t end
eq(L.eligible(ok), true, 'a plain window fades')
eq(L.eligible(with('on', false)), false, 'option off')
eq(L.eligible(with('on', nil)), false, 'option unknown is off')
eq(L.eligible(with('className', 'UIMiniWindow')), false, 'mini window')
eq(L.eligible(with('className', 'UIWidget')), false, 'plain widget')
eq(L.eligible(with('topLevel', false)), false, 'nested window')
eq(L.eligible(with('phantom', true)), false, 'phantom (tooltip)')
eq(L.eligible(with('noFade', true)), false, 'opt out')
eq(L.eligible(with('w', 100)), false, 'too narrow')
eq(L.eligible(with('h', 60)), false, 'too low')
eq(L.eligible(with('w', 140)), true, 'minimum width')
eq(L.eligible(with('w', 'x')), false, 'bad width')
eq(L.eligible(with('h', nil)), false, 'no height')
eq(L.eligible(nil), false, 'nil info')
eq(L.eligible('x'), false, 'string info')

-- fade in: 0 -> 1, never down, ends exactly at 1
do
  local st = L.begin('in', 1000)
  eq(st.kind, 'in', 'in kind')
  eq(st.ms, L.CFG.inMs, 'in time')
  local last = -1
  local done = false
  for t = 1000, 1000 + L.CFG.inMs + 40, 4 do
    local v, d = L.step(st, t)
    eq(v >= last, true, 'in is rising at ' .. t)
    eq(v >= 0 and v <= 1, true, 'in in range at ' .. t)
    last = v
    if d then done = true; eq(v, 1, 'in ends at 1'); break end
  end
  eq(done, true, 'in finishes')
  local st2 = L.begin('in', 0)
  local v0 = L.step(st2, 0)
  eq(v0, 0, 'in starts at 0')
  local vmid = L.step(st2, L.CFG.inMs / 2)
  eq(vmid > 0.5, true, 'ease-out is past half at half time')
  local vb, db = L.step(st2, -50)
  eq(vb, 0, 'clock before the start gives the start')
  eq(db, false, 'not done before the start')
end

-- fade out: 1 -> 0, never up, ends exactly at 0
do
  local st = L.begin('out', 500)
  eq(st.ms, L.CFG.outMs, 'out time')
  local last = 2
  local done = false
  for t = 500, 500 + L.CFG.outMs + 40, 4 do
    local v, d = L.step(st, t)
    eq(v <= last, true, 'out is falling at ' .. t)
    last = v
    if d then done = true; eq(v, 0, 'out ends at 0'); break end
  end
  eq(done, true, 'out finishes')
end

-- turning round: a close in the middle of an open starts from the opacity it has and takes only its share
do
  local a = L.begin('in', 0)
  local v = L.step(a, 70)                      -- about half way
  local b = L.begin('out', 70, v)
  eq(b.from, v, 'out starts where in stopped')
  eq(b.ms < L.CFG.outMs and b.ms >= L.CFG.minMs, true, 'out of a half-open window is shorter')
  local v1 = L.step(b, 70)
  near(v1, v, 'no jump at the turn')
  local c = L.begin('in', 100, 0.99)
  eq(c.ms, L.CFG.minMs, 'a sliver left still takes the minimum')
  local d = L.begin('out', 100, 0)
  eq(d.ms, L.CFG.minMs, 'closing a window at 0 takes the minimum')
  local _, dd = L.step(d, 100 + L.CFG.minMs)
  eq(dd, true, 'and finishes')
end

-- bad input never gives a bad opacity
do
  local st = L.begin('in', 0, 0 / 0)
  eq(st.from, 0, 'nan from -> 0')
  st = L.begin('out', 0, 7)
  eq(st.from, 1, 'from above 1 -> 1')
  st = L.begin('out', 0, -3)
  eq(st.from, 0, 'from below 0 -> 0')
  st = L.begin('weird', 0)
  eq(st.kind, 'out', 'unknown kind closes (the safe side: it ends hidden, not stuck half visible)')
  local v = L.step(L.begin('in', 0), 0 / 0)
  eq(v >= 0 and v <= 1, true, 'nan clock stays in range')
end

-- the widget is only touched when the rounded value changes
do
  local st = L.begin('in', 0)
  local touches, steps = 0, 0
  for t = 0, L.CFG.inMs + 16, 1 do
    local _, _, changed = L.step(st, t)
    steps = steps + 1
    if changed then touches = touches + 1 end
  end
  eq(touches <= L.CFG.steps + 2, true, 'at most one change per opacity step')
  eq(touches < steps, true, 'fewer touches than steps')
end

-- the whole open at 60 Hz is a handful of timer ticks
eq(math.ceil(L.CFG.inMs / L.CFG.tickMs) <= 10, true, 'an open is at most 10 ticks')

if fails > 0 then print(fails .. ' of ' .. checks .. ' checks failed'); os.exit(1) end
print('uifade_test: ' .. checks .. ' checks passed')
