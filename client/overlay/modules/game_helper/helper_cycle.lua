-- ChaosHelperCycle: the helper's tick timer without a replay of missed cycles (pure; tests: helper_cycle_test.lua).
-- Chaos base patch 0026 for the former helper, kept here: the engine's cycleEvent puts each run at "last scheduled time +
-- interval", so after a long frame (a big window built, a module reload) it ran every missed cycle back to back: about
-- 50 helper ticks after a 2.5 s stall, each one free to cast before the server's cooldown packets came back, and the
-- server kicked the player for sending too many packets. Here the next run is scheduled from the time the callback ran:
-- after a stall it runs once (catches up at most one cycle) and then keeps its interval. handle:cancel() stops it, and
-- removeEvent(handle) does the same in the client.
ChaosHelperCycle = ChaosHelperCycle or {}
local C = ChaosHelperCycle

-- schedule(fn, ms) -> an event with :cancel(); callback runs in pcall; onError(err) is told about a failure and the cycle
-- goes on
function C.new(schedule, callback, interval, onError)
  local handle = {}
  local pending = nil
  local function run()
    pending = nil
    if handle.canceled then
      return
    end
    local ok, err = pcall(callback)
    if not ok and onError then
      pcall(onError, err)
    end
    if not handle.canceled then
      pending = schedule(run, interval)
    end
  end
  function handle:cancel()
    self.canceled = true
    if pending then
      pending:cancel()
      pending = nil
    end
  end
  pending = schedule(run, interval)
  return handle
end

return ChaosHelperCycle
