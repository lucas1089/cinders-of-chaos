-- Chaos market: the rules without engine calls (tested by server/tests/market_test.lua with LuaJIT and Lua 5.3).
-- market.lua does the database, the items and the protocol; market_config.lua has every number.
--   ChaosMarketCore.fee(cfg, gold, coins)                    listing fee in gold
--   ChaosMarketCore.tax(cfg, currency, price)                tax, net (what the seller receives)
--   ChaosMarketCore.checkPrices(cfg, gold, coins, days)      normalized prices + days, or nil and the refusal
--   ChaosMarketCore.itemRefusal(info, cfg)                   why an item cannot be listed (nil = it can)
--   ChaosMarketCore.realmOf(storedRealm, currentSeason)      the market an offer is on (0 = standard)
--   ChaosMarketCore.browseQuery(filter, realm, now, cfg, esc, season, known)  WHERE / ORDER BY of a Browse page
--   ChaosMarketCore.offerIndex(tip)                          the searchable facts of an offer (modifiers, sockets, ...)
--   ChaosMarketCore.modFilter(filter, cfg, known)            the checked modifier filter of a Browse request
--   ChaosMarketCore.deliveryPlan(rows, mark)                 which owed rows are already applied, which to apply
--   ChaosMarketCore.pendingAction(offerId, listSeq)          a half-done listing after a crash: activate or drop
--   ChaosMarketCore.hex / unhex, encodeAttrs / decodeAttrs   the escrow codecs' text forms
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.

if not ChaosRarity then
	dofile("data/lib/chaos_rarity.lua")
end

ChaosMarketCore = ChaosMarketCore or {}
local C = ChaosMarketCore

local floor = math.floor

C.STATE = {active = 0, sold = 1, cancelled = 2, expired = 3, pending = 9}
C.STATE_NAME = {[0] = "active", [1] = "sold", [2] = "cancelled", [3] = "expired", [9] = "pending"}

local function int(v)
	v = tonumber(v)
	-- beyond +-2^53 no exact integer: "%d" in an SQL string fails (Lua 5.3) or reads -2^63 (LuaJIT)
	if not v or v ~= v or v > 9007199254740992 or v < -9007199254740992 then
		return nil
	end
	return floor(v)
end
C.int = int

-- ------------------------------------------------------------------ money
function C.fee(cfg, gold, coins)
	local f = cfg.listingFee
	gold, coins = int(gold) or 0, int(coins) or 0
	local base = gold > 0 and gold or coins * (f.coinFeeGold or 0)
	local fee = floor(base * f.pct / 100)
	if fee < f.minFee then
		fee = f.minFee
	end
	if f.maxFee and fee > f.maxFee then
		fee = f.maxFee
	end
	return fee
end

function C.tax(cfg, currency, price)
	price = int(price) or 0
	local pct = cfg.tax[currency] or 0
	local tax = floor(price * pct / 100)
	if tax < 0 then
		tax = 0
	end
	return tax, price - tax
end

-- gold / coins: 0 or nil = not sold for it; at least one price. Returns gold, coins, days or nil, refusal
function C.checkPrices(cfg, gold, coins, days)
	gold, coins = int(gold) or 0, int(coins) or 0
	if gold < 0 or coins < 0 then
		return nil, "Prices cannot be negative."
	end
	if gold == 0 and coins == 0 then
		return nil, "Set a price in gold, in Chaos Coins or in both."
	end
	local pg, pc = cfg.price.gold, cfg.price.coins
	if gold > 0 and (gold < pg.min or gold > pg.max) then
		return nil, string.format("A gold price must be between %s and %s.", C.money(pg.min), C.money(pg.max))
	end
	if coins > 0 and (coins < pc.min or coins > pc.max) then
		return nil, string.format("A coin price must be between %s and %s.", C.money(pc.min), C.money(pc.max))
	end
	days = int(days) or cfg.defaultDuration
	local okDays = false
	for _, d in ipairs(cfg.durations) do
		if d == days then
			okDays = true
		end
	end
	if not okDays then
		return nil, "Choose one of the offer durations."
	end
	return gold, coins, days
end

-- 1234567 -> "1,234,567"
function C.money(n)
	local s = tostring(int(n) or 0)
	local sign = ""
	if s:sub(1, 1) == "-" then
		sign, s = "-", s:sub(2)
	end
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if out:sub(1, 1) == "," then
		out = out:sub(2)
	end
	return sign .. out
end

-- ------------------------------------------------------------------ what may be listed
-- info = {equipped, locked, container, contents, pickupable, movable, store, storeBound (store pouches:
--         ChaosPouches.isPouch / custom attribute chaos_storebound), uniqueId, actionId, id, count, have, decaying}
function C.itemRefusal(info, cfg)
	if not info or not info.id then
		return "That item is no longer where it was."
	end
	if info.equipped then
		return "Take the item off before you list it."
	end
	if info.locked then
		return "The item is locked. Unlock it first."
	end
	if info.store or info.storeBound then
		return "Store items cannot be sold."
	end
	if info.container and (info.contents or 0) > 0 then
		return "Empty the container before you list it."
	end
	if info.pickupable == false or info.movable == false then
		return "That item cannot be sold."
	end
	if cfg.blockedIds[info.id] then
		return "That item cannot be sold on the market."
	end
	if (info.uniqueId or 0) > 0 then
		return "Quest items cannot be sold."
	end
	if info.actionId and info.actionId > 0 and cfg.blockedActionIds[info.actionId] then
		return "Quest items cannot be sold."
	end
	if info.decaying then
		return "Items that are wearing off cannot be sold."
	end
	local count = int(info.count) or 0
	if count < 1 or count > (info.have or 0) then
		return "You do not have that many."
	end
	return nil
end

-- ------------------------------------------------------------------ seasons
-- the market an offer is on: its season while that season runs, the standard market (0) otherwise (an ended season's
-- characters are standard characters again, so are their offers)
function C.realmOf(storedRealm, currentSeason)
	storedRealm = int(storedRealm) or 0
	if storedRealm ~= 0 and storedRealm == (int(currentSeason) or 0) then
		return storedRealm
	end
	return 0
end

-- ------------------------------------------------------------------ categories and modifiers
-- the category an item is filed under: its gear kind (chaos_item_mods.lua M.kindOf), else orb / gem / key / misc
function C.category(kind, name, isGem, isKey, rarity)
	-- "other" is any item that fits a hand slot: gear only when it rolled a rarity (an orb or a torch is not gear)
	if kind and kind ~= "" and (kind ~= "other" or (tonumber(rarity) or 0) > 0) then
		return kind
	end
	if isKey then
		return "key"
	end
	if isGem then
		return "gem"
	end
	name = tostring(name or ""):lower()
	if name:find("orb") then
		return "orb"
	end
	return "misc"
end

-- the modifier keys of an item as one searchable field ",key1,key2,"
function C.modsField(keys)
	local seen, list = {}, {}
	for _, k in ipairs(keys or {}) do
		k = tostring(k):lower():gsub("[^%w_]", "")
		if k ~= "" and not seen[k] then
			seen[k] = true
			list[#list + 1] = k
		end
	end
	if #list == 0 then
		return ""
	end
	local s = "," .. table.concat(list, ",") .. ","
	if #s > 1000 then
		s = s:sub(1, 1000)
	end
	return s
end

-- ------------------------------------------------------------------ the modifier index (chaos_market_offer_mods)
local function clampInt(v, lo, hi)
	v = int(v) or lo
	if v < lo then
		return lo
	end
	if v > hi then
		return hi
	end
	return v
end
C.clampInt = clampInt

-- the searchable facts of an offer from its tooltip snapshot (ChaosItemTooltip.build): every modifier with its value and
-- tier ({key, value, tier}; a critical / leech pair by its amount, the number its tiers are made of; a unique's
-- modifiers have tier 0), sockets, quality, the free prefix / suffix slots (the rarity's limit, plus the Orb of Ruin's
-- extra slot, minus what is there; none on a unique, a ruined or a corrupted item: no orb changes those), whether it has a
-- legendary power and how many bound modifiers
function C.offerIndex(tip)
	tip = type(tip) == "table" and tip or {}
	local out = {mods = {}, sockets = 0, quality = 0, freePrefix = 0, freeSuffix = 0, hasPower = 0, bound = 0}
	local seen = {}
	for _, m in ipairs(type(tip.mods) == "table" and tip.mods or {}) do
		local key = tostring(m.k or ""):lower():gsub("[^%w_]", "")
		if key ~= "" and #key <= 48 and not seen[key] then
			seen[key] = true
			local value = m.g == "special" and (int(m.v2) or 0) ~= 0 and int(m.v2) or (int(m.v) or 0)
			out.mods[#out.mods + 1] = {key = key, value = clampInt(value, -1000000000, 1000000000),
				tier = clampInt(m.tr, 0, 99)}
			if m.pw then
				out.hasPower = 1
			end
			if m.bd then
				out.bound = out.bound + 1
			end
		end
	end
	if type(tip.sockets) == "table" then
		out.sockets = clampInt(tip.sockets.count, 0, 99)
	end
	if type(tip.quality) == "table" then
		out.quality = clampInt(tip.quality.q, 0, 999)
	end
	local sd = tip.sides
	if type(sd) == "table" and not tip.unique and not tip.ruined and not tip.corrupted then
		out.freePrefix = clampInt((int(sd.mp) or int(sd.max) or 0) - (int(sd.p) or 0), 0, 9)
		out.freeSuffix = clampInt((int(sd.ms) or int(sd.max) or 0) - (int(sd.s) or 0), 0, 9)
	end
	return out
end

local function flag(v)
	return v == true or v == 1 or v == "1" or v == "true"
end

-- the modifier part of a Browse filter, checked: up to cfg.modFilter.maxRows rows {k = modifier key, min = lowest
-- value, t = lowest tier (T1 lowest .. T8 best; "T5" = T5 or better)}, need = how many of the rows must match (0 / nil
-- = all), sockets, quality (lowest), freeP / freeS (a free prefix / suffix slot), power (a legendary power), bound (a
-- bound modifier). Unknown keys, a modifier twice and too many rows are refused; numbers are clamped. A Browse of the
-- old client (`mod` = one key) is one row. Returns the normalized filter or nil, why
function C.modFilter(filter, cfg, known)
	filter = type(filter) == "table" and filter or {}
	local L = cfg.modFilter or {}
	local maxRows, maxTier = L.maxRows or 6, L.maxTier or 8
	local rows = filter.mods
	if rows == nil and filter.mod ~= nil and filter.mod ~= "" then
		rows = {{k = filter.mod}}
	end
	if rows ~= nil and type(rows) ~= "table" then
		return nil, "That modifier filter is not valid."
	end
	local out = {mods = {}}
	local seen = {}
	local n = 0
	for _ in pairs(rows or {}) do
		n = n + 1
	end
	if n > maxRows then
		return nil, string.format("At most %d modifiers per search.", maxRows)
	end
	for i = 1, n do
		local r = rows[i]
		if type(r) ~= "table" then
			return nil, "That modifier filter is not valid."
		end
		local raw = tostring(r.k or "")
		local key = raw:lower()
		if key == "" or #key > 48 or key:find("[^%w_]") then
			return nil, "Unknown modifier."
		end
		if known and not known[key] then
			return nil, "Unknown modifier."
		end
		if seen[key] then
			return nil, "Each modifier only once per search."
		end
		seen[key] = true
		out.mods[#out.mods + 1] = {key = key, min = clampInt(r.min, 0, L.maxValue or 1000000), tier = clampInt(r.t, 0, maxTier)}
	end
	local need = int(filter.need) or 0
	if need <= 0 or need > #out.mods then
		need = #out.mods
	end
	out.need = need
	out.sockets = clampInt(filter.sockets, 0, L.maxSockets or 8)
	out.quality = clampInt(filter.quality, 0, L.maxQuality or 30)
	out.freePrefix = flag(filter.freeP)
	out.freeSuffix = flag(filter.freeS)
	out.power = flag(filter.power)
	out.bound = flag(filter.bound)
	return out
end

-- SQL conditions of a checked modifier filter (on the offers table; the rows through the child table). Every row
-- needed: one EXISTS per row (an index lookup on the primary key offer_id, mod_key); at least `need` of them: the
-- offer ids with that many matching rows (GROUP BY ... HAVING COUNT(*), the (mod_key, value) / (mod_key, tier) indexes)
function C.modClauses(mf, cfg, esc)
	local T = cfg.tables
	local mt, ot = T.offerMods or "chaos_market_offer_mods", T.offers
	local out = {}
	local function cond(m)
		local c = {"`mod_key` = " .. esc(m.key)}
		if m.min > 0 then
			c[#c + 1] = "`value` >= " .. m.min
		end
		if m.tier > 0 then
			c[#c + 1] = "`tier` >= " .. m.tier
		end
		return table.concat(c, " AND ")
	end
	local rows = mf.mods
	if #rows > 0 then
		if mf.need >= #rows then
			for _, m in ipairs(rows) do
				out[#out + 1] = string.format("EXISTS (SELECT 1 FROM `%s` WHERE `%s`.`offer_id` = `%s`.`id` AND %s)", mt, mt, ot, cond(m))
			end
		else
			local any = {}
			for _, m in ipairs(rows) do
				any[#any + 1] = "(" .. cond(m) .. ")"
			end
			out[#out + 1] = string.format("`id` IN (SELECT `offer_id` FROM `%s` WHERE %s GROUP BY `offer_id` HAVING COUNT(*) >= %d)", mt,
				table.concat(any, " OR "), mf.need)
		end
	end
	if mf.sockets > 0 then
		out[#out + 1] = "`sockets` >= " .. mf.sockets
	end
	if mf.quality > 0 then
		out[#out + 1] = "`quality` >= " .. mf.quality
	end
	if mf.freePrefix then
		out[#out + 1] = "`free_prefix` > 0"
	end
	if mf.freeSuffix then
		out[#out + 1] = "`free_suffix` > 0"
	end
	if mf.power then
		out[#out + 1] = "`has_power` = 1"
	end
	if mf.bound then
		out[#out + 1] = "`bound_mods` > 0"
	end
	return out
end

-- ------------------------------------------------------------------ Browse
local SORTS = {
	new = "`id` DESC",
	price = nil, -- by the chosen currency (below)
	price_desc = nil,
	ilvl = "`ilvl` DESC, `id` DESC",
	rarity = "`rarity` DESC, `ilvl` DESC, `id` DESC",
	name = "`name` ASC, `id` DESC",
	ending = "`expires` ASC, `id` ASC"
}

-- text for SQL LIKE: % _ \ escaped (then escaped once more by the database's own escapeString)
function C.likeEscape(s)
	return (tostring(s or ""):gsub("[\\%%_]", "\\%0"))
end

-- filter = {q, cat, rarity, ilvlMin, ilvlMax, cur ("gold" | "coins" | ""), priceMin, priceMax, sort, page, and the
-- modifier filter (C.modFilter): mods = {{k, min, t}, ...}, need, sockets, quality, freeP, freeS, power, bound}
-- esc(text) quotes a string for SQL (db.escapeString); known = {[modifier key] = true} (nil: any well-formed key).
-- Returns where, orderBy, page (1-based), offset; or nil and the refusal when the modifier filter is invalid
-- realm = the viewer's market (C.realmOf), season = the running season id (0 = none): a season character sees its
-- season's offers; everybody else every offer not of the running season (an ended season's offers are standard)
function C.realmClause(realm, season)
	realm, season = int(realm) or 0, int(season) or 0
	if realm > 0 then
		return "`realm` = " .. realm
	end
	if season > 0 then
		return "`realm` <> " .. season
	end
	return "`realm` >= 0"
end

function C.browseQuery(filter, realm, now, cfg, esc, season, known)
	filter = type(filter) == "table" and filter or {}
	local w = {"`state` = 0", C.realmClause(realm, season), "`expires` > " .. (int(now) or 0)}
	local q = tostring(filter.q or ""):gsub("^%s+", ""):gsub("%s+$", "")
	if q ~= "" then
		q = q:sub(1, 40)
		w[#w + 1] = "`name` LIKE " .. esc("%" .. C.likeEscape(q) .. "%")
	end
	local cat = tostring(filter.cat or "")
	for _, c in ipairs(cfg.categories) do
		if c == cat then
			w[#w + 1] = "`category` = " .. esc(cat)
		end
	end
	local rarity = int(filter.rarity)
	if rarity and rarity > 0 and rarity <= 15 then
		-- a stored id of data/lib/chaos_rarity.lua; offers saved before the seven rarities may hold 6 .. 15, which the
		-- comparison still orders right (the login migration and sql/chaos_rarity_migrate.sql make them stored ids)
		w[#w + 1] = "`rarity` >= " .. ChaosRarity.canon(rarity)
	end
	local lo, hi = int(filter.ilvlMin), int(filter.ilvlMax)
	if lo and lo > 0 then
		w[#w + 1] = "`ilvl` >= " .. lo
	end
	if hi and hi > 0 then
		w[#w + 1] = "`ilvl` <= " .. hi
	end
	local cur = filter.cur == "gold" and "gold" or (filter.cur == "coins" and "coins" or nil)
	local col = cur == "coins" and "`price_coins`" or "`price_gold`"
	if cur then
		w[#w + 1] = col .. " > 0"
	end
	local pmin, pmax = int(filter.priceMin), int(filter.priceMax)
	if cur and pmin and pmin > 0 then
		w[#w + 1] = col .. " >= " .. pmin
	end
	if cur and pmax and pmax > 0 then
		w[#w + 1] = col .. " <= " .. pmax
	end
	local mf, why = C.modFilter(filter, cfg, known)
	if not mf then
		return nil, why
	end
	local clauses = C.modClauses(mf, cfg, esc)
	for _, c in ipairs(clauses) do
		w[#w + 1] = c
	end
	local sort = tostring(filter.sort or "new")
	local order = SORTS[sort]
	if sort == "price" or sort == "price_desc" then
		local dir = sort == "price" and "ASC" or "DESC"
		if cur then
			order = col .. " " .. dir .. ", `id` DESC"
		else
			-- no currency chosen: gold offers first by gold, then coin-only offers by coins
			order = "(`price_gold` = 0) ASC, `price_gold` " .. dir .. ", `price_coins` " .. dir .. ", `id` DESC"
		end
	end
	order = order or SORTS.new
	local page = int(filter.page) or 1
	if page < 1 then
		page = 1
	end
	if page > 1000 then
		page = 1000
	end
	return table.concat(w, " AND "), order, page, (page - 1) * cfg.pageSize
end

function C.pages(total, cfg)
	total = int(total) or 0
	if total <= 0 then
		return 1
	end
	return floor((total + cfg.pageSize - 1) / cfg.pageSize)
end

-- one Browse / My Offers row as the client gets it
function C.rowView(r, now)
	return {
		id = r.id, item = r.client_id, count = r.count, name = r.name, rarity = r.rarity, ilvl = r.ilvl,
		unique = (r.unique_item or 0) == 1 or nil, cat = r.category, gold = r.price_gold, coins = r.price_coins,
		seller = r.seller_name, left = math.max(0, (r.expires or 0) - (now or 0)), state = C.STATE_NAME[r.state] or "?",
		buyer = r.buyer_name ~= "" and r.buyer_name or nil, paid = (r.paid_amount or 0) > 0 and r.paid_amount or nil,
		cur = r.paid_currency ~= "" and r.paid_currency or nil, tax = (r.tax or 0) > 0 and r.tax or nil,
		at = r.closed_at ~= 0 and r.closed_at or r.created, order = (r.order_id or 0) > 0 and r.order_id or nil
	}
end

-- ------------------------------------------------------------------ crash safety
-- rows = owed delivery rows of one character (any order), mark = its deliverSeq storage. Rows up to the mark were
-- applied in a state the server saved (the storage is saved in the same transaction as the items and the bank), so
-- they are only marked delivered; the others are applied in id order. Returns applied, toApply (both sorted by id).
function C.deliveryPlan(rows, mark)
	mark = int(mark) or 0
	local sorted = {}
	for _, r in ipairs(rows or {}) do
		sorted[#sorted + 1] = r
	end
	table.sort(sorted, function(a, b) return a.id < b.id end)
	local done, todo = {}, {}
	for _, r in ipairs(sorted) do
		if r.id <= mark then
			done[#done + 1] = r
		else
			todo[#todo + 1] = r
		end
	end
	return done, todo
end

-- a listing that was interrupted between taking the item and activating the offer (state pending): when the seller's
-- saved listSeq reached the offer id the item left the character in a saved state -> activate; else the item is
-- still the character's -> drop the row
function C.pendingAction(offerId, listSeq)
	if (int(listSeq) or 0) >= (int(offerId) or 0) then
		return "activate"
	end
	return "drop"
end

-- ------------------------------------------------------------------ codecs
-- the shared item codec's text forms (item_codec_core.lua; the stash stores items the same way)
if not ChaosItemCodecCore then
	dofile("data/scripts/chaos/item_codec_core.lua")
end
C.hex = ChaosItemCodecCore.hex
C.unhex = ChaosItemCodecCore.unhex
-- the key-list codec (no engine patch 0017): list of {key, value} (value number or string; key "@NAME" = a standard
-- attribute ITEM_ATTRIBUTE_NAME) -> "key=n:123;key=s:<hex>;..." with every key hex encoded
C.encodeAttrs = ChaosItemCodecCore.encodeAttrs
C.decodeAttrs = ChaosItemCodecCore.decodeAttrs

return C
