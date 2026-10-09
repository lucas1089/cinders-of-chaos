-- Guild siege: pure logic (no engine calls), shared by siege.lua and server/tests/siege_test.lua.
--   ChaosSiege.nextStart(now, cfg)              unix time of the next weekly start (strictly after now)
--   ChaosSiege.signupsOpen(now, at, cfg)        whether sign-ups for the siege at `at` are still open
--   ChaosSiege.signupError(info, cfg)           nil or the reason a !siege join is refused
--   ChaosSiege.leaveError(info, cfg)            nil or the reason a !siege leave is refused
--   ChaosSiege.brackets(guilds, cfg)            signed-up guilds -> brackets (arenas) of 2..perBracket guilds, waitlist
--   ChaosSiege.layout(a, bracket)               geometry of one bracket: arena, obelisk, capture area, 4 bases
--   ChaosSiege.footprint(L)                     every tile of arena + bases: {x, y, z, wall, ground}
--   ChaosSiege.where(pos, L)                    "arena" | "base", base slot | nil
--   ChaosSiege.onPoint(pos, L, radius)          whether pos is on the capture area
--   ChaosSiege.control(counts, exclusive)       holder guild id | nil, contested
--   ChaosSiege.standings(teams)                 sorted copy with place (score, kills, sign-up order)
--   ChaosSiege.winner(list)                     the bracket winner of standings (nil: no score, or a tie for first)
--   ChaosSiege.rewardFor(isWinner, presence, cfg)  "winner" | "others" | nil and the reward table
--   ChaosSiege.championOf(champions, guildId, now)  champion entry while the title lasts
--   ChaosSiege.durationText(s), clock(s), whenText(t), calendarEvent(cfg)   texts
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible (integer arithmetic through math.floor).

ChaosSiege = ChaosSiege or {}
local S = ChaosSiege

S.WEEKDAYS = {"Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"}

-- ---------------------------------------------------------------- schedule
function S.nextStart(now, cfg)
	local d = os.date("*t", now)
	for i = 0, 8 do
		local t = os.time({year = d.year, month = d.month, day = d.day + i, hour = cfg.hour or 20, min = cfg.minute or 0, sec = 0})
		if t > now and os.date("*t", t).wday == cfg.weekday then
			return t
		end
	end
	return now + 7 * 86400
end

function S.signupsOpen(now, at, cfg)
	return now < at - (cfg.signupCloseMinutes or 0) * 60
end

-- "Saturday 20:00"
function S.whenText(at)
	local d = os.date("*t", at)
	return string.format("%s %02d:%02d", S.WEEKDAYS[d.wday], d.hour, d.min)
end

function S.capacity(cfg)
	return (cfg.perBracket or 4) * (cfg.maxBrackets or 1)
end

-- info = {guildId, guildName, rank (guild level, 0 = none), members, signed (bool), count (guilds signed up),
--         open (sign-ups open), running (a siege is running)}
function S.signupError(info, cfg)
	if not info.guildId or info.guildId == 0 then
		return "You are not in a guild."
	end
	if (info.rank or 0) < (cfg.signupRank or 2) then
		return (cfg.signupRank or 2) >= 3 and "Only the guild leader can sign the guild up."
			or "Only the guild leader or a vice-leader can sign the guild up."
	end
	if info.signed then
		return info.guildName and (info.guildName .. " is already signed up for the next siege.")
			or "Your guild is already signed up for the next siege."
	end
	if info.running then
		return "A siege is running. Sign-ups for the next one open when it is over."
	end
	if not info.open then
		return "Sign-ups for this siege are closed."
	end
	if (info.members or 0) < (cfg.minMembers or 1) then
		return string.format("Your guild needs at least %d members to sign up (it has %d).", cfg.minMembers or 1, info.members or 0)
	end
	if (info.count or 0) >= S.capacity(cfg) then
		return string.format("The siege is full (%d guilds).", S.capacity(cfg))
	end
	return nil
end

function S.leaveError(info, cfg)
	if not info.guildId or info.guildId == 0 then
		return "You are not in a guild."
	end
	if (info.rank or 0) < (cfg.signupRank or 2) then
		return "Only the guild leader or a vice-leader can withdraw the guild."
	end
	if not info.signed then
		return "Your guild is not signed up."
	end
	if info.running or not info.open then
		return "Sign-ups for this siege are closed: the guild can no longer withdraw."
	end
	return nil
end

-- guilds: list in sign-up order ({id, name, ...}). Brackets of nearly equal size (they differ by at most one), each with
-- at least minGuilds and at most perBracket guilds, at most maxBrackets of them; the guilds that do not fit wait
-- (first come). Returns brackets ({{guild, ...}, ...}), waitlist.
function S.brackets(guilds, cfg)
	local per, maxB, minG = cfg.perBracket or 4, cfg.maxBrackets or 1, math.max(2, cfg.minGuilds or 2)
	local n = math.min(#guilds, per * maxB)
	local waiting = {}
	for i = n + 1, #guilds do
		waiting[#waiting + 1] = guilds[i]
	end
	if n < minG then
		for i = n, 1, -1 do
			table.insert(waiting, 1, guilds[i])
		end
		return {}, waiting
	end
	local count = math.floor((n + per - 1) / per)
	-- never a bracket below minGuilds (e.g. 5 guilds with minGuilds 3 and perBracket 4: one bracket of 4, one waits)
	while count > 1 and math.floor(n / count) < minG do
		count = count - 1
	end
	local used = math.min(n, count * per)
	for i = n, used + 1, -1 do
		table.insert(waiting, 1, guilds[i])
	end
	local out = {}
	for b = 1, count do
		out[b] = {}
	end
	-- sizes: the first (used % count) brackets get one more
	local base, extra = math.floor(used / count), used % count
	local i = 1
	for b = 1, count do
		local size = base + (b <= extra and 1 or 0)
		for _ = 1, size do
			out[b][#out[b] + 1] = guilds[i]
			i = i + 1
		end
	end
	return out, waiting
end

-- ---------------------------------------------------------------- geometry
-- Bracket b's footprint starts at origin.x + (b - 1) * stride. The arena is a square of inner x inner floor tiles with
-- a wall around it; the base rooms (baseInnerW x baseInnerH) sit outside the middle of each side and share the arena
-- wall: no tile connects a base to the arena, a forcefield gate next to that wall takes the player in.
function S.layout(a, bracket)
	bracket = bracket or 1
	local depth = a.baseInnerH + 1 -- tiles a base adds beyond the arena wall
	local size = a.inner + 2 + 2 * depth -- footprint width and height
	local stride = size + (a.bracketGap or 0)
	local ox, oy, z = a.origin.x + (bracket - 1) * stride, a.origin.y, a.origin.z
	local L = {z = z, bracket = bracket, size = size, stride = stride}
	L.box = {x1 = ox, y1 = oy, x2 = ox + size - 1, y2 = oy + size - 1}
	local x1, y1 = ox + depth, oy + depth
	L.arena = {x1 = x1, y1 = y1, x2 = x1 + a.inner + 1, y2 = y1 + a.inner + 1}
	local half = math.floor((a.inner + 1) / 2)
	local cx, cy = x1 + half, y1 + half
	L.center = {x = cx, y = cy, z = z}
	local hw = math.floor((a.baseInnerW + 1) / 2)
	local mid = math.floor((a.baseInnerH + 1) / 2)
	local A = L.arena
	-- 1 north, 2 east, 3 south, 4 west
	L.bases = {
		{rect = {x1 = cx - hw, y1 = A.y1 - depth, x2 = cx + hw, y2 = A.y1},
			gate = {x = cx, y = A.y1 - 1, z = z}, out = {x = cx, y = A.y1 + 1, z = z}, spawn = {x = cx, y = A.y1 - mid, z = z}},
		{rect = {x1 = A.x2, y1 = cy - hw, x2 = A.x2 + depth, y2 = cy + hw},
			gate = {x = A.x2 + 1, y = cy, z = z}, out = {x = A.x2 - 1, y = cy, z = z}, spawn = {x = A.x2 + mid, y = cy, z = z}},
		{rect = {x1 = cx - hw, y1 = A.y2, x2 = cx + hw, y2 = A.y2 + depth},
			gate = {x = cx, y = A.y2 + 1, z = z}, out = {x = cx, y = A.y2 - 1, z = z}, spawn = {x = cx, y = A.y2 + mid, z = z}},
		{rect = {x1 = A.x1 - depth, y1 = cy - hw, x2 = A.x1, y2 = cy + hw},
			gate = {x = A.x1 - 1, y = cy, z = z}, out = {x = A.x1 + 1, y = cy, z = z}, spawn = {x = A.x1 - mid, y = cy, z = z}}
	}
	for _, b in ipairs(L.bases) do
		local r = b.rect
		b.basins = {{x = r.x1 + 1, y = r.y1 + 1, z = z}, {x = r.x2 - 1, y = r.y2 - 1, z = z}}
		b.flags = {{x = r.x2 - 1, y = r.y1 + 1, z = z}, {x = r.x1 + 1, y = r.y2 - 1, z = z}}
		-- forcefield home on the far side of the room, opposite the gate
		b.exit = {x = 2 * b.spawn.x - b.gate.x, y = 2 * b.spawn.y - b.gate.y, z = z}
	end
	L.pillars = {}
	local q = math.max(3, math.floor(a.inner / 5))
	for _, d in ipairs({{-q, -q}, {q, -q}, {-q, q}, {q, q}, {-2 * q, -1}, {2 * q, 1}, {1, -2 * q}, {-1, 2 * q}}) do
		local px, py = cx + d[1], cy + d[2]
		if px > A.x1 + 1 and px < A.x2 - 1 and py > A.y1 + 1 and py < A.y2 - 1 then
			L.pillars[#L.pillars + 1] = {x = px, y = py, z = z}
		end
	end
	L.basins = {{x = A.x1 + 1, y = A.y1 + 1, z = z}, {x = A.x2 - 1, y = A.y1 + 1, z = z},
		{x = A.x1 + 1, y = A.y2 - 1, z = z}, {x = A.x2 - 1, y = A.y2 - 1, z = z}}
	L.radius = a.radius or 2
	return L
end

local function inRect(r, pos)
	return pos.x >= r.x1 and pos.x <= r.x2 and pos.y >= r.y1 and pos.y <= r.y2
end

-- "arena" (floor or wall of the arena), "base", slot (inside a base room, its walls included), or nil
function S.where(pos, L)
	if not pos or pos.z ~= L.z or not inRect(L.box, pos) then
		return nil
	end
	for i, b in ipairs(L.bases) do
		local r = b.rect
		-- the shared wall row belongs to the arena; the room is strictly beyond it
		if inRect(r, pos) and not inRect(L.arena, pos) then
			return "base", i
		end
	end
	if inRect(L.arena, pos) then
		return "arena"
	end
	return nil
end

function S.onPoint(pos, L, radius)
	return pos ~= nil and pos.z == L.z and math.max(math.abs(pos.x - L.center.x), math.abs(pos.y - L.center.y)) <= radius
end

-- every tile: {x, y, z, wall = bool, ground = "arena" | "point" | "base"}
function S.footprint(L, radius)
	radius = radius or L.radius or 2
	local tiles, index = {}, {}
	local function add(x, y, wall, ground)
		local k = x .. "," .. y
		local t = index[k]
		if not t then
			t = {x = x, y = y, z = L.z, wall = wall, ground = ground}
			index[k] = t
			tiles[#tiles + 1] = t
		elseif wall then
			t.wall = true
		end
	end
	local A = L.arena
	for x = A.x1, A.x2 do
		for y = A.y1, A.y2 do
			local wall = x == A.x1 or x == A.x2 or y == A.y1 or y == A.y2
			local point = math.max(math.abs(x - L.center.x), math.abs(y - L.center.y)) <= radius
			add(x, y, wall, point and "point" or "arena")
		end
	end
	for _, b in ipairs(L.bases) do
		local r = b.rect
		for x = r.x1, r.x2 do
			for y = r.y1, r.y2 do
				add(x, y, x == r.x1 or x == r.x2 or y == r.y1 or y == r.y2, "base")
			end
		end
	end
	return tiles
end

-- ---------------------------------------------------------------- capture point
-- counts = {[guildId] = members on the point}. Returns holder (guild id or nil), contested (bool).
function S.control(counts, exclusive)
	local best, bestN, atBest, present = nil, 0, 0, 0
	for id, n in pairs(counts) do
		if n > 0 then
			present = present + 1
			if n > bestN then
				best, bestN, atBest = id, n, 1
			elseif n == bestN then
				atBest = atBest + 1
			end
		end
	end
	if not best then
		return nil, false
	end
	if atBest > 1 or (exclusive and present > 1) then
		return nil, true
	end
	return best, false
end

-- teams: list of {id, name, score, kills, order (sign-up order)}. Returns a sorted copy with .place; equal score and
-- kills share a place. The winner is place 1 with a score above 0 (all at 0: no winner).
function S.standings(teams)
	local list = {}
	for _, t in ipairs(teams) do
		local c = {}
		for k, v in pairs(t) do
			c[k] = v
		end
		list[#list + 1] = c
	end
	table.sort(list, function(a, b)
		if (a.score or 0) ~= (b.score or 0) then
			return (a.score or 0) > (b.score or 0)
		end
		if (a.kills or 0) ~= (b.kills or 0) then
			return (a.kills or 0) > (b.kills or 0)
		end
		return (a.order or 0) < (b.order or 0)
	end)
	for i, t in ipairs(list) do
		local prev = list[i - 1]
		if prev and (prev.score or 0) == (t.score or 0) and (prev.kills or 0) == (t.kills or 0) then
			t.place = prev.place
		else
			t.place = i
		end
	end
	return list
end

-- the winning guild of a bracket's standings, or nil (no score at all, or a tie for first place)
function S.winner(list)
	local first, second = list[1], list[2]
	if not first or (first.score or 0) <= 0 then
		return nil
	end
	if second and second.place == first.place then
		return nil
	end
	return first
end

-- kind, reward: "winner" / "others" with cfg.reward[kind], or nil when the player was not there long enough
function S.rewardFor(isWinner, presence, cfg)
	if (presence or 0) < (cfg.minPresenceSeconds or 0) then
		return nil, nil
	end
	local kind = isWinner and "winner" or "others"
	return kind, cfg.reward[kind]
end

-- champions = {[guildId] = {name, untilAt}}
function S.championOf(champions, guildId, now)
	local c = guildId and champions[guildId]
	if c and (c.untilAt or 0) > now then
		return c
	end
	return nil
end

-- the "Guild Siege" calendar entry for events_schedule.lua (whole day; the time is in the description)
function S.calendarEvent(cfg)
	return {id = "guildsiege", name = "Guild Siege", weekdays = {cfg.weekday},
		colorlight = cfg.calendar and cfg.calendar.colorlight or "#c0392b",
		colordark = cfg.calendar and cfg.calendar.colordark or "#5e1a12",
		description = string.format("%02d:%02d server time: signed-up guilds fight for the Chaos Obelisk. "
			.. "Guild leaders sign up in Adventure > Guild Siege (at least %d members).", cfg.hour or 20, cfg.minute or 0, cfg.minMembers or 1)}
end

-- seconds -> "2d 3h", "5h 12m", "12m" (until the next siege)
function S.durationText(seconds)
	seconds = math.max(0, math.floor(seconds))
	local d, h, m = math.floor(seconds / 86400), math.floor(seconds % 86400 / 3600), math.floor(seconds % 3600 / 60)
	if d > 0 then
		return string.format("%dd %dh", d, h)
	elseif h > 0 then
		return string.format("%dh %dm", h, m)
	end
	return string.format("%dm", m)
end

-- seconds -> "12:05"
function S.clock(seconds)
	seconds = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end
