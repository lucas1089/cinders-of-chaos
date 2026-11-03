-- Death advice (O371), pure logic (no engine calls): the facts of a death (from the death recap's rolling log and the
-- recap built from it) and the 1-3 short tips they lead to. Rules and numbers: deathrecap_config.lua `advice`; the
-- engine part is in deathrecap.lua (healing and potion hooks, the monster level, the resistances); the client words
-- each tip in English and pt-BR (game_deathrecap deathrecaplogic.lua L.tips). Tested by server/tests/deathadvice_test.lua.
-- Lua 5.1 / LuaJIT and 5.3 compatible.
--
-- A tip on the wire (recap.tips, a list in rule order; short keys):
--   {k = "lvl", d = levels above}                the monsters that dealt most of the damage were far above the character
--   {k = "res", el = element, r = resist %, s = share %}   one element dealt most of it and the character barely resists it
--   {k = "pot"}                                   no potion in a long enough fight, and little healing
--   {k = "heal", s = healing share %}             potions drunk, but the healing covered little of the damage
--   {k = "pack", n = monsters}                    many monsters hit the character
-- The rolling log (ChaosDeathRecap.newLog) gets three more parts here: lv (attacker key -> monster level), hl (healing
-- received: {t, a}), po (potions drunk: times).

ChaosDeathAdvice = ChaosDeathAdvice or {}
local A = ChaosDeathAdvice
local floor, max, min = math.floor, math.max, math.min

local function num(v)
	v = tonumber(v)
	if v and v == v and v ~= math.huge and v ~= -math.huge then
		return v
	end
	return nil
end

-- ---------------------------------------------------------------- the log parts
-- a bounded list of {t, a} (or times): the oldest goes beyond cap
local function push(list, entry, cap)
	list[#list + 1] = entry
	while #list > cap do
		table.remove(list, 1)
	end
end

function A.addHeal(log, now, amount, cap)
	amount = num(amount)
	if not log or not amount or amount <= 0 then
		return
	end
	log.hl = log.hl or {}
	push(log.hl, {t = now, a = amount}, cap or 60)
end

function A.addPotion(log, now, cap)
	if not log then
		return
	end
	log.po = log.po or {}
	push(log.po, now, cap or 30)
end

-- the level of a monster attacker, taken once per key (bounded like the looks)
function A.wantLevel(log, key, bound)
	log.lv = log.lv or {}
	log.nLv = log.nLv or 0
	return log.lv[key] == nil and log.nLv < (bound or 20)
end

function A.setLevel(log, key, level)
	log.lv = log.lv or {}
	if log.lv[key] == nil then
		level = num(level)
		log.lv[key] = (level and level > 0) and floor(level) or false
		log.nLv = (log.nLv or 0) + 1
	end
end

-- ---------------------------------------------------------------- resistances
-- the absorb of worn items (a list of percents, each on what the one before left) and the absorb storages (percent),
-- held at cap: the rule of engine patch 0049 when ChaosItemMods.effectiveAbsorb is not loaded
function A.absorb(items, storage, cap)
	local left = 1
	for _, p in ipairs(items or {}) do
		left = left * (1 - max(0, min(100, num(p) or 0)) / 100)
	end
	left = left * (1 - max(0, min(100, num(storage) or 0)) / 100)
	return min(cap or 75, (1 - left) * 100)
end

-- what is left of a hit after the absorb (equipment and storages, percent) and a gem resistance (percent, taken off
-- after): the resistance in whole percent, 0..100
function A.combine(absorbPct, gemPct)
	local a = max(0, min(100, num(absorbPct) or 0)) / 100
	local g = max(0, min(100, num(gemPct) or 0)) / 100
	return floor((1 - (1 - a) * (1 - g)) * 100 + 1e-9)
end

-- ---------------------------------------------------------------- facts
-- the facts of a death. log: the rolling log (hits with k, kind, m, a, t, cid); deathAt: ms; recap: ChaosDeathRecap.build's;
-- level: the character's; resistOf(el) -> percent (or nil: unknown). Returns
-- {pl, dur, tot, hp, heal, pot, top = {el, share, r}, high = {share, gap}, pack}
function A.facts(log, deathAt, recap, level, windowMs, resistOf)
	recap = type(recap) == "table" and recap or {}
	local f = {pl = num(level) or num(recap.lvl) or 0, dur = num(recap.dur) or 0, tot = num(recap.tot) or 0,
		hp = num(recap.hp) or 0, heal = 0, pot = 0, pack = 0}
	local from = deathAt - windowMs
	-- monsters: damage by key, distinct creatures
	local byKey, ids, monsterTot = {}, {}, 0
	for _, h in ipairs(log and log.buf and ChaosDeathRecap.hits(log) or {}) do
		if h.t >= from and h.t <= deathAt and h.kind == "c" and not h.m then
			byKey[h.k] = (byKey[h.k] or 0) + h.a
			monsterTot = monsterTot + h.a
			if h.cid and not ids[h.cid] then
				ids[h.cid] = true
				f.pack = f.pack + 1
			end
		end
	end
	-- the monsters far above the character: their share of all damage, and the gap of the one that hit hardest
	local lv = log and log.lv or {}
	local highDmg, bestDmg, gap = 0, -1, 0
	for key, dmg in pairs(byKey) do
		local l = lv[key]
		if l then
			local d = l - f.pl
			if d > 0 then
				highDmg = highDmg + dmg -- every monster above the character; the rule reads the gap
				if dmg > bestDmg then
					bestDmg, gap = dmg, d
				end
			end
		end
	end
	f.high = {share = f.tot > 0 and floor(highDmg * 100 / f.tot + 0.5) or 0, gap = gap}
	-- healing and potions in the window
	for _, e in ipairs(log and log.hl or {}) do
		if e.t >= from and e.t <= deathAt then
			f.heal = f.heal + e.a
		end
	end
	for _, t in ipairs(log and log.po or {}) do
		if t >= from and t <= deathAt then
			f.pot = f.pot + 1
		end
	end
	-- the element that dealt the most
	local topEl, topA = nil, 0
	for el, a in pairs(type(recap.el) == "table" and recap.el or {}) do
		a = num(a) or 0
		if a > topA or (a == topA and topEl and el < topEl) then
			topEl, topA = el, a
		end
	end
	if topEl and f.tot > 0 then
		local r = resistOf and resistOf(topEl) or nil
		f.top = {el = topEl, share = floor(topA * 100 / f.tot + 0.5), r = num(r)}
	end
	return f
end

-- ---------------------------------------------------------------- tips
-- the tips of the facts, in rule order, at most cfg.max
function A.tips(f, cfg)
	cfg = cfg or {}
	local out = {}
	if cfg.enabled == false or type(f) ~= "table" or (f.tot or 0) <= 0 then
		return out
	end
	local cap = cfg.max or 3
	local function add(t)
		if #out < cap then
			out[#out + 1] = t
		end
	end
	local high = f.high or {}
	if (high.gap or 0) >= (cfg.levelGap or 30) and (high.share or 0) >= (cfg.levelShare or 30) then
		add({k = "lvl", d = floor(high.gap)})
	end
	local top = f.top
	local els = cfg.resElements or {}
	if top and els[top.el] and top.r and top.share >= (cfg.resShare or 40) and top.r < (cfg.resLow or 10) then
		add({k = "res", el = top.el, r = max(0, floor(top.r)), s = top.share})
	end
	local healShare = (f.hp or 0) > 0 and floor((f.heal or 0) * 100 / f.hp + 0.5) or 100
	if (f.pot or 0) == 0 then
		if (f.dur or 0) >= (cfg.potMinMs or 4000) and healShare < (cfg.potHealShare or 30) then
			add({k = "pot"})
		end
	elseif (f.dur or 0) >= (cfg.healMinMs or 8000) and healShare < (cfg.healShare or 25) then
		add({k = "heal", s = healShare})
	end
	if (f.pack or 0) >= (cfg.packSize or 5) then
		add({k = "pack", n = f.pack})
	end
	return out
end

return A
