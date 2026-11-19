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
eq(#cfg.bands, 10, "ten bands")
eq(cfg.bands[1][3], "1-20", "first band label")
eq(cfg.bands[10][3], "1700-2400+", "last band label")
eq(C.bandOf(cfg, 1), 1, "level 1")
eq(C.bandOf(cfg, 19), 1, "level 19")
eq(C.bandOf(cfg, 20), 2, "level 20 opens the second band")
eq(C.bandOf(cfg, 1299), 8, "level 1299")
eq(C.bandOf(cfg, 1300), 9, "level 1300 opens the 1300-1700 band")
eq(C.bandOf(cfg, 1699), 9, "level 1699")
eq(C.bandOf(cfg, 1700), 10, "level 1700 opens the last band")
eq(C.bandOf(cfg, 2400), 10, "level 2400")
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
eq(C.tier(cfg, "sword", 1, 5000), 199, "flat after the last anchor (O472: 69 times the weapon growth a(2000) = 2.88)")
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
-- O472: the weapon curves (attack, bow, wand) and their anchors are WEAPON_CURVES / WEAPON_ANCHORS of the installer
local function pyList(name, block)
	local text = block and (py:match("\n" .. block .. " = %{(.-)\n%}") or error("no " .. block)) or py
	local body = text:match("\n" .. name .. " = %(([^)]*)%)") or text:match("'" .. name .. "':%s*%(([^)]*)%)")
	assert(body, "no " .. name .. " in install_gear_sets.py")
	local t = {}
	for v in body:gmatch("%d+") do
		t[#t + 1] = tonumber(v)
	end
	return t
end
local anchors = pyList("WEAPON_ANCHORS")
eq(#anchors, #cfg.anchors, "same number of anchors")
for i, v in ipairs(anchors) do
	eq(cfg.anchors[i], v, "anchor " .. i)
end
for _, name in ipairs({"attack", "bow", "wand"}) do
	local curve = pyList(name, "WEAPON_CURVES")
	eq(#curve, #cfg.curves[name], name .. ": same length")
	eq(#curve, #anchors, name .. ": one value per anchor")
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

-- ---------------------------------------------------------------- equip access (O329)
do
	local function w(kind, hands, list, extra)
		local t = {id = 1, name = "t", kind = kind, family = ({sword = "melee", bow = "launcher", crossbow = "launcher", wand = "wand"})[kind],
			hands = hands, level = 10, power = 1, origin = "stock", classes = {}}
		for _, name in ipairs(list) do
			t.classes[name] = true
		end
		for k, v in pairs(extra or {}) do
			t[k] = v
		end
		return t
	end
	local RANGER = {"Ranger", "Deadeye", "Beastmaster"}
	local MELEE2 = {"Warrior", "Juggernaut", "Berserker", "Thief", "Ninja", "Samurai", "Monk", "Shadowfist", "Iron Sage",
		"Templar", "Inquisitor", "Sentinel"}
	local function problems(...)
		return C.accessProblems(cfg, {weapons = {...}})
	end
	eq(#problems(w("bow", 2, RANGER)), 0, "a bow for the Ranger line is fine")
	local p = problems(w("bow", 2, {"Ranger", "Deadeye"}))
	eq(#p, 1, "a bow without the Beastmaster is one problem")
	eq(p[1]:find("Beastmaster", 1, true) ~= nil, true, "it names the Beastmaster")
	eq(#problems(w("crossbow", 2, {"Ranger", "Deadeye"})), 0, "a crossbow is for the Ranger and the Deadeye only")
	eq(#problems(w("crossbow", 2, RANGER)), 1, "a crossbow listing the Beastmaster contradicts the bow-only rule")
	eq(#problems(w("sword", 2, MELEE2)), 0, "a two-handed sword for every melee class")
	eq(#problems(w("sword", 1, MELEE2)), 1, "a one-handed sword listing the Berserker")
	eq(#problems(w("sword", 2, {"Warrior", "Juggernaut", "Thief", "Ninja", "Samurai", "Monk", "Shadowfist", "Iron Sage",
		"Templar", "Inquisitor", "Sentinel"})), 1, "a two-handed sword without the Berserker")
	local WAND = {"Mystic", "Necromancer", "Lich", "Bone Lord"}
	local function plus(list, name)
		local t = {}
		for _, v in ipairs(list) do
			t[#t + 1] = v
		end
		t[#t + 1] = name
		return t
	end
	eq(#problems(w("wand", 1, plus(WAND, "Elementalist"))), 0, "a wand for the Elementalist")
	eq(#problems(w("wand", 1, plus(WAND, "Illusionist"))), 0, "a rod for the Illusionist")
	eq(#problems(w("wand", 1, WAND)) >= 1, true, "a wand for neither")
	eq(#problems(w("bow", 2, {"Ranger"}, {origin = "unique"})), 0, "uniques have their own equip lines")
	local nolist = w("bow", 2, {"Ranger"})
	nolist.classes = nil
	eq(#problems(nolist), 0, "no list: everyone")
end

-- ---------------------------------------------------------------- weapon families (O454): sword, axe and club per class and band
do
	eq(cfg.familyMinOptions >= 3 and cfg.familyMinFamilies >= 2, true, "families: three weapons in at least two of them")
	eq(#cfg.familyLines, 3, "the Warrior, Thief and Templar lines get the traits (not the Monk line)")
	for _, l in ipairs(cfg.familyLines) do
		eq(l ~= "Monk", true, "the Monk line is not a family line")
	end
	local D = C.load(cfg)
	local A = C.audit(cfg, D)
	local rows = C.familyRows(cfg, A)
	eq(#rows, 9, "nine classes in the family table")
	local names = {}
	for _, r in ipairs(rows) do
		names[#names + 1] = r.class
		eq(#r.cells, #cfg.bands, r.class .. " has a cell per band")
	end
	eq(table.concat(names, ","), "Warrior,Juggernaut,Berserker,Thief,Ninja,Samurai,Templar,Inquisitor,Sentinel", "the classes, in order")
	eq(#C.familyFailures(cfg, rows), 0, "the shipped data passes (the Berserker gaps are listed)")
	-- the numbers of one cell agree with the plain audit
	for _, r in ipairs(rows) do
		for i, cell in ipairs(A.rows[1].cells) do
			local c = r.cells[i]
			local audit
			for _, ar in ipairs(A.rows) do
				if ar.class == r.class then
					audit = ar.cells[i]
				end
			end
			-- the Thief line also has throwing weapons (family "throw"), which are no melee family
			eq(c.sword + c.axe + c.club <= audit.n, true, r.class .. " band " .. i .. ": the three families are in the band")
			if r.line ~= "Thief" then
				eq(c.sword + c.axe + c.club, audit.n, r.class .. " band " .. i .. ": and are the whole band")
			end
		end
	end
	-- a gap that is not listed fails, a listed one that is not a gap fails too
	local fake = {{class = "X", cells = {{sword = 5, axe = 1, club = 0, families = 1}}}}
	local f1 = C.familyFailures(cfg, fake)
	eq(#f1 >= 1 and f1[1].text:find("only 1 family", 1, true) ~= nil, true, "an unlisted one-family cell fails")
	-- O500 (2026-11-11): the Berserker's cells 1-20 and 1000-1300 left the known gaps when stock weapons moved to the kind their name says
	-- (patch_stock_weapon_types.py); the one left is the last band (1700-2400+), so the fake cells are the bands of the config
	local goodCells = {}
	for i = 1, #cfg.bands do
		goodCells[i] = {sword = 5, axe = 4, club = 0, families = 2}
	end
	local good = {{class = "Berserker", cells = goodCells}}
	local f2 = C.familyFailures(cfg, good)
	eq(f2[1] and f2[1].text:find("no gap any more", 1, true) ~= nil, true, "a known gap that is not one any more fails")
	eq(C.familyCellText(cfg, rows[3], #cfg.bands), "2/7/2*", "a known gap is starred")
	eq(C.familyCellText(cfg, rows[3], 1), "3/3/2", "a Berserker cell that is no gap any more is plain")
	eq(C.familyCellText(cfg, rows[1], 1), "30/9/16", "a plain cell is three numbers")
	eq(C.familyMarkdown(cfg, rows):find("| Berserker | 3/3/2 |", 1, true) ~= nil, true, "the markdown table")
	eq(C.familyText(cfg, rows):find("Sentinel", 1, true) ~= nil, true, "the plain table")
end

-- ---------------------------------------------------------------- the physical attack the weapon spells read (O673)
do
	-- the stock rule: the total is kept, the element damage is at most 35% of it (tools/stock_weapon_physical.py is the same rule)
	eq(cfg.stockPhysical.share, 0.35, "the share of the sets")
	local function stock(kind, level, attack, element, charges)
		local a, e = C.stockGrowth({kind = kind, level = tostring(level), attack = tostring(attack), element = tostring(element),
			charges = tostring(charges or 0)}, cfg)
		return a, e
	end
	local a0, e0 = stock("sword", 600, 8, 46)
	local a1, e1 = stock("sword", 100, 8, 46)
	eq(a1 + e1, 54, "a weapon of level 100 does not grow and is not split")
	eq(e1, 46, "level 100 keeps its element")
	eq(a0 + e0, 86, "a sword of level 600: the total after the growth, 13 + 73")
	eq(e0, 30, "the element is 35% of 86")
	eq(a0, 56, "the rest is physical attack")
	local a2, e2 = stock("axe", 400, 60, 0)
	eq(a2 .. "/" .. e2, "85/0", "a plain physical weapon stays")
	local a3, e3 = stock("club", 400, 40, 12)
	eq(e3 <= math.floor((a3 + e3) * 0.35 + 0.5), true, "a small element stays under the cap")
	local a4, e4 = stock("sword", 330, 0, 50)
	eq(a4 > 0 and a4 + e4 == 67, true, "an attack of 0 becomes physical: total 67")
	local a5, e5 = stock("bow", 600, 8, 46)
	eq(a5 .. "/" .. e5, "13/73", "a bow is not split")
	local a6, e6 = stock("sword", 600, 8, 46, 5)
	eq(a6 .. "/" .. e6, "8/46", "a weapon with charges is left alone")

	-- the audit on synthetic weapons
	local D = {weapons = {
		{id = 1, family = "melee", kind = "sword", hands = 1, level = 650, phys = 13, physRatio = 13 / 91, obtainable = true, origin = "stock"},
		{id = 2, family = "melee", kind = "sword", hands = 1, level = 650, phys = 59, physRatio = 59 / 91, obtainable = true, origin = "set:x"},
		{id = 3, family = "melee", kind = "axe", hands = 1, level = 650, phys = 59, physRatio = 59 / 91, obtainable = true, origin = "set:x"},
		{id = 4, family = "melee", kind = "axe", hands = 1, level = 650, phys = 80, physRatio = 80 / 91, obtainable = false, origin = "stock"},
		{id = 5, family = "wand", kind = "wand", hands = 1, level = 650, power = 100, ratio = 1, obtainable = true, origin = "stock"}
	}}
	local rows = C.physAudit(cfg, D)
	local jug
	for _, r in ipairs(rows) do
		if r.class == "Juggernaut" then
			jug = r
		end
		eq(r.class ~= "Mystic" and r.class ~= "Ranger", true, "only the melee classes are audited")
	end
	local cell = jug.cells[6]
	eq(cell.total, 3, "three obtainable melee weapons in the band (the unobtainable one and the wand do not count)")
	eq(cell.n, 2, "two have a physical attack of 60% of the tier or more")
	eq(C.physFlag(cfg, cell), "ONE", "two are too few")
	eq(C.physFlag(cfg, {n = 0}), "ZERO", "none")
	eq(C.physFlag(cfg, {n = 3}), nil, "three pass")
	eq(#C.physFailures(cfg, rows) > 0, true, "the failures list the bands")
	local stockRows = C.physAudit(cfg, D, "stock")
	for _, r in ipairs(stockRows) do
		if r.class == "Juggernaut" then
			eq(r.cells[6].total, 1, "only the stock weapon counts with an origin")
			eq(r.cells[6].n, 0, "and its physical attack is 14% of the tier")
		end
	end

	-- the shipped data: every melee class, the Thief and Monk lines included, has the options in every band up to 2400+
	local data = C.load(cfg)
	local real = C.physAudit(cfg, data)
	local seen = {}
	for _, r in ipairs(real) do
		seen[r.class] = true
		for i, c in ipairs(r.cells) do
			eq(c.n >= cfg.minOptions, true, r.class .. " band " .. cfg.bands[i][3] .. ": " .. c.n .. " weapons with a physical attack of " .. cfg.physMin)
		end
	end
	for _, name in ipairs({"Warrior", "Juggernaut", "Berserker", "Thief", "Ninja", "Samurai", "Monk", "Shadowfist", "Iron Sage",
			"Templar", "Inquisitor", "Sentinel"}) do
		eq(seen[name], true, name .. " is audited")
	end
	eq(#C.physFailures(cfg, real), 0, "the shipped data passes")
	-- no stock melee weapon that grows has more than the share as element
	for _, w in ipairs(data.weapons) do
		if w.origin == "stock" and w.family == "melee" and w.charges == 0 and w.level > cfg.stockGrowth.fromLevel then
			local total = w.power
			eq(w.phys >= total - math.floor(total * cfg.stockPhysical.share + 0.5), true, "stock weapon " .. w.id .. ": the element is at most 35%")
		end
	end
	-- the Juggernaut's stock weapons of the levels 600 to 999 read a physical attack of 56 or more (before O673: 13 to 16)
	local best = 0
	for _, w in ipairs(data.weapons) do
		if w.origin == "stock" and w.family == "melee" and w.level == 600 then
			best = math.max(best, w.phys)
		end
	end
	eq(best >= 60, true, "the best stock weapon of level 600 has a physical attack of 60 or more: " .. best)
end

print("weapon_coverage_test: " .. n .. " checks ok")
