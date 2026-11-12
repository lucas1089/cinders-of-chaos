-- Run from the server/ folder: luajit tests/fx_pass_test.lua (no engine needed; CI runs it with luajit and lua5.3)
-- Spell effects pass (O457, data/lib/chaos_fx_pass.lua): the switch is one plain line; every entry names a spell of
-- spells_chaos.xml by id and name; the effect a spell sends today (the old name) is a name the registries know; every
-- new name is a ChaosVfx name once the id files are loaded (the way ChaosFxPass.live loads them); an entry never maps a
-- name to itself unless it is a deliberate step past a swap (Heretic's Brand); off, nothing is swapped; _common.lua is
-- wired, the pass is asked before the Mystic, pair 29, pair 36, class and pair 27 swaps; the three scripts that
-- send a class effect or a stock constant themselves ask the pass.
local failures = 0
local function ok(c, msg)
	if not c then
		failures = failures + 1
		print("FAIL " .. msg)
	end
end
local function eq(a, b, msg)
	ok(a == b, msg .. " (got " .. tostring(a) .. ", want " .. tostring(b) .. ")")
end
local function readFile(p)
	local f = io.open(p, "r")
	if not f then return nil end
	local s = f:read("*a")
	f:close()
	return s
end

dofile("data/lib/chaos_fx.lua")
dofile("data/lib/chaos_vfx.lua")
dofile("data/lib/chaos_vfx_art.lua")
dofile("data/lib/chaos_pack27_fx.lua")
dofile("data/lib/chaos_fx_pass.lua")
local C = ChaosFxPass

local src = readFile("data/lib/chaos_fx_pass.lua") or ""
eq(src:match("\nC%.ON = (%a+)\n"), "true", "the switch is one plain line, on")

-- the spells of the chaos spell file
local xml = readFile("data/spells/chaos/spells_chaos.xml") or ""
local byId = {}
for tag in xml:gmatch("<instant%s[^>]*>") do
	local id, name = tag:match('spellid="(%d+)"'), tag:match('name="([^"]*)"')
	if id and name then
		byId[tonumber(id)] = name
	end
end
ok(next(byId) ~= nil, "spells_chaos.xml read")

-- before the id files: nothing is live
ChaosVfx = ChaosVfx or {}
eq(C.pick(214, "fx", "holy_hit"), "p50_gold_comet_burst_4293", "pick: Dawnpiercer holy_hit")
eq(C.pick(214, "fx", "no_such_name"), nil, "pick: another name")
eq(C.pick(1, "fx", "holy_hit"), nil, "pick: a spell without an entry")
eq(C.pick(nil, "fx", "holy_hit"), nil, "pick: no spell")
eq(C.pick(214, "missile", "holy_hit"), nil, "pick: another kind")

-- the id files (the ones ChaosFxPass.live loads through ChaosPack36Fx.live and the class ids)
local savedPack36 = ChaosPack36Fx
dofile("data/lib/chaos_pack36_fx.lua")
local live = C.live()
ok(live == true, "live: the pair 36, 41, 50 and class ids load")
ok(ChaosVfx.p50_gold_comet_burst_4293 ~= nil, "live: a pair 50 name is known")
ok(ChaosVfx.warrior_quake ~= nil, "live: a class name is known")

local count, names = 0, {}
for id, s in pairs(C.spells) do
	count = count + 1
	ok(byId[id] ~= nil, "spell " .. tostring(id) .. " is in spells_chaos.xml")
	eq(C.names[id], byId[id], "spell " .. tostring(id) .. " name")
	for kind, map in pairs(s) do
		ok(kind == "fx", "spell " .. tostring(id) .. ": the kind " .. tostring(kind) .. " is fx")
		for old, new in pairs(map) do
			names[new] = true
			ok(ChaosFx[old] ~= nil or ChaosVfx[old] ~= nil or ChaosVfx[old .. "_e"] ~= nil, "spell " .. tostring(id) .. ": the old name " .. old .. " is a known effect")
			ok(ChaosVfx[new] ~= nil, "spell " .. tostring(id) .. ": the new name " .. new .. " is a ChaosVfx name")
			eq(C.swapFor(id, kind, old), new, "swapFor " .. tostring(id) .. " " .. old)
			if old == new then
				ok(id == 138, "only Heretic's Brand names its own old picture: " .. tostring(id))
			end
		end
	end
end
for id in pairs(C.names) do
	ok(C.spells[id] ~= nil, "the name table has no row without an entry: " .. tostring(id))
end
ok(count >= 40, "the pass covers the rows (" .. count .. " spells)")

-- off: nothing is swapped
C.ON = false
eq(C.swapFor(214, "fx", "holy_hit"), nil, "off: no swap")
C.ON = true
eq(C.swapFor(214, "fx", "holy_hit"), "p50_gold_comet_burst_4293", "on again")
-- an unknown new name is not swapped (the id file lacks it)
C.spells[99999] = {fx = {holy_hit = "p50_no_such_name"}}
eq(C.swapFor(99999, "fx", "holy_hit"), nil, "an unknown name is ignored")
C.spells[99999] = nil

-- _common.lua: loaded, asked first
local common = readFile("data/spells/chaos/_common.lua") or ""
ok(common:find("data/lib/chaos_fx_pass.lua", 1, true) ~= nil, "_common.lua loads the module")
local iPass = common:find("local own = pass(kind, name)", 1, true)
local iQ = common:find("local Q, W = ChaosPack29Fx, ChaosSupportsSpell", 1, true)
ok(iPass ~= nil and iQ ~= nil and iPass < iQ, "pack29 asks the pass before the Mystic table")
ok(common:find("function ChaosSpell.passFx", 1, true) ~= nil, "ChaosSpell.passFx is exported")
ok(common:find('pass("fx", name)', 1, true) ~= nil, "the Fx wrapper asks the pass")

-- the scripts that send a class effect or a stock constant themselves
for _, p in ipairs({"data/spells/chaos/berserker/skyfall_cleave.lua", "data/spells/chaos/berserker/rampage_leap.lua"}) do
	ok((readFile(p) or ""):find("ChaosSpell.passFx", 1, true) ~= nil, p .. " asks the pass")
end
local iai = readFile("data/spells/chaos/samurai/iaijutsu.lua") or ""
ok(iai:find("p50_yellow_rune_ring_1_4144", 1, true) ~= nil, "Iaijutsu gathers in gold")
ok(iai:find("sendMagicEffect(CONST_ME_YELLOWENERGY)", 1, true) ~= nil, "Iaijutsu keeps the stock constant as the fallback")
-- the owner's donor client effects (O525): the id file is loaded by ChaosPack36Fx.live, every name has an offset inside its picture
ok(ChaosVfx.donor_ice_hit_489 ~= nil, "live: a donor effect name is known")
local donorCount = 0
for name, e in pairs(ChaosVfx) do
	if name:match("^donor_") then
		donorCount = donorCount + 1
		ok(e.id > 4701 and e.dx >= 0 and e.dy >= 0 and e.ms > 0, "donor effect " .. name .. " has an id past pair 65 and an offset")
	end
end
eq(donorCount, 40, "40 donor effects")
eq(C.swapFor(38, "fx", "ice_shatter"), "donor_ice_hit_489", "Mirror Shards sends the donor ice burst")
-- Forked Storm (O532, owner choice): the first hit and each jump send the donor strike 4707; its art (5x5, send offset 0,0) ends
-- inside the target tile (measured on pair 68: no pixel right of or below the target cell, the foot at about 148,148 px of the 160 px canvas)
eq(C.swapFor(202, "fx", "lightning_strike"), "donor_energy_strike_632", "Forked Storm sends the donor strike for the first hit")
eq(C.swapFor(202, "fx", "lightning_hit"), "donor_energy_strike_632", "Forked Storm sends the donor strike for each jump")
do
	local e = ChaosVfx.donor_energy_strike_632
	ok(e ~= nil and e.id == 4707 and e.dx == 0 and e.dy == 0, "the strike's bottom-right tile is the target tile (offset 0,0)")
end
local iaiDonor = readFile("data/spells/chaos/samurai/iaijutsu.lua") or ""
ok(iaiDonor:find("donor_holy_ring_449", 1, true) ~= nil, "Iaijutsu gathers in the donor gold ring first")
local snares = readFile("data/spells/chaos/_snares.lua") or ""
ok(snares:find("MINE_MARK", 1, true) ~= nil, "a set mine shows its element")

ChaosPack36Fx = savedPack36 or ChaosPack36Fx
if failures > 0 then
	print(failures .. " failure(s)")
	os.exit(1)
end
print("fx_pass_test: ok (" .. count .. " spells)")
