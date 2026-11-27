-- The "XP gain rate" of the client's Skills window counts every bonus (xp_rate_display_core.lua; server/README.md "XP
-- gain rate display"). The engine sends the rate from the player's base XP gain (Player:setBaseXpGain, which sends the
-- stats), and the Chaos bonuses (world, self, passive tree, item mods, party, ...) are multipliers in the
-- onGainExperience chain, so the window stayed at 100%. This callback runs after every bonus (index 999, before the hunt
-- tracker at 1000) and sets the base XP gain to what the last monster kill really gave over its base experience.
-- Engine API: Player:setBaseXpGain (src-patch 0096, O774: the base engine had none and sent a fixed 100); Player:
-- getStaminaXpBoost is not in this engine (guarded: stamina 100). At login (2 s) and after a Pact purchase the line shows
-- the standing rate (R.refresh: the Pact, World Experience); the first kill sets the exact one.
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.

if not ChaosXpRateDisplay or not ChaosXpRateDisplay.percent then
	dofile("data/scripts/chaos/xp_rate_display_core.lua")
end
local R = ChaosXpRateDisplay

local entered = {} -- player id -> experience as the chain started (this call only; stands in for a missing rawExp)
local last = {} -- player id -> the base XP gain last sent
local killGain = {} -- player id -> the gain of the last monster kill, and the standing multiplier then (O774)
local killStanding = {}

-- the standing multiplier of the registered providers (xp_rate_display_core.lua R.providers: the Chaos Pact, World
-- Experience)
local function standing(player)
	local mults = {}
	for name, fn in pairs(R.providers) do
		local ok, v = pcall(fn, player)
		if ok then
			mults[#mults + 1] = v
		end
	end
	return R.product(mults)
end

local function send(player, gain)
	local pid = player:getId()
	if gain and last[pid] ~= gain then
		last[pid] = gain
		pcall(player.setBaseXpGain, player, gain)
	end
end

-- O774: at login and when a standing bonus starts or ends (the Pact bought), the line shows the rate at once instead of
-- waiting for a kill (engine patch 0096 sends it)
function R.refresh(player)
	if not player or not player.setBaseXpGain then
		return nil
	end
	local pid = player:getId()
	local gain = R.refreshGain(killGain[pid], killStanding[pid], standing(player))
	send(player, gain)
	return gain
end

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
	if gain then
		killGain[pid], killStanding[pid] = gain, standing(player)
	end
	send(player, gain)
	return exp
end
show:register(999)

local login = CreatureEvent("ChaosXpRateLogin")
function login.onLogin(player)
	-- after the Pact perks are applied at login (pact_perks.lua, 1500 ms)
	addEvent(function(cid)
		local p = Player(cid)
		if p then
			R.refresh(p)
		end
	end, 2000, player:getId())
	return true
end
login:type("login")
login:register()

local gone = CreatureEvent("ChaosXpRateLogout")
function gone.onLogout(player)
	last[player:getId()] = nil
	entered[player:getId()] = nil
	killGain[player:getId()], killStanding[player:getId()] = nil, nil
	return true
end
gone:register()
