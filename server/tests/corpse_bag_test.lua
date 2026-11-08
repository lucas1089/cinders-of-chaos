-- Run from the server/ folder: luajit tests/corpse_bag_test.lua (and lua5.3; CI runs both)
-- Loot bag instead of monster bodies (O435; server/README.md "Loot bag instead of corpses"). Part 1, the pure core
-- (corpse_core.lua): validation, the arguments the engine gets, the rule per creature kind: a monster with a corpse
-- leaves the bag, corpse 0 stays nothing, a kept id stays, a PLAYER body is never changed (the owner: "player corpses
-- stay exactly as they are"). Part 2, the engine glue corpse_bag.lua on a mocked engine: the switch, a bag that is no
-- corpse container, an engine without the patch. Part 3, the consumers of a corpse read the bag as a corpse: the
-- Necromancer's usable corpses, the ground labels' rule, the player corpse ids the Necromancer refuses. Part 4, one rule
-- in one place: the client's ground labels and the import fallback carry the config's bag id, every monster file's
-- corpse 0 stays and the kept ids are real corpse ids of the base scripts.

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

print(string.format("corpse_bag_test: %d checks ok", checks))
