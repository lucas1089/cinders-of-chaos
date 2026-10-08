-- Respec rules without engine calls (respec.lua, buildshare.lua, server/tests/respec_test.lua). Numbers in respec_config.lua.
--   ChaosRespecCore.fullCost(level, kind, cfg)        gold of a full reset; kind "tree" (default) or "paragon"; 0 below
--                                                     cfg.freeBelowLevel
--   ChaosRespecCore.nodeCost(level, cfg)              gold of a single-node refund (0 below cfg.freeBelowLevel)
--   ChaosRespecCore.freeReason(level, vocId, stored, cfg)   why the next full reset is free ("level", "vocation") or nil
--   ChaosRespecCore.canRemove(tree, ids, id)          true, or nil + error: the node is allocated and every other
--                                                     allocated node stays connected to the root without it
--   ChaosRespecCore.formatGold(n)                     "1,250,000"

ChaosRespecCore = ChaosRespecCore or {}
local R = ChaosRespecCore

local function config(cfg)
	return cfg or ChaosRespecConfig
end

local function curve(points, level)
	if level <= points[1][1] then
		return points[1][2]
	end
	for i = 2, #points do
		local a, b = points[i - 1], points[i]
		if level <= b[1] then
			return a[2] + (b[2] - a[2]) * (level - a[1]) / (b[1] - a[1])
		end
	end
	local a, b = points[#points - 1], points[#points]
	return b[2] + (b[2] - a[2]) * (level - b[1]) / (b[1] - a[1])
end

local function round(value, step)
	step = step or 1
	return math.floor(value / step) * step
end

function R.fullCost(level, kind, cfg)
	cfg = config(cfg)
	level = tonumber(level) or 0
	if level < cfg.freeBelowLevel then
		return 0
	end
	local cost = curve(cfg.fullCurve, level)
	if kind == "paragon" then
		cost = cost * (cfg.paragonFactor or 1)
	end
	return round(cost, cfg.roundTo)
end

function R.nodeCost(level, cfg)
	cfg = config(cfg)
	level = tonumber(level) or 0
	if level < cfg.freeBelowLevel then
		return 0
	end
	return math.max(cfg.nodeMin or 0, round(curve(cfg.fullCurve, level) * cfg.nodeShare, cfg.roundTo))
end

-- stored: the vocation id the respec storage holds (-1 / nil: not recorded yet, no free reset)
function R.freeReason(level, vocId, stored, cfg)
	cfg = config(cfg)
	if (tonumber(level) or 0) < cfg.freeBelowLevel then
		return "level"
	end
	if stored and stored >= 0 and vocId and vocId ~= stored then
		return "vocation"
	end
	return nil
end

-- tree = passivetree_data.lua ({root, nodes = {[id] = {n = {neighbours}}}}); ids = allocated ids (list)
function R.canRemove(tree, ids, id)
	id = tonumber(id)
	local set, found = {}, false
	for _, other in ipairs(ids or {}) do
		set[other] = true
		if other == id then
			found = true
		end
	end
	if not id or not tree.nodes[id] or id == tree.root then
		return nil, "Unknown node."
	end
	if not found then
		return nil, "That node is not allocated."
	end
	set[id] = nil
	local reached, queue, head, count = {[tree.root] = true}, {tree.root}, 1, 0
	while head <= #queue do
		local current = queue[head]
		head = head + 1
		for _, neighbour in ipairs(tree.nodes[current].n or {}) do
			if set[neighbour] and not reached[neighbour] then
				reached[neighbour] = true
				count = count + 1
				queue[#queue + 1] = neighbour
			end
		end
	end
	local remaining = 0
	for other in pairs(set) do
		if other ~= tree.root then
			remaining = remaining + 1
		end
	end
	if count ~= remaining then
		return nil, "Other allocated nodes depend on that node: refund the nodes further out first."
	end
	return true
end

function R.formatGold(n)
	local s = tostring(math.floor(tonumber(n) or 0))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

return ChaosRespecCore
