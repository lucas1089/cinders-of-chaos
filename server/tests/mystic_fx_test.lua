-- Run from the server/ folder: luajit tests/mystic_fx_test.lua (no engine needed; CI runs it with luajit and lua5.3)
-- Mystic line effects (data/lib/chaos_mystic_fx.lua; server/data/spells/README_FX.md "Mystic line effects"): the
-- missile flight time, the ring and cone helpers, the stock spell plans; sending only names the pair has, exactly the
-- name asked; the tile effect of an area only when no large effect covers it; the stock wrappers; every name the
-- Mystic spells send through ChaosMysticFx is in an ids file of the pair. (Every name asked of ChaosFx exists:
-- tests/spell_fx_names_test.lua.)
local failures, checks = 0, 0
local function ok(c, msg)
	checks = checks + 1
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

-- ---------------------------------------------------------------- engine mock (only what the lib touches)
CONST_ME_NONE, CONST_ANI_NONE = 0, 0
local sent, shots, events = {}, {}, {}
function Position(x, y, z)
	if type(x) == "table" then
		return {x = x.x, y = x.y, z = x.z}
	end
	return {x = x, y = y, z = z}
end
function addEvent(fn, ms, ...)
	events[#events + 1] = {fn = fn, ms = ms, args = {...}}
end
local function runEvents()
	local list = events
	events = {}
	table.sort(list, function(a, b) return a.ms < b.ms end)
	for _, e in ipairs(list) do
		e.fn((table.unpack or unpack)(e.args))
	end
end
ChaosVfx = {arcane_hit = {id = 464, dx = 1, dy = 1}, tick_curse = {id = 633, dx = 1, dy = 1},
	px674_arcane = {id = 558, dx = 1, dy = 1}, big_shock_frost_7 = {id = 639, dx = 3, dy = 3}}
ChaosVfxMissile = {arcane_bolt = {id = 126, dx = 1, dy = 1}}
function Vfx(pos, name)
	if not ChaosVfx[name] or not pos then
		return false
	end
	sent[#sent + 1] = {name = name, x = pos.x, y = pos.y}
	return true
end
function VfxShoot(from, to, name)
	if not ChaosVfxMissile[name] then
		return false
	end
	shots[#shots + 1] = {name = name, fx = from.x, tx = to.x}
	return true
end
-- the effect libs are absent here: ensure() must not fail without them
local realDofile = dofile
dofile = nil
realDofile("data/lib/chaos_mystic_fx.lua")
dofile = realDofile
local M = ChaosMysticFx

-- ---------------------------------------------------------------- pure parts
eq(M.flightMs({x = 1, y = 1, z = 7}, {x = 1, y = 1, z = 7}), 0, "same tile: no flight")
eq(M.flightMs({x = 1, y = 1, z = 7}, {x = 5, y = 1, z = 7}), 300, "4 tiles: 150 * sqrt(4)")
eq(M.flightMs({x = 1, y = 1, z = 7}, {x = 2, y = 1, z = 7}), 150, "1 tile")
eq(M.flightMs(nil, {x = 1, y = 1, z = 7}), 0, "nil from")
local r = M.ring({x = 10, y = 10, z = 7}, 3, 4)
eq(#r, 4, "ring of 4")
for i, p in ipairs(r) do
	local d = math.sqrt((p.x - 10) ^ 2 + (p.y - 10) ^ 2)
	ok(d >= 2.2 and d <= 3.8, "ring tile " .. i .. " at radius 3 (" .. d .. ")")
	eq(p.z, 7, "ring floor")
end
eq(M.ring({x = 0, y = 0, z = 7}, 2, 4)[1].x, M.ring({x = 0, y = 0, z = 7}, 2, 4)[1].x, "ring is deterministic")
local o = {x = 10, y = 10, z = 7}
ok(M.inCone(o, 1, {x = 11, y = 10, z = 7}, 6), "east: the tile in front")
ok(M.inCone(o, 1, {x = 15, y = 12, z = 7}, 6), "east: wide far away")
ok(not M.inCone(o, 1, {x = 11, y = 13, z = 7}, 6), "east: too wide near")
ok(not M.inCone(o, 1, {x = 9, y = 10, z = 7}, 6), "east: behind")
ok(not M.inCone(o, 1, {x = 17, y = 10, z = 7}, 6), "east: too far")
ok(M.inCone(o, 0, {x = 10, y = 7, z = 7}, 6), "north")
ok(M.inCone(o, 5, {x = 12, y = 12, z = 7}, 6), "south-east diagonal")
ok(not M.inCone(o, 1, {x = 11, y = 10, z = 8}, 6), "another floor")
local plan = M.stockPlan("bewitching_hex", 300)
eq(#plan, 6, "hex: missile, impact, four ticks")
eq(plan[1][2], "missile", "hex: the bolt first")
eq(plan[2][1], 300, "hex: the impact on arrival")
eq(plan[6][1], 300 + 4 * 2000, "hex: the last tick")
eq(#M.stockPlan("arcane_ripple"), 2, "ripple: mouth and hits")
eq(#M.stockPlan("nope"), 0, "unknown stock spell")

-- ---------------------------------------------------------------- sending
ok(M.known("arcane_hit"), "known")
ok(not M.known("not_in_pair"), "unknown name")
eq(M.send({x = 1, y = 2, z = 7}, "arcane_hit"), true, "send")
eq(sent[#sent].name, "arcane_hit", "exactly the name asked")
eq(M.send({x = 1, y = 2, z = 7}, "not_in_pair"), false, "a name the pair lacks sends nothing")
eq(M.send(nil, "arcane_hit"), false, "no position")
eq(M.sendFirst({x = 1, y = 1, z = 7}, {"nope", "tick_curse"}), "tick_curse", "sendFirst")
local before = #sent
M.later(200, {x = 3, y = 3, z = 7}, "arcane_hit")
eq(#sent, before, "later: not yet")
runEvents()
eq(#sent, before + 1, "later: sent")
eq(M.tileFx(true, 7), 0, "covered: no tile effect")
eq(M.tileFx(false, 7), 7, "not covered: the old tile effect")
eq(M.tileFx(nil, 7), 7, "nil: the old tile effect")
eq(M.shoot({x = 1, y = 1, z = 7}, {x = 4, y = 1, z = 7}, "arcane_bolt"), true, "shoot")
eq(M.shoot({x = 1, y = 1, z = 7}, {x = 4, y = 1, z = 7}, "nope"), false, "shoot unknown")
eq(M.stockEffect("bewitching_hex", 218), 0, "hex: none effect when the arcane hit is in the pair")
eq(M.stockMissile("bewitching_hex", 84), 0, "hex: none missile when the arcane bolt is in the pair")

-- ---------------------------------------------------------------- stock wrappers
local function creature(id, x, dir, monster)
	return {
		getPosition = function() return {x = x, y = 10, z = 7} end,
		getDirection = function() return dir or 1 end,
		getId = function() return id end,
		isMonster = function() return monster end,
		getTarget = function() return nil end,
	}
end
local foe = creature(2, 14, 3, true)
function Creature(id)
	return id == 2 and foe or nil
end
local variant = {getNumber = function() return 2 end}
local calls = 0
local hex = M.wrapStock("bewitching_hex", function() calls = calls + 1 return true end)
sent, shots, events = {}, {}, {}
eq(hex(creature(1, 10), variant), true, "hex: the base result")
eq(calls, 1, "hex: the base cast ran")
-- with the pair 29 switch on (ChaosPack29Fx.PAIR29) the Hex sends its pair 29 missile and curse instead
local p29 = ChaosPack29Fx and ChaosPack29Fx.PAIR29
eq(shots[1] and shots[1].name, p29 and "hex_missile" or "arcane_bolt", "hex: the bolt")
runEvents()
local names = {}
for _, s in ipairs(sent) do names[s.name] = (names[s.name] or 0) + 1 end
eq(names.arcane_hit, 1, "hex: one impact")
eq(names[p29 and "hex_curse" or "tick_curse"], 4, "hex: four tick marks")
sent, shots, events = {}, {}, {}
local failed = M.wrapStock("bewitching_hex", function() return false end)
eq(failed(creature(1, 10), variant), false, "hex: a failed cast")
eq(#shots + #events, 0, "hex: a failed cast sends nothing")
Game = {getSpectators = function() return {foe, creature(3, 9, 1, true)} end}
local ripple = M.wrapStock("arcane_ripple", function() return true end)
sent, events = {}, {}
eq(ripple(creature(1, 10, 1), {}), true, "ripple: the base result")
eq(sent[1] and sent[1].name, "arcane_hit", "ripple: the hit at the mouth")
eq(sent[1] and sent[1].x, 11, "ripple: one tile in front")
runEvents()
eq(#sent, 2, "ripple: one sigil, on the monster in the cone only")
eq(sent[2] and sent[2].name, "px674_arcane", "ripple: the sigil")
local boom = M.wrapStock("arcane_ripple", function() return true end)
Game = {getSpectators = function() error("boom") end}
local realPrint, logged = print, nil
print = function(m) logged = m end
eq(boom(creature(1, 10, 1), {}), true, "ripple: an error in the effects keeps the cast")
print = realPrint
ok(logged and logged:find("arcane_ripple", 1, true) ~= nil, "ripple: the error is logged")
eq(M.wrapStock("nope", print), print, "unknown key: the function itself")

-- ---------------------------------------------------------------- the scripts
-- the spell scripts of the Mystic line (sorcerer/, druid/, illusionist/)
local xml = readFile("data/spells/chaos/spells_chaos.xml") or ""
local scripts = {}
for script in xml:gmatch('script="chaos/([^"]+)"') do
	scripts[#scripts + 1] = script
end
ok(#scripts > 50, "the spell scripts: " .. #scripts)
local function mysticScript(script)
	return script:match("^sorcerer/") or script:match("^druid/") or script:match("^illusionist/")
end

-- every name the Mystic spells send through ChaosMysticFx is in an ids file of the pair (ChaosVfx names)
local ids = ""
for _, f in ipairs({"chaos_vfx.lua", "chaos_vfx_art.lua", "chaos_class_fx_ids.lua", "chaos_big_fx_ids.lua",
	"chaos_pack_fx_ids.lua", "chaos_pack27_fx_ids.lua", "chaos_pack29_fx_ids.lua"}) do
	ids = ids .. (readFile("data/lib/" .. f) or "")
end
local function inPair(name)
	return ids:find("\n%s*" .. name .. " = {id", 1) ~= nil or ids:find("ChaosVfx%." .. name .. " = {id") ~= nil
		or ids:find("ChaosVfxMissile%." .. name .. " = {id") ~= nil
end
local mysticNames = 0
for _, script in ipairs(scripts) do
	if mysticScript(script) then
		local s = readFile("data/spells/chaos/" .. script) or ""
		for _, pat in ipairs({'M%.send%([^,]+, "([%w_]+)"%)', 'M%.later%([^,]+,[^,]+, "([%w_]+)"%)',
			'M%.known%("([%w_]+)"%)', 'ChaosMysticFx%.send%([^,]+, "([%w_]+)"%)', 'M%.shoot%([^,]+,[^,]+, "([%w_]+)"%)',
			'{"([%w_]+)", %d}'}) do
			for name in s:gmatch(pat) do
				mysticNames = mysticNames + 1
				ok(inPair(name), script .. " sends " .. name .. ", which no ids file of the pair has")
			end
		end
	end
end
ok(mysticNames >= 30, "Mystic names checked: " .. mysticNames)
for key, st in pairs(M.STOCK) do
	for _, field in ipairs({"missile", "impact", "tick", "mouth", "hit"}) do
		if st[field] then
			ok(inPair(st[field]), key .. "." .. field .. " " .. st[field] .. " is in the pair")
		end
	end
end
-- the Mystic scripts that send through ChaosMysticFx load it
for _, script in ipairs(scripts) do
	local s = readFile("data/spells/chaos/" .. script) or ""
	if s:find("ChaosMysticFx", 1, true) then
		ok(s:find("data/lib/chaos_mystic_fx.lua", 1, true) ~= nil, script .. " loads chaos_mystic_fx.lua")
	end
end

print(string.format("mystic_fx_test: %d checks, %d failed", checks, failures))
if failures > 0 then
	os.exit(1)
end
