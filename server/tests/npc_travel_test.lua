-- Run from the server/ folder: luajit tests/npc_travel_test.lua (and lua5.3; CI runs both)
-- Travel to an NPC (npc_travel_core.lua, npc_travel.lua, npc_travel_config.lua; client game_npctravel; server/README.md "Travel
-- to an NPC"). Checks: the opcode (121: free, unique, named by no other script or client module); the real config against
-- the places the NPCs really are (the hub's stalls, the four factions of factions_config.lua, the temples of
-- data/chaos_poi.lua, data/npc/<name>.xml); the client's key list equals the config's keys; every text has a pt-BR entry;
-- the pure rules (resolve, the tiles in front of a stall, the refusals, the cooldown); the glue on a mocked engine (combat,
-- a rift, the cooldown, a stall, a town far away, an NPC that is not placed, a blocked front tile).

local checks, failures = 0, 0
local function check(cond, label)
	checks = checks + 1
	if not cond then
		failures = failures + 1
		io.write("FAIL " .. label .. "\n")
	end
end
local function eq(a, b, label)
	check(a == b, label .. " (" .. tostring(a) .. " ~= " .. tostring(b) .. ")")
end

local function readFile(path)
	local f = io.open(path, "r")
	if not f then return nil end
	local s = f:read("*a")
	f:close()
	return s
end

-- the engine pieces chaos_constants.lua touches when loaded
json = json or {decode = function(s) return NEXT_MESSAGE end, encode = function() return "{}" end}
dofile("data/scripts/chaos/chaos_constants.lua")
dofile("data/scripts/chaos/i18n_core.lua")
dofile("data/scripts/chaos/npc_booths_core.lua")
dofile("data/scripts/chaos/npc_travel_core.lua")
local K = ChaosNpcTravelCore
local cfg = dofile("data/scripts/chaos/npc_travel_config.lua")
local boothCfg = ChaosNpcBoothsCore.cfg()
local booths = ChaosNpcBoothsCore.booths(boothCfg)
local factionsCfg = dofile("data/scripts/chaos/factions_config.lua")

-- ---------------------------------------------------------------- the opcode
eq(ChaosOpcodes.npcTravel, 121, "opcode 121")
do
	local seen = {}
	for name, v in pairs(ChaosOpcodes) do
		check(seen[v] == nil, "opcode " .. v .. " used twice (" .. name .. ", " .. tostring(seen[v]) .. ")")
		seen[v] = name
	end
	for _, v in ipairs({1, 67, 73, 89, 91, 92, 99, 106, 107, 136, 181, 201, 202, -- the reference server
			126, 127, -- its NPC scripts' currency opcodes
			140, 144, 145, 146, 210, 212, 213, 230, 246}) do -- the reference client's own ExtendedIds
		check(ChaosOpcodes.npcTravel ~= v, "not an opcode of the reference server or client: " .. v)
	end
	local others = 0
	for _, cmd in ipairs({"ls data/scripts/chaos/*.lua", "ls ../client/overlay/modules/*/*.lua"}) do
		local ph = io.popen(cmd .. " 2>/dev/null")
		for file in ph:lines() do
			local s = readFile(file)
			local own = file:find("npc_travel", 1, true) or file:find("game_npctravel", 1, true) or file:find("chaos_constants", 1, true)
			if s and not own and not file:find("_test.lua", 1, true)
					and (s:find("[Oo]pcode[%w_]*%s*=%s*121%f[%D]") or s:find("xtended[%w]*Opcode%(%s*121%f[%D]")) then
				others = others + 1
				io.write("opcode 121 in " .. file .. "\n")
			end
		end
		ph:close()
	end
	eq(others, 0, "no other script or module on 121")
	local client = readFile("../client/overlay/modules/game_npctravel/npctravel.lua") or ""
	check(client:find("local OPCODE = 121", 1, true) ~= nil, "the client sends on 121")
end

-- ---------------------------------------------------------------- the real config against the real places
do
	-- the temples of the map (data/chaos_poi.lua, written by tools/gen_poi.py) and the town names (tools/base_towns.csv)
	local poi = dofile("data/chaos_poi.lua")
	local temples = {}
	for _, m in ipairs(poi.marks) do
		if m.k == "temple" then
			temples[m.n:gsub("^Temple of ", "")] = m
		end
	end
	local towns, names = {}, {}
	for line in (readFile("tools/base_towns.csv") or ""):gmatch("[^\r\n]+") do
		local id, name = line:match("^(%d+),(.+)$")
		if id then
			names[tonumber(id)] = name
			if temples[name] then
				towns[tonumber(id)] = temples[name]
			end
		end
	end
	local problems = K.validate(cfg, booths, factionsCfg.factions, towns)
	for _, p in ipairs(problems) do
		io.write("problem: " .. p .. "\n")
	end
	eq(#problems, 0, "validate")

	-- the main city's temple is the one the stalls are placed for
	local cind = temples["Cinderhold"]
	check(cind ~= nil, "Cinderhold has a temple in data/chaos_poi.lua")
	eq(cind.x, boothCfg.temple.x, "the stalls' temple x")
	eq(cind.y, boothCfg.temple.y, "the stalls' temple y")
	eq(cind.z, boothCfg.temple.z, "the stalls' temple z")

	-- every NPC: its XML and the script that XML names exist; the hub ones have a stall, the others a town with a temple
	for _, key in ipairs(K.keys(cfg)) do
		local e = cfg.npcs[key]
		local xml = readFile("data/npc/" .. e.name .. ".xml")
		check(xml ~= nil, key .. ": data/npc/" .. e.name .. ".xml exists")
		if xml then
			check(xml:find('name="' .. e.name .. '"', 1, true) ~= nil, key .. ": the XML names " .. e.name)
			local script = xml:match('script="([^"]+)"')
			check(script ~= nil and readFile("data/npc/scripts/" .. script) ~= nil, key .. ": its script exists")
		end
		check(K.hubSpot(cfg, booths, e.name) ~= nil or (e.townId and towns[e.townId]), key .. ": a stall or a town temple")
	end

	-- the four factions: an entry each, the same NPC, in the hub or in the town factions_config.lua places it in
	for _, f in ipairs(factionsCfg.factions) do
		local e = cfg.npcs["faction_" .. f.key]
		check(e ~= nil, f.key .. ": entry")
		if e then
			eq(e.name, f.npc.name, f.key .. ": NPC")
			local stall = K.hubSpot(cfg, booths, f.npc.name)
			if stall then
				eq(f.npc.townId, boothCfg.town, f.key .. ": a hub NPC belongs to the hub's town")
			else
				eq(e.townId, f.npc.townId, f.key .. ": town")
				check(towns[f.npc.townId] ~= nil, f.key .. ": the temple the NPC is placed next to exists")
				-- the town name the placement uses is the name of that town id
				if type(f.npc.town) == "string" then
					eq(names[f.npc.townId], f.npc.town, f.key .. ": town name and id agree")
				end
			end
			-- the faction window says where: the text exists in pt-BR
			check(e.where:find(f.npc.name, 1, true) ~= nil, f.key .. ": the where text names the NPC")
		end
	end
	-- the home faction NPC of the main city stands in the hub
	check(K.hubSpot(cfg, booths, "Warden Ysolde") ~= nil, "Warden Ysolde has a stall in the hub")
	-- the NPCs the panels name
	for _, key in ipairs({"stash", "pocketboss", "gambler", "candlemarks", "materials"}) do
		check(cfg.npcs[key] ~= nil, "panel NPC " .. key)
	end
end

-- ---------------------------------------------------------------- the client's key list equals the config's keys
do
	dofile("../client/overlay/modules/game_npctravel/npctravellogic.lua")
	local clientKeys, serverKeys = NpcTravelLogic.KEYS, K.keys(cfg)
	eq(#clientKeys, #serverKeys, "client and server list the same number of NPCs")
	for i, k in ipairs(serverKeys) do
		eq(clientKeys[i], k, "client key " .. i)
	end
	-- every panel button names a key of the list
	local ph = io.popen("grep -rhoE \"modules\\.game_npctravel\\.travel\\('[a-z_]+'\\)\" ../client/overlay/modules --include=*.otui")
	local n = 0
	for line in ph:lines() do
		n = n + 1
		local key = line:match("travel%('([a-z_]+)'%)")
		check(cfg.npcs[key] ~= nil, "a panel button names an unknown NPC: " .. tostring(key))
	end
	ph:close()
	check(n >= 5, "the panels carry the buttons (" .. n .. ")")
end

-- ---------------------------------------------------------------- pt-BR for every text
do
	local strings = dofile("data/scripts/chaos/i18n_strings.lua")["pt-BR"]
	local function need(key, where)
		check(type(strings[key]) == "string" and strings[key] ~= "", "pt-BR entry for " .. where .. ": " .. key)
		-- the same % conversions in the same order
		local a, b = {}, {}
		for c in key:gmatch("%%(%a)") do a[#a + 1] = c end
		for c in tostring(strings[key]):gmatch("%%(%a)") do b[#b + 1] = c end
		eq(table.concat(a), table.concat(b), "conversions of " .. key)
	end
	for _, key in ipairs(K.keys(cfg)) do
		need(cfg.npcs[key].where, key .. ".where")
	end
	for k, label in pairs(cfg.labels) do
		need(label, "labels." .. k)
	end
	need("this place", "core")
	for _, file in ipairs({"data/scripts/chaos/npc_travel_core.lua", "data/scripts/chaos/npc_travel.lua"}) do
		local s = readFile(file)
		for key in s:gmatch("tx%(\"([^\"]+)\"") do need(key, file) end
		for key in s:gmatch("tr%(player, \"([^\"]+)\"") do need(key, file) end
	end
end

-- ---------------------------------------------------------------- resolve
local probeLive = {}
local probe = {
	live = function(name) return probeLive[name] end,
	temple = function(id) return ({[1] = {x = 32957, y = 32076, z = 7}, [2] = {x = 32369, y = 32241, z = 7}})[id] end
}
do
	-- a hub NPC not on the map yet: its stall, the carpet in front of it
	local w = K.resolve(cfg, booths, "stash", probe)
	eq(w.via, "hub", "stash: stall")
	eq(w.npc.x, 31666, "stash: stall x")
	eq(w.npc.y, 32230, "stash: stall y")
	eq(w.hint.y, 32233, "stash: the carpet")
	check(w.front, "stash: front")
	-- the live NPC in its stall wins and keeps the front rule
	probeLive["Tavish Coldhand"] = {x = 31666, y = 32230, z = 7}
	w = K.resolve(cfg, booths, "stash", probe)
	eq(w.via, "live", "stash: live")
	check(w.front, "stash: live in the stall keeps front")
	-- a live NPC elsewhere (moved by the owner): near it, toward the temple
	probeLive["Tavish Coldhand"] = {x = 32370, y = 32245, z = 7}
	w = K.resolve(cfg, booths, "stash", probe)
	eq(w.via, "live", "stash moved: live")
	check(not w.front, "stash moved: no front")
	eq(w.hint.x, 32369, "stash moved: hint is the temple")
	probeLive["Tavish Coldhand"] = nil
	-- a faction NPC of another town: only the live NPC or the temple
	w = K.resolve(cfg, booths, "faction_compact", probe)
	eq(w.via, "temple", "Brannoc not placed: the temple of Mirewake")
	eq(w.npc.x, 32957, "Brannoc: temple x")
	probeLive["Forgemaster Brannoc"] = {x = 32961, y = 32073, z = 7}
	w = K.resolve(cfg, booths, "faction_compact", probe)
	eq(w.via, "live", "Brannoc live")
	eq(w.npc.x, 32961, "Brannoc live x")
	eq(w.hint.x, 32957, "Brannoc: hint is the temple")
	probeLive["Forgemaster Brannoc"] = nil
	-- a town whose temple the probe does not know, and no stall: unset
	w = K.resolve(cfg, booths, "faction_choir", probe)
	eq(w, nil, "Velith with nothing known")
	local _, why = K.resolve(cfg, booths, "faction_choir", probe)
	eq(why, "unset", "unset reason")
	_, why = K.resolve(cfg, booths, "nothing", probe)
	eq(why, "unknown", "unknown reason")
	_, why = K.resolve(cfg, booths, nil, probe)
	eq(why, "unknown", "nil key")
	-- an explicit pos wins over the temple
	local own = {npcs = {x = {name = "Nobody", townId = 1, pos = {x = 5, y = 6, z = 7}, where = "x"}}}
	w = K.resolve(own, {}, "x", probe)
	eq(w.via, "pos", "explicit pos")
	eq(w.npc.y, 6, "explicit pos y")
end

-- ---------------------------------------------------------------- the tiles in front of a stall
do
	-- north row (y 32230): the carpet is south
	local north = K.resolve(cfg, booths, "stash", probe)
	local list = K.candidates(north.npc, north.hint, cfg.maxRing, north.front)
	eq(#list, 24, "5x5 minus the NPC's tile")
	eq(list[1].x, 31666, "north stall: first tile x")
	eq(list[1].y, 32232, "north stall: first tile is across the counter, on the carpet side")
	-- south row (y 32236): the carpet is north
	local south = K.resolve(cfg, booths, "pocketboss", probe)
	list = K.candidates(south.npc, south.hint, cfg.maxRing, south.front)
	eq(list[1].y, 32234, "south stall: first tile on the carpet side")
	eq(list[1].x, 31660, "south stall: x")
	-- every tile within the ring, none the NPC's own
	for _, p in ipairs(list) do
		check(not (p.x == south.npc.x and p.y == south.npc.y), "not the NPC's own tile")
		check(math.max(math.abs(p.x - south.npc.x), math.abs(p.y - south.npc.y)) <= cfg.maxRing, "within the ring")
		eq(p.z, 7, "same floor")
	end
	-- a town NPC: the nearest ring first, the temple side first inside it
	local npc, hint = {x = 100, y = 100, z = 7}, {x = 90, y = 100, z = 7}
	list = K.candidates(npc, hint, 2, false)
	eq(list[1].x, 99, "town NPC: the tile next to it toward the temple")
	eq(list[1].y, 100, "town NPC: same row")
	local ring1 = 0
	for i = 1, 8 do
		if math.max(math.abs(list[i].x - npc.x), math.abs(list[i].y - npc.y)) == 1 then ring1 = ring1 + 1 end
	end
	eq(ring1, 8, "town NPC: ring one before ring two")
	-- the order is stable
	local again = K.candidates(npc, hint, 2, false)
	for i, p in ipairs(list) do
		check(p.x == again[i].x and p.y == again[i].y, "stable order " .. i)
	end
	-- the range of every panel's service is met (the shortest is Osric's, 3)
	check(cfg.maxRing <= 3, "the landing tile is in talking range of every service")
end

-- ---------------------------------------------------------------- near, cooldown, refusals
do
	check(K.near({x = 1, y = 1, z = 7}, {x = 3, y = 2, z = 7}, 2), "near: 2 tiles")
	check(not K.near({x = 1, y = 1, z = 7}, {x = 4, y = 1, z = 7}, 2), "near: 3 tiles is not")
	check(not K.near({x = 1, y = 1, z = 7}, {x = 1, y = 1, z = 6}, 2), "near: another floor is not")
	check(not K.near(nil, {x = 1, y = 1, z = 7}, 2), "near: no position")
	eq(K.cooldownLeft(cfg, 100, nil), 0, "no journey yet")
	eq(K.cooldownLeft(cfg, 100, 0), 0, "zero")
	eq(K.cooldownLeft(cfg, 110, 100), 20, "20 seconds left")
	eq(K.cooldownLeft(cfg, 131, 100), 0, "done")
	eq(K.cooldownLeft(cfg, 100.5, 100), 30, "rounded up")

	eq(K.blockReason({}, nil, cfg.labels), nil, "allowed")
	check(K.blockReason({inFight = true}, nil, cfg.labels):find("combat", 1, true), "combat")
	check(K.blockReason({skull = true}, nil, cfg.labels):find("skull", 1, true), "skull")
	check(K.blockReason({rift = true}, nil, cfg.labels):find("a rift", 1, true), "rift")
	check(K.blockReason({arena = true}, nil, cfg.labels):find("arena match", 1, true), "arena")
	check(K.blockReason({tower = true}, nil, cfg.labels):find("Infinity Tower", 1, true), "tower")
	check(K.blockReason({instance = "a raid"}, nil, cfg.labels):find("a raid", 1, true), "any other instance")
	check(K.blockReason({tutorial = true}, nil, cfg.labels):find("tutorial", 1, true), "tutorial")
	check(K.blockReason({casting = true}, nil, cfg.labels):find("portal", 1, true), "town portal channel")
	check(K.blockReason({disabled = true}, nil, cfg.labels):find("switched off", 1, true), "off")
	check(K.blockReason({cooldownLeft = 1}, nil, cfg.labels):find("1 second", 1, true), "cooldown 1")
	check(K.blockReason({cooldownLeft = 12}, nil, cfg.labels):find("12 seconds", 1, true), "cooldown 12")
	-- the cooldown is told before the place, the place before combat
	check(K.blockReason({cooldownLeft = 5, rift = true, inFight = true}, nil, cfg.labels):find("5 seconds", 1, true), "order: cooldown")
	check(K.blockReason({rift = true, inFight = true}, nil, cfg.labels):find("a rift", 1, true), "order: place")
	-- the player's language comes through T
	eq(K.blockReason({inFight = true}, function(k) return "T:" .. k end, cfg.labels), "T:You cannot travel to an NPC while you are in combat.", "T is used")
end

-- ---------------------------------------------------------------- validate catches mistakes
do
	local bad = {npcs = {a = {name = "X", where = "w"}, b = {name = "X", where = ""}, c = {name = "Y", townId = 99, where = "w"}}}
	local p = K.validate(bad, booths, nil, {[1] = true})
	check(#p >= 4, "a bad config is reported (" .. #p .. ")")
	local fp = K.validate(cfg, booths, {{key = "ghost", npc = {name = "Ghost", townId = 1}}}, nil)
	eq(#fp, 1, "a faction without an entry")
	fp = K.validate(cfg, booths, {{key = "compact", npc = {name = "Forgemaster Brannoc", townId = 4}}}, nil)
	eq(#fp, 1, "a faction NPC in another town than the entry")
	eq(#K.validate(nil), 1, "no config")
end

-- ---------------------------------------------------------------- the glue, on a mocked engine
do
	CONST_ME_TELEPORT = 11
	MESSAGE_STATUS_SMALL = 19
	CONST_PROP_BLOCKSOLID, CONST_PROP_BLOCKPATH, CONST_PROP_IMMOVABLEBLOCKSOLID = 1, 2, 3
	TILESTATE_FLOORCHANGE, TILESTATE_TELEPORT, TILESTATE_MAGICFIELD = 1, 2, 3
	CONDITION_INFIGHT = 8

	local blocked = {} -- "x:y:z" -> true (a wall)
	local occupied = {}
	local npcs = {} -- name -> {x, y, z}
	local sentEffects = {}
	local function key(p) return p.x .. ":" .. p.y .. ":" .. p.z end

	function Position(x, y, z)
		local p = {x = x, y = y, z = z}
		function p:sendMagicEffect(e) sentEffects[#sentEffects + 1] = {x = self.x, y = self.y, e = e} end
		return p
	end
	function Tile(p)
		if p.x < 31000 then return nil end
		local t = {}
		function t:getGround() return {} end
		function t:getHouse() return nil end
		function t:hasProperty(prop) return blocked[key(p)] == true and prop == CONST_PROP_BLOCKSOLID end
		function t:hasFlag() return false end
		function t:getTopCreature() return occupied[key(p)] end
		return t
	end
	function Creature(name)
		local at = npcs[name]
		if not at then return nil end
		return {isNpc = function() return true end, getPosition = function() return Position(at.x, at.y, at.z) end}
	end
	function Town(id)
		local temples = {[1] = {x = 32957, y = 32076, z = 7}, [2] = {x = 32369, y = 32241, z = 7}}
		local t = temples[id]
		if not t then return nil end
		return {getTemplePosition = function() return Position(t.x, t.y, t.z) end}
	end

	local events, registered = {}, {}
	function CreatureEvent(name)
		local ev = {name = name}
		function ev:type() end
		function ev:register() events[name] = self end
		return ev
	end
	function GlobalEvent(name)
		local ev = {name = name}
		function ev:register() events[name] = self end
		return ev
	end

	local cancels, texts = {}, {}
	local teleports = {}
	local function newPlayer(guid, at)
		local p = {guid = guid, pos = at, fight = false, skull = false}
		function p:getGuid() return self.guid end
		function p:getId() return self.guid end
		function p:getStorageValue() return -1 end
		function p:getPosition() return Position(self.pos.x, self.pos.y, self.pos.z) end
		function p:teleportTo(to) self.pos = {x = to.x, y = to.y, z = to.z}; teleports[#teleports + 1] = {x = to.x, y = to.y, z = to.z} end
		function p:isPzLocked() return self.fight end
		function p:hasCondition() return false end
		function p:sendCancelMessage(t) cancels[#cancels + 1] = t end
		function p:sendTextMessage(_, t) texts[#texts + 1] = t end
		function p:registerEvent(n) registered[#registered + 1] = n end
		return p
	end

	ChaosTownPortal = {blockFacts = function(player) return player.facts or {} end}
	dofile("data/scripts/chaos/npc_travel.lua")
	local T = ChaosNpcTravel
	check(events.ChaosNpcTravelExtended ~= nil, "the opcode handler is registered")
	events.ChaosNpcTravelLogin.onLogin(newPlayer(1, {x = 1, y = 1, z = 7}))
	eq(registered[1], "ChaosNpcTravelExtended", "the handler is added at login")
	events.ChaosNpcTravelStartup.onStartup()

	local function send(player, message)
		NEXT_MESSAGE = message
		cancels, texts = {}, {}
		events.ChaosNpcTravelExtended.onExtendedOpcode(player, 121, "x")
	end
	local HUNT = {x = 32000, y = 32000, z = 7}

	-- the Gambler: not placed yet -> the stall; the first free tile in front of the counter
	local p = newPlayer(10, HUNT)
	send(p, {action = "travel", data = {k = "gambler"}})
	eq(#teleports, 1, "gambler: teleported")
	eq(teleports[1].x, 31660, "gambler: stall x")
	eq(teleports[1].y, 32232, "gambler: on the carpet, across the counter")
	eq(texts[1], "You stand before Mordecai Ashwager.", "gambler: told")
	eq(#sentEffects, 2, "gambler: effects at both ends")

	-- a second journey at once: refused by the rate limit or the cooldown, no teleport
	send(p, {action = "travel", data = {k = "stash"}})
	eq(#teleports, 1, "no second journey at once")
	-- the cooldown by itself (the rate limit is the module's own)
	local why = T.blockReason(p)
	check(why and why:find("again in", 1, true), "cooldown text: " .. tostring(why))
	T.last[10] = os.time() - cfg.cooldownSeconds - 1
	eq(T.blockReason(p), nil, "cooldown over")

	-- next to the NPC already: no journey, no cooldown
	local near = newPlayer(11, {x = 31666, y = 32232, z = 7})
	local ok, text = T.go(near, "stash")
	eq(ok, false, "next to Tavish: no journey")
	check(text:find("already next to Tavish Coldhand", 1, true), "next to Tavish: told")
	eq(T.last[11], nil, "no cooldown after a refusal")

	-- the front tile taken by a creature: the next tile of the carpet
	occupied["31666:32232:7"] = true
	local q = newPlayer(12, HUNT)
	ok = T.go(q, "stash")
	check(ok, "stash with the first tile taken")
	eq(q.pos.y, 32232, "stash: still the carpet")
	check(q.pos.x ~= 31666, "stash: a tile beside the taken one")
	occupied["31666:32232:7"] = nil

	-- the whole front blocked (walls): the ring behind the counter is not used before the carpet is tried; with all
	-- of the 24 tiles blocked there is a friendly refusal and no cooldown
	local wall = newPlayer(13, HUNT)
	for _, c in ipairs(K.candidates({x = 31666, y = 32230, z = 7}, nil, 2, false)) do blocked[c.x .. ":" .. c.y .. ":" .. c.z] = true end
	ok, text = T.go(wall, "stash")
	eq(ok, false, "all tiles blocked")
	check(text:find("no free spot in front of Tavish Coldhand", 1, true) ~= nil or text:find("There is no free spot", 1, true) ~= nil, "blocked: told")
	eq(T.last[13], nil, "blocked: no cooldown")
	blocked = {}

	-- combat, a skull, a rift: refused, nothing moves
	local fighter = newPlayer(14, HUNT)
	fighter.fight = true
	ok, text = T.go(fighter, "stash")
	eq(ok, false, "combat: refused")
	check(text:find("combat", 1, true), "combat: told")
	eq(fighter.pos.x, HUNT.x, "combat: not moved")
	local rifter = newPlayer(15, HUNT)
	rifter.facts = {rift = true}
	ok, text = T.go(rifter, "stash")
	eq(ok, false, "rift: refused")
	check(text:find("a rift", 1, true), "rift: told")
	local skull = newPlayer(16, HUNT)
	skull.facts = {skull = true}
	eq((T.go(skull, "stash")), false, "skull: refused")
	local inst = newPlayer(17, HUNT)
	inst.facts = {instance = "a raid"}
	ok, text = T.go(inst, "stash")
	check(not ok and text:find("a raid", 1, true), "instance: refused with its label")

	-- an NPC placed in another town (live): the player lands beside it, toward the temple
	npcs["Forgemaster Brannoc"] = {x = 32961, y = 32073, z = 7}
	local far = newPlayer(18, HUNT)
	ok, text = T.go(far, "faction_compact")
	check(ok, "Brannoc: travel")
	check(math.max(math.abs(far.pos.x - 32961), math.abs(far.pos.y - 32073)) == 1, "Brannoc: right beside him")
	eq(text, "You stand before Forgemaster Brannoc.", "Brannoc: told")

	-- an NPC that is not placed, in a town with a known temple: the temple, said plainly
	npcs["Forgemaster Brannoc"] = nil
	local lost = newPlayer(19, HUNT)
	ok, text = T.go(lost, "faction_compact")
	check(ok, "Brannoc not placed: the temple")
	check(text:find("was not found", 1, true), "Brannoc not placed: told")
	-- an NPC of a town the map does not give: a friendly line
	local nowhere = newPlayer(20, HUNT)
	ok, text = T.go(nowhere, "faction_choir")
	eq(ok, false, "Velith with no town: refused")
	check(text:find("not at their post", 1, true), "Velith: friendly line")
	eq(nowhere.pos.x, HUNT.x, "Velith: not moved")
	-- a key the server does not know
	ok = T.go(newPlayer(21, HUNT), "../etc")
	eq(ok, false, "unknown key")
	send(newPlayer(22, HUNT), {action = "travel", data = {k = 5}})
	eq(#cancels, 1, "a key of the wrong type is answered, not raised on")
	send(newPlayer(23, HUNT), {action = "other"})
	eq(#cancels + #texts, 0, "another action is ignored")
	-- the where text for the faction window
	eq(T.where(newPlayer(24, HUNT), "faction_vigil"), "Warden Ysolde, in the market of the teleport room in Cinderhold", "where text")
	eq(T.where(newPlayer(24, HUNT), "nothing"), nil, "where: unknown")
end

print(string.format("npc_travel_test: %s (%d checks)", failures == 0 and "OK" or (failures .. " FAILED"), checks))
if failures > 0 then os.exit(1) end
