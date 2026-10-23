-- The weekly guild boss: the pure part (no engine calls), shared by guildboss.lua and tests/guildboss_test.lua.
-- Numbers: guildboss_config.lua. Overview: server/README.md "The weekly guild boss". The arena geometry, the telegraph
-- shapes, the phase machine and the lethal-hit catch are uber_core.lua's (U.layout / U.pattern / U.markPlan /
-- U.advancePhase / U.clock / U.catchDamage with this config); this file holds what is the guild's own.
--   week       B.weekKey(cfg, t), B.nextReset(cfg, t)
--   fuel       B.need(level, cfg), B.goldEmbers(amount, cfg), B.material(cfg, key), B.materialEmbers(def, count, cfg),
--              B.fuelAfterFail(fuel, need, cfg)
--   summon     B.summonError(info, cfg)
--   scaling    B.healthMult(cfg, players), B.addHealthMult(cfg, players), B.livesFor(cfg, players), B.killTime(cfg, players)
--   rewards    B.rewarded(damage, healers, present, cfg), B.goldPool(n, cfg), B.splitGold(pool, winners, damage, healing, cfg),
--              B.gxp(players, cfg), B.banner(kills, cfg)
--   board      B.rankGuilds(rows)
--   texts      B.clockText(s), B.money(n)
-- Lua 5.1 / LuaJIT and Lua 5.3.

ChaosGuildBossCore = ChaosGuildBossCore or {}
local B = ChaosGuildBossCore

local floor = math.floor

function B.money(n)
	n = floor(tonumber(n) or 0)
	local s = tostring(math.abs(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if out:sub(1, 1) == "," then
		out = out:sub(2)
	end
	return (n < 0 and "-" or "") .. out
end

function B.clockText(secs)
	secs = math.max(0, floor(secs or 0))
	return string.format("%d:%02d", floor(secs / 60), secs % 60)
end

-- ---------------------------------------------------------------- week
-- YYYYMMDD of the day the week of t started (resetDay at resetHour, server time)
function B.weekKey(cfg, t)
	local day, hour = cfg.resetDay or 2, cfg.resetHour or 6
	local d = os.date("*t", t - hour * 3600)
	local back = (d.wday - day + 7) % 7
	local s = os.date("*t", os.time({year = d.year, month = d.month, day = d.day - back, hour = 12}))
	return s.year * 10000 + s.month * 100 + s.day
end

function B.nextReset(cfg, t)
	local w = B.weekKey(cfg, t)
	local y, m, d = floor(w / 10000), floor(w / 100) % 100, w % 100
	return os.time({year = y, month = m, day = d + 7, hour = cfg.resetHour or 6, min = 0, sec = 0})
end

-- ---------------------------------------------------------------- fuel
function B.need(level, cfg)
	local n = cfg.need or {}
	return (n.base or 0) + (n.perLevel or 0) * math.max(1, floor(tonumber(level) or 1))
end

-- gold -> embers: whole embers only. Returns embers, the gold that buys them (a multiple of perEmber), or nil + why.
function B.goldEmbers(amount, cfg)
	local g = cfg.gold or {}
	amount = tonumber(amount)
	if not amount or amount ~= amount or amount == math.huge then
		return nil, "Donate how much?"
	end
	amount = floor(amount)
	if amount < (g.min or 0) then
		return nil, string.format("Donate at least %s gold.", B.money(g.min or 0))
	end
	local embers = floor(amount / g.perEmber)
	if embers <= 0 then
		return nil, "That is not enough for one ember."
	end
	return embers, embers * g.perEmber
end

function B.material(cfg, key)
	for _, m in ipairs(cfg.materials or {}) do
		if m.key == key or m.id == key then
			return m
		end
	end
	return nil
end

-- count = what the member carries; returns the items taken (capped) and their embers
function B.materialEmbers(def, count, cfg)
	count = math.max(0, floor(tonumber(count) or 0))
	local take = math.min(count, cfg.maxPerDonation or count)
	return take, take * (def.embers or 0)
end

-- the fuel after a failed attempt: what was left over the need, plus failKeep of the need
function B.fuelAfterFail(fuel, need, cfg)
	return math.max(0, floor(fuel or 0)) + floor((need or 0) * (cfg.failKeep or 0))
end

-- ---------------------------------------------------------------- summon
-- info = {enabled, guildId, rank, hasHall, rentLocked, inHall, fuel, need, killed, attempts, players, running, inside}
function B.summonError(info, cfg)
	if not cfg.enabled or info.enabled == false then
		return "The guild boss sleeps (disabled)."
	end
	if not info.guildId or info.guildId == 0 then
		return "You are not in a guild."
	end
	if (info.rank or 0) < (cfg.summonRank or 2) then
		return "Only the guild leader or a vice-leader can summon the guild boss."
	end
	if not info.hasHall then
		return "The Summoning Stone stands in a guild hall: your guild has none."
	end
	if info.rentLocked then
		return "The hall's rent is unpaid: the Summoning Stone is cold."
	end
	if not info.inHall then
		return "Stand in your guild hall to summon the guild boss."
	end
	local beta = ChaosBetaMode and ChaosBetaMode.lifted("guildboss_weekly") -- beta test mode: no weekly limits
	if info.killed and not beta then
		return "Your guild already slew the guild boss this week."
	end
	if info.running then
		return "Your guild is fighting the guild boss right now."
	end
	if (info.attempts or 0) >= (cfg.maxAttempts or 3) and not beta then
		return string.format("Your guild used its %d summons this week.", cfg.maxAttempts or 3)
	end
	if (info.fuel or 0) < (info.need or 0) then
		return string.format("The stone holds %s of %s embers.", B.money(info.fuel or 0), B.money(info.need or 0))
	end
	if (info.players or 0) < (cfg.minPlayers or 1) then
		return string.format("At least %d members (level %d+) must stand in the hall.", cfg.minPlayers or 1, cfg.minLevel or 1)
	end
	return nil
end

-- ---------------------------------------------------------------- scaling
function B.healthMult(cfg, players)
	return 1 + (cfg.boss.healthPerExtraPlayer or 0) * (math.max(1, tonumber(players) or 1) - 1)
end

function B.addHealthMult(cfg, players)
	return 1 + (cfg.addHealthPerExtraPlayer or 0) * (math.max(1, tonumber(players) or 1) - 1)
end

function B.livesFor(cfg, players)
	local l = cfg.lives or {}
	players = math.max(1, tonumber(players) or 1)
	return math.max(1, (l.base or 3) + floor((players - 1) / math.max(1, l.perPlayers or 3)))
end

-- seconds to kill with `players` characters dealing model.refDps at model.uptime
function B.killTime(cfg, players)
	local m = cfg.model
	players = math.max(1, players or 1)
	return cfg.bossHealth * B.healthMult(cfg, players) / (players * m.refDps * m.uptime)
end

-- ---------------------------------------------------------------- rewards
-- damage = {[guid] = damage to the boss}, healers = {[guid] = true}, present = {[guid] = true} (in the run at the
-- kill). Returns the set of rewarded guids: present and (damage share >= minDamageShare or a healer).
function B.rewarded(damage, healers, present, cfg)
	local total = 0
	for _, d in pairs(damage or {}) do
		total = total + math.max(0, d)
	end
	local share = (cfg.reward and cfg.reward.minDamageShare) or 0
	local out = {}
	for guid in pairs(present or {}) do
		local d = (damage or {})[guid] or 0
		if (healers and healers[guid]) or (total > 0 and d / total >= share) or (total == 0 and share <= 0) then
			out[guid] = true
		end
	end
	return out
end

-- the kill's gold: one pool for the guild, reward.pool.perPlayer per rewarded participant, counted up to
-- reward.pool.maxPlayers (5 rewarded: 7,500,000; 10 or more: 15,000,000)
function B.goldPool(n, cfg)
	local p = (cfg.reward and cfg.reward.pool) or {}
	n = math.max(0, floor(tonumber(n) or 0))
	return floor((p.perPlayer or 0) * math.min(n, p.maxPlayers or n))
end

-- The pool split among the rewarded guids (winners = {[guid] = true}) by contribution: damage to the boss plus
-- reward.healWeight x the healing done to the other participants. Every winner first gets the floor,
-- floor(pool x reward.floorShare / n); the rest goes in proportion to the contribution (an even split when nobody has
-- any), rounded down, and the rounding remainder goes to the top contributor: the shares sum to the pool exactly.
-- Returns shares {[guid] = gold} and the list {{guid, gold, weight}} from the top contributor down.
function B.splitGold(pool, winners, damage, healing, cfg)
	local r = cfg.reward or {}
	pool = math.max(0, floor(tonumber(pool) or 0))
	local hw = r.healWeight or 1
	local list, total = {}, 0
	for guid in pairs(winners or {}) do
		local w = math.max(0, tonumber((damage or {})[guid]) or 0) + hw * math.max(0, tonumber((healing or {})[guid]) or 0)
		list[#list + 1] = {guid = guid, weight = w, gold = 0}
		total = total + w
	end
	local shares = {}
	local n = #list
	if n == 0 then
		return shares, list
	end
	table.sort(list, function(a, b)
		if a.weight ~= b.weight then
			return a.weight > b.weight
		end
		return a.guid < b.guid
	end)
	local base = floor(pool * math.min(1, math.max(0, r.floorShare or 0)) / n)
	local rest = pool - base * n
	local paid = 0
	for _, e in ipairs(list) do
		local part
		if total > 0 then
			part = floor(rest * e.weight / total)
		else
			part = floor(rest / n)
		end
		e.gold = base + part
		paid = paid + e.gold
	end
	list[1].gold = list[1].gold + (pool - paid)
	for _, e in ipairs(list) do
		shares[e.guid] = e.gold
	end
	return shares, list
end

function B.gxp(players, cfg)
	local g = cfg.gxp or {}
	local n = (g.base or 0) + (g.perPlayer or 0) * math.max(0, floor(tonumber(players) or 0))
	return math.min(n, g.max or n)
end

-- the banner of a guild with `kills` weekly kills in total: tier (0 = none), its name, the kills of the next tier
function B.banner(kills, cfg)
	kills = math.max(0, floor(tonumber(kills) or 0))
	local tier, name, nextAt = 0, nil, nil
	for i, b in ipairs(cfg.banners or {}) do
		if kills >= b.kills then
			tier, name = i, b.name
		elseif not nextAt then
			nextAt = b.kills
		end
	end
	return tier, name, nextAt
end

-- ---------------------------------------------------------------- board
-- rows = {{id, name, killed (bool), seconds, damage, players}}: kills first (fastest), then the most damage
function B.rankGuilds(rows)
	local list = {}
	for _, r in ipairs(rows or {}) do
		list[#list + 1] = r
	end
	table.sort(list, function(a, b)
		if (a.killed and true or false) ~= (b.killed and true or false) then
			return a.killed and true or false
		end
		if a.killed and (a.seconds or 0) ~= (b.seconds or 0) then
			return (a.seconds or 0) < (b.seconds or 0)
		end
		if (a.damage or 0) ~= (b.damage or 0) then
			return (a.damage or 0) > (b.damage or 0)
		end
		return (a.id or 0) < (b.id or 0)
	end)
	for i, r in ipairs(list) do
		r.rank = i
	end
	return list
end

return B
