-- Run from the server/ folder: luajit tests/corpse_bag_test.lua (and lua5.3; CI runs both)
-- Loot bag instead of monster bodies (O435; server/README.md "Loot bag instead of corpses"). Part 1, the pure core
-- (corpse_core.lua): validation, the arguments the engine gets, the rule per creature kind: a monster with a corpse
-- leaves the bag, corpse 0 stays nothing, a kept id stays, a PLAYER body is never changed (the owner: "player corpses
-- stay exactly as they are"). Part 2, the engine glue corpse_bag.lua on a mocked engine: the switch, a bag that is no
-- corpse container, an engine without the patch. Part 3, the consumers of a corpse read the bag as a corpse: the
-- Necromancer's usable corpses, the ground labels' rule, the player corpse ids the Necromancer refuses. Part 4, one rule
-- in one place: the client's ground labels and the import fallback carry the config's bag id, every monster file's
-- corpse 0 stays and the kept ids are real corpse ids of the base scripts. Part 5 (O565): the bag looks like a plain pouch
-- (the config's client id, carried by the client's labels and glint) and an EMPTY bag decays in emptySeconds: the pure
-- sweep (a bag with items keeps its time, the time is never made longer, a forgotten place) and the engine glue
-- corpse_empty.lua on a mocked engine (tiles, containers, the timer).

local checks = 0
local function eq(a, b, m)
	checks = checks + 1
	if a ~= b then
		error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2)
	end
end
local function ok(v, m)
	checks = checks + 1
	if not v then
		error(m or "expected true", 2)
	end
end
local function readFile(path)
	local f = assert(io.open(path, "r"), "cannot open " .. path)
	local s = f:read("*a")
	f:close()
	return s
end

Chaos = Chaos or {}
dofile("data/scripts/chaos/corpse_core.lua")
local C = ChaosCorpse
local cfg = dofile("data/scripts/chaos/corpse_config.lua")

-- ---------------------------------------------------------------- part 1: the core
eq(#C.validate(cfg), 0, "the shipped config is valid")
eq(cfg.enabled, true, "on by default (owner 2026-11-08)")
eq(cfg.bagId, 6068, "the bag is item 6068")
ok(cfg.seconds <= 300, "a corpse stays at most 5 minutes (owner 2026-10-20)")
ok(cfg.slots >= 60, "as many slots as the biggest stock corpse")
eq(cfg.look, 19202, "the bag draws client item 19202, a plain leather pouch (not the stock dark lump of 6068)")
ok(cfg.emptySeconds >= 3 and cfg.emptySeconds <= 5, "an empty bag goes in 3-5 seconds (owner 2026-11-14)")
ok(cfg.emptySeconds < cfg.seconds, "the empty time is shorter than the bag's own")

local bag, keep = C.engineArgs(cfg)
eq(bag, 6068, "engine args: the bag")
eq(#keep, #cfg.keepIds, "engine args: every kept id")
for i = 2, #keep do
	ok(keep[i - 1] < keep[i], "kept ids sorted")
end
local off = {}
for k, v in pairs(cfg) do
	off[k] = v
end
off.enabled = false
eq((C.engineArgs(off)), 0, "off: bag id 0 (the engine keeps every body)")
eq(#select(2, C.engineArgs(off)), 0, "off: no kept ids")
eq((C.engineArgs(cfg, false)), 0, "a bag item the engine says is no corpse container: off")
eq((C.engineArgs(cfg, true)), 6068, "a bag item that is fine: on")
eq((C.engineArgs(nil)), 0, "no config: off")

-- validation catches what would break a server
local function bad(change, what)
	local c = {}
	for k, v in pairs(cfg) do
		c[k] = v
	end
	change(c)
	ok(#C.validate(c) > 0, what)
	eq((C.engineArgs(c)), 0, what .. ": the engine is not given a broken config")
end
bad(function(c) c.bagId = 0 end, "bag id 0")
bad(function(c) c.bagId = 70000 end, "bag id over 65535")
bad(function(c) c.bagId = 6068.5 end, "bag id not whole")
bad(function(c) c.seconds = 3000 end, "a bag that lasts over 5 minutes")
bad(function(c) c.slots = 0 end, "no slots")
bad(function(c) c.name = "" end, "no name")
bad(function(c) c.look = 0 end, "no look")
bad(function(c) c.look = 70000 end, "a look over 65535")
bad(function(c) c.emptySeconds = -1 end, "a negative empty time")
bad(function(c) c.emptySeconds = 61 end, "an empty time over a minute")
bad(function(c) c.emptySeconds = c.seconds end, "an empty time as long as the bag's own")
bad(function(c) c.emptySeconds = "5" end, "an empty time that is no number")
bad(function(c) c.keepIds = {6068} end, "the bag among the kept ids")
bad(function(c) c.keepIds = {"x"} end, "a kept id that is no number")

-- the rule per kind (the same cases as server/tools/chaoslootbag_test.cpp)
eq(C.corpseFor(cfg, "monster", 5972), 6068, "a dragon leaves the bag")
eq(C.corpseFor(cfg, "monster", 65535), 6068, "the highest corpse id too")
eq(C.corpseFor(cfg, "monster", 1), 6068, "the lowest too")
eq(C.corpseFor(cfg, "monster", 0), 0, "corpse 0 leaves nothing")
eq(C.corpseFor(cfg, "monster", nil), nil, "no corpse stays no corpse")
eq(C.corpseFor(cfg, "monster", 6068), 6068, "the bag stays the bag")
for _, id in ipairs(cfg.keepIds) do
	eq(C.corpseFor(cfg, "monster", id), id, "kept corpse " .. id)
end
eq(C.corpseFor(cfg, "monster", 8966), 6068, "the Overcharged Energy Elemental (8966, next to the overlords) is a bag")
eq(C.corpseFor(off, "monster", 5972), 5972, "switched off: the body")

-- PLAYER deaths: never touched, on or off, whatever the id
for _, id in ipairs({3058, 3065, 6068, 5972, 0, 20000}) do
	eq(C.corpseFor(cfg, "player", id), id, "a player corpse " .. id .. " is not changed")
	eq(C.corpseFor(off, "player", id), id, "a player corpse " .. id .. " is not changed (off)")
end
eq(C.corpseFor(cfg, nil, 3058), 3058, "an unknown kind is not changed")
eq(C.corpseFor(cfg, "npc", 3058), 3058, "an NPC is not changed")
ok(C.isBag(cfg, 6068) and not C.isBag(cfg, 3058), "isBag")

-- ---------------------------------------------------------------- part 2: the engine glue
local function run(config, opts)
	opts = opts or {}
	local calls = {}
	local printed = {}
	Game = {}
	if not opts.noEngine then
		Game.setMonsterLootBag = function(id, list)
			calls[#calls + 1] = {id = id, list = list}
			if opts.engineError then
				error("boom")
			end
			return true
		end
	end
	ItemType = function(id)
		return {
			getId = function() return opts.itemMissing and 0 or id end,
			isContainer = function() return opts.container ~= false end,
			isCorpse = function() return opts.corpse ~= false end,
		}
	end
	local realPrint, realDofile = print, dofile
	print = function(s) printed[#printed + 1] = s end
	dofile = function(path)
		if path == "data/scripts/chaos/corpse_config.lua" then
			return config
		end
		return realDofile(path)
	end
	ChaosCorpse = nil
	local good, err = pcall(realDofile, "data/scripts/chaos/corpse_bag.lua")
	print, dofile = realPrint, realDofile
	if not good then
		error(err)
	end
	return calls, printed, ChaosCorpse
end

local calls, printed, K = run(cfg)
eq(#calls, 1, "the engine is called once per load")
eq(calls[1].id, 6068, "glue: the bag id")
eq(#calls[1].list, #cfg.keepIds, "glue: the kept ids")
eq(K.active, true, "glue: active")
eq(#printed, 0, "glue: nothing in the log")

calls, printed, K = run(off)
eq(#calls, 1, "off: the engine is still told (a reload turns the bodies back)")
eq(calls[1].id, 0, "off: bag id 0")
eq(K.active, false, "off: not active")

calls, printed, K = run(cfg, {container = false})
eq(calls[1].id, 0, "an item that is no container: bodies stay")
ok(#printed == 1 and printed[1]:find("no corpse container"), "that is logged")
calls, printed, K = run(cfg, {corpse = false})
eq(calls[1].id, 0, "an item without a corpse type: bodies stay")
calls, printed, K = run(cfg, {itemMissing = true})
eq(calls[1].id, 0, "an item this server does not have: bodies stay")

local broken = {}
for k, v in pairs(cfg) do
	broken[k] = v
end
broken.seconds = 99999
calls, printed, K = run(broken)
eq(calls[1].id, 0, "a broken config: the engine is told off")
ok(#printed >= 1 and printed[1]:find("seconds"), "a broken config is logged")

calls, printed, K = run(cfg, {noEngine = true})
eq(#calls, 0, "an engine without the patch: no call")
eq(K.active, false, "an engine without the patch: not active")
ok(#printed == 1 and printed[1]:find("src%-patch 0089"), "an engine without the patch says so once")
calls, printed, K = run(off, {noEngine = true})
eq(#printed, 0, "an engine without the patch and the switch off: silent")

calls, printed, K = run(cfg, {engineError = true})
eq(K.engine, false, "an engine error does not stop the load")
Game, ItemType, ChaosCorpse = nil, nil, nil

-- ---------------------------------------------------------------- part 3: the consumers read the bag as a corpse
dofile("data/scripts/chaos/necro_core.lua")
dofile("data/scripts/chaos/groundloot_core.lua")
local N = ChaosNecroCore
local G = ChaosGroundLoot
ok(N and G, "cores loaded")
-- a bag: a container (ItemType:isContainer), corpse type set in items.xml (ItemType:isCorpse), owner set by the engine
-- in Monster::getCorpse; the patch changes only the id
local bagInfo = {isCorpse = true, items = 0, owner = 7, playerCorpse = false}
ok(N.corpseUsable(bagInfo, {[7] = true}), "Necromancer: an emptied bag of the caster is a usable corpse (Raise Dead, Corpse Explosion)")
ok(not N.corpseUsable({isCorpse = true, items = 2, owner = 7}, {[7] = true}), "Necromancer: a bag with loot is not (as before)")
ok(not N.corpseUsable({isCorpse = true, items = 0, owner = 8}, {[7] = true}), "Necromancer: someone else's bag is not (as before)")
ok(not N.corpseUsable({isCorpse = true, items = 0, owner = 0, playerCorpse = true}, {}), "Necromancer: a player corpse never")
local necroLib = readFile("data/scripts/chaos/necro_lib.lua")
ok(necroLib:find("M.playerCorpses = {[3058] = true, [3065] = true}", 1, true), "Necromancer: the player corpse ids are the two player bodies")
ok(C.corpseFor(cfg, "player", 3058) == 3058, "the player body ids stay")
ok(necroLib:find("it:isCorpse()", 1, true), "Necromancer: corpses are found by ItemType:isCorpse, not by id")
ok(G.isCorpse({container = true, corpseType = true, owner = 0}), "ground loot: the bag is a corpse (container with a corpse type)")
ok(G.isCorpse({container = true, corpseType = false, owner = 5}), "ground loot: a bag with an owner is a corpse")
ok(not G.isCorpse({container = false, corpseType = true, owner = 0}), "ground loot: a non-container is not")

-- no script of ours looks for a monster corpse by a fixed id (a scan: a new site fails here)
local function listFiles(dir)
	local p = io.popen('ls "' .. dir .. '"')
	local out = {}
	for line in p:lines() do
		out[#out + 1] = line
	end
	p:close()
	return out
end
local DIR = "data/scripts/chaos/"
local fixed = {}
for _, f in ipairs(listFiles(DIR)) do
	if f:match("%.lua$") then
		local src = readFile(DIR .. f)
		for line in src:gmatch("[^\n]+") do
			if line:find("getId%(%)%s*==%s*%d%d%d%d") and line:lower():find("corpse") then
				fixed[#fixed + 1] = f .. ": " .. line
			end
		end
	end
end
eq(#fixed, 0, "no Chaos script compares a corpse's item id with a number: " .. table.concat(fixed, " | "))

-- ---------------------------------------------------------------- part 4: one rule in one place
local labels = readFile("../client/overlay/modules/game_groundlabels/groundlabelslogic.lua")
eq(tonumber(labels:match("GL%.CORPSE_BAG_ID%s*=%s*(%d+)")), cfg.bagId, "the client's ground labels carry the config's bag id")
eq(tonumber(labels:match("GL%.LOOT_BAG_LOOK%s*=%s*(%d+)")), cfg.look, "the client's ground labels carry the config's bag look")
local aura = readFile("../client/overlay/modules/game_chestaura/chestaura_logic.lua")
ok(aura:find("[" .. cfg.look .. "] = { art = 'bag_glint'", 1, true), "the client's glint is keyed on the config's bag look")
local fix = readFile("tools/fix_monster_xml.py")
eq(tonumber(fix:match("FALLBACK_CORPSE%s*=%s*(%d+)")), cfg.bagId, "the monster import fallback is the bag")
local pouchCfg = readFile("data/scripts/chaos/pouches_config.lua")
ok(not pouchCfg:find("6068", 1, true), "the store pouches do not use the bag id")

-- the monster files: corpse 0 monsters stay as they are, no file asks for a kept id by accident other than the quest ones
local zero, bagUsers = 0, 0
local p = io.popen('find data/monster/monsters -name "*.xml"')
for path in p:lines() do
	local src = readFile(path)
	local c = tonumber(src:match('corpse="(%d+)"'))
	if c == 0 then
		zero = zero + 1
		eq(C.corpseFor(cfg, "monster", c), 0, path .. ": corpse 0 leaves nothing")
	elseif c then
		local want = 6068
		for _, k in ipairs(cfg.keepIds) do
			if k == c then
				want = c
			end
		end
		eq(C.corpseFor(cfg, "monster", c), want, path .. ": corpse " .. c)
		bagUsers = bagUsers + 1
	end
end
p:close()
ok(zero >= 20, "the 22 Chaos monsters with corpse 0 are there (" .. zero .. ")")
ok(bagUsers > 100, "the Chaos monsters have corpses to replace (" .. bagUsers .. ")")

-- ---------------------------------------------------------------- part 5: the empty bag decay (O565)
local W = 1000 * cfg.emptySeconds
eq(C.emptyMs(cfg), W, "emptyMs: the config in milliseconds")
eq(C.emptyMs(off), nil, "emptyMs: the switch off, no shortcut")
local zero = {}
for k, v in pairs(cfg) do
	zero[k] = v
end
zero.emptySeconds = 0
eq(C.emptyMs(zero), nil, "emptyMs: 0 seconds is off")
eq(#C.validate(zero), 0, "emptySeconds 0 is a valid config")
eq(C.emptyMs(nil), nil, "emptyMs: no config")
eq(C.emptyMs(broken), nil, "emptyMs: a broken config is off")
ok(C.shouldShorten(cfg, 0, 120000), "an empty bag with 2 minutes left is cut")
ok(not C.shouldShorten(cfg, 0, W), "an empty bag with exactly that left is left alone")
ok(not C.shouldShorten(cfg, 0, 1000), "an empty bag that goes sooner is never made longer")
ok(not C.shouldShorten(cfg, 1, 120000), "a bag with an item keeps its time")
ok(not C.shouldShorten(cfg, 12, 120000), "a bag with items keeps its time")
ok(not C.shouldShorten(zero, 0, 120000), "0 seconds: nothing is cut")
ok(not C.shouldShorten(off, 0, 120000), "switched off: nothing is cut")
ok(C.shouldShorten(cfg, nil, 120000), "no size is an empty bag")

-- the sweep on a fake map: tiles hold rows {size, remaining}
local function sweepWorld(tiles, w, now)
	local cut = {}
	local n = C.sweep(cfg, w, now, function(pos)
		return tiles[pos.x .. "," .. pos.y .. "," .. pos.z] or {}
	end, function(row, ms)
		row.remaining = ms
		cut[#cut + 1] = row
	end)
	return cut, n
end
local w = C.newWatch()
eq(C.count(w), 0, "a new watch is empty")
ok(not C.watch(w, nil, 1), "no position is not watched")
ok(not C.watch(w, {x = 1}, 1), "a position without y and z is not watched")
ok(C.watch(w, {x = 5, y = 6, z = 7}, 100), "a place is watched")
ok(C.watch(w, {x = 5, y = 6, z = 7}, 101), "the same place again")
eq(C.count(w), 1, "one place once")
C.watch(w, {x = 9, y = 9, z = 7}, 100)
C.watch(w, {x = 3, y = 3, z = 7}, 100)
eq(C.count(w), 3, "three places")
local tiles = {
	["5,6,7"] = {{size = 0, remaining = 170000}, {size = 3, remaining = 170000}}, -- one empty, one with loot (a pack died here)
	["9,9,7"] = {{size = 0, remaining = 170000}},
	-- 3,3,7: no bag any more
}
local cut, gone = sweepWorld(tiles, w, 102)
eq(#cut, 2, "the two empty bags are cut")
eq(cut[1].remaining, W, "to the config time")
eq(tiles["5,6,7"][2].remaining, 170000, "the bag with loot keeps its time")
eq(gone, 2, "the place with no bag and the place with only an emptied bag are forgotten")
eq(C.count(w), 1, "the place of the bag with loot is still watched")
cut, gone = sweepWorld(tiles, w, 103)
eq(#cut, 0, "a second pass cuts nothing more (the empty bag is short already)")
eq(C.count(w), 1, "still watched: the loot is not taken yet")
tiles["5,6,7"][2].size = 0 -- the player takes the last item
cut, gone = sweepWorld(tiles, w, 104)
eq(#cut, 1, "the bag that was emptied later is cut")
eq(tiles["5,6,7"][2].remaining, W, "to the config time")
eq(C.count(w), 0, "and the place is forgotten")
-- a place is forgotten when the bag's own time is over, whatever it still says
local w2 = C.newWatch()
C.watch(w2, {x = 1, y = 1, z = 7}, 1000)
cut, gone = sweepWorld({["1,1,7"] = {{size = 4, remaining = 170000}}}, w2, 1000 + cfg.seconds + C.GRACE_SEC + 1)
eq(C.count(w2), 0, "a place older than the bag can live is forgotten")
-- the switch off: the places are dropped and nothing is cut
local w3 = C.newWatch()
C.watch(w3, {x = 1, y = 1, z = 7}, 5)
local probed = false
C.sweep(off, w3, 6, function() probed = true return {} end, function() end)
eq(C.count(w3), 0, "switched off: places are dropped")
ok(not probed, "switched off: no tile is looked at")

-- the engine glue on a mocked engine
local function glue(config)
	local env = {tiles = {}, events = {}, printed = {}, callbacks = {}}
	Chaos = {corpseConfig = config}
	ChaosCorpse = nil
	ITEM_ATTRIBUTE_DURATION = 16
	local function newBag(pos, size, remaining)
		local item = {id = config.bagId, size = size, remaining = remaining, sets = {}, decays = 0}
		function item:getId() return self.id end
		function item:getSize() return self.size end
		function item:getAttribute(k) assert(k == ITEM_ATTRIBUTE_DURATION) return self.remaining end
		function item:setAttribute(k, v) assert(k == ITEM_ATTRIBUTE_DURATION) self.remaining = v self.sets[#self.sets + 1] = v return true end
		function item:decay() self.decays = self.decays + 1 return true end
		function item:getPosition() return pos end
		local key = pos.x .. "," .. pos.y .. "," .. pos.z
		env.tiles[key] = env.tiles[key] or {}
		table.insert(env.tiles[key], item)
		return item
	end
	env.newBag = newBag
	Tile = function(x, y, z)
		local list = env.tiles[x .. "," .. y .. "," .. z]
		if not list then return nil end
		return {getItems = function() return list end}
	end
	addEvent = function(fn, ms) env.events[#env.events + 1] = {fn = fn, ms = ms} end
	local realEventCallback, realPrint = EventCallback, print
	EventCallback = setmetatable({register = function(self, prio) env.callbacks[#env.callbacks + 1] = {fn = self.onDropLoot, prio = prio} end}, {})
	print = function(m) env.printed[#env.printed + 1] = m end
	local good, err = pcall(dofile, "data/scripts/chaos/corpse_empty.lua")
	EventCallback, print = realEventCallback, realPrint
	if not good then error(err) end
	function env.runEvents()
		local list = env.events
		env.events = {}
		for _, e in ipairs(list) do e.fn() end
	end
	return env
end

local env = glue(cfg)
eq(#env.callbacks, 1, "glue: one onDropLoot callback")
eq(env.callbacks[1].prio, 9, "glue: after the loot layer and autoloot")
eq(#env.events, 0, "glue: no timer until a bag lies somewhere")
local pos = {x = 100, y = 200, z = 7}
local empty = env.newBag(pos, 0, 180000)
local full = env.newBag(pos, 5, 180000)
local other = env.newBag({x = 101, y = 200, z = 7}, 2, 180000)
local function die(bag)
	env.callbacks[1].fn({}, bag)
end
die(empty)
die(full)
die(other)
eq(#env.events, 1, "glue: one timer for all the places")
eq(env.events[1].ms, C.CHECK_MS, "glue: it looks every second")
env.runEvents()
eq(empty.remaining, W, "glue: an empty bag has the config time left")
eq(empty.sets[1], W, "glue: through the duration attribute")
eq(full.remaining, 180000, "glue: a bag with items keeps its time")
eq(other.remaining, 180000, "glue: another place's bag keeps its time")
eq(#env.events, 1, "glue: the timer runs while a place is watched")
full.size = 0 -- looted by hand
env.runEvents()
eq(full.remaining, W, "glue: a bag emptied later goes the same way")
eq(#empty.sets, 1, "glue: an emptied bag is cut once")
other.size = 0
env.runEvents()
eq(other.remaining, W, "glue: the other place too")
eq(#env.events, 0, "glue: the timer stops when no place is watched")
local late = env.newBag(pos, 0, 180000)
die(late)
eq(#env.events, 1, "glue: the next kill starts it again")
env.runEvents()
eq(late.remaining, W, "glue: and cuts that bag")
-- not our bag, no corpse: nothing watched
local foreign = env.newBag({x = 1, y = 1, z = 7}, 0, 180000)
foreign.id = 3058
env.events = {}
die(foreign)
die(nil)
eq(#env.events, 0, "glue: a body that is no bag is not watched")
-- the switch off or 0 seconds: not watched
local offEnv = glue(off)
offEnv.callbacks[1].fn({}, offEnv.newBag(pos, 0, 180000))
eq(#offEnv.events, 0, "glue: switched off, nothing is watched")
local zeroEnv = glue(zero)
zeroEnv.callbacks[1].fn({}, zeroEnv.newBag(pos, 0, 180000))
eq(#zeroEnv.events, 0, "glue: 0 seconds, nothing is watched")
-- an error in a pass is logged, not thrown, and the timer keeps running while a place is watched
local errEnv = glue(cfg)
local bomb = errEnv.newBag(pos, 0, 180000)
bomb.getAttribute = function() error("boom") end
errEnv.callbacks[1].fn({}, bomb)
local realPrint = print
local logged = {}
print = function(m) logged[#logged + 1] = m end
errEnv.runEvents()
print = realPrint
ok(#logged == 1 and logged[1]:find("empty bag sweep"), "glue: an error in a pass is logged")
eq(#errEnv.events, 1, "glue: the timer is kept after an error")
Chaos, ChaosCorpse, Tile, addEvent, ITEM_ATTRIBUTE_DURATION = nil, nil, nil, nil, nil

-- the script file itself: registered after autoloot, reads and sets the duration attribute
local glueSrc = readFile("data/scripts/chaos/corpse_empty.lua")
ok(glueSrc:find("drop:register(9)", 1, true), "glue: registered after autoloot")
ok(glueSrc:find("ITEM_ATTRIBUTE_DURATION", 1, true), "glue: reads and sets the duration attribute")

print(string.format("corpse_bag_test: %d checks ok", checks))
