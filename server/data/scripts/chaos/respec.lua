-- respec.lua: what taking passive points back costs (ROADMAP 19). Rules in respec_core.lua, numbers in respec_config.lua.
--   * full reset of the passive tree (resetPreset) and of the Paragon track (paragonReset): the level curve of
--     respec_config.lua (~37.5 minutes of hunting gold at the level), free below level 50
--   * single-node refund (refundNode {id}): a node whose removal keeps every other allocated node connected to the start;
--     ~1.5 minutes of hunting gold, free below level 50
--   * one free full reset after the vocation changed (ascension, class migration). The store's vocation change resets
--     the tree for free itself and the store's Passive Tree Reset service resets tree and Paragon for free; both use
--     ChaosPassiveTree.resetAll, which also uses up a pending free reset
--   * gold: carried gold first, then the bank (Chaos.pay)
-- Build sharing (buildshare.lua) charges the same full reset price when an import takes nodes back.
--
-- Protocol (opcode 65, dispatched through ChaosPassiveTree.extraActions, passivetree.lua):
--   client -> server  respecInfo                -> respecInfo
--                     refundNode {id = n}       -> refund, then sendNodes + sendPoints + respecInfo
--                     resetPreset n, paragonReset (replace the handlers of passivetree.lua / paragon.lua)
--                     requestPoints             -> respecInfo, then the tree's own sendPoints
--   server -> client  {"action":"respecInfo","data":{level, full, paragon, node, free ("level" / "vocation" / nil),
--                      freeBelowLevel}}

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not ChaosRespecConfig then
	dofile("data/scripts/chaos/respec_config.lua")
end
if not ChaosRespecCore then
	dofile("data/scripts/chaos/respec_core.lua")
end

ChaosRespec = ChaosRespec or {}
local R = ChaosRespec
local Core = ChaosRespecCore
local cfg = ChaosRespecConfig
local OPCODE = ChaosOpcodes.passivetree

ChaosPassiveTree = ChaosPassiveTree or {}
ChaosPassiveTree.extraActions = ChaosPassiveTree.extraActions or {}

local function vocationId(player)
	local vocation = player:getVocation()
	return vocation and vocation:getId() or 0
end

function R.freeReason(player)
	return Core.freeReason(player:getLevel(), vocationId(player), player:getStorageValue(cfg.freeVocationStorage))
end

-- full reset price for this player now (0 when free); kind "tree" or "paragon"
function R.fullCost(player, kind)
	if R.freeReason(player) then
		return 0
	end
	return Core.fullCost(player:getLevel(), kind)
end

function R.nodeCost(player)
	return Core.nodeCost(player:getLevel())
end

-- a full reset was done: a pending free reset (vocation change) is used up
function R.useFree(player)
	player:setStorageValue(cfg.freeVocationStorage, vocationId(player))
end

function R.pay(player, cost)
	if cost <= 0 then
		return true
	end
	return Chaos.pay(player, cost) and true or false
end

function R.info(player)
	return {
		level = player:getLevel(), full = R.fullCost(player, "tree"), paragon = R.fullCost(player, "paragon"),
		node = R.nodeCost(player), free = R.freeReason(player), freeBelowLevel = cfg.freeBelowLevel
	}
end

function R.sendInfo(player)
	Chaos.send(player, OPCODE, "respecInfo", R.info(player))
end

function R.freeText(player)
	local reason = R.freeReason(player)
	if reason == "level" then
		return string.format("free below level %d", cfg.freeBelowLevel)
	elseif reason == "vocation" then
		return "free once after your class changed"
	end
	return nil
end

local function box(player, title, text)
	Chaos.send(player, OPCODE, "sendMessage", {title = title, message = text})
end

-- the store's free resets (vocation change, Passive Tree Reset service) use up a pending free reset too
local function wrapResetAll()
	local tree = ChaosPassiveTree
	if tree.resetAll and tree.resetAll ~= R.wrappedResetAll then
		local original = tree.resetAll
		R.wrappedResetAll = function(player, ...)
			local result = original(player, ...)
			R.useFree(player)
			R.sendInfo(player)
			return result
		end
		tree.resetAll = R.wrappedResetAll
	end
end

-- ------------------------------------------------------------------------------------------------ handlers
local actions = ChaosPassiveTree.extraActions

actions.respecInfo = function(player)
	R.sendInfo(player)
	return true
end

actions.requestPoints = function(player)
	R.sendInfo(player)
	return false -- the tree's own handler sends the points
end

actions.resetPreset = function(player, data)
	local T = ChaosPassiveTree.internal
	if not T then
		return false
	end
	local guid = player:getGuid()
	local rows = T.loadPresets(guid)
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
		T.sendMessageBox(player, "Reset", "There is nothing to reset.")
		T.sendPoints(player, rows)
		return true
	end
	local free = R.freeText(player)
	local cost = R.fullCost(player, "tree")
	if not R.pay(player, cost) then
		T.sendMessageBox(player, "Reset", string.format("You need %s gold coins (carried or in the bank) to reset your passive tree.",
			Core.formatGold(cost)))
		return true
	end
	R.useFree(player)
	T.savePreset(guid, preset, target.name, {})
	T.sendNodes(player)
	T.sendPoints(player)
	ChaosPassiveTree.apply(player)
	R.sendInfo(player)
	T.sendMessageBox(player, "Reset", free and ("Your passive tree was reset for free (" .. free .. ").") or
		string.format("Your passive tree was reset for %s gold coins.", Core.formatGold(cost)))
	return true
end

actions.paragonReset = function(player)
	local P = ChaosParagon
	if not (P and P.hasAllocation) then
		return false
	end
	if not P.hasAllocation(player) then
		box(player, "Paragon", "There is nothing to reset.")
		P.sendState(player)
		return true
	end
	local free = R.freeText(player)
	local cost = R.fullCost(player, "paragon")
	if not R.pay(player, cost) then
		box(player, "Paragon", string.format("You need %s gold coins (carried or in the bank) to reset your Paragon points.",
			Core.formatGold(cost)))
		return true
	end
	R.useFree(player)
	P.resetAll(player)
	R.sendInfo(player)
	box(player, "Paragon", free and ("Your Paragon points were reset for free (" .. free .. ").") or
		string.format("Your Paragon points were reset for %s gold coins.", Core.formatGold(cost)))
	return true
end

actions.refundNode = function(player, data)
	local T = ChaosPassiveTree.internal
	if not T then
		return false
	end
	local id = Chaos.toInt(type(data) == "table" and data.id or data, 1)
	local guid = player:getGuid()
	local rows = T.loadPresets(guid)
	local active = rows[1]
	local ok, err = Core.canRemove(T.getTree(), active and active.nodes or {}, id)
	if not ok then
		T.sendMessageBox(player, "Refund", err)
		T.sendNodes(player, rows)
		return true
	end
	local cost = R.nodeCost(player)
	if not R.pay(player, cost) then
		T.sendMessageBox(player, "Refund", string.format("You need %s gold coins (carried or in the bank) to refund a node.",
			Core.formatGold(cost)))
		return true
	end
	local left = {}
	for _, other in ipairs(active.nodes) do
		if other ~= id then
			left[#left + 1] = other
		end
	end
	T.savePreset(guid, active.preset, active.name, left, active.masteries) -- the other masteries keep their effect
	T.sendNodes(player)
	T.sendPoints(player)
	ChaosPassiveTree.apply(player)
	R.sendInfo(player)
	player:sendTextMessage(MESSAGE_EVENT_ADVANCE, cost > 0 and
		string.format("Passive node refunded for %s gold coins. The point is free to spend again.", Core.formatGold(cost)) or
		"Passive node refunded for free. The point is free to spend again.")
	return true
end

-- ------------------------------------------------------------------------------------------------ login
local login = CreatureEvent("ChaosRespecLogin")
function login.onLogin(player)
	wrapResetAll()
	-- first login with respec.lua: remember the vocation (no free reset for what happened before)
	if player:getStorageValue(cfg.freeVocationStorage) < 0 then
		R.useFree(player)
	end
	return true
end
login:register()

wrapResetAll()
