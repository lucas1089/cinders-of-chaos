-- Bounty board: pure logic (no engine calls), shared by bounty.lua and server/tests/bounty_test.lua.
--   ChaosBounty.day(t, cfg)            bounty day (YYYYMMDD) of unix time t; the day starts at cfg.rollHour
--   ChaosBounty.nextRoll(t, cfg)       unix time of the next roll
--   ChaosBounty.week(t, cfg)           bounty day of the Monday that starts t's bounty week
--   ChaosBounty.roll(day, cfg, pool)   the board of a day: {day, bands = {{index, min, max, contracts}}, byName}
--   ChaosBounty.bandOf(level, cfg)     band index of a level; visibleBands(level, cfg) -> {indexes}
--   ChaosBounty.matches(c, name, tier) whether a kill counts for contract c
--   ChaosBounty.credit(killers, membersOf, posOf, range, idOf) players a kill counts for (own + party in range)
--   ChaosBounty.addKill(entry)         progress +1, returns crossed milestone percents and completion
--   ChaosBounty.reward(c, cfg, level)  {gold, chaos, divine, exp}
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

function B.reward(c, cfg, playerLevel)
	local band = cfg.bands[c.band]
	local mult = cfg.typeMult[c.type] or 1
	local r = band.reward
	local level = math.max(1, math.min(playerLevel or band.min, band.max))
	return {
		gold = math.floor((r.gold or 0) * mult),
		chaos = math.floor((r.chaos or 0) * mult),
		divine = (r.divine or 0) > 0 and math.ceil(r.divine * mult) or 0,
		exp = math.floor(B.expForLevel(level) * (cfg.expPercent[c.type] or 0) / 100)
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
