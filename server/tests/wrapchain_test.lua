-- ChaosWrapChain (data/scripts/chaos/wrapchain_core.lua): several scripts hook ChaosLeaderboard.record and the
-- achievement functions and install their hooks again every minute. Each hook must run once per call, also with a
-- wrapper of another kind on top (seasonpass.lua) and after a /reload of the wrapped script.
-- Run from server/: luajit tests/wrapchain_test.lua (and lua5.3).

local fails, checks = 0, 0
local function check(c, msg)
	checks = checks + 1
	if not c then
		fails = fails + 1
		print("FAIL " .. msg)
	end
end

dofile("data/scripts/chaos/wrapchain_core.lua")
local W = ChaosWrapChain

local LB = {calls = 0}
function LB.record(board, who, value)
	LB.calls = LB.calls + 1
	return {board = board, value = value}, "second"
end

local seen = {}
local function hook(flag, opts)
	return function()
		return W.wrap(LB, "record", flag, function(res, board)
			seen[flag] = (seen[flag] or 0) + 1
		end, nil, opts)
	end
end
local records, season, guild, mentor = hook("records"), hook("season"), hook("guild", {outer = true}), hook("mentor")

-- a foreign wrapper that wraps once by a flag (as seasonpass.lua)
local spSeen = 0
local function seasonpass()
	if not LB.spWrapped then
		LB.spWrapped = true
		local orig = LB.record
		LB.record = function(...)
			local a, b = orig(...)
			spSeen = spSeen + 1
			return a, b
		end
	end
end

-- load order, then the minute timers ten times, in a shuffled order
records(); season(); seasonpass(); guild(); mentor()
for i = 1, 10 do
	if i % 2 == 0 then
		mentor(); guild(); season(); records()
	else
		records(); season(); guild(); mentor()
	end
end
local e, s2 = LB.record("bounty", "x", 3)
check(e and e.value == 3 and s2 == "second", "both results through")
check(LB.calls == 1, "the original once")
for _, f in ipairs({"records", "season", "guild", "mentor"}) do
	check(seen[f] == 1, f .. " hook once per call (got " .. tostring(seen[f]) .. ")")
end
check(spSeen == 1, "the foreign wrapper once")
check(W.has(LB.record, "season") and not W.has(LB.record, "nobody"), "has")

-- a /reload of the leaderboard: a new function, every script hooks it again
LB.record = function(board, who, value) LB.calls = LB.calls + 1; return value end
LB.spWrapped = nil
seen, spSeen, LB.calls = {}, 0, 0
for _ = 1, 3 do
	records(); season(); seasonpass(); guild(); mentor()
end
check(LB.record("rift", "x", 7) == 7, "result after reload")
check(LB.calls == 1 and spSeen == 1, "original and foreign wrapper once after reload")
for _, f in ipairs({"records", "season", "guild", "mentor"}) do
	check(seen[f] == 1, f .. " once after reload (got " .. tostring(seen[f]) .. ")")
end

-- outer only: a nested call (the original calls record again) gives no guild hook for the inner call
local T = {}
local depthSeen = {}
function T.go(n)
	if n > 0 then
		T.go(n - 1)
	end
	return n
end
W.wrap(T, "go", "outer", function(res, n) depthSeen.outer = (depthSeen.outer or 0) + 1 end, nil, {outer = true})
W.wrap(T, "go", "all", function(res, n) depthSeen.all = (depthSeen.all or 0) + 1 end)
T.go(2)
check(depthSeen.outer == 1, "outer hook once for a nested call (got " .. tostring(depthSeen.outer) .. ")")
check(depthSeen.all == 3, "plain hook for every call (got " .. tostring(depthSeen.all) .. ")")

-- a failing hook and an error of the original
W.wrap(T, "go", "boom", function() error("boom") end, function() end)
check(T.go(0) == 0, "a failing hook never breaks the call")
local E = {}
function E.f() error("original failed", 0) end
W.wrap(E, "f", "x", function() end)
local ok, err = pcall(E.f)
check(not ok and err == "original failed", "the original's error passes through")
check(E.f ~= nil and pcall(function() return W.wrap(E, "f", "y", function() end) end), "hooks still added after an error")

print(string.format("wrapchain_test: %d checks, %d failures", checks, fails))
if fails > 0 then
	os.exit(1)
end
