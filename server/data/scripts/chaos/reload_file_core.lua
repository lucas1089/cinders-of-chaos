-- Reload one config table without a full /reload (O312 desktop admin app; reload_file_core.lua, reload_file_config.lua,
-- the panel action server.reload_file; server/README.md "Reload one config table (O312)"): the pure part.
--
-- How it works. chaos_constants.lua installs a thin wrapper around the global dofile (ChaosReloadFile.install). Every
-- data/scripts/chaos/*_config.lua that a script loads with dofile hands back a table; the wrapper remembers that table
-- (the live copy). A reload runs the file again, and only when it parses and returns a table, copies the new values INTO
-- the live tables, keeping their identity (nested tables too), so a script that holds the table (a global, a field of
-- Chaos, a local) sees the new numbers at its next read. A key the file no longer has is removed.
--
-- What it cannot do, and says so: a script file is never reloaded alone (it registers events and keeps locals: use
-- "Reload system" scripts, which reloads every revscript, or restart); a value a script copied out of the table when it
-- loaded (local N = cfg.n) keeps the old number until the next script reload or restart; a config no live copy of is
-- known (loaded before the wrapper, or by a script that never calls dofile on it) is refused.
-- Safety: only a bare file name of the config folder is accepted (a-z, 0-9, _), never a path, so there is nothing to
-- escape; a file with an error or without a table changes nothing; groups and audit come from the admin panel action.
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.

local R = ChaosReloadFile or {}
ChaosReloadFile = R

local DEFAULTS = {dir = "data/scripts/chaos/", suffix = "_config", maxTracked = 8, maxChanges = 12, maxDepth = 16, restartOnly = {}}

R.live = R.live or {} -- name -> {table, ...}

function R.config()
	if R.cfg then return R.cfg end
	-- the real dofile: the wrapper asks for this config itself
	local ok, c = pcall(R.realDofile or dofile, DEFAULTS.dir .. "reload_file_config.lua")
	if not ok or type(c) ~= "table" then c = DEFAULTS end
	R.cfg = c
	return c
end

-- "pace_config", "pace_config.lua" or "data/scripts/chaos/pace_config.lua" -> "pace_config"; nil, reason otherwise
function R.normalize(arg)
	if type(arg) ~= "string" or arg == "" then return nil, "no file name" end
	if #arg > 120 then return nil, "name too long" end
	local c = R.config()
	local name = arg
	if name:sub(1, #c.dir) == c.dir then name = name:sub(#c.dir + 1) end
	name = name:gsub("%.lua$", "")
	if not name:match("^[a-z][a-z0-9_]*$") or #name > 64 then
		return nil, "only a config file name of data/scripts/chaos is accepted (letters, digits, underscore)"
	end
	return name
end

-- "config" (can reload live), "script", or "restart" with the reason
function R.classify(name)
	local c = R.config()
	local why = c.restartOnly and c.restartOnly[name]
	if why then return "restart", "needs a restart: " .. why end
	if name:sub(-#c.suffix) ~= c.suffix then
		return "script", "'" .. name .. ".lua' is a script, not a config table. A script is not reloaded alone (it registers "
			.. "events and keeps local copies): use Reload system > scripts (every revscript) or restart."
	end
	return "config"
end

local function pathOf(name) return R.config().dir .. name .. ".lua" end

-- the file name of a chaos config path as a script wrote it, or nil
local function trackedName(path)
	if type(path) ~= "string" then return nil end
	local p = path:gsub("\\", "/")
	local c = R.config()
	local at = p:find(c.dir, 1, true)
	if not at then return nil end
	local rest = p:sub(at + #c.dir)
	local name = rest:match("^([a-z][a-z0-9_]*)%.lua$")
	if name and name:sub(-#c.suffix) == c.suffix then return name end
end

-- remember the table a config file returned
function R.track(path, value)
	if type(value) ~= "table" then return end
	local name = trackedName(path)
	if not name then return end
	local list = R.live[name]
	if not list then list = {}; R.live[name] = list end
	for _, t in ipairs(list) do
		if t == value then return end
	end
	list[#list + 1] = value
	if #list > R.config().maxTracked then table.remove(list, 1) end
end

local function pass(path, ...)
	R.track(path, (...))
	return ...
end

-- wraps env.dofile once (env defaults to _G); a reload of chaos_constants.lua keeps the first wrapper
function R.install(env)
	env = env or _G
	if R.installed or type(env.dofile) ~= "function" then return false end
	local real = env.dofile
	R.realDofile = real
	R.installed = true
	env.dofile = function(path, ...)
		return pass(path, real(path, ...))
	end
	return true
end

local function keyText(parent, k)
	return parent == "" and tostring(k) or (parent .. "." .. tostring(k))
end

-- copies `new` into `live` in place; `out.count` counts the changed keys, `out.list` names the first ones
local function sync(live, new, depth, seen, parent, out)
	if depth > R.config().maxDepth then return end
	local function note(k, how)
		out.count = out.count + 1
		if #out.list < R.config().maxChanges then out.list[#out.list + 1] = keyText(parent, k) .. " " .. how end
	end
	local gone = {}
	for k in pairs(live) do
		if new[k] == nil then gone[#gone + 1] = k end
	end
	for _, k in ipairs(gone) do
		if type(live[k]) ~= "function" then note(k, "removed") end
		live[k] = nil
	end
	for k, v in pairs(new) do
		local old = live[k]
		if type(v) == "table" and type(old) == "table" then
			if not seen[old] then
				seen[old] = true
				sync(old, v, depth + 1, seen, keyText(parent, k), out)
			end
		elseif type(v) == "function" then
			live[k] = v
		elseif old ~= v then
			if old == nil then note(k, "added") else note(k, "changed") end
			live[k] = v
		end
	end
end

-- exposed for the test
function R.sync(live, new)
	local out = {count = 0, list = {}}
	sync(live, new, 0, {[live] = true}, "", out)
	return out
end

-- names of the configs a live copy is known of, sorted
function R.tracked()
	local names = {}
	for name, list in pairs(R.live) do
		if #list > 0 then names[#names + 1] = name end
	end
	table.sort(names)
	return names
end

-- ok, message, lines. env: {loadfile = ...} (the engine's loadfile by default). An empty name lists the live ones.
function R.reload(arg, env)
	env = env or {}
	local load = env.loadfile or loadfile
	if arg == nil or arg == "" then
		local names = R.tracked()
		return true, string.format("%d config tables can be reloaded one by one.", #names), names
	end
	local name, why = R.normalize(arg)
	if not name then return false, why end
	local kind, reason = R.classify(name)
	if kind ~= "config" then return false, reason end
	local list = R.live[name]
	if not list or #list == 0 then
		return false, "'" .. name .. ".lua' has no live copy known (no script loaded it with dofile since the server started, "
			.. "or it was loaded before this feature). Use Reload system > scripts or restart."
	end
	local chunk, err = load(pathOf(name))
	if not chunk then return false, "cannot read " .. name .. ".lua, nothing changed: " .. tostring(err) end
	local ok, new = pcall(chunk)
	if not ok then return false, name .. ".lua has an error, nothing changed: " .. tostring(new) end
	if type(new) ~= "table" then return false, name .. ".lua does not return a table, nothing changed." end
	local total = {count = 0, list = {}}
	for _, live in ipairs(list) do
		local out = R.sync(live, new)
		if out.count > total.count then total = out end
	end
	if total.count == 0 then return true, name .. ".lua: no value differs from the running game.", {} end
	local msg = string.format("%s.lua reloaded: %d value(s) changed in %d live table(s). Values a script copied when it "
		.. "loaded keep the old number until the next scripts reload or restart.", name, total.count, #list)
	return true, msg, total.list
end

return R
