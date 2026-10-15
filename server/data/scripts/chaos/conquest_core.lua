-- Conquest Tokens: pure rules (no engine calls), shared by conquest.lua, the generators (tools/gen_codex_data.lua), the
-- Item Finder (itemfinder_sources.lua) and server/tests/conquest_test.lua. Numbers: conquest_config.lua.
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible (whole numbers through math.floor).
--
--   K.validate(cfg)                          -> list of problems (slots used twice or out of the block, bad numbers)
--   K.amount(cfg, key, ctx)                  -> tokens of a source: its amount, or base + per* x ctx (a clear's tier,
--                                               difficulty, depth, share), + clear, at most max
--   K.grantPlan(cfg, key, amount, day, today, used) -> {give, used, day}: the daily cap per source (a new day starts at 0)
--   K.bossSource(cfg, typeName, category, isBoss) -> source key, amount (nil when the monster gives nothing)
--   K.pityMult(cfg, group, misses)           -> the chance multiplier after `misses` misses in a row (1 .. cap)
--   K.pityNext(cfg, group, misses, hit)      -> the misses after this roll (0 on a hit)
--   K.pityChance(base, mult, max)            -> base x mult, at most max
--   K.specLevel(spec)                        -> the level of a unique spec's "(Requires level N.)", or nil
--   K.catalog(cfg, src)                      -> every offer {key, id, name, group, level, price, slot, set, season,
--                                               monsters, always}, sorted by group, level, name
--   K.price(cfg, group, level, id)           -> tokens
--   K.visible(cfg, offer, ctx)               -> true | false, reason (ctx: level, seen[id], killed[lower name])
--   K.canBuy(cfg, offer, ctx)                -> true | nil, reason key (ctx: balance, visible, pz, blocked)
--   K.refinePrice(cfg, rarity)               -> tokens to raise `rarity` by one, nil when it may not go up
--   K.refineCheck(cfg, info)                 -> true | nil, reason key (info: gear, rarity, unique, ruined)
--   K.convertCheck(cfg, what, from, to, have, kinds) -> true, cost | nil, reason key
--   K.salvageTokens(cfg, price)              -> tokens a salvaged unique gives
--   K.payload(cfg, offers, ctx)              -> the window's rows {k, id, n, g, l, p, s, set, ok, why}
-- Reason keys map to the English texts of K.reasons (the pt-BR entries are in i18n_strings.lua).

ChaosConquestCore = ChaosConquestCore or {}
local K = ChaosConquestCore
local floor = math.floor

K.reasons = {
	disabled = "The Conquest vendor is closed.",
	unknown = "There is no such offer.",
	tokens = "You do not have enough Conquest Tokens.",
	hidden = "You have not seen this item yet: find it once, slay a monster that drops it, or reach its level band.",
	season = "This season item is not for sale to your character.",
	pz = "Visit the Conquest vendor from a protection zone.",
	notGear = "Wear an item with a rarity in that slot first.",
	unique = "Uniques keep their stats: they cannot be refined.",
	ruined = "A ruined item cannot be refined.",
	maxRarity = "This item is already at the highest rarity a refinement reaches.",
	sameKind = "Choose two different kinds.",
	badKind = "There is no such kind.",
	notEnough = "You do not carry enough of that kind to convert.",
	noKey = "Carry an Omen Key to attune it.",
	level = "Your level is too low for that."
}

local function num(v, d)
	v = tonumber(v)
	if not v or v ~= v or v == math.huge or v == -math.huge then
		return d
	end
	return v
end

function K.validate(cfg)
	local p = {}
	if type(cfg) ~= "table" then
		return {"no config"}
	end
	local slots = {}
	for key, s in pairs(cfg.sources or {}) do
		local slot = num(s.slot, 0)
		if slot < 1 or slot >= (cfg.pitySlot or 30) or slot ~= floor(slot) then
			p[#p + 1] = "source " .. key .. ": slot must be 1.." .. ((cfg.pitySlot or 30) - 1)
		elseif slots[slot] then
			p[#p + 1] = "source " .. key .. ": slot " .. slot .. " is used by " .. slots[slot]
		else
			slots[slot] = key
		end
		if num(s.cap, 0) <= 0 then
			p[#p + 1] = "source " .. key .. ": no daily cap"
		end
	end
	local pslots = {}
	for key, g in pairs(cfg.pity or {}) do
		local slot = num(g.slot, 0)
		if slot < 1 or slot > 9 or pslots[slot] then
			p[#p + 1] = "pity " .. key .. ": slot must be 1..9 and used once"
		end
		pslots[slot] = key
		if num(g.step, -1) < 0 or num(g.cap, 0) < 1 then
			p[#p + 1] = "pity " .. key .. ": step >= 0 and cap >= 1"
		end
	end
	for cat, src in pairs((cfg.boss or {}).categories or {}) do
		if not (cfg.sources or {})[src] then
			p[#p + 1] = "boss category " .. cat .. ": unknown source " .. tostring(src)
		end
	end
	for name, b in pairs((cfg.boss or {}).byName or {}) do
		if not (cfg.sources or {})[b.source] then
			p[#p + 1] = "boss " .. name .. ": unknown source " .. tostring(b.source)
		end
	end
	for g, def in pairs((cfg.vendor or {}).groups or {}) do
		if num(def.base, -1) < 0 or num(def.perLevel, -1) < 0 then
			p[#p + 1] = "vendor group " .. g .. ": base and perLevel >= 0"
		end
	end
	return p
end

-- ---------------------------------------------------------------- income
function K.amount(cfg, key, ctx)
	local s = (cfg.sources or {})[key]
	if not s then
		return 0
	end
	ctx = ctx or {}
	local n
	if s.base then
		n = s.base + num(s.perTier, 0) * math.max(0, num(ctx.tier, 0))
			+ num(s.perDifficulty, 0) * math.max(0, num(ctx.difficulty, 0))
			+ num(s.perDepth, 0) * math.max(0, num(ctx.depth, 0))
			+ num(s.perShare, 0) * math.max(0, math.min(1, num(ctx.share, 0)))
			+ (ctx.cleared and num(s.clear, 0) or 0)
		if s.max then
			n = math.min(s.max, n)
		end
	else
		n = num(s.amount, 0)
	end
	return math.max(0, floor(n + 1e-9))
end

-- the daily cap: `used` tokens of this source were given on `day`; returns what to give now and the new counter
function K.grantPlan(cfg, key, amount, day, today, used)
	local s = (cfg.sources or {})[key]
	amount = floor(num(amount, 0))
	if not s or amount <= 0 then
		return {give = 0, used = num(used, 0), day = day}
	end
	if day ~= today then
		used = 0
	end
	used = math.max(0, floor(num(used, 0)))
	local left = math.max(0, floor(num(s.cap, 0)) - used)
	local give = math.min(amount, left)
	return {give = give, used = used + give, day = today, capped = give < amount}
end

function K.bossSource(cfg, typeName, category, isBoss)
	local b = cfg.boss or {}
	local name = type(typeName) == "string" and typeName:lower() or ""
	local own = (b.byName or {})[name]
	if own then
		return own.source, own.amount or K.amount(cfg, own.source)
	end
	local src = category and (b.categories or {})[category]
	if not src and isBoss then
		src = b.fallback
	end
	if not src or not (cfg.sources or {})[src] then
		return nil
	end
	return src, K.amount(cfg, src)
end

-- ---------------------------------------------------------------- bad-luck protection
function K.pityMult(cfg, group, misses)
	local g = (cfg.pity or {})[group]
	if not g then
		return 1
	end
	misses = math.max(0, floor(num(misses, 0)))
	return math.min(num(g.cap, 1), 1 + num(g.step, 0) * misses)
end

-- misses stop counting once the cap is reached (the storage never grows without end)
function K.pityNext(cfg, group, misses, hit)
	local g = (cfg.pity or {})[group]
	if hit or not g then
		return 0
	end
	misses = math.max(0, floor(num(misses, 0)))
	local step = num(g.step, 0)
	local top = step > 0 and math.ceil((num(g.cap, 1) - 1) / step) or 0
	return math.min(top, misses + 1)
end

function K.pityChance(base, mult, max)
	local c = num(base, 0) * num(mult, 1)
	if max and c > max then
		c = max
	end
	return c
end

-- ---------------------------------------------------------------- the catalog
function K.specLevel(spec)
	local d = type(spec) == "table" and spec.description or nil
	local n = type(d) == "string" and d:match("[Rr]equires level (%d+)") or nil
	return n and tonumber(n) or nil
end

function K.price(cfg, group, level, id)
	local v = cfg.vendor or {}
	local fixed = (v.prices or {})[id]
	if fixed then
		return fixed
	end
	local g = (v.groups or {})[group]
	if not g then
		return nil
	end
	local r = math.max(1, num(v.round, 10))
	local raw = num(g.base, 0) + num(g.perLevel, 0) * math.max(0, num(level, 0))
	return math.max(r, floor(raw / r + 0.5) * r)
end

-- src = {uniques = ChaosUniqueItems, sets = ChaosItemSets.sets, raid = raid_config.lua uniques, specs = ChaosUniqueSpecs}
function K.catalog(cfg, src)
	src = src or {}
	local v = cfg.vendor or {}
	local always = {}
	for _, id in ipairs(v.always or {}) do
		always[id] = true
	end
	local raidIds, pieceOf = {}, {}
	for _, u in ipairs(src.raid or {}) do
		if tonumber(u.id) then
			raidIds[tonumber(u.id)] = u
		end
	end
	for _, set in ipairs(src.sets or {}) do
		for _, p in ipairs(set.pieces or {}) do
			if tonumber(p.id) then
				pieceOf[tonumber(p.id)] = {set = set, piece = p}
			end
		end
	end
	local out, have = {}, {}
	local function add(id, name, group, level, extra)
		if have[id] or not id then
			return
		end
		local spec = (src.specs or {})[id]
		level = tonumber(level) or K.specLevel(spec) or num(v.defaultLevel, 100)
		local o = {key = "u:" .. id, id = id, name = name or (spec and spec.name) or ("item " .. id), group = group,
			level = level, price = K.price(cfg, group, level, id), always = always[id] or nil}
		for k, val in pairs(extra or {}) do
			o[k] = val
		end
		if o.price then
			have[id] = o
			out[#out + 1] = o
		end
	end
	for _, e in ipairs(src.uniques or {}) do
		local id = tonumber(e.id)
		if id then
			local group
			if raidIds[id] then
				group = "raid"
			elseif e.ascended then
				group = "ascended"
			elseif e.set or pieceOf[id] then
				group = "set"
			elseif e.bossOnly then
				group = "boss"
			else
				group = "monster"
			end
			local p = pieceOf[id]
			add(id, e.name, group, e.level or (p and p.piece.level), {slot = e.slot, season = e.season, monsters = e.monsters,
				set = p and p.set.name or nil})
		end
	end
	for id, p in pairs(pieceOf) do
		if not have[id] then
			add(id, p.piece.name, "set", p.piece.level, {slot = p.piece.slot, set = p.set.name})
		end
	end
	for id, u in pairs(raidIds) do
		if not have[id] then
			add(id, u.name, "raid", nil, {raidBosses = u.bosses})
		end
	end
	local order = {}
	for i, g in ipairs(v.groupOrder or {}) do
		order[g] = i
	end
	table.sort(out, function(a, b)
		local ga, gb = order[a.group] or 99, order[b.group] or 99
		if ga ~= gb then
			return ga < gb
		end
		if a.level ~= b.level then
			return a.level < b.level
		end
		if a.name ~= b.name then
			return a.name < b.name
		end
		return a.id < b.id
	end)
	return out
end

function K.byKey(offers)
	local m = {}
	for _, o in ipairs(offers or {}) do
		m[o.key] = o
	end
	return m
end

-- ctx = {level, seen = {[id] = true}, killed = {[lower monster name] = true}}
function K.visible(cfg, offer, ctx)
	ctx = ctx or {}
	if offer.always then
		return true
	end
	if ctx.seen and ctx.seen[offer.id] then
		return true
	end
	if num(offer.level, 0) <= num(ctx.level, 0) + num((cfg.vendor or {}).levelBand, 0) then
		return true
	end
	if ctx.killed then
		for _, m in ipairs(offer.monsters or {}) do
			if ctx.killed[tostring(m):lower()] then
				return true
			end
		end
	end
	return false, "hidden"
end

-- ctx = {enabled, balance, visible, pz, blocked (a season item)}
function K.canBuy(cfg, offer, ctx)
	ctx = ctx or {}
	if not cfg.enabled or ctx.enabled == false then
		return nil, "disabled"
	end
	if not offer then
		return nil, "unknown"
	end
	if ctx.blocked then
		return nil, "season"
	end
	if not ctx.visible then
		return nil, "hidden"
	end
	if (cfg.vendor or {}).needProtectionZone and not ctx.pz then
		return nil, "pz"
	end
	if num(ctx.balance, 0) < num(offer.price, math.huge) then
		return nil, "tokens"
	end
	return true
end

-- ---------------------------------------------------------------- refinement
function K.refinePrice(cfg, rarity)
	local r = cfg.refine or {}
	rarity = floor(num(rarity, 0))
	if rarity < 1 or rarity + 1 > num(r.maxRarity, 0) then
		return nil
	end
	return floor(num(r.base, 0) + num(r.perRarity, 0) * (rarity + 1))
end

function K.refineCheck(cfg, info)
	info = info or {}
	if info.unique then
		return nil, "unique"
	end
	if not info.gear or num(info.rarity, 0) < 1 then
		return nil, "notGear"
	end
	if info.ruined then
		return nil, "ruined"
	end
	if not K.refinePrice(cfg, info.rarity) then
		return nil, "maxRarity"
	end
	return true
end

-- what = "shards" | "relics"; kinds = the valid kind keys; have = {[kind] = count carried}
function K.convertCheck(cfg, what, from, to, have, kinds)
	local c = (cfg.cinder or {}).convert or {}
	local need = floor(num(c[what], 0))
	if need < 1 then
		return nil, "unknown"
	end
	local valid = {}
	for _, k in ipairs(kinds or {}) do
		valid[k] = true
	end
	if not valid[from] or not valid[to] then
		return nil, "badKind"
	end
	if from == to then
		return nil, "sameKind"
	end
	if num((have or {})[from], 0) < need then
		return nil, "notEnough"
	end
	return true, need
end

function K.salvageTokens(cfg, price)
	local s = cfg.salvage or {}
	return math.max(floor(num(s.min, 0)), floor(num(price, 0) * num(s.share, 0)))
end

-- ---------------------------------------------------------------- the window
-- ctx: as K.visible, plus blocked(offer) -> true for a season item this character may not have
function K.payload(cfg, offers, ctx)
	local rows = {}
	for _, o in ipairs(offers or {}) do
		if not (ctx and ctx.blocked and ctx.blocked(o)) then
			local ok, why = K.visible(cfg, o, ctx)
			rows[#rows + 1] = {k = o.key, id = o.id, n = o.name, g = o.group, l = o.level, p = o.price, s = o.slot,
				set = o.set, ok = ok and true or nil, why = why}
		end
	end
	return rows
end

return K
