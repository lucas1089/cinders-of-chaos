-- Run from the server/ folder: luajit tests/stop_request_test.lua (or lua5.3; CI runs both)
-- Graceful stop by file: stop_request_core.lua (file name check, poll), stop_request.lua against a mocked engine
-- (broadcast, save, shutdown once; a file that cannot be removed stops nothing; a leftover at startup is removed), a
-- real file in a temporary folder, and the package scripts that write the file.
local failures, count = 0, 0
local function check(cond, label)
	count = count + 1
	if not cond then
		failures = failures + 1
		print("FAIL " .. label)
	end
end
local function eq(a, b, label)
	check(a == b, label .. " (" .. tostring(a) .. " ~= " .. tostring(b) .. ")")
end

-- ================================================================== the core
dofile("data/scripts/chaos/stop_request_core.lua")
local K = ChaosStopRequestCore
eq(K.fileName({file = "stop.request"}), "stop.request", "the configured name")
eq(K.fileName({file = "halt_now-1"}), "halt_now-1", "another bare name")
for _, bad in ipairs({"../stop.request", "/tmp/stop.request", "C:\\stop.request", "a/b", "..", ".hidden", "",
	"stop request", "stop;rm -rf", "stop$(x)", "x\nstop", string.rep("a", 65), 42}) do
	eq(K.fileName({file = bad}), "stop.request", "not a bare name: the default (" .. tostring(bad):gsub("\n", "\\n") .. ")")
end
eq(K.fileName(nil), "stop.request", "no config: the default")

local function memFs(files, removable)
	return {
		exists = function(n) return files[n] == true end,
		remove = function(n)
			if removable == false then
				return false
			end
			files[n] = nil
			return true
		end
	}
end
local files = {}
eq(K.poll(memFs(files), "stop.request"), "none", "no file: nothing")
files["stop.request"] = true
eq(K.poll(memFs(files), "stop.request"), "stop", "a file: stop")
eq(files["stop.request"], nil, "and it is removed")
files["stop.request"] = true
eq(K.poll(memFs(files, false), "stop.request"), "stuck", "a file that cannot be removed: no stop")
local sticky = {exists = function() return true end, remove = function() return true end}
eq(K.poll(sticky, "stop.request"), "stuck", "removed but still there: no stop")

-- real files (a temporary folder; the name is a bare name inside it)
local tmp = os.tmpname()
os.remove(tmp)
local real = K.realFs()
eq(real.exists(tmp), false, "real: no file")
local f = io.open(tmp, "wb")
f:write("ignored content; rm -rf /")
f:close()
eq(real.exists(tmp), true, "real: the file is seen")
eq(K.poll(real, tmp), "stop", "real: stop")
eq(real.exists(tmp), false, "real: removed")

-- ================================================================== the engine file
local events, broadcasts, saves, shutdowns, pending = {}, {}, 0, 0, {}
GAME_STATE_SHUTDOWN, GAME_STATE_CLOSED, GAME_STATE_NORMAL, MESSAGE_STATUS_WARNING = 4, 5, 1, 18
local gameState = GAME_STATE_NORMAL
Game = {
	getGameState = function() return gameState end,
	setGameState = function(s)
		gameState = s
		if s == GAME_STATE_SHUTDOWN then
			shutdowns = shutdowns + 1
		end
	end,
	broadcastMessage = function(text, kind) broadcasts[#broadcasts + 1] = {text, kind} end
}
function saveServer() saves = saves + 1 end
function addEvent(fn, ms, ...) pending[#pending + 1] = {fn = fn, ms = ms, args = {...}} end
GlobalEvent = function(name)
	local ev = {name = name}
	function ev:interval(ms) self.ms = ms end
	function ev:register() events[self.name] = self end
	return ev
end
Chaos = {}
local disk = {["stop.request"] = true}
ChaosStopRequest = {fs = memFs(disk)}
dofile("data/scripts/chaos/stop_request.lua")
local SR = ChaosStopRequest
check(events.ChaosStopRequest ~= nil and events.ChaosStopRequestStartup ~= nil, "startup and poll registered")
eq(events.ChaosStopRequest.ms, 2500, "polls every 2.5 s")
events.ChaosStopRequestStartup.onStartup()
eq(disk["stop.request"], nil, "a leftover request at startup is removed, not obeyed")
eq(shutdowns, 0, "no stop from a leftover")
events.ChaosStopRequest.onThink(2500)
eq(#broadcasts, 0, "no file: nothing")
disk["stop.request"] = true
events.ChaosStopRequest.onThink(2500)
eq(disk["stop.request"], nil, "the request file is removed")
eq(#broadcasts, 1, "everyone is told")
eq(broadcasts[1] and broadcasts[1][2], MESSAGE_STATUS_WARNING, "as a warning")
eq(saves, 0, "the save waits for the grace time")
eq(#pending, 1, "one shutdown scheduled")
eq(pending[1] and pending[1].ms, 3000, "after graceMs")
disk["stop.request"] = true
eq(SR.check(), "busy", "a second request while stopping is ignored")
pending[1].fn()
eq(saves, 1, "saved")
eq(shutdowns, 1, "shut down")
eq(SR.check(), "busy", "after the shutdown: nothing more")

-- a request whose file cannot be removed stops nothing
SR.stopping, gameState, saves, shutdowns, pending, broadcasts = nil, GAME_STATE_NORMAL, 0, 0, {}, {}
SR.fs = memFs({["stop.request"] = true}, false)
eq(SR.check(), "stuck", "cannot be removed")
eq(#pending + saves + shutdowns + #broadcasts, 0, "and nothing happens")

-- ================================================================== the package scripts
local function src(path)
	local h = io.open(path, "r")
	local t = h and h:read("*a") or ""
	if h then
		h:close()
	end
	return t
end
local bat = src("../tools/windows/package/stop-server.bat")
check(bat:find('> "%~dp0server\\stop.request"', 1, true) ~= nil, "stop-server.bat writes server\\stop.request")
check(bat:find("goto stopdb", 1, true) ~= nil, "stop-server.bat still waits for the exit before the database")
local start = src("../tools/windows/package/start-server.bat")
check(start:find('del /q "%ROOT%server\\stop.request"', 1, true) ~= nil, "start-server.bat removes a leftover request")
local sh = src("../tools/linux/server/stop-server.sh")
check(sh:find('local req="$ROOT/server/stop.request"', 1, true) ~= nil and sh:find(': > "$req"', 1, true) ~= nil,
	"stop-server.sh writes server/stop.request")
check(sh:find("kill -TERM", 1, true) ~= nil, "stop-server.sh keeps the signal as fallback")
local ssh = src("../tools/linux/server/start-server.sh")
check(ssh:find('rm -f "$ROOT/server/stop.request"', 1, true) ~= nil, "start-server.sh removes a leftover request")

print(string.format("stop_request_test: %d checks, %d failures", count, failures))
if failures > 0 then
	os.exit(1)
end
