-- Run from the server/ folder: luajit tests/reload_file_test.lua (CI runs it with LuaJIT and Lua 5.3)
-- Reload one config table (reload_file_core.lua, reload_file_config.lua, the panel action server.reload_file;
-- server/README.md "Reload one config table (O312)"):
--   * names: only a bare config file name of the config folder is accepted, no path, no shell or Lua metacharacter
--   * a script file is refused with the way to reload it, a restart-only config says so
--   * the dofile wrapper remembers the tables of data/scripts/chaos/*_config.lua, once per table, others not
--   * a reload copies new values into the live table (identity kept, nested tables too), removes keys the file lost,
--     adds new ones, and changes nothing when the file has an error, returns no table or has no live copy
--   * the panel action runs it and the real shipped configs load, track and reload without a change
local checks, fails = 0, 0
local function ok(cond, what)
	checks = checks + 1
	if not cond then fails = fails + 1; print("FAIL " .. tostring(what)) end
end
local function eq(a, b, what) ok(a == b, what .. ": " .. tostring(a) .. " ~= " .. tostring(b)) end

local n = 0
setmetatable(_G, {__index = function(t, k)
	if type(k) == "string" and k:match("^[A-Z_0-9]+$") then n = n + 1; rawset(t, k, n); return n end
end})

dofile("data/scripts/chaos/chaos_constants.lua")
local R = ChaosReloadFile
ok(R ~= nil, "chaos_constants.lua loads ChaosReloadFile")
ok(R.installed, "the dofile wrapper is installed")
ok(dofile ~= R.realDofile, "dofile is the wrapper")
local wrapped = dofile
ChaosReloadFile.install()
ok(dofile == wrapped, "a second install keeps the first wrapper")

-- ---------------------------------------------------------------- names
eq(R.normalize("pace_config"), "pace_config", "bare name")
eq(R.normalize("pace_config.lua"), "pace_config", "with .lua")
eq(R.normalize("data/scripts/chaos/pace_config.lua"), "pace_config", "with the folder")
for _, bad in ipairs({"", "../x_config", "data/scripts/chaos/../../config.lua", "data/lib/x_config.lua", "/etc/passwd", "a/b_config",
		"x_config.lua;rm -rf /", "x config", "X_config", "a\\b_config", "x_config\n", "x$(id)_config", "_config", "1_config",
		"x_config.lua.lua", string.rep("a", 70) .. "_config", "x`id`", "x'_config", 'x"_config', "x.lua/y", "x_config.luac"}) do
	local name, why = R.normalize(bad)
	ok(name == nil and type(why) == "string", "refused name " .. string.format("%q", bad))
end
local nameNil, whyNil = R.normalize(nil)
ok(nameNil == nil and whyNil, "nil refused")
local okNum, msgNum = R.reload(12)
ok(okNum == false and msgNum, "a number refused")

-- ---------------------------------------------------------------- classes
eq(R.classify("pace_config"), "config", "config")
local kind, why = R.classify("pace")
eq(kind, "script", "a script")
ok(why:find("Reload system", 1, true) and why:find("restart", 1, true), "the script answer names the system reload and the restart")
kind, why = R.classify("pace_core")
eq(kind, "script", "a core is a script")
kind, why = R.classify("remote_cmd_config")
eq(kind, "restart", "restart only config")
ok(why:find("restart", 1, true), "restart only says why")
kind = R.classify("reload_file_config")
eq(kind, "restart", "this config is restart only")

-- ---------------------------------------------------------------- tracking
local function fresh()
	R.live = {}
end
fresh()
R.track("data/scripts/chaos/x_config.lua", {a = 1})
R.track("server/data/scripts/chaos/y_config.lua", {a = 1})
R.track("data\\scripts\\chaos\\z_config.lua", {a = 1})
R.track("data/scripts/chaos/not_a_cfg.lua", {a = 1})
R.track("data/lib/q_config.lua", {a = 1})
R.track("data/scripts/chaos/sub/w_config.lua", {a = 1})
R.track("data/scripts/chaos/s_config.lua", "text")
R.track(nil, {})
eq(table.concat(R.tracked(), ","), "x_config,y_config,z_config", "only chaos configs with a table are tracked")
local same = {a = 1}
R.track("data/scripts/chaos/same_config.lua", same)
R.track("data/scripts/chaos/same_config.lua", same)
eq(#R.live.same_config, 1, "one table once")
for i = 1, 12 do R.track("data/scripts/chaos/many_config.lua", {i = i}) end
eq(#R.live.many_config, R.config().maxTracked, "the list is capped")
eq(R.live.many_config[#R.live.many_config].i, 12, "the newest is kept")

-- the wrapper passes every return value and tracks a table
fresh()
local f = os.tmpname()
local h = io.open(f, "w"); h:write("return {k = 1}, 'second'"); h:close()
local a, b = dofile(f)
eq(a.k, 1, "the wrapper returns the first value")
eq(b, "second", "the wrapper returns the second value")
os.remove(f)
eq(#R.tracked(), 0, "a file outside the chaos folder is not tracked")

-- ---------------------------------------------------------------- sync in place
local live = {n = 1, gone = 2, nested = {x = 1, y = {deep = 1}}, list = {1, 2, 3}, same = 7}
local held = live.nested
local heldDeep = live.nested.y
local out = R.sync(live, {n = 2, nested = {x = 1, y = {deep = 5, extra = true}}, list = {1, 9}, same = 7, fresh = "new", fn = print})
eq(live.n, 2, "number changed")
eq(live.gone, nil, "removed key")
eq(live.fresh, "new", "added key")
eq(live.nested, held, "nested table keeps its identity")
eq(live.nested.y, heldDeep, "deeper table keeps its identity")
eq(heldDeep.deep, 5, "deep value changed")
eq(heldDeep.extra, true, "deep key added")
eq(#live.list, 2, "a shorter list is cut")
eq(live.list[2], 9, "list value changed")
eq(live.fn, print, "a function is set")
ok(out.count >= 6, "changes counted: " .. out.count)
local again = R.sync(live, {n = 2, nested = {x = 1, y = {deep = 5, extra = true}}, list = {1, 9}, same = 7, fresh = "new", fn = print})
eq(again.count, 0, "a second sync changes nothing")
-- a cycle does not loop
local cyc = {}; cyc.self = cyc
local cycNew = {}; cycNew.self = cycNew
R.sync(cyc, cycNew)
ok(true, "a cycle ends")
-- a table where the live value was a number
local l2 = {v = 1}
R.sync(l2, {v = {a = 1}})
eq(l2.v.a, 1, "a number replaced by a table")
-- the report is capped
local big, bigNew = {}, {}
for i = 1, 40 do big["k" .. i] = 1; bigNew["k" .. i] = 2 end
local capped = R.sync(big, bigNew)
eq(capped.count, 40, "all counted")
eq(#capped.list, R.config().maxChanges, "the named ones are capped")

-- ---------------------------------------------------------------- reload
local files = {}
local function loader(path)
	local src = files[path]
	if not src then return nil, "cannot open " .. path end
	return (loadstring or load)(src, "=" .. path)
end
local env = {loadfile = loader}
local dir = R.config().dir

fresh()
local cfgLive = {rate = 1, nested = {a = 1}}
local nestedLive = cfgLive.nested
R.track(dir .. "demo_config.lua", cfgLive)
local copy = R.live.demo_config
eq(#copy, 1, "demo tracked")

files[dir .. "demo_config.lua"] = "return {rate = 2, nested = {a = 5}}"
local okR, msg, lines = R.reload("demo_config", env)
ok(okR, "reload ok: " .. tostring(msg))
eq(cfgLive.rate, 2, "live value changed")
eq(cfgLive.nested, nestedLive, "nested identity kept")
eq(nestedLive.a, 5, "nested value changed")
ok(msg:find("2 value", 1, true), "message counts the changes: " .. tostring(msg))
ok(msg:find("copied", 1, true), "message warns about copied values")
ok(#lines == 2, "two changed keys named")
okR, msg = R.reload("demo_config.lua", env)
ok(okR and msg:find("no value differs", 1, true), "the same file again: nothing differs")

-- a broken file changes nothing
files[dir .. "demo_config.lua"] = "return {rate = = 3"
okR, msg = R.reload("demo_config", env)
ok(okR == false and msg:find("nothing changed", 1, true), "syntax error refused: " .. tostring(msg))
eq(cfgLive.rate, 2, "after a syntax error the live value stays")
files[dir .. "demo_config.lua"] = "error('boom')"
okR, msg = R.reload("demo_config", env)
ok(okR == false and msg:find("nothing changed", 1, true), "runtime error refused")
files[dir .. "demo_config.lua"] = "return 5"
okR, msg = R.reload("demo_config", env)
ok(okR == false and msg:find("table", 1, true), "no table refused")
eq(cfgLive.rate, 2, "after a bad file the live value stays")
files[dir .. "demo_config.lua"] = nil
okR, msg = R.reload("demo_config", env)
ok(okR == false and msg:find("cannot read", 1, true), "missing file refused")

-- unknown, script, restart only, path tricks
okR, msg = R.reload("unknown_config", env)
ok(okR == false and msg:find("no live copy", 1, true), "no live copy refused")
okR, msg = R.reload("pace_core", env)
ok(okR == false and msg:find("script", 1, true), "script refused")
okR, msg = R.reload("remote_cmd_config", env)
ok(okR == false and msg:find("restart", 1, true), "restart only refused")
local readPaths = {}
local spy = {loadfile = function(p) readPaths[#readPaths + 1] = p; return loader(p) end}
for _, bad in ipairs({"../../etc/passwd", "demo_config/../../x", "demo_config;id", "/tmp/x_config.lua"}) do
	okR = R.reload(bad, spy)
	ok(okR == false, "refused " .. bad)
end
eq(#readPaths, 0, "a refused name reads no file")
okR = R.reload("demo_config", spy)
eq(readPaths[1], dir .. "demo_config.lua", "the file read is inside the config folder")

-- the empty name lists the live tables
okR, msg, lines = R.reload("", env)
ok(okR and #lines == 1 and lines[1] == "demo_config", "list of live tables")

-- two live copies of one file are both updated
fresh()
local c1, c2 = {v = 1}, {v = 1}
R.track(dir .. "twice_config.lua", c1)
R.track(dir .. "twice_config.lua", c2)
files[dir .. "twice_config.lua"] = "return {v = 4}"
okR, msg = R.reload("twice_config", env)
ok(okR and c1.v == 4 and c2.v == 4, "both live copies changed")

-- ---------------------------------------------------------------- real files
fresh()
local pace = dofile("data/scripts/chaos/pace_config.lua")
eq(#R.live.pace_config, 1, "a real config is tracked through the wrapper")
eq(R.live.pace_config[1], pace, "the tracked table is the one the script got")
local before = pace.enabled
pace.enabled = not before
okR, msg, lines = R.reload("pace_config")
ok(okR and msg:find("1 value", 1, true), "real reload restores one value: " .. tostring(msg))
eq(pace.enabled, before, "the shipped value is back")
eq(lines[1], "enabled changed", "the changed key is named")

-- every shipped config loads under the wrapper and syncs into itself without a change
local ls = io.popen("ls data/scripts/chaos")
local count = 0
if ls then
	for file in ls:lines() do
		local name = file:match("^([a-z][a-z0-9_]*_config)%.lua$")
		if name and R.classify(name) == "config" then
			local okLoad, t = pcall(dofile, dir .. file)
			if okLoad and type(t) == "table" then
				count = count + 1
				local r1, m1 = R.reload(name)
				ok(r1, "shipped " .. name .. " reloads: " .. tostring(m1))
				ok(m1:find("no value differs", 1, true), "shipped " .. name .. " is unchanged by its own reload: " .. tostring(m1))
			end
		end
	end
	ls:close()
end
ok(count > 100, "many shipped configs went through the reload: " .. count)

-- ---------------------------------------------------------------- the panel action
local def
ChaosAdminPending = {}
dofile("data/scripts/chaos/admin/actions_server.lua")
def = ChaosAdminPending["server.reload_file"]
ok(def ~= nil, "the panel action is registered")
ok(def.dangerous == true, "the panel action is dangerous (group 6 as the system reload)")
eq(def.params[1].required, false, "the file may be empty (lists)")
eq(def.params[1].type, "string", "a plain string")
local okA, msgA = def.handler({}, {file = "x_config; rm"})
ok(okA == false and msgA, "the action refuses a bad name")
okA, msgA = def.handler({}, {file = "pace"})
ok(okA == false and msgA:find("script", 1, true), "the action refuses a script")
okA, msgA = def.handler({}, {})
ok(okA == true and msgA:find("config tables", 1, true), "the action lists")

print(string.format("reload_file_test: %d checks, %d failures", checks, fails))
os.exit(fails == 0 and 0 or 1)
