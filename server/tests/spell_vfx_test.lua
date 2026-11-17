-- Run from the server/ folder: luajit tests/spell_vfx_test.lua (and lua5.3; CI runs both)
-- The spell effects of the purchased effect packs (O596, client pair 73, data/lib/chaos_spell_vfx.lua and the generated
-- chaos_spell_vfx_ids.lua): the gate is config.lua chaosClientPair >= 73 and nothing answers below it, every piece a spell
-- is given exists with the right kind, the ids are the block 4743.. in order, a projectile id fits one byte, every effect
-- has its element tag, and a spell with an element is only given a piece of that element (or a reason in C.allow).
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

local C = dofile("data/lib/chaos_spell_vfx.lua")
eq(C, ChaosSpellVfx, "the global")
eq(C.PAIR, 73, "pair 73")
eq(C.ON, false, "no config.lua next to the tests: the gate is off")

-- ---------------------------------------------------------------- the pair record
eq(C.parsePair("chaosClientPair = 73"), 73, "plain")
eq(C.parsePair("x = 1\nchaosClientPair=72 -- shipped\ny = 2\n"), 72, "comment, no spaces, other lines")
eq(C.parsePair("chaosClientPair = \"abc\"\n"), nil, "not a number")
eq(C.parsePair(nil), nil, "no text")
eq(C.recordedPair("tests/no_such_config.lua"), nil, "no file")

-- ---------------------------------------------------------------- gate off: nothing answers, nothing is merged
ChaosVfx = {fire_nova = {id = 372, dx = 0, dy = 0, ms = 500}}
ChaosVfxMissile = {fireball = {id = 4, dx = 0, dy = 0}}
eq(C.pick(201, "missile", "fireball"), "sv_fire_bolt", "pick is pure")
eq(C.swapFor(201, "missile", "fireball"), nil, "gate off: no projectile")
eq(C.swapFor(106, "fx", "necro_skull"), nil, "gate off: no effect")
eq(ChaosVfx.sv_death_wail, nil, "gate off: no name merged")
eq(ChaosSpellVfxIds, nil, "gate off: the ids are not even loaded")

-- ---------------------------------------------------------------- gate on
C.ON = true
C.loaded = nil
eq(C.swapFor(201, "missile", "fireball"), "sv_fire_bolt", "Witchfire Bolt: the bolt")
eq(C.swapFor(201, "send", "fire_explosion"), "sv_fire_bolt_hit", "Witchfire Bolt: a projectile ends in its paired burst")
eq(C.swapFor(106, "missile", "skull_orb"), "sv_death_skull", "Marrow Bolt: the skull")
eq(C.swapFor(106, "fx", "necro_skull"), "sv_death_wail", "Marrow Bolt: the wail")
eq(C.swapFor(57, "missile", "venom_glob"), "sv_venom_glob", "Venom Spiral")
eq(C.swapFor(218, "missile", "holy_spear"), "sv_holy_lance", "Final Verdict")
eq(C.swapFor(201, "fx", "necro_skull"), nil, "a name the spell is not given")
eq(C.swapFor(9999, "fx", "fire_nova"), nil, "a spell with no entry")
eq(C.swapFor(nil, "fx", "fire_nova"), nil, "no spell")
eq(C.swapFor(201, "fx", 372), nil, "not a name")
local I = ChaosSpellVfxIds
ok(I, "the ids are loaded")
eq(I.pair, C.PAIR, "the ids are of the same pair")
eq(ChaosVfx.sv_death_wail.id, I.effects.sv_death_wail.id, "merged into ChaosVfx")
eq(ChaosVfxMissile.sv_fire_bolt.id, 43, "merged into ChaosVfxMissile")
eq(ChaosVfx.fire_nova.id, 372, "other names untouched")

-- ---------------------------------------------------------------- the id block
local ids, count = {}, 0
for name, e in pairs(I.effects) do
	count = count + 1
	ok(name:match("^sv_"), name .. ": a neutral name")
	ok(not ids[e.id], name .. ": id used twice")
	ids[e.id] = name
	ok(e.dx >= 0 and e.dy >= 0 and e.ms > 0, name .. ": offset and length")
end
eq(count, I.count, "the recorded count")
eq(I.first, 4743, "the block starts after pair 72's 4,742 effects")
for id = I.first, I.first + I.count - 1 do
	ok(ids[id], "effect " .. id .. " missing: the block has no hole")
end
ok(I.first + I.count - 1 <= 5142, "the block ends at 5142 at most")
local mseen = {}
for name, e in pairs(I.missiles) do
	ok(e.id >= 1 and e.id <= 253, name .. ": a projectile id is one byte, 254 and 255 are the engine's")
	ok(not mseen[e.id], name .. ": projectile id used twice")
	mseen[e.id] = true
	eq(e.dx, 1, name .. " dx")
	eq(e.dy, 1, name .. " dy")
end
for id in pairs(I.rebuilt) do
	ok(id >= 1 and id <= 253 and not mseen[id], "rebuilt projectile " .. id)
end

-- ---------------------------------------------------------------- tags, and the element rule
local tags = {}
for line in slurp("data/spells/spell_fx_elements.csv"):gmatch("[^\n]+") do
	local id, name, el = line:match("^(%d+),([^,]+),(%w+)")
	if id then
		tags[name] = {id = tonumber(id), element = el}
	end
end
for name, e in pairs(I.effects) do
	ok(tags[name], name .. ": no row in spell_fx_elements.csv")
	eq(tags[name].id, e.id, name .. ": tag id")
	eq(tags[name].element, e.element, name .. ": tag element")
end
local element = {}
for id, el in slurp("../client/overlay/modules/game_chaosspells/spelldata.lua"):gmatch('{ id = (%d+), name = "[^"]+"[^\n]-element = "(%w+)"') do
	element[tonumber(id)] = el
end
ok(element[201] == "fire", "the client spell list is read")
local used, spells = {}, 0
for spellId, kinds in pairs(C.spells) do
	spells = spells + 1
	for kind, map in pairs(kinds) do
		ok(kind == "fx" or kind == "send" or kind == "missile", "kind " .. tostring(kind))
		for asked, piece in pairs(map) do
			local e = kind == "missile" and I.missiles[piece] or (kind ~= "missile" and I.effects[piece])
			ok(e, spellId .. ": " .. piece .. " is not a piece of that kind")
			used[piece] = true
			eq(C.swapFor(spellId, kind, asked), piece, spellId .. " " .. asked)
			local want = element[spellId]
			if want and e.element ~= want then
				ok(C.allow[spellId] and C.allow[spellId][piece], "spell " .. spellId .. " (" .. want .. ") sends " .. piece .. " (" .. e.element ..
					") without a reason in C.allow")
			end
		end
	end
end
ok(spells >= 40, "the spells mapped")
for spellId, map in pairs(C.allow) do
	for piece, why in pairs(map) do
		local e = I.effects[piece]
		ok(e and element[spellId] and e.element ~= element[spellId] and #why > 10, "allow " .. spellId .. " " .. piece .. " is not needed or has no reason")
	end
end
for name in pairs(I.effects) do
	ok(used[name], name .. ": imported but no spell sends it")
end
for name in pairs(I.missiles) do
	ok(used[name], name .. ": imported but no spell sends it")
end

print("spell_vfx_test: " .. n .. " checks passed")
