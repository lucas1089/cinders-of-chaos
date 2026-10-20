-- Run from the server/ folder: luajit tests/remote_cmd_test.lua (or lua5.3; CI runs both)
-- Remote admin commands by file: remote_cmd_core.lua (file name, line whitelist, taking the file) and remote_cmd.lua
-- against a mocked engine (each command runs once, refused lines run nothing, a leftover at startup is removed), and a
-- real file in a temporary folder.
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
dofile("data/scripts/chaos/remote_cmd_core.lua")
local K = ChaosRemoteCmdCore
eq(K.fileName({file = "remote.cmd"}), "remote.cmd", "the configured name")
for _, bad in ipairs({"../remote.cmd", "/tmp/x", "a/b", "..", ".hidden", "", "a b", "x;y", string.rep("a", 65), 42}) do
	eq(K.fileName({file = bad}), "remote.cmd", "not a bare name: the default")
end
eq(K.fileName(nil), "remote.cmd", "no config: the default")

local function parsed(line)
	local c, why = K.parse(line)
	return c, why
end
local c = parsed("broadcast Server restarts in 5 minutes")
eq(c and c.cmd, "broadcast", "broadcast parses")
eq(c and c.arg, "Server restarts in 5 minutes", "with its text")
c = parsed("  KICK   Bad Player  \r")
eq(c and c.cmd, "kick", "commands are case blind, spaces trimmed")
eq(c and c.arg, "Bad Player", "kick keeps the name")
for _, one in ipairs({"save", "open", "close"}) do
	c = parsed(one)
	eq(c and c.cmd, one, one .. " parses")
end
for _, bad in ipairs({"", "   ", "save now", "open x", "broadcast", "broadcast " .. string.rep("x", 201), "kick", "kick ab",
	"kick x; rm -rf /", "kick $(id)", "kick 1abc", "kick a\1b", "rm -rf /", "shutdown", "lua print(1)", "broadcast a\0b",
	string.rep("a", 301), 42}) do
	local r = parsed(bad)
	eq(r, nil, "refused: " .. tostring(bad):gsub("[%c]", "?"):sub(1, 40))
end
-- a "z" in a broadcast must not be taken for a control character class (Lua 5.3 has no %z)
c = parsed("broadcast zzz Zorro")
eq(c and c.arg, "zzz Zorro", "letters z are fine")

local cmds, refused = K.parseAll("broadcast hi\nkick Bob\nbogus\n\nsave\n")
eq(#cmds, 3, "three good lines")
eq(#refused, 1, "one refused line")
local many = {}
for i = 1, 30 do
	many[i] = "save"
end
cmds, refused = K.parseAll(table.concat(many, "\n"))
eq(#cmds, K.MAX_LINES, "at most MAX_LINES commands per file")
eq(#refused, 1, "the rest is reported once")

-- taking the file
local function memFs(files, renamable)
	return {
		exists = function(n) return files[n] ~= nil end,
		rename = function(a, b)
			if renamable == false then
				return false
			end
			files[b], files[a] = files[a], nil
			return true
		end,
		read = function(n) return files[n] end,
		remove = function(n) files[n] = nil return true end
	}
end
local files = {}
eq(K.take(memFs(files), "remote.cmd"), nil, "no file: nothing")
files["remote.cmd"] = "save\n"
eq(K.take(memFs(files), "remote.cmd"), "save\n", "the text comes back")
check(files["remote.cmd"] == nil and files["remote.cmd.work"] == nil, "and no file is left")
files["remote.cmd"] = "save\n"
local t, why = K.take(memFs(files, false), "remote.cmd")
eq(t, nil, "cannot be renamed: nothing taken")
eq(why, "stuck", "reported as stuck")

-- a real file
local tmp = os.tmpname()
os.remove(tmp)
local real = K.realFs()
eq(real.exists(tmp), false, "real: no file")
local f = io.open(tmp, "wb")
f:write("broadcast hello\nsave\n")
f:close()
eq(K.take(real, tmp), "broadcast hello\nsave\n", "real: taken")
eq(real.exists(tmp), false, "real: removed")
eq(real.exists(tmp .. ".work"), false, "real: no work file left")

-- ================================================================== the engine file
local events, broadcasts, saves, states, kicked = {}, {}, 0, {}, {}
MESSAGE_STATUS_WARNING, GAME_STATE_NORMAL, GAME_STATE_CLOSED = 18, 1, 5
Game = {
	broadcastMessage = function(text, kind) broadcasts[#broadcasts + 1] = {text, kind} end,
	setGameState = function(s) states[#states + 1] = s end
}
function saveServer() saves = saves + 1 end
function Player(name)
	if name == "Bob" then
		return {remove = function() kicked[#kicked + 1] = "Bob" end}
	end
	return nil
end
GlobalEvent = function(name)
	local ev = {name = name}
	function ev:interval(ms) self.ms = ms end
	function ev:register() events[self.name] = self end
	return ev
end
Chaos = {}
local disk = {["remote.cmd"] = "save\n"}
ChaosRemoteCmd = {fs = memFs(disk)}
dofile("data/scripts/chaos/remote_cmd.lua")
local RC = ChaosRemoteCmd
check(events.ChaosRemoteCmd ~= nil and events.ChaosRemoteCmdStartup ~= nil, "startup and poll registered")
eq(events.ChaosRemoteCmd.ms, 2500, "polls every 2.5 s")
events.ChaosRemoteCmdStartup.onStartup()
eq(disk["remote.cmd"], nil, "a leftover file at startup is removed, not obeyed")
eq(saves, 0, "nothing ran from a leftover")
eq(RC.check(), 0, "no file: nothing")
disk["remote.cmd"] = "broadcast Back soon\nkick Bob\nkick Nobody\nsave\nclose\nopen\nrm -rf /\n"
eq(RC.check(), 6, "six commands ran")
eq(#broadcasts, 1, "one broadcast")
eq(broadcasts[1] and broadcasts[1][1], "Back soon", "with the text")
eq(broadcasts[1] and broadcasts[1][2], MESSAGE_STATUS_WARNING, "as a warning")
eq(#kicked, 1, "only the player who is online is kicked")
eq(saves, 1, "saved once")
eq(states[1], GAME_STATE_CLOSED, "closed")
eq(states[2], GAME_STATE_NORMAL, "opened")
eq(disk["remote.cmd"], nil, "the file is gone")
eq(RC.check(), 0, "and it runs once")

-- a handler that errors does not stop the next command
function saveServer() error("boom") end
disk["remote.cmd"] = "save\nbroadcast after\n"
RC.check()
eq(#broadcasts, 2, "the next command still ran")

-- stuck: nothing runs
disk = {["remote.cmd"] = "save\n"}
RC.fs = memFs(disk, false)
saves = 0
eq(RC.check(), 0, "cannot be renamed: nothing runs")
eq(saves, 0, "no save")

print(string.format("remote_cmd_test: %d checks, %d failures", count, failures))
if failures > 0 then
	os.exit(1)
end
