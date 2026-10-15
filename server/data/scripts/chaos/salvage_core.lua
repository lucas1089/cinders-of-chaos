-- Salvage: pure logic (no engine calls), shared by salvage.lua and server/tests/salvage_test.lua.
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible (integers through math.floor). Numbers: salvage_config.lua.
--
-- An item is described by an info table built by salvage.lua from the engine item:
--   {gear, riftKey, rarity, level (item level), unique, sockets, gems (socketed), highTiers (modifiers of tier
--   cfg.highTier or better), locked, stackable, inBackpack, setPiece (an item set piece: salvaged for setPieceShards
--   although it is a unique without a rarity; "salvage all" never takes one), tokens (the Conquest Tokens a unique gives,
--   conquest.lua; a unique with tokens > 0 may be salvaged when cfg.uniqueTokens, for uniqueShards shards + the tokens)}
--
--   K.isLocked(value)                     a lock attribute value -> true / false
--   K.check(info, cfg)                    nil when the item may be salvaged, else a reason key (K.reasons)
--   K.shards(info, cfg)                   shards the item gives (deterministic)
--   K.orbChance(info, cfg)                chance of a whole orb, per 10000
--   K.roll(info, cfg, rand)               {shards, orb = key | nil}; rand(a, b) is math.random's contract
--   K.preview(info, cfg)                  {ok, why, shards, orbChance (percent)} for the bench
--   K.batch(entries, maxRarity, cfg)      which items of a container "salvage all" takes, the skips and the totals
--   K.signature(list)                     a short hash of the picked items (the confirm must match the preview)
--   K.recipe(key, cfg)                    the recipe of an orb key
--   K.combineCheck(owned, key, count, cfg) ok, cost | nil, reason key

ChaosSalvageCore = ChaosSalvageCore or {}
local K = ChaosSalvageCore
local floor = math.floor

K.reasons = {
	locked = "The item is locked. Unlock it first.",
	unique = "Unique items cannot be salvaged.",
	riftKey = "Rift Keys cannot be salvaged.",
	notGear = "Only gear can be salvaged.",
	normal = "Only items with a rarity can be salvaged.",
	gems = "Take the gems out first (bench: Remove or Shatter).",
	notBackpack = "Put the item in your backpack first (equipped items cannot be salvaged).",
	stack = "Stacks cannot be salvaged.",
	unknownRecipe = "There is no such recipe.",
	shards = "You do not have enough rune shards.",
	count = "Choose how many orbs to make."
}

function K.isLocked(value)
	if value == nil or value == false then
		return false
	end
	local n = tonumber(value)
	if n then
		return n ~= 0
	end
	return value ~= ""
end

function K.check(info, cfg)
	if not info then
		return "notGear"
	end
	if info.locked then
		return "locked"
	end
	if info.riftKey then
		return "riftKey"
	end
	if info.unique and not cfg.allowUniques and not info.setPiece and not (cfg.uniqueTokens and (info.tokens or 0) > 0) then
		return "unique"
	end
	if info.stackable then
		return "stack"
	end
	if not info.gear then
		return "notGear"
	end
	if (info.rarity or 0) < 1 and not info.setPiece and not (info.unique and (info.tokens or 0) > 0) then
		return "normal"
	end
	if (info.gems or 0) > 0 then
		return "gems"
	end
	if info.inBackpack == false then
		return "notBackpack"
	end
	return nil
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

local function rarityIndex(info, cfg)
	return clamp(floor(tonumber(info.rarity) or 0), 1, #cfg.baseShards)
end

-- the item level as a share of the highest, 0..1
function K.levelFraction(level, cfg)
	local max = tonumber(cfg.maxLevel) or 150
	level = floor(tonumber(level) or 0)
	if level <= 0 or max <= 0 then
		return 0
	end
	return math.min(1, level / max)
end

function K.shards(info, cfg)
	if info.setPiece then
		-- an item set piece (data/lib/chaos_item_sets.lua): a fixed number, it has no rarity to price it
		return math.max(1, floor(tonumber(cfg.setPieceShards) or 1))
	end
	if info.unique then
		-- a unique salvaged for Conquest Tokens (info.tokens): a fixed number of shards on top
		return math.max(1, floor(tonumber(cfg.uniqueShards) or 1))
	end
	local r = rarityIndex(info, cfg)
	local base = cfg.baseShards[r]
	local n = floor(base * (1 + cfg.levelBonus * K.levelFraction(info.level, cfg)) + 1e-9)
	n = n + (cfg.perHighTier or 0) * floor(tonumber(info.highTiers) or 0)
	n = n + (cfg.perSocket or 0) * math.max(0, floor(tonumber(info.sockets) or 0) - floor(tonumber(info.gems) or 0))
	return math.max(1, n)
end

function K.orbChance(info, cfg)
	return cfg.orbChance[rarityIndex(info, cfg)] or 0
end

local function weighted(rows, rand)
	local total = 0
	for _, r in ipairs(rows) do
		total = total + r[2]
	end
	if total <= 0 then
		return nil
	end
	local roll = rand(1, total)
	for _, r in ipairs(rows) do
		roll = roll - r[2]
		if roll <= 0 then
			return r[1]
		end
	end
	return rows[#rows][1]
end
K.weighted = weighted

function K.roll(info, cfg, rand)
	local out = {shards = K.shards(info, cfg), tokens = info.unique and (info.tokens or 0) > 0 and info.tokens or nil}
	if rand(1, 10000) <= K.orbChance(info, cfg) then
		out.orb = weighted(cfg.orbWeights, rand)
	end
	return out
end

local function percent(perTenThousand)
	local p = perTenThousand / 100
	if p == floor(p) then
		return string.format("%d", p)
	end
	return (string.format("%.2f", p):gsub("0+$", ""))
end
K.percent = percent

function K.preview(info, cfg)
	local why = K.check(info, cfg)
	if why then
		return {ok = false, why = K.reasons[why] or why, locked = info and info.locked or nil}
	end
	return {ok = true, why = "", shards = K.shards(info, cfg), orbChance = percent(K.orbChance(info, cfg)),
		locked = nil, tokens = info.unique and (info.tokens or 0) > 0 and info.tokens or nil}
end

-- entries: list of info tables (in container order). Returns
--   {picked = {index...}, shards, orbs (expected, per 10000 summed), capped, skipped = {reason -> n}, count}
-- Items above maxRarity are skipped as "above"; anything K.check refuses is skipped under its reason.
-- Non-gear (potions, runes, bags, ...) is not counted at all: a backpack holds many things that are no candidates.
function K.batch(entries, maxRarity, cfg)
	maxRarity = clamp(floor(tonumber(maxRarity) or 0), 1, #cfg.baseShards)
	local out = {picked = {}, shards = 0, orbs = 0, capped = false, skipped = {}, count = 0, maxRarity = maxRarity}
	for i, info in ipairs(entries) do
		local why
		if info.riftKey or info.stackable or not info.gear or (info.rarity or 0) < 1 then
			why = "ignore"
		else
			why = K.check(info, cfg)
		end
		if not why and (info.rarity or 0) > maxRarity then
			why = "above"
		end
		if why == nil then
			if #out.picked >= cfg.batchCap then
				out.capped = true
				out.skipped.cap = (out.skipped.cap or 0) + 1
			else
				out.picked[#out.picked + 1] = i
				out.shards = out.shards + K.shards(info, cfg)
				out.orbs = out.orbs + K.orbChance(info, cfg)
			end
		elseif why ~= "ignore" then
			out.skipped[why] = (out.skipped[why] or 0) + 1
		end
	end
	out.count = #out.picked
	return out
end

-- a short hash of the picked items: list of strings (path .. ":" .. item signature), order kept
function K.signature(list)
	local h = 5381
	for _, s in ipairs(list) do
		s = tostring(s) .. "|"
		for j = 1, #s do
			h = (h * 33 + s:byte(j)) % 2147483647
		end
	end
	return string.format("%d:%d", #list, h)
end

function K.recipe(key, cfg)
	for _, r in ipairs(cfg.recipes) do
		if r.key == key then
			return r
		end
	end
	return nil
end

function K.combineCheck(owned, key, count, cfg)
	local r = K.recipe(key, cfg)
	if not r then
		return nil, "unknownRecipe"
	end
	count = floor(tonumber(count) or 0)
	if count < 1 or count > (cfg.maxCombine or 1) then
		return nil, "count"
	end
	local cost = r.cost * count
	if (tonumber(owned) or 0) < cost then
		return nil, "shards"
	end
	return true, cost
end

return K
