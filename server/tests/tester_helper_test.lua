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
	check(htext:find("HELPER_VERSION = 21", 1, true) ~= nil, "the helper is v21 (O652)")
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
	check(bad == nil and usage == "usage: journey [state | jump | hall] [keep ID] [skip ID,ID]", "journey: an unknown word is the usage")
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

print = origPrint
print(string.format("tester_helper_test: %d checks, %d failures", count, failures))
os.exit(failures == 0 and 0 or 1)
