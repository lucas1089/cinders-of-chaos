-- Chaos Pact and account storage: the rules, without engine calls (pact.lua, stash.lua; server/tests/pact_test.lua).
--
-- An account's state:  {pactEnds = unix time (0 = never), lastClaim = YYYYMMDD, extras = {key = amount}, premium = bool}
--
--   ChaosPactCore.active(state, now)                    true while the Pact runs
--   ChaosPactCore.limit(cfg, state, key, now)           the account's limit for a cfg.limits key
--   ChaosPactCore.limits(cfg, state, now)               every limit, plus stashSpecial = {kind = true}
--   ChaosPactCore.breakdown(cfg, state, now)            rows for the client: {key, label, free, pact, extra, total, max}
--   ChaosPactCore.extendPact(cfg, endsAt, now)          new end time of one purchase, or nil + error text
--   ChaosPactCore.claim(cfg, state, now, dayKey)        coins of today's claim, or nil + error text
--   ChaosPactCore.extraMax(cfg, key)                    how many of an extra an account may own (nil: no such extra)
--   ChaosPactCore.extraCheck(cfg, state, key, amount)   nil when `amount` (default 1) more can be bought, else the error text
--   ChaosPactCore.daysLeft(endsAt, now)                 whole days left, rounded up (0 when over)
--
-- Stash tabs. An entry is {item = id, tab = n, kind = "orbs" | "gems" | "keys" | nil}. Tabs 1.. are general tabs of
-- cfg.stash.tabSize item types; a general tab above the account's stashTabs limit is withdraw-only. Special tabs (ids in
-- cfg.stash.special) take only their kind and exist while the account owns them. Nothing is ever deleted: entries that do
-- not fit any more stay where they are, read-only, until withdrawn.
--   ChaosPactCore.tabWritable(cfg, lim, tab)            may new items go into this tab
--   ChaosPactCore.layout(cfg, lim, entries)             gives every entry a tab (tab 0 = not placed yet, the stash of
--                                                       before tabs) and moves entries of a special kind into their
--                                                       owned special tab while it has room; returns {{item, tab}} moves
--   ChaosPactCore.depositTab(cfg, lim, entries, item, kind)  the tab for a deposit (the entry's own tab while writable,
--                                                       else a writable tab with room), or nil + "full" | "locked"
--   ChaosPactCore.tabsView(cfg, lim, entries)           the tab bar: {{id, name, used, size, locked, special}}
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
	local out = {stashSpecial = {}}
	for key in pairs(cfg.limits) do
		out[key] = P.limit(cfg, state, key, now)
	end
	for _, s in ipairs(cfg.stash.special) do
		out.stashSpecial[s.kind] = extraOf(state, s.extra) > 0
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

-- ---------------------------------------------------------------- stash tabs
local function specialByTab(cfg, tab)
	for _, s in ipairs(cfg.stash.special) do
		if s.tab == tab then
			return s
		end
	end
	return nil
end

local function specialByKind(cfg, kind)
	for _, s in ipairs(cfg.stash.special) do
		if s.kind == kind then
			return s
		end
	end
	return nil
end

function P.tabWritable(cfg, lim, tab)
	tab = int(tab)
	local s = specialByTab(cfg, tab)
	if s then
		return lim.stashSpecial[s.kind] == true
	end
	return tab >= 1 and tab <= int(lim.stashTabs)
end

local function sizeOf(cfg, tab)
	local s = specialByTab(cfg, tab)
	return s and int(s.size) or int(cfg.stash.tabSize)
end

local function counts(entries)
	local used = {}
	for _, e in ipairs(entries) do
		local t = int(e.tab)
		if t > 0 then
			used[t] = (used[t] or 0) + 1
		end
	end
	return used
end

-- a general tab for one more entry: the first writable one with room, else (allowLocked) the first tab above the limit
-- with room (where entries that do not fit any more are kept, read-only)
local function generalTab(cfg, lim, used, allowLocked)
	local size = int(cfg.stash.tabSize)
	local t = 1
	while true do
		local writable = t <= int(lim.stashTabs)
		if not writable and not allowLocked then
			return nil
		end
		if (used[t] or 0) < size then
			return t
		end
		t = t + 1
	end
end

local function specialTab(cfg, lim, used, kind)
	local s = kind and specialByKind(cfg, kind)
	if s and lim.stashSpecial[kind] and (used[s.tab] or 0) < int(s.size) then
		return s.tab
	end
	return nil
end

function P.layout(cfg, lim, entries)
	local used = counts(entries)
	local moves = {}
	-- entries in an unknown tab (a special tab id that is no longer configured, a negative id) are placed again
	for _, e in ipairs(entries) do
		local t = int(e.tab)
		if t > 100 and not specialByTab(cfg, t) then
			used[t] = (used[t] or 1) - 1
			e.tab = 0
		end
	end
	local order = {}
	for i, e in ipairs(entries) do
		order[i] = e
	end
	table.sort(order, function(a, b) return int(a.item) < int(b.item) end)
	for _, e in ipairs(order) do
		local t = int(e.tab)
		local target
		if t <= 0 then
			target = specialTab(cfg, lim, used, e.kind) or generalTab(cfg, lim, used, true)
		elseif not specialByTab(cfg, t) and e.kind then
			target = specialTab(cfg, lim, used, e.kind) -- an orb in a general tab moves to the owned Orbs tab
		end
		if target and target ~= t then
			if t > 0 then
				used[t] = (used[t] or 1) - 1
			end
			used[target] = (used[target] or 0) + 1
			e.tab = target
			moves[#moves + 1] = {item = e.item, tab = target}
		end
	end
	return moves
end

function P.depositTab(cfg, lim, entries, item, kind)
	local used = counts(entries)
	local own
	for _, e in ipairs(entries) do
		if int(e.item) == int(item) then
			own = e
			break
		end
	end
	if own and int(own.tab) > 0 and P.tabWritable(cfg, lim, own.tab) then
		return int(own.tab)
	end
	local target = specialTab(cfg, lim, used, kind) or generalTab(cfg, lim, used, false)
	if target then
		return target
	end
	if own or next(used) ~= nil then
		-- full: say whether entries sit in withdraw-only tabs (the Pact ran out, or a staff change)
		for t in pairs(used) do
			if not P.tabWritable(cfg, lim, t) then
				return nil, "locked"
			end
		end
	end
	return nil, "full"
end

function P.tabsView(cfg, lim, entries)
	local used = counts(entries)
	local view = {}
	local highest = int(lim.stashTabs)
	for t in pairs(used) do
		if t < 100 and t > highest then
			highest = t
		end
	end
	for t = 1, highest do
		view[#view + 1] = {id = t, name = tostring(t), used = used[t] or 0, size = sizeOf(cfg, t),
			locked = not P.tabWritable(cfg, lim, t)}
	end
	for _, s in ipairs(cfg.stash.special) do
		if lim.stashSpecial[s.kind] or (used[s.tab] or 0) > 0 then
			view[#view + 1] = {id = s.tab, name = s.name, used = used[s.tab] or 0, size = int(s.size),
				locked = not P.tabWritable(cfg, lim, s.tab), special = s.kind}
		end
	end
	return view
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
