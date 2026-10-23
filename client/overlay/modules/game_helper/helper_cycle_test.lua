-- luajit helper_cycle_test.lua && lua5.3 helper_cycle_test.lua (from the repository root or this folder)
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'helper_cycle.lua')
local C = ChaosHelperCycle
local fails = 0
local function eq(a, b, what)
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

-- a scheduler that keeps its queue: fire() runs the oldest event once
local function newScheduler()
  local s = { queue = {}, delays = {} }
  s.schedule = function(fn, ms)
    local ev = { fn = fn, ms = ms }
    function ev:cancel() self.dead = true end
    s.queue[#s.queue + 1] = ev
    s.delays[#s.delays + 1] = ms
    return ev
  end
  function s.fire()
    local ev = table.remove(s.queue, 1)
    if ev and not ev.dead then ev.fn() end
    return ev
  end
  return s
end

-- one run per fire, the next one scheduled after the callback: a stall cannot queue a burst
local s = newScheduler()
local runs = 0
local h = C.new(s.schedule, function() runs = runs + 1 end, 50)
eq(#s.queue, 1, 'one event waits')
for _ = 1, 10 do s.fire() end
eq(runs, 10, 'ten fires, ten runs')
eq(#s.queue, 1, 'still exactly one event waiting (no backlog)')
eq(s.delays[#s.delays], 50, 'the interval is kept')

-- a failing callback does not stop the cycle, and the error is reported
local errors = 0
s = newScheduler()
local n = 0
h = C.new(s.schedule, function() n = n + 1 error('boom') end, 50, function() errors = errors + 1 end)
s.fire() s.fire() s.fire()
eq(n, 3, 'the cycle goes on after an error')
eq(errors, 3, 'each error is reported')

-- cancel before and after a run
s = newScheduler()
runs = 0
h = C.new(s.schedule, function() runs = runs + 1 end, 50)
s.fire()
h:cancel()
s.fire()
eq(runs, 1, 'cancel stops the next run')
eq(h.canceled, true, 'the handle says canceled')

-- cancel from inside the callback: no further event
s = newScheduler()
local hh
hh = C.new(s.schedule, function() hh:cancel() end, 50)
s.fire()
eq(#s.queue, 0, 'a cancel inside the callback leaves nothing scheduled')

if fails > 0 then os.exit(1) end
print('helper_cycle_test: ok')
