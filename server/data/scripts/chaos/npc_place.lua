-- Startup NPCs next to a temple: the engine side of npc_place_core.lua (the search, why, and the rules).
--   ChaosNpcPlace.spot(temple, offsets, name, opts) -> Position | nil   a free spot (others = every NPC near the temple
--                                                                      but one called `name`)
--   ChaosNpcPlace.place(name, temple, offsets, opts) -> Npc | nil       an NPC of that name already near the temple (a
--                                                                      reload) or a new one on spot()
-- opts: radius, spacing, minFromTemple, minOpen (npc_place_core.lua K.DEFAULTS); depotFallback = true: no spot near
-- the temple -> the same search around the town's nearest depot (ChaosNpcPlaceCore.depotAnchors). Used by item_prices.lua (Loot Buyer),
-- gamble.lua (the Gambler), ascension_quest.lua (Ascendant Oracle), tales.lua (Archivist Maelis), professions.lua
-- (Material Broker) and factions.lua. An NPC with a booth in its town's Hall of Services (npc_booths_config.lua) is
-- placed in the booth instead (ChaosNpcBooths.spotForTemple). Lua 5.1 / LuaJIT compatible.

if not ChaosNpcPlaceCore then
	dofile("data/scripts/chaos/npc_place_core.lua")
end

ChaosNpcPlace = ChaosNpcPlace or {}
local NP = ChaosNpcPlace
local K = ChaosNpcPlaceCore

local function flag(tile, f)
	return f ~= nil and tile:hasFlag(f)
end

local function prop(tile, p)
	return p ~= nil and tile:hasProperty(p)
end

local function standable(tile)
	if not tile or not tile:getGround() then
		return false
	end
	if flag(tile, TILESTATE_TELEPORT) or flag(tile, TILESTATE_FLOORCHANGE) then
		return false
	end
	local okH, house = pcall(function() return tile:getHouse() end)
	return not (okH and house)
end

local function isDoorTile(tile)
	if not standable(tile) then
		return false
	end
	local okI, list = pcall(function() return tile:getItems() end)
	for _, item in ipairs(okI and list or {}) do
		local okD, door = pcall(function() return ItemType(item:getId()):isDoor() end)
		if okD and door then
			return true
		end
	end
	return false
end

local function near(temple, radius)
	local ok, list = pcall(Game.getSpectators, temple, false, false, radius, radius, radius, radius)
	local out = {}
	for _, c in ipairs(ok and list or {}) do
		local okN, isNpc = pcall(function() return c:isNpc() end)
		if okN and isNpc then
			local okP, pos = pcall(function() return c:getPosition() end)
			pos = okP and pos or nil
			if not pos or pos.z == temple.z then
				out[#out + 1] = {npc = c, pos = pos}
			end
		end
	end
	return out
end

function NP.spot(temple, offsets, name, opts)
	opts = opts or {}
	local radius = opts.radius or K.DEFAULTS.radius
	local spacing = opts.spacing or K.DEFAULTS.spacing
	local cache = {}
	local function tileAt(dx, dy)
		local k = dx .. ":" .. dy
		if cache[k] == nil then
			cache[k] = Tile(Position(temple.x + dx, temple.y + dy, temple.z)) or false
		end
		return cache[k] or nil
	end
	local others = {}
	for _, e in ipairs(near(temple, radius + spacing)) do
		if e.pos and (not name or e.npc:getName():lower() ~= name:lower()) then
			others[#others + 1] = {e.pos.x - temple.x, e.pos.y - temple.y}
		end
	end
	local dx, dy = K.pick({
		walkable = function(x, y)
			local t = tileAt(x, y)
			return standable(t) and not prop(t, CONST_PROP_BLOCKSOLID) and not prop(t, CONST_PROP_BLOCKPATH)
		end,
		door = function(x, y) return isDoorTile(tileAt(x, y)) end,
		free = function(x, y)
			local t = tileAt(x, y)
			return t ~= nil and not t:getTopCreature()
		end,
		offsets = offsets, others = others, radius = radius, spacing = spacing,
		minFromTemple = opts.minFromTemple, minOpen = opts.minOpen
	})
	if not dx then
		return nil
	end
	return Position(temple.x + dx, temple.y + dy, temple.z)
end

-- the NPC's booth in its town's Hall of Services (npc_booths.lua), when it has one and the hall is on the map
local function booth(name, temple)
	if not (ChaosNpcBooths and ChaosNpcBooths.spotForTemple) then
		return nil
	end
	local ok, pos = pcall(ChaosNpcBooths.spotForTemple, name, temple)
	return ok and pos or nil
end

function NP.place(name, temple, offsets, opts)
	local b = booth(name, temple)
	if b then
		for _, e in ipairs(near(b, 1)) do
			if e.npc:getName():lower() == name:lower() then
				return e.npc
			end
		end
		return Game.createNpc(name, b)
	end
	local radius = (opts and opts.radius) or K.DEFAULTS.radius
	for _, e in ipairs(near(temple, radius)) do
		if e.npc:getName():lower() == name:lower() then
			return e.npc
		end
	end
	local pos = NP.spot(temple, offsets, name, opts)
	if pos then
		return Game.createNpc(name, pos)
	end
	if not (opts and opts.depotFallback) then
		return nil
	end
	for _, a in ipairs(NP.depotAnchors(temple)) do
		local anchor = Position(a.x, a.y, a.z)
		for _, e in ipairs(near(anchor, radius)) do
			if e.npc:getName():lower() == name:lower() then
				return e.npc
			end
		end
		pos = NP.spot(anchor, {}, name, opts)
		if pos then
			return Game.createNpc(name, pos)
		end
	end
	return nil
end

-- the depots of the map markers (data/chaos_poi.lua, written at install by tools/gen_poi.py) near a temple
function NP.depotAnchors(temple)
	if NP.poiMarks == nil then
		local ok, t = pcall(dofile, NP.POI_FILE or "data/chaos_poi.lua")
		NP.poiMarks = ok and type(t) == "table" and type(t.marks) == "table" and t.marks or false
	end
	return K.depotAnchors(temple, NP.poiMarks or {})
end
