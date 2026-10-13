-- Run from the server/ folder: luajit tests/bazaar_test.lua (and lua5.3; CI runs both)
-- Character Bazaar, the game server's part: the config (bazaar_config.lua: fee 5-10 %, 1-7 days), the pure rules
-- (bazaar_core.lua: the lock, the fee, the bid step) and the login lock of bazaar.lua against a mocked engine: a listed
-- character (active or settling) is refused at login and the refusal logged; a sold, cancelled or expired listing
-- locks nothing; staff are never locked; the sweep removes a listed character that is online. The SQL file and the
-- engine file create the same tables.
dofile("data/scripts/chaos/bazaar_core.lua")
local B = ChaosBazaarCore
local cfg = dofile("data/scripts/chaos/bazaar_config.lua")

local n = 0
local function eq(a, b, m)
	n = n + 1
	if a ~= b then
		error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2)
	end
end

-- ---------------------------------------------------------------- config and rules
local problems = B.validate(cfg)
for _, p in ipairs(problems) do
	print("problem: " .. p)
end
eq(#problems, 0, "shipped config validates")
eq(cfg.feePct >= 5 and cfg.feePct <= 10, true, "fee 5-10 %")
local bad = {}
for k, v in pairs(cfg) do
	bad[k] = v
end
bad.feePct = 12
eq(#B.validate(bad) > 0, true, "a 12 % fee is refused")
bad.feePct, bad.maxDays = 8, 14
eq(#B.validate(bad) > 0, true, "14 days refused")

eq(B.fee(1000, cfg), math.floor(1000 * cfg.feePct / 100), "fee of 1000")
eq(B.fee(5, cfg), 1, "at least one coin")
eq(B.fee(0, cfg), 0, "no sale, no fee")
eq(B.minNextBid(0, 300, cfg), 300, "first bid: the minimum")
eq(B.minNextBid(0, 10, cfg), cfg.minPrice, "never under the bazaar minimum")
eq(B.minNextBid(1000, 300, cfg), 1000 + math.max(cfg.minStep, 1000 * cfg.minStepPct / 100), "step on 1000")
eq(B.minNextBid(100, 100, cfg), 100 + cfg.minStep, "the step's floor in coins")

eq(B.locks({}, cfg), nil, "no listing")
eq(B.locks({{id = 1, status = "sold", ends_at = 5}, {id = 2, status = "cancelled", ends_at = 9}}, cfg), nil, "ended listings lock nothing")
eq(B.locks({{id = 1, status = "expired", ends_at = 5}, {id = 3, status = "active", ends_at = 9}}, cfg).id, 3, "active locks")
eq(B.locks({{id = 4, status = "settling", ends_at = 9}}, cfg).id, 4, "settling locks")
eq(B.lockMessage({ends_at = os.time({year = 2026, month = 11, day = 2, hour = 20, min = 0})}, cfg):find("2026-11-02 20:00", 1, true) ~= nil,
	true, "the message names the end")

-- ---------------------------------------------------------------- the login lock, mocked engine
local events, globals = {}, {}
CreatureEvent = function(name)
	local e = {register = function() end, type = function() end}
	events[name] = e
	return e
end
GlobalEvent = function(name)
	local e = {register = function() end, interval = function() end}
	globals[name] = e
	return e
end
MESSAGE_EVENT_ADVANCE = 2
local logged, queries = {}, {}
db = {
	escapeString = function(s) return "'" .. tostring(s):gsub("'", "''") .. "'" end,
	query = function(q) queries[#queries + 1] = q return true end,
	asyncQuery = function(q) logged[#logged + 1] = q end
}
local online = {}
Game = {getPlayers = function() return online end}
dofile("data/scripts/chaos/chaos_constants.lua")
local listings = {} -- player id -> rows
Chaos.select = function(q, cols)
	local guid = tonumber(q:match("`player_id` = (%d+)"))
	assert(q:find("chaos_bazaar_listings", 1, true), "only the listings are read: " .. q)
	local out = {}
	for _, r in ipairs(listings[guid] or {}) do
		if r.status == "active" or r.status == "settling" then -- the query's IN (...)
			out[#out + 1] = r
		end
	end
	return out
end
local function newPlayer(guid, group)
	local p = {guid = guid, removed = false, saved = false, texts = {}}
	function p:getGuid() return self.guid end
	function p:getAccountId() return 100 + self.guid end
	function p:getName() return "Char" .. self.guid end
	function p:getGroup() return {getId = function() return group or 1 end} end
	function p:sendTextMessage(_, t) self.texts[#self.texts + 1] = t end
	function p:save() self.saved = true end
	function p:remove() self.removed = true end
	return p
end
dofile("data/scripts/chaos/bazaar.lua")
local login = events.ChaosBazaarLogin.onLogin
globals.ChaosBazaarStartup.onStartup()
eq(#queries, 3, "three tables created at startup")

eq(login(newPlayer(1)), true, "a character never listed logs in")
listings[2] = {{id = 7, status = "active", ends_at = os.time() + 3600}}
eq(login(newPlayer(2)), false, "an active listing refuses the login")
eq(logged[#logged]:find("login_refused", 1, true) ~= nil, true, "the refusal is logged")
listings[3] = {{id = 8, status = "settling", ends_at = os.time() - 5}}
eq(login(newPlayer(3)), false, "a listing being settled refuses the login")
listings[4] = {{id = 9, status = "sold", ends_at = os.time() - 5}, {id = 10, status = "cancelled", ends_at = os.time() - 99}}
eq(login(newPlayer(4)), true, "sold / cancelled listings lock nothing (a bought character logs in for its new owner)")
eq(login(newPlayer(2, 5)), true, "staff (group 5) are never locked")
Chaos.bazaarConfig.enabled = false
eq(login(newPlayer(2)), true, "switched off: no lock")
Chaos.bazaarConfig.enabled = true
-- a broken query (no tables yet) never locks anyone out
local sel = Chaos.select
Chaos.select = function() error("no table") end
eq(login(newPlayer(2)), true, "no tables: logs in")
Chaos.select = sel

-- the sweep: a listed character online is saved and removed, the others stay
local listed, free = newPlayer(2), newPlayer(1)
online = {listed, free}
eq(ChaosBazaar.sweep(), 1, "one removed")
eq(listed.removed and listed.saved, true, "listed character saved and removed")
eq(free.removed, false, "the other stays")
eq(listed.texts[1], cfg.messages.kicked, "told why")

-- ---------------------------------------------------------------- tables agree
local function read(path)
	local f = assert(io.open(path, "rb"))
	local text = f:read("*a")
	f:close()
	return text
end
local sql, engine = read("sql/chaos_bazaar.sql"), read("data/scripts/chaos/bazaar.lua")
for _, t in pairs(cfg.tables) do
	eq(sql:find("CREATE TABLE IF NOT EXISTS `" .. t .. "`", 1, true) ~= nil, true, "sql file creates " .. t)
	eq(engine:find("CREATE TABLE IF NOT EXISTS `" .. t .. "`", 1, true) ~= nil, true, "engine creates " .. t)
end
local site = read("../website/overlay/plugins/chaos/install.sql")
for _, t in pairs(cfg.tables) do
	eq(site:find("CREATE TABLE IF NOT EXISTS `" .. t .. "`", 1, true) ~= nil, true, "website install.sql creates " .. t)
end

print("bazaar_test: " .. n .. " checks OK")
