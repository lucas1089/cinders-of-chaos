-- Invasions and world events: the pure logic (no engine calls), tested by server/tests/invasion_test.lua.
-- The runtime is invasion.lua (invasions) and worldevents.lua (Chaos Storm, Wandering Merchant, Golden Hour); every
-- number is in invasion_config.lua. Server local time. Lua 5.1 / LuaJIT and Lua 5.3 compatible.
--
--   schedule      I.scheduledStarts, I.randomStart, I.upcoming, I.resolve
--   waves         I.roster, I.scale, I.playerFactor, I.tierChances, I.planWave, I.planBoss, I.edgePoints, I.nextWaveDue
--   the fight     I.breachStep, I.outcome, I.sweep
--   rewards       I.credit, I.shares, I.rewards, I.defenderPoints
--   after         I.occupationOver, I.buffActive
--   world events  I.pickWorldEvent, I.nextWorldEventAt
--   HUD           I.hud, I.clock

ChaosInvasionCore = ChaosInvasionCore or {}
local I = ChaosInvasionCore

local floor, max, min = math.floor, math.max, math.min

local function clamp(v, lo, hi)
	if v < lo then
		return lo
	end
	if v > hi then
		return hi
	end
	return v
end
I.clamp = clamp

-- deterministic generator (same numbers in LuaJIT and Lua 5.3): rng(a, b) -> integer in [a, b], rng() -> [0, 1)
function I.lcg(seed)
	local s = floor(math.abs(tonumber(seed) or 1)) % 2147483647
	if s == 0 then
		s = 1
	end
	return function(a, b)
		s = (s * 16807) % 2147483647
		if a == nil then
			return (s - 1) / 2147483646
		end
		if b == nil then
			a, b = 1, a
		end
		if b < a then
			return a
		end
		return a + s % (b - a + 1)
	end
end

local function contains(list, value)
	for _, v in ipairs(list or {}) do
		if v == value then
			return true
		end
	end
	return false
end

function I.areaByKey(cfg, key)
	for i, a in ipairs(cfg.areas or {}) do
		if a.key == key then
			return a, i
		end
	end
	return nil
end

function I.factionKeys(cfg)
	local keys = {}
	for key in pairs(cfg.factions or {}) do
		keys[#keys + 1] = key
	end
	table.sort(keys)
	return keys
end

-- ============================================================================ schedule

local function dayStart(t)
	local d = os.date("*t", t)
	return os.time({year = d.year, month = d.month, day = d.day, hour = 0, min = 0, sec = 0})
end
I.dayStart = dayStart

local function dayKey(t)
	return tonumber(os.date("%Y%m%d", t))
end
I.dayKey = dayKey

-- the areas an invasion may pick (enabled, not world-event only)
function I.invasionAreas(cfg)
	local list = {}
	for _, a in ipairs(cfg.areas or {}) do
		if a.enabled ~= false and a.invasion ~= false then
			list[#list + 1] = a
		end
	end
	return list
end

-- "random" or a key -> an area key and a faction key; the random picks depend only on the start time, so the
-- warnings, the calendar and the start itself name the same area and faction
function I.resolve(cfg, at, areaKey, factionKey)
	local rng = I.lcg((tonumber(at) or 0) % 2147483647 + (cfg.random and cfg.random.salt or 0))
	local area
	if areaKey and areaKey ~= "random" then
		area = I.areaByKey(cfg, areaKey)
	end
	if not area then
		local list = I.invasionAreas(cfg)
		if #list == 0 then
			return nil
		end
		area = list[rng(1, #list)]
	end
	local faction = factionKey
	if not faction or faction == "random" or not (cfg.factions or {})[faction] then
		local keys = area.factions and #area.factions > 0 and area.factions or I.factionKeys(cfg)
		local valid = {}
		for _, k in ipairs(keys) do
			if (cfg.factions or {})[k] then
				valid[#valid + 1] = k
			end
		end
		if #valid == 0 then
			return nil
		end
		faction = valid[rng(1, #valid)]
	end
	return area.key, faction
end

-- scheduled starts in [fromT, toT): every entry {weekdays = {1..7} (1 = Sunday; nil = every day), hour, minute, area,
-- faction}; one-off entries {at = unix time, area, faction} (the /invasion schedule command) count too
function I.scheduledStarts(cfg, fromT, toT)
	local out = {}
	for i, e in ipairs(cfg.schedule or {}) do
		if e.at then
			if e.at >= fromT and e.at < toT then
				out[#out + 1] = {at = e.at, area = e.area, faction = e.faction, source = "once", index = i}
			end
		else
			local day = dayStart(fromT) - 86400
			while day < toT + 86400 do
				local d = os.date("*t", day + 43200)
				if not e.weekdays or contains(e.weekdays, d.wday) then
					local at = os.time({year = d.year, month = d.month, day = d.day, hour = e.hour or 20, min = e.minute or 0, sec = 0})
					if at >= fromT and at < toT then
						out[#out + 1] = {at = at, area = e.area, faction = e.faction, source = "schedule", index = i}
					end
				end
				day = dayStart(day + 86400 + 43200)
			end
		end
	end
	table.sort(out, function(a, b)
		return a.at < b.at
	end)
	return out
end

-- the random invasion of the calendar day of t, or nil. Decided by the day key alone (a restart does not re-roll):
-- chance percent per day, a start minute between fromHour and toHour, kept minGapMinutes away from the scheduled ones
function I.randomStart(cfg, t)
	local r = cfg.random
	if not r or (r.chance or 0) <= 0 then
		return nil
	end
	local day = dayStart(t)
	local rng = I.lcg(dayKey(day) * 7 + (r.salt or 0))
	if rng(1, 100) > r.chance then
		return nil
	end
	local fromMin = (r.fromHour or 12) * 60
	local toMin = max(fromMin, (r.toHour or 23) * 60 - 1)
	local d = os.date("*t", day)
	local gap = (r.minGapMinutes or 0) * 60
	local scheduled = I.scheduledStarts(cfg, day - 86400, day + 2 * 86400)
	for _ = 1, 8 do
		local m = rng(fromMin, toMin)
		local at = os.time({year = d.year, month = d.month, day = d.day, hour = floor(m / 60), min = m % 60, sec = 0})
		local clash = false
		for _, s in ipairs(scheduled) do
			if math.abs(s.at - at) < gap then
				clash = true
				break
			end
		end
		for _, h in ipairs(r.avoidHours or {}) do -- e.g. the world boss hours
			local hd = os.date("*t", at)
			if hd.hour == h or (hd.hour == (h + 23) % 24 and hd.min >= 60 - (r.minGapMinutes or 0)) then
				clash = true
			end
		end
		if not clash then
			return {at = at, area = r.area or "random", faction = r.faction or "random", source = "random"}
		end
	end
	return nil
end

-- every start after `now` within `horizon` seconds, scheduled and random, sorted, with area and faction resolved
-- (secret = true for the random ones: the calendar does not show them before their first warning)
function I.upcoming(cfg, now, horizon)
	local list = {}
	for _, s in ipairs(I.scheduledStarts(cfg, now + 1, now + horizon + 1)) do
		list[#list + 1] = s
	end
	local day = dayStart(now)
	while day <= now + horizon do
		local s = I.randomStart(cfg, day + 43200)
		if s and s.at > now and s.at <= now + horizon then
			s.secret = true
			list[#list + 1] = s
		end
		day = dayStart(day + 86400 + 43200)
	end
	table.sort(list, function(a, b)
		return a.at < b.at
	end)
	for _, s in ipairs(list) do
		s.areaKey, s.factionKey = I.resolve(cfg, s.at, s.area, s.faction)
	end
	return list
end

-- ============================================================================ waves

-- the faction's monsters that fit the area level: level within [lo x level, hi x level]; fewer than minTypes -> the
-- closest ones by level. Each entry {name, level, weight}
function I.roster(faction, areaLevel, sc)
	sc = sc or {}
	local lo, hi = (sc.rosterLow or 0.35) * areaLevel, (sc.rosterHigh or 1.25) * areaLevel
	local fit = {}
	for _, m in ipairs(faction.monsters or {}) do
		if m.level >= lo and m.level <= hi then
			fit[#fit + 1] = m
		end
	end
	local need = sc.minTypes or 3
	if #fit < need then
		local all = {}
		for _, m in ipairs(faction.monsters or {}) do
			all[#all + 1] = m
		end
		table.sort(all, function(a, b)
			local da, db = math.abs(a.level - areaLevel), math.abs(b.level - areaLevel)
			if da ~= db then
				return da < db
			end
			return a.name < b.name
		end)
		fit = {}
		for i = 1, min(need, #all) do
			fit[i] = all[i]
		end
	end
	table.sort(fit, function(a, b)
		if a.level ~= b.level then
			return a.level < b.level
		end
		return a.name < b.name
	end)
	return fit
end

-- the level shown after an invader's name (monster_levels.lua, engine patches 0040 / 0044): the area level every
-- invader is scaled to (I.scale; the roster stays within rosterLow-rosterHigh of it, inside the clamps); nil without one
function I.displayLevel(areaLevel)
	local lv = tonumber(areaLevel)
	if not lv or lv ~= lv or lv <= 0 or lv == math.huge then
		return nil
	end
	return math.floor(lv + 0.5)
end

-- multipliers that bring a monster of `monLevel` to the area level: health, damage and experience
function I.scale(monLevel, areaLevel, sc)
	sc = sc or {}
	local ratio = (areaLevel or 1) / max(1, monLevel or 1)
	local function f(exp, lo, hi)
		return clamp(ratio ^ (exp or 1), lo or 0.5, hi or 10)
	end
	return {
		hp = f(sc.hpExp or 1.0, sc.minMult or 0.5, sc.maxHp or 10),
		dmg = f(sc.dmgExp or 0.5, sc.minMult or 0.5, sc.maxDmg or 3),
		xp = f(sc.xpExp or 0.8, sc.minMult or 0.5, sc.maxXp or 6)
	}
end

-- more defenders -> bigger waves and a tougher boss
function I.playerFactor(players, p)
	p = p or {}
	players = max(1, floor(tonumber(players) or 1))
	return clamp(1 + (players - 1) * (p.perPlayer or 0.15), 1, p.maxFactor or 3)
end

-- percent chances {magic, rare, legendary} for wave i: base + perWave x (i - 1)
function I.tierChances(i, tiers)
	local out = {}
	for _, t in ipairs({"magic", "rare", "legendary"}) do
		local c = (tiers or {})[t] or {0, 0}
		out[t] = max(0, (c[1] or 0) + (c[2] or 0) * (i - 1))
	end
	return out
end

local function rollTier(chances, rng)
	local r = rng(1, 10000)
	local acc = 0
	for _, t in ipairs({"legendary", "rare", "magic"}) do
		acc = acc + floor((chances[t] or 0) * 100)
		if r <= acc then
			return t
		end
	end
	return "normal"
end
I.rollTier = rollTier

-- One wave: {index, count, packs = {{monsters = {{name, level, tier, scale}}}}}. Wave i favours the stronger half of
-- the roster as i grows; packs of packSize monsters arrive together at one edge point.
function I.planWave(cfg, area, faction, i, players, rng)
	local w = cfg.waves or {}
	local roster = I.roster(faction, area.level, cfg.scaling)
	local count = floor(((w.base or 10) + (w.perWave or 4) * (i - 1)) * I.playerFactor(players, cfg.players) + 0.5)
	local total = max(1, w.count or 5)
	local chances = I.tierChances(i, cfg.tiers)
	local monsters = {}
	if #roster > 0 then
		-- window of the roster: wave 1 the lower part, the last wave the upper part
		local frac = total > 1 and (i - 1) / (total - 1) or 1
		local span = max(1, floor(#roster * 0.6 + 0.5))
		local first = 1 + floor((#roster - span) * frac + 0.5)
		for _ = 1, count do
			local m = roster[rng(first, min(#roster, first + span - 1))]
			monsters[#monsters + 1] = {name = m.name, level = m.level, tier = rollTier(chances, rng),
				scale = I.scale(m.level, area.level, cfg.scaling)}
		end
	end
	local packs = {}
	local lo, hi = (w.packSize or {3, 5})[1], (w.packSize or {3, 5})[2]
	local k = 1
	while k <= #monsters do
		local size = rng(lo, max(lo, hi))
		local pack = {monsters = {}}
		for j = k, min(#monsters, k + size - 1) do
			pack.monsters[#pack.monsters + 1] = monsters[j]
		end
		packs[#packs + 1] = pack
		k = k + size
	end
	return {index = i, count = #monsters, packs = packs}
end

-- the invasion boss of the faction for the area level: the boss entry with the highest level not above the area level
-- (else the lowest), health = hpPerLevel x level x player factor, damage scaled like the waves
function I.planBoss(cfg, area, faction, players)
	local list = faction.bosses or {}
	if #list == 0 then
		return nil
	end
	local pick
	for _, b in ipairs(list) do
		if b.level <= area.level and (not pick or b.level > pick.level) then
			pick = b
		end
	end
	if not pick then
		for _, b in ipairs(list) do
			if not pick or b.level < pick.level then
				pick = b
			end
		end
	end
	local bc = cfg.boss or {}
	local hp = max(bc.minHealth or 1000, floor((bc.hpPerLevel or 2500) * area.level * I.playerFactor(players, cfg.players)))
	local s = I.scale(pick.level, area.level, {dmgExp = bc.dmgExp or 0.5, maxDmg = bc.maxDmg or 3, minMult = bc.minMult or 0.3,
		xpExp = 0, maxXp = 1, hpExp = 0, maxHp = 1})
	return {name = pick.name, rename = pick.rename, level = pick.level, health = hp, dmg = s.dmg,
		xp = bc.xpMult or 1, tier = bc.tier or "legendary"}
end

-- points on the area border (inset 0 .. depth-1) of the given edges ({"north", "south", "east", "west"}; nil = all),
-- shuffled; the runtime keeps the ones whose tile is valid
function I.edgePoints(area, rng, depth, edges)
	depth = max(1, depth or 2)
	local x1, y1, x2, y2 = area.from.x, area.from.y, area.to.x, area.to.y
	local z = area.z or area.from.z or 7
	local want = {}
	for _, e in ipairs(edges or area.edges or {"north", "south", "east", "west"}) do
		want[e] = true
	end
	local seen, pts = {}, {}
	local function add(x, y)
		local key = x .. ":" .. y
		if not seen[key] and x >= x1 and x <= x2 and y >= y1 and y <= y2 then
			seen[key] = true
			pts[#pts + 1] = {x = x, y = y, z = z}
		end
	end
	for d = 0, depth - 1 do
		for x = x1, x2 do
			if want.north then
				add(x, y1 + d)
			end
			if want.south then
				add(x, y2 - d)
			end
		end
		for y = y1, y2 do
			if want.west then
				add(x1 + d, y)
			end
			if want.east then
				add(x2 - d, y)
			end
		end
	end
	for i = #pts, 2, -1 do
		local j = rng(1, i)
		pts[i], pts[j] = pts[j], pts[i]
	end
	return pts
end

function I.inArea(pos, area, margin)
	margin = margin or 0
	if not pos or not area then
		return false
	end
	local z = area.z or area.from.z or 7
	return pos.z == z and pos.x >= area.from.x - margin and pos.x <= area.to.x + margin
		and pos.y >= area.from.y - margin and pos.y <= area.to.y + margin
end

-- inside one of the area's excluded rectangles {x1, y1, x2, y2} (temple surroundings, quest rooms)
function I.excluded(pos, area)
	for _, r in ipairs(area.exclude or {}) do
		if pos.x >= r[1] and pos.x <= r[3] and pos.y >= r[2] and pos.y <= r[4] then
			return true
		end
	end
	return false
end

-- next wave: the current one is down to nextAtLeft (fraction) of its monsters, or maxWaveSeconds passed
function I.nextWaveDue(st, now, w)
	w = w or {}
	if st.wave >= st.waves then
		return false
	end
	if st.wave == 0 then
		return now >= (st.firstWaveAt or st.startedAt)
	end
	local alive = st.waveAlive or 0
	local size = max(1, st.waveSize or 1)
	return alive <= floor(size * (w.nextAtLeft or 0.25)) or now - (st.waveAt or now) >= (w.maxWaveSeconds or 150)
end

-- ============================================================================ the fight

-- breach meter in percent: + perInvader per invader at the target per second (the boss counts bossWeight), at most
-- maxPerSecond; - decay per second while no invader is at the target
function I.breachStep(breach, atTarget, bossAt, dt, b)
	b = b or {}
	dt = dt or 1
	local weight = (atTarget or 0) + (bossAt and (b.bossWeight or 4) or 0)
	if weight > 0 then
		breach = breach + min(b.maxPerSecond or 3, weight * (b.perInvader or 0.35)) * dt
	else
		breach = breach - (b.decay or 0.25) * dt
	end
	return clamp(breach, 0, 100)
end

-- nil while running, else "win", "breach" or "time". rout = cfg.rout ({seconds}): once the warlord is down
-- (st.bossDownAt), the invaders still alive `seconds` later flee and it is a win; a time-up with the warlord down is a
-- win too. Without rout only a full clear wins (the old rule).
function I.outcome(st, now, rout)
	if st.breach >= 100 then
		return "breach"
	end
	local bossDown = st.wave >= st.waves and st.bossSpawned and not st.bossAlive
	if bossDown and (st.alive or 0) == 0 then
		return "win"
	end
	if bossDown and rout and st.bossDownAt and now - st.bossDownAt >= (rout.seconds or 90) then
		return "win"
	end
	if now >= st.endsAt then
		return (bossDown and rout) and "win" or "time"
	end
	return nil
end

-- the invaders that still count, once a second. invaders = {[id] = info} (info.wave, info.boss, info.stuckSince,
-- info.lastHitAt); look(id) -> nil when the monster no longer exists, else {pos = {x, y, z}, master = bool,
-- target = bool}. ctx = {now, wave (the current one), target = {x, y, z}, area (I.inArea's rectangle)}; s =
-- cfg.stragglers. Returns {alive, waveAlive, gone = {ids}, strays = {ids}, bossGone = bool}. Nothing is changed: the
-- engine removes the gone ones and calls the strays back.
function I.sweep(invaders, look, ctx, s)
	s = s or {}
	local out = {alive = 0, waveAlive = 0, gone = {}, strays = {}, bossGone = false}
	local ids = {}
	for id in pairs(invaders or {}) do
		ids[#ids + 1] = id
	end
	table.sort(ids)
	for _, id in ipairs(ids) do
		local info = invaders[id]
		local m = look(id)
		if not m or m.master then
			out.gone[#out.gone + 1] = id
			if info.boss then
				out.bossGone = true
			end
		else
			local stray = false
			local p, t = m.pos, ctx.target
			if p and t and p.z ~= t.z then
				stray = true
			elseif p and ctx.area and not I.inArea(p, ctx.area, s.margin or 8) then
				stray = true
			elseif not m.target and info.stuckSince and ctx.now - info.stuckSince >= (s.stuckSeconds or 30)
				and ctx.now - (info.lastHitAt or 0) >= (s.idleSeconds or 30) then
				stray = true
			end
			if stray then
				out.strays[#out.strays + 1] = id
			end
			out.alive = out.alive + 1
			if info.wave and info.wave == ctx.wave then
				out.waveAlive = out.waveAlive + 1
			end
		end
	end
	return out
end

-- ============================================================================ contribution and rewards

-- contrib = {[guid] = {name, damage, healing, kills, boss}}
function I.credit(contrib, guid, name, field, amount)
	if not guid or not amount or amount <= 0 then
		return nil
	end
	local e = contrib[guid]
	if not e then
		e = {name = name, damage = 0, healing = 0, kills = 0, boss = 0}
		contrib[guid] = e
	end
	e[field] = (e[field] or 0) + amount
	return e
end

function I.score(e, w, unit)
	w = w or {}
	return (e.damage or 0) * (w.damage or 1) + (e.healing or 0) * (w.healing or 0.6)
		+ (e.kills or 0) * (w.kill or 0.25) * (unit or 0)
end

-- eligible players (score >= minPoints, not excluded), sorted by score, with share and rank
function I.shares(contrib, w, unit, minPoints, excluded)
	excluded = excluded or {}
	local list, total = {}, 0
	for guid, e in pairs(contrib) do
		local s = I.score(e, w, unit)
		if not excluded[guid] and s > 0 and s >= (minPoints or 0) then
			list[#list + 1] = {guid = guid, name = e.name, score = s, damage = e.damage or 0, healing = e.healing or 0,
				kills = e.kills or 0, boss = e.boss or 0}
			total = total + s
		end
	end
	table.sort(list, function(a, b)
		if a.score ~= b.score then
			return a.score > b.score
		end
		return a.guid < b.guid
	end)
	for i, e in ipairs(list) do
		e.share = total > 0 and e.score / total or 0
		e.rank = i
	end
	return list, total
end

-- weekly Defender board points: base per invasion + the share in percent
function I.defenderPoints(share, d)
	d = d or {}
	return floor((d.base or 10) + (share or 0) * (d.sharePoints or 100) + 0.5)
end

-- shares -> rewards {guid, name, rank, share, bank, items = {{id, count}}, unique = bool, points}
-- gold = level x (goldBase + goldPool x share); orbs: base + floor(pool x share) + the top 3 extras; mult scales gold
-- and orbs (the liberation of an occupied area pays less); unique: chance per 10000 = uniqueChance + share x bonus
function I.rewards(shares, r, areaLevel, mult, rng)
	mult = mult or 1
	rng = rng or math.random
	local out = {}
	for _, s in ipairs(shares) do
		local map, order = {}, {}
		local function add(id, count)
			count = floor(count * mult)
			if count > 0 then
				if not map[id] then
					map[id] = 0
					order[#order + 1] = id
				end
				map[id] = map[id] + count
			end
		end
		for _, it in ipairs(r.base or {}) do
			add(it.id, it.count)
		end
		for _, it in ipairs(r.pool or {}) do
			add(it.id, floor(it.count * s.share))
		end
		for _, it in ipairs((r.top or {})[s.rank] or {}) do
			add(it.id, it.count)
		end
		local items = {}
		for _, id in ipairs(order) do
			items[#items + 1] = {id = id, count = map[id]}
		end
		local bank = floor((areaLevel or 1) * ((r.goldBase or 0) + (r.goldPool or 0) * s.share) * mult)
		local unique = false
		if (r.uniqueChance or 0) > 0 and mult >= 1 then
			unique = rng(1, 10000) <= (r.uniqueChance or 0) + floor((r.uniqueShareBonus or 0) * s.share)
		end
		out[#out + 1] = {guid = s.guid, name = s.name, rank = s.rank, share = s.share, score = s.score, bank = bank,
			items = items, unique = unique, points = I.defenderPoints(s.share, r.defender)}
	end
	return out
end

-- ============================================================================ after the invasion

-- occupation of a lost area: nil while it lasts, "liberated" (every occupier slain) or "withdrawn" (time up)
function I.occupationOver(occ, now, alive)
	if not occ then
		return nil
	end
	if (alive or 0) <= 0 then
		return "liberated"
	end
	if now >= occ.endsAt then
		return "withdrawn"
	end
	return nil
end

function I.buffActive(buff, now)
	return buff ~= nil and now < (buff.endsAt or 0)
end

-- ============================================================================ world events

-- the next event kind by weight, never the same kind twice in a row (unless it is the only one)
function I.pickWorldEvent(we, lastKind, rng)
	local kinds, total = {}, 0
	for _, k in ipairs({"storm", "merchant", "golden"}) do
		local e = we[k]
		local w = e and e.enabled ~= false and (e.weight or 0) or 0
		if w > 0 and (k ~= lastKind) then
			kinds[#kinds + 1] = {k, w}
			total = total + w
		end
	end
	if #kinds == 0 then
		local e = lastKind and we[lastKind]
		return (e and e.enabled ~= false and (e.weight or 0) > 0) and lastKind or nil
	end
	local r = rng(1, total)
	for _, kw in ipairs(kinds) do
		r = r - kw[2]
		if r <= 0 then
			return kw[1]
		end
	end
	return kinds[#kinds][1]
end

-- the areas a world event kind may use (areas with worldEvents ~= false, and the kind's own `areas` list if any)
function I.worldEventAreas(cfg, kind)
	local we = cfg.worldEvents or {}
	local only = we[kind] and we[kind].areas
	local list = {}
	for _, a in ipairs(cfg.areas or {}) do
		if a.enabled ~= false and a.worldEvents ~= false and (not only or contains(only, a.key)) then
			list[#list + 1] = a
		end
	end
	return list
end

-- when the next world event starts after one at `last`: a random gap of intervalMinutes {lo, hi}, pushed past an
-- invasion that would start within quietMinutes of it
function I.nextWorldEventAt(we, last, rng, upcoming)
	local lo, hi = (we.intervalMinutes or {120, 240})[1], (we.intervalMinutes or {120, 240})[2]
	local at = last + rng(lo, max(lo, hi)) * 60
	local quiet = (we.quietMinutes or 45) * 60
	for _, s in ipairs(upcoming or {}) do
		if at > s.at - quiet and at < s.at + quiet then
			at = s.at + quiet
		end
	end
	return at
end

-- ============================================================================ HUD

function I.clock(seconds)
	seconds = max(0, floor(seconds or 0))
	return string.format("%d:%02d", floor(seconds / 60), seconds % 60)
end

-- the HUD message. st = the runtime state; list = I.shares(...) of this tick (sorted); mine = the player's entry of
-- that list (or nil). progress = invaders slain or gone (I.sweep) of all planned (the boss counts as one)
function I.hud(st, now, list, mine, cfg)
	cfg = cfg or {}
	local d = {
		phase = st.phase,
		area = st.areaName,
		faction = st.factionName,
		color = st.factionColor,
		target = st.targetName,
		wave = st.wave or 0,
		waves = st.waves or 0,
		left = st.alive or 0,
		progress = st.planned and st.planned > 0 and min(100, floor(((st.slain or 0) + (st.gone or 0)) * 100 / st.planned)) or 0,
		breach = floor((st.breach or 0) + 0.5),
		time = max(0, (st.endsAt or now) - now),
		top = {}
	}
	if st.bossAlive then
		d.boss = st.bossName
		d.bossHp = st.bossHp or 100
	end
	if st.phase == "occupied" then
		d.time = max(0, (st.occupation and st.occupation.endsAt or now) - now)
		d.left = st.occupation and st.occupation.alive or 0
	elseif st.wave == 0 and st.firstWaveAt then
		d.next = max(0, st.firstWaveAt - now)
	end
	for i = 1, min(cfg.hudTop or 3, #(list or {})) do
		d.top[i] = {name = list[i].name, share = floor(list[i].share * 100 + 0.5)}
	end
	if mine then
		d.you = {rank = mine.rank, share = floor(mine.share * 100 + 0.5), kills = mine.kills or 0}
	end
	return d
end

return I
