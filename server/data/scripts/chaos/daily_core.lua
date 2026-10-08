-- Daily reward login streaks, pure logic (no engine calls). Used by daily.lua; tested by server/tests/daily_test.lua.
-- Lua 5.1 / LuaJIT and 5.3 compatible.
--
-- An account record: {streak = consecutive claim days (0 = none), best = best streak ever, grace = grace charges,
--                     last = YYYYMMDD of the last claim (0 = never), claims = claims ever}
-- The 7-slot reward cycle follows the streak: slot = ((streak - 1) % 7) + 1, so day 8 of a streak is slot 1 again.
-- Grace: missing up to cfg.graceMaxMissed days in a row does not break the streak while the account has that many
-- charges (one is used per missed day). One charge is earned per cfg.graceEvery claimed days, cfg.graceMax at most.

ChaosDailyCore = ChaosDailyCore or {}
local D = ChaosDailyCore

-- ---------------------------------------------------------------- days
-- YYYYMMDD -> a day number (consecutive calendar days differ by 1; noon avoids daylight saving edges)
function D.dayNumber(key)
	key = math.floor(tonumber(key) or 0)
	if key <= 0 then
		return nil
	end
	local y, m, d = math.floor(key / 10000), math.floor(key / 100) % 100, key % 100
	return math.floor(os.time({year = y, month = m, day = d, hour = 12}) / 86400 + 0.5)
end

-- days from `last` to `today` (1 = yesterday), nil when there was no claim
function D.gap(last, today)
	local a, b = D.dayNumber(last), D.dayNumber(today)
	if not a or not b then
		return nil
	end
	return b - a
end

function D.slotOf(streak)
	streak = math.max(1, math.floor(tonumber(streak) or 1))
	return ((streak - 1) % 7) + 1
end

function D.blank()
	return {streak = 0, best = 0, grace = 0, last = 0, claims = 0}
end

-- ---------------------------------------------------------------- milestones and titles
-- the milestone reached at exactly `streak` days, or nil
function D.milestoneAt(cfg, streak)
	for _, m in ipairs(cfg.milestones or {}) do
		if m.days == streak then
			return m
		end
	end
	return nil
end

-- the first milestone above `achieved` days, or nil (all reached)
function D.nextMilestone(cfg, achieved)
	local best
	for _, m in ipairs(cfg.milestones or {}) do
		if m.days > achieved and (not best or m.days < best.days) then
			best = m
		end
	end
	return best
end

-- the title of the highest milestone with a title at or below `best` days, and its days
function D.titleFor(cfg, best)
	local title, days = nil, 0
	for _, m in ipairs(cfg.milestones or {}) do
		if m.title and m.days <= (best or 0) and m.days > days then
			title, days = m.title, m.days
		end
	end
	return title, days
end

-- ---------------------------------------------------------------- today's state
-- -> {taken, streak (the streak now: kept, or 0 when broken), next (the streak after claiming today), slot (the
--     reward slot claimable or claimed today), graceUse (charges today's claim uses), broken (a streak was lost),
--     achieved (the days already reached, for the next milestone)}
function D.view(rec, today, cfg)
	rec = rec or D.blank()
	local streak = rec.streak or 0
	local gap = D.gap(rec.last, today)
	local v = {taken = false, streak = streak, next = 1, graceUse = 0, broken = false}
	if gap == 0 and streak > 0 then
		v.taken, v.next = true, streak
	elseif gap == 1 and streak > 0 then
		v.next = streak + 1
	elseif gap and gap > 1 and streak > 0 then
		local missed = gap - 1
		if missed <= (cfg.graceMaxMissed or 1) and missed <= (rec.grace or 0) then
			v.graceUse, v.next = missed, streak + 1
		else
			v.broken, v.streak, v.next = true, 0, 1
		end
	else
		v.streak, v.next = 0, 1 -- no claim yet, or a date in the future (clock went back): start again
	end
	v.slot = D.slotOf(v.next)
	v.achieved = v.taken and v.next or (v.next - 1)
	return v
end

-- claim today: -> newRecord, result {slot, streak, graceUsed, graceGained, milestone, week (slot 7)}
-- or nil, "taken" when today's reward was already claimed
function D.claim(rec, today, cfg)
	rec = rec or D.blank()
	local v = D.view(rec, today, cfg)
	if v.taken then
		return nil, "taken"
	end
	local out = {
		streak = v.next,
		best = math.max(rec.best or 0, v.next),
		grace = math.max(0, (rec.grace or 0) - v.graceUse),
		last = today,
		claims = (rec.claims or 0) + 1
	}
	local gained = 0
	local every = cfg.graceEvery or 7
	if every > 0 and v.next % every == 0 and out.grace < (cfg.graceMax or 2) then
		out.grace = out.grace + 1
		gained = 1
	end
	return out, {slot = v.slot, streak = v.next, graceUsed = v.graceUse, graceGained = gained,
		milestone = D.milestoneAt(cfg, v.next), week = v.slot == 7}
end

-- ---------------------------------------------------------------- migration from the per-character storages
-- list = {{slot = 1..7, last = YYYYMMDD}, ...} of the account's characters (the old storages). The best one wins:
-- the most recent claim, then the higher slot. The old cycle only knew the slot, so it becomes the streak.
function D.migrate(list)
	local best
	for _, e in ipairs(list or {}) do
		local slot, last = tonumber(e.slot) or 0, tonumber(e.last) or 0
		if slot >= 1 and slot <= 7 and last > 0 then
			if not best or last > best.last or (last == best.last and slot > best.slot) then
				best = {slot = slot, last = last}
			end
		end
	end
	local rec = D.blank()
	if best then
		rec.streak, rec.best, rec.last = best.slot, best.slot, best.last
	end
	return rec
end

-- ---------------------------------------------------------------- texts
-- "5x Chaos Orb, 3x Divine Orb" from {{itemId, count}}; name(id) gives the item name
function D.itemsText(items, name)
	local parts = {}
	for _, it in ipairs(items or {}) do
		parts[#parts + 1] = string.format("%dx %s", it.count, name and name(it.itemId) or tostring(it.itemId))
	end
	return table.concat(parts, ", ")
end

function D.milestoneText(m, name)
	if not m then
		return ""
	end
	local text = D.itemsText(m.items, name)
	if m.title then
		text = text .. (text ~= "" and " and " or "") .. "the title \"" .. m.title .. "\""
	end
	return text
end

function D.lookText(title, days, pronoun)
	if not title then
		return nil
	end
	pronoun = pronoun or "He"
	local verb = pronoun == "You" and "hold" or "holds"
	return string.format("%s %s the login streak title %s (%d days in a row).", pronoun, verb, title, days)
end

-- ---------------------------------------------------------------- login window queue (pure part)
-- entries = {{key, order}}, wanted = {[key] = true}: the keys to open at this login, in order (ties by key)
function D.loginOrder(entries, wanted)
	local list = {}
	for _, e in ipairs(entries or {}) do
		if wanted[e.key] then
			list[#list + 1] = e
		end
	end
	table.sort(list, function(a, b)
		if a.order ~= b.order then
			return a.order < b.order
		end
		return a.key < b.key
	end)
	local keys = {}
	for i, e in ipairs(list) do
		keys[i] = e.key
	end
	return keys
end

return D
