-- The Ember Descent: the rules without engine calls (tested by server/tests/descent_test.lua with LuaJIT and Lua 5.3).
-- descent.lua does the instance, the monsters, the hooks, the database and the protocol; descent_config.lua has the
-- numbers. Everything random here draws from a seeded generator, so one seed always gives the same run: the rooms, the
-- monster picks of a room and the boons offered (the weekly run gives everyone the same descent).
--
--   ChaosDescentCore.rng(seed)                       a generator: r:next() 0..2^31-2, r:int(a, b), r:chance(pct)
--   ChaosDescentCore.hash(text)                      a seed from a string (the same in LuaJIT and Lua 5.3)
--   ChaosDescentCore.weekKey(t, hour) / weekSeed(week) / runSeed(guid, t, n)
--   ChaosDescentCore.generate(cfg, seed, themeCount) the rooms of a run {seed, count, rooms = {{index, type, theme}}}
--   ChaosDescentCore.roomRng(seed, room, salt)       the generator of one room (spawns, offers)
--   ChaosDescentCore.escalation(cfg, depth, level)   level window, health / damage scaling, tier mix of a depth
--   ChaosDescentCore.rollTier(esc, r) / eliteTier(cfg, depth, r)
--   ChaosDescentCore.roomPlan(cfg, kind, depth, players, swarmPct)   waves and monsters per wave
--   ChaosDescentCore.rollOffer(cfg, r, held, depth, opts)            three boons (and maybe a curse)
--   ChaosDescentCore.newState() / applyPick(cfg, st, offer, index, takeCurse) / cleanse(cfg, st)
--   ChaosDescentCore.effects(cfg, st)                the numbers of every boon and curse a player holds
--   ChaosDescentCore.partyEffects(cfg, states)       the party-wide curses (swarm, frenzy)
--   ChaosDescentCore.hitOut(fx, amount, physical, targetPct, r) / hitIn(fx, amount, ward) / healIn(fx, amount)
--   ChaosDescentCore.embers(fx, base) / price(cfg, ware, depth)
--   ChaosDescentCore.reward(cfg, depth, cleared, level, rewardPct) / pickUnique(cfg, depth, r)
--   ChaosDescentCore.titles(cfg, best, cleared) / freeState(cfg, row, now) / validate(cfg)
--   ChaosDescentCore.boonText(def, stacks) / curseText(def)
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible: only integer maths below 2^53, no 5.3-only syntax.

if not ChaosBounty or not ChaosBounty.week then
	dofile("data/scripts/chaos/bounty_core.lua")
end

ChaosDescentCore = ChaosDescentCore or {}
local D = ChaosDescentCore
local floor, max, min = math.floor, math.max, math.min

local MOD = 2147483647 -- 2^31 - 1 (Park-Miller): products with 48271 stay below 2^47
local MULT = 48271

-- ---------------------------------------------------------------- random
local Rng = {}
Rng.__index = Rng

function Rng:next()
	self.s = (self.s * MULT) % MOD
	return self.s
end

-- a whole number a..b (both included)
function Rng:int(a, b)
	if b <= a then
		return a
	end
	return a + self:next() % (b - a + 1)
end

-- true with `pct` percent (0..100, fractions allowed)
function Rng:chance(pct)
	if (pct or 0) <= 0 then
		return false
	end
	return self:next() % 100000 < floor(pct * 1000 + 0.5)
end

-- an entry of rows = {{value, weight}, ...}
function Rng:weighted(rows)
	local total = 0
	for _, row in ipairs(rows) do
		total = total + max(0, row[2])
	end
	if total <= 0 then
		return nil
	end
	local roll = self:int(1, total)
	for _, row in ipairs(rows) do
		roll = roll - max(0, row[2])
		if roll <= 0 then
			return row[1]
		end
	end
	return rows[#rows][1]
end

function D.rng(seed)
	local s = floor(tonumber(seed) or 1) % MOD
	if s <= 0 then
		s = s + MOD - 1
	end
	local r = setmetatable({s = s}, Rng)
	r:next() -- one step so that close seeds part ways at once
	return r
end

function D.hash(text)
	local h = 5381
	text = tostring(text)
	for i = 1, #text do
		h = (h * 33 + text:byte(i)) % MOD
	end
	return h > 0 and h or 1
end

function D.weekKey(t, hour)
	return ChaosBounty.week(t, {rollHour = hour or 6})
end

function D.weekSeed(week)
	return D.hash("ember descent week " .. tostring(week))
end

function D.runSeed(guid, t, n)
	return D.hash(string.format("ember descent %d %d %d", tonumber(guid) or 0, tonumber(t) or 0, tonumber(n) or 0))
end

-- the generator of one room of a run (salt: "spawn", "offer:<player slot>:<n>" ...)
function D.roomRng(seed, room, salt)
	return D.rng(D.hash(string.format("%d:%d:%s", seed, room, tostring(salt or ""))))
end

-- ---------------------------------------------------------------- the rooms
local SPECIAL = {treasure = true, shrine = true, merchant = true}

function D.generate(cfg, seed, themeCount)
	local r = D.rng(seed)
	local count = r:int(cfg.rooms.min, cfg.rooms.max)
	themeCount = max(1, themeCount or 1)
	local rooms = {}
	for i = 1, count do
		local kind
		if i == 1 then
			kind = "combat"
		elseif i == count then
			kind = "boss"
		elseif i == count - 1 then
			kind = "merchant"
		else
			local rows = {}
			local prev = rooms[i - 1].type
			for _, w in ipairs(cfg.roomWeights) do
				local ok = not (w[1] == "elite" and i < cfg.eliteFrom)
				ok = ok and not (SPECIAL[w[1]] and w[1] == prev)
				-- the merchant waits for the room before the boss: no merchant right before it
				ok = ok and not (w[1] == "merchant" and i == count - 2)
				if ok then
					rows[#rows + 1] = w
				end
			end
			kind = r:weighted(rows) or "combat"
		end
		local theme = r:int(1, themeCount)
		if i > 1 and themeCount > 1 and theme == rooms[i - 1].theme then
			theme = theme % themeCount + 1 -- never the same floor twice in a row
		end
		rooms[i] = {index = i, type = kind, theme = theme}
	end
	return {seed = seed, count = count, rooms = rooms}
end

D.ROOM_NAMES = {combat = "Combat", elite = "Elite", treasure = "Treasure", shrine = "Shrine", merchant = "Merchant",
	boss = "Boss"}

-- ---------------------------------------------------------------- escalation
local function round2(v)
	return floor(v * 100 + 0.5) / 100
end

function D.escalation(cfg, depth, level)
	local e = cfg.escalation
	depth = max(1, depth or 1)
	level = max(1, level or 1)
	local lo = floor(level * (e.lo + e.perDepth * depth))
	local hi = floor(level * (e.hi + e.perDepth * depth))
	lo = min(e.maxLevel, max(e.minLevel, lo))
	hi = min(e.maxLevel, max(lo + 10, hi))
	local tiers = {}
	for _, k in ipairs({"magic", "rare", "legendary"}) do
		local t = e.tiers[k]
		tiers[k] = max(0, round2(t[1] + t[2] * depth))
	end
	return {window = {lo, hi}, health = round2(1 + e.health * (depth - 1)), damage = round2(1 + e.damage * (depth - 1)),
		tiers = tiers}
end

-- the tier of one monster (nil = normal)
function D.rollTier(esc, r)
	local roll = r:next() % 100000
	local acc = 0
	for _, k in ipairs({"legendary", "rare", "magic"}) do
		acc = acc + floor((esc.tiers[k] or 0) * 1000 + 0.5)
		if roll < acc then
			return k
		end
	end
	return nil
end

function D.eliteTier(cfg, depth, r)
	local el = cfg.elite
	return r:chance(min(100, el.legendaryBase + el.legendaryPerDepth * depth)) and "legendary" or "rare"
end

-- waves and monsters per wave of a room; swarmPct: the Swarm curses of the party
function D.roomPlan(cfg, kind, depth, players, swarmPct)
	players = max(1, players or 1)
	local swarm = 1 + (swarmPct or 0) / 100
	if kind == "combat" then
		local w, s = cfg.waves, cfg.size
		local size = s.base + floor(depth * s.perDepth) + s.perExtraPlayer * (players - 1)
		return {waves = min(w.max, w.base + floor(depth * w.perDepth)), size = min(s.max, floor(size * swarm + 0.5))}
	elseif kind == "elite" then
		local el = cfg.elite
		local size = el.base + floor(depth * el.perDepth) + el.perExtraPlayer * (players - 1)
		return {waves = 1, size = floor(size * swarm + 0.5), elite = true}
	elseif kind == "treasure" then
		return {waves = 1, size = floor((cfg.treasure.guards + (players - 1)) * swarm + 0.5)}
	elseif kind == "boss" then
		return {waves = 1, size = 1, boss = true}
	end
	return {waves = 0, size = 0}
end

-- health multiplier of the boss for a party
function D.bossHealth(cfg, players)
	return cfg.boss.healthMult + cfg.boss.perExtraPlayer * (max(1, players or 1) - 1)
end

-- ---------------------------------------------------------------- boons and curses
function D.boonDef(cfg, key)
	for _, b in ipairs(cfg.boons) do
		if b.key == key then
			return b
		end
	end
	return nil
end

function D.curseDef(cfg, key)
	for _, c in ipairs(cfg.curses) do
		if c.key == key then
			return c
		end
	end
	return nil
end

-- the description with the numbers of `stacks` stacks
function D.boonText(def, stacks)
	stacks = max(1, stacks or 1)
	local v = def.value
	if def.kind ~= "convert" and def.kind ~= "phoenix" then
		v = v * stacks
	end
	local ok, text = pcall(string.format, def.desc, v, def.extra or 0)
	return ok and text or def.desc
end

function D.curseText(def)
	local ok, text = pcall(string.format, def.desc, def.value)
	return ok and text or def.desc
end

function D.newState()
	return {boons = {}, order = {}, curses = {}, rewardPct = 0, embers = 0, picks = 0}
end

local function stacksOf(st, key)
	return st and st.boons and st.boons[key] or 0
end

-- three different boons that are not at their maximum (fewer when fewer are left), and maybe a curse.
-- opts = {curse = true (a curse may come), cards = 3}. Returns {cards = {key...}, curse = key or nil}
function D.rollOffer(cfg, r, st, depth, opts)
	opts = opts or {}
	local pool = {}
	local brands = 0
	for _, b in ipairs(cfg.boons) do
		if b.kind == "convert" and stacksOf(st, b.key) > 0 then
			brands = brands + 1
		end
	end
	for _, b in ipairs(cfg.boons) do
		-- one brand (damage conversion) at a time: the others are not offered once one is held
		local blocked = b.kind == "convert" and brands > 0 and stacksOf(st, b.key) == 0
		if stacksOf(st, b.key) < b.max and not blocked then
			pool[#pool + 1] = {b.key, b.weight}
		end
	end
	local cards = {}
	for _ = 1, opts.cards or 3 do
		local key = r:weighted(pool)
		if not key then
			break
		end
		cards[#cards + 1] = key
		for i, row in ipairs(pool) do
			if row[1] == key then
				table.remove(pool, i)
				break
			end
		end
	end
	local curse
	if opts.curse and depth >= cfg.curseFrom and r:chance(cfg.curseChance) then
		local free = {}
		for _, c in ipairs(cfg.curses) do
			local held = false
			for _, k in ipairs(st and st.curses or {}) do
				if k == c.key then
					held = true
				end
			end
			if not held then
				free[#free + 1] = c.key
			end
		end
		if #free > 0 then
			curse = free[r:int(1, #free)]
		end
	end
	return {cards = cards, curse = curse}
end

-- the pick of card `index` (and the curse when takeCurse): returns true, the boon key (and the curse key), or false
function D.applyPick(cfg, st, offer, index, takeCurse)
	local key = offer and offer.cards and offer.cards[tonumber(index) or 0]
	local def = key and D.boonDef(cfg, key)
	if not def then
		return false
	end
	if stacksOf(st, key) == 0 then
		st.order[#st.order + 1] = key
	end
	st.boons[key] = min(def.max, stacksOf(st, key) + 1)
	st.picks = st.picks + 1
	local curse
	if takeCurse and offer.curse then
		local c = D.curseDef(cfg, offer.curse)
		if c then
			st.curses[#st.curses + 1] = c.key
			st.rewardPct = st.rewardPct + c.reward
			st.embers = st.embers + c.embers
			curse = c.key
		end
	end
	return true, key, curse
end

-- the newest curse goes, with its reward bonus; returns its key or nil
function D.cleanse(cfg, st)
	local key = table.remove(st.curses)
	if not key then
		return nil
	end
	local c = D.curseDef(cfg, key)
	if c then
		st.rewardPct = max(0, st.rewardPct - c.reward)
	end
	return key
end

-- what a player's boons and curses do, summed (percent values unless noted)
function D.effects(cfg, st)
	local fx = {damage = 0, leech = 0, burst = 0, burstRadius = 0, harvest = 0, echo = 0, echoPct = 0, ward = 0,
		wardEvery = 0, speed = 0, crit = 0, critPct = 0, execute = 0, executeBelow = 0, reduce = 0, thorns = 0,
		phoenix = 0, tithe = 0, taken = 0, healing = 0, purse = 0}
	for _, b in ipairs(cfg.boons) do
		local n = stacksOf(st, b.key)
		if n > 0 then
			local k = b.kind
			if k == "damage" then
				fx.damage = fx.damage + b.value * n
			elseif k == "convert" then
				fx.convert = {element = b.element, pct = b.value, extra = b.extra or 0}
			elseif k == "leech" then
				fx.leech = fx.leech + b.value * n
			elseif k == "burst" then
				fx.burst, fx.burstRadius = fx.burst + b.value * n, b.extra or 1
			elseif k == "harvest" then
				fx.harvest = fx.harvest + b.value * n
			elseif k == "echo" then
				fx.echo, fx.echoPct = fx.echo + b.value * n, b.extra or 50
			elseif k == "ward" then
				fx.ward, fx.wardEvery = fx.ward + b.value * n, b.extra or 20
			elseif k == "speed" then
				fx.speed = fx.speed + b.value * n
			elseif k == "crit" then
				fx.crit, fx.critPct = fx.crit + b.value * n, b.extra or 50
			elseif k == "execute" then
				fx.execute, fx.executeBelow = fx.execute + b.value * n, b.extra or 30
			elseif k == "reduce" then
				fx.reduce = fx.reduce + b.value * n
			elseif k == "thorns" then
				fx.thorns = fx.thorns + b.value * n
			elseif k == "phoenix" then
				fx.phoenix = b.value
			elseif k == "tithe" then
				fx.tithe = fx.tithe + b.value * n
			end
		end
	end
	for _, key in ipairs(st and st.curses or {}) do
		local c = D.curseDef(cfg, key)
		if c then
			if c.kind == "taken" then
				fx.taken = fx.taken + c.value
			elseif c.kind == "healing" then
				fx.healing = fx.healing + c.value
			elseif c.kind == "purse" then
				fx.purse = fx.purse + c.value
			end
		end
	end
	fx.reduce = min(fx.reduce, 60)
	fx.crit = min(fx.crit, 75)
	fx.echo = min(fx.echo, 75)
	return fx
end

-- the curses that act on the whole party (swarm: percent more monsters, frenzy: speed of the monsters)
function D.partyEffects(cfg, states)
	local p = {swarm = 0, frenzy = 0}
	for _, st in pairs(states or {}) do
		for _, key in ipairs(st.curses or {}) do
			local c = D.curseDef(cfg, key)
			if c and c.kind == "swarm" then
				p.swarm = p.swarm + c.value
			elseif c and c.kind == "frenzy" then
				p.frenzy = p.frenzy + c.value
			end
		end
	end
	return p
end

-- a hit a player deals to a Descent monster: {amount, converted (the part that changes type), element, crit, echo}
-- amount: the whole damage (positive); physical: the hit is physical; targetPct: the target's health percent before it
function D.hitOut(fx, amount, physical, targetPct, r)
	amount = max(0, amount or 0)
	local mult = 100 + fx.damage
	if fx.execute > 0 and (targetPct or 100) < fx.executeBelow then
		mult = mult + fx.execute
	end
	local crit = fx.crit > 0 and r and r:chance(fx.crit) or false
	if crit then
		mult = mult + fx.critPct
	end
	local total = floor(amount * mult / 100)
	local converted = 0
	if physical and fx.convert then
		converted = floor(total * fx.convert.pct / 100)
		local bonus = floor(converted * fx.convert.extra / 100)
		total = total + bonus
		converted = converted + bonus
	end
	local echo = fx.echo > 0 and r and r:chance(fx.echo) or false
	return {amount = total, converted = converted, element = fx.convert and fx.convert.element or nil, crit = crit,
		echo = echo and floor(total * fx.echoPct / 100) or 0,
		leech = floor(total * fx.leech / 100)}
end

-- a hit a player takes: the amount after Stoneskin and Frailty, what the ward took and what is left of the ward
function D.hitIn(fx, amount, ward)
	amount = max(0, amount or 0)
	local a = floor(amount * (100 - fx.reduce + fx.taken) / 100)
	ward = max(0, ward or 0)
	local absorbed = min(ward, a)
	return a - absorbed, absorbed, ward - absorbed
end

function D.healIn(fx, amount)
	return floor(max(0, amount or 0) * max(0, 100 - fx.healing) / 100)
end

-- embers of `base` for a player (Ember Tithe, Ashen Purse)
function D.embers(fx, base)
	return max(0, floor((base or 0) * (100 + fx.tithe - fx.purse) / 100))
end

function D.price(cfg, ware, depth)
	return ware.base + ware.perDepth * max(1, depth or 1)
end

function D.ware(cfg, key)
	for _, w in ipairs(cfg.wares) do
		if w.key == key then
			return w
		end
	end
	return nil
end

-- ---------------------------------------------------------------- rewards
-- depth: rooms cleared; cleared: the boss is slain. Returns {gold, items = {{id, count}}, uniqueChance (per 10000)}
function D.reward(cfg, depth, cleared, level, rewardPct)
	local rw = cfg.rewards
	depth = max(0, depth or 0)
	local mult = (cleared and rw.clearMult or 1) * (100 + (rewardPct or 0)) / 100
	local g = rw.gold
	local gold = (g.perDepth * depth + g.square * depth * depth) * (1 + (level or 1) / g.levelDiv)
	local out = {gold = floor(gold * mult), items = {}, uniqueChance = 0}
	for _, o in ipairs(rw.orbs) do
		local n = floor(floor(depth / o.every) * mult)
		if n > 0 then
			out.items[#out.items + 1] = {id = o.id, count = n}
		end
	end
	local u = rw.unique
	if depth >= u.from then
		local c = u.perDepth * (depth - u.from + 1) + (cleared and u.clear or 0)
		out.uniqueChance = min(u.max, floor(c * (100 + (rewardPct or 0)) / 100))
	end
	return out
end

-- a run-exclusive unique the depth has opened (nil when none)
function D.pickUnique(cfg, depth, r)
	local list = {}
	for _, u in ipairs(cfg.rewards.uniques) do
		if depth >= u.minDepth then
			list[#list + 1] = u
		end
	end
	if #list == 0 then
		return nil
	end
	return list[r:int(1, #list)]
end

-- the titles of a best depth / a full clear
function D.titles(cfg, best, cleared)
	local list = {}
	for _, t in ipairs(cfg.titles) do
		if (t.clear and cleared) or (t.depth and (best or 0) >= t.depth) then
			list[#list + 1] = t
		end
	end
	return list
end

-- the free runs left: row = {freeDay, freeWeek} (the day / week key of the last free run used)
function D.freeState(cfg, row, now)
	row = row or {}
	local day = tonumber(os.date("%Y%m%d", now))
	local week = D.weekKey(now, cfg.resetHour)
	local d = os.date("*t", now)
	local tomorrow = os.time({year = d.year, month = d.month, day = d.day + 1, hour = 0, min = 0, sec = 0})
	local daily = (tonumber(row.freeDay) or 0) ~= day
	return {daily = daily, weekly = (tonumber(row.freeWeek) or 0) ~= week, day = day, week = week,
		nextDaily = daily and now or tomorrow}
end

-- how a run is paid: "free" (the free run of the mode), "sigil" or nil + why
function D.payment(fs, weekly, sigils)
	if weekly and fs.weekly then
		return "free"
	elseif not weekly and fs.daily then
		return "free"
	elseif (sigils or 0) > 0 then
		return "sigil"
	end
	return nil, weekly and "Your free weekly descent is used and you carry no Ember Sigil."
		or "Your free descent of today is used and you carry no Ember Sigil."
end

-- ---------------------------------------------------------------- checks
function D.validate(cfg)
	local problems = {}
	local function bad(text)
		problems[#problems + 1] = text
	end
	local seen = {}
	for _, b in ipairs(cfg.boons) do
		if seen[b.key] then
			bad("boon twice: " .. b.key)
		end
		seen[b.key] = true
		if not b.key:match("^[a-z_]+$") then
			bad("boon key " .. b.key)
		end
		if (b.max or 0) < 1 or (b.weight or 0) <= 0 or not b.name or not b.desc then
			bad("boon " .. b.key .. ": max, weight, name, desc")
		end
		if b.kind == "convert" and not ({fire = true, ice = true, death = true, energy = true, earth = true, holy = true})[b.element] then
			bad("boon " .. b.key .. ": element")
		end
	end
	for _, c in ipairs(cfg.curses) do
		if seen[c.key] then
			bad("curse key used twice: " .. c.key)
		end
		seen[c.key] = true
		if (c.reward or 0) <= 0 then
			bad("curse " .. c.key .. ": no reward")
		end
	end
	if cfg.rooms.min < 3 or cfg.rooms.max < cfg.rooms.min then
		bad("rooms")
	end
	for _, u in ipairs(cfg.rewards.uniques) do
		if not tonumber(u.id) or not u.name then
			bad("unique " .. tostring(u.name))
		end
	end
	return problems
end

return D
