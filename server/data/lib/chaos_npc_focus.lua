-- Only the nearest NPC answers a greeting (live test 2026-10-14: the Loot Buyer stood next to the Gambler, and "hi" /
-- "trade" opened both their windows). Every NPC within its talk radius hears a player; our NPC scripts
-- (data/npc/scripts/*.lua) now pass a line on to their handler only when the player is already talking to them, or
-- when no other NPC within the talk radius stands nearer the player (same distance: the lower creature id answers).
-- The startup placement keeps our NPCs apart as well (data/scripts/chaos/npc_place_core.lua).
--   ChaosNpcFocus.answers(me, others, player, radius) -> bool   pure: me / others = {id, x, y}, player = {x, y}
--   ChaosNpcFocus.hears(cid, npcHandler) -> bool                in an NPC script's onCreatureSay
-- Runs in the NPC scripts' Lua state (dofile) and in server/tests/npc_place_test.lua. Lua 5.1 / LuaJIT and 5.3.
ChaosNpcFocus = ChaosNpcFocus or {}
local F = ChaosNpcFocus

F.RADIUS = 3 -- the base NPC library's talkRadius

local abs, max = math.abs, math.max

local function dist(a, p)
	return max(abs(a.x - p.x), abs(a.y - p.y))
end

function F.answers(me, others, player, radius)
	radius = radius or F.RADIUS
	local mine = dist(me, player)
	for _, o in ipairs(others or {}) do
		if o.id ~= me.id then
			local d = dist(o, player)
			if d <= radius and (d < mine or (d == mine and o.id < me.id)) then
				return false
			end
		end
	end
	return true
end

function F.hears(cid, npcHandler)
	local ok, res = pcall(function()
		if npcHandler and npcHandler.isFocused and npcHandler:isFocused(cid) then
			return true
		end
		local npc, player = Npc(), Player(cid)
		if not npc or not player then
			return true
		end
		local radius = npcHandler and npcHandler.talkRadius or F.RADIUS
		local pp, np = player:getPosition(), npc:getPosition()
		local others = {}
		for _, c in ipairs(Game.getSpectators(pp, false, false, radius, radius, radius, radius) or {}) do
			if c:isNpc() then
				local p = c:getPosition()
				if p.z == pp.z then
					others[#others + 1] = {id = c:getId(), x = p.x, y = p.y}
				end
			end
		end
		return F.answers({id = npc:getId(), x = np.x, y = np.y}, others, {x = pp.x, y = pp.y}, radius)
	end)
	return not ok or res
end
