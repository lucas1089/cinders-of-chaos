TREE_DATA = {}

dofile("treedata/groups.lua")
dofile("treedata/nodes.lua")
dofile("treedata/icons.lua")
dofile("treedata/static.lua")
dofile("treedata/classlanes.lua") -- per-class stats of plain nodes (server/tools/gen_class_lanes.lua)
dofile("treedata/painted.lua") -- painted keystone and mastery icons (client/tools/gen_painted_icons.py)

-- the class lanes: a plain node gives a class other stats than its own (the same ones the server uses: its `v`), merged
-- by treelanes.lua as node[<variant key>] = {customStats, icon, name} like the keystones' per-class tables (setNodeTooltip,
-- the bonus sums, the search and the refund box read node[vocation]); the name follows the class's stats
local function applyClassLanes(nodes)
	return TreeLanes.apply(nodes, getClassLanes(), getClassLaneIcons())
end

function getTreeData()
	local nodes = applyClassLanes(getTreeNodes())
	-- every link listed on both ends, as the server stores it (treeplan.lua TreePlan.linkBack)
	TreePlan.linkBack(nodes)
	local data = {
		groups = getTreeGroups(),
		nodes = nodes,
		icons = getTreeIcons(),
		static = getTreeStatic(),
		painted = getPaintedTreeIcons()
	}

	return data
end

return 