-- Spawn tiles: where a script may put a monster it places itself (not a map spawn). Pure rules over the engine's Tile API,
-- tested against a mocked map in tests/spawn_tile_test.lua.
--
-- Why: Game.createMonster(name, pos, extended, force) puts the monster on `pos` whenever the tile has a ground, because
-- Map::placeCreature asks the first tile with FLAG_IGNOREBLOCKITEM (and force skips the check). So a computed position
-- (a random offset around a chest, the border of an area, a breach) put land monsters on swimmable water and on
-- deep water (a blocking ground). A land monster never leaves it. Every script that picks a tile itself asks here.
--
--   ChaosSpawnTile.isWater(tile)             -> true: a water ground (the tile is a trash holder, or its ground's item type
--                                               has a fluid source: sea, swimmable water, puddles)
--   ChaosSpawnTile.ok(pos[, opts])           -> true | false, reason
--   ChaosSpawnTile.find(center[, opts])      -> {x, y, z} | nil   the centre if it fits, else a bounded number of random
--                                               tiles around it (opts.radius, opts.tries); nil: skip the spawn
--   ChaosSpawnTile.reachMap(from[, opts])    -> {["x:y"] = steps}, count   the tiles a walker reaches from `from` on its floor
--                                               (O517): breadth first, 8 directions, over the same tile rules, at most
--                                               opts.maxPath steps (default 12), inside a box of opts.box tiles
--                                               (default maxPath) around `from`: at most (2 * box + 1)^2 tiles looked at
-- opts: reachFrom = pos (a tile that fits must also be walk-connected to pos, within maxPath steps; `from` itself is
-- the seed and need not fit: a chest tile is blocked by the chest; opts.reach caches the map across calls with the same
-- opts table, so a search over a whole square runs the walk once), maxPath, box, walk = function(pos) -> true (injected
-- tile query for the walk, default: S.ok with occupied, and protection / house / water as in opts),
-- protection = true (a protection zone is fine), house = true, water = true (a water monster), occupied = true (a
-- creature on the tile is fine), rand = function(a, b) -> integer (default math.random), radius (default 2),
-- tries (default 12), minRadius (default 0: the least distance, in tiles, from the centre).
--
-- Assumed engine API (TFS 1.4.2): Tile(pos), Tile:getGround / hasFlag / hasProperty / getHouse / getCreatureCount,
-- Item:getType, ItemType:getFluidSource, the TILESTATE_* and CONST_PROP_* constants.

ChaosSpawnTile = ChaosSpawnTile or {}
local S = ChaosSpawnTile

local function flag(name)
	return rawget(_G, name) or 0
end

local function has(tile, name)
	local f = flag(name)
	return f ~= 0 and tile:hasFlag(f) == true
end

local function prop(tile, name)
	local p = rawget(_G, name)
	return p ~= nil and tile:hasProperty(p) == true
end

function S.isWater(tile)
	if has(tile, "TILESTATE_TRASHHOLDER") then
		return true
	end
	local ground = tile:getGround()
	if ground and type(ground) ~= "number" and ground.getType then
		local ok, t = pcall(ground.getType, ground)
		if ok and t and t.getFluidSource then
			local ok2, source = pcall(t.getFluidSource, t)
			return ok2 and type(source) == "number" and source ~= 0
		end
	end
	return false
end

local function key(pos)
	return pos.x .. ":" .. pos.y
end
S.key = key

local DIRS = {{0, -1}, {1, 0}, {0, 1}, {-1, 0}, {1, -1}, {1, 1}, {-1, 1}, {-1, -1}}

function S.reachMap(from, opts)
	opts = opts or {}
	local maxPath = opts.maxPath or 12
	local box = opts.box or maxPath
	local walk = opts.walk
	if not walk then
		local wopts = {occupied = true, protection = opts.protection, house = opts.house, water = opts.water}
		walk = function(p) return S.ok(p, wopts) end
	end
	local seen = {[key(from)] = 0}
	local count = 1
	local queue, head = {{x = from.x, y = from.y, z = from.z}}, 1
	while queue[head] do
		local cur = queue[head]
		head = head + 1
		local d = seen[key(cur)]
		if d < maxPath then
			for _, dir in ipairs(DIRS) do
				local nx, ny = cur.x + dir[1], cur.y + dir[2]
				local k = nx .. ":" .. ny
				if not seen[k] and math.abs(nx - from.x) <= box and math.abs(ny - from.y) <= box then
					local np = {x = nx, y = ny, z = from.z}
					if walk(np) then
						seen[k] = d + 1
						count = count + 1
						queue[#queue + 1] = np
					end
				end
			end
		end
	end
	return seen, count
end

function S.ok(pos, opts)
	opts = opts or {}
	local tile = pos and Tile(pos)
	if not tile or not tile:getGround() then
		return false, "no ground"
	end
	if not opts.protection and has(tile, "TILESTATE_PROTECTIONZONE") then
		return false, "protection zone"
	end
	if not opts.house and tile.getHouse and tile:getHouse() then
		return false, "house"
	end
	if has(tile, "TILESTATE_FLOORCHANGE") or has(tile, "TILESTATE_TELEPORT") then
		return false, "floor change / teleport"
	end
	if prop(tile, "CONST_PROP_BLOCKSOLID") or prop(tile, "CONST_PROP_IMMOVABLEBLOCKSOLID") or has(tile, "TILESTATE_BLOCKSOLID") then
		return false, "blocked"
	end
	if not opts.water and S.isWater(tile) then
		return false, "water"
	end
	if not opts.occupied and tile.getCreatureCount and tile:getCreatureCount() > 0 then
		return false, "occupied"
	end
	if opts.reachFrom then
		if pos.z ~= opts.reachFrom.z then
			return false, "unreachable"
		end
		opts.reach = opts.reach or S.reachMap(opts.reachFrom, opts)
		if opts.reach[key(pos)] == nil then
			return false, "unreachable"
		end
	end
	return true
end

function S.find(center, opts)
	opts = opts or {}
	if (opts.minRadius or 0) <= 0 and S.ok(center, opts) then
		return {x = center.x, y = center.y, z = center.z}
	end
	local rand = opts.rand or math.random
	local radius = math.max(1, opts.radius or 2)
	local least = opts.minRadius or 0
	for _ = 1, opts.tries or 12 do
		local dx, dy = rand(-radius, radius), rand(-radius, radius)
		if math.max(math.abs(dx), math.abs(dy)) >= least and (dx ~= 0 or dy ~= 0) then
			local pos = {x = center.x + dx, y = center.y + dy, z = center.z}
			if S.ok(pos, opts) then
				return pos
			end
		end
	end
	return nil
end

return S
