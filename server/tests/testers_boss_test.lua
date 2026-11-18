-- Run from the server/ folder: luajit tests/testers_boss_test.lua (no engine; CI runs it with luajit and lua5.3)
-- Tester copies of the key bosses (O652, testers_boss.lua, testers_boss_config.lua, boss_mechanics.lua M.dangerFor, bossspawns.lua; server/README.md
-- "The rest of the closed audit (O589)" step 10) on a mocked engine: who may ask, where and when, the copy's mechanics and health, only testers can hurt
-- it, the Boss Spawns tracker never sees it, the probe (telegraph marks, the safe tile, the guide, the kills, the boards), and the close.
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

local n = 0
setmetatable(_G, {__index = function(t, k)
	if type(k) == "string" and k:match("^[A-Z][A-Z_0-9]+$") then n = n + 1; rawset(t, k, n); return n end
end})
RETURNVALUE_NOERROR = 0
local events = {}
local function newEvent(name)
	local e = setmetatable({name = name}, {__index = function() return function() end end})
	function e:type() end
	function e:register() events[name] = e end
	function e:interval() end
	return e
end
CreatureEvent, GlobalEvent, TalkAction, MoveEvent = newEvent, newEvent, newEvent, newEvent
local callbacks = {}
EventCallback = {}
function EventCallback:register()
	for name, fn in pairs(self) do
		if type(fn) == "function" and name ~= "register" then
			callbacks[name] = fn
		end
	end
end
local queue = {}
function addEvent(fn, delay, ...) queue[#queue + 1] = {fn = fn, delay = delay, args = {...}} return #queue end
local realPrint, logged = print, {}
print = function(s) logged[#logged + 1] = tostring(s) end
local clock = 5000000
os.mtime = function() return clock end
db = {query = function() return true end, storeQuery = function() return false end, escapeString = function(s) return "'" .. tostring(s) .. "'" end}

-- positions, tiles, creatures
local PosMT = {}
PosMT.__index = PosMT
function Position(x, y, z) return setmetatable({x = x, y = y, z = z}, PosMT) end
function PosMT:sendMagicEffect() end
local pzOn
function Tile(p)
	return {getGround = function() return {} end, getCreatureCount = function() return 0 end,
		hasFlag = function(_, f) return pzOn and f == TILESTATE_PROTECTIONZONE end, hasProperty = function() return false end}
end
local creatures, nextId = {}, 100
local C = {}
C.__index = C
local function new(kind, t)
	nextId = nextId + 1
	t.id, t.kind, t.events, t.storage = nextId, kind, {}, t.storage or {}
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
function C:getMaster() return nil end
function C:getHealth() return self.health end
function C:getMaxHealth() return self.maxHealth end
function C:setMaxHealth(v) self.maxHealth = v end
function C:addHealth(v) self.health = self.health + v end
function C:registerEvent(name) self.events[#self.events + 1] = name end
function C:getStorageValue(k) return self.storage[k] or -1 end
function C:remove() creatures[self.id] = nil self.removed = true end
function C:getParty() return nil end
function C:getGuid() return self.id + 1000 end
function C:getGroup() return {getId = function() return 1 end} end
function C:getAccountType() return 1 end
function Monster(x) local c = type(x) == "table" and x or creatures[x] return c and c.kind == "monster" and c or nil end
function Player(x) local c = creatures[x] return c and c.kind == "player" and c or nil end
local spectators = {}
local made = {}
Game = {getSpectators = function() return spectators end, getPlayers = function() return {} end, broadcastMessage = function() return true end,
	getStorageValue = function() return -1 end}
function Game.createMonster(typeName, pos, extended, force)
	made[#made + 1] = {name = typeName, creating = ChaosTestersBoss and ChaosTestersBoss.creating, force = force}
	if typeName == "Missing Boss" then return nil end
	return new("monster", {name = typeName, pos = {x = pos.x, y = pos.y, z = pos.z}, maxHealth = 1000000})
end
ChaosTitles = {register = function() end}

dofile("data/scripts/chaos/chaos_constants.lua")
dofile("data/scripts/chaos/i18n_core.lua")
local okT = pcall(dofile, "data/scripts/chaos/testers.lua")
check(okT, "testers.lua loads")
local okM, eM = pcall(dofile, "data/scripts/chaos/boss_mechanics.lua")
check(okM, "boss_mechanics.lua loads: " .. tostring(eM))
dofile("data/scripts/chaos/bosslair_core.lua")
Chaos.bossLairConfig = dofile("data/scripts/chaos/bosslair_config.lua")
local okB, eB = pcall(dofile, "data/scripts/chaos/testers_boss.lua")
check(okB, "testers_boss.lua loads: " .. tostring(eB))
local B, M, X, G = ChaosTestersBoss, ChaosBossMech, ChaosTesters, ChaosBossMechCore
local cfg = Chaos.testersBossConfig
check(B and B.testerSpawn and B.probe and B.testerClose and B.pick, "the functions are there")

-- ------------------------------------------------------------------ the config
check(cfg.clearRadius >= 20 and cfg.lairGuard >= 20 and cfg.reach >= 1 and cfg.healthShare > 0 and cfg.healthShare <= 0.2 and cfg.lifeSeconds >= 60, "config: the numbers")
for _, name in ipairs(cfg.bosses) do
	local p = M.profileOf(name)
	check(p and #(p.telegraphs or {}) > 0, "config: " .. name .. " has a mechanics profile with telegraphs")
	check((M.fairOf(name).refLevel or 0) > 0, "config: " .. name .. " has a level")
end

-- ------------------------------------------------------------------ the pick
local nm, lv = B.pick(100)
check(nm == nil and lv:find("under the lowest", 1, true), "a level under the lowest boss: no boss")
nm, lv = B.pick(300)
check(nm ~= nil and lv == 300, "level 300: a boss of 300")
nm, lv = B.pick(700)
check(nm ~= nil and lv >= 650 and lv <= 700, "level 700: the highest boss it reaches (" .. tostring(nm) .. " " .. tostring(lv) .. ")")
nm = B.pick(2000, "talath")
eq(nm, "Talath", "a part of a name asks for that boss")
nm, lv = B.pick(2000, "nobody")
check(nm == nil and lv == "no such boss for this level", "an unknown name")

-- ------------------------------------------------------------------ the spawn
local function player(name, tester, pos, level)
	local p = new("player", {name = name, level = level or 700, pos = pos or {x = 100, y = 100, z = 7}})
	if tester then p.storage[Chaos.storage.tester] = 1 end
	return p
end
local bot, human = player("Tester Bos", true), player("Ana", false, {x = 400, y = 400, z = 7})
local attached
M.attach = function(monster, key, opts) attached = {monster = monster, opts = opts} return {} end
local m1, why1 = B.testerSpawn(human)
check(m1 == nil and why1 == "not a tester", "never for a player")
spectators = {human}
local m2, why2 = B.testerSpawn(bot)
check(m2 == nil and why2:find("a player is near", 1, true), "refused while a player is near: " .. tostring(why2))
spectators = {bot}
pzOn = true
local m3, why3 = B.testerSpawn(bot)
check(m3 == nil and why3 == "the bot stands in a protection zone", "refused in a protection zone")
pzOn = nil
local low = player("Tester Low", true, nil, 100)
local m4, why4 = B.testerSpawn(low)
check(m4 == nil and why4:find("under the lowest", 1, true), "refused under the lowest boss level")
-- a lair near: the real boss is the players'
local lair = Chaos.bossLairConfig.lairs[1]
local lp = ChaosBossLairCore.bossPos(lair)
local near = player("Tester Lair", true, {x = lp.x + 5, y = lp.y, z = lp.z})
local m5, why5 = B.testerSpawn(near)
check(m5 == nil and why5:find("the lair of talath is near", 1, true), "refused near a lair's boss spawn: " .. tostring(why5))
local far = player("Tester Far", true, {x = lp.x + 5 + Chaos.testersBossConfig.lairGuard, y = lp.y, z = lp.z}, 650)
spectators = {far}
local mf, whyF = B.testerSpawn(far, "talath")
check(mf ~= nil, "outside the guard: a copy (" .. tostring(whyF) .. ")")
B.testerClose(far)

local before = #logged
spectators = {bot}
local boss = B.testerSpawn(bot)
check(boss ~= nil, "a tester gets a copy")
check(made[#made].creating == true and made[#made].force == true, "made with the creating flag up (the Boss Spawns tracker leaves it alone)")
eq(B.creating, false, "the flag is down again")
check(X.worldSide(boss) == "testers", "marked as the testers' own")
eq(boss.events[1], "ChaosTestersWorldTaken", "the guard event comes first")
eq(boss.events[2], "ChaosTestersBossDeath", "then the kill counter")
eq(boss.maxHealth, math.floor(1000000 * cfg.healthShare), "a small share of the health")
eq(boss.health, boss.maxHealth, "at full health")
check(attached and attached.monster == boss and attached.opts.solo == true and attached.opts.radius == cfg.arenaRadius, "the mechanics are attached with a box arena, solo")
check(attached.opts.players()[1] == bot and #attached.opts.players() == 1, "the fight counts the bot only")
local d = math.max(math.abs(boss.pos.x - 100), math.abs(boss.pos.y - 100))
check(d >= cfg.spotDistance - 1 and d <= cfg.spotDistance + 1, "it stands a few tiles from the bot")
check(B.isCopy(boss) and not B.isCopy(bot), "isCopy")
local again, whyA = B.testerSpawn(bot)
check(again == nil and whyA == "the bot has a boss copy already", "one at a time")
local line = false
for i = before + 1, #logged do if logged[i]:find("TEST ONLY: a copy of", 1, true) and logged[i]:find("Tester Bos", 1, true) then line = true end end
check(line, "the grant is logged")
check(queue[#queue].delay == cfg.lifeSeconds * 1000, "a removal is queued after the copy's life")

-- only testers can hurt it
local guard = events.ChaosTestersWorldTaken.onHealthChange
eq(guard(boss, human, 100, COMBAT_PHYSICALDAMAGE, 0, 0), 0, "a player's hit on the copy is cancelled")
eq(guard(boss, bot, 100, COMBAT_PHYSICALDAMAGE, 0, 0), 100, "the bot's hit lands")

-- the Boss Spawns tracker: the creating flag is what bossspawns.lua reads
local f = io.open("data/scripts/chaos/bossspawns.lua", "r")
local src = f:read("*a")
f:close()
check(src:find("ChaosTestersBoss and ChaosTestersBoss.creating", 1, true) ~= nil, "bossspawns.lua leaves a copy alone")
check(src:find("return true -- O652", 1, true) ~= nil, "and says why")

-- ------------------------------------------------------------------ the probe: no danger, then telegraphs
local pr = B.probe(bot)
check(pr.boss and pr.boss.hp == 100 and pr.boss.name == "Talath" and pr.boss.left == cfg.lifeSeconds, "probe: the copy (the boss for level 700), its health, its time")
eq(pr.killed, 0, "probe: no kill yet")
eq(pr.listed, 0, "probe: no tester in a boss board")
check(pr.guide.mode == "walk" and pr.guide.area == "boss" and pr.guide.reach[2] == cfg.reach, "probe: far: walk to it")
bot.pos = {x = boss.pos.x - 3, y = boss.pos.y, z = 7}
pr = B.probe(bot)
eq(pr.guide.mode, "fight", "probe: in reach: fight")
check(pr.danger == nil, "probe: no mark up")

-- a telegraph: a fight with marks over the bot's tile (boss_mechanics.lua M.dangerFor on its own state)
local tiles = {}
for x = boss.pos.x - 8, boss.pos.x + 8 do
	for y = boss.pos.y - 8, boss.pos.y + 8 do
		tiles[#tiles + 1] = {x = x, y = y, z = 7}
	end
end
local mark = {}
for x = bot.pos.x - 1, bot.pos.x + 1 do
	for y = bot.pos.y - 1, bot.pos.y + 1 do
		mark[G.key(x, y)] = true
	end
end
M.fights[boss:getId()] = {profile = {fair = {refLevel = 650}}, grid = G.grid(tiles), danger = {
	{tel = {set = mark, tiles = {}}, hitAt = clock + 2500, label = "Frost Lance"},
	{tel = {set = {}, tiles = {}}, hitAt = clock - 5000, label = "old"}}}
local dg = M.dangerFor(boss:getId(), bot.pos)
check(dg and dg.count == 1 and dg.left == 2500 and dg.labels[1] == "Frost Lance", "dangerFor: one pending mark (the old one is gone), the time to the hit")
check(dg.goal and not mark[G.key(dg.goal.x, dg.goal.y)] and math.max(math.abs(dg.goal.x - bot.pos.x), math.abs(dg.goal.y - bot.pos.y)) == 2,
	"dangerFor: the safe tile is the nearest outside the mark (two steps off)")
check(M.dangerFor(999, bot.pos) == nil and M.dangerFor(boss:getId(), {x = 1, y = 1, z = 7}).goal == nil, "dangerFor: no fight, no goal on a safe tile")
pr = B.probe(bot)
check(pr.guide.mode == "dodge" and pr.guide.goal.x == dg.goal.x and pr.guide.goal.y == dg.goal.y, "probe: the bot stands in the mark: dodge to the safe tile")
check(pr.danger.here == true and pr.danger.count == 1 and #pr.danger.tiles == 9 and pr.danger.left == 2500, "probe: the danger, the bot's tile marked, the tiles")
bot.pos = {x = dg.goal.x, y = dg.goal.y, z = 7}
pr = B.probe(bot)
check(pr.guide.mode == "fight" and pr.danger.here == false, "probe: off the mark: fight again, the mark still shows")
-- no safe tile within the time left: no goal, the bot fights on
M.fights[boss:getId()].grid = G.grid({{x = bot.pos.x, y = bot.pos.y, z = 7}})
M.fights[boss:getId()].danger[1].tel.set = {[G.key(bot.pos.x, bot.pos.y)] = true}
pr = B.probe(bot)
check(pr.guide.mode == "fight" and pr.danger.here == true, "probe: no tile to go to: fight on")
M.fights[boss:getId()] = nil

-- the kill: counted for the owner only
local corpse = {}
events.ChaosTestersBossDeath.onDeath(boss, corpse, bot, bot)
eq(B.killed[bot:getId()], 1, "the kill is counted")
check(B.copyOf(bot) == nil, "the copy is gone from the table")
eq(B.probe(bot).killed, 1, "probe: killed")
check(B.probe(bot).guide.mode == "wait", "probe: wait for the next copy")
-- the boss points, as the bot's own storage
ChaosBossPoints = {count = function() return 3 end}
eq(B.probe(bot).points, 3, "probe: the boss passive points of the bot")
ChaosBossPoints = nil
-- a board naming a tester: counted (must be 0)
ChaosBossSpawns = {state = {rows = {{by = "Ana"}}}}
eq(B.listed(), 0, "no board names a tester")
ChaosBossSpawns = {state = {rows = {{by = "Tester Bos"}}}}
Chaos.testerGuids[bot:getGuid()] = bot:getName()
eq(B.listed(), 1, "a kill row that names a tester is counted")
ChaosBossSpawns = nil

-- the close and the removal of a copy that nobody kills
spectators = {bot}
local boss2 = B.testerSpawn(bot)
check(boss2 ~= nil, "another copy once the first is gone")
eq(B.testerClose(human), false, "close: a player has none")
eq(B.testerClose(bot), true, "close: the bot's copy goes")
check(boss2.removed and B.copyOf(bot) == nil, "close: removed")
eq(B.testerClose(bot), false, "close: nothing to close twice")
local boss3 = B.testerSpawn(bot)
local life = queue[#queue]
life.fn(table.unpack and table.unpack(life.args) or unpack(life.args))
check(boss3.removed and B.copyOf(bot) == nil, "the copy of nobody's kill is removed after its life")
local gone, whyG = B.testerSpawn(bot, "Missing")
check(gone == nil, "a name that matches no boss gives no copy: " .. tostring(whyG))

print = realPrint
print(string.format("testers_boss_test: %d checks, %d failed", count, failures))
if failures > 0 then os.exit(1) end
