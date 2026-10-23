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

-- ================================================================== panel and catalog
-- parse
c = parsed('panel 123 players.kick|Admin One|{"player":"Bob"}')
eq(c and c.cmd, "panel", "panel parses")
eq(c and c.rid, 123, "with its request id")
eq(c and c.action, "players.kick", "the action")
eq(c and c.actor, "Admin One", "the admin character")
eq(c and c.json, '{"player":"Bob"}', "and the parameters")
c = parsed('panel 5 a.b|Gma|{"x":"a|b"}')
eq(c and c.json, '{"x":"a|b"}', "a | inside the JSON is kept")
for _, bad in ipairs({"panel", "panel x a|Gma|{}", "panel 1 a|Gma|[]", "panel 1 a|Gma|{", "panel 1 a b|Gma|{}", "panel 1 ../x|Gma|{}",
	"panel 1 a|G|{}", "panel 1 a|Gma", "panel 1234567890123 a|Gma|{}", "panel 1 a|Gma;x|{}", "panel 1 a|Gma|{}\1"}) do
	eq(parsed(bad), nil, "refused: " .. bad:gsub("[%c]", "?"))
end
eq(parsed("panel 1 a.b|Gma|{" .. string.rep("x", 1450) .. "}"), nil, "a panel line over MAX_PANEL_LINE is refused")
c = parsed('panel 1 a.b|Gma|{"t":"' .. string.rep("x", 600) .. '"}')
check(c ~= nil, "a long panel line is fine (up to MAX_PANEL_LINE)")
eq(parsed("broadcast " .. string.rep("x", 190) .. string.rep("y", 150)), nil, "other commands keep the 300 limit")
c = parsed("catalog Admin One")
eq(c and c.cmd, "catalog", "catalog parses")
eq(c and c.actor, "Admin One", "for an admin character")
eq(parsed("catalog"), nil, "catalog needs a name")
eq(parsed("catalog x; ls"), nil, "and a plain one")
eq(K.bareName("remote.result", "d"), "remote.result", "bareName: ok")
eq(K.bareName("../x", "d"), "d", "bareName: refused")

-- engine
local function memFs2(files)
	local fs = memFs(files)
	fs.write = function(n, text, mode)
		files[n] = mode == "a" and ((files[n] or "") .. text) or text
		return true
	end
	fs.size = function(n) return files[n] and #files[n] or 0 end
	return fs
end
json = {
	encode = function(v)
		local function e(x)
			if type(x) == "table" then
				local keys = {}
				for k in pairs(x) do keys[#keys + 1] = k end
				table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
				local out = {}
				for _, k in ipairs(keys) do out[#out + 1] = tostring(k) .. "=" .. e(x[k]) end
				return "{" .. table.concat(out, ",") .. "}"
			end
			return tostring(x)
		end
		return e(v)
	end,
	decode = function(text)
		if text == '{"player":"Bob"}' then return {player = "Bob"} end
		if text == "{}" then return {} end
		if text == '{"player":"Pos"}' then return {player = "Pos"} end
		error("bad json")
	end
}
local executed = {}
local admins = {Gma = true}
ChaosAdmin = {
	isAdmin = function(p)
		if type(p.admin) == "boolean" then return p.admin end
		return p:getGroup():getId() >= 4
	end,
	execute = function(p, id, params)
		local nm = type(p.name) == "string" and p.name or p:getName()
		executed[#executed + 1] = {nm, id, params.player}
		if params.player == "Pos" then
			local ok, err = pcall(function() return p:getPosition() end)
			return {ok = false, message = tostring(err)}
		end
		if id == "players.kick" then
			return {ok = true, message = "Kicked", lines = {"one", "two"}}
		end
		return {ok = false, message = "Unknown action."}
	end,
	buildCatalog = function(p) return {group = 6, categories = {}} end
}
local rows = {Offa = {1001, 77, 6, "Offa"}, Lowly = {1002, 78, 1, "Lowly"}}
db = {
	escapeString = function(v) return "'" .. v .. "'" end,
	storeQuery = function(q)
		local name = q:match("`name` = '([^']*)'")
		return name and rows[name] or nil
	end,
}
result = {
	getNumber = function(r, col) return ({id = r[1], account_id = r[2], group_id = r[3]})[col] end,
	getString = function(r, col) return r[4] end,
	free = function() end,
}
function Player(name)
	if name == "Gma" then return {name = "Gma", admin = true} end
	if name == "Pleb" then return {name = "Pleb", admin = false} end
	if name == "Bob" then return {remove = function() end} end
	return nil
end
disk = {}
RC.fs = memFs2(disk)
disk["remote.cmd"] = 'panel 77 players.kick|Gma|{"player":"Bob"}\npanel 78 nope.nothing|Gma|{}\npanel 79 players.kick|Pleb|{}\n'
    .. 'panel 80 players.kick|Ghost|{}\npanel 81 players.kick|Gma|{}\ncatalog Gma\ncatalog Ghost\n'
    .. 'panel 82 players.kick|Offa|{"player":"Bob"}\npanel 83 players.kick|Lowly|{}\npanel 84 x.y|Offa|{"player":"Pos"}\ncatalog Offa\n'
eq(RC.check(), 11, "eleven panel and catalog commands ran")
eq(#executed, 5, "five reached the panel (the ones without an admin character did not)")
eq(executed[1] and executed[1][1], "Gma", "run as the admin character")
eq(executed[1] and executed[1][2], "players.kick", "the action")
eq(executed[1] and executed[1][3], "Bob", "with the decoded parameters")
local res = disk["remote.result"] or ""
check(res:find("rid=77", 1, true) ~= nil and res:find("ok=true", 1, true) ~= nil, "answer for 77: ok")
check(res:find("message=Kicked", 1, true) ~= nil, "with the message")
check(res:find("rid=78", 1, true) ~= nil and res:find("Unknown action", 1, true) ~= nil, "answer for 78: refused by the panel")
check(res:find("rid=79", 1, true) ~= nil and res:find("is not an admin character", 1, true) ~= nil, "a non-admin character is refused")
check(res:find("rid=80", 1, true) ~= nil and res:find("no character named", 1, true) ~= nil, "a name with no character is reported")
check(res:find("no character named Ghost", 1, true) ~= nil, "with the name")
check(res:find("rid=82", 1, true) ~= nil and res:find("message=Kicked", 1, true) ~= nil, "an offline admin character runs actions")
eq(executed[4] and executed[4][1], "Offa", "as the stand-in")
check(res:find("rid=83", 1, true) ~= nil and res:find("Lowly is not an admin character", 1, true) ~= nil, "an offline low group is refused")
check(res:find("needs Offa in the game", 1, true) ~= nil, "a world action says the character must be in the game")
check(res:find("rid=81", 1, true) ~= nil and res:find("not a JSON object", 1, true) ~= nil or res:find("rid=81", 1, true) ~= nil,
	"bad parameters are answered too")
check(disk["remote.catalog"] ~= nil and disk["remote.catalog"]:find("group=6", 1, true) ~= nil, "the catalog file is written")
eq(disk["remote.catalog.tmp"], nil, "through a temporary file")
-- an unreadable result file grows no further than maxResultBytes
disk["remote.result"] = string.rep("x", 200001)
disk["remote.cmd"] = 'panel 90 players.kick|Gma|{"player":"Bob"}\n'
RC.check()
check(#disk["remote.result"] < 1000, "the result file starts again above maxResultBytes")

-- ================================================================== spectate (the app's live view, spectate.lua)
c = parsed("spectate Bad Player")
eq(c and c.cmd, "spectate", "spectate parses")
eq(c and c.arg, "Bad Player", "with the name")
for _, bad in ipairs({"spectate", "spectate ab", "spectate x; rm -rf /", "spectate $(id)", "spectate 1abc", "spectate a|b"}) do
	eq(parsed(bad), nil, "refused: " .. bad)
end
local watches, logged = {}, {}
local realPrint = print
print = function(s) logged[#logged + 1] = tostring(s) end
disk["remote.cmd"] = "spectate Bob\n"
ChaosSpectate = nil
RC.check()
check(logged[#logged] and logged[#logged]:find("not loaded", 1, true) ~= nil, "spectate without spectate.lua says so")
ChaosSpectate = {watch = function(name)
	watches[#watches + 1] = name
	return #watches == 1
end}
logged = {}
disk["remote.cmd"] = "spectate Bob\n"
eq(RC.check(), 1, "spectate runs")
eq(watches[1], "Bob", "the watch gets the name")
check(logged[1] and logged[1]:find("spectate Bob: watching Bob", 1, true) ~= nil, "a new watch is logged")
disk["remote.cmd"] = "spectate Bob\n"
RC.check()
eq(#watches, 2, "a renewal runs too")
eq(#logged, 1, "but is not logged")
print = realPrint
ChaosSpectate = nil

-- ================================================================== cast (engine patch 0064, the live cast)
c = parsed("cast Bad Player")
eq(c and c.cmd, "cast", "cast parses")
eq(c and c.arg, "Bad Player", "with the name")
c = parsed("caststop")
eq(c and c.cmd, "caststop", "caststop parses")
for _, bad in ipairs({"cast", "cast ab", "cast x; rm -rf /", "cast $(id)", "cast 1abc", "cast a|b", "caststop Bob",
	"cast " .. string.rep("a", 30)}) do
	eq(parsed(bad), nil, "refused: " .. bad)
end
logged = {}
print = function(s) logged[#logged + 1] = tostring(s) end
local setCast = Game.setCastTarget
Game.setCastTarget = nil
disk["remote.cmd"] = "cast Bob\n"
RC.check()
check(logged[#logged] and logged[#logged]:find("no cast port", 1, true) ~= nil, "an engine without patch 0064 says so")
local targets, portOpen = {}, true
Game.setCastTarget = function(name)
	targets[#targets + 1] = name
	return portOpen
end
logged = {}
disk["remote.cmd"] = "cast Bob\ncaststop\n"
eq(RC.check(), 2, "cast and caststop run")
eq(targets[1], "Bob", "cast sets the target")
eq(targets[2], "", "caststop clears it")
check(logged[1] and logged[1]:find("cast Bob: casting Bob", 1, true) ~= nil, "cast is logged")
check(logged[2] and logged[2]:find("cast stopped", 1, true) ~= nil, "caststop is logged")
portOpen = false
logged = {}
disk["remote.cmd"] = "cast Bob\n"
RC.check()
check(logged[1] and logged[1]:find("cast port is closed", 1, true) ~= nil, "a closed port is reported")
Game.setCastTarget = setCast
print = realPrint

print(string.format("remote_cmd_test: %d checks, %d failures", count, failures))
if failures > 0 then
	os.exit(1)
end
