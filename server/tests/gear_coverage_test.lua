-- Run from the server/ folder: luajit tests/gear_coverage_test.lua (and lua5.3; CI runs both)
-- The gear coverage audit (tools/gear_coverage.lua, gear_coverage_config.lua): the slots, the flags, the known gaps,
-- the README markers, the fairness of the weapon drops, and the real data passes.

local n = 0
local function eq(a, b, m)
	n = n + 1
	if a ~= b then
		error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2)
	end
end

GEAR_COVERAGE_NO_MAIN = true
local C = dofile("tools/gear_coverage.lua")
local cfg = dofile("tools/gear_coverage_config.lua")
local wcfg = dofile("tools/weapon_coverage_config.lua")

-- ---------------------------------------------------------------- config
eq(#cfg.slots, 9, "nine slots")
local keys = {}
for _, s in ipairs(cfg.slots) do
	keys[s.key] = s
	eq(s.min >= 2, true, s.key .. " asks for at least two options")
end
for _, k in ipairs({"helmet", "armor", "legs", "boots", "shield", "book", "quiver", "amulet", "ring"}) do
	eq(keys[k] ~= nil, true, k .. " is audited")
end
eq(cfg.minPower >= 0.8, true, "the best option at least 80% of the curve")
eq(#cfg.who.quiver, 3, "three launcher classes wear a quiver")
eq(#cfg.who.book, 6, "six caster classes wear a spellbook")
eq(#cfg.who.shield, 5, "five shield classes")
local weighted = 0
for _, list in pairs(cfg.weight) do
	weighted = weighted + #list
end
eq(weighted, 21, "every class has an armor weight")

-- ---------------------------------------------------------------- flags
local cell = function(nn, good) return {n = nn, good = good, list = {}} end
local sc = {key = "helmet", min = 3}
eq(C.flag(cfg, sc, cell(0, 0)), "ZERO", "no option")
eq(C.flag(cfg, sc, cell(2, 2)), "FEW", "two options")
eq(C.flag(cfg, sc, cell(5, 2)), "WEAK", "five options, two at full strength")
eq(C.flag(cfg, sc, cell(3, 3)), nil, "three at full strength pass")

-- ---------------------------------------------------------------- the real data
local D = C.load(cfg, wcfg)
local A = C.audit(cfg, wcfg, D)
eq(#C.failures(cfg, wcfg, A), 0, "no gap in the real data")
eq(D.byId[27696] ~= nil, true, "the stock quiver is in the data")
-- a Ranger has a quiver in every band, a caster a spellbook, and everyone a helmet, armor, legs, boots and ring
local function row(slot, class)
	for _, r in ipairs(A.rows) do
		if r.slot == slot and r.class == class then
			return r
		end
	end
end
for i = 1, #wcfg.bands do
	eq(row("quiver", "Ranger").cells[i].n >= 2, true, "Ranger quiver in band " .. i)
	eq(row("quiver", "Beastmaster").cells[i].n >= 2, true, "Beastmaster quiver in band " .. i)
	eq(row("book", "Mystic").cells[i].n >= 3, true, "Mystic spellbook in band " .. i)
	eq(row("book", "Lich").cells[i].n >= 3, true, "Lich spellbook in band " .. i)
	for _, slot in ipairs({"helmet", "armor", "legs", "boots", "ring", "amulet"}) do
		eq(row(slot, "Monk").cells[i].n >= 3, true, "Monk " .. slot .. " in band " .. i)
		eq(row(slot, "Necromancer").cells[i].n >= 3, true, "Necromancer " .. slot .. " in band " .. i)
	end
	eq(row("shield", "Warrior").cells[i].n >= 3, true, "Warrior shield in band " .. i)
end
-- classes with no off-hand item have no row
eq(row("shield", "Ranger"), nil, "Ranger has no shield row")
eq(row("quiver", "Warrior"), nil, "Warrior has no quiver row")
eq(row("book", "Thief"), nil, "Thief has no spellbook row")

-- the new uniques are in the data and can be obtained
local byName = {}
for _, it in ipairs(D.items) do
	byName[it.name] = it
end
for _, name in ipairs({"Fletcher's First Sheath", "Hollow-Reed Quiver", "Gravewind Quiver", "Quiver of Shattered Skies",
	"Ember-Lashed Quiver", "Nightglass Quiver", "Quiver of the Last Volley", "Hollow Sun Quiver", "Primer of Small Fires",
	"Codex of the Unwritten End", "Cinder Knuckle Band", "Pilgrim's Reliquary", "Emberwake Locket",
	"Crown of Ten Thousand Cinders", "Veil of the Quiet Throne", "Pyre-Sworn Cuirass", "Greaves of the Final Ash"}) do
	eq(byName[name] ~= nil, true, name .. " is in the audit")
	eq(byName[name] and C.level(byName[name]) ~= nil, true, name .. " can be obtained")
end
eq(byName["Hollow Sun Quiver"].slot, "quiver", "a quiver unique is a quiver")
eq(byName["Primer of Small Fires"].slot, "book", "a spellbook unique is a spellbook")

-- ---------------------------------------------------------------- the README table
local W = dofile("tools/weapon_coverage.lua")
local text = W.readFile("README.md")
eq(C.readmeReplace(text, C.readmeBlock(cfg, wcfg, A)), text, "server/README.md holds the current table")
eq(C.readmeReplace("no markers", "x"), nil, "no markers, no replacement")
local one = C.BEGIN .. "\nold\n" .. C.END
eq(C.readmeReplace("a\n" .. one .. "\nb", "NEW"), "a\nNEW\nb", "the block is replaced")

-- ---------------------------------------------------------------- fairness
local F = C.fairness(cfg, wcfg)
eq(#F.fails, 0, "no class is left behind in weapon drops")
eq(#F.rows, 21, "21 classes")
for _, r in ipairs(F.rows) do
	for i, v in ipairs(r.cells) do
		eq(v > 0, true, r.class .. " finds a usable weapon in the hunting band " .. F.edges[i])
	end
end

print("gear_coverage_test: " .. n .. " checks ok")
