-- The class lanes on the client (pure Lua, no engine calls; tested by treelanes_test.lua). treedata/classlanes.lua
-- (server/tools/gen_class_lanes.lua) re-skins plain nodes for one class: same place, other stats. TreeLanes.apply merges
-- them into the nodes as node[<variant key>] = {customStats, icon, name} like the keystones' per-class tables, so the
-- tooltip, the search, the bonus sums and the refund box read the class's own stats AND a name that fits them.
--
-- The name: a re-skinned node used to keep the name of its own stats ("Pyre Litany", holy damage, gave a Beastmaster
-- physical damage; "Speed" gave a Berserker strength; "Hawk's Malice", distance skill, gave a Lich magic level). Now a
-- lane node of a named node gets a name made from the class's stats ("Physical Damage and Vitality", "Strength",
-- "Critical Hits and Magic Level"); only the generic "Attribute" of the small nodes stays.
TreeLanes = {}

local ELEMENTS = {Physical = true, Fire = true, Ice = true, Energy = true, Earth = true, Death = true, Holy = true,
	Arcane = true, Water = true, Drown = true}
local LABELS = {
	strength = "Strength", dexterity = "Dexterity", intelligence = "Intelligence", vitality = "Vitality", spirit = "Spirit",
	wisdom = "Wisdom", incrementHealth = "Health Spells", multiIncrement = "All Damage",
	absorbAllElements = "Elemental Absorption", swordSkill = "Sword Skill", axeSkill = "Axe Skill", clubSkill = "Club Skill",
	distanceSkill = "Distance Skill", magicSkill = "Magic Level", shielding = "Shielding", craftingSkill = "Crafting Skill",
	herbalistSkill = "Herbalist Skill", woodcuttingSkill = "Woodcutting Skill", miningSkill = "Mining Skill",
	armorsmithSkill = "Armorsmith Skill", jewelsmithSkill = "Jewelsmith Skill", weaponsmithSkill = "Weaponsmith Skill",
	crit = "Critical Hits", lifeLeech = "Life Leech", manaLeech = "Mana Leech", speed = "Speed", experience = "Experience",
	loot = "Loot", rarityLoot = "Rarity Loot"
}

local function sortedKeys(t)
	local keys = {}
	for k in pairs(t) do
		keys[#keys + 1] = k
	end
	table.sort(keys, function(a, b)
		return tostring(a) < tostring(b)
	end)
	return keys
end

-- the group of one stat: stats of one group share one label ("Fire Damage & Absorption", "Critical Hits")
function TreeLanes.groupOf(stat)
	local e = stat:match("^increment(%u%l+)$")
	if e and ELEMENTS[e] then
		return "el" .. e
	end
	e = stat:match("^absorb(%u%l+)$")
	if e and ELEMENTS[e] then
		return "el" .. e
	end
	if stat == "incrementLifeDrain" or stat == "incrementManaDrain" then
		return "drain"
	end
	if stat == "absorbLife" or stat == "absorbMana" then
		return "drainAbsorb"
	end
	if stat:match("^criticalHit") then
		return "crit"
	end
	if stat:match("^lifeLeech") then
		return "lifeLeech"
	end
	if stat:match("^manaLeech") then
		return "manaLeech"
	end
	if stat == "shieldingSkill" or stat == "skillShield" then
		return "shielding"
	end
	return stat
end

local function humanize(stat)
	local s = stat:gsub("(%l)(%u)", "%1 %2")
	return (s:gsub("^%l", string.upper))
end

-- the label of a group, from the stats of it the node has
function TreeLanes.label(group, members)
	local e = group:match("^el(%u%l+)$")
	if e then
		local inc, abs = members["increment" .. e], members["absorb" .. e]
		if inc and abs then
			return e .. " Damage & Absorption"
		end
		return e .. (inc and " Damage" or " Absorption")
	end
	if group == "drain" then
		local life, mana = members.incrementLifeDrain, members.incrementManaDrain
		return (life and mana) and "Life & Mana Drain Damage" or (life and "Life Drain Damage" or "Mana Drain Damage")
	end
	if group == "drainAbsorb" then
		local life, mana = members.absorbLife, members.absorbMana
		return (life and mana) and "Drain Absorption" or (life and "Life Drain Absorption" or "Mana Drain Absorption")
	end
	return LABELS[group] or humanize(group)
end

-- the median of every plain stat over the tree's plain nodes (what "a lot" of a stat is): the order of a name's labels
function TreeLanes.norms(nodes)
	local values = {}
	for _, node in pairs(nodes) do
		if type(node) == "table" and node.customStats and not node.masteries and not node.hidden then
			for stat, v in pairs(node.customStats) do
				if type(v) == "number" and v > 0 then
					values[stat] = values[stat] or {}
					table.insert(values[stat], v)
				end
			end
		end
	end
	local norm = {}
	for stat, list in pairs(values) do
		table.sort(list)
		norm[stat] = list[math.floor((#list + 1) / 2)]
	end
	return norm
end

-- the groups of a stat table, strongest first (value against the stat's median; ties by label):
-- {{group = , label = , score = }, ...}
function TreeLanes.groups(stats, norm)
	local byGroup, order = {}, {}
	for _, stat in ipairs(sortedKeys(stats)) do
		local v = stats[stat]
		if type(v) == "number" and v > 0 then
			local g = TreeLanes.groupOf(stat)
			if not byGroup[g] then
				byGroup[g] = {group = g, members = {}, score = 0}
				order[#order + 1] = byGroup[g]
			end
			local entry = byGroup[g]
			entry.members[stat] = v
			local score = v / ((norm and norm[stat]) or v)
			if score > entry.score then
				entry.score = score
			end
		end
	end
	for _, entry in ipairs(order) do
		entry.label = TreeLanes.label(entry.group, entry.members)
	end
	table.sort(order, function(a, b)
		if a.score ~= b.score then
			return a.score > b.score
		end
		return a.label < b.label
	end)
	return order
end

-- the name made from a stat table: its strongest group, and the second one when there is one ("Physical Damage and
-- Vitality"); the tooltip lists every stat below it
function TreeLanes.name(stats, norm)
	local groups = TreeLanes.groups(stats, norm)
	if #groups == 0 then
		return nil
	end
	if #groups == 1 then
		return groups[1].label
	end
	return groups[1].label .. " and " .. groups[2].label
end

function TreeLanes.mainGroup(stats, norm)
	local groups = TreeLanes.groups(stats, norm)
	return groups[1] and groups[1].group or nil
end

-- the name a lane node shows for that class; nil = its own name ("Attribute", or the same name made from stats)
function TreeLanes.laneName(node, stats, norm)
	local own = node.name
	if own == nil or own == "Attribute" then
		return nil
	end
	local name = TreeLanes.name(stats, norm)
	if name == own then
		return nil
	end
	return name
end

-- merges the lanes ({[variant key] = {[node id] = stats}}) and their icons ({[variant key] = {[node id] = icon}}) into
-- the nodes. A node with its own table for that key (a keystone variant), a mastery and a node without stats keep theirs.
function TreeLanes.apply(nodes, lanes, icons)
	local norm = TreeLanes.norms(nodes)
	for key, lane in pairs(lanes or {}) do
		for id, stats in pairs(lane) do
			local node = nodes[id]
			if node and node.customStats and not node.masteries and node[key] == nil then
				node[key] = {customStats = stats, icon = icons and icons[key] and icons[key][id] or nil,
					name = TreeLanes.laneName(node, stats, norm)}
			end
		end
	end
	return nodes
end

-- the name a class sees on a node (its variant's, else the node's own)
function TreeLanes.displayName(node, key)
	local variant = key and node[key]
	if type(variant) == "table" and variant.name then
		return variant.name
	end
	return node.name
end
