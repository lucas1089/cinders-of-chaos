-- Reward chest sparkle (server/README.md "Reward chests"): one shared GlobalEvent glints every unopened reward chest a
-- system registered, so the chest stands out on a dark floor. Rules: reward_sparkle_core.lua (tests/reward_sparkle_test.lua);
-- numbers: reward_sparkle_config.lua.
--   ChaosRewardSparkle.add(key, pos, itemId, check)   the rift chest (rift.lua), the sealed coffer; check() -> false
--                                                     when nothing is left to take
--   ChaosRewardSparkle.remove(key)
-- Assumed engine API (TFS 1.4): GlobalEvent think, Tile(pos):getItemById, Position:sendMagicEffect, os.time.
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.

dofile("data/scripts/chaos/reward_sparkle_core.lua")
ChaosRewardSparkleConfig = dofile("data/scripts/chaos/reward_sparkle_config.lua")

ChaosRewardSparkle = ChaosRewardSparkle or {}
local S = ChaosRewardSparkle
local K = ChaosRewardSparkleCore
S.state = S.state or K.new()

local function cfg()
	return ChaosRewardSparkleConfig
end

function S.add(key, pos, itemId, check)
	if not cfg().enabled then
		return false
	end
	return K.add(S.state, cfg(), key, pos, itemId, os.time(), check)
end

function S.remove(key)
	return K.remove(S.state, key)
end

local function exists(pos, itemId)
	local tile = Tile(Position(pos.x, pos.y, pos.z))
	return tile ~= nil and tile:getItemById(itemId) ~= nil
end

local think = GlobalEvent("ChaosRewardSparkle")
function think.onThink(interval)
	if K.count(S.state) == 0 then
		return true
	end
	local effect = _G[cfg().effect or ""]
	for _, e in ipairs(K.due(S.state, cfg(), os.time(), exists)) do
		if effect then
			Position(e.pos.x, e.pos.y, e.pos.z):sendMagicEffect(effect)
		end
	end
	return true
end
think:interval(ChaosRewardSparkleConfig.intervalMs or 2500)
think:register()
