-- Bounty board: pure logic (no engine calls), shared by bounty.lua and server/tests/bounty_test.lua.
--   ChaosBounty.day(t, cfg)            bounty day (YYYYMMDD) of unix time t; the day starts at cfg.rollHour
--   ChaosBounty.nextRoll(t, cfg)       unix time of the next roll
--   ChaosBounty.week(t, cfg)           bounty day of the Monday that starts t's bounty week
--   ChaosBounty.roll(day, cfg, pool)   the board of a day: {day, bands = {{index, min, max, contracts}}, byName}
--   ChaosBounty.bandOf(level, cfg)     band index of a level; visibleBands(level, cfg) -> {indexes}
--   ChaosBounty.matches(c, name, tier) whether a kill counts for contract c
--   ChaosBounty.credit(killers, membersOf, posOf, range, idOf) players a kill counts for (own + party in range)
--   ChaosBounty.partyCounts(c, cfg, level) whether a party member's (not a killer's) kill credit counts for c
--   ChaosBounty.addKill(entry)         progress +1, returns crossed milestone percents and completion
--   ChaosBounty.reward(c, cfg, level, stage, huntMean)  {gold, chaos, divine, exp}; exp: B.expReward (a share of the
--                                      kills' experience; elite and boss at least huntMean, B.huntMean)
--   ChaosBounty.canAccept(...)         the accept rules (limit, visibility, duplicates)
-- The roll uses its own generator (MINSTD), so the board is the same on every restart, on LuaJIT and Lua 5.3:
-- it depends only on the day, the config and the pool.

ChaosBounty = ChaosBounty or {}
local B = ChaosBounty

B.TIER_RANK = {normal = 0, magic = 1, rare = 2, legendary = 3}

-- ---------------------------------------------------------------- random numbers (deterministic)
-- Park-Miller "minimal standard": state * 48271 stays below 2^53, so doubles (LuaJIT) and integers (5.3) agree.
function B.rng(seed)
	local m = 2147483647
	local state = math.floor(seed) % (m - 1) + 1
	local function nextValue()
		state = (state * 48271) % m
		return state
	end
	for _ = 1, 3 do
		nextValue()
	end
	return function(a, b)
		local v = nextValue()
		if not a then
			return v
		end
		return a + v % (b - a + 1)
	end
end

-- ---------------------------------------------------------------- days and weeks
local function dayKeyOf(t)
	return tonumber(os.date("%Y%m%d", t))
end

function B.day(t, cfg)
	return dayKeyOf(t - cfg.rollHour * 3600)
end

function B.nextRoll(t, cfg)
	local d = os.date("*t", t - cfg.rollHour * 3600)
	return os.time({year = d.year, month = d.month, day = d.day + 1, hour = cfg.rollHour, min = 0, sec = 0})
end

-- bounty day of the Monday of t's bounty week
function B.week(t, cfg)
	local d = os.date("*t", t - cfg.rollHour * 3600)
	local back = (d.wday + 5) % 7 -- wday 1 = Sunday: Monday -> 0, Sunday -> 6
	return dayKeyOf(os.time({year = d.year, month = d.month, day = d.day - back, hour = 12}))
end

-- ---------------------------------------------------------------- bands
function B.bandOf(level, cfg)
	local bands = cfg.bands
	for i, band in ipairs(bands) do
		if level <= band.max then
			return i
		end
	end
	return #bands
end

function B.visibleBands(level, cfg)
	local own = B.bandOf(level, cfg)
	local list = {}
	for i = math.max(1, own - cfg.visibleAround), math.min(#cfg.bands, own + cfg.visibleAround) do
		list[#list + 1] = i
	end
	return list, own
end

function B.bandLabel(band)
	if band.max >= 999999 then
		return string.format("Level %d+", band.min)
	end
	return string.format("Level %d-%d", band.min, band.max)
end

-- ---------------------------------------------------------------- the roll
local function inWindow(entry, window)
	return entry.level >= window[1] and entry.level <= window[2]
end

local function candidates(list, window, minSpawns, used)
	local out = {}
	for _, e in ipairs(list or {}) do
		if inWindow(e, window) and (e.spawns or 0) >= (minSpawns or 0) and not used[e.name:lower()] then
			out[#out + 1] = e
		end
	end
	return out
end

local function roundTo(n, step)
	return math.max(step, math.floor(n / step + 0.5) * step)
end

local function pickWeighted(rand, list)
	local total = 0
	for _, e in ipairs(list) do
		total = total + e.weight
	end
	local roll = rand(1, total)
	for _, e in ipairs(list) do
		roll = roll - e.weight
		if roll <= 0 then
			return e
		end
	end
	return list[#list]
end

local function contractOf(bandIndex, slot, kind, mon)
	local c = {
		key = bandIndex .. "-" .. slot,
		band = bandIndex,
		slot = slot,
		type = kind,
		name = mon.name,
		level = mon.level,
		exp = mon.exp,
		health = mon.health,
		look = mon.look or 0
	}
	if mon.head then
		c.outfit = {head = mon.head, body = mon.body, legs = mon.legs, feet = mon.feet, addons = mon.addons}
	end
	return c
end

function B.rollBand(day, bandIndex, cfg, pool)
	local band = cfg.bands[bandIndex]
	local rand = B.rng(day * 31 + bandIndex * 7919)
	local used, contracts = {}, {}
	for slot, kind in ipairs(cfg.slots) do
		local c
		if kind == "boss" then
			local list = candidates(pool.bosses, band.pick, 0, used)
			if #list > 0 then
				local mon = list[rand(1, #list)]
				c = contractOf(bandIndex, slot, "boss", mon)
				c.count = rand(cfg.bossCount[1], cfg.bossCount[2])
			else
				kind = "hunt"
			end
		elseif kind == "elite" then
			local list = candidates(pool.hunt, band.pick, cfg.eliteMinSpawns, used)
			if #list > 0 then
				local mon = list[rand(1, #list)]
				local e = pickWeighted(rand, cfg.elite)
				c = contractOf(bandIndex, slot, "elite", mon)
				c.tier = e.tier
				c.count = rand(e.count[1], e.count[2])
				-- pack combat (pace): the monster's kill-goal factor (cfg.goalMult, set by bounty.lua; 1 without it)
				local g = cfg.goalMult and cfg.goalMult(mon) or 1
				if g > 1 then
					c.count = math.max(c.count, math.floor(c.count * g + 0.5))
				end
			else
				kind = "hunt"
			end
		end
		if kind == "hunt" then
			local list = candidates(pool.hunt, band.pick, 0, used)
			if #list > 0 then
				local mon = list[rand(1, #list)]
				c = contractOf(bandIndex, slot, "hunt", mon)
				local n = rand(band.kills[1], band.kills[2])
				-- pack combat (pace): x the monster's kill-goal factor (cfg.goalMult, set by bounty.lua; 1 without it)
				local g = cfg.goalMult and cfg.goalMult(mon) or 1
				if g > 1 then
					n = n * g
				end
				if (mon.spawns or 0) < cfg.fewSpawns then
					c.count = roundTo(n * cfg.fewSpawnsMult, 5)
				else
					c.count = roundTo(n, 10)
				end
			end
		end
		if c then
			used[c.name:lower()] = true
			contracts[#contracts + 1] = c
		end
	end
	return contracts
end

-- a reroll (2026-10-15, bounty rerolls bought with Candlemarks): another monster for an accepted contract `c`, same
-- band, slot, type and elite tier, picked by the board's own rules (the count too), never a name of `avoid` (lower case
-- names: the band's board and the player's other contracts) nor c's own monster. nil when nothing else fits.
function B.rerollContract(c, cfg, pool, avoid, rand)
	local band = c and cfg.bands[c.band]
	if not band then
		return nil
	end
	local used = {[c.name:lower()] = true}
	for name in pairs(avoid or {}) do
		used[name] = true
	end
	local nc
	if c.type == "boss" then
		local list = candidates(pool.bosses, band.pick, 0, used)
		if #list == 0 then
			return nil
		end
		nc = contractOf(c.band, c.slot, "boss", list[rand(1, #list)])
		nc.count = rand(cfg.bossCount[1], cfg.bossCount[2])
	elseif c.type == "elite" then
		local list = candidates(pool.hunt, band.pick, cfg.eliteMinSpawns, used)
		if #list == 0 then
			return nil
		end
		local mon = list[rand(1, #list)]
		local e = cfg.elite[1]
		for _, x in ipairs(cfg.elite) do
			if x.tier == c.tier then
				e = x
			end
		end
		nc = contractOf(c.band, c.slot, "elite", mon)
		nc.tier = c.tier or e.tier
		nc.count = rand(e.count[1], e.count[2])
		local g = cfg.goalMult and cfg.goalMult(mon) or 1
		if g > 1 then
			nc.count = math.max(nc.count, math.floor(nc.count * g + 0.5))
		end
	else
		local list = candidates(pool.hunt, band.pick, 0, used)
		if #list == 0 then
			return nil
		end
		local mon = list[rand(1, #list)]
		nc = contractOf(c.band, c.slot, c.type, mon)
		local n = rand(band.kills[1], band.kills[2])
		local g = cfg.goalMult and cfg.goalMult(mon) or 1
		if g > 1 then
			n = n * g
		end
		nc.count = (mon.spawns or 0) < cfg.fewSpawns and roundTo(n * cfg.fewSpawnsMult, 5) or roundTo(n, 10)
	end
	return nc
end

-- the contract a player really holds: the board's `c`, or after a reroll (entry e names another monster) a copy with
-- that monster (find(name) -> its pool entry, for the look and level) and the entry's count
function B.overrideOf(c, e, find)
	if not c or not e or type(e.monster) ~= "string" or e.monster:lower() == c.name:lower() then
		return c
	end
	local mon = find and find(e.monster) or nil
	local nc = contractOf(c.band, c.slot, c.type, mon or {name = e.monster, level = c.level, look = 0})
	nc.tier = c.tier
	nc.count = e.required or c.count
	nc.rerolled = true
	return nc
end

function B.roll(day, cfg, pool)
	local board = {day = day, bands = {}, byKey = {}, byName = {}}
	for i, band in ipairs(cfg.bands) do
		local contracts = B.rollBand(day, i, cfg, pool)
		board.bands[i] = {index = i, min = band.min, max = band.max, label = B.bandLabel(band), contracts = contracts}
		for _, c in ipairs(contracts) do
			board.byKey[c.key] = c
			local name = c.name:lower()
			board.byName[name] = board.byName[name] or {}
			table.insert(board.byName[name], c)
		end
	end
	return board
end

-- ---------------------------------------------------------------- kills
function B.matches(c, name, tier)
	if not c or c.name:lower() ~= tostring(name):lower() then
		return false
	end
	if c.type == "elite" then
		return (B.TIER_RANK[tier or "normal"] or 0) >= (B.TIER_RANK[c.tier] or 1)
	end
	return true
end

function B.inRange(a, b, range)
	return a and b and a.z == b.z and math.max(math.abs(a.x - b.x), math.abs(a.y - b.y)) <= range
end

-- killers: players that made the kill (last hit and most damage, summons already resolved to their master).
-- membersOf(p) -> the party of p (all members, leader included) or nil; posOf(p) -> position; idOf(p) -> unique id.
-- Returns every killer and every party member of a killer within range of that killer, each once.
function B.credit(killers, membersOf, posOf, range, idOf)
	local out, seen = {}, {}
	local function add(p)
		local id = idOf(p)
		if not seen[id] then
			seen[id] = true
			out[#out + 1] = p
		end
	end
	for _, k in ipairs(killers) do
		add(k)
	end
	for _, k in ipairs(killers) do
		local members = membersOf(k)
		if members then
			local kp = posOf(k)
			for _, m in ipairs(members) do
				if B.inRange(kp, posOf(m), range) then
					add(m)
				end
			end
		end
	end
	return out
end

-- entry = {progress, required, status}; status 0 = active, 1 = completed
function B.addKill(entry, notices)
	if entry.status ~= 0 then
		return nil, false
	end
	local before = entry.progress
	entry.progress = math.min(entry.required, before + 1)
	local crossed = {}
	for _, pct in ipairs(notices or {}) do
		local at = math.ceil(entry.required * pct / 100)
		if at < entry.required and before < at and entry.progress >= at then
			crossed[#crossed + 1] = pct
		end
	end
	local done = entry.progress >= entry.required
	if done then
		entry.status = 1
	end
	return crossed, done
end

-- ---------------------------------------------------------------- rewards
-- experience from level L to L + 1 (the engine's formula)
function B.expForLevel(level)
	return 50 * level * level - 50 * level + 100
end

-- the base experience of one kill of contract c's monster before the stage and the tier, as the engine gives it: the
-- monster's experience x the engine's monster level factor (x0.03 L when that is above 1, level-scaled monsters only:
-- base data/events/scripts/player.lua, checked on the test server, server/README.md "Late game"; xpcap_core.lua
-- X.levelFactor) x the pace experience curve of its hunting level (pace_core.lua; bosses are never paced).
-- P = ChaosPaceCore, pc = the pace config (nil: no pace and no level information). bounty.lua uses it as cfg.killBase,
-- bestiary.lua for kill tasks (an entry {exp, health, level, minLevel, maxLevel, boss}).
function B.monsterKillBase(c, P, pc)
	local exp = tonumber(c and c.exp) or 0
	if exp <= 0 then
		return 0
	end
	if not P or not pc then
		return exp
	end
	local level, scaled = P.entryLevel(pc, c)
	if scaled and level * 0.03 > 1 then
		exp = exp * level * 0.03
	end
	if c.type == "boss" or c.boss then
		return exp
	end
	return exp * P.factors(pc, level, scaled).xp
end

-- the base experience of the kills a player makes for contract c, with experience stage `stage` (Game.getExperienceStage
-- of the player's level): one kill's base (cfg.killBase(c), else the pool experience) x stage x the kills. A hunt or boss
-- contract: its count. An elite contract: each counted kill gives its tier's experience (cfg.tierXp, the lowest tier that
-- counts) and comes after cfg.eliteSearch[tier] - 1 kills of the type that do not count (the tier's spawn chance).
-- No bonus (potion, stamina, world, multikill ...) is counted.
function B.contractKillExp(c, cfg, stage)
	local per = cfg.killBase and cfg.killBase(c) or tonumber(c.exp) or 0
	local kills = c.count or 0
	if c.type == "elite" then
		local tier = c.tier or "magic"
		local tierXp = cfg.tierXp and cfg.tierXp[tier] or 1
		local search = cfg.eliteSearch and cfg.eliteSearch[tier] or 1
		kills = kills * (tierXp + math.max(0, search - 1))
	end
	return kills * per * (tonumber(stage) or 1)
end

-- party credit (B.credit): a kill counts for a party member who did not make it only when the member's level is at
-- least the contract band's min level, so a low character cannot finish a higher band's contract by standing next to a
-- strong one (own kills always count)
function B.partyCounts(c, cfg, level)
	local band = c and cfg.bands[c.band]
	return band ~= nil and (tonumber(level) or 0) >= band.min
end

-- `exp` between expFloor and expCap percent of the experience from level L to L + 1, L = min(player level, band max)
local function clampExp(exp, c, cfg, playerLevel)
	local band = cfg.bands[c.band]
	local level = math.max(1, math.min(playerLevel or band.min, band.max))
	local lvlExp = B.expForLevel(level)
	local floorPct = cfg.expFloor and cfg.expFloor[c.type]
	if floorPct then
		exp = math.max(exp, lvlExp * floorPct / 100)
	end
	local cap = cfg.expCap and cfg.expCap[c.type]
	if cap then
		exp = math.min(exp, lvlExp * cap / 100)
	end
	return math.floor(exp)
end

-- experience of a finished contract for a player of playerLevel with experience stage `stage`: expShare percent of
-- the base experience of its kills (B.contractKillExp), at least expFloor and at most expCap percent of the experience
-- from level L to L + 1, L = min(player level, band max level). An elite or boss contract pays at least `huntMean`
-- (B.huntMean: the mean hunt reward of its band for this player), still at most the cap.
function B.expReward(c, cfg, playerLevel, stage, huntMean)
	local exp = B.contractKillExp(c, cfg, stage) * (cfg.expShare[c.type] or 0) / 100
	if c.type ~= "hunt" and huntMean then
		exp = math.max(exp, huntMean)
	end
	return clampExp(exp, c, cfg, playerLevel)
end

-- the median base experience (stage 1) of a hunt contract of a band, over the pool's hunt monsters of the band's pick
-- window at the middle of the band's kill range (x the pace goal, fewer for few spawns, as rollBand). Cached per band.
local medianCache = setmetatable({}, {__mode = "k"}) -- [cfg][pool][band]

function B.huntPoolMedian(bandIndex, cfg, pool)
	medianCache[cfg] = medianCache[cfg] or setmetatable({}, {__mode = "k"})
	local byPool = medianCache[cfg]
	byPool[pool] = byPool[pool] or {}
	local cache = byPool[pool]
	if cache[bandIndex] then
		return cache[bandIndex]
	end
	local band = cfg.bands[bandIndex]
	local list = {}
	for _, mon in ipairs(pool and pool.hunt or {}) do
		if band and mon.level >= band.pick[1] and mon.level <= band.pick[2] then
			local c = contractOf(bandIndex, 0, "hunt", mon)
			local n = (band.kills[1] + band.kills[2]) / 2
			local g = cfg.goalMult and cfg.goalMult(mon) or 1
			if g > 1 then
				n = n * g
			end
			if (mon.spawns or 0) < cfg.fewSpawns then
				n = n * cfg.fewSpawnsMult
			end
			c.count = n
			list[#list + 1] = B.contractKillExp(c, cfg, 1)
		end
	end
	table.sort(list)
	local m = #list > 0 and list[math.floor((#list + 1) / 2)] or 0
	cache[bandIndex] = m
	return m
end

-- the mean experience reward of the hunt contracts of c's band for a player (level, stage): the board's hunts of that
-- band (`hunts`, a list of contracts; the board is the same for everyone), else the band's pool median (B.huntPoolMedian).
-- nil for a hunt contract.
function B.huntMean(c, cfg, playerLevel, stage, hunts, pool)
	if not c or c.type == "hunt" then
		return nil
	end
	local sum, n = 0, 0
	for _, h in ipairs(hunts or {}) do
		if h.type == "hunt" and h.band == c.band then
			sum = sum + B.expReward(h, cfg, playerLevel, stage)
			n = n + 1
		end
	end
	if n > 0 then
		return sum / n
	end
	if not pool then
		return nil
	end
	local h = {band = c.band, type = "hunt"}
	return clampExp(B.huntPoolMedian(c.band, cfg, pool) * (tonumber(stage) or 1) * (cfg.expShare.hunt or 0) / 100, h,
		cfg, playerLevel)
end

function B.reward(c, cfg, playerLevel, stage, huntMean)
	local band = cfg.bands[c.band]
	local mult = cfg.typeMult[c.type] or 1
	local r = band.reward
	return {
		gold = math.floor((r.gold or 0) * mult),
		chaos = math.floor((r.chaos or 0) * mult),
		divine = (r.divine or 0) > 0 and math.ceil(r.divine * mult) or 0,
		exp = B.expReward(c, cfg, playerLevel, stage, huntMean)
	}
end

function B.weeklyReward(bandIndex, cfg)
	local band = cfg.bands[math.max(1, math.min(#cfg.bands, bandIndex))]
	return {chaos = band.weekly.chaos or 0, divine = band.weekly.divine or 0}
end

-- ---------------------------------------------------------------- accepting
-- entries: {[key] = {status, day}} of the player for `day`; visible: list of band indexes the player sees.
function B.activeCount(entries, day)
	local n = 0
	for _, e in pairs(entries) do
		if e.status == 0 and e.day == day then
			n = n + 1
		end
	end
	return n
end

function B.canAccept(board, entries, key, visible, cfg)
	local c = board.byKey[key]
	if not c then
		return false, "That contract is not on today's board."
	end
	local seen = false
	for _, i in ipairs(visible) do
		if i == c.band then
			seen = true
		end
	end
	if not seen then
		return false, "That contract is not for your level."
	end
	local e = entries[key]
	if e and e.day == board.day then
		return false, e.status == 1 and "You already completed that contract today." or "You already accepted that contract."
	end
	if B.activeCount(entries, board.day) >= cfg.maxActive then
		return false, string.format("You can hold at most %d contracts at once.", cfg.maxActive)
	end
	return true, c
end

-- drops entries of other days (expired at the roll); returns the number dropped
function B.expire(entries, day)
	local n = 0
	for key, e in pairs(entries) do
		if e.day ~= day then
			entries[key] = nil
			n = n + 1
		end
	end
	return n
end

return B
