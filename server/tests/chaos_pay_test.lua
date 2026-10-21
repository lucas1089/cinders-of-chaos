-- Run from the server/ folder: luajit tests/chaos_pay_test.lua (CI runs it with luajit and lua5.3)
-- Gold payments (data/lib/chaos_pay.lua, Chaos.pay in chaos_constants.lua; server/README.md "Gold payments: carried
-- coins, then the bank"): carried coins only, bank only, both (carried first), not enough (nothing taken), zero and bad
-- amounts, a negative balance, a coin removal that fails, the bank message and its pt-BR text, the Player overrides
-- (getTotalMoney / removeTotalMoney) and the old style cid helpers.

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

MESSAGE_INFO_DESCR = 22

local function mkPlayer(money, bank)
	local p = {money = money, bank = bank, msgs = {}, removeCalls = 0, failRemove = false}
	function p:getMoney() return self.money end
	function p:getBankBalance() return self.bank end
	function p:removeMoney(n)
		self.removeCalls = self.removeCalls + 1
		if self.failRemove or n > self.money then return false end
		self.money = self.money - n
		return true
	end
	function p:setBankBalance(n)
		if n < 0 then return nil end
		self.bank = n
		return true
	end
	function p:sendTextMessage(_, text) self.msgs[#self.msgs + 1] = text end
	return p
end

dofile("data/lib/chaos_pay.lua")
local P = ChaosPay
check(P ~= nil and P.pay and P.canPay and P.total, "ChaosPay loaded")

-- carried coins only
local a = mkPlayer(500, 0)
local ok, coins, bank = P.pay(a, 300)
check(ok, "carried only: paid")
eq(coins, 300, "carried only: from coins")
eq(bank, 0, "carried only: nothing from the bank")
eq(a.money, 200, "carried only: coins left")
eq(#a.msgs, 0, "carried only: no bank message")

-- bank only
local b = mkPlayer(0, 1000)
ok, coins, bank = P.pay(b, 400)
check(ok, "bank only: paid")
eq(coins, 0, "bank only: no coins")
eq(bank, 400, "bank only: from the bank")
eq(b.bank, 600, "bank only: balance")
eq(b.removeCalls, 0, "bank only: no coin removal")
eq(b.msgs[1], "Paid 400 gold from your bank. Bank balance: 600 gold.", "bank only: told")

-- mixed: carried first, then the bank
local c = mkPlayer(150, 1000)
ok, coins, bank = P.pay(c, 400)
check(ok, "mixed: paid")
eq(coins, 150, "mixed: every carried coin first")
eq(bank, 250, "mixed: the rest from the bank")
eq(c.money, 0, "mixed: coins")
eq(c.bank, 750, "mixed: balance")
eq(c.msgs[1], "Paid 400 gold: 150 carried and 250 from your bank. Bank balance: 750 gold.", "mixed: told")

-- exactly everything
local d = mkPlayer(100, 100)
check(P.pay(d, 200), "exactly all: paid")
eq(d.money + d.bank, 0, "exactly all: nothing left")

-- not enough: nothing charged
local e = mkPlayer(100, 200)
check(not P.canPay(e, 301), "short: canPay false")
check(P.canPay(e, 300), "exact: canPay true")
check(not P.pay(e, 301), "short: refused")
eq(e.money, 100, "short: coins untouched")
eq(e.bank, 200, "short: bank untouched")
eq(e.removeCalls, 0, "short: nothing removed")
eq(#e.msgs, 0, "short: no message")

-- the coin removal fails: nothing taken from the bank
local f = mkPlayer(100, 500)
f.failRemove = true
check(not P.pay(f, 300), "coin removal failed: refused")
eq(f.bank, 500, "coin removal failed: bank untouched")

-- the bank write fails after the coins went: the coins go to the bank, nothing lost, refused
local g = mkPlayer(100, 500)
local realSet = g.setBankBalance
local first = true
function g:setBankBalance(n)
	if first then
		first = false
		return false
	end
	return realSet(self, n)
end
check(not P.pay(g, 300), "bank write failed: refused")
eq(g.money + g.bank, 600, "bank write failed: nothing lost")

-- zero, bad and fractional amounts; a negative balance counts as 0
local h = mkPlayer(10, 10)
check(P.pay(h, 0), "zero: paid")
eq(h.money + h.bank, 20, "zero: nothing taken")
check(not P.pay(h, -5), "negative amount: refused")
check(not P.pay(h, "x"), "not a number: refused")
check(not P.pay(h, 0 / 0), "nan: refused")
check(not P.pay(h, math.huge), "inf: refused")
check(not P.pay(nil, 5), "no player: refused")
check(P.pay(h, 5.9), "fraction: floored")
eq(h.money, 5, "fraction: 5 taken")
local neg = mkPlayer(50, -100)
eq(P.total(neg), 50, "negative balance counts as 0")
check(not P.pay(neg, 60), "negative balance: cannot pay past the coins")
eq(neg.bank, -100, "negative balance: untouched")

-- quiet: no message
local q = mkPlayer(0, 100)
check(P.pay(q, 10, true), "quiet: paid")
eq(#q.msgs, 0, "quiet: no message")

-- a player without a bank (setBankBalance missing) pays only from the coins
local nb = {money = 50}
function nb:getMoney() return self.money end
function nb:removeMoney(n) self.money = self.money - n return true end
check(P.pay(nb, 50), "no bank api: coins")
eq(nb.money, 0, "no bank api: paid")

-- the Player overrides: both definitions of the base lib replaced
Player = {}
Player.removeTotalMoney = function() return "stock" end
Player.getTotalMoney = function() return -1 end
check(P.install(), "install")
local pm = mkPlayer(30, 70)
eq(Player.getTotalMoney(pm), 100, "Player.getTotalMoney is carried + bank")
check(Player.removeTotalMoney(pm, 90) == true, "Player.removeTotalMoney pays")
eq(pm.money + pm.bank, 10, "Player.removeTotalMoney took 90")
check(Player.removeTotalMoney(pm, 11) == false, "Player.removeTotalMoney: short is false")

-- old style cid helpers
local byCid = {[7] = mkPlayer(5, 5)}
setmetatable(Player, {__call = function(_, cid) return byCid[cid] end})
eq(P.totalCid(7), 10, "totalCid")
check(P.payCid(7, 10), "payCid")
check(not P.payCid(8, 1), "payCid: no player")
Player = nil

-- Chaos.pay / canPay / totalMoney on chaos_constants, and the pt-BR texts
dofile("data/scripts/chaos/chaos_constants.lua")
dofile("data/scripts/chaos/i18n_core.lua")
local cp = mkPlayer(20, 80)
eq(Chaos.totalMoney(cp), 100, "Chaos.totalMoney")
check(Chaos.canPay(cp, 100) and not Chaos.canPay(cp, 101), "Chaos.canPay")
check(Chaos.pay(cp, 50), "Chaos.pay")
eq(cp.money, 0, "Chaos.pay: coins first")
eq(cp.bank, 50, "Chaos.pay: then the bank")
local pt = ChaosI18n.strings["pt-BR"]
for _, key in ipairs({"Paid %d gold: %d carried and %d from your bank. Bank balance: %d gold.",
		"Paid %d gold from your bank. Bank balance: %d gold.",
		"You do not have enough gold (carried and in the bank)."}) do
	check(pt[key] ~= nil, "pt-BR: " .. key)
end
local br = mkPlayer(0, 100)
function br:getId() return 1 end
function br:getStorageValue() return -1 end
ChaosI18n.players[1] = "pt-BR"
check(Chaos.pay(br, 40), "pt-BR player pays")
eq(br.msgs[1], "Pago 40 de ouro do seu banco. Saldo no banco: 60 de ouro.", "the bank message in pt-BR")

print(string.format("chaos_pay_test: %d checks, %d failures", checks, failures))
if failures > 0 then
	os.exit(1)
end
