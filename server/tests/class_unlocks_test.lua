-- Run from the server/ folder: luajit tests/class_unlocks_test.lua (mock engine API; CI runs it with luajit and lua5.3)
-- Covers the class lock: the config (vocation ids, store offers, placeholder prices), the pure rules
-- (class_unlocks_core.lua: vocation -> class, the decision, staff bypass, lock messages, pluggable methods, SQL) and the
-- engine part (class_unlocks.lua: isUnlocked / canUseVocation for players and account ids, the store entry, the
-- account-wide grant, the login restriction and its callbacks, automatic unlocks, the staff command).
local n = 0
setmetatable(_G, {__index = function(t, k)
	if type(k) == "string" and k:match("^[A-Z_0-9]+$") then n = n + 1; rawset(t, k, n); return n end
end})

local function eq(a, b, m) if a ~= b then error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2) end end

-- ================================================================== pure part
dofile("data/scripts/chaos/class_unlocks_core.lua")
local K = ChaosClassUnlocksCore
local cfg = K.config

-- ------------------------------------------------------------------ config
eq(cfg.classes.necromancer.vocations[1], 20, "necromancer 20"); eq(cfg.classes.necromancer.vocations[3], 22)
eq(cfg.classes.monk.vocations[1], 17, "monk 17"); eq(cfg.classes.monk.vocations[3], 19)
eq(cfg.classes.templar.vocations[1], 23, "templar 23"); eq(cfg.classes.templar.vocations[3], 25)
for key, class in pairs(cfg.classes) do
	eq(class.locked, true, key .. " locked")
	eq(class.unlock.store, nil, key .. ": not sold (owner rule 2026-10-15, earned by play only)")
	eq(class.unlock.level and class.unlock.level.min, 200, key .. " free at level 200")
	eq(type(class.icon), "number", key .. " icon")
end
eq(table.concat(K.lockedClasses(), ","), "monk,necromancer,templar", "locked classes, sorted")

-- ------------------------------------------------------------------ vocation -> class
for v = 17, 19 do eq(K.classOfVocation(v), "monk", "voc " .. v) end
for v = 20, 22 do eq(K.classOfVocation(v), "necromancer", "voc " .. v) end
for v = 23, 25 do eq(K.classOfVocation(v), "templar", "voc " .. v) end
for _, v in ipairs({0, 1, 3, 4, 5, 7, 8, 10, 11, 12, 13, 14, 15, 16, 26}) do eq(K.classOfVocation(v), nil, "voc " .. v) end
eq(K.classOfOffer("unlockTemplar"), nil, "no class is sold any more"); eq(K.classOfOffer("unlockMonk"), nil)
eq(K.classOfOffer("autoSeller"), nil, "other unlocks are not classes")

-- ------------------------------------------------------------------ decision and bypass
local ok, msg, key = K.decide(23, {}, 1, 1)
eq(ok, false, "templar locked"); eq(key, "templar")
assert(msg:find("Templar is locked") and msg:find("level 200") and not msg:find("store"), "message names the level, no store: " .. msg)
eq(K.decide(24, {templar = true}, 1, 1), true, "unlocked templar -> inquisitor ok")
eq(K.decide(24, {monk = true}, 1, 1), false, "another class's unlock does not count")
eq(K.decide(4, {}, 1, 1), true, "warrior is never locked")
eq(K.decide(21, {}, 4, 1), true, "gamemaster group bypasses")
eq(K.decide(21, {}, 3, 1), false, "senior tutor does not")
eq(K.decide(18, {}, 1, 5), true, "community manager account bypasses")
eq(K.decide(18, {}, 1, 6), true, "god account bypasses")
eq(K.decide(18, {}, 1, 4), false, "gamemaster account type on a player group does not")
eq(K.decide(18, nil, 1, 1), false, "no set")

-- an unlocked class flag off: not locked any more, no gate
local custom = {table = "t", bypass = {minGroup = 4, minAccountType = 5}, login = cfg.login,
	classes = {x = {name = "X", vocations = {30}, locked = false, unlock = {store = {offer = "unlockX", cost = 1}}}}}
eq(K.decide(30, {}, 1, 1, custom), true, "locked = false opens the class")
eq(K.isLocked("x", custom), false)

-- ------------------------------------------------------------------ pluggable methods
local multi = {table = "t", bypass = {minGroup = 4, minAccountType = 5}, login = cfg.login, classes = {
	q = {name = "Questy", vocations = {40}, locked = true, unlock = {
		store = {offer = "unlockQ", cost = 100}, level = {min = 500},
		quest = {storage = 9000, value = 2, text = "finish the Sunken Choir quest"}}}}}
msg = K.lockMessage("q", multi)
assert(msg:find("level 500") and msg:find("Sunken Choir") and msg:find("100 Chaos Coins"), "all ways listed: " .. msg)
eq(K.autoUnlock("q", {level = 499}, multi), nil, "level 499 not yet")
eq(K.autoUnlock("q", {level = 500}, multi), "level", "level 500 unlocks")
local st = {[9000] = 1}
eq(K.autoUnlock("q", {level = 1, storage = function(k) return st[k] end}, multi), nil, "quest step 1 not yet")
st[9000] = 2
eq(K.autoUnlock("q", {level = 1, storage = function(k) return st[k] end}, multi), "quest", "quest done unlocks")
local storeOnly = {table = "t", bypass = cfg.bypass, login = cfg.login,
	classes = {s = {name = "S", vocations = {60}, locked = true, unlock = {store = {offer = "unlockS", cost = 1}}}}}
eq(K.autoUnlock("s", {level = 5000}, storeOnly), nil, "the store method never unlocks by itself")
eq(K.autoUnlock("templar", {level = 199}), nil, "the live config: below level 200 only the store")
eq(K.autoUnlock("templar", {level = 200}), "level", "the live config: level 200 unlocks for free")
-- a new kind without touching the gate
K.registerMethod("event", {describe = function(spec) return "win " .. spec.name end,
	check = function(spec, facts) return facts.won == spec.name end})
local ev = {table = "t", bypass = cfg.bypass, login = cfg.login,
	classes = {e = {name = "E", vocations = {50}, locked = true, unlock = {event = {name = "the Midwinter Joust"}}}}}
assert(K.lockMessage("e", ev):find("win the Midwinter Joust"), "custom method described")
eq(K.autoUnlock("e", {won = "the Midwinter Joust"}, ev), "event", "custom method checked")
eq(K.decide(50, {}, 1, 1, ev), false, "gate unchanged: still locked until granted")
eq(K.decide(50, {e = true}, 1, 1, ev), true)

-- ------------------------------------------------------------------ grouped status (Character Info)
local gs = K.lockGroups(function() return false end)
eq(#gs.unlocked, 0, "nothing unlocked"); eq(#gs.groups, 1, "the three level-200 classes form one group")
eq(table.concat(gs.groups[1].names, ", "), "Monk, Necromancer, Templar", "sorted names")
eq(gs.groups[1].level, 200, "level group")
gs = K.lockGroups(function(key) return key == "monk" end)
eq(gs.unlocked[1], "Monk", "unlocked listed"); eq(#gs.groups[1].names, 2, "two still locked")
local mixed = {table = "t", bypass = cfg.bypass, login = cfg.login, classes = {
	a = {name = "A", vocations = {60}, locked = true, unlock = {level = {min = 200}}},
	b = {name = "B", vocations = {61}, locked = true, unlock = {event = {name = "the Joust"}}}}}
gs = K.lockGroups(function() return false end, mixed)
eq(#gs.groups, 2, "different ways, different groups"); eq(gs.groups[2].level, nil, "no level for a custom way")
eq(gs.groups[2].how, "win the Joust", "the way described")

-- ------------------------------------------------------------------ SQL
assert(K.sqlCreate():find("CREATE TABLE IF NOT EXISTS `chaos_class_unlocks`"), "create")
eq(K.sqlSelect(42), "SELECT `class_key` FROM `chaos_class_unlocks` WHERE `account_id` = 42")
eq(K.sqlInsert(42, "templar", "store", 1000),
	"INSERT IGNORE INTO `chaos_class_unlocks` (`account_id`, `class_key`, `source`, `created`) VALUES (42, 'templar', 'store', 1000)")
eq(K.sqlInsert(42, "x'; DROP TABLE players; --", "store", 1), nil, "only plain keys reach the database")
eq(K.sqlInsert(42, "templar", "a b", 1), nil, "source too")
eq(K.sqlDelete(42, "monk"), "DELETE FROM `chaos_class_unlocks` WHERE `account_id` = 42 AND `class_key` = 'monk'")
local set = K.toSet({{class_key = "monk"}, {class_key = ""}, {class_key = "templar"}})
eq(set.monk, true); eq(set.templar, true); eq(set[""], nil)

-- ================================================================== engine part (mocks)
local callbacks, events, talks = {}, {}, {}
local function obj(store, name)
	local o = {}
	function o:register() if store and name then store[name] = o end end
	function o:separator() end
	function o:interval() end
	return o
end
function CreatureEvent(name) return obj(events, name) end
function GlobalEvent(name) return obj(events, name) end
function TalkAction(words) return obj(talks, words) end
local pendingCb
EventCallback = setmetatable({}, {
	__index = function(_, k)
		if k == "register" then
			return function(_, index) callbacks[#callbacks + 1] = {name = pendingCb[1], fn = pendingCb[2]} end
		end
	end,
	__newindex = function(_, k, v) pendingCb = {k, v} end
})
local function callback(name)
	for _, c in ipairs(callbacks) do if c.name == name then return c.fn end end
end

-- a tiny database: rows of chaos_class_unlocks, players(name, account_id, level)
local rows, chars, queries = {}, {}, {}
local resultSets, nextId = {}, 0
local function store(list)
	if #list == 0 then return nil end
	nextId = nextId + 1
	resultSets[nextId] = {list = list, i = 1}
	return nextId
end
db = {
	query = function(q)
		queries[#queries + 1] = q
		local acc, k, src = q:match("VALUES %((%d+), '([%w_]+)', '([%w_]+)'")
		if acc then rows[#rows + 1] = {account = tonumber(acc), key = k, source = src} end
		local dacc, dk = q:match("DELETE FROM .- = (%d+) AND `class_key` = '([%w_]+)'")
		if dacc then
			for i = #rows, 1, -1 do
				if rows[i].account == tonumber(dacc) and rows[i].key == dk then table.remove(rows, i) end
			end
		end
		return true
	end,
	storeQuery = function(q)
		local acc = q:match("SELECT `class_key` .- = (%d+)")
		if acc then
			local list = {}
			for _, r in ipairs(rows) do if r.account == tonumber(acc) then list[#list + 1] = {class_key = r.key} end end
			return store(list)
		end
		local macc = q:match("MAX%(`level`%).- = (%d+)")
		if macc then
			local best = 0
			for _, c in pairs(chars) do if c.account == tonumber(macc) then best = math.max(best, c.level) end end
			return store({{l = best}})
		end
		local name = q:match("WHERE `name` = '([^']+)'")
		if name and chars[name] then return store({{account_id = chars[name].account}}) end
		return nil
	end,
	escapeString = function(s) return "'" .. tostring(s) .. "'" end
}
result = {
	getString = function(id, col) local r = resultSets[id]; return tostring(r.list[r.i][col]) end,
	getNumber = function(id, col) local r = resultSets[id]; return tonumber(r.list[r.i][col]) end,
	next = function(id) local r = resultSets[id]; r.i = r.i + 1; return r.list[r.i] ~= nil end,
	free = function(id) resultSets[id] = nil end
}
local online = {}
Game = {getPlayers = function() return online end}
local scheduled = {}
function addEvent(fn, ms, ...) scheduled[#scheduled + 1] = {fn = fn, args = {...}} end

local Player_mt = {}
Player_mt.__index = Player_mt
local nextCid = 100
local function newPlayer(o)
	nextCid = nextCid + 1
	local p = setmetatable({cid = nextCid, name = o.name or "P", account = o.account or 1, voc = o.voc or 4,
		group = o.group or 1, accountType = o.accountType or 1, level = o.level or 100, messages = {}, storage = {},
		temple = {x = 1, y = 2, z = 7}}, Player_mt)
	chars[p.name] = {account = p.account, level = p.level}
	return p
end
function Player_mt:getId() return self.cid end
function Player_mt:getName() return self.name end
function Player_mt:getAccountId() return self.account end
function Player_mt:getAccountType() return self.accountType end
function Player_mt:getGroup()
	local g = self.group
	return {getId = function() return g end, getAccess = function() return g >= 4 end}
end
function Player_mt:getVocation() local v = self.voc; return {getId = function() return v end} end
function Player_mt:getLevel() return self.level end
function Player_mt:isPlayer() return true end
function Player_mt:getStorageValue(k) return self.storage[k] or -1 end
function Player_mt:sendTextMessage(_, text) self.messages[#self.messages + 1] = text end
function Player_mt:sendCancelMessage(text) self.cancel = text end
function Player_mt:popupFYI(text) self.popup = text end
function Player_mt:registerEvent(name) self.events = self.events or {}; self.events[name] = true end
function Player_mt:getTown() local t = self.temple; return {getTemplePosition = function() return t end} end
function Player_mt:teleportTo(pos) self.pos = pos end
function Player_mt:remove() self.removed = true end
function Player(cid) for _, p in ipairs(online) do if p.cid == cid then return p end end end
-- userdata check in class_unlocks.lua: the mock players are tables, so treat them as userdata
local realType = type
type = function(x) if getmetatable(x) == Player_mt then return "userdata" end return realType(x) end

dofile("data/scripts/chaos/class_unlocks.lua")
local U = ChaosClassUnlocks

-- the open beta (beta_config.lua enabled) opens every class; the lock rules below run with the beta off
ChaosClassUnlocksCore.config.betaOpen = false
-- ------------------------------------------------------------------ API
local alice = newPlayer({name = "Alice", account = 7, voc = 23})
local alt = newPlayer({name = "Alt", account = 7, voc = 4})
local gm = newPlayer({name = "Gamemaster", account = 9, voc = 25, group = 6})
local bob = newPlayer({name = "Bob", account = 8, voc = 20})
online = {alice, alt, gm, bob}

eq(U.classOfVocation(23), "templar"); eq(U.classOfVocation(8), nil); eq(U.classOfVocation(18), "monk")
eq(U.isUnlocked(alice, "templar"), false, "alice locked")
assert(queries[1]:find("CREATE TABLE"), "table created on first use")
eq(U.isUnlocked(7, "templar"), false, "account id form")
eq(U.isUnlocked(alice, "warrior"), true, "a class that is not locked")
eq(U.isUnlocked(gm, "templar"), true, "staff player")
eq(U.isUnlocked(9, "templar"), false, "the account id form has no staff bypass")
eq(U.isUnlocked(0, "templar"), false, "no account")
ok, msg = U.canUseVocation(alt, 24)
eq(ok, false, "alt cannot become an inquisitor"); assert(msg:find("Templar is locked"), msg)
eq(U.canUseVocation(alt, 8), true, "juggernaut is free")
eq(U.canUseVocation(gm, 21), true, "gm may be a lich")
eq(U.isRestricted(alice), true, "alice on a locked vocation")
eq(U.isRestricted(alt), false)
eq(U.isRestricted(gm), false)

-- ------------------------------------------------------------------ the restriction callbacks
eq(callback("onTargetCombat")(alice, {}), RETURNVALUE_NOTPOSSIBLE, "restricted cannot attack")
assert(alice.cancel and alice.cancel:find("level 200"), "and is told why")
eq(callback("onTargetCombat")(alt, {}), RETURNVALUE_NOERROR, "others attack")
eq(callback("onGainExperience")(alice, nil, 500, 500), 0, "no experience")
eq(callback("onGainExperience")(alt, nil, 500, 500), 500)
eq(callback("onGainSkillTries")(alice, 2, 7), 0, "no skill")
eq(callback("onGainSkillTries")(alt, 2, 7), 7)

-- ------------------------------------------------------------------ login
events.ChaosClassUnlocksLogin.onLogin(alice)
eq(alice.pos, alice.temple, "sent to the temple")
assert(alice.popup and alice.popup:find("Templar is locked") and alice.popup:find("temple"), "window says why")
eq(alice.events.ChaosClassUnlocksAdvance, true, "advance event registered")
events.ChaosClassUnlocksLogin.onLogin(alt)
eq(alt.pos, nil, "a free character is left alone"); eq(alt.popup, nil)

-- ------------------------------------------------------------------ the store entry and the account-wide grant
eq(U.storeUnlock("autoSeller"), nil, "not a class offer")
eq(U.storeUnlock("unlockTemplar"), nil, "the class offers are gone (2026-10-15)")
eq(U.isUnlocked(7, "templar"), false, "not unlocked yet")
eq(U.grant(7, "templar", "level"), true, "earned by another character of the account")
eq(U.isUnlocked(7, "templar"), true)
eq(U.isRestricted(alice), false, "the restriction ends at once")
eq(U.canUseVocation(alt, 25), true, "alt may become a sentinel now")
assert(alice.messages[#alice.messages]:find("unlocked"), "the locked character is told")
eq(U.isUnlocked(8, "templar"), false, "other accounts unaffected")
eq(U.isUnlocked(7, "monk"), false, "other classes unaffected")
eq(U.isUnlocked(8, "necromancer"), false)
eq(U.grant(8, "nonsense", "store"), false, "unknown class refused")

-- revoke (staff) and the kick mode
eq(U.revoke(7, "templar"), true)
eq(U.isRestricted(alice), true, "revoked: restricted again")
cfg.login.mode = "kick"
events.ChaosClassUnlocksLogin.onLogin(alice)
assert(alice.popup:find("logged out"), "kick mode says so")
local last = scheduled[#scheduled]
last.fn((table.unpack or unpack)(last.args))
eq(alice.removed, true, "kicked")
cfg.login.mode = "restrict"

-- ------------------------------------------------------------------ automatic methods
cfg.classes.monk.unlock.level = {min = 400}
local carl = newPlayer({name = "Carl", account = 11, voc = 17, level = 50})
chars.CarlMain = {account = 11, level = 420}
online[#online + 1] = carl
events.ChaosClassUnlocksLogin.onLogin(carl)
eq(U.isUnlocked(11, "monk"), true, "level method: another character of the account is 420")
eq(carl.popup, nil, "unlocked before the check: no restriction")
eq(rows[#rows].source, "level", "source recorded")
cfg.classes.monk.unlock.level = nil

-- ------------------------------------------------------------------ staff command
-- an unlock is value: an administrator (group 5+, Chaos.staffCommand; docs/GM_HANDBOOK.md: staff never give value);
-- a gamemaster (group 4) may revoke
dofile("data/scripts/chaos/chaos_constants.lua")
local gm4 = newPlayer({name = "Gamemaster Four", account = 12, voc = 4, group = 4})
talks["/classunlock"].onSay(gm4, "/classunlock", "Bob, necromancer")
eq(U.isUnlocked(8, "necromancer"), false, "a gamemaster cannot unlock")
eq(gm4.cancel ~= nil, true, "and is told why")
talks["/classunlock"].onSay(gm, "/classunlock", "Bob, necromancer")
eq(U.isUnlocked(8, "necromancer"), true, "gm grant")
talks["/classunlock"].onSay(gm4, "/classunlock", "Bob, necromancer, revoke")
eq(U.isUnlocked(8, "necromancer"), false, "gm revoke (a gamemaster may)")
talks["/classunlock"].onSay(alt, "/classunlock", "Bob, necromancer")
eq(U.isUnlocked(8, "necromancer"), false, "players cannot use it")
eq(talks["!classes"], nil, "no spoken player command")
ChaosCommands.handlers.classes(bob, "")
assert(bob.messages[#bob.messages]:find("Locked classes: .*Necromancer"), "the menu's Character Info lists the state")

print("class_unlocks_test: OK")

-- ------------------------------------------------------------------ open beta
ChaosClassUnlocksCore.config.betaOpen = true
eq(U.isUnlocked(bob, "necromancer"), true, "beta: every class open to everyone")
eq(U.isUnlocked(7, "templar"), true, "beta: account id form too")
ChaosClassUnlocksCore.config.betaOpen = false
eq(U.isUnlocked(bob, "necromancer"), false, "beta off: the lock is back")
