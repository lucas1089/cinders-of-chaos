-- Store price model (O140): every store offer with what it gives, its value in play time or gold and the coins per hour
-- of benefit, and the rules that keep the prices consistent. Computed from the repository's configs and models, not
-- measured in game. docs/PRICES.md "Store balance (O140)" has the table and the reasons.
--     cd server && luajit tools/store_model.lua [--check]      (also lua5.3)
-- Inputs: shop_coins_config.lua (packs, brlPerUsd), shop_config.lua (offers), pact_config.lua, seasonpass_config.lua,
-- chaos_constants.lua (world buffs), gentledeath_config.lua (blessing gold), xpcap_config.lua, apothecary_config.lua and
-- data/lib/chaos_rune_supply.lua (NPC asks), data/lib/chaos_item_prices.lua (NPC bids), progression_model.lua (levels per
-- hour), loot_model.lua (gold per hour), store_balance_config.lua (the limits --check enforces).
local M = {}

-- engine globals the configs read (constants are numbered on first use, as in tests/shop_test.lua)
local nconst = 0
setmetatable(_G, {__index = function(t, k)
	if type(k) == "string" and k:match("^[A-Z_0-9]+$") then nconst = nconst + 1; rawset(t, k, nconst); return nconst end
end})
PLAYERSEX_FEMALE, PLAYERSEX_MALE = 0, 1
CONST_ME_FIREWORK_YELLOW = 29

function M.load()
	local env = {}
	env.rules = dofile("data/scripts/chaos/store_balance_config.lua")
	env.coins = dofile("data/scripts/chaos/shop_coins_config.lua")
	dofile("data/scripts/chaos/shop_core.lua")
	env.K = ChaosShopCore
	env.shop = dofile("data/scripts/chaos/shop_config.lua")
	env.pact = dofile("data/scripts/chaos/pact_config.lua")
	env.stash = dofile("data/scripts/chaos/stash_config.lua")
	env.season = dofile("data/scripts/chaos/seasonpass_config.lua")
	env.death = dofile("data/scripts/chaos/gentledeath_config.lua")
	env.xpcap = dofile("data/scripts/chaos/xpcap_config.lua")
	env.apo = dofile("data/scripts/chaos/apothecary_config.lua")
	env.runes = dofile("data/lib/chaos_rune_supply.lua")
	env.potions = dofile("data/scripts/chaos/potions_config.lua")
	dofile("data/lib/chaos_item_prices.lua")
	env.prices = ChaosItemPrices
	-- chaos_constants.lua needs the engine; read the two tables the model uses out of its text
	local f = assert(io.open("data/scripts/chaos/chaos_constants.lua", "rb"))
	local text = f:read("*a")
	f:close()
	env.worldBuffs = {}
	local block = text:match("worldBuffs = (%b{})") or ""
	for id, bonus, minutes, cap in block:gmatch('{id = "(%w+)"[^}]-bonus = ([%d%.]+), minutes = (%d+), capMinutes = (%d+)') do
		env.worldBuffs[id] = {bonus = tonumber(bonus), minutes = tonumber(minutes), cap = tonumber(cap)}
	end
	env.resetPerLevel = tonumber(text:match("resetCostPerLevel = (%d+)"))
	-- every offer by key
	env.offers, env.byKey, env.catOf = {}, {}, {}
	for _, cat in ipairs(env.shop.categories) do
		for _, o in ipairs(cat.offers) do
			env.offers[#env.offers + 1] = o
			env.catOf[o] = cat.name
			env.byKey[env.K.offerKey(o)] = o
		end
	end
	for _, p in ipairs(env.pact.store.pact.offers) do env.offers[#env.offers + 1] = p; env.catOf[p] = "Chaos Pact" end
	for _, p in ipairs(env.pact.store.storage.offers) do
		env.offers[#env.offers + 1] = p
		env.catOf[p] = "Storage & Slots"
		env.byKey[p.key] = p
	end
	return env
end

-- ---------------------------------------------------------------- helpers
local function find(env, pred)
	local out = {}
	for _, o in ipairs(env.offers) do
		if pred(o) then out[#out + 1] = o end
	end
	return out
end

-- gold the NPCs ask for one potion or rune, nil when the store item is not a supply
-- an Everfull entry made from another one (potions_config.lua `from`): the ones the store sells as a swap
local function isUpgrade(e)
	return type(e.from) == "table" and #e.from > 0
end

-- what Veyra's task takes for an upgrade: {id, count} (potions_core.lua materialOf)
function M.materialOf(PC, e)
	return {id = e.materialId or e.sourceId, count = e.materialCount or PC.upgrade.materials}
end

function M.askOf(env, id)
	for _, p in ipairs(env.apo.potions) do
		if p.id == id then return p.price end
	end
	for _, r in ipairs(env.runes.runes or {}) do
		if r.id == id then return r.price end
	end
	return nil
end

-- coins per real of a pack by Pix
function M.pixCents(env, pack)
	return pack.usdCents * env.coins.payments.brlPerUsd
end

function M.packCoins(pack)
	return pack.coins + math.floor(pack.coins * (pack.bonusPct or 0) / 100) + (pack.bonusCoins or 0)
end

function M.packRate(env, pack)
	return M.packCoins(pack) / (M.pixCents(env, pack) / 100)
end

-- gold the one-blessing price asks at a level (gentledeath_config.lua bless)
function M.blessGold(env, level)
	local b = env.death.bless
	if level <= b.fromLevel then return b.baseCost end
	local g
	if level <= b.lateFrom then
		g = b.baseCost + (level - b.fromLevel) * b.perLevel
		return math.min(g, b.midCap)
	end
	g = b.midCap + (level - b.lateFrom) * b.latePerLevel
	return math.min(g, b.maxEach)
end

-- the value of a bundle's parts at list price, from the store's own offers
function M.partsValue(env, o)
	local sum = 0
	for _, p in ipairs(o.parts or {}) do
		local c
		if type(p) == "string" then
			c = env.byKey[p] and env.byKey[p].cost
		else
			c = p.cost
		end
		if not c then return nil end
		sum = sum + c
	end
	return sum
end

-- ---------------------------------------------------------------- problems (--check)
function M.problems(env)
	local R, out = env.rules, {}
	local function bad(fmt, ...) out[#out + 1] = string.format(fmt, ...) end

	-- coin packs
	local pk = R.packs
	local base, prev, prevBonus = nil, nil, -1
	local bru = env.coins.payments.brlPerUsd
	for _, p in ipairs(env.coins.packs) do
		if p.usdCents % 100 ~= pk.usdCentsEnding then bad("pack %s: USD price does not end in .%d (%d)", p.key, pk.usdCentsEnding, p.usdCents) end
		if M.pixCents(env, p) % 100 ~= pk.pixCentsEnding then bad("pack %s: Pix price is not round (R$ x%d,%d): %d cents", p.key, 9, pk.pixCentsEnding, M.pixCents(env, p)) end
		local rate = M.packRate(env, p)
		if p.starter then
			if rate > pk.coinsPerReal * pk.starterMaxMult then bad("starter pack gives %.1f coins per real (> %.1fx the base rate)", rate, pk.starterMaxMult) end
		else
			if (p.bonusPct or 0) > pk.maxBonusPct then bad("pack %s: bonus %d%% > %d%%", p.key, p.bonusPct, pk.maxBonusPct) end
			if (p.bonusPct or 0) < prevBonus then bad("pack %s: bonus falls with size", p.key) end
			prevBonus = p.bonusPct or 0
			if (p.bonusPct or 0) == 0 then
				if rate < pk.coinsPerReal * (1 - pk.baseTolerancePct / 100) or rate > pk.coinsPerReal * (1 + pk.baseTolerancePct / 100) then
					bad("pack %s: %.2f coins per real, base rate is %d +-%.1f%%", p.key, rate, pk.coinsPerReal, pk.baseTolerancePct)
				end
			end
			if prev and rate + 1e-9 < prev * (1 - pk.baseTolerancePct / 100) then bad("pack %s: fewer coins per real than the smaller pack", p.key) end
			prev = rate
			if rate > pk.coinsPerReal * pk.maxBulkMult then bad("pack %s: %.2f coins per real is above %.2fx the base rate", p.key, rate, pk.maxBulkMult) end
			local fp = env.coins.firstPurchase
			local extra = math.min(math.floor(M.packCoins(p) * fp.bonusPct / 100), fp.maxBonus)
			local frate = (M.packCoins(p) + extra) / (M.pixCents(env, p) / 100)
			if frate > pk.coinsPerReal * pk.firstMaxMult then bad("pack %s: with the first donation bonus %.1f coins per real (> %.2fx)", p.key, frate, pk.firstMaxMult) end
		end
	end
	if bru ~= 5 then bad("brlPerUsd is %s, the .98 USD ladder assumes 5", tostring(bru)) end

	-- supplies: gold value per coin
	local sp = R.supplies
	local lastBy = {}
	for _, o in ipairs(env.offers) do
		if o.kind == "item" and o.count then
			local ask = M.askOf(env, o.id)
			if ask then
				local gpc = ask * o.count / o.cost
				if gpc < sp.minGoldPerCoin or gpc > sp.maxGoldPerCoin then
					bad("%s: %.0f gold per coin (limits %d-%d)", o.name, gpc, sp.minGoldPerCoin, sp.maxGoldPerCoin)
				end
			end
		end
	end
	-- no store item may sell to an NPC for more than half the gold a coin is worth (buy >= 2x sell, coin -> gold loop)
	for _, o in ipairs(env.offers) do
		if o.kind == "item" and o.id and o.cost > 0 then
			local sell = env.prices.basePrice(o.id) or 0
			if sell * (o.count or 1) / o.cost > R.maxSellGoldPerCoin then
				bad("%s: NPC bid %.0f gold per coin", o.name or tostring(o.id), sell * (o.count or 1) / o.cost)
			end
		end
	end

	-- boosts
	local bo = R.boosts
	local hours, seen = 0, 0
	for _, o in ipairs(env.offers) do
		if o.kind == "item" and o.id == bo.xpPotion.itemId then
			seen = seen + 1
			if not o.weeklyLimit then
				bad("%s has no weekly limit", o.name)
			else
				hours = hours + o.weeklyLimit * (o.count or 1)
			end
		end
	end
	if seen == 0 then bad("no Double Experience Potion offer found") end
	if hours > bo.xpPotion.maxHoursPerWeek then bad("Double Experience Potions: %d hours of x2 a week (limit %d)", hours, bo.xpPotion.maxHoursPerWeek) end
	local single, pack
	for _, o in ipairs(env.offers) do
		if o.id == bo.xpPotion.itemId then
			if (o.count or 1) == 1 then single = o else pack = o end
		end
	end
	if single and pack then
		local disc = 100 * (1 - pack.cost / pack.count / single.cost)
		if disc > bo.xpPackMaxDiscountPct then bad("5 potions are %.0f%% off the single (limit %d%%)", disc, bo.xpPackMaxDiscountPct) end
	end
	for id, w in pairs(env.worldBuffs) do
		if w.bonus > (bo.worldBuffMaxBonus[id] or 0) then bad("world buff %s: bonus %.2f above %.2f", id, w.bonus, bo.worldBuffMaxBonus[id] or 0) end
		if w.cap > bo.worldBuffMaxCapMinutes then bad("world buff %s: cap %d minutes above %d", id, w.cap, bo.worldBuffMaxCapMinutes) end
	end
	local lo, hi = math.huge, 0
	for _, o in ipairs(env.offers) do
		if o.service == "worldBuff" and (o.buff == "xp" or o.buff == "loot" or o.buff == "skill") then
			lo, hi = math.min(lo, o.cost), math.max(hi, o.cost)
		end
	end
	if hi > lo * (1 + bo.worldBuffMaxSpreadPct / 100) then bad("world buffs xp / loot / skill cost %d to %d coins", lo, hi) end
	if env.xpcap.cap > bo.xpCapMax then bad("xp cap %.1f above %.1f", env.xpcap.cap, bo.xpCapMax) end

	-- services against their gold way
	local sv = R.services
	local reset = find(env, function(o) return o.service == "passiveReset" end)[1]
	if reset then
		local goldWay = env.resetPerLevel * sv.passiveResetMaxLevelAt2x
		if reset.cost * R.goldPerCoin * R.maxCheaperThanGold < goldWay then
			bad("Passive Tree Reset %d coins is more than %dx cheaper than the %d gold reset at level %d", reset.cost, R.maxCheaperThanGold, goldWay, sv.passiveResetMaxLevelAt2x)
		end
	end
	local bless = find(env, function(o) return o.service == "blessings" end)[1]
	local eternal = find(env, function(o) return o.service == "eternalBlessing" end)[1]
	if bless then
		local goldWay = 5 * M.blessGold(env, sv.blessingLevel)
		if bless.cost * R.goldPerCoin * R.maxCheaperThanGold < goldWay then
			bad("All Blessings %d coins is more than %dx cheaper than %d gold at level %d", bless.cost, R.maxCheaperThanGold, goldWay, sv.blessingLevel)
		end
	end
	if bless and eternal then
		local t = eternal.cost / bless.cost
		if t < sv.eternalMinTimes or t > sv.eternalMaxTimes then bad("Eternal Blessing is %.1f All Blessings (limits %d-%d)", t, sv.eternalMinTimes, sv.eternalMaxTimes) end
	end

	-- premium and the Pact
	local prem = find(env, function(o) return o.kind == "premium" end)
	table.sort(prem, function(a, b) return a.days < b.days end)
	if #prem == 3 then
		local d90 = 100 * (1 - prem[2].cost / 3 / prem[1].cost)
		local d180 = 100 * (1 - prem[3].cost / 6 / prem[1].cost)
		if d90 < R.premium.minDiscountPct90 or d90 > R.premium.maxDiscountPct90 then bad("90 days of premium are %.0f%% off", d90) end
		if d180 < d90 or d180 > R.premium.maxDiscountPct180 then bad("180 days of premium are %.0f%% off (90 days %.0f%%)", d180, d90) end
	end
	local pact = find(env, function(o) return o.service == "pact" end)[1]
	for _, o in ipairs(env.shop.categories[1].offers) do
		for _, p in ipairs(o.parts or {}) do
			if type(p) == "table" and p.kind == "pact" and pact then
				local want = pact.cost / 30 * p.days
				if math.abs(p.cost - want) > want * R.pactDayTolerancePct / 100 then
					bad("%s: %d days of the Pact listed at %d, the Pact's own price is %.0f", o.name, p.days, p.cost, want)
				end
			end
		end
	end

	-- bundles
	for _, o in ipairs(env.offers) do
		if o.kind == "bundle" then
			local value = M.partsValue(env, o)
			if value and o.cost then
				local disc = 100 * (1 - o.cost / value)
				if disc > R.bundles.maxStarterDiscountPct then bad("%s: %.0f%% off its parts (limit %d%%)", o.name, disc, R.bundles.maxStarterDiscountPct) end
				if disc < 0 then bad("%s: costs more than its parts", o.name) end
			elseif o.pct and o.pct > R.bundles.maxSetDiscountPct then
				bad("%s: %d%% off (limit %d%%)", o.name, o.pct, R.bundles.maxSetDiscountPct)
			end
		end
	end
	local conv = 0
	for _, o in ipairs(env.offers) do
		if env.catOf[o] == "Convenience" and o.cost and (o.service == "pouch" or o.service == "storeFood" or o.kind == "unlock") then
			conv = conv + o.cost
		end
	end
	if conv > R.perCharacterConvenienceMax then bad("per-character convenience adds up to %d coins (limit %d)", conv, R.perCharacterConvenienceMax) end

	-- Everfull potion tiers (O245, O247): one store offer per upgrade (an entry made from another one: tier 2 and up and the
	-- tier 1 spirit potion) at the config's price, never more than 2x cheaper than the task's gold way, a line costs at most
	-- maxLineCoins, nothing sells to an NPC
	do
		local PC, ev = env.potions, R.everfull
		local lineCoins = {}
		for _, e in ipairs(PC.everfull) do
			if isUpgrade(e) then
				local offers = find(env, function(o) return o.service == "everfullUpgrade" and o.upgrade == e.id end)
				local coins = PC.upgrade.coins[e.tier]
				if #offers ~= 1 then
					bad("%s: %d store offers (want 1)", e.name, #offers)
				else
					local o = offers[1]
					if o.cost ~= coins then bad("%s: the store asks %s coins, potions_config.lua upgrade.coins[%d] is %s", e.name, tostring(o.cost), e.tier, tostring(coins)) end
					if o.kind ~= "service" or env.catOf[o] ~= "Everfull Potions" then bad("%s: not an Everfull Potions service", e.name) end
					local mat = M.materialOf(PC, e)
					local ask = M.askOf(env, mat.id)
					if not ask then
						bad("%s: Veyra has no price for the potion %d her task takes", e.name, mat.id)
					else
						local goldWay = mat.count * ask
						if o.cost * R.goldPerCoin * R.maxCheaperThanGold < goldWay then
							bad("%s: %d coins is more than %dx cheaper than the %d gold of the task", e.name, o.cost, R.maxCheaperThanGold, goldWay)
						end
					end
				end
				if (env.prices.basePrice(e.id) or 0) > 0 then bad("%s: an NPC pays %d gold for it (coin -> gold loop)", e.name, env.prices.basePrice(e.id)) end
				lineCoins[e.line] = (lineCoins[e.line] or 0) + (coins or 0)
			end
		end
		for line, coins in pairs(lineCoins) do
			if coins > ev.maxLineCoins then bad("Everfull %s line costs %d coins in all (limit %d)", line, coins, ev.maxLineCoins) end
		end
		local last = 0
		for t = 1, 4 do
			local c = PC.upgrade.coins[t]
			if not c or c < last then bad("Everfull upgrade coins do not grow with the tier (tier %d)", t) else last = c end
		end
	end

	-- exercise weapons: coins per hunting hour saved (skill_model.lua) between half of Premium's and the Double Experience Potion's
	do
		ChaosSkillModelLib = true
		local SM = dofile("tools/skill_model.lua")
		local senv = SM.load()
		local training = find(env, function(o) return o.kind == "item" and env.catOf[o] == "Training" end)
		local p30 = find(env, function(o) return o.kind == "premium" and o.days == 30 end)[1]
		local xp1 = find(env, function(o) return o.id == R.boosts.xpPotion.itemId and (o.count or 1) == 1 end)[1]
		if p30 and xp1 then
			for _, p in ipairs(SM.exerciseProblems(senv, training, p30.cost / 30, xp1.cost)) do bad("%s", p) end
		end
	end

	-- the stash room (O316): the expansion's price per slot, its pack, the cap, the affinity tabs and the old tabs
	do
		local St = R.stash
		local sl = env.stash.slots
		local one, pack = env.byKey["service:pactExtra:stashSlots"], env.byKey["service:pactExtra:stashSlots:4"]
		local cap = env.pact.limits.stashSlots and env.pact.limits.stashSlots.maxExtra or 0
		if not one then
			bad("stash: no single Stash Slot Expansion offer")
		else
			local perSlot = one.cost / sl.perPack
			if perSlot < St.minCoinsPerSlot or perSlot > St.maxCoinsPerSlot then
				bad("stash: an expansion costs %.2f coins per slot (outside %.1f-%.1f)", perSlot, St.minCoinsPerSlot, St.maxCoinsPerSlot)
			end
			if cap * one.cost > St.maxFullCapCoins then bad("stash: all %d expansions cost %d coins (> %d)", cap, cap * one.cost, St.maxFullCapCoins) end
			if pack then
				local n = pack.amount or 1
				local off = 100 * (1 - pack.cost / (n * one.cost))
				if pack.cost >= n * one.cost then bad("stash: the pack of %d (%d coins) is not cheaper than %d singles", n, pack.cost, n) end
				if off > St.maxPackDiscountPct then bad("stash: the pack of %d is %.0f%% off (> %d%%)", n, off, St.maxPackDiscountPct) end
				if cap % n ~= 0 then bad("stash: the pack of %d does not divide the cap of %d", n, cap) end
			end
			local oldTab = sl.legacyPacksPerTab * one.cost
			if oldTab > St.maxOldTabCoins then bad("stash: an old tab converts to %d coins of expansions (> %d)", oldTab, St.maxOldTabCoins) end
			for _, a2 in ipairs(env.stash.affinities) do
				local offer = a2.extra and env.byKey["service:pactExtra:" .. a2.extra]
				if not offer then
					bad("stash: the %s tab has no store offer", a2.key)
				elseif offer.cost / a2.size > St.maxAffinityCoinsPerEntry + 1e-9 then
					bad("stash: the %s tab costs %.2f coins per entry (> %.1f)", a2.key, offer.cost / a2.size, St.maxAffinityCoinsPerEntry)
				end
			end
		end
		if sl.free ~= 30 or env.stash.generalTabs ~= 1 then bad("stash: the free room must be one tab of 30 (owner, O316)") end
	end

	-- season packs
	for _, pass in pairs(env.season.passes) do
		local last = 0
		for _, pk2 in ipairs(pass.packs or {}) do
			if pk2.price <= last then bad("season pack %s is not dearer than the one before", pk2.key) end
			last = pk2.price
		end
	end

	-- cosmetics
	local cosKinds = {wings = true, aura = true, shader = true, frame = true, mount = true, outfit = true, addons = true}
	local minWings = math.huge
	for _, o in ipairs(env.offers) do
		if o.kind == "wings" then minWings = math.min(minWings, o.cost) end
	end
	for _, o in ipairs(env.offers) do
		if cosKinds[o.kind] or (o.kind == "unlock" and env.catOf[o] ~= "Convenience" and env.catOf[o] ~= "Season Pass") then
			if o.cost < R.cosmetics.min or o.cost > R.cosmetics.max then bad("%s: %d coins outside %d-%d", o.name or o.kind, o.cost, R.cosmetics.min, R.cosmetics.max) end
		end
		if o.kind == "frame" and o.cost > minWings then bad("%s: a static frame (%d) costs more than the cheapest animated wings (%d)", o.name, o.cost, minWings) end
	end
	return out
end

-- ---------------------------------------------------------------- the table
local function real(coins) return string.format("R$ %.2f", coins / 10):gsub("%.", ",") end

function M.report(env)
	local R = env.rules
	local PM
	-- the levels of the table: the loot model's bands (O285: 100 / 300 / 500 / 650, the pool ends at hunting level 657)
	ChaosLootModelLib = true
	local okL, LM = pcall(dofile, "tools/loot_model.lua")
	local bands = okL and LM.BANDS or {100, 300, 500, 650}
	ChaosProgressionLib = true
	local okP, mod = pcall(dofile, "tools/progression_model.lua")
	local levelsPerHour = {}
	if okP then
		PM = mod
		local penv = PM.load()
		local curve = PM.curve(penv, 1500)
		for _, L in ipairs(bands) do levelsPerHour[L] = 60 / curve[L].min end
	end
	local goldPerHour = {}
	if okL then
		local ctx = LM.load()
		for _, b in ipairs(bands) do goldPerHour[b] = LM.band(ctx, b).newGold end
	end
	local function line(...) print(string.format(...)) end

	print("Coin packs (Pix by brlPerUsd " .. env.coins.payments.brlPerUsd .. ")")
	print("| Pack | Coins | Pix | PayPal | Coins per R$ | With the first donation |")
	print("|---|---|---|---|---|---|")
	for _, p in ipairs(env.coins.packs) do
		local fp = env.coins.firstPurchase
		local total = M.packCoins(p)
		local extra = p.starter and 0 or math.min(math.floor(total * fp.bonusPct / 100), fp.maxBonus)
		line("| %s | %d | R$ %s | US$ %.2f | %.2f | %.2f |", p.key, total, string.format("%.2f", M.pixCents(env, p) / 100):gsub("%.", ","),
			p.usdCents / 100, M.packRate(env, p), (total + extra) / (M.pixCents(env, p) / 100))
	end

	print("\nTime and gold value of the offers that give play time (coins per hour of benefit)")
	print("| Offer | Coins | About | Gives | Coins per hour of benefit |")
	print("|---|---|---|---|---|")
	local xp = find(env, function(o) return o.id == R.boosts.xpPotion.itemId end)
	for _, o in ipairs(xp) do
		line("| %s | %d | %s | %d h of x2 experience (+1 h of progress each) | %.0f |", o.name, o.cost, real(o.cost), o.count or 1, o.cost / (o.count or 1))
	end
	local pact = find(env, function(o) return o.service == "pact" end)[1]
	for _, d in ipairs({30, 60, 120}) do
		line("| Chaos Pact, %d played hours a month | %d | %s | +10%% experience = %.0f h of progress, plus the perks | %.0f |", d, pact.cost, real(pact.cost), d * 0.1, pact.cost / (d * 0.1))
	end
	for _, w in ipairs({"xp", "loot", "skill", "hunt"}) do
		local o = find(env, function(x) return x.service == "worldBuff" and x.buff == w end)[1]
		local b = env.worldBuffs[w]
		for _, n in ipairs({10, 30}) do
			line("| World %s, %d players online | %d | %s | +%d%% for 1 h for everybody = %.1f player hours | %.0f |", w, n, o.cost, real(o.cost), 100 * b.bonus, n * b.bonus, o.cost / (n * b.bonus))
		end
	end
	for _, o in ipairs(find(env, function(x) return x.kind == "premium" end)) do
		line("| %s | %d | %s | green stamina x1.5 experience, about 1 h of progress a day | %.0f |", o.name, o.cost, real(o.cost), o.cost / o.days)
	end
	for _, o in ipairs(find(env, function(x) return env.catOf[x] == "Training" end)) do
		local ch = tonumber(o.name:match("%((%d+)%)")) or 0
		local h = ch * 0.75 / 3600
		line("| %s | %d | %s | %.2f h on a dummy (750 ms a charge) | %.0f |", o.name, o.cost, real(o.cost), h, o.cost / h)
	end
	do
		ChaosSkillModelLib = true
		local SM = dofile("tools/skill_model.lua")
		local senv = SM.load()
		local training = find(env, function(o) return o.kind == "item" and env.catOf[o] == "Training" end)
		print("\nExercise weapons in hunting hours saved (skill_model.lua; coins per hunting hour at the reference skills, all classes that use it)")
		print("| Offer | Coins | Dummy hours | Coins per hunting hour, lowest | highest |")
		print("|---|---|---|---|---|")
		for _, r in ipairs(SM.exerciseRows(senv, training)) do
			if r.hi > 0 then line("| %s | %d | %.2f | %.1f | %.1f |", r.offer.name, r.cost, r.hours, r.lo, r.hi) end
		end
	end
	if okP then
		print("\nWhat one hour of x2 experience is worth by level (progression_model.lua)")
		print("| Level | Levels gained in 1 extra hour | Coins per level (potion) | Gold per hour (loot_model.lua) | Potion in hours of gold |")
		print("|---|---|---|---|---|")
		for _, L in ipairs(bands) do
			line("| %d | %.2f | %.0f | %s | %.3f |", L, levelsPerHour[L], 50 / levelsPerHour[L], goldPerHour[L] and string.format("%d", math.floor(goldPerHour[L] + 0.5)) or "-",
				goldPerHour[L] and (50 * R.goldPerCoin / goldPerHour[L]) or 0)
		end
	end

	print("\nSupplies: gold value per coin (NPC ask x count / coins)")
	print("| Pack | Coins | Gold per coin |")
	print("|---|---|---|")
	for _, o in ipairs(env.offers) do
		if o.kind == "item" and o.count and M.askOf(env, o.id) and (o.count == 100 or o.count == 500 or o.count == 25) then
			line("| %s | %d | %.0f |", o.name, o.cost, M.askOf(env, o.id) * o.count / o.cost)
		end
	end

	print("\nEverfull potion tiers: the store's swap against the task's gold way (materials x Veyra's price)")
	print("| Tier | Level | Coins | About | Task gold | Task gold in coins | Coins / task coins |")
	print("|---|---|---|---|---|---|---|")
	for _, e in ipairs(env.potions.everfull) do
		if isUpgrade(e) then
			local coins = env.potions.upgrade.coins[e.tier]
			local mat = M.materialOf(env.potions, e)
			local gold = mat.count * (M.askOf(env, mat.id) or 0)
			line("| %s | %d | %d | %s | %d | %.1f | %.1f |", e.name, e.level, coins, real(coins), gold, gold / R.goldPerCoin, coins / (gold / R.goldPerCoin))
		end
	end

	print("\nServices against the gold way")
	local reset = find(env, function(o) return o.service == "passiveReset" end)[1]
	for _, L in ipairs({100, 500, 800, 1000, 2000}) do
		line("- Passive reset at level %d: %d gold in the window = %.0f coins at %d gold a coin; the store asks %d", L, L * env.resetPerLevel,
			L * env.resetPerLevel / R.goldPerCoin, R.goldPerCoin, reset.cost)
	end
	local bless = find(env, function(o) return o.service == "blessings" end)[1]
	for _, L in ipairs({50, 120, 500, 1000}) do
		line("- All Blessings at level %d: %d gold by !bless = %.0f coins; the store asks %d", L, 5 * M.blessGold(env, L), 5 * M.blessGold(env, L) / R.goldPerCoin, bless.cost)
	end

	print("\nBundles (parts at list price)")
	for _, o in ipairs(env.offers) do
		if o.kind == "bundle" then
			local v = M.partsValue(env, o)
			if v and o.cost then line("- %s: %d coins for parts worth %d (%.0f%% off)", o.name, o.cost, v, 100 * (1 - o.cost / v)) end
		end
	end
	for _, pass in pairs(env.season.passes) do
		for _, p in ipairs(pass.packs or {}) do line("- Season pack %s: %d coins", p.key, p.price) end
		line("- Premium pass: %d coins", pass.premium.price)
	end

	-- the stash room (O316)
	local sl = env.stash.slots
	local one = env.byKey["service:pactExtra:stashSlots"]
	local pk4 = env.byKey["service:pactExtra:stashSlots:4"]
	local cap = env.pact.limits.stashSlots.maxExtra
	print("\nStash room (O316): one free tab of " .. sl.free .. " entries")
	print("| Offer | Coins | About | Gives | Coins per entry |")
	print("|---|---|---|---|---|")
	line("| %s | %d | %s | +%d slots | %.2f |", one.name, one.cost, real(one.cost), sl.perPack, one.cost / sl.perPack)
	line("| %s | %d | %s | +%d slots | %.2f |", pk4.name, pk4.cost, real(pk4.cost), sl.perPack * pk4.amount, pk4.cost / (sl.perPack * pk4.amount))
	line("| All %d expansions (the cap) | %d | %s | %d slots in all | %.2f |", cap, cap * one.cost, real(cap * one.cost), sl.free + cap * sl.perPack,
		cap * one.cost / (cap * sl.perPack))
	for _, a2 in ipairs(env.stash.affinities) do
		local o = env.byKey["service:pactExtra:" .. a2.extra]
		line("| %s | %d | %s | a tab of %d entries for %s | %.2f |", o.name, o.cost, real(o.cost), a2.size, a2.key, o.cost / a2.size)
	end
	line("| An old tab (bought or earned) | - | - | %d expansions = %d slots, outside the cap | - |", sl.legacyPacksPerTab, sl.legacyPacksPerTab * sl.perPack)
end

function M.main(args)
	local env = M.load()
	if args[1] == "--check" then
		local problems = M.problems(env)
		for _, p in ipairs(problems) do print("store model: " .. p) end
		if #problems > 0 then
			return 1
		end
		print(string.format("store model: prices consistent (%d offers, %d packs)", #env.offers, #env.coins.packs))
		return 0
	end
	M.report(env)
	return 0
end

if ChaosStoreModelLib then
	return M
end
os.exit(M.main(arg or {}))
