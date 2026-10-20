-- Pure rules of the stat help of the passive tree (passivetree_stats.lua, passive_builds_core.lua; tests:
-- tests/passivetree_stats_test.lua). Texts and lists: passivetree_stats_config.lua. Lua 5.1 / LuaJIT and Lua 5.3.
--
--   PassiveStatsCore.expand(cfg, list)              the stat keys of a list, "@group" names replaced by their stats
--   PassiveStatsCore.classInfo(cfg, classKey)       {primary, secondary, irrelevant (lists), tag = {[stat] = "primary" |
--                                                   "secondary"}, bad = {[stat] = true}} or nil for an unknown class
--   PassiveStatsCore.isFlag(stat)                   a keystone / notable / archetype flag (text in the node tooltip)
--   PassiveStatsCore.nodeStats(node)                every plain stat key a node can give (own, variants, mastery effects)
--   PassiveStatsCore.treeStats(tree, classKey)      sorted list of the plain stat keys the class's nodes give
--   PassiveStatsCore.nodeTag(stats, info)           "primary" if a stat of the table is primary, else "secondary", else nil
--   PassiveStatsCore.header(cfg, info, present, T)  {primary = "A, B", secondary = "C"}: group labels, only stats the class
--                                                   can find in the tree, at most `max` entries
--   PassiveStatsCore.parts(cfg, classKey, tree, T, per)  the statInfo messages' data tables

PassiveStatsCore = PassiveStatsCore or {}
local M = PassiveStatsCore

function M.isFlag(stat)
	return (stat:match("^ar%u") or stat:match("^ks%u") or stat:match("^ct%u")) ~= nil
end

function M.expand(cfg, list)
	local out, seen = {}, {}
	for _, entry in ipairs(list or {}) do
		local group = entry:match("^@(.+)$")
		local keys = group and cfg.groups[group] or {entry}
		for _, key in ipairs(keys) do
			if not seen[key] then
				seen[key] = true
				out[#out + 1] = key
			end
		end
	end
	return out
end

function M.classInfo(cfg, classKey)
	local c = cfg.classes[classKey]
	if not c then
		return nil
	end
	local info = {
		primary = M.expand(cfg, c.primary), secondary = M.expand(cfg, c.secondary), irrelevant = M.expand(cfg, c.irrelevant),
		tag = {}, bad = {}, raw = c
	}
	for _, key in ipairs(info.secondary) do
		info.tag[key] = "secondary"
	end
	for _, key in ipairs(info.primary) do
		info.tag[key] = "primary"
	end
	for _, key in ipairs(info.irrelevant) do
		info.bad[key] = true
	end
	return info
end

function M.nodeStats(node)
	local set = {}
	local function add(t)
		for stat in pairs(t or {}) do
			if not M.isFlag(stat) then
				set[stat] = true
			end
		end
	end
	add(node.s)
	for _, v in pairs(node.v or {}) do
		add(v)
	end
	for _, m in ipairs(node.m or {}) do
		add(m)
	end
	return set
end

function M.treeStats(tree, classKey)
	local set = {}
	for _, node in pairs(tree.nodes) do
		if not node.c or node.c[classKey] == true then
			for stat in pairs(M.nodeStats(node)) do
				set[stat] = true
			end
		end
	end
	local list = {}
	for stat in pairs(set) do
		list[#list + 1] = stat
	end
	table.sort(list)
	return list
end

function M.nodeTag(stats, info)
	local tag
	for stat in pairs(stats or {}) do
		local t = info.tag[stat]
		if t == "primary" then
			return "primary"
		elseif t == "secondary" then
			tag = "secondary"
		end
	end
	return tag
end

local function label(cfg, entry, T)
	local group = entry:match("^@(.+)$")
	if group then
		return T(cfg.groupNames[group] or group)
	end
	local s = cfg.stats[entry]
	return T(s and s[1] or entry)
end

function M.header(cfg, info, present, T, max)
	max = max or 6
	local function build(raw)
		local names, seen = {}, {}
		for _, entry in ipairs(raw) do
			local keys = M.expand(cfg, {entry})
			local any = false
			for _, key in ipairs(keys) do
				any = any or present[key]
			end
			local name = any and label(cfg, entry, T)
			if name and not seen[name] and #names < max then
				seen[name] = true
				names[#names + 1] = name
			end
		end
		return table.concat(names, ", ")
	end
	return {primary = build(info.raw.primary), secondary = build(info.raw.secondary)}
end

-- the statInfo messages: {cls, part, parts, header (first part), stats = {{k, n, d, t}}}; T translates an English text
function M.parts(cfg, classKey, tree, T, per)
	local info = M.classInfo(cfg, classKey)
	if not info then
		return {}
	end
	local keys = M.treeStats(tree, classKey)
	local present, rows = {}, {}
	for _, key in ipairs(keys) do
		present[key] = true
		local s = cfg.stats[key]
		if s then
			rows[#rows + 1] = {k = key, n = T(s[1]), d = T(s[2]), t = info.tag[key]}
		end
	end
	per = per or 10
	local parts = {}
	for i = 1, #rows, per do
		local chunk = {}
		for j = i, math.min(i + per - 1, #rows) do
			chunk[#chunk + 1] = rows[j]
		end
		parts[#parts + 1] = {cls = classKey, stats = chunk}
	end
	if #parts == 0 then
		parts[1] = {cls = classKey, stats = {}}
	end
	for i, p in ipairs(parts) do
		p.part, p.parts = i, #parts
	end
	parts[1].header = M.header(cfg, info, present, T)
	return parts
end

return PassiveStatsCore
