-- smartloot_core.lua: the pure rules of smart loot (smartloot_config.lua; server/README.md "Smart loot"). No engine
-- calls: smartloot.lua hands in the item rules (from movements.xml and weapons.xml, the Gambler's parser), the kind of
-- an item and a random source. Tests: server/tests/smartloot_test.lua. Lua 5.1 / LuaJIT and Lua 5.3 compatible.
--
--   rule    {level = n, vocs = {["lower-case vocation name"] = true} | nil (every class)} or nil (no rule: anyone)
--   wearer  {voc = "lower-case vocation name", level = n}

ChaosSmartLootCore = ChaosSmartLootCore or {}
local S = ChaosSmartLootCore

local floor = math.floor

-- true when this wearer may wear an item with this rule
function S.usableBy(rule, wearer, checkLevel)
	if not rule then
		return true
	end
	if checkLevel and (tonumber(rule.level) or 0) > (tonumber(wearer.level) or 0) then
		return false
	end
	return rule.vocs == nil or rule.vocs[wearer.voc] == true
end

-- true when any of the wearers may wear it
function S.usableByAny(rule, wearers, checkLevel)
	for _, w in ipairs(wearers or {}) do
		if S.usableBy(rule, w, checkLevel) then
			return true
		end
	end
	return false
end

-- the class weight of an item for the wearers: an item made for one of their classes (its rule names the class)
-- weighs w.classSpecific, an item they can wear w.usable, else w.unusable
function S.classWeight(rule, wearers, w, checkLevel)
	w = w or {}
	if rule and rule.vocs then
		for _, x in ipairs(wearers or {}) do
			if rule.vocs[x.voc] and S.usableBy(rule, x, checkLevel) then
				return tonumber(w.classSpecific) or 1
			end
		end
	end
	if S.usableByAny(rule, wearers, checkLevel) then
		return tonumber(w.usable) or 1
	end
	return tonumber(w.unusable) or 1
end

-- a copy of the loot table with the gear chances reweighted by S.classWeight and scaled so that their sum stays the
-- same (non-gear rows unchanged). ctx = {isGear, ruleOf, wearers, cfg}
function S.reweight(lootTable, ctx)
	local cfg = ctx.cfg or {}
	local w = cfg.weights or {}
	local sumBefore, sumAfter, weights = 0, 0, {}
	for i, e in ipairs(lootTable or {}) do
		local id, c = tonumber(e.itemId), tonumber(e.chance) or 0
		if id and c > 0 and ctx.isGear(id) then
			local k = S.classWeight(ctx.ruleOf(id), ctx.wearers, w, cfg.checkLevel)
			weights[i] = k
			sumBefore = sumBefore + c
			sumAfter = sumAfter + c * k
		end
	end
	local out = {}
	local scale = sumAfter > 0 and sumBefore / sumAfter or 1
	local maxChance = tonumber(cfg.maxChance) or 100000
	for i, e in ipairs(lootTable or {}) do
		if weights[i] then
			local row = {}
			for k, v in pairs(e) do
				row[k] = v
			end
			row.chance = math.min(maxChance, floor(e.chance * weights[i] * scale + 0.5))
			out[i] = row
		else
			out[i] = e
		end
	end
	return out
end

-- the gear entries of a loot table someone of the wearers can wear: list of {id, weight, kind}, one per id (the
-- weights of an id that is listed twice add up). lootTable = MonsterType:getLoot() style rows {itemId, chance}.
function S.candidates(lootTable, ctx)
	local out, at = {}, {}
	for _, entry in ipairs(lootTable or {}) do
		local id = tonumber(entry.itemId)
		local weight = floor(tonumber(entry.chance) or 0)
		if id and weight > 0 and ctx.isGear(id) and S.usableByAny(ctx.ruleOf(id), ctx.wearers, ctx.checkLevel) then
			local row = at[id]
			if not row then
				row = {id = id, weight = 0, kind = ctx.kindOf(id)}
				at[id] = row
				out[#out + 1] = row
			end
			-- the class weight (an item made for one of the wearers' classes first)
			row.weight = row.weight + weight * math.max(1, floor(S.classWeight(ctx.ruleOf(id), ctx.wearers,
				ctx.weights, ctx.checkLevel)))
		end
	end
	return out
end

-- one candidate by weight, of `kind` first (any kind when there is none and anySlot is on); nil when none fits.
-- rnd(a, b) -> integer in [a, b]
function S.pick(cands, kind, rnd, anySlot, exceptId)
	local function draw(filter)
		local total = 0
		for _, c in ipairs(cands) do
			if c.id ~= exceptId and filter(c) then
				total = total + c.weight
			end
		end
		if total <= 0 then
			return nil
		end
		local roll, acc = rnd(1, total), 0
		for _, c in ipairs(cands) do
			if c.id ~= exceptId and filter(c) then
				acc = acc + c.weight
				if roll <= acc then
					return c
				end
			end
		end
		return nil
	end
	local c = kind and draw(function(x) return x.kind == kind end)
	if not c and anySlot then
		c = draw(function() return true end)
	end
	return c
end

-- the swaps of one corpse. items = list of item ids as they lie in the corpse (top level). ctx = {lootTable, wearers,
-- isGear(id), ruleOf(id), kindOf(id), rnd(a, b), cfg}. Returns a list of {index, from, to}.
function S.plan(items, ctx)
	local cfg = ctx.cfg or {}
	local swaps = {}
	if cfg.enabled == false or #(ctx.wearers or {}) == 0 then
		return swaps
	end
	local chance = tonumber(cfg.swapChance) or 0
	local maxSwaps = floor(tonumber(cfg.maxSwapsPerCorpse) or 0)
	if chance <= 0 or maxSwaps <= 0 then
		return swaps
	end
	local cands
	for i, id in ipairs(items or {}) do
		if #swaps >= maxSwaps then
			break
		end
		if ctx.isGear(id) and not S.usableByAny(ctx.ruleOf(id), ctx.wearers, cfg.checkLevel) then
			cands = cands or S.candidates(ctx.lootTable, {isGear = ctx.isGear, ruleOf = ctx.ruleOf, kindOf = ctx.kindOf,
				wearers = ctx.wearers, checkLevel = cfg.checkLevel, weights = cfg.weights})
			if #cands == 0 then
				break
			end
			if ctx.rnd(1, 100) <= chance then
				local c = S.pick(cands, ctx.kindOf(id), ctx.rnd, cfg.anySlotFallback, id)
				if c then
					swaps[#swaps + 1] = {index = i, from = id, to = c.id}
				end
			end
		end
	end
	return swaps
end

return S
