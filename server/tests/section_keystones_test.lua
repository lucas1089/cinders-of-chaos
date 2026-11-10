-- Run from the server/ folder: luajit tests/section_keystones_test.lua (and lua5.3; CI runs both). No engine.
-- The class sections of the Warrior, Ranger and Mystic lines (O449), the nine classes that had none:
--   * the pure rules of the six keystones (section_keystones_core.lua): Unbroken Line, Open Veins, Lone Mark, Wolfbond,
--     Convergence, Phantom Double (the engine glue against mocked creatures is in passivetree_keystones_test.lua);
--   * the numbers: every client tooltip (treedata/nodes.lua) states what section_keystones_config.lua and class_tree.lua use;
--   * the generated server data: the same shape as the four sections of the Thief, Necromancer, Monk and Templar lines (a start
--     node that is not a server node, three line nodes, two ascended paths of two notables and a keystone, one mastery), one
--     keystone of the "ascension" kind per ascended class, none for the base class, nothing for another line;
--   * the sizes: every number of a new node is at or below the median of its kind among the sections that existed, no new
--     node has a stat the stat help does not describe, every flag has a combat log label or a reason, and no existing node
--     was changed (the ids 1 to 672 are what they were: checked against the node list below).
local n = 0
setmetatable(_G, {__index = function(t, k)
	if type(k) == "string" and k:match("^[A-Z_0-9]+$") then n = n + 1; rawset(t, k, n); return n end
end})
local checks, failures = 0, 0
local function check(cond, label)
	checks = checks + 1
	if not cond then
		failures = failures + 1
		print("FAIL " .. label)
	end
end
local function eq(a, b, label) check(a == b, label .. ": " .. tostring(a) .. " ~= " .. tostring(b)) end

dofile("data/scripts/chaos/chaos_constants.lua")
dofile("data/scripts/chaos/classes.lua")
dofile("data/scripts/chaos/class_tree.lua")
dofile("data/scripts/chaos/passivetree_core.lua")
dofile("data/scripts/chaos/passivetree_stats_config.lua")
dofile("data/scripts/chaos/section_keystones_core.lua")
local SK, cfg, CT, Core = ChaosSectionKeystones, ChaosSectionKeystonesConfig, ChaosClassTree, ChaosPassiveTreeCore
local tree = dofile("data/scripts/chaos/passivetree_data.lua")
local labels = dofile("data/scripts/chaos/keystone_labels_config.lua")

-- ------------------------------------------------------------------------------------------------ pure rules
eq(#SK.FLAGS, 6, "six flags")
check(SK.holds({ksOpenVeins = 1}) and SK.holds({ksWolfbond = 1}) and not SK.holds({ksBulwark = 1}) and not SK.holds(nil), "holds")
local function near(a, b, label) check(math.abs(a - b) < 1e-9, label .. ": " .. a .. " ~= " .. b) end
near(SK.unbrokenFactor(0), 1, "Unbroken Line: nobody next to you")
near(SK.unbrokenFactor(1), 0.98, "one enemy")
near(SK.unbrokenFactor(4), 0.92, "four enemies: the most")
near(SK.unbrokenFactor(9), 0.92, "nine enemies: the same")
near(SK.unbrokenFactor(-3), 1, "a negative count is none")
near(SK.unbrokenPrice(), 0.95, "Unbroken Line price")
local tick, ticks, tickMs = SK.bleedOf(920)
eq(tick, 115, "Open Veins: 50% of 920 over 4 ticks"); eq(ticks, 4, "ticks"); eq(tickMs, 1000, "tick ms")
eq(SK.bleedOf(3), nil, "a hit too small to bleed"); eq(SK.bleedOf(-920), 115, "the sign of the hit does not matter")
near(SK.openVeinsPrice(), 0.92, "Open Veins price")
near(SK.loneMarkFactor(0), 1.12, "Lone Mark alone"); near(SK.loneMarkFactor(1), 0.92, "Lone Mark with one other"); near(SK.loneMarkFactor(7), 0.92, "crowd")
near(SK.wolfbondPrice(), 0.92, "Wolfbond price")
near(SK.convergenceFactor(0), 0.93, "Convergence alone"); near(SK.convergenceFactor(1), 1, "one other: neither")
near(SK.convergenceFactor(2), 1.12, "two others"); near(SK.convergenceFactor(10), 1.12, "ten others")
near(SK.phantomPrice(), 0.95, "Phantom Double price")
local state = {}
eq(SK.phantomStrike(state, 1000, 0, function() return 20 end), 600, "Phantom Double: the roll of 20 succeeds (20%)")
eq(SK.phantomStrike(state, 1000, 999, function() return 1 end), 0, "the cooldown")
eq(SK.phantomStrike(state, 1000, 1000, function() return 21 end), 0, "a roll of 21 fails")
eq(SK.phantomStrike(state, -1000, 1000, function() return 1 end), 600, "the cooldown is over, the sign does not matter")
-- crowd: the candidates within the radius, not the skipped one, not another floor
local pos = function(x, y, z) return {x = x, y = y, z = z or 7} end
local around = {{id = 1, pos = pos(10, 10)}, {id = 2, pos = pos(11, 10)}, {id = 3, pos = pos(12, 12)}, {id = 4, pos = pos(13, 10)},
	{id = 5, pos = pos(10, 11, 6)}}
eq(SK.crowd(around, pos(10, 10), 1, 2), 2, "crowd: 2 and 3, not 1 (skipped), 4 (3 away) or 5 (another floor)")
eq(SK.crowd(around, pos(10, 10), nil, 1), 2, "crowd: 1 and 2 within 1 sqm (nobody skipped)")
eq(SK.crowd(nil, pos(0, 0), nil, 2), 0, "crowd: none")
eq(SK.scale(-1000, 0.95), -950, "scale keeps the sign")

-- ------------------------------------------------------------------------------------------------ the config
local FLAGS = {ksUnbrokenLine = 679, ksOpenVeins = 682, ksLoneMark = 689, ksWolfbond = 692, ksConvergence = 699, ksPhantomDouble = 702}
for flag in pairs(FLAGS) do
	check(flag == "ksWolfbond" and CT.fx.ksWolfbond ~= nil or cfg[flag] ~= nil, flag .. " has its numbers")
end
check(CT.bit.ksWolfbond ~= nil, "Wolfbond has a bit of the class flag storage (the spells' Lua state reads it)")
check(#CT.keys < 31, "the class flags fit a 32-bit storage")
for flag in pairs(FLAGS) do
	check(flag == "ksWolfbond" or labels.flags[flag] ~= nil, flag .. " has a combat log label")
end
check(labels.flags.ksWolfbond == nil, "Wolfbond has none: its gain is in the wolves' hits (tester_keytree.py NO_PROBE says why)")
for _, p in ipairs({cfg.ksUnbrokenLine.price, cfg.ksOpenVeins.price, cfg.ksLoneMark.crowd, cfg.ksConvergence.alone, cfg.ksPhantomDouble.price,
		CT.fx.ksWolfbond.price}) do
	check(p < 1 and p >= 0.9 - 1e-9, "every price is a cut of 10% at most (" .. p .. ")")
end
for _, g in ipairs({cfg.ksLoneMark.alone, cfg.ksConvergence.bonus, 1 + CT.fx.ksWolfbond.bonus}) do
	check(g > 1 and g <= 1.20 + 1e-9, "every direct gain is 20% at most (" .. g .. ")")
end
-- sized under the signature keystones of the other lines (class_keystones_config.lua): bleed under Barbed Quiver's 60%
local ar = dofile("data/scripts/chaos/archetypes_config.lua")
check(cfg.ksOpenVeins.share <= ar.arBarbed.share, "Open Veins bleeds no more than Barbed Quiver")
check(cfg.ksOpenVeins.price >= ar.arBarbed.mainDamage, "and its price is no smaller")
local ck = dofile("data/scripts/chaos/class_keystones_config.lua")
check(cfg.ksPhantomDouble.chance * cfg.ksPhantomDouble.percent <= ck.ksShadowTwin.chance * ck.ksShadowTwin.percent,
	"Phantom Double is no stronger than Shadow Twin")
check(1 - SK.unbrokenFactor(cfg.ksUnbrokenLine.maxEnemies) <= CT.fx.ksImmovable.reduction + 1e-9, "Unbroken Line takes off no more than Immovable's base")

-- ------------------------------------------------------------------------------------------------ the generated data
local SECTIONS = {
	warrior = {first = 673, classes = {"warrior", "juggernaut", "berserker"}, a = "juggernaut", b = "berserker", ka = "ksUnbrokenLine", kb = "ksOpenVeins", mastery = 703},
	ranger = {first = 683, classes = {"ranger", "deadeye", "beastmaster"}, a = "deadeye", b = "beastmaster", ka = "ksLoneMark", kb = "ksWolfbond", mastery = 704},
	mystic = {first = 693, classes = {"mystic", "elementalist", "illusionist"}, a = "elementalist", b = "illusionist", ka = "ksConvergence", kb = "ksPhantomDouble", mastery = 705},
}
local rootLinks = {}
for _, id in ipairs(tree.nodes[tree.root].n) do rootLinks[id] = true end
for line, sec in pairs(SECTIONS) do
	local f = sec.first
	eq(tree.nodes[f], nil, line .. ": the start node is not a server node")
	eq(rootLinks[f + 1], true, line .. ": the first line node hangs on the root")
	for i = 2, 9 do eq(rootLinks[f + i], nil, line .. ": node " .. (f + i) .. " is not on the root") end
	for i = 1, 3 do
		for _, k in ipairs(sec.classes) do eq(tree.nodes[f + i].c[k], true, line .. " line node " .. (f + i) .. " " .. k) end
		local count = 0
		for _ in pairs(tree.nodes[f + i].c) do count = count + 1 end
		eq(count, 3, line .. " line node " .. (f + i) .. ": three classes")
	end
	for i = 4, 6 do
		eq(tree.nodes[f + i].c[sec.a], true, sec.a .. " path " .. (f + i)); eq(tree.nodes[f + i].c[sec.b], nil, sec.b .. " not on " .. (f + i))
		eq(tree.nodes[f + i + 3].c[sec.b], true, sec.b .. " path " .. (f + i + 3)); eq(tree.nodes[f + i + 3].c[sec.a], nil, sec.a .. " not on " .. (f + i + 3))
	end
	eq(tree.nodes[f + 6].s[sec.ka], 1, sec.a .. " keystone"); eq(#tree.nodes[f + 6].n, 1, "the keystone ends the path")
	eq(tree.nodes[f + 9].s[sec.kb], 1, sec.b .. " keystone"); eq(#tree.nodes[f + 9].n, 1, "the keystone ends the path")
	eq(Core.keystoneKind(tree.nodes[f + 6]), "ascension", sec.ka .. " is an ascension keystone")
	eq(Core.keystoneKind(tree.nodes[f + 9]), "ascension", sec.kb .. " is an ascension keystone")
	for _, i in ipairs({4, 5, 7, 8}) do eq(Core.keystoneKind(tree.nodes[f + i]), nil, "notable " .. (f + i) .. " is no keystone") end
	-- the mastery hangs on the third line node, like 665 to 668, with 3 or 4 effects
	local m = tree.nodes[sec.mastery]
	check(m and m.m and #m.m >= 3 and #m.m <= 4, line .. " mastery " .. sec.mastery .. " has 3 or 4 effects")
	eq(m.n[1], f + 3, line .. " mastery hangs on the third line node"); eq(#m.n, 1, "and nothing else")
	for _, k in ipairs(sec.classes) do eq(m.c[k], true, line .. " mastery for " .. k) end
	-- the three classes: a keystone and a path only for the ascended class
	for _, k in ipairs(sec.classes) do
		local ks = 0
		for id = f, f + 9 do
			local node = tree.nodes[id]
			if node and CT.allowed(node, k) then
				for stat in pairs(node.s or {}) do
					if stat:sub(1, 2) == "ks" then ks = ks + 1 end
				end
			end
		end
		eq(ks, k == line and 0 or 1, "keystones of " .. k .. " in its section")
		local held = 0 -- the nodes of the section the class may take: the line nodes, the mastery, and its own path
		for id = f + 1, f + 9 do if tree.nodes[id] and CT.allowed(tree.nodes[id], k) then held = held + 1 end end
		if CT.allowed(m, k) then held = held + 1 end
		eq(held, k == line and 4 or 7, k .. ": nodes of its section it may take (line nodes, mastery, its own path)")
	end
	-- the other lines may not take any node of it
	for other, osec in pairs(SECTIONS) do
		if other ~= line then
			for id = f + 1, f + 9 do
				for _, k in ipairs(osec.classes) do eq(CT.allowed(tree.nodes[id], k), false, k .. " may not take " .. id) end
			end
		end
	end
	for _, k in ipairs({"thief", "necromancer", "monk", "templar", "ninja", "lich", "shadowfist", "sentinel"}) do
		for id = f + 1, f + 9 do eq(CT.allowed(tree.nodes[id], k), false, k .. " may not take " .. id) end
	end
end
-- the keystones: 14 of the ascension kind, 44 in all; Mystic and Elementalist differ in their sections
local kinds, total = {}, 0
for _, node in pairs(tree.nodes) do
	local kind = Core.keystoneKind(node)
	if kind then kinds[kind] = (kinds[kind] or 0) + 1; total = total + 1 end
end
eq(kinds.ascension, 14, "14 class section keystones"); eq(kinds.archetype, 24, "24 archetype keystones"); eq(kinds.line, 4, "4 line keystones")
eq(kinds.pair, 2, "2 pair nodes"); eq(total, 44, "44 keystones in all")
local function reach(class)
	local list = {}
	for id = 673, 705 do
		local node = tree.nodes[id]
		if node and CT.allowed(node, class) then list[#list + 1] = id end
	end
	return table.concat(list, ",")
end
check(reach("mystic") ~= reach("elementalist"), "the Mystic and the Elementalist differ in their class sections")
check(reach("mystic") ~= reach("illusionist") and reach("elementalist") ~= reach("illusionist"), "and the Illusionist differs from both")
check(reach("juggernaut") ~= reach("berserker") and reach("deadeye") ~= reach("beastmaster"), "the ascended classes of the other two lines differ too")

-- nothing of the old tree changed: no node below 673 links a new node but the root (which gained the three first line nodes)
for id, node in pairs(tree.nodes) do
	if id < 673 and id ~= tree.root then
		for _, o in ipairs(node.n) do check(o < 673, "old node " .. id .. " links no new node (" .. o .. ")") end
	end
end
eq(#tree.nodes[tree.root].n, 13, "the root has its 7 neighbours and the first line node of each of the 6 sections (3 old, 3 new)") -- 2-7 and 6 more

-- ------------------------------------------------------------------------------------------------ the sizes
-- the number of a node: the sum of its stat values (walking speed counts 1 per 100: its unit is 1/10 of a point)
local function weight(stats)
	local sum = 0
	for stat, v in pairs(stats) do sum = sum + (stat == "speed" and v / 100 or v) end
	return sum
end
local function median(list)
	table.sort(list)
	return list[math.floor((#list + 1) / 2)]
end
local function hasFlag(stats)
	for stat in pairs(stats) do if stat:match("^c[ts]%u") or stat:match("^ks%u") or stat:match("^ar%u") then return true end end
	return false
end
local lineW, notableW, masteryW = {}, {}, {}
for _, f in ipairs({625, 635, 645, 655}) do
	for i = 1, 3 do lineW[#lineW + 1] = weight(tree.nodes[f + i].s) end
	for _, i in ipairs({4, 5, 7, 8}) do
		local s = tree.nodes[f + i].s
		if not hasFlag(s) then notableW[#notableW + 1] = weight(s) end
	end
end
for id = 665, 668 do for _, effect in ipairs(tree.nodes[id].m) do masteryW[#masteryW + 1] = weight(effect) end end
local lineMax, notableMax, masteryMax = median(lineW), median(notableW), median(masteryW)
print(string.format("medians of the sections that existed: line nodes %g, plain notables %g, mastery effects %g", lineMax, notableMax, masteryMax))
local statHelp = ChaosPassiveStatsConfig.stats
for line, sec in pairs(SECTIONS) do
	local f = sec.first
	for i = 1, 3 do
		check(weight(tree.nodes[f + i].s) <= lineMax, line .. " line node " .. (f + i) .. " is at or below the median of the line nodes")
	end
	for _, i in ipairs({4, 5, 7, 8}) do
		check(weight(tree.nodes[f + i].s) <= notableMax, line .. " notable " .. (f + i) .. " is at or below the median of the plain notables")
		check(not hasFlag(tree.nodes[f + i].s), line .. " notable " .. (f + i) .. " is plain tree stats (no new combat code)")
	end
	for _, effect in ipairs(tree.nodes[sec.mastery].m) do
		check(weight(effect) <= masteryMax, line .. " mastery effect is at or below the median of the mastery effects")
		for stat in pairs(effect) do check(statHelp[stat] ~= nil, "the stat help knows " .. stat) end
	end
	for id = f + 1, f + 8 do
		for stat in pairs(tree.nodes[id].s or {}) do
			if not hasFlag({[stat] = 1}) then check(statHelp[stat] ~= nil, "the stat help knows " .. stat .. " (node " .. id .. ")") end
		end
	end
end

-- ------------------------------------------------------------------------------------------------ the client tree
local nodesFile = "../client/overlay/modules/game_passivetree/treedata/nodes.lua"
local fh = io.open(nodesFile)
if not fh then
	print("(client tree not found: tooltip check skipped)")
else
	fh:close()
	dofile(nodesFile)
	local nodes = getTreeNodes()
	local function pct(x) return tostring(math.floor(x * 100 + 0.5)) .. "%" end
	local want = {
		[679] = {"2%", pct(cfg.ksUnbrokenLine.perEnemy), cfg.ksUnbrokenLine.maxEnemies .. " at most", pct(cfg.ksUnbrokenLine.perEnemy * cfg.ksUnbrokenLine.maxEnemies),
			pct(1 - cfg.ksUnbrokenLine.price) .. " less", cfg.ksUnbrokenLine.radius == 1 and "next to you" or "?"},
		[682] = {pct(cfg.ksOpenVeins.share), math.floor(cfg.ksOpenVeins.ticks * cfg.ksOpenVeins.tickMs / 1000) .. " s", pct(1 - cfg.ksOpenVeins.price) .. " less"},
		[689] = {cfg.ksLoneMark.radius .. " sqm", pct(cfg.ksLoneMark.alone - 1) .. " more", pct(1 - cfg.ksLoneMark.crowd) .. " less"},
		[692] = {pct(CT.fx.ksWolfbond.bonus) .. " more", pct(1 - CT.fx.ksWolfbond.price) .. " less"},
		[699] = {cfg.ksConvergence.others .. " or more", cfg.ksConvergence.radius .. " sqm", pct(cfg.ksConvergence.bonus - 1) .. " more", pct(1 - cfg.ksConvergence.alone) .. " less"},
		[702] = {cfg.ksPhantomDouble.chance .. "%", cfg.ksPhantomDouble.delayMs / 1000 .. " s", pct(cfg.ksPhantomDouble.percent), "once a second", pct(1 - cfg.ksPhantomDouble.price) .. " less"},
	}
	for id, needles in pairs(want) do
		local text = table.concat(nodes[id].stats, " ")
		for _, needle in ipairs(needles) do
			check(text:find(needle, 1, true) ~= nil, "node " .. id .. " tooltip lacks '" .. needle .. "': " .. text)
		end
	end
	for flag, id in pairs(FLAGS) do
		check(nodes[id].customStats[flag] == 1 and nodes[id].isKeystone and nodes[id].isDivine, id .. " " .. flag .. " is drawn as a keystone")
	end
	-- every class list and every link of the client matches the server data
	for id = 673, 705 do
		local cn, sn = nodes[id], tree.nodes[id]
		check(cn ~= nil, "client node " .. id)
		if cn and cn.isStartNode then
			eq(sn, nil, "start " .. id .. " is no server node")
		elseif cn and sn then
			for _, k in ipairs(cn.classes) do eq(sn.c[k], true, "client classes of " .. id .. ": " .. k) end
			local count = 0
			for _ in pairs(sn.c) do count = count + 1 end
			eq(count, #cn.classes, "the class count of " .. id)
			check(cn.line == "warrior" or cn.line == "ranger" or cn.line == "mystic", "the line of " .. id)
		end
	end
	-- the keystones are the ones the client marks isKeystone (44 in all), and the icons are cells that exist
	local keystones = 0
	for _, cn in pairs(nodes) do if cn.isKeystone then keystones = keystones + 1 end end
	eq(keystones, 44, "the client marks 44 keystones")
	dofile("../client/overlay/modules/game_passivetree/treedata/icons.lua")
	local icons = getTreeIcons()
	for id = 673, 705 do
		check(icons[nodes[id].icon] ~= nil, "node " .. id .. " icon " .. tostring(nodes[id].icon) .. " exists in icons.lua")
	end
end

if failures > 0 then
	error(failures .. " of " .. checks .. " checks failed")
end
print("section_keystones_test: " .. checks .. " checks ok")
