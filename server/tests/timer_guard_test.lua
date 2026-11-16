-- Run from the server/ folder: luajit tests/timer_guard_test.lua (and lua5.3; CI runs both)
-- Timer guard (O579; data/lib/chaos_timer_guard.lua, data/scripts/chaos/timer_guard.lua). The first live run of 100 tester bots
-- (2026-11-15) logged 54 "Lua Script Error: [Main Interface] in a timer event called from: (Unknown scriptfile)": a callback
-- of addEvent threw (a Player / Creature / Item kept in an upvalue and used after a logout or a death) and the engine named no
-- script. The guard runs every callback under xpcall and prints the file and line of the callback once.
-- Checks: install swaps addEvent once; arguments and the event id are the engine's; a callback that errors never throws; the
-- line names the file:line the callback was written at, with the traceback the first time; the same callback is quiet for a
-- minute and then says how many it held back; a callback that is not a function goes to the engine untouched; the scripts that keep
-- the engine's addEvent in a local load the guard first.

local checks, failures = 0, 0
local function check(cond, label)
	checks = checks + 1
	if not cond then
		failures = failures + 1
		io.stdout:write("FAIL " .. label .. "\n")
	end
end
local function eq(a, b, label)
	check(a == b, label .. " (" .. tostring(a) .. " ~= " .. tostring(b) .. ")")
end

-- the engine's addEvent: remembers what it was given, runs nothing by itself
local queue, nextId = {}, 100
local rawCalls = 0
function addEvent(callback, delay, ...)
	rawCalls = rawCalls + 1
	nextId = nextId + 1
	queue[#queue + 1] = {fn = callback, delay = delay, args = {...}, n = select("#", ...), id = nextId}
	return nextId
end
local engineAddEvent = addEvent

local printed = {}
local realPrint = print
print = function(...)
	local parts = {}
	for i = 1, select("#", ...) do
		parts[#parts + 1] = tostring(select(i, ...))
	end
	printed[#printed + 1] = table.concat(parts, " ")
end
local function run(entry)
	return pcall(entry.fn, (table.unpack or unpack)(entry.args, 1, entry.n))
end

dofile("data/lib/chaos_timer_guard.lua")
local G = ChaosTimerGuard

check(G.installed == true, "installed by the load")
check(addEvent ~= engineAddEvent, "the global addEvent is the guarded one")
eq(G.raw, engineAddEvent, "the engine's own function is kept")
eq(G.install(), false, "a second install does nothing")
dofile("data/lib/chaos_timer_guard.lua")
local guarded = addEvent
eq(G.install(), false, "a reload of the file does not wrap it again")
check(addEvent == guarded, "still the same wrapper")

-- the event id and the arguments are the engine's own
local got
local id = addEvent(function(a, b, c) got = {a, b, c} end, 250, 1, nil, "x")
eq(id, nextId, "the event id of the engine comes back (stopEvent works)")
local entry = queue[#queue]
eq(entry.delay, 250, "the delay is passed")
eq(entry.n, 3, "three extra arguments")
local ok = run(entry)
check(ok and got[1] == 1 and got[2] == nil and got[3] == "x", "the callback gets its arguments, holes included")

-- a callback that errors never throws
local line = debug.getinfo(1, "l").currentline + 1
local function broken() local creature = nil; return creature:getName() end
addEvent(broken, 0)
entry = queue[#queue]
local before = #printed
ok = run(entry)
check(ok, "a callback that errors does not throw into the engine")
eq(#printed, before + 1, "one line printed")
local text = printed[#printed]
check(text:find("^%[Chaos timer error%] ") ~= nil, "it starts with the tag the log readers know (it has the word error)")
check(text:find("timer_guard_test.lua:" .. line, 1, true) ~= nil, "it names the file and the line the callback was written at (" .. text:sub(1, 120) .. ")")
check(text:find("stack traceback", 1, true) ~= nil, "the first one carries the traceback")
eq(G.stats().errors, 1, "counted")
eq(G.stats().sites[G.siteOf(broken)], 1, "per callback")

-- quiet for a minute, then it says how many it held back
local site = G.siteOf(broken)
for _ = 1, 4 do
	run(entry)
end
eq(#printed, before + 1, "the same callback is not printed again at once")
eq(G.stats().errors, 5, "but every error is counted")
local t0 = G.sites[site].last
eq(G.note(site, "x", nil, t0 + G.QUIET_SECONDS - 1), nil, "still quiet just before the minute")
local again = G.note(site, "later", nil, t0 + G.QUIET_SECONDS)
check(again and again:find("later", 1, true) and again:find("(5 more since the last line)", 1, true), "after the minute: the line, with the held back count")
check(again and not again:find("stack traceback", 1, true), "without a second traceback")
check(G.note("other.lua:1", "m", "tb", t0) ~= nil, "another callback is printed at once")

-- an error that is not a string, an error with no message
addEvent(function() error({code = 7}) end, 0)
check(run(queue[#queue]), "an error object does not throw either")
addEvent(function() error() end, 0)
check(run(queue[#queue]), "an error with no value does not throw")

-- a callback that returns values: ignored, no problem
addEvent(function() return 1, 2, 3 end, 0)
check(run(queue[#queue]), "return values do not matter")

-- not a function: the engine gets it as it is (and answers with its own error)
local rawBefore = rawCalls
addEvent("not a function", 10)
eq(queue[#queue].fn, "not a function", "a string goes to the engine untouched")
eq(rawCalls, rawBefore + 1, "through the engine")

-- a callback that stops its own timer chain: the next addEvent inside a callback is guarded too
local inner
addEvent(function()
	addEvent(function() inner = "ran" end, 5)
end, 0)
run(queue[#queue])
local nested = queue[#queue]
check(nested.fn ~= nil and run(nested) and inner == "ran", "a timer started by a timer is guarded and runs")

-- the scripts that keep the engine's addEvent in a local load the guard first
local function slurp(path)
	local f = assert(io.open(path, "r"))
	local s = f:read("*a")
	f:close()
	return s
end
for _, path in ipairs({"data/lib/chaos_fx_owner.lua", "data/scripts/chaos/combatlog.lua", "data/spells/chaos/_supports.lua"}) do
	local s = slurp(path)
	local a = s:find("chaos_timer_guard.lua", 1, true)
	local b = s:find("local rawAddEvent = addEvent", 1, true)
	check(a and b and a < b, path .. ": the guard is loaded before the engine's addEvent is kept")
end
local glue = slurp("data/scripts/chaos/timer_guard.lua")
check(glue:find('dofile("data/lib/chaos_timer_guard.lua")', 1, true) and glue:find("ChaosTimerGuard.install()", 1, true),
	"the revscript loads the lib and installs it")

print = realPrint
print(string.format("timer_guard_test: %d checks, %d failures", checks, failures))
os.exit(failures == 0 and 0 or 1)
