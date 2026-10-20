-- passivetree_stats.lua: the stat help of the passive tree window (ROADMAP "stat help"). Texts and the Primary /
-- Secondary lists of every class: passivetree_stats_config.lua; rules: passivetree_stats_core.lua.
--
-- Protocol (opcode 65, through ChaosPassiveTree.extraActions, passivetree.lua):
--   client -> server  statInfo                -> a few statInfo messages (the stats of the player's class, 10 a message)
--   server -> client  {"action":"statInfo","data":{cls, part, parts, header = {primary, secondary} (part 1), stats = [{k, n, d,
--                      t = "primary" | "secondary" | nil}]}}  names and descriptions in the player's language (Chaos.t)
-- The window shows the header, marks the nodes (gold: a primary stat, silver: a secondary one), adds the description under
-- each stat of a node tooltip and lists every stat in its Stats panel.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not Chaos.t then
	dofile("data/scripts/chaos/i18n_core.lua")
end
if not ChaosPassiveStatsConfig then
	dofile("data/scripts/chaos/passivetree_stats_config.lua")
end
if not PassiveStatsCore then
	dofile("data/scripts/chaos/passivetree_stats_core.lua")
end

local OPCODE = ChaosOpcodes.passivetree
ChaosPassiveTree = ChaosPassiveTree or {}
ChaosPassiveTree.extraActions = ChaosPassiveTree.extraActions or {}

ChaosPassiveTree.extraActions.statInfo = function(player)
	local T = ChaosPassiveTree.internal
	local classKey = ChaosPassiveTree.classKey and ChaosPassiveTree.classKey(player)
	if not T or not classKey then
		return true
	end
	local parts = PassiveStatsCore.parts(ChaosPassiveStatsConfig, classKey, T.getTree(), function(text)
		return Chaos.t(player, text)
	end)
	for _, part in ipairs(parts) do
		Chaos.send(player, OPCODE, "statInfo", part)
	end
	return true
end
