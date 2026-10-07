TREE_DATA = {}

dofile("treedata/groups.lua")
dofile("treedata/nodes.lua")
dofile("treedata/icons.lua")
dofile("treedata/static.lua")

function getTreeData()
	local data = {
		groups = getTreeGroups(),
		nodes = getTreeNodes(),
		icons = getTreeIcons(),
		static = getTreeStatic()
	}

	return data
end

return 