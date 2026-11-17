-- Run from the server/ folder: luajit tests/lightning_fx_test.lua (and lua5.3; CI runs both)
-- The bolt from the sky, drawn by code (O614, client pair 73, data/lib/chaos_lightning_fx.lua and the generated
-- chaos_lightning_fx_ids.lua): the gate is config.lua chaosClientPair >= 73; below it Vfx(pos, "lightning_strike") sends
-- effect 458 as before; with it the new ids go out at their send offsets, the three shapes in turn, a boss strike one
-- heavy bolt in four; `raw` and every other name are untouched; the ids are the block 5331.. in order and tagged energy;
-- every file that names the old bolt is a listed sender, and the two boss scripts ask the lib.
local n = 0
local function eq(a, b, m)
	n = n + 1
	if a ~= b then
		error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2)
	end
end
local function ok(v, m)
	n = n + 1
	if not v then
		error(m or "not true", 2)
	end
end
local function slurp(path)
	local f = assert(io.open(path, "r"), path)
	local text = f:read("*a")
	f:close()
	return text
end

-- ---------------------------------------------------------------- a small engine
local sent = {}
local PosMeta = {}
PosMeta.__index = PosMeta
function PosMeta:sendMagicEffect(id, who)
	sent[#sent + 1] = {x = self.x, y = self.y, z = self.z, id = id, who = who}
end
function Position(x, y, z)
	return setmetatable({x = x, y = y, z = z}, PosMeta)
end

dofile("data/lib/chaos_vfx.lua")
local OLD = ChaosVfx.lightning_strike
eq(OLD.id, 458, "the old bolt is effect 458")
ChaosAreaFx = false -- the area swap of O607 is not under test here

-- ---------------------------------------------------------------- gate off: exactly as before
local at = Position(100, 200, 7)
ok(Vfx(at, "lightning_strike"), "gate off: the effect goes out")
local C = ChaosLightningFx
ok(C, "Vfx loads the lib on its first call")
eq(C.PAIR, 73, "pair 73")
eq(C.ON, false, "no config.lua next to the tests: the gate is off")
eq(#sent, 1, "gate off: one effect")
eq(sent[1].id, 458, "gate off: effect 458")
eq(sent[1].x, 100 + OLD.dx, "gate off: its send offset x")
eq(sent[1].y, 200 + OLD.dy, "gate off: its send offset y")
eq(C.swap("lightning_strike"), "lightning_strike", "gate off: the name as asked")
eq(C.boss("lightning_strike"), "lightning_strike", "gate off: a boss strike too")
eq(ChaosLightningFxIds, nil, "gate off: the ids are not even loaded")
eq(ChaosVfx.lf_bolt_a, nil, "gate off: no name merged")

-- the pair record
eq(C.parsePair("chaosClientPair = 73"), 73, "plain")
eq(C.parsePair("x = 1\nchaosClientPair=72 -- shipped\ny = 2\n"), 72, "comment, no spaces, other lines")
eq(C.parsePair("chaosClientPair = \"abc\"\n"), nil, "not a number")
eq(C.parsePair(nil), nil, "no text")
eq(C.recordedPair("tests/no_such_config.lua"), nil, "no file")

-- ---------------------------------------------------------------- gate on
C.ON = true
C.loaded = nil
sent = {}
ok(C.live(), "gate on: the ids load")
local I = ChaosLightningFxIds
ok(I, "the generated ids")
eq(I.pair, 73, "the ids are of pair 73")
eq(I.first, 5331, "after the last effect of the steps before (5330)")
eq(I.count, #C.std + #C.heavy, "every effect of the pair has a use")
local seen = {}
for name, e in pairs(I.effects) do
	ok(e.id >= I.first and e.id < I.first + I.count, name .. ": in the block")
	ok(not seen[e.id], name .. ": its own id")
	seen[e.id] = true
	ok(e.ms >= 400 and e.ms <= 900, name .. ": a strike of half a second or so")
	eq(e.tint, "energy", name .. ": energy, as the bolt it stands in for")
	eq(ChaosVfx[name].id, e.id, name .. ": merged into ChaosVfx")
end
for _, name in ipairs(C.std) do
	eq(I.effects[name].size, "std", name .. " is a plain bolt")
end
for _, name in ipairs(C.heavy) do
	eq(I.effects[name].size, "heavy", name .. " is a heavy bolt")
end

-- the door of Vfx: the three shapes in turn, each at its own send offset
for i = 1, 4 do
	ok(Vfx(at, "lightning_strike"), "gate on: sent")
	local e = I.effects[C.std[(i - 1) % #C.std + 1]]
	eq(sent[i].id, e.id, "gate on: shape " .. i)
	eq(sent[i].x, 100 + e.dx, "gate on: the send offset x")
	eq(sent[i].y, 200 + e.dy, "gate on: the send offset y")
	eq(sent[i].z, 7, "the floor")
end
eq(#sent, 4, "one effect a call: the old bolt is not sent as well")
ok(Vfx(at, "lightning_strike", true), "raw")
eq(sent[5].id, 458, "raw: effect 458, for a caller that wants the old picture")
ok(Vfx(at, "lightning_hit"), "another name")
eq(sent[6].id, ChaosVfx.lightning_hit.id, "another energy effect is not touched")
eq(C.swap("holy_smite"), "holy_smite", "nor the holy column")
eq(C.swap(nil), nil, "no name")
eq(Vfx(at, "no_such_effect"), false, "an unknown name sends nothing")

-- a boss strike: one heavy bolt in C.heavyEvery, the two heavy shapes in turn, the others plain
C.turn = {std = 0, heavy = 0, boss = 0}
local kinds = {}
for i = 1, 2 * C.heavyEvery do
	local name = C.boss("lightning_strike")
	kinds[i] = I.effects[name].size
	ok(ChaosVfx[name], "a boss strike names an effect the senders' fx finds")
end
eq(table.concat(kinds, " "), "heavy std std std heavy std std std", "one heavy bolt in four")
C.turn = {std = 0, heavy = 0, boss = 0}
eq(C.boss("lightning_strike"), "lf_bolt_heavy_a", "the first heavy shape")
for _ = 2, C.heavyEvery do
	C.boss("lightning_strike")
end
eq(C.boss("lightning_strike"), "lf_bolt_heavy_b", "then the second")
eq(C.boss("lightning_hit"), "lightning_hit", "a boss effect of another name is not touched")
eq(C.boss(nil), nil, "no name")

-- a pair that lacks a shape: the next one; none at all: the old bolt
local keep = ChaosVfx.lf_bolt_b
ChaosVfx.lf_bolt_b = nil
C.turn = {std = 0, heavy = 0, boss = 0}
eq(C.swap("lightning_strike"), "lf_bolt_a", "first")
eq(C.swap("lightning_strike"), "lf_bolt_c", "the missing shape is skipped")
ChaosVfx.lf_bolt_b = keep
local all = {}
for _, name in ipairs(C.std) do
	all[name], ChaosVfx[name] = ChaosVfx[name], nil
end
eq(C.swap("lightning_strike"), "lightning_strike", "no shape known: the old bolt")
for name, e in pairs(all) do
	ChaosVfx[name] = e
end

-- ---------------------------------------------------------------- the files
-- the ids file is the tool's table, and every id is tagged energy for the spell effect check
local csv = slurp("../client/tools/sprites/art_import/lightning_fx.csv")
local tags = slurp("data/spells/spell_fx_elements.csv")
local rows = 0
for id, name in csv:gmatch("\neffect,(%d+),([%w_]+),") do
	rows = rows + 1
	eq(I.effects[name] and I.effects[name].id, tonumber(id), name .. ": the id of the table")
	ok(tags:find("\n" .. id .. "," .. name .. ",energy\n", 1, true), name .. ": tagged energy")
end
eq(rows, I.count, "one row per effect")

-- every script that names the old bolt is a listed sender (a new one must be looked at: std, boss or none)
local SCAN = {"data/spells/chaos/sorcerer/cataclysm.lua", "data/spells/chaos/sorcerer/glacial_doom.lua",
	"data/spells/chaos/sorcerer/chain_lightning.lua", "data/lib/chaos_pack_fx.lua",
	"data/scripts/chaos/boss_mechanics_config.lua", "data/scripts/chaos/uber_config.lua"}
local listed = 0
for file, s in pairs(C.senders) do
	listed = listed + 1
	ok(slurp(file):find('"lightning_strike"', 1, true), file .. " names the old bolt")
	ok(s.bolt == "std" or s.bolt == "boss" or s.bolt == "none", file .. ": which bolt")
	ok(type(s.what) == "string" and #s.what > 10, file .. ": what it is")
end
eq(listed, #SCAN, "the senders of the list")
for _, file in ipairs(SCAN) do
	ok(C.senders[file], file .. " is listed")
end
-- Forked Storm keeps the owner's donor strike: the effects pass changes the name before Vfx
ok(slurp("data/lib/chaos_fx_pass.lua"):find('lightning_strike = "donor_energy_strike_632"', 1, true), "Forked Storm: the pass comes first")
-- the two boss scripts ask the lib before they look the name up, the door of Vfx asks it for everything else
for _, file in ipairs({"data/scripts/chaos/boss_mechanics.lua", "data/scripts/chaos/uber.lua"}) do
	local text = slurp(file)
	ok(text:find("ChaosLightningFx.boss(name)", 1, true), file .. " asks for the boss bolt")
	ok(text:find("name = skyHeavy(name)", 1, true), file .. ": in its fx")
end
ok(slurp("data/lib/chaos_vfx.lua"):find("name = skySwap(areaSwap(name))", 1, true), "Vfx asks the lib")
ok(slurp("../client/tools/sprites/import_vfx.py"):find("name = skySwap(areaSwap(name))", 1, true), "and the tool that writes chaos_vfx.lua keeps it")

print("lightning_fx_test: " .. n .. " checks passed")
