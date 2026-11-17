-- Run from the server/ folder: luajit tests/area_fx_test.lua (and lua5.3; CI runs both)
-- An area burst, beams, markers and a status effect of the purchased effect packs (O607, client pair 73,
-- data/lib/chaos_area_fx.lua and the generated chaos_area_fx_ids.lua): the gate is config.lua chaosClientPair >= 73 and below
-- it every sender sends exactly what it sends today; a refill keeps the id and send offset of chaos_pack36_fx_ids.lua; the
-- new ids are the block 5300..; a beam is the heading from the caster to the target; a marker goes to one player; every id
-- has its element tag.
-- O609: every beam spell draws ONE effect per heading, as long as its damage line (one start, one tip): the generated
-- lengths table, the ids 5301.., the canvas, the view of the caster; the chain of copies only for a length the pair
-- lacks and for a viewer who cannot draw the one piece.
-- O613 (owner 2026-11-17): our own fire, blood, frost and holy bursts are sent again by every sender (spells, boss hits,
-- boss deaths), gate on or off; the pack's clock face goes to the arcane nova of Veil of Whispers and Tear in the Weave
-- only; Eclipse Edge has no beam; a slowed creature shows the pack's gravity press in place of the whirlwind.
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
	if type(x) == "table" then
		x, y, z = x.x, x.y, x.z
	end
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
-- our own bursts: O607 swapped the first four for pack bursts, O613 gave them back; 648 is the arcane nova
local OLD = {big_shock_fire_7 = 638, big_shock_blood_9 = 642, big_nova_frost_7 = 644, big_nova_holy_7 = 646,
	big_nova_arcane_7 = 648}

-- ---------------------------------------------------------------- gate off: exactly what is sent today
for name, id in pairs(OLD) do
	ok(Vfx(HERE, name), name .. " is sent")
	eq(last().id, id, name .. ": gate off, our id")
	eq(last().x, HERE.x + pack36[name].dx, name .. ": gate off, our offset")
end
eq(C.spellBurst(153, "big_nova_arcane_7"), nil, "gate off: Veil of Whispers keeps our nova")
eq(C.spellBurst(231, "arcane_circle"), nil, "gate off: Tear in the Weave keeps what it sends")
eq(C.statusName("slowed"), nil, "gate off: a slowed creature keeps the whirlwind")
eq(C.beam(118, 1, 6), nil, "gate off: no beam")
eq(C.sendBeam(HERE, 118, 1, 6), false, "gate off: no beam is drawn")
eq(C.mark("locked"), nil, "gate off: no marker")
local count = #sent
eq(C.sendMark(HERE, "locked", "player"), false, "gate off: no marker is sent")
eq(#sent, count, "gate off: nothing more was sent")
eq(ChaosAreaFxIds, nil, "gate off: the ids are not even loaded")
eq(ChaosVfx.ab_arcane_clock, nil, "gate off: no name merged")
-- the large effects and the slowed aura with the gate off: what they sent before pair 73
dofile("data/lib/chaos_big_fx.lua")
local B = ChaosBigFx
ok(B.live(), "the large effects are on")
eq(B.swapFor(231, "arcane_circle"), "big_nova_arcane_7", "the large effect of each implosion of Tear in the Weave is our arcane nova")
eq(B.swapFor(153, "big_nova_arcane_7"), nil, "Veil of Whispers names the nova itself")
dofile("data/lib/chaos_pack29_fx.lua")
dofile("data/lib/chaos_pack29_vfx.lua")
dofile("data/lib/chaos_pack29_vfx_ids.lua")
local V = ChaosPack29Vfx
ok(V.live(), "the pair 29 auras are on")
eq(V.auraNow("slowed"), "cond_slowed", "gate off: the aura of a slowed creature is the whirlwind")
local function creature(id)
	return {getId = function() return id end, getPosition = function() return Position(HERE.x, HERE.y, HERE.z) end}
end
V.resetThrottle()
ok(V.show(creature(11), "slowed"), "gate off: the slowed aura is sent")
eq(last().id, 783, "gate off: the whirlwind 783")

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
		eq(e.len ~= nil, e.id >= I.first + 1, name .. ": the long beams follow the one burst")
		eq(ChaosVfx[name].id, e.id, name .. ": merged into ChaosVfx")
	end
end
eq(new, I.count, "the recorded count")
eq(total, 51, "51 effects: 30 refilled, 1 new burst, 20 long beams")
eq(I.count, 21, "the new block is 5300..5320")
for _, gone in ipairs({"ab_fire_rain", "ab_blood_sigil", "area_whiteout", "area_radiant_repulse", "mega_blood_siphon_n",
	"mega_blood_siphon_l5_n"}) do
	eq(I.effects[gone], nil, gone .. ": O613, not in the pair")
end
for _, id in ipairs({1612, 1642, 3356, 3363}) do
	eq(ids[id], nil, "effect " .. id .. ": O613, blank again")
end
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

-- A. O613: our own bursts are sent by every sender, gate on as off (O607 had swapped four of them in Vfx)
for name, id in pairs(OLD) do
	ok(Vfx(HERE, name), name .. " is sent")
	eq(last().id, id, name .. ": gate on, still our id")
	eq(last().x, HERE.x + pack36[name].dx, name .. ": gate on, our offset")
	eq(last().who, nil, name .. ": to every spectator")
end
eq(Vfx(HERE, "no_such_effect"), false, "an unknown name sends nothing")
eq(C.names, nil, "no swap by name is left")
eq(C.swap, nil, "no swap door is left")
eq(C.swapId, nil, "no swap by id is left")
-- the boss hits and the spells of chaos_big_fx.lua send ours
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
	for element, id in pairs({physical = 642, fire = 638, holy = 646}) do
		ok(B.bossHit(disc(3), element), element .. " boss hit, 7 tiles")
		eq(last().id, id, element .. " boss hit: ours")
		ok(B.bossHit(disc(4), element), element .. " boss hit, 9 tiles")
		eq(last().id, id, element .. " boss hit on 9 tiles: ours")
	end
	eq(B.swapFor(206, "fire_explosion"), "big_shock_fire_7", "Doomtide: our fire shockwave")
	eq(B.swapFor(225, "earth_spikes"), "big_shock_fire_7", "Colossus Fall: our fire shockwave")
	eq(B.swapFor(148, "aura_burst_red"), "big_shock_blood_9", "Judgment of Iron: our blood shockwave")
	eq(B.swapFor(213, "frost_nova"), "big_nova_frost_7", "Primordial Squall: our frost nova")
	eq(B.swapFor(199, "dome_blast_holy"), "big_nova_holy_7", "Purging Nova: our holy nova")
	eq(B.swapFor(237, "dome_blast_holy"), "big_nova_holy_7", "Hammer of Ember Dawn: our holy nova")
	eq(B.pickUse("wb_enrage"), "big_shock_blood_9", "the world boss enrage: our blood shockwave")
end
-- the boss death effect is sent by id, as it is in the config (deathfx.lua has no hook)
dofile("data/scripts/chaos/deathfx_config.lua")
ok(not slurp("data/scripts/chaos/deathfx.lua"):find("ChaosAreaFx", 1, true), "deathfx.lua asks no swap")
ok(slurp("data/scripts/chaos/deathfx_config.lua"):find("fire = {id = 638, dx = 3, dy = 3", 1, true), "a fire boss death is our 638")

-- A. the clock face: the arcane nova of two spells only
local clock = I.effects.ab_arcane_clock
ok(clock and clock.role == "area" and clock.id == 5300, "the clock face is the area burst 5300")
eq(clock.element, "arcane", "the clock face is arcane, as the nova it stands in for")
eq(tags.ab_arcane_clock.element, "arcane", "and tagged so")
-- the centre tile lies inside the picture with 3 tiles on every side: a disc of 7 tiles, as our nova (7 x 7)
ok(clock.dx >= 3 and clock.dy >= 3 and clock.w - 1 - clock.dx >= 3 and clock.h - 1 - clock.dy >= 3, "the clock covers 7 tiles round its centre")
local asks = {[153] = "big_nova_arcane_7", [231] = "arcane_circle"}   -- the name each script sends to ChaosSpell.vfx
local bursts = 0
for spellId, t in pairs(C.spellBursts) do
	for name, alt in pairs(t) do
		bursts = bursts + 1
		eq(name, asks[spellId], spellId .. ": the name its script sends")
		eq(alt, "ab_arcane_clock", spellId .. ": the clock face")
		eq(C.spellBurst(spellId, name), alt, spellId .. ": swapped")
	end
end
eq(bursts, 2, "two spells")
ok(C.spellBursts[153] and C.spellBursts[231], "Veil of Whispers (153) and Tear in the Weave (231)")
local xml = slurp("data/spells/chaos/spells_chaos.xml")
ok(xml:find('spellid="153" name="Veil of Whispers"', 1, true), "153 is Veil of Whispers")
ok(xml:find('spellid="231" name="Tear in the Weave"', 1, true), "231 is Tear in the Weave")
ok(xml:find('spellid="231"[^\n]-illusionist/reality_rift.lua'), "231 is the script reality_rift.lua")
ok(slurp("data/spells/chaos/sorcerer/veil_of_whispers.lua"):find("'big_nova_arcane_7', 'arcane_circle'", 1, true), "Veil of Whispers asks for the arcane nova")
ok(slurp("data/spells/chaos/illusionist/reality_rift.lua"):find('ChaosSpell.vfx(center, "arcane_circle")', 1, true), "each implosion asks for arcane_circle")
eq(B.pick(231, "arcane_circle"), "big_nova_arcane_7", "which is the arcane nova 648 of the large effects")
eq(C.spellBurst(231, "void_rift"), nil, "Tear in the Weave: the rift stays ours")
eq(C.spellBurst(231, "big_nova_arcane_7"), nil, "Tear in the Weave: only the name it sends")
eq(C.spellBurst(153, "arcane_circle"), nil, "Veil of Whispers: its fallback name is not touched")
eq(C.spellBurst(230, "big_nova_arcane_7"), nil, "another spell that names the nova keeps it")
eq(C.spellBurst(nil, "big_nova_arcane_7"), nil, "no spell: no clock")
eq(C.spellBurst(153, nil), nil, "no name: no clock")
eq(B.swapFor(231, "arcane_circle"), "big_nova_arcane_7", "the large effects are asked nothing new")
ok(Vfx(HERE, C.spellBurst(153, "big_nova_arcane_7")), "the clock is sent")
eq(last().id, 5300, "the clock id")
eq(last().x - clock.dx, HERE.x, "the clock is centred on the caster's tile (x)")
eq(last().y - clock.dy, HERE.y, "the clock is centred on the caster's tile (y)")
ok(Vfx(HERE, "big_nova_arcane_7"), "any other sender of the arcane nova")
eq(last().id, 648, "any other sender: our 648")
-- through the door the spells use: ChaosSpell.vfx of _common.lua, inside a cast (the supports wrapper names the spell)
do
	local cast
	ChaosSupportsSpell = {cast = function() if cast then return 7, cast end end}
	local keep = {Vfx = Vfx}
	NORTH, EAST, SOUTH, WEST, SOUTHWEST, SOUTHEAST, NORTHWEST, NORTHEAST = 0, 1, 2, 3, 4, 5, 6, 7
	CONST_ME_POFF = 3
	Player = function() return nil end
	dofile("data/spells/chaos/_common.lua")
	ok(ChaosSpell and ChaosSpell.areaBurst, "the spells' library has the door")
	local function sendsIn(spellId, name)
		cast = spellId
		local before = #sent
		local okv = ChaosSpell.vfx(HERE, name)
		cast = nil
		return okv, #sent - before, last().id
	end
	local okv, count, id = sendsIn(153, "big_nova_arcane_7")
	ok(okv and count == 1, "Veil of Whispers: one effect")
	eq(id, 5300, "Veil of Whispers: the clock")
	okv, count, id = sendsIn(231, "arcane_circle")
	ok(okv and count == 1, "Tear in the Weave, an implosion: one effect")
	eq(id, 5300, "Tear in the Weave: the clock, before the pair 29 swap and the large effect")
	okv, count, id = sendsIn(231, "void_rift")
	ok(okv and id ~= 5300, "Tear in the Weave: the rift is not the clock")
	okv, count, id = sendsIn(160, "big_nova_arcane_7")
	ok(okv and count == 1, "another spell that sends the nova")
	eq(id, 648, "another spell: our 648")
	eq(ChaosSpell.areaBurst("big_nova_arcane_7"), nil, "outside a cast: no clock")
	-- gate off: what the two spells sent before (648 for the Veil; the pair 29 gravity crush for the implosion)
	C.ON = false
	okv, count, id = sendsIn(153, "big_nova_arcane_7")
	eq(id, 648, "gate off: Veil of Whispers sends our nova")
	okv, count, id = sendsIn(231, "arcane_circle")
	ok(okv and count == 1 and id ~= 5300, "gate off: an implosion is not the clock")
	eq(id, ChaosVfx.weave_crush and ChaosVfx.weave_crush.id or 648, "gate off: an implosion is what pair 29 draws (775) or our nova")
	C.ON = true
	ChaosSupportsSpell = nil
	Vfx = keep.Vfx
end

-- D. the status effect: the gravity press on a slowed creature
do
	local g = I.effects.mega_gravity_press
	ok(g and g.role == "status" and g.refill and g.id == 3036, "the gravity press is the refilled 3036")
	eq(C.status.slowed, "mega_gravity_press", "slowed -> the gravity press")
	eq(C.statusName("slowed"), "mega_gravity_press", "gate on: the name")
	eq(C.statusName("stunned"), nil, "another state has no stand-in")
	eq(C.statusName(nil), nil, "no state")
	local states = 0
	for state in pairs(C.status) do
		states = states + 1
		ok(V.auras[state], state .. ": a state of chaos_pack29_vfx.lua")
	end
	eq(states, 1, "one state")
	eq(V.auraFor("slowed"), "cond_slowed", "the table of auras is untouched")
	eq(V.auraNow("slowed"), "mega_gravity_press", "gate on: the aura of a slowed creature now")
	eq(V.auraNow("stunned"), "cond_stunned", "another state keeps its aura")
	V.resetThrottle()
	local before = #sent
	ok(V.show(creature(12), "slowed"), "a slowed creature shows its aura")
	eq(#sent - before, 1, "one effect")
	eq(last().id, 3036, "the gravity press, not the whirlwind 783")
	eq(last().x, HERE.x + g.dx, "centred on the creature (x): the middle tile of 3 x 3")
	eq(last().y, HERE.y + g.dy, "centred on the creature (y)")
	eq(V.show(creature(12), "slowed"), false, "not sent again while it plays")
	ok(V.show(creature(12), "stunned"), "a stunned creature shows its own aura")
	eq(last().id, ChaosVfx.cond_stunned.id, "the stunned aura of pair 29")
	-- held: the next send comes after the gravity press has played (its own length, not the whirlwind's)
	local waits = {}
	addEvent = function(fn, ms) waits[#waits + 1] = ms end
	V.resetThrottle()
	ok(V.hold(creature(13), "slowed", 5000), "a slow of 5 s holds the effect")
	eq(waits[1], g.ms, "the next one after " .. g.ms .. " ms, the length of the gravity press")
	ok(g.ms ~= ChaosVfx.cond_slowed.ms, "which is not the whirlwind's length")
	addEvent = nil
	-- with the status layer of O597 live (lib/chaos_status_vfx.lua): its root status yields to the gravity press, so a
	-- slowed creature is not handed to the layer and the paralyse condition gives no root bit; other states go to the layer
	dofile("data/lib/chaos_status_vfx.lua")
	local L = ChaosStatusVfx
	local keepOn = ChaosStatusVfxIds.on
	ChaosStatusVfxIds.on = true
	ok(L.live(), "the status layer is live")
	eq(L.yield.root, "slowed", "the layer's root status is the slowed state")
	ok(L.yielded("root") and not L.yielded("stun") and not L.yielded("nope"), "root yields, nothing else")
	eq(L.markState(21, "slowed", 1000, 0), false, "slowed is not marked in the layer")
	ok(L.markState(21, "stunned", 1000, 0), "stunned is")
	eq(L.markMask(21, 1), L.bits.stun, "the mark is the stun alone")
	eq(L.cutBrief(21, L.bits.root + L.bits.burn, 0), L.bits.burn, "a paralysed creature shows no root in the layer")
	L.forget(21)
	V.resetThrottle()
	before = #sent
	ok(V.show(creature(14), "slowed"), "layer live: a slowed creature shows its effect")
	eq(#sent - before, 1, "layer live: one effect")
	eq(last().id, 3036, "layer live: the gravity press")
	before = #sent
	ok(V.show(creature(14), "stunned"), "layer live: stunned is taken")
	eq(#sent - before, 0, "layer live: by the layer, no aura is sent")
	C.ON = false
	ok(not L.yielded("root"), "area effects off: root does not yield")
	ok(L.markState(22, "slowed", 1000, 0), "area effects off: slowed is the layer's root")
	eq(L.cutBrief(22, L.bits.root, 0), L.bits.root, "area effects off: the root bit stays")
	C.ON = true
	L.forget(21)
	L.forget(22)
	L.forget(14)
	ChaosStatusVfxIds.on = keepOn
	-- the root word of chaos_status_fx.lua holds slowed too
	eq(V.words.word_rooted_vines, "slowed", "the root word is the slowed state")
	ok(slurp("data/spells/chaos/_common.lua"):find('pcall(ChaosPack29Vfx.hold, target, "slowed", ticks)', 1, true), "ChaosSpell.slow holds slowed")
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
eq(beams, 3, "three beam spells")
eq(natural, 4, "Lance of Vigil on the four straight headings is the pack's own beam, 3 tiles")
eq(long, 20, "20 long beams: every other spell and heading")
eq(C.beams[118], "mega_soul_chain", "Soulrend Beam is the chain of souls")
eq(C.beam(118, 1, 6)[1].name, "mega_soul_chain_l6_e", "Soulrend Beam east: one beam of 6 tiles")
eq(I.effects.mega_soul_chain_l6_e.id, 5303, "its id")
eq(C.beam(129, 1, 3)[1].name, "mega_sunbeam_lance_e", "Lance of Vigil east: the pack's own 3 tiles")
eq(C.beam(129, 7, 3)[1].name, "mega_sunbeam_lance_l3_ne", "Lance of Vigil north-east: a beam made for 3 diagonal tiles")
eq(C.beam(151, 1, 8)[1].name, "mega_sunbeam_lance_l8_e", "Dawnbreaker Shot east: one beam of 8 tiles")
-- O613: Eclipse Edge draws its line, no beam
eq(C.beams[155], nil, "Eclipse Edge has no beam")
eq(C.beam(155, 2, 5), nil, "Eclipse Edge south: nothing from the beam door")
eq(C.sendBeam(HERE, 155, 2, 5), false, "Eclipse Edge: the attack kit draws the line as before")
eq(kit[155].shape, "line", "Eclipse Edge is still a line spell")
eq(I.beams.mega_blood_siphon, nil, "the blood stream is not in the pair")
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
	eq(got[near][1].id, 5303, "the beam of 6 tiles")
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
for _, t in pairs(C.spellBursts) do
	for _, alt in pairs(t) do used[alt] = true end
end
for _, name in pairs(C.status) do used[name] = true end
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
ok(vfx:find("function Vfx(pos, name, raw)", 1, true) and vfx:find("name = skySwap(name)", 1, true) and not vfx:find("ChaosAreaFx", 1, true),
	"O613: Vfx asks no area swap (the bolt from the sky of O614 is its only swap)")
ok(not slurp("../client/tools/sprites/import_vfx.py"):find("ChaosAreaFx", 1, true), "the generator of chaos_vfx.lua writes no hook")
local big = slurp("data/lib/chaos_big_fx.lua")
ok(big:find("function C.send(pos, name)", 1, true) and not big:find("ChaosAreaFx", 1, true), "the large effects ask no swap: boss hits are ours on any size")
local common = slurp("data/spells/chaos/_common.lua")
ok(common:find("pcall(A.spellBurst, spellId, name)", 1, true) and common:find("local burst = not alt and areaBurst(name)", 1, true),
	"ChaosSpell.vfx asks for the burst of the spell, after the skin")
local p29 = slurp("data/lib/chaos_pack29_vfx.lua")
ok(p29:find("A.statusName(state)", 1, true) and p29:find("local name = auraNow(state)", 1, true), "the auras ask for the status effect")
ok(not slurp("data/scripts/chaos/prizes.lua"):find("jackpot", 1, true), "O613: the roulette sends no jackpot effect")
ok(slurp("data/spells/chaos/_attackkit.lua"):find("B.sendBeam(pos, spec.id, dir, spec.length)", 1, true), "the attack kit draws the beam")
ok(slurp("data/scripts/chaos/chronicle.lua"):find('ChaosAreaFx.sendMark, pos, "locked", player', 1, true), "chronicle.lua marks the gate")
ok(slurp("data/scripts/chaos/areagen.lua"):find('ChaosAreaFx.sendMark, position, "locked", player', 1, true), "areagen.lua marks the entrance")
ok(slurp("data/scripts/chaos/mainquest.lua"):find('"quest", player', 1, true), "mainquest.lua marks the loot bag")

print("area_fx_test: " .. n .. " checks passed")
