-- Run from the server/ folder: luajit tests/testers_test.lua (no engine; CI runs it with luajit and lua5.3)
-- Tester bots (data/scripts/chaos/testers_core.lua, testers.lua; server/README.md "Tester bots"): the safety rules,
-- the name pattern, broadcasts and Discord events naming a tester, and testers.lua against a mocked engine: a staff
-- tester is refused, combat / trade / party never mix testers and players, the TESTER title and look line, the counts
-- without testers (Chaos.countedPlayers), the storage key equal to src-patch 0059's CHAOS_TESTER_STORAGE.
local count, failures = 0, 0
local function check(cond, label)
	count = count + 1
	if not cond then
		failures = failures + 1
		io.stderr:write("FAIL " .. label .. "\n")
	end
end
local function eq(a, b, label)
	check(a == b, tostring(label or "") .. " (" .. tostring(a) .. " ~= " .. tostring(b) .. ")")
end

dofile("data/scripts/chaos/chaos_constants.lua")
dofile("data/scripts/chaos/testers_core.lua")
local K = ChaosTestersCore

-- ------------------------------------------------------------------ the key the engine reads
eq(Chaos.storage.tester, 7102900, "the tester storage")
check(Chaos.storage.tester >= 7100000 and Chaos.storage.tester <= 7127999, "in the reserved storage range")
local f = io.open("src-patches/0059-tester-bots-not-counted.patch", "r")
local patch = f and f:read("*a") or ""
if f then f:close() end
local engineKey = tonumber(patch:match("uint32_t CHAOS_TESTER_STORAGE = (%d+)"))
eq(engineKey, Chaos.storage.tester, "src-patch 0059 reads the same storage key")
local used = {}
for k, v in pairs(Chaos.storage) do
	if type(v) == "number" and v ~= Chaos.storage.tester and v >= 7102900 and v <= 7102909 then
		used[#used + 1] = k
	end
end
eq(#used, 0, "no other storage in 7102900-7102909: " .. table.concat(used, ","))
check(Chaos.notTesterSql("`p`"):find("`ts`.`player_id` = `p`.`id`", 1, true) ~= nil, "the SQL filter uses the alias")
check(Chaos.notTesterSql("`p`"):find("7102900", 1, true) ~= nil, "the SQL filter uses the key")

-- ------------------------------------------------------------------ rules
eq(K.safetyProblem(1, 1), nil, "group 1 on a type 1 account is fine")
check(K.safetyProblem(2, 1) ~= nil, "a tutor group is refused")
check(K.safetyProblem(6, 1) ~= nil, "a god group is refused")
check(K.safetyProblem(1, 5) ~= nil, "a god account is refused")
check(K.safetyProblem(nil, nil) ~= nil, "an unknown group is refused")
check(K.isTesterName("Tester Abc"), "Tester Abc")
check(not K.isTesterName("Tester abc") and not K.isTesterName("Tester Abcd") and not K.isTesterName("Testerx Abc"),
	"other shapes are not tester names")
check(not K.isTesterName("Loadbot Abc") and not K.isTesterName(nil), "load bots and nil")
local names = {[10] = "Tester Abc", [11] = "Tester Abd"}
check(K.mentions("Tester Abc advanced to level 100.", names), "a broadcast naming a tester")
check(not K.mentions("Tester Abz advanced to level 100.", names), "an unknown Tester name is not one")
check(not K.mentions("Ana advanced to level 100.", names), "a player's broadcast")
check(K.mentions("Ana and Tester Abd won.", {["Tester Abd"] = true}), "a set of names")
check(K.mentionsAny({kind = "level", fields = {{name = "Who", value = "Tester Abd"}}}, names), "nested Discord fields")
check(not K.mentionsAny({kind = "level", text = "Ana reached level 500."}, names), "a player's Discord event")
check(K.mixed(true, false) and K.mixed(nil, 1), "tester and player are mixed")
check(not K.mixed(true, true) and not K.mixed(false, nil), "two testers or two players are not")
check(K.marketBlocked("buy") and K.marketBlocked("fill") and K.marketBlocked("list") and K.marketBlocked("orderPost"),
	"market trades are blocked")
check(not K.marketBlocked("open") and not K.marketBlocked("browse") and not K.marketBlocked("cancel"),
	"looking at the market is allowed")
check(K.lookLine(true):find("TESTER", 1, true) and K.lookLine(false):find("TESTER", 1, true), "look lines")

-- ------------------------------------------------------------------ testers.lua in a mocked engine
RETURNVALUE_NOERROR, RETURNVALUE_YOUMAYNOTATTACKTHISPLAYER, RETURNVALUE_NOTPOSSIBLE = 0, 41, 1
local events, callbacks, broadcasts, logged = {}, {}, {}, {}
local function newEvent(kind)
	return function(name)
		local e = {name = name}
		function e:type() end
		function e:register() events[name] = self end
		return e
	end
end
CreatureEvent = newEvent("creature")
GlobalEvent = newEvent("global")
-- the engine's EventCallback is one object; each script sets its handler fields, then register() files them
EventCallback = {}
function EventCallback:register()
	for name, fn in pairs(self) do
		if type(fn) == "function" and name ~= "register" then
			callbacks[name] = fn
		end
	end
end
local origPrint = print
print = function(s) logged[#logged + 1] = s end
local dbRows = {{id = 10, name = "Tester Abc"}, {id = 11, name = "Tester Abd"}}
db = {storeQuery = function(sql)
	check(sql:find("`s`.`key` = 7102900 AND `s`.`value` = 1", 1, true) ~= nil, "the load query matches the key exactly")
	return 1
end}
local cursor = 1
result = {
	getNumber = function(_, k) return dbRows[cursor][k] end,
	getString = function(_, k) return dbRows[cursor][k] end,
	next = function() cursor = cursor + 1; return dbRows[cursor] ~= nil end,
	free = function() end,
}
local function player(o)
	o.storage = o.storage or {}
	local p = {}
	function p:isPlayer() return true end
	function p:getMaster() return nil end
	function p:getId() return o.cid end
	function p:getGuid() return o.guid end
	function p:getName() return o.name end
	function p:getGroup() return {getId = function() return o.group or 1 end} end
	function p:getAccountType() return o.accountType or 1 end
	function p:getStorageValue(k) return o.storage[k] or -1 end
	function p:sendCancelMessage(m) o.cancel = m end
	return p
end
local function summon(master)
	local s = {}
	function s:isPlayer() return false end
	function s:getMaster() return master end
	return s
end
local function monster()
	return summon(nil)
end
local players = {}
Game = {
	getPlayers = function() return players end,
	getPlayerCount = function() return #players end,
	broadcastMessage = function(text, kind) broadcasts[#broadcasts + 1] = text; return true end,
}
ChaosTitles = {sources = {}, register = function(source, fn) ChaosTitles.sources[source] = fn end}
dofile("data/scripts/chaos/testers.lua")

local T = {[Chaos.storage.tester] = 1}
local tester = player({cid = 1, guid = 10, name = "Tester Abc", storage = T})
local tester2 = player({cid = 2, guid = 11, name = "Tester Abd", storage = T})
local ana = player({cid = 3, guid = 20, name = "Ana"})
local bob = player({cid = 4, guid = 21, name = "Bob", storage = {[Chaos.storage.tester] = 0}})
local staffTester = player({cid = 5, guid = 12, name = "Tester Abe", group = 6, storage = T})
local godAccount = player({cid = 6, guid = 13, name = "Tester Abf", accountType = 5, storage = T})
local oddName = player({cid = 7, guid = 14, name = "Ana Tester", storage = T})

check(events.ChaosTestersStartup.onStartup(), "startup")
eq(Chaos.testerGuids[10], "Tester Abc", "startup loads the tester guids")
check(Chaos.isTesterGuid(11) and not Chaos.isTesterGuid(20) and not Chaos.isTesterGuid(nil), "isTesterGuid")

local login = events.ChaosTestersLogin.onLogin
check(login(ana), "a player logs in")
check(login(bob), "storage 0 is a player")
check(login(tester), "a tester logs in")
check(not login(staffTester), "a tester in a staff group is refused")
check(not login(godAccount), "a tester on a staff account is refused")
check(not login(oddName), "a tester without a tester name is refused")
check(logged[#logged]:find("refused tester", 1, true) ~= nil, "a refusal is logged")
check(not Chaos.testerGuids[12] and not Chaos.testerGuids[13], "refused testers are not added")

local title = ChaosTitles.sources.tester
eq(title(ana), nil, "no title for a player")
local t = title(tester)
check(t and t.text == "TESTER" and t.priority == 1000, "the TESTER title")

local look = callbacks.onLook
eq(look(ana, bob, nil, 1, "You see Bob."), "You see Bob.", "a look at a player is unchanged")
check(look(ana, tester, nil, 1, "You see Tester Abc."):find("TESTER", 1, true), "a look at a tester says TESTER")
check(look(tester, tester, nil, 1, "You see yourself."):find("You are a TESTER", 1, true), "a look at oneself")

local combat = callbacks.onTargetCombat
eq(combat(tester, ana), RETURNVALUE_YOUMAYNOTATTACKTHISPLAYER, "a tester never hits a player")
eq(combat(ana, tester), RETURNVALUE_YOUMAYNOTATTACKTHISPLAYER, "a player never hits a tester")
eq(combat(summon(tester), ana), RETURNVALUE_YOUMAYNOTATTACKTHISPLAYER, "a tester's summon never hits a player")
eq(combat(ana, summon(tester)), RETURNVALUE_YOUMAYNOTATTACKTHISPLAYER, "a player never hits a tester's summon")
K.reader, K.clock = function() return nil end, function() return 1000 end
K.resetClosedCache()
eq(combat(tester, tester2), RETURNVALUE_YOUMAYNOTATTACKTHISPLAYER, "two testers never fight while closed mode is off")
eq(combat(summon(tester), tester2), RETURNVALUE_YOUMAYNOTATTACKTHISPLAYER, "nor a tester's summon and another tester")
K.reader, K.clock = function() return "on" end, function() return 2000 end
K.resetClosedCache()
eq(combat(tester, tester2), RETURNVALUE_NOERROR, "testers among themselves in closed mode")
eq(combat(summon(tester), tester2), RETURNVALUE_NOERROR, "their summons too")
eq(combat(tester, ana), RETURNVALUE_YOUMAYNOTATTACKTHISPLAYER, "closed mode on: a tester still never hits a player")
eq(combat(ana, tester2), RETURNVALUE_YOUMAYNOTATTACKTHISPLAYER, "closed mode on: a player still never hits a tester")
eq(combat(tester, summon(tester)), RETURNVALUE_NOERROR, "a tester and its own summon")
K.reader, K.clock = nil, nil
K.resetClosedCache()
eq(combat(ana, bob), RETURNVALUE_NOERROR, "players among themselves: other systems decide")
eq(combat(tester, monster()), RETURNVALUE_NOERROR, "a tester hits a monster")
eq(combat(monster(), tester), RETURNVALUE_NOERROR, "a monster hits a tester: real damage")

check(not callbacks.onTradeRequest(tester, ana, nil), "no trade tester to player")
check(not callbacks.onTradeRequest(ana, tester, nil), "no trade player to tester")
check(callbacks.onTradeRequest(tester, tester2, nil) and callbacks.onTradeRequest(ana, bob, nil), "same side trades")
check(not callbacks.onTradeAccept(ana, tester, nil, nil), "no accept across")
local function party(leader) return {getLeader = function() return leader end} end
check(not callbacks.onJoin(party(ana), tester), "a tester never joins a player's party")
check(not callbacks.onJoin(party(tester), ana), "a player never joins a tester's party")
check(callbacks.onJoin(party(tester), tester2), "testers party together")

Game.broadcastMessage("Tester Abc advanced from level 99 to 100.", 1)
Game.broadcastMessage("Ana advanced from level 99 to 100.", 1)
eq(#broadcasts, 1, "a broadcast naming a tester is dropped")
eq(broadcasts[1], "Ana advanced from level 99 to 100.", "a player's broadcast goes out")
local raw = ChaosTesters.rawBroadcast
dofile("data/scripts/chaos/testers.lua") -- /reload never wraps twice
check(ChaosTesters.rawBroadcast == raw, "the broadcast wrapper is installed once")

players = {ana, tester, bob, tester2}
eq(Chaos.countedPlayers(), 2, "2 counted of 4 online")
players = {tester, tester2}
eq(Chaos.countedPlayers(), 0, "only testers: 0 online")

-- ------------------------------------------------------------------ mail
eq(K.receiverOf("  Tester Abc \nTown"), "Tester Abc", "the receiver is the first line")
eq(K.receiverOf(""), nil, "an empty label")
eq(K.mailBlocked(true, "Ana"), "Tester characters cannot send mail.", "a tester sends no mail")
eq(K.mailBlocked(false, "Tester Abc"), "Mail to tester characters is not delivered.", "no mail to a tester")
eq(K.mailBlocked(false, "Ana"), nil, "mail between players")
CONTAINER_POSITION, ITEM_ATTRIBUTE_TEXT, MESSAGE_STATUS_SMALL = 0xFFFF, 8, 21
local mailbox = {x = 100, y = 100, z = 7}
function Tile(pos)
	return {getItemById = function(_, id) return pos.x == mailbox.x and pos.y == mailbox.y and id == 2593 end}
end
local function mail(id, text)
	local label = {getId = function() return 2599 end, getAttribute = function() return text end}
	return {getId = function() return id end, isContainer = function() return id == 2595 end,
		getSize = function() return 1 end, getItem = function() return label end,
		getAttribute = function() return text end}
end
local moved, told = 0, nil
ChaosDepot = {onMoveItem = function() moved = moved + 1; return RETURNVALUE_NOERROR end}
local sender = player({cid = 4, guid = 21, name = "Bea"})
function sender:sendTextMessage(_, t) told = t end
function tester:sendTextMessage(_, t) told = t end
dofile("data/scripts/chaos/testers.lua")
local move = ChaosDepot.onMoveItem
eq(move(sender, mail(2595, "Tester Abc\nTown"), 1, nil, mailbox), RETURNVALUE_NOTPOSSIBLE, "a parcel to a tester stays")
eq(told, "Mail to tester characters is not delivered.", "with its text")
eq(move(sender, mail(2597, "Tester Abd"), 1, nil, mailbox), RETURNVALUE_NOTPOSSIBLE, "a letter to a tester stays")
eq(move(tester, mail(2597, "Ana"), 1, nil, mailbox), RETURNVALUE_NOTPOSSIBLE, "a tester sends no letter")
eq(moved, 0, "refused moves never reach the depot check")
eq(move(sender, mail(2595, "Ana"), 1, nil, mailbox), RETURNVALUE_NOERROR, "a parcel to a player goes")
eq(move(sender, mail(2595, "Tester Abc"), 1, nil, {x = 1, y = 1, z = 7}), RETURNVALUE_NOERROR, "not on a mailbox")
eq(move(tester, mail(2160, ""), 1, nil, mailbox), RETURNVALUE_NOERROR, "other items on a mailbox tile")
eq(moved, 3, "the depot check runs after")
dofile("data/scripts/chaos/testers.lua")
check(ChaosDepot.onMoveItem == move, "the move wrapper is installed once")

-- ------------------------------------------------------------------ closed test mode (O582), the rules
check(K.parseClosed("on") and K.parseClosed(" ON \n") and K.parseClosed("On"), "the word on, any case, trimmed")
check(not K.parseClosed("off") and not K.parseClosed("") and not K.parseClosed("onn") and not K.parseClosed("1")
	and not K.parseClosed("on off") and not K.parseClosed(nil) and not K.parseClosed(12), "anything else is off")
local now, text = 100, "on"
K.reader, K.clock = function() return text end, function() return now end
K.resetClosedCache()
check(K.closedOn(), "the file says on")
text = "off"
check(K.closedOn(), "read at most every few seconds")
now = now + K.CLOSED_TTL
check(not K.closedOn(), "then read again: off")
K.reader = function() error("disk gone") end
now = now + K.CLOSED_TTL
check(not K.closedOn(), "a read that fails is off")
K.reader = function() return nil end
now = now + K.CLOSED_TTL
check(not K.closedOn(), "no file is off")
K.reader = function() return "on" end
now = now - 1000
K.resetClosedCache()
check(K.closedOn(), "on again")
now = now - 500
check(K.closedOn(), "a clock that went back reads again")
K.reader, K.clock = nil, nil
K.resetClosedCache()

eq(K.sideOf({true, true}), "tester", "all testers")
eq(K.sideOf({false}), "player", "a player")
eq(K.sideOf({true, false}), nil, "a tester and a player: no side")
eq(K.sideOf({false, true, false}), nil, "a tester in a party of players")
eq(K.sideOf({}), nil, "nobody")
eq(K.sideOf({true, "?"}), nil, "an unknown party")
eq(K.sideOf(nil), nil, "no list")
for sys in pairs(K.CLOSED_SYSTEMS) do
	check(K.sameSide(sys, true, "tester", "tester"), sys .. ": testers together, mode on")
	local ok, why = K.sameSide(sys, false, "tester", "tester")
	check(not ok and why == "closed-off", sys .. ": testers together, mode off")
	ok, why = K.sameSide(sys, true, "tester", "player")
	check(not ok and why == "apart", sys .. ": a tester against a player, mode on")
	ok, why = K.sameSide(sys, true, "player", "tester")
	check(not ok and why == "apart", sys .. ": a player against a tester, mode on")
	ok = K.sameSide(sys, false, "player", "tester")
	check(not ok, sys .. ": a player against a tester, mode off")
	ok, why = K.sameSide(sys, true, nil, "tester")
	check(not ok and why == "mixed", sys .. ": an unknown side is refused")
	ok, why = K.sameSide(sys, true, "tester", nil)
	check(not ok and why == "mixed", sys .. ": an unknown side is refused (second)")
	check(K.sameSide(sys, false, "player", "player"), sys .. ": players among themselves are not a closed-mode matter")
end
check(not K.sameSide("dungeons", true, "tester", "tester"), "a system outside the closed list never pairs testers")
check(not K.sameSide("arena", "yes", "tester", "tester"), "only the boolean true switches it on")
eq(K.joinRefusal("arena", true, {true, true}), nil, "a tester party queues in closed mode")
eq(K.joinRefusal("arena", false, {true}), "closed-off", "a tester queues with the mode off: refused")
eq(K.joinRefusal("arena", true, {true, false}), "mixed", "a mixed party is refused")
eq(K.joinRefusal("arena", false, {false, false}), nil, "players queue as always")
for why, line in pairs(K.CLOSED_TEXT) do
	check(type(line) == "string" and line ~= "", "a refusal text for " .. why)
end

eq(K.guildSide("Tester Guild Alfa", true, true), "tester", "a tester guild")
eq(K.guildSide("Iron Crows", false, false), "player", "a player guild")
eq(K.guildSide("Tester Guild Alfa", true, false), nil, "a tester guild with a player member")
eq(K.guildSide("Iron Crows", true, true), nil, "testers in a player guild: no side")
eq(K.guildSide("Iron Crows", true, false), nil, "a tester among players")
eq(K.guildSide("Tester Guild Alfa", nil, nil), nil, "unknown members")
eq(K.guildSide("Tester Foo", false, false), "player", "a player's guild named like a tester one is still theirs")
-- which guilds a viewer sees on a board (O592)
check(K.guildVisible(false, "Iron Crows", nil) and K.guildVisible(false, "Iron Crows", "player"), "a player sees a player guild (no query: side unknown is fine)")
check(not K.guildVisible(false, "Tester Guild Alfa", "tester"), "a player never sees a tester guild")
check(not K.guildVisible(false, "Tester Guild Alfa", nil), "a guild named like a tester guild of unknown side is hidden from a player")
check(K.guildVisible(false, "Tester Foo", "player"), "a player's guild named like a tester one is shown to its side")
check(K.guildVisible(true, "Tester Guild Alfa", "tester"), "a tester sees a tester guild")
check(not K.guildVisible(true, "Iron Crows", "player"), "a tester never sees a player guild")
check(not K.guildVisible(true, "Tester Guild Alfa", nil), "a tester does not see a guild of unknown side")
check(K.CLOSED_SYSTEMS.siege and K.CLOSED_SYSTEMS.guildboss, "the siege and the guild boss are closed systems (O592)")
eq(K.guildBlocked(true, "Tester Guild Alfa", true, true, true), nil, "a tester in a tester guild, mode on")
eq(K.guildBlocked(true, "Tester Guild Alfa", true, true, false), "closed-off", "mode off")
eq(K.guildBlocked(true, "Iron Crows", false, false, true), "apart", "a tester in a player guild")
eq(K.guildBlocked(true, "Iron Crows", true, false, true), "mixed", "a tester in a mixed guild")
eq(K.guildBlocked(true, "Tester Guild Alfa", nil, nil, true), "mixed", "a tester with an unknown guild")
eq(K.guildBlocked(false, "Tester Guild Alfa", true, true, true), "apart", "a player in a tester guild")
eq(K.guildBlocked(false, "Tester Guild Alfa", true, false, true), "mixed", "a player in a tester guild with testers")
eq(K.guildBlocked(false, "Tester Guild Alfa", nil, nil, true), "mixed", "a player in a tester-named guild, unknown members")
eq(K.guildBlocked(false, "Iron Crows", false, false, true), nil, "a player in a player guild")
eq(K.guildBlocked(false, "Iron Crows", true, false, false), nil, "a player is not blocked by a stray tester of its guild")

eq(K.marketRealm(true, 0), K.REALM, "a tester trades in the tester book")
eq(K.marketRealm(true, 5), K.REALM, "whatever season runs")
eq(K.marketRealm(false, 5), 5, "a player in its own realm")
check(K.REALM > 1000000, "no season has the tester realm")
eq(K.marketRefusal("buy", true, false), "Tester characters cannot trade on the market.", "mode off: a tester cannot buy")
eq(K.marketRefusal("orderPost", true, nil), "Tester characters cannot trade on the market.", "unknown mode is off")
eq(K.marketRefusal("fill", true, "on"), "Tester characters cannot trade on the market.", "only the boolean true")
eq(K.marketRefusal("buy", true, true), nil, "mode on: a tester buys in its book")
eq(K.marketRefusal("browse", true, false), nil, "looking is always allowed")
eq(K.marketRefusal("buy", false, false), nil, "a player is not this rule's business")
check(not K.marketCoinsOk(K.REALM) and K.marketCoinsOk(0) and K.marketCoinsOk(3), "the tester book trades gold only")

-- testers.lua: the guild sides from the database (members' tester storage), the war rule and the guild block
do
	local guilds = {[1] = {n = 3, t = 3}, [2] = {n = 2, t = 0}, [3] = {n = 3, t = 1}, [4] = {n = 0, t = 0}}
	local queries, row = 0, nil
	local realStore = db.storeQuery
	db.storeQuery = function(sql)
		queries = queries + 1
		local gid = tonumber(sql:match("`m`.`guild_id` = (%d+)"))
		if not guilds[gid] then error("database gone") end
		row = guilds[gid]
		return 1
	end
	local realNum, realFree = result.getNumber, result.free
	result.getNumber = function(_, k) return row[k] end
	result.free = function() end
	local X = ChaosTesters
	K.reader, K.clock = function() return "on" end, function() return os.time() end
	K.resetClosedCache()
	eq(X.guildSide(1, "Tester Guild Alfa"), "tester", "a guild of three testers")
	eq(X.guildSide(2, "Iron Crows"), "player", "a guild of players")
	eq(X.guildSide(3, "Tester Guild Bravo"), nil, "a tester guild with a player in it")
	eq(X.guildSide(4, "Tester Guild Echo"), nil, "an empty guild")
	eq(X.guildSide(9, "Tester Guild Zulu"), nil, "a database error: no side")
	local q = queries
	X.guildSide(1, "Tester Guild Alfa")
	eq(queries, q, "the members are kept a few seconds")
	local ok = X.warAllowed(1, "Tester Guild Alfa", 1, "Tester Guild Alfa")
	check(ok, "a war between tester guilds, mode on")
	check(not X.warAllowed(1, "Tester Guild Alfa", 2, "Iron Crows"), "a tester guild against a player guild")
	check(not X.warAllowed(2, "Iron Crows", 1, "Tester Guild Alfa"), "a player guild against a tester guild")
	check(not X.warAllowed(1, "Tester Guild Alfa", 3, "Tester Guild Bravo"), "a tester guild against a mixed one")
	check(not X.warAllowed(1, "Tester Guild Alfa", 9, "Tester Guild Zulu"), "a tester guild against an unknown one")
	check(X.warAllowed(2, "Iron Crows", 2, "Iron Crows"), "player guilds as always")
	eq(X.guildBlocked(tester, 1, "Tester Guild Alfa"), nil, "a tester uses its tester guild, mode on")
	eq(X.guildBlocked(ana, 2, "Iron Crows"), nil, "a player uses its guild")
	eq(X.guildBlocked(ana, 1, "Tester Guild Alfa"), "apart", "a player never uses a tester guild")
	eq(X.guildBlocked(tester, 2, "Iron Crows"), "apart", "a tester never uses a player guild")
	-- the boards (O592): the engine side of K.guildVisible
	check(X.guildVisible(ana, 2, "Iron Crows"), "a player's board lists a player guild")
	check(not X.guildVisible(ana, 1, "Tester Guild Alfa"), "a player's board never lists a tester guild")
	check(X.guildVisible(tester, 1, "Tester Guild Alfa"), "a tester's board lists a tester guild")
	check(not X.guildVisible(tester, 2, "Iron Crows"), "a tester's board never lists a player guild")
	check(not X.guildVisible(ana, 3, "Tester Guild Bravo"), "a player never sees a mixed guild named like a tester guild")
	K.reader, K.clock = function() return "off" end, function() return os.time() + 500 end
	K.resetClosedCache()
	X.guildCache = {}
	check(not X.warAllowed(1, "Tester Guild Alfa", 1, "Tester Guild Alfa"), "a war between tester guilds, mode off")
	eq(X.guildBlocked(tester, 1, "Tester Guild Alfa"), "closed-off", "a tester guild, mode off")
	local q2 = queries
	X.guildBlocked(ana, 2, "Iron Crows")
	eq(queries, q2, "a player in an ordinary guild costs no query")
	K.reader, K.clock = nil, nil
	K.resetClosedCache()
	X.guildCache = {}
	db.storeQuery, result.getNumber, result.free = realStore, realNum, realFree
end

-- the same numbers in the systems that carry them
dofile("data/scripts/chaos/market_core.lua")
eq(ChaosMarketCore.TESTER_REALM, K.REALM, "market_core.lua carries the tester realm")
eq(ChaosMarketCore.realmOf(K.REALM, 0), K.REALM, "an offer of the tester book stays in it")
check(ChaosMarketCore.realmClause(0, 0):find(tostring(K.REALM), 1, true), "a player's view leaves the tester book out")
check(ChaosMarketCore.realmClause(0, 4):find(tostring(K.REALM), 1, true), "a season player's view too")
eq(ChaosMarketCore.realmClause(K.REALM, 4), "`realm` = " .. K.REALM, "a tester sees only its book")
local pcfg = dofile("data/scripts/chaos/pvpzone_config.lua")
eq(pcfg.testerRealm, K.REALM, "pvpzone_config.lua carries the tester realm")
dofile("data/scripts/chaos/pvpzone_core.lua")
local PZ = ChaosPvpZoneCore
eq(PZ.slotForRealm(pcfg, K.REALM), pcfg.testerSlot, "the testers have their own Marches slot")
for realm = 0, 12 do
	check(PZ.slotForRealm(pcfg, realm) ~= pcfg.testerSlot, "realm " .. realm .. " never shares the testers' slot")
end
check(pcfg.testerSlot >= pcfg.grid.slots, "the testers' slot is after the grid's slots")
local origin = PZ.slotOrigin(pcfg, pcfg.testerSlot)
eq(PZ.slotOfPos(pcfg, {x = origin.x + 2, y = origin.y + 2, z = origin.z}), pcfg.testerSlot, "a position in the testers' slot belongs to it")
check(PZ.entryRefusal(pcfg, {testerClosedOff = true, accept = true, inPz = true, level = 9999}) ~= nil,
	"a tester with the mode off cannot enter the Marches")

-- the systems' own guards, in the files
local function source(path)
	local f = assert(io.open(path, "r"))
	local t = f:read("*a")
	f:close()
	return t
end
for _, file in ipairs({"arena", "battleground", "pvpzone", "market", "guildwar", "guild"}) do
	check(source("data/scripts/chaos/" .. file .. ".lua"):find("O582", 1, true), file .. ".lua carries the closed-mode guard")
end
-- the raid (O588) is a closed system: its rules for testers are in raid.lua, it no longer refuses every tester
do
	local t = source("data/scripts/chaos/raid.lua")
	check(t:find("O588", 1, true) and t:find("testerRefusal", 1, true) and t:find("K.allocSlot", 1, true), "raid.lua carries the closed-mode guard (O588)")
	check(not t:find("Testers do not use this queue", 1, true), "raid.lua no longer refuses every tester")
end
-- the dungeons (O589) are a closed system too: the entry carries its side (dungeons_core.lua), no blanket refusal left
do
	local t = source("data/scripts/chaos/dungeons.lua")
	check(t:find("O589", 1, true) and t:find("DC.pick", 1, true) and t:find("sideOfPlayer", 1, true), "dungeons.lua carries the closed-mode guard (O589)")
	check(not t:find("Testers do not use this queue", 1, true), "dungeons.lua no longer refuses every tester")
	check(t:find('run.side ~= "tester"', 1, true), "dungeons.lua never ranks or records a tester run")
end
-- the group queue and the party finder (O589) are closed systems: a group or a listing has a side, no blanket refusal left
do
	local t = source("data/scripts/chaos/groupqueue.lua")
	check(t:find("O589", 1, true) and t:find("sideOfGroup", 1, true) and t:find("K.sidesAgree", 1, true) == nil, "groupqueue.lua carries the closed-mode guard (O589)")
	check(not t:find("Testers do not use this queue", 1, true), "groupqueue.lua no longer refuses every tester")
	check(source("data/scripts/chaos/groupqueue_core.lua"):find("sidesAgree", 1, true), "groupqueue_core.lua: a match of two sides is never started")
	t = source("data/scripts/chaos/party_finder.lua")
	check(t:find("O589", 1, true) and t:find("testerOn", 1, true), "party_finder.lua carries the closed-mode guard (O589)")
	check(not t:find("Testers do not use this queue", 1, true), "party_finder.lua no longer refuses every tester")
	check(source("data/scripts/chaos/party_finder_core.lua"):find("L.tester and true or false", 1, true), "party_finder_core.lua: a listing has a side")
end

-- ------------------------------------------------------------------ solo content a tester plays beside the players (O595)
do
	local P = player({cid = 91, guid = 910, name = "Ana"})
	local T1 = player({cid = 92, guid = 911, name = "Tester Abc", storage = T})
	local T2 = player({cid = 93, guid = 912, name = "Tester Abd", storage = T})
	eq(K.soloRefusal({false}, 1, 4), nil, "a player is never kept waiting by the reserve")
	eq(K.soloRefusal({true}, 16, 4), nil, "a tester with the halls free: in")
	eq(K.soloRefusal({true}, 5, 4), nil, "a tester may take the fifth-last hall: 4 stay free")
	eq(K.soloRefusal({true}, 4, 4), "reserve", "a tester may not take a hall when fewer than 4 would stay free")
	eq(K.soloRefusal({true, true}, 2, 2), "reserve", "a group of testers is one hall")
	eq(K.soloRefusal({true, false}, 16, 4), "mixed", "a tester and a player are never one group")
	eq(K.soloRefusal({true, "?"}, 16, 4), "mixed", "an unknown side is mixed")
	check(K.CLOSED_TEXT.reserve:find("kept for the players", 1, true) ~= nil, "the reserve text")
	eq(ChaosTesters.soloRefusal({P}, 0, 4), nil, "players: no refusal and no query")
	eq(ChaosTesters.soloRefusal({T1}, 16, 4), nil, "a tester alone with halls free")
	eq(ChaosTesters.soloRefusal({T1, T2}, 16, 4), nil, "two testers")
	eq(ChaosTesters.soloRefusal({T1}, 3, 4), K.CLOSED_TEXT.reserve, "a tester when the halls are the players'")
	eq(ChaosTesters.soloRefusal({T1, P}, 16, 4), K.CLOSED_TEXT.mixed, "a tester with a player")
	eq(ChaosTesters.soloRefusal({P, T1}, 16, 4), K.CLOSED_TEXT.mixed, "a player with a tester")
	eq(ChaosTesters.soloRefusal(nil, 16, 4), nil, "nobody")
	eq(source("data/scripts/chaos/i18n_strings.lua"):find("The testers wait: the halls are kept for the players.", 1, true) ~= nil, true,
		"the reserve text has pt-BR")
end

-- ------------------------------------------------------------------ monsters of a world event (O650)
do
	check(K.worldBlocked("players", true) and not K.worldBlocked("players", false), "players' monster: a tester's hit is cancelled, a player's lands")
	check(K.worldBlocked("testers", false) and not K.worldBlocked("testers", true), "testers' monster: a player's hit is cancelled, a tester's lands")
	check(not K.worldBlocked(nil, true) and not K.worldBlocked("other", false) and not K.worldBlocked("players", nil), "no side, an unknown side: nothing is cancelled; nil is a player")
	local registered = {}
	local function mon(id)
		local m = {}
		function m:getId() return id end
		function m:isPlayer() return false end
		function m:getMaster() return nil end
		function m:registerEvent(n) registered[#registered + 1] = id .. ":" .. n end
		return m
	end
	local X = ChaosTesters
	local goblin, invader, ownGoblin = mon(900), mon(901), mon(902)
	check(X.markWorld(goblin, "players") and X.markWorld(ownGoblin, "testers"), "markWorld: both sides")
	check(not X.markWorld(invader, "nonsense") and X.world[901] == nil, "markWorld: an unknown side is refused")
	check(registered[1] == "900:ChaosTestersWorldTaken" and registered[2] == "902:ChaosTestersWorldTaken" and #registered == 2, "the guard event is registered on the marked monsters")
	eq(X.worldSide(goblin), "players", "worldSide")
	eq(X.worldSide(invader), nil, "worldSide: unmarked")
	local guard = events.ChaosTestersWorldTaken.onHealthChange
	COMBAT_HEALING, COMBAT_PHYSICALDAMAGE = 99, 1
	local pd, pt, sd, st = guard(goblin, tester, 500, COMBAT_PHYSICALDAMAGE, 40, 2)
	check(pd == 0 and sd == 0 and pt == COMBAT_PHYSICALDAMAGE and st == 2, "a tester's hit on a world monster is cancelled")
	eq(X.worldCancelled[1], 1, "and counted for the bot's probe (its creature id)")
	eq(guard(goblin, ana, 500, COMBAT_PHYSICALDAMAGE, 40, 2), 500, "a player's hit on it lands")
	eq(guard(goblin, summon(tester), 500, COMBAT_PHYSICALDAMAGE, 0, 2), 0, "a tester's summon counts as its master: cancelled")
	eq(X.worldCancelled[1], 2, "and counted")
	eq(guard(goblin, monster(), 500, COMBAT_PHYSICALDAMAGE, 0, 2), 500, "another monster's hit (no master): unchanged")
	eq(guard(goblin, nil, 500, COMBAT_PHYSICALDAMAGE, 0, 2), 500, "no attacker (a field): unchanged")
	eq(guard(goblin, tester, -300, COMBAT_HEALING, 0, 2), -300, "healing passes")
	eq(guard(ownGoblin, ana, 500, COMBAT_PHYSICALDAMAGE, 0, 2), 0, "a player's hit on a testers' goblin is cancelled")
	eq(guard(ownGoblin, tester, 500, COMBAT_PHYSICALDAMAGE, 0, 2), 500, "a tester's hit on it lands")
	eq(guard(invader, tester, 500, COMBAT_PHYSICALDAMAGE, 0, 2), 500, "an unmarked monster is nobody's: unchanged")
	check(X.worldHit(tester, "players") and not X.worldHit(ana, "players") and X.worldHit(ana, "testers") and not X.worldHit(nil, "players"), "worldHit: the same rule for the scripts that ask directly")
	eq(X.worldCancelled[1], 3, "worldHit counts a tester's cancelled hit too")
end

-- ------------------------------------------------------------------ O653: a tester is on no season board and takes no chest from the pool
do
	local function source(path)
		local f = io.open(path, "r")
		local text = f and f:read("*a") or ""
		if f then f:close() end
		return text
	end
	local season = source("data/scripts/chaos/season.lua")
	local onRecord = season:match("function S%.onRecord%(board, who, value%)(.-)\nend\n") or ""
	check(onRecord:find("Chaos.isTesterGuid(guid)", 1, true) ~= nil, "season.lua S.onRecord skips a tester guid: no season stat row, no milestone")
	check((onRecord:find("isTesterGuid", 1, true) or 0) > 0 and (onRecord:find("isTesterGuid", 1, true) or 0) < (onRecord:find("INSERT INTO", 1, true) or 0),
		"the tester guard comes before the database write")
	local ladder = season:match("local function ladderWhere%(g, seasonId%)(.-)\nend\n") or ""
	check(ladder:find('Chaos.notTesterSql("p")', 1, true) ~= nil, "season.lua ladderWhere leaves the testers out of the season ladder (the mode ladders share it)")
	local modes = source("data/scripts/chaos/season_modes.lua")
	check(modes:find("S.ladderHelpers.where(g, season.id)", 1, true) ~= nil, "the mode ladders read the same where clause")
	local chest = source("data/scripts/chaos/weeklychest.lua")
	local credit = chest:match("function W%.credit%(player, key%)(.-)\nend\n") or ""
	check(credit:find("Chaos.isTesterGuid(player:getGuid())", 1, true) ~= nil, "the Weekly Chest credits a tester nothing: it is not marked and the chest is not given")
	-- the leaderboard record the season and the pass hook into already skips a tester
	local lb = source("data/scripts/chaos/leaderboard.lua")
	check(lb:find("Chaos.isTesterGuid(guid)", 1, true) ~= nil, "the leaderboard record skips a tester")
end

print = origPrint
print(string.format("testers_test: %d checks, %d failures", count, failures))
os.exit(failures == 0 and 0 or 1)
