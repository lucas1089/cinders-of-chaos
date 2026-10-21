-- Pack combat ("pace"), pure logic (no engine calls): the curves, the level of a monster, random rounding, the loot
-- thinning plan, the multikill chain and the kill-goal helpers. Used by pace.lua, loot.lua, monster_tiers.lua,
-- monster_damage.lua, xpcap.lua, bounty / bestiary / achievements / season pass, tools/gen_codex_data.lua and
-- tools/gen_wiki_data.lua; tested by server/tests/pace_test.lua. Numbers: pace_config.lua.
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.

ChaosPaceCore = ChaosPaceCore or {}
local P = ChaosPaceCore

local floor = math.floor

local function num(v, default)
	v = tonumber(v)
	if not v or v ~= v then
		return default
	end
	return v
end

-- linear between points {{x, y}, ...} (sorted by x), flat beyond the ends; default for an empty list
function P.lin(points, x, default)
	if type(points) ~= "table" or #points == 0 then
		return default
	end
	x = num(x, 0)
	if x <= points[1][1] then
		return points[1][2]
	end
	for i = 2, #points do
		local a, b = points[i - 1], points[i]
		if x <= b[1] then
			return a[2] + (b[2] - a[2]) * (x - a[1]) / (b[1] - a[1])
		end
	end
	return points[#points][2]
end

-- monotone cubic between points {{x, y}, ...} (sorted by x; Fritsch-Carlson slopes: no overshoot, so falling points
-- give a falling curve), flat beyond the ends; default for an empty list. Through every point, smooth between them.
function P.smooth(points, x, default)
	if type(points) ~= "table" or #points == 0 then
		return default
	end
	x = num(x, 0)
	local n = #points
	if n == 1 or x <= points[1][1] then
		return points[1][2]
	end
	if x >= points[n][1] then
		return points[n][2]
	end
	local d, m = {}, {}
	for i = 1, n - 1 do
		d[i] = (points[i + 1][2] - points[i][2]) / (points[i + 1][1] - points[i][1])
	end
	m[1], m[n] = d[1], d[n - 1]
	for i = 2, n - 1 do
		m[i] = (d[i - 1] * d[i] <= 0) and 0 or (d[i - 1] + d[i]) / 2
	end
	for i = 1, n - 1 do
		if d[i] == 0 then
			m[i], m[i + 1] = 0, 0
		else
			local a, b = m[i] / d[i], m[i + 1] / d[i]
			local h = a * a + b * b
			if h > 9 then
				local t = 3 / math.sqrt(h)
				m[i], m[i + 1] = t * a * d[i], t * b * d[i]
			end
		end
	end
	for i = 1, n - 1 do
		local x0, x1 = points[i][1], points[i + 1][1]
		if x <= x1 then
			local h = x1 - x0
			local t = (x - x0) / h
			local t2, t3 = t * t, t * t * t
			return (2 * t3 - 3 * t2 + 1) * points[i][2] + (t3 - 2 * t2 + t) * h * m[i]
				+ (-2 * t3 + 3 * t2) * points[i + 1][2] + (t3 - t2) * h * m[i + 1]
		end
	end
	return points[n][2]
end

local ONE = {health = 1, xp = 1, loot = 1, gold = 1, coins = 1, notable = 1, goal = 1, damage = 1}

-- the factors of a monster of hunting level `level` (scaled: a level of its own). All 1 when the layer is off.
function P.factors(cfg, level, scaled, generated)
	if not cfg or cfg.enabled == false then
		return ONE
	end
	local set = scaled and ((generated and cfg.generated) or cfg.scaled) or cfg.base
	if not set then
		return ONE
	end
	-- calibration (pace_config.lua `scale`): one factor on every point of the experience / loot curves, never above 1
	local sc = cfg.scale or {}
	local function scaled(v, k)
		return math.min(1, v * (tonumber(sc[k]) or 1))
	end
	local loot = scaled(P.lin(set.loot, level, 1), "loot")
	-- loot by monster level (P.levelPlan): the value of coins and junk on top of `loot` (the smooth `coins` curve; a
	-- config without it: the linear `gold` of before), junk kept in kind (`junkKeep`, at most `coins`), notable drops
	-- (`notable`: a share of their own; nil = `loot`)
	local coins = set.coins and P.smooth(set.coins, level, 1) or P.lin(set.gold, level, 1)
	local junkKeep = set.junkKeep and P.smooth(set.junkKeep, level, 1) or nil
	local notable = loot
	if type(set.notable) == "table" then
		notable = math.max(loot, P.smooth(set.notable, level, loot))
	elseif tonumber(set.notable) then
		notable = math.max(loot, tonumber(set.notable))
	end
	return {
		health = P.lin(set.health, level, 1),
		xp = scaled(P.lin(set.xp, level, 1), "xp"),
		loot = loot,
		gold = coins,
		coins = coins,
		junkKeep = junkKeep,
		notable = notable,
		goal = P.lin(set.goal, level, 1),
		damage = P.lin(cfg.damage, level, 1)
	}
end

-- the hunting level and the curve set of a monster. info = {native = Monster:getMonsterLevel(), point = a generated
-- area point's level, pool = ChaosLoot.monsterLevel}. Returns level, scaled, generated (a generated area / dungeon point).
function P.levelOf(cfg, info)
	info = info or {}
	local point = num(info.point, 0)
	if point > 0 then
		return point, true, true
	end
	local native = num(info.native, 0)
	if native > 0 then
		return native, true
	end
	return num(info.pool, 0) * num(cfg and cfg.baseLevelMult, 2), false
end

-- the bounty pool's / bestiary's level estimate from experience and health (gen_bounty_pool.estimate_level)
function P.estimateLevel(exp, health)
	local byExp = 1.6 * math.sqrt(math.max(num(exp, 0), 1))
	local byHp = num(health, 0) / 60
	return math.max(1, floor(math.max(byExp, math.min(byHp, byExp * 1.5)) + 0.5))
end

-- a monster known by its data only (a bounty pool entry {level, exp, health}; a bestiary entry with minLevel/maxLevel):
-- level, scaled. A pool level that is not the estimate of its experience and health is a level-scaled monster's
-- (the middle of its <level min max>).
function P.entryLevel(cfg, e)
	e = e or {}
	local minL, maxL = num(e.minLevel, 0), num(e.maxLevel, 0)
	if minL > 0 and maxL >= minL then
		return floor((minL + maxL) / 2), true
	end
	local lvl = num(e.level, 0)
	if lvl > 0 and e.exp and e.health and P.estimateLevel(e.exp, e.health) ~= lvl then
		return lvl, true
	end
	if lvl <= 0 then
		lvl = P.estimateLevel(e.exp, e.health)
	end
	return lvl * num(cfg and cfg.baseLevelMult, 2), false
end

-- the kill-goal multiplier of a monster known by its data (1 when the layer is off)
function P.goalOfEntry(cfg, e)
	local level, scaled = P.entryLevel(cfg, e)
	return P.factors(cfg, level, scaled).goal
end

-- a kill goal n x mult, rounded to the nearest `step` (at least step, and never below n)
function P.scaleGoal(n, mult, step)
	n, mult, step = num(n, 0), num(mult, 1), num(step, 1)
	if mult <= 1 or n <= 0 then
		return n
	end
	if step < 1 then
		step = 1
	end
	local v = floor(n * mult / step + 0.5) * step
	if v < step then
		v = step
	end
	if v < n then
		v = n
	end
	return v
end

-- x rounded down or up at random so that the expected value is x (rnd() in [0, 1))
function P.roundRandom(x, rnd)
	x = num(x, 0)
	local base = floor(x)
	local frac = x - base
	if frac > 0 and (rnd or math.random)() < frac then
		return base + 1
	end
	return base
end

-- experience x f with random rounding; a kill that gave 1 or more still gives at least 1
function P.scaleExp(exp, f, rnd)
	exp, f = num(exp, 0), num(f, 1)
	if exp <= 0 or f == 1 then
		return exp
	end
	local v = P.roundRandom(exp * f, rnd)
	if v < 1 and exp >= 1 then
		v = 1
	end
	return v
end

-- the new max health (at least 1)
function P.scaleHealth(maxHealth, f)
	local v = floor(num(maxHealth, 0) * num(f, 1) + 0.5)
	if v < 1 then
		v = 1
	end
	return v
end

-- loot thinning of a corpse: items = list of {count =, stackable = bool}. Returns a list (same order) of the count to
-- keep (0 = remove): a stack keeps count x f rounded at random, any other item stays with chance f. f >= 1 keeps all.
function P.thinPlan(items, f, rnd)
	f = num(f, 1)
	rnd = rnd or math.random
	local out = {}
	for i, it in ipairs(items or {}) do
		local count = num(it.count, 1)
		if f >= 1 then
			out[i] = count
		elseif it.stackable then
			out[i] = P.roundRandom(count * f, rnd)
		else
			out[i] = rnd() < f and count or 0
		end
	end
	return out
end

-- ------------------------------------------------------------------ loot by monster level
-- Owner 2026-10-21 ("Ajuste o loot de acordo com o lvl só monstro"): what a corpse keeps depends on the monster's level
-- only (P.levelOf: its own level, a generated point's, else 2 x the pool estimate; the curve set is the monster's kind),
-- never on who killed it. server/README.md "Loot by monster level"; numbers: pace_config.lua `lootLevel` and the sets'
-- `coins` / `junkKeep` / `notable`; the economy model: tools/loot_model.lua.

-- is a corpse item notable (kept whole, x f.notable only): a gear piece with a stock rarity of Rare or better (a stored
-- rarity >= notableRarity: the old ids 4-15 all map to Rare, Legendary or Divine), or a rare drop of the monster's loot
-- table (chance per 100000 at most notableChance). Coins never are.
function P.isNotable(ll, it)
	if not it or it.class == "coin" then
		return false
	end
	ll = ll or {}
	if it.class == "gear" and num(it.rarity, 0) >= num(ll.notableRarity, 4) then
		return true
	end
	local ch = tonumber(it.chance)
	return ch ~= nil and ch > 0 and ch <= num(ll.notableChance, 1000)
end

-- the corpse plan. ll = pace_config.lua `lootLevel`; f = factors (P.factors: loot, coins, junkKeep, notable; the
-- caller may multiply loot and notable by a pocket's factor). items = list of {count, stackable, class = "coin" | "junk"
-- | "gear" | "other", value = gold per unit (coins 1 / 100 / 10000, junk its NPC price), rarity = stored rarity, chance =
-- the loot table's chance}. Returns keep (the count to keep per item, same order; a coin item is always 0) and pay (whole
-- gold to put back as coins, P.coinStacks).
--   coins    their value x loot x coins comes back as coins: a corpse that had coins shows coins
--   junk     (NPC-sellable, not gear) is worth sv = loot x coins of its value. It stays in kind with chance sk = loot x
--            junkKeep (a single item: at most sv); a stack that stays keeps count x min(1, sv / sk), rounded at random.
--            Taken out, it pays its value x (sv - sk) / (1 - sk) as coins when sk < sv. The expected value is sv either way.
--   notable  stays whole with chance f.notable
--   gear, other (orbs, gems, keys, unsellables): P.thinPlan with loot, as before
--   floor    a corpse that would show nothing (no item kept, no coin) although junk dropped is paid sv x the value of
--            that junk as coins: an emptied corpse shows what its junk was worth (the coins curve pays for it)
-- pay is rounded at random to whole gold. Shares of 1 or more keep everything (pay = the coins' value).
function P.levelPlan(ll, f, items, rnd)
	rnd = rnd or math.random
	f = f or ONE
	local loot = num(f.loot, 1)
	local sv = math.min(1, loot * num(f.coins, 1))
	-- no junkKeep (a set without the curve): a stack always stays with count x sv, a single item with chance sv (the old
	-- thinning)
	local skStack = f.junkKeep and math.min(1, loot * num(f.junkKeep, 1)) or 1
	local notable = num(f.notable, loot)
	local keep, pay, removed = {}, 0, 0
	for i, it in ipairs(items or {}) do
		local count = num(it.count, 1)
		local value = num(it.value, 0)
		if it.class == "coin" then
			keep[i] = 0
			pay = pay + count * value * sv
		elseif P.isNotable(ll, it) then
			keep[i] = (notable >= 1 or rnd() < notable) and count or 0
		elseif it.class == "junk" then
			local sk = it.stackable and skStack or math.min(sv, skStack)
			if sv >= 1 then
				keep[i] = count
			elseif sk > 0 and rnd() < sk then
				keep[i] = sk > sv and P.roundRandom(count * sv / sk, rnd) or count
			else
				keep[i] = 0
				if sv > sk then
					pay = pay + count * value * (sv - sk) / (1 - sk)
				end
			end
			if keep[i] <= 0 then
				removed = removed + count * value * sv
			end
		else
			keep[i] = P.thinPlan({it}, loot, rnd)[1]
		end
	end
	pay = P.roundRandom(pay, rnd)
	if pay <= 0 and removed > 0 then
		local shows = false
		for i = 1, #keep do
			if keep[i] > 0 then
				shows = true
				break
			end
		end
		if not shows then
			pay = math.max(1, P.roundRandom(removed, rnd))
		end
	end
	return keep, pay
end

-- whole gold as coin stacks, largest first: list of {id, count} (crystal 10000, platinum 100, gold 1)
function P.coinStacks(gold)
	gold = floor(num(gold, 0))
	local out = {}
	for _, c in ipairs({{2160, 10000}, {2152, 100}, {2148, 1}}) do
		local n = floor(gold / c[2])
		if n > 0 then
			out[#out + 1] = {c[1], n}
			gold = gold - n * c[2]
		end
	end
	return out
end

-- a chance (any unit) x f, for the per-kill rolls (ambush, goblin): f >= 1 or off leaves it
function P.scaleChance(chance, f)
	f = num(f, 1)
	if f >= 1 then
		return chance
	end
	return num(chance, 0) * f
end

-- multikill bonus percent for a chain of n kills
function P.multikillPercent(cfg, n)
	local mk = cfg and cfg.multikill
	if not mk or mk.enabled == false or (cfg.enabled == false) then
		return 0
	end
	local best = 0
	for _, s in ipairs(mk.steps or {}) do
		if n >= s.kills and s.percent > best then
			best = s.percent
		end
	end
	return best
end

-- one kill into a player's chain. st = the player's state table ({} at first), now in ms, exp = this kill's experience
-- as it enters the bonus (after the pace curve), tierXp = the monster tier's experience multiplier that the later tier
-- callback applies to the returned value (1 for a normal monster). Returns the experience to give for this kill (its
-- own bonus plus the step-up on the chain's earlier kills), the chain length and the chain's percent.
function P.multikill(cfg, st, now, exp, tierXp)
	exp, tierXp = num(exp, 0), num(tierXp, 1)
	if tierXp <= 0 then
		tierXp = 1
	end
	local mk = cfg and cfg.multikill
	if not mk or mk.enabled == false or cfg.enabled == false or exp <= 0 then
		return exp, 0, 0
	end
	local window = num(mk.windowMs, 3000)
	if not st.last or now - st.last > window or now < st.last then
		st.n, st.sum, st.percent = 0, 0, 0
	end
	st.last = now
	st.n = st.n + 1
	local pct = P.multikillPercent(cfg, st.n)
	-- the earlier kills were paid at st.percent; this kill pays the difference on them, divided by this kill's tier
	-- multiplier, which the tier callback applies to the returned value
	local extra = exp * pct / 100 + st.sum * (pct - st.percent) / 100 / tierXp
	st.sum = st.sum + exp * tierXp
	st.percent = pct
	return exp + extra, st.n, pct
end

-- kill credit for the generic kill counters (achievements, season pass, journey): every paced kill adds 1 / goal to the
-- player's accumulator; returns how many whole kills it completed (0, 1, rarely more). acc = {v = number}.
function P.killCredit(acc, goal)
	goal = num(goal, 1)
	if goal <= 1 then
		return 1
	end
	acc.v = num(acc.v, 0) + 1 / goal
	local whole = floor(acc.v + 1e-9)
	acc.v = acc.v - whole
	return whole
end

-- pack cleave: the cleave of a vocation ({percent, targets} or nil) and its damage for a hit of `amount`
function P.cleaveOf(cfg, vocationId)
	local c = cfg and cfg.cleave
	if not c or c.enabled == false or cfg.enabled == false or not c.byVocation then
		return nil
	end
	local e = c.byVocation[tonumber(vocationId) or -1]
	if not e or math.max(tonumber(e.percent) or 0, tonumber(e.high) or 0) <= 0 or (tonumber(e.targets) or 0) <= 0 then
		return nil
	end
	return e
end

-- the share of a cleave entry at a character level: `percent` up to the table's fromLevel, linear to `high` at toLevel,
-- `high` from there (an entry without `high` keeps `percent` at every level)
function P.cleavePercent(e, level, c)
	local lo = num(e and e.percent, 0)
	local hi = e and e.high ~= nil and num(e.high, lo) or lo
	local from, to = num(c and c.fromLevel, 300), num(c and c.toLevel, 1000)
	level = num(level, from)
	if hi == lo or level <= from or to <= from then
		return lo
	end
	if level >= to then
		return hi
	end
	return lo + (hi - lo) * (level - from) / (to - from)
end

function P.cleaveDamage(amount, percent)
	return floor(math.abs(num(amount, 0)) * num(percent, 0) / 100)
end

-- the cleave's targets: list of {id, x, y} candidates (the hit monster excluded by the caller), the hit monster at
-- (cx, cy); up to n within radius (Chebyshev), nearest first, ties by id
function P.cleaveTargets(cands, cx, cy, radius, n)
	local list = {}
	for _, c in ipairs(cands or {}) do
		local d = math.max(math.abs(c.x - cx), math.abs(c.y - cy))
		if d <= radius then
			list[#list + 1] = {c = c, d = d}
		end
	end
	table.sort(list, function(a, b)
		if a.d ~= b.d then
			return a.d < b.d
		end
		return a.c.id < b.c.id
	end)
	local out = {}
	for i = 1, math.min(n, #list) do
		out[i] = list[i].c
	end
	return out
end

return P
