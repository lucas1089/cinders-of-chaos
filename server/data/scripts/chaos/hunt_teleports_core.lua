-- Hunt teleports, pure logic (server/README.md "Hunt teleports"; tests/hunt_teleports_test.lua). No engine calls.
-- The config is hunt_teleports_config.lua; the places (slot, arrival, exit and level band of every placed plan) come
-- from data/lib/chaos_hunt_places.lua, which server/tools/install_content_areas.py writes into the installed server.
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.
ChaosHuntTeleportsCore = ChaosHuntTeleportsCore or {}
local H = ChaosHuntTeleportsCore

local function key(p)
	return p.x .. "," .. p.y .. "," .. p.z
end
H.key = key

local function isPos(p)
	return type(p) == "table" and type(p.x) == "number" and type(p.y) == "number" and type(p.z) == "number"
end

-- "pt-BR" for a Portuguese language code, else "en"
function H.lang(code)
	if type(code) == "string" and code:lower():sub(1, 2) == "pt" then
		return "pt-BR"
	end
	return "en"
end

-- the text of `k` in `lang` (the English key when the language has none), formatted
function H.text(cfg, lang, k, ...)
	local t = cfg.texts and cfg.texts[H.lang(lang)]
	local pattern = t and t[k] or k
	local ok, s = pcall(string.format, pattern, ...)
	if ok then
		return s
	end
	return (string.format(k, ...))
end

-- problems of the config and the places (strings); an empty list when both are usable
function H.validate(cfg, places)
	local out = {}
	if type(cfg) ~= "table" then
		return {"no config"}
	end
	if type(cfg.aid) ~= "number" or cfg.aid < 47930 or cfg.aid > 47939 then
		out[#out + 1] = "aid must be in the block 47930-47939"
	end
	local ids = {}
	for i, p in ipairs(cfg.plans or {}) do
		if type(p.id) ~= "string" then
			out[#out + 1] = "plans[" .. i .. "] has no id"
		elseif ids[p.id] then
			out[#out + 1] = "plan " .. p.id .. " is listed twice"
		end
		ids[p.id or ""] = true
		if type(p.monster) ~= "string" or p.monster == "" then
			out[#out + 1] = "plan " .. tostring(p.id) .. " has no display monster"
		end
	end
	if places == nil then
		return out
	end
	if type(places) ~= "table" or type(places.places) ~= "table" then
		out[#out + 1] = "places: not a table"
		return out
	end
	if not isPos(places.back) then
		out[#out + 1] = "places: no back tile"
	end
	local seen = {}
	for i, e in ipairs(places.places) do
		local name = tostring(e.id or i)
		for _, f in ipairs({"teleport", "arrival"}) do
			if not isPos(e[f]) then
				out[#out + 1] = name .. ": no " .. f .. " tile"
			end
		end
		if type(e.level) ~= "table" or type(e.level[1]) ~= "number" or type(e.level[2]) ~= "number" then
			out[#out + 1] = name .. ": no level band"
		end
		if isPos(e.teleport) then
			if seen[key(e.teleport)] then
				out[#out + 1] = name .. ": shares its teleport tile with " .. seen[key(e.teleport)]
			end
			seen[key(e.teleport)] = name
		end
	end
	return out
end

-- the plan entries of the config by id
local function cfgPlans(cfg)
	local by = {}
	for _, p in ipairs(cfg.plans or {}) do
		if p.id then
			by[p.id] = p
		end
	end
	return by
end

-- the corridor tile in front of a teleport of the room: below a north-row teleport, above a south-row one, towards
-- the stairs' column (room.back.x) for one on the corridor's end row; nil without the room's rows
function H.frontOf(cfg, pos)
	local r = cfg and cfg.room
	if not isPos(pos) or type(r) ~= "table" or type(r.teleportRows) ~= "table" then
		return nil
	end
	if pos.y == r.teleportRows[1] then
		return {x = pos.x, y = pos.y + 1, z = pos.z}
	elseif pos.y == r.teleportRows[2] then
		return {x = pos.x, y = pos.y - 1, z = pos.z}
	end
	local mid = r.back and r.back.x or pos.x
	return {x = pos.x < mid and pos.x + 1 or pos.x - 1, y = pos.y, z = pos.z}
end

-- the lookup tables: byTeleport[tile key] and byExit[tile key] -> entry {id, name, level, minLevel, teleport, sign,
-- arrival, exit, front, monster}; the config's entry of a plan (when it has one) gives minLevel and the display
-- monster; front (where the exit sends players back) is the places file's, else H.frontOf the teleport
function H.index(cfg, places)
	local idx = {byTeleport = {}, byExit = {}, list = {}, back = places and places.back, returns = {}, byReturn = {}}
	if type(places) ~= "table" or type(places.places) ~= "table" then
		return idx
	end
	local by = cfgPlans(cfg)
	for _, e in ipairs(places.places) do
		local c = by[e.id] or {}
		if isPos(e.teleport) and isPos(e.arrival) and type(e.level) == "table" then
			local entry = {
				id = e.id, name = e.name or e.id, level = {e.level[1], e.level[2]},
				minLevel = c.minLevel or e.level[1], teleport = e.teleport, sign = e.sign, arrival = e.arrival,
				exit = e.exit, monster = c.monster or e.monster,
				front = isPos(e.front) and e.front or H.frontOf(cfg, e.teleport)
			}
			idx.byTeleport[key(e.teleport)] = entry
			if isPos(e.exit) then
				idx.byExit[key(e.exit)] = entry
			end
			idx.list[#idx.list + 1] = entry
		end
	end
	-- the hall order (tools/hall_order.py): the base server's hunts (their teleports lead there by the map) and the
	-- floors' bands; only labels and signs here
	idx.base, idx.floors = {}, {}
	for _, e in ipairs(type(places.base) == "table" and places.base or {}) do
		if isPos(e.teleport) and type(e.level) == "table" then
			idx.base[#idx.base + 1] = {id = e.id, name = e.name or e.id, level = {e.level[1], e.level[2]},
				teleport = e.teleport, sign = e.sign, arrival = isPos(e.dest) and e.dest or nil,
				front = H.frontOf(cfg, e.teleport)}
		end
	end
	H.indexReturns(cfg, idx)
	for _, f in ipairs(type(places.floors) == "table" and places.floors or {}) do
		if type(f.z) == "number" and type(f.level) == "table" then
			idx.floors[f.z] = {f.level[1], f.level[2]}
		end
	end
	-- the quest hall (tools/hall_quests.py): where its "Quests" labels float (its corridor, the plaza's way in)
	if type(places.quests) == "table" and isPos(places.quests.label) then
		idx.quests = {label = places.quests.label, count = tonumber(places.quests.count) or 0,
			entrance = isPos(places.quests.entrance) and places.quests.entrance or nil}
	end
	return idx
end

-- the texts of a floor's band: "Floor 7: levels 1-500", "Floor 5: levels 1000+" (hi 0: no upper limit, the top floor)
local function floorText(cfg, lang, z, band)
	if band[2] == 0 then
		return H.text(cfg, lang, "Floor %d: levels %d+", z, band[1])
	end
	return H.text(cfg, lang, "Floor %d: levels %d-%d", z, band[1], band[2])
end

local function upText(cfg, lang, z, band)
	if band[2] == 0 then
		return H.text(cfg, lang, "Up: floor %d, levels %d+", z, band[1])
	end
	return H.text(cfg, lang, "Up: floor %d, levels %d-%d", z, band[1], band[2])
end

-- the floating labels of the hall's floors (cfg.hall.labels, the bands of idx.floors): {{pos, text}} in `lang`
-- "Floor 7: levels 1-500" over `at`; over `up` (the stairs up) the next floor's band, "Up: floor 6, levels 500-1000"
-- (a floor without an upper limit: "Floor 5: levels 1000+")
function H.floorLabels(cfg, idx, lang)
	local out = {}
	local hall = cfg.hall
	if not hall or not idx or not idx.floors then
		return out
	end
	for i, l in ipairs(hall.labels or {}) do
		local band = idx.floors[l.z]
		if band and l.at then
			out[#out + 1] = {pos = {x = l.at.x, y = l.at.y, z = l.z}, text = floorText(cfg, lang, l.z, band)}
		end
		local nz = hall.floors and hall.floors[i + 1]
		local up = nz and idx.floors[nz]
		if up and l.up then
			out[#out + 1] = {pos = {x = l.up.x, y = l.up.y, z = l.z}, text = upText(cfg, lang, nz, up)}
		end
	end
	return out
end

-- the quest hall's floating label: {pos, text} in `lang`, nil when the hall is not installed
function H.questLabel(cfg, idx, lang)
	local q = idx and idx.quests
	if not q then
		return nil
	end
	return {pos = q.label, text = H.text(cfg, lang, "Quests")}
end

-- every "Quests" label: over the quest hall's corridor and, when the places file has it, where the plaza's aisle
-- meets the corridor to the hall (beta 2026-10-20: the hall off the aisle was not found)
function H.questLabels(cfg, idx, lang)
	local out = {}
	local l = H.questLabel(cfg, idx, lang)
	if l then
		out[1] = l
		if idx.quests.entrance then
			out[2] = {pos = idx.quests.entrance, text = l.text}
		end
	end
	return out
end

-- a display monster's spot: a cell row of the room (cfg.room.cellRows) on a floor of the hall (cfg.display)
function H.isDisplaySpot(cfg, pos)
	local d, r = cfg and cfg.display, cfg and cfg.room
	if not isPos(pos) or type(d) ~= "table" or type(r) ~= "table" or type(r.cellRows) ~= "table" then
		return false
	end
	if pos.z < d.floors[1] or pos.z > d.floors[2] or pos.x < d.x[1] or pos.x > d.x[2] then
		return false
	end
	for _, y in ipairs(r.cellRows) do
		if pos.y == y then
			return true
		end
	end
	return false
end

-- the hunt a display monster at `pos` stands for (beta 2026-10-22: the showcase showed the monster's own level, a
-- Dragon [42] beside a hunt of levels 665+): the teleport of its alcove, a placed plan's (idx.byTeleport) or a base
-- hunt's (idx.base). A cell row's cell belongs to the teleport right in front of it, else to the one beside that (the
-- install's hall_order.display_cells); a cell beside the corridor's end row (cfg.hall.endRow) to the end teleport on
-- its inner side. nil when none.
function H.entryForDisplay(cfg, idx, pos)
	local r = cfg and cfg.room
	if not isPos(pos) or type(idx) ~= "table" or type(r) ~= "table" then
		return nil
	end
	if not idx.byDisplay then
		idx.byDisplay = {}
		for _, e in ipairs(idx.list or {}) do
			idx.byDisplay[key(e.teleport)] = e
		end
		for _, e in ipairs(idx.base or {}) do
			idx.byDisplay[key(e.teleport)] = idx.byDisplay[key(e.teleport)] or e
		end
	end
	local at = idx.byDisplay
	for i, row in ipairs(r.cellRows or {}) do
		local ty = r.teleportRows and r.teleportRows[i]
		if pos.y == row and ty then
			for _, dx in ipairs({0, -1, 1}) do
				local e = at[key({x = pos.x + dx, y = ty, z = pos.z})]
				if e then
					return e
				end
			end
		end
	end
	local endRow = cfg.hall and cfg.hall.endRow
	if endRow and (pos.y == endRow - 1 or pos.y == endRow + 1) then
		for _, dx in ipairs({-1, 1}) do
			local e = at[key({x = pos.x + dx, y = endRow, z = pos.z})]
			if e then
				return e
			end
		end
	end
	return nil
end

-- the level a display monster shows: the middle of its hunt's band
function H.displayLevel(entry)
	local lv = entry and entry.level
	if type(lv) ~= "table" or type(lv[1]) ~= "number" then
		return nil
	end
	local hi = (type(lv[2]) == "number" and lv[2] > 0) and lv[2] or lv[1]
	return math.floor((lv[1] + hi) / 2 + 0.5)
end

-- the label of a teleport in one language: "Widowmere, levels 480-640"
function H.label(cfg, entry, lang)
	return H.text(cfg, lang, "%s, levels %d-%d", entry.name, entry.level[1], entry.level[2])
end

-- the sign's text (signs have one text for everybody): the name, then the band in both languages
function H.signText(cfg, entry)
	return H.label(cfg, entry, "en") .. "\n" .. H.label(cfg, entry, "pt-BR")
end

-- a player of `level` steps on the teleport of `entry`: true, arrival message; or false, refusal message
function H.enter(cfg, entry, level, lang)
	if type(level) ~= "number" or level < entry.minLevel then
		return false, H.text(cfg, lang, "%s is for level %d and above.", entry.name, entry.minLevel)
	end
	return true, H.text(cfg, lang, "%s: monsters of level %d-%d. The portal at the camp leads back to the teleport room.",
		entry.name, entry.level[1], entry.level[2])
end

-- where the exit portal at `pos` sends players: the tile in front of the plan's own teleport (the floor and the slot
-- the player left from; beta 2026-10-20: every exit led to the middle of floor 6, though the hunts of levels 1-500
-- stand on floor 7), the room's back tile when the entry has none; nil for an exit that is not a placed plan's
function H.backFor(idx, pos)
	local e = isPos(pos) and idx and idx.byExit[key(pos)]
	if not e then
		return nil
	end
	return e.front or idx.back
end

-- ------------------------------------------------------------------ ways back (cfg.returns)
-- Owner, 2026-10-20: "many teleports to hunts have no teleport back". The base hunts have their way back on the map
-- and the planned hunts their camp portal; the hunts added to the hall without a base teleport (hall_hunts.csv rows
-- without a place) have none. cfg.returns lists them: startup puts a teleport beside the arrival that leads back in
-- front of the hunt's own teleport of the hall, wherever the hall order put it.

-- problems of cfg.returns (strings); `hunts` (optional): {id = {arrival = pos}} of the hall's hunts to check against
function H.validateReturns(cfg, hunts)
	local out = {}
	local r = cfg and cfg.returns
	if r == nil then
		return out
	end
	if type(r.radius) ~= "number" or r.radius < 1 or r.radius > 6 then
		out[#out + 1] = "returns.radius must be 1-6"
	end
	local ids, tiles = {}, {}
	for i, e in ipairs(r.list or {}) do
		local name = tostring(e.id or ("returns[" .. i .. "]"))
		if type(e.id) ~= "string" then
			out[#out + 1] = name .. ": no id"
		elseif ids[e.id] then
			out[#out + 1] = name .. ": listed twice"
		end
		ids[e.id or name] = true
		if not isPos(e.at) then
			out[#out + 1] = name .. ": no `at` tile"
		else
			if tiles[key(e.at)] then
				out[#out + 1] = name .. ": shares its tile with " .. tiles[key(e.at)]
			end
			tiles[key(e.at)] = name
			local h = hunts and hunts[e.id]
			if hunts and not h then
				out[#out + 1] = name .. ": not a hunt of the hall"
			elseif h and isPos(h.arrival) then
				local a = h.arrival
				local d = math.max(math.abs(a.x - e.at.x), math.abs(a.y - e.at.y))
				if a.z ~= e.at.z or d < 1 or d > (tonumber(r.radius) or 0) then
					out[#out + 1] = name .. ": `at` must be 1-" .. tostring(r.radius) .. " tiles from the arrival, same floor"
				end
			end
		end
	end
	return out
end

-- pairs each entry of cfg.returns.list with its hunt in the index (a placed plan of idx.list or a base hunt of
-- idx.base, by id): idx.returns = {{id, name, at, arrival, target}}, target the tile in front of the hunt's teleport.
-- A hunt without a teleport in the hall (not installed) gets no way back. idx.byReturn is filled by the engine with
-- the tile each one stands on.
function H.indexReturns(cfg, idx)
	idx.returns, idx.byReturn = {}, {}
	local byId = {}
	for _, list in ipairs({idx.list or {}, idx.base or {}}) do
		for _, e in ipairs(list) do
			byId[e.id] = e
		end
	end
	for _, r in ipairs(cfg.returns and cfg.returns.list or {}) do
		local e = byId[r.id]
		local target = e and (e.front or H.frontOf(cfg, e.teleport))
		local arrival = e and (e.arrival or e.dest)
		if e and isPos(target) and isPos(arrival) and (not isPos(r.at) or r.at.z == arrival.z) then
			idx.returns[#idx.returns + 1] = {id = r.id, name = e.name, at = isPos(r.at) and r.at or nil,
				arrival = arrival, target = target}
		end
	end
	return idx.returns
end

-- where the way back at `pos` sends players: the tile in front of its hunt's teleport; nil for another tile
function H.returnFor(idx, pos)
	local r = isPos(pos) and idx and idx.byReturn and idx.byReturn[key(pos)]
	return r and r.target or nil
end

-- the floating label over a way back, in `lang`
function H.returnLabel(cfg, lang)
	return H.text(cfg, lang, "Back to the teleport room")
end

-- the 8 tiles around p
local function around(p)
	local out = {}
	for dy = -1, 1 do
		for dx = -1, 1 do
			if dx ~= 0 or dy ~= 0 then
				out[#out + 1] = {x = p.x + dx, y = p.y + dy, z = p.z}
			end
		end
	end
	return out
end

-- true when a teleport on p would split the walkable tiles around it: the walkable ones of its 8 neighbours must all
-- reach each other through neighbours side by side (no diagonal squeeze past the corner), else p is a corridor, a
-- junction or a door and the teleport would block the way. info(pos) -> {walk, spot} or nil (see H.pickReturnTile).
function H.cutsWay(p, info)
	local walk = {}
	for _, q in ipairs(around(p)) do
		local i = info(q)
		if i and i.walk then
			walk[#walk + 1] = q
		end
	end
	if #walk == 0 then
		return true
	end
	local seen, stack, n = {[1] = true}, {1}, 1
	while #stack > 0 do
		local a = walk[table.remove(stack)]
		for j, b in ipairs(walk) do
			if not seen[j] and math.abs(a.x - b.x) + math.abs(a.y - b.y) == 1 then
				seen[j] = true
				n = n + 1
				stack[#stack + 1] = j
			end
		end
	end
	return n < #walk
end

-- the tile for the way back of a hunt arriving at `arrival`: a tile a player reaches from the arrival on foot within
-- `radius` tiles (8 directions, through walkable tiles), not the arrival itself, fit for a teleport (spot: walkable,
-- no stairs or hole, no protection zone, no house, no teleport, nothing lying on it) and not splitting the way
-- (H.cutsWay). `prefer` (the config's `at`) wins when it qualifies; else the nearest on foot, then north to south,
-- west to east. info(pos) -> {walk = bool, spot = bool} or nil (no tile). Returns the tile or nil.
function H.pickReturnTile(arrival, radius, info, prefer)
	if not isPos(arrival) then
		return nil
	end
	local steps, order = {[key(arrival)] = 0}, {}
	local queue, head = {arrival}, 1
	while head <= #queue do
		local p = queue[head]
		head = head + 1
		for _, q in ipairs(around(p)) do
			local k = key(q)
			if not steps[k] and math.max(math.abs(q.x - arrival.x), math.abs(q.y - arrival.y)) <= radius then
				local i = info(q)
				if i and i.walk then
					steps[k] = steps[key(p)] + 1
					queue[#queue + 1] = q
					order[#order + 1] = q
				end
			end
		end
	end
	local function fits(q)
		local i = info(q)
		return steps[key(q)] ~= nil and steps[key(q)] > 0 and i and i.spot and not H.cutsWay(q, info)
	end
	if isPos(prefer) and prefer.z == arrival.z and fits(prefer) then
		return prefer
	end
	table.sort(order, function(a, b)
		local sa, sb = steps[key(a)], steps[key(b)]
		if sa ~= sb then
			return sa < sb
		end
		if a.y ~= b.y then
			return a.y < b.y
		end
		return a.x < b.x
	end)
	for _, q in ipairs(order) do
		if fits(q) then
			return q
		end
	end
	return nil
end

return H
