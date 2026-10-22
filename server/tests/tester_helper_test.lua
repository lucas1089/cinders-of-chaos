-- Run from the server/ folder: luajit tests/tester_helper_test.lua (no engine; CI runs it with luajit and lua5.3)
-- The TEST ONLY helper of the tester bots (tools/tester_helper_core.lua, tools/tester_helper.lua; server/README.md
-- "Tester bots"): the pure rules (eligibility, anomalies, JSON, commands) and the engine file against a mocked engine.
-- The safety proof: a real player, a player named like a tester without the storage, and a player with the storage
-- but another name are never targeted, teleported, given items, answered or logged; their words go on (return true).
local count, failures = 0, 0
local function check(cond, label)
	count = count + 1
	if not cond then
		failures = failures + 1
		io.stdout:write("FAIL " .. label .. "\n")
	end
end
local function eq(a, b, label)
	check(a == b, tostring(label or "") .. " (" .. tostring(a) .. " ~= " .. tostring(b) .. ")")
end

dofile("data/scripts/chaos/chaos_constants.lua")
dofile("tools/tester_helper_core.lua")
local H = ChaosTesterHelperCore

-- ------------------------------------------------------------------ pure rules
eq(H.STORAGE, Chaos.storage.tester, "the helper's storage is Chaos.storage.tester")
check(H.eligible("Tester Abc", 1), "a tester")
check(not H.eligible("Tester Abc", -1) and not H.eligible("Tester Abc", 0), "tester name without the storage")
check(not H.eligible("Ana", 1), "the storage without the name")
check(not H.eligible("Tester abc", 1) and not H.eligible("Tester Abcd", 1) and not H.eligible(nil, 1), "name shapes")

eq(H.hitAnomaly({kind = "taken", damage = 130000000, health = 500, maxHealth = 500, level = 100}),
	"hit taken over 3x max health", "the 130M one-shot")
eq(H.hitAnomaly({kind = "taken", damage = 600, health = 500, maxHealth = 500, level = 100}),
	"one hit from full health", "one hit from full")
eq(H.hitAnomaly({kind = "taken", damage = 400, health = 500, maxHealth = 500, level = 100}), nil, "a normal hit")
eq(H.hitAnomaly({kind = "taken", damage = 600, health = 300, maxHealth = 500, level = 100}), nil, "a kill from 60 %")
eq(H.hitAnomaly({kind = "dealt", damage = 50000, level = 100}), "hit dealt far above the level", "absurd dealt")
eq(H.hitAnomaly({kind = "dealt", damage = 40000, level = 100}), nil, "a strong hit of level 100")
eq(H.hitAnomaly({kind = "dealt", damage = -5, level = 100}), "negative damage", "negative damage")
eq(H.xpAnomaly(100, -1), "negative experience gain", "negative xp")
eq(H.xpAnomaly(100, 300000000), "absurd experience gain", "absurd xp")
eq(H.xpAnomaly(100, 50000), nil, "normal xp")
eq(H.xpAnomaly(100, 0 / 0), "experience not a number", "NaN xp")
eq(H.itemAnomaly({count = 101, stackable = true}), "impossible count 101", "stack over 100")
eq(H.itemAnomaly({count = 0}), "impossible count 0", "zero count")
eq(H.itemAnomaly({count = 1, attrs = {attack = 2e9}}), "impossible attribute attack = 2000000000", "absurd attack")
eq(H.itemAnomaly({count = 50, stackable = true, attrs = {armor = 12}}), nil, "a normal item")

eq(H.json({b = 1, a = "x\"y\n", c = {1, 2}, d = {}, e = true}), '{"a":"x\\"y\\n","b":1,"c":[1,2],"d":[],"e":true}',
	"json: sorted keys, escapes, arrays")
eq(H.json(1.5), "1.5000", "json: a fraction")
eq(H.json(0 / 0), "null", "json: NaN")
eq(H.encode("info", {cid = 7}), '[tester-helper] info {"cid":7}', "a helper line")

local c, a = H.parseCommand(" Town ")
eq(c, "town", "command, case and spaces")
eq(a, nil, "no argument")
c, a = H.parseCommand("enter rift 3")
eq(c, "enter", "enter")
eq(a, "rift 3", "its argument")
eq(H.parseCommand("kill everyone"), nil, "an unknown command")
eq(H.parseCommand(nil), nil, "no param")

local o = {x = 100, y = 100, z = 7}
local list = {
	{id = 1, pos = {x = 103, y = 100, z = 7}, health = 10},
	{id = 2, pos = {x = 101, y = 101, z = 7}, health = 10, owned = true}, -- a summon
	{id = 3, pos = {x = 101, y = 100, z = 6}, health = 10}, -- another floor
	{id = 4, pos = {x = 102, y = 102, z = 7}, health = 0}, -- dead
	{id = 5, pos = {x = 102, y = 98, z = 7}, health = 10},
	{id = 6, pos = {x = 110, y = 100, z = 7}, health = 10}, -- out of range
}
local best, d = H.nearest(o, list, 5)
eq(best and best.id, 5, "the nearest live, unowned monster on the floor")
eq(d, 2, "its distance")
eq(H.nearest(o, {list[6]}, 5), nil, "nothing in range")
eq(H.directionTo(o, {x = 100, y = 90}), 0, "north")
eq(H.directionTo(o, {x = 105, y = 101}), 1, "east")
eq(H.directionTo(o, {x = 100, y = 105}), 2, "south")
eq(H.directionTo(o, {x = 95, y = 101}), 3, "west")

-- ------------------------------------------------------------------ a mocked engine
MESSAGE_INFO_DESCR, COMBAT_HEALING, COMBAT_PHYSICALDAMAGE = 22, 128, 1
CONST_SLOT_BACKPACK, CONST_SLOT_LEFT, CONST_SLOT_RIGHT = 3, 6, 5
TILESTATE_BLOCKSOLID = 1
ChaosTestKit = {kits = {knight = {slots = {[CONST_SLOT_LEFT] = 8209, [CONST_SLOT_RIGHT] = 10318}}},
	kindFor = function() return "knight" end}

local talks, events, timers, printed = {}, {}, {}, {}
local callbacks = {}
function TalkAction(words)
	local t = {words = words}
	function t:separator() end
	function t:register() talks[words] = self end
	return t
end
function CreatureEvent(name)
	local e = {name = name}
	function e:type(t) self.kind = t end
	function e:register() events[name] = self end
	return e
end
EventCallback = {register = function(self, n) callbacks.onGainExperience = self.onGainExperience end}
function addEvent(fn, ms, ...)
	timers[#timers + 1] = {fn = fn, ms = ms}
end
local function lastStep()
	for i = #timers, 1, -1 do
		if timers[i].ms == 500 then
			return timers[i], i
		end
	end
end
function Position(x, y, z)
	return {x = x, y = y, z = z}
end
function Tile()
	return nil
end
function ItemType(id)
	return {getClientId = function() return id + 10000 end, getName = function() return "item " .. id end,
		isStackable = function() return id == 7618 or id == 7620 end}
end

local byId = {}
local function creature(id, name, opts)
	opts = opts or {}
	local cr = {id = id, name = name, store = opts.store or {}, pos = opts.pos or {x = 100, y = 100, z = 7},
		player = opts.player ~= false, monster = opts.monster or false, health = opts.health or 500,
		log = {msgs = {}, items = {}, teleports = {}, events = {}, targets = {}}}
	function cr:isPlayer() return self.player end
	function cr:isMonster() return self.monster end
	function cr:isNpc() return false end
	function cr:getId() return self.id end
	function cr:getName() return self.name end
	function cr:getStorageValue(k) return self.store[k] or -1 end
	function cr:setStorageValue(k, v) self.store[k] = v end
	function cr:getPosition() return self.pos end
	function cr:getLevel() return 100 end
	function cr:getHealth() return self.health end
	function cr:getMaxHealth() return 500 end
	function cr:getMaster() return self.master end
	function cr:getTarget() return self.target end
	function cr:setTarget(t) self.target = t; self.log.targets[#self.log.targets + 1] = t end
	function cr:setDirection(dir) self.dir = dir end
	function cr:registerEvent(n) self.log.events[#self.log.events + 1] = n end
	function cr:teleportTo(p) self.log.teleports[#self.log.teleports + 1] = p; self.pos = p end
	function cr:sendTextMessage(kind, text) self.log.msgs[#self.log.msgs + 1] = text end
	function cr:getSlotItem(slot)
		return self.slots and self.slots[slot]
	end
	function cr:addItem(itemId, n, _, _, slot)
		self.log.items[#self.log.items + 1] = {itemId, n, slot}
		if slot then
			self.slots = self.slots or {}
			local bag = {addItem = function(_, i, k) self.log.items[#self.log.items + 1] = {i, k, "bag"} end,
				isContainer = function() return true end, getSize = function() return 0 end}
			self.slots[slot] = bag
			return bag
		end
		return true
	end
	function cr:getVocation() return {getId = function() return 4 end} end
	function cr:getTown() return {getTemplePosition = function() return {x = 50, y = 50, z = 7} end} end
	function cr:getBankBalance() return self.bank or 0 end
	function cr:setBankBalance(v) self.bank = v end
	function cr:getMonsterLevel() return 10 end
	byId[id] = cr
	return cr
end
function Player(id)
	local p = byId[type(id) == "table" and id.id or id]
	return p and p.player and p or nil
end

local ST = Chaos.storage.tester
local tester = creature(268435457, "Tester Abc", {store = {[ST] = 1}})
local ana = creature(268435458, "Ana") -- a real player
local fake = creature(268435459, "Tester Abz") -- a tester's name, no storage
local marked = creature(268435460, "Bob", {store = {[ST] = 1}}) -- the storage, not a tester's name
local wolf = creature(1073741825, "wolf", {player = false, monster = true, pos = {x = 102, y = 100, z = 7}, health = 30})
local pet = creature(1073741826, "pet", {player = false, monster = true, pos = {x = 101, y = 100, z = 7}, health = 30})
pet.master = ana
local spectators = {ana, fake, marked, pet, wolf}
Game = {getSpectators = function() return spectators end, getPlayers = function() return {} end}

local origPrint = print
print = function(...)
	local parts = {}
	for i = 1, select("#", ...) do parts[#parts + 1] = tostring(select(i, ...)) end
	printed[#printed + 1] = table.concat(parts, " ")
end
dofile("tools/tester_helper.lua")
local T = TesterHelper

check(talks["!tester"] ~= nil, "the !tester talkaction registered")
check(events.TesterHelperLogin and events.TesterHelperHealth and events.TesterHelperDealt and events.TesterHelperDeath,
	"the creature events registered")
eq(#timers, 1, "the target loop started at load")
eq(timers[1].ms, 500, "every 500 ms")
check(printed[#printed]:find("[tester-helper] running", 1, true) ~= nil, "the running line for chaos-ctl")
dofile("tools/tester_helper.lua")
eq(#timers, 1, "a reload does not start a second loop")
T.present = function() return true end -- the file is in data/scripts while the helper runs

-- ------------------------------------------------------------------ the people the helper must never touch
local others = {ana, fake, marked}
for _, p in ipairs(others) do
	check(events.TesterHelperLogin.onLogin(p) == true, p.name .. ": login goes on")
	check(talks["!tester"].onSay(p, "!tester", "town") == true, p.name .. ": !tester is left to the game")
	check(talks["!tester"].onSay(p, "!tester", "depot") == true, p.name .. ": !tester depot is left to the game")
end
local before = #printed
for _, p in ipairs(others) do
	local a1, b1, c1, d1 = events.TesterHelperHealth.onHealthChange(p, wolf, 130000000, COMBAT_PHYSICALDAMAGE, 0, 0, 0)
	eq(a1, 130000000, p.name .. ": damage passes unchanged")
	events.TesterHelperDealt.onHealthChange(wolf, p, 99999999, COMBAT_PHYSICALDAMAGE, 0, 0, 0)
	events.TesterHelperDeath.onDeath(p, nil, wolf, wolf)
	eq(callbacks.onGainExperience(p, wolf, -5, -5), -5, p.name .. ": experience passes unchanged")
end
eq(#printed, before, "nothing logged about the other players")
-- even when slipped into the loop's list, a player is dropped, never targeted
T.ids[ana.id], T.ids[fake.id], T.ids[marked.id] = true, true, true
for _ = 1, 8 do
	lastStep().fn()
end
check(T.ids[ana.id] == nil and T.ids[fake.id] == nil and T.ids[marked.id] == nil, "the loop drops non-testers")
for _, p in ipairs(others) do
	eq(#p.log.msgs, 0, p.name .. ": no message")
	eq(#p.log.items, 0, p.name .. ": no item")
	eq(#p.log.teleports, 0, p.name .. ": no teleport")
	eq(#p.log.events, 0, p.name .. ": no event registered")
	eq(#p.log.targets, 0, p.name .. ": no target set")
	eq(p.bank, nil, p.name .. ": no gold")
	check(p.store[ST + 1] == nil and p.store[ST + 2] == nil and p.store[ST + 3] == nil, p.name .. ": no storage written")
end

-- ------------------------------------------------------------------ the tester
check(events.TesterHelperLogin.onLogin(tester) == true, "tester: login")
eq(tester.store[ST + 1], 1, "supplies given")
eq(tester.store[ST + 2], 100, "hunt spot x from the login position")
eq(tester.bank, 20000, "the bank gold")
local got = {}
for _, it in ipairs(tester.log.items) do got[it[1]] = it end
check(got[1988] and got[1988][3] == CONST_SLOT_BACKPACK, "a backpack")
check(got[8209] and got[8209][3] == CONST_SLOT_LEFT, "the kit weapon in the hand")
check(got[7618] and got[7618][3] == "bag" and got[7618][2] == 100, "health potions in the backpack")
local n = #tester.log.items
events.TesterHelperLogin.onLogin(tester)
eq(#tester.log.items, n, "supplies only once")
eq(tester.bank, 20000, "gold only once")

check(talks["!tester"].onSay(tester, "!tester", "town") == false, "tester: !tester consumed")
eq(tester.log.teleports[#tester.log.teleports].x, 50, "town: to the temple")
check(tester.log.msgs[#tester.log.msgs]:find('^%[tester%-helper%] town {"pos":') ~= nil, "town: the answer line")
talks["!tester"].onSay(tester, "!tester", "hunt")
eq(tester.pos.x, 100, "hunt: back to the hunt spot")
talks["!tester"].onSay(tester, "!tester", "fly")
check(tester.log.msgs[#tester.log.msgs]:find("unknown command", 1, true) ~= nil, "an unknown command answers an error")
talks["!tester"].onSay(tester, "!tester", "depot")
check(tester.log.msgs[#tester.log.msgs]:find('depot {"err":', 1, true) ~= nil, "no locker: an error answer")

-- the target loop: the tester gets the nearest monster, never a player or a player's summon
T.ids[tester.id] = true
for _ = 1, 8 do
	lastStep().fn()
end
eq(tester.target, wolf, "the tester targets the wolf")
eq(tester.dir, 1, "and faces it (east)")
for _, t in ipairs(tester.log.targets) do
	check(t.monster and not t.master, "only unowned monsters are ever targeted")
end

before = #printed
local r1, r2, r3, r4 = events.TesterHelperHealth.onHealthChange(tester, wolf, 130000000, COMBAT_PHYSICALDAMAGE, 0, 0, 0)
check(r1 == 130000000 and r2 == COMBAT_PHYSICALDAMAGE and r3 == 0 and r4 == 0, "damage to a tester is not changed")
check(printed[#printed]:find('[tester-anomaly] {"by":"wolf"', 1, true) ~= nil, "the 130M hit is logged")
check(printed[#printed]:find('"rule":"hit taken over 3x max health"', 1, true) ~= nil, "with its rule")
events.TesterHelperHealth.onHealthChange(tester, tester, 1000000, COMBAT_HEALING, 0, 0, 0)
eq(#printed, before + 1, "healing is not a hit")
events.TesterHelperDealt.onHealthChange(wolf, tester, 99999999, COMBAT_PHYSICALDAMAGE, 0, 0, 0)
check(printed[#printed]:find('"rule":"hit dealt far above the level"', 1, true) ~= nil, "an absurd hit dealt is logged")
eq(callbacks.onGainExperience(tester, wolf, -5, -5), -5, "experience is not changed")
check(printed[#printed]:find('"rule":"negative experience gain"', 1, true) ~= nil, "negative xp is logged")
events.TesterHelperDeath.onDeath(tester, nil, wolf, wolf)
check(printed[#printed]:find('[tester-event] {"killer":"wolf"', 1, true) ~= nil, "the death event")

-- stopped: chaos-ctl removed the file, the helper does nothing more
T.present = function() return false end
local tp = #tester.log.teleports
check(talks["!tester"].onSay(tester, "!tester", "town") == true, "a stopped helper leaves !tester alone")
eq(#tester.log.teleports, tp, "and teleports nobody")
for _ = 1, 20 do
	local t, i = lastStep()
	t.fn()
	if select(2, lastStep()) == i then break end
end
check(not T.started, "the loop ends once the file is gone")

print = origPrint
print(string.format("tester_helper_test: %d checks, %d failures", count, failures))
os.exit(failures == 0 and 0 or 1)
