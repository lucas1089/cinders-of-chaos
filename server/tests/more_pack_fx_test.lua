-- Run from the server/ folder: luajit tests/more_pack_fx_test.lua (and lua5.3; CI runs both)
-- The effects of the purchased 32 px effect sets that no pair held before (O735, client pair 82,
-- data/lib/chaos_wst_more_fx.lua and the generated chaos_wst_more_fx_ids.lua): below pair 82 nothing is sent; with the gate
-- the id goes out at its send offset; the ids are the block 5442.. dense; every heading set has 8 names.
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

local sent = {}
local PosMeta = {}
PosMeta.__index = PosMeta
function PosMeta:sendMagicEffect(id, who)
	sent[#sent + 1] = {x = self.x, y = self.y, z = self.z, id = id, who = who}
end
function Position(x, y, z)
	return setmetatable({x = x, y = y, z = z}, PosMeta)
end

local C = dofile("data/lib/chaos_wst_more_fx.lua")
eq(C.PAIR, 82, "the gate is pair 82")
eq(C.parsePair("chaosClientPair = 82 -- x"), 82, "the pair is read")
eq(C.parsePair("a = 1\nchaosClientPair = 81\n"), 81, "on a later line")
eq(C.parsePair("nothing"), nil, "no key")

dofile("data/lib/chaos_wst_more_fx_ids.lua")
local I = ChaosWstMoreFxIds
eq(I.pair, 82, "the ids file names pair 82")
eq(I.first, 5442, "the block starts after effect 5441 of pair 81")
local ids, count, any = {}, 0, nil
for name, e in pairs(I.effects) do
	count = count + 1
	ids[e.id] = name
	ok(e.dx >= 0 and e.dy >= 0 and e.ms > 0, name .. ": offset and play time")
	ok(e.el == "any" or e.el == "physical" or e.el == "fire" or e.el == "ice" or e.el == "energy" or e.el == "earth"
		or e.el == "holy" or e.el == "death" or e.el == "arcane", name .. ": element tag")
	any = any or name
end
eq(count, I.count, "count")
for id = I.first, I.first + I.count - 1 do
	ok(ids[id], "id " .. id .. " is used")
end
for name in pairs(I.effects) do
	local base = name:match("^(.+)_n$")
	if base then
		for _, d in ipairs(C.DIRS) do
			ok(I.effects[base .. "_" .. d], base .. ": heading " .. d)
		end
	end
end

-- gate off: nothing
C.ON = false
eq(C.at(Position(100, 100, 7), any), false, "below pair 82 nothing is sent")
eq(#sent, 0, "no effect went out")
eq(C.entry(any), nil, "no entry with the gate off")
-- gate on
C.ON = true
local e = C.entry(any)
ok(e, "an entry with the gate on")
eq(C.at(Position(100, 100, 7), any), true, "sent")
eq(sent[1].id, e.id, "its id")
eq(sent[1].x, 100 + e.dx, "x at the send offset")
eq(sent[1].y, 100 + e.dy, "y at the send offset")
eq(C.to("p", {x = 1, y = 2, z = 3}, any), true, "to one player")
eq(sent[2].who, "p", "only that player")
eq(C.at(Position(1, 1, 7), "no_such_effect"), false, "an unknown name sends nothing")
eq(C.at(nil, any), false, "no position, nothing")
local cone
for name in pairs(I.effects) do
	cone = cone or name:match("^(.+)_ne$")
end
if cone then
	eq(C.heading(cone, 2), cone .. "_e", "direction 2 is east")
	eq(C.heading(cone, 9), nil, "no direction 9")
end

print("more_pack_fx_test: " .. n .. " checks OK")
