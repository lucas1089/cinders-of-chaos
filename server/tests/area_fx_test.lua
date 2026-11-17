-- Run from the server/ folder: luajit tests/area_fx_test.lua (and lua5.3; CI runs both)
-- Area bursts, beams and markers of the purchased effect packs (O607, client pair 73, data/lib/chaos_area_fx.lua and the
-- generated chaos_area_fx_ids.lua): the gate is config.lua chaosClientPair >= 73 and below it every sender sends exactly what
-- it sends today; a pack burst has the element of the burst it stands in for and is sent on the same centre tile; a refill
-- keeps the id and send offset of chaos_pack36_fx_ids.lua; the new ids are the block 5300..; a beam is the heading from the
-- caster to the target; a marker goes to one player; every id has its element tag.
-- O609: every beam spell draws ONE effect per heading, as long as its damage line (one start, one tip): the generated
-- lengths table, the ids 5303.., the canvas, the view of the caster; the chain of copies only for a length the pair
-- lacks and for a viewer who cannot draw the one piece.
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

-- a fake engine: Position(...):sendMagicEffect records what was sent
local sent = {}
function Position(x, y, z)
	return {x = x, y = y, z = z, sendMagicEffect = function(self, id, who)
		sent[#sent + 1] = {x = self.x, y = self.y, z = self.z, id = id, who = who}
	end}
end
local function last()
	return sent[#sent]
end

dofile("data/lib/chaos_vfx.lua")
dofile("data/lib/chaos_big_fx_ids.lua")
dofile("data/lib/chaos_pack36_fx_ids.lua")
dofile("data/lib/chaos_donor_fx_ids.lua")
local pack36 = {}
for name, e in pairs(ChaosVfx) do
	pack36[name] = {id = e.id, dx = e.dx, dy = e.dy}
end

local C = dofile("data/lib/chaos_area_fx.lua")
eq(C, ChaosAreaFx, "the global")
eq(C.PAIR, 73, "pair 73")
eq(C.ON, false, "no config.lua next to the tests: the gate is off")
eq(C.parsePair("x = 1\nchaosClientPair=72 -- shipped\n"), 72, "the pair record")
eq(C.parsePair("chaosClientPair = 73"), 73, "plain")
eq(C.recordedPair("tests/no_such_config.lua"), nil, "no file")

local HERE = {x = 100, y = 200, z = 7}
local OLD = {big_shock_fire_7 = 638, big_shock_blood_9 = 642, donor_arcane_nova_695 = 4711, big_nova_frost_7 = 644,
	big_nova_holy_7 = 646}

-- ---------------------------------------------------------------- gate off: exactly what is sent today
for name, id in pairs(OLD) do
	eq(C.swap(name), name, name .. ": gate off, the name as asked")
	ok(Vfx(HERE, name), name .. " is sent")
	eq(last().id, id, name .. ": gate off, our id")
	eq(last().x, HERE.x + pack36[name].dx, name .. ": gate off, our offset")
end
eq(C.beam(118, 1, 6), nil, "gate off: no beam")
eq(C.sendBeam(HERE, 118, 1, 6), false, "gate off: no beam is drawn")
eq(C.mark("locked"), nil, "gate off: no marker")
local count = #sent
eq(C.sendMark(HERE, "locked", "player"), false, "gate off: no marker is sent")
eq(#sent, count, "gate off: nothing more was sent")
local e638 = {id = 638, dx = 3, dy = 3, ms = 700}
eq(C.swapId(e638), e638, "gate off: the boss death effect as it is")
eq(ChaosAreaFxIds, nil, "gate off: the ids are not even loaded")
eq(ChaosVfx.ab_fire_rain, nil, "gate off: no name merged")

-- ---------------------------------------------------------------- gate on
C.ON = true
C.loaded = nil
ok(C.live(), "live")
local I = ChaosAreaFxIds
ok(I, "the ids are loaded")
eq(I.pair, C.PAIR, "the ids are of the same pair")
eq(I.first, 5300, "the new block starts at 5300 (5190.. is another step's, 4743..5299 padded blank)")

-- the ids: new ones a dense block, a refill the id and offset of pair 36
local ids, new, total = {}, 0, 0
for name, e in pairs(I.effects) do
	total = total + 1
	ok(not ids[e.id], name .. ": id used twice")
	ids[e.id] = name
	ok(e.dx >= 0 and e.dy >= 0 and e.dx < e.w and e.dy < e.h and e.ms > 0, name .. ": offset inside the canvas")
	if e.refill then
		ok(e.id < 4743, name .. ": a refill is an id of pair 36")
		ok(pack36[name], name .. ": a refill keeps its pair 36 name")
		eq(pack36[name].id, e.id, name .. ": the pair 36 id")
		eq(pack36[name].dx, e.dx, name .. ": the pair 36 dx")
		eq(pack36[name].dy, e.dy, name .. ": the pair 36 dy")
	else
		new = new + 1
		ok(name:match("^ab_") or (e.len and name:match("^mega_[a-z_]+_l%d+_[nesw]+$")), name .. ": a neutral name")
		ok(not pack36[name], name .. ": a new name")
		ok(e.id >= I.first and e.id < I.first + I.count, name .. ": inside the new block")
		eq(e.len ~= nil, e.id >= I.first + 3, name .. ": the long beams follow the three bursts")
		eq(ChaosVfx[name].id, e.id, name .. ": merged into ChaosVfx")
	end
end
eq(new, I.count, "the recorded count")
eq(total, 70, "70 effects: 39 refilled, 3 new bursts, 28 long beams")
eq(I.count, 31, "the new block is 5300..5330")
eq(I.natural, 3, "the pack's own beam covers 3 tiles on a straight heading")
for id = I.first, I.first + I.count - 1 do
	ok(ids[id], "effect " .. id .. " missing: the block has no hole")
end

-- tags
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

-- A. the bursts: the pack burst of the same element, on the same centre tile
local swaps = 0
for name, alt in pairs(C.names) do
	swaps = swaps + 1
	ok(OLD[name], name .. ": one of the five bursts")
	local e = I.effects[alt]
	ok(e and e.role == "area", alt .. " is an area burst")
	eq(tags[name].element, e.element, name .. " -> " .. alt .. ": the same element")
	eq(C.swap(name), alt, name .. " swapped")
	ok(Vfx(HERE, name), name .. " is sent")
	eq(last().id, e.id, name .. ": the pack id")
	eq(last().x - e.dx, HERE.x, name .. ": centred on the centre tile (x)")
	eq(last().y - e.dy, HERE.y, name .. ": centred on the centre tile (y)")
	eq(last().who, nil, name .. ": to every spectator")
	-- the centre tile lies inside the picture, with at least 2 tiles on every side
	ok(e.dx >= 2 and e.dy >= 2 and e.w - 1 - e.dx >= 2 and e.h - 1 - e.dy >= 2, alt .. ": the anchor is not at an edge")
	ok(Vfx(HERE, name, true), name .. " raw")
	eq(last().id, OLD[name], name .. ": raw keeps our id")
	local se = C.swapId({id = OLD[name], dx = 3, dy = 3})
	eq(se.id, e.id, name .. ": by id")
	eq(se.dx, e.dx, name .. ": by id, the pack offset")
end
eq(swaps, 5, "five bursts")
eq(C.swap("big_nova_void_7"), "big_nova_void_7", "another burst is not swapped")
eq(C.swap(nil), nil, "no name")
eq(C.swapId({id = 647, dx = 3, dy = 3}).id, 647, "another id is not swapped")
ok(Vfx(HERE, "big_nova_void_7"), "another burst is sent")
eq(last().id, 647, "another burst keeps its id")
eq(Vfx(HERE, "no_such_effect"), false, "an unknown name sends nothing")
-- the size rule: the blood sigil is 6 tiles wide, an area of 9 keeps ours
eq(C.swap("big_shock_blood_9", 7), "ab_blood_sigil", "blood on 7 tiles")
eq(C.swap("big_shock_blood_9", 9), "big_shock_blood_9", "blood on 9 tiles keeps ours")
eq(C.swap("big_shock_fire_7", 9), "ab_fire_rain", "no size limit for the others")

-- the boss hit of chaos_big_fx.lua goes through the same door
dofile("data/lib/chaos_big_fx.lua")
local B = ChaosBigFx
ok(B.live(), "the large effects are on")
do
	local function disc(r)
		local t = {}
		for dx = -r, r do
			for dy = -r, r do
				if dx * dx + dy * dy <= r * r + r then
					t[#t + 1] = {x = HERE.x + dx, y = HERE.y + dy, z = HERE.z}
				end
			end
		end
		return t
	end
	ok(B.bossHit(disc(3), "physical"), "boss hit, 7 tiles")
	eq(last().id, 5301, "7 tiles: the sigil")
	ok(B.bossHit(disc(4), "physical"), "boss hit, 9 tiles")
	eq(last().id, 642, "9 tiles: ours")
	ok(B.bossHit(disc(4), "fire"), "fire boss hit")
	eq(last().id, 5300, "fire: the shard rain")
	ok(B.bossHit(disc(3), "holy"), "holy boss hit")
	eq(last().id, 1642, "holy: the refilled burst")
end

-- B. beams
local element = {}
for id, el in slurp("../client/overlay/modules/game_chaosspells/spelldata.lua"):gmatch('{ id = (%d+), name = "[^"]+"[^\n]-element = "(%w+)"') do
	element[tonumber(id)] = el
end
eq(element[118], "death", "the client spell list is read")
dofile("data/scripts/chaos/attack_kit_config.lua")
local kit = {}
for _, spec in pairs(ChaosAttackKit.cfg.spells or ChaosAttackKit.cfg) do
	if type(spec) == "table" and spec.id then
		kit[spec.id] = spec
	end
end
local STEP = C.STEP
dofile("data/scripts/chaos/attack_kit_core.lua")
local K = ChaosAttackKitCore
local beams, long, natural = 0, 0, 0
local usedBeam = {}
for spellId, base in pairs(C.beams) do
	beams = beams + 1
	local spec = kit[spellId]
	ok(spec and spec.shape == "line", spellId .. ": a line spell of the attack kit")
	ok(I.beams[base], base .. ": a beam of the ids file")
	ok(I.lengths[base] and I.lengths[base][spec.length], spellId .. ": the pair has the beam at the spell's line length " .. spec.length)
	for dir = 0, 7 do
		local d = C.DIRNAME[dir]
		local s = STEP[dir]
		local straight = s[1] == 0 or s[2] == 0
		-- the damage line: `length` tiles from the caster's along the heading
		local line = K.tiles(spec, HERE, dir)
		eq(#line, spec.length, spellId .. " " .. d .. ": the damage line")
		eq(line[#line][1], HERE.x + s[1] * spec.length, "the last tile of the line (x)")
		eq(line[#line][2], HERE.y + s[2] * spec.length, "the last tile of the line (y)")
		-- O609: ONE effect, as long as that line
		local segs = C.beam(spellId, dir, spec.length)
		ok(segs and #segs == 1, spellId .. " " .. d .. ": one effect, not a chain")
		eq(segs[1].at, 0, spellId .. " " .. d .. ": from the caster's tile")
		eq(segs[1].len, spec.length, spellId .. " " .. d .. ": named for the length of the line")
		local name = segs[1].name
		eq(name, I.lengths[base][spec.length][d], "the name of the lengths table")
		local e = I.effects[name]
		ok(e and e.role == "beam", name .. ": a beam of the pair")
		eq(e.element, element[spellId], spellId .. " " .. d .. ": the spell's element")
		eq(ChaosVfx[name].id, e.id, name .. ": known to Vfx")
		usedBeam[name] = true
		local reach
		if e.refill then
			-- the pack's own art is as long as the line: only 3 tiles on a straight heading
			natural = natural + 1
			ok(straight and spec.length == I.natural, name .. ": the pack's own beam only where the line is its length")
			eq(name, base .. "_" .. d, "the refilled name")
			reach = I.natural
		else
			long = long + 1
			eq(name, base .. "_l" .. spec.length .. "_" .. d, "the name says the length")
			eq(e.len, spec.length, name .. ": made for the length of the line")
			-- the art covers the whole line; only a beam cut at the caster's view (7 tiles south) stops one tile short
			ok(e.reach == e.len or (e.reach == e.len - 1 and s[2] > 0 and e.dy == 7), name .. ": the art covers " .. e.reach ..
				" tiles of " .. e.len)
			reach = e.reach
		end
		-- the canvas holds those tiles from the caster's along the heading, and at most one more (a tip that spills)
		local far = {}
		if s[1] > 0 then far[#far + 1] = e.dx end
		if s[1] < 0 then far[#far + 1] = e.w - 1 - e.dx end
		if s[2] > 0 then far[#far + 1] = e.dy end
		if s[2] < 0 then far[#far + 1] = e.h - 1 - e.dy end
		for _, f in ipairs(far) do
			ok(f >= reach and f <= reach + 1, name .. ": the canvas reaches " .. f .. " tiles for a beam of " .. reach)
		end
		-- the caster gets its own beam: the far corner of the picture is in its view
		ok(C.sees(HERE, {x = HERE.x + e.dx, y = HERE.y + e.dy, z = HERE.z}), name .. ": the caster sees the far corner")
		local before = #sent
		ok(C.sendBeam(HERE, spellId, dir, spec.length), "beam sent")
		eq(#sent - before, 1, spellId .. " " .. d .. ": one effect is sent")
		eq(last().id, e.id, "the id of the length and heading")
		eq(last().x, HERE.x + e.dx, "sent so that the caster's tile is the start (x)")
		eq(last().y, HERE.y + e.dy, "sent so that the caster's tile is the start (y)")
		eq(last().who, nil, "to every spectator")
	end
end
eq(beams, 4, "four beam spells")
eq(natural, 4, "Lance of Vigil on the four straight headings is the pack's own beam, 3 tiles")
eq(long, 28, "28 long beams: every other spell and heading")
eq(C.beams[118], "mega_soul_chain", "Soulrend Beam is the chain of souls")
eq(C.beam(118, 1, 6)[1].name, "mega_soul_chain_l6_e", "Soulrend Beam east: one beam of 6 tiles")
eq(I.effects.mega_soul_chain_l6_e.id, 5305, "its id")
eq(C.beam(129, 1, 3)[1].name, "mega_sunbeam_lance_e", "Lance of Vigil east: the pack's own 3 tiles")
eq(C.beam(129, 7, 3)[1].name, "mega_sunbeam_lance_l3_ne", "Lance of Vigil north-east: a beam made for 3 diagonal tiles")
eq(C.beam(151, 1, 8)[1].name, "mega_sunbeam_lance_l8_e", "Dawnbreaker Shot east: one beam of 8 tiles")
eq(C.beam(155, 2, 5)[1].name, "mega_blood_siphon_l5_s", "Eclipse Edge south: one beam of 5 tiles")
-- every long beam of the pair is the beam of a spell
for name, e in pairs(I.effects) do
	if e.len then
		ok(usedBeam[name], name .. ": a long beam no spell draws")
	end
end
-- the chain of O607 stays for a length the pair has no beam for
eq(#C.chain(118, 1, 6), 2, "the chain: two copies of 3 tiles")
eq(C.chain(118, 1, 6)[2].at, 3, "the second copy starts where the first ends")
local odd = C.beam(118, 1, 7)
eq(#odd, 2, "a length with no variant falls back to the chain")
eq(odd[1].name, "mega_soul_chain_e", "the chain is the pack's own beam")
eq(odd[1].len, nil, "a chain copy is not named for a length")
eq(C.beam(9, 1, 3), nil, "a line spell with no beam")
eq(C.beam(118, 9, 6), nil, "no such heading")
eq(C.chain(9, 1, 3), nil, "no chain either")
ok(I.beams.mega_glacier_breath, "the ice beam is in the pair")
ok(not I.lengths.mega_glacier_breath, "the ice beam has no long variant")
for _, base in pairs(C.beams) do
	ok(base ~= "mega_glacier_breath", "the ice beam has no sender")
end
-- the view: 8 tiles west, 9 east, 6 north, 7 south
ok(C.sees(HERE, {x = HERE.x + 9, y = HERE.y + 7, z = HERE.z}), "the far corner of the view")
ok(not C.sees(HERE, {x = HERE.x + 10, y = HERE.y, z = HERE.z}), "10 east is out")
ok(not C.sees(HERE, {x = HERE.x, y = HERE.y + 8, z = HERE.z}), "8 south is out")
ok(C.sees(HERE, {x = HERE.x - 8, y = HERE.y - 6, z = HERE.z}) and not C.sees(HERE, {x = HERE.x - 9, y = HERE.y, z = HERE.z}), "west and north")
-- with the engine's spectators: who sees the far corner gets the one piece, who stands behind the caster gets the chain
do
	local function viewer(dx, dy)
		return {getPosition = function() return {x = HERE.x + dx, y = HERE.y + dy, z = HERE.z} end}
	end
	local near, behind = viewer(1, 2), viewer(-6, 0)
	local asked
	Game = {getSpectators = function(pos, multifloor, onlyPlayers)
		asked = {pos = pos, multifloor = multifloor, onlyPlayers = onlyPlayers}
		return {near, behind}
	end}
	local before = #sent
	ok(C.sendBeam(HERE, 118, 1, 6), "Soulrend Beam east with two viewers")
	ok(asked and asked.onlyPlayers == true and asked.pos == HERE, "the players around the caster are asked for")
	local got = {[near] = {}, [behind] = {}}
	for i = before + 1, #sent do
		local list = got[sent[i].who]
		ok(list, "every effect goes to one viewer")
		list[#list + 1] = sent[i]
	end
	eq(#got[near], 1, "a viewer who sees the far corner gets one effect")
	eq(got[near][1].id, 5305, "the beam of 6 tiles")
	eq(got[near][1].x, HERE.x + I.effects.mega_soul_chain_l6_e.dx, "at its far corner")
	eq(#got[behind], 2, "a viewer 6 tiles behind the caster cannot draw it: the chain")
	eq(got[behind][1].id, 3494, "the pack's own beam")
	eq(got[behind][2].x - got[behind][1].x, 3, "its second copy 3 tiles on")
	-- a beam towards the north-west has its far corner on the caster's tile: both viewers get the one piece
	before = #sent
	ok(C.sendBeam(HERE, 118, 6, 6), "Soulrend Beam north-west")
	eq(#sent - before, 2, "one effect each")
	eq(sent[#sent].id, I.effects.mega_soul_chain_l6_nw.id, "the one piece")
	Game = nil
end

-- C. markers
for use, name in pairs(C.marks) do
	local e = I.effects[name]
	ok(e and e.role == "mark", use .. ": a marker")
	eq(C.mark(use).id, e.id, use .. ": the id")
end
ok(C.sendMark(HERE, "locked", "player"), "the lock is sent")
eq(last().id, 3690, "the lock id")
eq(last().who, "player", "to that player only")
eq(last().x, HERE.x + I.effects.mega_util_locked_marker.dx, "at the gate tile")
ok(C.sendMark(HERE, "quest", "player"), "the quest marker is sent")
eq(last().id, 4051, "the quest marker id")
eq(C.sendMark(HERE, "nope", "player"), false, "no such use")
eq(C.sendMark(nil, "locked", "player"), false, "no position")

-- every effect of the ids file has a use or is named as having no sender
local used = {}
for _, alt in pairs(C.names) do used[alt] = true end
for _, base in pairs(C.beams) do
	for dir = 0, 7 do used[base .. "_" .. C.DIRNAME[dir]] = true end
end
for name in pairs(usedBeam) do used[name] = true end
for _, name in pairs(C.marks) do used[name] = true end
for name in pairs(I.effects) do
	ok(used[name] or name:match("^mega_glacier_breath_"), name .. ": in the pair but not in a table of chaos_area_fx.lua")
end

-- ---------------------------------------------------------------- the callers hold the hook
local vfx = slurp("data/lib/chaos_vfx.lua")
ok(vfx:find("function Vfx(pos, name, raw)", 1, true) and vfx:find("ChaosAreaFx.swap(name)", 1, true), "Vfx asks the swap")
ok(slurp("../client/tools/sprites/import_vfx.py"):find("ChaosAreaFx.swap(name)", 1, true), "the generator of chaos_vfx.lua writes the hook")
ok(slurp("data/scripts/chaos/deathfx.lua"):find("ChaosAreaFx.swapId(e)", 1, true), "deathfx.lua swaps by id")
ok(slurp("data/spells/chaos/_attackkit.lua"):find("B.sendBeam(pos, spec.id, dir, spec.length)", 1, true), "the attack kit draws the beam")
ok(slurp("data/scripts/chaos/chronicle.lua"):find('ChaosAreaFx.sendMark, pos, "locked", player', 1, true), "chronicle.lua marks the gate")
ok(slurp("data/scripts/chaos/areagen.lua"):find('ChaosAreaFx.sendMark, position, "locked", player', 1, true), "areagen.lua marks the entrance")
ok(slurp("data/scripts/chaos/mainquest.lua"):find('"quest", player', 1, true), "mainquest.lua marks the loot bag")

print("area_fx_test: " .. n .. " checks passed")
