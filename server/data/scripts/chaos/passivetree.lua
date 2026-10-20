-- game_passivetree (extended opcode 65)
--
-- Client contract (client/overlay/modules/game_passivetree/passivetree.lua). The client sends
-- through sendExtendedJSONOpcode as {"action":..., "data":...}:
--   client -> server  requestPoints                      -> server sendPoints
--                     requestNodesUnlocked               -> server sendNodes
--                     sendNodes  {nodes:[ids], preset:N} -> saved (no reply on success)
--                     resetPreset N                      -> priced by respec.lua (respec_config.lua), then sendNodes + sendPoints
--                     respec.lua / buildshare.lua add refundNode, respecInfo, buildExport, buildPreview, buildApply
--                     refund                             -> resync (sendPoints + sendNodes)
--   server -> client  {"action":"sendPoints","data":<free points number>}
--                     {"action":"bossPoints","data":{got, total, label, bosses}} after every sendPoints (bosspoints.lua)
--                     {"action":"sendNodes","data":{"preset":N,"presetsTable":[{"name":".."}],"nodes":[ids],"vocation":"knight"}}
--                     {"action":"sendMessage","data":{"title":"..","message":".."}}
--   Planner and mastery nodes (rules in passivetree_core.lua, numbers in passivetree_config.lua), same opcode:
--   client -> server  planApply {nodes:[ids to add], masteries:[{id, choice}]}  -> the whole plan checked like a save
--                                                       (validatePlan) and saved at once, or nothing; then planResult
--                     masteryChoose {id, choice}         -> the effect of a saved mastery changes for the single-node
--                                                       refund price (respec.lua); then planResult
--   server -> client  {"action":"planResult","data":{"ok":bool,"message":".."}} (sendNodes + sendPoints after a change)
--                     sendNodes also carries "masteries":[{"id":n,"choice":c}] (the active preset's chosen effects)
--   Paragon track (paragon.lua, ChaosParagon.actions), same opcode:
--   client -> server  paragonRequest                     -> server paragonState
--                     paragonApply {alloc:{stat:n}}      -> absolute allocation, validated; saved, applied, paragonState
--                     paragonReset                       -> costs level*250 gold, then paragonState
--   server -> client  {"action":"paragonState","data":{unlocked, level, startLevel, total, spent, free, resetCost, categories}}
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
if not Chaos.t then
	dofile("data/scripts/chaos/i18n_core.lua")
end
if not ChaosPassiveTreeConfig then
	dofile("data/scripts/chaos/passivetree_config.lua")
end
if not ChaosPassiveTreeCore then
	dofile("data/scripts/chaos/passivetree_core.lua")
end
local Core = ChaosPassiveTreeCore
local planCfg = ChaosPassiveTreeConfig

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
	-- +1 per major boss killed once (bosspoints.lua): kept through every reset, refund and build code
	local bosses = ChaosBossPoints and ChaosBossPoints.count and ChaosBossPoints.count(player) or 0
	return byLevel + math.max(0, extra) + bosses
end

-- preset rows: {{preset=1,name="..",nodes={ids},masteries={[id]=choice}}, ...} ordered by preset
-- (the nodes text is "ids" or "ids|id:choice,..." : passivetree_core.lua parseAlloc)
local function loadPresets(guid)
	local rows = Chaos.select(
		"SELECT `preset`, `name`, `nodes` FROM `" .. T .. "` WHERE `player_id` = " .. guid .. " ORDER BY `preset`",
		{{"preset", "n"}, {"name", "s"}, {"nodes", "s"}}
	)
	for _, row in ipairs(rows) do
		row.nodes, row.masteries = Core.parseAlloc(row.nodes)
	end
	return rows
end

-- masteries: the chosen effects to keep ({[id] = choice}); only those of nodes in ids are written. Callers that do not
-- pass them drop every choice (a reset); a refund or a re-save passes the row's own (row.masteries).
local function savePreset(guid, preset, name, ids, masteries)
	table.sort(ids)
	db.query(
		"INSERT INTO `" .. T .. "` (`player_id`, `preset`, `name`, `nodes`) VALUES (" .. guid .. ", " .. preset .. ", " ..
			db.escapeString(name) .. ", " .. db.escapeString(Core.formatAlloc(ids, masteries)) ..
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
	if ChaosBossPoints and ChaosBossPoints.sendInfo then
		ChaosBossPoints.sendInfo(player) -- "Boss points n/10" under the points box
	end
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
		-- the chosen effect of each allocated mastery node
		masteries = Core.toList(active and Core.cleanMasteries(getTree(), active.nodes, active.masteries) or {}),
		-- which per-class node variants (keystones) the client must show: the ones the server applies
		vocation = ChaosPassiveTree.vocationKey and ChaosPassiveTree.vocationKey(player) or nil,
		-- the class (which class nodes it may take) and its line (whose class section the client shows)
		cls = ChaosPassiveTree.classKey(player),
		line = ChaosPassiveTree.lineKey(player)
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
		if not ChaosClassTree.allowed(tree.nodes[id], ChaosPassiveTree.classKey(player)) then
			return nil, "That node belongs to another class."
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

-- key of the per-class node variants (keystones 621 / 624): ChaosClasses.keystoneKey (classes.lua): Warrior "knight",
-- Juggernaut "juggernaut", Berserker "berserker", Ranger "paladin", Deadeye "deadeye", Beastmaster "beastmaster",
-- Mystic / Elementalist "sorcerer", Illusionist "illusionist"; the other lines their class key (a variant only for the
-- Iron Sage, "ironsage" Overgrowth on 621, and the Sentinel, "sentinel" Thorns on 624).
-- The class sections and the restricted nodes use the class key (class_tree.lua).
if not ChaosClasses then
	dofile("data/scripts/chaos/classes.lua")
end
if not ChaosClassTree then
	dofile("data/scripts/chaos/class_tree.lua")
end
function ChaosPassiveTree.vocationKey(player)
	local vocation = player:getVocation()
	return vocation and ChaosClasses.keystoneKey(vocation:getId()) or nil
end

function ChaosPassiveTree.classKey(player)
	local vocation = player:getVocation()
	return vocation and ChaosClasses.classKey(vocation:getId()) or nil
end

function ChaosPassiveTree.lineKey(player)
	local vocation = player:getVocation()
	return vocation and ChaosClasses.lineKey(vocation:getId()) or nil
end

-- stats a node gives this vocation: its own variant (node.v) if it has one, else the shared stats; a mastery node the
-- chosen effect (choice; nothing without one)
function ChaosPassiveTree.nodeStats(node, vocationKey, choice)
	return Core.nodeStats(node, vocationKey, choice)
end

function ChaosPassiveTree.getBonuses(player)
	local tree = getTree()
	local rows = loadPresets(player:getGuid())
	local active = activePreset(rows)
	local bonuses = {}
	local vocationKey = ChaosPassiveTree.vocationKey(player)
	local classKey = ChaosPassiveTree.classKey(player)
	if active then
		for _, id in ipairs(active.nodes) do
			local node = tree.nodes[id]
			-- a node of another class (a vocation change before the next login check) gives nothing
			local stats = node and ChaosClassTree.allowed(node, classKey) and
				ChaosPassiveTree.nodeStats(node, vocationKey, active.masteries and active.masteries[id])
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
	-- the Paragon track's percentages go into the same table (keys paragonX), so every effect sums tree + Paragon
	if ChaosParagon and ChaosParagon.addBonuses then
		ChaosParagon.addBonuses(player, bonuses)
	end
	-- the held Vocation Trial nodes (trials.lua): not passive points, kept through the tree's resets
	if ChaosTrials and ChaosTrials.addBonuses then
		ChaosTrials.addBonuses(player, bonuses)
	end
	ChaosPassiveCache[player:getId()] = bonuses
	-- the class nodes' flags, for the class scripts and the spells (another Lua state): one storage
	ChaosClassTree.write(player, bonuses)
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
	local tree = getTree()
	-- Only one preset slot exists in the client UI: a save always goes to the active preset (activePreset: the lowest
	-- saved one; slot 1 when none) and is checked against it. data.preset is ignored: saving a fresh set into another
	-- slot number that then becomes the active one would be a free respec.
	local active = activePreset(rows)
	local preset = active and active.preset or 1
	local name = active and active.name or ("Preset " .. preset)
	local saved = active and active.nodes or nil
	-- allocations only go up: taking a node back is a priced reset or refund (respec.lua), never a plain save
	if saved and #saved > 0 then
		local kept = {}
		for _, id in ipairs(ids) do
			kept[id] = true
		end
		for _, id in ipairs(saved) do
			if not kept[id] then
				sendMessageBox(player, "Error saving passive tree",
					"Saved nodes cannot be removed by saving. Use a refund (right-click a node) or a reset.")
				sendNodes(player)
				sendPoints(player)
				return
			end
		end
	end
	-- mastery nodes: the saved choices stay; a newly added mastery needs its effect in data.masteries (planApply is the
	-- client's way; this plain save keeps working for the rest)
	local savedSet = {}
	for _, id in ipairs(saved or {}) do
		savedSet[id] = true
	end
	local choices = Core.toMap(data.masteries) or {}
	local masteries = Core.cleanMasteries(tree, saved or {}, active and active.masteries)
	for _, id in ipairs(ids) do
		if not savedSet[id] and Core.isMastery(tree.nodes[id]) then
			if not Core.validChoice(tree.nodes[id], choices[id]) then
				sendMessageBox(player, "Error saving passive tree", "Choose an effect for every new mastery node.")
				sendNodes(player)
				sendPoints(player)
				return
			end
			masteries[id] = choices[id]
		end
	end
	savePreset(guid, preset, name, ids, masteries)
	sendPoints(player)
	applyBonuses(player)
end

local function planResult(player, ok, message)
	Chaos.send(player, OPCODE, "planResult", {ok = ok == true, message = message})
end

-- the whole plan in one request: checked fully (validatePlan: the same rules as a save), saved at once or not at all
local function handlePlanApply(player, data)
	local guid = player:getGuid()
	local rows = loadPresets(guid)
	local active = activePreset(rows)
	local tree = getTree()
	-- nodes already held are not an error: the client's view was behind (a refund, a reply still on its way). They are
	-- left out of the plan; a plan of nothing else answers with the saved tree so the client catches up.
	local plan, dropped = Core.dropOwned(active and active.nodes or {}, type(data) == "table" and data or nil)
	if dropped > 0 and type(plan.nodes) == "table" and #plan.nodes == 0 then
		planResult(player, false, "You already have those nodes. Your tree was refreshed.")
		sendNodes(player, rows)
		sendPoints(player, rows)
		return
	end
	local result, err = Core.validatePlan(tree, active and active.nodes or {}, active and active.masteries or {},
		plan, {
			classKey = ChaosPassiveTree.classKey(player), allowed = ChaosClassTree.allowed, points = totalPoints(player),
			maxNodes = planCfg.maxPlanNodes
		})
	if result then
		-- and the plain save's own check once more on the final list (known ids, class, connected, points)
		local ids, invalid = validateNodes(player, result.ids)
		if not ids then
			result, err = nil, invalid
		end
	end
	if not result then
		planResult(player, false, err)
		sendNodes(player, rows)
		sendPoints(player, rows)
		return
	end
	local preset = active and active.preset or 1
	savePreset(guid, preset, active and active.name or ("Preset " .. preset), result.ids, result.masteries)
	sendNodes(player)
	sendPoints(player)
	applyBonuses(player)
	planResult(player, true, string.format("%d node%s allocated.", #result.added, #result.added == 1 and "" or "s"))
end

-- a saved mastery takes another effect: the single-node refund price (respec.lua), the same free cases
local function handleMasteryChoose(player, data)
	if type(data) ~= "table" then
		return
	end
	local guid = player:getGuid()
	local rows = loadPresets(guid)
	local active = activePreset(rows)
	local tree = getTree()
	local id, choice = Chaos.toInt(data.id, 1), Chaos.toInt(data.choice, 1)
	local ok, err = Core.checkMasteryChange(tree, active and active.nodes or {}, active and active.masteries or {}, id, choice)
	if not ok then
		planResult(player, false, err)
		sendNodes(player, rows)
		return
	end
	local R = ChaosRespec
	local cost = (planCfg.masteryChangeUsesNodePrice and R and R.nodeCost) and R.nodeCost(player) or 0
	if cost > 0 and not R.pay(player, cost) then
		planResult(player, false, string.format("You need %s gold coins (carried or in the bank) to change the effect.",
			ChaosRespecCore and ChaosRespecCore.formatGold(cost) or tostring(cost)))
		return
	end
	local masteries = Core.cleanMasteries(tree, active.nodes, active.masteries)
	masteries[id] = choice
	savePreset(guid, active.preset, active.name, active.nodes, masteries)
	sendNodes(player)
	sendPoints(player)
	applyBonuses(player)
	if R and R.sendInfo then
		R.sendInfo(player)
	end
	planResult(player, true, cost > 0 and string.format("Mastery effect changed for %s gold coins.",
		ChaosRespecCore and ChaosRespecCore.formatGold(cost) or tostring(cost)) or "Mastery effect changed (free).")
end

-- Inspect Player (inspect.lua): the public view of a character's active tree
function ChaosPassiveTree.publicView(player)
	local active = activePreset(loadPresets(player:getGuid()))
	local nodes = active and active.nodes or {}
	return {
		nodes = nodes, masteries = Core.toList(Core.cleanMasteries(getTree(), nodes, active and active.masteries)),
		cls = ChaosPassiveTree.classKey(player), line = ChaosPassiveTree.lineKey(player),
		vocation = ChaosPassiveTree.vocationKey(player), total = totalPoints(player)
	}
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

-- respec.lua / buildshare.lua (single-node refund, priced full reset, build codes) use these, and add their opcode
-- actions to ChaosPassiveTree.extraActions (checked first; a handler that returns true has handled the message)
ChaosPassiveTree.internal = {getTree = getTree, loadPresets = loadPresets, savePreset = savePreset, sendNodes = sendNodes,
	sendPoints = sendPoints, sendMessageBox = sendMessageBox, totalPoints = totalPoints, validateNodes = validateNodes,
	core = Core}
ChaosPassiveTree.extraActions = ChaosPassiveTree.extraActions or {}

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
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, Chaos.t(player,
			"Your passive tree was refunded for free: it held more nodes than your %d passive points. Please allocate them again.", total))
	end
end

-- presets that hold nodes the class may not hold (another class's section after a class change, the keystones 621 /
-- 624 for a class without a variant there) or nodes the tree no longer has: those nodes, and the ones that only
-- connected through them, are refunded for free and the player is told how many (never a silent wipe)
local function refundForeignNodes(player)
	local tree = getTree()
	local classKey = ChaosPassiveTree.classKey(player)
	local total = 0
	for _, row in ipairs(loadPresets(player:getGuid())) do
		local kept, removed = ChaosClassTree.sanitize(tree, row.nodes, classKey)
		if #removed > 0 then
			savePreset(player:getGuid(), row.preset, row.name, kept, row.masteries)
			total = total + #removed
		end
	end
	if total > 0 then
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, Chaos.t(player, total == 1 and
			"Your passive tree: %d node your class cannot hold (or that left the tree) was refunded for free." or
			"Your passive tree: %d nodes your class cannot hold (or that left the tree) were refunded for free.", total))
	end
	return total
end
ChaosPassiveTree.refundForeignNodes = refundForeignNodes

-- nodes whose meaning changed a lot (passivetree_config.lua `reworked`): once per version, every preset and saved
-- loadout of the character loses them (and the nodes only connected through them), for free, with a message.
-- Chaos.storage.passiveRework keeps the last version handled (a new character simply records it).
local function refundReworked(player)
	local key = Chaos.storage.passiveRework
	local list = planCfg.reworked
	if not key or type(list) ~= "table" or #list == 0 then
		return 0
	end
	local seen = player:getStorageValue(key)
	local drop, newest, any = Core.reworkedSince(list, seen, getTree(), ChaosPassiveTree.vocationKey(player))
	if newest == seen then
		return 0
	end
	local total, inLoadouts = 0, 0
	if any then
		local tree = getTree()
		for _, row in ipairs(loadPresets(player:getGuid())) do
			local kept, removed = Core.dropNodes(tree, row.nodes, drop)
			if #removed > 0 then
				savePreset(player:getGuid(), row.preset, row.name, kept, row.masteries)
				total = total + #removed
			end
		end
		if ChaosLoadouts and ChaosLoadouts.dropNodes then
			local ok, n = pcall(ChaosLoadouts.dropNodes, player, drop)
			if ok then
				inLoadouts = tonumber(n) or 0
			else
				print("[ChaosPassiveTree] reworked nodes in loadouts: " .. tostring(n))
			end
		end
	end
	player:setStorageValue(key, newest)
	if total + inLoadouts > 0 then
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, Chaos.t(player, total == 1 and
			"Your passive tree: %d node whose effect changed or that left the tree was refunded for free%s." or
			"Your passive tree: %d nodes whose effect changed or that left the tree were refunded for free%s.", total,
			inLoadouts > 0 and Chaos.t(player, "; your saved loadouts lost %d", inLoadouts) or ""))
	end
	return total
end
ChaosPassiveTree.refundReworked = refundReworked

function LoginEvent.onLogin(player)
	player:registerEvent("ChaosPassiveTreeExtended")
	refundReworked(player)
	refundForeignNodes(player)
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
	if type(action) ~= "string" then
		return
	end
	-- nearly every request loads the presets from the database, the extra actions too (respec.lua resetPreset and
	-- refundNode, buildshare.lua buildExport), which run before the limits below: per action (ratelimit.lua), so
	-- opening the window (requestPoints + requestNodesUnlocked) passes; planApply keeps its own "Too fast" answer
	if action ~= "planApply" and ChaosRateLimit
		and not ChaosRateLimit.allow(player, "passivetree.req." .. action, action == "resetPreset" and 1000 or 200) then
		return
	end
	local extra = ChaosPassiveTree.extraActions[action]
	if extra and extra(player, msg.data) then
		return
	end
	if action == "requestPoints" then
		sendPoints(player)
	elseif action == "requestNodesUnlocked" then
		sendNodes(player)
	elseif action == "sendNodes" then
		-- a SELECT, a graph walk, an INSERT and every bonus re-applied: at most once a second (ratelimit.lua)
		if ChaosRateLimit and not ChaosRateLimit.allow(player, "passivetree.save", 1000) then
			return
		end
		handleSave(player, msg.data)
	elseif action == "planApply" then
		if ChaosRateLimit and not ChaosRateLimit.allow(player, "passivetree.save", planCfg.rateMs or 1000) then
			planResult(player, false, "Too fast: wait a moment and apply again.")
			return
		end
		handlePlanApply(player, msg.data)
	elseif action == "masteryChoose" then
		if ChaosRateLimit and not ChaosRateLimit.allow(player, "passivetree.mastery", planCfg.rateMs or 1000) then
			return
		end
		handleMasteryChoose(player, msg.data)
	elseif action == "resetPreset" then
		if ChaosRateLimit and not ChaosRateLimit.allow(player, "passivetree.reset", 1000) then
			return
		end
		handleReset(player, msg.data)
	elseif action == "refund" then
		sendNodes(player)
		sendPoints(player)
	elseif ChaosParagon and ChaosParagon.actions and ChaosParagon.actions[action] then
		ChaosParagon.actions[action](player, msg.data)
	end
end

LoginEvent:type("login")
LoginEvent:register()
ExtendedEvent:type("extendedopcode")
ExtendedEvent:register()
