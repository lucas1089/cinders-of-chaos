-- Skill training model (O150): skill tries and levels per hour from hunting, exercise weapons and offline training for every
-- vocation, the hours a skill takes, and the value of an exercise weapon hour in hunting hours. Computed from the
-- repository's configs and the engine formulas, not measured in game. docs/PRICES.md "Skill training (O150)" has the tables.
--     cd server && luajit tools/skill_model.lua [--check|--sensitivity]      (also lua5.3)
-- Inputs: chaos_vocations*.xml (skill and mana multipliers, attack speed, mana gain), exercise_config.lua / exercise_core.lua
-- (charges, tries per step), skill_model_config.lua (rates, stage multipliers, hunting assumptions, limits). The price bound
-- on the store's exercise weapons is in tools/store_model.lua (M.exerciseProblems is here, store_model.lua calls it).
local M = {}

local function readAll(path)
	local f = assert(io.open(path, "rb"))
	local s = f:read("*a")
	f:close()
	return s
end

-- vocations of the XML files: [id] = {id, name, line, attackMs, manaMult, manaAmount, manaTicks, skill = {fist, melee, distance, shield}}
function M.vocations(lines)
	local out = {}
	local files = {"chaos_vocations.xml", "chaos_vocations_monk.xml", "chaos_vocations_necro.xml", "chaos_vocations_templar.xml"}
	for _, file in ipairs(files) do
		local text = readAll("data/XML/" .. file)
		for attrs, body in text:gmatch("<vocation ([^>]-)>(.-)</vocation>") do
			local a = {}
			for k, v in attrs:gmatch('([%w_]+)="([^"]*)"') do a[k] = v end
			local id = tonumber(a.id)
			local sk = {}
			for sid, mult in body:gmatch('<skill id="(%d+)" multiplier="([%d%.]+)"') do sk[tonumber(sid)] = tonumber(mult) end
			local line
			for name, ids in pairs(lines) do
				for _, v in ipairs(ids) do if v == id then line = name end end
			end
			if line then
				out[id] = {id = id, name = a.name, line = line, attackMs = tonumber(a.attackspeed), manaMult = tonumber(a.manamultiplier),
					manaAmount = tonumber(a.gainmanaamount), manaTicks = tonumber(a.gainmanaticks),
					skill = {fist = sk[0], melee = sk[2], distance = sk[4], shield = sk[5]}}
			end
		end
	end
	return out
end

-- the stage rows with the O154 speed-up: every multiplier from `from` up times `factor` (data/scripts/chaos/skill_stages_config.lua,
-- which tools/patch_skill_stages.py applies to the base server's skills_stages.lua); a row that spans from - 1 and from is split
function M.applyFactor(rows, from, factor)
	local out = {}
	for _, r in ipairs(rows) do
		local a, b, m = r[1], r[2], r[3]
		if b ~= nil and b < from then
			out[#out + 1] = {a, b, m}
		elseif a >= from then
			out[#out + 1] = {a, b, m * factor}
		else
			out[#out + 1] = {a, from - 1, m}
			out[#out + 1] = {from, b, m * factor}
		end
	end
	return out
end

function M.load()
	local env = {}
	env.cfg = dofile("data/scripts/chaos/skill_model_config.lua")
	env.stages = dofile("data/scripts/chaos/skill_stages_config.lua")
	-- cfg.stockStages: the base server's rows as downloaded; cfg.stages: what the install leaves (patch_skill_stages.py)
	env.cfg.stockStages = env.cfg.stages
	env.cfg.stages = {
		skill = M.applyFactor(env.cfg.stockStages.skill, env.stages.fromLevel, env.stages.factor),
		magic = M.applyFactor(env.cfg.stockStages.magic, env.stages.fromLevel, env.stages.factor)
	}
	env.exercise = dofile("data/scripts/chaos/exercise_config.lua")
	dofile("data/scripts/chaos/exercise_core.lua")
	env.E = ChaosExercise
	env.vocs = M.vocations(env.exercise.lines)
	env.order = {}
	for id in pairs(env.vocs) do env.order[#env.order + 1] = id end
	table.sort(env.order)
	return env
end

-- ---------------------------------------------------------------- the engine's formulas
-- the stage multiplier of a trained level
function M.stageMult(rows, level)
	for _, r in ipairs(rows) do
		if level >= r[1] and (r[2] == nil or level <= r[2]) then return r[3] end
	end
	return 1
end

-- tries (mana for the magic level) to go from `level` to level + 1
function M.need(env, voc, skill, level)
	local c = env.cfg
	if skill == "magic" then return c.magicBase * voc.manaMult ^ level end
	return c.skillBase[skill] * voc.skill[skill] ^ (level - c.minSkill)
end

local function stagesOf(env, skill) return skill == "magic" and env.cfg.stages.magic or env.cfg.stages.skill end

-- tries an hour of hunting brings at a trained level (nil: this class has no hunting figure for the skill)
function M.hunting(env, voc, skill, level)
	local c, h = env.cfg, env.cfg.hunting
	local mult = M.stageMult(stagesOf(env, skill), level)
	if skill == "magic" then
		local mpm = h.manaPerMinute[voc.line]
		if not mpm then return nil end
		return mpm * 60 * h.castShare * c.rates.magic * mult
	end
	if skill == "shield" then return nil end
	return 3600000 / voc.attackMs * h.attackShare * c.rates.skill * mult
end

local KIND_OF = {melee = "melee", fist = "melee", distance = "ranged", magic = "rod"}

-- tries an hour on a dummy brings (kind: the exercise weapon kind; gear: skill from equipment, which picks the stage rate
-- of the weapon; house: the 10% dummy)
function M.exercise(env, kind, skill, level, gear, house)
	local c, ex = env.cfg, env.exercise
	local rate = skill == "magic" and c.rates.magic or c.rates.skill
	local perStep = env.E.step(kind, level + (gear or 0), rate, house)
	return 3600000 / ex.tickMs * perStep * M.stageMult(stagesOf(env, skill), level)
end

-- tries an hour of offline training brings (the base script, then the rate and the stage)
function M.offline(env, voc, skill, level)
	local c, o = env.cfg, env.cfg.offline
	local mult = M.stageMult(stagesOf(env, skill), level)
	if skill == "magic" then
		return 3600 * voc.manaAmount / (voc.manaTicks * 2) * c.rates.magic * mult
	end
	if skill == "shield" then return nil end
	local div = skill == "distance" and o.distanceDivisor or o.meleeDivisor
	return 3600 / (voc.attackMs / 1000) / div * c.rates.skill * mult
end

-- hours to go from level a to level b at tries(level) an hour
function M.hours(env, voc, skill, a, b, tries)
	local h = 0
	for L = a, b - 1 do
		local t = tries(L)
		if not t or t <= 0 then return math.huge end
		h = h + M.need(env, voc, skill, L) / t
	end
	return h
end

-- the value of one dummy hour in hunting hours at a trained level: tries of the dummy / tries of the hunt
function M.ratio(env, voc, skill, level, gear, house)
	local hunt = M.hunting(env, voc, skill, level)
	if not hunt then return nil end
	return M.exercise(env, KIND_OF[skill], skill, level, gear, house) / hunt
end

-- ---------------------------------------------------------------- exercise weapon prices
-- the skill an exercise weapon kind trains for a class line ("melee", "fist", "distance", "magic"), nil for the shield
function M.kindSkill(env, kind, line)
	local def = env.exercise.kinds[kind]
	if not def then return nil end
	local skill = (def.skillBy and def.skillBy[line]) or def.skill
	if skill == "shield" then return nil end
	return skill
end

local function kindOfName(name)
	if name:find("Melee", 1, true) then return "melee" end
	if name:find("Fist", 1, true) then return "fist" end
	if name:find("Bow", 1, true) then return "ranged" end
	if name:find("Rod", 1, true) then return "rod" end
	if name:find("Wand", 1, true) then return "wand" end
	if name:find("Shield", 1, true) then return "shield" end
end

-- one row per Training offer: {offer, kind, charges, hours, perHour = min/max coins per hunting hour, per charge}
function M.exerciseRows(env, offers)
	local rows = {}
	local ref = env.cfg.reference.skills
	for _, o in ipairs(offers) do
		local charges = tonumber((o.name or ""):match("%((%d+)%)"))
		local kind = kindOfName(o.name or "")
		if charges and kind then
			local hours = charges * env.exercise.tickMs / 3600000
			local row = {offer = o, kind = kind, charges = charges, hours = hours, cost = o.cost, perCharge = o.cost / charges,
				lo = math.huge, hi = 0, cells = {}}
			for _, id in ipairs(env.order) do
				local voc = env.vocs[id]
				local skill = M.kindSkill(env, kind, voc.line)
				local allowed = false
				for _, l in ipairs(env.exercise.kinds[kind].lines) do if l == voc.line then allowed = true end end
				if allowed and skill and id == env.exercise.lines[voc.line][1] then -- the base vocation of the line
					for _, L in ipairs(ref) do
						local r = M.ratio(env, voc, skill, L)
						if r then
							local cph = o.cost / (hours * r)
							row.cells[#row.cells + 1] = {voc = voc, skill = skill, level = L, ratio = r, perHour = cph}
							row.lo, row.hi = math.min(row.lo, cph), math.max(row.hi, cph)
						end
					end
				end
			end
			rows[#rows + 1] = row
		end
	end
	return rows
end

-- problems of the exercise weapon prices. premiumPerHour: coins per hour of benefit of Premium (30 days / 30);
-- xpPerHour: coins per hour of the Double Experience Potion
function M.exerciseProblems(env, offers, premiumPerHour, xpPerHour)
	local lim, out = env.cfg.limits, {}
	local rows = M.exerciseRows(env, offers)
	local lo, hi = premiumPerHour * lim.minFractionOfPremium, xpPerHour
	if #rows == 0 then out[#out + 1] = "no exercise weapon offers found" end
	local byKind = {}
	for _, r in ipairs(rows) do
		if r.lo < lo then
			out[#out + 1] = string.format("%s: %.1f coins per hunting hour saved (%s, skill %d), under %.1f (%.0f%% of Premium's %.1f)",
				r.offer.name, r.lo, "", env.cfg.reference.skills[1], lo, lim.minFractionOfPremium * 100, premiumPerHour)
		end
		if r.hi > hi then
			out[#out + 1] = string.format("%s: %.1f coins per hunting hour saved, over the Double Experience Potion's %.1f", r.offer.name, r.hi, hi)
		end
		byKind[r.kind] = byKind[r.kind] or {}
		byKind[r.kind][#byKind[r.kind] + 1] = r
	end
	for kind, list in pairs(byKind) do
		table.sort(list, function(a, b) return a.charges < b.charges end)
		local first, last = list[1], list[#list]
		if #list > 1 and first.perCharge > 0 then
			local disc = 100 * (1 - last.perCharge / first.perCharge)
			if disc > lim.maxTierDiscountPct then
				out[#out + 1] = string.format("exercise %s: the %d tier is %.0f%% cheaper per charge than the %d tier (limit %d%%)", kind, last.charges, disc, first.charges, lim.maxTierDiscountPct)
			end
			for i = 2, #list do
				if list[i].perCharge > list[i - 1].perCharge + 1e-9 then
					out[#out + 1] = string.format("exercise %s: %d charges cost more per charge than %d", kind, list[i].charges, list[i - 1].charges)
				end
			end
		end
	end
	return out
end

-- ---------------------------------------------------------------- problems (--check)
function M.problems(env)
	local out = {}
	local function bad(fmt, ...) out[#out + 1] = string.format(fmt, ...) end
	for _, e in ipairs(env.E.validate()) do bad("exercise config: %s", e) end
	local n = 0
	for _ in pairs(env.vocs) do n = n + 1 end
	if n ~= 21 then bad("%d vocations read from the XML files (expected 21)", n) end
	for _, name in ipairs({"skill", "magic"}) do
		local rows = env.cfg.stages[name]
		for L = 1, 3000 do
			if M.stageMult(rows, L) < 1 then bad("stage table %s: level %d has no multiplier", name, L) end
		end
	end
	for _, id in ipairs(env.order) do
		local v = env.vocs[id]
		for _, sk in ipairs({"fist", "melee", "distance", "shield"}) do
			if not v.skill[sk] or v.skill[sk] < 1 then bad("%s: bad %s multiplier", v.name, sk) end
		end
		if not v.attackMs or not v.manaMult or not v.manaAmount or not v.manaTicks then bad("%s: attributes missing", v.name) end
		-- a level never costs less than the one before
		for _, sk in ipairs({"fist", "melee", "distance", "magic"}) do
			if M.need(env, v, sk, 101) < M.need(env, v, sk, 100) then bad("%s: %s tries fall with the level", v.name, sk) end
		end
	end
	-- an exercise hour is worth more than a hunting hour at the reference skills (else the weapon is useless there)
	for _, line in ipairs({"warrior", "ranger", "mystic", "thief", "monk", "necromancer", "templar"}) do
		local skill = env.cfg.main[line]
		local voc = env.vocs[env.exercise.lines[line][1]]
		for _, L in ipairs(env.cfg.reference.skills) do
			local r = M.ratio(env, voc, skill, L)
			if r and r <= 1 then bad("%s %s at %d: a dummy hour is worth %.2f hunting hours", line, skill, L, r) end
		end
	end
	return out
end

-- ---------------------------------------------------------------- the tables
local function fmt(x)
	if x == math.huge then return "inf" end
	if x >= 100 then return string.format("%.0f", x) end
	if x >= 10 then return string.format("%.1f", x) end
	return string.format("%.2f", x)
end

function M.report(env)
	local c = env.cfg
	local function line(...) print(string.format(...)) end
	local lv = c.reference.table
	local head = {}
	for _, L in ipairs(lv) do head[#head + 1] = tostring(L) end

	print(string.format("Stage multipliers: the base server's x%s from level %d up (skill_stages_config.lua, patch_skill_stages.py)\n",
		tostring(env.stages.factor), env.stages.fromLevel))
	print("Hunting hours for one skill level, by trained level (main skill of each vocation)")
	print("| Vocation | Skill | " .. table.concat(head, " | ") .. " | Hours 100 -> 130 |")
	print("|---|---|" .. string.rep("---|", #lv + 1))
	for _, id in ipairs(env.order) do
		local v = env.vocs[id]
		local skill = c.main[v.line]
		local cells = {}
		for _, L in ipairs(lv) do
			local t = M.hunting(env, v, skill, L)
			cells[#cells + 1] = t and fmt(M.need(env, v, skill, L) / t) or "-"
		end
		local h = M.hours(env, v, skill, 100, 130, function(L) return M.hunting(env, v, skill, L) end)
		line("| %s | %s | %s | %s |", v.name, skill, table.concat(cells, " | "), fmt(h))
	end

	print("\nSkill levels gained in one hour at trained level 100 / 130 (base vocation of each line)")
	print("| Line | Skill | Hunting | Dummy | House dummy | Offline | Dummy hour in hunting hours |")
	print("|---|---|---|---|---|---|---|")
	for _, name in ipairs({"warrior", "ranger", "mystic", "thief", "monk", "necromancer", "templar"}) do
		local v = env.vocs[env.exercise.lines[name][1]]
		local skill = c.main[name]
		local cells = {{}, {}, {}, {}, {}}
		for _, L in ipairs(c.reference.skills) do
			local need = M.need(env, v, skill, L)
			local hunt = M.hunting(env, v, skill, L)
			local ex = M.exercise(env, KIND_OF[skill], skill, L)
			local exh = M.exercise(env, KIND_OF[skill], skill, L, 0, true)
			local off = M.offline(env, v, skill, L)
			cells[1][#cells[1] + 1] = fmt(hunt / need)
			cells[2][#cells[2] + 1] = fmt(ex / need)
			cells[3][#cells[3] + 1] = fmt(exh / need)
			cells[4][#cells[4] + 1] = fmt(off / need)
			cells[5][#cells[5] + 1] = fmt(ex / hunt)
		end
		line("| %s | %s | %s | %s | %s | %s | %s |", v.name, skill, table.concat(cells[1], " / "), table.concat(cells[2], " / "),
			table.concat(cells[3], " / "), table.concat(cells[4], " / "), table.concat(cells[5], " / "))
	end

	print(string.format("\nMain skill after %d hours of hunting (leveling 8 to 1000), by line (base vocation)", c.levelingHours))
	print("| Line | Skill | Now | Stock stages |")
	print("|---|---|---|---|")
	local stock = {skill = env.cfg.stages.skill, magic = env.cfg.stages.magic}
	for _, name in ipairs({"warrior", "ranger", "mystic", "thief", "monk", "necromancer", "templar"}) do
		local v = env.vocs[env.exercise.lines[name][1]]
		local skill = c.main[name]
		local now = M.reached(env, v, skill, c.levelingHours)
		env.cfg.stages = c.stockStages
		local was = M.reached(env, v, skill, c.levelingHours)
		env.cfg.stages = stock
		line("| %s | %s | %d | %d |", v.name, skill, now, was)
	end

	print("\nHours (Warrior melee, Mystic magic level) to reach a trained level from 10 (0 for magic), hunting / offline days at 12 h / dummy hours")
	print("| Class | To level | Hunting hours | Offline training days | Dummy hours |")
	print("|---|---|---|---|---|")
	for _, pair in ipairs({{4, "melee", {80, 100, 115, 130, 140}}, {1, "magic", {60, 80, 100, 120, 130}}}) do
		local v = env.vocs[pair[1]]
		local skill = pair[2]
		local from = skill == "magic" and 0 or c.minSkill
		for _, to in ipairs(pair[3]) do
			local hh = M.hours(env, v, skill, from, to, function(L) return M.hunting(env, v, skill, L) end)
			local oh = M.hours(env, v, skill, from, to, function(L) return M.offline(env, v, skill, L) end)
			local eh = M.hours(env, v, skill, from, to, function(L) return M.exercise(env, KIND_OF[skill], skill, L) end)
			line("| %s %s | %d | %s | %s | %s |", v.name, skill, to, fmt(hh), fmt(oh / c.offline.poolHours), fmt(eh))
		end
	end
end

-- the main skill a character has when it reaches the level where it has hunted `hours` hours (from 10, magic level from 0)
function M.reached(env, voc, skill, hours)
	local from = skill == "magic" and 0 or env.cfg.minSkill
	local h, L = 0, from
	while true do
		local t = M.hunting(env, voc, skill, L)
		if not t then return nil end
		h = h + M.need(env, voc, skill, L) / t
		if h > hours then return L end
		L = L + 1
	end
end

function M.sensitivity(env)
	local base = env.cfg.hunting.attackShare
	local cs = env.cfg.hunting.castShare
	print("Dummy hour in hunting hours (Warrior melee / Mystic magic) at trained level 100 and 130, by hunting assumption")
	print("| attackShare | castShare | Warrior 100 | Warrior 130 | Mystic 100 | Mystic 130 |")
	print("|---|---|---|---|---|---|")
	for _, a in ipairs({0.5, 0.7, 0.9}) do
		env.cfg.hunting.attackShare, env.cfg.hunting.castShare = a, a - 0.2
		local w, m = env.vocs[4], env.vocs[1]
		print(string.format("| %.1f | %.1f | %s | %s | %s | %s |", a, a - 0.2, fmt(M.ratio(env, w, "melee", 100)), fmt(M.ratio(env, w, "melee", 130)),
			fmt(M.ratio(env, m, "magic", 100)), fmt(M.ratio(env, m, "magic", 130))))
	end
	env.cfg.hunting.attackShare, env.cfg.hunting.castShare = base, cs
end

function M.main(args)
	local env = M.load()
	if args[1] == "--check" then
		local problems = M.problems(env)
		for _, p in ipairs(problems) do print("skill model: " .. p) end
		if #problems > 0 then return 1 end
		print(string.format("skill model: consistent (%d vocations)", #env.order))
		return 0
	elseif args[1] == "--sensitivity" then
		M.sensitivity(env)
		return 0
	end
	M.report(env)
	return 0
end

if ChaosSkillModelLib then
	return M
end
os.exit(M.main(arg or {}))
