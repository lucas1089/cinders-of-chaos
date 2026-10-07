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
--                     {"action":"sendNodes","data":{"preset":N,"presetsTable":[{"name":".."}],"nodes":[ids]}}
--                     {"action":"sendMessage","data":{"title":"..","message":".."}}
--
-- Tree topology comes from passivetree_data.lua (generated from the client's nodes.lua).
-- The server validates every save: known ids, no duplicates, every node connected to the root
-- (node 1) through other allocated nodes, and #nodes <= points the player owns.
--
-- NOT implemented: applying the node bonuses to combat/stats. ChaosPassiveTree.getBonuses(player)
-- returns the summed customStats (e.g. {strength=3, incrementFire=10}); wire those into your
-- damage/absorb/skill code, or register appliers in ChaosPassiveTree.appliers (called after
-- each save and at login). See README.

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
	local byLevel = math.max(0, player:getLevel() - cfg.startLevel) * cfg.pointsPerLevel
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
		nodes = active and active.nodes or {}
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

function ChaosPassiveTree.getBonuses(player)
	local tree = getTree()
	local rows = loadPresets(player:getGuid())
	local active = activePreset(rows)
	local bonuses = {}
	if active then
		for _, id in ipairs(active.nodes) do
			local node = tree.nodes[id]
			if node and node.s then
				for stat, value in pairs(node.s) do
					bonuses[stat] = (bonuses[stat] or 0) + value
				end
			end
		end
	end
	return bonuses
end

local function applyBonuses(player)
	if next(ChaosPassiveTree.appliers) == nil then
		return
	end
	local bonuses = ChaosPassiveTree.getBonuses(player)
	for stat, applier in pairs(ChaosPassiveTree.appliers) do
		applier(player, bonuses[stat] or 0)
	end
end

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

local LoginEvent = CreatureEvent("ChaosPassiveTreeLogin")

function LoginEvent.onLogin(player)
	player:registerEvent("ChaosPassiveTreeExtended")
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
