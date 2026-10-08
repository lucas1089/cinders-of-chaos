-- game_passivetree (extended opcode 65)
--
-- Client contract (client/overlay/modules/game_passivetree/passivetree.lua). The client sends
-- through sendExtendedJSONOpcode as {"action":..., "data":...}:
--   client -> server  requestPoints                      -> server sendPoints
--                     requestNodesUnlocked               -> server sendNodes
--                     sendNodes  {nodes:[ids], preset:N} -> saved (no reply on success)
--                     resetPreset N                      -> costs level*250 gold, then sendNodes + sendPoints
--                     refund                             -> resync (sendPoints + sendNodes)
--   server -> client  {"action":"sendPoints","data":<free points number>}
--                     {"action":"sendNodes","data":{"preset":N,"presetsTable":[{"name":".."}],"nodes":[ids],"vocation":"knight"}}
--                     {"action":"sendMessage","data":{"title":"..","message":".."}}
--
-- Tree topology comes from passivetree_data.lua (generated from the client's nodes.lua).
-- The server validates every save: known ids, no duplicates, every node connected to the root
-- (node 1) through other allocated nodes, and #nodes <= points the player owns.
--
-- The node bonuses are applied by passivetree_effects.lua through ChaosPassiveTree.listeners
-- (called after each save, reset and at login with the summed customStats). You can also read
-- ChaosPassiveTree.getBonuses(player) or register per-stat appliers in ChaosPassiveTree.appliers.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end

local OPCODE = ChaosOpcodes.passivetree
local cfg = Chaos.passive
local T = Chaos.tables.passiveTree

ChaosPassiveTree = ChaosPassiveTree or {}
ChaosPassiveTree.appliers = ChaosPassiveTree.appliers or {} -- [statName] = function(player, totalValue)

local treeData -- loaded on first use

local function getTree()
	if not treeData then
		treeData = Chaos.load("passivetree_data.lua")
	end
	return treeData
end

local function sendMessageBox(player, title, message)
	Chaos.send(player, OPCODE, "sendMessage", {title = title, message = message})
end

local function totalPoints(player)
	local byLevel = math.floor(math.max(0, player:getLevel() - cfg.startLevel) / (cfg.levelsPerPoint or 1))
	local extra = player:getStorageValue(Chaos.storage.passiveExtraPoints)
	return byLevel + math.max(0, extra)
end

-- preset rows: {{preset=1,name="..",nodes={ids}}, ...} ordered by preset
local function loadPresets(guid)
	local rows = Chaos.select(
		"SELECT `preset`, `name`, `nodes` FROM `" .. T .. "` WHERE `player_id` = " .. guid .. " ORDER BY `preset`",
		{{"preset", "n"}, {"name", "s"}, {"nodes", "s"}}
	)
	for _, row in ipairs(rows) do
		local ids = {}
		for token in (row.nodes or ""):gmatch("%d+") do
			ids[#ids + 1] = tonumber(token)
		end
		row.nodes = ids
	end
	return rows
end

local function savePreset(guid, preset, name, ids)
	table.sort(ids)
	db.query(
		"INSERT INTO `" .. T .. "` (`player_id`, `preset`, `name`, `nodes`) VALUES (" .. guid .. ", " .. preset .. ", " ..
			db.escapeString(name) .. ", " .. db.escapeString(table.concat(ids, ",")) ..
			") ON DUPLICATE KEY UPDATE `nodes` = VALUES(`nodes`)"
	)
end

local function activePreset(rows)
	return rows[1]
end

local function freePoints(player, rows)
	local active = activePreset(rows)
	local spent = active and #active.nodes or 0
	return math.max(0, totalPoints(player) - spent)
end

local function sendPoints(player, rows)
	rows = rows or loadPresets(player:getGuid())
	Chaos.send(player, OPCODE, "sendPoints", freePoints(player, rows))
end

local function sendNodes(player, rows)
	rows = rows or loadPresets(player:getGuid())
	local presetsTable = {}
	for i, row in ipairs(rows) do
		presetsTable[i] = {name = row.name}
	end
	local active = activePreset(rows)
	Chaos.send(player, OPCODE, "sendNodes", {
		preset = active and active.preset or 0,
		presetsTable = presetsTable,
		nodes = active and active.nodes or {},
		-- which per-vocation node variants (keystones) the client must show: the ones the server applies
		vocation = ChaosPassiveTree.vocationKey and ChaosPassiveTree.vocationKey(player) or nil
	})
end

-- Returns cleaned id list or nil, errorText
local function validateNodes(player, rawNodes)
	local tree = getTree()
	if type(rawNodes) ~= "table" then
		return nil, "Malformed request."
	end
	local seen, ids = {}, {}
	for _, raw in ipairs(rawNodes) do
		local id = Chaos.toInt(raw, 1)
		if not id or not tree.nodes[id] then
			return nil, "Unknown node in request."
		end
		if id ~= tree.root and not seen[id] then
			seen[id] = true
			ids[#ids + 1] = id
		end
	end

	if #ids > totalPoints(player) then
		return nil, "You do not own enough passive points for that allocation."
	end

	-- connectivity: BFS from the root, only stepping onto allocated nodes
	local reached, queue, head, count = {[tree.root] = true}, {tree.root}, 1, 0
	while head <= #queue do
		local current = queue[head]
		head = head + 1
		for _, neighbour in ipairs(tree.nodes[current].n) do
			if seen[neighbour] and not reached[neighbour] then
				reached[neighbour] = true
				count = count + 1
				queue[#queue + 1] = neighbour
			end
		end
	end
	if count ~= #ids then
		return nil, "Every allocated node must be connected to the starting node."
	end
	return ids
end

-- vocation key of the per-vocation node variants (keystones), by the client's vocation id like the client module
local VOCATION_KEY = {[1] = "knight", [2] = "paladin", [3] = "sorcerer", [4] = "druid", [5] = "illusionist", [6] = "monk"}
function ChaosPassiveTree.vocationKey(player)
	local vocation = player:getVocation()
	return vocation and VOCATION_KEY[vocation:getClientId()] or nil
end

-- stats a node gives this vocation: its own variant (node.v) if it has one, else the shared stats
function ChaosPassiveTree.nodeStats(node, vocationKey)
	return (node.v and vocationKey and node.v[vocationKey]) or node.s
end

function ChaosPassiveTree.getBonuses(player)
	local tree = getTree()
	local rows = loadPresets(player:getGuid())
	local active = activePreset(rows)
	local bonuses = {}
	local vocationKey = ChaosPassiveTree.vocationKey(player)
	if active then
		for _, id in ipairs(active.nodes) do
			local node = tree.nodes[id]
			local stats = node and ChaosPassiveTree.nodeStats(node, vocationKey)
			if stats then
				for stat, value in pairs(stats) do
					bonuses[stat] = (bonuses[stat] or 0) + value
				end
			end
		end
	end
	return bonuses
end

-- last computed bonuses per player id (read by passivetree_effects.lua during combat)
ChaosPassiveCache = ChaosPassiveCache or {}
-- listeners[i] = function(player, bonuses) : called once after every apply (login, save, reset)
ChaosPassiveTree.listeners = ChaosPassiveTree.listeners or {}

local function applyBonuses(player)
	local bonuses = ChaosPassiveTree.getBonuses(player)
	ChaosPassiveCache[player:getId()] = bonuses
	for stat, applier in pairs(ChaosPassiveTree.appliers) do
		applier(player, bonuses[stat] or 0)
	end
	for _, listener in ipairs(ChaosPassiveTree.listeners) do
		listener(player, bonuses)
	end
end
ChaosPassiveTree.apply = applyBonuses

local function handleSave(player, data)
	if type(data) ~= "table" then
		return
	end
	local guid = player:getGuid()
	local ids, err = validateNodes(player, data.nodes)
	if not ids then
		sendMessageBox(player, "Error saving passive tree", err)
		sendNodes(player)
		sendPoints(player)
		return
	end

	local rows = loadPresets(guid)
	local preset = Chaos.toInt(data.preset, 0) or 0
	-- Only one preset slot exists in the client UI: 0 (never saved) and 1 both mean slot 1.
	if preset < 1 or preset > cfg.maxPresets then
		preset = 1
	end
	local name = "Preset " .. preset
	for _, row in ipairs(rows) do
		if row.preset == preset then
			name = row.name
		end
	end
	savePreset(guid, preset, name, ids)
	sendPoints(player)
	applyBonuses(player)
end

local function handleReset(player, data)
	local guid = player:getGuid()
	local rows = loadPresets(guid)
	local preset = Chaos.toInt(data, 0) or 0
	if preset < 1 then
		preset = rows[1] and rows[1].preset or 1
	end
	local target
	for _, row in ipairs(rows) do
		if row.preset == preset then
			target = row
		end
	end
	if not target or #target.nodes == 0 then
		sendMessageBox(player, "Reset", "There is nothing to reset.")
		sendPoints(player, rows)
		return
	end

	local cost = player:getLevel() * cfg.resetCostPerLevel
	if not player:removeMoney(cost) then
		sendMessageBox(player, "Reset", string.format("You need %d gold coins to reset your passive tree.", cost))
		return
	end
	savePreset(guid, preset, target.name, {})
	sendNodes(player)
	sendPoints(player)
	applyBonuses(player)
	sendMessageBox(player, "Reset", string.format("Your passive tree was reset for %d gold coins.", cost))
end

-- store services (shop_services.lua): free reset of every preset (respec offer, vocation change)
function ChaosPassiveTree.hasAllocation(player)
	for _, row in ipairs(loadPresets(player:getGuid())) do
		if #row.nodes > 0 then
			return true
		end
	end
	return false
end

function ChaosPassiveTree.resetAll(player)
	db.query("UPDATE `" .. T .. "` SET `nodes` = '' WHERE `player_id` = " .. player:getGuid())
	sendNodes(player)
	sendPoints(player)
	applyBonuses(player)
end

local LoginEvent = CreatureEvent("ChaosPassiveTreeLogin")

-- presets that hold more nodes than the character owns points (the point rate went down, or the level dropped)
-- are emptied for free, so no allocation is ever larger than the points behind it
local function refundOverBudget(player)
	local total = totalPoints(player)
	local refunded = 0
	for _, row in ipairs(loadPresets(player:getGuid())) do
		if #row.nodes > total then
			db.query("UPDATE `" .. T .. "` SET `nodes` = '' WHERE `player_id` = " .. player:getGuid() .. " AND `preset` = " .. row.preset)
			refunded = refunded + 1
		end
	end
	if refunded > 0 then
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, string.format(
			"Your passive tree was refunded for free: it held more nodes than your %d passive points. Please allocate them again.", total))
	end
end

function LoginEvent.onLogin(player)
	player:registerEvent("ChaosPassiveTreeExtended")
	refundOverBudget(player)
	applyBonuses(player)
	return true
end

local ExtendedEvent = CreatureEvent("ChaosPassiveTreeExtended")

function ExtendedEvent.onExtendedOpcode(player, opcode, buffer)
	if opcode ~= OPCODE then
		return
	end
	local msg = Chaos.decode(buffer)
	if not msg then
		return
	end

	local action = msg.action
	if action == "requestPoints" then
		sendPoints(player)
	elseif action == "requestNodesUnlocked" then
		sendNodes(player)
	elseif action == "sendNodes" then
		handleSave(player, msg.data)
	elseif action == "resetPreset" then
		handleReset(player, msg.data)
	elseif action == "refund" then
		sendNodes(player)
		sendPoints(player)
	end
end

LoginEvent:type("login")
LoginEvent:register()
ExtendedEvent:type("extendedopcode")
ExtendedEvent:register()
