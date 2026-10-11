-- Crafting bonus: pure logic (no engine calls), shared by craft_bonus.lua and server/tests/craft_bonus_test.lua.
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible (integers through math.floor). Numbers: craft_bonus_config.lua.
--
-- The base crafting tables (data/scripts/customs/crafting/1crafting_mod.lua, patched by
-- server/tools/patch_base_crafting_bonus.py) ask craft_bonus.lua for two things, both by the crafter's mastery
-- (skill in the recipe's category minus the recipe's required level):
--   equipment: a rarity (Common .. Legendary) and an item level, rolled the way a drop is (ChaosCrafting.createItem)
--   potions and runes: extra pieces on top of the recipe's count
--
--   K.mastery(recipeLevel, skill)                 skill above the recipe's level, 0 at least
--   K.gearMult(cfg, mastery)                      the factor on every rarity chance
--   K.gearOdds(cfg, recipeLevel, skill)           {{rarity, pct}, ...} best first, pct with up to 2 decimals
--   K.itemLevel(cfg, recipeLevel, skill, typeLevel)  the item level of the crafted piece
--   K.rollGear(cfg, recipeLevel, skill, rand)     a rarity, 0 = plain
--   K.yieldOdds(cfg, recipeLevel, skill, count)   {{extra, pct}, ...} best first
--   K.rollYield(cfg, recipeLevel, skill, count, rand)  extra pieces, 0 = none
--   K.isTool(cfg, kind, slots)                    an "other" item that only fits the hands: a tool, no equipment
--   K.isYieldId(cfg, id)                          a potion of the config list
--   K.plural(name) / K.article(word)              "Health Potions" / "a" | "an"
--   K.gearText(name, rarityName, level)           "You crafted a Rare Steel Axe (item level 32)."
--   K.yieldText(name, total, extra, inbox)        "You crafted 7 Exalted Health Potions (bonus +2)."
-- rand(a, b) is math.random's contract.

ChaosCraftBonusCore = ChaosCraftBonusCore or {}
local K = ChaosCraftBonusCore
local floor = math.floor

local function num(v)
	return tonumber(v) or 0
end

local function clamp(v, lo, hi)
	if v < lo then
		return lo
	end
	if v > hi then
		return hi
	end
	return v
end

-- percent to 2 decimals
local function round2(p)
	return floor(p * 100 + 0.5) / 100
end

-- percent -> roll units (1 / 1000 of a percent): a roll of rand(1, 100000)
local UNITS = 100000
local function units(p)
	return floor(p * 1000 + 0.5)
end

function K.mastery(recipeLevel, skill)
	return math.max(0, floor(num(skill) - num(recipeLevel)))
end

-- ---------------------------------------------------------------- equipment
function K.gearMult(cfg, mastery)
	local g = cfg.gear
	return 1 + math.min(g.maxBonus, math.max(0, num(mastery)) * g.perPoint)
end

function K.gearOdds(cfg, recipeLevel, skill)
	local g = cfg.gear
	local mult = K.gearMult(cfg, K.mastery(recipeLevel, skill))
	local rows, total = {}, 0
	for _, o in ipairs(g.odds) do
		if o.rarity >= 1 and o.rarity <= g.maxRarity and o.chance > 0 then
			rows[#rows + 1] = {rarity = o.rarity, pct = o.chance * mult}
			total = total + o.chance * mult
		end
	end
	-- above the cap every chance shrinks by the same factor
	local scale = total > g.maxTotal and g.maxTotal / total or 1
	for _, r in ipairs(rows) do
		r.pct = round2(r.pct * scale)
	end
	table.sort(rows, function(a, b) return a.rarity > b.rarity end)
	return rows
end

function K.itemLevel(cfg, recipeLevel, skill, typeLevel)
	local il = cfg.gear.itemLevel
	local lv = math.max(1, floor(num(recipeLevel))) + floor(K.mastery(recipeLevel, skill) * il.perMastery)
	lv = math.max(lv, floor(num(typeLevel)))
	return clamp(lv, 1, il.max)
end

-- the best rarity first: one roll over the summed chances
function K.rollGear(cfg, recipeLevel, skill, rand)
	local roll, acc = rand(1, UNITS), 0
	for _, r in ipairs(K.gearOdds(cfg, recipeLevel, skill)) do
		acc = acc + units(r.pct)
		if roll <= acc then
			return r.rarity
		end
	end
	return 0
end

-- true when every bit of slots is one of mask's (no bit operators: Lua 5.1 has none)
local function within(slots, mask)
	slots, mask = floor(num(slots)), floor(num(mask))
	while slots > 0 do
		if slots % 2 == 1 and mask % 2 == 0 then
			return false
		end
		slots, mask = floor(slots / 2), floor(mask / 2)
	end
	return true
end

function K.isTool(cfg, kind, slots)
	return kind == "other" and within(slots, cfg.gear.toolSlots)
end

-- ---------------------------------------------------------------- potions and runes
function K.isYieldId(cfg, id)
	id = num(id)
	for _, v in ipairs(cfg.yield.ids) do
		if v == id then
			return true
		end
	end
	return false
end

function K.yieldOdds(cfg, recipeLevel, skill, count)
	local m = K.mastery(recipeLevel, skill)
	count = math.max(1, floor(num(count)))
	local rows = {}
	for _, s in ipairs(cfg.yield.steps) do
		local pct = round2(math.min(s.max, s.base + m * s.perPoint))
		local extra = math.ceil(count * s.mult - 1e-9)
		if pct > 0 and extra > 0 then
			rows[#rows + 1] = {extra = extra, pct = pct}
		end
	end
	table.sort(rows, function(a, b) return a.extra > b.extra end)
	return rows
end

function K.rollYield(cfg, recipeLevel, skill, count, rand)
	local roll, acc = rand(1, UNITS), 0
	for _, r in ipairs(K.yieldOdds(cfg, recipeLevel, skill, count)) do
		acc = acc + units(r.pct)
		if roll <= acc then
			return r.extra
		end
	end
	return 0
end

-- expected extra pieces per craft (for the README and the tests)
function K.yieldMean(cfg, recipeLevel, skill, count)
	local e = 0
	for _, r in ipairs(K.yieldOdds(cfg, recipeLevel, skill, count)) do
		e = e + r.extra * r.pct / 100
	end
	return e
end

-- ---------------------------------------------------------------- texts
function K.article(word)
	return tostring(word or ""):match("^[AEIOUaeiou]") and "an" or "a"
end

function K.plural(name)
	name = tostring(name or "")
	if name:match("[sxz]$") or name:match("[cs]h$") then
		return name .. "es"
	end
	if name:match("[^aeiouAEIOU]y$") then
		return name:sub(1, -2) .. "ies"
	end
	return name .. "s"
end

function K.gearText(name, rarityName, level)
	local full = rarityName and rarityName ~= "" and (rarityName .. " " .. name) or name
	return string.format("You crafted %s %s (item level %d).", K.article(full), full, floor(num(level)))
end

function K.yieldText(name, total, extra, inbox)
	total, extra, inbox = floor(num(total)), floor(num(extra)), floor(num(inbox))
	local what = total == 1 and (K.article(name) .. " " .. name) or (total .. " " .. K.plural(name))
	local text = "You crafted " .. what
	if extra > 0 then
		text = text .. string.format(" (bonus +%d)", extra)
	end
	text = text .. "."
	if inbox > 0 then
		text = text .. string.format(" Your backpack was full: %d went to your store inbox.", inbox)
	end
	return text
end

return K
