-- The chase pity model (O753; server/README.md "Chase pity (O753)"): the base chance p of the chase drop of every source of
-- chase_pity_config.lua, computed from the configs that roll it, and the n of the guarantee against it.
--
--     cd server && luajit tools/chase_pity_model.lua           the table (also lua5.3)
--     cd server && luajit tools/chase_pity_model.lua --check   exit 1 when a source's p drifts from the config or its n moves
--                                                              the mean chase by more than maxShift (tests/chase_pity_test.lua
--                                                              runs the same check in the server loop)
--
-- p per source (the lowest it can be, so the shift a real character sees is at most the one printed: a higher p makes the
-- guarantee matter less):
--   rift      a sealed rift or Greater Rift chest: one set piece chase roll, chaos_item_sets_config.lua chase.rift.base per
--             10000 at the set's own tier (more above it, up to max)
--   waystone  a waystone map boss at tier I (waystone_tiers_config.lua tiers[1].level): content_rewards_config.lua
--             waystone.boss.uniqueRolls at tier I, each over the open uniques (loot_config.lua unique.open, minMonsterLevel up
--             to the level) at the boss multiplier x uniqueFind x open.mult; the uniques that list the boss come on top
--   guardian  a rift's guardian (its corpse, content_rewards.lua riftKill) at the config's refTier / refLevel: rift.guardian
--             uniqueRolls (a fraction is a chance of one more) over the same open uniques x its uniqueFind
--   pocket    a world boss in a pocket: Chaos.worldBoss.reward.uniqueChance x pocketboss_config.lua world lootMult per 10000
--   fragment  a pinnacle fragment clear: the own kind chance of pinnacle_config.lua fragments.sources (the keystone apart)
-- Item find 1 everywhere (the character's item find and the Conquest pity raise every p alike).

local args = {}
for _, a in ipairs(arg or {}) do
	args[a] = true
end

local function load(path)
	local f = assert(loadfile(path))
	return f()
end

local M = {}

-- the open uniques of a level: {chance per 10000 before the tier multiplier}
function M.openChances(list, level)
	local out = {}
	for _, e in ipairs(list) do
		if e.minMonsterLevel and not e.bossOnly and not e.ascended and not e.season and level >= e.minMonsterLevel then
			out[#out + 1] = tonumber(e.chance) or 0
		end
	end
	return out
end

-- one roll at the boss tier over the open uniques: the chance that one drops
function M.rollP(chances, tierMult, find, openMult, maxChance)
	local miss = 1
	for _, c in ipairs(chances) do
		local x = math.min(maxChance, c * tierMult * find * openMult) / 10000
		miss = miss * (1 - math.min(1, x))
	end
	return 1 - miss
end

-- r rolls, a fraction is a chance of one more
function M.rollsP(pRoll, r)
	local whole = math.floor(r)
	local frac = r - whole
	local miss = (1 - pRoll) ^ whole * (1 - frac * pRoll)
	return 1 - miss
end

function M.numbers()
	if not ChaosUniqueSpecs then
		ChaosUniqueSpecs = {}
	end
	local realDofile = dofile
	dofile = function(p)
		if tostring(p):find("chaos_effect_compat", 1, true) or tostring(p):find("chaos_unique_specs", 1, true) then
			return
		end
		return realDofile(p)
	end
	if not ChaosUniqueItems then
		realDofile("data/lib/chaos_unique_items.lua")
	end
	dofile = realDofile
	local loot = load("data/scripts/chaos/loot_config.lua")
	local cr = load("data/scripts/chaos/content_rewards_config.lua")
	local wt = load("data/scripts/chaos/waystone_tiers_config.lua")
	local sets = load("data/lib/chaos_item_sets_config.lua")
	local pin = load("data/scripts/chaos/pinnacle_config.lua")
	local pocket = load("data/scripts/chaos/pocketboss_config.lua")
	local cfg = load("data/scripts/chaos/chase_pity_config.lua")
	local u = loot.unique
	local bossMult = u.tierMult.boss
	local openMult = u.open.mult
	local maxC = u.maxChance
	local out = {cfg = cfg, p = {}}

	out.p.rift = sets.chase.rift.base / 10000

	local wLevel = wt.tiers[1].level
	local wb = cr.waystone.boss
	local wp = M.rollP(M.openChances(ChaosUniqueItems, wLevel), bossMult, wb.uniqueFind, openMult, maxC)
	out.p.waystone = M.rollsP(wp, wb.uniqueRolls.base)

	local g = cr.rift.guardian
	local gsrc
	for _, s in ipairs(cfg.sources) do
		if s.key == "guardian" then
			gsrc = s
		end
	end
	local gp = M.rollP(M.openChances(ChaosUniqueItems, gsrc.refLevel), bossMult, g.uniqueFind, openMult, maxC)
	out.p.guardian = M.rollsP(gp, g.uniqueRolls.base + g.uniqueRolls.perTier * gsrc.refTier)

	-- Chaos.worldBoss.reward.uniqueChance is in chaos_constants.lua (read from its text: the file needs the engine)
	local f = assert(io.open("data/scripts/chaos/chaos_constants.lua", "r"))
	local text = f:read("*a")
	f:close()
	local wbChance = tonumber(text:match("uniqueChance = (%d+), %-%- per 10000: one of the boss%-only uniques"))
	out.p.pocket = wbChance * pocket.categories.world.lootMult / 10000

	out.p.fragment = pin.fragments.sources.waystone.chance / 100
	out.pinnacle = {p = pin.unique.chance / 100, n = pin.unique.pity}
	return out
end

function M.check(K, quiet)
	local N = M.numbers()
	local cfg = N.cfg
	local errors, lines = {}, {}
	lines[#lines + 1] = "| Source | p (model) | p (config) | n | ramp | mean before | mean after | shift | smallest n |"
	lines[#lines + 1] = "|---|---|---|---|---|---|---|---|---|"
	for _, key in ipairs(cfg.order) do
		local s = K.source(cfg, key)
		local p = N.p[key]
		if not s then
			errors[#errors + 1] = key .. ": no source row"
		elseif not p then
			errors[#errors + 1] = key .. ": the model has no p"
		else
			if math.abs(p - s.p) > 0.02 * p + 1e-9 then
				errors[#errors + 1] = string.format("%s: config p %.5f, the model says %.5f", key, s.p, p)
			end
			local shift = K.shift(p, s.n, s.ramp)
			local need = K.deriveN(p, s.ramp, cfg.maxShift)
			if shift > cfg.maxShift + 1e-9 then
				errors[#errors + 1] = string.format("%s: n %d moves the mean chase by %.1f%%, the limit is %.0f%%", key, s.n,
					shift * 100, cfg.maxShift * 100)
			end
			if need and s.n > need * 1.25 + 1 then
				errors[#errors + 1] = string.format("%s: n %d is far above the smallest n %d that holds the limit", key, s.n, need)
			end
			lines[#lines + 1] = string.format("| %s | %.4f | %.4f | %d | %.2f | %.1f | %.1f | %.1f%% | %s |", key, p, s.p, s.n,
				s.ramp, 1 / p, K.meanEvents(p, s.n, s.ramp), shift * 100, tostring(need))
		end
	end
	local pn = N.pinnacle
	lines[#lines + 1] = string.format("| pinnacle (existing, per boss) | %.4f | %.4f | %d | 0.00 | %.1f | %.1f | %.1f%% | - |", pn.p,
		pn.p, pn.n, 1 / pn.p, K.meanEvents(pn.p, pn.n, 0), K.shift(pn.p, pn.n, 0) * 100)
	if not quiet then
		print(table.concat(lines, "\n"))
	end
	return errors, N
end

if arg and arg[0] and tostring(arg[0]):find("chase_pity_model", 1, true) then
	dofile("data/scripts/chaos/chase_pity_core.lua")
	local errors = M.check(ChaosChasePityCore, false)
	if args["--check"] then
		for _, e in ipairs(errors) do
			print("FAIL " .. e)
		end
		if #errors > 0 then
			os.exit(1)
		end
		print("chase pity: ok")
	end
end

return M
