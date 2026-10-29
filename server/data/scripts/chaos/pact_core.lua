-- Chaos Pact and account storage: the rules, without engine calls (pact.lua, stash.lua; server/tests/pact_test.lua).
--
-- An account's state:  {pactEnds = unix time (0 = never), lastClaim = YYYYMMDD, extras = {key = amount}, premium = bool}
--
--   ChaosPactCore.active(state, now)                    true while the Pact runs
--   ChaosPactCore.limit(cfg, state, key, now)           the account's limit for a cfg.limits key
--   ChaosPactCore.limits(cfg, state, now)               every limit
--   ChaosPactCore.breakdown(cfg, state, now)            rows for the client: {key, label, free, pact, extra, total, max}
--   ChaosPactCore.extendPact(cfg, endsAt, now, days?)   new end time of one purchase (cfg.pact.days, or `days` of a bundle),
--                                                       or nil + error text
--   ChaosPactCore.claim(cfg, state, now, dayKey)        Pact Marks of today's claim, or nil + error text
--   ChaosPactCore.expiry(cfg, endsAt, premiumDays, now) the warning due now: {level = 3 | 1, days, both} or nil
--   ChaosPactCore.shelfCheck(cfg, marks, owned, key, now?)  nil when the Marks shelf item can be bought, else the error text
--   ChaosPactCore.monthlyItem(cfg, now?) / monthIndex(count, year, month) / shelf(cfg, now?)  the month's slot of the shelf (server month)
--   ChaosPactCore.monthExp(rows, month)                 experience the +10% added in `month` from rows {month, exp}
--   ChaosPactCore.extraMax(cfg, key)                    how many of an extra an account may own (nil: no such extra)
--   ChaosPactCore.extraCheck(cfg, state, key, amount)   nil when `amount` (default 1) more can be bought, else the error text
--   ChaosPactCore.daysLeft(endsAt, now)                 whole days left, rounded up (0 when over)
--
-- Stash tabs (general tabs, affinity tabs, what goes where): stash_core.lua; the limit stashTabs and the extras that buy
-- tabs live here.
--
-- Saved builds: rows {slot, name, code}; slots 1..limit are editable, higher slots read-only (load or delete only).
--   ChaosPactCore.buildEditable(lim, slot)
--   ChaosPactCore.freeBuildSlot(lim, rows)              the first editable empty slot, or nil
--
-- Characters:
--   ChaosPactCore.characterIndex(ids, guid)             1-based position of guid among the account's ids (sorted)
--   ChaosPactCore.legacySlots(cfg, count, owned)        character slots to grant an account that already has `count`
--
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.

ChaosPactCore = ChaosPactCore or {}
local P = ChaosPactCore

local DAY = 86400

local function int(v)
	v = tonumber(v) or 0
	if v ~= v then
		return 0
	end
	return math.floor(v)
end

function P.active(state, now)
	return state ~= nil and int(state.pactEnds) > (now or os.time())
end

function P.daysLeft(endsAt, now)
	local left = int(endsAt) - now
	if left <= 0 then
		return 0
	end
	return math.floor((left + DAY - 1) / DAY)
end

local function extraOf(state, key)
	local e = state and state.extras
	return math.max(0, int(e and e[key]))
end

-- the most of an extra an account may own (from the limit's maxExtra or the extra's own max)
function P.extraMax(cfg, key)
	local x = cfg.extras[key]
	if not x then
		return nil
	end
	if x.limit then
		return int(cfg.limits[x.limit] and cfg.limits[x.limit].maxExtra)
	end
	return int(x.max)
end

function P.limit(cfg, state, key, now)
	local l = cfg.limits[key]
	if not l then
		return 0
	end
	local value = int(l.free)
	local pact = P.active(state, now) or (l.premiumCounts and state ~= nil and state.premium == true)
	if pact then
		value = value + int(l.pact)
	end
	value = value + math.min(extraOf(state, key), int(l.maxExtra))
	if key == "charSlots" and cfg.legacyCharSlots then
		value = value + extraOf(state, cfg.legacyCharSlots) -- granted, not bought: no maxExtra
	end
	return value
end

function P.limits(cfg, state, now)
	local out = {}
	for key in pairs(cfg.limits) do
		out[key] = P.limit(cfg, state, key, now)
	end
	return out
end

function P.breakdown(cfg, state, now)
	local rows = {}
	local active = P.active(state, now)
	for _, key in ipairs(cfg.order) do
		local l = cfg.limits[key]
		local extra = math.min(extraOf(state, key), int(l.maxExtra))
		if key == "charSlots" and cfg.legacyCharSlots then
			extra = extra + extraOf(state, cfg.legacyCharSlots)
		end
		rows[#rows + 1] = {
			key = key, label = l.label, free = int(l.free), pact = int(l.pact), extra = extra,
			maxExtra = int(l.maxExtra), total = P.limit(cfg, state, key, now),
			pactActive = active or (l.premiumCounts == true and state ~= nil and state.premium == true)
		}
	end
	return rows
end

-- days: how many days one purchase adds (default cfg.pact.days; a store bundle such as the Pacto Completo adds 30 / 90 / 180)
function P.extendPact(cfg, endsAt, now, days)
	days = days and int(days) or int(cfg.pact.days)
	local base = math.max(int(endsAt), now)
	local new = base + days * DAY
	if new > now + int(cfg.pact.maxStackDays) * DAY then
		return nil, string.format(cfg.messages.pactCap, math.max(0, int(cfg.pact.maxStackDays) - days))
	end
	return new
end

function P.claim(cfg, state, now, dayKey)
	if not P.active(state, now) then
		return nil, cfg.messages.noPact
	end
	if int(state.lastClaim) >= dayKey then
		return nil, cfg.messages.alreadyClaimed
	end
	return int(cfg.pact.dailyMarks)
end

-- The warning due for a Pact that ends at endsAt: cfg.pact.warnDays is {3, 1}. level 3 from three days before the end,
-- level 1 from the last day (a smaller level replaces a bigger one). days = whole days left. both = the premium days
-- run out in the same window too (a Pacto Completo ends together: the text offers the Completo again).
-- nil when the Pact is over, not active or more than the first warning away.
function P.expiry(cfg, endsAt, premiumDays, now)
	endsAt = int(endsAt)
	if endsAt <= now then
		return nil
	end
	local days = P.daysLeft(endsAt, now)
	local level
	for _, w in ipairs(cfg.pact.warnDays or {}) do
		if days <= w and (level == nil or w < level) then
			level = w
		end
	end
	if not level then
		return nil
	end
	local prem = int(premiumDays)
	return {level = level, days = days, both = prem > 0 and prem <= level}
end

-- ---------------------------------------------------------------- Pact Marks
-- The month's slot of the shelf (cfg.marks.monthly, O317 follow-up): a pure function of the server month. The entry at
-- ((year * 12 + month - 1) mod #list) + 1; with 12 entries that is the month number. `now` is a unix time (default os.time()).
function P.monthIndex(count, year, month)
	count = int(count)
	if count < 1 then
		return nil
	end
	return ((int(year) * 12 + int(month) - 1) % count) + 1
end

-- {key, marks, monthly = true, endsAt = the first second of the next month} or nil when the list is empty
function P.monthlyItem(cfg, now)
	local list = cfg.marks.monthly or {}
	now = int(now or os.time())
	local d = os.date("*t", now)
	local i = P.monthIndex(#list, d.year, d.month)
	local it = i and list[i]
	if not it then
		return nil
	end
	local nextMonth = os.time({year = d.year + (d.month == 12 and 1 or 0), month = d.month == 12 and 1 or d.month + 1, day = 1, hour = 0, min = 0, sec = 0})
	return {key = it.key, marks = it.marks, monthly = true, endsAt = nextMonth}
end

-- the whole shelf now: the fixed rows, then the month's slot (a monthly cosmetic that is also on the fixed shelf shows once)
function P.shelf(cfg, now)
	local out = {}
	local seen = {}
	for _, it in ipairs(cfg.marks.shelf or {}) do
		out[#out + 1] = {key = it.key, marks = it.marks}
		seen[it.key] = true
	end
	local m = P.monthlyItem(cfg, now)
	if m and not seen[m.key] then
		out[#out + 1] = m
	end
	return out
end

-- shelf item: the rows of P.shelf (cfg.marks.shelf and the month's slot); owned = set of cosmetic keys the account has.
-- Marks buy only the cosmetics of the shelf (never coins, services, boosts or supplies): the check is against that list,
-- nothing else. A monthly cosmetic of another month is not on the shelf.
function P.shelfItem(cfg, key, now)
	for _, it in ipairs(P.shelf(cfg, now)) do
		if it.key == key then
			return it
		end
	end
	return nil
end

function P.shelfCheck(cfg, marks, owned, key, now)
	local it = P.shelfItem(cfg, key, now)
	if not it then
		return cfg.messages.marksNoItem
	end
	if owned and owned[key] then
		return cfg.messages.marksOwned
	end
	if int(marks) < int(it.marks) then
		return string.format(cfg.messages.marksShort, int(it.marks), int(marks))
	end
	return nil
end

-- experience the +10% added: rows {month = YYYYMM, exp}; the sum of the rows of `month`
function P.monthExp(rows, month)
	local sum = 0
	for _, r in ipairs(rows or {}) do
		if int(r.month) == int(month) then
			sum = sum + math.max(0, int(r.exp))
		end
	end
	return sum
end

function P.extraCheck(cfg, state, key, amount)
	local max = P.extraMax(cfg, key)
	amount = math.max(1, int(amount or 1))
	if not max or max <= 0 then
		return "This offer cannot be bought."
	end
	local owned = extraOf(state, key)
	if owned >= max then
		return string.format(cfg.messages.extraMax, cfg.extras[key].name, max)
	end
	if owned + amount > max then
		return string.format(cfg.messages.extraOver, owned, max, cfg.extras[key].name, amount)
	end
	return nil
end

-- ---------------------------------------------------------------- saved builds
function P.buildEditable(lim, slot)
	slot = int(slot)
	return slot >= 1 and slot <= int(lim.buildSlots)
end

function P.freeBuildSlot(lim, rows)
	local taken = {}
	for _, r in ipairs(rows) do
		taken[int(r.slot)] = true
	end
	for s = 1, int(lim.buildSlots) do
		if not taken[s] then
			return s
		end
	end
	return nil
end

-- ---------------------------------------------------------------- characters
function P.characterIndex(ids, guid)
	local sorted = {}
	for i, id in ipairs(ids) do
		sorted[i] = int(id)
	end
	table.sort(sorted)
	for i, id in ipairs(sorted) do
		if id == int(guid) then
			return i
		end
	end
	return #sorted + 1
end

-- slots an account that already holds `count` characters needs on top of the free ones and the slots it owns
function P.legacySlots(cfg, count, owned)
	return math.max(0, int(count) - int(cfg.limits.charSlots.free) - int(owned))
end

return P
