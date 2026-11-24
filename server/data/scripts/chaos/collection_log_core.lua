-- collection_log_core.lua: the Collection log (O753), pure rules. Engine glue collection_log.lua, numbers
-- collection_log_config.lua, tests tests/collection_log_test.lua. server/README.md "Collection log (O753)".
--
-- Every unique, set piece, raid unique and card by source, with its state for one character: owned (it dropped for the
-- character: the log table chaos_collection_log, or chaos_conquest_seen of the Conquest vendor, or a Deck of Cards copy),
-- seen (the character killed a monster that lists it, chaos_bestiary) or not yet.
--   CL.groupOf(e, pinnacleIds)          -> the group key of a unique entry (chaos_unique_items.lua)
--   CL.catalog(input)                   -> {{id, name, g}} in group order then name; input = {uniques, raid, cards, pinnacle}
--   CL.state(row, mine)                 -> 2 owned, 1 seen, 0 not yet; mine = {owned = {[id] = {count, at}}, seen, killed}
--   CL.rows(catalog, mine)              -> the payload rows {i, n, g, s, k, d}
--   CL.summary(rows)                    -> {owned, seen, total, byGroup = {[g] = {owned, total}}}
--   CL.groups(cfg, catalog)             -> the group list {k, l, a} of the groups that have rows, in cfg.groupOrder
--   CL.merge(logRows, seenRows)         -> {[id] = {count, at}}: the first date of either, the log's count (at least 1)
--   CL.sqlCreate(t), CL.sqlNote(t, guid, id, n, now), CL.sqlSelect(t, guid)
-- Lua 5.1 / LuaJIT and Lua 5.3.

ChaosCollectionLogCore = ChaosCollectionLogCore or {}
local CL = ChaosCollectionLogCore

local floor = math.floor

local function int(v)
	v = tonumber(v)
	if not v or v ~= v then
		return 0
	end
	return floor(v)
end

function CL.groupOf(e, pinnacleIds)
	if pinnacleIds and pinnacleIds[int(e.id)] then
		return "pinnacle"
	elseif e.set then
		return "set:" .. tostring(e.set)
	elseif e.ascended then
		return "ascended"
	elseif e.bossOnly then
		return "boss"
	elseif e.minMonsterLevel then
		return "endgame"
	end
	return "hunt"
end

-- input.uniques: the unique entries; input.raid: {{id, name}}; input.cards: {{id, name}}; input.pinnacle: {[id] = true};
-- input.order: {group prefix -> rank} (cfg.groupOrder as a map)
function CL.catalog(input)
	local out, seen = {}, {}
	local function add(id, name, g, monsters)
		id = int(id)
		if id <= 0 or seen[id] then
			return
		end
		seen[id] = true
		out[#out + 1] = {id = id, name = tostring(name or id), g = g, monsters = monsters}
	end
	for _, e in ipairs(input.uniques or {}) do
		if type(e) == "table" then
			add(e.id, e.name, CL.groupOf(e, input.pinnacle), e.monsters)
		end
	end
	for _, r in ipairs(input.raid or {}) do
		add(r.id, r.name, "raid")
	end
	for _, c in ipairs(input.cards or {}) do
		add(c.id, c.name, "card")
	end
	local rank = input.order or {}
	local function rankOf(g)
		return rank[g] or rank[(tostring(g):match("^(%a+):") or g)] or 99
	end
	table.sort(out, function(a, b)
		local ra, rb = rankOf(a.g), rankOf(b.g)
		if ra ~= rb then
			return ra < rb
		end
		if a.g ~= b.g then
			return a.g < b.g
		end
		if a.name ~= b.name then
			return a.name < b.name
		end
		return a.id < b.id
	end)
	return out
end

local function listed(monsters, killed)
	if type(monsters) ~= "table" or not killed then
		return false
	end
	for _, m in pairs(monsters) do
		if killed[tostring(m):lower()] then
			return true
		end
	end
	return false
end

function CL.state(row, mine)
	mine = mine or {}
	if (mine.owned or {})[row.id] then
		return 2
	end
	if listed(row.monsters, mine.killed) then
		return 1
	end
	return 0
end

function CL.rows(catalog, mine)
	mine = mine or {}
	local out = {}
	for _, r in ipairs(catalog) do
		local s = CL.state(r, mine)
		local o = (mine.owned or {})[r.id]
		out[#out + 1] = {i = r.id, n = r.name, g = r.g, s = s, k = o and int(o.count) or 0, d = o and int(o.at) or 0}
	end
	return out
end

function CL.summary(rows)
	local out = {owned = 0, seen = 0, total = #rows, byGroup = {}}
	for _, r in ipairs(rows) do
		local b = out.byGroup[r.g]
		if not b then
			b = {owned = 0, total = 0}
			out.byGroup[r.g] = b
		end
		b.total = b.total + 1
		if r.s == 2 then
			out.owned = out.owned + 1
			b.owned = b.owned + 1
		elseif r.s == 1 then
			out.seen = out.seen + 1
		end
	end
	return out
end

-- {k = group key, l = English label (a pattern), a = its argument (a set's name)}
function CL.groups(cfg, catalog, setNames)
	local have, out = {}, {}
	for _, r in ipairs(catalog) do
		if not have[r.g] then
			have[r.g] = true
			local kind, arg = tostring(r.g):match("^(%a+):(.+)$")
			if kind then
				out[#out + 1] = {k = r.g, l = (cfg.labels or {})[kind] or kind, a = (setNames or {})[arg] or arg}
			else
				out[#out + 1] = {k = r.g, l = (cfg.labels or {})[r.g] or r.g}
			end
		end
	end
	return out
end

function CL.merge(logRows, seenRows)
	local out = {}
	for _, r in ipairs(logRows or {}) do
		local id = int(r.item_id)
		if id > 0 then
			out[id] = {count = math.max(1, int(r.count)), at = int(r.first_at)}
		end
	end
	for _, r in ipairs(seenRows or {}) do
		local id = int(r.item_id)
		if id > 0 then
			local o = out[id]
			local at = int(r.at)
			if not o then
				out[id] = {count = 1, at = at}
			elseif at > 0 and (o.at <= 0 or at < o.at) then
				o.at = at
			end
		end
	end
	return out
end

function CL.sqlCreate(t)
	return "CREATE TABLE IF NOT EXISTS `" .. t .. "` (`player_id` int(11) NOT NULL, `item_id` int(10) unsigned NOT NULL, " ..
		"`count` int(10) unsigned NOT NULL DEFAULT 0, `first_at` int(10) unsigned NOT NULL DEFAULT 0, " ..
		"`last_at` int(10) unsigned NOT NULL DEFAULT 0, PRIMARY KEY (`player_id`, `item_id`)) ENGINE=InnoDB DEFAULT CHARSET=utf8"
end

function CL.sqlNote(t, guid, id, n, now)
	return string.format("INSERT INTO `%s` (`player_id`, `item_id`, `count`, `first_at`, `last_at`) VALUES (%d, %d, %d, %d, %d) " ..
		"ON DUPLICATE KEY UPDATE `count` = `count` + %d, `last_at` = %d", t, int(guid), int(id), math.max(1, int(n)), int(now),
		int(now), math.max(1, int(n)), int(now))
end

function CL.sqlSelect(t, guid)
	return string.format("SELECT `item_id`, `count`, `first_at` FROM `%s` WHERE `player_id` = %d", t, int(guid))
end

return CL
