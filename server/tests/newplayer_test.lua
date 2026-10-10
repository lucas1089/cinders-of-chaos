-- Run from the server/ folder: luajit tests/newplayer_test.lua (CI runs it with LuaJIT and Lua 5.3)
-- New players (newplayer_core.lua + newplayer_config.lua): kit lookup by vocation with the base-class and default
-- fallbacks, one-time flags, milestones, the tutorial island layout and its station state machine.
dofile("data/scripts/chaos/chaos_constants.lua")
dofile("data/scripts/chaos/newplayer_core.lua")
local NP = ChaosNewPlayer
local cfg = NP.cfg()

local fails, checks = 0, 0
local function ok(cond, what)
	checks = checks + 1
	if not cond then
		fails = fails + 1
		print("FAIL " .. what)
	end
end
local function eq(a, b, what)
	ok(a == b, what .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end
local function slotOf(kit, slot)
	for _, e in ipairs(kit.equip) do
		if e.slot == slot then
			return e
		end
	end
	return nil
end
local function bpCount(kit, id)
	local n = 0
	for _, b in ipairs(kit.backpack) do
		if b.id == id then
			n = n + (b.count or 1)
		end
	end
	return n
end

-- ------------------------------------------------------------------ kits by vocation
do
	-- the class ids of Chaos.classes.ids (class rework)
	local ids = Chaos.classes.ids
	eq(NP.kitNameFor(ids.warrior), "warrior", "warrior")
	eq(NP.kitNameFor(ids.juggernaut), "warrior", "juggernaut")
	eq(NP.kitNameFor(ids.berserker), "warrior", "berserker")
	eq(NP.kitNameFor(ids.ranger), "ranger", "ranger")
	eq(NP.kitNameFor(ids.deadeye), "ranger", "deadeye")
	eq(NP.kitNameFor(ids.beastmaster), "ranger", "beastmaster")
	eq(NP.kitNameFor(ids.mystic), "mystic", "mystic")
	eq(NP.kitNameFor(ids.elementalist), "mystic", "elementalist")
	eq(NP.kitNameFor(ids.illusionist), "mystic", "illusionist")
	eq(NP.kitNameFor(ids.thief), "thief", "thief")
	eq(NP.kitNameFor(ids.ninja), "ninja", "ninja")
	eq(NP.kitNameFor(ids.samurai), "thief", "samurai")
	eq(NP.kitNameFor(0), nil, "vocation 0 is left to the base firstitems.lua")
	for _, id in pairs(ids) do
		ok(NP.kitFor(id) ~= nil, "kit for vocation " .. id)
		eq(select(2, NP.kitNameFor(id)), "vocation", "own row for vocation " .. id)
	end
	-- every class id in Chaos.classes.baseOf has a kit row (a new class must add one)
	for id in pairs(Chaos.classes.baseOf) do
		ok(cfg.vocations[id] ~= nil, "row for class id " .. id)
	end
	-- a vocation without a row falls back to its base class (Chaos.classes.baseOf)
	local c0 = dofile("data/scripts/chaos/newplayer_config.lua")
	c0.vocations[14] = nil
	local name, how = NP.kitNameFor(14, c0)
	eq(name, "warrior", "berserker without a row -> warrior")
	eq(how, "base", "found by base class")
	-- the retired ids 2, 6, 9 get the default kit
	eq(NP.kitNameFor(2), "default", "retired id 2")
	-- engine demotion fallback, then default
	local old = NP.demotionOf
	NP.demotionOf = function(id)
		return id == 40 and 4 or nil
	end
	eq(NP.kitNameFor(40), "warrior", "unknown id with an engine demotion to a warrior")
	name, how = NP.kitNameFor(99)
	eq(name, "default", "unknown vocation -> default")
	eq(how, "default", "found as default")
	NP.demotionOf = old

	-- kit contents
	local k = NP.kitFor(4)
	eq(slotOf(k, "left").id, 8602, "warrior sword")
	eq(slotOf(k, "right").id, 2525, "warrior shield")
	eq(k.role, "melee", "warrior role")
	eq(bpCount(k, 2120), 1, "rope from the common items")
	eq(bpCount(k, 2554), 1, "shovel from the common items")
	ok(bpCount(k, 2789) > 0, "food")
	ok(bpCount(k, 7618) > 0, "health potions")
	eq(k.backpackId, 1988, "backpack")
	ok(k.templeScrollUses > 0, "temple scroll")
	ok(k.gold > 0, "gold")
	local r = NP.kitFor(3)
	eq(slotOf(r, "left").id, 2456, "ranger bow")
	eq(slotOf(r, "ammo").id, 2544, "ranger arrows")
	eq(r.role, "ranged", "ranger role")
	local s = NP.kitFor(1)
	eq(slotOf(s, "left").id, 2190, "mystic wand")
	eq(s.role, "caster", "caster role")
	local th = NP.kitFor(11)
	eq(slotOf(th, "left").id, 2379, "thief dagger")
	eq(bpCount(th, 2399), 30, "thief throwing stars")
	local nj = NP.kitFor(12)
	eq(slotOf(nj, "left").id, 2379, "ninja inherits the dagger")
	eq(bpCount(nj, 2399), 30, "ninja inherits the stars")
	eq(bpCount(nj, 2379), 1, "ninja off-hand dagger")
	eq(nj.role, "ranged", "ninja role inherited (the Royal Paladin's potions)")
	eq(NP.kitFor(17).role, "ranged", "monk: the Royal Paladin's potions")

	-- copies: changing a returned kit does not change the config
	k.equip[1].id = 1
	eq(NP.kitFor(4).equip[1].id, 8602, "kitFor returns a copy")

	-- the wand below its level: fallback equipped, the wand into the backpack
	local wand = slotOf(NP.kitFor(1), "left")
	local equip, spare = NP.equipFor(wand, 1)
	eq(equip, 23719, "level 1 mystic equips the scorcher")
	eq(spare, 2190, "and keeps the wand")
	equip, spare = NP.equipFor(wand, 8)
	eq(equip, 2190, "level 8 equips the wand")
	eq(spare, nil, "nothing spare")

	-- setKit: the class rework adds a class
	local c = dofile("data/scripts/chaos/newplayer_config.lua")
	NP.setKit("berserker", {base = "warrior", equip = {{slot = "left", id = 2378}}}, {14}, c)
	eq(NP.kitNameFor(14, c), "berserker", "setKit maps the vocation")
	local b = NP.kitFor(14, c)
	eq(slotOf(b, "left").id, 2378, "setKit replaces the weapon")
	eq(slotOf(b, "right").id, 2525, "and inherits the rest")
	NP.setKit("ranger", "ranger", {16}, c)
	eq(NP.kitNameFor(16, c), "ranger", "setKit with an existing kit name")
end

-- ------------------------------------------------------------------ one-time flags
do
	eq(NP.key("kit"), 7100250, "kit storage")
	eq(NP.key("stage"), 7100252, "stage storage")
	eq(NP.milestoneKey(1), 7100260, "first milestone storage")
	eq(NP.milestoneKey(4), 7100263, "fourth milestone storage")
	ok(NP.milestoneKey(#cfg.milestones) <= 7100269, "milestones stay in the reserved range")
	ok(not NP.isSet(-1), "unset storage")
	ok(NP.isSet(1700000000), "set storage")
	ok(NP.kitDueAtLogin(-1, 0), "new character gets the kit")
	ok(not NP.kitDueAtLogin(1700000000, 0), "never twice")
	ok(not NP.kitDueAtLogin(-1, 1700000000), "existing characters never get it by logging in")
	local m = 0
	m = NP.setBit(m, 4)
	m = NP.setBit(m, 4)
	eq(m, 4, "setBit is idempotent")
	ok(NP.hasBit(m, 4) and not NP.hasBit(m, 2), "hasBit")
	ok(not NP.hasBit(-1, 1), "unset mask")
end

-- ------------------------------------------------------------------ milestones
do
	local claimed = {}
	local function isClaimed(i)
		return claimed[i] == true
	end
	local due = NP.milestonesDue(19, 20, isClaimed)
	eq(#due, 1, "19 -> 20")
	eq(due[1], 1, "level 20 gift")
	claimed[1] = true
	eq(#NP.milestonesDue(19, 20, isClaimed), 0, "never twice (death and level 20 again)")
	eq(#NP.milestonesDue(20, 21, isClaimed), 0, "nothing at 21")
	due = NP.milestonesDue(45, 120, isClaimed)
	eq(#due, 2, "a big jump reaches 50 and 100")
	eq(due[1], 2, "50 first")
	eq(due[2], 3, "then 100")
	eq(#NP.milestonesDue(120, 110, isClaimed), 0, "level loss")
	eq(#NP.milestonesDue(199, 200, isClaimed), 1, "200")

	local items = NP.milestoneItems(3, "melee")
	local orbs, stamina, potions = 0, 0, 0
	for _, it in ipairs(items) do
		if it.id == cfg.orbId then
			orbs = orbs + it.count
		elseif it.id == 27990 then
			stamina = stamina + it.count
		else
			potions = potions + it.count
		end
	end
	eq(orbs, 3, "level 100: 3 Orbs of Upheaval")
	ok(stamina > 0, "level 100: stamina refill item")
	ok(potions > 0, "level 100: potions")
	-- the Thief and Monk lines drink the Royal Paladin's potions (add_vocations.py): the ranged gifts
	local thiefRole = NP.kitFor(11).role
	eq(thiefRole, "ranged", "thief role")
	local has = false
	for _, it in ipairs(NP.milestoneItems(3, thiefRole)) do
		has = has or it.id == 8472
	end
	ok(has, "thief level 100: great spirit potions")
	ok(#NP.milestoneItems(1, "nonsense") > 0, "an unknown role falls back to melee potions")
	eq(#NP.milestoneItems(9, "melee"), 0, "unknown milestone")
end

-- ------------------------------------------------------------------ tutorial island
do
	local t = cfg.tutorial
	local L = NP.layout()
	eq(#L.rooms, t.rooms, "rooms")
	eq(#L.gates, t.rooms - 1, "gates")
	local foot = NP.footprint(L)
	local W = t.rooms * (t.roomW + 1) + 1 + 2 * t.waterRing
	local H = t.roomH + 2 + 2 * t.waterRing
	eq(#foot, W * H, "footprint size")
	local kinds, seen = {}, {}
	for _, f in ipairs(foot) do
		kinds[f.kind] = (kinds[f.kind] or 0) + 1
		local k = f.x .. ":" .. f.y
		ok(not seen[k], "tile listed once " .. k)
		seen[k] = true
		ok(f.x < 4500 or f.x > 4500, "x in the free area")
	end
	eq(kinds.gate, t.rooms - 1, "gate tiles")
	eq(kinds.marker, t.rooms, "marker tiles")
	eq(kinds.wall, (t.rooms - 1) * (t.roomH - 1), "divider walls (minus the gates)")
	eq(kinds.ground, t.rooms * t.roomW * t.roomH - t.rooms, "ground tiles")
	ok(L.outer.x1 >= 4500 and L.outer.x2 <= 5600 and L.outer.y1 >= 4500 and L.outer.y2 <= 5600, "inside the tile-less area")
	ok(L.outer.x2 < 5000 or L.outer.y2 < 5000, "away from the world boss arena")
	-- the points of interest are on walkable ground
	local kindAt = {}
	for _, f in ipairs(foot) do
		kindAt[f.x .. ":" .. f.y] = f.kind
	end
	for i, r in ipairs(L.rooms) do
		eq(NP.roomOf(r.arrival, L), i, "arrival in room " .. i)
		eq(NP.roomOf(r.marker, L), i, "marker in room " .. i)
		eq(NP.roomOf(r.statue, L), i, "statue in room " .. i)
		eq(kindAt[r.marker.x .. ":" .. r.marker.y], "marker", "marker tile kind " .. i)
	end
	for i, g in ipairs(L.gates) do
		eq(kindAt[g.x .. ":" .. g.y], "gate", "gate tile " .. i)
		eq(NP.roomOf(g, L), nil, "gate is between rooms")
	end
	for _, s in ipairs(L.spawns) do
		eq(NP.roomOf(s, L), 1, "spawn in the first pen")
	end
	eq(NP.roomOf(L.exit, L), t.rooms, "exit in the last room")
	eq(NP.roomOf(L.skipStatue, L), 1, "skip statue in the first room")
	ok(NP.onIsland(L.rooms[3].arrival, L), "on the island")
	ok(not NP.onIsland({x = 1000, y = 1000, z = 7}, L), "the mainland is not the island")
	ok(not NP.onIsland({x = L.rooms[1].arrival.x, y = L.rooms[1].arrival.y, z = 6}, L), "other floor")

	-- state machine
	ok(not NP.inTutorial(-1), "never started")
	ok(NP.inTutorial(1) and NP.inTutorial(5), "stations")
	ok(not NP.inTutorial(cfg.stageDone) and not NP.inTutorial(cfg.stageSkipped), "finished / skipped")
	local done = 0
	ok(not NP.gateOpen(1, done), "gate 1 closed")
	done = NP.setBit(done, NP.stationBit(1))
	ok(NP.gateOpen(1, done), "gate 1 open after station 1")
	ok(not NP.gateOpen(2, done), "gate 2 still closed")
	eq(NP.stageAfterGate(1, 1), 2, "through gate 1 -> station 2")
	eq(NP.stageAfterGate(1, 4), 4, "walking back and forth never lowers the stage")
	ok(not NP.exitOpen(5, done), "exit closed")
	for i = 2, 4 do
		done = NP.setBit(done, NP.stationBit(i))
	end
	ok(not NP.exitOpen(4, done), "exit needs the last station reached")
	ok(NP.exitOpen(5, done), "exit open")
	eq(NP.resumeSpot(3, L).x, L.rooms[3].arrival.x, "resume at the station")
	eq(NP.resumeSpot(99, L).x, L.rooms[#L.rooms].arrival.x, "resume clamps")

	-- station 2
	ok(not NP.spellTaskDone(0, true), "nothing done")
	ok(not NP.spellTaskDone(1, true), "spellbook only, spell missing")
	ok(NP.spellTaskDone(3, true), "spellbook and spell")
	ok(NP.spellTaskDone(1, false), "a class without a level 1 spell only opens the book")
	eq(NP.tutorialSpellFor(4).words, "saen tin brak", "warrior spell")
	eq(NP.tutorialSpellFor(8).words, "saen tin brak", "juggernaut spell")
	eq(NP.tutorialSpellFor(3).words, "saen tin", "ranger spell")
	eq(NP.tutorialSpellFor(1).words, "saen tin", "mystic spell")
	eq(NP.tutorialSpellFor(10).words, "saen tin", "illusionist spell")
	eq(NP.tutorialSpellFor(11), nil, "no thief spell at level 1")
	eq(NP.tutorialSpellFor(12), nil, "no ninja spell at level 1")
	eq(#t.lessons, t.rooms, "a lesson per station")
end

print(string.format("newplayer_test: %d checks, %d failures", checks, fails))
if fails > 0 then
	os.exit(1)
end
