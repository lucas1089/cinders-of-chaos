-- Run from the server/ folder: luajit tests/passivetree_plan_test.lua (and lua5.3; CI runs both). Mock engine API.
-- The tree planner and the mastery nodes (passivetree_core.lua, passivetree.lua, passivetree_config.lua):
--   * the saved allocation text with mastery choices (old texts read as before), the mastery data of the tree;
--   * validatePlan: a valid plan, empty, malformed, oversize, unknown ids, the root, duplicates, already allocated,
--     another class's node (class sections and the ascended paths), over the points, disconnected, the mastery rules;
--   * checkMasteryChange;
--   * the opcode handlers: planApply saves the whole plan at once or nothing (planResult), the rate limit, masteryChoose
--     priced like a single-node refund, sendNodes carries the masteries, the bonuses use the chosen effect, a refund keeps
--     the other masteries, the inspect view;
--   * the loadouts tree text keeps the masteries;
--   * reworked nodes (passivetree_config.lua reworked): the core (reworkedSince, dropNodes) and the free refund at login.
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

dofile("data/scripts/chaos/passivetree_config.lua")
dofile("data/scripts/chaos/passivetree_core.lua")
local C = ChaosPassiveTreeCore
local tree = dofile("data/scripts/chaos/passivetree_data.lua")
local cfg = ChaosPassiveTreeConfig

-- ------------------------------------------------------------------------------------------------ saved text
local ids, m = C.parseAlloc("2,3,9")
check(#ids == 3 and ids[3] == 9 and next(m) == nil, "an old text reads as before")
ids, m = C.parseAlloc("2,3,9,665|665:2")
check(#ids == 4 and ids[4] == 665 and m[665] == 2, "a text with a mastery choice")
ids, m = C.parseAlloc("2,3|665:2,3:1")
check(#ids == 2 and m[665] == nil and m[3] == 1, "a choice of a node not in the list is dropped")
ids, m = C.parseAlloc("")
check(#ids == 0 and next(m) == nil, "empty text")
check(C.formatAlloc({9, 2, 665}, {[665] = 3}) == "2,9,665|665:3", "format sorts and appends the choices")
check(C.formatAlloc({9, 2}, {[665] = 3}) == "2,9", "no choice without its node (the old text exactly)")
check(C.formatAlloc({}, nil) == "", "empty")
local text = C.formatAlloc({626, 627, 628, 665}, {[665] = 4})
ids, m = C.parseAlloc(text)
check(#ids == 4 and m[665] == 4, "round trip")

-- ------------------------------------------------------------------------------------------------ mastery data
local masteryIds = {}
for id, node in pairs(tree.nodes) do
	if C.isMastery(node) then
		masteryIds[#masteryIds + 1] = id
		check(#node.m >= 2 and #node.m <= cfg.maxMasteryChoices, "mastery " .. id .. " has 2-4 effects")
		check(node.s == nil and node.v == nil, "mastery " .. id .. " has no own stats")
		check(node.c ~= nil, "mastery " .. id .. " belongs to a class line")
		for i, effect in ipairs(node.m) do
			local sum = 0
			for stat, value in pairs(effect) do
				check(type(value) == "number" and value > 0, "mastery " .. id .. " effect " .. i .. " " .. stat)
				check(not stat:match("^ks") and not stat:match("^ct"), "mastery effects are ordinary stats")
				sum = sum + 1
			end
			check(sum >= 2, "mastery " .. id .. " effect " .. i .. " has stats")
		end
	end
end
table.sort(masteryIds)
check(table.concat(masteryIds, ",") == "665,666,667,668", "one mastery per class section: " .. table.concat(masteryIds, ","))
check(C.nodeStats(tree.nodes[665], nil, 2).dexterity == 3, "the chosen effect's stats")
check(C.nodeStats(tree.nodes[665], nil, nil) == nil, "no effect without a choice")
check(C.nodeStats(tree.nodes[665], nil, 9) == nil, "no effect for a choice it does not have")
check(C.nodeStats(tree.nodes[2], nil, 1).strength == 1, "a plain node keeps its stats")
check(C.nodeStats(tree.nodes[621], "knight", nil).ksCleavingArc == 1, "a keystone variant")

-- ------------------------------------------------------------------------------------------------ validatePlan
local ClassTree = {allowed = function(node, classKey)
	return not node.c or (classKey ~= nil and node.c[classKey] == true)
end}
local function ctx(classKey, points)
	return {classKey = classKey, allowed = ClassTree.allowed, points = points or 100, maxNodes = cfg.maxPlanNodes}
end
local function plan(current, masteries, nodes, pm, c)
	return C.validatePlan(tree, current, masteries, {nodes = nodes, masteries = pm}, c or ctx("warrior"))
end
local r, err, code = plan({}, {}, {2, 9, 11})
check(r and #r.added == 3 and #r.ids == 3, "a path from the start")
r = plan({2}, {}, {9, 11})
check(r and #r.ids == 3 and r.ids[1] == 2, "a plan onto saved nodes: saved first")
r = plan({2}, {}, {11, 9})
check(r ~= nil, "the order of the plan does not matter")
r, err, code = plan({}, {}, {})
check(code == "empty", "empty plan: " .. tostring(err))
r, err, code = C.validatePlan(tree, {}, {}, "x", ctx("warrior"))
check(code == "malformed", "not a table")
r, err, code = C.validatePlan(tree, {}, {}, {nodes = {[1] = 2, [5] = 9}}, ctx("warrior"))
check(code == "malformed", "a sparse list")
r, err, code = plan({}, {}, {2, "9"})
check(r ~= nil, "a number as a string is a number")
r, err, code = plan({}, {}, {2, 9.5})
check(code == "unknown", "a fraction is no id")
local big = {}
for i = 1, cfg.maxPlanNodes + 1 do
	big[i] = i + 1
end
r, err, code = plan({}, {}, big, nil, ctx("warrior", 1000))
check(code == "size" and err:find(tostring(cfg.maxPlanNodes)), "oversize: " .. tostring(err))
r, err, code = plan({}, {}, {2, 99999})
check(code == "unknown", "unknown id: " .. tostring(err))
r, err, code = plan({}, {}, {1, 2})
check(code == "unknown", "the root is not plannable")
r, err, code = plan({}, {}, {2, 9, 2})
check(code == "duplicate" and err:find("twice"), "duplicate: " .. tostring(err))
r, err, code = plan({2}, {}, {2, 9})
check(code == "owned", "already allocated: " .. tostring(err))
r, err, code = plan({}, {}, {2, 9, 11}, nil, ctx("warrior", 2))
check(code == "points" and err:find("2 free"), "over the points: " .. tostring(err))
r, err, code = plan({2}, {}, {9, 11}, nil, ctx("warrior", 2))
check(code == "points", "saved + planned over the points")
r = plan({2}, {}, {9}, nil, ctx("warrior", 2))
check(r ~= nil, "exactly the points")
r, err, code = plan({}, {}, {2, 600})
check(code == "disconnected" and err:find("600"), "disconnected: " .. tostring(err))
r, err, code = plan({}, {}, {9})
check(code == "disconnected", "a node next to nothing allocated")
-- class sections and the ascended paths (the gates)
r, err, code = plan({}, {}, {626})
check(code == "class", "another line's section: " .. tostring(err))
r = plan({}, {}, {626, 627, 628}, nil, ctx("thief"))
check(r ~= nil, "the thief line's nodes for a thief")
r, err, code = plan({626, 627, 628}, {}, {629}, nil, ctx("thief"))
check(code == "class", "an ascended path for the base class: " .. tostring(err))
r = plan({626, 627, 628}, {}, {629, 630, 631}, nil, ctx("ninja"))
check(r ~= nil, "the ninja path for a ninja")
r, err, code = plan({}, {}, {621})
check(code ~= nil and r == nil, "a keystone far away is refused")
r, err, code = plan({}, {}, {626, 627, 628}, nil, ctx(nil))
check(code == "class", "no class: no class nodes")
-- mastery rules
r, err, code = plan({626, 627, 628}, {}, {665}, nil, ctx("thief"))
check(code == "mastery" and err:find("Choose an effect"), "a mastery needs a choice: " .. tostring(err))
r, err, code = plan({626, 627, 628}, {}, {665}, {{id = 665, choice = 5}}, ctx("thief"))
check(code == "mastery" and err:find("no effect 5"), "a choice it does not have: " .. tostring(err))
r, err, code = plan({626, 627, 628}, {}, {665}, {{id = 665, choice = 0}}, ctx("thief"))
check(code == "mastery", "choice 0 is no effect")
r = plan({626, 627, 628}, {}, {665}, {{id = 665, choice = 3}}, ctx("thief"))
check(r and r.masteries[665] == 3, "a mastery with its effect")
r = plan({626, 627}, {}, {628, 665}, {[665] = 2}, ctx("ninja"))
check(r and r.masteries[665] == 2, "a choice as a map, an ascended class of the line")
r, err, code = plan({626, 627}, {}, {628, 665}, {{id = 665, choice = 2}, {id = 665, choice = 1}}, ctx("thief"))
check(code == "malformed" and err:find("twice"), "a choice twice: " .. tostring(err))
r, err, code = plan({}, {}, {2}, {{id = 2, choice = 1}})
check(code == "mastery" and err:find("not a mastery"), "a choice for a plain node: " .. tostring(err))
r, err, code = plan({626, 627, 628, 665}, {[665] = 1}, {629}, {{id = 665, choice = 2}}, ctx("ninja"))
check(code == "mastery" and err:find("Change effect"), "a plan cannot change a saved mastery: " .. tostring(err))
r, err, code = plan({626, 627, 628}, {}, {629}, {{id = 665, choice = 2}}, ctx("ninja"))
check(code == "mastery" and err:find("not in the plan"), "a choice for a mastery outside the plan: " .. tostring(err))
r = plan({626, 627, 628, 665}, {[665] = 4}, {629}, nil, ctx("ninja"))
check(r and r.masteries[665] == 4, "saved choices are kept")
r, err, code = plan({626, 627, 628}, {}, {666}, {{id = 666, choice = 1}}, ctx("thief"))
check(code == "class", "another line's mastery")

-- checkMasteryChange
local ok
ok, err = C.checkMasteryChange(tree, {626, 627, 628, 665}, {[665] = 1}, 665, 2)
check(ok == true, "change a saved mastery")
ok, err = C.checkMasteryChange(tree, {626, 627, 628, 665}, {[665] = 1}, 665, 1)
check(not ok and err:find("already"), "the same effect: " .. tostring(err))
ok, err = C.checkMasteryChange(tree, {626, 627, 628}, {}, 665, 1)
check(not ok and err:find("not allocated"), "not allocated: " .. tostring(err))
ok, err = C.checkMasteryChange(tree, {626, 627, 628, 665}, {[665] = 1}, 665, 7)
check(not ok and err:find("no such"), "no such effect")
ok, err = C.checkMasteryChange(tree, {2}, {}, 2, 1)
check(not ok and err:find("not a mastery"), "not a mastery")
-- toMap / toList
check(C.toMap(nil) and next(C.toMap(nil)) == nil, "no masteries")
check(C.toMap({["665"] = 2})[665] == 2, "a string key")
check(C.toMap("x") == nil, "malformed masteries")
check(C.toList({[667] = 1, [665] = 2})[1].id == 665, "list sorted by id")

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
dofile("data/scripts/chaos/passivetree.lua")
ChaosClassTree.write = function() end
local ext = events.ChaosPassiveTreeExtended
local paid = {}
ChaosRespec = {nodeCost = function() return 9000 end, sendInfo = function() end,
	pay = function(player, cost) if player.gold >= cost then player.gold = player.gold - cost; paid[#paid + 1] = cost; return true end return false end}
ChaosRespecCore = {formatGold = function(v) return tostring(v) end}

local p = {gold = 0, voc = 12, level = 500, storage = {}}
function p:getGuid() return 1 end
function p:getId() return 1 end
function p:getLevel() return self.level end
function p:getStorageValue(k) return self.storage[k] or -1 end
function p:setStorageValue(k, v) self.storage[k] = v end
function p:getVocation() local id = self.voc; return {getId = function() return id end} end
function p:sendExtendedOpcode() return true end
function p:registerEvent() end
function p:sendTextMessage() end
local OP = ChaosOpcodes.passivetree
local function call(action, data)
	clock = clock + 2000
	inserts, sent = {}, {}
	ext.onExtendedOpcode(p, OP, {action = action, data = data})
	local result
	for _, s in ipairs(sent) do
		if s.action == "planResult" then result = s.data end
	end
	return result
end
local function nodesSent()
	for _, s in ipairs(sent) do
		if s.action == "sendNodes" then return s.data end
	end
end

-- a ninja (vocation 12), nothing saved yet
rows = {}
local res = call("planApply", {nodes = {626, 627, 628, 665}, masteries = {{id = 665, choice = 2}}})
check(res and res.ok and res.message:find("4 nodes"), "planApply: saved")
check(#inserts == 1 and inserts[1].nodes == "626,627,628,665|665:2", "one insert with the choice: " .. tostring(inserts[1] and inserts[1].nodes))
local sn = nodesSent()
check(sn and #sn.nodes == 4 and sn.masteries[1].id == 665 and sn.masteries[1].choice == 2, "sendNodes carries the masteries")
local bonuses = ChaosPassiveTree.getBonuses(p)
check(bonuses.dexterity == 4 + 3 and bonuses.speed == 400, "the bonuses use the chosen effect (Light Step)")
res = call("planApply", {nodes = {629, 600}})
check(res and not res.ok and res.message:find("600"), "a disconnected plan is refused: " .. tostring(res and res.message))
check(#inserts == 0, "nothing saved on a refusal")
check(nodesSent() ~= nil, "the client is sent the saved tree again")
res = call("planApply", {nodes = {629, 629}})
check(res and not res.ok and #inserts == 0, "duplicates refused, nothing saved")
res = call("planApply", {nodes = {632}})
check(res and not res.ok and res.message:find("another class"), "the samurai path refused for a ninja")
p.level = 24 -- (24 - 8) / 4 = 4 points, all spent
res = call("planApply", {nodes = {629}})
check(res and not res.ok and res.message:find("points"), "no free point: " .. tostring(res and res.message))
p.level = 500
res = call("planApply", {nodes = {629, 630}})
check(res and res.ok and inserts[1].nodes == "626,627,628,629,630,665|665:2", "a second plan keeps the saved choice")
-- rate limit: a second apply inside a second is refused
clock = clock + 2000
inserts, sent = {}, {}
ext.onExtendedOpcode(p, OP, {action = "planApply", data = {nodes = {631}}})
ext.onExtendedOpcode(p, OP, {action = "planApply", data = {nodes = {}}})
check(#inserts == 1, "the second apply inside a second is dropped")
-- a plan made from a view that was a step behind: nodes the server already holds are left out, not an error
rows = {{preset = 1, name = "Preset 1", nodes = "626,627,628,629,630,631,665|665:2"}}
res = call("planApply", {nodes = {630, 631}})
check(res and not res.ok and res.message:find("already have") and #inserts == 0, "only held nodes: nothing saved, the tree is sent again: " .. tostring(res and res.message))
check(nodesSent() ~= nil, "the client catches up with sendNodes")
res = call("planApply", {nodes = {631, 630, 632, 633}})
check(res and not res.ok and res.message:find("another class") and #inserts == 0, "the rest is still checked")
local dp, dn = C.dropOwned({1, 2, 3}, {nodes = {2, 4, 3, 5}, masteries = {{id = 3, choice = 1}, {id = 5, choice = 2}}})
check(dn == 2 and #dp.nodes == 2 and dp.nodes[1] == 4 and dp.nodes[2] == 5, "dropOwned keeps the new nodes in order")
check(#dp.masteries == 1 and dp.masteries[1].id == 5, "dropOwned drops the choices of held nodes (a list)")
dp, dn = C.dropOwned({1, 2}, {nodes = {2, 4}, masteries = {[2] = 1, [4] = 3}})
check(dn == 1 and dp.masteries[2] == nil and dp.masteries[4] == 3, "dropOwned on a map of choices")
local same
same, dn = C.dropOwned({1}, {nodes = {2}})
check(dn == 0 and same.nodes[1] == 2, "dropOwned: nothing held, the same plan")
check(select(2, C.dropOwned({1}, "x")) == 0, "dropOwned leaves a malformed plan to validatePlan")
-- the old plain save still refuses a new mastery without an effect, and keeps saved choices
rows = {{preset = 1, name = "Preset 1", nodes = "626,627,628"}}
clock = clock + 2000
inserts = {}
ext.onExtendedOpcode(p, OP, {action = "sendNodes", data = {nodes = {626, 627, 628, 665}}})
check(#inserts == 0, "plain save: a mastery without an effect is refused")
clock = clock + 2000
ext.onExtendedOpcode(p, OP, {action = "sendNodes", data = {nodes = {626, 627, 628, 665}, masteries = {{id = 665, choice = 1}}}})
check(#inserts == 1 and inserts[1].nodes == "626,627,628,665|665:1", "plain save with the effect")
-- masteryChoose: priced like a single-node refund
p.gold = 5000
res = call("masteryChoose", {id = 665, choice = 3})
check(res and not res.ok and res.message:find("9000"), "not enough gold: " .. tostring(res and res.message))
check(#inserts == 0, "nothing changed without the gold")
p.gold = 20000
res = call("masteryChoose", {id = 665, choice = 3})
check(res and res.ok and p.gold == 11000 and inserts[1].nodes == "626,627,628,665|665:3", "effect changed for the node price")
res = call("masteryChoose", {id = 665, choice = 3})
check(res and not res.ok and p.gold == 11000, "the same effect again costs nothing and changes nothing")
res = call("masteryChoose", {id = 629, choice = 1})
check(res and not res.ok, "not a mastery")
-- a refund of another node keeps the mastery's effect (respec.lua passes the row's choices)
dofile("data/scripts/chaos/respec_config.lua")
dofile("data/scripts/chaos/respec_core.lua")
local realRespec = ChaosRespec
ChaosRespec = nil
dofile("data/scripts/chaos/respec.lua")
ChaosRespec.pay = function() return true end
rows = {{preset = 1, name = "Preset 1", nodes = "626,627,628,629,665|665:3"}}
call("refundNode", {id = 629})
check(inserts[1] and inserts[1].nodes == "626,627,628,665|665:3", "a refund keeps the other masteries: " .. tostring(inserts[1] and inserts[1].nodes))
call("refundNode", {id = 665})
check(inserts[1] and inserts[1].nodes == "626,627,628", "refunding the mastery drops its effect")
ChaosRespec = realRespec
-- inspect view
rows = {{preset = 1, name = "Preset 1", nodes = "626,627,628,665|665:4"}}
local view = ChaosPassiveTree.publicView(p)
check(#view.nodes == 4 and view.masteries[1].choice == 4 and view.cls == "ninja" and view.line == "thief", "the public view")

-- ------------------------------------------------------------------------------------------------ reworked nodes
-- the config: append only, version 1 = the four mythic leaves that became the line keystones
local RW = ChaosPassiveTreeConfig.reworked
check(RW[1].version == 1 and table.concat(RW[1].ids, ",") == "369,376,383,390", "version 1 of the reworked list")
local set, newest, any = C.reworkedSince(RW, -1)
check(set[383] and set[369] and set[376] and set[390] and set[108] and set[105] and set[8] and set[503] and set[428] and set[447] and newest == 6 and any,
	"a character that saw none")
-- version 2 (the build archetype keystones, 2026-10): twelve small leaves
check(RW[2].version == 2 and table.concat(RW[2].ids, ",") == "77,78,81,82,106,107,108,109,253,262,355,362",
	"version 2 of the reworked list")
set, newest, any = C.reworkedSince(RW, 1)
check(set[77] and set[362] and set[96] and not set[383] and newest == 6 and any, "a character that saw version 1")
-- version 3 (the second round, 2026-10-12): the four other elemental cluster ends
check(RW[3].version == 3 and table.concat(RW[3].ids, ",") == "96,99,102,105", "version 3 of the reworked list")
set, newest, any = C.reworkedSince(RW, 2)
check(set[96] and set[99] and set[102] and set[105] and not set[77] and newest == 6 and any, "a character that saw version 2")
-- version 4 (2026-10, owner: no drown nodes): 23 nodes left the tree
check(RW[4].version == 4 and #RW[4].ids == 23 and RW[4].ids[1] == 8 and RW[4].ids[23] == 503, "version 4 of the reworked list")
set, newest, any = C.reworkedSince(RW, 3)
check(set[8] and set[490] and set[561] and not set[96] and newest == 6 and any, "a character that saw version 3")
-- version 6 (the third round, 2026-10-20): eight mythic leaves became the Warrior and Ranger line keystones
check(RW[6].version == 6 and table.concat(RW[6].ids, ",") == "428,409,466,523,561,542,599,447", "version 6 of the reworked list")
set, newest, any = C.reworkedSince(RW, 4)
check(set[428] and set[447] and not set[8] and newest == 6 and any, "a character that saw version 4")
set, newest, any = C.reworkedSince(RW, 5)
check(set[466] and set[523] and not set[8] and newest == 6 and any, "a character that saw version 5")
set, newest, any = C.reworkedSince(RW, 6)
check(next(set) == nil and newest == 6 and not any, "a character that saw version 6")
set, newest = C.reworkedSince({{version = 1, ids = {5}}, {version = 2, ids = {7}}}, 1)
check(set[7] and not set[5] and newest == 2, "only what came after")
local kept, removed = C.dropNodes(tree, {2, 9, 11, 13, 61}, {[61] = true})
check(table.concat(kept, ",") == "2,9,11,13" and #removed == 1 and removed[1].why == "reworked", "a leaf goes alone")
kept, removed = C.dropNodes(tree, {2, 9, 11, 13, 61}, {[9] = true})
check(table.concat(kept, ",") == "2" and #removed == 4 and removed[2].why == "disconnected", "what hangs on it goes too")
kept, removed = C.dropNodes(tree, {3, 32}, {})
check(#kept == 2 and #removed == 0, "nothing to drop")
-- at login (passivetree.lua refundReworked): once, presets and loadouts, with a message
-- nodes without a class lane (a lane node is reworked for its class by version 5)
local plain = {}
for id = 2, 400 do
	local nd = tree.nodes[id]
	if nd and not nd.v and not nd.c and not nd.m and #plain < 5 then plain[#plain + 1] = id end
end
rows = {{preset = 1, name = "Preset 1", nodes = table.concat(plain, ",")}}
local msgs = {}
function p:sendTextMessage(_, text) msgs[#msgs + 1] = text end
p.storage[Chaos.storage.passiveRework] = nil
check(ChaosPassiveTree.refundReworked(p) == 0 and p.storage[Chaos.storage.passiveRework] == 6 and #msgs == 0,
	"nothing reworked held: the version is recorded, no message")
check(ChaosPassiveTree.refundReworked(p) == 0, "and not looked at again")
-- a Thief line tree up to 383 (Blackblood Creed; it was the mythic leaf "wisdom 10")
local path383 = {}
do
	local prev, queue, head = {[1] = 1}, {1}, 1
	while head <= #queue do
		local id = queue[head]
		head = head + 1
		for _, nb in ipairs(tree.nodes[id].n) do
			if not prev[nb] and not tree.nodes[nb].c then prev[nb] = id; queue[#queue + 1] = nb end
		end
	end
	prev[383] = prev[383] or 382
	local id = 383
	while id ~= 1 do table.insert(path383, 1, id); id = prev[id] end
end
rows = {{preset = 1, name = "Preset 1", nodes = table.concat(path383, ",")}}
inserts, msgs = {}, {}
local loadoutDrop
ChaosLoadouts = {dropNodes = function(player, drop) loadoutDrop = drop; return 2 end}
p.storage[Chaos.storage.passiveRework] = 0
local refunded = ChaosPassiveTree.refundReworked(p)
check(refunded >= 1, "383 refunded (and, with the class lanes of version 5, the lane nodes before it and what hangs on them)")
check(#inserts == 1 and not ("," .. inserts[1].nodes .. ","):find(",383,", 1, true), "saved without it")
check(#C.parseAlloc(inserts[1].nodes) == #path383 - refunded, "every other node kept")
check(loadoutDrop and loadoutDrop[383] and loadoutDrop[390], "the loadouts are told the same ids")
check(msgs[1] and msgs[1]:find(refunded .. " node", 1, true) and msgs[1]:find("loadouts lost 2", 1, true), "one message: " .. tostring(msgs[1]))
check(p.storage[Chaos.storage.passiveRework] == 6, "version recorded")
inserts = {}
check(ChaosPassiveTree.refundReworked(p) == 0 and #inserts == 0, "only once")
ChaosLoadouts = nil
p.sendTextMessage = function() end

-- ------------------------------------------------------------------------------------------------ loadouts text
dofile("data/scripts/chaos/loadouts_config.lua")
dofile("data/scripts/chaos/loadouts_core.lua")
local L = ChaosLoadoutsCore
check(L.formatNodes({628, 626, 665}, {[665] = 2}) == "626,628,665|665:2", "loadouts write the masteries")
check(table.concat(L.parseNodes("626,628,665|665:2"), ",") == "626,628,665", "loadouts read the ids only")
check(L.parseMasteries("626,628,665|665:2")[665] == 2, "loadouts read the masteries")
check(next(L.parseMasteries("2,3,9")) == nil, "an old loadout has none")
check(L.cleanMasteries(tree, {665, 2}, {[665] = 9, [2] = 1})[665] == nil, "an effect the node does not have is dropped")
check(L.cleanMasteries(tree, {665}, {[665] = 4})[665] == 4, "a valid effect is kept")
check(L.formatNodes({2, 3}) == "2,3", "no masteries: the old text")

print(string.format("passivetree_plan_test: %d checks, %d failures", checks, failures))
if failures > 0 then
	os.exit(1)
end
