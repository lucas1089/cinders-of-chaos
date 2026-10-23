-- Community goals and the weekly world modifier: the pure part (no engine calls), shared by community.lua and
-- tests/community_test.lua. Numbers: community_config.lua. Overview: server/README.md "Community goals and the weekly
-- world modifier".
--   time       the week (Monday at resetHour, as ChaosBounty.week), the goal's period, the cap day
--   points     what a source is worth, the per-character caps of a day (all sources and each source)
--   stages     percent, stages crossed, the buff windows they open, the bonus of the windows open now
--   ranking    the period's contributors (staff never), the rewards when a period ends
--   week       the seeded draw of the week's modifiers, staff overrides, what each modifier changes
--   hooks      the numbers community.lua hands to the other systems (1 / nil / 0 when nothing is active)
--   payload    the window's state, the buff bar items, the login lines
-- Every random draw uses the Park-Miller generator below on integers under 2^46, so one seed gives the same draw in
-- LuaJIT (doubles) and Lua 5.3 (integers). Lua 5.1 / LuaJIT and Lua 5.3.

ChaosCommunityCore = ChaosCommunityCore or {}
local C = ChaosCommunityCore

-- a text in `lang` (Chaos.t keys, i18n_strings.lua); English without ChaosI18n
local function T(lang, key, ...)
	if ChaosI18n and ChaosI18n.text then
		return ChaosI18n.text(lang, key, ...)
	end
	if select("#", ...) == 0 then
		return key
	end
	return string.format(key, ...)
end

local floor, max, min = math.floor, math.max, math.min
local MOD = 2147483647

local function num(v, d)
	v = tonumber(v)
	if v == nil or v ~= v then
		return d or 0
	end
	return v
end

-- ===================================================================== time
local function dayKeyOf(t)
	return tonumber(os.date("%Y%m%d", t))
end

-- the week of t: YYYYMMDD of its Monday (the week starts Monday at `hour`), the bounty board's rule
function C.week(t, hour)
	local d = os.date("*t", t - (hour or 6) * 3600)
	local back = (d.wday + 5) % 7 -- wday 1 = Sunday: Monday -> 0, Sunday -> 6
	return dayKeyOf(os.time({year = d.year, month = d.month, day = d.day - back, hour = 12}))
end

-- unix time a day key starts at `hour` (+ `days` days)
function C.keyStart(key, hour, days)
	key = floor(num(key))
	local y, m, d = floor(key / 10000), floor(key / 100) % 100, key % 100
	return os.time({year = y, month = m, day = d + (days or 0), hour = hour or 6, min = 0, sec = 0})
end

function C.weekEnd(t, hour)
	return C.keyStart(C.week(t, hour), hour, 7)
end

-- the cap day of t (turns at `hour`)
function C.day(t, hour)
	return dayKeyOf(t - (hour or 6) * 3600)
end

-- the goal's period at t: key (YYYYMMDD of its first day), start, finish
function C.period(cfg, t)
	local hour = cfg.resetHour or 6
	local days = floor(num(cfg.goal.periodDays, 7))
	if days == 7 then
		local key = C.week(t, hour)
		return key, C.keyStart(key, hour), C.keyStart(key, hour, 7)
	end
	days = max(1, days)
	local epoch = cfg.goal.epoch or 20260105
	local first = C.keyStart(epoch, hour)
	local n = floor((t - first) / (days * 86400))
	local start = C.keyStart(epoch, hour, n * days)
	if t < start then
		n = n - 1
	elseif t >= C.keyStart(epoch, hour, (n + 1) * days) then
		n = n + 1
	end
	start = C.keyStart(epoch, hour, n * days)
	return dayKeyOf(start + 12 * 3600), start, C.keyStart(epoch, hour, (n + 1) * days)
end

-- the realm a character's points and buffs belong to
function C.realmOf(cfg, realm)
	if cfg.goal.realms == "separate" then
		return floor(num(realm))
	end
	return 0
end

-- ===================================================================== points and caps
function C.source(cfg, key)
	for _, s in ipairs(cfg.goal.sources) do
		if s.key == key then
			return s
		end
	end
	return nil
end

-- raw points of `n` units of a source. opts: tier (kill: the monster tier), riftTier (rift)
function C.points(cfg, key, n, opts)
	local s = C.source(cfg, key)
	n = num(n)
	if not s or n <= 0 then
		return 0
	end
	opts = opts or {}
	if key == "kill" then
		return floor(s.points * n * num((s.tierMult or {})[opts.tier or "normal"], 1))
	elseif key == "rift" then
		return floor((s.points + num(s.perTier) * max(1, num(opts.riftTier, 1))) * n)
	elseif key == "brazier" then
		return floor(n / max(1, num(s.perGold, 1))) * s.points
	end
	return floor(s.points * n)
end

-- "kill:120,rift:300" <-> {kill = 120, rift = 300}
function C.encodeSrc(src)
	local keys = {}
	for k, v in pairs(src or {}) do
		if num(v) > 0 then
			keys[#keys + 1] = k
		end
	end
	table.sort(keys)
	local parts = {}
	for _, k in ipairs(keys) do
		parts[#parts + 1] = k .. ":" .. floor(src[k])
	end
	return table.concat(parts, ",")
end

function C.decodeSrc(text)
	local out = {}
	for k, v in tostring(text or ""):gmatch("([%w_]+):(%d+)") do
		out[k] = tonumber(v)
	end
	return out
end

function C.newEntry()
	return {points = 0, day = 0, dayTotal = 0, daySrc = {}, at = 0}
end

-- credit `pts` raw points of `key` to entry e on cap day `day` (now = time, for the ranking's tie rule).
-- Returns the points really counted and whether a cap cut them.
function C.credit(cfg, e, key, pts, day, now)
	pts = floor(num(pts))
	local s = C.source(cfg, key)
	if not s or pts <= 0 then
		return 0, false
	end
	if e.day ~= day then
		e.day, e.dayTotal, e.daySrc = day, 0, {}
	end
	local room = num(cfg.goal.dailyCap, math.huge) - e.dayTotal
	local srcRoom = num(s.dailyCap, math.huge) - num(e.daySrc[key])
	if ChaosBetaMode and ChaosBetaMode.lifted("community_daily_cap") then
		room, srcRoom = math.huge, math.huge -- beta test mode: no daily cap
	end
	local gained = max(0, min(pts, room, srcRoom))
	if gained > 0 then
		e.points = e.points + gained
		e.dayTotal = e.dayTotal + gained
		e.daySrc[key] = num(e.daySrc[key]) + gained
		e.at = now or e.at
	end
	return gained, gained < pts
end

-- what a source may still give today (points) for entry e
function C.roomToday(cfg, e, key, day)
	local s = C.source(cfg, key)
	if not s then
		return 0
	end
	local total, src = 0, 0
	if e and e.day == day then
		total, src = e.dayTotal, num(e.daySrc[key])
	end
	if ChaosBetaMode and ChaosBetaMode.lifted("community_daily_cap") then
		return math.huge
	end
	return max(0, min(num(cfg.goal.dailyCap, math.huge) - total, num(s.dailyCap, math.huge) - src))
end

-- the gold a Brazier donation may take: whole perGold units, within the donation limits and today's room
function C.donation(cfg, e, gold, day, carried, lang)
	local b, s = cfg.brazier, C.source(cfg, "brazier")
	gold = floor(num(gold))
	if not s then
		return 0, T(lang, "The Brazier is cold.")
	end
	if gold < b.minGold then
		return 0, T(lang, "Give at least %d gold.", b.minGold)
	end
	gold = min(gold, b.maxGold)
	local per = max(1, num(s.perGold, 1))
	local room = floor(C.roomToday(cfg, e, "brazier", day) / s.points) * per
	if b.dailyGold then
		room = min(room, b.dailyGold - (e and e.day == day and num(e.daySrc.brazier) / s.points * per or 0))
	end
	gold = min(gold, room)
	gold = floor(gold / per) * per
	if gold <= 0 then
		return 0, T(lang, "The Brazier has taken all it will from you today.")
	end
	if carried and carried < gold then
		return 0, T(lang, "You do not have that much gold (backpack and bank).")
	end
	return gold
end

-- ===================================================================== stages
function C.pct(cfg, progress)
	local target = max(1, num(cfg.goal.target, 1))
	return min(100, num(progress) * 100 / target)
end

-- the highest stage index reached by `progress` (0 = none)
function C.stageAt(cfg, progress)
	local p = C.pct(cfg, progress)
	local n = 0
	for i, s in ipairs(cfg.goal.stages) do
		if p >= s.pct then
			n = i
		end
	end
	return n
end

-- the stage indexes crossed going from `before` to `after` points
function C.crossed(cfg, before, after)
	local out = {}
	local a, b = C.stageAt(cfg, before), C.stageAt(cfg, after)
	for i = a + 1, b do
		out[#out + 1] = i
	end
	return out
end

-- the announce percents of cfg.goal.announceSteps passed going from before to after
function C.steps(cfg, before, after)
	local out = {}
	local a, b = C.pct(cfg, before), C.pct(cfg, after)
	for _, p in ipairs(cfg.goal.announceSteps or {}) do
		if a < p and b >= p then
			out[#out + 1] = p
		end
	end
	return out
end

-- buffs = {[stage index] = {endsAt, startedAt, period}}: open (or reopen) the window of stage i
function C.openWindow(cfg, buffs, i, now, period)
	local s = cfg.goal.stages[i]
	if not s then
		return nil
	end
	local w = {startedAt = now, endsAt = now + floor(num(s.hours, 24) * 3600), period = period}
	buffs[i] = w
	return w
end

-- the stage windows open at `now`: {{i, stage, endsAt, left}} by stage order
function C.activeStages(cfg, buffs, now)
	local out = {}
	for i, s in ipairs(cfg.goal.stages) do
		local w = buffs and buffs[i]
		if w and num(w.endsAt) > now then
			out[#out + 1] = {i = i, stage = s, endsAt = w.endsAt, left = w.endsAt - now}
		end
	end
	return out
end

-- the sum of `kind` over the stage windows open now (0 when none)
function C.stageBonus(cfg, buffs, now, kind)
	local sum = 0
	for _, a in ipairs(C.activeStages(cfg, buffs, now)) do
		sum = sum + num(a.stage.bonus and a.stage.bonus[kind])
	end
	return sum
end

-- ===================================================================== ranking and rewards
-- list = {{guid, name, points, at}}; staff = {[guid] = true}. Sorted: points desc, then who got there first, then guid.
function C.rank(list, staff)
	local out = {}
	for _, e in ipairs(list or {}) do
		if num(e.points) > 0 and not (staff and staff[e.guid]) then
			out[#out + 1] = e
		end
	end
	table.sort(out, function(a, b)
		if a.points ~= b.points then
			return a.points > b.points
		end
		if num(a.at) ~= num(b.at) then
			return num(a.at) < num(b.at)
		end
		return num(a.guid) < num(b.guid)
	end)
	for i, e in ipairs(out) do
		e.rank = i
	end
	return out
end

-- the rewards of a finished period: {[guid] = {place = n or 0, token = bool}}
function C.periodRewards(cfg, ranked)
	local r = cfg.goal.rewards
	local out = {}
	for i, e in ipairs(ranked) do
		local place = i <= num(r.top) and i or 0
		local token = num(e.points) >= num(r.token and r.token.minPoints, math.huge)
		if place > 0 or token then
			out[e.guid] = {place = place, token = token}
		end
	end
	return out
end

-- the title of a top place, or nil when it ran out (periodEnd = when the period ended)
function C.titleOf(cfg, place, periodEnd, now)
	local r = cfg.goal.rewards
	if num(place) < 1 or num(place) > num(r.top) or not r.title then
		return nil
	end
	if now >= periodEnd + num(r.titleDays, 7) * 86400 then
		return nil
	end
	return {key = "community:keeper", text = r.title, color = r.titleColor, at = periodEnd}
end

-- ===================================================================== the week's modifiers
local Rng = {}
Rng.__index = Rng

function Rng:next()
	self.s = (self.s * 16807) % MOD
	return self.s
end

function Rng:int(a, b)
	if b <= a then
		return a
	end
	return a + self:next() % (b - a + 1)
end

function Rng:weighted(rows)
	local total = 0
	for _, row in ipairs(rows) do
		total = total + max(0, floor(row[2]))
	end
	if total <= 0 then
		return nil, nil
	end
	local roll = self:int(1, total)
	for i, row in ipairs(rows) do
		roll = roll - max(0, floor(row[2]))
		if roll <= 0 then
			return row[1], i
		end
	end
	return rows[#rows][1], #rows
end

function C.rng(seed)
	local s = floor(num(seed, 1)) % MOD
	if s <= 0 then
		s = s + MOD - 1
	end
	local r = setmetatable({s = s}, Rng)
	r:next()
	return r
end

function C.hash(text)
	local h = 5381
	text = tostring(text)
	for i = 1, #text do
		h = (h * 33 + text:byte(i)) % MOD
	end
	return h > 0 and h or 1
end

function C.weekSeed(cfg, week)
	return C.hash("community week " .. tostring(floor(num(week))) .. " " .. tostring(cfg.week.seedSalt or ""))
end

function C.mod(cfg, key)
	for _, m in ipairs(cfg.week.pool) do
		if m.key == key then
			return m
		end
	end
	return nil
end

-- the seeded draw: a list of keys (pool order), never two of one group
function C.pickModifiers(cfg, week)
	local r = C.rng(C.weekSeed(cfg, week))
	local count = r:weighted(cfg.week.count) or 1
	local rows, groups, picked = {}, {}, {}
	for _, m in ipairs(cfg.week.pool) do
		rows[#rows + 1] = {m, m.weight or 100}
	end
	for _ = 1, count do
		local left = {}
		for _, row in ipairs(rows) do
			if not picked[row[1].key] and not (row[1].group and groups[row[1].group]) then
				left[#left + 1] = row
			end
		end
		local m = r:weighted(left)
		if not m then
			break
		end
		picked[m.key] = true
		if m.group then
			groups[m.group] = true
		end
	end
	local out = {}
	for _, m in ipairs(cfg.week.pool) do
		if picked[m.key] then
			out[#out + 1] = m.key
		end
	end
	return out
end

-- keys a staff member typed ("ember_tides, gilded_week") -> a valid key list, or nil and why
function C.checkKeys(cfg, text)
	local keys, seen, groups = {}, {}, {}
	for k in tostring(text or ""):gmatch("[%w_]+") do
		local m = C.mod(cfg, k)
		if not m then
			return nil, "Unknown modifier " .. k .. "."
		end
		if seen[k] then
			return nil, "Twice: " .. k .. "."
		end
		if m.group and groups[m.group] then
			return nil, "Two modifiers of one group: " .. groups[m.group] .. " and " .. k .. "."
		end
		seen[k] = true
		if m.group then
			groups[m.group] = k
		end
		keys[#keys + 1] = k
	end
	if #keys == 0 then
		return nil, "Name at least one modifier."
	end
	if #keys > 3 then
		return nil, "Three modifiers at most."
	end
	return keys
end

-- server_config text "<week>:<key>,<key>" <-> week, keys
function C.encodeOverride(week, keys)
	return tostring(floor(num(week))) .. ":" .. table.concat(keys or {}, ",")
end

function C.decodeOverride(text)
	local w, list = tostring(text or ""):match("^(%d+):([%w_,]*)$")
	if not w then
		return nil, nil
	end
	local keys = {}
	for k in list:gmatch("[%w_]+") do
		keys[#keys + 1] = k
	end
	return tonumber(w), keys
end

-- the modifier definitions of a week: the override when it is for that week and valid, else the draw.
-- Returns defs, source ("staff" | "seed")
function C.weekModifiers(cfg, week, overrideText)
	local ow, okeys = C.decodeOverride(overrideText)
	local keys, source = nil, "seed"
	if ow and ow == week and okeys and #okeys > 0 then
		keys = C.checkKeys(cfg, table.concat(okeys, ","))
		if keys then
			source = "staff"
		end
	end
	keys = keys or C.pickModifiers(cfg, week)
	local defs = {}
	for _, k in ipairs(keys) do
		defs[#defs + 1] = C.mod(cfg, k)
	end
	return defs, source
end

-- ===================================================================== hooks (all neutral with no modifiers / buffs)
-- the calendar bonuses of the active modifiers merged: {tierChance = 1.5, goblin = 2} (multiplied), or nil
function C.eventBonus(mods)
	local out, any = {}, false
	for _, m in ipairs(mods or {}) do
		for k, v in pairs(m.events or {}) do
			out[k] = (out[k] or 1) * num(v, 1)
			any = true
		end
	end
	return any and out or nil
end

-- the bestiary family of a monster name: lookup(nameLower) -> family or nil (the bestiary), else the config words
function C.familyOf(cfg, name, lookup)
	name = tostring(name or ""):lower()
	if name == "" then
		return nil
	end
	if lookup then
		local f = lookup(name)
		if f then
			return f
		end
	end
	for fam, words in pairs(cfg.week.familyWords or {}) do
		for _, w in ipairs(words) do
			if name:find(w, 1, true) then
				return fam
			end
		end
	end
	return nil
end

-- 1 + the family bonus of `kind` ("xp" / "loot") of the active modifiers for a monster of `family`
function C.familyMult(mods, family, kind)
	local add = 0
	if family then
		for _, m in ipairs(mods or {}) do
			if m.family == family then
				add = add + num(m[kind])
			end
		end
	end
	return 1 + add
end

-- the experience multiplier of a kill: stage xp windows x the family modifier
function C.xpMult(cfg, buffs, mods, now, family)
	return (1 + C.stageBonus(cfg, buffs, now, "xp")) * C.familyMult(mods, family, "xp")
end

-- the Chaos loot multiplier (loot_config.lua rateMult): stage loot windows x the family modifier
function C.lootMult(cfg, buffs, mods, now, family)
	return (1 + C.stageBonus(cfg, buffs, now, "loot")) * C.familyMult(mods, family, "loot")
end

-- the reputation multiplier (factions.lua F.gain)
function C.repMult(cfg, buffs, mods, now)
	local add = C.stageBonus(cfg, buffs, now, "rep")
	for _, m in ipairs(mods or {}) do
		add = add + num(m.rep)
	end
	return 1 + add
end

-- the rift's world modifiers (rift_core.lua R.hooks.world): nil, or {keyChance, rewardMult, extraMods, note}
function C.riftWorld(cfg, buffs, mods, now)
	local wm = {keyChance = C.stageBonus(cfg, buffs, now, "riftKey"), rewardMult = 0, extraMods = 0}
	local names = {}
	for _, m in ipairs(mods or {}) do
		if num(m.riftMods) > 0 or num(m.riftReward) > 0 then
			wm.extraMods = wm.extraMods + floor(num(m.riftMods))
			wm.rewardMult = wm.rewardMult + num(m.riftReward)
			names[#names + 1] = m.name
		end
	end
	if wm.keyChance <= 0 and wm.rewardMult <= 0 and wm.extraMods <= 0 then
		return nil
	end
	wm.note = #names > 0 and table.concat(names, ", ") or nil
	return wm
end

-- percent chance that a crafting orb is kept (0 = always used up)
function C.orbKeep(mods)
	local p = 0
	for _, m in ipairs(mods or {}) do
		p = p + num(m.orbKeep)
	end
	return min(90, p)
end

-- ===================================================================== payload, buff bar, login
local function clock(seconds)
	seconds = max(0, floor(num(seconds)))
	local d, h, m = floor(seconds / 86400), floor(seconds % 86400 / 3600), floor(seconds % 3600 / 60)
	if d > 0 then
		return string.format("%dd %dh", d, h)
	end
	if h > 0 then
		return string.format("%dh %dm", h, m)
	end
	return string.format("%dm", max(1, m))
end
C.clock = clock

-- ctx = {now, period, finish, progress, buffs, mods, modSource, weekEnd, entry, day, rank, top = ranked list, near,
--        gold, realm, realmName}
function C.payload(cfg, ctx)
	local now = ctx.now
	local g = cfg.goal
	local buffs = ctx.buffs or {}
	local stages = {}
	for i, s in ipairs(g.stages) do
		local w = buffs[i]
		local open = w and num(w.endsAt) > now
		stages[#stages + 1] = {i = i, pct = s.pct, key = s.key, n = s.name, d = s.text, s = s.short, h = s.hours,
			done = C.stageAt(cfg, ctx.progress) >= i, left = open and (w.endsAt - now) or nil}
	end
	local e = ctx.entry or C.newEntry()
	local today = e.day == ctx.day and e.dayTotal or 0
	local top = {}
	for i, r in ipairs(ctx.top or {}) do
		if i > num(g.topShown, 5) then
			break
		end
		top[#top + 1] = {n = r.name, p = r.points}
	end
	local srcs = {}
	for _, s in ipairs(g.sources) do
		local mine = e.day == ctx.day and num(e.daySrc[s.key]) or 0
		srcs[#srcs + 1] = {k = s.key, n = s.name, cap = s.dailyCap, mine = mine}
	end
	local mods = {}
	for _, m in ipairs(ctx.mods or {}) do
		mods[#mods + 1] = {k = m.key, n = m.name, d = m.text}
	end
	local b = cfg.brazier
	local r = g.rewards
	local room = C.donation(cfg, e, b.maxGold, ctx.day) -- the gold one donation could still take today
	return {
		now = now,
		goal = {n = g.name, d = g.text, period = ctx.period, left = max(0, num(ctx.finish) - now), target = g.target,
			p = floor(num(ctx.progress)), pct = floor(C.pct(cfg, ctx.progress) * 10) / 10, realm = ctx.realm,
			rn = ctx.realmName},
		stages = stages,
		sources = srcs,
		mine = {p = e.points, today = today, cap = g.dailyCap, rank = ctx.rank, token = r.token and r.token.minPoints,
			tokenText = r.token and r.token.text, title = r.title, top = r.top},
		top = top,
		week = {mods = mods, left = max(0, num(ctx.weekEnd) - now), staff = ctx.modSource == "staff" or nil},
		brazier = {near = ctx.near and true or false, min = b.minGold, max = b.maxGold, gold = floor(num(ctx.gold)),
			per = (C.source(cfg, "brazier") or {}).perGold, room = room}
	}
end

-- the buff bar items (data/lib/chaos_buffs.lua, source "community"): the open stage windows and the week's modifiers.
-- kind = "stage" | "week"
function C.buffItems(cfg, buffs, mods, now, weekEnd, kind)
	local out = {}
	if kind == "stage" then
		for _, a in ipairs(C.activeStages(cfg, buffs, now)) do
			local s = a.stage
			out[#out + 1] = {key = "community_" .. s.key, name = s.name, icon = "buff:community_" .. s.key, kind = "buff",
				prio = 18, leftMs = a.left * 1000,
				desc = string.format("Community goal %d%%: %s for everyone online.", s.pct, s.text)}
		end
	else
		for _, m in ipairs(mods or {}) do
			out[#out + 1] = {key = "wmod_" .. m.key, name = m.name, icon = "buff:wmod_" .. m.key, kind = "buff", prio = 19,
				leftMs = weekEnd and weekEnd > now and (weekEnd - now) * 1000 or nil,
				desc = "World modifier of the week: " .. m.text}
		end
	end
	return out
end

-- the login lines: the goal and the week
function C.loginLines(cfg, progress, buffs, mods, now, finish, lang)
	local lines = {}
	local active = {}
	for _, a in ipairs(C.activeStages(cfg, buffs, now)) do
		active[#active + 1] = T(lang, "%s (%s left)", a.stage.name, clock(a.left))
	end
	lines[#lines + 1] = T(lang, "Community goal \"%s\": %d%% (%s left this period)%s.", cfg.goal.name,
		floor(C.pct(cfg, progress)), clock(finish - now), #active > 0 and T(lang, "; active: %s", table.concat(active, ", ")) or "")
	if #(mods or {}) > 0 then
		local parts = {}
		for _, m in ipairs(mods) do
			parts[#parts + 1] = m.name .. ": " .. T(lang, m.text)
		end
		lines[#lines + 1] = T(lang, "World modifiers this week - %s", table.concat(parts, " "))
	end
	return lines
end

-- ===================================================================== config check
function C.validate(cfg)
	local p = {}
	local g = cfg.goal
	if num(g.target) <= 0 then
		p[#p + 1] = "goal.target must be > 0"
	end
	local last = 0
	local keys = {}
	for i, s in ipairs(g.stages) do
		if num(s.pct) <= last or num(s.pct) > 100 then
			p[#p + 1] = "stage " .. i .. ": percents must rise and stay <= 100"
		end
		last = num(s.pct)
		if not tostring(s.key or ""):match("^[a-z_]+$") or keys[s.key] then
			p[#p + 1] = "stage " .. i .. ": key"
		end
		keys[s.key] = true
		if num(s.hours) <= 0 or type(s.bonus) ~= "table" or not s.name or not s.text then
			p[#p + 1] = "stage " .. i .. ": hours, bonus, name, text"
		end
	end
	for _, s in ipairs(g.sources) do
		if num(s.points) <= 0 then
			p[#p + 1] = "source " .. tostring(s.key) .. ": points"
		end
	end
	if not C.source(cfg, "brazier") then
		p[#p + 1] = "the brazier source is missing"
	end
	local mk = {}
	for _, m in ipairs(cfg.week.pool) do
		if not tostring(m.key or ""):match("^[a-z_]+$") or mk[m.key] then
			p[#p + 1] = "modifier key " .. tostring(m.key)
		end
		mk[m.key] = true
		if not m.name or not m.text or num(m.weight, 100) <= 0 then
			p[#p + 1] = "modifier " .. tostring(m.key) .. ": name, text, weight"
		end
		local effect = m.events or m.family or num(m.riftMods) > 0 or num(m.riftReward) > 0 or num(m.orbKeep) > 0 or num(m.rep) > 0
		if not effect then
			p[#p + 1] = "modifier " .. tostring(m.key) .. ": no effect"
		end
		if m.family and num(m.xp) <= 0 and num(m.loot) <= 0 then
			p[#p + 1] = "modifier " .. tostring(m.key) .. ": a family needs xp or loot"
		end
	end
	for _, row in ipairs(cfg.week.count) do
		if num(row[1]) < 1 or num(row[1]) > 3 then
			p[#p + 1] = "week.count: 1 to 3 modifiers"
		end
	end
	if g.realms ~= "together" and g.realms ~= "separate" then
		p[#p + 1] = "goal.realms must be together or separate"
	end
	return p
end

return C
