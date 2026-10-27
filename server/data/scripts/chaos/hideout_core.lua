-- Hideouts: pure logic (ChaosHideoutCore), no engine calls. Used by hideout.lua, hideout_store.lua and
-- server/tests/hideout_test.lua. Lua 5.1 / LuaJIT and Lua 5.3 compatible.
--
--   catalogue  K.theme(cfg, key), K.deco(cfg, key), K.rotCount(d), K.parts(d, rot, side), K.icon(d)
--   checks     K.validate(cfg, achievementsData, factionsConfig, shopConfig) -> list of problems
--   geometry   K.slotOrigin(cfg, slot), K.toWorld(cfg, slot, gx, gy), K.fromWorld(cfg, pos) -> slot, gx, gy,
--              K.footprint(cfg, slot), K.wallSide(cfg, gx, gy), K.reserved(cfg), K.fixtureTiles(cfg)
--   placing    K.placeProblem(cfg, themeKey, placed, cand, ignoreId) -> nil | text; K.nextId(placed);
--              K.reachProblem(cfg, placed) (every fixture keeps a path from the arrival tile)
--   unlocks    K.sourceMet(cfg, src, facts), K.owned(cfg, entry, facts), K.lockText(cfg, entry, facts, names)
--   access     K.mayVisit(perm, rel) -> true | false, reason; K.enterProblem(f)
--   leaving    K.exitDestination(cfg, f) -> pos, why: the stored spot, a usable neighbour, the home temple, Cinderhold's
--   social     K.likeProblem(t), K.countsVisit(lastVisit, now), K.showcase(rows, by, limit)
--   pool       K.poolNew(cfg), K.poolAcquire(pool, owner, usable), K.poolRelease(pool, slot), K.poolSlotOf(pool, owner)
--   view       K.catalogueView(cfg, facts, placed, names), K.themesView(cfg, facts, names, current)

ChaosHideoutCore = ChaosHideoutCore or {}
local K = ChaosHideoutCore

K.LAYERS = {object = true, floor = true, wall = true}
K.SOURCES = {default = true, achievement = true, stat = true, faction = true, descent = true, journey = true, store = true}

local function key(x, y)
	return x .. "," .. y
end
K.key = key

-- ---------------------------------------------------------------- catalogue
function K.theme(cfg, k)
	for _, t in ipairs(cfg.themes) do
		if t.key == k then
			return t
		end
	end
	return nil
end

function K.defaultTheme(cfg)
	for _, t in ipairs(cfg.themes) do
		if t.source and t.source.type == "default" then
			return t
		end
	end
	return cfg.themes[1]
end

function K.deco(cfg, k)
	if not cfg._decoIndex then
		local idx = {}
		for _, d in ipairs(cfg.decorations) do
			idx[d.key] = d
		end
		cfg._decoIndex = idx
	end
	return cfg._decoIndex[k]
end

function K.rotCount(d)
	if d.layer == "wall" then
		return 1
	end
	if d.rots then
		return #d.rots
	end
	return #(d.ids or {})
end

-- rotation index into 1..rotCount (anything else -> 1)
function K.rot(d, r)
	r = math.floor(tonumber(r) or 1)
	if r < 1 or r > K.rotCount(d) then
		return 1
	end
	return r
end

-- {{dx, dy, id}, ...} of a decoration at rotation `rot`; a wall decoration takes the id of its wall `side`
function K.parts(d, rot, side)
	if d.layer == "wall" then
		return {{0, 0, d.wall and d.wall[side or "n"] or nil}}
	end
	rot = K.rot(d, rot)
	if d.rots then
		return d.rots[rot]
	end
	return {{0, 0, d.ids[rot]}}
end

function K.icon(d)
	if d.icon then
		return d.icon
	end
	if d.layer == "wall" then
		return d.wall and d.wall.n
	end
	local p = K.parts(d, 1)
	return p and p[1] and p[1][3]
end

function K.maxOf(cfg, d)
	return d.max or cfg.defaultMax or 4
end

-- ---------------------------------------------------------------- geometry
-- top-left wall corner of a slot (inner (1, 1) is origin + 1, + 1)
function K.slotOrigin(cfg, slot)
	local g = cfg.grid
	local i = slot - 1
	return {x = g.origin.x + (i % g.cols) * g.spacing, y = g.origin.y + math.floor(i / g.cols) * g.spacing, z = g.origin.z}
end

function K.toWorld(cfg, slot, gx, gy)
	local o = K.slotOrigin(cfg, slot)
	return {x = o.x + gx, y = o.y + gy, z = o.z}
end

-- slot, gx, gy of a world position inside a slot's footprint (walls included: gx 0..w + 1); nil when outside
function K.fromWorld(cfg, pos)
	local g = cfg.grid
	if not pos or pos.z ~= g.origin.z then
		return nil
	end
	local dx, dy = pos.x - g.origin.x, pos.y - g.origin.y
	if dx < 0 or dy < 0 then
		return nil
	end
	local col, row = math.floor(dx / g.spacing), math.floor(dy / g.spacing)
	if col >= g.cols then
		return nil
	end
	local slot = row * g.cols + col + 1
	if slot > g.maxSlots then
		return nil
	end
	local gx, gy = dx - col * g.spacing, dy - row * g.spacing
	if gx > cfg.inner.w + 1 or gy > cfg.inner.h + 1 then
		return nil
	end
	return slot, gx, gy
end

-- every tile of a slot: {x, y, z, gx, gy, wall = true for the wall ring}
function K.footprint(cfg, slot)
	local o = K.slotOrigin(cfg, slot)
	local W, H = cfg.inner.w, cfg.inner.h
	local out = {}
	for gy = 0, H + 1 do
		for gx = 0, W + 1 do
			out[#out + 1] = {x = o.x + gx, y = o.y + gy, z = o.z, gx = gx, gy = gy,
				wall = gx == 0 or gy == 0 or gx == W + 1 or gy == H + 1}
		end
	end
	return out
end

-- which wall a wall decoration at (gx, gy) hangs on: "n" (the north wall, gy 0) or "w" (the west wall, gx 0)
function K.wallSide(cfg, gx, gy)
	if gy == 0 and gx >= 1 and gx <= cfg.inner.w then
		return "n"
	end
	if gx == 0 and gy >= 1 and gy <= cfg.inner.h then
		return "w"
	end
	return nil
end

-- the wall piece of a wall tile: "corner" (north-west), "h" (north / south, the south-west end), "v" (west / east,
-- the north-east end), "pole" (south-east); nil for a floor tile. back = true on the north and west walls.
function K.wallPiece(cfg, gx, gy)
	local W, H = cfg.inner.w, cfg.inner.h
	if gx > 0 and gy > 0 and gx <= W and gy <= H then
		return nil
	end
	local back = gx == 0 or gy == 0
	if gx == 0 and gy == 0 then
		return "corner", true
	elseif gx == W + 1 and gy == H + 1 then
		return "pole", false
	elseif gx == W + 1 and gy == 0 then
		return "v", true
	elseif gx == 0 and gy == H + 1 then
		return "h", true
	elseif gy == 0 or gy == H + 1 then
		return "h", back
	end
	return "v", back
end

-- fixture tiles: {{name, x, y, solid}}
function K.fixtureTiles(cfg)
	local f = cfg.fixtures
	local out = {
		{name = "arrival", x = f.arrival[1], y = f.arrival[2], solid = false},
		{name = "exit", x = f.exit[1], y = f.exit[2], solid = false},
		{name = "depot", x = f.depot[1], y = f.depot[2], solid = true},
		{name = "stash", x = f.stash[1], y = f.stash[2], solid = true}
	}
	for i, p in ipairs(f.dummies or {}) do
		out[#out + 1] = {name = "dummy" .. i, x = p[1], y = p[2], solid = true}
	end
	for i, p in ipairs(f.lights or {}) do
		out[#out + 1] = {name = "light" .. i, x = p[1], y = p[2], solid = true, decor = true}
	end
	if f.waystone then
		-- the device blocks its tile; its portal pads (base tier_maps.lua) go on the four diagonal tiles: kept free of
		-- decorations, not checked for the path (a pad that finds no free tile is simply not made)
		out[#out + 1] = {name = "waystone", x = f.waystone[1], y = f.waystone[2], solid = true}
		local n = 0
		for _, d in ipairs({{-1, -1}, {1, -1}, {-1, 1}, {1, 1}}) do
			n = n + 1
			out[#out + 1] = {name = "waystonepad" .. n, x = f.waystone[1] + d[1], y = f.waystone[2] + d[2], solid = false,
				decor = true}
		end
	end
	return out
end

function K.reserved(cfg)
	local set = {}
	for _, t in ipairs(K.fixtureTiles(cfg)) do
		set[key(t.x, t.y)] = t
	end
	return set
end

-- ---------------------------------------------------------------- placing
-- occupancy of the placed list: {object = {xy -> id}, floor = {...}, wall = {...}, solid = {xy -> true}}, counts
function K.occupancy(cfg, placed, ignoreId)
	local occ = {object = {}, floor = {}, wall = {}, solid = {}}
	local total, per = 0, {}
	for _, p in ipairs(placed or {}) do
		if p.id ~= ignoreId then
			local d = K.deco(cfg, p.key)
			if d then
				total = total + 1
				per[p.key] = (per[p.key] or 0) + 1
				local side = d.layer == "wall" and K.wallSide(cfg, p.x, p.y) or nil
				for _, part in ipairs(K.parts(d, p.rot, side) or {}) do
					local k = key(p.x + part[1], p.y + part[2])
					occ[d.layer][k] = p.id or true
					if d.block and d.layer == "object" then
						occ.solid[k] = true
					end
				end
			end
		end
	end
	return occ, total, per
end

-- tiles walkable from the arrival tile (8 directions: Tibia walks diagonally); solid = {xy -> true}
local function reachSet(cfg, solid)
	local W, H = cfg.inner.w, cfg.inner.h
	local fixtures = K.reserved(cfg)
	local blocked = {}
	for k in pairs(solid) do
		blocked[k] = true
	end
	for k, t in pairs(fixtures) do
		if t.solid then
			blocked[k] = true
		end
	end
	local a = cfg.fixtures.arrival
	local seen, queue, head = {[key(a[1], a[2])] = true}, {{a[1], a[2]}}, 1
	while queue[head] do
		local x, y = queue[head][1], queue[head][2]
		head = head + 1
		for dy = -1, 1 do
			for dx = -1, 1 do
				local nx, ny = x + dx, y + dy
				local k = key(nx, ny)
				if (dx ~= 0 or dy ~= 0) and nx >= 1 and ny >= 1 and nx <= W and ny <= H and not seen[k] and not blocked[k] then
					seen[k] = true
					queue[#queue + 1] = {nx, ny}
				end
			end
		end
	end
	return seen
end

-- nil when every fixture (exit, depot, stash, dummies, waystone) can still be reached from the arrival tile; else the text
function K.reachProblem(cfg, placed, extraSolid)
	local occ = K.occupancy(cfg, placed)
	for k in pairs(extraSolid or {}) do
		occ.solid[k] = true
	end
	local seen = reachSet(cfg, occ.solid)
	for _, t in ipairs(K.fixtureTiles(cfg)) do
		if not t.decor and t.name ~= "arrival" then
			local ok = false
			if not t.solid then
				ok = seen[key(t.x, t.y)] == true
			else
				for dy = -1, 1 do
					for dx = -1, 1 do
						if seen[key(t.x + dx, t.y + dy)] then
							ok = true
						end
					end
				end
			end
			if not ok then
				return "That would wall off the " .. (t.name:match("^dummy") and "training dummies" or t.name) .. "."
			end
		end
	end
	return nil
end

-- why `cand` = {key, x, y, rot} cannot be placed (nil = it can). `placed` = the hideout's decorations
-- {{id, key, x, y, rot}}; ignoreId = the decoration being moved (it leaves its old place first).
function K.placeProblem(cfg, themeKey, placed, cand, ignoreId)
	local d = cand and K.deco(cfg, cand.key)
	if not d then
		return "Unknown decoration."
	end
	local theme = K.theme(cfg, themeKey) or K.defaultTheme(cfg)
	local x, y = math.floor(tonumber(cand.x) or -1), math.floor(tonumber(cand.y) or -1)
	local occ, total, per = K.occupancy(cfg, placed, ignoreId)
	if total >= theme.maxDecor then
		return string.format("%s holds at most %d decorations.", theme.name, theme.maxDecor)
	end
	if (per[d.key] or 0) >= K.maxOf(cfg, d) then
		return string.format("At most %d x %s per hideout.", K.maxOf(cfg, d), d.name)
	end
	local W, H = cfg.inner.w, cfg.inner.h
	if d.layer == "wall" then
		local side = K.wallSide(cfg, x, y)
		if not side then
			return "Wall decorations hang on the north or the west wall."
		end
		if occ.wall[key(x, y)] then
			return "Something already hangs there."
		end
		return nil
	end
	local reserved = K.reserved(cfg)
	local parts = K.parts(d, cand.rot)
	local newSolid = {}
	for _, part in ipairs(parts) do
		local px, py = x + part[1], y + part[2]
		local k = key(px, py)
		if px < 1 or py < 1 or px > W or py > H then
			return "Place it on the floor of the room."
		end
		if reserved[k] then
			return "That tile is kept free (" .. (reserved[k].name:match("^light") and "a light" or
				reserved[k].name:match("^dummy") and "a dummy" or
				reserved[k].name:match("^waystone") and "the waystone" or reserved[k].name) .. ")."
		end
		if occ[d.layer][k] then
			return d.layer == "floor" and "There is a rug there already." or "Something already stands there."
		end
		if d.layer == "object" and d.block then
			newSolid[k] = true
		end
	end
	if next(newSolid) then
		local others = {}
		for _, p in ipairs(placed or {}) do
			if p.id ~= ignoreId then
				others[#others + 1] = p
			end
		end
		local problem = K.reachProblem(cfg, others, newSolid)
		if problem then
			return problem
		end
	end
	return nil
end

-- the next free decoration id of a hideout (ids are per hideout, 1..)
function K.nextId(placed)
	local used, n = {}, 0
	for _, p in ipairs(placed or {}) do
		used[p.id] = true
	end
	repeat
		n = n + 1
	until not used[n]
	return n
end

-- ---------------------------------------------------------------- unlocks
local function rankIndex(cfg, rankKey)
	for i, r in ipairs(cfg.factionRanks) do
		if r == rankKey then
			return i
		end
	end
	return nil
end

-- facts: achievement(id) -> bool, stat(name) -> number, factionRank(faction) -> rank index (1 = hostile),
--        descent = {best = depth, clear = bool}, journey = chapters done (nil: no journey system), store = {key = true}
function K.sourceMet(cfg, src, facts)
	src = src or {type = "default"}
	facts = facts or {}
	local t = src.type
	if t == "default" then
		return true
	elseif t == "achievement" then
		return facts.achievement ~= nil and facts.achievement(src.id) == true
	elseif t == "stat" then
		return facts.stat ~= nil and (tonumber(facts.stat(src.stat)) or 0) >= (src.min or 1)
	elseif t == "faction" then
		local have = facts.factionRank and facts.factionRank(src.faction)
		local need = rankIndex(cfg, src.rank)
		return have ~= nil and need ~= nil and have >= need
	elseif t == "descent" then
		local dsc = facts.descent or {}
		if src.clear then
			return dsc.clear == true
		end
		return (tonumber(dsc.best) or 0) >= (src.depth or 1)
	elseif t == "journey" then
		return facts.journey ~= nil and facts.journey >= (src.chapter or 1)
	end
	return false -- store: only by owning it
end

-- entry = a decoration or a theme; keyOf = the unlock key ("theme:<key>" for themes)
function K.unlockKey(entry, isTheme)
	return (isTheme and "theme:" or "") .. entry.key
end

-- owned when: the source is met now, or it was met before (facts.earned), or bought (facts.store)
function K.owned(cfg, entry, facts, isTheme)
	local src = entry.source or {type = "default"}
	local k = K.unlockKey(entry, isTheme)
	facts = facts or {}
	if facts.earned and facts.earned[k] then
		return true
	end
	if src.type == "store" then
		return facts.store ~= nil and facts.store[k] == true
	end
	return K.sourceMet(cfg, src, facts)
end

-- how to unlock it, in words. names = {achievement = {id -> name}, faction = {key -> name}, rank = {key -> name}}
function K.sourceText(cfg, src, names)
	names = names or {}
	-- names.tr(key, ...) -> the text in the player's language (the engine file); English by default
	local tr = names.tr or function(key, ...)
		return select("#", ...) > 0 and string.format(key, ...) or key
	end
	local t = src and src.type or "default"
	if t == "default" then
		return tr("Every character")
	elseif t == "achievement" then
		return tr("Achievement: %s", (names.achievement or {})[src.id] or src.id)
	elseif t == "stat" then
		if src.group == "trophy" then
			return tr(src.label or "A trophy of your own kills")
		end
		return src.label and tr(src.label) or tr("Event: %s", tostring(src.stat))
	elseif t == "faction" then
		local f = (names.faction or {})[src.faction] or src.faction
		local r = (names.rank or {})[src.rank] or src.rank
		return string.format("%s: %s", f, r)
	elseif t == "descent" then
		if src.clear then
			return tr("Ember Descent: slay its boss")
		end
		return tr("Ember Descent: reach depth %d", src.depth or 1)
	elseif t == "journey" then
		return tr("Season journey: chapter %d", src.chapter or 1)
	elseif t == "store" then
		return tr("Store: %d Chaos Coins (cosmetic, giftable)", src.price or 0)
	end
	return tr("Unknown")
end

-- the filter group of a source (the window's "Source" filter)
function K.sourceGroup(src)
	local t = src and src.type or "default"
	if t == "stat" then
		return src.group == "trophy" and "trophy" or "event"
	end
	return t
end

-- ---------------------------------------------------------------- access
-- perm 0 private, 1 friends, 2 guild, 3 public. rel = {self, staff, vip, party, guild, realmMismatch, banned}
function K.mayVisit(perm, rel)
	rel = rel or {}
	if rel.self then
		return true
	end
	if rel.staff then
		return true
	end
	if rel.realmMismatch then
		return false, "Season and standard characters cannot visit each other while the season runs."
	end
	perm = tonumber(perm) or 1
	if perm >= 3 then
		return true
	end
	if perm >= 1 and (rel.vip or rel.party) then
		return true
	end
	if perm >= 2 and rel.guild then
		return true
	end
	if perm <= 0 then
		return false, "That hideout is private."
	end
	return false, perm == 1 and "Only the owner's friends and party may enter." or
		"Only the owner's friends, party and guild may enter."
end

-- why a character cannot go to a hideout now (nil = it can). f = facts of the engine
function K.enterProblem(f)
	f = f or {}
	if f.tutorial then
		return "Finish or skip the tutorial first."
	end
	if f.pzLocked or f.inFight then
		return "You cannot enter a hideout right after a fight."
	end
	if f.skull then
		return "You cannot enter a hideout with a skull."
	end
	if f.arena or f.worldBoss or f.siege or f.rift or f.dungeon or f.tower or f.instance then
		return "Leave this place through its own exit first."
	end
	if f.full then
		return "Every hideout room is in use. Try again in a minute."
	end
	return nil
end

-- where the exit (and a login inside, and "leave") sends a character. f = {
--   stored    {x, y, z} the spot the character entered from, or nil (none, or already used)
--   usable    function(pos) -> true when a character may stand there now: ground, walkable, no portal or stairs, not
--             in an instance area (the engine checks; never asked for a tile of the hideout grid)
--   home      the temple of the character's home town, or nil (no such town)
--   fallback  the temple of the main city (Cinderhold), or nil}
-- The stored spot when it is usable; else a usable neighbour of it (the spot was the entry portal itself, or someone's
-- portal stands there now); else the home temple, else the main city's. Never a tile of the hideout grid: a portal
-- back into a hideout is how a character got stuck in a loop. Returns pos, why (stored | near | home | fallback | nil)
function K.exitDestination(cfg, f)
	local function inGrid(p)
		return p ~= nil and K.fromWorld(cfg, p) ~= nil
	end
	local function valid(p)
		return type(p) == "table" and tonumber(p.x) and tonumber(p.y) and tonumber(p.z) and p.x > 0 and p.y > 0
			and p.z >= 0 and p.z <= 15
	end
	local s = f.stored
	if valid(s) and not inGrid(s) then
		if f.usable(s) then
			return {x = s.x, y = s.y, z = s.z}, "stored"
		end
		for _, d in ipairs({{0, 1}, {1, 0}, {-1, 0}, {0, -1}, {1, 1}, {-1, 1}, {1, -1}, {-1, -1}}) do
			local n = {x = s.x + d[1], y = s.y + d[2], z = s.z}
			if not inGrid(n) and f.usable(n) then
				return n, "near"
			end
		end
	end
	if valid(f.home) and not inGrid(f.home) then
		return {x = f.home.x, y = f.home.y, z = f.home.z}, "home"
	end
	if valid(f.fallback) and not inGrid(f.fallback) then
		return {x = f.fallback.x, y = f.fallback.y, z = f.fallback.z}, "fallback"
	end
	return nil, nil
end

-- ---------------------------------------------------------------- likes and visits
-- t = {self (own account), inside (the liker stands in that hideout), already, today (likes given today), perDay}
function K.likeProblem(t)
	if t.self then
		return "You cannot like your own account's hideouts."
	end
	if not t.inside then
		return "Visit the hideout to like it."
	end
	if t.already then
		return "You already like this hideout."
	end
	if (t.today or 0) >= (t.perDay or 10) then
		return "You have given every like you may give today."
	end
	return nil
end

-- a visit counts once per visitor and calendar day (dayKey = YYYYMMDD)
function K.countsVisit(lastDay, today)
	return lastDay == nil or tonumber(lastDay) ~= tonumber(today)
end

-- rows = {{owner, name, likes, visits, ...}}; by = "likes" | "visits"; ties: the other counter, then the name
function K.showcase(rows, by, limit)
	local list = {}
	for _, r in ipairs(rows or {}) do
		list[#list + 1] = r
	end
	local other = by == "likes" and "visits" or "likes"
	table.sort(list, function(a, b)
		if (a[by] or 0) ~= (b[by] or 0) then
			return (a[by] or 0) > (b[by] or 0)
		end
		if (a[other] or 0) ~= (b[other] or 0) then
			return (a[other] or 0) > (b[other] or 0)
		end
		return tostring(a.name) < tostring(b.name)
	end)
	local out = {}
	for i = 1, math.min(#list, limit or #list) do
		out[i] = list[i]
	end
	return out
end

-- ---------------------------------------------------------------- slot pool
-- slots are reused: an owner keeps its slot while the room is up; a released slot goes back to the free list and the
-- lowest free usable slot is taken first. usable(slot) -> false skips a slot (a map tile is in its footprint).
function K.poolNew(cfg)
	return {max = cfg.grid.maxSlots, byOwner = {}, bySlot = {}, bad = {}}
end

function K.poolSlotOf(pool, owner)
	return pool.byOwner[owner]
end

function K.poolOwnerOf(pool, slot)
	return pool.bySlot[slot]
end

function K.poolAcquire(pool, owner, usable)
	local s = pool.byOwner[owner]
	if s then
		return s, false
	end
	for slot = 1, pool.max do
		if not pool.bySlot[slot] and not pool.bad[slot] then
			if not usable or usable(slot) then
				pool.bySlot[slot] = owner
				pool.byOwner[owner] = slot
				return slot, true
			end
			pool.bad[slot] = true
		end
	end
	return nil
end

function K.poolRelease(pool, slot)
	local owner = pool.bySlot[slot]
	if owner ~= nil then
		pool.byOwner[owner] = nil
	end
	pool.bySlot[slot] = nil
	return owner
end

function K.poolUsed(pool)
	local n = 0
	for _ in pairs(pool.bySlot) do
		n = n + 1
	end
	return n
end

-- ---------------------------------------------------------------- views for the client
-- names: {achievement, faction, rank} (K.sourceText); clientId(serverId) -> client id (identity when missing)
function K.catalogueView(cfg, facts, placed, names, clientId)
	clientId = clientId or function(id)
		return id
	end
	local _, _, per = K.occupancy(cfg, placed)
	local rows = {}
	for _, d in ipairs(cfg.decorations) do
		local owned = K.owned(cfg, d, facts)
		local rots = {}
		if d.layer == "wall" then
			rots[1] = {{0, 0, clientId(d.wall.n)}}
			rots.w = {{0, 0, clientId(d.wall.w)}}
		else
			for r = 1, K.rotCount(d) do
				local list = {}
				for i, p in ipairs(K.parts(d, r)) do
					list[i] = {p[1], p[2], clientId(p[3])}
				end
				rots[r] = list
			end
		end
		rows[#rows + 1] = {key = d.key, name = d.name, cat = d.cat, layer = d.layer, block = d.block == true,
			item = clientId(K.icon(d)), rots = rots, wallW = rots.w, max = K.maxOf(cfg, d), placed = per[d.key] or 0,
			owned = owned, source = K.sourceGroup(d.source),
			how = d.trophy and (names and names.tr and names.tr("Trophy: slay %s", d.trophy.boss) or ("Trophy: slay " .. d.trophy.boss)) or K.sourceText(cfg, d.source, names),
			price = d.source and d.source.type == "store" and d.source.price or nil, trophy = d.trophy ~= nil}
		rows[#rows].rots.w = nil
	end
	return rows
end

function K.themesView(cfg, facts, names, current, clientId)
	clientId = clientId or function(id)
		return id
	end
	local out = {}
	for _, t in ipairs(cfg.themes) do
		out[#out + 1] = {key = t.key, name = t.name, desc = t.desc, maxDecor = t.maxDecor, item = clientId(t.ground),
			owned = K.owned(cfg, t, facts, true), how = K.sourceText(cfg, t.source, names), selected = t.key == current}
	end
	return out
end

-- the room's fixed layout for the client: size, reserved tiles, the arrival tile
function K.layoutView(cfg)
	local res = {}
	for _, t in ipairs(K.fixtureTiles(cfg)) do
		res[#res + 1] = {t.x, t.y, t.name}
	end
	return {w = cfg.inner.w, h = cfg.inner.h, reserved = res, arrival = cfg.fixtures.arrival}
end

-- ---------------------------------------------------------------- validation
function K.validate(cfg, achievementsData, factionsConfig, shopConfig)
	local problems = {}
	local function bad(text)
		problems[#problems + 1] = text
	end
	local achievements = {}
	for _, a in ipairs((achievementsData or {}).list or {}) do
		achievements[a.id] = true
	end
	local factions, ranks = {}, {}
	for _, f in ipairs((factionsConfig or {}).factions or {}) do
		factions[f.key] = true
	end
	for i, r in ipairs((factionsConfig or {}).ranks or {}) do
		ranks[r.key] = i
	end
	for i, r in ipairs(cfg.factionRanks) do
		if factionsConfig and ranks[r] ~= i then
			bad("factionRanks: " .. r .. " is not rank " .. i .. " of factions_config.lua")
		end
	end
	local function checkSource(what, src)
		if type(src) ~= "table" or not K.SOURCES[src.type] then
			bad(what .. ": unknown source")
			return
		end
		if src.type == "achievement" and achievementsData and not achievements[src.id] then
			bad(what .. ": unknown achievement " .. tostring(src.id))
		elseif src.type == "faction" then
			if factionsConfig and not factions[src.faction] then
				bad(what .. ": unknown faction " .. tostring(src.faction))
			end
			if not rankIndex(cfg, src.rank) then
				bad(what .. ": unknown rank " .. tostring(src.rank))
			end
		elseif src.type == "stat" and (type(src.stat) ~= "string" or src.stat == "") then
			bad(what .. ": stat source without a stat")
		elseif src.type == "store" and (type(src.price) ~= "number" or src.price <= 0) then
			bad(what .. ": store source without a price")
		end
	end
	local cats = {}
	for _, c in ipairs(cfg.categories) do
		cats[c.key] = true
	end
	local seen, keys = {}, {}
	for _, t in ipairs(cfg.themes) do
		if keys["theme:" .. t.key] then
			bad("theme " .. t.key .. " twice")
		end
		keys["theme:" .. t.key] = true
		local w = t.walls or {}
		if type(t.ground) ~= "number" or type(t.light) ~= "number" or type(w.v) ~= "number" or type(w.h) ~= "number" or
				type(w.pole) ~= "number" or type(w.corner) ~= "number" then
			bad("theme " .. t.key .. ": ground, walls = {v, h, pole, corner} and light ids")
		end
		if type(t.maxDecor) ~= "number" or t.maxDecor < 1 then
			bad("theme " .. t.key .. ": maxDecor")
		end
		checkSource("theme " .. t.key, t.source)
		if t.source and t.source.type == "store" then
			bad("theme " .. t.key .. ": themes are earned, not sold")
		end
	end
	local reserved = K.reserved(cfg)
	for _, f in ipairs(K.fixtureTiles(cfg)) do
		if f.x < 1 or f.y < 1 or f.x > cfg.inner.w or f.y > cfg.inner.h then
			bad("fixture " .. f.name .. " outside the room")
		end
	end
	if K.reachProblem(cfg, {}) then
		bad("the empty room does not reach every fixture")
	end
	local at = {}
	for _, f in ipairs(K.fixtureTiles(cfg)) do
		local k = key(f.x, f.y)
		if at[k] then
			bad("fixtures " .. at[k] .. " and " .. f.name .. " on one tile")
		end
		at[k] = f.name
	end
	local _ = reserved
	for _, d in ipairs(cfg.decorations) do
		local what = "decoration " .. tostring(d.key)
		if seen[d.key] then
			bad(what .. " twice")
		end
		seen[d.key] = true
		if not K.LAYERS[d.layer] then
			bad(what .. ": layer")
		end
		if not cats[d.cat] then
			bad(what .. ": category " .. tostring(d.cat))
		end
		if type(d.name) ~= "string" or d.name == "" then
			bad(what .. ": name")
		end
		if d.layer == "wall" then
			if type(d.wall) ~= "table" or type(d.wall.n) ~= "number" or type(d.wall.w) ~= "number" then
				bad(what .. ": wall = {n, w}")
			end
			if d.block then
				bad(what .. ": a wall decoration cannot block")
			end
		elseif K.rotCount(d) < 1 then
			bad(what .. ": no ids")
		else
			for r = 1, K.rotCount(d) do
				local parts = K.parts(d, r)
				if type(parts) ~= "table" or #parts == 0 then
					bad(what .. ": rotation " .. r .. " has no parts")
				end
				for _, p in ipairs(parts or {}) do
					if type(p[3]) ~= "number" or p[1] < 0 or p[2] < 0 then
						bad(what .. ": rotation " .. r .. " part")
					end
				end
			end
		end
		if d.layer == "floor" and d.block then
			bad(what .. ": a rug cannot block")
		end
		-- cosmetic only: no field that could carry power
		for _, f in ipairs({"buff", "stat", "bonus", "skill", "damage", "heal", "exp", "loot", "speed", "attr"}) do
			if d[f] ~= nil then
				bad(what .. ": field " .. f .. " (decorations are cosmetic only)")
			end
		end
		if d.trophy and (type(d.trophy.stat) ~= "string" or type(d.trophy.boss) ~= "string") then
			bad(what .. ": trophy = {stat, boss}")
		end
		checkSource(what, d.source)
	end
	-- the store category sells exactly the store decorations, at their price, as giftable cosmetic unlocks
	if shopConfig then
		local sold = {}
		for _, cat in ipairs(shopConfig.categories or {}) do
			for _, o in ipairs(cat.offers or {}) do
				if o.kind == "unlock" and type(o.unlock) == "string" and o.unlock:sub(1, 8) == "hideout_" then
					sold[o.unlock:sub(9)] = o
				end
			end
		end
		for _, d in ipairs(cfg.decorations) do
			local o = sold[d.key]
			if d.source and d.source.type == "store" then
				if not o then
					bad(d.key .. ": store decoration without its store offer")
				elseif o.cost ~= d.source.price or o.name ~= d.name then
					bad(d.key .. ": store offer price or name differs")
				end
			elseif o then
				bad(d.key .. ": sold in the store but its source is " .. tostring(d.source and d.source.type))
			end
			sold[d.key] = nil
		end
		for k in pairs(sold) do
			bad("store offer hideout_" .. k .. " has no decoration")
		end
	end
	return problems
end

return K
