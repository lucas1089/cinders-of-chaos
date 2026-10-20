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
--   C.weekEnds(t, hour)                   when the week of t ends (the weekly rotation's countdown)
--   C.price(offer, categoryName, ctx)     cost, oldCost (nil when not reduced), tags {"Sale", "New", "Featured"}
--   C.bundleCost(bundle, listSum)         a bundle's price: its own cost, or listSum minus its pct
--   C.giftProblem(t)                      why a gift to this target is refused, or nil
--   C.coinGiftProblem(rules, f, lang?)    why a Chaos Coin gift is refused (hold after a donation, daily cap, ban), or nil
--                                         (in `lang` through ChaosI18n when it is loaded; English otherwise)
--   C.clawbackPlan(shortfall, gifts)      what to take back from the receivers of a charged-back donor's coin gifts
--   C.packCredit(pack, first, cfg)        {coins, bonus, firstBonus, total} for a paid Chaos Coin pack
--   C.validate(cfg, cosmetics, ex)        list of problems in shop_config.lua (keys, prices, sales, bundles, exclusives)
--   C.iconCount(icon, stackable)          the count an item picture is drawn with (a pile for a stackable item)
--   C.FRAMES / C.frameIndex(frame) / C.frameStorage(S, i)   name plate frames: the order is the ownership storage slot
--                                         (shop.lua kind "frame", exclusives.lua kind "frame")
-- Lua 5.1 / LuaJIT / Lua 5.3 compatible.

ChaosShopCore = ChaosShopCore or {}
local C = ChaosShopCore

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

-- offer kinds that can be bought for another character (services and unlocks run per character, right away)
C.GIFTABLE = {item = true, wings = true, aura = true, shader = true, outfit = true, addons = true, mount = true,
	premium = true, frame = true, bundle = true}

-- ------------------------------------------------------------------ item pictures (offer and category icons)
-- A stackable item is drawn by its count: one small gem or coin is a few pixels in the 32 px cell (live test
-- 2026-10-14: the Stormcaller Regalia, a small amethyst, showed as a dot). Without its own iconCount (offers) or count
-- (category icons) a stackable picture is drawn as a pile; anything else as one item.
C.ICON_PILE = 100

-- icon = an offer ({iconCount}) or a category icon ({count}); stackable = the engine's ItemType:isStackable()
function C.iconCount(icon, stackable)
	local n = icon and (icon.iconCount or icon.count)
	if n then
		return n
	end
	return stackable and C.ICON_PILE or 1
end

-- ------------------------------------------------------------------ what an offer looks like (icon and preview)
-- An offer's own appearance as a look option, the shape of the client's LookPreviewCore options (sent as `look` in the
-- offer; the client draws the icon from it and, when the offer is picked, the character preview):
--   {kind = "outfit" | "addons", look = looktype, addons = 3}   {kind = "mount" | "wings" | "aura", look = client id}
--   {kind = "shader", shader = name}   {kind = "outline", art, pulse?}   {kind = "footprint", art}
--   {kind = "effects", play, killfx?}  {kind = "swatch", color, accent?}  {kind = "nameplate", frame}
--   {kind = "subject", look = looktype}  (a pet)   {kind = "bundle", parts = {look, ...}}
-- nil for offers that are not an appearance (items, services, premium time, convenience unlocks): the client then
-- draws the item picture. src supplies what only the engine side knows: outfitLook(offer) (the viewer's sex),
-- wings(id) / aura(id) -> client id, shader(id) -> name, cosmetic(unlockName) -> a cosmetics_core.lua offerLook.
function C.lookOf(offer, src)
	if type(offer) ~= "table" then
		return nil
	end
	src = src or {}
	local k = offer.kind
	if k == "outfit" or k == "addons" then
		local look = src.outfitLook and src.outfitLook(offer) or offer.looktype
		return look and {kind = k, look = look, addons = 3} or nil
	elseif k == "mount" then
		return (offer.clientid or 0) > 0 and {kind = "mount", look = offer.clientid} or nil
	elseif k == "wings" or k == "aura" then
		local id = src[k] and src[k](offer.id) or 0
		return (id or 0) > 0 and {kind = k, look = id} or nil
	elseif k == "shader" then
		local name = src.shader and src.shader(offer.id)
		return type(name) == "string" and name ~= "" and {kind = "shader", shader = name} or nil
	elseif k == "frame" then
		return type(offer.frame) == "string" and {kind = "nameplate", frame = offer.frame} or nil
	elseif k == "unlock" then
		if offer.look then
			return {kind = "subject", look = offer.look}
		end
		return src.cosmetic and type(offer.unlock) == "string" and src.cosmetic(offer.unlock) or nil
	elseif k == "bundle" then
		local parts = {}
		for _, p in ipairs(offer.resolved or {}) do
			local l = C.lookOf(p, src)
			if l then
				parts[#parts + 1] = l
			end
		end
		return #parts > 0 and {kind = "bundle", parts = parts} or nil
	end
	return nil
end

-- Whether a category of the store shows its first cosmetic as its icon. The category cell is small and tall, so a plate
-- frame (a wide 9-slice), a footprint (a long print, rotated), a loot label accent (a plain colour block) and a spell
-- effect (its frame reads as a dark ring) drew as broken pictures in the beta; those categories keep their item icon.
-- A kill effect, an outline, a chat colour sample and the creatures (outfits, mounts, wings ...) read well.
function C.categoryShowsLook(look)
	if type(look) ~= "table" or look.kind == "bundle" then
		return false
	end
	if look.kind == "nameplate" or look.kind == "footprint" then
		return false
	end
	if look.kind == "swatch" then
		return look.accent ~= true
	end
	if look.kind == "effects" then
		return look.killfx == true
	end
	return true
end

-- The outfit a creature icon of a look is drawn with, or nil when the icon is no creature (a print, an effect, a colour,
-- a plate frame): an outline is worn by the plain figure (neutral), a mount alone or a pet is drawn alone, the other
-- parts on the preview figure, a bundle by its parts merged (outfit, mount, wings, aura, shader).
-- preview / neutral: the outfit tables of shop_config.lua (the store's preview figure, the plain one).
local function copyTable(t)
	local o = {}
	for k, v in pairs(t or {}) do
		o[k] = v
	end
	return o
end

-- put one look on outfit o; true when it changed something
local function wear(o, p)
	if p.kind == "outfit" or p.kind == "addons" then
		o.type, o.addons = p.look, 3
		o.head, o.body, o.legs, o.feet = 2, 116, 114, 114 -- the colours the store gives an outfit
	elseif p.kind == "mount" or p.kind == "wings" or p.kind == "aura" then
		o[p.kind] = p.look
	elseif p.kind == "shader" then
		o.shader = p.shader
	else
		return false
	end
	return true
end

function C.iconOutfit(look, preview, neutral)
	if type(look) ~= "table" then
		return nil
	end
	local o
	if look.kind == "outline" then
		o = copyTable(neutral)
	elseif look.kind == "subject" then
		o = {type = look.look}
	elseif look.kind == "mount" then
		o = {type = look.look} -- a mount is drawn alone, as a creature
	elseif look.kind == "bundle" then
		o = copyTable(preview)
		local any = false
		for _, p in ipairs(look.parts or {}) do
			any = wear(o, p) or p.kind == "outline" or any
		end
		if not any then
			return nil
		end
	else
		o = copyTable(preview)
		if not wear(o, look) then
			return nil
		end
	end
	o.rotating = true
	return o
end

-- ------------------------------------------------------------------ name plate frames
-- index = the frame's slot: never reorder, only append. 1-5 the first store frames, 6-13 the second set of store frames,
-- 14-16 never sold (exclusives_config.lua). Slots 1-8 own storage Chaos.storage.shopFrameBase + i (7100761-7100768),
-- slots 9 and up Chaos.storage.shopFrameBase2 + i - 9 (7102010-7102039); Chaos.storage.shopFrameActive = the slot shown.
C.FRAMES = {"violet", "frost", "ember", "verdant", "bone", "ashen", "sapphire", "rose", "jade", "copper", "obsidian",
	"amber", "storm", "laurel", "sepulchre", "infernal"}
C.FRAME_SLOTS2 = 30 -- 7102010 - 7102039

function C.frameIndex(frame)
	for i, f in ipairs(C.FRAMES) do
		if f == frame then
			return i
		end
	end
	return nil
end

function C.frameStorage(S, i)
	i = tonumber(i)
	if not i or i < 1 or i % 1 ~= 0 then
		return nil
	end
	if i <= 8 then
		return S.shopFrameBase + i
	end
	if i - 9 >= C.FRAME_SLOTS2 then
		return nil
	end
	return S.shopFrameBase2 + i - 9
end

-- ------------------------------------------------------------------ outfit shaders
-- a store or season pass shader leaves a mark in Chaos.storage.shopShaderBase + id (7100701-7100759) and the engine's
-- ownership (Player:addShader). Before server src-patch 0036 the engine dropped that ownership, so the mark stayed
-- alone and the Outfit window listed nothing; shop.lua adds the ownership again at login for every marked id.
C.SHADER_MARKS = 59

-- the shaders.xml ids with a mark: value(id) is the mark's storage value
function C.markedShaders(value)
	local ids = {}
	for id = 1, C.SHADER_MARKS do
		if (tonumber(value(id)) or 0) > 0 then
			ids[#ids + 1] = id
		end
	end
	return ids
end

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
	-- the exclusives (exclusives_config.lua): never sold
	for _, e in ipairs(src.exclusives and src.exclusives.exclusives or {}) do
		if e.kind == "outfit" or e.kind == "addons" then
			addLook(ex.looks, e.male); addLook(ex.looks, e.female)
		elseif e.kind == "mount" then
			addLook(ex.mounts, e.id)
		elseif e.kind == "wings" or e.kind == "aura" or e.kind == "shader" then
			addLook(ex[e.kind], e.id)
		elseif e.kind == "frame" and e.frame then
			ex.frames[e.frame] = true
		end
	end
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

-- unix time the week of t ends (the next Monday at `hour`): the weekly rotation changes then
function C.weekEnds(t, hour)
	local monday = os.time({year = 1970, month = 1, day = 5, hour = hour or 0, min = 0, sec = 0})
	return monday + (C.weekKey(t, hour) + 1) * 604800
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

-- ------------------------------------------------------------------ coin gifts
-- Chaos Coins given to another account must not outlive a chargeback of the donation that bought them.
-- rules = shop_config.lua coinGifts {holdDays, perDay}; f = {now, amount, lastCredited (unix time of the sender's last
-- credited coin order, 0 = none), giftedToday (coins gifted by the sender in the last 24 hours), targetBanned}
function C.coinGiftProblem(rules, f, lang)
	rules = rules or {}
	if f.targetBanned then
		return "That account cannot receive gifts."
	end
	local hold = (tonumber(rules.holdDays) or 0) * 86400
	local last = tonumber(f.lastCredited) or 0
	if hold > 0 and last > 0 and f.now - last < hold then
		local days = math.ceil((hold - (f.now - last)) / 86400)
		return T(lang, days == 1 and "Chaos Coins can be gifted %d days after your last donation (in %d day)." or
			"Chaos Coins can be gifted %d days after your last donation (in %d days).", rules.holdDays, days)
	end
	local cap = tonumber(rules.perDay) or 0
	if cap > 0 and (tonumber(f.giftedToday) or 0) + f.amount > cap then
		local left = math.max(0, cap - (tonumber(f.giftedToday) or 0))
		return T(lang, "You can gift at most %d Chaos Coins a day (%d left today).", cap, left)
	end
	return nil
end

-- shortfall: coins of a reversed donation the donor's balance could not cover; gifts: the donor's coin gifts made since
-- that donation, newest first {id, to_account, amount, clawed, balance (the receiver's coins now)}. Takes from the newest
-- gift first, never more than a gift's unclawed rest or the receiver's balance. Returns {{id, account, take}}, the rest
-- that could not be taken back (to be flagged for staff).
function C.clawbackPlan(shortfall, gifts)
	local plan, left = {}, math.max(0, math.floor(tonumber(shortfall) or 0))
	local balances = {}
	for _, g in ipairs(gifts or {}) do
		if left <= 0 then
			break
		end
		local acc = g.to_account
		if balances[acc] == nil then
			balances[acc] = math.max(0, math.floor(tonumber(g.balance) or 0))
		end
		local open = math.max(0, (tonumber(g.amount) or 0) - (tonumber(g.clawed) or 0))
		local take = math.min(left, open, balances[acc])
		if take > 0 then
			plan[#plan + 1] = {id = g.id, account = acc, take = take}
			balances[acc] = balances[acc] - take
			left = left - take
		end
	end
	return plan, left
end

-- ------------------------------------------------------------------ coin packs
-- pack = {coins, bonusPct?, bonusCoins?}; first = true for the first credited pack of the account (not the starter)
function C.packCredit(pack, first, cfg)
	local coins = math.floor(tonumber(pack.coins) or 0)
	local bonus = math.floor(coins * (tonumber(pack.bonusPct) or 0) / 100) + math.floor(tonumber(pack.bonusCoins) or 0)
	local firstBonus = 0
	if first and not pack.starter and cfg and cfg.firstPurchase then
		firstBonus = math.floor(coins * (tonumber(cfg.firstPurchase.bonusPct) or 0) / 100)
		local cap = tonumber(cfg.firstPurchase.maxBonus)
		if cap and cap > 0 then
			firstBonus = math.min(firstBonus, math.floor(cap)) -- "Limite a 1000": double up to +1000 extra
		end
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
