-- The loot-by-monster-level model (server/README.md "Loot by monster level"): gold and items per hour of each hunting
-- band under the corpse rule of 2026-10-20 (every item x loot, coins and NPC-sellable items x loot x gold on top) and
-- under the rule by monster level (pace_core.lua P.levelPlan), at the pack model's kills per hour.
--
--     cd server && luajit tools/loot_model.lua            the table (also lua5.3)
--     cd server && luajit tools/loot_model.lua --derive   the coins / junkKeep (constant per band) that hold `lootLevel` targets
--     cd server && luajit tools/loot_model.lua --check    exit 1 when a band leaves the tolerances (CI)
--
-- Inputs, all in the repository: tools/loot_bands_data.lua (the stock loot tables of the bands' monsters, written by
-- tools/loot_bands.py from an installed base server), pace_config.lua (curves, `lootLevel`), tools/spawn_tuning.json
-- `model.paceKillsPerHour` (one hunter's kills per hour by the monster's level, the pack-cycle model), data/lib/
-- chaos_rarity.lua (the stock rarity roll: the Rare+ share of gear drops), gamble_config.lua `balance.hunting` (the
-- "Respec" gold per hour, printed as the reference). Expected values, no random numbers: per loot entry the chance,
-- the stock count (uniform 1..max, x the stock level count multiplier of a level-scaled monster) and the rule's
-- shares. Gold is coins plus the plain NPC price of every item (the "Respec" model's measure; rarity and item level
-- are left out). Items are the non-coin corpse entries (a stack is one). Orbs, gems, keys (class other) and plain gear
-- keep the loot factor under both rules, so their per hour does not change.
--
-- O751 (owner 2026-11-24 "Acertar o ouro"): the gold per hour of a hunt by level, the one curve every price in hours of
-- hunting reads (data/scripts/chaos/hunt_gold_config.lua `hunting`), is this model's SALE gold: the corpse gold above with
-- the gear at what an NPC pays for the copy that drops (x the expected rarity multiplier of its branch, x 1 + item
-- level / 200 at the monster's level, data/lib/chaos_item_prices.lua) plus the Chaos extra rolls (loot_config.lua
-- extraRolls x monster_tiers.lua spawnChance x the monster's loot factor, not thinned). The late bands 800-2500 read
-- tools/loot_bands_late_data.lua (our own level-scaled monsters, tools/loot_bands.py --late) and the hunts of the
-- progression window (0.8-1.1 x the band). --check also holds hunt_gold_config.lua to the model (M.TOL.curve).
--     cd server && luajit tools/loot_model.lua --income     the sale gold per hour by band and the curve it gives
--
-- A test can load it as a library: ChaosLootModelLib = true; local M = dofile("tools/loot_model.lua").

if not ChaosPaceCore or not ChaosPaceCore.levelPlan then
	dofile("data/scripts/chaos/pace_core.lua")
end
local P = ChaosPaceCore

local M = {}
-- O285: the hunting level of a base monster is its pool level (baseLevelMult 1), the pool has none above 657, so the bands
-- stop at 650 (they were 800, 1000 and 1500 with the level twice the pool's); a band hunts +-15% of its level
M.BANDS = {100, 300, 500, 650}
M.RANGES = {[100] = {85, 115}, [300] = {255, 345}, [500] = {425, 575}, [650] = {552, 748}}
-- the rule of 2026-10-20 (pace_config.lua `gold`, linear), the reference the new curves keep
M.OLD_GOLD = {base = {{250, 1.0}, {450, 0.30}, {1000, 0.30}}, scaled = {{100, 1.0}, {450, 0.30}, {2000, 0.30}}}
-- tolerances of --check: gold per hour and items per hour of the new rule against the old, per band
M.TOL = {gold = 0.05, items = 0.07, rare = 0.05}
-- O285: the notable rule from before the monsters stood at their pool level (hunting level = 2 x pool level, base `loot`
-- points of that day, `notable` {{650, 0}, {700, 1}}, scale.loot on the loot points): the Rare+ gear per hour of a band
-- under it is the figure the curves of pace_config.lua must keep (`rarePerHour`, tolerance M.TOL.rare)
M.OLD_RULE = {mult = 2,
	loot = {{20, 1.00}, {35, 0.59}, {60, 0.54}, {100, 0.37}, {175, 0.27}, {250, 0.20}, {450, 0.20}, {600, 0.19},
		{800, 0.19}, {1000, 0.20}},
	notable = {{650, 0}, {700, 1}}}

-- the notable share of a base monster of pool level `level` under the rule of before
function M.oldNotable(cfg, level)
	local r = M.OLD_RULE
	local hl = level * r.mult
	local loot = math.min(1, P.lin(r.loot, hl, 1) * (tonumber((cfg.scale or {}).loot) or 1))
	return math.max(loot, P.smooth(r.notable, hl, loot))
end
-- O141 (2026-10-23): the gold per hour must grow with the level (no dip; O285: the gold without the notable drops) and by at most this factor from one checked
-- band to the next one up to 150 levels higher, from level 300 on (before: 469k at 300, 325-537k at 400-600, 1.8M at
-- 650, 2.5M at 800). The bands 350, 400 and 600 are checked on top of the table's and of `--derive`'s.
M.MAX_STEP = 2.3
M.SMOOTH_FROM = 300
M.SMOOTH_SPAN = 150
M.SMOOTH_BANDS = {350, 400, 600}
M.WIDOWS = {"Nightfang Widow", "Shadowcrystal Widow"}

local function readFile(path)
	local f = assert(io.open(path, "r"))
	local s = f:read("*a")
	f:close()
	return s
end

-- spawn_tuning.json model.paceKillsPerHour {base = {{level, kills}}, scaled = ...}
function M.killsTable(text)
	text = text or readFile("tools/spawn_tuning.json")
	local block = text:match('"paceKillsPerHour"%s*:%s*(%b{})')
	local out = {}
	for _, k in ipairs({"base", "scaled"}) do
		local arr = block:match('"' .. k .. '"%s*:%s*(%b[])')
		local pts = {}
		for a, b in arr:gmatch("%[%s*([%d%.]+)%s*,%s*([%d%.]+)%s*%]") do
			pts[#pts + 1] = {tonumber(a), tonumber(b)}
		end
		out[k] = pts
	end
	return out
end

-- the share of stock gear drops with a rarity of Rare or better (stored id >= notableRarity)
function M.rarePlusShare(R, notableRarity)
	R = R or dofile("data/lib/chaos_rarity.lua")
	local reach = (tonumber(R.stockRollChance) or 70) / 100
	local left, share = 1, 0
	for _, e in ipairs(R.stockRolls) do
		local hit = left * e.chance / 100
		if e.id >= (notableRarity or 4) then
			share = share + hit
		end
		left = left - hit
	end
	return reach * share
end

-- the stock pass's count multiplier (default_onDropLoot.lua) for a monster's own level (0 for a base monster)
function M.countMult(level)
	level = tonumber(level) or 0
	if level >= 501 then return 2.70 elseif level >= 301 then return 2.25 elseif level >= 201 then return 1.95
	elseif level >= 101 then return 1.65 elseif level >= 51 then return 1.35 elseif level >= 5 then return 1.15 end
	return 1
end

-- the stock counts of an entry: list of {count, probability}
local function counts(e, mult)
	local cmax = e[3]
	local stack = cmax > 1 or e[4] == "coin"
	if not stack then
		return {{1, 1}}, false
	end
	local out = {}
	for n = 1, cmax do
		out[#out + 1] = {math.max(1, math.floor(n * mult)), 1 / cmax}
	end
	return out, true
end

-- expected per kill of one monster: gold, items (non-coin entries), coins entry present, P(empty corpse)
-- rule = {kind = "old", f =, g =} or {kind = "new", f = factors, ll = lootLevel, rare = Rare+ share}
function M.perKill(mon, rule)
	local mult = mon.scaled and M.countMult(mon.level) or 1
	local gold, items, pNoCoin, pEmpty = 0, 0, 1, 1
	local ngold = 0
	-- O751: the gear gold of the corpse at plain price, notable branch (Rare+) and plain branch; the whole stock loot
	-- before any thinning (coins and junk, gear at plain price) for the extra rolls
	local gearN, gearP, gearC, stockGold, stockGear = 0, 0, 0, 0, 0 -- the part of `gold` that is Rare+ gear and rare drops at their notable share (new rule)
	local f = rule.f
	local loot = f.loot
	-- new rule: P(no coin dropped), P(no non-coin non-junk entry shows), the junk entries
	local newC, newN, junk = 1, 1, {}
	for _, e in ipairs(mon.loot) do
		local p = e[2] / 100000
		local cls, price = e[4], e[5]
		local cs, stack = counts(e, mult)
		local mean = 0
		for _, c in ipairs(cs) do
			mean = mean + c[1] * c[2]
		end
		local keepEntry -- P(the entry shows in the corpse | it dropped)
		if cls == "gear" then
			stockGear = stockGear + p * price
		elseif cls == "coin" or cls == "junk" then
			stockGold = stockGold + p * mean * price
		end
		if rule.kind == "old" then
			local s = (cls == "coin" or cls == "junk") and loot * rule.g or loot
			s = math.min(1, s)
			gold = gold + p * mean * price * s
			if stack then
				keepEntry = 0
				for _, c in ipairs(cs) do
					keepEntry = keepEntry + c[2] * math.min(1, c[1] * s)
				end
			else
				keepEntry = s
			end
			if cls == "coin" then
				pNoCoin = pNoCoin * (1 - p * keepEntry)
			else
				items = items + p * keepEntry
			end
			pEmpty = pEmpty * (1 - p * keepEntry)
		else
			local sv = math.min(1, loot * f.coins)
			local skStack = f.junkKeep and math.min(1, loot * f.junkKeep) or 1
			local notableByChance = cls ~= "coin" and e[2] <= (rule.ll.notableChance or 1000)
			local show -- P(a non-coin entry shows | it dropped)
			if cls == "coin" then
				gold = gold + p * mean * price * sv
				-- coins that dropped come back as coins (a value of at least 1 gold)
				newC = newC * (1 - p)
			elseif notableByChance then
				gold = gold + p * mean * price * f.notable
				ngold = ngold + p * mean * price * f.notable
				if cls == "gear" then
					gearC = gearC + p * mean * price * f.notable
				end
				show = f.notable
			elseif cls == "junk" and f.cheap and f.cheap > 0 and price <= f.cheap then
				-- O285: cheap junk stays whole (P.levelPlan `cheap`)
				gold = gold + p * mean * price
				show = 1
			elseif cls == "junk" then
				gold = gold + p * mean * price * sv
				local sk = stack and skStack or math.min(sv, skStack)
				show = sk
				if sv >= 1 then
					show = 1
				elseif stack and sk > sv then
					show = 0
					for _, c in ipairs(cs) do
						show = show + c[2] * sk * math.min(1, c[1] * sv / sk)
					end
				end
				-- taken out, it pays coins when sk < sv; else it is gone without a trace (unless the floor pays)
				local paid = (sv < 1 and sk < sv) and (1 - sk) or 0
				junk[#junk + 1] = {p = p, show = show, paid = paid, silent = math.max(0, 1 - show - paid),
					value = mean * price * sv}
				items = items + p * show
				show = nil
			elseif cls == "gear" then
				show = rule.rare * f.notable + (1 - rule.rare) * loot
				gold = gold + p * price * show
				ngold = ngold + p * price * rule.rare * f.notable
				gearN = gearN + p * price * rule.rare * f.notable
				gearP = gearP + p * price * (1 - rule.rare) * loot
			else -- other: P.thinPlan with loot
				show = 0
				if stack then
					for _, c in ipairs(cs) do
						show = show + c[2] * math.min(1, c[1] * loot)
					end
				else
					show = math.min(1, loot)
				end
			end
			if show then
				items = items + p * show
				newN = newN * (1 - p * show)
			end
		end
	end
	if rule.kind == "old" then
		return {gold = gold, items = items, coins = 1 - pNoCoin, empty = pEmpty}
	end
	-- the floor (P.levelPlan): no coin dropped, nothing else shows, no junk shows or paid, at least one junk silently
	-- removed: its value x sv comes as coins (the expected value uses each entry's mean count)
	local allQuiet, noneDropped, noPaid = 1, 1, 1
	for _, j in ipairs(junk) do
		allQuiet = allQuiet * (1 - j.p * (1 - j.silent))
		noneDropped = noneDropped * (1 - j.p)
		noPaid = noPaid * (1 - j.p * j.paid)
	end
	local floorGold = 0
	for i, j in ipairs(junk) do
		local others = 1
		for k, o in ipairs(junk) do
			if k ~= i then
				others = others * (1 - o.p * (1 - o.silent))
			end
		end
		floorGold = floorGold + j.p * j.silent * j.value * others
	end
	gold = gold + newC * newN * floorGold
	local pFloor = newC * newN * (allQuiet - noneDropped)
	return {gold = gold, items = items, coins = 1 - (newC * noPaid - pFloor), empty = newC * newN * noneDropped,
		notableGold = ngold, gearN = gearN, gearP = gearP, gearC = gearC, stockGold = stockGold, stockGear = stockGear}
end

function M.load(opts)
	opts = opts or {}
	local cfg = opts.cfg or dofile("data/scripts/chaos/pace_config.lua")
	local data = opts.data or dofile("tools/loot_bands_data.lua")
	local kills = opts.kills or M.killsTable()
	local ll = cfg.lootLevel or {}
	local late = opts.late or dofile("tools/loot_bands_late_data.lua")
	return {cfg = cfg, data = data, late = late, kills = kills, ll = ll, rare = M.rarePlusShare(nil, ll.notableRarity),
		sale = opts.sale or M.saleFactors(nil, ll.notableRarity), extra = opts.extra or M.extraRolls()}
end

-- O751: the late bands (our own level-scaled monsters, tools/loot_bands_late_data.lua) and the hunts they take: the
-- progression model's window (progression_config.lua window 0.8-1.1 x the level), the base pool ends at 657
M.LATE_BANDS = {800, 1000, 1300, 1600, 2000, 2500}
M.LATE_WINDOW = {0.8, 1.1}
M.LATE_FROM = 658
-- the bands of the one gold curve (hunt_gold_config.lua): the base bands and the late ones; 40 is the lowest level the
-- base data holds (every base monster from level 40)
M.CURVE_BANDS = {40, 100, 300, 500, 650, 800, 1000, 1300, 1600, 2000, 2500}
M.RANGES[40] = {34, 46}
-- --check: every point of hunt_gold_config.lua `hunting` within this share of the model's sale gold at its band
M.TOL.curve = 0.05
-- a point may stay at the point before it where the model dips (the curve never falls: a price or a prize in hours of
-- hunting never gets cheaper with the level), at most this far above the model
M.TOL.flat = 0.10
-- the rarity multiplier the Rare+ pieces of the stock roll are counted at in the sale gold (1: their plain price)
M.RARE_KEPT = 1

-- the expected NPC price multiplier of a gear drop by branch (data/lib/chaos_item_prices.lua: rarity x item level):
-- {notable = Rare or better, plain = no rarity / Common / Uncommon / Magic, all = every drop}, from the stock roll
-- (chaos_rarity.lua stockRolls) and the price table's rarityMult (by place)
function M.saleFactors(R, notableRarity)
	R = R or dofile("data/lib/chaos_rarity.lua")
	local data = dofile("data/lib/chaos_item_prices_data.lua")
	local reach = (tonumber(R.stockRollChance) or 70) / 100
	local left, rows = 1, {}
	for i, e in ipairs(R.stockRolls) do
		local hit = left * e.chance / 100
		rows[#rows + 1] = {id = e.id, p = reach * hit, mult = data.rarityMult[i] or 1}
		left = left - hit
	end
	local nP, nV, pP, pV = 0, 0, 0, 0
	for _, r in ipairs(rows) do
		if r.id >= (notableRarity or 4) then
			nP, nV = nP + r.p, nV + r.p * r.mult
		else
			pP, pV = pP + r.p, pV + r.p * r.mult
		end
	end
	local none = 1 - nP - pP
	return {notable = nV / nP, plain = (none + pV) / (none + pP), all = none + pV + nV, ilvlDiv = data.ilvlDiv or 200}
end

-- the item level of a drop of a monster of level `level` (chaos_item_mods.lua itemLevel.curve, at most max)
function M.itemLevel(level)
	if not M._ilvl then
		local text = readFile("data/lib/chaos_item_mods.lua")
		local body = text:match("itemLevel%s*=%s*{.-curve%s*=%s*(%b{})")
		local pts = {}
		for a, b in body:gmatch("{%s*(%d+)%s*,%s*(%d+)%s*}") do
			pts[#pts + 1] = {tonumber(a), tonumber(b)}
		end
		M._ilvl = {pts = pts, max = tonumber(text:match("itemLevel%s*=%s*{%s*max%s*=%s*(%d+)")) or 150}
	end
	return math.min(M._ilvl.max, P.lin(M._ilvl.pts, level, 1))
end

-- the expected extra rolls of a kill (loot_config.lua extraRolls x extraChanceMult x monster_tiers.lua spawnChance): the
-- share of the monster's stock loot that comes again (x its loot factor, loot.lua L.rollExtraLoot), and their count mult
function M.extraRolls()
	local lc = dofile("data/scripts/chaos/loot_config.lua")
	local text = readFile("data/scripts/chaos/monster_tiers.lua")
	local body = text:match("spawnChance%s*=%s*(%b{})")
	local out = 0
	for _, t in ipairs({"magic", "rare", "legendary"}) do
		local c = tonumber(body:match(t .. "%s*=%s*(%d+)")) or 0
		out = out + c / 10000 * (lc.extraRolls[t] or 0) * (lc.extraChanceMult[t] or 1) * (lc.extraCountMult[t] or 1)
	end
	return out
end

-- the sale gold of one kill (O751): the corpse gold with its gear at the copy's NPC price, plus the extra rolls
function M.saleKill(ctx, mon, k)
	local lm = 1 + M.itemLevel(mon.level) / ctx.sale.ilvlDiv
	-- gear: the plain branch and gear of a rare loot entry (chance at most 1%: any rarity) at the copy's NPC price; the
	-- Rare+ pieces of the stock roll at their plain price x the item level (M.RARE_KEPT): they are the pieces a hunter
	-- equips, salvages or sells on the market, not to an NPC at x6-24 (--income prints what that would add)
	local plain = k.gold - k.gearN - k.gearP - (k.gearC or 0)
	local kept = ctx.rareKept or M.RARE_KEPT
	local anyRarity = ctx.rare * kept + (1 - ctx.rare) * ctx.sale.plain
	local gear = (k.gearN * kept + k.gearP * ctx.sale.plain + (k.gearC or 0) * anyRarity) * lm
	local f = P.factors(ctx.cfg, mon.level, mon.scaled)
	local extra = ctx.extra * math.min(1, f.loot) * (k.stockGold + k.stockGear * anyRarity * lm)
	return plain + gear + extra, plain, gear, extra
end

function M.killsPerHour(ctx, mon)
	return P.lin(mon.scaled and ctx.kills.scaled or ctx.kills.base, mon.level, 1000)
end

function M.rules(ctx, mon, override)
	local f = P.factors(ctx.cfg, mon.level, mon.scaled)
	local setName = mon.scaled and "scaled" or "base"
	local old = {kind = "old", f = f, g = P.lin(M.OLD_GOLD[setName], mon.level, 1)}
	local nf = {loot = f.loot, coins = f.coins, junkKeep = f.junkKeep, notable = f.notable, cheap = f.cheap}
	if override then
		nf.coins = override.coins or nf.coins
		nf.junkKeep = override.junkKeep or nf.junkKeep
		nf.notable = override.notable and math.max(f.loot, override.notable) or nf.notable
	end
	return old, {kind = "new", f = nf, ll = ctx.ll, rare = ctx.rare}
end

-- one band: spawn-weighted per hour of both rules. override = {coins, junkKeep} for every monster (--derive)
function M.bandRange(band)
	if M.RANGES[band] then
		return M.RANGES[band][1], M.RANGES[band][2], false
	end
	if band > M.LATE_BANDS[1] - 1 then
		return math.max(M.LATE_FROM, math.floor(band * M.LATE_WINDOW[1])), math.ceil(band * M.LATE_WINDOW[2]), true
	end
	return math.floor(band * 0.85), math.ceil(band * 1.15), false
end
-- mix (O751, the one gold curve): the hunts of the base data and of the late data inside the range together (the base
-- pool ends at 657, the late monsters start at 658: a character of level 650 hunts both)
function M.band(ctx, band, override, mix)
	local lo, hi, late = M.bandRange(band)
	local list = late and ctx.late or ctx.data
	if mix then
		list = {}
		for _, src in ipairs({ctx.data, ctx.late}) do
			for _, mon in ipairs(src) do
				list[#list + 1] = mon
			end
		end
	end
	local acc = {w = 0, kills = 0, oldGold = 0, newGold = 0, oldItems = 0, newItems = 0, oldEmpty = 0, newEmpty = 0,
		oldRare = 0, newRare = 0, notableGold = 0, n = 0, sale = 0, salePlain = 0, saleGear = 0, saleExtra = 0}
	for _, mon in ipairs(list) do
		if mon.level >= lo and mon.level <= hi then
			local w = mon.spawns
			local k = M.killsPerHour(ctx, mon)
			local o, n = M.rules(ctx, mon, override)
			local a, b = M.perKill(mon, o), M.perKill(mon, n)
			acc.w = acc.w + w
			acc.n = acc.n + 1
			acc.kills = acc.kills + w * k
			acc.oldGold, acc.newGold = acc.oldGold + w * k * a.gold, acc.newGold + w * k * b.gold
			acc.oldItems, acc.newItems = acc.oldItems + w * k * a.items, acc.newItems + w * k * b.items
			acc.oldEmpty, acc.newEmpty = acc.oldEmpty + w * a.empty, acc.newEmpty + w * b.empty
			acc.notableGold = acc.notableGold + w * k * b.notableGold
			local sale, sp, sg, se = M.saleKill(ctx, mon, b)
			acc.sale, acc.salePlain = acc.sale + w * k * sale, acc.salePlain + w * k * sp
			acc.saleGear, acc.saleExtra = acc.saleGear + w * k * sg, acc.saleExtra + w * k * se
			-- Rare+ gear drops per kill that show: the stock gear chances x the Rare+ share x the notable share
			local gear = 0
			for _, e in ipairs(mon.loot) do
				if e[4] == "gear" then
					gear = gear + e[2] / 100000
				end
			end
			local share = gear * ctx.rare
			acc.newRare = acc.newRare + w * k * share * n.f.notable
			acc.oldRare = acc.oldRare + w * k * share * (mon.scaled and n.f.notable or M.oldNotable(ctx.cfg, mon.level))
		end
	end
	local w = math.max(acc.w, 1)
	return {band = band, monsters = acc.n, kills = acc.kills / w, oldGold = acc.oldGold / w, newGold = acc.newGold / w,
		oldItems = acc.oldItems / w, newItems = acc.newItems / w, oldEmpty = acc.oldEmpty / w,
		newEmpty = acc.newEmpty / w, oldRare = acc.oldRare / w, newRare = acc.newRare / w, notableGold = acc.notableGold / w,
		sale = acc.sale / w, salePlain = acc.salePlain / w, saleGear = acc.saleGear / w, saleExtra = acc.saleExtra / w}
end

-- O751: the one gold curve: {level, sale gold per hour, band row} at M.CURVE_BANDS (rounded to 1000; the base data starts
-- at level 40, the level 8 point of hunt_gold_config.lua is not modelled)
function M.curve(ctx)
	local pts = {}
	for _, b in ipairs(M.CURVE_BANDS) do
		local r = M.band(ctx, b, nil, true)
		pts[#pts + 1] = {b, math.floor(r.sale / 1000 + 0.5) * 1000, r}
	end
	return pts
end

-- the hunting gold of hunt_gold_config.lua at a level (linear between its points, flat beyond)
function M.huntGold(level, cfg)
	cfg = cfg or dofile("data/scripts/chaos/hunt_gold_config.lua")
	return P.lin(cfg.hunting, level, 0)
end

-- the shares (constant over the band) that hold the gold and items per hour a band is held to (`lootLevel.goldPerHour`
-- / `itemsPerHour`, else the 2026-10-20 rule's): the coins that give the gold, then the junkKeep that gives the items
-- (bisection: gold rises with coins, items with junkKeep up to KEEP_MAX), solved in turn until they settle. The notable
-- share is the curve of pace_config.lua (O285: the old rule on the pool scale, `rarePerHour` is held by --check), not a
-- parameter. junkKeep only bites below the coins share (above it every junk item that shows stays in kind), so a band
-- whose items are too high at junkKeep 6 needs a lower `cheapPrice` instead (bisection on the cheapPrice point: items
-- rise with it); the cheapPrice points of pace_config.lua were fitted that way (O285).
M.KEEP_MAX = 6
-- the levels --derive solves (the bands of the table and the curve points of pace_config.lua)
M.POINTS = {100, 300, 350, 400, 450, 500, 550, 600, 650}
function M.targets(ctx, band)
	local ref = M.band(ctx, band)
	return (ctx.ll.goldPerHour or {})[band] or ref.oldGold, (ctx.ll.itemsPerHour or {})[band] or ref.oldItems
end
function M.derive(ctx, band)
	local function solve(fn, target, hi)
		local lo = 0
		for _ = 1, 50 do
			local mid = (lo + hi) / 2
			if fn(mid) < target then lo = mid else hi = mid end
		end
		return (lo + hi) / 2
	end
	local gold, items = M.targets(ctx, band)
	local coins, keep = 0.1, 2
	for _ = 1, 12 do
		keep = solve(function(k)
			return M.band(ctx, band, {coins = coins, junkKeep = k}).newItems
		end, items * (1 - 1e-6), M.KEEP_MAX)
		coins = solve(function(c)
			return M.band(ctx, band, {coins = c, junkKeep = keep}).newGold
		end, gold, 2)
	end
	return coins, keep, nil
end

-- --fit: the curve points themselves (every band of M.POINTS reads the smooth curve at each monster's level, not a
-- constant): starting from the shipped points, each band's coins point x (old gold / new gold) and, from 700 on, its
-- junkKeep point x (old items / new items)^2, a few rounds. Prints the points for pace_config.lua.
function M.fit(ctx, rounds)
	local base = ctx.cfg.base
	local function pointsAt(list, keys)
		local out = {}
		for _, b in ipairs(keys) do
			out[#out + 1] = {b, P.smooth(list, b, 1)}
		end
		return out
	end
	local coinKeys, keepKeys = {35}, {650}
	for _, b in ipairs(M.POINTS) do
		coinKeys[#coinKeys + 1] = b
		if b >= 700 then
			keepKeys[#keepKeys + 1] = b
		end
	end
	-- the shipped points past the last band stay where they are (1250: the top of the pool, the 1500 band)
	for _, pt in ipairs(base.coins) do
		if pt[1] > M.POINTS[#M.POINTS] then
			coinKeys[#coinKeys + 1] = pt[1]
		end
	end
	local coins, keep = pointsAt(base.coins, coinKeys), pointsAt(base.junkKeep, keepKeys)
	coins[1][2] = 1
	keep[1][2] = 5
	local function apply()
		base.coins, base.junkKeep = coins, keep
		local sc = {{100, coins[2][2]}, {275, 0.65 * coins[2][2]}}
		for _, pt in ipairs(coins) do
			if pt[1] >= 450 then
				sc[#sc + 1] = pt
			end
		end
		ctx.cfg.scaled.coins, ctx.cfg.scaled.junkKeep = sc, keep
	end
	for _ = 1, rounds or 12 do
		apply()
		for i, pt in ipairs(coins) do
			if M.RANGES[pt[1]] then
				local r = M.band(ctx, pt[1])
				if r.monsters > 0 then
					pt[2] = math.min(1, pt[2] * (r.oldGold / r.newGold) ^ 0.7)
					for _, kp in ipairs(keep) do
						if kp[1] == pt[1] then
							kp[2] = math.max(0.01, math.min(5, kp[2] * (r.oldItems / r.newItems) ^ 1.5))
						end
					end
				end
			end
		end
	end
	apply()
	return coins, keep
end

-- per kill of one monster by name: {old =, new =, f =}
function M.monster(ctx, name)
	for _, mon in ipairs(ctx.data) do
		if mon.name == name then
			local o, n = M.rules(ctx, mon)
			return {level = mon.level, old = M.perKill(mon, o), new = M.perKill(mon, n), f = n.f}
		end
	end
	return nil
end

-- the hunting gold per hour of the one curve (hunt_gold_config.lua; before O751 the "Respec" table of gamble_config.lua)
function M.respec(level)
	return M.huntGold(level)
end

local function fmt(n)
	local s = string.format("%.0f", n)
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end
M.fmt = fmt

function M.report(ctx)
	local lines = {"| Band | Monsters | Kills/h | Gold/h before | Gold/h after | Items/h before | Items/h after | Per kill: gold, items before / after | Empty corpse before / after | Rare+ gear/h before / after | Sale gold/h (hunt_gold_config.lua) |",
		"|---|---|---|---|---|---|---|---|---|---|---|"}
	local rows = {}
	for _, b in ipairs(M.BANDS) do
		local r = M.band(ctx, b)
		rows[#rows + 1] = r
		lines[#lines + 1] = string.format("| %d | %d | %s | %s | %s (%+.1f%%) | %s | %s (%+.1f%%) | %s, %.2f / %s, %.2f | %.0f%% / %.0f%% | %.1f / %.1f | %s |",
			b, r.monsters, fmt(r.kills), fmt(r.oldGold), fmt(r.newGold), 100 * (r.newGold / r.oldGold - 1), fmt(r.oldItems),
			fmt(r.newItems), 100 * (r.newItems / r.oldItems - 1), fmt(r.oldGold / r.kills), r.oldItems / r.kills,
			fmt(r.newGold / r.kills), r.newItems / r.kills, 100 * r.oldEmpty, 100 * r.newEmpty, r.oldRare, r.newRare, fmt(M.respec(b)))
	end
	return table.concat(lines, "\n"), rows
end

function M.main(args)
	local mode = args[1]
	local ctx = M.load()
	for _, b in ipairs(M.POINTS) do
		M.RANGES[b] = M.RANGES[b] or {math.floor(b * 0.85), math.ceil(b * 1.15)}
	end
	if mode == "--fit" then
		local coins, keep = M.fit(ctx)
		local function show(list)
			local t = {}
			for _, pt in ipairs(list) do
				t[#t + 1] = string.format("{%d, %.3f}", pt[1], pt[2])
			end
			return "{" .. table.concat(t, ", ") .. "}"
		end
		print("coins = " .. show(coins))
		print("junkKeep = " .. show(keep))
		for _, b in ipairs(M.POINTS) do
			local r = M.band(ctx, b)
			print(string.format("band %4d  gold %+.1f%%  items %+.1f%%", b, 100 * (r.newGold / r.oldGold - 1),
				100 * (r.newItems / r.oldItems - 1)))
		end
		return 0
	end
	if mode == "--income" then
		print("| Band | Hunts (levels) | Monsters | Kills/h | Corpse gold/h | Coins and junk/h | Gear at sale price/h | Extra rolls/h | Sale gold/h | hunt_gold_config.lua |")
		print("|---|---|---|---|---|---|---|---|---|---|")
		for _, pt in ipairs(M.curve(ctx)) do
			local r = pt[3]
			local lo, hi = M.bandRange(pt[1])
			print(string.format("| %d | %d-%d | %d | %s | %s | %s | %s | %s | %s | %s |", pt[1], lo, hi, r.monsters, fmt(r.kills),
				fmt(r.newGold), fmt(r.salePlain), fmt(r.saleGear), fmt(r.saleExtra), fmt(r.sale), fmt(M.huntGold(pt[1]))))
		end
		print(string.format("gear price x%.2f (no rarity to Magic), Rare+ x%g (kept; x%.2f sold to an NPC) before the item level; Rare+ share %.3f; extra rolls %.4f of a kill's stock loot x its loot factor",
			ctx.sale.plain, M.RARE_KEPT, ctx.sale.notable, ctx.rare, ctx.extra))
		ctx.rareKept = ctx.sale.notable
		local t = {}
		for _, b in ipairs(M.CURVE_BANDS) do
			t[#t + 1] = string.format("%d: %s", b, fmt(M.band(ctx, b, nil, true).sale))
		end
		print("with every Rare+ piece sold to an NPC: " .. table.concat(t, ", "))
		ctx.rareKept = nil
		local t, prev = {}, 0
		for _, pt in ipairs(M.curve(ctx)) do
			prev = math.max(prev, pt[2])
			t[#t + 1] = string.format("{%d, %d}", pt[1], prev)
		end
		print("hunting = {" .. table.concat(t, ", ") .. "} (never falling)")
		return 0
	end
	if mode == "--derive" then
		for _, b in ipairs(M.POINTS) do
			M.RANGES[b] = M.RANGES[b] or {math.floor(b * 0.85), math.ceil(b * 1.15)}
			local c, k, n = M.derive(ctx, b)
			local r = M.band(ctx, b, {coins = c, junkKeep = k, notable = n})
			local g, i = M.targets(ctx, b)
			print(string.format("band %4d  coins %.4f  junkKeep %.4f  gold %+.1f%%  items %+.1f%%  Rare+ gear/h %.1f", b, c, k,
				100 * (r.newGold / g - 1), 100 * (r.newItems / i - 1), r.newRare))
		end
		return 0
	end
	local text, rows = M.report(ctx)
	print(text)
	print("")
	print("| Monster | Level | Gold / kill before / after | Items / kill before / after | Coins shown | Empty corpse before / after |")
	print("|---|---|---|---|---|---|")
	for _, name in ipairs(M.WIDOWS) do
		local w = M.monster(ctx, name)
		print(string.format("| %s | %d | %s / %s | %.2f / %.2f | %.0f%% / %.0f%% | %.0f%% / %.0f%% |", name, w.level,
			fmt(w.old.gold), fmt(w.new.gold), w.old.items, w.new.items, 100 * w.old.coins, 100 * w.new.coins,
			100 * w.old.empty, 100 * w.new.empty))
	end
	if mode == "--check" then
		local bad = 0
		-- the table's bands and every curve point of --derive
		for _, b in ipairs(M.POINTS) do
			if not M.RANGES[b] then
				M.RANGES[b] = {math.floor(b * 0.85), math.ceil(b * 1.15)}
				rows[#rows + 1] = M.band(ctx, b)
			end
		end
		for _, b in ipairs(M.SMOOTH_BANDS) do
			if not M.RANGES[b] then
				M.RANGES[b] = {math.floor(b * 0.85), math.ceil(b * 1.15)}
				rows[#rows + 1] = M.band(ctx, b)
			end
		end
		-- the gold per hour a band is held to: the smooth curve of pace_config.lua lootLevel.goldPerHour {band = gold}
		-- where it lists the band, else the 2026-10-20 rule's
		local want = ctx.ll.goldPerHour or {}
		-- O285: the items per hour a band is held to (`lootLevel.itemsPerHour`, the 2026-10-20 values of before the monsters
		-- stood at their pool level), else the 2026-10-20 rule's at the same loot factor
		local wantItems = ctx.ll.itemsPerHour or {}
		-- the Rare+ gear per hour a band is held to: `lootLevel.rarePerHour` {band = pieces} where it lists the band, else
		-- the rule of before's (M.OLD_RULE) on the same monsters: the notable drops must not thin out with the pool scale
		local wantRare = ctx.ll.rarePerHour or {}
		for _, r in ipairs(rows) do
			local rref = wantRare[r.band] or r.oldRare
			if rref > 0 and math.abs(r.newRare / rref - 1) > M.TOL.rare then
				bad = bad + 1
				print(string.format("band %d out of tolerance: Rare+ gear per hour %.2f against %.2f (%+.1f%%)", r.band,
					r.newRare, rref, 100 * (r.newRare / rref - 1)))
			end
			local ref = want[r.band] or r.oldGold
			local iref = wantItems[r.band] or r.oldItems
			local dg, di = math.abs(r.newGold / ref - 1), math.abs(r.newItems / iref - 1)
			if dg > M.TOL.gold or di > M.TOL.items then
				bad = bad + 1
				print(string.format("band %d out of tolerance: gold %+.1f%% (of %s), items %+.1f%%", r.band,
					100 * (r.newGold / ref - 1), want[r.band] and "the goldPerHour target" or "the 2026-10-20 rule",
					100 * (r.newItems / iref - 1)))
			end
		end
		table.sort(rows, function(a, b) return a.band < b.band end)
		for i = 2, #rows do
			local a, b = rows[i - 1], rows[i]
			if a.band >= M.SMOOTH_FROM and b.band - a.band <= M.SMOOTH_SPAN then
				-- O285: the Rare+ gear and rare drops (`notableGold`) are luck, and the pool levels 350-410 hold the richest
				-- stock gear: the no-dip rule reads the gold without them (the trade gold), the step bound the whole
				local step = b.newGold / a.newGold
				local tradeStep = (b.newGold - b.notableGold) / (a.newGold - a.notableGold)
				if tradeStep < 1 or step > M.MAX_STEP then
					bad = bad + 1
					print(string.format("gold per hour from band %d to %d: x%.2f (%s to %s), trade gold x%.2f, allowed 1 to %.1f",
						a.band, b.band, step, fmt(a.newGold), fmt(b.newGold), tradeStep, M.MAX_STEP))
				end
			end
		end
		-- O751: the one gold curve (hunt_gold_config.lua) at the model's sale gold, every band, never falling (a point held
		-- at the one before where the model dips, at most M.TOL.flat above it)
		local hg = dofile("data/scripts/chaos/hunt_gold_config.lua")
		local prev = 0
		for _, pt in ipairs(M.curve(ctx)) do
			local have = M.huntGold(pt[1], hg)
			local d = have / pt[3].sale - 1
			local held = math.abs(have - prev) < 0.5 and d > 0 and d <= M.TOL.flat
			if math.abs(d) > M.TOL.curve and not held then
				bad = bad + 1
				print(string.format("hunt_gold_config.lua at level %d: %s against the model's sale gold %s (%+.1f%%, allowed %.0f%%)",
					pt[1], fmt(have), fmt(pt[3].sale), 100 * d, 100 * M.TOL.curve))
			end
			if have < prev then
				bad = bad + 1
				print(string.format("hunt_gold_config.lua falls at level %d (%s after %s)", pt[1], fmt(have), fmt(prev)))
			end
			prev = have
		end
		local last = hg.hunting[#hg.hunting][1]
		if last < M.CURVE_BANDS[#M.CURVE_BANDS] then
			bad = bad + 1
			print(string.format("hunt_gold_config.lua ends at level %d, the model to %d", last, M.CURVE_BANDS[#M.CURVE_BANDS]))
		end
		print(bad == 0 and "loot model: every band within the tolerances" or "loot model: OUT OF TOLERANCE")
		return bad == 0 and 0 or 1
	end
	return 0
end

if ChaosLootModelLib then
	return M
end
os.exit(M.main(arg or {}))
