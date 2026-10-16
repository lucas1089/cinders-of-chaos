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
	eq(NP.kitNameFor(ids.berserker), "berserker", "berserker (two-handed, no shield)")
	eq(NP.kitNameFor(ids.ranger), "ranger", "ranger")
	eq(NP.kitNameFor(ids.deadeye), "ranger", "deadeye")
	eq(NP.kitNameFor(ids.beastmaster), "ranger", "beastmaster")
	eq(NP.kitNameFor(ids.mystic), "mystic", "mystic")
	eq(NP.kitNameFor(ids.elementalist), "mystic", "elementalist")
	eq(NP.kitNameFor(ids.illusionist), "mystic", "illusionist")
	eq(NP.kitNameFor(ids.thief), "thief", "thief")
	eq(NP.kitNameFor(ids.ninja), "ninja", "ninja")
	eq(NP.kitNameFor(ids.samurai), "samurai", "samurai (katana)")
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
	-- the only starting potions are the two Everfull ones (potions_config.lua, the wearable part): no kit carries stock
	-- health or mana potions (owner 2026-10-16)
	for name in pairs(cfg.kits) do
		local kit = NP.resolveKit(name)
		for _, id in ipairs({7618, 7620, 7588, 7589, 7590, 7591, 8472, 8473, 26029, 26030}) do
			eq(bpCount(kit, id), 0, "kit " .. name .. ": no stock potion " .. id)
		end
	end
	eq(k.backpackId, 1988, "backpack")
	ok(k.templeScrollUses > 0, "temple scroll")
	ok(k.gold > 0, "gold")
	local r = NP.kitFor(3)
	eq(slotOf(r, "left").id, 2456, "ranger bow")
	eq(slotOf(r, "ammo"), nil, "ranger: no arrows (bows fire without ammunition)")
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
	local bz = NP.kitFor(14)
	eq(slotOf(bz, "left").id, 2378, "berserker battle axe (two-handed)")
	eq(slotOf(bz, "right"), nil, "berserker: no shield")
	eq(bz.role, "melee", "berserker role")
	local sm = NP.kitFor(13)
	eq(slotOf(sm, "left").id, 2412, "samurai katana")
	eq(bpCount(sm, 2399), 30, "samurai keeps the thief's stars")
	eq(sm.role, "ranged", "samurai role inherited")
	eq(slotOf(NP.kitFor(23), "right").id, 2525, "templar: sword and shield (the warrior kit)")
	eq(slotOf(NP.kitFor(20), "left").id, 2190, "necromancer: the caster kit")

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
	-- the home town: the main city (Cinderhold, town 2) for brand-new characters only
	eq(cfg.homeTown.id, 2, "the main city is Cinderhold (town 2)")
	eq(NP.homeTownFor(1, false), 2, "a new character created in town 1 moves to the main city")
	eq(NP.homeTownFor(2, false), nil, "already there")
	eq(NP.homeTownFor(1, true), nil, "a character with its kit keeps its town")
	eq(NP.homeTownFor(nil, false), 2, "no town at all: the main city")
	local keep = {homeTown = {id = 2, keep = {4}}}
	eq(NP.homeTownFor(4, false, keep), nil, "a town the website offers as a choice is kept")
	eq(NP.homeTownFor(1, false, keep), 2, "other towns still move")
	eq(NP.homeTownFor(1, false, {homeTown = {id = 0}}), nil, "id 0 turns it off")
	eq(NP.homeTownFor(1, false, {}), nil, "no homeTown entry: off")
	local m = 0
	m = NP.setBit(m, 4)
	m = NP.setBit(m, 4)
	eq(m, 4, "setBit is idempotent")
	ok(NP.hasBit(m, 4) and not NP.hasBit(m, 2), "hasBit")
	ok(not NP.hasBit(-1, 1), "unset mask")
end

-- ------------------------------------------------------------------ milestones
do
	-- the welcome's gift line follows the milestone levels in the config and drops the ones already passed
	local levels = {}
	for _, m in ipairs(NP.cfg().milestones) do levels[#levels + 1] = m.level end
	local line = NP.giftLine(1)
	for _, l in ipairs(levels) do
		assert(line:find(tostring(l), 1, true), "gift line names level " .. l)
	end
	eq(NP.giftLine(levels[#levels]), "", "no gift line past the last milestone")
	eq(NP.giftLine(levels[#levels] - 1), "A gift waits for you at level " .. levels[#levels] .. ".", "one gift left")
	local text = string.format(NP.cfg().welcome.text, "Name", "Warrior", NP.giftLine(1))
	assert(text:find(line, 1, true) and not text:find("%s", 1, true), "welcome text takes the gift line")
end
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
	eq(#NP.milestoneItems(99, "melee"), 0, "unknown milestone")
	-- gifts over the whole level range (2026-10-15): up to 2000, Orbs of Fate and Grafting late, 10 storages at most
	ok(#cfg.milestones <= 10, "at most 10 milestones")
	eq(cfg.milestones[#cfg.milestones].level, 2000, "the last gift at 2000")
	local last = 0
	for _, m in ipairs(cfg.milestones) do
		ok(m.level > last, "milestones rise")
		last = m.level
	end
	local fate, graft = 0, 0
	for _, it in ipairs(NP.milestoneItems(#cfg.milestones, "caster")) do
		if it.id == 29857 then fate = fate + it.count elseif it.id == 29855 then graft = graft + it.count end
	end
	ok(fate > 0 and graft > 0, "level 2000: Orbs of Fate and Grafting")
	due = NP.milestonesDue(299, 999, function() return false end)
	eq(#due, 3, "299 -> 999 reaches 300, 500 and 800")
end

-- ------------------------------------------------------------------ the start (owner design 2026-10-16)
do
	eq(cfg.tutorial.enabled, false, "no tutorial island by default (the code stays, the switch brings it back)")
	ok(cfg.welcome.helper and cfg.welcome.helper.open and cfg.welcome.helper.hint ~= "", "the first login opens the Helper")
	eq(cfg.welcome.window, false, "no welcome modal over the Helper (the text goes to the chat)")
	ok(cfg.welcome.firstToast:find("level 8", 1, true) ~= nil, "the first toast says the start level")
	-- a new character is raised to the start level once, without its kit; one with the kit keeps its level
	ok(NP.startLevelDue(1, false) and not NP.startLevelDue(1, true) and not NP.startLevelDue(8, false), "startLevelDue")
	-- the full kit at level 8: the Mystic wears its real wand (level 7), no spare in the rest
	local parts = NP.kitParts(NP.kitFor(1), 8)
	local wand = false
	for _, w in ipairs(parts.wear) do
		wand = wand or w.id == 2190
	end
	ok(wand, "level 8 Mystic wears the wand of vortex")
	for _, r in ipairs(parts.rest) do
		ok(r.id ~= 2190, "no spare wand at level 8")
	end
end

-- ------------------------------------------------------------------ tutorial island
do
	local t = cfg.tutorial
	local L = NP.layout()
	eq(#L.rooms, t.rooms, "rooms")
	eq(#L.gates, t.rooms - 1, "gates")
	local foot = NP.footprint(L)
	eq(#foot, (L.outer.x2 - L.outer.x1 + 1) * (L.outer.y2 - L.outer.y1 + 1), "footprint: every tile of the outer rectangle")
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
	local W, H = t.rooms * (t.roomW + 1) + 1, t.roomH + 2
	eq(kinds.fence, 2 * W + 2 * (H - 2) + (t.rooms - 1) * (t.roomH - 1), "the fence ring and the dividers (minus the gates)")
	-- the path: the middle row of every pen and a branch to each lesson tile
	local branch = L.cy - L.rooms[1].marker.y - 1
	local landPath = L.coast.x1 - L.land.x1
	eq(kinds.path, t.rooms * t.roomW + t.rooms * branch, "path tiles")
	eq(kinds.trail, landPath, "the way to the dock (land, not walked)")
	eq(kinds.ground, t.rooms * t.roomW * t.roomH - t.rooms - t.rooms * t.roomW - t.rooms * branch, "grass tiles in the pens")
	eq(kinds.dock, 2 * t.dockLength, "dock tiles")
	-- no black void: from every walkable tile the client's largest view (29 x 21, + 1) ends on built tiles
	local built = {}
	for _, f in ipairs(foot) do
		built[f.x .. ":" .. f.y] = true
	end
	local hx, hy = math.floor(t.view.w / 2) + 1, math.floor(t.view.h / 2) + 1
	local missing = 0
	for _, f in ipairs(foot) do
		if f.kind == "ground" or f.kind == "path" or f.kind == "gate" or f.kind == "marker" then
			ok(NP.onIsland(f, L), "walkable only inside the fence " .. f.x .. ":" .. f.y)
			for _, c in ipairs({{-hx, -hy}, {hx, -hy}, {-hx, hy}, {hx, hy}}) do
				if not built[(f.x + c[1]) .. ":" .. (f.y + c[2])] then
					missing = missing + 1
				end
			end
		end
	end
	eq(missing, 0, "every corner of every view is a built tile")
	-- the fence is closed: from the arrival only the pens, the gates and the path are reachable (no way onto the land)
	local kindAt0 = {}
	for _, f in ipairs(foot) do
		kindAt0[f.x .. ":" .. f.y] = f.kind
	end
	local walk = {ground = true, path = true, gate = true, marker = true}
	local seen0, queue, reached, landHit = {}, {L.rooms[1].arrival}, 0, false
	seen0[queue[1].x .. ":" .. queue[1].y] = true
	while #queue > 0 do
		local p = table.remove(queue)
		reached = reached + 1
		if not NP.onIsland(p, L) then
			landHit = true
		end
		for _, d in ipairs({{1, 0}, {-1, 0}, {0, 1}, {0, -1}}) do
			local q = {x = p.x + d[1], y = p.y + d[2], z = p.z}
			local k = q.x .. ":" .. q.y
			if not seen0[k] and walk[kindAt0[k]] then
				seen0[k] = true
				queue[#queue + 1] = q
			end
		end
	end
	ok(not landHit, "the land outside the fence cannot be reached")
	eq(reached, t.rooms * t.roomW * t.roomH + (t.rooms - 1), "every pen tile and gate is reachable from the arrival")
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
	ok(math.abs(L.skipStatue.x - L.rooms[1].arrival.x) <= 1 and math.abs(L.skipStatue.y - L.rooms[1].arrival.y) <= 1,
		"the skip statue stands beside the arrival tile")
	for i, r in ipairs(L.rooms) do
		eq(NP.roomOf(r.sign, L), i, "signpost in room " .. i)
		eq(kindAt[r.sign.x .. ":" .. r.sign.y], "ground", "signpost on grass, beside the path " .. i)
	end

	-- the island's look (NP.islandModel): grounds and items from cfg.tutorial.look, borders on the shore and the path
	local model = NP.islandModel(L)
	eq(#model.tiles, #foot, "one model tile per footprint tile")
	local look, known = t.look, {}
	local function knownList(list) for _, id in ipairs(list) do known[id] = true end end
	knownList(look.grass) knownList(look.water) knownList(look.trees) knownList(look.bushes) knownList(look.flowers)
	knownList(look.boat)
	for _, set in ipairs({look.shore, look.pathEdge, look.fence}) do
		for _, id in pairs(set) do known[id] = true end
	end
	for _, id in ipairs({look.path, look.dock, look.lamp, look.bollard, look.barrel, t.markerGround}) do
		known[id] = true
	end
	local counts = {shore = 0, edge = 0, tree = 0, lamp = 0, fence = 0, boat = 0}
	local isShore, isEdge, isTree, isBoat = {}, {}, {}, {}
	for _, id in pairs(look.shore) do isShore[id] = true end
	for _, id in pairs(look.pathEdge) do isEdge[id] = true end
	for _, id in ipairs(look.trees) do isTree[id] = true end
	for _, id in ipairs(look.boat) do isBoat[id] = true end
	local blocking = {}
	for _, id in ipairs(look.trees) do blocking[id] = true end
	for _, id in ipairs(look.bushes) do blocking[id] = true end
	blocking[look.lamp] = true
	for _, tile in ipairs(model.tiles) do
		ok(known[tile.ground], "ground from the config " .. tile.ground)
		for _, id in ipairs(tile.items) do
			ok(known[id], "item from the config " .. id)
			counts.shore = counts.shore + (isShore[id] and 1 or 0)
			counts.edge = counts.edge + (isEdge[id] and 1 or 0)
			counts.tree = counts.tree + (isTree[id] and 1 or 0)
			counts.lamp = counts.lamp + (id == look.lamp and 1 or 0)
			counts.boat = counts.boat + (isBoat[id] and 1 or 0)
			if blocking[id] then
				ok(tile.kind == "land", "trees, bushes and lamps only on the land " .. tile.x .. ":" .. tile.y)
			end
			if isShore[id] then
				ok(tile.kind == "land", "shore pieces on land tiles")
			end
			if isEdge[id] then
				ok(tile.kind == "path" or tile.kind == "gate" or tile.kind == "trail", "path edges on the path")
			end
		end
		if tile.kind == "fence" then
			counts.fence = counts.fence + 1
			eq(#tile.items, 1, "one fence piece per fence tile")
		end
		if tile.kind == "water" or tile.kind == "dock" then
			ok(tile.kind == "dock" or #tile.items == 0 or isBoat[tile.items[1]], "open water carries only the boat")
		end
	end
	ok(counts.shore > 50, "the shore has its border all round")
	ok(counts.edge > 20, "the path has grass edges")
	ok(counts.tree > 15, "trees on the land")
	eq(counts.lamp, 2 * (2 + t.rooms - 1) + 1, "lamps: north and south of every gate and both ends, one at the dock")
	eq(counts.boat, #look.boat, "the boat")
	-- the fence pieces by neighbours (measured on the live map)
	local f = look.fence
	eq(NP.fencePiece(false, true, true, false, f), f.post, "north-west post")
	eq(NP.fencePiece(true, false, false, true, f), f.joint, "south-east joint")
	eq(NP.fencePiece(true, true, false, false, f), f.vertical, "south-west corner")
	eq(NP.fencePiece(false, false, true, true, f), f.horizontal, "north-east corner")
	eq(NP.fencePiece(true, false, true, false, f), f.vertical, "north-south run")
	eq(NP.fencePiece(false, true, false, true, f), f.horizontal, "east-west run")
	eq(NP.fencePiece(true, false, false, false, f), f.southEnd, "the end above a gate")
	eq(NP.fencePiece(false, false, true, false, f), f.vertical, "the end below a gate")
	-- the same island in every run
	local again = NP.islandModel(L)
	local same = true
	for i, tile in ipairs(model.tiles) do
		local b = again.tiles[i]
		if b.ground ~= tile.ground or #b.items ~= #tile.items then
			same = false
		end
	end
	ok(same, "deterministic")
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

-- ------------------------------------------------------------------ the main city (server/README.md "Main city")
-- the temple services new characters need stand in their home town: every config that anchors something next to a
-- temple lists the main city first (or names it alone)
do
	local main = cfg.homeTown.id
	local function first(list, what)
		eq(list and list[1], main, what .. ": the main city first")
	end
	first(dofile("data/scripts/chaos/ascension_quest_config.lua").npc.townIds, "Ascendant Oracle")
	first(dofile("data/scripts/chaos/trials_config.lua").npc.townIds, "Keeper of Trials")
	first(dofile("data/scripts/chaos/tales_config.lua").npc.townIds, "Archivist Maelis")
	first(dofile("data/scripts/chaos/descent_config.lua").portal.townIds, "Descent portal")
	first(dofile("data/scripts/chaos/raid_config.lua").portal.townIds, "raid portal")
	eq(dofile("data/scripts/chaos/community_config.lua").brazier.townId, main, "the Great Brazier")
	eq(dofile("data/scripts/chaos/chronicle_config.lua").townId, main, "the Chronicle's capital")
	local hunts = dofile("data/scripts/chaos/hunt_teleports_config.lua")
	eq(hunts.room.town, main, "the hunt teleport room")
end

print(string.format("newplayer_test: %d checks, %d failures", checks, fails))
if fails > 0 then
	os.exit(1)
end
