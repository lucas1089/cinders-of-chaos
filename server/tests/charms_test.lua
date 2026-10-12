-- Run from the server/ folder: luajit tests/charms_test.lua (and lua5.3; CI runs both)
-- Charms: the pure rules (charms_core.lua: config check, the grid and its unlocks, placement and overlap, rolls and the
-- gear-slot rule, totals under the caps, drops, item attributes, the crash-safe place / take with every crash point)
-- and the engine part (charms.lua) against a mocked engine and database: place, move, take, salvage, reforge, the
-- totals handed to item_mods.lua, the effects, a crash in the middle of a place and of a take settled at login.

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

-- a small deterministic random source (the same numbers under LuaJIT and Lua 5.3)
local function lcg(seed)
	local s = seed
	return function(a, b)
		s = (s * 16807) % 2147483647 -- exact in doubles and in 5.3 integers
		if not a then
			return s / 2147483647
		end
		return a + s % (b - a + 1)
	end
end

COMBAT_PHYSICALDAMAGE, COMBAT_FIREDAMAGE, COMBAT_ICEDAMAGE, COMBAT_ENERGYDAMAGE = 1, 8, 512, 4
COMBAT_EARTHDAMAGE, COMBAT_DEATHDAMAGE, COMBAT_HOLYDAMAGE, COMBAT_HEALING = 2, 1024, 2048, 128

local cfg = dofile("data/scripts/chaos/charms_config.lua")
dofile("data/scripts/chaos/charms_core.lua")
local C = ChaosCharmsCore

-- ---------------------------------------------------------------- config
local errors = C.validate(cfg)
eq(#errors, 0, "config valid: " .. table.concat(errors, "; "))
eq(cfg.opcode, 198, "opcode")
for _, it in ipairs(cfg.items) do
	check(it.id >= 32301 and it.id <= 32309, "item id range " .. it.id)
end
eq(C.shardId(cfg), 32309, "shard id")
eq(C.idOfShape(cfg, "grand"), 32304, "grand id")
eq(C.idOfUnique(cfg, "hoard"), 32307, "unique id")
check(C.charmDef(cfg, 32309) == nil, "the shard is no charm")
check(C.charmDef(cfg, 32305) ~= nil, "a unique is a charm")
-- a broken config is caught
do
	local bad = dofile("data/scripts/chaos/charms_config.lua")
	bad.pool[1].range = {1, 9} -- 9 x 3.0 = 27 >= one gear slot's 16
	bad.unlocks[2].cells[1] = {1, 1} -- a cell twice
	local e = C.validate(bad)
	check(#e >= 2, "broken config reported (" .. #e .. ")")
end

-- every key: the best roll of the biggest charm stays below one gear slot's best and inside the charm cap
for _, def in ipairs(cfg.pool) do
	local best = C.maxRoll(cfg, def)
	if def.gearRef then
		check(best < def.gearRef, def.key .. " best " .. best .. " below the gear slot " .. def.gearRef)
	end
	check(best <= def.cap, def.key .. " best within cap")
	check(C.maxRoll(cfg, def, "small") < best or best == 1, def.key .. ": bigger charms roll stronger")
end
-- the gear catalogue's own T8 tops (chaos_item_mods.lua) are the gear references
do
	ChaosItemMods = nil
	local okLoad = pcall(dofile, "data/lib/chaos_item_mods.lua")
	if okLoad and ChaosItemMods then
		for _, def in ipairs(cfg.pool) do
			local g = def.gear and ChaosItemMods.byKey[def.key]
			if g then
				eq(def.gearRef, g.tiers[#g.tiers][2], def.key .. " gearRef = gear T8 top")
			end
		end
		eq(cfg.pool[1].gearRef, ChaosItemMods.byKey.bossdamage.tiers[8][2], "family ref = elites and bosses T8")
		eq(cfg.extraKeys.goblinchance.gearRef, ChaosItemMods.byKey.goblinchance.tiers[8][2], "goblin ref")
	end
end

-- ---------------------------------------------------------------- the grid and its unlocks
local function opened(level, ach)
	return C.unlockState(cfg, level, function(id) return ach and id == "rift_t10" end)
end
eq(opened(1).openCount, 6, "base cells")
eq(opened(199).openCount, 6, "level 199")
eq(opened(200).openCount, 10, "level 200")
eq(opened(400).openCount, 13, "level 400")
eq(opened(600).openCount, 15, "level 600")
eq(opened(800).openCount, 18, "level 800")
eq(opened(800, true).openCount, 20, "level 800 + achievement: the whole grid")
eq(opened(1, true).openCount, 8, "the achievement alone")
has(opened(350).locked["1,3"].text, "level 400", "locked reason: level")
has(opened(900).locked["5,4"].text, "Edge of Ruin", "locked reason: achievement")
check(opened(900).locked["1,1"] == nil, "base never locked")

local open1 = opened(1).open
local openAll = opened(1000, true).open
eq(#C.footprint(cfg, "grand", 1, 1), 4, "grand covers 4 cells")
eq(C.footprint(cfg, "tall", 2, 3)[2][2], 4, "tall goes down")
check(C.placeRefusal(cfg, {}, "small", 1, 1, open1) == nil, "small at 1,1")
check(C.placeRefusal(cfg, {}, "grand", 2, 1, open1) == nil, "grand at 2,1")
has(C.placeRefusal(cfg, {}, "grand", 3, 1, open1), "locked", "grand into a locked column")
has(C.placeRefusal(cfg, {}, "grand", 5, 1, openAll), "inside the grid", "grand over the edge")
has(C.placeRefusal(cfg, {}, "tall", 1, 4, openAll), "inside the grid", "tall below the grid")
has(C.placeRefusal(cfg, {}, "small", 0, 1, openAll), "inside the grid", "x 0")
has(C.placeRefusal(cfg, {}, "small", "a", 1, openAll), "not a charm", "bad x")
has(C.placeRefusal(cfg, {}, "nope", 1, 1, openAll), "not a charm", "unknown shape")
local placed = {{id = 1, shape = "grand", x = 1, y = 1}, {id = 2, shape = "tall", x = 3, y = 1}}
has(C.placeRefusal(cfg, placed, "small", 2, 2, openAll), "in the way", "overlap grand")
has(C.placeRefusal(cfg, placed, "wide", 2, 1, openAll), "in the way", "overlap two")
has(C.placeRefusal(cfg, placed, "small", 3, 2, openAll), "in the way", "overlap tall's second cell")
check(C.placeRefusal(cfg, placed, "small", 4, 1, openAll) == nil, "free cell next to them")
check(C.placeRefusal(cfg, placed, "tall", 3, 2, openAll, 2) == nil, "moving a charm over its own cells")
has(C.placeRefusal(cfg, placed, "tall", 3, 2, openAll, 1), "in the way", "ignoring the wrong charm")
do -- a full grid
	local many = {}
	for i = 1, cfg.maxPlaced do
		many[i] = {id = i, shape = "small", x = 1 + (i - 1) % 5, y = 1 + math.floor((i - 1) / 5)}
	end
	has(C.placeRefusal(cfg, {}, "small", 1, 1, openAll) or "fits", "fits", "empty grid")
	local occ = C.occupancy(cfg, many)
	eq(occ["5,4"], 20, "occupancy")
end
check(C.activeOf(cfg, {shape = "grand", x = 1, y = 1}, open1), "grand on base cells is active")
check(not C.activeOf(cfg, {shape = "wide", x = 3, y = 1}, open1), "a charm on a closed cell gives nothing")

-- ---------------------------------------------------------------- rolls
local rand = lcg(7)
local seenShapes, seenRarity, tooHigh = {}, {}, 0
for i = 1, 3000 do
	local ch = C.rollCharm(cfg, {ilvl = 1 + i % 100, rand = rand})
	seenShapes[ch.shape] = (seenShapes[ch.shape] or 0) + 1
	seenRarity[ch.rarity] = (seenRarity[ch.rarity] or 0) + 1
	eq(#ch.mods, cfg.rarities[ch.rarity].mods, "mod count by rarity")
	eq(ch.item, C.idOfShape(cfg, ch.shape), "item id of the shape")
	if #ch.mods == 2 then
		check(ch.mods[1].key ~= ch.mods[2].key, "two different modifiers")
		local d1, d2 = C.index(cfg).pool[ch.mods[1].key], C.index(cfg).pool[ch.mods[2].key]
		check(not (d1.group and d1.group == d2.group), "never two of one group")
	end
	for _, m in ipairs(ch.mods) do
		local def = C.index(cfg).pool[m.key]
		if m.value < 1 or m.value > C.maxRoll(cfg, def, ch.shape) then
			tooHigh = tooHigh + 1
		end
	end
end
eq(tooHigh, 0, "every roll inside 1 .. the shape's best")
check(seenShapes.small > seenShapes.grand and seenShapes.grand > 100, "shape weights")
check(seenRarity[1] > seenRarity[2] and seenRarity[2] > seenRarity[3], "rarity weights")
-- bigger, rarer and higher-level charms roll stronger
local fire = C.index(cfg).pool.dmg_dragons
eq(C.valueOf(cfg, fire, 1, "small", 3, 100), 3, "small best")
eq(C.valueOf(cfg, fire, 1, "tall", 3, 100), 5, "tall best")
eq(C.valueOf(cfg, fire, 1, "grand", 3, 100), 9, "grand best")
eq(C.valueOf(cfg, fire, 1, "grand", 1, 100), 6, "faint grand")
eq(C.valueOf(cfg, fire, 1, "grand", 3, 1), 5, "item level 1 grand")
eq(C.valueOf(cfg, fire, 0, "small", 1, 1), 1, "never below 1")
local lok = C.index(cfg).pool.lifeonkill
eq(C.valueOf(cfg, lok, 1, "grand", 3, 100), 30, "life on kill grand best")
-- uniques
local u = C.rollCharm(cfg, {unique = "hoard", ilvl = 80})
eq(u.item, 32307, "unique item")
eq(u.shape, "grand", "unique shape")
eq(u.mods[1].key, "orbfind", "unique fixed mod")
eq(C.nameOf(cfg, u), "Eye of the Hoard", "unique name")
eq(C.rarityName(cfg, u), "Unique", "unique rarity")
check(C.reforge(cfg, u) == nil, "a unique cannot be reforged")
eq(C.salvageShards(cfg, u), 15, "unique salvage")
-- reforge keeps the modifiers
local r3 = C.rollCharm(cfg, {shape = "wide", rarity = 3, ilvl = 90, rand = lcg(3)})
local rf = C.reforge(cfg, r3, lcg(99))
eq(rf.mods[1].key, r3.mods[1].key, "reforge keeps mod 1")
eq(rf.mods[2].key, r3.mods[2].key, "reforge keeps mod 2")
eq(rf.ilvl, 90, "reforge keeps the item level")
eq(C.reforgeCost(cfg, r3), 12, "reforge cost wide")
eq(C.salvageShards(cfg, r3), 6, "salvage wide radiant")
eq(C.salvageShards(cfg, {shape = "small", rarity = 1, mods = {}}), 2, "salvage small faint")

-- ---------------------------------------------------------------- texts and item attributes
eq(C.text(cfg, "goldfind", 4), "Gold Find +4%", "pct text")
eq(C.text(cfg, "lifeonkill", 12), "Life on Kill +12", "flat text")
eq(C.text(cfg, "rifttime", 20), "Rift Time +20 s", "own text")
eq(C.nameOf(cfg, r3), "Radiant Wide Charm", "rolled name")
local lines = C.describe(cfg, r3)
has(lines[1], "item level 90", "look text level")
has(lines[1], "2x1", "look text shape")
local attrs = {}
for _, a in ipairs(C.toAttrs(r3)) do
	attrs[a[1]] = a[2]
end
local back = C.fromAttrs(cfg, r3.item, function(k) return attrs[k] end)
eq(back.shape, "wide", "attrs round trip shape")
eq(back.rarity, 3, "attrs round trip rarity")
eq(back.mods[2].value, r3.mods[2].value, "attrs round trip value")
attrs[C.ATTR.value1] = 500
back = C.fromAttrs(cfg, r3.item, function(k) return attrs[k] end)
eq(back.mods[1].value, C.maxRoll(cfg, C.index(cfg).pool[r3.mods[1].key], "wide"), "an impossible value counts as the best roll")
attrs[C.ATTR.key2] = "bossdamage"
back = C.fromAttrs(cfg, r3.item, function(k) return attrs[k] end)
eq(#back.mods, 1, "a key outside the charm pool is ignored")
check(C.fromAttrs(cfg, 2160, function() return nil end) == nil, "no charm")
local uniq = C.fromAttrs(cfg, 32305, function(k) return k == "chaos_ilvl" and 70 or nil end)
eq(uniq.unique, "gravewarden", "unique from attrs")
eq(uniq.mods[1].value, 6, "unique values are fixed")
eq(C.unhex(C.hex("a\0b\255")), "a\0b\255", "hex round trip")
check(C.unhex("zz") == nil and C.unhex("abc") == nil, "bad hex")
local view = C.viewOf(cfg, r3)
eq(view.w, 2, "view width")
eq(#view.mods, 2, "view mods")
eq(view.reforge, 12, "view reforge cost")

-- ---------------------------------------------------------------- totals and caps
local function grand(key, value)
	return {charm = {shape = "grand", rarity = 3, mods = {{key = key, value = value}}}, active = true}
end
local own, gear, sig = C.totals(cfg, {grand("goldfind", 6), grand("goldfind", 6), grand("lifeonkill", 30),
	{charm = {shape = "small", rarity = 1, mods = {{key = "goldfind", value = 2}}}, active = false}})
eq(own.goldfind, 10, "gold find capped at the charm cap")
eq(gear.goldfind, 10, "gear extra gold find")
eq(own.lifeonkill, 30, "life on kill summed")
eq(own.orbfind, 0, "nothing else")
check(gear.orbfind == nil, "own keys stay out of the gear extra")
eq(own.manaonkill, 0, "no harvester, no mana")
own, gear, sig = C.totals(cfg, {grand("dmg_undead", 9), grand("dmg_undead", 9), {charm = C.rollCharm(cfg, {unique = "gravewarden"})},
	{charm = C.rollCharm(cfg, {unique = "tally"})}, {charm = C.rollCharm(cfg, {unique = "hoard"})}, grand("res_fire", 6),
	grand("res_fire", 6)})
eq(own.dmg_undead, 15, "family capped (9 + 9 + 6 -> 15)")
eq(own.res_death, 4, "unique resistance")
eq(own.res_fire, 8, "element capped")
eq(own.lifeonkill, 12, "tally")
eq(own.manaonkill, 6, "harvester: half the charm life on kill")
eq(own.goblinchance, 15, "hoard sense")
eq(gear.goblinchance, 15, "goblin chance into the gear totals")
check(sig.lastember and sig.harvester and sig.hoardsense and not sig.wayfarer, "signatures")
eq(C.familyPct(own, "undead"), 15, "family pct")
eq(C.familyPct(own, "dragons"), 0, "other family")
eq(C.resistPct(cfg, own, COMBAT_FIREDAMAGE), 8, "fire resist")
eq(C.resistPct(cfg, own, COMBAT_DEATHDAMAGE), 4, "death resist")
eq(C.resistPct(cfg, own, COMBAT_PHYSICALDAMAGE), 0, "no physical resist")
eq(C.reduce(-100, 8), -92, "reduce a hit")
eq(C.reduce(-7, 8), -6, "reduce rounds toward zero")
eq(C.emberCap(100, -150, 0), 99, "lethal hit leaves 1")
check(C.emberCap(100, -50, -20) == nil, "not lethal")
-- the item modifiers' caps still apply on top (item_mods.lua hands the charms in as `extra`)
if ChaosItemMods then
	local gearOwn = {}
	gearOwn.goldfind = 10
	local t = ChaosItemMods.totals({}, C.merge({goldfind = 35}, gearOwn))
	eq(t.goldfind, ChaosItemMods.byKey.goldfind.cap, "gear cap over items + charms")
	local base = {goldfind = 3}
	local merged = C.merge(base, {goldfind = 2, lifeonkill = 4})
	eq(base.goldfind, 3, "merge leaves its input alone")
	eq(merged.goldfind, 5, "merge sums")
	check(C.merge(base, {}) == base and C.merge(base, nil) == base, "merge with nothing")
end
eq(C.signature({grand("goldfind", 6), grand("lifeonkill", 30)}), C.signature({grand("lifeonkill", 30), grand("goldfind", 6)}),
	"signature ignores the order")
local rows = C.totalsView(cfg, own)
check(#rows >= 5, "totals view rows")
eq(rows[1].k, "dmg_undead", "totals view in pool order")

-- ---------------------------------------------------------------- drops
local function chance(src, ctx)
	return (C.dropChance(cfg, src, ctx))
end
eq(chance("rift", {tier = 5}), 0, "rift below tier 6")
eq(chance("rift", {tier = 6}), 6, "rift tier 6")
eq(chance("rift", {tier = 10}), 10, "rift tier 10")
eq(chance("rift", {tier = 30}), 15, "rift chance capped")
eq(select(2, C.dropChance(cfg, "rift", {tier = 15})), 100, "rift tier 15 item level")
eq(chance("bounty", {level = 500}), 4, "bounty")
eq(select(2, C.dropChance(cfg, "bounty", {level = 2000})), 80, "bounty item level capped")
eq(chance("invasion", {rank = 1}), 25, "invasion top")
eq(chance("invasion", {rank = 4}), 10, "invasion")
eq(chance("dungeon", {difficulty = 3}), 14, "dungeon")
eq(chance("descent", {depth = 4}), 3, "descent room")
eq(chance("descent", {depth = 9, boss = true}), 15, "descent boss")
eq(chance("nothing", {}), 0, "unknown source")
do -- 20000 tier 10 rifts: about 10% charms, about 2% of those unique
	local r = lcg(2024)
	local got, uniques = 0, 0
	for _ = 1, 20000 do
		local ch = C.rollDrop(cfg, "rift", {tier = 10}, r)
		if ch then
			got = got + 1
			if ch.unique then
				uniques = uniques + 1
			end
			check(ch.ilvl == 80, "rift tier 10 charm item level")
		end
	end
	check(got > 1800 and got < 2200, "rift drop rate about 10% (" .. got .. ")")
	check(uniques >= 15 and uniques <= 70, "unique share about 2% (" .. uniques .. ")")
	eq(C.rollDrop(cfg, "rift", {tier = 3}, r), nil, "no drop below the tier")
end

-- ---------------------------------------------------------------- crash safety (simulated world, every crash point)
-- The world: the saved database rows (written at once), the character in memory and as saved (inventory and storage).
-- A crash loses memory: the character is reloaded from its saved state. Then the login settles pending rows.
local function world()
	local w = {rows = {}, nextId = 1, mem = {inv = {charm = 1}, seq = 0}, saved = {inv = {charm = 1}, seq = 0}}
	function w.copies()
		local n = w.saved.inv.charm or 0
		for _, r in pairs(w.rows) do
			if r.state == C.STATE_PLACED then
				n = n + 1
			end
		end
		return n
	end
	function w.recover()
		for id, r in pairs(w.rows) do
			local a = C.recoverAction(r.state, r.seq, w.saved.seq)
			if a == "activate" or a == "restore" then
				r.state = C.STATE_PLACED
			elseif a == "drop" then
				w.rows[id] = nil
			end
		end
		w.mem = {inv = {charm = w.saved.inv.charm}, seq = w.saved.seq}
	end
	return w
end
local function envOf(w, crashAt, failSave)
	local steps = 0
	local function step()
		steps = steps + 1
		if steps == crashAt then
			error("crash")
		end
	end
	return {
		getSeq = function() return w.mem.seq end,
		setSeq = function(n) step(); w.mem.seq = n end,
		insertRow = function(rec) step(); local id = w.nextId; w.nextId = id + 1; w.rows[id] = {id = id, state = rec.state, seq = rec.seq}; return id end,
		setRow = function(id, from, to, seq) step(); local r = w.rows[id]; if r and r.state == from then r.state, r.seq = to, seq; return true end; return false end,
		deleteRow = function(id, state) step(); if w.rows[id] and w.rows[id].state == state then w.rows[id] = nil end end,
		removeItem = function() step(); if (w.mem.inv.charm or 0) < 1 then return false end; w.mem.inv.charm = w.mem.inv.charm - 1; return true end,
		restoreItem = function() step(); w.mem.inv.charm = w.mem.inv.charm + 1 end,
		createItem = function() step(); w.mem.inv.charm = (w.mem.inv.charm or 0) + 1; return true end,
		uncreateItem = function() step(); w.mem.inv.charm = w.mem.inv.charm - 1 end,
		save = function()
			step()
			if failSave then
				return false
			end
			w.saved = {inv = {charm = w.mem.inv.charm}, seq = w.mem.seq}
			return true
		end
	}
end
for crashAt = 1, 8 do
	-- place, crash at step crashAt, login
	local w = world()
	local ok = pcall(C.place, envOf(w, crashAt), {x = 1, y = 1})
	if not ok then
		w.recover()
	end
	eq(w.copies(), 1, "place, crash at step " .. crashAt .. ": exactly one charm")
	-- take it out again (when it went in), crash at step crashAt, login
	local placedRow
	for _, r in pairs(w.rows) do
		placedRow = r
	end
	if placedRow then
		w.mem = {inv = {charm = w.saved.inv.charm}, seq = w.saved.seq}
		local ok2 = pcall(C.take, envOf(w, crashAt), {id = placedRow.id, seq = placedRow.seq})
		if not ok2 then
			w.recover()
		end
		eq(w.copies(), 1, "take, crash at step " .. crashAt .. ": exactly one charm")
	end
end
do -- a failed save gives everything back
	local w = world()
	local ok, why = C.place(envOf(w, 0, true), {x = 1, y = 1})
	check(not ok and why == "busy", "place refused when the save fails")
	eq(w.mem.inv.charm, 1, "the charm is back in memory")
	eq(next(w.rows), nil, "no row left")
	eq(w.mem.seq, 0, "serial back")
	local ok2 = C.place(envOf(w, 0), {x = 1, y = 1})
	check(ok2, "place")
	local row = w.rows[2]
	eq(row and row.state, C.STATE_PLACED, "row placed")
	local ok3, why3 = C.take(envOf(w, 0, true), row)
	check(not ok3 and why3 == "busy", "take refused when the save fails")
	eq(w.mem.inv.charm, 0, "no copy in memory")
	eq(row.state, C.STATE_PLACED, "row back to placed")
	-- a second take of the same row while one is pending cannot happen: the row must be placed
	row.state = C.STATE_TAKING
	local ok4 = C.take(envOf(w, 0), row)
	check(not ok4, "a row that is not placed cannot be taken")
end
eq(C.recoverAction(C.STATE_PLACING, 5, 5), "activate", "placing saved")
eq(C.recoverAction(C.STATE_PLACING, 6, 5), "drop", "placing not saved")
eq(C.recoverAction(C.STATE_TAKING, 5, 5), "drop", "taking saved")
eq(C.recoverAction(C.STATE_TAKING, 6, 5), "restore", "taking not saved")
eq(C.recoverAction(C.STATE_PLACING, 1, -1), "drop", "no storage yet")
eq(C.recoverAction(C.STATE_PLACED, 1, 9), "keep", "placed rows stay")

-- ---------------------------------------------------------------- engine (charms.lua) against a mocked engine
RETURNVALUE_NOERROR, RETURNVALUE_NOTENOUGHROOM = 0, 1
MESSAGE_STATUS_SMALL, MESSAGE_EVENT_ADVANCE, MESSAGE_INFO_DESCR = 1, 2, 3
CONDITION_INFIGHT, SKILL_LEVEL, CONST_SLOT_BACKPACK = 4, 8, 3
ITEM_ATTRIBUTE_DESCRIPTION, ITEM_ATTRIBUTE_NAME = 1, 2
INDEX_WHEREEVER, FLAG_NOLIMIT = -1, 1
CONST_ME_MAGIC_GREEN, CONST_ME_FIREAREA = 13, 7

local events, globalEvents = {}, {}
CreatureEvent = function(name)
	local e = {register = function() end}
	events[name] = e
	return e
end
GlobalEvent = function(name)
	local e = {register = function() end}
	globalEvents[name] = e
	return e
end
EventCallback = {register = function() end}
TalkAction = function() return {separator = function() end, register = function() end} end
local timers = {}
addEvent = function(fn, ms, ...) timers[#timers + 1] = {fn = fn, args = {...}} end

-- json: a registry of deep copies (the engine only encodes what it sends or stores and decodes what it stored)
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

-- items and the backpack
local itemSeq = 0
local function newItem(id, count)
	itemSeq = itemSeq + 1
	local it = {id = id, count = count or 1, custom = {}, attrs = {}, uid = itemSeq}
	function it:getId() return self.id end
	function it:getCount() return self.count end
	function it:getCustomAttribute(k) return self.custom[k] end
	function it:setCustomAttribute(k, v) self.custom[k] = v end
	function it:removeCustomAttribute(k) self.custom[k] = nil end
	function it:setAttribute(k, v) self.attrs[k] = v end
	function it:isContainer() return false end
	function it:remove()
		if self.parent then
			for i, x in ipairs(self.parent.items) do
				if x == self then
					table.remove(self.parent.items, i)
					break
				end
			end
			self.parent = nil
		end
		self.removed = true
		return true
	end
	return it
end
local function newContainer(cap)
	local c = newItem(1988)
	c.items, c.cap = {}, cap
	function c:isContainer() return true end
	function c:getSize() return #self.items end
	function c:getItem(i) return self.items[i + 1] end
	function c:addItemEx(item)
		if #self.items >= self.cap then
			return RETURNVALUE_NOTENOUGHROOM
		end
		if item.parent then
			item:remove()
		end
		item.removed = nil
		item.parent = self
		table.insert(self.items, 1, item)
		return RETURNVALUE_NOERROR
	end
	return c
end
Game = {createItem = function(id, count) return newItem(id, count) end, getPlayers = function() return {} end}
ItemType = function(id) return {getClientId = function() return id + 100000 end} end

-- the database: chaos_charms rows; escaped strings are tokens
local DB, strings, lastCount, lastId, failNext = {}, {}, 0, 0, nil
local nextRow = 1
local function val(tok)
	local i = tok:match("^@(%d+)@$")
	if i then
		return strings[tonumber(i)]
	end
	return tonumber(tok)
end
db = {
	escapeString = function(s) strings[#strings + 1] = tostring(s); return "@" .. #strings .. "@" end,
	query = function(q)
		if failNext and q:find(failNext, 1, true) then
			failNext = nil
			error("crash")
		end
		lastCount = 0
		if q:match("^CREATE") then
			return true
		end
		local list = q:match("^INSERT INTO `chaos_charms` %b() VALUES %((.*)%)$")
		if list then
			local v = {}
			for tok in list:gmatch("[^,%s]+") do
				v[#v + 1] = val(tok)
			end
			local r = {id = nextRow, player_id = v[1], state = v[2], seq = v[3], x = v[4], y = v[5], item_id = v[6], codec = v[7],
				data = v[8], charm = v[9]}
			DB[nextRow], lastId, nextRow, lastCount = r, nextRow, nextRow + 1, 1
			return true
		end
		local to, seq, id, pid, from = q:match("^UPDATE `chaos_charms` SET `state` = (%d+), `seq` = (%d+) WHERE `id` = (%d+) AND `player_id` = (%d+) AND `state` = (%d+)$")
		if to then
			local r = DB[tonumber(id)]
			if r and r.player_id == tonumber(pid) and r.state == tonumber(from) then
				r.state, r.seq, lastCount = tonumber(to), tonumber(seq), 1
			end
			return true
		end
		local x, y
		x, y, id, pid = q:match("^UPDATE `chaos_charms` SET `x` = (%d+), `y` = (%d+) WHERE `id` = (%d+) AND `player_id` = (%d+) AND `state` = 0$")
		if x then
			local r = DB[tonumber(id)]
			if r and r.player_id == tonumber(pid) and r.state == 0 then
				r.x, r.y, lastCount = tonumber(x), tonumber(y), 1
			end
			return true
		end
		id, from = q:match("^UPDATE `chaos_charms` SET `state` = 0 WHERE `id` = (%d+) AND `state` = (%d+)$")
		if id then
			local r = DB[tonumber(id)]
			if r and r.state == tonumber(from) then
				r.state, lastCount = 0, 1
			end
			return true
		end
		id, pid, from = q:match("^DELETE FROM `chaos_charms` WHERE `id` = (%d+) AND `player_id` = (%d+) AND `state` = (%d+)$")
		if not id then
			id, from = q:match("^DELETE FROM `chaos_charms` WHERE `id` = (%d+) AND `state` = (%d+)$")
		end
		if id then
			local r = DB[tonumber(id)]
			if r and r.state == tonumber(from) and (not pid or r.player_id == tonumber(pid)) then
				DB[tonumber(id)], lastCount = nil, 1
			end
			return true
		end
		error("unexpected query " .. q)
	end
}

dofile("data/scripts/chaos/chaos_constants.lua")
Chaos.select = function(q, cols)
	if q:match("ROW_COUNT") then
		return {{n = lastCount}}
	elseif q:match("LAST_INSERT_ID") then
		return {{id = lastId}}
	elseif q:match("FROM `players`") then
		return {{save = 1}}
	end
	local pid = tonumber(q:match("`player_id` = (%d+)"))
	local out = {}
	local ids = {}
	for id in pairs(DB) do
		ids[#ids + 1] = id
	end
	table.sort(ids)
	for _, id in ipairs(ids) do
		local r = DB[id]
		if r.player_id == pid then
			if (q:match("`state` = 0") and r.state == 0) or (q:match("IN %(8, 9%)") and (r.state == 8 or r.state == 9)) then
				out[#out + 1] = deep(r)
			end
		end
	end
	return out
end
local sentOps = {}
Chaos.send = function(player, op, action, data) sentOps[#sentOps + 1] = {action = action, data = data} end
Chaos.sendChunked = function(player, op, text) sentOps[#sentOps + 1] = json.decode(text) end
Chaos.heal = function(creature, amount) creature.health = math.min(creature.maxHealth, creature.health + amount) end
Chaos.monsterTypeName = function(creature) return creature.name end

-- item_mods.lua's side: what it would hand to its totals
local itemModsRefreshed = 0
ChaosItemMods = ChaosItemMods or {}
ChaosItemMods.refresh = function(player, force)
	itemModsRefreshed = itemModsRefreshed + 1
	local gear = ChaosCharms.extra(player)
	player.gearExtra = gear
end
ChaosAchievements = {has = function(player, id) return player.ach and player.ach[id] == true end}

local function newPlayer(guid, level)
	local p = {guid = guid, level = level, storage = {}, backpack = newContainer(20), inbox = newContainer(100), messages = {},
		speed = 0, baseSpeed = 200, health = 1000, maxHealth = 1000, mana = 100, maxMana = 500, infight = false}
	function p:getGuid() return self.guid end
	function p:getId() return 0x10000000 + self.guid end
	function p:getName() return "Tester" .. self.guid end
	function p:getLevel() return self.level end
	function p:getSlotItem(slot) return slot == CONST_SLOT_BACKPACK and self.backpack or nil end
	function p:getInbox() return self.inbox end
	function p:isPzLocked() return false end
	function p:hasCondition(c) return c == CONDITION_INFIGHT and self.infight end
	function p:getStorageValue(k) return self.storage[k] or -1 end
	function p:setStorageValue(k, v) self.storage[k] = v end
	function p:sendTextMessage(t, text) self.messages[#self.messages + 1] = text end
	function p:getPosition() return {sendMagicEffect = function() end} end
	function p:isPlayer() return true end
	function p:isMonster() return false end
	function p:getHealth() return self.health end
	function p:getMaxHealth() return self.maxHealth end
	function p:getMana() return self.mana end
	function p:getMaxMana() return self.maxMana end
	function p:addMana(n) self.mana = math.min(self.maxMana, self.mana + n) end
	function p:getBaseSpeed() return self.baseSpeed end
	function p:changeSpeed(d) self.speed = self.speed + d end
	function p:addItemEx(item) return self.backpack:addItemEx(item) end
	function p:registerEvent() end
	function p:getItemCount(id)
		local n = 0
		for _, it in ipairs(self.backpack.items) do
			if it.id == id then
				n = n + it.count
			end
		end
		return n
	end
	function p:removeItem(id, n)
		for _, it in ipairs(self.backpack.items) do
			if it.id == id and it.count >= n then
				it.count = it.count - n
				if it.count == 0 then
					it:remove()
				end
				return true
			end
		end
		return false
	end
	-- save: the storage and the items as they are now (what a crash goes back to)
	function p:save()
		if self.failSave then
			return false
		end
		if self.crashInSave then
			self.crashInSave = nil
			error("crash")
		end
		self.saved = {storage = deep(self.storage), items = {}}
		for _, it in ipairs(self.backpack.items) do
			self.saved.items[#self.saved.items + 1] = {id = it.id, count = it.count, custom = deep(it.custom)}
		end
		return true
	end
	-- a crash: the character comes back as it was saved
	function p:restart()
		self.storage = deep(self.saved.storage)
		self.backpack.items = {}
		for i = #self.saved.items, 1, -1 do
			local s = self.saved.items[i]
			local it = newItem(s.id, s.count)
			it.custom = deep(s.custom)
			self.backpack:addItemEx(it)
		end
	end
	p:save()
	return p
end

dofile("data/scripts/chaos/charms.lua")
local CH = ChaosCharms
eq(ChaosOpcodes.charms, 198, "opcode constant")
eq(Chaos.storage.charms, cfg.storage.seq, "storage constant")
eq(Chaos.tables.charms, "chaos_charms", "table constant")
-- the opcode collision check (server/README.md): the reference server's opcodes, the reference client's own, every Chaos one
for _, taken in ipairs({1, 67, 73, 89, 91, 92, 99, 106, 107, 136, 181, 201, 202, 140, 144, 145, 146, 210, 212, 213, 230, 246}) do
	check(taken ~= ChaosOpcodes.charms, "opcode free of " .. taken)
end
for name, v in pairs(ChaosOpcodes) do
	check(name == "charms" or v ~= ChaosOpcodes.charms, "opcode not shared with " .. name)
end
globalEvents.ChaosCharmsStartup.onStartup()

local player = newPlayer(7, 250)
events.ChaosCharmsLogin.onLogin(player)
local function giveCharm(spec)
	local item = CH.makeItem(C.rollCharm(cfg, spec))
	player.backpack:addItemEx(item)
	return item
end
local function refOf(item)
	for i, it in ipairs(player.backpack.items) do
		if it == item then
			return "s3." .. (i - 1)
		end
	end
end
local function op(action, data)
	sentOps = {}
	events.ChaosCharmsExtended.onExtendedOpcode(player, 198, json.encode({action = action, data = data}))
	for _, s in ipairs(sentOps) do
		if s.action == "result" then
			return s.data
		end
	end
	return sentOps[#sentOps] and sentOps[#sentOps].data
end
local function countCharms()
	local n = 0
	for _, it in ipairs(player.backpack.items) do
		if C.charmDef(cfg, it.id) then
			n = n + 1
		end
	end
	for _, it in ipairs(player.inbox.items) do
		if C.charmDef(cfg, it.id) then
			n = n + 1
		end
	end
	for _, r in pairs(DB) do
		if r.player_id == player.guid and r.state == 0 then
			n = n + 1
		end
	end
	return n
end

local g1 = giveCharm({shape = "grand", rarity = 3, ilvl = 100, rand = lcg(11)})
local g1mods = deep(CH.charmOf(g1).mods)
has(g1.attrs[ITEM_ATTRIBUTE_DESCRIPTION], "item level 100", "the look text is written")
eq(g1.attrs[ITEM_ATTRIBUTE_NAME], "radiant grand charm", "the item name")
local st = op("open")
eq(st.cols, 5, "state grid")
eq(#st.cells, 20, "state cells")
eq(#st.bag, 1, "one charm in the bag")
eq(st.bag[1].ref, "s3.0", "bag ref")
eq(#st.groups, #cfg.unlocks, "unlock groups")

-- place it: the item leaves, the row holds it
local res = op("place", {ref = refOf(g1), sid = 32304, x = 1, y = 1})
check(res and res.ok, "placed: " .. tostring(res and res.text))
eq(#player.backpack.items, 0, "the charm left the backpack")
eq(countCharms(), 1, "one charm after placing")
eq(player.saved.storage[cfg.storage.seq], 1, "serial saved with the items")
local row = DB[1]
eq(row.state, 0, "row placed")
eq(row.codec, "attrs", "attrs codec without engine patch 0017")
check(itemModsRefreshed > 0, "item_mods asked to refresh")
local pst = CH.players[player.guid]
eq(#pst.rows, 1, "placed row loaded")
local key1 = g1mods[1].key
check((pst.own[key1] or 0) == g1mods[1].value or pst.own[key1] == C.index(cfg).any[key1].cap, "the charm counts in the totals")

-- a second charm cannot overlap; a locked cell refuses
local s2 = giveCharm({shape = "small", rarity = 1, ilvl = 50, rand = lcg(5)})
res = op("place", {ref = refOf(s2), sid = 32301, x = 2, y = 2})
check(res and not res.ok, "overlap refused")
has(res.text, "in the way", "overlap text")
res = op("place", {ref = refOf(s2), sid = 32301, x = 5, y = 4})
has(res.text, "locked", "locked cell refused")
res = op("place", {ref = refOf(s2), sid = 32301, iid = "12345", x = 3, y = 1})
has(res.text, "not in your backpack", "wrong per-item id refused")
res = op("place", {ref = refOf(s2), sid = 32302, x = 3, y = 1})
has(res.text, "not in your backpack", "wrong item id refused")
eq(countCharms(), 2, "nothing changed by refusals")
res = op("place", {ref = refOf(s2), sid = 32301, x = 3, y = 1})
check(res.ok, "small placed")
eq(countCharms(), 2, "two charms")

-- combat blocks changes
player.infight = true
res = op("move", {id = 2, x = 3, y = 2})
has(res.text, "combat", "no moves in combat")
player.infight = false
res = op("move", {id = 2, x = 3, y = 2})
check(res and res.ok ~= false, "moved")
eq(DB[2].x, 3, "move x")
eq(DB[2].y, 2, "move y")
res = op("move", {id = 2, x = 2, y = 2})
has(res.text, "in the way", "move onto the grand refused")

-- take the small one out: a new item, the row is gone
res = op("take", {id = 2})
check(res.ok, "taken out")
eq(DB[2], nil, "row deleted")
eq(countCharms(), 2, "still two charms")
local taken = player.backpack.items[1]
eq(taken.id, 32301, "the charm is back")
eq(taken.custom.chaos_iid, nil, "a new per-item id")
res = op("take", {id = 2})
has(res.text, "not in your grid", "a row is taken only once")
eq(countCharms(), 2, "no copy from a second take")

-- a full backpack: the inbox takes it
player.backpack.cap = 1
res = op("take", {id = 1})
check(res.ok, "taken into the inbox")
eq(#player.inbox.items, 1, "inbox")
eq(countCharms(), 2, "still two")
player.backpack.cap = 20
local back1 = player.inbox.items[1]
player.backpack:addItemEx(back1)
player:save() -- the engine's own save (the inbox is not part of this mock's saved state)
eq(CH.charmOf(back1).mods[1].value, g1mods[1].value, "the charm keeps its modifiers through the grid")

-- crash while placing (inside the save): the row stays pending and the charm stays in the saved backpack
player.crashInSave = true
local okPlace = pcall(CH.place, player, {ref = refOf(back1), sid = 32304, x = 1, y = 1})
check(not okPlace, "crash while placing")
player:restart()
CH.players[player.guid] = nil
events.ChaosCharmsLogin.onLogin(player)
eq(countCharms(), 2, "crash while placing: no copy, no loss")
local pending = 0
for _, r in pairs(DB) do
	if r.state ~= 0 then
		pending = pending + 1
	end
end
eq(pending, 0, "the pending row is settled")
-- crash right after the save, before the row is marked placed: the login activates it
back1 = nil
for _, it in ipairs(player.backpack.items) do
	if it.id == 32304 then
		back1 = it
	end
end
failNext = "SET `state` = 0, `seq`"
local okPlace2 = pcall(CH.place, player, {ref = refOf(back1), sid = 32304, x = 1, y = 1})
check(not okPlace2, "crash after the save")
player:restart()
CH.players[player.guid] = nil
events.ChaosCharmsLogin.onLogin(player)
eq(countCharms(), 2, "crash after the save: no copy, no loss")
eq(#CH.players[player.guid].rows, 1, "the charm is in the grid after the login")
-- crash while taking out (after the item was made, before the save)
local placedId = CH.players[player.guid].rows[1].id
player.crashInSave = true
local okTake = pcall(CH.take, player, {id = placedId})
check(not okTake, "crash while taking")
player:restart()
CH.players[player.guid] = nil
events.ChaosCharmsLogin.onLogin(player)
eq(countCharms(), 2, "crash while taking: no copy, no loss")
eq(DB[placedId] and DB[placedId].state, 0, "the charm is back in the grid")
-- a failed save while taking gives nothing
player.failSave = true
res = op("take", {id = placedId})
check(not res.ok, "take refused when the save fails")
eq(countCharms(), 2, "no copy after a failed save")
player.failSave = false

-- effects: totals into item_mods, damage to a family, resistance, out-of-combat speed
for _, it in ipairs(player.backpack.items) do
	it:remove()
end
for id in pairs(DB) do
	DB[id] = nil
end
CH.players[player.guid] = nil
player.level = 1000
player.ach = {rift_t10 = true}
local function placeNew(spec, x, y)
	local it = giveCharm(spec)
	local r = op("place", {ref = refOf(it), sid = it.id, x = x, y = y})
	check(r and r.ok, "placed " .. it.id .. " at " .. x .. "," .. y .. " " .. tostring(r and r.text))
end
placeNew({unique = "gravewarden", ilvl = 80}, 1, 1)
placeNew({unique = "hoard", ilvl = 80}, 2, 1)
placeNew({unique = "tally", ilvl = 80}, 4, 1)
placeNew({unique = "compass", ilvl = 80}, 4, 4) -- the achievement cells
placeNew({shape = "small", rarity = 3, ilvl = 100, rand = lcg(1)}, 5, 1)
pst = CH.players[player.guid]
eq(#pst.rows, 5, "five charms placed")
eq(pst.own.goblinchance, 15, "hoard sense")
eq(player.gearExtra.goblinchance, 15, "item_mods gets the goblin chance")
eq(player.gearExtra.lifeonkill, pst.own.lifeonkill, "item_mods gets life on kill")
eq(pst.own.manaonkill, math.floor(pst.own.lifeonkill / 2), "harvester")
check(player.gearExtra.dmg_undead == nil, "own keys stay with the charms")
eq(CH.riftSeconds(player), pst.own.rifttime, "rift time hook")
check(CH.riftSeconds(player) >= 20, "compass rift time")
check(CH.orbFindMult(player) >= 1.08, "orb find hook")
eq(CH.repPct(player), pst.own.reputation, "reputation hook")
-- the level drops below the achievement? no: the achievement cells stay; a level loss closes the l800 cells only
player.level = 300
CH.recompute(player)
eq(CH.players[player.guid].own.rifttime >= 20, true, "achievement cells stay open")
player.level = 150
CH.recompute(player)
eq(CH.players[player.guid].own.lifeonkill, 0, "charms over closed cells give nothing")
eq(CH.players[player.guid].own.goblinchance, 15, "charms on open cells still count")
player.level = 1000
CH.recompute(player)

-- damage to undead (the family of the monster's type name)
local monster = {name = "Skeleton", isMonster = function() return true end, isPlayer = function() return false end,
	getType = function() return {race = function() return 3 end} end}
eq(CH.familyOf(monster), "undead", "skeleton family")
local dmg = events.ChaosCharmsDealt.onHealthChange(monster, player, -100, COMBAT_PHYSICALDAMAGE, 0, COMBAT_PHYSICALDAMAGE, 0)
eq(dmg, -106, "damage to undead +6%")
local dragon = {name = "Dragon Lord", isMonster = function() return true end, getType = function() return {race = function() return 2 end} end}
eq(events.ChaosCharmsDealt.onHealthChange(dragon, player, -100, COMBAT_PHYSICALDAMAGE, 0, COMBAT_PHYSICALDAMAGE, 0), -100, "no dragon bonus")
-- death resistance and the Last Ember
local attacker = monster
local p1 = events.ChaosCharmsTaken.onHealthChange(player, attacker, -100, COMBAT_DEATHDAMAGE, 0, COMBAT_NONE or 0, 0)
eq(p1, -96, "death resistance 4%")
player.health = 50
local p2, _, s2v = events.ChaosCharmsTaken.onHealthChange(player, attacker, -500, COMBAT_PHYSICALDAMAGE, -40, COMBAT_FIREDAMAGE, 0)
eq(p2, -49, "Last Ember leaves 1 health")
eq(s2v, 0, "and drops the second part")
local p3 = events.ChaosCharmsTaken.onHealthChange(player, attacker, -500, COMBAT_PHYSICALDAMAGE, 0, COMBAT_PHYSICALDAMAGE, 0)
eq(p3, -500, "Last Ember waits for its cooldown")
player.health = 1000
-- out-of-combat speed and the Wayfarer's Rest (the think)
Game.getPlayers = function() return {player} end
player.health, player.mana = 500, 100
timers = {}
for _, t in ipairs({}) do t.fn() end
local thinkFn
globalEvents.ChaosCharmsStartup.onStartup()
thinkFn = timers[#timers].fn
thinkFn()
eq(player.speed, math.floor(200 * pst.own.oocspeed / 100), "out-of-combat speed")
eq(player.health, 510, "Wayfarer's Rest health")
eq(player.mana, 105, "Wayfarer's Rest mana")
player.infight = true
thinkFn()
eq(player.speed, 0, "speed bonus off in combat")
player.infight = false

-- salvage and reforge in the backpack
local sv = giveCharm({shape = "grand", rarity = 2, ilvl = 60, rand = lcg(8)})
res = op("salvage", {ref = refOf(sv), sid = 32304})
check(res.ok, "salvaged")
eq(player:getItemCount(32309), 8, "eight shards")
local rf2 = giveCharm({shape = "small", rarity = 3, ilvl = 100, rand = lcg(4)})
local beforeKeys = CH.charmOf(rf2).mods[1].key
res = op("reforge", {ref = refOf(rf2), sid = 32301})
check(res.ok, "reforged: " .. tostring(res.text))
eq(CH.charmOf(rf2).mods[1].key, beforeKeys, "reforge keeps the modifier")
eq(player:getItemCount(32309), 2, "shards spent")
res = op("reforge", {ref = refOf(rf2), sid = 32301})
has(res.text, "needs 6 charm shards", "reforge needs shards")

-- drops: online characters get the charm (backpack, else inbox)
local before = countCharms()
local got = 0
local realRandom = math.random
math.random = lcg(42)
for _ = 1, 400 do
	if CH.onSource(player, "rift", {tier = 15}) then
		got = got + 1
	end
end
math.random = realRandom
check(got > 30 and got < 100, "rift tier 15 drops about 15% (" .. got .. ")")
eq(countCharms(), before + got, "every dropped charm reached the character")
eq(CH.onSource({guid = 1, name = "offline"}, "rift", {tier = 15}), nil, "offline characters get nothing")

if failures > 0 then
	error(failures .. " of " .. count .. " charms checks failed")
end
print("charms_test: " .. count .. " checks passed")
