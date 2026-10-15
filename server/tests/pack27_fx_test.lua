-- Run from the server/ folder: luajit tests/pack27_fx_test.lua (no engine needed; CI runs it with luajit and lua5.3)
-- Pack farming spell effects (data/lib/chaos_pack27_fx.lua, pair 27 trial): the switch is one plain line, off; every
-- swap names a spell of spells_chaos.xml (by id and name) whose script sends the swapped name; every new name is in
-- the client spec (art_import/pack27_fx.csv) and the ids file; off, nothing is swapped and the ids file is not loaded;
-- on, the pair 27 names; _common.lua is wired.
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

dofile("data/lib/chaos_pack27_fx.lua")
local C = ChaosPack27Fx

-- the switch: one plain line, off (no published pair has effects 674-687 / missiles 154-157)
local src = readFile("data/lib/chaos_pack27_fx.lua") or ""
eq(src:match("\nC%.PAIR27_FX = (%a+)\n"), "false", "the switch is one plain line, off")
eq(C.PAIR27_FX, false, "the shipped switch is off")

-- the client spec
local spec = {}
for line in (readFile("../client/tools/sprites/art_import/pack27_fx.csv") or ""):gmatch("[^\n]+") do
	local kind, name = line:match("^(%a+),([%w_]+),")
	if kind == "effect" or kind == "missile" then
		spec[kind .. ":" .. name] = true
	end
end
local dirs = {"n", "ne", "e", "se", "s", "sw", "w", "nw"}

-- the spells: id and name as in spells_chaos.xml, the script sends the swapped names
local xml = readFile("data/spells/chaos/spells_chaos.xml") or ""
local helpers = (readFile("data/spells/chaos/_packtools.lua") or "") .. (readFile("data/spells/chaos/_blades.lua") or "")
local n = 0
for id, kinds in pairs(C.spells) do
	n = n + 1
	local name = C.names[id]
	ok(name ~= nil, "spell " .. id .. " has a name")
	local script = xml:match('spellid="' .. id .. '" name="' .. (name or "?") .. '"[^>]-script="([^"]+)"')
	ok(script ~= nil, "spells_chaos.xml has spell " .. id .. " named " .. tostring(name))
	local body = (script and readFile("data/spells/" .. script) or "") .. helpers
	for kind, swaps in pairs(kinds) do
		ok(kind == "fx" or kind == "missile" or kind == "dir", id .. ": kind " .. kind)
		for from, to in pairs(swaps) do
			ok(body:find('"' .. from .. '"', 1, true) ~= nil, tostring(name) .. " sends " .. from)
			if kind == "dir" then
				for _, d in ipairs(dirs) do
					ok(spec["effect:" .. to .. "_" .. d], to .. "_" .. d .. " in the client spec")
				end
			else
				ok(spec[(kind == "missile" and "missile:" or "effect:") .. to], to .. " in the client spec")
			end
			eq(C.pick(id, kind, from), to, "pick " .. id .. " " .. from)
		end
	end
end
eq(n, 9, "nine pack farming spells")
eq(C.pick(194, "fx", "whirlwind"), nil, "no swap for another name")
eq(C.pick(999, "fx", "aura_burst_gold"), nil, "no swap for another spell")

-- off: nothing, and the ids file is not loaded
ChaosVfx, ChaosVfxMissile = {aura_burst_gold = {id = 1, dx = 0, dy = 0}}, {}
eq(C.swapFor(194, "fx", "aura_burst_gold"), nil, "off: no swap")
eq(ChaosVfx.palm_quake, nil, "off: ids not loaded")

-- on: the ids file merges the names, the swaps come back
C.PAIR27_FX, C.loaded = true, nil
eq(C.swapFor(194, "fx", "aura_burst_gold"), "palm_quake", "on: Palm Shockwave")
eq(C.swapFor(136, "missile", "razor_disc"), "fan_knife", "on: Fan of Knives missile")
eq(C.swapFor(74, "dir", "heavy_cleave"), "iaido_dash", "on: Iaido Sweep directional")
eq(C.swapFor(73, "fx", "aura_burst_gold"), nil, "on: no swap for another name")
for key in pairs(spec) do
	local kind, name = key:match("^(%a+):(.+)$")
	local e = (kind == "missile" and ChaosVfxMissile or ChaosVfx)[name]
	ok(e ~= nil, name .. " in the ids file")
	if e and kind == "missile" then
		ok(e.id <= 255, name .. ": a missile id fits u8")
	end
end
C.PAIR27_FX, C.loaded = false, nil

-- _common.lua asks the module in fx, vfx, vfxDir, shoot and vshoot
local common = readFile("data/spells/chaos/_common.lua") or ""
for _, k in ipairs({'pack27%("fx", name%)', 'pack27%("missile", name%)', 'pack27%("dir", base%)',
		'pack27%("missile", vname%)'}) do
	ok(common:find(k) ~= nil, "_common.lua calls " .. k)
end

if failures > 0 then
	print(failures .. " failure(s)")
	os.exit(1)
end
print("pack27 fx test: OK")
