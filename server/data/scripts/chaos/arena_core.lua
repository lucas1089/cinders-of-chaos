-- Ranked PvP arena: the pure part (no engine calls), shared by arena.lua and tests/arena_test.lua.
--   rating     Elo expected score, K factor, rating change per player (1v1 and 2v2), floor
--   queue      matchmaking window, the level rule, pairing of queue entries
--   instance   slot grid, layout and footprint of a slot
--   fight      which hits are allowed, the death catch, the timeout decision, the result of a match
--   rewards    win / first win of the day
-- Settings: arena_config.lua (passed in as `cfg`). Lua 5.1 / LuaJIT and Lua 5.3 compatible.

ChaosArenaCore = ChaosArenaCore or {}
local A = ChaosArenaCore

local floor = math.floor

local function round(x)
	return floor(x + 0.5)
end

-- ------------------------------------------------------------------ rating
-- chance of a player rated `r` to beat one rated `opp`
function A.expected(r, opp)
	return 1 / (1 + 10 ^ ((opp - r) / 400))
end

function A.kFactor(cfg, matches)
	local c = cfg.rating
	if (matches or 0) < c.provisionalMatches then
		return c.kProvisional
	end
	return c.k
end

-- score: 1 win, 0.5 draw, 0 loss. Returns the new rating and the change (after the floor).
function A.rate(cfg, r, opp, score, matches)
	local delta = round(A.kFactor(cfg, matches) * (score - A.expected(r, opp)))
	local new = math.max(cfg.rating.floor, r + delta)
	return new, new - r
end

function A.average(list, field)
	local sum, n = 0, 0
	for _, e in ipairs(list) do
		sum = sum + (field and e[field] or e)
		n = n + 1
	end
	return n > 0 and sum / n or 0
end

-- teams = {{{rating, matches, left}, ...}, {...}}; winner = 1, 2 or 0 (draw).
-- Every player is rated against the other team's average. A player who left the match scores 0 whatever the team
-- did. Writes before / after / delta / score into every player entry and returns teams.
function A.rateMatch(cfg, teams, winner)
	local avg = {A.average(teams[1], "rating"), A.average(teams[2], "rating")}
	for side = 1, 2 do
		local score = winner == 0 and 0.5 or (winner == side and 1 or 0)
		local opp = avg[3 - side]
		for _, p in ipairs(teams[side]) do
			local s = p.left and 0 or score
			p.before = p.rating
			p.after, p.delta = A.rate(cfg, p.rating, opp, s, p.matches)
			p.score = s
		end
	end
	return teams
end

-- ------------------------------------------------------------------ queue
-- rating difference allowed after waiting `waited` seconds
function A.window(cfg, waited)
	local w = cfg.window
	local steps = floor(math.max(0, waited or 0) / w.everySeconds)
	return math.min(w.max, w.base + w.step * steps)
end

-- levels = list of every player's level in the match
function A.levelsOk(cfg, levels)
	local lo, hi
	for _, l in ipairs(levels) do
		lo = (not lo or l < lo) and l or lo
		hi = (not hi or l > hi) and l or hi
	end
	if not lo then
		return false
	end
	return hi - lo <= cfg.level.slack or lo >= hi * cfg.level.ratio
end

-- the lowest level that may face `level` (for the window text)
function A.levelRange(cfg, level)
	local lo = math.min(level - cfg.level.slack, math.ceil(level * cfg.level.ratio))
	local hi = math.max(level + cfg.level.slack, floor(level / cfg.level.ratio))
	return math.max(1, lo), hi
end

local function concat(a, b)
	local out = {}
	for _, v in ipairs(a) do
		out[#out + 1] = v
	end
	for _, v in ipairs(b) do
		out[#out + 1] = v
	end
	return out
end

-- entry = {mode, rating, joined, levels = {...}, parties = {[partyKey] = true}, ips = {[ip] = true}}
-- Returns true or false + reason.
function A.canPair(cfg, a, b, now)
	if a.mode ~= b.mode then
		return false, "mode"
	end
	if not A.levelsOk(cfg, concat(a.levels, b.levels)) then
		return false, "level"
	end
	for k in pairs(a.parties or {}) do
		if (b.parties or {})[k] then
			return false, "party"
		end
	end
	for k in pairs(a.ips or {}) do
		if (b.ips or {})[k] then
			return false, "ip"
		end
	end
	local waited = now - math.min(a.joined, b.joined)
	if math.abs(a.rating - b.rating) > A.window(cfg, waited) then
		return false, "rating"
	end
	return true
end

-- entries: list (any order). Oldest entry first, each takes the closest rating it may pair with.
-- Returns a list of {a, b} (the entries themselves).
function A.findMatches(cfg, entries, now)
	local list = {}
	for _, e in ipairs(entries) do
		list[#list + 1] = e
	end
	table.sort(list, function(x, y)
		if x.joined ~= y.joined then
			return x.joined < y.joined
		end
		return (x.id or 0) < (y.id or 0)
	end)
	local used, pairs_ = {}, {}
	for i, a in ipairs(list) do
		if not used[i] then
			local best, bestDiff
			for j = i + 1, #list do
				local b = list[j]
				if not used[j] and A.canPair(cfg, a, b, now) then
					local diff = math.abs(a.rating - b.rating)
					if not best or diff < bestDiff then
						best, bestDiff = j, diff
					end
				end
			end
			if best then
				used[i], used[best] = true, true
				pairs_[#pairs_ + 1] = {a, list[best]}
			end
		end
	end
	return pairs_
end

-- ------------------------------------------------------------------ instance
function A.slotOrigin(cfg, slot)
	local g = cfg.grid
	local col = slot % g.cols
	local row = floor(slot / g.cols)
	return {x = g.origin.x + col * g.spacing, y = g.origin.y + row * g.spacing, z = g.origin.z}
end

-- slot index of a position (any tile of a slot footprint), or nil
function A.slotOfPos(cfg, pos)
	for slot = 0, cfg.grid.slots - 1 do
		local L = A.layout(cfg, slot)
		if A.inSlot(L, pos) then
			return slot
		end
	end
	return nil
end

function A.layout(cfg, slot)
	local o = A.slotOrigin(cfg, slot)
	local r = cfg.room
	local L = {slot = slot, z = o.z}
	L.arena = {x1 = o.x, y1 = o.y, x2 = o.x + r.innerW + 1, y2 = o.y + r.innerH + 1}
	L.gallery = {x1 = o.x, y1 = L.arena.y2, x2 = L.arena.x2, y2 = L.arena.y2 + r.galleryH + 1}
	local cx = o.x + floor((r.innerW + 1) / 2)
	local cy = o.y + floor((r.innerH + 1) / 2)
	L.center = {x = cx, y = cy, z = o.z}
	local off = math.max(2, floor(r.innerW / 2) - 2) -- 3 for an inner width of 11: 6 tiles apart, on screen
	L.spawns = {
		[1] = {{x = cx - off, y = cy, z = o.z}, {x = cx - off, y = cy - 1, z = o.z}, {x = cx - off, y = cy + 1, z = o.z}},
		[2] = {{x = cx + off, y = cy, z = o.z}, {x = cx + off, y = cy - 1, z = o.z}, {x = cx + off, y = cy + 1, z = o.z}}
	}
	local gy = L.gallery.y1 + 1
	L.galleryspots = {
		[1] = {{x = cx - 3, y = gy, z = o.z}, {x = cx - 2, y = gy + 1, z = o.z}, {x = cx - 4, y = gy + 1, z = o.z}},
		[2] = {{x = cx + 3, y = gy, z = o.z}, {x = cx + 2, y = gy + 1, z = o.z}, {x = cx + 4, y = gy + 1, z = o.z}}
	}
	L.pillars = {{x = cx, y = cy - 2, z = o.z}, {x = cx, y = cy + 2, z = o.z}}
	L.basins = {
		{x = L.arena.x1 + 1, y = L.arena.y1 + 1, z = o.z}, {x = L.arena.x2 - 1, y = L.arena.y1 + 1, z = o.z},
		{x = L.arena.x1 + 1, y = L.arena.y2 - 1, z = o.z}, {x = L.arena.x2 - 1, y = L.arena.y2 - 1, z = o.z},
		{x = L.gallery.x1 + 1, y = L.gallery.y2 - 1, z = o.z}, {x = L.gallery.x2 - 1, y = L.gallery.y2 - 1, z = o.z}
	}
	return L
end

local function inRect(r, z, pos)
	return pos ~= nil and pos.z == z and pos.x >= r.x1 and pos.x <= r.x2 and pos.y >= r.y1 and pos.y <= r.y2
end

function A.inArena(L, pos)
	return inRect(L.arena, L.z, pos)
end

function A.inSlot(L, pos)
	return inRect(L.arena, L.z, pos) or inRect(L.gallery, L.z, pos)
end

-- every tile of the slot once: {x, y, z, wall = bool, gallery = bool}
function A.footprint(L)
	local list = {}
	local a, g = L.arena, L.gallery
	for x = a.x1, a.x2 do
		for y = a.y1, g.y2 do
			local inGallery = y > a.y2
			local wall = x == a.x1 or x == a.x2 or y == a.y1 or y == a.y2 or y == g.y2
			list[#list + 1] = {x = x, y = y, z = L.z, wall = wall, gallery = inGallery}
		end
	end
	return list
end

-- first free slot that is not marked bad, or nil
function A.allocSlot(cfg, busy, bad)
	for slot = 0, cfg.grid.slots - 1 do
		if not busy[slot] and not (bad and bad[slot]) then
			return slot
		end
	end
	return nil
end

-- ------------------------------------------------------------------ fight
-- May a hit of attacker `a` land on target `t`? a / t = the players' match entries ({team, defeated}) or nil.
-- a == nil: the damage has no player behind it (a field, a monster). self = the attacker is the target itself.
function A.canHit(phase, a, t, self)
	if not t then
		return true -- the target is not in a match
	end
	if t.defeated or phase ~= "fight" then
		return false
	end
	if self or not a then
		return true
	end
	return not a.defeated and a.team ~= t.team
end

-- The death catch. health = current health, primary / secondary = damage values (positive).
-- Returns the clamped values and true when the hit would have killed: the player keeps 1 health and is defeated.
function A.catchDamage(health, primary, secondary)
	primary, secondary = math.max(0, primary or 0), math.max(0, secondary or 0)
	if primary + secondary < health then
		return primary, secondary, false
	end
	local keep = math.max(0, health - 1)
	local p = math.min(primary, keep)
	local s = math.min(secondary, keep - p)
	return p, s, true
end

-- sides = {{{health, maxHealth, defeated}, ...}, {...}} -> share of health left per side (defeated count as 0)
function A.healthShare(side)
	local hp, max = 0, 0
	for _, p in ipairs(side) do
		max = max + math.max(1, p.maxHealth or 1)
		if not p.defeated then
			hp = hp + math.max(0, p.health or 0)
		end
	end
	return max > 0 and hp / max or 0
end

-- timeout: the side with the higher share wins; within `epsilon` it is a draw (0)
function A.timeoutWinner(sides, epsilon)
	local a, b = A.healthShare(sides[1]), A.healthShare(sides[2])
	epsilon = epsilon or 0.001
	if math.abs(a - b) <= epsilon then
		return 0, a, b
	end
	return a > b and 1 or 2, a, b
end

local function standing(side)
	local n = 0
	for _, p in ipairs(side) do
		if not p.defeated then
			n = n + 1
		end
	end
	return n
end

-- winner while the fight runs: 1 / 2 when only one side has players standing, 0 when neither has, nil otherwise
function A.decided(sides)
	local a, b = standing(sides[1]), standing(sides[2])
	if a > 0 and b > 0 then
		return nil
	end
	if a > 0 then
		return 1
	elseif b > 0 then
		return 2
	end
	return 0
end

-- ------------------------------------------------------------------ rewards
-- day = today's key, st = {firstWinDay, winsDay, winsCount} read from the storages.
-- Returns the items (list of {id, count}), whether it is the first win of the day, and the new storage values.
function A.reward(cfg, day, st)
	local r = cfg.reward
	local count = (st.winsDay == day) and (st.winsCount or 0) or 0
	local items = {}
	local first = st.firstWinDay ~= day
	if count < r.maxRewardedWinsPerDay then
		for _, it in ipairs(r.win) do
			items[#items + 1] = {id = it.id, count = it.count}
		end
	end
	if first then
		for _, it in ipairs(r.firstWin) do
			items[#items + 1] = {id = it.id, count = it.count}
		end
	end
	return items, first, {firstWinDay = day, winsDay = day, winsCount = count + 1}
end

-- "1v1" / "2v2" / "3v3" from a talk parameter ("1", "1v1", "2V2", "duo", "trio"...), or nil
function A.parseMode(cfg, text)
	text = tostring(text or ""):lower():gsub("%s", "")
	if cfg.modes[text] then
		return text
	end
	if text == "1" or text == "solo" then
		return "1v1"
	elseif text == "2" or text == "duo" then
		return "2v2"
	elseif text == "3" or text == "trio" then
		return "3v3"
	end
	return nil
end

return A
