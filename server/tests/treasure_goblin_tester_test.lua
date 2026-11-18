-- Run from the server/ folder: luajit tests/treasure_goblin_tester_test.lua (CI runs it with LuaJIT and Lua 5.3)
-- The tester bots and the treasure goblin (O650, server/README.md "Tester bots", step 9): treasure_goblin.lua and testers.lua on a mocked engine.
-- A world goblin is the players' (a tester's hit on it is cancelled, so it never takes the hoard of a player); `TG.testerSpawn` makes a goblin
-- of the bot's own (TEST ONLY, a tester only, only while no player is near), only the testers can hurt it, it says nothing to anybody, its
-- probe gives the bot a guide, its kill is counted, and `TG.testerClose` takes it away.
local n = 0
setmetatable(_G, {__index = function(t, k)
	if type(k) == "string" and k:match("^[A-Z][A-Z_0-9]+$") then n = n + 1; rawset(t, k, n); return n end
end})
local fails, checks = 0, 0
local function ok(cond, what)
	checks = checks + 1
	if not cond then fails = fails + 1; io.write("FAIL " .. what .. "\n") end
end
local function eq(a, b, what) ok(a == b, what .. ": " .. tostring(a) .. " ~= " .. tostring(b)) end

local events = {}
local function newEvent(name)
	local e = setmetatable({name = name}, {__index = function() return function() end end})
	function e:type() end
	function e:register() events[name] = self end
	function e:interval() end
	return e
end
CreatureEvent, GlobalEvent, TalkAction = newEvent, newEvent, newEvent
EventCallback = setmetatable({}, {__newindex = function() end, __index = function(t, k) if k == "register" then return function() end end end})
local queue = {}
function addEvent(fn, delay, ...) queue[#queue + 1] = {fn = fn, delay = delay, args = {...}} return #queue end
local realPrint, logged = print, {}
print = function(s) logged[#logged + 1] = tostring(s) end
local clock = 1000000
os.mtime = function() return clock end

-- positions, tiles, creatures
local PosMT = {}
PosMT.__index = PosMT
function Position(x, y, z) return setmetatable({x = x, y = y, z = z}, PosMT) end
function PosMT:sendMagicEffect() end
local blocked = {}
function Tile(p)
	if blocked[p.x .. ":" .. p.y .. ":" .. p.z] then return nil end
	return {getGround = function() return {} end, getCreatureCount = function() return 0 end,
		hasFlag = function(_, f) return pzOn and f == TILESTATE_PROTECTIONZONE end}
end
local creatures, nextId = {}, 100
local C = {}
C.__index = C
local function new(kind, t)
	nextId = nextId + 1
	t.id, t.kind, t.events, t.storage, t.msgs = t.id or nextId, kind, {}, t.storage or {}, {}
	t.health = t.health or t.maxHealth or 100
	creatures[t.id] = setmetatable(t, C)
	return t
end
function C:getId() return self.id end
function C:isPlayer() return self.kind == "player" end
function C:isMonster() return self.kind == "monster" end
function C:getName() return self.name end
function C:getLevel() return self.level end
function C:getPosition() return Position(self.pos.x, self.pos.y, self.pos.z) end
function C:getMaster() return self.master end
function C:getHealth() return self.health end
function C:getMaxHealth() return self.maxHealth end
function C:setMaxHealth(v) self.maxHealth = v end
function C:setHealth(v) self.health = v end
function C:getOutfit() return {} end
function C:setOutfit() end
function C:registerEvent(name) self.events[#self.events + 1] = name end
function C:getStorageValue(k) return self.storage[k] or -1 end
function C:remove() creatures[self.id] = nil self.removed = true end
function C:getSpeed() return 200 end
function C:addExperience() return true end
function C:getParty() return nil end
function Monster(x) local c = type(x) == "table" and x or creatures[x] return c and c.kind == "monster" and c or nil end
local spectators = {}
Game = {getSpectators = function() return spectators end}
function Game.createMonster(typeName, pos)
	return new("monster", {name = typeName, pos = {x = pos.x, y = pos.y, z = pos.z}, maxHealth = 400})
end

dofile("data/scripts/chaos/chaos_constants.lua")
dofile("data/scripts/chaos/i18n_core.lua")
local okTesters, eT = pcall(dofile, "data/scripts/chaos/testers.lua")
ok(okTesters, "testers.lua loads: " .. tostring(eT))
local okG, eG = pcall(dofile, "data/scripts/chaos/treasure_goblin.lua")
ok(okG, "treasure_goblin.lua loads: " .. tostring(eG))
local TG, X = ChaosTreasureGoblin, ChaosTesters
ok(TG and TG.testerSpawn and TG.probe and TG.testerClose, "the tester functions are there")
ChaosSpeed = ChaosSpeed or {effective = function() return 200 end}
ok(ChaosTreasureGoblinConfig.tester.clearRadius >= 10 and ChaosTreasureGoblinConfig.tester.reach >= 1, "config: the bots' numbers")

local function player(name, tester, pos)
	local p = new("player", {name = name, level = 150, pos = pos or {x = 100, y = 100, z = 7}})
	if tester then p.storage[Chaos.storage.tester] = 1 end
	return p
end
local bot, human = player("Tester Gob", true), player("Ana", false, {x = 300, y = 300, z = 7})

-- a goblin of the world: marked as the players'
local world = Game.createMonster("Treasure Goblin", Position(200, 200, 7))
TG.spawn(Position(200, 200, 7), {})
local w
for id, st in pairs(TG.alive) do if not st.tester then w = id end end
ok(w ~= nil and X.worldSide(creatures[w]) == "players", "a world goblin is marked as the players'")
eq(TG.probe(bot).world, 1, "probe: one world goblin alive")

-- the goblin of its own
local m1, why1 = TG.testerSpawn(human)
ok(m1 == nil and why1 == "not a tester", "never for a player")
spectators = {human}
local m2, why2 = TG.testerSpawn(bot)
ok(m2 == nil and why2:find("a player is near", 1, true), "refused while a player is near: " .. tostring(why2))
spectators = {bot}
pzOn = true
local m3, why3 = TG.testerSpawn(bot)
ok(m3 == nil and why3 == "the bot stands in a protection zone", "refused in a protection zone")
pzOn = nil
local p0 = TG.probe(bot)
ok(p0.goblin == nil and p0.guide.mode == "wait" and p0.killed == 0, "probe: no goblin of its own yet")
local gob = TG.testerSpawn(bot)
ok(gob ~= nil and X.worldSide(gob) == "testers", "a tester gets a goblin of its own, marked as the testers'")
local st = TG.alive[gob:getId()]
ok(st.tester == true and st.owner == bot:getId() and st.level == 150, "its state: the bot's, at the bot's level")
ok(gob.events[1] == "ChaosTestersWorldTaken" and gob.events[2] == "ChaosTreasureGoblinHit", "the guard is registered before the goblin's own hit event")
ok(math.max(math.abs(gob.pos.x - 100), math.abs(gob.pos.y - 100)) >= 4, "it appears a few tiles from the bot")
local again, whyA = TG.testerSpawn(bot)
ok(again == nil and whyA == "the bot has a goblin already", "one at a time")
local logLine = false
for _, l in ipairs(logged) do if l:find("TEST ONLY: a goblin of its own made for tester Tester Gob", 1, true) then logLine = true end end
ok(logLine, "the grant is logged")
-- it says nothing to a player near it (no appear text for a testers' goblin)
local told = 0
human.sendTextMessage = function() told = told + 1 end
spectators = {human, bot}
queue = {}
TG.tick(gob:getId())
eq(told, 0, "a testers' goblin announces nothing")
-- the probe: where, how hurt, the guide
local pr = TG.probe(bot)
ok(pr.goblin and pr.goblin.hit == false and pr.goblin.hp == 100 and pr.goblin.left == nil, "probe: the goblin, not hit yet")
eq(pr.guide.mode, "fight", "probe: within 5 tiles, fight")
gob.pos = {x = 120, y = 100, z = 7}
local pf = TG.probe(bot)
ok(pf.guide.mode == "walk" and pf.guide.area == "goblin" and pf.guide.reach[2] == 5 and pf.guide.goal.x == 120, "probe: far, walk to it")
-- only the testers hurt it
local guard = events.ChaosTestersWorldTaken.onHealthChange
local d1 = guard(gob, human, 100, COMBAT_PHYSICALDAMAGE, 0, 0)
local d2 = guard(gob, bot, 100, COMBAT_PHYSICALDAMAGE, 0, 0)
ok(d1 == 0 and d2 == 100, "a player's hit on it is cancelled, the bot's lands")
-- the world goblin: the bot's hit is cancelled and counted
local d3 = guard(creatures[w], bot, 100, COMBAT_PHYSICALDAMAGE, 0, 0)
ok(d3 == 0 and TG.probe(bot).cancelled == 1, "a tester's hit on a world goblin is cancelled and counted in its probe")
-- the kill: counted for the bot, no line to the area, the hoard is the bot's own corpse
local corpse = {isContainer = function() return true end}
local killed = events.ChaosTreasureGoblinDeath.onDeath(gob, corpse, bot, bot)
ok(killed == true and TG.testerKilled[bot:getId()] == 1 and TG.alive[gob:getId()] == nil, "the kill is counted for the bot")
eq(TG.probe(bot).killed, 1, "probe: killed")
eq(told, 0, "the kill says nothing to the players near")
-- the close
spectators = {bot}
local gob2 = TG.testerSpawn(bot)
ok(gob2 ~= nil, "another goblin once the first is gone")
eq(TG.testerClose(human), false, "close: a player has none")
eq(TG.testerClose(bot), true, "close: the bot's goblin goes")
ok(gob2.removed == true and TG.alive[gob2:getId()] == nil, "close: removed")
eq(TG.testerClose(bot), false, "close: nothing to close twice")

print = realPrint
print(string.format("treasure_goblin_tester_test: %d checks, %d failures", checks, fails))
if fails > 0 then os.exit(1) end
