-- Rift Atlas (client game_riftatlas, extended opcode ChaosOpcodes.riftAtlas = 210): the long-term progression tree of
-- the rifts. Numbers and the node graph: atlas_config.lua; pure logic: atlas_core.lua (tests/riftatlas_test.lua);
-- overview: server/README.md "Rift Atlas".
--
-- Points come from first completions on a finite grid (theme x tier, flawless and swift per tier, the Omen guardians;
-- every finisher of a sealed rift is credited, online or not). They buy nodes of a map: a core and four theme branches
-- with small nodes, notables and keystones. The effects reach the rifts through ChaosRiftCore.hooks (rift_core.lua
-- "rift atlas"): the key user's atlas shapes the run, each finisher's own atlas adds to their chest.
--
-- Persistence: one row per character in chaos_rift_atlas (sql/chaos_rift_atlas.sql; created here when missing):
-- `done` = the completed cells, `nodes` = the allocated node ids (both comma lists). Season characters are characters
-- of their own (season.lua), so every realm has its own atlas; a migrated character keeps its atlas as it keeps its
-- levels.
--
-- Protocol (JSON {action, data}; the tree goes out with Chaos.sendChunked):
--   client -> server  open {tree = true when the client has none} | alloc {id} | refund {id, pay = "gold"|"orb"} | reset {pay}
--   server -> client  tree {nodes, branches, start, keystoneMax, grid, max}    (once per login, on the first open)
--                     state {earned, spent, points, max, alloc, done, refund, reset, orb, totals, msg}
--                     credit {cells = [names], points}                        (a sealed rift added cells)
-- Lua 5.1 / LuaJIT.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not Chaos.t then
	dofile("data/scripts/chaos/i18n_core.lua")
end
dofile("data/scripts/chaos/atlas_core.lua")
ChaosAtlasConfig = ChaosAtlasConfig or dofile("data/scripts/chaos/atlas_config.lua")
-- the Swift times come from the rift model (atlas_core.lua A.swiftSeconds -> rift_core.lua R.clearSeconds); rift.lua
-- loads rift_core.lua too (it keeps R.hooks), whichever script comes first
if not (ChaosRiftCore and ChaosRiftCore.clearSeconds) then
	dofile("data/scripts/chaos/rift_core.lua")
end
ChaosRiftCore = ChaosRiftCore or {}
ChaosRiftCore.hooks = ChaosRiftCore.hooks or {}

ChaosAtlas = ChaosAtlas or {}
local S = ChaosAtlas
local A = ChaosAtlasCore
local cfg = ChaosAtlasConfig
local OPCODE = ChaosOpcodes and ChaosOpcodes.riftAtlas or cfg.opcode
local TABLE = (Chaos.tables and Chaos.tables.riftAtlas) or cfg.table

S.state = S.state or {} -- guid -> {alloc = {[id] = true}, done = {[cell] = true}}
S.treeSent = S.treeSent or {} -- player id -> true once the tree went out this login
S.online = S.online or {} -- guid -> player id (Player(number) takes a creature id, not a guid)

local function RC()
	if not ChaosRiftConfig then
		ChaosRiftConfig = dofile("data/scripts/chaos/rift_config.lua")
	end
	return ChaosRiftConfig
end

local function log(text)
	print("[Chaos atlas] " .. text)
end

-- ======================================================================== database
local tableReady = false
local function ensureTable()
	if not tableReady then
		tableReady = db.query("CREATE TABLE IF NOT EXISTS `" .. TABLE .. "` (`player_id` int(11) NOT NULL, " ..
			"`done` text NOT NULL, `nodes` varchar(1024) NOT NULL DEFAULT '', `updated` int(10) unsigned NOT NULL DEFAULT 0, " ..
			"PRIMARY KEY (`player_id`), CONSTRAINT `chaos_rift_atlas_player_fk` FOREIGN KEY (`player_id`) REFERENCES " ..
			"`players` (`id`) ON DELETE CASCADE) ENGINE=InnoDB DEFAULT CHARSET=utf8") and true
	end
	return tableReady
end

local function loadRow(guid)
	ensureTable()
	local st = {alloc = {}, done = {}}
	local rid = db.storeQuery("SELECT `done`, `nodes` FROM `" .. TABLE .. "` WHERE `player_id` = " .. guid)
	if rid then
		st.done = A.decodeSet(result.getString(rid, "done"))
		st.alloc = A.decodeSet(result.getString(rid, "nodes"), true)
		result.free(rid)
	end
	return st
end

local function saveRow(guid, st)
	ensureTable()
	return db.query(string.format("INSERT INTO `%s` (`player_id`, `done`, `nodes`, `updated`) VALUES (%d, %s, %s, %d) " ..
		"ON DUPLICATE KEY UPDATE `done` = VALUES(`done`), `nodes` = VALUES(`nodes`), `updated` = VALUES(`updated`)",
		TABLE, guid, db.escapeString(A.encodeSet(st.done)), db.escapeString(A.encodeSet(st.alloc)), os.time()))
end

-- the state of a character (loaded once per login, made valid against the current config)
function S.get(guid)
	local st = S.state[guid]
	if not st then
		st = loadRow(guid)
		local clean, changed = A.sanitize(cfg, RC(), st.alloc, st.done)
		st.alloc = clean
		if changed then
			saveRow(guid, st)
			log(string.format("player %d: allocation adjusted to the current atlas", guid))
		end
		S.state[guid] = st
	end
	return st
end

-- ======================================================================== the hooks of rift_core.lua
ChaosRiftCore.hooks.atlasMods = function(player, ctx)
	local st = S.get(player:getGuid())
	return A.resolve(cfg, st.alloc, ctx)
end

local function sendState(player, msg)
	Chaos.send(player, OPCODE, "state", A.statePayload(cfg, RC(), S.get(player:getGuid()), msg))
end

-- credit of a sealed rift (every finisher; one who is offline is written straight to the database)
ChaosRiftCore.hooks.onSealed = function(info)
	local keys = A.runCells(cfg, RC(), info)
	if #keys == 0 then
		return
	end
	for _, guid in ipairs(info.guids or {}) do
		local cached = S.state[guid] ~= nil
		local st = cached and S.state[guid] or loadRow(guid)
		local new, pts = A.credit(cfg, RC(), st.done, keys)
		if #new > 0 then
			saveRow(guid, st)
			if ChaosSeasonJourney and ChaosSeasonJourney.emit then -- Seasonal Journey (season_journey.lua)
				ChaosSeasonJourney.emit(guid, "atlas_points", A.earned(cfg, RC(), st.done), "max")
			end
			local player = S.online[guid] and Player(S.online[guid])
			if player and player:getGuid() == guid then
				local names = {}
				for _, c in ipairs(new) do
					names[#names + 1] = A.cellName(RC(), c)
				end
				player:sendTextMessage(MESSAGE_EVENT_ADVANCE, Chaos.t(player, "Rift Atlas: %s completed, +%d point%s.",
					table.concat(names, ", "), pts, pts == 1 and "" or "s"))
				Chaos.send(player, OPCODE, "credit", {cells = names, points = pts})
				if S.treeSent[player:getId()] then
					sendState(player)
				end
			end
		end
	end
end

-- ======================================================================== actions
local function charge(player, price, pay)
	if pay == "orb" then
		local r = cfg.respec
		if player:getItemCount(r.orbItem) < price.orbs then
			return false, string.format("You need %d %s.", price.orbs, r.orbName .. (price.orbs == 1 and "" or "s"))
		end
		if not player:removeItem(r.orbItem, price.orbs) then
			return false, "The orbs could not be taken."
		end
		return true
	end
	if price.gold <= 0 then
		return true
	end
	local paid
	paid = Chaos.pay(player, price.gold)
	if not paid then
		return false, string.format("You need %d gold (carried or in the bank).", price.gold)
	end
	return true
end

local REASONS = {
	unknown = "That node does not exist.", held = "You hold that node already.",
	points = "Not enough atlas points: seal new rifts to earn more.",
	keystone = "You can hold only one keystone. Refund the other first.",
	path = "That node is not connected to your atlas.", ["not held"] = "You do not hold that node."
}

local function onAlloc(player, data)
	local st = S.get(player:getGuid())
	local id = Chaos.toInt(data and data.id, 1, 100000)
	local points = A.earned(cfg, RC(), st.done) - A.spent(cfg, st.alloc)
	local ok, why = A.canAllocate(cfg, st.alloc, id, points)
	if not ok then
		sendState(player, REASONS[why] or why)
		return
	end
	st.alloc[id] = true
	saveRow(player:getGuid(), st)
	sendState(player)
end

local function onRefund(player, data)
	local st = S.get(player:getGuid())
	local id = Chaos.toInt(data and data.id, 1, 100000)
	local ok, why = A.canRefund(cfg, st.alloc, id)
	if not ok then
		sendState(player, why == "path" and "Other nodes depend on that one: refund them first." or (REASONS[why] or why))
		return
	end
	local paid, err = charge(player, A.refundPrice(cfg, 1), data.pay)
	if not paid then
		sendState(player, err)
		return
	end
	st.alloc[id] = nil
	saveRow(player:getGuid(), st)
	sendState(player, "Node refunded.")
end

local function onReset(player, data)
	local st = S.get(player:getGuid())
	if A.count(st.alloc) == 0 then
		sendState(player, "Your atlas is empty.")
		return
	end
	local paid, err = charge(player, A.resetPrice(cfg, st.alloc), data.pay)
	if not paid then
		sendState(player, err)
		return
	end
	st.alloc = {}
	saveRow(player:getGuid(), st)
	sendState(player, "Every node refunded.")
end

local ext = CreatureEvent("ChaosAtlasExtended")
function ext.onExtendedOpcode(player, opcode, buffer)
	if opcode ~= OPCODE then
		return
	end
	if ChaosRateLimit and not ChaosRateLimit.allow(player, "atlas", cfg.requestMs) then
		return
	end
	local msg = Chaos.decode(buffer)
	if not msg then
		return
	end
	local data = type(msg.data) == "table" and msg.data or {}
	local ok, err = pcall(function()
		if msg.action == "open" then
			if not S.treeSent[player:getId()] or data.tree then -- tree = true: the client has none (a module reload)
				S.treeSent[player:getId()] = true
				Chaos.sendChunked(player, OPCODE, json.encode({action = "tree", data = A.treePayload(cfg, RC())}))
			end
			sendState(player)
		elseif msg.action == "alloc" then
			onAlloc(player, data)
		elseif msg.action == "refund" then
			onRefund(player, data)
		elseif msg.action == "reset" then
			onReset(player, data)
		end
	end)
	if not ok then
		log("opcode: " .. tostring(err))
	end
end
ext:type("extendedopcode")
ext:register()

local login = CreatureEvent("ChaosAtlasLogin")
function login.onLogin(player)
	player:registerEvent("ChaosAtlasExtended")
	player:registerEvent("ChaosAtlasLogout")
	S.treeSent[player:getId()] = nil
	S.online[player:getGuid()] = player:getId()
	S.state[player:getGuid()] = nil -- fresh from the database (an offline credit may have changed it)
	pcall(S.get, player:getGuid())
	return true
end
login:register()

local logout = CreatureEvent("ChaosAtlasLogout")
function logout.onLogout(player)
	S.treeSent[player:getId()] = nil
	S.online[player:getGuid()] = nil
	S.state[player:getGuid()] = nil
	return true
end
logout:register()

-- staff (testing): /atlas grant all | grant <cell key> | clear | status
local talk = TalkAction("/atlas")
function talk.onSay(player, words, param)
	if not player:getGroup():getAccess() then
		return false
	end
	local cmd, arg = (param or ""):match("^%s*(%S*)%s*(.-)%s*$")
	-- cells give atlas points: an administrator only, logged (docs/GM_HANDBOOK.md section 2)
	if cmd == "grant" and not Chaos.staffCommand(player, words, param, true) then
		return false
	end
	local st = S.get(player:getGuid())
	if cmd == "grant" then
		local keys = {}
		for _, c in ipairs(A.cells(cfg, RC())) do
			if arg == "all" or c.key == arg then
				keys[#keys + 1] = c.key
			end
		end
		local new, pts = A.credit(cfg, RC(), st.done, keys)
		saveRow(player:getGuid(), st)
		player:sendTextMessage(MESSAGE_INFO_DESCR, string.format("Atlas: %d cell(s), +%d point(s).", #new, pts))
	elseif cmd == "clear" then
		st.done, st.alloc = {}, {}
		saveRow(player:getGuid(), st)
		player:sendTextMessage(MESSAGE_INFO_DESCR, "Atlas cleared.")
	else
		local p = A.statePayload(cfg, RC(), st)
		player:sendTextMessage(MESSAGE_INFO_DESCR, string.format("Atlas: %d / %d points earned, %d spent, %d nodes.",
			p.earned, p.max, p.spent, #p.alloc))
	end
	if S.treeSent[player:getId()] then
		sendState(player)
	end
	return false
end
talk:separator(" ")
talk:register()
