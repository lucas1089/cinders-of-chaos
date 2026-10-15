-- Chaos Pact and account storage: the rules, without engine calls (pact.lua, stash.lua; server/tests/pact_test.lua).
--
-- An account's state:  {pactEnds = unix time (0 = never), lastClaim = YYYYMMDD, extras = {key = amount}, premium = bool}
--
--   ChaosPactCore.active(state, now)                    true while the Pact runs
--   ChaosPactCore.limit(cfg, state, key, now)           the account's limit for a cfg.limits key
--   ChaosPactCore.limits(cfg, state, now)               every limit
--   ChaosPactCore.breakdown(cfg, state, now)            rows for the client: {key, label, free, pact, extra, total, max}
--   ChaosPactCore.extendPact(cfg, endsAt, now)          new end time of one purchase, or nil + error text
--   ChaosPactCore.claim(cfg, state, now, dayKey)        coins of today's claim, or nil + error text
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

function P.extendPact(cfg, endsAt, now)
	local base = math.max(int(endsAt), now)
	local new = base + int(cfg.pact.days) * DAY
	if new > now + int(cfg.pact.maxStackDays) * DAY then
		return nil, string.format(cfg.messages.pactCap, int(cfg.pact.maxStackDays) - int(cfg.pact.days))
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
	return int(cfg.pact.dailyCoins)
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
