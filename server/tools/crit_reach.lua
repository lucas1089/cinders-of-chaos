-- crit_reach.lua: how much critical hit chance and damage a character can reach, from the real data (O146).
--
-- Beta feedback: "my crit (about 28%) from gear does not show in the tree window; reaching 70-80% is unviable even with T8
-- items on every slot". This tool computes the ceilings from the same tables the game rolls with:
--   * gear: the engine modifier "Critical Chance / Critical Hit" (data/lib/chaos_item_mods.lua config.engine.critical:
--     amount per tier; the chance is ChaosCrafting.specialChance(amount) = floor((2 x amount + 1) / 3)), one per item, on
--     any of the 8 equipment slots (head, necklace, armor, both hands, legs, boots, ring; the quiver cannot roll it),
--     scaled by item quality (Whetstone) up to config.quality.capHigh (30%) on Divine and better items
--   * gems: the most a character gets from all gems (chaos_gems_config.lua effects.crit.cap / cap2)
--   * the passive tree: the sum of the criticalHitChance / criticalHitAmount of every node the class may take (a ceiling:
--     a real path to all of them costs more points than a character owns), per class
--   * a Vocation Trial node (trials_nodes.lua, the best one) and the Keen Edge mastery
--   * Paragon: critical damage only (Paragon has no critical chance), 15% from the categories and the mastery on top
-- The numbers are ceilings and typical builds; the live total is what the engine rolls (statTotals in the tree window).
--
--   luajit tools/crit_reach.lua            print the table (run from server/)
--   luajit tools/crit_reach.lua --check    exit 1 when the model does not hold (the unit test runs the same checks)
-- Lua 5.1 / LuaJIT and Lua 5.3.

local R = {}

local function load()
	if not Chaos then
		dofile("data/scripts/chaos/chaos_constants.lua")
	end
	dofile("data/scripts/chaos/classes.lua") -- before the libraries below (they replace parts of Chaos)
	dofile("data/lib/chaos_item_mods.lua")
	dofile("data/lib/chaos_crafting.lua")
	return ChaosItemMods, ChaosCrafting, ChaosClasses, ChaosClassTree, dofile("data/scripts/chaos/passivetree_data.lua"),
		dofile("data/lib/chaos_gems_config.lua")
end

-- slots that can carry the engine critical modifier
R.SLOTS = {"head", "necklace", "armor", "left hand", "right hand", "legs", "boots", "ring"}
-- the best Vocation Trial node's critical chance (trials_nodes.lua: Focus Break 5; the others give 4) and the Keen Edge mastery
R.TRIAL_CHANCE, R.TRIAL_AMOUNT = 5, 30
R.KEEN_EDGE_CHANCE, R.KEEN_EDGE_AMOUNT = 2, 5

function R.compute()
	local M, C, Classes, ClassTree, tree, gems = load()
	local out = {}
	local tiers = M.config.engine.critical.tiers
	local top = tiers[M.config.maxTier]
	local lo, hi = C.specialChance(top[1]), C.specialChance(top[2])
	local q = M.config.quality.capHigh
	out.t8 = {amountLo = top[1], amountHi = top[2], chanceLo = lo, chanceHi = hi,
		chanceHiQuality = M.scaleQuality(hi, q), amountHiQuality = M.scaleQuality(top[2], q), qualityPercent = q,
		itemLevel = M.config.tierLevels[M.config.maxTier]}
	local t7 = tiers[M.config.maxTier - 1]
	out.t7 = {chanceLo = C.specialChance(t7[1]), chanceHi = C.specialChance(t7[2]), itemLevel = M.config.tierLevels[M.config.maxTier - 1]}
	out.slots = #R.SLOTS
	local n = out.slots
	out.gear = {
		min = n * lo, -- all eight slots T8, the lowest roll
		avg = n * ((lo + hi) / 2),
		max = n * hi, -- the highest roll everywhere
		maxQuality = n * out.t8.chanceHiQuality, -- the highest roll, every item at the quality cap
		amountMax = n * top[2], amountMaxQuality = n * out.t8.amountHiQuality
	}
	out.gems = {chance = gems.effects.crit.cap, amount = gems.effects.crit.cap2}
	-- the passive tree, per class: the sum of every crit node the class may take, with the class's variant stats
	out.tree = {}
	for v = 1, 25 do
		local cls = Classes.classKey(v)
		if cls and not out.tree[cls] then
			local chance, amount = 0, 0
			for id, node in pairs(tree.nodes) do
				if id ~= tree.root and ClassTree.allowed(node, cls) then
					local s = (node.v and node.v[cls]) or node.s or {}
					chance = chance + (s.criticalHitChance or 0)
					amount = amount + (s.criticalHitAmount or 0)
				end
			end
			out.tree[cls] = {chance = chance, amount = amount}
		end
	end
	local best, worst, median = 0, math.huge, {}
	for _, t in pairs(out.tree) do
		best, worst = math.max(best, t.chance), math.min(worst, t.chance)
		median[#median + 1] = t.chance
	end
	table.sort(median)
	out.treeBest, out.treeWorst, out.treeMedian = best, worst, median[math.ceil(#median / 2)]
	-- totals: a ceiling (everything at its best) and two builds
	local extra = R.TRIAL_CHANCE + R.KEEN_EDGE_CHANCE + out.gems.chance
	out.ceiling = out.gear.maxQuality + best + extra
	-- a dedicated build: crit on six of the eight slots at an average T8 roll, the tree's crit nodes along the way (the
	-- median class takes about 70% of its crit nodes with the path), the trial node, Keen Edge, gems at half
	out.dedicated = 6 * ((lo + hi) / 2) + out.treeMedian * 0.7 + R.TRIAL_CHANCE + R.KEEN_EDGE_CHANCE + out.gems.chance / 2
	-- a casual crit build: three slots
	out.casual = 3 * ((lo + hi) / 2) + out.treeMedian * 0.4
	-- a threshold a gated passive may ask: halfway between the casual and the dedicated build, rounded down to 5
	out.suggestedThreshold = 5 * math.floor((out.casual + out.dedicated) / 2 / 5)
	-- the same gear with T7 only (item level 136 drops, a level 1500 hunt: the tier window tops out at T7)
	out.gearT7 = {max = n * out.t7.chanceHi, avg = n * ((out.t7.chanceLo + out.t7.chanceHi) / 2)}
	-- crit damage ceiling
	out.amountCeiling = out.gear.amountMaxQuality + R.TRIAL_AMOUNT + R.KEEN_EDGE_AMOUNT + out.gems.amount
	return out
end

function R.report(o)
	local lines = {}
	local function add(...)
		lines[#lines + 1] = string.format(...)
	end
	add("Critical chance reach (O146)")
	add("  T8 modifier (item level %d+): amount %d-%d, chance %d-%d per item (%d at +%d%% quality)", o.t8.itemLevel,
		o.t8.amountLo, o.t8.amountHi, o.t8.chanceLo, o.t8.chanceHi, o.t8.chanceHiQuality, o.t8.qualityPercent)
	add("  gear, %d slots all T8: lowest roll %d, average %.0f, highest roll %d, highest roll + quality %d", o.slots, o.gear.min,
		o.gear.avg, o.gear.max, o.gear.maxQuality)
	add("  gear with T7 only (item level %d+, the best a level 1500 hunt drops without bonuses): chance %d-%d per item, %d slots: "
		.. "average %.0f, highest %d", o.t7.itemLevel, o.t7.chanceLo, o.t7.chanceHi, o.slots, o.gearT7.avg, o.gearT7.max)
	add("  gems: at most %d chance, %d damage", o.gems.chance, o.gems.amount)
	add("  tree (every crit node of the class): best %d, median %d, worst %d", o.treeBest, o.treeMedian, o.treeWorst)
	add("  ceiling (everything at its best) %.0f; dedicated build %.0f; casual build %.0f", o.ceiling, o.dedicated, o.casual)
	add("  suggested threshold for a passive that needs critical chance: %d%%", o.suggestedThreshold)
	add("  critical damage ceiling from gear, gems, trial, mastery: %d (+ Paragon 15 + mastery)", o.amountCeiling)
	return table.concat(lines, "\n")
end

if arg and arg[0] and arg[0]:find("crit_reach", 1, true) then
	local o = R.compute()
	print(R.report(o))
	if arg[1] == "--check" then
		local ok = o.gear.max == 56 and o.ceiling > o.dedicated and o.dedicated > o.casual
		os.exit(ok and 0 or 1)
	end
end

return R
