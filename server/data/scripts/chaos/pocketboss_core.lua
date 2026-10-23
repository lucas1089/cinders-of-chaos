-- Pure logic of the pocket bosses (pocketboss.lua; numbers pocketboss_config.lua; tests/pocketboss_test.lua). No engine
-- calls. Overview: server/README.md "Pocket bosses". Lua 5.1 / LuaJIT and Lua 5.3.
--
--   K.list(cfg, worldBoss, spawnEntries)  -> {list, byKey, byType} of the pocket-able bosses
--   K.dayKey(now, resetHour)              -> YYYYMMDD of the pocket day (the day turns at resetHour:00)
--   K.charges(cfg, row, now)              -> {day, used, bonus, daily, left, max, addedToday}: a row of another day counts
--                                            as a fresh day (the daily charges come back, the bonus stays)
--   K.spend(cfg, row, now)                -> newRow, "daily" | "bonus" | nil, why
--   K.addBonus(cfg, row, n, now)          -> newRow, added, why
--   K.refund(cfg, row, kind, now)         -> newRow (a charge back: only for a restart, never for a logout or a death)
--   K.enterError(info)                    -> nil or why (the opener's checks, in order)
--   K.memberError(info)                   -> nil or why (a party member's checks: they stay behind)
--   K.scale(curve, players)               -> health / damage factor
--   K.scaleExp(exp, mult, rand)           -> experience x mult, rounded at random
--   K.worldReward(r, boss, mult, unique, rand, opts) -> {items, gear, gearRarity, unique} of one player
--   K.islandReward(r, mult, gearIds, cardsByTier, rand) -> {items, gear = {{id, rarity}}, cards = {id}} of one player
--   K.noteEvent(cfg, row, now)            -> the row with eventAt = now (a reward of the boss's event)
--   K.noStackLeft(lastAt, now, seconds)   -> seconds before the pocket of that boss opens again for this player
--   K.contestEligible(stats, maxHealth, cfg, ownerGuid) -> players for a personal loot roll, best first
--   K.personalRoll(loot, mult, rand)      -> {{id, count}} from a monster's loot table
--   K.tidy(rows, levels, sorted)          -> the Boss Spawns rows with their pocket level, sorted categories by level
-- Reasons (why) are {key, args...}: key an English string.format pattern the engine translates (Chaos.t).

ChaosPocketBossCore = ChaosPocketBossCore or {}
local K = ChaosPocketBossCore

local floor, max, min = math.floor, math.max, math.min

-- a reason: the key and its arguments (the engine calls Chaos.t(player, why[1], unpack(why, 2)))
local function T(key, ...)
	return {key, ...}
end
K.T = T

local function lower(s)
	return type(s) == "string" and s:lower() or nil
end

-- ======================================================================== the bosses

-- the category settings of a boss with its key's overrides on top
function K.settings(cfg, category, key)
	local base = (cfg.categories or {})[category]
	if not base then
		return nil
	end
	local out = {}
	for k, v in pairs(base) do
		out[k] = v
	end
	for k, v in pairs((cfg.overrides or {})[key] or {}) do
		out[k] = v
	end
	return out
end

-- worldBoss = Chaos.worldBoss; spawnEntries = the Boss Spawns list (bossspawns_core.lua K.build(...).list): entries
-- {key, category, name, monster, level, look}. World bosses come from worldBoss (keys world_1 .. world_n, as the Boss
-- Spawns window), the rest from the categories of cfg.categories. A missing entry (e.missing) is left out.
function K.list(cfg, worldBoss, spawnEntries)
	local out = {list = {}, byKey = {}, byType = {}, problems = {}}
	local exclude = {}
	for _, k in ipairs(cfg.exclude or {}) do
		exclude[k] = true
	end
	local function add(e)
		if exclude[e.key] or out.byKey[e.key] then
			return
		end
		local s = K.settings(cfg, e.category, e.key)
		if not s then
			return
		end
		local entry = {key = e.key, category = e.category, name = e.name, monster = e.monster, look = e.look,
			minLevel = s.minLevel or e.level or 0, settings = s, worldIndex = e.worldIndex}
		out.list[#out.list + 1] = entry
		out.byKey[e.key] = entry
		local t = lower(e.monster)
		if t then
			out.byType[t] = out.byType[t] or {}
			table.insert(out.byType[t], entry)
		end
	end
	if cfg.categories and cfg.categories.world and type(worldBoss) == "table" then
		for i, b in ipairs(worldBoss.bosses or {}) do
			add({key = "world_" .. i, category = "world", name = b.name, monster = b.name, level = worldBoss.minLevel,
				worldIndex = i})
		end
	end
	for _, e in ipairs(spawnEntries or {}) do
		if type(e) == "table" and e.category ~= "world" and not e.missing and e.monster and e.key then
			add(e)
		end
	end
	return out
end

-- ======================================================================== charges

function K.dayKey(now, resetHour)
	return tonumber(os.date("%Y%m%d", now - (resetHour or 0) * 3600))
end

-- the seconds until the next reset
function K.nextReset(now, resetHour)
	local t = os.date("*t", now - (resetHour or 0) * 3600)
	return os.time({year = t.year, month = t.month, day = t.day + 1, hour = resetHour or 0, min = 0, sec = 0}) - now
end

local function num(v)
	return max(0, floor(tonumber(v) or 0))
end

-- row = {day, used, bonus, bonusDay, bonusAdded} as stored (nil = never)
function K.charges(cfg, row, now)
	local c = cfg.charges or {}
	row = row or {}
	local day = K.dayKey(now, c.resetHour)
	local used = num(row.day) == day and num(row.used) or 0
	local daily = max(0, num(c.daily) - used)
	local bonus = min(num(row.bonus), num(c.bonusMax))
	local addedToday = num(row.bonusDay) == day and num(row.bonusAdded) or 0
	return {day = day, used = used, bonus = bonus, daily = daily, left = daily + bonus, max = num(c.daily),
		addedToday = addedToday, bonusDay = num(row.bonusDay), bonusAdded = num(row.bonusAdded), eventAt = num(row.eventAt)}
end

local function rowOf(s)
	return {day = s.day, used = s.used, bonus = s.bonus, bonusDay = s.bonusDay, bonusAdded = s.bonusAdded, eventAt = s.eventAt}
end

-- the row after the boss's scheduled or contested fight rewarded the player (no stacking; persisted with the charges)
function K.noteEvent(cfg, row, now)
	local out = rowOf(K.charges(cfg, row, now))
	out.eventAt = now
	return out
end

function K.spend(cfg, row, now)
	local s = K.charges(cfg, row, now)
	if s.daily > 0 then
		s.used = s.used + 1
		return rowOf(s), "daily"
	end
	if s.bonus > 0 then
		s.bonus = s.bonus - 1
		return rowOf(s), "bonus"
	end
	return rowOf(s), nil, T("No pocket charges left for this boss today. They come back in %s.",
		K.clockText(K.nextReset(now, (cfg.charges or {}).resetHour)))
end

-- a charge back (a server restart closed the pocket): a daily one of the same day (a new day gave it back already), a
-- bonus one as a bonus charge
function K.refund(cfg, row, kind, now)
	local s = K.charges(cfg, row, now)
	if kind == "daily" then
		-- a new day already gave the daily charges back
		s.used = math.max(0, s.used - 1)
	elseif kind == "bonus" then
		s.bonus = min(s.bonus + 1, num((cfg.charges or {}).bonusMax))
	end
	return rowOf(s)
end

function K.addBonus(cfg, row, n, now)
	local c = cfg.charges or {}
	n = tonumber(n)
	if not n or n ~= n or n < 1 or n ~= floor(n) then
		return row, 0, T("Bad request.")
	end
	local s = K.charges(cfg, row, now)
	local room = min(num(c.bonusPerDay) - s.addedToday, num(c.bonusMax) - s.bonus)
	if room <= 0 then
		return rowOf(s), 0, s.bonus >= num(c.bonusMax) and T("You hold the most bonus charges for this boss (%d).", num(c.bonusMax))
			or T("No more bonus charges for this boss today (%d a day).", num(c.bonusPerDay))
	end
	local add = min(n, room)
	s.bonus = s.bonus + add
	s.bonusDay = s.day
	s.bonusAdded = s.addedToday + add
	return rowOf(s), add
end

-- ======================================================================== entering

-- info = {enabled, boss (entry or nil), level, pz, needPz, inFight, instance (label or nil), dead, multiClient,
-- cooldown (seconds), charges (K.charges), noStack (seconds), busy}
function K.enterError(info)
	if not info.enabled then
		return T("Pocket bosses are switched off.")
	end
	if not info.boss then
		return T("There is no pocket of that boss.")
	end
	if (info.level or 0) < (info.boss.minLevel or 0) then
		return T("You need level %d for the pocket of %s.", info.boss.minLevel, info.boss.name)
	end
	if info.instance then
		return T("Leave %s first.", info.instance)
	end
	if info.needPz and not info.pz then
		return T("Open a pocket from a protection zone.")
	end
	if info.inFight then
		return T("You are in combat.")
	end
	if (info.cooldown or 0) > 0 then
		return T("Wait %d seconds before opening another pocket.", info.cooldown)
	end
	if (info.noStack or 0) > 0 then
		return T("You were rewarded by the %s fight less than an hour ago: its pocket opens for you in %s.", info.boss.name,
			K.clockText(info.noStack))
	end
	if not info.charges or info.charges.left <= 0 then
		return T("No pocket charges left for this boss today. They come back in %s.", K.clockText(info.reset or 0))
	end
	return nil
end

function K.memberError(info)
	if (info.level or 0) < (info.boss.minLevel or 0) then
		return T("level %d needed", info.boss.minLevel)
	end
	if info.instance then
		return T("inside %s", info.instance)
	end
	if info.far then
		return T("too far away")
	end
	if info.inFight then
		return T("in combat")
	end
	if (info.noStack or 0) > 0 then
		return T("rewarded by this boss's event within the hour")
	end
	if not info.charges or info.charges.left <= 0 then
		return T("no charges left")
	end
	return nil
end

-- ======================================================================== the fight

-- curve = {solo, perExtra, max}: solo + perExtra x (players - 1), at most max
function K.scale(curve, players)
	if type(curve) ~= "table" then
		return 1
	end
	local n = max(1, floor(tonumber(players) or 1))
	local f = (curve.solo or 1) + (curve.perExtra or 0) * (n - 1)
	if curve.max then
		f = min(f, curve.max)
	end
	return max(0, f)
end

-- exp x mult, the fraction kept at random (so 0.6 of 1 exp is 1 exp 60% of the time)
function K.scaleExp(exp, mult, rand)
	exp = tonumber(exp) or 0
	if exp <= 0 or mult >= 1 then
		return exp
	end
	local v = exp * max(0, mult)
	local whole = floor(v)
	local frac = v - whole
	if frac > 0 and (rand or math.random)() < frac then
		whole = whole + 1
	end
	return whole
end

-- count x mult with the fraction rolled
local function roundAtRandom(v, rand)
	local whole = floor(v)
	if v - whole > 0 and rand(1000000) <= floor((v - whole) * 1000000) then
		whole = whole + 1
	end
	return whole
end

-- one player's world boss reward in a pocket. r = Chaos.worldBoss.reward, boss = its boss entry (gear list),
-- uniquePool = ids of the uniques that list this boss, rand(n) -> 1..n / rand(a, b) -> a..b
function K.worldReward(r, boss, mult, uniquePool, rand, opts)
	opts = opts or {base = true, gear = true, unique = true}
	local out = {items = {}}
	if opts.base then
		for _, it in ipairs(r.base or {}) do
			local n = roundAtRandom((it.count or 0) * mult, rand)
			if n > 0 then
				out.items[#out.items + 1] = {id = it.id, count = n}
			end
		end
	end
	local gear = boss and boss.gear or {}
	if opts.gear and #gear > 0 and rand(10000) <= floor((r.gearChance or 0) * mult) then
		out.gear = gear[rand(#gear)]
		local lo, hi = (r.gearRarity or {0, 0})[1], (r.gearRarity or {0, 0})[2]
		out.gearRarity = rand(lo, max(lo, hi))
	end
	uniquePool = uniquePool or {}
	if opts.unique and #uniquePool > 0 and rand(10000) <= floor((r.uniqueChance or 0) * mult) then
		out.unique = uniquePool[rand(#uniquePool)]
	end
	return out
end

-- one player's island boss reward in a pocket (pocketboss_config.lua islandReward). r = that table, mult = the pocket's
-- lootMult, gearIds = the gear ids of the boss's loot table (may be empty), cardsByTier = {[1..4] = {card ids}} (may be
-- empty), rand as in worldReward. The base items are x mult rounded at random; every pick draws one pool entry by weight
-- among those that can give something.
function K.islandReward(r, mult, gearIds, cardsByTier, rand)
	r = r or {}
	local out = {items = {}, gear = {}, cards = {}}
	local function add(id, n)
		for _, it in ipairs(out.items) do
			if it.id == id then
				it.count = it.count + n
				return
			end
		end
		out.items[#out.items + 1] = {id = id, count = n}
	end
	for _, it in ipairs(r.base or {}) do
		local n = roundAtRandom((it.count or 0) * mult, rand)
		if n > 0 then
			add(it.id, n)
		end
	end
	local function haveCards()
		for t = 1, 4 do
			if cardsByTier and cardsByTier[t] and #cardsByTier[t] > 0 then
				return true
			end
		end
		return false
	end
	local entries, total = {}, 0
	for _, e in ipairs(r.pool or {}) do
		local w = tonumber(e.weight) or 0
		local usable = w > 0 and (e.kind ~= "gear" or #(gearIds or {}) > 0) and (e.kind ~= "card" or haveCards())
		if usable then
			entries[#entries + 1] = {e = e, w = w}
			total = total + w
		end
	end
	if total <= 0 then
		return out
	end
	for _ = 1, r.picks or 0 do
		local roll, pick = rand(total), nil
		for _, x in ipairs(entries) do
			if roll <= x.w then
				pick = x.e
				break
			end
			roll = roll - x.w
		end
		pick = pick or entries[#entries].e
		if pick.kind == "gear" then
			local lo, hi = (r.rarity or {0, 0})[1], (r.rarity or {0, 0})[2]
			out.gear[#out.gear + 1] = {id = gearIds[rand(#gearIds)], rarity = rand(lo, max(lo, hi))}
		elseif pick.kind == "card" then
			local weights, sum = {}, 0
			for t = 1, 4 do
				local w = (cardsByTier[t] and #cardsByTier[t] > 0) and ((r.cardTiers or {})[t] or 1) or 0
				weights[t] = w
				sum = sum + w
			end
			local tr, tier = rand(sum), 4
			for t = 1, 4 do
				if tr <= weights[t] then
					tier = t
					break
				end
				tr = tr - weights[t]
			end
			local list = cardsByTier[tier]
			out.cards[#out.cards + 1] = list[rand(#list)]
		else
			local c = pick.count or {1, 1}
			add(pick.id, rand(c[1], max(c[1], c[2])))
		end
	end
	return out
end

function K.noStackLeft(lastAt, now, seconds)
	lastAt = tonumber(lastAt)
	if not lastAt or not seconds or seconds <= 0 then
		return 0
	end
	return max(0, lastAt + seconds - now)
end

-- ======================================================================== personal loot of the contested fights

-- stats = {[guid] = {name, damage, healing}}; a player whose damage + healWeight x healing reaches minPercent % of
-- maxHealth gets a roll, the corpse owner excepted (the corpse is theirs). Best first, at most maxPlayers.
function K.contestEligible(stats, maxHealth, cfg, ownerGuid)
	local c = cfg or {}
	local need = (maxHealth or 0) * (c.minPercent or 0) / 100
	local list = {}
	for guid, e in pairs(stats or {}) do
		local score = (e.damage or 0) + (c.healWeight or 1) * (e.healing or 0)
		if guid ~= ownerGuid and score > 0 and score >= need then
			list[#list + 1] = {guid = guid, name = e.name, score = score, damage = e.damage or 0, healing = e.healing or 0}
		end
	end
	table.sort(list, function(a, b)
		if a.score ~= b.score then
			return a.score > b.score
		end
		return a.guid < b.guid
	end)
	local cap = c.maxPlayers or #list
	while #list > cap do
		list[#list] = nil
	end
	return list
end

-- loot = {{id = itemId, chance = 0..100000, maxCount = n}} (MonsterType:getLoot() as the base server reads it);
-- every entry rolled with chance x mult; nested containers are left out
function K.personalRoll(loot, mult, rand)
	local out = {}
	for _, e in ipairs(loot or {}) do
		local id = tonumber(e.itemId or e.id)
		local chance = floor((tonumber(e.chance) or 0) * (mult or 1))
		if id and id > 0 and chance > 0 and rand(100000) <= chance then
			local cmax = max(1, floor(tonumber(e.maxCount or e.countmax) or 1))
			out[#out + 1] = {id = id, count = cmax > 1 and rand(1, cmax) or 1}
		end
	end
	return out
end

-- ======================================================================== after the kill (beta 2026-10-20)
-- A pocket spawns the boss's own monster type outside its home: a boss whose loot is not a corpse of its own (the base
-- server's reward bosses: the loot goes to a reward chest of its home room) left nothing, and a boss whose death opens
-- its home's way on (stairs, a teleport, made by its own death script) put that way into the pocket, where it leads
-- nowhere. info = {rewardBoss = bool, corpseItems = items in the corpse at the death (nil: no corpse), lootEntries =
-- entries of its loot table}. True when the players get a personal roll of the loot table instead.
function K.needsFallbackLoot(info)
	info = info or {}
	if (info.lootEntries or 0) <= 0 then
		return false
	end
	return info.rewardBoss == true or info.corpseItems == nil or info.corpseItems <= 0
end

-- the tiles of the pocket after the kill that hold a way out the pocket did not make: tiles = {{x, y, exit = bool (a
-- teleport or a floor change on it)}}, gates = {["x,y"] = true} (the pocket's two forcefields). -> the tiles to clean
function K.foreignExits(tiles, gates)
	local out = {}
	for _, t in ipairs(tiles or {}) do
		if t.exit and not (gates or {})[t.x .. "," .. t.y] then
			out[#out + 1] = t
		end
	end
	return out
end

-- the arena's own way out, chosen before the room is painted (so no decoration lands on it): the floor tile nearest to
-- `from` (the arrival) at Chebyshev distance >= 2 that is not taken ({["x,y"] = true}); first in list order on a tie
function K.arenaGate(floorList, from, taken)
	local best, bestD
	for _, t in ipairs(floorList or {}) do
		local d = max(math.abs(t.x - from.x), math.abs(t.y - from.y))
		if d >= 2 and not (taken or {})[t.x .. "," .. t.y] and (not bestD or d < bestD) then
			best, bestD = t, d
		end
	end
	return best
end

-- ======================================================================== the Boss Spawns list
-- rows = the Boss Spawns payload rows ({k, c, n, ...}), levels = {key -> pocket level}, sorted = {category -> true}:
-- every pocket row gets pl (its pocket level); the rows of a sorted category go by pocket level, then name; every other
-- row keeps its place (the categories keep their order: the window groups the rows by category anyway)
function K.tidy(rows, levels, sorted)
	local catOrder, pos = {}, {}
	for i, r in ipairs(rows) do
		if catOrder[r.c] == nil then
			catOrder[r.c] = i
		end
		pos[r] = i
		local lv = levels[r.k]
		if lv then
			r.pl = lv
		end
	end
	table.sort(rows, function(a, b)
		if a.c ~= b.c then
			return catOrder[a.c] < catOrder[b.c]
		end
		if sorted[a.c] then
			local la, lb = a.pl or a.lv or 0, b.pl or b.lv or 0
			if la ~= lb then
				return la < lb
			end
			local na, nb = tostring(a.n or ""):lower(), tostring(b.n or ""):lower()
			if na ~= nb then
				return na < nb
			end
		end
		return pos[a] < pos[b]
	end)
	return rows
end

-- ======================================================================== text

function K.clockText(secs)
	secs = max(0, floor(tonumber(secs) or 0))
	local h, m = floor(secs / 3600), floor(secs % 3600 / 60)
	if h > 0 then
		return string.format("%dh %02dm", h, m)
	end
	if m > 0 then
		return string.format("%dm %02ds", m, secs % 60)
	end
	return string.format("%ds", secs)
end

-- the window's view of one player: {key = {l = left, m = daily max, b = bonus}} and the seconds to the reset
function K.view(cfg, index, rows, now, level)
	local out = {}
	for _, b in ipairs(index.list) do
		local s = K.charges(cfg, rows[b.key], now)
		out[b.key] = {l = s.left, m = s.max, b = s.bonus, lv = b.minLevel, ok = (level or 0) >= (b.minLevel or 0) and 1 or nil}
	end
	return {bosses = out, reset = K.nextReset(now, (cfg.charges or {}).resetHour)}
end

return K
