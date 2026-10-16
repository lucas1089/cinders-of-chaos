-- Run from the server/ folder: luajit tests/big_fx_test.lua (no engine needed; CI runs it with luajit and lua5.3)
-- Large spell effects (data/lib/chaos_big_fx.lua): the switch is one plain line, on (since 2026-10-13); the effect list is the client
-- spec's (art_import/big_fx.csv) in order; every spell swap names a spell of spells_chaos.xml whose script sends that
-- effect name, every use is a ChaosPackFx use sent by a call site, every name is one of the set; the round telegraph
-- test (sizes, cones, rings, marks); off, nothing big is sent and the pack / stock effects go out exactly as before;
-- on without the ids file, nothing big either; on with the ids, the big effect at the centre; the call sites are wired.
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

-- engine mocks: effects and Vfx calls are recorded
local effects, vfxSent = {}, {}
local PosMT = {}
PosMT.__index = PosMT
function PosMT:sendMagicEffect(id) effects[#effects + 1] = {id = id, x = self.x, y = self.y} end
Position = function(x, y, z)
	if type(x) == "table" then x, y, z = x.x, x.y, x.z end
	return setmetatable({x = x, y = y, z = z}, PosMT)
end
local function reset() effects, vfxSent = {}, {} end

dofile("data/lib/chaos_big_fx.lua")
local C = ChaosBigFx

-- the switch: one plain line, on since 2026-10-13 (things_custom24 with effects 635-655 is on windows-assets at 407ad9b6)
local src = readFile("data/lib/chaos_big_fx.lua") or ""
eq(src:match("\nC%.BIG_FX = (%a+)\n"), "true", "the switch is one plain line, on")
eq(C.BIG_FX, true, "the shipped switch is on")

-- the set: the client spec's names, sizes and send offsets
local spec, order = {}, {}
for line in (readFile("../client/tools/sprites/art_import/big_fx.csv") or ""):gmatch("[^\n]+") do
	local name, w, h, ph, dx, dy, alpha = line:match("^effect,([%w_]+),[^,]+,(%d+),(%d+),(%d+),%d+,(%d+),(%d+),(%a+),")
	if name then
		spec[name] = {w = tonumber(w), h = tonumber(h), phases = tonumber(ph), dx = tonumber(dx), dy = tonumber(dy),
			alpha = alpha}
		order[#order + 1] = name
	end
end
eq(#order, #C.effects, "C.effects has the spec's effects")
ok(#order >= 16 and #order <= 24, "16 to 24 effects")
for i, name in ipairs(C.effects) do
	eq(order[i], name, "effect " .. i .. " in spec order")
	local s = spec[name] or {}
	ok(s.w == s.h and s.w and s.w % 2 == 1 and s.w >= 5 and s.w <= 9, name .. " is 5x5, 7x7 or 9x9")
	ok(s.phases and s.phases >= 10 and s.phases <= 13, name .. " has 10 to 13 frames")
	eq(s.dx, s.w and (s.w - 1) / 2, name .. " is sent at its centre tile (dx)")
	eq(s.dy, s.h and (s.h - 1) / 2, name .. " is sent at its centre tile (dy)")
	eq(s.alpha, "soft", name .. " keeps its alpha levels")
	eq(tonumber(name:match("_(%d)$")), s.w, name .. " is named by its size")
end
local inSet = {}
for _, n in ipairs(C.effects) do inSet[n] = true end
-- the names must not clash with the pair's effects (vfx_catalog.csv, class effects)
for _, cat in ipairs({"data/spells/vfx_catalog.csv", "data/spells/vfx_art_catalog.csv", "data/spells/class_fx_catalog.csv"}) do
	for line in (readFile(cat) or ""):gmatch("[^\n]+") do
		local name = line:match("^effect,%d+,([%w_]+),")
		ok(not (name and inSet[name]), cat .. " has no " .. tostring(name))
	end
end

-- every effect is used or listed as unwired
local used = {}
for _, swaps in pairs(C.spells) do
	for _, big in pairs(swaps) do used[big] = true end
end
for _, big in pairs(C.uses) do used[big] = true end
for _, big in pairs(C.hits) do used[big] = true end
for _, n in ipairs({5, 7, 9}) do used["big_telegraph_" .. n] = true end
for _, n in ipairs(C.unwired) do
	ok(inSet[n], "unwired " .. n .. " is in the set")
end
for _, n in ipairs(C.effects) do
	local un = false
	for _, u in ipairs(C.unwired) do un = un or u == n end
	ok(used[n] or un, n .. " is used or listed as unwired")
	ok(not (used[n] and un), n .. " is not both used and unwired")
end

-- spells: the id is a spell of spells_chaos.xml and its script sends the swapped name through ChaosSpell.vfx / vfxOr
local xml = readFile("data/spells/chaos/spells_chaos.xml") or ""
local scriptOf = {}
for attrs in xml:gmatch("<instant ([^>]*)>") do
	local id, script = attrs:match('spellid="(%d+)"'), attrs:match('script="chaos/([^"]+)"')
	if id and script then
		scriptOf[tonumber(id)] = script
	end
end
local spells = 0
for id, swaps in pairs(C.spells) do
	spells = spells + 1
	local script = scriptOf[id]
	ok(script ~= nil, "spell " .. id .. " is in spells_chaos.xml")
	local s = script and readFile("data/spells/chaos/" .. script) or ""
	for name, big in pairs(swaps) do
		ok(inSet[big], id .. ": " .. big .. " is in the set")
		local direct = s:find('ChaosSpell.vfx%(.-"' .. name .. '"') or s:find('ChaosSpell.vfxOr%(.-"' .. name .. '"')
		local waves = s:find('"' .. name .. '"%s*}') and s:find("ChaosSpell.vfx%(%a+, w%[4%]%)")
		ok(direct or waves, script .. " sends " .. name)
		eq(C.pick(id, name), big, "pick " .. id .. " " .. name)
	end
end
ok(spells >= 10, "spells listed")
eq(C.pick(206, "nope"), nil, "unknown name")
eq(C.pick(1, "dome_blast_fire"), nil, "unknown spell")
eq(C.pick(nil, "dome_blast_fire"), nil, "nil spell")

-- the strongest area spells of each class line (one or more per line; the Thief line has no centred area effect)
local lineOf = {
	[206] = "mystic", [213] = "mystic", [204] = "mystic", [202] = "mystic", [231] = "mystic", [230] = "mystic",
	[225] = "warrior", [216] = "ranger", [218] = "ranger", [185] = "necromancer", [188] = "necromancer",
	[65] = "monk", [199] = "templar", [190] = "templar", [198] = "templar",
}
local lines = {}
for id in pairs(C.spells) do
	ok(lineOf[id] ~= nil, "spell " .. id .. " has a line here")
	lines[lineOf[id] or "?"] = true
end
for _, l in ipairs({"mystic", "warrior", "ranger", "necromancer", "monk", "templar"}) do
	ok(lines[l], l .. " line has a big effect")
end

-- uses: ChaosPackFx uses
dofile("data/lib/chaos_pack_fx.lua")
local P = ChaosPackFx
for use, big in pairs(C.uses) do
	ok(P.uses[use] ~= nil, use .. " is a ChaosPackFx use (sent by a call site)")
	ok(inSet[big], use .. " -> " .. big .. " is in the set")
	eq(C.pickUse(use), big, "pickUse " .. use)
end
eq(C.pickUse("nope"), nil, "unknown use")
for el, big in pairs(C.hits) do
	ok(inSet[big], "hit " .. el .. " -> " .. big .. " is in the set")
end

-- round telegraphs
local function circle(cx, cy, r)
	local t = {}
	for y = cy - r - 1, cy + r + 1 do
		for x = cx - r - 1, cx + r + 1 do
			local dx, dy = x - cx, y - cy
			if math.sqrt(dx * dx + dy * dy) <= r then t[#t + 1] = {x = x, y = y, z = 7} end
		end
	end
	return t
end
for r, size in pairs({[2] = 5, [3] = 7, [4] = 9}) do
	local c, n = C.circleOf(circle(100, 200, r))
	eq(n, size, "circle radius " .. r)
	ok(c and c.x == 100 and c.y == 200 and c.z == 7, "circle radius " .. r .. " centre")
	ok(c and math.type == nil or (c and math.type(c.x) == "integer"), "centre x is an integer")
end
eq(C.circleOf(circle(100, 200, 1)), nil, "3x3 circle: too small")
eq(C.circleOf(circle(100, 200, 5)), nil, "11x11 circle: too big")
local ring = {}
for _, t in ipairs(circle(100, 200, 3)) do
	local dx, dy = t.x - 100, t.y - 200
	if math.sqrt(dx * dx + dy * dy) >= 1.5 then ring[#ring + 1] = t end
end
eq(C.circleOf(ring), nil, "ring with a safe middle")
local cone = {}
for d = 1, 6 do
	for s = -math.floor(d / 2), math.floor(d / 2) do cone[#cone + 1] = {x = 100 + d, y = 200 + s, z = 7} end
end
eq(C.circleOf(cone), nil, "cone")
local marks = {}
for _, c in ipairs({{100, 200}, {104, 204}}) do
	for _, t in ipairs(circle(c[1], c[2], 1)) do marks[#marks + 1] = t end
end
eq(C.circleOf(marks), nil, "marks round two players")
local square = {}
for y = 0, 6 do for x = 0, 6 do square[#square + 1] = {x = x, y = y, z = 7} end end
eq(select(2, C.circleOf(square)), 7, "a full 7x7 square counts (box filled)")
local twoFloors = circle(100, 200, 2)
twoFloors[1] = {x = twoFloors[1].x, y = twoFloors[1].y, z = 8}
eq(C.circleOf(twoFloors), nil, "tiles on two floors")
eq(C.circleOf({}), nil, "no tiles")
eq(C.circleOf(nil), nil, "nil tiles")

-- switch off: nothing big, Vfx never asked, the pack lib sends exactly the stock effect (the shipped line is on; the
-- off path is tested by turning it off here)
ChaosVfx = {big_telegraph_7 = {id = 630, dx = 3, dy = 3}, big_nova_void_7 = {id = 640, dx = 3, dy = 3},
	big_rift_void_7 = {id = 646, dx = 3, dy = 3}, big_telegraph_5 = {id = 628, dx = 2, dy = 2}}
Vfx = function(pos, name) vfxSent[#vfxSent + 1] = {name = name, x = pos.x, y = pos.y}; return true end
reset()
C.BIG_FX = false
C.loaded = nil
eq(C.live(), false, "off: not live")
eq(C.swapFor(231, "void_rift"), nil, "off: no swap")
eq(C.send({x = 1, y = 2, z = 7}, "big_rift_void_7"), false, "off: send")
eq(C.sendUse({x = 1, y = 2, z = 7}, "wb_arrives"), false, "off: sendUse")
eq(C.telegraph(circle(100, 200, 3)), false, "off: telegraph")
eq(C.bossHit(circle(100, 200, 3), "death"), false, "off: bossHit")
eq(#vfxSent, 0, "off: Vfx not called")
P.PACK_FX = false
P.loaded = nil
eq(P.send(Position(5, 6, 7), "wb_arrives", 17), false, "off: pack send falls back")
eq(#effects, 1, "off: one stock effect")
eq(effects[1] and effects[1].id, 17, "off: the stock effect id")
eq(#vfxSent, 0, "off: still no Vfx")

-- switch on, no ids file loaded yet and the names unknown: nothing big
reset()
local saved = ChaosVfx
ChaosVfx = {}
C.BIG_FX = true
C.loaded = nil
local realDofile = dofile
dofile = function(p)
	if p == "data/lib/chaos_big_fx_ids.lua" or p == "data/lib/chaos_vfx.lua" then
		error("absent")
	end
	return realDofile(p)
end
eq(C.live(), false, "on without ids: not live")
eq(C.sendUse({x = 1, y = 2, z = 7}, "wb_arrives"), false, "on without ids: nothing big")
eq(P.send(Position(5, 6, 7), "wb_arrives", 17), false, "on without ids: pack falls back")
eq(effects[1] and effects[1].id, 17, "on without ids: the stock effect")
dofile = realDofile

-- switch on with the ids
reset()
ChaosVfx = saved
C.loaded = nil
eq(C.live(), true, "on with ids: live")
eq(C.swapFor(231, "void_rift"), "big_rift_void_7", "on: spell swap")
eq(C.swapFor(230, "shadow_smoke"), "big_nova_void_7", "on: spell swap 2 (Nightburst's eruption)")
eq(C.swapFor(230, "void_maw"), nil, "on: Nightburst's gather keeps the pack void_maw")
eq(C.swapFor(206, "dome_blast_fire"), nil, "on: a name not in the pair is not swapped")
eq(C.pick(231, "arcane_circle"), "big_nova_arcane_7", "pick: another name of the spell (each implosion)")
eq(C.swapFor(231, "arcane_circle"), nil, "on: a big effect this pair lacks is not swapped")
eq(C.swapFor(231, "shadow_smoke"), nil, "on: a name the spell has no swap for")
eq(C.sendUse({x = 1, y = 2, z = 7}, "wb_arrives"), true, "on: sendUse")
eq(vfxSent[1] and vfxSent[1].name, "big_rift_void_7", "on: the use's big effect")
eq(C.sendUse({x = 1, y = 2, z = 7}, "wb_adds"), false, "on: a use without a big effect")
reset()
eq(P.send(Position(5, 6, 7), "wb_arrives", 17), true, "on: pack send takes the big effect")
eq(#effects, 0, "on: no stock effect then")
eq(vfxSent[1] and vfxSent[1].name, "big_rift_void_7", "on: through the pack lib")
reset()
eq(C.telegraph(circle(100, 200, 3)), true, "on: telegraph 7x7")
ok(vfxSent[1] and vfxSent[1].name == "big_telegraph_7" and vfxSent[1].x == 100 and vfxSent[1].y == 200,
	"on: the 7x7 circle at the centre")
eq(C.telegraph(circle(100, 200, 4)), false, "on: 9x9 not in this mocked pair")
eq(C.telegraph(cone), false, "on: no circle over a cone")
reset()
eq(C.bossHit(circle(10, 20, 3), "death"), true, "on: boss hit")
eq(vfxSent[1] and vfxSent[1].name, "big_nova_void_7", "on: the death hit")
eq(C.bossHit(circle(10, 20, 3), "fire"), false, "on: fire hit not in this mocked pair")
eq(C.bossHit(ring, "death"), false, "on: no hit over a ring")
C.BIG_FX = false
C.loaded = nil

-- call sites
local common = readFile("data/spells/chaos/_common.lua") or ""
ok(common:find("pcall(dofile, 'data/lib/chaos_big_fx.lua')", 1, true) ~= nil, "_common.lua loads the lib")
local vfxBody = common:match("function ChaosSpell%.vfx%(pos, name%)(.-)\nend") or ""
local bi = vfxBody:find("bigFx(name)", 1, true)
local ci = vfxBody:find("classFx(name)", 1, true)
ok(bi ~= nil and ci ~= nil and bi < ci, "ChaosSpell.vfx asks the big effect before the class effect")
ok(vfxBody:find("not alt and bigFx", 1, true) ~= nil, "a chosen skin wins over the big effect")
local pack = readFile("data/lib/chaos_pack_fx.lua") or ""
ok(pack:find("ChaosBigFx.sendUse", 1, true) ~= nil, "ChaosPackFx.send asks the big effect first")
for _, f in ipairs({"uber.lua", "guildboss.lua", "raid.lua"}) do
	local s = readFile("data/scripts/chaos/" .. f) or ""
	ok(s:find('pcall(dofile, "data/lib/chaos_big_fx.lua")', 1, true) ~= nil, f .. " loads the lib")
	ok(s:find('bigFx("telegraph", tiles)', 1, true) ~= nil, f .. " draws the big warning circle")
end
for _, f in ipairs({"uber.lua", "guildboss.lua"}) do
	local s = readFile("data/scripts/chaos/" .. f) or ""
	ok(s:find('bigFx("bossHit", tiles,', 1, true) ~= nil, f .. " draws the big hit")
end

if failures > 0 then
	print(failures .. " failure(s)")
	os.exit(1)
end
print("big_fx_test: all passed")
