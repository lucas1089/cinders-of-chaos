-- game_visualfx: the pulse on an action bar slot when its cooldown ends (O229, base patch 0161). Pure logic with no engine
-- calls, tested by cooldownpulse_test.lua. The base action bar calls ChaosCooldownPulse.onEnd(button, duration, elapsed) from
-- removeCooldown (the timer of a cooldown has run out); this file decides whether that is a pulse and how bright it is.
CooldownPulseLogic = {}
local L = CooldownPulseLogic

L.DURATION = 280      -- ms, the whole pulse
L.RISE = 40           -- ms, the flash reaches its peak this fast, then fades out
L.PEAK = 0.55         -- opacity of the pale layer at the peak
L.MIN_COOLDOWN = 3000 -- ms, shorter cooldowns (the global exhaust of a rotation) would flash all the time
L.TOLERANCE = 150     -- ms, the timer may fire this early; a slot cleared earlier (drag, change) is no pulse
L.MAX_ALIVE = 24      -- pulses at once (every slot of three bars); more are dropped

-- a cooldown that ran its course: long enough, and at (or just before) its end
function L.shouldPulse(duration, elapsed)
  if type(duration) ~= 'number' or type(elapsed) ~= 'number' then return false end
  if duration < L.MIN_COOLDOWN then return false end
  return duration - elapsed <= L.TOLERANCE
end

-- opacity of the layer t ms after the start: a short rise, then a squared fall to 0 at DURATION
function L.opacity(t)
  if type(t) ~= 'number' or t < 0 or t >= L.DURATION then return 0 end
  if t < L.RISE then return L.PEAK * t / L.RISE end
  local k = 1 - (t - L.RISE) / (L.DURATION - L.RISE)
  return L.PEAK * k * k
end

-- the pulses alive: key -> start time. A key that pulses again restarts.
function L.newTracker()
  return { starts = {}, count = 0 }
end

-- false when dropped (too many alive)
function L.start(tr, key, now)
  if tr.starts[key] == nil then
    if tr.count >= L.MAX_ALIVE then return false end
    tr.count = tr.count + 1
  end
  tr.starts[key] = now
  return true
end

-- opacities now: { [key] = opacity } of the pulses still running; the finished ones are removed and listed in the second
-- result so the caller can destroy their widgets
function L.step(tr, now)
  local live, done = {}, {}
  for key, t0 in pairs(tr.starts) do
    local a = L.opacity(now - t0)
    if now - t0 >= L.DURATION then
      done[#done + 1] = key
    else
      live[key] = a
    end
  end
  for _, key in ipairs(done) do tr.starts[key] = nil; tr.count = tr.count - 1 end
  return live, done
end

function L.remove(tr, key)
  if tr.starts[key] ~= nil then tr.starts[key] = nil; tr.count = tr.count - 1 end
end

function L.active(tr)
  return tr.count > 0
end
