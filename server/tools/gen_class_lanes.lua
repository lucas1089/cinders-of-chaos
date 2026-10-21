-- Regenerates the class lanes of the passive tree: client/overlay/modules/game_passivetree/treedata/classlanes.lua.
-- Run from the server/ folder:
--   luajit tools/gen_class_lanes.lua            write the file, print the before / after report
--   luajit tools/gen_class_lanes.lua --check    exit 1 when the file differs (CI); lua5.3 gives the same bytes
-- Then regenerate the tree data: lua5.3 ../server/tools/gen_passivetree_data.lua (it merges the lanes into `v`).
--
-- What a lane is: the tree is one graph shared by 21 classes, so the plain nodes on the way to a class's keystones were
-- often useless to it (a Necromancer crossed axe and club nodes to reach its own notables). A lane re-skins a plain node
-- FOR ONE CLASS: same place, same point cost, same id, other stat (a stat of the same family the class lists as primary
-- or secondary, value scaled by the median of the two stats). Flag nodes (keystones, class and archetype nodes),
-- masteries and nodes that already have a per-class variant are never touched.
--
-- Rules (config: ChaosPassiveStatsConfig.paths): for every target (a keystone or notable the class can reach) the
-- shortest legal route from the start must be free of irrelevant nodes and at least `goalShare` relevant (the test
-- tests/passivetree_paths_test.lua requires `minShare`). Irrelevant nodes on a route are always re-skinned; neutral
-- ones only until the share reaches the goal. Deterministic: no random, sorted iteration.
--
-- Mystic and Elementalist share one variant key (ChaosClasses.keystoneKey): their lanes are one table built for both.
package.path = "tools/?.lua;" .. package.path

local Lanes = dofile("tools/passivetree_lanes_lib.lua")
local OUT = "../client/overlay/modules/game_passivetree/treedata/classlanes.lua"
local NODES = "../client/overlay/modules/game_passivetree/treedata/nodes.lua"

local Gen = {}

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

local function setup()
	local n = 0
	if not rawget(_G, "Chaos") then
		setmetatable(_G, {__index = function(t, k)
			if type(k) == "string" and k:match("^[A-Z_0-9]+$") then
				n = n + 1
				rawset(t, k, n)
				return n
			end
		end})
		dofile("data/scripts/chaos/chaos_constants.lua")
	end
	if not ChaosClasses then
		dofile("data/scripts/chaos/classes.lua")
	end
	if not PassiveStatsCore then
		dofile("data/scripts/chaos/passivetree_stats_core.lua")
	end
end

-- the stat families: a replacement comes from the same family first
local FAMILY = {}
for _, s in ipairs({"strength", "intelligence", "dexterity", "vitality", "spirit", "wisdom"}) do FAMILY[s] = "attr" end
for _, s in ipairs({"swordSkill", "axeSkill", "clubSkill", "distanceSkill", "magicSkill", "shieldingSkill", "skillShield"}) do
	FAMILY[s] = "skill"
end
for _, s in ipairs({"craftingSkill", "armorsmithSkill", "weaponsmithSkill", "jewelsmithSkill", "miningSkill", "woodcuttingSkill",
	"herbalistSkill"}) do FAMILY[s] = "craft" end
for _, s in ipairs({"criticalHitChance", "criticalHitAmount"}) do FAMILY[s] = "crit" end
for _, s in ipairs({"lifeLeechChance", "lifeLeechAmount"}) do FAMILY[s] = "leech" end
for _, s in ipairs({"manaLeechChance", "manaLeechAmount"}) do FAMILY[s] = "mleech" end
for _, s in ipairs({"speed", "loot", "rarityLoot", "experience"}) do FAMILY[s] = "misc" end
local function familyOf(stat)
	if FAMILY[stat] then
		return FAMILY[stat]
	end
	if stat:match("^absorb") then
		return "abs"
	end
	if stat:match("^increment") or stat == "multiIncrement" then
		return "inc"
	end
	return "misc"
end
-- when the family has nothing the class likes: next families to try
local NEXT = {
	attr = {"attr", "skill", "inc"}, skill = {"skill", "attr", "inc"}, craft = {"attr", "skill", "inc"},
	inc = {"inc", "attr", "skill"}, abs = {"abs", "attr", "inc"}, crit = {"crit", "leech", "inc", "attr"},
	leech = {"leech", "crit", "abs", "attr"}, mleech = {"mleech", "leech", "inc", "attr"}, misc = {"attr", "skill", "inc"}
}
local SUFFIX = function(stat) return stat:match("Chance$") and "Chance" or (stat:match("Amount$") and "Amount" or nil) end

-- the plain stats of the tree: {stat -> median value}, and the set of nodes a lane may re-skin
function Gen.universe(tree)
	local values, plain = {}, {}
	for _, id in ipairs(sortedKeys(tree.nodes)) do
		local node = tree.nodes[id]
		if not Lanes.isFlagNode(node) and node.s then
			plain[id] = true
			for stat, v in pairs(node.s) do
				if type(v) == "number" and v > 0 then
					values[stat] = values[stat] or {}
					values[stat][#values[stat] + 1] = v
				end
			end
		end
	end
	local norm = {}
	for stat, list in pairs(values) do
		table.sort(list)
		norm[stat] = list[math.floor((#list + 1) / 2)]
	end
	return {norm = norm, plain = plain}
end

-- candidate stats per family for a class: primary first (twice as often), then secondary
local function candidates(info, uni, neutral)
	local byFamily = {}
	local function add(stat, times)
		if uni.norm[stat] and not neutral[stat] then
			local f = familyOf(stat)
			byFamily[f] = byFamily[f] or {}
			for _ = 1, times do
				table.insert(byFamily[f], stat)
			end
		end
	end
	for _, stat in ipairs(info.primary) do add(stat, 2) end
	for _, stat in ipairs(info.secondary) do add(stat, 1) end
	return byFamily
end

local function scaled(uni, from, to, value)
	return math.max(1, math.floor(value * uni.norm[to] / uni.norm[from] + 0.5))
end

-- the replacement of one stat of node `id`; nil when the class has nothing for it. `bud` = {supply, cap}: a stat that
-- the tree has few of (skills, crit, leech) is not handed out beyond its cap, so a lane moves the relevant stats around
-- without growing what one class can collect.
local function replace(info, uni, byFamily, id, index, stat, value, bud)
	local fam = familyOf(stat)
	local suffix = SUFFIX(stat)
	for _, f in ipairs(NEXT[fam] or {"attr"}) do
		local list = byFamily[f]
		if list and #list > 0 then
			local pool = list
			if suffix and (f == "crit" or f == "leech" or f == "mleech") then
				pool = {}
				for _, s in ipairs(list) do
					if SUFFIX(s) == suffix then pool[#pool + 1] = s end
				end
			end
			local start = id * 7 + index * 3
			for k = 0, #pool - 1 do
				local to = pool[(start + k) % #pool + 1]
				local v = scaled(uni, stat, to, value)
				if (bud.supply[to] or 0) + v <= (bud.cap[to] or math.huge) then
					return to, v
				end
			end
		end
	end
end

-- a node's stats as a lane would have them: bad stats always replaced, neutral ones when `neutral` is true
local function reskin(info, uni, byFamily, id, stats, includeNeutral, bud)
	local out, index = {}, 0
	local pending = {}
	for _, stat in ipairs(sortedKeys(stats)) do
		index = index + 1
		local value = stats[stat]
		local keep = info.tag[stat] ~= nil or ((not info.bad[stat]) and (not includeNeutral))
		if keep then
			out[stat] = (out[stat] or 0) + value
		else
			local to, v = replace(info, uni, byFamily, id, index, stat, value, bud)
			if to then
				out[to] = (out[to] or 0) + v
				bud.supply[to] = (bud.supply[to] or 0) + v -- counted at once so two stats of one node cannot both fit
				pending[#pending + 1] = {to, v}
			else
				out[stat] = (out[stat] or 0) + value
			end
		end
	end
	for _, p in ipairs(pending) do
		bud.supply[p[1]] = bud.supply[p[1]] - p[2]
	end
	return out
end

-- targets: every named (not "Attribute") node of the client tree that exists in the server tree
function Gen.targets(tree)
	dofile(NODES)
	local nodes = getTreeNodes()
	local out = {}
	for id = 1, #nodes do
		local nd = nodes[id]
		if nd and not nd.hidden and not nd.isStartNode and nd.name and nd.name ~= "Attribute" and tree.nodes[id] then
			out[#out + 1] = id
		end
	end
	return out
end

-- classes that share a variant key (Mystic and Elementalist) share one lane: a stat is wanted only when EVERY class of the
-- key tags it (primary only when all call it primary) and unwanted when any of them lists it as irrelevant
local function mergedInfo(cfg, keys)
	local infos = {}
	for _, classKey in ipairs(keys) do
		infos[#infos + 1] = PassiveStatsCore.classInfo(cfg, classKey)
	end
	if #infos == 1 then
		return infos[1]
	end
	local first = infos[1]
	local out = {primary = {}, secondary = {}, irrelevant = {}, tag = {}, bad = {}, raw = first.raw}
	for _, stat in ipairs(first.primary) do
		local all, primary = true, true
		for _, info in ipairs(infos) do
			all = all and info.tag[stat] ~= nil
			primary = primary and info.tag[stat] == "primary"
		end
		if all then
			out.tag[stat] = primary and "primary" or "secondary"
		end
	end
	for _, stat in ipairs(first.secondary) do
		local all = true
		for _, info in ipairs(infos) do
			all = all and info.tag[stat] ~= nil
		end
		if all and not out.tag[stat] then
			out.tag[stat] = "secondary"
		end
	end
	for _, info in ipairs(infos) do
		for stat in pairs(info.bad) do
			out.bad[stat] = true
		end
	end
	for _, stat in ipairs(first.primary) do
		if out.tag[stat] == "primary" then out.primary[#out.primary + 1] = stat
		elseif out.tag[stat] then out.secondary[#out.secondary + 1] = stat end
	end
	for _, stat in ipairs(first.secondary) do
		if out.tag[stat] and not (out.tag[stat] == "primary") then
			local listed = false
			for _, x in ipairs(out.secondary) do listed = listed or x == stat end
			if not listed then out.secondary[#out.secondary + 1] = stat end
		end
	end
	for stat in pairs(out.tag) do
		out.bad[stat] = nil
	end
	return out
end

-- Lanes set by hand, applied after the generated ones (same id, same cost). 2026-10-22: the Thief and Ninja collected far
-- more dexterity than its cap (80 points) from the path nodes alone, so the most taken 10-point Attribute nodes that the
-- lanes had turned into dexterity give all-element resistance instead (absorbAllElements, a secondary stat of both).
Gen.OVERRIDES = {
	thief = {[130] = {absorbAllElements = 2}, [132] = {absorbAllElements = 2}, [157] = {absorbAllElements = 2},
		[173] = {absorbAllElements = 2}, [238] = {absorbAllElements = 2}},
	ninja = {[130] = {absorbAllElements = 2}, [132] = {absorbAllElements = 2}, [238] = {absorbAllElements = 2}}
}

-- lanes[variantKey] = {[node id] = stats}; report[classKey] = {before = summary, after = summary, changed = n}
function Gen.build(tree, cfg, targets)
	setup()
	local uni = Gen.universe(tree)
	local neutral = {}
	for _, stat in ipairs(PassiveStatsCore.expand(cfg, cfg.neutral)) do
		neutral[stat] = true
	end
	local goal, minShare = cfg.paths.goalShare, cfg.paths.minShare
	local ids = Chaos.classes.ids
	local groups, order = {}, {}
	for _, classKey in ipairs(sortedKeys(ids)) do
		local vk = ChaosClasses.keystoneKey(ids[classKey])
		if not groups[vk] then
			groups[vk] = {}
			order[#order + 1] = vk
		end
		table.insert(groups[vk], classKey)
	end
	local lanes, report = {}, {}
	for _, vk in ipairs(order) do
		local keys = groups[vk]
		local info = mergedInfo(cfg, keys)
		local byFamily = candidates(info, uni, neutral)
		local lane = {}
		local before = {}
		-- what the class can collect of each plain stat now, and the most a lane may leave it
		local bud = {supply = {}, cap = {}}
		local total = {}
		for id, node in pairs(tree.nodes) do
			if node.s and not Lanes.isFlagNode(node) then
				local mayHold = false
				for _, classKey in ipairs(keys) do
					mayHold = mayHold or Lanes.allowed(node, classKey)
				end
				for stat, v in pairs(node.s) do
					if type(v) == "number" then
						total[stat] = (total[stat] or 0) + v
						if mayHold then bud.supply[stat] = (bud.supply[stat] or 0) + v end
					end
				end
			end
		end
		for stat, v in pairs(total) do
			local scarce = ({skill = true, crit = true, leech = true, mleech = true})[familyOf(stat)]
			bud.cap[stat] = math.ceil(v * (scarce and cfg.paths.supplyFactor or cfg.paths.supplyFactorCommon))
		end
		local function commit(id, stats)
			local old = lane[id] or tree.nodes[id].s
			for stat, v in pairs(old) do bud.supply[stat] = (bud.supply[stat] or 0) - v end
			for stat, v in pairs(stats) do bud.supply[stat] = (bud.supply[stat] or 0) + v end
			lane[id] = stats
		end
		for _, classKey in ipairs(keys) do
			before[classKey] = Lanes.summary(Lanes.routes(tree, classKey, info, vk, targets, nil), targets, minShare)
		end
		for pass = 1, 8 do
			local changed = false
			for _, classKey in ipairs(keys) do
				local routes = Lanes.routes(tree, classKey, info, vk, targets, lane)
				local order2 = {}
				for _, t in ipairs(targets) do
					if routes[t] then order2[#order2 + 1] = t end
				end
				table.sort(order2, function(a, b)
					if routes[a].len ~= routes[b].len then return routes[a].len < routes[b].len end
					return a < b
				end)
				for _, t in ipairs(order2) do
					local r = routes[t]
					if r.bad > 0 or r.rel / r.len < goal then
						local kinds = {}
						for _, id in ipairs(r.path) do
							kinds[#kinds + 1] = {id = id, kind = Lanes.kind(tree.nodes[id], id, info, vk, lane)}
						end
						local rel = r.rel
						for _, k in ipairs(kinds) do
							if k.kind == "bad" and uni.plain[k.id] then
								local node = tree.nodes[k.id]
								commit(k.id, reskin(info, uni, byFamily, k.id, lane[k.id] or node.s, false, bud))
								if Lanes.kind(node, k.id, info, vk, lane) == "rel" then rel = rel + 1 end
								changed = true
							end
						end
						for _, k in ipairs(kinds) do
							if rel / r.len >= goal then break end
							if k.kind == "neutral" and uni.plain[k.id] then
								local node = tree.nodes[k.id]
								local stats = reskin(info, uni, byFamily, k.id, lane[k.id] or node.s, true, bud)
								local saved = lane[k.id]
								lane[k.id] = stats
								if Lanes.kind(node, k.id, info, vk, lane) == "rel" then
									lane[k.id] = saved
									commit(k.id, stats)
									rel = rel + 1
									changed = true
								else
									lane[k.id] = saved
								end
							end
						end
					end
				end
			end
			if not changed then break end
		end
		-- a lane equal to the node's own stats is no lane
		for id, stats in pairs(lane) do
			local same, own = true, tree.nodes[id].s
			for stat, v in pairs(stats) do if own[stat] ~= v then same = false end end
			for stat, v in pairs(own) do if stats[stat] ~= v then same = false end end
			if same then lane[id] = nil end
		end
		for id, stats in pairs(Gen.OVERRIDES[vk] or {}) do
			lane[id] = stats
		end
		lanes[vk] = lane
		for _, classKey in ipairs(keys) do
			local after = Lanes.summary(Lanes.routes(tree, classKey, info, vk, targets, lane), targets, minShare)
			local count = 0
			for _ in pairs(lane) do count = count + 1 end
			report[classKey] = {before = before[classKey], after = after, changed = count, key = vk}
		end
	end
	return lanes, report, order
end

function Gen.render(lanes, icons)
	local out = {
		"-- GENERATED by server/tools/gen_class_lanes.lua. Do not edit; run it again after changing the tree or the lists in",
		"-- server/data/scripts/chaos/passivetree_stats_config.lua. The class lanes: for one class (its variant key), a plain",
		"-- node gives these stats instead of its own (same place, same cost). treedata.lua merges them into the nodes as",
		"-- node[<key>] = {customStats}, tools/gen_passivetree_data.lua into the server tree's `v`. Hand-set lanes: Gen.OVERRIDES.",
		"function getClassLanes()",
		"\treturn {"
	}
	local keys = sortedKeys(lanes)
	for ki, key in ipairs(keys) do
		out[#out + 1] = string.format("\t\t%s = {", key)
		local ids = {}
		for id in pairs(lanes[key]) do ids[#ids + 1] = id end
		table.sort(ids)
		for i, id in ipairs(ids) do
			local parts = {}
			for _, stat in ipairs(sortedKeys(lanes[key][id])) do
				parts[#parts + 1] = string.format("%s=%d", stat, lanes[key][id][stat])
			end
			out[#out + 1] = string.format("\t\t\t[%d]={%s}%s", id, table.concat(parts, ","), i < #ids and "," or "")
		end
		out[#out + 1] = "\t\t}" .. (ki < #keys and "," or "")
	end
	out[#out + 1] = "\t}"
	out[#out + 1] = "end"
	out[#out + 1] = ""
	out[#out + 1] = "-- the icon a lane node shows for that class (a plain stat icon of treedata/icons.lua)"
	out[#out + 1] = "function getClassLaneIcons()"
	out[#out + 1] = "\treturn {"
	local ikeys = sortedKeys(icons)
	for ki, key in ipairs(ikeys) do
		out[#out + 1] = string.format("\t\t%s = {", key)
		local ids = {}
		for id in pairs(icons[key]) do ids[#ids + 1] = id end
		table.sort(ids)
		for i, id in ipairs(ids) do
			out[#out + 1] = string.format("\t\t\t[%d]=%q%s", id, icons[key][id], i < #ids and "," or "")
		end
		out[#out + 1] = "\t\t}" .. (ki < #ikeys and "," or "")
	end
	out[#out + 1] = "\t}"
	out[#out + 1] = "end"
	out[#out + 1] = ""
	return table.concat(out, "\n")
end

-- the icon of a re-skinned node: the one of its strongest stat (strength relative to the stat's median), only for nodes
-- whose own icon is a plain stat icon (the painted notable and keystone icons stay)
local ICON = {strength = "strength", dexterity = "dexterity", intelligence = "intelligence", vitality = "life", spirit = "mana",
	wisdom = "baseStat", incrementPhysical = "physicalDamage", incrementFire = "fireDamage", incrementIce = "coldDamage",
	incrementEnergy = "lightningDamage", incrementEarth = "earthDamage", incrementDeath = "deathDamage",
	incrementHoly = "holyDamage", incrementArcane = "arcaneDamage", incrementWater = "waterDamage",
	incrementHealth = "healthDamage", incrementLifeDrain = "lifeManaDrain", incrementManaDrain = "lifeManaDrain",
	multiIncrement = "multiStat", absorbAllElements = "multiStat", absorbLife = "absorbLife", absorbMana = "absorbMana",
	speed = "speed", loot = "loot", rarityLoot = "rarityLoot", experience = "experience"}
local function iconOf(uni, stats)
	local best, bestScore
	for _, stat in ipairs(sortedKeys(stats)) do
		local score = stats[stat] / (uni.norm[stat] or 1)
		if not bestScore or score > bestScore then
			best, bestScore = stat, score
		end
	end
	if not best then return nil end
	return ICON[best] or best
end
function Gen.icons(tree, lanes, uni)
	dofile(NODES)
	local nodes = getTreeNodes()
	dofile("../client/overlay/modules/game_passivetree/treedata/icons.lua")
	local known = getTreeIcons()
	local out = {}
	for key, lane in pairs(lanes) do
		out[key] = {}
		for id, stats in pairs(lane) do
			local own = nodes[id] and nodes[id].icon or ""
			if not (own:match("^nt") or own:match("^ks") or own:match("^ar%u") or own:match("^ms") or own:match("^cs")) then
				local icon = iconOf(uni, stats)
				if icon and known[icon] and icon ~= own then out[key][id] = icon end
			end
		end
	end
	return out
end

Gen.sortedKeys = sortedKeys

local function readFile(path)
	local f = io.open(path, "rb")
	if not f then return nil end
	local s = f:read("*a")
	f:close()
	return s
end

function Gen.main(args)
	setup()
	local tree = dofile("data/scripts/chaos/passivetree_data.lua")
	-- gen_passivetree_data.lua stores the lanes in `v` of plain nodes (the only other `v` nodes are the flagged keystones 621
	-- and 624): take them off again, the lanes are built from the tree as it is without them
	for _, node in pairs(tree.nodes) do
		if node.v and not Lanes.isFlagNode(node) then node.v = nil end
	end
	local cfg = dofile("data/scripts/chaos/passivetree_stats_config.lua")
	local targets = Gen.targets(tree)
	local lanes, report, order = Gen.build(tree, cfg, targets)
	local text = Gen.render(lanes, Gen.icons(tree, lanes, Gen.universe(tree)))
	if args[1] == "--check" then
		if readFile(OUT) ~= text then
			io.stderr:write("classlanes.lua is stale: run luajit tools/gen_class_lanes.lua\n")
			os.exit(1)
		end
		print("classlanes.lua is up to date")
		return
	end
	local f = assert(io.open(OUT, "wb"))
	f:write(text)
	f:close()
	local ids = Chaos.classes.ids
	local names = Gen.sortedKeys(ids)
	table.sort(names, function(a, b) return ids[a] < ids[b] end)
	print(string.format("%-12s %7s %12s %12s %8s", "class", "targets", "before avg", "after avg", "lane"))
	for _, k in ipairs(names) do
		local r = report[k]
		print(string.format("%-12s %7d %11.0f%% %11.0f%% %8d   passing %d -> %d of %d", k, r.after.targets, r.before.avg * 100,
			r.after.avg * 100, r.changed, r.before.passing, r.after.passing, r.after.targets))
	end
end

if not rawget(_G, "CLASS_LANES_GEN_NO_MAIN") then
	Gen.main(arg or {})
end
return Gen
