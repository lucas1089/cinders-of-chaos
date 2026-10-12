-- treestats_core.lua: the passive tree pick statistics without engine calls (treestats.lua; tests:
-- server/tests/treestats_test.lua). Lua 5.1 / LuaJIT and Lua 5.3.
--
-- From the saved trees (the `nodes` column of chaos_passive_tree, the active preset of each character: its lowest
-- preset number, as passivetree.lua reads it) it counts, per class line and level band, how many characters hold
-- each node. Only counts leave this file: no character name, id or account is ever in a result, a report or the CSV.
--
--   ChaosTreeStatsCore.bandOf(level, bands)           the band label of a level ("300-499", "1000+"), nil below the first
--   ChaosTreeStatsCore.aggregate(rows, ctx)           stats[line][band] = {characters, counts = {[node id] = n}} (+ "all")
--   ChaosTreeStatsCore.lineNodes(tree, classes)        the node ids a line may take (sorted)
--   ChaosTreeStatsCore.top(entry, n) / never(entry, ids)   most taken nodes / nodes nobody of the line and band took
--   ChaosTreeStatsCore.describe(node)                  a short text of a node's stats ("incrementFire+3 absorbFire+1")
--   ChaosTreeStatsCore.report(stats, tree, ctx, line, band, n)   the lines /treestats prints
--   ChaosTreeStatsCore.csv(stats, tree, ctx)           the CSV text, rows written, bands left out (too few characters)

ChaosTreeStatsCore = ChaosTreeStatsCore or {}
local S = ChaosTreeStatsCore

S.ALL = "all"

function S.bandLabel(b)
	return b[2] and (b[1] .. "-" .. b[2]) or (b[1] .. "+")
end

function S.bandOf(level, bands)
	level = tonumber(level) or 0
	for _, b in ipairs(bands or {}) do
		if level >= b[1] and (not b[2] or level <= b[2]) then
			return S.bandLabel(b)
		end
	end
	return nil
end

-- the band labels in order, then "all"
function S.bandLabels(bands)
	local out = {}
	for _, b in ipairs(bands or {}) do
		out[#out + 1] = S.bandLabel(b)
	end
	out[#out + 1] = S.ALL
	return out
end

-- node ids of a saved allocation text ("2,3,9" or "2,3,9,665|665:2"), each once
function S.parseNodes(text)
	local out, seen = {}, {}
	text = tostring(text or "")
	text = text:match("^([^|]*)") or text
	for token in text:gmatch("%d+") do
		local id = tonumber(token)
		if id and not seen[id] then
			seen[id] = true
			out[#out + 1] = id
		end
	end
	return out
end

-- rows: {{player, preset, vocation, level, group, nodes}} (any order; a character may have several presets)
-- ctx: {tree, bands, lineOf = function(vocation) -> line key or nil, staffGroup}
-- A character counts once, with its active preset (the lowest preset number), when it is not staff, its vocation has a
-- line and its tree holds at least one known node. The root and unknown (retired) ids are not counted.
function S.aggregate(rows, ctx)
	local active = {}
	for _, r in ipairs(rows or {}) do
		local key = r.player
		local cur = active[key]
		if key ~= nil and (not cur or (tonumber(r.preset) or 0) < (tonumber(cur.preset) or 0)) then
			active[key] = r
		end
	end
	local stats = {}
	local tree = ctx.tree
	for _, r in pairs(active) do -- (counts only: the order of the characters does not matter)
		local line = ctx.lineOf and ctx.lineOf(tonumber(r.vocation) or 0) or nil
		local band = S.bandOf(r.level, ctx.bands)
		local staff = ctx.staffGroup and (tonumber(r.group) or 1) >= ctx.staffGroup
		if line and band and not staff then
			local ids = {}
			for _, id in ipairs(S.parseNodes(r.nodes)) do
				if id ~= tree.root and tree.nodes[id] then
					ids[#ids + 1] = id
				end
			end
			if #ids > 0 then
				stats[line] = stats[line] or {}
				for _, b in ipairs({band, S.ALL}) do
					local entry = stats[line][b]
					if not entry then
						entry = {characters = 0, counts = {}}
						stats[line][b] = entry
					end
					entry.characters = entry.characters + 1
					for _, id in ipairs(ids) do
						entry.counts[id] = (entry.counts[id] or 0) + 1
					end
				end
			end
		end
	end
	return stats
end

-- the node ids (root excluded) a line may take: every node without a class list, and those listing a class of the line
function S.lineNodes(tree, classes)
	local out = {}
	for id, node in pairs(tree.nodes) do
		if id ~= tree.root then
			local ok = node.c == nil
			for _, k in ipairs(classes or {}) do
				ok = ok or (node.c and node.c[k] == true)
			end
			if ok then
				out[#out + 1] = id
			end
		end
	end
	table.sort(out)
	return out
end

-- the n most taken nodes of an entry: {{id, count, share (0..1 of the characters)}}, most first, then lowest id
function S.top(entry, n)
	local list = {}
	if not entry then
		return list
	end
	for id, count in pairs(entry.counts) do
		list[#list + 1] = {id = id, count = count, share = entry.characters > 0 and count / entry.characters or 0}
	end
	table.sort(list, function(a, b)
		if a.count ~= b.count then
			return a.count > b.count
		end
		return a.id < b.id
	end)
	for i = #list, (n or #list) + 1, -1 do
		list[i] = nil
	end
	return list
end

-- the ids of `lineIds` no character of the entry took (all of them for a missing entry)
function S.never(entry, lineIds)
	local out = {}
	for _, id in ipairs(lineIds or {}) do
		if not (entry and entry.counts[id]) then
			out[#out + 1] = id
		end
	end
	return out
end

-- "incrementFire+3 absorbFire+1"; a keystone or class flag by its key; a mastery node "mastery (n effects)";
-- a node with per-class variants "variants (n classes)"
function S.describe(node)
	if not node then
		return "?"
	end
	if node.m then
		return "mastery (" .. #node.m .. " effects)"
	end
	local parts = {}
	for k, v in pairs(node.s or {}) do
		if k:sub(1, 2) == "ks" or k:sub(1, 2) == "ct" then
			parts[#parts + 1] = k
		else
			parts[#parts + 1] = k .. "+" .. tostring(v)
		end
	end
	if #parts == 0 and node.v then
		local n = 0
		for _ in pairs(node.v) do
			n = n + 1
		end
		return "variants (" .. n .. " classes)"
	end
	table.sort(parts)
	return #parts > 0 and table.concat(parts, " ") or "-"
end

local function pct(share)
	return string.format("%d%%", math.floor(share * 100 + 0.5))
end

-- ctx: {lineClasses = {[line] = {class keys}}, minCharacters}
-- Returns the lines /treestats prints for one line and band
function S.report(stats, tree, ctx, line, band, n, neverListed)
	local out = {}
	local entry = stats[line] and stats[line][band]
	local chars = entry and entry.characters or 0
	local few = chars > 0 and ctx.minCharacters and chars < ctx.minCharacters
	out[#out + 1] = string.format("Passive tree picks: %s, level %s, %d character%s%s.", line, band, chars,
		chars == 1 and "" or "s", few and " (few characters: not in the CSV)" or "")
	if chars == 0 then
		out[#out + 1] = "No saved tree in this line and band."
		return out
	end
	out[#out + 1] = string.format("Top %d:", n)
	for i, t in ipairs(S.top(entry, n)) do
		out[#out + 1] = string.format("%2d. node %d  %d (%s)  %s", i, t.id, t.count, pct(t.share), S.describe(tree.nodes[t.id]))
	end
	local never = S.never(entry, S.lineNodes(tree, ctx.lineClasses and ctx.lineClasses[line] or {}))
	local shown = {}
	for i = 1, math.min(#never, neverListed or 40) do
		shown[i] = tostring(never[i])
	end
	out[#out + 1] = string.format("Never taken: %d node%s%s%s", #never, #never == 1 and "" or "s", #never > 0 and ": " or ".",
		table.concat(shown, ", ") .. (#never > #shown and ", ..." or ""))
	return out
end

local function csvField(text)
	text = tostring(text)
	if text:find('[,"\n]') then
		return '"' .. text:gsub('"', '""') .. '"'
	end
	return text
end

-- ctx: {bands, lineClasses = {[line] = {class keys}}, lines = {line keys in order}, minCharacters}
-- One row per line, band (the bands, then "all") and node the line may take, counts of 0 included:
--   line,band,characters,node,count,share,stats
-- A line and band with fewer than minCharacters characters is left out (returned in `skipped` as "line band").
function S.csv(stats, tree, ctx)
	local out = {"line,band,characters,node,count,share,stats"}
	local skipped, written = {}, 0
	for _, line in ipairs(ctx.lines or {}) do
		local ids = S.lineNodes(tree, ctx.lineClasses and ctx.lineClasses[line] or {})
		for _, band in ipairs(S.bandLabels(ctx.bands)) do
			local entry = stats[line] and stats[line][band]
			if entry and entry.characters > 0 then
				if ctx.minCharacters and entry.characters < ctx.minCharacters then
					skipped[#skipped + 1] = line .. " " .. band
				else
					for _, id in ipairs(ids) do
						local count = entry.counts[id] or 0
						out[#out + 1] = table.concat({csvField(line), csvField(band), entry.characters, id, count,
							string.format("%.3f", count / entry.characters), csvField(S.describe(tree.nodes[id]))}, ",")
						written = written + 1
					end
				end
			end
		end
	end
	return table.concat(out, "\n") .. "\n", written, skipped
end

return S
