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
					check(theme and theme.nodes and theme.nodes[id], b.id .. ": flagged node " .. id .. " not named by the theme")
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
check(classCount == 21 and buildCount > 350, classCount .. " classes, " .. buildCount .. " builds")
for classKey in pairs(cfg.roles) do
	check(Chaos.classes.ids[classKey] ~= nil, "recipes for a class that does not exist: " .. classKey)
end
-- a theme only some classes have
check(Core.find(data, "necromancer", "focus_summons") and not Core.find(data, "warrior", "focus_summons"), "the summons theme is for the summoners")

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
for classKey, roles in pairs(cfg.roles) do
	for _, role in ipairs(roles) do
		hasPt(role.name, "role " .. classKey .. "/" .. role.id)
	end
end
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

if failures > 0 then
	error(failures .. " of " .. checks .. " checks failed")
end
print("passive_builds_test: " .. checks .. " checks OK")
