-- spell_scaling_core.lua: the magic level share of weapon spells (O468; numbers: spell_scaling_config.lua). Pure: no
-- engine call besides the player getters it is handed. Tests: server/tests/spell_scaling_test.lua. Lua 5.1 / LuaJIT and
-- Lua 5.3 compatible.
--
-- A weapon spell's base damage (the formula of its script: level, weapon skill x attack, flat terms) is multiplied by
-- S.factor(level, magicLevel) = (1 + ML / per) / (1 + refML(level) / per). Applied in the helpers, once per hit:
--   * AttackKit.cast for the melee, distance and monk schools (the blade and shuriken schools through ChaosSpell.weaponStrike),
--   * the SKILLVALUE callback spells (ChaosSpell.weaponFormula), ChaosSpell.weaponStrike, MonkSpell.strike / values,
--   * the wolves' mauls and the companion bite (ChaosClasses.biteValuesFor, autoBiteValuesFor), snares and mines (at placement).
-- Not applied to auto attacks, to caster spells, to the spells that already read the magic level (the Templar line, the
-- Ranger holy spells) nor twice to one hit.
-- O472: the weapon growth W(level) and the caster factor 1 + (W - 1) x min(1.2, wand / mean wand of the level) are below
-- (S.weaponW, S.weaponA, S.casterFactor, S.casterForPlayer); a caster spell takes the caster factor once, through ChaosSpell.casterShare.

ChaosSpellScaling = ChaosSpellScaling or {}
local S = ChaosSpellScaling

local function cfg(c)
	c = c or ChaosSpellScalingConfig
	return c and c.mlShare
end

-- the typical magic level of a weapon class at `level`: linear between the anchors, flat above the last one
function S.refML(level, c)
	local m = cfg(c)
	local pts = m and m.ref
	if not pts or #pts == 0 then
		return 0
	end
	level = tonumber(level) or 0
	if level <= pts[1][1] then
		return pts[1][2]
	end
	for i = 2, #pts do
		local a, b = pts[i - 1], pts[i]
		if level <= b[1] then
			return a[2] + (b[2] - a[2]) * (level - a[1]) / (b[1] - a[1])
		end
	end
	return pts[#pts][2]
end

-- the factor on a weapon spell's base damage for a character of `level` and `magicLevel` (1 without a config)
function S.factor(level, magicLevel, c)
	local m = cfg(c)
	if not m or not m.per or m.per <= 0 then
		return 1
	end
	local f = 1 + math.max(0, tonumber(magicLevel) or 0) / m.per
	if m.normalise then
		f = f / (1 + S.refML(level, c) / m.per)
	end
	return f
end

-- the same for a player object
function S.forPlayer(player, c)
	if not player or not player.getLevel or not player.getMagicLevel then
		return 1
	end
	return S.factor(player:getLevel(), player:getMagicLevel(), c)
end

-- ------------------------------------------------------------------------------------------------ O472: the weapon growth
-- W(level) (config `weaponGrowth`): 1 up to the first row, straight in the logarithm of the level between the rows, flat above
-- the last one. a(level) = 1 + (W - 1) / skillShare: the growth of a weapon's attack (the Monk's fist attack takes it).
function S.weaponW(level, c)
	c = c or ChaosSpellScalingConfig
	local pts = c and c.weaponGrowth
	if not pts or #pts == 0 then
		return 1
	end
	level = tonumber(level) or 0
	if level <= pts[1][1] then
		return pts[1][2]
	end
	for i = 2, #pts do
		local a, b = pts[i - 1], pts[i]
		if level <= b[1] then
			return a[2] + (b[2] - a[2]) * math.log(level / a[1]) / math.log(b[1] / a[1])
		end
	end
	return pts[#pts][2]
end

function S.weaponA(level, c)
	c = c or ChaosSpellScalingConfig
	local share = c and c.skillShare or 0.85
	return 1 + (S.weaponW(level, c) - 1) / share
end

-- the mean wand damage of a level (the gear sets' wand curve, linear between the anchors, flat outside)
function S.wandMeanOfLevel(level, c)
	c = c or ChaosSpellScalingConfig
	local pts = c and c.caster and c.caster.wandMean
	if not pts or #pts == 0 then
		return 0
	end
	level = tonumber(level) or 0
	if level <= pts[1][1] then
		return pts[1][2]
	end
	for i = 2, #pts do
		local a, b = pts[i - 1], pts[i]
		if level <= b[1] then
			return a[2] + (b[2] - a[2]) * (level - a[1]) / (b[1] - a[1])
		end
	end
	return pts[#pts][2]
end

-- the factor on a caster's spells for a character of `level` holding a wand or rod of mean damage `wandMean` (nil or 0: none):
-- 1 + (W - 1) x min(cap, wandMean / mean wand of the level). A wand of the level's band gives exactly W, none gives 1.
function S.casterFactor(level, wandMean, c)
	c = c or ChaosSpellScalingConfig
	local cc = c and c.caster
	local mean = S.wandMeanOfLevel(level, c)
	wandMean = tonumber(wandMean) or 0
	if not cc or mean <= 0 or wandMean <= 0 then
		return 1
	end
	return 1 + (S.weaponW(level, c) - 1) * math.min(cc.cap or 1.2, wandMean / mean)
end

-- the wands and rods: S.wands[server id] = {min, max}, the weapons.xml damage the engine does not give to Lua. The stock ones are
-- data/lib/chaos_base_wands.lua (tools/gen_base_wands.py), ours the generated item tables (tools/install_*.py --lua). Built once.
S.wandFiles = {"data/lib/chaos_base_wands.lua", "data/lib/chaos_gear_sets_items.lua", "data/lib/chaos_relic_sets_items.lua",
	"data/lib/chaos_weapons800.lua"}

local function collect(out, t, key, depth)
	if type(t) ~= "table" or depth > 4 then
		return
	end
	local st = t.stats
	if type(st) == "table" and tonumber(st.wandMax) and tonumber(st.wandMax) > 0 then
		local id = tonumber(t.id) or tonumber(key)
		if id then
			out[id] = {min = tonumber(st.wandMin) or 0, max = tonumber(st.wandMax)}
		end
		return
	end
	for k, v in pairs(t) do
		if type(v) == "table" and k ~= "stats" then
			collect(out, v, k, depth + 1)
		end
	end
end

function S.loadWands()
	if S.wands then
		return S.wands
	end
	local out = {}
	for _, path in ipairs(S.wandFiles) do
		local ok, t = pcall(dofile, path)
		if ok then
			collect(out, t, nil, 0)
		end
	end
	S.wands = out
	return out
end

-- the mean damage of the wand or rod in a player's hands: nil without one. A wand the tables do not list counts as the mean
-- wand of the level (the factor is then exactly W): a missing row must not take the growth away.
function S.equippedWandMean(player)
	if not player or not player.getSlotItem or not rawget(_G, "ItemType") then
		return nil
	end
	local slots = {rawget(_G, "CONST_SLOT_LEFT"), rawget(_G, "CONST_SLOT_RIGHT")}
	for _, slot in ipairs(slots) do
		local ok, item = pcall(player.getSlotItem, player, slot)
		if ok and item then
			local okId, id = pcall(function() return item:getId() end)
			local it = okId and ItemType(id)
			local okWt, wt = pcall(function() return it and it:getWeaponType() end)
			if okWt and wt ~= nil and wt == rawget(_G, "WEAPON_WAND") then
				local w = S.loadWands()[id]
				if w then
					return (w.min + w.max) / 2
				end
				return S.wandMeanOfLevel(player:getLevel())
			end
		end
	end
	return nil
end

-- the factor on the spells of a caster player: his level and his wand or rod (1 without one)
function S.casterForPlayer(player, c)
	if not player or not player.getLevel then
		return 1
	end
	return S.casterFactor(player:getLevel(), S.equippedWandMean(player), c)
end

return S
