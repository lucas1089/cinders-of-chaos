-- The group nudge (groupnudge.lua, groupnudge_core.lua; client game_partyfinder; server/README.md "The group nudge
-- (O261)"): every number. Plain table, loaded with
--     ChaosGroupNudgeConfig = dofile("data/scripts/chaos/groupnudge_config.lua")
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.
--
-- Retention pass, owner 2026-10-26: players play alone. Entering a dungeon or a rift alone shows one line when the Party
-- Finder has open groups for that content ("2 players look for a group for Rift T5."), with a Join button on the client
-- that opens the Party Finder on its browse tab. No storage: the cooldown is kept in memory.
return {
	enabled = true,

	-- at most one nudge per player in this many seconds (any content)
	cooldownSeconds = 600,

	-- the contents that nudge: Party Finder activity key (party_finder_config.lua activities) of what was entered
	activities = {rift = true, dungeon = true},

	-- the group is "alone" up to this many members (the entering player's party, the player included)
	aloneUpTo = 1
}
