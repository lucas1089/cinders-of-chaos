-- Season pass: pure logic (no engine calls), shared by seasonpass.lua, seasonpass_store.lua and
-- server/tests/seasonpass_test.lua. Lua 5.1 / LuaJIT and Lua 5.3 compatible.
--   tiers       P.tierCost(cfg, t), P.xpForTier(cfg, t), P.maxXp(cfg), P.tierOf(cfg, xp) -> tier, into, need,
--               P.skip(cfg, xp, n)
--   sources     P.expForLevel(level), P.expUnits(rawExp, stage, level), P.sourceGain(cfg, source, value, usedToday)
--   periods     P.dayKey(t), P.weekKey(t), P.nextDay(t), P.nextWeek(t)
--   challenges  P.pick(slots, seed), P.challenges(cfg, seasonId, kind, period), P.statsOf(stat, value)
--   claims      P.claimCheck(pass, view, tier, track), P.claimable(pass, view), P.claimedString(set, n),
--               P.premiumBacklog(pass, view) (a late buyer's reached premium rewards, claimed at once)
--   packs       P.pack(pass, id), P.ownedPack(packRows), P.hasPremium(pass, premium, packId),
--               P.packPrice(pass, target, ownedPack, passPaid), P.packGrants(pass, fromId, toId)
--   cosmetics   P.entitlements(pass, claims, packId) -> list of cosmetic rewards of the account
--   checks      P.validate(cfg), P.rewardText(r, lang?) (in `lang` through ChaosI18n when loaded; English otherwise)

ChaosSeasonPassCore = ChaosSeasonPassCore or {}
local P = ChaosSeasonPassCore

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

P.KINDS = {item = true, coins = true, title = true, outfit = true, mount = true, shader = true, portal = true,
	frame = true, transmog = true, tierskips = true, premium = true}
P.TRACK_KINDS = {item = true, coins = true, title = true, outfit = true, mount = true, shader = true, portal = true,
	frame = true, transmog = true}
P.COSMETIC = {title = true, outfit = true, mount = true, shader = true, portal = true, frame = true, transmog = true}
-- what the premium (paid) track may give: cosmetics and Chaos Coins back. Never gold, potions, experience or gear.
P.PREMIUM_KINDS = {coins = true, title = true, outfit = true, mount = true, shader = true, portal = true, frame = true,
	transmog = true}
P.FREE, P.PREMIUM = 0, 1

-- ---------------------------------------------------------------- tiers
function P.tierCost(cfg, t)
	return cfg.tierXp.base + cfg.tierXp.step * (t - 1)
end

-- total pass XP needed to reach tier t (tier 0 = 0)
function P.xpForTier(cfg, t)
	t = math.max(0, math.min(cfg.maxTier, math.floor(t)))
	return t * cfg.tierXp.base + cfg.tierXp.step * (t - 1) * t / 2
end

function P.maxXp(cfg)
	return P.xpForTier(cfg, cfg.maxTier)
end

-- tier reached with `xp`, xp into the next tier, xp that tier costs (0 / 0 at the top)
function P.tierOf(cfg, xp)
	xp = math.max(0, math.floor(tonumber(xp) or 0))
	local t = 0
	while t < cfg.maxTier and xp >= P.xpForTier(cfg, t + 1) do
		t = t + 1
	end
	if t >= cfg.maxTier then
		return cfg.maxTier, 0, 0
	end
	return t, xp - P.xpForTier(cfg, t), P.tierCost(cfg, t + 1)
end

-- xp after n tier skips: each skip adds the cost of the next tier, so the progress inside a tier is kept
function P.skip(cfg, xp, n)
	xp = math.max(0, math.floor(tonumber(xp) or 0))
	for _ = 1, math.max(0, math.floor(n or 0)) do
		local t = P.tierOf(cfg, xp)
		if t >= cfg.maxTier then
			break
		end
		xp = xp + P.tierCost(cfg, t + 1)
	end
	return math.min(xp, P.maxXp(cfg))
end

-- ---------------------------------------------------------------- sources
-- experience of a level (the engine's Player::getExpForLevel)
function P.expForLevel(level)
	level = math.floor(level)
	return math.floor((((level - 6) * level + 17) * level - 12) / 6) * 100
end

-- 1 unit = 1% of the current level, counted on the monster's base experience times the level's experience stage
function P.expUnits(rawExp, stage, level)
	level = math.max(1, math.floor(tonumber(level) or 1))
	local span = P.expForLevel(level + 1) - P.expForLevel(level)
	if span <= 0 then
		return 0
	end
	local exp = math.max(0, tonumber(rawExp) or 0) * math.max(0, tonumber(stage) or 1)
	return exp * 100 / span
end

-- pass XP a source event gives, after the daily cap. value: units for exp, the key tier for rift, else unused.
-- Returns gained (whole number), the source's raw xp before the cap
function P.sourceGain(cfg, source, value, usedToday)
	local s = cfg.sources[source]
	if not s then
		return 0, 0
	end
	local raw
	if source == "exp" then
		raw = (tonumber(value) or 0) * s.xp
	elseif source == "rift" then
		raw = s.xp + (s.perTier or 0) * math.max(0, math.floor(tonumber(value) or 0))
	else
		raw = s.xp
	end
	local room = math.max(0, (s.dailyCap or math.huge) - (tonumber(usedToday) or 0))
	return math.max(0, math.min(raw, room)), raw
end

-- ---------------------------------------------------------------- periods (server local time)
function P.dayKey(t)
	return tonumber(os.date("%Y%m%d", t))
end

local function midnight(t, addDays)
	local d = os.date("*t", t)
	return os.time({year = d.year, month = d.month, day = d.day + (addDays or 0), hour = 0, min = 0, sec = 0})
end

-- the YYYYMMDD of the Monday that starts t's week
function P.weekKey(t)
	local wday = tonumber(os.date("%w", t)) -- 0 = Sunday
	local back = (wday + 6) % 7
	return P.dayKey(midnight(t, -back) + 3600)
end

function P.nextDay(t)
	return midnight(t, 1)
end

function P.nextWeek(t)
	local wday = tonumber(os.date("%w", t))
	return midnight(t, 7 - (wday + 6) % 7)
end

-- ---------------------------------------------------------------- challenges
-- small string hash: every step stays below 2^53, so LuaJIT (doubles) and Lua 5.3 (integers) agree; two Lehmer
-- rounds at the end mix the last characters into every residue
local function hash(s)
	local h = 5381
	for i = 1, #s do
		h = (h * 31 + s:byte(i)) % 2147483647
	end
	for _ = 1, 2 do
		h = (h * 48271) % 2147483647
	end
	return h
end

-- one entry of every slot, picked by the seed
function P.pick(slots, seed)
	local out = {}
	for i, slot in ipairs(slots or {}) do
		if #slot > 0 then
			out[#out + 1] = slot[hash(seed .. ":" .. i) % #slot + 1]
		end
	end
	return out
end

-- the challenges of a period: kind "daily" (period = dayKey) or "weekly" (period = weekKey)
function P.challenges(cfg, seasonId, kind, period)
	return P.pick(cfg.challenges[kind], string.format("%s:%s:%s", tostring(seasonId), kind, tostring(period)))
end

-- one game event -> {stat = amount} for the challenges. rift: value = tier
function P.statsOf(stat, value)
	if stat == "rift" then
		local out = {rift = 1}
		if (tonumber(value) or 0) >= 8 then
			out.rift8 = 1
		end
		return out
	elseif stat == "exp" then
		return {exp = tonumber(value) or 0}
	end
	return {[stat] = tonumber(value) or 1}
end

-- ---------------------------------------------------------------- packs and premium
function P.pack(pass, id)
	for _, p in ipairs(pass.packs or {}) do
		if p.id == id then
			return p
		end
	end
	return nil
end

function P.packIncludesPremium(pack)
	for _, r in ipairs(pack and pack.rewards or {}) do
		if r.kind == "premium" then
			return true
		end
	end
	return false
end

-- the highest pack of the account (rows: list of pack ids, or a set) -> id or 0
function P.ownedPack(rows)
	local best = 0
	for k, v in pairs(rows or {}) do
		local id = type(k) == "number" and v == true and k or tonumber(v)
		if id and id > best then
			best = id
		end
	end
	return best
end

function P.hasPremium(pass, premium, packId)
	if premium then
		return true
	end
	for _, p in ipairs(pass.packs or {}) do
		if p.id <= (packId or 0) and P.packIncludesPremium(p) then
			return true
		end
	end
	return false
end

-- price of pack `target` for an account that owns pack ownedPack (0 = none) and paid passPaid coins for the premium
-- pass bought on its own (0 = not bought). Returns price or nil, reason
function P.packPrice(pass, target, ownedPack, passPaid)
	local p = P.pack(pass, target)
	if not p then
		return nil, "This pack does not exist."
	end
	ownedPack = ownedPack or 0
	if ownedPack >= target then
		return nil, "Your account already owns " .. p.name .. (ownedPack > target and " (in a higher pack)." or ".")
	end
	local credit = 0
	local owned = P.pack(pass, ownedPack)
	if owned then
		credit = owned.price
	end
	-- a pack holds every lower pack, so the pass is in it when it or a lower pack has the premium reward
	if (passPaid or 0) > 0 and P.hasPremium(pass, false, target) and not P.hasPremium(pass, false, ownedPack) then
		credit = credit + passPaid
	end
	return math.max(0, p.price - credit)
end

-- one-time rewards (coins, tier skips) of the packs above fromId up to toId
function P.packGrants(pass, fromId, toId)
	local out = {}
	for _, p in ipairs(pass.packs or {}) do
		if p.id > (fromId or 0) and p.id <= toId then
			for _, r in ipairs(p.rewards) do
				if r.kind == "coins" or r.kind == "tierskips" then
					out[#out + 1] = r
				end
			end
		end
	end
	return out
end

-- ---------------------------------------------------------------- claims
-- view = {tier, premium, claimed = {[track] = {[tier] = true}}, open = bool (the season runs or is in its grace)}
-- track: P.FREE or P.PREMIUM. Returns reward or nil, reason
function P.claimCheck(pass, view, tier, track)
	tier = math.floor(tonumber(tier) or 0)
	local row = pass.tiers[tier]
	if not row then
		return nil, "That tier does not exist."
	end
	if track ~= P.FREE and track ~= P.PREMIUM then
		return nil, "Unknown track."
	end
	if not view.open then
		return nil, "The season pass is closed: its season is over."
	end
	if tier > (view.tier or 0) then
		return nil, string.format("Reach tier %d first.", tier)
	end
	if track == P.PREMIUM and not view.premium then
		return nil, "This reward is on the premium track."
	end
	if view.claimed and view.claimed[track] and view.claimed[track][tier] then
		return nil, "Already claimed."
	end
	return row[track + 1]
end

-- every {tier, track} that can be claimed now, in tier order
function P.claimable(pass, view)
	local out = {}
	for t = 1, math.min(view.tier or 0, #pass.tiers) do
		for _, track in ipairs({P.FREE, P.PREMIUM}) do
			if P.claimCheck(pass, view, t, track) then
				out[#out + 1] = {tier = t, track = track}
			end
		end
	end
	return out
end

-- the premium rewards a late buyer has already reached and not claimed: {tier, track = P.PREMIUM}, in tier order.
-- seasonpass.lua claims them at once when the premium track is bought (and at the next login of an account that got it
-- as a gift while offline), so buying late never means walking back through the tiers.
function P.premiumBacklog(pass, view)
	local out = {}
	if not view.premium then
		return out
	end
	for _, c in ipairs(P.claimable(pass, view)) do
		if c.track == P.PREMIUM then
			out[#out + 1] = c
		end
	end
	return out
end

-- "0110..." of n tiers (1 = claimed)
function P.claimedString(set, n)
	local parts = {}
	for t = 1, n do
		parts[t] = set and set[t] and "1" or "0"
	end
	return table.concat(parts)
end

-- ---------------------------------------------------------------- cosmetics of an account
-- claims = {[track] = {[tier] = true}}; packId = the highest pack owned. Returns the cosmetic rewards it owns.
function P.entitlements(pass, claims, packId)
	local out = {}
	for t, row in ipairs(pass.tiers) do
		for track = P.FREE, P.PREMIUM do
			local r = row[track + 1]
			if r and P.COSMETIC[r.kind] and claims and claims[track] and claims[track][t] then
				out[#out + 1] = r
			end
		end
	end
	for _, p in ipairs(pass.packs or {}) do
		if p.id <= (packId or 0) then
			for _, r in ipairs(p.rewards) do
				if P.COSMETIC[r.kind] then
					out[#out + 1] = r
				end
			end
		end
	end
	return out
end

function P.rewardText(r, lang)
	if not r then
		return ""
	end
	if r.name then
		return r.name
	end
	if r.kind == "title" then
		return T(lang, "Title: %s", tostring(r.title))
	elseif r.kind == "coins" then
		return T(lang, "%s Chaos Coins", tostring(r.amount))
	elseif r.kind == "tierskips" then
		return T(lang, "%s tier skips", tostring(r.count))
	elseif r.kind == "premium" then
		return T(lang, "Premium pass")
	end
	return r.kind
end

-- ---------------------------------------------------------------- config checks
local function same(a, b)
	if a.kind ~= b.kind then
		return false
	end
	if a.kind == "outfit" then
		return a.male == b.male and a.female == b.female
	elseif a.kind == "mount" or a.kind == "shader" then
		return a.id == b.id
	elseif a.kind == "portal" then
		return a.key == b.key
	elseif a.kind == "frame" then
		return a.frame == b.frame
	elseif a.kind == "transmog" then
		return a.key == b.key
	elseif a.kind == "title" then
		return a.title == b.title
	end
	return false
end
P.sameCosmetic = same

-- list of problems (empty = fine): reward kinds, allowed items, tier count, prices, packs, the cosmetics list
function P.validate(cfg)
	local problems = {}
	local function bad(text)
		problems[#problems + 1] = text
	end
	local registered = cfg.cosmetics or {}
	local function checkReward(r, where, packOnly, seasonId)
		if type(r) ~= "table" or not P.KINDS[r.kind] then
			bad(where .. ": unknown reward kind " .. tostring(r and r.kind))
			return
		end
		if not packOnly and not P.TRACK_KINDS[r.kind] then
			bad(where .. ": " .. r.kind .. " is a pack reward only")
		end
		if r.kind == "item" then
			if not cfg.allowedItems[r.id] then
				bad(where .. ": item " .. tostring(r.id) .. " is not an allowed item (gold, potions)")
			end
			if type(r.count) ~= "number" or r.count < 1 or r.count > 100 then
				bad(where .. ": item count 1..100")
			end
		elseif r.kind == "coins" and (type(r.amount) ~= "number" or r.amount < 1) then
			bad(where .. ": coins amount")
		elseif r.kind == "outfit" and (type(r.male) ~= "number" or type(r.female) ~= "number") then
			bad(where .. ": outfit looks")
		elseif r.kind == "tierskips" and (type(r.count) ~= "number" or r.count < 1) then
			bad(where .. ": tier skips count")
		elseif r.kind == "transmog" and type(r.key) ~= "string" then
			bad(where .. ": transmog set key")
		end
		if P.COSMETIC[r.kind] then
			local found = false
			for _, c in ipairs(registered) do
				if c.season == seasonId and type(c.reward) == "table" and same(c.reward, r) then
					found = true
				end
			end
			if not found then
				bad(where .. ": cosmetic " .. P.rewardText(r) .. " is not in the cosmetics list")
			end
		end
	end
	for seasonId, pass in pairs(cfg.passes or {}) do
		local w = "pass " .. tostring(seasonId)
		if #pass.tiers ~= cfg.maxTier then
			bad(w .. ": " .. #pass.tiers .. " tiers, maxTier is " .. cfg.maxTier)
		end
		if type(pass.premium) ~= "table" or type(pass.premium.price) ~= "number" or pass.premium.price <= 0 then
			bad(w .. ": premium price")
		end
		for t, row in ipairs(pass.tiers) do
			if type(row) ~= "table" or not row[1] or not row[2] then
				bad(w .. " tier " .. t .. ": needs a free and a premium reward")
			else
				checkReward(row[1], w .. " tier " .. t .. " free", false, seasonId)
				checkReward(row[2], w .. " tier " .. t .. " premium", false, seasonId)
				if type(row[2]) == "table" and not P.PREMIUM_KINDS[row[2].kind] then
					bad(w .. " tier " .. t .. " premium: " .. tostring(row[2].kind) .. " on the paid track (cosmetics and coins only)")
				end
			end
		end
		local lastPrice, unlocks = 0, {[pass.premium and pass.premium.unlock or "?"] = true}
		for i, p in ipairs(pass.packs or {}) do
			local pw = w .. " pack " .. tostring(p.id)
			if p.id ~= i then
				bad(pw .. ": pack ids must be 1, 2, 3 in order")
			end
			if type(p.price) ~= "number" or p.price <= lastPrice then
				bad(pw .. ": prices must go up")
			end
			lastPrice = p.price or lastPrice
			if not p.unlock or unlocks[p.unlock] then
				bad(pw .. ": unlock name missing or used twice")
			end
			unlocks[p.unlock or "?"] = true
			for j, r in ipairs(p.rewards or {}) do
				checkReward(r, pw .. " reward " .. j, true, seasonId)
			end
		end
	end
	-- a cosmetic may be given by one place only
	for i, a in ipairs(registered) do
		if type(a.reward) ~= "table" or not P.COSMETIC[a.reward.kind] then
			bad("cosmetics list entry " .. i .. ": needs a cosmetic reward")
		else
			for j = i + 1, #registered do
				if type(registered[j].reward) == "table" and same(a.reward, registered[j].reward) then
					bad("cosmetics list: " .. P.rewardText(a.reward) .. " listed twice")
				end
			end
		end
	end
	return problems
end

return P
