-- The Ashen Sepulchre (the weekly raid): the pure part (no engine calls), shared by raid.lua and tests/raid_test.lua.
-- Numbers: raid_config.lua. Overview: server/README.md "The Ashen Sepulchre (weekly raid)".
--   week       the lockout week (reset day and hour), its start and the next reset
--   bosses     lookup, the phase machine (health thresholds, each phase once and in order), the clock
--   scaling    boss / trash / add health by raid size, pack sizes, the balance model
--   lockout    per character, week and boss: who may loot a kill, the lockout state of the window
--   instance   the saved raid of a week (bosses killed, trash cleared, members): continue, next boss, doors, the record
--   geometry   the slot layout (hall, corridors, rooms, doors) on the rift slot grid, cones, circles
--   mechanics  sunder (tank swap), soak (split damage), adds (priority), totems and hex stacks, the hex (dispel), marks
--   loot       one eligible player's spoils of a boss, the unique pick
--   vendor     the week's stock (seeded), offer lookup
--   texts      the journal (mechanics with their numbers), the HUD payload, validation
-- Every random number comes from a `rand(a, b)` argument (integer in [a, b]). Lua 5.1 / LuaJIT and Lua 5.3.

ChaosRaidCore = ChaosRaidCore or {}
local K = ChaosRaidCore

local floor, abs, sqrt = math.floor, math.abs, math.sqrt

local function key(x, y)
	return x .. "," .. y
end
K.key = key

-- ===================================================================== week
-- the lockout week of t: the YYYYMMDD of the day the week started (resetDay at resetHour, local time)
function K.weekKey(t, day, hour)
	day, hour = day or 2, hour or 6
	local d = os.date("*t", t - hour * 3600)
	local back = (d.wday - day + 7) % 7
	local s = os.date("*t", os.time({year = d.year, month = d.month, day = d.day - back, hour = 12}))
	return s.year * 10000 + s.month * 100 + s.day
end

function K.weekStart(week, hour)
	local y, m, d = floor(week / 10000), floor(week / 100) % 100, week % 100
	return os.time({year = y, month = m, day = d, hour = hour or 6, min = 0, sec = 0})
end

-- the time of the next reset after t
function K.nextReset(t, day, hour)
	local w = K.weekKey(t, day, hour)
	local y, m, d = floor(w / 10000), floor(w / 100) % 100, w % 100
	return os.time({year = y, month = m, day = d + 7, hour = hour or 6, min = 0, sec = 0})
end

function K.cfgWeek(cfg, t)
	return K.weekKey(t, cfg.resetDay, cfg.resetHour)
end

function K.cfgReset(cfg, t)
	return K.nextReset(t, cfg.resetDay, cfg.resetHour)
end

-- ===================================================================== bosses
function K.boss(cfg, k)
	for i, b in ipairs(cfg.bosses) do
		if b.key == k or i == k then
			return b, i
		end
	end
	return nil
end

function K.bossOfName(cfg, name)
	name = tostring(name or ""):lower()
	for i, b in ipairs(cfg.bosses) do
		if b.name:lower() == name then
			return b, i
		end
	end
	return nil
end

function K.phaseIndex(boss, frac)
	local idx = 1
	for i, p in ipairs(boss.phases) do
		if frac <= p.at then
			idx = i
		end
	end
	return idx
end

-- moves fight.phase forward (never back); returns the phases entered, in order
function K.advancePhase(fight, boss, frac)
	local want = K.phaseIndex(boss, frac)
	local entered = {}
	local cur = fight.phase or 0
	while cur < want do
		cur = cur + 1
		entered[#entered + 1] = cur
	end
	fight.phase = math.max(fight.phase or 0, want)
	return entered
end

-- the mechanics of a phase as a set
function K.mechSet(boss, phase)
	local p = boss.phases[phase or 1] or boss.phases[1]
	local set = {}
	for _, m in ipairs(p.mech or {}) do
		set[m] = true
	end
	return set
end

-- every mechanic a boss uses in any phase, in first-seen order
function K.bossMechs(boss)
	local seen, out = {}, {}
	for _, p in ipairs(boss.phases) do
		for _, m in ipairs(p.mech or {}) do
			if not seen[m] then
				seen[m] = true
				out[#out + 1] = m
			end
		end
	end
	return out
end

-- seconds since the pull -> enraged, seconds left to the enrage
function K.clock(boss, elapsed)
	elapsed = math.max(0, elapsed or 0)
	return elapsed >= boss.enrageAt, math.max(0, boss.enrageAt - elapsed)
end

-- ms between two casts of a mechanic (faster when enraged)
function K.every(cfg, mech, enraged)
	local m = cfg.mechanics[mech] or {}
	local every = m.every or 15000
	if enraged then
		every = floor(every * (cfg.enrage.everyMult or 1))
	end
	return math.max(2000, every)
end

function K.telegraphTiming(cfg, enraged)
	local t = cfg.telegraph
	-- never under 1.5 s (server/README.md "Boss mechanics", the fairness rules): enraged 60% of warnMs, at least 1500
	local warn = enraged and math.max(1500, floor(t.warnMs * 0.6)) or t.warnMs
	local marks = {0}
	if t.turnMs and t.turnMs < warn then
		marks[#marks + 1] = t.turnMs
	end
	return {marks = marks, hitMs = warn}
end

function K.shareDamage(maxHealth, share)
	return math.max(1, floor((tonumber(maxHealth) or 0) * (share or 0) + 0.5))
end

function K.damageMult(cfg, enraged)
	return enraged and cfg.enrage.damageMult or 1
end

-- ===================================================================== scaling
local function extra(cfg, players)
	return math.max(0, (math.max(1, tonumber(players) or 1)) - cfg.minPlayers)
end

function K.healthMult(cfg, players)
	return 1 + cfg.healthPerPlayer * extra(cfg, players)
end

function K.trashMult(cfg, players)
	return 1 + cfg.trashPerPlayer * extra(cfg, players)
end

function K.addMult(cfg, players)
	return 1 + cfg.addPerPlayer * extra(cfg, players)
end

-- monsters of one trash pack
function K.packSize(cfg, players)
	local p = cfg.trashPack
	return math.min(p.max, p.base + floor(math.max(1, players or 1) / p.perPlayers))
end

-- the tier of one trash monster: "normal" | "magic" | "rare" | "legendary" from a roll 1..100
function K.trashTier(cfg, roll)
	local t = cfg.trashTiers
	local acc = 0
	for _, name in ipairs({"legendary", "rare", "magic"}) do
		acc = acc + (t[name] or 0)
		if roll <= acc then
			return name
		end
	end
	return "normal"
end

-- adds or totems of one wave
function K.waveCount(m, players)
	if not m then
		return 0
	end
	return math.max(0, (m.base or 0) + floor(math.max(1, players or 1) / math.max(1, m.perPlayers or 1000)))
end

-- the balance model: seconds to kill `health` (the XML's) with `players` (a fifth of them support at supportShare)
function K.killTime(cfg, health, players)
	local m = cfg.model
	players = math.max(1, players or 1)
	local support = floor(players / m.supportEvery)
	local dps = (players - support) * m.refDps + support * m.refDps * m.supportShare
	return health * K.healthMult(cfg, players) / (dps * m.uptime)
end

-- ===================================================================== lockout
-- rows = {{week, boss}, ...} of one character (the chaos_raid_lockouts rows); the set of boss keys locked in `week`
function K.lockSet(rows, week)
	local set = {}
	for _, r in ipairs(rows or {}) do
		if tonumber(r.week) == week then
			set[r.boss] = true
		end
	end
	return set
end

-- may this character loot `boss` this week? (true, or false and why)
function K.eligible(lockSet, bossKey)
	if ChaosBetaMode and ChaosBetaMode.lifted("raid_lockout") then
		return true -- beta test mode: loot from every kill
	end
	if lockSet and lockSet[bossKey] then
		return false, "locked"
	end
	return true
end

-- one kill: for every present player {guid, locked = set} the loot decision; returns {eligible = {guid...}, helpers =
-- {guid...}} and marks the eligible ones locked (the caller writes the rows)
function K.splitKill(bossKey, present)
	local out = {eligible = {}, helpers = {}}
	for _, p in ipairs(present) do
		p.locked = p.locked or {}
		if K.eligible(p.locked, bossKey) then
			p.locked[bossKey] = true
			out.eligible[#out.eligible + 1] = p.guid
		else
			out.helpers[#out.helpers + 1] = p.guid
		end
	end
	return out
end

-- the lockout view of the window: one entry per boss {key, name, looted}, the count and the seconds to the reset
function K.lockView(cfg, lockSet, now)
	local list, n = {}, 0
	for _, b in ipairs(cfg.bosses) do
		local looted = lockSet[b.key] == true
		if looted then
			n = n + 1
		end
		list[#list + 1] = {k = b.key, n = b.name, l = looted or nil}
	end
	return {bosses = list, looted = n, total = #cfg.bosses, reset = math.max(0, K.cfgReset(cfg, now) - now)}
end

-- the storage value of a boss's lockout (Boss Spawns cooldown): the reset time while locked, 0 when free
function K.lockStorage(cfg, lockSet, bossKey, now)
	return lockSet[bossKey] and K.cfgReset(cfg, now) or 0
end

-- ===================================================================== instance
-- the killed bosses as a number: bit i-1 for boss i (no bit library: plain arithmetic)
function K.hasBit(mask, i)
	return floor((tonumber(mask) or 0) / 2 ^ (i - 1)) % 2 == 1
end

function K.setBit(mask, i)
	mask = tonumber(mask) or 0
	if K.hasBit(mask, i) then
		return mask
	end
	return mask + 2 ^ (i - 1)
end

function K.bitCount(mask, n)
	local c = 0
	for i = 1, n do
		if K.hasBit(mask, i) then
			c = c + 1
		end
	end
	return c
end

function K.newInstance(id, week, leaderGuid, leaderName)
	return {id = id, week = week, leader = leaderGuid, leaderName = leaderName, killed = 0, trash = 0, members = {},
		cleared = false}
end

-- the next boss to fight (index), or nil when every boss is slain
function K.nextBoss(cfg, inst)
	for i = 1, #cfg.bosses do
		if not K.hasBit(inst.killed, i) then
			return i
		end
	end
	return nil
end

function K.isCleared(cfg, inst)
	return K.nextBoss(cfg, inst) == nil
end

-- may `guid` continue this saved raid now? (true or false and why)
function K.canContinue(cfg, inst, guid, week)
	if not inst then
		return false, "none"
	end
	if inst.week ~= week then
		return false, "expired"
	end
	if K.isCleared(cfg, inst) then
		return false, "cleared"
	end
	if inst.leader ~= guid and not inst.members[guid] then
		return false, "member"
	end
	return true
end

-- the saved raids a character may continue: instances = list, the newest first
function K.continuable(cfg, instances, guid, week)
	local out = {}
	for _, inst in ipairs(instances or {}) do
		if K.canContinue(cfg, inst, guid, week) then
			out[#out + 1] = inst
		end
	end
	table.sort(out, function(a, b)
		return a.id > b.id
	end)
	return out
end

-- the doors: corridor i (in front of boss room i) has a west door (out of the hall / room i - 1) and an east door
-- (into room i). West: open once boss i - 1 is slain (always for i = 1). East: open once its trash is cleared and the
-- west is open, closed while boss i fights (sealed), open after its kill.
function K.doorOpen(inst, i, side, fighting)
	if side == "west" then
		return i == 1 or K.hasBit(inst.killed, i - 1)
	end
	if K.hasBit(inst.killed, i) then
		return true
	end
	if fighting == i then
		return false
	end
	return K.doorOpen(inst, i, "west") and K.hasBit(inst.trash, i)
end

-- a fresh session counts for the clear board when it started with no boss slain and slew them all
function K.sessionClear(cfg, session)
	return session ~= nil and session.startKilled == 0 and session.kills == #cfg.bosses and session.firstPull ~= nil
end

-- the instance summary of the window: {id, week, killed = {bool...}, next, leader, members}
function K.instanceView(cfg, inst)
	local killed = {}
	for i = 1, #cfg.bosses do
		killed[i] = K.hasBit(inst.killed, i)
	end
	local nb = K.nextBoss(cfg, inst)
	local n = 0
	for _ in pairs(inst.members or {}) do
		n = n + 1
	end
	return {id = inst.id, killed = killed, done = K.bitCount(inst.killed, #cfg.bosses), next = nb and cfg.bosses[nb].name or nil,
		leader = inst.leaderName, members = n, cleared = nb == nil}
end

-- ===================================================================== geometry
local function rectList(r, z, out, set)
	for y = r.y1, r.y2 do
		for x = r.x1, r.x2 do
			local k = key(x, y)
			if not set[k] then
				local t = {x = x, y = y, z = z}
				set[k] = t
				out[#out + 1] = t
			end
		end
	end
end

-- the slot center: ChaosRiftCore.slotCenter with the raid grid (rift_core.lua), or the same formula when it is not loaded
function K.slotCenter(cfg, slot)
	if ChaosRiftCore and ChaosRiftCore.slotCenter then
		return ChaosRiftCore.slotCenter(cfg, slot)
	end
	local g = cfg.grid
	local half = floor(g.spacing / 2)
	return {x = g.origin.x + (slot % g.cols) * g.spacing + half, y = g.origin.y + floor(slot / g.cols) * g.spacing + half,
		z = g.origin.z}
end

-- the layout of a slot: hall, corridors[i] = {rect, west = {pos...}, east = {pos...}}, rooms[i] = {rect, center,
-- entry, bossSpawn, fonts}, floor (set), floorList, wallList, exit (the hall's portal), start (where players land),
-- fallen (where fallen players land), basins, z. West to east along the slot's centre row.
function K.layout(cfg, slot)
	local c = K.slotCenter(cfg, slot)
	local z = c.z
	local hh, ch, cl, rh = cfg.hall.half, cfg.corridor.half, cfg.corridor.length, cfg.room.half
	local total = (2 * hh + 1) + #cfg.bosses * (cl + 2 * rh + 1)
	local x = c.x - floor(total / 2)
	local L = {center = c, z = z, floor = {}, floorList = {}, wallList = {}, walls = {}, corridors = {}, rooms = {},
		basins = {}}
	L.hall = {x1 = x, y1 = c.y - hh, x2 = x + 2 * hh, y2 = c.y + hh}
	rectList(L.hall, z, L.floorList, L.floor)
	L.exit = {x = L.hall.x1 + 1, y = c.y, z = z}
	L.start = {x = L.hall.x1 + 4, y = c.y, z = z}
	L.fallen = {x = L.hall.x1 + 3, y = c.y + 2, z = z}
	x = L.hall.x2 + 1
	for i = 1, #cfg.bosses do
		local cr = {x1 = x, y1 = c.y - ch, x2 = x + cl - 1, y2 = c.y + ch}
		rectList(cr, z, L.floorList, L.floor)
		local west, east = {}, {}
		for y = cr.y1, cr.y2 do
			west[#west + 1] = {x = cr.x1, y = y, z = z}
			east[#east + 1] = {x = cr.x2, y = y, z = z}
		end
		L.corridors[i] = {rect = cr, west = west, east = east,
			packAt = {{x = cr.x1 + 3, y = c.y, z = z}, {x = cr.x1 + 6, y = c.y, z = z}, {x = cr.x1 + 5, y = c.y - 1, z = z}}}
		x = cr.x2 + 1
		local rr = {x1 = x, y1 = c.y - rh, x2 = x + 2 * rh, y2 = c.y + rh}
		rectList(rr, z, L.floorList, L.floor)
		local rc = {x = rr.x1 + rh, y = c.y, z = z}
		L.rooms[i] = {rect = rr, center = rc, entry = {x = rr.x1 + 1, y = c.y, z = z}, bossSpawn = {x = rc.x + 2, y = c.y, z = z},
			fonts = {{x = rr.x1 + 1, y = rr.y1 + 1, z = z}, {x = rr.x1 + 1, y = rr.y2 - 1, z = z},
				{x = rr.x2 - 1, y = rr.y1 + 1, z = z}, {x = rr.x2 - 1, y = rr.y2 - 1, z = z}}}
		L.basins[#L.basins + 1] = {x = rr.x1, y = rr.y1, z = z}
		L.basins[#L.basins + 1] = {x = rr.x2, y = rr.y1, z = z}
		L.basins[#L.basins + 1] = {x = rr.x1, y = rr.y2, z = z}
		L.basins[#L.basins + 1] = {x = rr.x2, y = rr.y2, z = z}
		x = rr.x2 + 1
	end
	L.basins[#L.basins + 1] = {x = L.hall.x1, y = L.hall.y1, z = z}
	L.basins[#L.basins + 1] = {x = L.hall.x1, y = L.hall.y2, z = z}
	L.x2 = x - 1
	for _, f in ipairs(L.floorList) do
		for ox = -1, 1 do
			for oy = -1, 1 do
				local k = key(f.x + ox, f.y + oy)
				if not L.floor[k] and not L.walls[k] then
					L.walls[k] = {x = f.x + ox, y = f.y + oy, z = z}
					L.wallList[#L.wallList + 1] = L.walls[k]
				end
			end
		end
	end
	table.sort(L.wallList, function(p, q)
		return p.y == q.y and p.x < q.x or p.y < q.y
	end)
	return L
end

local function inRect(r, pos)
	return pos.x >= r.x1 and pos.x <= r.x2 and pos.y >= r.y1 and pos.y <= r.y2
end

-- where a position is in a layout: "hall" | "corridor", i | "room", i | nil
function K.where(L, pos)
	if not pos or pos.z ~= L.z then
		return nil
	end
	if inRect(L.hall, pos) then
		return "hall"
	end
	for i, cr in ipairs(L.corridors) do
		if inRect(cr.rect, pos) then
			return "corridor", i
		end
		if inRect(L.rooms[i].rect, pos) then
			return "room", i
		end
	end
	return nil
end

function K.inRoom(L, i, pos)
	return pos ~= nil and pos.z == L.z and L.rooms[i] ~= nil and inRect(L.rooms[i].rect, pos)
end

function K.dist(a, b)
	local dx, dy = a.x - b.x, a.y - b.y
	return sqrt(dx * dx + dy * dy)
end

-- the main direction from a to b: dx, dy in {-1, 0, 1}, one of them 0 (east when equal)
function K.direction(a, b)
	local dx, dy = b.x - a.x, b.y - a.y
	if dx == 0 and dy == 0 then
		return 1, 0
	end
	if abs(dx) > abs(dy) then
		return dx > 0 and 1 or -1, 0
	end
	return 0, dy > 0 and 1 or -1
end

-- the tiles of room i for which want(x, y) holds (rows north to south)
local function collect(L, i, want)
	local r = L.rooms[i].rect
	local out = {}
	for y = r.y1, r.y2 do
		for x = r.x1, r.x2 do
			if want(x, y) then
				out[#out + 1] = {x = x, y = y, z = L.z}
			end
		end
	end
	return out
end

-- a cone from the boss: towards `toward` (cleave) or away from it (back = true, sweep). length / spread in sqm
function K.cone(L, i, boss, toward, length, spread, back)
	local dx, dy = K.direction(boss, toward or {x = boss.x + 1, y = boss.y})
	if back then
		dx, dy = -dx, -dy
	end
	return collect(L, i, function(x, y)
		local along = (x - boss.x) * dx + (y - boss.y) * dy
		local side = abs((x - boss.x) * dy) + abs((y - boss.y) * dx)
		if along < 1 or along > length then
			return false
		end
		return side <= math.max(1, floor(spread * along / length + 0.5))
	end)
end

-- circles of `radius` round each centre (room tiles only; radius 1 is the 3 x 3 square, 2 a round 5 x 5)
function K.circles(L, i, centers, radius)
	return collect(L, i, function(x, y)
		for _, c in ipairs(centers) do
			if K.dist({x = x, y = y}, c) <= radius + 0.5 then
				return true
			end
		end
		return false
	end)
end

function K.tileSet(list)
	local s = {}
	for _, t in ipairs(list) do
		s[key(t.x, t.y)] = true
	end
	return s
end

-- the warning pictures (uber_core.lua U.markPlan when loaded: 3x3 pictures only where they cannot spill)
function K.markPlan(tiles)
	if ChaosUberCore and ChaosUberCore.markPlan then
		return ChaosUberCore.markPlan(tiles)
	end
	return {big = {}, small = tiles}
end

-- ===================================================================== mechanics
-- ---- sunder (tank swap)
function K.newSunder()
	return {stacks = {}, at = {}}
end

-- a boss hit on `pid` at `now` (ms): its stacks after the hit
function K.sunderHit(st, cfg, pid, now)
	local m = cfg.mechanics.sunder
	K.sunderExpire(st, cfg, now)
	st.stacks[pid] = math.min(m.maxStacks, (st.stacks[pid] or 0) + 1)
	st.at[pid] = now
	return st.stacks[pid]
end

function K.sunderExpire(st, cfg, now)
	local m = cfg.mechanics.sunder
	for pid, at in pairs(st.at) do
		if now - at >= m.expireMs then
			st.stacks[pid], st.at[pid] = nil, nil
		end
	end
end

function K.sunderStacks(st, pid)
	return st and st.stacks[pid] or 0
end

-- the damage multiplier of a boss hit on a player with `stacks`
function K.sunderMult(cfg, stacks)
	return 1 + (cfg.mechanics.sunder.stackPct / 100) * (stacks or 0)
end

-- after a hit on `target`: candidates = {{id, dist}} (other players, distance to the boss in sqm). Returns
-- {action = "swap", to = id} when someone fresh stands in melee range, {action = "verdict"} when nobody does, or nil
-- while the target is below swapAt.
function K.sunderDecide(st, cfg, target, candidates)
	local m = cfg.mechanics.sunder
	if K.sunderStacks(st, target) < m.swapAt then
		return nil
	end
	local best, bestStacks
	for _, c in ipairs(candidates or {}) do
		if c.id ~= target and (c.dist or 99) <= m.challengeRange + 0.5 then
			local s = K.sunderStacks(st, c.id)
			if s < m.swapAt and (not best or s < bestStacks or (s == bestStacks and c.id < best)) then
				best, bestStacks = c.id, s
			end
		end
	end
	if best then
		return {action = "swap", to = best}
	end
	return {action = "verdict"}
end

function K.verdictShare(cfg, stacks)
	return cfg.mechanics.sunder.verdictShare * K.sunderMult(cfg, stacks)
end

-- ---- soak (split damage)
function K.soakNeed(cfg, players)
	local m = cfg.mechanics.soak
	return m.need + floor(math.max(0, (players or 1) - cfg.minPlayers) / m.needPerPlayers)
end

function K.soakCount(cfg, players)
	return 1 + floor(math.max(0, (players or 1) - 1) / cfg.mechanics.soak.perCircle)
end

-- the circles' centres: on `count` different players (positions), spread by the order given
function K.soakCenters(cfg, positions, rand)
	local list = {}
	for _, p in ipairs(positions) do
		list[#list + 1] = p
	end
	local out = {}
	local n = math.min(K.soakCount(cfg, #positions), #list)
	for _ = 1, n do
		local p = table.remove(list, rand(1, #list))
		out[#out + 1] = {x = p.x, y = p.y, z = p.z}
	end
	return out
end

-- one circle resolves: inside = number of players in it, need, roomPlayers. Returns the share of max health each
-- player inside takes and the share everyone else in the room takes (overflow when too few soaked)
function K.soakResolve(cfg, inside, need)
	local m = cfg.mechanics.soak
	inside = inside or 0
	if inside <= 0 then
		return 0, m.overflowShare + m.totalShare / math.max(1, need) * 0.25
	end
	local each = m.totalShare / inside
	if inside < need then
		return each, m.overflowShare
	end
	return each, 0
end

-- ---- adds (priority)
function K.addReduction(cfg, alive)
	local m = cfg.mechanics.adds
	return math.min(m.maxReduce, m.reducePct * math.max(0, alive or 0))
end

function K.addHeal(cfg, alive, maxHealth)
	return floor(cfg.mechanics.adds.healPct / 100 * math.max(0, alive or 0) * (maxHealth or 0))
end

-- ---- totems and the Hexed stacks
function K.newHexed()
	return {stacks = {}}
end

-- one hex tick: every player in the room gains a stack per living totem (at most maxStacks); with no totem alive the
-- stacks fall by one. Returns the damage share of each player for this tick ({pid = share})
function K.hexTick(st, cfg, totems, players)
	local m = cfg.mechanics.totem
	local out = {}
	for _, pid in ipairs(players) do
		local s = st.stacks[pid] or 0
		if totems > 0 then
			s = math.min(m.maxStacks, s + totems)
		else
			s = math.max(0, s - 1)
		end
		st.stacks[pid] = s > 0 and s or nil
		if totems > 0 and s > 0 then
			out[pid] = m.stackShare * s
		end
	end
	return out
end

function K.totemExpired(cfg, bornMs, now)
	return now - bornMs >= cfg.mechanics.totem.lifeMs
end

-- ---- hex (dispel)
-- the hexed players of one cast: `count` of the given player ids (random order through rand)
function K.hexTargets(cfg, ids, players, rand)
	local list = {}
	for _, id in ipairs(ids) do
		list[#list + 1] = id
	end
	local n = math.min(K.waveCount(cfg.mechanics.hex, players), #list)
	local out = {}
	for _ = 1, n do
		out[#out + 1] = table.remove(list, rand(1, #list))
	end
	return out
end

-- a hex is due: cleansed (no damage), else the players within radius of the hexed one take burstShare
function K.hexResolve(cfg, cleansed, hexedPos, others)
	if cleansed then
		return {}
	end
	local m = cfg.mechanics.hex
	local hit = {}
	for _, o in ipairs(others) do
		if K.dist(o.pos, hexedPos) <= m.radius + 0.01 then
			hit[#hit + 1] = o.id
		end
	end
	return hit
end

-- ===================================================================== loot
-- one eligible player's spoils of boss `b`: {gold, items = {{id, count}}, gearRolls, uniqueChance, marks}
function K.spoils(cfg, b)
	local l = b.final and cfg.loot.final or cfg.loot.boss
	local items = {}
	for _, it in ipairs(l.orbs) do
		items[#items + 1] = {id = it.id, count = it.count}
	end
	return {gold = l.gold, items = items, gearRolls = l.gearRolls, uniqueChance = l.uniqueChance, marks = l.marks}
end

-- the raid uniques a kill of `bossKey` can give
function K.uniquesOf(cfg, bossKey)
	local out = {}
	for _, u in ipairs(cfg.uniques) do
		for _, k in ipairs(u.bosses) do
			if k == bossKey then
				out[#out + 1] = u
			end
		end
	end
	return out
end

-- the unique of a roll: roll 1..10000 against the chance, then rand picks one; nil when the roll misses
-- mult (optional): the bad-luck multiplier of the character (conquest.lua, group "raid"), at most x10000
function K.rollUnique(cfg, b, roll, rand, mult)
	local chance = math.min(10000, (b.final and cfg.loot.final or cfg.loot.boss).uniqueChance * (tonumber(mult) or 1))
	if roll > chance then
		return nil
	end
	local list = K.uniquesOf(cfg, b.key)
	if #list == 0 then
		return nil
	end
	return list[rand(1, #list)]
end

function K.gearLevel(cfg, rand)
	local g = cfg.loot.gearLevel
	return rand(g[1], g[2])
end

-- ===================================================================== vendor
local MOD, MULT = 2147483647, 48271
function K.hash(s)
	local h = 7
	s = tostring(s)
	for i = 1, #s do
		h = (h * 31 + s:byte(i)) % MOD
	end
	if h == 0 then
		h = 1
	end
	return h
end

-- a small seeded generator (Park-Miller): rng:int(a, b)
function K.rng(seed)
	local s = (tonumber(seed) or 1) % MOD
	if s <= 0 then
		s = s + MOD - 1
	end
	local r = {s = s}
	function r.next()
		r.s = (r.s * MULT) % MOD
		return r.s
	end
	function r.int(a, b)
		if b <= a then
			return a
		end
		return a + r.next() % (b - a + 1)
	end
	return r
end

function K.offer(cfg, k)
	for _, o in ipairs(cfg.vendor.pool) do
		if o.key == k then
			return o
		end
	end
	return nil
end

-- the week's stock: the `always` offers, then gear offers of the pool picked by the week's seed until `slots` are
-- filled (no offer twice). Returns a list of offer keys.
function K.vendorStock(cfg, week)
	local v = cfg.vendor
	local out, have = {}, {}
	for _, k in ipairs(v.always or {}) do
		if K.offer(cfg, k) then
			out[#out + 1] = k
			have[k] = true
		end
	end
	local gear = {}
	for _, o in ipairs(v.pool) do
		if o.kind == "gear" and not have[o.key] then
			gear[#gear + 1] = o.key
		end
	end
	local r = K.rng(K.hash("ashen sepulchre vendor " .. tostring(week)))
	while #out < v.slots + #(v.always or {}) and #gear > 0 do
		local k = table.remove(gear, r.int(1, #gear))
		out[#out + 1] = k
	end
	return out
end

function K.inStock(cfg, week, k)
	for _, s in ipairs(K.vendorStock(cfg, week)) do
		if s == k then
			return true
		end
	end
	return false
end

-- can this character buy offer `o` now? bought = times this week, marks = balance
function K.canBuy(o, bought, marks)
	if (bought or 0) >= (o.weekly or 1) then
		return false, "limit"
	end
	if (marks or 0) < o.price then
		return false, "marks"
	end
	return true
end

-- ===================================================================== texts
local function pct(v)
	return floor(v * 100 + 0.5) .. "%"
end

-- what a mechanic does, with its numbers (the journal and the yells)
function K.mechText(cfg, mech, b)
	local m = cfg.mechanics[mech] or {}
	if mech == "sunder" then
		return string.format("Sundering Blows: every hit stacks Sundered on the tank (+%d%% damage taken each, %d s). " ..
			"At %d stacks the boss turns to the next tank in melee range; with nobody there it brings down Crushing Verdict " ..
			"(%s of max health and more with the stacks).", m.stackPct, floor(m.expireMs / 1000), m.swapAt, pct(m.verdictShare))
	elseif mech == "cleave" then
		return string.format("Frontal Cleave: a cone %d sqm long in front of the boss, every %d s. Everyone in it but the " ..
			"tank takes %s of max health. Stand beside or behind.", m.length, floor(m.every / 1000), pct(m.share))
	elseif mech == "sweep" then
		return string.format("Rear Sweep: a cone %d sqm long behind the boss, every %d s, %s of max health. Never stand " ..
			"behind it.", m.length, floor(m.every / 1000), pct(m.share))
	elseif mech == "soak" then
		return string.format("Ember Brand: circles fall near players (one more per %d raiders). Each circle's %s of max " ..
			"health is split among those inside; fewer than %d inside (+1 per %d raiders over %d) and everyone else takes %s.",
			m.perCircle, pct(m.totalShare), m.need, m.needPerPlayers, cfg.minPlayers, pct(m.overflowShare))
	elseif mech == "adds" then
		return string.format("%s: adds every %d s; each one alive makes the boss take %d%% less damage (up to %d%%) and " ..
			"heals it %d%% every 5 s. Kill them first.", b and b.add or "Adds", floor(m.every / 1000), m.reducePct, m.maxReduce,
			m.healPct)
	elseif mech == "marks" then
		return string.format("Bone Bloom: a circle opens under every player; %s of max health to anyone still on one. " ..
			"Step out, and not onto someone else's.", pct(m.share))
	elseif mech == "totem" then
		return string.format("%s: effigies rise every %d s; each puts a Hexed stack on everyone every %d s (%s of max " ..
			"health per stack). Not killed within %d s they detonate for %s on everyone.", b and b.totem or "Hex Effigy",
			floor(m.every / 1000), floor(m.hexMs / 1000), pct(m.stackShare), floor(m.lifeMs / 1000), pct(m.detonateShare))
	elseif mech == "hex" then
		return string.format("Withering Hex: a curse on random players. Lift it within %d s (a cure curse spell, or use " ..
			"the Font of Ash in a corner) or it bursts for %s on everyone within %d sqm of them.", floor(m.windowMs / 1000),
			pct(m.burstShare), m.radius)
	end
	return mech
end

-- the short line the HUD and the yells announce when a mechanic starts
K.ANNOUNCE = {
	sunder = "TANK SWAP: %s is at %d stacks!",
	verdict = "CRUSHING VERDICT on %s!",
	cleave = "Frontal Cleave: get out of the front!",
	sweep = "Rear Sweep: get out from behind!",
	soak = "Ember Brand: SOAK the circles (%d each)!",
	adds = "%s arrive: kill them first!",
	marks = "Bone Bloom: step out of your circle!",
	totem = "%s rises: KILL IT!",
	hex = "Withering Hex on %s: cleanse it!"
}

-- the journal of the window: per boss {k, n, intro, roles, phases = {{n, at}}, mech = {text}, loot = {...}}
function K.journal(cfg)
	local out = {}
	for i, b in ipairs(cfg.bosses) do
		local phases = {}
		for _, p in ipairs(b.phases) do
			phases[#phases + 1] = {n = p.name, at = floor(p.at * 100 + 0.5)}
		end
		local mech = {}
		for _, m in ipairs(K.bossMechs(b)) do
			mech[#mech + 1] = K.mechText(cfg, m, b)
		end
		local sp = K.spoils(cfg, b)
		local uniques = {}
		for _, u in ipairs(K.uniquesOf(cfg, b.key)) do
			uniques[#uniques + 1] = u.name
		end
		out[i] = {k = b.key, n = b.name, intro = b.intro, roles = b.roles, phases = phases, mech = mech,
			enrage = b.enrageAt, final = b.final or nil,
			loot = {gold = sp.gold, items = sp.items, gear = b.gear, gearRolls = sp.gearRolls, gearLevel = cfg.loot.gearLevel,
				unique = sp.uniqueChance, uniques = uniques, marks = sp.marks}}
	end
	return out
end

function K.clockText(secs)
	secs = math.max(0, floor(secs or 0))
	return string.format("%d:%02d", floor(secs / 60), secs % 60)
end

-- the in-raid HUD (game_raid): s = {inst, bossIdx, boss = def|nil, state = "clear"|"idle"|"fight", hp, phase,
-- toEnrage, enraged, adds, totems, players, fallen, alerts = {text...}, stacks = {sunder, hexed}, hexed}
function K.hud(cfg, s)
	local b = s.boss
	local killed = {}
	for i = 1, #cfg.bosses do
		killed[i] = K.hasBit(s.inst.killed, i) or nil
	end
	local out = {raid = cfg.name, id = s.inst.id, boss = b and b.name or nil, idx = s.bossIdx, total = #cfg.bosses,
		done = K.bitCount(s.inst.killed, #cfg.bosses), killed = killed, state = s.state, hp = s.hp,
		phase = b and s.phase or nil, phases = b and #b.phases or nil,
		phaseName = b and s.phase and b.phases[s.phase] and b.phases[s.phase].name or nil,
		enrage = s.toEnrage, enraged = s.enraged or nil, adds = (s.adds or 0) > 0 and s.adds or nil,
		totems = (s.totems or 0) > 0 and s.totems or nil, players = s.players, fallen = (s.fallen or 0) > 0 and s.fallen or nil,
		alerts = s.alerts or {}, stacks = s.stacks or {}, hexed = s.hexed or nil, trash = s.trash}
	return out
end

-- problems of the config (startup console and the test)
function K.validate(cfg)
	local out = {}
	local function bad(fmt, ...)
		out[#out + 1] = string.format(fmt, ...)
	end
	if #cfg.bosses < 4 or #cfg.bosses > 5 then
		bad("%d bosses (4-5 expected)", #cfg.bosses)
	end
	if #cfg.trash ~= #cfg.bosses then
		bad("trash sections %d ~= bosses %d", #cfg.trash, #cfg.bosses)
	end
	local seen = {}
	for i, b in ipairs(cfg.bosses) do
		if seen[b.key] then
			bad("boss key %s twice", b.key)
		end
		seen[b.key] = true
		if b.phases[1].at ~= 1 then
			bad("%s: the first phase must start at 1", b.key)
		end
		for j = 2, #b.phases do
			if b.phases[j].at >= b.phases[j - 1].at then
				bad("%s: phase %d does not go down", b.key, j)
			end
		end
		local mechs = K.bossMechs(b)
		if (b.final and #mechs < 4) or (not b.final and (#mechs < 2 or #mechs > 3)) then
			bad("%s: %d mechanics", b.key, #mechs)
		end
		for _, m in ipairs(mechs) do
			if not cfg.mechanics[m] then
				bad("%s: unknown mechanic %s", b.key, m)
			end
			if m == "adds" and not b.add then
				bad("%s: adds without an add name", b.key)
			end
			if m == "totem" and not b.totem then
				bad("%s: totems without a totem name", b.key)
			end
		end
		if (i == #cfg.bosses) ~= (b.final == true) then
			bad("%s: only the last boss is final", b.key)
		end
		if #b.gear == 0 then
			bad("%s: no gear", b.key)
		end
	end
	for _, u in ipairs(cfg.uniques) do
		for _, k in ipairs(u.bosses) do
			if not seen[k] then
				bad("unique %s names unknown boss %s", u.name, k)
			end
		end
	end
	local keys = {}
	for _, o in ipairs(cfg.vendor.pool) do
		if keys[o.key] then
			bad("vendor offer %s twice", o.key)
		end
		keys[o.key] = true
	end
	for _, k in ipairs(cfg.vendor.always or {}) do
		if not keys[k] then
			bad("vendor always %s is not in the pool", k)
		end
	end
	if cfg.minPlayers < 1 or cfg.maxPlayers < cfg.minPlayers then
		bad("players %d-%d", cfg.minPlayers, cfg.maxPlayers)
	end
	return out
end

return K
