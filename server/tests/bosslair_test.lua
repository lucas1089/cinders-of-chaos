-- Run from the server/ folder: luajit tests/bosslair_test.lua (or lua5.3; CI runs both)
-- Boss lairs (O616, Talath's lair): the client pair gate, the config, the spawn rule, the Boss Spawns entry, the
-- plan's boss block and Talath's file, and bosslair.lua against a mocked engine (the portal at startup, open and
-- closed; stepping on it; the refused spawn).
local n = 0
setmetatable(_G, {__index = function(t, k)
	if type(k) == "string" and k:match("^[A-Z_0-9]+$") then n = n + 1; rawset(t, k, n); return n end
end})
loadstring = loadstring or load
dofile("data/scripts/chaos/chaos_constants.lua")
dofile("data/scripts/chaos/bosslair_core.lua")
local L = ChaosBossLairCore
local cfg = dofile("data/scripts/chaos/bosslair_config.lua")

local failures, count = 0, 0
local function check(cond, label)
	count = count + 1
	if not cond then
		failures = failures + 1
		print("FAIL " .. label)
	end
end
local function eq(a, b, label)
	check(a == b, label .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end
local function read(path)
	local f = assert(io.open(path, "r"), path)
	local s = f:read("*a")
	f:close()
	return s
end

-- ---------------------------------------------------------------- the pair gate
eq(L.parsePair("a = 1\nchaosClientPair = 73\n"), 73, "the pair of a config text")
eq(L.parsePair("chaosClientPair = 72 -- note"), 72, "the only line, with a comment")
eq(L.parsePair("x = 1\nchaosClientPair = 72 -- note\ny = 2\n"), 72, "a middle line, with a comment")
eq(L.parsePair("-- chaosClientPair = 73\n"), nil, "a commented line is no pair")
eq(L.parsePair("x = 1\n"), nil, "no key")
eq(L.parsePair(nil), nil, "no text")
eq(L.recordedPair("no/such/config.lua"), nil, "no config file")

local talath = cfg.lairs[1]
eq(#cfg.lairs, 2, "two lairs: Talath and Malgrath")
eq(talath.monster, "Talath", "Talath's lair")
eq(talath.pair, 73, "open from client pair 73, where look 3529 exists")
check(not L.open(talath, 72) and not L.open(talath, nil) and L.open(talath, 73) and L.open(talath, 80), "open at 73 and above only")
check(L.open({}, 0), "a lair without a pair is open")
check(not L.open(nil, 99), "no lair")

-- ---------------------------------------------------------------- the config
eq(table.concat(L.validate(cfg), "; "), "", "the config is sound")
eq(cfg.aid, 47890, "the lair portals' action id")
local bad = L.validate({aid = 1, lairs = {
	{key = "a", monster = "A", at = {x = 1, y = 1, z = 7}, portal = {x = 5, y = 5, z = 7}, back = {x = 5, y = 5, z = 7},
		arrival = {1, 1, 0}, boss = {2, 2, 0}, respawn = 600},
	{key = "a", monster = "a", at = {x = 1, y = 1, z = 7}, portal = {x = 5, y = 5, z = 7}, back = {x = 5, y = 6, z = 7},
		arrival = {1, 1, 0}, respawn = 5, pair = "x"}}})
local text = table.concat(bad, "; ")
for _, want in ipairs({"aid is not in the block", "leads onto the portal", "key twice", "monster in two lairs",
	"arrival and boss are offsets", "no respawn time", "pair is not a client pair"}) do
	check(text:find(want, 1, true) ~= nil, "validate names: " .. want .. " (" .. text .. ")")
end
eq(L.validate({})[1], "no lairs", "no lairs")

local arr = L.arrival(talath)
eq(arr.x .. "," .. arr.y .. "," .. arr.z, "15878,15571,7", "the arrival")
local bp = L.bossPos(talath)
eq(bp.x .. "," .. bp.y .. "," .. bp.z, "15880,15517,7", "the boss's spawn point")
eq(L.offset(talath, nil), nil, "no offset")
check(talath.back.x == talath.portal.x and talath.back.y == talath.portal.y + 2, "the way back lands two tiles south of the portal")

-- ---------------------------------------------------------------- the spawn rule and the way in
check(not L.allowSpawn(cfg, "Talath", 72), "Talath does not spawn below pair 73")
check(not L.allowSpawn(cfg, "talath", nil), "nor without a recorded pair")
check(L.allowSpawn(cfg, "Talath", 73), "Talath spawns at pair 73")
check(L.allowSpawn(cfg, "Skaldra the Rime Queen", 0) and L.allowSpawn(cfg, "Rat", nil), "every other monster spawns")
check(L.allowSpawn({enabled = false, lairs = cfg.lairs}, "Talath", 0), "the system switched off refuses nothing")
check(L.allowSpawn(nil, "Talath", 0), "no config refuses nothing")
eq(L.byMonster(cfg, "TALATH"), talath, "by monster, any case")
eq(L.byMonster(cfg, "Saga"), nil, "another monster has no lair")
eq(L.enter(talath, 72, 900), "closed", "the portal of a closed lair lets nobody in")
eq(L.enter(talath, 73, talath.minLevel - 1), "level", "too low a level")
local what, to = L.enter(talath, 73, talath.minLevel)
check(what == "enter" and to.x == arr.x and to.y == arr.y and to.z == arr.z, "at the level: to the arrival")

-- ---------------------------------------------------------------- the plan, the monster file, the Boss Spawns entry
local plan = read("tools/areaplan/rooms/" .. talath.plan .. ".json")
eq(plan:match('"boss"%s*:%s*{[^}]-"monster"%s*:%s*"([^"]+)"'), "Talath", "the plan's boss")
eq(tonumber(plan:match('"boss"%s*:%s*{[^}]-"respawn"%s*:%s*(%d+)')), talath.respawn, "the plan's respawn is the config's")
eq(talath.respawn, 14400, "back 4 hours after the kill")
check(plan:find('"biome"%s*:%s*"ice"') ~= nil, "an ice area")
local ox, oy, oz = plan:match('"origin"%s*:%s*{%s*"x"%s*:%s*(%d+),%s*"y"%s*:%s*(%d+),%s*"z"%s*:%s*(%d+)')
eq(ox .. "," .. oy .. "," .. oz, talath.at.x .. "," .. talath.at.y .. "," .. talath.at.z, "the config's `at` is the plan's origin")
local tx, ty = plan:match('"exit"%s*:%s*{.-"to"%s*:%s*{%s*"x"%s*:%s*(%d+),%s*"y"%s*:%s*(%d+)')
eq(tx .. "," .. ty, talath.back.x .. "," .. talath.back.y, "the plan's exit leads to the config's `back`")
check(io.open("tools/areaplan/plans/" .. talath.hunt .. ".json", "r") ~= nil, "the hunt's plan exists")

local xml = read("data/monster/monsters/chaos/talath.xml")
-- 800 was the donor's number, three times our bosses': Talath walks as Skaldra the Rime Queen, the ice world boss
eq(tonumber(xml:match('<monster name="Talath"[^>]-speed="(%d+)"')), 280, "Talath's speed")
local skaldra = read("data/monster/monsters/chaos/world_bosses/skaldra_the_rime_queen.xml")
eq(tonumber(skaldra:match('<monster[^>]-speed="(%d+)"')), 280, "Skaldra's speed")
eq(tonumber(xml:match('<look type="(%d+)"')), 1473, "the repository file keeps the old look (step monstercreaturelooks moves it at pair 73)")
local looks = read("data/monster/monster_creature_looks.csv")
check(looks:find("Talath,1473,3529", 1, true) ~= nil, "look 3529 from pair 73")
local mech = dofile("data/scripts/chaos/boss_mechanics_config.lua")
local function find(tbl, key, depth)
	if type(tbl) ~= "table" or depth > 4 then return nil end
	if type(tbl[key]) == "table" and tbl[key].label then return tbl[key] end
	for _, v in pairs(tbl) do
		local r = find(v, key, depth + 1)
		if r then return r end
	end
end
local tm = find(mech, "talath", 0)
check(tm and tm.element == "ice", "Talath's mechanics are ice")

local bcfg = dofile("data/scripts/chaos/bossspawns_config.lua")
dofile("data/scripts/chaos/bossspawns_core.lua")
local K = ChaosBossSpawnsCore
local entry
for _, e in ipairs(bcfg.bosses) do
	if e.key == "lair_talath" then entry = e end
end
check(entry ~= nil, "the Boss Spawns window has Talath")
eq(entry.minPair, talath.pair, "listed from the lair's pair")
eq(entry.rule.seconds, talath.respawn, "the window's timer is the respawn")
eq(entry.pos.x .. "," .. entry.pos.y .. "," .. entry.pos.z, bp.x .. "," .. bp.y .. "," .. bp.z, "tracked at the boss's spawn point")
eq(entry.category, "lair", "a lair boss")
local function listed(pair)
	local idx = K.build(bcfg, {clientPair = pair})
	eq(#idx.problems, 0, "no config problems at pair " .. tostring(pair))
	return idx.byKey.lair_talath ~= nil, idx.byKey.lair_vharzul ~= nil
end
local a, b = listed(72)
check(not a and b, "pair 72: Talath is not listed, the others are")
a, b = listed(nil)
check(not a and b, "no pair: not listed")
a, b = listed(73)
check(a and b, "pair 73: listed")

-- the texts have pt-BR
local pt = dofile("data/scripts/chaos/i18n_strings.lua")["pt-BR"]
local src = read("data/scripts/chaos/bosslair.lua")
local texts = 0
for lit in src:gmatch('t%(player, "([^"]+)"') do
	texts = texts + 1
	check(pt[lit] ~= nil, "pt-BR for \"" .. lit .. "\"")
end
eq(texts, 3, "three player texts")

-- ---------------------------------------------------------------- Malgrath, the Drowned Crown (O637)
local mal = cfg.lairs[2]
eq(mal.key, "malgrath", "the second lair is Malgrath's")
eq(mal.monster, "Malgrath, the Drowned Crown", "Malgrath's lair")
eq(mal.pair, 74, "open from client pair 74, where outfit 3530 and its eight attack effects exist")
check(not L.open(mal, 73) and not L.open(mal, nil) and L.open(mal, 74), "open at 74 and above only")
check(not L.allowSpawn(cfg, "Malgrath, the Drowned Crown", 73) and L.allowSpawn(cfg, "Malgrath, the Drowned Crown", 74), "Malgrath spawns at pair 74 only")
check(not L.allowSpawn(cfg, "malgrath, the drowned crown", nil), "nor without a recorded pair")
check(L.allowSpawn(cfg, "Talath", 73), "Talath still spawns at 73")
eq(L.byMonster(cfg, "MALGRATH, THE DROWNED CROWN"), mal, "by monster, any case")
eq(L.enter(mal, 73, 900), "closed", "the portal of a closed lair lets nobody in")
eq(L.enter(mal, 74, mal.minLevel - 1), "level", "too low a level")
check(mal.back.x == mal.portal.x and mal.back.y == mal.portal.y + 2, "the way back lands two tiles south of the portal")
check(mal.portal.x ~= talath.portal.x or mal.portal.y ~= talath.portal.y, "two portals on two tiles")
local mplan = read("tools/areaplan/rooms/" .. mal.plan .. ".json")
eq(mplan:match('"boss"%s*:%s*{[^}]-"monster"%s*:%s*"([^"]+)"'), mal.monster, "the plan's boss")
eq(tonumber(mplan:match('"boss"%s*:%s*{[^}]-"respawn"%s*:%s*(%d+)')), mal.respawn, "the plan's respawn is the config's")
check(mplan:find('"biome"%s*:%s*"abyss"') ~= nil, "an abyss area")
local mx, my, mz = mplan:match('"origin"%s*:%s*{%s*"x"%s*:%s*(%d+),%s*"y"%s*:%s*(%d+),%s*"z"%s*:%s*(%d+)')
eq(mx .. "," .. my .. "," .. mz, mal.at.x .. "," .. mal.at.y .. "," .. mal.at.z, "the config's `at` is the plan's origin")
local mxml = read("data/monster/monsters/chaos/malgrath_the_drowned_crown.xml")
eq(mxml:match('<monster name="([^"]+)"'), mal.monster, "the monster file's name")
eq(tonumber(mxml:match('<look type="(%d+)"')), 1473, "the repository file keeps the old look (step monstermalgrathlook moves it at pair 74)")
local mlooks = read("data/monster/monster_malgrath_looks.csv")
check(mlooks:find('"Malgrath, the Drowned Crown",1473,3530', 1, true) ~= nil, "look 3530 from pair 74")
local mm = find(mech, "malgrath, the drowned crown", 0)
check(mm and mm.element == "death" and mm.fair.refLevel == 800, "Malgrath's mechanics are death, fair for level 800")
local mentry
for _, e in ipairs(bcfg.bosses) do
	if e.key == "lair_malgrath" then mentry = e end
end
check(mentry ~= nil and mentry.minPair == 74 and mentry.category == "lair" and mentry.level == 800, "the Boss Spawns window has Malgrath from pair 74")
local mbp = L.bossPos(mal)
eq(mentry.pos.x .. "," .. mentry.pos.y .. "," .. mentry.pos.z, mbp.x .. "," .. mbp.y .. "," .. mbp.z, "tracked at the boss's spawn point")
eq(mentry.rule.seconds, mal.respawn, "the window's timer is the respawn")
do
	local idx73 = K.build(bcfg, {clientPair = 73})
	local idx74 = K.build(bcfg, {clientPair = 74})
	check(idx73.byKey.lair_malgrath == nil and idx73.byKey.lair_talath ~= nil, "pair 73: Malgrath is not listed, Talath is")
	check(idx74.byKey.lair_malgrath ~= nil and #idx74.problems == 0, "pair 74: listed")
end

-- ---------------------------------------------------------------- bosslair.lua on a mocked engine
local tiles, created, events = {}, {}, {}
local function key(p) return p.x .. "," .. p.y .. "," .. p.z end
local function ground(p) tiles[key(p)] = {items = {}} end
ground(talath.portal)
ground(arr)
function Position(x, y, z)
	return {x = x, y = y, z = z, sendMagicEffect = function() end}
end
function Tile(p)
	local t = tiles[key(p)]
	if not t then return nil end
	return {getGround = function() return true end, getItems = function() return t.items end}
end
Game = {createItem = function(id, _count, p)
	local t = tiles[key(p)]
	if not t then return nil end
	local it = {id = id, aid = 0, attrs = {}}
	function it:getActionId() return self.aid end
	function it:setActionId(v) self.aid = v end
	function it:setAttribute(k, v) self.attrs[k] = v end
	function it:remove()
		for i, o in ipairs(t.items) do
			if o == self then table.remove(t.items, i) end
		end
	end
	t.items[#t.items + 1] = it
	created[#created + 1] = it
	return it
end}
function GlobalEvent(name)
	local e = {name = name}
	function e:register() events[name] = self end
	return e
end
local stepEvent
function MoveEvent()
	local e = {}
	function e:type(v) self.kind = v end
	function e:aid(v) self.actionId = v end
	function e:register() stepEvent = self end
	return e
end
local spawnCb
EventCallback = setmetatable({}, {__index = {register = function(self) spawnCb = rawget(self, "onSpawn") end}})
local creatureEvents = {}
function CreatureEvent(name)
	local e = {name = name}
	function e:register() creatureEvents[name] = self end
	return e
end
Chaos.t = function(_player, text, ...)
	return select("#", ...) > 0 and string.format(text, ...) or text
end

ChaosBossLair = {pair = 72}
dofile("data/scripts/chaos/bosslair.lua")
local X = ChaosBossLair
check(events.ChaosBossLairStartup ~= nil and stepEvent ~= nil and spawnCb ~= nil, "startup, step and spawn events registered")
eq(stepEvent.actionId, cfg.aid, "the step event listens on the lairs' action id")

-- closed: no portal, no spawn
events.ChaosBossLairStartup.onStartup()
eq(#created, 0, "pair 72: no portal placed")
local function mon(name) return {getName = function() return name end, registerEvent = function() end} end
eq(spawnCb(mon("Talath"), nil, true, false), false, "pair 72: Talath's spawn is refused")
eq(spawnCb(mon("Mercenary"), nil, true, false), true, "pair 72: the hunt's monsters spawn")

-- open: the portal goes on its tile once, with the action id and the text
X.pair = 73
eq(X.placePortal(talath), "placed", "pair 73: the portal is placed")
eq(#created, 1, "one forcefield")
eq(created[1].id, 1387, "a magic forcefield")
eq(created[1].aid, cfg.aid, "with the lairs' action id")
eq(X.placePortal(talath), "kept", "a second startup keeps it")
eq(#created, 1, "and makes no second one")
eq(X.placeAll(), 1, "one open lair")
eq(spawnCb(mon("Talath"), nil, true, false), true, "pair 73: Talath spawns")

-- O686 phase 3: a lair boss takes H of the spell ranks at the level its lair is planned for, once, at its first think
check(creatureEvents.ChaosBossLairHealth ~= nil, "the lair health event is registered")
eq(talath.healthLevel, 650, "Talath's fight is planned for level 650")
local function lairBoss(name, hp)
	local m = {name = name, max = hp, hp = hp, events = {}, registered = {}}
	function m:getName() return self.name end
	function m:isMonster() return true end
	function m:getMaxHealth() return self.max end
	function m:getHealth() return self.hp end
	function m:setMaxHealth(v) self.max = v; self.hp = math.min(self.hp, v) end
	function m:addHealth(a, b) local n = b or a; self.hp = math.min(self.max, self.hp + n) end
	function m:registerEvent(e) self.registered[#self.registered + 1] = e end
	function m:unregisterEvent(e) self.events[e] = true end
	return m
end
local boss = lairBoss("Talath", 21000000)
eq(spawnCb(boss, nil, true, false), true, "an open lair's boss spawns")
eq(boss.registered[1], "ChaosBossLairHealth", "and gets the health event")
local plain = lairBoss("Mercenary", 100)
spawnCb(plain, nil, true, false)
eq(#plain.registered, 0, "a hunt monster gets none")
creatureEvents.ChaosBossLairHealth.onThink(boss, 1000)
eq(boss.max, 21000000, "the ranks are off: the health is the file's")
eq(boss.events.ChaosBossLairHealth, true, "the event is one-shot")
dofile("data/lib/chaos_spell_ranks.lua")
ChaosSpellRanksConfig.enabled = true
local boss2 = lairBoss("Talath", 21000000)
creatureEvents.ChaosBossLairHealth.onThink(boss2, 1000)
check(math.abs(boss2.max / 21000000 - Chaos.healthFactor(650)) < 1e-6 and boss2.max > 21000000, "the ranks on: x H of level 650")
eq(boss2.hp, boss2.max, "and the boss is at full health")
local mboss = lairBoss("Malgrath, the Drowned Crown", 5240000)
creatureEvents.ChaosBossLairHealth.onThink(mboss, 1000)
check(math.abs(mboss.max / 5240000 - Chaos.healthFactor(800)) < 1e-6, "Malgrath: x H of level 800")
ChaosSpellRanksConfig.enabled = false

-- stepping on it
local function player(level)
	local p = {level = level, msgs = {}}
	function p:getPlayer() return self end
	function p:getLevel() return self.level end
	function p:teleportTo(pos) self.at = pos end
	function p:sendTextMessage(_kind, text) self.msgs[#self.msgs + 1] = text end
	return p
end
local from = {x = talath.portal.x, y = talath.portal.y + 1, z = talath.portal.z}
local hero = player(700)
stepEvent.onStepIn(hero, created[1], talath.portal, from)
check(hero.at and hero.at.x == arr.x and hero.at.y == arr.y and hero.at.z == arr.z, "a level 700 player lands on the arrival")
check(hero.msgs[1] and hero.msgs[1]:find("The Shard Hollow", 1, true) ~= nil, "and reads where they are")
local low = player(talath.minLevel - 1)
stepEvent.onStepIn(low, created[1], talath.portal, from)
check(low.at == from, "a player below the level is pushed back")
check(low.msgs[1] and low.msgs[1]:find(tostring(talath.minLevel), 1, true) ~= nil, "and reads the level")
local ghost = {getPlayer = function() return nil end}
check(stepEvent.onStepIn(ghost, created[1], talath.portal, from) == true, "a monster on the portal is left alone")
local stray = player(700)
stepEvent.onStepIn(stray, created[1], {x = 1, y = 1, z = 7}, from)
check(stray.at == nil, "a forcefield of the action id elsewhere moves nobody")

-- the pair goes back down: the portal is taken away, the lair is closed again
X.pair = 72
eq(X.placePortal(talath), "removed", "closed again: our portal is removed")
eq(#tiles[key(talath.portal)].items, 0, "the tile is bare")
eq(X.placePortal(talath), "closed", "and stays away")
local late = player(700)
stepEvent.onStepIn(late, created[1], talath.portal, from)
check(late.at == from, "a closed lair lets nobody in")

-- an open lair that is not on the map places nothing and says why
X.pair = 73
tiles[key(arr)] = nil
local state, why = X.placePortal(talath)
check(state == nil and why:find("not on the map", 1, true) ~= nil, "no lair on the map: no portal")
tiles[key(talath.portal)] = nil
state, why = X.placePortal(talath)
check(state == nil and why:find("no tile", 1, true) ~= nil, "no hunt tile: no portal")

print(string.format("bosslair_test: %d checks, %d failures", count, failures))
os.exit(failures == 0 and 0 or 1)
