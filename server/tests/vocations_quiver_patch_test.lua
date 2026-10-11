-- run from server/: luajit tests/vocations_quiver_patch_test.lua (also lua5.3)
-- install_all.py runs tools/add_vocations.py (vocations) and tools/patch_base_archery.py (archery) on the same
-- data/movements/movements.xml. The archery tool rebuilds its quiver block with the launcher classes; add_vocations.py
-- must leave that block alone, or the two tools rewrite it back and forth on every install.
local checks, fails = 0, 0
local function ok(cond, what)
	checks = checks + 1
	if not cond then
		fails = fails + 1
		print("FAIL: " .. what)
	end
end
local function eq(a, b, what)
	ok(a == b, what .. " (got " .. tostring(a) .. ", expected " .. tostring(b) .. ")")
end

local python = io.popen and io.popen("python3 -V 2>/dev/null")
local hasPython = python and (python:read("*a") or ""):find("Python 3")
if python then
	python:close()
end
if not hasPython then
	print("vocations_quiver_patch_test: python3 not found, skipped")
	return
end

local function writeFile(path, text)
	local f = assert(io.open(path, "wb"))
	f:write(text)
	f:close()
end
local function readFile(path)
	local f = assert(io.open(path, "rb"))
	local s = f:read("*a")
	f:close()
	return s
end

-- a converted movements.xml: a light armour (the class lines go there) and a stock quiver entry with the launcher classes
local MOVES = table.concat({
	"<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
	"<movements>",
	"\t<!-- chaos classes: vocation lists converted (server/tools/add_vocations.py) -->",
	"\t<movevent event=\"Equip\" itemid=\"2660\" slot=\"armor\" level=\"20\" function=\"onEquipItem\">",
	"\t\t<vocation name=\"Ranger\" />",
	"\t\t<vocation name=\"Deadeye\" showInDescription=\"0\" />",
	"\t</movevent>",
	"\t<movevent event=\"DeEquip\" itemid=\"2660\" slot=\"armor\" function=\"onDeEquipItem\" />",
	"</movements>",
	""
}, "\n")
local WEAPONS = table.concat({
	"<weapons>",
	"\t<distance id=\"2456\" level=\"1\" unproperly=\"1\">",
	"\t\t<vocation name=\"Ranger\" />",
	"\t\t<vocation name=\"Deadeye\" showInDescription=\"0\" />",
	"\t\t<vocation name=\"Beastmaster\" showInDescription=\"0\" />",
	"\t</distance>",
	"</weapons>",
	""
}, "\n")

-- one install = add_vocations.patch_movements, then patch_base_archery.patch_movements (the install_all.py order)
local SCRIPT = [[
import sys
sys.path.insert(0, 'tools')
import add_vocations as A, patch_base_archery as P
moves, weapons = A.read(sys.argv[1]), A.read(sys.argv[2])
cfg = P.read_config()
launchers = set(cfg['launchers'])
for run in (1, 2, 3):
    before = moves
    moves, counts = A.patch_movements(moves, {})
    voc_changed = moves != before
    mid = moves
    moves, _note = P.patch_movements(moves, cfg, weapons, launchers)
    print('run %d vocations=%s archery=%s' % (run, 'changed' if voc_changed else 'same', 'changed' if moves != mid else 'same'))
A.write(sys.argv[1], moves)
print('markers', int(P.MOVE_BEGIN.strip() in moves and A.QUIVER_BLOCK.search(moves) is not None))
]]

local base = os.tmpname()
local movesPath, weaponsPath, scriptPath = base .. "_moves.xml", base .. "_weapons.xml", base .. "_run.py"
writeFile(movesPath, MOVES)
writeFile(weaponsPath, WEAPONS)
writeFile(scriptPath, SCRIPT)
local h = assert(io.popen("python3 -I " .. scriptPath .. " " .. movesPath .. " " .. weaponsPath .. " 2>&1"))
local out = h:read("*a") or ""
h:close()
local final = readFile(movesPath)
for _, p in ipairs({base, movesPath, weaponsPath, scriptPath}) do
	os.remove(p)
end

ok(out:find("run 1 vocations=changed archery=changed", 1, true), "first install: both tools write (" .. out .. ")")
ok(out:find("run 2 vocations=same archery=same", 1, true), "second install: neither tool changes movements.xml (" .. out .. ")")
ok(out:find("run 3 vocations=same archery=same", 1, true), "third install: still nothing")
ok(out:find("markers 1", 1, true), "add_vocations.py finds the archery tool's quiver block by its markers")

-- the quiver block keeps the launcher classes only; the armour outside it gets the Thief and Monk lines
local block = final:match("Chaos quivers.-end of the Chaos quivers") or ""
ok(block:find('<vocation name="Ranger"', 1, true), "quiver block: Ranger")
ok(not block:find('name="Thief"', 1, true), "quiver block: no Thief line")
ok(not block:find('name="Monk"', 1, true), "quiver block: no Monk line")
local armour = final:match('itemid="2660" slot="armor".-</movevent>') or ""
ok(armour:find('<vocation name="Thief" />', 1, true), "light armour: the Thief line is added")
ok(armour:find('<vocation name="Monk" />', 1, true), "light armour: the Monk line is added")

print(string.format("vocations_quiver_patch_test: %d checks, %d failures", checks, fails))
if fails > 0 then
	os.exit(1)
end
