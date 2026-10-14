-- Where a startup NPC stands next to a temple: the pure search (no engine calls), shared by npc_place.lua and
-- server/tests/npc_place_test.lua. server/README.md "Item prices" (Loot Buyer), "Gambling" (the Gambler), the Ascendant
-- Oracle, Archivist Maelis, the Material Brokers and the faction NPCs all place through it.
-- Live test 2026-10-14: no Loot Buyer at Nightwrack ("no free tile") and the startup log listed Scorchveil too (the
-- fixed offsets were all walls or taken); at the capital the Loot Buyer stood next to the Gambler, so "hi" and
-- "trade" opened both their windows. Now:
--   * the configured offsets are tried first (the town keeps its look), then every tile a player can walk to from the
--     temple (a flood fill, closed doors count as walkable), nearest walking distance first, up to `radius`;
--   * a spot keeps `spacing` tiles (Chebyshev) from every other NPC: more than the NPC talk radius (3), so a player
--     never stands in reach of both (npc lib chaos_npc_focus.lua answers only the nearest NPC on top of that);
--   * not the temple tile itself and not next to it (`minFromTemple`), not in a corridor (a tile with fewer than
--     `minOpen` walkable straight neighbours: an NPC there would block the way) unless nothing else is left;
--   * the order is fixed (offsets, then distance, then row, then column), so a restart gives the same spot.
--
--   ChaosNpcPlaceCore.pick(spec) -> dx, dy (relative to the temple) | nil
--   spec = {walkable(dx, dy) -> bool       a player can stand there (ground, nothing blocking, no teleport / stairs)
--           door(dx, dy) -> bool           a closed door (walkable for the flood fill, never a spot)
--           free(dx, dy) -> bool           nobody stands there now (default: true)
--           offsets = {{dx, dy}, ...}, others = {{dx, dy}, ...} (the other NPCs), radius, spacing, minFromTemple,
--           minOpen}
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.
ChaosNpcPlaceCore = ChaosNpcPlaceCore or {}
local K = ChaosNpcPlaceCore

K.DEFAULTS = {radius = 14, spacing = 4, minFromTemple = 2, minOpen = 3}
K.TALK_RADIUS = 3 -- the base NPC library's talkRadius

local abs, max = math.abs, math.max

local function cheb(ax, ay, bx, by)
	return max(abs(ax - bx), abs(ay - by))
end
K.cheb = cheb

local function key(x, y)
	return x .. ":" .. y
end

-- walking distance from the temple (0, 0) to every reachable tile within radius: {["dx:dy"] = steps}, list in BFS order
function K.reach(spec, radius)
	local dist, order = {[key(0, 0)] = 0}, {{0, 0}}
	local i = 1
	while order[i] do
		local x, y = order[i][1], order[i][2]
		local d = dist[key(x, y)]
		i = i + 1
		for _, s in ipairs({{0, -1}, {-1, 0}, {1, 0}, {0, 1}}) do
			local nx, ny = x + s[1], y + s[2]
			local k = key(nx, ny)
			if not dist[k] and cheb(nx, ny, 0, 0) <= radius
					and (spec.walkable(nx, ny) or (spec.door and spec.door(nx, ny))) then
				dist[k] = d + 1
				order[#order + 1] = {nx, ny}
			end
		end
	end
	return dist, order
end

local function openSides(spec, x, y)
	local n = 0
	for _, s in ipairs({{0, -1}, {-1, 0}, {1, 0}, {0, 1}}) do
		if spec.walkable(x + s[1], y + s[2]) then
			n = n + 1
		end
	end
	return n
end

function K.pick(spec)
	local radius = spec.radius or K.DEFAULTS.radius
	local spacing = spec.spacing or K.DEFAULTS.spacing
	local minFrom = spec.minFromTemple or K.DEFAULTS.minFromTemple
	local minOpen = spec.minOpen or K.DEFAULTS.minOpen
	local dist, order = K.reach(spec, radius)

	-- the candidates: the configured offsets first, then every reachable tile by walking distance, row, column
	local list, seen = {}, {}
	for _, o in ipairs(spec.offsets or {}) do
		local k = key(o[1], o[2])
		if not seen[k] then
			seen[k] = true
			list[#list + 1] = {o[1], o[2]}
		end
	end
	local rest = {}
	for _, t in ipairs(order) do
		if not seen[key(t[1], t[2])] then
			rest[#rest + 1] = t
		end
	end
	table.sort(rest, function(a, b)
		local da, db = dist[key(a[1], a[2])], dist[key(b[1], b[2])]
		if da ~= db then
			return da < db
		end
		if a[2] ~= b[2] then
			return a[2] < b[2]
		end
		return a[1] < b[1]
	end)
	for _, t in ipairs(rest) do
		list[#list + 1] = t
	end

	local function ok(x, y, needOpen)
		if not dist[key(x, y)] or not spec.walkable(x, y) or (spec.door and spec.door(x, y)) then
			return false
		end
		if spec.free and not spec.free(x, y) then
			return false
		end
		if cheb(x, y, 0, 0) < minFrom then
			return false
		end
		for _, o in ipairs(spec.others or {}) do
			if cheb(x, y, o[1], o[2]) < spacing then
				return false
			end
		end
		return not needOpen or openSides(spec, x, y) >= minOpen
	end
	for _, needOpen in ipairs({true, false}) do
		for _, c in ipairs(list) do
			if ok(c[1], c[2], needOpen) then
				return c[1], c[2]
			end
		end
	end
	return nil
end
