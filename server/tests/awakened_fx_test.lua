-- Run from the server/ folder: luajit tests/awakened_fx_test.lua (and lua5.3; CI runs both)
-- The awakened spell look kit (O711, client pair 76, data/lib/chaos_awakened_fx.lua and the generated
-- chaos_awakened_fx_ids.lua): the gate is config.lua chaosClientPair >= 76; below it every answer is nil (the caller keeps
-- today's effects); with it every element and shape maps to its effect id 5354.. in table order and every element to its
-- projectile; every effect is tagged with its element. The headings (a line and a wave north, south and west, effects 5394-5441)
-- answer from chaosClientPair >= 77 only. The wiring into the awakened casts: tests/awakened_look_test.lua.
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

local C = dofile("data/lib/chaos_awakened_fx.lua")
eq(C.PAIR, 76, "the kit joins pair 76")
eq(C.PAIR_HEADINGS, 77, "the headings join pair 77")
eq(ChaosAwakenedFx, C, "the lib registers itself")

-- the gate reads config.lua
eq(C.parsePair("chaosClientPair = 76"), 76, "parse a plain line")
eq(C.parsePair("x = 1\n  chaosClientPair = 75 -- note\n"), 75, "parse a line with a note")
eq(C.parsePair("chaosClientPair = abc"), nil, "no number")
eq(C.parsePair(nil), nil, "no text")
eq(C.recordedPair("/nonexistent/config.lua"), nil, "no file")
eq(C.headings, false, "the checked in config.lua is below pair 77 (PAIR_ASSETS stays 76 until the owner pushes pair 77)")

-- gate off (below 76): nothing answers
for _, p in ipairs({0, 73, 75}) do
	C.on = (p >= C.PAIR)
	C.headings = (p >= C.PAIR_HEADINGS)
	eq(C.effect("fire", "single"), nil, "pair " .. p .. ": no effect")
	eq(C.effect("fire", "line", "north"), nil, "pair " .. p .. ": no heading effect")
	eq(C.missile("fire"), nil, "pair " .. p .. ": no missile")
end

-- gate on
C.on = (76 >= C.PAIR)
C.headings = false
dofile("data/lib/chaos_awakened_fx_ids.lua")
local I = ChaosAwakenedFxIds
eq(I.pair, 76, "the ids file is pair 76")
eq(I.first, 5354, "the effects start after the footprints (5353)")
eq(I.count, 40, "40 effects")
eq(#C.ELEMENTS, 8, "8 elements")
eq(#C.SHAPES, 5, "5 shapes")
local seen, id = {}, I.first - 1
for _, el in ipairs(C.ELEMENTS) do
	for _, sh in ipairs(C.SHAPES) do
		id = id + 1
		local e = C.effect(el, sh)
		ok(e ~= nil, el .. " " .. sh .. " is mapped")
		eq(e.id, id, el .. " " .. sh .. " id in table order")
		ok(not seen[e.id], "no id twice")
		seen[e.id] = true
		ok(e.dx >= 0 and e.dy >= 0 and e.ms > 0, el .. " " .. sh .. " has an offset and a play time")
		eq(I.effects["af_" .. el .. "_" .. sh].element, el, "the element of the row")
		eq(I.effects["af_" .. el .. "_" .. sh].shape, sh, "the shape of the row")
	end
end
eq(id, 5393, "the block ends at 5393")
local mseen = {}
for _, el in ipairs(C.ELEMENTS) do
	local m = C.missile(el)
	ok(m ~= nil, el .. " has a projectile")
	ok(m.id >= 1 and m.id <= 253, "a missile id is one byte and below the weapon-type constant (254)")
	ok(not mseen[m.id], "no missile id twice")
	mseen[m.id] = true
end
eq(C.missile("fire").id, 43, "fire takes the first blank stock id")
eq(C.effect("fire", "triangle"), nil, "an unknown shape")
eq(C.effect("water", "single"), nil, "an unknown element")
eq(C.missile("water"), nil, "an unknown element has no projectile")

-- the ids file is the whole kit: 40 effects, 8 missiles, nothing else
local ne, nm = 0, 0
for _ in pairs(I.effects) do
	ne = ne + 1
end
for _ in pairs(I.missiles) do
	nm = nm + 1
end
eq(ne, 88, "88 effects in the ids file (the kit and its headings)")
eq(nm, 8, "8 missiles in the ids file")

-- pair 76: the kit answers, the headings do not; east, nil and "" are the kit effect
eq(I.headingPair, 77, "the ids file names the heading pair")
eq(I.headingFirst, 5394, "the headings start after the kit")
eq(I.headingCount, 48, "48 heading effects")
eq(C.effect("fire", "line", "north"), nil, "pair 76: a heading is nil")
eq(C.effect("fire", "wave", "west"), nil, "pair 76: a heading is nil")
eq(C.effect("fire", "line", "east").id, C.effect("fire", "line").id, "east is the kit effect")
eq(C.effect("fire", "line", "").id, C.effect("fire", "line").id, "an empty heading is the kit effect")

-- pair 77: every element, line and wave, heading north / south / west, in table order from 5394
C.headings = true
eq(C.effect("fire", "line").id, 5357, "the kit is unchanged at pair 77")
eq(C.effect("fire", "line", "east").id, 5357, "east is the kit effect at pair 77")
local hid = I.headingFirst - 1
local hseen = {}
for _, el in ipairs(C.ELEMENTS) do
	for _, sh in ipairs({"line", "wave"}) do
		for _, hd in ipairs({"north", "south", "west"}) do
			hid = hid + 1
			local e = C.effect(el, sh, hd)
			ok(e ~= nil, el .. " " .. sh .. " " .. hd .. " is mapped")
			eq(e.id, hid, el .. " " .. sh .. " " .. hd .. " id in table order")
			ok(not seen[e.id] and not hseen[e.id], "no id twice")
			hseen[e.id] = true
			ok(e.dx >= 0 and e.dy >= 0 and e.ms > 0, "an offset and a play time")
			local row = I.effects["af_" .. el .. "_" .. sh .. "_" .. hd]
			eq(row.heading, hd, "the heading of the row")
			eq(row.element, el, "the element of the row")
			eq(row.shape, sh, "the shape of the row")
		end
	end
end
eq(hid, 5441, "the headings end at 5441")
eq(C.effect("fire", "line", "north").dx, 1, "line north: the caster's tile is the bottom middle")
eq(C.effect("fire", "line", "south").dy, 7, "line south: the caster's tile is at the top")
eq(C.effect("fire", "line", "west").dx, 0, "line west: the caster's tile is the right end")
eq(C.effect("fire", "single", "north"), nil, "a single has no heading effect")
eq(C.effect("fire", "line", "up"), nil, "an unknown heading")
eq(C.effect("fire", "line", "northeast"), nil, "a diagonal has no heading effect")
for _, hd in ipairs(C.HEADINGS) do
	local ok2 = hd == "east" or C.effect("fire", "wave", hd) ~= nil
	ok(ok2, "the heading " .. hd .. " is one of the four")
end
C.headings = false

-- the tags: every effect id has its element in spell_fx_elements.csv
local tags = {}
for line in slurp("data/spells/spell_fx_elements.csv"):gmatch("[^\r\n]+") do
	local a, b, c = line:match("^(%d+),([^,]+),([^,]+)$")
	if a then
		tags[tonumber(a)] = {name = b, element = c}
	end
end
for name, e in pairs(I.effects) do
	ok(tags[e.id] ~= nil, name .. " is tagged")
	eq(tags[e.id].name, name, "the tag names the effect")
	eq(tags[e.id].element, e.element, name .. " is tagged with its element")
end

print("awakened_fx_test: " .. n .. " checks OK")
