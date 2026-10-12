-- Run from the server/ folder: luajit tests/class_fx_test.lua (no engine needed; CI runs it with luajit and lua5.3)
-- Class signature effects (data/lib/chaos_class_fx.lua): the vocation table equals Chaos.classes.ids, every swap is a
-- spell the class may cast and an effect name that spell's script sends, every class effect is in the generated ids
-- (chaos_class_fx_ids.lua) and the art spec (class_fx.csv); a class takes its line's swaps and its own win; the pair
-- switch is off and then nothing changes; on, the _common.lua hooks send the class effect during a cast (a cosmetic
-- skin first, the default outside a cast, per-tile Fx only for effects on the tile itself).
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

-- engine mocks: effects are recorded
local effects = {}
local PosMT = {}
PosMT.__index = PosMT
function PosMT:sendMagicEffect(id) effects[#effects + 1] = {id = id, x = self.x, y = self.y} end
function PosMT:sendDistanceEffect() end
Position = function(x, y, z)
	if type(x) == "table" then x, y, z = x.x, x.y, x.z end
	return setmetatable({x = x, y = y, z = z}, PosMT)
end
local vocOf = {}
Player = function(pid)
	local v = vocOf[pid]
	return v and {getVocation = function() return {getId = function() return v end} end} or nil
end
NORTH, EAST, SOUTH, WEST, SOUTHWEST, SOUTHEAST, NORTHWEST, NORTHEAST = 0, 1, 2, 3, 4, 5, 6, 7
CONST_ME_POFF = 3

dofile("data/lib/chaos_class_fx.lua")
local C = ChaosClassFx

-- the switch: one plain line, off until things_custom22 is on windows-assets
local src = readFile("data/lib/chaos_class_fx.lua") or ""
eq(src:match("\nC%.PAIR22_FX = (%a+)\n"), "false", "the switch is one plain line, off")

-- vocations equal Chaos.classes.ids
local consts = readFile("data/scripts/chaos/chaos_constants.lua") or ""
local idsBlock = consts:match("\tids = {(.-)\n\t},")
ok(idsBlock ~= nil, "Chaos.classes.ids found")
local n = 0
for key, id in (idsBlock or ""):gmatch("(%a+) = (%d+)") do
	n = n + 1
	eq(C.vocations[tonumber(id)], key, "vocation " .. id)
	ok(C.lineOf[key] ~= nil, key .. " has a line")
end
local m = 0
for _ in pairs(C.vocations) do m = m + 1 end
eq(m, n, "as many vocations as Chaos.classes.ids")

-- the art spec and the generated ids
local spec = {}
for line in (readFile("../client/tools/sprites/art_import/class_fx.csv") or ""):gmatch("[^\n]+") do
	local kind, name, _, w, h, _, _, dx, dy = line:match("^(%a+),([%w_]+),([^,]+),(%d+),(%d+),(%d+),(%d+),(%d+),(%d+),")
	if kind == "effect" then
		spec[name] = {w = tonumber(w), dx = tonumber(dx), dy = tonumber(dy)}
	end
end
local saved = ChaosVfx
ChaosVfx = {}
dofile("data/lib/chaos_class_fx_ids.lua")
local ids = ChaosVfx
ChaosVfx = saved
local nspec = 0
for name, s in pairs(spec) do
	nspec = nspec + 1
	ok(ids[name] ~= nil, name .. " has an id")
	if ids[name] then
		eq(ids[name].dx, s.dx, name .. " offset")
		ok(ids[name].id >= 593 and ids[name].id <= 627, name .. " id in 593..627")
	end
end
eq(nspec, 35, "35 class effects in the spec")

-- spells: id -> script and vocation names (spells_chaos.xml)
local xml = readFile("data/spells/chaos/spells_chaos.xml") or ""
local spells = {}
for attrs, body in xml:gmatch("<instant ([^>]*)>(.-)</instant>") do
	local id = tonumber(attrs:match('spellid="(%d+)"'))
	local vocs = {}
	for v in body:gmatch('vocation name="([^"]+)"') do
		vocs[v:lower():gsub(" ", "")] = true
	end
	spells[id] = {script = attrs:match('script="chaos/([^"]+)"'), vocs = vocs}
end
local used = {}
for key, bySpell in pairs(C.swaps) do
	ok(C.lineOf[key] ~= nil, "swaps for a known class " .. key)
	for id, map in pairs(bySpell) do
		local sp = spells[id]
		ok(sp ~= nil, key .. ": spell " .. id .. " exists")
		if sp then
			ok(sp.vocs[key] == true, key .. " may cast spell " .. id)
			local s = readFile("data/spells/chaos/" .. sp.script) or ""
			for from, to in pairs(map) do
				ok(s:find('"' .. from .. '"', 1, true) ~= nil, sp.script .. " sends " .. from)
				ok(spec[to] ~= nil, to .. " is drawn")
				used[to] = true
			end
		end
	end
end
for _, name in ipairs(C.unwired) do
	ok(spec[name] ~= nil, name .. " is drawn")
	used[name] = true
end
for name in pairs(spec) do
	ok(used[name], name .. " is used by a swap or listed unwired")
end

-- pick: the line's swaps, the class's own first
eq(C.pick("warrior", 223, "aura_burst_gold"), "warrior_bellow", "Warrior Iron Bellow")
eq(C.pick("juggernaut", 223, "aura_burst_gold"), "juggernaut_bulwark", "Juggernaut's own Iron Bellow")
eq(C.pick("berserker", 221, "earth_spikes"), "warrior_quake", "Berserker takes the line's Earthbreaker")
eq(C.pick("samurai", 245, "aura_burst_gold"), "samurai_focus", "Bushido Focus")
eq(C.pick("inquisitor", 250, "aura_burst_gold"), "inquisitor_zeal", "Zealotry")
eq(C.pick("templar", 250, "aura_burst_gold"), nil, "no swap for a spell not listed")
eq(C.pick("ranger", 214, "holy_spear"), nil, "no swap for another name")
eq(C.pick(nil, 214, "holy_hit"), nil, "no class")

-- switch off: nothing
vocOf[1] = 8
eq(C.live(), false, "off: not live")
eq(C.swapFor(1, 223, "aura_burst_gold"), nil, "off: no swap")

-- the _common.lua hooks
local castPid, castSpell
ChaosSupportsSpell = {cast = function() return castPid, castSpell end}
dofile("data/spells/chaos/_common.lua")
ok(ChaosVfx and ChaosVfx.aura_burst_gold, "pack effects loaded")
local P = {x = 50, y = 50, z = 7}
castPid, castSpell = 1, 223
ChaosSpell.vfx(P, "aura_burst_gold")
eq(effects[#effects].id, ChaosVfx.aura_burst_gold.id, "off: the default effect during a cast")
eq(ChaosVfx.warrior_quake, nil, "off: the class ids are not loaded")

-- switch on
C.PAIR22_FX = true
C.loaded = nil
eq(C.live(), true, "on: live")
ok(ChaosVfx.juggernaut_bulwark ~= nil, "on: ids loaded into ChaosVfx")
ok(ChaosVfx.aura_burst_gold ~= nil, "pack effects kept")
ChaosSpell.vfx(P, "aura_burst_gold")
local e = effects[#effects]
eq(e.id, ChaosVfx.juggernaut_bulwark.id, "on: the Juggernaut's Iron Bellow")
eq(e.x, P.x + ChaosVfx.juggernaut_bulwark.dx, "at its offset tile")
vocOf[2] = 4
castPid = 2
ChaosSpell.vfx(P, "aura_burst_gold")
eq(effects[#effects].id, ChaosVfx.warrior_bellow.id, "the Warrior's Iron Bellow")
castPid, castSpell = nil, nil
ChaosSpell.vfx(P, "aura_burst_gold")
eq(effects[#effects].id, ChaosVfx.aura_burst_gold.id, "outside a cast: the default")
-- ChaosSpell.fx with a 3x3 class effect: sent through Vfx at its offset
vocOf[3] = 18
castPid, castSpell = 3, 68
ChaosSpell.fx(P, "void_eye", 1)
eq(effects[#effects].id, ChaosVfx.shadowfist_mark.id, "Pressure Points: the Shadowfist's mark")
eq(effects[#effects].x, P.x + 1, "at its offset tile")
-- Fx (an id only): a class effect on the tile itself stands in, a 3x3 one does not
ok(Fx("void_eye", 1) ~= ChaosVfx.shadowfist_mark.id, "Fx: a 3x3 class effect does not stand in for an id")
vocOf[4] = 3
castPid, castSpell = 4, 219
eq(Fx("holy_smite", 1), ChaosVfx.ranger_arrowfall.id, "Hail of Dawn: the arrowfall on every tile")
castPid, castSpell = 4, 218
ok(Fx("holy_smite", 1) ~= ChaosVfx.deadeye_mark.id, "a Ranger has no Final Verdict mark")
-- a cosmetic skin wins over the class effect
ChaosCosmetics = {swapFor = function(pid, spellId, kind, name)
	return (kind == "vfx" and name == "aura_burst_gold") and "aura_burst_violet" or nil
end}
castPid, castSpell = 1, 223
if ChaosVfx.aura_burst_violet then
	ChaosSpell.vfx(P, "aura_burst_gold")
	eq(effects[#effects].id, ChaosVfx.aura_burst_violet.id, "the skin wins")
end
ChaosCosmetics = nil
-- C.send for the snares and vigils
local before = #effects
eq(C.send(P, "vigil_wrath", 3), true, "send: on and known")
eq(effects[#effects].id, ChaosVfx.vigil_wrath.id, "the vigil banner")
C.PAIR22_FX = false
eq(C.send(P, "vigil_wrath", 3), false, "send: off")
eq(effects[#effects].id, 3, "the stock fallback")
eq(#effects, before + 2, "one effect each")
castPid, castSpell = nil, nil

if failures > 0 then
	print(failures .. " failure(s)")
	os.exit(1)
end
print("class_fx_test: ok")
