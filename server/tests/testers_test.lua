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
		print("FAIL " .. label)
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
eq(combat(tester, tester2), RETURNVALUE_NOERROR, "testers among themselves")
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

print = origPrint
print(string.format("testers_test: %d checks, %d failures", count, failures))
os.exit(failures == 0 and 0 or 1)
