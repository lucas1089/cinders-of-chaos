-- Auto Seller: pure rules of selling the Loot Bag (no engine calls), shared by autosell.lua and server/tests/autosell_test.lua.
--   ChaosAutoSellCore.COOLDOWN                         seconds between two sales of the bag (owner: "a cada 30s")
--   ChaosAutoSellCore.cooldownLeft(last, now, cd)      seconds still to wait (0 = ready)
--   ChaosAutoSellCore.bagPlan(entries, prices, opts)   what one sale does with the bag's contents
--       entries: {{ref, id, count, container, unique, rarity, locked, attributes, neverSell, price}} (every item in the bag,
--                price = that copy's own price each, ChaosItemPrices.sellPrice(item, 1), when known;
--                nested ones too); prices: id -> NPC gold each (sell_prices.lua); opts.tiers (the player's rarity
--                choice, below), opts.coins (id -> gold each: gold, platinum and crystal coins go to the bank as they are)
--       -> {sell = {{ref, id, count, gold}}, gold, kept = {locked, unique, rarity, custom, noPrice, protected}}
--       storeBound (custom attribute chaos_storebound or a store item: the Everfull Ration, the pouches, Nemesis items)
--       is kept as protected, like orbs, gems and keys
--   ChaosAutoSellCore.opensContents(entry)             false for a container whose contents are never sold: a locked
--                                                      one (the item lock covers what is inside), a store-bound one or a
--                                                      store pouch (entry.pouch). Others are walked (autosell.lua bagEntries)
--   Rarities the Auto Seller sells (owner 2026-10-13: "Deixe o jogador configurar o autosell por raridade"): one choice
--   per tier, per character, in one storage value (Chaos.storage.autosellRarity, 7100103):
--   ChaosAutoSellCore.TIERS                            {{key, name, rank, bit}}: Common, Uncommon, Magic, Rare, Legendary, Divine
--                                                      (data/lib/chaos_rarity.lua; before 2026-10-18 the last was Legendary+, every
--                                                      rarity from 5 up; a choice saved then ticked Divine with it)
--   ChaosAutoSellCore.DEFAULT_TIERS                    Common and Uncommon on; Magic, Rare, Legendary, Divine off
--   ChaosAutoSellCore.unpackTiers(v) / packTiers(t)    storage value <-> {key = bool}; unset = the defaults; the old
--                                                      "!autosell rarity on" value 1 = every tier on, 0 = the defaults
--   ChaosAutoSellCore.tierOf(rarity)                   the tier key of a rarity (any of the 15 old ids too; nil for 0)
--   ChaosAutoSellCore.sells(tiers, rarity)             true when a rarity item may be sold (rarity 0: true)
--   ChaosAutoSellCore.rarityChange(tiers, data)        validates a client change {tier = key, on = bool} or {tiers =
--                                                      {key = bool}} -> new tiers, or nil and the reason
--   Uniques are never sold, whatever the choice. An item with a custom name, description or text and no rarity is kept.
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.
ChaosAutoSellCore = ChaosAutoSellCore or {}
local K = ChaosAutoSellCore

K.COOLDOWN = 30
-- "sell every X minutes" (owner 2026-10-17): the choices of the window's dropdown; off (0) by default
K.INTERVALS = {5, 10, 15, 30, 60}
K.TICK = 30 -- seconds between two looks at the (small) list of characters that have it on
K.MAX_PER_TICK = 10 -- sales one tick makes at most; the rest are still due at the next one

-- a stored or requested number of minutes -> minutes (0 = off), or nil when it is not one of the choices
function K.intervalOf(v)
	local n = tonumber(v)
	if n == nil or n ~= n then
		return nil
	end
	if n == 0 then
		return 0
	end
	for _, m in ipairs(K.INTERVALS) do
		if n == m then
			return m
		end
	end
	return nil
end

-- the stored value (unset -1 / garbage reads as off)
function K.storedInterval(v)
	return K.intervalOf(v) or 0
end

-- seconds until `nextAt` (0 = due)
function K.dueIn(nextAt, now)
	if not nextAt then
		return 0
	end
	return math.max(0, nextAt - now)
end
K.COINS = {[2148] = 1, [2152] = 100, [2160] = 10000}

if not ChaosRarity then
	dofile("data/lib/chaos_rarity.lua")
end

-- one choice per rarity (data/lib/chaos_rarity.lua rank); the bits of the first five are the ones the choices had since
-- 2026-10-13 (Common, Uncommon, Rare = today's Magic, Epic = today's Rare, Legendary+ = today's Legendary), so a saved
-- choice keeps its meaning; Divine (32) is new. A choice saved before it (no LEGACY_END bit) sold Divine with Legendary.
K.TIERS = {
	{key = "common", name = "Common", rank = 1, bit = 1},
	{key = "uncommon", name = "Uncommon", rank = 2, bit = 2},
	{key = "magic", name = "Magic", rank = 3, bit = 4},
	{key = "rare", name = "Rare", rank = 4, bit = 8},
	{key = "legendary", name = "Legendary", rank = 5, bit = 16},
	{key = "divine", name = "Divine", rank = 6, bit = 32}
}
K.DEFAULT_TIERS = {common = true, uncommon = true, magic = false, rare = false, legendary = false, divine = false}
local TIER_MARK = 64 -- a stored choice always has it (0 = every tier off is a valid choice)
local VERSION_MARK = 128 -- a choice saved since the seven rarities has it; one without it ticked Divine with Legendary+

local function copyTiers(t)
	local out = {}
	for _, tier in ipairs(K.TIERS) do
		out[tier.key] = t[tier.key] == true
	end
	return out
end

function K.unpackTiers(v)
	v = tonumber(v) or -1
	if v == 1 then
		local all = {}
		for _, tier in ipairs(K.TIERS) do
			all[tier.key] = true -- the old "!autosell rarity on": every rarity was sold
		end
		return all
	end
	if v < TIER_MARK then
		return copyTiers(K.DEFAULT_TIERS)
	end
	local out = {}
	for _, tier in ipairs(K.TIERS) do
		out[tier.key] = math.floor(v / tier.bit) % 2 == 1
	end
	if v < VERSION_MARK then
		out.divine = out.legendary -- "Legendary+" of before covered every rarity above Legendary
	end
	return out
end

function K.packTiers(t)
	local v = TIER_MARK + VERSION_MARK
	for _, tier in ipairs(K.TIERS) do
		if type(t) == "table" and t[tier.key] == true then
			v = v + tier.bit
		end
	end
	return v
end

-- the tier key of a rarity (any of the 15 old ids counts as the rarity it became); nil for none
function K.tierOf(rarity)
	local rank = ChaosRarity.rank(rarity)
	for _, tier in ipairs(K.TIERS) do
		if rank == tier.rank then
			return tier.key
		end
	end
	return nil
end

function K.sells(tiers, rarity)
	if (tonumber(rarity) or 0) <= 0 then
		return true
	end
	local key = K.tierOf(rarity)
	return key ~= nil and type(tiers) == "table" and tiers[key] == true
end

local TIER_KEY = {}
for _, tier in ipairs(K.TIERS) do
	TIER_KEY[tier.key] = tier
end

function K.rarityChange(tiers, data)
	if type(data) ~= "table" then
		return nil, "bad request"
	end
	local out = copyTiers(type(tiers) == "table" and tiers or K.DEFAULT_TIERS)
	if type(data.tiers) == "table" then
		for k, on in pairs(data.tiers) do
			if not TIER_KEY[k] or type(on) ~= "boolean" then
				return nil, "unknown rarity"
			end
			out[k] = on
		end
		return out
	end
	local key = type(data.tier) == "string" and data.tier:lower() or nil
	if not key or not TIER_KEY[key] then
		for _, tier in ipairs(K.TIERS) do
			if key and tier.name:lower():gsub("%+", "") == key:gsub("%+", "") then
				key = tier.key
			end
		end
	end
	if not key or not TIER_KEY[key] then
		return nil, "unknown rarity"
	end
	if type(data.on) ~= "boolean" then
		return nil, "on must be true or false"
	end
	out[key] = data.on
	return out
end

-- the window's list of tiers: {{key, name, on}}
function K.tierList(tiers)
	local out = {}
	for i, tier in ipairs(K.TIERS) do
		out[i] = {key = tier.key, name = tier.name, on = type(tiers) == "table" and tiers[tier.key] == true or false}
	end
	return out
end

function K.cooldownLeft(last, now, cd)
	if not last then
		return 0
	end
	return math.max(0, (last + (cd or K.COOLDOWN)) - now)
end

function K.bagPlan(entries, prices, opts)
	opts = opts or {}
	local coins = opts.coins or K.COINS
	local tiers = opts.tiers or K.DEFAULT_TIERS
	local out = {sell = {}, gold = 0, kept = {locked = 0, unique = 0, rarity = 0, custom = 0, noPrice = 0, protected = 0}}
	for _, e in ipairs(entries or {}) do
		local count = math.max(1, math.floor(tonumber(e.count) or 1))
		if e.container then
			-- a container is never sold: its contents are (they are entries of their own)
		elseif e.locked then
			out.kept.locked = out.kept.locked + 1 -- the item lock: never sold
		elseif e.neverSell or e.storeBound then
			out.kept.protected = out.kept.protected + 1 -- orbs, gems, keys (what the other pouches collect)
		elseif coins[e.id] then
			local gold = coins[e.id] * count
			out.sell[#out.sell + 1] = {ref = e.ref, id = e.id, count = count, gold = gold, coin = true}
			out.gold = out.gold + gold
		elseif e.unique then
			out.kept.unique = out.kept.unique + 1 -- uniques are never sold
		elseif (tonumber(e.rarity) or 0) > 0 and not K.sells(tiers, e.rarity) then
			out.kept.rarity = out.kept.rarity + 1 -- a rarity the player keeps (the Auto Seller window's checkboxes)
		elseif (tonumber(e.rarity) or 0) <= 0 and e.attributes then
			out.kept.custom = out.kept.custom + 1 -- a custom name, description or text: never sold
		else
			local each = tonumber(e.price or (prices and prices[e.id])) or 0 -- e.price: the copy's own (ChaosItemPrices)
			if each > 0 then
				local gold = each * count
				out.sell[#out.sell + 1] = {ref = e.ref, id = e.id, count = count, gold = gold}
				out.gold = out.gold + gold
			else
				out.kept.noPrice = out.kept.noPrice + 1 -- no NPC buys it
			end
		end
	end
	return out
end

function K.opensContents(e)
	return type(e) == "table" and e.container == true and not e.locked and not e.storeBound and not e.pouch
end

-- the chat line of a sale, in `lang` (Chaos.t keys, i18n_strings.lua; English without ChaosI18n)
function K.saleText(plan, lang)
	local function T(key, ...)
		if ChaosI18n then
			return ChaosI18n.text(lang, key, ...)
		end
		return string.format(key, ...)
	end
	local n = 0
	for _, s in ipairs(plan.sell) do
		if not s.coin then
			n = n + s.count
		end
	end
	local k = plan.kept
	local keptN = k.locked + k.unique + k.rarity + (k.custom or 0) + k.noPrice + k.protected
	local parts = {}
	for _, x in ipairs({{"locked", k.locked}, {"unique", k.unique}, {"rarity", k.rarity}, {"named", k.custom or 0},
			{"no NPC buys", k.noPrice}, {"orbs / gems / keys", k.protected}}) do
		if x[2] > 0 then
			parts[#parts + 1] = T("%s %d", T(x[1]), x[2])
		end
	end
	return T("Auto Seller: sold %d item%s from your Loot Bag for %d gold (to your bank).%s", n, n == 1 and "" or "s",
		plan.gold, keptN > 0 and T(" Kept %d: %s.", keptN, table.concat(parts, ", ")) or "")
end
