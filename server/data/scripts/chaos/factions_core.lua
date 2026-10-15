-- Factions: the pure logic (no engine calls). factions.lua is the engine side, factions_config.lua the numbers;
-- tests: server/tests/factions_test.lua. Lua 5.1 / LuaJIT and Lua 5.3 compatible.
--
--   K.index(cfg)                          lookups: factions by key, category / theme / invader / boss -> faction keys,
--                                         offers by key, rank index by key
--   K.validate(cfg, itemMods)             list of problems (empty = fine); itemMods = ChaosItemMods (gear offers)
--   K.day(t, cfg) / K.week(t, cfg)        faction day (YYYYMMDD) and week (YYYYMMDD of its Monday); start at cfg.dayHour
--   K.nextDay(t, cfg) / K.nextWeek(t, cfg) unix time of the next start
--   K.rankAt(cfg, rep)                    rank index, rank
--   K.bar(cfg, rep)                       {rank, key, name, color, rep, lo, hi, pct, next}
--   K.newEntry(cfg) / K.roll(e, day, week) a character's standing with one faction; roll resets the day / week sums
--   K.dr(cfg, dayGain, amount)            activity reputation after the daily diminishing returns
--   K.gain(cfg, idx, st, key, amount, o)  apply a gain (st = {[faction] = entry}); o = {day, week, contract, now}
--   K.hash(...) / K.rng(seed)             deterministic seed and generator (same numbers in every interpreter)
--   K.makeContract(...) / K.contracts(...) contracts of a period, deterministic by (character, period, faction, slot)
--   K.matchKill / K.matchRift / K.matchEvent, K.advance
--   K.offerState(cfg, idx, offer, ctx)    "locked" | "owned" | "soldout" | "ok" (+ reason, in ctx.lang)
--   K.label(c, lang?)                     a contract's text in `lang` (c.label is the English one)
--   K.gearMods(offer, itemMods)           the fixed modifiers of a gear offer: {key, tier, value, lo, hi, side, label}
--   K.tokenChance(cfg, tier)              token drop chance per 10000 of a kill
--   K.titlesOf(cfg, idx, st)              titles a character holds (rank titles; the Exalted one with the frame)
--   K.payload(cfg, idx, st, ctx)          the window data

ChaosFactionsCore = ChaosFactionsCore or {}
local K = ChaosFactionsCore
local unpack = unpack or table.unpack

local floor, max, min = math.floor, math.max, math.min

-- a text in `lang` (Chaos.t keys, i18n_strings.lua); English without ChaosI18n
local function T(lang, key, ...)
	if ChaosI18n and ChaosI18n.text then
		return ChaosI18n.text(lang, key, ...)
	end
	if select("#", ...) == 0 then
		return key
	end
	return string.format(key, ...)
end

local function round(v)
	return floor(v + 0.5)
end

-- ---------------------------------------------------------------- index and checks
function K.index(cfg)
	local idx = {list = {}, byKey = {}, byCategory = {}, byTheme = {}, byInvader = {}, bosses = {}, offers = {},
		offerList = {}, rankIndex = {}}
	for i, r in ipairs(cfg.ranks) do
		idx.rankIndex[r.key] = i
	end
	for _, f in ipairs(cfg.factions) do
		idx.list[#idx.list + 1] = f
		idx.byKey[f.key] = f
		for _, c in ipairs(f.categories or {}) do
			idx.byCategory[c] = idx.byCategory[c] or f.key
		end
		if f.theme then
			idx.byTheme[f.theme:lower()] = f.key
		end
		for _, inv in ipairs(f.invaders or {}) do
			idx.byInvader[inv] = idx.byInvader[inv] or {}
			table.insert(idx.byInvader[inv], f.key)
		end
		for _, b in ipairs(f.bosses or {}) do
			idx.bosses[#idx.bosses + 1] = {part = b:lower(), faction = f.key}
		end
		for _, o in ipairs((cfg.offers or {})[f.key] or {}) do
			o.faction = f.key
			idx.offers[o.key] = o
			idx.offerList[#idx.offerList + 1] = o
		end
	end
	return idx
end

-- the faction of a world boss name (a part of the name is enough), or nil
function K.factionOfBoss(idx, name)
	local lower = tostring(name or ""):lower()
	for _, b in ipairs(idx.bosses) do
		if lower:find(b.part, 1, true) then
			return b.faction
		end
	end
	return nil
end

-- the modifier definition of a Chaos modifier key in chaos_item_mods.lua
local function modDef(itemMods, key)
	for _, d in ipairs(itemMods.config.mods) do
		if d.key == key then
			return d
		end
	end
	return nil
end

function K.gearProblems(offer, itemMods, limits)
	local out = {}
	local function bad(fmt, ...)
		out[#out + 1] = string.format("%s: " .. fmt, offer.key, ...)
	end
	local c = itemMods.config
	limits = limits or {}
	if type(offer.id) ~= "number" or offer.id <= 0 then
		bad("no base item id")
	end
	local rarity, level = tonumber(offer.rarity) or 0, tonumber(offer.level) or 0
	if rarity < 1 or rarity > #c.rarity.count then
		bad("rarity %s out of range", tostring(offer.rarity))
		return out
	end
	if level < 1 or level > c.itemLevel.max then
		bad("item level %s out of range", tostring(offer.level))
	end
	if limits.maxLevel and level > limits.maxLevel then
		bad("item level %d above the faction limit %d", level, limits.maxLevel)
	end
	if limits.maxRarity and rarity > limits.maxRarity then
		bad("rarity %d above the faction limit %d", rarity, limits.maxRarity)
	end
	local mods = offer.mods or {}
	if #mods == 0 then
		bad("no modifiers")
	end
	if #mods > c.rarity.count[rarity] then
		bad("%d modifiers, the rarity allows %d", #mods, c.rarity.count[rarity])
	end
	local sides, seen = {prefix = 0, suffix = 0}, {}
	for _, m in ipairs(mods) do
		local key, tier = m[1], tonumber(m[2]) or 0
		local d = modDef(itemMods, key)
		if not d then
			bad("unknown modifier %s", tostring(key))
		else
			if seen[key] then
				bad("modifier %s twice", key)
			end
			seen[key] = true
			if not d.kinds[offer.itemKind or ""] then
				bad("%s cannot be on a %s", key, tostring(offer.itemKind))
			end
			sides[d.side] = sides[d.side] + 1
			if tier < 1 or tier > c.maxTier then
				bad("%s tier %d out of range", key, tier)
			elseif level < c.tierLevels[tier] then
				bad("%s T%d needs item level %d (offer: %d)", key, tier, c.tierLevels[tier], level)
			end
			if limits.maxTier and tier > limits.maxTier then
				bad("%s T%d above the faction limit T%d", key, tier, limits.maxTier)
			end
		end
	end
	local side = c.rarity.sides[rarity]
	if sides.prefix > side or sides.suffix > side then
		bad("%d prefixes / %d suffixes, the rarity allows %d of each", sides.prefix, sides.suffix, side)
	end
	return out
end

local OFFER_KINDS = {gear = true, orbs = true, recipe = true, aura = true, mount = true}

function K.validate(cfg, itemMods)
	local problems = {}
	local function bad(fmt, ...)
		problems[#problems + 1] = string.format(fmt, ...)
	end
	local last
	for i, r in ipairs(cfg.ranks) do
		if last and r.min <= last then
			bad("rank %d (%s) does not rise", i, r.key)
		end
		last = r.min
	end
	if cfg.ranks[1].min ~= cfg.rep.min then
		bad("the first rank must start at rep.min")
	end
	if cfg.ranks[#cfg.ranks].min ~= cfg.rep.max then
		bad("the last rank (Exalted) must start at rep.max")
	end
	local idx = K.index(cfg)
	local keys, offerKeys, tokenIds = {}, {}, {}
	for _, f in ipairs(cfg.factions) do
		if keys[f.key] then
			bad("faction %s twice", f.key)
		end
		keys[f.key] = true
		local rival = f.rival and idx.byKey[f.rival]
		if f.rival and not rival then
			bad("%s: unknown rival %s", f.key, f.rival)
		elseif rival and rival.rival ~= f.key then
			bad("%s: rivalry with %s is not mutual", f.key, f.rival)
		end
		local t = cfg.tokens[f.key]
		if not t or type(t.id) ~= "number" or type(t.sourceId) ~= "number" then
			bad("%s: no token item", f.key)
		elseif tokenIds[t.id] then
			bad("%s: token id %d twice", f.key, t.id)
		else
			tokenIds[t.id] = true
		end
		if not f.npc or type(f.npc.name) ~= "string" then
			bad("%s: no NPC", f.key)
		end
		for _, o in ipairs(cfg.offers[f.key] or {}) do
			if offerKeys[o.key] then
				bad("offer %s twice", tostring(o.key))
			end
			offerKeys[o.key] = true
			if not OFFER_KINDS[o.kind] then
				bad("%s: unknown kind %s", tostring(o.key), tostring(o.kind))
			end
			if not idx.rankIndex[o.rank] then
				bad("%s: unknown rank %s", o.key, tostring(o.rank))
			end
			if type(o.price) ~= "number" or o.price < 0 then
				bad("%s: price", o.key)
			end
			if o.kind == "gear" and itemMods then
				for _, p in ipairs(K.gearProblems(o, itemMods, cfg.gearLimits)) do
					problems[#problems + 1] = p
				end
			elseif o.kind == "orbs" and (type(o.items) ~= "table" or #o.items == 0) then
				bad("%s: no items", o.key)
			elseif o.kind == "recipe" and (type(o.craft) ~= "table" or #(o.craft.output or {}) == 0) then
				bad("%s: no craft", o.key)
			elseif o.kind == "aura" and type(o.aura) ~= "number" then
				bad("%s: no aura id", o.key)
			elseif o.kind == "mount" and type(o.mount) ~= "number" then
				bad("%s: no mount id", o.key)
			end
		end
	end
	return problems
end

-- ---------------------------------------------------------------- days and weeks
local function dayKeyOf(t)
	return tonumber(os.date("%Y%m%d", t))
end

function K.day(t, cfg)
	return dayKeyOf(t - (cfg.dayHour or 0) * 3600)
end

function K.week(t, cfg)
	local d = os.date("*t", t - (cfg.dayHour or 0) * 3600)
	local back = (d.wday + 5) % 7 -- wday 1 = Sunday: Monday -> 0, Sunday -> 6
	return dayKeyOf(os.time({year = d.year, month = d.month, day = d.day - back, hour = 12}))
end

function K.nextDay(t, cfg)
	local d = os.date("*t", t - (cfg.dayHour or 0) * 3600)
	return os.time({year = d.year, month = d.month, day = d.day + 1, hour = cfg.dayHour or 0, min = 0, sec = 0})
end

function K.nextWeek(t, cfg)
	local d = os.date("*t", t - (cfg.dayHour or 0) * 3600)
	local back = (d.wday + 5) % 7
	return os.time({year = d.year, month = d.month, day = d.day - back + 7, hour = cfg.dayHour or 0, min = 0, sec = 0})
end

-- ---------------------------------------------------------------- ranks
function K.rankAt(cfg, rep)
	local idx = 1
	for i, r in ipairs(cfg.ranks) do
		if rep >= r.min then
			idx = i
		end
	end
	return idx, cfg.ranks[idx]
end

function K.bar(cfg, rep)
	local i, r = K.rankAt(cfg, rep)
	local nextRank = cfg.ranks[i + 1]
	local lo, hi = r.min, nextRank and nextRank.min or r.min
	local pct = nextRank and floor((rep - lo) * 100 / max(1, hi - lo)) or 100
	return {rank = i, key = r.key, name = r.name, color = r.color, rep = rep, lo = lo, hi = hi,
		pct = max(0, min(100, pct)), next = nextRank and nextRank.name or nil}
end

-- ---------------------------------------------------------------- standing and gains
function K.newEntry(cfg)
	return {rep = cfg.rep.start or 0, day = 0, dayGain = 0, week = 0, weekGain = 0, bank = 0, exalted = 0, total = 0,
		carry = 0, rivalCarry = 0}
end

-- the cap of this week for an entry: weeklyCap + what earlier weeks left unused (e.bank)
function K.weekCap(cfg, e)
	return cfg.weeklyCap + max(0, (e and e.bank) or 0)
end

-- whole weeks from week key a to week key b (YYYYMMDD of their Mondays); nil for a key that is not a date
function K.weeksBetween(a, b)
	local function t(k)
		k = tonumber(k) or 0
		local y, m, d = floor(k / 10000), floor(k / 100) % 100, k % 100
		if y < 2000 or m < 1 or m > 12 or d < 1 or d > 31 then
			return nil
		end
		return os.time({year = y, month = m, day = d, hour = 12})
	end
	local ta, tb = t(a), t(b)
	if not ta or not tb then
		return nil
	end
	return floor((tb - ta) / (7 * 86400) + 0.5)
end

-- cfg (optional): the unused cap of the week that ends, and every week skipped, carry over into e.bank, together at
-- most (rolloverWeeks - 1) x weeklyCap (so a week's cap is at most rolloverWeeks weeks' worth)
function K.roll(e, day, week, cfg)
	if day and e.day ~= day then
		e.day, e.dayGain, e.carry = day, 0, 0
	end
	if week and e.week ~= week then
		local bank = 0
		local weeks = cfg and (cfg.rolloverWeeks or 1) or 1
		local n = weeks > 1 and (e.week or 0) > 0 and K.weeksBetween(e.week, week) or nil
		if n and n >= 1 then
			local unused = max(0, K.weekCap(cfg, e) - (e.weekGain or 0)) + (n - 1) * cfg.weeklyCap
			bank = min((weeks - 1) * cfg.weeklyCap, unused)
		end
		e.week, e.weekGain, e.bank = week, 0, bank
	end
	return e
end

-- activity reputation `amount` after the bands, given dayGain already earned (raw, before the bands) this faction day
function K.dr(cfg, dayGain, amount)
	local out, pos, left = 0, dayGain, amount
	for _, b in ipairs(cfg.daily.bands) do
		if left <= 0 then
			break
		end
		local room = b.upTo and max(0, b.upTo - pos) or left
		local take = min(left, room)
		if take > 0 then
			out = out + take * b.mult
			pos = pos + take
			left = left - take
		end
	end
	return out
end

-- the multiplier the next point of activity reputation gets (for the window)
function K.drMult(cfg, dayGain)
	for _, b in ipairs(cfg.daily.bands) do
		if not b.upTo or dayGain < b.upTo then
			return b.mult
		end
	end
	return 0
end

-- Apply `amount` to faction `key` of st ({[key] = entry}). o.contract: no diminishing returns. o.day / o.week: the
-- current faction day and week (the sums roll). Returns {gained, before, after, rankBefore, rankAfter, capped,
-- rival, rivalLoss, exaltedNow}.
function K.gain(cfg, idx, st, key, amount, o)
	o = o or {}
	local f = idx.byKey[key]
	local res = {gained = 0, rivalLoss = 0}
	if not f or type(amount) ~= "number" or amount <= 0 then
		return res
	end
	local e = st[key] or K.newEntry(cfg)
	st[key] = e
	K.roll(e, o.day, o.week, cfg)
	res.before = e.rep
	res.rankBefore = K.rankAt(cfg, e.rep)
	local value = amount
	if not o.contract then
		value = K.dr(cfg, e.dayGain, amount) + (e.carry or 0)
		e.dayGain = e.dayGain + amount
	end
	local whole = floor(value + 1e-9)
	if not o.contract then
		e.carry = value - whole
	end
	local room = max(0, K.weekCap(cfg, e) - e.weekGain)
	local gained = min(whole, room, max(0, cfg.rep.max - e.rep))
	res.capped = gained < whole
	if gained > 0 then
		e.rep = e.rep + gained
		e.weekGain = e.weekGain + gained
		e.total = (e.total or 0) + gained
	end
	res.gained = gained
	res.after = e.rep
	res.rankAfter = K.rankAt(cfg, e.rep)
	if e.rep >= cfg.rep.max and (e.exalted or 0) == 0 then
		e.exalted = o.now or 1
		res.exaltedNow = true
	end
	-- rivalry
	local rv = f.rival and idx.byKey[f.rival]
	if gained > 0 and rv then
		local r = st[rv.key] or K.newEntry(cfg)
		st[rv.key] = r
		res.rival = rv.key
		local sworn = cfg.rivalry.swornAtExalted and (r.exalted or 0) > 0
		if not sworn and r.rep > cfg.rivalry.floor then
			-- fractions carry over (kills give one point at a time)
			local raw = gained * cfg.rivalry.share + (r.rivalCarry or 0)
			local loss = floor(raw + 1e-9)
			r.rivalCarry = raw - loss
			local after = max(cfg.rivalry.floor, r.rep - loss)
			res.rivalLoss = r.rep - after
			r.rep = after
		end
	end
	return res
end

-- staff: set a standing (clamped); counts as reached Exalted when it is
function K.set(cfg, st, key, rep, now)
	local e = st[key] or K.newEntry(cfg)
	st[key] = e
	e.rep = max(cfg.rep.min, min(cfg.rep.max, floor(rep)))
	if e.rep >= cfg.rep.max and (e.exalted or 0) == 0 then
		e.exalted = now or 1
	end
	return e
end

-- ---------------------------------------------------------------- seeds
function K.hash(...)
	local h = 5381
	for _, part in ipairs({...}) do
		local s = tostring(part)
		for i = 1, #s do
			h = (h * 33 + s:byte(i)) % 2147483647
		end
		h = (h * 33 + 47) % 2147483647 -- separator
	end
	return h
end

-- Park-Miller generator: rand(a, b) -> integer in [a, b]
function K.rng(seed)
	local s = seed % 2147483647
	if s <= 0 then
		s = s + 2147483646
	end
	return function(a, b)
		s = (s * 16807) % 2147483647
		if not a then
			return s / 2147483647
		end
		return a + s % (b - a + 1)
	end
end

local function pickWeighted(list, rand, skip)
	local total = 0
	for _, w in ipairs(list) do
		if not skip[w[1]] then
			total = total + w[2]
		end
	end
	if total <= 0 then
		return nil
	end
	local roll = rand(1, total)
	for _, w in ipairs(list) do
		if not skip[w[1]] then
			roll = roll - w[2]
			if roll <= 0 then
				return w[1]
			end
		end
	end
	return nil
end

-- ---------------------------------------------------------------- contracts
local function thousands(n)
	local s = tostring(floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end
K.thousands = thousands

-- the highest rift tier a character of `level` may open (rift_config.lua tiers[i].minLevel; beyond: +minLevelStep)
function K.riftTierFor(level, riftCfg)
	local tiers = riftCfg and riftCfg.tiers or {}
	local best = 0
	for i, t in ipairs(tiers) do
		if level >= t.minLevel then
			best = i
		end
	end
	if best == #tiers and best > 0 and riftCfg.beyond and riftCfg.maxTier then
		local lastMin = tiers[#tiers].minLevel
		local extra = floor((level - lastMin) / max(1, riftCfg.beyond.minLevelStep or 25))
		best = min(riftCfg.maxTier, best + max(0, extra))
	end
	return best
end

-- one contract. kind "daily" | "weekly"; period = day or week key; ctx = {level, families = fn(cat, minLevel, level)
-- -> number of huntable monster types, riftCfg, itemName = fn(id)}. nil when no kind can be made.
function K.makeContract(cfg, f, kind, period, guid, slot, ctx, used)
	local cc = cfg.contracts
	local rand = K.rng(K.hash("faction", guid, kind, period, f.key, slot))
	local level = max(1, floor(tonumber(ctx.level) or 1))
	used = used or {}
	local skip = {}
	for k in pairs(used) do
		skip[k] = true
	end
	local kinds = kind == "daily" and cc.dailyKinds or cc.weeklyKinds
	for _ = 1, #kinds do
		local pick = pickWeighted(kinds, rand, skip)
		if not pick then
			return nil
		end
		skip[pick] = true
		local c = {key = string.format("%s:%d:%s:%d", kind == "daily" and "d" or "w", period, f.key, slot),
			faction = f.key, period = kind, slot = slot, kind = pick, level = level,
			rep = kind == "daily" and cc.rep.daily or cc.rep.weekly}
		if pick == "kill" then
			local minLevel = floor(level * cc.kill.minLevelShare)
			local cats = {}
			for _, cat in ipairs(f.categories or {}) do
				if not ctx.families or (ctx.families(cat, minLevel, level) or 0) > 0 then
					cats[#cats + 1] = cat
				end
			end
			if #cats > 0 then
				c.cat = cats[rand(1, #cats)]
				local n = rand(cc.kill.count[1], cc.kill.count[2])
				c.count = max(cc.kill.step, floor(n / cc.kill.step) * cc.kill.step)
				c.minLevel = minLevel
				c.lab = {"Slay %d %s of level %d+", c.count, ctx.catName and ctx.catName(c.cat) or c.cat, minLevel}
				c.label = K.label(c)
				used[pick] = true
				return c
			end
		elseif pick == "rift" or pick == "riftmany" then
			local top = K.riftTierFor(level, ctx.riftCfg)
			if top > 0 and f.theme then
				local spec = cc[pick]
				c.kind = "rift"
				c.theme = f.theme
				c.tier = max(1, top - spec.tierBelow)
				c.count = spec.count
				c.lab = c.count == 1 and {"Seal a tier %d+ rift of the %s", c.tier, f.theme}
					or {"Seal %d tier %d+ rifts of the %s", c.count, c.tier, f.theme}
				c.label = K.label(c)
				used[pick] = true
				return c
			end
		elseif pick == "deliver" or pick == "delivermany" then
			local spec = cc[pick]
			c.kind = "deliver"
			c.items = {}
			local parts = {}
			for _, it in ipairs(spec.items) do
				local n = rand(it.count[1], it.count[2])
				c.items[#c.items + 1] = {id = it.id, count = n}
				parts[#parts + 1] = string.format("%d %s", n, ctx.itemName and ctx.itemName(it.id, n) or ("item " .. it.id))
			end
			local g = spec.gold
			c.gold = floor(max(g.min, min(g.max, level * g.perLevel)) / 1000) * 1000
			c.count = 1
			c.lab = {"Deliver %s", parts, thousands(c.gold)}
			c.label = K.label(c)
			used[pick] = true
			return c
		elseif pick == "worldboss" then
			c.count = cc.worldboss.count
			c.lab = {"Take part in the fall of a world boss"}
			c.label = K.label(c)
			used[pick] = true
			return c
		elseif pick == "invasion" then
			c.count = cc.invasion.count
			c.lab = {"Stand against an invasion"}
			c.label = K.label(c)
			used[pick] = true
			return c
		end
	end
	return nil
end

-- a contract's text in `lang` (English without one): c.lab = {key, args...}; a list argument is the items of a
-- delivery, then its gold ("Deliver 3 x and 5,000 gold")
function K.label(c, lang)
	local lab = c.lab
	if not lab then
		return c.label
	end
	if type(lab[2]) == "table" then
		local parts = {}
		for i, x in ipairs(lab[2]) do
			parts[i] = x
		end
		parts[#parts + 1] = T(lang, "%s gold", lab[3])
		return T(lang, lab[1], table.concat(parts, T(lang, " and ")))
	end
	return T(lang, lab[1], unpack(lab, 2))
end

-- every contract of a period for every faction: list in faction order, then slot order
function K.contracts(cfg, idx, kind, period, guid, levelOf, ctx)
	local out = {}
	local n = kind == "daily" and cfg.contracts.daily or cfg.contracts.weekly
	for _, f in ipairs(idx.list) do
		local used = {}
		for slot = 1, n do
			local c2 = {}
			for k, v in pairs(ctx) do
				c2[k] = v
			end
			c2.level = levelOf(f.key, slot)
			local c = K.makeContract(cfg, f, kind, period, guid, slot, c2, used)
			if c then
				out[#out + 1] = c
			end
		end
	end
	return out
end

function K.matchKill(c, info)
	return c.kind == "kill" and info.cat == c.cat and (info.level or 0) >= (c.minLevel or 0)
end

function K.matchRift(c, theme, tier)
	return c.kind == "rift" and tostring(theme or ""):lower() == tostring(c.theme or ""):lower() and (tier or 0) >= (c.tier or 0)
end

function K.matchEvent(c, kind)
	return c.kind == kind
end

-- progress + n, capped at the count. Returns the new progress and whether it just completed.
function K.advance(c, progress, n)
	if progress >= c.count then
		return progress, false
	end
	local p = min(c.count, progress + (n or 1))
	return p, p >= c.count
end

-- ---------------------------------------------------------------- the quartermaster
-- ctx = {ranks = {[faction] = rank index}, owned = {[offer] = true}, weekly = {[offer] = bought this week}, lang?}
function K.offerState(cfg, idx, offer, ctx)
	local need = idx.rankIndex[offer.rank] or 1
	local have = (ctx.ranks or {})[offer.faction] or 1
	if (offer.kind == "recipe" or offer.kind == "aura" or offer.kind == "mount") and (ctx.owned or {})[offer.key] then
		return "owned", T(ctx.lang, "You have it.")
	end
	if have < need then
		return "locked", T(ctx.lang, "Needs %s with %s.", cfg.ranks[need].name, idx.byKey[offer.faction].name)
	end
	if offer.weekly and ((ctx.weekly or {})[offer.key] or 0) >= offer.weekly then
		return "soldout", T(ctx.lang, "Bought %d of %d this week.", offer.weekly, offer.weekly)
	end
	return "ok", nil
end

-- the gear offer's modifiers with their values (the middle of the tier's range)
function K.gearMods(offer, itemMods)
	local out = {}
	for _, m in ipairs(offer.mods or {}) do
		local d = modDef(itemMods, m[1])
		if d then
			local r = d.tiers[m[2]]
			out[#out + 1] = {key = m[1], tier = m[2], lo = r[1], hi = r[2], value = floor((r[1] + r[2]) / 2),
				side = d.side, label = d.label, fmt = d.fmt, text = d.text}
		end
	end
	return out
end

function K.modText(m)
	if m.text then
		return string.format(m.text, m.value)
	end
	if m.fmt == "flat" then
		return string.format("%s +%d", m.label, m.value)
	elseif m.fmt == "less" then
		return string.format("%s -%d%%", m.label, m.value)
	end
	return string.format("%s +%d%%", m.label, m.value)
end

-- ---------------------------------------------------------------- tokens and titles
function K.tokenChance(cfg, tier)
	local t = cfg.tokenDrop.chance
	return t[tier or "normal"] or t.normal or 0
end

function K.titlesOf(cfg, idx, st)
	local out = {}
	for _, f in ipairs(idx.list) do
		local e = st[f.key]
		if e then
			local rank = K.rankAt(cfg, e.rep)
			local reached = (e.exalted or 0) > 0 and #cfg.ranks or rank
			for _, rk in ipairs({"honored", "revered", "exalted"}) do
				local need = idx.rankIndex[rk]
				local text = f.titles and f.titles[rk]
				if text and need and reached >= need then
					out[#out + 1] = {key = "faction:" .. f.key .. ":" .. rk, text = text, color = f.color,
						frame = rk == "exalted" and f.frame or nil, at = rk == "exalted" and e.exalted or nil}
				end
			end
		end
	end
	return out
end

-- ---------------------------------------------------------------- the window
-- ctx = {now, day, week, contracts = list (c.progress, c.done), owned, weekly, near = faction key or nil,
--        tokens = {[faction] = carried count}, itemName = fn(id, n), itemMods, offerItemId = fn(offer),
--        clientId = fn(server id) -> client id (the window draws items by client id), lang = the texts' language}
function K.payload(cfg, idx, st, ctx)
	local function cid(id)
		return (ctx.clientId and id and id > 0) and ctx.clientId(id) or id
	end
	local now = ctx.now or os.time()
	local out = {now = now, nextDay = K.nextDay(now, cfg) - now, nextWeek = K.nextWeek(now, cfg) - now,
		weekCap = cfg.weeklyCap, ranks = {}, factions = {}, contracts = {}, offers = {}}
	for _, r in ipairs(cfg.ranks) do
		out.ranks[#out.ranks + 1] = {k = r.key, n = r.name, min = r.min, c = r.color}
	end
	local ranks = {}
	for _, f in ipairs(idx.list) do
		local e = K.roll(st[f.key] or K.newEntry(cfg), ctx.day, ctx.week, cfg)
		local b = K.bar(cfg, e.rep)
		ranks[f.key] = b.rank
		local tok = cfg.tokens[f.key]
		out.factions[#out.factions + 1] = {k = f.key, n = f.name, s = f.short, c = f.color, lore = f.lore, rival = f.rival,
			rep = e.rep, rank = b.rank, rn = b.name, rc = b.color, lo = b.lo, hi = b.hi, pct = b.pct, nx = b.next,
			wk = e.weekGain, wc = K.weekCap(cfg, e), dy = e.dayGain, dr = K.drMult(cfg, e.dayGain), ex = (e.exalted or 0) > 0 or nil,
			npc = f.npc.name, near = ctx.near == f.key or nil, tok = (ctx.tokens or {})[f.key] or 0,
			tn = tok and tok.plural or "tokens", tid = cid(tok and tok.id or 0), theme = f.theme}
	end
	for _, c in ipairs(ctx.contracts or {}) do
		out.contracts[#out.contracts + 1] = {key = c.key, f = c.faction, per = c.period == "daily" and "d" or "w",
			kind = c.kind, label = K.label(c, ctx.lang), p = c.progress or 0, n = c.count, rep = c.rep, done = c.done and true or nil,
			give = c.kind == "deliver" and not c.done or nil}
	end
	local sctx = {ranks = ranks, owned = ctx.owned, weekly = ctx.weekly, lang = ctx.lang}
	for _, o in ipairs(idx.offerList) do
		local state, why = K.offerState(cfg, idx, o, sctx)
		local row = {key = o.key, f = o.faction, kind = o.kind, n = o.name, rank = idx.rankIndex[o.rank],
			rn = cfg.ranks[idx.rankIndex[o.rank] or 1].name, price = o.price, tokens = o.tokens or 0, st = state, why = why,
			wl = o.weekly, wb = o.weekly and ((ctx.weekly or {})[o.key] or 0) or nil}
		if o.kind == "gear" then
			row.item = o.id
			row.lv = o.level
			row.rar = o.rarity
			local lines = {}
			if ctx.itemMods then
				for _, m in ipairs(K.gearMods(o, ctx.itemMods)) do
					lines[#lines + 1] = string.format("T%d %s", m.tier, K.modText(m))
				end
			end
			row.mods = lines
		elseif o.kind == "orbs" then
			row.item = o.items[1].id
			local parts = {}
			for _, it in ipairs(o.items) do
				parts[#parts + 1] = string.format("%d %s", it.count, ctx.itemName and ctx.itemName(it.id, it.count) or it.id)
			end
			row.desc = table.concat(parts, ", ")
		elseif o.kind == "recipe" then
			local cr = o.craft
			row.item = cr.output[1].id
			local ins = {}
			for _, it in ipairs(cr.inputs or {}) do
				ins[#ins + 1] = string.format("%d %s", it.count, ctx.itemName and ctx.itemName(it.id, it.count) or it.id)
			end
			if (cr.tokens or 0) > 0 then
				local tok = cfg.tokens[o.faction]
				ins[#ins + 1] = string.format("%d %s", cr.tokens, cr.tokens == 1 and tok.name or tok.plural)
			end
			if (cr.gold or 0) > 0 then
				ins[#ins + 1] = thousands(cr.gold) .. " gold"
			end
			local outs = {}
			for _, it in ipairs(cr.output) do
				outs[#outs + 1] = string.format("%d %s", it.count, ctx.itemName and ctx.itemName(it.id, it.count) or it.id)
			end
			row.desc = table.concat(ins, " + ") .. " -> " .. table.concat(outs, ", ")
			row.craft = state == "owned" or nil
		elseif o.kind == "aura" then
			row.desc = "The faction tabard: an aura around your character."
		elseif o.kind == "mount" then
			row.desc = "A faction mount, yours for good."
		end
		row.item = cid(row.item or (ctx.offerItemId and ctx.offerItemId(o)) or 0)
		out.offers[#out.offers + 1] = row
	end
	return out
end

return K
