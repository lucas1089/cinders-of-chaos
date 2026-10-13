-- Run from the server/ folder: luajit tests/base_server_name_patch_test.lua (CI runs it with LuaJIT and Lua 5.3)
-- tools/patch_base_server_name.py with a test list (made-up old strings, their sha256 computed here): only whole
-- quoted strings whose content hashes to a row of that file change, in either quote style; a longer string, another
-- file and identifiers stay; two old forms of one phrase give the same new text; --dry-run writes nothing; a second
-- run changes nothing; a file with neither the old string nor the new text is an error; a missing file is skipped.
-- config.lua next to data/: only a serverName value that hashes to a row changes; an own name stays.
-- And the real list (tools/base_server_texts.csv) is well formed.
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
	print("base_server_name_patch_test: python3 not found, skipped")
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
	local h = io.popen(cmd .. " 2>&1; echo \"rc=$?\"")
	local out = h:read("*a")
	h:close()
	return out
end
local function sha256(text)
	local out = sh("python3 -I -c \"import hashlib,sys; print(hashlib.sha256(sys.argv[1].encode()).hexdigest())\" '"
		.. text .. "'")
	return out:match("^(%x+)")
end

local root = os.tmpname()
os.remove(root)
local data = root .. "/data"
os.execute("mkdir -p '" .. data .. "/scripts/customs'")

local OLD_WELCOME = "Welcome to Oldworld!"
local OLD_BANNER = "= Oldworld Oldname Login ="
local OLD_BANNER_2 = "= Cinders of Chaos Oldname Login =" -- the same banner after another step renamed a word
local list = root .. "/list.csv"
writeFile(list, "sha256,file,new,note\n"
	.. sha256(OLD_WELCOME) .. ",scripts/customs/welcome.lua,Welcome to Cinders of Chaos!,welcome\n"
	.. sha256(OLD_BANNER) .. ",scripts/customs/banner.lua,= Cinders of Chaos Login =,banner\n"
	.. sha256(OLD_BANNER_2) .. ",scripts/customs/banner.lua,= Cinders of Chaos Login =,banner after worldtexts\n"
	.. sha256(OLD_BANNER) .. ",scripts/customs/other.lua,= Cinders of Chaos Login =,a second banner\n"
	.. sha256(OLD_WELCOME) .. ",scripts/customs/missing.lua,Welcome to Cinders of Chaos!,not in the data\n")

local WELCOME = "local effects = {\n"
	.. "\t{text = '" .. OLD_WELCOME .. "', effect = 317},\n"
	.. "\t{text = \"" .. OLD_WELCOME .. "\", effect = 1},\n"
	.. "\t{text = '" .. OLD_WELCOME .. " Have fun', effect = 2},\n"
	.. "\t{text = 'Temple', effect = 288},\n"
	.. "}\nlocal Oldworld = 'it\\'s fine'\n"
local BANNER = "print(\"=====\")\nprint(\"" .. OLD_BANNER .. "\")\nprint(\"=====\")\n"
local BANNER_2 = "print(\"" .. OLD_BANNER_2 .. "\")\n"
local OTHER = "print('nothing to see')\n"
writeFile(data .. "/scripts/customs/welcome.lua", WELCOME)
writeFile(data .. "/scripts/customs/banner.lua", BANNER)
writeFile(data .. "/scripts/customs/other.lua", OTHER)

local tool = "python3 -I tools/patch_base_server_name.py '" .. data .. "' --list '" .. list .. "'"

-- dry run: reports, writes nothing; other.lua has neither form: exit status 1
local out = sh(tool .. " --dry-run")
ok(out:find("welcome.lua: 2 strings replaced %(dry run"), "dry run counts both quote styles: " .. out)
ok(readFile(data .. "/scripts/customs/welcome.lua") == WELCOME, "dry run wrote nothing")
ok(out:find("other.lua: neither the old string nor"), "a file without the string is reported")
ok(out:find("missing.lua: not there, skipped"), "a missing file is skipped")
ok(out:find("rc=1"), "exit status 1 when a file lacks a string")

writeFile(data .. "/scripts/customs/other.lua", "print('" .. OLD_BANNER .. "')\n")
out = sh(tool)
ok(out:find("rc=0"), "exit status 0: " .. out)
local w = readFile(data .. "/scripts/customs/welcome.lua")
ok(w == WELCOME:gsub(OLD_WELCOME:gsub("%p", "%%%0") .. "(['\"],)", "Welcome to Cinders of Chaos!%1"), "welcome.lua: " .. w)
ok(w:find("'" .. OLD_WELCOME .. " Have fun'", 1, true), "a longer string stays")
ok(w:find("local Oldworld = 'it\\'s fine'", 1, true), "identifiers and other strings stay")
ok(readFile(data .. "/scripts/customs/banner.lua") == BANNER:gsub(OLD_BANNER:gsub("%p", "%%%0"), "= Cinders of Chaos Login ="),
	"banner.lua replaced")
ok(readFile(data .. "/scripts/customs/other.lua") == "print('= Cinders of Chaos Login =')\n", "other.lua replaced")

-- the second form of the banner (another step renamed a word first) gives the same text
writeFile(data .. "/scripts/customs/banner.lua", BANNER_2)
out = sh(tool)
ok(out:find("banner.lua: 1 string replaced"), "second form replaced: " .. out)
ok(readFile(data .. "/scripts/customs/banner.lua") == "print(\"= Cinders of Chaos Login =\")\n", "second form text")

-- a second run changes nothing
local before = readFile(data .. "/scripts/customs/welcome.lua")
out = sh(tool)
ok(out:find("welcome.lua: already done") and out:find("banner.lua: already done") and out:find("rc=0"),
	"second run: already done: " .. out)
ok(readFile(data .. "/scripts/customs/welcome.lua") == before, "second run wrote nothing new")

-- a list row the tool cannot write safely is refused
local bad = root .. "/bad.csv"
writeFile(bad, "sha256,file,new,note\n" .. sha256(OLD_WELCOME) .. ",scripts/customs/welcome.lua,it's,quote\n")
out = sh("python3 -I tools/patch_base_server_name.py '" .. data .. "' --list '" .. bad .. "'")
ok(out:find("has a quote") and out:find("rc=1"), "a quote in the new text is refused: " .. out)

-- config.lua next to data/: only the serverName value, only when it hashes to a config.lua row
local OLD_NAME = "Oldworld"
local cfgList = root .. "/cfg.csv"
writeFile(cfgList, "sha256,file,new,note\n" .. sha256(OLD_NAME) .. ",config.lua,Cinders of Chaos,base name\n")
local cfgPath = root .. "/config.lua"
local CFG = "ownerName = \"" .. OLD_NAME .. "\"\nserverName = \"" .. OLD_NAME .. "\"\nmotd = \"Welcome to " .. OLD_NAME
	.. "\"\n"
local CFG_NEW = "ownerName = \"" .. OLD_NAME .. "\"\nserverName = \"Cinders of Chaos\"\nmotd = \"Welcome to " .. OLD_NAME
	.. "\"\n"
writeFile(cfgPath, CFG)
local cfgTool = "python3 -I tools/patch_base_server_name.py '" .. data .. "' --list '" .. cfgList .. "'"
out = sh(cfgTool .. " --dry-run")
ok(out:find("config.lua: 1 string replaced %(dry run") and out:find("rc=0"), "config dry run: " .. out)
ok(readFile(cfgPath) == CFG, "config dry run wrote nothing")
out = sh(cfgTool)
ok(out:find("config.lua: 1 string replaced") and out:find("rc=0"), "config replaced: " .. out)
ok(readFile(cfgPath) == CFG_NEW, "only the serverName value changed: " .. tostring(readFile(cfgPath)))
out = sh(cfgTool)
ok(out:find("config.lua: already done") and out:find("rc=0"), "config second run: " .. out)
ok(readFile(cfgPath) == CFG_NEW, "config second run wrote nothing")
-- an owner's own name (or prod_config.py's line) stays
local OWN = "  serverName = 'My Own World'\n"
writeFile(cfgPath, OWN)
out = sh(cfgTool)
ok(out:find("left as it is") and out:find("rc=0"), "own name kept: " .. out)
ok(readFile(cfgPath) == OWN, "own name not written")
-- no serverName line: reported
writeFile(cfgPath, "motd = 'hi'\n")
out = sh(cfgTool)
ok(out:find("no serverName line") and out:find("rc=1"), "missing serverName line: " .. out)
os.remove(cfgPath)
out = sh(cfgTool)
ok(out:find("config.lua: not there, skipped") and out:find("rc=0"), "missing config.lua skipped: " .. out)

-- the real list
local real = readFile("tools/base_server_texts.csv")
ok(real ~= nil, "tools/base_server_texts.csv is there")
local rows = 0
for line in (real or ""):gmatch("[^\n]+") do
	if not line:find("^sha256,") then
		rows = rows + 1
		local key, file, new = line:match("^(%x+),([^,]+),([^,]+),")
		ok(key and #key == 64, "row " .. rows .. ": sha256")
		ok(file == "config.lua" or (file and file:find("^scripts/") and file:find("%.lua$")),
			"row " .. rows .. ": config.lua or a Lua file of data/")
		ok(new and new:find("Cinders of Chaos", 1, true) and not new:find("['\"\\]"), "row " .. rows .. ": new text")
	end
end
ok(rows >= 3, "the real list has its rows")

os.execute("rm -rf '" .. root .. "'")
print(string.format("base_server_name_patch_test: %d checks, %d failures", checks, fails))
if fails > 0 then
	os.exit(1)
end
