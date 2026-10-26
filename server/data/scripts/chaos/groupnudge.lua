-- The group nudge (client game_partyfinder, extended opcode 208 action "nudge"; server/README.md "The group nudge
-- (O261)"). Rules: groupnudge_core.lua (pure, tests/groupnudge_test.lua); numbers: groupnudge_config.lua.
--
-- dungeons.lua (a run starts for a lone player) and rift.lua (a rift opens for a lone player) call
-- ChaosGroupNudge.onEnter(player, "dungeon" | "rift", detail) behind a guard. If the Party Finder has open groups for that
-- content, the player gets one line, "2 players look for a group for Rift T5." and the client adds a [Join] button that opens
-- the Party Finder. At most once per ten minutes per player. No storage, no table, no timer.
--
-- Protocol: server -> client on the Party Finder opcode: nudge {text, a, n}. Lua 5.1 / LuaJIT and Lua 5.3 compatible.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not Chaos.t then
	dofile("data/scripts/chaos/i18n_core.lua")
end
dofile("data/scripts/chaos/groupnudge_core.lua")
ChaosGroupNudgeConfig = dofile("data/scripts/chaos/groupnudge_config.lua")

ChaosGroupNudge = ChaosGroupNudge or {}
local G = ChaosGroupNudge
local N = ChaosGroupNudgeCore
G.last = G.last or {} -- guid -> os.time() of the last nudge
G.sweptAt = G.sweptAt or 0

local function cfg()
	return ChaosGroupNudgeConfig
end

-- Returns the number of players looking for a group when a nudge was sent, else nil
function G.onEnter(player, activity, detail)
	local c = cfg()
	local PF = ChaosPartyFinder
	if not c.enabled or not PF or not PF.state or not PF.who or not PF.acts or not c.activities[activity] then
		return nil
	end
	local who = PF.who(player)
	if N.groupSize(who) > c.aloneUpTo then
		return nil
	end
	local now = os.time()
	local n, label = N.looking(PF.state, Chaos.partyFinderConfig, PF.acts(), who, activity, detail)
	if n <= 0 then
		return nil
	end
	-- the cooldown is spent only when there is something to say
	if not N.due(G.last, who.guid, now, c.cooldownSeconds) then
		return nil
	end
	if now - G.sweptAt > c.cooldownSeconds then
		G.sweptAt = now
		N.sweep(G.last, now, c.cooldownSeconds)
	end
	local text
	if n == 1 then
		text = Chaos.t(player, "1 player looks for a group for %s.", label)
	else
		text = Chaos.t(player, "%d players look for a group for %s.", n, label)
	end
	Chaos.send(player, ChaosOpcodes.partyFinder or 208, "nudge", {text = text, a = activity, n = n})
	return n
end

