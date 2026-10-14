-- Boss mechanics: the pure part (no engine calls), shared by boss_mechanics.lua, uber_core.lua (the Ascended Omens,
-- the Cinderheart and the guild boss use its shapes and timing) and tests/boss_mechanics_test.lua.
--   grid        the tiles a fight can use (a list of walkable tiles), the boss's footprint (size 1 or 4)
--   shapes      circle, cone, line, ring (donut), cross, puddles, follow, marks, half, lines, eye
--   timing      the warning time (1.5-3 s by difficulty) and the pulses of the danger mark until the hit
--   fairness    walking costs (ChaosSpeed: the player step rules of patch 0018), the safe tiles a player reaches in
--               time, the pockets cut into a telegraph (or into the union of overlapping ones) so one always exists
--   fight       the per-boss state machine: telegraph cadence, adds phases (immune / shield / empower / heal), soft
--               enrage, stacking debuffs, soak, channel + totem (interrupt), line of sight (pillars), warnings
--   balance     the downtime the mechanics add and the health factor that keeps the kill time
-- Every random number comes from the `rand(a, b)` argument (integer in [a, b]). Lua 5.1 / LuaJIT and Lua 5.3.

ChaosBossMechCore = ChaosBossMechCore or {}
local G = ChaosBossMechCore

local floor, abs, sqrt, min, max = math.floor, math.abs, math.sqrt, math.min, math.max

local function key(x, y)
	return x .. "," .. y
end
G.key = key

-- ===================================================================== grid
-- a grid from a list of walkable tiles {x, y, z}: set (key -> tile), list (the given order), rect, z
function G.grid(list)
	local g = {set = {}, list = {}, z = list[1] and list[1].z or 7}
	local x1, y1, x2, y2 = math.huge, math.huge, -math.huge, -math.huge
	for _, t in ipairs(list) do
		local k = key(t.x, t.y)
		if not g.set[k] then
			g.set[k] = t
			g.list[#g.list + 1] = t
			x1, y1, x2, y2 = min(x1, t.x), min(y1, t.y), max(x2, t.x), max(y2, t.y)
		end
	end
	g.rect = {x1 = x1, y1 = y1, x2 = x2, y2 = y2}
	return g
end

-- a square box of `radius` round `center`; walkable(x, y) -> bool decides each tile (nil: every tile)
function G.boxGrid(center, radius, walkable)
	local list = {}
	for y = center.y - radius, center.y + radius do
		for x = center.x - radius, center.x + radius do
			if not walkable or walkable(x, y) then
				list[#list + 1] = {x = x, y = y, z = center.z}
			end
		end
	end
	return G.grid(list)
end

-- a grid without the tiles of `blocked` (key -> true): pillars
function G.without(g, blocked)
	local list = {}
	for _, t in ipairs(g.list) do
		if not blocked[key(t.x, t.y)] then
			list[#list + 1] = t
		end
	end
	return G.grid(list)
end

-- the tiles a creature of `size` covers: a big creature stands on its tile and reaches up and left
function G.footprint(pos, size)
	size = math.max(1, size or 1)
	return {x1 = pos.x - (size - 1), y1 = pos.y - (size - 1), x2 = pos.x, y2 = pos.y}
end

-- the distance from a tile to a footprint (0 inside)
function G.distBody(x, y, b)
	local dx = x < b.x1 and b.x1 - x or (x > b.x2 and x - b.x2 or 0)
	local dy = y < b.y1 and b.y1 - y or (y > b.y2 and y - b.y2 or 0)
	return sqrt(dx * dx + dy * dy)
end

local function dist(a, b)
	local dx, dy = a.x - b.x, a.y - b.y
	return sqrt(dx * dx + dy * dy)
end
G.dist = dist

-- the main direction from a to b: dx, dy in {-1, 0, 1}, one of them 0 (south when equal)
function G.direction(a, b)
	local dx, dy = b.x - a.x, b.y - a.y
	if dx == 0 and dy == 0 then
		return 0, 1
	end
	if abs(dx) > abs(dy) then
		return dx > 0 and 1 or -1, 0
	end
	return 0, dy > 0 and 1 or -1
end

local function collect(list, want)
	local out = {}
	for _, t in ipairs(list) do
		if want(t.x, t.y) then
			out[#out + 1] = t
		end
	end
	return out
end

-- along / side of a tile from a footprint in a main direction (dx, dy): along = steps out of the body's edge,
-- side = steps off the body's span (size 1: the stock cone of uber_core.lua)
local function alongSide(x, y, b, dx, dy)
	local along, side
	if dx ~= 0 then
		along = dx > 0 and x - b.x2 or b.x1 - x
		side = y < b.y1 and b.y1 - y or (y > b.y2 and y - b.y2 or 0)
	else
		along = dy > 0 and y - b.y2 or b.y1 - y
		side = x < b.x1 and b.x1 - x or (x > b.x2 and x - b.x2 or 0)
	end
	return along, side
end

-- ===================================================================== shapes
G.SHAPES = {"circle", "cone", "line", "ring", "cross", "puddles", "follow", "marks", "half", "lines", "eye"}

-- a shape widened for a big boss: +1 sqm per two tiles of size past the first (size 4: +1, on top of its body)
local GROW = {radius = 1, length = 1, spread = 1, outer = 1, inner = 1, halfWidth = 1}
function G.scaleShape(spec, size)
	local bonus = floor((math.max(1, size or 1) - 1) / 2)
	local out = {}
	for k, v in pairs(spec) do
		out[k] = v
	end
	if bonus > 0 and not spec.fixedSize then
		for k in pairs(GROW) do
			if type(out[k]) == "number" and not (k == "radius" and (spec.kind == "marks" or spec.kind == "puddles")) then
				out[k] = out[k] + bonus
			end
		end
	end
	return out
end

-- a telegraph shape. spec = {kind, ...sizes}; ctx = {list | grid, boss = pos, size, target = pos, players = {pos},
-- rand}. Returns the tiles (of the list only) and info ({side, safe, lines, centers, at}).
-- The kinds circle / cone / ring / marks / cross / half / lines / eye are uber_core.lua's (the same tiles for a size 1
-- boss, the same calls of rand).
function G.shape(spec, ctx)
	local list = ctx.list or (ctx.grid and ctx.grid.list) or {}
	local rect = ctx.rect or (ctx.grid and ctx.grid.rect) or G.grid(list).rect
	local b0 = ctx.boss or {x = floor((rect.x1 + rect.x2) / 2), y = floor((rect.y1 + rect.y2) / 2)}
	local body = G.footprint(b0, ctx.size)
	local rand = ctx.rand or function(a) return a end
	local P = spec
	local name = spec.kind
	local info = {}
	if name == "cone" then
		local dx, dy = G.direction(b0, ctx.target or {x = b0.x, y = b0.y + 1})
		return collect(list, function(x, y)
			local along, side = alongSide(x, y, body, dx, dy)
			if along < 1 or along > P.length then
				return false
			end
			return side <= math.max(1, floor(P.spread * along / P.length + 0.5))
		end), info
	elseif name == "line" then
		-- a beam from the boss's body to the wall, towards the target, halfWidth tiles to each side
		local dx, dy = G.direction(b0, ctx.target or {x = b0.x, y = b0.y + 1})
		local length = P.length or 99
		return collect(list, function(x, y)
			local along, side = alongSide(x, y, body, dx, dy)
			return along >= 1 and along <= length and side <= (P.halfWidth or 0)
		end), info
	elseif name == "ring" then
		return collect(list, function(x, y)
			local d = G.distBody(x, y, body)
			return d >= P.inner and d <= P.outer
		end), info
	elseif name == "circle" then
		if P.at == "target" and ctx.target then
			info.at = ctx.target
			return collect(list, function(x, y)
				return dist({x = x, y = y}, ctx.target) <= P.radius
			end), info
		end
		return collect(list, function(x, y)
			return G.distBody(x, y, body) <= P.radius
		end), info
	elseif name == "follow" then
		-- a circle on the target: the engine draws it again on every pulse until lockMs before the hit
		local t = ctx.target or b0
		info.at = {x = t.x, y = t.y, z = t.z}
		return collect(list, function(x, y)
			return dist({x = x, y = y}, t) <= P.radius
		end), info
	elseif name == "marks" then
		local players = ctx.players or {}
		return collect(list, function(x, y)
			for _, p in ipairs(players) do
				if dist({x = x, y = y}, p) <= P.radius then
					return true
				end
			end
			return false
		end), info
	elseif name == "puddles" then
		-- onPlayers puddles under players (spread out), the rest at random tiles of the list
		local centers = {}
		local players = ctx.players or {}
		local n = (P.count or 3) + floor((P.perPlayer or 0) * #players)
		if P.maxCount then
			n = math.min(n, P.maxCount)
		end
		for i = 1, math.min(P.onPlayers or 0, #players) do
			centers[#centers + 1] = players[i]
		end
		while #centers < n and #list > 0 do
			centers[#centers + 1] = list[rand(1, #list)]
		end
		info.centers = centers
		return collect(list, function(x, y)
			for _, c in ipairs(centers) do
				if dist({x = x, y = y}, c) <= (P.radius or 1) then
					return true
				end
			end
			return false
		end), info
	elseif name == "cross" then
		local hw = P.halfWidth or 1
		return collect(list, function(x, y)
			local ox = x < body.x1 and body.x1 - x or (x > body.x2 and x - body.x2 or 0)
			local oy = y < body.y1 and body.y1 - y or (y > body.y2 and y - body.y2 or 0)
			return ox <= hw or oy <= hw
		end), info
	elseif name == "half" then
		local sides = {"n", "e", "s", "w"}
		info.side = sides[rand(1, 4)]
		return collect(list, function(x, y)
			if info.side == "n" then
				return y < body.y1
			elseif info.side == "s" then
				return y > body.y2
			elseif info.side == "e" then
				return x > body.x2
			end
			return x < body.x1
		end), info
	elseif name == "lines" then
		local rows, cols = {}, {}
		info.lines = {}
		for _ = 1, P.count or 3 do
			if rand(1, 2) == 1 then
				local y = rand(rect.y1, rect.y2)
				rows[y] = true
				info.lines[#info.lines + 1] = "row " .. y
			else
				local x = rand(rect.x1, rect.x2)
				cols[x] = true
				info.lines[#info.lines + 1] = "col " .. x
			end
		end
		return collect(list, function(x, y)
			return rows[y] or cols[x]
		end), info
	elseif name == "eye" then
		local m = (P.safe or 2) + 1
		local safe = {x = rand(rect.x1 + m, rect.x2 - m), y = rand(rect.y1 + m, rect.y2 - m), z = ctx.z or (list[1] and list[1].z)}
		info.safe = safe
		return collect(list, function(x, y)
			return dist({x = x, y = y}, safe) > P.safe
		end), info
	end
	return {}, info
end

-- the set (key -> true) of a tile list
function G.tileSet(list)
	local s = {}
	for _, t in ipairs(list) do
		s[key(t.x, t.y)] = true
	end
	return s
end

-- how to show a telegraph's tiles: the 3x3 warning pictures go only on tiles whose 8 neighbours are marked too
-- (every second row and column), every marked tile they do not cover gets a one-tile effect: a picture never spills
-- onto a safe tile. Returns {big = tiles, small = tiles}.
function G.markPlan(tiles)
	local set = G.tileSet(tiles)
	local big, covered, small = {}, {}, {}
	for _, t in ipairs(tiles) do
		if t.x % 2 == 0 and t.y % 2 == 0 then
			local inside = true
			for ox = -1, 1 do
				for oy = -1, 1 do
					if not set[key(t.x + ox, t.y + oy)] then
						inside = false
					end
				end
			end
			if inside then
				big[#big + 1] = t
				for ox = -1, 1 do
					for oy = -1, 1 do
						covered[key(t.x + ox, t.y + oy)] = true
					end
				end
			end
		end
	end
	for _, t in ipairs(tiles) do
		if not covered[key(t.x, t.y)] then
			small[#small + 1] = t
		end
	end
	return {big = big, small = small}
end

-- ===================================================================== timing
G.MIN_WARN, G.MAX_WARN = 1500, 3000

-- the warning time of a telegraph: spec.warnMs when set, else 3000 ms at difficulty 0 down to 1500 ms at 1 (the
-- default difficulty 0-0.33 gives 2.5-3 s); never below 1500 or above 3000. enraged adds `fair.enrageDifficulty`.
function G.warnMs(spec, difficulty, fair, enraged)
	fair = fair or {}
	local lo, hi = fair.minWarnMs or G.MIN_WARN, fair.maxWarnMs or G.MAX_WARN
	lo = math.max(G.MIN_WARN, lo)
	local d = (difficulty or 0) + (enraged and (fair.enrageDifficulty or 0.3) or 0)
	d = math.max(0, math.min(1, d))
	local ms = spec and spec.warnMs or floor(hi - (hi - lo) * d + 0.5)
	ms = floor(ms / 100 + 0.5) * 100
	return math.max(lo, math.min(hi, ms))
end

-- the pulses of the danger mark: {at = ms after the start, kind = "zone" | "fill"}, every pulseMs from 0 while
-- before the hit; the pulses inside the last fillMs show the filling mark (the hit is near)
function G.pulses(warnMs, pulseMs, fillMs)
	pulseMs = math.max(200, pulseMs or 600)
	fillMs = fillMs or 900
	local out = {}
	local t = 0
	while t < warnMs do
		out[#out + 1] = {at = t, kind = (warnMs - t <= fillMs and t > 0) and "fill" or "zone"}
		t = t + pulseMs
	end
	if #out >= 2 and out[#out].kind ~= "fill" then
		out[#out].kind = "fill"
	end
	return out
end

-- ===================================================================== fairness
-- the step costs (ms) of the reference player: straight and diagonal on normal ground. fair = {refLevel, vocationBase}
-- -> ChaosSpeed (data/lib/chaos_speed.lua, patch 0018) when loaded, else its default formula inline
function G.stepCosts(fair)
	fair = fair or {}
	local S = ChaosSpeed
	local level = fair.refLevel or 300
	local voc = fair.vocationBase or 220
	if S and S.baseSpeed and S.stepDuration then
		local cfg = S.defaults
		local speed = S.clamp(S.baseSpeed(voc, level, cfg), cfg)
		return S.stepDuration(speed, nil, {}), S.stepDuration(speed, nil, {diagonal = true})
	end
	-- the same rules without the library (the patch's defaults)
	local levels = math.max(0, level - 1)
	local below = math.min(levels, 299)
	local speed = voc + 50 + floor((below * 25 + (levels - below) * 10) / 10)
	speed = math.max(120, math.min(2600, speed))
	local step = floor(857.36 * math.log(floor(speed / 2) + 261.29) - 4795.01 + 0.5)
	local ms = math.ceil(floor(1000 * 150 / step) / 10) * 10
	return ms, floor(ms * 7 / 5)
end

-- the walking budget of a warning: warnMs - reactionMs (the time to see it and start), at least 0
function G.budget(warnMs, fair)
	return math.max(0, warnMs - ((fair and fair.reactionMs) or 500))
end

-- every tile of grid g reachable from `from` within budget ms (Dijkstra; straight / diagonal costs): key -> ms
function G.reach(g, from, budget, straight, diag)
	local best = {}
	local k0 = key(from.x, from.y)
	if not g.set[k0] then
		return best
	end
	best[k0] = 0
	local open = {{x = from.x, y = from.y, c = 0}}
	while #open > 0 do
		-- the cheapest open node (the lists stay small: a budget of a few seconds)
		local bi = 1
		for i = 2, #open do
			if open[i].c < open[bi].c then
				bi = i
			end
		end
		local n = table.remove(open, bi)
		if n.c <= (best[key(n.x, n.y)] or math.huge) then
			for ox = -1, 1 do
				for oy = -1, 1 do
					if ox ~= 0 or oy ~= 0 then
						local nx, ny = n.x + ox, n.y + oy
						local nk = key(nx, ny)
						if g.set[nk] then
							local c = n.c + ((ox ~= 0 and oy ~= 0) and diag or straight)
							if c <= budget and c < (best[nk] or math.huge) then
								best[nk] = c
								open[#open + 1] = {x = nx, y = ny, c = c}
							end
						end
					end
				end
			end
		end
	end
	return best
end

-- the nearest safe tile (not in `marked`) a player at `from` reaches in budget ms: tile, ms; nil when none
function G.safeSpot(g, marked, from, budget, straight, diag)
	local r = G.reach(g, from, budget, straight, diag)
	local bestK, bestC
	for k, c in pairs(r) do
		if not marked[k] and (not bestC or c < bestC or (c == bestC and k < bestK)) then
			bestK, bestC = k, c
		end
	end
	if not bestK then
		return nil
	end
	return g.set[bestK], bestC
end

-- the players (positions) of a telegraph who have no safe tile in reach: list of positions
function G.trapped(g, marked, players, budget, straight, diag)
	local out = {}
	for _, p in ipairs(players or {}) do
		if g.set[key(p.x, p.y)] and not G.safeSpot(g, marked, p, budget, straight, diag) then
			out[#out + 1] = p
		end
	end
	return out
end

-- makes a telegraph fair: for every player without a safe tile in reach (given `others`, the tiles of telegraphs that
-- are still pending: key -> true), a pocket (a tile and its four neighbours) is cut out of `tiles` at a reachable tile
-- the others leave safe, as far from the boss as the walk allows within 60% of the budget (else within all of it). Returns the tiles left,
-- the cut tiles (list) and the pocket centres.
function G.makeFair(g, tiles, players, budget, straight, diag, boss, others)
	others = others or {}
	local set = G.tileSet(tiles)
	local cut, pockets = {}, {}
	for _, p in ipairs(players or {}) do
		local union = {}
		for k in pairs(set) do
			union[k] = true
		end
		for k in pairs(others) do
			union[k] = true
		end
		if g.set[key(p.x, p.y)] and not G.safeSpot(g, union, p, budget, straight, diag) then
			local r = G.reach(g, p, budget, straight, diag)
			local pick, pickScore
			-- comfortably in reach first (60% of the budget), else anywhere in reach
			for _, share in ipairs({0.6, 1.0}) do
				for k, c in pairs(r) do
					if not others[k] and c <= budget * share then
						local t = g.set[k]
						local score = boss and dist(t, boss) or -c
						if not pickScore or score > pickScore or (score == pickScore and k < pick) then
							pick, pickScore = k, score
						end
					end
				end
				if pick then
					break
				end
			end
			if not pick then
				-- nothing the others leave safe near: the player's own tile
				pick = key(p.x, p.y)
			end
			local t = g.set[pick]
			pockets[#pockets + 1] = t
			for _, o in ipairs({{0, 0}, {1, 0}, {-1, 0}, {0, 1}, {0, -1}}) do
				local k = key(t.x + o[1], t.y + o[2])
				if set[k] then
					set[k] = nil
					cut[#cut + 1] = g.set[k]
				end
			end
		end
	end
	local left = {}
	for _, t in ipairs(tiles) do
		if set[key(t.x, t.y)] then
			left[#left + 1] = t
		end
	end
	return left, cut, pockets
end

-- a whole check: every player has a safe tile in reach of the union of `tiles` and `others`; ok, trapped list
function G.isFair(g, tiles, players, budget, straight, diag, others)
	local union = G.tileSet(tiles)
	for k in pairs(others or {}) do
		union[k] = true
	end
	local t = G.trapped(g, union, players, budget, straight, diag)
	return #t == 0, t
end

-- line of sight: the tiles on the line from a to b (Bresenham, both ends excluded)
function G.lineTiles(a, b)
	local out = {}
	local x0, y0, x1, y1 = a.x, a.y, b.x, b.y
	local dx, dy = abs(x1 - x0), -abs(y1 - y0)
	local sx, sy = x0 < x1 and 1 or -1, y0 < y1 and 1 or -1
	local err = dx + dy
	while true do
		if x0 == x1 and y0 == y1 then
			break
		end
		local e2 = 2 * err
		if e2 >= dy then
			err = err + dy
			x0 = x0 + sx
		end
		if e2 <= dx then
			err = err + dx
			y0 = y0 + sy
		end
		if not (x0 == x1 and y0 == y1) then
			out[#out + 1] = {x = x0, y = y0}
		end
	end
	return out
end

-- a tile is hidden from the boss when a pillar (key -> true) lies on the line between them
function G.hidden(boss, tile, pillars)
	for _, t in ipairs(G.lineTiles(boss, tile)) do
		if pillars[key(t.x, t.y)] then
			return true
		end
	end
	return false
end

-- the tiles a room-wide blast hits: every grid tile in view of the boss (not a pillar, not hidden)
function G.blastTiles(g, boss, pillars)
	return collect(g.list, function(x, y)
		return not pillars[key(x, y)] and not G.hidden(boss, {x = x, y = y}, pillars)
	end)
end

-- the pillar spots of a line-of-sight mechanic: offsets round the boss's spawn ({dx, dy} list), kept when on the grid
function G.pillarSpots(g, center, offsets)
	local out = {}
	for _, o in ipairs(offsets or {}) do
		local k = key(center.x + o[1], center.y + o[2])
		if g.set[k] then
			out[#out + 1] = g.set[k]
		end
	end
	return out
end

-- ===================================================================== soak, debuffs, enrage
-- the share of max health each player in a soak circle takes: total split by the players inside (at least
-- spec.min of them count, so a lone soaker takes total / min); nobody inside: everyone takes spec.missShare
function G.soakShare(spec, inside)
	if (inside or 0) <= 0 then
		return 0, spec.missShare or 0.5
	end
	return spec.total / math.max(inside, spec.min or 1), 0
end

-- the stacks of a debuff after a new application at `now` (ms): stacks fall off one per decayMs since the last
function G.stackAdd(entry, spec, now)
	entry = entry or {stacks = 0, at = now}
	G.stackDecay(entry, spec, now)
	entry.stacks = math.min(spec.max or 10, entry.stacks + 1)
	entry.at = now
	return entry
end

function G.stackDecay(entry, spec, now)
	if not entry then
		return 0
	end
	local d = spec.decayMs or 6000
	local lost = floor(math.max(0, now - (entry.at or now)) / d)
	if lost > 0 then
		entry.stacks = math.max(0, entry.stacks - lost)
		entry.at = (entry.at or now) + lost * d
	end
	return entry.stacks
end

-- the multiplier on the boss's damage to a player with `stacks`
function G.stackMult(spec, stacks)
	return 1 + (spec and spec.perStack or 0) * (stacks or 0)
end

-- the soft enrage: +perMin per minute past `at` seconds, at most maxMult in all (1 before)
function G.softEnrage(spec, elapsedSec)
	if not spec or not elapsedSec or elapsedSec < spec.at then
		return 1
	end
	local m = 1 + (spec.perMin or 0.1) * (elapsedSec - spec.at) / 60
	return math.min(spec.maxMult or 2, m)
end

-- ===================================================================== the fight (state machine)
-- st = G.newFight(profile, opts): opts = {now (ms), difficulty (0..1), solo, players, size}
function G.newFight(profile, opts)
	opts = opts or {}
	local now = opts.now or 0
	local st = {p = profile, t0 = now, difficulty = opts.difficulty or profile.difficulty or 0.2, solo = opts.solo,
		size = opts.size or profile.size or 1, players = opts.players or 1, phasesDone = {}, adds = {}, stacks = {},
		pending = {}, mechIdx = 0, enraged = false, tier = opts.tier}
	local first = profile.firstMs or 6000
	st.nextTelegraph = now + first
	for i, m in ipairs(profile.timed or {}) do
		m._i = i
	end
	st.nextTimed = {}
	for i, m in ipairs(profile.timed or {}) do
		st.nextTimed[i] = now + (m.firstMs or (first + 8000 * i))
	end
	return st
end

-- the mechanics this fight has (by tier: a mechanic with minTier needs a tier at least that)
local function allowed(st, m)
	return not (m.minTier and (st.tier or 0) < m.minTier) and not (m.groupOnly and st.solo)
end

-- the telegraph cadence: ms between two telegraphs (faster with the difficulty, faster again when an adds phase is
-- not running; at least the warning plus gapMs, so two telegraphs never land at once)
function G.telegraphEvery(st, warn)
	local p = st.p
	local every = (p.every or 9000) * (1 - 0.25 * (st.difficulty or 0))
	return math.max(warn + (p.gapMs or 1500), floor(every))
end

-- one step of the fight at `now` (ms); hp = health fraction 0..1; liveAdds = adds of the open phase still alive.
-- Returns a list of actions for the engine:
--   {kind = "telegraph", spec, warnMs}               draw spec now (the engine asks G.planTelegraph)
--   {kind = "adds", phase = i, spec}                 spawn the phase's adds (immune / shield / empower / heal)
--   {kind = "warn", text}                            the orange warning
--   {kind = "channel" | "soak" | "los", spec, warnMs} a timed mechanic starts (cast bar of warnMs)
--   {kind = "softEnrage"}                            the soft enrage starts
function G.update(st, now, hp, liveAdds)
	local p = st.p
	local out = {}
	-- adds phases at health thresholds, each once and in order
	for i, ph in ipairs(p.adds or {}) do
		if not st.phasesDone[i] and hp <= ph.at and allowed(st, ph) then
			st.phasesDone[i] = true
			st.addsPhase = i
			st.addsSince = now
			out[#out + 1] = {kind = "adds", phase = i, spec = ph}
			if ph.text then
				out[#out + 1] = {kind = "warn", text = ph.text}
			end
		end
	end
	if st.addsPhase and (liveAdds or 0) <= 0 and st.addsSince and now > st.addsSince + 1000 then
		local ph = p.adds[st.addsPhase]
		if ph and ph.doneText then
			out[#out + 1] = {kind = "warn", text = ph.doneText}
		end
		st.addsPhase = nil
	end
	-- soft enrage
	local elapsed = (now - st.t0) / 1000
	if p.softEnrage and not st.enraged and elapsed >= p.softEnrage.at then
		st.enraged = true
		out[#out + 1] = {kind = "softEnrage"}
		if p.softEnrage.text then
			out[#out + 1] = {kind = "warn", text = p.softEnrage.text}
		end
	end
	-- a busy boss (a channel, a soak or a blast running) draws no telegraph meanwhile
	local busy = st.busyUntil and now < st.busyUntil
	-- timed mechanics (channel, soak, line of sight), each on its own cadence
	for i, m in ipairs(p.timed or {}) do
		if allowed(st, m) and now >= st.nextTimed[i] and not busy and hp <= (m.below or 1) then
			local warn = G.warnMs(m, st.difficulty, p.fair, st.enraged)
			if m.kind == "channel" then
				warn = math.max(warn, m.channelMs or 8000)
			elseif m.kind == "los" then
				warn = math.max(warn, m.hideMs or 3000)
			end
			st.nextTimed[i] = now + (m.every or 40000)
			st.busyUntil = now + warn + 500
			busy = true
			out[#out + 1] = {kind = m.kind, spec = m, warnMs = warn}
			if m.text then
				out[#out + 1] = {kind = "warn", text = m.text}
			end
		end
	end
	-- telegraphs: one at a time on the cadence, a random one of the list (by tier)
	if not busy and now >= st.nextTelegraph and p.telegraphs and #p.telegraphs > 0 then
		local pool = {}
		for _, t in ipairs(p.telegraphs) do
			if allowed(st, t) and hp <= (t.below or 1) then
				pool[#pool + 1] = t
			end
		end
		if #pool > 0 then
			st.mechIdx = st.mechIdx % #pool + 1
			local spec = pool[st.rand and st.rand(1, #pool) or st.mechIdx]
			local warn = G.warnMs(spec, st.difficulty, p.fair, st.enraged)
			if spec.kind == "follow" then
				warn = warn + (spec.followMs or 1500)
			end
			st.nextTelegraph = now + G.telegraphEvery(st, warn)
			out[#out + 1] = {kind = "telegraph", spec = spec, warnMs = warn}
		end
	end
	return out
end

-- the pending telegraphs' tiles at `now` (key -> true), dropping the ones that hit already
-- and the earliest of their hits (nil when none)
function G.pendingTiles(st, now)
	local u = {}
	local keep = {}
	local first
	for _, t in ipairs(st.pending) do
		if t.hitAt > now then
			keep[#keep + 1] = t
			first = math.min(first or t.hitAt, t.hitAt)
			for k in pairs(t.set) do
				u[k] = true
			end
		end
	end
	st.pending = keep
	return u, first
end

-- plans one telegraph: the shape (widened for the boss's size), made fair against the players and the telegraphs
-- still pending, the pulses and the hit time. ctx as G.shape plus grid; fair = the profile's fair settings.
-- Returns {tiles, set, plan (G.markPlan), pulses, hitAt, warnMs, share, info, cut, pockets}
function G.planTelegraph(st, spec, ctx, now, warnMs)
	local p = st.p
	local fair = p.fair or {}
	local s = G.scaleShape(spec, ctx.size or st.size)
	local tiles, info = G.shape(s, ctx)
	local straight, diag = G.stepCosts(fair)
	local lockMs = warnMs
	if spec.kind == "follow" then
		-- the circle follows for followMs; the last warning (the part that counts for dodging) is warnMs - followMs
		lockMs = warnMs - (spec.followMs or 1500)
	end
	local budget = G.budget(lockMs, fair)
	local others, first = G.pendingTiles(st, now)
	if first then
		-- overlapping: a tile safe from all of them must be reached before the earliest pending hit
		budget = math.min(budget, G.budget(first - now, fair))
	end
	local cut, pockets
	tiles, cut, pockets = G.makeFair(ctx.grid, tiles, ctx.players, budget, straight, diag, ctx.boss, others)
	local tel = {tiles = tiles, set = G.tileSet(tiles), plan = G.markPlan(tiles), pulses = G.pulses(warnMs, fair.pulseMs, fair.fillMs),
		hitAt = now + warnMs, warnMs = warnMs, lockAt = now + (warnMs - lockMs), share = spec.share or 0.4, info = info,
		cut = cut, pockets = pockets, spec = spec}
	st.pending[#st.pending + 1] = tel
	return tel
end

-- a follow telegraph drawn again at its target's new spot (before its lock): the new tiles, made fair the same way
function G.refollow(st, tel, ctx, now)
	local p = st.p
	local fair = p.fair or {}
	local s = G.scaleShape(tel.spec, ctx.size or st.size)
	local tiles = G.shape(s, ctx)
	local straight, diag = G.stepCosts(fair)
	local budget = G.budget(math.max(0, tel.hitAt - math.max(now, tel.lockAt)), fair)
	local others = {}
	for _, o in ipairs(st.pending) do
		if o ~= tel and o.hitAt > now then
			for k in pairs(o.set) do
				others[k] = true
			end
		end
	end
	tiles = G.makeFair(ctx.grid, tiles, ctx.players, budget, straight, diag, ctx.boss, others)
	tel.tiles, tel.set, tel.plan = tiles, G.tileSet(tiles), G.markPlan(tiles)
	return tel
end

-- adds: the damage the boss takes x this (0 = immune while the phase's adds live; shield: 1 - reduce)
function G.damageTakenMult(st, liveAdds)
	local ph = st.addsPhase and st.p.adds[st.addsPhase]
	if not ph or (liveAdds or 0) <= 0 then
		return 1
	end
	if ph.mode == "immune" then
		return 0
	elseif ph.mode == "shield" then
		return 1 - (ph.reduce or 0.5)
	end
	return 1
end

-- the boss's damage x this: the soft enrage x the empower of living adds
function G.damageDealtMult(st, now, liveAdds)
	local m = G.softEnrage(st.p.softEnrage, (now - st.t0) / 1000)
	local ph = st.addsPhase and st.p.adds[st.addsPhase]
	if ph and ph.mode == "empower" and (liveAdds or 0) > 0 then
		m = m * (1 + (ph.perAdd or 0.1) * liveAdds)
	end
	return m
end

-- the heal of a heal phase per step: perAdd x max health per living add
function G.addsHeal(st, liveAdds, maxHealth)
	local ph = st.addsPhase and st.p.adds[st.addsPhase]
	if not ph or ph.mode ~= "heal" or (liveAdds or 0) <= 0 then
		return 0
	end
	return floor((ph.perAdd or 0.005) * liveAdds * (maxHealth or 0))
end

-- the adds of a phase: count = base + perPlayer x players (at least 1), health = spec.health x (1 + perExtra x
-- (players - 1)); solo content keeps the solo numbers
function G.addsCount(spec, players)
	return math.max(1, floor((spec.count or 1) + (spec.perPlayer or 0) * math.max(0, (players or 1) - 1)))
end

function G.addsHealth(spec, players)
	return floor((spec.health or 10000) * (1 + (spec.healthPerExtra or 0) * math.max(0, (players or 1) - 1)))
end

-- a totem's health for a channel: spec.totemHealth x (1 + perExtra x (players - 1))
function G.totemHealth(spec, players)
	return floor((spec.totemHealth or 20000) * (1 + (spec.totemPerExtra or 0.5) * math.max(0, (players or 1) - 1)))
end

-- the warning line of a mechanic for a boss name: spec.text with %s = the boss name
function G.warnText(text, bossName)
	if not text then
		return nil
	end
	return (text:gsub("%%s", bossName or "The boss"))
end

-- the cast bar payload for the client (game_monsterbar, opcode 125 action "mech")
function G.castPayload(cid, bossName, label, ms, kind)
	return {cid = cid, boss = bossName, label = label, ms = math.max(0, floor(ms or 0)), kind = kind or "telegraph"}
end

-- ===================================================================== balance
-- the downtime the mechanics add, as a share of the fight spent not hitting the boss, and the fixed seconds (adds,
-- totems). ref = {dps, players}: a telegraph costs its moveMs (default the budget's walk, 1.2 s) per cadence; a
-- channel costs its totem's health / dps; an adds phase its adds' total health / dps (immune) or their share (else);
-- line of sight hideMs per cadence; soak a second per cadence. Returns share, fixedSeconds
function G.downtime(profile, ref)
	local share, fixed = 0, 0
	local dps = ref.dps
	local players = ref.players or 1
	if profile.telegraphs and #profile.telegraphs > 0 then
		local warn = G.warnMs(nil, profile.difficulty or 0.2, profile.fair)
		local every = (profile.every or 9000) * (1 - 0.25 * (profile.difficulty or 0.2))
		every = math.max(warn + (profile.gapMs or 1500), every)
		share = share + (profile.moveMs or 1200) / every
	end
	for _, m in ipairs(profile.timed or {}) do
		if not (m.minTier and (ref.tier or 0) < m.minTier) and not (m.groupOnly and players == 1) then
			local cost
			if m.kind == "channel" then
				cost = G.totemHealth(m, players) / dps + (m.walkSec or 2)
			elseif m.kind == "los" then
				cost = (m.hideMs or 3000) / 1000
			else
				cost = (m.soakSec or 1.5)
			end
			share = share + cost / ((m.every or 40000) / 1000)
		end
	end
	for _, ph in ipairs(profile.adds or {}) do
		if not (ph.minTier and (ref.tier or 0) < ph.minTier) then
			local hp = G.addsHealth(ph, players) * G.addsCount(ph, players)
			if ph.mode == "immune" then
				fixed = fixed + hp / dps
			else
				fixed = fixed + hp / dps * (ph.cost or 0.5)
			end
		end
	end
	return share, fixed
end

-- the kill time model of a profile against ref = {health, heal, dps, uptime, players, tier}: base = health / (dps x uptime)
-- (the old time); with = the time with the mechanics before the health change; hpMult = the boss health factor that
-- brings `with` back to base (at least minHpMult); final = the time with both
function G.balance(profile, ref)
	local up = ref.uptime or 0.75
	-- the boss's own heal comes off the damage (heal per second / uptime: it heals while nobody hits it too)
	local r = {}
	for k, v in pairs(ref) do
		r[k] = v
	end
	r.dps = ref.dps - (ref.heal or 0) / up
	ref = r
	local share, fixed = G.downtime(profile, ref)
	local base = ref.health / (ref.dps * up)
	local up2 = math.max(0.3, up - share)
	local with = ref.health / (ref.dps * up2) + fixed
	local hpMult = 1
	if profile.compensate ~= false then
		hpMult = math.max(profile.minHpMult or 0.6, math.min(1, (base - fixed) * ref.dps * up2 / ref.health))
	end
	-- the weakest damage the content must still allow (ref.weakDps, e.g. the weakest class): the same rule at that
	-- damage; the lower factor wins, so a weak build keeps its old time too (a strong one gets a little faster)
	if ref.weakDps and profile.compensate ~= false then
		local w = {}
		for k, v in pairs(ref) do
			w[k] = v
		end
		w.dps = ref.weakDps - (ref.heal or 0) / up
		local wShare, wFixed = G.downtime(profile, w)
		local wUp = math.max(0.3, up - wShare)
		local wBase = ref.health / (w.dps * up)
		local wMult = (wBase - wFixed) * w.dps * wUp / ref.health
		hpMult = math.max(profile.minHpMult or 0.6, math.min(hpMult, wMult))
	end
	local final = ref.health * hpMult / (ref.dps * up2) + fixed
	return {base = base, with = with, hpMult = hpMult, final = final, downShare = share, fixed = fixed}
end

function G.clockText(secs)
	secs = math.max(0, floor((secs or 0) + 0.5))
	return string.format("%d:%02d", floor(secs / 60), secs % 60)
end

return G
