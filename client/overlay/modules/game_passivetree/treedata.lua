TREE_DATA = {}

dofile("treedata/groups.lua")
dofile("treedata/nodes.lua")
dofile("treedata/icons.lua")
dofile("treedata/static.lua")
dofile("treedata/classlanes.lua") -- per-class stats of plain nodes (server/tools/gen_class_lanes.lua)
dofile("treedata/painted.lua") -- painted keystone and mastery icons (client/tools/gen_painted_icons.py)

-- the class lanes: a plain node gives a class other stats than its own (the same ones the server uses: its `v`), written as
-- node[<variant key>] = {customStats} like the keystones' per-class tables (setNodeTooltip, the bonus sums and the search
-- read node[vocation].customStats)
local function applyClassLanes(nodes)
	local icons = getClassLaneIcons()
	for key, lane in pairs(getClassLanes()) do
		for id, stats in pairs(lane) do
			local node = nodes[id]
			if node and node.customStats and not node.masteries and node[key] == nil then
				node[key] = {customStats = stats, icon = icons[key] and icons[key][id] or nil}
			end
		end
	end
	return nodes
end

function getTreeData()
	local data = {
		groups = getTreeGroups(),
		nodes = applyClassLanes(getTreeNodes()),
		icons = getTreeIcons(),
		static = getTreeStatic(),
		painted = getPaintedTreeIcons()
	}

	return data
end

return 