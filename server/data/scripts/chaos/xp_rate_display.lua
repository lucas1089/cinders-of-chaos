-- The "XP gain rate" of the client's Skills window counts every bonus (xp_rate_display_core.lua; server/README.md "XP
-- gain rate display"). The engine sends the rate from the player's base XP gain (Player:setBaseXpGain, which sends the
-- stats), and the Chaos bonuses (world, self, passive tree, item mods, party, ...) are multipliers in the
-- onGainExperience chain, so the window stayed at 100%. This callback runs after every bonus (index 999, before the hunt
-- tracker at 1000) and sets the base XP gain to what the last monster kill really gave over its base experience.
-- Assumed engine API (not verified on a running server): Player:setBaseXpGain, Player:getStaminaXpBoost; both guarded.
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.

if not ChaosXpRateDisplay or not ChaosXpRateDisplay.percent then
	dofile("data/scripts/chaos/xp_rate_display_core.lua")
end
local R = ChaosXpRateDisplay

local entered = {} -- player id -> experience as the chain started (this call only; stands in for a missing rawExp)
local last = {} -- player id -> the base XP gain last sent

local record = EventCallback
record.onGainExperience = function(player, source, exp, rawExp)
	if source ~= nil and source.isMonster ~= nil and source:isMonster() then
		entered[player:getId()] = exp
	end
	return exp
end
record:register(-999)

local show = EventCallback
show.onGainExperience = function(player, source, exp, rawExp)
	local pid = player:getId()
	local enteredExp = entered[pid]
	entered[pid] = nil
	if source == nil or source.isMonster == nil or not source:isMonster() or (tonumber(exp) or 0) <= 0 then
		return exp
	end
	if not (ChaosXpCap and ChaosXpCap.baseOf) or not player.setBaseXpGain then
		return exp
	end
	local okB, base = pcall(ChaosXpCap.baseOf, player, source, rawExp, enteredExp)
	local pct = okB and R.percent(exp, base)
	if not pct then
		return exp
	end
	local stamina = 100
	if player.getStaminaXpBoost then
		local okS, v = pcall(player.getStaminaXpBoost, player)
		stamina = okS and tonumber(v) or 100
	end
	local gain = R.baseGain(pct, stamina)
	if gain and last[pid] ~= gain then
		last[pid] = gain
		pcall(player.setBaseXpGain, player, gain)
	end
	return exp
end
show:register(999)

local gone = CreatureEvent("ChaosXpRateLogout")
function gone.onLogout(player)
	last[player:getId()] = nil
	entered[player:getId()] = nil
	return true
end
gone:register()
