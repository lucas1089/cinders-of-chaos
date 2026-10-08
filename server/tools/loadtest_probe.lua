-- TEST ONLY: never ship this file. It is not under server/data, so install_all.py never copies it.
-- Load-test probe for server/tools/loadtest.py: measures how late the engine runs a timer (the dispatcher / scheduler
-- lag, i.e. how far behind the game loop is) and prints one line every 5 seconds to the console:
--   [loadtest-probe] t=<unix time> players=<online> lag_avg_ms=<mean> lag_max_ms=<worst> samples=<n>
-- A 50 ms timer that fires on time has lag 0; with a busy game loop every task waits in the queue and the lag grows.
-- Use: copy to <server>/data/scripts/zz_loadtest_probe.lua, restart the server (or /reload scripts), run the load test
-- with --server-log pointing at the console log, then DELETE the copy and restart again.
local INTERVAL_MS = 50
local REPORT_MS = 5000

local function now()
	return os.mtime and os.mtime() or os.time() * 1000
end

local stats = {n = 0, sum = 0, max = 0, since = 0}

local function tick(expected)
	local t = now()
	local lag = math.max(0, t - expected)
	stats.n, stats.sum = stats.n + 1, stats.sum + lag
	if lag > stats.max then
		stats.max = lag
	end
	if t - stats.since >= REPORT_MS then
		print(string.format("[loadtest-probe] t=%d players=%d lag_avg_ms=%.1f lag_max_ms=%d samples=%d", os.time(),
			#Game.getPlayers(), stats.sum / math.max(1, stats.n), stats.max, stats.n))
		stats.n, stats.sum, stats.max, stats.since = 0, 0, 0, t
	end
	addEvent(tick, INTERVAL_MS, t + INTERVAL_MS)
end

local start = GlobalEvent("ChaosLoadTestProbe")
function start.onStartup()
	stats.since = now()
	addEvent(tick, INTERVAL_MS, now() + INTERVAL_MS)
	print("[loadtest-probe] running (TEST ONLY, remove data/scripts/zz_loadtest_probe.lua before going live)")
	return true
end
start:register()
