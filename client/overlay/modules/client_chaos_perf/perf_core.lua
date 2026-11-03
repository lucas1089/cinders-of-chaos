-- perf_core.lua: the pure part of the performance overlay (client_chaos_perf, O376). No engine calls; the module
-- passes in clocks, samples and debug.getinfo. Tested by perf_core_test.lua (luajit and lua5.3, from the repo root).
--   stats: min, max, avg, median, p5, p95 of a list (nearest rank)
--   probe: the gap between two ticks of a short timer = how long the main loop was blocked (worst frame)
--   timer: wraps callbacks of scheduleEvent / cycleEvent / addEvent / extended opcodes, sums time per module
--   recording: one sample a second for 60 s, then a CSV and a text summary
ChaosPerfCore = {}
local C = ChaosPerfCore

C.WINDOW_S = 10     -- the overlay shows the last 10 seconds
C.RECORD_S = 60     -- one record
C.PROBE_MS = 10     -- the stall probe's timer
C.TOP = 15          -- modules in the summary
C.MAX_WINDOWS = 40  -- window ids kept per sample
-- avg FPS for "good" and the lowest 5 % for "ok"; a phone draws a smaller screen at a lower target
C.TARGET = { pc = { good = 60, low = 30 }, phone = { good = 30, low = 20 } }
-- frames of these modules are skipped when a callback is attributed (helpers of the engine's Lua and this module)
C.SKIP = { corelib = true, gamelib = true, modulelib = true, client_chaos_perf = true }

local floor = math.floor

local function num(v) return tonumber(v) or 0 end

-- ---------------------------------------------------------------- stats
function C.sorted(values)
  local out = {}
  for _, v in ipairs(values or {}) do
    local n = tonumber(v)
    if n and n == n then out[#out + 1] = n end
  end
  table.sort(out)
  return out
end

-- nearest rank: the smallest value with at least p percent of the list at or below it
function C.percentile(sorted, p)
  local n = #sorted
  if n == 0 then return 0 end
  local k = math.ceil((tonumber(p) or 0) / 100 * n)
  if k < 1 then k = 1 end
  if k > n then k = n end
  return sorted[k]
end

function C.stats(values)
  local s = C.sorted(values)
  local n = #s
  if n == 0 then return { n = 0, min = 0, max = 0, avg = 0, median = 0, p5 = 0, p95 = 0 } end
  local sum = 0
  for i = 1, n do sum = sum + s[i] end
  return { n = n, min = s[1], max = s[n], avg = sum / n, median = C.percentile(s, 50), p5 = C.percentile(s, 5),
    p95 = C.percentile(s, 95) }
end

-- keeps the last `max` items of a list (oldest first)
function C.pushLast(list, item, max)
  list[#list + 1] = item
  while #list > (max or C.WINDOW_S) do table.remove(list, 1) end
  return list
end

-- ---------------------------------------------------------------- stall probe
function C.newProbe() return { last = nil, worst = 0, ticks = 0 } end

-- a tick of the probe timer at `now` ms; the gap to the previous tick is how long the main loop did not come back
function C.probeTick(p, now)
  now = num(now)
  if p.last then
    local gap = now - p.last
    if gap > p.worst then p.worst = gap end
    p.ticks = p.ticks + 1
  end
  p.last = now
end

-- the worst gap since the last take (0 without two ticks), then starts over
function C.probeTake(p)
  local w = p.worst
  p.worst, p.ticks = 0, 0
  return w
end

-- the probe was stopped (window closed): the next tick must not count the pause
function C.probeReset(p) p.last, p.worst, p.ticks = nil, 0, 0 end

-- what the overlay shows from the last samples ({fps, gfx, cpu, gap})
function C.overlay(samples)
  local fps, gaps, gfx, cpu = {}, {}, {}, {}
  for _, s in ipairs(samples or {}) do
    fps[#fps + 1] = num(s.fps)
    gaps[#gaps + 1] = num(s.gap)
    if s.gfx then gfx[#gfx + 1] = num(s.gfx) end
    if s.cpu then cpu[#cpu + 1] = num(s.cpu) end
  end
  local f, g = C.stats(fps), C.stats(gaps)
  local last = samples and samples[#samples] or {}
  return {
    fps = floor(num(last.fps) + 0.5), fpsAvg = f.avg, fpsMin = f.min,
    frameAvgMs = f.avg > 0 and 1000 / f.avg or 0, frameWorstMs = g.max,
    gfx = #gfx > 0 and floor(C.stats(gfx).avg + 0.5) or nil, cpu = #cpu > 0 and floor(C.stats(cpu).avg + 0.5) or nil,
    seconds = #(samples or {}),
  }
end

-- ---------------------------------------------------------------- attribution
-- "@/modules/game_dpsmeter/dpsmeter.lua" -> "game_dpsmeter"; mods/ too; nil for anything else
function C.moduleOfSource(src)
  src = tostring(src or ''):gsub('\\', '/'):gsub('^@', '')
  return src:match('/modules/([^/]+)/') or src:match('^modules/([^/]+)/') or src:match('/mods/([^/]+)/')
end

-- the first module up the stack from `level` that is not a helper (C.SKIP); '?' when none
function C.callerModule(getinfo, level)
  for l = level or 3, (level or 3) + 12 do
    local ok, info = pcall(getinfo, l, 'S')
    if not ok or not info then break end
    local m = C.moduleOfSource(info.source)
    if m and not C.SKIP[m] then return m end
  end
  return '?'
end

-- ---------------------------------------------------------------- timer
-- clock() gives microseconds; traceback(err) the message an error leaves with
function C.newProfile() return { mods = {}, calls = 0, us = 0 } end

function C.newTimer(clock, traceback)
  return { on = false, depth = 0, profile = C.newProfile(), clock = clock, traceback = traceback or tostring }
end

function C.addCost(p, mod, kind, us)
  us = num(us)
  if us < 0 then us = 0 end
  local m = p.mods[mod]
  if not m then
    m = { name = mod, us = 0, calls = 0, worstUs = 0, kinds = {} }
    p.mods[mod] = m
  end
  m.us = m.us + us
  m.calls = m.calls + 1
  if us > m.worstUs then m.worstUs = us end
  m.kinds[kind] = (m.kinds[kind] or 0) + us
  p.calls = p.calls + 1
  p.us = p.us + us
end

-- the n costliest modules: {name, us, calls, worstUs, kind (the kind with the most time)}
function C.topModules(p, n)
  local list = {}
  for _, m in pairs(p and p.mods or {}) do
    local best, bestUs = '', -1
    for k, us in pairs(m.kinds) do
      if us > bestUs or (us == bestUs and k < best) then best, bestUs = k, us end
    end
    list[#list + 1] = { name = m.name, us = m.us, calls = m.calls, worstUs = m.worstUs, kind = best }
  end
  table.sort(list, function(a, b)
    if a.us ~= b.us then return a.us > b.us end
    return a.name < b.name
  end)
  while #list > (n or C.TOP) do table.remove(list) end
  return list
end

-- a callback that adds its time to `mod` while timer.on. Off: one test, then the callback. A callback called from
-- inside another timed one is not timed again (its time is in the outer one). An error goes on with its traceback.
function C.wrap(timer, fn, mod, kind)
  if type(fn) ~= 'function' then return fn end
  local function done(t0, ok, ...)
    timer.depth = timer.depth - 1
    if not ok then error((...), 0) end
    if timer.on then C.addCost(timer.profile, mod, kind, timer.clock() - t0) end
    return ...
  end
  return function(...)
    if not timer.on or timer.depth > 0 then return fn(...) end
    timer.depth = timer.depth + 1
    return done(timer.clock(), xpcall(fn, timer.traceback, ...))
  end
end

function C.startTimer(timer)
  timer.profile = C.newProfile()
  timer.depth = 0
  timer.on = true
end

function C.stopTimer(timer) timer.on = false end

-- ---------------------------------------------------------------- recording
function C.newRecording(startMs, seconds)
  return { start = num(startMs), seconds = seconds or C.RECORD_S, samples = {}, windows = {}, done = false }
end

-- s = {t, fps, gfx, cpu, gap, luaKb, creatures, windows = {ids}}; true when the record is full
function C.addSample(rec, s)
  local row = { t = num(s.t) - rec.start, fps = num(s.fps), gfx = s.gfx and num(s.gfx) or nil,
    cpu = s.cpu and num(s.cpu) or nil, gap = num(s.gap), luaKb = num(s.luaKb),
    creatures = s.creatures and num(s.creatures) or nil, windows = {} }
  local seen = {}
  for _, id in ipairs(s.windows or {}) do
    id = tostring(id)
    if not seen[id] and #row.windows < C.MAX_WINDOWS then
      seen[id] = true
      row.windows[#row.windows + 1] = id
      rec.windows[id] = (rec.windows[id] or 0) + 1
    end
  end
  table.sort(row.windows)
  rec.samples[#rec.samples + 1] = row
  if #rec.samples >= rec.seconds then rec.done = true end
  return rec.done
end

-- 'good' | 'ok' | 'low' against the target of the platform
function C.verdict(fpsAvg, fpsP5, mobile)
  local t = mobile and C.TARGET.phone or C.TARGET.pc
  fpsAvg, fpsP5 = num(fpsAvg), num(fpsP5)
  if fpsAvg >= t.good * 0.95 and fpsP5 >= t.low then return 'good' end
  if fpsAvg >= t.low and fpsP5 >= t.low * 0.5 then return 'ok' end
  return 'low'
end

function C.summarize(rec, profile, mobile)
  local fps, gfx, cpu, gaps, lua, cr = {}, {}, {}, {}, {}, {}
  for _, s in ipairs(rec.samples) do
    fps[#fps + 1] = s.fps
    gaps[#gaps + 1] = s.gap
    lua[#lua + 1] = s.luaKb
    if s.gfx then gfx[#gfx + 1] = s.gfx end
    if s.cpu then cpu[#cpu + 1] = s.cpu end
    if s.creatures then cr[#cr + 1] = s.creatures end
  end
  local n = #rec.samples
  local f = C.stats(fps)
  local first, last = rec.samples[1], rec.samples[n]
  local spanS = (n > 1) and (last.t - first.t) / 1000 or 0
  local growth = 0
  if spanS > 0 then growth = (last.luaKb - first.luaKb) / spanS * 60 end
  local wins = {}
  for id, secs in pairs(rec.windows) do wins[#wins + 1] = { id = id, seconds = secs } end
  table.sort(wins, function(a, b)
    if a.seconds ~= b.seconds then return a.seconds > b.seconds end
    return a.id < b.id
  end)
  local seconds = math.max(n, 1)
  local top = C.topModules(profile, C.TOP)
  for _, m in ipairs(top) do
    m.msPerS = m.us / 1000 / seconds
    m.share = m.us / (seconds * 1e6) * 100
  end
  return {
    seconds = n, fps = f, gfx = #gfx > 0 and C.stats(gfx) or nil, cpu = #cpu > 0 and C.stats(cpu) or nil,
    frameAvgMs = f.avg > 0 and 1000 / f.avg or 0, gap = C.stats(gaps), lua = C.stats(lua),
    luaStart = first and first.luaKb or 0, luaEnd = last and last.luaKb or 0, luaGrowthKbPerMin = growth,
    creatures = #cr > 0 and C.stats(cr) or nil, windows = wins, top = top,
    luaTotalMs = profile and profile.us / 1000 or 0, luaCalls = profile and profile.calls or 0,
    verdict = C.verdict(f.avg, f.p5, mobile), mobile = mobile and true or false,
  }
end

local function csvCell(v)
  if v == nil then return '' end
  v = tostring(v)
  if v:find('[",\n]') then v = '"' .. v:gsub('"', '""') .. '"' end
  return v
end

function C.csv(rec)
  local out = { 'second,fps,graphics_fps,processing_fps,frame_ms,worst_gap_ms,lua_kb,creatures,windows' }
  for i, s in ipairs(rec.samples) do
    out[#out + 1] = table.concat({
      csvCell(i), csvCell(s.fps), csvCell(s.gfx), csvCell(s.cpu),
      csvCell(s.fps > 0 and ('%.1f'):format(1000 / s.fps) or ''), csvCell(floor(s.gap + 0.5)),
      csvCell(floor(s.luaKb + 0.5)), csvCell(s.creatures), csvCell(table.concat(s.windows, ' ')),
    }, ',')
  end
  return table.concat(out, '\n') .. '\n'
end

-- the text summary. info = {stamp, version, os, screen, clock, profiled ('start'|'record'|'off'), modules,
-- chaosModules, stats (engine lines)}
function C.report(sum, info)
  info = info or {}
  local L = {}
  local function add(fmt, ...) L[#L + 1] = fmt:format(...) end
  local t = sum.mobile and C.TARGET.phone or C.TARGET.pc
  local function int(v) return floor(num(v) + 0.5) end
  add('Cinders of Chaos client performance record (O376)')
  add('when: %s  client: %s  os: %s  phone: %s  screen: %s', tostring(info.stamp or '?'), tostring(info.version or '?'),
    tostring(info.os or '?'), sum.mobile and 'yes' or 'no', tostring(info.screen or '?'))
  add('seconds: %d  modules loaded: %d (%d Chaos)', int(sum.seconds), int(info.modules), int(info.chaosModules))
  add('verdict: %s (target avg %d FPS, lowest 5%% at least %d)', sum.verdict, t.good, t.low)
  add('')
  add('FPS: avg %.1f  min %d  p5 %d  median %d  max %d', sum.fps.avg, int(sum.fps.min), int(sum.fps.p5), int(sum.fps.median), int(sum.fps.max))
  if sum.gfx then add('graphics FPS: avg %.1f  min %d', sum.gfx.avg, int(sum.gfx.min)) end
  if sum.cpu then add('processing FPS: avg %.1f  min %d', sum.cpu.avg, int(sum.cpu.min)) end
  add('frame time: avg %.1f ms (from FPS)', sum.frameAvgMs)
  add('main loop stall (worst gap of a %d ms timer per second): worst %d ms  p95 %d ms  median %d ms', C.PROBE_MS,
    int(sum.gap.max), int(sum.gap.p95), int(sum.gap.median))
  add('Lua memory: start %d KB  end %d KB  max %d KB  growth %.0f KB/min', int(sum.luaStart), int(sum.luaEnd), int(sum.lua.max),
    sum.luaGrowthKbPerMin)
  if sum.creatures then add('creatures on screen: avg %.1f  max %d', sum.creatures.avg, int(sum.creatures.max)) end
  add('')
  add('open windows (seconds visible of %d):', int(sum.seconds))
  if #sum.windows == 0 then add('  none') end
  for i, w in ipairs(sum.windows) do
    if i > 25 then add('  ... %d more', #sum.windows - 25) break end
    add('  %s %d', w.id, int(w.seconds))
  end
  add('')
  if info.profiled == 'off' or #sum.top == 0 and num(sum.luaCalls) == 0 then
    add('Lua time per module: not measured (%s)', info.profiled == 'off' and 'timing not available' or 'no timed callback ran')
  else
    add('Lua time per module (timers, cycle events, extended opcodes; clock %s):', tostring(info.clock or '?'))
    if info.profiled == 'record' then
      add('  only callbacks registered during the record; for every cycle event tick "Time Lua per module from client start" and restart')
    end
    add('  total %.1f ms in %d calls (%.2f ms per second)', sum.luaTotalMs, int(sum.luaCalls), sum.luaTotalMs / math.max(sum.seconds, 1))
    for i, m in ipairs(sum.top) do
      add('  %2d. %-28s %8.1f ms  %6.2f ms/s  %5.2f%%  calls %6d  worst %6.1f ms  mostly %s', i, m.name, m.us / 1000,
        m.msPerS, m.share, int(m.calls), m.worstUs / 1000, m.kind)
    end
  end
  if info.stats and #info.stats > 0 then
    add('')
    add('engine timings (g_stats):')
    for _, line in ipairs(info.stats) do add('  %s', tostring(line)) end
  end
  return table.concat(L, '\n') .. '\n'
end

-- {year, month, day, hour, min, sec} (os.date('*t')) -> '20261103-142501'
function C.stamp(d)
  d = type(d) == 'table' and d or {}
  return ('%04d%02d%02d-%02d%02d%02d'):format(num(d.year), num(d.month), num(d.day), num(d.hour), num(d.min), num(d.sec))
end

-- the files of a record: chaos-* names are kept by the client's write folder clean-up (cleanup_core.lua keepName)
function C.fileNames(stamp)
  return '/chaos-perf-' .. stamp .. '.csv', '/chaos-perf-' .. stamp .. '.txt'
end

return C
