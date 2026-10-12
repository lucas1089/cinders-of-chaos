-- Pure logic of the map overlay marks (map_marks.lua; client game_mapoverlay). No engine calls here, so
-- server/tests/map_marks_test.lua can run it with plain Lua. Lua 5.1 / LuaJIT / Lua 5.3 compatible.
--
-- A mark is {k = kind, x, y, z, n = label (optional)}. Kinds the client knows (icons in game_mapoverlay):
--   party, temple, depot, npc, entry (rift way in), guardian (rift boss, alive or its spawn while it waits),
--   chest (rift reward chest), coffer (sealed rift coffer), goblin (treasure goblin), worldboss, invasion (the
--   invaders' target point), boss (invasion / dungeon boss)

ChaosMapMarksCore = ChaosMapMarksCore or {}
local M = ChaosMapMarksCore

M.KINDS = {
	party = true, temple = true, depot = true, npc = true, entry = true, guardian = true, chest = true,
	coffer = true, goblin = true, worldboss = true, invasion = true, boss = true
}

local floor = math.floor

local function num(v)
	v = tonumber(v)
	if not v or v ~= v then
		return nil
	end
	return floor(v)
end

-- a mark from a position table ({x, y, z} or an engine Position read as a table), nil when it is not one
function M.mark(kind, pos, name)
	if not M.KINDS[kind] or type(pos) ~= "table" and type(pos) ~= "userdata" then
		return nil
	end
	local x, y, z = num(pos.x), num(pos.y), num(pos.z)
	if not x or not y or not z or x <= 0 or y <= 0 or z < 0 or z > 15 then
		return nil
	end
	local m = {k = kind, x = x, y = y, z = z}
	if name ~= nil and name ~= "" then
		m.n = tostring(name)
	end
	return m
end

-- Chebyshev distance on one floor (math.huge across floors)
function M.distance(a, b)
	if a.z ~= b.z then
		return math.huge
	end
	return math.max(math.abs(a.x - b.x), math.abs(a.y - b.y))
end

-- add a mark to the list unless a mark of that kind already sits on the same tile; returns the mark or nil
function M.add(list, seen, kind, pos, name)
	local m = M.mark(kind, pos, name)
	if not m then
		return nil
	end
	local key = m.k .. ":" .. m.x .. ":" .. m.y .. ":" .. m.z
	if seen[key] then
		return nil
	end
	seen[key] = true
	list[#list + 1] = m
	return m
end

-- The square of a rift slot (rift_core.lua R.slotCenter: a grid of `spacing`-wide squares from `origin`).
-- Returns {x1, y1, x2, y2, z} or nil.
function M.riftArea(grid, slot)
	if type(grid) ~= "table" or type(grid.origin) ~= "table" or not num(slot) or not num(grid.cols) then
		return nil
	end
	local cols, spacing = num(grid.cols), num(grid.spacing)
	if cols < 1 or not spacing or spacing < 1 then
		return nil
	end
	local col, row = slot % cols, floor(slot / cols)
	local x1, y1 = grid.origin.x + col * spacing, grid.origin.y + row * spacing
	return {x1 = x1, y1 = y1, x2 = x1 + spacing - 1, y2 = y1 + spacing - 1, z = grid.origin.z}
end

-- Keeps the nearest `limit` marks to `center` (party members and the far event marks are kept first: they are
-- the reason to open the map). Sorts in place and returns the list.
local KEEP = {party = true, worldboss = true, invasion = true, entry = true, guardian = true, chest = true, coffer = true}
function M.trim(list, center, limit)
	if #list <= limit then
		return list
	end
	table.sort(list, function(a, b)
		local ka, kb = KEEP[a.k] and 0 or 1, KEEP[b.k] and 0 or 1
		if ka ~= kb then
			return ka < kb
		end
		local da, db = M.distance(a, center), M.distance(b, center)
		if da ~= db then
			return da < db
		end
		return a.k < b.k
	end)
	for i = #list, limit + 1, -1 do
		list[i] = nil
	end
	return list
end

return M
