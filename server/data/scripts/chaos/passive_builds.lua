-- passive_builds.lua: the Auto build button of the passive tree window. Rules: passive_builds_core.lua, the paths
-- (generated from the real tree): passive_builds_data.lua, recipes and texts: passive_builds_config.lua.
--
-- Every class has 3 Recommended builds and the Focus builds (damage, leech, mana, defense ...) it has enough relevant nodes
-- for. A build is a path from the start; the character takes as many nodes of it as it has points for.
--
-- Protocol (opcode 65, through ChaosPassiveTree.extraActions, passivetree.lua; the player picks the build):
--   client -> server  autobuildList                     -> autobuildList (twice: group "role" and group "focus")
--                     autobuildPreview {build}          -> autobuildPreview {build, add = {...}, reset = {...}, ...}
--                     autobuildApply {build, mode = "add" | "reset", cost}
--                                                       -> autobuildApplied {message, applied, skipped, removed} or
--                                                          autobuildError {message}; sendNodes, sendPoints, respecInfo follow
--   server -> client  {"action":"autobuildList","data":{group, builds = [{id, name, text, summary, points, fit}], owned,
--                      held, free, cap}}
--                     {"action":"autobuildPreview","data":{build, name, owned, held, add = {nodes, added, skipped},
--                      reset = {nodes, added, skipped, removed, cost, free}, masteries}}   (nodes = the whole allocation)
-- Rules: "add" only adds the missing nodes, free; it never takes anything back. "reset" is the tree's Reset and apply: the
-- full reset price of respec.lua (free below its level and once after a class change) when it takes nodes back; it uses
-- respec.lua's pay / useFree, never its own price. At most one request a second (ratelimit.lua).

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not Chaos.t then
	dofile("data/scripts/chaos/i18n_core.lua")
end
if not ChaosPassiveBuildsConfig then
	dofile("data/scripts/chaos/passive_builds_config.lua")
end
if not ChaosPassiveStatsConfig then
	dofile("data/scripts/chaos/passivetree_stats_config.lua")
end
if not PassiveStatsCore then
	dofile("data/scripts/chaos/passivetree_stats_core.lua")
end
if not PassiveBuildsCore then
	dofile("data/scripts/chaos/passive_builds_core.lua")
end
if not ChaosClasses then
	dofile("data/scripts/chaos/classes.lua")
end

local OPCODE = ChaosOpcodes.passivetree
local cfg = ChaosPassiveBuildsConfig
local Core = PassiveBuildsCore
local data -- loaded on first use

ChaosPassiveTree = ChaosPassiveTree or {}
ChaosPassiveTree.extraActions = ChaosPassiveTree.extraActions or {}
ChaosPassiveBuilds = ChaosPassiveBuilds or {}
local P = ChaosPassiveBuilds

local function getData()
	if not data then
		data = dofile("data/scripts/chaos/passive_builds_data.lua")
	end
	return data
end

local function fail(player, text)
	Chaos.send(player, OPCODE, "autobuildError", {message = text})
end

local function limited(player)
	return ChaosRateLimit and not ChaosRateLimit.allow(player, "passivetree.autobuild", cfg.rateMs or 1000)
end

-- the state of the character: {classKey, active row, current ids, masteries, points}
local function state(player)
	local T = ChaosPassiveTree.internal
	local classKey = ChaosPassiveTree.classKey(player)
	local active = T.loadPresets(player:getGuid())[1]
	local current = active and active.nodes or {}
	return {
		T = T, classKey = classKey, active = active, current = current, points = T.totalPoints(player),
		masteries = active and T.core.cleanMasteries(T.getTree(), current, active.masteries) or {}
	}
end

local function respecPrice(player)
	local R = ChaosRespec
	if not R then
		return player:getLevel() * Chaos.passive.resetCostPerLevel, nil
	end
	return R.fullCost(player, "tree"), R.freeText(player)
end

local function textFor(player)
	return function(text)
		return Chaos.t(player, text)
	end
end

-- ------------------------------------------------------------------------------------------------ list
ChaosPassiveTree.extraActions.autobuildList = function(player)
	local st = state(player)
	if not st.classKey then
		return true
	end
	local T = textFor(player)
	local list = Core.list(getData(), cfg, ChaosPassiveStatsConfig, st.classKey)
	local groups = {role = {}, focus = {}}
	for _, b in ipairs(list) do
		groups[b.kind][#groups[b.kind] + 1] = {
			id = b.id, name = T(b.name), text = T(b.text), summary = Core.summary(cfg, b.top, T), points = b.points, fit = b.fit
		}
	end
	for _, group in ipairs({"role", "focus"}) do
		Chaos.send(player, OPCODE, "autobuildList", {
			group = group, builds = groups[group], owned = st.points, held = #st.current,
			free = math.max(0, st.points - #st.current), cap = cfg.maxPoints
		})
	end
	return true
end

-- the build of the request, or nil + an error text
local function pick(player, st, id)
	if type(id) ~= "string" or #id > 60 or not st.classKey then
		return nil, Chaos.t(player, "Unknown build.")
	end
	local build = Core.find(getData(), st.classKey, id)
	if not build then
		return nil, Chaos.t(player, "That build is not for your class.")
	end
	return build
end

local function planFor(st, build, reset)
	return Core.plan(st.T.getTree(), build, {
		classKey = st.classKey, current = st.current, currentMasteries = st.masteries, points = st.points, reset = reset
	})
end

local function skippedList(plan)
	local out = {}
	for i, s in ipairs(plan.skipped) do
		if i > 40 then
			break
		end
		out[i] = {id = s.id, why = s.why}
	end
	return out
end

local function countWhy(plan, why)
	local n = 0
	for _, s in ipairs(plan.skipped) do
		if s.why == why then
			n = n + 1
		end
	end
	return n
end

-- ------------------------------------------------------------------------------------------------ preview
ChaosPassiveTree.extraActions.autobuildPreview = function(player, data)
	if limited(player) then
		return true
	end
	local st = state(player)
	local build, err = pick(player, st, type(data) == "table" and data.build or nil)
	if not build then
		fail(player, err)
		return true
	end
	local add, reset = planFor(st, build, false), planFor(st, build, true)
	local cost, free = respecPrice(player)
	local tree = st.T.getTree()
	local entry
	for _, e in ipairs(Core.list(getData(), cfg, ChaosPassiveStatsConfig, st.classKey)) do
		if e.id == build.id then
			entry = e
		end
	end
	local function side(plan, extra)
		extra.nodes, extra.added, extra.skipped = plan.ids, #plan.added, countWhy(plan, "points")
		extra.other = #plan.skipped - extra.skipped
		return extra
	end
	local masteries = st.T.core.toList(add.masteries)
	local resetSide = side(reset, {removed = #reset.removed, cost = reset.treeReset and cost or 0, free = reset.treeReset and free or nil,
		masteries = st.T.core.toList(reset.masteries)})
	Chaos.send(player, OPCODE, "autobuildPreview", {
		build = build.id, name = entry and Chaos.t(player, entry.name) or build.id, owned = st.points, held = #st.current,
		wanted = #build.order, add = side(add, {masteries = masteries}), reset = resetSide
	})
	return true
end

-- ------------------------------------------------------------------------------------------------ apply
function P.apply(player, buildId, mode, seenCost)
	local st = state(player)
	local build, err = pick(player, st, buildId)
	if not build then
		return nil, err
	end
	local reset = mode == "reset"
	if mode ~= "add" and not reset then
		return nil, Chaos.t(player, "Malformed request.")
	end
	local plan = planFor(st, build, reset)
	if not plan.changed then
		return nil, Chaos.t(player, "Nothing would change: you already have this build, or you have no free points.")
	end
	-- the same checks as a normal save (known ids, class, connected, points owned)
	local ids, invalid = st.T.validateNodes(player, plan.ids)
	if not ids then
		return nil, invalid
	end
	local R = ChaosRespec
	local cost, free = 0, nil
	if plan.treeReset then
		cost, free = respecPrice(player)
		if seenCost and cost > seenCost then
			return nil, Chaos.t(player, "The price changed since the preview. Open the build again.")
		end
		local paid
		if R then
			paid = R.pay(player, cost)
		else
			paid = cost <= 0 or player:removeMoney(cost)
		end
		if not paid then
			return nil, Chaos.t(player, "You need %s gold coins (carried or in the bank) to reset your tree first.",
				ChaosRespecCore and ChaosRespecCore.formatGold(cost) or tostring(cost))
		end
		if R then
			R.useFree(player)
		end
	end
	local guid = player:getGuid()
	st.T.savePreset(guid, st.active and st.active.preset or 1, st.active and st.active.name or "Preset 1", ids, plan.masteries)
	ChaosPassiveTree.apply(player)
	st.T.sendNodes(player)
	st.T.sendPoints(player)
	if R and R.sendInfo then
		R.sendInfo(player)
	end
	local text
	if plan.treeReset then
		text = Chaos.t(player, "Auto build: %d nodes now allocated, %d taken back%s.", #ids, #plan.removed,
			cost > 0 and (" " .. Chaos.t(player, "for %s gold coins", ChaosRespecCore and ChaosRespecCore.formatGold(cost) or tostring(cost)))
				or (free and (" " .. Chaos.t(player, "(free)")) or ""))
	else
		text = Chaos.t(player, "Auto build: %d nodes added, %d in all.", #plan.added, #ids)
	end
	local left = countWhy(plan, "points")
	if left > 0 then
		text = text .. " " .. Chaos.t(player, "%d more nodes of the build need more points.", left)
	end
	return true, text, plan
end

ChaosPassiveTree.extraActions.autobuildApply = function(player, data)
	if type(data) ~= "table" then
		fail(player, Chaos.t(player, "Malformed request."))
		return true
	end
	if limited(player) then
		fail(player, Chaos.t(player, "Too fast: wait a moment and apply again."))
		return true
	end
	local ok, text, plan = P.apply(player, data.build, data.mode, Chaos.toInt(data.cost, 0))
	if ok then
		Chaos.send(player, OPCODE, "autobuildApplied", {
			message = text, applied = plan.added, removed = plan.removed, skipped = skippedList(plan)
		})
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, text)
	else
		fail(player, text)
	end
	return true
end
