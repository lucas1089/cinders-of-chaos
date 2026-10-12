-- PvP battleground "Ember Wells" and the PvP seasons: the pure part (no engine calls), shared by battleground.lua,
-- arena_season.lua and tests/battleground_test.lua.
--   season     season number and dates, Glicko-lite rating (team matches), inactivity rd growth, soft reset, decay,
--              placement, tiers, the end-of-season rewards
--   queue      level brackets, rating window, roles, match forming (realm + bracket groups, role and rating balance),
--              estimated wait
--   match      level normalisation, who may hit whom, the death catch, capture, score ticks, respawn waves, AFK,
--              the winner
--   rewards    honor (weekly cap, weekly first win), deserter penalty, the vendor
--   map        slot grid, the Ember Wells layout (180-degree rotation symmetric) and its footprint
-- Settings: battleground_config.lua (passed in as `cfg`). Lua 5.1 / LuaJIT and Lua 5.3 compatible.

ChaosBattlegroundCore = ChaosBattlegroundCore or {}
local K = ChaosBattlegroundCore

local floor, max, min, abs, sqrt = math.floor, math.max, math.min, math.abs, math.sqrt
local WEEK, DAY = 7 * 86400, 86400

local function round(x)
	return floor(x + 0.5)
end

local function clamp(x, lo, hi)
	return max(lo, min(hi, x))
end

-- ====================================================================== season
function K.seasonLength(cfg)
	return cfg.season.weeks * WEEK
end

function K.epoch(cfg)
	local e = cfg.season.epoch
	return os.time({year = e.year, month = e.month, day = e.day, hour = e.hour or 0, min = 0, sec = 0})
end

-- season id (1, 2, ...) of time `now`, its start and its end. Before the epoch it is season 1 (not started yet).
function K.seasonOf(cfg, now)
	local epoch, len = K.epoch(cfg), K.seasonLength(cfg)
	local id = max(1, floor((now - epoch) / len) + 1)
	local start = epoch + (id - 1) * len
	return id, start, start + len
end

-- ---------------------------------------------------------------- Glicko-lite
local Q = math.log(10) / 400
local PI2 = math.pi * math.pi

function K.g(rd)
	return 1 / sqrt(1 + 3 * Q * Q * rd * rd / PI2)
end

-- chance of r to beat an opponent rated ro with deviation rdo
function K.expected(r, ro, rdo)
	return 1 / (1 + 10 ^ (-K.g(rdo or 0) * (r - ro) / 400))
end

-- one Glicko-1 rating period with one game. Returns the new rating, the new rd (never below rdMin) and the change.
function K.glicko(cfg, r, rd, ro, rdo, score)
	local s = cfg.season
	local g = K.g(rdo)
	local e = K.expected(r, ro, rdo)
	local d2inv = Q * Q * g * g * e * (1 - e)
	local denom = 1 / (rd * rd) + d2inv
	local newR = r + (Q / denom) * g * (score - e)
	local newRd = clamp(sqrt(1 / denom), s.rdMin, s.rdMax)
	newR = max(s.floor, round(newR))
	return newR, newRd, newR - r
end

-- rd after `idle` seconds without a match: sqrt(rd^2 + c^2 x weeks), at most rdMax
function K.inflate(cfg, rd, idle)
	local s = cfg.season
	local weeks = max(0, idle or 0) / WEEK
	return min(s.rdMax, sqrt(rd * rd + s.c * s.c * weeks))
end

-- teams = {{{rating, rd, left}, ...}, {...}}, winner 1 / 2 / 0 (draw). Every player is rated against the other team's
-- average rating and root-mean-square rd; a player who left scores 0. Writes before / after / rdAfter / delta / score.
function K.rateTeams(cfg, teams, winner)
	local comp = {}
	for side = 1, 2 do
		local sr, srd, n = 0, 0, 0
		for _, p in ipairs(teams[side]) do
			sr = sr + p.rating
			srd = srd + p.rd * p.rd
			n = n + 1
		end
		comp[side] = {r = n > 0 and sr / n or cfg.season.start, rd = n > 0 and sqrt(srd / n) or cfg.season.rdStart}
	end
	for side = 1, 2 do
		local score = winner == 0 and 0.5 or (winner == side and 1 or 0)
		local o = comp[3 - side]
		for _, p in ipairs(teams[side]) do
			local sc = p.left and 0 or score
			p.before = p.rating
			p.after, p.rdAfter, p.delta = K.glicko(cfg, p.rating, p.rd, o.r, o.rd, sc)
			p.score = sc
		end
	end
	return teams
end

-- rating after the inactivity decay: at or above decay.from, perWeek per full week past graceDays since `last`,
-- never below decay.from. Returns the rating and the weeks decayed.
function K.decay(cfg, rating, last, now)
	local d = cfg.season.decay
	if not last or last <= 0 or rating <= d.from then
		return rating, 0
	end
	local idle = now - last - d.graceDays * DAY
	if idle < WEEK then
		return rating, 0
	end
	local weeks = floor(idle / WEEK)
	return max(d.from, rating - d.perWeek * weeks), weeks
end

-- a new season's row from the last one: r = start + (r - start) x squash, rd = max(rd, rdReset), placement again
function K.softReset(cfg, rating, rd)
	local s = cfg.season
	return round(s.start + (rating - s.start) * s.squash), max(rd or s.rdStart, s.rdReset)
end

function K.newRow(cfg)
	local s = cfg.season
	return {rating = s.start, rd = s.rdStart, matches = 0, wins = 0, losses = 0, draws = 0, peak = s.start, last = 0}
end

function K.placed(cfg, row)
	return (row and row.matches or 0) >= cfg.season.placementMatches
end

-- tier index and tier of a rating
function K.tierOf(cfg, rating)
	local tiers = cfg.season.tiers
	local idx = 1
	for i, t in ipairs(tiers) do
		if rating >= t.min then
			idx = i
		end
	end
	return idx, tiers[idx]
end

-- what a row shows now: decayed rating, rd grown by the idle time, placement and tier
function K.view(cfg, row, now)
	row = row or K.newRow(cfg)
	local r, weeks = K.decay(cfg, row.rating, row.last, now)
	local rd = row.last and row.last > 0 and K.inflate(cfg, row.rd, now - row.last) or row.rd
	local v = {rating = r, rd = round(rd), matches = row.matches, wins = row.wins, losses = row.losses, draws = row.draws,
		peak = row.peak or r, decayed = weeks, placed = K.placed(cfg, row)}
	v.tierIndex, v.tier = K.tierOf(cfg, r)
	v.placementLeft = max(0, cfg.season.placementMatches - (row.matches or 0))
	-- decay warning: days until the next decay step when the rating decays at all
	local d = cfg.season.decay
	if r > d.from and row.last and row.last > 0 then
		local nextAt = row.last + d.graceDays * DAY + (weeks + 1) * WEEK
		v.decayIn = max(0, nextAt - now)
	end
	return v
end

-- the best placed bracket of a character's rows at time `now` (season end): tier index, bracket, rating; nil if none
function K.bestTier(cfg, rows, now)
	local best
	for bracket, row in pairs(rows or {}) do
		if K.placed(cfg, row) then
			local r = K.decay(cfg, row.rating, row.last, now)
			if not best or r > best.rating or (r == best.rating and bracket < best.bracket) then
				best = {rating = r, bracket = bracket}
			end
		end
	end
	if not best then
		return nil
	end
	best.tierIndex = K.tierOf(cfg, best.rating)
	return best.tierIndex, best.bracket, best.rating
end

-- the rewards of a tier: {title, frame, cosmetics = {...}, honor, tier}
function K.seasonReward(cfg, tierIndex, seasonId)
	local t = cfg.season.tiers[tierIndex]
	if not t then
		return nil
	end
	local out = {tier = t, honor = t.honor or 0, frame = t.frame, cosmetics = {}}
	if t.title then
		out.title = string.format("%s (S%d)", t.title, seasonId or 0)
	end
	for _, c in ipairs(t.cosmetics or {}) do
		out.cosmetics[#out.cosmetics + 1] = c
	end
	return out
end

-- the reward preview of every tier for the client (lowest first)
function K.rewardPreview(cfg)
	local out = {}
	for i, t in ipairs(cfg.season.tiers) do
		out[#out + 1] = {i = i, key = t.key, name = t.name, min = t.min, color = t.color, honor = t.honor or 0,
			title = t.title, frame = t.frame, cosmetics = t.cosmetics or {}}
	end
	return out
end

-- ====================================================================== queue
function K.bracketOf(cfg, level)
	for _, b in ipairs(cfg.brackets) do
		if level >= b.min and (not b.max or level <= b.max) then
			return b
		end
	end
	return nil
end

function K.bracketByKey(cfg, key)
	for _, b in ipairs(cfg.brackets) do
		if b.key == key then
			return b
		end
	end
	return nil
end

function K.window(cfg, waited)
	local w = cfg.window
	return min(w.max, w.base + w.step * floor(max(0, waited or 0) / w.everySeconds))
end

-- the roles of a vocation (party_finder_config.lua classRoles); the first is its main role
function K.rolesOf(pf, voc)
	local roles = pf and pf.classRoles and pf.classRoles[voc]
	if type(roles) == "table" and #roles > 0 then
		return roles
	end
	return (pf and pf.defaultRoles) or {"dps"}
end

-- the role a player queues as: `wanted` when the class may fill it, else the main role
function K.pickRole(pf, voc, wanted)
	local roles = K.rolesOf(pf, voc)
	for _, r in ipairs(roles) do
		if r == wanted then
			return r
		end
	end
	return roles[1]
end

local function entrySize(e)
	return #e.members
end

local function teamStats(team)
	local n, sum, roles = 0, 0, {tank = 0, healer = 0, dps = 0}
	for _, e in ipairs(team) do
		for _, m in ipairs(e.members) do
			n = n + 1
			sum = sum + (m.rating or 0)
			roles[m.role or "dps"] = (roles[m.role or "dps"] or 0) + 1
		end
	end
	return n, n > 0 and sum / n or 0, roles
end
K.teamStats = teamStats

-- cost of a split: rating difference + roleWeight x (|tanks| + |healers| differences)
function K.cost(cfg, t1, t2)
	local _, a1, r1 = teamStats(t1)
	local _, a2, r2 = teamStats(t2)
	return abs(a1 - a2) + cfg.roleWeight * (abs(r1.tank - r2.tank) + abs(r1.healer - r2.healer))
end

-- a first subset of exactly n players in the given order (dynamic programming: parties make it a subset-sum)
local function subset(order, n)
	local reach = {[0] = {}}
	for i, e in ipairs(order) do
		local s = entrySize(e)
		for sum = n - s, 0, -1 do
			if reach[sum] and not reach[sum + s] then
				local used = {}
				for k in pairs(reach[sum]) do
					used[k] = true
				end
				used[i] = true
				reach[sum + s] = used
			end
		end
	end
	if not reach[n] then
		return nil
	end
	local t1, t2 = {}, {}
	for i, e in ipairs(order) do
		if reach[n][i] then
			t1[#t1 + 1] = e
		else
			t2[#t2 + 1] = e
		end
	end
	return t1, t2
end

-- t1 without the entries at ia plus `add`
local function swapOut(t, idx, add)
	local skip, out = {}, {}
	for _, i in ipairs(idx) do
		skip[i] = true
	end
	for i, e in ipairs(t) do
		if not skip[i] then
			out[#out + 1] = e
		end
	end
	for _, e in ipairs(add) do
		out[#out + 1] = e
	end
	return out
end

-- local search: move one entry against one entry of the same size, or against two whose sizes add up, while the
-- cost goes down
local function improve(cfg, t1, t2)
	local best = K.cost(cfg, t1, t2)
	for _ = 1, 80 do
		local improved = false
		for side = 1, 2 do
			local a, b = side == 1 and t1 or t2, side == 1 and t2 or t1
			for i = 1, #a do
				local si = entrySize(a[i])
				for j = 1, #b do
					local options = {}
					if side == 1 and entrySize(b[j]) == si then
						options[#options + 1] = {j}
					end
					for k = j + 1, #b do
						if entrySize(b[j]) + entrySize(b[k]) == si then
							options[#options + 1] = {j, k}
						end
					end
					for _, ib in ipairs(options) do
						local back = {}
						for _, x in ipairs(ib) do
							back[#back + 1] = b[x]
						end
						local na, nb = swapOut(a, {i}, back), swapOut(b, ib, {a[i]})
						local c1, c2 = side == 1 and na or nb, side == 1 and nb or na
						local c = K.cost(cfg, c1, c2)
						if c < best - 1e-9 then
							best, improved, t1, t2 = c, true, c1, c2
							break
						end
					end
					if improved then
						break
					end
				end
				if improved then
					break
				end
			end
			if improved then
				break
			end
		end
		if not improved then
			break
		end
	end
	return t1, t2, best
end

-- split `entries` (whole parties) into two teams of exactly n players each. Returns t1, t2, cost or nil.
-- A few starting splits (subset-sum in different orders: big parties first, by rating both ways, roles first), each
-- improved by the local search; the cheapest wins.
function K.split(cfg, entries, n)
	local total = 0
	for _, e in ipairs(entries) do
		total = total + entrySize(e)
	end
	if total ~= 2 * n then
		return nil
	end
	local function roleRank(e)
		local r = 0
		for _, m in ipairs(e.members) do
			r = r + (m.role == "tank" and 2 or (m.role == "healer" and 1 or 0))
		end
		return r
	end
	-- a fixed pseudo-random key per start (the same split for the same queue every time)
	local seed = 1
	local function shuffled()
		local keys = {}
		for _, e in ipairs(entries) do
			seed = (seed * 16807) % 2147483647
			keys[e] = seed
		end
		return function(x, y) return keys[x] < keys[y] end
	end
	local orders = {
		function(x, y) return (x.rating or 0) > (y.rating or 0) end,
		function(x, y) return (x.rating or 0) < (y.rating or 0) end,
		function(x, y) return roleRank(x) > roleRank(y) end
	}
	for _ = 1, cfg.splitStarts or 8 do
		orders[#orders + 1] = shuffled()
	end
	local best1, best2, bestCost
	for oi, cmp in ipairs(orders) do
		local order = {}
		for i, e in ipairs(entries) do
			order[i] = e
		end
		table.sort(order, function(x, y)
			if oi <= 3 and entrySize(x) ~= entrySize(y) then
				return entrySize(x) > entrySize(y)
			end
			if cmp(x, y) ~= cmp(y, x) then
				return cmp(x, y)
			end
			return (x.id or 0) < (y.id or 0)
		end)
		local t1, t2 = subset(order, n)
		if t1 then
			local c
			t1, t2, c = improve(cfg, t1, t2)
			if not bestCost or c < bestCost - 1e-9 then
				best1, best2, bestCost = t1, t2, c
			end
		end
	end
	if not best1 then
		return nil
	end
	return best1, best2, bestCost
end

-- entries = {id, joined, rating, group, members = {{guid, role, rating, level}, ...}}. Groups (realm and level
-- bracket) never mix. Oldest entry first: the entries within its rating window, oldest first, fill up to
-- 2 x teamMax players; the largest even match (teamMin..teamMax a side) that whole parties can fill is taken, but a
-- match below teamMax only once the oldest entry waited fillSeconds. Returns a list of {teams = {t1, t2}, size, group,
-- cost}.
function K.findMatches(cfg, entries, now)
	local groups, order = {}, {}
	for _, e in ipairs(entries) do
		local g = e.group or ""
		if not groups[g] then
			groups[g] = {}
			order[#order + 1] = g
		end
		table.insert(groups[g], e)
	end
	table.sort(order)
	local out = {}
	for _, g in ipairs(order) do
		local list = groups[g]
		table.sort(list, function(a, b)
			if a.joined ~= b.joined then
				return a.joined < b.joined
			end
			return (a.id or 0) < (b.id or 0)
		end)
		local used = {}
		for ai, anchor in ipairs(list) do
			if not used[ai] then
				local waited = now - anchor.joined
				local win = K.window(cfg, waited)
				local cand = {}
				for j = ai, #list do
					local e = list[j]
					if not used[j] and abs((e.rating or 0) - (anchor.rating or 0)) <= win then
						cand[#cand + 1] = {e = e, j = j}
					end
				end
				local total = 0
				for _, c in ipairs(cand) do
					total = total + entrySize(c.e)
				end
				local n = min(cfg.teamMax, floor(total / 2))
				local found
				while n >= cfg.teamMin and not found do
					if n < cfg.teamMax and waited < cfg.fillSeconds then
						break
					end
					-- oldest first, skipping an entry that does not fit, until exactly 2n
					local pick, sum = {}, 0
					for _, c in ipairs(cand) do
						if sum + entrySize(c.e) <= 2 * n then
							pick[#pick + 1] = c
							sum = sum + entrySize(c.e)
						end
						if sum == 2 * n then
							break
						end
					end
					if sum == 2 * n and pick[1] and pick[1].e == anchor then
						local es = {}
						for _, c in ipairs(pick) do
							es[#es + 1] = c.e
						end
						local t1, t2, cost = K.split(cfg, es, n)
						if t1 then
							found = {teams = {t1, t2}, size = n, group = g, cost = cost}
							for _, c in ipairs(pick) do
								used[c.j] = true
							end
						end
					end
					n = n - 1
				end
				if found then
					out[#out + 1] = found
				end
			end
		end
	end
	return out
end

-- estimated wait in seconds: soon when enough are queued, else the average of the recent waits (or the default)
function K.estimateWait(cfg, samples, queued, waited)
	waited = waited or 0
	if (queued or 0) >= 2 * cfg.teamMax then
		return cfg.matchmakeSeconds
	end
	local avg = cfg.defaultWaitSeconds
	if type(samples) == "table" and #samples > 0 then
		local s = 0
		for _, v in ipairs(samples) do
			s = s + v
		end
		avg = s / #samples
	end
	if (queued or 0) >= 2 * cfg.teamMin then
		avg = min(avg, max(cfg.matchmakeSeconds, cfg.fillSeconds - waited))
	end
	return max(cfg.matchmakeSeconds, round(avg - waited))
end

function K.addSample(cfg, samples, value)
	samples[#samples + 1] = value
	while #samples > cfg.waitSamples do
		table.remove(samples, 1)
	end
	return samples
end

-- ====================================================================== match
-- damage / healing factor from a source of level ls to a target of level lt in a bracket of reference level ref
function K.normFactor(cfg, ls, lt, ref)
	local n = cfg.normalise
	local out = clamp((ref / max(1, ls)) ^ n.exponent, n.minFactor, n.maxFactor)
	local inn = clamp((max(1, lt) / ref) ^ n.exponent, n.minFactor, n.maxFactor)
	return out * inn
end

-- may a hit of attacker `a` land on target `t` (their match entries {team, down}, nil = not a fighter)?
-- self = the attacker hits itself. Damage without a player behind it (a = nil) lands in the fight.
function K.canHit(phase, a, t, self)
	if not t then
		return true
	end
	if t.down or phase ~= "fight" then
		return false
	end
	if self or not a then
		return true
	end
	return not a.down and a.team ~= t.team
end

-- the death catch (as the arena): returns the clamped hit and true when it would have killed (1 health is left)
function K.catchDamage(health, primary, secondary)
	primary, secondary = max(0, primary or 0), max(0, secondary or 0)
	if primary + secondary < health then
		return primary, secondary, false
	end
	local keep = max(0, health - 1)
	local p = min(primary, keep)
	return p, min(secondary, keep - p), true
end

-- one capture step. b = {progress (-100..100), owner (0, 1, 2)}, counts = {[1] = n1, [2] = n2} (alive players in the
-- circle), dt seconds. Returns the event: "captured" (team) / "lost" (old owner) / nil, and the moving team.
function K.captureStep(cfg, b, counts, dt)
	local c = cfg.capture
	local n1, n2 = counts[1] or 0, counts[2] or 0
	b.contested = n1 > 0 and n2 > 0
	if b.contested or (n1 == 0 and n2 == 0) then
		return nil
	end
	local team = n1 > 0 and 1 or 2
	local n = team == 1 and n1 or n2
	local rate = 100 / c.captureSeconds * min(c.maxRate, 1 + c.perExtra * (n - 1))
	local dir = team == 1 and 1 or -1
	local before = b.progress
	b.progress = clamp(before + dir * rate * dt, -100, 100)
	local event, who
	if b.owner ~= 0 and b.owner ~= team and ((team == 1 and before < 0 and b.progress >= 0) or
			(team == 2 and before > 0 and b.progress <= 0)) then
		event, who = "lost", b.owner
		b.owner = 0
	end
	if b.owner ~= team and abs(b.progress) >= 100 then
		event, who = "captured", team
		b.owner = team
	end
	return event, who, team
end

-- points of each team for one tick: perTick[braziers held]
function K.tickPoints(cfg, braziers)
	local held = {0, 0}
	for _, b in ipairs(braziers) do
		if b.owner == 1 or b.owner == 2 then
			held[b.owner] = held[b.owner] + 1
		end
	end
	return cfg.perTick[held[1]] or 0, cfg.perTick[held[2]] or 0, held
end

-- winner while running: the team at winScore (both: the higher, equal = draw), nil otherwise; at the end of time the
-- higher score (equal = draw = 0). reason "score" / "time".
function K.winner(cfg, score, timeUp)
	local a, b = score[1], score[2]
	if a >= cfg.winScore or b >= cfg.winScore then
		return a == b and 0 or (a > b and 1 or 2), "score"
	end
	if timeUp then
		return a == b and 0 or (a > b and 1 or 2), "time"
	end
	return nil
end

-- the next respawn wave (os.time) after `now` for a fight that started at fightAt
function K.nextWave(cfg, fightAt, now)
	local w = cfg.waveSeconds
	if now < fightAt then
		return fightAt
	end
	return fightAt + (floor((now - fightAt) / w) + 1) * w
end

-- AFK: "kick", "warn" or nil from the seconds since the last action
function K.afk(cfg, idle)
	if idle >= cfg.afkKickSeconds then
		return "kick"
	elseif idle >= cfg.afkWarnSeconds then
		return "warn"
	end
	return nil
end

-- the scoreboard rows of a match: players = list of {name, team, kills, downs, captures, damage, healing, honor},
-- sorted by team, then captures + kills, then damage
function K.scoreboard(players)
	local rows = {}
	for _, p in ipairs(players) do
		rows[#rows + 1] = p
	end
	table.sort(rows, function(a, b)
		if a.team ~= b.team then
			return a.team < b.team
		end
		local sa, sb = (a.kills or 0) + (a.captures or 0) * 2, (b.kills or 0) + (b.captures or 0) * 2
		if sa ~= sb then
			return sa > sb
		end
		if (a.damage or 0) ~= (b.damage or 0) then
			return (a.damage or 0) > (b.damage or 0)
		end
		return tostring(a.name) < tostring(b.name)
	end)
	return rows
end

-- ====================================================================== rewards
-- week key (YYYYMMDD of the Monday the week started) of a time, the week turning at resetHour on Monday
function K.weekKey(t, resetHour)
	local s = t - (resetHour or 6) * 3600
	local d = os.date("*t", s)
	local back = (d.wday + 5) % 7 -- days since Monday
	local m = os.date("*t", os.time({year = d.year, month = d.month, day = d.day - back, hour = 12}))
	return m.year * 10000 + m.month * 100 + m.day
end

-- honor of a match. r = {result "win"/"loss"/"draw", kills, captures, deserter, presence (0..1)};
-- w = {earned = honor from matches this week, firstWinDone}. Returns honor, firstWin (bool), capped (bool).
function K.honorFor(cfg, r, w)
	local h = cfg.honor
	if r.deserter or (r.presence or 1) < cfg.minPresenceShare then
		return 0, false, false
	end
	local total = (h[r.result] or 0) + min(h.killCap, h.perKill * (r.kills or 0)) +
		min(h.captureCap, h.perCapture * (r.captures or 0))
	local allowed = max(0, h.weeklyCap - (w.earned or 0))
	local gained = min(total, allowed)
	local first = r.result == "win" and not w.firstWinDone
	if first then
		gained = gained + h.weeklyFirstWin
	end
	return gained, first, gained < total + (first and h.weeklyFirstWin or 0)
end

-- deserter: history = list of os.time of earlier desertions. Returns the minutes of this penalty and the new history
-- (desertions older than windowHours dropped, this one added).
function K.deserter(cfg, history, now)
	local d = cfg.deserter
	local keep = {}
	for _, t in ipairs(history or {}) do
		if now - t < d.windowHours * 3600 then
			keep[#keep + 1] = t
		end
	end
	keep[#keep + 1] = now
	local minutes = d.minutes[min(#keep, #d.minutes)]
	return minutes, keep
end

-- may this offer be bought? honor = balance, owns(cosmeticKey) -> bool. Returns the offer or nil, reason.
function K.vendorCheck(cfg, key, honor, owns)
	local offer
	for _, o in ipairs(cfg.vendor) do
		if o.key == key then
			offer = o
		end
	end
	if not offer then
		return nil, "Unknown offer."
	end
	if offer.kind == "cosmetic" and owns and owns(offer.cosmetic) then
		return nil, "Your account owns it already."
	end
	if (honor or 0) < offer.cost then
		return nil, string.format("You need %d honor (you have %d).", offer.cost, honor or 0)
	end
	return offer
end

function K.parseRole(text)
	text = tostring(text or ""):lower()
	if text == "tank" or text == "healer" or text == "dps" then
		return text
	end
	return nil
end

-- ====================================================================== map
function K.slotOrigin(cfg, slot)
	local g = cfg.grid
	return {x = g.origin.x + (slot % g.cols) * g.spacing, y = g.origin.y + floor(slot / g.cols) * g.spacing, z = g.origin.z}
end

-- team 1's half in local coordinates (0..W+1, 0..H+1, the outer wall included); team 2 gets the 180-degree turn
local function halfPlan(W, H)
	local cx, cy = floor((W + 1) / 2), floor((H + 1) / 2)
	local p = {walls = {}, pillars = {}, flags = {}}
	local function wall(x, y)
		p.walls[#p.walls + 1] = {x, y}
	end
	-- base: x 1..7, y cy-4..cy+4, its east wall at x 8 with a 3-tile gate in the middle
	p.base = {x1 = 1, y1 = cy - 4, x2 = 7, y2 = cy + 4}
	for y = cy - 5, cy + 5 do
		if y < cy - 1 or y > cy + 1 then
			wall(8, y)
		end
	end
	for x = 1, 7 do
		wall(x, cy - 5)
		wall(x, cy + 5)
	end
	-- graveyard: x 1..7, y 1..5, closed (teleport only)
	p.grave = {x1 = 1, y1 = 1, x2 = 7, y2 = 5}
	for x = 1, 8 do
		wall(x, 6)
	end
	for y = 1, 5 do
		wall(8, y)
	end
	-- cover
	for _, y in ipairs({cy - 4, cy - 3, cy - 2, cy + 2, cy + 3, cy + 4}) do
		wall(14, y) -- in front of the gate
	end
	for y = cy + 3, cy + 6 do
		wall(24, y)
	end
	for x = 20, 24 do
		wall(x, cy - 6)
	end
	for y = 5, 8 do
		wall(cx - 5, y)
	end
	p.pillars = {{cx - 4, cy - 3}, {cx - 4, cy + 3}, {22, H - 4}, {10, H - 4}}
	p.flags = {{7, cy - 4}, {7, cy + 4}}
	p.brazier = {18, cy + 8} -- the near well (team 2's turn of it is the far well)
	return p, cx, cy
end

-- the layout of a slot: rectangles and positions in map coordinates
function K.layout(cfg, slot)
	local o = K.slotOrigin(cfg, slot)
	local W, H = cfg.field.innerW, cfg.field.innerH
	local plan, cx, cy = halfPlan(W, H)
	local z = o.z
	local function at(x, y, turn)
		if turn then
			x, y = W + 1 - x, H + 1 - y
		end
		return {x = o.x + x, y = o.y + y, z = z}
	end
	local function rect(r, turn)
		local a, b = at(r.x1, r.y1, turn), at(r.x2, r.y2, turn)
		return {x1 = min(a.x, b.x), y1 = min(a.y, b.y), x2 = max(a.x, b.x), y2 = max(a.y, b.y)}
	end
	local L = {slot = slot, z = z, x1 = o.x, y1 = o.y, x2 = o.x + W + 1, y2 = o.y + H + 1,
		center = at(cx, cy), bases = {}, graves = {}, spawns = {}, graveSpots = {}, walls = {}, pillars = {}, flags = {}}
	for team = 1, 2 do
		local turn = team == 2
		L.bases[team] = rect(plan.base, turn)
		L.graves[team] = rect(plan.grave, turn)
		L.spawns[team], L.graveSpots[team] = {}, {}
		for _, xy in ipairs({{3, 0}, {5, 0}, {3, -1}, {5, -1}, {3, 1}, {5, 1}, {3, -2}, {5, -2}, {3, 2}, {5, 2},
				{4, -3}, {4, 3}}) do
			table.insert(L.spawns[team], at(xy[1], cy + xy[2], turn))
		end
		for y = 2, 4 do
			for x = 2, 6, 2 do
				table.insert(L.graveSpots[team], at(x, y, turn))
			end
		end
		for _, w in ipairs(plan.walls) do
			L.walls[#L.walls + 1] = at(w[1], w[2], turn)
		end
		for _, q in ipairs(plan.pillars) do
			L.pillars[#L.pillars + 1] = at(q[1], q[2], turn)
		end
		for _, q in ipairs(plan.flags) do
			L.flags[#L.flags + 1] = at(q[1], q[2], turn)
		end
	end
	local near = at(plan.brazier[1], plan.brazier[2])
	local far = at(plan.brazier[1], plan.brazier[2], true)
	L.braziers = {
		{name = cfg.braziers[1], x = near.x, y = near.y, z = z},
		{name = cfg.braziers[2], x = L.center.x, y = L.center.y, z = z},
		{name = cfg.braziers[3], x = far.x, y = far.y, z = z}
	}
	-- the west well is team 1's near one; sort by x so the HUD reads west to east
	table.sort(L.braziers, function(a, b)
		return a.x < b.x
	end)
	for i, b in ipairs(L.braziers) do
		b.name = cfg.braziers[i]
	end
	return L
end

local function inRect(r, z, pos)
	return pos ~= nil and pos.z == z and pos.x >= r.x1 and pos.x <= r.x2 and pos.y >= r.y1 and pos.y <= r.y2
end
K.inRect = inRect

function K.inSlot(L, pos)
	return inRect(L, L.z, pos)
end

function K.baseOf(L, pos)
	for team = 1, 2 do
		if inRect(L.bases[team], L.z, pos) then
			return team
		end
	end
	return nil
end

function K.graveOf(L, pos)
	for team = 1, 2 do
		if inRect(L.graves[team], L.z, pos) then
			return team
		end
	end
	return nil
end

-- index of the brazier whose circle holds pos (Chebyshev distance <= radius), or nil
function K.brazierAt(cfg, L, pos)
	if not pos or pos.z ~= L.z then
		return nil
	end
	local r = cfg.capture.radius
	for i, b in ipairs(L.braziers) do
		if abs(pos.x - b.x) <= r and abs(pos.y - b.y) <= r then
			return i
		end
	end
	return nil
end

-- every tile of the slot once: {x, y, z, wall = bool, ground = "ground" | "base" | "ring"}
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
			if K.baseOf(L, pos) or K.graveOf(L, pos) then
				ground = "base"
			elseif K.brazierAt(cfg, L, pos) then
				ground = "ring"
			end
			list[#list + 1] = {x = x, y = y, z = L.z, wall = wall, ground = ground}
		end
	end
	return list
end

-- slot index of a position, or nil
function K.slotOfPos(cfg, pos)
	for slot = 0, cfg.grid.slots - 1 do
		if K.inSlot(K.layout(cfg, slot), pos) then
			return slot
		end
	end
	return nil
end

function K.allocSlot(cfg, busy, bad)
	for slot = 0, cfg.grid.slots - 1 do
		if not busy[slot] and not (bad and bad[slot]) then
			return slot
		end
	end
	return nil
end

return K
