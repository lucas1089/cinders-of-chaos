-- Run from the server/ folder: luajit tests/passive_builds_test.lua (and lua5.3; CI runs both). Mock engine API.
-- The Auto build button of the passive tree (passive_builds_config.lua, passive_builds_core.lua, passive_builds.lua, the
-- generated passive_builds_data.lua and tools/gen_passive_builds.lua):
--   * every build of every class, against the real tree rules: known nodes, none twice, none of another class, the root
--     not in it, every node touching the start or an earlier node (so every prefix is legal), within the points a
--     character owns at the level cap, no priced keystone / mastery in a Focus build, Recommended builds walk to their
--     targets, 3 Recommended builds per class and the Focus builds the class has enough relevant nodes for;
--   * the texts: names, descriptions and stat labels have a pt-BR entry;
--   * the generator is deterministic (same tree and recipes give the same data file: CI also runs --check);
--   * the plan (Apply adds, Reset and apply starts over), the skipped reasons, the points limit, masteries;
--   * the opcode handlers: list, preview, apply and reset-and-apply with the respec price, refusals, the rate limit.
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

dofile("data/scripts/chaos/chaos_constants.lua")
dofile("data/scripts/chaos/classes.lua")
dofile("data/scripts/chaos/i18n_core.lua")
dofile("data/scripts/chaos/passivetree_stats_config.lua")
dofile("data/scripts/chaos/passivetree_stats_core.lua")
local cfg = dofile("data/scripts/chaos/passive_builds_config.lua")
dofile("data/scripts/chaos/passive_builds_core.lua")
local Core = PassiveBuildsCore
local tree = dofile("data/scripts/chaos/passivetree_data.lua")
local data = dofile("data/scripts/chaos/passive_builds_data.lua")
local statsCfg = ChaosPassiveStatsConfig
local pt = dofile("data/scripts/chaos/i18n_strings.lua")["pt-BR"]

local capPoints = math.floor((1000 - Chaos.passive.startLevel) / Chaos.passive.levelsPerPoint)
check(cfg.maxPoints == capPoints, "maxPoints is what the level cap gives (" .. capPoints .. ")")
check(data.maxPoints == cfg.maxPoints, "the data was generated for the same budget")

local function needsChoice(node)
	if node.m then return true end
	for _, stats in pairs(node.v or {}) do -- per-class keystones; the class lanes (plain nodes with v) are not a choice
		for stat in pairs(stats) do
			if stat:match("^ar%u") or stat:match("^ks%u") or stat:match("^ct%u") then return true end
		end
	end
	for stat in pairs(node.s or {}) do
		if stat:match("^ar%u") or stat:match("^ks%u") or stat:match("^ct%u") then return true end
	end
	return false
end

-- the flags a class gets from a node (its variant on 621 / 624, else its own stats) that the config tags for a theme
local function tagged(node, classKey, themeKey)
	local stats = (node.v and node.v[ChaosClasses.keystoneKey(Chaos.classes.ids[classKey])]) or node.s or {}
	for stat in pairs(stats) do
		for _, key in ipairs(cfg.keystoneThemes[stat] or {}) do
			if key == themeKey then return true end
		end
	end
	return false
end

-- ------------------------------------------------------------------------------------------------ every build
local classCount, buildCount = 0, 0
local focusPerClass = {}
for classKey, vocId in pairs(Chaos.classes.ids) do
	classCount = classCount + 1
	local builds = data.classes[classKey]
	check(builds ~= nil, classKey .. " has builds")
	local ids, roles, focus = {}, 0, 0
	for _, b in ipairs(builds or {}) do
		buildCount = buildCount + 1
		check(not ids[b.id] and #b.id <= 60 and b.id:match("^[%w_]+$"), classKey .. ": build id " .. b.id .. " is unique and tame")
		ids[b.id] = true
		check(b.kind == "role" or b.kind == "focus", b.id .. ": kind")
		if b.kind == "role" then roles = roles + 1 else focus = focus + 1 end
		check(#b.order > 0 and #b.order <= cfg.maxPoints, b.id .. ": " .. #b.order .. " nodes within the points of the cap")
		local taken, seen = {[tree.root] = true}, {}
		local ok = true
		for i, id in ipairs(b.order) do
			local node = tree.nodes[id]
			if not node or seen[id] or id == tree.root then
				ok = false
				check(false, b.id .. ": node " .. id .. " is unknown, twice or the root")
				break
			end
			seen[id] = true
			if node.c and not node.c[classKey] then
				ok = false
				check(false, b.id .. ": node " .. id .. " belongs to another class")
			end
			local touches = false
			for _, nb in ipairs(node.n) do touches = touches or taken[nb] end
			if not touches then
				ok = false
				check(false, b.id .. ": node " .. id .. " (#" .. i .. ") does not touch the start or an earlier node")
			end
			taken[id] = true
		end
		check(ok, b.id .. ": a legal path")
		-- masteries: only choices for mastery nodes of the build
		for id, choice in pairs(b.masteries) do
			local node = tree.nodes[id]
			check(seen[id] and node.m and choice >= 1 and choice <= #node.m, b.id .. ": mastery " .. id .. " choice " .. choice)
		end
		for _, id in ipairs(b.order) do
			if tree.nodes[id].m then
				check(b.masteries[id] ~= nil, b.id .. ": mastery node " .. id .. " has an effect")
			end
		end
		check(#b.top >= 1 and #b.top <= 3, b.id .. ": a summary")
		if b.kind == "focus" then
			-- a theme build never takes a priced keystone, a variant or a mastery unless the theme names it
			local theme
			for _, t in ipairs(cfg.themes) do if "focus_" .. t.key == b.id then theme = t end end
			check(theme ~= nil, b.id .. ": a theme of the config")
			for _, id in ipairs(b.order) do
				if needsChoice(tree.nodes[id]) then
					check(theme and ((theme.nodes and theme.nodes[id]) or tagged(tree.nodes[id], classKey, theme.key)),
						b.id .. ": flagged node " .. id .. " not named or tagged by the theme")
				end
			end
			if theme and theme.classes then
				local listed = false
				for _, key in ipairs(theme.classes) do listed = listed or key == classKey end
				check(listed, b.id .. ": theme limited to other classes")
			end
		end
		-- nothing the class never uses is the main stat of a build
		local info = PassiveStatsCore.classInfo(statsCfg, classKey)
		check(not info.bad[b.top[1][1]], b.id .. ": main stat " .. b.top[1][1] .. " is irrelevant for the class")
	end
	check(roles == 3, classKey .. ": 3 recommended builds (" .. roles .. ")")
	check(focus >= 8, classKey .. ": enough focus builds (" .. focus .. ")")
	focusPerClass[classKey] = focus
	-- the recommended builds walk to their targets: every target is in the build, before the fill
	for _, role in ipairs(cfg.roles[classKey] or {}) do
		local b = Core.find(data, classKey, classKey .. "_" .. role.id)
		check(b ~= nil, classKey .. "/" .. role.id .. " exists")
		if b then
			local pos = {}
			for i, id in ipairs(b.order) do pos[id] = i end
			for _, target in ipairs(role.targets) do
				check(pos[target] ~= nil, role.id .. ": target " .. target .. " is in the build")
			end
			check(cfg.kinds[role.kind] ~= nil, role.id .. ": a kind text")
		end
	end
end
-- every stat a node, a class lane or a mastery effect gives is scored (a label for the summary) or ignored on purpose;
-- a stat added to the tree later must be added to passive_builds_config.lua too
do
	local ignoredSet, unknown = {}, {}
	for _, stat in ipairs(cfg.ignored) do ignoredSet[stat] = true end
	local function scan(stats)
		for stat in pairs(stats or {}) do
			if not stat:match("^ar%u") and not stat:match("^ks%u") and not stat:match("^ct%u")
				and not ignoredSet[stat] and not cfg.statLabels[stat] then
				unknown[stat] = true
			end
		end
	end
	for _, node in pairs(tree.nodes) do
		scan(node.s)
		for _, stats in pairs(node.v or {}) do scan(stats) end
		for _, stats in pairs(node.m or {}) do scan(stats) end
	end
	for stat in pairs(unknown) do check(false, "tree stat " .. stat .. " has no label and is not ignored in passive_builds_config.lua") end
	check(cfg.caps.attackSpeed ~= nil, "attack speed has a cap")
end
check(classCount == 21 and buildCount > 350, classCount .. " classes, " .. buildCount .. " builds")
for classKey in pairs(cfg.roles) do
	check(Chaos.classes.ids[classKey] ~= nil, "recipes for a class that does not exist: " .. classKey)
end
-- a theme only some classes have
check(Core.find(data, "necromancer", "focus_summons") and not Core.find(data, "warrior", "focus_summons"), "the summons theme is for the summoners")

-- ------------------------------------------------------------------------------------------------ build variety (O442)
-- The Recommended builds are three different ways to play, not three stat fills, and the Auto build list reaches every
-- keystone a class may hold. A keystone is a node whose stats for the class (its variant on 621 / 624, else its own)
-- carry an ar* or ks* flag: the 38 keystones of the tree. The class notables (ct*) are not keystones.
local function keystoneFlag(node, classKey)
	local stats = (node.v and node.v[ChaosClasses.keystoneKey(Chaos.classes.ids[classKey])]) or node.s or {}
	for stat in pairs(stats) do
		if stat:match("^ar%u") or stat:match("^ks%u") then return stat end
	end
	return nil
end
local function keystonesOf(build, classKey)
	local list, set = {}, {}
	for _, id in ipairs(build.order) do
		local flag = keystoneFlag(tree.nodes[id], classKey)
		if flag then
			list[#list + 1] = id
			set[id] = flag
		end
	end
	table.sort(list)
	return list, set
end
-- Keystones left out of the Auto build list on purpose, with the reason (docs/BUILDS.md, the audit of 2026-11-09). Hollow Palm
-- (Hollow Vessel with Aether Edge) is not recommended by default: strong, owner 2026-11-09 keeps it as it is. They are
-- in no Recommended build and in no theme (keystoneThemes has no tag for them).
local deny = {
	arOpenHand = "fists for the loss of the weapon: -4% to +4% in the computed rows, a price for no gain",
	arAetherEdge = "6% of the shield as energy damage for 20% less health: +2% on one and five targets without Hollow Vessel",
	arHollowVessel = "health 100: against two monsters the shield never recharges, the pool is 51-56% smaller at level 1000 (measured)"
}
-- Keystones no Recommended build of the class holds, although a Focus build may: [class .. ":" .. flag] or [flag] for every
-- class that may hold it.
local roleAvoid = {
	arOpenHand = deny.arOpenHand, arAetherEdge = deny.arAetherEdge, arHollowVessel = deny.arHollowVessel,
	["elementalist:arCinderSigil"] = "Sigil of Cinders on an Elementalist: -2% on one and five targets for -20% of the other damage",
	["ranger:arSnarewright"] = "Seeker Mine and Detonate Mines are not on the Ranger line spell list on this base (O455 gives them back): no mine role yet",
	["deadeye:arSnarewright"] = "Seeker Mine and Detonate Mines are not on the Ranger line spell list on this base (O455 gives them back): no mine role yet",
	["beastmaster:arSnarewright"] = "Seeker Mine and Detonate Mines are not on the Ranger line spell list on this base (O455 gives them back): no mine role yet",
	["samurai:arContagion"] = "poison is a loss for the Samurai: measured 654 / 2218, flagged in docs/CLASSES.md",
	["samurai:ksBlackbloodCreed"] = "poison is a loss for the Samurai: measured 654 / 2218, flagged in docs/CLASSES.md",
	["samurai:ksViperVerdict"] = "poison is a loss for the Samurai: measured 654 / 2218, flagged in docs/CLASSES.md"
}
-- a kept anchor (the tank role of the survival model) may hold no keystone; every other role holds 1 to 3
local noKeystone = {templar_shield_wall = "the Templar's tank role stays as it was: the survival model takes the median of the role builds"}
local denyUsed, avoidChecks, coverageChecks, distinctChecks = {}, 0, 0, 0
for classKey in pairs(Chaos.classes.ids) do
	local inSomeBuild = {}
	local sets = {}
	for _, b in ipairs(data.classes[classKey]) do
		local list, set = keystonesOf(b, classKey)
		for id in pairs(set) do inSomeBuild[id] = true end
		if b.kind == "role" then
			sets[#sets + 1] = {id = b.id, key = table.concat(list, ","), count = #list}
			check(#list <= 3, b.id .. " holds " .. #list .. " keystones: a role names 1 to 3 (" .. table.concat(list, ",") .. ")")
			check(#list >= 1 or noKeystone[b.id] ~= nil, b.id .. " holds no keystone")
			for id, flag in pairs(set) do
				avoidChecks = avoidChecks + 1
				check(not roleAvoid[flag] and not roleAvoid[classKey .. ":" .. flag], b.id .. " holds " .. flag .. ", which is left out of the Recommended builds")
			end
		end
	end
	-- C1: no two of the three roles hold the same set of keystones at the full budget
	check(#sets == 3, classKey .. ": three roles")
	for i = 1, #sets do
		for j = i + 1, #sets do
			distinctChecks = distinctChecks + 1
			check(sets[i].key ~= sets[j].key, classKey .. ": " .. sets[i].id .. " and " .. sets[j].id .. " hold the same keystones {" .. sets[i].key .. "}")
		end
	end
	-- C2: every keystone the class may hold is in a Recommended or Focus build, unless denied
	for id, node in pairs(tree.nodes) do
		if not node.c or node.c[classKey] then
			local flag = keystoneFlag(node, classKey)
			if flag then
				if deny[flag] then
					denyUsed[flag] = true
					check(not inSomeBuild[id], classKey .. ": the denied keystone " .. flag .. " is in a build")
				else
					coverageChecks = coverageChecks + 1
					check(inSomeBuild[id], classKey .. ": the keystone " .. flag .. " (node " .. id .. ") is in no Recommended or Focus build")
				end
			end
		end
	end
end
for flag in pairs(deny) do check(denyUsed[flag], "the deny table names a keystone the tree has: " .. flag) end
check(coverageChecks >= 200 and distinctChecks == 63 and avoidChecks >= 90, "the variety guards ran: " .. coverageChecks .. " keystones, " .. distinctChecks .. " role pairs, " .. avoidChecks .. " role keystones")

-- ------------------------------------------------------------------------------------------------ the texts
local function hasPt(text, what)
	check(type(text) == "string" and pt[text] ~= nil and pt[text] ~= "", what .. " has a pt-BR: " .. tostring(text))
end
for _, theme in ipairs(cfg.themes) do
	hasPt(theme.name, "theme " .. theme.key)
	hasPt(theme.text, "theme text " .. theme.key)
end
for kind, text in pairs(cfg.kinds) do
	hasPt(text, "kind " .. kind)
end
local longestRoleText = 0
for classKey, roles in pairs(cfg.roles) do
	for _, role in ipairs(roles) do
		hasPt(role.name, "role " .. classKey .. "/" .. role.id)
		-- O442: the list shows the role's own line under its name (what it does and its price)
		check(type(role.text) == "string" and role.text:find("Price:", 1, true), "role " .. classKey .. "/" .. role.id .. " has a text that names its price")
		hasPt(role.text, "role text " .. classKey .. "/" .. role.id)
		longestRoleText = math.max(longestRoleText, #tostring(role.text))
	end
end
check(longestRoleText <= 170, "a role text is one line: the longest has " .. longestRoleText .. " characters")
for stat, label in pairs(cfg.statLabels) do
	hasPt(label[1], "label of " .. stat)
end

-- the menu: Recommended first, Focus by fit
local list = Core.list(data, cfg, statsCfg, "necromancer")
check(list[1].kind == "role" and list[3].kind == "role" and list[4].kind == "focus", "recommended first")
local prev = math.huge
for i = 4, #list do
	check(list[i].fitScore <= prev, "focus builds ordered by fit")
	prev = list[i].fitScore
end
local fits = 0
for _, b in ipairs(list) do fits = fits + (b.fit and 1 or 0) end
check(fits >= 2 and list[4].fit ~= nil, "the best focus builds of a class fit it (" .. tostring(list[4].name) .. ")")
check(Core.summary(cfg, {{"incrementDeath", 52}, {"speed", 3200}}, function(t) return t end) == "Death damage +52, Speed +320", "summary text")

-- ------------------------------------------------------------------------------------------------ the generator
PASSIVE_BUILDS_GEN_NO_MAIN = true
local Gen = dofile("tools/gen_passive_builds.lua")
local ctx = Gen.context(tree, cfg)
ctx.statsCfg = statsCfg
ctx.bad = {}
local a = Gen.grow(ctx, {weights = Gen.weights(cfg, cfg.themes[1], "warrior"), targets = {}, classKey = "warrior", lineKey = "warrior",
	variant = "knight", budget = 40})
local b2 = Gen.grow(ctx, {weights = Gen.weights(cfg, cfg.themes[1], "warrior"), targets = {}, classKey = "warrior", lineKey = "warrior",
	variant = "knight", budget = 40})
check(#a.order == 40 and table.concat(a.order, ",") == table.concat(b2.order, ","), "the generator is deterministic")
-- keystones tagged for a theme (Poison is earth): the Ninja's earth builds take the poison keystones, Contagion Rite
-- (the poison spread on a poisoned monster's death), Viper's Verdict and the Blackblood Creed, early enough for a real
-- character (owner report: the Poison build skipped them)
local function positionOf(build, id)
	for i, v in ipairs(build.order) do if v == id then return i end end
end
local ninjaEarth = Core.find(data, "ninja", "focus_earth")
local ninjaPlague = Core.find(data, "ninja", "ninja_plaguebearer")
check(ninjaEarth and ninjaPlague, "ninja has the earth focus and the Plaguebearer build")
for _, id in ipairs({107, 383, 624}) do
	local at = positionOf(ninjaEarth, id)
	check(at and at <= 100, "ninja earth focus takes poison keystone " .. id .. " within 100 points (at " .. tostring(at) .. ")")
	at = positionOf(ninjaPlague, id)
	check(at and at <= 60, "ninja Plaguebearer takes poison keystone " .. id .. " within 60 points (at " .. tostring(at) .. ")")
end
check(cfg.keystoneThemes.arContagion and cfg.keystoneThemes.arContagion[1] == "earth", "Contagion Rite is tagged earth")
-- without the tags the earth build skips all three (the report)
local noTags = {}
for k, v in pairs(cfg) do noTags[k] = v end
noTags.keystoneThemes = {}
local ctx0 = Gen.context(tree, noTags)
ctx0.statsCfg = statsCfg
ctx0.bad = {}
local earthTheme
for _, t in ipairs(cfg.themes) do if t.key == "earth" then earthTheme = t end end
local ninjaVariant = ChaosClasses.keystoneKey(Chaos.classes.ids.ninja)
local bare = Gen.grow(ctx0, {weights = Gen.weights(noTags, earthTheme, "thief"), nodeScores = Gen.themeNodeScores(earthTheme, "ninja", tree, noTags, ninjaVariant),
	targets = {}, classKey = "ninja", lineKey = "thief", variant = ninjaVariant, budget = cfg.maxPoints})
local bareHas = false
for _, id in ipairs(bare.order) do bareHas = bareHas or id == 107 or id == 383 or id == 624 end
check(not bareHas, "without keystoneThemes the earth build takes none of the poison keystones")

-- general: no build skips a keystone tagged for its theme (a Focus build of the theme, a Recommended build that fills
-- with it) when the class may hold the node: it is in the build, within the points of the cap
local tagChecks = 0
for classKey in pairs(Chaos.classes.ids) do
	for _, b in ipairs(data.classes[classKey]) do
		local themeKey = nil
		if b.kind == "focus" then
			themeKey = b.id:gsub("^focus_", "")
		else
			for _, role in ipairs(cfg.roles[classKey]) do
				if classKey .. "_" .. role.id == b.id then themeKey = role.fill end
			end
		end
		local inBuild = {}
		for _, id in ipairs(b.order) do inBuild[id] = true end
		-- a build that already holds the most keystones a character may (O447) leaves the other tagged ones out
		local atCap = ChaosPassiveTreeCore.countKeystones(tree, b.order) >= ChaosPassiveTreeCore.keystoneMax()
		for id, node in pairs(tree.nodes) do
			if not node.m and (not node.c or node.c[classKey]) and tagged(node, classKey, themeKey) then
				tagChecks = tagChecks + 1
				check(inBuild[id] or atCap, b.id .. " (" .. classKey .. ") skips the keystone " .. id .. " tagged for " .. themeKey)
			end
		end
	end
end
check(tagChecks >= 20, "the tags are checked on builds (" .. tagChecks .. ")")
local _, err = Gen.grow(ctx, {weights = {}, targets = {626}, classKey = "warrior", lineKey = "warrior", variant = "knight", budget = 10})
check(err and err:find("not a node of class"), "a target of another class is an error: " .. tostring(err))

-- ------------------------------------------------------------------------------------------------ plan
local build = Core.find(data, "warrior", "warrior_slayer")
local plan = Core.plan(tree, build, {classKey = "warrior", current = {}, points = 10})
check(#plan.added == 10 and #plan.removed == 0 and not plan.treeReset and plan.changed, "10 points take the first 10 nodes")
check(table.concat(plan.ids, ",") == table.concat(build.order, ",", 1, 10), "in the order of the build")
check(#plan.skipped == #build.order - 10 and plan.skipped[1].why == "points", "the rest is skipped for points")
-- on top of an existing tree: only the missing nodes, nothing taken back
local held = {build.order[2], build.order[1], 2}
plan = Core.plan(tree, build, {classKey = "warrior", current = held, points = 8})
check(#plan.ids == 8 and #plan.removed == 0 and not plan.treeReset, "Apply on top: no node is taken back")
local has = {}
for _, id in ipairs(plan.ids) do has[id] = true end
check(has[2] and has[build.order[1]] and has[build.order[2]], "the held nodes stay")
check(#plan.added == 5, "free points = 8 - 3 held: " .. #plan.added)
-- a held node that is part of the build is not counted twice
check(plan.kept[1] == held[1], "held nodes listed as kept")
-- reset: starts over, takes back what is outside the build
plan = Core.plan(tree, build, {classKey = "warrior", current = held, points = 8, reset = true})
check(#plan.ids == 8 and #plan.removed == 1 and plan.removed[1] == 2 and plan.treeReset, "Reset and apply takes node 2 back")
-- a reset that takes nothing back is not a reset
plan = Core.plan(tree, build, {classKey = "warrior", current = {build.order[1], build.order[2]}, points = 8, reset = true})
check(not plan.treeReset and #plan.ids == 8 and #plan.added == 6, "a reset that keeps everything costs nothing")
-- nothing to do
plan = Core.plan(tree, build, {classKey = "warrior", current = {build.order[1]}, points = 1})
check(not plan.changed and #plan.added == 0, "no free point: nothing changes")
plan = Core.plan(tree, build, {classKey = "warrior", current = {}, points = 0})
check(not plan.changed, "no points at all")
-- wrong class / unknown / disconnected nodes are skipped with their reasons
local bad = {id = "x", kind = "role", order = {2, 9999, 626, 11, 665}, masteries = {}, top = {}}
plan = Core.plan(tree, bad, {classKey = "warrior", current = {}, points = 50})
local why = {}
for _, s in ipairs(plan.skipped) do why[s.id] = s.why end
check(why[9999] == "unknown" and why[626] == "class" and why[665] == "class", "unknown and class skips")
check(#plan.added == 1 and plan.added[1] == 2, "node 11 is not connected without 9: " .. table.concat(plan.added, ","))
check(why[11] == "disconnected", "disconnected skip")
-- masteries: the build's choice for a new mastery node, the held choice stays
local m = {id = "m", kind = "role", order = {626, 627, 628, 665}, masteries = {[665] = 3}, top = {}}
plan = Core.plan(tree, m, {classKey = "ninja", current = {}, points = 10})
check(plan.masteries[665] == 3 and #plan.added == 4, "mastery choice from the build")
plan = Core.plan(tree, m, {classKey = "ninja", current = {626, 627, 628, 665}, currentMasteries = {[665] = 1}, points = 10, reset = true})
check(plan.masteries[665] == 1 and not plan.treeReset, "a held mastery keeps its choice")

-- ------------------------------------------------------------------------------------------------ keystone cap (O447)
-- No committed build holds more keystones than the cap, for any prefix (any point budget), Recommended builds hold 1 to 3.
-- The count is the tree core's: the same function the server checks a save, a plan, a code, a loadout with.
local PC = ChaosPassiveTreeCore
local ksMax = PC.keystoneMax()
check(ksMax == 3, "the owner decision of 2026-11-09: the cap is 3")
local ksBuilds, ksRoles, ksTop = 0, 0, 0
for classKey, list in pairs(data.classes) do
	for _, b in ipairs(list) do
		ksBuilds = ksBuilds + 1
		local running, seen = 0, {}
		for _, id in ipairs(b.order) do
			if PC.isKeystone(tree.nodes[id]) and not seen[id] then
				seen[id] = true
				running = running + 1
				check(running <= ksMax, classKey .. " " .. b.id .. " takes keystone " .. id .. " past the cap")
			end
		end
		check(PC.countKeystones(tree, b.order) == running, classKey .. " " .. b.id .. " counts the same both ways")
		ksTop = math.max(ksTop, running)
		if b.kind == "role" then
			ksRoles = ksRoles + 1
			-- O442: a Recommended build holds 1 to 3 keystones; the one named exception is the Templar tank, which holds none
			-- and is as it was (docs/BUILDS.md: 62 of the 63 builds hold one)
			local floor = b.id == "templar_shield_wall" and 0 or 1
			check(running >= floor and running <= 3, classKey .. " " .. b.id .. " (Recommended) holds " .. floor .. " to 3 keystones, not " .. running)
		end
	end
end
check(ksBuilds > 400 and ksRoles >= 60 and ksTop == 3, "the cap check saw every build: " .. ksBuilds .. " builds, " .. ksRoles .. " roles, most " .. ksTop)
-- the generator itself holds the cap: a theme that scores all four keystones of a Deadeye still stops at 3
do
	local ks = {561, 599, 621, 624}
	local scores = {}
	for _, id in ipairs(ks) do scores[id] = 50 end
	local st = Gen.grow(ctx, {weights = Gen.weights(cfg, cfg.themes[1], "ranger"), nodeScores = scores, targets = {},
		classKey = "deadeye", lineKey = "ranger", variant = "deadeye", budget = 248})
	check(st and PC.countKeystones(tree, st.order) == 3, "four wanted keystones: the build stops at 3: " .. tostring(st and PC.countKeystones(tree, st.order)))
	-- role targets over the cap are a config error, not a silent trim
	local _, capErr = Gen.grow(ctx, {weights = {}, targets = {561, 599, 621, 624}, classKey = "deadeye", lineKey = "ranger",
		variant = "deadeye", budget = 248})
	check(capErr and capErr:find("cap"), "targets over the cap are an error: " .. tostring(capErr))
end
-- Hollow Palm (Shadowfist with Hollow Vessel 96 and Aether Edge 362) holds 2 keystones and stays legal
do
	local function route(classKey, targets)
		local set, order, parent = {}, {}, {}
		local queue, head, seen = {tree.root}, 1, {[tree.root] = true}
		while head <= #queue do
			local cur = queue[head]; head = head + 1
			for _, nb in ipairs(tree.nodes[cur].n) do
				local node = tree.nodes[nb]
				if not seen[nb] and (not node.c or node.c[classKey]) and not PC.isKeystone(node) or (not seen[nb] and targets[nb]) then
					seen[nb] = true; parent[nb] = cur; queue[#queue + 1] = nb
				end
			end
		end
		for target in pairs(targets) do
			local id = target
			while id and id ~= tree.root do
				if not set[id] then set[id] = true; order[#order + 1] = id end
				id = parent[id]
			end
		end
		table.sort(order)
		return order
	end
	local ids = route("shadowfist", {[96] = true, [362] = true})
	check(PC.countKeystones(tree, ids) == 2, "Hollow Palm holds exactly 2 keystones: " .. PC.countKeystones(tree, ids))
	check(PC.checkKeystones(tree, ids) == true, "Hollow Palm is under the cap")
	local result = PC.validatePlan(tree, {}, {}, {nodes = ids}, {classKey = "shadowfist", points = 400,
		allowed = function(node, key) return not node.c or node.c[key] == true end})
	check(result and #result.added == #ids, "the Hollow Palm plan is accepted whole")
end
-- Apply on top of a tree that holds keystones: a build that would take the total past the cap is refused whole
do
	local held = {}
	local sorted = {}
	for _, id in ipairs(data.classes.warrior[1].order) do sorted[#sorted + 1] = id end
	local function firstWith(classKey, pred)
		for _, b in ipairs(data.classes[classKey]) do
			if pred(b) then return b end
		end
	end
	local three = firstWith("warrior", function(b) return PC.countKeystones(tree, b.order) == 3 end)
	local other = firstWith("warrior", function(b)
		if b == three then return false end
		local _, mine = PC.countKeystones(tree, b.order)
		local _, theirs = PC.countKeystones(tree, three and three.order or {})
		local have = {}
		for _, id in ipairs(theirs) do have[id] = true end
		for _, id in ipairs(mine) do if not have[id] then return true end end
		return false
	end)
	if three and other then
		local p1 = Core.plan(tree, three, {classKey = "warrior", current = {}, points = 400})
		check(not p1.overCap and p1.keystones == 3, "a 3 keystone build on a clean tree is legal")
		local p2 = Core.plan(tree, other, {classKey = "warrior", current = p1.ids, points = 800})
		check(p2.overCap and p2.capText == "You can hold at most 3 keystones. Refund one to take another.",
			"Apply on top of 3 keystones: a build with another keystone is refused whole (" .. p2.keystones .. ")")
		local p3 = Core.plan(tree, other, {classKey = "warrior", current = p1.ids, points = 800, reset = true})
		check(not p3.overCap, "Reset and apply starts from nothing and always fits")
	else
		check(false, "the test needs a warrior build with 3 keystones and another with a different one")
	end
end

-- ------------------------------------------------------------------------------------------------ into a loadout slot (O448)
-- pick: the build of the character's class; another class's id and unknown ids are refused with their reason
do
	check(Core.pick(data, "warrior", "warrior_slayer") == Core.find(data, "warrior", "warrior_slayer"), "pick: an own Recommended build")
	check(Core.pick(data, "warrior", "focus_damage") ~= nil, "pick: an own Focus build")
	local b, why = Core.pick(data, "warrior", "ranger_stormquiver")
	check(b == nil and why == "class", "pick: a build of another class is refused as class")
	b, why = Core.pick(data, "warrior", "focus_snares")
	check(b == nil and why == "class", "pick: a Focus theme the class does not have is refused as class")
	b, why = Core.pick(data, "warrior", "no_such_build")
	check(b == nil and why == "unknown", "pick: unknown id")
	for _, bad in ipairs({"", 5, {}, string.rep("x", 61)}) do
		b, why = Core.pick(data, "warrior", bad)
		check(b == nil and why == "unknown", "pick: a malformed id is unknown")
	end
	b, why = Core.pick(data, nil, "warrior_slayer")
	check(b == nil and why == "class", "pick: no class of the character refuses a real build")
end
-- planSlot: the tree part, cut to the points; the character's own tree is never read
do
	local slayer = Core.find(data, "warrior", "warrior_slayer")
	local sp, why = Core.planSlot(tree, slayer, {classKey = "warrior", points = 248})
	check(sp and #sp.ids == #slayer.order and sp.left == 0 and sp.keystones == 2, "planSlot: a legal build whole")
	sp = Core.planSlot(tree, slayer, {classKey = "warrior", points = 40})
	check(sp and #sp.ids == 40 and sp.left == #slayer.order - 40, "planSlot: cut to the points")
	local same = sp ~= nil
	for i = 1, 40 do
		same = same and sp.ids[i] == slayer.order[i]
	end
	check(same, "planSlot: the first 40 nodes in build order")
	sp, why = Core.planSlot(tree, slayer, {classKey = "warrior", points = 0})
	check(sp == nil and why == "empty", "planSlot: no points, nothing to write")
	sp, why = Core.planSlot(tree, slayer, {classKey = "ninja", points = 248})
	check(sp == nil and why == "class", "planSlot: a warrior build for a ninja is refused")
	sp, why = Core.planSlot(tree, Core.find(data, "ranger", "ranger_stormquiver"), {classKey = "warrior", points = 248})
	check(sp == nil and why == "class", "planSlot: a ranger build for a warrior is refused")
	local broken = {id = "x", kind = "role", order = {slayer.order[1], 9999, slayer.order[2]}, masteries = {}, top = {}}
	sp, why = Core.planSlot(tree, broken, {classKey = "warrior", points = 248})
	check(sp == nil and why == "class", "planSlot: an unknown node makes the build illegal")
	-- four keystones: refused whole, with the tree's text, and nothing trimmed
	local function route(classKey, targets)
		local parent, queue, head, seenIds, index = {}, {tree.root}, 1, {[tree.root] = true}, {[tree.root] = 0}
		while head <= #queue do
			local cur = queue[head]; head = head + 1
			for _, nb in ipairs(tree.nodes[cur].n) do
				local node = tree.nodes[nb]
				if not seenIds[nb] and (not node.c or node.c[classKey]) and (not PC.isKeystone(node) or targets[nb]) then
					seenIds[nb] = true; parent[nb] = cur; queue[#queue + 1] = nb; index[nb] = #queue
				end
			end
		end
		local set, list = {}, {}
		for target in pairs(targets) do
			local id = target
			while id and id ~= tree.root do
				if not set[id] then set[id] = true; list[#list + 1] = id end
				id = parent[id]
			end
		end
		table.sort(list, function(a, b) return index[a] < index[b] end)
		return list
	end
	local four = {id = "ranger_four", kind = "role", order = route("deadeye", {[561] = true, [599] = true, [621] = true, [624] = true}),
		masteries = {}, top = {}}
	check(PC.countKeystones(tree, four.order) == 4 and #four.order <= 248, "planSlot: the test build holds 4 keystones")
	local pl
	sp, why, pl = Core.planSlot(tree, four, {classKey = "deadeye", points = 248})
	check(sp == nil and why == "cap" and pl.capText == "You can hold at most 3 keystones. Refund one to take another.",
		"planSlot: 4 keystones are refused with the cap text")
	-- cut before the fourth keystone it fits: the cap counts what the slot would hold
	local three = {id = "ranger_three", kind = "role", masteries = {}, top = {}, order = {}}
	local seen3 = 0
	for _, id in ipairs(four.order) do
		if PC.isKeystone(tree.nodes[id]) then
			seen3 = seen3 + 1
			if seen3 == 4 then break end
		end
		three.order[#three.order + 1] = id
	end
	sp = Core.planSlot(tree, three, {classKey = "deadeye", points = 248})
	check(sp and sp.keystones == 3, "planSlot: 3 keystones are legal")
	-- masteries: a mastery node of the build takes the build's choice
	local ninjaBuild = {id = "m", kind = "role", order = {626, 627, 628, 665}, masteries = {[665] = 3}, top = {}}
	sp = Core.planSlot(tree, ninjaBuild, {classKey = "ninja", points = 10})
	check(sp and sp.masteries[665] == 3, "planSlot: the build's mastery choice")
end
-- every committed build of every class is a legal slot at the points of the audit's cuts (23, 73, 123, 248)
do
	local bad = 0
	for classKey, list in pairs(data.classes) do
		for _, b in ipairs(list) do
			for _, points in ipairs({23, 73, 123, 248}) do
				local sp, why = Core.planSlot(tree, b, {classKey = classKey, points = points})
				if not sp then bad = bad + 1; print("planSlot refused " .. classKey .. " " .. b.id .. " at " .. points .. ": " .. tostring(why)) end
			end
		end
	end
	check(bad == 0, "planSlot: every build is legal at every cut of the starter guide")
end

-- ------------------------------------------------------------------------------------------------ handlers
local events = {}
local function object(name)
	local o = {}
	return setmetatable(o, {__index = function(t, k)
		if k == "register" then return function() if name then events[name] = o end return true end end
		return function() return true end
	end})
end
CreatureEvent = function(name) return object(name) end
GlobalEvent = function(name) return object(name) end
function addEvent() return 1 end
local rows, inserts = {}, {}
db = {escapeString = function(s) return "'" .. tostring(s) .. "'" end, asyncQuery = function() end,
	query = function(q)
		local p, nodes = q:match("INSERT INTO `[%w_]+` %(`player_id`, `preset`, `name`, `nodes`%) VALUES %(%d+, (%d+), '[^']*', '([^']*)'%)")
		if p then
			inserts[#inserts + 1] = {preset = tonumber(p), nodes = nodes}
			local found
			for _, row in ipairs(rows) do if row.preset == tonumber(p) then row.nodes = nodes; found = true end end
			if not found then rows[#rows + 1] = {preset = tonumber(p), name = "Preset " .. p, nodes = nodes} end
		end
		return true
	end}
Chaos = nil
dofile("data/scripts/chaos/chaos_constants.lua")
local sent = {}
Chaos.decode = function(b) return b end
Chaos.send = function(player, opcode, action, data) sent[#sent + 1] = {action = action, data = data}; return true end
Chaos.select = function(q)
	if q:find("SELECT `preset`, `name`, `nodes`", 1, true) then
		local out = {}
		for _, row in ipairs(rows) do out[#out + 1] = {preset = row.preset, name = row.name, nodes = row.nodes} end
		return out
	end
	return {}
end
local clock = 1000000
os.mtime = function() return clock end
dofile("data/scripts/chaos/ratelimit.lua")
dofile("data/scripts/chaos/passive_builds.lua")
dofile("data/scripts/chaos/passivetree.lua")
ChaosClassTree.write = function() end
local ext = events.ChaosPassiveTreeExtended
local paid, used = {}, 0
ChaosRespec = {nodeCost = function() return 9000 end, sendInfo = function() end, freeText = function() return nil end,
	fullCost = function(player) return player.free and 0 or 125000 end, useFree = function() used = used + 1 end,
	pay = function(player, cost) if cost <= player.gold then player.gold = player.gold - cost; paid[#paid + 1] = cost; return true end return false end}
ChaosRespecCore = {formatGold = function(v) return tostring(v) end}
local messages = {}
local p = {gold = 0, voc = 12, level = 500, storage = {}} -- a Ninja: (500 - 8) / 4 = 123 points
function p:getGuid() return 1 end
function p:getId() return 1 end
function p:getLevel() return self.level end
function p:getStorageValue(k) return self.storage[k] or -1 end
function p:setStorageValue(k, v) self.storage[k] = v end
function p:getVocation() local id = self.voc; return {getId = function() return id end} end
function p:sendExtendedOpcode() return true end
function p:registerEvent() end
function p:sendTextMessage(_, text) messages[#messages + 1] = text end
local OP = ChaosOpcodes.passivetree
local function call(action, data)
	clock = clock + 2000
	inserts, sent = {}, {}
	ext.onExtendedOpcode(p, OP, {action = action, data = data})
	local out = {}
	for _, s in ipairs(sent) do out[s.action] = out[s.action] or s.data; out[#out + 1] = s end
	return out
end

rows = {}
local res = call("autobuildList")
local lists = {}
for _, s in ipairs(res) do if s.action == "autobuildList" then lists[s.data.group] = s.data end end
check(lists.role and #lists.role.builds == 3 and lists.focus and #lists.focus.builds >= 8, "list: two groups")
check(lists.role.owned == 123 and lists.role.held == 0 and lists.role.free == 123 and lists.role.cap == 248, "list: points")
local first = lists.role.builds[1]
check(first.id:match("^ninja_") and first.name ~= "" and first.text ~= "" and first.summary ~= "" and first.points > 100, "list: a role entry")
check(lists.focus.builds[1].fit ~= nil or lists.focus.builds[2].fit ~= nil, "list: focus entries carry the fit")
for _, g in pairs(lists) do
	for _, b in ipairs(g.builds) do
		check(b.id:match("^ninja_") or b.id:match("^focus_"), "list: no build of another class: " .. b.id)
	end
end

-- preview
res = call("autobuildPreview", {build = "ninja_twin_fangs"})
local pv = res.autobuildPreview
check(pv and pv.build == "ninja_twin_fangs" and #pv.add.nodes == 123 and pv.add.added == 123 and pv.reset.removed == 0, "preview: an empty tree")
res = call("autobuildPreview", {build = "warrior_slayer"})
check(res.autobuildError and not res.autobuildPreview, "preview: a build of another class is refused")
res = call("autobuildPreview", {build = 5})
check(res.autobuildError, "preview: a bad id")
res = call("autobuildPreview", {})
check(res.autobuildError, "preview: no id")
check(call("autobuildPreview", {build = "warrior_slayer"}).autobuildError.build == "warrior_slayer", "preview: the error names the asked build")

-- every preview request is answered (the client waited for good when one was dropped): a second preview inside the
-- preview limit gets autobuildError {retry}; a preview right after an Apply is not refused by the Apply's limit
clock = clock + 2000
sent = {}
ext.onExtendedOpcode(p, OP, {action = "autobuildPreview", data = {build = "ninja_twin_fangs"}})
clock = clock + 60 -- inside the preview limit and inside the generic 200 ms per-action limit (O560)
ext.onExtendedOpcode(p, OP, {action = "autobuildPreview", data = {build = "ninja_phantom", seq = 7}})
check(#sent == 2 and sent[1].action == "autobuildPreview" and sent[2].action == "autobuildError" and sent[2].data.retry == true
	and sent[2].data.build == "ninja_phantom", "preview: too fast is answered with retry, even inside the generic limit")
check(sent[2].data.seq == 7 and sent[2].data.wait == cfg.previewRateMs, "preview: the refusal echoes the request number and says how long to wait")
check(cfg.previewRateMs <= 200, "preview: the limit is short (O560)")
clock = clock + cfg.previewRateMs
ext.onExtendedOpcode(p, OP, {action = "autobuildPreview", data = {build = "ninja_phantom", seq = 8}})
check(sent[#sent].action == "autobuildPreview" and sent[#sent].data.seq == 8 and sent[#sent].data.build == "ninja_phantom",
	"preview: the pick after the wait is answered with its own build and number")
-- the last of several quick picks is the one the server answers last, with its own number
clock = clock + 2000
sent = {}
for i, id in ipairs({"ninja_twin_fangs", "ninja_phantom", "ninja_twin_fangs"}) do
	clock = clock + 20
	ext.onExtendedOpcode(p, OP, {action = "autobuildPreview", data = {build = id, seq = 100 + i}})
end
check(#sent == 3 and sent[3].data.seq == 103 and sent[3].data.build == "ninja_twin_fangs", "preview: every quick pick is answered, in order, with its number")
-- another autobuild action refused by the generic limit is answered, not dropped
clock = clock + 2000
sent = {}
ext.onExtendedOpcode(p, OP, {action = "autobuildList", data = {}})
local before = #sent
clock = clock + 20
ext.onExtendedOpcode(p, OP, {action = "autobuildList", data = {}})
check(sent[#sent].action == "autobuildError" and #sent == before + 1, "autobuild: a request refused by the generic limit gets an answer")
check(ChaosPassiveBuilds.seqOf({seq = "x"}) == nil and ChaosPassiveBuilds.seqOf({seq = -1}) == nil and ChaosPassiveBuilds.seqOf({seq = 5.9}) == 5
	and ChaosPassiveBuilds.seqOf(nil) == nil, "preview: the request number is a small integer or nothing")
clock = clock + 2000
sent = {}
ext.onExtendedOpcode(p, OP, {action = "autobuildApply", data = {build = "ninja_twin_fangs", mode = "bogus"}})
clock = clock + 300
ext.onExtendedOpcode(p, OP, {action = "autobuildPreview", data = {build = "ninja_twin_fangs"}})
check(sent[#sent].action == "autobuildPreview", "preview: answered right after an Apply")
-- a Lua error while making the preview is answered too
local realPlan = Core.plan
Core.plan = function() error("boom") end
local realPrint = print
print = function() end
res = call("autobuildPreview", {build = "ninja_twin_fangs"})
print = realPrint
Core.plan = realPlan
check(res.autobuildError and res.autobuildError.build == "ninja_twin_fangs" and not res.autobuildPreview, "preview: an error is answered")

-- the owner's case: a Ranger with 32 points, all spent on the start of Sharpshooter (248 points); the preview answers
local ranger = {}
for i = 1, 32 do ranger[i] = Core.find(data, "ranger", "ranger_sharpshooter").order[i] end
rows = {{preset = 1, name = "Preset 1", nodes = table.concat(ranger, ",")}}
p.voc, p.level = Chaos.classes.ids.ranger, 8 + 32 * 4
res = call("autobuildPreview", {build = "ranger_sharpshooter"})
pv = res.autobuildPreview
check(pv and pv.owned == 32 and pv.held == 32 and pv.add.added == 0 and pv.add.skipped == 216 and pv.add.other == 0 and #pv.add.nodes == 32,
	"preview: Sharpshooter with 32 points, none free")
check(pv and pv.wanted == 248 and pv.reset.removed == 0, "preview: Sharpshooter's reset side")
-- with another build held, Reset and apply takes it back
local other = Core.find(data, "ranger", "focus_mana").order
local held2 = {}
for i = 1, 32 do held2[i] = other[i] end
rows = {{preset = 1, name = "Preset 1", nodes = table.concat(held2, ",")}}
res = call("autobuildPreview", {build = "ranger_sharpshooter"})
check(res.autobuildPreview and res.autobuildPreview.reset.removed > 0, "preview: another build held, reset takes it back")

-- every preview of every class fits one extended opcode message (8192 bytes; the tree's listener does not join parts)
local function enc(v)
	if type(v) == "table" then
		local parts = {}
		if #v > 0 or next(v) == nil then
			for _, x in ipairs(v) do parts[#parts + 1] = enc(x) end
			return "[" .. table.concat(parts, ",") .. "]"
		end
		for k, x in pairs(v) do parts[#parts + 1] = string.format("%q:%s", tostring(k), enc(x)) end
		return "{" .. table.concat(parts, ",") .. "}"
	elseif type(v) == "string" then
		return string.format("%q", v)
	end
	return tostring(v)
end
rows = {}
local biggest = 0
for classKey, vocId in pairs(Chaos.classes.ids) do
	p.voc, p.level = vocId, 1000
	for _, b in ipairs(data.classes[classKey] or {}) do
		res = call("autobuildPreview", {build = b.id})
		local size = res.autobuildPreview and #enc({action = "autobuildPreview", data = res.autobuildPreview}) or math.huge
		biggest = math.max(biggest, size)
	end
end
check(biggest < Chaos.extendedOpcodeMax, "every preview fits one message: biggest " .. biggest .. " bytes")
p.voc, p.level = 12, 500

-- apply on an empty tree
res = call("autobuildApply", {build = "ninja_twin_fangs", mode = "add", cost = 0})
check(res.autobuildApplied and #res.autobuildApplied.applied == 123, "apply: 123 nodes")
check(#inserts == 1 and #Core.plan(tree, {order = {}}, {classKey = "ninja", current = {}, points = 0}).ids == 0, "apply: one insert")
local saved = {}
for id in inserts[1].nodes:gmatch("%d+") do saved[#saved + 1] = tonumber(id) end
check(#saved >= 123 and #paid == 0, "apply: saved, nothing paid")
-- the saved tree is legal by the tree's own rules
local okIds = ChaosPassiveTree.internal.validateNodes(p, saved)
check(okIds ~= nil, "apply: the saved tree passes validateNodes")
check(res.sendNodes and res.sendPoints, "apply: the client is sent the tree and the points")
-- no free points now
res = call("autobuildApply", {build = "ninja_twin_fangs", mode = "add", cost = 0})
check(res.autobuildError and #inserts == 0, "apply: nothing to do the second time")
-- another build on top: no free point, nothing changes and nothing is taken
p.level = 700 -- 173 points: 50 free
res = call("autobuildApply", {build = "ninja_phantom", mode = "add", cost = 0})
check(res.autobuildApplied and #res.autobuildApplied.removed == 0, "apply on top: nothing taken back")
local after = {}
for id in inserts[1].nodes:gmatch("%d+") do after[tonumber(id)] = true end
local lost = 0
for _, id in ipairs(saved) do if not after[id] then lost = lost + 1 end end
check(lost == 0, "apply on top: every old node is still there")
-- reset and apply: the price, the check, the refusal without gold
p.gold = 1000
res = call("autobuildApply", {build = "ninja_phantom", mode = "reset", cost = 125000})
check(res.autobuildError and #inserts == 0 and p.gold == 1000, "reset: not enough gold, nothing changes")
p.gold = 200000
res = call("autobuildApply", {build = "ninja_phantom", mode = "reset", cost = 1})
check(res.autobuildError and p.gold == 200000, "reset: the price rose since the preview")
res = call("autobuildApply", {build = "ninja_phantom", mode = "reset", cost = 125000})
check(res.autobuildApplied and p.gold == 75000 and paid[#paid] == 125000 and used == 1, "reset: paid with the respec price and the free reset used")
check(#res.autobuildApplied.removed > 0 and #inserts == 1, "reset: the nodes outside the build are listed")
-- a reset that takes nothing back is free
res = call("autobuildApply", {build = "ninja_phantom", mode = "reset", cost = 0})
check(res.autobuildError, "reset: already the build, nothing to do")
-- bad requests
res = call("autobuildApply", {build = "ninja_phantom", mode = "bogus"})
check(res.autobuildError, "apply: bad mode")
res = call("autobuildApply", {build = "lich_rot_curser", mode = "add"})
check(res.autobuildError, "apply: another class's build")
res = call("autobuildApply", "x")
check(res.autobuildError, "apply: malformed")
-- rate limit: two applies inside a second, the second is refused
clock = clock + 2000
inserts, sent = {}, {}
p.level = 900
ext.onExtendedOpcode(p, OP, {action = "autobuildApply", data = {build = "ninja_phantom", mode = "add", cost = 0}})
local errors = 0
clock = clock + 300 -- past the generic 200 ms per-action limit, inside the build limit's second
ext.onExtendedOpcode(p, OP, {action = "autobuildApply", data = {build = "ninja_phantom", mode = "add", cost = 0}})
for _, s in ipairs(sent) do if s.action == "autobuildError" then errors = errors + 1 end end
check(#inserts == 1 and errors == 1, "the second apply inside a second is refused")

-- into a loadout slot (O448): two more actions of the same opcode, wired to the loadouts' own functions (their rules are
-- tested above and in loadouts_test.lua). Every request is answered; a refusal carries the slot and the build.
do
	ChaosLoadouts = nil
	res = call("autobuildSlots")
	check(res.autobuildError and not res.autobuildSlots, "slots: without the loadouts the request is still answered")
	res = call("autobuildSaveSlot", {build = "ninja_twin_fangs", slot = 1})
	check(res.autobuildError and not res.autobuildSlotSaved, "save to a slot: without the loadouts it is refused")
	local seen, stateSent = nil, 0
	ChaosLoadouts = {
		slotChoices = function(player)
			return {slots = {{slot = 1, empty = true, locked = false, active = false}}, limit = 5, max = 8, level = player:getLevel(), minLevel = 15}
		end,
		saveBuild = function(player, slot, build, confirm)
			seen = {slot = slot, build = build, confirm = confirm}
			if slot == 2 and not confirm then
				return false, "Slot 2 already holds Old. Confirm to replace its passive tree.", {confirm = true, name = "Old"}
			elseif slot == 99 or slot < 1 then
				return false, "That loadout slot does not exist."
			end
			return true, "Saved Twin Fangs in loadout slot " .. slot .. ": 5 passive nodes.", {"3 more nodes of the build need more points."}
		end,
		sendState = function() stateSent = stateSent + 1 end
	}
	res = call("autobuildSlots")
	check(res.autobuildSlots and res.autobuildSlots.limit == 5 and #res.autobuildSlots.slots == 1 and res.autobuildSlots.level == p.level,
		"slots: the choices of the loadouts")
	res = call("autobuildSaveSlot", {build = "ninja_twin_fangs", slot = 1})
	local saved = res.autobuildSlotSaved
	check(saved and saved.slot == 1 and saved.build == "ninja_twin_fangs" and saved.message:find("Saved Twin Fangs", 1, true)
		and saved.lines[1] and seen.confirm == false and stateSent == 1, "save to a slot: saved, the loadouts window told")
	res = call("autobuildSaveSlot", {build = "ninja_twin_fangs", slot = 2})
	check(res.autobuildError and res.autobuildError.needConfirm == true and res.autobuildError.name == "Old" and res.autobuildError.slot == 2
		and not res.autobuildSlotSaved and seen.confirm == false, "save to a slot: a held slot asks to confirm")
	res = call("autobuildSaveSlot", {build = "ninja_twin_fangs", slot = 2, confirm = true})
	check(res.autobuildSlotSaved and seen.confirm == true, "save to a slot: confirmed")
	res = call("autobuildSaveSlot", {build = "ninja_twin_fangs", slot = "2", confirm = "yes"})
	check(res.autobuildError and seen.confirm == false, "save to a slot: only the boolean true confirms")
	res = call("autobuildSaveSlot", {build = "ninja_twin_fangs", slot = 99})
	check(res.autobuildError and res.autobuildError.message == "That loadout slot does not exist." and not res.autobuildError.needConfirm,
		"save to a slot: a refusal is the loadouts' text")
	res = call("autobuildSaveSlot", {build = "ninja_twin_fangs", slot = 1e300})
	check(res.autobuildError and seen.slot == 0, "save to a slot: an absurd slot number is a plain 0, refused by the rules")
	res = call("autobuildSaveSlot", "x")
	check(res.autobuildError, "save to a slot: malformed")
	res = call("autobuildSaveSlot", {build = {}, slot = 1})
	check(seen.build == nil, "save to a slot: a malformed build id reaches the rules as nil")
	-- the limit: two requests inside a second, the second is refused and answered
	clock = clock + 2000
	sent = {}
	ext.onExtendedOpcode(p, OP, {action = "autobuildSaveSlot", data = {build = "ninja_twin_fangs", slot = 1}})
	clock = clock + 300
	ext.onExtendedOpcode(p, OP, {action = "autobuildSaveSlot", data = {build = "ninja_twin_fangs", slot = 1}})
	check(#sent >= 2 and sent[#sent].action == "autobuildError" and sent[#sent].data.slot == 1, "save to a slot: too fast is answered")
	ChaosLoadouts = nil
end

if failures > 0 then
	error(failures .. " of " .. checks .. " checks failed")
end
print("passive_builds_test: " .. checks .. " checks OK")
