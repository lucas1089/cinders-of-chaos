-- Run from the server/ folder: luajit tests/base_towns_patch_test.lua (CI runs it with LuaJIT and Lua 5.3)
-- tools/patch_base_towns.py on a small OTBM map written here: the towns node is rebuilt with the names of a CSV
-- (longer and shorter names, temple coordinates that need escape bytes), ids, temples and every other byte stay,
-- the tree still parses, a town without a CSV row keeps its name, --dry-run writes nothing, a second run changes nothing.
-- The fixture names are placeholders.
local fails, checks = 0, 0
local function ok(cond, what)
	checks = checks + 1
	if not cond then
		fails = fails + 1
		print("FAIL " .. what)
	end
end

local python = io.popen and io.popen("python3 -V 2>/dev/null")
local hasPython = python and (python:read("*a") or ""):find("Python 3")
if python then
	python:close()
end
if not hasPython then
	print("base_towns_patch_test: python3 not found, skipped")
	return
end

local function readFile(path)
	local f = io.open(path, "rb")
	if not f then
		return nil
	end
	local s = f:read("*a")
	f:close()
	return s
end
local function writeFile(path, text)
	local f = assert(io.open(path, "wb"))
	f:write(text)
	f:close()
end
local function sh(cmd)
	local h = io.popen(cmd .. " 2>&1")
	local out = h:read("*a")
	h:close()
	return out
end

local root = os.tmpname()
os.remove(root)
local data = root .. "/data"
os.execute("mkdir -p '" .. data .. "/world'")
writeFile(root .. "/config.lua", 'mapName = "testmap"\n')
writeFile(root .. "/names.csv", "id,name\n1,New Alpha With A Longer Name\n2,Bet\n9,Not On The Map\n")
local map = data .. "/world/testmap.otbm"

-- root > map data (description) > one area with a tile and an item, the towns (1, 2, 7) and a waypoints node.
-- Town 1's temple x is 0x80FF and town 2's y is 0x7FFD: both need escape bytes in the file.
sh("python3 -I -c \"import sys, struct; sys.path.insert(0, 'tools'); import patch_base_towns as T; "
	.. "E = T.escape; n = lambda t, body, kids=b'': bytes([0xFE, t]) + E(body) + kids + bytes([0xFF]); "
	.. "item = n(6, struct.pack('<H', 2148)); tile = n(5, bytes([3, 4]), item); "
	.. "area = n(4, struct.pack('<HHB', 32000, 32000, 7), tile); "
	.. "towns = T.build_towns_node([(1, b'Old Alpha', 0x80FF, 0x7D00, 7, b''), (2, b'Old Beta Town', 100, 0x7FFD, 6, b''), "
	.. "(7, b'Kept Gamma', 10, 20, 7, b'')]); "
	.. "wp = n(15, b'', n(16, struct.pack('<H', 0) + struct.pack('<HHB', 1, 2, 7))); "
	.. "md = n(2, bytes([1]) + struct.pack('<H', 4) + b'test', area + towns + wp); "
	.. "d = b'\\x00\\x00\\x00\\x00' + n(0, struct.pack('<IHHII', 2, 34000, 34000, 3, 57), md); "
	.. "open(sys.argv[1], 'wb').write(d)\" '" .. map .. "'")
local original = readFile(map)
ok(original and #original > 40, "fixture map written")

local function run(extra)
	return sh("python3 -I tools/patch_base_towns.py '" .. data .. "' --names '" .. root .. "/names.csv' " .. (extra or ""))
end
local function list(path)
	return sh("python3 -I tools/patch_base_towns.py --list '" .. path .. "'")
end

-- dry run: reports, writes nothing
local dry = run("--dry-run")
ok(dry:find("would change", 1, true) ~= nil, "dry run reports: " .. dry)
ok(readFile(map) == original and readFile(map .. ".bak") == nil, "dry run writes nothing")

local out1 = run()
ok(out1:find('town 1: renamed to "New Alpha With A Longer Name"', 1, true) ~= nil, "town 1 renamed: " .. out1)
ok(out1:find('town 2: renamed to "Bet"', 1, true) ~= nil, "town 2 renamed")
ok(out1:find("town 7 (temple 10,20,7): no row in base_towns.csv, name kept", 1, true) ~= nil, "town without a row listed")
ok(out1:find("town 9 is not on the map", 1, true) ~= nil, "CSV id not on the map listed")
ok(out1:find("towns: 2 renamed of 3 (verified)", 1, true) ~= nil, "summary")
ok(readFile(map .. ".bak") == original, "the original kept as .bak")
ok(readFile(map .. ".tmp") == nil, "no temporary file left")

local towns = list(map)
ok(towns:find("1\tNew Alpha With A Longer Name\t33023,32000,7", 1, true) ~= nil, "town 1: new name, same temple: " .. towns)
ok(towns:find("2\tBet\t100,32765,6", 1, true) ~= nil, "town 2: new name, same temple")
ok(towns:find("7\tKept Gamma\t10,20,7", 1, true) ~= nil, "town 7 kept")
ok(not towns:find("Old Alpha", 1, true) and not towns:find("Old Beta", 1, true), "old names gone")

-- the whole tree parses and has the same nodes; the bytes before the towns node are the same
local tree = sh("python3 -I -c \"import sys; sys.path.insert(0, 'tools'); import patch_base_towns as T; "
	.. "a = T.walk_nodes(open(sys.argv[1], 'rb').read()); b = T.walk_nodes(open(sys.argv[2], 'rb').read()); "
	.. "print('same tree' if a == b else 'other tree', len(a))\" '" .. map .. "' '" .. map .. ".bak'")
ok(tree:find("same tree 11", 1, true) ~= nil, "the map parses with the same 11 nodes: " .. tree)
local new = readFile(map)
local at = original:find("\254\12", 1, true)
ok(at and new:sub(1, at - 1) == original:sub(1, at - 1), "bytes before the towns node unchanged")
ok(new:sub(-24) == original:sub(-24), "waypoints and the closing bytes unchanged")

-- second run: nothing to change, the file is not touched
local out2 = run()
ok(out2:find("towns: 3 on the map, nothing to change", 1, true) ~= nil, "second run: nothing to change (" .. out2 .. ")")
ok(readFile(map) == new, "second run keeps the map")

-- a broken map is refused and not written
writeFile(map, new:sub(1, #new - 30))
local bad = run()
ok(bad:find("nothing written", 1, true) ~= nil, "a truncated map is refused: " .. bad)

os.execute("rm -rf '" .. root .. "'")
print(string.format("base_towns_patch_test: %d checks, %d failures", checks, fails))
if fails > 0 then
	os.exit(1)
end
