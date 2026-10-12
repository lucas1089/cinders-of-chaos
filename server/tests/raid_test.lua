-- Run from the server/ folder: luajit tests/raid_test.lua (or lua5.3; CI runs both)
-- The Ashen Sepulchre, the weekly raid: raid_core.lua (pure: the lockout week and its reset, lockouts per character and
-- boss, loot eligibility and helpers, the saved raid of a week and its continuation, doors, the session clear, scaling,
-- the layout on the rift slot grid, cones and circles, the mechanic state machines: sunder / tank swap, soak, adds,
-- effigy stacks, the hex, loot and uniques, the seeded vendor, the journal), the wiring into the other systems (opcode,
-- storages, tables, grid, monsters, unique specs, leaderboard, Boss Spawns, achievements, cosmetic, buff bar, Party
-- Finder) and raid.lua against a mocked engine (open a raid with a party, the size rule, trash and doors, the pull and the
-- seal, the tank swap and the Crushing Verdict, a cleave, a caught lethal hit, a wipe, kills with personal loot and the
-- lockout, helpers without loot, the continuation of a saved raid, the week's reset, the vendor, a full clear for the
-- board and the guild trophy, the hex and the Font of Ash).
local n = 0
setmetatable(_G, {__index = function(t, k)
	if type(k) == "string" and k:match("^[A-Z_0-9]+$") then n = n + 1; rawset(t, k, n); return n end
end})
loadstring = loadstring or load

local failures, count = 0, 0
local function check(cond, label)
	count = count + 1
	if not cond then
		failures = failures + 1
		print("FAIL " .. label)
	end
end
local function eq(a, b, label)
	check(a == b, label .. " (" .. tostring(a) .. " ~= " .. tostring(b) .. ")")
end
local function readAll(path)
	local f = io.open(path, "rb")
	if not f then
		return nil
	end
	local s = f:read("*a")
	f:close()
	return s
end

dofile("data/scripts/chaos/chaos_constants.lua")
dofile("data/scripts/chaos/rift_core.lua")
dofile("data/scripts/chaos/uber_core.lua")
local cfg = dofile("data/scripts/chaos/raid_config.lua")
dofile("data/scripts/chaos/raid_core.lua")
local K = ChaosRaidCore

-- ================================================================== the config and its place
eq(#K.validate(cfg), 0, "the config is valid: " .. table.concat(K.validate(cfg), "; "))
eq(#cfg.bosses, 5, "five bosses")
eq(cfg.minPlayers, 5, "5 to ...")
eq(cfg.maxPlayers, 15, "... 15 players")
eq(ChaosOpcodes.raid, 213, "opcode 213")
local seen = {}
for k, v in pairs(ChaosOpcodes) do
	if v == 213 then
		seen[#seen + 1] = k
	end
end
eq(#seen, 1, "213 is the raid's alone")
for _, v in ipairs({1, 67, 73, 89, 91, 92, 99, 106, 107, 136, 181, 201, 202}) do
	check(v ~= 213, "not a reference server opcode " .. v)
end
eq(Chaos.storage.raid, cfg.storage, "the storage base in chaos_constants.lua")
check(cfg.storage >= 7100440 and cfg.storage + #cfg.bosses <= 7100449, "storages 7100440-7100449")
for k, t in pairs(cfg.tables) do
	check(t:match("^chaos_raid"), "table " .. k .. " is chaos_raid*")
end
local sql = readAll("sql/chaos_raid.sql") or ""
for _, t in pairs(cfg.tables) do
	check(sql:find("`" .. t .. "`", 1, true) ~= nil, "sql/chaos_raid.sql creates " .. t)
end
eq(cfg.resetDay, 2, "Monday, like the other weekly resets")
eq(cfg.resetHour, dofile("data/scripts/chaos/leaderboard_config.lua").resetHour, "the leaderboards' reset hour")

-- the grid: inside its documented box, clear of every other runtime area
local g = cfg.grid
local gx2, gy2 = g.origin.x + g.cols * g.spacing - 1, g.origin.y + g.rows * g.spacing - 1
eq(g.origin.x, 10400, "x from 10400"); eq(gx2, 10911, "to 10911"); eq(g.origin.y, 10000, "y from 10000"); eq(gy2, 10511, "to 10511")
local function box(x1, y1, x2, y2)
	return {x1 = x1, y1 = y1, x2 = x2, y2 = y2}
end
local function overlap(a, b)
	return a.x1 <= b.x2 and b.x1 <= a.x2 and a.y1 <= b.y2 and b.y1 <= a.y2
end
local mine = box(g.origin.x, g.origin.y, gx2, gy2)
local dc = dofile("data/scripts/chaos/descent_config.lua").grid
local rc = dofile("data/scripts/chaos/rift_config.lua").grid
local uc = dofile("data/scripts/chaos/uber_config.lua").grid
local others = {
	descent = box(dc.origin.x, dc.origin.y, dc.origin.x + dc.cols * dc.spacing - 1, dc.origin.y + dc.rows * dc.spacing - 1),
	rift = box(rc.origin.x, rc.origin.y, rc.origin.x + rc.cols * rc.spacing - 1, rc.origin.y + rc.rows * rc.spacing - 1),
	ascended = box(uc.origin.x, uc.origin.y, uc.origin.x + uc.cols * uc.spacing - 1, uc.origin.y + 2 * uc.spacing - 1),
	guild = box(9216, 9216, 9216 + 8 * 40 - 1, 9216 + 8 * 40 - 1),
	trials = box(9000, 9000, 9400, 9400),
	tower = box(2000, 2000, 2999, 2999), arena = box(6000, 6000, 6200, 6100), ascension = box(7000, 7000, 7100, 7100),
	worldboss = box(5000, 5000, 5100, 5100), siege = box(5100, 5000, 5600, 5300), island = box(4600, 4600, 4900, 4900)
}
for name, b in pairs(others) do
	check(not overlap(mine, b), "the raid grid is clear of " .. name)
end
for slot = 0, ChaosRiftCore.slotCount(cfg) - 1 do
	local L = K.layout(cfg, slot)
	local sq = box(g.origin.x + (slot % g.cols) * g.spacing, g.origin.y + math.floor(slot / g.cols) * g.spacing, 0, 0)
	sq.x2, sq.y2 = sq.x1 + g.spacing - 1, sq.y1 + g.spacing - 1
	local inside = true
	for _, list in ipairs({L.floorList, L.wallList}) do
		for _, t in ipairs(list) do
			if t.x < sq.x1 or t.x > sq.x2 or t.y < sq.y1 or t.y > sq.y2 then
				inside = false
			end
			if ChaosRiftCore.slotOfPos(cfg, t) ~= slot then
				inside = false
			end
		end
	end
	check(inside, "slot " .. slot .. ": every tile in its own square (rift slotOfPos agrees)")
end

-- ================================================================== the week
dofile("data/scripts/chaos/bounty_core.lua")
local monday = os.time({year = 2026, month = 10, day = 5, hour = 12})
eq(K.weekKey(monday, 2, 6), 20261005, "Monday noon")
eq(K.weekKey(os.time({year = 2026, month = 10, day = 5, hour = 5}), 2, 6), 20260928, "Monday 05:00 is still last week")
eq(K.weekKey(os.time({year = 2026, month = 10, day = 11, hour = 23}), 2, 6), 20261005, "Sunday night")
eq(K.weekKey(os.time({year = 2026, month = 10, day = 12, hour = 6, min = 0, sec = 1}), 2, 6), 20261012, "after the reset")
for d = 0, 13 do
	for _, h in ipairs({0, 5, 6, 7, 23}) do
		local t = os.time({year = 2026, month = 12, day = 24 + d, hour = h})
		eq(K.weekKey(t, 2, 6), ChaosBounty.week(t, {rollHour = 6}), "the same week as the bounty board, day " .. d .. " " .. h)
	end
end
eq(K.weekKey(os.time({year = 2026, month = 10, day = 10, hour = 12}), 7, 20), 20261003, "a Saturday 20:00 reset")
eq(K.nextReset(monday, 2, 6), os.time({year = 2026, month = 10, day = 12, hour = 6, min = 0, sec = 0}), "next reset")
eq(K.weekStart(20261005, 6), os.time({year = 2026, month = 10, day = 5, hour = 6, min = 0, sec = 0}), "week start")
check(K.cfgReset(cfg, monday) > monday, "the reset is ahead")

-- ================================================================== lockouts and eligibility
local rows = {{week = 20261005, boss = "ulthar"}, {week = 20260928, boss = "morwen"}}
local set = K.lockSet(rows, 20261005)
check(set.ulthar and not set.morwen, "only this week's rows lock")
check(not K.eligible(set, "ulthar"), "a looted boss is locked")
check(K.eligible(set, "morwen"), "last week's kill does not lock this week")
check(K.eligible(K.lockSet(rows, 20261012), "ulthar"), "across the reset everything is free again")
local present = {{guid = 1, locked = {ulthar = true}}, {guid = 2}, {guid = 3, locked = {}}}
local split = K.splitKill("ulthar", present)
eq(#split.eligible, 2, "two may loot"); eq(#split.helpers, 1, "one helps")
eq(split.helpers[1], 1, "the one who looted already helps")
check(present[2].locked.ulthar, "the eligible are locked after the kill")
local again = K.splitKill("ulthar", present)
eq(#again.eligible, 0, "a second kill the same week gives nobody loot")
local view = K.lockView(cfg, {ulthar = true, sovereign = true}, monday)
eq(view.looted, 2, "looted count"); eq(view.total, 5, "of five"); eq(#view.bosses, 5, "a row per boss")
eq(view.bosses[1].l, true, "row looted"); eq(view.bosses[2].l, nil, "row free")
eq(view.reset, K.cfgReset(cfg, monday) - monday, "seconds to the reset")
eq(K.lockStorage(cfg, {ulthar = true}, "ulthar", monday), K.cfgReset(cfg, monday), "storage: the reset while locked")
eq(K.lockStorage(cfg, {}, "ulthar", monday), 0, "storage: 0 when free")

-- ================================================================== the saved raid
check(K.hasBit(5, 1) and not K.hasBit(5, 2) and K.hasBit(5, 3), "bits")
eq(K.setBit(0, 3), 4, "set bit"); eq(K.setBit(4, 3), 4, "set twice"); eq(K.bitCount(31, 5), 5, "count")
local inst = K.newInstance(7, 20261005, 101, "Ash")
eq(K.nextBoss(cfg, inst), 1, "starts at the first boss")
inst.killed = K.setBit(inst.killed, 1)
inst.killed = K.setBit(inst.killed, 2)
eq(K.nextBoss(cfg, inst), 3, "continues at the third")
check(K.canContinue(cfg, inst, 101, 20261005), "the leader continues")
local ok, why = K.canContinue(cfg, inst, 202, 20261005)
check(not ok and why == "member", "a stranger may not")
inst.members[202] = true
check(K.canContinue(cfg, inst, 202, 20261005), "a member may")
ok, why = K.canContinue(cfg, inst, 101, 20261012)
check(not ok and why == "expired", "a raid ends with its week")
local done = K.newInstance(8, 20261005, 101, "Ash")
done.killed = 31
ok, why = K.canContinue(cfg, done, 101, 20261005)
check(not ok and why == "cleared", "a cleared raid cannot be continued")
local list = K.continuable(cfg, {inst, done, K.newInstance(9, 20261005, 101, "Ash")}, 101, 20261005)
eq(#list, 2, "two to continue"); eq(list[1].id, 9, "newest first")
-- doors
local fresh = K.newInstance(1, 1, 1, "x")
check(K.doorOpen(fresh, 1, "west"), "the hall's door is open")
check(not K.doorOpen(fresh, 1, "east"), "the first room waits for its trash")
check(not K.doorOpen(fresh, 2, "west"), "the second corridor waits for the first boss")
fresh.trash = K.setBit(fresh.trash, 1)
check(K.doorOpen(fresh, 1, "east"), "trash cleared: the first room opens")
check(not K.doorOpen(fresh, 1, "east", 1), "the fight seals it")
fresh.killed = K.setBit(fresh.killed, 1)
check(K.doorOpen(fresh, 1, "east", 1) and K.doorOpen(fresh, 2, "west"), "the kill opens the way on")
check(not K.doorOpen(fresh, 2, "east"), "the next room waits for its trash")
check(K.sessionClear(cfg, {startKilled = 0, kills = 5, firstPull = 1}), "a clear in one sitting counts")
check(not K.sessionClear(cfg, {startKilled = 2, kills = 3, firstPull = 1}), "a continued raid does not count")
local iv = K.instanceView(cfg, inst)
eq(iv.done, 2, "view: slain"); eq(iv.next, "The Marrow Colossus", "view: next"); eq(iv.members, 1, "view: members")

-- ================================================================== scaling and balance
eq(K.healthMult(cfg, 5), 1, "health x1 at five"); check(math.abs(K.healthMult(cfg, 15) - 2.8) < 1e-9, "x2.8 at fifteen")
eq(K.healthMult(cfg, 3), 1, "never below the five-player health")
eq(K.packSize(cfg, 5), 4, "packs of 4 at five"); eq(K.packSize(cfg, 15), 8, "8 at fifteen")
eq(K.waveCount(cfg.mechanics.adds, 5), 2, "adds at five"); eq(K.waveCount(cfg.mechanics.adds, 15), 4, "adds at fifteen")
eq(K.waveCount(cfg.mechanics.totem, 15), 2, "effigies at fifteen")
local function xmlOf(name)
	local p = io.popen and nil
	for _, f in ipairs({"gravewarden_ulthar", "morwen_the_ash_sister", "the_marrow_colossus", "vhoss_the_hexmaw",
			"varkhul_the_ashen_sovereign", "cinder_acolyte", "hex_effigy", "sepulchre_ghoul", "bone_lancer", "hex_cultist",
			"cinder_hound", "marrow_knight", "ashen_reaper"}) do
		local s = readAll("data/monster/monsters/chaos/raid/" .. f .. ".xml") or ""
		if s:match('<monster%s+name="([^"]+)"') == name then
			return s
		end
	end
	return nil
end
for _, b in ipairs(cfg.bosses) do
	local s = xmlOf(b.name)
	check(s ~= nil, "the XML of " .. b.name)
	local hp = tonumber(s and s:match('<health now="(%d+)"') or 0)
	for _, players in ipairs({5, 10, 15}) do
		local t = K.killTime(cfg, hp, players)
		check(t > 240 and t < b.enrageAt, string.format("%s at %d: %.0f s, before the enrage (%d)", b.name, players, t, b.enrageAt))
	end
	check(s and s:find('isboss="1"', 1, true) ~= nil, b.name .. " is a boss")
end
local looks = {}
for _, b in ipairs(cfg.bosses) do
	local s = xmlOf(b.name) or ""
	looks[#looks + 1] = tonumber(s:match('<look type="(%d+)"'))
end
-- the bosses' looks: their own donor-library looks 2127..2131 (picks.csv family "raid"), no other monster file uses them
local function listXml(dir)
	local out = {}
	local p = io.popen and io.popen('find "' .. dir .. '" -name "*.xml" 2>/dev/null')
	if p then
		for line in p:lines() do
			out[#out + 1] = line
		end
		p:close()
	end
	return out
end
local files = listXml("data/monster/monsters/chaos")
if #files > 0 then
	for i, look in ipairs(looks) do
		local users = 0
		for _, f in ipairs(files) do
			local s = readAll(f) or ""
			if tonumber(s:match('<look type="(%d+)"')) == look then
				users = users + 1
			end
		end
		eq(users, 1, "look " .. tostring(look) .. " of " .. cfg.bosses[i].name .. " is its alone")
		check(look == 2126 + i, "look " .. tostring(look) .. " is the raid look of picks.csv (" .. (2126 + i) .. ")")
	end
end
for _, b in ipairs(cfg.bosses) do
	for _, name in ipairs({b.add, b.totem}) do
		check(xmlOf(name) ~= nil, "the XML of " .. name)
	end
end
for _, s in ipairs(cfg.trash) do
	for _, pack in ipairs(s.packs) do
		for _, name in ipairs(pack) do
			check(xmlOf(name) ~= nil, "the XML of " .. name)
		end
	end
end
eq(K.trashTier(cfg, 1), "rare", "tier roll 1"); eq(K.trashTier(cfg, 25), "magic", "tier roll 25"); eq(K.trashTier(cfg, 99), "normal", "tier roll 99")

-- ================================================================== geometry
local L = K.layout(cfg, 0)
eq(#L.rooms, 5, "five rooms"); eq(#L.corridors, 5, "five corridors")
for i = 1, 5 do
	local r = L.rooms[i].rect
	eq(r.x2 - r.x1 + 1, 23, "room " .. i .. " is 23 wide")
	eq(K.where(L, L.rooms[i].center), "room", "the centre is in the room")
	local _, wi = K.where(L, L.corridors[i].packAt[1])
	eq(wi, i, "the pack spot is in corridor " .. i)
	check(K.inRoom(L, i, L.rooms[i].bossSpawn), "the boss spawn is in its room")
	if i > 1 then
		check(L.rooms[i].rect.x1 > L.rooms[i - 1].rect.x2, "rooms run west to east")
	end
end
eq(K.where(L, L.start), "hall", "players land in the hall"); eq(K.where(L, L.fallen), "hall", "the fallen too")
eq(K.where(L, {x = 1, y = 1, z = 7}), nil, "outside")
local bc = L.rooms[1].center
local front = K.cone(L, 1, bc, {x = bc.x + 3, y = bc.y, z = 7}, 7, 3)
local fset = K.tileSet(front)
check(fset[K.key(bc.x + 2, bc.y)] and not fset[K.key(bc.x - 2, bc.y)], "the cleave is in front")
local back = K.tileSet(K.cone(L, 1, bc, {x = bc.x + 3, y = bc.y, z = 7}, 6, 3, true))
check(back[K.key(bc.x - 2, bc.y)] and not back[K.key(bc.x + 2, bc.y)], "the sweep is behind")
check(not fset[K.key(bc.x, bc.y)], "never the boss's own tile")
local circ = K.circles(L, 1, {{x = bc.x, y = bc.y}}, 1)
eq(#circ, 9, "a circle of radius 1 is 3 x 3")

-- ================================================================== mechanics
-- sunder
local st = K.newSunder()
for i = 1, 3 do
	eq(K.sunderHit(st, cfg, 1, i * 1000), i, "stack " .. i)
end
eq(K.sunderDecide(st, cfg, 1, {}), nil, "below swapAt: nothing")
K.sunderHit(st, cfg, 1, 4000)
local d = K.sunderDecide(st, cfg, 1, {{id = 1, dist = 1}, {id = 2, dist = 1}, {id = 3, dist = 4}})
check(d and d.action == "swap" and d.to == 2, "a fresh tank in melee takes over")
d = K.sunderDecide(st, cfg, 1, {{id = 3, dist = 4}})
check(d and d.action == "verdict", "nobody in melee: the verdict")
K.sunderHit(st, cfg, 2, 4000)
K.sunderHit(st, cfg, 2, 4000)
d = K.sunderDecide(st, cfg, 1, {{id = 2, dist = 1}, {id = 5, dist = 1}})
check(d.to == 5, "the one with the fewest stacks")
check(math.abs(K.sunderMult(cfg, 4) - 1.6) < 1e-9, "4 stacks: +60% damage taken")
check(K.verdictShare(cfg, 4) > cfg.mechanics.sunder.verdictShare, "the verdict grows with the stacks")
K.sunderExpire(st, cfg, 4000 + cfg.mechanics.sunder.expireMs)
eq(K.sunderStacks(st, 1), 0, "stacks fall off")
for i = 1, 20 do
	K.sunderHit(st, cfg, 9, 50000 + i)
end
eq(K.sunderStacks(st, 9), cfg.mechanics.sunder.maxStacks, "at most maxStacks")
-- soak
eq(K.soakNeed(cfg, 5), 3, "3 to soak at five"); eq(K.soakNeed(cfg, 15), 5, "5 at fifteen")
eq(K.soakCount(cfg, 5), 1, "one circle at five"); eq(K.soakCount(cfg, 15), 3, "three at fifteen")
local each_, over = K.soakResolve(cfg, 3, 3)
check(math.abs(each_ - 0.5) < 1e-9 and over == 0, "three soak: half each, no overflow")
each_, over = K.soakResolve(cfg, 6, 3)
check(math.abs(each_ - 0.25) < 1e-9, "more soakers, less each")
each_, over = K.soakResolve(cfg, 1, 3)
check(each_ == 1.5 and over == cfg.mechanics.soak.overflowShare, "one alone: the whole hit and the overflow")
each_, over = K.soakResolve(cfg, 0, 3)
check(each_ == 0 and over > cfg.mechanics.soak.overflowShare, "nobody: a bigger overflow on the room")
local centers = K.soakCenters(cfg, {{x = 1, y = 1, z = 7}, {x = 2, y = 2, z = 7}, {x = 3, y = 3, z = 7}},
	function(a) return a end)
eq(#centers, 1, "one circle for three players")
-- adds
eq(K.addReduction(cfg, 1), 15, "one add: 15% less"); eq(K.addReduction(cfg, 9), 60, "capped")
eq(K.addHeal(cfg, 2, 1000000), 20000, "heal per add")
-- effigies and the Hexed stacks
local hx = K.newHexed()
local hits = K.hexTick(hx, cfg, 2, {1, 2})
eq(hx.stacks[1], 2, "two effigies: two stacks"); check(math.abs(hits[1] - 0.04) < 1e-9, "2% per stack")
K.hexTick(hx, cfg, 20, {1})
eq(hx.stacks[1], cfg.mechanics.totem.maxStacks, "capped stacks")
hits = K.hexTick(hx, cfg, 0, {1, 2})
eq(hx.stacks[1], cfg.mechanics.totem.maxStacks - 1, "no effigy: the stacks fall"); eq(hits[1], nil, "and do not hurt")
check(K.totemExpired(cfg, 0, cfg.mechanics.totem.lifeMs) and not K.totemExpired(cfg, 0, 1000), "the effigy's timer")
-- the hex
local targets = K.hexTargets(cfg, {11, 12, 13, 14, 15, 16}, 10, function(a) return a end)
eq(#targets, 3, "1 + 1 per 5 raiders"); eq(targets[1], 11, "the order of rand")
eq(#K.hexResolve(cfg, true, {x = 0, y = 0}, {{id = 1, pos = {x = 0, y = 0}}}), 0, "cleansed: nothing")
local hit = K.hexResolve(cfg, false, {x = 0, y = 0}, {{id = 1, pos = {x = 0, y = 0}}, {id = 2, pos = {x = 2, y = 0}},
	{id = 3, pos = {x = 3, y = 0}}})
eq(#hit, 2, "the burst reaches radius 2")

-- ================================================================== loot
local sp = K.spoils(cfg, cfg.bosses[1])
eq(sp.gold, cfg.loot.boss.gold, "boss gold"); eq(sp.gearRolls, 2, "two gear rolls"); eq(sp.marks, 20, "marks")
local fp = K.spoils(cfg, cfg.bosses[5])
eq(fp.gearRolls, 3, "the final boss: three rolls"); check(fp.marks > sp.marks, "more marks")
eq(#K.uniquesOf(cfg, "sovereign"), 5, "the final boss can give every raid unique")
eq(#K.uniquesOf(cfg, "ulthar"), 1, "a boss its own")
eq(K.rollUnique(cfg, cfg.bosses[1], 151, function(a) return a end), nil, "the roll misses")
eq(K.rollUnique(cfg, cfg.bosses[1], 150, function(a) return a end).name, "Gravewarden's Verdict", "the roll hits")
for _ = 1, 50 do
	local lv = K.gearLevel(cfg, math.random)
	check(lv >= 120 and lv <= 130, "gear item level 120-130")
end
for _, b in ipairs(cfg.bosses) do
	for _, id in ipairs(b.gear) do
		check(id >= 29861 and id <= 29890, b.key .. ": gear " .. id .. " is late-game boss gear")
	end
end
dofile("data/lib/chaos_unique_specs.lua")
dofile("data/lib/chaos_unique_items.lua")
local ids = {}
for _, u in ipairs(cfg.uniques) do
	local spec = ChaosUniqueSpecs[u.id]
	check(spec ~= nil, "a unique spec for " .. u.name)
	eq(spec and spec.name, u.name, "its name")
	check(ChaosUniqueById == nil or ChaosUniqueById[u.id] == nil, "never a monster drop: " .. u.name)
	check(not ids[u.id], "one base item per unique")
	ids[u.id] = true
	check(spec and spec.description:find("level 800", 1, true) ~= nil, "it asks for the raid level")
end

-- ================================================================== the vendor
local w1 = K.vendorStock(cfg, 20261005)
eq(#w1, cfg.vendor.slots + #cfg.vendor.always, "slots filled")
eq(w1[1], "v_upheaval", "the orb bundles always"); eq(table.concat(w1), table.concat(K.vendorStock(cfg, 20261005)),
	"the same stock for everyone all week")
local differ = false
for wk = 20261012, 20261012 + 7 * 30, 7 do
	if table.concat(K.vendorStock(cfg, wk)) ~= table.concat(w1) then
		differ = true
	end
end
check(differ, "the stock changes with the weeks")
local dup = {}
for _, k in ipairs(w1) do
	check(not dup[k], "no offer twice: " .. k)
	dup[k] = true
	check(K.inStock(cfg, 20261005, k), "in stock " .. k)
end
check(K.canBuy(K.offer(cfg, "v_fate"), 0, 60), "60 marks buy the fate bundle")
check(not K.canBuy(K.offer(cfg, "v_fate"), 2, 999), "the weekly limit")
check(not K.canBuy(K.offer(cfg, "v_fate"), 0, 59), "too few marks")
dofile("data/lib/chaos_item_mods.lua")
dofile("data/scripts/chaos/factions_core.lua")
local M = ChaosItemMods
local gearN = 0
for _, o in ipairs(cfg.vendor.pool) do
	if o.kind == "gear" then
		gearN = gearN + 1
		local bad = ChaosFactionsCore.gearProblems(o, M, cfg.vendor.gearLimits)
		eq(#bad, 0, o.key .. " follows chaos_item_mods.lua: " .. table.concat(bad, "; "))
		check(o.level < M.config.itemLevel.worldBoss, o.key .. " below world boss drops")
	else
		check(#o.items > 0, o.key .. " has items")
	end
end
check(gearN >= cfg.vendor.slots, "enough gear for the slots")

-- ================================================================== journal and HUD
local j = K.journal(cfg)
eq(#j, 5, "a journal page per boss")
for _, page in ipairs(j) do
	check(#page.mech >= 2, page.n .. ": its mechanics")
	check(page.intro ~= "" and page.roles ~= "", page.n .. ": intro and roles")
end
check(j[1].mech[1]:find("4 stacks", 1, true) ~= nil, "the sunder text carries its numbers")
eq(#j[5].mech, 7, "the final boss uses seven mechanics")
check(j[5].final, "the last page is the final boss")
local hud = K.hud(cfg, {inst = inst, bossIdx = 3, boss = cfg.bosses[3], state = "fight", hp = 40, phase = 2, toEnrage = 90,
	players = 10, alerts = {"x"}})
eq(hud.done, 2, "hud: slain"); eq(hud.phaseName, "Shattering", "hud: phase name"); eq(hud.total, 5, "hud: total")

-- ================================================================== wiring
local lb = dofile("data/scripts/chaos/leaderboard_config.lua")
local board
for _, bd in ipairs(lb.boards) do
	if bd.key == cfg.board then
		board = bd
	end
end
check(board and board.mode == "min" and board.format == "time", "the weekly fastest-clear board")
local bs = dofile("data/scripts/chaos/bossspawns_config.lua")
local cat
for _, c in ipairs(bs.categories) do
	if c.key == "sepulchre" then
		cat = c
	end
end
check(cat ~= nil, "the Boss Spawns category")
for i, b in ipairs(cfg.bosses) do
	local row
	for _, e in ipairs(bs.bosses or {}) do
		if e.key == "raid_" .. b.key then
			row = e
		end
	end
	check(row and row.category == "sepulchre" and row.monster == b.name, "Boss Spawns row of " .. b.name)
	eq(row and row.rule.type, "ondemand", "on demand")
	eq(row and row.rule.cooldown, cfg.storage + i, "its cooldown is the lockout storage")
end
local ach = dofile("data/scripts/chaos/achievements_data.lua")
local stats, byId = {}, {}
for _, a in ipairs(ach.list) do
	if a.stat then
		stats[a.stat] = true
	end
	byId[a.id] = a
end
for _, b in ipairs(cfg.bosses) do
	check(stats["raid_" .. b.key], "an achievement for " .. b.name)
end
for _, s in ipairs({"raid_kills", "raid_clears", "raid_flawless", "raid_speed"}) do
	check(stats[s], "an achievement reads " .. s)
end
local cos = dofile("data/scripts/chaos/cosmetics_config.lua")
local fx
for _, c in ipairs(cos.cosmetics) do
	if c.achievement == "raid_sovereign" then
		fx = c
	end
end
check(fx and byId[fx.achievement] ~= nil and fx.kind == "killfx", "the final boss's cosmetic")
local pf = dofile("data/scripts/chaos/party_finder_config.lua")
local raidAct
for _, a in ipairs(pf.activities) do
	if a.key == "raid" then
		raidAct = a
	end
end
check(raidAct and raidAct.fallback and raidAct.fallback[1] == cfg.name, "the Party Finder names the raid")
dofile("data/lib/chaos_buffs.lua")
check(ChaosBuffs.byKey.raid_debuff and ChaosBuffs.byKey.raid_debuff.kind == "debuff", "the buff registry entry")
check(ChaosBuffs.sources.raid ~= nil, "the buff source")
local function pngSize(path)
	local s = readAll(path) or ""
	if #s < 24 then
		return nil
	end
	local function u32(i)
		local b1, b2, b3, b4 = s:byte(i, i + 3)
		return ((b1 * 256 + b2) * 256 + b3) * 256 + b4
	end
	return u32(17), u32(21)
end
for _, icon in ipairs({"raid_debuff", "raid_sunder", "raid_hexed", "raid_hex"}) do
	local wv, hv = pngSize("../client/overlay/data/images/game/buffs/" .. icon .. ".png")
	check(wv == 26 and hv == 26, "icon " .. icon .. " at 26 x 26")
end

-- ================================================================== raid.lua against a mocked engine
local T = 0 -- ms
local BASE = os.time({year = 2026, month = 10, day = 6, hour = 12}) -- a Tuesday: week 20261005
local shift = 0
os.mtime = function() return T end
local realTime = os.time
os.time = function(t) if t then return realTime(t) end return BASE + shift + math.floor(T / 1000) end
local queue = {}
function addEvent(fn, ms, ...)
	queue[#queue + 1] = {at = T + (ms or 0), fn = fn, args = {...}, n = select("#", ...)}
	return #queue
end
local unpack = table.unpack or unpack
local function runTo(t)
	while true do
		local best, bi
		for i, q in ipairs(queue) do
			if q.at <= t and (not best or q.at < best.at) then
				best, bi = q, i
			end
		end
		if not best then
			break
		end
		table.remove(queue, bi)
		T = math.max(T, best.at)
		best.fn(unpack(best.args, 1, best.n))
	end
	T = t
end

local tiles = {}
local function tkey(p)
	return p.x .. "," .. p.y .. "," .. p.z
end
local Pos = {}
Pos.__index = Pos
function Position(x, y, z)
	if type(x) == "table" then
		x, y, z = x.x, x.y, x.z
	end
	return setmetatable({x = x, y = y, z = z}, Pos)
end
function Pos:sendMagicEffect() end
function Pos:getDistance(o)
	return math.max(math.abs(self.x - o.x), math.abs(self.y - o.y))
end
local creatures = {}
local nextCid = 1000
local Item = {}
Item.__index = Item
local function newItem(id, count)
	return setmetatable({id = id, count = count or 1, attrs = {}, custom = {}}, Item)
end
function Item:getId() return self.id end
function Item:getCount() return self.count end
function Item:setActionId(a) self.aid = a end
function Item:getActionId() return self.aid or 0 end
function Item:setAttribute(k, v) self.attrs[k] = v end
function Item:setCustomAttribute(k, v) self.custom[k] = v end
function Item:getPosition() return self.pos end
function Item:remove()
	self.removed = true
	return true
end
function ItemType(id)
	return {getId = function() return id end, getName = function() return "item " .. id end,
		getPluralName = function() return "" end, getClientId = function() return id end}
end
local Tl = {}
Tl.__index = Tl
function Tile(p)
	return tiles[tkey(p)]
end
Game = {}
function Game.createTile(p)
	local t = setmetatable({pos = Position(p), items = {}, flags = {}}, Tl)
	tiles[tkey(p)] = t
	return t
end
function Tl:getGround() return self.ground end
function Tl:getItemById(id)
	for _, it in ipairs(self.items) do
		if it.id == id and not it.removed then
			return it
		end
	end
end
function Tl:getItems()
	local out = {}
	for _, it in ipairs(self.items) do
		if not it.removed then
			out[#out + 1] = it
		end
	end
	return out
end
function Tl:getCreatures()
	local out = {}
	for _, c in pairs(creatures) do
		if tkey(c.pos) == tkey(self.pos) then
			out[#out + 1] = c
		end
	end
	return out
end
function Tl:getTopCreature() return self:getCreatures()[1] end
function Tl:hasFlag(f) return self.flags[f] end
function Tl:hasProperty() return false end
function Game.createItem(id, count, pos)
	local it = newItem(id, count)
	if pos then
		local t = tiles[tkey(pos)]
		if t then
			it.pos = Position(pos)
			if id == cfg.groundId and not t.ground then
				t.ground = it
			else
				t.items[#t.items + 1] = it
			end
		end
	end
	return it
end
function Game.broadcastMessage(text) Game.lastBroadcast = text end
local registered = {}
local function eventObj(name)
	return {name = name, register = function(self) registered[self.name or name] = self end, type = function() end,
		aid = function(self, ...) self.aids = {...} end, separator = function() end}
end
function CreatureEvent(name) return eventObj(name) end
function GlobalEvent(name) return eventObj(name) end
local actions, moves = {}, {}
function Action()
	local a = eventObj("action")
	a.register = function(self) actions[#actions + 1] = self end
	return a
end
function MoveEvent()
	local m = eventObj("move")
	m.register = function(self) moves[#moves + 1] = self end
	return m
end
function TalkAction(w) return eventObj(w) end
local Cond = {}
Cond.__index = Cond
function Condition(ctype, cid)
	return setmetatable({ctype = ctype, cid = cid, params = {}}, Cond)
end
function Cond:setParameter(k, v) self.params[k] = v end
function Cond:addDamage() end

local C = {}
C.__index = C
local function newCreature(o)
	nextCid = nextCid + 1
	o.id = nextCid
	o.events = {}
	o.texts = {}
	o.conds = {}
	creatures[o.id] = setmetatable(o, C)
	return o
end
function C:getId() return self.id end
function C:getName() return self.name end
function C:getPosition() return Position(self.pos) end
function C:teleportTo(p) self.pos = Position(p) end
function C:getHealth() return self.hp end
function C:getMaxHealth() return self.maxhp end
function C:setMaxHealth(v) self.maxhp = v end
function C:setHealth(v) self.hp = v end
function C:addHealth(a, b)
	if type(a) == "string" then
		a = b
	end
	self.hp = math.max(0, math.min(self.maxhp, self.hp + a))
end
function C:registerEvent(e) self.events[e] = true end
function C:unregisterEvent(e) self.events[e] = nil end
function C:isPlayer() return self.player == true end
function C:isMonster() return self.player ~= true end
function C:getMaster() return nil end
function C:say(t) self.said = t end
function C:getTarget() return self.target end
function C:selectTarget(c) self.target = c return true end
function C:remove() creatures[self.id] = nil end
function C:sendTextMessage(_, t) self.texts[#self.texts + 1] = t end
function C:sendCancelMessage(t) self.texts[#self.texts + 1] = "CANCEL " .. t end
function C:getStorageValue(k) return self.storage[k] or -1 end
function C:setStorageValue(k, v) self.storage[k] = v end
function C:getLevel() return self.level end
function C:getGuid() return self.guid end
function C:getParty() return self.party end
function C:isPzLocked() return false end
function C:hasCondition() return false end
function C:addCondition(c) self.conds[c.ctype .. ":" .. tostring(c.params[CONDITION_PARAM_SUBID] or 0)] = c end
function C:getCondition(ctype, _, sub) return self.conds[ctype .. ":" .. tostring(sub or 0)] end
function C:removeCondition(ctype, _, sub) self.conds[ctype .. ":" .. tostring(sub or 0)] = nil end
function C:getTown() return {getTemplePosition = function() return Position(1000, 1000, 7) end} end
function C:getBankBalance() return self.bank or 0 end
function C:setBankBalance(v) self.bank = v end
function C:getInbox() return {addItemEx = function() end, addItem = function() end} end
function C:getEnergyShield() return 0 end
function C:getGroup() return {getId = function() return self.group or 1 end} end
function C:getItemCount(id)
	local c = 0
	for _, it in ipairs(self.bag) do
		if it.id == id then
			c = c + it.count
		end
	end
	return c
end
function C:addItem(id, count)
	local it = newItem(id, count or 1)
	self.bag[#self.bag + 1] = it
	return it
end
function C:addItemEx(it)
	self.bag[#self.bag + 1] = it
	return RETURNVALUE_NOERROR
end
function C:getGuild() return self.guild end
function Player(x)
	local c = type(x) == "table" and x or creatures[x]
	return c and c.player and c or nil
end
function Monster(id)
	local c = creatures[id]
	return c and not c.player and c or nil
end
function Creature(id) return creatures[id] end
local made = {}
function Game.createMonster(name, pos)
	local s = xmlOf(name)
	if not s then
		return nil
	end
	local hp = tonumber(s:match('<health now="(%d+)"'))
	local m = newCreature({name = name, pos = Position(pos), hp = hp, maxhp = hp})
	made[#made + 1] = m
	return m
end
function doTargetCombat(attackerId, target, ctype, min, max, effect, origin)
	local pd, pt, sd, st = min, ctype, 0, COMBAT_NONE
	if target.events.ChaosRaidPlayerHit then
		pd, pt, sd, st = registered.ChaosRaidPlayerHit.onHealthChange(target, creatures[attackerId], pd, pt, sd, st, origin)
	end
	target.hp = math.max(0, target.hp + pd + sd)
	target.lastHit = -(pd + sd)
end
-- a melee hit of a monster on a player, through the player's health event (as the engine does)
local function melee(m, p, dmg)
	doTargetCombat(m.id, p, COMBAT_PHYSICALDAMAGE, -dmg, -dmg, 0, ORIGIN_MELEE)
end

json = {encode = function(t) return t end, decode = function(t) return t end}
Chaos.sendChunked = function(p, opcode, payload)
	p.sent = p.sent or {}
	p.sent[#p.sent + 1] = payload
	return true
end
Chaos.decode = function(b) return b end
Chaos.isMultiClient = function() return false end
Chaos.giveItem = function(player, id, count)
	player:addItem(id, count)
	return count
end
db = {query = function() end, escapeString = function(s) return "'" .. tostring(s) .. "'" end}
ChaosAchievements = {got = {}, progress = function(p, k, a)
	ChaosAchievements.got[p.name .. ":" .. k] = (ChaosAchievements.got[p.name .. ":" .. k] or 0) + a
end}
ChaosLeaderboard = {rec = {}, record = function(b, who, v) ChaosLeaderboard.rec[#ChaosLeaderboard.rec + 1] = {b, who.name, v} end}
ChaosGuild = {stats = {}, xp = {}, guildOf = function(p) return p.guild and p.guild.id or nil end,
	addStat = function(gid, stat, v) ChaosGuild.stats[gid .. ":" .. stat] = (ChaosGuild.stats[gid .. ":" .. stat] or 0) + v end,
	addXp = function(gid, guid, source, amount) ChaosGuild.xp[gid] = (ChaosGuild.xp[gid] or 0) + amount end}

dofile("data/scripts/chaos/raid.lua")
local X = ChaosRaid
-- the in-memory store (the SQL one is raid.lua's store.*)
local mem = {locks = {}, players = {}, inst = {}, members = {}, buys = {}, nextId = 0}
X.store = {
	lockRows = function(guid, week)
		local out = {}
		for _, r in ipairs(mem.locks) do
			if r.guid == guid and r.week == week then
				out[#out + 1] = {week = r.week, boss = r.boss}
			end
		end
		return out
	end,
	addLock = function(guid, week, boss, id) mem.locks[#mem.locks + 1] = {guid = guid, week = week, boss = boss, inst = id} end,
	player = function(guid)
		local r = mem.players[guid] or {marks = 0, kills = 0, clears = 0, best = 0}
		return {marks = r.marks, kills = r.kills, clears = r.clears, best = r.best}
	end,
	savePlayer = function(guid, row) mem.players[guid] = {marks = row.marks, kills = row.kills, clears = row.clears, best = row.best} end,
	spendMarks = function(guid, amount)
		local r = mem.players[guid]
		if not r or r.marks < amount then
			return false
		end
		r.marks = r.marks - amount
		return true
	end,
	newInstance = function(week, guid, name)
		mem.nextId = mem.nextId + 1
		mem.inst[mem.nextId] = {id = mem.nextId, week = week, leader = guid, leaderName = name, killed = 0, trash = 0}
		return mem.nextId
	end,
	instance = function(id)
		local r = mem.inst[id]
		if not r then
			return nil
		end
		local m = {}
		for g in pairs(mem.members[id] or {}) do
			m[g] = true
		end
		return {id = r.id, week = r.week, leader = r.leader, leaderName = r.leaderName, killed = r.killed, trash = r.trash,
			cleared = r.cleared, members = m}
	end,
	instancesOf = function(guid, week)
		local out = {}
		for id, r in pairs(mem.inst) do
			if r.week == week and (r.leader == guid or (mem.members[id] or {})[guid]) then
				out[#out + 1] = X.store.instance(id)
			end
		end
		table.sort(out, function(a, b) return a.id > b.id end)
		return out
	end,
	saveInstance = function(inst)
		local r = mem.inst[inst.id]
		r.killed, r.trash, r.cleared = inst.killed, inst.trash, inst.cleared
	end,
	addMember = function(id, guid)
		mem.members[id] = mem.members[id] or {}
		mem.members[id][guid] = true
	end,
	purchases = function(guid, week)
		return (mem.buys[guid .. ":" .. week]) or {}
	end,
	addPurchase = function(guid, week, offer)
		local k = guid .. ":" .. week
		mem.buys[k] = mem.buys[k] or {}
		mem.buys[k][offer] = (mem.buys[k][offer] or 0) + 1
	end
}
check(registered.ChaosRaidPlayerHit and registered.ChaosRaidBossDeath and registered.ChaosRaidMonsterDeath,
	"the events are registered")
eq(#moves, 1, "the portal / exit move event"); eq(#actions, 1, "the Font of Ash action")

-- the town and the raiders
for x = 95, 115 do
	Game.createTile({x = x, y = 100, z = 7}).flags[TILESTATE_PROTECTIONZONE] = true
end
local function newPlayer(name, guid, x)
	return newCreature({player = true, name = name, guid = guid, level = 900, pos = Position(x, 100, 7), hp = 20000,
		maxhp = 20000, storage = {}, bag = {}})
end
local raiders = {}
for i = 1, 6 do
	raiders[i] = newPlayer("R" .. i, 100 + i, 99 + i)
end
local lead = raiders[1]
local function partyOf(list)
	local party = {getLeader = function() return list[1] end, getMembers = function()
		local out = {}
		for i = 2, #list do
			out[#out + 1] = list[i]
		end
		return out
	end}
	for _, p in ipairs(list) do
		p.party = party
	end
end
partyOf({raiders[1], raiders[2], raiders[3], raiders[4]})
local okOpen, whyOpen = X.open(lead)
check(not okOpen and whyOpen:find("party of 5", 1, true) ~= nil, "four are too few: " .. tostring(whyOpen))
partyOf({raiders[1], raiders[2], raiders[3], raiders[4], raiders[5]})
okOpen, whyOpen = X.open(lead)
check(okOpen, "five open the raid: " .. tostring(whyOpen))
local run = X.runOf[lead.id]
check(run ~= nil, "the run")
for i = 1, 5 do
	check(X.runOf[raiders[i].id] == run, "R" .. i .. " is inside")
	eq(K.where(run.L, raiders[i].pos), "hall", "R" .. i .. " lands in the hall")
	eq(raiders[i].storage[cfg.storage], 1, "the crash marker")
end
check(X.runOf[raiders[6].id] == nil, "the sixth was not in the party")
eq(run.inst.id, 1, "raid #1"); eq(run.inst.week, 20261005, "of this week")
local function bars(i, side)
	local n = 0
	for _, f in ipairs(run.L.corridors[i][side]) do
		local t = Tile(f)
		if t and t:getItemById(cfg.doorId) then
			n = n + 1
		end
	end
	return n
end
eq(bars(1, "west"), 0, "the hall's door is open")
eq(bars(1, "east"), 5, "the first room is barred")
eq(bars(2, "west"), 5, "the second corridor is barred")
local trash = {}
for mid, e in pairs(run.mons) do
	if e.kind == "trash" then
		trash[#trash + 1] = Monster(mid)
		eq(e.idx, 1, "only the first corridor's trash is up")
	end
end
eq(#trash, 2 * K.packSize(cfg, 5), "two packs of four")
eq(run.trashLeft[1], #trash, "counted")
for i = 1, 5 do
	check(run.bossId[i] ~= nil, "boss " .. i .. " waits in its room")
end
check(Tile(run.L.exit):getItemById(cfg.objects.exit).aid == cfg.aid.exit, "the exit portal")
local fonts = 0
for i = 1, 5 do
	for _, f in ipairs(run.L.rooms[i].fonts) do
		local t = Tile(f)
		if t and t:getItemById(cfg.objects.font) then
			fonts = fonts + 1
		end
	end
end
eq(fonts, 8, "the Fonts of Ash of the two rooms with hexes")
local hudMsg = lead.sent[#lead.sent]
eq(hudMsg.action, "hud", "the HUD"); eq(hudMsg.data.boss, "Gravewarden Ulthar", "the next boss on the HUD")

-- the trash dies: the door opens
for _, m in ipairs(trash) do
	registered.ChaosRaidMonsterDeath.onDeath(m)
	m:remove()
end
runTo(T + 300)
check(K.hasBit(run.inst.trash, 1), "the first corridor is cleared")
eq(mem.inst[1].trash, 1, "and saved")
eq(bars(1, "east"), 0, "the door opens")

-- the pull: a raider near the boss; the others wait in the corridor and come in with it
local room = run.L.rooms[1]
local boss = Monster(run.bossId[1])
lead.pos = Position(room.center.x, room.center.y, 7)
for i = 2, 5 do
	raiders[i].pos = Position(run.L.corridors[1].rect.x1 + i, run.L.corridors[1].rect.y1 + 1, 7)
end
runTo(T + 300)
check(run.fight ~= nil and run.fight.idx == 1, "the pull")
eq(bars(1, "east"), 5, "the room seals")
for i = 2, 5 do
	check(K.inRoom(run.L, 1, raiders[i].pos), "R" .. i .. " is drawn in")
end
eq(boss.maxhp, 4000000, "five raiders: the XML health")

-- the tank swap: four melee hits on the tank with a fresh tank beside the boss
local tank, off = lead, raiders[2]
boss.target = tank
boss.pos = Position(room.center.x + 1, room.center.y, 7)
tank.pos = Position(room.center.x, room.center.y, 7)
off.pos = Position(room.center.x + 2, room.center.y, 7)
for i = 3, 5 do
	raiders[i].pos = Position(room.rect.x1 + 2, room.rect.y1 + i, 7)
end
for k = 1, 4 do
	tank.hp = tank.maxhp
	melee(boss, tank, 1000)
	runTo(T + 10)
	if k == 2 then
		eq(tank.lastHit, math.floor(1000 * K.sunderMult(cfg, 1)), "the second hit is 15% harder")
	end
end
eq(K.sunderStacks(run.fight.sunder, tank.id), 4, "four stacks of Sundered")
eq(boss.target, off, "the boss turns to the fresh tank")
local items = X.buffItems(tank, "debuff")
check(items and items[1].key == "raid_sunder" and items[1].stacks == 4, "the buff bar shows the stacks")
-- the off tank takes four too, the first tank walks away: the verdict
for _ = 1, 4 do
	off.hp = off.maxhp
	melee(boss, off, 1000)
	runTo(T + 10)
end
tank.pos = Position(room.rect.x1 + 1, room.rect.y1 + 1, 7)
check(run.fight.verdictAt ~= nil, "nobody fresh in melee: the verdict is coming")
off.hp = off.maxhp
runTo(T + cfg.mechanics.sunder.warnMs + 50)
check(off.hp < off.maxhp * 0.5, "the Crushing Verdict lands: " .. off.hp)

-- a cleave: the raider in front of the boss is hit, the target and the one behind are not
local f = run.fight
f.next.cleave = T
boss.target = off
off.pos = Position(boss.pos.x + 1, boss.pos.y, 7)
local front_, behind = raiders[3], raiders[4]
front_.pos = Position(boss.pos.x + 3, boss.pos.y, 7)
behind.pos = Position(boss.pos.x - 3, boss.pos.y, 7)
for _, p in ipairs(raiders) do
	p.hp = p.maxhp
end
-- the one in front is a Hollow Vessel (archetypes.lua percentBase via Chaos.percentBase): health + maximum energy shield
ChaosArchetypes = {percentBase = function(p) return p.vessel and (p.maxhp + p.vessel) or p.maxhp end}
front_.vessel = 5000
runTo(T + 300)
runTo(T + cfg.telegraph.warnMs + 100)
check(front_.hp < front_.maxhp, "the cleave hits the one in front")
eq(behind.hp, behind.maxhp, "not the one behind")
eq(off.hp, off.maxhp, "not the tank")
eq(front_.lastHit, K.shareDamage(front_.maxhp + 5000, cfg.mechanics.cleave.share), "the cleave on a Hollow Vessel counts its shield")
ChaosArchetypes, front_.vessel = nil, nil

-- a lethal hit is caught: the hall, healed, out of the fight
behind.hp = 100
melee(boss, behind, 5000)
runTo(T + 10)
eq(K.where(run.L, behind.pos), "hall", "the fallen land in the hall")
eq(behind.hp, behind.maxhp, "healed")
check(run.players[behind.id].fallen ~= nil, "out of the fight")
check(X.runOf[behind.id] == run, "still in the raid")

-- a wipe: nobody left standing in the room
for i = 1, 5 do
	raiders[i].pos = Position(run.L.start.x, run.L.start.y + i - 3, 7)
end
boss.hp = boss.maxhp - 1000
runTo(T + cfg.wipeSeconds * 1000 + 600)
check(run.fight == nil, "the wipe ends the fight")
eq(boss.hp, boss.maxhp, "the boss resets")
eq(bars(1, "east"), 0, "the room opens again")
check(run.players[behind.id].fallen == nil, "everyone may fight again")

-- the kill: personal loot and the lockout for everyone present
lead.pos = Position(room.center.x, room.center.y, 7)
runTo(T + 300)
check(run.fight ~= nil, "pulled again")
for i = 2, 5 do
	raiders[i].pos = Position(room.center.x - 2, room.center.y + i - 3, 7)
end
local bank = lead.bank or 0
registered.ChaosRaidBossDeath.onDeath(boss)
boss:remove()
runTo(T + 300)
check(K.hasBit(run.inst.killed, 1), "boss 1 slain")
eq(mem.inst[1].killed, 1, "the progress is saved")
eq(#mem.locks, 5, "five lockouts")
eq((lead.bank or 0) - bank, cfg.loot.boss.gold, "gold to the bank")
eq(mem.players[lead.guid].marks, cfg.loot.boss.marks, "Sepulchre Marks")
eq(lead.storage[cfg.storage + 1], K.cfgReset(cfg, os.time()), "the Boss Spawns cooldown is the reset")
eq(ChaosAchievements.got["R1:raid_ulthar"], 1, "the achievement stat")
check(lead.sent[#lead.sent].action == "hud" and lead.sent[#lead.sent].data.done == 1, "the HUD counts the kill")
local lootMsg
for _, m in ipairs(lead.sent) do
	if m.action == "loot" then
		lootMsg = m
	end
end
check(lootMsg and lootMsg.data.eligible, "the loot call-out")
local gear = 0
for _, it in ipairs(lead.bag) do
	for _, gid in ipairs(cfg.bosses[1].gear) do
		if it.id == gid then
			gear = gear + 1
		end
	end
end
eq(gear, cfg.loot.boss.gearRolls, "two gear rolls")
eq(bars(2, "west"), 0, "the way on opens")
eq(bars(2, "east"), 5, "the second room waits for its trash")
local trash2 = 0
for _, e in pairs(run.mons) do
	if e.kind == "trash" and e.idx == 2 then
		trash2 = trash2 + 1
	end
end
eq(trash2, 2 * K.packSize(cfg, 5), "the second corridor's trash wakes")

-- the instance closes (a restart); the group continues another day of the same week
X.interruptAll()
check(X.runOf[lead.id] == nil and lead.storage[cfg.storage] == 0, "everyone out, the marker cleared")
eq(lead.pos.x, 1000, "to the temple")
shift = 2 * 86400 -- two days later, same week
for i = 1, 5 do
	raiders[i].pos = Position(99 + i, 100, 7)
end
okOpen, whyOpen = X.open(raiders[3], 1) -- a member, not the opener
check(okOpen, "a member continues raid #1: " .. tostring(whyOpen))
run = X.runOf[raiders[3].id]
eq(run.inst.id, 1, "the same raid")
check(run.bossId[1] == nil and run.bossId[2] ~= nil, "the slain boss stays dead, the second waits")
eq(K.nextBoss(cfg, run.inst), 2, "next: Morwen")
eq(run.session.startKilled, 1, "a continued session")
local tr2 = 0
for _, e in pairs(run.mons) do
	if e.kind == "trash" then
		tr2 = tr2 + 1
		eq(e.idx, 2, "only the second corridor's trash")
	end
end
check(tr2 > 0, "trash again")
-- the info window: the saved raid, the lockouts, the vendor
X.sendInfo(lead)
local inf = lead.sent[#lead.sent]
eq(inf.action, "info", "the window")
eq(inf.data.lock.looted, 1, "one boss looted this week")
eq(#inf.data.saved, 1, "one saved raid"); check(inf.data.saved[1].open, "and it is open")
eq(#inf.data.vendor.stock, cfg.vendor.slots + #cfg.vendor.always, "the vendor's stock")

-- joining an open raid: a stranger may not, a member may (from the window, while it is open)
local stranger = raiders[6]
stranger.party = nil
local okJoin, whyJoin = X.join(stranger, 1)
check(not okJoin and whyJoin:find("members", 1, true) ~= nil, "a stranger cannot join: " .. tostring(whyJoin))
X.join(stranger, 99)
local member = raiders[2]
registered.ChaosRaidExtended.onExtendedOpcode(member, 213, {action = "leave", data = {}})
check(X.runOf[member.id] == nil, "a raider leaves through the window")
eq(member.sent[#member.sent].action, "info", "and sees the window again")
member.pos = Position(101, 100, 7)
okJoin, whyJoin = X.join(member, 1)
check(okJoin and X.runOf[member.id] == run, "a member joins the open raid: " .. tostring(whyJoin))

-- a second raid the same week: the first boss gives the same characters nothing
X.interruptAll()
for i = 1, 5 do
	raiders[i].pos = Position(99 + i, 100, 7)
end
okOpen = X.open(lead)
check(okOpen, "a new raid of the same week")
run = X.runOf[lead.id]
eq(run.inst.id, 2, "raid #2")
check(run.bossId[1] ~= nil, "a fresh raid has its first boss")
bank = lead.bank
for i = 1, 5 do
	raiders[i].pos = Position(run.L.rooms[1].center.x - 1, run.L.rooms[1].center.y + i - 3, 7)
end
run.inst.trash = K.setBit(run.inst.trash, 1)
X.syncDoors(run)
runTo(T + 300)
check(run.fight ~= nil, "pulled")
registered.ChaosRaidBossDeath.onDeath(Monster(run.bossId[1]))
runTo(T + 300)
eq(lead.bank, bank, "no gold: looted this week already")
eq(#mem.locks, 5, "no new lockout")
check(K.hasBit(mem.inst[2].killed, 1), "but the kill counts for raid #2")
check(lead.texts[#lead.texts]:find("helped", 1, true) ~= nil or lead.texts[#lead.texts - 1]:find("helped", 1, true) ~= nil,
	"told they helped")

-- the reset: a new week, everything free again; last week's raid cannot be continued
X.interruptAll()
shift = 8 * 86400
X.locks = {}
for i = 1, 5 do
	raiders[i].pos = Position(99 + i, 100, 7)
end
okOpen, whyOpen = X.open(lead, 1)
check(not okOpen and whyOpen:find("earlier week", 1, true) ~= nil, "last week's raid is gone: " .. tostring(whyOpen))
check(K.eligible(X.lockSet(lead.guid), "ulthar"), "the lockout is free in the new week")
eq(K.cfgWeek(cfg, os.time()), 20261012, "the new week")

-- the vendor: marks for the fate bundle, the weekly limit
mem.players[lead.guid].marks = 200
X.prow[lead.guid] = nil
local okBuy, text = X.buy(lead, "v_fate")
check(okBuy, "bought: " .. tostring(text))
eq(mem.players[lead.guid].marks, 140, "60 marks spent")
eq(lead:getItemCount(29857), 3 + cfg.loot.boss.orbs[2].count, "three Orbs of Fate more")
X.buy(lead, "v_fate")
okBuy, text = X.buy(lead, "v_fate")
check(not okBuy and text:find("as often", 1, true) ~= nil, "the weekly limit: " .. tostring(text))
okBuy = X.buy(lead, "v_nothing")
check(not okBuy, "not for sale")

-- a full clear in one sitting: the board, the clears, the guild trophy, the broadcast
local guild = {id = 77}
raiders[1].guild, raiders[2].guild = guild, guild
for i = 1, 5 do
	raiders[i].pos = Position(99 + i, 100, 7)
end
okOpen = X.open(lead)
run = X.runOf[lead.id]
local t0 = T
for i = 1, 5 do
	run.inst.trash = K.setBit(run.inst.trash, i)
	X.syncDoors(run)
	for k = 1, 5 do
		raiders[k].pos = Position(run.L.rooms[i].center.x - 1, run.L.rooms[i].center.y + k - 3, 7)
	end
	runTo(T + 300)
	check(run.fight and run.fight.idx == i, "boss " .. i .. " pulled")
	for _ = 1, 60 do -- a minute of the fight; the healers keep everyone up
		for k = 1, 5 do
			raiders[k].hp = raiders[k].maxhp
		end
		runTo(T + 1000)
	end
	check(run.fight and run.fight.idx == i, "boss " .. i .. ": nobody fell for a minute")
	if run.fight then
		registered.ChaosRaidBossDeath.onDeath(Monster(run.bossId[i]))
	end
	runTo(T + 300)
	check(K.hasBit(run.inst.killed, i), "boss " .. i .. " slain")
end
check(run.inst.cleared and mem.inst[run.inst.id].cleared, "the raid is cleared and saved")
local rec = ChaosLeaderboard.rec[#ChaosLeaderboard.rec]
check(rec and rec[1] == "raid_clear" and rec[3] >= 300 and rec[3] <= (T - t0) / 1000 + 1, "the fastest-clear board gets the time")
eq(ChaosGuild.stats["77:raidClears"], 1, "one trophy for the guild, once")
eq(ChaosGuild.xp[77], cfg.trophyGxp, "its guild XP")
eq(ChaosAchievements.got["R1:raid_sovereign"], 1, "the final achievement (the cosmetic)")
eq(ChaosAchievements.got["R1:raid_clears"], 1, "a clear")
check(Game.lastBroadcast and Game.lastBroadcast:find("Varkhul", 1, true) ~= nil, "the broadcast")
eq(mem.players[lead.guid].clears, 1, "the record")

-- the hex and the Font of Ash: the cleansed raider is spared, the other bursts on its neighbours
X.interruptAll()
for i = 1, 5 do
	raiders[i].pos = Position(99 + i, 100, 7)
end
X.open(lead)
run = X.runOf[lead.id]
run.inst.killed = 7
run.inst.trash = 15
X.syncDoors(run)
for k = 1, 5 do
	raiders[k].pos = Position(run.L.rooms[4].center.x + k, run.L.rooms[4].center.y, 7)
	raiders[k].hp = raiders[k].maxhp
end
runTo(T + 300)
-- the run was opened before the kills were set: spawn the fourth boss's fight by hand
if not run.fight then
	run.bossId[4] = run.bossId[4] or nil
end
check(run.fight and run.fight.idx == 4, "the Hexmaw is pulled")
f = run.fight
f.next = {}
f.nextHex = T + 999999
local cleansed, burst = raiders[1], raiders[4]
cleansed:addCondition(Condition(CONDITION_CURSED, CONDITIONID_COMBAT))
cleansed.conds = {}
local hexCond = Condition(CONDITION_CURSED, CONDITIONID_COMBAT)
hexCond:setParameter(CONDITION_PARAM_SUBID, cfg.mechanics.hex.subId)
cleansed:addCondition(hexCond)
burst:addCondition(hexCond)
f.hexes[cleansed.id] = T + 1000
f.hexes[burst.id] = T + 1000
local fontItem = Tile(run.L.rooms[4].fonts[1]):getItemById(cfg.objects.font)
cleansed.pos = Position(run.L.rooms[4].fonts[1].x + 1, run.L.rooms[4].fonts[1].y, 7)
actions[1].onUse(cleansed, fontItem)
check(cleansed:getCondition(CONDITION_CURSED, CONDITIONID_COMBAT, cfg.mechanics.hex.subId) == nil, "the Font of Ash lifts the hex")
local neighbour = raiders[5]
neighbour.pos = Position(burst.pos.x + 1, burst.pos.y, 7)
local far = raiders[2]
far.pos = Position(burst.pos.x - 6, burst.pos.y, 7)
runTo(T + 1300)
eq(cleansed.hp, cleansed.maxhp, "the cleansed one is spared")
check(burst.hp < burst.maxhp and neighbour.hp < neighbour.maxhp, "the hex bursts on the hexed and the neighbour")
eq(far.hp, far.maxhp, "not on the far one")
-- effigies: a stack per living effigy on everyone in the room
f.nextHex = T
runTo(T + 300)
X.interruptAll()

-- ================================================================== instance limits (instance_limits.lua)
-- the session's time limit with its warnings (progress kept), the idle close after idleMinutes, the cap with the wait
-- and the waiting line, the staff list and close
do
	dofile("data/scripts/chaos/instance_limits.lua")
	local byId = Player
	Player = function(x) -- the engine also finds a player by name
		if type(x) == "string" then
			for _, c in pairs(creatures) do
				if c.player and c.name == x then
					return c
				end
			end
			return nil
		end
		return byId(x)
	end
	local function told(p, text)
		for _, t in ipairs(p.texts) do
			if t:find(text, 1, true) then
				return true
			end
		end
		return false
	end
	eq(cfg.sessionMinutes, 150, "limits: a session lasts 150 minutes")
	eq(cfg.idleMinutes, 5, "limits: an empty raid closes after 5 minutes")
	for i = 1, 5 do
		raiders[i].pos = Position(99 + i, 100, 7)
		raiders[i].texts = {}
	end
	check(X.open(lead), "limits: open")
	run = X.runOf[lead.id]
	eq(run.endsAt, os.time() + cfg.sessionMinutes * 60, "limits: the session's end")
	runTo(T + 300)
	run.endsAt = os.time() + 600
	runTo(T + 300)
	check(told(raiders[2], "The Ashen Sepulchre: 10 minutes left"), "limits: the 10 minute warning to every raider")
	-- the cap: one raid at most; a second party is refused with the wait and waits in line
	ChaosRaidConfig.limits.maxRuns = 1
	local other = newPlayer("Other", 300, 110)
	local okO, whyO = X.open(other, nil, true)
	check(not okO and whyO:find("All wings of the Sepulchre are busy. Try again in ~10 min. You are 1st in line", 1, true),
		"limits: busy with the wait: " .. tostring(whyO))
	ChaosRaidConfig.limits.maxRuns = 4
	-- staff list
	local found
	for _, r in ipairs(ChaosInstanceLimits.runs()) do
		if r.key == "raid" then found = r end
	end
	check(found and found.players == 5 and found.left == 600, "limits: /instances lists the raid")
	-- time up: everyone back where they came from, the slot closes, the progress stays
	run.inst.killed = 1
	X.store.saveInstance(run.inst)
	run.endsAt = os.time() + 1
	runTo(T + 1500)
	check(X.runOf[lead.id] == nil and next(X.runs) == nil, "limits: time up closes the raid")
	eq(lead.pos.x, 100, "limits: back where the raider came from")
	check(told(lead, "Time is up: The Ashen Sepulchre closes. Your progress is saved for the week"), "limits: told")
	eq(mem.inst[run.inst.id].killed, 1, "limits: the progress is kept")
	check(told(other, "A place in The Ashen Sepulchre is free now"), "limits: the first in line is told")
	-- idle: everyone leaves; the empty raid closes after idleMinutes
	check(X.open(lead), "limits: open again")
	run = X.runOf[lead.id]
	for i = 1, 5 do
		raiders[i].pos = Position(99 + i, 100, 7)
	end
	runTo(T + 300)
	check(next(run.players) == nil and X.runs[run.slot] == run, "limits: empty, still open")
	runTo(T + (cfg.idleMinutes * 60 - 2) * 1000)
	check(X.runs[run.slot] == run, "limits: open until the idle time")
	runTo(T + 3000)
	check(X.runs[run.slot] == nil, "limits: closed after idleMinutes")
	-- staff close
	check(X.open(lead), "limits: open for the staff close")
	run = X.runOf[lead.id]
	local okC = Chaos.instances.raid.close(run.inst.id)
	check(okC and next(X.runs) == nil, "limits: staff close")
	eq(lead.pos.x, 1000, "limits: a staff close sends to the temple")
end

print(string.format("raid_test: %d checks, %d failures", count, failures))
if failures > 0 then
	os.exit(1)
end
