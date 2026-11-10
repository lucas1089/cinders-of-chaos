-- pvp_scale_core.lua: the PvP damage scale (O473; the table: pvp_balance_config.lua `damageScale`; applied once, in
-- passivetree_effects.lua ChaosPassiveDealt; tests: server/tests/pvp_scale_test.lua). Pure: no engine call besides the getters
-- of the creatures it is handed. Lua 5.1 / LuaJIT and Lua 5.3 compatible.
--
-- The one additive damage pool (damage_pool_core.lua) and the weapon, gear and tier changes of the same round raise the damage a
-- player deals, to players too. A duel must keep today's length, so every hit a player (or a summon or companion of a player)
-- deals to ANOTHER player is multiplied by a factor of the ATTACKER's level: the rows of the table, geometric between two
-- rows (the logarithm of the factor is linear in the level, as display_scale_core.lua's curve), the first factor below the
-- first row and the last above the last. A monster's hit, a heal and a hit on a monster are never scaled.

ChaosPvpScale = ChaosPvpScale or {}
local S = ChaosPvpScale

if not ChaosPvpBalanceConfig then
	ChaosPvpBalanceConfig = dofile("data/scripts/chaos/pvp_balance_config.lua")
end

local exp, log = math.exp, math.log

-- the table: {{level, factor}, ...} ascending by level
function S.table(cfg)
	cfg = cfg or ChaosPvpBalanceConfig
	return cfg and cfg.damageScale or {}
end

-- the factor of an attacker's level
function S.factor(level, cfg)
	local pts = S.table(cfg)
	if #pts == 0 then
		return 1
	end
	level = tonumber(level)
	if not level then
		return 1 -- O475: the first row is no longer 1, so an unknown level must not take it
	end
	if level <= pts[1][1] then
		return pts[1][2]
	end
	if level >= pts[#pts][1] then
		return pts[#pts][2]
	end
	for i = 2, #pts do
		local a, b = pts[i - 1], pts[i]
		if level <= b[1] then
			local t = (level - a[1]) / (b[1] - a[1])
			return exp(log(a[2]) + (log(b[2]) - log(a[2])) * t)
		end
	end
	return pts[#pts][2]
end

-- The scale of one hit. owner = the player whose level counts (the attacker, or the master of a summon), target = the creature
-- hit, attacker = who dealt it. 1 unless the target is another player.
function S.forHit(owner, target, attacker)
	if not owner or not target or not target.isPlayer or not target:isPlayer() then
		return 1
	end
	if target == owner or target == attacker then
		return 1
	end
	local ok, level = pcall(function() return owner:getLevel() end)
	if not ok or not tonumber(level) then
		return 1
	end
	return S.factor(level)
end

return S
