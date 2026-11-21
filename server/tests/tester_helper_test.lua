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
-- the death record: hits of the last 5 seconds, their sum and the biggest, as a percent of the maximum health
local hl = {}
H.pushHit(hl, 100, {damage = 40, by = "wolf"})
H.pushHit(hl, 103, {damage = 120, by = "bear"})
H.pushHit(hl, 104, {damage = -5, by = "rat"})
local rec = H.deathRecord(hl, 105, {who = "Tester Aaa", level = 30, killer = "bear", maxHealth = 400, secsOnline = 12})
eq(rec.hits, 3, "death record: three hits")
eq(rec.damage, 160, "their sum (a negative one counts 0)")
eq(rec.damagePct, 40, "as a percent of the maximum")
eq(rec.biggest, 120, "the biggest hit")
eq(rec.biggestPct, 30, "its percent")
eq(rec.biggestBy, "bear", "and who dealt it")
eq(rec.secsOnline, 12, "seconds online")
eq(H.deathRecord(hl, 109, {who = "x", maxHealth = 400}).hits, 1, "hits older than 5 seconds are not in the record")
eq(H.deathRecord(nil, 109, {who = "x", maxHealth = 0}).hits, 0, "no hits: an empty record")
eq(H.deathRecord({}, 1, {who = "x"}).killer, "?", "no killer: ?")
for i = 1, 100 do H.pushHit(hl, 200 + i, {damage = 1}) end
check(#hl <= H.HIT_KEEP, "the list stays short")
eq(H.hotSpot(40, {{"a", 30}, {"b", 90}, {"c", 500}})[1], "c", "hotSpot: the highest above the level")
eq(H.hotSpot(40, {{"a", 30}, {"b", 40}}), nil, "hotSpot: nothing above")
eq(H.hotSpot(40, nil), nil, "hotSpot: no monsters")
eq(H.hotSpot(287, {{"Urzog", 300}}), nil, "hotSpot: a few levels lost by dying keep the spot")
eq(H.hotSpot(40, {{"a", 65}}), nil, "hotSpot: the margin is at least 25 levels")
eq(H.hotSpot(40, {{"a", 66}})[1], "a", "hotSpot: over the margin")
eq(H.hotSpot(575, {{"Embermaw Archon", 2100}})[1], "Embermaw Archon", "hotSpot: a far higher monster")
-- the fist pair of the probe (O580): the best two plain fist weapons the level may wield (code 33 = NOTENOUGHLEVEL otherwise)
local fistItems = {[40000] = {level = 1}, [36654] = {level = 8}, [40009] = {level = 14, unique = "Vigil-Knot Wraps"},
	[40010] = {level = 26, unique = "Chapel-Iron Knuckles"}, [40001] = {level = 35}, [36655] = {level = 60},
	[40002] = {level = 100}, [36656] = {level = 150}, [36657] = {level = 300}, [36659] = {level = 650, unique = "Grasp"}}
local function pair(level) local p = H.fistPair(level, fistItems, {36656, 36657}) return p[1] .. "," .. p[2] end
eq(pair(30), "36654,40000", "fistPair: level 30 wears the level 8 and the level 1 weapon")
eq(pair(100), "40002,36655", "fistPair: level 100")
eq(pair(150), "36656,40002", "fistPair: level 150 (the old probe failed the second hand at 150-299)")
eq(pair(299), "36656,40002", "fistPair: level 299")
eq(pair(300), "36657,36656", "fistPair: level 300")
eq(pair(2000), "36657,36656", "fistPair: a unique is never picked")
eq(pair(1), "40000,40000", "fistPair: only one fits: the same one twice")
eq(pair(0), "36656,36657", "fistPair: none fits: the fallback")
eq(H.fistPair(50, nil, {1, 2})[2], 2, "fistPair: no table: the fallback")
-- hunt marks for a level (O580): the band is read from the name, the whole band must be at or under the level
local lo, hi = H.huntBand("Hunting: Penguin, Mammoth (level 1-20)")
check(lo == 1 and hi == 20 and H.huntBand("Temple") == nil, "huntBand reads the band of a hunt mark")
local huntMarks = {{k = "hunt", x = 1, y = 1, z = 7, n = "Hunting: A (level 1-20)"},
	{k = "hunt", x = 2, y = 2, z = 7, n = "Hunting: B (level 20-90)"}, {k = "hunt", x = 3, y = 3, z = 7, n = "Hunting: C (level 70-80)"},
	{k = "hunt", x = 4, y = 4, z = 7, n = "Hunting: D (level 60-85)"}, {k = "hunt", x = 5, y = 5, z = 7, n = "no band"},
	{k = "boss", x = 6, y = 6, z = 7, n = "Boss (level 10-20)"}}
local function xs(list) local o = {} for _, m in ipairs(list) do o[#o + 1] = m.x end return table.concat(o, ",") end
eq(xs(H.huntCandidates(huntMarks, 100, 0)), "2,4,3,1", "huntCandidates: tops 90 and 85 first (>= 0.8 x 90), then 80, then 20")
eq(xs(H.huntCandidates(huntMarks, 100, 1)), "4,3,2,1", "huntCandidates: the seed turns the best group (90, 85, 80), not the rest")
eq(xs(H.huntCandidates(huntMarks, 30, 0)), "1", "huntCandidates: only the bands at or under level 30")
eq(xs(H.huntCandidates(huntMarks, 5, 0)), "1,3,4,2", "huntCandidates: none fits: the lowest band first, then upward")
eq(#H.huntCandidates(nil, 100, 0), 0, "huntCandidates: no marks")
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

-- places: `!tester enter <kind> [N]`, `enter npc <name>`, `enter rift [tier]`
local pl = H.parsePlace("rift 3")
check(pl and pl.kind == "rift" and pl.tier == 3, "enter rift 3")
eq(H.parsePlace("rift").tier, 1, "a rift key of tier 1 by default")
eq(H.parsePlace("rift 99").tier, H.RIFT_MAX, "the tier is capped")
eq(H.parsePlace("rift -4").tier, 1, "and at least 1")
pl = H.parsePlace("npc Keeper of Trials")
check(pl and pl.kind == "npc" and pl.name == "Keeper of Trials", "enter npc <name>")
eq(H.parsePlace("npc "), nil, "an NPC needs a name")
eq(H.parsePlace("npc Bob\"; drop"), nil, "an NPC name has letters only")
pl = H.parsePlace("Boss 2")
check(pl and pl.kind == "boss" and pl.n == 2, "enter boss 2")
eq(H.parsePlace("boss").n, nil, "enter boss: the first")
eq(H.parsePlace("boss x"), nil, "a bad number")
eq(H.parsePlace("boss 1.5"), nil, "not a whole number")
eq(H.parsePlace("guild"), nil, "guild halls are out of scope")
eq(H.parsePlace("player Ana"), nil, "never a player")
eq(H.parsePlace(nil), nil, "no place")
local mk = {{k = "boss", x = 1, y = 1, z = 7, n = "A"}, {k = "temple", x = 2, y = 2, z = 7},
	{k = "boss", x = 3, y = 3, z = 7, n = "B"}, {k = "guild", x = 4, y = 4, z = 7}, {k = "npc", x = 5, y = 5, z = 7}}
local m1, cnt = H.pickMark(mk, "boss", 2)
eq(m1 and m1.n, "B", "the second boss mark")
eq(cnt, 2, "of two")
eq(H.pickMark(mk, "boss", 3).n, "A", "the number wraps")
eq(H.pickMark(mk, "boss").n, "A", "the first by default")
eq(H.pickMark(mk, "bank"), nil, "no bank mark")
local pc = H.placeCounts(mk)
check(pc.boss == 2 and pc.temple == 1 and pc.guild == nil and pc.npc == nil, "place counts, no guilds, NPCs by name")

-- the console line of the testers online
eq(H.onlineLine(12, nil, 1), "[tester-helper] testers online: 12", "the first count is logged")
eq(H.onlineLine(12, 12, 3), nil, "the same count is not logged again")
eq(H.onlineLine(0, 12, 3), "[tester-helper] testers online: 0", "a change is logged")
eq(H.onlineLine(12, 12, 10), "[tester-helper] testers online: 12", "every 5 minutes it is logged anyway")

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
-- the engine passes damage negative: the record must still see it
eq(H.damageOf(-40, COMBAT_PHYSICALDAMAGE, -10, COMBAT_FIREDAMAGE), 50, "negative engine damage counts as its size")
eq(H.damageOf(40, COMBAT_HEALING, 0, 0), 0, "healing is no damage")
eq(H.damageOf(-40, COMBAT_PHYSICALDAMAGE, 15, COMBAT_HEALING), 40, "a healing second part is left out")
eq(H.damageOf(nil, 0, 0 / 0, 0), 0, "nothing, nan: 0")
COMBAT_FIREDAMAGE = COMBAT_FIREDAMAGE or 2
CONST_SLOT_BACKPACK, CONST_SLOT_LEFT, CONST_SLOT_RIGHT = 3, 6, 5
CONST_SLOT_HEAD, CONST_SLOT_NECKLACE, CONST_SLOT_ARMOR, CONST_SLOT_LEGS, CONST_SLOT_FEET, CONST_SLOT_RING = 1, 2, 4, 7, 8, 9
TILESTATE_BLOCKSOLID = 1
TILESTATE_FLOORCHANGE = 2
TILESTATE_TELEPORT = 4
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
	function cr:unregisterEvent(n)
		for i, e in ipairs(self.log.events) do
			if e == n then
				table.remove(self.log.events, i)
				return true
			end
		end
		return false
	end
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
local npcs = {["Keeper of Trials"] = {getName = function() return "Keeper of Trials" end, isNpc = function() return true end,
	getPosition = function() return {x = 70, y = 70, z = 7} end}}
function Creature(name)
	if npcs[name] then return npcs[name] end
	for _, c in pairs(byId) do
		if c.name == name then return c end
	end
end
ChaosPoi = {all = {{k = "boss", x = 300, y = 300, z = 8, n = "Boss A"}, {k = "boss", x = 310, y = 300, z = 8, n = "Boss B"},
	{k = "guild", x = 9, y = 9, z = 7}}}
local keys = {}
ChaosRift = {giveKey = function(p, key, why) keys[#keys + 1] = {who = p, key = key} end}
ChaosRiftConfig = {key = {itemId = 10155}}
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
check(printed[#printed]:find("[tester-helper] running v" .. tostring(HELPER_VERSION) .. " ", 1, true) ~= nil, "the running line for chaos-ctl carries the version")
dofile("tools/tester_helper.lua")
eq(#timers, 1, "a reload does not start a second loop")
T.present = function() return true end -- the file is in data/scripts while the helper runs

-- ------------------------------------------------------------------ the people the helper must never touch
local others = {ana, fake, marked}
for _, p in ipairs(others) do
	check(events.TesterHelperLogin.onLogin(p) == true, p.name .. ": login goes on")
	check(talks["!tester"].onSay(p, "!tester", "town") == true, p.name .. ": !tester is left to the game")
	check(talks["!tester"].onSay(p, "!tester", "depot") == true, p.name .. ": !tester depot is left to the game")
	check(talks["!tester"].onSay(p, "!tester", "enter rift 5") == true, p.name .. ": !tester enter is left to the game")
	check(talks["!tester"].onSay(p, "!tester", "enter boss") == true, p.name .. ": enter boss too")
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
-- a hunt spot with a monster above the tester (a spot from before the safe-spawn fix): the tester stays where it is
local lvl = {wolf = 9999}
local realMhl = Chaos.monsterHuntingLevel
Chaos.monsterHuntingLevel = function(m) return lvl[m:getName()] or 0 end
talks["!tester"].onSay(tester, "!tester", "town")
talks["!tester"].onSay(tester, "!tester", "hunt")
eq(tester.pos.x, 50, "hunt spot with a monster far above the level: no teleport")
check(tester.log.msgs[#tester.log.msgs]:find('"err":"hunt spot too high: ', 1, true) ~= nil, "and the answer names it")
-- O580: a hunt of the tester's level is looked for before the bot stays in the temple for good. The marks: a band above
-- the level (never), a band at the level with a high monster beside it (skipped), a clean band at the level (taken)
local realTile, realSpect, realPoi = Tile, Game.getSpectators, ChaosPoi
function Tile(p)
	return {getGround = function() return true end, hasFlag = function() return false end,
		getTopCreature = function() return nil end}
end
ChaosPoi = {all = {
	{k = "hunt", x = 300, y = 300, z = 7, n = "Hunting: Dragon (level 300-400)"},
	{k = "hunt", x = 200, y = 200, z = 7, n = "Hunting: Hound (level 60-90)"},
	{k = "hunt", x = 210, y = 210, z = 7, n = "Hunting: Rat (level 40-80)"},
	{k = "temple", x = 50, y = 50, z = 7, n = "Temple"},
}}
local nearPos = {}
Game.getSpectators = function(p)
	-- the old spot (100, 100) and the mark of the Hound hold a monster far above level 100; the Rat's mark is clean
	if (p.x == 100 and p.y == 100) or (p.x >= 199 and p.x <= 203 and p.y >= 199 and p.y <= 203) then
		return {wolf}
	end
	nearPos[#nearPos + 1] = p.x
	return {}
end
tester.pos = {x = 50, y = 50, z = 7}
talks["!tester"].onSay(tester, "!tester", "hunt")
check(tester.pos.x >= 209 and tester.pos.x <= 213 and tester.pos.y >= 209 and tester.pos.y <= 213,
	"hunt spot too high: the bot goes to the clean hunt of its level (" .. tostring(tester.pos.x) .. ")")
check(tester.log.msgs[#tester.log.msgs]:find('"moved":{', 1, true) ~= nil, "and the answer says it moved")
eq(tester.store[ST + 2], tester.pos.x, "the new spot is the bot's hunt spot from now on")
for _, x in ipairs(nearPos) do
	check(x ~= 300, "a band above the level is never a candidate")
end
-- no clean hunt: it stays
Game.getSpectators = function() return {wolf} end
tester.store[ST + 2], tester.store[ST + 3], tester.store[ST + 4] = 100, 100, 7
tester.pos = {x = 50, y = 50, z = 7}
talks["!tester"].onSay(tester, "!tester", "hunt")
eq(tester.pos.x, 50, "no clean hunt: no teleport")
check(tester.log.msgs[#tester.log.msgs]:find('"err":"hunt spot too high: ', 1, true) ~= nil, "no clean hunt: the old answer")
Tile, Game.getSpectators, ChaosPoi = realTile, realSpect, realPoi
Chaos.monsterHuntingLevel = realMhl
talks["!tester"].onSay(tester, "!tester", "hunt")
eq(tester.pos.x, 100, "a spot within the level: teleport")
talks["!tester"].onSay(tester, "!tester", "fly")
check(tester.log.msgs[#tester.log.msgs]:find("unknown command", 1, true) ~= nil, "an unknown command answers an error")
talks["!tester"].onSay(tester, "!tester", "depot")
check(tester.log.msgs[#tester.log.msgs]:find('depot {"err":', 1, true) ~= nil, "no locker: an error answer")

-- enter: only the tester moves; a rift key goes to the tester; a player's name is never an NPC
local function last(p) return p.log.msgs[#p.log.msgs] end
talks["!tester"].onSay(tester, "!tester", "places")
check(last(tester):find('places {"counts":{"boss":2}}', 1, true) ~= nil, "places: the counts, no guild halls")
talks["!tester"].onSay(tester, "!tester", "enter boss 2")
check(last(tester):find('enter {"count":2,"err":"no free tile"', 1, true) ~= nil, "a blocked place is an error answer")
local realTile = Tile
Tile = function() return {getGround = function() return true end, hasFlag = function() return false end,
	getTopCreature = function() return nil end} end
talks["!tester"].onSay(tester, "!tester", "enter boss 2")
eq(tester.pos.x, 310, "enter boss 2: next to the second boss mark")
eq(tester.pos.y, 299, "enter boss 2: a straight neighbour first (north)")
check(last(tester):find('"name":"Boss B"', 1, true) ~= nil, "enter: the answer names the place")
talks["!tester"].onSay(tester, "!tester", "enter npc Keeper of Trials")
eq(tester.pos.x, 70, "enter npc: next to the NPC")
check(last(tester):find('"npc":"Keeper of Trials"', 1, true) ~= nil, "enter npc: the answer")
-- shop: a trader first (the NPC nearest the temple may only talk), the nearest NPC without one
talks["!tester"].onSay(tester, "!tester", "shop")
check(last(tester):find('shop {"err":"no NPC near the temple"}', 1, true) ~= nil, "shop: no trader, no NPC near: an error")
npcs["Material Broker"] = {getName = function() return "Material Broker" end, isNpc = function() return true end,
	getPosition = function() return {x = 80, y = 80, z = 7} end, getId = function() return 9001 end}
talks["!tester"].onSay(tester, "!tester", "shop")
eq(tester.pos.x, 80, "shop: next to the trader")
eq(tester.pos.y, 79, "shop: north of it first")
-- another NPC as near the north tile: only the nearest NPC answers there (chaos_npc_focus.lua), so the tile east
local stall = {isNpc = function() return true end, getId = function() return 9002 end,
	getPosition = function() return {x = 80, y = 78, z = 7} end}
spectators[#spectators + 1] = stall
talks["!tester"].onSay(tester, "!tester", "shop")
eq(tester.pos.x, 81, "shop: not where another NPC is as near")
eq(tester.pos.y, 80, "shop: the east tile")
spectators[#spectators] = nil
-- no floor change or teleport tile
Tile = function(p) return {getGround = function() return true end, getTopCreature = function() return nil end,
	hasFlag = function(_, f) return p.y == 79 and f == TILESTATE_FLOORCHANGE end} end
talks["!tester"].onSay(tester, "!tester", "shop")
eq(tester.pos.x, 81, "shop: never onto a floor change (north is stairs)")
check(last(tester):find('"npc":"Material Broker"', 1, true) ~= nil, "shop: the answer names the trader")
npcs["Material Broker"] = nil
local tps = #tester.log.teleports
talks["!tester"].onSay(tester, "!tester", "enter npc Ana")
check(last(tester):find('"err":"no such NPC"', 1, true) ~= nil, "a player's name is not an NPC")
eq(#tester.log.teleports, tps, "and nobody moves")
eq(#ana.log.teleports, 0, "Ana stays where she is")
local keyRemoved = 0
function tester:getItemById(id)
	if #keys > keyRemoved then
		return {remove = function() keyRemoved = keyRemoved + 1 return true end}
	end
	return nil
end
-- !tester pet: the first species of the config, granted once
do
	local owned, granted = {}, 0
	ChaosPetsConfig = {species = {{key = "ember_whelp"}}}
	ChaosPets = {owns = function(_, k) return owned[k] == true end,
		grant = function(_, k, src, quiet) granted = granted + 1; owned[k] = src == "staff" and quiet == true end}
	talks["!tester"].onSay(tester, "!tester", "pet")
	check(last(tester):find('"owns":true', 1, true) ~= nil and granted == 1, "pet: granted quietly as staff")
	talks["!tester"].onSay(tester, "!tester", "pet")
	check(last(tester):find('"had":true', 1, true) ~= nil and granted == 1, "pet: an owned pet is not granted again")
	-- the live pet and why it waits (the pets check tells a game rule from a bug)
	check(last(tester):find('"cid"', 1, true) == nil, "pet: none out, no creature id")
	local realCreature, realGuid = Creature, tester.getGuid
	Creature = function(id) return id == pet.id and pet or nil end
	function pet:isRemoved() return false end
	tester.getGuid = function() return 77 end
	ChaosPets.live = {[tester.id] = {species = "ember_whelp", cid = pet.id}}
	ChaosPets.cool = {[77] = {summon = os.time() + 30, death = 0}}
	talks["!tester"].onSay(tester, "!tester", "pet")
	check(last(tester):find('"cid":' .. pet.id, 1, true) ~= nil, "pet: the live pet's creature id")
	check(last(tester):find('"summonLeft":3', 1, true) ~= nil and last(tester):find('"deathLeft":0', 1, true) ~= nil,
		"pet: the call and death cooldowns left")
	ChaosPets.live[tester.id] = {species = "ember_whelp", rest = "summons"}
	talks["!tester"].onSay(tester, "!tester", "pet")
	check(last(tester):find('"rest":"summons"', 1, true) ~= nil and last(tester):find('"cid"', 1, true) == nil,
		"pet: a resting pet says why")
	Creature, tester.getGuid = realCreature, realGuid
	ChaosPets, ChaosPetsConfig = nil, nil
end
talks["!tester"].onSay(tester, "!tester", "enter rift 4")
eq(#keys, 1, "a rift key")
check(last(tester):find('"held":true', 1, true) ~= nil and keyRemoved == 1, "the key is read back and taken again")
check(keys[1].who == tester and keys[1].key.tier == 4 and #keys[1].key.mods == 0, "tier 4, no modifiers, to the tester")
check(last(tester):find('"keyClientId":20155', 1, true) ~= nil, "the key's client id for the hotkey use")
eq(tester.pos.x, 50, "and the tester waits in the temple")
-- a full bag: the key lies under the tester (player:addItem's rule); found there, taken away, told as bagFull
do
	local realGet, realTileF, groundTaken = tester.getItemById, Tile, 0
	function tester:getItemById() return nil end
	Tile = function() return {getItemById = function() return {remove = function() groundTaken = groundTaken + 1 end} end} end
	talks["!tester"].onSay(tester, "!tester", "enter rift 2")
	check(last(tester):find('"held":false', 1, true) ~= nil and last(tester):find('"bagFull":true', 1, true) ~= nil,
		"full bag: not held, bagFull")
	eq(groundTaken, 1, "full bag: the key on the ground is taken away")
	Tile = function() return nil end
	talks["!tester"].onSay(tester, "!tester", "enter rift 2")
	check(last(tester):find('"held":false', 1, true) ~= nil and last(tester):find('bagFull', 1, true) == nil,
		"no key anywhere: not held, no bagFull (the check fails)")
	-- RF.giveKey answers true when the key went to the inbox (a full bag)
	local realGive, inboxTaken = ChaosRift.giveKey, 0
	ChaosRift.giveKey = function() return true end
	function tester:getInbox()
		return {getItems = function() return {{getId = function() return ChaosRiftConfig.key.itemId end,
			remove = function() inboxTaken = inboxTaken + 1 end}} end}
	end
	talks["!tester"].onSay(tester, "!tester", "enter rift 2")
	check(last(tester):find('"bagFull":true', 1, true) ~= nil and inboxTaken == 1, "full bag: the key in the inbox, taken again")
	ChaosRift.giveKey, tester.getInbox = realGive, nil
	tester.getItemById, Tile = realGet, realTileF
end
talks["!tester"].onSay(tester, "!tester", "enter guild")
check(last(tester):find('"err":"unknown place"', 1, true) ~= nil, "guild halls: unknown place")
Tile = realTile
talks["!tester"].onSay(tester, "!tester", "hunt")
eq(tester.pos.x, 100, "back to the hunt spot")

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

-- O681: inside a pinnacle fight an add of a phase comes before the boss: the loop aims the tester at it (ChaosPinnacle.priorityTarget), then the boss again
do
	local add = creature(1073741999, "Drowned Anchor", {player = false, monster = true, pos = {x = 103, y = 100, z = 7}, health = 150000})
	local realPN = ChaosPinnacle
	local ask = 0
	ChaosPinnacle = {priorityTarget = function(p)
		ask = ask + 1
		if add.dead then
			return nil
		end
		return add
	end}
	tester.target = wolf
	local n0 = #tester.log.targets
	for _ = 1, 8 do
		lastStep().fn()
	end
	eq(tester.target, add, "pinnacle: the tester aims at the add that shields the boss, not the boss it had")
	check(ask >= 1 and #tester.log.targets == n0 + 1, "pinnacle: the target is changed once, not every beat")
	eq(tester.dir, 1, "pinnacle: and it faces the add (east)")
	add.dead = true
	tester.target = nil
	for _ = 1, 8 do
		lastStep().fn()
	end
	eq(tester.target, wolf, "pinnacle: the add gone, the loop aims at the nearest monster again")
	ChaosPinnacle = {priorityTarget = function() error("a probe that breaks") end}
	tester.target = nil
	for _ = 1, 8 do
		lastStep().fn()
	end
	eq(tester.target, wolf, "pinnacle: a priority call that breaks does not stop the loop")
	ChaosPinnacle = realPN
	byId[add.id] = nil
end

-- O695: inside a pinnacle fight the loop aims the tester at the boss of its fight before the nearest monster, when it is in reach; the boss carries the
-- damage event; the damage tally counts the hits on the boss apart from the others
do
	check(HELPER_VERSION >= 38, "the helper is version 38 or later (O695: boss aim, damage tally)")
	local boss = creature(1073742500, "Ascended Malgrath", {player = false, monster = true, pos = {x = 105, y = 100, z = 7}, health = 900000})
	local farBoss = creature(1073742501, "Far Boss", {player = false, monster = true, pos = {x = 140, y = 100, z = 7}, health = 900000})
	local realPN = ChaosPinnacle
	local which = boss
	ChaosPinnacle = {bossOf = function() return which end, isBoss = function(c) return c == boss end}
	tester.target = wolf
	for _ = 1, 8 do
		lastStep().fn()
	end
	eq(tester.target, boss, "boss aim: the tester hits the boss of its fight, not the nearest monster it had")
	local carried = 0
	for _, e in ipairs(boss.log.events) do
		if e == "TesterHelperDealt" then carried = carried + 1 end
	end
	check(carried >= 1, "boss aim: the boss carries the damage event")
	local n0 = #tester.log.targets
	for _ = 1, 8 do
		lastStep().fn()
	end
	eq(#tester.log.targets, n0, "boss aim: the target is set once, not every beat")
	which = farBoss
	tester.target = wolf
	for _ = 1, 8 do
		lastStep().fn()
	end
	eq(tester.target, wolf, "boss aim: a boss out of reach is not aimed at (the nearest monster stays)")
	ChaosPinnacle = {bossOf = function() error("a probe that breaks") end}
	for _ = 1, 8 do
		lastStep().fn()
	end
	eq(tester.target, wolf, "boss aim: a probe that breaks does not stop the loop")
	ChaosPinnacle = {bossOf = function() return boss end, isBoss = function(c) return c == boss end,
		priorityTarget = function() return wolf end}
	tester.target = boss
	for _ = 1, 8 do
		lastStep().fn()
	end
	eq(tester.target, wolf, "boss aim: an add that shields the boss still comes first")
	-- the tally
	TesterHelper.dealt = nil
	events.TesterHelperDealt.onHealthChange(boss, tester, -1000, COMBAT_PHYSICALDAMAGE, -500, COMBAT_PHYSICALDAMAGE, 0)
	events.TesterHelperDealt.onHealthChange(wolf, tester, -200, COMBAT_PHYSICALDAMAGE, 0, 0, 0)
	events.TesterHelperDealt.onHealthChange(boss, tester, 5000, COMBAT_HEALING, 0, 0, 0)
	local row = H.dealtRow(TesterHelper.dealt, tester.id)
	check(row and row.boss == 1500 and row.bossHits == 1 and row.other == 200 and row.otherHits == 1, "damage tally: the boss and the others apart, healing not counted")
	TesterHelper.dealt = nil
	ChaosPinnacle = realPN
	byId[boss.id], byId[farBoss.id] = nil, nil
end

-- O697: the late event, the ledger and the kinds of a hit on the boss
do
	check(HELPER_VERSION >= 39, "the helper is version 39 or later (O697: the boss's last event and ledger)")
	check(events.TesterHelperDealtLate ~= nil, "the late damage event is registered")
	local boss = creature(1073742600, "Ascended Malgrath", {player = false, monster = true, pos = {x = 105, y = 100, z = 7}, health = 1000000})
	local realPN = ChaosPinnacle
	ChaosPinnacle = {bossOf = function() return boss end, isBoss = function(c) return c == boss end}
	tester.target = nil
	for _ = 1, 8 do
		lastStep().fn()
	end
	local names = boss.log.events
	eq(names[#names], "TesterHelperDealtLate", "the boss carries the late event last")
	local early, late = 0, 0
	for _, e in ipairs(names) do
		if e == "TesterHelperDealt" then early = early + 1 elseif e == "TesterHelperDealtLate" then late = late + 1 end
	end
	check(early >= 1 and late == 1, "the boss carries the early event and the late event once")
	-- a later event (what a first hit registers) comes behind the late one; the next round puts the late one back last
	boss:registerEvent("ChaosPassiveDealt")
	for _ = 1, 8 do
		lastStep().fn()
	end
	eq(names[#names], "TesterHelperDealtLate", "after another event was registered the loop puts the late event behind it again")
	-- the hits
	TesterHelper.dealt, TesterHelper.dealtLate, TesterHelper.bossLedger = nil, nil, nil
	local summon = creature(1073742601, "Illusion", {player = false, monster = true})
	summon.master = tester
	local stranger = creature(1073742602, "Ashveil Hierarch", {player = false, monster = true})
	local person = creature(1073742603, "Ana Two", {player = true})
	local L = events.TesterHelperDealtLate
	local COND = 7
	rawset(_G, "ORIGIN_CONDITION", COND)
	boss.health = 1000000
	L.onHealthChange(boss, tester, -1000, COMBAT_PHYSICALDAMAGE, -500, COMBAT_PHYSICALDAMAGE, 3)
	boss.health = 998500
	L.onHealthChange(boss, summon, -2000, COMBAT_PHYSICALDAMAGE, 0, 0, 3)
	boss.health = 996500
	L.onHealthChange(boss, tester, -300, COMBAT_FIREDAMAGE, 0, 0, COND)
	boss.health = 996200
	L.onHealthChange(boss, nil, -700, COMBAT_PHYSICALDAMAGE, 0, 0, 3)
	boss.health = 995500
	L.onHealthChange(boss, boss, -200, COMBAT_PHYSICALDAMAGE, 0, 0, 3)
	boss.health = 995300
	L.onHealthChange(boss, stranger, -100, COMBAT_PHYSICALDAMAGE, 0, 0, 3)
	boss.health = 995200
	L.onHealthChange(boss, person, -50, COMBAT_PHYSICALDAMAGE, 0, 0, 3)
	L.onHealthChange(boss, tester, 4000, COMBAT_HEALING, 0, 0, 3)
	local led = H.ledgerRow(TesterHelper.bossLedger)
	check(led.seen == 4850 and led.hits == 7 and led.own == 3800 and led.none == 700 and led.reflect == 200 and led.other == 150, "the ledger: every hit by its kind, healing not counted")
	eq(led.lost, 4800, "the ledger: the fall of the health read between the hits (the last hit is not applied yet)")
	local row = H.dealtRow(TesterHelper.dealtLate, tester.id)
	check(row.boss == 3800 and row.bossHits == 3 and row.summon == 2000 and row.dot == 300, "late tally: the tester's hits, its summon's and its dot apart")
	check(H.dealtRow(TesterHelper.dealtLate, person.id).boss == 0, "late tally: a player that is no tester has no row")
	-- O700: the final damage by origin and by damage type (the report says where the boss's health went)
	check(HELPER_VERSION >= 41, "the helper is version 41 or later (O700: the final damage by origin and by type)")
	TesterHelper.dealtLate = {}
	local spellWas = rawget(_G, "ORIGIN_SPELL")
	rawset(_G, "ORIGIN_SPELL", 3)
	boss.health = 900000
	L.onHealthChange(boss, tester, -600, COMBAT_FIREDAMAGE, -400, COMBAT_PHYSICALDAMAGE, 3)
	boss.health = 899000
	L.onHealthChange(boss, tester, -300, COMBAT_FIREDAMAGE, 0, 0, COND)
	local sr = H.dealtRow(TesterHelper.dealtLate, tester.id)
	check(sr.src and sr.src.spell == 1000 and sr.src.dot == 300 and sr.elem and sr.elem.fire == 900 and sr.elem.physical == 400,
		"late tally: the damage by origin (spell, dot) and by type (fire, physical)")
	sr.src.spell = 0
	eq(H.dealtRow(TesterHelper.dealtLate, tester.id).src.spell, 1000, "late tally: the split of a row is a copy")
	-- O706: the hits of each origin beside the damage of each (the report prints the mean hit)
	check(HELPER_VERSION >= 42, "the helper is version 42 or later (O706: the hits by origin)")
	check(sr.srcN and sr.srcN.spell == 1 and sr.srcN.dot == 1, "late tally: one hit counted for each origin")
	sr.srcN.spell = 9
	eq(H.dealtRow(TesterHelper.dealtLate, tester.id).srcN.spell, 1, "late tally: the hit counts of a row are a copy")
	rawset(_G, "ORIGIN_SPELL", spellWas)
	-- a hit that does not change the damage
	local a, b = L.onHealthChange(boss, tester, -10, COMBAT_PHYSICALDAMAGE, 0, 0, 3)
	check(a == -10 and b == COMBAT_PHYSICALDAMAGE, "the late event returns the hit as it came")
	-- an event that breaks does not break the chain
	local broken = {getHealth = function() error("gone") end, getId = function() return 5 end}
	local a2 = L.onHealthChange(broken, tester, -10, COMBAT_PHYSICALDAMAGE, 0, 0, 3)
	eq(a2, -10, "the late event never throws into the engine")
	-- the early event carries the kinds too
	TesterHelper.dealt = nil
	events.TesterHelperDealt.onHealthChange(boss, summon, -400, COMBAT_PHYSICALDAMAGE, 0, 0, 3)
	events.TesterHelperDealt.onHealthChange(boss, tester, -100, COMBAT_FIREDAMAGE, 0, 0, COND)
	local er = H.dealtRow(TesterHelper.dealt, tester.id)
	check(er.boss == 500 and er.summon == 400 and er.dot == 100, "early tally: a summon's and a dot's part")
	rawset(_G, "ORIGIN_CONDITION", nil)
	TesterHelper.dealt, TesterHelper.dealtLate, TesterHelper.bossLedger = nil, nil, nil
	ChaosPinnacle = realPN
	byId[boss.id], byId[summon.id], byId[stranger.id], byId[person.id] = nil, nil, nil, nil
end
do
	-- the pure parts
	local k = H.hitKind
	eq(k(nil), "none", "hitKind: no table is no attacker")
	eq(k({attacker = false}), "none", "hitKind: no attacker")
	eq(k({attacker = true, self = true, tester = true}), "reflect", "hitKind: the boss hit itself")
	eq(k({attacker = true, tester = false}), "other", "hitKind: an attacker that is no tester")
	eq(k({attacker = true, tester = true, summon = true, dot = true}), "summon", "hitKind: a summon's dot is the summon's")
	eq(k({attacker = true, tester = true, dot = true}), "dot", "hitKind: a tester's dot")
	eq(k({attacker = true, tester = true}), "player", "hitKind: a tester's hit")
	local L = H.ledgerNew(1)
	check(H.ledgerSample(L, 1000) and L.lost == 0 and L.hp == 1000, "ledger: the first look sets the health")
	H.ledgerSample(L, 700)
	H.ledgerSample(L, 800)
	check(L.lost == 300 and L.healed == 100 and L.hp == 800, "ledger: a fall and a rise apart")
	eq(H.ledgerHit(L, 800, 250, "player"), 250, "ledger: a hit lands whole")
	eq(L.seen, 250, "ledger: seen")
	eq(H.ledgerHit(L, 500, 900, "summon"), 500, "ledger: a lethal hit lands the health that was left")
	check(L.lost == 300 + 300 + 500 and L.hp == 0 and L.own == 750, "ledger: the lethal hit counts its fall (the boss is gone, no look follows)")
	eq(H.ledgerHit(L, 10, 0, "player"), 0, "ledger: no damage, no hit")
	eq(H.ledgerHit(nil, 10, 5, "player"), 0, "ledger: no ledger, no hit")
	check(not H.ledgerSample(L, nil) and not H.ledgerSample(nil, 5) and not H.ledgerSample(L, 0 / 0), "ledger: nothing to read")
	-- the fall and the hits agree when every hit is seen: 1000 -> 0 in three hits
	local M = H.ledgerNew(2)
	H.ledgerHit(M, 1000, 300, "player")
	H.ledgerHit(M, 700, 300, "dot")
	H.ledgerHit(M, 400, 500, "summon")
	check(M.lost == 1000 and M.seen == 1000 and M.own == 1000, "ledger: lost and seen agree when no hit is missed")
	-- a fall with no event shows as lost minus seen
	local N = H.ledgerNew(3)
	H.ledgerSample(N, 1000)
	H.ledgerHit(N, 1000, 100, "player")
	H.ledgerSample(N, 700)
	check(N.lost == 300 and N.seen == 100, "ledger: a fall no event saw is lost minus seen")
	local z = H.ledgerRow(nil)
	eq(z, nil, "ledgerRow: none for no ledger")
	local r = H.ledgerRow({lost = 5.9, healed = 0, seen = 4, hits = 2, own = 4})
	check(r.lost == 5 and r.none == 0 and r.reflect == 0 and r.other == 0, "ledgerRow: whole numbers, zeros for what is not there")
end
do
	local t = {}
	check(H.dealtAdd(t, 7, true, 100.9) and t[7].boss == 100 and t[7].bossHits == 1, "dealtAdd: a hit on the boss")
	check(not H.dealtAdd(t, 7, true, 0) and not H.dealtAdd(t, 7, true, -5) and not H.dealtAdd(t, nil, true, 5) and not H.dealtAdd(nil, 7, true, 5), "dealtAdd: nothing for no damage, no id, no table")
	H.dealtAdd(t, 7, false, 40)
	local r = H.dealtRow(t, 7)
	check(r.boss == 100 and r.other == 40 and r.otherHits == 1, "dealtRow: the row of one tester")
	r.boss = 0
	eq(t[7].boss, 100, "dealtRow: a copy")
	local z = H.dealtRow(t, 8)
	check(z.boss == 0 and z.bossHits == 0 and z.other == 0 and z.otherHits == 0, "dealtRow: none dealt is a row of zeros")
	-- O700: origin and damage type parts
	local o = {spell = 3, melee = 1, ranged = 2, cond = 7, none = 0}
	eq(H.originName(3, o), "spell", "originName: a spell")
	eq(H.originName(1, o), "melee", "originName: a melee auto attack")
	eq(H.originName(2, o), "ranged", "originName: a ranged auto attack")
	eq(H.originName(7, o), "dot", "originName: a condition is a dot")
	eq(H.originName(0, o), "none", "originName: no origin")
	eq(H.originName(nil, o), "none", "originName: nil is none")
	eq(H.originName(9, o), "other", "originName: any other value")
	eq(H.originName(3, nil), "other", "originName: no table, nothing matches")
	local pp = H.damageParts(-600, 2, -400, 1, {[1] = "physical", [2] = "fire"})
	check(pp.fire == 600 and pp.physical == 400, "damageParts: both slots by name, positive")
	check(next(H.damageParts(500, 128, 0, 0, {[1] = "physical"})) == nil, "damageParts: healing and unknown types count nothing")
	local t2 = {}
	H.dealtAdd(t2, 9, true, 1000, "player", "spell", {fire = 600, physical = 400})
	H.dealtAdd(t2, 9, true, 300, "dot", "dot", {fire = 300})
	H.dealtAdd(t2, 9, false, 50, "player", "spell", {fire = 50})
	check(t2[9].src.spell == 1000 and t2[9].src.dot == 300 and t2[9].elem.fire == 900 and t2[9].elem.physical == 400, "dealtAdd: origin and type parts of the boss damage")
	check(t2[9].other == 50 and t2[9].src.spell == 1000, "dealtAdd: a hit on another monster is in neither split")
	check(H.withinReach({x = 10, y = 10, z = 7}, {x = 17, y = 3, z = 7}, 7) and not H.withinReach({x = 10, y = 10, z = 7}, {x = 18, y = 10, z = 7}, 7)
		and not H.withinReach({x = 10, y = 10, z = 7}, {x = 10, y = 10, z = 8}, 7) and not H.withinReach(nil, {x = 1, y = 1, z = 7}, 7), "withinReach: a square of the floor")
end

-- once a minute the console gets the count of testers in game
before = #printed
for _ = 1, 120 do
	lastStep().fn()
end
local onlineLines = 0
for i = before + 1, #printed do
	if printed[i] == "[tester-helper] testers online: 1" then onlineLines = onlineLines + 1 end
end
eq(onlineLines, 1, "the console line of the testers online")

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
check(printed[#printed]:find('[tester-event] {', 1, true) ~= nil and printed[#printed]:find('"killer":"wolf"', 1, true) ~= nil,
	"the death event")
check(printed[#printed]:find('"hits":1', 1, true) ~= nil and printed[#printed]:find('"biggestBy":"wolf"', 1, true) ~= nil,
	"with the hits of the last seconds (the 130M one)")
-- the engine's negative damage reaches the death record (the bug of the first live death lines: hits 2, damage 0)
T.hits[tester.id] = nil
events.TesterHelperHealth.onHealthChange(tester, wolf, -30, COMBAT_PHYSICALDAMAGE, -20, COMBAT_FIREDAMAGE, 0)
events.TesterHelperHealth.onHealthChange(tester, wolf, -70, COMBAT_PHYSICALDAMAGE, 0, 0, 0)
before = #printed
events.TesterHelperDeath.onDeath(tester, nil, wolf, wolf)
local line = printed[before + 1] or ""
check(line:find('"hits":2', 1, true) and line:find('"damage":120', 1, true) and line:find('"biggest":70', 1, true)
	and line:find('"biggestBy":"wolf"', 1, true), "death line of negative engine damage: " .. line)
check(T.hits[tester.id] == nil, "and the tester's hits are forgotten")

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


-- ------------------------------------------------------------------ O584: keeping the drops (`!tester bag` reports, never wipes)
do
	T.present = function() return true end
	local H = ChaosTesterHelperCore
	eq(H.parseBag(nil), "report", "bag: a plain bag reports")
	eq(H.parseBag("wipe"), "wipe", "bag wipe: the last resort")
	check(H.parseBag("everything") == nil, "bag: another word is refused")
	eq(H.parseShop("loot buyer"), "Loot Buyer", "shop: a trader by name, any case")
	check(H.parseShop("Odrenna") == nil, "shop: not a trader of the list")
	local ctx = {want = {[7618] = 100}, currency = {[2160] = true}}
	eq(H.itemKind({id = 7618}, ctx), "supply", "kind: the potion is a supply")
	eq(H.itemKind({id = 2160}, ctx), "currency", "kind: coins")
	eq(H.itemKind({id = 5, container = true}, ctx), "container", "kind: a bag")
	eq(H.itemKind({id = 6, price = 40, blocked = true}, ctx), "locked", "kind: the Loot Buyer refuses it")
	eq(H.itemKind({id = 7, price = 40}, ctx), "sell", "kind: the Loot Buyer buys it")
	eq(H.itemKind({id = 8, price = 0}, ctx), "junk", "kind: nothing buys it")
	local rows = {{id = 10, slot = 1, score = 30, kind = "sell"}, {id = 11, slot = 1, score = 90, kind = "sell"},
		{id = 12, slot = 4, score = 5, kind = "sell"}, {id = 7618, slot = nil, kind = "supply"}}
	eq(H.betterPiece({[1] = 50, [4] = 5}, rows), 2, "better: the helmet that beats the worn one by most")
	check(H.betterPiece({[1] = 95, [4] = 9}, rows) == nil, "better: nothing beats what is worn")
	check(H.betterPiece({[1] = 50}, rows, {[11] = true}) == nil or H.betterPiece({[1] = 50}, rows, {[11] = true}) ~= 2,
		"better: a refused piece is not tried again")
	eq(H.betterPiece({[1] = 89, [4] = 5}, rows), 2, "better: a gain of the margin counts")
	-- junk is dropped only from a jammed bag, the weakest first, never a supply, a locked item or a sale
	local bag = {}
	for i = 1, 18 do
		bag[i] = {i = i - 1, id = 100 + i, count = 1, kind = i <= 4 and "sell" or i <= 6 and "locked" or "junk", score = i}
	end
	eq(#H.junkPlan(bag, 17, 20), 0, "junk: a bag under BAG_JAM drops nothing")
	local drop = H.junkPlan(bag, 19, 20)
	check(#drop >= 1 and #drop <= 6, "junk: a jammed bag drops a few")
	for _, idx in ipairs(drop) do
		eq(bag[idx].kind, "junk", "junk: only junk is dropped")
	end
	eq(drop[1], 7, "junk: the weakest first")
	local rep = H.bagReport(bag, {}, 20, nil)
	eq(rep.used, 18, "report: the slots in use")
	eq(rep.sell, 4, "report: the rows the Loot Buyer buys")
	check(#rep.rows <= H.REPORT_MAX, "report: the answer stays small")

	-- the command on a mock backpack
	local saved = ItemType
	local types = {[3001] = {slot = 1, armor = 8, def = 0, atk = 0, price = 120}, [3002] = {slot = 1, armor = 3, def = 0, atk = 0, price = 40},
		[3003] = {slot = 0, armor = 0, def = 0, atk = 0, price = 0}, [7618] = {slot = 0, armor = 0, def = 0, atk = 0, price = 0}}
	function ItemType(id)
		local t = types[id] or {slot = 0, armor = 0, def = 0, atk = 0}
		return {getClientId = function() return id + 10000 end, getName = function() return "item " .. id end,
			isStackable = function() return false end, getSlotPosition = function() return t.slot end,
			getArmor = function() return t.armor end, getDefense = function() return t.def end, getAttack = function() return t.atk end}
	end
	ChaosItemPrices = {basePrice = function(id) return (types[id] or {}).price or 0 end, saleBlock = function() return nil end}
	local function it(id, n)
		return {getId = function() return id end, getCount = function() return n or 1 end, isContainer = function() return false end}
	end
	local items = {[0] = it(7618, 90), [1] = it(3002), [2] = it(3001), [3] = it(3003)}
	local kb = creature(268435480, "Tester Kbg", {store = {[ST] = 1}})
	local wornHelmet = it(3002)
	kb.slots = {[CONST_SLOT_HEAD] = wornHelmet, [CONST_SLOT_BACKPACK] = {
		getSize = function() return 4 end, getItem = function(_, i) return items[i] end, getCapacity = function() return 20 end,
		getItems = function() return {items[0], items[1], items[2], items[3]} end, getId = function() return 1988 end,
		addItem = function() end}}
	function kb:getItemCount(id) return id == 7618 and 90 or 0 end
	function kb:getMoney() return 321 end
	check(talks["!tester"].onSay(kb, "!tester", "bag #4") == false, "bag report: consumed")
	local line = kb.log.msgs[#kb.log.msgs]
	check(line:find("[tester-helper] bag ", 1, true) ~= nil, "bag report: the answer line")
	check(line:find('"seq":4', 1, true) ~= nil, "bag report: numbered")
	check(line:find('"used":4', 1, true) ~= nil and line:find('"size":20', 1, true) ~= nil, "bag report: slots used of the size")
	check(line:find('"better":2', 1, true) ~= nil, "bag report: the helmet of armour 8 beats the worn one of armour 3 (container index 2)")
	check(line:find('"gold":321', 1, true) ~= nil and line:find('"bagClientId":11988', 1, true) ~= nil, "bag report: the gold and the backpack id")
	check(line:find('"k":"junk"', 1, true) ~= nil and line:find('"k":"sell"', 1, true) ~= nil and line:find('"k":"supply"', 1, true) ~= nil,
		"bag report: the kinds of the rows")
	eq(#kb.log.items, 0, "bag report: nothing added when the potions are enough")
	eq(kb.removedItems, nil, "bag report: nothing removed")
	-- `shop Loot Buyer` goes to that trader and names it
	local lb = {getName = function() return "Loot Buyer" end, isNpc = function() return true end,
		getPosition = function() return {x = 70, y = 70, z = 7} end}
	npcs["Loot Buyer"] = lb
	check(talks["!tester"].onSay(kb, "!tester", "shop Loot Buyer #5") == false, "shop Loot Buyer: consumed")
	check(kb.log.msgs[#kb.log.msgs]:find('"npc":"Loot Buyer"', 1, true) ~= nil or kb.log.msgs[#kb.log.msgs]:find("no free tile next to Loot Buyer", 1, true) ~= nil,
		"shop Loot Buyer: it names the Loot Buyer or says why not")
	npcs["Loot Buyer"] = nil
	ItemType = saved
	ChaosItemPrices = nil
end


-- ------------------------------------------------------------------ O584: `!tester give` (items for the crafting checks)
do
	T.present = function() return true end
	local H = ChaosTesterHelperCore
	local g = H.parseGive("orb alchemy 3")
	check(g and g.what == "orb" and g.key == "alchemy" and g.n == 3, "give: an orb with its key and number")
	eq(H.parseGive("orb whetstone").n, 1, "give: one orb by default")
	eq(H.parseGive("orb chaos 99").n, H.GIVE_MAX, "give: at most GIVE_MAX")
	check(H.parseGive("orb") == nil, "give: an orb needs its key")
	check(H.parseGive("sword") == nil and H.parseGive("") == nil and H.parseGive("gem x") == nil, "give: only the listed things")
	eq(H.parseGive("gem 2").n, 2, "give: a gem number")
	eq(H.parseCommand("give item #3"), "give", "give is a command")

	local made, putIn = {}, {}
	ChaosCrafting = {orbByKey = {alchemy = {id = 24691}}, createItem = function(id, rarity, level)
		made[#made + 1] = {id, rarity, level}
		return {getId = function() return id end, getCount = function() return 1 end, setCustomAttribute = function(self, k, v) self.attr = v end,
			getCustomAttribute = function(self) return self.attr end}
	end}
	ChaosGems = {gemId = function(t, tier) return 32000 + t * 5 + tier end}
	ChaosTestKit = {kits = {sword = {slots = {[CONST_SLOT_LEFT] = 2400}}}, kindFor = function() return "sword" end}
	local stored = {}
	local bag = {getSize = function() return #stored end, getItem = function(_, i) return stored[i + 1] end, getId = function() return 1988 end}
	Game.createItem = function(id, n)
		return {getId = function() return id end, getCount = function() return n end, setCustomAttribute = function(self, k, v) self.attr = v end,
			getCustomAttribute = function(self) return self.attr end}
	end
	local gb = creature(268435490, "Tester Gvq", {store = {[ST] = 1}})
	gb.slots = {[CONST_SLOT_BACKPACK] = bag}
	function gb:addItemEx(item) stored[#stored + 1] = item; return RETURNVALUE_NOERROR or 0 end
	function gb:getLevel() return 700 end
	RETURNVALUE_NOERROR = 0
	check(talks["!tester"].onSay(gb, "!tester", "give item #2") == false, "give item: consumed")
	local line = gb.log.msgs[#gb.log.msgs]
	check(line:find('"what":"item"', 1, true) ~= nil and line:find('"path":"0"', 1, true) ~= nil and line:find('"seq":2', 1, true) ~= nil,
		"give item: the slot of the backpack and the number: " .. tostring(line))
	eq(made[1][1] .. "," .. made[1][2] .. "," .. made[1][3], "2400,0,150", "give item: the plain kit weapon at an item level of at most 150")
	check(talks["!tester"].onSay(gb, "!tester", "give orb alchemy 2") == false, "give orb: consumed")
	line = gb.log.msgs[#gb.log.msgs]
	check(line:find('"id":24691', 1, true) ~= nil and line:find('"count":2', 1, true) ~= nil and line:find('"index":1', 1, true) ~= nil, "give orb: the orb stack: " .. tostring(line))
	talks["!tester"].onSay(gb, "!tester", "give orb nothing")
	check(gb.log.msgs[#gb.log.msgs]:find("no orb nothing", 1, true) ~= nil, "give orb: an unknown orb says so")
	talks["!tester"].onSay(gb, "!tester", "give gem")
	check(gb.log.msgs[#gb.log.msgs]:find('"id":32006', 1, true) ~= nil, "give gem: the smallest gem")
	talks["!tester"].onSay(gb, "!tester", "give nonsense")
	check(gb.log.msgs[#gb.log.msgs]:find("give takes", 1, true) ~= nil, "give: a wrong word is told")
	local ana2 = creature(268435491, "Ana Player", {})
	ana2.slots = {[CONST_SLOT_BACKPACK] = bag}
	check(talks["!tester"].onSay(ana2, "!tester", "give item") == true, "give: left to the game for a player")
	ChaosCrafting, ChaosGems, ChaosTestKit = nil, nil, nil
end

-- ------------------------------------------------------------------ the bag clean-up (`!tester bag`)
do
	T.present = function() return true end
	local H = ChaosTesterHelperCore
	local rm, add = H.bagPlan({{id = 7618, count = 90}, {id = 2160, count = 3}, {id = 1987, count = 1}, {id = 7620, count = 100}},
		{[7618] = 100, [7620] = 100}, {[7618] = 90, [7620] = 100})
	eq(#rm, 2, "bagPlan: the two loot slots go")
	eq(rm[1] .. "," .. rm[2], "2,3", "bagPlan: by index")
	eq(#add, 0, "bagPlan: 90 of 100 potions is enough")
	rm, add = H.bagPlan({}, {[7618] = 100, [7620] = 100}, {[7618] = 49})
	eq(#add, 2, "bagPlan: under half is topped up (and a missing kind)")
	eq(add[1].id .. ":" .. add[1].count .. " " .. add[2].id .. ":" .. add[2].count, "7618:51 7620:100", "bagPlan: up to the number, by id")
	check(H.parseCommand("bag") == "bag", "bag is a command")

	local bt = creature(268435470, "Tester Abq", {store = {[ST] = 1}})
	local removed, added = {}, {}
	local function slot(id, n)
		return {getId = function() return id end, getCount = function() return n end, remove = function() removed[#removed + 1] = id end}
	end
	bt.slots = {[CONST_SLOT_BACKPACK] = {getItems = function() return {slot(2160, 5), slot(7618, 30), slot(1987, 1)} end,
		addItem = function(_, id, n) added[#added + 1] = id .. ":" .. n end}}
	function bt:getItemCount(id) return id == 7618 and 30 or 0 end
	check(talks["!tester"].onSay(bt, "!tester", "bag wipe") == false, "bag wipe: consumed")
	eq(table.concat(removed, ","), "2160,1987", "bag wipe: the loot is removed, the potions stay")
	eq(table.concat(added, " "), "7618:70 7620:100", "bag: the potions topped up")
	check(bt.log.msgs[#bt.log.msgs]:find('bag {"topped":2,"wiped":2}', 1, true) ~= nil or bt.log.msgs[#bt.log.msgs]:find('"wiped":2', 1, true) ~= nil, "bag wipe: the answer line")
	for _, p in ipairs({ana, fake, marked}) do
		removed = {}
		check(talks["!tester"].onSay(p, "!tester", "bag") == true, p.name .. ": !tester bag is left to the game")
		eq(#removed, 0, p.name .. ": nothing removed from a player")
	end
	-- a teleport the game refuses leaves the tester where it is: the answer says so
	local lt = creature(268435471, "Tester Abr", {store = {[ST] = 1}})
	function lt:teleportTo(p) end
	npcs["Material Broker"] = {getName = function() return "Material Broker" end, isNpc = function() return true end,
		getPosition = function() return {x = 70, y = 70, z = 7} end}
	function Tile() return {getGround = function() return true end, hasFlag = function() return false end,
		getTopCreature = function() return nil end} end
	talks["!tester"].onSay(lt, "!tester", "shop")
	check(lt.log.msgs[#lt.log.msgs]:find("shop {\"err\":\"the teleport next to the NPC was refused", 1, true) ~= nil,
		"shop: a refused teleport is an error, not a window the bot cannot reach")
	-- the depot twin (O592): a locker stands near the temple, the teleport next to it is refused, the bot stays and the answer says so
	local dt = creature(268435472, "Tester Abs", {store = {[ST] = 1}})
	function dt:teleportTo(p) end
	local lockerAt = {x = 53, y = 50, z = 7}
	function Tile(p)
		local t = {getGround = function() return true end, hasFlag = function() return false end,
			getTopCreature = function() return nil end, getPosition = function() return p end,
			getThingIndex = function() return 1 end}
		t.getItemById = function(_, id)
			if id == 2589 and p.x == lockerAt.x and p.y == lockerAt.y and p.z == lockerAt.z then
				return {getId = function() return id end}
			end
			return nil
		end
		return t
	end
	local dx0 = dt.pos.x
	talks["!tester"].onSay(dt, "!tester", "depot")
	check(dt.log.msgs[#dt.log.msgs]:find("depot {\"err\":\"the teleport next to the locker was refused", 1, true) ~= nil,
		"depot: a refused teleport is an error, not a locker the bot cannot reach")
	eq(dt.pos.x, dx0, "depot: the refused bot stayed where it was")
end

-- ------------------------------------------------------------------ O86: summons, party, cursed chest probes
do
	-- the pure rules
	local owner = {id = 1, isPlayer = true, partyLeaderId = 9}
	eq(H.targetKind(owner, nil), "none", "no target")
	eq(H.targetKind(owner, {id = 1, isPlayer = true}), "owner", "the owner")
	eq(H.targetKind(owner, {id = 2, isPlayer = true, partyLeaderId = 9}), "ally", "a party member")
	eq(H.targetKind(owner, {id = 3, isPlayer = true}), "player", "a stranger")
	eq(H.targetKind(owner, {id = 4, ownerId = 1}), "summon", "own summon")
	eq(H.targetKind(owner, {id = 5, ownerId = 2, partyLeaderId = 9}), "summon", "a party member's summon")
	eq(H.targetKind(owner, {id = 6}), "monster", "a wild monster")
	local seen = {}
	local snap = {who = "Tester Abc", ownerTarget = "summon", summons = {{name = "wolf", id = 4, target = "owner"},
		{name = "wolf", id = 5, target = "monster"}, {name = "wolf", id = 6, target = "ally"}}}
	local a = H.summonAnomalies(snap, 100, seen)
	eq(#a, 3, "three rules fire once")
	local rules = {}
	for _, x in ipairs(a) do rules[x.rule] = true end
	check(rules.summon_targets_owner and rules.summon_targets_ally and rules.owner_targets_summon, "the three rule names")
	eq(#H.summonAnomalies(snap, 110, seen), 0, "throttled for 30 s")
	eq(#H.summonAnomalies(snap, 131, seen), 3, "and again after")
	eq(#H.summonAnomalies({who = "x", ownerTarget = "monster", summons = {{target = "monster"}, {target = "none"}}}, 1, {}), 0, "a healthy pack: nothing")
	check(H.COMMANDS.summons and H.COMMANDS.party and H.COMMANDS.chest, "commands registered")

	-- the engine file: a tester with a wolf that targets it, and a party
	local t2 = creature(268435480, "Tester Abw", {store = {[ST] = 1}})
	local mate = creature(268435481, "Tester Abx", {store = {[ST] = 1}})
	local w1 = creature(1073741830, "wolf", {player = false, monster = true})
	w1.master = t2
	local party = {getLeader = function() return t2 end, getMembers = function() return {mate} end}
	t2.getParty = function() return party end
	mate.getParty = function() return party end
	w1.getParty = function() return nil end
	t2.getSummons = function() return {w1} end
	local stranger = creature(268435482, "Tester Aby", {store = {[ST] = 1}})
	stranger.getParty = function() return nil end
	w1.getTargetList = function() return {t2, mate, wolf, stranger} end -- a player outside the party: no ally
	w1.target = t2
	function Game.getPlayers() return {t2, mate} end
	talks["!tester"].onSay(t2, "!tester", "summons")
	local line = t2.log.msgs[#t2.log.msgs]
	check(line:find("summons ", 1, true) ~= nil and line:find('"target":"owner"', 1, true) ~= nil, "summons: the wolf targets its owner")
	check(line:find('"listedAllies":2', 1, true) ~= nil, "summons: two allies in the engine target list")
	talks["!tester"].onSay(t2, "!tester", "party")
	check(t2.log.msgs[#t2.log.msgs]:find('"size":2', 1, true) ~= nil, "party: size 2")
	-- leave: out through Party:removeMember (the leave packet is refused in a fight)
	local removed
	party.removeMember = function(_, who) removed = who; mate.getParty = function() return nil end end
	talks["!tester"].onSay(mate, "!tester", "party leave")
	check(removed == mate and mate.log.msgs[#mate.log.msgs]:find('"size":0', 1, true) ~= nil, "party leave: removed, size 0")
	mate.getParty = function() return party end
	party.removeMember = nil
	-- the loop reports the anomaly of a tester with a wolf on the console
	T.ids[t2.id] = true
	spectators = {}
	local before = #printed
	for _ = 1, 8 do lastStep().fn() end
	local found
	for i = before + 1, #printed do
		if printed[i]:find("[tester-anomaly]", 1, true) and printed[i]:find("summon_targets_owner", 1, true) then found = true end
	end
	check(found, "the loop prints [tester-anomaly] summon_targets_owner")
	-- a non-tester with summons is never probed
	talks["!tester"].onSay(ana, "!tester", "summons")
	eq(#ana.log.msgs, 0, "a real player's summons are not probed")
	talks["!tester"].onSay(t2, "!tester", "chest")
	check(t2.log.msgs[#t2.log.msgs]:find('chest {"err":"no cursed chest system"}', 1, true) ~= nil, "chest: no system, an error answer")
	-- a standing chest names its tile: the client check looks at that tile only
	local realGuid = t2.getGuid
	t2.getGuid = function() return 78 end
	ChaosCursedChest = {spawnChest = function() end, tagged = {},
		chests = {k = {key = "k", ownerId = 78, state = "idle", itemId = 1, pos = {x = 101, y = 202, z = 7}}}}
	talks["!tester"].onSay(t2, "!tester", "chest state")
	local line = t2.log.msgs[#t2.log.msgs]
	check(line:find('"state":"idle"', 1, true) and line:find('"cx":101', 1, true) and line:find('"cy":202', 1, true) and line:find('"cz":7', 1, true),
		"chest: a standing chest answers its tile")
	ChaosCursedChest.chests = {}
	talks["!tester"].onSay(t2, "!tester", "chest state")
	line = t2.log.msgs[#t2.log.msgs]
	check(line:find('"state":"none"', 1, true) and not line:find('"cx"', 1, true), "chest: no chest, no tile")
	ChaosCursedChest, t2.getGuid = nil, realGuid
end

-- ------------------------------------------------------------------ O671: the rift's greater, seal and fail words on a mocked ChaosRift
do
	local savedRF, savedCfg, savedCore, savedIT = ChaosRift, ChaosRiftConfig, ChaosRiftCore, ItemType
	local held, sealed, failed, keyBack = false, 0, 0, nil
	ChaosRiftConfig = {maxTier = 15, key = {itemId = 10155}}
	ChaosRiftCore = {tierInfo = function() return {minLevel = 100} end}
	ChaosRift = {
		probe = function(p) return {inside = false, level = 1500, pz = p.inPz ~= false, held = held, keyShown = held and 17 or nil} end,
		giveKey = function() return nil end,
		testerGreaterKey = function(p, g) held = not keyBack return 15 + g, keyBack end,
		testerSeal = function(p) sealed = sealed + 1 return true end,
		testerFail = function(p) failed = failed + 1 return true end,
	}
	function ItemType(id) return {getClientId = function() return 4000 + id end} end
	local gt = creature(268435493, "Tester Grr", {store = {[ST] = 1}})
	gt.getItemById = function() return held and {remove = function() end} or nil end
	local function sayR(cmd)
		talks["!tester"].onSay(gt, "!tester", "rift " .. cmd)
		return gt.log.msgs[#gt.log.msgs]
	end
	local line = sayR("greater 3")
	check(line:find('"tier":18', 1, true) and line:find('"greater":3', 1, true) and line:find('"held":true', 1, true), "rift greater 3: the key of tier 18 is in the backpack: " .. tostring(line))
	check(line:find('"keyClientId":14155', 1, true), "rift greater: the client id of the key to use")
	check(line:find('"keyShown":17', 1, true), "rift greater: the answer carries the key shown now")
	held, keyBack = false, true
	line = sayR("greater 2")
	check(line:find('"bagFull":true', 1, true) and line:find('"held":false', 1, true), "rift greater with a full backpack: the key went to the inbox, and the answer says so: " .. tostring(line))
	gt.inPz = false
	line = sayR("greater 2")
	check(line:find("not in a protection zone", 1, true), "rift greater outside a protection zone: refused")
	gt.inPz = true
	eq(sealed, 0, "no seal asked yet")
	line = sayR("seal")
	check(line:find('"sealing":true', 1, true) and sealed == 1, "rift seal: started: " .. tostring(line))
	line = sayR("fail")
	check(line:find('"failed":true', 1, true) and failed == 1, "rift fail: done: " .. tostring(line))
	ChaosRift.testerSeal = function() return nil, "not inside a running rift" end
	check(sayR("seal"):find("not inside a running rift", 1, true), "rift seal: the engine's reason comes back")
	ChaosRift.testerGreaterKey = nil
	check(sayR("greater 1"):find("no Greater Rift", 1, true), "rift greater: an engine with no such function says so")
	ChaosRift, ChaosRiftConfig, ChaosRiftCore, ItemType = savedRF, savedCfg, savedCore, savedIT
end

-- ------------------------------------------------------------------ the line spell quests (!tester spellquest)
do
	local sq = H.parseSpellQuest
	eq(sq("").sub, "state", "spellquest: no argument is the state")
	eq(sq("set 1 1 0 0").quest, 1, "set: quest"); eq(sq("set 1 1 0 0").kills, 0, "set: kills"); eq(sq("set 2 3").fragments, nil, "set: no fragments")
	eq(sq("kill").n, 1, "kill: one by default"); eq(sq("kill 45").n, 45, "kill: a number"); eq(sq("kill boss").boss, true, "kill boss")
	eq(sq("kill 3 boss").n, 3, "kill 3 boss")
	check(select(2, sq("kill 999")) ~= nil, "kill: capped"); check(select(2, sq("set 0 1")) ~= nil, "set: quest 0")
	check(select(2, sq("set 1 4")) ~= nil, "set: step 4"); check(select(2, sq("set 1 1 x")) ~= nil, "set: kills not a number")
	check(select(2, sq("state now")) ~= nil, "state takes no argument"); check(select(2, sq("give")) ~= nil, "an unknown command")
	check(H.COMMANDS.spellquest, "spellquest is a registered command")

	-- the engine file of the quests (a mocked engine) and a tester of the Warrior line at level 600
	local savedTrials = ChaosTrials
	ChaosTrials = {runs = {}, enter = function(player) ChaosTrials.runs[player:getId()] = {} return true end,
		leave = function(player) local was = ChaosTrials.runs[player:getId()] ~= nil; ChaosTrials.runs[player:getId()] = nil; return was end}
	function GlobalEvent() return {register = function() end} end
	Game.createNpc = function() return nil end
	dofile("data/scripts/chaos/spellquest.lua")
	local qt = creature(268435490, "Tester Aqb", {store = {[ST] = 1}})
	qt.level, qt.learned = 600, {}
	function qt:getLevel() return self.level end
	function qt:getParty() return nil end
	function qt:hasLearnedSpell(name) return self.learned[name] == true end
	function qt:learnSpell(name) self.learned[name] = true return true end
	function qt:forgetSpell(name) self.learned[name] = nil return true end
	local odrenna = {getName = function() return "Archivist Odrenna" end, isNpc = function() return true end}
	local near
	Game.getSpectators = function() return near and {odrenna} or {} end
	local function say(cmd)
		talks["!tester"].onSay(qt, "!tester", "spellquest " .. cmd)
		local line = qt.log.msgs[#qt.log.msgs]
		return line:match("^%[tester%-helper%] spellquest (.*)$"), line
	end
	local function has(body, part, label) check(body and body:find(part, 1, true) ~= nil, label .. ": " .. tostring(body)) end
	local body = say("state")
	has(body, '"quest":1', "state: quest 1"); has(body, '"step":0', "state: not started"); has(body, '"learned":false', "state: spell unknown")
	has(body, '"spell":"Keepfall"', "state: the Warrior line's first spell")
	body = say("set 1 1 0 0")
	has(body, '"step":1', "set: on the hunt"); has(body, '"kills":0', "set: no kills")
	body = say("kill 3")
	has(body, '"counted":3', "kill: three count"); has(body, '"kills":3', "kill: the storage counts"); has(body, '"pity":3', "kill: the pity counts")
	body = say("kill 45")
	has(body, '"counted":45', "kill: 45 count"); has(body, '"kills":48', "kill: 48 in all")
	check(body:find('"fragments":0', 1, true) == nil, "kill: the pity gives a fragment within 41 counted kills: " .. tostring(body))
	has(body, '"rolled":', "kill: the fragments are listed")
	qt.level = 450
	body = say("kill 2")
	has(body, '"counted":0', "kill: a level under the quest counts nothing")
	qt.level = 600
	body = say("kill boss")
	has(body, '"weight":25', "kill boss: 25 kills")
	body = say("set 1 2")
	has(body, '"step":2', "set: the trial step"); has(body, '"kills":400', "set: the kills filled")
	near = false
	body = say("trial")
	has(body, '"entered":false', "trial: away from Odrenna the door is shut"); has(body, '"running":false', "trial: nothing runs")
	near = true
	body = say("trial")
	has(body, '"entered":true', "trial: at Odrenna the trial opens"); has(body, '"running":true', "trial: it runs")
	body = say("leave")
	has(body, '"left":true', "leave: the run ends"); has(body, '"running":false', "leave: nothing runs")
	local bank = qt:getBankBalance()
	body = say("complete")
	has(body, '"taught":"Keepfall"', "complete: Keepfall"); has(body, '"taughtKnown":true', "complete: the spell is learned")
	eq(qt:getBankBalance() - bank, 600 * 2000, "complete: 2000 gold per level to the bank")
	body = say("complete")
	has(body, '"err":"the quest is not on its trial step"', "complete: nothing to complete a second time")
	body = say("reset")
	has(body, '"step":0', "reset: back to the start"); check(not qt.learned.Keepfall, "reset: the spell is forgotten")
	body = say("bogus")
	has(body, '"err":"unknown spellquest command"', "an unknown sub command is an error")
	local nl = creature(268435491, "Tester Aqc", {store = {[ST] = 1}})
	function nl:getVocation() return {getId = function() return 0 end} end
	talks["!tester"].onSay(nl, "!tester", "spellquest state")
	check(nl.log.msgs[#nl.log.msgs]:find('"code":"noline"', 1, true) ~= nil, "no line: an error answer")
	local msgs = #ana.log.msgs
	check(talks["!tester"].onSay(ana, "!tester", "spellquest reset") == true, "a player's !tester spellquest is left to the game")
	eq(#ana.log.msgs, msgs, "a player is never answered")
	ChaosTrials = savedTrials
end

-- ------------------------------------------------------------------ O110: party XP, waystone runs, rift layouts, rewards
do
	local p, perr = H.parseWaystone("8 loot")
	check(p and p.tier == 8 and p.loot == true, "waystone: tier and loot")
	eq(H.parseWaystone("3").loot, false, "waystone: no loot by default")
	check(select(2, H.parseWaystone("0")) ~= nil and select(2, H.parseWaystone("16")) ~= nil and select(2, H.parseWaystone("x")) ~= nil
		and select(2, H.parseWaystone("3 gold")) ~= nil and select(2, H.parseWaystone(nil)) ~= nil, "waystone: bad arguments are refused")
	eq(H.parseRiftRun(nil), "layout", "riftrun: layout by default")
	eq(H.parseRiftRun("LOOT"), "loot", "riftrun: loot")
	check(select(2, H.parseRiftRun("open")) ~= nil, "riftrun: an unknown mode is refused")
	eq(H.riftTierFor(99, 15, function(t) return 100 + (t - 1) * 50 end), nil, "no tier under the first level")
	eq(H.riftTierFor(210, 15, function(t) return 100 + (t - 1) * 50 end), 3, "the highest tier the level opens")
	check(H.COMMANDS.waystone and H.COMMANDS.riftrun, "waystone and riftrun are registered commands")
	check(H.COMMANDS.unique and H.parseCommand("unique") == "unique", "unique is a registered command (O278)")
	check(H.COMMANDS.fists and H.parseCommand("fists") == "fists", "fists is a registered command (O360)")
	check(H.COMMANDS.blades and H.parseCommand("blades") == "blades", "blades is a registered command (O360)")

	CONDITION_INFIGHT, CONDITIONID_DEFAULT = 1, 0
	dofile("data/scripts/chaos/party_xp_core.lua")
	local function lastBody(pl, kind)
		local line = pl.log.msgs[#pl.log.msgs] or ""
		return line:match("^%[tester%-helper%] " .. kind .. " (.*)$"), line
	end
	local function has(body, part, label) check(body and body:find(part, 1, true) ~= nil, label .. ": " .. tostring(body)) end

	-- ---------------------------------------------------------------- party XP sharing
	local function mkPartyMember(id, name, level, line, pos, fighting)
		local m = creature(id, name, {store = {[ST] = 1}, pos = pos})
		m.getLevel = function() return level end
		m.getVocation = function() return {getBase = function() return {getId = function() return line end} end} end
		m.getCondition = function() return fighting and {} or nil end
		return m
	end
	local function mkParty(leader, members, active, enabled)
		local pt = {getLeader = function() return leader end, getMembers = function() return members end,
			isSharedExperienceActive = function() return active end, isSharedExperienceEnabled = function() return enabled end}
		-- the stock Party:onShareExperience (events/scripts/party.lua, class lines patched in by patch_base_classes.py)
		function pt:onShareExperience(exp)
			local ids = {}
			for _, who in ipairs({leader, members[1]}) do
				ids[who:getVocation():getBase():getId()] = true
			end
			local n = 0
			for _ in pairs(ids) do n = n + 1 end
			local mult = n > 1 and (1 + (n * (5 * (n - 1) + 10)) / 100) or 1.2
			return math.ceil(exp * mult / (#members + 1))
		end
		leader.getParty = function() return pt end
		for _, m in ipairs(members) do m.getParty = function() return pt end end
		return pt
	end
	local lead = mkPartyMember(268435600, "Tester Pxa", 100, 4, {x = 100, y = 100, z = 7}, true)
	local mate = mkPartyMember(268435601, "Tester Pxb", 90, 3, {x = 110, y = 100, z = 7}, true)
	mkParty(lead, {mate}, true, true)
	talks["!tester"].onSay(lead, "!tester", "party")
	local body = lastBody(lead, "party")
	has(body, '"shareActive":true', "party xp: the switch is reported")
	has(body, '"shareEnabled":true', "party xp: the engine's verdict is reported")
	has(body, '"shareOf1000":650', "party xp: 1000 experience pays ceil(1000 x 1.3 / 2)")
	has(body, '"lines":2', "party xp: two class lines")
	has(body, '"bonusPct":30', "party xp: +30 %")
	has(body, '"problems":[]', "party xp: everyone passes")
	has(body, '"minLevel":67', "party xp: two thirds of the highest level")
	-- a member far below two thirds of the highest level and one out of range are named with their rule
	local weak = mkPartyMember(268435602, "Tester Pxc", 30, 3, {x = 150, y = 100, z = 7}, false)
	mkParty(lead, {weak}, true, false)
	talks["!tester"].onSay(lead, "!tester", "party")
	body = lastBody(lead, "party")
	has(body, '"kind":"level"', "party xp: the level rule fails for the weak member")
	has(body, '"kind":"range"', "party xp: the range rule fails for the far member")
	has(body, '"kind":"idle"', "party xp: the fight rule fails for the idle member")
	has(body, '"shareEnabled":false', "party xp: not working")
	-- a party without the helper's probes still answers its size
	local plain = mkPartyMember(268435603, "Tester Pxd", 100, 4, {x = 1, y = 1, z = 7}, true)
	plain.getParty = function() return {getLeader = function() return plain end, getMembers = function() return {} end} end
	talks["!tester"].onSay(plain, "!tester", "party")
	has((lastBody(plain, "party")), '"size":1', "party xp: a party the probes cannot read still answers its size")

	-- ---------------------------------------------------------------- the mocked waystone and loot systems
	local saved = {Tile = Tile, Game = Game, WT = ChaosWaystoneTiers, WM = ChaosWaystoneMods, WTC = ChaosWaystoneTilesCore,
		CR = ChaosContentRewards, L = ChaosLoot, GS = ChaosGearSets, RF = ChaosRift, RFC = ChaosRiftConfig, RL = ChaosRiftLayout,
		RC = ChaosRiftCore}
	dofile("data/scripts/chaos/waystone_tiers_core.lua")
	dofile("data/scripts/chaos/waystone_mods_core.lua")
	local KK, WK = ChaosWaystoneTiersCore, ChaosWaystoneModsCore
	local tcfg = dofile("data/scripts/chaos/waystone_tiers_config.lua")
	local mcfg = dofile("data/scripts/chaos/waystone_mods_config.lua")
	local index = KK.index(tcfg)
	local faults = {}
	local WT = {config = tcfg, applied = {}, active = {}}
	local WM = {config = mcfg, runs = {}, mon = {}}
	ChaosWaystoneTiers, ChaosWaystoneMods = WT, WM
	local monsters = {}
	function WT.entryOf(c) return KK.classify(tcfg, index, c:getName(), c:getPosition(), WT.active) end
	function WT.addWaystone(corpse, t) corpse:addItem(tcfg.tiers[t].item, 1) end
	function WT.startRun(area, sid, mods)
		local t, i = KK.tierOfItem(tcfg, sid), KK.mapOfArea(tcfg, area.fromPos)
		if not t or not i then return nil end
		WT.active[i] = t
		WM.begin(i, t, mods or {})
		if faults.noRescale then return 0 end
		local n = 0
		for _, c in ipairs(monsters) do
			local e = WT.entryOf(c)
			if WT.applied[c.id] and e then
				local target = KK.level(tcfg, e)
				if target ~= WT.applied[c.id] then
					local f = KK.scale(tcfg, WT.applied[c.id], target)
					c.max = math.floor(c.max * f.health + 0.5)
					WT.applied[c.id] = target
					n = n + 1
				end
				local run = WM.runs[i]
				if run and not faults.noHealthMod then c.max = math.floor(c.max * run.fx.health + 0.5) end
			end
		end
		return n
	end
	function WM.runOf(i) return WM.runs[i] end
	function WM.write(item, ws)
		local mods = {}
		for _, m in ipairs(ws.mods) do mods[#mods + 1] = m end
		item.ws = {tier = ws.tier, mods = mods}
	end
	function WM.read(item) return item.ws or {tier = KK.tierOfItem(tcfg, item.id), mods = {}} end
	function WM.choose(p, item) WM.chosen = item end
	function WM.take(p, sid)
		local item = WM.chosen
		for i, it in ipairs(p.bag) do
			if it == item then table.remove(p.bag, i) end
		end
		local mods = {}
		for _, m in ipairs(item.ws and item.ws.mods or {}) do mods[#mods + 1] = m end
		mods.opener = 1
		return true, mods
	end
	function WM.begin(i, t, mods)
		WM.runs[i] = nil
		if #mods == 0 then return nil end
		WM.runs[i] = {tier = t, mods = mods, fx = WK.effects(mcfg, mods, t), bonus = WK.bonuses(mcfg, mods, t), untilAt = os.time() + 1860}
	end
	function WM.finish(i) WM.runs[i] = nil end
	function WM.lootMult() return 1 end

	local mapFrom = tcfg.maps[1].from
	local function mkMonster(id, name, pos, max)
		local c = {id = id, name = name, pos = pos, max = max}
		function c:isMonster() return true end
		function c:getMaster() return nil end
		function c:getId() return self.id end
		function c:getName() return self.name end
		function c:getPosition() return self.pos end
		function c:getMaxHealth() return self.max end
		return c
	end
	monsters = {mkMonster(900001, "Armorcoil", {x = mapFrom.x + 50, y = mapFrom.y + 30, z = mapFrom.z}, 10000),
		mkMonster(900002, "Blazefang", {x = mapFrom.x + 60, y = mapFrom.y + 40, z = mapFrom.z}, 12000)}
	for _, c in ipairs(monsters) do WT.applied[c.id] = 1100 end
	local playersInMap = {}
	Game = {getPlayers = function() return {} end,
		getSpectators = function(pos, multi, onlyPlayers) return onlyPlayers and playersInMap or monsters end,
		createItem = function(id, n, pos)
			local box = {id = id, items = {}}
			function box:addItem(itemId, k)
				local it = {id = itemId, count = k or 1, attrs = {}}
				function it:getId() return self.id end
				function it:getCount() return self.count end
				function it:setCustomAttribute(a, v) self.attrs[a] = v end
				function it:getCustomAttribute(a) return self.attrs[a] end
				self.items[#self.items + 1] = it
				return it
			end
			function box:getItems() return self.items end
			function box:remove() self.removed = true end
			return box
		end}
	ChaosGearSets = {items = {pieces = {{id = 50001, set = "sunderthrone", level = 2400, name = "Sunder Piece"},
		{id = 50002, set = "lumenhallow", level = 1700, name = "Lumen Piece"}}}}
	ChaosLoot = {addToCorpse = function(corpse, id, n)
		local it = corpse:addItem(id, n)
		return it, n
	end, rollUniques = function() return {} end}
	ChaosContentRewards, ChaosContentRewardsCore = nil, nil
	dofile("data/scripts/chaos/content_rewards.lua")
	local wp = creature(268435700, "Tester Wsa", {store = {[ST] = 1}})
	wp.bag = {}
	function wp:addItem(id, n)
		local it = {id = id, count = n, ws = nil}
		function it:getId() return self.id end
		local owner = self
		function it:getTopParent() return owner.bagFull and {} or owner end
		self.bag[#self.bag + 1] = it
		return it
	end
	function wp:getItemCount(id)
		local c = 0
		for _, it in ipairs(self.bag) do if it.id == id then c = c + it.count end end
		return c
	end
	wp:addItem(tcfg.tiers[2].item, 1) -- a plain waystone the tester carries: the take must leave it
	local function ask(pl, cmd, kind)
		talks["!tester"].onSay(pl, "!tester", cmd)
		return lastBody(pl, kind)
	end

	wp.bagFull = true
	local nBag = #wp.bag
	has((ask(wp, "waystone 2", "waystone")), "the bag is full", "waystone: a waystone that fell on the ground: refused")
	wp.bagFull = nil
	table.remove(wp.bag, nBag + 1)
	body = ask(wp, "waystone 2", "waystone")
	has(body, '"tier":2', "waystone: tier 2")
	has(body, '"tierLevel":1200', "waystone: tier 2 runs at level 1200")
	has(body, '"rarity":"Rare"', "waystone: a Rare waystone reads back")
	has(body, '"expectRarity":"Rare"', "waystone: ... as written")
	has(body, '"ok":true', "waystone: the device took it")
	has(body, '"live":true', "waystone: the run is registered")
	has(body, '"active":2', "waystone: the map counts at the waystone's tier")
	has(body, '"level":1200', "waystone: the map's monsters are at the tier's level")
	has(body, '"levelBefore":1100', "waystone: ... from the level they had")
	has(body, '"expectLevel":1200', "waystone: ... which is the rule's level")
	check(body:find('"err"', 1, true) == nil, "waystone: no error: " .. tostring(body))
	eq(wp:getItemCount(tcfg.tiers[2].item), 1, "waystone: the tester's own plain waystone is untouched, the written one is gone")
	eq(WT.active[1], nil, "waystone: the map counts as before after the command")
	eq(WM.runs[1], nil, "waystone: the run is closed")
	eq(WT.applied[900001], 1100, "waystone: the monsters are back at their level")

	-- a run that does not rescale the monsters shows in the answer (the check names it)
	faults.noRescale = true
	monsters[1].max, monsters[2].max = 10000, 12000
	body = ask(wp, "waystone 3", "waystone")
	has(body, '"level":1100', "waystone fault: the monsters stayed at 1100 in a tier 3 run")
	has(body, '"expectLevel":1300', "waystone fault: the rule says 1300")
	faults.noRescale = nil
	-- a busy map and a missing system
	playersInMap = {ana}
	has((ask(wp, "waystone 3", "waystone")), '"err":"map in use"', "waystone: players in the map: refused")
	playersInMap = {}
	WM.runs[1] = {tier = 1, mods = {{}}, fx = {}, untilAt = os.time() + 100}
	has((ask(wp, "waystone 3", "waystone")), '"err":"map in use"', "waystone: a live run on the map: refused")
	WM.runs[1] = nil
	has((ask(wp, "waystone 99", "waystone")), '"err":"usage', "waystone: a bad tier is refused")
	-- the boss table through the content rewards
	body = ask(wp, "waystone 8 loot", "waystone")
	has(body, '"paid":true', "loot: the boss kill paid")
	has(body, '"minPieces":4', "loot: tier 8 guarantees floor(3 + 0.25 x 7) pieces")
	has(body, '"minWaystones":1', "loot: and a waystone of the tier")
	local pieces = tonumber(body:match('"pieces":(%d+)'))
	check(pieces and pieces >= 4, "loot: at least 4 gear pieces in the corpse: " .. tostring(pieces))
	eq(tonumber(body:match('"badRarity":(%d+)')), 0, "loot: no piece under Legendary")
	check(body:find('"name":"Orb of Awakening"', 1, true) and body:find('"min":2', 1, true), "loot: the sure orbs are listed with their minimum")
	local orbCount = tonumber(body:match('"count":(%d+)[^}]-"id":29851')) or tonumber(body:match('"id":29851[^}]-"count":(%d+)'))
	check(orbCount and orbCount >= 2, "loot: Orb of Awakening x" .. tostring(orbCount))
	eq(tonumber(body:match('"waystones":(%d+)')) >= 1, true, "loot: the waystone of the run's tier is in the corpse")
	-- content rewards switched off: the kill pays nothing and the answer says so
	ChaosContentRewards.config.enabled = false
	body = ask(wp, "waystone 8 loot", "waystone")
	has(body, '"paid":false', "loot fault: a disabled content reward pays nothing")
	ChaosContentRewards.config.enabled = true
	-- no system
	ChaosWaystoneTiers = nil
	has((ask(wp, "waystone 2", "waystone")), '"err":"no waystone system"', "waystone: no system, an error answer")
	ChaosWaystoneTiers = WT

	-- ---------------------------------------------------------------- rift layouts and the guardian's reward
	dofile("data/scripts/chaos/rift_layout_core.lua")
	ChaosRiftConfig = dofile("data/scripts/chaos/rift_config.lua")
	local RL, rcfg = ChaosRiftLayout, ChaosRiftConfig
	local walkKeys = {}
	for y = 100, 179 do
		for x = 100, 179 do walkKeys[#walkKeys + 1] = RL.key(x, y, 7) end
	end
	table.sort(walkKeys)
	local L = {theme = "Obsidian Hall", kind = "dungeon", band = 1, side = 144, floors = {7}, walkKeys = walkKeys, walkable = #walkKeys,
		route = 160, start = {x = 101, y = 101, z = 7}, bossSpawn = {x = 178, y = 178, z = 7}, arenaStart = {x = 170, y = 170, z = 7}}
	local rp = creature(268435701, "Tester Rfa", {store = {[ST] = 1}})
	rp.getLevel = function() return 600 end
	rp.bag = {}
	function rp:getItemById(id)
		for _, it in ipairs(self.bag) do if it.id == id then return it end end
	end
	function rp:getItemCount() return 0 end
	local RF = {runOf = {}, runs = {}, bossDead = {}, busy = false}
	ChaosRift = RF
	function RF.giveKey(p, key) p.bag[#p.bag + 1] = {id = rcfg.key.itemId, tier = key.tier} end
	function RF.open(p, item)
		if RF.busy then return false end
		local run = {L = L, slot = 3, key = {tier = item.tier}, state = "running"}
		RF.runOf[p:getId()], RF.runs[3] = run, run
		p.opened = item.tier
		p:teleportTo(L.start)
		return true
	end
	function RF.interrupt(run)
		for id in pairs(RF.runOf) do RF.runOf[id] = nil end
		if not faults.stuck then RF.runs[run.slot] = nil end
		rp:teleportTo({x = 50, y = 50, z = 7})
	end
	function RF.contentOf(monster, player)
		local run = RF.runOf[player:getId()]
		if not run then return nil end
		return {tier = run.key.tier, omen = false, guardian = RF.bossDead[monster:getId()] == true, quantity = 1}
	end
	local ground = true
	Tile = function(pos) return {getGround = function() return ground and {} or nil end, hasFlag = function() return faults.blocked end} end
	TILESTATE_BLOCKSOLID = 1
	body = ask(rp, "riftrun layout", "riftrun")
	has(body, '"theme":"Obsidian Hall"', "rift: the theme")
	eq(rp.opened, 7, "rift: a level 600 tester opens the highest tier it may (tier 7 needs level 600)")
	has(body, '"startWalk":true', "rift: the arrival is a walkable cell")
	has(body, '"bossWalk":true', "rift: the guardian's spot is a walkable cell")
	has(body, '"mouthWalk":true', "rift: the arena's mouth is a walkable cell")
	has(body, '"playerWalk":true', "rift: the tester stands on a walkable cell")
	has(body, '"walkable":6400', "rift: the walkable count")
	has(body, '"walkableMin":4500', "rift: the band's limits come from the balance config")
	has(body, '"bare":0', "rift: every sampled cell has a ground")
	has(body, '"inRun":false', "rift: the run is closed")
	has(body, '"slotFree":true', "rift: the slot is free again")
	check(body:find('"kinds":["dungeon","mixed"]', 1, true) ~= nil, "rift: the theme's kinds come from the config")
	eq(next(RF.runOf), nil, "rift: the tester is out")
	ground = false
	has((ask(rp, "riftrun layout", "riftrun")), '"bare":40', "rift fault: tiles without a ground are counted")
	ground = true
	faults.blocked = true
	has((ask(rp, "riftrun layout", "riftrun")), '"blocked":40', "rift fault: blocking walkable tiles are counted")
	faults.blocked = nil
	faults.stuck = true
	has((ask(rp, "riftrun layout", "riftrun")), '"slotFree":false', "rift fault: a slot that stays busy is reported")
	faults.stuck = nil
	RF.runs[3] = nil
	RF.busy = true
	has((ask(rp, "riftrun layout", "riftrun")), '"busy":true', "rift: a slot that is busy: an error with busy")
	RF.busy = false
	rp.getLevel = function() return 50 end
	has((ask(rp, "riftrun layout", "riftrun")), '"err":"level too low for a rift"', "rift: a low level: an error")
	rp.getLevel = function() return 600 end
	body = ask(rp, "riftrun loot", "riftrun")
	has(body, '"paid":true', "rift loot: the guardian's kill paid")
	local orbs, minOrbs = tonumber(body:match('"orbs":(%d+)')), tonumber(body:match('"minOrbs":(%d+)'))
	check(orbs and minOrbs and orbs >= minOrbs and minOrbs >= 4, "rift loot: orbs " .. tostring(orbs) .. " >= " .. tostring(minOrbs))
	eq(RF.bossDead[2000000001], nil, "rift loot: the stand-in guardian is forgotten")
	-- the real player's words are left alone, as for every command
	local msgs = #ana.log.msgs
	check(talks["!tester"].onSay(ana, "!tester", "waystone 3") == true and talks["!tester"].onSay(ana, "!tester", "riftrun") == true,
		"a player's !tester waystone / riftrun is left to the game")
	eq(#ana.log.msgs, msgs, "a player is never answered")

	Tile, Game, ChaosWaystoneTiers, ChaosWaystoneMods = saved.Tile, saved.Game, saved.WT, saved.WM
	ChaosContentRewards, ChaosLoot, ChaosGearSets = saved.CR, saved.L, saved.GS
	ChaosRift, ChaosRiftConfig = saved.RF, saved.RFC
end

-- ------------------------------------------------------------------ O579: numbered commands, a loop that never throws, a crowd, no chest tile
do
	local c1, a1, n1 = H.parseCommand("spellquest kill 3 #12")
	check(c1 == "spellquest" and a1 == "kill 3" and n1 == 12, "parseCommand: the number after the argument")
	local c2, a2, n2 = H.parseCommand("town #5")
	check(c2 == "town" and a2 == nil and n2 == 5, "parseCommand: a number and no argument")
	eq(select(3, H.parseCommand("town")), nil, "parseCommand: no number")
	eq(select(3, H.parseCommand("enter npc Archivist Odrenna")), nil, "parseCommand: a name is no number")
	check(H.parseCommand("nonsense #3") == nil, "parseCommand: an unknown command stays unknown")
	check(H.parseSpellQuest((select(2, H.parseCommand("spellquest set 1 1 0 0 #8")))).quest == 1, "the argument of a numbered command parses")

	local t5 = creature(268435490, "Tester Abq", {store = {[ST] = 1}})
	talks["!tester"].onSay(t5, "!tester", "info #7")
	check(last(t5):find('"seq":7', 1, true) ~= nil, "a numbered command: its answer carries the number")
	talks["!tester"].onSay(t5, "!tester", "nonsense #9")
	check(last(t5):find('error {', 1, true) and last(t5):find('"seq":9', 1, true), "an unknown command answers with its number too")
	talks["!tester"].onSay(t5, "!tester", "info")
	check(last(t5):find('"seq"', 1, true) == nil, "a command with no number: an answer with none")
	talks["!tester"].onSay(t5, "!tester", "info #11")
	events.TesterHelperLogout.onLogout(t5)
	eq(T.seq[t5:getId()], nil, "a logout forgets the number")

	-- the loop is a timer: a round that errors must not throw into the engine nor end the loop (live run 2026-11-15: 54 timer errors)
	T.ids[t5:getId()] = true
	local realSpectators = Game.getSpectators
	Game.getSpectators = function() error("stale creature") end
	local nt, nprinted = #timers, #printed
	local threw = false
	for _ = 1, 8 do
		if not pcall(function() lastStep().fn() end) then
			threw = true
		end
	end
	check(not threw, "a failing round of the loop does not throw")
	eq(#timers, nt + 8, "and every round schedules the next")
	local errors = 0
	for i = nprinted + 1, #printed do
		if printed[i]:find("[tester-helper] error in the loop", 1, true) and printed[i]:find("stale creature", 1, true) then
			errors = errors + 1
		end
	end
	eq(errors, 1, "the error is printed once a minute, not at every round")
	Game.getSpectators = realSpectators
	T.ids[t5:getId()] = nil
	T.present = function() return false end
	T.lastStepError, T.ids = nil, {}
	local nt2, nprinted2 = #timers, #printed
	for _ = 1, 20 do lastStep().fn() end
	T.present = function() return true end
	check(#timers <= nt2 + 20, "a removed helper file still ends the loop")
	local stopped = false
	for i = nprinted2 + 1, #printed do
		if printed[i]:find("stopped:", 1, true) then stopped = true end
	end
	check(stopped, "the loop says it stopped")
	T.started = true
	addEvent(T.step_fn, 500) -- the loop goes on for the tests below

	-- a crowd round an NPC: no tile within four, the answer says so (the check asks again instead of "not in the game")
	local realTile2 = Tile
	Tile = function() return {getGround = function() return true end, hasFlag = function() return false end,
		getTopCreature = function() return {} end} end
	talks["!tester"].onSay(t5, "!tester", "enter npc Keeper of Trials #20")
	check(last(t5):find('"crowd":true', 1, true) and last(t5):find('"err":"no free tile"', 1, true) and last(t5):find('"seq":20', 1, true),
		"enter npc in a crowd: no free tile, crowd true")
	-- a free tile only at four tiles: found now (two was the reach before)
	Tile = function(p) return {getGround = function() return true end, hasFlag = function() return false end,
		getTopCreature = function() if math.max(math.abs(p.x - 70), math.abs(p.y - 70)) < 4 then return {} end end} end
	talks["!tester"].onSay(t5, "!tester", "enter npc Keeper of Trials #21")
	check(last(t5):find('"npc":"Keeper of Trials"', 1, true) ~= nil, "enter npc: a free tile four away is taken")
	check(math.max(math.abs(t5.pos.x - 70), math.abs(t5.pos.y - 70)) == 4, "the tile is four from the NPC")
	check(T.RINGS[1][2] == -1 and #T.RINGS == 8 + 16 + 24 + 32, "the rings: 8 neighbours first, then 2, 3 and 4 out")
	Tile = realTile2

	-- no tile for a cursed chest near the tester: an answer with the reason, not state "none"
	local realGuid2 = t5.getGuid
	t5.getGuid = function() return 91 end
	local spawned = {}
	ChaosCursedChestConfig = {}
	ChaosCursedChestCore = {areaLevel = function() return 50 end, buildPool = function() return {} end}
	ChaosCursedChest = {chests = {}, tagged = {}, spawnChest = function(_, center)
		spawned[#spawned + 1] = center
		return nil
	end}
	Tile = function() return {getGround = function() return true end, hasFlag = function() return false end} end
	talks["!tester"].onSay(t5, "!tester", "chest spawn #30")
	check(last(t5):find('"err":"no tile for a chest near the tester', 1, true) and last(t5):find('"seq":30', 1, true),
		"chest spawn with no tile: an error answer with its reason")
	check(last(t5):find('"state"', 1, true) == nil, "and no state \"none\"")
	check(#spawned > 2, "other centres up to four tiles out were tried first (" .. #spawned .. ")")
	local far = false
	for _, c in ipairs(spawned) do
		if math.max(math.abs(c.x - t5.pos.x), math.abs(c.y - t5.pos.y)) >= 3 then far = true end
	end
	check(far, "a centre three or four tiles out")
	-- the first centre that takes a chest wins
	local made
	ChaosCursedChest.spawnChest = function(owner, center)
		spawned[#spawned + 1] = center
		if math.abs(center.x - t5.pos.x) >= 3 and not made then
			made = {key = "k9", ownerId = 91, state = "idle", itemId = 1, pos = {x = center.x, y = center.y, z = 7}, ev = nil}
			ChaosCursedChest.chests.k9 = made
			return made
		end
	end
	talks["!tester"].onSay(t5, "!tester", "chest spawn #31")
	check(last(t5):find('"state":"idle"', 1, true) ~= nil and made and made.level == 50, "a chest made at a farther centre: idle, level set")
	ChaosCursedChest, ChaosCursedChestConfig, ChaosCursedChestCore = nil, nil, nil
	t5.getGuid = realGuid2
	Tile = realTile2
end

-- closed test mode (O582): the helper reports the deployed rules
do
	check(H.COMMANDS.closed and H.parseCommand("closed") == "closed", "closed is a registered command (O582)")
	dofile("data/scripts/chaos/testers_core.lua")
	local g = H.closedGuards(ChaosTestersCore)
	local n = 0
	for system in pairs(ChaosTestersCore.CLOSED_SYSTEMS) do
		n = n + 1
		check(g[system] and g[system].mixed and g[system].off and g[system].together, system .. ": every guard holds in the rules")
	end
	check(n >= 7, "arena, battleground, pvp, guild, guild war, market and bazaar are closed systems")
	check(next(H.closedGuards(nil)) == nil and next(H.closedGuards({})) == nil, "no rules: no guards reported")
	local weak = {CLOSED_SYSTEMS = {arena = true}, sameSide = function() return true end}
	local w = H.closedGuards(weak)
	check(w.arena.mixed == false and w.arena.off == false, "rules that let a tester meet a player are reported as not guarding")
end

-- the raid in closed test mode (O588): `!tester raid [state | portal | close]`
do
	check(H.COMMANDS.raid and H.parseCommand("raid portal") == "raid", "raid is a registered command (O588)")
	eq(H.parseRaid(nil), "state", "raid: no word is state")
	eq(H.parseRaid("Portal"), "portal", "raid: portal (any case)")
	eq(H.parseRaid("close"), "close", "raid: close")
	local w, usage = H.parseRaid("start")
	check(w == nil and usage:find("usage: raid", 1, true), "raid: start is no helper word: the bot opens the raid from its own window")
	local a = H.raidAnswer({inside = true, level = 900, minLevel = 800, pos = {x = 1, y = 2, z = 7, junk = 1}, on = true, junk = 1,
		portal = {x = 5, y = 6, z = 7}, run = {id = 3, slot = 3, side = "tester", players = 2, killed = 1, trash = 2, kills = 4,
			fight = 2, phase = 1, trashLeft = 3, monsters = 9, bossHp = 80, fallen = false, final = {x = 8, y = 8, z = 7}, junk = 1},
		guide = {mode = "walk", goal = {x = 9, y = 9, z = 7, junk = 1}, why = ("x"):rep(100), idx = 2, where = "hall", area = "trash",
			junk = 1}}, {closed = true})
	check(a.inside and a.on and a.pos.x == 1 and a.pos.junk == nil and a.junk == nil, "raid answer: cut down to what the bot reads")
	check(a.run.side == "tester" and a.run.slot == 3 and a.run.final.x == 8 and a.run.junk == nil and a.run.fallen == false, "raid answer: the run")
	check(a.guide.mode == "walk" and a.guide.goal.x == 9 and #a.guide.why == 60 and a.guide.junk == nil, "raid answer: the guide")
	eq(a.closed, true, "raid answer: extra merged in")
	check(H.raidAnswer(nil).inside == false and H.raidAnswer(nil).run == nil, "raid answer: nothing known")
	check(H.json(H.raidAnswer({inside = false, level = 50, pos = {x = 1, y = 2, z = 7}})):find('"inside":false', 1, true), "raid answer: encodes")

	local t5 = creature(268435499, "Tester Abz", {store = {[ST] = 1}})
	local realRaid, realTile3 = ChaosRaid, Tile
	local closedCalls = 0
	ChaosRaid = {probe = function(p)
		return {inside = p.inRaid == true, level = 900, minLevel = 800, minPlayers = 1, maxPlayers = 15, on = true, pz = true,
			pos = p:getPosition(), portal = {x = 70, y = 71, z = 7}, bosses = 5}
	end, testerClose = function(p) closedCalls = closedCalls + 1 return true end}
	Tile = function() return {getGround = function() return true end, hasFlag = function() return false end,
		getTopCreature = function() return nil end} end
	talks["!tester"].onSay(t5, "!tester", "raid #40")
	check(last(t5):find('"portal":{"x":70', 1, true) and last(t5):find('"seq":40', 1, true) and last(t5):find('"minLevel":800', 1, true),
		"raid state: the entrance, the level rule and the number of the command")
	t5.pos = {x = 100, y = 100, z = 7}
	talks["!tester"].onSay(t5, "!tester", "raid portal #41")
	check(math.max(math.abs(t5.pos.x - 70), math.abs(t5.pos.y - 71)) == 1, "raid portal: next to the entrance, not on it")
	check(not (t5.pos.x == 70 and t5.pos.y == 71), "raid portal: never on the portal tile")
	check(last(t5):find('"seq":41', 1, true) and not last(t5):find('"err"', 1, true), "raid portal: answered")
	-- the path on foot: the engine's own pathfinding, cut to the directions 0-7
	eq(H.parseRaid("path"), "path", "raid: path")
	local dirs = H.pathDirections({1, 1, 2, "x", 9, 3, -1, 1.5, 7})
	eq(table.concat(dirs, ","), "1,1,2,3,7", "path: only the directions 0-7 stay")
	eq(#H.pathDirections(nil), 0, "path: nothing is no path")
	local long = {}
	for i = 1, 200 do long[i] = 1 end
	eq(#H.pathDirections(long), H.RAID_PATH_MAX, "path: at most RAID_PATH_MAX steps")
	t5.getPathTo = function(self, pos, minD, maxD, full, clear, dist)
		t5.pathAsked = {pos = pos, maxD = maxD}
		return {1, 1, 2, 3}
	end
	talks["!tester"].onSay(t5, "!tester", "raid path #47")
	check(last(t5):find('"path":[1,1,2,3]', 1, true) and last(t5):find('"seq":47', 1, true), "raid path: the directions of the path")
	check(t5.pathAsked.pos.x == 70 and t5.pathAsked.pos.y == 71 and t5.pathAsked.maxD == 1, "raid path: to the portal, a tile next to it")
	t5.getPathTo = function() return false end
	talks["!tester"].onSay(t5, "!tester", "raid path #48")
	check(last(t5):find("no path to the raid portal", 1, true), "raid path: no path, the reason")
	t5.getPathTo = nil
	talks["!tester"].onSay(t5, "!tester", "raid path #49")
	check(last(t5):find("no path to the raid portal", 1, true), "raid path: an engine without the call, the reason")
	t5.inRaid = true
	talks["!tester"].onSay(t5, "!tester", "raid path #50")
	check(last(t5):find("already inside the raid", 1, true), "raid path: inside, no path")
	t5.inRaid = nil
	talks["!tester"].onSay(t5, "!tester", "raid close #42")
	check(last(t5):find('"closed":true', 1, true) and closedCalls == 1, "raid close: the testers' own raid is closed")
	talks["!tester"].onSay(t5, "!tester", "raid bogus #43")
	check(last(t5):find("usage: raid", 1, true), "raid: an unknown word is the usage")
	t5.inRaid = true
	local before = t5.pos
	talks["!tester"].onSay(t5, "!tester", "raid portal #44")
	check(last(t5):find("already inside the raid", 1, true) and t5.pos == before, "raid portal: inside, no teleport")
	t5.inRaid = nil
	Tile = function() return {getGround = function() return false end, hasFlag = function() return false end,
		getTopCreature = function() return nil end} end
	talks["!tester"].onSay(t5, "!tester", "raid portal #45")
	check(last(t5):find("no free tile next to the raid portal", 1, true), "raid portal: no free tile, the reason")
	ChaosRaid = nil
	talks["!tester"].onSay(t5, "!tester", "raid #46")
	check(last(t5):find("no raid system", 1, true), "raid: no raid system, the reason")
	ChaosRaid, Tile = realRaid, realTile3
	-- a player is never answered
	local civ = creature(990, "Ana Raider", {store = {}})
	local nBefore = #civ.log.msgs
	local passed = talks["!tester"].onSay(civ, "!tester", "raid close #1")
	check(passed == true and #civ.log.msgs == nBefore, "raid: a player's words go on and get no answer")
end

-- the way on foot and the dungeons in closed test mode (O589): `!tester path ...`, `!tester dungeon [state | path | close]`
do
	check(H.COMMANDS.path and H.COMMANDS.dungeon, "path and dungeon are registered commands (O589)")
	check(H.parseCommand("path temple") == "path" and H.parseCommand("dungeon path #3") == "dungeon", "path / dungeon parse")
	eq(H.parseDungeon(nil), "state", "dungeon: no word is state")
	eq(H.parseDungeon("PATH"), "path", "dungeon: path (any case)")
	eq(H.parseDungeon("close"), "close", "dungeon: close")
	local w, usage = H.parseDungeon("queue")
	check(w == nil and usage:find("usage: dungeon", 1, true), "dungeon: queue is no helper word: the bot queues from the window")
	local pl = H.parsePath("temple")
	check(pl and pl.kind == "temple", "path: a place kind")
	pl = H.parsePath("dungeon 2")
	check(pl and pl.kind == "dungeon" and pl.n == 2, "path: the n-th mark of a kind")
	pl = H.parsePath("npc Archivist Odrenna")
	check(pl and pl.kind == "npc" and pl.name == "Archivist Odrenna", "path: an NPC")
	pl = H.parsePath("pos 31574 31623 8")
	check(pl and pl.kind == "pos" and pl.x == 31574 and pl.y == 31623 and pl.z == 8, "path: a position")
	check(H.parsePath("rift 3") == nil and H.parsePath("pos 1 2") == nil and H.parsePath("pos 1 2 99") == nil and H.parsePath("") == nil,
		"path: a rift, half a position, a floor above 15 and nothing are no destination")
	local ans = H.pathAnswer({x = 10, y = 10, z = 7}, {x = 13, y = 8, z = 7}, {1, 1}, {name = "x"})
	check(ans.dist == 3 and ans.path[2] == 1 and ans.dest.x == 13 and ans.name == "x" and ans.floor == nil, "path answer: the distance left")
	ans = H.pathAnswer({x = 10, y = 10, z = 7}, {x = 13, y = 8, z = 8}, nil)
	check(ans.dist == nil and ans.floor == 1 and #ans.path == 0, "path answer: another floor has no distance")
	local a = H.dungeonAnswer({inside = true, level = 900, pos = {x = 1, y = 2, z = 8, junk = 1}, on = true, junk = 1,
		run = {id = 4, dungeon = 4, title = "Rootmaw", side = "tester", percent = 40, left = 12, unlocked = false, junk = 1},
		guide = {mode = "walk", goal = {x = 5, y = 6, z = 8}, why = ("w"):rep(80), area = "monsters", junk = 1}})
	check(a.inside and a.on and a.pos.junk == nil and a.junk == nil, "dungeon answer: cut down to what the bot reads")
	check(a.run.side == "tester" and a.run.percent == 40 and a.run.junk == nil and a.run.unlocked == false, "dungeon answer: the run")
	check(a.guide.mode == "walk" and a.guide.goal.x == 5 and #a.guide.why == 60 and a.guide.junk == nil, "dungeon answer: the guide")
	local list = {}
	for i = 1, 40 do list[i] = {id = i, title = "d" .. i, level = i, size = 1, max = 1} end
	eq(#H.dungeonAnswer({list = list}).list, H.DUNGEON_LIST_MAX, "dungeon answer: the list is bounded")
	check(H.dungeonAnswer(nil).inside == false and H.dungeonAnswer(nil).run == nil, "dungeon answer: nothing known")

	local t6 = creature(268435510, "Tester Abx", {store = {[ST] = 1}})
	local realPoi, realD, realTile4, realCreature = ChaosPoi, ChaosDungeons, Tile, Creature
	ChaosPoi = {all = {{k = "dungeon", x = 50, y = 51, z = 7, n = "Bones Dungeon"}, {k = "temple", x = 60, y = 60, z = 7, n = "Temple"}}}
	t6.pos = {x = 40, y = 51, z = 7}
	t6.getPathTo = function(self, pos, minD, maxD, full, clear, dist)
		t6.pathAsked = {pos = pos, minD = minD, maxD = maxD}
		return {1, 1, 1, 2}
	end
	talks["!tester"].onSay(t6, "!tester", "path dungeon #60")
	check(last(t6):find('"path":[1,1,1,2]', 1, true) and last(t6):find('"seq":60', 1, true) and last(t6):find('"name":"Bones Dungeon"', 1, true),
		"path: the directions to the mark, the name and the number of the command")
	check(last(t6):find('"dist":10', 1, true), "path: the distance left")
	check(t6.pathAsked.pos.x == 50 and t6.pathAsked.minD == 0 and t6.pathAsked.maxD == 1, "path: to the tile or next to it")
	t6.getPathTo = function() return false end
	talks["!tester"].onSay(t6, "!tester", "path dungeon #61")
	check(last(t6):find('"err":"no path"', 1, true), "path: no path, the reason (the bot's fallback is the teleport)")
	t6.getPathTo = nil
	talks["!tester"].onSay(t6, "!tester", "path dungeon #62")
	check(last(t6):find('"err":"no path"', 1, true), "path: an engine without the call, the reason")
	t6.pos = {x = 50, y = 52, z = 7}
	talks["!tester"].onSay(t6, "!tester", "path dungeon #63")
	check(last(t6):find('"here":true', 1, true), "path: next to it already: here")
	t6.pos = {x = 40, y = 51, z = 8}
	talks["!tester"].onSay(t6, "!tester", "path dungeon #64")
	check(last(t6):find('"err":"another floor"', 1, true), "path: another floor, the reason")
	t6.pos = {x = 40, y = 51, z = 7}
	talks["!tester"].onSay(t6, "!tester", "path bank #65")
	check(last(t6):find('"err":"no such place"', 1, true), "path: a kind with no mark on the map")
	talks["!tester"].onSay(t6, "!tester", "path rift 3 #66")
	check(last(t6):find("usage: path", 1, true), "path: a rift is no destination")
	talks["!tester"].onSay(t6, "!tester", "path pos 70 70 7 #67")
	check(last(t6):find('"dest":{"x":70,"y":70,"z":7}', 1, true), "path: a position")
	Creature = function(name) return nil end
	talks["!tester"].onSay(t6, "!tester", "path npc Nobody #68")
	check(last(t6):find('"err":"no such NPC"', 1, true), "path: no such NPC")

	local closeCalls = 0
	ChaosDungeons = {probe = function(p)
		if p.inRun then
			return {inside = true, level = 900, pos = p:getPosition(), on = true,
				run = {id = 4, dungeon = 4, side = "tester", percent = 10, left = 20, unlocked = false},
				guide = {mode = "walk", goal = {x = 45, y = 51, z = 7}, area = "monsters"}}
		end
		return {inside = false, level = 900, pos = p:getPosition(), on = true, list = {{id = 4, title = "Rootmaw", level = 600, size = 1, max = 1}}}
	end, testerClose = function() closeCalls = closeCalls + 1 return true end}
	talks["!tester"].onSay(t6, "!tester", "dungeon #70")
	check(last(t6):find('"list":[{', 1, true) and last(t6):find('"level":600', 1, true) and last(t6):find('"seq":70', 1, true),
		"dungeon state: the list with the level rule")
	talks["!tester"].onSay(t6, "!tester", "dungeon path #71")
	check(last(t6):find("not inside a dungeon run", 1, true), "dungeon path: outside, the reason")
	t6.inRun = true
	t6.getPathTo = function(self, pos, minD, maxD)
		t6.pathAsked = {pos = pos, minD = minD, maxD = maxD}
		return {3, 3, 0}
	end
	talks["!tester"].onSay(t6, "!tester", "dungeon path #72")
	check(last(t6):find('"path":[3,3,0]', 1, true) and last(t6):find('"dist":5', 1, true), "dungeon path: the directions to the guide's goal")
	check(t6.pathAsked.pos.x == 45 and t6.pathAsked.minD == 1 and t6.pathAsked.maxD == 3, "dungeon path: within reach of the monster, not on it")
	t6.getPathTo = function() return false end
	talks["!tester"].onSay(t6, "!tester", "dungeon path #73")
	check(last(t6):find('"err":"no path"', 1, true), "dungeon path: no path, the reason")
	talks["!tester"].onSay(t6, "!tester", "dungeon close #74")
	check(last(t6):find('"closed":true', 1, true) and closeCalls == 1, "dungeon close: the testers' own run is closed")
	talks["!tester"].onSay(t6, "!tester", "dungeon bogus #75")
	check(last(t6):find("usage: dungeon", 1, true), "dungeon: an unknown word is the usage")
	ChaosDungeons = nil
	talks["!tester"].onSay(t6, "!tester", "dungeon #76")
	check(last(t6):find("no dungeon system", 1, true), "dungeon: no dungeon system, the reason")
	ChaosPoi, ChaosDungeons, Tile, Creature = realPoi, realD, realTile4, realCreature
	local civ2 = creature(991, "Ana Walker", {store = {}})
	local n2 = #civ2.log.msgs
	check(talks["!tester"].onSay(civ2, "!tester", "path temple #1") == true and #civ2.log.msgs == n2, "path: a player's words go on and get no answer")
end


-- the siege, the guild boss and the rift (O592): `!tester siege | guildboss | rift ...`
do
	check(H.COMMANDS.siege and H.COMMANDS.guildboss and H.COMMANDS.rift, "siege, guildboss and rift are registered commands (O592)")
	check(H.parseCommand("siege path #3") == "siege" and H.parseCommand("guildboss hall") == "guildboss" and H.parseCommand("rift key 3") == "rift",
		"siege / guildboss / rift parse")
	eq(H.parseSiege(nil), "state", "siege: no word is state")
	eq(H.parseSiege("START"), "start", "siege: start (any case)")
	eq(H.parseSiege("portal"), "portal", "siege: portal")
	local w, usage = H.parseSiege("join")
	check(w == nil and usage:find("usage: siege", 1, true), "siege: join is no helper word: the testers never sign up")
	eq(H.parseGuildBoss(nil), "state", "guildboss: no word is state")
	eq(H.parseGuildBoss("hall"), "hall", "guildboss: hall")
	w, usage = H.parseGuildBoss("summon")
	check(w == nil and usage:find("usage: guildboss", 1, true), "guildboss: summon is no helper word: the bot summons from the window")
	local r = H.parseRift("key 3")
	check(r and r.what == "key" and r.tier == 3, "rift: key with a tier")
	r = H.parseRift("key")
	check(r and r.what == "key" and r.tier == nil, "rift: key with no tier")
	check(H.parseRift("key 99") == nil and H.parseRift("key 0") == nil and H.parseRift("state 3") == nil and H.parseRift("open") == nil,
		"rift: a bad tier, a number after another word, an unknown word")
	eq(H.parseRift(nil).what, "state", "rift: no word is state")
	-- O671: the Greater Rift Key, the seal and the fail of a tester's own run
	r = H.parseRift("greater 3")
	check(r and r.what == "greater" and r.greater == 3, "rift: greater with a number")
	r = H.parseRift("greater")
	check(r and r.what == "greater" and r.greater == 1, "rift: greater alone is the first one (tier 16)")
	check(H.parseRift("greater 0") == nil and H.parseRift("greater 100") == nil and H.parseRift("greater x") == nil, "rift: a bad Greater number")
	check(H.parseRift("seal").what == "seal" and H.parseRift("FAIL").what == "fail" and H.parseRift("seal 2") == nil, "rift: seal and fail take no number")
	eq(H.riftAnswer({run = {id = 1, greater = 3}}).run.greater, 3, "rift: the answer carries the Greater number of the run")
	eq(H.riftAnswer({keyShown = 20}).keyShown, 20, "rift: the answer carries the shown tier of the key held")
	-- O671: every command the helper defines is a word the dispatcher knows (explode and wsendgame were missing: "unknown command" in the first live run)
	do
		local f = io.open("tools/tester_helper.lua", "r")
		local src = f and f:read("*a") or ""
		if f then f:close() end
		local n, missing = 0, {}
		for name in src:gmatch("\nfunction commands%.(%w+)") do
			n = n + 1
			if not H.COMMANDS[name] then missing[#missing + 1] = name end
		end
		check(n > 40 and #missing == 0, "every commands.X of the helper is in H.COMMANDS (" .. n .. " read; missing: " .. table.concat(missing, ", ") .. ")")
	end
	check(HELPER_VERSION >= 28, "the helper is version 28 or later (O671: rift greater, seal, fail)")
	-- the answers cut the probes down
	local a = H.siegeAnswer({inside = true, level = 900, minLevel = 100, pos = {x = 1, y = 2, z = 7, junk = 1}, on = true, running = true, phase = "match",
		side = "tester", guild = "Tester Guild Alfa", signed = true, left = 90, where = "arena", bracket = 1, center = {x = 5, y = 5, z = 7},
		gate = {x = 4, y = 4, z = 7}, onPoint = true, members = 1, team = {name = "A", score = 7, kills = 0, junk = 1}, holder = "A", contested = false,
		rivals = {{name = "B", score = 0, kills = 0}}, you = {points = 7, kills = 0, deaths = 0, junk = 1},
		guide = {mode = "hold", goal = {x = 5, y = 5, z = 7}, reach = {0, 2}, why = ("w"):rep(80), area = "obelisk", junk = 1}, junk = 1})
	check(a.inside and a.on and a.pos.junk == nil and a.junk == nil and a.team.junk == nil and a.you.junk == nil, "siege answer: cut down to what the bot reads")
	check(a.team.score == 7 and a.holder == "A" and a.rivals[1].name == "B" and a.where == "arena" and a.center.x == 5, "siege answer: the scores and the place")
	check(a.guide.mode == "hold" and a.guide.reach[2] == 2 and #a.guide.why == 60 and a.guide.junk == nil, "siege answer: the guide")
	check(H.siegeAnswer(nil).inside == false and H.siegeAnswer(nil).team == nil, "siege answer: nothing known")
	local g = H.guildBossAnswer({inside = true, hasHall = true, inHall = false, fuel = 5, need = 5, canSummon = true, reason = ("r"):rep(120), stone = {x = 1, y = 1, z = 7},
		board = {"A", "B", "C", "D", "E", "F", "G", "H", "I", "J"}, run = {state = "running", boss = "alive", tester = true, bossHp = 40,
		bossPos = {x = 3, y = 3, z = 7, junk = 1}, gate = {x = 2, y = 2, z = 7}, junk = 1}, guide = {mode = "fight", goal = {x = 3, y = 3, z = 7}, area = "boss"}, junk = 1})
	check(g.inside and g.hasHall and g.fuel == 5 and #g.reason == 90 and #g.board == 8 and g.junk == nil, "guild boss answer: the facts, the board is bounded")
	check(g.run.tester and g.run.bossHp == 40 and g.run.bossPos.junk == nil and g.run.junk == nil and g.guide.mode == "fight", "guild boss answer: the run and the guide")
	local ra = H.riftAnswer({inside = true, level = 400, pos = {x = 1, y = 2, z = 7}, pz = false, held = true, run = {id = 2, tier = 3, theme = "ash", state = "running",
		boss = "waiting", killed = 4, total = 20, entry = {x = 9, y = 9, z = 7, junk = 1}, monsters = 5, junk = 1},
		guide = {mode = "walk", goal = {x = 9, y = 9, z = 7}, reach = {1, 4}, area = "pack"}, junk = 1})
	check(ra.inside and ra.held and ra.run.killed == 4 and ra.run.entry.junk == nil and ra.run.junk == nil and ra.junk == nil, "rift answer: cut down")
	check(ra.guide.reach[2] == 4 and H.riftAnswer(nil).inside == false, "rift answer: the reach, nothing known")

	local last = function(p) return p.log.msgs[#p.log.msgs] end
	local t7 = creature(268435520, "Tester Aby", {store = {[ST] = 1}})
	local realS, realB, realRF, realCfg, realCore, realTile5, realG = ChaosSiege, ChaosGuildBoss, ChaosRift, ChaosRiftConfig, ChaosRiftCore, Tile, ChaosGuild
	-- ---- the siege
	local startCalls, closeCalls, started = 0, 0, true
	ChaosSiege = {probe = function(p)
		local inside = p.inSiege
		local out = {inside = inside, level = 900, minLevel = 100, pos = p:getPosition(), on = true, running = true, phase = "match", side = "tester",
			portal = {x = 70, y = 71, z = 7}}
		if inside then
			out.where, out.center, out.gate = "arena", {x = 60, y = 60, z = 7}, {x = 58, y = 60, z = 7}
			out.guide = {mode = "walk", goal = {x = 60, y = 60, z = 7}, reach = {0, 2}, area = "obelisk"}
		end
		return out
	end, startTester = function() startCalls = startCalls + 1 return started, not started and "players are signed up for the next siege" or nil end,
		testerClose = function() closeCalls = closeCalls + 1 return true end}
	t7.pos = {x = 40, y = 71, z = 7}
	talks["!tester"].onSay(t7, "!tester", "siege #80")
	check(last(t7):find('"portal":{"x":70,"y":71,"z":7}', 1, true) and last(t7):find('"seq":80', 1, true), "siege state: the portal and the number")
	talks["!tester"].onSay(t7, "!tester", "siege start #81")
	check(last(t7):find('"started":true', 1, true) and startCalls == 1, "siege start: the testers' siege is asked for")
	started = false
	talks["!tester"].onSay(t7, "!tester", "siege start #82")
	check(last(t7):find('"started":false', 1, true) and last(t7):find("players are signed up", 1, true), "siege start: refused with the reason")
	t7.getPathTo = function(self, pos, minD, maxD)
		t7.pathAsked = {pos = pos, minD = minD, maxD = maxD}
		return {1, 1, 2}
	end
	talks["!tester"].onSay(t7, "!tester", "siege path #83")
	check(last(t7):find('"path":[1,1,2]', 1, true) and last(t7):find('"dist":30', 1, true), "siege path: the directions to the portal")
	check(t7.pathAsked.pos.x == 70 and t7.pathAsked.minD == 0 and t7.pathAsked.maxD == 1, "siege path: to the portal tile or next to it")
	t7.pos = {x = 70, y = 70, z = 7}
	talks["!tester"].onSay(t7, "!tester", "siege path #84")
	check(last(t7):find('"here":true', 1, true), "siege path: next to the portal: here")
	t7.inSiege = true
	t7.pos = {x = 50, y = 60, z = 7}
	talks["!tester"].onSay(t7, "!tester", "siege path #85")
	check(last(t7):find('"path":[1,1,2]', 1, true) and t7.pathAsked.pos.x == 60 and t7.pathAsked.maxD == 2, "siege path inside: within the capture radius of the obelisk")
	t7.getPathTo = function() return false end
	talks["!tester"].onSay(t7, "!tester", "siege path #86")
	check(last(t7):find('"err":"no path"', 1, true), "siege path: no path, the reason")
	talks["!tester"].onSay(t7, "!tester", "siege portal #87")
	check(last(t7):find("already inside the siege", 1, true), "siege portal: inside, no teleport")
	t7.inSiege = nil
	Tile = function() return {getGround = function() return false end, hasFlag = function() return false end, getTopCreature = function() return nil end} end
	talks["!tester"].onSay(t7, "!tester", "siege portal #88")
	check(last(t7):find("no free tile next to the portal", 1, true), "siege portal: no free tile, the reason")
	Tile = realTile5
	talks["!tester"].onSay(t7, "!tester", "siege close #89")
	check(last(t7):find('"closed":true', 1, true) and closeCalls == 1, "siege close: the testers' own siege is closed")
	talks["!tester"].onSay(t7, "!tester", "siege join #90")
	check(last(t7):find("usage: siege", 1, true), "siege: an unknown word is the usage")
	ChaosSiege = nil
	talks["!tester"].onSay(t7, "!tester", "siege #91")
	check(last(t7):find("no siege system", 1, true), "siege: no siege system, the reason")
	ChaosSiege = realS

	-- ---- the guild boss
	local gbClose, entered = 0, 0
	ChaosGuildBoss = {probe = function(p)
		if p.inArena then
			return {inside = true, level = 900, pos = p:getPosition(), on = true, hasHall = true, run = {state = "running", boss = "alive", tester = true,
				bossPos = {x = 90, y = 50, z = 7}, bossHp = 100}, guide = {mode = "walk", goal = {x = 90, y = 50, z = 7}, reach = {1, 5}, area = "boss"}}
		end
		return {inside = false, level = 900, pos = p:getPosition(), on = true, hasHall = p.hasHall ~= false, inHall = p.inHall, stone = {x = 80, y = 81, z = 7},
			fuel = 0, need = 5, canSummon = false, reason = "The stone holds 0 of 5 embers.", guild = "Tester Guild Alfa", board = {"Tester Guild Alfa"}}
	end, testerClose = function() gbClose = gbClose + 1 return true end}
	ChaosGuild = {enterHall = function(p) entered = entered + 1 p.inHall = true return true end}
	Chaos.guildConfig = {hall = {ids = {portal = 1387}, aid = {enter = 47602}}}
	t7.pos = {x = 50, y = 50, z = 7}
	t7.getPathTo = function(self, pos, minD, maxD)
		t7.pathAsked = {pos = pos, minD = minD, maxD = maxD}
		return {2, 2, 3}
	end
	talks["!tester"].onSay(t7, "!tester", "guildboss #100")
	check(last(t7):find('"hasHall":true', 1, true) and last(t7):find('"need":5', 1, true) and last(t7):find('"board":["Tester Guild Alfa"]', 1, true),
		"guildboss state: the hall, the need and the board the tester sees")
	-- outside the hall: the portal near the temple is found by its action id
	local hallTile = {x = 53, y = 52, z = 7}
	Tile = function(p)
		return {getItemById = function(_, id)
			if id == 1387 and p.x == hallTile.x and p.y == hallTile.y and p.z == hallTile.z then
				return {getActionId = function() return 47602 end}
			end
			return nil
		end, getGround = function() return true end, hasFlag = function() return false end, getTopCreature = function() return nil end}
	end
	talks["!tester"].onSay(t7, "!tester", "guildboss path #101")
	check(last(t7):find('"target":"hall"', 1, true) and last(t7):find('"path":[2,2,3]', 1, true) and t7.pathAsked.pos.x == 53,
		"guildboss path outside: on foot to the Guild Hall Portal")
	talks["!tester"].onSay(t7, "!tester", "guildboss hall #102")
	check(entered == 1 and last(t7):find('"inHall":true', 1, true), "guildboss hall: the portal's own entry, the fallback")
	talks["!tester"].onSay(t7, "!tester", "guildboss path #103")
	check(last(t7):find('"target":"stone"', 1, true) and t7.pathAsked.pos.x == 80 and t7.pathAsked.pos.y == 81, "guildboss path in the hall: on foot to the stone")
	t7.inArena = true
	talks["!tester"].onSay(t7, "!tester", "guildboss path #104")
	check(t7.pathAsked.pos.x == 90 and t7.pathAsked.minD == 1 and t7.pathAsked.maxD == 5, "guildboss path in the arena: within reach of the boss")
	talks["!tester"].onSay(t7, "!tester", "guildboss hall #105")
	check(last(t7):find("already inside the arena", 1, true) and entered == 1, "guildboss hall: inside the arena, no entry")
	t7.inArena = nil
	t7.hasHall = false
	talks["!tester"].onSay(t7, "!tester", "guildboss path #106")
	check(last(t7):find("the guild has no hall", 1, true), "guildboss path: no hall, the reason")
	t7.hasHall = nil
	Tile = realTile5
	talks["!tester"].onSay(t7, "!tester", "guildboss close #107")
	check(last(t7):find('"closed":true', 1, true) and gbClose == 1, "guildboss close: the testers' own run is closed")
	talks["!tester"].onSay(t7, "!tester", "guildboss summon #108")
	check(last(t7):find("usage: guildboss", 1, true), "guildboss: an unknown word is the usage")
	ChaosGuildBoss = nil
	talks["!tester"].onSay(t7, "!tester", "guildboss #109")
	check(last(t7):find("no guild boss system", 1, true), "guildboss: no system, the reason")
	ChaosGuildBoss, ChaosGuild = realB, realG

	-- ---- the rift
	local riftClose, given = 0, 0
	local rcfg = {key = {itemId = 4444}, maxTier = 5}
	ChaosRiftConfig = rcfg
	ChaosRiftCore = {tierInfo = function(_, t) return {minLevel = t * 100} end}
	ChaosRift = {giveKey = function() given = given + 1 end, testerClose = function() riftClose = riftClose + 1 return true end,
		probe = function(p)
			if p.inRift then
				return {inside = true, level = p:getLevel(), pos = p:getPosition(), pz = false, held = false,
					run = {id = 1, tier = 3, state = "running", boss = "waiting", killed = 1, total = 9, monsters = 8, floors = 1},
					guide = {mode = "walk", goal = {x = 30, y = 30, z = 7}, reach = {1, 4}, area = "pack"}}
			end
			return {inside = false, level = p:getLevel(), pos = p:getPosition(), pz = p.zone and true or false, held = p.keyHeld and true or false}
		end}
	t7.getLevel = function() return 350 end
	t7.getItemById = function(self, id) return self.keyHeld and {remove = function(item) self.keyHeld = false return true end} or nil end
	t7.pos = {x = 50, y = 50, z = 7}
	talks["!tester"].onSay(t7, "!tester", "rift #110")
	check(last(t7):find('"pz":false', 1, true) and last(t7):find('"tier":3', 1, true), "rift state: the zone and the tier the level opens")
	talks["!tester"].onSay(t7, "!tester", "rift key #111")
	check(last(t7):find("not in a protection zone", 1, true) and given == 0, "rift key: outside a protection zone, no key")
	t7.zone = true
	talks["!tester"].onSay(t7, "!tester", "rift key 2 #112")
	check(given == 1 and last(t7):find('"tier":2', 1, true), "rift key: the named tier is given where the bot stands")
	talks["!tester"].onSay(t7, "!tester", "rift key #113")
	check(given == 2 and last(t7):find('"tier":3', 1, true), "rift key: no tier is the highest the level opens")
	t7.getLevel = function() return 50 end
	talks["!tester"].onSay(t7, "!tester", "rift key #114")
	check(last(t7):find("level too low for a rift", 1, true) and given == 2, "rift key: a level that opens none")
	t7.getLevel = function() return 350 end
	t7.inRift = true
	talks["!tester"].onSay(t7, "!tester", "rift key #115")
	check(last(t7):find("already inside a rift", 1, true) and given == 2, "rift key: inside, none")
	t7.getPathTo = function(self, pos, minD, maxD)
		t7.pathAsked = {pos = pos, minD = minD, maxD = maxD}
		return {0, 0, 1}
	end
	t7.pos = {x = 50, y = 30, z = 7}
	talks["!tester"].onSay(t7, "!tester", "rift path #116")
	check(last(t7):find('"path":[0,0,1]', 1, true) and t7.pathAsked.pos.x == 30 and t7.pathAsked.minD == 1 and t7.pathAsked.maxD == 4,
		"rift path: on foot to the guide's goal, within reach of the monster")
	t7.getPathTo = function() return false end
	talks["!tester"].onSay(t7, "!tester", "rift path #117")
	check(last(t7):find('"err":"no path"', 1, true), "rift path: no path, the reason")
	t7.inRift = nil
	talks["!tester"].onSay(t7, "!tester", "rift path #118")
	check(last(t7):find("not inside a rift", 1, true), "rift path: outside, the reason")
	t7.keyHeld = true
	talks["!tester"].onSay(t7, "!tester", "rift close #119")
	check(last(t7):find('"closed":true', 1, true) and riftClose == 1 and t7.keyHeld == false, "rift close: the run ends and a refunded key is taken out")
	talks["!tester"].onSay(t7, "!tester", "rift bogus #120")
	check(last(t7):find("usage: rift", 1, true), "rift: an unknown word is the usage")
	ChaosRift = nil
	talks["!tester"].onSay(t7, "!tester", "rift #121")
	check(last(t7):find("no rifts on this server", 1, true), "rift: no rifts, the reason")
	ChaosRift, ChaosRiftConfig, ChaosRiftCore = realRF, realCfg, realCore
	-- `enter rift`: no teleport from a protection zone, counted in the answer
	ChaosRift = {giveKey = function() end}
	ChaosRiftConfig = {key = {itemId = 4444}}
	t7.getItemById = function() return nil end
	local temple0 = {x = 50, y = 50, z = 7}
	t7.pos = {x = 120, y = 120, z = 7}
	function t7:teleportTo(p) self.pos = p end
	Tile = function() return {hasFlag = function(_, f) return f == TILESTATE_PROTECTIONZONE end, getItemById = function() return nil end} end
	talks["!tester"].onSay(t7, "!tester", "enter rift 2 #122")
	check(last(t7):find('"teleported":false', 1, true) and t7.pos.x == 120, "enter rift: in a protection zone the bot stays (it walked there)")
	Tile = function() return {hasFlag = function() return false end, getItemById = function() return nil end} end
	talks["!tester"].onSay(t7, "!tester", "enter rift 2 #123")
	check(last(t7):find('"teleported":true', 1, true) and t7.pos.x == temple0.x, "enter rift: outside one the temple, counted as a teleport")
	ChaosRift, ChaosRiftConfig, Tile = realRF, realCfg, realTile5
	-- a player is never answered
	local civ3 = creature(992, "Ana Rifter", {store = {}})
	local n3 = #civ3.log.msgs
	check(talks["!tester"].onSay(civ3, "!tester", "siege start #1") == true and talks["!tester"].onSay(civ3, "!tester", "guildboss close #2") == true
		and talks["!tester"].onSay(civ3, "!tester", "rift key #3") == true and #civ3.log.msgs == n3, "siege / guildboss / rift: a player's words go on and get no answer")
end

-- the Infinity Tower and the Ember Descent (O595): `!tester tower | descent ...`
do
	check(H.COMMANDS.tower and H.COMMANDS.descent, "tower and descent are registered commands (O595)")
	check(H.parseCommand("tower path #3") == "tower" and H.parseCommand("descent sigil") == "descent", "tower / descent parse")
	eq(H.parseTower(nil), "state", "tower: no word is state")
	eq(H.parseTower("CLOSE"), "close", "tower: close (any case)")
	local w, usage = H.parseTower("enter")
	check(w == nil and usage:find("usage: tower", 1, true) and not usage:find("sigil", 1, true), "tower: enter is no helper word: the bot enters from the window")
	eq(H.parseDescent("sigil"), "sigil", "descent: sigil")
	w, usage = H.parseDescent("start")
	check(w == nil and usage:find("usage: descent", 1, true) and usage:find("sigil", 1, true), "descent: start is no helper word: the bot starts from the window")
	local ta = H.towerAnswer({inside = true, level = 300, minLevel = 100, pos = {x = 1, y = 2, z = 7, junk = 1}, canEnter = true, free = 12, reserve = 4, bank = 99,
		floorGold = 50, inArena = true, run = {slot = 2, floor = 3, cleared = 2, remaining = 4, total = 6, monsters = 4, boss = false, waiting = false, nextIn = 0,
		left = 7000, floorLeft = 200, players = 1, testers = 1, canSkip = false, nextBoss = true, junk = 1},
		guide = {mode = "walk", goal = {x = 5, y = 5, z = 7, junk = 1}, reach = {1, 5}, why = ("w"):rep(90), area = "pack", junk = 1}, junk = 1})
	check(ta.inside and ta.canEnter and ta.free == 12 and ta.bank == 99 and ta.junk == nil and ta.pos.junk == nil, "tower answer: the facts, cut down")
	check(ta.run.floor == 3 and ta.run.testers == 1 and ta.run.nextBoss and ta.run.junk == nil, "tower answer: the run")
	check(ta.guide.mode == "walk" and ta.guide.reach[2] == 5 and #ta.guide.why == 60 and ta.guide.goal.junk == nil and ta.guide.junk == nil, "tower answer: the guide")
	check(H.towerAnswer(nil).inside == false and H.towerAnswer(nil).run == nil, "tower answer: nothing known")
	local da = H.descentAnswer({inside = true, level = 300, minLevel = 100, pos = {x = 1, y = 2, z = 7}, pz = false, pay = "sigil", payWhy = ("y"):rep(120), sigils = 1,
		free = 6, reserve = 2, run = {id = 4, room = 2, rooms = 10, kind = "combat", state = "choose", depth = 1, monsters = 0, left = 500, players = 1, testers = 1,
		embers = 5, offer = {id = 9, cards = 3, curse = true, left = 30, junk = 1}, boss = {pos = {x = 3, y = 3, z = 7, junk = 1}, hp = 40}, ready = true, junk = 1},
		guide = {mode = "pick", offer = 9, card = 1}, junk = 1})
	check(da.pay == "sigil" and #da.payWhy == 90 and da.sigils == 1 and da.junk == nil, "descent answer: how it is paid, cut down")
	check(da.run.offer.id == 9 and da.run.offer.cards == 3 and da.run.offer.junk == nil and da.run.boss.hp == 40 and da.run.boss.pos.junk == nil and da.run.junk == nil,
		"descent answer: the choice and the boss")
	check(da.guide.mode == "pick" and da.guide.offer == 9 and da.guide.card == 1, "descent answer: the guide asks the pick")
	check(H.descentAnswer(nil).inside == false, "descent answer: nothing known")

	local last = function(p) return p.log.msgs[#p.log.msgs] end
	local t9 = creature(268435530, "Tester Abz", {store = {[ST] = 1}})
	local realTR, realD = ChaosTowerRun, ChaosDescent
	local closes, sigils = 0, 0
	ChaosTowerRun = {probe = function(p)
		if p.inTower then
			return {inside = true, level = 300, minLevel = 100, pos = p:getPosition(), canEnter = true, run = {floor = 2, remaining = 3, players = 1, testers = 1},
				guide = {mode = "walk", goal = {x = 90, y = 50, z = 7}, reach = {1, 5}, area = "pack"}}
		end
		return {inside = false, level = 300, minLevel = 100, pos = p:getPosition(), canEnter = true, free = 16, reserve = 4}
	end, testerClose = function() closes = closes + 1 return true end}
	ChaosDescent = {probe = function(p)
		if p.inDescent then
			return {inside = true, level = 300, pos = p:getPosition(), run = {room = 1, rooms = 9, state = "fight"},
				guide = {mode = "walk", goal = {x = 40, y = 40, z = 7}, reach = {1, 5}, area = "pack"}}
		end
		return {inside = false, level = 300, pos = p:getPosition(), pz = true, pay = sigils > 0 and "sigil" or "free", sigils = sigils}
	end, testerClose = function() closes = closes + 1 return true end, testerSigil = function() sigils = sigils + 1 return true end}
	t9.pos = {x = 60, y = 60, z = 7}
	t9.getPathTo = function(self, pos, minD, maxD)
		t9.pathAsked = {pos = pos, minD = minD, maxD = maxD}
		return {2, 2, 3}
	end
	talks["!tester"].onSay(t9, "!tester", "tower #130")
	check(last(t9):find('"inside":false', 1, true) and last(t9):find('"free":16', 1, true) and last(t9):find('"seq":130', 1, true), "tower state: outside, the halls and the number")
	talks["!tester"].onSay(t9, "!tester", "tower path #131")
	check(last(t9):find("not inside the tower", 1, true), "tower path outside: the reason")
	t9.inTower = true
	talks["!tester"].onSay(t9, "!tester", "tower path #132")
	check(last(t9):find('"path":[2,2,3]', 1, true) and t9.pathAsked.pos.x == 90 and t9.pathAsked.minD == 1 and t9.pathAsked.maxD == 5, "tower path: on foot to the monster, within reach")
	talks["!tester"].onSay(t9, "!tester", "tower close #133")
	check(closes == 1 and last(t9):find('"closed":true', 1, true), "tower close: the bot's own run")
	talks["!tester"].onSay(t9, "!tester", "tower bogus #134")
	check(last(t9):find("usage: tower", 1, true), "tower: an unknown word is the usage")
	t9.inTower = nil
	talks["!tester"].onSay(t9, "!tester", "descent #140")
	check(last(t9):find('"pay":"free"', 1, true) and last(t9):find('"pz":true', 1, true), "descent state: how a run is paid")
	talks["!tester"].onSay(t9, "!tester", "descent sigil #141")
	check(sigils == 1 and last(t9):find('"given":true', 1, true) and last(t9):find('"pay":"sigil"', 1, true), "descent sigil: given, and the next run is paid with it")
	t9.inDescent = true
	talks["!tester"].onSay(t9, "!tester", "descent sigil #142")
	check(sigils == 1 and last(t9):find("already inside the descent", 1, true), "descent sigil: never inside a run")
	talks["!tester"].onSay(t9, "!tester", "descent path #143")
	check(last(t9):find('"path":[2,2,3]', 1, true) and t9.pathAsked.pos.x == 40, "descent path: on foot to the monster")
	talks["!tester"].onSay(t9, "!tester", "descent close #144")
	check(closes == 2 and last(t9):find('"closed":true', 1, true), "descent close: the bot's own run")
	ChaosTowerRun = nil
	talks["!tester"].onSay(t9, "!tester", "tower #145")
	check(last(t9):find("no tower system", 1, true), "tower: no tower system, the reason")
	ChaosDescent = nil
	talks["!tester"].onSay(t9, "!tester", "descent #146")
	check(last(t9):find("no descent system", 1, true), "descent: no descent system, the reason")
	-- ---- the trials
	check(H.COMMANDS.trial and H.parseCommand("trial path #5") == "trial", "trial is a registered command")
	eq(H.parseTrial(nil), "state", "trial: no word is state")
	w, usage = H.parseTrial("enter")
	check(w == nil and usage:find("usage: trial", 1, true), "trial: enter is no helper word: the bot enters from the tree window")
	local tra = H.trialAnswer({inside = true, level = 300, minLevel = 100, pos = {x = 1, y = 2, z = 7, junk = 1}, pz = false, family = "warrior", familyName = "Iron Gauntlet",
		cleared = 1, tier = 2, maxTier = 3, problem = ("p"):rep(120), puzzle = true, kinds = {"wave", "wave", "boss", "a", "b", "c", "d", "e", "f", "g", "h", "i", "j"},
		run = {tier = 2, phase = "fight", stage = "wave", stageIdx = 1, stages = 4, killed = 3, total = 12, lives = 3, livesMax = 3, left = 400, monsters = 5,
		boss = "waiting", bossPos = {x = 3, y = 3, z = 7, junk = 1}, junk = 1}, guide = {mode = "fight", goal = {x = 5, y = 5, z = 7}, area = "pack"}, junk = 1})
	check(tra.inside and tra.family == "warrior" and tra.tier == 2 and #tra.problem == 90 and tra.puzzle == true and #tra.kinds == 12 and tra.junk == nil, "trial answer: the facts, bounded")
	check(tra.run.killed == 3 and tra.run.lives == 3 and tra.run.bossPos.junk == nil and tra.run.junk == nil and tra.guide.mode == "fight", "trial answer: the run and the guide")
	check(H.trialAnswer(nil).inside == false and H.trialAnswer(nil).run == nil, "trial answer: nothing known")
	local realTT = ChaosTrials
	ChaosTrials = {probe = function(p)
		if p.inTrial then
			return {inside = true, level = 300, pos = p:getPosition(), run = {stage = "wave", killed = 1},
				guide = {mode = "walk", goal = {x = 70, y = 40, z = 7}, reach = {1, 5}, area = "pack"}}
		end
		return {inside = false, level = 300, pos = p:getPosition(), pz = true, family = "warrior", tier = 1, minLevel = 100, free = 8, reserve = 2}
	end, testerClose = function() closes = closes + 1 return true end}
	t9.inDescent = nil
	local c0 = closes
	talks["!tester"].onSay(t9, "!tester", "trial #150")
	check(last(t9):find('"family":"warrior"', 1, true) and last(t9):find('"tier":1', 1, true) and last(t9):find('"seq":150', 1, true), "trial state: outside, the family and the next tier")
	talks["!tester"].onSay(t9, "!tester", "trial path #151")
	check(last(t9):find("not inside a trial", 1, true), "trial path outside: the reason")
	t9.inTrial = true
	talks["!tester"].onSay(t9, "!tester", "trial path #152")
	check(last(t9):find('"path":[2,2,3]', 1, true) and t9.pathAsked.pos.x == 70, "trial path: on foot to the monster")
	talks["!tester"].onSay(t9, "!tester", "trial close #153")
	check(closes == c0 + 1 and last(t9):find('"closed":true', 1, true), "trial close: the bot's own run")
	-- ---- O685: `trial clear [N]` (TEST ONLY: a family whose trial is a puzzle), the held picks in the state, the vocation in `info`
	local wc, nc = H.parseTrial("clear")
	check(wc == "clear" and nc == nil, "trial clear: no number is the last tier")
	wc, nc = H.parseTrial("clear 2")
	check(wc == "clear" and nc == 2, "trial clear 2")
	wc, nc = H.parseTrial(" clear  3 ")
	check(wc == "clear" and nc == 3, "trial clear: spaces are fine")
	w, usage = H.parseTrial("clear x")
	check(w == nil and usage:find("usage: trial", 1, true), "trial clear: a word after it is no number")
	w, usage = H.parseTrial("clearing")
	check(w == nil and usage ~= nil, "trial: clearing is no helper word")
	check(H.trialAnswer({picks = {1, 2, 0, 9}}).picks[3] == 0 and #H.trialAnswer({picks = {1, 2, 0, 9}}).picks == 3, "trial answer: the held node of each pair, three numbers")
	check(H.trialAnswer({}).picks == nil, "trial answer: no picks known")
	local clearedWith
	ChaosTrials.testerClear = function(_, n)
		clearedWith = n
		if n == 9 then return nil, "the tier is 0 to 3" end
		return n or 3
	end
	talks["!tester"].onSay(t9, "!tester", "trial clear #170")
	check(clearedWith == nil and last(t9):find('"set":3', 1, true) and last(t9):find('"seq":170', 1, true), "trial clear: the last tier by default, the answer says what was set")
	talks["!tester"].onSay(t9, "!tester", "trial clear 2 #171")
	check(clearedWith == 2 and last(t9):find('"set":2', 1, true), "trial clear 2: the tier asked")
	talks["!tester"].onSay(t9, "!tester", "trial clear 9 #172")
	check(last(t9):find("the tier is 0 to 3", 1, true) and not last(t9):find('"set"', 1, true), "trial clear: the server's refusal is the answer")
	ChaosTrials.testerClear = nil
	talks["!tester"].onSay(t9, "!tester", "trial clear #173")
	check(last(t9):find("no trial system", 1, true), "trial clear: an older trials file has no such function: the reason")
	talks["!tester"].onSay(t9, "!tester", "info #174")
	check(last(t9):find('"voc":4', 1, true), "info: the vocation id of the bot (the class changes in a run, O685)")
	check(HELPER_VERSION >= 33, "the helper is version 33 or later (O685: trial clear, voc in info)")
	-- ---- O685: gear set RARITY, and `loadout` (cards of the best set, support runes), TEST ONLY
	check(H.COMMANDS.loadout and H.parseCommand("loadout cards Earth #5") == "loadout", "loadout is a registered command")
	eq(H.parseGear("set").rarity, nil, "gear set: no number, the default rarity")
	eq(H.parseGear("set 10").rarity, 10, "gear set 10: Divine")
	eq(H.parseGear("set 5").rarity, 5, "gear set 5: Legendary")
	w, usage = H.parseGear("set 7")
	check(w == nil and usage:find("usage: gear", 1, true), "gear set 7: no such stored rarity")
	w, usage = H.parseGear("state 3")
	check(w == nil and usage ~= nil, "gear state takes no number")
	do
		local lp = creature(268435499, "Tester Abz", {store = {[ST] = 1}})
		lp.getVocation = function() return {getId = function() return 8 end, getName = function() return "Juggernaut" end} end
		lp.getLevel = function() return 1900 end
		lp.getCapacity = function() return 1000 end
		lp.setCapacity = function() end
		talks["!tester"].onSay(lp, "!tester", "loadout cards Earth #180")
		check(last(lp):find("no cards system", 1, true) and last(lp):find('"seq":180', 1, true), "loadout cards: no cards system, the reason")
		local toggled, owned, on = {}, {}, {}
		ChaosCardsConfig = {maxActive = 5, sets = {need = 3}, cards = {
			[100] = {storage = 9100, kind = "convert", family = 1, element = "Earth", spell = "Earthbreaker", spells = {{"Earthbreaker", 221}}},
			[101] = {storage = 9101, kind = "convert", family = 1, element = "Fire", spell = "Earthbreaker", spells = {{"Earthbreaker", 221}}},
			[102] = {storage = 9102, kind = "convert", family = 2, element = "Earth", spell = "Reaping Gyre", spells = {{"Reaping Gyre", 220}}},
			[103] = {storage = 9103, kind = "convert", family = 3, element = "Earth", spell = "Heal", spells = {{"Heal", 5}}},
			[104] = {storage = 9104, kind = "convert", family = 4, element = "Earth", spell = "Far", spells = {{"Far", 6}}},
		}}
		ChaosCardDeck = {add = function(_, id, n) owned[id] = (owned[id] or 0) + n end, unlock = function() end}
		ChaosCards = {toggle = function(p, id) toggled[#toggled + 1] = id; on[id] = true; p.storage[ChaosCardsConfig.cards[id].storage] = 1 end}
		ChaosSupports = {
			spellInfo = function(id)
				local t = {[221] = {level = 1100, vocations = {[8] = true}}, [220] = {level = 1200, vocations = {[8] = true}}, [5] = {level = 10, vocations = {[10] = true}},
					[6] = {level = 3000, vocations = {[8] = true}}}
				return t[id]
			end,
			catalog = function() return {} end,
		}
		lp.storage = lp.storage or {}
		lp.getStorageValue = lp.getStorageValue or function(self, k) return self.storage[k] or -1 end
		lp.setStorageValue = lp.setStorageValue or function(self, k, v) self.storage[k] = v end
		talks["!tester"].onSay(lp, "!tester", "loadout cards earth #181")
		check(#toggled == 2 and toggled[1] == 100 and toggled[2] == 102, "loadout cards: one Earth card of each family the class casts (the Fire card, the heal of another class and the spell above the level are left)")
		check(owned[100] == 1 and owned[102] == 1 and owned[101] == nil, "loadout cards: the cards are put in the Deck first")
		check(last(lp):find('"set":false', 1, true), "loadout cards: two cards are no set (the set needs three)")
		-- O689: with the cards core, a line is picked by lineClasses (the Frostfall Rune line is no attack spell of ChaosSupports and every class casts it)
		toggled, owned, on = {}, {}, {}
		lp.storage[9100], lp.storage[9102] = nil, nil
		ChaosCardsConfig.lineClasses = {["Earthbreaker"] = {"Juggernaut"}, ["Reaping Gyre"] = {"Warrior"}, ["Frostfall Rune"] = {"Warrior", "Juggernaut"}}
		ChaosCardsConfig.cards[105] = {storage = 9105, kind = "convert", family = 5, element = "Earth", spell = "Frostfall Rune", spells = {}}
		ChaosCardsCore = {classNameOf = function() return "Juggernaut" end,
			castsLine = function(name, fam) for _, n in ipairs(ChaosCardsConfig.lineClasses[fam.spell] or {}) do if n == name then return true end end return false end}
		talks["!tester"].onSay(lp, "!tester", "loadout cards earth #183")
		local got = {}
		for _, id in ipairs(toggled) do got[id] = true end
		check(got[100] and got[105] and not got[102] and not got[103], "loadout cards: the Frostfall Rune card is picked (every class casts it) and a line of another class is not (lineClasses)")
		ChaosCardsCore = nil
		ChaosCardsConfig, ChaosCardDeck, ChaosCards, ChaosSupports = nil, nil, nil, nil
		talks["!tester"].onSay(lp, "!tester", "loadout support keenedge,echo kah ael #182")
		check(last(lp):find("no supports system", 1, true), "loadout support: no supports system, the reason")
		talks["!tester"].onSay(lp, "!tester", "loadout support keenedge #183")
		check(last(lp):find("usage: loadout support", 1, true), "loadout support: the words of the spells are named")
	end
	-- ---- the Ascended arenas and the omen arenas (O599)
	check(H.COMMANDS.ascended and H.COMMANDS.omen and H.parseCommand("ascended sigil bloodmoon #1") == "ascended", "ascended and omen are registered commands")
	local pa = H.parseAscended("sigil Storm")
	check(pa.what == "sigil" and pa.kind == "storm", "ascended: sigil with a kind (lower case)")
	eq(H.parseAscended(nil).what, "state", "ascended: no word is state")
	eq(H.parseAscended("path").what, "path", "ascended: path")
	w, usage = H.parseAscended("open")
	check(w == nil and usage:find("usage: ascended", 1, true), "ascended: open is no helper word: the bot uses the sigil itself")
	w, usage = H.parseAscended("close now")
	check(w == nil and usage ~= nil, "ascended: close takes no argument")
	local po = H.parseOmen("key hollow")
	check(po.what == "key" and po.kind == "hollow", "omen: key with a kind")
	check(H.parseOmen("sigil") == nil, "omen: sigil is the Ascended word")
	local aa = H.ascendedAnswer({inside = true, level = 1000, pos = {x = 1, y = 2, z = 7, junk = 1}, pz = false, held = true, sigilKind = "storm", free = 3, reserve = 1,
		kinds = {{key = "bloodmoon", minLevel = 900, junk = 1}}, run = {id = 4, kind = "storm", boss = "alive", state = "running", tester = true, lives = 3, livesMax = 3,
		players = 1, testers = 1, left = 700, down = false, gateIn = 0, phase = 2, bossPos = {x = 5, y = 5, z = 7, junk = 1}, bossHp = 80, gate = {x = 1, y = 1, z = 7}, adds = 2, junk = 1},
		guide = {mode = "fight", goal = {x = 5, y = 5, z = 7}, area = "boss", why = ("w"):rep(90)}, junk = 1})
	check(aa.inside and aa.held and aa.sigilKind == "storm" and aa.free == 3 and aa.junk == nil and aa.pos.junk == nil and aa.kinds[1].junk == nil, "ascended answer: the facts, cut down")
	check(aa.run.tester and aa.run.bossHp == 80 and aa.run.phase == 2 and aa.run.bossPos.junk == nil and aa.run.junk == nil and #aa.guide.why == 60, "ascended answer: the run and the guide")
	check(H.ascendedAnswer(nil).inside == false and H.ascendedAnswer(nil).run == nil, "ascended answer: nothing known")
	check(H.omenAnswer({inside = true, run = {omen = "storm", state = "running"}}).run.omen == "storm", "omen answer: the omen kind of the run")
	local realA, realRF, realRC = ChaosAscended, ChaosRift, ChaosRiftConfig
	local gave, c1 = 0, closes
	ChaosAscended = {probe = function(p)
		if p.inAscended then
			return {inside = true, level = 1000, pos = p:getPosition(), run = {boss = "alive", state = "running"},
				guide = {mode = "walk", goal = {x = 33, y = 44, z = 7}, reach = {1, 5}, area = "boss"}}
		end
		return {inside = false, level = 1000, pos = p:getPosition(), pz = true, held = gave > 0, free = 4, reserve = 1}
	end, testerClose = function() closes = closes + 1 return true end, testerSigil = function(_, kind)
		if kind == "nonsense" then return nil, "no such Ascended Omen" end
		gave = gave + 1
		return false, kind or "bloodmoon"
	end}
	t9.inTrial = nil
	talks["!tester"].onSay(t9, "!tester", "ascended #160")
	check(last(t9):find('"inside":false', 1, true) and last(t9):find('"pz":true', 1, true) and last(t9):find('"seq":160', 1, true), "ascended state: outside")
	talks["!tester"].onSay(t9, "!tester", "ascended sigil #161")
	check(gave == 1 and last(t9):find('"given":true', 1, true) and last(t9):find('"kind":"bloodmoon"', 1, true) and last(t9):find('"held":true', 1, true), "ascended sigil: given, then held")
	talks["!tester"].onSay(t9, "!tester", "ascended sigil nonsense #162")
	check(gave == 1 and last(t9):find("no such Ascended Omen", 1, true), "ascended sigil: the reason of the refusal")
	talks["!tester"].onSay(t9, "!tester", "ascended path #163")
	check(last(t9):find("not inside an arena", 1, true), "ascended path outside: the reason")
	t9.inAscended = true
	talks["!tester"].onSay(t9, "!tester", "ascended sigil #164")
	check(gave == 1 and last(t9):find("already inside an arena", 1, true), "ascended sigil: never inside a run")
	talks["!tester"].onSay(t9, "!tester", "ascended path #165")
	check(last(t9):find('"path":[2,2,3]', 1, true) and t9.pathAsked.pos.x == 33 and t9.pathAsked.maxD == 5, "ascended path: on foot to the boss, within reach")
	talks["!tester"].onSay(t9, "!tester", "ascended close #166")
	check(closes == c1 + 1 and last(t9):find('"closed":true', 1, true), "ascended close: the bot's own run")
	ChaosAscended = nil
	-- ---- the pinnacle bosses (O678)
	check(HELPER_VERSION >= 29, "the helper is version 29 or later (O678: pinnacle)")
	check(H.COMMANDS.pinnacle and H.parseCommand("pinnacle set vhoss #170") == "pinnacle", "pinnacle is a registered command")
	local pp = H.parsePinnacle("set Vhoss")
	check(pp.what == "set" and pp.kind == "vhoss", "pinnacle: set with a boss (lower case)")
	eq(H.parsePinnacle(nil).what, "state", "pinnacle: no word is state")
	eq(H.parsePinnacle("path").what, "path", "pinnacle: path")
	w, usage = H.parsePinnacle("open")
	check(w == nil and usage:find("usage: pinnacle", 1, true), "pinnacle: open is the Keeper's button, never the helper's")
	local pn = H.pinnacleAnswer({inside = "vhoss", level = 2100, pos = {x = 1, y = 2, z = 7, junk = 1}, pz = false, free = 7, reserve = 2, enabled = true, focus = 2,
		bosses = {{key = "malgrath", minLevel = 1800, ready = true, open = true, kills = 3, have = {1, 1, 1, 1}, junk = 1}, {key = "vhoss", minLevel = 2000}},
		run = {id = 5, kind = "vhoss", boss = "alive", state = "running", players = 1, testers = 1, size = 1, falls = 0, left = 900, bossPos = {x = 5, y = 5, z = 7, junk = 1},
			bossHp = 77, bossHealth = 2988000, bossMax = 3876000, sinceBoss = 40, gate = {x = 1, y = 1, z = 7}, junk = 1},
		guide = {mode = "walk", goal = {x = 5, y = 5, z = 7}, reach = {1, 5}, area = "boss", why = ("w"):rep(90)}, junk = 1})
	check(pn.inside == "vhoss" and pn.level == 2100 and pn.free == 7 and pn.junk == nil and pn.pos.junk == nil and pn.bosses[1].junk == nil and #pn.bosses == 2, "pinnacle answer: the facts, cut down")
	check(pn.bosses[1].have[4] == 1 and pn.bosses[1].ready and pn.bosses[1].kills == 3, "pinnacle answer: the fragments held")
	check(pn.run.tester and pn.run.bossHp == 77 and pn.run.bossHealth == 2988000 and pn.run.sinceBoss == 40 and pn.run.bossPos.junk == nil and pn.run.junk == nil
		and #pn.guide.why == 60, "pinnacle answer: the run and the guide")
	check(H.pinnacleAnswer(nil).run == nil and H.pinnacleAnswer(nil).enabled == true, "pinnacle answer: nothing known")
	-- O683: the mark pending now and the tally of the telegraphs reach the bot's check
	local pd = H.pinnacleAnswer({inside = "vhoss", pos = {x = 1, y = 2, z = 7},
		danger = {left = 1200, labels = {"A", "B", "C", "D", ("x"):rep(40)}, count = 2, here = true, marked = {["1,2"] = true}},
		tally = {fired = 4, exposed = 9, taken = 2, by = {["Tidal Collapse"] = {fired = 2, exposed = 4, taken = 1, junk = 1}}, junk = 1}})
	check(pd.danger.left == 1200 and pd.danger.count == 2 and pd.danger.here == true and #pd.danger.labels == 3 and pd.danger.marked == nil, "pinnacle answer: the danger, cut down")
	check(pd.tally.fired == 4 and pd.tally.exposed == 9 and pd.tally.taken == 2 and pd.tally.junk == nil and pd.tally.by["Tidal Collapse"].taken == 1
		and pd.tally.by["Tidal Collapse"].junk == nil, "pinnacle answer: the tally, cut down")
	check(H.pinnacleAnswer({inside = "vhoss"}).danger == nil and H.pinnacleAnswer({inside = "vhoss"}).tally == nil, "pinnacle answer: no danger and no tally when none is up")
	check(HELPER_VERSION >= 31, "the helper is version 31 or later (O683: the probe's danger and tally)")
	-- O684: the planned way to the safe tile, cut to 12 steps of (dx, dy)
	local steps = {}
	for i = 1, 15 do
		steps[i] = {-1, 1, junk = 1}
	end
	local pw = H.pinnacleAnswer({inside = "vhoss", danger = {left = 900, labels = {"A"}, count = 1, here = true, steps = steps}})
	eq(#pw.danger.steps, 12, "pinnacle answer: at most 12 steps of the way to the safe tile")
	check(pw.danger.steps[1][1] == -1 and pw.danger.steps[1][2] == 1 and pw.danger.steps[1].junk == nil, "pinnacle answer: a step is (dx, dy)")
	check(H.pinnacleAnswer({inside = "vhoss", danger = {left = 900, labels = {}, count = 1}}).danger.steps == nil, "pinnacle answer: no steps when the server planned none")
	check(HELPER_VERSION >= 32, "the helper is version 32 or later (O684: the planned way to the safe tile)")
	local realPN = ChaosPinnacle
	local setFor, closesPN = 0, closes
	ChaosPinnacle = {probe = function(p)
		if p.inPinnacle then
			return {inside = "vhoss", level = 2100, pos = p:getPosition(), run = {boss = "alive", state = "running"},
				guide = {mode = "walk", goal = {x = 44, y = 55, z = 7}, reach = {1, 5}, area = "boss"}}
		end
		return {inside = nil, level = 2100, pos = p:getPosition(), pz = true, free = 8, reserve = 2, bosses = {{key = "vhoss", minLevel = 2000, ready = setFor > 0}}}
	end, testerClose = function() closes = closes + 1 return true end, testerSet = function(_, kind)
		if kind == "nonsense" then return nil, "no pinnacle boss named nonsense" end
		setFor = setFor + 1
		return kind or "vhoss"
	end}
	talks["!tester"].onSay(t9, "!tester", "pinnacle #170")
	check(last(t9):find('"inside":null', 1, true) == nil and last(t9):find('"pz":true', 1, true) and last(t9):find('"seq":170', 1, true), "pinnacle state: outside")
	events.TesterHelperDealt.onHealthChange(wolf, t9, -700, COMBAT_PHYSICALDAMAGE, 0, 0, 0)   -- O695: the answer carries the tester's damage tally
	talks["!tester"].onSay(t9, "!tester", "pinnacle #174")
	check(last(t9):find('"dealt":{', 1, true) and last(t9):find('"other":700', 1, true) and last(t9):find('"seq":174', 1, true), "pinnacle state: the damage tally of the tester")
	TesterHelper.dealt = nil
	-- O697: the late tally of the tester and the boss's ledger ride in the answer
	TesterHelper.bossLedger = ChaosTesterHelperCore.ledgerNew(77)
	ChaosTesterHelperCore.ledgerHit(TesterHelper.bossLedger, 900, 120, "player")
	TesterHelper.dealtLate = {}
	ChaosTesterHelperCore.dealtAdd(TesterHelper.dealtLate, t9.id, true, 120, "summon")
	talks["!tester"].onSay(t9, "!tester", "pinnacle #175")
	check(last(t9):find('"late":120', 1, true) and last(t9):find('"lateSummon":120', 1, true) and last(t9):find('"lateHits":1', 1, true), "pinnacle state: the late tally of the tester")
	check(last(t9):find('"ledger":{', 1, true) and last(t9):find('"seen":120', 1, true) and last(t9):find('"lost":900', 1, true) == nil, "pinnacle state: the ledger of the boss")
	TesterHelper.bossLedger, TesterHelper.dealtLate = nil, nil
	talks["!tester"].onSay(t9, "!tester", "pinnacle set #171")
	check(setFor == 1 and last(t9):find('"given":true', 1, true) and last(t9):find('"kind":"vhoss"', 1, true) and last(t9):find('"ready":true', 1, true), "pinnacle set: given, then ready")
	talks["!tester"].onSay(t9, "!tester", "pinnacle set nonsense #172")
	check(setFor == 1 and last(t9):find("no pinnacle boss named nonsense", 1, true), "pinnacle set: the reason of the refusal")
	talks["!tester"].onSay(t9, "!tester", "pinnacle path #173")
	check(last(t9):find("not inside a pinnacle fight", 1, true), "pinnacle path outside: the reason")
	t9.inPinnacle = true
	talks["!tester"].onSay(t9, "!tester", "pinnacle set #174")
	check(setFor == 1 and last(t9):find("already inside a fight", 1, true), "pinnacle set: never inside a run")
	talks["!tester"].onSay(t9, "!tester", "pinnacle path #175")
	check(last(t9):find('"path":[2,2,3]', 1, true) and t9.pathAsked.pos.x == 44 and t9.pathAsked.maxD == 5, "pinnacle path: on foot to the boss, within reach")
	talks["!tester"].onSay(t9, "!tester", "pinnacle close #176")
	check(closes == closesPN + 1 and last(t9):find('"closed":true', 1, true), "pinnacle close: the bot's own way out")
	ChaosPinnacle = nil
	talks["!tester"].onSay(t9, "!tester", "pinnacle #177")
	check(last(t9):find("no pinnacle system", 1, true), "pinnacle: no system, the reason")
	ChaosPinnacle = realPN
	t9.inPinnacle = nil
	talks["!tester"].onSay(t9, "!tester", "ascended #167")
	check(last(t9):find("no ascended system", 1, true), "ascended: no system, the reason")
	-- the omen arena
	t9.inAscended = nil
	local keyHeld, removed = false, 0
	t9.getItemById = function() return keyHeld and {remove = function() keyHeld = false removed = removed + 1 end} or nil end
	ChaosRiftConfig = {omen = {minLevel = 800, key = {id = 32072}}}
	ChaosRift = {probe = function(p)
		if p.inOmen then
			return {inside = true, level = 900, pos = p:getPosition(), run = {omen = "storm", state = "running"},
				guide = {mode = "walk", goal = {x = 55, y = 66, z = 7}, reach = {1, 4}, area = "boss"}}
		end
		return {inside = false, level = 900, pos = p:getPosition(), pz = p.omenPz ~= false}
	end, testerClose = function() closes = closes + 1 return true end, testerOmenKey = function(_, kind)
		if kind == "nonsense" then return nil, "no such omen" end
		keyHeld = true
		return kind or "hollow"
	end}
	local realIT = ItemType
	ItemType = function() return {getClientId = function() return 2222 end} end
	talks["!tester"].onSay(t9, "!tester", "omen #170")
	check(last(t9):find('"minLevel":800', 1, true) and last(t9):find('"seq":170', 1, true), "omen state: outside, the level rule")
	talks["!tester"].onSay(t9, "!tester", "omen key storm #171")
	check(keyHeld and last(t9):find('"kind":"storm"', 1, true) and last(t9):find('"keyClientId":2222', 1, true) and last(t9):find('"held":true', 1, true), "omen key: given, the client id to use it")
	talks["!tester"].onSay(t9, "!tester", "omen key nonsense #172")
	check(last(t9):find("no such omen", 1, true), "omen key: the reason of the refusal")
	t9.omenPz = false
	talks["!tester"].onSay(t9, "!tester", "omen key #173")
	check(last(t9):find("not in a protection zone", 1, true), "omen key: only in a protection zone")
	t9.omenPz = nil
	t9.inOmen = true
	talks["!tester"].onSay(t9, "!tester", "omen key #174")
	check(last(t9):find("already inside a run", 1, true), "omen key: never inside a run")
	talks["!tester"].onSay(t9, "!tester", "omen path #175")
	check(last(t9):find('"path":[2,2,3]', 1, true) and t9.pathAsked.pos.x == 55 and t9.pathAsked.maxD == 4 and last(t9):find('"omen":"storm"', 1, true), "omen path: on foot to the guardian")
	talks["!tester"].onSay(t9, "!tester", "omen close #176")
	check(last(t9):find('"closed":true', 1, true) and removed == 1 and not keyHeld, "omen close: the run ends and a refunded key leaves the backpack")
	ItemType = realIT
	ChaosAscended, ChaosRift, ChaosRiftConfig = realA, realRF, realRC
	t9.inOmen = nil
	-- ---- the bounty board (O599)
	check(H.COMMANDS.bounty and H.parseCommand("bounty where Rat #5") == "bounty", "bounty is a registered command")
	eq(H.parseBounty(nil).what, "state", "bounty: no word is state")
	eq(H.parseBounty("PATH").what, "path", "bounty: path (any case)")
	local pw = H.parseBounty("where Cave Rat")
	check(pw.what == "where" and pw.name == "Cave Rat", "bounty: where takes a monster name with spaces")
	w, usage = H.parseBounty("where")
	check(w == nil and usage:find("usage: bounty", 1, true), "bounty: where needs a name")
	check(H.parseBounty("where Rat; drop table") == nil, "bounty: a name is letters only")
	check(H.parseBounty("accept") == nil, "bounty: accept is the window's word")
	check(H.parseBounty("state now") == nil, "bounty: state takes no argument")
	local ba = H.bountyAnswer({level = 100, pos = {x = 1, y = 2, z = 7, junk = 1}, day = 5, maxActive = 3, target = "1-2",
		active = {{key = "1-2", name = "Rat", progress = 3, required = 60, status = 0, junk = 1}},
		candidates = {{key = "1-1", name = ("N"):rep(60), count = 80, level = 4, distance = 12, mark = {x = 5, y = 6, z = 7, n = ("m"):rep(100), junk = 1}, junk = 1}},
		where = {name = "Rat", marks = 3, distance = 20, nearest = {x = 9, y = 9, z = 7, n = "Hunting: Rat (level 1-10)", junk = 1}},
		guide = {mode = "walk", goal = {x = 5, y = 5, z = 7}, reach = {1, 5}, area = "monster"}, junk = 1})
	check(ba.level == 100 and ba.day == 5 and ba.target == "1-2" and ba.junk == nil and ba.pos.junk == nil, "bounty answer: the facts, cut down")
	check(ba.active[1].progress == 3 and ba.active[1].junk == nil and ba.candidates[1].count == 80 and #ba.candidates[1].name == 40 and #ba.candidates[1].mark.n == 70
		and ba.candidates[1].mark.junk == nil, "bounty answer: the contracts, bounded")
	check(ba.where.marks == 3 and ba.where.nearest.x == 9 and ba.where.nearest.junk == nil and ba.guide.mode == "walk", "bounty answer: where and the guide")
	check(H.bountyAnswer(nil).active[1] == nil and H.bountyAnswer(nil).where == nil, "bounty answer: nothing known")
	local realB = ChaosBounty
	local asked
	ChaosBounty = {probe = function(p, name)
		asked = name
		return {level = 100, pos = p:getPosition(), day = 1, active = {{key = "1-2", name = "Rat", progress = 1, required = 60, status = 0}},
			candidates = {}, where = name and {name = name, marks = 2, distance = 7} or nil,
			guide = {mode = "walk", goal = {x = 77, y = 88, z = 7}, reach = {1, 5}, area = "monster"}}
	end}
	talks["!tester"].onSay(t9, "!tester", "bounty #180")
	check(last(t9):find('"day":1', 1, true) and last(t9):find('"progress":1', 1, true) and last(t9):find('"seq":180', 1, true) and asked == nil, "bounty state: the contracts held")
	talks["!tester"].onSay(t9, "!tester", "bounty where Cave Rat #181")
	check(asked == "Cave Rat" and last(t9):find('"marks":2', 1, true), "bounty where: asks for the monster")
	talks["!tester"].onSay(t9, "!tester", "bounty path #182")
	check(last(t9):find('"path":[2,2,3]', 1, true) and t9.pathAsked.pos.x == 77 and t9.pathAsked.maxD == 5, "bounty path: on foot to the monster")
	talks["!tester"].onSay(t9, "!tester", "bounty bogus #183")
	check(last(t9):find("usage: bounty", 1, true), "bounty: an unknown word is the usage")
	ChaosBounty = nil
	talks["!tester"].onSay(t9, "!tester", "bounty #184")
	check(last(t9):find("no bounty system", 1, true), "bounty: no system, the reason")
	ChaosBounty = realB
	-- ---- the main quest (O599)
	check(H.COMMANDS.mainquest and H.parseCommand("mainquest #9") == "mainquest", "mainquest is a registered command")
	eq(H.parseMainQuest(nil), "state", "mainquest: no word is state")
	w, usage = H.parseMainQuest("skip")
	check(w == nil and usage:find("usage: mainquest", 1, true), "mainquest: skip is the window's word, not the helper's")
	local mq = H.mainQuestAnswer({enabled = true, level = 100, pos = {x = 1, y = 2, z = 7, junk = 1}, state = 1, active = true, step = 5, steps = 60, key = "trolls",
		stepLevel = 8, running = true, progress = 3, target = 12, ready = false,
		cond = {kind = "count", mons = {"Troll", "a", "b", "c", "d"}, target = 12, label = "Troll", pos = {x = 5, y = 5, z = 7, junk = 1}, junk = 1},
		where = {k = "pos", label = "the Troll ground", pos = {x = 9, y = 9, z = 8, junk = 1}, junk = 1},
		plan = {action = "kill", label = "Troll", target = 12, monsters = {"Troll", "a", "b", "c", "d", "e"}, reason = ("r"):rep(120)}, junk = 1})
	check(mq.active and mq.step == 5 and mq.key == "trolls" and mq.progress == 3 and mq.junk == nil and mq.pos.junk == nil, "mainquest answer: the facts, cut down")
	check(mq.cond.kind == "count" and #mq.cond.mons == 4 and mq.cond.pos.junk == nil and mq.where.pos.z == 8 and mq.where.junk == nil, "mainquest answer: the condition and the place")
	check(mq.plan.action == "kill" and #mq.plan.monsters == 4 and #mq.plan.reason == 90 and mq.plan.target == 12, "mainquest answer: the plan, bounded")
	check(H.mainQuestAnswer(nil).active == false and H.mainQuestAnswer(nil).plan == nil, "mainquest answer: nothing known")
	local realW = ChaosMainQuest
	ChaosMainQuest = {probe = function(p) return {enabled = true, level = 100, pos = p:getPosition(), active = true, step = 1, key = "warden", plan = {action = "talk", label = "Warden Ysolde"}} end}
	talks["!tester"].onSay(t9, "!tester", "mainquest #190")
	check(last(t9):find('"key":"warden"', 1, true) and last(t9):find('"action":"talk"', 1, true) and last(t9):find('"seq":190', 1, true), "mainquest state: the step and the plan")
	talks["!tester"].onSay(t9, "!tester", "mainquest bogus #191")
	check(last(t9):find("usage: mainquest", 1, true), "mainquest: an unknown word is the usage")
	ChaosMainQuest = nil
	talks["!tester"].onSay(t9, "!tester", "mainquest #192")
	check(last(t9):find("no main quest system", 1, true), "mainquest: no system, the reason")
	ChaosMainQuest = realW
	-- ---- the Nemesis, the daily, the Chronicle, Vael, the goblin and the invasions (O650)
	for _, c in ipairs({"nemesis", "daily", "chronicle", "vael", "goblin", "invasion"}) do
		check(H.COMMANDS[c] and H.parseCommand(c .. " state #1") == c, c .. " is a registered command")
	end
	eq(H.parseNemesis(nil), "state", "nemesis: no word is state")
	eq(H.parseNemesis("BORN"), "born", "nemesis: born (any case)")
	eq(H.parseNemesis("appear"), "appear", "nemesis: appear")
	local wn, un = H.parseNemesis("kill")
	check(wn == nil and un == "usage: nemesis [state | born | appear | path | close]", "nemesis: an unknown word is the usage: " .. tostring(un))
	check(H.parseNemesis("born now") == nil, "nemesis: a word takes no argument")
	eq(H.parseDaily("state"), "state", "daily: state")
	check(H.parseDaily("claim") == nil, "daily: claim is the window's word")
	check(H.parseChronicle("open") == nil, "chronicle: open is the window's word")
	eq(H.parseVael("enter"), "enter", "vael: enter")
	check(H.parseVael("win") == nil and select(2, H.parseVael("win")) == "usage: vael [state | enter | path | close]", "vael: the usage")
	eq(H.parseGoblin("spawn"), "spawn", "goblin: spawn")
	eq(H.parseExplode("run"), "run", "explode: run (O669)")
	eq(H.parseExplode("state"), "state", "explode: state")
	eq(H.parseExplode("set"), "set", "explode: set (a set piece among the loot, O678)")
	eq(H.parseExplode("bag"), "bag", "explode: bag (the loot stays in the bag, O678)")
	check(H.parseExplode("steal") == nil and select(2, H.parseExplode("steal")) == "usage: explode [state | run | set | bag | join NAME]", "explode: the usage")
	local jw, jn = H.parseExplode("join Tester Aab")
	check(jw == "join" and jn == "Tester Aab", "explode: join takes the name of the owner bot (O671)")
	check(H.parseExplode("join") == nil and H.parseExplode("join   ") == nil, "explode: join needs a name")
	eq(H.parseInvasion("path"), "path", "invasion: path")
	check(H.parseInvasion("start") == nil, "invasion: start is a staff word, never the helper's")
	-- the answer is the probe cut down
	local ans = H.cutAnswer({level = 100, pos = {x = 1, y = 2, z = 7, junk = 1}, f = function() end, text = ("t"):rep(200), nested = {a = {b = {c = {d = 1}}}},
		list = {1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14}, guide = {mode = "walk", goal = {x = 5, y = 6, z = 7, junk = 1}, reach = {1, 5}, why = ("w"):rep(100), junk = 1}},
		{done = true})
	check(ans.level == 100 and ans.pos.junk == nil and ans.f == nil and #ans.text == 90 and #ans.list == 12 and ans.nested.a.b.c == nil and ans.done == true,
		"cutAnswer: scalars kept, strings and lists bounded, three levels")
	check(ans.guide.mode == "walk" and ans.guide.goal.junk == nil and #ans.guide.why == 60 and ans.guide.junk == nil and ans.guide.reach[2] == 5,
		"cutAnswer: the guide as for the other systems")
	check(H.cutAnswer(nil).guide == nil, "cutAnswer: nothing known")
	local realNE, realDY, realCH, realB2, realTG, realIV, realTT2 = ChaosNemesis, ChaosDaily, ChaosChronicle, ChaosMainQuestBoss, ChaosTreasureGoblin, ChaosInvasion, ChaosTrials
	-- nemesis
	local born, appeared, closed2 = 0, 0, 0
	ChaosNemesis = {probe = function(p)
		return {has = born > 0, level = 200, pos = p:getPosition(), guide = born > 1 and {mode = "walk", goal = {x = 40, y = 41, z = 7}, reach = {1, 5}, area = "nemesis"} or {mode = "wait", why = "no Nemesis"}}
	end, testerBorn = function() if born > 0 then return nil, "the bot has a Nemesis already" end born = born + 1 return {} end,
		testerAppear = function() appeared = appeared + 1 born = 2 return true end, testerClose = function() closed2 = closed2 + 1 born = 0 return true end}
	talks["!tester"].onSay(t9, "!tester", "nemesis #200")
	check(last(t9):find('"has":false', 1, true) and last(t9):find('"seq":200', 1, true), "nemesis state")
	talks["!tester"].onSay(t9, "!tester", "nemesis born #201")
	check(born == 1 and last(t9):find('"born":true', 1, true) and last(t9):find('"has":true', 1, true), "nemesis born: the grant, then the record")
	talks["!tester"].onSay(t9, "!tester", "nemesis born #202")
	check(last(t9):find("the bot has a Nemesis already", 1, true), "nemesis born: the reason of the refusal")
	talks["!tester"].onSay(t9, "!tester", "nemesis appear #203")
	check(appeared == 1 and last(t9):find('"appear":true', 1, true), "nemesis appear")
	talks["!tester"].onSay(t9, "!tester", "nemesis path #204")
	check(last(t9):find('"path":[2,2,3]', 1, true) and t9.pathAsked.pos.x == 40 and t9.pathAsked.maxD == 5, "nemesis path: on foot to it, within reach")
	talks["!tester"].onSay(t9, "!tester", "nemesis close #205")
	check(closed2 == 1 and last(t9):find('"closed":true', 1, true), "nemesis close")
	talks["!tester"].onSay(t9, "!tester", "nemesis kill #206")
	check(last(t9):find("usage: nemesis", 1, true), "nemesis: an unknown word")
	ChaosNemesis = nil
	talks["!tester"].onSay(t9, "!tester", "nemesis #207")
	check(last(t9):find("no nemesis system", 1, true), "nemesis: no system, the reason")
	ChaosNemesis = realNE
	-- daily and chronicle
	ChaosDaily = {probe = function() return {taken = false, slot = 3, value = 1, reward = {itemId = 2160, count = 2, clientId = 3031, held = 5}} end}
	talks["!tester"].onSay(t9, "!tester", "daily #210")
	check(last(t9):find('"slot":3', 1, true) and last(t9):find('"value":1', 1, true) and last(t9):find('"held":5', 1, true) and last(t9):find('"seq":210', 1, true),
		"daily state: the slot, the value and the reward")
	ChaosDaily = nil
	talks["!tester"].onSay(t9, "!tester", "daily #211")
	check(last(t9):find("no daily system", 1, true), "daily: no system")
	ChaosDaily = realDY
	ChaosChronicle = {probe = function() return {running = true, tester = true, counted = false, testersListed = 0, goals = {{label = "Raids", progress = 1, target = 5}}} end}
	talks["!tester"].onSay(t9, "!tester", "chronicle #212")
	check(last(t9):find('"counted":false', 1, true) and last(t9):find('"testersListed":0', 1, true) and last(t9):find('"target":5', 1, true), "chronicle state")
	ChaosChronicle = nil
	talks["!tester"].onSay(t9, "!tester", "chronicle #213")
	check(last(t9):find("no chronicle system", 1, true), "chronicle: no system")
	ChaosChronicle = realCH
	-- vael
	local entered, trialCloses = 0, 0
	ChaosMainQuestBoss = {probe = function(p)
		if p.inVael then
			return {inside = true, level = 500, pos = p:getPosition(), family = "warrior", run = {phase = "fight", boss = "alive", bossHp = 90, spell = true},
				won = false, tries = 1, door = "door_closed", guide = {mode = "walk", goal = {x = 90, y = 91, z = 7}, reach = {1, 5}, area = "boss"}}
		end
		return {inside = false, level = 500, minLevel = 500, pos = p:getPosition(), family = "warrior", won = false, tries = 0, door = "door_closed", pz = true}
	end, testerEnter = function(p)
		if p.vaelRefuse then return nil, "Vael's door opens from level 500" end
		entered = entered + 1
		p.inVael = true
		return true
	end}
	ChaosTrials = {testerClose = function(p) trialCloses = trialCloses + 1 p.inVael = nil return true end}
	t9.inVael, t9.vaelRefuse = nil, true
	talks["!tester"].onSay(t9, "!tester", "vael #220")
	check(last(t9):find('"inside":false', 1, true) and last(t9):find('"door":"door_closed"', 1, true) and last(t9):find('"won":false', 1, true), "vael state: the door's facts")
	talks["!tester"].onSay(t9, "!tester", "vael enter #221")
	check(entered == 0 and last(t9):find("opens from level 500", 1, true), "vael enter: the reason of the refusal")
	t9.vaelRefuse = nil
	talks["!tester"].onSay(t9, "!tester", "vael enter #222")
	check(entered == 1 and last(t9):find('"entered":true', 1, true) and last(t9):find('"inside":true', 1, true) and last(t9):find('"bossHp":90', 1, true),
		"vael enter: inside, the boss and its health")
	talks["!tester"].onSay(t9, "!tester", "vael enter #223")
	check(entered == 1 and last(t9):find("already inside a trial", 1, true), "vael enter: never twice")
	talks["!tester"].onSay(t9, "!tester", "vael path #224")
	check(last(t9):find('"path":[2,2,3]', 1, true) and t9.pathAsked.pos.x == 90, "vael path: on foot to the boss")
	talks["!tester"].onSay(t9, "!tester", "vael close #225")
	check(trialCloses == 1 and last(t9):find('"closed":true', 1, true), "vael close: the Leave button")
	talks["!tester"].onSay(t9, "!tester", "vael path #226")
	check(last(t9):find("not inside the trial", 1, true), "vael path outside: the reason")
	ChaosMainQuestBoss, ChaosTrials = nil, nil
	talks["!tester"].onSay(t9, "!tester", "vael #227")
	check(last(t9):find("no main quest boss", 1, true), "vael: no system")
	ChaosMainQuestBoss, ChaosTrials = realB2, realTT2
	-- goblin
	local spawned, gcloses = 0, 0
	ChaosTreasureGoblin = {probe = function(p)
		return {killed = 0, world = 1, goblin = spawned > 0 and {hp = 100, hit = false} or nil,
			guide = spawned > 0 and {mode = "walk", goal = {x = 70, y = 71, z = 7}, reach = {1, 5}, area = "goblin"} or {mode = "wait", why = "no goblin of its own"}}
	end, testerSpawn = function() if spawned > 0 then return nil, "the bot has a goblin already" end spawned = spawned + 1 return {} end,
		testerClose = function() gcloses = gcloses + 1 spawned = 0 return true end}
	talks["!tester"].onSay(t9, "!tester", "goblin spawn #230")
	check(spawned == 1 and last(t9):find('"spawned":true', 1, true) and last(t9):find('"hp":100', 1, true), "goblin spawn: the grant, then the goblin")
	talks["!tester"].onSay(t9, "!tester", "goblin spawn #231")
	check(last(t9):find("the bot has a goblin already", 1, true), "goblin spawn: the reason of the refusal")
	talks["!tester"].onSay(t9, "!tester", "goblin path #232")
	check(last(t9):find('"path":[2,2,3]', 1, true) and t9.pathAsked.pos.x == 70, "goblin path: on foot to it")
	talks["!tester"].onSay(t9, "!tester", "goblin close #233")
	check(gcloses == 1 and last(t9):find('"closed":true', 1, true), "goblin close")
	ChaosTreasureGoblin = nil
	talks["!tester"].onSay(t9, "!tester", "goblin #234")
	check(last(t9):find("no treasure goblin system", 1, true), "goblin: no system")
	ChaosTreasureGoblin = realTG
	-- invasion
	ChaosInvasion = {probe = function(p)
		return {phase = "running", running = true, level = 300, pos = p:getPosition(), credited = false, cancelled = 3,
			invader = {x = 80, y = 81, z = 7, name = "Orc Raider", hp = 40}, guide = {mode = "walk", goal = {x = 80, y = 81, z = 7}, reach = {1, 5}, area = "invader"}}
	end}
	talks["!tester"].onSay(t9, "!tester", "invasion #240")
	check(last(t9):find('"credited":false', 1, true) and last(t9):find('"cancelled":3', 1, true) and last(t9):find('"name":"Orc Raider"', 1, true),
		"invasion state: the invader, no credit, the hits cancelled")
	talks["!tester"].onSay(t9, "!tester", "invasion path #241")
	check(last(t9):find('"path":[2,2,3]', 1, true) and t9.pathAsked.pos.x == 80, "invasion path: on foot to the invader")
	talks["!tester"].onSay(t9, "!tester", "invasion start #242")
	check(last(t9):find("usage: invasion", 1, true), "invasion: start is a staff word")
	ChaosInvasion = nil
	talks["!tester"].onSay(t9, "!tester", "invasion #243")
	check(last(t9):find("no invasion system", 1, true), "invasion: no system")
	ChaosInvasion = realIV
	-- ---- PvP among the testers and the tester copy of a boss (O652)
	for _, c in ipairs({"pvp", "boss"}) do
		check(H.COMMANDS[c] and H.parseCommand(c .. " state #1") == c, c .. " is a registered command")
	end
	eq(H.parsePvp(nil), "state", "pvp: no word is state")
	eq(H.parsePvp("PATH"), "path", "pvp: path (any case)")
	local wp, up = H.parsePvp("hit")
	check(wp == nil and up == "usage: pvp [state | path]", "pvp: an unknown word is the usage: " .. tostring(up))
	eq(H.parseBoss("spawn"), "spawn", "boss: spawn")
	check(H.parseBoss("kill") == nil and select(2, H.parseBoss("kill")) == "usage: boss [state | spawn | path | close]", "boss: the usage")
	-- the aim: only a foe tester, same floor, within range, the nearest, the weakest among equals; a player is never one
	local me = {x = 100, y = 100, z = 7}
	local aim = H.pvpTarget(me, {
		{pos = {x = 101, y = 100, z = 7}, tester = false, foe = true, health = 10, id = 1},
		{pos = {x = 102, y = 100, z = 7}, tester = true, foe = false, health = 10, id = 2},
		{pos = {x = 104, y = 100, z = 7}, tester = true, foe = true, health = 50, id = 3},
		{pos = {x = 100, y = 103, z = 7}, tester = true, foe = true, health = 20, id = 4},
		{pos = {x = 103, y = 100, z = 8}, tester = true, foe = true, health = 5, id = 5},
		{pos = {x = 100, y = 101, z = 7}, tester = true, foe = true, health = 0, id = 6}}, 5)
	check(aim and aim.id == 4, "pvpTarget: the nearest foe tester (a player, a team mate, another floor and a downed one are skipped)")
	aim = H.pvpTarget(me, {{pos = {x = 102, y = 100, z = 7}, tester = true, foe = true, health = 40, id = 7}, {pos = {x = 100, y = 102, z = 7}, tester = true, foe = true, health = 30, id = 8}}, 5)
	check(aim and aim.id == 8, "pvpTarget: equal distance, the lower health")
	check(H.pvpTarget(me, {{pos = {x = 109, y = 100, z = 7}, tester = true, foe = true, health = 1, id = 9}}, 5) == nil, "pvpTarget: out of range")
	check(H.pvpTarget(me, {{pos = {x = 101, y = 100, z = 7}, tester = true, foe = nil, health = 1, id = 9}}, 5) == nil, "pvpTarget: an unknown foe flag is no foe")
	check(H.pvpTarget(me, nil, 5) == nil and H.pvpTarget(me, {}, 5) == nil, "pvpTarget: nobody")
	local hf = io.open("tools/tester_helper.lua", "r")
	local htext = hf and hf:read("*a") or ""
	if hf then hf:close() end
	check(htext:find("pcall(pvpAim, player)", 1, true) ~= nil, "the loop aims at a foe first (pvpAim)")
	check((tonumber(htext:match("HELPER_VERSION = (%d+)")) or 0) >= 21, "the helper is v21 or later (O652)")
	local realTS, realTB = ChaosTesters, ChaosTestersBoss
	-- pvp
	ChaosTesters = {pvpProbe = function(p)
		return {closed = true, place = "arena", cancelledPlayer = 2, cancelledOutside = 1, cancelledOff = 0, seasonListed = 0,
			foe = {x = 75, y = 76, z = 7, name = "Tester Ccc", seen = false}, guide = {mode = "walk", goal = {x = 75, y = 76, z = 7}, reach = {1, 5}, area = "foe"}}
	end}
	talks["!tester"].onSay(t9, "!tester", "pvp #250")
	check(last(t9):find('"place":"arena"', 1, true) and last(t9):find('"seasonListed":0', 1, true) and last(t9):find('"cancelledPlayer":2', 1, true)
		and last(t9):find('"name":"Tester Ccc"', 1, true), "pvp state: the place, the cancelled hits, the season rows, the foe")
	talks["!tester"].onSay(t9, "!tester", "pvp path #251")
	check(last(t9):find('"path":[2,2,3]', 1, true) and t9.pathAsked.pos.x == 75, "pvp path: on foot to the foe")
	talks["!tester"].onSay(t9, "!tester", "pvp hit #252")
	check(last(t9):find("usage: pvp", 1, true), "pvp: an unknown word is the usage")
	ChaosTesters = nil
	talks["!tester"].onSay(t9, "!tester", "pvp #253")
	check(last(t9):find("no PvP rules for the testers", 1, true), "pvp: no rules")
	ChaosTesters = realTS
	-- boss
	local bspawned, bcloses = 0, 0
	ChaosTestersBoss = {probe = function(p)
		return {killed = 0, listed = 0, points = 2, boss = bspawned > 0 and {hp = 100, name = "Talath"} or nil,
			guide = bspawned > 0 and {mode = "walk", goal = {x = 66, y = 67, z = 7}, reach = {1, 6}, area = "boss"} or {mode = "wait", why = "no boss copy of its own"}}
	end, testerSpawn = function() if bspawned > 0 then return nil, "the bot has a boss copy already" end bspawned = bspawned + 1 return {} end,
		testerClose = function() bcloses = bcloses + 1 bspawned = 0 return true end}
	talks["!tester"].onSay(t9, "!tester", "boss spawn #260")
	check(bspawned == 1 and last(t9):find('"spawned":true', 1, true) and last(t9):find('"name":"Talath"', 1, true) and last(t9):find('"points":2', 1, true), "boss spawn: the grant, then the copy")
	talks["!tester"].onSay(t9, "!tester", "boss spawn #261")
	check(last(t9):find("the bot has a boss copy already", 1, true), "boss spawn: the reason of the refusal")
	talks["!tester"].onSay(t9, "!tester", "boss path #262")
	check(last(t9):find('"path":[2,2,3]', 1, true) and t9.pathAsked.pos.x == 66, "boss path: on foot to it")
	talks["!tester"].onSay(t9, "!tester", "boss close #263")
	check(bcloses == 1 and last(t9):find('"closed":true', 1, true), "boss close")
	ChaosTestersBoss = nil
	talks["!tester"].onSay(t9, "!tester", "boss #264")
	check(last(t9):find("no tester boss system", 1, true), "boss: no system")
	ChaosTestersBoss = realTB
	local civ6 = creature(995, "Ana Pvp", {store = {}})
	local n6 = #civ6.log.msgs
	check(talks["!tester"].onSay(civ6, "!tester", "boss spawn #5") == true and talks["!tester"].onSay(civ6, "!tester", "pvp #6") == true and #civ6.log.msgs == n6,
		"pvp / boss: a player's words go on and get no answer")
	-- a player's words go on and get no answer
	local civ5 = creature(994, "Ana Nemesis", {store = {}})
	local n5 = #civ5.log.msgs
	check(talks["!tester"].onSay(civ5, "!tester", "nemesis born #3") == true and talks["!tester"].onSay(civ5, "!tester", "vael enter #4") == true and #civ5.log.msgs == n5,
		"nemesis / vael: a player's words go on and get no answer")
	ChaosTrials = nil
	talks["!tester"].onSay(t9, "!tester", "trial #154")
	check(last(t9):find("no trial system", 1, true), "trial: no trial system, the reason")
	ChaosTrials = realTT
	t9.inTrial = nil
	-- ---- O651: pocket bosses, dungeon difficulties and the Weekly Challenge, the rift stairs, a waystone map walked
	check(H.COMMANDS.pocket and H.COMMANDS.wsmap and H.parseCommand("pocket path #1") == "pocket" and H.parseCommand("wsmap enter 11 #2") == "wsmap",
		"pocket and wsmap are registered commands")
	eq(H.parsePocket(nil), "state", "pocket: no word is state")
	eq(H.parsePocket("PATH"), "path", "pocket: path")
	eq(H.parsePocket("close"), "close", "pocket: close")
	w, usage = H.parsePocket("enter")
	check(w == nil and usage:find("usage: pocket", 1, true), "pocket: enter is the window's request, no helper word")
	local pk = H.pocketAnswer({inside = false, level = 400, pos = {x = 1, y = 2, z = 7, junk = 1}, pz = true, enabled = true, free = 12, reserve = 4,
		points = {got = 2, total = 10, junk = 1}, bosses = {
			{key = "island_b", name = "Island B", category = "island", level = 250, left = 3, ok = true, point = {id = 9, got = true}},
			{key = "world_1", name = "Kaelgor", category = "world", level = 300, left = 2, ok = true, point = {id = 1, got = false}},
			{key = "raid_a", name = "Raid A", category = "raid", level = 150, left = 3, ok = true},
			{key = "raid_z", name = "Raid Z", category = "raid", level = 150, left = 0, ok = true},
			{key = "world_2", name = "Skaldra", category = "world", level = 900, left = 3, ok = false}}})
	check(pk.usable == 3 and #pk.bosses == 3 and pk.bosses[1].key == "world_1" and pk.bosses[2].key == "raid_a" and pk.bosses[3].key == "island_b",
		"pocket answer: only the pockets the bot may open, a boss point it lacks first, then by level")
	check(pk.bosses[1].point.id == 1 and pk.bosses[1].point.got == false and pk.points.got == 2 and pk.points.junk == nil and pk.pos.junk == nil,
		"pocket answer: the boss point and the points held, cut down")
	local many = {}
	for i = 1, 20 do many[i] = {key = "k" .. i, name = "B" .. i, level = i, left = 1, ok = true} end
	eq(#H.pocketAnswer({bosses = many}).bosses, H.POCKET_ROWS, "pocket answer: at most the rows a text line holds")
	local pin = H.pocketAnswer({inside = true, run = {id = 3, key = "world_1", name = "Kaelgor", state = "running", boss = "alive", left = 500, players = 1,
		testers = 1, bossHp = 70, bossPos = {x = 5, y = 5, z = 7, junk = 1}, inArena = true, tester = true, junk = 1}, guide = {mode = "fight", goal = {x = 5, y = 5, z = 7}, area = "boss"}})
	check(pin.run.bossHp == 70 and pin.run.testers == 1 and pin.run.bossPos.junk == nil and pin.run.junk == nil and pin.guide.mode == "fight", "pocket answer: the run and the guide")
	-- O662: the exact health, for the bots' damage meter
	local pdm = H.pocketAnswer({inside = true, run = {id = 3, key = "world_1", state = "running", boss = "alive", bossHp = 99, bossMax = 16000000, bossNow = 15840000}})
	check(pdm.run.bossMax == 16000000 and pdm.run.bossNow == 15840000, "pocket answer: the boss's health and its maximum")
	local realPB = ChaosPocketBoss
	local pclose, ppath = 0, nil
	ChaosPocketBoss = {probe = function(p)
		if p.inPocket then
			return {inside = true, level = 400, pos = p:getPosition(), run = {key = "world_1", state = "running", boss = "alive", players = 1, testers = 1},
				guide = {mode = "walk", goal = {x = 70, y = 71, z = 7}, reach = {1, 5}, area = "boss"}}
		end
		return {inside = false, level = 400, pos = p:getPosition(), pz = true, enabled = true, free = 16, reserve = 4,
			bosses = {{key = "world_1", name = "Kaelgor", category = "world", level = 300, left = 3, ok = true}}}
	end, testerClose = function() pclose = pclose + 1 return true end}
	talks["!tester"].onSay(t9, "!tester", "pocket #300")
	check(last(t9):find('"inside":false', 1, true) and last(t9):find('"key":"world_1"', 1, true) and last(t9):find('"seq":300', 1, true), "pocket state: the pockets it may open")
	talks["!tester"].onSay(t9, "!tester", "pocket path #301")
	check(last(t9):find("not inside a pocket", 1, true), "pocket path outside: the reason")
	t9.inPocket = true
	talks["!tester"].onSay(t9, "!tester", "pocket path #302")
	print(last(t9), t9.pathAsked and t9.pathAsked.pos.x)
	check(last(t9):find('"path":[2,2,3]', 1, true) and t9.pathAsked.pos.x == 70 and t9.pathAsked.maxD == 5, "pocket path: on foot to the boss, within reach")
	talks["!tester"].onSay(t9, "!tester", "pocket close #303")
	check(pclose == 1 and last(t9):find('"closed":true', 1, true), "pocket close: the bot's own Leave")
	t9.inPocket = nil
	ChaosPocketBoss = nil
	talks["!tester"].onSay(t9, "!tester", "pocket #304")
	check(last(t9):find("no pocket boss system", 1, true), "pocket: no system, the reason")
	ChaosPocketBoss = realPB
	-- dungeons: the unlock and the weekly challenge
	local pu = H.parseDungeon("unlock 4 3")
	check(type(pu) == "table" and pu.what == "unlock" and pu.id == 4 and pu.difficulty == 3, "dungeon: unlock ID N")
	eq(H.parseDungeon("weekly"), "weekly", "dungeon: weekly")
	w, usage = H.parseDungeon("unlock 4")
	check(w == nil and usage:find("unlock ID N", 1, true), "dungeon: unlock needs both numbers")
	w = H.parseDungeon("close 4")
	eq(w, nil, "dungeon: close takes no number")
	local da = H.dungeonAnswer({inside = true, list = {{id = 10, title = "Weekly Challenge", level = 800, size = 1, max = 1, fixed = 1, weekly = true}},
		run = {id = 1, difficulty = 3, scaled = 2, bossScaled = true, weekly = true, left = 2}})
	check(da.list[1].weekly == true and da.list[1].fixed == 1 and da.run.scaled == 2 and da.run.bossScaled == true and da.run.weekly == true, "dungeon answer: weekly and scaled")
	local realD2, unlocks, weeklyProbe = ChaosDungeons, {}, nil
	ChaosDungeons = {probe = function(p) return {inside = false, level = 900, pos = p:getPosition(), on = true, list = {}} end,
		testerUnlock = function(p, id, d)
			unlocks[#unlocks + 1] = {id, d}
			if id == 99 then return nil, "no such dungeon" end
			return d
		end}
	local realWC = ChaosWeeklyChallenge
	ChaosWeeklyChallenge = {probe = function() return {enabled = true, id = 10, built = "2026-W46", current = true, testersListed = 0, rows = 5} end}
	talks["!tester"].onSay(t9, "!tester", "dungeon unlock 4 3 #310")
	check(#unlocks == 1 and unlocks[1][1] == 4 and unlocks[1][2] == 3 and last(t9):find('"unlocked":3', 1, true), "dungeon unlock: the difficulty is written")
	talks["!tester"].onSay(t9, "!tester", "dungeon unlock 99 3 #311")
	check(last(t9):find("no such dungeon", 1, true), "dungeon unlock: the reason of the refusal")
	talks["!tester"].onSay(t9, "!tester", "dungeon weekly #312")
	check(last(t9):find('"testersListed":0', 1, true) and last(t9):find('"built":"2026-W46"', 1, true) and last(t9):find('"current":true', 1, true), "dungeon weekly: the week and the boards")
	ChaosWeeklyChallenge = nil
	talks["!tester"].onSay(t9, "!tester", "dungeon weekly #313")
	check(last(t9):find("no weekly challenge", 1, true), "dungeon weekly: no system")
	ChaosWeeklyChallenge = realWC
	ChaosDungeons.testerUnlock = nil
	talks["!tester"].onSay(t9, "!tester", "dungeon unlock 4 3 #314")
	check(last(t9):find("no dungeon system", 1, true), "dungeon unlock: an old server has no unlock")
	ChaosDungeons = realD2
	local civU = creature(992, "Ana Unlock", {store = {}})
	local nU = #civU.log.msgs
	check(talks["!tester"].onSay(civU, "!tester", "dungeon unlock 4 6 #1") == true and talks["!tester"].onSay(civU, "!tester", "pocket close #2") == true
		and talks["!tester"].onSay(civU, "!tester", "wsmap enter 1 #3") == true and #civU.log.msgs == nU, "unlock / pocket / wsmap: a player's words go on and get no answer")
	-- the rift answer carries the stairs
	local ra = H.riftAnswer({inside = true, run = {floors = 2, links = 1}, guide = {mode = "use", goal = {x = 1, y = 2, z = 8}, area = "stairs", via = "ladder",
		use = {x = 1, y = 2, z = 8, clientId = 1386, stack = 2, junk = 1}}})
	check(ra.run.floors == 2 and ra.run.links == 1 and ra.guide.via == "ladder" and ra.guide.use.clientId == 1386 and ra.guide.use.stack == 2 and ra.guide.use.junk == nil,
		"rift answer: the floors, the links, the ladder to use")
	-- a waystone map walked
	local ws = H.parseWsMap("enter 11")
	check(ws and ws.what == "enter" and ws.tier == 11, "wsmap: enter a tier")
	eq(H.parseWsMap("enter").tier, nil, "wsmap: enter without a tier")
	eq(H.parseWsMap(nil).what, "state", "wsmap: no word is state")
	w = H.parseWsMap("enter 25")
	check(w and w.tier == 25, "wsmap: the deep band's tiers 16 to 25 open for a tester (O671)")
	w, usage = H.parseWsMap("enter 26")
	check(w == nil and usage:find("usage: wsmap", 1, true), "wsmap: a tier above 25")
	w = H.parseWsMap("state 3")
	eq(w, nil, "wsmap: state takes no number")
	local wa = H.wsmapAnswer({inside = true, level = 1500, pos = {x = 1, y = 2, z = 7, junk = 1}, minLevel = 1000, kills = 3, arrivals = 4, free = true, freeTier = 6,
		freeTierLevel = 1600, run = {map = 9, tier = 11, tierLevel = 2100, since = 5, left = 590, players = 0, monsters = 12, monsterLevel = 2100, nearest = {x = 3, y = 4, z = 7, junk = 1},
		nearestHp = 90, boss = {pos = {x = 9, y = 9, z = 7}, hp = 100}, junk = 1}, guide = {mode = "walk", goal = {x = 3, y = 4, z = 7}, reach = {1, 5}, area = "pack"}})
	check(wa.inside and wa.freeTier == 6 and wa.run.tierLevel == 2100 and wa.run.monsterLevel == 2100 and wa.run.nearest.junk == nil and wa.run.junk == nil
		and wa.run.boss.hp == 100 and wa.guide.mode == "walk", "wsmap answer: the run, the level of the monsters, the guide")
	local realWT, entered, wclose = ChaosWaystoneTiers, nil, 0
	ChaosWaystoneTiers = {probe = function(p)
		if p.inMap then
			return {inside = true, level = 1500, pos = p:getPosition(), run = {map = 9, tier = 11, tierLevel = 2100, monsters = 3},
				guide = {mode = "walk", goal = {x = 90, y = 91, z = 7}, reach = {1, 5}, area = "pack"}}
		end
		return {inside = false, level = 1500, pos = p:getPosition(), minLevel = 1000, arrivals = 1, free = true, freeTier = 1, freeTierLevel = 1100}
	end, testerEnter = function(p, tier)
		if tier == 15 then return nil, "no map of the band has an arrival tile (config arrivals)" end
		entered = tier or 1
		return {map = 9, tier = tier or 1}
	end, testerClose = function() wclose = wclose + 1 return true end}
	talks["!tester"].onSay(t9, "!tester", "wsmap #320")
	check(last(t9):find('"freeTier":1', 1, true) and last(t9):find('"seq":320', 1, true), "wsmap state: a map is free")
	talks["!tester"].onSay(t9, "!tester", "wsmap enter 11 #321")
	check(entered == 11 and last(t9):find('"entered":true', 1, true) and last(t9):find('"map":9', 1, true), "wsmap enter: the stand-in of the pads")
	talks["!tester"].onSay(t9, "!tester", "wsmap enter 15 #322")
	check(last(t9):find("arrival tile", 1, true), "wsmap enter: the reason of the refusal")
	talks["!tester"].onSay(t9, "!tester", "wsmap path #323")
	check(last(t9):find("not inside a waystone map", 1, true), "wsmap path outside: the reason")
	t9.inMap = true
	talks["!tester"].onSay(t9, "!tester", "wsmap path #324")
	check(last(t9):find('"path":[2,2,3]', 1, true) and t9.pathAsked.pos.x == 90 and t9.pathAsked.maxD == 5, "wsmap path: on foot to the monster")
	talks["!tester"].onSay(t9, "!tester", "wsmap close #325")
	check(wclose == 1 and last(t9):find('"closed":true', 1, true), "wsmap close: the bot's own way out")
	t9.inMap = nil
	ChaosWaystoneTiers = nil
	talks["!tester"].onSay(t9, "!tester", "wsmap #326")
	check(last(t9):find("no waystone system", 1, true), "wsmap: no system")
	ChaosWaystoneTiers = realWT
	ChaosTowerRun, ChaosDescent = realTR, realD
	local civ4 = creature(993, "Ana Tower", {store = {}})
	local n4 = #civ4.log.msgs
	check(talks["!tester"].onSay(civ4, "!tester", "tower close #1") == true and talks["!tester"].onSay(civ4, "!tester", "descent sigil #2") == true
		and #civ4.log.msgs == n4, "tower / descent: a player's words go on and get no answer")
end

-- ------------------------------------------------------------------ O653: `!tester found` (what the bot's own drops can do)
do
	local H = ChaosTesterHelperCore
	check(H.COMMANDS.found and H.parseCommand("found #1") == "found", "found is a registered command")
	eq(H.parseFound(nil), "state", "found: no word is state")
	eq(H.parseFound("state"), "state", "found: state")
	check(H.parseFound("give") == nil and select(2, H.parseFound("give")) == "usage: found", "found: it takes no grant word")
	-- the chase score knows sets, uniques and jewelry
	local worn = {[1] = {score = 30}, [2] = {score = 0}, [8] = {score = 40, set = "ashen"}}
	local state = {sets = {ashen = 2, other = 0}, size = {ashen = 4, other = 4, full = 2}}
	eq(H.chaseScore({slot = 1, score = 50}, worn, state), 20, "chase: the plain gain only")
	eq(H.chaseScore({slot = 1, score = 50, set = "ashen"}, worn, state), 20 + H.CHASE_SET * 2, "chase: a set piece joins the 2 worn pieces of its set")
	eq(H.chaseScore({slot = 1, score = 50, set = "other"}, worn, state), 20 + H.CHASE_SET_NEW, "chase: the first piece of a set")
	eq(H.chaseScore({slot = 8, score = 45, set = "ashen"}, worn, state), 5 + H.CHASE_SET, "chase: a piece of the same set as the worn one adds no piece")
	eq(H.chaseScore({slot = 1, score = 50, set = "full"}, worn, {sets = {full = 2}, size = {full = 2}}), 20, "chase: a full set adds nothing")
	eq(H.chaseScore({slot = 1, score = 50, unique = true}, worn, state), 20 + H.CHASE_UNIQUE, "chase: a unique")
	eq(H.chaseScore({slot = 1, score = 50, unique = true}, {[1] = {score = 30, unique = true}}, state), 20, "chase: no bonus over a unique already worn")
	eq(H.chaseScore({slot = 2, score = 5, jewelry = true}, worn, state), 5 + H.CHASE_JEWELRY, "chase: a jewel for an empty slot")
	eq(H.chaseScore({slot = 2, score = 5, jewelry = true}, {[2] = {score = 4}}, state), 1, "chase: a jewel for a worn slot is a plain gain")
	-- the report: drops, pieces, the best one
	local rows = {
		{i = 0, id = 7618, cid = 1, n = 90},
		{i = 1, id = 24691, cid = 2, n = 3, orb = "alchemy"},
		{i = 2, id = 24692, cid = 3, n = 2, orb = "alchemy"},
		{i = 3, id = 32006, cid = 4, n = 1, gem = true},
		{i = 4, id = 33001, cid = 5, n = 1, rune = true},
		{i = 5, id = 3001, cid = 6, n = 1, slot = 1, score = 40},
		{i = 6, id = 3002, cid = 7, n = 1, slot = 1, score = 50, set = "ashen"},
		{i = 7, id = 3003, cid = 8, n = 1, slot = 2, score = 6, jewelry = true},
	}
	local rep = H.foundReport(rows, worn, state)
	eq(rep.orbs.alchemy, 5, "found: the orbs by key, stacks added")
	eq(#rep.drops, 4, "found: two orb rows, a gem and a rune are drops")
	check(rep.drops[3].k == "gem" and rep.drops[4].k == "rune" and rep.drops[1].key == "alchemy", "found: the kinds of the drops")
	eq(#rep.pieces, 3, "found: three wearable pieces (a potion is none)")
	eq(rep.best, 6, "found: the piece of a set with 2 worn pieces wins (100 over the jewel 56 and the plain 10)")
	eq(H.foundReport({rows[8], rows[6]}, worn, state).best, 7, "found: a jewel for the empty slot wins over a plain gain")
	eq(rep.pieces[2].chase, 20 + H.CHASE_SET * 2, "found: the set piece is scored with its set")
	eq(rep.pieces[2].set, "ashen", "found: the set key")
	eq(rep.sets.ashen, 2, "found: the sets worn")
	eq(#rep.worn, 3, "found: the worn slots")
	eq(H.foundReport({{i = 0, id = 3001, cid = 6, n = 1, slot = 1, score = 20}}, worn, state).best, nil, "found: nothing beats the worn piece")
	local many = {}
	for i = 1, 40 do
		many[i] = {i = i, id = 1000 + i, cid = i, n = 1, orb = "chaos"}
	end
	eq(#H.foundReport(many, {}, {}).drops, H.FOUND_MAX, "found: the lists are bounded")

	-- the command on a mock backpack: nothing is given or moved
	T.present = function() return true end
	local saved = ItemType
	local types = {[3001] = {slot = 1, armor = 4, def = 0, atk = 0}, [3002] = {slot = 1, armor = 5, def = 0, atk = 0}, [24691] = {slot = 0, armor = 0, def = 0, atk = 0},
		[32006] = {slot = 0, armor = 0, def = 0, atk = 0}}
	function ItemType(id)
		local t = types[id] or {slot = 0, armor = 0, def = 0, atk = 0}
		return {getClientId = function() return id + 10000 end, getName = function() return "item " .. id end,
			isStackable = function() return false end, getSlotPosition = function() return t.slot end,
			getArmor = function() return t.armor end, getDefense = function() return t.def end, getAttack = function() return t.atk end}
	end
	local function it(id, n, uniq)
		return {getId = function() return id end, getCount = function() return n or 1 end, isContainer = function() return false end,
			getCustomAttribute = function(_, k) if k == "chaos_unique" and uniq then return 1 end return nil end}
	end
	local items = {[0] = it(24691, 4), [1] = it(32006, 1), [2] = it(3001), [3] = it(3002, 1, true)}
	local realC, realG, realS, realSets = ChaosCrafting, ChaosGems, ChaosSupports, ChaosItemSets
	ChaosCrafting = {orbByKey = {alchemy = {id = 24691}}}
	ChaosGems = {isGem = function(id) return id == 32006 end}
	ChaosSupports = {isRune = function() return false end}
	ChaosItemSets = {pieceOf = function(item) if item:getId() == 3002 then return {key = "ashen"} end return nil end,
		stateOf = function() return {sets = {ashen = {count = 1}}} end, sets = {ashen = {key = "ashen", pieces = {1, 2, 3, 4}}}}
	local fb = creature(268435495, "Tester Fnd", {store = {[ST] = 1}})
	local gave = 0
	fb.slots = {[CONST_SLOT_HEAD] = it(3001), [CONST_SLOT_BACKPACK] = {
		getSize = function() return 4 end, getItem = function(_, i) return items[i] end, getCapacity = function() return 20 end, getId = function() return 1988 end,
		addItem = function() gave = gave + 1 end}}
	function fb:getLevel() return 300 end
	fb.addItemEx = function() gave = gave + 1 end
	check(talks["!tester"].onSay(fb, "!tester", "found #7") == false, "found: consumed")
	local line = fb.log.msgs[#fb.log.msgs]
	check(line:find("[tester-helper] found ", 1, true) ~= nil and line:find('"seq":7', 1, true) ~= nil, "found: the numbered answer line: " .. tostring(line))
	check(line:find('"alchemy":4', 1, true) ~= nil, "found: the orb stack by key: " .. tostring(line))
	check(line:find('"k":"gem"', 1, true) ~= nil and line:find('"k":"orb"', 1, true) ~= nil, "found: the gem and the orb are drops")
	check(line:find('"set":"ashen"', 1, true) ~= nil and line:find('"unique":true', 1, true) ~= nil, "found: the set and unique facts of the piece")
	check(line:find('"best":3', 1, true) ~= nil, "found: the unique set piece of armour 5 is the best: " .. tostring(line))
	check(line:find('"bagClientId":11988', 1, true) ~= nil and line:find('"level":300', 1, true) ~= nil, "found: the backpack id and the level")
	check(line:find('"bagOpen":false', 1, true) ~= nil, "found: a backpack that is no open container 0 says so (O662): " .. tostring(line))
	local bagOf = fb.slots[CONST_SLOT_BACKPACK]
	function fb:getContainerById(id) return id == 0 and bagOf or nil end
	talks["!tester"].onSay(fb, "!tester", "found #8")
	check(fb.log.msgs[#fb.log.msgs]:find('"bagOpen":true', 1, true) ~= nil, "found: the open backpack says so (O662)")
	fb.getContainerById = nil
	eq(gave, 0, "found: nothing is given")
	check(talks["!tester"].onSay(fb, "!tester", "found give #8") == false and fb.log.msgs[#fb.log.msgs]:find("usage: found", 1, true) ~= nil, "found: a grant word is the usage")
	fb.slots[CONST_SLOT_BACKPACK] = nil
	talks["!tester"].onSay(fb, "!tester", "found #9")
	check(fb.log.msgs[#fb.log.msgs]:find("no backpack", 1, true) ~= nil, "found: no backpack, the reason")
	local civ6 = creature(268435496, "Ana Found", {store = {}})
	local n6 = #civ6.log.msgs
	check(talks["!tester"].onSay(civ6, "!tester", "found #1") == true and #civ6.log.msgs == n6, "found: a player's words go on and get no answer")
	ItemType = saved
	ChaosCrafting, ChaosGems, ChaosSupports, ChaosItemSets = realC, realG, realS, realSets
end

-- ------------------------------------------------------------------ O654: the levelling journey on foot (`!tester journey`)
do
	check(H.COMMANDS.journey and H.parseCommand("journey state keep a #1") == "journey", "journey is a registered command")
	-- the parser
	local o = H.parseJourney(nil)
	check(o and o.what == "state" and o.keep == nil and next(o.skip) == nil, "journey: no word is state")
	o = H.parseJourney("JUMP")
	eq(o.what, "jump", "journey: jump (any case)")
	eq(H.parseJourney("hall").what, "hall", "journey: hall")
	o = H.parseJourney("state keep camp_1 skip a-b,c.d")
	check(o.keep == "camp_1" and o.skip["a-b"] and o.skip["c.d"], "journey: keep and skip")
	local bad, usage = H.parseJourney("teleport")
	check(bad == nil and usage == "usage: journey [state | jump | hall] [keep ID] [skip ID,ID] [near X Y Z]", "journey: an unknown word is the usage")
	check(H.parseJourney("keep") == nil and H.parseJourney("skip") == nil, "journey: keep and skip need an id")
	check(H.parseJourney("keep a;b") == nil and H.parseJourney("keep " .. ("x"):rep(49)) == nil, "journey: an id is plain and short")
	local many = {}
	for i = 1, 25 do many[i] = "h" .. i end
	check(H.parseJourney("skip " .. table.concat(many, ",")) == nil, "journey: at most 24 skipped hunts")
	-- the pick: the window of the progression model, widened until one hunt fits
	local function port(id, lo, hi, z)
		return {i = id, n = id, l = {lo, hi}, t = {x = 100 + lo, y = 50, z = z or 7}, f = {x = 100 + lo, y = 51, z = z or 7},
			a = {x = 5000 + lo, y = 60, z = 7}, b = {x = 5000 + lo, y = 61, z = 7}}
	end
	local ports = {port("rats", 1, 20), port("cave", 15, 40), port("bog", 40, 90), port("keep", 60, 120), port("ruin", 90, 200),
		port("deep", 300, 500, 6)}
	eq(H.journeyMid(ports[1]), 10.5, "journeyMid: the middle of the band")
	eq(H.journeyMid({l = {50, 0}}), 50, "journeyMid: no top is the bottom")
	eq(H.journeyMid({}), nil, "journeyMid: no band")
	local pk = H.journeyPick(ports, 100, {})
	eq(pk.id, "keep", "pick: level 100 takes the hunt whose middle (90) is inside the window 80-110")
	pk = H.journeyPick(ports, 8, {})
	check(pk and pk.id == "rats" and pk.widen > 0, "pick: level 8 widens the window until the first hunt fits (and may enter)")
	pk = H.journeyPick(ports, 70, {})
	eq(pk.id, "bog", "pick: level 70: bog (middle 65) is the one inside the window 56-77")
	-- O661: near X Y Z: the hunt whose arrival is nearest to a place among the ones the level may enter
	local nearOpts = H.parseJourney("state near 5090 60 7")
	check(nearOpts and nearOpts.near and nearOpts.near.x == 5090 and nearOpts.near.y == 60 and nearOpts.near.z == 7, "journey: near X Y Z")
	check(H.parseJourney("near 1 2") == nil and H.parseJourney("near 1 2 x") == nil and H.parseJourney("near 1 2 3 4") == nil, "journey: near needs three numbers")
	check(H.parseJourney("near 1 2 99999") == nil, "journey: near numbers are map numbers")
	pk = H.journeyPick(ports, 100, {near = {x = 5090, y = 60, z = 7}})
	check(pk and pk.id == "ruin" and pk.stay == true and pk.d == 0 and pk.a.x == 5090, "near: level 100 takes the hunt whose arrival is at the place (ruin, 90)")
	pk = H.journeyPick(ports, 30, {near = {x = 5090, y = 60, z = 7}})
	check(pk and pk.id == "cave", "near: ruin needs level 90, level 30 takes the nearest hunt it may enter (cave, 15)")
	pk = H.journeyPick(ports, 1000, {near = {x = 5300, y = 60, z = 6}})
	check(pk and pk.id == "deep" and pk.d == 1000, "near: an arrival on another floor counts 1000 tiles more (the place is x 5300 on floor 6, the arrivals are on floor 7)")
	check(H.journeyNear({}, 100, {x = 1, y = 1, z = 7}) == nil and H.journeyNear(ports, 100, nil) == nil, "near: no hunt, no place")
	pk = H.journeyPick(ports, 100, {near = {x = 1, y = 1, z = 7}, keep = "keep"})
	check(pk and pk.id == "rats", "near: the place wins over keep (a bounty walk goes to its hunt)")
	local answer = H.journeyAnswer({level = 100, zone = "temple", pick = H.journeyNear(ports, 100, {x = 5090, y = 60, z = 7})})
	check(answer.pick.id == "ruin" and answer.pick.d == 0 and answer.pick.a.x == 5090, "journey answer: the pick carries d and the arrival")
	-- O661: the pockets of a level the boss is not above come first
	local pb = H.pocketAnswer({level = 700, bosses = {
		{key = "raid_ul", name = "Ul'thazmor", category = "raid", level = 150, bl = 2400, left = 1, ok = true, point = {id = 10, got = false}},
		{key = "raid_lo", name = "Lowbie", category = "raid", level = 150, bl = 300, left = 1, ok = true, point = {id = 3, got = true}},
		{key = "raid_mid", name = "Middling", category = "raid", level = 150, bl = 650, left = 1, ok = true, point = {id = 4, got = true}}}})
	check(pb.bosses[1].key == "raid_mid" and pb.bosses[2].key == "raid_lo" and pb.bosses[3].key == "raid_ul" and pb.bosses[1].bl == 650,
		"pocket answer: a boss at or under the bot's level first, the highest of them; a point it lacks does not outweigh a boss above it")
	-- the hunt it is at stays while it fits (never a hop between two equal hunts)
	pk = H.journeyPick(ports, 70, {keep = "bog"})
	check(pk.id == "bog" and pk.stay == true, "pick: keep: the hunt it is at stays while it fits")
	pk = H.journeyPick(ports, 130, {keep = "bog"})
	check(pk.id ~= "bog" and not pk.stay, "pick: keep: a hunt the level outgrew is left (middle 65 against level 130)")
	eq(H.journeyPick(ports, 130, {keep = "nope"}).id, "ruin", "pick: an unknown keep is ignored")
	-- skip: a hunt that hurt the bot is not picked again (and when every hunt is skipped the skip is dropped)
	pk = H.journeyPick(ports, 70, {skip = {bog = true}})
	check(pk.id ~= "bog", "pick: skip leaves the hunt that hurt it")
	local allSkip = {}
	for _, e in ipairs(ports) do allSkip[e.i] = true end
	check(H.journeyPick(ports, 70, {skip = allSkip}) ~= nil, "pick: every hunt skipped: the skip is dropped, not the bot stranded")
	-- a level under every band cannot go in; a level over every band goes to the highest it may enter
	pk = H.journeyPick({port("high", 300, 400)}, 50, {})
	check(pk.above == true and pk.id == "high", "pick: every hunt needs more than the level: above")
	pk = H.journeyPick(ports, 5000, {})
	check(pk and pk.id == "deep" and not pk.above, "pick: far above every band: the highest it may enter")
	eq(H.journeyPick({}, 10, {}), nil, "pick: no hunts")
	eq(H.journeyPick(nil, 10, {}), nil, "pick: no list")
	-- the seed turns the choice among the best three so the bots do not share one hunt
	local crowd = {port("a", 80, 100), port("b", 82, 100), port("c", 84, 100), port("d", 86, 100)}
	local seen = {}
	for seed = 0, 8 do seen[H.journeyPick(crowd, 95, {seed = seed}).id] = true end
	local n = 0
	for _ in pairs(seen) do n = n + 1 end
	eq(n, 3, "pick: three hunts share the bots")
	-- zones
	eq(H.journeyZone({x = 31650, y = 32240, z = 7}, {x = 50, y = 50, z = 7}), "hall", "zone: the teleport room")
	eq(H.journeyZone({x = 60, y = 55, z = 7}, {x = 50, y = 50, z = 7}), "temple", "zone: round the temple")
	eq(H.journeyZone({x = 60, y = 55, z = 6}, {x = 50, y = 50, z = 7}), "other", "zone: another floor of the temple's tiles is not the temple")
	eq(H.journeyZone({x = 5000, y = 60, z = 7}, {x = 50, y = 50, z = 7}), "other", "zone: a hunt")
	check(H.journeyInHall({x = 31648, y = 32256, z = 6}) and not H.journeyInHall({x = 31648, y = 32256, z = 8}), "hall: floors 5 to 7")
	-- finding things on a grid
	local grid = {["50,45,7"] = {dest = {x = 31648, y = 32233, z = 7}}, ["53,50,7"] = {dest = {x = 1, y = 1, z = 7}},
		["52,49,7"] = {change = "up"}, ["46,50,7"] = {change = "down"}, ["51,50,7"] = {aid = H.PORTAL_AID}}
	local function at(x, y, z) return grid[x .. "," .. y .. "," .. z] end
	local home = {x = 50, y = 50, z = 7}
	local g = H.journeyFind(at, home, 14, H.journeyIsGate)
	check(g and g.x == 50 and g.y == 45, "find: the gate is the teleport that leads to the hub, not the other one")
	eq(H.journeyFind(at, home, 3, H.journeyIsGate), nil, "find: out of reach")
	local up = H.journeyFind(at, home, 14, function(i) return H.journeyIsStairs(i, "up") end)
	local dn = H.journeyFind(at, home, 14, function(i) return H.journeyIsStairs(i, "down") end)
	check(up and up.x == 52 and dn and dn.x == 46, "find: stairs up and down apart")
	local pt = H.journeyFind(at, home, 4, H.journeyIsPortal)
	check(pt and pt.x == 51, "find: the town portal by its action id")
	check(not H.journeyIsGate({dest = {x = 31648, y = 32233, z = 6}}) and H.journeyIsGate({dest = {x = 31650, y = 32235, z = 7}}), "gate: the hub's floor and within 6 tiles")
	-- the answer
	local ans = H.journeyAnswer({level = 30, zone = "temple", pz = true, pos = {x = 1, y = 2, z = 7, junk = 1}, gate = {x = 5, y = 6, z = 7},
		locker = {x = 7, y = 8, z = 7, cid = 2589, sp = 1, spot = {x = 7, y = 9, z = 7}}, stairs = {up = {x = 1, y = 1, z = 7}},
		pick = {id = "cave", n = ("N"):rep(80), lo = 15, hi = 40, t = {x = 1, y = 2, z = 7}, f = {x = 1, y = 3, z = 7}, a = {x = 9, y = 9, z = 7}, widen = 0}},
		{jumped = "hunt"})
	check(ans.zone == "temple" and ans.pz == true and ans.pos.junk == nil and ans.gate.x == 5 and ans.locker.cid == 2589 and ans.locker.spot.y == 9
		and ans.stairs.up.x == 1 and ans.stairs.down == nil and ans.pick.id == "cave" and #ans.pick.n == 40 and ans.pick.z == 7 and ans.jumped == "hunt",
		"answer: the places as x y z, the name cut, the extras merged")
	-- the engine file against a fake map
	local savedTile, savedPorts = Tile, ChaosHuntTeleports
	local saved = {ITEM_TYPE_TELEPORT, TILESTATE_PROTECTIONZONE, TILESTATE_FLOORCHANGE_DOWN, ChaosPoi}
	ITEM_TYPE_TELEPORT, TILESTATE_PROTECTIONZONE, TILESTATE_FLOORCHANGE_DOWN = 21, 8, 16
	local fgrid = {}
	local function key(p) return p.x .. "," .. p.y .. "," .. p.z end
	local function fakeTile(p)
		local f = fgrid[key(p)] or {}
		local t = {pos = p}
		function t:getGround() return true end
		function t:hasFlag(flag)
			if flag == TILESTATE_FLOORCHANGE then return f.change ~= nil end
			if flag == TILESTATE_FLOORCHANGE_DOWN then return f.change == "down" end
			if flag == TILESTATE_PROTECTIONZONE then return f.pz == true end
			if flag == TILESTATE_TELEPORT then return f.dest ~= nil end
			return false
		end
		function t:getTopCreature() return nil end
		function t:getPosition() return p end
		function t:getItemByType(kind)
			if kind == ITEM_TYPE_TELEPORT and f.dest then
				return {getDestination = function() return f.dest end}
			end
		end
		function t:getItems()
			return f.aid and {{getActionId = function() return f.aid end}} or {}
		end
		function t:getItemById(id)
			if f.locker == id then return {} end
		end
		function t:getThingIndex() return 2 end
		return t
	end
	Tile = function(p) return p and p.x and fakeTile(p) or nil end
	fgrid["50,45,7"] = {dest = {x = 31648, y = 32233, z = 7}}
	fgrid["53,52,7"] = {locker = 2589}
	fgrid["52,50,7"] = {pz = true}
	ChaosHuntTeleports = {ports = function() return ports end}
	local realMhl2, realSpectators = Chaos.monsterHuntingLevel, Game.getSpectators
	Game.getSpectators = function() return {wolf, pet} end
	Chaos.monsterHuntingLevel = function() return 5 end
	local jt = creature(268435470, "Tester Jny", {store = {[ST] = 1}, pos = {x = 52, y = 50, z = 7}})
	talks["!tester"].onSay(jt, "!tester", "journey #300")
	local m = last(jt)
	check(m:find('"zone":"temple"', 1, true) and m:find('"id":"keep"', 1, true) and m:find('"seq":300', 1, true) and m:find('"pz":true', 1, true),
		"journey state at the temple: the zone, the hunt for level 100, the protection zone")
	check(m:find('"gate":{"x":50,"y":45,"z":7}', 1, true), "journey state: the temple's great teleport")
	check(m:find('"locker":', 1, true) and m:find('"cid":12589', 1, true), "journey state: the depot locker next to the temple")
	check(#jt.log.teleports == 0, "journey state moves nobody")
	talks["!tester"].onSay(jt, "!tester", "journey keep bog #301")
	check(last(jt):find('"id":"keep"', 1, true) and not last(jt):find('"stay":true', 1, true), "journey keep: a hunt that no longer fits (bog, 65) is left")
	talks["!tester"].onSay(jt, "!tester", "journey keep keep skip keep #302")
	check(last(jt):find('"id":"bog"', 1, true) and not last(jt):find('"stay":true', 1, true), "journey skip: the skipped hunt is not kept, the window widens to the next (bog)")
	talks["!tester"].onSay(jt, "!tester", "journey keep keep #303")
	check(last(jt):find('"stay":true', 1, true) and last(jt):find('"id":"keep"', 1, true), "journey keep: stays at a hunt that fits")
	-- the fallback teleports
	talks["!tester"].onSay(jt, "!tester", "journey jump #304")
	check(#jt.log.teleports == 1 and jt.pos.x >= 5000 and last(jt):find('"jumped":"jump"', 1, true), "journey jump: the hunt's arrival, counted in the answer")
	jt.pos = {x = 52, y = 50, z = 7}
	fgrid["31660,32250,7"] = {change = "up"}
	talks["!tester"].onSay(jt, "!tester", "journey hall #305")
	check(jt.pos.x >= 31645 and jt.pos.x <= 31651 and last(jt):find('"jumped":"hall"', 1, true) and last(jt):find('"zone":"hall"', 1, true),
		"journey hall: next to the gate's arrival in the teleport room")
	-- in the hall: the stairs of the floor
	talks["!tester"].onSay(jt, "!tester", "journey #306")
	check(last(jt):find('"stairs":{"up":{"x":31660', 1, true), "journey state in the hall: the stairs up")
	-- a town portal beside the bot
	jt.pos = {x = 5000, y = 60, z = 7}
	fgrid["5001,60,7"] = {aid = H.PORTAL_AID}
	talks["!tester"].onSay(jt, "!tester", "journey #307")
	check(last(jt):find('"zone":"other"', 1, true) and last(jt):find('"portal":{"x":5001', 1, true), "journey state at a hunt: the town portal beside the bot")
	wolf.pos = {x = 5003, y = 60, z = 7}
	talks["!tester"].onSay(jt, "!tester", "journey #310")
	check(last(jt):find('"monster":{"dist":3,"level":5,"name":"wolf"', 1, true) and last(jt):find('"crowd":1', 1, true) and not last(jt):find('"hot"', 1, true),
		"journey state at a hunt: the nearest monster, how many are round, nothing too high")
	Chaos.monsterHuntingLevel = function() return 900 end
	talks["!tester"].onSay(jt, "!tester", "journey #311")
	check(last(jt):find('"hot":{"l":900,"n":"wolf"}', 1, true), "journey state at a hunt: a monster far above the level is `hot`")
	Chaos.monsterHuntingLevel = realMhl2
	wolf.pos = {x = 102, y = 100, z = 7}
	talks["!tester"].onSay(jt, "!tester", "journey fly #308")
	check(last(jt):find("usage: journey", 1, true), "journey: an unknown word")
	local noArrival = port("base", 85, 105)
	noArrival.a = nil
	ChaosHuntTeleports = {ports = function() return {noArrival} end}
	jt.pos = {x = 52, y = 50, z = 7}
	local before = #jt.log.teleports
	talks["!tester"].onSay(jt, "!tester", "journey jump #312")
	check(last(jt):find("has no known arrival", 1, true) and #jt.log.teleports == before, "journey jump: a base hunt has no arrival to put the bot at, the reason")
	ChaosHuntTeleports = nil
	jt.pos = {x = 52, y = 50, z = 7}
	talks["!tester"].onSay(jt, "!tester", "journey jump #309")
	check(last(jt):find("no hunt the level may enter", 1, true), "journey jump: no teleport room, the reason")
	-- a player's words go on and get no answer
	local civ6 = creature(995, "Ana Journey", {store = {}})
	local n6 = #civ6.log.msgs
	check(talks["!tester"].onSay(civ6, "!tester", "journey jump #3") == true and #civ6.log.msgs == n6 and #civ6.log.teleports == 0,
		"journey: a player's words go on and get no answer, nobody is moved")
	Tile, ChaosHuntTeleports = savedTile, savedPorts
	Chaos.monsterHuntingLevel, Game.getSpectators = realMhl2, realSpectators
	ITEM_TYPE_TELEPORT, TILESTATE_PROTECTIONZONE, TILESTATE_FLOORCHANGE_DOWN, ChaosPoi = saved[1], saved[2], saved[3], saved[4]
end

-- ------------------------------------------------------------------ O655: `!tester ascend` and `!tester gather`
do
	local H = ChaosTesterHelperCore
	for _, c in ipairs({"ascend", "gather"}) do
		check(H.COMMANDS[c] and H.parseCommand(c .. " state #1") == c, c .. " is a registered command")
	end
	eq(H.parseAscend(nil), "state", "ascend: no word is state")
	eq(H.parseAscend("PROOF"), "proof", "ascend: proof (any case)")
	eq(H.parseAscend("close"), "close", "ascend: close")
	check(H.parseAscend("win") == nil and select(2, H.parseAscend("win")) == "usage: ascend [state | proof | path | close]", "ascend: the usage")
	check(H.parseAscend("proof now") == nil, "ascend: a word takes no argument")
	eq(H.parseGather("path"), "path", "gather: path")
	check(H.parseGather("sell") == nil and select(2, H.parseGather("sell")) == "usage: gather [state | path | corpse | water]", "gather: the usage")
	local realAQ, realPF = ChaosAscensionQuest, ChaosProfessions
	local lastOf = function(p) return p.log.msgs[#p.log.msgs] end
	local t = creature(268435560, "Tester Asc", {store = {[ST] = 1}})
	t.pos = {x = 60, y = 60, z = 7}
	t.getPathTo = function(self, pos, minD, maxD)
		t.pathAsked = {pos = pos, minD = minD, maxD = maxD}
		return {2, 2, 3}
	end
	local credited, closed = 0, 0
	local inside = false
	ChaosAscensionQuest = {probe = function(p)
		local out = {enabled = true, level = 100, minLevel = 100, stage = credited > 0 and 2 or 1, proof = credited > 0 and 10 or 0, needed = 10, eligible = true,
			ascended = false, oracle = true, wait = 0, free = 8, reserve = 2, tester = true, vocName = "Warrior",
			choices = {{i = 1, word = "berserker", id = 14, name = "Berserker", allowed = false, why = "locked", junk = 1}, {i = 2, word = "paladin", id = 15, name = "Paladin Lord", allowed = true}}}
		if inside then
			out.inside = true
			out.run = {state = "fight", boss = "alive", bossHp = 80, adds = 1, players = 1, testers = 1, tester = true, kind = "Warden of Iron"}
			out.guide = {mode = "walk", goal = {x = 90, y = 91, z = 7}, reach = {1, 5}, area = "boss"}
		end
		return out
	end, testerProof = function(p)
		if credited > 0 then return nil, "the Proof of Strength is not open (stage 2)" end
		credited = credited + 1
		return true
	end, testerClose = function() closed = closed + 1 inside = false return true end}
	talks["!tester"].onSay(t, "!tester", "ascend #300")
	local l = lastOf(t)
	check(l:find('"stage":1', 1, true) and l:find('"seq":300', 1, true) and l:find('"vocName":"Warrior"', 1, true) and l:find('"allowed":false', 1, true),
		"ascend state: the stage and the choices with the class lock: " .. l)
	talks["!tester"].onSay(t, "!tester", "ascend proof #301")
	check(credited == 1 and lastOf(t):find('"proofed":true', 1, true) and lastOf(t):find('"stage":2', 1, true), "ascend proof: the credit, then the record")
	talks["!tester"].onSay(t, "!tester", "ascend proof #302")
	check(lastOf(t):find("not open", 1, true) and credited == 1, "ascend proof: the reason of the refusal")
	talks["!tester"].onSay(t, "!tester", "ascend path #303")
	check(lastOf(t):find('"err":"no goal"', 1, true), "ascend path outside the trial: no goal")
	inside = true
	talks["!tester"].onSay(t, "!tester", "ascend path #304")
	check(lastOf(t):find('"path":[2,2,3]', 1, true) and t.pathAsked.pos.x == 90 and t.pathAsked.maxD == 5, "ascend path: on foot to the guardian, within reach")
	check(lastOf(t):find('"bossHp":80', 1, true) and lastOf(t):find('"adds":1', 1, true) and lastOf(t):find('"testers":1', 1, true), "ascend: the guardian, its adds, the run's players")
	talks["!tester"].onSay(t, "!tester", "ascend close #305")
	check(closed == 1 and lastOf(t):find('"closed":true', 1, true) and lastOf(t):find('"inside"', 1, true) == nil, "ascend close: the bot's own trial ends")
	talks["!tester"].onSay(t, "!tester", "ascend kill #306")
	check(lastOf(t):find("usage: ascend", 1, true), "ascend: an unknown word")
	ChaosAscensionQuest = nil
	talks["!tester"].onSay(t, "!tester", "ascend #307")
	check(lastOf(t):find("no ascension quest", 1, true), "ascend: no system, the reason")
	ChaosAscensionQuest = realAQ
	-- gather
	ChaosProfessions = {probe = function(p)
		return {enabled = true, level = 100, minLevel = 20, levelOk = true, tools = {delving = true, wortcunning = false}, held = 2, gathering = false, bank = 900,
			buy = {{id = 2553, clientId = 2553, price = 50}},
			node = {prof = "delving", tier = 2, id = 100, clientId = 4000, pos = {x = 70, y = 71, z = 7}, stackpos = 1, d = 12},
			guide = {mode = "walk", goal = {x = 70, y = 71, z = 7}, reach = {1, 1}, area = "mine", why = "to the nearest delving node"}}
	end}
	talks["!tester"].onSay(t, "!tester", "gather #310")
	l = lastOf(t)
	check(l:find('"clientId":4000', 1, true) and l:find('"stackpos":1', 1, true) and l:find('"delving":true', 1, true) and l:find('"held":2', 1, true) and l:find('"seq":310', 1, true),
		"gather state: the tools, the node's client id and stack position: " .. l)
	talks["!tester"].onSay(t, "!tester", "gather path #311")
	check(lastOf(t):find('"path":[2,2,3]', 1, true) and t.pathAsked.pos.x == 70 and t.pathAsked.minD == 1 and t.pathAsked.maxD == 1, "gather path: on foot next to the node")
	talks["!tester"].onSay(t, "!tester", "gather sell #312")
	check(lastOf(t):find("usage: gather", 1, true), "gather: an unknown word")
	ChaosProfessions = nil
	talks["!tester"].onSay(t, "!tester", "gather #313")
	check(lastOf(t):find("no professions", 1, true), "gather: no system, the reason")
	ChaosProfessions = realPF
	-- a player's words go on and get no answer
	local civ = creature(268435561, "Ana Ascend", {store = {}})
	local n = #civ.log.msgs
	check(talks["!tester"].onSay(civ, "!tester", "ascend proof #1") == true and talks["!tester"].onSay(civ, "!tester", "gather #2") == true and #civ.log.msgs == n,
		"ascend / gather: a player's words go on and get no answer")
	check(HELPER_VERSION >= 20, "the helper is version 20 or later (O655: a new command)")
end

-- ------------------------------------------------------------------ O657: `!tester dummy`, `mount`, `task` and `gather corpse | water`
do
	local H = ChaosTesterHelperCore
	for _, c in ipairs({"dummy", "mount", "task"}) do
		check(H.COMMANDS[c] and H.parseCommand(c .. " state #1") == c, c .. " is a registered command")
	end
	eq(H.parseDummy(nil), "state", "dummy: no word is state"); eq(H.parseDummy("GIVE"), "give", "dummy: give (any case)"); eq(H.parseDummy("clear"), "clear", "dummy: clear")
	check(H.parseDummy("burn") == nil and select(2, H.parseDummy("burn")) == "usage: dummy [state | path | give | clear]", "dummy: the usage")
	eq(H.parseMount("give"), "give", "mount: give"); check(H.parseMount("ride") == nil and select(2, H.parseMount("ride")) == "usage: mount [state | give | clear]", "mount: the usage")
	eq(H.parseTask("path").what, "path", "task: path"); eq(H.parseTask("where Rat").name, "Rat", "task: where NAME")
	check(H.parseTask("where") == nil and select(2, H.parseTask("where")) == "usage: task [state | where NAME | path]", "task: the usage names task")
	eq(H.parseGather("corpse"), "corpse", "gather: corpse"); eq(H.parseGather("water"), "water", "gather: water")
	-- the mount the helper picks: the cheapest free one of the store's list, the lowest id on a tie; a premium one only when there is no other
	eq(H.pickMount({{id = 5, name = "A", cost = 700}, {id = 3, name = "B", cost = 350, premium = true}, {id = 9, name = "C", cost = 550}, {id = 7, name = "D", cost = 550}}).id, 7,
		"pickMount: the cheapest free mount, the lowest id on a tie")
	eq(H.pickMount({{id = 4, name = "P", cost = 350, premium = true}, {id = 2, name = "Q", cost = 350, premium = true}}).id, 2, "pickMount: only premium ones: the lowest id")
	eq(H.pickMount({}), nil, "pickMount: none"); eq(H.pickMount(nil), nil, "pickMount: no list")
	local realMounts = dofile("data/scripts/chaos/shop_cosmetics.lua").mounts
	check(H.pickMount(realMounts) ~= nil, "pickMount: the real store list has a mount")
	local lastOf = function(p) return p.log.msgs[#p.log.msgs] end
	local realEx, realBes, realBounty, realPF = ChaosExercise, ChaosBestiary, ChaosBounty, ChaosProfessions
	local t = creature(268435570, "Tester Dmy", {store = {[ST] = 1}})
	t.pos = {x = 60, y = 60, z = 7}
	t.getPathTo = function(self, pos, minD, maxD)
		t.pathAsked = {pos = pos, minD = minD, maxD = maxD}
		return {1, 1}
	end
	-- the exercise dummy
	local gave, cleared = 0, 0
	ChaosExercise = {probe = function(p)
		return {enabled = true, pz = true, level = 100, pos = t.pos, weapon = gave > 0 and {id = 27733, clientId = 7733, index = 4, charges = 500, kind = "fist", allowed = true} or nil,
			skill = {skill = "fist", level = 30, tries = 12},
			dummy = {id = 27751, clientId = 7751, pos = {x = 64, y = 60, z = 7}, d = 4, stackpos = 2, kind = "bonus"},
			guide = {mode = "walk", goal = {x = 64, y = 60, z = 7}, reach = {1, 1}, why = "to the nearest dummy"}}
	end, testerGive = function(p) gave = gave + 1 return true end, testerClear = function() cleared = cleared + 1 return gave end}
	talks["!tester"].onSay(t, "!tester", "dummy #400")
	local l = lastOf(t)
	check(l:find('"clientId":7751', 1, true) and l:find('"stackpos":2', 1, true) and l:find('"tries":12', 1, true) and l:find('"seq":400', 1, true), "dummy state: the dummy and the skill: " .. l)
	talks["!tester"].onSay(t, "!tester", "dummy give #401")
	l = lastOf(t)
	check(gave == 1 and l:find('"granted":true', 1, true) and l:find('"index":4', 1, true) and l:find('"charges":500', 1, true), "dummy give: the weapon, its slot and charges: " .. l)
	talks["!tester"].onSay(t, "!tester", "dummy path #402")
	check(lastOf(t):find('"path":[1,1]', 1, true) and t.pathAsked.pos.x == 64 and t.pathAsked.minD == 1 and t.pathAsked.maxD == 1, "dummy path: on foot next to the dummy")
	talks["!tester"].onSay(t, "!tester", "dummy clear #403")
	check(cleared == 1 and lastOf(t):find('"cleared":1', 1, true), "dummy clear: the weapon goes")
	talks["!tester"].onSay(t, "!tester", "dummy dance #404")
	check(lastOf(t):find("usage: dummy", 1, true), "dummy: an unknown word")
	ChaosExercise = nil
	talks["!tester"].onSay(t, "!tester", "dummy #405")
	check(lastOf(t):find("no exercise weapons", 1, true), "dummy: no system, the reason")
	ChaosExercise = {probe = function() return {} end, testerGive = function() return nil, "no exercise weapon for this class" end, testerClear = function() return 0 end}
	talks["!tester"].onSay(t, "!tester", "dummy give #406")
	check(lastOf(t):find('"err":"no exercise weapon for this class"', 1, true), "dummy give: the refusal is told")
	ChaosExercise = realEx
	-- the kill task
	local near = false
	ChaosBestiary = {probe = function(p)
		return {level = 100, pos = t.pos, maxActive = 5, target = "h:rat", active = {{key = "h:rat", kind = "hunt", label = "Rat", progress = 2, required = 10, status = 0, monster = "Rat", kills = 4}},
			guide = {mode = "walk", goal = {x = 70, y = 60, z = 7}, reach = {1, 5}, area = "mark", why = "to the hunt of Rat"}}
	end}
	ChaosBounty = {probe = function(p, name)
		return {where = {name = name, marks = 2, distance = 30, nearest = {x = 70, y = 60, z = 7, n = "Hunting: Rat (level 1-8)"}}}
	end}
	talks["!tester"].onSay(t, "!tester", "task #410")
	l = lastOf(t)
	check(l:find('"progress":2', 1, true) and l:find('"monster":"Rat"', 1, true) and l:find('"kills":4', 1, true) and l:find('"seq":410', 1, true), "task state: the task, its monster and the bestiary kills: " .. l)
	talks["!tester"].onSay(t, "!tester", "task where Rat #411")
	l = lastOf(t)
	check(l:find('"marks":2', 1, true) and l:find('"x":70', 1, true), "task where: the hunt marks that list the monster: " .. l)
	talks["!tester"].onSay(t, "!tester", "task path #412")
	check(lastOf(t):find('"path":[1,1]', 1, true) and t.pathAsked.pos.x == 70 and t.pathAsked.maxD == 5, "task path: on foot to the hunt")
	talks["!tester"].onSay(t, "!tester", "task win #413")
	check(lastOf(t):find("usage: task", 1, true), "task: an unknown word")
	ChaosBestiary = nil
	talks["!tester"].onSay(t, "!tester", "task #414")
	check(lastOf(t):find("no bestiary", 1, true), "task: no system, the reason")
	ChaosBestiary, ChaosBounty = realBes, realBounty
	-- gather corpse / water: the guide of the tool
	ChaosProfessions = {probe = function(p)
		return {enabled = true, level = 100, levelOk = true, tools = {flaying = true, angling = true}, held = 0,
			corpse = {tag = 32, tier = 2, pos = {x = 66, y = 60, z = 7}, d = 6, clientId = 2300, stackpos = 1},
			water = {pos = {x = 60, y = 69, z = 7}, d = 9, clientId = 4608, stackpos = 0},
			guide = {mode = "wait", why = "no node"},
			flayGuide = {mode = "walk", goal = {x = 66, y = 60, z = 7}, reach = {0, 1}, why = "to the nearest fresh corpse"},
			angleGuide = {mode = "walk", goal = {x = 60, y = 69, z = 7}, reach = {1, 2}, why = "to the nearest water"}}
	end}
	talks["!tester"].onSay(t, "!tester", "gather corpse #420")
	check(lastOf(t):find('"path":[1,1]', 1, true) and t.pathAsked.pos.x == 66 and t.pathAsked.minD == 0 and t.pathAsked.maxD == 1, "gather corpse: on foot next to the corpse")
	talks["!tester"].onSay(t, "!tester", "gather water #421")
	check(lastOf(t):find('"path":[1,1]', 1, true) and t.pathAsked.pos.y == 69 and t.pathAsked.maxD == 2, "gather water: on foot within two tiles of the water")
	talks["!tester"].onSay(t, "!tester", "gather #422")
	l = lastOf(t)
	check(l:find('"corpse":', 1, true) and l:find('"water":', 1, true) and l:find('"flayGuide":', 1, true) and l:find('"angleGuide":', 1, true), "gather state: the corpse, the water and both guides: " .. l)
	ChaosProfessions = realPF
	-- the mount: a fake player with the engine's mount calls
	local m = creature(268435571, "Tester Mnt", {store = {[ST] = 1}})
	local mounts, current, mounted, speed = {}, nil, false, 220
	m.getOutfit = function() return {lookType = 128, lookMount = mounted and 368 or 0} end
	m.getSpeed = function() return mounted and speed + 20 or speed end
	m.getBaseSpeed = function() return speed end
	-- O660: the engine (TFS 1.4.2) has no Player:getCurrentMount / setCurrentMount / toggleMount in Lua: the current mount is a player storage (10002011)
	m.hasMount = function(_, id) return mounts[id] == true end
	m.addMount = function(_, id) mounts[id] = true return true end
	m.removeMount = function(_, id) mounts[id] = nil return true end
	talks["!tester"].onSay(m, "!tester", "mount #430")
	l = lastOf(m)
	check(l:find('"mounted":false', 1, true) and l:find('"speed":220', 1, true) and l:find('"baseSpeed":220', 1, true) and l:find('"seq":430', 1, true), "mount state: not mounted, the speed: " .. l)
	talks["!tester"].onSay(m, "!tester", "mount give #431")
	l = lastOf(m)
	local pick = H.pickMount(realMounts)
	current = m:getStorageValue(10002011)
	check(mounts[pick.id] == true and current == pick.id and l:find('"current":' .. pick.id, 1, true) and l:find('"granted":' .. pick.id, 1, true), "mount give: the cheapest free mount, owned and current: " .. l)
	mounted = true
	talks["!tester"].onSay(m, "!tester", "mount state #432")
	l = lastOf(m)
	check(l:find('"mounted":true', 1, true) and l:find('"speed":240', 1, true), "mount state: mounted, the speed is higher: " .. l)
	mounted = false -- the bot dismounts with the mount button's packet (0xD4), as a person does; Lua cannot
	talks["!tester"].onSay(m, "!tester", "mount clear #433")
	l = lastOf(m)
	check(mounted == false and next(mounts) == nil and l:find('"cleared":true', 1, true) and l:find('"mounted":false', 1, true), "mount clear: dismounted, the mount taken back: " .. l)
	talks["!tester"].onSay(m, "!tester", "mount clear #434")
	check(lastOf(m):find('"cleared":false', 1, true), "mount clear: nothing was given")
	talks["!tester"].onSay(m, "!tester", "mount ride #435")
	check(lastOf(m):find("usage: mount", 1, true), "mount: an unknown word")
	m.addMount = function() error("no such call") end
	talks["!tester"].onSay(m, "!tester", "mount give #436")
	check(lastOf(m):find("the engine refused the mount", 1, true), "mount give: an engine that cannot says so")
	-- a player's words go on and get no answer
	local civ = creature(268435572, "Ana Mount", {store = {}})
	local n = #civ.log.msgs
	check(talks["!tester"].onSay(civ, "!tester", "mount give #1") == true and talks["!tester"].onSay(civ, "!tester", "dummy give #2") == true
		and talks["!tester"].onSay(civ, "!tester", "task #3") == true and #civ.log.msgs == n, "dummy / mount / task: a player's words go on and get no answer")
	check(HELPER_VERSION >= 24, "the helper is version 24 or later (O657: new commands)")
end

-- ---------------------------------------------------------------- O658: `!tester gold [to N]`
do
	local lastOf = function(p) return p.log.msgs[#p.log.msgs] end
	eq(H.parseGold(nil).to, nil, "gold: no word reads the state")
	eq(H.parseGold("to 5000").to, 5000, "gold: to N")
	eq(H.parseGold("to 99999999999").to, H.GOLD_CAP, "gold: to N is capped")
	check(H.parseGold("to") == nil and H.parseGold("give 5") == nil and H.parseGold("to 0") == nil, "gold: other words are refused")
	eq(H.goldPlan(100, 50, 0), 0, "gold plan: a bank over the wish gets nothing")
	eq(H.goldPlan(100, 1100, 0), 1000, "gold plan: the difference")
	eq(H.goldPlan(0, H.GOLD_CAP, 0), H.GOLD_STEP, "gold plan: one call is at most the step")
	local give, why = H.goldPlan(0, 1000, H.GOLD_CAP)
	check(give == 0 and why and why:find("used up", 1, true), "gold plan: the lifetime limit of a bot")
	eq(H.goldPlan(0, 1000, H.GOLD_CAP - 400), 400, "gold plan: the rest of the allowance")
	local g = creature(268435700, "Tester Gld", {store = {[ST] = 1}})
	local before = #g.log.msgs
	talks["!tester"].onSay(g, "!tester", "gold #500")
	local l = lastOf(g)
	check(l:find('"bank":0', 1, true) and l:find('"total":0', 1, true) and l:find('"seq":500', 1, true) and not l:find('"granted"', 1, true), "gold state: the bank, nothing granted: " .. l)
	talks["!tester"].onSay(g, "!tester", "gold to 250000 #501")
	l = lastOf(g)
	check(g.bank == 250000 and l:find('"granted":250000', 1, true) and l:find('"total":250000', 1, true), "gold to: the bank is topped up and the grant counted: " .. l)
	talks["!tester"].onSay(g, "!tester", "gold to 250000 #502")
	check(g.bank == 250000 and lastOf(g):find('"granted":0', 1, true), "gold to: a bank at the wish gets nothing more")
	talks["!tester"].onSay(g, "!tester", "gold to 99999999 #503")
	check(g.bank == 250000 + H.GOLD_STEP and lastOf(g):find('"granted":' .. H.GOLD_STEP, 1, true), "gold to: one call is at most the step")
	for i = 1, math.ceil(H.GOLD_CAP / H.GOLD_STEP) + 1 do -- O660: the cap is 16M, five steps of 3M and a rest; the calls go on until it is reached
		talks["!tester"].onSay(g, "!tester", "gold to 99999999 #" .. (504 + i))
	end
	l = lastOf(g)
	check(g.bank == H.GOLD_CAP and l:find('"granted":0', 1, true), "gold to: no wish goes past the cap of a bot: " .. l)
	talks["!tester"].onSay(g, "!tester", "gold maybe #506")
	check(lastOf(g):find("usage: gold", 1, true), "gold: an unknown word")
	-- a player's words go on and get no answer, no gold
	local civ = creature(268435701, "Ana Gold", {store = {}})
	local n = #civ.log.msgs
	check(talks["!tester"].onSay(civ, "!tester", "gold to 1000000 #1") == true and #civ.log.msgs == n and (civ.bank or 0) == 0, "gold: a player gets no answer and no gold")
	check(HELPER_VERSION >= 25, "the helper is version 25 or later (O658: gold)")
end

-- O662: the weapons of `!tester found` (`hands`): only weapon types, best score first, the worn hands named, a shield and an ammunition left out
do
	local rows = {
		{i = 0, id = 100, cid = 1, wt = 1, il = 10, sc = 50},
		{i = 1, id = 101, cid = 2, wt = 4, il = 99, sc = 900},   -- a shield is not a weapon
		{i = 2, id = 102, cid = 3, wt = 3, il = 700, sc = 400, two = true},
		{i = 3, id = 103, cid = 4, wt = 7, il = 5, sc = 90},      -- an ammunition
		{i = 4, id = 104, cid = 5, wt = 0, il = 5, sc = 90},      -- no weapon
		{i = 5, id = 105, cid = 6, wt = 6, il = 700, sc = 400},   -- a tie on the score: the lower slot first
	}
	local rep = H.handReport(rows, {{s = 6, id = 90, cid = 9, wt = 1, il = 0, sc = 30}, {s = 5, id = 91, cid = 8, wt = 4, il = 0, sc = 10}})
	eq(#rep.bag, 3, "hands: three weapons of the six rows")
	eq(rep.bag[1].id, 102, "hands: the best score first")
	eq(rep.bag[1].two, true, "hands: a two-handed weapon says so")
	eq(rep.bag[2].id, 105, "hands: a tie goes to the lower backpack slot")
	eq(rep.bag[3].id, 100, "hands: the plain sword last")
	eq(#rep.worn, 2, "hands: both hands named")
	eq(rep.worn[1].s, 5, "hands: the worn list is by slot")
	eq(rep.worn[2].id, 90, "hands: the worn weapon")
	local many = {}
	for k = 0, 20 do many[#many + 1] = {i = k, id = 200 + k, cid = 1, wt = 2, il = 0, sc = k} end
	eq(#H.handReport(many, {}).bag, H.HAND_MAX, "hands: at most HAND_MAX rows")
	eq(#H.handReport(nil, nil).bag, 0, "hands: nothing in, nothing out")
end

-- O681: `!tester gear`: the plan of the sets' pieces by class and level, and the grant on a mocked player
do
	check(HELPER_VERSION >= 30, "the helper is version 30 or later (O681: gear)")
	check(H.COMMANDS.gear and H.parseCommand("gear set #5") == "gear", "gear is a registered command")
	eq(H.parseGear(nil).what, "state", "gear: no word is state")
	eq(H.parseGear(" SET ").what, "set", "gear: set")
	local w, usage = H.parseGear("wear")
	check(w == nil and usage:find("usage: gear", 1, true), "gear: an unknown word")
	check(H.parseGear("set now") == nil, "gear: nothing after the word")
	local HEAVY = {"Warrior", "Juggernaut", "Berserker"}
	local CLOTH = {"Mystic", "Elementalist"}
	local pieces = {
		{id = 1, kind = "helmet", fit = "H", level = 1700, name = "low helm", classes = HEAVY, stats = {armor = 40}},
		{id = 2, kind = "helmet", fit = "H", level = 1875, name = "mid helm", classes = HEAVY, stats = {armor = 50}},
		{id = 3, kind = "helmet", fit = "H", level = 2050, name = "top helm", classes = HEAVY, stats = {armor = 60}},
		{id = 4, kind = "helmet", fit = "C", level = 1875, name = "cowl", classes = CLOTH, stats = {armor = 30}},
		{id = 5, kind = "armor", fit = "H", level = 1700, name = "plate", classes = HEAVY, stats = {armor = 90}},
		{id = 6, kind = "legs", fit = "H", level = 1700, name = "legs", classes = HEAVY, stats = {armor = 70}},
		{id = 7, kind = "sword", fit = "1", level = 1875, name = "sword", classes = {"Warrior", "Juggernaut"}, stats = {attack = 40, elementenergy = 30}},
		{id = 8, kind = "sword", fit = "2", level = 1875, name = "greatsword", classes = HEAVY, stats = {attack = 40, elementenergy = 30}},
		{id = 9, kind = "axe", fit = "2", level = 1875, name = "greataxe", classes = HEAVY, stats = {attack = 50, elementenergy = 30}},
		{id = 10, kind = "boots", fit = "A", level = 1875, name = "boots", classes = {}, stats = {armor = 99}},
		{id = 11, kind = "club", fit = "1", level = 1700, name = "all club", classes = {}, stats = {attack = 99}},
	}
	local plan = H.gearPlan(pieces, "Warrior", 2000)
	eq(plan.helmet.id, 2, "gear plan: the highest level the character may wear, 2050 is above 2000")
	eq(plan.armor.id, 5, "gear plan: the armour")
	eq(plan.legs.id, 6, "gear plan: the legs")
	eq(plan.weapon.id, 11, "gear plan: the weapon of the most power (99 of a club open to everyone) wins")
	check(plan.boots == nil, "gear plan: the sets' boots are no slot of the plan")
	plan = H.gearPlan(pieces, "Juggernaut", 2100)
	eq(plan.helmet.id, 3, "gear plan: the top helmet at 2100")
	eq(plan.weapon.id, 11, "gear plan: the same power rule")
	table.remove(pieces)
	plan = H.gearPlan(pieces, "Warrior", 2100)
	eq(plan.weapon.id, 9, "gear plan: the two-handed axe of 80 over the one-handed sword of 70")
	plan = H.gearPlan(pieces, "Berserker", 2100)
	eq(plan.weapon.id, 9, "gear plan: a Berserker has two-handed weapons only")
	pieces[9].stats.attack = 40
	eq(H.gearPlan(pieces, "Warrior", 2100).weapon.id, 7, "gear plan: a one-handed weapon over a two-handed one of the same power 70")
	plan = H.gearPlan(pieces, "Mystic", 2100)
	eq(plan.helmet.id, 4, "gear plan: a cloth class takes the cloth piece")
	check(plan.armor == nil and plan.weapon == nil, "gear plan: no armour or weapon of the sets for a class they do not list")
	check(next(H.gearPlan(pieces, "Warrior", 1000)) == nil, "gear plan: no piece of the level")
	check(next(H.gearPlan(nil, "Warrior", 2000)) == nil, "gear plan: no list, no plan")
	eq(H.gearWeaponPower({attack = 10, elementfire = 5, defense = 99, skillSword = 3}), 15, "gear power: attack and element damage only")
	local ans = H.gearAnswer({helmet = {id = 2, name = ("n"):rep(60), level = 1875, fit = "H", junk = 1}}, {armor = {id = 5, il = 2000, junk = 1}}, {level = 2000})
	check(ans.plan.helmet.id == 2 and #ans.plan.helmet.name == 40 and ans.plan.helmet.junk == nil and ans.worn.armor.il == 2000 and ans.worn.armor.junk == nil
		and ans.level == 2000, "gear answer: the facts, cut down")

	-- the engine side on a mocked player
	RETURNVALUE_NOERROR = 0
	local made, moved, removed = {}, {}, {}
	local function item(id, il)
		local it = {id = id, il = il or 0}
		function it:getId() return self.id end
		function it:remove() removed[#removed + 1] = self.id; self.gone = true end
		function it:clone() return item(self.id, self.il) end
		function it:moveTo(bag)
			moved[#moved + 1] = self.id
			if self.owner and self.owner.slots[self.slot] == self then self.owner.slots[self.slot] = nil end
			return true
		end
		return it
	end
	local savedCrafting, savedSets = ChaosCrafting, ChaosGearSets
	ChaosCrafting = {levelOf = function(it) return it.il end, createItem = function(id, rarity, level)
		local it = item(id, level)
		it.rarity = rarity
		made[#made + 1] = it
		return it
	end}
	ChaosGearSets = {items = {pieces = pieces}}
	local gp = creature(268435700, "Tester Aza", {store = {[ST] = 1}})
	gp.getLevel = function() return 2100 end
	gp.getVocation = function() return {getId = function() return 4 end, getName = function() return "Warrior" end} end
	gp.cap = 400
	function gp:getCapacity() return self.cap end
	function gp:setCapacity(v) self.cap = v end
	gp.slots = {[CONST_SLOT_BACKPACK] = {isContainer = function() return true end}, [CONST_SLOT_HEAD] = item(1, 1700), [CONST_SLOT_LEFT] = item(555, 0),
		[CONST_SLOT_RIGHT] = item(556, 0)}
	for slot, it in pairs(gp.slots) do it.owner, it.slot = gp, slot end
	function gp:addItemEx(it, _, slot)
		if self.slots[slot] then return 1 end
		self.slots[slot] = it
		it.owner, it.slot = self, slot
		return RETURNVALUE_NOERROR
	end
	local last = function(p) return p.log.msgs[#p.log.msgs] end
	local flask = {}
	function gp:getItemCount(id) return flask[id] or 0 end
	function gp:addItem(id, n) flask[id] = (flask[id] or 0) + (n or 1) return true end
	local realPC = ChaosPotionsConfig
	ChaosPotionsConfig = {everfull = {{id = 32085, tier = 1, line = "health"}, {id = 32267, tier = 4, line = "health"}, {id = 32269, tier = 4, line = "mana"},
		{id = 32266, tier = 4, line = "spirit"}}}
	local lines = {}
	local origP = print
	print = function(...) lines[#lines + 1] = table.concat({...}, " ") end
	talks["!tester"].onSay(gp, "!tester", "gear #301")
	local stateAns, stateMade = last(gp), #made
	talks["!tester"].onSay(gp, "!tester", "gear set #302")
	print = origP
	check(stateAns:find('"plan"', 1, true) and stateAns:find('"seq":301', 1, true) and stateMade == 0, "gear state: reads only, nothing made")
	check(#made == 4 and made[1].rarity == 3 and made[1].il == 2100, "gear set: four Rare pieces of item level = the level (helmet, armour, legs, weapon)")
	eq(gp.slots[CONST_SLOT_HEAD].id, 3, "gear set: the top helmet is worn (the old one went to the backpack)")
	eq(gp.slots[CONST_SLOT_ARMOR].id, 5, "gear set: the armour is worn")
	eq(gp.slots[CONST_SLOT_LEGS].id, 6, "gear set: the legs are worn")
	eq(gp.slots[CONST_SLOT_LEFT].id, 7, "gear set: the one-handed weapon in the hand")
	check(gp.slots[CONST_SLOT_RIGHT] ~= nil and gp.slots[CONST_SLOT_RIGHT].id == 556, "gear set: a one-handed weapon leaves the off hand alone")
	check(last(gp):find('"given":["helmet","armor","legs","weapon"]', 1, true) and gp.cap == 400, "gear set: the answer names the slots and the capacity is back")
	check(#lines == 1 and lines[1]:find("[tester-helper] gear set for Tester Aza", 1, true), "gear set: one console line")
	eq(flask[32267], 1, "gear set: the Everfull health potion of the model's tier 4 is carried")
	eq(flask[32269], 1, "gear set: and the mana potion of tier 4")
	check(flask[32266] == nil and flask[32085] == nil, "gear set: no spirit flask, no flask of another tier")
	check(last(gp):find('"potions":{', 1, true) and last(gp):find('"health":', 1, true), "gear set: the answer names the flasks (client ids)")
	local before = flask[32267]
	talks["!tester"].onSay(gp, "!tester", "gear set #3010")
	eq(flask[32267], before, "gear set again: one flask a character")
	local nm = #made
	talks["!tester"].onSay(gp, "!tester", "gear set #303")
	eq(#made, nm, "gear set again: the pieces at the level are worn already, nothing is made")
	pieces[9].stats.attack = 60
	gp.slots[CONST_SLOT_LEFT].il = 0
	talks["!tester"].onSay(gp, "!tester", "gear set #304")
	eq(gp.slots[CONST_SLOT_LEFT].id, 9, "gear set: a two-handed weapon replaces the hand")
	check(gp.slots[CONST_SLOT_RIGHT] == nil, "gear set: the off hand is emptied for a two-handed weapon")
	-- O695: the best piece of a slot is an item the server does not have: the next best is worn, in order, and a slot with none is refused with the id
	local rk = H.gearRanked(pieces, "Warrior", 2100)
	check(#rk.helmet == 3 and rk.helmet[1].id == 3 and rk.helmet[2].id == 2 and rk.helmet[3].id == 1, "gear ranked: the helmets of the class, best first (the cowl is not a Warrior's)")
	check(rk.weapon[1].id == H.gearPlan(pieces, "Warrior", 2100).weapon.id and rk.boots == nil, "gear ranked: the first is the plan's piece, the sets' boots are no slot")
	check(next(H.gearRanked(nil, "Warrior", 2100)) == nil, "gear ranked: no list, nothing")
	local createOk = ChaosCrafting.createItem
	local gone = {[3] = true}
	ChaosCrafting.createItem = function(id, rarity, level) if gone[id] then return nil end return createOk(id, rarity, level) end
	gp.slots[CONST_SLOT_HEAD] = item(1, 1000)
	gp.slots[CONST_SLOT_HEAD].owner, gp.slots[CONST_SLOT_HEAD].slot = gp, CONST_SLOT_HEAD
	lines = {}
	local printWas = print
	print = function(...) lines[#lines + 1] = table.concat({...}, " ") end
	talks["!tester"].onSay(gp, "!tester", "gear set #307")
	print = printWas
	eq(gp.slots[CONST_SLOT_HEAD].id, 2, "gear set: the best helmet is unknown to the server, the next best is worn")
	check(last(gp):find('"given":["helmet"', 1, true) and last(gp):find('"refused":[]', 1, true), "gear set: the slot is given, nothing refused")
	local worn2 = false
	for _, l in ipairs(lines) do if l:find("helmet worn after 2 tries", 1, true) then worn2 = true end end
	check(worn2, "gear set: a console line names the second try")
	gone[2], gone[1] = true, true
	gp.slots[CONST_SLOT_HEAD] = item(9, 0)
	gp.slots[CONST_SLOT_HEAD].owner, gp.slots[CONST_SLOT_HEAD].slot = gp, CONST_SLOT_HEAD
	talks["!tester"].onSay(gp, "!tester", "gear set #308")
	check(last(gp):find('"slot":"helmet"', 1, true) and last(gp):find("item 3 unknown) +2 more", 1, true), "gear set: no helmet can be made: refused, with the id of the best piece and the others tried")
	ChaosCrafting.createItem = createOk
	local realPN2 = ChaosPinnacle
	ChaosPinnacle = {isInside = function() return true end}
	talks["!tester"].onSay(gp, "!tester", "gear set #305")
	check(last(gp):find("not inside a fight", 1, true), "gear set: never inside a pinnacle fight")
	ChaosPinnacle = realPN2
	ChaosGearSets = nil
	talks["!tester"].onSay(gp, "!tester", "gear #306")
	check(last(gp):find("no equipment sets", 1, true), "gear: no sets, the reason")
	ChaosCrafting, ChaosGearSets = savedCrafting, savedSets
	ChaosPotionsConfig = realPC
end

-- O693: the rest of the gear (`gear extras | growth | orbs | gems`), `food` and `buffs`: the plans on the real lists of the sets, the gems and the quivers, and
-- every step on a mocked player (the right slots, ids that exist in the configs, sockets filled, refused outside the closed mode and for a non-tester)
do
	check(HELPER_VERSION >= 37, "the helper is version 37 or later (O693: gear extras, growth, orbs, gems, food, buffs)")
	check(H.COMMANDS.food and H.COMMANDS.buffs and H.parseCommand("food #3") == "food" and H.parseCommand("buffs learn #4") == "buffs", "food and buffs are registered commands")
	eq(H.parseGear("extras").what, "extras", "gear extras")
	eq(H.parseGear("extras 10").rarity, 10, "gear extras 10: Divine")
	eq(H.parseGear("growth").what, "growth", "gear growth")
	eq(H.parseGear("orbs").what, "orbs", "gear orbs")
	local gw = H.parseGear("gems")
	check(gw.what == "gems" and #gw.words == 0, "gear gems: no words, every attack spell of the class")
	gw = H.parseGear("gems Saen Spek; Reth Vas Spek ;")
	check(gw.what == "gems" and #gw.words == 2 and gw.words[1] == "saen spek" and gw.words[2] == "reth vas spek", "gear gems: the words, lower case, apart by ;")
	check(H.parseGear("gems saen;ra1") == nil and H.parseGear("growth 10") == nil and H.parseGear("orbs 3") == nil and H.parseGear("extras 7") == nil
		and H.parseGear("extras now") == nil, "gear: a number or a word where none belongs is the usage")
	eq(H.gearWeaponPower({wandMin = 100, wandMax = 200}), 150, "gear power: a wand or rod is the middle of its range")
	eq(H.gearWeaponPower({attack = 245, hitChance = 98}), 245, "gear power: a bow is its attack")

	-- the plans on the real lists
	local sets = dofile("data/lib/chaos_gear_sets_items.lua")
	local pieces = sets.pieces
	local byId = {}
	for _, p in ipairs(pieces) do byId[p.id] = p end
	local quivers = dofile("data/lib/chaos_archery_config.lua").quivers
	local function checkPlan(plan, cls, level)
		for slot, p in pairs(plan) do
			check(p.id and (byId[p.id] ~= nil or p.kind == "quiver"), cls .. " " .. level .. ": " .. slot .. " is a piece of the lists (id " .. tostring(p.id) .. ")")
			check(p.level <= level, cls .. " " .. level .. ": " .. slot .. " is a piece the character may wear")
		end
	end
	local jug = H.gearExtrasPlan(pieces, "Juggernaut", 1900, quivers)
	checkPlan(jug, "Juggernaut", 1900)
	check(jug.boots and jug.boots.kind == "boots" and jug.amulet and jug.amulet.kind == "amulet" and jug.ring and jug.ring.kind == "ring", "extras plan: boots, amulet and ring for every class")
	check(jug.offhand and jug.offhand.kind == "shield", "extras plan: the Juggernaut's off hand is a shield")
	check(jug.weapon1h and jug.weapon1h.fit ~= "2" and H.GEAR_WEAPON[jug.weapon1h.kind], "extras plan: and a one-handed weapon next to it")
	check(jug.ranged == nil, "extras plan: no bow or wand for a Juggernaut")
	local sam = H.gearExtrasPlan(pieces, "Samurai", 1900, quivers)
	checkPlan(sam, "Samurai", 1900)
	check(sam.boots and sam.amulet and sam.ring and sam.offhand == nil and sam.weapon1h == nil, "extras plan: a Samurai has no shield: the jewellery and boots only")
	local dead = H.gearExtrasPlan(pieces, "Deadeye", 1900, quivers)
	checkPlan(dead, "Deadeye", 1900)
	check(dead.ranged and (dead.ranged.kind == "bow" or dead.ranged.kind == "crossbow"), "extras plan: the Deadeye's weapon is a bow or crossbow")
	check(dead.offhand and dead.offhand.kind == "quiver" and quivers[dead.offhand.id] ~= nil and quivers[dead.offhand.id][1] <= 1900, "extras plan: the Deadeye's off hand is a quiver of the archery config")
	local top = 0
	for _, q in pairs(quivers) do if q[1] <= 1900 and q[1] > top then top = q[1] end end
	eq(dead.offhand.level, top, "extras plan: the quiver of the highest level the character may wear")
	local ill = H.gearExtrasPlan(pieces, "Illusionist", 1900, quivers)
	checkPlan(ill, "Illusionist", 1900)
	check(ill.ranged and ill.ranged.kind == "rod" and ill.offhand and ill.offhand.kind == "spellbook", "extras plan: the Illusionist has a rod and a spellbook")
	local ele = H.gearExtrasPlan(pieces, "Elementalist", 2500, quivers)
	checkPlan(ele, "Elementalist", 2500)
	check(ele.ranged and ele.ranged.kind == "wand" and ele.offhand and ele.offhand.kind == "spellbook" and ele.ranged.level <= 2050, "extras plan: the Elementalist has a wand and a spellbook, none above the top set")
	check(next(H.gearExtrasPlan(pieces, "Juggernaut", 0, quivers)) == nil and next(H.gearExtrasPlan(nil, "Juggernaut", 1900)) == nil, "extras plan: no piece of the level, no list: no plan")

	-- the gems, on the real config
	local gcfg = dofile("data/lib/chaos_gems_config.lua")
	local function effects(group, plan)
		local out = {}
		for i, t in ipairs(plan) do out[i] = gcfg.types[t][group].effect end
		return table.concat(out, ",")
	end
	eq(H.gemTier(gcfg.drop.levelWeights[#gcfg.drop.levelWeights][2]), 5, "gem tier: a high level makes Perfect gems")
	eq(H.gemTier({60, 32, 8, 0, 0}), 3, "gem tier: the last tier with a weight")
	eq(H.gemTier(nil), 1, "gem tier: no row, tier 1")
	eq(H.gemElement({{element = "fire"}, {element = "fire"}, {element = "ice"}, {}}), "fire", "gem element: the most common element of the spells")
	eq(H.gemElement({{element = "ice"}, {element = "fire"}}), "fire", "gem element: a tie goes by the fixed order")
	eq(H.gemElement({}), nil, "gem element: no spell, none")
	eq(effects("weapon", H.gemPlan(gcfg.types, "weapon", "fire", 2)), "dmg_fire,dmg_fire", "gem plan: a fire class's weapon takes fire damage gems")
	eq(effects("weapon", H.gemPlan(gcfg.types, "weapon", "holy", 3)), "dmg_holy,dmg_holy,dmg_holy", "gem plan: a holy class, a two-handed weapon")
	eq(effects("weapon", H.gemPlan(gcfg.types, "weapon", "death", 2)), "crit,attackspeed", "gem plan: death has no weapon gem: crit, then attack speed")
	eq(effects("weapon", H.gemPlan(gcfg.types, "weapon", nil, 3)), "crit,attackspeed,attackspeed", "gem plan: no element: crit, then attack speed")
	eq(effects("armour", H.gemPlan(gcfg.types, "armour", "fire", 3)), "maxhealth,maxhealth,maxhealth", "gem plan: armour takes max health")
	eq(effects("jewel", H.gemPlan(gcfg.types, "jewel", "death", 1)), "dmg_death", "gem plan: death damage on a jewel")
	eq(effects("jewel", H.gemPlan(gcfg.types, "jewel", "energy", 1)), "dmg_energy", "gem plan: energy damage on a jewel")
	eq(effects("jewel", H.gemPlan(gcfg.types, "jewel", "physical", 1)), "dmg_physical", "gem plan: physical damage on a jewel")
	eq(effects("jewel", H.gemPlan(gcfg.types, "jewel", "fire", 1)), "res_ice", "gem plan: a fire class's jewel takes ice resistance")
	eq(#H.gemPlan(gcfg.types, "weapon", "fire", 0), 0, "gem plan: no socket, no gem")
	-- the buff spells are the second spell of each line of the line spell quests
	local qc = dofile("data/scripts/chaos/spellquest_config.lua")
	eq(#qc.lines, #H.BUFF_SPELLS, "buff spells: one for each line")
	for i, line in ipairs(qc.lines) do
		check(H.isBuffSpell(line.spells[2]), "buff spells: " .. line.key .. " quest 2 is " .. tostring(line.spells[2]))
	end
	check(not H.isBuffSpell("Keepfall") and not H.isBuffSpell(nil), "buff spells: a quest 1 or 3 spell is no buff")

	-- the engine side on a mocked player
	local savedC, savedG, savedSets, savedArch, savedK, savedIT, savedPN = ChaosCrafting, ChaosGems, ChaosGearSets, ChaosArchery, ChaosTestersCore, ItemType, ChaosPinnacle
	local savedSupports, savedFood, savedFoodCore, savedFoodCfg, savedQ, savedItemMods = ChaosSupports, ChaosStoreFood, ChaosStoreFoodCore, ChaosStoreFoodConfig, ChaosSpellQuestCore, ChaosItemMods
	local savedSlotp, savedAttr, savedRegen, savedCid, savedRC = SLOTP_TWO_HAND, ITEM_ATTRIBUTE_ATTACK, CONDITION_REGENERATION, CONDITIONID_DEFAULT, RETURNVALUE_NOERROR
	SLOTP_TWO_HAND, ITEM_ATTRIBUTE_ATTACK, CONDITION_REGENERATION, CONDITIONID_DEFAULT, RETURNVALUE_NOERROR = 2048, 17, 5, 0, 0
	local twoHand = {}
	for _, p in ipairs(pieces) do
		if p.fit == "2" and H.GEAR_WEAPON[p.kind] then twoHand[p.id] = true end
	end
	ItemType = function(id)
		return {getClientId = function() return id + 10000 end, getName = function() return "item " .. id end, isStackable = function() return false end,
			getSlotPosition = function() return twoHand[id] and 2048 or 0 end}
	end
	local MAXSOCK = {helmet = 2, armor = 3, legs = 2, boots = 1, shield = 2, spellbook = 2, quiver = 1, amulet = 1, ring = 1, sword = 2, axe = 2, club = 2,
		bow = 2, crossbow = 2, wand = 2, rod = 2}
	local GROUP = {amulet = "jewel", ring = "jewel", sword = "weapon", axe = "weapon", club = "weapon", bow = "weapon", crossbow = "weapon", wand = "weapon", rod = "weapon"}
	local made, removedGems = {}, 0
	local function newItem(id)
		local row = byId[id]
		local kind = row and row.kind or (quivers[id] and "quiver") or "plain"
		local it = {id = id, kind = kind, il = 0, rarity = 0, quality = 0, attack = (row and row.stats and row.stats.attack) or 0, marks = {}, gems = {}, sockets = 0,
			fit = row and row.fit}
		function it:getId() return self.id end
		function it:remove() self.gone = true end
		function it:clone() return newItem(self.id) end
		function it:moveTo() self.moved = true; if self.owner and self.owner.slots[self.slot] == self then self.owner.slots[self.slot] = nil end return true end
		function it:getAttribute() return self.attack end
		function it:getCustomAttribute(k) return self.marks[k] end
		return it
	end
	local touches = 0
	ChaosCrafting = {GROWN = "chaos_wgrow",
		levelOf = function(it) return it.il end, rarityOf = function(it) return it.rarity end,
		createItem = function(id, rarity, level)
			local it = newItem(id)
			it.il, it.rarity = level, rarity
			if MAXSOCK[it.kind] then it.maxSockets = MAXSOCK[it.kind] + ((it.kind == "sword" or it.kind == "axe" or it.kind == "club") and it.fit == "2" and 1 or 0) end
			it.group = GROUP[it.kind] or "armour"
			made[#made + 1] = it
			return it
		end,
		upgradeItem = function(it) touches = touches + 1 if it.marks.chaos_wgrow then return false end it.marks.chaos_wgrow = 1 it.attack = it.attack + 5 return true end,
		qualityOf = function(it) return it.quality end,
		orbByKey = {whetstone = {}, tempering = {}, ember = {}},
		apply = function(key, it)
			if it.corrupted then return false, "corrupted" end
			if key == "whetstone" then
				if it.quality >= 30 then return false, "full" end
				it.quality = it.quality + 1
			elseif key == "tempering" then it.tempered = (it.tempered or 0) + 1
			else it.embers = (it.embers or 0) + 1 end
			return true, {item = it}
		end}
	ChaosGearSets = {items = {pieces = pieces}}
	ChaosArchery = {config = {quivers = quivers}}
	local G = {config = gcfg}
	G.levelWeights = function(level)
		for _, row in ipairs(gcfg.drop.levelWeights) do if level <= row[1] then return row[2] end end
		return gcfg.drop.levelWeights[#gcfg.drop.levelWeights][2]
	end
	G.maxSockets = function(it) return it.maxSockets or 0 end
	G.groupOf = function(it) return it.group end
	G.count = function(it) return it.sockets end
	G.setCount = function(it, n) it.sockets = n return {} end
	G.gemAt = function(it, i) return it.gems[i] or 0 end
	G.gemId = function(t, tier) return gcfg.firstId + (t - 1) * 5 + tier - 1 end
	G.gemName = function(id) return "gem" .. id end
	G.writeDescription = function() end
	G.socket = function(_, gem, it)
		for i = 1, it.sockets do
			if not it.gems[i] then it.gems[i] = gem.id; gem.gone = true return true, "ok" end
		end
		return false, "full"
	end
	ChaosGems = G
	local closed = true
	ChaosTestersCore = {closedOn = function() return closed end}
	ChaosPinnacle = nil
	local refreshed = 0
	ChaosItemMods = {refresh = function() refreshed = refreshed + 1 end}
	ChaosSupports = {catalog = function()
		return {
			[1] = {words = "exura a", element = "fire", kind = "single", level = 100, vocations = {[8] = true}},
			[2] = {words = "exura b", element = "fire", kind = "area", level = 200, vocations = {}},
			[3] = {words = "exura c", element = "ice", kind = "area", level = 300, vocations = {[8] = true}},
			[4] = {words = "exura d", element = "death", kind = "single", level = 400, vocations = {[2] = true}},
			[5] = {words = "exura e", element = "ice", kind = "heal", level = 100, vocations = {}},
			[6] = {words = "exura f", element = "ice", kind = "single", level = 9000, vocations = {}},
		}
	end}

	local function slotsOf(p) return p.slots end
	local gp = creature(268435800, "Tester Jug", {store = {[ST] = 1}})
	gp.getLevel = function() return 1900 end
	gp.getVocation = function() return {getId = function() return 8 end, getName = function() return "Juggernaut" end} end
	gp.cap = 400
	function gp:getCapacity() return self.cap end
	function gp:setCapacity(v) self.cap = v end
	local greatsword
	for _, p in ipairs(pieces) do
		if p.fit == "2" and p.kind == "sword" and p.level <= 1900 then greatsword = p.id end
	end
	gp.slots = {[CONST_SLOT_BACKPACK] = {isContainer = function() return true end}, [CONST_SLOT_LEFT] = newItem(greatsword)}
	for slot, it in pairs(gp.slots) do it.owner, it.slot = gp, slot end
	function gp:addItemEx(it, _, slot)
		if self.slots[slot] then return 1 end
		self.slots[slot] = it
		it.owner, it.slot = self, slot
		return RETURNVALUE_NOERROR
	end
	function gp:addItem(id) return newItem(id) end
	function gp:removeItem() removedGems = removedGems + 1 end
	local last = function(p) return p.log.msgs[#p.log.msgs] end
	local say = function(p, text) talks["!tester"].onSay(p, "!tester", text) end
	local origP = print
	print = function() end

	-- refused: the closed mode off, a pinnacle fight, a character that is no tester
	closed = false
	for i, word in ipairs({"gear extras", "gear growth", "gear orbs", "gear gems"}) do
		say(gp, word .. " #" .. (500 + i))
		check(last(gp):find("closed test mode is off", 1, true) and last(gp):find('"seq":' .. (500 + i), 1, true), word .. ": refused with the closed test mode off")
	end
	say(gp, "food #510")
	check(last(gp):find("closed test mode is off", 1, true), "food: refused with the closed test mode off")
	say(gp, "buffs learn #511")
	check(last(gp):find("closed test mode is off", 1, true), "buffs learn: refused with the closed test mode off")
	eq(#made, 0, "nothing was made while refused")
	closed = true
	ChaosPinnacle = {isInside = function() return true end}
	say(gp, "gear gems #512")
	check(last(gp):find("not inside a fight", 1, true), "gear gems: never inside a pinnacle fight")
	ChaosPinnacle = nil
	local stranger = creature(268435801, "Ana Real")
	stranger.slots = {}
	local before = #stranger.log.msgs
	check(talks["!tester"].onSay(stranger, "!tester", "gear extras #513") == true and #stranger.log.msgs == before and #made == 0, "gear extras: a player is left alone, nothing is made")
	local fakeT = creature(268435802, "Tester Fak")
	check(talks["!tester"].onSay(fakeT, "!tester", "gear gems #514") == true and #fakeT.log.msgs == 0, "gear gems: a tester's name without the storage is left alone")

	-- extras: a Juggernaut after `gear set` (a two-handed sword is the plan's weapon): the one-handed weapon, boots, amulet, ring, the shield
	function gp:getItemCount() return 1 end
	say(gp, "gear set 10 #519")
	check(gp.slots[CONST_SLOT_ARMOR] ~= nil and gp.slots[CONST_SLOT_HEAD] ~= nil and gp.slots[CONST_SLOT_LEGS] ~= nil, "gear set first: the armour pieces are worn: " .. last(gp):sub(1, 160))
	do -- the two-handed sword back in hand, as a character that wore it before the shield
		local sword = newItem(greatsword)
		sword.owner, sword.slot, sword.il, sword.rarity = gp, CONST_SLOT_LEFT, 1900, 10
		gp.slots[CONST_SLOT_LEFT] = sword
	end
	say(gp, "gear extras 10 #520")
	local ans = last(gp)
	check(ans:find('"what":"extras"', 1, true) and ans:find('"seq":520', 1, true), "gear extras: answers as extras")
	check(gp.slots[CONST_SLOT_FEET] and byId[gp.slots[CONST_SLOT_FEET].id].kind == "boots", "gear extras: boots are worn")
	check(gp.slots[CONST_SLOT_NECKLACE] and byId[gp.slots[CONST_SLOT_NECKLACE].id].kind == "amulet", "gear extras: the amulet is worn")
	check(gp.slots[CONST_SLOT_RING] and byId[gp.slots[CONST_SLOT_RING].id].kind == "ring", "gear extras: the ring is worn")
	check(gp.slots[CONST_SLOT_RIGHT] and byId[gp.slots[CONST_SLOT_RIGHT].id].kind == "shield", "gear extras: the shield is in the off hand")
	check(gp.slots[CONST_SLOT_LEFT] and byId[gp.slots[CONST_SLOT_LEFT].id].fit ~= "2", "gear extras: a one-handed weapon replaced the two-handed one")
	local allOk = #made >= 5
	for _, it in ipairs(made) do
		allOk = allOk and it.rarity == 10 and it.il == 1900 and byId[it.id] ~= nil
	end
	check(allOk, "gear extras: every piece is a piece of the lists, Divine, item level = the level")
	check(ans:find('"given":["weapon1h","boots","amulet","ring","offhand"]', 1, true), "gear extras: the answer names the slots in order: " .. ans:sub(1, 300))
	eq(gp.cap, 400, "gear extras: the capacity is back")
	check(refreshed >= 1, "gear extras: the item modifiers are refreshed")
	local nm = #made
	say(gp, "gear extras 10 #521")
	eq(#made, nm, "gear extras again: the pieces are worn at the level and rarity, nothing is made")
	check(last(gp):find('"given":["boots","amulet","ring","offhand"]', 1, true) and last(gp):find("skipped", 1, true), "gear extras again: the rest is worn, the one-handed weapon step is skipped")

	-- an archer: a bow and the quiver; a class with a two-handed weapon in hand keeps no shield
	local ap = creature(268435803, "Tester Arc", {store = {[ST] = 1}})
	ap.getLevel = function() return 1900 end
	ap.getVocation = function() return {getId = function() return 9 end, getName = function() return "Deadeye" end} end
	ap.cap = 400
	function ap:getCapacity() return self.cap end
	function ap:setCapacity(v) self.cap = v end
	ap.slots = {[CONST_SLOT_BACKPACK] = {isContainer = function() return true end}}
	for slot, it in pairs(ap.slots) do it.owner, it.slot = ap, slot end
	ap.addItemEx, ap.addItem, ap.removeItem = gp.addItemEx, gp.addItem, gp.removeItem
	say(ap, "gear extras 10 #530")
	check(ap.slots[CONST_SLOT_LEFT] and (byId[ap.slots[CONST_SLOT_LEFT].id].kind == "bow" or byId[ap.slots[CONST_SLOT_LEFT].id].kind == "crossbow"), "gear extras: the Deadeye wears a bow or crossbow")
	check(ap.slots[CONST_SLOT_RIGHT] and quivers[ap.slots[CONST_SLOT_RIGHT].id] ~= nil, "gear extras: and a quiver of the archery config in the off hand")
	check(ap.slots[CONST_SLOT_FEET] and ap.slots[CONST_SLOT_NECKLACE] and ap.slots[CONST_SLOT_RING], "gear extras: and boots, amulet, ring")
	local sp = creature(268435804, "Tester Sam", {store = {[ST] = 1}})
	sp.getLevel = function() return 1900 end
	sp.getVocation = function() return {getId = function() return 10 end, getName = function() return "Samurai" end} end
	sp.cap = 400
	function sp:getCapacity() return self.cap end
	function sp:setCapacity(v) self.cap = v end
	sp.slots = {[CONST_SLOT_BACKPACK] = {isContainer = function() return true end}, [CONST_SLOT_LEFT] = newItem(greatsword)}
	for slot, it in pairs(sp.slots) do it.owner, it.slot = sp, slot end
	sp.addItemEx, sp.addItem, sp.removeItem = gp.addItemEx, gp.addItem, gp.removeItem
	say(sp, "gear extras 10 #531")
	check(sp.slots[CONST_SLOT_RIGHT] == nil and sp.slots[CONST_SLOT_FEET] and sp.slots[CONST_SLOT_NECKLACE] and sp.slots[CONST_SLOT_RING], "gear extras: a Samurai has jewellery and boots, no off hand")

	-- growth: the touch of the game, once (the mark)
	say(gp, "gear growth #540")
	ans = last(gp)
	check(ans:find('"what":"growth"', 1, true) and ans:find('"grown":true', 1, true) and ans:find('"touched":true', 1, true), "gear growth: the weapon is touched and carries the mark: " .. ans:sub(1, 200))
	local t1 = touches
	say(gp, "gear growth #541")
	check(last(gp):find('"touched":false', 1, true) and last(gp):find('"grown":true', 1, true) and touches > t1, "gear growth again: the mark holds, the attack does not move twice")

	-- orbs: whetstones to the quality of the plan, one tempering, embers on the weapon and the armour
	for _, e in pairs(gp.slots) do if e.quality then e.quality = 0 end end
	say(gp, "gear orbs #550")
	ans = last(gp)
	local weaponIt, armorIt = gp.slots[CONST_SLOT_LEFT], gp.slots[CONST_SLOT_ARMOR]
	eq(weaponIt.quality, H.ORB_PLAN.quality, "gear orbs: the weapon is at the quality of the plan")
	check(gp.slots[CONST_SLOT_FEET].quality == H.ORB_PLAN.quality and gp.slots[CONST_SLOT_RING].quality == H.ORB_PLAN.quality, "gear orbs: so are the boots and the ring")
	eq(weaponIt.tempered, 1, "gear orbs: one Orb of Tempering")
	eq(weaponIt.embers, 1, "gear orbs: one Ember Orb on the weapon")
	check(gp.slots[CONST_SLOT_FEET].embers == nil, "gear orbs: no Ember Orb on the boots")
	check(ans:find('"what":"orbs"', 1, true) and ans:find('"whetstone":', 1, true), "gear orbs: the answer counts the orbs")
	local wq = weaponIt.quality
	say(gp, "gear orbs #551")
	eq(weaponIt.quality, wq + 0, "gear orbs again: whetstones stop at the quality")
	weaponIt.quality, weaponIt.corrupted = 0, true
	say(gp, "gear orbs #552")
	check(weaponIt.quality == 0 and last(gp):find("corrupted", 1, true), "gear orbs: a corrupted piece is refused by the orbs' own rule and named")
	weaponIt.corrupted = nil
	local plain = ChaosCrafting.orbByKey
	ChaosCrafting.orbByKey = {}
	say(gp, "gear orbs #553")
	check(last(gp):find("no crafting orbs", 1, true), "gear orbs: an install without the orbs: the reason")
	ChaosCrafting.orbByKey = plain

	-- gems: the element of the class's spells (Juggernaut: fire x2, ice x1 -> fire), sockets to the item's most, Perfect gems at level 1900
	say(gp, "gear gems #560")
	ans = last(gp)
	check(ans:find('"what":"gems"', 1, true) and ans:find('"element":"fire"', 1, true) and ans:find('"tier":5', 1, true), "gear gems: fire, tier 5: " .. ans:sub(1, 160))
	local function gemEffectsOf(it)
		local out = {}
		for i = 1, it.sockets do
			local g = it.gems[i]
			check(g ~= nil and g >= gcfg.firstId and g <= gcfg.firstId + 34, "gear gems: socket " .. i .. " of " .. it.kind .. " holds a gem id of the config")
			if g then
				local n = g - gcfg.firstId
				out[i] = gcfg.types[math.floor(n / 5) + 1][it.group].effect .. "@" .. (n % 5 + 1)
			end
		end
		return table.concat(out, ",")
	end
	eq(gemEffectsOf(gp.slots[CONST_SLOT_LEFT]), "dmg_fire@5,dmg_fire@5", "gear gems: the one-handed weapon has two Perfect fire gems")
	eq(gemEffectsOf(gp.slots[CONST_SLOT_ARMOR]), "maxhealth@5,maxhealth@5,maxhealth@5", "gear gems: the armour has three Perfect health gems")
	eq(gemEffectsOf(gp.slots[CONST_SLOT_FEET]), "maxhealth@5", "gear gems: the boots one")
	eq(gemEffectsOf(gp.slots[CONST_SLOT_RING]), "res_ice@5", "gear gems: the ring has ice resistance")
	eq(gemEffectsOf(gp.slots[CONST_SLOT_RIGHT]), "maxhealth@5,maxhealth@5", "gear gems: the shield has two health gems")
	local gemsBefore = 0
	for _, it in pairs(gp.slots) do gemsBefore = gemsBefore + #(it.gems or {}) end
	say(gp, "gear gems #561")
	local gemsAfter = 0
	for _, it in pairs(gp.slots) do gemsAfter = gemsAfter + #(it.gems or {}) end
	eq(gemsAfter, gemsBefore, "gear gems again: the sockets are full, no gem is added")
	check(last(gp):find('"socketed":0', 1, true), "gear gems again: nothing socketed")
	eq(gp.cap, 400, "gear gems: the capacity is back")
	-- named words decide the element: a death spell and an energy-free list
	for _, it in pairs(gp.slots) do if it.gems then it.gems, it.sockets = {}, 0 end end
	say(gp, "gear gems exura d #562")
	check(last(gp):find('"element":"death"', 1, true), "gear gems with words: the element of the named spell")
	eq(gemEffectsOf(gp.slots[CONST_SLOT_LEFT]), "crit@5,attackspeed@5", "gear gems: a death class's weapon takes crit and attack speed")
	eq(gemEffectsOf(gp.slots[CONST_SLOT_RING]), "dmg_death@5", "gear gems: and death damage on the ring")
	-- a gem that cannot be socketed is taken back
	for _, it in pairs(gp.slots) do if it.gems then it.gems, it.sockets = {}, 0 end end
	G.socket = function() return false, "refused here" end
	local rb = removedGems
	say(gp, "gear gems #563")
	check(removedGems > rb and last(gp):find('"socketed":0', 1, true) and last(gp):find("refused here", 1, true), "gear gems: a refused gem is taken away again and named")
	G.socket = nil
	say(gp, "gear gems #564")
	check(last(gp):find("no gems system", 1, true), "gear gems: an install without the gems: the reason")

	-- food: the store's ration and its bites
	local feed = 0
	local owned = false
	local function regen() return feed > 0 and {getTicks = function() return feed * 1000 end} or nil end
	gp.getCondition = function() return regen() end
	function gp:feed(s) feed = feed + s end
	dofile("data/scripts/chaos/store_food_core.lua")
	ChaosStoreFoodConfig = dofile("data/scripts/chaos/store_food_config.lua")
	ChaosStoreFood = {installed = function() return true end, owned = function() return owned end, give = function() owned = true return "backpack" end}
	say(gp, "food #570")
	ans = last(gp)
	check(ans:find('"gave":"backpack"', 1, true) and ans:find('"bites":1', 1, true) and ans:find('"seconds":720', 1, true), "food: the ration is given and one bite fills it to 720 s: " .. ans)
	check(ans:find('"item":' .. ChaosStoreFoodConfig.item.id, 1, true), "food: the item is the ration of the store config")
	say(gp, "food #571")
	ans = last(gp)
	check(ans:find('"bites":0', 1, true) and ans:find('"gave"', 1, true) == nil, "food again: one ration a character, full: no bite")
	ChaosStoreFood.installed = function() return false end
	say(gp, "food #572")
	check(last(gp):find("no ration system", 1, true), "food: a server without the ration: the reason")

	-- buffs: the level 800 spell of the class line
	local learned = false
	gp.hasLearnedSpell = function() return learned end
	gp.learnSpell = function(_, name) learned = name end
	ChaosSpellQuestCore = {lineOf = function(voc) return 1, qc.lines[1] end}
	say(gp, "buffs #580")
	ans = last(gp)
	check(ans:find('"spell":"Ironbound Oath"', 1, true) and ans:find('"learned":false', 1, true), "buffs state: the Warrior line's buff, not learned: " .. ans)
	say(gp, "buffs learn #581")
	ans = last(gp)
	eq(learned, "Ironbound Oath", "buffs learn: the spell is taught by the engine's own call")
	check(ans:find('"learned":true', 1, true), "buffs learn: the answer says it is learned")
	learned = true
	local taught = false
	gp.learnSpell = function() taught = true end
	say(gp, "buffs learn #582")
	check(not taught, "buffs learn again: a spell that is known is not taught again")
	say(gp, "buffs now #583")
	check(last(gp):find("usage: buffs", 1, true), "buffs: an unknown word is the usage")
	ChaosSpellQuestCore = {lineOf = function() return nil end}
	say(gp, "buffs #584")
	check(last(gp):find("no buff spell", 1, true), "buffs: a class with no line: the reason")
	ChaosSpellQuestCore = {lineOf = function() return 1, {key = "x", spells = {"Keepfall", "Keepfall", "Keepfall"}} end}
	say(gp, "buffs #585")
	check(last(gp):find("no buff spell", 1, true), "buffs: a second spell that is no buff is refused")

	print = origP
	ChaosCrafting, ChaosGems, ChaosGearSets, ChaosArchery, ChaosTestersCore, ItemType, ChaosPinnacle = savedC, savedG, savedSets, savedArch, savedK, savedIT, savedPN
	ChaosSupports, ChaosStoreFood, ChaosStoreFoodCore, ChaosStoreFoodConfig, ChaosSpellQuestCore, ChaosItemMods = savedSupports, savedFood, savedFoodCore, savedFoodCfg, savedQ, savedItemMods
	SLOTP_TWO_HAND, ITEM_ATTRIBUTE_ATTACK, CONDITION_REGENERATION, CONDITIONID_DEFAULT, RETURNVALUE_NOERROR = savedSlotp, savedAttr, savedRegen, savedCid, savedRC
end

-- O686 phase 8: `!tester spellup` (TEST ONLY): the reading of the words, the probe, the grants, the log of the hook wrappers, the monster health factor
do
	check(HELPER_VERSION >= 40, "the helper is version 40 or later (O686 phase 8: spellup)")
	eq(H.parseSpellup(nil).what, "state", "spellup: no word is state")
	eq(H.parseSpellup("LOG clear").clear, true, "spellup: log clear")
	local r = H.parseSpellup("rank 200 20")
	check(r.what == "rank" and r.spell == 200 and r.rank == 20, "spellup: rank SPELL RANK")
	check(H.parseSpellup("rank 200 21") == nil and H.parseSpellup("rank 500 1") == nil and H.parseSpellup("rank 5") == nil, "spellup: a rank above 20 or a spell above 499 is refused")
	local s1, s3 = H.parseSpellup("seals 7"), H.parseSpellup("seals 1 2 3")
	check(s1.waystone == 7 and s1.rift == 7 and s1.pinnacle == 7 and s3.waystone == 1 and s3.rift == 2 and s3.pinnacle == 3, "spellup: seals N or W R P")
	eq(H.parseSpellup("seals 5000").waystone, 999, "spellup: Seals are capped at 999")
	check(H.parseSpellup("seals 1 2 3 4") == nil and H.parseSpellup("seals x") == nil and H.parseSpellup("burn") == nil and select(2, H.parseSpellup("burn")) == H.SPELLUP_USAGE,
		"spellup: other words are the usage")

	local saved = {ChaosSpellRanks, ChaosSpellRanksConfig, ChaosSpellRanksCore, ChaosSpellCombos, ChaosSpellAwakening, ChaosCombatLog, ChaosSpellForms, ChaosPace,
		COMBAT_NONE, ORIGIN_SPELL, Chaos.healthFactor, Game.createMonster, Game.getSpectators}
	COMBAT_NONE, ORIGIN_SPELL = 0, 3
	local cfgS = {enabled = true, track = true, testersEarn = true,
		storage = {rankBase = 5000, sealWaystone = 6001, sealRift = 6002, sealPinnacle = 6003, awakened = 6004, formChanges = 6005, lastPickAt = 6006,
			lastPickWhat = 6007, awakenedSlots = 6100}}
	ChaosSpellRanksConfig = cfgS
	local spell = 200
	local sup = creature(268436100, "Tester Sup", {store = {[ST] = 1}})
	sup.getLevel = function() return 150 end
	sup.getExperience = function() return 123456 end
	sup.hasLearnedSpell = function() return true end
	local ranked = {sp = {[200] = 1.5, [201] = 0}, rank = {[200] = 3}, dirty = {}}
	local flushed = 0
	ChaosSpellRanks = {players = {[sup.id] = ranked}, catalog = {[200] = {name = "Bolt", scale = 1}, [201] = {name = "Wave", scale = 1}},
		castSpell = function() return spell end, hitFactor = function() return 1.09 end, flush = function() flushed = flushed + 1 end,
		state = function() return {s = {{200, 3, 0.5, 2}}} end}
	ChaosSpellRanksCore = {refXp = function() return 39130589.5 end, spForRank = function(rank) return rank * 2 end, unpack = function(v) return v > 0 and v or 0, 0, 0, false end,
		pack = function(rank) return rank end}
	local cf = 1
	ChaosSpellCombos = {hitFactor = function() return cf end, announce = function() end}
	local af = 1
	ChaosSpellAwakening = {hitFactor = function() return af end, seals = function(p) return {waystone = 2, rift = 3, pinnacle = 4} end, slots = function() return {0, 0, 0} end}
	local spellHits = 0
	ChaosCombatLog = {spellHook = function() spellHits = spellHits + 1 end}
	ChaosSpellForms = {picksOf = function() return {{200, 1, 0}} end}
	local hf = 1.05
	Chaos.healthFactor = function() return hf end
	local made = {}
	ChaosPace = {levelOf = function() return 300 end, apply = function() return true end}
	local mon = creature(268436101, "Troll", {player = false, monster = true})
	Game.getSpectators = function() return {sup, mon} end
	Game.createMonster = function(name)
		local m = creature(268436200 + #made, name, {player = false, monster = true, health = 1000})
		m.removed = false
		m.maxHealth = cfgS.enabled and 1050 or 1000
		function m:getMaxHealth() return self.maxHealth end
		function m:remove() self.removed = true end
		function m:setMaxHealth(v) self.hp = v end
		function m:setHealth(v) self.hp = v end
		made[#made + 1] = m
		return m
	end
	local origP = print
	print = function() end
	local function say2(text) talks["!tester"].onSay(sup, "!tester", text) end
	say2("spellup #901")
	local out = last(sup)
	check(out:find('"on":true', 1, true) and out:find('"earn":true', 1, true) and out:find('"hf":1.0500', 1, true) and out:find('"seq":901', 1, true), "spellup state: the switches, H, the number")
	check(out:find('"sp":1.5000', 1, true) and out:find("[200,3,1.5000]", 1, true), "spellup state: the SP and the rank of the spell")
	check(out:find('"exp":123456', 1, true) and out:find('"ref":39130589', 1, true), "spellup state: the experience and the model's experience an hour, for the pace")
	ChaosSpellForms.entry = function(sid)
		if sid == 200 then return {[1] = {{kind = "ECHO"}, {kind = "BURST"}}, [2] = {{kind = "AREA"}}} end
	end
	say2("spellup forms #912")
	check(last(sup):find('"forms":[[200,"Bolt",0,["ECHO","BURST","AREA","?"]]]', 1, true), "spellup forms: the spells with Forms and the kind of each pick")
	-- the wrappers count the factors the hooks give a tester's hit, and only a tester's
	local rf = ChaosSpellRanks.hitFactor
	eq(rf(sup, mon, ORIGIN_SPELL, 1), 1.09, "the wrapper passes the rank factor through")
	cf, af = 1.15, 1.1
	ChaosSpellCombos.announce(sup, {id = "steam_burst"}, nil)
	ChaosSpellCombos.hitFactor(sup, mon)
	ChaosSpellAwakening.hitFactor(sup)
	ChaosCombatLog.spellHook(sup, nil, mon, 400, 200)
	ChaosCombatLog.spellHook(sup, nil, mon, 600, 200)
	check(spellHits == 2, "the wrapper of the combat log calls the original")
	local stranger = creature(268436102, "Ana Three", {player = true})
	rf(stranger, mon, ORIGIN_SPELL, 1)
	say2("spellup log #902")
	out = last(sup)
	check(out:find('"log":[[200,1,1.0900,1,1.1500,1.1500,1,1.1000,2,1000,600,1.1000,1.1000]]', 1, true), "spellup log: factors, combo and awakening procs, the hits and their total and best")
	check(out:find('"fires":[["steam_burst",', 1, true) and out:find(',' .. mon.id .. ',', 1, true), "spellup log: the combo row that fired, the target and the time")
	say2("spellup log clear #903")
	say2("spellup log #904")
	check(last(sup):find('"log":[]', 1, true), "spellup log clear: the log is empty after it")
	-- grants
	ChaosSpellForms.element = function(sid) return sid == 200 and "fire" or nil end
	say2("spellup combos #930")
	check(last(sup):find('"spells":[[200,"Bolt","fire",0],[201,"Wave","",0]]', 1, true), "spellup combos: the spells of the book with the element and the heal flag: " .. last(sup))
	check(last(sup):find('"combos":false', 1, true) and last(sup):find('"ring":-1', 1, true), "spellup combos: the combos state is told (off and no ring in the mock)")
	local madeBefore = #made
	Game.getSpectators = function() return {sup, mon} end
	say2("spellup mob #931")
	check(last(sup):find('"mob":3', 1, true) and last(sup):find('"name":"Rat"', 1, true) and #made == madeBefore + 3, "spellup mob: three Rats beside the bot, whatever stands near")
	eq(sup.target, made[madeBefore + 1], "spellup mob: the first Rat is the bot's target")
	eq(made[madeBefore + 2].hp, 200000, "spellup mob: sturdy enough to live through two casts")
	say2("spellup rank 201 12 #905")
	eq(ranked.rank[201], 12, "spellup rank: the rank is set")
	eq(ranked.sp[201], 24, "spellup rank: with the SP of that rank")
	eq(sup.store[5201], 12, "spellup rank: and stored")
	check(flushed >= 1 and last(sup):find('"name":"Wave"', 1, true), "spellup rank: flushed, named")
	ChaosSpellRanksCore.rankOf = function(sp, scale) return 2, 0.1, 0.6 end
	say2("spellup near 200 #920")
	check(last(sup):find('"near":[200,2,1.9995]', 1, true), "spellup near: the SP is set just under the next rank (cost 0.6, 0.1 in: +0.5 - 0.0005)")
	eq(ranked.dirty[200], true, "spellup near: the spell is marked for the writer")
	ChaosSpellRanksCore.rankOf = function() return 20, 0, 0 end
	say2("spellup near 200 #921")
	check(last(sup):find("top rank", 1, true), "spellup near: the top rank has no next rank")
	check(H.parseSpellup("near 200").spell == 200 and H.parseSpellup("near") == nil and H.parseSpellup("near 500") == nil, "spellup: near SPELL")
	say2("spellup rank 300 5 #906")
	check(last(sup):find('"err":', 1, true), "spellup rank: a spell with no rank is an error")
	say2("spellup seals 5 6 7 #907")
	eq(sup.store[6001] .. sup.store[6002] .. sup.store[6003], "567", "spellup seals: the three counters")
	-- the health factor: two fresh copies, off then on, removed after
	local beforeH = #made
	say2("spellup h #908")
	out = last(sup)
	check(out:find('"off":1000', 1, true) and out:find('"on":1050', 1, true) and out:find('"hf":1.0500', 1, true) and out:find('"level":300', 1, true), "spellup h: both copies read")
	check(#made == beforeH + 2 and made[beforeH + 1].removed and made[beforeH + 2].removed and cfgS.enabled == true, "spellup h: the copies are removed and the switch is back")
	Game.getSpectators = function() return {sup} end
	say2("spellup h #909")
	check(last(sup):find("no monster within 7 tiles", 1, true), "spellup h: no monster near is an answer")
	say2("spellup clear #910")
	check(ranked.rank[200] == 0 and ranked.sp[201] == 0 and sup.store[6001] == 0 and sup.store[5200] == 0, "spellup clear: ranks, SP and Seals back to nothing")
	say2("spellup burn #911")
	check(last(sup):find("usage: spellup", 1, true), "spellup: an unknown word is the usage")
	print = origP
	ChaosSpellRanks, ChaosSpellRanksConfig, ChaosSpellRanksCore, ChaosSpellCombos, ChaosSpellAwakening, ChaosCombatLog, ChaosSpellForms, ChaosPace,
		COMBAT_NONE, ORIGIN_SPELL, Chaos.healthFactor, Game.createMonster, Game.getSpectators = (table.unpack or unpack)(saved, 1, 13)
end

print = origPrint
print(string.format("tester_helper_test: %d checks, %d failures", count, failures))
os.exit(failures == 0 and 0 or 1)
