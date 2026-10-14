TREE_DATA = {}

dofile("treedata/groups.lua")
dofile("treedata/nodes.lua")
dofile("treedata/icons.lua")
dofile("treedata/static.lua")
dofile("treedata/painted.lua") -- painted keystone and mastery icons (client/tools/gen_painted_icons.py)

function getTreeData()
	local data = {
		groups = getTreeGroups(),
		nodes = getTreeNodes(),
		icons = getTreeIcons(),
		static = getTreeStatic(),
		painted = getPaintedTreeIcons()
	}

	return data
end

return 