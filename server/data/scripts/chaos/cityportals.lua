-- City portals, the engine side (server/README.md "City portals"): place a labelled portal near every temple (or in a
-- town's Hall of Services) and remember it, so cityportals_fx.lua marks it with an effect and a look text. No event is
-- registered here: hideout.lua, guild_hall.lua and npc_booths.lua load this file themselves (guarded), and the script
-- loader loading it again only keeps the same functions and the same registry.
--   ChaosCityPortals.place(spec)   spec = {kind, aid, item?, towns? (ids; nil = every town), offsets? (tried after the
--                                  config's fixed spot), spot? (the key of the hall / town spots; default kind),
--                                  title? (a proper name shown in the look text)}: one portal per town (temple).
--                                  Returns placed, positions
--   ChaosCityPortals.remove(aid)   remove every registered portal with that action id (a gate that closes); count
--   ChaosCityPortals.register(kind, aid, pos, town, title)   remember a portal placed by other means (title: a proper
--                                  name for this one portal's look text, e.g. a hunting area and its levels)
--   ChaosCityPortals.titleOf(aid, pos)   the look text's title: this portal's own, else the action id's
--   ChaosCityPortals.kindOf(aid)   the kind of a portal action id, or nil
--   ChaosCityPortals.hallPos(kind, town)   the tile of `kind` in the town's Hall of Services when the hall is on the map
if not ChaosCityPortalsCore then
	dofile("data/scripts/chaos/cityportals_core.lua")
end

ChaosCityPortals = ChaosCityPortals or {}
local X = ChaosCityPortals
local C = ChaosCityPortalsCore
X.placed = X.placed or {} -- "x,y,z" -> {x, y, z, kind, aid, town, item}
X.aids = X.aids or {} -- action id -> kind
X.titles = X.titles or {} -- action id -> a proper name for the look text (optional)

local function P(t)
	return Position(t.x, t.y, t.z)
end

local function prop(tile, name)
	local v = rawget(_G, name)
	return v ~= nil and tile:hasProperty(v) == true
end

local function flag(tile, name)
	local v = rawget(_G, name)
	return v ~= nil and tile.hasFlag ~= nil and tile:hasFlag(v) == true
end

-- items that keep a portal off a tile: anything that can be moved (something dropped there) and doors. Borders, grass,
-- flowers and other fixed floor dressing do not count (most temple squares have them)
local function loose(tile)
	local n = 0
	for _, it in ipairs(tile:getItems() or {}) do
		local t = it.getType and it:getType() or (ItemType and ItemType(it:getId()))
		if not t or (t.isMovable and t:isMovable()) or (t.isDoor and t:isDoor()) then
			n = n + 1
		end
	end
	return n
end

-- the facts of a tile for C.spotOk
function X.facts(pos)
	local tile = Tile(P(pos))
	if not tile then
		return nil
	end
	return {
		ground = tile:getGround() ~= nil,
		solid = prop(tile, "CONST_PROP_BLOCKSOLID"),
		path = prop(tile, "CONST_PROP_BLOCKPATH"),
		house = tile.getHouse ~= nil and tile:getHouse() ~= nil,
		teleport = flag(tile, "TILESTATE_TELEPORT") or (tile.getItemByType ~= nil and rawget(_G, "ITEM_TYPE_TELEPORT") ~= nil
			and tile:getItemByType(ITEM_TYPE_TELEPORT) ~= nil),
		floorchange = flag(tile, "TILESTATE_FLOORCHANGE"),
		loose = loose(tile),
	}
end

local function ours(pos, item, aid)
	local tile = Tile(P(pos))
	local it = tile and tile:getItemById(item)
	return it ~= nil and it:getActionId() == aid
end

function X.kindOf(aid)
	return aid and X.aids[aid] or nil
end

function X.titleOf(aid, pos)
	local p = pos and X.placed[C.key(pos)]
	if p and p.aid == aid and p.title then
		return p.title
	end
	return aid and X.titles[aid] or nil
end

function X.remove(aid)
	local n = 0
	for key, p in pairs(X.placed) do
		if p.aid == aid then
			local tile = Tile(P(p))
			local it = tile and tile:getItemById(p.item)
			if it and it:getActionId() == aid then
				it:remove()
				n = n + 1
			end
			X.placed[key] = nil
		end
	end
	return n
end

function X.register(kind, aid, pos, town, title)
	X.aids[aid] = kind
	X.placed[C.key(pos)] = {x = pos.x, y = pos.y, z = pos.z, kind = kind, aid = aid, town = town,
		item = C.cfg().item, title = title}
end

function X.hallPos(kind, town)
	local cfg = C.cfg()
	if not (cfg.hall and cfg.hall[kind]) then
		return nil
	end
	if not ChaosNpcBoothsCore then
		dofile("data/scripts/chaos/npc_booths_core.lua")
	end
	local K = ChaosNpcBoothsCore
	local bc = K.cfg()
	local hall = bc.enabled and K.hallOf(bc, town)
	local p = hall and K.portal(bc, hall, kind)
	if not p then
		return nil
	end
	-- the hall is on the map when its arrival tile is (npc_booths.lua X.hallReady)
	local a = hall.arrival or {0, 0, 0}
	local arrival = Tile(P(K.offset(hall, a[1], a[2], a[3])))
	if not (arrival and arrival:getGround() and Tile(P(p))) then
		return nil
	end
	return p
end

function X.place(spec)
	local cfg = C.cfg()
	local item = spec.item or cfg.item
	local made, positions, seen = 0, {}, {}
	local want
	if spec.towns then
		want = {}
		for _, id in ipairs(spec.towns) do
			want[id] = true
		end
	end
	X.aids[spec.aid] = spec.kind
	X.titles[spec.aid] = spec.title
	local spot = spec.spot or spec.kind
	for _, town in ipairs(Game.getTowns() or {}) do
		local id = town:getId()
		local t = town:getTemplePosition()
		local k = t and C.key(t)
		if t and t.x > 0 and not seen[k] and (not want or want[id]) and Tile(t) then
			seen[k] = true
			local list = C.candidates(cfg, spot, id, t, X.hallPos(spot, id), spec.offsets)
			local pos, had = C.pick(list, function(p)
				if ours(p, item, spec.aid) then
					return "ours"
				end
				return C.spotOk(X.facts(p)) and "free" or "taken"
			end)
			if pos and not had then
				local it = Game.createItem(item, 1, P(pos))
				if it then
					it:setActionId(spec.aid)
					made = made + 1
				else
					pos = nil
				end
			end
			if pos then
				X.register(spec.kind, spec.aid, pos, id)
				positions[#positions + 1] = {x = pos.x, y = pos.y, z = pos.z, town = id, why = pos.why}
			elseif spec.log then
				spec.log(string.format("no free tile for the %s next to the temple of town %d", cfg.kinds[spec.kind]
					and cfg.kinds[spec.kind].name or spec.kind, id))
			end
		end
	end
	return made, positions
end

return X
