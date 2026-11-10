-- Infinity Tower seasons and the season-end top 3 chests: pure logic (no engine API). infinitytower.lua uses it,
-- tests/infinitytower_season_test.lua checks it. Numbers: Chaos.tower in chaos_constants.lua (seasonEpoch,
-- seasonLengthDays, seasonEnd). Overview: server/README.md "Infinity Tower season rewards".
--   K.epoch(cfg)                         the epoch as unix time (a number, or {year, month, day, hour} in server local time); nil: none (open)
--   K.seasonOf(cfg, now)                 -> season number (1 before the epoch), its start, its end (1, nil, nil with no epoch)
--   K.places(rows, staffGroup)           ranked rows with `place`: best floor desc, then best time asc; staff left out;
--                                        equal floor AND time share a place (1, 1, 3); rows without a floor are left out
--   K.awards(rows, seasonEnd)            -> {{guid, place, floor, time, chest}} for places 1..#chests
--   K.pendingSeasons(done, current)      -> seasons to pay out (each ended season once), or nil on a new server
--   K.chestText(chest)                   "Gold Tower Chest (15 Orb of Fate, 25 Orb of Upheaval)"
--   K.topRewards(seasonEnd, clientIdOf)  the podium for the client window (place, name, chest client id, items)
--   K.claimReward(api, row, index, milestone)  milestone claim, mark first: -> "claimed" | "already" | "points" | "room" | "db"
--                                        api.mark(bit) sets the claimed bit only while it is clear and returns true on success,
--                                        api.unmark(bit) clears it, api.give(item) -> count given, api.take(id, count)
-- Leaving a run (infinitytower_run.lua; tests/infinitytower_exit_test.lua; server/README.md "Infinity Tower: leaving a run"):
--   K.portalSpot(inner)                  local x, y of the exit portal: the south end of the lane (the arena look keeps it
--                                        open), one row above the last floor row: the 2x2 south wall pieces draw over that row
--   K.leaveRule(s)                       what a leave request does. s = {inRun, inArena, fighting, pendingAt, now, delay}:
--                                        "outside"        no run and not in an arena: refused
--                                        "stray", 0       in an arena without a run (a script reload lost it): to the temple
--                                        "pending", secs  a countdown already runs: seconds left
--                                        "now", 0         no live floor (start delay, the pause between floors): out at once
--                                        "countdown", d   a floor is being fought: out after d seconds
--   K.exitPos(entry, temple, inArena)    where a leaver lands: the entry spot; the temple when it is missing or in an arena
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.

ChaosTowerCore = ChaosTowerCore or {}
local K = ChaosTowerCore

function K.epoch(cfg)
	local e = cfg.seasonEpoch
	if type(e) == "table" then
		return os.time({year = e.year, month = e.month, day = e.day, hour = e.hour or 0, min = e.min or 0, sec = 0})
	end
	if e == nil then
		return nil -- no epoch: the launch date is open (O463)
	end
	return tonumber(e) or 0
end

-- no epoch (the launch date is open): season 1 with no start and no end, so nothing counts down and no season ends
function K.seasonOf(cfg, now)
	local epoch = K.epoch(cfg)
	if not epoch then
		return 1, nil, nil
	end
	local length = cfg.seasonLengthDays * 86400
	local number = math.floor((now - epoch) / length) + 1
	if number < 1 then
		number = 1
	end
	return number, epoch + (number - 1) * length, epoch + number * length
end

local function better(a, b)
	if a.floor ~= b.floor then
		return a.floor > b.floor
	end
	if a.time ~= b.time then
		return a.time < b.time
	end
	return a.guid < b.guid -- equal results share the place; the order among them is only for a stable list
end

-- rows = {{guid, name, floor, time, group}}
function K.places(rows, staffGroup)
	local list = {}
	for _, r in ipairs(rows or {}) do
		if (r.floor or 0) > 0 and (r.group or 1) < (staffGroup or 4) then
			list[#list + 1] = {guid = r.guid, name = r.name, floor = r.floor, time = r.time or 0, group = r.group}
		end
	end
	table.sort(list, better)
	for i, r in ipairs(list) do
		local prev = list[i - 1]
		if prev and prev.floor == r.floor and prev.time == r.time then
			r.place = prev.place
		else
			r.place = i
		end
	end
	return list
end

-- ranked = K.places(...) (possibly filtered afterwards); seasonEnd = Chaos.tower.seasonEnd
function K.awards(ranked, seasonEnd)
	local out = {}
	for _, r in ipairs(ranked) do
		local chest = seasonEnd.chests[r.place]
		if chest then
			out[#out + 1] = {guid = r.guid, name = r.name, place = r.place, floor = r.floor, time = r.time, chest = chest}
		end
	end
	return out
end

-- done = the last season paid out (server_config), current = the running season. nil done: a new server, nothing
-- earlier to pay (the caller stores current - 1). Each ended season once, oldest first.
function K.pendingSeasons(done, current)
	if done == nil then
		return nil
	end
	local out = {}
	for s = done + 1, current - 1 do
		out[#out + 1] = s
	end
	return out
end

function K.chestText(chest)
	local parts = {}
	for _, it in ipairs(chest.items) do
		parts[#parts + 1] = it.count .. " " .. (it.name or ("item " .. it.id))
	end
	return string.format("%s (%s)", chest.name, table.concat(parts, ", "))
end

-- The claimed bit is written BEFORE the items are given, so a second claim (double click, two packets) finds it
-- set and gets nothing. If the mark fails, nothing is given. If the items do not fit, they are taken back and the
-- bit is cleared again (a failed clear is logged by the caller through api.log, the reward stays unclaimable then).
function K.claimReward(api, row, index, milestone)
	local bit = 2 ^ (index - 1)
	if math.floor((row.claimed_mask or 0) / bit) % 2 == 1 then
		return "already"
	end
	if (row.points or 0) < milestone.points then
		return "points"
	end
	if not api.mark(bit) then
		return "db"
	end
	local granted = {}
	local ok = true
	for _, item in ipairs(milestone.items) do
		local given = api.give(item) or 0
		if given > 0 then
			granted[#granted + 1] = {id = item.id, count = given}
		end
		if given < item.count then
			ok = false
			break
		end
	end
	if ok then
		return "claimed"
	end
	for _, g in ipairs(granted) do
		api.take(g.id, g.count)
	end
	if not api.unmark(bit) and api.log then
		api.log("could not clear claimed bit " .. index .. " after a failed give")
	end
	return "room"
end

-- ------------------------------------------------------------------ leaving a run
function K.portalSpot(inner)
	return math.floor(inner / 2) + 1, inner - 1
end

function K.leaveRule(s)
	if not s.inRun then
		if s.inArena then
			return "stray", 0
		end
		return "outside", 0
	end
	local now = s.now or 0
	if s.pendingAt and s.pendingAt > now then
		return "pending", s.pendingAt - now
	end
	local delay = math.floor(tonumber(s.delay) or 0)
	if s.fighting and delay > 0 then
		return "countdown", delay
	end
	return "now", 0
end

function K.exitPos(entry, temple, inArena)
	if entry and not (inArena and inArena(entry)) then
		return entry
	end
	return temple
end

K.placeNames = {"1st", "2nd", "3rd"}

-- the podium of the client window: place 1..n, chest name, chest look (client id), contents text
function K.topRewards(seasonEnd, clientIdOf)
	local out = {}
	for place, chest in ipairs(seasonEnd.chests) do
		local items = {}
		for _, it in ipairs(chest.items) do
			items[#items + 1] = {name = it.name, count = it.count}
		end
		out[place] = {place = place, name = chest.name, id = clientIdOf and clientIdOf(chest.chestId) or chest.chestId,
			text = K.chestText(chest), items = items}
	end
	return out
end

return K
