-- Run from the server/ folder: luajit tests/weapon_coverage_test.lua (and lua5.3; CI runs both)
-- The weapon coverage audit (tools/weapon_coverage.lua, weapon_coverage_config.lua): bands, who may wield what, the
-- flags (zero, too few, too weak), known gaps, the gear set curves equal the installer's, and the real data passes.

local n = 0
local function eq(a, b, m)
	n = n + 1
	if a ~= b then
		error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2)
	end
end

WEAPON_COVERAGE_NO_MAIN = true
local C = dofile("tools/weapon_coverage.lua")
local cfg = dofile("tools/weapon_coverage_config.lua")

-- ---------------------------------------------------------------- bands
eq(#cfg.bands, 9, "nine bands")
eq(cfg.bands[1][3], "1-20", "first band label")
eq(cfg.bands[9][3], "1500-2400+", "last band label")
eq(C.bandOf(cfg, 1), 1, "level 1")
eq(C.bandOf(cfg, 19), 1, "level 19")
eq(C.bandOf(cfg, 20), 2, "level 20 opens the second band")
eq(C.bandOf(cfg, 1499), 8, "level 1499")
eq(C.bandOf(cfg, 1500), 9, "level 1500 opens the last band")
eq(C.bandOf(cfg, 2400), 9, "level 2400")
eq(C.bandOf(cfg, 0), 1, "level 0 is the first band")
for i = 2, #cfg.bands do
	eq(cfg.bands[i][1], cfg.bands[i - 1][2], "bands touch: " .. cfg.bands[i][3])
end

-- ---------------------------------------------------------------- thresholds
eq(cfg.minOptions >= 3, true, "at least three options per band")
eq(cfg.minPower >= 0.8, true, "the best option at least 80% of the tier")
eq(#cfg.lines, 7, "seven class lines")
local classes = 0
for _, l in ipairs(cfg.lines) do
	classes = classes + #l.classes
end
eq(classes, 21, "21 classes")

-- ---------------------------------------------------------------- tiers (the gear set curves)
eq(C.tier(cfg, "sword", 1, 8), 16, "one-handed tier at 8")
eq(C.tier(cfg, "sword", 2, 8), 19, "two-handed is +3")
eq(C.tier(cfg, "bow", 2, 100), 68, "bow tier at 100")
eq(C.tier(cfg, "crossbow", 2, 100), 71, "crossbow is bow +3")
eq(C.tier(cfg, "sword", 1, 5000), 69, "flat after the last anchor")
eq(C.curve(cfg, "attack", 75) > 40 and C.curve(cfg, "attack", 75) < 46, true, "linear between anchors")

-- ---------------------------------------------------------------- who may wield what
local function set(...)
	local t = {}
	for _, v in ipairs({...}) do
		t[v] = true
	end
	return t
end
local byName = {}
for _, l in ipairs(cfg.lines) do
	for _, c in ipairs(l.classes) do
		byName[c.name] = c
	end
end
local sword1 = {family = "melee", kind = "sword", hands = 1}
local sword2 = {family = "melee", kind = "sword", hands = 2}
local bow = {family = "launcher", kind = "bow", hands = 2}
local xbow = {family = "launcher", kind = "crossbow", hands = 2, classes = set("Ranger", "Deadeye")}
local wand = {family = "wand", kind = "wand", hands = 1, classes = set("Mystic", "Elementalist")}
eq(C.suits(byName.Warrior, sword1), true, "warrior wields a sword")
eq(C.suits(byName.Berserker, sword1), false, "berserker: two-handed only")
eq(C.suits(byName.Berserker, sword2), true, "berserker two-handed")
eq(C.suits(byName.Warrior, bow), false, "warrior has no bow")
eq(C.suits(byName.Beastmaster, bow), true, "beastmaster bow")
eq(C.suits(byName.Beastmaster, xbow), false, "beastmaster: bows only")
eq(C.suits(byName.Ranger, xbow), true, "ranger crossbow")
eq(C.suits(byName["Bone Lord"], xbow), false, "bone lord no crossbow")
eq(C.suits(byName.Mystic, wand), true, "mystic wand")
eq(C.suits(byName.Illusionist, wand), false, "illusionist: not in the wand class list")
eq(C.suits(byName.Elementalist, sword1), false, "elementalist no sword")

-- ---------------------------------------------------------------- flags and failures on synthetic data
local function w(id, level, ratio, extra)
	local t = {id = id, level = level, ratio = ratio, family = "melee", kind = "sword", hands = 1, obtainable = true}
	for k, v in pairs(extra or {}) do
		t[k] = v
	end
	return t
end
local small = {
	bands = {{1, 100, "low"}, {100, 1000, "mid"}, {1000, 100000, "high"}},
	minOptions = 2, minPower = 0.8,
	handledElsewhere = {Other = "someone else"}, knownGaps = {{"Solo", "high", "on purpose"}},
	lines = {
		{line = "Main", classes = {{name = "Solo", families = {"melee"}}}},
		{line = "Other", classes = {{name = "Duo", families = {"melee"}}}}
	}
}
local D = {weapons = {
	w(1, 10, 1.0), w(2, 20, 1.1), -- low: two options
	w(3, 150, 1.0), -- mid: one option
	w(4, 1100, 0.5), w(5, 1200, 0.6), -- high: weak
	w(6, 300, 1.2, {obtainable = false}), -- not obtainable: not counted
}}
local A = C.audit(small, D)
eq(#A.rows, 2, "two rows")
eq(A.rows[1].cells[1].n, 2, "low has two")
eq(A.rows[1].cells[2].n, 1, "mid has one (the unobtainable one is not counted)")
eq(A.rows[1].cells[3].n, 2, "high has two")
eq(C.flag(small, A.rows[1].cells[1]), nil, "low passes")
eq(C.flag(small, A.rows[1].cells[2]), "ONE", "mid is one option")
eq(C.flag(small, A.rows[1].cells[3]), "WEAK", "high is weak")
eq(C.flag(small, {n = 0}), "ZERO", "empty is zero")
eq(C.cellText(small, A.rows[1].cells[1]), "2/110", "cell text")
eq(C.cellText(small, {n = 0}), "0", "cell text empty")
eq(#A.unobtainable, 1, "one unobtainable weapon")
local F = C.failures(small, A)
eq(#F, 1, "one failure: Solo high is a known gap, the other line is handled elsewhere")
eq(F[1].class, "Solo", "the failing class")
eq(F[1].band, "mid", "the failing band")
eq(F[1].flag, "ONE", "the failing flag")
small.knownGaps = {}
eq(#C.failures(small, A), 2, "without the known gap the weak band fails too")
small.handledElsewhere = {}
eq(#C.failures(small, A), 4, "without 'handled elsewhere' the second line fails the same cells")
small.minOptions = 1
eq(#C.failures(small, A), 2, "fewer options needed: only the weak cells fail")

-- ---------------------------------------------------------------- the curves equal the installer's
local f = assert(io.open("tools/install_gear_sets.py", "r"))
local py = f:read("*a")
f:close()
local function pyList(name)
	local body = py:match("\n" .. name .. " = %(([^)]*)%)") or py:match("'" .. name .. "':%s*%(([^)]*)%)")
	assert(body, "no " .. name .. " in install_gear_sets.py")
	local t = {}
	for v in body:gmatch("%d+") do
		t[#t + 1] = tonumber(v)
	end
	return t
end
local anchors = pyList("ANCHORS")
eq(#anchors, #cfg.anchors, "same number of anchors")
for i, v in ipairs(anchors) do
	eq(cfg.anchors[i], v, "anchor " .. i)
end
for _, name in ipairs({"attack", "bow", "wand"}) do
	local curve = pyList(name)
	eq(#curve, #cfg.curves[name], name .. ": same length")
	for i, v in ipairs(curve) do
		eq(cfg.curves[name][i], v, name .. " curve point " .. i)
	end
end

-- ---------------------------------------------------------------- the real data passes
local real = C.load(cfg)
eq(#real.notes, 0, "no loading notes: " .. table.concat(real.notes, "; "))
local RA = C.audit(cfg, real)
eq(#RA.rows, 21, "21 class rows")
local fails = C.failures(cfg, RA)
local msg = {}
for _, x in ipairs(fails) do
	msg[#msg + 1] = x.class .. " " .. x.band .. " " .. x.flag
end
eq(#fails, 0, "no coverage gap: " .. table.concat(msg, "; "))
-- every class has a weapon in every band, whatever the thresholds say
for _, row in ipairs(RA.rows) do
	for i, cell in ipairs(row.cells) do
		eq(cell.n > 0, true, row.class .. " has a weapon in " .. cfg.bands[i][3])
	end
end
-- the new uniques are counted
local seen = {}
for _, wp in ipairs(real.weapons) do
	seen[wp.name or ""] = wp
end
for _, name in ipairs({"Hoarfen Bow", "Moonlit Gallows Bow", "Hollow Throne Claymore", "Gravetide Arbalest",
	"Emberhowl Greataxe", "Wake-Heron Longbow", "Bellringer of the Last Vigil"}) do
	eq(seen[name] ~= nil, true, name .. " is in the audit")
	eq(seen[name].obtainable, true, name .. " can be obtained")
end

print("weapon_coverage_test: " .. n .. " checks ok")
