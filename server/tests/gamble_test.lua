-- Run from the server/ folder: luajit tests/gamble_test.lua (and lua5.3; CI runs both)
-- The Gambler: the pure rules (gamble_core.lua: config check, the 4-hour windows and their boundaries in a fixed and in
-- the server's own time zone, the seed, stock determinism per character / window / early refresh, the base types a
-- character can use around its level, item levels never above the gate, prices and their share of hunting gold per hour,
-- the sold slots, the exact rarity odds against a monster drop and against the loot layer's real roll, the purchase
-- refusals) and the engine part (gamble.lua) against a mocked engine: reading movements.xml / weapons.xml, the window
-- state, buying (gold first, the sold mark, the save, then the roll and the item), a slot sold once, too little gold,
-- a failed save (gold back, nothing rolled), two requests at once, a relog and a restart keeping the stock, a new
-- window, the early refresh, the rate limit, away from the Gambler, the NPC placement.

local count, failures = 0, 0
local function check(cond, label)
	count = count + 1
	if not cond then
		failures = failures + 1
		print("FAIL " .. label)
	end
end
local function eq(a, b, label)
	check(a == b, label .. " (" .. tostring(a) .. " ~= " .. tostring(b) .. ")")
end
local function has(text, part, label)
	check(type(text) == "string" and text:find(part, 1, true) ~= nil, label .. " (" .. tostring(text) .. ")")
end

local cfg = dofile("data/scripts/chaos/gamble_config.lua")
dofile("data/scripts/chaos/gamble_core.lua")
ChaosArcheryConfigForTest = dofile("data/lib/chaos_archery_config.lua")
local K = ChaosGambleCore
dofile("data/lib/chaos_item_mods.lua")
local M = ChaosItemMods
local function gate(level)
	return M.sourceLevel({monsterLevel = level, tier = cfg.itemLevel.tier})
end

-- ---------------------------------------------------------------- config
local errors = K.validate(cfg)
eq(#errors, 0, "config valid: " .. table.concat(errors, "; "))
eq(cfg.opcode, 199, "opcode")
eq(cfg.storage, 7101900, "storage block")
eq(cfg.refresh.hours, 4, "every 4 hours")
check(cfg.stock.size >= 12 and cfg.stock.size <= 16, "12-16 pieces")
do
	local bad = dofile("data/scripts/chaos/gamble_config.lua")
	bad.refresh.hours = 5
	bad.pool.ring[2] = {bad.pool.ring[1][1], 5}
	bad.price.curve[3] = {2, 1}
	bad.stock.order[#bad.stock.order + 1] = "tail"
	check(#K.validate(bad) >= 4, "a broken config is reported (" .. #K.validate(bad) .. ")")
end

-- ---------------------------------------------------------------- the 4-hour windows
do
	local c = dofile("data/scripts/chaos/gamble_config.lua")
	c.refresh.utcOffsetHours = -3
	local off = K.offset(c, 0)
	eq(off, -3 * 3600, "UTC-3 offset")
	local t = 1791702000 -- 2026-10-11 07:00:00 UTC = 04:00:00 UTC-3
	local w = K.window(c, t, off)
	eq(K.window(c, t - 1, off), w - 1, "03:59:59 is the window before")
	eq(K.window(c, t + 4 * 3600 - 1, off), w, "07:59:59 is the same window")
	eq(K.window(c, t + 4 * 3600, off), w + 1, "08:00:00 starts the next")
	eq(K.windowStart(c, w, off), t, "the window starts at 04:00 UTC-3")
	eq(K.nextRefresh(c, t, off), t + 4 * 3600, "next refresh at 08:00")
	eq(K.nextRefresh(c, t - 1, off), t, "one second before: the refresh is now")
	eq(K.clock(c, w), "04:00", "clock text")
	eq(K.clock(c, w + 1), "08:00", "the next one")
	eq(K.clock(c, w + 5), "00:00", "midnight")
	-- six windows a day, starting at local 00:00
	local midnight = t - 4 * 3600
	eq(K.clock(c, K.window(c, midnight, off)), "00:00", "midnight window")
	eq(K.window(c, midnight + 86400, off) - K.window(c, midnight, off), 6, "six windows a day")
	-- UTC+0: the same instant is window start 04:00 UTC only for the UTC clock
	c.refresh.utcOffsetHours = 0
	eq(K.clock(c, K.window(c, t, 0)), "04:00", "07:00 UTC lies in the 04:00 UTC window")
	-- the server's own zone: every window starts on a local 4-hour mark
	c.refresh.utcOffsetHours = nil
	for k = 0, 11 do
		local at = 1791702000 + k * 7919
		local o = K.offset(c, at)
		local start = K.windowStart(c, K.window(c, at, o), o)
		local d = os.date("*t", start)
		check(d.hour % 4 == 0 and d.min == 0 and d.sec == 0, "local window start on a 4-hour mark " .. os.date("%H:%M:%S", start))
		check(start <= at and at < start + 4 * 3600, "the instant lies in its window " .. k)
	end
end

-- ---------------------------------------------------------------- prices
eq(K.interp(cfg.price.curve, 1), 1500, "price at item level 1")
eq(K.interp(cfg.price.curve, 36), 56000, "price at 36")
eq(K.interp(cfg.price.curve, 200), 1800000, "flat past the end")
eq(K.price(cfg, 36, "armor"), 64400, "armour x1.15")
eq(K.price(cfg, 36, "weapon"), 72800, "weapon x1.3")
eq(K.price(cfg, 36, "boots"), 50400, "boots x0.9")
eq(K.price(cfg, 90, "helmet"), 850000, "helmet at 90")
for l = 2, 150 do
	check(K.price(cfg, l, "helmet") >= K.price(cfg, l - 1, "helmet"), "the price rises with the item level " .. l)
end
for _, s in ipairs(cfg.stock.order) do
	eq(K.price(cfg, 50, s) % 100, 0, "rounded to 100 gold " .. s)
end
-- a gold sink, but cheaper than nothing: an armour piece costs between minShare and maxShare of an hour of hunting
local worst, best = 1, 0
for level = 8, 1500 do
	local share = K.shareAt(cfg, level, gate)
	worst, best = math.min(worst, share), math.max(best, share)
	check(share >= cfg.balance.minShare and share <= cfg.balance.maxShare,
		string.format("level %d: a piece is %.1f%% of an hour of hunting", level, share * 100))
end
do
	local share, g = K.shareAt(cfg, 1000, gate)
	check(share > 0.15 and share < 0.25, string.format("level 1000 (gate %d): %.1f%% of 9.5M/h", g, share * 100))
	-- a whole stock of 14 at level 1000: about two to four hours of hunting
	local whole = 14 * K.price(cfg, g, "armor") / K.huntIncome(cfg, 1000)
	check(whole > 2 and whole < 4.5, string.format("a whole stock at 1000 costs %.1f hours of hunting", whole))
end
-- early refresh: half an armour piece, doubled each time, three a window
do
	local g = gate(1000)
	local p1 = K.rerollPrice(cfg, g, 0)
	eq(p1, math.floor(K.price(cfg, g, "armor") * 0.5 / 100) * 100, "first early refresh")
	eq(K.rerollPrice(cfg, g, 1), 2 * p1, "second doubles")
	eq(K.rerollPrice(cfg, g, 2), 4 * p1, "third doubles again")
	eq(K.rerollPrice(cfg, g, 3), nil, "no fourth")
end

-- ---------------------------------------------------------------- base types and the stock
local VOC = {} -- id -> set of line keys that may use it (a stand-in for movements.xml in the core tests)
local function only(line, ...)
	for _, id in ipairs({...}) do
		VOC[id] = VOC[id] or {}
		VOC[id][line] = true
	end
end
only("warrior", 29883, 29885, 29887, 27458, 27462, 27460, 29882, 29878, 29879, 29880, 29881, 29889, 29890, 29559, 29560, 29561,
	29562, 29563)
only("ranger", 29874, 29869, 29870, 29871, 29872, 29876, 29877, 27471)
-- the quivers: the bow classes only (patch_base_archery.py writes their movements.xml entries so)
for _, e in ipairs(cfg.pool.quiver) do
	only("ranger", e[1])
end
only("mystic", 29866, 27476, 27479, 29865, 29861, 29862, 29863, 29864, 29867, 29868, 29572, 29573, 29574, 29575, 29576)
local function canUseAs(line)
	return function(id)
		return VOC[id] == nil or VOC[id][line] == true
	end
end
local function inSet(set, v)
	for _, x in ipairs(set) do
		if x == v then
			return true
		end
	end
	return false
end

do
	local c = K.candidates(cfg, "armor", 1000, canUseAs("warrior"))
	eq(#c, cfg.base.choices, "four armour choices")
	eq(c[1].id, 29879, "the best armour a level 1000 warrior can use first")
	for _, e in ipairs(c) do
		check(not inSet({29862, 29574}, e.id), "no mystic armour for a warrior " .. e.id)
	end
	local low = K.candidates(cfg, "armor", 8, canUseAs("warrior"))
	for _, e in ipairs(low) do
		check(e.lv <= 8, "nothing above level 8 for level 8 " .. e.id)
	end
	eq(#K.candidates(cfg, "ring", 50, canUseAs("warrior")), 0, "no ring under level 100")
	-- quivers: in the pool for a ranger, never for a warrior
	eq(#K.candidates(cfg, "quiver", 1000, canUseAs("warrior")), 0, "no quiver for a warrior")
	local q = K.candidates(cfg, "quiver", 1000, canUseAs("ranger"))
	eq(#q, cfg.base.choices, "four quiver choices for a level 1000 ranger")
	eq(q[1].id, 29873, "the best quiver first")
	for _, e in ipairs(cfg.pool.quiver) do
		check(ChaosArcheryConfigForTest.quivers[e[1]] ~= nil, "pool quiver " .. e[1] .. " is a quiver base")
		eq(e[2], ChaosArcheryConfigForTest.quivers[e[1]][1], "pool level of quiver " .. e[1] .. " is its base level")
	end
	eq(#K.candidates(cfg, "quiver", 10, canUseAs("ranger")), 0, "no quiver under level 20")
	local quivers, pieces = 0, 0
	for window = 1, 20 do
		for _, e in ipairs(K.stock(cfg, {guid = 9, window = window, rerolls = 0, level = 600, gate = gate(600),
				canUse = canUseAs("ranger")})) do
			pieces = pieces + 1
			if e.slot == "quiver" then
				quivers = quivers + 1
				check(e.lv <= 600, "a quiver of the ranger's level")
			end
		end
	end
	-- one slot weight of 16: about 6% of the pieces
	check(quivers > 0 and quivers < pieces / 5, "a ranger's stocks hold some quivers: " .. quivers .. " of " .. pieces)
end

local ctx = {guid = 4242, window = 123456, rerolls = 0, level = 1000, gate = gate(1000), canUse = canUseAs("warrior")}
local s1 = K.stock(cfg, ctx)
local s2 = K.stock(cfg, ctx)
eq(#s1, cfg.stock.size, "a full stock")
local function same(a, b)
	if #a ~= #b then
		return false
	end
	for i = 1, #a do
		for _, f in ipairs({"i", "id", "slot", "ilvl", "price"}) do
			if a[i][f] ~= b[i][f] then
				return false
			end
		end
	end
	return true
end
check(same(s1, s2), "the same character and window: the same stock")
local function differs(field, value)
	local c = {}
	for k, v in pairs(ctx) do
		c[k] = v
	end
	c[field] = value
	return not same(s1, K.stock(cfg, c))
end
check(differs("window", 123457), "another window: another stock")
check(differs("guid", 4243), "another character: another stock")
check(differs("rerolls", 1), "an early refresh: another stock")
local slots, order = {}, {}
for i, so in ipairs(cfg.stock.order) do
	order[so] = i
end
for i, e in ipairs(s1) do
	eq(e.i, i, "index " .. i)
	check(e.ilvl <= ctx.gate and e.ilvl >= ctx.gate - cfg.itemLevel.spread, "item level within the gate " .. e.ilvl)
	check(e.lv <= 1000, "base level <= character level")
	check(canUseAs("warrior")(e.id), "the warrior can use " .. e.id)
	eq(e.price, K.price(cfg, e.ilvl, e.slot), "price of " .. e.id)
	slots[e.slot] = (slots[e.slot] or 0) + 1
	if i > 1 then
		check(order[s1[i - 1].slot] <= order[e.slot], "sorted by slot")
	end
end
check((slots.weapon or 0) >= 1, "at least one weapon in a stock")
-- determinism over many windows; the item level never above the gate at any level
for level = 1, 1500, 37 do
	local g = gate(level)
	local st = K.stock(cfg, {guid = 9, window = level, rerolls = 0, level = level, gate = g, canUse = canUseAs("mystic")})
	for _, e in ipairs(st) do
		check(e.ilvl <= g and e.ilvl >= 1, "level " .. level .. ": item level " .. e.ilvl .. " <= gate " .. g)
		check(e.lv <= level, "level " .. level .. ": base " .. e.id .. " of level " .. e.lv)
	end
	check(#st > 0, "level " .. level .. " gets a stock")
end
-- a character that can use nothing gets nothing (and no endless loop)
eq(#K.stock(cfg, {guid = 1, window = 1, rerolls = 0, level = 50, gate = 20, canUse = function() return false end}), 0, "nothing usable")
-- the same numbers under LuaJIT and Lua 5.3 (fixed values of the generator and a stock)
local r = K.rng(K.seed(cfg, 4242, 123456, 0))
eq(K.seed(cfg, 4242, 123456, 0), (7717 * 1000003 + 4242 * 7919 + 123456 * 31) % 2147483646 + 1, "seed formula")
local firsts = {r(1, 1000), r(1, 1000), r(1, 1000)}
local r2 = K.rng(K.seed(cfg, 4242, 123456, 0))
eq(r2(1, 1000), firsts[1], "generator repeats")
local fixed = K.stock(cfg, {guid = 7, window = 100000, rerolls = 0, level = 300, gate = gate(300), canUse = canUseAs("warrior")})
local sig = {}
for _, e in ipairs(fixed) do
	sig[#sig + 1] = e.id .. "@" .. e.ilvl
end
-- recorded once under LuaJIT and Lua 5.3; must not change between interpreters or runs (it would move every player's
-- stock). A change of the pool, the slot weights or the generator changes it: then record the new one.
eq(table.concat(sig, ","), "27197@67,27197@65,27198@67,28111@61,22424@62,27653@61,29471@64,27227@64,28113@65,28100@63," ..
	"27692@61,28109@67,28115@67,27211@64", "the stock of a fixed character and window")

-- ---------------------------------------------------------------- the equipment sets of pair 28
do
	local G = dofile("data/lib/chaos_gear_sets.lua")
	eq(G.PAIR28, true, "sets: the pair switch is on as shipped")
	check(cfg.sets and cfg.sets.enabled, "sets: on in the config as shipped")
	eq(cfg.sets.share, 20, "sets: 20% of the picks")
	for key in pairs(G.items.sets) do
		check(type(cfg.sets.weight[key]) == "number" and cfg.sets.weight[key] > 0, "sets: a weight for " .. key)
	end
	for key in pairs(cfg.sets.weight) do
		check(G.items.sets[key] ~= nil, "sets: the weight of " .. key .. " names a real set")
	end
	-- the config check
	local bad = dofile("data/scripts/chaos/gamble_config.lua")
	bad.sets.share = 101
	bad.sets.weight.gildcrown = 1.5
	check(#K.validate(bad) >= 2, "sets: a broken sets block is reported")

	-- the entries: every piece, in the slot of its kind, inside its set's band, none while a switch is off
	local entries = K.setEntries(cfg, G)
	eq(#entries, 643, "sets: all 643 pieces are on offer")
	local slots = {}
	for _, e in ipairs(entries) do
		local piece = G.piece(e.id)
		local band = G.items.sets[e.set].band
		check(piece ~= nil and piece.set == e.set and piece.level == e.lv, "sets: the entry is the piece " .. e.id)
		check(e.lv >= band[1] and e.lv <= band[2], "sets: piece " .. e.id .. " level " .. e.lv .. " is inside the band of " .. e.set)
		check(K.SET_SLOT[piece.kind] == e.slot, "sets: slot of " .. piece.kind)
		check(cfg.stock.slots[e.slot] ~= nil and e.slot ~= "quiver", "sets: a slot of the stock " .. e.slot)
		slots[e.slot] = (slots[e.slot] or 0) + 1
	end
	for _, slot in ipairs({"weapon", "shield", "helmet", "armor", "legs", "boots", "amulet", "ring"}) do
		check((slots[slot] or 0) > 0, "sets: pieces for " .. slot)
	end
	eq(slots.quiver, nil, "sets: no quiver piece")
	G.PAIR28 = false
	eq(#K.setEntries(cfg, G), 0, "sets: none while the pair switch is off")
	G.PAIR28 = true
	cfg.sets.enabled = false
	eq(#K.setEntries(cfg, G), 0, "sets: none while the config is off")
	cfg.sets.enabled = true
	eq(#K.setEntries(cfg, nil), 0, "sets: none without the library")
	local half = cfg.sets.weight.gildcrown
	cfg.sets.weight.gildcrown = 0
	eq(#K.setEntries(cfg, G), 643 - 64, "sets: weight 0 leaves a set out")
	cfg.sets.weight.gildcrown = half

	-- candidates: the character's level and class, the highest levels first
	local function classOf(name)
		return function(id)
			local piece = G.piece(id)
			if not piece or #piece.classes == 0 then
				return true
			end
			for _, c in ipairs(piece.classes) do
				if c == name then
					return true
				end
			end
			return false
		end
	end
	local c = K.setCandidates(cfg, "armor", 1000, classOf("Warrior"), entries)
	eq(#c, cfg.sets.choices, "sets: four armour choices at 1000")
	for i, e in ipairs(c) do
		check(e.lv <= 1000 and G.piece(e.id).fit == "H", "sets: heavy armour of the level for a Warrior " .. e.id)
		check(i == 1 or c[i - 1].lv >= e.lv, "sets: the best first")
	end
	for _, level in ipairs({8, 40, 120, 300, 450, 800, 1250, 2000}) do
		for _, slot in ipairs(cfg.stock.order) do
			for _, e in ipairs(K.setCandidates(cfg, slot, level, classOf("Mystic"), entries)) do
				check(e.lv <= level, "sets: level " .. level .. " never gets " .. e.id .. " of level " .. e.lv)
				check(classOf("Mystic")(e.id), "sets: a Mystic can wear " .. e.id)
			end
		end
	end
	eq(#K.setCandidates(cfg, "armor", 7, classOf("Warrior"), entries), 0, "sets: nothing under level 8")
	eq(#K.setCandidates(cfg, "quiver", 2000, classOf("Ranger"), entries), 0, "sets: no quiver")

	-- stocks: set pieces come in at about the share, never above the level, none when switched off
	local function run(ctxSets, share, level, line)
		local n, sets, total = 0, 0, 0
		local c2 = dofile("data/scripts/chaos/gamble_config.lua")
		c2.sets.share = share
		for window = 1, 300 do
			for _, e in ipairs(K.stock(c2, {guid = 31, window = window, rerolls = 0, level = level, gate = gate(level),
					sets = ctxSets, canUse = line})) do
				total = total + 1
				if G.piece(e.id) then
					sets = sets + 1
					check(e.lv <= level, "sets: stock piece " .. e.id .. " of level " .. e.lv .. " for level " .. level)
					check(e.lv >= G.items.sets[G.piece(e.id).set].band[1], "sets: inside the band")
					check(line(e.id), "sets: usable by the class " .. e.id)
				end
			end
		end
		return sets, total
	end
	local withSets, total = run(entries, 20, 1000, classOf("Warrior"))
	check(withSets / total > 0.12 and withSets / total < 0.27,
		string.format("sets: about 20%% of the pieces are set pieces (%.1f%%)", 100 * withSets / total))
	local none = run(entries, 0, 1000, classOf("Warrior"))
	eq(none, 0, "sets: share 0 offers none")
	local nothing = run(nil, 20, 1000, classOf("Warrior"))
	eq(nothing, 0, "sets: no entries (a switch off) offers none")
	local low = run(entries, 100, 7, classOf("Warrior"))
	eq(low, 0, "sets: a level 7 character is offered none")
	local all = run(entries, 100, 400, classOf("Ranger"))
	check(all > 0, "sets: a level 400 ranger is offered some")
	-- the stock is the same for the same character and window, with and without the engine asking twice
	local ctx = {guid = 5, window = 99, rerolls = 0, level = 600, gate = gate(600), sets = entries, canUse = classOf("Thief")}
	local a, b = K.stock(cfg, ctx), K.stock(cfg, ctx)
	local sa, sb = {}, {}
	for i = 1, #a do
		sa[i], sb[i] = a[i].id .. "@" .. a[i].ilvl, b[i].id .. "@" .. b[i].ilvl
	end
	eq(table.concat(sa, ","), table.concat(sb, ","), "sets: deterministic")
	-- the weights: a set with weight 0 never shows, the only one left always does when a set piece is picked
	local c3 = dofile("data/scripts/chaos/gamble_config.lua")
	c3.sets.share = 100
	for key in pairs(c3.sets.weight) do
		c3.sets.weight[key] = key == "wyrmscale" and 10 or 0
	end
	local only = K.setEntries(c3, G)
	eq(#only, 64, "sets: one set left")
	for window = 1, 40 do
		for _, e in ipairs(K.stock(c3, {guid = 8, window = window, rerolls = 0, level = 220, gate = gate(220), sets = only,
				canUse = classOf("Warrior")})) do
			local piece = G.piece(e.id)
			check(piece == nil or piece.set == "wyrmscale", "sets: only wyrmscale at weight 0 for the others")
		end
	end
	-- prices follow the item level and slot like any piece
	local e1 = K.stock(c3, {guid = 8, window = 1, rerolls = 0, level = 220, gate = gate(220), sets = only, canUse = classOf("Warrior")})[1]
	eq(e1.price, K.price(c3, e1.ilvl, e1.slot), "sets: priced by item level and slot")
end

-- ---------------------------------------------------------------- sold slots
local mask = 0
check(not K.isSold(mask, 1), "nothing sold")
mask = K.markSold(mask, 3)
check(K.isSold(mask, 3) and not K.isSold(mask, 2) and not K.isSold(mask, 4), "slot 3 sold")
eq(K.markSold(mask, 3), mask, "marking twice changes nothing")
mask = K.markSold(mask, 14)
eq(mask, 4 + 8192, "bits 2 and 13")
eq(K.soldCount(mask, 14), 2, "two sold")
mask = K.unmarkSold(mask, 3)
eq(mask, 8192, "unmarked")
eq(K.isSold(-1, 1), false, "an unset storage (-1) is nothing sold")

-- ---------------------------------------------------------------- odds
MAX_LOOTCHANCE = 100000
Chaos = Chaos or {}
EventCallback = setmetatable({register = function() end}, {__newindex = rawset})
ItemType = function(id)
	return {isStackable = function() return false end, getName = function() return "item " .. id end, getId = function() return id end}
end
dofile("data/scripts/chaos/loot.lua")
local L, LC = ChaosLoot, ChaosLootConfig
local odds = K.odds(cfg, LC.gear) -- by place: 0 none, 1 Common .. 6 Divine
local total = 0
for v = 0, 6 do
	total = total + odds[v]
end
check(math.abs(total - 1) < 1e-9, "odds sum to 1 (" .. total .. ")")
eq(odds[0], 0, "never plain")
for v = ChaosRarity.rank(cfg.odds.maxRarity) + 1, 6 do
	eq(odds[v], 0, "nothing above the cap " .. v)
end
local leg = K.atLeast(odds, 5) -- Legendary or better
local normalDrop = K.odds({odds = {draws = 1, floor = 0, tier = "normal", find = 1, maxRarity = 10}}, LC.gear)
local magicDrop = K.odds({odds = {draws = 1, floor = 0, tier = "magic", find = 1, maxRarity = 10}}, LC.gear)
-- Legendary stays as rare as on drops: no more often than on a magic monster's gear drop
check(leg <= K.atLeast(magicDrop, 5) + 1e-12, string.format("Legendary or better %.2f%% <= a magic drop's %.2f%%", leg * 100,
	K.atLeast(magicDrop, 5) * 100))
check(leg < 0.15, string.format("Legendary or better stays rare: %.2f%%", leg * 100))
check(K.atLeast(odds, 6) < 0.03, string.format("Divine %.2f%%", K.atLeast(odds, 6) * 100))
-- the drops' own numbers (for server/README.md)
print(string.format("drops: normal plain %.1f%%, Legendary+ %.2f%%; magic plain %.1f%%, Legendary+ %.2f%%",
	normalDrop[0] * 100, K.atLeast(normalDrop, 5) * 100, magicDrop[0] * 100, K.atLeast(magicDrop, 5) * 100))
-- better than a gear drop of a normal and of a magic monster at every rarity
for _, tier in ipairs({"normal", "magic"}) do
	local drop = K.odds({odds = {draws = 1, floor = 0, tier = tier, find = 1, maxRarity = 10}}, LC.gear)
	for v = 1, ChaosRarity.rank(cfg.odds.maxRarity) do
		check(K.atLeast(odds, v) >= K.atLeast(drop, v) - 1e-12,
			string.format("rarity place %d+: gamble %.2f%% >= %s drop %.2f%%", v, K.atLeast(odds, v) * 100, tier, K.atLeast(drop, v) * 100))
	end
end
-- the real roll (loot.lua's own functions) agrees with the table
do
	local rand = K.rng(20261011)
	L.setRandom(function(a, b) return rand(a, b) end)
	local n, hits = 200000, {}
	for _ = 1, n do
		local v = ChaosRarity.rank(K.rollRarity(cfg, L)) -- the roll gives a stored id
		hits[v] = (hits[v] or 0) + 1
	end
	L.setRandom(nil)
	for v = 0, 6 do
		local seen = (hits[v] or 0) / n
		local want = odds[v]
		local tol = 4 * math.sqrt(math.max(want * (1 - want), 1e-9) / n) + 1e-4
		check(math.abs(seen - want) <= tol, string.format("rarity place %d: rolled %.4f, table %.4f", v, seen, want))
	end
	eq(hits[0], nil, "the real roll never gives a plain piece")
end
print(string.format("odds: Common %.1f%%, Uncommon %.1f%%, Magic %.1f%%, Rare %.1f%%, Legendary+ %.2f%%, Divine %.2f%%",
	odds[1] * 100, odds[2] * 100, odds[3] * 100, odds[4] * 100, leg * 100, odds[6] * 100))

-- ---------------------------------------------------------------- purchase refusals (in order)
do
	local st = {{i = 1, id = 100, price = 5000}, {i = 2, id = 101, price = 9000}}
	local base = {enabled = true, stock = st, mask = 0, slot = 1, window = 7, want = {w = 7, id = 100}, money = 10000, near = true}
	local function with(k, v)
		local s = {}
		for a, b in pairs(base) do
			s[a] = b
		end
		s[k] = v
		return K.checkBuy(cfg, s)
	end
	local ok, text, e = K.checkBuy(cfg, base)
	check(ok and e.id == 100, "a good purchase")
	ok, text = with("enabled", false)
	check(not ok and text:find("packed up", 1, true), "disabled")
	ok, text = with("busy", true)
	check(not ok and text:find("One crate", 1, true), "busy")
	ok, text = with("near", false)
	check(not ok and text:find("in person", 1, true), "away from the Gambler")
	ok, text = with("slot", 9)
	check(not ok and text:find("not on offer", 1, true), "no such slot")
	ok, text = with("want", {w = 6, id = 100})
	check(not ok and text:find("changed", 1, true), "an old window")
	ok, text = with("want", {w = 7, id = 101})
	check(not ok and text:find("changed", 1, true), "another piece in that slot")
	ok, text = with("mask", 1)
	check(not ok and text:find("already sold", 1, true), "sold")
	ok, text = with("money", 4999)
	check(not ok and text:find("5,000 gold", 1, true), "too little gold")
end

-- ---------------------------------------------------------------- engine (gamble.lua) against a mocked engine
MESSAGE_STATUS_SMALL, MESSAGE_EVENT_ADVANCE, MESSAGE_INFO_DESCR, MESSAGE_STATUS_DEFAULT = 1, 2, 3, 4
TILESTATE_TELEPORT, TILESTATE_FLOORCHANGE, CONST_PROP_BLOCKSOLID, RETURNVALUE_NOERROR = 2, 4, 1, 0

local function deep(t)
	if type(t) ~= "table" then
		return t
	end
	local o = {}
	for k, v in pairs(t) do
		o[k] = deep(v)
	end
	return o
end
local registry = {}
json = {
	encode = function(t) registry[#registry + 1] = deep(t); return "J" .. #registry end,
	decode = function(s) return deep(registry[tonumber(tostring(s):match("^J(%d+)$") or -1)]) end
}
local events, globalEvents = {}, {}
CreatureEvent = function(name)
	local e = {register = function() end, type = function() end}
	events[name] = e
	return e
end
GlobalEvent = function(name)
	local e = {register = function() end}
	globalEvents[name] = e
	return e
end
TalkAction = function() return {separator = function() end, register = function() end} end
local timers = {}
addEvent = function(fn, ms) timers[#timers + 1] = fn end

local NAMES = {}
ItemType = function(id)
	return {getId = function() return id end, getName = function() return NAMES[id] or ("item " .. id) end,
		getClientId = function() return id - 20000 end, isStackable = function() return false end,
		getCharges = function() return id == 26807 and 50 or 0 end, getDuration = function() return 0 end}
end
Vocation = function(id)
	return {getName = function() return ({[4] = "Warrior", [1] = "Mystic"})[id] or "None" end}
end
-- the npc and the tiles around the temple
local npcs = {}
local tiles = {}
Position = function(x, y, z) return {x = x, y = y, z = z} end
Tile = function(pos)
	local k = pos.x .. ":" .. pos.y .. ":" .. pos.z
	local t = tiles[k]
	if not t then
		t = {blocked = false, creature = nil}
		function t:getGround() return true end
		function t:hasProperty() return self.blocked end
		function t:getTopCreature() return self.creature end
		function t:hasFlag() return false end
		tiles[k] = t
	end
	return t
end
Town = function(id)
	if id ~= 2 then -- the Gambler stands in the main city only (gamble_config.lua towns)
		return nil
	end
	return {getTemplePosition = function() return {x = 1000, y = 1000, z = 7} end, getName = function() return "Ember Hold" end}
end
local created = {}
Game = {
	getSpectators = function(pos, multi, onlyPlayers, a, b, c, d)
		local out = {}
		for _, n in ipairs(npcs) do
			if not onlyPlayers and math.abs(n.pos.x - pos.x) <= a and math.abs(n.pos.y - pos.y) <= c and n.pos.z == pos.z then
				out[#out + 1] = n
			end
		end
		return out
	end,
	createNpc = function(name, pos)
		local n = {name = name, pos = pos}
		function n:isNpc() return true end
		function n:getName() return self.name end
		npcs[#npcs + 1] = n
		created[#created + 1] = n
		return n
	end,
	createItem = function(id) return {id = id, custom = {}} end
}
Player = function(x) return type(x) == "table" and x or nil end

Chaos = nil -- the loot part above made a bare one
dofile("data/scripts/chaos/chaos_constants.lua")
local sent = {}
Chaos.send = function(player, op, action, data) sent[#sent + 1] = {op = op, action = action, data = deep(data)} end
Chaos.sendChunked = function(player, op, text)
	local m = json.decode(text)
	sent[#sent + 1] = {op = op, action = m.action, data = m.data}
end
local saveOk = true
local saves = 0
local limited = false
ChaosRateLimit = {allow = function() return not limited end}
local createdItems = {}
ChaosCrafting = {createItem = function(id, rarity, level)
	local it = {id = id, rarity = rarity, level = level, custom = {}}
	createdItems[#createdItems + 1] = it
	return it
end}
ChaosItemMods = M

local function newPlayer(guid, level, vocId)
	local p = {guid = guid, id = 0x10000000 + guid, level = level, voc = vocId, pos = {x = 1000, y = 1000, z = 7}, storage = {},
		money = 0, bank = 0, items = {}, inbox = {}, messages = {}}
	function p:getId() return self.id end
	function p:getGuid() return self.guid end
	function p:getName() return "Gambler" .. self.guid end
	function p:getLevel() return self.level end
	function p:getVocation()
		local me = self
		return {getId = function() return me.voc end, getName = function() return Vocation(me.voc):getName() end}
	end
	function p:getPosition() return self.pos end
	function p:getStorageValue(k) return self.storage[k] or -1 end
	function p:setStorageValue(k, v) self.storage[k] = v end
	function p:getTotalMoney() return self.money + self.bank end
	function p:removeTotalMoney(n)
		if self.money + self.bank < n then
			return false
		end
		local fromHand = math.min(self.money, n)
		self.money = self.money - fromHand
		self.bank = self.bank - (n - fromHand)
		return true
	end
	function p:getBankBalance() return self.bank end
	function p:setBankBalance(v) self.bank = v end
	function p:getMoney() return self.money end
	function p:removeMoney(n) if self.money < n then return false end self.money = self.money - n return true end
	function p:addItemEx(item)
		if self.full then
			return 1
		end
		self.items[#self.items + 1] = item
		return RETURNVALUE_NOERROR
	end
	function p:getInbox()
		local me = self
		return {addItemEx = function(_, item) me.inbox[#me.inbox + 1] = item end}
	end
	function p:save()
		saves = saves + 1
		return saveOk
	end
	function p:sendTextMessage(t, text) self.messages[#self.messages + 1] = text end
	function p:registerEvent() end
	function p:getGroup() return {getId = function() return 1 end} end
	return p
end

dofile("data/scripts/chaos/gamble.lua")
local P = ChaosGamble
eq(ChaosOpcodes.gamble, 199, "opcode constant")
eq(Chaos.storage.gamble, 7101900, "storage constant")
-- the opcode collision check (server/README.md): the reference server's, the reference client's own, every Chaos one
for _, taken in ipairs({1, 67, 73, 89, 91, 92, 99, 106, 107, 136, 181, 201, 202, 140, 144, 145, 146, 210, 212, 213, 230, 246}) do
	check(taken ~= ChaosOpcodes.gamble, "opcode free of " .. taken)
end
for name, v in pairs(ChaosOpcodes) do
	check(name == "gamble" or v ~= ChaosOpcodes.gamble, "opcode not shared with " .. name)
end
-- the storage block is free: no other Chaos.storage value in 7101900 - 7101909
for name, v in pairs(Chaos.storage) do
	if name ~= "gamble" and type(v) == "number" then
		check(v < 7101900 or v > 7101909, "storage block not shared with " .. name)
	end
end

-- movements.xml / weapons.xml rules
local MOVEMENTS = [[
<movements>
	<movevent event="Equip" itemid="29879" slot="armor" level="1000" function="onEquipItem">
		<vocation name="Warrior" />
		<vocation name="Juggernaut" showInDescription="0" />
	</movevent>
	<movevent event="DeEquip" itemid="29879" slot="armor" function="onDeEquipItem" />
	<movevent event="Equip" itemid="29862" slot="armor" level="1000" function="onEquipItem">
		<vocation name="Mystic" />
	</movevent>
	<movevent event="Equip" fromid="2463" toid="2464" slot="armor" function="onEquipItem" />
	<movevent event="Equip" itemid="29878" slot="head" level="1000" function="onEquipItem"><vocation name="Warrior" /></movevent>
	<movevent event="StepIn" itemid="1387" function="onStepIn" />
</movements>]]
local WEAPONS = [[
<weapons>
	<melee id="29883" level="1000" unproperly="1"> <!-- a blade -->
		<vocation name="Warrior" />
	</melee>
	<wand id="29866" level="1000" mana="20" min="1" max="2" type="fire">
		<vocation name="Mystic" />
	</wand>
	<distance id="2456" />
</weapons>]]
P.ruleTable = P.parseRules(MOVEMENTS, WEAPONS)
local rules = P.ruleTable
eq(rules[29879].level, 1000, "armour level")
check(rules[29879].vocs.warrior and rules[29879].vocs.juggernaut and not rules[29879].vocs.mystic, "armour vocations")
eq(rules[2464].level, 0, "a range without level")
eq(rules[2464].vocs, nil, "a range open to everyone")
eq(rules[29883].level, 1000, "weapon level from weapons.xml")
check(rules[29866].vocs.mystic, "wand vocation")
eq(rules[1387], nil, "non-equip events ignored")
ChaosLoot.isGearId = function(id) return id ~= 2398 end -- one id that is no gear
local warriorUse = P.canUseFor(1000, "Warrior")
check(warriorUse(29879), "a level 1000 warrior wears the plate")
check(not warriorUse(29862), "not the mystic mantle")
check(not P.canUseFor(999, "Warrior")(29879), "not below its level")
check(warriorUse(2463), "plate armor for everyone")
check(not warriorUse(26807), "an item with charges is never offered")
check(not warriorUse(2398), "a non-gear id is never offered")
check(P.canUseFor(1000, "Mystic")(29866), "the mystic's wand")

-- the NPC next to the main temple
globalEvents.ChaosGambleStartup.onStartup()
eq(#timers, 1, "placement scheduled")
Tile({x = 995, y = 998, z = 7}).blocked = true -- the first offset is a wall
timers[1]()
eq(#created, 1, "one Gambler placed")
eq(created[1].name, "Mordecai Ashwager", "his name")
eq(created[1].pos.x, 1005, "on the second offset")
eq(created[1].pos.y, 998, "next to the temple")
eq(P.placeNpcs(), 1, "placing again finds him")
eq(#created, 1, "and makes no second one")

-- a level 1000 warrior next to him
local now0 = os.time()
local tz = K.offset(cfg, now0)
-- start 10 minutes into a window, so a test run near the mark does not cross it
P.clockShift = K.windowStart(cfg, K.window(cfg, now0, tz) + 1, tz) + 600 - now0
local hero = newPlayer(11, 1000, 4)
hero.pos = {x = 1004, y = 998, z = 7}
hero.money = 1000
hero.bank = 50000000
events.ChaosGambleLogin.onLogin(hero)
local function op(player, action, data)
	sent = {}
	events.ChaosGambleExtended.onExtendedOpcode(player, 199, json.encode({action = action, data = data}))
	local out = {}
	for _, s in ipairs(sent) do
		out[s.action] = s.data
	end
	return out
end
local st = op(hero, "open").state
check(st ~= nil, "state sent")
eq(#st.items, cfg.stock.size, "fourteen pieces")
eq(st.near, true, "at the Gambler")
eq(st.level, 1000, "level snapshot")
eq(st.gate, gate(1000), "the gate")
check(st.left > 0 and st.left <= 4 * 3600, "time to the refresh " .. st.left)
eq(st.reroll, K.rerollPrice(cfg, gate(1000), 0), "early refresh price")
check(#st.odds > 0 and st.odds[1].n == "Common", "odds listed by name")
local window = st.w
for _, it in ipairs(st.items) do
	check(it.c > 0 and it.n ~= "" and it.l > 0 and it.p > 0 and it.sn ~= nil, "a piece shows look, name, level, price, slot")
	check(it.r == nil and it.rarity == nil, "no rarity shown")
	check(warriorUse(it.id), "the warrior can use " .. it.id)
end
eq(hero.storage[7101900], window, "window stored")
eq(hero.storage[7101901], 1000, "level stored")
eq(hero.storage[7101902], 4, "vocation stored")

-- buy piece 2
local piece = st.items[2]
local goldBefore = hero.money + hero.bank
saves = 0
local res = op(hero, "buy", {i = 2, w = window, id = piece.id})
check(res.result and res.result.ok, "bought: " .. tostring(res.result and res.result.text))
eq(hero.money + hero.bank, goldBefore - piece.p, "the price taken")
eq(hero.money, 0, "the gold in the backpack first")
check(K.isSold(hero.storage[7101903], 2), "slot 2 marked sold")
eq(saves, 2, "saved before the roll and after the delivery")
eq(#hero.items, 1, "the piece in the backpack")
local got = hero.items[1]
eq(got.id, piece.id, "the piece bought")
eq(got.level, piece.l, "at its item level")
check(got.rarity >= cfg.odds.floor and got.rarity <= cfg.odds.maxRarity, "a rarity " .. got.rarity)
eq(res.result.reveal.r, got.rarity, "the reveal names the rarity")
has(res.result.text, "The seal breaks", "reveal text")
has(res.result.reveal.rn, "", "rarity name")
check(res.state.items[2].sold == true, "the window shows it sold")
eq(res.state.last.r, got.rarity, "the last reveal in the window")

-- the same slot again: refused, nothing taken
local gold2 = hero.money + hero.bank
res = op(hero, "buy", {i = 2, w = window, id = piece.id})
check(res.result and not res.result.ok, "a sold slot is refused")
has(res.result.text, "already sold", "sold text")
eq(hero.money + hero.bank, gold2, "no gold taken")
eq(#hero.items, 1, "no second piece")

-- an old window or another piece: refused
res = op(hero, "buy", {i = 3, w = window - 1, id = st.items[3].id})
has(res.result.text, "changed", "old window refused")
local other
for _, it in ipairs(st.items) do
	if it.id ~= st.items[3].id then
		other = it.id
	end
end
res = op(hero, "buy", {i = 3, w = window, id = other})
has(res.result.text, "changed", "a wrong piece refused")

-- too little gold
local poor = newPlayer(12, 1000, 4)
poor.pos = hero.pos
poor.money = 10
events.ChaosGambleLogin.onLogin(poor)
local pst = op(poor, "open").state
res = op(poor, "buy", {i = 1, w = pst.w, id = pst.items[1].id})
check(not res.result.ok, "too poor")
has(res.result.text, "You need", "the gold text")
eq(poor.money, 10, "nothing taken")
check(not K.isSold(poor.storage[7101903], 1), "not marked")

-- a failed save: the gold back, nothing rolled, the slot open
local nItems = #createdItems
local gold3 = hero.money + hero.bank
saveOk = false
res = op(hero, "buy", {i = 3, w = window, id = st.items[3].id})
saveOk = true
check(not res.result.ok, "a failed save refuses")
has(res.result.text, "could not be written", "save text")
eq(hero.money + hero.bank, gold3, "all gold back")
eq(#createdItems, nItems, "no item rolled")
check(not K.isSold(hero.storage[7101903], 3), "slot 3 still open")

-- two requests at once: the second is refused while the first runs
P.busy[hero:getGuid()] = true
res = op(hero, "buy", {i = 3, w = window, id = st.items[3].id})
P.busy[hero:getGuid()] = nil
has(res.result.text, "One crate at a time", "busy refused")
eq(#createdItems, nItems, "nothing made")
-- a save that buys again from inside (a re-entrant request) cannot buy the same slot twice
local inner
local origSave = hero.save
hero.save = function(self)
	if not inner then
		inner = op(hero, "buy", {i = 3, w = window, id = st.items[3].id})
	end
	return origSave(self)
end
res = op(hero, "buy", {i = 3, w = window, id = st.items[3].id})
hero.save = origSave
check(inner and inner.result and not inner.result.ok, "the inner request is refused")
eq(#createdItems, nItems + 1, "one piece made")

-- full backpack: the inbox
hero.full = true
res = op(hero, "buy", {i = 4, w = window, id = st.items[4].id})
hero.full = false
check(res.result.ok, "bought with a full backpack")
eq(#hero.inbox, 1, "into the inbox")
has(res.result.text, "inbox", "the inbox text")

-- away from the Gambler: the window opens, buying does not
hero.pos = {x = 900, y = 900, z = 7}
res = op(hero, "buy", {i = 5, w = window, id = st.items[5].id})
has(res.result.text, "in person", "away refused")
eq(res.state.near, false, "the window knows")
hero.pos = {x = 1004, y = 998, z = 7}

-- the rate limit drops a request
limited = true
res = op(hero, "buy", {i = 5, w = window, id = st.items[5].id})
limited = false
eq(res.result, nil, "rate limited: no answer")
eq(res.state, nil, "rate limited: no state")

-- relog and restart: the same stock, the sold slots kept
local before = op(hero, "open").state
events.ChaosGambleLogout.onLogout(hero)
P.cache = {}
P.ruleTable = P.parseRules(MOVEMENTS, WEAPONS)
local after = op(hero, "open").state
eq(#after.items, #before.items, "same size after a relog")
local kept = true
for i, it in ipairs(before.items) do
	local b = after.items[i]
	kept = kept and b.id == it.id and b.l == it.l and b.p == it.p and (b.sold or false) == (it.sold or false)
end
check(kept, "the same stock and sold slots after a relog / restart")
-- leveling inside the window does not change the stock
hero.level = 1100
local leveled = op(hero, "open").state
check(leveled.items[1].id == before.items[1].id and leveled.level == 1000, "the stock is frozen for the window")

-- early refresh: a new stock, the sold marks cleared, the price doubles, three at most
local g = gate(1000)
local price1 = K.rerollPrice(cfg, g, 0)
local gold4 = hero.money + hero.bank
res = op(hero, "reroll", {w = window})
check(res.result.ok, "early refresh")
eq(hero.money + hero.bank, gold4 - price1, "its price taken")
eq(hero.storage[7101904], 1, "one early refresh")
eq(hero.storage[7101903], 0, "sold marks cleared")
check(not same(K.stock(cfg, {guid = 11, window = window, rerolls = 0, level = 1000, gate = g, canUse = warriorUse}),
	K.stock(cfg, {guid = 11, window = window, rerolls = 1, level = 1000, gate = g, canUse = warriorUse})), "a new stock")
eq(res.state.reroll, 2 * price1, "the next costs double")
op(hero, "reroll", {w = window})
op(hero, "reroll", {w = window})
res = op(hero, "reroll", {w = window})
check(not res.result.ok, "a fourth is refused")
has(res.result.text, "No more fresh crates", "fourth text")
eq(hero.storage[7101904], 3, "three at most")
hero.pos = {x = 900, y = 900, z = 7}
res = op(hero, "reroll", {w = window})
has(res.result.text, "in person", "early refresh away refused")
hero.pos = {x = 1004, y = 998, z = 7}

-- the next window: a new snapshot, nothing sold, no refreshes, the new level
P.clockShift = P.clockShift + 4 * 3600
local nextSt = op(hero, "open").state
eq(nextSt.w, window + 1, "the next window")
eq(hero.storage[7101903], 0, "nothing sold")
eq(hero.storage[7101904], 0, "no early refresh")
eq(nextSt.level, 1100, "the level of the new window")
local anySold = false
for _, it in ipairs(nextSt.items) do
	anySold = anySold or it.sold == true
end
check(not anySold, "a fresh stock")

-- a mystic of the same level sees mystic gear only
local mystic = newPlayer(13, 1000, 1)
mystic.pos = hero.pos
events.ChaosGambleLogin.onLogin(mystic)
local mst = op(mystic, "open").state
local mysticUse = P.canUseFor(1000, "Mystic")
for _, it in ipairs(mst.items) do
	check(mysticUse(it.id), "the mystic can use " .. it.id)
	check(it.id ~= 29879 and it.id ~= 29883, "no warrior gear for the mystic")
end

-- unknown actions and other opcodes are ignored
res = op(hero, "steal", {})
eq(res.state, nil, "unknown action ignored")
sent = {}
events.ChaosGambleExtended.onExtendedOpcode(hero, 198, json.encode({action = "open"}))
eq(#sent, 0, "another opcode ignored")

-- the engine part reads the library itself: the entries follow the switch
do
	ChaosGearSets = nil
	eq(#P.setEntries(), 643, "engine: set pieces on offer with the switch on")
	ChaosGearSets.PAIR28 = false
	eq(#P.setEntries(), 0, "engine: none with the switch off")
	ChaosGearSets.PAIR28 = true
end

print(string.format("gamble_test: %d checks, %d failures", count, failures))
if failures > 0 then
	os.exit(1)
end
