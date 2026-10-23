-- Waystone Atlas (client game_riftatlas in waystone mode, extended opcode ChaosOpcodes.waystoneAtlas = 159): the
-- long-term progression of the waystone maps. Numbers and the node graph: waystone_atlas_config.lua; pure logic:
-- waystone_atlas_core.lua (tests/waystone_atlas_test.lua); overview: server/README.md "Waystone Atlas".
--
-- Points come from first completions on a finite grid: each map at each tier of its band and a Rare completion per tier
-- (the map's boss killed during a waystone run; every player inside the map is credited). They buy nodes of a map
-- shaped like the Rift Atlas's. The effects reach the waystone runs through the hooks of waystone_mods.lua and
-- waystone_tiers.lua: the atlas of the player who opened the map (the device took their waystone) shapes the run:
-- item quantity, rarity, experience, the extra waystone chance, the modifiers' reward bonuses and the waystones that drop.
--
-- Persistence: one row per character in chaos_waystone_atlas (sql/chaos_waystone_atlas.sql; created here when missing).
-- Protocol (JSON {action, data}; the tree goes out with Chaos.sendChunked), as the Rift Atlas's:
--   client -> server  open {tree} | alloc {id} | refund {id, pay = "gold"|"orb"} | reset {pay}
--   server -> client  tree {kind = "waystone", nodes, branches, start, keystoneMax, grid = {tiers, rows}, max}
--                     state {earned, spent, points, max, alloc, done, refund, reset, orb, totals, msg}
--                     credit {cells = [names], points}
-- Lua 5.1 / LuaJIT.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not Chaos.t then
	dofile("data/scripts/chaos/i18n_core.lua")
end
dofile("data/scripts/chaos/waystone_atlas_core.lua")
if not ChaosWaystoneTiersCore then
	dofile("data/scripts/chaos/waystone_tiers_core.lua")
end
ChaosWaystoneAtlasConfig = ChaosWaystoneAtlasConfig or dofile("data/scripts/chaos/waystone_atlas_config.lua")

ChaosWaystoneAtlas = ChaosWaystoneAtlas or {}
local WA = ChaosWaystoneAtlas
local WC = ChaosWaystoneAtlasCore
local A = ChaosAtlasCore
local K = ChaosWaystoneTiersCore
local cfg = ChaosWaystoneAtlasConfig
WA.config = cfg
local OPCODE = ChaosOpcodes and ChaosOpcodes.waystoneAtlas or cfg.opcode
local TABLE = (Chaos.tables and Chaos.tables.waystoneAtlas) or cfg.table

WA.state = WA.state or {} -- guid -> {alloc = {[id] = true}, done = {[cell] = true}}
WA.treeSent = WA.treeSent or {} -- player id -> true once the tree went out this login
WA.online = WA.online or {} -- guid -> player id
WA.runs = WA.runs or {} -- map index -> {opener = guid, tier, rare, am, untilAt}

local function TC()
	if ChaosWaystoneTiers and ChaosWaystoneTiers.config then
		return ChaosWaystoneTiers.config
	end
	ChaosWaystoneTiersConfig = ChaosWaystoneTiersConfig or dofile("data/scripts/chaos/waystone_tiers_config.lua")
	return ChaosWaystoneTiersConfig
end
WA.tiersConfig = TC

local function log(text)
	print("[Chaos waystone atlas] " .. text)
end

-- ======================================================================== database
local tableReady = false
local function ensureTable()
	if not tableReady then
		tableReady = db.query("CREATE TABLE IF NOT EXISTS `" .. TABLE .. "` (`player_id` int(11) NOT NULL, " ..
			"`done` text NOT NULL, `nodes` varchar(1024) NOT NULL DEFAULT '', `updated` int(10) unsigned NOT NULL DEFAULT 0, " ..
			"PRIMARY KEY (`player_id`), CONSTRAINT `chaos_waystone_atlas_player_fk` FOREIGN KEY (`player_id`) REFERENCES " ..
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

function WA.get(guid)
	local st = WA.state[guid]
	if not st then
		st = loadRow(guid)
		local clean, changed = WC.sanitize(cfg, TC(), st.alloc, st.done)
		st.alloc = clean
		if changed then
			saveRow(guid, st)
			log(string.format("player %d: allocation adjusted to the current atlas", guid))
		end
		WA.state[guid] = st
	end
	return st
end

local function sendState(player, msg)
	Chaos.send(player, OPCODE, "state", WC.statePayload(cfg, TC(), WA.get(player:getGuid()), msg))
end

-- ======================================================================== runs
-- waystone_tiers.lua WT.startRun: map i opened at tier t from a waystone with these modifiers; mods.opener (the guid of
-- the player whose waystone the device took, waystone_mods.lua WM.take). The opener's atlas shapes the run.
function WA.beginRun(i, t, mods)
	mods = type(mods) == "table" and mods or {}
	local run = {tier = t, opener = tonumber(mods.opener), rare = false,
		untilAt = os.time() + ((ChaosWaystoneMods and ChaosWaystoneMods.config and ChaosWaystoneMods.config.runSeconds) or 1860)}
	local W = ChaosWaystoneModsCore
	if W and W.rarityOf and ChaosWaystoneMods and ChaosWaystoneMods.config then
		local ok, r = pcall(W.rarityOf, ChaosWaystoneMods.config, mods)
		run.rare = ok and r == 3
	end
	if run.opener and cfg.enabled ~= false then
		local ok, st = pcall(WA.get, run.opener)
		if ok and st then
			local bi = WC.bandOfMap(TC(), i)
			run.am = WC.resolve(cfg, st.alloc, {theme = cfg.bandThemes[bi or 0], mods = #mods})
		end
	end
	WA.runs[i] = run
	return run
end

local function liveRun(i)
	local run = i and WA.runs[i]
	if run and run.untilAt <= os.time() then
		WA.runs[i] = nil
		return nil
	end
	return run
end
WA.runOf = liveRun

-- the opener's atlas effects of map i (nil: no atlas run there)
function WA.fxOfMap(i)
	local run = liveRun(i)
	return run and run.am or nil
end

-- the atlas effects of the map a creature (or position) is in
function WA.fxAt(creature)
	if not creature then
		return nil
	end
	local ok, pos = pcall(function() return creature.getPosition and creature:getPosition() or creature end)
	if not ok or not pos then
		return nil
	end
	local i = K.mapAt(TC(), pos)
	return i and WA.fxOfMap(i) or nil
end

-- one stat of the atlas where the creature is (0 when none)
function WA.stat(creature, key)
	local am = WA.fxAt(creature)
	return am and tonumber(am[key]) or 0
end

-- ======================================================================== credit
local function playersInMap(i)
	local m = TC().maps[i]
	if not m then
		return {}
	end
	local cx, cy = math.floor((m.from.x + m.to.x) / 2), math.floor((m.from.y + m.to.y) / 2)
	local hx, hy = math.ceil(math.abs(m.to.x - m.from.x) / 2), math.ceil(math.abs(m.to.y - m.from.y) / 2)
	local ok, specs = pcall(Game.getSpectators, Position(cx, cy, m.from.z), false, true, hx, hx, hy, hy)
	local out = {}
	for _, c in ipairs(ok and specs or {}) do
		if c:isPlayer() then
			out[#out + 1] = c
		end
	end
	return out
end
WA.playersInMap = playersInMap

-- the boss of a waystone map died (waystone_tiers.lua death event): every player inside the map earns the map x tier
-- cell, and the Rare cell of the tier when the run's waystone was Rare. Only a map opened by a waystone counts.
function WA.onBossDeath(e)
	if not e or not e.boss or not tonumber(e.run) or cfg.enabled == false then
		return 0
	end
	local run = liveRun(e.map)
	local keys = WC.runCells(cfg, TC(), {map = e.map, tier = e.run, rare = run and run.rare and run.tier == e.run})
	if #keys == 0 then
		return 0
	end
	local credited = 0
	for _, player in ipairs(playersInMap(e.map)) do
		local guid = player:getGuid()
		local st = WA.get(guid)
		local new, pts = WC.credit(cfg, TC(), st.done, keys)
		if #new > 0 then
			saveRow(guid, st)
			credited = credited + 1
			local names = {}
			for _, c in ipairs(new) do
				names[#names + 1] = WC.cellName(cfg, c)
			end
			player:sendTextMessage(MESSAGE_EVENT_ADVANCE, Chaos.t(player, "Waystone Atlas: %s completed, +%d point%s.",
				table.concat(names, ", "), pts, pts == 1 and "" or "s"))
			Chaos.send(player, OPCODE, "credit", {cells = names, points = pts})
			if WA.treeSent[player:getId()] then
				sendState(player)
			end
		end
	end
	return credited
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
	if not Chaos.pay(player, price.gold) then
		return false, string.format("You need %d gold (carried or in the bank).", price.gold)
	end
	return true
end

local REASONS = {
	unknown = "That node does not exist.", held = "You hold that node already.",
	points = "Not enough atlas points: complete new maps to earn more.",
	keystone = "You can hold only one keystone. Refund the other first.",
	path = "That node is not connected to your atlas.", ["not held"] = "You do not hold that node."
}

local function onAlloc(player, data)
	local st = WA.get(player:getGuid())
	local id = Chaos.toInt(data and data.id, 1, 100000)
	local points = WC.earned(cfg, TC(), st.done) - A.spent(cfg, st.alloc)
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
	local st = WA.get(player:getGuid())
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
	local st = WA.get(player:getGuid())
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

function WA.onOpcode(player, buffer)
	if ChaosRateLimit and not ChaosRateLimit.allow(player, "waystoneatlas", cfg.requestMs) then
		return
	end
	local msg = Chaos.decode(buffer)
	if not msg then
		return
	end
	local data = type(msg.data) == "table" and msg.data or {}
	local ok, err = pcall(function()
		if msg.action == "open" then
			if not WA.treeSent[player:getId()] or data.tree then
				WA.treeSent[player:getId()] = true
				Chaos.sendChunked(player, OPCODE, json.encode({action = "tree", data = WC.treePayload(cfg, TC())}))
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

if CreatureEvent then
	local ext = CreatureEvent("ChaosWaystoneAtlasExtended")
	function ext.onExtendedOpcode(player, opcode, buffer)
		if opcode == OPCODE then
			WA.onOpcode(player, buffer)
		end
	end
	ext:type("extendedopcode")
	ext:register()

	local login = CreatureEvent("ChaosWaystoneAtlasLogin")
	function login.onLogin(player)
		player:registerEvent("ChaosWaystoneAtlasExtended")
		player:registerEvent("ChaosWaystoneAtlasLogout")
		WA.treeSent[player:getId()] = nil
		WA.online[player:getGuid()] = player:getId()
		WA.state[player:getGuid()] = nil
		pcall(WA.get, player:getGuid())
		return true
	end
	login:register()

	local logout = CreatureEvent("ChaosWaystoneAtlasLogout")
	function logout.onLogout(player)
		WA.treeSent[player:getId()] = nil
		WA.online[player:getGuid()] = nil
		WA.state[player:getGuid()] = nil
		return true
	end
	logout:register()
end
