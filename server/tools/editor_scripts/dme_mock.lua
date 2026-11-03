-- A stand-in for the map editor's Lua runner (tests only, not shipped): what its docs and API say a custom script
-- gets (cinders_editor.lua header). Relative dofile / loadfile / io.open paths start at ROOT; no os.execute, os.exit,
-- io.popen; the dme table writes into a buffer and refuses bad positions, ids and counts; the limits of one run are
-- checked at the end, as the editor does when it reads the buffer.
--   local mock = dofile("tools/editor_scripts/dme_mock.lua")
--   local res = mock.run(SCRIPT, {root = "", seed = 7, params = {...}})
--   res.ok, res.error, res.tiles (key "x:y:z" -> {x, y, z, ground = {id, count}, items = {{id, count}, ...}}),
--   res.count, res.items, res.log (lines), res.value (what the script returned)
local M = {}

local function check(cond, msg)
	if not cond then
		error(msg, 3)
	end
end

local function int(v, lo, hi)
	return type(v) == "number" and v == math.floor(v) and v >= lo and v <= hi
end

function M.run(script, o)
	o = o or {}
	local root = o.root or ""
	local saved = {dofile = dofile, loadfile = loadfile, open = io.open, execute = os.execute, exit = os.exit,
		popen = io.popen, dme = dme, print = print, seed = DME_SEED, params = CINDERS_PARAMS}
	local function resolve(path)
		if path:sub(1, 1) == "/" or path:match("^%a:") then
			return path
		end
		return root .. path
	end
	local tiles, count, log = {}, 0, {}
	local function tile(pos)
		check(type(pos) == "table", "Expected a position table")
		check(int(pos.x, 0, 65535), "Invalid x")
		check(int(pos.y, 0, 65535), "Invalid y")
		check(int(pos.z, 0, 15), "Invalid floor")
		local key = pos.x .. ":" .. pos.y .. ":" .. pos.z
		if not tiles[key] then
			tiles[key] = {x = pos.x, y = pos.y, z = pos.z, items = {}}
			count = count + 1
		end
		return tiles[key]
	end
	local function item(id, n)
		check(int(id, 1, 65535), "Invalid item ID")
		n = n or 1
		check(int(n, 0, 255), "Invalid count (0-255)")
		return {id = id, count = n}
	end
	dofile = function(path)
		return saved.dofile(resolve(path))
	end
	loadfile = function(path)
		return saved.loadfile(resolve(path))
	end
	io.open = function(path, mode)
		return saved.open(resolve(path), mode)
	end
	os.execute, os.exit, io.popen = nil, nil, nil
	print = function(...)
		local parts = {}
		for k = 1, select("#", ...) do
			parts[k] = tostring((select(k, ...)))
		end
		log[#log + 1] = table.concat(parts, "\t")
	end
	dme = {apiVersion = 1}
	function dme.setGround(pos, id)
		tile(pos).ground = item(id, 1)
	end
	function dme.addItem(pos, id, n)
		local t = tile(pos)
		t.items[#t.items + 1] = item(id, n)
	end
	function dme.clearTile(pos)
		local t = tile(pos)
		t.ground = nil
		t.items = {}
	end
	function dme.getTile(pos)
		return tile(pos)
	end
	function dme.log(msg)
		print(msg)
	end
	DME_SEED = o.seed or 1
	CINDERS_PARAMS = o.params
	local ok, value = pcall(saved.dofile, resolve(script))

	dofile, loadfile, io.open, os.execute, os.exit, io.popen = saved.dofile, saved.loadfile, saved.open, saved.execute,
		saved.exit, saved.popen
	dme, print, DME_SEED, CINDERS_PARAMS = saved.dme, saved.print, saved.seed, saved.params

	local items = 0
	if ok then
		for _, t in pairs(tiles) do
			items = items + #t.items + (t.ground and 1 or 0)
			if #t.items > 1024 then
				ok, value = false, "Invalid item or generation size limit exceeded."
			end
		end
		if count > 100000 or items > 500000 then
			ok, value = false, "Invalid item or generation size limit exceeded."
		elseif count == 0 then
			ok, value = false, "Script produced no tiles."
		end
	end
	return {ok = ok, error = not ok and tostring(value) or nil, value = ok and value or nil, tiles = tiles,
		count = count, items = items, log = log}
end

return M
