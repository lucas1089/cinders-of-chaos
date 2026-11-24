-- Spell Forms (O686 phase 4): pure logic, no engine call. Design: docs/SPELL_UPGRADES.md sections 2 and 5.2; numbers below (the
-- standard of each kind, a forms.csv row may override a key); engine: spell_forms.lua; the read API every state shares:
-- data/lib/chaos_spell_forms.lua; tests: server/tests/spell_forms_test.lua; model: server/tools/spell_upgrade_model.py (the Form band).
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.
--
--   A Form changes HOW a spell plays, not how strong it is. A Form acts on the hits of one cast: plan(spec, cast) returns what to
--   change on the cast's hits (`factors`, by target id) and the extra things to do (`actions`). The engine runs the actions as hits of
--   the spell under the supports' proc guard; the model counts them (`up` is the modelled uptime of an action, 1 when absent).
--   Forms with extra targets act on the MAIN hit (the biggest hit of the cast); the kinds that replay or mark the whole cast
--   (ECHO, TWIN, DELAY, OVERCHARGE, GROUND, PULL, AFTERMATH, REND, the conversions) act on every hit of it.

ChaosSpellFormsCore = ChaosSpellFormsCore or {}
local F = ChaosSpellFormsCore

local floor, min, max, abs = math.floor, math.min, math.max, math.abs

local function num(v, default)
	v = tonumber(v)
	if not v or v ~= v then
		return default
	end
	return v
end

-- ---------------------------------------------------------------- kinds (design 2.2)
-- Form I damage, Form II damage, Form I heal, Form II heal. SHIFT / ASCEND carry an element: "SHIFT:ice", "ASCEND:weakest".
F.kinds1 = {"SPLIT", "CHAIN", "PIERCE", "REND", "DELAY", "PULL", "GROUND", "ECHO", "SHIFT"}
F.kinds2 = {"TWIN", "CASCADE", "AFTERMATH", "OVERCHARGE", "SIPHON", "SEEK", "SPREAD", "ASCEND"}
F.heal1 = {"RIPPLE", "BLOOM", "WARD", "PULSE"}
F.heal2 = {"SECONDWIND", "LINK", "SANCTUARY", "CLEANSE"}
F.elements = {"physical", "fire", "ice", "energy", "earth", "holy", "death"}
-- the elements ASCEND:weakest may pick, in the order a tie is broken
F.weakestOrder = {"fire", "ice", "energy", "earth", "holy", "death"}

local function setOf(list)
	local s = {}
	for _, k in ipairs(list) do
		s[k] = true
	end
	return s
end
F.set1, F.set2, F.setHeal1, F.setHeal2 = setOf(F.kinds1), setOf(F.kinds2), setOf(F.heal1), setOf(F.heal2)
F.setElements = setOf(F.elements)

-- "SHIFT:ice" -> "SHIFT", "ice"; "SPLIT" -> "SPLIT", nil
function F.parseKind(text)
	text = tostring(text or "")
	local base, el = text:match("^(%u+):(%a+)$")
	if base then
		return base, el
	end
	return text, nil
end

-- is `text` a legal kind for a tier (1 or 2) of a damage or a heal spell
function F.validKind(text, tier, heal)
	local base, el = F.parseKind(text)
	local set
	if heal then
		set = tier == 1 and F.setHeal1 or F.setHeal2
	else
		set = tier == 1 and F.set1 or F.set2
	end
	if not set[base] then
		return false, "unknown kind"
	end
	if base == "SHIFT" or base == "ASCEND" then
		if not el then
			return false, "needs an element"
		end
		if el == "weakest" then
			return base == "ASCEND", "weakest is for ASCEND"
		end
		return F.setElements[el] == true, "unknown element"
	end
	if el then
		return false, "takes no element"
	end
	return true
end

-- ---------------------------------------------------------------- the standard numbers
-- percent of the hit (of the heal for the heal kinds) unless the key says ms / count / radius / ticks. Phase 4 moved the first
-- design's numbers (docs/SPELL_UPGRADES.md 2.2 "Phase 4") so that every kind sits inside the band of 2.1 on one target and on five:
-- the model reads these through plan() and the real planner, never a copy.
F.numbers = {
	-- Form I, damage
	SPLIT = {count = 3, pct = 35, radius = 3},
	CHAIN = {main = 95, pct1 = 7, pct2 = 5, radius = 3},
	PIERCE = {main = 100, pct = 3, count = 2, range = 1},
	REND = {main = 70, dot = 40, ticks = 4, every = 1000, up = 85},
	DELAY = {ms = 1500, pct = 110, area = 150, up = 95},
	PULL = {main = 95, pullTo = 1, radius = 3},
	GROUND = {pct = 3, seconds = 4, radius = 1, up = 50},
	ECHO = {main = 85, pct = 22, ms = 1000, up = 90},
	SHIFT = {pct = 4, ticks = 3, every = 1000, up = 85},
	-- Form II, damage
	TWIN = {main = 75, pct = 30, ms = 400, cd = 400},
	CASCADE = {pct = 25, radius = 3, q = 30},
	AFTERMATH = {pct = 7.5, radius = 1, ms = 1000, up = 80},
	OVERCHARGE = {ms = 600, pct = 112, up = 93},
	SIPHON = {heal = 4, healCap = 5, mana = 3, manaCap = 3},
	SEEK = {pct = 102, radius = 3},
	SPREAD = {count = 2, pct = 4, ticks = 2, every = 1000, radius = 3, up = 90},
	ASCEND = {hit = 102, pct = 4, ticks = 3, every = 1000, up = 85},
	-- Form I, heal
	RIPPLE = {main = 95, count = 2, pct = 6, radius = 3},
	BLOOM = {main = 75, over = 35, ticks = 6, every = 1000, up = 90},
	WARD = {cap = 10, share = 3},
	PULSE = {main = 95, pct = 3, count = 4, radius = 3},
	-- Form II, heal
	SECONDWIND = {below = 40, pct = 25, cdcut = 20, share = 15},
	LINK = {ms = 2000, pct = 30, below = 50, share = 25},
	SANCTUARY = {pct = 1.5, seconds = 5, radius = 1, up = 80},
	CLEANSE = {shield = 5},
}

-- the situation a kind is for (the model's "best Form at most +8% in the situation it is for"): one, pack or both
F.situation = {
	SPLIT = "both", CHAIN = "pack", PIERCE = "pack", REND = "both", DELAY = "both", PULL = "pack", GROUND = "both", ECHO = "both",
	SHIFT = "both", TWIN = "both", CASCADE = "pack", AFTERMATH = "both", OVERCHARGE = "both", SIPHON = "both", SEEK = "pack",
	SPREAD = "pack", ASCEND = "both", RIPPLE = "pack", BLOOM = "one", WARD = "one", PULSE = "pack", SECONDWIND = "one",
	LINK = "one", SANCTUARY = "both", CLEANSE = "both",
}

-- where a kind acts: "main" = the main hit of the cast (the biggest, the first of equals), "all" = every hit of it
F.scope = {
	SPLIT = "main", CHAIN = "main", PIERCE = "main", REND = "all", DELAY = "all", PULL = "all", GROUND = "all", ECHO = "all",
	SHIFT = "all", TWIN = "all", CASCADE = "main", AFTERMATH = "all", OVERCHARGE = "all", SIPHON = "all", SEEK = "main",
	SPREAD = "main", ASCEND = "all", RIPPLE = "main", BLOOM = "all", WARD = "all", PULSE = "main", SECONDWIND = "all",
	LINK = "all", SANCTUARY = "main", CLEANSE = "all",
}

-- the utility a kind gives when its damage (or heal) gain is under -3% on both counts (design 2.1)
F.utility = {
	PULL = "control: the enemies in the area are pulled together",
	SIPHON = "sustain: health and mana from the damage",
	SEEK = "targeting: the weakest enemy in reach, through cover",
	CLEANSE = "cleanse: a debuff removed, a shield",
	WARD = "safety: an overheal becomes a shield",
	SECONDWIND = "safety: a stronger heal and a shorter cooldown for a low target",
	LINK = "safety: a second heal for a low target",
	SHIFT = "element: the spell changes element, with a status",
	ASCEND = "element: a second conversion, a stronger status",
}

-- keys a forms.csv `over` column may set for a kind
function F.overrideKeys(base)
	return F.numbers[base]
end

-- "pct=30;count=2" -> {pct = 30, count = 2}; nil and a message for a bad text or an unknown key (kind: the base kind)
function F.parseOver(text, base)
	local out = {}
	text = tostring(text or "")
	if text == "" then
		return out
	end
	local keys = F.numbers[base]
	if not keys then
		return nil, "unknown kind " .. tostring(base)
	end
	for part in text:gmatch("[^;]+") do
		local k, v = part:match("^%s*(%w+)%s*=%s*(-?[%d%.]+)%s*$")
		if not k then
			return nil, "bad override " .. part
		end
		if keys[k] == nil then
			return nil, "no key " .. k .. " in " .. base
		end
		out[k] = tonumber(v)
	end
	return out
end

-- the numbers of a kind with the row's overrides
function F.params(base, over)
	local p = {}
	for k, v in pairs(F.numbers[base] or {}) do
		p[k] = v
	end
	for k, v in pairs(over or {}) do
		if p[k] ~= nil then
			p[k] = v
		end
	end
	return p
end

-- ---------------------------------------------------------------- geometry and picking
local function dist(a, b)
	if a.z ~= b.z then
		return math.huge
	end
	return max(abs(a.x - b.x), abs(a.y - b.y))
end
F.dist = dist

local function part(amount, pct)
	return floor(num(amount, 0) * num(pct, 0) / 100 + 0.0001)
end
F.part = part

-- the biggest hit of the cast (the first of equals)
local function mainOf(cast)
	local main
	for _, h in ipairs(cast.hits or {}) do
		if not main or h.amount > main.amount then
			main = h
		end
	end
	return main
end

-- candidates (list of {id, pos, ...}) near `pos` within radius, not in `skip`, nearest first then lowest id, at most n
local function nearest(list, pos, radius, skip, n)
	local out = {}
	for _, c in ipairs(list or {}) do
		if not (skip and skip[c.id]) then
			local d = dist(pos, c.pos)
			if d <= radius then
				out[#out + 1] = {c = c, d = d}
			end
		end
	end
	table.sort(out, function(a, b)
		if a.d ~= b.d then
			return a.d < b.d
		end
		return a.c.id < b.c.id
	end)
	local res = {}
	for i = 1, min(n or #out, #out) do
		res[i] = out[i].c
	end
	return res
end
F.nearest = nearest

local function idSet(hits)
	local s = {}
	for _, h in ipairs(hits or {}) do
		s[h.id] = true
	end
	return s
end

-- ---------------------------------------------------------------- the PvP rule (design 5.2, owner 2026-10-20: half)
-- a hit on a player: the extra amounts count at `share`, a main factor moves that share of the way from 1
function F.pvpScale(plan, share)
	share = num(share, 0.5)
	for id, f in pairs(plan.factors) do
		plan.factors[id] = 1 + (f - 1) * share
	end
	for _, a in ipairs(plan.actions) do
		if a.amount then
			a.amount = floor(a.amount * share)
		end
	end
	if plan.convert then
		plan.convert = plan.convert -- the element conversion is a shape: it stays
	end
	return plan
end

-- ---------------------------------------------------------------- the element of a conversion
function F.weakest(resist)
	local best, bestRes
	for _, el in ipairs(F.weakestOrder) do
		local r = num(resist and resist(el), 0)
		if bestRes == nil or r < bestRes then
			best, bestRes = el, r
		end
	end
	return best
end

local function convertTo(spec, cast)
	local el = spec.element
	if el == "weakest" then
		el = F.weakest(cast.resist)
	end
	return el
end

-- ---------------------------------------------------------------- the planners
-- spec = {tier = 1|2, kind = "SPLIT" (base), element = "ice" | "weakest" | nil, over = {key = number}}
-- cast = {hits = {{id, pos, amount, kill}}, foes = {{id, pos, health}}, pvp = bool, resist = function(element) -> percent,
--         heal = bool, allies = {{id, pos, health, maxHealth}}}
-- plan = {factors = {[hit id] = factor}, actions = {...}, convert = element | nil, cooldownAddMs = n, cooldownCutPct = n}
local planners = {}

local function newPlan()
	return {factors = {}, actions = {}}
end

local function add(plan, a)
	plan.actions[#plan.actions + 1] = a
end

-- the hits the kind multiplies by `f` are all hits of the cast
local function allFactor(plan, cast, f)
	for _, h in ipairs(cast.hits or {}) do
		plan.factors[h.id] = (plan.factors[h.id] or 1) * f
	end
end

local function mainFactor(plan, cast, f)
	local m = mainOf(cast)
	if m then
		plan.factors[m.id] = (plan.factors[m.id] or 1) * f
	end
	return m
end

function F.hitScale(cast)
	return math.sqrt(max(1, #(cast.hits or {})))
end

-- extra hits: `list` of enemies get pct of the main hit each; `scale` (the kinds that reach more targets: the square root of the number of
-- hits of the cast) makes the percent grow with the cast, so an area spell that hits t enemies is not diluted t times
local function extraHits(plan, m, list, pcts, p, extra, scale)
	for i, c in ipairs(list) do
		local a = {t = "hit", id = c.id, pos = c.pos, amount = part(m.amount * (scale or 1), pcts[i] or pcts[#pcts]), delay = 0, from = m.pos,
			up = 1}
		if extra then
			for k, v in pairs(extra) do
				a[k] = v
			end
		end
		add(plan, a)
	end
end

function planners.SPLIT(spec, cast, p)
	local plan = newPlan()
	local m = mainFactor(plan, cast, p.pct / 100)
	if not m then
		return plan
	end
	local skip = {[m.id] = true}
	local others = nearest(cast.foes, m.pos, p.radius, skip, p.count - 1)
	-- with fewer enemies near, the remaining hits of the split fall on the same enemies in turn
	local targets = {}
	for _, c in ipairs(others) do
		targets[#targets + 1] = c
	end
	local pool = #targets > 0 and targets or {{id = m.id, pos = m.pos}}
	local i = 1
	while #targets < p.count - 1 do
		targets[#targets + 1] = pool[i]
		i = i % #pool + 1
	end
	extraHits(plan, m, targets, {p.pct}, p, {fx = "split"})
	return plan
end

function planners.CHAIN(spec, cast, p)
	local plan = newPlan()
	local m = mainFactor(plan, cast, p.main / 100)
	if not m then
		return plan
	end
	local list = nearest(cast.foes, m.pos, p.radius, {[m.id] = true}, 2)
	extraHits(plan, m, list, {p.pct1, p.pct2}, p, {fx = "chain"}, F.hitScale(cast))
	return plan
end

function planners.PIERCE(spec, cast, p)
	local plan = newPlan()
	local m = mainFactor(plan, cast, p.main / 100)
	if not m then
		return plan
	end
	-- enemies on the line behind the target, away from the caster: the engine passes them as cast.line (nearest first)
	local list = {}
	for _, c in ipairs(cast.line or {}) do
		if c.id ~= m.id and #list < p.count then
			list[#list + 1] = c
		end
	end
	extraHits(plan, m, list, {p.pct}, p, {fx = "pierce"}, F.hitScale(cast))
	plan.rangeAdd = p.range
	return plan
end

function planners.REND(spec, cast, p)
	local plan = newPlan()
	local f = p.main / 100
	allFactor(plan, cast, f)
	for _, h in ipairs(cast.hits or {}) do
		local per = part(h.amount, p.dot / p.ticks)
		if per > 0 then
			add(plan, {t = "dot", id = h.id, amount = per, ticks = p.ticks, every = p.every, fx = "rend", up = p.up / 100})
		end
	end
	return plan
end

function planners.DELAY(spec, cast, p)
	local plan = newPlan()
	allFactor(plan, cast, 0)
	for _, h in ipairs(cast.hits or {}) do
		add(plan, {t = "hit", id = h.id, pos = h.pos, amount = part(h.amount, p.pct), delay = p.ms, telegraph = true,
			areaPct = p.area, fx = "delay", up = p.up / 100})
	end
	return plan
end

function planners.PULL(spec, cast, p)
	local plan = newPlan()
	allFactor(plan, cast, p.main / 100)
	local m = mainOf(cast)
	if m then
		-- every enemy the cast hit is pulled to within pullTo of the centre (the main hit's tile); never a player
		for _, h in ipairs(cast.hits or {}) do
			if not h.player and h.id ~= m.id and dist(h.pos, m.pos) > p.pullTo then
				add(plan, {t = "pull", id = h.id, to = m.pos, within = p.pullTo})
			end
		end
	end
	return plan
end

function planners.GROUND(spec, cast, p)
	local plan = newPlan()
	for _, h in ipairs(cast.hits or {}) do
		add(plan, {t = "ground", pos = h.pos, radius = p.radius, amount = part(h.amount, p.pct), seconds = p.seconds, every = 1000,
			fx = "ground", up = p.up / 100, ref = h.id})
	end
	-- one ground per distinct hit position is enough: a crowded cast does not lay twenty
	plan.actions = F.uniquePositions(plan.actions, 3)
	return plan
end

function planners.ECHO(spec, cast, p)
	local plan = newPlan()
	allFactor(plan, cast, p.main / 100)
	for _, h in ipairs(cast.hits or {}) do
		add(plan, {t = "hit", id = h.id, pos = h.pos, amount = part(h.amount, p.pct), delay = p.ms, fx = "echo", up = p.up / 100})
	end
	return plan
end

function planners.SHIFT(spec, cast, p)
	local plan = newPlan()
	plan.convert = convertTo(spec, cast)
	for _, h in ipairs(cast.hits or {}) do
		local per = part(h.amount, p.pct / p.ticks)
		if per > 0 then
			add(plan, {t = "dot", id = h.id, amount = per, ticks = p.ticks, every = p.every, fx = "status", element = plan.convert,
				up = p.up / 100})
		end
	end
	return plan
end

function planners.TWIN(spec, cast, p)
	local plan = newPlan()
	allFactor(plan, cast, p.main / 100)
	for _, h in ipairs(cast.hits or {}) do
		add(plan, {t = "hit", id = h.id, pos = h.pos, amount = part(h.amount, p.pct), delay = p.ms, fx = "twin", up = 1})
	end
	plan.cooldownAddMs = p.cd
	return plan
end

function planners.CASCADE(spec, cast, p)
	local plan = newPlan()
	local killer
	for _, h in ipairs(cast.hits or {}) do
		if h.kill then
			killer = h
			break
		end
	end
	local m = mainOf(cast)
	if killer and m then
		local list = nearest(cast.foes, killer.pos, p.radius, {[killer.id] = true}, 1)
		extraHits(plan, {amount = killer.amount, pos = killer.pos}, list, {p.pct}, p, {fx = "cascade", up = 1})
	end
	-- what the model counts: a kill happens in q percent of the casts (the engine has the real kill)
	-- a cast that hits more enemies kills one more often: 1 - (1 - q)^hits
	plan.killChance = 100 * (1 - (1 - p.q / 100) ^ max(1, #cast.hits))
	return plan
end

function planners.AFTERMATH(spec, cast, p)
	local plan = newPlan()
	for _, h in ipairs(cast.hits or {}) do
		add(plan, {t = "burst", pos = h.pos, radius = p.radius, amount = part(h.amount, p.pct), delay = p.ms, fx = "aftermath",
			up = p.up / 100, ref = h.id})
	end
	plan.actions = F.uniquePositions(plan.actions, 3)
	return plan
end

function planners.OVERCHARGE(spec, cast, p)
	local plan = newPlan()
	allFactor(plan, cast, 0)
	for _, h in ipairs(cast.hits or {}) do
		add(plan, {t = "hit", id = h.id, pos = h.pos, amount = part(h.amount, p.pct), delay = p.ms, telegraph = true,
			fx = "overcharge", up = p.up / 100})
	end
	return plan
end

function planners.SIPHON(spec, cast, p)
	local plan = newPlan()
	local total = 0
	for _, h in ipairs(cast.hits or {}) do
		total = total + h.amount
	end
	if total > 0 then
		add(plan, {t = "selfheal", amount = part(total, p.heal), capPct = p.healCap})
		add(plan, {t = "selfmana", amount = part(total, p.mana), capPct = p.manaCap})
	end
	return plan
end

function planners.SEEK(spec, cast, p)
	local plan = newPlan()
	local m = mainOf(cast)
	if not m then
		return plan
	end
	-- the weakest enemy in reach of the main hit's tile (health, then nearest, then id)
	local best
	local list = {{id = m.id, pos = m.pos, health = m.health}}
	for _, c in ipairs(nearest(cast.foes, m.pos, p.radius, {[m.id] = true}, 12)) do
		list[#list + 1] = c
	end
	for _, c in ipairs(list) do
		local h = num(c.health, math.huge)
		if not best or h < best.h or (h == best.h and dist(m.pos, c.pos) < best.d) then
			best = {c = c, h = h, d = dist(m.pos, c.pos)}
		end
	end
	if best and best.c.id ~= m.id then
		plan.factors[m.id] = 0
		add(plan, {t = "hit", id = best.c.id, pos = best.c.pos, amount = part(m.amount, p.pct), delay = 0, from = m.pos,
			fx = "seek", up = 1})
	else
		plan.factors[m.id] = p.pct / 100
	end
	return plan
end

function planners.SPREAD(spec, cast, p)
	local plan = newPlan()
	local m = mainOf(cast)
	if not m then
		return plan
	end
	local list = nearest(cast.foes, m.pos, p.radius, {[m.id] = true}, p.count)
	for _, c in ipairs(list) do
		local per = part(m.amount * F.hitScale(cast), p.pct / p.ticks)
		if per > 0 then
			add(plan, {t = "dot", id = c.id, amount = per, ticks = p.ticks, every = p.every, fx = "spread", up = p.up / 100})
		end
	end
	return plan
end

function planners.ASCEND(spec, cast, p)
	local plan = newPlan()
	plan.convert = convertTo(spec, cast)
	allFactor(plan, cast, p.hit / 100)
	for _, h in ipairs(cast.hits or {}) do
		local per = part(h.amount, p.pct / p.ticks)
		if per > 0 then
			add(plan, {t = "dot", id = h.id, amount = per, ticks = p.ticks, every = p.every, fx = "status", element = plan.convert,
				up = p.up / 100})
		end
	end
	return plan
end

-- ---- heals: cast.hits are the heals {id, pos, amount, health, maxHealth, overheal}, cast.allies the other allies near
function planners.RIPPLE(spec, cast, p)
	local plan = newPlan()
	local m = mainFactor(plan, cast, p.main / 100)
	if not m then
		return plan
	end
	local list = nearest(cast.allies, m.pos, p.radius, {[m.id] = true}, p.count)
	for _, c in ipairs(list) do
		add(plan, {t = "heal", id = c.id, pos = c.pos, amount = part(m.amount * F.hitScale(cast), p.pct), delay = 0, fx = "ripple", up = 1})
	end
	return plan
end

function planners.BLOOM(spec, cast, p)
	local plan = newPlan()
	allFactor(plan, cast, p.main / 100)
	for _, h in ipairs(cast.hits or {}) do
		local per = part(h.amount, p.over / p.ticks)
		if per > 0 then
			add(plan, {t = "hot", id = h.id, amount = per, ticks = p.ticks, every = p.every, fx = "bloom", up = p.up / 100})
		end
	end
	return plan
end

function planners.WARD(spec, cast, p)
	local plan = newPlan()
	for _, h in ipairs(cast.hits or {}) do
		local over = num(h.overheal, 0)
		local cap = part(num(h.maxHealth, 0), p.cap)
		local amount = min(over, cap)
		if amount > 0 then
			add(plan, {t = "shield", id = h.id, amount = amount, fx = "ward", up = 1})
		end
	end
	plan.modelShare = p.share
	return plan
end

function planners.PULSE(spec, cast, p)
	local plan = newPlan()
	local m = mainFactor(plan, cast, p.main / 100)
	if not m then
		return plan
	end
	local list = nearest(cast.allies, m.pos, p.radius, {[m.id] = true}, p.count)
	for _, c in ipairs(list) do
		add(plan, {t = "heal", id = c.id, pos = c.pos, amount = part(m.amount * F.hitScale(cast), p.pct), delay = 0, fx = "pulse", up = 1})
	end
	return plan
end

function planners.SECONDWIND(spec, cast, p)
	local plan = newPlan()
	for _, h in ipairs(cast.hits or {}) do
		local pctHealth = num(h.maxHealth, 0) > 0 and 100 * num(h.health, 0) / h.maxHealth or 100
		if pctHealth < p.below then
			plan.factors[h.id] = 1 + p.pct / 100
			plan.cooldownCutPct = p.cdcut
		end
	end
	plan.modelShare = p.share
	return plan
end

function planners.LINK(spec, cast, p)
	local plan = newPlan()
	for _, h in ipairs(cast.hits or {}) do
		local pctHealth = num(h.maxHealth, 0) > 0 and 100 * num(h.health, 0) / h.maxHealth or 100
		if pctHealth < p.below then
			add(plan, {t = "heal", id = h.id, pos = h.pos, amount = part(h.amount, p.pct), delay = p.ms, fx = "link", up = 1,
				onlyBelow = p.below})
		end
	end
	plan.modelShare = p.share
	return plan
end

function planners.SANCTUARY(spec, cast, p)
	local plan = newPlan()
	local m = mainOf(cast)
	if m then
		add(plan, {t = "groundheal", pos = m.pos, radius = p.radius, amount = part(m.amount, p.pct), seconds = p.seconds,
			every = 1000, fx = "sanctuary", up = p.up / 100})
	end
	return plan
end

function planners.CLEANSE(spec, cast, p)
	local plan = newPlan()
	for _, h in ipairs(cast.hits or {}) do
		add(plan, {t = "cleanse", id = h.id})
		add(plan, {t = "shield", id = h.id, amount = part(h.amount, p.shield), fx = "cleanse", up = 1})
	end
	return plan
end

-- at most n actions of a kind with distinct positions
function F.uniquePositions(actions, n)
	local seen, out = {}, {}
	for _, a in ipairs(actions) do
		local key = a.pos and (a.pos.x .. "," .. a.pos.y .. "," .. a.pos.z) or tostring(#out)
		if not seen[key] and #out < n then
			seen[key] = true
			out[#out + 1] = a
		end
	end
	return out
end

-- plan one Form on a cast
function F.plan(spec, cast)
	local fn = planners[spec.kind]
	if not fn then
		return nil, "unknown kind"
	end
	local p = F.params(spec.kind, spec.over)
	local plan = fn(spec, cast, p)
	plan.kind = spec.kind
	plan.tier = spec.tier
	if cast.pvp then
		F.pvpScale(plan, cast.pvpShare)
	end
	return plan
end

-- several Forms (Form I, Form II) of one cast: the factors multiply, the actions join, the later conversion wins
function F.planAll(specs, cast)
	local all = {factors = {}, actions = {}, kinds = {}}
	for _, spec in ipairs(specs) do
		local plan = F.plan(spec, cast)
		if plan then
			all.kinds[#all.kinds + 1] = spec.kind
			for id, f in pairs(plan.factors) do
				all.factors[id] = (all.factors[id] or 1) * f
			end
			for _, a in ipairs(plan.actions) do
				all.actions[#all.actions + 1] = a
			end
			if plan.convert then
				all.convert = plan.convert
			end
			all.cooldownAddMs = (all.cooldownAddMs or 0) + (plan.cooldownAddMs or 0)
			if plan.cooldownCutPct then
				all.cooldownCutPct = max(all.cooldownCutPct or 0, plan.cooldownCutPct)
			end
			all.killChance = plan.killChance or all.killChance
			all.modelShare = plan.modelShare or all.modelShare
			all.rangeAdd = (all.rangeAdd or 0) + (plan.rangeAdd or 0)
		end
	end
	return all
end

-- The factor the Forms put on ONE hit at the moment it lands (the engine cannot wait for the rest of the cast): the "all" kinds
-- always, the "main" kinds on the first hit of the cast. `foes` only matters for SEEK (the weakest enemy near). The rest of the plan
-- (the extra hits) is made when the cast ends, over every hit (planAll).
function F.hitFactor(specs, hit, first, pvp, share, foes)
	local f = 1
	for _, spec in ipairs(specs) do
		if first or F.scope[spec.kind] == "all" then
			local plan = F.plan(spec, {hits = {hit}, foes = foes or {}, allies = {}, line = {}, pvp = pvp, pvpShare = share,
				resist = function() return 0 end})
			if plan then
				f = f * (plan.factors[hit.id] or 1)
			end
		end
	end
	return f
end

-- ---------------------------------------------------------------- the model's gain (docs/SPELL_UPGRADES.md 2.1)
-- The damage (or heal) of one cast with the Form against the cast without it, for a synthetic cast: `hits` = what the base spell
-- hits (1 hit on one target, `t` hits in a pack of `n` enemies), `foes` = the other enemies of the pack, packed (all within 1 sqm).
-- Counts every action at its amount x up; conditional kinds count their modelled share.
function F.gain(spec, n, t, shape)
	local hits, foes = {}, {}
	local A = 1000
	for i = 1, n do
		local e = {id = i, pos = {x = 100 + (i % 2), y = 100 + floor(i / 2) % 2, z = 7}, health = 5000, maxHealth = 10000}
		if i <= t then
			hits[#hits + 1] = {id = i, pos = e.pos, amount = A, kill = false, health = 5000, maxHealth = 10000}
		end
		foes[#foes + 1] = e
	end
	local line = {}
	for i = 2, n do
		line[#line + 1] = {id = i, pos = {x = 100 + i, y = 100, z = 7}}
	end
	local cast = {hits = hits, foes = foes, allies = foes, line = line, resist = function() return 0 end}
	if spec.kind == "CASCADE" then
		-- a kill by the spell in q percent of the casts: the first hit kills
		hits[1].kill = true
	end
	local plan = F.plan(spec, cast)
	if not plan then
		return nil
	end
	local base = 0
	for _, h in ipairs(hits) do
		base = base + h.amount
	end
	if base <= 0 then
		return 1
	end
	local total = 0
	for _, h in ipairs(hits) do
		total = total + h.amount * (plan.factors[h.id] or 1)
	end
	for _, a in ipairs(plan.actions) do
		local v = num(a.amount, 0)
		local up = num(a.up, 1)
		if a.t == "dot" or a.t == "hot" then
			v = v * a.ticks
		elseif a.t == "ground" or a.t == "groundheal" then
			-- a ground counts once for the enemy it was laid for
			v = v * a.seconds
		end
		if a.t ~= "pull" and a.t ~= "cleanse" and a.t ~= "selfheal" and a.t ~= "selfmana" and a.t ~= "shield" then
			total = total + v * up
		end
	end
	if spec.kind == "CASCADE" then
		-- the free hit lands in q percent of the casts
		total = base + (total - base) * (plan.killChance or 0) / 100
	end
	if spec.kind == "WARD" then
		total = base * (1 + (plan.modelShare or 0) / 100)
	end
	if spec.kind == "SECONDWIND" or spec.kind == "LINK" then
		-- conditional on a target under the threshold: only the share of casts that meet one
		local share = (plan.modelShare or 0) / 100
		local gain = 0
		if spec.kind == "SECONDWIND" then
			local p = F.params("SECONDWIND", spec.over)
			gain = p.pct / 100 + (plan.cooldownCutPct or 0) / 100 * 0.5
		else
			local p = F.params("LINK", spec.over)
			gain = p.pct / 100
		end
		total = base * (1 + gain * share)
	end
	if spec.kind == "SIPHON" or spec.kind == "CLEANSE" then
		total = base * (spec.kind == "CLEANSE" and (1 + F.params("CLEANSE", spec.over).shield / 100) or 1)
	end
	return total / base
end

-- ---------------------------------------------------------------- choosing and changing (design 2.4)
-- the gold of a change
function F.price(level, cfg)
	local f = cfg.forms
	return max(f.minPrice, f.perLevel * max(0, floor(num(level, 0))))
end

-- the rank a tier needs
function F.rankNeeded(tier, cfg)
	return tier == 2 and cfg.forms.rank2 or cfg.forms.rank1
end

-- decide a pick request. st = {rank, f1, f2 (current picks 0|1|2), level, lastAt, lastWhat (spell id * 10 + tier), now, spellId,
-- gate (O752: the level the tier opens for this spell, spell_milestones_core.lua formLevel; nil: none)}
-- Returns {ok = true, price = n, free = bool, why = "first" | "same" | "window" | "paid"} or {ok = false, why = "...", need}
-- The level gate holds only the first pick of a tier: a pick already made stays and may be changed.
function F.decide(st, tier, pick, cfg)
	if tier ~= 1 and tier ~= 2 then
		return {ok = false, why = "tier"}
	end
	if pick ~= 1 and pick ~= 2 then
		return {ok = false, why = "pick"}
	end
	if num(st.rank, 0) < F.rankNeeded(tier, cfg) then
		return {ok = false, why = "rank"}
	end
	if tier == 2 and num(st.f1, 0) == 0 then
		return {ok = false, why = "form1"}
	end
	local cur = tier == 1 and num(st.f1, 0) or num(st.f2, 0)
	if cur == pick then
		return {ok = true, price = 0, free = true, why = "same", noop = true}
	end
	if cur == 0 then
		if st.gate and num(st.level, 0) < num(st.gate, 0) then
			return {ok = false, why = "level", need = num(st.gate, 0)}
		end
		return {ok = true, price = 0, free = true, why = "first"}
	end
	local what = num(st.spellId, 0) * 10 + tier
	if num(st.lastWhat, -1) == what and num(st.now, 0) - num(st.lastAt, -1e12) <= cfg.forms.freeSeconds then
		return {ok = true, price = 0, free = true, why = "window"}
	end
	return {ok = true, price = F.price(st.level, cfg), free = false, why = "paid"}
end

-- bank first, then carried coins: {fromBank, fromCoins} or nil when the two are short
function F.split(price, bank, carried)
	price, bank, carried = max(0, num(price, 0)), max(0, num(bank, 0)), max(0, num(carried, 0))
	if bank + carried < price then
		return nil
	end
	local fromBank = min(bank, price)
	return {fromBank = fromBank, fromCoins = price - fromBank}
end

-- the Form's pick -> the kind row: rows = {[tier] = {[pick] = {kind, element, over, ...}}}
function F.specOf(row)
	local base, el = F.parseKind(row.kind)
	local over = F.parseOver(row.over, base) or {}
	return {tier = row.tier == "II" and 2 or 1, kind = base, element = el, over = over}
end

return F
