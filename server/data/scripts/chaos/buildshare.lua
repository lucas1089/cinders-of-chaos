-- buildshare.lua: export / import a passive tree build as a short code (ROADMAP 18). Format and import rules in
-- buildshare_core.lua; the server decides everything, the client only shows what it gets.
--
-- Import rules (also in server/README.md "Build sharing"):
--   * same class line (base class: Warrior, Ranger, Mystic, Thief lines); keystone variants follow the importer's class
--   * every node known, connected to the start through the build's own nodes, keystones only if the class has them
--   * more nodes than the character owns points: the first N nodes in path order are applied (nodes it already has
--     first), the rest is listed in the preview as left out
--   * the build only adds to the current tree: free. It takes nodes (or Paragon points) back: the full reset price of
--     respec.lua for that part (tree / Paragon), the same as the Reset buttons, including the free cases
--   * the Paragon part is applied when the code has one and the track is unlocked
--
-- Protocol (opcode 65, through ChaosPassiveTree.extraActions in passivetree.lua):
--   client -> server  buildExport                  -> buildCode {code, nodes, paragon}
--                     buildPreview {code}          -> buildPreview {code, nodes, current, wanted, applied, skipped, added,
--                                                     removed, treeReset, paragon, paragonChange, paragonReset, cost,
--                                                     free, points, notes, change} or buildError {message}
--                     buildApply {code, cost}      -> applied (sendNodes, sendPoints, paragonState, respecInfo) and
--                                                     buildApplied {message}, or buildError {message}; cost is the price
--                                                     the preview showed: a higher price now is refused
-- Chat: !build export | !build import <code> (preview) | !build confirm | !build cancel

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not ChaosBuildShare then
	dofile("data/scripts/chaos/buildshare_core.lua")
end

local B = ChaosBuildShare
local OPCODE = ChaosOpcodes.passivetree
local PENDING_SECONDS = 300

ChaosPassiveTree = ChaosPassiveTree or {}
ChaosPassiveTree.extraActions = ChaosPassiveTree.extraActions or {}

B.pending = B.pending or {} -- player id -> {code, cost, time} of a chat preview

local function className(index)
	local name = B.lineName(index)
	return name and (name .. " line class") or "character without a class"
end

-- the code's class byte: the player's class line (base class of Chaos.classes, e.g. Juggernaut -> "warrior")
local function classOf(player)
	local vocation = player:getVocation()
	local base = vocation and ChaosClasses and ChaosClasses.baseOf and ChaosClasses.baseOf(vocation:getId())
	for name, id in pairs((Chaos.classes and Chaos.classes.ids) or {}) do
		if id == base then
			return B.lineIndex(name)
		end
	end
	return 0
end

local function activeRow(T, player)
	return T.loadPresets(player:getGuid())[1]
end

local function context(T, player)
	local active = activeRow(T, player)
	local ctx = {
		classId = classOf(player), className = className, current = active and active.nodes or {},
		points = T.totalPoints(player),
		keystoneKey = ChaosPassiveTree.vocationKey and ChaosPassiveTree.vocationKey(player) or nil
	}
	local P = ChaosParagon
	if P and P.defs then
		local max = {}
		for key, def in pairs(P.defs) do
			max[key] = def.maxPoints
		end
		local current = {}
		for key, n in pairs(P.allocation(player)) do
			current[key] = n
		end
		ctx.paragon = {unlocked = P.unlocked(player:getLevel()), total = P.totalPoints(player:getLevel()), current = current,
			max = max}
	end
	return ctx
end

function B.exportCode(player)
	local T = ChaosPassiveTree.internal
	local active = activeRow(T, player)
	local build = {classId = classOf(player), nodes = active and active.nodes or {}}
	if ChaosParagon and ChaosParagon.allocation then
		local alloc = ChaosParagon.allocation(player)
		if ChaosParagon.spent(alloc) > 0 then
			build.paragon = alloc
		end
	end
	return B.encode(build), build
end

-- preview data, or nil + error text
function B.preview(player, code)
	local T = ChaosPassiveTree.internal
	local build, err = B.decode(B.extract(code) or code)
	if not build then
		return nil, err
	end
	local ctx = context(T, player)
	local plan
	plan, err = B.plan(T.getTree(), build, ctx)
	if not plan then
		return nil, err
	end
	local R = ChaosRespec
	local cost = 0
	if plan.treeReset then
		cost = cost + (R and R.fullCost(player, "tree") or player:getLevel() * Chaos.passive.resetCostPerLevel)
	end
	if plan.paragonReset then
		cost = cost + (R and R.fullCost(player, "paragon") or player:getLevel() * Chaos.passive.resetCostPerLevel)
	end
	return {
		code = B.encode(build), nodes = plan.nodes, current = ctx.current, wanted = plan.wanted, applied = plan.applied,
		skipped = plan.skipped, added = plan.added, removed = plan.removed, treeReset = plan.treeReset,
		paragon = plan.paragon, paragonChange = plan.paragonChange or false, paragonReset = plan.paragonReset or false,
		cost = cost, free = (plan.treeReset or plan.paragonReset) and R and R.freeText(player) or nil, points = ctx.points,
		notes = plan.notes, change = plan.treeChange or plan.paragonChange or false,
		className = className(build.classId)
	}, nil, plan
end

local function summary(p)
	local lines = {string.format("Build for a %s: %d nodes, %d applied (%d new, %d taken back).", p.className, p.wanted,
		p.applied, p.added, p.removed)}
	if p.paragon and p.paragonChange then
		lines[#lines + 1] = "The Paragon allocation changes too."
	end
	for _, note in ipairs(p.notes) do
		lines[#lines + 1] = note
	end
	if not p.change then
		lines[#lines + 1] = "You already have this build: nothing would change."
	elseif p.cost > 0 then
		lines[#lines + 1] = string.format("It takes points back, so it costs the full reset price: %s gold coins.",
			ChaosRespecCore and ChaosRespecCore.formatGold(p.cost) or tostring(p.cost))
	elseif p.free then
		lines[#lines + 1] = "It takes points back; the reset is free (" .. p.free .. ")."
	else
		lines[#lines + 1] = "It only adds nodes: free."
	end
	return table.concat(lines, "\n")
end
B.summary = summary

-- apply; returns true, message or nil, error
function B.apply(player, code, seenCost)
	local T = ChaosPassiveTree.internal
	local p, err, plan = B.preview(player, code)
	if not p then
		return nil, err
	end
	if not p.change then
		return nil, "You already have this build: nothing changed."
	end
	if seenCost and p.cost > seenCost then
		return nil, "The price changed since the preview. Preview the build again."
	end
	-- the same checks as a normal save (known ids, connected, points owned)
	local ids, invalid = T.validateNodes(player, plan.nodes)
	if not ids then
		return nil, invalid
	end
	local R = ChaosRespec
	if p.cost > 0 and not (R and R.pay(player, p.cost) or (not R and player:removeMoney(p.cost))) then
		return nil, string.format("You need %s gold coins (carried or in the bank) to take points back for this build.",
			ChaosRespecCore and ChaosRespecCore.formatGold(p.cost) or tostring(p.cost))
	end
	if (p.treeReset or p.paragonReset) and R then
		R.useFree(player)
	end
	local guid = player:getGuid()
	if plan.treeChange then
		local active = activeRow(T, player)
		T.savePreset(guid, active and active.preset or 1, active and active.name or "Preset 1", ids)
	end
	local P = ChaosParagon
	if plan.paragon and plan.paragonChange and P then
		P.save(guid, plan.paragon)
		P.cache[player:getId()] = plan.paragon
	end
	ChaosPassiveTree.apply(player)
	T.sendNodes(player)
	T.sendPoints(player)
	if P and P.sendState then
		P.sendState(player)
	end
	if R then
		R.sendInfo(player)
	end
	local text = string.format("Build imported: %d nodes allocated%s.", #ids,
		p.cost > 0 and string.format(" for %s gold coins", ChaosRespecCore.formatGold(p.cost)) or "")
	if p.skipped > 0 then
		text = text .. string.format(" %d nodes were left out (not enough points).", p.skipped)
	end
	return true, text
end

-- ------------------------------------------------------------------------------------------------ opcode
local actions = ChaosPassiveTree.extraActions

local function sendError(player, text)
	Chaos.send(player, OPCODE, "buildError", {message = text})
end

actions.buildExport = function(player)
	local code, build = B.exportCode(player)
	Chaos.send(player, OPCODE, "buildCode", {code = code, nodes = build.nodes, paragon = build.paragon})
	return true
end

actions.buildPreview = function(player, data)
	local code = type(data) == "table" and data.code or data
	local p, err = B.preview(player, type(code) == "string" and code or "")
	if not p then
		sendError(player, err)
	else
		p.summary = summary(p)
		Chaos.send(player, OPCODE, "buildPreview", p)
	end
	return true
end

actions.buildApply = function(player, data)
	if type(data) ~= "table" or type(data.code) ~= "string" then
		sendError(player, "Malformed request.")
		return true
	end
	local ok, text = B.apply(player, data.code, Chaos.toInt(data.cost, 0))
	if ok then
		Chaos.send(player, OPCODE, "buildApplied", {message = text})
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, text)
	else
		sendError(player, text)
	end
	return true
end

-- ------------------------------------------------------------------------------------------------ chat
local function onBuildCommand(player, words, param)
	local verb, rest = (param or ""):match("^%s*(%S*)%s*(.-)%s*$")
	verb = (verb or ""):lower()
	local id = player:getId()
	if verb == "export" then
		local code = B.exportCode(player)
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "Your build code: " .. code)
		player:sendTextMessage(MESSAGE_INFO_DESCR, "Build link: [build " .. code .. "]  (import with !build import <code>)")
		actions.buildExport(player)
	elseif verb == "import" then
		local p, err = B.preview(player, rest)
		if not p then
			player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "Build import: " .. err)
			return false
		end
		p.summary = summary(p)
		Chaos.send(player, OPCODE, "buildPreview", p)
		for line in p.summary:gmatch("[^\n]+") do
			player:sendTextMessage(MESSAGE_EVENT_ADVANCE, line)
		end
		if p.change then
			B.pending[id] = {code = p.code, cost = p.cost, time = os.time()}
			player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "Type !build confirm to apply it, or !build cancel.")
		end
	elseif verb == "confirm" then
		local pending = B.pending[id]
		B.pending[id] = nil
		if not pending or os.time() - pending.time > PENDING_SECONDS then
			player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "No build import to confirm. Use !build import <code> first.")
			return false
		end
		local ok, text = B.apply(player, pending.code, pending.cost)
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, ok and text or ("Build import: " .. text))
	elseif verb == "cancel" then
		B.pending[id] = nil
		ChaosPassiveTree.internal.sendNodes(player)
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "Build import cancelled.")
	else
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE,
			"!build export: your build code. !build import <code>: preview a build, then !build confirm to apply it.")
	end
	return false
end

local talk = TalkAction("!build")
talk.onSay = onBuildCommand
talk:separator(" ")
talk:register()

local logout = CreatureEvent("ChaosBuildShareLogout")
function logout.onLogout(player)
	B.pending[player:getId()] = nil
	return true
end
logout:register()

local login = CreatureEvent("ChaosBuildShareLogin")
function login.onLogin(player)
	player:registerEvent("ChaosBuildShareLogout")
	return true
end
login:register()
