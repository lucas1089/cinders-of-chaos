-- Run from the server/ folder: luajit tests/restock_test.lua (CI runs it with luajit and lua5.3)
-- Restock (restock_core.lua, restock_config.lua, restock.lua; server/README.md "Restock"): what is left to buy back,
-- runes by their charges, the unit cap, the order, what the money pays for, stacks, the quote check; then the engine on
-- a mocked server: refused outside a protection zone and in an instance, the quote, the purchase (paid, items given,
-- noted on the session so a second click buys nothing), a changed quote quoted again, not enough money, a session
-- reset, a full backpack to the inbox, and the pt-BR keys.

local checks, failures = 0, 0
local function check(cond, label)
	checks = checks + 1
	if not cond then
		failures = failures + 1
		print("FAIL " .. label)
	end
end
local function eq(a, b, label)
	check(a == b, tostring(label or "check") .. " (" .. tostring(a) .. " ~= " .. tostring(b) .. ")")
end

dofile("data/scripts/chaos/restock_core.lua")
local R = ChaosRestockCore
local cfg = dofile("data/scripts/chaos/restock_config.lua")
check(cfg.priceMult > 0 and cfg.maxUnits > 0 and cfg.stackSize > 0, "config")

-- 7618 potion (stackable, 45), 2268 rune (5 charges, 220 for the rune), 2389 spear (stackable, 2), 1 no price
local PRICES = {[7618] = 45, [2268] = 220, [2389] = 2}
local INFO = {[7618] = {stack = true}, [2268] = {stack = false, charges = 5}, [2389] = {stack = true}, [1] = {stack = true}}
local function info(id) return INFO[id] end

local left = R.remaining({[7618] = 30, [2268] = 12, [2389] = 4}, {[7618] = 10, [2389] = 9})
eq(left[7618], 20, "potions left"); eq(left[2268], 12, "rune charges"); eq(left[2389], nil, "spears done")
local plain = {priceMult = 1, maxUnits = 5000}
local plan = R.plan({[7618] = 20, [2268] = 12, [1] = 5}, PRICES, info, plain)
eq(#plan, 2, "no price: left out")
eq(plan[1].id, 7618, "most gold first"); eq(plan[1].count, 20); eq(plan[1].gold, 900)
eq(plan[2].id, 2268); eq(plan[2].count, 3, "12 charges: 3 runes"); eq(plan[2].gold, 660)
eq(R.total(plan), 1560, "total")
local capped = R.plan({[7618] = 20, [2268] = 12}, PRICES, info, {priceMult = 1, maxUnits = 25})
eq(capped[1].count, 20); eq(capped[2].units, 5, "the rest of the cap"); eq(capped[2].count, 1)
local pricier = R.plan({[7618] = 1}, PRICES, info, {priceMult = 1.5, maxUnits = 10})
eq(pricier[1].each, 68, "price x 1.5 rounded")
eq(cfg.priceMult, 1.10, "a 10% convenience fee"); eq(R.feePercent(cfg), 10, "fee percent")
local feePlan = R.plan({[7618] = 20, [2268] = 12}, PRICES, info, cfg)
eq(feePlan[1].each, 50, "potion 45 + 10% rounded"); eq(R.fee(feePlan, PRICES), 20 * 5 + 3 * 22, "fee in gold")
eq(R.fee(plan, PRICES), 0, "no fee at x1"); eq(R.feePercent({priceMult = 1}), 0)

local rows, gold = R.afford(plan, 1000)
eq(#rows, 1, "the potions; 100 left is no rune"); eq(rows[1].count, 20); eq(gold, 900, "paid")
rows, gold = R.afford(plan, 1400)
eq(#rows, 2, "and two runes"); eq(rows[2].count, 2); eq(rows[2].units, 10, "units of the runes bought"); eq(gold, 1340)
rows, gold = R.afford(plan, 100)
eq(#rows, 1, "two potions only"); eq(rows[1].count, 2); eq(gold, 90)
rows, gold = R.afford(plan, 0)
eq(#rows, 0, "no money"); eq(gold, 0)

local st = R.stacks(250, 100)
eq(#st, 3); eq(st[3], 50, "the rest"); eq(#R.stacks(0, 100), 0)
check(R.sameQuote(plan, plan), "same quote")
check(not R.sameQuote(plan, {plan[1]}), "different quote"); check(not R.sameQuote(nil, plan), "no quote")

-- ================================================================ restock.lua on a mocked engine
MESSAGE_EVENT_ADVANCE, TILESTATE_PROTECTIONZONE = 19, 1
local registry = {}
function CreatureEvent(name)
	local o = {name = name}
	function o:type() end
	function o:register() registry[name] = self end
	return o
end
local sent = {}
json = {encode = function(t) sent[#sent + 1] = t return "#" .. #sent end, decode = function(s) return {action = s} end}
local TYPES = {[7618] = {stack = true, charges = 0, name = "health potion"}, [2268] = {stack = false, charges = 5,
	name = "sudden death rune"}}
function ItemType(id)
	local t = TYPES[id] or {stack = true, charges = 0, name = "x"}
	return {isStackable = function() return t.stack end, getCharges = function() return t.charges end,
		getClientId = function() return id + 1 end, getName = function() return t.name end}
end
local pz = true
function Tile() return {hasFlag = function() return pz end} end
local mkPlayer = function()
	local p = {id = 1, guid = 7, money = 500, bankGold = 2000, items = {}, inbox = {}, said = {}, cancels = {}, full = false}
	function p:getId() return self.id end
	function p:getGuid() return self.guid end
	function p:getName() return "P" end
	function p:getPosition() return {x = 1, y = 1, z = 7} end
	function p:getMoney() return self.money end
	function p:getBankBalance() return self.bankGold end
	function p:setBankBalance(v) self.bankGold = v return true end
	function p:removeMoney(g) if self.money < g then return false end self.money = self.money - g return true end
	function p:removeTotalMoney(g)
		if self.money + self.bankGold < g then return false end
		local fromHand = math.min(self.money, g)
		self.money = self.money - fromHand
		self.bankGold = self.bankGold - (g - fromHand)
		return true
	end
	function p:addItem(id, n, drop, sub)
		if self.full then return nil end
		self.items[id] = (self.items[id] or 0) + (sub and 1 or n)
		return {}
	end
	function p:getInbox() local me = self return {addItem = function(_, id, n) me.inbox[id] = (me.inbox[id] or 0) + 1 return true end} end
	function p:sendTextMessage(t, m) self.said[#self.said + 1] = m end
	function p:sendCancelMessage(m) self.cancels[#self.cancels + 1] = m end
	function p:sendExtendedOpcode() end
	function p:registerEvent() end
	return p
end
dofile("data/scripts/chaos/chaos_constants.lua")
dofile("data/scripts/chaos/i18n_core.lua")
ChaosHunt = {sessions = {}}
dofile("data/scripts/chaos/restock.lua")
local RS = ChaosRestock
RS.prices = {[7618] = 45, [2268] = 220}
ChaosRestockConfig.priceMult = 1.0 -- the engine checks below at the plain price; the fee is checked once at the end
local p = mkPlayer()
local ext = registry.ChaosRestockExtended
local function say(action) ext.onExtendedOpcode(p, ChaosOpcodes.hunt, action) end

say("restockQuote")
eq(sent[#sent].data.why, "none", "no session: nothing to buy")
local s = {supplies = {[7618] = {n = 30}, [2268] = {n = 10}}}
ChaosHunt.sessions[7] = s
pz = false
say("restockQuote")
eq(sent[#sent].data.why, "pz", "outside a protection zone")
say("restock")
check(p.cancels[#p.cancels]:find("protection zone", 1, true) ~= nil, "pz refusal told")
pz = true
local oldInst = Chaos.inAnyInstance
Chaos.inAnyInstance = function() return "rift" end
say("restockQuote")
eq(sent[#sent].data.why, "instance", "in an instance")
Chaos.inAnyInstance = oldInst

-- a purchase without a quote first: quoted, not bought
say("restock")
eq(sent[#sent].action, "restockQuote", "quote first"); eq(p.items[7618], nil, "nothing bought yet")
local q = sent[#sent].data
eq(q.why, ""); eq(q.gold, 30 * 45 + 2 * 220, "quote gold"); eq(#q.rows, 2); eq(q.money, 2500)
say("restock")
eq(p.items[7618], 30, "potions bought"); eq(p.items[2268], 2, "two runes"); eq(p.money + p.bankGold, 2500 - q.gold, "paid")
check(p.said[#p.said]:find("Restocked", 1, true) ~= nil, "told")
eq(s.restock.n[7618], 30, "noted on the session")
say("restockQuote")
eq(sent[#sent].data.why, "none", "a second click buys nothing")
-- more used; the quote changes between the click and the purchase: quoted again
s.supplies[7618].n = 40
say("restockQuote")
s.supplies[7618].n = 50
say("restock")
eq(sent[#sent].action, "restockQuote", "changed: quoted again"); eq(p.items[7618], 30, "not bought")
-- not enough money
p.money, p.bankGold = 0, 10
say("restockQuote")
eq(sent[#sent].data.why, "money", "no money")
say("restock")
check(p.cancels[#p.cancels]:find("gold", 1, true) ~= nil, "money refusal told")
-- a reset of the session (a new supplies table): starts over; a full backpack goes to the inbox
p.money, p.bankGold = 0, 100000
s.supplies = {[7618] = {n = 5}}
p.full = true
say("restockQuote")
eq(sent[#sent].data.gold, 225, "after a reset only the new use")
say("restock")
eq(p.inbox[7618], 1, "one stack to the inbox")
check(p.said[#p.said]:find("inbox", 1, true) ~= nil, "inbox told")
-- other actions of the hunt opcode are not ours
local n = #sent
say("open")
eq(#sent, n, "hunt actions ignored")

-- the fee in the quote
ChaosRestockConfig.priceMult = 1.10
s.supplies = {[7618] = {n = 10}}
say("restockQuote")
eq(sent[#sent].data.gold, 500, "10 potions at 50"); eq(sent[#sent].data.fee, 50, "fee in the quote")
eq(sent[#sent].data.pct, 10, "fee percent in the quote")

-- pt-BR keys
local strings = dofile("data/scripts/chaos/i18n_strings.lua")["pt-BR"]
local fh = io.open("data/scripts/chaos/restock.lua", "r")
local src = fh:read("*a")
fh:close()
local keys = 0
for key in src:gmatch('Chaos%.t%(player, "([^"]+)"') do
	keys = keys + 1
	check(strings[key] ~= nil, "pt-BR for: " .. key)
end
check(keys >= 6, "keys found")

print(string.format("restock_test: %d checks, %d failures", checks, failures))
if failures > 0 then
	os.exit(1)
end
