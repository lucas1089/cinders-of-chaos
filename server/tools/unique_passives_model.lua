-- Expected power gain of the unique item passives (O278; server/README.md "Unique passives").
-- usage (from server/): luajit tools/unique_passives_model.lua [--check] [--list]
--   no flag   the table: per class line and level band the average gain of one passive and of the best five together
--   --list    every passive with its gain on each line it works for
--   --check   fails when a passive is weaker than model.minGain or stronger than model.maxGain on a line it works for,
--             or the best five of a line in a band are outside bestFiveMin..bestFiveMax (limits: unique_passives_config.lua)
-- The gain is damage dealt x survivability (1 = no change) in a typical hunt. The assumptions below are the model's, not
-- measurements: every one is a number to change when a measurement says otherwise.
dofile("data/scripts/chaos/unique_passives_config.lua")
dofile("data/scripts/chaos/unique_passives_text.lua")
dofile("data/scripts/chaos/unique_passives_core.lua")
local C, CFG = ChaosUniquePassivesCore, ChaosUniquePassivesConfig

local A = {
	killsPerSec = 0.4, hitsPerSec = 1.2, critChance = 0.2, nearbyMonsters = 3, healShare = 0.25,
	hurtPerSec = 0.6, -- hard hits taken per second
	lowLifeTime = 0.12, highLifeTime = 0.45, fullManaTime = 0.45, emptyManaTime = 0.15,
	hitAbove90 = 0.35, hitBelow25 = 0.15, hitBelow30 = 0.2,
	chain = 8, -- hits in a row on one target
	spreadKills = 0.4, spreadTargets = 2.2, dotTickShare = 0.04, -- a tick of yours: 4% of a monster
	dotShare = 0.12, spikeShare = 0.12, healWeight = 8,
	-- the share of a class line's damage by origin
	origin = {
		warrior = {melee = 0.85, ranged = 0, spell = 0.15}, ranger = {melee = 0, ranged = 0.9, spell = 0.1},
		mystic = {melee = 0, ranged = 0, spell = 1}, thief = {melee = 0.6, ranged = 0.3, spell = 0.1},
		monk = {melee = 0.7, ranged = 0, spell = 0.3}, necromancer = {melee = 0, ranged = 0, spell = 1},
		templar = {melee = 0.5, ranged = 0, spell = 0.5},
	},
	physical = {warrior = 0.9, ranger = 0.9, mystic = 0.1, thief = 0.9, monk = 0.9, necromancer = 0.1, templar = 0.6},
	stat = function(stat, level)
		return ({maxMana = level * 8, maxHealth = level * 15, magicLevel = level * 0.5, speed = 220 + level * 2,
			shield = level * 0.5, level = level})[stat] or 0
	end,
}

-- the item's own critical chance (percent) from its spec: a crit rule item brings crit chance of its own
for i, n in ipairs({"ATTACK", "DEFENSE", "EXTRADEFENSE", "ARMOR", "HITCHANCE", "SHOOTRANGE"}) do
	_G["ITEM_ATTRIBUTE_" .. n] = i
end
dofile("data/lib/chaos_unique_specs.lua")
local function ownCrit(id)
	local sp = ChaosUniqueSpecs[id]
	return sp and sp.custom and sp.custom.rarity_criticalHitChance or 0
end

local function clamp(x, lo, hi)
	return math.max(lo, math.min(hi, x))
end

-- (dealt multiplier, survive multiplier) of one passive for a class line at a level
local function gain(e, line, level)
	local o = A.origin[line]
	local crit = A.critChance + ownCrit(e.id) / 100
	local f = e.family
	local d, s = 1, 1
	if f == "convert" then
		local pf = A.physical[line]
		d = 1 + pf * e.share / 100 * e.bonus / 100 - (1 - pf) * e.other / 100 * 0.5
	elseif f == "lowlife" then
		d = 1 + A.lowLifeTime * e.bonus / 100 - A.highLifeTime * e.malus / 100
	elseif f == "overflow" then
		d = 1 + A.fullManaTime * e.bonus / 100 - A.emptyManaTime * e.malus / 100
	elseif f == "opener" then
		local up = e.side == "above" and A.hitAbove90 or 0.3
		local down = e.side == "above" and A.hitBelow25 or 0.35
		d = 1 + up * e.bonus / 100 - down * e.malus / 100
	elseif f == "focus" then
		local sum = 0
		for i = 1, A.chain do
			sum = sum + (i == 1 and (1 - e.first / 100) or (1 + math.min(e.max, i - 1) * e.perStack / 100))
		end
		d = sum / A.chain
	elseif f == "statscale" then
		local share = e.origin == "any" and 1 or (o[e.origin] or 0)
		local pct = math.min(e.cap, math.floor(math.max(0, A.stat(e.stat, level) - e.from) / e.per) * e.bonusPer)
		d = 1 + share * pct / 100
	elseif f == "critrule" then
		d = 1 + crit * e.crit / 100 - (1 - crit) * e.plain / 100
		s = 1 + A.hitsPerSec * crit * (e.heal / 100) * 0.3 * A.healWeight / 10
	elseif f == "crowd" then
		if e.mode == "pack" then
			d = 1 + 0.8 * math.min(e.max, A.nearbyMonsters) * e.per / 100 - 0.2 * e.alone / 100
		else
			d = 1 + 0.25 * e.bonus / 100 - 0.35 * e.malus / 100
		end
	elseif f == "extra" then
		local share = e.origin == "any" and 1 or (o[e.origin] or 0)
		local frac = math.min(1, 1000 / e.icdMs)
		d = 1 + share * frac * e.pct / 100 * math.min(e.targets, 1.3) * 0.7 - e.costPct * frac * 0.003
	elseif f == "ward" then
		s = 1 + 2 * math.min(e.cap / 100, e.onHit / 100 * 0.6 + e.onKill / 100 * A.killsPerSec * 3)
		s = s * (1 - e.healLess / 100 * A.healShare)
		s = s * (1 + e.reflect / 100 * 0.02)
	elseif f == "spread" then
		d = 1 + A.spreadKills * math.min(e.targets, A.spreadTargets) * A.dotTickShare * e.share / 100 * e.ticks
		d = d * (1 - e.dealtLess / 100 * 0.8)
	elseif f == "stacks" then
		local rate = e.trigger == "kill" and A.killsPerSec or A.hitsPerSec * crit
		local avg = math.min(e.max, e.windowMs / 1000 * rate)
		d = 1 + avg * e.perStack / 100
		s = 1 / (1 + avg * e.takenPerStack / 100)
	elseif f == "feast" then
		local perSec = math.min(e.capPerSec, A.killsPerSec * e.onKill)
		s = (e.res == "health" and 1 + perSec / 100 * A.healWeight or 1 + perSec / 100 * 2) * (1 - e.healLess / 100 * A.healShare)
	elseif f == "hitcap" then
		s = (1 + math.max(0, 50 - e.cap) / 100 * 0.45) * (1 - e.healLess / 100 * A.healShare)
	elseif f == "immunity" then
		s = 1 + A.dotShare - e.more / 100 * A.dotShare * 1.3
	elseif f == "riposte" then
		local perSec = math.min(1000 / e.icdMs, A.hurtPerSec)
		local dmg = math.min(e.pct / 100 * 0.9 * level, e.capBase + e.capPerLevel * level)
		d = 1 + perSec * dmg * 1.3 / (level * 4)
	elseif f == "panic" then
		s = 1 + (e.reduce / 100) * (e.ms / e.icdMs) * 6 - (e.ms / e.icdMs) * 1.5 * A.healShare
	elseif f == "manashield" then
		s = 1 + e.share / 100 * 0.8
		d = 1 - e.dealtLess / 100 * 0.8
	elseif f == "mend" then
		local perSec = e.heal / (e.tickMs / 1000)
		s = (1 + math.min(CFG.mendMaxPct, perSec) / 100 * A.healWeight * 1.4) * (1 - e.healLess / 100 * A.healShare)
	elseif f == "mark" then
		local frac = math.min(1, e.max / 2.5)
		d = 1 + frac * e.bonus / 100 - (1 - frac) * e.unmarked / 100
	elseif f == "nova" then
		local rate = e.on == "kill" and A.killsPerSec or (e.on == "crit" and A.hitsPerSec * crit or A.hurtPerSec)
		local ev = math.min(1000 / e.icdMs, rate)
		local dmg = e.base + e.perLevel * level
		d = 1 + ev * dmg * math.min(e.targets, A.nearbyMonsters) / (level * 4) - e.selfCost * ev * 0.003
	elseif f == "minionPact" then
		d = 0.55 * (1 + e.hit / 100) + 0.45 * (1 - e.own / 100)
		s = 1 + 0.55 * e.health / 100 * 0.3
	end
	if e.takenMore then
		s = s / (1 + e.takenMore / 100)
	end
	return d, s
end

local function totalGain(e, line, level)
	local d, s = gain(e, line, level)
	return d * s
end

local mode = arg and arg[1]

local ids = {}
for id in pairs(CFG.passives) do
	if id < 900000 then
		ids[#ids + 1] = id
	end
end
table.sort(ids, function(a, b)
	local x, y = CFG.passives[a], CFG.passives[b]
	if x.lv ~= y.lv then
		return x.lv < y.lv
	end
	return a < b
end)

-- --tune: the knobs that bring a passive into the target range; prints "id key value" lines (a maintenance aid: the
-- numbers go into the entry of unique_passives_config.lua by hand or with the script that applies them)
local KNOB = {
	convert = {"bonus", 1, 80}, critrule = {"crit", 1, 100}, crowd = {"per", 1, 12}, extra = {"pct", 1, 90},
	feast = {"onKill", 1, 8}, focus = {"perStack", 1, 12}, hitcap = {"cap", -1, 15}, immunity = {"more", -1, 0},
	lowlife = {"bonus", 1, 100}, manashield = {"share", 1, 50}, mark = {"bonus", 1, 60}, mend = {"heal", 1, 3},
	minionPact = {"hit", 1, 70}, nova = {"base", 1, 500}, opener = {"bonus", 1, 120}, overflow = {"bonus", 1, 80},
	panic = {"reduce", 1, 60}, riposte = {"pct", 1, 130}, spread = {"share", 1, 100}, stacks = {"perStack", 1, 12},
	statscale = {"bonusPer", 1, 3}, ward = {"onHit", 1, 15},
}
local function range(e)
	local lo, hi = 9, 0
	for _, line in ipairs(CFG.lineOrder) do
		if C.worksFor(CFG, e, line) then
			local g = totalGain(e, line, math.max(e.lv, 20))
			lo, hi = math.min(lo, g), math.max(hi, g)
		end
	end
	return lo, hi
end
if mode == "--tune" then
	local LOW, HIGH = 1.08, 1.45
	for _, id in ipairs(ids) do
		local raw = CFG.passives[id]
		local e = C.entry(CFG, id)
		local k = KNOB[e.family]
		if e.family == "crowd" and e.mode == "duel" then
			k = {"bonus", 1, 70}
		end
		local lo, hi = range(e)
		if k and (lo < LOW or hi > HIGH) then
			local key, dir, limit = k[1], k[2], k[3]
			local steps = 0
			local up = lo < LOW and hi <= HIGH
			while steps < 60 do
				local v = e[key]
				local nv
				if (up and dir > 0) or (not up and dir < 0) then
					nv = v * 1.1 + (v < 10 and 0.1 or 0)
				else
					nv = v / 1.1 - (v < 10 and 0.1 or 0)
				end
				nv = nv >= 10 and math.floor(nv + 0.5) or math.floor(nv * 10 + 0.5) / 10
				if nv == v or (dir > 0 and up and nv > limit) or (dir > 0 and not up and nv < 1) or (dir < 0 and up and nv < limit) then
					break
				end
				e[key] = nv
				lo, hi = range(e)
				steps = steps + 1
				if up and lo >= LOW or (not up and hi <= HIGH) then
					break
				end
				if up and hi > HIGH then
					break
				end
			end
			local relief
			while up and lo < LOW and (e.healLess or 0) > 10 do
				e.healLess = e.healLess - 5
				relief = e.healLess
				lo, hi = range(e)
			end
			if raw[key] ~= e[key] then
				print(id, key, e[key], string.format("%.2f-%.2f", lo, hi))
			end
			if relief then
				print(id, "healLess", relief, string.format("%.2f-%.2f", lo, hi))
			end
		end
	end
	os.exit(0)
end
local errors = {}
local function problem(m)
	errors[#errors + 1] = m
end

if mode == "--list" then
	for _, id in ipairs(ids) do
		local e = C.entry(CFG, id)
		local row = {}
		for _, line in ipairs(CFG.lineOrder) do
			if C.worksFor(CFG, e, line) then
				row[#row + 1] = string.format("%s %.2f", line:sub(1, 3), totalGain(e, line, e.lv))
			end
		end
		print(string.format("%-6d lv%-5d %-9s %-26s %s", id, e.lv, e.family, e.name, table.concat(row, "  ")))
	end
end

-- per passive, on the lines it works for (judged at the level it can be worn at)
for _, id in ipairs(ids) do
	local e = C.entry(CFG, id)
	for _, line in ipairs(CFG.lineOrder) do
		if C.worksFor(CFG, e, line) then
			local g = totalGain(e, line, math.max(e.lv, 20))
			if g < CFG.model.minGain or g > CFG.model.maxGain then
				problem(string.format("%d %s (%s, %s): gain %.3f outside %.2f-%.2f", id, e.name, e.family, line, g,
					CFG.model.minGain, CFG.model.maxGain))
			end
		end
	end
end

-- per line and band: the average passive and the best five (one per family) together
print(string.format("%-12s %-12s %5s %9s %9s", "class line", "level band", "n", "average", "best five"))
for _, line in ipairs(CFG.lineOrder) do
	for _, band in ipairs(CFG.model.bands) do
		local list = {}
		for _, id in ipairs(ids) do
			local e = C.entry(CFG, id)
			if e.lv >= band[1] and e.lv <= band[2] and C.worksFor(CFG, e, line) then
				local d, sv = gain(e, line, math.max(e.lv, 20))
				list[#list + 1] = {e = e, g = d * sv, d = d, s = sv}
			end
		end
		table.sort(list, function(a, b) return a.g > b.g end)
		local sum, bestD, bestS, fam, used = 0, 1, 1, {}, 0
		for _, r in ipairs(list) do
			sum = sum + r.g
			if used < CFG.maxActive and not fam[r.e.family] then
				fam[r.e.family] = true
				used = used + 1
				bestD, bestS = bestD * r.d, bestS * r.s
			end
		end
		-- the engine's clamps: damage dealt in [dealtFloor, dealtCap], damage taken in [takenFloor, takenCeil]
		local best = clamp(bestD, CFG.dealtFloor, CFG.dealtCap) * clamp(bestS, 1 / CFG.takenCeil, 1 / CFG.takenFloor)
		local avg = #list > 0 and sum / #list or 1
		print(string.format("%-12s %-12s %5d %9.3f %9.3f", line, band[1] .. "-" .. band[2], #list, avg, best))
		if #list < 3 then
			problem(line .. " " .. band[1] .. "-" .. band[2] .. ": only " .. #list .. " passives")
		elseif best < CFG.model.bestFiveMin or best > CFG.model.bestFiveMax then
			problem(string.format("%s %d-%d: best five %.3f outside %.2f-%.2f", line, band[1], band[2], best,
				CFG.model.bestFiveMin, CFG.model.bestFiveMax))
		end
	end
end

if mode == "--check" then
	if #errors > 0 then
		for _, m in ipairs(errors) do
			print("FAIL " .. m)
		end
		os.exit(1)
	end
	print("unique passives model: ok")
end
