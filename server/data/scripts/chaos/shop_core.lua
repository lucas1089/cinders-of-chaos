-- shop_core.lua: the Chaos store's rules without engine calls (ChaosShopCore; tests/shop_test.lua).
--
--   C.offerKey(offer)                     stable id of an offer ("wings:4", "outfit:909", "item:29856x10", ...): sales,
--                                         featured lists, bundles, limits and the purchase log name offers by it
--   C.exclusions(src)                     {looks = set, mounts = set} of the cosmetics that are exclusive elsewhere:
--                                         src = {classLooks, classOutfits, achievements, season, seasonpass} (any may be
--                                         nil); also {wings, auras, shaders, frames} sets of reward cosmetics
--   C.excluded(offer, ex)                 reason text when the offer sells one of them, else nil
--   C.outfitLooks(offer)                  the look types an outfit offer gives (male and female), each once
--   C.parseTime(v)                        "YYYY-MM-DD HH:MM" (server time) or a number -> unix time; nil when invalid
--   C.weekKey(t, hour)                    week number; weeks start on Monday at `hour` (server time)
--   C.featured(pool, week, count)         `count` keys of `pool`, a different choice every week (deterministic)
--   C.price(offer, categoryName, ctx)     cost, oldCost (nil when not reduced), tags {"Sale", "New", "Featured"}
--   C.bundleCost(bundle, listSum)         a bundle's price: its own cost, or listSum minus its pct
--   C.giftProblem(t)                      why a gift to this target is refused, or nil
--   C.packCredit(pack, first, cfg)        {coins, bonus, firstBonus, total} for a paid Chaos Coin pack
--   C.validate(cfg, cosmetics, ex)        list of problems in shop_config.lua (keys, prices, sales, bundles, exclusives)
-- Lua 5.1 / LuaJIT / Lua 5.3 compatible.

ChaosShopCore = ChaosShopCore or {}
local C = ChaosShopCore

-- offer kinds that can be bought for another character (services and unlocks run per character, right away)
C.GIFTABLE = {item = true, wings = true, aura = true, shader = true, outfit = true, addons = true, mount = true,
	premium = true, frame = true, bundle = true}

-- ------------------------------------------------------------------ keys
function C.offerKey(o)
	if o.key then
		return o.key
	end
	local k = o.kind
	if k == "item" then
		return "item:" .. tostring(o.id) .. "x" .. tostring(o.count or 1)
	elseif k == "wings" or k == "aura" or k == "shader" or k == "mount" then
		return k .. ":" .. tostring(o.id)
	elseif k == "outfit" then
		return "outfit:" .. tostring(o.looktype)
	elseif k == "addons" then
		return "addons:" .. tostring(o.looktype)
	elseif k == "premium" then
		return "premium:" .. tostring(o.days)
	elseif k == "frame" then
		return "frame:" .. tostring(o.frame)
	elseif k == "service" then
		return "service:" .. tostring(o.service) .. (o.buff and (":" .. o.buff) or "") .. (o.pouch and (":" .. o.pouch) or "")
	elseif k == "unlock" then
		return "unlock:" .. tostring(o.unlock)
	elseif k == "pact" then
		return "pact:" .. tostring(o.days)
	end
	return tostring(k) .. ":" .. tostring(o.name)
end

-- ------------------------------------------------------------------ exclusives
local function addLook(set, v)
	v = tonumber(v)
	if v then
		set[v] = true
	end
end

-- walks a table (achievements_data, season_config) for reward outfits and mounts
local function walkRewards(t, ex, seen)
	if type(t) ~= "table" or seen[t] then
		return
	end
	seen[t] = true
	local r = t.reward
	if type(r) == "table" then
		if type(r.outfit) == "table" then
			addLook(ex.looks, r.outfit.male); addLook(ex.looks, r.outfit.female)
		end
		if type(r.mount) == "table" then
			addLook(ex.mounts, r.mount.id)
		end
		if r.kind == "outfit" or r.kind == "addon" then
			addLook(ex.looks, r.male); addLook(ex.looks, r.female)
		elseif r.kind == "mount" then
			addLook(ex.mounts, r.id)
		elseif r.kind == "wings" or r.kind == "aura" or r.kind == "shader" then
			addLook(ex[r.kind], r.id)
		elseif r.kind == "frame" and r.frame then
			ex.frames[r.frame] = true
		end
	end
	for _, v in pairs(t) do
		walkRewards(v, ex, seen)
	end
end

function C.exclusions(src)
	src = src or {}
	local ex = {looks = {}, mounts = {}, wings = {}, aura = {}, shader = {}, frames = {}}
	for _, e in pairs(src.classLooks or {}) do
		addLook(ex.looks, e.male); addLook(ex.looks, e.female)
	end
	for _, list in pairs(src.classOutfits or {}) do
		for _, o in ipairs(list) do
			addLook(ex.looks, o.lookType)
		end
	end
	local seen = {}
	walkRewards(src.achievements, ex, seen)
	walkRewards(src.season, ex, seen)
	walkRewards(src.seasonpass, ex, seen)
	for _, v in ipairs(src.looks or {}) do
		addLook(ex.looks, v)
	end
	for _, v in ipairs(src.mounts or {}) do
		addLook(ex.mounts, v)
	end
	return ex
end

function C.excluded(offer, ex)
	if offer.kind == "outfit" or offer.kind == "addons" then
		for _, look in ipairs(C.outfitLooks(offer)) do
			if ex.looks[look] then
				return "look " .. look .. " is a class look or a reward"
			end
		end
	elseif offer.kind == "mount" and ex.mounts[offer.id] then
		return "mount " .. offer.id .. " is a reward"
	elseif (offer.kind == "wings" or offer.kind == "aura" or offer.kind == "shader") and ex[offer.kind] and ex[offer.kind][offer.id] then
		return offer.kind .. " " .. offer.id .. " is a reward"
	elseif offer.kind == "frame" and ex.frames and ex.frames[offer.frame] then
		return "frame " .. tostring(offer.frame) .. " is a reward"
	end
	return nil
end

function C.outfitLooks(offer)
	local out = {offer.looktype}
	if offer.lookfemale and offer.lookfemale ~= offer.looktype then
		out[2] = offer.lookfemale
	end
	return out
end

-- ------------------------------------------------------------------ time
function C.parseTime(v)
	if type(v) == "number" then
		return v
	end
	if type(v) ~= "string" then
		return nil
	end
	local y, mo, d, h, mi = v:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)%s+(%d%d):(%d%d)$")
	if not y then
		y, mo, d = v:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
		h, mi = 0, 0
	end
	if not y then
		return nil
	end
	return os.time({year = tonumber(y), month = tonumber(mo), day = tonumber(d), hour = tonumber(h), min = tonumber(mi), sec = 0})
end

-- 1970-01-05 was a Monday
function C.weekKey(t, hour)
	local monday = os.time({year = 1970, month = 1, day = 5, hour = hour or 0, min = 0, sec = 0})
	return math.floor((t - monday) / 604800)
end

-- `count` distinct entries of `pool`, the same all week, another set next week
function C.featured(pool, week, count)
	local list = {}
	for i, v in ipairs(pool or {}) do
		list[i] = v
	end
	local seed = (week * 7919 + 104729) % 2147483647
	for i = #list, 2, -1 do
		seed = (seed * 48271) % 2147483647
		local j = seed % i + 1
		list[i], list[j] = list[j], list[i]
	end
	local out = {}
	for i = 1, math.min(count or 0, #list) do
		out[i] = list[i]
	end
	return out
end

-- ------------------------------------------------------------------ prices
local function inList(list, v)
	for _, x in ipairs(list or {}) do
		if x == v then
			return true
		end
	end
	return false
end

local function active(s, now)
	local from, to = C.parseTime(s.from), C.parseTime(s.to)
	return (not from or now >= from) and (not to or now < to)
end

-- ctx = {now, sales = {{offers?, categories?, kinds?, pct, from?, to?, tag?}}, featured = {key = pct},
--        new = {{offers?, categories?, until}}}; discounts do not stack (the biggest wins); bundles and starter packs keep their price
function C.price(offer, categoryName, ctx)
	ctx = ctx or {}
	local now = ctx.now or os.time()
	local key = C.offerKey(offer)
	local cost, best, tags = offer.cost, 0, {}
	local saleTag
	if offer.kind ~= "bundle" and not offer.noSale then
		for _, s in ipairs(ctx.sales or {}) do
			if active(s, now) and (inList(s.offers, key) or inList(s.categories, categoryName) or inList(s.kinds, offer.kind)) then
				local pct = tonumber(s.pct) or 0
				if pct > best then
					best, saleTag = pct, s.tag or "Sale"
				end
			end
		end
		local f = ctx.featured and ctx.featured[key]
		if f then
			tags[#tags + 1] = "Featured"
			if f > best then
				best, saleTag = f, "Sale"
			end
		end
	end
	for _, n in ipairs(ctx.new or {}) do
		local untilT = C.parseTime(n["until"])
		if (inList(n.offers, key) or inList(n.categories, categoryName)) and (not untilT or now < untilT) then
			tags[#tags + 1] = "New"
			break
		end
	end
	if best > 0 then
		best = math.min(best, 90)
		local reduced = math.max(1, math.floor(cost * (100 - best) / 100))
		if reduced < cost then
			table.insert(tags, 1, saleTag .. " -" .. best .. "%")
			return reduced, cost, tags
		end
	end
	return cost, nil, tags
end

function C.bundleCost(bundle, listSum)
	if bundle.cost then
		return bundle.cost
	end
	local pct = math.max(0, math.min(90, tonumber(bundle.pct) or 0))
	return math.max(1, math.floor(listSum * (100 - pct) / 100))
end

-- ------------------------------------------------------------------ gifts
-- t = {found, self, staff, banned, sameAccount?, kind}
function C.giftProblem(t)
	if not t.found then
		return "There is no character with that name."
	end
	if t.self then
		return "Buy it for yourself with the Buy button."
	end
	if t.staff then
		return "Gifts cannot go to staff characters."
	end
	if t.banned then
		return "That account cannot receive gifts."
	end
	if t.kind and not C.GIFTABLE[t.kind] then
		return "This offer cannot be gifted."
	end
	return nil
end

-- ------------------------------------------------------------------ coin packs
-- pack = {coins, bonusPct?, bonusCoins?}; first = true for the first credited pack of the account (not the starter)
function C.packCredit(pack, first, cfg)
	local coins = math.floor(tonumber(pack.coins) or 0)
	local bonus = math.floor(coins * (tonumber(pack.bonusPct) or 0) / 100) + math.floor(tonumber(pack.bonusCoins) or 0)
	local firstBonus = 0
	if first and not pack.starter and cfg and cfg.firstPurchase then
		firstBonus = math.floor(coins * (tonumber(cfg.firstPurchase.bonusPct) or 0) / 100)
	end
	return {coins = coins, bonus = bonus, firstBonus = firstBonus, total = coins + bonus + firstBonus}
end

-- ------------------------------------------------------------------ config check
function C.validate(cfg, ex)
	local problems, keys = {}, {}
	local function bad(s)
		problems[#problems + 1] = s
	end
	for _, cat in ipairs(cfg.categories or {}) do
		for _, o in ipairs(cat.offers or {}) do
			local key = C.offerKey(o)
			if keys[key] then
				bad("offer " .. key .. " twice (" .. keys[key] .. ", " .. cat.name .. ")")
			end
			keys[key] = cat.name
			if o.kind ~= "bundle" and (type(o.cost) ~= "number" or o.cost < 1) then
				bad("offer " .. key .. ": no cost")
			end
			local why = ex and C.excluded(o, ex)
			if why then
				bad("offer " .. key .. ": " .. why)
			end
		end
	end
	local sf = cfg.storefront or {}
	for _, cat in ipairs(cfg.categories or {}) do
		for _, o in ipairs(cat.offers or {}) do
			if o.kind == "bundle" then
				for _, p in ipairs(o.parts or {}) do
					if type(p) == "string" and not keys[p] then
						bad("bundle " .. C.offerKey(o) .. ": unknown part " .. p)
					end
					if type(p) == "table" and p.kind == "bundle" then
						bad("bundle " .. C.offerKey(o) .. ": a bundle in a bundle")
					end
				end
			end
		end
	end
	for i, s in ipairs(sf.sales or {}) do
		local pct = tonumber(s.pct)
		if not pct or pct < 1 or pct > 90 then
			bad("sale " .. i .. ": pct 1..90")
		end
		if (s.from and not C.parseTime(s.from)) or (s.to and not C.parseTime(s.to)) then
			bad("sale " .. i .. ": bad time")
		end
		for _, k in ipairs(s.offers or {}) do
			if not keys[k] then
				bad("sale " .. i .. ": unknown offer " .. k)
			end
		end
	end
	for _, k in ipairs((sf.featured or {}).pool or {}) do
		if not keys[k] then
			bad("featured: unknown offer " .. k)
		end
	end
	for _, n in ipairs(sf.new or {}) do
		for _, k in ipairs(n.offers or {}) do
			if not keys[k] then
				bad("new: unknown offer " .. k)
			end
		end
	end
	return problems
end

return C
