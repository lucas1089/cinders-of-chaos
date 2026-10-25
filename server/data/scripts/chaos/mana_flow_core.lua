-- mana_flow_core.lua: the pure rules of the mana flow (ChaosManaFlow): the regeneration by level. Spell costs are fixed
-- (no rule here changes them; mana_flow_config.lua). No engine calls; mana_flow.lua is the glue. Numbers:
-- mana_flow_config.lua. Test: server/tests/mana_flow_test.lua. Lua 5.1 / LuaJIT and Lua 5.3 compatible.

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

-- One think for one player (mana_flow.lua calls it every regen.thinkMs for everyone online). Same result as
-- regenAmount(player:getLevel(), ...) but the cheap checks come first: most players sit at a full pool, so the level,
-- the health and the Parched Veins lookup are only read when mana is missing; the rounded amount of a level is cached
-- (F.clearCache() after the config changes). Returns the mana to add (0 when none).
local giveCache, giveCacheCfg = {}, nil
function F.clearCache()
	giveCache, giveCacheCfg = {}, nil
end

function F.thinkPlayer(player, noManaOf)
	local mana, maxMana = player:getMana(), player:getMaxMana()
	if mana >= maxMana then
		return 0
	end
	if player:getHealth() <= 0 or (noManaOf and noManaOf(player:getId())) then
		return 0
	end
	if giveCacheCfg ~= F.cfg then
		giveCache, giveCacheCfg = {}, F.cfg
	end
	local level = player:getLevel()
	local give = giveCache[level]
	if give == nil then
		give = floor(F.regenPerSecond(level) + 0.5)
		giveCache[level] = give
	end
	return math.max(0, math.min(give, maxMana - mana))
end

return F
