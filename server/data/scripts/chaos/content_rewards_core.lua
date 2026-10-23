-- Content rewards, pure logic (no engine calls; tests/content_rewards_test.lua, tools/content_reward_model.lua).
-- The numbers are content_rewards_config.lua; the engine side is content_rewards.lua. Every function takes the config
-- and a rand(a, b) (math.random's shape). Lua 5.1 / LuaJIT and 5.3.
--
--   CR.waystoneGearChance(cfg, tier, tierName, quantity)   per 10000 of a gear piece on a kill in a waystone run
--   CR.waystoneRarityFind(cfg, tier) / CR.waystoneQuantity(cfg, tier)   the run tier's own bonus (percent / multiplier)
--   CR.waystoneKill(cfg, tier, tierName, quantity, rand)   {piece = bool, waystone = bool}
--   CR.waystoneBoss(cfg, tier, quantity, rand)             {pieces, uniqueRolls, waystones, orbs = {{id, name, count}}}
--   CR.riftOrbChance(cfg, tier, tierName, quantity)        per 10000 of an orb on a kill in a rift
--   CR.riftKill(cfg, tier, tierName, quantity, rand)       nil or {id, name}
--   CR.riftGuardian(cfg, tier, quantity, rand)             {orbs = {{id, name, count}}, uniqueRolls}
--   CR.pickPiece(cfg, pieces, level, rand)                 a set piece (row of chaos_gear_sets_items.lua) near the level
--   CR.pickRarity(rows, rand, divineExtra)                 a stored rarity id
--   CR.expected(...)                                       expected values per kill / per boss (the model tool)
ChaosContentRewardsCore = ChaosContentRewardsCore or {}
local CR = ChaosContentRewardsCore
local floor, min, max = math.floor, math.min, math.max

local function lin(row, steps)
	return (row.base or 0) + (row.perTier or 0) * steps
end

-- n whole + the fraction as the chance of one more
local function count(x, rand)
	local n = floor(x)
	if x - n > 0 and rand(1, 10000) <= (x - n) * 10000 then
		n = n + 1
	end
	return n
end
CR.count = count

local function tierMult(cfg, tierName)
	return cfg.tierMult[tierName or "normal"] or 1
end

local function clampTier(t)
	return max(1, floor(tonumber(t) or 1))
end

-- ===================================================================== waystones
function CR.waystoneGearChance(cfg, tier, tierName, quantity)
	local w = cfg.waystone
	local c = lin(w.gear, clampTier(tier) - 1) * tierMult(cfg, tierName) * (quantity or 1)
	return min(w.gear.maxChance, max(0, c))
end

function CR.waystoneRarityFind(cfg, tier)
	return lin(cfg.waystone.rarityFind, clampTier(tier) - 1)
end

function CR.waystoneQuantity(cfg, tier)
	return 1 + lin(cfg.waystone.quantity, clampTier(tier) - 1) / 100
end

-- rows {{id, weight}}: a stored rarity id. divineExtra adds weight to the Divine row (id 10)
function CR.pickRarity(rows, rand, divineExtra)
	local total = 0
	for _, r in ipairs(rows) do
		total = total + r[2] + (r[1] == 10 and (divineExtra or 0) or 0)
	end
	local at = rand(1, floor(total * 100)) / 100
	local acc = 0
	for _, r in ipairs(rows) do
		acc = acc + r[2] + (r[1] == 10 and (divineExtra or 0) or 0)
		if at <= acc then
			return r[1]
		end
	end
	return rows[#rows][1]
end

-- pieces: ChaosGearSets.items.pieces rows {id, set, level, ...}. A piece of cfg.waystone.sets whose level is in
-- [floorShare x level, level]; none: the pieces of the sets at the highest level. nil when the sets hold nothing.
function CR.pickPiece(cfg, pieces, level, rand)
	local w = cfg.waystone
	local sets = {}
	for _, s in ipairs(w.sets) do
		sets[s] = true
	end
	local pool, best, top = {}, {}, 0
	for _, p in ipairs(pieces or {}) do
		if sets[p.set] then
			if p.level <= level and p.level >= level * w.floorShare then
				pool[#pool + 1] = p
			end
			if p.level > top then
				top, best = p.level, {p}
			elseif p.level == top then
				best[#best + 1] = p
			end
		end
	end
	if #pool == 0 then
		pool = best
	end
	return #pool > 0 and pool[rand(1, #pool)] or nil
end

function CR.waystoneKill(cfg, tier, tierName, quantity, rand)
	local w = cfg.waystone
	local out = {piece = false, waystone = false}
	if rand(1, 10000) <= CR.waystoneGearChance(cfg, tier, tierName, quantity) then
		out.piece = true
	end
	if rand(1, 10000) <= w.trickle.chance * tierMult(cfg, tierName) then
		out.waystone = true
	end
	return out
end

function CR.waystoneBoss(cfg, tier, quantity, rand)
	local b = cfg.waystone.boss
	local steps = clampTier(tier) - 1
	local out = {pieces = count(lin(b.pieces, steps) * (quantity or 1), rand),
		uniqueRolls = count(lin(b.uniqueRolls, steps), rand), waystones = b.waystones.same, orbs = {}}
	for _, o in ipairs(b.orbs) do
		if rand(1, 100) <= o.chance then
			out.orbs[#out.orbs + 1] = {id = o.id, name = o.name, count = rand(o.min, o.max)}
		end
	end
	return out
end

-- ===================================================================== rifts
function CR.riftOrbChance(cfg, tier, tierName, quantity)
	local r = cfg.rift
	return min(r.orb.maxChance, max(0, lin(r.orb, clampTier(tier)) * tierMult(cfg, tierName) * (quantity or 1)))
end

local function pickOrb(cfg, rand)
	local total = 0
	for _, o in ipairs(cfg.rift.orbs) do
		total = total + o.weight
	end
	local at = rand(1, total)
	local acc = 0
	for _, o in ipairs(cfg.rift.orbs) do
		acc = acc + o.weight
		if at <= acc then
			return o
		end
	end
	return cfg.rift.orbs[#cfg.rift.orbs]
end

function CR.riftKill(cfg, tier, tierName, quantity, rand)
	if rand(1, 10000) <= CR.riftOrbChance(cfg, tier, tierName, quantity) then
		local o = pickOrb(cfg, rand)
		return {id = o.id, name = o.name}
	end
	return nil
end

-- the burst: orbs by id merged
function CR.riftGuardian(cfg, tier, quantity, rand)
	local g = cfg.rift.guardian
	tier = clampTier(tier)
	local n = count(lin(g.orbs, tier) * (quantity or 1), rand)
	local merged, order = {}, {}
	for _ = 1, n do
		local o = pickOrb(cfg, rand)
		if not merged[o.id] then
			merged[o.id] = {id = o.id, name = o.name, count = 0}
			order[#order + 1] = merged[o.id]
		end
		merged[o.id].count = merged[o.id].count + 1
	end
	return {orbs = order, uniqueRolls = count(lin(g.uniqueRolls, tier), rand)}
end

-- ===================================================================== expected values (the model tool)
-- per kill of a monster of tierName in a run of `tier` with `quantity`: gear pieces, rare+ pieces (all of them), waystones
function CR.expectedWaystoneKill(cfg, tier, tierName, quantity)
	return CR.waystoneGearChance(cfg, tier, tierName, quantity) / 10000,
		cfg.waystone.trickle.chance * tierMult(cfg, tierName) / 10000
end

-- per boss kill: pieces (the quantity-scaled mean), and the pieces of the table in all
function CR.expectedWaystoneBoss(cfg, tier, quantity)
	return lin(cfg.waystone.boss.pieces, clampTier(tier) - 1) * (quantity or 1)
end

function CR.expectedRiftKill(cfg, tier, tierName, quantity)
	return CR.riftOrbChance(cfg, tier, tierName, quantity) / 10000
end

function CR.expectedRiftGuardian(cfg, tier, quantity)
	return lin(cfg.rift.guardian.orbs, clampTier(tier)) * (quantity or 1)
end

return CR
