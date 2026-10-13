-- Run from the server/ folder: luajit tests/pack_fx_test.lua (no engine needed; CI runs it with luajit and lua5.3)
-- Pack effects for procs, snares, rift modifiers, world bosses and the reflect (data/lib/chaos_pack_fx.lua): the
-- switch is one plain line, off; every use names an effect of the pair (vfx_catalog.csv) or a cut of the next pair
-- (client art_import/pack_fx.csv); every use is sent by a call site and every call site's use exists; off, a call
-- sends exactly the stock effect; on, the pack effect at its offset tile, the stock one for a name not known yet.
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
local effects, vfxSent = {}, {}
local PosMT = {}
PosMT.__index = PosMT
function PosMT:sendMagicEffect(id) effects[#effects + 1] = {id = id, x = self.x, y = self.y} end
Position = function(x, y, z)
	if type(x) == "table" then x, y, z = x.x, x.y, x.z end
	return setmetatable({x = x, y = y, z = z}, PosMT)
end
local function reset() effects, vfxSent = {}, {} end

dofile("data/lib/chaos_pack_fx.lua")
local C = ChaosPackFx

-- the switch: one plain line, off until the owner turns it on
local src = readFile("data/lib/chaos_pack_fx.lua") or ""
eq(src:match("\nC%.PACK_FX = (%a+)\n"), "false", "the switch is one plain line, off")

-- names: the pair's pack effects and the cuts of the next pair
local inPair = {}
for line in (readFile("data/spells/vfx_catalog.csv") or ""):gmatch("[^\n]+") do
	local kind, id, name = line:match("^(%a+),(%d+),([%w_]+),")
	if kind == "effect" then
		inPair[name] = tonumber(id)
	end
end
ok(inPair.void_maw ~= nil and inPair.fire_explosion ~= nil, "vfx_catalog.csv read")
local cutSpec, cutOrder = {}, {}
for line in (readFile("../client/tools/sprites/art_import/pack_fx.csv") or ""):gmatch("[^\n]+") do
	local name, w, h, dx, dy = line:match("^effect,([%w_]+),[^,]+,(%d+),(%d+),%d+,%d+,(%d+),(%d+),")
	if name then
		cutSpec[name] = {w = tonumber(w), h = tonumber(h), dx = tonumber(dx), dy = tonumber(dy)}
		cutOrder[#cutOrder + 1] = name
	end
end
eq(#cutOrder, #C.cuts, "C.cuts has the spec's effects")
for i, name in ipairs(C.cuts) do
	eq(cutOrder[i], name, "cut " .. i .. " in spec order")
	ok(inPair[name] == nil, name .. " is a new name, not one of the pair's")
end
local uses = 0
for use, name in pairs(C.uses) do
	uses = uses + 1
	ok(inPair[name] ~= nil or cutSpec[name] ~= nil, use .. " -> " .. name .. " is in the pair or the cut spec")
	eq(C.pick(use), name, "pick " .. use)
end
ok(uses >= 25, "uses listed")
eq(C.pick("nope"), nil, "unknown use")
eq(C.pick(nil), nil, "nil use")

-- call sites: every literal use exists, the built ones (snare_<element>, rift_strike_<element>) too, every use is sent
local sites = {
	"data/scripts/chaos/combat_fx.lua", "data/scripts/chaos/item_mods.lua", "data/scripts/chaos/rift.lua",
	"data/scripts/chaos/worldboss.lua", "data/spells/chaos/_snares.lua",
}
local sent = {}
for _, path in ipairs(sites) do
	local s = readFile(path)
	ok(s ~= nil, path .. " read")
	s = s or ""
	ok(s:find('pcall(dofile, "data/lib/chaos_pack_fx.lua")', 1, true) ~= nil, path .. " loads the lib")
	for use in s:gmatch('packFx%([^\n]-, "([%w_]+)",') do
		ok(C.uses[use] ~= nil, path .. " sends a known use " .. use)
		sent[use] = true
	end
	for use in s:gmatch('use = "([%w_]+)"') do
		ok(C.uses[use] ~= nil, path .. " names a known use " .. use)
		sent[use] = true
	end
	for use in s:gmatch('packUses = {%a+ = "([%w_]+)"}') do
		ok(C.uses[use] ~= nil, path .. " names a known use " .. use)
		sent[use] = true
	end
end
local snares = readFile("data/spells/chaos/_snares.lua") or ""
ok(snares:find('packFx(center, "snare_" .. tostring(snare.element)', 1, true) ~= nil, "snare burst by element")
for el in (snares:match("local AREA_FX = (%b{})") or ""):gmatch("(%a+) = ") do
	if el ~= "physical" then
		ok(C.uses["snare_" .. el] ~= nil, "snare element " .. el .. " has a use")
	end
	sent["snare_" .. el] = true
end
eq(C.uses.snare_physical, nil, "physical snares keep the stock burst")
local rift = readFile("data/scripts/chaos/rift.lua") or ""
ok(rift:find('"rift_strike_" .. tostring(element), effectOf(element))', 1, true) ~= nil, "rift strike by element")
for el in (rift:match("local function effectOf%(element%)\n\treturn %((%b{})") or ""):gmatch("(%a+) = ") do
	ok(C.uses["rift_strike_" .. el] ~= nil, "rift element " .. el .. " has a use")
	sent["rift_strike_" .. el] = true
end
for use in pairs(C.uses) do
	ok(sent[use], use .. " is sent by a call site")
end

-- switch off: the stock effect, exactly, and Vfx is never asked
ChaosVfx = {void_maw = {id = 449, dx = 1, dy = 2}}
Vfx = function(pos, name) vfxSent[#vfxSent + 1] = {name = name, x = pos.x, y = pos.y}; return true end
reset()
eq(C.send(Position(100, 100, 7), "wb_arrives", 18), false, "off: not sent as pack")
eq(#vfxSent, 0, "off: no Vfx")
eq(#effects, 1, "off: one stock effect")
eq(effects[1] and effects[1].id, 18, "off: the stock id")
eq(effects[1] and effects[1].x, 100, "off: on the same tile")
reset()
C.send(Position(1, 1, 7), "item_bleed", nil)
eq(#effects + #vfxSent, 0, "off, no stock effect: nothing, as before")
reset()
C.send({x = 5, y = 6, z = 7}, "reflect", 3)
eq(effects[1] and effects[1].x, 5, "off: a plain table position still gets its stock effect")

-- switch on: pack names the server knows go through Vfx, the others fall back. The cuts' ids file
-- (data/lib/chaos_pack_fx_ids.lua) is kept out here, as on a server whose pair lacks the cuts; it is read below.
local idsPath = "data/lib/chaos_pack_fx_ids.lua"
local plainDofile = dofile
dofile = function(p, ...)
	if p == idsPath then error("no ids file in this pair") end
	return plainDofile(p, ...)
end
C.PACK_FX = true
C.loaded = nil
reset()
eq(C.send(Position(100, 100, 7), "wb_arrives", 18), true, "on: sent as pack")
eq(#effects, 0, "on: no stock effect")
eq(vfxSent[1] and vfxSent[1].name, "void_maw", "on: the use's effect")
reset()
eq(C.send(Position(100, 100, 7), "reflect", 3), false, "on, cut not in this pair: fallback")
eq(effects[1] and effects[1].id, 3, "on, cut not in this pair: the stock id")
dofile = plainDofile
reset()
ChaosVfx.reflect_bubble = {id = 700, dx = 1, dy = 1}
eq(C.send(Position(100, 100, 7), "reflect", 3), true, "on, cut in the ids: sent")
eq(vfxSent[1] and vfxSent[1].name, "reflect_bubble", "on: the cut")
reset()
eq(C.send(Position(1, 1, 7), "nope", 9), false, "on, unknown use: fallback")
eq(effects[1] and effects[1].id, 9, "on, unknown use: the stock id")
reset()
Vfx = function() return false end
eq(C.send(Position(1, 1, 7), "wb_arrives", 18), false, "on, Vfx refuses: fallback")
eq(effects[1] and effects[1].id, 18, "on, Vfx refuses: the stock id")

-- the ids file of the pair that has the cuts (written by import_fx_art.py): when present, every cut in spec
-- order from one first id, with the spec's offsets, the same ids as data/spells/pack_fx_catalog.csv
if readFile(idsPath) then
	local saved = ChaosVfx
	ChaosVfx = {}
	plainDofile(idsPath)
	local first = ChaosVfx[cutOrder[1]] and ChaosVfx[cutOrder[1]].id
	ok(first ~= nil, "ids file: the first cut has an id")
	local cat = {}
	for line in (readFile("data/spells/pack_fx_catalog.csv") or ""):gmatch("[^\n]+") do
		local id, name = line:match("^effect,(%d+),([%w_]+),")
		if id then cat[name] = tonumber(id) end
	end
	for i, name in ipairs(cutOrder) do
		local e = ChaosVfx[name]
		ok(e ~= nil, "ids file: " .. name)
		if e and first then
			eq(e.id, first + i - 1, "ids file: " .. name .. " id in spec order")
			eq(e.dx, cutSpec[name].dx, "ids file: " .. name .. " dx")
			eq(e.dy, cutSpec[name].dy, "ids file: " .. name .. " dy")
			eq(cat[name], e.id, "ids file: " .. name .. " id as in pack_fx_catalog.csv")
		end
	end
	ChaosVfx = saved
end

-- on without chaos_vfx.lua (Vfx missing): not live, stock effects
C.loaded = nil
ChaosVfx, Vfx = nil, nil
local realDofile = dofile
dofile = function() error("no file") end
reset()
eq(C.live(), false, "on, no chaos_vfx.lua: not live")
C.send(Position(1, 1, 7), "wb_enrage", 7)
eq(effects[1] and effects[1].id, 7, "on, no chaos_vfx.lua: the stock id")
dofile = realDofile
C.PACK_FX = false

-- the cuts: send offset inside the thing, at most 4x4 tiles
for name, sp in pairs(cutSpec) do
	ok(sp.w >= 1 and sp.w <= 4 and sp.h >= 1 and sp.h <= 4, name .. " size")
	ok(sp.dx >= 0 and sp.dx < sp.w and sp.dy >= 0 and sp.dy < sp.h, name .. " offset")
end

if failures > 0 then
	print(failures .. " failure(s)")
	os.exit(1)
end
print("pack_fx_test: OK")
