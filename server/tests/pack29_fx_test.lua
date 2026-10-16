-- Run from the server/ folder: luajit tests/pack29_fx_test.lua (no engine needed; CI runs it with luajit and lua5.3)
-- Mystic line effects, Tier B (data/lib/chaos_pack29_fx.lua, pair 29): the switch is one plain line, off; every swap
-- names a spell of spells_chaos.xml (by id and name) whose script sends the swapped name; every new name is in the
-- client spec (art_import/pack29_fx.csv) and the ids file, and every spec name is sent by something; off, nothing is
-- swapped and the ids file is not loaded; on, the pair 29 names through _common.lua and ChaosMysticFx.
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

dofile("data/lib/chaos_pack29_fx.lua")
local C = ChaosPack29Fx

-- the switch: one plain line, off until pair 29 is live
local src = readFile("data/lib/chaos_pack29_fx.lua") or ""
eq(C.PAIR29, true, "the switch is on (pair 29 live)")
eq(src:match("\nC%.PAIR29 = (%a+)\n"), tostring(C.PAIR29), "the switch is one plain line")

-- the client spec
local spec, specNames = {}, {}
for line in (readFile("../client/tools/sprites/art_import/pack29_fx.csv") or ""):gmatch("[^\n]+") do
	local kind, name = line:match("^(%a+),([%w_]+),")
	if kind == "effect" or kind == "missile" then
		spec[kind .. ":" .. name] = true
		specNames[#specNames + 1] = kind .. ":" .. name
	end
end
ok(#specNames >= 25, "the client spec lists the pair 29 effects and missiles")

-- the spells: id and name as in spells_chaos.xml, the script sends the swapped names
local xml = readFile("data/spells/chaos/spells_chaos.xml") or ""
local used = {}
local n = 0
for id, kinds in pairs(C.spells) do
	n = n + 1
	local name = C.names[id]
	ok(name ~= nil, "spell " .. id .. " has a name")
	local script = xml:match('spellid="' .. id .. '" name="' .. (name or "?") .. '"[^>]-script="([^"]+)"')
	ok(script ~= nil, "spells_chaos.xml has spell " .. id .. " named " .. tostring(name))
	local body = script and readFile("data/spells/" .. script) or ""
	for kind, swaps in pairs(kinds) do
		ok(kind == "fx" or kind == "missile" or kind == "send", id .. ": kind " .. kind)
		for from, to in pairs(swaps) do
			ok(body:find('"' .. from .. '"', 1, true) ~= nil, tostring(name) .. " sends " .. from)
			local key = (kind == "missile" and "missile:" or "effect:") .. to
			ok(spec[key], to .. " in the client spec")
			used[key] = true
			eq(C.pick(id, kind, from), to, "pick " .. id .. " " .. from)
		end
	end
end
eq(n, 17, "the Mystic line spells with pair 29 effects")
local mystic = readFile("data/lib/chaos_mystic_fx.lua") or ""
for key, swaps in pairs(C.stock) do
	ok(mystic:find(key .. " = {", 1, true) ~= nil, "stock spell " .. key .. " is wrapped by ChaosMysticFx")
	for from, to in pairs(swaps) do
		ok(mystic:find('"' .. from .. '"', 1, true) ~= nil, key .. " sends " .. from)
		local key2 = (spec["missile:" .. to] and "missile:" or "effect:") .. to
		ok(spec[key2], to .. " in the client spec")
		used[key2] = true
	end
end
-- Tear in the Weave shoots the singularity itself (no old missile to swap)
ok((readFile("data/spells/chaos/illusionist/reality_rift.lua") or ""):find('"weave_marble"', 1, true) ~= nil,
	"Tear in the Weave shoots weave_marble")
used["missile:weave_marble"] = true
for _, key in ipairs(specNames) do
	ok(used[key], key .. " is sent by a pair 29 swap")
end
eq(C.pick(230, "fx", "whirlwind"), nil, "no swap for another name")
eq(C.pick(999, "fx", "void_maw"), nil, "no swap for another spell")

-- off: nothing, and the ids file is not loaded
C.PAIR29, C.loaded = false, nil
ChaosVfx, ChaosVfxMissile = {void_maw = {id = 1, dx = 0, dy = 0}}, {}
eq(C.swapFor(230, "fx", "void_maw"), nil, "off: no swap")
eq(C.stockFor("bewitching_hex", "missile", "arcane_bolt"), nil, "off: the stock Hex keeps its missile")
eq(ChaosVfx.night_eyelid, nil, "off: ids not loaded")

-- on: the ids file merges the names, the swaps come back
C.PAIR29, C.loaded = true, nil
eq(C.swapFor(230, "fx", "void_maw"), "night_eyelid", "on: Nightburst gather")
eq(C.swapFor(201, "missile", "fireball"), "witchfire_lance", "on: Witchfire Bolt missile")
eq(C.swapFor(205, "send", "nova_frost"), "crypt_ice_strike", "on: Frozen Crypt landing")
eq(C.swapFor(206, "fx", "dome_blast_fire"), nil, "on: Doomtide's first wave keeps its nova")
eq(C.stockFor("bewitching_hex", "missile", "arcane_bolt"), "hex_missile", "on: the stock Hex missile")
eq(C.stockFor("bewitching_hex", "fx", "tick_curse"), "hex_curse", "on: the stock Hex ticks")
for key in pairs(spec) do
	local kind, name = key:match("^(%a+):(.+)$")
	local e = (kind == "missile" and ChaosVfxMissile or ChaosVfx)[name]
	ok(e ~= nil, name .. " in the ids file")
	if e and kind == "missile" then
		ok(e.id <= 255, name .. ": a missile id fits u8")
	end
	if e and kind == "effect" then
		ok(e.id >= 759, name .. ": an effect of pair 29")
	end
end

-- ChaosMysticFx: send / shoot take the casting spell's pair 29 name; off, the same name
dofile("data/lib/chaos_mystic_fx.lua")
local M = ChaosMysticFx
local cast = {nil, nil}
ChaosSupportsSpell = {cast = function() return cast[1], cast[2] end}
Position = function(x, y, z)
	if type(x) == "table" then return x end
	return {x = x, y = y, z = z}
end
local sent, shot = {}, {}
Vfx = function(pos, name) sent[#sent + 1] = name return ChaosVfx[name] ~= nil end
VfxShoot = function(a, b, name) shot[#shot + 1] = name return ChaosVfxMissile[name] ~= nil end
cast = {7, 228}
eq(M.alt("send", "px03_arcane"), "psyche_fracture", "on: Shattered Psyche impact")
eq(M.send({x = 1, y = 1, z = 7}, "px03_arcane"), true, "on: sent")
eq(sent[#sent], "psyche_fracture", "on: the pair 29 effect went out")
cast = {7, 96}
eq(M.shoot({x = 1, y = 1, z = 7}, {x = 3, y = 1, z = 7}, "arcane_bolt"), true, "on: Mirror Mend shot")
eq(shot[#shot], "mend_shards", "on: the mirror shards")
cast = {7, 231}
eq(M.shoot({x = 1, y = 1, z = 7}, {x = 3, y = 1, z = 7}, "weave_marble"), true, "on: the singularity")
cast = {nil, nil}
eq(M.alt("send", "px03_arcane"), "px03_arcane", "no cast: the same name")
local plan = M.stockPlan("bewitching_hex", 300)
eq(plan[1][3], "hex_missile", "on: the Hex plan shoots the pair 29 missile")
eq(plan[3][3], "hex_curse", "on: the Hex plan ticks the pair 29 curse")
C.PAIR29 = false
cast = {7, 228}
eq(M.alt("send", "px03_arcane"), "px03_arcane", "off: the same name")
plan = M.stockPlan("bewitching_hex", 300)
eq(plan[1][3], "arcane_bolt", "off: the Hex plan keeps arcane_bolt")
eq(plan[3][3], "tick_curse", "off: the Hex plan keeps tick_curse")
ChaosVfxMissile.weave_marble = nil
cast = {7, 231}
eq(M.shoot({x = 1, y = 1, z = 7}, {x = 3, y = 1, z = 7}, "weave_marble"), false, "off: no singularity")
ChaosSupportsSpell, Vfx, VfxShoot, Position = nil, nil, nil, nil

-- _common.lua asks the module first (pack27 helper) and gives the scripts pack29Name
local common = readFile("data/spells/chaos/_common.lua") or ""
ok(common:find("local p29 = pack29(kind, name)", 1, true) ~= nil, "_common.lua asks pair 29 before pair 27")
ok(common:find("function ChaosSpell.pack29Name", 1, true) ~= nil, "_common.lua has pack29Name")
for _, f in ipairs({"sorcerer/hexfire_bolt.lua", "illusionist/mind_fracture.lua"}) do
	ok((readFile("data/spells/chaos/" .. f) or ""):find('ChaosSpell.pack29Name("missile", ', 1, true) ~= nil,
		f .. " shoots through pack29Name")
end

if failures > 0 then
	print(failures .. " failure(s)")
	os.exit(1)
end
print("pack29 fx test: OK")
