-- Run from the server/ folder: luajit tests/respec_test.lua (or lua5.3; CI runs both)
-- Respec prices and rules (respec_core.lua, respec_config.lua) and the handlers of respec.lua against a mocked engine:
-- the cost curve, the free cases, single-node refunds (connectivity, gold), the full reset and the Paragon reset.
local n = 0
setmetatable(_G, {__index = function(t, k)
	if type(k) == "string" and k:match("^[A-Z_0-9]+$") then n = n + 1; rawset(t, k, n); return n end
end})
dofile("data/scripts/chaos/chaos_constants.lua")
dofile("data/scripts/chaos/respec_config.lua")
dofile("data/scripts/chaos/respec_core.lua")
local C, cfg = ChaosRespecCore, ChaosRespecConfig
local tree = dofile("data/scripts/chaos/passivetree_data.lua")

local failures, count = 0, 0
local function check(cond, label)
	count = count + 1
	if not cond then
		failures = failures + 1
		print("FAIL " .. label)
	end
end

-- curve
check(C.fullCost(49) == 0 and C.nodeCost(49) == 0, "free below level 50")
check(C.fullCost(50) == 50000, "level 50 point")
check(C.fullCost(100) == 225000 and C.fullCost(300) == 565000 and C.fullCost(1000) == 5950000, "curve points")
check(C.fullCost(200) == 395000, "linear between points")
check(C.fullCost(1200) == 6950000, "last slope past the last point")
local last = 0
for level = 50, 2000, 7 do
	local cost = C.fullCost(level)
	check(cost >= last, "monotonic at " .. level)
	last = cost
end
check(C.fullCost(600, "paragon") == C.fullCost(600) * cfg.paragonFactor, "paragon factor")
check(C.nodeCost(1000) == 238000 and C.nodeCost(100) == 9000, "node refund = 4% of the full reset")
check(C.nodeCost(50) == 2000, "node refund at level 50")
-- ~37.5 minutes / ~1.5 minutes of the measured income (respec_income.py)
local income = {[100] = 358839, [300] = 881866, [500] = 5548330, [600] = 6342606, [1000] = 9519711}
for level, perHour in pairs(income) do
	local minutes = C.fullCost(level) / perHour * 60
	check(minutes >= 30 and minutes <= 45, string.format("full reset at %d = %.1f min of hunting", level, minutes))
	local nodeMinutes = C.nodeCost(level) / perHour * 60
	check(nodeMinutes >= 1 and nodeMinutes <= 2, string.format("node refund at %d = %.2f min", level, nodeMinutes))
end
check(C.formatGold(5950000) == "5,950,000" and C.formatGold(999) == "999", "format gold")

-- free reasons
check(C.freeReason(10, 4, 4) == "level", "low level")
check(C.freeReason(300, 8, 4) == "vocation", "vocation changed since the last free reset")
check(C.freeReason(300, 4, 4) == nil, "same vocation: not free")
check(C.freeReason(300, 4, -1) == nil, "not recorded yet: not free")

-- canRemove
local ok, err = C.canRemove(tree, {2, 9, 11}, 11)
check(ok, "leaf can be refunded")
ok, err = C.canRemove(tree, {2, 9, 11}, 9)
check(not ok and err:find("depend"), "middle node cannot: " .. tostring(err))
ok = C.canRemove(tree, {2, 9, 11, 3}, 2)
check(not ok, "first node with a branch behind it cannot")
ok = C.canRemove(tree, {2, 3}, 2)
check(ok, "first node alone can")
ok, err = C.canRemove(tree, {2, 9}, 30)
check(not ok and err:find("not allocated"), "unallocated node")
ok = C.canRemove(tree, {2}, 1)
check(not ok, "root never")
-- a node on a loop: removing one side keeps the rest connected through the other
ok = C.canRemove(tree, {2, 4, 29, 30, 31}, 30)
check(ok, "node on a loop can be refunded")

-- ---------------------------------------------------------------- handlers (respec.lua) against mocks
local sent, texts = {}, {}
function Chaos.send(player, opcode, action, data) sent[#sent + 1] = {action = action, data = data}; return true end
local registered = {}
function CreatureEvent(name) local o = {}; function o:register() registered[name] = o end; return o end
local function newPlayer(level, voc, gold)
	local p = {level = level, voc = voc, gold = gold, storage = {}, guid = 7}
	function p:getLevel() return self.level end
	function p:getVocation() local s = self; return {getId = function() return s.voc end} end
	function p:getStorageValue(k) return self.storage[k] or -1 end
	function p:setStorageValue(k, v) self.storage[k] = v end
	function p:getGuid() return self.guid end
	function p:getId() return 100 end
	function p:removeTotalMoney(amount) if amount > self.gold then return false end; self.gold = self.gold - amount; return true end
	function p:getMoney() return self.gold end
	function p:removeMoney(amount) if amount > self.gold then return false end; self.gold = self.gold - amount; return true end
	function p:sendTextMessage(_, text) texts[#texts + 1] = text end
	return p
end
local saved = {nodes = {2, 9, 11}}
local resetAllCalls = 0
ChaosPassiveTree = {
	apply = function() end,
	resetAll = function() resetAllCalls = resetAllCalls + 1 end,
	extraActions = {},
	internal = {
		getTree = function() return tree end,
		loadPresets = function() return {{preset = 1, name = "Preset 1", nodes = saved.nodes}} end,
		savePreset = function(_, _, _, ids) saved.nodes = ids end,
		sendNodes = function() end, sendPoints = function() end,
		sendMessageBox = function(_, title, text) texts[#texts + 1] = title .. ": " .. text end,
		totalPoints = function() return 100 end
	}
}
local paragonAlloc = {damage = 5}
ChaosParagon = {
	hasAllocation = function() return next(paragonAlloc) ~= nil end,
	resetAll = function() paragonAlloc = {} end,
	sendState = function() end
}
dofile("data/scripts/chaos/respec.lua")
local A = ChaosPassiveTree.extraActions
local R = ChaosRespec

local p = newPlayer(1000, 4, 10000000)
registered.ChaosRespecLogin.onLogin(p)
check(p.storage[cfg.freeVocationStorage] == 4, "first login records the vocation")
check(R.fullCost(p, "tree") == 5950000, "full cost for the player")

-- single-node refund
A.refundNode(p, {id = 9})
check(#saved.nodes == 3 and p.gold == 10000000, "refund refused when others depend on it")
A.refundNode(p, {id = 11})
check(#saved.nodes == 2 and p.gold == 10000000 - 238000, "leaf refunded for the node price")
local poor = newPlayer(1000, 4, 1000)
poor.storage[cfg.freeVocationStorage] = 4
A.refundNode(poor, {id = 9})
check(#saved.nodes == 2 and texts[#texts]:find("238,000"), "refund without gold refused")

-- full reset: paid, then free once after an ascension, then paid again
A.resetPreset(p, 1)
check(#saved.nodes == 0 and p.gold == 10000000 - 238000 - 5950000, "full reset paid")
saved.nodes = {2, 9}
p.voc = 8 -- ascended
check(R.info(p).full == 0 and R.info(p).free == "vocation", "free reset offered after the class change")
local before = p.gold
A.resetPreset(p, 1)
check(#saved.nodes == 0 and p.gold == before and texts[#texts]:find("free"), "free reset after the class change")
saved.nodes = {2, 9}
A.resetPreset(p, 1)
check(#saved.nodes == 2 and texts[#texts]:find("You need"), "the free reset is used up (not enough gold left)")

-- the store's free resets (resetAll) use up a pending free reset
p.voc = 14
check(R.freeReason(p) == "vocation", "pending again")
ChaosPassiveTree.resetAll(p)
check(resetAllCalls == 1 and R.freeReason(p) == nil, "resetAll uses up the free reset")

-- below level 50 everything is free
local low = newPlayer(30, 4, 0)
registered.ChaosRespecLogin.onLogin(low)
saved.nodes = {2, 9, 11}
A.refundNode(low, {id = 11})
check(#saved.nodes == 2, "free refund below 50")
A.resetPreset(low, 1)
check(#saved.nodes == 0, "free reset below 50")

-- Paragon reset uses the same rule
local rich = newPlayer(1100, 4, 100000000)
registered.ChaosRespecLogin.onLogin(rich)
A.paragonReset(rich)
check(next(paragonAlloc) == nil and rich.gold == 100000000 - C.fullCost(1100, "paragon"), "paragon reset priced by the curve")

-- requestPoints sends the prices and lets the tree answer too
sent = {}
check(A.requestPoints(rich) == false and sent[1].action == "respecInfo" and sent[1].data.node == C.nodeCost(1100),
	"requestPoints: respecInfo then the tree's own reply")

-- ---------------------------------------------------------------- tester bots: a waiver, never gold
local w = cfg.testerWaiver
check(w and w.perDay > 0 and w.storageDay >= 7102900 and w.storageUsed <= 7102909 and w.storageDay ~= w.storageUsed,
	"tester waiver config inside the tester storage block")
check(select(1, C.testerWaiver(-1, -1, 20000)) == true, "core: first waiver of the day")
do
	local okw, day, used = C.testerWaiver(-1, -1, 20000)
	check(okw and day == 20000 and used == 1, "core: state after the first waiver")
	okw, day, used = C.testerWaiver(20000, w.perDay, 20000)
	check(not okw and used == w.perDay, "core: the daily cap refuses")
	okw, day, used = C.testerWaiver(20000, w.perDay, 20001)
	check(okw and used == 1 and day == 20001, "core: a new day starts over")
	okw = C.testerWaiver(20000, 5, nil)
	check(not okw, "core: no day, no waiver")
	okw = C.testerWaiver(-1, -1, 20000, {})
	check(not okw, "core: no testerWaiver config, nothing waived")
end
local function newTester(name, group, accountType, tag)
	local t = newPlayer(1000, 4, 0)
	t.name, t.group, t.accountType = name, group or 1, accountType or 1
	t.storage[cfg.freeVocationStorage] = 4
	if tag ~= false then
		t.storage[Chaos.storage.tester] = 1
	end
	function t:getName() return self.name end
	function t:getGroup() local g = self.group; return {getId = function() return g end} end
	function t:getAccountType() return self.accountType end
	return t
end
local printed = {}
local rawPrint = print
print = function(...) printed[#printed + 1] = table.concat({...}, " ") end
local bot = newTester("Tester Abc")
saved.nodes = {2, 9, 11}
A.resetPreset(bot, 1)
check(#saved.nodes == 0 and bot.gold == 0, "tester: full reset at level 1000 without gold, none created")
check(printed[#printed] and printed[#printed]:find("waived 5,950,000 gold for tester Tester Abc"), "tester: the waiver is logged")
check(bot.storage[w.storageUsed] == 1, "tester: counted")
saved.nodes = {2, 9, 11}
A.refundNode(bot, {id = 11})
check(#saved.nodes == 2 and bot.gold == 0 and bot.storage[w.storageUsed] == 2, "tester: node refund waived too")
for i = 1, w.perDay do
	saved.nodes = {2, 9, 11}
	A.refundNode(bot, {id = 11})
end
check(bot.storage[w.storageUsed] == w.perDay, "tester: the count stops at the daily cap")
saved.nodes = {2, 9, 11}
A.resetPreset(bot, 1)
check(#saved.nodes == 3 and texts[#texts]:find("You need"), "tester: over the cap the normal price applies")
bot.storage[w.storageDay] = bot.storage[w.storageDay] - 1 -- yesterday's count
saved.nodes = {2, 9, 11}
A.resetPreset(bot, 1)
check(#saved.nodes == 0 and bot.storage[w.storageUsed] == 1, "tester: the next day starts over")
-- not a tester: the tag alone is not enough (name, group, account type), and nobody without the tag
for _, c in ipairs({
	{"a player carrying the tag", newTester("Hero Player")},
	{"a tester in a staff group", newTester("Tester Abc", 3)},
	{"a tester on a staff account", newTester("Tester Abc", 1, 5)},
	{"a player without the tag", newTester("Tester Abc", 1, 1, false)},
	{"a normal player", newPlayer(1000, 4, 0)},
}) do
	local who = c[2]
	who.getName = who.getName or function() return "Hero Player" end
	who.getGroup = who.getGroup or function() return {getId = function() return 1 end} end
	who.getAccountType = who.getAccountType or function() return 1 end
	who.storage[cfg.freeVocationStorage] = 4
	saved.nodes = {2, 9, 11}
	A.resetPreset(who, 1)
	check(#saved.nodes == 3 and who.gold == 0 and who.storage[w.storageUsed] == nil, c[1] .. ": pays like everybody")
end
check(R.fullCost(bot, "tree") == 5950000, "tester: the price shown is unchanged (only the payment is waived)")
print = rawPrint

print(string.format("respec_test: %d checks, %d failures", count, failures))
if failures > 0 then
	os.exit(1)
end
