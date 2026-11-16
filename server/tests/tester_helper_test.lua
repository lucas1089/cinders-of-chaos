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

print = origPrint
print(string.format("tester_helper_test: %d checks, %d failures", count, failures))
os.exit(failures == 0 and 0 or 1)
