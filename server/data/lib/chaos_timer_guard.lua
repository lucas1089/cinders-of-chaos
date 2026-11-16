-- Timer guard (O579; server/README.md "Timer guard"). The engine's addEvent runs a callback later, outside every script:
-- an error in it is printed as "Lua Script Error: [Main Interface] in a timer event called from: (Unknown scriptfile)" with
-- no word of which script it was (the first live run of 100 tester bots, 2026-11-15: 54 of them). The usual cause is
-- a Player / Creature / Item object kept in the callback's upvalue and used after a logout, a death or a removal.
--
-- ChaosTimerGuard.install() swaps the global addEvent for one that runs every callback under xpcall:
--   * a callback never throws into the engine (the timer simply ends, as it did after the error)
--   * the error is printed ONCE per callback (source file and line where the function is defined) with its stack
--     traceback, then at most once a minute per callback with the number of repeats:
--         [Chaos timer error] data/scripts/chaos/foo.lua:123: attempt to index a nil value (3 more since the last line)
--     The text has the word "error" (chaos-ctl.sh errors, the tester report and chaos_update.sh read it).
--   * the event id, stopEvent and the extra arguments are the engine's own; a callback that is not a function goes to
--     the engine untouched (its own error)
-- Idempotent: a second install does nothing. A script that keeps the engine's addEvent in a local before this loads
-- (`local rawAddEvent = addEvent`) must dofile this file first: _supports.lua, combatlog.lua and chaos_fx_owner.lua do.
-- ChaosTimerGuard.stats() -> {errors = total, sites = {["file:line"] = count}} for the tests and the staff.
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.

ChaosTimerGuard = ChaosTimerGuard or {}
local G = ChaosTimerGuard

G.QUIET_SECONDS = 60 -- the same callback is printed at most this often
G.sites = G.sites or {} -- "file:line" -> {count, last (os.time of the last line), muted (errors since then)}
G.errors = G.errors or 0

local unpack = table.unpack or unpack

-- where a callback was written: "data/scripts/chaos/foo.lua:123" ("?" for a C function)
function G.siteOf(callback)
	local ok, info = pcall(debug.getinfo, callback, "S")
	if not ok or type(info) ~= "table" then
		return "?"
	end
	return tostring(info.short_src or "?") .. ":" .. tostring(info.linedefined or 0)
end

-- one error of a callback: counts it and returns the line to print (with the traceback the first time), or nil while quiet
function G.note(site, message, trace, now)
	G.errors = G.errors + 1
	local s = G.sites[site]
	if not s then
		s = {count = 0, last = nil, muted = 0}
		G.sites[site] = s
	end
	s.count = s.count + 1
	if s.last and now - s.last < G.QUIET_SECONDS then
		s.muted = s.muted + 1
		return nil
	end
	local line = "[Chaos timer error] " .. site .. ": " .. tostring(message)
	if s.muted > 0 then
		line = line .. " (" .. s.muted .. " more since the last line)"
	elseif s.last == nil and trace then
		line = line .. "\n" .. tostring(trace)
	end
	s.last, s.muted = now, 0
	return line
end

-- the guarded version of a callback
function G.guard(callback)
	return function(...)
		local n, args = select("#", ...), {...}
		local ok, err = xpcall(function() return callback(unpack(args, 1, n)) end, function(e)
			return {message = e, trace = debug and debug.traceback and debug.traceback(tostring(e), 2) or nil}
		end)
		if not ok then
			local message = type(err) == "table" and err.message or err
			local trace = type(err) == "table" and err.trace or nil
			local line = G.note(G.siteOf(callback), message, trace, os.time())
			if line then
				print(line)
			end
		end
	end
end

function G.install()
	if G.installed or type(addEvent) ~= "function" then
		return false
	end
	local raw = addEvent
	G.raw = raw
	function addEvent(callback, delay, ...)
		if type(callback) ~= "function" then
			return raw(callback, delay, ...)
		end
		return raw(G.guard(callback), delay, ...)
	end
	G.installed = true
	return true
end

function G.stats()
	local sites = {}
	for site, s in pairs(G.sites) do
		sites[site] = s.count
	end
	return {errors = G.errors, sites = sites}
end

G.install()
