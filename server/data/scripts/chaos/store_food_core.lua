-- Everfull Ration: pure rules (no engine calls), shared by store_food.lua and server/tests/store_food_test.lua.
--   ChaosStoreFoodCore.bite(cfg, s)   s = {ticksMs, nowMs, lastMs, owner, guid} -> {ok, seconds} | {ok = false, why, text}
--   ChaosStoreFoodCore.storeCheck(cfg, s)   s = {installed, owned, owed} -> nil (can buy) | refusal text
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.
ChaosStoreFoodCore = ChaosStoreFoodCore or {}
local K = ChaosStoreFoodCore

-- the seconds of regeneration one bite gives (the best stock food)
function K.seconds(cfg)
	return cfg.foodValue * cfg.secondsPerValue
end

-- one use of the ration. ticksMs = the regeneration condition's ticks left (0 = none); owner = the guid on the item
-- (nil: an old or GM-made copy, anyone may eat); lastMs = the character's last bite.
function K.bite(cfg, s)
	if s.owner and s.guid and s.owner ~= s.guid then
		return {ok = false, why = "owner", text = "This ration belongs to someone else."}
	end
	if s.lastMs and s.nowMs and s.nowMs - s.lastMs < (cfg.exhaustMs or 0) then
		return {ok = false, why = "exhaust", text = nil}
	end
	local add = K.seconds(cfg)
	if math.floor((s.ticksMs or 0) / 1000 + add) >= cfg.maxSeconds then
		return {ok = false, why = "full", text = "You are full."}
	end
	return {ok = true, seconds = add}
end

function K.storeCheck(cfg, s)
	if not s.installed then
		return "The Everfull Ration is not installed on this server yet."
	end
	if s.owned then
		return "You already have an Everfull Ration (backpack, inbox or depot). One per character."
	end
	if s.owed then
		return "Your Everfull Ration comes back at your next login."
	end
	return nil
end
