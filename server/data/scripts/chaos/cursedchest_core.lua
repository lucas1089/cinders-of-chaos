-- Cursed Chest pure logic (no engine calls): the chance of a kill and its exclusions, the monster pool, the hordes,
-- the level scale, the event's state machine (what to do on each tick) and the loot amounts. Used by cursedchest.lua and
-- tested by server/tests/cursedchest_test.lua. Every function takes the config table and, where it rolls, a random
-- function rand(a, b) -> integer in [a, b]. Lua 5.1 / LuaJIT and Lua 5.3 compatible. See server/README.md "Cursed Chest".

ChaosCursedChestCore = ChaosCursedChestCore or {}
local K = ChaosCursedChestCore

local floor, min, max = math.floor, math.min, math.max

local function clamp(v, lo, hi)
	if v < lo then
		return lo
	end
	if v > hi then
		return hi
	end
	return v
end
K.clamp = clamp

-- ------------------------------------------------------------------ the chance
-- the share of the chance a monster of `monsterLevel` keeps against a character of `playerLevel` (1 within the grace)
function K.levelFactor(cfg, playerLevel, monsterLevel)
	local g = cfg.spawn.levelGap
	playerLevel, monsterLevel = tonumber(playerLevel) or 0, tonumber(monsterLevel) or 0
	if playerLevel <= 0 or monsterLevel + (g.grace or 0) >= playerLevel then
		return 1
	end
	local share = monsterLevel / playerLevel
	for _, row in ipairs(g.ratio or {}) do
		if share >= row[1] then
			return row[2]
		end
	end
	return 0
end

-- percent chance of a chest for one kill; 0 for an unknown tier
function K.chance(cfg, tier, playerLevel, monsterLevel, mult)
	local base = cfg.spawn.chance[tier] or 0
	if base <= 0 then
		return 0
	end
	local pct = base * K.levelFactor(cfg, playerLevel, monsterLevel) * (mult or 1)
	return clamp(pct, 0, cfg.spawn.maxChance or 100)
end

function K.inRects(rects, pos)
	for _, r in ipairs(rects or {}) do
		if (r[5] == nil or r[5] == pos.z) and pos.x >= r[1] and pos.x <= r[3] and pos.y >= r[2] and pos.y <= r[4] then
			return true
		end
	end
	return false
end

-- state = {cooldown = {[ownerId] = untilSec}, alive = n, perOwner = {[ownerId] = n}}
function K.newState()
	return {cooldown = {}, alive = 0, perOwner = {}}
end

-- Whether a kill may roll, before the dice. info = {ownerId, tier, boss (a tiered boss still rolls, as its tier),
-- name, summon, tagged (a monster of an event: this one's or another system's), eventTagged, husk (loot off),
-- maxHealth, pos, place (PvP place name or nil), instance (an instance's key or nil), protectionZone, house,
-- stamina (false: no stamina for loot), playerLevel, monsterLevel}. Returns ok, reason.
function K.eligible(cfg, info, state, now)
	local s = cfg.spawn
	if cfg.enabled == false then
		return false, "disabled"
	end
	if not info.ownerId then
		return false, "no owner"
	end
	if info.summon then
		return false, "summon"
	end
	if info.tagged or info.eventTagged or info.husk then
		return false, "event monster"
	end
	if info.stamina == false then
		return false, "stamina"
	end
	if info.place then
		return false, "pvp place"
	end
	if info.instance then
		return false, "instance"
	end
	if info.protectionZone or info.house then
		return false, "zone"
	end
	local name = tostring(info.name or ""):lower()
	if (s.excludeNames or {})[name] then
		return false, "skipped"
	end
	if (info.maxHealth or 0) < (s.minMaxHealth or 0) then
		return false, "weak"
	end
	if info.pos and K.inRects(s.excludedAreas, info.pos) then
		return false, "area"
	end
	if (state.alive or 0) >= (s.maxAlive or 1) then
		return false, "max alive"
	end
	if (state.perOwner[info.ownerId] or 0) >= (s.maxPerPlayer or 1) then
		return false, "own chest"
	end
	local untilSec = state.cooldown[info.ownerId]
	if untilSec and now < untilSec then
		return false, "cooldown"
	end
	if K.levelFactor(cfg, info.playerLevel, info.monsterLevel) <= 0 then
		return false, "level"
	end
	return true
end

-- the dice: percent chance of the tier and level gap; rand(1, 1000000) <= pct * 10000
function K.roll(cfg, info, rand, mult)
	local pct = K.chance(cfg, info.tier, info.playerLevel, info.monsterLevel, mult)
	if pct <= 0 then
		return false
	end
	return rand(1, 1000000) <= floor(pct * 10000 + 0.5)
end

function K.markSpawn(cfg, state, ownerId, now)
	state.cooldown[ownerId] = now + (cfg.spawn.cooldownSec or 0)
	state.perOwner[ownerId] = (state.perOwner[ownerId] or 0) + 1
	state.alive = (state.alive or 0) + 1
end

function K.markGone(state, ownerId)
	state.alive = max(0, (state.alive or 0) - 1)
	local n = (state.perOwner[ownerId] or 0) - 1
	state.perOwner[ownerId] = n > 0 and n or nil
end

-- drops cooldowns that passed (called now and then so the table does not grow)
function K.prune(state, now)
	for id, untilSec in pairs(state.cooldown) do
		if now >= untilSec then
			state.cooldown[id] = nil
		end
	end
end

-- ------------------------------------------------------------------ the level
-- the chest's area level: the killed monster's level, lifted to floorShare of the opener's, at most opener + slack
function K.areaLevel(cfg, monsterLevel, openerLevel)
	local l = cfg.level
	openerLevel = tonumber(openerLevel) or 1
	local level = max(tonumber(monsterLevel) or 0, floor(openerLevel * (l.floorShare or 0)))
	level = min(level, openerLevel + (l.slack or 0))
	return clamp(floor(level), l.min or 1, l.max or 1500)
end

-- the level the hordes are scaled to for an opener (their own level is lifted to it, never lowered)
function K.targetLevel(cfg, openerLevel)
	return clamp(floor((tonumber(openerLevel) or 1) * cfg.event.scale.levelShare), 1, cfg.level.max or 1500)
end

-- health / damage multipliers for a monster of native level `native` brought to `target` (capped)
function K.levelScale(cfg, native, target)
	local s = cfg.event.scale
	native = max(1, tonumber(native) or 1)
	target = max(native, tonumber(target) or native)
	local hp = (1 + s.healthK * target) / (1 + s.healthK * native)
	local dmg = (1 + s.damageK * target) / (1 + s.damageK * native)
	return {health = min(hp, s.maxHealth), damage = min(dmg, s.maxDamage)}
end

-- ------------------------------------------------------------------ the pool
-- names: {name, ...} of the monsters seen near the corpse (repeats weigh), killed: the killed monster's name. Returns
-- the kinds {name = , weight = } (lowercase keys kept as given), killed first; at most maxKinds; padded from the
-- themed band of `level` up to minKinds.
function K.buildPool(cfg, killed, names, level, skip)
	local p = cfg.event.pool
	local counts, order = {}, {}
	local function add(name, n)
		if type(name) ~= "string" or name == "" then
			return
		end
		local key = name:lower()
		if skip and skip[key] then
			return
		end
		if not counts[key] then
			counts[key] = {name = name, weight = 0}
			order[#order + 1] = key
		end
		counts[key].weight = counts[key].weight + n
	end
	add(killed, p.killedWeight or 1)
	for _, n in ipairs(names or {}) do
		add(n, 1)
	end
	local list = {}
	for _, key in ipairs(order) do
		list[#list + 1] = counts[key]
	end
	table.sort(list, function(a, b)
		if a.weight ~= b.weight then
			return a.weight > b.weight
		end
		return a.name:lower() < b.name:lower()
	end)
	while #list > (p.maxKinds or 4) do
		list[#list] = nil
	end
	if #list < (p.minKinds or 1) then
		local themed = {}
		for _, band in ipairs(p.themed or {}) do
			if level >= band[1] then
				themed = band[2]
			end
		end
		for _, n in ipairs(themed) do
			if #list >= (p.minKinds or 1) then
				break
			end
			local key = n:lower()
			if not counts[key] and not (skip and skip[key]) then
				counts[key] = {name = n, weight = 1}
				list[#list + 1] = counts[key]
			end
		end
	end
	return list
end

-- weighted pick of a kind name
function K.pickKind(pool, rand)
	local total = 0
	for _, k in ipairs(pool) do
		total = total + k.weight
	end
	if total <= 0 then
		return nil
	end
	local roll, acc = rand(1, total), 0
	for _, k in ipairs(pool) do
		acc = acc + k.weight
		if roll <= acc then
			return k.name
		end
	end
	return pool[#pool].name
end

-- ------------------------------------------------------------------ the hordes
function K.hordeCount(cfg)
	return #cfg.event.hordes
end

-- party scale of a horde: 1 + partyHorde per extra player, at most maxPartyScale
function K.partyScale(cfg, players)
	local e = cfg.event
	return min(e.maxPartyScale or 1, 1 + (e.partyHorde or 0) * max(0, (players or 1) - 1))
end

-- weighted pick of a tier from {tier = percent}; the rest is "normal"
local function pickTier(weights, rand)
	local roll, acc = rand(1, 100), 0
	local keys = {}
	for k in pairs(weights or {}) do
		keys[#keys + 1] = k
	end
	table.sort(keys)
	for _, k in ipairs(keys) do
		acc = acc + weights[k]
		if roll <= acc then
			return k
		end
	end
	return "normal"
end
K.pickTier = pickTier

-- The plan of horde n (1-based) for `players` taking part: {count, tiers = {tier per monster, the leader first},
-- leader = tier or nil, health, damage}. A leader replaces one of the monsters and is listed first.
function K.hordePlan(cfg, n, players, rand)
	local h = cfg.event.hordes[n]
	if not h then
		return nil
	end
	local count = max(1, floor(h.count * K.partyScale(cfg, players) + 0.5))
	local tiers = {}
	local leader
	if h.leader then
		leader = pickTier(h.leader, rand)
		tiers[1] = leader
	end
	for i = #tiers + 1, count do
		tiers[i] = pickTier(h.tiers, rand)
	end
	return {count = count, tiers = tiers, leader = leader, health = h.health or 1, damage = h.damage or 1}
end

-- ------------------------------------------------------------------ the event
-- info = {ownerId, openerId, level (area level), openerLevel, pool, gear, killed, pos, participants = {[id] = true},
-- startedAt (ms)}
function K.newEvent(cfg, info, nowMs)
	local ev = {
		state = "running", ownerId = info.ownerId, openerId = info.openerId, level = info.level,
		openerLevel = info.openerLevel, pool = info.pool, gear = info.gear, killed = info.killed, pos = info.pos,
		participants = info.participants or {}, startedAt = nowMs, horde = 0, lastSpawnAt = nil, lastClearAt = nil,
		claimed = {}, warned = false
	}
	ev.players = 0
	for _ in pairs(ev.participants) do
		ev.players = ev.players + 1
	end
	return ev
end

-- snap = {alive = event monsters alive, inside = participants inside the radius (online, alive, same floor)}
-- Returns a list of actions in order: {"spawn", n}, {"warn"}, {"unwarn"}, {"fail", reason}, {"win"}.
-- The caller applies them and calls K.spawned(ev, n, nowMs) after a spawn. A finished event returns nothing.
function K.step(cfg, ev, snap, nowMs)
	local e = cfg.event
	local out = {}
	if ev.state ~= "running" then
		return out
	end
	if nowMs - ev.startedAt >= e.totalSec * 1000 then
		out[#out + 1] = {"fail", "time"}
		return out
	end
	if (snap.inside or 0) <= 0 then
		ev.emptySince = ev.emptySince or nowMs
		local gone = nowMs - ev.emptySince
		if gone >= e.emptyGraceSec * 1000 then
			out[#out + 1] = {"fail", "abandoned"}
			return out
		end
		if gone >= e.warnSec * 1000 and not ev.warned then
			ev.warned = true
			out[#out + 1] = {"warn"}
		end
	else
		ev.emptySince = nil
		if ev.warned then
			ev.warned = false
			out[#out + 1] = {"unwarn"}
		end
	end
	local total = K.hordeCount(cfg)
	if (snap.alive or 0) == 0 and ev.horde > 0 and not ev.lastClearAt then
		ev.lastClearAt = nowMs
	end
	if ev.horde >= total then
		if (snap.alive or 0) == 0 then
			out[#out + 1] = {"win"}
		end
		return out
	end
	local due = false
	if ev.horde == 0 then
		due = nowMs - ev.startedAt >= e.firstDelayMs
	elseif (snap.alive or 0) == 0 and ev.lastClearAt and nowMs - ev.lastClearAt >= e.betweenMs then
		due = true
	elseif nowMs - ev.lastSpawnAt >= e.hordeTimerSec * 1000 then
		due = true
	end
	if due and (snap.alive or 0) < e.aliveCap then
		out[#out + 1] = {"spawn", ev.horde + 1}
	end
	return out
end

function K.spawned(ev, n, nowMs)
	ev.horde = n
	ev.lastSpawnAt = nowMs
	ev.lastClearAt = nil
end

-- the event is won: the chest waits for its party
function K.win(cfg, ev, nowMs)
	ev.state = "won"
	ev.claimUntil = nowMs + cfg.event.claimSec * 1000
end

function K.fail(ev, reason)
	ev.state = "failed"
	ev.reason = reason
end

-- A player may claim: took part and has not yet. Returns ok, reason.
function K.canClaim(ev, playerId, nowMs)
	if ev.state ~= "won" then
		return false, ev.state == "running" and "running" or "closed"
	end
	if not ev.participants[playerId] then
		return false, "not a participant"
	end
	if ev.claimed[playerId] then
		return false, "claimed"
	end
	if nowMs >= (ev.claimUntil or 0) then
		return false, "closed"
	end
	return true
end

-- marks the claim; false when it was claimed already (no loot twice)
function K.claim(ev, playerId)
	if ev.claimed[playerId] then
		return false
	end
	ev.claimed[playerId] = true
	return true
end

-- every participant claimed, or the time ran out
function K.claimDone(ev, nowMs)
	if ev.state ~= "won" then
		return false
	end
	if nowMs >= (ev.claimUntil or 0) then
		return true
	end
	for id in pairs(ev.participants) do
		if not ev.claimed[id] then
			return false
		end
	end
	return true
end

-- The looks of the chest. cfg.chest.itemIds are the looks a new chest may wear (the one-tile look since pair 53),
-- cfg.chest.legacyItemIds the older looks that still count as a cursed chest when one is already on the map,
-- cfg.chest.itemId the fallback (the Sealed Coffer's chest). exists(id) -> true when the server has that item type (ItemType(id):getId() ~= 0).
-- chestIds: the looks a new chest may wear; the installed ones, else the fallback alone.
function K.chestIds(cfg, exists)
	local out = {}
	for _, id in ipairs(cfg.chest.itemIds or {}) do
		if exists == nil or exists(id) then
			out[#out + 1] = id
		end
	end
	if #out == 0 then
		out[1] = cfg.chest.itemId
	end
	return out
end

-- one look at random: rand(a, b) -> integer in [a, b]
function K.pickChestId(cfg, exists, rand)
	local ids = K.chestIds(cfg, exists)
	return ids[rand(1, #ids)]
end

-- every id that is a cursed chest, whatever look it wears (the looks, the older looks and the fallback)
function K.allChestIds(cfg)
	local out, seen = {}, {}
	for _, list in ipairs({cfg.chest.itemIds or {}, cfg.chest.legacyItemIds or {}}) do
		for _, id in ipairs(list) do
			if not seen[id] then
				seen[id] = true
				out[#out + 1] = id
			end
		end
	end
	if cfg.chest.itemId and not seen[cfg.chest.itemId] then
		out[#out + 1] = cfg.chest.itemId
	end
	return out
end

function K.isChestId(cfg, id)
	for _, v in ipairs(K.allChestIds(cfg)) do
		if v == id then
			return true
		end
	end
	return false
end

-- Who may use the chest: its owner, or someone in the owner's party. info = {userId, ownerId, sameParty}.
function K.mayUse(info)
	return info.userId == info.ownerId or info.sameParty == true
end

-- ------------------------------------------------------------------ the loot
-- gold per hour of hunting at a level: linear between the points, flat beyond
function K.hourlyGold(cfg, level)
	local pts = cfg.loot.hunting
	if level <= pts[1][1] then
		return pts[1][2]
	end
	for i = 2, #pts do
		local a, b = pts[i - 1], pts[i]
		if level <= b[1] then
			return a[2] + (b[2] - a[2]) * (level - a[1]) / (b[1] - a[1])
		end
	end
	return pts[#pts][2]
end

function K.shareOf(cfg, players)
	local ps = cfg.loot.partyShare
	return ps[min(max(1, players or 1), #ps)] or cfg.loot.partyShareMin or 0.4
end

-- gold value of one player's loot
function K.goldValue(cfg, level, players, rand)
	local l = cfg.loot
	local base = K.hourlyGold(cfg, level) * l.goldMinutes / 60 * K.shareOf(cfg, players)
	return floor(base * rand(l.goldMin, l.goldMax) / 100)
end

-- gold value -> {{id, count}, ...} in crystal (2160), platinum (2152) and gold (2148) coins, stacks of at most 100
function K.coins(value)
	local out = {}
	local function add(id, n)
		while n > 0 do
			local c = min(100, n)
			out[#out + 1] = {id = id, count = c}
			n = n - c
		end
	end
	add(2160, floor(value / 10000))
	value = value % 10000
	add(2152, floor(value / 100))
	add(2148, value % 100)
	return out
end

-- a count x share, rounded at random (so a share of 0.5 of one orb is an orb half of the time)
local function share(n, f, rand)
	local x = n * f
	local whole = floor(x)
	if rand(1, 1000) <= floor((x - whole) * 1000 + 0.5) then
		whole = whole + 1
	end
	return whole
end

function K.chaosOrbs(cfg, level, players, rand)
	local o = cfg.loot.chaosOrb
	local n = rand(o.min, o.max) + floor(level / (o.perLevels or 1000000))
	n = min(n, o.cap or n)
	return share(n, K.shareOf(cfg, players), rand)
end

function K.divineOrb(cfg, itemFind, players, rand)
	local chance = cfg.loot.divineOrb.chance * (itemFind or 1) * K.shareOf(cfg, players)
	return rand(1, 10000) <= floor(chance * 100 + 0.5)
end

function K.shardCount(cfg, level, players, rand)
	local s = cfg.loot.shards
	local n = floor((s.base + level / s.perLevel) * K.shareOf(cfg, players))
	return clamp(n, 0, s.cap or n)
end

function K.orbKeys(cfg, rand)
	local o = cfg.loot.orbs
	local out = {}
	if not o or not o.weights or #o.weights == 0 then
		return out
	end
	local total = 0
	for _, w in ipairs(o.weights) do
		total = total + w[2]
	end
	for i = 1, o.count or 0 do
		local roll, acc = rand(1, total), 0
		for _, w in ipairs(o.weights) do
			acc = acc + w[2]
			if roll <= acc then
				out[i] = w[1]
				break
			end
		end
	end
	return out
end

function K.itemCount(cfg, players, rand)
	local it = cfg.loot.items
	return share(rand(it.min, it.max), K.shareOf(cfg, players), rand)
end

function K.pickItemTier(cfg, rand)
	local total = 0
	for _, t in ipairs(cfg.loot.itemTiers) do
		total = total + t.weight
	end
	local roll, acc = rand(1, total), 0
	for _, t in ipairs(cfg.loot.itemTiers) do
		acc = acc + t.weight
		if roll <= acc then
			return t
		end
	end
	return cfg.loot.itemTiers[#cfg.loot.itemTiers]
end

function K.poolFor(cfg, level)
	local best
	for _, band in ipairs(cfg.loot.pool) do
		if level >= band[1] then
			best = band[2]
		end
	end
	return best or {}
end

-- n gear ids: from `gear` (the killed monster's gear ids) when it has any, else from the band's pool
function K.pickGear(cfg, level, gear, n, rand)
	local src = (gear and #gear > 0) and gear or K.poolFor(cfg, level)
	local out = {}
	if #src == 0 then
		return out
	end
	for i = 1, n do
		out[i] = src[rand(1, #src)]
	end
	return out
end

return K
