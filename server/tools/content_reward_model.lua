-- The content reward model (server/README.md "Content rewards"): what a waystone run and a rift pay per hour against
-- open-world hunting at the same level, and the bounds that keep both worth doing without breaking the economy.
--
--     cd server && luajit tools/content_reward_model.lua            the tables (also lua5.3)
--     cd server && luajit tools/content_reward_model.lua --check    exit 1 when a gain leaves content_rewards_config.lua `bounds`
--
-- Inputs, all in the repository: content_rewards_config.lua, loot_config.lua (the orbs of a hunt), the loot model
-- (tools/loot_model.lua: the stock gear of the hunting bands, their kills per hour), the rift and waystone configs
-- (monster tier shares, the tiers' levels). Expected values, no random numbers.
--
-- Assumptions (the model is computed, not measured in game):
--   * Hunting and both contents kill the same number of monsters per hour (the pack model's kills per hour at the
--     level), x EFFICIENCY of the content (walking in and out, the key / waystone handling).
--   * A rift or waystone monster is magic / rare / legendary as often as a hunted one (rift_config.lua `elite`).
--   * The contents pay ON TOP of the monsters' own loot, so the gain is (hunt + extra) / hunt. The gold of the contents is
--     not touched (the tool adds no coin or NPC-sold item), so the gold model of tools/loot_model.lua stays as it is.
--   * A waystone run takes RUN_MINUTES to clear and kill the boss; the boss table counts once per run.
-- A test can load it as a library: ChaosContentRewardsModelLib = true; local M = dofile("tools/content_reward_model.lua").

ChaosLootModelLib = true
local LM = dofile("tools/loot_model.lua")
ChaosLootModelLib = nil
dofile("data/scripts/chaos/content_rewards_core.lua")
local K = ChaosContentRewardsCore
local cfg = dofile("data/scripts/chaos/content_rewards_config.lua")
local lootCfg = dofile("data/scripts/chaos/loot_config.lua")
local riftCfg = dofile("data/scripts/chaos/rift_config.lua")
local wtCfg = dofile("data/scripts/chaos/waystone_tiers_config.lua")
local P = ChaosPaceCore

local M = {}
M.EFFICIENCY = {waystone = 0.85, rift = 0.80}
M.RUN_MINUTES = 12

-- the shares of a hunted / content monster by loot tier (rift_config.lua elite, no tier bonus)
function M.tierShares(riftTier)
	local e = riftCfg.elite
	local mult = 1 + e.perTier * (riftTier or 0)
	local shares, left = {}, 1
	for _, n in ipairs({"legendary", "rare", "magic"}) do
		local s = e[n] * mult / 100
		shares[n] = s
		left = left - s
	end
	shares.normal = left
	return shares
end

-- orbs per kill of a hunt at level >= currency.minMonsterLevel: the sum of the entries' chances by tier share
function M.huntOrbsPerKill(shares)
	local sum = 0
	for _, e in ipairs(lootCfg.currency.entries) do
		for tier, share in pairs(shares) do
			local count = e.count and (e.count[1] + e.count[2]) / 2 or 1
			sum = sum + share * (e.chance[tier] or 0) / 10000 * count
		end
	end
	return sum
end

-- Rare or better gear drops per hour of a hunting band (stock tables), solo, at the pack model's kills
function M.huntRareGear(ctx, band)
	local lo, hi = LM.RANGES[band][1], LM.RANGES[band][2]
	local w, kills, rare = 0, 0, 0
	for _, mon in ipairs(ctx.data) do
		if mon.level >= lo and mon.level <= hi then
			local k = LM.killsPerHour(ctx, mon)
			local _, n = LM.rules(ctx, mon)
			local per = 0
			for _, e in ipairs(mon.loot) do
				if e[4] == "gear" then
					per = per + e[2] / 100000 * ctx.rare * n.f.notable
				end
			end
			w = w + mon.spawns
			kills = kills + mon.spawns * k
			rare = rare + mon.spawns * k * per
		end
	end
	return rare / math.max(w, 1), kills / math.max(w, 1)
end

local function killsAt(ctx, level)
	return P.lin(ctx.kills.scaled, level, 800)
end

-- the shares of the loot tiers weighted into a per kill value
local function perKill(fn, shares)
	local sum = 0
	for tier, share in pairs(shares) do
		sum = sum + share * fn(tier)
	end
	return sum
end

-- one waystone tier: {level, hunt = rare gear / h, content = rare+ pieces / h (kills + bosses), gain}
function M.waystone(ctx, tier, quantity)
	local level = wtCfg.tiers[tier].level
	local band = 1000 -- the richest stock hunting band (the 1500 band's stock tables hold no gear: server/README.md "Loot by monster level")
	local hunt, huntKills = M.huntRareGear(ctx, band)
	local shares = M.tierShares(tier)
	local kills = killsAt(ctx, level) * M.EFFICIENCY.waystone
	local q = K.waystoneQuantity(cfg, tier) * (quantity or 1)
	local pieceKill = perKill(function(t) return K.expectedWaystoneKill(cfg, tier, t, q) end, shares)
	local boss = K.expectedWaystoneBoss(cfg, tier, q) * 60 / M.RUN_MINUTES
	local content = kills * pieceKill + boss
	return {tier = tier, level = level, band = band, hunt = hunt, content = content, gain = (hunt + content) / hunt,
		perKill = pieceKill, bossPerRun = K.expectedWaystoneBoss(cfg, tier, q)}
end

-- one rift tier: orbs per hour of the hunt and of the rift (its trickle and its guardian, one run of tier t in RIFT_MINUTES)
M.RIFT_MINUTES = 13
function M.rift(ctx, tier, quantity)
	local level = riftCfg.tiers[math.min(tier, #riftCfg.tiers)].minLevel + math.max(0, tier - #riftCfg.tiers) * riftCfg.beyond.minLevelStep
	local shares = M.tierShares(tier)
	local kills = P.lin(ctx.kills.scaled, math.max(level, 650), 800) * M.EFFICIENCY.rift
	if level < 650 then
		kills = P.lin(ctx.kills.base, level, 1200) * M.EFFICIENCY.rift
	end
	local huntKill = M.huntOrbsPerKill(shares)
	local q = quantity or 1
	local extra = perKill(function(t) return K.expectedRiftKill(cfg, tier, t, q) end, shares)
	local guardian = K.expectedRiftGuardian(cfg, tier, q) * 60 / M.RIFT_MINUTES
	local hunt = kills / M.EFFICIENCY.rift * huntKill
	local content = kills * extra + guardian
	return {tier = tier, level = level, hunt = hunt, content = content, gain = (hunt + content) / hunt, perKill = extra}
end

function M.load()
	local ctx = LM.load()
	return ctx
end

function M.report(ctx)
	local lines = {"| Waystone tier | Level | Hunt rare+ gear/h | Waystone pieces/h | Gain (no mods) | Gain (+60% quantity) | Boss pieces per run |",
		"|---|---|---|---|---|---|---|"}
	local ws, rf = {}, {}
	for t = 1, #wtCfg.tiers do
		local a, b = M.waystone(ctx, t, 1), M.waystone(ctx, t, 1.6)
		ws[t] = a
		lines[#lines + 1] = string.format("| %d | %d | %.1f | %.1f | x%.1f | x%.1f | %.1f |", t, a.level, a.hunt, a.content, a.gain,
			b.gain, a.bossPerRun)
	end
	lines[#lines + 1] = ""
	lines[#lines + 1] = "| Rift tier | Level | Hunt orbs/h | Rift orbs/h (trickle + guardian) | Gain (no mods) | Gain (+60% quantity) |"
	lines[#lines + 1] = "|---|---|---|---|---|---|"
	for t = 1, 15 do
		local a, b = M.rift(ctx, t, 1), M.rift(ctx, t, 1.6)
		rf[t] = a
		lines[#lines + 1] = string.format("| %d | %d | %.1f | %.1f | x%.1f | x%.1f |", t, a.level, a.hunt, a.content, a.gain, b.gain)
	end
	return table.concat(lines, "\n"), ws, rf
end

-- the bounds: every tier's no-modifier gain at least `min`; the best tier with modifiers (+60% quantity) at most `max`
function M.check(ctx)
	local b, bad = cfg.bounds, {}
	local function inBounds(name, rows, bound, fn)
		for _, r in ipairs(rows) do
			if r.gain < bound.min then
				bad[#bad + 1] = string.format("%s tier %d: gain x%.2f below %.1f", name, r.tier, r.gain, bound.min)
			end
		end
		for t = 1, #rows do
			local hi = fn(t)
			if hi.gain > bound.max then
				bad[#bad + 1] = string.format("%s tier %d with modifiers: gain x%.2f above %.1f", name, t, hi.gain, bound.max)
			end
		end
	end
	local _, ws, rf = M.report(ctx)
	inBounds("waystone gear", ws, b.waystoneGear, function(t) return M.waystone(ctx, t, 1.6) end)
	inBounds("rift orbs", rf, b.riftOrbs, function(t) return M.rift(ctx, t, 1.6) end)
	return bad
end

function M.main(args)
	local ctx = M.load()
	local text = M.report(ctx)
	print(text)
	if args[1] == "--check" then
		local bad = M.check(ctx)
		for _, l in ipairs(bad) do
			print(l)
		end
		print(#bad == 0 and "content reward model: every gain inside the bounds" or "content reward model: OUT OF BOUNDS")
		return #bad == 0 and 0 or 1
	end
	return 0
end

if ChaosContentRewardsModelLib then
	return M
end
os.exit(M.main(arg or {}))
