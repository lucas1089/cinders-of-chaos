-- Run from the server/ folder: luajit tests/pact_engine_test.lua (and lua5.3; CI runs both)
-- pact.lua against a mocked engine and database (O317): the daily claim now pays Pact Marks (once a day, not Chaos Coins),
-- the Marks shelf (cosmetics only: a key off the shelf, too few Marks or an owned cosmetic is refused; a failed grant gives
-- the Marks back), the experience the +10% added per character and month (pending, flushed, summed), the expiry warnings
-- (3 days, then 1 day: a chat line and a toast, at login and online, in pt-BR too), the stacking cap for store bundles,
-- the name plate frame, and the status the window reads.
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
local function eq(a, b, label)
	check(a == b, label .. " (got " .. tostring(a) .. ", want " .. tostring(b) .. ")")
end

local NOW = os.time()
local DAY = 86400

-- ---------------------------------------------------------------- mocked database
local DB = {pact = {}, marks = {}, xp = {}, extras = {}, log = {}, rowCount = 0, queries = {}}
local function monthOf(t) local d = os.date("*t", t) return d.year * 100 + d.month end

db = {
	escapeString = function(s) return "'" .. tostring(s) .. "'" end,
	asyncQuery = function(q) DB.queries[#DB.queries + 1] = q end,
	query = function(q)
		DB.queries[#DB.queries + 1] = q
		local acc, ends, started, days = q:match("INSERT INTO `chaos_pact` %(`account_id`, `ends_at`, `started_at`, `total_days`%) VALUES %((%d+), (%d+), (%d+), (%d+)%)")
		if acc then
			acc = tonumber(acc)
			local r = DB.pact[acc] or {ends = 0, started = 0, total = 0, claim = 0, claimed = 0}
			r.ends, r.started, r.total = tonumber(ends), tonumber(started), r.total + tonumber(days)
			DB.pact[acc] = r
			return true
		end
		local day, amount, a2 = q:match("UPDATE `chaos_pact` SET `last_claim` = (%d+), `claimed_total` = `claimed_total` %+ (%d+) WHERE `account_id` = (%d+) AND")
		if day then
			local r = DB.pact[tonumber(a2)]
			if r and r.claim < tonumber(day) then r.claim, r.claimed = tonumber(day), r.claimed + tonumber(amount) end
			return true
		end
		local a3, bal = q:match("INSERT INTO `chaos_pact_marks` %(`account_id`, `balance`, `earned`, `updated`%) VALUES %((%d+), (%d+),")
		if a3 then
			a3, bal = tonumber(a3), tonumber(bal)
			local r = DB.marks[a3] or {balance = 0, earned = 0, spent = 0}
			r.balance, r.earned = math.min(r.balance + bal, 100000), r.earned + bal
			DB.marks[a3] = r
			return true
		end
		local take, a4, need = q:match("UPDATE `chaos_pact_marks` SET `balance` = `balance` %- (%d+), `spent` = `spent` %+ %d+, `updated` = %d+ WHERE `account_id` = (%d+) AND `balance` >= (%d+)")
		if take then
			local r = DB.marks[tonumber(a4)]
			if r and r.balance >= tonumber(need) then
				r.balance, r.spent = r.balance - tonumber(take), r.spent + tonumber(take)
				DB.rowCount = 1
			else
				DB.rowCount = 0
			end
			return true
		end
		local back, a5 = q:match("UPDATE `chaos_pact_marks` SET `earned` = `earned` %- (%d+), `spent` = `spent` %- %d+ WHERE `account_id` = (%d+)")
		if back then
			local r = DB.marks[tonumber(a5)]
			r.earned, r.spent = r.earned - tonumber(back), r.spent - tonumber(back)
			return true
		end
		local pid, month, exp = q:match("INSERT INTO `chaos_pact_xp` %(`player_id`, `month`, `exp`%) VALUES %((%d+), (%d+), (%d+)%)")
		if pid then
			DB.xp[#DB.xp + 1] = {player = tonumber(pid), month = tonumber(month), exp = tonumber(exp)}
			return true
		end
		return true
	end
}
local players = {}
Chaos = nil
dofile("data/scripts/chaos/chaos_constants.lua")
Chaos.select = function(q, cols)
	if q:find("ROW_COUNT()", 1, true) then
		return {{n = DB.rowCount}}
	elseif q:find("FROM `chaos_pact` WHERE", 1, true) then
		local r = DB.pact[tonumber(q:match("`account_id` = (%d+)"))]
		return r and {{ends_at = r.ends, last_claim = r.claim, started_at = r.started, total_days = r.total, claimed_total = r.claimed}} or {}
	elseif q:find("FROM `chaos_account_extras`", 1, true) then
		return {}
	elseif q:find("FROM `chaos_pact_marks`", 1, true) then
		local r = DB.marks[tonumber(q:match("`account_id` = (%d+)"))]
		return r and {{balance = r.balance, earned = r.earned, spent = r.spent}} or {}
	elseif q:find("FROM `chaos_pact_xp` x JOIN `players`", 1, true) then
		local account, month = tonumber(q:match("p%.`account_id` = (%d+)")), tonumber(q:match("x%.`month` = (%d+)"))
		local out, sums = {}, 0
		for _, r in ipairs(DB.xp) do
			local p = players[r.player]
			if p and p.account == account and r.month == month then out[#out + 1] = {month = r.month, exp = r.exp} end
		end
		return out
	elseif q:find("FROM `chaos_pact_xp`", 1, true) then
		local pid, month = tonumber(q:match("`player_id` = (%d+)")), tonumber(q:match("`month` = (%d+)"))
		local out = {}
		for _, r in ipairs(DB.xp) do
			if r.player == pid and r.month == month then out[#out + 1] = {month = r.month, exp = r.exp} end
		end
		return out
	end
	return {}
end
Chaos.decode = function(b) return b end

-- ---------------------------------------------------------------- mocked engine
local sent = {}
json = {encode = function(t) sent[#sent + 1] = t; return t end, decode = function(b) return b end}
local registry = {}
local function event(name)
	local e = {name = name}
	function e:register() registry[name] = self end
	function e:type() end
	function e:interval() end
	function e:separator() end
	return e
end
CreatureEvent, GlobalEvent, TalkAction = event, event, event
addEvent = function() end
ChaosRateLimit = {allow = function() return true end}
local cosmeticsOwned, cosmeticsFail = {}, false
local grants = {}
ChaosCosmetics = {
	owns = function(acc, key) return (cosmeticsOwned[acc] or {})[key] == true end,
	grant = function(acc, key, src)
		if cosmeticsFail then return false, "Could not save the cosmetic." end
		cosmeticsOwned[acc] = cosmeticsOwned[acc] or {}
		if cosmeticsOwned[acc][key] then return false, "owned" end
		cosmeticsOwned[acc][key] = true
		grants[#grants + 1] = key .. ":" .. src
		return true
	end,
	sendState = function() end
}
local toasts = {}
dofile("data/scripts/chaos/i18n_core.lua")
ChaosNotify = {send = function(p, title, text, kind) toasts[#toasts + 1] = {player = p, text = text, kind = kind}; return true end}

local nextGuid = 0
local function newPlayer(name, account, lang)
	nextGuid = nextGuid + 1
	local p = {name = name, guid = nextGuid, account = account, premiumDays = 0, messages = {}, cancels = {}, lang = lang or "en"}
	function p:getName() return self.name end
	function p:getGuid() return self.guid end
	function p:getId() return self.guid end
	function p:getAccountId() return self.account end
	function p:isPremium() return self.premiumDays > 0 end
	function p:getPremiumDays() return self.premiumDays end
	function p:addPremiumDays(d) self.premiumDays = self.premiumDays + d end
	function p:sendTextMessage(_, text) self.messages[#self.messages + 1] = text end
	function p:sendCancelMessage(text) self.cancels[#self.cancels + 1] = text end
	function p:sendExtendedOpcode(_, buffer) end
	function p:registerEvent() end
	function p:getGroup() return {getAccess = function() return false end} end
	function p:getAccountType() return 1 end
	players[p.guid] = p
	return p
end
Game = {getPlayers = function() local l = {} for _, p in pairs(players) do l[#l + 1] = p end return l end}
Player = function(x) return players[x] end

-- Chaos.t reads the player's language: pt-BR for those that ask
Chaos.lang = function(p) return p.lang or "en" end

dofile("data/scripts/chaos/pact.lua")
local Pact = ChaosPact
local cfg = Chaos.pactConfig
local Core = ChaosPactCore
Pact.ensureHooks()

local function statusOf(p)
	sent = {}
	registry.ChaosPactExtended.onExtendedOpcode(p, ChaosOpcodes.pact, {action = "sync", data = {}})
	for i = #sent, 1, -1 do if sent[i].action == "status" then return sent[i].data end end
end
local function request(p, action, data)
	sent = {}
	registry.ChaosPactExtended.onExtendedOpcode(p, ChaosOpcodes.pact, {action = action, data = data or {}})
end
local function lastMessage()
	for i = #sent, 1, -1 do if sent[i].action == "message" then return sent[i].data end end
end

-- ---------------------------------------------------------------- the daily claim pays Pact Marks
local A = newPlayer("Ashen", 10)
local A2 = newPlayer("Ashen Two", 10)
DB.pact[10] = {ends = NOW + 20 * DAY, started = NOW - DAY, total = 30, claim = 0, claimed = 0}
local st = statusOf(A)
eq(st.dailyMarks, 5, "the status names the daily Marks") eq(st.dailyCoins, nil, "no daily coins in the status")
eq(st.canClaim, true, "can claim") eq(st.marks, 0, "no Marks yet")
request(A, "claim")
eq(DB.marks[10].balance, 5, "5 Marks credited") eq(DB.marks[10].earned, 5, "earned counted")
eq(DB.pact[10].claimed, 5, "the claim total counts Marks")
check(lastMessage() and lastMessage().text:find("5 Pact Marks", 1, true), "told: 5 Pact Marks")
st = statusOf(A)
eq(st.canClaim, false, "claimed today") eq(st.marks, 5, "balance 5 in the status")
request(A, "claim")
eq(DB.marks[10].balance, 5, "a second claim the same day pays nothing")
check(lastMessage().error == true, "and says so")
request(A2, "claim")
eq(DB.marks[10].balance, 5, "another character of the account cannot claim twice either")
DB.pact[10].claim = 0
local noPact = newPlayer("Plain", 11)
request(noPact, "claim")
eq(DB.marks[11], nil, "no Pact, no Marks")
local coinsAdded = 0
ChaosShop = {addCoins = function(_, c) coinsAdded = coinsAdded + c end, getCoins = function() return 0 end}
request(A, "claim")
eq(coinsAdded, 0, "never any Chaos Coins")
eq(DB.marks[10].balance, 10, "the next day's 5 Marks")

-- ---------------------------------------------------------------- the shelf
DB.marks[10].balance = 149
request(A, "marksBuy", {key = "loot_ember"})
check(lastMessage().error, "149 Marks do not buy a 150 Mark label") eq(DB.marks[10].balance, 149, "nothing taken")
request(A, "marksBuy", {key = "premium:30"})
check(lastMessage().error and lastMessage().text:find("shelf", 1, true), "a key off the shelf is refused")
request(A, "marksBuy", {key = "kill_voidring"})
check(lastMessage().error, "an achievement cosmetic is not on the shelf")
DB.marks[10].balance = 400
request(A, "marksBuy", {key = "loot_ember"})
eq(DB.marks[10].balance, 250, "150 Marks taken") eq(DB.marks[10].spent, 150, "spent counted")
check(cosmeticsOwned[10] and cosmeticsOwned[10].loot_ember, "the cosmetic is granted to the account")
eq(grants[1], "loot_ember:marks", "with the source marks")
check(lastMessage() and not lastMessage().error, "told it was bought")
request(A, "marksBuy", {key = "loot_ember"})
check(lastMessage().error and lastMessage().text:find("owns that cosmetic", 1, true), "owned: not twice") eq(DB.marks[10].balance, 250, "nothing taken twice")
cosmeticsFail = true
request(A, "marksBuy", {key = "chat_cinder"})
check(lastMessage().error, "a failed grant is an error") eq(DB.marks[10].balance, 250, "the Marks are back")
eq(DB.marks[10].spent, 150, "and the spent total") eq(DB.marks[10].earned, 400 - 400 + DB.marks[10].earned, "earned unchanged")
cosmeticsFail = false
st = statusOf(A)
eq(#st.shelf, #cfg.marks.shelf, "the status carries the shelf")
eq(st.shelf[1].owned, true, "Ember Labels shown as owned") eq(st.shelf[4].owned, false, "Cinder not owned")
check(st.shelf[1].name ~= nil and st.shelf[1].name ~= "", "with names")
-- the Marks cap and accrual limit
DB.marks[10].balance = 99998
request(A, "claim") -- claim reset above? the day claimed already: nothing
DB.pact[10].claim = 0
request(A, "claim")
eq(DB.marks[10].balance, 100000, "the balance is capped")
-- no store path takes Marks: the Pact module exposes no coin conversion
eq(Pact.marksToCoins, nil, "Marks do not turn into coins")

-- ---------------------------------------------------------------- the experience the +10% added, per character and month
local X = newPlayer("Xp One", 20)
local X2 = newPlayer("Xp Two", 20)
local Y = newPlayer("Other Account", 21)
Pact.addMonthExp(X, 100) Pact.addMonthExp(X, 250) Pact.addMonthExp(X, 0) Pact.addMonthExp(X, -5)
local mine, all, month = Pact.monthExp(X)
eq(mine, 350, "pending experience counts at once") eq(all, 350, "also for the account") eq(month, monthOf(NOW), "this month")
eq(#DB.xp, 0, "nothing written yet")
Pact.flushXp(X.guid)
eq(#DB.xp, 1, "one write") eq(DB.xp[1].exp, 350, "350 written") eq(DB.xp[1].month, monthOf(NOW), "for this month")
eq(Pact.xpPending[X.guid], nil, "pending cleared")
Pact.addMonthExp(X2, 1000)
Pact.addMonthExp(Y, 777)
mine, all = Pact.monthExp(X)
eq(mine, 350, "this character") eq(all, 350 + 1000, "the account: both characters, not the other account")
Pact.flushXp()
eq(#DB.xp, 3, "everybody flushed") eq(next(Pact.xpPending), nil, "nothing pending")
mine, all = Pact.monthExp(X2)
eq(mine, 1000, "the other character") eq(all, 1350, "same account total")
st = statusOf(X)
eq(st.monthExp, 350, "the status carries the month's experience") eq(st.monthExpAccount, 1350, "and the account's")
-- an older month is not counted
DB.xp[#DB.xp + 1] = {player = X.guid, month = monthOf(NOW) - 1, exp = 99999}
mine = Pact.monthExp(X)
eq(mine, 350, "another month does not count")

-- ---------------------------------------------------------------- expiry warnings
toasts = {}
local W = newPlayer("Warned", 30)
DB.pact[30] = {ends = NOW + 10 * DAY, started = NOW, total = 30, claim = 0, claimed = 0}
Pact.load(30)
eq(Pact.warnExpiry(W, true), false, "10 days left: no warning at login")
DB.pact[30].ends = NOW + 3 * DAY - 60
Pact.load(30)
eq(Pact.warnExpiry(W, true), true, "3 days left: a warning at login")
eq(#toasts, 1, "with a toast") eq(toasts[1].kind, "pact", "of the pact kind")
check(W.messages[#W.messages]:find("ends in 3 days", 1, true), "the chat line says 3 days: " .. tostring(W.messages[#W.messages]))
eq(toasts[1].text, W.messages[#W.messages], "the toast says the same")
eq(Pact.warnExpiry(W, false), false, "online: not again at the same level")
DB.pact[30].ends = NOW + DAY - 60
Pact.load(30)
eq(Pact.warnExpiry(W, false), true, "online, the last day: the second warning")
check(W.messages[#W.messages]:find("within 24 hours", 1, true), "24 hours: " .. tostring(W.messages[#W.messages]))
eq(Pact.warnExpiry(W, false), false, "and only once")
eq(Pact.warnExpiry(W, true), true, "a new login in the window warns again")
eq(#toasts, 3, "three toasts so far")
-- renewed: the warning clears, a later window warns again online
DB.pact[30].ends = NOW + 40 * DAY
Pact.load(30)
eq(Pact.warnExpiry(W, false), false, "renewed: nothing") eq(Pact.warned[W.guid], nil, "and forgotten")
DB.pact[30].ends = NOW + 2 * DAY
Pact.load(30)
eq(Pact.warnExpiry(W, false), true, "online, the window opens: the first warning")
-- the Pact and Premium end together: the Completo text
local B = newPlayer("Both", 31)
B.premiumDays = 2
DB.pact[31] = {ends = NOW + 2 * DAY, started = NOW, total = 30, claim = 0, claimed = 0}
Pact.load(31)
Pact.warnExpiry(B, true)
check(B.messages[#B.messages]:find("Pacto Completo", 1, true) and B.messages[#B.messages]:find("Premium", 1, true), "both ending: names the Pacto Completo")
-- pt-BR
local P = newPlayer("Portuguesa", 32, "pt-BR")
DB.pact[32] = {ends = NOW + 2 * DAY, started = NOW, total = 30, claim = 0, claimed = 0}
Pact.load(32)
Pact.warnExpiry(P, true)
check(P.messages[#P.messages]:find("termina em 3 dias", 1, true) or P.messages[#P.messages]:find("termina em 2 dias", 1, true), "pt-BR: " .. tostring(P.messages[#P.messages]))
P.premiumDays = 1
DB.pact[32].ends = NOW + DAY - 60
Pact.load(32)
Pact.warnExpiry(P, true)
check(P.messages[#P.messages]:find("menos de 24 horas", 1, true) and P.messages[#P.messages]:find("Pacto Completo", 1, true), "pt-BR, both, the last day: " .. tostring(P.messages[#P.messages]))
-- an ended Pact warns nothing
local E = newPlayer("Ended", 33)
DB.pact[33] = {ends = NOW - 5, started = NOW - 30 * DAY, total = 30, claim = 0, claimed = 0}
Pact.load(33)
eq(Pact.warnExpiry(E, true), false, "ended: no warning")

-- ---------------------------------------------------------------- the stacking cap for bundles and the frame
local C = newPlayer("Capped", 40)
DB.pact[40] = {ends = NOW + 190 * DAY, started = NOW, total = 30, claim = 0, claimed = 0}
Pact.load(40)
check(Pact.checkDays(C, 180) ~= nil, "180 days on top of 190 pass the cap")
eq(Pact.checkDays(C, 30), nil, "30 days on top of 190 fit")
DB.pact[40].ends = 0
Pact.load(40)
eq(Pact.checkDays(C, 180), nil, "180 days fit on no Pact")
eq(Pact.frameOf(C), nil, "no Pact: no frame")
DB.pact[40].ends = NOW + DAY
Pact.load(40)
eq(Pact.frameOf(C), "pactbound", "an active Pact: the Pactbound frame")
-- the bundle days: the Pact is extended by the days of the part, with the source
C.premiumDays = 0
local ends = DB.pact[40].ends
check(Pact.grantDays(C, 90, "complete"), "grantDays 90 days")
eq(DB.pact[40].ends, ends + 90 * DAY, "stacked on the time left")

-- ---------------------------------------------------------------- the login
local L = newPlayer("Login", 50)
DB.pact[50] = {ends = NOW + 2 * DAY, started = NOW, total = 30, claim = 0, claimed = 0}
registry.ChaosPactLogin.onLogin(L)
local text = table.concat(L.messages, "\n")
check(text:find("Pact Marks wait", 1, true), "the login line names the Marks, not coins")
check(not text:find("Chaos Coins", 1, true), "and no Chaos Coins")
check(text:find("ends in", 1, true), "plus the expiry warning")

-- the logout writes what is pending
Pact.addMonthExp(L, 40)
registry.ChaosPactLogout.onLogout(L)
eq(DB.xp[#DB.xp].exp, 40, "logout flushes the experience")

if failures > 0 then
	print(string.format("pact_engine_test: %d of %d checks FAILED", failures, checks))
	os.exit(1)
end
print(string.format("pact_engine_test: %d checks OK", checks))
