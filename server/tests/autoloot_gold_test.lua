-- Run from the server/ folder: luajit tests/autoloot_gold_test.lua (and lua5.3; CI runs both)
-- Coins of every corpse the character owns go to the bank (autoloot.lua, onDropLoot 2.6).
local count, failures = 0, 0
local function check(cond, label)
	count = count + 1
	if not cond then failures = failures + 1 print("FAIL " .. label) end
end
dofile("data/scripts/chaos/chaos_constants.lua")
dofile("data/scripts/chaos/i18n_core.lua")
local names = {[2148] = "gold coin", [2152] = "platinum coin", [2160] = "crystal coin", [2400] = "dagger"}
ItemType = function(x)
	local id = tonumber(x)
	return {getId = function() return names[id or 0] and id or 0 end, getName = function() return names[id] or "?" end,
		getClientId = function() return (id or 0) + 1 end}
end
ChaosArchery = {isAmmoId = function() return false end}
function CreatureEvent(name) return {type = function() end, register = function() end} end
Chaos.send = function() end
dofile("data/scripts/chaos/autoloot.lua")
local G = ChaosAutolootGold
check(G.total({{id = 2148, count = 50}, {id = 2152, count = 2}, {id = 2160, count = 1}, {id = 2400, count = 5}}) == 50 + 200 + 10000,
	"coin values add up, other items ignored")

local base = Chaos.storage.autolootBase
local function owner(listIds)
	local o = {st = {}, bank = 0, msgs = {}}
	function o:getStorageValue(k) return self.st[k] or -1 end
	function o:setStorageValue(k, v) self.st[k] = v end
	function o:isPremium() return true end
	function o:getBankBalance() return self.bank end
	function o:setBankBalance(v) self.bank = v end
	function o:sendTextMessage(_, t) self.msgs[#self.msgs + 1] = t end
	for i, id in ipairs(listIds) do o.st[base + i] = id end
	return o
end
local function corpse(items)
	local c = {items = items}
	function c:getItems() return self.items end
	return c
end
local function coin(id, n, c)
	local it = {id = id, n = n}
	function it:getId() return self.id end
	function it:getCount() return self.n end
	function it:getType() return {isContainer = function() return false end} end
	function it:remove() self.gone = true return true end
	return it
end

local o = owner({2160})
local a, b, d = coin(2148, 30), coin(2152, 3), coin(2400, 1)
local paid = G.toBank(o, corpse({a, b, d}))
check(paid == 330 and o.bank == 330, "coins paid into the bank")
check(a.gone and b.gone and not d.gone, "only the coins are taken from the corpse")
check(#o.msgs == 1, "one message")

local o2 = owner({2400})
local c2 = coin(2148, 10)
check(G.toBank(o2, corpse({c2})) == 10 and c2.gone and o2.bank == 10, "no coin on the list: the coins still go to the bank (default)")
local o3 = owner({})
check(G.toBank(o3, corpse({coin(2400, 1)})) == 0 and o3.bank == 0, "no coins in the corpse: nothing paid")

-- coins inside a bag of the corpse are taken too
local function bag(items)
	local b = {items = items}
	function b:getItems() return self.items end
	function b:getId() return 1987 end
	function b:getType() return {isContainer = function() return true end} end
	return b
end
local o7 = owner({2148})
local inner = coin(2160, 1)
check(G.toBank(o7, corpse({coin(2148, 5), bag({inner})})) == 10005 and inner.gone, "coins in a bag of the corpse")
print(string.format("autoloot_gold_test: %d checks, %d failures", count, failures))
if failures > 0 then os.exit(1) end
