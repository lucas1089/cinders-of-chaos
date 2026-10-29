-- Points of interest on the map (client game_mapmarkers, extended opcode ChaosOpcodes.mapMarkers = 153, shared with
-- partymarkers.lua; server/README.md "Map markers").
--
-- The marks: data/chaos_poi.lua (generated at install by tools/gen_poi.py from the map, items, NPC files and spawn data:
-- temples, depots, crafting tables, service NPCs, hunting areas, boss places) plus what the systems place when the
-- server starts, found cfg.firstScanMs after the start and every cfg.rescanMs: the Chaos NPCs and the portals next to
-- the temples, the Chaos NPCs in the stalls of the hub (npc_booths_config.lua) and the dungeons of the base dungeon system. Rules (keys, reveal, view): poi_core.lua
-- (tests/poi_test.lua); numbers and names: poi_config.lua.
-- Discovery: marks with r = 1 are shown once the character came within cfg.revealRange squares (checked every
-- cfg.checkMs for every online character, also when its client shows no markers, so turning them on later shows what
-- was found). The discoveries are one row per character in chaos_poi_seen (sql/chaos_poi.sql), read at login and
-- written at most every cfg.saveMs and at logout.
--
-- Protocol (JSON {action, data}):
--   client -> server  hello {poi = true|false, party = ...} | set {poi = true|false}
--   server -> client  poi {v = version, marks = [{k, x, y, z, n}]}   (Chaos.sendChunked: it can pass 8 KB)
--                     reveal {marks = [{k, x, y, z, n}]}               (newly discovered)
-- Staff: /poi status | reset (forget my discoveries) | all (discover everything). Lua 5.1 / LuaJIT compatible.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not Chaos.t then
	dofile("data/scripts/chaos/i18n_core.lua")
end
dofile("data/scripts/chaos/poi_core.lua")

local I = ChaosPoi
local cfg = dofile("data/scripts/chaos/poi_config.lua")
I.cfg = cfg
local OPCODE = ChaosOpcodes.mapMarkers or 153
local TABLE = Chaos.tables.poiSeen or "chaos_poi_seen"

I.watch = I.watch or {} -- creature id -> true while the client shows points of interest
I.seen = I.seen or {} -- player guid -> set of keys
I.dirty = I.dirty or {} -- player guid -> true while unsaved
I.runtime = I.runtime or {}
I.stats = I.stats or {checks = 0, checkMs = 0, reveals = 0}

local function loadStatic()
	local ok, data = pcall(dofile, cfg.dataFile)
	if not ok then
		print("[Chaos poi] " .. cfg.dataFile .. " not loaded (run tools/gen_poi.py, install step poi): " .. tostring(data))
		data = nil
	end
	I.static, I.staticVersion = I.load(data)
end

local function rebuild()
	I.all, I.version = I.merge(I.static or {}, I.runtime, I.staticVersion)
	I.idx = I.index(I.all)
end

loadStatic()
rebuild()

-- ---------------------------------------------------------------- the database
local tableReady = false
local function ensureTable()
	if tableReady then
		return
	end
	db.query("CREATE TABLE IF NOT EXISTS `" .. TABLE .. "` (`player_id` int(11) NOT NULL, `seen` mediumtext NOT NULL, " ..
		"PRIMARY KEY (`player_id`)) ENGINE=InnoDB DEFAULT CHARSET=utf8")
	tableReady = true
end

local function loadSeen(guid)
	ensureTable()
	local set = {}
	local rid = db.storeQuery("SELECT `seen` FROM `" .. TABLE .. "` WHERE `player_id` = " .. tonumber(guid))
	if rid then
		set = I.decodeSeen(result.getString(rid, "seen"))
		result.free(rid)
	end
	I.seen[guid] = set
	return set
end

local function saveSeen(guid)
	local set = I.seen[guid]
	if not set or not I.dirty[guid] then
		return
	end
	ensureTable()
	db.asyncQuery(string.format("REPLACE INTO `%s` (`player_id`, `seen`) VALUES (%d, %s)", TABLE, tonumber(guid),
		db.escapeString(I.encodeSeen(set))))
	I.dirty[guid] = nil
end

local function seenOf(player)
	local guid = player:getGuid()
	return I.seen[guid] or loadSeen(guid), guid
end

-- ---------------------------------------------------------------- sending
local function sendAll(player)
	local set = seenOf(player)
	local buffer = json.encode({action = "poi", data = {v = I.version, marks = I.view(I.all, set)}})
	Chaos.sendChunked(player, OPCODE, buffer)
end

local function sendReveal(player, found)
	local list = {}
	for _, m in ipairs(found) do
		list[#list + 1] = {k = m.k, x = m.x, y = m.y, z = m.z, n = m.n}
	end
	Chaos.send(player, OPCODE, "reveal", {marks = list})
end

-- ---------------------------------------------------------------- the runtime marks
local portalIds
local function portals()
	if not portalIds then
		portalIds = I.portalIds(cfg.portals, function(file)
			local ok, t = pcall(dofile, "data/scripts/chaos/" .. file)
			return ok and type(t) == "table" and t or nil
		end, _G)
	end
	return portalIds
end

local function scanRuntime()
	local list = {}
	local byAid = portals()
	local towns = Game.getTowns and Game.getTowns() or {}
	local r = cfg.templeRadius
	for _, town in ipairs(towns) do
		local temple = town:getTemplePosition()
		if temple then
			for _, c in ipairs(Game.getSpectators(temple, false, false, r, r, r, r) or {}) do
				if c:isNpc() then
					local name = I.npcName(cfg, c:getName())
					local pos = c:getPosition()
					local m = name and I.mark("npc", pos.x, pos.y, pos.z, name, 0)
					if m then
						list[#list + 1] = m
					end
				end
			end
			for x = temple.x - r, temple.x + r do
				for y = temple.y - r, temple.y + r do
					local tile = Tile(Position(x, y, temple.z))
					if tile then
						for _, item in ipairs(tile:getItems() or {}) do
							local p = byAid[item:getActionId()]
							local m = p and I.mark(p.kind, x, y, temple.z, p.name, 0)
							if m then
								list[#list + 1] = m
							end
						end
					end
				end
			end
		end
	end
	-- the Chaos NPCs in the stalls of the hub: far from every temple, found at their stall tiles
	if ChaosNpcBoothsCore or pcall(dofile, "data/scripts/chaos/npc_booths_core.lua") then
		local K = ChaosNpcBoothsCore
		local hubR = cfg.hubRadius or 1
		local stalls = K.booths(K.cfg())
		for _, m in ipairs(I.hubMarks(cfg, stalls, function(b)
			local found = {}
			for _, c in ipairs(Game.getSpectators(Position(b.x, b.y, b.z), false, false, hubR, hubR, hubR, hubR) or {}) do
				if c:isNpc() then
					local pos = c:getPosition()
					found[#found + 1] = {name = c:getName(), x = pos.x, y = pos.y, z = pos.z}
				end
			end
			return found
		end)) do
			list[#list + 1] = m
		end
	end
	if cfg.dungeons and type(DUNGEON_SYSTEM) == "table" and type(DUNGEON_SYSTEM.Dungeons) == "table" then
		local extra = Chaos.dungeons and Chaos.dungeons.extra or {}
		for id, d in pairs(DUNGEON_SYSTEM.Dungeons) do
			local pos = type(d) == "table" and d.DungeonPos
			local ex = extra[id]
			local name = ex and ex.title
			if pos and name then
				local m = I.mark("dungeon", pos.x, pos.y, pos.z, string.format("%s (dungeon, level %d)", name,
					tonumber(d.Level) or 0), 1)
				if m then
					list[#list + 1] = m
				end
			end
		end
	end
	table.sort(list, function(a, b)
		return I.key(a) < I.key(b)
	end)
	return list
end

local function refreshRuntime()
	local ok, list = pcall(scanRuntime)
	if not ok then
		print("[Chaos poi] runtime scan: " .. tostring(list))
		return
	end
	local old = I.version
	I.runtime = list
	rebuild()
	if I.version ~= old then
		for id in pairs(I.watch) do
			local p = Player(id)
			if p then
				sendAll(p)
			end
		end
	end
end

-- ---------------------------------------------------------------- events
local start = GlobalEvent("ChaosPoiStartup")
function start.onStartup()
	addEvent(refreshRuntime, cfg.firstScanMs)
	return true
end
start:type("startup")
start:register()

local lastRescan, lastSave = os.time(), os.time()
local think = GlobalEvent("ChaosPoiThink")
function think.onThink(interval)
	local t0 = os.mtime and os.mtime() or os.clock() * 1000
	for _, player in ipairs(Game.getPlayers()) do
		local set, guid = seenOf(player)
		local found = I.reveal(I.idx, player:getPosition(), cfg.revealRange, set)
		if #found > 0 then
			I.dirty[guid] = true
			I.stats.reveals = I.stats.reveals + #found
			if I.watch[player:getId()] then
				sendReveal(player, found)
			end
			local names = {}
			for i = 1, math.min(#found, 3) do
				names[i] = found[i].n
			end
			player:sendTextMessage(MESSAGE_STATUS_SMALL, Chaos.t(player, "Discovered on your map: %s", table.concat(names, "; ")) ..
				(#found > 3 and Chaos.t(player, " and %d more", #found - 3) or ""))
		end
	end
	I.stats.checks, I.stats.checkMs = I.stats.checks + 1, I.stats.checkMs + ((os.mtime and os.mtime() or os.clock() * 1000) - t0)
	local now = os.time()
	if (now - lastSave) * 1000 >= cfg.saveMs then
		lastSave = now
		for guid in pairs(I.dirty) do
			saveSeen(guid)
		end
	end
	if (now - lastRescan) * 1000 >= cfg.rescanMs then
		lastRescan = now
		refreshRuntime()
	end
	return true
end
think:interval(cfg.checkMs)
think:register()

local login = CreatureEvent("ChaosPoiLogin")
function login.onLogin(player)
	player:registerEvent("ChaosPoiExtended")
	player:registerEvent("ChaosPoiLogout")
	loadSeen(player:getGuid())
	return true
end
login:type("login")
login:register()

local logout = CreatureEvent("ChaosPoiLogout")
function logout.onLogout(player)
	local guid = player:getGuid()
	saveSeen(guid)
	I.seen[guid], I.dirty[guid] = nil, nil
	I.watch[player:getId()] = nil
	return true
end
logout:type("logout")
logout:register()

local ext = CreatureEvent("ChaosPoiExtended")
function ext.onExtendedOpcode(player, opcode, buffer)
	if opcode ~= OPCODE then
		return
	end
	local msg = Chaos.decode(buffer)
	if not msg or (msg.action ~= "hello" and msg.action ~= "set") then
		return
	end
	local data = type(msg.data) == "table" and msg.data or {}
	if data.poi == nil then
		return
	end
	if msg.action == "set" and ChaosRateLimit and not ChaosRateLimit.allow(player, "poi.set", cfg.setMs) then
		return
	end
	if data.poi == true then
		I.watch[player:getId()] = true
		sendAll(player)
	else
		I.watch[player:getId()] = nil
	end
end
ext:type("extendedopcode")
ext:register()

local talk = TalkAction("/poi")
function talk.onSay(player, words, param)
	if not player:getGroup():getAccess() or player:getGroup():getId() < cfg.staffGroup then
		return false
	end
	local cmd = tostring(param or ""):match("^%s*(%S*)")
	local set, guid = seenOf(player)
	if cmd == "reset" then
		I.seen[guid] = {}
		I.dirty[guid] = true
		saveSeen(guid)
	elseif cmd == "all" then
		for _, m in ipairs(I.all) do
			if m.r == 1 then
				set[I.key(m)] = true
			end
		end
		I.dirty[guid] = true
		saveSeen(guid)
	elseif cmd == "rescan" then
		refreshRuntime()
	end
	if I.watch[player:getId()] then
		sendAll(player)
	end
	local discoverable, mine = 0, 0
	for _, m in ipairs(I.all) do
		if m.r == 1 then
			discoverable = discoverable + 1
			if (I.seen[guid] or {})[I.key(m)] then
				mine = mine + 1
			end
		end
	end
	player:sendTextMessage(MESSAGE_INFO_DESCR, string.format(
		"POI %s: %d marks (%d static, %d runtime), %d discoverable, %d discovered by you; checks %d (%.2f ms each), %d reveals.",
		I.version, #I.all, #(I.static or {}), #I.runtime, discoverable, mine, I.stats.checks,
		I.stats.checks > 0 and I.stats.checkMs / I.stats.checks or 0, I.stats.reveals))
	return false
end
talk:separator(" ")
talk:register()
