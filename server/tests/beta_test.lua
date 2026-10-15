-- Run from the server/ folder: luajit tests/beta_test.lua (CI runs it with LuaJIT and Lua 5.3).
-- The beta switch (data/scripts/chaos/beta_core.lua, beta_config.lua): the starter coins are on only in the beta, due
-- at a character's first login, the claim SQL. Then beta.lua against a mocked engine with an in-memory table: the
-- first character of an account gets the coins once, a second character and a restart get nothing, beta off = nothing,
-- the message comes later in the player's language.
local checks, fails = 0, 0
local function ok(cond, what)
	checks = checks + 1
	if not cond then
		fails = fails + 1
		print("FAIL " .. tostring(what))
	end
end
local function eq(a, b, what)
	ok(a == b, (what or "check") .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end
local function readFile(path)
	local f = io.open(path, "r")
	if not f then
		return ""
	end
	local s = f:read("*a")
	f:close()
	return s
end

dofile("data/scripts/chaos/chaos_constants.lua")
dofile("data/scripts/chaos/beta_core.lua")
local B = ChaosBetaCore
local cfg = dofile("data/scripts/chaos/beta_config.lua")

-- ====================================================================== core and config
eq(cfg.enabled, true, "the beta is on for now (off at launch)")
eq(cfg.starterCoins, 5000, "5,000 starter coins")
eq(B.TABLE, Chaos.tables.betaGrants, "table name in chaos_constants.lua")
eq(B.starterCoins(cfg), 5000, "starter coins")
eq(B.starterCoins({enabled = false, starterCoins = 5000}), 0, "beta off: none")
eq(B.starterCoins({enabled = true, starterCoins = 0}), 0, "zero: none")
eq(B.starterCoins({enabled = true, starterCoins = -5}), 0, "negative: none")
eq(B.starterCoins(nil), 0, "no config")
ok(B.dueAtLogin(cfg, 0), "first login: due")
ok(not B.dueAtLogin(cfg, 1700000000), "later login: not due")
ok(B.dueAtLogin({enabled = true, starterCoins = 10, firstLoginOnly = false}, 1700000000), "any login when firstLoginOnly is off")
ok(not B.dueAtLogin({enabled = false, starterCoins = 5000}, 0), "beta off: not due")
eq(B.claimSql(7, 12, 5000, 99),
	"INSERT IGNORE INTO `chaos_beta_grants` (`account_id`, `kind`, `coins`, `player_id`, `granted_at`) VALUES (7, 'starter', 5000, 12, 99)",
	"claim sql")
eq(B.claimSql(0, 12, 5000, 99), nil, "no account")
eq(B.claimSql("7 OR 1=1", 12, 5000, 99), nil, "not a number")
eq(B.grantedSql(7), "SELECT `coins` FROM `chaos_beta_grants` WHERE `account_id` = 7 LIMIT 1", "granted sql")
ok(B.claimed(1), "row made")
ok(not B.claimed(0), "row there before")
ok(not B.claimed(nil), "no answer")

-- the SQL file has the same table as the engine's CREATE
local sql = readFile("sql/chaos_beta.sql")
ok(sql:find("CREATE TABLE IF NOT EXISTS `chaos_beta_grants`", 1, true) ~= nil, "sql file")
ok(sql:find("PRIMARY KEY (`account_id`)", 1, true) ~= nil and B.SCHEMA:find("PRIMARY KEY (`account_id`)", 1, true) ~= nil,
	"one row per account")
-- the pt-BR text exists
local pt = dofile("data/scripts/chaos/i18n_strings.lua")["pt-BR"]
local key = readFile("data/scripts/chaos/beta.lua"):match('Chaos%.t%(p, "([^"]+)"')
ok(key ~= nil and pt[key] ~= nil, "pt-BR message")

-- ====================================================================== engine
local grants, coins = {}, {}
local lastRowCount = 0
local cursor, nextId = {}, 0
db = {
	escapeString = function(s) return "'" .. tostring(s) .. "'" end,
	query = function(q)
		if q:find("CREATE TABLE", 1, true) then
			return true
		end
		local acc, kind, n, pid, at = q:match("VALUES %((%d+), '(%a+)', (%d+), (%d+), (%d+)%)")
		if q:find("INSERT IGNORE INTO `chaos_beta_grants`", 1, true) and acc then
			acc = tonumber(acc)
			if grants[acc] then
				lastRowCount = 0
			else
				grants[acc] = {kind = kind, coins = tonumber(n), player = tonumber(pid), at = tonumber(at)}
				lastRowCount = 1
			end
			return true
		end
		error("unexpected query " .. q)
	end,
	storeQuery = function(q)
		local rows
		if q:find("ROW_COUNT()", 1, true) then
			rows = {{n = lastRowCount}}
		else
			error("unexpected query " .. q)
		end
		nextId = nextId + 1
		cursor[nextId] = {rows = rows, i = 1}
		return nextId
	end
}
result = {
	getNumber = function(id, col) return tonumber(cursor[id].rows[cursor[id].i][col]) or 0 end,
	getString = function(id, col) return tostring(cursor[id].rows[cursor[id].i][col] or "") end,
	next = function(id) cursor[id].i = cursor[id].i + 1; return cursor[id].rows[cursor[id].i] ~= nil end,
	free = function(id) cursor[id] = nil end
}
ChaosShop = {
	addCoins = function(acc, n) coins[acc] = (coins[acc] or 0) + n end,
	getCoins = function(acc) return coins[acc] or 0 end
}
MESSAGE_EVENT_ADVANCE = 19
local events, timers = {}, {}
function CreatureEvent(name)
	local o = {name = name}
	function o:type(t) o.t = t end
	function o:register() events[name] = o end
	return o
end
function addEvent(fn, ms, ...)
	timers[#timers + 1] = {fn = fn, ms = ms, args = {...}}
end
local players = {}
local function newPlayer(id, account, lastLogin, lang)
	local p = {id = id, account = account, last = lastLogin or 0, msgs = {}, storage = {}}
	function p:getId() return self.id end
	function p:getGuid() return self.id - 1000 end
	function p:getName() return "Tester" .. self.id end
	function p:getAccountId() return self.account end
	function p:getLastLoginSaved() return self.last end
	function p:getStorageValue(k) return self.storage[k] or -1 end
	function p:setStorageValue(k, v) self.storage[k] = v end
	function p:sendTextMessage(kind, text) self.msgs[#self.msgs + 1] = {kind, text} end
	players[id] = p
	if lang then
		Chaos.setLang(p, lang)
	end
	return p
end
function Player(id) return players[id] end
local function runTimers()
	local t = timers
	timers = {}
	local unpackArgs = table.unpack or unpack
	for _, e in ipairs(t) do e.fn(unpackArgs(e.args)) end
end
local function login(p)
	return events.ChaosBetaLogin.onLogin(p)
end
local realPrint = print
print = function() end -- the engine's log lines

dofile("data/scripts/chaos/beta.lua")
ok(events.ChaosBetaLogin ~= nil and events.ChaosBetaLogin.t == "login", "login event")
eq(Chaos.beta.enabled, true, "Chaos.beta is the switch")
eq(Chaos.beta.starterCoins, 5000, "Chaos.beta.starterCoins")

-- the first character of account 7: 5,000 coins and the message, later
local first = newPlayer(1001, 7, 0)
ok(login(first), "login allowed")
eq(coins[7], 5000, "first character: 5,000 coins to the account")
eq(grants[7] and grants[7].coins, 5000, "grant recorded")
eq(grants[7] and grants[7].player, 1, "with the character")
eq(#first.msgs, 0, "message not yet")
eq(#timers, 1, "message later")
eq(timers[1].ms, cfg.delayMs, "after the delay")
runTimers()
eq(#first.msgs, 1, "one message")
eq(first.msgs[1][1], MESSAGE_EVENT_ADVANCE, "a visible message")
ok(first.msgs[1][2]:find("5000 Chaos Coins", 1, true) and first.msgs[1][2]:find("wiped at launch", 1, true), "English text")

-- the same character again: no first login, nothing
first.last = 1700000000
login(first)
runTimers()
eq(coins[7], 5000, "relog: no more coins")
eq(#first.msgs, 1, "relog: no message")

-- a second (new) character of the same account: no grant (alts cannot farm)
local alt = newPlayer(1002, 7, 0)
login(alt)
runTimers()
eq(coins[7], 5000, "second character: no more coins")
eq(#alt.msgs, 0, "second character: no message")

-- a restart: the module loads again, the grants table stays
ChaosBeta = nil
dofile("data/scripts/chaos/beta.lua")
local alt2 = newPlayer(1003, 7, 0)
login(alt2)
runTimers()
eq(coins[7], 5000, "after a restart: still once")
ok(not ChaosBeta.grantStarter(alt2), "direct call: already granted")
eq(coins[7], 5000, "direct call gave nothing")

-- another account, a pt-BR player
local br = newPlayer(1004, 8, 0, "pt-BR")
login(br)
runTimers()
eq(coins[8], 5000, "second account: its own grant")
ok(br.msgs[1] and br.msgs[1][2]:find("moedas de teste do beta", 1, true), "pt-BR message")

-- a character made before the beta switch: its login is not first, so nothing; the account gets it with a new one
local old = newPlayer(1005, 9, 1690000000)
login(old)
eq(coins[9], nil, "old character: nothing")
eq(grants[9], nil, "old character: no grant row")
login(newPlayer(1006, 9, 0))
eq(coins[9], 5000, "new character of that account: the grant")

-- beta off: nothing at all
Chaos.beta.enabled = false
local off = newPlayer(1007, 10, 0)
login(off)
runTimers()
eq(coins[10], nil, "beta off: no coins")
eq(grants[10], nil, "beta off: no grant row")
eq(#off.msgs, 0, "beta off: no message")
Chaos.beta.enabled = true

-- the store not loaded: nothing recorded, so the grant comes later
local saved = ChaosShop
ChaosShop = nil
login(newPlayer(1008, 11, 0))
eq(grants[11], nil, "no store: no grant row")
ChaosShop = saved
login(newPlayer(1009, 11, 0))
eq(coins[11], 5000, "store back: the grant")

print = realPrint
print(string.format("beta_test: %d checks, %d failures", checks, fails))
if fails > 0 then
	os.exit(1)
end
