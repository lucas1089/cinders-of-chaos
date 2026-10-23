-- Content rewards, engine side (content_rewards_core.lua, content_rewards_config.lua; server/README.md "Content
-- rewards"): what a waystone run and a rift pay on top of the monsters' own loot.
--   * loot.lua calls ChaosContentRewards.onKill(monster, corpse, owner, ctx, L) after its extra rolls, before the gear
--     quality step, so the gear pieces it adds get their rarity floor, item level, sockets and modifiers like any drop.
--   * waystone_mods.lua reads ChaosContentRewards.waystoneQuantity / waystoneRarityFind (the run tier's own bonus).
-- Waystone run: gear pieces (Rare or better) on a share of the kills, the boss table, waystones that keep the loop going.
-- Rift: a crafting orb trickle on every kill and a burst from the guardian. Summons pay nothing.
ChaosContentRewardsCore = ChaosContentRewardsCore or dofile("data/scripts/chaos/content_rewards_core.lua")
ChaosContentRewards = ChaosContentRewards or {}
local CR = ChaosContentRewards
local K = ChaosContentRewardsCore
CR.config = CR.config or dofile("data/scripts/chaos/content_rewards_config.lua")

local function cfg()
	return CR.config
end

local function rand(a, b)
	return math.random(a, b)
end

local function enabled()
	return cfg().enabled ~= false
end

-- the run tier (1-15) of a waystone map monster, nil outside the maps or for a summon
local function waystoneTier(monster)
	local WT = ChaosWaystoneTiers
	if not (WT and WT.entryOf) then
		return nil
	end
	local e = WT.entryOf(monster)
	if not e or not e.run then
		return nil
	end
	return e.run, e.boss, e
end
CR.waystoneTier = waystoneTier

-- waystone_mods.lua: the run tier's own bonus, only for a monster of a map whose run is on
function CR.waystoneQuantity(monster)
	if not enabled() then
		return 1
	end
	local t = waystoneTier(monster)
	return t and K.waystoneQuantity(cfg(), t) or 1
end

function CR.waystoneRarityFind(monster)
	if not enabled() then
		return 0
	end
	local t = waystoneTier(monster)
	return t and K.waystoneRarityFind(cfg(), t) or 0
end

local function gearPieces()
	local G = ChaosGearSets
	return G and G.items and G.items.pieces or {}
end

-- one gear piece into the corpse at a rarity from rows; returns its name or nil
local function addPiece(L, corpse, runLevel, rows, divineExtra, say)
	local piece = K.pickPiece(cfg(), gearPieces(), runLevel, rand)
	if not piece then
		return nil
	end
	local item = (L.addToCorpse(corpse, piece.id, 1))
	if not item then
		return nil
	end
	item:setCustomAttribute("rarity", K.pickRarity(rows, rand, divineExtra))
	return piece.name
end

local function addOrbs(L, corpse, orbs, bonus)
	for _, o in ipairs(orbs) do
		local item, added = L.addToCorpse(corpse, o.id, o.count)
		if item then
			bonus[#bonus + 1] = (added > 1 and (added .. "x ") or "") .. o.name
		end
	end
end

local function addUniques(L, corpse, owner, monster, rolls, find, level, bonus, ctx)
	for _ = 1, rolls do
		for _, e in ipairs(L.rollUniques("boss", monster:getName(), level,
				(ctx.itemFind or 1) * find, nil, owner)) do
			local item = (L.addToCorpse(corpse, e.id, 1))
			if item then
				if ChaosMakeUnique then
					ChaosMakeUnique(item)
				end
				bonus[#bonus + 1] = "{" .. e.name .. "}"
			end
		end
	end
end

local function waystoneKill(monster, corpse, owner, ctx, L, bonus)
	local t, isBoss = waystoneTier(monster)
	if not t then
		return false
	end
	local W = ChaosWaystoneTiers
	local run = W.config.tiers[t]
	local runLevel = run and run.level or 1100
	local quantity = ChaosWaystoneMods and ChaosWaystoneMods.lootMult and ChaosWaystoneMods.lootMult(ctx) or 1
	local c = cfg().waystone
	if isBoss then
		local plan = K.waystoneBoss(cfg(), t, quantity, rand)
		local divine = (c.rarityPerTier.divine or 0) * (t - 1)
		for _ = 1, plan.pieces do
			local name = addPiece(L, corpse, runLevel, c.boss.rarity, divine)
			if name then
				bonus[#bonus + 1] = "{" .. name .. "}"
			end
		end
		addOrbs(L, corpse, plan.orbs, bonus)
		addUniques(L, corpse, owner, monster, plan.uniqueRolls, c.boss.uniqueFind, ctx.orbLevel or runLevel, bonus, ctx)
		if W.addWaystone then
			for _ = 1, plan.waystones do
				W.addWaystone(corpse, t, monster, true)
			end
		end
		return true
	end
	local plan = K.waystoneKill(cfg(), t, ctx.tier, quantity, rand)
	if plan.piece then
		local name = addPiece(L, corpse, runLevel, c.rarity, (c.rarityPerTier.divine or 0) * (t - 1))
		if name then
			bonus[#bonus + 1] = name
		end
	end
	if plan.waystone and W.addWaystone then
		W.addWaystone(corpse, t, monster, true)
	end
	return true
end

local function riftKill(monster, corpse, owner, ctx, L, bonus)
	local R = ChaosRift
	local info = R and R.contentOf and R.contentOf(monster, owner)
	if not info or info.omen then
		return false
	end
	if info.guardian then
		local plan = K.riftGuardian(cfg(), info.tier, info.quantity, rand)
		addOrbs(L, corpse, plan.orbs, bonus)
		addUniques(L, corpse, owner, monster, plan.uniqueRolls, cfg().rift.guardian.uniqueFind, ctx.orbLevel or 0, bonus, ctx)
		return true
	end
	local orb = K.riftKill(cfg(), info.tier, ctx.tier, info.quantity, rand)
	if orb then
		local item = (L.addToCorpse(corpse, orb.id, 1))
		if item then
			bonus[#bonus + 1] = orb.name
		end
	end
	return true
end

-- loot.lua processKill: bonus gets the text pieces of the loot line. Returns true when a content paid
function CR.onKill(monster, corpse, owner, ctx, L, bonus)
	if not enabled() or not monster or not corpse or monster:getMaster() then
		return false
	end
	local ok, res = pcall(function()
		return waystoneKill(monster, corpse, owner, ctx, L, bonus) or riftKill(monster, corpse, owner, ctx, L, bonus)
	end)
	if not ok then
		print("[Chaos content rewards] " .. tostring(res))
		return false
	end
	return res
end
