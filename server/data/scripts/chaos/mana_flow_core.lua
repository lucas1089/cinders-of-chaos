-- mana_flow_core.lua: the pure rules of the mana flow (ChaosManaFlow): the regeneration by level and the cap of a
-- spell's cost. No engine calls; mana_flow.lua is the glue. Numbers: mana_flow_config.lua. Test:
-- server/tests/mana_flow_test.lua. Lua 5.1 / LuaJIT and Lua 5.3 compatible.

ChaosManaFlowConfig = ChaosManaFlowConfig or dofile("data/scripts/chaos/mana_flow_config.lua")

ChaosManaFlow = ChaosManaFlow or {}
local F = ChaosManaFlow
F.cfg = ChaosManaFlowConfig
local floor = math.floor

-- mana a second at a level: 0 below regen.fromLevel, linear between the curve points, the last value past the last
function F.regenPerSecond(level, cfg)
	cfg = cfg or F.cfg
	level = tonumber(level) or 1
	local r = cfg.regen
	if level < r.fromLevel then
		return 0
	end
	local curve = r.curve
	if level <= curve[1][1] then
		return curve[1][2]
	end
	for i = 2, #curve do
		local a, b = curve[i - 1], curve[i]
		if level <= b[1] then
			return a[2] + (b[2] - a[2]) * (level - a[1]) / (b[1] - a[1])
		end
	end
	return curve[#curve][2]
end

-- the whole mana one think gives: nil/0 when nothing to give (below the level, a full pool, Parched Veins, dead)
function F.regenAmount(level, mana, maxMana, noMana, dead, cfg)
	if noMana or dead then
		return 0
	end
	mana, maxMana = tonumber(mana) or 0, tonumber(maxMana) or 0
	if mana >= maxMana then
		return 0
	end
	local give = floor(F.regenPerSecond(level, cfg) + 0.5)
	return math.max(0, math.min(give, maxMana - mana))
end

-- the cost of a cast after the cap: at most cap.share of the maximum mana (reserved mana included), from cap.fromLevel
function F.capCost(mana, level, maxMana, reserved, cfg)
	cfg = cfg or F.cfg
	mana = tonumber(mana) or 0
	if mana <= 0 or (tonumber(level) or 1) < cfg.cap.fromLevel then
		return mana
	end
	local pool = (tonumber(maxMana) or 0) + (tonumber(reserved) or 0)
	if pool <= 0 then
		return mana
	end
	return math.min(mana, math.max(1, floor(pool * cfg.cap.share)))
end

return F
