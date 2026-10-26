-- Run from the server/ folder: luajit tests/keystone_labels_test.lua (and lua5.3; CI runs both)
-- Keystone labels of the combat log (keystone_labels.lua, keystone_labels_config.lua): the label file is valid and
-- complete, run / note do nothing special without the combat log, pass results through and delegate to a sink, and
-- every labelled keystone is wired in the scripts that apply it.
local checks = 0
local function eq(a, b, m)
	checks = checks + 1
	if a ~= b then
		error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2)
	end
end
local function ok(v, m)
	checks = checks + 1
	if not v then
		error(m or "expected true", 2)
	end
end

dofile("data/scripts/chaos/keystone_labels.lua")
local KL = ChaosKeystoneLabels
local cfg = KL.cfg

-- ---------------------------------------------------------------- the label file
ok(type(cfg.prefix) == "string" and cfg.prefix ~= "", "a prefix")
local names, count = {}, 0
for flag, d in pairs(cfg.flags) do
	count = count + 1
	ok(flag:match("^ks%u") or flag:match("^ar%u"), "a keystone flag: " .. flag)
	ok(type(d.name) == "string" and d.name ~= "" and not d.name:find("\"", 1, true), "name of " .. flag)
	ok(d.kind == "p" or d.kind == "k", "kind of " .. flag)
	ok(d.tab == "dealt" or d.tab == "healing" or d.tab == "taken", "tab of " .. flag)
	ok(d.observe == nil or d.observe == false, "observe is absent or false: " .. flag)
	ok((d.observe == false) == (d.why ~= nil), "a flag a bot cannot observe says why, and only that one: " .. flag)
	local full = cfg.prefix .. d.name
	ok(not names[d.kind .. ":" .. full], "unique row key " .. full)
	names[d.kind .. ":" .. full] = true
	eq(KL.def(flag).name, full, "def name of " .. flag)
	eq(KL.def(flag).observe, d.observe ~= false, "def observe of " .. flag)
end
ok(count >= 40, "the file names " .. count .. " keystones")
-- a note (kind k) only changes a counted hit: it is never the keystone's own damage in the damage tab; a heal that
-- Chaos.heal does (no health event) is kind p in the healing tab
for flag, d in pairs(cfg.flags) do
	if d.tab == "healing" then
		eq(d.kind, "p", flag .. ": a heal of its own is counted")
	end
end

-- every flag exists in the tree (passivetree_data.lua customStats) or in the archetypes
local tree = io.open("data/scripts/chaos/passivetree_data.lua"):read("*a")
local arch = io.open("data/scripts/chaos/archetypes_config.lua"):read("*a")
for flag in pairs(cfg.flags) do
	ok(tree:find(flag .. "=1", 1, true) or arch:find(flag, 1, true), flag .. " is a keystone of the tree")
end

-- every labelled flag is passed to run / note / procDamage / dealProc in the scripts that apply it
local wired = ""
for _, f in ipairs({"passivetree_keystones", "archetypes", "templar_combat", "monk_combat"}) do
	wired = wired .. io.open("data/scripts/chaos/" .. f .. ".lua"):read("*a")
end
for flag in pairs(cfg.flags) do
	ok(wired:find("\"" .. flag .. "\"", 1, true), flag .. " is wired")
end

-- ---------------------------------------------------------------- without the combat log
ChaosKeystoneLabels.sink = nil
local function two(a, b) return a, b end
local r1, r2 = KL.run("ksCleavingArc", two, 7, 8)
ok(r1 == 7 and r2 == 8, "run passes the results through without a sink")
r1 = KL.run(nil, two, 5, 6)
eq(r1, 5, "run without a flag")
r1 = KL.run("ksNoSuchKeystone", two, 3, 4)
eq(r1, 3, "run with an unknown flag")
eq(KL.note({}, "ksDeadeye", 5), false, "note without a sink")

-- ---------------------------------------------------------------- with a sink
local runs, notes = {}, {}
KL.sink = {
	run = function(def, fn, ...) runs[#runs + 1] = def; return fn(...) end,
	note = function(player, def, amount) notes[#notes + 1] = {player, def, amount}; return true end,
}
r1, r2 = KL.run("ksCleavingArc", two, 7, 8)
ok(r1 == 7 and r2 == 8, "run passes the results through a sink")
eq(runs[1].name, "Keystone: Cleaving Arc", "the sink gets the def")
eq(runs[1].kind, "p", "with its kind")
KL.run("ksNoSuchKeystone", two, 1, 2)
KL.run(nil, two, 1, 2)
eq(#runs, 1, "an unknown flag or none does not reach the sink")
local player = {}
eq(KL.note(player, "ksDeadeye", 12), true, "note reaches the sink")
eq(notes[1][1], player, "for the player")
eq(notes[1][2].name, "Keystone: Deadeye", "with the def")
eq(notes[1][3], 12, "and the amount")
KL.note(player, "ksDeadeye", "7")
eq(notes[2][3], 7, "a number as text is a number")
KL.note(player, "ksDeadeye", nil)
eq(notes[3][3], 0, "no amount is 0")
eq(KL.note(nil, "ksDeadeye", 1), false, "no player")
eq(KL.note(player, "ksNoSuchKeystone", 1), false, "unknown flag")
KL.sink.note = function() error("boom") end
eq(KL.note(player, "ksDeadeye", 1), false, "an error in the sink never reaches the keystone script")

print(string.format("keystone_labels_test: OK (%d checks)", checks))
