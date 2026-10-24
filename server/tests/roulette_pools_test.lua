-- Run from the server/ folder: luajit tests/roulette_pools_test.lua (and lua5.3; CI runs both)
-- The prize pools of the exercise, premium and the two crystal token roulettes (data/scripts/chaos/roulette_{exercise,
-- premium,crystal}_config.lua, tools/patch_roulette.py, README "Roulette prizes against token drops", O151) and the value
-- of a spin of every roulette against the hunting time its token costs (tools/roulette_model.lua,
-- roulette_value_config.lua). Checks: no retired id (decks, ships, belts, gloves, the retired axe and club chests, the fixed
-- "Moist" gear), no dead id, no repeated prize, the odds add up, the shares the config's limits hold, the orbs are the ones
-- the loot layer drops, the exercise chest is always one the winner's class can train with, the actionIds and tokens match
-- the base scripts, the value config matches the data it copies (pace, gold curve, token sources), every roulette is worth
-- its token at every level; prints the numbers before and after.

local checks, fails = 0, 0
local function ok(cond, what)
	checks = checks + 1
	if not cond then
		fails = fails + 1
		print("FAIL " .. what)
	end
end
local function near(a, b, eps, what)
	ok(math.abs(a - b) <= eps, what .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end
local function readFile(path)
	local f = assert(io.open(path, "r"), path)
	local s = f:read("*a")
	f:close()
	return s
end

ChaosRouletteModelLib = true
local M = dofile("tools/roulette_model.lua")
ChaosRouletteModelLib = nil
local K = ChaosPrizesCore
local V = M.V

-- ------------------------------------------------------------------------------------------------ the item ids
local known = {}
local function addAll(text, pattern)
	for id in text:gmatch(pattern) do
		known[tonumber(id)] = true
	end
end
addAll(readFile("data/items/base_item_names.csv"), "\n(%d+),")
addAll(readFile("data/items/base_item_values.csv"), "\n(%d+),")
addAll(readFile("data/items/chaos_items.xml"), 'id="(%d+)"')
addAll(readFile("data/lib/chaos_item_prices_data.lua"), "%[(%d+)%]")
addAll(readFile("data/lib/chaos_orbs_config.lua"), "id = (%d+)")
addAll(readFile("data/lib/chaos_crafting.lua"), "id = (%d+)")
addAll(readFile("data/lib/chaos_gems_config.lua"), "id = (%d+)")
-- the base items.xml is not in the repo: the ids that only the base data defines (the Tower Defense units and the
-- cosmetics) are listed by the base use-scripts and the price lists of the committed data
addAll(readFile("data/scripts/chaos/sell_prices.lua"), "%[(%d+)%]")
-- ids that only the base server's items.xml defines (auras and the Tower Defense units; the base use-scripts and the
-- Tower Defense script name them): tools/patch_roulette_test.py checks them against an installed items.xml
for _, id in ipairs({26649, 26650, 26651, 26652, 26653, 28369, 28370}) do
	known[id] = true
end
local badgesPy = readFile("tools/patch_badges.py")
local lo, hi = badgesPy:match("BADGES = range%((%d+), (%d+)%)")
for id = tonumber(lo), tonumber(hi) - 1 do
	known[id] = true
end

local retiredAlways = {}
for _, name in ipairs({"DECKS", "BELTGLOVES"}) do
	local body = badgesPy:match(name .. " = %(([^)]*)%)")
	for id in (body or ""):gmatch("%d+") do
		retiredAlways[tonumber(id)] = true
	end
end
local shipLo, shipHi = badgesPy:match("SHIPS = tuple%(range%((%d+), (%d+)%)%)")
for id = tonumber(shipLo), tonumber(shipHi) - 1 do
	retiredAlways[id] = true
end
ok(retiredAlways[27633] and retiredAlways[27634] and retiredAlways[27797] and retiredAlways[29577],
	"the retired set holds decks, ships, belts")

local MOIST = {} -- the pieces of the old crystal pool (the helmet 28382 was not in it; it is a transmog set look)
for id = 28373, 28393 do
	if id ~= 28382 then
		MOIST[id] = true
	end
end
local RETIRED_CHESTS = {[27762] = true, [27763] = true, [27769] = true, [27770] = true, [27776] = true, [27777] = true}

local KINDS = {
	exercise = {orb = true, material = true, gold = true, unique = true, chest = true},
	premium = {orb = true, material = true, gold = true, unique = true, cosmetic = true},
	crystal = {orb = true, material = true, gold = true, unique = true, unit = true},
}

-- ------------------------------------------------------------------------------------------------ the loot layer orbs
local dropped = {}
for id in pairs((function()
	local t = {}
	for _, e in ipairs(dofile("data/scripts/chaos/loot_config.lua").currency.entries) do
		t[e.id] = true
	end
	return t
end)()) do
	dropped[id] = true
end

-- ------------------------------------------------------------------------------------------------ the pools
local cfgs = {}
local actionSeen = {}
for _, key in ipairs({"exercise", "premium", "crystal"}) do
	local cfg = M.load(key)
	cfgs[key] = cfg
	local lim = cfg.limits
	ok(cfg.title == key, key .. ": title")
	ok(cfg.token == V.tokens[key].item, key .. ": the token is the value config's")
	ok(cfg.tokenCount >= 1, key .. ": a token count")
	ok(cfg.gold == dofile("data/scripts/chaos/boss_roulette_config.lua").gold or cfg.gold.perUnit == 0.2,
		key .. ": the gold of the boss roulette")
	ok(cfg.gold.hunting and #cfg.gold.hunting == 6, key .. ": a hunting gold curve")
	ok(cfg.unique and cfg.unique.low and cfg.unique.high, key .. ": a unique band")
	ok(cfg.rareThreshold and cfg.rareThreshold >= 1 and cfg.rareThreshold <= 1000, key .. ": a broadcast threshold")
	for _, aid in ipairs(cfg.actionIds) do
		ok(not actionSeen[aid], key .. ": actionId " .. aid .. " is used once")
		actionSeen[aid] = true
		ok(aid >= 18563 and aid <= 18566, key .. ": actionId " .. aid .. " is one of the base roulettes")
	end

	local retired = {}
	for id in pairs(retiredAlways) do
		retired[id] = true
	end
	for _, id in ipairs(cfg.retired) do
		retired[id] = true
	end
	local seen, ids = {}, {}
	for i, e in ipairs(cfg.pool) do
		local tag = key .. " entry " .. i .. " " .. tostring(e.name)
		ok(type(e.id) == "number" and e.id > 0, tag .. ": an id")
		ok(known[e.id], tag .. ": id " .. tostring(e.id) .. " is a known item")
		ok(not retired[e.id], tag .. ": not retired")
		ok(not MOIST[e.id], tag .. ": not the fixed Moist gear")
		ok(not RETIRED_CHESTS[e.id], tag .. ": not a retired exercise chest")
		ok(KINDS[key][e.kind], tag .. ": a kind of this roulette (" .. tostring(e.kind) .. ")")
		ok(e.count[1] >= 1 and e.count[2] >= e.count[1], tag .. ": a count")
		ok(e.chance >= 1 and e.chance <= 10000, tag .. ": a chance in 1..10000")
		ok(type(e.name) == "string" and #e.name > 2, tag .. ": a name")
		local sig = e.id .. ":" .. e.count[1] .. "-" .. e.count[2]
		ok(not seen[sig], tag .. ": not twice")
		seen[sig] = true
		if e.kind ~= "gold" then
			ok(not ids[e.id], tag .. ": the id appears once (only gold repeats the crystal coin)")
		end
		ids[e.id] = true
		if e.kind == "orb" or e.kind == "material" then
			ok(dropped[e.id], tag .. " is an orb the loot layer drops (currency.entries)")
		elseif e.kind == "gold" then
			ok(e.id == 2160, tag .. ": gold is shown as crystal coins")
		elseif e.kind == "unique" then
			ok(e.id == 1740, tag .. ": the unique chest")
		end
	end
	ok(#cfg.pool >= 15, key .. ": a pool with variety (" .. #cfg.pool .. ")")

	local odds = M.odds(cfg)
	local sum, share = 0, {}
	for i, e in ipairs(cfg.pool) do
		sum = sum + odds[i]
		share[e.kind] = (share[e.kind] or 0) + odds[i]
	end
	near(sum, 1, 1e-9, key .. ": the odds add up to 1")
	local bulk = (share.orb or 0) + (share.material or 0) + (share.gold or 0)
	ok(bulk >= lim.minOrbShare, key .. ": orbs, sockets and gold are the bulk: " .. bulk)
	ok((share.gold or 0) >= lim.minGoldShare, key .. ": gold share: " .. (share.gold or 0))
	ok(share.unique >= lim.minUniqueShare and share.unique <= lim.maxUniqueShare, key .. ": unique chest share: " .. share.unique)
	-- the broadcast: a prize is announced when its chance is at most the threshold: the gold and the plain stacks never,
	-- only the chase orbs
	for _, e in ipairs(cfg.pool) do
		if e.kind == "gold" or e.kind == "unique" or e.kind == "cosmetic" or e.kind == "unit" then
			ok(e.chance > cfg.rareThreshold, key .. ": " .. e.name .. " is not broadcast as a rare prize")
		end
	end
	cfg._share = share
	cfg._odds = odds
end

-- the actionIds: the four base roulettes besides the boss one, the crystal ones twice
ok(actionSeen[18563] and actionSeen[18564] and actionSeen[18565] and actionSeen[18566], "every base roulette has a pool")
local boss = M.load("boss")
ok(boss.actionIds[1] == 18562 and boss.title == "boss" and boss.token == 28033, "the boss roulette's ids")

-- ------------------------------------------------------------------------------------------------ exercise: the chests
local avgUsable = 0
do
	local cfg, share = cfgs.exercise, cfgs.exercise._share
	ok(share.chest <= cfg.limits.maxChestShare, "exercise: chests are at most " .. cfg.limits.maxChestShare .. " of the spins: "
		.. share.chest)
	ok(share.chest >= 0.05, "exercise: the chests stay the theme: " .. share.chest)
	local inTier = {}
	for t, tier in ipairs(cfg.chests.tiers) do
		for _, kind in ipairs(cfg.chests.kinds) do
			inTier[tier[kind]] = {tier = t, kind = kind}
			ok(known[tier[kind]], "exercise: tier " .. t .. " " .. kind .. " chest is a known item")
			ok(not RETIRED_CHESTS[tier[kind]], "exercise: tier " .. t .. " " .. kind .. " chest is not retired")
		end
	end
	local pooled = {}
	for _, e in ipairs(cfg.pool) do
		if e.kind == "chest" then
			ok(inTier[e.id], "exercise: " .. e.name .. " is in the chest table")
			pooled[e.id] = true
		end
	end
	for id in pairs(inTier) do
		ok(pooled[id], "exercise: chest " .. id .. " is in the pool")
	end
	-- the price of every chest is known (the model values it by it)
	for id in pairs(inTier) do
		ok(M.price(id) and M.price(id) > 0, "exercise: chest " .. id .. " has a price")
	end

	-- every class gets a chest it can train with, whichever chest the tile shows
	dofile("data/scripts/chaos/exercise_core.lua")
	local E = ChaosExercise
	local vocations = {}
	for line, ids in pairs(E.cfg.lines) do
		for _, v in ipairs(ids) do
			vocations[#vocations + 1] = {id = v, line = line}
		end
	end
	ok(#vocations >= 21, "the class lines list 21+ vocations: " .. #vocations)
	for _, voc in ipairs(vocations) do
		local allowed = function(kind) return E.allowed(kind, voc.id) end
		for id, where in pairs(inTier) do
			for pick = 1, 5 do
				local got, changed = K.classChest(cfg, id, allowed, function(n) return math.min(pick, n) end)
				local g = inTier[got]
				ok(g and g.tier == where.tier, "exercise: vocation " .. voc.id .. " chest " .. id .. ": the same tier")
				ok(g and allowed(g.kind), "exercise: vocation " .. voc.id .. " chest " .. id .. " -> " .. tostring(got) ..
					" is one it can train with")
				ok(changed == (got ~= id), "exercise: changed says whether the id changed")
			end
		end
	end

	-- before: how many of the old spins gave a chest a class could use
	local oldKinds = {[27761] = "melee", [27762] = "melee", [27763] = "melee", [27764] = "ranged", [27765] = "rod",
		[27766] = "wand", [27767] = "shield"}
	local old = {}
	for i = 0, 6 do
		old[#old + 1] = {itemId = 27761 + i, chance = 6000}
	end
	for i = 0, 6 do
		old[#old + 1] = {itemId = 27768 + i, chance = 2500}
	end
	for i = 0, 6 do
		old[#old + 1] = {itemId = 27775 + i, chance = 900}
	end
	local o = K.odds(old)
	local usable = {}
	for i, e in ipairs(old) do
		local kind = oldKinds[27761 + (e.itemId - 27761) % 7]
		for line in pairs(E.cfg.lines) do
			local v = E.cfg.lines[line][1]
			usable[line] = (usable[line] or 0) + (E.allowed(kind, v) and o[i] or 0)
		end
	end
	local parts = {}
	for _, line in ipairs({"warrior", "ranger", "mystic", "thief", "monk", "necromancer", "templar"}) do
		avgUsable = avgUsable + (usable[line] or 0) / 7
		parts[#parts + 1] = string.format("%s %.0f%%", line, (usable[line] or 0) * 100)
		ok(usable[line] and usable[line] < 0.9, "exercise: before, the " .. line .. " line could use only " ..
			string.format("%.0f%%", (usable[line] or 0) * 100) .. " of the chests")
	end
	print("Exercise Roulette, share of the old spins (21 chests) that a class could use: " .. table.concat(parts, ", ") ..
		"; now every chest is usable (and chests are " .. string.format("%.1f%%", share.chest * 100) .. " of the spins)")
end

-- ------------------------------------------------------------------------------------------------ premium: cosmetics
do
	local cfg, share = cfgs.premium, cfgs.premium._share
	ok(share.cosmetic <= cfg.limits.maxCosmeticShare, "premium: cosmetics are at most " .. cfg.limits.maxCosmeticShare ..
		" of the spins: " .. share.cosmetic)
	ok(share.cosmetic >= 0.10, "premium: the cosmetics stay a prize: " .. share.cosmetic)
	local n = 0
	for _, e in ipairs(cfg.pool) do
		if e.kind == "cosmetic" then
			n = n + 1
			ok((e.id >= 26649 and e.id <= 26653) or (e.id >= 27975 and e.id <= 27984), "premium: " .. e.name .. " is an aura or wings")
		end
	end
	ok(n == 14, "premium: the 14 auras and wings of the base pool: " .. n)
	-- the chase orbs stay chase prizes, each between the config's bounds, and the rarest one is announced
	local chase = {"Orb of Ruin", "Void Orb", "Crown Orb", "Ember Orb", "Orb of Binding", "Orb of Excision"}
	local rarest = 1
	for _, name in ipairs(chase) do
		for i, e in ipairs(cfg.pool) do
			if e.name == name then
				ok(cfg._odds[i] <= cfg.limits.maxChaseShare, "premium: " .. name .. " is at most " .. cfg.limits.maxChaseShare ..
					" of the spins: " .. cfg._odds[i])
				rarest = math.min(rarest, cfg._odds[i])
			end
		end
	end
	ok(rarest >= 0.0001 and rarest < cfg.limits.minChaseShare, "premium: the rarest chase orb is rare but possible: " .. rarest)
end

-- ------------------------------------------------------------------------------------------------ crystal: the units
do
	local cfg, share = cfgs.crystal, cfgs.crystal._share
	ok(share.unit <= cfg.limits.maxUnitShare and share.unit > 0, "crystal: the units are the theme, at most " ..
		cfg.limits.maxUnitShare .. ": " .. share.unit)
	ok(cfg.tokenCount == 15, "crystal: 15 tokens a spin, as the base scripts")
end

-- ------------------------------------------------------------------------------------------------ the value config
-- the pace is the one of tools/spawn_tuning.json
do
	local tuning = readFile("tools/spawn_tuning.json")
	local block = tuning:match('"scaled": (%[%[.-%]%])')
	local pts = {}
	for a, b in (block or ""):gmatch("%[(%d+), (%d+)%]") do
		pts[#pts + 1] = {tonumber(a), tonumber(b)}
	end
	ok(#pts == #V.kph, "the pace has the points of spawn_tuning.json paceKillsPerHour.scaled")
	for i, p in ipairs(pts) do
		ok(V.kph[i] and V.kph[i][1] == p[1] and V.kph[i][2] == p[2], "pace point " .. i)
	end
	-- the gold curve is the one of gamble_config.lua (the boss test checks that too)
	local hunting = dofile("data/scripts/chaos/gamble_config.lua").balance.hunting
	for i, p in ipairs(hunting) do
		ok(boss.gold.hunting[i][1] == p[1] and boss.gold.hunting[i][2] == p[2], "gold curve point " .. i)
	end
	-- the token sources: how many monsters drop each token and from which level (the survey of the base monsters)
	local rows = {}
	for line in readFile("data/items/base_item_values.csv"):gmatch("[^\n]+") do
		local f = {}
		for x in (line .. ","):gmatch("([^,]*),") do
			f[#f + 1] = x
		end
		rows[tonumber(f[1]) or 0] = f
	end
	for key, want in pairs({boss = {43, 509}, exercise = {43, 509}, premium = {22, 1018}}) do
		local t = V.tokens[key]
		local r = rows[t.item]
		ok(r and tonumber(r[11]) == want[1] and tonumber(r[11]) == t.bosses, key .. ": " .. want[1] .. " monsters drop the token")
		ok(r and tonumber(r[12]) == want[2], key .. ": from level " .. want[2])
		ok(t.chance > 0.04 and t.chance < 0.2 and t.count == 1.5, key .. ": a plausible drop chance")
		-- the highest loot chance of the survey is not below the mean
		ok(r and tonumber(r[14]) / 100000 >= t.chance, key .. ": the mean chance is below the maximum of the survey")
	end
	ok(V.tokens.crystal.perRun == 5, "a Tower Defense run pays 5 Crystal Tokens")
	ok(V.band.min > 0 and V.band.max > V.band.min, "a band")
	ok(V.minutesPerBossKill >= 3 and V.minutesPerBossKill <= 20, "a plausible boss kill time")
end

-- ------------------------------------------------------------------------------------------------ the value of a spin
local function pct(x) return string.format("%.0f%%", x * 100) end
print("Roulette spin against its token (minutes of hunting; orbs, sockets, gold, exercise chests and unique chests counted)")
for _, r in ipairs(M.rows()) do
	ok(r.ratio >= V.band.min and r.ratio <= V.band.max, string.format("%s at level %d: value %.1f / cost %.1f = %.2f is in %.2f-%.2f",
		r.key, r.level, r.value, r.cost, r.ratio, V.band.min, V.band.max))
	if r.level == 1000 then
		print(string.format("  %-8s level %d: %5.1f min of prizes for %5.1f min of tokens (x%.2f): %.2f orbs, %.0f gold, "
			.. "cards/badges/cosmetics/units not counted", r.key, r.level, r.value, r.cost, r.ratio, r.spin.orbs, r.spin.gold))
	end
end
-- the cost side
near(M.cost("boss", boss), 1 / (0.0837 * 1.5) * V.minutesPerBossKill, 1e-9, "boss token cost")
near(M.cost("crystal", cfgs.crystal), 3 * V.minutesPerRun, 1e-9, "crystal: 15 tokens are 3 runs")
ok(M.cost("premium", cfgs.premium) > M.cost("exercise", cfgs.exercise) and M.cost("exercise", cfgs.exercise) > M.cost("boss", boss),
	"the rarer the token, the more a spin is worth")
-- the same number every roulette wins by: a spin does not fall with the level (gold and pace move it a little)
for _, key in ipairs(M.KEYS) do
	local cfg = M.load(key)
	local a, b = M.spin(cfg, 650).minutes, M.spin(cfg, 2000).minutes
	ok(b >= a * 0.95, key .. ": a spin at level 2000 is not worth less than at 650")
	ok(b <= a * 1.35, key .. ": and not far more")
end

-- before: what the counted value of a spin was (the chests by price; the Moist gear, the cosmetics and the units are not counted
-- here, they only sold to an NPC), against the cost of the token
do
	local oldEx = {}
	for i = 0, 6 do oldEx[#oldEx + 1] = {id = 27761 + i, chance = 6000} end
	for i = 0, 6 do oldEx[#oldEx + 1] = {id = 27768 + i, chance = 2500} end
	for i = 0, 6 do oldEx[#oldEx + 1] = {id = 27775 + i, chance = 900} end
	local pool = {}
	for i, e in ipairs(oldEx) do pool[i] = {itemId = e.id, chance = e.chance} end
	local o = K.odds(pool)
	local v = 0
	for i, e in ipairs(oldEx) do
		v = v + o[i] * M.entryMinutes({gold = boss.gold}, {id = e.id, count = {1, 1}, kind = "chest"}, 1000)
	end
	local cost = M.cost("exercise", cfgs.exercise)
	ok(v < 0.1 * cost, "exercise before: chests were worth " .. string.format("%.1f", v) .. " min of a " .. string.format("%.0f", cost) ..
		" min token")
	print(string.format("  before: exercise %.1f min of %.0f (x%.2f; %s of the chests unusable to the average class); premium: 14 cosmetics, "
		.. "0 min counted of %.0f; crystal: 21 fixed Moist pieces and 2 units, 0 min counted of %.0f", v, cost, v / cost,
		pct(1 - avgUsable), M.cost("premium", cfgs.premium), M.cost("crystal", cfgs.crystal)))
end

print(string.format("roulette_pools_test: %d of %d failed", fails, checks))
os.exit(fails == 0 and 0 or 1)
