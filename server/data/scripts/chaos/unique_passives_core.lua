-- unique_passives_core.lua: the pure rules of the unique item passives (O278; numbers: unique_passives_config.lua,
-- texts: unique_passives_text.lua, engine glue: unique_passives.lua, tests: tests/unique_passives_test.lua).
-- No engine calls here: every rule takes the state of one character, the active passives and a plain context table, and
-- returns numbers or a plan the glue carries out. Lua 5.1 / 5.3 / LuaJIT compatible.
--
-- Vocabulary: `entry` = a passive of the config (family defaults merged in), `act` = the list of active entries of a
-- character (activeSet), `S` = the state of a character (newState), `ctx` = what the engine tells for one event:
--   now (ms), origin (melee ranged spell), elem (physical fire ice energy earth death holy drown ...), crit, proc (the hit
--   is itself a proc or a condition tick: no passive reacts to it), dot (damage over time), targetId, targetPlayer,
--   targetPct (health % of the target), selfPct, manaPct, others (monsters near the character besides the target),
--   stats {maxMana maxHealth magicLevel speed shield level}.

ChaosUniquePassivesCore = ChaosUniquePassivesCore or {}
local C = ChaosUniquePassivesCore

local floor, min, max, abs = math.floor, math.min, math.max, math.abs

local function cfgOf(cfg)
	return cfg or ChaosUniquePassivesConfig
end

-- ------------------------------------------------------------------------------------------------ entries and sets
-- the passive of an item id with the family defaults under it, nil for a plain item. The merged table is cached.
function C.entry(cfg, itemId)
	cfg = cfgOf(cfg)
	cfg._merged = cfg._merged or {}
	local hit = cfg._merged[itemId]
	if hit then
		return hit
	end
	local raw = cfg.passives[itemId]
	if not raw then
		return nil
	end
	local e = {id = itemId}
	for k, v in pairs(cfg.families[raw.family] or {}) do
		e[k] = v
	end
	for k, v in pairs(raw) do
		e[k] = v
	end
	if e.lines == "ALL" then
		e.lines = "WRMTKNP"
	end
	cfg._merged[itemId] = e
	return e
end

-- the letter of a class line key ("warrior" -> "W"), nil for an unknown line
function C.letterOf(cfg, lineKey)
	for letter, name in pairs(cfgOf(cfg).lines) do
		if name == lineKey then
			return letter
		end
	end
	return nil
end

-- do the passive's lines include this class line
function C.worksFor(cfg, entry, lineKey)
	local letter = C.letterOf(cfg, lineKey)
	return letter ~= nil and entry.lines:find(letter, 1, true) ~= nil
end

-- the active passives of a character: the worn unique ids (a list, repeats allowed), its class line. A passive of
-- another line sleeps, a family counts once (the highest item level wins, then the lower id), at most maxActive.
function C.activeSet(cfg, ids, lineKey)
	cfg = cfgOf(cfg)
	local list, seen = {}, {}
	for _, id in ipairs(ids or {}) do
		local e = C.entry(cfg, id)
		if e and not seen[id] and C.worksFor(cfg, e, lineKey) then
			seen[id] = true
			list[#list + 1] = e
		end
	end
	table.sort(list, function(a, b)
		if a.lv ~= b.lv then
			return a.lv > b.lv
		end
		return a.id < b.id
	end)
	local out, fam = {}, {}
	for _, e in ipairs(list) do
		if #out < cfg.maxActive and not fam[e.family] then
			fam[e.family] = true
			out[#out + 1] = e
		end
	end
	return out
end

function C.find(act, family)
	for _, e in ipairs(act or {}) do
		if e.family == family then
			return e
		end
	end
	return nil
end

-- a key of the active set for caches: "id,id,id"
function C.key(act)
	local t = {}
	for _, e in ipairs(act or {}) do
		t[#t + 1] = e.id
	end
	return table.concat(t, ",")
end

-- ------------------------------------------------------------------------------------------------ state
function C.newState()
	return {focus = {target = nil, stacks = 0, last = 0}, marks = {}, stacks = {n = 0, last = -1e9}, ward = 0, wardAt = -1e9,
		icd = {}, panicUntil = -1, panicAt = -1e9, feast = {t0 = -1e9, amount = 0}, fightAt = -1e9, afflict = {},
		labels = {}}
end

-- true when the cooldown of `key` is over; starts it
function C.ready(S, key, now, ms)
	local last = S.icd[key]
	if last and now - last < ms then
		return false
	end
	S.icd[key] = now
	return true
end

local function stackCount(S, e, now)
	local st = S.stacks
	if st.n > 0 and now - st.last > e.windowMs then
		st.n = 0
	end
	return st.n
end

-- ------------------------------------------------------------------------------------------------ damage you deal
local function marked(S, id, now)
	local at = S.marks[id]
	return at ~= nil and at > now
end

-- the multiplier on a direct hit of the character (1 = unchanged). Procs and condition ticks never get one.
function C.dealt(cfg, S, act, ctx)
	cfg = cfgOf(cfg)
	if ctx.proc or ctx.dot or #act == 0 then
		return 1
	end
	local now, m = ctx.now, 1
	for _, e in ipairs(act) do
		local f, k = e.family, 1
		if f == "convert" then
			-- the converted part's bonus is in C.convertPlan; here only the price on the other elements
			if ctx.elem ~= "physical" and ctx.elem ~= e.elem then
				k = 1 - e.other / 100
			end
		elseif f == "lowlife" then
			if ctx.selfPct < e.at then
				k = 1 + e.bonus / 100
			elseif ctx.selfPct > e.malusAt then
				k = 1 - e.malus / 100
			end
		elseif f == "overflow" then
			if ctx.manaPct >= e.at then
				k = 1 + e.bonus / 100
			elseif ctx.manaPct <= e.malusAt then
				k = 1 - e.malus / 100
			end
		elseif f == "opener" then
			local p = ctx.targetPct
			if e.side == "above" then
				k = p >= e.at and 1 + e.bonus / 100 or (p <= e.malusAt and 1 - e.malus / 100 or 1)
			else
				k = p <= e.at and 1 + e.bonus / 100 or (p >= e.malusAt and 1 - e.malus / 100 or 1)
			end
		elseif f == "focus" then
			local fo = S.focus
			if fo.target == ctx.targetId and now - fo.last <= e.resetMs then
				fo.stacks = min(e.max, fo.stacks + 1)
				k = 1 + fo.stacks * e.perStack / 100
			else
				fo.target, fo.stacks = ctx.targetId, 0
				k = 1 - e.first / 100
			end
			fo.last = now
		elseif f == "statscale" then
			if e.origin == "any" or e.origin == ctx.origin then
				local v = (ctx.stats and ctx.stats[e.stat]) or 0
				local pct = min(e.cap, floor(max(0, v - e.from) / e.per) * e.bonusPer)
				k = 1 + pct / 100
			end
		elseif f == "critrule" then
			k = ctx.crit and 1 + e.crit / 100 or 1 - e.plain / 100
		elseif f == "crowd" then
			local n = ctx.others or 0
			if e.mode == "pack" then
				k = n == 0 and 1 - e.alone / 100 or 1 + min(e.max, n) * e.per / 100
			else
				k = n == 0 and 1 + e.bonus / 100 or (n >= e.many and 1 - e.malus / 100 or 1)
			end
		elseif f == "stacks" then
			k = 1 + stackCount(S, e, now) * e.perStack / 100
		elseif f == "minionPact" then
			if ctx.origin == "spell" then
				k = 1 - e.own / 100
			end
		elseif f == "mark" then
			if marked(S, ctx.targetId, now) then
				k = 1 + e.bonus / 100
			else
				k = 1 - e.unmarked / 100
			end
		end
		if e.dealtLess and e.dealtLess > 0 then
			k = k * (1 - e.dealtLess / 100)
		end
		m = m * k
	end
	m = min(cfg.dealtCap, max(cfg.dealtFloor, m))
	if ctx.targetPlayer and m > 1 then
		m = 1 + (m - 1) * cfg.pvpScale
	end
	return m
end

-- a hit that landed (after dealt): marks and fight clock. Call once per direct hit.
function C.landed(cfg, S, act, ctx)
	if ctx.proc then
		return
	end
	S.fightAt = ctx.now
	local e = C.find(act, "mark")
	if e and ctx.targetId then
		local n = 0
		for id, at in pairs(S.marks) do
			if at <= ctx.now then
				S.marks[id] = nil
			else
				n = n + 1
			end
		end
		if S.marks[ctx.targetId] or n < min(e.max, cfgOf(cfg).markKeep) then
			S.marks[ctx.targetId] = ctx.now + e.ms
		end
	end
	local st = C.find(act, "stacks")
	if st and st.trigger == "crit" and ctx.crit then
		C.addStack(S, st, ctx.now)
	end
end

function C.addStack(S, e, now)
	local st = S.stacks
	if st.n > 0 and now - st.last > e.windowMs then
		st.n = 0
	end
	st.n = min(e.max, st.n + 1)
	st.last = now
end

-- convert: the part of a physical hit that is dealt as the element instead: nil or {elem, share (0-1), bonus (mult)}
function C.convertPlan(act, ctx)
	local e = C.find(act, "convert")
	if not e or ctx.proc or ctx.dot or ctx.elem ~= "physical" or ctx.targetPlayer then
		return nil
	end
	return {elem = e.elem, share = e.share / 100, mult = 1 + e.bonus / 100}
end

-- ------------------------------------------------------------------------------------------------ damage you take
-- healing the character receives, scaled (a price of some passives, and none while a panic guard holds)
function C.healMult(S, act, now)
	if now < S.panicUntil and C.find(act, "panic") then
		return 0
	end
	local m = 1
	for _, e in ipairs(act) do
		if e.healLess and e.healLess > 0 then
			m = m * (1 - e.healLess / 100)
		end
	end
	return max(0, m)
end

local DOT_KIND = {fire = "fire", poison = "earth", earth = "earth", energy = "energy", ice = "ice", drown = "drown",
	death = "death", bleed = "physical", physical = "physical"}

-- one hit on the character. ctx: now, dmg (>0), elem, dot, fromMonster, maxHealth, health, maxMana, mana, level.
-- Returns {dmg = what the health takes, mana = paid from mana, absorbed = taken by the ward, reflect = damage to send
-- back (a number to deal to the attacker), panic = true when the panic guard just started}
function C.incoming(cfg, S, act, ctx)
	cfg = cfgOf(cfg)
	local out = {dmg = ctx.dmg, mana = 0, absorbed = 0, reflect = 0, panic = false}
	if #act == 0 or ctx.dmg <= 0 then
		return out
	end
	local now, dmg = ctx.now, ctx.dmg
	local mult = 1
	local imm = C.find(act, "immunity")
	if imm then
		if ctx.dot and DOT_KIND[imm.kind] and DOT_KIND[imm.kind] == (DOT_KIND[ctx.elem] or ctx.elem) then
			out.dmg = 0
			return out
		elseif not ctx.dot and (ctx.elem == imm.kind or (imm.kind == "bleed" and ctx.elem == "physical")) then
			mult = mult * (1 + imm.more / 100)
		end
	end
	for _, e in ipairs(act) do
		if e.takenMore and e.takenMore > 0 then
			mult = mult * (1 + e.takenMore / 100)
		end
	end
	local st = C.find(act, "stacks")
	if st and st.takenPerStack > 0 then
		mult = mult * (1 + stackCount(S, st, now) * st.takenPerStack / 100)
	end
	local pn = C.find(act, "panic")
	if pn and now < S.panicUntil then
		mult = mult * (1 - pn.reduce / 100)
	end
	mult = min(cfg.takenCeil, max(cfg.takenFloor, mult))
	dmg = dmg * mult
	local hc = C.find(act, "hitcap")
	if hc and ctx.fromMonster then
		dmg = min(dmg, ctx.maxHealth * hc.cap / 100)
	end
	local ms = C.find(act, "manashield")
	if ms and ctx.fromMonster and ctx.maxMana > 0 then
		local room = max(0, ctx.mana - ctx.maxMana * ms.reserve / 100)
		local pay = min(floor(dmg * ms.share / 100), floor(room))
		out.mana = pay
		dmg = dmg - pay
	end
	local w = C.find(act, "ward")
	if w and S.ward > 0 then
		local a = min(S.ward, dmg)
		S.ward = S.ward - a
		dmg = dmg - a
		out.absorbed = floor(a)
		if w.reflect > 0 and ctx.fromMonster then
			out.reflect = floor(a * w.reflect / 100)
		end
	end
	dmg = max(0, floor(dmg + 0.5))
	out.dmg = dmg
	if pn and ctx.fromMonster and now >= S.panicUntil and ctx.health - dmg < ctx.maxHealth * pn.below / 100
			and ctx.health - dmg > 0 and C.ready(S, "panic", now, pn.icdMs) then
		S.panicUntil = now + pn.ms
		out.panic = true
	end
	return out
end

-- ward gain: from damage dealt (a hit) or a kill. The ward never exceeds cap% of the maximum health; one hit adds at
-- most wardHitMax% of it.
function C.wardGain(cfg, S, act, kind, amount, maxHealth, now)
	local w = C.find(act, "ward")
	if not w then
		return 0
	end
	local gain
	if kind == "kill" then
		gain = maxHealth * w.onKill / 100
	else
		gain = min(amount * w.onHit / 100, maxHealth * cfgOf(cfg).wardHitMax / 100)
	end
	local room = max(0, maxHealth * w.cap / 100 - S.ward)
	gain = min(gain, room)
	if gain > 0 then
		S.ward = S.ward + gain
		S.wardAt = now
	end
	return gain
end

-- the fade of the ward, once a tick
function C.wardFade(cfg, S, act, maxHealth, now)
	local w = C.find(act, "ward")
	if not w then
		S.ward = 0
		return
	end
	if S.ward > 0 and now - S.wardAt >= w.decayAfterMs then
		S.ward = max(0, S.ward - maxHealth * w.cap / 100 * w.decayPct / 100 * cfgOf(cfg).tickMs / 1000)
	end
	S.ward = min(S.ward, maxHealth * w.cap / 100)
end

-- ------------------------------------------------------------------------------------------------ procs
-- extra: a hit that sends a share of itself at other monsters. nil or {damage, targets, radius, elem (nil = the hit's own),
-- cost, costKind}
function C.extraPlan(cfg, S, act, ctx)
	local e = C.find(act, "extra")
	if not e or ctx.proc or ctx.dot or ctx.targetPlayer or ctx.damage <= 0 then
		return nil
	end
	if e.origin ~= "any" and e.origin ~= ctx.origin then
		return nil
	end
	local cost = 0
	if e.cost == "health" then
		local keep = ctx.maxHealth * e.minHealth / 100
		cost = max(1, floor(ctx.maxHealth * e.costPct / 100))
		if ctx.health - cost <= keep then
			return nil
		end
	elseif e.cost == "mana" then
		cost = max(1, floor(ctx.maxMana * e.costPct / 100))
		if ctx.mana < cost then
			return nil
		end
	end
	if not C.ready(S, "extra", ctx.now, e.icdMs) then
		return nil
	end
	local dmg = floor(ctx.damage * e.pct / 100)
	if dmg <= 0 then
		return nil
	end
	return {damage = dmg, targets = e.targets, radius = e.radius, elem = e.elem, cost = cost, costKind = e.cost}
end

-- nova: event "kill", "crit" or "hurt". nil or {damage, elem, radius, targets, cost}
function C.novaPlan(cfg, S, act, event, ctx)
	local e = C.find(act, "nova")
	if not e or e.on ~= event then
		return nil
	end
	local cost = 0
	if e.selfCost > 0 then
		local keep = ctx.maxHealth * e.minHealth / 100
		cost = max(1, floor(ctx.maxHealth * e.selfCost / 100))
		if ctx.health - cost <= keep then
			return nil
		end
	end
	if event == "hurt" and (not ctx.fromMonster or ctx.dmg < ctx.maxHealth * e.minHit / 100) then
		return nil
	end
	if not C.ready(S, "nova", ctx.now, e.icdMs) then
		return nil
	end
	return {damage = floor(e.base + e.perLevel * (ctx.level or 1)), elem = e.elem, radius = e.radius, targets = e.targets,
		cost = cost}
end

-- riposte: a hard monster hit answered. nil or {damage, elem}
function C.ripostePlan(cfg, S, act, ctx)
	local e = C.find(act, "riposte")
	if not e or not ctx.fromMonster or ctx.dmg < ctx.maxHealth * e.minHit / 100 then
		return nil
	end
	if not C.ready(S, "riposte", ctx.now, e.icdMs) then
		return nil
	end
	local dmg = min(floor(ctx.dmg * e.pct / 100), floor(e.capBase + e.capPerLevel * (ctx.level or 1)))
	if dmg <= 0 then
		return nil
	end
	return {damage = dmg, elem = e.elem}
end

-- a kill: stacks, the ward, a feast. Returns {heal, mana} (already capped per second and scaled by the healing price)
function C.kill(cfg, S, act, ctx)
	local out = {heal = 0, mana = 0, ward = 0}
	local st = C.find(act, "stacks")
	if st and st.trigger == "kill" then
		C.addStack(S, st, ctx.now)
	end
	out.ward = C.wardGain(cfg, S, act, "kill", 0, ctx.maxHealth, ctx.now)
	local f = C.find(act, "feast")
	if f then
		local pool = f.res == "mana" and ctx.maxMana or ctx.maxHealth
		local want = pool * f.onKill / 100
		local fe = S.feast
		if ctx.now - fe.t0 >= 1000 then
			fe.t0, fe.amount = ctx.now, 0
		end
		local give = max(0, min(want, pool * f.capPerSec / 100 - fe.amount))
		fe.amount = fe.amount + give
		give = floor(give)
		if f.res == "mana" then
			out.mana = give
		else
			out.heal = floor(give * C.healMult(S, act, ctx.now))
		end
	end
	return out
end

-- mend: the heal of a tick for each ally in reach. nil when it is not time or the character did not fight.
function C.mendPlan(cfg, S, act, now)
	local e = C.find(act, "mend")
	if not e or now - S.fightAt > e.fightMs then
		return nil
	end
	if not C.ready(S, "mend", now, e.tickMs) then
		return nil
	end
	return {pct = min(e.heal, cfgOf(cfg).mendMaxPct), radius = e.radius}
end

-- critrule: a heal on a critical hit. Returns the amount (0 = none)
function C.critHeal(cfg, S, act, ctx)
	local e = C.find(act, "critrule")
	if not e or e.heal <= 0 or not ctx.crit or ctx.proc or ctx.damage <= 0 then
		return 0
	end
	if not C.ready(S, "critheal", ctx.now, e.healIcdMs) then
		return 0
	end
	local amount = min(ctx.damage * e.heal / 100, ctx.maxHealth * cfgOf(cfg).healCapPct / 100)
	return floor(amount * C.healMult(S, act, ctx.now))
end

-- spread: a monster died with your damage over time on it. nil or the plan.
function C.spreadPlan(cfg, S, act, rec, now)
	local e = C.find(act, "spread")
	if not e or not rec or now - rec.at > e.recentMs or rec.tick <= 0 then
		return nil
	end
	return {elem = e.elem, targets = e.targets, radius = e.radius, ticks = e.ticks, tickMs = e.tickMs,
		damage = floor(rec.tick * e.share / 100)}
end

-- the last tick of yours on a monster is remembered (a bounded table)
function C.noteAfflict(cfg, S, act, id, tick, now)
	if not C.find(act, "spread") then
		return
	end
	local n = 0
	for k, r in pairs(S.afflict) do
		if now - r.at > 10000 then
			S.afflict[k] = nil
		else
			n = n + 1
		end
	end
	if n < cfgOf(cfg).afflictKeep or S.afflict[id] then
		S.afflict[id] = {tick = tick, at = now}
	end
end

-- ------------------------------------------------------------------------------------------------ Necromancer
-- minionPact: multipliers for the minions' hit, their health and the necromancer's own spells
function C.minion(act)
	local e = C.find(act, "minionPact")
	if not e then
		return 1, 1, 1
	end
	return 1 + e.hit / 100, 1 + e.health / 100, 1 - e.own / 100
end

-- ------------------------------------------------------------------------------------------------ text
-- the line of a passive in a language ("en" / "pt-BR"): unique_passives_text.lua
function C.text(cfg, e, lang)
	local T = ChaosUniquePassivesText
	local fn = T and T.family[e.family]
	if not fn then
		return ""
	end
	local pt = lang == "pt-BR" or lang == "pt"
	local body = fn(e, T, pt and 2 or 1)
	local name = pt and (e.namePt or e.name) or e.name
	local s = name .. ": " .. body
	if e.lines and #e.lines < 7 then
		local names = {}
		for i = 1, #e.lines do
			local line = cfgOf(cfg).lines[e.lines:sub(i, i)]
			names[#names + 1] = T.lineName[line][pt and 2 or 1]
		end
		s = s .. " " .. (pt and "Só para: " or "For: ") .. table.concat(names, ", ") .. "."
	end
	return s
end

-- the numbers of a text, in order (the pt-BR line must carry the same numbers in the same order)
function C.numbers(s)
	local t = {}
	for n in tostring(s):gmatch("%d+%.?%d*") do
		t[#t + 1] = n
	end
	return t
end

return C
