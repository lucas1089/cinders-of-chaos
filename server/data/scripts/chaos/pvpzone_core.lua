-- The Scorched Marches (open-world PvP zone): the pure part (no engine calls), shared by pvpzone.lua and
-- tests/pvpzone_test.lua.
--   map        instance slots per realm, the layout (gates, safe exits, the Cinder Shrine, ruins, spawn points), the
--              footprint, map mode (an existing rectangle)
--   entering   who may enter (level, Hardcore rule, confirmation, protection zone, combat, cooldown, ...), login
--              inside (hold, then the safe exit), protection, the exit channel
--   embers     carry cap, monster embers, the death pile, who may take how much, banking
--   kills      anti-farming verdict (as guild wars), faction reputation (pledge, rival, daily cap)
--   shrine     the contest (warden, capture, contested, decay), control and the faction-wide buff
--   vendor     prices, weekly limits, cosmetics
--   pvp        damage scaling like the battleground (its normalise numbers)
-- Settings: pvpzone_config.lua (passed in as `cfg`). Lua 5.1 / LuaJIT and Lua 5.3 compatible.

ChaosPvpZoneCore = ChaosPvpZoneCore or {}
local K = ChaosPvpZoneCore

local floor, max, min, abs = math.floor, math.max, math.min, math.abs
local DAY, WEEK = 86400, 7 * 86400

local function clamp(x, lo, hi)
	return max(lo, min(hi, x))
end

-- ====================================================================== time keys (Monday / day at `hour`, local)
local function startOfDay(t, hour)
	local d = os.date("*t", t)
	local s = os.time({year = d.year, month = d.month, day = d.day, hour = hour or 0, min = 0, sec = 0})
	if s > t then
		s = s - DAY
	end
	return s
end

-- a number that changes once a day at `hour`
function K.dayKey(t, hour)
	local s = startOfDay(t, hour)
	local d = os.date("*t", s)
	return d.year * 10000 + d.month * 100 + d.day
end

-- a number that changes every Monday at `hour`
function K.weekKey(t, hour)
	local s = startOfDay(t, hour)
	local wday = tonumber(os.date("%w", s)) -- 0 = Sunday
	local back = (wday + 6) % 7 -- days since Monday
	local d = os.date("*t", s - back * DAY + 3600) -- +1 h: safe over a DST change
	return d.year * 10000 + d.month * 100 + d.day
end

-- ====================================================================== map
function K.slotForRealm(cfg, realm)
	realm = tonumber(realm) or 0
	if cfg.mode == "map" then
		return 0
	end
	if realm <= 0 then
		return 0
	end
	local n = max(1, cfg.grid.slots - 1)
	return 1 + (floor(realm) - 1) % n
end

function K.slotOrigin(cfg, slot)
	local g = cfg.grid
	return {x = g.origin.x + (slot % g.cols) * g.spacing, y = g.origin.y + floor(slot / g.cols) * g.spacing, z = g.origin.z}
end

-- the ruins of one half in local coordinates (1..W, 1..H); the other half is the 180-degree turn (fair to both gates)
local RUIN_WALLS = {
	-- an L near the south-west gate's way to the shrine
	{18, 38}, {19, 38}, {20, 38}, {21, 38}, {22, 38}, {18, 39}, {18, 40}, {18, 41},
	-- a broken wall west of the shrine
	{26, 24}, {26, 25}, {26, 26}, {26, 30}, {26, 31}, {26, 32},
	-- a ruined hall in the north-west
	{10, 10}, {11, 10}, {12, 10}, {14, 10}, {15, 10}, {10, 11}, {10, 12}, {10, 14}, {15, 11}, {15, 12}, {15, 14},
	-- cover in the south
	{40, 46}, {41, 46}, {42, 46}, {43, 46},
	{30, 12}, {30, 13}, {30, 14}
}
local RUIN_PILLARS = {{24, 44}, {12, 24}, {33, 40}, {20, 18}, {46, 50}}

-- the layout of a slot (build mode): rectangles and positions in map coordinates
function K.layout(cfg, slot)
	local o = K.slotOrigin(cfg, slot)
	local W, H = cfg.field.innerW, cfg.field.innerH
	local z = o.z
	local function at(x, y)
		return {x = o.x + x, y = o.y + y, z = z}
	end
	local function turn(x, y)
		return W + 1 - x, H + 1 - y
	end
	local cx, cy = floor((W + 1) / 2), floor((H + 1) / 2)
	local L = {slot = slot, z = z, x1 = o.x, y1 = o.y, x2 = o.x + W + 1, y2 = o.y + H + 1, shrine = at(cx, cy),
		exits = {}, gates = {}, walls = {}, pillars = {}, flags = {}, spawns = {}, entrySpots = {}}
	-- two safe exits: south-west and (turned) north-east, each in a gate yard of 11 x 11
	local ex, ey = 7, H - 6
	for i, p in ipairs({{ex, ey}, {turn(ex, ey)}}) do
		local e = at(p[1], p[2])
		L.exits[i] = e
		L.gates[i] = {x1 = e.x - 5, y1 = e.y - 5, x2 = e.x + 5, y2 = e.y + 5}
		L.flags[#L.flags + 1] = {x = e.x - 3, y = e.y - 3, z = z}
		L.flags[#L.flags + 1] = {x = e.x + 3, y = e.y - 3, z = z}
		-- where a player arrives: the ring 2 tiles around the exit circle
		local spots = {}
		for dx = -2, 2 do
			for dy = -2, 2 do
				if max(abs(dx), abs(dy)) == 2 then
					spots[#spots + 1] = {x = e.x + dx, y = e.y + dy, z = z}
				end
			end
		end
		L.entrySpots[i] = spots
	end
	for _, w in ipairs(RUIN_WALLS) do
		L.walls[#L.walls + 1] = at(w[1], w[2])
		L.walls[#L.walls + 1] = at(turn(w[1], w[2]))
	end
	for _, q in ipairs(RUIN_PILLARS) do
		L.pillars[#L.pillars + 1] = at(q[1], q[2])
		L.pillars[#L.pillars + 1] = at(turn(q[1], q[2]))
	end
	-- spawn points: a grid, away from the gates and the shrine, never on a wall or a pillar
	local blocked = {}
	for _, list in ipairs({L.walls, L.pillars, L.flags}) do
		for _, p in ipairs(list) do
			blocked[p.x .. "," .. p.y] = true
		end
	end
	local m = cfg.monsters
	local step = m.spawnSpacing or 9
	for y = 4, H - 3, step do
		for x = 4, W - 3, step do
			local p = at(x, y)
			local far = true
			for _, e in ipairs(L.exits) do
				if max(abs(p.x - e.x), abs(p.y - e.y)) < (m.keepAway.exit or 9) then
					far = false
				end
			end
			if max(abs(p.x - L.shrine.x), abs(p.y - L.shrine.y)) < (m.keepAway.shrine or 7) then
				far = false
			end
			if far and not blocked[p.x .. "," .. p.y] then
				L.spawns[#L.spawns + 1] = p
			end
		end
	end
	return L
end

-- map mode: the configured rectangle of the loaded map
function K.mapLayout(cfg)
	local a = cfg.area
	if not a then
		return nil
	end
	local L = {slot = 0, z = a.z, x1 = a.x1, y1 = a.y1, x2 = a.x2, y2 = a.y2, shrine = a.shrine, exits = a.exits or {},
		gates = {}, walls = {}, pillars = {}, flags = {}, spawns = a.spawns or {}, entrySpots = {}, map = true}
	for i, e in ipairs(L.exits) do
		local spots = {}
		for dx = -2, 2 do
			for dy = -2, 2 do
				if max(abs(dx), abs(dy)) == 2 then
					spots[#spots + 1] = {x = e.x + dx, y = e.y + dy, z = e.z or a.z}
				end
			end
		end
		L.entrySpots[i] = spots
	end
	return L
end

local function inRect(r, z, pos)
	return pos ~= nil and pos.z == z and pos.x >= r.x1 and pos.x <= r.x2 and pos.y >= r.y1 and pos.y <= r.y2
end
K.inRect = inRect

function K.inLayout(L, pos)
	return L ~= nil and inRect(L, L.z, pos)
end

-- the instance slot a position belongs to (the outer wall included), or nil
function K.slotOfPos(cfg, pos)
	if not pos then
		return nil
	end
	if cfg.mode == "map" then
		local L = K.mapLayout(cfg)
		return (L and K.inLayout(L, pos)) and 0 or nil
	end
	local g = cfg.grid
	if pos.z ~= g.origin.z then
		return nil
	end
	local dx, dy = pos.x - g.origin.x, pos.y - g.origin.y
	if dx < 0 or dy < 0 then
		return nil
	end
	local col, row = floor(dx / g.spacing), floor(dy / g.spacing)
	if col >= g.cols then
		return nil
	end
	local slot = row * g.cols + col
	if slot >= g.slots then
		return nil
	end
	local lx, ly = dx - col * g.spacing, dy - row * g.spacing
	if lx > cfg.field.innerW + 1 or ly > cfg.field.innerH + 1 then
		return nil
	end
	return slot
end

-- index of the safe exit whose circle holds pos, or nil
function K.exitAt(cfg, L, pos)
	if not pos or pos.z ~= L.z then
		return nil
	end
	local r = cfg.exit.radius
	for i, e in ipairs(L.exits) do
		if abs(pos.x - e.x) <= r and abs(pos.y - e.y) <= r then
			return i
		end
	end
	return nil
end

-- the safe exit nearest to pos (index)
function K.nearestExit(L, pos)
	local best, bd
	for i, e in ipairs(L.exits) do
		local d = max(abs(pos.x - e.x), abs(pos.y - e.y))
		if not bd or d < bd then
			best, bd = i, d
		end
	end
	return best
end

function K.inShrine(cfg, L, pos)
	return pos ~= nil and L.shrine ~= nil and pos.z == L.z and abs(pos.x - L.shrine.x) <= cfg.contest.capture.radius
		and abs(pos.y - L.shrine.y) <= cfg.contest.capture.radius
end

-- every tile of a build-mode instance once: {x, y, z, wall = bool, ground = "ground" | "gate" | "ring"}
function K.footprint(cfg, L)
	local walls = {}
	for _, w in ipairs(L.walls) do
		walls[w.x .. "," .. w.y] = true
	end
	local list = {}
	for x = L.x1, L.x2 do
		for y = L.y1, L.y2 do
			local pos = {x = x, y = y, z = L.z}
			local wall = x == L.x1 or x == L.x2 or y == L.y1 or y == L.y2 or walls[x .. "," .. y] == true
			local ground = "ground"
			if K.inShrine(cfg, L, pos) or K.exitAt(cfg, L, pos) then
				ground = "ring"
			else
				for _, g in ipairs(L.gates) do
					if inRect(g, L.z, pos) then
						ground = "gate"
					end
				end
			end
			list[#list + 1] = {x = x, y = y, z = L.z, wall = wall, ground = ground}
		end
	end
	return list
end

-- ====================================================================== entering, login, protection, exit
-- p = {level, enabled, inside, hc, hcAccept, accept, inPz, inCombat, elsewhere (text), multiClient, cooldown (seconds
-- left), realmOk, staff}. Returns nil (may enter) or the reason. accept = the confirmation was given.
function K.entryRefusal(cfg, p)
	if not cfg.enabled or p.enabled == false then
		return string.format("%s are closed.", cfg.name)
	end
	if p.inside then
		return string.format("You are already in %s.", cfg.name)
	end
	if (p.level or 0) < cfg.minLevel then
		return string.format("You need level %d to enter %s.", cfg.minLevel, cfg.name)
	end
	if p.hc and not p.staff then
		if not (cfg.hardcore and cfg.hardcore.allow) then
			return "Hardcore characters cannot enter the Marches: a Hardcore life is not staked in open PvP."
		end
		if not p.hcAccept then
			return "Hardcore: confirm that a defeat in the Marches may end your Hardcore run."
		end
	end
	if p.realmOk == false then
		return string.format("Characters of your realm cannot enter %s.", cfg.name)
	end
	if (p.cooldown or 0) > 0 then
		return string.format("You were defeated in the Marches. You can enter again in %d seconds.", floor(p.cooldown + 0.5))
	end
	if p.multiClient then
		return "You cannot enter the Marches while another character from your connection is online."
	end
	if p.elsewhere then
		return "You cannot enter the Marches while in " .. p.elsewhere .. "."
	end
	if p.inCombat then
		return "You cannot enter the Marches while in combat."
	end
	if cfg.entry.needPz and not p.inPz then
		return "You can only enter the Marches from a protection zone."
	end
	if not p.accept then
		return "Read and accept the rules of the Marches first."
	end
	return nil
end

-- login inside: held (no damage) until moveAt, then moved to the nearest safe exit and protected until protectUntil
function K.loginTimes(cfg, now)
	local moveAt = now + cfg.login.holdSeconds
	return moveAt, moveAt + cfg.login.protectSeconds
end

function K.protected(untilAt, now)
	return (tonumber(untilAt) or 0) > now
end

-- the exit channel: standing in a safe exit circle since `since` (nil = not in one), last damage dealt or taken at
-- `lastCombat`. Returns nil (not channelling), or the share done (0..1) and true once it is complete.
function K.exitProgress(cfg, since, lastCombat, now)
	if not since then
		return nil
	end
	local from = max(since, tonumber(lastCombat) or 0)
	local need = max(1, cfg.exit.channelSeconds)
	local share = clamp((now - from) / need, 0, 1)
	return share, share >= 1
end

-- ====================================================================== embers
function K.addCarried(cfg, carried, amount)
	carried, amount = max(0, floor(carried or 0)), max(0, floor(amount or 0))
	local room = max(0, cfg.carry.max - carried)
	local added = min(room, amount)
	return carried + added, added, amount - added
end

function K.monsterEmbers(cfg, tier)
	return cfg.monsterEmbers[tier or "normal"] or cfg.monsterEmbers.normal or 0
end

-- a defeat: the pile that falls and what burns
function K.deathPile(cfg, carried)
	carried = max(0, floor(carried or 0))
	local pile = floor(carried * clamp(cfg.death.dropShare or 1, 0, 1))
	return pile, carried - pile
end

-- a new pile record. killerGuid = nil: a monster's victim (anyone at once); counted = false: the defeat failed the
-- anti-farming rules (the pile burns at once: amount 0)
function K.newPile(cfg, amount, victimGuid, killerGuid, counted, now)
	local p = {amount = max(0, floor(amount or 0)), victim = victimGuid, owner = killerGuid, taken = {}, at = now,
		expiresAt = now + cfg.death.pileSeconds}
	p.ownerUntil = killerGuid and (now + cfg.death.ownerSeconds) or now
	if counted == false then
		p.burned, p.amount = p.amount, 0
	end
	return p
end

-- what `picker` = {guid, carried, dayPicked, ssf} may take from pile now. Returns the amount, the reason when 0
-- ("gone", "owner", "ssf", "kill cap", "daily cap", "full"), and whether it counts for the daily cap (not the own pile).
function K.pickup(cfg, pile, picker, now)
	if not pile or pile.amount <= 0 or now >= pile.expiresAt then
		return 0, "gone", false
	end
	local own = picker.guid == pile.victim
	if not own and pile.owner and now < pile.ownerUntil and picker.guid ~= pile.owner then
		return 0, "owner", false
	end
	if not own and picker.ssf and not (cfg.ssf and cfg.ssf.takePiles) then
		return 0, "ssf", false
	end
	local take = pile.amount
	if not own then
		take = min(take, max(0, cfg.pickup.perKillMax - (pile.taken[picker.guid] or 0)))
		if take <= 0 then
			return 0, "kill cap", false
		end
		take = min(take, max(0, cfg.pickup.perDayMax - (picker.dayPicked or 0)))
		if take <= 0 then
			return 0, "daily cap", true
		end
	end
	take = min(take, max(0, cfg.carry.max - (picker.carried or 0)))
	if take <= 0 then
		return 0, "full", not own
	end
	return take, nil, not own
end

-- take `n` from the pile (after K.pickup said so)
function K.takeFrom(pile, guid, n)
	pile.amount = max(0, pile.amount - n)
	pile.taken[guid] = (pile.taken[guid] or 0) + n
	return pile.amount
end

-- banking at a safe exit: new banked balance, moved, lost (over the bank cap)
function K.bank(cfg, banked, carried)
	banked, carried = max(0, floor(banked or 0)), max(0, floor(carried or 0))
	local room = max(0, cfg.bankMax - banked)
	local moved = min(room, carried)
	return banked + moved, moved, carried - moved
end

-- ====================================================================== player rows
function K.newRow()
	return {banked = 0, total = 0, kills = 0, defeats = 0, captures = 0, haul = 0, pledge = "", pledgeAt = 0,
		day = 0, dayRep = 0, dayPicked = 0, week = 0, weekBanked = 0}
end

-- new day / week: the counters start again
function K.roll(row, day, week)
	if row.day ~= day then
		row.day, row.dayRep, row.dayPicked = day, 0, 0
	end
	if row.week ~= week then
		row.week, row.weekBanked = week, 0
	end
	return row
end

-- ====================================================================== kills: anti-farming and reputation
-- k = {killerAccount, victimAccount, killerIp, victimIp, killerLevel, victimLevel, enteredAt (the victim's entry),
-- at, lastCounted (this killer's last counted defeat of this victim, or nil)}. Returns counted, reason ("ok" or why not).
function K.killVerdict(cfg, k)
	local r = cfg.antiFarm
	if r.sameAccount and (k.killerAccount or 0) ~= 0 and k.killerAccount == k.victimAccount then
		return false, "same account"
	end
	if r.sameIp and (k.killerIp or 0) ~= 0 and k.killerIp == k.victimIp then
		return false, "same IP"
	end
	local vl, kl = tonumber(k.victimLevel) or 0, tonumber(k.killerLevel) or 0
	if vl < cfg.minLevel then
		return false, "low level"
	end
	if r.minLevelRatio and vl < kl * r.minLevelRatio then
		return false, "level gap"
	end
	if r.minSecondsInside and k.enteredAt and (k.at or 0) - k.enteredAt < r.minSecondsInside then
		return false, "just arrived"
	end
	if k.lastCounted and r.sameVictimMinutes and (k.at or 0) - k.lastCounted < r.sameVictimMinutes * 60 then
		return false, "repeat"
	end
	return true, "ok"
end

-- reputation for a counted defeat: killer pledged to `kf`, victim to `vf` (nil / "" = none), `rivalOf` = faction key ->
-- its sworn rival, `given` = reputation from Marches kills given today. Returns amount, reason.
function K.repFor(cfg, kf, vf, rivalOf, given)
	local r = cfg.reputation
	if not kf or kf == "" then
		return 0, "not pledged"
	end
	if not vf or vf == "" then
		return 0, "victim not pledged"
	end
	if kf == vf then
		return 0, "same faction"
	end
	local mult = (rivalOf and rivalOf[kf] == vf) and r.rivalMult or r.otherMult
	local amount = floor(r.perKill * mult + 0.5)
	local room = max(0, r.dailyCap - (given or 0))
	if room <= 0 then
		return 0, "daily cap"
	end
	return min(amount, room), nil
end

-- may a character pledge to `key`? ranks = factions_config.lua ranks, rep = its reputation with that faction,
-- current / changedAt = the pledge now and when it was made. Returns nil or the reason.
function K.pledgeRefusal(cfg, factions, ranks, key, rep, current, changedAt, now)
	local f
	for _, x in ipairs(factions or {}) do
		if x.key == key then
			f = x
		end
	end
	if not f then
		return "Unknown faction."
	end
	if current == key then
		return string.format("You already fight for %s.", f.name)
	end
	local need
	for _, r in ipairs(ranks or {}) do
		if r.key == cfg.reputation.minRank then
			need = r
		end
	end
	if need and (tonumber(rep) or 0) < need.min then
		return string.format("%s does not trust you enough: you need the rank %s.", f.name, need.name)
	end
	local wait = (tonumber(changedAt) or 0) + cfg.reputation.changeHours * 3600 - now
	if current and current ~= "" and wait > 0 then
		return string.format("You can change your pledge in %d hour(s).", math.ceil(wait / 3600))
	end
	return nil
end

-- ====================================================================== PvP scaling (the battleground's numbers)
-- damage of a level-ls player to a level-lt player is multiplied by this; the target's battleground bracket sets the
-- reference level (battleground_core.lua normFactor with its `normalise`)
function K.pvpFactor(bg, ls, lt)
	if not bg or not bg.normalise then
		return 1
	end
	lt = max(1, tonumber(lt) or 1)
	local ref
	for _, b in ipairs(bg.brackets or {}) do
		if lt >= b.min and (not b.max or lt <= b.max) then
			ref = b.ref
		end
	end
	ref = ref or (bg.brackets and bg.brackets[1] and bg.brackets[1].ref) or lt
	local n = bg.normalise
	local out = clamp((ref / max(1, tonumber(ls) or 1)) ^ n.exponent, n.minFactor, n.maxFactor)
	local inn = clamp((lt / ref) ^ n.exponent, n.minFactor, n.maxFactor)
	return out * inn
end

-- ====================================================================== the Cinder Shrine
function K.newContest(cfg, now)
	return {phase = "idle", nextAt = now + cfg.contest.firstMinutes * 60, progress = {}}
end

-- one capture step: counts = faction key -> pledged players in the circle, dt seconds. Returns the faction that
-- reached 100, or nil; and "contested" when two or more factions stand inside.
function K.captureStep(cfg, progress, counts, dt)
	local c = cfg.contest.capture
	local present = {}
	for key, n in pairs(counts or {}) do
		if n > 0 then
			present[#present + 1] = key
		end
	end
	if #present >= 2 then
		return nil, "contested"
	end
	local only = present[1]
	for key, v in pairs(progress) do
		if key ~= only then
			progress[key] = max(0, v - c.decayPerSecond * dt)
		end
	end
	if not only then
		return nil, nil
	end
	local n = counts[only]
	local rate = (100 / c.seconds) * min(c.maxRate, 1 + c.perExtra * (n - 1))
	progress[only] = min(100, (progress[only] or 0) + rate * dt)
	if progress[only] >= 100 then
		return only, nil
	end
	return nil, nil
end

-- the contest clock. info = {counts, wardenAlive, dt}. Returns a list of events:
--   {kind = "start"}       the warden must be spawned (phase "warden")
--   {kind = "warden"}      the warden fell: the shrine can be taken (phase "capture")
--   {kind = "captured", faction}
--   {kind = "expired"}     the window closed without a holder
function K.contestTick(cfg, c, now, info)
	local ev = {}
	local cc = cfg.contest
	if c.phase == "idle" then
		if now >= c.nextAt then
			c.phase, c.startedAt, c.endsAt = "warden", now, now + cc.windowMinutes * 60
			c.nextAt = now + cc.everyMinutes * 60
			c.progress, c.contested = {}, false
			ev[#ev + 1] = {kind = "start"}
		end
		return ev
	end
	if now >= (c.endsAt or now) then
		c.phase, c.contested = "idle", false
		ev[#ev + 1] = {kind = "expired"}
		return ev
	end
	if c.phase == "warden" then
		if not info.wardenAlive then
			c.phase = "capture"
			ev[#ev + 1] = {kind = "warden"}
		end
		return ev
	end
	if c.phase == "capture" then
		local winner, state = K.captureStep(cfg, c.progress, info.counts, info.dt or 1)
		c.contested = state == "contested"
		if winner then
			c.phase, c.winner, c.contested = "idle", winner, false
			ev[#ev + 1] = {kind = "captured", faction = winner}
		end
	end
	return ev
end

function K.newControl(cfg, faction, now)
	return {faction = faction, at = now, untilAt = now + cfg.contest.holdMinutes * 60}
end

-- the faction holding the shrine now (nil when nobody or the hold ran out)
function K.holder(control, now)
	if control and control.faction and control.faction ~= "" and (control.untilAt or 0) > now then
		return control.faction
	end
	return nil
end

-- the faction-wide buff: 1 + percent / 100 for a character pledged to the holder, else 1. kind "exp" | "loot"
function K.buffMult(cfg, control, pledge, now, kind)
	local h = K.holder(control, now)
	if h and pledge and pledge == h then
		return 1 + (cfg.contest.buff[kind] or 0) / 100
	end
	return 1
end

-- ====================================================================== vendor
function K.offer(cfg, key)
	for _, o in ipairs(cfg.vendor) do
		if o.key == key then
			return o
		end
	end
	return nil
end

-- may it be bought? banked = the balance, bought = purchases of it this week, owns(cosmeticKey) -> bool
function K.vendorCheck(cfg, key, banked, bought, owns)
	local o = K.offer(cfg, key)
	if not o then
		return false, "Unknown offer.", nil
	end
	if o.kind == "cosmetic" and owns and owns(o.cosmetic) then
		return false, "You already own it.", o
	end
	if o.weekly and (bought or 0) >= o.weekly then
		return false, string.format("Weekly limit reached (%d).", o.weekly), o
	end
	if (banked or 0) < o.cost then
		return false, string.format("You need %d more banked embers.", o.cost - (banked or 0)), o
	end
	return true, nil, o
end

return K
