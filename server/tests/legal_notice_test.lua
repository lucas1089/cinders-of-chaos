-- Run from the server/ folder: luajit tests/legal_notice_test.lua (CI runs it with LuaJIT and Lua 5.3).
-- The in-game notice for accounts without the acceptance of the current Terms of Use and Privacy Policy
-- (data/scripts/chaos/legal_notice_core.lua, legal_notice_config.lua): the version check, the SQL, when it shows, the
-- texts and the link (the website's accept page exists and the website setup writes the version). Then legal_notice.lua
-- against a mocked engine: login -> delayed check, an account without the row gets the message and the window, one with
-- it gets nothing, no version = no notice, the version cache.
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
dofile("data/scripts/chaos/legal_notice_core.lua")
local L = ChaosLegalNoticeCore
local cfg = dofile("data/scripts/chaos/legal_notice_config.lua")
local V = "0123456789abcdef"

-- ====================================================================== core
eq(L.cleanVersion(V), V, "version")
eq(L.cleanVersion(" 0123456789ABCDEF "), V, "trimmed, lower case")
eq(L.cleanVersion("0123"), nil, "short")
eq(L.cleanVersion("0123456789abcdeg"), nil, "not hex")
eq(L.cleanVersion("x' OR 1=1 -- abcd"), nil, "injection")
eq(L.cleanVersion(nil), nil, "nil")
ok(L.versionSql():find("`server_config`", 1, true) and L.versionSql():find("'chaos_legal_version'", 1, true), "version query")
eq(L.acceptedSql(41, V), "SELECT `id` FROM `chaos_legal_acceptance` WHERE `account_id` = 41 AND `version` = '" .. V .. "' LIMIT 1", "accepted query")
eq(L.acceptedSql(0, V), nil, "no account")
eq(L.acceptedSql(41, "bad"), nil, "bad version")
ok(L.needsNotice(cfg, V, false), "no row: notice")
ok(not L.needsNotice(cfg, V, true), "row: no notice")
ok(not L.needsNotice(cfg, nil, false), "no version: no notice")
ok(not L.needsNotice({enabled = false, url = cfg.url}, V, false), "disabled")
local en, pt = L.message(cfg)
ok(en:find(cfg.url, 1, true) and pt:find(cfg.url, 1, true), "both texts carry the link")
ok(en:find("Terms of Use", 1, true) and pt:find("Termos de Uso", 1, true), "both languages")
ok(L.popup(cfg):find(en, 1, true) and L.popup(cfg):find(pt, 1, true), "popup has both")
ok(not L.cacheFresh(nil, 100, cfg), "no cache")
ok(L.cacheFresh({at = 100}, 100 + cfg.cacheSeconds - 1, cfg), "fresh")
ok(not L.cacheFresh({at = 100}, 100 + cfg.cacheSeconds, cfg), "stale")
ok(not L.cacheFresh({at = 100}, 50, cfg), "clock moved back: stale")

-- the link is the website's accept page; the website setup writes the version the server reads
eq(cfg.url, "page.php?plugin=chaos&p=accept", "url")
ok(readFile("../website/overlay/plugins/chaos/pages/accept.php") ~= "", "website accept page exists")
local setup = readFile("../website/setup/chaos_setup.php")
ok(setup:find("'chaos_legal_version'", 1, true) ~= nil, "website setup writes server_config chaos_legal_version")
local lib = readFile("../website/overlay/plugins/chaos/legal_lib.php")
ok(lib:find("CHAOS_LEGAL_ACCEPT_URL', 'page.php?plugin=chaos&p=accept'", 1, true) ~= nil, "same url as the website")
ok(lib:find("substr(hash('sha256', $all), 0, 16)", 1, true) ~= nil, "website version is 16 hex digits")

-- ====================================================================== engine
local serverConfig = {chaos_legal_version = V}
local acceptance = {{account_id = 41, version = V}}
local queries = 0
local cursor, nextId = {}, 0
db = {
	escapeString = function(s) return "'" .. tostring(s) .. "'" end,
	storeQuery = function(q)
		queries = queries + 1
		local rows = {}
		if q:find("FROM `server_config`", 1, true) then
			if serverConfig.chaos_legal_version then rows = {{value = serverConfig.chaos_legal_version}} end
		elseif q:find("FROM `chaos_legal_acceptance`", 1, true) then
			local acc, ver = q:match("`account_id` = (%d+) AND `version` = '(%x+)'")
			for _, r in ipairs(acceptance) do
				if r.account_id == tonumber(acc) and r.version == ver then rows = {{id = 1}} end
			end
		else
			error("unexpected query " .. q)
		end
		if #rows == 0 then return false end
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
local function newPlayer(id, account)
	local p = {id = id, account = account, msgs = {}, popups = {}}
	function p:getId() return self.id end
	function p:getAccountId() return self.account end
	function p:sendTextMessage(kind, text) self.msgs[#self.msgs + 1] = {kind, text} end
	function p:popupFYI(text) self.popups[#self.popups + 1] = text end
	players[id] = p
	return p
end
function Player(id) return players[id] end
local function runTimers()
	local t = timers
	timers = {}
	local unpackArgs = table.unpack or unpack
	for _, e in ipairs(t) do e.fn(unpackArgs(e.args)) end
end

local LN = dofile("data/scripts/chaos/legal_notice.lua")
ok(events.ChaosLegalNoticeLogin ~= nil and events.ChaosLegalNoticeLogin.t == "login", "login event")

local beta = newPlayer(1001, 7)
ok(events.ChaosLegalNoticeLogin.onLogin(beta), "login allowed (nothing blocked)")
eq(#timers, 1, "delayed check")
eq(timers[1].ms, cfg.delayMs, "after the delay")
runTimers()
eq(#beta.msgs, 2, "two lines")
ok(beta.msgs[1][2]:find(cfg.url, 1, true) ~= nil, "message has the link")
eq(beta.msgs[1][1], MESSAGE_EVENT_ADVANCE, "a visible message")
eq(#beta.popups, 1, "a window")

local done = newPlayer(1002, 41)
events.ChaosLegalNoticeLogin.onLogin(done)
runTimers()
eq(#done.msgs, 0, "accepted account: no notice")
eq(#done.popups, 0, "accepted account: no window")

local q0 = queries
events.ChaosLegalNoticeLogin.onLogin(newPlayer(1003, 8))
runTimers()
eq(queries - q0, 1, "version cached: one query (the acceptance)")

ok(not LN.check(9999), "logged out before the check: nothing")

LN.cache = nil
serverConfig.chaos_legal_version = nil
local noSite = newPlayer(1004, 9)
events.ChaosLegalNoticeLogin.onLogin(noSite)
runTimers()
eq(#noSite.msgs, 0, "no version (site not installed): no notice")

print(string.format("legal_notice_test: %d checks, %d failures", checks, fails))
if fails > 0 then
	os.exit(1)
end
