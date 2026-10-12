-- Global experience cap (xpcap_core.lua, xpcap_config.lua; server/README.md "Experience cap").
-- The onGainExperience callbacks of the Chaos systems multiply one another; this one, late in the chain, clamps a
-- monster kill's experience to cap x its base (rawExp x monster level factor x stage x tier). When the engine passes
-- no rawExp, the experience as it entered the chain (recorded at the lowest index) stands in for rawExp x factor x stage.
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.

if not ChaosXpCap or not ChaosXpCap.clamp then
	dofile("data/scripts/chaos/xpcap_core.lua")
end
ChaosXpCapConfig = dofile("data/scripts/chaos/xpcap_config.lua")

local X = ChaosXpCap
local function cfg()
	return ChaosXpCapConfig
end

local entered = {} -- player id -> experience as the chain started (this call only)

local function isMonster(source)
	return source ~= nil and source.isMonster ~= nil and source:isMonster()
end

local record = EventCallback
record.onGainExperience = function(player, source, exp, rawExp)
	if isMonster(source) then
		entered[player:getId()] = exp
	end
	return exp
end
record:register(cfg().recordIndex or -1000)

-- the kill's base experience, or nil when unknown
function X.baseOf(player, source, rawExp, enteredExp)
	local tierXp = 1
	local tier = ChaosTierOf and ChaosTierOf(source)
	if tier and ChaosTiers and ChaosTiers[tier] then
		tierXp = ChaosTiers[tier].xp or 1
	end
	rawExp = tonumber(rawExp)
	if rawExp and rawExp > 0 then
		local okL, lvl = pcall(function() return source:getMonsterLevel() end)
		local okS, stage = pcall(function() return Game.getExperienceStage(player:getLevel()) end)
		return X.base(rawExp, okL and lvl or 0, okS and stage or 1, tierXp)
	end
	if enteredExp and enteredExp > 0 then
		return enteredExp * tierXp
	end
	return nil
end

local capCb = EventCallback
capCb.onGainExperience = function(player, source, exp, rawExp)
	local c = cfg()
	local pid = player:getId()
	local enteredExp = entered[pid]
	entered[pid] = nil
	if not c.enabled or not isMonster(source) or (tonumber(exp) or 0) <= 0 then
		return exp
	end
	local base = X.baseOf(player, source, rawExp, enteredExp)
	if not base then
		return exp
	end
	return X.clamp(exp, base, c.cap)
end
capCb:register(cfg().index or 85)
